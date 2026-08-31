local _, Quiz = ...
local L = Quiz.L
local MAX_PEERS = 16
local MAX_INTEGER = 9007199254740990
local MAX_TOKEN_BYTES = 64
local MAX_PROMPT_BYTES = 160
local MAX_CHOICE_BYTES = 100
local MAX_EXPLANATION_BYTES = 160
local MAX_LEAGUE_BYTES = 48
local MAX_ERA_BYTES = 64
local MAX_PACK_ID_BYTES = 48
local MAX_PACK_TITLE_BYTES = 64
local MAX_PACK_VERSION = 2147483647
local MAX_ELAPSED_BYTES = 32
local MIN_CHOICES = Quiz.MIN_CHOICES
local MAX_CHOICES = Quiz.MAX_CHOICES
local QUESTION_HEADER_FIELDS = 15
local LETTER_OFFSET = 64
local ANSWER_SECONDS = Quiz.ANSWER_SECONDS
local MAX_FUTURE_EXPIRY = 60
local PREPARE_TIMEOUT = 12
local JOIN_TIMEOUT = 12
local JOIN_RETRY = 3
local HEARTBEAT_INTERVAL = 5
local HOST_TIMEOUT = 18
local PEER_TIMEOUT = 35
local SYNC_INTERVAL = 2
local ANSWER_RETRY = 2
local MAX_ANSWER_ATTEMPTS = 3
local MAX_RETIRED_REQUESTS = 128
local RETIRED_REQUEST_TTL = 120
local MAX_RESULT_RECIPIENTS = 32
local MAX_RESULTS_PER_RECIPIENT = 16
local MAX_RESULTS = 256
local RESULT_TTL = 300
local RESULT_RETRY = 5
local MAX_KNOWN_QUESTIONS = 32
local MILLISECONDS = 1000
local POINT_SCALE = 10
local MAX_SCORE = math.floor(MAX_INTEGER / POINT_SCALE)
local MESSAGE_FIELDS =
    { J = 2, W = 5, S = 3, D = 4, O = 4, A = 6, K = 7, E = 6, R = 19, F = 4, P = 4, H = 5, T = 3, L = 3, X = 2 }
local HOST_STATES = { ready = true, posting = true, open = true, results = true, paused = true }
local ANSWER_ERRORS = { not_open = true, wrong_question = true, invalid_answer = true, late = true, duplicate = true }
local PAUSE_REASONS = { manual = true, restricted = true, error = true }

Quiz.Session = { nonce = 0 }
local Session = Quiz.Session

local function Integer(text, minimum, maximum)
    if type(text) ~= "string" or not text:match("^%-?%d+$") then
        return nil
    end
    local value = tonumber(text)
    if value and value % 1 == 0 and value >= minimum and value <= maximum then
        return value
    end
end

local function Token(text)
    return type(text) == "string" and #text > 0 and #text <= MAX_TOKEN_BYTES and text:match("^[%w.%-]+$") ~= nil
end

local function NewRequest(now)
    Session.nonce = Session.nonce + 1
    return string.format("%.0f.%.0f.%d", GetServerTime(), now * MILLISECONDS, Session.nonce)
end

local function OlderRequest(request, current)
    local a, b, c = request:match("^(%d+)%.(%d+)%.(%d+)$")
    local x, y, z = current:match("^(%d+)%.(%d+)%.(%d+)$")
    if a and x then
        a, b, c, x, y, z = tonumber(a), tonumber(b), tonumber(c), tonumber(x), tonumber(y), tonumber(z)
        return a < x or a == x and (b < y or b == y and c < z)
    end
    return false
end

local function Score(text)
    if type(text) ~= "string" or not (text:match("^%-?%d+$") or text:match("^%-?%d+%.%d$")) then
        return nil
    end
    local value = tonumber(text)
    if value and value >= -MAX_SCORE and value <= MAX_SCORE then
        return value
    end
end

local function ScoreText(value)
    return string.format("%.1f", value)
end

local function Elapsed(text)
    if type(text) ~= "string" or #text > MAX_ELAPSED_BYTES then
        return nil
    end
    if not (text:match("^%d+%.?%d*$") or text:match("^%d+%.?%d*[eE][%+%-]?%d+$")) then
        return nil
    end
    local value = tonumber(text)
    if value and value >= 0 and value <= ANSWER_SECONDS then
        return value
    end
end

local function Plain(text, maximum, empty, allowBraces)
    return type(text) == "string"
        and #text <= maximum
        and (empty or text:find("%S"))
        and not text:find(allowBraces and "[%z\1-\31\127|]" or "[%z\1-\31\127|{}]")
end

local function PackId(text)
    return type(text) == "string"
        and #text > 0
        and #text <= MAX_PACK_ID_BYTES
        and text ~= "all"
        and text:match("^[a-z0-9][a-z0-9_%-]*$") ~= nil
end

local function Fields(...)
    local fields = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        fields[index] = type(value) == "number" and string.format("%.0f", value) or value
    end
    return fields
end

local function PeerTag(name)
    return "round:" .. name:lower()
end

local function AnswerTag(name)
    return "answer:" .. name:lower()
end

local function ResultTag(name, id)
    return "result:" .. name:lower() .. ":" .. string.format("%.0f", id)
end

local function RemoveResult(self, recipient, id)
    Quiz.Comms:Cancel(ResultTag(recipient.name, id))
    recipient.entries[id] = nil
    recipient.count, self.resultCount = recipient.count - 1, self.resultCount - 1
    if recipient.count == 0 then
        self.resultRecipients[recipient.key] = nil
        self.resultRecipientCount = self.resultRecipientCount - 1
    end
end

local function OldestResult(self, recipient)
    local oldest, owner
    for _, candidate in pairs(recipient and { recipient } or self.resultRecipients) do
        for _, entry in pairs(candidate.entries) do
            if
                not oldest
                or entry.expiresAt < oldest.expiresAt
                or entry.expiresAt == oldest.expiresAt and entry.id < oldest.id
            then
                oldest, owner = entry, candidate
            end
        end
    end
    return oldest, owner
end

local function SendRetained(recipient, entry, now)
    local tag = ResultTag(recipient.name, entry.id)
    if now < entry.nextRetryAt or Quiz.Comms:IsTagBusy(tag) then
        return false
    end
    local sent = Quiz.Comms:Send(recipient.name, entry.fields, tag)
    if sent then
        entry.nextRetryAt = now + RESULT_RETRY
    end
    return sent
end

local function Remember(history, id, value)
    if not history.entries[id] then
        local previous = history.slots[history.nextSlot]
        if previous then
            history.entries[previous] = nil
        end
        history.slots[history.nextSlot] = id
        history.nextSlot = history.nextSlot % MAX_KNOWN_QUESTIONS + 1
    end
    history.entries[id] = value
end

local function SameMetadata(question, receipt)
    return question.packId == receipt.packId
        and question.packTitle == receipt.packTitle
        and question.packVersion == receipt.packVersion
        and question.scoringVersion == receipt.scoringVersion
        and question.duration == receipt.duration
        and #question.choices == receipt.choiceCount
end

local function AnswerFields(client, view)
    return Fields("A", client.session, view.id, view.selected, client.answerRevision, client.request)
end

local function RenewMembership(client, view, now)
    client.request = NewRequest(now)
    client.answerRevision, client.ackVersion = 0, -1
    client.ackChoice, client.ackRevision = nil, nil
    client.answerAttempts, client.retryAt = nil, nil
    client.awaitingWelcome = true
    client.lastHeard, client.nextJoin = now, now + JOIN_RETRY
    client.nextHeartbeat, client.nextSyncAt = now + HEARTBEAT_INTERVAL, now + SYNC_INTERVAL
    view.selected, view.confirmedSelected, view.pending, view.locked = nil, nil, false, true
end

local function Choice(input, choices)
    if type(input) == "number" then
        return input % 1 == 0 and input >= 1 and input <= #choices and input or nil
    end
    if type(input) ~= "string" or #input > MAX_CHOICE_BYTES or input:find("[%z\1-\31\127|]") then
        return nil
    end
    local normalized = input:match("^ *(.-) *$"):lower()
    if normalized:match("^[a-f]$") then
        local index = string.byte(normalized:upper()) - LETTER_OFFSET
        return index <= #choices and index or nil
    end
    for index, text in ipairs(choices) do
        if normalized == text:match("^ *(.-) *$"):lower() then
            return index
        end
    end
end

function Session:Initialize()
    self.peers = {}
    self.retiredRequests, self.retiredCount = {}, 0
    self.client = nil
    self.hostSession = nil
    self.resultRecipients, self.resultRecipientCount, self.resultCount = {}, 0, 0
    self.restricted = false
    self.view = { role = "idle", state = "idle", hostName = Quiz.Store:GetSettings().hostName }
end

function Session:RetireRequest(peer, now)
    local key = peer.name:lower() .. ":" .. peer.request
    if not self.retiredRequests[key] and self.retiredCount >= MAX_RETIRED_REQUESTS then
        local oldestKey, oldestExpiry
        for candidate, expiry in pairs(self.retiredRequests) do
            if not oldestExpiry or expiry < oldestExpiry then
                oldestKey, oldestExpiry = candidate, expiry
            end
        end
        self.retiredRequests[oldestKey] = nil
        self.retiredCount = self.retiredCount - 1
    end
    if not self.retiredRequests[key] then
        self.retiredCount = self.retiredCount + 1
    end
    self.retiredRequests[key] = now + RETIRED_REQUEST_TTL
end

function Session:GetView()
    if self.hostSession then
        return Quiz.Main:GetHostView()
    end
    if self.restricted and self.client then
        local view = {}
        for key, value in pairs(self.view) do
            view[key] = value
        end
        view.state, view.notice = "paused", L.NET_RESTRICTED
        return view
    end
    return self.view
end

function Session:StartHost(sessionId)
    local client = self.client
    Quiz.Comms:Clear()
    if client then
        Quiz.Comms:Send(client.name, Fields("L", client.session or "", client.request))
    end
    self.client = nil
    self.hostSession = sessionId
    self.peers = {}
    self.retiredRequests, self.retiredCount = {}, 0
    self.resultRecipients, self.resultRecipientCount, self.resultCount = {}, 0, 0
    self.nextHeartbeat = GetTime() + HEARTBEAT_INTERVAL
    Quiz.Discovery:Advertise()
end

function Session:EndHost()
    Quiz.Discovery:StopHost()
    self:CancelRoundMessages()
    local now = GetTime()
    for _, peer in pairs(self.peers) do
        local recipient = self.resultRecipients[peer.name:lower()]
        if recipient then
            for _, entry in pairs(recipient.entries) do
                if now < entry.expiresAt then
                    entry.nextRetryAt = 0
                    SendRetained(recipient, entry, now)
                end
            end
        end
        Quiz.Comms:Send(peer.name, Fields("X", self.hostSession))
    end
    self.hostSession = nil
    self.peers = {}
    self.resultRecipients, self.resultRecipientCount, self.resultCount = {}, 0, 0
    self.view = { role = "idle", state = "stopped", hostName = Quiz.Store:GetSettings().hostName }
end

function Session:JoinHost(name, advertisedSession)
    if not Quiz.Main.initialized then
        return false, L.HOST_UNAVAILABLE
    end
    if Quiz.Main:IsRestricted() then
        return false, L.NET_RESTRICTED
    end
    if issecretvalue(advertisedSession) or advertisedSession ~= nil and not Token(advertisedSession) then
        return false, "invalid_session"
    end
    local host = Quiz.Comms:NormalizeName(name)
    if not host then
        return false, "invalid_host_name"
    end
    local identified, reason = Quiz.Identity:Initialize()
    if not identified then
        return false, reason
    end
    if host:lower() == Quiz.Identity.name:lower() then
        return false, L.NET_SELF_JOIN
    end
    if self.client and self.client.key == host:lower() and self.view.state ~= "disconnected" then
        local currentSession = self.client.session or self.client.advertisedSession
        if not advertisedSession or advertisedSession == currentSession then
            return true
        end
    end
    local saved, saveError = Quiz.Store:SaveSettings({ hostName = host })
    if not saved then
        return false, saveError
    end
    if self.hostSession then
        Quiz.Main:Stop()
    else
        self:Leave()
    end
    Quiz.Main.notice = nil
    local now = GetTime()
    local request = NewRequest(now)
    self.client = {
        name = host,
        key = host:lower(),
        request = request,
        advertisedSession = advertisedSession,
        awaitingWelcome = true,
        joinedAt = now,
        lastHeard = now,
        nextJoin = now + JOIN_RETRY,
        answerRevision = 0,
        ackVersion = -1,
        questionHistory = { entries = {}, slots = {}, nextSlot = 1 },
        resultHistory = { entries = {}, slots = {}, nextSlot = 1 },
    }
    self.view = { role = "participant", state = "joining", hostName = host }
    local sent, sendError = Quiz.Comms:Send(host, Fields("J", request))
    if not sent then
        self.client = nil
        self.view.state = "disconnected"
        self.view.notice = L.errors[sendError] or L.NET_SEND_FAILED
        return false, self.view.notice
    end
    Quiz.Main:EnsureTicker()
    Quiz.Widget:Show()
    return true
end

function Session:Leave()
    if self.hostSession then
        return false, L.NET_STOP_HOST_FIRST
    end
    local client = self.client
    Quiz.Comms:Clear()
    if client then
        Quiz.Comms:Send(client.name, Fields("L", client.session or "", client.request))
        Quiz.Main:EnsureTicker()
    end
    self.client = nil
    self.view = { role = "idle", state = "idle", hostName = Quiz.Store:GetSettings().hostName }
    Quiz.Widget:Refresh()
    return true
end

function Session:SubmitAnswer(input)
    local view = self:GetView()
    if Quiz.Main:IsRestricted() then
        return false, L.NET_RESTRICTED
    end
    if view.state ~= "open" then
        return false, "not_open"
    end
    if GetTime() >= view.deadline then
        return false, "late"
    end
    local index = Choice(input, view.choices)
    if not index then
        return false, "invalid_answer"
    end
    if view.selected == index then
        return true, "unchanged"
    end
    if self.hostSession then
        return Quiz.Main:AcceptAnswer(Quiz.Identity.name, Quiz.Identity.guid, view.id, index)
    end
    local client = self.client
    local previous, previousRevision, wasPending = view.selected, client.answerRevision, view.pending
    client.answerRevision = client.answerRevision + 1
    view.selected = index
    Quiz.Comms:Cancel("answer")
    local sent, reason = Quiz.Comms:Send(client.name, AnswerFields(client, view), "answer")
    if not sent then
        view.selected, view.pending, client.answerRevision = previous, wasPending, previousRevision
        return false, L.errors[reason] or L.NET_SEND_FAILED
    end
    view.locked, view.pending, view.notice = false, true, nil
    client.answerAttempts, client.retryAt = 1, GetTime() + ANSWER_RETRY
    return true
end

function Session:CancelRoundMessages()
    for _, peer in pairs(self.peers) do
        Quiz.Comms:Cancel(PeerTag(peer.name))
        Quiz.Comms:Cancel(AnswerTag(peer.name))
    end
end

function Session:SendQuestion(peer)
    local game, round = Quiz.Main.game, Quiz.Main.game.round
    return Quiz.Comms:Send(
        peer.name,
        Fields(
            "Q",
            self.hostSession,
            round.id,
            round.cycle,
            round.number,
            game.total,
            Quiz.ANSWER_SECONDS,
            round.prompt,
            #round.choices,
            round.difficulty or "",
            round.era or "",
            round.packId,
            round.packTitle,
            round.packVersion,
            Quiz.Scoring.VERSION,
            unpack(round.choices)
        ),
        PeerTag(peer.name)
    )
end

function Session:SendLock(peer)
    local round = Quiz.Main.game.round
    local answer = round and round.answers[peer.playerKey]
    local now = GetTime()
    local version = peer.answerVersion or 0
    if
        answer
        and (peer.lastLockId ~= round.id or peer.lastLockVersion ~= version or now - peer.lastLockAt >= SYNC_INTERVAL)
    then
        peer.lastLockId, peer.lastLockAt, peer.lastLockVersion = round.id, now, version
        Quiz.Comms:Cancel(AnswerTag(peer.name))
        Quiz.Comms:Send(
            peer.name,
            Fields("K", self.hostSession, round.id, answer.choiceIndex, peer.answerRevision or 0, peer.request, version),
            AnswerTag(peer.name)
        )
    end
end

function Session:SendOpen(peer)
    local round = Quiz.Main.game.round
    local now = GetTime()
    if now < round.deadline and (peer.lastOpenId ~= round.id or now - peer.lastOpenAt >= SYNC_INTERVAL) then
        peer.lastOpenId, peer.lastOpenAt = round.id, now
        Quiz.Comms:Send(peer.name, Fields("O", self.hostSession, round.id, self.serverDeadline), PeerTag(peer.name))
        self:SendLock(peer)
    end
end

function Session:SendResult(peer)
    local game, result = Quiz.Main.game, Quiz.Main.game.lastResult
    local now = GetTime()
    if
        peer.lastResultAckId == result.id
        or peer.lastResultId == result.id and now - peer.lastResultAt < SYNC_INTERVAL
    then
        return
    end
    local key = peer.name:lower()
    local recipient = self.resultRecipients[key]
    local entry = recipient and recipient.entries[result.id]
    if not entry then
        if recipient and recipient.count >= MAX_RESULTS_PER_RECIPIENT then
            local oldest = OldestResult(self, recipient)
            RemoveResult(self, recipient, oldest.id)
        end
        while self.resultCount >= MAX_RESULTS or not recipient and self.resultRecipientCount >= MAX_RESULT_RECIPIENTS do
            local oldest, owner = OldestResult(self)
            RemoveResult(self, owner, oldest.id)
        end
        recipient = self.resultRecipients[key]
        if not recipient then
            recipient = { name = peer.name, key = key, count = 0, entries = {} }
            self.resultRecipients[key] = recipient
            self.resultRecipientCount = self.resultRecipientCount + 1
        end
        local answer = game.round.answers[peer.playerKey]
        local fields = Fields(
            "R",
            self.hostSession,
            result.id,
            result.correctIndex,
            answer and answer.choiceIndex or "",
            answer and ScoreText(answer.points) or "",
            ScoreText(Quiz.Main:GetScore(peer.playerKey)),
            result.correctCount,
            result.totalAnswers,
            result.explanation or "",
            result.packId,
            result.packTitle,
            result.packVersion,
            result.scoringVersion,
            result.duration,
            result.choiceCount,
            answer and string.format("%.17g", answer.elapsed) or "",
            result.fastestName or "",
            result.fastestElapsed and string.format("%.17g", result.fastestElapsed) or ""
        )
        entry = { id = result.id, fields = fields, expiresAt = now + RESULT_TTL, nextRetryAt = 0 }
        recipient.entries[result.id] = entry
        recipient.count, self.resultCount = recipient.count + 1, self.resultCount + 1
    end
    entry.nextRetryAt = 0
    if SendRetained(recipient, entry, now) then
        peer.lastResultId, peer.lastResultAt = result.id, now
    end
end

function Session:RetryResults(now)
    for _, recipient in pairs(self.resultRecipients) do
        local nextEntry
        for id, entry in pairs(recipient.entries) do
            if now >= entry.expiresAt then
                RemoveResult(self, recipient, id)
            elseif now >= entry.nextRetryAt and (not nextEntry or id < nextEntry.id) then
                nextEntry = entry
            end
        end
        if nextEntry and self.peers[recipient.key] and not Quiz.Comms:IsBusy(recipient.name) then
            SendRetained(recipient, nextEntry, now)
        end
    end
end

function Session:Snapshot(peer, now)
    if peer.lastSync and now - peer.lastSync < SYNC_INTERVAL then
        return
    end
    peer.lastSync = now
    if Quiz.Comms:IsBusy(peer.name) then
        return
    end
    peer.lastOpenId, peer.lastLockId, peer.lastResultId = nil, nil, nil
    local game = Quiz.Main.game
    if game.state == "paused" then
        Quiz.Comms:Send(
            peer.name,
            Fields("P", self.hostSession, game.lastQuestionId, Quiz.Main.autoPaused and "restricted" or "manual")
        )
    elseif game.round then
        if peer.readyId ~= game.round.id then
            self:SendQuestion(peer)
        end
        if game.state == "results" then
            self:SendResult(peer)
        elseif game.state == "open" and peer.readyId == game.round.id then
            self:SendOpen(peer)
        end
    end
end

function Session:PrepareRound(now)
    self:CancelRoundMessages()
    self.prepareDeadline = now + PREPARE_TIMEOUT
    for _, peer in pairs(self.peers) do
        peer.readyId = nil
        peer.answerRevision, peer.answerVersion = 0, 0
        self:SendQuestion(peer)
    end
end

function Session:CanOpen(now)
    if now >= self.prepareDeadline then
        return true
    end
    for _, peer in pairs(self.peers) do
        if peer.readyId ~= Quiz.Main.game.round.id then
            return false
        end
    end
    return true
end

function Session:HasRoundPeers(id, now)
    for _, peer in pairs(self.peers) do
        if peer.readyId == id and now < peer.lastSeen + PEER_TIMEOUT then
            return true
        end
    end
    return false
end

function Session:OpenRound()
    self.serverDeadline = GetServerTime() + Quiz.ANSWER_SECONDS
    for _, peer in pairs(self.peers) do
        if peer.readyId == Quiz.Main.game.round.id then
            self:SendOpen(peer)
        end
    end
end

function Session:RevealRound()
    self:CancelRoundMessages()
    local round = Quiz.Main.game.round
    for _, peer in pairs(self.peers) do
        if peer.readyId == round.id or round.answers[peer.playerKey] then
            self:SendResult(peer)
        end
    end
    for playerKey, answer in pairs(round.answers) do
        local key = answer.name:lower()
        if not self.peers[key] and key ~= Quiz.Identity.name:lower() then
            self:SendResult({ name = answer.name, playerKey = playerKey })
        end
    end
end

function Session:Pause(reason)
    self:CancelRoundMessages()
    for _, peer in pairs(self.peers) do
        peer.readyId = nil
        Quiz.Comms:Send(peer.name, Fields("P", self.hostSession, Quiz.Main.game.lastQuestionId, reason))
    end
end

function Session:SetRestricted(restricted)
    if self.restricted == restricted then
        return
    end
    self.restricted = restricted
    Quiz.Comms:Clear()
    if restricted and self.client then
        local view = self.view
        if view.pending then
            view.selected = view.confirmedSelected
        end
        view.pending, view.locked = false, true
        self.client.answerAttempts, self.client.retryAt = nil, nil
    end
    if not restricted then
        local now = GetTime()
        for _, peer in pairs(self.peers) do
            peer.lastSeen = now
        end
        if self.client then
            local client = self.client
            client.lastHeard = now
            if client.session then
                RenewMembership(client, self.view, now)
                self.view.state, self.view.notice = "waiting", L.NET_RESYNC
                Quiz.Comms:Send(client.name, Fields("J", client.request))
            else
                client.joinedAt, client.nextJoin = now, now
            end
        end
    end
end

function Session:OnSendError(target, reason)
    if reason == "addon_lockdown" then
        Quiz.Main.restrictedUntil = GetTime() + SYNC_INTERVAL
        Quiz.Main:SyncRestriction()
        return
    end
    local name = Quiz.Comms:NormalizeName(target)
    if not name then
        return
    end
    local key = name:lower()
    if self.hostSession then
        if reason == "target_offline" then
            self.peers[key] = nil
        end
    elseif self.client and self.client.key == key then
        if reason == "target_offline" then
            Quiz.Comms:Clear()
            self.client = nil
            self.view.state, self.view.notice = "disconnected", L.NET_HOST_OFFLINE
        else
            self.view.notice = L.NET_SEND_FAILED
        end
    end
end

function Session:ReceiveHost(sender, fields, now)
    local code = fields[1]
    local key = sender:lower()
    local peer = self.peers[key]
    if code == "J" then
        if not Token(fields[2]) or key == Quiz.Identity.name:lower() then
            return
        end
        local retiredKey = key .. ":" .. fields[2]
        local retiredUntil = self.retiredRequests[retiredKey]
        if retiredUntil then
            if now < retiredUntil then
                return
            end
            self.retiredRequests[retiredKey] = nil
            self.retiredCount = self.retiredCount - 1
        end
        if peer and peer.request and OlderRequest(fields[2], peer.request) then
            return
        end
        if not peer then
            local count = 0
            for _ in pairs(self.peers) do
                count = count + 1
            end
            if count >= MAX_PEERS then
                return
            end
            peer = { name = sender, playerKey = Quiz.Main:PlayerKey(sender), lastSeen = now }
            self.peers[key] = peer
        end
        if not peer.lastWelcome or now - peer.lastWelcome >= SYNC_INTERVAL then
            if peer.request ~= fields[2] then
                if peer.request then
                    self:RetireRequest(peer, now)
                end
                Quiz.Comms:Cancel(PeerTag(sender))
                Quiz.Comms:Cancel(AnswerTag(sender))
                peer.request, peer.readyId, peer.lastSync = fields[2], nil, nil
                peer.lastOpenId, peer.lastLockId, peer.lastResultId = nil, nil, nil
                peer.lastResultAckId = nil
                peer.answerRevision, peer.answerVersion = 0, 0
            end
            peer.lastWelcome, peer.lastSeen = now, now
            Quiz.Comms:Send(
                sender,
                Fields(
                    "W",
                    fields[2],
                    self.hostSession,
                    Quiz.Main.game.settings.league,
                    ScoreText(Quiz.Main:GetScore(peer.playerKey))
                )
            )
        end
        return
    end
    if code == "L" then
        if Token(fields[3]) and (fields[2] == self.hostSession or fields[2] == "") then
            self:RetireRequest({ name = sender, request = fields[3] }, now)
            if peer and fields[3] == peer.request then
                Quiz.Comms:Cancel(PeerTag(sender))
                Quiz.Comms:Cancel(AnswerTag(sender))
                self.peers[key] = nil
            end
        end
        return
    end
    if not peer then
        return
    end
    if fields[2] ~= self.hostSession then
        return
    end
    local game = Quiz.Main.game
    if
        (code == "T" or code == "S") and fields[3] ~= peer.request
        or code == "D" and fields[4] ~= peer.request
        or code == "F" and fields[4] ~= peer.request
        or code == "A" and fields[6] ~= peer.request
    then
        return
    end
    if code == "T" then
        peer.lastSeen = now
    elseif code == "F" then
        local id = Integer(fields[3], 1, MAX_INTEGER)
        local recipient = self.resultRecipients[key]
        if id and recipient and recipient.entries[id] then
            peer.lastSeen, peer.lastResultAckId = now, math.max(peer.lastResultAckId or 0, id)
            RemoveResult(self, recipient, id)
        end
    elseif code == "S" then
        peer.lastSeen = now
        self:Snapshot(peer, now)
    elseif code == "D" then
        local id = Integer(fields[3], 1, MAX_INTEGER)
        if game.round and id == game.round.id then
            peer.readyId, peer.lastSeen = id, now
            if game.state == "open" then
                self:SendOpen(peer)
            elseif game.state == "results" then
                self:SendResult(peer)
            end
        end
    elseif code == "A" then
        local id = Integer(fields[3], 1, MAX_INTEGER)
        local choice = Integer(fields[4], 1, game.round and #game.round.choices or 0)
        local revision = Integer(fields[5], 1, MAX_INTEGER)
        if not id or not choice or not revision or peer.readyId ~= id then
            return
        end
        peer.lastSeen = now
        if revision <= (peer.answerRevision or 0) then
            self:SendLock(peer)
            return
        end
        local accepted, reason = Quiz.Main:AcceptAnswer(peer.name, nil, id, choice, peer.request .. "." .. fields[5])
        if accepted then
            peer.answerRevision = revision
            peer.answerVersion = (peer.answerVersion or 0) + 1
            self:SendLock(peer)
        elseif ANSWER_ERRORS[reason] and (not peer.lastErrorAt or now - peer.lastErrorAt >= SYNC_INTERVAL) then
            peer.lastErrorAt = now
            Quiz.Comms:Send(sender, Fields("E", self.hostSession, id, reason, revision, peer.request), PeerTag(sender))
        end
    end
end

function Session:ReceiveQuestion(fields, now)
    local id = Integer(fields[3], 1, MAX_INTEGER)
    local cycle = Integer(fields[4], 1, MAX_INTEGER)
    local number = Integer(fields[5], 1, MAX_INTEGER)
    local total = Integer(fields[6], 1, MAX_INTEGER)
    local duration = Integer(fields[7], ANSWER_SECONDS, ANSWER_SECONDS)
    local choiceCount = Integer(fields[9], MIN_CHOICES, MAX_CHOICES)
    local packVersion = Integer(fields[14], 1, MAX_PACK_VERSION)
    local scoringVersion = Integer(fields[15], Quiz.Scoring.VERSION, Quiz.Scoring.VERSION)
    if
        not id
        or not cycle
        or not number
        or not total
        or number > total
        or not duration
        or not Plain(fields[8], MAX_PROMPT_BYTES)
        or not choiceCount
        or #fields ~= QUESTION_HEADER_FIELDS + choiceCount
        or fields[10] ~= "" and not Quiz.DIFFICULTIES[fields[10]]
        or not Plain(fields[11], MAX_ERA_BYTES, true)
        or not PackId(fields[12])
        or not Plain(fields[13], MAX_PACK_TITLE_BYTES)
        or not packVersion
        or not scoringVersion
    then
        return false
    end
    local choices, seen = {}, {}
    for index = 1, choiceCount do
        local choice = fields[QUESTION_HEADER_FIELDS + index]
        if not Plain(choice, MAX_CHOICE_BYTES) then
            return false
        end
        local normalized = choice:match("^ *(.-) *$"):lower()
        if seen[normalized] then
            return false
        end
        choices[index], seen[normalized] = choice, true
    end
    local view = self.view
    if id <= (self.client.voidedThrough or 0) or id < (self.client.latestId or 0) or view.id and id < view.id then
        return false
    end
    self.client.latestId = id
    if view.id ~= id then
        Quiz.Comms:Cancel("answer")
        self.client.answerRevision, self.client.ackVersion = 0, -1
        self.client.ackChoice, self.client.ackRevision = nil, nil
        self.view = {
            role = "participant",
            state = "posting",
            hostName = self.client.name,
            session = self.client.session,
            id = id,
            cycle = cycle,
            number = number,
            total = total,
            duration = duration,
            prompt = fields[8],
            choices = choices,
            difficulty = fields[10] ~= "" and fields[10] or nil,
            era = fields[11] ~= "" and fields[11] or nil,
            packId = fields[12],
            packTitle = fields[13],
            packVersion = packVersion,
            scoringVersion = scoringVersion,
            score = view.score,
        }
        Remember(self.client.questionHistory, id, self.view)
    elseif
        view.prompt ~= fields[8]
        or view.packId ~= fields[12]
        or view.packTitle ~= fields[13]
        or view.packVersion ~= packVersion
        or view.scoringVersion ~= scoringVersion
        or #view.choices ~= choiceCount
    then
        return false
    elseif view.state == "waiting" or view.state == "disconnected" or view.state == "paused" then
        view.state, view.notice = "posting", nil
    end
    Quiz.Comms:Send(self.client.name, Fields("D", self.client.session, id, self.client.request))
    local receipt = self.client.resultHistory.entries[id]
    if receipt then
        self:ReceiveResult(receipt, now)
    end
    return true
end

function Session:ReceiveResult(fields, now)
    local client, view = self.client, self.view
    local id = Integer(fields[3], 1, MAX_INTEGER)
    local choiceCount = Integer(fields[16], MIN_CHOICES, MAX_CHOICES)
    local correct = choiceCount and Integer(fields[4], 1, choiceCount)
    local selected = fields[5] ~= "" and choiceCount and Integer(fields[5], 1, choiceCount) or nil
    local points = fields[6] ~= "" and Score(fields[6]) or nil
    local score = Score(fields[7])
    local count = Integer(fields[8], 0, MAX_INTEGER)
    local total = Integer(fields[9], 0, MAX_INTEGER)
    local packVersion = Integer(fields[13], 1, MAX_PACK_VERSION)
    local scoringVersion = Integer(fields[14], Quiz.Scoring.VERSION, Quiz.Scoring.VERSION)
    local duration = Integer(fields[15], ANSWER_SECONDS, ANSWER_SECONDS)
    local elapsed = fields[17] ~= "" and Elapsed(fields[17]) or nil
    local fastestName = fields[18] ~= "" and Quiz.Comms:NormalizeName(fields[18]) or nil
    local fastestElapsed = fields[19] ~= "" and Elapsed(fields[19]) or nil
    if
        not id
        or not correct
        or not score
        or not count
        or not total
        or count > total
        or not Plain(fields[10], MAX_EXPLANATION_BYTES, true)
        or not PackId(fields[11])
        or not Plain(fields[12], MAX_PACK_TITLE_BYTES)
        or not packVersion
        or not scoringVersion
        or not duration
        or fields[5] ~= "" and not selected
        or fields[6] ~= "" and not points
        or fields[17] ~= "" and not elapsed
        or (selected == nil) ~= (points == nil)
        or (selected == nil) ~= (elapsed == nil)
        or selected and (total == 0 or selected == correct and count == 0 or selected ~= correct and count == total)
        or selected and points ~= Quiz.Scoring.Calculate(selected == correct, elapsed, duration)
        or fields[18] ~= "" and (not fastestName or fastestName ~= fields[18])
        or fields[19] ~= "" and not fastestElapsed
        or (fastestName == nil) ~= (fastestElapsed == nil)
        or fastestName and count == 0
        or fastestElapsed and selected == correct and fastestElapsed > elapsed
    then
        return false
    end
    if
        fastestName
        and fastestName:lower() == Quiz.Identity.name:lower()
        and (selected ~= correct or fastestElapsed ~= elapsed)
    then
        return false
    end
    local previousResult = client.resultHistory.entries[id]
    if
        previousResult
        and (previousResult[18]:lower() ~= fields[18]:lower() or Elapsed(previousResult[19]) ~= fastestElapsed)
    then
        return false
    end
    local receipt = {
        host = client.name,
        session = client.session,
        roundId = id,
        packId = fields[11],
        packTitle = fields[12],
        packVersion = packVersion,
        scoringVersion = scoringVersion,
        duration = duration,
        choiceCount = choiceCount,
        selected = selected,
        correctIndex = correct,
        elapsed = elapsed,
        points = points,
    }
    local question = client.questionHistory.entries[id]
    if question and not SameMetadata(question, receipt) then
        return false
    end
    local recorded, reason = Quiz.PersonalScores:RecordResult(receipt)
    if not recorded then
        view.notice = L.errors[reason] or L.errors.invalid_personal_result
        return false
    end
    Remember(client.resultHistory, id, { unpack(fields) })
    local tag = "result-ack:" .. fields[3]
    Quiz.Comms:Cancel(tag)
    Quiz.Comms:Send(client.name, Fields("F", client.session, id, client.request), tag)
    if
        not client.awaitingWelcome
        and id == view.id
        and id >= (client.latestId or 0)
        and id > (client.voidedThrough or 0)
    then
        Quiz.Comms:Cancel("answer")
        if not view.correctIndex then
            view.suppressScoreAnimation = reason == "duplicate"
            view.suppressWinnerPopup = reason == "duplicate"
        end
        view.state, view.correctIndex, view.selected, view.points, view.score =
            "results", correct, selected, points, score
        view.correctCount, view.totalAnswers, view.explanation = count, total, fields[10]
        view.fastestName, view.fastestElapsed = fastestName, fastestElapsed
        view.pending, view.locked, view.notice = false, true, nil
    end
    client.lastHeard = now
    return true
end

function Session:ReceiveParticipant(fields, now)
    local client, view = self.client, self.view
    local code = fields[1]
    if code == "W" then
        local score = Score(fields[5])
        if
            fields[2] ~= client.request
            or not Token(fields[3])
            or client.advertisedSession and fields[3] ~= client.advertisedSession
            or not Plain(fields[4], MAX_LEAGUE_BYTES, false, true)
            or not score
        then
            return
        end
        if client.session and fields[3] ~= client.session then
            return
        end
        if not client.session then
            client.session = fields[3]
            view.state, view.session, view.score, view.notice = "waiting", client.session, score, nil
            client.nextHeartbeat = now + HEARTBEAT_INTERVAL
        elseif client.awaitingWelcome then
            view.state, view.score, view.notice = "waiting", score, L.NET_RESYNC
        end
        client.awaitingWelcome = false
        client.lastHeard = now
        client.nextSyncAt = now + SYNC_INTERVAL
        Quiz.Comms:Send(client.name, Fields("S", client.session, client.request))
        return
    end
    if not client.session or fields[2] ~= client.session then
        return
    end
    if code == "R" then
        self:ReceiveResult(fields, now)
        return
    end
    if client.awaitingWelcome and code ~= "X" then
        return
    end
    if code == "Q" then
        if not self:ReceiveQuestion(fields, now) then
            return
        end
    elseif code == "X" then
        Quiz.Comms:Clear()
        self.client = nil
        view.state, view.notice, view.pending = "stopped", nil, false
    elseif code == "H" then
        local id = Integer(fields[4], 0, MAX_INTEGER)
        local score = Score(fields[5])
        if
            not HOST_STATES[fields[3]]
            or not id
            or not score
            or id < (client.latestId or 0)
            or view.id and id < view.id
        then
            return
        end
        if id == view.id and view.correctIndex and fields[3] ~= "results" and fields[3] ~= "paused" then
            return
        end
        client.latestId = id
        view.score = score
        if fields[3] == "paused" then
            client.voidedThrough = math.max(client.voidedThrough or 0, id)
            Quiz.Comms:Cancel("answer")
            view.state, view.notice, view.pending = "paused", nil, false
        elseif
            id ~= (view.id or 0)
            or view.state == "disconnected"
            or view.state == "paused"
            or view.state == "waiting"
            or fields[3] == "open" and view.state == "posting"
            or fields[3] == "results" and not view.correctIndex
        then
            if id > (view.id or 0) then
                view.state, view.pending = "waiting", false
                Quiz.Comms:Cancel("answer")
            end
            view.notice = L.NET_RESYNC
            Quiz.Comms:Send(client.name, Fields("S", client.session, client.request))
        end
    elseif code == "P" then
        local id = Integer(fields[3], 0, MAX_INTEGER)
        if not id or not PAUSE_REASONS[fields[4]] or id < (client.latestId or 0) or view.id and id < view.id then
            return
        end
        client.latestId = id
        client.voidedThrough = math.max(client.voidedThrough or 0, id)
        Quiz.Comms:Cancel("answer")
        view.state, view.pending, view.notice = "paused", false, fields[4] == "restricted" and L.NET_RESTRICTED or nil
    else
        local id = Integer(fields[3], 1, MAX_INTEGER)
        if not id or id ~= view.id or id < (client.latestId or 0) or id <= (client.voidedThrough or 0) then
            return
        end
        if code == "O" then
            local expiry = Integer(fields[4], 1, MAX_INTEGER)
            if not expiry or expiry > GetServerTime() + MAX_FUTURE_EXPIRY then
                return
            end
            if view.correctIndex then
                return
            end
            local deadline = now + math.max(0, math.min(view.duration, expiry - GetServerTime()))
            view.deadline = view.deadline and math.min(view.deadline, deadline) or deadline
            view.state, view.notice = now < view.deadline and "open" or "results", nil
            view.locked = view.state ~= "open"
        elseif code == "K" then
            local choice = Integer(fields[4], 1, #view.choices)
            local revision = Integer(fields[5], 0, MAX_INTEGER)
            local version = Integer(fields[7], 0, MAX_INTEGER)
            if
                not choice
                or not revision
                or not version
                or fields[6] ~= client.request
                or view.correctIndex
                or revision > client.answerRevision
                or version < client.ackVersion
            then
                return
            end
            if version == client.ackVersion and (choice ~= client.ackChoice or revision ~= client.ackRevision) then
                return
            end
            client.ackVersion, client.ackChoice, client.ackRevision = version, choice, revision
            view.confirmedSelected = choice
            if revision < client.answerRevision and view.pending then
                return
            end
            Quiz.Comms:Cancel("answer")
            view.selected, view.locked, view.pending, view.notice = choice, false, false, nil
        elseif code == "E" then
            local revision = Integer(fields[5], 1, MAX_INTEGER)
            if
                not ANSWER_ERRORS[fields[4]]
                or view.correctIndex
                or fields[6] ~= client.request
                or revision ~= client.answerRevision
            then
                return
            end
            Quiz.Comms:Cancel("answer")
            view.selected, view.pending, view.notice = view.confirmedSelected, false, L.errors[fields[4]]
        else
            return
        end
    end
    client.lastHeard = now
end

function Session:Receive(sender, fields)
    if self.restricted or Quiz.Main:IsRestricted() then
        return
    end
    local name = Quiz.Comms:NormalizeName(sender)
    if not name or type(fields) ~= "table" then
        return
    end
    local code = fields[1]
    if code == "Q" then
        if #fields < QUESTION_HEADER_FIELDS + MIN_CHOICES or #fields > QUESTION_HEADER_FIELDS + MAX_CHOICES then
            return
        end
    elseif MESSAGE_FIELDS[code] ~= #fields then
        return
    end
    for _, field in ipairs(fields) do
        if type(field) ~= "string" then
            return
        end
    end
    local now = GetTime()
    if self.hostSession then
        self:ReceiveHost(name, fields, now)
    elseif self.client and name:lower() == self.client.key then
        self:ReceiveParticipant(fields, now)
    end
end

function Session:Tick(now)
    if self.restricted then
        return
    end
    if self.hostSession then
        self:RetryResults(now)
        for key, peer in pairs(self.peers) do
            if now - peer.lastSeen >= PEER_TIMEOUT then
                Quiz.Comms:Cancel(PeerTag(peer.name))
                Quiz.Comms:Cancel(AnswerTag(peer.name))
                self.peers[key] = nil
            end
        end
        if now >= self.nextHeartbeat then
            self.nextHeartbeat = now + HEARTBEAT_INTERVAL
            local game = Quiz.Main.game
            for _, peer in pairs(self.peers) do
                if not Quiz.Comms:IsBusy(peer.name) then
                    Quiz.Comms:Send(
                        peer.name,
                        Fields(
                            "H",
                            self.hostSession,
                            game.state,
                            game.lastQuestionId,
                            ScoreText(Quiz.Main:GetScore(peer.playerKey))
                        ),
                        PeerTag(peer.name)
                    )
                end
            end
        end
    elseif self.client then
        local client, view = self.client, self.view
        if not client.session then
            if now - client.joinedAt >= JOIN_TIMEOUT then
                self.client = nil
                view.state, view.notice = "disconnected", L.NET_JOIN_TIMEOUT
                Quiz.Comms:Clear()
            elseif now >= client.nextJoin then
                client.nextJoin = now + JOIN_RETRY
                Quiz.Comms:Send(client.name, Fields("J", client.request))
            end
            return
        end
        if client.awaitingWelcome then
            if now >= client.nextJoin then
                client.nextJoin = now + JOIN_RETRY
                Quiz.Comms:Send(client.name, Fields("J", client.request))
            end
            return
        end
        if now - client.lastHeard >= HOST_TIMEOUT then
            Quiz.Comms:Clear()
            RenewMembership(client, view, now)
            view.state, view.notice = "disconnected", L.NET_HOST_SILENT
            Quiz.Comms:Send(client.name, Fields("J", client.request))
            return
        elseif view.state == "open" and now >= view.deadline then
            view.state = "results"
        end
        if view.pending and view.state == "open" and now >= client.retryAt then
            if client.answerAttempts < MAX_ANSWER_ATTEMPTS then
                client.answerAttempts, client.retryAt = client.answerAttempts + 1, now + ANSWER_RETRY
                Quiz.Comms:Send(client.name, AnswerFields(client, view), "answer")
            else
                view.notice = L.NET_ANSWER_UNCONFIRMED
            end
        end
        if
            (view.state == "waiting" or view.state == "posting" or view.state == "results" and not view.correctIndex)
            and now >= (client.nextSyncAt or 0)
        then
            client.nextSyncAt = now + SYNC_INTERVAL
            Quiz.Comms:Send(client.name, Fields("S", client.session, client.request))
        end
        if now >= client.nextHeartbeat then
            client.nextHeartbeat = now + HEARTBEAT_INTERVAL
            if view.state == "disconnected" then
                Quiz.Comms:Send(client.name, Fields("J", client.request))
            else
                Quiz.Comms:Send(client.name, Fields("T", client.session, client.request))
            end
        end
    end
end

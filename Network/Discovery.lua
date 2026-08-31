local _, Quiz = ...
local PREFIX = "ORBITQUIZDISC8"
local WIRE_VERSION = "8"
local LOBBY_NAME = "OrbitQuizLobby"
local MAX_PACKET_BYTES = 255
local MAX_SESSION_BYTES = 64
local MAX_PACK_BYTES = 64
local MAX_LEAGUE_BYTES = 48
local MAX_HOSTS = 32
local MAX_PLAYERS = 17
local MAX_QUEUE = 32
local MAX_CHANNEL_ID = 2147483647
local MAX_JOIN_ATTEMPTS = 3
local MAX_SEND_ATTEMPTS = 3
local JOIN_DELAY = 2
local JOIN_INTERVAL = 30
local QUERY_INTERVAL = 5
local ADVERTISE_INTERVAL = 15
local ENTRY_TTL = 45
local RETIRED_TTL = 90
local QUEUE_TTL = 12
local PROBE_TTL = 12
local SEND_INTERVAL = 1
local TICK_INTERVAL = 1
local RETRY_INTERVAL = 2
local HOST_STATES = { ready = true, posting = true, open = true, results = true, paused = true }

Quiz.Discovery = { initialized = false, started = false }
local Discovery = Quiz.Discovery

local function IsBlocked()
    return Quiz.Comms.suspended or Quiz.Main:IsRestricted()
end

local function Plain(value, maximum, allowBraces)
    return not issecretvalue(value)
        and type(value) == "string"
        and #value > 0
        and #value <= maximum
        and value:find("%S") ~= nil
        and not value:find(allowBraces and "[%z\1-\31\127|]" or "[%z\1-\31\127|{}]")
end

local function Token(value)
    return Plain(value, MAX_SESSION_BYTES) and value:match("^[%w.%-]+$") ~= nil
end

local function ClearQueue(self)
    self.queue, self.queueCount = {}, 0
end

local function Prune(self, now)
    for name, entry in pairs(self.games) do
        if now >= entry.expiresAt then
            self.games[name] = nil
            self.gameCount = self.gameCount - 1
        end
    end
    for name, entry in pairs(self.probes) do
        if now >= entry.expiresAt then
            self.probes[name] = nil
            self.probeCount = self.probeCount - 1
        end
    end
    for name, entry in pairs(self.retired) do
        if now >= entry.expiresAt then
            self.retired[name] = nil
            self.retiredCount = self.retiredCount - 1
        end
    end
    for name, expiresAt in pairs(self.responders) do
        if now >= expiresAt then
            self.responders[name] = nil
            self.responderCount = self.responderCount - 1
        end
    end
    for key, entry in pairs(self.queue) do
        if now >= entry.expiresAt then
            self.queue[key] = nil
            self.queueCount = self.queueCount - 1
        end
    end
end

local function Retire(self, name, session, now)
    if not self.retired[name] and self.retiredCount >= MAX_HOSTS then
        local oldestName, oldestExpiry
        for candidate, entry in pairs(self.retired) do
            if not oldestExpiry or entry.expiresAt < oldestExpiry then
                oldestName, oldestExpiry = candidate, entry.expiresAt
            end
        end
        self.retired[oldestName] = nil
        self.retiredCount = self.retiredCount - 1
    end
    if not self.retired[name] then
        self.retiredCount = self.retiredCount + 1
    end
    self.retired[name] = { session = session, expiresAt = now + RETIRED_TTL }
end

local function Lobby(self)
    local info = C_ChatInfo.GetChannelInfoFromIdentifier(LOBBY_NAME)
    if issecretvalue(info) then
        self.lobbyReason = "discovery_invalid_channel"
        return nil
    end
    if info == nil then
        self.lobbyReason = "discovery_not_joined"
        return nil
    end
    if
        type(info) ~= "table"
        or issecretvalue(info.name)
        or issecretvalue(info.localID)
        or issecretvalue(info.channelType)
        or type(info.name) ~= "string"
        or type(info.localID) ~= "number"
        or info.channelType ~= Enum.PermanentChatChannelType.Custom
        or info.name:lower() ~= LOBBY_NAME:lower()
        or info.localID < 1
        or info.localID > MAX_CHANNEL_ID
        or info.localID % 1 ~= 0
    then
        self.lobbyReason = "discovery_invalid_channel"
        return nil
    end
    self.lobbyReason = nil
    return info.localID
end

local function HasRoute(self, distribution)
    if distribution == "CHANNEL" then
        return Lobby(self) ~= nil
    elseif distribution == "GUILD" then
        return IsInGuild()
    elseif distribution == "PARTY" then
        return IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid(LE_PARTY_CATEGORY_HOME)
    elseif distribution == "RAID" then
        return IsInRaid(LE_PARTY_CATEGORY_HOME)
    elseif distribution == "INSTANCE_CHAT" then
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    return false
end

local function Enqueue(self, message, distribution, target, kind, now)
    local key = kind .. ":" .. distribution .. ":" .. (target or "")
    local previous = self.queue[key]
    if not previous and self.queueCount >= MAX_QUEUE then
        return false, "discovery_full"
    end
    self.sequence = self.sequence + 1
    self.queue[key] = {
        message = message,
        distribution = distribution,
        target = target,
        kind = kind,
        sequence = previous and previous.sequence or self.sequence,
        attempts = 0,
        expiresAt = now + QUEUE_TTL,
    }
    if not previous then
        self.queueCount = self.queueCount + 1
    end
    return true
end

local function Broadcast(self, message, kind, now)
    local routed = false
    for _, distribution in ipairs({ "CHANNEL", "GUILD", "RAID", "PARTY", "INSTANCE_CHAT" }) do
        if HasRoute(self, distribution) then
            routed = Enqueue(self, message, distribution, nil, kind, now) or routed
        end
    end
    return routed
end

local function HostedGame(self)
    local session, game = Quiz.Session.hostSession, Quiz.Main.game
    local state = game and (game.state == "finished" and Quiz.Main.finishPending and "results" or game.state)
    if not session or session == self.withdrawnSession or not game or not HOST_STATES[state] then
        return nil
    end
    local packName = Quiz.L.ALL_PACKS
    if game.settings.packId ~= "all" then
        packName = game.settings.packId
        for _, pack in ipairs(Quiz:GetQuestionPacks()) do
            if pack.id == game.settings.packId then
                packName = pack.title
                break
            end
        end
    end
    local players = 1
    for _ in pairs(Quiz.Session.peers) do
        players = players + 1
    end
    if
        not Token(session)
        or not Plain(packName, MAX_PACK_BYTES)
        or not Plain(game.settings.league, MAX_LEAGUE_BYTES, true)
        or players > MAX_PLAYERS
    then
        self.lastError = "discovery_invalid_game"
        return nil
    end
    return table.concat({ WIRE_VERSION, "A", session, packName, game.settings.league, state, players }, "|"), session
end

local function SendNext(self, now)
    if now < self.nextSendAt then
        return
    end
    local chosenKey, chosen
    for key, entry in pairs(self.queue) do
        if not chosen or entry.sequence < chosen.sequence then
            chosenKey, chosen = key, entry
        end
    end
    if not chosen then
        return
    end
    local target = chosen.target
    local available = chosen.distribution == "WHISPER" or HasRoute(self, chosen.distribution)
    if available and chosen.distribution == "CHANNEL" then
        local localID = Lobby(self)
        available = localID ~= nil
        target = localID and tostring(localID) or nil
    end
    if not available then
        self.queue[chosenKey] = nil
        self.queueCount = self.queueCount - 1
        return
    end
    self.nextSendAt = now + SEND_INTERVAL
    local result = C_ChatInfo.SendAddonMessage(PREFIX, chosen.message, chosen.distribution, target)
    if IsBlocked() then
        ClearQueue(self)
        return
    end
    if not issecretvalue(result) and result == Enum.SendAddonMessageResult.AddonMessageThrottle then
        chosen.attempts = chosen.attempts + 1
        if chosen.attempts < MAX_SEND_ATTEMPTS then
            self.nextSendAt = now + RETRY_INTERVAL
            return
        end
        self.lastError = "discovery_send_failed"
    elseif
        not issecretvalue(result)
        and (result == Enum.SendAddonMessageResult.Success or result == Enum.SendAddonMessageResult.ChannelThrottle)
    then
        self.lastError = nil
    else
        self.lastError = "discovery_send_failed"
    end
    if self.queue[chosenKey] == chosen then
        self.queue[chosenKey] = nil
        self.queueCount = self.queueCount - 1
    end
end

function Discovery:Initialize()
    self.started, self.initialized = false, false
    self.games, self.gameCount = {}, 0
    self.probes, self.probeCount = {}, 0
    self.retired, self.retiredCount = {}, 0
    self.responders, self.responderCount = {}, 0
    self.sequence, self.joinAttempts = 0, 0
    self.lastHostedSession, self.withdrawnSession = nil, nil
    self.lastAdvertAt, self.lastQueryAt = nil, nil
    self.pendingAdvert, self.queryAt, self.wasBlocked = false, nil, false
    self.lastError, self.lobbyReason, self.localName, self.lobbyConfirmed = nil, nil, nil, false
    self.nextSendAt, self.nextAdvertAt, self.nextJoinAt, self.nextTickAt = 0, 0, 0, 0
    ClearQueue(self)
    local result = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    if
        issecretvalue(result)
        or (
            result ~= Enum.RegisterAddonMessagePrefixResult.Success
            and result ~= Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix
        )
    then
        self.lastError = "discovery_prefix_failed"
        return false, self.lastError
    end
    self.initialized = true
    return true
end

function Discovery:Start()
    if not self.initialized then
        return false, "discovery_not_ready"
    end
    if self.started then
        return true
    end
    local name, realm = UnitFullName("player")
    if not issecretvalue(name) and not issecretvalue(realm) and type(name) == "string" then
        self.localName =
            Quiz.Identity:NormalizeName(type(realm) == "string" and realm ~= "" and name .. "-" .. realm or name)
    end
    self.started = true
    self.nextJoinAt = GetTime() + JOIN_DELAY
    self.queryAt = self.nextJoinAt + SEND_INTERVAL
    return true
end

function Discovery:Refresh()
    if not self.started then
        return false, "discovery_not_ready"
    elseif IsBlocked() then
        return false, "discovery_restricted"
    end
    local now = GetTime()
    if self.lastQueryAt and now < self.lastQueryAt + QUERY_INTERVAL then
        return false, "discovery_throttled"
    end
    self.lastQueryAt = now
    self.queryAt = now
    self.joinAttempts = 0
    return true
end

function Discovery:Probe(hostName)
    if not self.started then
        return false, "discovery_not_ready"
    elseif IsBlocked() then
        return false, "discovery_restricted"
    end
    local name = Quiz.Identity:NormalizeName(hostName)
    if not name or self.localName and name:lower() == self.localName:lower() then
        return false, "invalid_host_name"
    end
    local now, key = GetTime(), name:lower()
    Prune(self, now)
    local previous = self.probes[key]
    if previous and now < previous.requestedAt + QUERY_INTERVAL then
        return false, "discovery_throttled"
    elseif not previous and self.probeCount >= MAX_HOSTS then
        return false, "discovery_full"
    end
    local queued, reason = Enqueue(self, WIRE_VERSION .. "|Q", "WHISPER", name, "probe", now)
    if not queued then
        return false, reason
    end
    if not previous then
        self.probeCount = self.probeCount + 1
    end
    self.probes[key] = { requestedAt = now, expiresAt = now + PROBE_TTL }
    return true
end

function Discovery:Advertise()
    if not self.started then
        return false, "discovery_not_ready"
    end
    self.pendingAdvert = true
    self.nextAdvertAt = math.max(GetTime(), (self.lastAdvertAt or -QUERY_INTERVAL) + QUERY_INTERVAL)
    return true
end

function Discovery:StopHost()
    local session = self.lastHostedSession or Quiz.Session.hostSession
    self.pendingAdvert, self.lastHostedSession = false, nil
    self.withdrawnSession = session
    for key, entry in pairs(self.queue) do
        if entry.kind == "advert" or entry.kind == "reply" then
            self.queue[key] = nil
            self.queueCount = self.queueCount - 1
        end
    end
    if self.started and session and not IsBlocked() then
        Broadcast(self, WIRE_VERSION .. "|X|" .. session, "withdraw", GetTime())
    end
end

function Discovery:Stop()
    self:StopHost()
    self.started = false
    ClearQueue(self)
end

function Discovery:GetGames()
    if not self.initialized then
        return {}
    end
    Prune(self, GetTime())
    local games = {}
    for _, entry in pairs(self.games) do
        local row = {}
        for key, value in pairs(entry) do
            row[key] = value
        end
        games[#games + 1] = row
    end
    table.sort(games, function(first, second)
        return first.hostName:lower() < second.hostName:lower()
    end)
    return games
end

function Discovery:Receive(prefix, text, distribution, sender, target, _, localID, channelName)
    if not self.started or IsBlocked() then
        return false
    end
    if
        issecretvalue(prefix)
        or issecretvalue(text)
        or issecretvalue(distribution)
        or issecretvalue(sender)
        or prefix ~= PREFIX
        or type(text) ~= "string"
        or #text > MAX_PACKET_BYTES
        or text:find("[%z\1-\31\127]")
        or type(distribution) ~= "string"
    then
        return false
    end
    local name = Quiz.Identity:NormalizeName(sender)
    if not name then
        return false
    end
    if distribution == "CHANNEL" then
        if
            issecretvalue(localID)
            or issecretvalue(channelName)
            or type(localID) ~= "number"
            or type(channelName) ~= "string"
            or channelName:lower() ~= LOBBY_NAME:lower()
            or localID ~= Lobby(self)
        then
            return false
        end
    elseif distribution == "WHISPER" then
        local recipient = Quiz.Identity:NormalizeName(target)
        if not recipient or not self.localName or recipient:lower() ~= self.localName:lower() then
            return false
        end
    elseif not HasRoute(self, distribution) then
        return false
    end
    if self.localName and name:lower() == self.localName:lower() then
        self.lobbyConfirmed = self.lobbyConfirmed or distribution == "CHANNEL"
        return true
    end
    local now, key = GetTime(), name:lower()
    Prune(self, now)
    if text == WIRE_VERSION .. "|Q" then
        local advert = HostedGame(self)
        if not advert then
            return true
        end
        if distribution ~= "WHISPER" then
            self:Advertise()
        elseif not self.responders[key] and self.responderCount < MAX_HOSTS then
            if Enqueue(self, advert, "WHISPER", name, "reply", now) then
                self.responders[key] = now + QUERY_INTERVAL
                self.responderCount = self.responderCount + 1
            end
        end
        return true
    elseif distribution == "WHISPER" and not self.probes[key] then
        return false
    end
    local stopped = text:match("^" .. WIRE_VERSION .. "|X|([%w.%-]+)$")
    local previous = self.games[key]
    if stopped and Token(stopped) then
        if previous and previous.session == stopped then
            self.games[key] = nil
            self.gameCount = self.gameCount - 1
            Retire(self, key, stopped, now)
        end
        return true
    end
    local session, packName, league, state, playerText =
        text:match("^" .. WIRE_VERSION .. "|A|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if
        not Token(session)
        or not Plain(packName, MAX_PACK_BYTES)
        or not Plain(league, MAX_LEAGUE_BYTES, true)
        or not HOST_STATES[state]
        or not playerText:match("^%d%d?$")
    then
        return false
    end
    local players = tonumber(playerText)
    if players < 1 or players > MAX_PLAYERS or self.retired[key] and self.retired[key].session == session then
        return false
    end
    if not previous and self.gameCount >= MAX_HOSTS then
        return false
    end
    if previous and previous.session ~= session then
        Retire(self, key, previous.session, now)
    elseif not previous then
        self.gameCount = self.gameCount + 1
    end
    self.games[key] = {
        hostName = name,
        session = session,
        packName = packName,
        league = league,
        state = state,
        players = players,
        expiresAt = now + ENTRY_TTL,
    }
    return true
end

function Discovery:Tick(now)
    if not self.started or now < self.nextTickAt then
        return
    end
    self.nextTickAt = now + TICK_INTERVAL
    Prune(self, now)
    if IsBlocked() then
        ClearQueue(self)
        self.wasBlocked = true
        return
    elseif self.wasBlocked then
        self.wasBlocked = false
        self:Refresh()
        self:Advertise()
    end
    local lobby = Lobby(self)
    if not lobby and self.lobbyReason == "discovery_not_joined" and now >= self.nextJoinAt then
        if type(JoinChannelByName) ~= "function" then
            self.lobbyReason = "discovery_lobby_unavailable"
        elseif self.joinAttempts < MAX_JOIN_ATTEMPTS then
            self.joinAttempts = self.joinAttempts + 1
            self.nextJoinAt = now + JOIN_INTERVAL
            JoinChannelByName(LOBBY_NAME)
            self.queryAt = now + SEND_INTERVAL
        end
    end
    if self.queryAt and now >= self.queryAt then
        self.queryAt = nil
        self.lastQueryAt = now
        Broadcast(self, WIRE_VERSION .. "|Q", "query", now)
    end
    local advert, session = HostedGame(self)
    if advert and (self.pendingAdvert or session ~= self.lastHostedSession or now >= self.nextAdvertAt) then
        if not self.lastAdvertAt or now >= self.lastAdvertAt + QUERY_INTERVAL then
            Broadcast(self, advert, "advert", now)
            self.pendingAdvert = false
            self.lastHostedSession = session
            self.lastAdvertAt = now
            self.nextAdvertAt = now + ADVERTISE_INTERVAL
        end
    elseif not advert and self.lastHostedSession then
        self:StopHost()
    end
    SendNext(self, now)
end

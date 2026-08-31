local _, Quiz = ...
local L = Quiz.L
local TICK_INTERVAL = 0.1
local MAX_IDENTITY_LENGTH = 128

Quiz.Main = { autoPaused = false }
local Main = Quiz.Main

local function RefreshMediaConsumers()
    if not Main.initialized then
        return
    end
    Quiz.Widget:ApplySettings()
    if Quiz.UI.frame then
        Quiz.UI:RefreshWidgetSettings()
    end
end

local function ErrorText(reason)
    return L.errors[reason] or reason
end

function Main:Report(reason)
    self.notice = ErrorText(reason)
    Quiz:Print(self.notice)
    Quiz.UI:Refresh()
    Quiz.Widget:Refresh()
    return false, self.notice
end

function Main:IsRunning()
    return self.game ~= nil
        and self.game.state ~= "stopped"
        and (self.game.state ~= "finished" or self.finishPending == true)
end

function Main:IsRestricted()
    return self.restrictionActive
        or self.chatDisconnected
        or self.restrictedUntil and GetTime() < self.restrictedUntil
        or C_ChatInfo.InChatMessagingLockdown()
end

function Main:SyncRestriction()
    local restricted = not not self:IsRestricted()
    local wasRestricted = Quiz.Comms.suspended
    Quiz.Comms.suspended = restricted
    Quiz.Session:SetRestricted(restricted)
    if not restricted and wasRestricted and self.finishPending and self.nextAutoAt then
        self.nextAutoAt = GetTime() + self.game.rules.revealSeconds
    end
    if restricted and self:IsRunning() and self.game.state ~= "paused" and self.game.state ~= "finished" then
        self:Pause(self.chatDisconnected and L.NET_CHAT_DISCONNECTED or L.NET_RESTRICTED, true)
    elseif not restricted and self.autoPaused and self:IsRunning() then
        self:Resume()
    end
end

function Main:EnsureTicker()
    if self.ticker then
        return
    end
    self.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
        local ok, failure = pcall(self.Tick, self)
        if not ok then
            self:CancelTicker()
            Quiz.Comms:Clear()
            self.autoPaused, self.nextAutoAt, self.notice = false, nil, L.INTERNAL_ERROR
            if self:IsRunning() then
                self.game:Pause(L.INTERNAL_ERROR)
            end
            geterrorhandler()(failure)
        end
    end)
end

function Main:CancelTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Main:SaveSettings(settings, silent)
    if self:IsRunning() then
        return self:Report(L.SETTINGS_LOCKED)
    end
    local ok, reason = Quiz.Store:SaveSettings(settings)
    if not ok then
        return self:Report(reason)
    end
    if Quiz.UI.frame then
        Quiz.UI:LoadSettings()
    end
    if not silent then
        self.notice = L.SETTINGS_SAVED
        Quiz:Print(self.notice)
        Quiz.UI:Refresh()
    end
    return true
end

function Main:PlayerKey(name, trustedGUID)
    local fullName = Quiz.Identity:NormalizeName(name)
    if not fullName then
        return nil
    end
    local normalized = fullName:lower()
    if not self.identityByName[normalized] then
        local guid = type(trustedGUID) == "string"
                and #trustedGUID > 0
                and #trustedGUID <= MAX_IDENTITY_LENGTH
                and not trustedGUID:find("[%c|]")
                and trustedGUID
            or nil
        self.identityByName[normalized] = guid or "name:" .. normalized
    end
    return self.identityByName[normalized]
end

function Main:GetScore(playerKey)
    local player = self.game and self.game.players[playerKey]
    return player and player.score or 0
end

function Main:Start(settings)
    if not self.initialized then
        return self:Report(self.initializationError or L.HOST_UNAVAILABLE)
    end
    if self:IsRunning() then
        return self:Report(L.ALREADY_RUNNING)
    end
    if not self:SaveSettings(settings or Quiz.Store:GetSettings(), true) then
        return false
    end
    local configured = Quiz.Store:GetSettings()
    local rules, rulesError = Quiz:GetPackRules(configured.packId)
    if not rules then
        return self:Report(rulesError)
    end
    local identified, identityError = Quiz.Identity:Initialize()
    if not identified then
        return self:Report(identityError)
    end
    local questions, packError = Quiz:GetQuestions(configured.packId)
    if not questions then
        return self:Report(packError)
    end
    local game, gameError = Quiz.Game.New(configured, questions, math.random, rules)
    if not game then
        return self:Report(gameError)
    end
    local sessionCounter, counterError = Quiz.Store:NextQuestionId()
    if not sessionCounter then
        return self:Report(counterError)
    end
    self.game = game
    self.identityByName = {}
    self.identityByName[Quiz.Identity.name:lower()] = Quiz.Identity.guid
    self.notice, self.nextAutoAt, self.autoPaused, self.finishPending = nil, nil, false, false
    Quiz.Session:StartHost(string.format("%.0f.%.0f", GetServerTime(), sessionCounter))
    self:EnsureTicker()
    self:SyncRestriction()
    Quiz.Widget:Show()
    if game.state ~= "paused" then
        return self:NextQuestion()
    end
    return true
end

function Main:NextQuestion()
    local game = self.game
    if not game then
        return self:Report(L.NO_GAME)
    end
    if game.state ~= "ready" and game.state ~= "results" then
        return false, "not_ready"
    end
    local id, idError = Quiz.Store:NextQuestionId()
    if not id then
        self:Pause(idError, false)
        return false, idError
    end
    local round, reason = game:PrepareQuestion(id)
    if not round then
        if game.state == "finished" then
            self:Finish()
            Quiz.UI:Refresh()
            Quiz.Widget:Refresh()
            return true
        end
        self:Pause(reason, false)
        return false, reason
    end
    self.nextAutoAt, self.notice = nil, nil
    local now = GetTime()
    Quiz.Session:PrepareRound(now)
    self:TryOpenQuestion(now)
    self:EnsureTicker()
    Quiz.UI:Refresh()
    Quiz.Widget:Refresh()
    return true
end

function Main:TryOpenQuestion(now)
    if self.game and self.game.state == "posting" and not self:IsRestricted() and Quiz.Session:CanOpen(now) then
        self.game:OpenQuestion(now)
        Quiz.Session:OpenRound()
    end
end

function Main:AcceptAnswer(name, trustedGUID, id, choice, actionId)
    if self:IsRestricted() then
        self:SyncRestriction()
        return false, "not_open"
    end
    if not self.game or self.game.state ~= "open" then
        return false, "not_open"
    end
    local now = GetTime()
    if now >= self.game.round.deadline then
        return false, "late"
    end
    local key = self:PlayerKey(name, trustedGUID)
    if not key then
        return false, "invalid_answer"
    end
    local accepted, reason = self.game:Submit(key, Quiz.Identity:NormalizeName(name), id, choice, now, actionId)
    if accepted then
        Quiz.UI:Refresh()
        Quiz.Widget:Refresh()
    end
    return accepted, reason
end

function Main:GetHostView()
    local game = self.game
    local view = {
        role = "host",
        hostName = Quiz.Identity.name,
        state = game.state == "finished" and self.finishPending and "results" or game.state,
        session = Quiz.Session.hostSession,
        score = self:GetScore(Quiz.Identity.guid),
        notice = game.state == "paused" and self.notice or nil,
    }
    local round = game.round
    if round then
        view.id, view.cycle, view.number, view.total = round.id, round.cycle, round.number, game.total
        view.prompt, view.choices = round.prompt, round.choices
        view.packId, view.packTitle, view.packVersion = round.packId, round.packTitle, round.packVersion
        view.scoringVersion, view.rulesKey, view.rules = Quiz.Scoring.VERSION, game.rulesKey, game.rules
        view.difficulty, view.era = round.difficulty, round.era
        view.duration, view.deadline = game.rules.answerSeconds, round.deadline
        local answer = round.answers[Quiz.Identity.guid]
        view.selected = answer and answer.choiceIndex or nil
        view.locked = game.state ~= "open" or answer ~= nil and not game.rules.allowAnswerChanges
        if view.state == "results" then
            view.correctIndex, view.points = round.correctIndex, answer and answer.points or nil
            view.correctCount, view.totalAnswers = game.lastResult.correctCount, game.lastResult.totalAnswers
            view.explanation = game.lastResult.explanation
            view.fastestName, view.fastestElapsed = game.lastResult.fastestName, game.lastResult.fastestElapsed
            view.streak, view.streakBonus = answer and answer.streak or 0, answer and answer.streakBonus or 0
            view.streakMilestones = game.lastResult.streakMilestones
        end
    end
    return view
end

function Main:CloseQuestion(now)
    local game = self.game
    local multiplayer = game.round and Quiz.Session:HasRoundPeers(game.round.id, now) or false
    local result = game:CloseQuestion(now, multiplayer)
    if not result then
        return
    end
    self.finishPending = result.complete == true
    local answer = game.round.answers[Quiz.Identity.guid]
    local saved, reason = Quiz.PersonalScores:RecordResult({
        host = Quiz.Identity.name,
        session = Quiz.Session.hostSession,
        roundId = result.id,
        packId = result.packId,
        packTitle = result.packTitle,
        packVersion = result.packVersion,
        scoringVersion = result.scoringVersion,
        duration = result.duration,
        choiceCount = result.choiceCount,
        selected = answer and answer.choiceIndex or nil,
        correctIndex = result.correctIndex,
        elapsed = answer and answer.elapsed or nil,
        points = answer and answer.points or nil,
        rulesKey = result.rulesKey,
        streak = answer and answer.streak or 0,
        streakBonus = answer and answer.streakBonus or 0,
    })
    Quiz.Session:RevealRound()
    if not saved then
        if self.finishPending then
            self.nextAutoAt = nil
            self:Report(reason)
        else
            self:Pause(reason, false)
        end
        return
    end
    self.nextAutoAt = now + game.rules.revealSeconds
end

function Main:Finish()
    self.nextAutoAt, self.finishPending, self.autoPaused = nil, false, false
    Quiz.Session:EndHost()
    self.notice = L.STATUS_FINISHED
    Quiz:Print(self.notice)
end

function Main:Pause(reason, automatic)
    if not self:IsRunning() then
        return self:Report(L.NO_GAME)
    end
    if self.game.state == "finished" then
        return false, L.STATUS_FINISHED
    end
    self.autoPaused = automatic == true
    self.game:Pause(reason or L.STATUS_PAUSED)
    self.nextAutoAt = nil
    self.notice = ErrorText(reason or L.STATUS_PAUSED)
    Quiz.Session:Pause(automatic and "restricted" or "manual")
    self:EnsureTicker()
    Quiz:Print(self.notice)
    Quiz.UI:Refresh()
    Quiz.Widget:Refresh()
    return true
end

function Main:Resume()
    if not self:IsRunning() then
        return self:Report(L.NO_GAME)
    end
    if self:IsRestricted() then
        return self:Report(L.NET_RESTRICTED)
    end
    local ok, reason = self.game:Resume()
    if not ok then
        return self:Report(reason)
    end
    self.autoPaused, self.notice = false, nil
    if self.game.state == "finished" then
        self:Finish()
        Quiz.UI:Refresh()
        Quiz.Widget:Refresh()
        return true
    end
    return self:NextQuestion()
end

function Main:Stop()
    if self.game then
        self.game:Stop()
    end
    if Quiz.Session.hostSession then
        Quiz.Session:EndHost()
    elseif Quiz.Session.client then
        Quiz.Session:Leave()
    end
    self.nextAutoAt, self.autoPaused, self.finishPending = nil, false, false
    self.notice = L.STATUS_STOPPED
    Quiz.Comms:Tick(GetTime())
    if Quiz.Comms:IsBusy() or Quiz.Discovery.started then
        self:EnsureTicker()
    else
        self:CancelTicker()
    end
    Quiz:Print(self.notice)
    Quiz.UI:Refresh()
    Quiz.Widget:Refresh()
    return true
end

function Main:Tick()
    local now = GetTime()
    self:SyncRestriction()
    Quiz.Session:Tick(now)
    local game = self.game
    if self:IsRunning() and not self:IsRestricted() then
        if game.state == "posting" then
            self:TryOpenQuestion(now)
        elseif game.state == "open" and now >= game.round.deadline then
            self:CloseQuestion(now)
        elseif game.state == "results" and self.nextAutoAt and now >= self.nextAutoAt then
            self:NextQuestion()
        elseif game.state == "finished" and self.nextAutoAt and now >= self.nextAutoAt then
            self:Finish()
        end
    end
    Quiz.Comms:Tick(now)
    Quiz.Discovery:Tick(now)
    Quiz.UI:Refresh()
    Quiz.Widget:Refresh()
    if not Quiz.Discovery.started and not self:IsRunning() and not Quiz.Session.client and not Quiz.Comms:IsBusy() then
        self:CancelTicker()
    end
end

function Main:Status()
    local view = Quiz.Session:GetView()
    Quiz:Print(L.NET_STATUS_F:format(view.role, view.hostName or "", view.state))
    if self.notice then
        Quiz:Print(self.notice)
    end
end

function Main:Command(message)
    if not self.initialized then
        return self:Report(self.initializationError or L.HOST_UNAVAILABLE)
    end
    local command, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "widget" or command == "host" or command == "setup" then
        Quiz.UI:Toggle()
    elseif command == "join" then
        local joined, reason = Quiz.Session:JoinHost(rest)
        if not joined then
            self:Report(reason)
        end
    elseif command == "leave" then
        local left, reason = Quiz.Session:Leave()
        if not left then
            self:Report(reason)
        end
        Quiz.Widget:Refresh()
    elseif command == "start" then
        self:Start()
    elseif command == "pause" then
        self:Pause(nil, false)
    elseif command == "resume" then
        self:Resume()
    elseif command == "stop" then
        self:Stop()
    elseif command == "status" then
        self:Status()
    elseif command == "packs" then
        for _, pack in ipairs(Quiz:GetQuestionPacks()) do
            Quiz:Print(L.PACK_ROW_F:format(pack.id, pack.title, pack.count))
        end
        for _, reason in ipairs(Quiz:GetPackErrors()) do
            Quiz:Print(reason)
        end
    elseif command == "scores" then
        local rows = Quiz.UI:GetPersonalScoreLines()
        Quiz:Print(L.W_PERSONAL_BOARD)
        if #rows == 0 then
            Quiz:Print(L.W_NO_PERSONAL_SCORES)
        end
        for _, row in ipairs(rows) do
            Quiz:Print(row)
        end
    elseif command == "legacy" or command == "archive" then
        Quiz:Print(command == "legacy" and L.LEGACY_SCORES or L.W_LEAGUE_ARCHIVE)
        local found = false
        for _, league in ipairs(Quiz.Store:GetArchivedLeagues()) do
            local standings = command == "legacy" and Quiz.Store:GetLegacyStandings(league, "PUBLIC")
                or Quiz.Store:GetStandings(league, "PUBLIC")
            if #standings > 0 then
                found = true
                Quiz:Print(L.W_ARCHIVE_LEAGUE_F:format(league))
                for index, player in ipairs(standings) do
                    Quiz:Print(
                        L.STANDINGS_ROW_F:format(index, player.name, player.score, player.correct, player.incorrect)
                    )
                end
            end
        end
        if not found then
            Quiz:Print(L.NO_STANDINGS)
        end
    else
        Quiz:Print(L.HELP)
    end
end

function Main:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == Quiz.addonName then
            local db, reason = Quiz.Store:Initialize(OrbitQuizDB)
            if not db then
                self.initializationError = reason
                self:Report(reason)
                return
            end
            OrbitQuizDB = db
            Quiz.Media:Initialize(RefreshMediaConsumers)
            Quiz.Session:Initialize()
            local ready, commError = Quiz.Comms:Initialize(function(sender, fields)
                Quiz.Session:Receive(sender, fields)
            end, function(target, errorCode)
                Quiz.Session:OnSendError(target, errorCode)
            end)
            if ready then
                self.initialized = true
                Quiz.Discovery:Initialize()
            else
                self.initializationError = commError
                self:Report(commError)
            end
        elseif self.initialized then
            Quiz.Media:Initialize(RefreshMediaConsumers)
        end
    elseif event == "PLAYER_LOGIN" then
        if self.initialized then
            Quiz.Discovery:Start()
            self:EnsureTicker()
            Quiz:Print(L.LOADED_F:format(Quiz.version))
            for _, reason in ipairs(Quiz:GetPackErrors()) do
                Quiz:Print(reason)
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        Quiz.Widget:SetEditing(false)
        self:CancelTicker()
        Quiz.Discovery.started = false
        Quiz.Comms:Clear()
        if self.game then
            self.game:Stop()
        end
        Quiz.Session.hostSession, Quiz.Session.client, Quiz.Session.peers = nil, nil, {}
        self.nextAutoAt, self.autoPaused, self.finishPending = nil, false, false
    elseif not self.initialized then
        return
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restriction, state = ...
        if
            not issecretvalue(restriction)
            and not issecretvalue(state)
            and restriction == Enum.AddOnRestrictionType.Chat
        then
            self.restrictionActive = state ~= Enum.AddOnRestrictionState.Inactive
            self:SyncRestriction()
        end
    elseif event == "CHAT_SERVER_DISCONNECTED" then
        self.chatDisconnected = true
        self:SyncRestriction()
    elseif event == "CHAT_SERVER_RECONNECTED" then
        self.chatDisconnected = false
        self:SyncRestriction()
    elseif event == "CHAT_MSG_ADDON" then
        if self:IsRestricted() then
            self:SyncRestriction()
        else
            Quiz.Comms:Receive(...)
            Quiz.Discovery:Receive(...)
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        Quiz.Discovery:Refresh()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        Quiz.Widget:OnDisplayChanged()
        Quiz.UI:OnDisplayChanged()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, method = ...
        if
            not issecretvalue(addon)
            and not issecretvalue(method)
            and addon == Quiz.addonName
            and type(method) == "string"
        then
            if method:find("SendAddonMessage", 1, true) then
                Quiz.Comms:Clear()
                if self:IsRunning() then
                    self:Pause(L.NET_SEND_FAILED, false)
                end
            end
        end
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "ADDON_RESTRICTION_STATE_CHANGED",
    "CHAT_SERVER_DISCONNECTED",
    "CHAT_SERVER_RECONNECTED",
    "CHAT_MSG_ADDON",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_GUILD_UPDATE",
    "DISPLAY_SIZE_CHANGED",
    "UI_SCALE_CHANGED",
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
    local ok, reason = pcall(Main.OnEvent, Main, event, ...)
    if not ok then
        geterrorhandler()(reason)
    end
end)

SLASH_ORBITQUIZ1 = "/orbitquiz"
SLASH_ORBITQUIZ2 = "/oq"
SlashCmdList.ORBITQUIZ = function(message)
    Main:Command(message)
end

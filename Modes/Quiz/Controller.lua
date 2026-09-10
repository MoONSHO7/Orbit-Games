local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L
local MAX_IDENTITY_LENGTH = 128

local function ErrorText(reason)
    return L.errors[reason] or reason
end

Quiz.Controller = { autoPaused = false }
local Controller = Quiz.Controller

function Controller:Initialize(application)
    self.app = application
end

function Controller:Report(reason)
    return self.app:Report(reason)
end

function Controller:SetNotice(notice)
    self.notice = notice
end

function Controller:GetNotice()
    return self.notice
end

function Controller:IsRunning()
    return self.game ~= nil
        and self.game.state ~= "stopped"
        and (self.game.state ~= "finished" or self.finishPending == true)
end

function Controller:OnWaitingChanged(waiting, wasWaiting, reason)
    if not waiting and wasWaiting and self.finishPending and self.nextAutoAt then
        self.nextAutoAt = GetTime() + self.game.rules.revealSeconds
    end
    if waiting and self:IsRunning() and self.game.state ~= "paused" and self.game.state ~= "finished" then
        self:Pause(reason, true)
    elseif waiting and self.autoPaused and self:IsRunning() and self.game.state == "paused" then
        local notice = ErrorText(reason)
        if notice ~= self.notice then
            self.notice = notice
            self.game.pauseReason = reason
            self.app:RefreshPresenters()
        end
    elseif not waiting and self.autoPaused and self:IsRunning() then
        self:Resume()
    end
end

function Controller:HandleRuntimeError(message)
    self.autoPaused, self.nextAutoAt, self.notice = false, nil, message
    if self:IsRunning() then
        self.game:Pause(message)
    end
end

function Controller:SaveSettings(settings, silent)
    if self:IsRunning() then
        return self:Report(L.SETTINGS_LOCKED)
    end
    local ok, reason = Quiz.Store:SaveSettings(settings)
    if not ok then
        return self:Report(reason)
    end
    if Games.UI.frame then
        Games.UI:LoadSettings()
    end
    if not silent then
        self.notice = L.SETTINGS_SAVED
        self.app:RefreshPresenters()
    end
    return true
end

function Controller:PlayerKey(name, trustedGUID)
    local fullName = Games.Identity:NormalizeName(name)
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

function Controller:GetScore(playerKey)
    local player = self.game and self.game.players[playerKey]
    return player and player.score or 0
end

function Controller:Start(settings)
    if not self.app.initialized then
        return self:Report(self.app.initializationError or L.HOST_UNAVAILABLE)
    end
    if self:IsRunning() then
        return self:Report(L.ALREADY_RUNNING)
    end
    if not self:SaveSettings(settings or Quiz.Store:GetSettings(), true) then
        return false
    end
    local configured = Quiz.Store:GetSettings()
    local rules, rulesError = Quiz:GetRules(configured.packId)
    if not rules then
        return self:Report(rulesError)
    end
    local identified, identityError = Games.Identity:Initialize()
    if not identified then
        return self:Report(identityError)
    end
    local questions, packError = Quiz:GetQuestions(configured.packId)
    if not questions then
        return self:Report(packError)
    end
    local game, gameError = Quiz.Model.New(configured, questions, math.random, rules)
    if not game then
        return self:Report(gameError)
    end
    local sessionCounter, counterError = Quiz.Store:NextQuestionId()
    if not sessionCounter then
        return self:Report(counterError)
    end
    self.game = game
    self.identityByName = {}
    self.identityByName[Games.Identity.name:lower()] = Games.Identity.guid
    self.notice, self.nextAutoAt, self.autoPaused, self.finishPending = nil, nil, false, false
    Quiz.Session:StartHost(string.format("%.0f.%.0f", GetServerTime(), sessionCounter))
    self.app:EnsureTicker()
    self.app:SyncRestriction()
    Quiz.Widget:Show()
    if game.state ~= "paused" then
        return self:NextQuestion()
    end
    return true
end

function Controller:NextQuestion()
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
            self.app:RefreshPresenters()
            return true
        end
        self:Pause(reason, false)
        return false, reason
    end
    self.nextAutoAt, self.notice = nil, nil
    local now = GetTime()
    Quiz.Session:PrepareRound(now)
    self:TryOpenQuestion(now)
    self.app:EnsureTicker()
    self.app:RefreshPresenters()
    return true
end

function Controller:TryOpenQuestion(now)
    if self.game and self.game.state == "posting" and not self.app:IsWaiting() and Quiz.Session:CanOpen(now) then
        self.game:OpenQuestion(now)
        Quiz.Session:OpenRound()
    end
end

function Controller:AcceptAnswer(name, trustedGUID, id, choice, actionId)
    if self.app:IsWaiting() then
        self.app:SyncWaiting()
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
    local accepted, reason = self.game:Submit(key, Games.Identity:NormalizeName(name), id, choice, now, actionId)
    if accepted then
        self.app:RefreshPresenters()
    end
    return accepted, reason
end

function Controller:GetHostView()
    local game = self.game
    local view = {
        role = "host",
        gameTypeId = Quiz.id,
        hostName = Games.Identity.name,
        state = game.state == "finished" and self.finishPending and "results" or game.state,
        session = Quiz.Session.hostSession,
        score = self:GetScore(Games.Identity.guid),
        notice = game.state == "paused" and self.notice or nil,
        scoringVersion = Quiz.Scoring.VERSION,
        rulesKey = game.rulesKey,
        rules = game.rules,
    }
    local round = game.round
    if round then
        view.id, view.cycle, view.number, view.total = round.id, round.cycle, round.number, game.total
        view.prompt, view.choices = round.prompt, round.choices
        view.packId, view.packTitle, view.packVersion = round.packId, round.packTitle, round.packVersion
        view.difficulty, view.era = round.difficulty, round.era
        view.duration, view.deadline = game.rules.answerSeconds, round.deadline
        local answer = round.answers[Games.Identity.guid]
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

function Controller:CloseQuestion(now)
    local game = self.game
    local multiplayer = game.round and Quiz.Session:HasRoundPeers(game.round.id, now) or false
    local result = game:CloseQuestion(now, multiplayer)
    if not result then
        return
    end
    self.finishPending = result.complete == true
    local answer = game.round.answers[Games.Identity.guid]
    local saved, reason = Quiz.PersonalScores:RecordResult({
        host = Games.Identity.name,
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

function Controller:Finish()
    self.nextAutoAt, self.finishPending, self.autoPaused = nil, false, false
    Quiz.Session:EndHost()
    self.notice = L.STATUS_FINISHED
end

function Controller:Pause(reason, automatic)
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
    self.app:EnsureTicker()
    self.app:RefreshPresenters()
    return true
end

function Controller:Resume()
    if not self:IsRunning() then
        return self:Report(L.NO_GAME)
    end
    if self.app:IsWaiting() then
        return self:Report(self.app:GetWaitingReason())
    end
    local ok, reason = self.game:Resume()
    if not ok then
        return self:Report(reason)
    end
    self.autoPaused, self.notice = false, nil
    if self.game.state == "finished" then
        self:Finish()
        self.app:RefreshPresenters()
        return true
    end
    return self:NextQuestion()
end

function Controller:Stop()
    if self.game then
        self.game:Stop()
    end
    if Quiz.Session.hostSession then
        Quiz.Session:EndHost(true)
    elseif Quiz.Session.client then
        Quiz.Session:Leave()
    end
    self.nextAutoAt, self.autoPaused, self.finishPending = nil, false, false
    self.notice = L.STATUS_STOPPED
    self.app:EnsureTicker()
    self.app:RefreshPresenters()
    return true
end

function Controller:Tick(now)
    Quiz.Session:Tick(now)
    local game = self.game
    if self:IsRunning() and not self.app:IsWaiting() then
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
end

function Controller:Shutdown()
    if self.game then
        self.game:Stop()
    end
    self.game = nil
    self.identityByName = nil
    self.notice, self.nextAutoAt, self.autoPaused, self.finishPending = nil, nil, false, false
end

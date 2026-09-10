local _, Games = ...
local L = Games.L

local TICK_INTERVAL = 0.1

Games.Main = {}
local Main = Games.Main

local function ErrorText(reason, gameType)
    local modeErrors = gameType and gameType.locale.errors
    return modeErrors and modeErrors[reason] or L.errors[reason] or reason
end

function Main:GetGameType()
    return Games.GameTypes:Get(self.activeGameTypeId) or Games.GameTypes:GetDefault()
end

function Main:GetController()
    return self:GetGameType().controller
end

function Main:GetSession()
    return self:GetGameType().session
end

function Main:GetHUD()
    return self:GetGameType().ui.hud
end

function Main:RefreshPresenters()
    if Games.UI.frame then
        Games.UI:Refresh()
    end
    local hud = self:GetHUD()
    if hud.frame then
        hud:Refresh()
    end
end

function Main:RefreshMediaConsumers()
    if not self.initialized then
        return
    end
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        gameType.ui.hud:ApplySettings()
    end
    if Games.UI.frame then
        Games.UI:RefreshModeSettings()
    end
end

function Main:Report(reason)
    self.notice = ErrorText(reason, self:GetGameType())
    self:GetController():SetNotice(self.notice)
    self:RefreshPresenters()
    return false, self.notice
end

function Main:AbortInitialization(reason)
    self.initialized = false
    self.initializationError = reason
    self:CancelTicker()
    Games.Comms:Clear()
    Games.Comms.initialized = false
    Games.Discovery.started = false
    Games.Discovery.initialized = false
    return self:Report(reason)
end

function Main:IsRunning()
    return self:GetController():IsRunning()
end

function Main:IsSessionActive()
    return self:GetSession():IsActive()
end

function Main:IsRestricted()
    return self.restrictionActive
        or self.chatDisconnected
        or self.restrictedUntil and GetTime() < self.restrictedUntil
        or C_ChatInfo.InChatMessagingLockdown()
end

function Main:IsWaiting()
    return self:IsRestricted() or self.encounterActive == true
end

function Main:GetWaitingReason()
    if self.encounterActive then
        return L.ENCOUNTER_WAITING
    elseif self.chatDisconnected then
        return L.NET_CHAT_DISCONNECTED
    end
    return L.NET_RESTRICTED
end

function Main:SyncWaiting()
    local waiting = not not self:IsWaiting()
    local wasWaiting = self.waitingActive == true
    self.waitingActive = waiting
    self:GetController():OnWaitingChanged(waiting, wasWaiting, waiting and self:GetWaitingReason() or nil)
end

function Main:SyncRestriction()
    local restricted = not not self:IsRestricted()
    Games.Comms.suspended = restricted
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        gameType.session:SetRestricted(restricted)
    end
    self:SyncWaiting()
end

function Main:SyncEncounter()
    self.encounterActive = C_InstanceEncounter.IsEncounterInProgress()
    self:SyncWaiting()
end

function Main:EnsureTicker()
    if self.ticker then
        return
    end
    self.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
        local ok, failure = pcall(self.Tick, self)
        if not ok then
            self:CancelTicker()
            Games.Comms:Clear()
            self:GetController():HandleRuntimeError(L.INTERNAL_ERROR)
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

function Main:SelectGameType(gameTypeId)
    local gameType = Games.GameTypes:Get(gameTypeId)
    if not gameType then
        return false, "invalid_game_type"
    end
    local current = self:GetGameType()
    if current.id == gameTypeId then
        return false, "unchanged"
    end
    if self:IsRunning() or self:IsSessionActive() then
        return false, "game_type_locked"
    end
    local saved, reason = Games.Store:SelectGameType(gameTypeId)
    if not saved then
        return false, reason
    end
    if Games.UI.frame and Games.UI.frame:IsShown() then
        current.ui.hud:SetEditing(false)
    end
    self.activeGameTypeId = gameTypeId
    if Games.UI.frame and Games.UI.frame:IsShown() then
        gameType.ui.hud:SetEditing(true)
    end
    self.notice = nil
    current.controller:SetNotice(nil)
    gameType.controller:SetNotice(nil)
    return true
end

function Main:Start(settings)
    self.notice = nil
    local controller = self:GetController()
    controller:SetNotice(nil)
    return controller:Start(settings)
end

function Main:Join(game)
    if type(game) ~= "table" or not Games.GameTypes:Get(game.gameTypeId) then
        return false, "invalid_game_type"
    end
    if game.joinable == false then
        return false, "game_not_joinable"
    end
    local current = self:GetGameType()
    if current.id ~= game.gameTypeId then
        if self:IsSessionActive() then
            local left = self:Leave()
            if not left then
                return false, "game_type_locked"
            end
        end
        local selected, reason = self:SelectGameType(game.gameTypeId)
        if not selected and reason ~= "unchanged" then
            return false, reason
        end
        if Games.UI.frame then
            Games.UI:ActivateGameType()
        end
    end
    self.notice = nil
    self:GetController():SetNotice(nil)
    return self:GetSession():JoinHost(game.hostName, game.sessionId, game)
end

function Main:Leave()
    local controller, session = self:GetController(), self:GetSession()
    local ok, reason
    if controller:IsRunning() then
        ok, reason = controller:Stop()
    else
        ok, reason = session:Leave()
    end
    self:RefreshPresenters()
    return ok, reason
end

function Main:Pause()
    return self:GetController():Pause(nil, false)
end

function Main:Resume()
    return self:GetController():Resume()
end

function Main:Stop()
    return self:GetController():Stop()
end

function Main:GetHostedAdvert()
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        local advert = gameType.advert:GetHosted(gameType.controller, gameType.session)
        if advert then
            advert.gameTypeId = gameType.id
            advert.protocolVersion = gameType.protocolVersion
            return advert
        end
    end
end

function Main:GetHostedSessionId()
    local advert = self:GetHostedAdvert()
    return advert and advert.sessionId
end

function Main:IsJoinedTo(game)
    local gameType = Games.GameTypes:Get(game.gameTypeId)
    return gameType ~= nil and gameType.session:IsJoinedTo(game)
end

function Main:Tick()
    local now = GetTime()
    self:SyncRestriction()
    self:GetController():Tick(now)
    Games.Comms:Tick(now)
    Games.Discovery:Tick(now)
    self:RefreshPresenters()
    if
        not Games.Discovery.started
        and not self:IsRunning()
        and not self:IsSessionActive()
        and not Games.Comms:IsBusy()
    then
        self:CancelTicker()
    end
end

function Main:Command(message)
    if not self.initialized then
        return self:Report(self.initializationError or L.HOST_UNAVAILABLE)
    end
    local command, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "games" or command == "host" or command == "setup" then
        Games.UI:Toggle()
    elseif command == "settings" then
        Games.UI:Show("settings")
    elseif command == "join" then
        local joined, reason = self:GetSession():JoinHost(rest)
        if not joined then
            self:Report(reason)
        end
    elseif command == "leave" then
        local left, reason = self:Leave()
        if not left then
            self:Report(reason)
        end
    elseif command == "start" then
        self:Start()
    elseif command == "pause" then
        self:Pause()
    elseif command == "resume" then
        self:Resume()
    elseif command == "stop" then
        self:Stop()
    elseif command == "status" then
        Games.UI:Show("play")
    elseif not self:GetGameType().commands:Handle(command, rest) then
        Games.UI:Show("play")
    end
end

function Main:Initialize()
    local db, reason = Games.Store:Initialize(OrbitGamesDB)
    if not db then
        self.initializationError = reason
        self:Report(reason)
        return
    end
    OrbitGamesDB = db
    self.activeGameTypeId = Games.Store:GetSelectedGameType()
    self.encounterActive = C_InstanceEncounter.IsEncounterInProgress()
    self.waitingActive = nil
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        gameType.controller:Initialize(self)
        gameType.session:Initialize()
    end
    Games.Media:Initialize(function()
        self:RefreshMediaConsumers()
    end)
    local ready, commError = Games.Comms:Initialize(function(sender, gameTypeId, fields)
        local gameType = Games.GameTypes:Get(gameTypeId)
        if gameType then
            gameType.session:Receive(sender, fields)
        end
    end, function(target, gameTypeId, errorCode)
        local gameType = Games.GameTypes:Get(gameTypeId)
        if gameType then
            gameType.session:OnSendError(target, errorCode)
        end
    end)
    if ready then
        self.initialized = true
        Games.Discovery:Initialize()
        Games.Minimap:Initialize()
    else
        self.initializationError = commError
        self:Report(commError)
    end
end

function Main:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == Games.addonName then
            self:Initialize()
        elseif self.initialized then
            Games.Media:Initialize(function()
                self:RefreshMediaConsumers()
            end)
        end
    elseif event == "PLAYER_LOGIN" then
        if self.initialized then
            self:SyncEncounter()
            Games.Discovery:Start()
            self:EnsureTicker()
            self:GetGameType().commands:OnLogin()
        end
    elseif event == "PLAYER_LOGOUT" then
        if not self.initialized then
            return
        end
        self:GetHUD():SetEditing(false)
        self:CancelTicker()
        Games.Discovery.started = false
        Games.Comms:Clear()
        for _, gameType in ipairs(Games.GameTypes:GetAll()) do
            gameType.controller:Shutdown()
            gameType.session:Shutdown()
        end
        self.encounterActive, self.waitingActive = nil, nil
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
    elseif event == "ENCOUNTER_STATE_CHANGED" then
        self:SyncEncounter()
    elseif event == "CHAT_MSG_ADDON" then
        if self:IsRestricted() then
            self:SyncRestriction()
        else
            Games.Comms:Receive(...)
            Games.Discovery:Receive(...)
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        Games.Discovery:Refresh()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        for _, gameType in ipairs(Games.GameTypes:GetAll()) do
            gameType.ui.hud:OnDisplayChanged()
        end
        Games.UI:OnDisplayChanged()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, method = ...
        if
            not issecretvalue(addon)
            and not issecretvalue(method)
            and addon == Games.addonName
            and type(method) == "string"
            and method:find("SendAddonMessage", 1, true)
        then
            Games.Comms:Clear()
            if self:IsRunning() then
                self:GetController():Pause(L.NET_SEND_FAILED, false)
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
    "ENCOUNTER_STATE_CHANGED",
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

SLASH_ORBITGAMES1 = "/orbitgames"
SLASH_ORBITGAMES2 = "/og"
SlashCmdList.ORBITGAMES = function(message)
    Main:Command(message)
end

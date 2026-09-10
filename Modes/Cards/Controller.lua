local _, Games = ...
local Cards = Games.Cards
local L = Cards.L

local ACTIVE_HAND_STATES = { preflop = true, flop = true, turn = true, river = true }

Cards.Controller = { autoPaused = false }
local Controller = Cards.Controller

local function ErrorText(reason)
    return L.errors[reason] or reason
end

local function PlayerId(name)
    local normalized = Games.Identity:NormalizeName(name)
    return normalized and "name:" .. normalized:lower() or nil
end

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
end

function Controller:IsHandActive()
    return self.game ~= nil and ACTIVE_HAND_STATES[self.game:GetState()] == true
end

function Controller:SaveSettings(settings, silent)
    if self:IsRunning() then
        return self:Report(L.SETTINGS_LOCKED)
    end
    local saved, reason = Cards.Store:SaveHostSettings(settings)
    if not saved then
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

function Controller:Rules(settings)
    return {
        version = Cards.TexasHoldem.Rules.VERSION,
        maxPlayers = settings.maxPlayers,
        buyIn = settings.buyIn,
        smallBlind = settings.smallBlind,
        bigBlind = settings.bigBlind,
        actionSeconds = settings.actionSeconds,
    }
end

function Controller:Start(settings)
    if not self.app.initialized then
        return self:Report(self.app.initializationError or L.HOST_UNAVAILABLE)
    end
    if self:IsRunning() then
        return self:Report(L.ALREADY_RUNNING)
    end
    if not self:SaveSettings(settings or Cards.Store:GetHostSettings(), true) then
        return false
    end
    local identified, identityError = Games.Identity:Initialize()
    if not identified then
        return self:Report(identityError)
    end
    local configured = Cards.Store:GetHostSettings()
    local variant = Cards.Variants:Get(Cards.Store:GetSelectedVariant())
    if not variant then
        return self:Report("invalid_variant")
    end
    local counter, counterError = Cards.Store:NextSessionId()
    if not counter then
        return self:Report(counterError)
    end
    local sessionId = string.format("%.0f.%.0f", GetServerTime(), counter)
    local hostId = Games.Identity.guid
    local game, gameError = variant.model.New(self:Rules(configured), {
        {
            seat = 1,
            id = hostId,
            name = Games.Identity.name,
            stack = configured.buyIn,
            sittingOut = false,
        },
    })
    if not game then
        return self:Report(gameError)
    end
    self.game = game
    self.variant = variant
    self.settings = configured
    self.hostId = hostId
    self.ledger = Cards.Ledger.New(sessionId)
    self.ledger:AddPlayer(hostId, Games.Identity.name, configured.buyIn)
    self.settlementSaved = false
    self.lastButtonSeat = 0
    self.connected = {}
    self.paused, self.pausedAt, self.autoPaused, self.notice = false, nil, false, nil
    Cards.Session:StartHost(sessionId)
    self.app:EnsureTicker()
    self.app:SyncRestriction()
    Cards.Table:Show()
    Cards.Session:Broadcast()
    self.app:RefreshPresenters()
    return true
end

function Controller:FindSeat()
    for seatNumber = 1, self.settings.maxPlayers do
        if not self.game.seats[seatNumber] then
            return seatNumber
        end
    end
end

function Controller:AcceptJoin(name)
    if not self.game then
        return nil, "not_running"
    end
    local id = PlayerId(name)
    if not id then
        return nil, "invalid_player"
    end
    if self.game.seatsById[id] then
        return id
    end
    if self:IsHandActive() then
        return nil, "table_started"
    end
    local seat = self:FindSeat()
    if not seat then
        return nil, "table_full"
    end
    local added, reason = self.game:AddPlayer({
        seat = seat,
        id = id,
        name = name,
        stack = self.settings.buyIn,
        sittingOut = false,
    })
    if not added then
        return nil, reason
    end
    self.ledger:AddPlayer(id, name, self.settings.buyIn)
    self.app:RefreshPresenters()
    return id
end

function Controller:SetConnected(playerId, connected)
    if not self.game or not self.game.seatsById[playerId] then
        return false
    end
    local value = connected == true
    if self.connected[playerId] == value then
        return true, "unchanged"
    end
    self.connected[playerId] = value
    if not value and not self:IsHandActive() then
        self.game:SetSittingOut(playerId, true)
    end
    self.app:RefreshPresenters()
    return true
end

function Controller:ReconcileDisconnected()
    if not self.game or self:IsHandActive() then
        return false
    end
    local changed = false
    for playerId, connected in pairs(self.connected) do
        local seat = self.game.seatsById[playerId]
        if not connected and seat and not seat.sittingOut then
            local seated = self.game:SetSittingOut(playerId, true)
            changed = seated or changed
        end
    end
    return changed
end

function Controller:SetSittingOut(playerId, sittingOut)
    if not self.game then
        return false, "not_running"
    end
    local changed, reason = self.game:SetSittingOut(playerId, sittingOut)
    if changed then
        Cards.Session:Broadcast()
        self.app:RefreshPresenters()
    end
    return changed, reason
end

function Controller:Rebuy(playerId)
    if not self.game then
        return false, "not_running"
    end
    if not self.settings.allowRebuys then
        return false, "rebuys_disabled"
    end
    if self.game.sessionChipTotal + self.settings.buyIn > Cards.MAX_TOTAL_CHIPS then
        return false, "rebuy_limit"
    end
    local bought, reason = self.game:Rebuy(playerId, self.settings.buyIn)
    if not bought then
        return false, reason
    end
    self.ledger:RecordRebuy(playerId, self.settings.buyIn)
    Cards.Session:Broadcast()
    self.app:RefreshPresenters()
    return true
end

function Controller:NextButtonSeat()
    for offset = 1, self.settings.maxPlayers do
        local seatNumber = (self.lastButtonSeat + offset - 1) % self.settings.maxPlayers + 1
        local seat = self.game.seats[seatNumber]
        if seat and not seat.sittingOut and seat.stack > 0 then
            return seatNumber
        end
    end
end

function Controller:StartHand()
    if not self.game then
        return self:Report(L.NO_GAME)
    end
    if self.paused or self.app:IsWaiting() then
        return self:Report(self.app:IsWaiting() and self.app:GetWaitingReason() or L.STATUS_PAUSED)
    end
    if self:IsHandActive() then
        return false, "hand_active"
    end
    self:ReconcileDisconnected()
    local counter, counterError = Cards.Store:NextHandId()
    if not counter then
        return self:Report(counterError)
    end
    local deck, deckError = Cards.Deck.Shuffle(math.random)
    if not deck then
        return self:Report(deckError)
    end
    local buttonSeat = self:NextButtonSeat()
    if not buttonSeat then
        return false, "not_enough_players"
    end
    local handId = string.format("%s.%.0f", Cards.Session.hostSession, counter)
    local started, reason = self.game:StartHand(handId, buttonSeat, deck, GetTime())
    if not started then
        return false, reason
    end
    self.lastButtonSeat = buttonSeat
    Cards.Session:Broadcast()
    self.app:RefreshPresenters()
    return true
end

function Controller:AcceptAction(playerId, action, targetAmount)
    if not self.game or self.paused or self.app:IsWaiting() then
        return false, self.app:IsRestricted() and "addon_lockdown" or "not_running"
    end
    local accepted, reason = self.game:Act(playerId, action, targetAmount, GetTime())
    if accepted then
        self:ReconcileDisconnected()
        Cards.Session:Broadcast()
        self.app:RefreshPresenters()
    end
    return accepted, reason
end

function Controller:GetProjection(playerId)
    if not self.game then
        return nil
    end
    local projection = self.game:GetProjection(playerId)
    projection.currencyMode = Cards.CURRENCY_MODE
    projection.allowRebuys = self.settings.allowRebuys
    projection.hostName = Games.Identity.name
    projection.session = Cards.Session.hostSession
    projection.notice = self.notice
    if self.paused then
        projection.baseState = projection.state
        projection.state = "paused"
        projection.actionDeadline = nil
        projection.legalActions = nil
    end
    for _, seat in ipairs(projection.seats) do
        seat.funded = true
        seat.connected = seat.id == self.hostId or self.connected and self.connected[seat.id] == true
    end
    return projection
end

function Controller:GetHostView()
    local projection = self:GetProjection(self.hostId)
    if not projection then
        return { role = "idle", state = "idle", gameTypeId = Cards.id }
    end
    projection.role = "host"
    projection.gameTypeId = Cards.id
    projection.playerId = self.hostId
    return projection
end

function Controller:Pause(reason, automatic)
    if not self:IsRunning() then
        return self:Report(L.NO_GAME)
    end
    if self.paused then
        if automatic ~= true and self.autoPaused then
            self.autoPaused = false
            self.notice = ErrorText(reason or L.STATUS_PAUSED)
            Cards.Session:Broadcast()
            self.app:RefreshPresenters()
            return true
        end
        return true, "unchanged"
    end
    self.paused = true
    self.pausedAt = GetTime()
    self.autoPaused = automatic == true
    self.notice = ErrorText(reason or L.STATUS_PAUSED)
    Cards.Session:Broadcast()
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
    if not self.paused then
        return false, "not_paused"
    end
    local now = GetTime()
    local pausedFor = now - self.pausedAt
    if self.game.hand and self.game.hand.actionDeadline then
        self.game.hand.actionStartedAt = self.game.hand.actionStartedAt + pausedFor
        self.game.hand.actionDeadline = self.game.hand.actionDeadline + pausedFor
    end
    self.paused, self.pausedAt, self.autoPaused, self.notice = false, nil, false, nil
    Cards.Session:Broadcast()
    self.app:RefreshPresenters()
    return true
end

function Controller:OnWaitingChanged(waiting, wasWaiting, reason)
    if waiting and self:IsRunning() and not self.paused then
        self:Pause(reason or "addon_lockdown", true)
    elseif waiting and self:IsRunning() and self.autoPaused then
        local notice = ErrorText(reason)
        if notice ~= self.notice then
            self.notice = notice
            Cards.Session:Broadcast()
            self.app:RefreshPresenters()
        end
    elseif not waiting and wasWaiting and self.autoPaused then
        self:Resume()
    end
end

function Controller:HandleRuntimeError(message)
    self.notice = message
    if self:IsRunning() and not self.paused then
        self:Pause(message, false)
    end
end

function Controller:FinalizeLedger()
    if not self.game or self.settlementSaved or self:IsHandActive() then
        return not self:IsHandActive()
    end
    for id, player in pairs(self.ledger.players) do
        local seat = self.game.seatsById[id]
        self.ledger:SetFinalStack(id, seat and seat.stack or player.buyIn + player.rebuy)
    end
    local settlement, reason = self.ledger:BuildSettlement(self.variant.id, GetServerTime())
    if not settlement then
        return false, reason
    end
    local saved, saveError = Cards.Store:AddSettlement(settlement)
    if not saved then
        return false, saveError
    end
    self.settlementSaved = true
    Cards.ResultsPage:Invalidate()
    return true
end

function Controller:Stop()
    if Cards.Session.client and not self.game then
        return Cards.Session:Leave()
    end
    if not self.game then
        return true, "unchanged"
    end
    if self:IsHandActive() then
        return false, "hand_active"
    end
    local finalized, reason = self:FinalizeLedger()
    if not finalized then
        return self:Report(reason)
    end
    Cards.Session:EndHost()
    self.game, self.variant, self.settings, self.hostId, self.ledger = nil, nil, nil, nil, nil
    self.connected = nil
    self.paused, self.pausedAt, self.autoPaused = false, nil, false
    self.notice = L.STATUS_STOPPED
    self.app:EnsureTicker()
    self.app:RefreshPresenters()
    return true
end

function Controller:Tick(now)
    Cards.Session:Tick(now)
    if
        self.game
        and not self.paused
        and not self.app:IsWaiting()
        and self.game.hand
        and self.game.hand.actionDeadline
        and now >= self.game.hand.actionDeadline
    then
        local advanced, reason = self.game:Advance(now)
        if not advanced then
            self:Pause(reason, false)
            return
        end
        self:ReconcileDisconnected()
        Cards.Session:Broadcast()
        self.app:RefreshPresenters()
    end
end

function Controller:Shutdown()
    self:FinalizeLedger()
    self.game, self.variant, self.settings, self.hostId, self.ledger = nil, nil, nil, nil, nil
    self.connected = nil
    self.paused, self.pausedAt, self.autoPaused, self.notice = false, nil, false, nil
end

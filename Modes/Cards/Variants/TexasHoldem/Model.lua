local _, Games = ...
local Cards = Games.Cards
local Holdem = Cards.TexasHoldem
local Betting = Holdem.Betting
local Pots = Holdem.Pots

local MAX_IDENTITY_BYTES = 128
local MAX_HAND_ID_BYTES = 64
local STREET_AFTER = { preflop = "flop", flop = "turn", turn = "river" }

local Model = {}
Model.__index = Model
Holdem.Model = Model

local function IsInteger(value, minimum, maximum)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= minimum and value <= maximum
end

local function IsText(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum and not value:find("[%z\1-\31\127|]")
end

local function IsTime(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function IsSeatDefinition(definition, maxPlayers)
    if type(definition) ~= "table" or getmetatable(definition) ~= nil then
        return false
    end
    for key in pairs(definition) do
        if key ~= "seat" and key ~= "id" and key ~= "name" and key ~= "stack" and key ~= "sittingOut" then
            return false
        end
    end
    return IsInteger(definition.seat, 1, maxPlayers)
        and IsText(definition.id, MAX_IDENTITY_BYTES)
        and IsText(definition.name, MAX_IDENTITY_BYTES)
        and IsInteger(definition.stack, 0, Holdem.Rules.MAX_CHIPS)
        and (definition.sittingOut == nil or type(definition.sittingOut) == "boolean")
end

local function IsDefinitionArray(definitions)
    if type(definitions) ~= "table" or getmetatable(definitions) ~= nil then
        return false
    end
    local count = 0
    for key in pairs(definitions) do
        if not IsInteger(key, 1, #definitions) then
            return false
        end
        count = count + 1
    end
    return count == #definitions
end

local function NextSeatMatching(hand, seatNumber, predicate)
    for offset = 1, hand.maxSeats do
        local candidate = (seatNumber + offset - 1) % hand.maxSeats + 1
        if predicate(hand.seats[candidate]) then
            return candidate
        end
    end
    return nil
end

local function IsInHand(seat)
    return seat and seat.inHand
end

local function CommitBlind(seat, amount)
    local paid = math.min(seat.stack, amount)
    seat.stack = seat.stack - paid
    seat.streetBet = seat.streetBet + paid
    seat.committed = seat.committed + paid
    seat.allIn = seat.stack == 0
    return paid
end

function Model.New(rawRules, definitions)
    local rules, reason = Holdem.Rules.Normalize(rawRules)
    if not rules then
        return nil, reason
    end
    if not IsDefinitionArray(definitions) or #definitions > rules.maxPlayers then
        return nil, "invalid_seats"
    end
    local self = setmetatable({
        rules = rules,
        seats = {},
        seatsById = {},
        state = "between_hands",
        revision = 0,
        sessionChipTotal = 0,
    }, Model)
    for _, definition in ipairs(definitions) do
        local added, addReason = self:AddPlayer(definition)
        if not added then
            return nil, addReason
        end
    end
    return self
end

function Model:AddPlayer(definition)
    if self.state ~= "between_hands" and self.state ~= "complete" then
        return false, "hand_active"
    end
    if not IsSeatDefinition(definition, self.rules.maxPlayers) then
        return false, "invalid_player"
    end
    if self.seats[definition.seat] or self.seatsById[definition.id] then
        return false, "seat_occupied"
    end
    local player = {
        seat = definition.seat,
        id = definition.id,
        name = definition.name,
        stack = definition.stack,
        sittingOut = definition.sittingOut == true,
    }
    self.seats[player.seat] = player
    self.seatsById[player.id] = player
    self.sessionChipTotal = self.sessionChipTotal + player.stack
    return true
end

function Model:RemovePlayer(playerId)
    if self.state ~= "between_hands" and self.state ~= "complete" then
        return nil, "hand_active"
    end
    local player = self.seatsById[playerId]
    if not player then
        return nil, "unknown_player"
    end
    self.seats[player.seat] = nil
    self.seatsById[player.id] = nil
    self.sessionChipTotal = self.sessionChipTotal - player.stack
    return player.stack
end

function Model:SetSittingOut(playerId, sittingOut)
    if self.state ~= "between_hands" and self.state ~= "complete" then
        return false, "hand_active"
    end
    if type(sittingOut) ~= "boolean" then
        return false, "invalid_sitting_out"
    end
    local player = self.seatsById[playerId]
    if not player then
        return false, "unknown_player"
    end
    player.sittingOut = sittingOut
    return true
end

function Model:Rebuy(playerId, amount)
    if self.state ~= "between_hands" and self.state ~= "complete" then
        return false, "hand_active"
    end
    local player = self.seatsById[playerId]
    if not player then
        return false, "unknown_player"
    end
    if player.stack ~= 0 then
        return false, "player_has_chips"
    end
    if amount ~= self.rules.buyIn then
        return false, "invalid_rebuy"
    end
    player.stack = player.stack + amount
    self.sessionChipTotal = self.sessionChipTotal + amount
    return true
end

function Model:GetState()
    return self.state
end

function Model:GetSeatNumber(playerId)
    local player = self.seatsById[playerId]
    return player and player.seat or nil
end

function Model:CheckChipConservation()
    local total = 0
    for seatNumber = 1, self.rules.maxPlayers do
        local seat = self.seats[seatNumber]
        if seat then
            total = total + seat.stack
            if self.hand and self.state ~= "complete" then
                total = total + seat.committed
            end
        end
    end
    return total == self.sessionChipTotal
end

function Model:AppendAction(action)
    self.revision = self.revision + 1
    action.revision = self.revision
    self.hand.actions[#self.hand.actions + 1] = action
end

function Model:StartTurn(now)
    if self.hand.betting and self.hand.betting.actorSeat then
        self.hand.actionStartedAt = now
        self.hand.actionDeadline = now + self.rules.actionSeconds
    else
        self.hand.actionStartedAt = nil
        self.hand.actionDeadline = nil
    end
end

function Model:DealStreet(street)
    local burned, reason = self.hand.deck:Draw(1)
    if not burned then
        return false, reason
    end
    self.hand.burnCards[#self.hand.burnCards + 1] = burned[1]
    local count = street == "flop" and 3 or 1
    local cards
    cards, reason = self.hand.deck:Draw(count)
    if not cards then
        return false, reason
    end
    for _, cardId in ipairs(cards) do
        self.hand.board[#self.hand.board + 1] = cardId
    end
    self.state = street
    return true
end

function Model:SettleHand()
    local contenderCount = Betting.CountContenders(self.hand)
    self.hand.showdown = contenderCount > 1
    local settlement, reason = Pots.Settle(self.hand)
    if not settlement then
        return false, reason
    end
    for seatNumber = 1, self.rules.maxPlayers do
        local seat = self.seats[seatNumber]
        if seat then
            seat.stack = seat.stack + (settlement.payouts[seatNumber] or 0) + (settlement.refunds[seatNumber] or 0)
        end
    end
    self.hand.settlement = settlement
    self.hand.betting = nil
    self.hand.actionStartedAt = nil
    self.hand.actionDeadline = nil
    self.state = "complete"
    self.revision = self.revision + 1
    if not self:CheckChipConservation() then
        return false, "chip_conservation_failed"
    end
    return true
end

function Model:ProgressAfterBetting(now)
    while true do
        if Betting.CountContenders(self.hand) <= 1 or self.state == "river" then
            return self:SettleHand()
        end
        local nextStreet = STREET_AFTER[self.state]
        local dealt, reason = self:DealStreet(nextStreet)
        if not dealt then
            return false, reason
        end
        local started
        started, reason =
            Betting.BeginStreet(self.hand, self.hand.buttonSeat % self.hand.maxSeats + 1, self.rules.bigBlind, 0, false)
        if not started then
            return false, reason
        end
        if not Betting.IsComplete(self.hand) then
            self:StartTurn(now)
            return true
        end
    end
end

function Model:StartHand(handId, buttonSeat, deckOrder, now)
    if self.state ~= "between_hands" and self.state ~= "complete" then
        return false, "hand_active"
    end
    if
        not IsText(handId, MAX_HAND_ID_BYTES)
        or handId == self.lastHandId
        or not IsInteger(buttonSeat, 1, self.rules.maxPlayers)
        or not IsTime(now)
    then
        return false, "invalid_hand"
    end
    local deck, reason = Cards.Deck.New(deckOrder)
    if not deck then
        return false, reason
    end
    local participants = {}
    for seatNumber = 1, self.rules.maxPlayers do
        local seat = self.seats[seatNumber]
        if seat and not seat.sittingOut and seat.stack > 0 then
            participants[#participants + 1] = seatNumber
        end
    end
    if #participants < 2 then
        return false, "not_enough_players"
    end
    local button = self.seats[buttonSeat]
    if not button or button.sittingOut or button.stack == 0 then
        return false, "invalid_button"
    end
    for seatNumber = 1, self.rules.maxPlayers do
        local seat = self.seats[seatNumber]
        if seat then
            seat.inHand = not seat.sittingOut and seat.stack > 0
            seat.folded = false
            seat.allIn = false
            seat.holeCards = {}
            seat.committed = 0
            seat.streetBet = 0
            seat.acted = false
            seat.lastActionBet = nil
        end
    end
    local hand = {
        id = handId,
        maxSeats = self.rules.maxPlayers,
        seats = self.seats,
        deck = deck,
        board = {},
        burnCards = {},
        actions = {},
        buttonSeat = buttonSeat,
        startedAt = now,
    }
    self.hand = hand
    self.lastHandId = handId
    self.state = "preflop"
    local smallBlindSeat, bigBlindSeat
    if #participants == 2 then
        smallBlindSeat = buttonSeat
        bigBlindSeat = NextSeatMatching(hand, smallBlindSeat, IsInHand)
    else
        smallBlindSeat = NextSeatMatching(hand, buttonSeat, IsInHand)
        bigBlindSeat = NextSeatMatching(hand, smallBlindSeat, IsInHand)
    end
    hand.smallBlindSeat, hand.bigBlindSeat = smallBlindSeat, bigBlindSeat
    local smallPaid = CommitBlind(self.seats[smallBlindSeat], self.rules.smallBlind)
    self:AppendAction({ street = "preflop", seat = smallBlindSeat, action = "small_blind", paid = smallPaid })
    local bigPaid = CommitBlind(self.seats[bigBlindSeat], self.rules.bigBlind)
    self:AppendAction({ street = "preflop", seat = bigBlindSeat, action = "big_blind", paid = bigPaid })
    local dealSeat = NextSeatMatching(hand, buttonSeat, IsInHand)
    for _ = 1, 2 do
        local seatNumber = dealSeat
        repeat
            local card
            card, reason = deck:Draw(1)
            if not card then
                return false, reason
            end
            self.seats[seatNumber].holeCards[#self.seats[seatNumber].holeCards + 1] = card[1]
            seatNumber = NextSeatMatching(hand, seatNumber, IsInHand)
        until seatNumber == dealSeat
    end
    local firstActor = #participants == 2 and smallBlindSeat or NextSeatMatching(hand, bigBlindSeat, IsInHand)
    local started
    started, reason = Betting.BeginStreet(hand, firstActor, self.rules.bigBlind, self.rules.bigBlind, true)
    if not started then
        return false, reason
    end
    if Betting.IsComplete(hand) then
        return self:ProgressAfterBetting(now)
    end
    self:StartTurn(now)
    return self:CheckChipConservation()
end

function Model:GetLegalActions(playerId)
    if not self.hand or self.state == "complete" then
        return nil, "no_active_hand"
    end
    local seat = self.seatsById[playerId]
    if not seat then
        return nil, "unknown_player"
    end
    return Betting.GetLegalActions(self.hand, seat.seat)
end

function Model:ApplyAction(playerId, action, targetAmount, now, automatic)
    if not self.hand or self.state == "complete" then
        return false, "no_active_hand"
    end
    if not IsTime(now) or now < self.hand.actionStartedAt then
        return false, "invalid_time"
    end
    if not automatic and now > self.hand.actionDeadline then
        return false, "turn_expired"
    end
    local seat = self.seatsById[playerId]
    if not seat then
        return false, "unknown_player"
    end
    local transition, reason = Betting.Apply(self.hand, seat.seat, action, targetAmount)
    if not transition then
        return false, reason
    end
    self:AppendAction({
        street = self.state,
        seat = seat.seat,
        action = action,
        paid = transition.paid,
        target = transition.target,
        automatic = automatic == true,
    })
    if not self:CheckChipConservation() then
        return false, "chip_conservation_failed"
    end
    if transition.complete then
        return self:ProgressAfterBetting(now)
    end
    self:StartTurn(now)
    return true
end

function Model:Act(playerId, action, targetAmount, now)
    return self:ApplyAction(playerId, action, targetAmount, now, false)
end

function Model:Advance(now)
    if not self.hand or self.state == "complete" then
        return false, "no_active_hand"
    end
    if not IsTime(now) then
        return false, "invalid_time"
    end
    if now < self.hand.actionDeadline then
        return false, "turn_active"
    end
    local actor = self.seats[self.hand.betting.actorSeat]
    local legal, reason = self:GetLegalActions(actor.id)
    if not legal then
        return false, reason
    end
    local action = legal.check and "check" or "fold"
    return self:ApplyAction(actor.id, action, nil, now, true)
end

function Model:GetProjection(recipientId)
    return Holdem.Projector.Build(self, recipientId)
end

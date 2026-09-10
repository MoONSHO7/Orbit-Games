local _, Games = ...
local Holdem = Games.Cards.TexasHoldem

local Betting = {}
Holdem.Betting = Betting

local function IsInteger(value)
    return type(value) == "number" and value == value and value % 1 == 0
end

local function IsContender(seat)
    return seat and seat.inHand and not seat.folded
end

local function IsActionable(seat)
    return IsContender(seat) and not seat.allIn
end

local function CountContenders(hand)
    local count = 0
    for seatNumber = 1, hand.maxSeats do
        if IsContender(hand.seats[seatNumber]) then
            count = count + 1
        end
    end
    return count
end

local function NeedsAction(hand, seat)
    return IsActionable(seat) and (not seat.acted or seat.streetBet < hand.betting.currentBet)
end

local function FindActor(hand, startSeat)
    for offset = 0, hand.maxSeats - 1 do
        local seatNumber = (startSeat + offset - 1) % hand.maxSeats + 1
        if NeedsAction(hand, hand.seats[seatNumber]) then
            return seatNumber
        end
    end
    return nil
end

local function HasOpponentWhoCanRespond(hand, seatNumber)
    for otherSeat = 1, hand.maxSeats do
        if otherSeat ~= seatNumber and IsActionable(hand.seats[otherSeat]) then
            return true
        end
    end
    return false
end

local function Commit(seat, amount)
    seat.stack = seat.stack - amount
    seat.streetBet = seat.streetBet + amount
    seat.committed = seat.committed + amount
    if seat.stack == 0 then
        seat.allIn = true
    end
end

function Betting.BeginStreet(hand, firstSeat, minimumBet, openingBet, preserveStreetBets)
    if
        type(hand) ~= "table"
        or not IsInteger(firstSeat)
        or firstSeat < 1
        or firstSeat > hand.maxSeats
        or not IsInteger(minimumBet)
        or minimumBet < 1
        or not IsInteger(openingBet)
        or openingBet < 0
    then
        return false, "invalid_betting_state"
    end
    for seatNumber = 1, hand.maxSeats do
        local seat = hand.seats[seatNumber]
        if seat and seat.inHand then
            if not preserveStreetBets then
                seat.streetBet = 0
            end
            seat.acted = false
            seat.lastActionBet = nil
        end
    end
    hand.betting = {
        currentBet = openingBet,
        lastFullRaiseSize = minimumBet,
        actorSeat = nil,
    }
    if not Betting.IsComplete(hand) then
        hand.betting.actorSeat = FindActor(hand, firstSeat)
    end
    return true
end

function Betting.IsComplete(hand)
    if CountContenders(hand) <= 1 then
        return true
    end
    local actionableCount, soleActionable = 0, nil
    for seatNumber = 1, hand.maxSeats do
        local seat = hand.seats[seatNumber]
        if IsActionable(seat) then
            actionableCount = actionableCount + 1
            soleActionable = seat
            if actionableCount > 1 then
                break
            end
        end
    end
    if actionableCount == 0 then
        return true
    end
    if actionableCount == 1 and soleActionable.streetBet >= hand.betting.currentBet then
        return true
    end
    for seatNumber = 1, hand.maxSeats do
        if NeedsAction(hand, hand.seats[seatNumber]) then
            return false
        end
    end
    return true
end

function Betting.GetLegalActions(hand, seatNumber)
    if not hand.betting or hand.betting.actorSeat ~= seatNumber then
        return nil, "not_turn"
    end
    local seat = hand.seats[seatNumber]
    if not IsActionable(seat) then
        return nil, "not_actionable"
    end
    local currentBet = hand.betting.currentBet
    local toCall = math.max(0, currentBet - seat.streetBet)
    local callAmount = math.min(toCall, seat.stack)
    local maxTarget = seat.streetBet + seat.stack
    local raisingReopened = seat.lastActionBet == nil
        or currentBet - seat.lastActionBet >= hand.betting.lastFullRaiseSize
    local opponentCanRespond = HasOpponentWhoCanRespond(hand, seatNumber)
    local minimumTarget = currentBet + hand.betting.lastFullRaiseSize
    local canIncrease = opponentCanRespond and raisingReopened and maxTarget > currentBet
    local allInIncreases = maxTarget > currentBet
    return {
        fold = true,
        check = toCall == 0,
        call = toCall > 0,
        callAmount = callAmount,
        toCall = toCall,
        bet = currentBet == 0 and canIncrease and maxTarget >= minimumTarget,
        raise = currentBet > 0 and canIncrease and maxTarget >= minimumTarget,
        allIn = seat.stack > 0 and (not allInIncreases or canIncrease),
        minTarget = minimumTarget,
        maxTarget = maxTarget,
        raisingReopened = raisingReopened,
    }
end

function Betting.Apply(hand, seatNumber, action, targetAmount)
    local legal, reason = Betting.GetLegalActions(hand, seatNumber)
    if not legal then
        return nil, reason
    end
    if type(action) ~= "string" then
        return nil, "invalid_action"
    end
    local seat = hand.seats[seatNumber]
    local previousBet = hand.betting.currentBet
    local paid, fullRaise, shortRaise = 0, false, false
    if action == "fold" and legal.fold then
        seat.folded = true
    elseif action == "check" and legal.check then
    elseif action == "call" and legal.call then
        paid = legal.callAmount
    elseif action == "bet" and legal.bet or action == "raise" and legal.raise then
        if not IsInteger(targetAmount) or targetAmount < legal.minTarget or targetAmount > legal.maxTarget then
            return nil, action == "bet" and "invalid_bet" or "invalid_raise"
        end
        paid = targetAmount - seat.streetBet
    elseif action == "all_in" and legal.allIn then
        if targetAmount ~= nil and targetAmount ~= legal.maxTarget then
            return nil, "invalid_all_in"
        end
        paid = seat.stack
    else
        return nil, "illegal_action"
    end
    Commit(seat, paid)
    if seat.streetBet > previousBet then
        local increase = seat.streetBet - previousBet
        hand.betting.currentBet = seat.streetBet
        fullRaise = increase >= hand.betting.lastFullRaiseSize
        shortRaise = not fullRaise
        if fullRaise then
            hand.betting.lastFullRaiseSize = increase
        end
    end
    seat.acted = true
    seat.lastActionBet = hand.betting.currentBet
    local complete = Betting.IsComplete(hand)
    hand.betting.actorSeat = complete and nil or FindActor(hand, seatNumber % hand.maxSeats + 1)
    if not complete and not hand.betting.actorSeat then
        return nil, "invalid_betting_state"
    end
    return {
        paid = paid,
        target = seat.streetBet,
        fullRaise = fullRaise,
        shortRaise = shortRaise,
        complete = complete,
        actorSeat = hand.betting.actorSeat,
    }
end

function Betting.CountContenders(hand)
    return CountContenders(hand)
end

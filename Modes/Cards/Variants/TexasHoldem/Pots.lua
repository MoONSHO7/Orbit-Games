local _, Games = ...
local Cards = Games.Cards
local Holdem = Cards.TexasHoldem

local Pots = {}
Holdem.Pots = Pots

local function CopyArray(values)
    local copy = {}
    for index, value in ipairs(values) do
        copy[index] = value
    end
    return copy
end

local function AddAmount(amounts, seatNumber, amount)
    amounts[seatNumber] = (amounts[seatNumber] or 0) + amount
end

local function ClockwiseDistance(seatNumber, buttonSeat, maxSeats)
    local distance = (seatNumber - buttonSeat) % maxSeats
    return distance == 0 and maxSeats or distance
end

function Pots.Build(seats, maxSeats)
    local levels, seenLevels, totalCommitted = {}, {}, 0
    for seatNumber = 1, maxSeats do
        local seat = seats[seatNumber]
        if seat and seat.committed > 0 then
            totalCommitted = totalCommitted + seat.committed
            if not seenLevels[seat.committed] then
                levels[#levels + 1] = seat.committed
                seenLevels[seat.committed] = true
            end
        end
    end
    table.sort(levels)
    local pots, refunds, previousLevel, distributed = {}, {}, 0, 0
    for _, level in ipairs(levels) do
        local contributors, eligible = {}, {}
        for seatNumber = 1, maxSeats do
            local seat = seats[seatNumber]
            if seat and seat.committed >= level then
                contributors[#contributors + 1] = seatNumber
                if seat.inHand and not seat.folded then
                    eligible[#eligible + 1] = seatNumber
                end
            end
        end
        local amount = (level - previousLevel) * #contributors
        if #contributors == 1 then
            AddAmount(refunds, contributors[1], amount)
        elseif #eligible == 0 then
            return nil, "pot_without_eligible_player"
        else
            pots[#pots + 1] = {
                amount = amount,
                cap = level,
                contributors = contributors,
                eligible = eligible,
            }
        end
        distributed = distributed + amount
        previousLevel = level
    end
    if distributed ~= totalCommitted then
        return nil, "chip_conservation_failed"
    end
    return { pots = pots, refunds = refunds, total = totalCommitted }
end

function Pots.Settle(hand)
    local built, reason = Pots.Build(hand.seats, hand.maxSeats)
    if not built then
        return nil, reason
    end
    local evaluations, payouts, potResults = {}, {}, {}
    for _, pot in ipairs(built.pots) do
        local bestScore, winners = nil, {}
        for _, seatNumber in ipairs(pot.eligible) do
            local evaluation = evaluations[seatNumber]
            if not evaluation and #pot.eligible > 1 then
                local seat = hand.seats[seatNumber]
                local cards = { seat.holeCards[1], seat.holeCards[2] }
                for _, cardId in ipairs(hand.board) do
                    cards[#cards + 1] = cardId
                end
                evaluation, reason = Cards.HandEvaluator.Evaluate(cards)
                if not evaluation then
                    return nil, reason
                end
                evaluations[seatNumber] = evaluation
            end
            local score = evaluation and evaluation.score or 0
            if bestScore == nil or score > bestScore then
                bestScore, winners = score, { seatNumber }
            elseif score == bestScore then
                winners[#winners + 1] = seatNumber
            end
        end
        table.sort(winners, function(left, right)
            return ClockwiseDistance(left, hand.buttonSeat, hand.maxSeats)
                < ClockwiseDistance(right, hand.buttonSeat, hand.maxSeats)
        end)
        local share = math.floor(pot.amount / #winners)
        local oddChips = pot.amount % #winners
        for index, seatNumber in ipairs(winners) do
            AddAmount(payouts, seatNumber, share + (index <= oddChips and 1 or 0))
        end
        potResults[#potResults + 1] = {
            amount = pot.amount,
            cap = pot.cap,
            eligible = CopyArray(pot.eligible),
            winners = CopyArray(winners),
        }
    end
    local distributed = 0
    for _, amount in pairs(payouts) do
        distributed = distributed + amount
    end
    for _, amount in pairs(built.refunds) do
        distributed = distributed + amount
    end
    if distributed ~= built.total then
        return nil, "chip_conservation_failed"
    end
    return {
        pots = potResults,
        payouts = payouts,
        refunds = built.refunds,
        evaluations = evaluations,
        total = built.total,
    }
end

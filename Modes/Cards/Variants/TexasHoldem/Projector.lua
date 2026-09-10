local _, Games = ...
local Cards = Games.Cards
local Holdem = Cards.TexasHoldem

local Projector = {}
Holdem.Projector = Projector

local function Copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, field in pairs(value) do
        copy[Copy(key, seen)] = Copy(field, seen)
    end
    return copy
end

local function PublicSettlement(settlement)
    if not settlement then
        return nil
    end
    local public = {
        pots = Copy(settlement.pots),
        payouts = Copy(settlement.payouts),
        refunds = Copy(settlement.refunds),
        total = settlement.total,
        evaluations = {},
    }
    for seatNumber, evaluation in pairs(settlement.evaluations) do
        public.evaluations[seatNumber] = {
            category = evaluation.category,
            categoryRank = evaluation.categoryRank,
            kickers = Copy(evaluation.kickers),
            score = evaluation.score,
        }
    end
    return public
end

function Projector.Build(model, recipientId)
    local projection = {
        activityId = "texas_holdem",
        activityVersion = Cards.ACTIVITY_VERSION,
        state = model.state,
        revision = model.revision,
        rules = Copy(model.rules),
        seats = {},
    }
    local recipient = recipientId and model.seatsById[recipientId] or nil
    local hand = model.hand
    for seatNumber = 1, model.rules.maxPlayers do
        local seat = model.seats[seatNumber]
        if seat then
            local publicSeat = {
                seat = seatNumber,
                id = seat.id,
                name = seat.name,
                stack = seat.stack,
                sittingOut = seat.sittingOut,
            }
            if hand then
                publicSeat.inHand = seat.inHand
                publicSeat.folded = seat.folded
                publicSeat.allIn = seat.allIn
                publicSeat.streetBet = seat.streetBet
                publicSeat.committed = seat.committed
                if seat.inHand and (seat == recipient or hand.showdown and not seat.folded) then
                    publicSeat.holeCards = Copy(seat.holeCards)
                end
            end
            projection.seats[#projection.seats + 1] = publicSeat
        end
    end
    if not hand then
        return projection
    end
    projection.handId = hand.id
    projection.buttonSeat = hand.buttonSeat
    projection.smallBlindSeat = hand.smallBlindSeat
    projection.bigBlindSeat = hand.bigBlindSeat
    projection.board = Copy(hand.board)
    projection.actions = Copy(hand.actions)
    projection.showdown = hand.showdown == true
    local pot = 0
    for seatNumber = 1, model.rules.maxPlayers do
        local seat = model.seats[seatNumber]
        pot = pot + (seat and seat.committed or 0)
    end
    projection.pot = pot
    if hand.betting then
        projection.actorSeat = hand.betting.actorSeat
        projection.currentBet = hand.betting.currentBet
        projection.minimumRaise = hand.betting.lastFullRaiseSize
        projection.actionStartedAt = hand.actionStartedAt
        projection.actionDeadline = hand.actionDeadline
        if recipient and recipient.seat == hand.betting.actorSeat then
            projection.legalActions = Holdem.Betting.GetLegalActions(hand, recipient.seat)
        end
    end
    projection.settlement = PublicSettlement(hand.settlement)
    return projection
end

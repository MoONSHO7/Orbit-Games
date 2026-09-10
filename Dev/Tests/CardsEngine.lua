return function(Games)
    local Cards = Games.Cards
    local Holdem = Cards.TexasHoldem
    local assertions = 0

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Card(code)
        local cardId = Cards.CardCatalog:FromCode(code)
        Check(cardId ~= nil, "fixture card code exists: " .. code)
        return cardId
    end

    local function Ordered(prefix)
        local order, used = {}, {}
        for _, cardId in ipairs(prefix or {}) do
            Check(not used[cardId], "injected deck prefix has unique cards")
            order[#order + 1] = cardId
            used[cardId] = true
        end
        for cardId = 1, Cards.CardCatalog.COUNT do
            if not used[cardId] then
                order[#order + 1] = cardId
            end
        end
        return order
    end

    local function Rules(overrides)
        local raw = {
            maxPlayers = 8,
            buyIn = 1000,
            smallBlind = 5,
            bigBlind = 10,
            actionSeconds = 15,
        }
        for key, value in pairs(overrides or {}) do
            raw[key] = value
        end
        return raw
    end

    local function Players(stacks)
        local players = {}
        for index, stack in ipairs(stacks) do
            players[index] = { seat = index, id = "player-" .. index, name = "Player " .. index, stack = stack }
        end
        return players
    end

    local function NewModel(stacks, overrides)
        local model, reason = Holdem.Model.New(Rules(overrides), Players(stacks))
        Check(model ~= nil, "valid table model constructs: " .. tostring(reason))
        return model
    end

    local function FindSeat(projection, seatNumber)
        for _, seat in ipairs(projection.seats) do
            if seat.seat == seatNumber then
                return seat
            end
        end
    end

    local function ContainsForbiddenKey(value)
        if type(value) ~= "table" then
            return false
        end
        for key, child in pairs(value) do
            if key == "deck" or key == "order" or key == "burnCards" then
                return true
            end
            if ContainsForbiddenKey(child) then
                return true
            end
        end
        return false
    end

    Same(Cards.CardCatalog.COUNT, 52, "standard deck has exactly 52 cards")
    for suitIndex, suit in ipairs({ "C", "D", "H", "S" }) do
        for rankIndex, rank in ipairs({ "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A" }) do
            local expectedId = (suitIndex - 1) * 13 + rankIndex
            Same(Cards.CardCatalog:FromCode(rank .. suit), expectedId, "atlas card ID is suit-major")
            Same(Cards.CardCatalog:GetCode(expectedId), rank .. suit, "card code round-trips")
            Same(Cards.CardCatalog:GetRank(expectedId), rankIndex + 1, "rank follows two-through-ace order")
            Same(Cards.CardCatalog:GetSuit(expectedId), suitIndex, "suit index follows atlas order")
        end
    end
    Same(Cards.CardCatalog:FromCode("as"), 52, "card parsing is case-insensitive")
    Same(Cards.CardCatalog:GetCode(0), nil, "out-of-range card IDs reject")

    local canonical = Cards.CardCatalog:GetAll()
    local deck = Cards.Deck.New(canonical)
    canonical[1] = 52
    Same(deck:Draw(1)[1], 1, "deck owns a detached injected order")
    Same(deck:Remaining(), 51, "draw advances the private cursor")
    Same(#deck:Draw(51), 51, "remaining cards draw exactly once")
    Same(deck:Draw(1), nil, "exhausted deck rejects")
    local duplicate = Cards.CardCatalog:GetAll()
    duplicate[52] = duplicate[1]
    Same(Cards.Deck.New(duplicate), nil, "duplicate cards reject transactionally")
    local randomCalls = 0
    local shuffled = Cards.Deck.Shuffle(function(limit)
        randomCalls = randomCalls + 1
        return limit
    end)
    Same(randomCalls, 51, "Fisher-Yates consumes one injected result per swap")
    for cardId = 1, 52 do
        Same(shuffled[cardId], cardId, "maximum injected index preserves canonical order")
    end
    Same(
        Cards.Deck.Shuffle(function()
            return 0
        end),
        nil,
        "invalid injected random results reject"
    )

    local categories = {
        { "high_card", { "AS", "KD", "9C", "7H", "3D" } },
        { "one_pair", { "AS", "AD", "9C", "7H", "3D" } },
        { "two_pair", { "AS", "AD", "9C", "9H", "3D" } },
        { "three_of_a_kind", { "AS", "AD", "AC", "9H", "3D" } },
        { "straight", { "9S", "8D", "7C", "6H", "5D" } },
        { "flush", { "AS", "JS", "9S", "7S", "3S" } },
        { "full_house", { "AS", "AD", "AC", "9H", "9D" } },
        { "four_of_a_kind", { "AS", "AD", "AC", "AH", "9D" } },
        { "straight_flush", { "9S", "8S", "7S", "6S", "5S" } },
    }
    local previousScore
    for _, fixture in ipairs(categories) do
        local cards = {}
        for _, code in ipairs(fixture[2]) do
            cards[#cards + 1] = Card(code)
        end
        local evaluated = Cards.HandEvaluator.Evaluate(cards)
        Same(evaluated.category, fixture[1], "five-card category evaluates exactly")
        Check(not previousScore or evaluated.score > previousScore, "category scores are strictly ordered")
        previousScore = evaluated.score
    end
    local wheel = Cards.HandEvaluator.Evaluate({ Card("AS"), Card("2D"), Card("3C"), Card("4H"), Card("5D") })
    Same(wheel.category, "straight", "ace-low wheel is a straight")
    Same(wheel.kickers[1], 5, "wheel compares as five-high")
    local sixHigh = Cards.HandEvaluator.Evaluate({ Card("2S"), Card("3D"), Card("4C"), Card("5H"), Card("6D") })
    Same(Cards.HandEvaluator.Compare(sixHigh, wheel), 1, "six-high straight beats the wheel")
    local sevenCards = Cards.HandEvaluator.Evaluate({
        Card("AS"),
        Card("AD"),
        Card("AC"),
        Card("KH"),
        Card("KD"),
        Card("KC"),
        Card("2S"),
    })
    Same(sevenCards.category, "full_house", "seven-card evaluator chooses the strongest five")
    Same(sevenCards.kickers[1], 14, "higher trip becomes the full-house trips")
    Same(sevenCards.kickers[2], 13, "remaining trip becomes the pair")
    for index, cardId in ipairs({ Card("AS"), Card("AD"), Card("AC"), Card("KH"), Card("KD") }) do
        Same(sevenCards.cards[index], cardId, "seven-card evaluator retains canonical winning card " .. index)
    end
    Same(
        Cards.HandEvaluator.Evaluate({ Card("AS"), Card("AS"), Card("3C"), Card("4H"), Card("5D") }),
        nil,
        "duplicate evaluation cards reject"
    )

    local normalized = Holdem.Rules.Normalize(Rules())
    Same(normalized.version, 2, "whole-Gold rules use version two")
    Same(normalized.maxPlayers, 8, "eight seats are supported")
    Same(normalized.smallBlind, 5, "small blind remains a whole-Gold unit")
    Same(normalized.bigBlind, 10, "big blind remains a whole-Gold unit")
    Same(Holdem.Rules.SmallBlindForRate(1000, 5), 5, "one-thousand Gold begins at five Gold")
    Same(Holdem.Rules.SmallBlindForRate(1000, 25), 25, "one-thousand Gold ends at twenty-five Gold")
    Same(Holdem.Rules.SmallBlindForRate(100000, 5), 500, "blind range scales with a larger buy-in")
    Same(Holdem.Rules.SmallBlindForRate(10000000, 25), 250000, "maximum buy-in retains the rate cap")
    Same(Holdem.Rules.BlindRateForSmallBlind(100000, 500), 5, "saved small blind resolves its rate")
    Same(Holdem.Rules.BlindRateForSmallBlind(100000, 2500), 25, "saved maximum blind resolves its rate")
    Same(Holdem.Rules.SmallBlindForRate(999, 5), nil, "blind rate rejects a below-minimum buy-in")
    Same(Holdem.Rules.SmallBlindForRate(1000, 26), nil, "blind rate rejects an unsupported detent")
    for _, invalid in ipairs({
        { version = 1 },
        { maxPlayers = 9 },
        { smallBlind = 10, bigBlind = 10 },
        { smallBlind = 11, bigBlind = 10 },
        { smallBlind = 26, bigBlind = 52 },
        { buyIn = 999 },
        { buyIn = 10000001 },
        { actionSeconds = 14 },
        { actionSeconds = 16 },
        { buyIn = 100.5 },
        { mystery = 1 },
    }) do
        local raw = Rules()
        for key, value in pairs(invalid) do
            raw[key] = value
        end
        Same(Holdem.Rules.Normalize(raw), nil, "invalid authored table rule rejects")
    end
    Same(Holdem.Model.New(Rules(), Players({ 1, 1, 1, 1, 1, 1, 1, 1, 1 })), nil, "ninth seat rejects")

    local sparse = Holdem.Model.New(Rules(), {
        { seat = 2, id = "sparse-2", name = "Sparse Two", stack = 1000 },
        { seat = 8, id = "sparse-8", name = "Sparse Eight", stack = 1000 },
    })
    Check(sparse:StartHand("sparse-heads-up", 8, Ordered(), 0), "sparse heads-up seats start")
    Same(sparse.hand.smallBlindSeat, 8, "sparse button posts the heads-up small blind")
    Same(sparse.hand.bigBlindSeat, 2, "clockwise traversal wraps across empty seats")
    Same(sparse.hand.betting.actorSeat, 8, "sparse button still acts first preflop")

    local headsUp = NewModel({ 1000, 1000 })
    local headOrder =
        Ordered({ Card("2C"), Card("AS"), Card("2D"), Card("AH"), Card("3C"), Card("4C"), Card("5C"), Card("6C") })
    Check(headsUp:StartHand("heads-up-order", 1, headOrder, 0), "heads-up hand starts")
    Same(headsUp.hand.smallBlindSeat, 1, "heads-up button posts the small blind")
    Same(headsUp.hand.bigBlindSeat, 2, "heads-up opponent posts the big blind")
    Same(headsUp.hand.betting.actorSeat, 1, "heads-up button acts first before the flop")
    Same(headsUp.hand.seats[1].holeCards[1], Card("AS"), "deal begins left of the button")
    Same(headsUp.hand.seats[2].holeCards[1], Card("2C"), "non-button receives the first card")
    local playerProjection = headsUp:GetProjection("player-1")
    Same(#FindSeat(playerProjection, 1).holeCards, 2, "recipient sees both own hole cards")
    Same(FindSeat(playerProjection, 2).holeCards, nil, "recipient never receives opponent hole cards")
    local spectatorProjection = headsUp:GetProjection(nil)
    Same(FindSeat(spectatorProjection, 1).holeCards, nil, "spectator receives no private cards")
    Check(not ContainsForbiddenKey(playerProjection), "projection contains no deck or burn-card fields")
    playerProjection.rules.bigBlind = 999
    FindSeat(playerProjection, 1).holeCards[1] = Card("KS")
    playerProjection.actions[1].paid = 999
    Same(headsUp.rules.bigBlind, 10, "projection rules are detached from the model")
    Same(headsUp.hand.seats[1].holeCards[1], Card("AS"), "projected hole cards are detached")
    Same(headsUp.hand.actions[1].paid, 5, "projected action history is detached")
    Check(headsUp:Act("player-1", "call", nil, 1), "heads-up small blind can call")
    Same(headsUp.hand.betting.actorSeat, 2, "big blind retains its preflop option")
    Check(headsUp:Act("player-2", "check", nil, 2), "big blind checks its option")
    Same(headsUp:GetState(), "flop", "matched preflop action deals the flop")
    Same(headsUp.hand.betting.actorSeat, 2, "non-button acts first after the flop")
    Same(#headsUp.hand.board, 3, "flop deals three public cards")
    Same(#headsUp.hand.burnCards, 1, "flop consumes one private burn card")
    Check(headsUp:Advance(17), "postflop timeout checks when no wager is faced")
    Same(headsUp:GetState(), "flop", "one automatic check passes action without skipping the street")
    Check(headsUp:Act("player-1", "check", nil, 18), "second flop player checks")
    Same(headsUp:GetState(), "turn", "two checks advance from flop to turn")
    Check(headsUp:Act("player-2", "check", nil, 19), "turn first player checks")
    Check(headsUp:Act("player-1", "check", nil, 20), "turn second player checks")
    Same(headsUp:GetState(), "river", "turn completion deals one river card after its burn")
    Check(headsUp:Act("player-2", "check", nil, 21), "river first player checks")
    Check(headsUp:Act("player-1", "check", nil, 22), "river second player checks")
    Same(headsUp:GetState(), "complete", "river completion settles a showdown")
    Same(#headsUp.hand.board, 5, "normal checkdown exposes five community cards")
    Same(#headsUp.hand.burnCards, 3, "normal checkdown consumes three hidden burns")
    Check(headsUp:CheckChipConservation(), "normal multi-street hand conserves every chip")

    local foldHand = NewModel({ 1000, 1000 })
    Check(foldHand:StartHand("fold", 1, Ordered(), 0), "fold fixture starts")
    Check(foldHand:Act("player-1", "fold", nil, 1), "facing blind may fold")
    Same(foldHand:GetState(), "complete", "last contender wins immediately")
    Same(foldHand.seats[1].stack, 995, "folder loses only the posted small blind")
    Same(foldHand.seats[2].stack, 1005, "winner receives both blinds")
    Check(foldHand:CheckChipConservation(), "uncontested payout conserves every chip")
    Same(FindSeat(foldHand:GetProjection("player-1"), 2).holeCards, nil, "uncontested winner need not reveal")

    local timeoutHand = NewModel({ 1000, 1000 })
    Check(timeoutHand:StartHand("timeout", 1, Ordered(), 10), "timeout fixture starts")
    Same(timeoutHand:Advance(24), false, "turn remains active before its deadline")
    Check(timeoutHand:Advance(25), "timeout resolves at the exact deadline")
    Same(timeoutHand:GetState(), "complete", "facing a wager times out to fold")
    Same(timeoutHand.hand.actions[#timeoutHand.hand.actions].automatic, true, "timeout action is explicitly marked")

    local raiseHand = NewModel({ 1000, 1000, 1000 })
    Check(raiseHand:StartHand("raise", 1, Ordered(), 0), "three-player raise fixture starts")
    Same(raiseHand.hand.betting.actorSeat, 1, "first seat after big blind acts preflop")
    local opening = raiseHand:GetLegalActions("player-1")
    Same(opening.minTarget, 20, "minimum preflop raise is one full blind increment")
    Same(raiseHand:Act("player-1", "raise", 19, 1), false, "under-minimum regular raise rejects")
    Check(raiseHand:Act("player-1", "raise", 30, 1), "larger full raise accepts")
    Same(raiseHand.hand.betting.lastFullRaiseSize, 20, "full raise size becomes the next minimum increment")

    local function BettingHand(stacks)
        local hand = { maxSeats = #stacks, seats = {} }
        for index, stack in ipairs(stacks) do
            hand.seats[index] = {
                seat = index,
                stack = stack,
                inHand = true,
                folded = false,
                allIn = false,
                committed = 0,
                streetBet = 0,
            }
        end
        Check(Holdem.Betting.BeginStreet(hand, 1, 100, 0, false), "isolated betting street starts")
        return hand
    end

    local oneShort = BettingHand({ 500, 500, 150 })
    Check(Holdem.Betting.Apply(oneShort, 1, "bet", 100), "full opening bet accepts")
    Check(Holdem.Betting.Apply(oneShort, 2, "call"), "caller acts at the full wager level")
    local short = Holdem.Betting.Apply(oneShort, 3, "all_in")
    Same(short.shortRaise, true, "under-minimum all-in is recorded as a short raise")
    Same(oneShort.betting.actorSeat, 1, "short raise returns action to prior bettor")
    Same(Holdem.Betting.GetLegalActions(oneShort, 1).raisingReopened, false, "one short raise does not reopen betting")
    Same(Holdem.Betting.GetLegalActions(oneShort, 1).raise, false, "closed player cannot raise over one short all-in")

    local cumulative = BettingHand({ 500, 500, 150, 200 })
    Check(Holdem.Betting.Apply(cumulative, 1, "bet", 100), "cumulative fixture opens")
    Check(Holdem.Betting.Apply(cumulative, 2, "call"), "cumulative fixture caller acts")
    Check(Holdem.Betting.Apply(cumulative, 3, "all_in"), "first short all-in accepts")
    Check(Holdem.Betting.Apply(cumulative, 4, "all_in"), "second short all-in accepts")
    local reopened = Holdem.Betting.GetLegalActions(cumulative, 1)
    Same(reopened.raisingReopened, true, "cumulative short raises reaching a full increment reopen betting")
    Same(reopened.minTarget, 300, "reopened minimum uses the last full raise size")

    local shortOpening = BettingHand({ 60, 500, 500 })
    Check(Holdem.Betting.Apply(shortOpening, 1, "all_in"), "short opening all-in accepts")
    Same(shortOpening.betting.currentBet, 60, "short opener establishes only its actual wager")
    local completion = Holdem.Betting.GetLegalActions(shortOpening, 2)
    Same(completion.minTarget, 160, "raising a short opener adds the full minimum increment")
    Same(Holdem.Betting.Apply(shortOpening, 2, "raise", 100), nil, "no-limit betting cannot complete a short opener")
    Check(Holdem.Betting.Apply(shortOpening, 2, "raise", 160), "full raise over a short opener accepts")
    Same(shortOpening.betting.lastFullRaiseSize, 100, "raise size excludes the short opening wager")
    Same(Holdem.Betting.GetLegalActions(shortOpening, 3).minTarget, 260, "next raise adds the last full increment")

    local shortRaises = BettingHand({ 60, 120, 500, 500 })
    Check(Holdem.Betting.Apply(shortRaises, 1, "all_in"), "short opener accepts")
    Check(Holdem.Betting.Apply(shortRaises, 2, "all_in"), "second short all-in accepts")
    Same(
        Holdem.Betting.GetLegalActions(shortRaises, 3).minTarget,
        220,
        "crossing the minimum does not enlarge a short raise"
    )

    local potSeats = {
        [1] = { inHand = true, folded = false, committed = 100, holeCards = { Card("AS"), Card("5S") } },
        [2] = { inHand = true, folded = false, committed = 200, holeCards = { Card("KH"), Card("KD") } },
        [3] = { inHand = true, folded = false, committed = 300, holeCards = { Card("QH"), Card("QD") } },
        [4] = { inHand = true, folded = true, committed = 300, holeCards = { Card("JH"), Card("JD") } },
    }
    local built = Holdem.Pots.Build(potSeats, 4)
    Same(#built.pots, 3, "three contribution levels create main and two side pots")
    Same(built.pots[1].amount, 400, "main pot contains every first hundred")
    Same(built.pots[2].amount, 300, "first side pot contains three second hundreds")
    Same(built.pots[3].amount, 200, "last side pot includes folded funding")
    Same(#built.pots[3].eligible, 1, "folded contributor cannot win a side pot")
    local settled = Holdem.Pots.Settle({
        seats = potSeats,
        maxSeats = 4,
        buttonSeat = 4,
        board = { Card("2C"), Card("3D"), Card("4H"), Card("9S"), Card("KC") },
    })
    Same(settled.payouts[1], 400, "short-stack straight wins the main pot")
    Same(settled.payouts[2], 300, "middle stack wins its side pot")
    Same(settled.payouts[3], 200, "deep stack wins the uncontested final side pot")
    local refunds = Holdem.Pots.Build({
        [1] = { inHand = true, folded = false, committed = 100 },
        [2] = { inHand = true, folded = false, committed = 50 },
    }, 2)
    Same(refunds.pots[1].amount, 100, "matched contribution becomes a pot")
    Same(refunds.refunds[1], 50, "uncalled excess is returned rather than awarded")

    local tieSeats = {
        [1] = { inHand = true, folded = true, committed = 5, holeCards = { Card("2C"), Card("3C") } },
        [2] = { inHand = true, folded = false, committed = 5, holeCards = { Card("4C"), Card("5C") } },
        [3] = { inHand = true, folded = false, committed = 5, holeCards = { Card("6C"), Card("7C") } },
    }
    local tied = Holdem.Pots.Settle({
        seats = tieSeats,
        maxSeats = 3,
        buttonSeat = 1,
        board = { Card("TS"), Card("JS"), Card("QS"), Card("KS"), Card("AS") },
    })
    Same(tied.payouts[2], 8, "first tied winner left of button receives the odd chip")
    Same(tied.payouts[3], 7, "remaining tied winner receives the equal share")

    local allIn = NewModel({ 20, 20 })
    Check(allIn:StartHand("all-in-runout", 1, Ordered(), 0), "all-in runout fixture starts")
    Check(allIn:Act("player-1", "all_in", nil, 1), "small blind can move all-in")
    Check(allIn:Act("player-2", "call", nil, 2), "big blind calls the all-in")
    Same(allIn:GetState(), "complete", "all-in call automatically runs every remaining street")
    Same(#allIn.hand.board, 5, "automatic runout deals all five community cards")
    Same(#allIn.hand.burnCards, 3, "automatic runout burns before flop, turn and river")
    Same(allIn.hand.showdown, true, "multiple remaining contenders reach showdown")
    Check(allIn:CheckChipConservation(), "showdown settlement conserves every chip")
    local showdown = allIn:GetProjection(nil)
    Same(#FindSeat(showdown, 1).holeCards, 2, "showdown reveals first contender")
    Same(#FindSeat(showdown, 2).holeCards, 2, "showdown reveals second contender")
    for seatNumber, payout in pairs(allIn.hand.settlement.payouts) do
        if payout > 0 then
            local seat = FindSeat(showdown, seatNumber)
            local cards = { seat.holeCards[1], seat.holeCards[2] }
            for _, cardId in ipairs(showdown.board) do
                cards[#cards + 1] = cardId
            end
            local rebuilt = Cards.HandEvaluator.Evaluate(cards)
            local authoritative = allIn.hand.settlement.evaluations[seatNumber]
            Same(rebuilt.category, authoritative.category, "public showdown rebuilds the winner category")
            Same(rebuilt.score, authoritative.score, "public showdown rebuilds the winner score")
            for cardIndex, cardId in ipairs(authoritative.cards) do
                Same(rebuilt.cards[cardIndex], cardId, "public showdown rebuilds winning card " .. cardIndex)
            end
        end
    end
    Check(not ContainsForbiddenKey(showdown), "completed projection still hides deck and burns")

    local lobby = NewModel({ 0, 1000 })
    Same(lobby:Rebuy("player-1", 999), false, "rebuy must equal the configured buy-in")
    Check(lobby:Rebuy("player-1", 1000), "busted player may rebuy between hands")
    Same(lobby:Rebuy("player-1", 1000), false, "player with chips cannot rebuy again")
    Check(lobby:SetSittingOut("player-1", true), "player may sit out between hands")
    local cashOut = lobby:RemovePlayer("player-1")
    Same(cashOut, 1000, "removing a player returns its exact cash-out stack")
    Check(lobby:CheckChipConservation(), "buy-in and cash-out update the session chip boundary")

    return assertions
end

local PLAYER_COUNT = 8
local MAX_CPU_STEPS = 16
local MAX_HAND_STEPS = 64
local RESULT_HOLD_SECONDS = 8
local RANDOM_CANARY_SEED = 8675309

return function(Games, development)
    local Cards, Quiz = Games.Cards, Games.Quiz
    local Table, Dev = Cards.Table, Games.Development
    local assertions = 0

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Clone(value, seen)
        if type(value) ~= "table" then
            return value
        end
        seen = seen or {}
        if seen[value] then
            return seen[value]
        end
        local copy = {}
        seen[value] = copy
        for key, item in pairs(value) do
            copy[key] = Clone(item, seen)
        end
        return copy
    end

    local function Equal(actual, expected, path, seen)
        if type(expected) ~= "table" then
            Same(actual, expected, path)
            return
        end
        Same(type(actual), "table", path .. " remains a table")
        seen = seen or {}
        if seen[actual] then
            Same(seen[actual], expected, path .. " retains shared references")
            return
        end
        seen[actual] = expected
        for key, value in pairs(expected) do
            Equal(actual[key], value, path .. "." .. tostring(key), seen)
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, path .. " adds no unexpected field " .. tostring(key))
        end
    end

    local function World()
        return {
            saved = OrbitGamesDB,
            store = Cards.Store,
            cardsSession = Cards.Session,
            cardsController = Cards.Controller,
            quizSession = Quiz.Session,
            quizController = Quiz.Controller,
            discovery = Games.Discovery,
            comms = Games.Comms,
            runtime = Games.Main,
            addonSends = #Test.addonSent,
            visibleSends = #Test.sent,
            channelJoins = #Test.joins,
        }
    end

    local function Isolated(action, message)
        local before = Clone(World())
        local root, database = OrbitGamesDB, Cards.Store.db
        action()
        Equal(World(), before, message)
        Same(OrbitGamesDB, root, message .. " retains the SavedVariables root")
        Same(Cards.Store.db, database, message .. " retains the Cards database object")
        Same(OrbitGamesDB.modes.cards, database, message .. " retains Cards storage under the root")
    end

    local function NoChat(before, message)
        Same(#Test.messages, before, message .. " emits no visible chat")
    end

    local function FindSeat(view, playerId)
        for _, seat in ipairs(view.seats or {}) do
            if seat.id == playerId then
                return seat
            end
        end
    end

    local function FindDisplayRow(playerId)
        for _, row in ipairs(Table.seats or {}) do
            if row:IsShown() and row.playerId == playerId then
                return row
            end
        end
    end

    local function Pulse(preview, ticker)
        Test.now = math.max(Test.now + 1, preview.nextStepAt or Test.now)
        ticker.callback()
        Same(#Test.errors, 0, "computer-player ticker does not reach the WoW error handler")
    end

    local function DeckSignature(order)
        return table.concat(order, ",")
    end

    local function CheckPermutation(order, message)
        Same(#order, Cards.CardCatalog.COUNT, message .. " contains every card")
        local seen = {}
        for position, cardId in ipairs(order) do
            Check(
                Cards.CardCatalog:IsCard(cardId) and not seen[cardId],
                message .. " has one unique valid card at position " .. position
            )
            seen[cardId] = true
        end
    end

    Same(Table.previewDriver, nil, "addon loading never enables a Cards preview driver")
    if not development then
        Same(Dev, nil, "packaged addon has no development module")
        Same(SLASH_ORBITGAMESDEV1, nil, "packaged addon has no developer slash command")
        Same(SlashCmdList.ORBITGAMESDEV, nil, "packaged addon has no developer command handler")
        Same(Table.frame, nil, "packaged loading does not allocate the Cards table")
        return assertions
    end

    Check(Dev ~= nil, "source checkout loads the development module")
    Same(type(Dev.cardsPreview), "table", "development module owns one computer-player driver")
    local preview = Dev.cardsPreview
    Check(not preview.active, "computer-player preview starts inactive")
    Same(preview.model, nil, "computer-player model is allocated only on demand")
    Same(preview.ticker, nil, "computer-player ticker is allocated only on demand")

    local function Blocked(install, restore, message)
        install()
        local messages, tickers = #Test.messages, #Test.tickers
        Isolated(function()
            Check(not Dev:ShowCards(), message .. " is rejected")
        end, message .. " cannot be replaced by a computer table")
        NoChat(messages, message .. " rejection")
        Same(#Test.tickers, tickers, message .. " rejection creates no ticker")
        Check(not preview.active, message .. " rejection leaves the preview inactive")
        Same(preview.model, nil, message .. " rejection creates no model")
        Same(Table.previewDriver, nil, message .. " rejection installs no table driver")
        restore()
    end

    local quizClient = Quiz.Session.client
    Blocked(function()
        Quiz.Session.client = { testMembership = true }
    end, function()
        Quiz.Session.client = quizClient
    end, "a real Quiz membership")

    local cardsGame = Cards.Controller.game
    Blocked(function()
        Cards.Controller.game = { testGame = true }
    end, function()
        Cards.Controller.game = cardsGame
    end, "a real Cards controller")

    Blocked(function()
        Table:SetEditing(true)
        Table:StartDrag()
    end, function()
        Table.frame:StopMovingOrSizing()
        Table.dragging = false
        Table:SetEditing(false)
    end, "an active Cards drag")

    local originalRandom, originalRandomSeed = math.random, math.randomseed
    originalRandomSeed(RANDOM_CANARY_SEED)
    local expectedFirstRandom, expectedSecondRandom = originalRandom(), originalRandom()
    originalRandomSeed(RANDOM_CANARY_SEED)
    Same(originalRandom(), expectedFirstRandom, "global random canary resets reproducibly")
    local randomCalls, randomSeedCalls = 0, 0
    math.random = function(...)
        randomCalls = randomCalls + 1
        return originalRandom(...)
    end
    math.randomseed = function(...)
        randomSeedCalls = randomSeedCalls + 1
        return originalRandomSeed(...)
    end
    local tickerCount, messages = #Test.tickers, #Test.messages
    Isolated(function()
        SlashCmdList.ORBITGAMESDEV("  CaRdS  ")
    end, "starting the computer table remains outside production state")
    math.random, math.randomseed = originalRandom, originalRandomSeed
    Same(randomCalls, 0, "computer table consumes no global random values")
    Same(randomSeedCalls, 0, "computer table never reseeds the global random stream")
    Same(originalRandom(), expectedSecondRandom, "computer table leaves captured global random state unchanged")
    NoChat(messages, "computer table start")
    Same(#Test.tickers, tickerCount + 1, "computer table owns one transient ticker")
    Check(preview.active, "computer-player driver becomes active")
    Check(preview.model ~= nil, "computer-player driver owns a real model")
    Same(getmetatable(preview.model), Cards.TexasHoldem.Model, "computer table uses the production Hold'em model")
    Same(preview.ticker, Test.tickers[#Test.tickers], "development driver owns the newly allocated ticker")
    Check(preview.ticker.active, "computer-player ticker starts active")
    Check(
        type(preview.ticker.interval) == "number" and preview.ticker.interval > 0,
        "computer-player ticker has a delay"
    )
    Same(Table.previewDriver, preview, "real Cards table renders through the development driver")
    Check(Table.frame and Table.frame:IsShown(), "computer table shows the production Cards frame")
    Same(Dev.enabled, false, "computer table does not enable dummy discovery listings")
    Same(Games.UI.gamePreview, nil, "computer table does not replace real discovery data")

    local view = preview:GetView()
    Same(preview.model:GetState(), "preflop", "computer table starts a real Hold'em hand")
    Same(view.state, preview.model:GetState(), "driver projects the real model state")
    Same(view.rules.maxPlayers, PLAYER_COUNT, "computer table uses all eight Cards seats")
    Same(#view.seats, PLAYER_COUNT, "projection contains one local and seven computer seats")
    Same(#preview.model.seats, PLAYER_COUNT, "real model owns all eight seats")
    Same(view.currencyMode, Cards.CURRENCY_MODE, "computer table uses the canonical Gold presentation")
    Same(view.allowRebuys, true, "computer table can continue after a sample stack is exhausted")
    Check(type(view.playerId) == "string" and view.playerId ~= "", "projection identifies the local player")
    Check(type(view.session) == "string" and view.session ~= "", "projection has a transient local session identity")
    Same(type(preview.deckRandom), "function", "active computer table owns one private deck random stream")
    local firstDeck = Clone(preview.model.hand.deck.order)
    CheckPermutation(firstDeck, "opening preview deck")
    local dealtCards = {}
    for seatNumber, seat in ipairs(preview.model.seats) do
        Same(#seat.holeCards, 2, "preview deals two private cards to seat " .. seatNumber)
        for _, cardId in ipairs(seat.holeCards) do
            Check(not dealtCards[cardId], "preview hole card is dealt once")
            dealtCards[cardId] = true
        end
    end
    Same(preview.model.hand.deck:Remaining(), 36, "eight complete hands leave thirty-six undealt cards")
    for index, card in ipairs(Table.board) do
        Check(card:IsShown() and card.Face:IsShown(), "preflop renders community-card back " .. index)
        Same(card.cardId, nil, "preflop community slot has no invented card identity " .. index)
        Same(card.concealed, true, "preflop community slot is visibly concealed " .. index)
    end

    local ids, localCount, cpuCount, activeRows = {}, 0, 0, 0
    for seatNumber, seat in ipairs(view.seats) do
        Same(seat.seat, seatNumber, "computer table retains canonical seat order")
        Check(
            type(seat.id) == "string" and seat.id ~= "" and not ids[seat.id],
            "every preview seat has a unique identity"
        )
        Check(type(seat.name) == "string" and seat.name ~= "", "every preview seat has a rendered name")
        ids[seat.id] = true
        if seat.id == view.playerId then
            localCount = localCount + 1
            Same(#seat.holeCards, 2, "local preview seat receives its private hole cards")
        else
            cpuCount = cpuCount + 1
            Same(seat.holeCards, nil, "computer hole cards remain concealed from the local projection")
        end
        local row = FindDisplayRow(seat.id)
        Check(row ~= nil, "production player list renders every projected identity")
        Same(row.seatNumber, seatNumber, "display row retains its canonical seat identity")
        Check(row:IsShown(), "production player row is visible")
        Same(#(row.textures or {}), 3, "production player row owns one active wash, dealer chip and Gold texture")
        Same(row.textures[1], row.ActiveBackground, "production player row's direct texture is the active wash")
        Same(row.textures[2], row.DealerChip, "production player row's second direct texture is the dealer chip")
        Same(row.textures[3], row.GoldIcon, "production player row's third direct texture is the Gold icon")
        if row.ActiveBackground:IsShown() then
            activeRows = activeRows + 1
            Same(seatNumber, view.actorSeat, "only the projected actor owns the production row highlight")
        end
    end
    Same(localCount, 1, "computer table has exactly one local seat")
    Same(cpuCount, PLAYER_COUNT - 1, "computer table has exactly seven CPU seats")
    Same(activeRows, 1, "computer table highlights exactly one acting player row")
    local localRow = FindDisplayRow(view.playerId)
    Same(localRow, Table.playerRowOrder[PLAYER_COUNT], "computer table keeps the local player in the final display row")
    Same(localRow.seatNumber, 1, "final display row retains the local canonical seat")
    for _, card in ipairs(localRow.Cards) do
        Check(card:IsShown() and card.cardId and not card.concealed, "local cards render their real atlas faces")
    end
    for _, seat in ipairs(view.seats) do
        if seat.id ~= view.playerId then
            local row = FindDisplayRow(seat.id)
            for cardIndex, card in ipairs(row.Cards) do
                Check(card:IsShown() and card.Face:IsShown(), "CPU card back is visible " .. cardIndex)
                Check(card.concealed, "CPU card remains private " .. cardIndex)
            end
            Same(row.FoldTint, nil, "active CPU row allocates no obsolete fold tint")
            Same(row.FoldStrikes, nil, "active CPU row allocates no obsolete fold X")
        end
    end

    local ticker, model = preview.ticker, preview.model
    local revisionBeforeComputers = model.revision
    Isolated(function()
        for _ = 1, MAX_CPU_STEPS do
            if preview:GetView().legalActions then
                break
            end
            Pulse(preview, ticker)
        end
    end, "computer turns advance only the transient model")
    view = preview:GetView()
    Check(view.legalActions ~= nil, "computer players advance until the local seat can act")
    Same(view.rules.actionSeconds, 5, "projected timer matches the local autoplay window")
    Same(view.actionDeadline - Test.now, 5, "local seat receives the advertised five seconds")
    Same(Table.timer.maximum, 5, "production timer renders the harness deadline rather than the model failsafe")
    Check(model.revision > revisionBeforeComputers, "computer turns use real model actions")
    local computerAction = model.hand.actions[#model.hand.actions]
    Check(computerAction.seat ~= 1 and computerAction.automatic, "ticker records CPU actions as automatic")
    Same(Table.view.revision, model.revision, "production table refreshes from the advanced model")

    local revisionBeforeLocal = model.revision
    local actionCount = #model.hand.actions
    Isolated(function()
        Check(Table.call:IsEnabled(), "local check or call is enabled by projected legality")
        Table.call:GetScript("OnClick")(Table.call)
    end, "real table input mutates only the transient model")
    Check(model.revision > revisionBeforeLocal, "production action control advances the real model")
    Same(#model.hand.actions, actionCount + 1, "local control submits exactly one action")
    local localAction = model.hand.actions[#model.hand.actions]
    Same(localAction.seat, 1, "production action control targets the local seat")
    Same(localAction.automatic, false, "interactive local action is not marked as CPU autoplay")
    Same(Table.view.revision, model.revision, "table immediately renders the local action")

    local completedHand = preview.handNumber
    Isolated(function()
        for _ = 1, MAX_HAND_STEPS do
            if model:GetState() == "complete" then
                break
            end
            Pulse(preview, ticker)
        end
    end, "computer players finish the hand only inside the transient model")
    Same(model:GetState(), "complete", "computer players reach a complete Hold'em settlement")
    Check(model.hand.showdown, "deterministic opening hand reaches showdown")
    Same(#model.hand.board, 5, "computer players reveal all five community cards")
    Same(#model.hand.burnCards, 3, "completed Hold'em hand burns exactly three cards")
    for _, cardId in ipairs(model.hand.burnCards) do
        Check(not dealtCards[cardId], "preview burn card was not dealt previously")
        dealtCards[cardId] = true
    end
    for _, cardId in ipairs(model.hand.board) do
        Check(not dealtCards[cardId], "preview community card was not dealt previously")
        dealtCards[cardId] = true
    end
    Same(model.hand.deck:Remaining(), 28, "holes, burns and board consume exactly twenty-four cards")
    for index, card in ipairs(Table.board) do
        Check(card:IsShown() and card.Face:IsShown(), "completed hand retains community-card slot " .. index)
    end
    Check(model.hand.settlement ~= nil, "real Hold'em settlement resolves the preview hand")
    Check(model:CheckChipConservation(), "computer-player actions conserve the complete table balance")
    Same(Table.view.state, "complete", "production table renders the completed hand")
    Same(Table.view.settlement.total, model.hand.settlement.total, "table receives the real settlement projection")
    Check(Table.timer:IsShown(), "completed computer hand retains the inactive timer track")
    Check(Table.timer.Track:IsVisible(), "completed computer hand retains the full timer backdrop")
    Same(Table.notice:GetText(), "", "completed computer hand leaves its winner summary unaccompanied")
    Check(not Table.notice:IsShown(), "completed computer hand keeps the redundant status lane collapsed")
    Same(preview.nextStepAt - preview.stepStartedAt, RESULT_HOLD_SECONDS, "computer table holds the outcome for review")
    Isolated(function()
        Test.now = preview.nextStepAt - 0.001
        ticker.callback()
    end, "computer players retain the settled hand before the review deadline")
    Same(preview.handNumber, completedHand, "computer table does not replace the hand before the review deadline")
    Same(model:GetState(), "complete", "settled outcome remains visible throughout the review hold")
    Isolated(function()
        Test.now = preview.nextStepAt
        ticker.callback()
    end, "computer players start the next hand only inside the transient model")
    Same(preview.handNumber, completedHand + 1, "computer table continues into another hand")
    Same(model:GetState(), "preflop", "the next deterministic hand begins at preflop")
    Check(Table.view.actionDeadline ~= nil, "continued table renders the next action timer")
    local secondDeck = Clone(model.hand.deck.order)
    CheckPermutation(secondDeck, "continued preview deck")
    Check(DeckSignature(secondDeck) ~= DeckSignature(firstDeck), "successive preview hands use different decks")

    local messagesBeforeOff = #Test.messages
    Isolated(function()
        SlashCmdList.ORBITGAMESDEV("off")
    end, "stopping the computer table remains outside production state")
    NoChat(messagesBeforeOff, "computer table stop")
    Check(not preview.active, "off deactivates the computer-player driver")
    Same(preview.model, nil, "off releases the transient model")
    Same(preview.deckRandom, nil, "off releases the private deck random stream")
    Same(preview.ticker, nil, "off releases the transient ticker")
    Same(ticker.active, false, "off cancels the owned native ticker")
    Same(Table.previewDriver, nil, "off detaches the production Cards table")
    Check(not Table.frame:IsShown(), "off hides the otherwise idle Cards table")
    Same(Table.timer:GetScript("OnUpdate"), nil, "off leaves no table timer callback")
    Same(#Test.errors, 0, "computer table lifecycle triggers no WoW error handler calls")

    local restartTickerCount = #Test.tickers
    Isolated(function()
        Check(Dev:ShowCards(), "computer table can restart after stopping")
    end, "restarting the computer table remains outside production state")
    Same(#Test.tickers, restartTickerCount + 1, "computer table restart owns a fresh ticker")
    Check(preview.active, "computer-player driver reactivates")
    local restartedDeck = Clone(preview.model.hand.deck.order)
    CheckPermutation(restartedDeck, "restarted opening preview deck")
    Same(
        DeckSignature(restartedDeck),
        DeckSignature(firstDeck),
        "computer table restart reproduces the opening deck sequence"
    )
    local restartedTicker = preview.ticker
    Isolated(function()
        SlashCmdList.ORBITGAMESDEV("off")
    end, "stopping a restarted computer table remains outside production state")
    Check(not preview.active, "second off deactivates the restarted driver")
    Same(preview.deckRandom, nil, "second off releases the restarted private random stream")
    Same(restartedTicker.active, false, "second off cancels the restarted ticker")
    Same(Table.previewDriver, nil, "second off detaches the restarted table driver")
    return assertions
end

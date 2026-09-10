return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local SHORT_PACK = "runtime-short"
    local LONG_PACK = "runtime-long"
    local LEAGUE = "Widget runtime"
    local VOID_LEAGUE = "Widget voids"
    local AUTOMATIC_LEAGUE = "Unattended widget"
    local LETTER_OFFSET = 64
    local REVEAL_SECONDS = 3
    local BOUNDARY_EPSILON = 0.001

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(
            actual == expected,
            (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
        )
    end
    local function Settings(packId)
        local settings = Quiz.Store:GetSettings()
        settings.packId = packId or SHORT_PACK
        return settings
    end
    local function Begin(settings, state)
        Check(Games.Main:Start(settings or Settings()), "widget host starts without a hardware event")
        Same(Quiz.Controller.game.state, state or "open", "host opens or prepares the expected presentation")
        Same(Quiz.Session:GetView().id, Quiz.Controller.game.round.id, "host widget and game share the question")
        return Quiz.Controller.game.round
    end
    local function Close()
        local game = Quiz.Controller.game
        Test.Advance(game.round.deadline - Test.now)
        Same(game.state, "results", "deadline finalizes into results")
        Same(Quiz.Controller.nextAutoAt - Test.now, REVEAL_SECONDS, "results schedule exactly three seconds of reveal")
        return game.lastResult
    end
    local function Next(state)
        Check(Quiz.Controller.nextAutoAt, "results schedule automatic progression")
        local nextAt, round = Quiz.Controller.nextAutoAt, Quiz.Controller.game.round
        Test.Advance(nextAt - Test.now - BOUNDARY_EPSILON)
        Same(Quiz.Controller.game.state, "results", "results remain visible just before the three-second boundary")
        Same(Quiz.Session:GetView().id, round.id, "reveal retains the completed question until the boundary")
        Same(
            Quiz.Session:GetView().correctIndex,
            round.correctIndex,
            "reveal retains the correct answer until the boundary"
        )
        Check(Quiz.Session:GetView().locked, "revealed answers cannot be changed during the result break")
        Test.Advance(nextAt - Test.now)
        Same(Quiz.Controller.game.state, state or "open", "intermission prepares the next question without a click")
        Check(Quiz.Controller.game.round.id > round.id, "the boundary allocates a fresh question automatically")
        Same(Quiz.Session:GetView().correctIndex, nil, "the next question does not inherit the revealed answer")
        if not state or state == "open" then
            Same(Quiz.Controller.game.round.startedAt, nextAt, "a host without peers opens at exactly three seconds")
            Same(
                Quiz.Controller.game.round.deadline - nextAt,
                15,
                "the next question receives its full fifteen-second window"
            )
        end
        return Quiz.Controller.game.round
    end
    local function IgnoreChat(round)
        local previous = round.answers[Test.hostGUID]
        local letter = string.char(LETTER_OFFSET + round.correctIndex)
        for _, event in ipairs({
            "CHAT_MSG_CHANNEL",
            "CHAT_MSG_GUILD",
            "CHAT_MSG_RAID",
            "CHAT_MSG_INSTANCE_CHAT",
            "CHAT_MSG_WHISPER",
        }) do
            for _, text in ipairs({
                letter,
                letter .. ". " .. round.choices[round.correctIndex],
                "!" .. round.id .. " " .. letter,
                "ordinary conversation",
                Test.secret,
            }) do
                Test.Incoming(text, "Chatplayer-TestRealm", "Player-0-CHAT", event)
                Test.Incoming(text, Games.Identity.name, Test.hostGUID, event)
                Same(round.answers["Player-0-CHAT"], nil, "visible chat never creates a participant answer")
                Same(round.answers[Test.hostGUID], previous, "visible chat never changes the host's widget answer")
            end
        end
    end
    local function Standing(_, guid)
        for _, player in ipairs(Quiz.Controller.game:GetStandings()) do
            if player.guid == guid then
                return player
            end
        end
    end
    local function Personal(packId)
        return Quiz.PersonalScores:GetPack(packId or SHORT_PACK)
    end
    local function Restriction(state)
        Games.Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, state)
    end
    local function Encounter(inProgress, payload)
        Test.encounter = inProgress
        Games.Main:OnEvent("ENCOUNTER_STATE_CHANGED", payload)
    end
    local function CheckVoided(message)
        Same(Quiz.Controller.game.state, "paused", message)
        Same(Quiz.Controller.game.round, nil, "interruption discards its exposed round")
        Same(#Quiz.Store:GetStandings(VOID_LEAGUE, "PUBLIC"), 0, "void answers never enter persistent standings")
        Same(#Test.sent, 0, "interruption never emits visible chat")
    end
    local function CheckNoTickers(message)
        for _, ticker in ipairs(Test.tickers) do
            Check(not ticker.active, message)
        end
    end

    Check(Games.Main.initialized, "TOC lifecycle initializes the addon")
    local encounterEventRegistered = false
    for _, frame in ipairs(Test.frames) do
        encounterEventRegistered = encounterEventRegistered
            or frame.events and frame.events.ENCOUNTER_STATE_CHANGED == true
    end
    Check(encounterEventRegistered, "runtime registers the native boss-encounter state event")
    Same(OrbitGamesDB.schemaVersion, 1, "lifecycle owns the generic root database")
    Same(OrbitGamesDB.modes.quiz.schemaVersion, 7, "Quiz data uses the current mode schema")
    Same(Quiz.Store.db, OrbitGamesDB.modes.quiz, "Quiz storage is bound to its root mode subtree")
    Same(Games.Chat, nil, "visible chat transport is absent")
    Same(Games.Main.PublishChat, nil, "manual publication is absent")
    Same(Games.Main.OnChat, nil, "visible chat answer handling is absent")
    Same(Games.Main.JoinChannel, nil, "manual visible-channel joining is absent")
    Same(Quiz.Store:GetSettings().bridgeChat, nil, "host setup has no bridge setting")
    local bundledCount = 0
    for _, pack in ipairs(Quiz:GetPacks()) do
        bundledCount = bundledCount + pack.count
    end
    Check(bundledCount > 0, "bundled questions load before fixture packs")
    Same(#Quiz:GetQuestions("all"), bundledCount, "every bundled question is available before fixture packs")
    Check(
        Quiz:RegisterPack({
            id = SHORT_PACK,
            title = "Runtime short questions",
            questions = {
                {
                    id = "one",
                    prompt = "One plus one?",
                    choices = { "Two", "Three", "Four", "Five" },
                    correctIndex = 1,
                },
                {
                    id = "two",
                    prompt = "Two plus two?",
                    choices = { "Four", "Five", "Six", "Seven" },
                    correctIndex = 1,
                },
                {
                    id = "three",
                    prompt = "Three plus three?",
                    choices = { "Six", "Seven", "Eight", "Nine" },
                    correctIndex = 1,
                },
            },
        }),
        "short fixture pack registers"
    )
    Check(
        Quiz:RegisterPack({
            id = LONG_PACK,
            title = "Runtime long question",
            questions = {
                {
                    id = "long",
                    prompt = string.rep("é", 80),
                    choices = { string.rep("é", 50), string.rep("ö", 50), string.rep("ü", 50), string.rep("à", 50) },
                    correctIndex = 1,
                },
            },
        }),
        "maximum UTF-8 fixture pack registers"
    )

    SlashCmdList.ORBITGAMES("")
    Check(Quiz.Widget.frame:IsShown(), "/og opens a positionable HUD preview")
    Check(Games.UI.frame:IsShown(), "/og opens games and host setup")
    SlashCmdList.ORBITGAMES("status")
    Same(Games.UI.tab, "play", "status opens the visual Games status instead of printing it")
    SlashCmdList.ORBITGAMES("packs")
    Same(Games.UI.tab, "host", "packs opens the Host pack selector instead of printing a list")
    SlashCmdList.ORBITGAMES("scores")
    Same(Games.UI.tab, "results", "scores opens the mode Results page instead of printing rows")
    SlashCmdList.ORBITGAMES("not-a-command")
    Same(Games.UI.tab, "play", "unknown commands fall back to the Games window without printing help")
    Same(#Test.messages, 0, "login and slash commands emit no visible chat")
    Same(Quiz.Widget.hostName, nil, "player has no host-name input")
    Same(Quiz.Widget.answer, nil, "multiple-choice participation needs no answer input")
    Games.UI:SetTab("host")
    Check(not Quiz.HostPage.start.enabled, "a mixed-rules All packs draft cannot start an incompatible game")
    Quiz.HostPage.draft.packId = SHORT_PACK
    Games.UI:Refresh()
    Check(Quiz.HostPage.start.enabled, "host Start is available before play")
    for _, control in ipairs({ "publish", "bridgeChat", "chatFields", "customChannel", "channelPassword", "join" }) do
        Same(Games.UI[control], nil, "removed chat control is not constructed: " .. control)
    end
    Check(Quiz.Controller:SaveSettings(Settings()), "valid host configuration saves")

    Test.guild, Test.raid, Test.instance = false, false, false
    local chatBefore = #Test.sent
    local round = Begin()
    local game = Quiz.Controller.game
    Same(game.continuous, true, "runtime explicitly requests continuous play")
    Same(game.total, 3, "all pack questions are used despite legacy count of one")
    Same(game.cycle, 1, "first cycle starts at one")
    Same(Quiz.Session:GetView().role, "host", "host uses the same widget view contract")
    Same(Quiz.Session:GetView().hostName, Test.hostName .. "-" .. Test.realm, "host identity includes realm")
    Same(#Test.sent, chatBefore, "starting never emits public chat")
    Check(not Quiz.Session:Leave(), "participant Leave cannot silently stop the host")
    for _, invalid in ipairs({ 0, 5, 1.5, true, {}, Test.secret, "", "A extra", "E", "|cffffffffA" }) do
        Check(not Quiz.Session:SubmitAnswer(invalid), "malformed widget input is not an answer")
    end
    Same(next(round.answers), nil, "invalid input does not create an answer")
    Test.Advance(0.5)
    Quiz.Widget:Refresh()
    Same(Quiz.Widget.prompt:GetText(), round.prompt, "widget renders the active prompt")
    Check(
        Quiz.Widget.choices[round.correctIndex].Text:GetText():find(round.choices[round.correctIndex], 1, true),
        "native choice button text mirrors the answer"
    )
    Quiz.Widget.choices[round.correctIndex].scripts.OnClick()
    Check(round.answers[Test.hostGUID], "choice button submits the host's GUID")
    Same(round.answers[Test.hostGUID].points, 2.4, "correct answer earns one plus whole remaining seconds")
    Check(not Quiz.Session:GetView().locked, "accepted widget answer remains adjustable")
    Same(Quiz.Session:GetView().selected, round.correctIndex, "widget tracks the accepted choice")
    local firstAnswer = round.answers[Test.hostGUID]
    Check(Quiz.Session:SubmitAnswer(round.correctIndex), "same-choice click is harmless")
    Same(round.answers[Test.hostGUID], firstAnswer, "same-choice click does not retime the answer")
    Test.Advance(1.5)
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "a changed choice replaces the old answer")
    Same(round.answers[Test.hostGUID].points, -0.9, "a wrong replacement receives its elapsed-time penalty")
    Test.Advance(1)
    Check(Quiz.Session:SubmitAnswer(round.correctIndex), "returning to a previous choice is allowed")
    Same(round.answers[Test.hostGUID].points, 2.2, "returning choice uses the latest answer time")
    Same(#Quiz.Store:GetStandings(LEAGUE, "PUBLIC"), 0, "live answer is not persisted")
    IgnoreChat(round)

    Quiz.Widget.frame:Hide()
    Games.UI.frame:Hide()
    Quiz.Widget:Refresh()
    Check(Quiz.Widget.frame:IsShown(), "an active session restores its required HUD")
    Same(game.state, "open", "closing setup does not stop the quiz")
    Check(Games.Main.ticker, "closing setup leaves the host timer active")
    local result = Close()
    Same(result.totalAnswers, 1, "only the latest answer per player is finalized")
    Same(Standing(LEAGUE, Test.hostGUID).score, 2.2, "finalized decimal host score enters this session")
    Same(Personal().score, 2.2, "the host saves only its personal pack score")
    Same(#Quiz.Store:GetStandings(LEAGUE, "PUBLIC"), 0, "new gameplay leaves archived league totals untouched")
    local completed = game.completed
    Games.Main:Tick()
    Quiz.Controller:CloseQuestion(Test.now)
    Same(game.completed, completed, "repeated close and tick commit once")
    Same(Standing(LEAGUE, Test.hostGUID).answers, 1, "repeated close cannot duplicate a saved answer")
    Same(Personal().answers, 1, "repeated close cannot duplicate personal progress")
    Same(#Test.sent, chatBefore, "results do not emit public chat")

    local seen = { [1] = { [round.key] = true } }
    local previousKey = round.key
    local previousId = round.id
    round = Next()
    Same(round.number, 2, "question two follows automatically")
    Same(Quiz.Widget.frame:IsShown(), true, "active HUD stays visible across automatic questions")
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "wrong choice can be clicked without typing")
    Same(round.answers[Test.hostGUID].points, -1, "an instant wrong choice loses one point")
    Close()
    Same(Standing(LEAGUE, Test.hostGUID).score, 1.2, "the finalized wrong answer reduces the accumulated score")
    Same(Personal().score, 1.2, "personal pack totals include authoritative wrong-answer penalties")
    seen[1][round.key] = true
    previousKey, previousId = round.key, round.id
    round = Next()
    Same(round.number, 3, "legacy count does not finish the host")
    Test.Advance(3)
    Check(
        Quiz.Session:SubmitAnswer("  " .. round.choices[round.correctIndex]:upper() .. "  "),
        "exact choice text is accepted case-insensitively"
    )
    Same(round.answers[Test.hostGUID].points, 2.2, "twelve seconds remaining add twelve tenths")
    Close()
    seen[1][round.key] = true
    previousKey, previousId = round.key, round.id
    Same(Standing(LEAGUE, Test.hostGUID).score, 3.4, "decimal scores accumulate across the first full deck")

    for cycle = 2, 5 do
        seen[cycle] = {}
        for number = 1, game.total do
            round = Next()
            Same(round.cycle, cycle, "round exposes its cycle")
            Same(round.number, number, "question number resets at each full deck")
            Check(not seen[cycle][round.key], "each question is used exactly once per cycle")
            Check(round.id > previousId, "question IDs keep increasing across cycles")
            if number == 1 then
                Check(round.key ~= previousKey, "reshuffle avoids an immediate boundary repeat")
            end
            seen[cycle][round.key] = true
            previousKey, previousId = round.key, round.id
            Check(Quiz.Session:SubmitAnswer(round.correctIndex), "numeric widget index is accepted")
            Close()
            Same(game.state, "results", "continuous game never enters finished")
        end
    end
    Same(game.completed, 15, "runtime continues across five complete cycles")
    Same(game.usedIds, nil, "continuous IDs do not grow a used-token map")
    Same(Standing(LEAGUE, Test.hostGUID).answers, 15, "every finalized cycle contributes to the hosted session")
    Same(Personal().answers, 15, "all fifteen completed answers contribute to personal pack progress")
    Same(#Test.sent, chatBefore, "five cycles produce no routine public chat")
    Games.Main:Stop()
    Same(game.state, "stopped", "Stop ends continuous progression")
    Check(Games.Main.ticker, "Stop retains discovery for joining another game")
    local stopId = OrbitGamesDB.modes.quiz.nextQuestionId
    Test.Advance(60)
    Same(OrbitGamesDB.modes.quiz.nextQuestionId, stopId, "stopped quizzes cannot allocate later questions")
    Test.guild, Test.raid, Test.instance = true, true, true

    round = Begin(Settings())
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "pending wrong answer before manual pause")
    local voidId = round.id
    Check(Games.Main:Pause(nil, false), "manual pause is supported")
    CheckVoided("manual pause voids the current question")
    Test.Advance(30)
    Same(game.state, "stopped", "previous game is not revived by later timers")
    Same(Quiz.Controller.game.state, "paused", "manual pause does not auto-resume")
    Check(Games.Main:Resume(), "manual resume starts a fresh question")
    round = Quiz.Controller.game.round
    Check(round.id > voidId, "resuming never reuses a voided question ID")
    Same(round.deadline, Test.now + 15, "resume receives the fixed answer window")
    Same(Quiz.Controller.game.total, 3, "voids never shrink a continuous deck")
    Games.Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Test.secret, Enum.AddOnRestrictionState.Active)
    Games.Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Test.secret)
    Same(Quiz.Controller.game.round, round, "secret restriction payloads are ignored before comparison")
    Test.restricted = true
    Test.Advance(0.1)
    CheckVoided("native lockdown polling also voids the active round")
    Test.restricted = false
    Test.Advance(0.1)
    Same(Quiz.Controller.game.state, "open", "native lockdown polling automatically recovers")
    Check(Quiz.Controller.game.round.id > round.id, "native lockdown recovery uses a fresh question")
    round = Quiz.Controller.game.round
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "wrong answer before communication restriction")
    voidId = round.id
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Activating)
    CheckVoided("activating payload pauses before the native query flips")
    Test.Advance(1)
    Same(Quiz.Controller.game.state, "paused", "stale unrestricted API cannot override activating payload")
    Test.restricted = true
    Restriction(Enum.AddOnRestrictionState.Active)
    Test.Advance(3)
    CheckVoided("active restriction keeps the void unscored")
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Inactive)
    Same(Quiz.Controller.game.state, "open", "restriction removal automatically resumes a fresh question")
    Check(Quiz.Controller.game.round.id > voidId, "restriction recovery allocates a new ID")
    Same(Quiz.Controller.game.round.deadline, Test.now + 15, "restriction recovery has the fixed window")

    Check(Games.Main:Pause(nil, false), "explicit pause before restriction")
    Test.restricted = true
    Restriction(Enum.AddOnRestrictionState.Active)
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Inactive)
    Same(Quiz.Controller.game.state, "paused", "restriction recovery cannot cancel a manual pause")
    Check(Games.Main:Resume(), "manually paused game remains resumable")
    voidId = Quiz.Controller.game.round.id
    Games.Main:OnEvent("CHAT_SERVER_DISCONNECTED")
    CheckVoided("chat-server disconnect voids synchronized gameplay")
    Test.Advance(2)
    Same(Quiz.Controller.game.state, "paused", "disconnect remains paused until reconnect")
    Games.Main:OnEvent("CHAT_SERVER_RECONNECTED")
    Same(Quiz.Controller.game.state, "open", "chat-server reconnect automatically resumes")
    Check(Quiz.Controller.game.round.id > voidId, "reconnect replaces the exposed round")
    Games.Main:OnEvent("CHAT_SERVER_DISCONNECTED")
    Check(Games.Main:Pause(nil, false), "manual pause may take ownership of a disconnected pause")
    Games.Main:OnEvent("CHAT_SERVER_RECONNECTED")
    Same(Quiz.Controller.game.state, "paused", "manual pause during disconnect remains manual")
    Games.Main:Stop()

    round = Begin(Settings())
    Games.Main:OnEvent("PLAYER_REGEN_DISABLED")
    Same(Quiz.Controller.game.state, "open", "ordinary combat does not pause social games")
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "boss fixture has an unfinished answer")
    local encounterVoidId = round.id
    Encounter(true, false)
    CheckVoided("the native boss-encounter query pauses and voids the active question")
    Same(Games.Main.waitingActive, true, "boss encounters activate the shared waiting state")
    Same(Quiz.Controller.autoPaused, true, "boss encounter pauses remain automatically owned")
    Same(Quiz.Controller.notice, Games.L.ENCOUNTER_WAITING, "boss encounters use their dedicated notice")
    Check(not Games.Main:Resume(), "a boss encounter blocks explicit resume")
    Same(Quiz.Controller.game.state, "paused", "blocked resume cannot replace the boss wait")
    Test.restricted = true
    Restriction(Enum.AddOnRestrictionState.Active)
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Inactive)
    Same(Quiz.Controller.game.state, "paused", "chat recovery cannot resume through an active boss encounter")
    Encounter(false, true)
    Same(Quiz.Controller.game.state, "open", "the game resumes after every automatic blocker clears")
    Check(Quiz.Controller.game.round.id > encounterVoidId, "boss recovery starts a fresh question")

    round = Quiz.Controller.game.round
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Activating)
    Same(Quiz.Controller.game.state, "paused", "chat restriction owns the automatic pause first")
    Same(Quiz.Controller.notice, Games.L.NET_RESTRICTED, "chat restriction initially uses its own notice")
    Encounter(true, false)
    Same(Quiz.Controller.notice, Games.L.ENCOUNTER_WAITING, "a boss encounter replaces stale chat wait text")
    Restriction(Enum.AddOnRestrictionState.Inactive)
    Same(Quiz.Controller.game.state, "paused", "ending chat restriction cannot bypass the boss wait")
    Encounter(false, true)
    Same(Quiz.Controller.game.state, "open", "the last overlapping blocker resumes the game once")
    Check(Quiz.Controller.game.round.id > round.id, "overlapping recovery also allocates a fresh question")

    Check(Games.Main:Pause(), "manual pause precedes a boss encounter")
    Encounter(true, false)
    Encounter(false, true)
    Same(Quiz.Controller.game.state, "paused", "boss recovery cannot cancel a manual pause")
    Check(Games.Main:Resume(), "manual pause remains explicitly resumable after the encounter")
    Games.Main:Stop()

    for _, automatic in ipairs({ false, true }) do
        local pauseLeague = automatic and "Restricted reveal" or "Manual reveal"
        round = Begin(Settings())
        Check(Quiz.Session:SubmitAnswer(round.correctIndex), "reveal-pause fixture has a correct answer")
        result = Close()
        local nextAt, savedId = Quiz.Controller.nextAutoAt, OrbitGamesDB.modes.quiz.nextQuestionId
        local savedScore = Standing(pauseLeague, Test.hostGUID).score
        Test.Advance(1)
        if automatic then
            Restriction(Enum.AddOnRestrictionState.Activating)
        else
            Check(Games.Main:Pause(nil, false), "manual pause can interrupt the reveal")
        end
        Same(Quiz.Controller.game.state, "paused", "pause interrupts the three-second reveal")
        Same(Quiz.Controller.nextAutoAt, nil, "pause cancels the scheduled next question")
        Test.Advance(nextAt - Test.now + REVEAL_SECONDS)
        Same(Quiz.Controller.game.state, "paused", "the old reveal deadline cannot restart a paused quiz")
        Same(OrbitGamesDB.modes.quiz.nextQuestionId, savedId, "paused reveal allocates no question IDs")
        Same(Quiz.Controller.game.completed, 1, "pausing a reveal cannot finalize the same round twice")
        Same(Quiz.Controller.game.lastResult, result, "pausing preserves the finalized result")
        Same(Standing(pauseLeague, Test.hostGUID).score, savedScore, "pausing a reveal preserves earned points")
        Same(Standing(pauseLeague, Test.hostGUID).answers, 1, "pausing a reveal preserves exactly one saved answer")
        if automatic then
            Restriction(Enum.AddOnRestrictionState.Inactive)
        else
            Check(Games.Main:Resume(), "manual reveal pause resumes on request")
        end
        Same(Quiz.Controller.game.state, "open", "reveal recovery starts a fresh question")
        Check(Quiz.Controller.game.round.id > round.id, "reveal recovery never reuses the completed question ID")
        Same(Quiz.Controller.game.round.deadline - Test.now, 15, "reveal recovery keeps the full answer window")
        Same(Quiz.Controller.game.completed, 1, "reveal recovery does not replay the saved result")
        Games.Main:Stop()
    end

    local legacySettings = Settings()
    legacySettings.bridgeChat = true
    legacySettings.channel = "GUILD"
    legacySettings.customChannel = "Retired visible channel"
    legacySettings.channelPassword = "Old password"
    legacySettings.answerMode = "WHISPER"
    OrbitGamesDB.modes.quiz.settings = legacySettings
    Games.Main:OnEvent("ADDON_LOADED", Games.addonName)
    Games.Main:OnEvent("PLAYER_LOGIN")
    for _, key in ipairs({ "bridgeChat", "channel", "customChannel", "channelPassword", "answerMode" }) do
        Same(Quiz.Store:GetSettings()[key], nil, "reload drops retired chat setup: " .. key)
    end
    Check(Games.Main:Start(), "an old enabled bridge does not require manual publication")
    game = Quiz.Controller.game
    Same(game.state, "open", "saved setup opens the widget immediately")
    local unanswered = {}
    previousKey, previousId = nil, nil
    for index = 1, 12 do
        round = game.round
        Same(game.state, "open", "unattended rounds open without any input")
        Same(round.deadline - round.startedAt, 15, "unattended rounds keep the full fifteen-second answer window")
        Same(round.cycle, math.ceil(index / game.total), "unattended play advances through repeated cycles")
        unanswered[round.cycle] = unanswered[round.cycle] or {}
        Check(not unanswered[round.cycle][round.key], "unattended cycles exhaust the pack without repeats")
        unanswered[round.cycle][round.key] = true
        if previousId then
            Check(round.id > previousId, "unattended question IDs increase")
            if round.number == 1 then
                Check(round.key ~= previousKey, "unattended reshuffles avoid a boundary repeat")
            end
        end
        Same(next(round.answers), nil, "unattended questions never create automatic answers")
        local currentResult = Close()
        Same(currentResult.totalAnswers, 0, "an unanswered round records no player")
        Same(
            Quiz.Controller.nextAutoAt - Test.now,
            REVEAL_SECONDS,
            "results use the automatic three-second intermission"
        )
        Same(#Test.sent, 0, "unattended questions and results never send visible chat")
        previousKey, previousId = round.key, round.id
        if index < 12 then
            Next()
        end
    end
    Same(game.completed, 12, "a single Start runs four whole packs without clicks or typing")
    Same(#Quiz.Store:GetStandings(AUTOMATIC_LEAGUE, "PUBLIC"), 0, "unattended rounds cannot invent scores")
    for _, join in ipairs(Test.joins) do
        Same(join.name, Test.lobbyName, "only invisible addon discovery may join a channel")
    end
    Games.Main:Stop()

    round = Begin(Settings(LONG_PACK))
    for cycle = 1, 3 do
        Same(round.cycle, cycle, "a one-question pack loops without input")
        Same(Quiz.Widget.prompt:GetText(), round.prompt, "long UTF-8 prompts remain available in the widget")
        Same(round.deadline - round.startedAt, 15, "long prompts use the fixed fifteen-second window")
        IgnoreChat(round)
        Close()
        if cycle < 3 then
            round = Next()
        end
    end
    Same(#Test.sent, 0, "long questions never require visible chat")
    Games.Main:Stop()

    Test.now = math.floor(Test.now) + 0.2
    round = Begin(Settings())
    Test.now = round.deadline - 0.000001
    Check(
        Quiz.Controller:AcceptAnswer(Games.Identity.name, Test.hostGUID, round.id, round.correctIndex),
        "fractional just-before-deadline answer remains valid"
    )
    Test.now = round.deadline
    Check(
        not Quiz.Controller:AcceptAnswer("Deadline-TestRealm", "Deadline", round.id, round.correctIndex),
        "runtime rejects answers at its exclusive deadline"
    )
    Games.Main:Tick()
    Same(
        Standing("Fractional deadline", Test.hostGUID).score,
        1,
        "near-deadline correct answer earns only the base point"
    )
    Check(Quiz.Controller.game.lastResult.answers[1].elapsed <= 15, "elapsed rounding cannot exceed persisted duration")
    Games.Main:Stop()

    local beforeNegative = Personal().score
    round = Begin(Settings())
    Same(Quiz.Controller:GetScore(Test.hostGUID), 0, "a new hosted game cannot inherit personal lifetime scores")
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "wrong-answer-only fixture accepts a choice")
    Close()
    Same(Standing("Negative total", Test.hostGUID).score, 0, "wrong answers floor the visible session total at zero")
    Same(
        Personal().score,
        Quiz.Scoring.Add(beforeNegative, -1),
        "one wrong-answer deduction updates existing personal progress"
    )
    round = Next()
    Close()
    Same(Standing("Negative total", Test.hostGUID).score, 0, "not answering the next question incurs no penalty")
    Same(
        Standing("Negative total", Test.hostGUID).answers,
        1,
        "an unanswered question does not count as a wrong answer"
    )
    round = Next()
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "another wrong selection may remain unfinalized")
    Check(Games.Main:Pause(nil, false), "pausing voids the pending wrong answer")
    Same(Standing("Negative total", Test.hostGUID).score, 0, "voiding a wrong answer does not deduct another penalty")
    Same(
        Standing("Negative total", Test.hostGUID).answers,
        1,
        "voiding preserves the previously finalized answer count"
    )
    Games.Main:Stop()

    do
        local joinHost = Quiz.Session.JoinHost
        local controllerNotice, mainNotice = Quiz.Controller:GetNotice(), Games.Main.notice
        local receivedName, receivedSession, receivedAdvert
        Quiz.Session.JoinHost = function(_, name, sessionId, advert)
            receivedName, receivedSession, receivedAdvert = name, sessionId, advert
            return true
        end
        local advert = {
            hostName = "Browser-TestRealm",
            sessionId = "browser.1",
            gameTypeId = Quiz.id,
            activityId = Quiz.id,
            activityVersion = 1,
            maxPlayers = 17,
            joinable = true,
        }
        Check(Games.Main:Join(advert), "browser join routes through the selected mode session")
        Same(receivedName, advert.hostName, "browser join forwards the advertised host")
        Same(receivedSession, advert.sessionId, "browser join forwards the advertised session")
        Same(receivedAdvert, advert, "browser join forwards the complete activity advert")
        advert.joinable = false
        local joined, reason = Games.Main:Join(advert)
        Same(joined, false, "closed browser games cannot be joined")
        Same(reason, "game_not_joinable", "closed browser games return the generic availability reason")
        Quiz.Session.JoinHost = joinHost
        Quiz.Controller:SetNotice(controllerNotice)
        Games.Main.notice = mainNotice
    end

    chatBefore = #Test.sent
    Same(Quiz.Controller:GetNotice(), Quiz.L.STATUS_STOPPED, "stopping a hosted session exposes its stopped notice")
    SlashCmdList.ORBITGAMES("join Remote-TestRealm")
    Same(Quiz.Controller:GetNotice(), nil, "joining another host clears the old local host's stopped notice")
    Same(Quiz.Session:GetView().state, "joining", "slash join opens participant connection state")
    Same(Quiz.Session:GetView().hostName, "Remote-TestRealm", "join target is retained with realm")
    Check(Quiz.Widget.frame:IsShown(), "joining opens the player widget")
    Games.UI.frame:Show()
    local connectionNotice = Quiz.Session.view.notice
    Quiz.Controller:SetNotice("Old host notice")
    Quiz.Session.view.notice = "Participant connection notice"
    Games.UI:Refresh()
    Same(
        Games.UI.notice:GetText(),
        "Participant connection notice",
        "active participant notices outrank old host notices"
    )
    Quiz.Controller:SetNotice(nil)
    Quiz.Session.view.notice = connectionNotice
    Games.UI.frame:Hide()
    Check(Games.Comms:IsBusy(), "join queues addon communication")
    local addonBefore = #Test.addonSent
    Test.Advance(0.1)
    Check(#Test.addonSent > addonBefore, "addon synchronization sends without public-chat hardware")
    Same(Test.addonSent[#Test.addonSent].channel, "WHISPER", "synchronization uses targeted addon messages")
    Same(Test.addonSent[#Test.addonSent].target, "Remote-TestRealm", "join packets target only the selected host")
    Same(#Test.sent, chatBefore, "joining does not require public chat")
    SlashCmdList.ORBITGAMES("leave")
    Same(Quiz.Session:GetView().state, "idle", "slash leave clears participant state")
    Check(Games.Comms:IsBusy(), "leaving an unconfirmed join queues cancellation for its request")
    Test.Advance(1)
    Check(Games.Main.ticker, "idle participant keeps discovery available")
    Check(not Quiz.Session:JoinHost(Test.hostName .. "-" .. Test.realm), "joining oneself is rejected")
    for _, name in ipairs({ "", "Other Realm", "Other|Realm", Test.secret, true }) do
        Check(not Quiz.Session:JoinHost(name), "malformed host names are rejected before communication")
    end
    Check(Quiz.Session:JoinHost("Absent-TestRealm"), "offline fixture begins joining")
    Test.Advance(13)
    Same(Quiz.Session:GetView().state, "disconnected", "unanswered join times out")
    Check(not Games.Comms:IsBusy(), "join timeout clears stale request packets")
    Quiz.Session:Leave()
    Games.Main:Tick()

    Games.UI:Toggle()
    Same(Games.UI.duration, nil, "there is no editable answer duration")
    Same(Quiz.HostPage:ReadSettings().packId, Quiz.HostPage.draft.packId, "host setup reads only its selected pack")
    Quiz.HostPage.draft.packId = SHORT_PACK
    Quiz.HostPage.start.scripts.OnClick()
    Same(Quiz.Controller.game.state, "open", "host Start button starts widget-first gameplay")
    Quiz.HostPage.pause.scripts.OnClick()
    Same(Quiz.Controller.game.state, "paused", "host Pause button pauses")
    Quiz.HostPage.pause.scripts.OnClick()
    Same(Quiz.Controller.game.state, "open", "same host control resumes fresh")
    Quiz.HostPage.stop.scripts.OnClick()
    Same(Quiz.Controller.game.state, "stopped", "host Stop button ends gameplay")

    round = Begin(Settings())
    Check(Quiz.Session:SubmitAnswer(round.correctIndex), "unfinished reload fixture has an accepted answer")
    local saved = OrbitGamesDB
    local nextId = saved.modes.quiz.nextQuestionId
    local savedScore, savedAnswers = Personal().score, Personal().answers
    Games.Main:OnEvent("PLAYER_LOGOUT")
    Check(not Games.Main.ticker, "logout cancels the runtime ticker")
    Check(not Games.Comms:IsBusy(), "logout clears addon transport")
    Same(#Test.sent, 0, "logout never emits visible chat")
    CheckNoTickers("logout leaves no active timer")
    Same(#Quiz.Store:GetStandings("Reload active", "PUBLIC"), 0, "logout cannot persist an unfinished answer")
    Same(saved.round, nil, "active round is absent from saved data")
    Same(saved.game, nil, "runtime game is absent from saved data")
    Quiz.Controller.game = nil
    Quiz.Controller.nextAutoAt = nil
    Games.Main:OnEvent("ADDON_LOADED", "Orbit-Games")
    Games.Main:OnEvent("PLAYER_LOGIN")
    Same(OrbitGamesDB.schemaVersion, 1, "reload preserves the generic root schema")
    Same(OrbitGamesDB.modes.quiz.schemaVersion, 7, "reload preserves the Quiz mode schema")
    Same(OrbitGamesDB.modes.quiz.nextQuestionId, nextId, "reload preserves the monotonic counter")
    Same(Personal().score, savedScore, "completed multi-cycle per-pack scores survive reload")
    Same(Personal().answers, savedAnswers, "personal answer counts survive reload without the unfinished answer")
    Same(
        #Quiz.Store:GetStandings("Negative total", "PUBLIC"),
        0,
        "new negative results never populate old league storage"
    )
    Same(
        #Quiz.Store:GetStandings(AUTOMATIC_LEAGUE, "PUBLIC"),
        0,
        "unanswered automatic rounds remain unscored after reload"
    )
    Same(#Quiz.Store:GetStandings("Reload active", "PUBLIC"), 0, "reload never revives active answers")
    Same(Quiz.Session:GetView().state, "idle", "reload does not automatically restart a quiz")
    Games.UI.frame:Show()
    Games.UI.boardScope = "personal"
    Games.UI:SetTab("results")
    Games.UI:LoadSettings()
    local getScoreRows, boardReads = Quiz.PersonalScores.GetScoreRows, 0
    Quiz.PersonalScores.GetScoreRows = function(owner, ...)
        boardReads = boardReads + 1
        return getScoreRows(owner, ...)
    end
    Games.UI:Refresh()
    Same(boardReads, 1, "personal board builds from saved pack totals on invalidation")
    for _ = 1, 20 do
        Games.UI:Refresh()
    end
    Same(boardReads, 1, "timer refreshes do not sort unchanged persistent standings")
    Games.UI:LoadSettings()
    Games.UI:Refresh()
    Same(boardReads, 2, "settings reload invalidates the board cache")
    Quiz.PersonalScores.GetScoreRows = getScoreRows
    do
        local function RegisterRules(id, rules, count)
            local questions = {}
            for index = 1, count do
                questions[index] = {
                    id = "question-" .. index,
                    prompt = "Authored question " .. index,
                    choices = { "Wrong first", "Right", "Wrong third", "Wrong fourth" },
                    correctIndex = 2,
                    explanation = "The authored explanation.",
                }
            end
            Check(
                Quiz:RegisterPack({ id = id, title = id, rules = rules, questions = questions }),
                "authored rules pack registers"
            )
            return assert(Quiz:GetRules(id))
        end

        local function CloseRules()
            local current = Quiz.Controller.game
            Test.Advance(current.round.deadline - Test.now)
            Same(Quiz.Session:GetView().state, "results", "every closed authored round has a visible result interval")
            Same(Quiz.Controller.nextAutoAt - Test.now, current.rules.revealSeconds, "reveal follows the pack's rule")
            return current.lastResult
        end

        local function AdvanceRules()
            local deadline = Quiz.Controller.nextAutoAt
            Test.Advance(deadline - Test.now - BOUNDARY_EPSILON)
            Same(Quiz.Session:GetView().state, "results", "authored reveal remains visible until its precise boundary")
            Test.Advance(deadline - Test.now)
            return Quiz.Controller.game.round
        end

        local rulesId = "runtime-authored-loop"
        local authored = RegisterRules(rulesId, {
            answerSeconds = 8,
            revealSeconds = 2,
            allowAnswerChanges = false,
            shuffleQuestions = false,
            shuffleChoices = false,
            correctPoints = 2,
            speedBonusPerSecond = 0.2,
            wrongPenaltyStart = 2,
            wrongPenaltyEnd = 1,
            streakBonusPerCorrect = 0.2,
            streakBonusMax = 0.4,
        }, 3)
        local settings = Settings(rulesId)
        Check(Games.Main:Start(settings), "author rules are selected without host overrides")
        local current = Quiz.Controller.game
        Same(current.continuous, true, "legacy host count cannot shorten an endless authored quiz")
        Same(current.round.prompt, "Authored question 1", "ordered pack starts with its authored first question")
        Same(current.round.correctIndex, 2, "disabled choice shuffling preserves the authored answer order")
        Same(current.round.deadline - current.round.startedAt, 8, "author controls the answer window")
        Same(Quiz.Session:GetView().duration, 8, "host widget receives the authored duration")
        local detached = assert(Quiz:GetRules(rulesId))
        detached.answerSeconds = 120
        Same(current.rules.answerSeconds, 8, "detached registry rules cannot mutate a live rules snapshot")
        Test.Advance(2)
        Check(Quiz.Session:SubmitAnswer(2), "first selection is accepted by a locked-answer pack")
        local accepted = current.round.answers[Test.hostGUID]
        Check(Quiz.Session:GetView().locked, "the host widget locks after its first accepted choice")
        Check(not Quiz.Session:SubmitAnswer(3), "the widget cannot replace a locked answer")
        Check(
            not Quiz.Controller:AcceptAnswer(Games.Identity.name, Test.hostGUID, current.round.id, 3),
            "host enforcement also rejects changed locked answers"
        )
        Check(
            Quiz.Controller:AcceptAnswer(Games.Identity.name, Test.hostGUID, current.round.id, 2),
            "same-choice retry remains harmless despite answer locking"
        )
        Same(current.round.answers[Test.hostGUID], accepted, "a same-choice retry cannot retime the locked answer")
        local closed = CloseRules()
        Same(closed.answers[1].points, 3.2, "authored base and speed rate score the host's observed elapsed time")
        Same(closed.answers[1].streak, 1, "first finalized correct answer starts a streak")
        Same(closed.answers[1].streakBonus, 0, "the first correct answer has no streak bonus")
        for index, expected in ipairs({ 3.8, 4, 4 }) do
            local nextRound = AdvanceRules()
            Same(
                nextRound.prompt,
                "Authored question " .. ((index % 3) + 1),
                "unshuffled questions retain authored order across cycles"
            )
            Same(nextRound.deadline - nextRound.startedAt, 8, "every loop retains the pack's full answer window")
            Check(Quiz.Session:SubmitAnswer(2), "next consecutive correct answer is accepted")
            closed = CloseRules()
            Same(
                closed.answers[1].points,
                expected,
                "streak bonus increments and caps on finalized consecutive answers"
            )
            Same(closed.answers[1].streak, index + 1, "correct streak counts completed rounds rather than clicks")
            Same(closed.answers[1].streakBonus, math.min(index * 0.2, 0.4), "authored streak cap is enforced")
        end
        AdvanceRules()
        Check(Quiz.Session:SubmitAnswer(3), "wrong pending answer exists before a void")
        Check(Games.Main:Pause(nil, false), "manual pause voids an unfinished custom-rule round")
        Same(current.players[Test.hostGUID].streak, 4, "void rounds do not reset or increment a completed streak")
        Check(Games.Main:Resume(), "custom-rule quiz resumes with a fresh question")
        Same(
            current.round.deadline - current.round.startedAt,
            8,
            "restriction and pause recovery cannot revert the authored clock"
        )
        Check(Quiz.Session:SubmitAnswer(3), "wrong final answer is accepted after recovery")
        closed = CloseRules()
        Same(closed.answers[1].points, -2, "wrong answer uses the authored early penalty")
        Same(closed.answers[1].streak, 0, "a finalized wrong answer resets the streak")
        Same(closed.answers[1].streakBonus, 0, "wrong answers never retain a streak bonus")
        AdvanceRules()
        Check(Quiz.Session:SubmitAnswer(2), "correct answer after a wrong starts a new streak")
        closed = CloseRules()
        Same(closed.answers[1].streak, 1, "a reset streak restarts at one")
        AdvanceRules()
        local scoreBeforeSkip = Quiz.Controller:GetScore(Test.hostGUID)
        closed = CloseRules()
        Same(closed.totalAnswers, 0, "an unanswered rule-controlled round invents no answer")
        Same(current.players[Test.hostGUID].streak, 0, "unanswered rounds reset a completed streak")
        Same(Quiz.Controller:GetScore(Test.hostGUID), scoreBeforeSkip, "a skipped round has no invented penalty")
        Check(Games.Main:Stop(), "custom loop stops explicitly")
        Check(Games.Main:Start(Settings(rulesId)), "the same authored pack can start another game")
        Same(
            Quiz.Controller:GetScore(Test.hostGUID),
            0,
            "new games reset session scores independently of personal progress"
        )
        Check(Quiz.Session:SubmitAnswer(2), "new-game correct answer is accepted")
        closed = CloseRules()
        Same(closed.answers[1].streak, 1, "new games cannot inherit a prior game's streak")
        Check(Games.Main:Stop(), "new-game streak fixture stops")

        for index, finite in ipairs({
            { repeats = false, limit = 0, deck = 3, count = 3 },
            { repeats = false, limit = 2, deck = 3, count = 2 },
            { repeats = false, limit = 10, deck = 3, count = 3 },
            { repeats = true, limit = 5, deck = 2, count = 5 },
        }) do
            local id = "runtime-authored-finite-" .. index
            RegisterRules(id, {
                answerSeconds = 5,
                revealSeconds = 2,
                shuffleQuestions = false,
                shuffleChoices = false,
                repeatQuestions = finite.repeats,
                questionLimit = finite.limit,
            }, finite.deck)
            Check(Games.Main:Start(Settings(id)), "finite quiz starts from its pack rules")
            current = Quiz.Controller.game
            Same(current.total, finite.count, "finite round total resolves repeat and question-limit rules")
            for number = 1, finite.count do
                Same(
                    current.round.prompt,
                    "Authored question " .. ((number - 1) % finite.deck + 1),
                    "finite decks preserve authored order"
                )
                Check(Quiz.Session:SubmitAnswer(2), "finite question accepts an answer without manual progression")
                closed = CloseRules()
                Same(closed.complete, number == finite.count, "completion occurs only after the authored final round")
                if number < finite.count then
                    AdvanceRules()
                    Same(current.state, "open", "finite quiz automatically advances until its limit")
                end
            end
            Same(current.state, "finished", "model stops allocating questions after the limit")
            Check(Games.Main:IsRunning(), "final result stays an active host presentation during its reveal")
            Check(Quiz.Session.hostSession, "the final result remains bound to its host until reveal completes")
            local nextId = OrbitGamesDB.modes.quiz.nextQuestionId
            AdvanceRules()
            Same(current.completed, finite.count, "reveal completion cannot finalize the last round twice")
            Same(Quiz.Session.hostSession, nil, "the host session ends automatically after its final reveal")
            Check(not Games.Main:IsRunning(), "finite completion does not silently restart a loop")
            Test.Advance(30)
            Same(OrbitGamesDB.modes.quiz.nextQuestionId, nextId, "a finished quiz allocates no later questions")
            Same(
                Quiz.PersonalScores:GetPack(id).answers,
                finite.count,
                "all finite-game results are persisted exactly once"
            )
        end

        for _, automatic in ipairs({ false, true }) do
            for count = 1, 2 do
                local id = "runtime-last-void-" .. (automatic and "auto-" or "manual-") .. count
                RegisterRules(id, {
                    answerSeconds = 5,
                    revealSeconds = 2,
                    repeatQuestions = false,
                    shuffleQuestions = false,
                    shuffleChoices = false,
                    streakBonusPerCorrect = 0.1,
                    streakBonusMax = 0.5,
                }, count)
                Check(Games.Main:Start(Settings(id)), "single-pass last-question void fixture starts")
                current = Quiz.Controller.game
                if count == 2 then
                    Check(
                        Quiz.Session:SubmitAnswer(2),
                        "a preceding correct round is finalized before the last-round void"
                    )
                    CloseRules()
                    AdvanceRules()
                end
                Check(Quiz.Session:SubmitAnswer(3), "the last exposed single-pass question has a pending wrong answer")
                local nextId, priorResult = OrbitGamesDB.modes.quiz.nextQuestionId, current.lastResult
                local completedScore = Quiz.Controller:GetScore(Test.hostGUID)
                if automatic then
                    Restriction(Enum.AddOnRestrictionState.Active)
                else
                    Check(Games.Main:Pause(nil, false), "manual pause can void the final available question")
                end
                Same(
                    current.state,
                    "paused",
                    "last-question interruption remains paused until explicit or automatic recovery"
                )
                Same(current.round, nil, "voiding the last question discards its unfinished answer")
                Test.Advance(5)
                Same(current.state, "paused", "the voided deadline cannot finalize a missing final question")
                if automatic then
                    Restriction(Enum.AddOnRestrictionState.Inactive)
                else
                    Check(Games.Main:Resume(), "manual recovery closes a consumed single-pass deck cleanly")
                end
                Same(current.state, "finished", "a consumed final question leaves the finite model finished")
                Same(current.completed, count - 1, "voids do not increment the count of finalized questions")
                Same(current.lastResult, priorResult, "a final void cannot fabricate another result")
                Same(
                    Quiz.Controller.nextAutoAt,
                    nil,
                    "there is no result reveal to schedule for a voided final question"
                )
                Same(Quiz.Session.hostSession, nil, "recovery cannot leave a phantom host for an exhausted deck")
                Check(not Games.Main:IsRunning(), "final-question void recovery terminates the finite session")
                Same(
                    Quiz.Controller:GetScore(Test.hostGUID),
                    completedScore,
                    "void recovery preserves only already-earned session points"
                )
                if count == 1 then
                    Same(
                        Quiz.PersonalScores:GetPack(id),
                        nil,
                        "an entirely voided single-pass game writes no personal score"
                    )
                else
                    Same(
                        Quiz.PersonalScores:GetPack(id).answers,
                        1,
                        "earlier finalized progress survives a voided final question"
                    )
                    Same(
                        current.players[Test.hostGUID].streak,
                        1,
                        "a voided final question does not reset a completed streak"
                    )
                end
                Test.Advance(10)
                Same(
                    OrbitGamesDB.modes.quiz.nextQuestionId,
                    nextId,
                    "finite void recovery never allocates a replacement question"
                )
            end
        end

        local loreRules = assert(Quiz:GetRules("warcraft-lore"))
        Same(loreRules.streakBonusPerCorrect, 0.1, "bundled Warcraft Lore opts into a tenth-point streak step")
        Same(loreRules.streakBonusMax, 0.5, "bundled Warcraft Lore caps its additional streak reward at half a point")
        Check(Games.Main:Start(Settings("warcraft-lore")), "bundled lore starts with its explicit author rules")
        for number = 1, 7 do
            Check(
                Quiz.Session:SubmitAnswer(Quiz.Controller.game.round.correctIndex),
                "bundled lore correct answer is accepted"
            )
            closed = CloseRules()
            Same(closed.answers[1].streak, number, "bundled lore records consecutive finalized correct answers")
            Same(
                closed.answers[1].streakBonus,
                math.min(number - 1, 5) / 10,
                "bundled lore streak step caps after six consecutive correct answers"
            )
            Same(
                closed.answers[1].points,
                (25 + math.min(number - 1, 5)) / 10,
                "bundled lore total includes speed and bounded streak rewards"
            )
            if number < 7 then
                AdvanceRules()
            end
        end
        Check(Games.Main:Stop(), "bundled streak fixture stops")
        Check(#Quiz:GetQuestions("all") > 0, "mixed-rule question catalogues remain readable as content")
        Check(not Games.Main:Start(Settings("all")), "incompatible pack rules cannot silently combine into one game")
        Same(Quiz.Session.hostSession, nil, "rejected mixed rules create no host authority")
    end
    Same(#Test.errors, 0, "runtime never invokes the unexpected-error handler")
    return assertions
end

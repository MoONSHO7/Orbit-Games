return function(Quiz)
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
    local function Settings(packId, league)
        local settings = Quiz.Store:GetSettings()
        settings.packId = packId or SHORT_PACK
        settings.questionCount = 1
        settings.duration = 60
        settings.autoAdvance = false
        settings.league = league or LEAGUE
        return settings
    end
    local function Begin(settings, state)
        Check(Quiz.Main:Start(settings or Settings()), "widget host starts without a hardware event")
        Same(Quiz.Main.game.state, state or "open", "host opens or prepares the expected presentation")
        Same(Quiz.Main.game.settings.duration, 15, "old configured durations cannot override the fixed clock")
        Same(Quiz.Session:GetView().id, Quiz.Main.game.round.id, "host widget and game share the question")
        return Quiz.Main.game.round
    end
    local function Close()
        local game = Quiz.Main.game
        Test.Advance(game.round.deadline - Test.now)
        Same(game.state, "results", "deadline finalizes into results")
        Same(Quiz.Main.nextAutoAt - Test.now, REVEAL_SECONDS, "results schedule exactly three seconds of reveal")
        return game.lastResult
    end
    local function Next(state)
        Check(Quiz.Main.nextAutoAt, "results schedule automatic progression")
        local nextAt, round = Quiz.Main.nextAutoAt, Quiz.Main.game.round
        Test.Advance(nextAt - Test.now - BOUNDARY_EPSILON)
        Same(Quiz.Main.game.state, "results", "results remain visible just before the three-second boundary")
        Same(Quiz.Session:GetView().id, round.id, "reveal retains the completed question until the boundary")
        Same(
            Quiz.Session:GetView().correctIndex,
            round.correctIndex,
            "reveal retains the correct answer until the boundary"
        )
        Check(Quiz.Session:GetView().locked, "revealed answers cannot be changed during the result break")
        Test.Advance(nextAt - Test.now)
        Same(Quiz.Main.game.state, state or "open", "intermission prepares the next question without a click")
        Check(Quiz.Main.game.round.id > round.id, "the boundary allocates a fresh question automatically")
        Same(Quiz.Session:GetView().correctIndex, nil, "the next question does not inherit the revealed answer")
        if not state or state == "open" then
            Same(Quiz.Main.game.round.startedAt, nextAt, "a host without peers opens at exactly three seconds")
            Same(
                Quiz.Main.game.round.deadline - nextAt,
                15,
                "the next question receives its full fifteen-second window"
            )
        end
        return Quiz.Main.game.round
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
                Test.Incoming(text, Quiz.Identity.name, Test.hostGUID, event)
                Same(round.answers["Player-0-CHAT"], nil, "visible chat never creates a participant answer")
                Same(round.answers[Test.hostGUID], previous, "visible chat never changes the host's widget answer")
            end
        end
    end
    local function Standing(_, guid)
        for _, player in ipairs(Quiz.Main.game:GetStandings()) do
            if player.guid == guid then
                return player
            end
        end
    end
    local function Personal(packId)
        return Quiz.PersonalScores:GetPack(packId or SHORT_PACK)
    end
    local function Restriction(state)
        Quiz.Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, state)
    end
    local function CheckVoided(message)
        Same(Quiz.Main.game.state, "paused", message)
        Same(Quiz.Main.game.round, nil, "interruption discards its exposed round")
        Same(#Quiz.Store:GetStandings(VOID_LEAGUE, "PUBLIC"), 0, "void answers never enter persistent standings")
        Same(#Test.sent, 0, "interruption never emits visible chat")
    end
    local function CheckNoTickers(message)
        for _, ticker in ipairs(Test.tickers) do
            Check(not ticker.active, message)
        end
    end

    Check(Quiz.Main.initialized, "TOC lifecycle initializes the addon")
    Same(OrbitQuizDB.schemaVersion, 6, "lifecycle uses personal per-pack scores and independent widget settings")
    Same(Quiz.Chat, nil, "visible chat transport is absent")
    Same(Quiz.Main.PublishChat, nil, "manual publication is absent")
    Same(Quiz.Main.OnChat, nil, "visible chat answer handling is absent")
    Same(Quiz.Main.JoinChannel, nil, "manual visible-channel joining is absent")
    Same(Quiz.Store:GetSettings().bridgeChat, nil, "host setup has no bridge setting")
    Same(Quiz.Store:GetSettings().hostName, "", "participant target starts empty")
    local bundledCount = 0
    for _, pack in ipairs(Quiz:GetQuestionPacks()) do
        bundledCount = bundledCount + pack.count
    end
    Check(bundledCount > 0, "bundled questions load before fixture packs")
    Same(#Quiz:GetQuestions("all"), bundledCount, "every bundled question is available before fixture packs")
    Check(
        Quiz:RegisterQuestionPack({
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
        Quiz:RegisterQuestionPack({
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

    SlashCmdList.ORBITQUIZ("")
    Check(Quiz.Widget.frame:IsShown(), "/oq opens a positionable HUD preview")
    Check(Quiz.UI.frame:IsShown(), "/oq opens games and host setup")
    Same(Quiz.Widget.hostName, nil, "player has no host-name input")
    Same(Quiz.Widget.answer, nil, "multiple-choice participation needs no answer input")
    Quiz.UI:SetTab("host")
    Same(Quiz.UI.questionCount, nil, "finite question-count control is absent")
    Same(Quiz.UI.autoAdvance, nil, "manual auto-advance toggle is absent")
    Check(Quiz.UI.start.enabled, "host Start is available before play")
    for _, control in ipairs({ "publish", "bridgeChat", "chatFields", "customChannel", "channelPassword", "join" }) do
        Same(Quiz.UI[control], nil, "removed chat control is not constructed: " .. control)
    end
    Check(Quiz.Main:SaveSettings(Settings()), "valid host configuration saves")

    Test.guild, Test.raid, Test.instance = false, false, false
    local chatBefore = #Test.sent
    local round = Begin()
    local game = Quiz.Main.game
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
    Quiz.UI.frame:Hide()
    Quiz.Widget:Refresh()
    Check(Quiz.Widget.frame:IsShown(), "an active session restores its required HUD")
    Same(game.state, "open", "closing setup does not stop the quiz")
    Check(Quiz.Main.ticker, "closing setup leaves the host timer active")
    local result = Close()
    Same(result.totalAnswers, 1, "only the latest answer per player is finalized")
    Same(Standing(LEAGUE, Test.hostGUID).score, 2.2, "finalized decimal host score enters this session")
    Same(Personal().score, 2.2, "the host saves only its personal pack score")
    Same(#Quiz.Store:GetStandings(LEAGUE, "PUBLIC"), 0, "new gameplay leaves archived league totals untouched")
    local completed = game.completed
    Quiz.Main:Tick()
    Quiz.Main:CloseQuestion(Test.now)
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
    Quiz.Main:Stop()
    Same(game.state, "stopped", "Stop ends continuous progression")
    Check(Quiz.Main.ticker, "Stop retains discovery for joining another game")
    local stopId = OrbitQuizDB.nextQuestionId
    Test.Advance(60)
    Same(OrbitQuizDB.nextQuestionId, stopId, "stopped quizzes cannot allocate later questions")
    Test.guild, Test.raid, Test.instance = true, true, true

    round = Begin(Settings(nil, VOID_LEAGUE))
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "pending wrong answer before manual pause")
    local voidId = round.id
    Check(Quiz.Main:Pause(nil, false), "manual pause is supported")
    CheckVoided("manual pause voids the current question")
    Test.Advance(30)
    Same(game.state, "stopped", "previous game is not revived by later timers")
    Same(Quiz.Main.game.state, "paused", "manual pause does not auto-resume")
    Check(Quiz.Main:Resume(), "manual resume starts a fresh question")
    round = Quiz.Main.game.round
    Check(round.id > voidId, "resuming never reuses a voided question ID")
    Same(round.deadline, Test.now + 15, "resume receives the fixed answer window")
    Same(Quiz.Main.game.total, 3, "voids never shrink a continuous deck")
    Quiz.Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Test.secret, Enum.AddOnRestrictionState.Active)
    Quiz.Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Test.secret)
    Same(Quiz.Main.game.round, round, "secret restriction payloads are ignored before comparison")
    Test.restricted = true
    Test.Advance(0.1)
    CheckVoided("native lockdown polling also voids the active round")
    Test.restricted = false
    Test.Advance(0.1)
    Same(Quiz.Main.game.state, "open", "native lockdown polling automatically recovers")
    Check(Quiz.Main.game.round.id > round.id, "native lockdown recovery uses a fresh question")
    round = Quiz.Main.game.round
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "wrong answer before communication restriction")
    voidId = round.id
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Activating)
    CheckVoided("activating payload pauses before the native query flips")
    Test.Advance(1)
    Same(Quiz.Main.game.state, "paused", "stale unrestricted API cannot override activating payload")
    Test.restricted = true
    Restriction(Enum.AddOnRestrictionState.Active)
    Test.Advance(3)
    CheckVoided("active restriction keeps the void unscored")
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Inactive)
    Same(Quiz.Main.game.state, "open", "restriction removal automatically resumes a fresh question")
    Check(Quiz.Main.game.round.id > voidId, "restriction recovery allocates a new ID")
    Same(Quiz.Main.game.round.deadline, Test.now + 15, "restriction recovery has the fixed window")

    Check(Quiz.Main:Pause(nil, false), "explicit pause before restriction")
    Test.restricted = true
    Restriction(Enum.AddOnRestrictionState.Active)
    Test.restricted = false
    Restriction(Enum.AddOnRestrictionState.Inactive)
    Same(Quiz.Main.game.state, "paused", "restriction recovery cannot cancel a manual pause")
    Check(Quiz.Main:Resume(), "manually paused game remains resumable")
    voidId = Quiz.Main.game.round.id
    Quiz.Main:OnEvent("CHAT_SERVER_DISCONNECTED")
    CheckVoided("chat-server disconnect voids synchronized gameplay")
    Test.Advance(2)
    Same(Quiz.Main.game.state, "paused", "disconnect remains paused until reconnect")
    Quiz.Main:OnEvent("CHAT_SERVER_RECONNECTED")
    Same(Quiz.Main.game.state, "open", "chat-server reconnect automatically resumes")
    Check(Quiz.Main.game.round.id > voidId, "reconnect replaces the exposed round")
    Quiz.Main:OnEvent("CHAT_SERVER_DISCONNECTED")
    Check(Quiz.Main:Pause(nil, false), "manual pause may take ownership of a disconnected pause")
    Quiz.Main:OnEvent("CHAT_SERVER_RECONNECTED")
    Same(Quiz.Main.game.state, "paused", "manual pause during disconnect remains manual")
    Quiz.Main:Stop()

    for _, automatic in ipairs({ false, true }) do
        local pauseLeague = automatic and "Restricted reveal" or "Manual reveal"
        round = Begin(Settings(nil, pauseLeague))
        Check(Quiz.Session:SubmitAnswer(round.correctIndex), "reveal-pause fixture has a correct answer")
        result = Close()
        local nextAt, savedId = Quiz.Main.nextAutoAt, OrbitQuizDB.nextQuestionId
        local savedScore = Standing(pauseLeague, Test.hostGUID).score
        Test.Advance(1)
        if automatic then
            Restriction(Enum.AddOnRestrictionState.Activating)
        else
            Check(Quiz.Main:Pause(nil, false), "manual pause can interrupt the reveal")
        end
        Same(Quiz.Main.game.state, "paused", "pause interrupts the three-second reveal")
        Same(Quiz.Main.nextAutoAt, nil, "pause cancels the scheduled next question")
        Test.Advance(nextAt - Test.now + REVEAL_SECONDS)
        Same(Quiz.Main.game.state, "paused", "the old reveal deadline cannot restart a paused quiz")
        Same(OrbitQuizDB.nextQuestionId, savedId, "paused reveal allocates no question IDs")
        Same(Quiz.Main.game.completed, 1, "pausing a reveal cannot finalize the same round twice")
        Same(Quiz.Main.game.lastResult, result, "pausing preserves the finalized result")
        Same(Standing(pauseLeague, Test.hostGUID).score, savedScore, "pausing a reveal preserves earned points")
        Same(Standing(pauseLeague, Test.hostGUID).answers, 1, "pausing a reveal preserves exactly one saved answer")
        if automatic then
            Restriction(Enum.AddOnRestrictionState.Inactive)
        else
            Check(Quiz.Main:Resume(), "manual reveal pause resumes on request")
        end
        Same(Quiz.Main.game.state, "open", "reveal recovery starts a fresh question")
        Check(Quiz.Main.game.round.id > round.id, "reveal recovery never reuses the completed question ID")
        Same(Quiz.Main.game.round.deadline - Test.now, 15, "reveal recovery keeps the full answer window")
        Same(Quiz.Main.game.completed, 1, "reveal recovery does not replay the saved result")
        Quiz.Main:Stop()
    end

    local legacySettings = Settings(nil, AUTOMATIC_LEAGUE)
    legacySettings.bridgeChat = true
    legacySettings.channel = "GUILD"
    legacySettings.customChannel = "Retired visible channel"
    legacySettings.channelPassword = "Old password"
    legacySettings.answerMode = "WHISPER"
    OrbitQuizDB.settings = legacySettings
    Quiz.Main:OnEvent("ADDON_LOADED", Quiz.addonName)
    Quiz.Main:OnEvent("PLAYER_LOGIN")
    for _, key in ipairs({ "bridgeChat", "channel", "customChannel", "channelPassword", "answerMode" }) do
        Same(Quiz.Store:GetSettings()[key], nil, "reload drops retired chat setup: " .. key)
    end
    Check(Quiz.Main:Start(), "an old enabled bridge does not require manual publication")
    game = Quiz.Main.game
    Same(game.state, "open", "saved setup opens the widget immediately")
    Same(game.settings.league, AUTOMATIC_LEAGUE, "normal saved setup remains selected")
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
        Same(Quiz.Main.nextAutoAt - Test.now, REVEAL_SECONDS, "results use the automatic three-second intermission")
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
    Quiz.Main:Stop()

    round = Begin(Settings(LONG_PACK, "Long widget"))
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
    Quiz.Main:Stop()

    Test.now = math.floor(Test.now) + 0.2
    round = Begin(Settings(nil, "Fractional deadline"))
    Test.now = round.deadline - 0.000001
    Check(
        Quiz.Main:AcceptAnswer(Quiz.Identity.name, Test.hostGUID, round.id, round.correctIndex),
        "fractional just-before-deadline answer remains valid"
    )
    Test.now = round.deadline
    Check(
        not Quiz.Main:AcceptAnswer("Deadline-TestRealm", "Deadline", round.id, round.correctIndex),
        "runtime rejects answers at its exclusive deadline"
    )
    Quiz.Main:Tick()
    Same(
        Standing("Fractional deadline", Test.hostGUID).score,
        1,
        "near-deadline correct answer earns only the base point"
    )
    Check(Quiz.Main.game.lastResult.answers[1].elapsed <= 15, "elapsed rounding cannot exceed persisted duration")
    Quiz.Main:Stop()

    local beforeNegative = Personal().score
    round = Begin(Settings(nil, "Negative total"))
    Same(Quiz.Main:GetScore(Test.hostGUID), 0, "a new hosted game cannot inherit personal lifetime scores")
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "wrong-answer-only fixture accepts a choice")
    Close()
    Same(Standing("Negative total", Test.hostGUID).score, -1, "wrong answers permit an honest negative session total")
    Same(
        Personal().score,
        Quiz.Scoring.Add(beforeNegative, -1),
        "one negative session updates existing personal progress"
    )
    round = Next()
    Close()
    Same(Standing("Negative total", Test.hostGUID).score, -1, "not answering the next question incurs no penalty")
    Same(
        Standing("Negative total", Test.hostGUID).answers,
        1,
        "an unanswered question does not count as a wrong answer"
    )
    round = Next()
    Check(Quiz.Session:SubmitAnswer(round.correctIndex % 4 + 1), "another wrong selection may remain unfinalized")
    Check(Quiz.Main:Pause(nil, false), "pausing voids the pending wrong answer")
    Same(Standing("Negative total", Test.hostGUID).score, -1, "voiding a wrong answer does not deduct another penalty")
    Same(
        Standing("Negative total", Test.hostGUID).answers,
        1,
        "voiding preserves the previously finalized answer count"
    )
    Quiz.Main:Stop()

    chatBefore = #Test.sent
    Same(Quiz.Main.notice, Quiz.L.STATUS_STOPPED, "stopping a hosted session exposes its stopped notice")
    SlashCmdList.ORBITQUIZ("join Remote-TestRealm")
    Same(Quiz.Main.notice, nil, "joining another host clears the old local host's stopped notice")
    Same(Quiz.Session:GetView().state, "joining", "slash join opens participant connection state")
    Same(Quiz.Session:GetView().hostName, "Remote-TestRealm", "join target is retained with realm")
    Check(Quiz.Widget.frame:IsShown(), "joining opens the player widget")
    Quiz.UI.frame:Show()
    local connectionNotice = Quiz.Session.view.notice
    Quiz.Main.notice, Quiz.Session.view.notice = "Old host notice", "Participant connection notice"
    Quiz.UI:Refresh()
    Same(
        Quiz.UI.notice:GetText(),
        "Participant connection notice",
        "active participant notices outrank old host notices"
    )
    Quiz.Main.notice, Quiz.Session.view.notice = nil, connectionNotice
    Quiz.UI.frame:Hide()
    Check(Quiz.Comms:IsBusy(), "join queues addon communication")
    local addonBefore = #Test.addonSent
    Test.Advance(0.1)
    Check(#Test.addonSent > addonBefore, "addon synchronization sends without public-chat hardware")
    Same(Test.addonSent[#Test.addonSent].channel, "WHISPER", "synchronization uses targeted addon messages")
    Same(Test.addonSent[#Test.addonSent].target, "Remote-TestRealm", "join packets target only the selected host")
    Same(#Test.sent, chatBefore, "joining does not require public chat")
    SlashCmdList.ORBITQUIZ("leave")
    Same(Quiz.Session:GetView().state, "idle", "slash leave clears participant state")
    Check(Quiz.Comms:IsBusy(), "leaving an unconfirmed join queues cancellation for its request")
    Test.Advance(1)
    Check(Quiz.Main.ticker, "idle participant keeps discovery available")
    Check(not Quiz.Session:JoinHost(Test.hostName .. "-" .. Test.realm), "joining oneself is rejected")
    for _, name in ipairs({ "", "Other Realm", "Other|Realm", Test.secret, true }) do
        Check(not Quiz.Session:JoinHost(name), "malformed host names are rejected before communication")
    end
    Check(Quiz.Session:JoinHost("Absent-TestRealm"), "offline fixture begins joining")
    Test.Advance(13)
    Same(Quiz.Session:GetView().state, "disconnected", "unanswered join times out")
    Check(not Quiz.Comms:IsBusy(), "join timeout clears stale request packets")
    Quiz.Session:Leave()
    Quiz.Main:Tick()

    Quiz.UI:Toggle()
    Same(Quiz.UI.duration, nil, "there is no editable answer duration")
    Same(Quiz.UI:ReadSettings().duration, 15, "host setup always supplies the fixed fifteen-second clock")
    Quiz.UI.league:SetText("UI start")
    Quiz.UI.draft.packId = SHORT_PACK
    Quiz.UI.start.scripts.OnClick()
    Same(Quiz.Main.game.state, "open", "host Start button starts widget-first gameplay")
    Quiz.UI.pause.scripts.OnClick()
    Same(Quiz.Main.game.state, "paused", "host Pause button pauses")
    Quiz.UI.pause.scripts.OnClick()
    Same(Quiz.Main.game.state, "open", "same host control resumes fresh")
    Quiz.UI.stop.scripts.OnClick()
    Same(Quiz.Main.game.state, "stopped", "host Stop button ends gameplay")

    round = Begin(Settings(nil, "Reload active"))
    Check(Quiz.Session:SubmitAnswer(round.correctIndex), "unfinished reload fixture has an accepted answer")
    local saved = OrbitQuizDB
    local nextId = saved.nextQuestionId
    local savedScore, savedAnswers = Personal().score, Personal().answers
    Quiz.Main:OnEvent("PLAYER_LOGOUT")
    Check(not Quiz.Main.ticker, "logout cancels the runtime ticker")
    Check(not Quiz.Comms:IsBusy(), "logout clears addon transport")
    Same(#Test.sent, 0, "logout never emits visible chat")
    CheckNoTickers("logout leaves no active timer")
    Same(#Quiz.Store:GetStandings("Reload active", "PUBLIC"), 0, "logout cannot persist an unfinished answer")
    Same(saved.round, nil, "active round is absent from saved data")
    Same(saved.game, nil, "runtime game is absent from saved data")
    Quiz.Main.game = nil
    Quiz.Main.nextAutoAt = nil
    Quiz.Main:OnEvent("ADDON_LOADED", "Orbit-Quiz")
    Quiz.Main:OnEvent("PLAYER_LOGIN")
    Same(OrbitQuizDB.schemaVersion, 6, "reload preserves the personal-pack schema version")
    Same(OrbitQuizDB.nextQuestionId, nextId, "reload preserves the monotonic counter")
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
    Same(Quiz.Store:GetSettings().hostName, "Absent-TestRealm", "saved participant host survives reload")
    Quiz.UI.frame:Show()
    Quiz.UI.boardScope = "personal"
    Quiz.UI:SetTab("scores")
    Quiz.UI:LoadSettings()
    local getPacks, boardReads = Quiz.PersonalScores.GetPacks, 0
    Quiz.PersonalScores.GetPacks = function(owner, ...)
        boardReads = boardReads + 1
        return getPacks(owner, ...)
    end
    Quiz.UI:Refresh()
    Same(boardReads, 1, "personal board builds from saved pack totals on invalidation")
    for _ = 1, 20 do
        Quiz.UI:Refresh()
    end
    Same(boardReads, 1, "timer refreshes do not sort unchanged persistent standings")
    Quiz.UI:LoadSettings()
    Quiz.UI:Refresh()
    Same(boardReads, 2, "settings reload invalidates the board cache")
    Quiz.PersonalScores.GetPacks = getPacks
    Same(#Test.errors, 0, "runtime never invokes the unexpected-error handler")
    return assertions
end

local SAMPLE_COUNT = 32
local MAX_PLAYERS = 17
local ROW_HEIGHT = 52
local LIVE_HOST = "Actualhost-TestRealm"
local LIVE_SESSION = "actual-session.1"
local LIVE_QUESTION = "The real question must remain active."
local LEAGUE = "Preview regression"
local PREFIX = "ORBITQUIZDISC8"
local EPSILON = 0.000001
local SCROLL_HOSTS = { "Zscrollone", "Zscrolltwo", "Zscrollthree", "Zscrollfour", "Zscrollfive" }

return function(Quiz, development)
    local assertions = 0
    local UI, Main, Session, Discovery, Dev = Quiz.UI, Quiz.Main, Quiz.Session, Quiz.Discovery, Quiz.Development
    local defaultRulesKey = Quiz.Rules.Encode(Quiz.Rules.Normalize())
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
    local function Count(values)
        local count = 0
        for _ in pairs(values) do
            count = count + 1
        end
        return count
    end
    local function Click(button)
        Check(button:IsEnabled(), "a normal click requires an enabled native control")
        button:GetScript("OnClick")(button)
    end
    local function Advertise(hostName, session)
        Check(
            Discovery:Receive(
                PREFIX,
                "8|A|" .. (session or LIVE_SESSION) .. "|Real question pack|" .. LEAGUE .. "|open|3",
                "GUILD",
                hostName or LIVE_HOST,
                "",
                0,
                0,
                ""
            ),
            "an actual addon advertisement seeds the live browser"
        )
    end

    Same(UI.gamePreview, nil, "loading the addon never enables a browser preview")
    Same(UI.frame, nil, "loading the addon does not open development UI")
    Same(_G.Orbit, nil, "preview and normal browser remain independent of Orbit")
    if not development then
        Same(Dev, nil, "packaged addon has no development module")
        Same(SLASH_ORBITQUIZDEV1, nil, "packaged addon has no development slash command")
        Same(SlashCmdList.ORBITQUIZDEV, nil, "packaged addon has no development command handler")
        for key in pairs(Quiz.L) do
            Check(not key:match("^DEV_"), "packaged localization has no development-only text")
        end
        Advertise()
        UI:Toggle()
        Same(UI.gamesTitle:GetText(), Quiz.L.W_AVAILABLE_GAMES, "packaged browser keeps the normal heading")
        Same(#UI.gameRows, 1, "packaged browser still shows real advertisements")
        Same(UI.gameRows[1].game.hostName, LIVE_HOST, "packaged row belongs to the actual advertised host")
        Check(not UI.gameRows[1].game.preview, "packaged live row is not marked as a sample")
        Click(UI.gameRows[1].join)
        Same(Session.client.name, LIVE_HOST, "packaged browser joins without any development dependency")
        return assertions
    end

    Check(Dev, "developer checkout loads the optional fixture module")
    Same(Dev.enabled, false, "development preview starts disabled")
    Same(Dev.games, nil, "sample data is allocated only when requested")
    Same(SLASH_ORBITQUIZDEV1, "/oqdev", "development command is separate from normal player commands")
    Same(type(SlashCmdList.ORBITQUIZDEV), "function", "development command has a registered handler")
    local refreshCalls, joinCalls = 0, 0
    local originalRefresh, originalJoin = Discovery.Refresh, Session.JoinHost
    Discovery.Refresh = function(self)
        refreshCalls = refreshCalls + 1
        return originalRefresh(self)
    end
    Session.JoinHost = function(self, ...)
        joinCalls = joinCalls + 1
        return originalJoin(self, ...)
    end
    local function World()
        return {
            saved = OrbitQuizDB,
            store = Quiz.Store.db,
            discovery = Discovery,
            session = Session,
            identity = Quiz.Identity,
            comms = Quiz.Comms,
            runtime = Main,
            sends = #Test.addonSent,
            publicSends = #Test.sent,
            channelJoins = #Test.joins,
            tickers = #Test.tickers,
            refreshCalls = refreshCalls,
            joinCalls = joinCalls,
        }
    end
    local function Quiet(action, message)
        local before = Clone(World())
        local database, client, game, listings = Quiz.Store.db, Session.client, Main.game, Discovery.games
        action()
        Equal(World(), before, message)
        Same(Quiz.Store.db, database, message .. " retains the database object")
        Same(OrbitQuizDB, database, message .. " retains SavedVariables ownership")
        Same(Session.client, client, message .. " retains the active membership object")
        Same(Main.game, game, message .. " retains the active game object")
        Same(Discovery.games, listings, message .. " retains the real discovery cache")
    end
    local function NoDummyJoins()
        Quiet(function()
            for _, row in ipairs(UI.gameRows) do
                Check(not row.join:IsEnabled(), "dummy Join controls are disabled")
                row.join:GetScript("OnClick")(row.join)
            end
        end, "even direct sample Join callbacks have no gameplay or network effects")
    end

    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("not-a-command")
    end, "an unknown developer command only prints help")
    Same(Test.messages[#Test.messages]:sub(-#Quiz.L.DEV_HELP), Quiz.L.DEV_HELP, "invalid command shows help")
    Same(Dev.enabled, false, "invalid command cannot enable preview")
    Same(UI.frame, nil, "invalid command cannot open a window")
    Check(Quiz.Store:SaveSettings({ league = LEAGUE }), "test creates an existing saved league preference")
    Check(Quiz.Store:SaveWidgetPosition(0.31, 0.72), "test creates an existing saved HUD position")
    Check(
        Quiz.Store:RecordRound(LEAGUE, "PUBLIC", {
            id = Quiz.Store:NextQuestionId(),
            questionKey = "retained:one",
            number = 1,
            cycle = 1,
            duration = 15,
            scoringVersion = 2,
            answers = {
                {
                    guid = "Player-0-SAVED",
                    name = "Saved-TestRealm",
                    choiceIndex = 1,
                    correct = true,
                    elapsed = 2,
                    points = 2.3,
                },
            },
        }),
        "test creates real saved scores and round history"
    )
    OrbitQuizDB.legacyLeagues.Legacy = {
        PUBLIC = {
            lastRoundId = 1,
            players = {
                ["Player-0-LEGACY"] = {
                    name = "Legacy-TestRealm",
                    score = 120,
                    correct = 1,
                    incorrect = 0,
                    answers = 1,
                },
            },
            history = {},
        },
    }
    Advertise()
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("")
    end, "bare development command opens a UI-only preview")
    Same(Dev.enabled, true, "bare command enables the preview")
    Check(UI.frame:IsShown(), "preview opens the existing setup window")
    Same(UI.tab, "play", "preview selects Available Games")
    Same(UI.gamesTitle:GetText(), Quiz.L.DEV_GAMES_TITLE, "preview heading visibly identifies development data")
    Same(UI.notice:GetText(), Quiz.L.DEV_GAMES_NOTICE, "preview notice clearly labels sample-only games")
    Same(#UI.gameRows, SAMPLE_COUNT, "a full page-overflowing set of thirty-two samples appears")
    Same(#UI.gamePreview.games, SAMPLE_COUNT, "preview data uses the full native browser capacity")
    Check(not UI.gamesEmpty:IsShown(), "populated preview does not show an empty-list hint")
    Same(UI.frame.Chrome.Background.atlas, "housing-basic-container", "preview preserves the native dialog shell")
    Same(UI.current:GetText(), Quiz.L.W_NO_SESSION, "sample games do not invent a current session")
    Check(not UI.leave:IsEnabled(), "an idle preview cannot leave a nonexistent session")
    local hosts, sessions, packs, leagues, states, counts, originalRows = {}, {}, {}, {}, {}, {}, {}
    local utf8Host, utf8Pack, longHost, longPack = false, false, false, false
    for index, row in ipairs(UI.gameRows) do
        local game = row.game
        originalRows[row] = true
        Same(game.preview, true, "every fixture has the inert preview marker")
        for _, field in ipairs({ "hostName", "session", "packName", "league", "state" }) do
            Check(type(game[field]) == "string" and game[field] ~= "", "sample has native field " .. field)
        end
        Check(not hosts[game.hostName], "dummy hosts are unique")
        Check(not sessions[game.session], "dummy session tokens are unique")
        hosts[game.hostName], sessions[game.session] = true, true
        packs[game.packName], leagues[game.league], states[game.state], counts[game.players] = true, true, true, true
        Check(game.players % 1 == 0 and game.players >= 1 and game.players <= MAX_PLAYERS, "player count is realistic")
        utf8Host = utf8Host or game.hostName:find("[\128-\255]") ~= nil
        utf8Pack = utf8Pack or game.packName:find("[\128-\255]") ~= nil
        longHost = longHost or #game.hostName > 24
        longPack = longPack or #game.packName > 48
        Same(row.host:GetText(), game.hostName, "row renders its actual sample host text")
        Same(
            row.detail:GetText(),
            Quiz.L.W_GAME_DETAIL_F:format(game.packName, game.players),
            "sample detail uses the same formatter as a real advertisement"
        )
        Same(row.host.wordWrap, false, "long host names retain native one-line truncation")
        Same(row.detail.wordWrap, false, "long pack names retain native one-line truncation")
        Same(row.join.template, "UIPanelButtonTemplate", "sample rows use native Join buttons")
        Same(row:GetHeight(), ROW_HEIGHT, "fixture strings cannot grow pooled rows")
        Same(row.point[5], -(index - 1) * ROW_HEIGHT, "rows occupy consecutive scroll slots")
        Check(row:IsShown(), "all sample rows participate in the scroll content")
    end
    Same(Count(hosts), SAMPLE_COUNT, "sample collection contains thirty-two distinct hosts")
    Check(Count(packs) >= 8, "sample collection covers many different question pack labels")
    Check(Count(leagues) >= 3, "sample collection covers different leagues")
    Check(Count(states) >= 3, "sample collection covers active and inactive round states")
    Same(Count(counts), MAX_PLAYERS, "samples cover every supported player count")
    Check(utf8Host and utf8Pack, "sample hosts and question packs exercise UTF-8")
    Check(longHost and longPack, "sample labels exercise clipping with long names")
    local sampleData = Clone(UI.gamePreview.games)
    local allocated = #Test.frames
    Same(UI.gamesContent:GetHeight(), SAMPLE_COUNT * ROW_HEIGHT, "scroll content includes every sample row")
    local range = UI.gamesScroll:GetVerticalScrollRange()
    Check(range > UI.gamesScroll:GetHeight(), "preview overflows by multiple screens")
    local bar = UI.gamesScroll.QuizScrollBar
    Check(bar:IsShown(), "preview reveals the existing thin scrollbar")
    bar:ScrollTo(range, true)
    Same(UI.gamesScroll:GetVerticalScroll(), range, "scrollbar reaches the last sample")
    Check(
        math.abs(range + UI.gamesScroll:GetHeight() - UI.gamesContent:GetHeight()) < EPSILON,
        "last sample is inside the reachable scroll extent"
    )
    Quiet(function()
        Click(UI.refreshGames)
        UI.nextGamesRefresh = nil
        UI:Refresh()
        UI.frame:Hide()
        UI.frame:Show()
    end, "refresh and reopening a preview cannot query discovery")
    Same(#Test.frames, allocated, "refresh and reopening reuse the existing row pool")
    Same(UI.gamesScroll:GetVerticalScroll(), range, "ordinary preview refresh preserves scroll position")
    NoDummyJoins()
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("unknown")
    end, "unknown command during preview has no gameplay effects")
    Same(Dev.enabled, true, "invalid command cannot disable an active preview")
    Same(#UI.gameRows, SAMPLE_COUNT, "invalid command preserves the sample list")
    UI.league:SetText("An unsaved draft")
    UI.draft.packId = "warcraft-lore"
    local draft = Clone(UI.draft)
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("off")
    end, "disabling preview restores live discovery without touching gameplay")
    Same(Dev.enabled, false, "off disables the development preview")
    Same(UI.gamePreview, nil, "off detaches sample data from the production browser")
    Same(UI.gamesTitle:GetText(), Quiz.L.W_AVAILABLE_GAMES, "off restores the regular browser title")
    Same(UI.gamesScroll:GetVerticalScroll(), 0, "switching back to live listings resets scroll")
    Same(#UI.gameRows, 1, "off restores the actual discovery list")
    Same(UI.gameRows[1].game.hostName, LIVE_HOST, "restored row points at the real host")
    Check(originalRows[UI.gameRows[1]], "real listing reuses a former sample row")
    Check(UI.gameRows[1].join:IsEnabled(), "reused row restores its live Join control")
    Equal(UI.draft, draft, "preview preserves unsaved host pack selection")
    Same(UI.league:GetText(), "An unsaved draft", "preview preserves unsaved host league text")
    Quiet(function()
        for _, row in ipairs(UI.gameRowPool.inactive) do
            Same(row.game, nil, "released sample rows discard their old host")
            row.join:GetScript("OnClick")(row.join)
        end
    end, "inactive pooled callbacks remain inert")
    for _ = 1, 4 do
        Quiet(function()
            SlashCmdList.ORBITQUIZDEV("  GAMES  ")
        end, "repeated preview activation remains local")
        Equal(UI.gamePreview.games, sampleData, "fixture data is deterministic across toggles")
        Same(#UI.gameRows, SAMPLE_COUNT, "all sample rows return on every activation")
        for _, row in ipairs(UI.gameRows) do
            Check(originalRows[row], "repeated activation only acquires existing pooled rows")
        end
        Quiet(function()
            Dev:HideGames()
        end, "repeated deactivation remains local")
        Same(#Test.frames, allocated, "preview toggles do not allocate additional frames")
    end
    for index, host in ipairs(SCROLL_HOSTS) do
        Advertise(host .. "-TestRealm", "scroll-live." .. index)
    end
    UI.nextGamesRefresh = nil
    UI:Refresh()
    Same(#UI.gameRows, #SCROLL_HOSTS + 1, "a separate real listing fixture overflows the live viewport")
    local function BeginMovement(mode)
        bar:ScrollTo(UI.gamesScroll:GetVerticalScrollRange(), true)
        Check(UI.gamesScroll:GetVerticalScroll() > 0, "movement starts in a genuinely overflowing list")
        if mode == "animation" then
            bar:ScrollTo(0)
            Check(bar.scrollTarget ~= nil, "fixture starts a pending wheel-style scroll target")
            Check(bar.Animator:IsShown(), "fixture starts an active scrollbar animation")
        else
            bar:GetScript("OnDragStart")(bar)
            Check(bar.dragY ~= nil, "fixture starts an active scrollbar drag")
            Check(bar:GetScript("OnUpdate"), "fixture installs the drag update callback")
        end
    end
    local function StoppedMovement()
        Same(UI.gamesScroll:GetVerticalScroll(), 0, "switching list sources resets to the first row")
        Same(bar.scrollTarget, nil, "switching list sources discards pending scroll targets")
        Same(bar.Animator:GetScript("OnUpdate"), nil, "switching list sources cancels animation callbacks")
        Check(not bar.Animator:IsShown(), "switching list sources stops the animation frame")
        Same(bar.dragY, nil, "switching list sources discards drag state")
        Same(bar:GetScript("OnUpdate"), nil, "switching list sources cancels drag callbacks")
        UI.nextGamesRefresh = nil
        UI:Refresh()
        Same(UI.gamesScroll:GetVerticalScroll(), 0, "refresh cannot revive the obsolete movement")
    end
    for _, mode in ipairs({ "animation", "drag" }) do
        BeginMovement(mode)
        Quiet(function()
            Dev:ShowGames()
        end, "enabling preview cancels old live-list movement without gameplay effects")
        StoppedMovement()
        BeginMovement(mode)
        Quiet(function()
            Dev:HideGames()
        end, "disabling preview cancels old sample-list movement without gameplay effects")
        StoppedMovement()
        Same(#UI.gameRows, #SCROLL_HOSTS + 1, "cancelling preview movement restores every actual listing")
        Check(UI.gamesScroll:GetVerticalScrollRange() > 0, "live range remains positive after movement is cancelled")
        Same(#Test.frames, allocated, "scroll cancellation still reuses the same frame pool")
    end
    local previousRefresh = refreshCalls
    Click(UI.refreshGames)
    Same(refreshCalls, previousRefresh + 1, "live Refresh regains its real discovery behavior")
    Click(UI.gameRows[1].join)
    Same(Session.client.name, LIVE_HOST, "reused sample button joins its current live host")
    local client = Session.client
    Session:Receive(LIVE_HOST, { "W", client.request, LIVE_SESSION, LEAGUE, "5.4" })
    Session:Receive(LIVE_HOST, {
        "Q",
        LIVE_SESSION,
        "500",
        "1",
        "1",
        "1",
        "15",
        LIVE_QUESTION,
        "4",
        "",
        "",
        "test-pack",
        "Test pack",
        "1",
        "3",
        defaultRulesKey,
        "A",
        "B",
        "C",
        "D",
    })
    Session:Receive(LIVE_HOST, { "O", LIVE_SESSION, "500", tostring(GetServerTime() + 15) })
    Quiz.Widget:Refresh()
    Same(Session:GetView().state, "open", "real participant receives an active question")
    Quiet(function()
        Dev:ShowGames()
    end, "preview preserves an active participant session")
    Same(Session.client, client, "preview never replaces the participant membership")
    Same(Quiz.Widget.prompt:GetText(), LIVE_QUESTION, "real participant HUD survives the game-list preview")
    Check(UI.current:GetText():find(LIVE_HOST, 1, true), "current-session label retains the actual host")
    Check(UI.leave:IsEnabled(), "real participants retain their explicit Leave control")
    NoDummyJoins()
    Click(Quiz.Widget.choices[2])
    Same(Session.view.selected, 2, "real widget answers remain usable while the list is previewed")
    Quiet(function()
        Dev:HideGames()
    end, "leaving preview preserves the real answer and membership")
    Check(not UI.gameRows[1].join:IsEnabled(), "restored live row reflects its already-joined status")
    Same(Session.view.selected, 2, "preview toggling preserves the current real answer")
    Check(Session:Leave(), "test explicitly leaves its real session")
    Check(Main:Start(Quiz.Store:GetSettings()), "test starts a real automatic host")
    local game, hostedSession = Main.game, Session.hostSession
    local firstRound = game.round
    Quiet(function()
        Dev:ShowGames()
    end, "preview preserves the active host game and its question deadline")
    Same(Session.hostSession, hostedSession, "preview leaves the actual hosted session in place")
    NoDummyJoins()
    Click(Quiz.Widget.choices[firstRound.correctIndex])
    Test.Advance(firstRound.deadline - Test.now)
    Same(game.state, "results", "hosted question still closes while preview is active")
    Same(game.completed, 1, "real answers still score while preview is active")
    Test.Advance(5)
    Same(game.state, "open", "host automatically starts the next question through preview")
    Same(game.round.deadline - Test.now, Quiz.ANSWER_SECONDS, "preview never changes the fifteen-second answer clock")
    Same(#UI.gameRows, SAMPLE_COUNT, "automatic runtime refreshes keep the preview list visible")
    Same(Dev.enabled, true, "host progression does not turn preview off unexpectedly")
    for _, packet in ipairs(Test.addonSent) do
        Check(not hosts[packet.target], "no addon packet is addressed to a sample host")
        for session in pairs(sessions) do
            Check(not packet.text:find(session, 1, true), "sample session tokens never enter addon traffic")
        end
    end
    Quiet(function()
        Dev:HideGames()
    end, "hiding a host preview retains scores and the next automatic round")
    Same(Main.game, game, "active automatic game is unchanged after preview ends")
    Same(Session.hostSession, hostedSession, "hosting membership is unchanged after preview ends")
    Same(#Quiz.Store:GetStandings(LEAGUE, "PUBLIC"), 1, "new gameplay cannot add participants to archived leagues")
    Same(Quiz.Store:GetStandings(LEAGUE, "PUBLIC")[1].score, 2.3, "existing saved player's score survives preview")
    Same(Quiz.PersonalScores:GetPack(firstRound.packId).answers, 1, "real personal progress persists through preview")
    Same(Quiz.Store:GetLegacyStandings("Legacy", "PUBLIC")[1].score, 120, "archived score scale survives preview")
    Main:Stop()
    Test.restricted = true
    Quiet(function()
        Dev:ShowGames()
        Click(UI.refreshGames)
        UI.frame:Hide()
        UI.frame:Show()
        Dev:HideGames()
    end, "preview works locally while communication is restricted")
    Test.restricted = false
    Same(Dev.enabled, false, "cleanup leaves development preview disabled")
    Same(UI.gamePreview, nil, "cleanup restores the real browser")
    Same(#Test.sent, 0, "development preview never publishes visible chat")
    return assertions
end

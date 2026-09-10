local ARCHIVE_PLAYER_COUNT = 25
local SCORE_COLUMN_GAP = 8
local EPSILON = 0.000001

return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local L = Quiz.L
    local Main, PersonalScores, ScoreView, Session, Store, UI =
        Games.Main, Quiz.PersonalScores, Quiz.ScoreView, Quiz.Session, Quiz.Store, Games.UI

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Near(actual, expected, message)
        Check(
            math.abs(actual - expected) < EPSILON,
            message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
        )
    end

    local function Count(set)
        local count = 0
        for _ in pairs(set) do
            count = count + 1
        end
        return count
    end

    local function Contains(values, expected)
        for _, value in ipairs(values) do
            if value == expected then
                return true
            end
        end
        return false
    end

    local function Copy(value, seen)
        if type(value) ~= "table" then
            return value
        end
        seen = seen or {}
        if seen[value] then
            return seen[value]
        end
        local result = {}
        seen[value] = result
        for key, child in pairs(value) do
            result[Copy(key, seen)] = Copy(child, seen)
        end
        return result
    end

    local function Equal(left, right, seen)
        if type(left) ~= type(right) then
            return false
        elseif type(left) ~= "table" then
            return left == right
        end
        seen = seen or {}
        if seen[left] then
            return seen[left] == right
        end
        seen[left] = right
        for key, value in pairs(left) do
            if not Equal(value, right[key], seen) then
                return false
            end
        end
        for key in pairs(right) do
            if left[key] == nil then
                return false
            end
        end
        return true
    end

    local function SameTable(actual, expected, message)
        Check(Equal(actual, expected), message)
    end

    local function ExpectedRules(rules, label)
        local streak = rules.streakBonusPerCorrect > 0
                and L.W_SCORE_RULE_STREAK_F:format(rules.streakBonusPerCorrect, rules.streakBonusMax)
            or L.W_SCORE_RULE_NO_STREAK
        return L.W_SCORE_RULE_DETAILS_F:format(
            label,
            rules.answerSeconds,
            rules.correctPoints,
            rules.speedBonusPerSecond,
            rules.wrongPenaltyStart,
            rules.wrongPenaltyEnd,
            rules.wrongPenaltyCurve,
            streak
        )
    end

    local function Refresh(scope, view)
        ScoreView.scope = scope
        ScoreView:Invalidate()
        ScoreView:Refresh(view)
    end

    local function FindScope(scope)
        ScoreView.scopeSwitch:OpenMenu()
        for _, entry in ipairs(ScoreView.scopeSwitch:GetMenuDescription().entries) do
            if entry:GetData() == scope then
                return entry
            end
        end
    end

    local rulesA = Quiz.Rules.Normalize({
        version = 7,
        answerSeconds = 20,
        correctPoints = 3.2,
        speedBonusPerSecond = 0.2,
        wrongPenaltyStart = 4.5,
        wrongPenaltyEnd = 1.2,
        wrongPenaltyCurve = 3.1,
    })
    local rulesB = Quiz.Rules.Normalize({
        version = 7,
        answerSeconds = 30,
        correctPoints = 4.4,
        speedBonusPerSecond = 0.3,
        wrongPenaltyStart = 6.5,
        wrongPenaltyEnd = 2.1,
        wrongPenaltyCurve = 4.2,
        streakBonusPerCorrect = 0.4,
        streakBonusMax = 2,
    })
    local rulesC = Quiz.Rules.Normalize({ version = 8, answerSeconds = 10 })
    local rulesKeyA, rulesKeyB, rulesKeyC =
        Quiz.Rules.Encode(rulesA), Quiz.Rules.Encode(rulesB), Quiz.Rules.Encode(rulesC)
    local personalFixture = {
        {
            id = "removed-quiz",
            title = "Removed quiz whose saved title remains available",
            score = 9.5,
            rounds = 5,
            correct = 1,
            incorrect = 2,
            unanswered = 2,
            archived = true,
        },
        {
            id = "same-quiz",
            title = "A deliberately long quiz title that must never overlap the score column",
            score = 0,
            rounds = 8,
            correct = 3,
            incorrect = 2,
            unanswered = 3,
            archived = false,
            rulesKey = rulesKeyA,
            rules = rulesA,
        },
        {
            id = "same-quiz",
            title = "A deliberately long quiz title that must never overlap the score column",
            score = 0,
            rounds = 6,
            correct = 0,
            incorrect = 4,
            unanswered = 2,
            archived = false,
            rulesKey = rulesKeyB,
            rules = rulesB,
        },
        {
            id = "same-quiz",
            title = "A deliberately long quiz title that must never overlap the score column",
            score = 19.3,
            rounds = 12,
            correct = 8,
            incorrect = 1,
            unanswered = 3,
            archived = false,
            rulesKey = rulesKeyC,
            rules = rulesC,
        },
    }
    local personalSnapshot = Copy(personalFixture)
    local personalRows = personalFixture
    local personalReads = 0
    local archivedLeagues = { "Many Players" }
    local archiveStandings, legacyStandings = {}, {}
    for index = 1, ARCHIVE_PLAYER_COUNT do
        archiveStandings[index] = {
            guid = "archive-" .. index,
            name = (index == ARCHIVE_PLAYER_COUNT and string.rep("Last archived player ", 8) or "Archived player ")
                .. index,
            score = index + 0.3,
            answers = index + 2,
            correct = index,
            incorrect = 2,
        }
        legacyStandings[index] = {
            guid = "legacy-" .. index,
            name = "Legacy player " .. index,
            score = index * 100,
            answers = index + 4,
            correct = index + 1,
            incorrect = 3,
        }
    end
    local archiveSnapshot, legacySnapshot = Copy(archiveStandings), Copy(legacyStandings)
    local archiveReads, legacyReads = 0, 0
    local currentView = { state = "idle" }
    local original = {
        getScoreRows = PersonalScores.GetScoreRows,
        getPack = PersonalScores.GetPack,
        getPacks = PersonalScores.GetPacks,
        getQuestionPacks = Quiz.GetPacks,
        getPackRules = Quiz.GetRules,
        getQuestions = Quiz.GetQuestions,
        getArchivedLeagues = Store.GetArchivedLeagues,
        getStandings = Store.GetStandings,
        getLegacyStandings = Store.GetLegacyStandings,
        getView = Session.GetView,
        game = Quiz.Controller.game,
    }

    UI:Toggle()
    Same(ScoreView.page, UI.modePages[Quiz.id].results, "ScoreView owns the Quiz results page")
    Check(
        ScoreView.scopeSwitch and ScoreView.scroll and ScoreView.content,
        "ScoreView owns its switch and scroll surface"
    )
    Check(ScoreView.empty and ScoreView.rowPool, "ScoreView owns its empty state and frame pool")
    Same(ScoreView.hint, nil, "Scores creates no passive guidance block")
    Near(ScoreView.scroll:GetBottom(), ScoreView.page:GetBottom(), "the score list reclaims the removed hint lane")

    PersonalScores.GetScoreRows = function()
        personalReads = personalReads + 1
        return personalRows
    end
    local function RejectRegistryRead()
        error("ScoreView must not rebuild personal history from the installed pack registry")
    end
    PersonalScores.GetPack, PersonalScores.GetPacks = RejectRegistryRead, RejectRegistryRead
    Quiz.GetPacks, Quiz.GetRules, Quiz.GetQuestions = RejectRegistryRead, RejectRegistryRead, RejectRegistryRead
    Store.GetArchivedLeagues = function()
        return archivedLeagues
    end
    Store.GetStandings = function(_, league, mode)
        archiveReads = archiveReads + 1
        Same(league, "Many Players", "archive reads the saved league name")
        Same(mode, "PUBLIC", "archive reads only the saved public standings")
        return archiveStandings
    end
    Store.GetLegacyStandings = function(_, league, mode)
        legacyReads = legacyReads + 1
        Same(league, "Many Players", "legacy archive reads the saved league name")
        Same(mode, "PUBLIC", "legacy archive reads only the saved public standings")
        return legacyStandings
    end
    Session.GetView = function()
        return currentView
    end

    UI:SetTab("results")
    Same(ScoreView.scope, "personal", "Scores defaults to personal score")
    local scopeSwitch = ScoreView.scopeSwitch
    scopeSwitch:OpenMenu()
    Check(scopeSwitch:IsMenuOpen(), "scope switch opens through the native menu lifecycle")
    local scopeEntries = scopeSwitch:GetMenuDescription().entries
    local expectedScopes = { "personal", "game" }
    local expectedTitles = {
        L.W_SCORE_SCOPE_PERSONAL,
        L.W_SCORE_SCOPE_GAME,
    }
    Same(#scopeEntries, #expectedScopes, "scope switch exposes exactly two live score sources")
    for index, scope in ipairs(expectedScopes) do
        Same(scopeEntries[index]:GetData(), scope, "scope switch preserves source order " .. index)
        Same(scopeEntries[index].text, expectedTitles[index], "scope switch uses current score terminology " .. index)
        Check(scopeEntries[index]:IsRadio(), "every score scope is a native radio entry")
        Same(scopeEntries[index]:IsSelected(), scope == "personal", "only the personal scope starts selected")
    end
    Same(FindScope("archive"), nil, "archived league standings are absent from the dropdown")
    Same(FindScope("legacy"), nil, "archived 100-point standings are absent from the dropdown")
    ScoreView:CloseMenu()
    Check(not scopeSwitch:IsMenuOpen(), "ScoreView closes its owned native menu")
    scopeSwitch:OpenMenu()
    UI:SetTab("play")
    Check(not scopeSwitch:IsMenuOpen(), "leaving Scores closes the scope menu")
    UI:SetTab("results")

    Same(personalReads, 1, "rendering personal history performs one canonical projection read")
    Same(#ScoreView.rows, #personalFixture, "personal history renders one row per canonical score row")
    local archivedRow, firstVariant, secondVariant, newRevision = unpack(ScoreView.rows)
    Same(archivedRow.kind, "personal", "earlier scoring remains a personal-history row")
    Same(archivedRow.record, personalFixture[1], "personal rows expose their canonical record")
    Same(archivedRow.player, nil, "personal rows never expose a standing player")
    Same(archivedRow.Title:GetText(), personalFixture[1].title, "removed packs retain their saved titles")
    Same(archivedRow.Score:GetText(), L.W_SCORE_POINTS_F:format(9.5), "earlier totals use decimal points")
    Same(archivedRow.Rules, nil, "personal rows do not create a scoring-explanation label")
    Same(
        archivedRow.Details:GetText(),
        L.W_SCORE_QUESTION_STATS_F:format(5, 1, 2, 2),
        "personal details distinguish correct, wrong and unanswered questions"
    )
    Same(firstVariant.record, personalFixture[2], "first authored variant retains its exact rulesKey record")
    Same(firstVariant.Score:GetText(), L.W_SCORE_POINTS_F:format(0), "zero personal totals remain visible")
    Same(firstVariant.Rules, nil, "personal score has no authored-rule prose label")
    Same(secondVariant.record, personalFixture[3], "second authored variant remains a separate rulesKey record")
    Same(secondVariant.Score:GetText(), L.W_SCORE_POINTS_F:format(0), "penalty-only personal totals stay at zero")
    Same(secondVariant.Rules, nil, "other personal rulesets have no rule-prose label")
    Same(
        secondVariant.Details:GetText(),
        L.W_SCORE_QUESTION_STATS_F:format(6, 0, 4, 2),
        "zero correct answers do not erase wrong and unanswered counts"
    )
    Same(newRevision.Rules, nil, "new personal rules revisions create no grey rule block")
    Check(rulesKeyA ~= rulesKeyB, "same authored revision fixture uses genuinely distinct canonical rules keys")
    Same(firstVariant.Title:GetMaxLines(), 1, "long quiz titles stay on one line")
    Same(firstVariant.Title.wordWrap, false, "long quiz titles never wrap into the score column")
    Same(firstVariant.Title.nonSpaceWrap, false, "long unbroken quiz titles never wrap into the score column")
    Same(firstVariant.Score:GetJustifyH(), "RIGHT", "scores remain right aligned")
    Same(firstVariant.Score:GetMaxLines(), 1, "scores stay on one line")
    Check(firstVariant.Title:GetRight() <= firstVariant.Score:GetLeft(), "long quiz titles cannot overlap their score")
    Near(
        firstVariant.Score:GetLeft() - firstVariant.Title:GetRight(),
        SCORE_COLUMN_GAP,
        "quiz title and score retain their reserved gap"
    )

    local personalLines = ScoreView:GetPersonalScoreLines()
    Same(#personalLines, #personalFixture, "text projection also keeps every ruleset separate")
    Same(
        personalLines[1],
        personalFixture[1].title
            .. " · "
            .. L.W_SCORE_POINTS_F:format(9.5)
            .. "\n"
            .. L.W_SCORE_QUESTION_STATS_F:format(5, 1, 2, 2)
            .. "\n"
            .. L.W_SCORE_EARLIER_RULES,
        "earlier text projection uses the same saved title, stats and scoring label"
    )
    Same(
        personalLines[2],
        personalFixture[2].title
            .. " · "
            .. L.W_SCORE_POINTS_F:format(0)
            .. "\n"
            .. L.W_SCORE_QUESTION_STATS_F:format(8, 3, 2, 3)
            .. "\n"
            .. ExpectedRules(rulesA, L.W_SCORE_RULE_VARIATION_F:format(7, 1)),
        "first authored ruleset text is exact"
    )
    Same(
        personalLines[3],
        personalFixture[3].title
            .. " · "
            .. L.W_SCORE_POINTS_F:format(0)
            .. "\n"
            .. L.W_SCORE_QUESTION_STATS_F:format(6, 0, 4, 2)
            .. "\n"
            .. ExpectedRules(rulesB, L.W_SCORE_RULE_VARIATION_F:format(7, 2)),
        "second authored ruleset text is exact rather than a mixed aggregate"
    )

    local renderedRows = ScoreView.rows
    local rowTextCalls, frameCount = {}, #Test.frames
    for index, row in ipairs(renderedRows) do
        rowTextCalls[index] = row.Title.textCalls + row.Score.textCalls + row.Details.textCalls
    end
    local contentSizeCalls = ScoreView.content.sizeCalls
    local verticalScrollCalls = ScoreView.scroll.verticalScrollCalls
    local switchTextCalls = scopeSwitch.textCalls
    local activeCount, inactiveCount = Count(ScoreView.rowPool.active), #ScoreView.rowPool.inactive
    local readsBeforeCachedRefresh = personalReads
    ScoreView:Refresh(currentView)
    Same(ScoreView.rows, renderedRows, "unchanged refresh retains the rendered row list")
    Same(personalReads, readsBeforeCachedRefresh, "unchanged refresh skips a new personal projection")
    Same(#Test.frames, frameCount, "unchanged refresh allocates no frames")
    Same(ScoreView.content.sizeCalls, contentSizeCalls, "unchanged refresh performs no content layout")
    Same(
        ScoreView.scroll.verticalScrollCalls,
        verticalScrollCalls,
        "unchanged refresh does not move the scroll position"
    )
    Same(scopeSwitch.textCalls, switchTextCalls, "unchanged refresh does not churn the scope label")
    Same(Count(ScoreView.rowPool.active), activeCount, "unchanged refresh keeps the same active pool size")
    Same(#ScoreView.rowPool.inactive, inactiveCount, "unchanged refresh keeps the same inactive pool size")
    for index, row in ipairs(renderedRows) do
        Same(
            row.Title.textCalls + row.Score.textCalls + row.Details.textCalls,
            rowTextCalls[index],
            "unchanged refresh does not rewrite row text " .. index
        )
    end

    ScoreView.scroll:SetVerticalScroll(80)
    local gameEntry = FindScope("game")
    Check(gameEntry:Pick(), "native scope selection accepts Current game")
    Same(ScoreView.scope, "game", "scope switch selects Current game")
    Same(scopeSwitch:GetText(), L.W_SCORE_SCOPE_GAME, "scope label follows current-game terminology")
    Same(ScoreView.scroll:GetVerticalScroll(), 0, "selecting Current game resets scroll immediately")
    Check(not scopeSwitch:IsMenuOpen(), "selecting Current game closes the native menu")

    ScoreView.scroll:SetVerticalScroll(80)
    Refresh("archive", currentView)
    Same(ScoreView.scroll:GetVerticalScroll(), 0, "switching score scopes resets scroll immediately")
    Same(FindScope("archive"), nil, "internal archive rendering never adds its scope back to the menu")
    ScoreView:CloseMenu()
    Same(#ScoreView.rows, ARCHIVE_PLAYER_COUNT + 1, "archived standings are not truncated to twenty players")
    Same(ScoreView.rows[1].kind, "heading", "archive begins with a league heading")
    Same(
        ScoreView.rows[1].Title:GetText(),
        L.W_SCORE_LEAGUE_F:format("Many Players"),
        "archive heading names its league"
    )
    Same(ScoreView.rows[1].record, nil, "archive headings never retain a personal record")
    Same(ScoreView.rows[1].player, nil, "archive headings never retain a standing player")
    Check(not ScoreView.rows[1].Score:IsShown(), "archive headings have no stale score")
    Check(not ScoreView.rows[1].Details:IsShown(), "archive headings have no stale details")
    Same(ScoreView.rows[1].Rules, nil, "archive headings have no rules label")
    Same(
        ScoreView.rows[2].Score:GetText(),
        L.W_SCORE_POINTS_F:format(1.3),
        "archived current-scale totals use decimals"
    )
    Same(
        ScoreView.rows[#ScoreView.rows].Title:GetText(),
        L.W_SCORE_RANK_F:format(ARCHIVE_PLAYER_COUNT, archiveStandings[ARCHIVE_PLAYER_COUNT].name),
        "the twenty-fifth archived player renders with its long saved name"
    )
    Check(
        ScoreView.rows[#ScoreView.rows].Title:GetRight() <= ScoreView.rows[#ScoreView.rows].Score:GetLeft(),
        "long archived player names cannot overlap the score column"
    )
    Same(archiveReads, 1, "archive scope performs one public-standing read")
    local archiveFrames, pooledFrameCount = { unpack(ScoreView.rows) }, #Test.frames
    local archiveLines = ScoreView:GetArchiveLines("archive")
    Same(#archiveLines, ARCHIVE_PLAYER_COUNT + 1, "archive text projection has no twenty-row cap")
    Same(
        archiveLines[2],
        L.W_SCORE_RANKED_LINE_F:format(1, archiveStandings[1].name, L.W_SCORE_POINTS_F:format(1.3), 1, 2),
        "archive text uses decimal totals and current terminology"
    )
    Same(
        archiveLines[#archiveLines],
        L.W_SCORE_RANKED_LINE_F:format(
            ARCHIVE_PLAYER_COUNT,
            archiveStandings[ARCHIVE_PLAYER_COUNT].name,
            L.W_SCORE_POINTS_F:format(ARCHIVE_PLAYER_COUNT + 0.3),
            ARCHIVE_PLAYER_COUNT,
            2
        ),
        "archive text includes every saved player"
    )

    Refresh("legacy", currentView)
    Same(#ScoreView.rows, ARCHIVE_PLAYER_COUNT + 1, "legacy archive also keeps more than twenty standings")
    Same(ScoreView.rows[2].kind, "legacy", "legacy rows remain explicitly typed")
    Same(
        ScoreView.rows[2].Score:GetText(),
        L.W_SCORE_LEGACY_POINTS_F:format(100),
        "legacy totals use integer formatting"
    )
    Same(legacyReads, 1, "legacy scope performs one legacy-standing read")
    local legacyLines = ScoreView:GetArchiveLines("legacy")
    Same(#legacyLines, ARCHIVE_PLAYER_COUNT + 1, "legacy text projection has no twenty-row cap")
    Same(
        legacyLines[2],
        L.W_SCORE_RANKED_LINE_F:format(1, legacyStandings[1].name, L.W_SCORE_LEGACY_POINTS_F:format(100), 2, 3),
        "legacy text projection preserves integer points"
    )

    local gamePlayers = {
        negative = {
            name = string.rep("A very long current-game player name ", 6),
            score = 0,
            answers = 4,
            correct = 0,
            incorrect = 4,
        },
        positive = { name = "Positive", score = 7.2, answers = 3, correct = 2, incorrect = 1 },
        zeroOne = { name = "Zero one", score = 0, answers = 4, correct = 1, incorrect = 3 },
        zeroTwo = { name = "Zero two", score = 0, answers = 5, correct = 2, incorrect = 3 },
    }
    local gamePlayersSnapshot = Copy(gamePlayers)
    local hostStandings = Quiz.Scoring.BuildStandings(gamePlayers)
    local hostStandingsSnapshot = Copy(hostStandings)
    local hostGame = { completed = 41 }
    function hostGame:GetStandings()
        return hostStandings
    end
    Quiz.Controller.game = hostGame
    local hostView = { session = "host-session", role = "host", state = "question" }
    Refresh("game", hostView)
    Same(#ScoreView.rows, #hostStandings, "host sees every current-game standing")
    for index, expected in ipairs(hostStandings) do
        local row = ScoreView.rows[index]
        Same(row.kind, "standing", "host rows are current-game standings " .. index)
        Same(row.player, expected, "host preserves authoritative standing order " .. index)
        Same(
            row.Title:GetText(),
            L.W_SCORE_RANK_F:format(index, expected.name),
            "host rank and name are exact " .. index
        )
        Same(row.Score:GetText(), L.W_SCORE_POINTS_F:format(expected.score), "host score is exact " .. index)
    end
    Same(hostStandings[1].name, "Positive", "positive current-game total ranks first")
    Same(hostStandings[2].name, "Zero two", "zero totals retain authoritative correct-answer tie breaking")
    Same(hostStandings[3].name, "Zero one", "second zero total follows the authoritative ordering")
    Same(hostStandings[4].score, 0, "penalty-only current-game total remains at zero")
    Check(
        ScoreView.rows[4].Title:GetRight() <= ScoreView.rows[4].Score:GetLeft(),
        "long current-game names cannot overlap the score column"
    )
    hostView.rules, hostView.rulesKey, hostView.packTitle = rulesB, rulesKeyB, "Authored scoring quiz"
    Refresh("game", hostView)
    Same(#ScoreView.rows, #hostStandings + 1, "host scoring summary precedes the standings")
    Same(ScoreView.rows[1].kind, "summary", "current authored rules have a summary row")
    Same(
        ScoreView.rows[1].Title:GetText(),
        L.W_SCORE_CURRENT_RULES_F:format("Authored scoring quiz"),
        "current rules summary retains the authored quiz title"
    )
    Same(ScoreView.rows[1].Rules, nil, "current-game summary has no grey scoring-rule label")
    Same(ScoreView.rows[1].record, nil, "current rules summary has no stale personal record")
    Same(ScoreView.rows[1].player, nil, "current rules summary has no stale standing player")

    hostGame.GetStandings = function()
        error("participants must not read host-only standings")
    end
    local participantView = { session = "participant-session", role = "participant", state = "question" }
    Refresh("game", participantView)
    Same(#ScoreView.rows, 1, "participant without a total sees only their waiting row")
    Same(ScoreView.rows[1].kind, "message", "missing participant total is an explicit message")
    Same(ScoreView.rows[1].Title:GetText(), L.W_SCORE_WAITING_TOTAL, "missing participant total has distinct guidance")
    Check(not ScoreView.empty:IsShown(), "participant waiting message is rendered as a row")
    participantView.score = 0
    Refresh("game", participantView)
    Same(#ScoreView.rows, 1, "zero-score participant sees only their own total")
    Same(ScoreView.rows[1].kind, "participant", "participant total has its own row type")
    Same(
        ScoreView.rows[1].Score:GetText(),
        L.W_SCORE_POINTS_F:format(0),
        "participant zero is not mistaken for missing"
    )
    Same(ScoreView.rows[1].player, nil, "participant row never leaks host standings")
    Same(ScoreView.rows[1].record, nil, "participant row never retains personal history")
    Same(ScoreView.rows[1].Details:GetText(), L.W_SCORE_PARTICIPANT_DETAIL, "participant total explains host ownership")
    participantView.score = 1.5
    Refresh("game", participantView)
    Same(#ScoreView.rows, 1, "positive-score participant still sees only their own total")
    Same(ScoreView.rows[1].Score:GetText(), L.W_SCORE_POINTS_F:format(1.5), "participant positive total remains exact")
    Check(Contains(archiveFrames, ScoreView.rows[1]), "participant rendering reuses a frame released by the archive")
    Same(#Test.frames, pooledFrameCount, "smaller score scopes allocate no frames after the archive fills the pool")
    Check(#ScoreView.rowPool.inactive >= ARCHIVE_PLAYER_COUNT, "large archives leave reusable rows inactive")
    for index, row in ipairs(ScoreView.rowPool.inactive) do
        Same(row.kind, nil, "released row clears kind " .. index)
        Same(row.record, nil, "released row clears personal record " .. index)
        Same(row.player, nil, "released row clears standing player " .. index)
        Same(row.Title:GetText(), "", "released row clears title " .. index)
        Same(row.Score:GetText(), "", "released row clears score " .. index)
        Same(row.Details:GetText(), "", "released row clears details " .. index)
        Same(row.Rules, nil, "released rows own no rules label " .. index)
        Check(not row:IsShown(), "released row is hidden " .. index)
    end

    hostGame.GetStandings = function()
        return hostStandings
    end
    hostGame.rules, hostGame.rulesKey = rulesB, rulesKeyB
    hostGame.lastResult = { packTitle = "Authored scoring quiz" }
    hostGame.completed = 42
    Quiz.Controller.game = hostGame
    Refresh("game", { role = "idle", state = "stopped" })
    Same(
        #ScoreView.rows,
        #hostStandings + 1,
        "the most recent hosted game's final rules and standings remain available"
    )
    Same(ScoreView.rows[1].kind, "summary", "an ended hosted game retains its rules summary")
    Same(
        ScoreView.rows[1].Title:GetText(),
        L.W_SCORE_CURRENT_RULES_F:format("Authored scoring quiz"),
        "an ended hosted game retains its last scored pack title"
    )
    Same(ScoreView.rows[2].player, hostStandings[1], "an ended hosted game retains authoritative rank order")
    Check(not ScoreView.empty:IsShown(), "an ended hosted game does not fall back to the no-game message")

    local emptyGame = { completed = 42 }
    function emptyGame:GetStandings()
        return {}
    end
    Quiz.Controller.game = emptyGame
    Refresh("game", { session = "empty-host", role = "host", state = "question" })
    Same(#ScoreView.rows, 1, "host without answers receives one explicit current-game message")
    Same(ScoreView.rows[1].Title:GetText(), L.W_SCORE_NO_GAME_RESULTS, "host empty result message is distinct")
    Check(not ScoreView.empty:IsShown(), "host result message is rendered as a row")

    Quiz.Controller.game = nil
    Refresh("game", { state = "idle" })
    Same(#ScoreView.rows, 0, "idle current-game scope has no invented rows")
    Check(ScoreView.empty:IsShown(), "idle current-game scope shows an empty state")
    Same(ScoreView.empty:GetText(), L.W_SCORE_NO_GAME, "idle current-game empty state is distinct")

    personalRows = {}
    Refresh("personal", currentView)
    Same(#ScoreView.rows, 0, "empty personal history has no rows")
    Check(ScoreView.empty:IsShown(), "empty personal history shows its empty state")
    Same(ScoreView.empty:GetText(), L.W_SCORE_NO_HISTORY, "personal history has its own empty message")

    archivedLeagues = {}
    Refresh("archive", currentView)
    Same(#ScoreView.rows, 0, "empty archive has no rows")
    Same(ScoreView.empty:GetText(), L.W_SCORE_NO_ARCHIVE, "current-scale archive has its own empty message")
    Refresh("legacy", currentView)
    Same(#ScoreView.rows, 0, "empty legacy archive has no rows")
    Same(ScoreView.empty:GetText(), L.W_SCORE_NO_LEGACY, "100-point archive has its own empty message")

    SameTable(personalFixture, personalSnapshot, "ScoreView never mutates canonical personal rows or authored rules")
    SameTable(archiveStandings, archiveSnapshot, "ScoreView never mutates archived current-scale standings")
    SameTable(legacyStandings, legacySnapshot, "ScoreView never mutates archived 100-point standings")
    SameTable(gamePlayers, gamePlayersSnapshot, "ScoreView never mutates host player state")
    SameTable(hostStandings, hostStandingsSnapshot, "ScoreView never mutates authoritative host standings")

    PersonalScores.GetScoreRows = original.getScoreRows
    PersonalScores.GetPack, PersonalScores.GetPacks = original.getPack, original.getPacks
    Quiz.GetPacks, Quiz.GetRules, Quiz.GetQuestions =
        original.getQuestionPacks, original.getPackRules, original.getQuestions
    Store.GetArchivedLeagues = original.getArchivedLeagues
    Store.GetStandings, Store.GetLegacyStandings = original.getStandings, original.getLegacyStandings
    Session.GetView, Quiz.Controller.game = original.getView, original.game
    UI.frame:Hide()
    return assertions
end

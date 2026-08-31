return function(Quiz)
    local assertions = 0
    local Personal, Store = Quiz.PersonalScores, Quiz.Store
    local defaultRules = Quiz.Rules.Normalize()
    local defaultRulesKey = Quiz.Rules.Encode(defaultRules)
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
    local function Copy(value)
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, child in pairs(value) do
            copy[key] = Copy(child)
        end
        return copy
    end
    local function SameTable(actual, expected, message)
        Check(type(actual) == "table", message .. " is a table")
        for key, value in pairs(expected) do
            local field = message .. "." .. tostring(key)
            if type(value) == "table" then
                SameTable(actual[key], value, field)
            else
                Same(actual[key], value, field)
            end
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " has no extra " .. tostring(key))
        end
    end
    local function Receipt(id, overrides)
        local receipt = {
            host = "Quizhost-TestRealm",
            session = "1234.1",
            roundId = id,
            packId = "warcraft-lore",
            packTitle = "Warcraft Lore",
            packVersion = 1,
            scoringVersion = 3,
            duration = 15,
            rulesKey = defaultRulesKey,
            choiceCount = 4,
            selected = 1,
            correctIndex = 1,
            elapsed = 1,
        }
        for key, value in pairs(overrides or {}) do
            receipt[key] = value
        end
        local correct = receipt.selected == receipt.correctIndex
        if receipt.scoringVersion == 2 then
            receipt.rulesKey, receipt.streak, receipt.streakBonus = nil, nil, nil
            receipt.points = Quiz.Scoring.CalculateLegacy(correct, receipt.elapsed, receipt.duration)
        else
            local rules = Quiz.Rules.Decode(receipt.rulesKey)
            receipt.streak = receipt.streak == nil and (correct and 1 or 0) or receipt.streak
            receipt.streakBonus = Quiz.Scoring.StreakBonus(rules, receipt.streak)
            receipt.points = Quiz.Scoring.Calculate(correct, receipt.elapsed, receipt.duration, rules, receipt.streak)
        end
        return receipt
    end
    local function Recorded(receipt, expected)
        local saved, reason = Personal:RecordResult(receipt)
        Check(saved, tostring(reason))
        Same(reason, expected or "recorded", "receipt outcome")
    end
    local function NewStore(saved)
        local db, reason = Store:Initialize(saved)
        Check(db ~= nil, tostring(reason))
        Same(db.schemaVersion, 6, "schema upgrades to per-pack personal scores")
        Same(Personal.data, db.personalScores, "personal owner binds to the committed database")
        return db
    end
    local function RejectReceipt(receipt, reason)
        local before, revision = Copy(Store.db), Personal.revision
        local valid, errorCode = Personal:RecordResult(receipt)
        Same(valid, false, "invalid receipt rejected")
        Same(errorCode, reason or "invalid_personal_result", "invalid receipt has explicit reason")
        SameTable(Store.db, before, "rejected receipt preserves data")
        Same(Personal.revision, revision, "rejected receipt does not invalidate the UI")
    end
    local function RejectDatabase(saved, reason)
        local before, prior, priorData, revision = Copy(saved), Store.db, Personal.data, Personal.revision
        local db, errorCode = Store:Initialize(saved)
        Same(db, nil, "invalid database rejected")
        Same(errorCode, reason or "invalid_personal_scores", "invalid database has explicit reason")
        Same(Store.db, prior, "failed migration keeps prior live database")
        Same(Personal.data, priorData, "failed migration keeps prior personal binding")
        Same(Personal.revision, revision, "failed migration does not invalidate scores")
        SameTable(saved, before, "invalid original saved data is untouched")
    end

    local db = NewStore(nil)
    Same(#Personal:GetPacks(), 0, "new accounts have no invented personal totals")
    Same(Personal:GetPack("warcraft-lore"), nil, "absent pack has no stats")
    Same(Personal:GetPack("all"), nil, "all is not a score-owning pack")
    Same(db.personalScores.schemaVersion, 2, "personal subtree identifies pack-owned scoring rules")
    local revision = Personal.revision
    Recorded(Receipt(1))
    Same(Personal.revision, revision + 1, "new receipt invalidates score consumers")
    local pack = Personal:GetPack("warcraft-lore")
    Same(pack.id, "warcraft-lore", "stable pack identifier owns stats")
    Same(pack.score, 2.4, "correct answer records timing reward")
    Same(pack.correct, 1, "correct count")
    Same(pack.incorrect, 0, "incorrect count")
    Same(pack.answers, 1, "answered count")
    Same(pack.unanswered, 0, "unanswered count")
    Same(pack.rounds, 1, "round count")
    Same(pack.scoringVersions[3].score, 2.4, "scoring version is not silently omitted")
    Same(pack.rulesets[defaultRulesKey].score, 2.4, "canonical rules own comparable score totals")
    Same(pack.versions[1], 1, "pack version records encountered rounds")
    Same(db.personalScores.recent[1].host, "quizhost-testrealm", "native identity case is normalized")

    Recorded(Receipt(2, { selected = 2 }))
    Same(Personal:GetPack("warcraft-lore").score, 1.5, "penalty retains exact signed tenths")
    local unanswered = Receipt(3)
    unanswered.selected, unanswered.elapsed, unanswered.points = nil, nil, nil
    unanswered.streak, unanswered.streakBonus = 0, 0
    Recorded(unanswered)
    pack = Personal:GetPack("warcraft-lore")
    Same(pack.score, 1.5, "unanswered questions never lose points")
    Same(pack.answers, 2, "unanswered questions are not recorded as answers")
    Same(pack.unanswered, 1, "unanswered result is remembered for idempotence")
    Same(pack.rounds, 3, "seen rounds include no-answer results")
    Same(db.personalScores.recent[3].points, 0, "no-answer canonical receipt has zero points")
    Recorded(Receipt(1, { host = "Anotherhost-TestRealm" }))
    Same(Personal:GetPack("warcraft-lore").score, 3.9, "same pack follows the player across hosts")
    Recorded(Receipt(4, {
        packId = "warcraft-rts",
        packTitle = "Azeroth's First Wars",
        choiceCount = 6,
        selected = 6,
        correctIndex = 6,
    }))
    Same(Personal:GetPack("warcraft-rts").score, 2.4, "different pack owns separate totals")
    Same(Personal:GetPack("warcraft-lore").score, 3.9, "another pack does not affect earlier progress")
    Same(db.personalScores.recent[5].choiceCount, 6, "receipt retains six-choice metadata")
    Same(db.personalScores.recent[5].selected, 6, "last choice survives persistence")
    Recorded(Receipt(5, { packVersion = 2, packTitle = "Expanded Warcraft Lore" }))
    Recorded(Receipt(6, { packVersion = 1, packTitle = "Old Warcraft Lore" }))
    pack = Personal:GetPack("warcraft-lore")
    Same(pack.score, 8.7, "same stable ID retains totals across pack updates")
    Same(pack.version, 2, "displayed version is highest encountered")
    Same(pack.title, "Expanded Warcraft Lore", "an older host pack does not roll back its display metadata")
    Same(pack.versions[1], 5, "older pack version remains counted")
    Same(pack.versions[2], 1, "new pack version is tracked separately")
    Same(pack.scoringVersions[3].answers, 5, "pack versions share the same explicitly tagged scoring rules")
    Same(Personal:GetPacks()[1].id, "warcraft-rts", "personal packs sort by display title")

    pack.score, pack.versions[1], pack.scoringVersions[3].score, pack.rulesets[defaultRulesKey].score =
        1000, 1000, 1000, 1000
    local summaries = Personal:GetPacks()
    summaries[1].score, summaries[1].scoringVersions[3].correct = 1000, 1000
    Same(Personal:GetPack("warcraft-lore").score, 8.7, "summary copies cannot mutate canonical scores")
    Same(Personal:GetPack("warcraft-lore").versions[1], 5, "version copies do not alias saved metadata")
    Same(Personal:GetPack("warcraft-rts").correct, 1, "nested stats copies do not alias saved metadata")

    revision = Personal.revision
    local beforeDuplicate = Copy(db)
    Recorded(Receipt(1, { host = "QUIZHOST-TESTREALM" }), "duplicate")
    Same(Personal.revision, revision, "duplicate acknowledgements do not invalidate scores")
    SameTable(db, beforeDuplicate, "duplicate replay is a complete no-op")
    local conflict = Receipt(1, { packId = "changed-pack", packTitle = "Different pack" })
    RejectReceipt(conflict, "conflicting_personal_result")
    conflict = Receipt(2, { selected = 1 })
    RejectReceipt(conflict, "conflicting_personal_result")

    local saved = Copy(db)
    local savedBefore = Copy(saved)
    db = NewStore(saved)
    SameTable(saved, savedBefore, "successful normalization does not mutate its input")
    Check(db.personalScores ~= saved.personalScores, "reloaded personal root is detached")
    Check(db.personalScores.packs ~= saved.personalScores.packs, "reloaded packs are detached")
    Check(db.personalScores.recent[1] ~= saved.personalScores.recent[1], "reloaded recent receipts are detached")
    Recorded(Receipt(1), "duplicate")
    Recorded(unanswered, "duplicate")
    Same(Personal:GetPack("warcraft-lore").score, 8.7, "saved reload does not reaward prior answers")
    Recorded(Receipt(1, { session = "new-session" }))
    Same(Personal:GetPack("warcraft-lore").score, 11.1, "new host session is a distinct receipt namespace")
    Recorded(
        Receipt(
            1,
            { host = "호스트-아즈샤라", session = "localized-host", packTitle = "워크래프트 전승" }
        )
    )
    Same(Personal:GetPack("warcraft-lore").score, 13.5, "normalized non-ASCII native host identities work")

    db = NewStore(nil)
    local originalGuid, originalName = Quiz.Identity.guid, Quiz.Identity.name
    Quiz.Identity.guid, Quiz.Identity.name = "Player-1-FirstAlt", "Firstalt-TestRealm"
    Recorded(Receipt(1))
    Quiz.Identity.guid, Quiz.Identity.name = "Player-1-SecondAlt", "Secondalt-TestRealm"
    NewStore(Copy(db))
    Recorded(Receipt(2))
    Same(Personal:GetPack("warcraft-lore").answers, 2, "local characters share account-wide personal pack progress")
    Quiz.Identity.guid, Quiz.Identity.name = originalGuid, originalName

    db = NewStore(nil)
    for _, id in ipairs({ 10, 8, 9, 1, 3, 2, 4, 7, 6, 5 }) do
        Recorded(Receipt(id))
    end
    local ranges = db.personalScores.receipts["quizhost-testrealm"]["1234.1"]
    Same(#ranges, 1, "reordered adjacent receipts compress into one interval")
    Same(ranges[1].first, 1, "compressed first round")
    Same(ranges[1].last, 10, "compressed last round")
    Same(Personal:GetPack("warcraft-lore").score, 24, "older delayed valid receipts are still credited")
    for id = 11, 10010 do
        Recorded(Receipt(id))
    end
    Same(#ranges, 1, "endless contiguous rounds never grow receipt identity storage")
    Same(#db.personalScores.recent, Personal.MAX_RECENT_RESULTS, "diagnostic recent receipts remain bounded")
    Same(
        db.personalScores.recent[1].roundId,
        10010 - Personal.MAX_RECENT_RESULTS + 1,
        "only bounded recent payloads remain"
    )
    Same(Personal:GetPack("warcraft-lore").score, 24024, "long running scores do not accumulate fractional drift")
    db = NewStore(Copy(db))
    local oldReplay = Receipt(1, { packId = "another-pack", packTitle = "An old conflicting replay" })
    Recorded(oldReplay, "duplicate")
    Same(Personal:GetPack("another-pack"), nil, "evicted audit payloads cannot be reawarded under another pack")
    Same(db.personalScores.rounds, 10010, "durable ranges survive far beyond the recent receipt window")

    local validSaved = Copy(db)
    local mutations = {
        function(value)
            value.personalScores.rounds = value.personalScores.rounds + 1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].rulesets[defaultRulesKey].answers = 1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].rulesets[defaultRulesKey].score = 0
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].rulesets[defaultRulesKey].score = math.huge
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].rulesets[defaultRulesKey].incorrect = -1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].versions[1] = 1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].version = 2
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].scoringVersions[3] =
                value.personalScores.packs["warcraft-lore"].rulesets[defaultRulesKey]
        end,
        function(value)
            value.personalScores.receipts["quizhost-testrealm"]["1234.1"][1].last = 10009
        end,
        function(value)
            value.personalScores.receipts["quizhost-testrealm"]["1234.1"][1].first = 0
        end,
        function(value)
            value.personalScores.receipts["quizhost-testrealm"]["1234.1"][2] = { first = 10, last = 20 }
        end,
        function(value)
            value.personalScores.recent[1].roundId = 20000
        end,
        function(value)
            value.personalScores.recent[1].points = 0
        end,
        function(value)
            value.personalScores.recent[1].selected = 5
        end,
        function(value)
            value.personalScores.recent[1].packId = "other-pack"
        end,
        function(value)
            value.personalScores.recent[1].packVersion = 2
        end,
        function(value)
            value.personalScores.recent[1].scoringVersion = 1
        end,
        function(value)
            value.personalScores.recent[1].unknownFutureData = true
        end,
        function(value)
            value.personalScores.recent[2] = Copy(value.personalScores.recent[1])
        end,
        function(value)
            table.remove(value.personalScores.recent, 1)
        end,
        function(value)
            value.personalScores.recent["injected"] = {}
        end,
        function(value)
            value.personalScores.packs["all"] = value.personalScores.packs["warcraft-lore"]
        end,
        function(value)
            value.personalScores.schemaVersion = 3
        end,
        function(value)
            value.personalScores.unknownFutureData = true
        end,
    }
    for _, mutate in ipairs(mutations) do
        local invalid = Copy(validSaved)
        mutate(invalid)
        RejectDatabase(invalid)
    end
    local invalidRoot = Copy(validSaved)
    invalidRoot.personalScores = false
    RejectDatabase(invalidRoot)

    db = NewStore(nil)
    Recorded(Receipt(1))
    local shortHistory = Copy(db)
    shortHistory.personalScores.packs["warcraft-lore"].rulesets[defaultRulesKey].score = 2.3
    RejectDatabase(shortHistory)
    local invalidCases = {
        { host = "" },
        { host = "NoRealm" },
        { host = "Bad Host-Realm" },
        { host = "Host-Realm|escape" },
        { session = "" },
        { session = string.rep("x", 65) },
        { session = "unsafe:token" },
        { roundId = 0 },
        { roundId = 1.5 },
        { roundId = math.huge },
        { packId = "all" },
        { packId = "UpperCase" },
        { packId = "has space" },
        { packId = string.rep("x", 49) },
        { packTitle = "" },
        { packTitle = "Title|escape" },
        { packTitle = string.rep("x", 65) },
        { packVersion = 0 },
        { packVersion = 0.5 },
        { packVersion = 2147483648 },
        { scoringVersion = 1 },
        { scoringVersion = 2 },
        { scoringVersion = 4 },
        { rulesKey = "" },
        { rulesKey = string.rep("1", Quiz.Rules.MAX_KEY_BYTES + 1) },
        { rulesKey = defaultRulesKey .. ":0" },
        { rulesKey = "0" .. defaultRulesKey },
        { streak = -1 },
        { streak = 0 },
        { streak = 1.5 },
        { streak = math.huge },
        { streakBonus = 0.1 },
        { streakBonus = -0.1 },
        { duration = 10 },
        { choiceCount = 3 },
        { choiceCount = 7 },
        { selected = 0 },
        { selected = 5 },
        { selected = 1.5 },
        { correctIndex = 0 },
        { correctIndex = 5 },
        { elapsed = -0.1 },
        { elapsed = 15.1 },
        { elapsed = math.huge },
        { points = 2.3 },
        { points = 0 / 0 },
        { points = math.huge },
    }
    for _, fields in ipairs(invalidCases) do
        local invalid = Receipt(2)
        for key, value in pairs(fields) do
            invalid[key] = value
        end
        RejectReceipt(invalid)
    end
    local noTiming = Receipt(2)
    noTiming.elapsed = nil
    RejectReceipt(noTiming)
    local impossibleNoAnswer = Receipt(2)
    impossibleNoAnswer.selected = nil
    RejectReceipt(impossibleNoAnswer)
    impossibleNoAnswer.elapsed = nil
    RejectReceipt(impossibleNoAnswer)
    local noClaimedPoints = Receipt(2, { selected = 2, elapsed = 15 })
    noClaimedPoints.points = nil
    RejectReceipt(noClaimedPoints)
    Recorded(Receipt(2, { selected = 2, elapsed = 15 }))
    Same(Personal:GetPack("warcraft-lore").score, 1.9, "validated final-tick penalty retains half-point cost")
    Recorded(Receipt(3, { selected = 2, elapsed = 0 }))
    Recorded(Receipt(4, { selected = 2, elapsed = 0 }))
    Same(Personal:GetPack("warcraft-lore").score, -0.1, "negative lifetime totals remain negative")
    NewStore(Copy(Store.db))
    Same(Personal:GetPack("warcraft-lore").score, -0.1, "negative lifetime totals survive reload")

    db = NewStore(nil)
    local lastSafeRound = 9007199254740990
    Recorded(Receipt(lastSafeRound))
    Recorded(Receipt(lastSafeRound - 2))
    Recorded(Receipt(lastSafeRound - 1))
    db = NewStore(Copy(db))
    Same(db.personalScores.rounds, 3, "large valid round IDs do not lose precision while counting ranges")
    Recorded(Receipt(lastSafeRound - 2), "duplicate")

    db = NewStore(nil)
    for id = 1, Personal.MAX_RANGES_PER_SESSION do
        Recorded(Receipt(id * 2))
    end
    ranges = db.personalScores.receipts["quizhost-testrealm"]["1234.1"]
    Same(#ranges, Personal.MAX_RANGES_PER_SESSION, "legitimate gaps use bounded compressed ranges")
    local beforeFull = Copy(db)
    local accepted, reason = Personal:RecordResult(Receipt(Personal.MAX_RANGES_PER_SESSION * 2 + 2))
    Same(accepted, false, "full range guard cannot silently evict duplicate protection")
    Same(reason, "personal_history_full", "capacity failure is explicit")
    SameTable(db, beforeFull, "range capacity failure does not partially award stats")
    Recorded(Receipt(3))
    Same(#ranges, Personal.MAX_RANGES_PER_SESSION - 1, "filling a gap still works at the range cap")
    Recorded(Receipt(Personal.MAX_RANGES_PER_SESSION * 2 + 2))
    NewStore(Copy(db))
    Recorded(Receipt(2), "duplicate")

    db = NewStore(nil)
    for index = 1, Personal.MAX_SESSIONS do
        Recorded(Receipt(1, { session = "session-" .. index }))
    end
    Same(Personal.sessionCount, Personal.MAX_SESSIONS, "session namespace count is bounded independently of rounds")
    beforeFull = Copy(db)
    accepted, reason = Personal:RecordResult(Receipt(1, { session = "one-session-too-many" }))
    Same(accepted, false, "full namespace guard does not forget old sessions")
    Same(reason, "personal_history_full", "namespace capacity reports explicit failure")
    SameTable(db, beforeFull, "namespace capacity failure does not partially award stats")
    Recorded(Receipt(2, { session = "session-1" }))
    NewStore(Copy(db))
    Recorded(Receipt(1, { session = "session-1" }), "duplicate")

    for version = 1, 5 do
        local oldScore = version <= 3 and 120 or 2.4
        local archive = {
            schemaVersion = version,
            settings = { league = "Old Game", packId = "warcraft-lore", hostName = "Oldhost-Realm" },
            nextQuestionId = 20,
            leagues = {
                ["Old League"] = {
                    PUBLIC = {
                        lastRoundId = 12,
                        players = {
                            ["Player-1-A"] = {
                                name = "Oldplayer-Realm",
                                score = oldScore,
                                correct = 1,
                                incorrect = 0,
                                answers = 1,
                            },
                        },
                        history = {},
                    },
                },
            },
            widgetPosition = { x = 0.23, y = 0.77 },
            widgetSettings = { scale = 135, font = "Custom Font" },
        }
        local before = Copy(archive)
        db = NewStore(archive)
        SameTable(archive, before, "migration never mutates source schema " .. version)
        Same(db.settings.league, "Old Game", "migration preserves host display settings")
        Same(db.widgetPosition.x, 0.23, "migration preserves saved widget position")
        Same(db.widgetSettings.scale, 135, "migration preserves live scale preference")
        Same(db.widgetSettings.font, "Custom Font", "migration preserves saved font preference")
        Same(db.nextQuestionId, 20, "migration retains session and question identity allocator")
        Same(#Personal:GetPacks(), 0, "legacy mixed-pack totals are never guessed into personal progress")
        local standings = version <= 3 and Store:GetLegacyStandings("Old League", "PUBLIC")
            or Store:GetStandings("Old League", "PUBLIC")
        Same(standings[1].score, oldScore, "historical host totals are retained as archives")
        Same(
            Store:GetArchivedLeagues()[1],
            "Old League",
            "historical leagues are discoverable independently of host setting"
        )
        Recorded(Receipt(30))
        Same(Personal:GetPack("warcraft-lore").score, 2.4, "new personal totals start from new receipts only")
        standings = version <= 3 and Store:GetLegacyStandings("Old League", "PUBLIC")
            or Store:GetStandings("Old League", "PUBLIC")
        Same(standings[1].score, oldScore, "personal awards do not extend historical host boards")
        NewStore(Copy(db))
        Recorded(Receipt(30), "duplicate")
    end
    db = NewStore({
        schemaVersion = 5,
        leagues = { Zebra = {}, Shared = {} },
        legacyLeagues = { Alpha = {}, Shared = {} },
    })
    local leagues = Store:GetArchivedLeagues()
    Same(#leagues, 3, "archive selector unifies old-scale and recent historical leagues")
    Same(leagues[1], "Alpha", "archive names sort")
    Same(leagues[2], "Shared", "shared archive names are deduplicated")
    Same(leagues[3], "Zebra", "archive names sort independently of current host game")
    leagues[1] = "mutated"
    Same(Store:GetArchivedLeagues()[1], "Alpha", "archive name lists are detached")
    RejectDatabase({ schemaVersion = 7 }, "unsupported_database_version")

    local legacyStats = { score = -0.6, correct = 1, incorrect = 3, answers = 4, unanswered = 0, rounds = 4 }
    local historical = {
        schemaVersion = 6,
        settings = { league = "Original game", packId = "warcraft-lore" },
        nextQuestionId = 80,
        leagues = {
            Original = {
                PUBLIC = {
                    lastRoundId = 77,
                    players = {
                        Original = { name = "Original-Realm", score = -0.9, correct = 0, incorrect = 1, answers = 1 },
                    },
                    history = {
                        {
                            id = 77,
                            questionKey = "warcraft-lore:old-question",
                            number = 1,
                            duration = 15,
                            scoringVersion = 2,
                            choiceCount = 4,
                            correctCount = 0,
                            totalAnswers = 1,
                            answers = {
                                {
                                    guid = "Original",
                                    name = "Original-Realm",
                                    choiceIndex = 2,
                                    correct = false,
                                    elapsed = 1,
                                    points = -0.9,
                                },
                            },
                        },
                    },
                },
            },
        },
        personalScores = {
            schemaVersion = 1,
            rounds = 4,
            packs = {
                ["warcraft-lore"] = {
                    title = "Original Warcraft Lore",
                    version = 1,
                    versions = { [1] = 4 },
                    scoringVersions = { [2] = legacyStats },
                },
            },
            receipts = { ["quizhost-testrealm"] = { ["1234.1"] = { { first = 1, last = 4 } } } },
            recent = {},
        },
    }
    for id = 1, 4 do
        historical.personalScores.recent[id] = Receipt(id, {
            host = "quizhost-testrealm",
            scoringVersion = 2,
            selected = id == 1 and 1 or 2,
            elapsed = id == 1 and 1 or 0,
            packTitle = "Original Warcraft Lore",
        })
    end
    local untouchedHistorical = Copy(historical)
    db = NewStore(historical)
    Same(db.personalScores.schemaVersion, 2, "the personal subtree migrates without changing the top-level schema")
    SameTable(historical, untouchedHistorical, "schema-six source remains untouched")
    SameTable(db.leagues, historical.leagues, "v2 host archives never use live pack rules")
    SameTable(
        db.personalScores.recent,
        historical.personalScores.recent,
        "old canonical receipt payloads are unchanged"
    )
    SameTable(
        db.personalScores.packs["warcraft-lore"].scoringVersions[2],
        legacyStats,
        "v2 personal stats remain exact"
    )
    Same(next(db.personalScores.packs["warcraft-lore"].rulesets), nil, "old results are not guessed into new rules")
    Same(Personal:GetPack("warcraft-lore").score, -0.6, "negative historical progress is not floored or reset")
    local scoreRows = Personal:GetScoreRows()
    Same(#scoreRows, 1, "an old pack produces one historical row")
    Same(scoreRows[1].archived, true, "old personal stats have explicit historical identity")
    Same(scoreRows[1].rulesKey, nil, "old stats do not acquire a current rules key")
    Same(scoreRows[1].scoringVersion, 2, "old stats identify their original calculator")
    RejectReceipt(historical.personalScores.recent[1])
    local upgradedReplay = Receipt(1)
    RejectReceipt(upgradedReplay, "conflicting_personal_result")
    Recorded(Receipt(5, { packVersion = 2 }))
    Same(Personal:GetPack("warcraft-lore").score, 1.8, "the compatibility summary retains both eras of progress")
    scoreRows = Personal:GetScoreRows()
    Same(#scoreRows, 2, "historical and new rule scores are never combined for display")
    Same(scoreRows[1].score, -0.6, "historical display row retains the original penalty total")
    Same(scoreRows[2].score, 2.4, "new rule display row contains only comparable points")
    Same(scoreRows[2].archived, false, "new rule rows are distinct from archives")
    Same(scoreRows[2].rulesKey, defaultRulesKey, "new rule row identifies its exact rules")
    Same(scoreRows[2].rules.answerSeconds, 15, "row exposes detached rule metadata for presentation")
    scoreRows[1].score, scoreRows[2].score, scoreRows[2].rules.answerSeconds = 999, 999, 120
    Same(Personal:GetScoreRows()[1].score, -0.6, "mutating old row copies cannot change saved scores")
    Same(Personal:GetScoreRows()[2].rules.answerSeconds, 15, "row rule metadata is detached")
    db = NewStore(Copy(db))
    SameTable(db.personalScores.packs["warcraft-lore"].scoringVersions[2], legacyStats, "later reload keeps old totals")
    Recorded(Receipt(5, { packVersion = 2 }), "duplicate")
    SameTable(db.leagues, historical.leagues, "new personal results leave every archived board unchanged")
    local malformedHistory = Copy(historical)
    malformedHistory.personalScores.recent[1].scoringVersion = 3
    RejectDatabase(malformedHistory)
    malformedHistory = Copy(historical)
    malformedHistory.personalScores.recent[1].points = 2.5
    RejectDatabase(malformedHistory)
    malformedHistory = Copy(historical)
    malformedHistory.personalScores.packs["warcraft-lore"].scoringVersions[2].score = -0.5
    RejectDatabase(malformedHistory)

    db = NewStore(nil)
    local bonusRules = Quiz.Rules.Normalize({
        answerSeconds = 20,
        revealSeconds = 5,
        correctPoints = 2,
        speedBonusPerSecond = 0.2,
        wrongPenaltyStart = 2,
        wrongPenaltyEnd = 0.3,
        wrongPenaltyCurve = 3,
        streakBonusPerCorrect = 0.2,
        streakBonusMax = 0.6,
    })
    local bonusKey = Quiz.Rules.Encode(bonusRules)
    for id, streak in ipairs({ 1, 2, 3, 4, 999 }) do
        Recorded(Receipt(id, { rulesKey = bonusKey, duration = 20, streak = streak }))
    end
    Same(db.personalScores.recent[1].points, 5.8, "pack-owned clock, base and speed replace fixed scoring")
    Same(db.personalScores.recent[1].streakBonus, 0, "first correct answer has no consecutive bonus")
    Same(db.personalScores.recent[2].streakBonus, 0.2, "second consecutive correct answer starts the bonus")
    Same(db.personalScores.recent[3].points, 6.2, "receipt validates base, timing and streak together")
    Same(db.personalScores.recent[4].streakBonus, 0.6, "consecutive bonus reaches the pack-owned cap")
    Same(db.personalScores.recent[5].streakBonus, 0.6, "host-observed long streaks retain the same cap")
    Recorded(Receipt(6, { rulesKey = bonusKey, duration = 20, selected = 2, elapsed = 0 }))
    Recorded(Receipt(7, { rulesKey = bonusKey, duration = 20, selected = 2, elapsed = 20 }))
    local bonusUnanswered = Receipt(8, { rulesKey = bonusKey, duration = 20 })
    bonusUnanswered.selected, bonusUnanswered.elapsed, bonusUnanswered.points = nil, nil, 0
    bonusUnanswered.streak, bonusUnanswered.streakBonus = 0, 0
    Recorded(bonusUnanswered)
    Same(Personal:GetPack("warcraft-lore").rulesets[bonusKey].score, 28.5, "pack penalties and zero nonanswers persist")
    Same(Personal:GetPack("warcraft-lore").rulesets[bonusKey].rounds, 8, "rule bucket tracks all confirmed rounds")
    local alternativeRules = Quiz.Rules.Normalize({
        answerSeconds = 5,
        correctPoints = 0.4,
        speedBonusPerSecond = 0.1,
        wrongPenaltyStart = 0.6,
        wrongPenaltyEnd = 0.1,
        streakBonusPerCorrect = 0.1,
        streakBonusMax = 0.2,
    })
    local alternativeKey = Quiz.Rules.Encode(alternativeRules)
    Recorded(Receipt(9, { rulesKey = alternativeKey, duration = 5, streak = 3 }))
    Same(Personal:GetPack("warcraft-lore").rulesets[alternativeKey].score, 1, "same pack keeps changed rules separate")
    Same(
        Personal:GetPack("warcraft-lore").rulesets[bonusKey].score,
        28.5,
        "incompatible rules never extend an earlier bucket"
    )
    Same(#Personal:GetScoreRows(), 2, "each comparable ruleset receives its own display row")
    Recorded(Receipt(10, { rulesKey = bonusKey, duration = 20, packVersion = 2, packTitle = "Lore Update" }))
    Same(
        Personal:GetPack("warcraft-lore").rulesets[bonusKey].score,
        34.3,
        "content update retains the same rule bucket"
    )
    Same(#Personal:GetScoreRows(), 2, "content version alone never splits comparable points")
    Same(Personal:GetPack("warcraft-lore").versions[2], 1, "content version remains tracked independently")
    Same(Personal:GetPack("warcraft-lore").score, 35.3, "aggregate API remains available without replacing rule rows")
    db = NewStore(Copy(db))
    Recorded(Receipt(9, { rulesKey = alternativeKey, duration = 5, streak = 3 }), "duplicate")
    Recorded(Receipt(12, { rulesKey = bonusKey, duration = 20, streak = 3 }))
    Recorded(Receipt(11, { rulesKey = bonusKey, duration = 20, streak = 2 }))
    Same(
        Personal:GetPack("warcraft-lore").rulesets[bonusKey].score,
        46.5,
        "arrival order never recomputes host streak awards"
    )
    Same(
        #db.personalScores.receipts["quizhost-testrealm"]["1234.1"],
        1,
        "mixed rules retain shared compressed identities"
    )
    local contradictory = Receipt(12, { rulesKey = alternativeKey, duration = 5, streak = 3 })
    RejectReceipt(contradictory, "conflicting_personal_result")
    contradictory = Receipt(13, { rulesKey = bonusKey, duration = 20, streak = 3 })
    contradictory.streakBonus = 0.3
    RejectReceipt(contradictory)
    contradictory = Receipt(13, { rulesKey = bonusKey, duration = 20, streak = 3 })
    contradictory.points = 6.1
    RejectReceipt(contradictory)
    contradictory = Receipt(13, { rulesKey = bonusKey, duration = 20, selected = 2 })
    contradictory.streak = 1
    RejectReceipt(contradictory)
    contradictory = Copy(bonusUnanswered)
    contradictory.roundId, contradictory.streak, contradictory.streakBonus = 13, 2, 0.2
    RejectReceipt(contradictory)
    for _, field in ipairs({ "rulesKey", "streak", "streakBonus" }) do
        contradictory = Receipt(13, { rulesKey = bonusKey, duration = 20 })
        contradictory[field] = nil
        RejectReceipt(contradictory)
    end
    local invalidRuleStats = Copy(db)
    invalidRuleStats.personalScores.packs["warcraft-lore"].rulesets[bonusKey].score = 1000
    RejectDatabase(invalidRuleStats)
    invalidRuleStats = Copy(db)
    invalidRuleStats.personalScores.packs["warcraft-lore"].rulesets[bonusKey].score = 46.4
    RejectDatabase(invalidRuleStats)
    invalidRuleStats = Copy(db)
    invalidRuleStats.personalScores.recent[12].streakBonus = 0.4
    RejectDatabase(invalidRuleStats)
    invalidRuleStats = Copy(db)
    invalidRuleStats.personalScores.packs["warcraft-lore"].rulesets["invalid-rules"] =
        invalidRuleStats.personalScores.packs["warcraft-lore"].rulesets[bonusKey]
    RejectDatabase(invalidRuleStats)

    db = NewStore(nil)
    local maximumRules = Quiz.Rules.Normalize({
        answerSeconds = 120,
        correctPoints = 1000,
        speedBonusPerSecond = 10,
        wrongPenaltyStart = 1000,
        wrongPenaltyEnd = 1000,
        streakBonusPerCorrect = 10,
        streakBonusMax = 100,
    })
    local maximumKey = Quiz.Rules.Encode(maximumRules)
    Recorded(Receipt(1, { rulesKey = maximumKey, duration = 120, elapsed = 0, streak = 11 }))
    Same(Personal:GetScoreRows()[1].score, 2300, "largest supported reward is not clipped to the old 2.5-point bound")
    Recorded(Receipt(2, { rulesKey = maximumKey, duration = 120, elapsed = 120, selected = 2 }))
    Same(Personal:GetScoreRows()[1].score, 1300, "largest configured penalty validates against its own rule bounds")
    NewStore(Copy(db))
    local zeroRules =
        Quiz.Rules.Normalize({ correctPoints = 0, speedBonusPerSecond = 0, wrongPenaltyStart = 0, wrongPenaltyEnd = 0 })
    local zeroKey = Quiz.Rules.Encode(zeroRules)
    Recorded(Receipt(3, { rulesKey = zeroKey }))
    Recorded(Receipt(4, { rulesKey = zeroKey, selected = 2 }))
    Same(Personal:GetPack("warcraft-lore").rulesets[zeroKey].score, 0, "zero-value rules still count actual answers")
    Same(Personal:GetPack("warcraft-lore").rulesets[zeroKey].correct, 1, "zero points do not mean unanswered")
    Same(Personal:GetPack("warcraft-lore").rulesets[zeroKey].incorrect, 1, "zero penalties still retain wrong answers")
    NewStore(Copy(Store.db))

    do
        db = NewStore(Copy(historical))
        Recorded(Receipt(5, { packTitle = "Alpha" }))
        Recorded(Receipt(6, { packTitle = "Alpha", rulesKey = bonusKey, duration = 20 }))
        Recorded(Receipt(7, { packTitle = "Alpha", rulesKey = alternativeKey, duration = 5 }))
        Recorded(Receipt(8, { packId = "sort-b", packTitle = "ALPHA" }))
        Recorded(Receipt(9, { packId = "sort-a", packTitle = "alpha", rulesKey = bonusKey, duration = 20 }))
        Recorded(Receipt(10, { packId = "sort-z", packTitle = "Beta" }))
        local expectedRows = {}
        for index, identity in ipairs({
            { "sort-a", bonusKey },
            { "sort-b", defaultRulesKey },
            { "warcraft-lore", false },
            { "warcraft-lore", defaultRulesKey },
            { "warcraft-lore", bonusKey },
            { "warcraft-lore", alternativeKey },
            { "sort-z", defaultRulesKey },
        }) do
            local summary = Personal:GetPack(identity[1])
            local key = identity[2]
            local row = Copy(key and summary.rulesets[key] or summary.scoringVersions[2])
            row.id, row.title, row.version = summary.id, summary.title, summary.version
            row.scoringVersion, row.archived = key and 3 or 2, not key
            if key then
                row.rulesKey, row.rules = key, Quiz.Rules.Decode(key)
            end
            expectedRows[index] = row
        end
        local savedBeforeRows, totalsBeforeRows, rowRevision = Copy(db), Copy(Personal.packTotals), Personal.revision
        local getPack, getPacks = Personal.GetPack, Personal.GetPacks
        local function RejectCompatibilityProjection()
            error("Score rows must not construct compatibility summaries.")
        end
        Personal.GetPack, Personal.GetPacks = RejectCompatibilityProjection, RejectCompatibilityProjection
        local rows = Personal:GetScoreRows()
        Personal.GetPack, Personal.GetPacks = getPack, getPacks
        SameTable(rows, expectedRows, "direct rows preserve complete contents and title/id/archive/rules ordering")
        rows[3].score, rows[4].score, rows[4].rules.answerSeconds = 999, 999, 120
        rows[1].id, rows[1].title, rows[1].version = "changed", "Changed", 999
        table.remove(rows, 2)
        SameTable(Personal:GetScoreRows(), expectedRows, "every score projection returns detached rows and rules")
        SameTable(db, savedBeforeRows, "score projections and mutated copies do not alter canonical saved data")
        SameTable(Personal.packTotals, totalsBeforeRows, "score projections leave compatibility totals untouched")
        Same(Personal.revision, rowRevision, "reading score rows does not invalidate score consumers")
    end

    NewStore(nil)
    return assertions
end

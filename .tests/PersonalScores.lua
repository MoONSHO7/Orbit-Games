return function(Quiz)
    local assertions = 0
    local Personal, Store = Quiz.PersonalScores, Quiz.Store
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
            scoringVersion = 2,
            duration = 15,
            choiceCount = 4,
            selected = 1,
            correctIndex = 1,
            elapsed = 1,
        }
        for key, value in pairs(overrides or {}) do
            receipt[key] = value
        end
        receipt.points =
            Quiz.Scoring.Calculate(receipt.selected == receipt.correctIndex, receipt.elapsed, receipt.duration)
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
    Same(db.personalScores.schemaVersion, 1, "personal subtree identifies its own contract")
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
    Same(pack.scoringVersions[2].score, 2.4, "rule version is not silently omitted")
    Same(pack.versions[1], 1, "pack version records encountered rounds")
    Same(db.personalScores.recent[1].host, "quizhost-testrealm", "native identity case is normalized")

    Recorded(Receipt(2, { selected = 2 }))
    Same(Personal:GetPack("warcraft-lore").score, 1.5, "penalty retains exact signed tenths")
    local unanswered = Receipt(3)
    unanswered.selected, unanswered.elapsed, unanswered.points = nil, nil, nil
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
    Same(pack.scoringVersions[2].answers, 5, "pack versions share the same explicitly tagged scoring rules")
    Same(Personal:GetPacks()[1].id, "warcraft-rts", "personal packs sort by display title")

    pack.score, pack.versions[1], pack.scoringVersions[2].score = 1000, 1000, 1000
    local summaries = Personal:GetPacks()
    summaries[1].score, summaries[1].scoringVersions[2].correct = 1000, 1000
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
            value.personalScores.packs["warcraft-lore"].scoringVersions[2].answers = 1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].scoringVersions[2].score = 0
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].scoringVersions[2].score = math.huge
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].scoringVersions[2].incorrect = -1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].versions[1] = 1
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].version = 2
        end,
        function(value)
            value.personalScores.packs["warcraft-lore"].scoringVersions[3] =
                value.personalScores.packs["warcraft-lore"].scoringVersions[2]
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
            value.personalScores.schemaVersion = 2
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
    shortHistory.personalScores.packs["warcraft-lore"].scoringVersions[2].score = 2.3
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
        { scoringVersion = 3 },
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
    NewStore(nil)
    return assertions
end

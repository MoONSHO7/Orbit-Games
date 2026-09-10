local PACK_ID = "warcraft-lore"
local PACK_VERSION = 2

return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local questions = Quiz:GetQuestions(PACK_ID)
    Check(type(questions) == "table" and #questions >= 1000, "the comprehensive bundled catalogue is loaded")
    local packs = Quiz:GetPacks()
    Check(#packs == 1 and packs[1].id == PACK_ID, "comic removal does not split or rename the bundled pack")
    Check(packs[1].version == PACK_VERSION, "comic removal updates the content version without changing the pack ID")
    Check(#Quiz:GetPackErrors() == 0, "the bundled catalogue registers without errors")
    Check(Quiz.Lore == nil, "temporary Quiz assembly data is released after registration")
    local authored = {}
    for _, question in ipairs(questions) do
        authored[question.key] = question
    end
    local game = Quiz.Model.New({ continuous = true }, questions, function()
        return 1
    end)
    Check(game ~= nil and game.total == #questions, "continuous play includes every bundled question")
    local previousKey
    for cycle = 1, 2 do
        local seen = {}
        for number = 1, #questions do
            local id = (cycle - 1) * #questions + number
            local now = id * 18
            local round = game:PrepareQuestion(id)
            Check(round ~= nil, "every bundled question prepares")
            Check(round.cycle == cycle and round.number == number, "full-catalogue cycle numbering is stable")
            Check(not seen[round.key], "each question appears exactly once per cycle")
            Check(previousKey ~= round.key, "a cycle boundary cannot immediately repeat its last question")
            seen[round.key] = true
            previousKey = round.key
            local original = authored[round.key]
            Check(original ~= nil, "the shuffled question belongs to the bundle")
            Check(
                round.key == PACK_ID .. ":" .. original.id,
                "retained question keys do not include the content version"
            )
            Check(
                round.packId == PACK_ID and round.packVersion == PACK_VERSION,
                "every shuffled round retains the comic-free content revision"
            )
            Check(#round.choices == #original.choices, "shuffling preserves this question's choice count")
            Check(
                round.choices[round.correctIndex] == original.choices[original.correctIndex],
                "every authored correct answer survives choice remapping"
            )
            Check(round.difficulty == original.difficulty and round.era == original.era, "round metadata is preserved")
            Check(round.source == original.source, "the host retains review provenance")
            Check(game:OpenQuestion(now), "every bundled question opens")
            Check(round.deadline == now + 15, "all difficulties retain the fixed fifteen-second clock")
            local wrong = round.correctIndex == 1 and 2 or 1
            Check(
                game:Submit("Lore-Player", "Reviewer-Realm", id, wrong, now + 1, "first"),
                "first selection is accepted"
            )
            Check(
                round.answers["Lore-Player"].points == -0.9,
                "a one-second wrong answer incurs the exponential penalty"
            )
            Check(
                game:Submit("Lore-Player", "Reviewer-Realm", id, round.correctIndex, now + 5, "changed"),
                "a changed correct selection is accepted"
            )
            Check(
                game:Submit("Lore-Player", "Reviewer-Realm", id, round.correctIndex, now + 7, "changed"),
                "a repeated transport action is accepted idempotently"
            )
            Check(round.answers["Lore-Player"].elapsed == 5, "a retry does not retime the changed selection")
            local result = game:CloseQuestion(now + 15)
            Check(result ~= nil and result.correctCount == 1, "every bundled question can finish correctly")
            Check(
                result.packId == PACK_ID and result.packVersion == PACK_VERSION,
                "finalized results retain the same stable pack ID and revised content version"
            )
            Check(result.answers[1].points == 2, "all authored answers use the same timed score")
            Check(result.choiceCount == #original.choices, "history retains the correct choice count")
            Check(
                game.state == "results" and game.usedIds == nil,
                "continuous play stays bounded across the full catalogue"
            )
        end
        for key in pairs(authored) do
            Check(seen[key], "no authored question is skipped by a full cycle")
        end
    end
    Check(game.players["Lore-Player"].score == #questions * 4, "two complete cycles accumulate decimal scores exactly")
    Check(game:Stop() and game.state == "stopped", "a full-catalogue game stops normally")

    local oldReceipt = {
        host = "previoushost-testrealm",
        session = "original-pack.1",
        roundId = 1,
        packId = PACK_ID,
        packTitle = "Warcraft Lore",
        packVersion = 1,
        scoringVersion = 2,
        duration = 15,
        choiceCount = 4,
        selected = 1,
        correctIndex = 1,
        elapsed = 5,
        points = 2,
    }
    local oldSave = {
        schemaVersion = 6,
        settings = Quiz.Store:GetSettings(),
        personalScores = {
            schemaVersion = 1,
            rounds = 1,
            packs = {
                [PACK_ID] = {
                    title = "Warcraft Lore",
                    version = 1,
                    versions = { [1] = 1 },
                    scoringVersions = {
                        [2] = { score = 2, correct = 1, incorrect = 0, answers = 1, unanswered = 0, rounds = 1 },
                    },
                },
            },
            receipts = { [oldReceipt.host] = { [oldReceipt.session] = { { first = 1, last = 1 } } } },
            recent = { oldReceipt },
        },
    }
    OrbitGamesDB = {
        schemaVersion = 1,
        selectedGameType = Quiz.id,
        minimap = {},
        modes = { quiz = oldSave },
    }
    Games.Main:OnEvent("ADDON_LOADED", Games.addonName)
    Check(
        Games.Main.initialized and Quiz.Store.db ~= oldSave,
        "existing progress reloads alongside the revised catalogue"
    )
    Check(Quiz.Store.db == OrbitGamesDB.modes.quiz, "reloaded progress remains bound to the Quiz mode subtree")
    Check(Quiz.PersonalScores:GetPack(PACK_ID).score == 2, "removing comic questions never recalculates prior points")
    Check(Quiz.PersonalScores:GetPack(PACK_ID).versions[1] == 1, "prior pack-one history remains identified separately")
    Check(Quiz.Store.db.personalScores.schemaVersion == 2, "old personal progress upgrades to rule-aware storage")
    Check(oldSave.personalScores.schemaVersion == 1, "migration leaves the supplied historical personal schema intact")
    local settings = Quiz.Store:GetSettings()
    settings.packId = PACK_ID
    Check(Games.Main:Start(settings), "the comic-free bundle hosts normally with existing pack-one progress")
    local round = Quiz.Controller.game.round
    Check(round.packVersion == PACK_VERSION, "the hosted question advertises the new content version")
    Check(
        Quiz.Controller:GetScore(Games.Identity.guid) == 0,
        "historical personal points do not seed the new hosted game"
    )
    Test.now = round.startedAt + 5
    Check(Quiz.Session:SubmitAnswer(round.correctIndex), "the revised bundle accepts a normal correct widget answer")
    Test.now = round.deadline
    Quiz.Controller:CloseQuestion(Test.now)
    local progress = Quiz.PersonalScores:GetPack(PACK_ID)
    Check(progress.score == 4 and progress.answers == 2, "new game-lore points add to unchanged historical progress")
    Check(progress.version == PACK_VERSION, "personal metadata advances to the highest played content version")
    Check(progress.versions[1] == 1 and progress.versions[2] == 1, "one personal pack retains both content versions")
    Check(#Quiz.PersonalScores:GetPacks() == 1, "content revision does not create a second personal scoreboard")
    Check(
        oldSave.personalScores.packs[PACK_ID].scoringVersions[2].score == 2,
        "loading and continuing leave the original save untouched"
    )
    local scoreRows = Quiz.PersonalScores:GetScoreRows()
    Check(#scoreRows == 2, "new streak rules and original scores have separate display rows within the same pack")
    Check(scoreRows[1].archived and scoreRows[1].score == 2, "the original row retains its frozen historical score")
    Check(
        not scoreRows[2].archived and scoreRows[2].score == 2 and scoreRows[2].rulesKey == Quiz.Controller.game.rulesKey,
        "the current row contains only the new rules' first correct answer"
    )
    local stored, reason = Quiz.PersonalScores:RecordResult(oldReceipt)
    Check(not stored and reason == "invalid_personal_result", "old protocol receipts cannot become new live awards")
    local rewrittenReceipt = {}
    for key, value in pairs(oldReceipt) do
        rewrittenReceipt[key] = value
    end
    rewrittenReceipt.scoringVersion = Quiz.Scoring.VERSION
    rewrittenReceipt.rulesKey = Quiz.Controller.game.rulesKey
    rewrittenReceipt.streak, rewrittenReceipt.streakBonus = 1, 0
    stored, reason = Quiz.PersonalScores:RecordResult(rewrittenReceipt)
    Check(
        not stored and reason == "conflicting_personal_result",
        "retagging an old identity with current rules cannot replay historical points"
    )
    Check(Quiz.PersonalScores:GetPack(PACK_ID).score == 4, "replaying old content never re-awards its historical score")
    Check(Games.Main:Stop(), "comic-free host stops normally after scoring")
    Games.Main:CancelTicker()
    Games.Main:OnEvent("ADDON_LOADED", Games.addonName)
    Check(Quiz.Store.db == OrbitGamesDB.modes.quiz, "mixed content-version progress remains persisted after reload")
    progress = Quiz.PersonalScores:GetPack(PACK_ID)
    Check(
        progress.score == 4 and progress.versions[1] == 1 and progress.versions[2] == 1,
        "reload preserves both versions"
    )
    Check(
        progress.scoringVersions[2].score == 2 and progress.rulesets[rewrittenReceipt.rulesKey].score == 2,
        "reload preserves separate original and current rule buckets without rescoring"
    )
    return assertions
end

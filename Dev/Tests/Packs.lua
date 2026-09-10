return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
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
    local function Question(id)
        return {
            id = id or "first",
            prompt = "Choose the second answer.",
            choices = { "Alpha", "Beta", "Gamma", "Delta" },
            correctIndex = 2,
            explanation = "Beta is the second authored answer.",
            category = "Testing",
        }
    end
    local function Pack(id)
        return { id = id or "test_invalid", title = "Test Pack", questions = { Question() } }
    end
    local function Metadata(id)
        for _, metadata in ipairs(Quiz:GetPacks()) do
            if metadata.id == id then
                return metadata
            end
        end
    end
    local function Reject(pack, message)
        local count = #Quiz:GetPacks()
        local errorsBefore = #Quiz:GetPackErrors()
        local accepted, errorText = Quiz:RegisterPack(pack)
        Same(accepted, false, message)
        Check(type(errorText) == "string" and errorText ~= "", "rejection has an error message")
        Same(#Quiz:GetPacks(), count, "failed registration must not change the registry")
        local errors = Quiz:GetPackErrors()
        Same(#errors, errorsBefore + 1, "failed registration records one error")
        Same(errors[#errors], errorText, "returned error matches retained error")
    end

    local originalCount = #Quiz:GetQuestions("all")
    local bundledRules, bundledKey = Quiz:GetRules("all")
    Check(bundledRules ~= nil, "the sole bundled quiz defines compatible all-pack rules")
    Same(Quiz.Rules.Encode(bundledRules), bundledKey, "all-pack rules expose a canonical immutable identity")
    bundledRules.correctPoints = 999
    Check(Quiz:GetRules("all").correctPoints ~= 999, "all-pack rules are detached registry copies")
    local valid = Pack("test_valid")
    valid.title = " Test Pack "
    valid.author = " Test Author "
    valid.questions[1].prompt = " Choose the second answer. "
    valid.questions[1].choices[1] = " Alpha "
    Check(Quiz:RegisterPack(valid), "ordinary pack registers")
    local metadata = Metadata("test_valid")
    Same(metadata.title, "Test Pack", "title is trimmed")
    Same(metadata.author, "Test Author", "author is trimmed")
    Same(metadata.version, 1, "version defaults to one")
    Same(metadata.locale, "enUS", "locale defaults to English")
    Same(metadata.count, 1, "metadata includes the question count")
    Same(metadata.rules.answerSeconds, 15, "old packs without rules retain the default answer window")
    Same(metadata.rules.streakBonusPerCorrect, 0, "streak bonuses are opt-in for third-party packs")
    Same(metadata.rulesKey, Quiz.Rules.Encode(), "old packs have an explicit default rules identity")
    local questions = Quiz:GetQuestions("test_valid")
    Same(questions[1].key, "test_valid:first", "question has a globally stable key")
    Same(questions[1].packId, "test_valid", "question retains pack ownership")
    Same(questions[1].prompt, "Choose the second answer.", "prompt is trimmed")
    Same(questions[1].choices[1], "Alpha", "choice is trimmed")
    Same(questions[1].rulesKey, metadata.rulesKey, "every question retains its source pack's rule identity")
    metadata.rules.correctPoints = 999
    questions[1].rulesKey = "mutated"
    Same(Metadata("test_valid").rules.correctPoints, 1, "metadata rules are copied, not shared registry state")
    Same(Quiz:GetQuestions("test_valid")[1].rulesKey, Quiz.Rules.Encode(), "question copies cannot rewrite pack rules")

    valid.questions[1].prompt = "Original table mutated"
    valid.questions[1].choices[2] = "Original choice mutated"
    questions[1].prompt = "Returned question mutated"
    questions[1].choices[2] = "Returned choice mutated"
    metadata.title = "Returned metadata mutated"
    local reread = Quiz:GetQuestions("test_valid")
    Same(reread[1].prompt, "Choose the second answer.", "registry owns its own question copy")
    Same(reread[1].choices[2], "Beta", "registry owns its own choices copy")
    Same(Metadata("test_valid").title, "Test Pack", "metadata is copied on every read")
    Reject(Pack("test_valid"), "duplicate pack cannot replace registered data")
    Same(Quiz:GetQuestions("test_valid")[1].choices[2], "Beta", "duplicate rejection preserves original data")

    Reject(nil, "nil is not a pack")
    Reject(false, "boolean is not a pack")
    Reject("pack", "string is not a pack")
    Reject(setmetatable(Pack(), {}), "pack metatables are not supported")
    for _, id in ipairs({ "", "ALL", "all", "bad:id", "bad.id", "bad id", "_first", "-first", string.rep("a", 49) }) do
        Reject(Pack(id), "invalid or reserved pack id")
    end
    for _, title in ipairs({ "", "   ", string.rep("a", 65), "bad|title", "bad{rt1}title", "bad\ntitle" }) do
        local pack = Pack()
        pack.title = title
        Reject(pack, "invalid title")
    end
    for _, version in ipairs({ 0, -1, 1.5, math.huge, 0 / 0, 2147483648, "1", false }) do
        local pack = Pack()
        pack.version = version
        Reject(pack, "invalid version")
    end
    for _, locale in ipairs({ "", "en", "ENUS", "unknown", false, 1 }) do
        local pack = Pack()
        pack.locale = locale
        Reject(pack, "invalid locale")
    end
    local unsupportedAuthor = Pack()
    unsupportedAuthor.author = string.rep("a", 65)
    Reject(unsupportedAuthor, "overlong author")

    local sparse = Pack()
    sparse.questions = { [1] = Question("first"), [3] = Question("third") }
    Reject(sparse, "sparse question arrays are rejected")
    for _, array in ipairs({
        {},
        { false },
        { Question(), label = "extra" },
        { [0] = Question() },
        { [1.5] = Question() },
    }) do
        local pack = Pack()
        pack.questions = array
        Reject(pack, "malformed question array")
    end
    local metatableQuestions = Pack()
    setmetatable(metatableQuestions.questions, {})
    Reject(metatableQuestions, "question arrays must not use metatables")
    local hugePack = Pack()
    for index = 1, 2001 do
        hugePack.questions[index] = Question("q" .. index)
    end
    Reject(hugePack, "question count is bounded")
    local metatableQuestion = Pack()
    setmetatable(metatableQuestion.questions[1], {})
    Reject(metatableQuestion, "questions must not use metatables")
    for _, id in ipairs({ "", "UPPER", "contains:colon", string.rep("a", 49) }) do
        local pack = Pack()
        pack.questions[1].id = id
        Reject(pack, "invalid question id")
    end

    local duplicatedQuestion = Pack("test_repair")
    duplicatedQuestion.questions[2] = Question()
    Reject(duplicatedQuestion, "duplicate question id rejects the entire pack")
    Same(Quiz:GetQuestions("test_repair"), nil, "partial pack is never visible")
    duplicatedQuestion.questions[2].id = "second"
    Check(Quiz:RegisterPack(duplicatedQuestion), "corrected rejected pack can be registered")
    Same(#Quiz:GetQuestions("test_repair"), 2, "all repaired questions register together")

    for _, prompt in ipairs({
        "",
        "   ",
        "bad\0prompt",
        "bad\1prompt",
        "bad\31prompt",
        "bad\127prompt",
        "bad\nprompt",
        "bad\rprompt",
        "bad\tprompt",
        "bad|cffff0000prompt",
        "bad|Hitem:1|hprompt",
        "bad{star}prompt",
        string.rep("a", 161),
        string.rep("é", 81),
    }) do
        local pack = Pack()
        pack.questions[1].prompt = prompt
        Reject(pack, "unsafe, empty, or overlong prompt")
    end
    for _, choices in ipairs({
        { "A", "B", "C" },
        { "A", "B", "C", "D", "E", "F", "G" },
        { [1] = "A", [2] = "B", [4] = "D" },
        { "A", "B", "C", "D", name = "extra" },
        { "A", "A", "C", "D" },
        { "A", " a ", "C", "D" },
        { "A", false, "C", "D" },
        { "A", "", "C", "D" },
        { "A", string.rep("b", 101), "C", "D" },
        { "A", "bad|choice", "C", "D" },
    }) do
        local pack = Pack()
        pack.questions[1].choices = choices
        Reject(pack, "invalid choices")
    end
    local metatableChoices = Pack()
    setmetatable(metatableChoices.questions[1].choices, {})
    Reject(metatableChoices, "choice array must not use metatables")
    for _, correctIndex in ipairs({ 0, 5, 1.5, math.huge, 0 / 0, "2", false }) do
        local pack = Pack()
        pack.questions[1].correctIndex = correctIndex
        Reject(pack, "correct answer must be a valid integer index")
    end
    for _, field in ipairs({ "category", "explanation", "era" }) do
        for _, value in ipairs({ "", false, "bad{rt1}", "bad\ntext", string.rep("a", 161) }) do
            local pack = Pack()
            pack.questions[1][field] = value
            Reject(pack, "optional text is still validated")
        end
    end
    local longCategory = Pack()
    longCategory.questions[1].category = string.rep("a", 65)
    Reject(longCategory, "category is limited to 64 bytes")
    local longEra = Pack()
    longEra.questions[1].era = string.rep("a", 65)
    Reject(longEra, "era is limited to 64 bytes")
    for _, difficulty in ipairs({ "", "Easy", "very hard", "legendary", 1, false, {} }) do
        local pack = Pack()
        pack.questions[1].difficulty = difficulty
        Reject(pack, "difficulty is one of the four exact supported identifiers")
    end
    for _, source in ipairs({
        "",
        false,
        {},
        "http://example.org/source",
        "file:///tmp/source",
        "https://",
        "https://bad host/source",
        "https://example.org/a b",
        "https://example.org/|Hitem",
        "https://example.org/{rt1}",
        "https://example.org/\n",
        "https://example.org/<script>",
        'https://example.org/"quoted"',
        "https://example.org/" .. string.rep("x", 493),
    }) do
        local pack = Pack()
        pack.questions[1].source = source
        Reject(pack, "source is a bounded plain HTTPS reference")
    end

    local boundaryPack = Pack("test_boundaries")
    boundaryPack.title = string.rep("a", 64)
    boundaryPack.author = string.rep("a", 64)
    boundaryPack.version = 2147483647
    boundaryPack.locale = "frFR"
    boundaryPack.questions[1].id = string.rep("a", 48)
    boundaryPack.questions[1].prompt = string.rep("é", 80)
    boundaryPack.questions[1].choices[1] = string.rep("a", 100)
    boundaryPack.questions[1].explanation = string.rep("e", 160)
    boundaryPack.questions[1].category = string.rep("c", 64)
    boundaryPack.questions[1].era = string.rep("e", 64)
    boundaryPack.questions[1].difficulty = "very_hard"
    boundaryPack.questions[1].source = "https://example.org/" .. string.rep("s", 492)
    Check(Quiz:RegisterPack(boundaryPack), "exact byte limits are accepted")
    Same(Metadata("test_boundaries").locale, "frFR", "pack language metadata is preserved")
    local bounded = Quiz:GetQuestions("test_boundaries")[1]
    Same(bounded.era, boundaryPack.questions[1].era, "maximum era bytes survive normalization")
    Same(#bounded.source, 512, "source URL accepts its exact byte limit")
    Same(bounded.difficulty, "very_hard", "very hard metadata survives normalization")
    local optional = Pack("test_optional")
    optional.questions[1].explanation = nil
    optional.questions[1].category = nil
    optional.questions[1].extra = { arbitrary = true }
    Check(Quiz:RegisterPack(optional), "optional text may be omitted")
    Same(Quiz:GetQuestions("test_optional")[1].extra, nil, "unknown fields are not copied")
    for _, field in ipairs({ "difficulty", "era", "source" }) do
        Same(Quiz:GetQuestions("test_optional")[1][field], nil, "old companion packs do not need " .. field)
    end

    local all = Quiz:GetQuestions("all")
    Same(#all, originalCount + 5, "all combines every registered question")
    local seen = {}
    for _, question in ipairs(all) do
        Check(not seen[question.key], "normalized keys are globally unique")
        seen[question.key] = true
        if question.packId == "test_valid" then
            question.choices[2] = "all mutated"
        end
    end
    Same(Quiz:GetQuestions("test_valid")[1].choices[2], "Beta", "combined pool also returns copies")
    local packs = Quiz:GetPacks()
    for index = 2, #packs do
        local previous, current = packs[index - 1], packs[index]
        Check(
            previous.title < current.title or (previous.title == current.title and previous.id < current.id),
            "metadata is title/id sorted"
        )
    end
    for _, packId in ipairs({ "test_missing", false, {}, 5 }) do
        local missing, errorText = Quiz:GetQuestions(packId)
        Same(missing, nil, "unknown pack returns nil")
        Check(type(errorText) == "string" and errorText ~= "", "unknown pack returns error message")
    end
    local missing, missingError = Quiz:GetQuestions()
    Same(missing, nil, "missing pack argument returns nil")
    Check(type(missingError) == "string", "missing argument returns error message")
    local errors = Quiz:GetPackErrors()
    local firstError = errors[1]
    Same(Quiz.HostPage:GetNotice(), firstError, "the Host notice lane exposes the first pack validation error")
    errors[1] = "mutated diagnostic"
    errors[#errors + 1] = "injected diagnostic"
    Same(Quiz:GetPackErrors()[1], firstError, "diagnostics are copied")
    Same(#Quiz:GetPackErrors(), #errors - 1, "external diagnostics cannot be appended to registry")
    for count = 4, 6 do
        for _, difficulty in ipairs({ "easy", "medium", "hard", "very_hard" }) do
            local pack = Pack("choices_" .. count .. "_" .. difficulty)
            local authored = pack.questions[1]
            authored.choices = {}
            for index = 1, count do
                authored.choices[index] = "Choice " .. index
            end
            authored.correctIndex = count
            authored.difficulty, authored.era = difficulty, " Warcraft III "
            authored.source = "https://warcraft.wiki.gg/wiki/Warcraft_III:_Reign_of_Chaos"
            Check(Quiz:RegisterPack(pack), "all supported choice counts and difficulty labels register")
            local registered = Quiz:GetQuestions(pack.id)[1]
            Same(#registered.choices, count, "normalization retains all authored choices")
            Same(registered.correctIndex, count, "the last of four to six choices can be correct")
            Same(registered.difficulty, difficulty, "difficulty is retained on each copied question")
            Same(registered.era, "Warcraft III", "era is trimmed like other display metadata")
            Same(registered.source, authored.source, "source remains available to the host for editorial review")
            registered.choices[count], registered.difficulty, registered.era, registered.source =
                "changed", nil, nil, nil
            local nextRead = Quiz:GetQuestions(pack.id)[1]
            Same(nextRead.choices[count], "Choice " .. count, "sixth-choice copies cannot mutate the registry")
            Same(nextRead.source, authored.source, "source copies cannot mutate the registry")
            Same(nextRead.difficulty, difficulty, "difficulty copies cannot mutate the registry")
            Same(nextRead.era, "Warcraft III", "era copies cannot mutate the registry")
        end
        local invalid = Pack("invalid_count_" .. count)
        for index = 1, count do
            invalid.questions[1].choices[index] = "Choice " .. index
        end
        invalid.questions[1].correctIndex = count + 1
        Reject(invalid, "answer index is bounded by this question's count, not the global maximum")
    end

    local authoredRules = Pack("test_authored_rules")
    authoredRules.rules = {
        answerSeconds = 30,
        revealSeconds = 5,
        allowAnswerChanges = false,
        shuffleQuestions = false,
        shuffleChoices = false,
        repeatQuestions = false,
        questionLimit = 10,
        correctPoints = 2,
        speedBonusPerSecond = 0.2,
        wrongPenaltyStart = 2,
        wrongPenaltyEnd = 1,
        wrongPenaltyCurve = 1.5,
        streakBonusPerCorrect = 0.2,
        streakBonusMax = 1,
    }
    local canonical = Quiz.Rules.Encode(authoredRules.rules)
    Check(Quiz:RegisterPack(authoredRules), "the pack author may supply basic mechanics and a capped streak bonus")
    local packRules, packRulesKey = Quiz:GetRules(authoredRules.id)
    Same(packRulesKey, canonical, "registry returns the author's full normalized rule identity")
    Same(Quiz.Rules.Encode(packRules), canonical, "the copied rule object agrees with its key")
    local authoredMetadata = Metadata(authoredRules.id)
    Same(authoredMetadata.rulesKey, canonical, "pack selectors can inspect read-only rules metadata")
    Same(authoredMetadata.rules.allowAnswerChanges, false, "false rule toggles survive registration")
    Same(Quiz:GetQuestions(authoredRules.id)[1].rulesKey, canonical, "pack question snapshots identify their own rules")
    authoredRules.rules.correctPoints = 999
    authoredMetadata.rules.answerSeconds = 120
    packRules.streakBonusMax = 100
    local untouched, untouchedKey = Quiz:GetRules(authoredRules.id)
    Same(untouched.correctPoints, 2, "later author table mutation never changes registered scoring")
    Same(untouched.answerSeconds, 30, "selector metadata cannot retime the pack")
    Same(untouched.streakBonusMax, 1, "each rule retrieval is detached")
    Same(untouchedKey, canonical, "registry identity cannot drift after outside mutations")
    local allRules, allReason = Quiz:GetRules("all")
    Same(allRules, nil, "different rules cannot be silently merged into one hosted quiz")
    Same(allReason, "incompatible_pack_rules", "mixed all-pack selection has an actionable stable reason")
    Check(#Quiz:GetQuestions("all") > originalCount, "mixed-rule content remains queryable without authorizing a game")
    for _, invalid in ipairs({
        false,
        "rules",
        { unknownSetting = true },
        { answerSeconds = 1 },
        { revealSeconds = 0 },
        { allowAnswerChanges = "false" },
        { wrongPenaltyStart = 0.1, wrongPenaltyEnd = 0.5 },
        { streakBonusPerCorrect = 0.1, streakBonusMax = 0 },
        setmetatable({}, {}),
    }) do
        local invalidPack = Pack("test_invalid_rules")
        invalidPack.rules = invalid
        local before = #Quiz:GetPacks()
        local accepted, message = Quiz:RegisterPack(invalidPack)
        Same(accepted, false, "invalid rules reject the complete question pack")
        Check(message:find("test_invalid_rules", 1, true) ~= nil, "rules errors identify the authored pack")
        Check(message:find("rules:", 1, true) ~= nil, "rules errors identify the invalid pack section")
        Same(#Quiz:GetPacks(), before, "rejected rules do not partially register questions")
        Same(Quiz:GetQuestions("test_invalid_rules"), nil, "invalid pack content remains unavailable")
    end
    local repair = Pack("test_invalid_rules")
    repair.rules = { answerSeconds = 20 }
    Check(Quiz:RegisterPack(repair), "an author can correct and re-register a rejected rules definition")
    for _, invalid in ipairs({ false, "missing_pack", {}, 1 }) do
        local absent, reason = Quiz:GetRules(invalid)
        Same(absent, nil, "unknown pack rules are never guessed from defaults")
        Check(type(reason) == "string" and reason ~= "", "unknown pack rules return context")
    end
    Same(Quiz:GetRules(), nil, "an omitted pack ID is not the implicit default game")
    return assertions
end

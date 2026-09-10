local DEFAULT_KEY = "1:15:3:1:1:1:1:0:10:1:10:5:25:0:0"
local DEFAULTS = {
    version = 1,
    answerSeconds = 15,
    revealSeconds = 3,
    allowAnswerChanges = true,
    shuffleQuestions = true,
    shuffleChoices = true,
    repeatQuestions = true,
    questionLimit = 0,
    correctPoints = 1,
    speedBonusPerSecond = 0.1,
    wrongPenaltyStart = 1,
    wrongPenaltyEnd = 0.5,
    wrongPenaltyCurve = 2.5,
    streakBonusPerCorrect = 0,
    streakBonusMax = 0,
}
local RANGES = {
    { "version", 1, 2147483647, 1 },
    { "answerSeconds", 5, 120, 1 },
    { "revealSeconds", 1, 30, 1 },
    { "questionLimit", 0, 2000, 1 },
    { "correctPoints", 0, 1000, 0.1 },
    { "speedBonusPerSecond", 0, 10, 0.1 },
    { "wrongPenaltyStart", 0, 1000, 0.1 },
    { "wrongPenaltyEnd", 0, 1000, 0.1 },
    { "wrongPenaltyCurve", 0.1, 10, 0.1 },
    { "streakBonusPerCorrect", 0, 10, 0.1 },
    { "streakBonusMax", 0, 100, 0.1 },
}

return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function SameRules(actual, expected, message)
        Check(type(actual) == "table", message .. " is a table")
        for key, value in pairs(expected) do
            Same(actual[key], value, message .. "." .. key)
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " has no extra fields")
        end
    end
    local function Reject(raw, reason)
        local value, actual = Quiz.Rules.Normalize(raw)
        Same(value, nil, "invalid authored rules reject transactionally")
        Same(actual, reason, "rules rejection returns a stable field-specific reason")
        local encoded, encodeReason = Quiz.Rules.Encode(raw)
        Same(encoded, nil, "the wire encoder cannot normalize invalid author rules silently")
        Same(encodeReason, reason, "encoding preserves validation reason")
    end
    local function RejectKey(key)
        local decoded, reason = Quiz.Rules.Decode(key)
        Same(decoded, nil, "noncanonical or invalid rules key rejects")
        Same(reason, "invalid_rules_key", "key rejections have a stable reason")
    end
    local function Paired(field, value)
        local raw = { [field] = value }
        if field == "wrongPenaltyStart" or field == "wrongPenaltyEnd" then
            raw.wrongPenaltyStart, raw.wrongPenaltyEnd = value, value
        elseif field == "streakBonusPerCorrect" then
            raw.streakBonusMax = value == 0 and 0 or 100
        elseif field == "streakBonusMax" then
            raw.streakBonusPerCorrect = value == 0 and 0 or 0.1
        end
        return raw
    end

    Same(Quiz.Rules.VERSION, 1, "first declarative rules schema is version one")
    Check(Quiz.Rules.MAX_KEY_BYTES <= 256, "rules identities are bounded wire/save scalar data")
    SameRules(Quiz.Rules.Normalize(), DEFAULTS, "omitted rules retain legacy-compatible defaults")
    SameRules(Quiz.Rules.Normalize({}), DEFAULTS, "empty rules use the same defaults")
    Same(Quiz.Rules.Encode(), DEFAULT_KEY, "default identity has a permanent canonical encoding")
    SameRules(Quiz.Rules.Decode(DEFAULT_KEY), DEFAULTS, "canonical defaults round-trip every field")
    local authored =
        { answerSeconds = 30, allowAnswerChanges = false, streakBonusPerCorrect = 0.1, streakBonusMax = 0.5 }
    local rules = Quiz.Rules.Normalize(authored)
    Check(rules ~= authored, "author definitions never become shared registry state")
    Same(authored.correctPoints, nil, "normalization never inserts defaults into author tables")
    Same(rules.allowAnswerChanges, false, "false overrides are not replaced by defaults")
    authored.answerSeconds = 120
    Same(rules.answerSeconds, 30, "author mutation cannot retime a normalized quiz")
    local key = Quiz.Rules.Encode(rules)
    local decoded = Quiz.Rules.Decode(key)
    SameRules(decoded, rules, "nondefault rules round-trip all fields")
    decoded.answerSeconds, decoded.correctPoints = 5, 999
    Same(rules.answerSeconds, 30, "decoded output is detached from encoder input")
    Same(Quiz.Rules.Decode(key).correctPoints, 1, "each decoded output is independently owned")
    rules.answerSeconds = 5
    Same(Quiz.Rules.Normalize().answerSeconds, 15, "returned rules cannot alter future default definitions")

    for _, invalid in ipairs({ false, true, "rules", 1, function() end }) do
        Reject(invalid, "invalid_rules")
    end
    local inspected = false
    Reject(
        setmetatable({}, {
            __index = function()
                inspected = true
                error("metatable must never execute during validation")
            end,
        }),
        "invalid_rules"
    )
    Same(inspected, false, "metatables are rejected before any inherited lookup")
    Reject({ answerSecond = 30 }, "unknown_rule")
    Reject({ [1] = "positional" }, "unknown_rule")
    Reject({ [false] = 1 }, "unknown_rule")
    Reject({ rules = DEFAULTS }, "unknown_rule")
    for _, version in ipairs({ 0, 2147483648, 1.5, 1.000000001, "1", false, math.huge, 0 / 0 }) do
        Reject({ version = version }, "invalid_rule_version")
    end
    for _, field in ipairs({ "allowAnswerChanges", "shuffleQuestions", "shuffleChoices", "repeatQuestions" }) do
        for _, value in ipairs({ false, true }) do
            local normalized = Quiz.Rules.Normalize({ [field] = value })
            Same(normalized[field], value, "both exact booleans are supported")
            Same(Quiz.Rules.Decode(Quiz.Rules.Encode(normalized))[field], value, "boolean wire form is lossless")
        end
        for _, value in ipairs({ 0, 1, "true", "false", {}, function() end }) do
            Reject({ [field] = value }, "invalid_rule_" .. field)
        end
    end
    for _, range in ipairs(RANGES) do
        local field, minimum, maximum, step = unpack(range)
        for _, value in ipairs({ minimum, minimum + step, maximum - step, maximum }) do
            local normalized = Quiz.Rules.Normalize(Paired(field, value))
            Check(normalized ~= nil, "inclusive documented bounds accept for " .. field)
            Check(math.abs(normalized[field] - value) < 0.000000001, "normalization preserves valid units")
            local identity = Quiz.Rules.Encode(normalized)
            Check(#identity <= Quiz.Rules.MAX_KEY_BYTES, "bounded rules never exceed their maximum key length")
            SameRules(Quiz.Rules.Decode(identity), normalized, "numeric boundary survives encoding")
        end
        for _, value in ipairs({
            minimum - step,
            maximum + step,
            minimum + step / 2,
            "1",
            false,
            {},
            math.huge,
            -math.huge,
            0 / 0,
        }) do
            local raw = { [field] = value }
            if field == "wrongPenaltyEnd" then
                raw.wrongPenaltyStart = 1000
            elseif field == "streakBonusPerCorrect" then
                raw.streakBonusMax = 100
            elseif field == "streakBonusMax" then
                raw.streakBonusPerCorrect = 0.1
            end
            Reject(raw, "invalid_rule_" .. field)
        end
        if step == 1 then
            Reject({ [field] = minimum + 0.000000001 }, "invalid_rule_" .. field)
        end
    end
    local decimal = Quiz.Rules.Normalize({ correctPoints = 0.1 + 0.2 })
    Same(decimal.correctPoints, 0.3, "harmless binary noise normalizes to integer tenths")
    Reject({ wrongPenaltyStart = 0.4, wrongPenaltyEnd = 0.5 }, "invalid_rule_penalty_order")
    Reject({ streakBonusPerCorrect = 0.1, streakBonusMax = 0 }, "invalid_rule_streak_bonus")
    Reject({ streakBonusPerCorrect = 0, streakBonusMax = 0.5 }, "invalid_rule_streak_bonus")

    RejectKey(nil)
    for _, invalid in ipairs({
        false,
        1,
        {},
        "",
        " ",
        DEFAULT_KEY .. ":0",
        DEFAULT_KEY .. ":",
        ":" .. DEFAULT_KEY,
        DEFAULT_KEY:gsub("^1:", "01:"),
        DEFAULT_KEY:gsub("^1:", "2147483648:"),
        DEFAULT_KEY:gsub("^1:", "1::"),
        DEFAULT_KEY:gsub(":15:", ":15.0:"),
        DEFAULT_KEY:gsub(":15:", ":+15:"),
        DEFAULT_KEY:gsub(":15:", ":-15:"),
        DEFAULT_KEY:gsub(":15:", ":1e1:"),
        DEFAULT_KEY:gsub(":15:", ":121:"),
        DEFAULT_KEY:gsub(":3:1:", ":3:2:"),
        DEFAULT_KEY:gsub(":25:", ":0:"),
        DEFAULT_KEY .. "\n",
        DEFAULT_KEY .. "\0",
        DEFAULT_KEY .. "|r",
        string.rep("1", Quiz.Rules.MAX_KEY_BYTES + 1),
    }) do
        RejectKey(invalid)
    end
    local distinct = { [DEFAULT_KEY] = true }
    for _, field in ipairs({
        "version",
        "answerSeconds",
        "revealSeconds",
        "questionLimit",
        "correctPoints",
        "speedBonusPerSecond",
        "wrongPenaltyStart",
        "wrongPenaltyEnd",
        "wrongPenaltyCurve",
    }) do
        local changed = Quiz.Rules.Normalize()
        changed[field] = changed[field] + (field == "wrongPenaltyEnd" and -0.1 or 1)
        local identity = Quiz.Rules.Encode(changed)
        Check(identity ~= nil and not distinct[identity], "every authored numeric mechanic has a distinct identity")
        distinct[identity] = true
    end
    for _, field in ipairs({ "allowAnswerChanges", "shuffleQuestions", "shuffleChoices", "repeatQuestions" }) do
        local identity = Quiz.Rules.Encode({ [field] = false })
        Check(not distinct[identity], "each toggle is part of the stable rules identity")
        distinct[identity] = true
    end
    local bonusOne = Quiz.Rules.Encode({ streakBonusPerCorrect = 0.1, streakBonusMax = 0.5 })
    local bonusTwo = Quiz.Rules.Encode({ streakBonusPerCorrect = 0.2, streakBonusMax = 0.5 })
    local bonusThree = Quiz.Rules.Encode({ streakBonusPerCorrect = 0.1, streakBonusMax = 0.6 })
    Check(bonusOne ~= bonusTwo and bonusOne ~= bonusThree, "streak rate and cap independently identify the rules")
    return assertions
end

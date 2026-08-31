local _, Quiz = ...

local POINT_SCALE = 10
local UNIT_EPSILON = 0.0000001
local MAX_KEY_BYTES = 128
local MAX_VERSION = 2147483647
local FIELDS = {
    { "version", 1, 1, MAX_VERSION, 1 },
    { "answerSeconds", 15, 5, 120, 1 },
    { "revealSeconds", 3, 1, 30, 1 },
    { "allowAnswerChanges", true },
    { "shuffleQuestions", true },
    { "shuffleChoices", true },
    { "repeatQuestions", true },
    { "questionLimit", 0, 0, 2000, 1 },
    { "correctPoints", 1, 0, 1000, POINT_SCALE },
    { "speedBonusPerSecond", 0.1, 0, 10, POINT_SCALE },
    { "wrongPenaltyStart", 1, 0, 1000, POINT_SCALE },
    { "wrongPenaltyEnd", 0.5, 0, 1000, POINT_SCALE },
    { "wrongPenaltyCurve", 2.5, 0.1, 10, POINT_SCALE },
    { "streakBonusPerCorrect", 0, 0, 10, POINT_SCALE },
    { "streakBonusMax", 0, 0, 100, POINT_SCALE },
}
local KNOWN_FIELDS = {}
for _, field in ipairs(FIELDS) do
    KNOWN_FIELDS[field[1]] = true
end

local Rules = { VERSION = 1, MAX_KEY_BYTES = MAX_KEY_BYTES }
Quiz.Rules = Rules

function Rules.Normalize(raw)
    if raw ~= nil and (type(raw) ~= "table" or getmetatable(raw) ~= nil) then
        return nil, "invalid_rules"
    end
    raw = raw or {}
    for key in pairs(raw) do
        if not KNOWN_FIELDS[key] then
            return nil, "unknown_rule"
        end
    end
    local normalized = {}
    for _, field in ipairs(FIELDS) do
        local key, default, minimum, maximum, scale = unpack(field)
        local value = raw[key]
        if value == nil then
            value = default
        end
        if type(default) == "boolean" then
            if type(value) ~= "boolean" then
                return nil, "invalid_rule_" .. key
            end
        else
            if type(value) ~= "number" or value ~= value or value < minimum or value > maximum then
                return nil, "invalid_rule_" .. key
            end
            local units = math.floor(value * scale + 0.5)
            if scale == 1 and value % 1 ~= 0 or math.abs(value * scale - units) > UNIT_EPSILON then
                return nil, "invalid_rule_" .. key
            end
            value = units / scale
        end
        normalized[key] = value
    end
    if normalized.wrongPenaltyStart < normalized.wrongPenaltyEnd then
        return nil, "invalid_rule_penalty_order"
    end
    if (normalized.streakBonusPerCorrect == 0) ~= (normalized.streakBonusMax == 0) then
        return nil, "invalid_rule_streak_bonus"
    end
    return normalized
end

function Rules.Encode(raw)
    local normalized, reason = Rules.Normalize(raw)
    if not normalized then
        return nil, reason
    end
    local encoded = {}
    for index, field in ipairs(FIELDS) do
        local value = normalized[field[1]]
        local units = type(value) == "boolean" and (value and 1 or 0) or math.floor(value * field[5] + 0.5)
        encoded[index] = string.format("%d", units)
    end
    return table.concat(encoded, ":")
end

function Rules.Decode(key)
    if type(key) ~= "string" or #key == 0 or #key > MAX_KEY_BYTES or key:find("[^%d:]") then
        return nil, "invalid_rules_key"
    end
    local values = {}
    for value in key:gmatch("[^:]+") do
        values[#values + 1] = value
    end
    if #values ~= #FIELDS then
        return nil, "invalid_rules_key"
    end
    local raw = {}
    for index, field in ipairs(FIELDS) do
        local value = tonumber(values[index])
        if type(field[2]) == "boolean" then
            if value ~= 0 and value ~= 1 then
                return nil, "invalid_rules_key"
            end
            raw[field[1]] = value == 1
        else
            raw[field[1]] = value / field[5]
        end
    end
    local normalized = Rules.Normalize(raw)
    if not normalized or Rules.Encode(normalized) ~= key then
        return nil, "invalid_rules_key"
    end
    return normalized
end

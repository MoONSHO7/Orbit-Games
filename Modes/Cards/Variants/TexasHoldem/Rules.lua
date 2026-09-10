local _, Games = ...
local Cards = Games.Cards
local Holdem = Cards.TexasHoldem

local RULES_VERSION = 2
local BLIND_RATE_DIVISOR = 1000
local MAX_CHIPS = Cards.MAX_CHIPS
local FIELDS = {
    { key = "version", default = RULES_VERSION, minimum = RULES_VERSION, maximum = RULES_VERSION },
    { key = "maxPlayers", default = 8, minimum = 2, maximum = 8 },
    { key = "buyIn", default = 10000, minimum = Cards.BUY_IN_MIN, maximum = Cards.BUY_IN_MAX },
    { key = "smallBlind", default = 50, minimum = 1, maximum = MAX_CHIPS },
    { key = "bigBlind", default = 100, minimum = 2, maximum = MAX_CHIPS },
    { key = "actionSeconds", default = 30, minimum = 15, maximum = 120 },
}
local KNOWN_FIELDS = {}
for _, field in ipairs(FIELDS) do
    KNOWN_FIELDS[field.key] = true
end

local Rules = {
    VERSION = RULES_VERSION,
    MAX_CHIPS = MAX_CHIPS,
    BLIND_RATE_MIN = 5,
    BLIND_RATE_MAX = 25,
    BLIND_RATE_STEP = 1,
    BLIND_RATE_DEFAULT = 5,
}
Holdem.Rules = Rules

local function IsInteger(value, minimum, maximum)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= minimum and value <= maximum
end

function Rules.SmallBlindForRate(buyIn, rate)
    if
        not IsInteger(buyIn, Cards.BUY_IN_MIN, Cards.BUY_IN_MAX)
        or not IsInteger(rate, Rules.BLIND_RATE_MIN, Rules.BLIND_RATE_MAX)
        or (rate - Rules.BLIND_RATE_MIN) % Rules.BLIND_RATE_STEP ~= 0
    then
        return nil
    end
    return math.floor(buyIn * rate / BLIND_RATE_DIVISOR)
end

function Rules.BlindRateForSmallBlind(buyIn, smallBlind)
    if not IsInteger(smallBlind, 1, MAX_CHIPS) then
        return nil
    end
    for rate = Rules.BLIND_RATE_MIN, Rules.BLIND_RATE_MAX, Rules.BLIND_RATE_STEP do
        if Rules.SmallBlindForRate(buyIn, rate) == smallBlind then
            return rate
        end
    end
end

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
        local value = raw[field.key]
        if value == nil then
            value = field.default
        end
        if not IsInteger(value, field.minimum, field.maximum) then
            return nil, "invalid_rule_" .. field.key
        end
        normalized[field.key] = value
    end
    if normalized.bigBlind ~= normalized.smallBlind * 2 then
        return nil, "invalid_blind_order"
    end
    if not Rules.BlindRateForSmallBlind(normalized.buyIn, normalized.smallBlind) then
        return nil, "invalid_blind_rate"
    end
    if (normalized.actionSeconds - Games.Cards.ACTION_SECONDS_MIN) % Games.Cards.ACTION_SECONDS_STEP ~= 0 then
        return nil, "invalid_rule_actionSeconds"
    end
    return normalized
end

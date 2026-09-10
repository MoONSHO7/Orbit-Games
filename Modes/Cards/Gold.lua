local _, Games = ...
local Cards = Games.Cards

local COMPACT_BASE = 1000
local COMPACT_DECIMAL_FACTOR = 100
local COMPACT_UNITS = {
    { threshold = 1000000000000, suffix = "T" },
    { threshold = 1000000000, suffix = "B" },
    { threshold = 1000000, suffix = "M" },
    { threshold = 1000, suffix = "K" },
}

local Gold = {}
Cards.Gold = Gold

local function RoundedCompact(amount, unit)
    return math.floor((amount * COMPACT_DECIMAL_FACTOR + unit.threshold / 2) / unit.threshold)
end

function Gold:Format(amount)
    return string.format("%.0f", amount)
end

function Gold:FormatSigned(amount)
    local sign = amount > 0 and "+" or amount < 0 and "-" or ""
    return sign .. self:Format(math.abs(amount))
end

function Gold:FormatCompact(amount)
    for unitIndex, unit in ipairs(COMPACT_UNITS) do
        if amount >= unit.threshold then
            local rounded = RoundedCompact(amount, unit)
            if rounded >= COMPACT_BASE * COMPACT_DECIMAL_FACTOR and unitIndex > 1 then
                unit = COMPACT_UNITS[unitIndex - 1]
                rounded = RoundedCompact(amount, unit)
            end
            local whole = math.floor(rounded / COMPACT_DECIMAL_FACTOR)
            local fraction = rounded % COMPACT_DECIMAL_FACTOR
            if fraction % 10 > 0 then
                return string.format("%.0f.%02d%s", whole, fraction, unit.suffix)
            elseif fraction > 0 then
                return string.format("%.0f.%d%s", whole, fraction / 10, unit.suffix)
            end
            return string.format("%.0f%s", whole, unit.suffix)
        end
    end
    return self:Format(amount)
end

function Gold:Parse(text, maximum)
    if type(text) ~= "string" then
        return nil
    end
    local whole = text:match("^%s*(%d+)%s*$")
    if not whole then
        return nil
    end
    local amount = tonumber(whole)
    return amount and amount <= maximum and amount or nil
end

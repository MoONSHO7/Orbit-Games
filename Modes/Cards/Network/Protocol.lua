local _, Games = ...
local Cards = Games.Cards

local MAX_TOKEN_BYTES = 128
local MAX_REASON_BYTES = 64
local MAX_SEQUENCE = 9007199254740990
local FIELD_COUNTS = {
    J = 3,
    W = 4,
    P = 4,
    A = 7,
    O = 5,
    B = 4,
    T = 3,
    L = 3,
    K = 4,
    E = 4,
    X = 2,
}
local ACTIONS = { fold = true, check = true, call = true, bet = true, raise = true, all_in = true }

local Protocol = {}
Cards.Protocol = Protocol

local function Token(value, empty)
    return type(value) == "string"
        and #value <= MAX_TOKEN_BYTES
        and (empty or #value > 0)
        and value:match("^[%w_.%-]*$") ~= nil
end

local function Identity(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_TOKEN_BYTES
        and value:find("%S") ~= nil
        and not value:find("[%z\1-\31\127|]")
end

local function Integer(value, minimum, maximum, empty)
    if empty and value == "" then
        return nil, true
    end
    if type(value) ~= "string" or not value:match("^%d+$") then
        return nil, false
    end
    local number = tonumber(value)
    return number, number ~= nil and number % 1 == 0 and number >= minimum and number <= maximum
end

local function Sequence(value)
    return Integer(value, 1, MAX_SEQUENCE)
end

local function Fields(...)
    local fields = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        fields[index] = type(value) == "number" and string.format("%.0f", value) or value
    end
    return fields
end

function Protocol.Join(request, advertisedSession)
    return Fields("J", request, advertisedSession or "")
end

function Protocol.Welcome(sessionId, request, playerId)
    return Fields("W", sessionId, request, playerId)
end

function Protocol.Projection(sessionId, revision, payload)
    return Fields("P", sessionId, revision, payload)
end

function Protocol.Action(sessionId, request, sequence, action, targetAmount, revision)
    return Fields("A", sessionId, request, sequence, action, targetAmount or "", revision)
end

function Protocol.SitOut(sessionId, request, sequence, sittingOut)
    return Fields("O", sessionId, request, sequence, sittingOut and "1" or "0")
end

function Protocol.Rebuy(sessionId, request, sequence)
    return Fields("B", sessionId, request, sequence)
end

function Protocol.Heartbeat(sessionId, request)
    return Fields("T", sessionId, request)
end

function Protocol.Leave(sessionId, request)
    return Fields("L", sessionId or "", request)
end

function Protocol.Acknowledge(sessionId, request, sequence)
    return Fields("K", sessionId, request, sequence)
end

function Protocol.Error(request, sequence, reason)
    return Fields("E", request, sequence and string.format("%.0f", sequence) or "", reason)
end

function Protocol.Close(sessionId)
    return Fields("X", sessionId)
end

function Protocol.Decode(fields)
    if type(fields) ~= "table" then
        return nil
    end
    local code = fields[1]
    if not FIELD_COUNTS[code] or #fields ~= FIELD_COUNTS[code] then
        return nil
    end
    for _, field in ipairs(fields) do
        if type(field) ~= "string" then
            return nil
        end
    end
    if code == "J" then
        if not Token(fields[2]) or not Token(fields[3], true) then
            return nil
        end
        return { code = code, request = fields[2], advertisedSession = fields[3] ~= "" and fields[3] or nil }
    end
    if code == "X" then
        return Token(fields[2]) and { code = code, sessionId = fields[2] } or nil
    end
    if code == "E" then
        local sequence, sequenceOk = Integer(fields[3], 1, MAX_SEQUENCE, true)
        if not Token(fields[2]) or not sequenceOk or not Token(fields[4]) or #fields[4] > MAX_REASON_BYTES then
            return nil
        end
        return { code = code, request = fields[2], sequence = sequence, reason = fields[4] }
    end
    if not Token(fields[2]) then
        return nil
    end
    if code == "P" then
        local revision, ok = Integer(fields[3], 0, MAX_SEQUENCE)
        if not ok or #fields[4] == 0 or #fields[4] > 4096 then
            return nil
        end
        return { code = code, sessionId = fields[2], revision = revision, payload = fields[4] }
    end
    if code == "W" then
        if not Token(fields[3]) or not Identity(fields[4]) then
            return nil
        end
        return { code = code, sessionId = fields[2], request = fields[3], playerId = fields[4] }
    end
    if not Token(fields[3]) then
        return nil
    end
    if code == "T" or code == "L" then
        return { code = code, sessionId = fields[2] ~= "" and fields[2] or nil, request = fields[3] }
    end
    local sequence, ok = Sequence(fields[4])
    if not ok then
        return nil
    end
    if code == "K" or code == "B" then
        return { code = code, sessionId = fields[2], request = fields[3], sequence = sequence }
    end
    if code == "O" then
        if fields[5] ~= "0" and fields[5] ~= "1" then
            return nil
        end
        return {
            code = code,
            sessionId = fields[2],
            request = fields[3],
            sequence = sequence,
            sittingOut = fields[5] == "1",
        }
    end
    if code == "A" then
        local targetAmount, targetOk = Integer(fields[6], 0, Cards.MAX_TOTAL_CHIPS, true)
        local revision, revisionOk = Integer(fields[7], 0, MAX_SEQUENCE)
        if not ACTIONS[fields[5]] or not targetOk or not revisionOk then
            return nil
        end
        return {
            code = code,
            sessionId = fields[2],
            request = fields[3],
            sequence = sequence,
            action = fields[5],
            targetAmount = targetAmount,
            revision = revision,
        }
    end
end

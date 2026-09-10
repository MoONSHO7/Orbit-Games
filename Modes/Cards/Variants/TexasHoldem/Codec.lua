local _, Games = ...
local Cards = Games.Cards
local Holdem = Cards.TexasHoldem

local SCHEMA_VERSION = 2
local MAX_PAYLOAD_BYTES = 4096
local MAX_FIELDS = 512
local MAX_FIELD_BYTES = 256
local MAX_ACTIONS = 16
local MAX_IDENTITY_BYTES = 128
local STATES = {
    between_hands = true,
    preflop = true,
    flop = true,
    turn = true,
    river = true,
    complete = true,
    paused = true,
}
local LEGACY_CURRENCY_MODES = { practice = true, gold = true }
local ACTIONS = {
    small_blind = true,
    big_blind = true,
    fold = true,
    check = true,
    call = true,
    bet = true,
    raise = true,
    all_in = true,
}

local Codec = {}
Holdem.Codec = Codec

local function IsInteger(value, minimum, maximum)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= minimum and value <= maximum
end

local function IsText(value, maximum, empty)
    return type(value) == "string"
        and #value <= maximum
        and (empty or value:find("%S") ~= nil)
        and not value:find("[%z\1-\31\127|]")
end

local function BooleanText(value)
    return value == nil and "-" or value and "1" or "0"
end

local function NumberText(value)
    return value == nil and "" or string.format("%.0f", value)
end

local function Pack(fields)
    local pieces = { #fields .. ":" }
    local size = #pieces[1]
    for _, field in ipairs(fields) do
        if type(field) ~= "string" or #field > MAX_FIELD_BYTES then
            return nil, "invalid_projection"
        end
        local length = #field .. ":"
        size = size + #length + #field
        if size > MAX_PAYLOAD_BYTES then
            return nil, "projection_too_large"
        end
        pieces[#pieces + 1] = length
        pieces[#pieces + 1] = field
    end
    return table.concat(pieces)
end

local function Unpack(payload)
    if type(payload) ~= "string" or #payload > MAX_PAYLOAD_BYTES then
        return nil
    end
    local separator = payload:find(":", 1, true)
    if not separator then
        return nil
    end
    local countText = payload:sub(1, separator - 1)
    if not countText:match("^%d+$") then
        return nil
    end
    local count, cursor = tonumber(countText), separator + 1
    if count > MAX_FIELDS then
        return nil
    end
    local fields = {}
    for index = 1, count do
        separator = payload:find(":", cursor, true)
        if not separator then
            return nil
        end
        local lengthText = payload:sub(cursor, separator - 1)
        if not lengthText:match("^%d+$") then
            return nil
        end
        local length = tonumber(lengthText)
        cursor = separator + 1
        if length > MAX_FIELD_BYTES or cursor + length - 1 > #payload then
            return nil
        end
        fields[index] = payload:sub(cursor, cursor + length - 1)
        cursor = cursor + length
    end
    if cursor ~= #payload + 1 then
        return nil
    end
    return fields
end

local function Reader(fields)
    return { fields = fields, cursor = 0 }
end

local function Read(reader)
    reader.cursor = reader.cursor + 1
    return reader.fields[reader.cursor]
end

local function ReadInteger(reader, minimum, maximum, optional)
    local text = Read(reader)
    if optional and text == "" then
        return nil, true
    end
    if type(text) ~= "string" or not text:match("^%-?%d+$") then
        return nil, false
    end
    local value = tonumber(text)
    return value, IsInteger(value, minimum, maximum)
end

local function ReadBoolean(reader)
    local text = Read(reader)
    if text == "-" then
        return nil, true
    end
    if text == "1" then
        return true, true
    end
    if text == "0" then
        return false, true
    end
    return nil, false
end

local function Add(fields, value)
    fields[#fields + 1] = value
end

local function AddNumber(fields, value)
    Add(fields, NumberText(value))
end

local function AddBoolean(fields, value)
    Add(fields, BooleanText(value))
end

local function EncodeActions(fields, actions)
    actions = actions or {}
    local first = math.max(1, #actions - MAX_ACTIONS + 1)
    AddNumber(fields, #actions - first + 1)
    for index = first, #actions do
        local action = actions[index]
        AddNumber(fields, action.revision)
        Add(fields, action.street or "")
        AddNumber(fields, action.seat)
        Add(fields, action.action or "")
        AddNumber(fields, action.paid)
        AddNumber(fields, action.target)
        AddBoolean(fields, action.automatic)
    end
end

function Codec.EncodeProjection(projection, now)
    if type(projection) ~= "table" or not STATES[projection.state] or type(now) ~= "number" then
        return nil, "invalid_projection"
    end
    local rules = projection.rules
    if type(rules) ~= "table" or type(projection.seats) ~= "table" or #projection.seats > Cards.MAX_PLAYERS then
        return nil, "invalid_projection"
    end
    local fields = {}
    AddNumber(fields, SCHEMA_VERSION)
    Add(fields, projection.activityId or "")
    AddNumber(fields, projection.activityVersion)
    Add(fields, projection.state)
    Add(fields, Cards.CURRENCY_MODE)
    AddBoolean(fields, projection.allowRebuys)
    AddNumber(fields, projection.revision)
    for _, key in ipairs({ "version", "maxPlayers", "buyIn", "smallBlind", "bigBlind", "actionSeconds" }) do
        AddNumber(fields, rules[key])
    end
    Add(fields, projection.handId or "")
    for _, key in ipairs({
        "buttonSeat",
        "smallBlindSeat",
        "bigBlindSeat",
        "actorSeat",
        "currentBet",
        "minimumRaise",
        "pot",
    }) do
        AddNumber(fields, projection[key])
    end
    local remaining = projection.actionDeadline and math.max(0, projection.actionDeadline - now) or nil
    AddNumber(fields, remaining and math.floor(remaining * 1000 + 0.5) or nil)
    AddBoolean(fields, projection.showdown)
    AddNumber(fields, #(projection.board or {}))
    for _, cardId in ipairs(projection.board or {}) do
        AddNumber(fields, cardId)
    end
    AddNumber(fields, #projection.seats)
    local settlement = projection.settlement or {}
    for _, seat in ipairs(projection.seats) do
        for _, key in ipairs({ "seat", "id", "name", "stack" }) do
            if key == "id" or key == "name" then
                Add(fields, seat[key] or "")
            else
                AddNumber(fields, seat[key])
            end
        end
        for _, key in ipairs({ "sittingOut", "inHand", "folded", "allIn" }) do
            AddBoolean(fields, seat[key])
        end
        AddBoolean(fields, true)
        AddBoolean(fields, seat.connected ~= false)
        AddNumber(fields, seat.streetBet)
        AddNumber(fields, seat.committed)
        AddNumber(fields, #(seat.holeCards or {}))
        for _, cardId in ipairs(seat.holeCards or {}) do
            AddNumber(fields, cardId)
        end
        AddNumber(fields, settlement.payouts and settlement.payouts[seat.seat] or nil)
        AddNumber(fields, settlement.refunds and settlement.refunds[seat.seat] or nil)
    end
    local legal = projection.legalActions
    AddBoolean(fields, legal ~= nil)
    if legal then
        for _, key in ipairs({ "fold", "check", "call", "bet", "raise", "allIn" }) do
            AddBoolean(fields, legal[key])
        end
        for _, key in ipairs({ "callAmount", "toCall", "minTarget", "maxTarget" }) do
            AddNumber(fields, legal[key])
        end
    end
    EncodeActions(fields, projection.actions)
    return Pack(fields)
end

local function DecodeRules(reader)
    local raw, ok = {}
    for _, key in ipairs({ "version", "maxPlayers", "buyIn", "smallBlind", "bigBlind", "actionSeconds" }) do
        raw[key], ok = ReadInteger(reader, 0, Cards.MAX_CHIPS)
        if not ok then
            return nil
        end
    end
    return Holdem.Rules.Normalize(raw)
end

local function DecodeBoard(reader)
    local count, ok = ReadInteger(reader, 0, 5)
    if not ok then
        return nil
    end
    local board, seen = {}, {}
    for index = 1, count do
        local cardId
        cardId, ok = ReadInteger(reader, 1, Cards.CardCatalog.COUNT)
        if not ok or seen[cardId] then
            return nil
        end
        board[index], seen[cardId] = cardId, true
    end
    return board, seen
end

local function DecodeSeats(reader, maxPlayers, seenCards)
    local count, ok = ReadInteger(reader, 0, maxPlayers)
    if not ok then
        return nil
    end
    local seats, seenSeats, seenIds = {}, {}, {}
    for index = 1, count do
        local seat = {}
        seat.seat, ok = ReadInteger(reader, 1, maxPlayers)
        if not ok or seenSeats[seat.seat] then
            return nil
        end
        seat.id, seat.name = Read(reader), Read(reader)
        if not IsText(seat.id, MAX_IDENTITY_BYTES) or not IsText(seat.name, MAX_IDENTITY_BYTES) or seenIds[seat.id] then
            return nil
        end
        seat.stack, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS)
        if not ok then
            return nil
        end
        for _, key in ipairs({ "sittingOut", "inHand", "folded", "allIn" }) do
            seat[key], ok = ReadBoolean(reader)
            if not ok then
                return nil
            end
        end
        local _, fundedOk = ReadBoolean(reader)
        if not fundedOk then
            return nil
        end
        seat.funded = true
        seat.connected, ok = ReadBoolean(reader)
        if not ok or seat.connected == nil then
            return nil
        end
        seat.streetBet, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil
        end
        seat.committed, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil
        end
        local holeCount
        holeCount, ok = ReadInteger(reader, 0, 2)
        if not ok then
            return nil
        end
        if holeCount > 0 then
            seat.holeCards = {}
            for cardIndex = 1, holeCount do
                local cardId
                cardId, ok = ReadInteger(reader, 1, Cards.CardCatalog.COUNT)
                if not ok or seenCards[cardId] then
                    return nil
                end
                seat.holeCards[cardIndex], seenCards[cardId] = cardId, true
            end
        end
        seat.payout, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil
        end
        seat.refund, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil
        end
        seats[index], seenSeats[seat.seat], seenIds[seat.id] = seat, true, true
    end
    table.sort(seats, function(left, right)
        return left.seat < right.seat
    end)
    return seats
end

local function DecodeLegalActions(reader)
    local present, ok = ReadBoolean(reader)
    if not ok or present == nil then
        return nil, false
    end
    if not present then
        return nil, true
    end
    local legal = {}
    for _, key in ipairs({ "fold", "check", "call", "bet", "raise", "allIn" }) do
        legal[key], ok = ReadBoolean(reader)
        if not ok or legal[key] == nil then
            return nil, false
        end
    end
    for _, key in ipairs({ "callAmount", "toCall", "minTarget", "maxTarget" }) do
        legal[key], ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil, false
        end
    end
    if
        (legal.bet or legal.raise)
        and (legal.minTarget == nil or legal.maxTarget == nil or legal.minTarget > legal.maxTarget)
    then
        return nil, false
    end
    return legal, true
end

local function DecodeActions(reader, maxPlayers)
    local count, ok = ReadInteger(reader, 0, MAX_ACTIONS)
    if not ok then
        return nil
    end
    local actions = {}
    for index = 1, count do
        local action = {}
        action.revision, ok = ReadInteger(reader, 1, Cards.MAX_CHIPS, true)
        action.street = Read(reader)
        action.seat, ok = ReadInteger(reader, 1, maxPlayers)
        if not ok then
            return nil
        end
        action.action = Read(reader)
        if not ACTIONS[action.action] or not STATES[action.street] then
            return nil
        end
        action.paid, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil
        end
        action.target, ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil
        end
        action.automatic, ok = ReadBoolean(reader)
        if not ok then
            return nil
        end
        actions[index] = action
    end
    return actions
end

function Codec.DecodeProjection(payload, now)
    local fields = Unpack(payload)
    if not fields or type(now) ~= "number" then
        return nil, "invalid_projection"
    end
    local reader, ok = Reader(fields)
    local schema
    schema, ok = ReadInteger(reader, SCHEMA_VERSION, SCHEMA_VERSION)
    if not ok then
        return nil, "invalid_projection"
    end
    local projection = { activityId = Read(reader) }
    projection.activityVersion, ok = ReadInteger(reader, 1, 2147483647)
    projection.state = Read(reader)
    local currencyMode = Read(reader)
    projection.allowRebuys, ok = ReadBoolean(reader)
    projection.revision, ok = ReadInteger(reader, 0, Cards.MAX_CHIPS)
    if
        not ok
        or projection.activityId ~= Cards.VARIANT_ID
        or projection.activityVersion ~= Cards.ACTIVITY_VERSION
        or not STATES[projection.state]
        or not LEGACY_CURRENCY_MODES[currencyMode]
        or projection.allowRebuys == nil
    then
        return nil, "invalid_projection"
    end
    projection.currencyMode = Cards.CURRENCY_MODE
    projection.rules = DecodeRules(reader)
    if not projection.rules then
        return nil, "invalid_projection"
    end
    projection.handId = Read(reader)
    if projection.handId == "" then
        projection.handId = nil
    elseif not IsText(projection.handId, 64) then
        return nil, "invalid_projection"
    end
    for _, key in ipairs({ "buttonSeat", "smallBlindSeat", "bigBlindSeat", "actorSeat" }) do
        projection[key], ok = ReadInteger(reader, 1, projection.rules.maxPlayers, true)
        if not ok then
            return nil, "invalid_projection"
        end
    end
    for _, key in ipairs({ "currentBet", "minimumRaise", "pot" }) do
        projection[key], ok = ReadInteger(reader, 0, Cards.MAX_TOTAL_CHIPS, true)
        if not ok then
            return nil, "invalid_projection"
        end
    end
    local remainingMilliseconds
    remainingMilliseconds, ok = ReadInteger(reader, 0, projection.rules.actionSeconds * 1000, true)
    if not ok then
        return nil, "invalid_projection"
    end
    projection.actionDeadline = remainingMilliseconds and now + remainingMilliseconds / 1000 or nil
    projection.showdown, ok = ReadBoolean(reader)
    if not ok then
        return nil, "invalid_projection"
    end
    local seenCards
    projection.board, seenCards = DecodeBoard(reader)
    if not projection.board then
        return nil, "invalid_projection"
    end
    projection.seats = DecodeSeats(reader, projection.rules.maxPlayers, seenCards)
    if not projection.seats then
        return nil, "invalid_projection"
    end
    projection.legalActions, ok = DecodeLegalActions(reader)
    if not ok then
        return nil, "invalid_projection"
    end
    projection.actions = DecodeActions(reader, projection.rules.maxPlayers)
    if not projection.actions or reader.cursor ~= #fields then
        return nil, "invalid_projection"
    end
    return projection
end

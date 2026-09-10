local _, Games = ...
local Cards = Games.Cards

local SCHEMA_VERSION = 4
local PREVIOUS_SCHEMA_VERSION = 3
local LEGACY_SCHEMA_VERSIONS = { [1] = true, [2] = true }
local MAX_SAFE_INTEGER = Cards.MAX_CHIPS
local MAX_SETTLEMENTS = 50
local MAX_TOKEN_BYTES = 64
local MAX_NAME_BYTES = 128
local MAX_TABLE_FONT_LENGTH = 128
local LEGACY_CURRENCY_MODES = { practice = true, gold = true }
local DEFAULT_HOST_SETTINGS = {
    buyIn = 10000,
    smallBlind = 50,
    bigBlind = 100,
    maxPlayers = Cards.MAX_PLAYERS,
    actionSeconds = Cards.ACTION_SECONDS_DEFAULT,
    allowRebuys = true,
}
local DEFAULT_TABLE_SETTINGS = {
    scale = Cards.TABLE_SCALE_DEFAULT,
    font = "",
    x = 0.5,
    y = 0.5,
    showHistory = true,
}

local Store = {}
Cards.Store = Store

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function IsInteger(value, minimum, maximum)
    return IsFinite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function IsFontName(value)
    return type(value) == "string"
        and #value <= MAX_TABLE_FONT_LENGTH
        and not value:find("[%z\1-\31\127|]")
        and (value == "" or value:find("%S") ~= nil)
end

local function IsText(value, maximum)
    return type(value) == "string"
        and #value > 0
        and #value <= maximum
        and value:find("%S") ~= nil
        and not value:find("[%z\1-\31\127|{}]")
end

local function IsArray(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if not IsInteger(key, 1, #value) then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function CopyHostSettings(settings)
    if settings == nil then
        settings = DEFAULT_HOST_SETTINGS
    end
    if type(settings) ~= "table" then
        return nil, "invalid_settings"
    end
    if settings.currencyMode ~= nil and not LEGACY_CURRENCY_MODES[settings.currencyMode] then
        return nil, "invalid_currency_mode"
    end
    local copy = {}
    for key, default in pairs(DEFAULT_HOST_SETTINGS) do
        copy[key] = settings[key] == nil and default or settings[key]
    end
    if not IsInteger(copy.buyIn, Cards.BUY_IN_MIN, Cards.BUY_IN_MAX) then
        return nil, "invalid_buy_in"
    end
    if
        not IsInteger(copy.smallBlind, 1, MAX_SAFE_INTEGER)
        or not Cards.TexasHoldem.Rules.BlindRateForSmallBlind(copy.buyIn, copy.smallBlind)
    then
        return nil, "invalid_small_blind"
    end
    if not IsInteger(copy.bigBlind, 2, MAX_SAFE_INTEGER) or copy.bigBlind ~= copy.smallBlind * 2 then
        return nil, "invalid_big_blind"
    end
    if not IsInteger(copy.maxPlayers, Cards.MIN_PLAYERS, Cards.MAX_PLAYERS) then
        return nil, "invalid_max_players"
    end
    if
        not IsInteger(copy.actionSeconds, Cards.ACTION_SECONDS_MIN, Cards.ACTION_SECONDS_MAX)
        or (copy.actionSeconds - Cards.ACTION_SECONDS_MIN) % Cards.ACTION_SECONDS_STEP ~= 0
    then
        return nil, "invalid_action_seconds"
    end
    if type(copy.allowRebuys) ~= "boolean" then
        return nil, "invalid_rebuys"
    end
    return copy
end

local function CopyTableSettings(settings)
    if settings == nil then
        settings = DEFAULT_TABLE_SETTINGS
    end
    if type(settings) ~= "table" then
        return nil, "invalid_table_settings"
    end
    local copy = {}
    for key, default in pairs(DEFAULT_TABLE_SETTINGS) do
        copy[key] = settings[key] == nil and default or settings[key]
    end
    if
        not IsInteger(copy.scale, Cards.TABLE_SCALE_MIN, Cards.TABLE_SCALE_MAX)
        or (copy.scale - Cards.TABLE_SCALE_MIN) % Cards.TABLE_SCALE_STEP ~= 0
    then
        return nil, "invalid_table_scale"
    end
    if not IsFontName(copy.font) then
        return nil, "invalid_table_font"
    end
    if not IsFinite(copy.x) or copy.x < 0 or copy.x > 1 or not IsFinite(copy.y) or copy.y < 0 or copy.y > 1 then
        return nil, "invalid_table_settings"
    end
    if type(copy.showHistory) ~= "boolean" then
        return nil, "invalid_table_settings"
    end
    return copy
end

local function CopySettlementPlayer(player)
    if type(player) ~= "table" then
        return nil
    end
    if not IsText(player.id, MAX_NAME_BYTES) or not IsText(player.name, MAX_NAME_BYTES) then
        return nil
    end
    if
        not IsInteger(player.buyIn, 0, MAX_SAFE_INTEGER)
        or not IsInteger(player.rebuy, 0, Cards.MAX_TOTAL_CHIPS)
        or not IsInteger(player.finalStack, 0, Cards.MAX_TOTAL_CHIPS)
    then
        return nil
    end
    local net = player.finalStack - player.buyIn - player.rebuy
    if player.net ~= nil and player.net ~= net then
        return nil
    end
    if player.funded ~= nil and type(player.funded) ~= "boolean" then
        return nil
    end
    if player.paid ~= nil and type(player.paid) ~= "boolean" then
        return nil
    end
    return {
        id = player.id,
        name = player.name,
        buyIn = player.buyIn,
        rebuy = player.rebuy,
        finalStack = player.finalStack,
        net = net,
    }
end

local function CopySettlement(settlement)
    if type(settlement) ~= "table" or not IsArray(settlement.players) then
        return nil
    end
    if
        not IsText(settlement.id, MAX_TOKEN_BYTES)
        or not IsText(settlement.variantId, MAX_TOKEN_BYTES)
        or not IsInteger(settlement.endedAt, 0, MAX_SAFE_INTEGER)
        or (settlement.currencyMode ~= nil and not LEGACY_CURRENCY_MODES[settlement.currencyMode])
        or #settlement.players < 1
        or #settlement.players > Cards.MAX_PLAYERS
    then
        return nil
    end
    local copy = {
        id = settlement.id,
        variantId = settlement.variantId,
        endedAt = settlement.endedAt,
        players = {},
    }
    local seen = {}
    for _, player in ipairs(settlement.players) do
        local entry = CopySettlementPlayer(player)
        if not entry or seen[entry.id] then
            return nil
        end
        seen[entry.id] = true
        copy.players[#copy.players + 1] = entry
    end
    return copy
end

local function CopySettlements(settlements)
    if settlements == nil then
        return {}
    end
    if not IsArray(settlements) then
        return nil
    end
    local copy, seen = {}, {}
    local first = math.max(1, #settlements - MAX_SETTLEMENTS + 1)
    for index = first, #settlements do
        local settlement = CopySettlement(settlements[index])
        if not settlement or seen[settlement.id] then
            return nil
        end
        seen[settlement.id] = true
        copy[#copy + 1] = settlement
    end
    return copy
end

local function CopySettings(settings)
    local copy = {}
    for key, value in pairs(settings) do
        copy[key] = value
    end
    return copy
end

function Store:Normalize(saved)
    if saved == nil then
        saved = {}
    end
    if type(saved) ~= "table" then
        return nil, "invalid_settings"
    end
    local schemaVersion = saved.schemaVersion or SCHEMA_VERSION
    if
        not LEGACY_SCHEMA_VERSIONS[schemaVersion]
        and schemaVersion ~= PREVIOUS_SCHEMA_VERSION
        and schemaVersion ~= SCHEMA_VERSION
    then
        return nil,
            type(schemaVersion) == "number" and schemaVersion > SCHEMA_VERSION and "unsupported_database_version"
                or "invalid_database_version"
    end
    local selectedVariant = saved.selectedVariant or Cards.VARIANT_ID
    if selectedVariant ~= Cards.VARIANT_ID then
        return nil, "invalid_variant"
    end
    local hostSettings, hostError = CopyHostSettings(saved.hostSettings)
    if not hostSettings and LEGACY_SCHEMA_VERSIONS[schemaVersion] then
        hostSettings = assert(CopyHostSettings(nil))
    end
    if not hostSettings then
        return nil, hostError
    end
    local tableSettings, tableError = CopyTableSettings(saved.tableSettings)
    if not tableSettings then
        return nil, tableError
    end
    local settlements = CopySettlements(saved.settlements)
    if not settlements then
        return nil, "invalid_settlement"
    end
    local nextSessionId = saved.nextSessionId or 1
    local nextHandId = saved.nextHandId or 1
    if not IsInteger(nextSessionId, 1, MAX_SAFE_INTEGER) or not IsInteger(nextHandId, 1, MAX_SAFE_INTEGER) then
        return nil, "invalid_settings"
    end
    return {
        schemaVersion = SCHEMA_VERSION,
        selectedVariant = selectedVariant,
        hostSettings = hostSettings,
        tableSettings = tableSettings,
        settlements = settlements,
        nextSessionId = nextSessionId,
        nextHandId = nextHandId,
    }
end

function Store:Bind(saved)
    self.db = saved
    self.revision = 0
end

function Store:GetSelectedVariant()
    return self.db.selectedVariant
end

function Store:GetHostSettings()
    return CopySettings(self.db.hostSettings)
end

function Store:SaveHostSettings(settings)
    local copy, reason = CopyHostSettings(settings)
    if not copy then
        return false, reason
    end
    self.db.hostSettings = copy
    return true
end

function Store:GetTableSettings()
    return CopySettings(self.db.tableSettings)
end

function Store:SaveTableSettings(settings)
    local merged = self:GetTableSettings()
    for key, value in pairs(settings) do
        merged[key] = value
    end
    local copy, reason = CopyTableSettings(merged)
    if not copy then
        return false, reason
    end
    self.db.tableSettings = copy
    return true
end

function Store:GetSettlements()
    return CopySettlements(self.db.settlements)
end

function Store:AddSettlement(settlement)
    local copy = CopySettlement(settlement)
    if not copy then
        return false, "invalid_settlement"
    end
    for _, existing in ipairs(self.db.settlements) do
        if existing.id == copy.id then
            return false, "invalid_settlement"
        end
    end
    self.db.settlements[#self.db.settlements + 1] = copy
    if #self.db.settlements > MAX_SETTLEMENTS then
        table.remove(self.db.settlements, 1)
    end
    self.revision = self.revision + 1
    return true
end

function Store:NextSessionId()
    local id = self.db.nextSessionId
    if id >= MAX_SAFE_INTEGER then
        return nil, "session_ids_exhausted"
    end
    self.db.nextSessionId = id + 1
    return id
end

function Store:NextHandId()
    local id = self.db.nextHandId
    if id >= MAX_SAFE_INTEGER then
        return nil, "hand_ids_exhausted"
    end
    self.db.nextHandId = id + 1
    return id
end

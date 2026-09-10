local _, Games = ...

local SCHEMA_VERSION = 1
local DEFAULT_MINIMAP_POSITION = 225
local FULL_CIRCLE_DEGREES = 360
local MINIMAP_FLAGS = { "hide", "lock", "showInCompartment" }
local HOST_AUDIENCE_KEYS = { "server", "guild", "party" }

local Store = {}
Games.Store = Store

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function CopyMinimapSettings(settings)
    if settings == nil then
        settings = {}
    end
    if type(settings) ~= "table" then
        return nil
    end
    local position = settings.minimapPos == nil and DEFAULT_MINIMAP_POSITION or settings.minimapPos
    if not IsFinite(position) then
        return nil
    end
    local copy = { minimapPos = position % FULL_CIRCLE_DEGREES }
    for _, key in ipairs(MINIMAP_FLAGS) do
        if settings[key] ~= nil and type(settings[key]) ~= "boolean" then
            return nil
        end
        copy[key] = settings[key] == true
    end
    return copy
end

local function CopyHostAudiences(audiences)
    if audiences == nil then
        return { server = true, guild = true, party = true }
    end
    if type(audiences) ~= "table" then
        return nil
    end
    local copy, hasAudience = {}, false
    for _, key in ipairs(HOST_AUDIENCE_KEYS) do
        local selected = audiences[key]
        if type(selected) ~= "boolean" then
            return nil
        end
        copy[key] = selected
        hasAudience = hasAudience or selected
    end
    return hasAudience and copy or nil
end

local function IsEmpty(value)
    return type(value) == "table" and next(value) == nil
end

local function NormalizeModes(savedModes)
    if savedModes ~= nil and type(savedModes) ~= "table" then
        return nil, "invalid_database"
    end
    local modes = {}
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        local saved = savedModes and savedModes[gameType.id] or nil
        local normalized, reason = gameType.storage:Normalize(saved)
        if not normalized then
            return nil, reason
        end
        modes[gameType.id] = normalized
    end
    return modes
end

function Store:Initialize(saved)
    if saved == nil or IsEmpty(saved) then
        saved = { schemaVersion = SCHEMA_VERSION }
    end
    if type(saved) ~= "table" then
        return nil, "invalid_database"
    end
    if IsFinite(saved.schemaVersion) and saved.schemaVersion > SCHEMA_VERSION then
        return nil, "unsupported_database_version"
    end
    if saved.schemaVersion ~= SCHEMA_VERSION then
        return nil, "invalid_database_version"
    end
    local selectedGameType = saved.selectedGameType or Games.GameTypes:GetDefault().id
    if not Games.GameTypes:Get(selectedGameType) then
        selectedGameType = Games.GameTypes:GetDefault().id
    end
    local modes, modeError = NormalizeModes(saved.modes)
    if not modes then
        return nil, modeError
    end
    local minimap = CopyMinimapSettings(saved.minimap)
    if not minimap then
        return nil, "invalid_minimap_settings"
    end
    local hostAudiences = CopyHostAudiences(saved.hostAudiences)
    if not hostAudiences then
        return nil, "invalid_host_audiences"
    end
    local db = {
        schemaVersion = SCHEMA_VERSION,
        selectedGameType = selectedGameType,
        hostAudiences = hostAudiences,
        minimap = minimap,
        modes = modes,
    }
    self.db = db
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        gameType.storage:Bind(modes[gameType.id])
    end
    return db
end

function Store:GetSelectedGameType()
    return self.db.selectedGameType
end

function Store:SelectGameType(gameTypeId)
    if not Games.GameTypes:Get(gameTypeId) then
        return false, "invalid_game_type"
    end
    self.db.selectedGameType = gameTypeId
    return true
end

function Store:GetMinimapSettings()
    return self.db.minimap
end

function Store:GetHostAudiences()
    return CopyHostAudiences(self.db.hostAudiences)
end

function Store:SaveHostAudiences(audiences)
    if audiences == nil then
        return false, "invalid_host_audiences"
    end
    local copy = CopyHostAudiences(audiences)
    if not copy then
        return false, "invalid_host_audiences"
    end
    local current, changed = self.db.hostAudiences, false
    for _, key in ipairs(HOST_AUDIENCE_KEYS) do
        changed = changed or current[key] ~= copy[key]
    end
    if not changed then
        return false, "unchanged"
    end
    self.db.hostAudiences = copy
    return true
end

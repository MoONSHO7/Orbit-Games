local _, Games = ...

local MAX_ID_BYTES = 32
local MAX_PROTOCOL_VERSION = 2147483647
local REQUIRED_OWNERS = { "controller", "session", "storage", "advert", "commands", "locale" }
local REQUIRED_UI_OWNERS = { "hostPage", "settingsPage", "hud", "resultsPage" }
local REQUIRED_OWNER_METHODS = {
    controller = {
        "Initialize",
        "Shutdown",
        "IsRunning",
        "Start",
        "Pause",
        "Resume",
        "Stop",
        "Tick",
        "OnWaitingChanged",
        "HandleRuntimeError",
        "SetNotice",
        "GetNotice",
    },
    session = {
        "Initialize",
        "Shutdown",
        "IsActive",
        "IsJoinedTo",
        "JoinHost",
        "Leave",
        "SetRestricted",
        "Receive",
        "OnSendError",
        "GetView",
    },
    storage = { "Normalize", "Bind" },
    advert = { "GetHosted" },
    commands = { "Handle", "OnLogin" },
    locale = {},
}
local REQUIRED_UI_METHODS = {
    hostPage = { "Create", "Load", "Refresh", "CloseMenus" },
    settingsPage = { "Create", "Refresh", "CloseMenus" },
    hud = { "ApplySettings", "Refresh", "SetEditing", "OnDisplayChanged" },
    resultsPage = { "Create", "Layout", "CloseMenu", "Invalidate", "Refresh" },
}

local descriptors = {}
local defaultId
local explicitDefaultId

local GameTypes = {}
Games.GameTypes = GameTypes

local function IsPlainTable(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function IsId(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_ID_BYTES
        and value:match("^[a-z0-9][a-z0-9_-]*$") ~= nil
end

local function IsProtocolVersion(value)
    return type(value) == "number" and value > 0 and value <= MAX_PROTOCOL_VERSION and value % 1 == 0
end

function GameTypes:Register(descriptor)
    if not IsPlainTable(descriptor) then
        return false, "invalid_game_type"
    end
    if not IsId(descriptor.id) then
        return false, "invalid_game_type_id"
    end
    if descriptors[descriptor.id] then
        return false, "duplicate_game_type"
    end
    if type(descriptor.title) ~= "string" or not descriptor.title:find("%S") then
        return false, "invalid_game_type_title"
    end
    if type(descriptor.resultsTitle) ~= "string" or not descriptor.resultsTitle:find("%S") then
        return false, "invalid_game_type_results_title"
    end
    if not IsProtocolVersion(descriptor.protocolVersion) then
        return false, "invalid_game_type_protocol"
    end
    if descriptor.default ~= nil and type(descriptor.default) ~= "boolean" then
        return false, "invalid_game_type_default"
    end
    for _, owner in ipairs(REQUIRED_OWNERS) do
        if type(descriptor[owner]) ~= "table" then
            return false, "invalid_game_type_" .. owner
        end
        for _, method in ipairs(REQUIRED_OWNER_METHODS[owner]) do
            if type(descriptor[owner][method]) ~= "function" then
                return false, "invalid_game_type_" .. owner
            end
        end
    end
    if type(descriptor.locale.errors) ~= "table" then
        return false, "invalid_game_type_locale"
    end
    if descriptor.commands.help ~= nil and type(descriptor.commands.help) ~= "string" then
        return false, "invalid_game_type_commands"
    end
    if type(descriptor.ui) ~= "table" then
        return false, "invalid_game_type_ui"
    end
    for _, owner in ipairs(REQUIRED_UI_OWNERS) do
        if type(descriptor.ui[owner]) ~= "table" then
            return false, "invalid_game_type_ui_" .. owner
        end
        for _, method in ipairs(REQUIRED_UI_METHODS[owner]) do
            if type(descriptor.ui[owner][method]) ~= "function" then
                return false, "invalid_game_type_ui_" .. owner
            end
        end
    end
    if descriptor.default and explicitDefaultId then
        return false, "duplicate_default_game_type"
    end

    descriptors[descriptor.id] = descriptor
    if not defaultId or descriptor.default then
        defaultId = descriptor.id
    end
    if descriptor.default then
        explicitDefaultId = descriptor.id
    end
    return true
end

function GameTypes:Get(id)
    return descriptors[id]
end

function GameTypes:GetAll()
    local registered = {}
    for _, descriptor in pairs(descriptors) do
        registered[#registered + 1] = descriptor
    end
    table.sort(registered, function(left, right)
        if left.title ~= right.title then
            return left.title < right.title
        end
        return left.id < right.id
    end)
    return registered
end

function GameTypes:GetDefault()
    return descriptors[defaultId]
end

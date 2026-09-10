local _, Games = ...
local Cards = Games.Cards

local MAX_ID_BYTES = 32
local MAX_PROTOCOL_VERSION = 2147483647
local REQUIRED = { "rules", "model" }

Cards.Variants = { descriptors = {} }
local Variants = Cards.Variants

local function IsId(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_ID_BYTES
        and value:match("^[a-z0-9][a-z0-9_%-]*$") ~= nil
end

function Variants:Register(descriptor)
    if type(descriptor) ~= "table" or getmetatable(descriptor) ~= nil then
        return false, "invalid_variant"
    end
    if not IsId(descriptor.id) or self.descriptors[descriptor.id] then
        return false, "invalid_variant"
    end
    if type(descriptor.title) ~= "string" or not descriptor.title:find("%S") then
        return false, "invalid_variant"
    end
    if
        type(descriptor.protocolVersion) ~= "number"
        or descriptor.protocolVersion % 1 ~= 0
        or descriptor.protocolVersion < 1
        or descriptor.protocolVersion > MAX_PROTOCOL_VERSION
    then
        return false, "invalid_variant"
    end
    for _, owner in ipairs(REQUIRED) do
        if type(descriptor[owner]) ~= "table" then
            return false, "invalid_variant"
        end
    end
    self.descriptors[descriptor.id] = descriptor
    return true
end

function Variants:Get(id)
    return self.descriptors[id]
end

function Variants:GetAll()
    local descriptors = {}
    for _, descriptor in pairs(self.descriptors) do
        descriptors[#descriptors + 1] = descriptor
    end
    table.sort(descriptors, function(left, right)
        return left.title < right.title or left.title == right.title and left.id < right.id
    end)
    return descriptors
end

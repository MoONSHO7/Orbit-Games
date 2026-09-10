local _, Games = ...
local L = Games.L
local MAX_NAME_BYTES = 120

Games.Identity = {}
local Identity = Games.Identity

function Identity:NormalizeName(value)
    if issecretvalue(value) or type(value) ~= "string" or value:find("[%z\1-\31\127|<>]") then
        return nil
    end
    value = value:gsub("^ +", ""):gsub(" +$", "")
    if #value == 0 or #value > MAX_NAME_BYTES or value:find(" ", 1, true) then
        return nil
    end
    local separator = value:find("-", 1, true)
    local name = separator and value:sub(1, separator - 1) or value
    local realm = separator and value:sub(separator + 1) or GetNormalizedRealmName()
    if issecretvalue(realm) or type(realm) ~= "string" then
        return nil
    end
    if not name:match("^[%a\128-\255]+$") or not realm:match("^[%w\128-\255'%-]+$") then
        return nil
    end
    local fullName = name .. "-" .. realm
    if #fullName > MAX_NAME_BYTES then
        return nil
    end
    return fullName
end

function Identity:Initialize()
    local guid = UnitGUID("player")
    local name, realm = UnitFullName("player")
    if issecretvalue(guid) or issecretvalue(name) or issecretvalue(realm) then
        return false, L.HOST_UNAVAILABLE
    end
    if type(guid) ~= "string" or guid == "" or type(name) ~= "string" or name == "" then
        return false, L.HOST_UNAVAILABLE
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if issecretvalue(realm) or type(realm) ~= "string" or realm == "" then
        return false, L.HOST_UNAVAILABLE
    end
    self.guid, self.name = guid, name .. "-" .. realm
    return true
end

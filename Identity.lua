local _, Quiz = ...
local L = Quiz.L

Quiz.Identity = {}
local Identity = Quiz.Identity

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

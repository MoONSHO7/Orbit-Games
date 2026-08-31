local _, Quiz = ...
local FONT_TYPE = "font"
local MAX_FONT_NAME_LENGTH = 128

Quiz.Media = { revision = 0 }
local Media = Quiz.Media

function Media:ResolveFont(name)
    if
        not self.library
        or type(name) ~= "string"
        or #name > MAX_FONT_NAME_LENGTH
        or not name:find("%S")
        or name:find("[%z\1-\31\127|]")
    then
        return nil
    end
    local fonts = self.library:HashTable(FONT_TYPE)
    local path = fonts and fonts[name]
    if type(path) == "string" and path ~= "" and not path:find("[%z\1-\31\127|]") then
        return path
    end
end

function Media:HasFont(name)
    return name == "" or self:ResolveFont(name) ~= nil
end

function Media:GetFontNames()
    local names = {}
    if self.library then
        for _, name in ipairs(self.library:List(FONT_TYPE)) do
            if self:ResolveFont(name) then
                names[#names + 1] = name
            end
        end
    end
    return names
end

function Media:OnRegistered(_, mediaType)
    if mediaType == FONT_TYPE then
        self.revision = self.revision + 1
        self.onChanged()
    end
end

function Media:Initialize(onChanged)
    self.onChanged = onChanged
    if self.library then
        return
    end
    local library = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not library then
        return
    end
    self.library = library
    library.RegisterCallback(self, "LibSharedMedia_Registered", "OnRegistered")
    self.revision = self.revision + 1
    self.onChanged()
end

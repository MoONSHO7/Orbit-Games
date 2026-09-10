local _, Games = ...
local L = Games.L

Games.Minimap = {}
local Minimap = Games.Minimap

local function OnClick(_, button)
    if button == "LeftButton" then
        Games.Main:Command("")
    elseif button == "RightButton" then
        Games.Main:Command("settings")
    end
end

local function OnTooltipShow(tooltip)
    tooltip:AddLine(L.W_TITLE)
    tooltip:AddLine(L.W_MINIMAP_TOGGLE, 1, 1, 1)
    tooltip:AddLine(L.W_MINIMAP_SETTINGS, 1, 1, 1)
    tooltip:AddLine(L.W_MINIMAP_DRAG, 1, 1, 1)
end

function Minimap:Initialize()
    if self.registered then
        return
    end
    local broker = LibStub and LibStub("LibDataBroker-1.1", true)
    local icons = LibStub and LibStub("LibDBIcon-1.0", true)
    if not broker or not icons then
        return
    end
    local object = broker:NewDataObject(Games.addonName, {
        type = "launcher",
        label = L.W_TITLE,
        icon = Games.Media.icon,
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
    icons:Register(Games.addonName, object, Games.Store:GetMinimapSettings())
    self.registered = true
end

function Minimap:Refresh()
    if not self.registered then
        return
    end
    local icons = LibStub("LibDBIcon-1.0", true)
    local settings = Games.Store:GetMinimapSettings()
    icons:Refresh(Games.addonName, settings)
    if settings.showInCompartment and icons.AddButtonToCompartment then
        icons:AddButtonToCompartment(Games.addonName, Games.Media.icon)
    end
end

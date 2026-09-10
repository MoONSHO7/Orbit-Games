local _, Games = ...
local Cards = Games.Cards
local L = Cards.L

local SCALE_Y = 0
local FONT_Y = -40
local HISTORY_Y = -84

local SettingsPage = {}
Cards.SettingsPage = SettingsPage

local function ErrorText(reason)
    return L.errors[reason] or L.W_ACTION_FAILED
end

function SettingsPage:Save(settings)
    local ok, reason = Cards.Store:SaveTableSettings(settings)
    Games.UI.actionError = not ok and ErrorText(reason) or nil
    if ok then
        Cards.Table:ApplySettings()
    end
    self:Refresh()
    Games.UI:Refresh()
end

function SettingsPage:Create(parent, layout)
    self.width = layout.width
    local settings = Cards.Store:GetTableSettings()
    self.settings = settings
    self.scaleSlider = Games.SettingsControls:Slider(
        parent,
        L.W_TABLE_SCALE,
        self.width,
        settings.scale,
        Cards.TABLE_SCALE_MIN,
        Cards.TABLE_SCALE_MAX,
        Cards.TABLE_SCALE_STEP,
        function(value)
            return L.W_PERCENT_F:format(value)
        end,
        function(value)
            if value ~= self.settings.scale then
                self:Save({ scale = value })
            end
        end
    )
    layout.Place(self.scaleSlider, parent, 0, SCALE_Y, self.width, self.scaleSlider.layoutHeight)
    self.fontRow = Games.SettingsControls:Font(parent, L.W_TABLE_FONT, self.width, function(value)
        if value ~= self.settings.font then
            self:Save({ font = value })
        end
    end)
    self.fontPicker = self.fontRow.Control
    layout.Place(self.fontRow, parent, 0, FONT_Y, self.width, self.fontRow.layoutHeight)
    layout.Label(parent, L.W_SHOW_HISTORY, 0, HISTORY_Y - 5, 104, 26)
    self.history = layout.Dropdown(parent, "", 104, HISTORY_Y, self.width - 104, function(_, root)
        local function IsSelected(value)
            return self.settings.showHistory == value
        end
        local function Select(value)
            if value ~= self.settings.showHistory then
                self:Save({ showHistory = value })
            end
        end
        root:CreateRadio(L.W_SHOW_HISTORY_ON, IsSelected, Select, true)
        root:CreateRadio(L.W_SHOW_HISTORY_OFF, IsSelected, Select, false)
    end)
    self:Refresh()
end

function SettingsPage:Refresh()
    if not self.scaleSlider then
        return
    end
    local settings = Cards.Store:GetTableSettings()
    local fontChanged = self.settings.font ~= settings.font or self.mediaRevision ~= Games.Media.revision
    self.settings = settings
    if self.scaleSlider.Slider.Slider:GetValue() ~= settings.scale then
        self.scaleSlider:SetValue(settings.scale)
    end
    if fontChanged then
        self.mediaRevision = Games.Media.revision
        self.fontPicker:SetSelection(settings.font)
    end
    self.history:SetDefaultText(self.settings.showHistory and L.W_SHOW_HISTORY_ON or L.W_SHOW_HISTORY_OFF)
    self.history:GenerateMenu()
end

function SettingsPage:CloseMenus()
    if self.fontPicker then
        self.fontPicker:CloseMenu()
    end
    if self.history then
        self.history:CloseMenu()
    end
end

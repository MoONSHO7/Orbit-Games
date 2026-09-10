local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L

local SCALE_Y = 0
local FONT_Y = -40
local SOUNDS_Y = -84
local LABEL_WIDTH = 104
local LABEL_HEIGHT = 26
local LABEL_Y_OFFSET = -5

local SettingsPage = {}
Quiz.SettingsPage = SettingsPage

function SettingsPage:Create(parent, layout)
    self.width = layout.width
    self.widgetSettings = Quiz.Store:GetWidgetSettings()
    self.scaleSlider = Games.SettingsControls:Slider(
        parent,
        L.W_WIDGET_SCALE,
        self.width,
        self.widgetSettings.scale,
        Quiz.WIDGET_SCALE_MIN,
        Quiz.WIDGET_SCALE_MAX,
        Quiz.WIDGET_SCALE_STEP,
        function(value)
            return L.W_WIDGET_SCALE_F:format(value)
        end,
        function(value)
            if value ~= self.widgetSettings.scale then
                self:SaveWidgetSettings({ scale = value })
            end
        end
    )
    self.scaleLabel = self.scaleSlider.Label
    layout.Place(self.scaleSlider, parent, 0, SCALE_Y, self.width, self.scaleSlider.layoutHeight)
    self.fontRow = Games.SettingsControls:Font(parent, L.W_WIDGET_FONT, self.width, function(value)
        self:SaveWidgetSettings({ font = value })
    end)
    self.fontPicker = self.fontRow.Control
    layout.Place(self.fontRow, parent, 0, FONT_Y, self.width, self.fontRow.layoutHeight)
    layout.Label(parent, L.W_SOUNDS, 0, SOUNDS_Y + LABEL_Y_OFFSET, LABEL_WIDTH, LABEL_HEIGHT)
    self.sounds = layout.Dropdown(parent, "", LABEL_WIDTH, SOUNDS_Y, self.width - LABEL_WIDTH, function(_, root)
        local function IsSelected(value)
            return self.soundsEnabled == value
        end
        local function Select(value)
            if value ~= self.soundsEnabled then
                self:SaveSoundsEnabled(value)
            end
        end
        root:CreateRadio(L.W_SOUNDS_ON, IsSelected, Select, true)
        root:CreateRadio(L.W_SOUNDS_OFF, IsSelected, Select, false)
    end)
    self:Refresh()
end

function SettingsPage:SaveWidgetSettings(settings)
    local ok, reason = Quiz.Store:SaveWidgetSettings(settings)
    Games.UI.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
    if ok then
        Quiz.Widget:ApplySettings()
    end
    self:Refresh()
    Games.UI:Refresh()
end

function SettingsPage:SaveSoundsEnabled(value)
    local ok, reason = Quiz.Store:SaveSoundsEnabled(value)
    Games.UI.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
    if ok then
        Quiz.StreakToasts:SetSoundsEnabled(Quiz.Store:GetSoundsEnabled())
    end
    self:Refresh()
end

function SettingsPage:Refresh()
    if not self.fontPicker then
        return
    end
    local settings = Quiz.Store:GetWidgetSettings()
    local fontChanged = self.widgetSettings.font ~= settings.font or self.widgetMediaRevision ~= Games.Media.revision
    self.widgetSettings = settings
    if self.scaleSlider.Slider.Slider:GetValue() ~= settings.scale then
        self.scaleSlider:SetValue(settings.scale)
    end
    self.soundsEnabled = Quiz.Store:GetSoundsEnabled()
    self.sounds:SetDefaultText(self.soundsEnabled and L.W_SOUNDS_ON or L.W_SOUNDS_OFF)
    self.sounds:GenerateMenu()
    if fontChanged then
        self.widgetMediaRevision = Games.Media.revision
        self.fontPicker:SetSelection(settings.font)
    end
end

function SettingsPage:CloseMenus()
    self.fontPicker:CloseMenu()
    self.sounds:CloseMenu()
end

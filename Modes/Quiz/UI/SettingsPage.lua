local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L

local SCALE_Y = 0
local FONT_Y = -40
local VOLUME_Y = -80

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
    self.soundVolume = Quiz.Store:GetSoundVolume()
    self.volumeSlider = Games.SettingsControls:Slider(
        parent,
        L.W_SOUND_VOLUME,
        self.width,
        self.soundVolume,
        Quiz.SOUND_VOLUME_MIN,
        Quiz.SOUND_VOLUME_MAX,
        Quiz.SOUND_VOLUME_STEP,
        function(value)
            return L.W_SOUND_VOLUME_F:format(value)
        end,
        function(value)
            if value ~= self.soundVolume then
                self:SaveSoundVolume(value)
            end
        end
    )
    layout.Place(self.volumeSlider, parent, 0, VOLUME_Y, self.width, self.volumeSlider.layoutHeight)
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

function SettingsPage:SaveSoundVolume(value)
    local ok, reason = Quiz.Store:SaveSoundVolume(value)
    Games.UI.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
    if ok then
        Quiz.StreakToasts:SetVolume(Quiz.Store:GetSoundVolume())
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
    self.soundVolume = Quiz.Store:GetSoundVolume()
    if self.volumeSlider.Slider.Slider:GetValue() ~= self.soundVolume then
        self.volumeSlider:SetValue(self.soundVolume)
    end
    if fontChanged then
        self.widgetMediaRevision = Games.Media.revision
        self.fontPicker:SetSelection(settings.font)
    end
end

function SettingsPage:CloseMenus()
    self.fontPicker:CloseMenu()
end

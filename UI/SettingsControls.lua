local _, Quiz = ...
local LABEL_WIDTH = 100
local LABEL_GAP_PIXELS = 3
local VALUE_WIDTH = 65
local VALUE_INSET_PIXELS = 3
local SLIDER_HEIGHT = 32
local PICKER_ROW_HEIGHT = 26
local PICKER_HEIGHT = 24
local LABEL_FONT = "GameFontHighlight"
local VALUE_FONT = "GameFontHighlightSmall"
local VALUE_COLOR = { 1, 0.82, 0, 1 }

Quiz.SettingsControls = { rows = {} }
local Settings = Quiz.SettingsControls

local function LayoutRow(row)
    local scale = row:GetEffectiveScale()
    local gap = PixelUtil.GetNearestPixelSize(0, scale, LABEL_GAP_PIXELS)
    local valueWidth = PixelUtil.GetNearestPixelSize(VALUE_WIDTH, scale)
    row.Label:ClearAllPoints()
    PixelUtil.SetPoint(row.Label, "TOPLEFT", row, "TOPLEFT", 0, 0)
    PixelUtil.SetSize(row.Label, LABEL_WIDTH, row:GetHeight())
    local control = row.Control or row.Slider
    local left = row.Label:GetWidth() + gap
    local height = row.Control and PICKER_HEIGHT or SLIDER_HEIGHT
    PixelUtil.SetSize(control, row:GetWidth() - left - valueWidth, height)
    control:ClearAllPoints()
    PixelUtil.SetPoint(control, "TOPLEFT", row, "TOPLEFT", left, -(row:GetHeight() - control:GetHeight()) / 2)
    if row.Value then
        local inset = PixelUtil.GetNearestPixelSize(0, scale, VALUE_INSET_PIXELS)
        row.Value:ClearAllPoints()
        PixelUtil.SetPoint(row.Value, "TOPRIGHT", row, "TOPRIGHT", -inset, 0)
        PixelUtil.SetSize(row.Value, valueWidth - inset, row:GetHeight())
    else
        row.Control:RefreshLayout()
    end
end

local function ConfigureRow(row, label, width, height)
    row.layoutHeight = height
    PixelUtil.SetSize(row, width, height)
    row.Label:SetFontObject(LABEL_FONT)
    row.Label:SetText(label)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetJustifyV("MIDDLE")
    row.Label:SetWordWrap(false)
    Settings.rows[row] = true
    row:SetScript("OnSizeChanged", LayoutRow)
    LayoutRow(row)
    row:Show()
end

function Settings:Slider(parent, label, width, value, minimum, maximum, step, formatter, action)
    local row = CreateFrame("Frame", nil, parent, "EditModeSettingSliderTemplate")
    -- The template captures Blizzard dialog callbacks during OnLoad; this independent row must detach those handles.
    row.cbrHandles:Unregister()
    row.Value = row:CreateFontString(nil, "OVERLAY", VALUE_FONT)
    row.Value:SetJustifyH("RIGHT")
    row.Value:SetJustifyV("MIDDLE")
    row.Value:SetTextColor(unpack(VALUE_COLOR))
    row.Value:SetWordWrap(false)
    local slider = row.Slider
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, newValue)
        row.Value:SetText(formatter(newValue))
        if not row.loadingValue then
            action(newValue)
        end
    end, row)
    row.loadingValue = true
    slider:Init(value, minimum, maximum, (maximum - minimum) / step, {})
    row.loadingValue = nil
    row.Value:SetText(formatter(value))
    slider.Slider:SetNarrationLabelRegion(row.Label)
    slider.Slider:SetNarrationValueFormatter(function()
        return row.Value:GetText()
    end)
    function row:SetValue(newValue)
        self.loadingValue = true
        if slider.Slider:GetValue() ~= newValue then
            slider:SetValue(newValue)
        end
        self.Value:SetText(formatter(newValue))
        self.loadingValue = nil
    end
    ConfigureRow(row, label, width, SLIDER_HEIGHT)
    return row
end

function Settings:Font(parent, label, width, action)
    local row = CreateFrame("Frame", nil, parent)
    row.Label = row:CreateFontString(nil, "ARTWORK", LABEL_FONT)
    row.Control = Quiz.FontPicker:Create(row, width - LABEL_WIDTH - VALUE_WIDTH, action)
    ConfigureRow(row, label, width, PICKER_ROW_HEIGHT)
    return row
end

function Settings:RefreshScale()
    for row in pairs(self.rows) do
        LayoutRow(row)
    end
end

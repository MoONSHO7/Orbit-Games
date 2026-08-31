local _, Quiz = ...
local L = Quiz.L
local Controls = Quiz.Controls
local HEIGHT = 24
local PREVIEW_SIZE = 12
local FONT_OBJECT = "GameFontHighlight"
local ARROW_ATLAS = "common-dropdown-icon-next"
local ARROW_SIZE = 10
local ARROW_INSET_PIXELS = 8
local TEXT_INSET_PIXELS = 6
local TEXT_GAP_PIXELS = 3
local ARROW_DOWN, ARROW_UP = -math.pi / 2, math.pi / 2
local COLORS = {
    background = { 0.08, 0.08, 0.1, 1 },
    border = { 0, 0, 0, 1 },
    hover = { 0.3, 0.3, 0.3, 1 },
    open = { 1, 0.82, 0, 0.65 },
    accent = { 1, 0.82, 0, 1 },
    text = { 1, 1, 1, 1 },
}

Quiz.FontPicker = {}
local FontPicker = Quiz.FontPicker

local function RefreshState(control)
    Controls:Outline(control, control.isOpen and COLORS.open or control.isHovered and COLORS.hover or COLORS.border)
    control.Arrow:SetRotation(control.isOpen and ARROW_UP or ARROW_DOWN)
    control.Arrow:SetVertexColor(unpack(control.isOpen and COLORS.accent or COLORS.text))
end

function FontPicker:PaintText(label, name, size)
    label:SetFontObject(FONT_OBJECT)
    local nativePath = label:GetFont()
    local path = Quiz.Media:ResolveFont(name)
    local available, applied = name == "" or path ~= nil, false
    if path then
        -- Registered font paths belong to other addons and can still fail native asset loading.
        local ok, success = pcall(label.SetFont, label, path, size, "")
        applied = ok and success
        available = applied
    end
    if not applied then
        label:SetFontObject(FONT_OBJECT)
        label:SetFont(nativePath, size, "")
    end
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetTextColor(unpack(COLORS.text))
    label:SetText(
        name == "" and L.W_WIDGET_FONT_DEFAULT or available and name or L.W_WIDGET_FONT_UNAVAILABLE_F:format(name)
    )
    return available
end

function FontPicker:Create(parent, width, onChange)
    local control = CreateFrame("Button", nil, parent)
    PixelUtil.SetSize(control, width, HEIGHT)
    Controls:Skin(control, COLORS.background)
    control.selectedName = ""
    control.Text = control:CreateFontString(nil, "OVERLAY", FONT_OBJECT)
    control.Arrow = control:CreateTexture(nil, "OVERLAY")
    control.Arrow:SetAtlas(ARROW_ATLAS)

    function control:CloseMenu()
        if self.Popup then
            self.Popup:Hide()
        end
    end

    function control:Refresh()
        FontPicker:PaintText(self.Text, self.selectedName, PREVIEW_SIZE)
        if self.Popup and self.Popup:IsShown() then
            self.Popup:Refresh()
        end
    end

    function control:SetSelection(name)
        self.selectedName = name
        self:Refresh()
    end

    function control:RefreshLayout()
        self:CloseMenu()
        PixelUtil.SetHeight(self, HEIGHT)
        Controls:Skin(self, COLORS.background)
        local scale = self:GetEffectiveScale()
        local arrowInset = PixelUtil.GetNearestPixelSize(0, scale, ARROW_INSET_PIXELS)
        local textInset = PixelUtil.GetNearestPixelSize(0, scale, TEXT_INSET_PIXELS)
        local gap = PixelUtil.GetNearestPixelSize(0, scale, TEXT_GAP_PIXELS)
        PixelUtil.SetSize(self.Arrow, ARROW_SIZE, ARROW_SIZE)
        self.Arrow:ClearAllPoints()
        PixelUtil.SetPoint(
            self.Arrow,
            "TOPRIGHT",
            self,
            "TOPRIGHT",
            -arrowInset,
            -(self:GetHeight() - self.Arrow:GetHeight()) / 2
        )
        self.Text:ClearAllPoints()
        PixelUtil.SetPoint(self.Text, "TOPLEFT", self, "TOPLEFT", textInset, 0)
        PixelUtil.SetPoint(self.Text, "BOTTOMRIGHT", self, "BOTTOMRIGHT", -arrowInset - self.Arrow:GetWidth() - gap, 0)
        RefreshState(self)
    end

    control:SetScript("OnClick", function(self)
        if self.Popup and self.Popup:IsShown() then
            self:CloseMenu()
            return
        end
        if not self.Popup then
            self.Popup = Quiz.FontMenu:Create(self, function(name)
                self:SetSelection(name)
                onChange(name)
            end)
            self.Popup:HookScript("OnShow", function()
                self.isOpen = true
                RefreshState(self)
            end)
            self.Popup:HookScript("OnHide", function()
                self.isOpen = false
                RefreshState(self)
            end)
        end
        self.Popup:Open()
    end)
    control:SetScript("OnEnter", function(self)
        self.isHovered = true
        RefreshState(self)
    end)
    control:SetScript("OnLeave", function(self)
        self.isHovered = false
        RefreshState(self)
    end)
    control:SetScript("OnHide", function(self)
        self.isHovered = false
        self:CloseMenu()
        RefreshState(self)
    end)
    control:SetScript("OnDisable", function(self)
        self:CloseMenu()
    end)
    control:RefreshLayout()
    control:Refresh()
    return control
end

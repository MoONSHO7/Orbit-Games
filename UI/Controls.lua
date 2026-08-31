local _, Quiz = ...

local TEXT_INSET = 9
local EDGE_PIXELS = 1
local SCROLLBAR_OFFSET = 6
local INPUT_INSET = 5
local CONTAINER_ATLAS = "housing-basic-container"
local DIVIDER_COLOR = { 0.3, 0.3, 0.3 }
local DIVIDER_PIXELS = 1
local INPUT_BACKDROP = {
    bgFile = 130937,
    edgeFile = 137057,
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local TAB_HEIGHT = 24
local TAB_TEXT_PADDING = 12
local TAB_HIGHLIGHT_ATLAS = "housing-basic-panel-gradient-header-bg"
local TAB_HIGHLIGHT_HEIGHT = 21
local TAB_HIGHLIGHT_WIDTH_SCALE = 1.84
local COLORS = {
    border = { 0, 0, 0, 1 },
    selected = { 1, 0.82, 0, 1 },
    text = { 1, 1, 1, 1 },
    muted = { 0.6, 0.6, 0.6, 1 },
}

Quiz.Controls = { pixelSkins = {}, scrolls = {}, tabs = {}, buttons = {}, edits = {}, dividers = {} }
local Controls = Quiz.Controls

local function Pixels(frame, count)
    return PixelUtil.GetNearestPixelSize(0, frame:GetEffectiveScale(), count)
end

local function LayoutDivider(divider, width)
    PixelUtil.SetWidth(divider, width)
    PixelUtil.SetHeight(divider, 0, DIVIDER_PIXELS)
    PixelUtil.SetWidth(divider.Left, divider:GetWidth() / 2)
end

local function LayoutTabHighlight(button)
    PixelUtil.SetSize(button.highlight, button:GetWidth() * TAB_HIGHLIGHT_WIDTH_SCALE, TAB_HIGHLIGHT_HEIGHT)
    local offset = (button:GetWidth() - button.highlight:GetWidth()) / 2
    PixelUtil.SetPoint(button.highlight, "BOTTOMLEFT", button, "BOTTOMLEFT", offset, -Pixels(button, EDGE_PIXELS))
end

local function LayoutButtonText(button)
    local inset = button.style == "tab" and TAB_TEXT_PADDING / 2 or TEXT_INSET
    button.Text:ClearAllPoints()
    PixelUtil.SetPoint(button.Text, "TOPLEFT", button, "TOPLEFT", inset, 0)
    PixelUtil.SetPoint(button.Text, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, 0)
end

local function LayoutEditText(edit)
    local inset = PixelUtil.GetNearestPixelSize(INPUT_INSET, edit:GetEffectiveScale())
    edit:SetTextInsets(inset, inset, inset, inset)
end

local function Texture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(unpack(color))
    return texture
end

local function ResizeEdges(frame)
    local scale = frame:GetEffectiveScale()
    local pixelFactor = PixelUtil.GetPixelToUIUnitFactor()
    if frame.skinScale == scale and frame.skinPixelFactor == pixelFactor then
        return
    end
    frame.skinScale, frame.skinPixelFactor = scale, pixelFactor
    local edge = PixelUtil.GetNearestPixelSize(0, scale, EDGE_PIXELS)
    local top, bottom, left, right = unpack(frame.edges)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(edge)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(edge)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(edge)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(edge)
end

function Controls:Skin(frame, background)
    if not frame.edges then
        frame.edges = {}
        for index = 1, 4 do
            frame.edges[index] = Texture(frame, "BORDER", COLORS.border)
        end
        self.pixelSkins[frame] = true
    end
    if background and not frame.background then
        frame.background = Texture(frame, "BACKGROUND", background)
        frame.background:SetAllPoints(frame)
    end
    ResizeEdges(frame)
end

function Controls:Outline(frame, color)
    self:Skin(frame)
    for _, edge in ipairs(frame.edges) do
        edge:SetColorTexture(unpack(color))
    end
end

function Controls:Label(parent, text, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetNonSpaceWrap(true)
    label:SetText(text or "")
    return label
end

function Controls:Panel(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    -- SetAtlas loads the housing container's native shader NineSlice data; a flat wash would replace its art.
    background:SetAtlas(CONTAINER_ATLAS)
    background:SetAllPoints(frame)
    frame.Chrome = { Background = background }
    return frame
end

function Controls:Divider(parent, width)
    local divider = CreateFrame("Frame", nil, parent)
    local r, g, b = unpack(DIVIDER_COLOR)
    local left = divider:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(1, 1, 1, 1)
    left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))
    left:SetPoint("TOPLEFT", divider, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", divider, "BOTTOMLEFT", 0, 0)
    local right = divider:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(1, 1, 1, 1)
    right:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0))
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", divider, "BOTTOMRIGHT", 0, 0)
    divider.Left, divider.Right = left, right
    self.dividers[divider] = width
    LayoutDivider(divider, width)
    return divider
end

function Controls:PaintButton(button)
    if button.style == "tab" then
        button.highlight:SetShown(button.selected == true)
        button.Text:SetTextColor(
            unpack(button.selected and COLORS.selected or button.hovered and COLORS.text or COLORS.muted)
        )
    else
        local color = button.selected and COLORS.selected
        button.Accent:SetShown(button.selected == true)
        if color then
            self:Outline(button.Accent, color)
        end
        button.Text:SetTextColor(
            unpack(
                color or (button.controlEnabled and (button.hovered and COLORS.text or COLORS.selected)) or COLORS.muted
            )
        )
    end
end

function Controls:SetButtonState(button, enabled, selected)
    button.controlEnabled, button.selected = enabled, selected
    button:SetEnabled(enabled and not (button.style == "tab" and selected))
    self:PaintButton(button)
end

function Controls:Button(parent, text, width, height, action)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    PixelUtil.SetSize(button, width, height)
    button.Text = button:GetFontString()
    LayoutButtonText(button)
    self.buttons[button] = true
    button.Text:SetJustifyH("CENTER")
    button.Text:SetJustifyV("MIDDLE")
    button.Text:SetWordWrap(true)
    button.Text:SetNonSpaceWrap(true)
    button:SetText(text)
    button.Accent = CreateFrame("Frame", nil, button)
    button.Accent:SetAllPoints(button)
    button.Accent:EnableMouse(false)
    button.Accent:Hide()
    button.controlEnabled = true
    button:SetScript("OnClick", action)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        Controls:PaintButton(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        Controls:PaintButton(self)
    end)
    return button
end

function Controls:Tab(parent, text, action)
    local button = CreateFrame("Button", nil, parent)
    button.style, button.controlEnabled = "tab", true
    button.Text = self:Label(button, text, "GameFontNormal")
    local width = button.Text:GetStringWidth() + TAB_TEXT_PADDING
    LayoutButtonText(button)
    button.Text:SetJustifyH("CENTER")
    button.Text:SetJustifyV("MIDDLE")
    button.Text:SetWordWrap(false)
    button:SetFontString(button.Text)
    PixelUtil.SetSize(button, width, TAB_HEIGHT)
    button.highlight = button:CreateTexture(nil, "BACKGROUND")
    button.highlight:SetAtlas(TAB_HIGHLIGHT_ATLAS)
    LayoutTabHighlight(button)
    self.tabs[button] = true
    button.highlight:Hide()
    button:SetScript("OnClick", action)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        Controls:PaintButton(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        Controls:PaintButton(self)
    end)
    return button
end

function Controls:Dropdown(parent, text, width, generator)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    PixelUtil.SetWidth(dropdown, width)
    dropdown:SetDefaultText(text)
    dropdown:SetupMenu(generator)
    dropdown:HookScript("OnHide", function(self)
        self:CloseMenu()
    end)
    dropdown:HookScript("OnDisable", function(self)
        self:CloseMenu()
    end)
    return dropdown
end

function Controls:StyleInput(frame, alpha)
    frame:SetBackdrop(INPUT_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

function Controls:Edit(parent, width, height, maxLetters)
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    PixelUtil.SetSize(edit, width, height)
    self:StyleInput(edit, 0.5)
    edit:SetFontObject("ChatFontNormal")
    LayoutEditText(edit)
    self.edits[edit] = true
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(maxLetters)
    edit:SetNumeric(false)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    return edit
end

function Controls:Scroll(parent, width, height, scrollbarOptions)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    PixelUtil.SetSize(scroll, width, height)
    scroll:SetClipsChildren(true)
    local content = CreateFrame("Frame", nil, scroll)
    PixelUtil.SetSize(content, width, height)
    scroll:SetScrollChild(content)
    scroll.ScrollBar = Quiz.ScrollBar:Attach(scroll, scrollbarOptions or { rightOffset = SCROLLBAR_OFFSET })
    self.scrolls[scroll] = true
    return scroll, content
end

function Controls:RefreshScale()
    for frame in pairs(self.pixelSkins) do
        frame.skinScale = nil
        ResizeEdges(frame)
    end
    for scroll in pairs(self.scrolls) do
        scroll.ScrollBar:Refresh()
    end
    for button in pairs(self.buttons) do
        LayoutButtonText(button)
    end
    for button in pairs(self.tabs) do
        LayoutButtonText(button)
        LayoutTabHighlight(button)
    end
    for edit in pairs(self.edits) do
        LayoutEditText(edit)
    end
    for divider, width in pairs(self.dividers) do
        LayoutDivider(divider, width)
    end
end

function Controls:SetMuted(label)
    label:SetTextColor(unpack(COLORS.muted))
end

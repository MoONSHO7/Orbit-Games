local _, Quiz = ...
local L = Quiz.L
local Controls = Quiz.Controls
local WIDTH = 230
local ROW_HEIGHT = 24
local ROW_FONT_SIZE = 13
local MAX_VISIBLE_ROWS = 10
local SEARCH_HEIGHT = 26
local SEARCH_MAX_LETTERS = 128
local PAD_PIXELS = 5
local SCREEN_MARGIN_PIXELS = 5
local OWNER_GAP_PIXELS = 2
local ROW_INSET_PIXELS = 2
local ROW_TEXT_INSET_PIXELS = 10
local ROW_VERTICAL_INSET_PIXELS = 1
local SEARCH_LEFT_PIXELS = 8
local SEARCH_RIGHT_PIXELS = 6
local SEARCH_VERTICAL_PIXELS = 1
local SEARCH_TEXT_LEFT = 16
local SEARCH_TEXT_RIGHT = 20
local SEARCH_ICON_SIZE = 10
local SEARCH_ICON_OFFSET = 1
local CLEAR_SIZE = 17
local CLEAR_INSET = 3
local CLEAR_PRESSED_INSET = 4
local SEARCH_ALPHA = 0.6
local POPUP_STRATA = "FULLSCREEN_DIALOG"
local LEVEL_OFFSET = 1
local COLORS = {
    background = { 0.06, 0.06, 0.06, 0.98 },
    border = { 0.3, 0.3, 0.3, 1 },
    selected = { 1, 0.82, 0, 0.11 },
    hover = { 1, 1, 1, 0.07 },
    unavailable = { 1, 0.5, 0.5, 1 },
}

Quiz.FontMenu = { nextID = 0 }
local FontMenu = Quiz.FontMenu

local function Pixels(frame, count)
    return PixelUtil.GetNearestPixelSize(0, frame:GetEffectiveScale(), count)
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function FloorSize(value, scale)
    local snapped = PixelUtil.GetNearestPixelSize(value, scale)
    if snapped > value then
        snapped = snapped - PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    return snapped
end

local function LayoutClearIcon(button, pressed)
    local inset = pressed and button:IsEnabled() and CLEAR_PRESSED_INSET or CLEAR_INSET
    button.Icon:ClearAllPoints()
    PixelUtil.SetPoint(button.Icon, "TOPLEFT", button, "TOPLEFT", inset, -inset)
end

local function LayoutSearch(search)
    local scale = search:GetEffectiveScale()
    local left = PixelUtil.GetNearestPixelSize(SEARCH_TEXT_LEFT, scale)
    local right = PixelUtil.GetNearestPixelSize(SEARCH_TEXT_RIGHT, scale)
    search:SetTextInsets(left, right, 0, 0)
    search.Instructions:ClearAllPoints()
    search.Instructions:SetPoint("TOPLEFT", search, "TOPLEFT", left, 0)
    search.Instructions:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -right, 0)
    PixelUtil.SetSize(search.searchIcon, SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    search.searchIcon:ClearAllPoints()
    PixelUtil.SetPoint(
        search.searchIcon,
        "TOPLEFT",
        search,
        "TOPLEFT",
        SEARCH_ICON_OFFSET,
        -(search:GetHeight() - search.searchIcon:GetHeight()) / 2 - SEARCH_ICON_OFFSET
    )
    local clear = search.clearButton
    PixelUtil.SetSize(clear, CLEAR_SIZE, CLEAR_SIZE)
    clear:ClearAllPoints()
    PixelUtil.SetPoint(
        clear,
        "TOPRIGHT",
        search,
        "TOPRIGHT",
        -CLEAR_INSET,
        -(search:GetHeight() - clear:GetHeight()) / 2
    )
    PixelUtil.SetSize(clear.Icon, SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
    LayoutClearIcon(clear, false)
end

local function LayoutRow(row, slot, popup)
    row:ClearAllPoints()
    PixelUtil.SetPoint(row, "TOPLEFT", popup.Content, "TOPLEFT", 0, -(slot - 1) * popup.rowHeight)
    row:SetSize(popup.Content:GetWidth(), popup.rowHeight)
    local inset, vertical = Pixels(row, ROW_INSET_PIXELS), Pixels(row, ROW_VERTICAL_INSET_PIXELS)
    for _, texture in ipairs({ row.SelectedBackground, row.Hover }) do
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -vertical)
        texture:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, vertical)
    end
    local textInset = Pixels(row, ROW_TEXT_INSET_PIXELS)
    row.Text:ClearAllPoints()
    row.Text:SetPoint("TOPLEFT", row, "TOPLEFT", textInset, 0)
    row.Text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -textInset, 0)
end

local function CreateRow(popup)
    local row = CreateFrame("Button", nil, popup.Content)
    row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.SelectedBackground = row:CreateTexture(nil, "BACKGROUND")
    row.SelectedBackground:SetColorTexture(unpack(COLORS.selected))
    row.Hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.Hover:SetColorTexture(unpack(COLORS.hover))
    row:SetScript("OnClick", function(self)
        if not self:IsEnabled() or self.value == nil then
            return
        end
        local name = self.value
        if name ~= "" and not Quiz.Media:ResolveFont(name) then
            popup:Refresh()
            return
        end
        popup:Hide()
        popup.onSelect(name)
    end)
    return row
end

local function RenderRows(popup)
    for slot = 1, popup.visibleSlots do
        local row = popup.rows[slot]
        if not row then
            row = CreateRow(popup)
            popup.rows[slot] = row
        end
        LayoutRow(row, slot, popup)
        local item = popup.filtered[popup.scrollOffset + slot]
        row.value = item and item.name or nil
        if item then
            local available = Quiz.FontPicker:PaintText(row.Text, item.name, ROW_FONT_SIZE)
            row:SetEnabled(available and not item.unavailable)
            row.SelectedBackground:SetShown(item.name == popup.owner.selectedName)
            if available and not item.unavailable then
                local color = item.name == popup.owner.selectedName and 1 or 0.9
                row.Text:SetTextColor(color, color, color, 1)
            else
                row.Text:SetTextColor(unpack(COLORS.unavailable))
            end
            row:Show()
        else
            row:Hide()
        end
    end
    for slot = popup.visibleSlots + 1, #popup.rows do
        popup.rows[slot].value = nil
        popup.rows[slot]:Hide()
    end
    popup.Empty:SetShown(#popup.filtered == 0)
end

local function RebuildItems(popup)
    popup.allItems = { { name = "", label = L.W_WIDGET_FONT_DEFAULT } }
    local selected = popup.owner.selectedName
    if selected ~= "" and not Quiz.Media:ResolveFont(selected) then
        popup.allItems[#popup.allItems + 1] = {
            name = selected,
            label = L.W_WIDGET_FONT_UNAVAILABLE_F:format(selected),
            unavailable = true,
        }
    end
    for _, name in ipairs(Quiz.Media:GetFontNames()) do
        popup.allItems[#popup.allItems + 1] = { name = name, label = name }
    end
    local width = math.max(WIDTH, popup.owner:GetWidth())
    for _, item in ipairs(popup.allItems) do
        popup.Measure:SetText(item.label)
        width =
            math.max(width, popup.Measure:GetStringWidth() + Pixels(popup, (PAD_PIXELS + ROW_TEXT_INSET_PIXELS) * 2))
    end
    popup.requiredWidth = width
end

local function FilterItems(popup, resetScroll)
    local query = string.lower(popup.Search:GetText())
    popup.filtered = {}
    for _, item in ipairs(popup.allItems) do
        if query == "" or string.find(string.lower(item.label), query, 1, true) then
            popup.filtered[#popup.filtered + 1] = item
        end
    end
    if resetScroll then
        popup.scrollOffset = 0
    end
    popup:RefreshLayout()
end

local function Scroll(popup, delta)
    local steps = delta > 0 and math.ceil(delta) or math.floor(delta)
    local offset = Clamp(popup.scrollOffset - steps, 0, math.max(0, #popup.filtered - popup.visibleSlots))
    if offset ~= popup.scrollOffset then
        popup.scrollOffset = offset
        RenderRows(popup)
    end
end

function FontMenu:Create(owner, onSelect)
    self.nextID = self.nextID + 1
    local name = "OrbitQuizFontMenu" .. self.nextID
    local popup = CreateFrame("Frame", name, UIParent)
    popup:Hide()
    popup:SetFrameStrata(POPUP_STRATA)
    popup:SetFrameLevel(owner:GetFrameLevel() + LEVEL_OFFSET)
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:SetClipsChildren(true)
    popup.owner, popup.onSelect = owner, onSelect
    popup.rows, popup.allItems, popup.filtered = {}, {}, {}
    popup.scrollOffset, popup.visibleSlots = 0, MAX_VISIBLE_ROWS
    Controls:Skin(popup, COLORS.background)
    Controls:Outline(popup, COLORS.border)
    UISpecialFrames[#UISpecialFrames + 1] = name

    popup.SearchStrip = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    Controls:StyleInput(popup.SearchStrip, SEARCH_ALPHA)
    local search = CreateFrame("EditBox", nil, popup.SearchStrip, "SearchBoxTemplate")
    popup.Search = search
    search:SetAutoFocus(false)
    search:SetMaxLetters(SEARCH_MAX_LETTERS)
    search:SetFontObject("ChatFontNormal")
    search.Instructions:SetText(L.W_WIDGET_FONT_SEARCH)
    search.Instructions:SetWordWrap(false)
    search.Left:Hide()
    search.Middle:Hide()
    search.Right:Hide()
    search:HookScript("OnTextChanged", function()
        if not popup.loadingQuery then
            FilterItems(popup, true)
        end
    end)
    search:HookScript("OnEscapePressed", function()
        popup:Hide()
    end)
    -- Retain search focus after Enter/clear so Escape dismisses this menu before the settings window.
    local function KeepSearchFocus()
        if popup:IsShown() then
            search:SetFocus()
        end
    end
    search:HookScript("OnEnterPressed", KeepSearchFocus)
    search.clearButton:HookScript("OnClick", KeepSearchFocus)
    search.clearButton:HookScript("OnMouseDown", function(self)
        LayoutClearIcon(self, true)
    end)
    search.clearButton:HookScript("OnMouseUp", function(self)
        LayoutClearIcon(self, false)
    end)
    search:EnableMouseWheel(true)
    search:SetScript("OnMouseWheel", function(_, delta)
        Scroll(popup, delta)
    end)

    popup.Content = CreateFrame("Frame", nil, popup)
    popup.Empty = popup.Content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.Empty:SetText(L.W_WIDGET_FONT_NO_RESULTS)
    popup.Empty:SetJustifyH("LEFT")
    popup.Empty:SetWordWrap(false)
    popup.Empty:Hide()
    popup.Measure = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local nativePath = popup.Measure:GetFont()
    popup.Measure:SetFont(nativePath, ROW_FONT_SIZE, "")
    popup.Measure:SetWordWrap(false)
    popup.Measure:Hide()

    function popup:RefreshLayout()
        self:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        local scale = self:GetEffectiveScale()
        local rootLeft, rootBottom, rootWidth, rootHeight = UIParent:GetScaledRect()
        local ownerLeft, ownerBottom, _, ownerHeight = owner:GetScaledRect()
        if not rootLeft or not ownerLeft or rootWidth <= 0 or rootHeight <= 0 then
            self:Hide()
            return false
        end
        local screenWidth, screenHeight = FloorSize(rootWidth / scale, scale), FloorSize(rootHeight / scale, scale)
        local margin = Pixels(self, SCREEN_MARGIN_PIXELS)
        local pad, gap = Pixels(self, PAD_PIXELS), Pixels(self, OWNER_GAP_PIXELS)
        local left, bottom = (ownerLeft - rootLeft) / scale, (ownerBottom - rootBottom) / scale
        local top = bottom + ownerHeight / scale
        self.rowHeight = PixelUtil.GetNearestPixelSize(ROW_HEIGHT, scale)
        local searchHeight = PixelUtil.GetNearestPixelSize(SEARCH_HEIGHT, scale)
        local headerHeight = searchHeight + pad * 3
        if screenHeight < headerHeight + self.rowHeight + margin * 2 or screenWidth < WIDTH / 2 then
            self:Hide()
            return false
        end
        local desiredHeight = math.max(1, math.min(MAX_VISIBLE_ROWS, #self.filtered)) * self.rowHeight + headerHeight
        local below, above = bottom - margin - gap, screenHeight - margin - top - gap
        local down = below >= desiredHeight or below >= above
        local room = math.max(0, down and below or above)
        self.visibleSlots = Clamp(math.floor((room - headerHeight) / self.rowHeight), 1, MAX_VISIBLE_ROWS)
        self.scrollOffset = Clamp(self.scrollOffset, 0, math.max(0, #self.filtered - self.visibleSlots))
        local rowCount = math.max(1, math.min(self.visibleSlots, #self.filtered))
        local height = headerHeight + rowCount * self.rowHeight
        local width =
            math.min(PixelUtil.GetNearestPixelSize(self.requiredWidth or WIDTH, scale), screenWidth - margin * 2)
        self:SetSize(width, height)
        left = Clamp(left, margin, screenWidth - margin - width)
        bottom = Clamp(down and bottom - gap - height or top + gap, margin, screenHeight - margin - height)
        self:ClearAllPoints()
        PixelUtil.SetPoint(self, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        Controls:Outline(self, COLORS.border)
        self.SearchStrip:ClearAllPoints()
        self.SearchStrip:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -pad)
        self.SearchStrip:SetSize(width - pad * 2, searchHeight)
        local searchVertical = Pixels(search, SEARCH_VERTICAL_PIXELS)
        search:ClearAllPoints()
        search:SetPoint("TOPLEFT", self.SearchStrip, "TOPLEFT", Pixels(search, SEARCH_LEFT_PIXELS), -searchVertical)
        search:SetPoint(
            "BOTTOMRIGHT",
            self.SearchStrip,
            "BOTTOMRIGHT",
            -Pixels(search, SEARCH_RIGHT_PIXELS),
            searchVertical
        )
        LayoutSearch(search)
        self.Content:ClearAllPoints()
        self.Content:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -(searchHeight + pad * 2))
        self.Content:SetSize(width - pad * 2, rowCount * self.rowHeight)
        self.Empty:ClearAllPoints()
        self.Empty:SetPoint("TOPLEFT", self.Content, "TOPLEFT", Pixels(self, ROW_TEXT_INSET_PIXELS), 0)
        self.Empty:SetPoint("BOTTOMRIGHT", self.Content, "BOTTOMRIGHT", -Pixels(self, ROW_TEXT_INSET_PIXELS), 0)
        RenderRows(self)
        return true
    end

    function popup:Refresh()
        self:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        RebuildItems(self)
        FilterItems(self, false)
    end

    function popup:Open()
        if not owner:IsVisible() or not owner:IsEnabled() then
            return
        end
        self.loadingQuery = true
        search:SetText("")
        self.loadingQuery = nil
        self.scrollOffset = 0
        self:Refresh()
        for index, item in ipairs(self.filtered) do
            if item.name == owner.selectedName then
                self.scrollOffset = Clamp(
                    index - math.floor(self.visibleSlots / 2) - 1,
                    0,
                    math.max(0, #self.filtered - self.visibleSlots)
                )
                break
            end
        end
        if self:RefreshLayout() then
            self:Show()
            search:SetFocus()
        end
    end

    popup:SetScript("OnMouseWheel", Scroll)
    popup:SetScript("OnEvent", function(self, event)
        if event ~= "GLOBAL_MOUSE_DOWN" or not (self:IsMouseOver() or owner:IsMouseOver()) then
            self:Hide()
        end
    end)
    popup:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        self:RegisterEvent("UI_SCALE_CHANGED")
    end)
    popup:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        self:UnregisterEvent("UI_SCALE_CHANGED")
        search:ClearFocus()
    end)
    return popup
end

local _, Games = ...
local Cards = Games.Cards
local L = Cards.L
local Controls = Games.Controls

local HELP_Y = 0
local HELP_HEIGHT = 40
local SCROLL_Y = -48
local HEADER_HEIGHT = 28
local DETAILS_HEIGHT = 18
local ROW_PADDING = 8
local ROW_GAP = 8

Cards.ResultsPage = { rows = {} }
local ResultsPage = Cards.ResultsPage

local function RoundUp(value, scale)
    local snapped = PixelUtil.GetNearestPixelSize(value, scale)
    if snapped < value then
        snapped = snapped + PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    return snapped
end

local function ResetRow(_, row)
    row:Hide()
    row:ClearAllPoints()
    if not row.Title then
        return
    end
    row.kind = nil
    row.Title:SetText("")
    row.Details:SetText("")
    row.Details:Hide()
    row.Divider:Hide()
end

local function SettlementDescriptors()
    local descriptors = {}
    local settlements = Cards.Store:GetSettlements()
    for settlementIndex = #settlements, 1, -1 do
        local settlement = settlements[settlementIndex]
        local timestamp = date and date("%Y-%m-%d %H:%M", settlement.endedAt) or tostring(settlement.endedAt)
        local variant = Cards.Variants:Get(settlement.variantId)
        descriptors[#descriptors + 1] = {
            kind = "heading",
            title = L.W_RESULTS_SESSION_F:format(
                timestamp,
                variant and variant.title or settlement.variantId,
                #settlement.players
            ),
        }
        for _, player in ipairs(settlement.players) do
            descriptors[#descriptors + 1] = {
                kind = "player",
                title = player.name,
                details = L.W_RESULTS_BALANCE_F:format(
                    Cards.Gold:Format(player.buyIn + player.rebuy),
                    Cards.Gold:Format(player.finalStack),
                    Cards.Gold:FormatSigned(player.net)
                ),
            }
        end
    end
    return descriptors
end

function ResultsPage:InitializeRow(row)
    row.Title = Controls:Label(row, "", "GameFontNormal")
    row.Title:SetMaxLines(1)
    row.Title:SetWordWrap(false)
    row.Title:SetNonSpaceWrap(false)
    row.Details = Controls:Label(row, "", "GameFontHighlightSmall")
    row.Details:SetMaxLines(0)
    row.Divider = Controls:Divider(row, self.width)
end

function ResultsPage:AcquireRow()
    local row = self.rowPool:Acquire()
    if not row.Title then
        self:InitializeRow(row)
    end
    return row
end

function ResultsPage:LayoutRow(row, descriptor, offset)
    row.kind = descriptor.kind
    row.Title:SetFontObject(descriptor.kind == "heading" and GameFontNormal or GameFontHighlightSmall)
    row.Title:SetText(descriptor.title)
    row.Details:SetText(descriptor.details or "")
    row.Details:SetShown(descriptor.details ~= nil)

    local textWidth = self.width
    PixelUtil.SetSize(row.Title, textWidth, DETAILS_HEIGHT)
    PixelUtil.SetPoint(row.Title, "TOPLEFT", row, "TOPLEFT", 0, 0)
    local height = descriptor.kind == "heading" and HEADER_HEIGHT or DETAILS_HEIGHT
    if descriptor.details then
        PixelUtil.SetWidth(row.Details, textWidth)
        PixelUtil.SetHeight(row.Details, 0)
        local detailsHeight = RoundUp(math.max(DETAILS_HEIGHT, row.Details:GetStringHeight()), row:GetEffectiveScale())
        PixelUtil.SetHeight(row.Details, detailsHeight)
        PixelUtil.SetPoint(row.Details, "TOPLEFT", row, "TOPLEFT", 0, -height)
        height = height + detailsHeight
    end
    if descriptor.kind ~= "heading" then
        height = height + ROW_PADDING
    end
    PixelUtil.SetSize(row, self.width, height)
    PixelUtil.SetPoint(row, "TOPLEFT", self.content, "TOPLEFT", 0, -offset)
    PixelUtil.SetPoint(row.Divider, "BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.Divider:SetShown(descriptor.kind ~= "heading")
    row:Show()
    return row:GetHeight()
end

function ResultsPage:Render(descriptors)
    self.rowPool:ReleaseAll()
    self.rows = {}
    local offset = 0
    for _, descriptor in ipairs(descriptors) do
        local row = self:AcquireRow()
        self.rows[#self.rows + 1] = row
        offset = offset + self:LayoutRow(row, descriptor, offset) + ROW_GAP
    end
    if #descriptors > 0 then
        offset = math.max(0, offset - ROW_GAP)
    end
    self.empty:SetShown(#descriptors == 0)
    PixelUtil.SetSize(self.empty, self.width, self.height)
    PixelUtil.SetHeight(self.content, math.max(self.height, offset))
end

function ResultsPage:Create(page, width, height, scrollbarOptions)
    if self.page then
        return
    end
    self.page, self.width, self.height = page, width, height
    self.help = Controls:Label(page, L.W_RESULTS_HELP, "GameFontHighlightSmall")
    Controls:SetMuted(self.help)
    self.scroll, self.content = Controls:Scroll(page, width, height, scrollbarOptions)
    self.empty = Controls:Label(self.content, L.W_RESULTS_EMPTY, "GameFontHighlightSmall")
    self.empty:SetJustifyV("TOP")
    Controls:SetMuted(self.empty)
    self.rowPool = CreateFramePool("Frame", self.content, nil, ResetRow)
    self:Layout(width, height)
end

function ResultsPage:Layout(width, height)
    self.width, self.height = width, height
    local scrollbar = self.scroll.ScrollBar
    scrollbar:BeginLayout()
    PixelUtil.SetSize(self.help, width, HELP_HEIGHT)
    PixelUtil.SetPoint(self.help, "TOPLEFT", self.page, "TOPLEFT", 0, HELP_Y)
    PixelUtil.SetSize(self.scroll, width, height)
    PixelUtil.SetPoint(self.scroll, "TOPLEFT", self.page, "TOPLEFT", 0, SCROLL_Y)
    PixelUtil.SetPoint(self.empty, "TOPLEFT", self.content, "TOPLEFT", 0, 0)
    self:Invalidate()
    scrollbar:EndLayout()
end

function ResultsPage:CloseMenu() end

function ResultsPage:Invalidate()
    self.cache = nil
end

function ResultsPage:Refresh()
    local revision = Cards.Store.revision or 0
    if self.cache and self.cache.database == Cards.Store.db and self.cache.revision == revision then
        return
    end
    self.cache = { database = Cards.Store.db, revision = revision }
    local scrollbar = self.scroll.ScrollBar
    scrollbar:BeginLayout()
    self:Render(SettlementDescriptors())
    scrollbar:EndLayout()
end

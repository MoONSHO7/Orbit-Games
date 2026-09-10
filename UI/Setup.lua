local _, Games = ...
local L = Games.L
local Controls = Games.Controls

local WIDTH = 370
local HEIGHT = 450
local PADDING = 18
local CONTENT_WIDTH = WIDTH - PADDING * 2
local HEADER_HEIGHT = 24
local ROW_HEIGHT = 52
local FIELD_HEIGHT = 26
local GAP = 8
local FORM_LABEL_FONT = "GameFontHighlight"
local TITLE_OFFSET = 20
local TITLE_WIDTH = CONTENT_WIDTH - 38
local CLOSE_OFFSET = -2
local TAB_SPACING = 4
local TAB_HEIGHT = 24
local TAB_TOP = -48
local DIVIDER_Y = -77
local DIVIDER_RAISE_PIXELS = 10
local FOOTER_DIVIDER_Y = -400
local NOTICE_Y = -410
local FOOTER_NOTICE_Y = -366
local PAGE_TOP = -88
local PAGE_HEIGHT = 302
local GAME_LIST_TOP = 36
local GAME_LIST_HEIGHT = 224
local GAME_JOIN_WIDTH = 64
local GAME_LEAVE_WIDTH = 104
local GAME_REFRESH_INTERVAL = 1
local MAX_GAME_ROWS = 32
local FORM_VALUE_X = 114
local FORM_ROW_STEP = 40
local HOST_TO_Y = 0
local GAME_TYPE_Y = HOST_TO_Y - FORM_ROW_STEP
local MODE_PAGE_TOP = -84
local MODE_PAGE_HEIGHT = PAGE_HEIGHT + MODE_PAGE_TOP
local FOOTER_TOP_PADDING = 12
local FOOTER_BOTTOM_PADDING = 12
local FOOTER_BUTTON_HEIGHT = 20
local FOOTER_SIDE_PADDING = 5
local FOOTER_BUTTON_SPACING = 8
local HOST_FOOTER_HEIGHT = FOOTER_TOP_PADDING + FOOTER_BUTTON_HEIGHT + FOOTER_BOTTOM_PADDING
local PANEL_SCROLLBAR = { rightOffset = PADDING, rightOffsetPixels = -10 }
local PANEL_STRATA = "DIALOG"
local PANEL_LEVEL = 200
local TABS = {
    { "play", L.W_TAB_PLAY },
    { "host", L.W_TAB_HOST },
    { "results", L.W_TAB_RESULTS },
    { "settings", L.W_TAB_SETTINGS },
}
local FORM_METRICS = {
    fieldHeight = FIELD_HEIGHT,
    gap = GAP,
    valueX = FORM_VALUE_X,
    rowStep = FORM_ROW_STEP,
}

Games.UI = { tab = "play", placements = {}, modePages = {} }
local UI = Games.UI

local function ErrorText(reason)
    local gameType = Games.Main:GetGameType()
    return gameType.locale.errors[reason] or L.errors[reason] or reason or L.W_ACTION_FAILED
end

local function ApplyPlacement(region, layout)
    PixelUtil.SetPoint(region, "TOPLEFT", layout.parent, "TOPLEFT", layout.x, layout.y)
    PixelUtil.SetSize(region, layout.width, layout.height)
end

local function Place(region, parent, x, y, width, height)
    local layout = UI.placements[region] or {}
    layout.parent, layout.x, layout.y, layout.width, layout.height = parent, x, y, width, height
    UI.placements[region] = layout
    ApplyPlacement(region, layout)
    return region
end

local function GamesHeight(scroll, count)
    if count == 0 then
        return scroll:GetHeight()
    end
    local scale = scroll:GetEffectiveScale()
    local extent = PixelUtil.GetNearestPixelSize((count - 1) * ROW_HEIGHT, scale)
        + PixelUtil.GetNearestPixelSize(ROW_HEIGHT, scale)
    return math.max(scroll:GetHeight(), extent)
end

local function Label(parent, text, x, y, width, height, font)
    return Place(Controls:Label(parent, text, font), parent, x, y, width, height)
end

local function FormLabel(parent, text, x, y, width)
    local label = Label(parent, text, x, y, width, FIELD_HEIGHT, FORM_LABEL_FONT)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetNonSpaceWrap(false)
    return label
end

local function Button(parent, text, x, y, width, action)
    return Place(Controls:Button(parent, text, width, FIELD_HEIGHT, action), parent, x, y, width, FIELD_HEIGHT)
end

local function Dropdown(parent, text, x, y, width, generator)
    local dropdown = Controls:Dropdown(parent, text, width, generator)
    return Place(dropdown, parent, x, y, width, dropdown:GetHeight())
end

local function CreateFooter(parent)
    local footer = Place(CreateFrame("Frame", nil, parent), UI.footerDivider, 0, 0, CONTENT_WIDTH, HOST_FOOTER_HEIGHT)
    footer.hasButtons = false
    footer:Hide()
    return footer
end

local function FooterButton(parent, text, action)
    return Controls:Button(parent, text, CONTENT_WIDTH, FOOTER_BUTTON_HEIGHT, action)
end

local function LayoutFooterButtons(footer, buttons)
    local count = #buttons
    footer.hasButtons = count > 0
    footer:SetShown(footer.hasButtons)
    if count == 0 then
        return
    end
    local gapCount = count - 1
    local scale = footer:GetEffectiveScale()
    local pixelSize = PixelUtil.GetNearestPixelSize(0, scale, 1)
    local footerPixels = math.floor(footer:GetWidth() / pixelSize + 0.5)
    local sidePixels = math.floor(PixelUtil.GetNearestPixelSize(FOOTER_SIDE_PADDING, scale) / pixelSize + 0.5)
    local spacingPixels = math.floor(PixelUtil.GetNearestPixelSize(FOOTER_BUTTON_SPACING, scale) / pixelSize + 0.5)
    local desiredGapPixels = spacingPixels * gapCount
    local availablePixels = footerPixels - sidePixels * 2 - desiredGapPixels
    local gapReduction = (count - availablePixels % count) % count
    local totalGapPixels = desiredGapPixels - gapReduction
    local buttonPixels = (footerPixels - sidePixels * 2 - totalGapPixels) / count
    local baseGapPixels = gapCount > 0 and math.floor(totalGapPixels / gapCount) or 0
    local extraGapPixels = gapCount > 0 and totalGapPixels % gapCount or 0
    local xPixels = sidePixels
    for index, button in ipairs(buttons) do
        Place(button, footer, xPixels * pixelSize, -FOOTER_TOP_PADDING, buttonPixels * pixelSize, FOOTER_BUTTON_HEIGHT)
        if index < count then
            local gapPixels = baseGapPixels + (index <= extraGapPixels and 1 or 0)
            xPixels = xPixels + buttonPixels + gapPixels
        end
    end
end

local function LayoutGamesFooter(footer, status, action)
    local scale = footer:GetEffectiveScale()
    local pixelSize = PixelUtil.GetNearestPixelSize(0, scale, 1)
    local footerPixels = math.floor(footer:GetWidth() / pixelSize + 0.5)
    local sidePixels = math.floor(PixelUtil.GetNearestPixelSize(FOOTER_SIDE_PADDING, scale) / pixelSize + 0.5)
    local spacingPixels = math.floor(PixelUtil.GetNearestPixelSize(FOOTER_BUTTON_SPACING, scale) / pixelSize + 0.5)
    local actionPixels = math.floor(PixelUtil.GetNearestPixelSize(GAME_LEAVE_WIDTH, scale) / pixelSize + 0.5)
    local statusPixels = footerPixels - sidePixels * 2 - spacingPixels - actionPixels
    Place(status, footer, sidePixels * pixelSize, -FOOTER_TOP_PADDING, statusPixels * pixelSize, FOOTER_BUTTON_HEIGHT)
    Place(
        action,
        footer,
        (sidePixels + statusPixels + spacingPixels) * pixelSize,
        -FOOTER_TOP_PADDING,
        actionPixels * pixelSize,
        FOOTER_BUTTON_HEIGHT
    )
end

local PAGE_LAYOUT = {
    width = CONTENT_WIDTH,
    form = FORM_METRICS,
    Place = Place,
    Label = Label,
    FormLabel = FormLabel,
    Button = Button,
    Dropdown = Dropdown,
    CreateFooter = CreateFooter,
    FooterButton = FooterButton,
    LayoutFooterButtons = LayoutFooterButtons,
}

function UI:GetGameType()
    return Games.Main:GetGameType()
end

function UI:RefreshFooter()
    local footer
    if self.tab == "play" then
        footer = self.gamesFooter
    elseif self.tab == "host" then
        footer = self:GetGameType().ui.hostPage.footer
    end
    self.footerDivider:SetShown(footer and footer.hasButtons or false)
end

function UI:CloseMenus()
    if not self.frame then
        return
    end
    local gameType = self:GetGameType()
    gameType.ui.hostPage:CloseMenus()
    gameType.ui.settingsPage:CloseMenus()
    gameType.ui.resultsPage:CloseMenu()
    self.hostTo:CloseMenu()
    self.gameType:CloseMenu()
end

function UI:SetTab(tab)
    self:CloseMenus()
    self.tab = tab
    for key, page in pairs(self.pages) do
        page:SetShown(key == tab)
        Controls:SetButtonState(self.tabs[key], true, key == tab)
    end
    if tab == "settings" then
        self:GetGameType().ui.settingsPage:Refresh()
    end
    self:Refresh()
end

function UI:LayoutTabs()
    local scale = self.header:GetEffectiveScale()
    local spacing = PixelUtil.GetNearestPixelSize(TAB_SPACING, scale)
    local width = (self.header:GetWidth() - spacing * (#TABS - 1)) / #TABS
    local snappedWidth = PixelUtil.GetNearestPixelSize(width, scale)
    if snappedWidth > width then
        snappedWidth = snappedWidth - PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    local offset = 0
    for _, entry in ipairs(TABS) do
        local button = self.tabs[entry[1]]
        PixelUtil.SetSize(button, snappedWidth, TAB_HEIGHT)
        PixelUtil.SetPoint(button, "TOPLEFT", self.header, "TOPLEFT", offset, 0)
        offset = offset + button:GetWidth() + spacing
    end
end

function UI:ApplyPosition()
    local scale = self.frame:GetScale()
    local screenWidth, screenHeight = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    local maxX, maxY =
        math.max(0, screenWidth - self.frame:GetWidth()), math.max(0, screenHeight - self.frame:GetHeight())
    local left = self.position and self.position.x * screenWidth - self.frame:GetWidth() / 2 or PADDING
    local bottom = (self.position and self.position.y or 0.5) * screenHeight - self.frame:GetHeight() / 2
    local effectiveScale = self.frame:GetEffectiveScale()
    local pixel = PixelUtil.GetNearestPixelSize(0, effectiveScale, 1)
    left = PixelUtil.GetNearestPixelSize(math.max(0, math.min(maxX, left)), effectiveScale)
    bottom = PixelUtil.GetNearestPixelSize(math.max(0, math.min(maxY, bottom)), effectiveScale)
    if left > maxX then
        left = math.max(0, left - pixel)
    end
    if bottom > maxY then
        bottom = math.max(0, bottom - pixel)
    end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

function UI:StopDrag()
    if not self.dragging then
        return
    end
    self.frame:StopMovingOrSizing()
    self.dragging = false
    local left, bottom, width, height = self.frame:GetScaledRect()
    local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
    if
        left
        and bottom
        and width
        and height
        and screenLeft
        and screenBottom
        and screenWidth
        and screenHeight
        and screenWidth > 0
        and screenHeight > 0
    then
        self.position = {
            x = (left + width / 2 - screenLeft) / screenWidth,
            y = (bottom + height / 2 - screenBottom) / screenHeight,
        }
    end
    self:ApplyPosition()
end

function UI:RefreshLayout()
    for region, layout in pairs(self.placements) do
        ApplyPlacement(region, layout)
    end
    PixelUtil.SetSize(self.close, self.closeWidth, self.closeHeight)
    PixelUtil.SetPoint(self.close, "TOPRIGHT", self.frame, "TOPRIGHT", CLOSE_OFFSET, CLOSE_OFFSET)
    PixelUtil.SetSize(self.gamesContent, CONTENT_WIDTH, GamesHeight(self.gamesScroll, #self.gameRows))
    LayoutGamesFooter(self.gamesFooter, self.currentViewport, self.leave)
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        gameType.ui.resultsPage:Layout(CONTENT_WIDTH, GAME_LIST_HEIGHT)
    end
    self:LayoutTabs()
    local raise = PixelUtil.GetNearestPixelSize(0, self.frame:GetEffectiveScale(), DIVIDER_RAISE_PIXELS)
    PixelUtil.SetPoint(self.headerDivider, "TOPLEFT", self.frame, "TOPLEFT", PADDING, DIVIDER_Y + raise)
    PixelUtil.SetPoint(self.footerDivider, "TOPLEFT", self.frame, "TOPLEFT", PADDING, FOOTER_DIVIDER_Y)
    Controls:RefreshScale()
    Games.SettingsControls:RefreshScale()
end

function UI:CreatePlayPage(page)
    self.refreshGames = Button(page, L.W_REFRESH, CONTENT_WIDTH - 90, 0, 90, function()
        if not self.gamePreview then
            Games.Discovery:Refresh()
        end
        self.nextGamesRefresh = nil
        self:Refresh()
    end)
    self.gamesTitle = Label(page, L.W_AVAILABLE_GAMES, 0, -5, CONTENT_WIDTH - 100, FIELD_HEIGHT, "GameFontNormal")
    self.gamesScroll, self.gamesContent = Controls:Scroll(page, CONTENT_WIDTH, GAME_LIST_HEIGHT, PANEL_SCROLLBAR)
    Place(self.gamesScroll, page, 0, -GAME_LIST_TOP, CONTENT_WIDTH, GAME_LIST_HEIGHT)
    self.gamesEmpty = Label(self.gamesContent, L.W_NO_GAMES, 0, -20, CONTENT_WIDTH, 64)
    Controls:SetMuted(self.gamesEmpty)
    self.gameRows = {}
    self.gameRowPool = CreateFramePool("Frame", self.gamesContent, nil, function(_, row)
        row:Hide()
        row:ClearAllPoints()
        row.game, row.gameKey = nil, nil
    end)
    self.gamesFooter = CreateFooter(page)
    self.gamesFooter.hasButtons = true
    self.gamesFooter:Show()
    self.currentViewport = Controls:ScrollingLabel(self.gamesFooter, L.W_NO_SESSION)
    self.current = self.currentViewport.Text
    self.current:SetJustifyV("MIDDLE")
    self.leave = FooterButton(self.gamesFooter, L.W_LEAVE, function()
        local ok, reason = Games.Main:Leave()
        self.actionError = not ok and ErrorText(reason) or nil
        self:Refresh()
    end)
    LayoutGamesFooter(self.gamesFooter, self.currentViewport, self.leave)
end

function UI:CreateModePages()
    self.hostToLabel = FormLabel(self.pages.host, L.W_HOST_TO, 0, HOST_TO_Y, FORM_VALUE_X - GAP)
    self.hostTo = Dropdown(
        self.pages.host,
        L.W_HOST_TO,
        FORM_VALUE_X,
        HOST_TO_Y,
        CONTENT_WIDTH - FORM_VALUE_X,
        function(_, root)
            local audiences = Games.Store:GetHostAudiences()
            local selectedCount = 0
            for _, selected in pairs(audiences) do
                selectedCount = selectedCount + (selected and 1 or 0)
            end
            local function IsSelected(value)
                return Games.Store:GetHostAudiences()[value]
            end
            local function Select(value)
                local selected = Games.Store:GetHostAudiences()
                selected[value] = not selected[value]
                local changed, reason = Games.Store:SaveHostAudiences(selected)
                self.actionError = not changed and reason ~= "unchanged" and ErrorText(reason) or nil
                self:Refresh()
            end
            for _, option in ipairs({
                { "server", L.W_HOST_TO_SERVER },
                { "guild", L.W_HOST_TO_GUILD },
                { "party", L.W_HOST_TO_PARTY },
            }) do
                local entry = root:CreateCheckbox(option[2], IsSelected, Select, option[1])
                entry:SetEnabled(not audiences[option[1]] or selectedCount > 1)
            end
        end
    )
    self.hostTo:EnableRegenerateOnResponse()
    self.gameTypeLabel = FormLabel(self.pages.host, L.W_GAME_TYPE, 0, GAME_TYPE_Y, FORM_VALUE_X - GAP)
    self.gameType = Dropdown(
        self.pages.host,
        L.W_GAME_TYPE,
        FORM_VALUE_X,
        GAME_TYPE_Y,
        CONTENT_WIDTH - FORM_VALUE_X,
        function(_, root)
            local function IsSelected(value)
                return self:GetGameType().id == value
            end
            local function Select(value)
                local changed, reason = Games.Main:SelectGameType(value)
                self.actionError = not changed and reason ~= "unchanged" and ErrorText(reason) or nil
                if changed then
                    self:ActivateGameType()
                end
                self:Refresh()
            end
            for _, gameType in ipairs(Games.GameTypes:GetAll()) do
                root:CreateRadio(gameType.title, IsSelected, Select, gameType.id)
            end
        end
    )
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        local host = CreateFrame("Frame", nil, self.pages.host)
        Place(host, self.pages.host, 0, MODE_PAGE_TOP, CONTENT_WIDTH, MODE_PAGE_HEIGHT)
        gameType.ui.hostPage:Create(host, PAGE_LAYOUT)

        local results = CreateFrame("Frame", nil, self.pages.results)
        Place(results, self.pages.results, 0, 0, CONTENT_WIDTH, PAGE_HEIGHT)
        gameType.ui.resultsPage:Create(results, CONTENT_WIDTH, GAME_LIST_HEIGHT, PANEL_SCROLLBAR)

        local settings = CreateFrame("Frame", nil, self.pages.settings)
        Place(settings, self.pages.settings, 0, 0, CONTENT_WIDTH, PAGE_HEIGHT)
        gameType.ui.settingsPage:Create(settings, PAGE_LAYOUT)

        self.modePages[gameType.id] = { host = host, results = results, settings = settings }
    end
end

function UI:ActivateGameType()
    local selected = self:GetGameType()
    for gameTypeId, pages in pairs(self.modePages) do
        local shown = gameTypeId == selected.id
        pages.host:SetShown(shown)
        pages.results:SetShown(shown)
        pages.settings:SetShown(shown)
    end
    self.gameType:SetDefaultText(selected.title)
    self.gameType:GenerateMenu()
    self.tabs.results:SetText(selected.resultsTitle)
    selected.ui.hostPage:Load()
    selected.ui.settingsPage:Refresh()
    selected.ui.resultsPage:Invalidate()
    self.gamesSignature, self.gamesViewKey = nil, nil
end

function UI:Create()
    if self.frame then
        return
    end
    local frame = Controls:Panel(UIParent, "OrbitGamesHostFrame")
    frame:Hide()
    self.frame = frame
    PixelUtil.SetSize(frame, WIDTH, HEIGHT)
    frame:SetFrameStrata(PANEL_STRATA)
    frame:SetFrameLevel(PANEL_LEVEL)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        UI:CloseMenus()
        UI.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        self:StopDrag()
    end)
    frame.TitleText = Controls:Label(frame, L.W_TITLE, "GameFontHighlightLarge")
    Place(frame.TitleText, frame, (WIDTH - TITLE_WIDTH) / 2, -TITLE_OFFSET, TITLE_WIDTH, HEADER_HEIGHT)
    frame.TitleText:SetJustifyH("CENTER")
    self.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    self.closeWidth, self.closeHeight = self.close:GetWidth(), self.close:GetHeight()
    PixelUtil.SetPoint(self.close, "TOPRIGHT", frame, "TOPRIGHT", CLOSE_OFFSET, CLOSE_OFFSET)
    self.close:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.CloseButton = self.close
    self.header = CreateFrame("Frame", nil, frame)
    Place(self.header, frame, PADDING, TAB_TOP, CONTENT_WIDTH, TAB_HEIGHT + GAP)
    self.header:SetClipsChildren(true)
    self.tabs, self.pages = {}, {}
    for _, entry in ipairs(TABS) do
        local tab = entry[1]
        local tabButton = Controls:Tab(self.header, entry[2], function()
            self:SetTab(tab)
        end)
        self.tabs[tab] = tabButton
        local page = CreateFrame("Frame", nil, frame)
        Place(page, frame, PADDING, PAGE_TOP, CONTENT_WIDTH, PAGE_HEIGHT)
        self.pages[tab] = page
    end
    self.headerDivider = Controls:Divider(frame, CONTENT_WIDTH)
    self.footerDivider = Controls:Divider(frame, CONTENT_WIDTH)
    PixelUtil.SetPoint(self.footerDivider, "TOPLEFT", frame, "TOPLEFT", PADDING, FOOTER_DIVIDER_Y)
    self.footerDivider:Hide()
    self:CreatePlayPage(self.pages.play)
    self:CreateModePages()
    self.notice = Label(frame, "", PADDING, NOTICE_Y, CONTENT_WIDTH, 28)
    self.notice:Hide()
    frame:SetScript("OnShow", function()
        self:GetGameType().ui.hud:SetEditing(true)
        self:GetGameType().ui.settingsPage:Refresh()
        if not self.gamePreview then
            Games.Discovery:Refresh()
        end
        self.nextGamesRefresh = nil
        self:Refresh()
    end)
    frame:SetScript("OnHide", function()
        self:StopDrag()
        self:CloseMenus()
        self:GetGameType().ui.hud:SetEditing(false)
    end)
    UISpecialFrames[#UISpecialFrames + 1] = "OrbitGamesHostFrame"
    self:ActivateGameType()
    self:SetTab(self.tab)
    self:OnDisplayChanged()
end

function UI:LoadSettings()
    if not self.frame then
        return
    end
    self:ActivateGameType()
    self:GetGameType().ui.hostPage:Load()
    self:GetGameType().ui.settingsPage:Refresh()
end

function UI:RefreshModeSettings()
    if self.frame then
        self:GetGameType().ui.settingsPage:Refresh()
    end
end

function UI:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end

function UI:Show(tab)
    self:Create()
    self:SetTab(tab)
    self.frame:Show()
end

function UI:SetGamePreview(preview)
    self.gamePreview = preview
    self.gamesSignature, self.gamesViewKey, self.nextGamesRefresh = nil, nil, nil
    self.actionError = nil
    if self.frame then
        self.gamesScroll.ScrollBar:ScrollTo(0, true)
        self:Refresh()
    end
end

function UI:OnDisplayChanged()
    if not self.frame then
        return
    end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then
        return
    end
    self.gamesScroll.ScrollBar:BeginLayout()
    self:StopDrag()
    self.frame:SetScale(math.min(1, (width - PADDING * 2) / WIDTH, (height - PADDING * 2) / HEIGHT))
    PixelUtil.SetSize(self.frame, WIDTH, HEIGHT)
    self:ApplyPosition()
    self:RefreshLayout()
    self:CloseMenus()
    self.gamesSignature = nil
    self:GetGameType().ui.resultsPage:Invalidate()
    self:Refresh()
    self.gamesScroll.ScrollBar:EndLayout()
end

function UI:RefreshGames(view)
    self.gamesTitle:SetText(self.gamePreview and self.gamePreview.title or L.W_AVAILABLE_GAMES)
    local sessionId = view.sessionId or view.session or ""
    local currentKey = (view.hostName or "")
        .. ":"
        .. sessionId
        .. ":"
        .. view.state
        .. ":"
        .. tostring(Games.Main:IsRestricted())
        .. ":"
        .. tostring(Games.Main:IsSessionActive())
        .. ":"
        .. tostring(self.gamePreview ~= nil)
    if self.nextGamesRefresh and GetTime() < self.nextGamesRefresh and self.gamesViewKey == currentKey then
        return
    end
    self.nextGamesRefresh = GetTime() + GAME_REFRESH_INTERVAL
    self.gamesViewKey = currentKey
    local games = self.gamePreview and self.gamePreview.games or Games.Discovery:GetGames()
    local count = math.min(MAX_GAME_ROWS, #games)
    local signature = { currentKey }
    for index = 1, count do
        local game = games[index]
        signature[#signature + 1] = table.concat({
            game.hostName,
            game.sessionId,
            game.gameTypeId,
            game.title,
            game.description,
            game.phase,
            tostring(game.playerCount),
            tostring(game.maxPlayers),
            tostring(game.joinable),
            game.activityId,
            tostring(game.activityVersion),
        }, ":")
    end
    signature = table.concat(signature, "|")
    if self.gamesSignature == signature then
        return
    end
    local scrollbar = self.gamesScroll.ScrollBar
    scrollbar:BeginLayout()
    self.gamesSignature = signature
    for index = #self.gameRows, count + 1, -1 do
        self.gameRowPool:Release(self.gameRows[index])
        self.gameRows[index] = nil
    end
    self.gamesEmpty:SetShown(#games == 0)
    for index = 1, count do
        local row, isNew = self.gameRows[index]
        if not row then
            row, isNew = self.gameRowPool:Acquire()
        end
        if isNew then
            row.host = Label(row, "", GAP, -GAP, CONTENT_WIDTH - GAME_JOIN_WIDTH - GAP * 3, 18, "GameFontNormal")
            row.detailViewport =
                Place(Controls:ScrollingLabel(row, ""), row, GAP, -28, CONTENT_WIDTH - GAME_JOIN_WIDTH - GAP * 3, 18)
            row.detail = row.detailViewport.Text
            row.host:SetWordWrap(false)
            Controls:SetMuted(row.detail)
            row.join = Button(row, L.W_JOIN, CONTENT_WIDTH - GAME_JOIN_WIDTH, -12, GAME_JOIN_WIDTH, function()
                if not row.game or row.game.preview then
                    return
                end
                local ok, reason = Games.Main:Join(row.game)
                self.actionError = not ok and ErrorText(reason) or nil
                self:Refresh()
            end)
        end
        local game = games[index]
        local gameKey = game.hostName .. ":" .. game.sessionId
        Controls:SetScrollingText(
            row.detailViewport,
            L.W_GAME_DETAIL_F:format(game.title, game.description, game.playerCount, game.maxPlayers),
            row.gameKey ~= gameKey
        )
        row.gameKey = gameKey
        row.game = game
        Place(row, self.gamesContent, 0, -(index - 1) * ROW_HEIGHT, CONTENT_WIDTH, ROW_HEIGHT)
        row.host:SetText(game.hostName)
        local joined = Games.Main:IsJoinedTo(game)
        row.join:SetText(joined and L.W_JOINED or not game.joinable and L.W_GAME_FULL or L.W_JOIN)
        Controls:SetButtonState(
            row.join,
            not game.preview and game.joinable and not joined and not Games.Main:IsRestricted(),
            joined
        )
        row:Show()
        self.gameRows[index] = row
    end
    PixelUtil.SetHeight(self.gamesContent, GamesHeight(self.gamesScroll, count))
    scrollbar:EndLayout()
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then
        return
    end
    local gameType = self:GetGameType()
    local controller = gameType.controller
    local session = gameType.session
    local view = session:GetView()
    local actionNotice = self.actionError or gameType.ui.hud.actionError
    local notice
    if self.tab == "host" then
        notice = actionNotice
            or gameType.ui.hostPage:GetNotice()
            or view.role == "participant" and view.notice
            or controller:GetNotice()
            or view.notice
    else
        notice = actionNotice
            or self.tab == "play" and self.gamePreview and self.gamePreview.notice
            or view.role == "participant" and view.notice
            or controller:GetNotice()
            or view.notice
    end
    self.notice:SetText(notice or "")
    self.notice:SetShown(notice ~= nil and notice ~= "")
    local noticeY = (self.tab == "play" or self.tab == "host") and FOOTER_NOTICE_Y or NOTICE_Y
    Place(self.notice, self.frame, PADDING, noticeY, CONTENT_WIDTH, 28)
    if self.tab == "play" then
        self:RefreshGames(view)
        local active = session:IsActive()
        local sessionText = view.state == "joining" and L.W_JOINING_SESSION_F
            or view.state == "disconnected" and L.W_REJOINING_SESSION_F
            or L.W_CURRENT_SESSION_F
        Controls:SetScrollingText(
            self.currentViewport,
            active and sessionText:format(view.hostName or "") or L.W_NO_SESSION
        )
        Controls:SetButtonState(self.leave, active)
    elseif self.tab == "host" then
        gameType.ui.hostPage:Refresh()
        local setupEnabled = not Games.Main:IsRunning() and not Games.Main:IsSessionActive()
        self.hostTo:SetEnabled(setupEnabled)
        self.gameType:SetEnabled(setupEnabled)
    elseif self.tab == "results" then
        gameType.ui.resultsPage:Refresh(view)
    elseif self.tab == "settings" then
        gameType.ui.settingsPage:Refresh()
    end
    self:RefreshFooter()
end

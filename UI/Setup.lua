local _, Quiz = ...
local L = Quiz.L
local Controls = Quiz.Controls
local WIDTH = 370
local HEIGHT = 450
local PADDING = 18
local CONTENT_WIDTH = WIDTH - PADDING * 2
local HEADER_HEIGHT = 24
local ROW_HEIGHT = 52
local FIELD_HEIGHT = 26
local GAP = 8
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
local PAGE_TOP = -88
local PAGE_HEIGHT = 302
local GAME_LIST_HEIGHT = 224
local GAME_JOIN_WIDTH = 64
local GAME_REFRESH_INTERVAL = 1
local MAX_GAME_ROWS = 32
local BOARD_ROWS = 20
local VALUE_X = 114
local VALUE_WIDTH = CONTENT_WIDTH - VALUE_X
local ACTION_WIDTH = (CONTENT_WIDTH - GAP * 2) / 3
local MENU_SCROLL_HEIGHT = 220
local MENU_MAX_WIDTH = 540
local MIN_FONT_HEIGHT = 16
local HOST_HELP_Y = -116
local HOST_HELP_HEIGHT = 136
local SETTINGS_SLIDER_Y = 0
local SETTINGS_FONT_Y = -40
local SETTINGS_VOLUME_Y = -80
local SETTINGS_HELP_Y = -128
local SETTINGS_HELP_HEIGHT = 114
local PANEL_SCROLLBAR = { rightOffset = PADDING, rightOffsetPixels = -10 }
local PANEL_STRATA = "DIALOG"
local PANEL_LEVEL = 200
local TABS = {
    { "play", L.W_TAB_PLAY },
    { "host", L.W_TAB_HOST },
    { "scores", L.W_TAB_SCORES },
    { "settings", L.W_TAB_SETTINGS },
}
local BOARD_SCOPES = { "personal", "game", "league", "legacy" }
local BOARD_TITLES = {
    personal = L.W_PERSONAL_BOARD,
    game = L.W_SESSION_BOARD,
    league = L.W_LEAGUE_ARCHIVE,
    legacy = L.W_LEGACY_BOARD,
}

Quiz.UI = { boardScope = "personal", tab = "play", placements = {} }
local UI = Quiz.UI

local function CloseMenus()
    UI.pack:CloseMenu()
    UI.boardSwitch:CloseMenu()
    UI.fontPicker:CloseMenu()
end

local function ApplyPlacement(region, layout)
    PixelUtil.SetPoint(region, "TOPLEFT", layout.parent, "TOPLEFT", layout.x, layout.y)
    PixelUtil.SetSize(region, layout.width, layout.height)
end

local function Place(region, parent, x, y, width, height)
    -- Keep authored units so display changes never re-snap previously rounded dimensions.
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

local function Button(parent, text, x, y, width, action)
    return Place(Controls:Button(parent, text, width, FIELD_HEIGHT, action), parent, x, y, width, FIELD_HEIGHT)
end

local function Dropdown(parent, text, x, y, width, generator)
    local dropdown = Controls:Dropdown(parent, text, width, generator)
    return Place(dropdown, parent, x, y, width, dropdown:GetHeight())
end

local function Edit(parent, label, y, maxLetters)
    Label(parent, label, 0, y - GAP, VALUE_X - GAP, FIELD_HEIGHT)
    return Place(
        Controls:Edit(parent, VALUE_WIDTH, FIELD_HEIGHT, maxLetters),
        parent,
        VALUE_X,
        y,
        VALUE_WIDTH,
        FIELD_HEIGHT
    )
end

function UI:SetTab(tab)
    CloseMenus()
    self.tab = tab
    for key, page in pairs(self.pages) do
        page:SetShown(key == tab)
        Controls:SetButtonState(self.tabs[key], true, key == tab)
    end
    if tab == "settings" then
        self:RefreshWidgetSettings()
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
    -- A corner anchor avoids half-pixel centers on odd-sized screens and windows.
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
    PixelUtil.SetSize(self.boardContent, CONTENT_WIDTH, math.max(GAME_LIST_HEIGHT, self.board:GetHeight()))
    self:LayoutTabs()
    local raise = PixelUtil.GetNearestPixelSize(0, self.frame:GetEffectiveScale(), DIVIDER_RAISE_PIXELS)
    PixelUtil.SetPoint(self.headerDivider, "TOPLEFT", self.frame, "TOPLEFT", PADDING, DIVIDER_Y + raise)
    PixelUtil.SetPoint(self.footerDivider, "TOPLEFT", self.frame, "TOPLEFT", PADDING, FOOTER_DIVIDER_Y)
    Controls:RefreshScale()
    Quiz.SettingsControls:RefreshScale()
end

function UI:CreatePlayPage(page)
    self.refreshGames = Button(page, L.W_REFRESH, CONTENT_WIDTH - 90, 0, 90, function()
        if not self.gamePreview then
            Quiz.Discovery:Refresh()
        end
        self.nextGamesRefresh = nil
        self:Refresh()
    end)
    self.gamesTitle = Label(page, L.W_AVAILABLE_GAMES, 0, -5, CONTENT_WIDTH - 100, FIELD_HEIGHT, "GameFontNormal")
    self.gamesScroll, self.gamesContent = Controls:Scroll(page, CONTENT_WIDTH, GAME_LIST_HEIGHT, PANEL_SCROLLBAR)
    Place(self.gamesScroll, page, 0, -36, CONTENT_WIDTH, GAME_LIST_HEIGHT)
    self.gamesEmpty = Label(self.gamesContent, L.W_NO_GAMES, 0, -20, CONTENT_WIDTH, 64)
    Controls:SetMuted(self.gamesEmpty)
    self.gameRows = {}
    self.gameRowPool = CreateFramePool("Frame", self.gamesContent, nil, function(_, row)
        row:Hide()
        row:ClearAllPoints()
        row.game, row.gameKey = nil, nil
    end)
    self.current = Label(page, L.W_NO_SESSION, 0, -270, CONTENT_WIDTH - 108, 34)
    self.leave = Button(page, L.W_LEAVE, CONTENT_WIDTH - 104, -270, 104, function()
        if Quiz.Main:IsRunning() then
            Quiz.Main:Stop()
        else
            local ok, reason = Quiz.Session:Leave()
            self.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
        end
        self:Refresh()
    end)
end

function UI:RefreshPack()
    self.pack:GenerateMenu()
    self:RefreshHostRules()
end

function UI:RefreshHostRules()
    local game = Quiz.Main:IsRunning() and Quiz.Main.game or nil
    local packId = game and game.settings.packId or self.draft.packId
    local rules, reason
    if game then
        rules = game.rules
    else
        rules, reason = Quiz:GetPackRules(packId)
    end
    self.hostRules, self.hostRulesPackId, self.hostRulesGame = rules, packId, game
    if not rules then
        self.durationInfo:SetText(L.W_RULES_UNAVAILABLE)
        self.hostHelp:SetText(L.errors[reason] or reason)
        return
    end
    self.durationInfo:SetText(L.W_RULE_DURATION_F:format(rules.answerSeconds, rules.revealSeconds))
    local length = rules.questionLimit > 0 and L.W_RULE_LIMIT_F:format(rules.questionLimit)
        or rules.repeatQuestions and L.W_RULE_ENDLESS
        or L.W_RULE_ONE_PASS
    local order = rules.shuffleQuestions and L.W_RULE_SHUFFLED or L.W_RULE_ORDERED
    self.hostHelp:SetText(table.concat({
        L.W_RULES_OWNED,
        L.W_RULE_FLOW_F:format(order, length),
        L.W_RULE_CORRECT_F:format(rules.correctPoints, rules.speedBonusPerSecond),
        L.W_RULE_WRONG_F:format(rules.wrongPenaltyStart, rules.wrongPenaltyEnd),
        rules.streakBonusPerCorrect > 0 and L.W_RULE_STREAK_F:format(rules.streakBonusPerCorrect, rules.streakBonusMax)
            or L.W_RULE_NO_STREAK,
        rules.allowAnswerChanges and L.W_RULE_EDITABLE or L.W_RULE_LOCKED,
    }, "\n"))
end

function UI:CreateHostPage(page)
    self.league = Edit(page, L.LEAGUE, 0, 48)
    Label(page, L.PACK, 0, -44, VALUE_X - GAP, FIELD_HEIGHT)
    self.pack = Dropdown(page, L.ALL_PACKS, VALUE_X, -36, VALUE_WIDTH, function(_, root)
        root:SetScrollMode(MENU_SCROLL_HEIGHT)
        root:SetMaximumWidth(MENU_MAX_WIDTH)
        local function IsSelected(value)
            return self.draft.packId == value
        end
        local function Select(value)
            self.draft.packId = value
            self:RefreshHostRules()
            self:Refresh()
        end
        if Quiz:GetPackRules("all") then
            root:CreateRadio(L.ALL_PACKS, IsSelected, Select, "all")
        end
        for _, pack in ipairs(Quiz:GetQuestionPacks()) do
            root:CreateRadio(pack.title, IsSelected, Select, pack.id)
        end
    end)
    self.durationInfo = Label(page, "", 0, -80, CONTENT_WIDTH, FIELD_HEIGHT)
    Controls:SetMuted(self.durationInfo)
    self.hostHelp = Label(page, "", 0, HOST_HELP_Y, CONTENT_WIDTH, HOST_HELP_HEIGHT)
    Controls:SetMuted(self.hostHelp)
    self.start = Button(page, L.W_START, 0, -268, ACTION_WIDTH, function()
        Quiz.Main:Start(self:ReadSettings())
    end)
    self.pause = Button(page, L.W_PAUSE, ACTION_WIDTH + GAP, -268, ACTION_WIDTH, function()
        if Quiz.Main.game.state == "paused" then
            Quiz.Main:Resume()
        else
            Quiz.Main:Pause(nil, false)
        end
    end)
    self.stop = Button(page, L.W_STOP, (ACTION_WIDTH + GAP) * 2, -268, ACTION_WIDTH, function()
        Quiz.Main:Stop()
    end)
    self.save = Button(page, L.APPLY, ACTION_WIDTH + GAP, -268, ACTION_WIDTH, function()
        Quiz.Main:SaveSettings(self:ReadSettings())
    end)
end

function UI:CreateScoresPage(page)
    self.boardSwitch = Dropdown(page, L.W_PERSONAL_BOARD, 0, 0, CONTENT_WIDTH, function(_, root)
        local function IsSelected(value)
            return self.boardScope == value
        end
        local function Select(value)
            self.boardScope = value
            self:Refresh()
        end
        for _, scope in ipairs(BOARD_SCOPES) do
            root:CreateRadio(BOARD_TITLES[scope], IsSelected, Select, scope)
        end
    end)
    self.boardScroll, self.boardContent = Controls:Scroll(page, CONTENT_WIDTH, GAME_LIST_HEIGHT, PANEL_SCROLLBAR)
    Place(self.boardScroll, page, 0, -38, CONTENT_WIDTH, GAME_LIST_HEIGHT)
    self.board = Label(self.boardContent, L.NO_STANDINGS, 0, 0, CONTENT_WIDTH, GAME_LIST_HEIGHT)
    self.boardHint = Label(page, L.W_BOARD_HELP, 0, -272, CONTENT_WIDTH, 36)
    Controls:SetMuted(self.boardHint)
end

function UI:CreateSettingsPage(page)
    self.widgetSettings = Quiz.Store:GetWidgetSettings()
    self.widgetFontAvailable = Quiz.Media:HasFont(self.widgetSettings.font)
    self.scaleSlider = Quiz.SettingsControls:Slider(
        page,
        L.W_WIDGET_SCALE,
        CONTENT_WIDTH,
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
    Place(self.scaleSlider, page, 0, SETTINGS_SLIDER_Y, CONTENT_WIDTH, self.scaleSlider.layoutHeight)
    self.fontRow = Quiz.SettingsControls:Font(page, L.W_WIDGET_FONT, CONTENT_WIDTH, function(value)
        self:SaveWidgetSettings({ font = value })
    end)
    self.fontPicker = self.fontRow.Control
    Place(self.fontRow, page, 0, SETTINGS_FONT_Y, CONTENT_WIDTH, self.fontRow.layoutHeight)
    self.soundVolume = Quiz.Store:GetSoundVolume()
    self.volumeSlider = Quiz.SettingsControls:Slider(
        page,
        L.W_SOUND_VOLUME,
        CONTENT_WIDTH,
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
    Place(self.volumeSlider, page, 0, SETTINGS_VOLUME_Y, CONTENT_WIDTH, self.volumeSlider.layoutHeight)
    self.widgetSettingsHelp = Label(page, "", 0, SETTINGS_HELP_Y, CONTENT_WIDTH, SETTINGS_HELP_HEIGHT)
    Controls:SetMuted(self.widgetSettingsHelp)
end

function UI:RefreshWidgetSettings()
    if not self.fontPicker then
        return
    end
    local settings = Quiz.Store:GetWidgetSettings()
    local fontChanged = self.widgetSettings.font ~= settings.font or self.widgetMediaRevision ~= Quiz.Media.revision
    self.widgetSettings = settings
    if self.scaleSlider.Slider.Slider:GetValue() ~= settings.scale then
        self.scaleSlider:SetValue(settings.scale)
    end
    self.soundVolume = Quiz.Store:GetSoundVolume()
    if self.volumeSlider.Slider.Slider:GetValue() ~= self.soundVolume then
        self.volumeSlider:SetValue(self.soundVolume)
    end
    if fontChanged then
        self.widgetMediaRevision = Quiz.Media.revision
        self.widgetFontAvailable = Quiz.Media:HasFont(settings.font)
        self.fontPicker:SetSelection(settings.font)
        local help = L.W_WIDGET_SETTINGS_HELP
        if not self.widgetFontAvailable then
            help = help .. "\n\n" .. L.W_WIDGET_FONT_MISSING
        end
        self.widgetSettingsHelp:SetText(help)
    end
end

function UI:SaveWidgetSettings(settings)
    local ok, reason = Quiz.Store:SaveWidgetSettings(settings)
    self.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
    if ok then
        Quiz.Widget:ApplySettings()
    end
    self:RefreshWidgetSettings()
    self:Refresh()
end

function UI:SaveSoundVolume(value)
    local ok, reason = Quiz.Store:SaveSoundVolume(value)
    self.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
    if ok then
        Quiz.StreakToasts:SetVolume(Quiz.Store:GetSoundVolume())
    end
    self:RefreshWidgetSettings()
end

function UI:Create()
    if self.frame then
        return
    end
    self.draft = Quiz.Store:GetSettings()
    self.frame = Controls:Panel(UIParent, "OrbitQuizHostFrame")
    local frame = self.frame
    PixelUtil.SetSize(frame, WIDTH, HEIGHT)
    frame:SetFrameStrata(PANEL_STRATA)
    frame:SetFrameLevel(PANEL_LEVEL)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        CloseMenus()
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
    self:CreatePlayPage(self.pages.play)
    self:CreateHostPage(self.pages.host)
    self:CreateScoresPage(self.pages.scores)
    self:CreateSettingsPage(self.pages.settings)
    self.footerDivider = Controls:Divider(frame, CONTENT_WIDTH)
    PixelUtil.SetPoint(self.footerDivider, "TOPLEFT", frame, "TOPLEFT", PADDING, FOOTER_DIVIDER_Y)
    self.notice = Label(frame, L.W_SETUP_HINT, PADDING, NOTICE_Y, CONTENT_WIDTH, 28)
    Controls:SetMuted(self.notice)
    frame:SetScript("OnShow", function()
        Quiz.Widget:SetEditing(true)
        self:RefreshWidgetSettings()
        if not self.gamePreview then
            Quiz.Discovery:Refresh()
        end
        self.nextGamesRefresh = nil
        self:Refresh()
    end)
    frame:SetScript("OnHide", function()
        self:StopDrag()
        CloseMenus()
        Quiz.Widget:SetEditing(false)
        self.league:ClearFocus()
    end)
    UISpecialFrames[#UISpecialFrames + 1] = "OrbitQuizHostFrame"
    self:LoadSettings()
    frame:Hide()
    self:SetTab(self.tab)
    self:OnDisplayChanged()
end

function UI:LoadSettings()
    self.draft = Quiz.Store:GetSettings()
    self.boardRevision = nil
    self.league:SetText(self.draft.league)
    self:RefreshPack()
    self:RefreshWidgetSettings()
end

function UI:ReadSettings()
    local settings = Quiz.Store:GetSettings()
    settings.packId = self.draft.packId
    settings.league = self.league:GetText()
    return settings
end

function UI:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
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
    self.boardScroll.ScrollBar:BeginLayout()
    self:StopDrag()
    self.frame:SetScale(math.min(1, (width - PADDING * 2) / WIDTH, (height - PADDING * 2) / HEIGHT))
    PixelUtil.SetSize(self.frame, WIDTH, HEIGHT)
    self:ApplyPosition()
    self:RefreshLayout()
    CloseMenus()
    self.gamesSignature, self.boardRevision = nil, nil
    self:Refresh()
    self.boardScroll.ScrollBar:EndLayout()
    self.gamesScroll.ScrollBar:EndLayout()
end

function UI:RefreshGames(view)
    self.gamesTitle:SetText(self.gamePreview and self.gamePreview.title or L.W_AVAILABLE_GAMES)
    local currentKey = (view.hostName or "")
        .. ":"
        .. (view.session or "")
        .. ":"
        .. view.state
        .. ":"
        .. tostring(Quiz.Main:IsRestricted())
        .. ":"
        .. tostring(Quiz.Session.client ~= nil)
        .. ":"
        .. tostring(self.gamePreview ~= nil)
    if self.nextGamesRefresh and GetTime() < self.nextGamesRefresh and self.gamesViewKey == currentKey then
        return
    end
    self.nextGamesRefresh = GetTime() + GAME_REFRESH_INTERVAL
    self.gamesViewKey = currentKey
    local games = self.gamePreview and self.gamePreview.games or Quiz.Discovery:GetGames()
    local count = math.min(MAX_GAME_ROWS, #games)
    local signature = { currentKey }
    for index = 1, count do
        local game = games[index]
        signature[#signature + 1] = table.concat(
            { game.hostName, game.session, game.packName, game.league, game.state, tostring(game.players) },
            ":"
        )
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
                local ok, reason = Quiz.Session:JoinHost(row.game.hostName, row.game.session)
                self.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
                self:Refresh()
            end)
        end
        local game = games[index]
        local gameKey = game.hostName .. ":" .. game.session
        Controls:SetScrollingText(
            row.detailViewport,
            L.W_GAME_DETAIL_F:format(game.packName, game.players),
            row.gameKey ~= gameKey
        )
        row.gameKey = gameKey
        row.game = game
        Place(row, self.gamesContent, 0, -(index - 1) * ROW_HEIGHT, CONTENT_WIDTH, ROW_HEIGHT)
        row.host:SetText(game.hostName)
        local joined = Quiz.Session.client ~= nil
            and view.state ~= "disconnected"
            and (view.hostName or ""):lower() == game.hostName:lower()
            and view.session == game.session
        row.join:SetText(joined and L.W_JOINED or L.W_JOIN)
        Controls:SetButtonState(row.join, not game.preview and not joined and not Quiz.Main:IsRestricted(), joined)
        row:Show()
        self.gameRows[index] = row
    end
    PixelUtil.SetHeight(self.gamesContent, GamesHeight(self.gamesScroll, count))
    scrollbar:EndLayout()
end

function UI:GetPersonalScoreLines()
    local records = Quiz.PersonalScores:GetScoreRows()
    local counts, indices, rows = {}, {}, {}
    for _, record in ipairs(records) do
        if not record.archived then
            local key = record.id .. ":" .. record.rules.version
            counts[key] = (counts[key] or 0) + 1
        end
    end
    for _, record in ipairs(records) do
        local label = L.W_ORIGINAL_RULES
        if not record.archived then
            local key = record.id .. ":" .. record.rules.version
            indices[key] = (indices[key] or 0) + 1
            label = counts[key] > 1 and L.W_RULE_VARIANT_F:format(record.rules.version, indices[key])
                or L.W_RULE_VERSION_F:format(record.rules.version)
        end
        rows[#rows + 1] = L.W_PACK_SCORE_ROW_F:format(
            L.W_PACK_RULES_TITLE_F:format(record.title, label),
            record.score,
            record.correct,
            record.incorrect,
            record.answers
        )
    end
    return rows
end

function UI:GetBoardRows(view)
    local rows = {}
    if self.boardScope == "personal" then
        return self:GetPersonalScoreLines()
    elseif self.boardScope == "game" then
        if view.role == "participant" then
            if view.score ~= nil then
                rows[1] = L.W_SESSION_TOTAL_F:format(view.score)
            end
        elseif Quiz.Main.game then
            for index, player in ipairs(Quiz.Main.game:GetStandings()) do
                rows[#rows + 1] =
                    L.W_BOARD_ROW_F:format(index, player.name, player.score, player.correct, player.incorrect)
            end
        end
    else
        for _, league in ipairs(Quiz.Store:GetArchivedLeagues()) do
            local standings = self.boardScope == "legacy" and Quiz.Store:GetLegacyStandings(league, "PUBLIC")
                or Quiz.Store:GetStandings(league, "PUBLIC")
            if #standings > 0 then
                rows[#rows + 1] = L.W_ARCHIVE_LEAGUE_F:format(league)
                for index = 1, math.min(BOARD_ROWS, #standings) do
                    local player = standings[index]
                    local format = self.boardScope == "legacy" and L.W_LEGACY_ROW_F or L.W_BOARD_ROW_F
                    rows[#rows + 1] = format:format(index, player.name, player.score, player.correct, player.incorrect)
                end
            end
        end
    end
    return rows
end

function UI:RefreshBoard()
    local game, view = Quiz.Main.game, Quiz.Session:GetView()
    local revision = self.boardScope == "personal" and Quiz.PersonalScores.revision or game and game.completed or 0
    if
        self.boardRevision == revision
        and self.boardGame == game
        and self.boardDatabase == Quiz.Store.db
        and self.boardSession == view.session
        and self.boardRole == view.role
        and self.boardScore == view.score
        and self.displayedBoardScope == self.boardScope
    then
        return
    end
    local scrollbar = self.boardScroll.ScrollBar
    scrollbar:BeginLayout()
    self.boardRevision, self.boardGame, self.boardDatabase = revision, game, Quiz.Store.db
    self.boardSession, self.boardRole, self.boardScore = view.session, view.role, view.score
    self.boardSwitch:Update()
    local rows = self:GetBoardRows(view)
    self.board:SetHeight(0)
    self.board:SetText(
        #rows > 0 and table.concat(rows, "\n\n")
            or self.boardScope == "personal" and L.W_NO_PERSONAL_SCORES
            or L.NO_STANDINGS
    )
    local height = math.max(MIN_FONT_HEIGHT, self.board:GetStringHeight())
    local scale = self.board:GetEffectiveScale()
    local snappedHeight = PixelUtil.GetNearestPixelSize(height, scale)
    if snappedHeight < height then
        snappedHeight = snappedHeight + PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    self.board:SetHeight(snappedHeight)
    PixelUtil.SetHeight(self.boardContent, math.max(GAME_LIST_HEIGHT, self.board:GetHeight()))
    self.boardHint:SetText(
        self.boardScope == "personal" and L.W_PERSONAL_HELP
            or self.boardScope == "league" and L.W_LEAGUE_ARCHIVE_HELP
            or self.boardScope == "legacy" and L.W_LEGACY_HELP
            or view.role == "participant" and L.W_PARTICIPANT_BOARD_HELP
            or L.W_BOARD_HELP
    )
    if self.displayedBoardScope ~= self.boardScope then
        scrollbar:ScrollTo(0, true)
        self.displayedBoardScope = self.boardScope
    end
    scrollbar:EndLayout()
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then
        return
    end
    local running = Quiz.Main:IsRunning()
    local game = Quiz.Main.game
    local view = Quiz.Session:GetView()
    self.notice:SetText(
        self.actionError
            or Quiz.Widget.actionError
            or self.tab == "play" and self.gamePreview and self.gamePreview.notice
            or view.role == "participant" and view.notice
            or Quiz.Main.notice
            or view.notice
            or L.W_SETUP_HINT
    )
    if self.tab == "play" then
        self:RefreshGames(view)
        local active = Quiz.Session.hostSession ~= nil or Quiz.Session.client ~= nil
        local sessionText = view.state == "joining" and L.W_JOINING_SESSION_F
            or view.state == "disconnected" and L.W_REJOINING_SESSION_F
            or L.W_CURRENT_SESSION_F
        self.current:SetText(active and sessionText:format(view.hostName or "") or L.W_NO_SESSION)
        Controls:SetButtonState(self.leave, active)
    elseif self.tab == "host" then
        if self.hostRulesPackId ~= self.draft.packId or self.hostRulesGame ~= (running and game or nil) then
            self:RefreshHostRules()
        end
        self.league:SetEnabled(not running)
        self.pack:SetEnabled(not running)
        Controls:SetButtonState(self.start, not running and self.hostRules ~= nil and not Quiz.Main:IsRestricted())
        Controls:SetButtonState(self.pause, running and game.state ~= "finished")
        Controls:SetButtonState(self.stop, running)
        self.pause:SetText(running and game.state == "paused" and L.W_RESUME or L.W_PAUSE)
        self.pause:SetShown(running)
        self.stop:SetShown(running)
        self.save:SetShown(not running)
    elseif self.tab == "scores" then
        self:RefreshBoard()
    end
end

local _, Games = ...
local Cards = Games.Cards
local L = Cards.L
local Controls = Games.Controls

local TABLE_WIDTH = 380
local TABLE_MAX_HEIGHT = 380
local SCREEN_MARGIN = 12
local SCREEN_MIDPOINT = 0.5
local ANCHOR_HORIZONTAL = { LEFT = 0, RIGHT = 1 }
local ANCHOR_VERTICAL = { TOP = 1, BOTTOM = 0 }
local CONTENT_WIDTH = TABLE_WIDTH
local PERCENT = 100
local BOARD_CARD_WIDTH = 44
local BOARD_CARD_HEIGHT = 30
local BOARD_CARD_GAP = 4
local POT_ICON_ATLAS = "plunderstorm-icon-plunderCoins-big"
local POT_ICON_SIZE = BOARD_CARD_HEIGHT
local POT_TEXT_GAP_PIXELS = 4
local POT_CARD_GAP_PIXELS = 4
local FLOP_CARD_COUNT = 3
local FINAL_BOARD_FLIP_SECONDS = 0.4
local TURN_HEIGHT = 18
local TIMER_BOARD_GAP_PIXELS = 10
local TIMER_TRACK_PIXELS = 2
local TIMER_FILL_OVERHANG_PIXELS = 1
local TIMER_FILL_PIXELS = TIMER_TRACK_PIXELS + TIMER_FILL_OVERHANG_PIXELS * 2
local TIMER_NOTICE_GAP_PIXELS = 6
local PLAYER_TOP_GAP_PIXELS = 8
local TIMER_GRADIENT_SHADE = 0.65
local PLAYER_ROW_HEIGHT = 26
local MIN_VISIBLE_ROWS = 0
local DEALER_CHIP_SIZE = 22
local DEALER_CHIP_GAP = 4
local DEALER_CHIP_X = -(DEALER_CHIP_SIZE + DEALER_CHIP_GAP)
local HOLE_CARDS_X = 0
local HOLE_CARD_WIDTH = 32
local HOLE_CARD_HEIGHT = 22
local HOLE_CARD_GAP = 2
local HOLE_CARDS_WIDTH = HOLE_CARD_WIDTH * 2 + HOLE_CARD_GAP
local PLAYER_NAME_X = 72
local PLAYER_NAME_WIDTH = 90
local PLAYER_BALANCE_X = 196
local PLAYER_BALANCE_WIDTH = 86
local PLAYER_GOLD_ICON_ATLAS = "coin-gold"
local PLAYER_GOLD_ICON_SIZE = 9.75
local PLAYER_GOLD_TEXT_GAP_PIXELS = 3
local PLAYER_TEXT_HEIGHT = 18
local PLAYER_STATUS_WIDTH = 92
local CONTROL_GAP = 8
local CONTROL_HEIGHT = 24
local WAGER_HEIGHT = 12
local WAGER_CONTROL_GAP = 2
local WAGER_TRACK_PIXELS = 2
local WAGER_THUMB_WIDTH_PIXELS = 3
local WAGER_THUMB_HEIGHT_PIXELS = 10
local WAGER_THUMB_TEXTURE = 130871
local WAGER_MAX_STEPS = 100
local WAGER_DISABLED_ALPHA = 0.5
local ACTION_GAP = 6
local FOLD_WIDTH = 52
local CALL_WIDTH = 82
local RAISE_WIDTH = 76
local ALL_IN_WIDTH = 56
local UTILITY_WIDTH = 106
local UTILITY_GAP = 10
local PRESS_PIXELS = 1
local PRESS_ALPHA = 0.8
local TEXT_SHADOW_PIXELS = 2
local PLAYER_TRANSITION_SECONDS = 0.2
local PLAYER_TRANSITION_EDGE = 0.05
local EDIT_OUTSET = 8
local FONT_NORMAL = "normal"
local FONT_SMALL = "small"
local FONT_OBJECT_NAMES = {
    [FONT_NORMAL] = "OrbitGamesCardsTableFont",
    [FONT_SMALL] = "OrbitGamesCardsTableSmallFont",
}
local FONT_SOURCES = {
    [FONT_NORMAL] = GameFontHighlight,
    [FONT_SMALL] = GameFontHighlightSmall,
}
local ACTIVE_HAND_STATES = { preflop = true, flop = true, turn = true, river = true }
local COLORS = {
    text = { 1, 1, 1, 1 },
    shadow = { 0, 0, 0, 1 },
    hover = { 1, 0.94, 0.55, 1 },
    selected = { 1, 0.82, 0, 1 },
    muted = { 0.6, 0.6, 0.6, 1 },
    activeRow = { 1, 0.82, 0, 0.18 },
    timerTrack = { 1, 1, 1, 0.15 },
    wagerTrack = { 1, 1, 1, 0.3 },
    timeout = { 1, 0.16, 0.08, 1 },
    edit = { 0.7, 0.6, 1, 1 },
}
local HAND_CATEGORY_LABELS = {
    high_card = L.W_HAND_HIGH_CARD,
    one_pair = L.W_HAND_ONE_PAIR,
    two_pair = L.W_HAND_TWO_PAIR,
    three_of_a_kind = L.W_HAND_THREE_OF_A_KIND,
    straight = L.W_HAND_STRAIGHT,
    flush = L.W_HAND_FLUSH,
    full_house = L.W_HAND_FULL_HOUSE,
    four_of_a_kind = L.W_HAND_FOUR_OF_A_KIND,
    straight_flush = L.W_HAND_STRAIGHT_FLUSH,
}

Cards.Table = {}
local Table = Cards.Table

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function ResolveGrowth(x, y)
    local horizontal = x < SCREEN_MIDPOINT and "LEFT" or "RIGHT"
    return horizontal, y >= SCREEN_MIDPOINT and "TOP" or "BOTTOM"
end

local function ApplyTextShadow(label)
    local offset = PixelUtil.GetNearestPixelSize(0, label:GetEffectiveScale(), TEXT_SHADOW_PIXELS)
    label:SetShadowColor(unpack(COLORS.shadow))
    label:SetShadowOffset(offset, -offset)
end

local function BindFont(label, font)
    local red, green, blue, alpha = label:GetTextColor()
    local horizontal, vertical = label:GetJustifyH(), label:GetJustifyV()
    label:SetFontObject(font)
    label:SetTextColor(red, green, blue, alpha)
    label:SetJustifyH(horizontal)
    label:SetJustifyV(vertical)
end

local function ErrorText(reason)
    local message = L.errors[reason]
    if message then
        return message
    end
    return type(reason) == "string" and reason:find("%s") and reason or L.W_ACTION_FAILED
end

local function FormatAmount(amount)
    return Cards.Gold:Format(amount or 0)
end

local function FormatSignedAmount(amount)
    return Cards.Gold:FormatSigned(amount)
end

local function FindSeat(view, playerId)
    for _, seat in ipairs(view.seats or {}) do
        if seat.id == playerId then
            return seat
        end
    end
end

local function SeatMap(view)
    local byNumber = {}
    for _, seat in ipairs(view.seats or {}) do
        byNumber[seat.seat] = seat
    end
    return byNumber
end

local function SeatPayout(view, seat)
    return seat.payout or view.settlement and view.settlement.payouts and view.settlement.payouts[seat.seat] or 0
end

local function SeatRefund(view, seat)
    return seat.refund or view.settlement and view.settlement.refunds and view.settlement.refunds[seat.seat] or 0
end

local function ActiveStreet(view)
    if ACTIVE_HAND_STATES[view.state] then
        return view.state
    end
    return ACTIVE_HAND_STATES[view.baseState] and view.baseState or nil
end

local function HasSettlement(view)
    if view.settlement then
        return true
    end
    for _, seat in ipairs(view.seats or {}) do
        if seat.payout ~= nil or seat.refund ~= nil then
            return true
        end
    end
    return false
end

local function EvaluateWinner(view, seat)
    if view.showdown ~= true or not view.board or #view.board ~= 5 or not seat.holeCards or #seat.holeCards ~= 2 then
        return nil
    end
    local cards = { seat.holeCards[1], seat.holeCards[2] }
    for _, cardId in ipairs(view.board) do
        cards[#cards + 1] = cardId
    end
    return Cards.HandEvaluator.Evaluate(cards)
end

local function SettlementWinners(view)
    local winners = {}
    for _, seat in ipairs(view.seats or {}) do
        local payout = SeatPayout(view, seat)
        if payout > 0 then
            winners[#winners + 1] = {
                seat = seat,
                payout = payout,
                evaluation = EvaluateWinner(view, seat),
            }
        end
    end
    return winners
end

local function SoleWinningHand(winners, settled)
    local winner = settled and #winners == 1 and winners[1] or nil
    local evaluation = winner and winner.evaluation or nil
    if not evaluation then
        return nil, nil
    end
    local cards = {}
    for _, cardId in ipairs(evaluation.cards) do
        cards[cardId] = true
    end
    return winner, cards
end

local function IsHandActive(view, settled)
    return ActiveStreet(view) ~= nil or view.state == "paused" and view.handId ~= nil and not settled
end

local function HasAuthoritativePlayers(view)
    return type(view.seats) == "table"
end

local function ShouldShowSeat(seat)
    local folded = seat.inHand == true and seat.folded == true
    return seat.connected ~= false and not folded
end

local function PreviewView()
    local hostSettings = Cards.Store:GetHostSettings()
    return {
        role = "preview",
        state = "between_hands",
        rules = hostSettings,
        seats = {},
        board = {},
        actions = {},
        pot = 0,
    }
end

local function SetTextButtonPressed(button, pressed)
    pressed = pressed == true
    if button.pressed == pressed then
        return
    end
    button.pressed = pressed
    local offset = pressed and PixelUtil.GetNearestPixelSize(0, button.Label:GetEffectiveScale(), PRESS_PIXELS) or 0
    button.Label:ClearAllPoints()
    PixelUtil.SetPoint(button.Label, "TOPLEFT", button, "TOPLEFT", offset, -offset)
    PixelUtil.SetPoint(button.Label, "BOTTOMRIGHT", button, "BOTTOMRIGHT", offset, -offset)
    button.Label:SetAlpha(pressed and PRESS_ALPHA or 1)
end

local function PaintTextButton(button)
    local color = button.controlEnabled and button.hovered and COLORS.hover
        or button.controlEnabled and COLORS.text
        or COLORS.muted
    button.Text:SetTextColor(unpack(color))
end

local function SetTextButtonState(button, enabled)
    button.controlEnabled = enabled == true
    button:SetEnabled(button.controlEnabled)
    if not button.controlEnabled then
        button.hovered = false
        SetTextButtonPressed(button, false)
    end
    PaintTextButton(button)
end

local function SetTextButtonText(button, text)
    Controls:SetScrollingText(button.Label, text)
end

local function TimerUpdate()
    local ok, failure = pcall(Table.UpdateTimer, Table)
    if not ok then
        Table.timer:SetScript("OnUpdate", nil)
        geterrorhandler()(failure)
    end
end

local function PlayerLayoutUpdate(_, elapsed)
    local ok, failure = pcall(Table.UpdatePlayerLayout, Table, elapsed)
    if not ok then
        Table.playerList:SetScript("OnUpdate", nil)
        geterrorhandler()(failure)
    end
end

function Table:TrackSize(region, width, height, minimumWidth, minimumHeight)
    self.staticLayouts[#self.staticLayouts + 1] = {
        region = region,
        width = width,
        height = height,
        minimumWidth = minimumWidth,
        minimumHeight = minimumHeight,
    }
    PixelUtil.SetSize(region, width, height, minimumWidth, minimumHeight)
end

function Table:TrackPoint(region, point, relative, relativePoint, x, y)
    self.staticLayouts[#self.staticLayouts + 1] = {
        region = region,
        point = point,
        relative = relative,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    PixelUtil.SetPoint(region, point, relative, relativePoint, x, y)
end

function Table:TrackText(label, role)
    self.shadowLabels[#self.shadowLabels + 1] = label
    self.fontTargets[#self.fontTargets + 1] = { label = label, role = role or FONT_NORMAL }
end

function Table:RefreshTextShadows()
    local offset = PixelUtil.GetNearestPixelSize(0, self.frame:GetEffectiveScale(), TEXT_SHADOW_PIXELS)
    for _, font in pairs(self.fontObjects) do
        font:SetShadowColor(unpack(COLORS.shadow))
        font:SetShadowOffset(offset, -offset)
    end
    for _, label in ipairs(self.shadowLabels) do
        ApplyTextShadow(label)
    end
end

function Table:ApplyFonts(path)
    local _, probeHeight, probeFlags = GameFontHighlight:GetFont()
    local applied = true
    if path then
        local ok, result = pcall(self.fontProbe.SetFont, self.fontProbe, path, probeHeight, probeFlags)
        applied = ok and result == true
    end
    for role, font in pairs(self.fontObjects) do
        local source = FONT_SOURCES[role]
        local nativePath, height, flags = source:GetFont()
        font:CopyFontObject(source)
        font:SetFont(applied and path or nativePath, height, flags)
    end
    for _, target in ipairs(self.fontTargets) do
        BindFont(target.label, self.fontObjects[target.role])
    end
    self.fontsApplied, self.fontPath = applied, applied and path or nil
end

function Table:RefreshStaticLayout()
    for _, layout in ipairs(self.staticLayouts) do
        if layout.width then
            PixelUtil.SetSize(layout.region, layout.width, layout.height, layout.minimumWidth, layout.minimumHeight)
        else
            PixelUtil.SetPoint(layout.region, layout.point, layout.relative, layout.relativePoint, layout.x, layout.y)
        end
    end
    for _, row in ipairs(self.seats) do
        self:RefreshPlayerBalanceLayout(row)
    end
    self:RefreshWagerSliderArt()
end

function Table:RefreshWagerSliderArt()
    local slider = self.wagerSlider
    PixelUtil.SetHeight(slider, WAGER_HEIGHT, WAGER_THUMB_HEIGHT_PIXELS)
    PixelUtil.SetHeight(slider.Track, 0, WAGER_TRACK_PIXELS)
    slider.Track:ClearAllPoints()
    PixelUtil.SetPoint(slider.Track, "LEFT", slider, "LEFT", 0, 0)
    PixelUtil.SetPoint(slider.Track, "RIGHT", slider, "RIGHT", 0, 0)
    PixelUtil.SetSize(slider.Thumb, 0, 0, WAGER_THUMB_WIDTH_PIXELS, WAGER_THUMB_HEIGHT_PIXELS)
end

function Table:RefreshPlayerBalanceLayout(row)
    local gap = PixelUtil.GetNearestPixelSize(0, row:GetEffectiveScale(), PLAYER_GOLD_TEXT_GAP_PIXELS)
    row.Balance:ClearAllPoints()
    PixelUtil.SetPoint(row.Balance, "LEFT", row.GoldIcon, "RIGHT", gap, 0)
    PixelUtil.SetSize(row.Balance, PLAYER_BALANCE_WIDTH - PLAYER_GOLD_ICON_SIZE - gap, PLAYER_TEXT_HEIGHT)
end

function Table:RefreshNoticeLayout(showNotice)
    local scale = self.content:GetEffectiveScale()
    local noticeGap = PixelUtil.GetNearestPixelSize(0, scale, TIMER_NOTICE_GAP_PIXELS)
    local playerGap = PixelUtil.GetNearestPixelSize(0, scale, PLAYER_TOP_GAP_PIXELS)
    self.notice:SetShown(showNotice)
    self.notice:ClearAllPoints()
    PixelUtil.SetPoint(self.notice, "TOPLEFT", self.timer, "BOTTOMLEFT", 0, -noticeGap)
    self.playerList:ClearAllPoints()
    if showNotice then
        PixelUtil.SetPoint(self.playerList, "TOPLEFT", self.notice, "BOTTOMLEFT", 0, -playerGap)
        self.playersTop = self.playersBaseTop + noticeGap + self.notice:GetHeight() + playerGap
    else
        PixelUtil.SetPoint(self.playerList, "TOPLEFT", self.timer, "BOTTOMLEFT", 0, -playerGap)
        self.playersTop = self.playersBaseTop + playerGap
    end
end

function Table:RefreshHeaderLayout()
    local scale = self.content:GetEffectiveScale()
    local potTextGap = PixelUtil.GetNearestPixelSize(0, scale, POT_TEXT_GAP_PIXELS)
    self.pot:ClearAllPoints()
    PixelUtil.SetPoint(self.pot, "TOPLEFT", self.potIcon, "TOPRIGHT", potTextGap, 0)
    PixelUtil.SetSize(self.pot, CONTENT_WIDTH - self.potIcon:GetWidth() - potTextGap, self.potIcon:GetHeight())
    local potCardGap = PixelUtil.GetNearestPixelSize(0, scale, POT_CARD_GAP_PIXELS)
    local boardTop = self.potIcon:GetHeight() + potCardGap
    for cardIndex, card in ipairs(self.board) do
        card:ClearAllPoints()
        PixelUtil.SetPoint(
            card,
            "TOPLEFT",
            self.content,
            "TOPLEFT",
            (cardIndex - 1) * (BOARD_CARD_WIDTH + BOARD_CARD_GAP),
            -boardTop
        )
    end
    self.winnerCards[1]:ClearAllPoints()
    PixelUtil.SetPoint(self.winnerCards[1], "TOPRIGHT", self.content, "TOPRIGHT", 0, -boardTop)
    self.winnerCards[2]:ClearAllPoints()
    PixelUtil.SetPoint(self.winnerCards[2], "RIGHT", self.winnerCards[1], "LEFT", -BOARD_CARD_GAP, 0)
    local timerGap = PixelUtil.GetNearestPixelSize(0, scale, TIMER_BOARD_GAP_PIXELS)
    self.timer:ClearAllPoints()
    PixelUtil.SetPoint(self.timer, "TOPLEFT", self.board[1], "BOTTOMLEFT", 0, -timerGap)
    local trackInset = PixelUtil.GetNearestPixelSize(0, scale, TIMER_FILL_OVERHANG_PIXELS)
    self.timer.Track:ClearAllPoints()
    PixelUtil.SetPoint(self.timer.Track, "TOPLEFT", self.timer, "TOPLEFT", 0, -trackInset)
    PixelUtil.SetPoint(self.timer.Track, "BOTTOMRIGHT", self.timer, "BOTTOMRIGHT", 0, trackInset)
    self.playersBaseTop = boardTop + BOARD_CARD_HEIGHT + timerGap + self.timer:GetHeight()
    self:RefreshNoticeLayout(self.notice:IsShown())
end

function Table:CreateTextButton(parent, text, width, height, action)
    local button = CreateFrame("Button", nil, parent)
    self:TrackSize(button, width, height)
    button.controlWidth = width
    button.Label = Controls:ScrollingLabel(button, text, "GameFontHighlight")
    button.Label:SetAllPoints(button)
    button.Text = button.Label.Text
    button.Text:SetJustifyH("CENTER")
    button.Text:SetJustifyV("MIDDLE")
    Controls:SetScrollingInsets(button.Label, TEXT_SHADOW_PIXELS, TEXT_SHADOW_PIXELS)
    self:TrackText(button.Text)
    SetTextButtonText(button, text)
    button.controlEnabled = true
    button.NarrationGetName = function(self)
        local visibleText = self.Text:GetText() or ""
        if self.narrationPrefix and visibleText ~= "" then
            return self.narrationPrefix .. " " .. visibleText
        end
        return self.narrationPrefix or visibleText
    end
    button:SetScript("OnClick", action)
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" and button.controlEnabled then
            SetTextButtonPressed(button, true)
        end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            SetTextButtonPressed(button, false)
        end
    end)
    button:SetScript("OnEnter", function()
        button.hovered = button.controlEnabled
        PaintTextButton(button)
    end)
    button:SetScript("OnLeave", function()
        button.hovered = false
        SetTextButtonPressed(button, false)
        PaintTextButton(button)
    end)
    button:SetScript("OnHide", function()
        button.hovered = false
        SetTextButtonPressed(button, false)
    end)
    button:SetScript("OnDisable", function()
        button.hovered = false
        SetTextButtonPressed(button, false)
    end)
    PaintTextButton(button)
    return button
end

function Table:SetWagerStep(step)
    local stepIndex = Clamp(math.floor(step + 0.5), 0, self.wagerSteps)
    local target = self.wagerMinimum
    if self.wagerSteps > 0 then
        target = target + math.floor((self.wagerMaximum - target) * stepIndex / self.wagerSteps + 0.5)
    end
    self.wagerTarget = target
    SetTextButtonText(self.raise, FormatAmount(target))
end

function Table:ConfigureWager(minimum, maximum)
    self.wagerMinimum = minimum
    self.wagerMaximum = maximum
    self.wagerSteps = math.min(maximum - minimum, WAGER_MAX_STEPS)
    self.wagerSlider:SetMinMaxValues(0, self.wagerSteps)
    self.wagerSlider:SetValueStep(1)
    self.wagerSlider:SetValue(0)
    self:SetWagerStep(0)
end

function Table:SetWagerEnabled(enabled)
    local interactive = enabled and self.wagerSteps > 0
    self.wagerSlider:SetEnabled(interactive)
    self.wagerSlider:SetAlpha(interactive and 1 or WAGER_DISABLED_ALPHA)
end

function Table:CreateWagerSlider(parent)
    local slider = CreateFrame("Slider", nil, parent)
    Mixin(slider, NarrationSliderMixin)
    PixelUtil.SetHeight(slider, WAGER_HEIGHT, WAGER_THUMB_HEIGHT_PIXELS)
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(0)
    slider.Track = slider:CreateTexture(nil, "BACKGROUND")
    slider.Track:SetColorTexture(unpack(COLORS.wagerTrack))
    slider:SetThumbTexture(WAGER_THUMB_TEXTURE)
    slider.Thumb = slider:GetThumbTexture()
    slider.Thumb:SetColorTexture(unpack(COLORS.selected))
    slider:SetScript("OnValueChanged", function(_, step)
        self:SetWagerStep(step)
    end)
    slider:Hide()
    return slider
end

function Table:CreatePlayerRow(rowIndex)
    local row = CreateFrame("Frame", nil, self.playerList)
    self:TrackSize(row, CONTENT_WIDTH, PLAYER_ROW_HEIGHT)
    row.Number = rowIndex
    row.ActiveBackground = row:CreateTexture(nil, "BACKGROUND")
    row.ActiveBackground:SetAllPoints(row)
    row.ActiveBackground:SetColorTexture(unpack(COLORS.activeRow))
    row.ActiveBackground:Hide()
    row.PlayerTransition = row:CreateAnimationGroup()
    row.PlayerTransition:SetLooping("NONE")
    row.PlayerTransition.Scale = row.PlayerTransition:CreateAnimation("Scale")
    row.PlayerTransition.Scale:SetOrigin("TOP", 0, 0)
    row.PlayerTransition:SetScript("OnFinished", function()
        self:FinishPlayerTransition(row)
    end)
    row.DealerChip = Cards.CardArt:CreateDealerChip(row)
    self:TrackSize(row.DealerChip, DEALER_CHIP_SIZE, DEALER_CHIP_SIZE)
    self:TrackPoint(row.DealerChip, "LEFT", row, "LEFT", DEALER_CHIP_X, 0)
    row.DealerChip:Hide()
    row.Cards = {}
    for cardIndex = 1, 2 do
        local card = Cards.CardArt:Create(row, HOLE_CARD_WIDTH, HOLE_CARD_HEIGHT)
        self:TrackSize(card, HOLE_CARD_WIDTH, HOLE_CARD_HEIGHT)
        self:TrackPoint(
            card,
            "LEFT",
            row,
            "LEFT",
            HOLE_CARDS_X + (cardIndex - 1) * (HOLE_CARD_WIDTH + HOLE_CARD_GAP),
            0
        )
        row.Cards[cardIndex] = card
    end
    row.Name = Controls:ScrollingLabel(row, "", "GameFontHighlight")
    row.Name.Text:SetJustifyV("MIDDLE")
    Controls:SetScrollingInsets(row.Name, 0, TEXT_SHADOW_PIXELS)
    self:TrackText(row.Name.Text)
    self:TrackSize(row.Name, PLAYER_NAME_WIDTH, PLAYER_TEXT_HEIGHT)
    self:TrackPoint(row.Name, "LEFT", row, "LEFT", PLAYER_NAME_X, 0)
    row.GoldIcon = row:CreateTexture(nil, "ARTWORK")
    row.GoldIcon:SetAtlas(PLAYER_GOLD_ICON_ATLAS, true)
    self:TrackSize(row.GoldIcon, PLAYER_GOLD_ICON_SIZE, PLAYER_GOLD_ICON_SIZE)
    self:TrackPoint(row.GoldIcon, "LEFT", row, "LEFT", PLAYER_BALANCE_X, 0)
    row.Balance = Controls:ScrollingLabel(row, "", "GameFontHighlightSmall")
    row.Balance.Text:SetJustifyH("LEFT")
    row.Balance.Text:SetJustifyV("MIDDLE")
    row.Balance.Text:SetTextColor(unpack(COLORS.text))
    Controls:SetScrollingInsets(row.Balance, 0, TEXT_SHADOW_PIXELS)
    self:TrackText(row.Balance.Text, FONT_SMALL)
    self:RefreshPlayerBalanceLayout(row)
    row.Status = Controls:ScrollingLabel(row, "", "GameFontHighlightSmall")
    row.Status.Text:SetJustifyH("RIGHT")
    row.Status.Text:SetJustifyV("MIDDLE")
    row.Status.Text:SetTextColor(unpack(COLORS.muted))
    Controls:SetScrollingInsets(row.Status, 0, TEXT_SHADOW_PIXELS)
    self:TrackText(row.Status.Text, FONT_SMALL)
    self:TrackSize(row.Status, PLAYER_STATUS_WIDTH, PLAYER_TEXT_HEIGHT)
    self:TrackPoint(row.Status, "RIGHT", row, "RIGHT", 0, 0)
    row.layoutHeight = 0
    row:Hide()
    self.seats[rowIndex] = row
end

function Table:Create()
    if self.frame then
        return
    end
    self.settings = Cards.Store:GetTableSettings()
    self.frame = CreateFrame("Frame", "OrbitGamesCardsTableFrame", UIParent)
    PixelUtil.SetSize(self.frame, TABLE_WIDTH, TABLE_MAX_HEIGHT)
    self.frame:SetMovable(false)
    self.frame:Hide()
    self.staticLayouts = {}
    self.shadowLabels = {}
    self.fontTargets = {}
    self.fontObjects = {
        [FONT_NORMAL] = CreateFont(FONT_OBJECT_NAMES[FONT_NORMAL]),
        [FONT_SMALL] = CreateFont(FONT_OBJECT_NAMES[FONT_SMALL]),
    }
    self.layoutHeight = TABLE_MAX_HEIGHT
    self.content = CreateFrame("Frame", nil, self.frame)
    PixelUtil.SetSize(self.content, TABLE_WIDTH, TABLE_MAX_HEIGHT)
    self.fontProbe = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.fontProbe:Hide()

    self.board = {}
    for cardIndex = 1, 5 do
        local card = Cards.CardArt:Create(self.content, BOARD_CARD_WIDTH, BOARD_CARD_HEIGHT)
        if cardIndex > FLOP_CARD_COUNT then
            Cards.CardArt:SetFlipDuration(card, FINAL_BOARD_FLIP_SECONDS)
        end
        self:TrackSize(card, BOARD_CARD_WIDTH, BOARD_CARD_HEIGHT)
        self.board[cardIndex] = card
    end
    self.winnerCards = {}
    for cardIndex = 1, 2 do
        local card = Cards.CardArt:Create(self.content, BOARD_CARD_WIDTH, BOARD_CARD_HEIGHT)
        self:TrackSize(card, BOARD_CARD_WIDTH, BOARD_CARD_HEIGHT)
        card:Hide()
        self.winnerCards[cardIndex] = card
    end
    self.potIcon = self.content:CreateTexture(nil, "ARTWORK")
    self.potIcon:SetAtlas(POT_ICON_ATLAS)
    self:TrackSize(self.potIcon, POT_ICON_SIZE, POT_ICON_SIZE)
    self:TrackPoint(self.potIcon, "TOPLEFT", self.content, "TOPLEFT", 0, 0)
    self.pot = Controls:ScrollingLabel(self.content, "", "GameFontHighlight")
    self.pot.Text:SetJustifyH("LEFT")
    self.pot.Text:SetJustifyV("MIDDLE")
    self.pot.Text:SetTextColor(unpack(COLORS.selected))
    Controls:SetScrollingInsets(self.pot, 0, TEXT_SHADOW_PIXELS)
    self:TrackText(self.pot.Text)
    self.notice = Controls:Label(self.content, "", "GameFontHighlight")
    self.notice:SetJustifyH("LEFT")
    self.notice:SetMaxLines(1)
    self.notice:SetWordWrap(false)
    self:TrackText(self.notice)
    self:TrackSize(self.notice, CONTENT_WIDTH, TURN_HEIGHT)

    self.timer = CreateFrame("StatusBar", nil, self.content)
    self:TrackSize(self.timer, CONTENT_WIDTH, 0, nil, TIMER_FILL_PIXELS)
    self.timer.Fill = self.timer:CreateTexture(nil, "ARTWORK")
    self.timer.Fill:SetColorTexture(unpack(COLORS.text))
    self.timer:SetStatusBarTexture(self.timer.Fill)
    self.timer:SetStatusBarColor(unpack(COLORS.text))
    self.timer.startColor = CreateColor(unpack(COLORS.selected))
    self.timer.endColor = CreateColor(unpack(COLORS.selected))
    self.timer.Track = self.timer:CreateTexture(nil, "BACKGROUND")
    self.timer.Track:SetColorTexture(unpack(COLORS.timerTrack))

    self.playerList = CreateFrame("Frame", nil, self.content)
    self:TrackSize(self.playerList, CONTENT_WIDTH, PLAYER_ROW_HEIGHT * Cards.MAX_PLAYERS)
    self.seats = {}
    self.playerRows = {}
    self.playerRowOrder = {}
    self.playerRowsInitialized = false
    self.playerSession = nil
    for rowIndex = 1, Cards.MAX_PLAYERS do
        self:CreatePlayerRow(rowIndex)
    end

    self.controlBar = CreateFrame("Frame", nil, self.content)
    self:TrackSize(self.controlBar, CONTENT_WIDTH, CONTROL_HEIGHT)
    self.actionBar = self.controlBar
    self.wagerMinimum = 0
    self.wagerMaximum = 1
    self.wagerSteps = 1
    self.wagerTarget = 0
    self.fold = self:CreateTextButton(self.controlBar, L.W_FOLD, FOLD_WIDTH, CONTROL_HEIGHT, function()
        self:Act("fold")
    end)
    self.call = self:CreateTextButton(self.controlBar, L.W_CHECK, CALL_WIDTH, CONTROL_HEIGHT, function()
        self:Act(self.callAction)
    end)
    self.raise = self:CreateTextButton(self.controlBar, "", RAISE_WIDTH, CONTROL_HEIGHT, function()
        self:Act(self.raiseAction, self.wagerTarget)
    end)
    self.raise.narrationPrefix = L.W_WAGER
    self.allIn = self:CreateTextButton(self.controlBar, L.W_ALL_IN, ALL_IN_WIDTH, CONTROL_HEIGHT, function()
        self:Act("all_in")
    end)
    self.wagerSlider = self:CreateWagerSlider(self.content)
    self.wagerSlider.narrationLabel = L.W_WAGER
    self.wagerSlider:SetNarrationValueFormatter(function()
        return self.raise.Text:GetText()
    end)
    self.sitOut = self:CreateTextButton(self.controlBar, L.W_SIT_OUT, UTILITY_WIDTH, CONTROL_HEIGHT, function()
        local seat = FindSeat(self.view, self.view.playerId)
        local owner = self.previewDriver or Cards.Session
        local ok, reason = owner:SetSittingOut(not seat.sittingOut)
        self.actionError = not ok and ErrorText(reason) or nil
        self:Refresh()
        Games.UI:Refresh()
    end)
    self.rebuy = self:CreateTextButton(self.controlBar, L.W_REBUY, UTILITY_WIDTH, CONTROL_HEIGHT, function()
        local owner = self.previewDriver or Cards.Session
        local ok, reason = owner:Rebuy()
        self.actionError = not ok and ErrorText(reason) or nil
        self:Refresh()
        Games.UI:Refresh()
    end)
    self.deal = self:CreateTextButton(self.controlBar, L.W_NEXT_HAND, UTILITY_WIDTH, CONTROL_HEIGHT, function()
        local owner = self.previewDriver or Cards.Controller
        local ok, reason = owner:StartHand()
        self.actionError = not ok and ErrorText(reason) or nil
        self:Refresh()
        Games.UI:Refresh()
    end)

    self.editOutline = CreateFrame("Frame", nil, self.content)
    self:TrackPoint(self.editOutline, "TOPLEFT", self.content, "TOPLEFT", -EDIT_OUTSET, EDIT_OUTSET)
    self:TrackPoint(self.editOutline, "BOTTOMRIGHT", self.content, "BOTTOMRIGHT", EDIT_OUTSET, -EDIT_OUTSET)
    Controls:Outline(self.editOutline, COLORS.edit)
    self.editOutline:EnableMouse(false)
    self.editOutline:Hide()
    self.dragHandle = CreateFrame("Frame", nil, self.content)
    PixelUtil.SetPoint(self.dragHandle, "TOPLEFT", self.board[1], "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(self.dragHandle, "BOTTOMRIGHT", self.board[5], "BOTTOMRIGHT", 0, 0)
    self.dragHandle:RegisterForDrag("LeftButton")
    self.dragHandle:SetScript("OnDragStart", function()
        self:StartDrag()
    end)
    self.dragHandle:SetScript("OnDragStop", function()
        if self:StopDrag() then
            self:Refresh()
        end
    end)
    self.dragHandle:EnableMouse(false)
    self.frame:SetScript("OnHide", function()
        self:StopDrag()
        self:ResetPlayerPresentation(nil)
        self.timer:SetScript("OnUpdate", nil)
        self.timerPaused = nil
    end)
    self:ApplySettings()
end

function Table:StartDrag()
    if not self.editing or self.dragging then
        return
    end
    self.dragging = true
    self.frame:StartMoving()
end

function Table:ResolveLayout(x, y, screenWidth, screenHeight, width, height)
    local horizontal, vertical = ResolveGrowth(x, y)
    local anchorX, anchorY = x * screenWidth, y * screenHeight
    local left = anchorX - width * ANCHOR_HORIZONTAL[horizontal]
    local bottom = anchorY - height * ANCHOR_VERTICAL[vertical]
    local marginX = math.min(SCREEN_MARGIN, math.max(0, (screenWidth - width) / 2))
    local marginY = math.min(SCREEN_MARGIN, math.max(0, (screenHeight - height) / 2))
    local clampedLeft = Clamp(left, marginX, screenWidth - width - marginX)
    local clampedBottom = Clamp(bottom, marginY, screenHeight - height - marginY)
    anchorX, anchorY = anchorX + clampedLeft - left, anchorY + clampedBottom - bottom
    return {
        horizontal = horizontal,
        vertical = vertical,
        point = vertical .. horizontal,
        x = anchorX / screenWidth,
        y = anchorY / screenHeight,
        left = clampedLeft,
        bottom = clampedBottom,
        width = width,
        height = height,
    }
end

function Table:StopDrag()
    if not self.dragging then
        return false
    end
    local left, bottom, width, height = self.content:GetScaledRect()
    local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
    self.frame:StopMovingOrSizing()
    self.dragging = false
    local hasPosition = left
        and bottom
        and width
        and height
        and screenLeft
        and screenBottom
        and screenWidth
        and screenHeight
        and screenWidth > 0
        and screenHeight > 0
    if hasPosition then
        local centerX = (left + width / 2 - screenLeft) / screenWidth
        local centerY = (bottom + height / 2 - screenBottom) / screenHeight
        local horizontal, vertical = ResolveGrowth(centerX, centerY)
        self.settings.x = Clamp((left + width * ANCHOR_HORIZONTAL[horizontal] - screenLeft) / screenWidth, 0, 1)
        self.settings.y = Clamp((bottom + height * ANCHOR_VERTICAL[vertical] - screenBottom) / screenHeight, 0, 1)
    end
    self:ApplyPosition()
    if hasPosition and self.layout then
        self.settings.x, self.settings.y = self.layout.x, self.layout.y
        local ok, reason = Cards.Store:SaveTableSettings({ x = self.settings.x, y = self.settings.y })
        self.actionError = not ok and ErrorText(reason) or nil
    end
    return true
end

function Table:GetScreenSize()
    local scale = self.frame:GetScale()
    return UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
end

function Table:ApplyPosition()
    local layout = self.layout
    if not self.dragging then
        local screenWidth, screenHeight = self:GetScreenSize()
        if not screenWidth or not screenHeight or screenWidth <= 0 or screenHeight <= 0 then
            return
        end
        PixelUtil.SetSize(self.frame, self.content:GetSize())
        layout = self:ResolveLayout(
            self.settings.x,
            self.settings.y,
            screenWidth,
            screenHeight,
            self.content:GetWidth(),
            self.content:GetHeight()
        )
        self.layout = layout
        self.frame:ClearAllPoints()
        PixelUtil.SetPoint(self.frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", layout.left, layout.bottom)
    end
    local horizontalOffset = (self.frame:GetWidth() - self.content:GetWidth()) * ANCHOR_HORIZONTAL[layout.horizontal]
    local verticalOffset = (self.frame:GetHeight() - self.content:GetHeight()) * ANCHOR_VERTICAL[layout.vertical]
    self.content:ClearAllPoints()
    PixelUtil.SetPoint(self.content, "BOTTOMLEFT", self.frame, "BOTTOMLEFT", horizontalOffset, verticalOffset)
end

function Table:ApplySettings()
    if not self.frame then
        return
    end
    self:StopDrag()
    self.settings = Cards.Store:GetTableSettings()
    local path = Games.Media:ResolveFont(self.settings.font)
    local fontChanged = not self.fontsApplied or self.fontPath ~= path
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local requestedScale = self.settings.scale / PERCENT
    local fitScale = math.min(
        (screenWidth - (SCREEN_MARGIN + EDIT_OUTSET) * 2) / TABLE_WIDTH,
        (screenHeight - (SCREEN_MARGIN + EDIT_OUTSET) * 2) / TABLE_MAX_HEIGHT
    )
    self.frame:SetScale(math.max(0.1, math.min(requestedScale, fitScale)))
    PixelUtil.SetSize(self.content, TABLE_WIDTH, self.layoutHeight)
    self:RefreshStaticLayout()
    self:RefreshHeaderLayout()
    if fontChanged then
        self:ApplyFonts(path)
    end
    self:RefreshTextShadows()
    Controls:RefreshScale()
    self:ApplyPosition()
    self:Refresh()
end

function Table:OnDisplayChanged()
    if not self.frame then
        return
    end
    self:ApplySettings()
    Controls:Outline(self.editOutline, COLORS.edit)
end

function Table:SetEditing(editing)
    self:Create()
    if not editing then
        self:StopDrag()
    end
    self.editing = editing == true
    self.frame:SetMovable(self.editing)
    self.dragHandle:EnableMouse(self.editing)
    self.editOutline:SetShown(self.editing)
    self:Refresh()
end

function Table:SetPreviewDriver(driver)
    if driver and (Cards.Session:IsActive() or self.dragging) then
        return false
    end
    if not driver and not self.previewDriver then
        return true
    end
    if driver then
        self:Create()
    end
    self.previewDriver = driver
    self.actionError = nil
    self:Refresh()
    return true
end

function Table:Act(action, targetAmount)
    local owner = self.previewDriver or Cards.Session
    local ok, reason = owner:Act(action, targetAmount)
    self.actionError = not ok and ErrorText(reason) or nil
    self:Refresh()
    Games.UI:Refresh()
end

function Table:RenderTimer(remaining)
    local fraction = Clamp(remaining / self.timerDuration, 0, 1)
    local red = COLORS.timeout[1] + (COLORS.selected[1] - COLORS.timeout[1]) * fraction
    local green = COLORS.timeout[2] + (COLORS.selected[2] - COLORS.timeout[2]) * fraction
    local blue = COLORS.timeout[3] + (COLORS.selected[3] - COLORS.timeout[3]) * fraction
    self.timer:SetValue(remaining)
    self.timer.startColor:SetRGBA(
        red * TIMER_GRADIENT_SHADE,
        green * TIMER_GRADIENT_SHADE,
        blue * TIMER_GRADIENT_SHADE,
        1
    )
    self.timer.endColor:SetRGBA(red, green, blue, 1)
    self.timer.Fill:SetGradient("HORIZONTAL", self.timer.startColor, self.timer.endColor)
end

function Table:UpdateTimer()
    local deadline = self.view and self.view.actionDeadline
    if self.view and self.view.state == "paused" then
        self.timer:SetScript("OnUpdate", nil)
        return
    end
    if not deadline then
        self:RenderTimer(0)
        self.timer:SetScript("OnUpdate", nil)
        return
    end
    local remaining = math.max(0, deadline - GetTime())
    self:RenderTimer(remaining)
    if remaining == 0 then
        self.timer:SetScript("OnUpdate", nil)
    end
end

function Table:ResetPlayerPresentation(session)
    if self.playerList then
        self.playerList:SetScript("OnUpdate", nil)
    end
    for _, row in ipairs(self.seats or {}) do
        if row.PlayerTransition:IsPlaying() then
            row.PlayerTransition:Stop()
        end
        row.playerId = nil
        row.seatNumber = nil
        row.layoutHeight = 0
        row.transitionPlayerId = nil
        row.transitionStartHeight = nil
        row.transitionTargetHeight = nil
        row.transitionElapsed = nil
        row.transitionDuration = nil
        row.releaseAfterTransition = nil
        row:Hide()
        row.ActiveBackground:Hide()
        row.DealerChip:Hide()
        for _, card in ipairs(row.Cards) do
            Cards.CardArt:Set(card, nil, false)
            card:Hide()
        end
    end
    self.playerRows = {}
    self.playerRowOrder = {}
    self.playerRowsInitialized = false
    self.playerSession = session
end

function Table:HasPlayerTransition()
    for _, row in ipairs(self.seats) do
        if row.transitionTargetHeight ~= nil and row.PlayerTransition:IsPlaying() then
            return true
        end
    end
    return false
end

function Table:RemovePlayerRow(row)
    if self.playerRows[row.playerId] == row then
        self.playerRows[row.playerId] = nil
    end
    for rowIndex, orderedRow in ipairs(self.playerRowOrder) do
        if orderedRow == row then
            table.remove(self.playerRowOrder, rowIndex)
            break
        end
    end
    row.playerId = nil
    row.seatNumber = nil
    row.layoutHeight = 0
    row.releaseAfterTransition = nil
    row:Hide()
    row.ActiveBackground:Hide()
    row.DealerChip:Hide()
end

function Table:FinishPlayerTransition(row)
    local playerId = row.transitionPlayerId
    local targetHeight = row.transitionTargetHeight
    if not playerId or row.playerId ~= playerId or targetHeight == nil then
        return
    end
    local release = targetHeight == 0 and row.releaseAfterTransition == true
    row.layoutHeight = targetHeight
    row.transitionPlayerId = nil
    row.transitionStartHeight = nil
    row.transitionTargetHeight = nil
    row.transitionElapsed = nil
    row.transitionDuration = nil
    row.releaseAfterTransition = nil
    row:SetShown(targetHeight > 0)
    if targetHeight == 0 then
        row.ActiveBackground:Hide()
    end
    if release then
        self:RemovePlayerRow(row)
    end
    self:RelayoutPlayerRows(true)
    if not self:HasPlayerTransition() then
        self.playerList:SetScript("OnUpdate", nil)
    end
    if release and not self.layoutPlayersActive and self.view and self.frame:IsShown() then
        self:Render(self.view)
    end
end

function Table:StartPlayerTransition(row, targetHeight, release)
    if row.transitionTargetHeight == targetHeight and row.PlayerTransition:IsPlaying() then
        row.releaseAfterTransition = release == true
        return
    end
    if row.PlayerTransition:IsPlaying() then
        row.PlayerTransition:Stop()
    end
    local startHeight = row.layoutHeight
    if startHeight == targetHeight then
        row.transitionPlayerId = nil
        row.transitionStartHeight = nil
        row.transitionTargetHeight = nil
        row.transitionElapsed = nil
        row.transitionDuration = nil
        row.releaseAfterTransition = nil
        row:SetShown(targetHeight > 0)
        if targetHeight == 0 then
            row.ActiveBackground:Hide()
        end
        if release then
            self:RemovePlayerRow(row)
        end
        if not self:HasPlayerTransition() then
            self.playerList:SetScript("OnUpdate", nil)
        end
        return
    end
    local duration = PLAYER_TRANSITION_SECONDS * math.abs(targetHeight - startHeight) / PLAYER_ROW_HEIGHT
    local startScale = math.max(PLAYER_TRANSITION_EDGE, startHeight / PLAYER_ROW_HEIGHT)
    local targetScale = math.max(PLAYER_TRANSITION_EDGE, targetHeight / PLAYER_ROW_HEIGHT)
    row.transitionPlayerId = row.playerId
    row.transitionStartHeight = startHeight
    row.transitionTargetHeight = targetHeight
    row.transitionElapsed = 0
    row.transitionDuration = duration
    row.releaseAfterTransition = release == true
    row.PlayerTransition.Scale:SetDuration(duration)
    row.PlayerTransition.Scale:SetScaleFrom(1, startScale)
    row.PlayerTransition.Scale:SetScaleTo(1, targetScale)
    row.PlayerTransition.Scale:SetSmoothing("NONE")
    row:SetShown(true)
    if targetHeight == 0 then
        row.ActiveBackground:Hide()
        if release then
            row.DealerChip:Hide()
        end
    end
    row.PlayerTransition:Play()
    self.playerList:SetScript("OnUpdate", PlayerLayoutUpdate)
end

function Table:RelayoutPlayerRows(updateContent)
    local top = 0
    for _, row in ipairs(self.playerRowOrder) do
        row:ClearAllPoints()
        PixelUtil.SetPoint(row, "TOPLEFT", self.playerList, "TOPLEFT", 0, -top)
        top = top + row.layoutHeight
    end
    self.playersHeight = math.max(MIN_VISIBLE_ROWS * PLAYER_ROW_HEIGHT, top)
    PixelUtil.SetSize(self.playerList, CONTENT_WIDTH, self.playersHeight)
    if updateContent then
        self:LayoutActionArea()
        self:LayoutContent(self.controlBar:IsShown(), self.wagerSlider:IsShown())
    end
end

function Table:UpdatePlayerLayout(elapsed)
    local changed = false
    for _, row in ipairs(self.playerRowOrder) do
        if row.transitionTargetHeight ~= nil and row.PlayerTransition:IsPlaying() then
            row.transitionElapsed = math.min(row.transitionDuration, row.transitionElapsed + elapsed)
            local progress = row.transitionElapsed / row.transitionDuration
            local height = row.transitionStartHeight
                + (row.transitionTargetHeight - row.transitionStartHeight) * progress
            if height ~= row.layoutHeight then
                row.layoutHeight = height
                changed = true
            end
        end
    end
    if changed then
        self:RelayoutPlayerRows(true)
    end
end

function Table:FindPlayerRowOrder(row)
    for rowIndex, orderedRow in ipairs(self.playerRowOrder) do
        if orderedRow == row then
            return rowIndex
        end
    end
end

function Table:InsertPlayerRow(row, playerId, ordered)
    local desiredIndex
    for seatIndex, seat in ipairs(ordered) do
        if seat.id == playerId then
            desiredIndex = seatIndex
            break
        end
    end
    for seatIndex = desiredIndex + 1, #ordered do
        local nextRow = self.playerRows[ordered[seatIndex].id]
        local nextIndex = nextRow and self:FindPlayerRowOrder(nextRow)
        if nextIndex then
            table.insert(self.playerRowOrder, nextIndex, row)
            return
        end
    end
    for seatIndex = desiredIndex - 1, 1, -1 do
        local previousRow = self.playerRows[ordered[seatIndex].id]
        local previousIndex = previousRow and self:FindPlayerRowOrder(previousRow)
        if previousIndex then
            table.insert(self.playerRowOrder, previousIndex + 1, row)
            return
        end
    end
    self.playerRowOrder[#self.playerRowOrder + 1] = row
end

function Table:AcquirePlayerRow(seat, ordered)
    for _, row in ipairs(self.seats) do
        if not row.playerId then
            row.playerId = seat.id
            row.seatNumber = seat.seat
            row.layoutHeight = 0
            row.transitionPlayerId = nil
            row.transitionTargetHeight = nil
            row.releaseAfterTransition = nil
            row:Hide()
            row.ActiveBackground:Hide()
            row.DealerChip:Hide()
            for _, card in ipairs(row.Cards) do
                Cards.CardArt:Set(card, nil, false)
                card:Hide()
            end
            self.playerRows[seat.id] = row
            self:InsertPlayerRow(row, seat.id, ordered)
            return row
        end
    end
end

function Table:OrderedSeats(view, byNumber)
    local ordered = {}
    local maxPlayers = view.rules and view.rules.maxPlayers or Cards.MAX_PLAYERS
    local localSeat = FindSeat(view, view.playerId)
    if not localSeat then
        for seatNumber = 1, maxPlayers do
            if byNumber[seatNumber] then
                ordered[#ordered + 1] = byNumber[seatNumber]
            end
        end
        return ordered
    end
    for offset = 1, maxPlayers - 1 do
        local seatNumber = (localSeat.seat - 1 + offset) % maxPlayers + 1
        if byNumber[seatNumber] then
            ordered[#ordered + 1] = byNumber[seatNumber]
        end
    end
    ordered[#ordered + 1] = localSeat
    return ordered
end

function Table:LayoutPlayers(view, ordered)
    if not HasAuthoritativePlayers(view) then
        self:RelayoutPlayerRows(false)
        return
    end
    local session = view.session or view.sessionId or self.previewDriver or "preview"
    if self.playerSession ~= session then
        self:ResetPlayerPresentation(session)
    end
    local desired = {}
    for _, seat in ipairs(ordered) do
        desired[seat.id] = seat
    end
    self.layoutPlayersActive = true
    local departing = {}
    for playerId, row in pairs(self.playerRows) do
        if not desired[playerId] then
            departing[#departing + 1] = row
        end
    end
    for _, row in ipairs(departing) do
        self:StartPlayerTransition(row, 0, true)
    end
    local baseline = not self.playerRowsInitialized
    for _, seat in ipairs(ordered) do
        local row = self.playerRows[seat.id] or self:AcquirePlayerRow(seat, ordered)
        if row then
            row.seatNumber = seat.seat
            local show = ShouldShowSeat(seat)
            if baseline then
                if row.PlayerTransition:IsPlaying() then
                    row.PlayerTransition:Stop()
                end
                row.transitionPlayerId = nil
                row.transitionTargetHeight = nil
                row.releaseAfterTransition = nil
                row.layoutHeight = show and PLAYER_ROW_HEIGHT or 0
                row:SetShown(show)
            else
                self:StartPlayerTransition(row, show and PLAYER_ROW_HEIGHT or 0, false)
            end
        end
    end
    self.playerRowsInitialized = true
    self.layoutPlayersActive = false
    self:RelayoutPlayerRows(false)
end

function Table:LayoutActionArea()
    local top = self.playersTop + self.playersHeight + CONTROL_GAP
    self.controlBar:ClearAllPoints()
    PixelUtil.SetPoint(self.controlBar, "TOPLEFT", self.content, "TOPLEFT", 0, -top)
    self.wagerSlider:ClearAllPoints()
    PixelUtil.SetPoint(self.wagerSlider, "TOPLEFT", self.fold, "BOTTOMLEFT", 0, -WAGER_CONTROL_GAP)
    PixelUtil.SetPoint(self.wagerSlider, "TOPRIGHT", self.allIn, "BOTTOMRIGHT", 0, -WAGER_CONTROL_GAP)
end

function Table:LayoutContent(showControls, showWager)
    local height = self.playersTop + self.playersHeight
    if showControls then
        height = height + CONTROL_GAP + CONTROL_HEIGHT
        if showWager then
            height = height + self.wagerSlider:GetHeight() + WAGER_CONTROL_GAP
        end
    end
    if height ~= self.layoutHeight then
        self.layoutHeight = height
        PixelUtil.SetSize(self.content, TABLE_WIDTH, height)
        self:ApplyPosition()
    end
end

function Table:ActionStatus(action)
    if action.action == "fold" then
        return L.W_FOLDED
    elseif action.action == "check" then
        return L.W_CHECKED
    elseif action.action == "call" then
        return L.W_CALLED_F:format(FormatAmount(action.paid))
    elseif action.action == "bet" then
        return L.W_BET_F:format(FormatAmount(action.target))
    elseif action.action == "raise" then
        return L.W_RAISED_TO_F:format(FormatAmount(action.target))
    elseif action.action == "all_in" then
        return L.W_ALL_IN .. " " .. FormatAmount(action.target or action.paid)
    elseif action.action == "small_blind" or action.action == "big_blind" then
        return L.W_POSTED_F:format(FormatAmount(action.paid))
    end
    return ""
end

function Table:LatestActions(view)
    local latest = {}
    local street = ActiveStreet(view)
    if not street or not self.settings.showHistory then
        return latest
    end
    for _, action in ipairs(view.actions or {}) do
        if action.street == nil or action.street == street then
            latest[action.seat] = action
        end
    end
    return latest
end

function Table:SeatStatus(view, seat, action, settled)
    local payout, refund = SeatPayout(view, seat), SeatRefund(view, seat)
    if settled and (seat.committed ~= nil or payout > 0 or refund > 0) then
        return FormatSignedAmount(payout + refund - (seat.committed or 0))
    elseif seat.connected == false then
        return L.W_DISCONNECTED
    elseif payout + refund > 0 then
        return "+" .. FormatAmount(payout + refund)
    elseif seat.folded then
        return L.W_FOLDED
    elseif seat.allIn then
        return L.W_ALL_IN_STATE
    elseif seat.sittingOut then
        return L.W_SITTING_OUT
    elseif action then
        return self:ActionStatus(action)
    end
    return ""
end

local function RenderHoleCards(row, seat)
    local inHand = seat.inHand == true
    local hasFaces = inHand and seat.holeCards and #seat.holeCards > 0
    local concealed = inHand and not hasFaces
    row.Cards[1]:ClearAllPoints()
    PixelUtil.SetPoint(row.Cards[1], "LEFT", row, "LEFT", HOLE_CARDS_X, 0)
    for cardIndex, card in ipairs(row.Cards) do
        local cardId = hasFaces and seat.holeCards[cardIndex] or nil
        Cards.CardArt:Transition(card, cardId, concealed)
        card:SetShown(concealed or cardId ~= nil)
    end
end

function Table:RenderPlayer(view, row, seat, latestAction, settled)
    Controls:SetScrollingText(row.Name, seat.name)
    Controls:SetScrollingText(row.Balance, Cards.Gold:FormatCompact(seat.stack))
    Controls:SetScrollingText(row.Status, self:SeatStatus(view, seat, latestAction, settled))
    row.DealerChip:SetShown(seat.seat == view.buttonSeat)
    local actor = seat.seat == view.actorSeat
    row.Name.Text:SetTextColor(unpack(COLORS.text))
    row.ActiveBackground:SetShown(actor and ShouldShowSeat(seat))
    RenderHoleCards(row, seat)
end

function Table:ResultText(winners)
    local results = {}
    for _, winner in ipairs(winners) do
        local category = winner.evaluation and HAND_CATEGORY_LABELS[winner.evaluation.category]
        results[#results + 1] = category
                and L.W_WINS_HAND_F:format(winner.seat.name, FormatAmount(winner.payout), category)
            or L.W_WINS_F:format(winner.seat.name, FormatAmount(winner.payout))
    end
    return #results > 0 and table.concat(results, " · ") or L.STATUS_SETTLED
end

function Table:RenderWinningHand(winner, winningCards)
    local showCards = winner ~= nil
    for cardIndex, card in ipairs(self.winnerCards) do
        local cardId = showCards and winner.seat.holeCards[cardIndex] or nil
        if cardId and not card:IsShown() then
            Cards.CardArt:Set(card, cardId, false)
        end
        Cards.CardArt:Transition(card, cardId, cardId ~= nil and not winningCards[cardId])
        card:SetShown(cardId ~= nil)
    end
end

function Table:StatusText(view, settled)
    if self.actionError then
        return self.actionError
    elseif view.notice then
        return view.notice
    elseif settled then
        return ""
    elseif view.state == "paused" then
        return L.STATUS_PAUSED
    elseif view.state == "joining" or view.state == "waiting" or view.state == "disconnected" then
        return L.W_WAITING_SEAT
    elseif view.state == "between_hands" then
        return view.role == "host" and L.STATUS_READY or L.W_WAITING_HAND
    elseif view.actorSeat then
        return ""
    elseif ActiveStreet(view) then
        return ""
    end
    return L.W_NO_ACTIVE_HAND
end

function Table:LayoutControls(controls, gap)
    local totalWidth = math.max(0, #controls - 1) * gap
    for _, control in ipairs(controls) do
        totalWidth = totalWidth + control.controlWidth
    end
    local offset = (CONTENT_WIDTH - totalWidth) / 2
    for _, control in ipairs(controls) do
        control:ClearAllPoints()
        PixelUtil.SetPoint(control, "TOPLEFT", self.controlBar, "TOPLEFT", offset, 0)
        offset = offset + control.controlWidth + gap
    end
end

function Table:RenderControls(view, settled)
    local legal = view.legalActions
    local enabled = legal ~= nil and not view.pending and view.state ~= "paused"
    local handActive = IsHandActive(view, settled)
    self.callAction = legal and legal.check and "check" or "call"
    SetTextButtonText(
        self.call,
        legal and legal.call and L.W_CALL_F:format(FormatAmount(legal.callAmount)) or L.W_CHECK
    )
    self.raiseAction = legal and legal.bet and "bet" or "raise"
    SetTextButtonState(self.fold, enabled and legal.fold)
    SetTextButtonState(self.call, enabled and (legal.check or legal.call))
    SetTextButtonState(self.raise, enabled and (legal.bet or legal.raise))
    SetTextButtonState(self.allIn, enabled and legal.allIn)
    local hasWager = legal and (legal.bet or legal.raise)
    local actionRevision = (view.session or "") .. ":" .. (view.handId or "") .. ":" .. tostring(view.revision or 0)
    if hasWager and self.wagerRevision ~= actionRevision then
        self.wagerRevision = actionRevision
        self:ConfigureWager(legal.minTarget, legal.maxTarget)
    elseif hasWager then
        SetTextButtonText(self.raise, FormatAmount(self.wagerTarget))
    else
        SetTextButtonText(self.raise, "")
    end
    self:SetWagerEnabled(enabled and hasWager == true)
    for _, control in ipairs({ self.fold, self.call, self.raise, self.allIn }) do
        control:SetShown(handActive)
    end
    local showWager = handActive and hasWager == true
    self.wagerSlider:SetShown(showWager)

    local localSeat = FindSeat(view, view.playerId)
    local betweenHands = view.state == "between_hands" or view.state == "complete"
    local utilityControls = {}
    self.sitOut:SetShown(not handActive and localSeat ~= nil)
    if not handActive and localSeat then
        SetTextButtonText(self.sitOut, localSeat.sittingOut and L.W_SIT_IN or L.W_SIT_OUT)
        SetTextButtonState(self.sitOut, betweenHands and not view.pending)
        utilityControls[#utilityControls + 1] = self.sitOut
    end
    local canRebuy = not handActive and localSeat and localSeat.stack == 0 and view.allowRebuys
    self.rebuy:SetShown(canRebuy == true)
    if canRebuy then
        SetTextButtonState(self.rebuy, betweenHands and not view.pending)
        utilityControls[#utilityControls + 1] = self.rebuy
    end
    local canDeal = not handActive and view.role == "host"
    self.deal:SetShown(canDeal)
    if canDeal then
        SetTextButtonState(self.deal, betweenHands and not view.pending)
        utilityControls[#utilityControls + 1] = self.deal
    end
    if handActive then
        local actionControls = { self.fold, self.call }
        actionControls[#actionControls + 1] = self.raise
        actionControls[#actionControls + 1] = self.allIn
        self:LayoutControls(actionControls, ACTION_GAP)
    else
        self:LayoutControls(utilityControls, UTILITY_GAP)
    end
    self.controlBar:SetShown(handActive or #utilityControls > 0)
    self:LayoutActionArea()
end

function Table:Render(view)
    self.view = view
    local byNumber = SeatMap(view)
    local ordered = self:OrderedSeats(view, byNumber)
    local settled = HasSettlement(view)
    local handActive = IsHandActive(view, settled)
    local settledPresentation = settled and not handActive
    local winners = SettlementWinners(view)
    local winningPlayer, winningCards = SoleWinningHand(winners, settledPresentation)
    local noticeText = self:StatusText(view, settledPresentation)
    self.notice:SetText(noticeText)
    self:RefreshNoticeLayout(noticeText ~= "")
    self:LayoutPlayers(view, ordered)
    local latestActions = self:LatestActions(view)
    for _, seat in ipairs(ordered) do
        local row = self.playerRows[seat.id]
        if row then
            self:RenderPlayer(view, row, seat, latestActions[seat.seat], settled)
        end
    end
    local showBoard = view.handId ~= nil or self.editing
    for cardIndex, card in ipairs(self.board) do
        local cardId = view.board and view.board[cardIndex] or nil
        local concealed = showBoard and cardId == nil
        if winningCards and cardId then
            concealed = not winningCards[cardId]
        end
        Cards.CardArt:Transition(card, cardId, concealed)
        card:SetShown(showBoard)
    end
    self:RenderWinningHand(winningPlayer, winningCards)
    Controls:SetScrollingText(self.pot, settledPresentation and self:ResultText(winners) or FormatAmount(view.pot))
    self:RenderControls(view, settled)
    self:LayoutContent(self.controlBar:IsShown(), self.wagerSlider:IsShown())
    self.timer:Show()
    local duration = view.rules and view.rules.actionSeconds or Cards.ACTION_SECONDS_DEFAULT
    self.timerDuration = duration
    self.timer:SetMinMaxValues(0, duration)
    local paused = view.state == "paused"
    if settled then
        self:RenderTimer(0)
    elseif paused and not self.timerPaused and view.actionDeadline then
        self:RenderTimer(math.max(0, view.actionDeadline - GetTime()))
    end
    self.timerPaused = paused
    self.timer:SetScript("OnUpdate", handActive and not paused and view.actionDeadline and TimerUpdate or nil)
    self:UpdateTimer()
end

function Table:Refresh()
    local sessionActive = Cards.Session:IsActive()
    if sessionActive and self.previewDriver then
        self.previewDriver = nil
        self.actionError = nil
    end
    local previewActive = self.previewDriver ~= nil
    local active = sessionActive or previewActive
    if not self.frame then
        if not active then
            return
        end
        self:Create()
    end
    local shown = active or self.editing == true
    self.frame:SetShown(shown)
    if not shown then
        self.timer:SetScript("OnUpdate", nil)
        return
    end
    self:Render(
        previewActive and self.previewDriver:GetView() or sessionActive and Cards.Session:GetView() or PreviewView()
    )
end

function Table:Show()
    self:Create()
    self:Refresh()
end

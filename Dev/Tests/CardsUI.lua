local EPSILON = 0.000001
local CARD_TEXTURE = "Interface\\AddOns\\Orbit-Games\\Assets\\Cards\\PlayingCards.png"
local ATLAS_WIDTH = 2048
local ATLAS_HEIGHT = 512
local CARD_WIDTH = 128
local CARD_HEIGHT = 88
local FIRST_LEFT = 96
local FIRST_TOP = 20
local COLUMN_STEP = 144
local ROW_STEP = 96
local BACK_TOP = 404
local DEALER_LEFT = 272
local DEALER_TOP = 416
local DEALER_WIDTH = 64
local DEALER_HEIGHT = 64
local TABLE_WIDTH = 380
local TABLE_EMPTY_HEIGHT = 110
local TABLE_FIXED_HEIGHT = 142
local PLAYER_ROW_HEIGHT = 26
local BOARD_CARD_WIDTH = 44
local BOARD_CARD_HEIGHT = 30
local BOARD_CARD_GAP = 4
local POT_ICON_ATLAS = "plunderstorm-icon-plunderCoins-big"
local POT_ICON_SIZE = BOARD_CARD_HEIGHT
local POT_TEXT_GAP_PIXELS = 4
local POT_CARD_GAP_PIXELS = 4
local HOLE_CARD_WIDTH = 32
local HOLE_CARD_HEIGHT = 22
local DEALER_CHIP_SIZE = 22
local DEALER_CHIP_X = -26
local HOLE_CARDS_X = 0
local PLAYER_NAME_X = 72
local PLAYER_BALANCE_X = 196
local PLAYER_BALANCE_WIDTH = 86
local PLAYER_GOLD_ICON_ATLAS = "coin-gold"
local PLAYER_GOLD_ICON_SIZE = 9.75
local PLAYER_GOLD_TEXT_GAP_PIXELS = 3
local FLIP_HALF_SECONDS = 0.12
local FINAL_BOARD_FLIP_HALF_SECONDS = 0.2
local FLIP_EDGE_SCALE = 0.08
local TIMER_HEIGHT_PIXELS = 4
local TIMER_BOARD_GAP_PIXELS = 10
local TIMER_GRADIENT_SHADE = 0.65
local TIMER_SELECTED = { 1, 0.82, 0, 1 }
local TIMER_TIMEOUT = { 1, 0.16, 0.08, 1 }
local TEXT_SHADOW_PIXELS = 2
local THRESHOLD_DELTA = 0.0000001
local HOST_NOTICE_Y = 366
local FOOTER_TOP_PADDING = 12
local FOOTER_BOTTOM_PADDING = 12
local FOOTER_BUTTON_HEIGHT = 20
local FOOTER_SIDE_PADDING = 5
local FOOTER_BUTTON_SPACING = 8
local FOOTER_HEIGHT = FOOTER_TOP_PADDING + FOOTER_BUTTON_HEIGHT + FOOTER_BOTTOM_PADDING
local DISABLED_SLIDER_ALPHA = 0.7
local DISABLED_STEPPER_ALPHA = 0.5
local HORIZONTAL = { LEFT = 0, RIGHT = 1 }
local VERTICAL = { TOP = 1, BOTTOM = 0 }

return function(Games)
    local Cards = Games.Cards
    local L = Cards.L
    local Rules = Cards.TexasHoldem.Rules
    local timerTrackPixels, timerFillOverhangPixels = 2, 1
    local wagerControlGap, wagerMaxSteps, wagerDisabledAlpha = 2, 100, 0.5
    local wagerTrackPixels, wagerThumbWidthPixels, wagerThumbHeightPixels = 2, 3, 10
    local playerTransitionSeconds, playerTransitionEdge = 0.2, 0.05
    local noticeHeight, timerNoticeGapPixels, playerTopGapPixels = 18, 6, 8
    local hostValueX, hostRowStep, hostColumnGap = 114, 40, 8
    local tableActiveFixedHeight = TABLE_FIXED_HEIGHT - noticeHeight - timerNoticeGapPixels
    local activeRowColor = { 1, 0.82, 0, 0.18 }
    local UI = Games.UI
    local assertions = 0

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Near(actual, expected, message)
        Check(
            math.abs(actual - expected) < EPSILON,
            message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
        )
    end

    local function PixelNear(actual, expected, message)
        Check(
            math.abs(actual - expected) <= PixelUtil.GetPixelToUIUnitFactor() + EPSILON,
            message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
        )
    end

    local function SliderEnabled(row, enabled, message)
        local control = row.Slider
        Same(row:IsEnabled(), enabled, message .. " row contract")
        Same(control:IsSliderEnabled(), enabled, message .. " stepper contract")
        Same(control.Slider:IsEnabled(), enabled, message .. " intrinsic slider")
        Near(control.Slider.Thumb:GetAlpha(), enabled and 1 or DISABLED_SLIDER_ALPHA, message .. " thumb alpha")
        if not enabled then
            for _, stepper in ipairs({ control.Back, control.Forward }) do
                Check(not stepper:IsEnabled(), message .. " disables each stepper")
                Near(stepper:GetAlpha(), DISABLED_STEPPER_ALPHA, message .. " dims each stepper")
                Same(stepper.hierarchyDesaturation, 1, message .. " desaturates each stepper")
            end
        end
    end

    local function Click(button)
        Check(button:IsEnabled(), "requested Cards control is enabled")
        local action = button:GetScript("OnClick")
        Check(type(action) == "function", "requested Cards control owns a click action")
        action(button)
    end

    local function FooterGrid(page, visible, hidden, message)
        local footer = page.footer
        Same(footer:GetParent(), UI.modePages[Cards.id].host, message .. " footer belongs to the Cards Host body")
        Check(footer.hasButtons and footer:IsShown(), message .. " exposes its populated footer")
        Check(UI.footerDivider:IsShown(), message .. " exposes the shared footer divider")
        Near(footer:GetTop(), UI.footerDivider:GetTop(), message .. " footer starts at the shared divider")
        local scale = footer:GetEffectiveScale()
        local top = PixelUtil.GetNearestPixelSize(FOOTER_TOP_PADDING, scale)
        local bottom = PixelUtil.GetNearestPixelSize(FOOTER_BOTTOM_PADDING, scale)
        local height = PixelUtil.GetNearestPixelSize(FOOTER_BUTTON_HEIGHT, scale)
        local side = PixelUtil.GetNearestPixelSize(FOOTER_SIDE_PADDING, scale)
        local spacing = PixelUtil.GetNearestPixelSize(FOOTER_BUTTON_SPACING, scale)
        Near(
            footer:GetHeight(),
            PixelUtil.GetNearestPixelSize(FOOTER_HEIGHT, scale),
            message .. " footer has Orbit height"
        )
        for index, button in ipairs(visible) do
            Same(button:GetParent(), footer, message .. " button stays inside its mode footer")
            Check(button:IsShown(), message .. " shows button " .. index)
            Near(button:GetHeight(), height, message .. " button uses Orbit footer height")
            Near(button:GetWidth(), visible[1]:GetWidth(), message .. " buttons share one width")
            Near(footer:GetTop() - button:GetTop(), top, message .. " button uses Orbit top padding")
            Near(button:GetBottom() - footer:GetBottom(), bottom, message .. " button uses Orbit bottom padding")
            if index > 1 then
                Check(
                    math.abs(button:GetLeft() - visible[index - 1]:GetRight() - spacing)
                        <= PixelUtil.GetPixelToUIUnitFactor() / scale + EPSILON,
                    message .. " buttons keep authored spacing within one physical pixel"
                )
            end
        end
        Near(visible[1]:GetLeft() - footer:GetLeft(), side, message .. " first button uses Orbit side padding")
        Near(footer:GetRight() - visible[#visible]:GetRight(), side, message .. " last button uses Orbit side padding")
        for index, button in ipairs(hidden) do
            Same(button:GetParent(), footer, message .. " inactive button remains owned by the footer")
            Check(not button:IsShown(), message .. " hides inactive button " .. index)
        end
    end

    local function Pick(dropdown, value)
        Check(dropdown:IsEnabled(), "requested Cards dropdown is enabled")
        dropdown:OpenMenu()
        Check(dropdown:IsMenuOpen(), "Cards dropdown opens through the native menu lifecycle")
        for _, entry in ipairs(dropdown:GetMenuDescription().entries) do
            if entry:GetData() == value then
                Check(entry:IsRadio(), "Cards dropdown choice is a native radio entry")
                Check(entry:Pick(), "Cards dropdown accepts the requested value")
                Check(not dropdown:IsMenuOpen(), "Cards dropdown closes after selection")
                return
            end
        end
        error("missing Cards dropdown value " .. tostring(value))
    end

    local function PickFont(picker, value)
        Click(picker)
        Check(picker.Popup:IsShown(), "Cards font picker opens its SharedMedia catalogue")
        for index, item in ipairs(picker.Popup.filtered) do
            if item.name == value then
                picker.Popup.scrollOffset =
                    math.max(0, math.min(index - 1, #picker.Popup.filtered - picker.Popup.visibleSlots))
                picker.Popup:Refresh()
                break
            end
        end
        for _, row in ipairs(picker.Popup.rows) do
            if row:IsShown() and row.value == value then
                Click(row)
                Check(not picker.Popup:IsShown(), "Cards font picker closes after selection")
                return
            end
        end
        error("missing Cards font value " .. tostring(value))
    end

    local function TexCoords(texture, expected, message)
        Check(texture.texCoord ~= nil, message .. " has atlas coordinates")
        for index, value in ipairs(expected) do
            Near(texture.texCoord[index], value, message .. " coordinate " .. index)
        end
    end

    local function FaceCoords(cardId)
        local zeroBased = cardId - 1
        local left = FIRST_LEFT + zeroBased % 13 * COLUMN_STEP
        local top = FIRST_TOP + math.floor(zeroBased / 13) * ROW_STEP
        return {
            left / ATLAS_WIDTH,
            (left + CARD_WIDTH) / ATLAS_WIDTH,
            top / ATLAS_HEIGHT,
            (top + CARD_HEIGHT) / ATLAS_HEIGHT,
        }
    end

    local function BackCoords()
        return {
            FIRST_LEFT / ATLAS_WIDTH,
            (FIRST_LEFT + CARD_WIDTH) / ATLAS_WIDTH,
            BACK_TOP / ATLAS_HEIGHT,
            (BACK_TOP + CARD_HEIGHT) / ATLAS_HEIGHT,
        }
    end

    local function Card(code)
        return assert(Cards.CardCatalog:FromCode(code))
    end

    local function Grid(region, message)
        local left, bottom, width, height = region:GetScaledRect()
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        for index, edge in ipairs({ left, bottom, left + width, bottom + height }) do
            Near(edge / factor, math.floor(edge / factor + 0.5), message .. " edge " .. index .. " is pixel-aligned")
        end
    end

    local function TextShadow(label, message)
        Check(label.shadowColorCalls and label.shadowOffsetCalls, message .. " has an explicit text shadow")
        local red, green, blue, alpha = label:GetShadowColor()
        Near(red, 0, message .. " shadow has no red tint")
        Near(green, 0, message .. " shadow has no green tint")
        Near(blue, 0, message .. " shadow has no blue tint")
        Near(alpha, 1, message .. " shadow is opaque")
        local x, y = label:GetShadowOffset()
        local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
        Near(x / pixel, TEXT_SHADOW_PIXELS, message .. " shadow is two physical pixels right")
        Near(y / pixel, -TEXT_SHADOW_PIXELS, message .. " shadow is two physical pixels down")
    end

    local function ShadowInset(frame, message)
        Near(
            frame.scrollRightInset / PixelUtil.GetPixelToUIUnitFactor(),
            TEXT_SHADOW_PIXELS,
            message .. " reserves two physical pixels after clipped text"
        )
    end

    local timerStartColor, timerEndColor
    local function TimerGradient(remaining, duration)
        local timer = Cards.Table.timer
        timerStartColor, timerEndColor = timerStartColor or timer.startColor, timerEndColor or timer.endColor
        Check(timerStartColor and timerEndColor, "Cards timer owns persistent color endpoints")
        Check(timerStartColor ~= timerEndColor, "Cards timer gradient endpoints are independent")
        Same(timer.startColor, timerStartColor, "Cards timer retains its dark endpoint object")
        Same(timer.endColor, timerEndColor, "Cards timer retains its bright endpoint object")
        Same(timer.Fill.gradient[1], "HORIZONTAL", "Cards timer gradient runs left to right")
        Same(timer.Fill.gradient[2], timerStartColor, "native gradient receives the Cards dark endpoint")
        Same(timer.Fill.gradient[3], timerEndColor, "native gradient receives the Cards bright endpoint")
        Near(timer:GetValue(), remaining, "Cards timer gradient accompanies the countdown value")
        Near(timer.Fill.gradientBarValue, remaining, "Cards timer value is set before its gradient")
        local fraction = math.max(0, math.min(1, remaining / duration))
        local tint = { timer:GetStatusBarColor() }
        for index = 1, 3 do
            local expected = TIMER_TIMEOUT[index] + (TIMER_SELECTED[index] - TIMER_TIMEOUT[index]) * fraction
            Near(timer.Fill.gradientColors[1][index], expected * TIMER_GRADIENT_SHADE, "Cards gradient dark hue")
            Near(timer.Fill.gradientColors[2][index], expected, "Cards gradient bright hue")
            Same(tint[index], 1, "white Cards timer tint preserves its gradient")
        end
        Same(timer.Fill.gradientColors[1][4], 1, "Cards gradient dark endpoint is opaque")
        Same(timer.Fill.gradientColors[2][4], 1, "Cards gradient bright endpoint is opaque")
        Same(tint[4], 1, "Cards timer tint is opaque")
    end

    local function Overlaps(left, right)
        local leftX, leftY, leftWidth, leftHeight = left:GetScaledRect()
        local rightX, rightY, rightWidth, rightHeight = right:GetScaledRect()
        return leftX < rightX + rightWidth - EPSILON
            and rightX < leftX + leftWidth - EPSILON
            and leftY < rightY + rightHeight - EPSILON
            and rightY < leftY + leftHeight - EPSILON
    end

    local function NewSeat(index, overrides)
        local seat = {
            seat = index,
            id = "player-" .. index,
            name = "Player " .. index,
            stack = 1000,
            sittingOut = false,
            connected = true,
        }
        for key, value in pairs(overrides or {}) do
            seat[key] = value
        end
        return seat
    end

    local viewSession = 0

    local function NewView(maxPlayers, overrides)
        viewSession = viewSession + 1
        local view = {
            role = "host",
            state = "between_hands",
            rules = {
                version = 1,
                buyIn = 1000,
                smallBlind = 5,
                bigBlind = 10,
                maxPlayers = maxPlayers,
                actionSeconds = 30,
            },
            seats = {},
            board = {},
            actions = {},
            pot = 0,
            currentBet = 0,
            playerId = "player-1",
            session = "cards-ui-session-" .. viewSession,
            revision = 1,
            allowRebuys = true,
        }
        for index = 1, maxPlayers do
            view.seats[index] = NewSeat(index)
        end
        for key, value in pairs(overrides or {}) do
            view[key] = value
        end
        return view
    end

    local function FindBoundRow(seatNumber)
        for _, row in ipairs(Cards.Table.seats) do
            if row.seatNumber == seatNumber then
                return row
            end
        end
    end

    local function FindPlayerRow(playerId)
        return Cards.Table.playerRows[playerId]
    end

    local function FindDisplayRow(seatNumber)
        local row = FindBoundRow(seatNumber)
        return row and row:IsShown() and row or nil
    end

    local function DisplayStatus(seatNumber)
        return FindDisplayRow(seatNumber).Status.Text:GetText()
    end

    local function FindResult(playerName)
        for _, row in ipairs(Cards.ResultsPage.rows) do
            if row.kind == "player" and row.Title:GetText() == playerName then
                return row
            end
        end
    end

    UI:Toggle()
    UI:SetTab("host")
    Pick(UI.gameType, Cards.id)
    Same(Games.Main:GetGameType().id, Cards.id, "generic setup activates Cards")
    Same(UI.hostTo:GetParent(), UI.pages.host, "Cards shares the Host-to selector with every game type")
    Same(UI.hostTo:GetText(), "Server, Guild, Party", "Cards inherits the persisted Host-to audiences")
    Same(UI.tabs.results:GetText(), L.RESULTS_TITLE, "Cards owns the shared Results tab title")
    Same(Cards.Table.frame:GetParent(), UIParent, "Cards table is an ordinary UIParent child")
    Same(Cards.Table.frame.template, nil, "Cards table uses no secure frame template")
    Same(Cards.Table.content:GetParent(), Cards.Table.frame, "visible Cards content owns a separate drag root")
    Same(Cards.Table.background, nil, "Cards table creates no backdrop texture")
    Same(Cards.Table.frame.backdrop, nil, "Cards table creates no native backdrop")
    Same(#(Cards.Table.frame.textures or {}), 0, "Cards table root creates no decorative textures")
    Same(#(Cards.Table.content.textures or {}), 1, "visible Cards content creates only its pot icon")
    Same(Cards.Table.content.textures[1], Cards.Table.potIcon, "the direct Cards texture is the pot atlas")
    Same(Cards.Table.potIcon:GetAtlas(), POT_ICON_ATLAS, "pot readout uses the requested Plunderstorm atlas")
    Check(not Cards.Table.potIcon.useAtlasSize, "pot atlas keeps the explicitly authored compact size")
    Same(Cards.Table.potIcon:GetWidth(), POT_ICON_SIZE, "pot atlas matches the community-card height")
    Same(Cards.Table.potIcon:GetHeight(), POT_ICON_SIZE, "pot atlas remains square")
    Same(#Cards.Table.winnerCards, 2, "table owns one stable winner hole-card pair")
    for cardIndex, card in ipairs(Cards.Table.winnerCards) do
        Same(card:GetWidth(), BOARD_CARD_WIDTH, "winner card uses community-card width " .. cardIndex)
        Same(card:GetHeight(), BOARD_CARD_HEIGHT, "winner card uses community-card height " .. cardIndex)
        Check(not card:IsShown(), "seatless table hides winner card " .. cardIndex)
    end
    Same(Cards.Table.playerList:GetHeight(), 0, "seatless edit preview reserves no invisible player row")
    Same(Cards.Table.content:GetHeight(), TABLE_EMPTY_HEIGHT, "seatless edit preview collapses to visible content")
    for _, entry in ipairs({
        { 0.25, "LEFT" },
        { 0.5 - THRESHOLD_DELTA, "LEFT" },
        { 0.5, "RIGHT" },
        { 0.5 + THRESHOLD_DELTA, "RIGHT" },
        { 0.75, "RIGHT" },
    }) do
        for _, y in ipairs({ 0.5 - THRESHOLD_DELTA, 0.5, 0.5 + THRESHOLD_DELTA }) do
            local layout = Cards.Table:ResolveLayout(entry[1], y, 1600, 1000, TABLE_WIDTH, 200)
            local vertical = y >= 0.5 and "TOP" or "BOTTOM"
            Same(layout.horizontal, entry[2], "Cards uses only the left or right screen half")
            Same(layout.vertical, vertical, "Cards uses the Quiz top/bottom midpoint")
            Same(layout.point, vertical .. entry[2], "Cards layout has no center anchor")
            Near(
                layout.left + TABLE_WIDTH * HORIZONTAL[entry[2]],
                entry[1] * 1600,
                "Cards layout keeps the selected horizontal growth edge"
            )
            Near(
                layout.bottom + 200 * VERTICAL[vertical],
                y * 1000,
                "Cards layout keeps the selected vertical growth edge"
            )
        end
    end

    local HostPage = Cards.HostPage
    local hostBody = UI.modePages[Cards.id].host
    for _, descriptor in ipairs({
        { UI.hostToLabel, Games.L.W_HOST_TO, UI.pages.host, "Host-to" },
        { UI.gameTypeLabel, Games.L.W_GAME_TYPE, UI.pages.host, "Game-type" },
        { HostPage.labels.variant, L.W_VARIANT, hostBody, "Card-game" },
        { HostPage.labels.buyIn, L.W_BUY_IN, hostBody, "Buy-in" },
        { HostPage.labels.blinds, L.W_BLINDS, HostPage.blindSlider, "Blinds" },
        { HostPage.labels.maxPlayers, L.W_MAX_PLAYERS, hostBody, "Seats" },
        { HostPage.labels.actionSeconds, L.W_ACTION_TIME, hostBody, "Action-timer" },
        { HostPage.labels.rebuys, L.W_REBUYS, hostBody, "Rebuys" },
    }) do
        local label, text, parent, message = unpack(descriptor)
        Same(label:GetText(), text, message .. " label is explicitly retained")
        Same(label:GetParent(), parent, message .. " label stays in its owning Host body")
        Same(label:GetFontObject(), GameFontHighlight, message .. " label uses the uniform Host font")
        Same(label:GetJustifyH(), "LEFT", message .. " label is left aligned")
        Same(label:GetJustifyV(), "MIDDLE", message .. " label is vertically centered")
        Same(label.wordWrap, false, message .. " label stays on one line")
        Same(label.nonSpaceWrap, false, message .. " label never wraps inside a word")
    end
    Same(HostPage.amounts.buyIn:GetFontObject(), GameFontHighlight, "buy-in value uses the same native Host font")
    Same(
        HostPage.blindSlider.Value:GetFontObject(),
        GameFontHighlight,
        "formatted blind value uses the same native Host font"
    )

    local sharedValueX = PixelUtil.GetNearestPixelSize(hostValueX, UI.pages.host:GetEffectiveScale())
    local cardsValueX = PixelUtil.GetNearestPixelSize(hostValueX, hostBody:GetEffectiveScale())
    for _, descriptor in ipairs({
        { UI.hostTo, UI.pages.host, sharedValueX, "Host-to" },
        { UI.gameType, UI.pages.host, sharedValueX, "Game-type" },
        { HostPage.variant, hostBody, cardsValueX, "Card-game" },
        { HostPage.amounts.buyIn, hostBody, cardsValueX, "Buy-in" },
        { HostPage.blindSlider.Slider, hostBody, cardsValueX, "Blinds" },
        { HostPage.rebuys, hostBody, cardsValueX, "Rebuys" },
    }) do
        local control, parent, expectedX, message = unpack(descriptor)
        Near(control:GetLeft() - parent:GetLeft(), expectedX, message .. " value starts at the shared column")
    end
    for _, descriptor in ipairs({
        { UI.hostTo, UI.pages.host, "Host-to" },
        { UI.gameType, UI.pages.host, "Game-type" },
        { HostPage.variant, hostBody, "Card-game" },
        { HostPage.amounts.buyIn, hostBody, "Buy-in" },
        { HostPage.rebuys, hostBody, "Rebuys" },
    }) do
        local control, parent, message = unpack(descriptor)
        Near(control:GetRight(), parent:GetRight(), message .. " value ends at the Host form edge")
    end
    Near(HostPage.blindSlider:GetRight(), hostBody:GetRight(), "Blinds composite ends at the Host form edge")

    local cardsRows = {
        HostPage.variant,
        HostPage.amounts.buyIn,
        HostPage.blindSlider,
        HostPage.maxPlayers,
        HostPage.rebuys,
    }
    local cardsRowStep = PixelUtil.GetNearestPixelSize(hostRowStep, hostBody:GetEffectiveScale())
    for index = 2, #cardsRows do
        Near(
            cardsRows[index - 1]:GetTop() - cardsRows[index]:GetTop(),
            cardsRowStep,
            "Cards Host row " .. index .. " keeps the uniform vertical step"
        )
    end

    local seatsLabel, timerLabel = HostPage.labels.maxPlayers, HostPage.labels.actionSeconds
    Near(seatsLabel:GetLeft(), hostBody:GetLeft(), "Seats cell begins at the Host form edge")
    Near(HostPage.actionSeconds:GetRight(), hostBody:GetRight(), "Action-timer cell ends at the Host form edge")
    Near(
        timerLabel:GetLeft() - HostPage.maxPlayers:GetRight(),
        PixelUtil.GetNearestPixelSize(hostColumnGap, hostBody:GetEffectiveScale()),
        "paired Host cells keep the exact center gap"
    )
    Near(
        HostPage.maxPlayers:GetRight() - seatsLabel:GetLeft(),
        HostPage.actionSeconds:GetRight() - timerLabel:GetLeft(),
        "paired Host cells have equal outer widths"
    )
    Near(seatsLabel:GetWidth(), timerLabel:GetWidth(), "paired Host labels have equal widths")
    Near(seatsLabel:GetTop(), timerLabel:GetTop(), "paired Host labels share their top edge")
    Near(seatsLabel:GetBottom(), timerLabel:GetBottom(), "paired Host labels share their bottom edge")
    Near(HostPage.maxPlayers:GetWidth(), HostPage.actionSeconds:GetWidth(), "paired Host controls have equal widths")
    Near(HostPage.maxPlayers:GetTop(), HostPage.actionSeconds:GetTop(), "paired Host controls share their top edge")
    Near(
        HostPage.maxPlayers:GetBottom(),
        HostPage.actionSeconds:GetBottom(),
        "paired Host controls share their bottom edge"
    )
    Same(HostPage.variant:IsEnabled(), false, "the initial Hold'em variant is read-only")
    HostPage.variant:GenerateMenu()
    Same(#HostPage.variant:GetMenuDescription().entries, 1, "host setup lists exactly the installed card variant")
    Same(HostPage.currency, nil, "host setup exposes no ledger-mode choice")
    Same(HostPage.amounts.buyIn:GetText(), "10000", "buy-in is shown as whole Gold")
    Same(HostPage.amounts.buyIn.numeric, true, "buy-in accepts numeric whole-Gold input")
    Same(HostPage.amounts.smallBlind, nil, "host setup has no small-blind EditBox")
    Same(HostPage.amounts.bigBlind, nil, "host setup has no big-blind EditBox")
    Same(HostPage.blindSlider.template, "EditModeSettingSliderTemplate", "blinds use the native inline slider row")
    local blindSlider = HostPage.blindSlider.Slider.Slider
    Same(blindSlider:GetMinMaxValues(), Rules.BLIND_RATE_MIN, "blind slider starts at the 100-BB rate")
    Same(select(2, blindSlider:GetMinMaxValues()), Rules.BLIND_RATE_MAX, "blind slider ends at the 20-BB rate")
    Same(blindSlider:GetValueStep(), Rules.BLIND_RATE_STEP, "blind slider exposes twenty-one exact rates")
    Same(HostPage.blindSlider.Value:GetText(), "SB 50 / BB 100", "blind slider displays both derived blinds")
    Same(HostPage.help, nil, "Cards Host has no muted explanatory copy")
    Same(UI.notice:GetText(), "", "Cards Host removes the default setup hint")
    Check(not UI.notice:IsShown(), "Cards Host hides its empty muted notice lane")
    Check(HostPage.open:IsShown() and HostPage.save:IsShown(), "idle host setup exposes open and save controls")
    Check(HostPage.open:IsEnabled() and HostPage.save:IsEnabled(), "idle host controls are actionable")
    FooterGrid(
        HostPage,
        { HostPage.save, HostPage.open },
        { HostPage.stop, HostPage.pause, HostPage.deal },
        "idle Cards"
    )

    HostPage.amounts.buyIn:SetText("1000")
    Same(HostPage.blindSlider.Value:GetText(), "SB 5 / BB 10", "one-thousand Gold starts at five/ten")
    Test.DragSlider(blindSlider, Rules.BLIND_RATE_MAX)
    Same(HostPage.blindSlider.Value:GetText(), "SB 25 / BB 50", "one-thousand Gold ends at twenty-five/fifty")
    HostPage.amounts.buyIn:SetText("100000")
    Same(
        HostPage.blindSlider.Value:GetText(),
        "SB 2500 / BB 5000",
        "one-hundred-thousand Gold scales the selected blinds"
    )
    Test.DragSlider(blindSlider, Rules.BLIND_RATE_MIN)
    Same(HostPage.blindSlider.Value:GetText(), "SB 500 / BB 1000", "one-hundred-thousand Gold starts at 500/1000")
    HostPage.amounts.buyIn:SetText("10000000")
    Same(HostPage.blindSlider.Value:GetText(), "SB 50000 / BB 100000", "maximum buy-in starts at 50000/100000")
    Test.DragSlider(blindSlider, Rules.BLIND_RATE_MAX)
    Same(HostPage.blindSlider.Value:GetText(), "SB 250000 / BB 500000", "maximum buy-in ends at 250000/500000")

    local originalHostSettings = Cards.Store:GetHostSettings()
    HostPage.amounts.buyIn:SetText("999")
    SliderEnabled(HostPage.blindSlider, false, "buy-in below one thousand disables the blind slider")
    Click(HostPage.save)
    Same(UI.actionError, L.errors.invalid_buy_in, "host setup reports the whole-Gold buy-in bounds")
    Same(UI.notice:GetText(), UI.actionError, "a real Cards Host validation error uses the notice lane")
    Check(UI.notice:IsShown(), "Cards Host shows its action error")
    Near(
        UI.frame:GetTop() - UI.notice:GetTop(),
        PixelUtil.GetNearestPixelSize(HOST_NOTICE_Y, UI.notice:GetEffectiveScale()),
        "Cards Host errors sit above the footer divider"
    )
    Check(UI.notice:GetBottom() > HostPage.footer:GetTop(), "Cards Host errors stay clear of the footer")
    Same(
        Cards.Store:GetHostSettings().buyIn,
        originalHostSettings.buyIn,
        "rejected host setup leaves saved settings unchanged"
    )
    HostPage.amounts.buyIn:SetText("10000001")
    Same(HostPage:ReadSettings().buyIn, 0, "host setup rejects buy-ins above ten million")
    HostPage.amounts.buyIn:SetText("1000.5")
    Same(HostPage:ReadSettings().buyIn, 0, "host setup rejects fractional Gold")
    HostPage.amounts.buyIn:SetText("100000")
    Test.DragSlider(blindSlider, Rules.BLIND_RATE_MAX)
    local goldDraft = HostPage:ReadSettings()
    Same(goldDraft.buyIn, 100000, "whole-Gold buy-in parses directly")
    Same(goldDraft.smallBlind, 2500, "small blind derives from the selected buy-in rate")
    Same(goldDraft.bigBlind, 5000, "big blind is always twice the small blind")
    Click(HostPage.save)
    Same(UI.actionError, nil, "valid Gold setup clears the prior validation error")
    Check(not UI.notice:IsShown(), "clearing the Cards Host error restores the lean page")
    local savedGold = Cards.Store:GetHostSettings()
    Same(savedGold.currencyMode, nil, "host settings persist no obsolete ledger mode")
    Same(savedGold.buyIn, 100000, "whole-Gold buy-in persists")
    Same(savedGold.smallBlind, 2500, "slider-selected small blind persists")
    Same(savedGold.bigBlind, 5000, "derived big blind persists")
    Same(blindSlider:GetValue(), Rules.BLIND_RATE_MAX, "load restores the saved blind rate")
    Same(HostPage.blindSlider.Value:GetText(), "SB 2500 / BB 5000", "load restores both blind values")

    local originalIsRunning = Cards.Controller.IsRunning
    Cards.Controller.IsRunning = function()
        return true
    end
    UI:Refresh()
    Check(not UI.hostTo:IsEnabled(), "a running Cards table locks the shared Host-to selector")
    Check(not HostPage.amounts.buyIn:IsEnabled(), "running table disables the buy-in")
    SliderEnabled(HostPage.blindSlider, false, "running table disables the blind slider")
    FooterGrid(
        HostPage,
        { HostPage.stop, HostPage.pause, HostPage.deal },
        { HostPage.save, HostPage.open },
        "active Cards"
    )
    Cards.Controller.IsRunning = originalIsRunning
    UI:Refresh()
    Check(UI.hostTo:IsEnabled(), "an idle Cards table unlocks the shared Host-to selector")
    Check(HostPage.amounts.buyIn:IsEnabled(), "idle table re-enables the buy-in")
    SliderEnabled(HostPage.blindSlider, true, "idle table re-enables the blind slider")
    Check(HostPage.blindSlider.Slider.Back:IsEnabled(), "re-enabled maximum slider restores its backward stepper")
    Check(not HostPage.blindSlider.Slider.Forward:IsEnabled(), "re-enabled maximum slider keeps its forward limit")
    FooterGrid(
        HostPage,
        { HostPage.save, HostPage.open },
        { HostPage.stop, HostPage.pause, HostPage.deal },
        "reset Cards"
    )
    Cards.SettingsPage:Refresh()
    Same(Cards.SettingsPage.help, nil, "Cards Settings creates no muted explanatory block")

    UI:SetTab("settings")
    Check(not UI.notice:IsShown(), "Cards Settings has no passive setup subtext")
    Same(UI.notice:GetText(), "", "Cards Settings leaves the shared notice lane empty")
    Check(not UI.footerDivider:IsShown(), "Cards Settings hides the footer divider because it has no actions")
    Check(not HostPage.footer:IsVisible(), "Cards Settings shows no Host footer")
    local SettingsPage = Cards.SettingsPage
    local scaleControl = SettingsPage.scaleSlider
    local scaleSlider = scaleControl.Slider.Slider
    Same(scaleControl.template, "EditModeSettingSliderTemplate", "table scale uses the native inline setting row")
    Same(scaleSlider:GetMinMaxValues(), Cards.TABLE_SCALE_MIN, "table scale exposes the supported minimum")
    Same(select(2, scaleSlider:GetMinMaxValues()), Cards.TABLE_SCALE_MAX, "table scale exposes the supported maximum")
    Same(scaleSlider:GetValueStep(), Cards.TABLE_SCALE_STEP, "table scale advances in five-percent steps")
    Same(SettingsPage.fontRow.Label:GetText(), L.W_TABLE_FONT, "Cards Settings exposes a compact Font row")
    Check(not Overlaps(scaleControl, SettingsPage.fontRow), "Cards Scale and Font rows do not overlap")
    Check(not Overlaps(SettingsPage.fontRow, SettingsPage.history), "Cards Font and history rows do not overlap")
    Test.DragSlider(scaleSlider, 127)
    Same(Cards.Store:GetTableSettings().scale, 125, "table scale drag snaps and persists immediately")
    Near(Cards.Table.frame:GetScale(), 1.25, "table scale applies to the whole play surface")
    Pick(SettingsPage.history, false)
    Same(Cards.Store:GetTableSettings().showHistory, false, "history dropdown persists the hidden state")
    Pick(SettingsPage.history, true)
    Same(Cards.Store:GetTableSettings().showHistory, true, "history dropdown restores the visible state")
    local normalHeight = select(2, Cards.Table.pot.Text:GetFont())
    local smallHeight = select(2, Cards.Table.seats[1].Status.Text:GetFont())
    local fontName = "Cards UI Test Font"
    local fontPath = "Interface\\AddOns\\CardsUITest\\Cards.ttf"
    Check(Games.Media.library:Register("font", fontName, fontPath), "Cards test font registers through SharedMedia")
    PickFont(SettingsPage.fontPicker, fontName)
    Same(Cards.Store:GetTableSettings().font, fontName, "Cards font selection persists immediately")
    Same(#Cards.Table.fontTargets, 33, "Cards table binds every owned text target through two font roles")
    for _, target in ipairs(Cards.Table.fontTargets) do
        Same(target.label:GetFont(), fontPath, "Cards font selection applies to every table text target")
        Same(
            target.label:GetFontObject(),
            Cards.Table.fontObjects[target.role],
            "Cards text inherits its owned normal or small font role"
        )
        Same(target.label.fontCalls, nil, "Cards font selection never inlines a font on visible table text")
    end
    Same(select(2, Cards.Table.pot.Text:GetFont()), normalHeight, "Cards font preserves normal text size")
    Same(select(2, Cards.Table.seats[1].Status.Text:GetFont()), smallHeight, "Cards font preserves small text size")
    Same(Cards.Table.raise.Text:GetFont(), fontPath, "Cards font applies to the wager action value")
    local normalFontCalls = Cards.Table.fontObjects.normal.fontCalls
    Cards.Table:ApplySettings()
    Same(Cards.Table.fontObjects.normal.fontCalls, normalFontCalls, "unchanged Cards settings do not reapply fonts")
    local lateFontName = "Cards Late Provider"
    local lateFontPath = "Interface\\AddOns\\CardsLateProvider\\Cards.ttf"
    SettingsPage:Save({ font = lateFontName })
    Same(Cards.Store:GetTableSettings().font, lateFontName, "unavailable Cards font selection remains saved")
    Same(Cards.Table.pot.Text:GetFont(), GameFontHighlight:GetFont(), "missing Cards font falls back to Blizzard")
    Same(
        SettingsPage.fontPicker.Text:GetText(),
        Games.L.W_WIDGET_FONT_UNAVAILABLE_F:format(lateFontName),
        "the picker itself marks a missing Cards font without explanatory subtext"
    )
    UI:SetTab("host")
    Pick(UI.gameType, Games.Quiz.id)
    Same(UI.hostTo:GetText(), "Server, Guild, Party", "switching to Quiz retains the shared Host-to selection")
    Check(
        Games.Media.library:Register("font", lateFontName, lateFontPath),
        "late Cards font registers while Quiz is selected"
    )
    Same(
        Cards.Table.pot.Text:GetFont(),
        lateFontPath,
        "late SharedMedia registration refreshes an already-created inactive Cards table"
    )
    Same(Cards.Store:GetTableSettings().font, lateFontName, "late font restoration keeps the Cards preference")
    Pick(UI.gameType, Cards.id)
    Same(UI.hostTo:GetText(), "Server, Guild, Party", "returning to Cards retains the shared Host-to selection")
    UI:SetTab("settings")
    Same(SettingsPage.fontPicker.Text:GetText(), lateFontName, "restored Cards font clears its unavailable marker")
    PickFont(SettingsPage.fontPicker, "")
    Same(Cards.Store:GetTableSettings().font, "", "Cards font picker restores the Blizzard default")
    Same(Cards.Table.pot.Text:GetFont(), GameFontHighlight:GetFont(), "default Cards font restores Blizzard text")
    Click(SettingsPage.fontPicker)
    UI:SetTab("host")
    Check(not SettingsPage.fontPicker.Popup:IsShown(), "leaving Cards Settings closes its font popup")
    Check(UI.footerDivider:IsShown(), "Cards Host restores its populated footer divider")
    UI:SetTab("settings")
    Check(not UI.footerDivider:IsShown(), "returning to Cards Settings hides the empty footer divider")
    Test.DragSlider(scaleSlider, 100)
    Near(Cards.Table.frame:GetScale(), 1, "table scale returns to one hundred percent")
    Same(SettingsPage.help, nil, "Cards Settings remains free of grey guidance copy")

    local standaloneCard = Cards.CardArt:Create(UIParent, 64, 44)
    Same(standaloneCard.Face:GetTexture(), CARD_TEXTURE, "card face uses the bundled playing-card atlas")
    Cards.CardArt:Set(standaloneCard, nil, false)
    Check(
        not standaloneCard.Face:IsShown() and not standaloneCard.Surface:IsShown() and standaloneCard.Empty:IsShown(),
        "missing cards render only the empty slot"
    )
    Cards.CardArt:Set(standaloneCard, 1, false)
    Check(
        standaloneCard.Face:IsShown() and standaloneCard.Surface:IsShown() and not standaloneCard.Empty:IsShown(),
        "valid cards render their face over an opaque card surface"
    )
    TexCoords(standaloneCard.Face, FaceCoords(1), "first atlas card")
    Cards.CardArt:Set(standaloneCard, 52, false)
    TexCoords(standaloneCard.Face, FaceCoords(52), "last atlas card")
    Cards.CardArt:Transition(standaloneCard, 52, true)
    Check(standaloneCard.FlipClose:IsPlaying(), "turning an irrelevant face down starts its closing flip")
    TexCoords(standaloneCard.Face, FaceCoords(52), "face remains visible through the closing half")
    Test.AdvanceAnimations(FLIP_HALF_SECONDS)
    Check(standaloneCard.FlipOpen:IsPlaying(), "card back starts opening at the flip midpoint")
    TexCoords(standaloneCard.Face, BackCoords(), "face changes to a card back at the flip midpoint")
    Test.AdvanceAnimations(FLIP_HALF_SECONDS)
    Check(not standaloneCard.flipPending, "face-to-back flip completes cleanly")
    Cards.CardArt:Set(standaloneCard, nil, true)
    Check(standaloneCard.Surface:IsShown(), "concealed cards retain the opaque card surface")
    TexCoords(standaloneCard.Face, BackCoords(), "card back cell")
    local dealerChip = Cards.CardArt:CreateDealerChip(UIParent)
    Same(dealerChip:GetTexture(), CARD_TEXTURE, "dealer chip shares the bundled playing-card atlas")
    TexCoords(dealerChip, {
        DEALER_LEFT / ATLAS_WIDTH,
        (DEALER_LEFT + DEALER_WIDTH) / ATLAS_WIDTH,
        DEALER_TOP / ATLAS_HEIGHT,
        (DEALER_TOP + DEALER_HEIGHT) / ATLAS_HEIGHT,
    }, "dealer-chip atlas region")
    Cards.CardArt:Set(standaloneCard, 0, false)
    Check(
        not standaloneCard.Face:IsShown() and not standaloneCard.Surface:IsShown() and standaloneCard.Empty:IsShown(),
        "invalid card IDs render empty"
    )

    local originalSession = {
        isActive = Cards.Session.IsActive,
        getView = Cards.Session.GetView,
        act = Cards.Session.Act,
        setSittingOut = Cards.Session.SetSittingOut,
        rebuy = Cards.Session.Rebuy,
    }
    local originalController = {
        startHand = Cards.Controller.StartHand,
    }
    local currentView
    local viewRequests = 0
    local sentActions, sitOutRequests, rebuyRequests, dealRequests = {}, {}, 0, 0
    Cards.Session.IsActive = function()
        return currentView ~= nil
    end
    Cards.Session.GetView = function()
        viewRequests = viewRequests + 1
        return currentView
    end
    Cards.Session.Act = function(_, action, targetAmount)
        sentActions[#sentActions + 1] = { action = action, targetAmount = targetAmount }
        return true
    end
    Cards.Session.SetSittingOut = function(_, sittingOut)
        sitOutRequests[#sitOutRequests + 1] = sittingOut
        return true
    end
    Cards.Session.Rebuy = function()
        rebuyRequests = rebuyRequests + 1
        return true
    end
    Cards.Controller.StartHand = function()
        dealRequests = dealRequests + 1
        return true
    end
    local hostIsRunning = Cards.Controller.IsRunning
    Cards.Controller.IsRunning = function()
        return currentView ~= nil
    end
    currentView = NewView(2)
    UI:SetTab("host")
    HostPage:Refresh()
    FooterGrid(
        HostPage,
        { HostPage.stop, HostPage.pause, HostPage.deal },
        { HostPage.save, HostPage.open },
        "live Cards"
    )
    Click(HostPage.deal)
    Same(dealRequests, 1, "Host footer Deal routes once through the Cards controller")
    dealRequests = 0
    Cards.Controller.IsRunning = hostIsRunning
    currentView = { role = "idle", state = "idle", gameTypeId = Cards.id }
    UI:SetTab("settings")
    currentView = nil
    Cards.Table:SetEditing(true)
    for cardIndex, card in ipairs(Cards.Table.board) do
        Check(card:IsShown() and card.concealed, "edit mode shows its community-card drag target " .. cardIndex)
    end
    currentView = NewView(2)
    Cards.Table:Refresh()
    Cards.Table:SetEditing(false)
    for cardIndex, card in ipairs(Cards.Table.board) do
        Check(not card:IsShown(), "closing edit mode hides between-hand community backs " .. cardIndex)
    end
    Cards.Table:SetEditing(true)
    for cardIndex, card in ipairs(Cards.Table.board) do
        Check(card:IsShown() and card.concealed, "reopening edit mode restores the community drag target " .. cardIndex)
    end
    for maxPlayers = Cards.MIN_PLAYERS, Cards.MAX_PLAYERS do
        currentView = NewView(maxPlayers)
        Cards.Table:Render(currentView)
        Same(Cards.Table.frame:GetWidth(), TABLE_WIDTH, "compact table width remains fixed")
        Same(Cards.Table.content:GetWidth(), TABLE_WIDTH, "visible table content retains the Quiz width")
        Same(
            Cards.Table.frame:GetHeight(),
            TABLE_FIXED_HEIGHT + maxPlayers * PLAYER_ROW_HEIGHT,
            "capacity " .. maxPlayers .. " drives the compact table height"
        )
        Same(
            Cards.Table.content:GetHeight(),
            TABLE_FIXED_HEIGHT + maxPlayers * PLAYER_ROW_HEIGHT,
            "capacity " .. maxPlayers .. " drives the visible content height"
        )
        Same(
            Cards.Table.playerList:GetHeight(),
            maxPlayers * PLAYER_ROW_HEIGHT,
            "capacity " .. maxPlayers .. " drives the vertical player list height"
        )
        for rowIndex, row in ipairs(Cards.Table.seats) do
            Same(row.background, nil, "player row creates no background surface " .. rowIndex)
            Same(row.Indicator, nil, "player row creates no active accent texture " .. rowIndex)
            Same(
                #(row.textures or {}),
                3,
                "player row owns only its active, dealer-chip and Gold textures " .. rowIndex
            )
            Same(row.textures[1], row.ActiveBackground, "player row direct texture is its active state " .. rowIndex)
            Same(row.textures[2], row.DealerChip, "player row second direct texture is its dealer chip " .. rowIndex)
            Same(row.textures[3], row.GoldIcon, "player row third direct texture is its Gold icon " .. rowIndex)
            Same(row.ActiveBackground.drawLayer, "BACKGROUND", "active wash stays behind row content " .. rowIndex)
            Same(row.ActiveBackground.allPoints, row, "active wash covers the entire player row " .. rowIndex)
            for component, expected in ipairs(activeRowColor) do
                Near(
                    row.ActiveBackground.color[component],
                    expected,
                    "active wash color " .. rowIndex .. ":" .. component
                )
            end
            Check(not row.ActiveBackground:IsShown(), "between hands have no active row wash " .. rowIndex)
            Same(row.DealerChip:GetWidth(), DEALER_CHIP_SIZE, "dealer chip uses the compact width " .. rowIndex)
            Same(row.DealerChip:GetHeight(), DEALER_CHIP_SIZE, "dealer chip uses the compact height " .. rowIndex)
            Check(not row.DealerChip:IsShown(), "seatless hand state hides dealer chip " .. rowIndex)
        end
        Same(#Cards.Table.playerRowOrder, maxPlayers, "capacity owns one identity-bound row per player")
        for rowIndex, row in ipairs(Cards.Table.playerRowOrder) do
            local expectedSeat = rowIndex == maxPlayers and 1 or rowIndex + 1
            Same(row.seatNumber, expectedSeat, "display rows rotate the local seat to the end")
            Same(row.playerId, "player-" .. expectedSeat, "display rows retain their projected player identity")
            Grid(row, "capacity " .. maxPlayers .. " display row " .. rowIndex)
            for other = 1, rowIndex - 1 do
                Check(
                    not Overlaps(row, Cards.Table.playerRowOrder[other]),
                    "capacity " .. maxPlayers .. " keeps display rows " .. other .. " and " .. rowIndex .. " separate"
                )
            end
        end
        Same(
            Cards.Table.playerRowOrder[maxPlayers].seatNumber,
            1,
            "capacity " .. maxPlayers .. " keeps local seat last"
        )
        Same(
            Cards.Table.playerRowOrder[maxPlayers].playerId,
            currentView.playerId,
            "capacity " .. maxPlayers .. " keeps the local player in the last row"
        )
    end

    currentView = NewView(3, {
        state = "preflop",
        handId = "private-hand",
        buttonSeat = 1,
        smallBlindSeat = 2,
        bigBlindSeat = 3,
        actorSeat = 2,
        actionDeadline = Test.now + 10,
        legalActions = nil,
        board = { 2, 15 },
        pot = 15,
    })
    currentView.seats[1].inHand = true
    currentView.seats[1].holeCards = { 1, 14 }
    currentView.seats[2].inHand = true
    currentView.seats[3].inHand = true
    currentView.seats[3].folded = false
    Cards.Table:Render(currentView)
    Check(Cards.Table.board[1].FlipClose:IsPlaying(), "the first live hand flips the edit-mode back to its face")
    Test.AdvanceAnimations(FLIP_HALF_SECONDS * 2)
    local localRow = FindDisplayRow(1)
    local actorRow = FindDisplayRow(2)
    local thirdRow = FindDisplayRow(3)
    Same(localRow.Cards[1]:GetWidth(), HOLE_CARD_WIDTH, "hole cards use the larger compact width")
    Same(localRow.Cards[1]:GetHeight(), HOLE_CARD_HEIGHT, "hole cards use the compact landscape height")
    TexCoords(localRow.Cards[1].Face, FaceCoords(1), "local first private card")
    TexCoords(localRow.Cards[2].Face, FaceCoords(14), "local second private card")
    for cardIndex, card in ipairs(actorRow.Cards) do
        Check(card:IsShown() and card.Face:IsShown(), "active opponent shows card back " .. cardIndex)
        Check(card.concealed, "active opponent card remains concealed " .. cardIndex)
        TexCoords(card.Face, {
            FIRST_LEFT / ATLAS_WIDTH,
            (FIRST_LEFT + CARD_WIDTH) / ATLAS_WIDTH,
            BACK_TOP / ATLAS_HEIGHT,
            (BACK_TOP + CARD_HEIGHT) / ATLAS_HEIGHT,
        }, "active opponent card back " .. cardIndex)
    end
    for rowIndex, row in ipairs(Cards.Table.seats) do
        Same(row.FoldTint, nil, "player row allocates no obsolete fold tint " .. rowIndex)
        Same(row.FoldStrikes, nil, "player row allocates no obsolete fold X " .. rowIndex)
        Same(row.Cards[1].lines, nil, "player card allocates no obsolete fold lines " .. rowIndex)
        Same(#row.Cards[1].textures, 3, "player card retains only its standard art textures " .. rowIndex)
    end
    TexCoords(Cards.Table.board[1].Face, FaceCoords(2), "first community card")
    TexCoords(Cards.Table.board[2].Face, FaceCoords(15), "second community card")
    Same(Cards.Table.board[1]:GetWidth(), BOARD_CARD_WIDTH, "community cards use the larger compact width")
    Same(Cards.Table.board[1]:GetHeight(), BOARD_CARD_HEIGHT, "community cards use the compact landscape height")
    for cardIndex, card in ipairs(Cards.Table.winnerCards) do
        Check(not card:IsShown(), "active hand hides winner card " .. cardIndex)
    end
    Same(Cards.Table.winnerCards[1].point[1], "TOPRIGHT", "winner cards pin to the table's right edge")
    Same(Cards.Table.winnerCards[1].point[2], Cards.Table.content, "winner cards anchor to visible content")
    Same(Cards.Table.winnerCards[1].point[3], "TOPRIGHT", "winner cards share the content's right edge")
    Near(Cards.Table.winnerCards[1]:GetRight(), Cards.Table.content:GetRight(), "first winner card is rightmost")
    Same(Cards.Table.winnerCards[2].point[1], "RIGHT", "second winner card grows left")
    Same(Cards.Table.winnerCards[2].point[2], Cards.Table.winnerCards[1], "winner pair retains one anchor chain")
    Same(Cards.Table.winnerCards[2].point[3], "LEFT", "second winner card grows from the first card's left edge")
    Near(
        Cards.Table.winnerCards[1]:GetLeft() - Cards.Table.winnerCards[2]:GetRight(),
        BOARD_CARD_GAP,
        "left-growing winner cards retain the board-card gap"
    )
    Check(
        Cards.Table.winnerCards[2]:GetLeft() > Cards.Table.board[5]:GetRight(),
        "right-pinned winner cards retain deliberate community-card spacing"
    )
    Same(Cards.Table.potIcon.point[1], "TOPLEFT", "pot atlas anchors above the board row")
    Near(Cards.Table.potIcon.point[4], 0, "pot atlas starts at the content's left edge")
    Near(Cards.Table.potIcon.point[5], 0, "pot atlas starts at the content's top edge")
    Near(
        (Cards.Table.pot:GetLeft() - Cards.Table.potIcon:GetRight())
            * Cards.Table.pot:GetEffectiveScale()
            / PixelUtil.GetPixelToUIUnitFactor(),
        POT_TEXT_GAP_PIXELS,
        "pot amount sits to the atlas's right"
    )
    Near(Cards.Table.pot:GetTop(), Cards.Table.potIcon:GetTop(), "pot amount aligns with the atlas top")
    Near(Cards.Table.pot:GetBottom(), Cards.Table.potIcon:GetBottom(), "pot amount aligns with the atlas bottom")
    Near(
        (Cards.Table.potIcon:GetBottom() - Cards.Table.board[1]:GetTop())
            * Cards.Table.board[1]:GetEffectiveScale()
            / PixelUtil.GetPixelToUIUnitFactor(),
        POT_CARD_GAP_PIXELS,
        "pot widget sits above the community cards"
    )
    Near(Cards.Table.board[1].point[4], 0, "community cards return to the content's left edge")
    Check(not Overlaps(Cards.Table.potIcon, Cards.Table.board[1]), "pot atlas never overlaps the card row")
    Check(not Overlaps(Cards.Table.pot, Cards.Table.board[1]), "pot amount never sits inline with the card row")
    Same(Cards.Table.pot.Text:GetText(), "15", "pot readout shows only the whole-Gold amount")
    Check(not Cards.Table.pot.Text:GetText():find("Pot", 1, true), "pot readout has no redundant text label")
    Near(
        Cards.Table.board[3].FlipClose.Animation:GetDuration(),
        FLIP_HALF_SECONDS,
        "the final flop card keeps the compact flip pace"
    )
    for cardIndex = 4, 5 do
        Near(
            Cards.Table.board[cardIndex].FlipClose.Animation:GetDuration(),
            FINAL_BOARD_FLIP_HALF_SECONDS,
            "turn and river use a slower closing flip " .. cardIndex
        )
        Near(
            Cards.Table.board[cardIndex].FlipOpen.Animation:GetDuration(),
            FINAL_BOARD_FLIP_HALF_SECONDS,
            "turn and river use a slower opening flip " .. cardIndex
        )
    end
    for cardIndex, card in ipairs(Cards.Table.board) do
        Check(card:IsShown() and card.Face:IsShown(), "active hand keeps community slot visible " .. cardIndex)
        if cardIndex > 2 then
            Check(card.concealed and card.cardId == nil, "undealt community slot is an anonymous back " .. cardIndex)
            TexCoords(card.Face, {
                FIRST_LEFT / ATLAS_WIDTH,
                (FIRST_LEFT + CARD_WIDTH) / ATLAS_WIDTH,
                BACK_TOP / ATLAS_HEIGHT,
                (BACK_TOP + CARD_HEIGHT) / ATLAS_HEIGHT,
            }, "undealt community-card back " .. cardIndex)
        end
    end
    Same(#localRow.textures, 3, "player rows own one active wash plus the dealer chip and Gold icon")
    Same(localRow.textures[3], localRow.GoldIcon, "the Gold icon is the player row's third direct texture")
    Same(localRow.GoldIcon:GetAtlas(), PLAYER_GOLD_ICON_ATLAS, "player balances use the native Gold coin atlas")
    Check(localRow.GoldIcon.useAtlasSize, "the Gold icon resolves its native atlas before applying compact geometry")
    local goldIconSize = PixelUtil.GetNearestPixelSize(PLAYER_GOLD_ICON_SIZE, localRow:GetEffectiveScale())
    Same(localRow.GoldIcon:GetWidth(), goldIconSize, "player Gold icons snap the reduced compact width")
    Same(localRow.GoldIcon:GetHeight(), goldIconSize, "player Gold icons snap the reduced compact height")
    Same(localRow.GoldIcon.point[4], PLAYER_BALANCE_X, "the Gold icon starts at the balance-column origin")
    Same(localRow.Balance.point[2], localRow.GoldIcon, "the compact balance follows its Gold icon")
    Same(localRow.Balance.point[3], "RIGHT", "the compact balance grows from the Gold icon's right edge")
    local goldTextGap = PixelUtil.GetNearestPixelSize(0, localRow:GetEffectiveScale(), PLAYER_GOLD_TEXT_GAP_PIXELS)
    Near(localRow.Balance.point[4], goldTextGap, "the Gold icon and value retain a physical gap")
    Near(
        localRow.Balance:GetWidth(),
        PixelUtil.GetNearestPixelSize(
            PLAYER_BALANCE_WIDTH - PLAYER_GOLD_ICON_SIZE - goldTextGap,
            localRow:GetEffectiveScale()
        ),
        "the compact value remains inside the original balance column"
    )
    Same(localRow.Balance.Text:GetText(), "1K", "the Gold icon replaces the redundant balance label")
    for index, component in ipairs({ 1, 1, 1, 1 }) do
        Near(select(index, localRow.Balance.Text:GetTextColor()), component, "Gold value color component " .. index)
    end
    Check(localRow.DealerChip:IsShown(), "dealer chip follows the projected button")
    Check(not actorRow.DealerChip:IsShown(), "small blind has no obsolete text marker")
    Check(not thirdRow.DealerChip:IsShown(), "big blind has no obsolete text marker")
    Same(localRow.DealerChip.point[4], DEALER_CHIP_X, "dealer chip overhangs the left edge")
    Check(
        localRow.DealerChip.point[4] + localRow.DealerChip:GetWidth() < 0,
        "dealer chip stays wholly outside the content frame"
    )
    Same(localRow.Cards[1].point[4], HOLE_CARDS_X, "player-row cards return to their original left column")
    Same(localRow.Name.point[4], PLAYER_NAME_X, "player names return to their original content column")
    Same(localRow.Status.point[4], 0, "player status returns to the row's right edge")
    Same(Cards.Table.notice:GetText(), "", "actor-row highlighting replaces the redundant turn line")
    Check(not Cards.Table.notice:IsShown(), "empty active-hand status lane collapses")
    Same(Cards.Table.playerList.point[2], Cards.Table.timer, "collapsed player rows follow the timer directly")
    Check(actorRow.ActiveBackground:IsShown(), "actor receives the full-row backdrop highlight")
    Check(not localRow.ActiveBackground:IsShown(), "non-actor local row has no backdrop highlight")
    Check(not thirdRow.ActiveBackground:IsShown(), "non-actor remote row has no backdrop highlight")
    for rowIndex, row in ipairs({ actorRow, localRow, thirdRow }) do
        for component, expected in ipairs({ 1, 1, 1, 1 }) do
            Near(
                select(component, row.Name.Text:GetTextColor()),
                expected,
                "player name stays white " .. rowIndex .. ":" .. component
            )
        end
    end
    local potAmountX = Cards.Table.pot:GetLeft()
    local firstBoardX = Cards.Table.board[1]:GetLeft()
    local turningCard = Cards.Table.board[3]
    currentView.board[3] = 28
    currentView.buttonSeat = 2
    Cards.Table:Render(currentView)
    Near(Cards.Table.pot:GetLeft(), potAmountX, "pot amount stays fixed as community cards turn face up")
    Near(Cards.Table.board[1]:GetLeft(), firstBoardX, "community row stays fixed as later cards turn face up")
    Check(turningCard.FlipClose:IsPlaying(), "newly dealt community card begins its closing flip")
    Same(turningCard.FlipClose.Animation.kind, "Scale", "card flip uses a native Scale animation")
    Near(turningCard.FlipClose.Animation:GetDuration(), FLIP_HALF_SECONDS, "closing flip uses the compact duration")
    Near(select(1, turningCard.FlipClose.Animation:GetScaleFrom()), 1, "closing flip begins at full width")
    Near(
        select(1, turningCard.FlipClose.Animation:GetScaleTo()),
        FLIP_EDGE_SCALE,
        "closing flip narrows to a visible edge"
    )
    Same(turningCard.FlipClose.Animation:GetSmoothing(), "IN", "closing flip accelerates into the turn")
    Same(turningCard.FlipClose.Animation:GetOrigin(), "CENTER", "closing flip pivots around the card center")
    TexCoords(turningCard.Face, {
        FIRST_LEFT / ATLAS_WIDTH,
        (FIRST_LEFT + CARD_WIDTH) / ATLAS_WIDTH,
        BACK_TOP / ATLAS_HEIGHT,
        (BACK_TOP + CARD_HEIGHT) / ATLAS_HEIGHT,
    }, "community card keeps its back through the closing half")
    Test.AdvanceAnimations(FLIP_HALF_SECONDS)
    Check(not turningCard.FlipClose:IsPlaying(), "closing flip completes at the midpoint")
    Check(turningCard.FlipOpen:IsPlaying(), "face begins opening from the midpoint")
    TexCoords(turningCard.Face, FaceCoords(28), "community card changes face only at the flip midpoint")
    Near(
        select(1, turningCard.FlipOpen.Animation:GetScaleFrom()),
        FLIP_EDGE_SCALE,
        "opening flip begins at the same narrow edge"
    )
    Near(select(1, turningCard.FlipOpen.Animation:GetScaleTo()), 1, "opening flip restores full width")
    Same(turningCard.FlipOpen.Animation:GetSmoothing(), "OUT", "opening flip eases into the revealed face")
    Test.AdvanceAnimations(FLIP_HALF_SECONDS)
    Check(not turningCard.FlipOpen:IsPlaying() and not turningCard.flipPending, "card flip finishes cleanly")
    Near(
        localRow.Cards[1].FlipClose.Animation:GetDuration(),
        FLIP_HALF_SECONDS,
        "player-card reveals keep the compact flip pace"
    )
    Check(not localRow.DealerChip:IsShown(), "dealer handoff clears the previous dealer row")
    Check(actorRow.DealerChip:IsShown(), "dealer handoff marks the new button row")
    currentView.buttonSeat = 1
    Cards.Table:Render(currentView)

    currentView.state = "complete"
    currentView.showdown = true
    currentView.actionDeadline = nil
    currentView.actorSeat = nil
    currentView.seats[2].holeCards = { 26, 52 }
    Cards.Table:Render(currentView)
    actorRow = FindDisplayRow(2)
    Check(
        actorRow.Cards[1].FlipClose:IsPlaying() and actorRow.Cards[2].FlipClose:IsPlaying(),
        "showdown starts both opponent-card flips"
    )
    TexCoords(actorRow.Cards[1].Face, {
        FIRST_LEFT / ATLAS_WIDTH,
        (FIRST_LEFT + CARD_WIDTH) / ATLAS_WIDTH,
        BACK_TOP / ATLAS_HEIGHT,
        (BACK_TOP + CARD_HEIGHT) / ATLAS_HEIGHT,
    }, "showdown retains the first opponent back before the midpoint")
    Test.AdvanceAnimations(FLIP_HALF_SECONDS)
    TexCoords(actorRow.Cards[1].Face, FaceCoords(26), "showdown first opponent card")
    TexCoords(actorRow.Cards[2].Face, FaceCoords(52), "showdown second opponent card")
    Check(
        actorRow.Cards[1].FlipOpen:IsPlaying() and actorRow.Cards[2].FlipOpen:IsPlaying(),
        "showdown opens both opponent faces after the midpoint"
    )
    Test.AdvanceAnimations(FLIP_HALF_SECONDS)
    Check(not actorRow.Cards[1].concealed, "showdown removes opponent backs")

    local foldingRow = FindDisplayRow(3)
    local trailingRow = FindDisplayRow(1)
    local fullPlayerHeight = Cards.Table.playerList:GetHeight()
    local fullContentHeight = Cards.Table.content:GetHeight()
    local trailingTop = trailingRow:GetTop()
    local controlTop = Cards.Table.controlBar:GetTop()
    local foldPlays = foldingRow.PlayerTransition.playCalls
    local foldStops = foldingRow.PlayerTransition.stopCalls
    currentView.seats[3].folded = true
    Cards.Table:Render(currentView)
    Same(foldingRow.PlayerTransition.playCalls, foldPlays + 1, "fold transition starts one row collapse")
    Check(foldingRow.PlayerTransition:IsPlaying(), "folded row collapse remains active until its native finish")
    Same(foldingRow.PlayerTransition.Scale.kind, "Scale", "folded row uses one native Scale animation")
    Near(
        foldingRow.PlayerTransition.Scale:GetDuration(),
        playerTransitionSeconds,
        "fold collapse uses the compact duration"
    )
    Near(select(1, foldingRow.PlayerTransition.Scale:GetScaleFrom()), 1, "fold collapse retains its full width")
    Near(select(2, foldingRow.PlayerTransition.Scale:GetScaleFrom()), 1, "fold collapse starts at full height")
    Near(select(1, foldingRow.PlayerTransition.Scale:GetScaleTo()), 1, "fold collapse never narrows the row")
    Near(
        select(2, foldingRow.PlayerTransition.Scale:GetScaleTo()),
        playerTransitionEdge,
        "fold collapse shrinks vertically to a narrow edge"
    )
    Same(foldingRow.PlayerTransition.Scale:GetOrigin(), "TOP", "folded row collapses upward around its top edge")
    Same(
        foldingRow.PlayerTransition.Scale:GetSmoothing(),
        "NONE",
        "fold scale stays synchronized with linear list reflow"
    )
    Check(
        foldingRow.Cards[1]:IsShown() and foldingRow.Cards[2]:IsShown(),
        "folding leaves the normal two-card presentation intact while the row exits"
    )
    Cards.Table:Render(currentView)
    Same(foldingRow.PlayerTransition.playCalls, foldPlays + 1, "repeated projections never restart the fold collapse")
    Same(foldingRow.PlayerTransition.stopCalls, foldStops, "repeated projections never cancel the fold collapse")
    local foldUpdate = Cards.Table.playerList:GetScript("OnUpdate")
    Check(type(foldUpdate) == "function", "active fold owns one shared player-list layout callback")
    foldUpdate(Cards.Table.playerList, playerTransitionSeconds / 2)
    PixelNear(
        Cards.Table.playerList:GetHeight(),
        fullPlayerHeight - PLAYER_ROW_HEIGHT / 2,
        "fold collapse shrinks the player list continuously"
    )
    PixelNear(trailingRow:GetTop(), trailingTop + PLAYER_ROW_HEIGHT / 2, "following rows slide upward with the fold")
    PixelNear(
        Cards.Table.content:GetHeight(),
        fullContentHeight - PLAYER_ROW_HEIGHT / 2,
        "fold collapse shrinks the visible table continuously"
    )
    PixelNear(
        Cards.Table.controlBar:GetTop(),
        controlTop + PLAYER_ROW_HEIGHT / 2,
        "downstream controls follow the collapsing player row"
    )
    Test.AdvanceAnimations(playerTransitionSeconds)
    Check(not foldingRow:IsShown(), "folded player row hides when its collapse completes")
    Same(FindDisplayRow(3), nil, "folded player is removed from the visible hand")
    Same(FindDisplayRow(2), actorRow, "remaining leading player keeps its stable display row")
    Same(FindDisplayRow(1), trailingRow, "remaining local player keeps its stable display row")
    Near(Cards.Table.playerList:GetHeight(), fullPlayerHeight - PLAYER_ROW_HEIGHT, "completed fold removes one row")
    Near(Cards.Table.content:GetHeight(), fullContentHeight - PLAYER_ROW_HEIGHT, "completed fold shortens the table")
    Near(trailingRow:GetTop(), trailingTop + PLAYER_ROW_HEIGHT, "following player fills the folded row's space")
    Near(Cards.Table.controlBar:GetTop(), controlTop + PLAYER_ROW_HEIGHT, "controls fill the folded row's space")
    Same(Cards.Table.playerList:GetScript("OnUpdate"), nil, "completed fold releases its layout callback")
    Cards.Table:Render(currentView)
    Same(foldingRow.PlayerTransition.playCalls, foldPlays + 1, "completed fold cannot replay on refresh")
    Check(not foldingRow:IsShown(), "completed folded row stays hidden across refreshes")

    local collapsedPlayerHeight = Cards.Table.playerList:GetHeight()
    local handSession = currentView.session
    currentView = NewView(3, {
        session = handSession,
        state = "preflop",
        handId = "return-hand",
        buttonSeat = 1,
        actorSeat = 3,
    })
    for _, seat in ipairs(currentView.seats) do
        seat.inHand = true
    end
    local entryPlays = foldingRow.PlayerTransition.playCalls
    local entryStops = foldingRow.PlayerTransition.stopCalls
    Cards.Table:Render(currentView)
    Same(FindPlayerRow("player-3"), foldingRow, "the next hand retains the folded player's physical row")
    Same(foldingRow.PlayerTransition.playCalls, entryPlays + 1, "the next hand starts one downward row entry")
    Check(foldingRow.PlayerTransition:IsPlaying(), "the returning player remains in its native entry animation")
    Near(select(1, foldingRow.PlayerTransition.Scale:GetScaleFrom()), 1, "entry retains the player's full width")
    Near(
        select(2, foldingRow.PlayerTransition.Scale:GetScaleFrom()),
        playerTransitionEdge,
        "entry starts at the collapsed top edge"
    )
    Near(select(1, foldingRow.PlayerTransition.Scale:GetScaleTo()), 1, "entry never widens the player row")
    Near(select(2, foldingRow.PlayerTransition.Scale:GetScaleTo()), 1, "entry expands to the full row height")
    Same(foldingRow.PlayerTransition.Scale:GetOrigin(), "TOP", "entry expands downward from the row's top edge")
    Same(
        foldingRow.PlayerTransition.Scale:GetSmoothing(),
        "NONE",
        "entry scale stays synchronized with linear list reflow"
    )
    Near(Cards.Table.playerList:GetHeight(), collapsedPlayerHeight, "entry begins without snapping list height")
    local entryContentHeight = Cards.Table.content:GetHeight()
    local entryTrailingTop = trailingRow:GetTop()
    local entryControlTop = Cards.Table.controlBar:GetTop()
    Cards.Table:Render(currentView)
    Same(foldingRow.PlayerTransition.playCalls, entryPlays + 1, "refresh cannot restart a player entry")
    Same(foldingRow.PlayerTransition.stopCalls, entryStops, "refresh cannot cancel a player entry")
    local entryUpdate = Cards.Table.playerList:GetScript("OnUpdate")
    Check(type(entryUpdate) == "function", "active entry shares the player-list layout callback")
    entryUpdate(Cards.Table.playerList, playerTransitionSeconds / 2)
    PixelNear(
        Cards.Table.playerList:GetHeight(),
        collapsedPlayerHeight + PLAYER_ROW_HEIGHT / 2,
        "entry expands the player list continuously"
    )
    PixelNear(
        trailingRow:GetTop(),
        entryTrailingTop - PLAYER_ROW_HEIGHT / 2,
        "following rows slide downward with the entry"
    )
    PixelNear(
        Cards.Table.content:GetHeight(),
        entryContentHeight + PLAYER_ROW_HEIGHT / 2,
        "entry expands the visible table continuously"
    )
    PixelNear(
        Cards.Table.controlBar:GetTop(),
        entryControlTop - PLAYER_ROW_HEIGHT / 2,
        "downstream controls follow the expanding row"
    )
    Test.AdvanceAnimations(playerTransitionSeconds)
    Same(FindDisplayRow(3), foldingRow, "the returning player finishes in its original row")
    Near(Cards.Table.playerList:GetHeight(), PLAYER_ROW_HEIGHT * 3, "the next hand restores every player row")
    Near(
        Cards.Table.content:GetHeight(),
        entryContentHeight + PLAYER_ROW_HEIGHT,
        "the next hand restores the full table height"
    )
    Same(Cards.Table.playerList:GetScript("OnUpdate"), nil, "completed entry releases its layout callback")
    Check(foldingRow.ActiveBackground:IsShown(), "the returning actor receives the full-row backdrop")

    local reconnectRow = foldingRow
    local reconnectLeader = FindPlayerRow("player-2")
    local reconnectTrailer = FindPlayerRow("player-1")
    currentView.seats[3].connected = false
    local leavePlays = reconnectRow.PlayerTransition.playCalls
    Cards.Table:Render(currentView)
    Same(reconnectRow.PlayerTransition.playCalls, leavePlays + 1, "leaving starts one upward row exit")
    Check(not reconnectRow.ActiveBackground:IsShown(), "a departing actor loses its backdrop immediately")
    Test.AdvanceAnimations(playerTransitionSeconds)
    Check(not reconnectRow:IsShown(), "a disconnected player collapses out of the table")
    Same(FindPlayerRow("player-2"), reconnectLeader, "leaving preserves the leading player's row identity")
    Same(FindPlayerRow("player-1"), reconnectTrailer, "leaving preserves the trailing player's row identity")
    currentView.seats[3].connected = true
    local rejoinPlays = reconnectRow.PlayerTransition.playCalls
    Cards.Table:Render(currentView)
    Same(FindPlayerRow("player-3"), reconnectRow, "rejoining reuses the disconnected player's row")
    Same(reconnectRow.PlayerTransition.playCalls, rejoinPlays + 1, "rejoining starts one downward row entry")
    Near(
        select(2, reconnectRow.PlayerTransition.Scale:GetScaleFrom()),
        playerTransitionEdge,
        "rejoining starts from the collapsed edge"
    )
    Test.AdvanceAnimations(playerTransitionSeconds)
    Check(reconnectRow:IsShown(), "rejoining restores the player after the entry finishes")

    currentView.seats[3].connected = false
    local reversalPlays = reconnectRow.PlayerTransition.playCalls
    local reversalStops = reconnectRow.PlayerTransition.stopCalls
    Cards.Table:Render(currentView)
    local reversalUpdate = Cards.Table.playerList:GetScript("OnUpdate")
    reversalUpdate(Cards.Table.playerList, playerTransitionSeconds / 2)
    Test.AdvanceAnimations(playerTransitionSeconds / 2)
    Near(reconnectRow.layoutHeight, PLAYER_ROW_HEIGHT / 2, "partial leave retains its exact rendered height")
    currentView.seats[3].connected = true
    Cards.Table:Render(currentView)
    Same(reconnectRow.PlayerTransition.playCalls, reversalPlays + 2, "mid-exit rejoin starts one reverse transition")
    Same(reconnectRow.PlayerTransition.stopCalls, reversalStops + 1, "mid-exit rejoin cancels only the old direction")
    Near(
        select(2, reconnectRow.PlayerTransition.Scale:GetScaleFrom()),
        0.5,
        "mid-exit rejoin resumes from the current linear scale"
    )
    Near(
        reconnectRow.PlayerTransition.Scale:GetDuration(),
        playerTransitionSeconds / 2,
        "mid-exit rejoin uses only the remaining proportional duration"
    )
    Test.AdvanceAnimations(playerTransitionSeconds / 2)
    Near(reconnectRow.layoutHeight, PLAYER_ROW_HEIGHT, "reversed rejoin returns smoothly to full height")

    currentView = NewView(2)
    Cards.Table:Render(currentView)
    local existingPlayerOne = FindPlayerRow("player-1")
    local existingPlayerTwo = FindPlayerRow("player-2")
    currentView.rules.maxPlayers = 3
    currentView.seats[3] = NewSeat(3, { id = "new-player", name = "New Player" })
    Cards.Table:Render(currentView)
    local joinedRow = FindPlayerRow("new-player")
    Check(joinedRow and joinedRow:IsShown(), "a new player appears through a visible entry row")
    Check(joinedRow.PlayerTransition:IsPlaying(), "a new player's downward entry remains active")
    Same(joinedRow.Name.Text:GetText(), "New Player", "a joining row renders the new identity before expanding")
    Same(FindPlayerRow("player-1"), existingPlayerOne, "joining preserves the first existing player's row")
    Same(FindPlayerRow("player-2"), existingPlayerTwo, "joining preserves the second existing player's row")
    Near(Cards.Table.playerList:GetHeight(), PLAYER_ROW_HEIGHT * 2, "joining begins without snapping list height")
    local joinPlays = joinedRow.PlayerTransition.playCalls
    Cards.Table:Render(currentView)
    Same(joinedRow.PlayerTransition.playCalls, joinPlays, "refresh cannot restart a new-player entry")
    Test.AdvanceAnimations(playerTransitionSeconds)
    Near(Cards.Table.playerList:GetHeight(), PLAYER_ROW_HEIGHT * 3, "joining restores one complete row")

    local authoritativeJoinView = currentView
    local authoritativeJoinHeight = Cards.Table.playerList:GetHeight()
    local placeholderRows, placeholderPlays = {}, {}
    for playerId, row in pairs(Cards.Table.playerRows) do
        placeholderRows[playerId] = row
        placeholderPlays[row] = row.PlayerTransition.playCalls
    end
    Cards.Table:Render({
        role = "participant",
        state = "paused",
        session = currentView.session,
        sessionId = currentView.session,
        playerId = currentView.playerId,
        notice = L.W_RESTRICTED,
    })
    Near(
        Cards.Table.playerList:GetHeight(),
        authoritativeJoinHeight,
        "a restricted seatless placeholder preserves the authoritative player list"
    )
    for playerId, row in pairs(placeholderRows) do
        Same(FindPlayerRow(playerId), row, "a seatless placeholder preserves row ownership for " .. playerId)
        Same(
            row.PlayerTransition.playCalls,
            placeholderPlays[row],
            "a seatless placeholder starts no membership transition for " .. playerId
        )
    end
    currentView = authoritativeJoinView
    Cards.Table:Render(currentView)

    localRow = FindDisplayRow(1)
    Check(
        not localRow.Cards[1]:IsShown() and not localRow.Cards[2]:IsShown(),
        "a fresh between-hands session owns no stale private cards"
    )
    for cardIndex, card in ipairs(Cards.Table.board) do
        Check(
            card:IsShown() and card.concealed and card.cardId == nil,
            "between hands replaces stale community faces with edit-mode backs " .. cardIndex
        )
    end

    currentView = NewView(8, {
        state = "preflop",
        handId = "replacement-hand",
        actorSeat = 4,
        buttonSeat = 4,
    })
    for _, seat in ipairs(currentView.seats) do
        seat.inHand = true
    end
    Cards.Table:Render(currentView)
    local departingRow = FindPlayerRow("player-4")
    local stableReplacementRows = {}
    for seatNumber = 1, 8 do
        if seatNumber ~= 4 then
            stableReplacementRows[seatNumber] = FindPlayerRow("player-" .. seatNumber)
        end
    end
    Check(departingRow.ActiveBackground:IsShown(), "the outgoing fixture begins as the highlighted actor")
    Check(departingRow.DealerChip:IsShown(), "the outgoing fixture begins with its dealer marker")
    currentView.seats[4] = NewSeat(4, {
        id = "replacement-player",
        name = "Replacement Player",
        inHand = true,
    })
    local replacementPlays = departingRow.PlayerTransition.playCalls
    Cards.Table:Render(currentView)
    Same(FindPlayerRow("player-4"), departingRow, "a full-table departure retains its row during collapse")
    Same(FindPlayerRow("replacement-player"), nil, "a full-table replacement waits for the outgoing row")
    Same(departingRow.Name.Text:GetText(), "Player 4", "departure content is not repainted during collapse")
    Check(not departingRow.ActiveBackground:IsShown(), "a departing identity loses the shared seat's actor backdrop")
    Check(not departingRow.DealerChip:IsShown(), "a departing identity releases its transient dealer marker")
    Cards.Table:Render(currentView)
    Same(departingRow.PlayerTransition.playCalls, replacementPlays + 1, "refresh cannot restart a replacement exit")
    Test.AdvanceAnimations(playerTransitionSeconds)
    Same(FindPlayerRow("player-4"), nil, "the departed identity releases ownership at zero height")
    Same(
        FindPlayerRow("replacement-player"),
        departingRow,
        "the replacement reuses the released physical row before expanding"
    )
    Same(departingRow.Name.Text:GetText(), "Replacement Player", "the replacement binds only after the old exit")
    Check(departingRow.PlayerTransition:IsPlaying(), "the full-table replacement starts a downward entry")
    Check(departingRow.ActiveBackground:IsShown(), "the replacement receives the actor backdrop after binding")
    for seatNumber, stableRow in pairs(stableReplacementRows) do
        Same(
            FindPlayerRow("player-" .. seatNumber),
            stableRow,
            "full-table replacement preserves row identity " .. seatNumber
        )
    end
    Test.AdvanceAnimations(playerTransitionSeconds)
    Near(Cards.Table.playerList:GetHeight(), PLAYER_ROW_HEIGHT * 8, "replacement entry restores full-table height")
    Same(#Cards.Table.playerRowOrder, 8, "replacement never allocates a ninth display row")

    currentView = NewView(8, {
        state = "preflop",
        handId = "status-hand",
        buttonSeat = 1,
        smallBlindSeat = 2,
        bigBlindSeat = 3,
        actorSeat = 8,
        settlement = { payouts = { [3] = 25 }, refunds = {} },
    })
    for _, seat in ipairs(currentView.seats) do
        seat.inHand = true
    end
    for seatIndex, stack in pairs({ [1] = 1655, [2] = 10450, [3] = 100550, [5] = 1105000 }) do
        currentView.seats[seatIndex].stack = stack
    end
    currentView.seats[2].connected = false
    currentView.seats[4].folded = true
    currentView.seats[5].allIn = true
    currentView.seats[6].sittingOut = true
    currentView.seats[6].inHand = false
    local baselineTransitionPlays = {}
    for _, row in ipairs(Cards.Table.seats) do
        baselineTransitionPlays[row] = row.PlayerTransition.playCalls
    end
    Cards.Table:Render(currentView)
    for seatIndex, expected in pairs({ [1] = "1.66K", [3] = "100.55K", [5] = "1.11M" }) do
        Same(FindDisplayRow(seatIndex).Balance.Text:GetText(), expected, "balance uses compact Gold " .. seatIndex)
    end
    local initiallyDisconnectedRow = FindBoundRow(2)
    Check(not initiallyDisconnectedRow:IsShown(), "a first snapshot omits an already disconnected player")
    Same(
        initiallyDisconnectedRow.PlayerTransition.playCalls,
        baselineTransitionPlays[initiallyDisconnectedRow],
        "an unseen historical disconnect does not play an exit animation"
    )
    local initiallyFoldedRow = FindBoundRow(4)
    Check(not initiallyFoldedRow:IsShown(), "a first snapshot omits a player who already folded")
    Same(
        initiallyFoldedRow.PlayerTransition.playCalls,
        baselineTransitionPlays[initiallyFoldedRow],
        "an unseen historical fold does not play an exit animation"
    )
    Same(
        Cards.Table:SeatStatus(currentView, currentView.seats[2], nil, false),
        L.W_DISCONNECTED,
        "disconnected status retains priority while its row exits"
    )
    Same(DisplayStatus(3), "+25", "settlement payout is visible at the seat")
    Same(DisplayStatus(5), L.W_ALL_IN_STATE, "all-in status is visible")
    Same(DisplayStatus(6), L.W_SITTING_OUT, "sitting-out status is visible")
    Same(DisplayStatus(7), "", "social tables expose no funding status")
    local remoteActorRow = FindDisplayRow(8)
    Check(remoteActorRow.ActiveBackground:IsShown(), "remote actor receives the row backdrop")
    Same(Cards.Table.notice:GetText(), "", "remote actor relies on the highlighted row")
    currentView.actorSeat = 1
    Cards.Table:Render(currentView)
    local localActorRow = FindDisplayRow(1)
    Check(not remoteActorRow.ActiveBackground:IsShown(), "actor handoff clears the previous row backdrop")
    Check(localActorRow.ActiveBackground:IsShown(), "actor handoff highlights the new full row")
    Same(Cards.Table.notice:GetText(), "", "local actor also relies on the highlighted row")
    currentView.actorSeat = nil
    Cards.Table:Render(currentView)
    Check(not localActorRow.ActiveBackground:IsShown(), "clearing the actor removes the final row backdrop")
    Same(Cards.Table.notice:GetText(), "", "automatic active-hand progress does not claim there is no hand")

    currentView = NewView(2, {
        state = "preflop",
        handId = "action-hand",
        actorSeat = 1,
        actionDeadline = Test.now + 10,
        revision = 10,
        legalActions = {
            fold = true,
            call = true,
            callAmount = 20,
            raise = true,
            minTarget = 50,
            maxTarget = 150,
            allIn = true,
            toCall = 20,
        },
    })
    for _, seat in ipairs(currentView.seats) do
        seat.inHand = true
    end
    Cards.Table:Render(currentView)
    Check(Cards.Table.actionBar:IsShown(), "active Cards session shows the action bar")
    Same(Cards.Table.actionBar, Cards.Table.controlBar, "actions and utilities share one compact control bar")
    Same(Cards.Table.call.Text:GetText(), L.W_CALL_F:format("20"), "call button includes the Gold amount")
    Same(Cards.Table.raise.Text:GetText(), "50", "wager action replaces Raise to with the selected Gold target")
    Same(Cards.Table.amount, nil, "the wager EditBox is removed")
    Same(Cards.Table.wagerSlider:GetParent(), Cards.Table.content, "smart wager slider belongs to the table content")
    Check(Cards.Table.wagerSlider:IsShown(), "a legal raise shows the smart wager slider")
    local wagerSlider = Cards.Table.wagerSlider
    Same(wagerSlider.kind, "Slider", "wager retains native slider input behavior")
    Same(wagerSlider.template, nil, "wager slider uses no Blizzard visual template")
    Same(wagerSlider:GetOrientation(), "HORIZONTAL", "template-less wager slider sets horizontal orientation")
    Same(wagerSlider.mouse, true, "template-less wager slider enables pointer input")
    Same(wagerSlider:GetLeft(), Cards.Table.fold:GetLeft(), "wager track begins beneath Fold")
    Same(wagerSlider:GetRight(), Cards.Table.allIn:GetRight(), "wager track ends beneath All-in")
    Same(
        wagerSlider:GetWidth(),
        Cards.Table.allIn:GetRight() - Cards.Table.fold:GetLeft(),
        "wager track matches the exact action-row span"
    )
    Check(wagerSlider:GetWidth() < TABLE_WIDTH, "wager track remains narrower than the Cards HUD")
    for _, region in ipairs({ "Left", "Right", "Middle" }) do
        Same(wagerSlider[region], nil, "wager slider omits native template art: " .. region)
    end
    Same(#wagerSlider.textures, 2, "wager slider owns only its thin track and thumb")
    Same(wagerSlider.Track.kind, "Texture", "wager slider owns a simple track texture")
    Same(wagerSlider.Thumb, wagerSlider:GetThumbTexture(), "wager slider exposes its custom native thumb")
    Near(wagerSlider.Track:GetLeft(), wagerSlider:GetLeft(), "wager line shares the action row's left edge")
    Near(wagerSlider.Track:GetRight(), wagerSlider:GetRight(), "wager line shares the action row's right edge")
    Near(wagerSlider.Track.color[4], 0.3, "wager line uses a restrained muted alpha")
    Near(wagerSlider.Thumb.color[1], 1, "wager marker uses the selected Gold red channel")
    Near(wagerSlider.Thumb.color[2], 0.82, "wager marker uses the selected Gold green channel")
    Near(wagerSlider.Thumb.color[3], 0, "wager marker uses the selected Gold blue channel")
    Near(
        wagerSlider.Track:GetHeight() * wagerSlider.Track:GetEffectiveScale() / PixelUtil.GetPixelToUIUnitFactor(),
        wagerTrackPixels,
        "wager line remains two physical pixels tall"
    )
    Near(
        wagerSlider.Thumb:GetWidth() * wagerSlider.Thumb:GetEffectiveScale() / PixelUtil.GetPixelToUIUnitFactor(),
        wagerThumbWidthPixels,
        "wager marker remains three physical pixels wide"
    )
    Near(
        wagerSlider.Thumb:GetHeight() * wagerSlider.Thumb:GetEffectiveScale() / PixelUtil.GetPixelToUIUnitFactor(),
        wagerThumbHeightPixels,
        "wager marker remains ten physical pixels tall"
    )
    Same(wagerSlider.narrationLabel, L.W_WAGER, "wager slider retains a semantic narration label")
    Same(wagerSlider.narrationLabelRegion, nil, "numeric action text is not reused as the narration label")
    Same(wagerSlider.narrationValueFormatter(), "50", "wager narration reads the exact selected Gold target")
    Same(wagerSlider:NarrationGetName(), L.W_WAGER, "custom wager slider participates in native narration")
    Same(wagerSlider:NarrationGetDescription(), "50", "custom wager narration describes the selected total")
    Same(Cards.Table.raise:NarrationGetName(), L.W_WAGER .. " 50", "numeric wager action retains a semantic name")
    Same(wagerSlider:GetMinMaxValues(), 0, "wager slider starts at its minimum detent")
    Same(select(2, wagerSlider:GetMinMaxValues()), 100, "one hundred Gold span exposes every legal target")
    Same(wagerSlider:GetValueStep(), 1, "wager slider advances through integer detents")
    Check(wagerSlider:GetObeyStepOnDrag(), "wager slider snaps while dragged")
    Same(wagerSlider:GetValue(), 0, "new legal range selects its first detent")
    Same(Cards.Table.wagerTarget, 50, "raise slider starts at the projected minimum Gold target")
    Check(not Overlaps(Cards.Table.playerList, Cards.Table.controlBar), "action row clears the player list")
    Check(not Overlaps(Cards.Table.controlBar, wagerSlider), "wager slider clears the action row")
    PixelNear(
        Cards.Table.controlBar:GetBottom() - wagerSlider:GetTop(),
        wagerControlGap,
        "wager slider sits below the actions"
    )
    Near(
        Cards.Table.content:GetHeight(),
        tableActiveFixedHeight + 2 * PLAYER_ROW_HEIGHT + wagerSlider:GetHeight() + wagerControlGap,
        "legal wager row contributes only its compact height"
    )
    local originalWagerScale = Cards.Store:GetTableSettings().scale
    for _, scale in ipairs({ 70, 100, 125, 150 }) do
        Cards.Store:SaveTableSettings({ scale = scale })
        Cards.Table:ApplySettings()
        Cards.Table:Render(currentView)
        Near(wagerSlider:GetLeft(), Cards.Table.fold:GetLeft(), "wager left edge remains aligned at " .. scale .. "%")
        Near(
            wagerSlider:GetRight(),
            Cards.Table.allIn:GetRight(),
            "wager right edge remains aligned at " .. scale .. "%"
        )
        Check(wagerSlider:GetWidth() < TABLE_WIDTH, "wager remains narrower than the HUD at " .. scale .. "%")
        Check(
            wagerSlider:GetHeight() + EPSILON >= wagerSlider.Thumb:GetHeight(),
            "wager marker remains inside its hitbox at " .. scale .. "%"
        )
    end
    Cards.Store:SaveTableSettings({ scale = originalWagerScale })
    Cards.Table:ApplySettings()
    Cards.Table:Render(currentView)
    for _, button in ipairs({
        Cards.Table.fold,
        Cards.Table.call,
        Cards.Table.raise,
        Cards.Table.allIn,
        Cards.Table.sitOut,
        Cards.Table.rebuy,
        Cards.Table.deal,
    }) do
        Same(button.template, nil, "compact Cards controls use template-less text buttons")
        Same(button:GetParent(), Cards.Table.controlBar, "compact Cards controls share one parent")
        Same(#(button.textures or {}), 0, "compact Cards text controls create no textures")
        for _, key in ipairs({ "background", "Background", "edges", "NineSlice", "highlight" }) do
            Same(button[key], nil, "compact Cards text controls create no decorative field: " .. key)
        end
        TextShadow(button.Text, "compact Cards control")
        ShadowInset(button.Label, "compact Cards control")
    end
    TextShadow(Cards.Table.pot.Text, "pot/result summary")
    ShadowInset(Cards.Table.pot, "pot/result summary")
    TextShadow(Cards.Table.notice, "turn/status line")
    for rowIndex, row in ipairs(Cards.Table.seats) do
        TextShadow(row.Name.Text, "player name " .. rowIndex)
        TextShadow(row.Balance.Text, "player balance " .. rowIndex)
        TextShadow(row.Status.Text, "player status " .. rowIndex)
        ShadowInset(row.Name, "player name " .. rowIndex)
        ShadowInset(row.Balance, "player balance " .. rowIndex)
        ShadowInset(row.Status, "player status " .. rowIndex)
        Same(row.Marker, nil, "player row owns no text marker " .. rowIndex)
        Same(row.Funded, nil, "player row owns no funding control " .. rowIndex)
    end
    local actionsBeforeDrag = #sentActions
    Test.DragSlider(wagerSlider, 25)
    Same(#sentActions, actionsBeforeDrag, "dragging the wager slider does not submit an action")
    Same(Cards.Table.wagerTarget, 75, "wager detent resolves to its legal whole-Gold target")
    Same(Cards.Table.raise.Text:GetText(), "75", "wager action follows the selected detent")
    Same(Cards.Table.raise:NarrationGetName(), L.W_WAGER .. " 75", "wager action narration follows the detent")
    Cards.Table:Render(currentView)
    Same(wagerSlider:GetValue(), 25, "unchanged snapshot preserves the selected wager detent")
    Same(Cards.Table.wagerTarget, 75, "unchanged snapshot preserves the selected legal target")
    for _, button in ipairs({ Cards.Table.fold, Cards.Table.call, Cards.Table.raise, Cards.Table.allIn }) do
        Check(button:IsEnabled(), "projected legal action enables its exact button")
    end
    Click(Cards.Table.fold)
    Click(Cards.Table.call)
    Click(Cards.Table.raise)
    Click(Cards.Table.allIn)
    Same(sentActions[1].action, "fold", "fold button sends fold")
    Same(sentActions[2].action, "call", "call button sends call")
    Same(sentActions[3].action, "raise", "raise button sends raise")
    Same(sentActions[3].targetAmount, 75, "raise button sends the selected total target")
    Same(sentActions[4].action, "all_in", "all-in button sends all_in")

    currentView.revision = 11
    currentView.legalActions = {
        check = true,
        bet = true,
        minTarget = 30,
        maxTarget = 90,
        allIn = true,
        toCall = 0,
    }
    Cards.Table:Render(currentView)
    Same(Cards.Table.call.Text:GetText(), L.W_CHECK, "zero-call action is labelled Check")
    Same(Cards.Table.raise.Text:GetText(), "30", "opening wager action shows its minimum Gold target")
    Same(wagerSlider:GetValue(), 0, "new projection resets the slider to its first detent")
    Same(Cards.Table.wagerTarget, 30, "new projection resets the target to its minimum")
    Click(Cards.Table.call)
    Test.DragSlider(wagerSlider, 15)
    Click(Cards.Table.raise)
    Same(sentActions[5].action, "check", "check button sends check")
    Same(sentActions[6].action, "bet", "bet button sends bet")
    Same(sentActions[6].targetAmount, 45, "bet button sends the selected total target")

    currentView.revision = 12
    currentView.legalActions = {
        fold = true,
        bet = true,
        minTarget = 100,
        maxTarget = 350,
        allIn = true,
        toCall = 0,
    }
    Cards.Table:Render(currentView)
    Same(select(2, wagerSlider:GetMinMaxValues()), wagerMaxSteps, "large ranges stay bounded to smart detents")
    Same(Cards.Table.raise.Text:GetText(), "100", "whole-Gold action target is formatted without decimals")
    local previousTarget
    for detent = 0, wagerMaxSteps do
        Test.DragSlider(wagerSlider, detent)
        local target = Cards.Table.wagerTarget
        Same(target, math.floor(target), "large-range detent remains whole Gold " .. detent)
        Check(target >= 100 and target <= 350, "large-range detent stays inside its legal projection " .. detent)
        if previousTarget then
            Check(target > previousTarget, "large-range sampled legal targets remain strictly increasing " .. detent)
        end
        previousTarget = target
    end
    Same(previousTarget, 350, "sampled legal detents retain the exact maximum endpoint")
    Test.DragSlider(wagerSlider, 50)
    Same(Cards.Table.wagerTarget, 225, "middle smart detent maps to a legal integer target")
    Test.DragSlider(wagerSlider, wagerMaxSteps + 20)
    Same(wagerSlider:GetValue(), wagerMaxSteps, "wager slider clamps above its legal range")
    Same(Cards.Table.wagerTarget, 350, "final wager detent reaches the exact projected maximum")
    Click(Cards.Table.raise)
    Same(sentActions[#sentActions].targetAmount, 350, "maximum slider endpoint submits the legal maximum")

    currentView.revision = 13
    currentView.legalActions = {
        fold = true,
        bet = true,
        minTarget = 235,
        maxTarget = 235,
        allIn = true,
        toCall = 0,
    }
    Cards.Table:Render(currentView)
    Same(wagerSlider:GetMinMaxValues(), 0, "single-target wager starts at its only detent")
    Same(select(2, wagerSlider:GetMinMaxValues()), 0, "single-target wager ends at its only detent")
    Check(not wagerSlider:IsEnabled(), "single-target wager has no misleading draggable range")
    Check(Cards.Table.raise:IsEnabled(), "single-target wager keeps its action available")
    Same(Cards.Table.raise.Text:GetText(), "235", "single-target wager displays its exact legal total")
    Click(Cards.Table.raise)
    Same(sentActions[#sentActions].targetAmount, 235, "single-target wager submits its sole legal total")

    currentView.revision = 14
    currentView.legalActions = {
        fold = true,
        call = true,
        callAmount = Cards.MAX_TOTAL_CHIPS,
        allIn = true,
        toCall = Cards.MAX_TOTAL_CHIPS,
    }
    Cards.Table:Render(currentView)
    Check(Cards.Table.call.Label.scrollDistance > 0, "large legal call amounts scroll inside the compact text control")
    Check(not wagerSlider:IsShown(), "call/all-in-only turn hides the regular wager slider")
    Same(Cards.Table.raise.Text:GetText(), "", "unavailable regular wager leaves no stale action value")

    currentView.revision = 15
    currentView.legalActions = { fold = true, bet = true, minTarget = 10, maxTarget = 30, allIn = true, toCall = 0 }
    Cards.Table:Render(currentView)
    Test.DragSlider(wagerSlider, 12)
    Same(Cards.Table.wagerTarget, 22, "pending-state fixture selects a legal target")
    currentView.pending = true
    Cards.Table:Render(currentView)
    Check(not Cards.Table.fold:IsEnabled(), "pending host acknowledgement disables fold")
    Check(not Cards.Table.call:IsEnabled(), "pending host acknowledgement disables check/call")
    Check(not Cards.Table.raise:IsEnabled(), "pending host acknowledgement disables bet/raise")
    Check(not Cards.Table.allIn:IsEnabled(), "pending host acknowledgement disables all-in")
    Check(wagerSlider:IsShown(), "pending host acknowledgement preserves the wager slider")
    Check(not wagerSlider:IsEnabled(), "pending host acknowledgement disables wager dragging")
    Near(wagerSlider:GetAlpha(), wagerDisabledAlpha, "pending host acknowledgement dims the wager track")
    Same(Cards.Table.wagerTarget, 22, "pending host acknowledgement preserves the selected legal target")
    Same(Cards.Table.raise.Text:GetText(), "22", "pending host acknowledgement preserves the displayed action target")

    currentView.pending = false
    currentView.actionDeadline = Test.now + 10
    Cards.Table:Render(currentView)
    Same(Cards.Table.timer:GetMinMaxValues(), 0, "turn timer starts at zero")
    Same(select(2, Cards.Table.timer:GetMinMaxValues()), 30, "turn timer uses the authored action duration")
    Near(Cards.Table.timer:GetValue(), 10, "turn timer shows exact remaining time")
    Check(Cards.Table.timer:IsShown() and Cards.Table.timer:GetScript("OnUpdate"), "live deadline animates the timer")
    Check(Cards.Table.timer.Track:IsVisible(), "live deadline retains the full timer backdrop")
    TimerGradient(10, 30)
    Near(
        (Cards.Table.board[1]:GetBottom() - Cards.Table.timer:GetTop())
            * Cards.Table.timer:GetEffectiveScale()
            / PixelUtil.GetPixelToUIUnitFactor(),
        TIMER_BOARD_GAP_PIXELS,
        "turn timer sits directly beneath the community cards"
    )
    Check(not Cards.Table.notice:IsShown(), "active timer has no empty status row below it")
    Same(Cards.Table.playerList.point[2], Cards.Table.timer, "active player list remains anchored to the timer")
    Near(
        Cards.Table.timer:GetBottom() - Cards.Table.playerList:GetTop(),
        PixelUtil.GetNearestPixelSize(0, Cards.Table.content:GetEffectiveScale(), playerTopGapPixels),
        "active player list keeps its physical gap below the timer"
    )
    Near(
        Cards.Table.timer.Track:GetHeight()
            * Cards.Table.timer.Track:GetEffectiveScale()
            / PixelUtil.GetPixelToUIUnitFactor(),
        timerTrackPixels,
        "Cards timer backdrop remains two physical pixels tall"
    )
    Near(Cards.Table.timer.Track:GetLeft(), Cards.Table.timer:GetLeft(), "Cards backdrop shares the fill's left edge")
    Near(
        Cards.Table.timer.Track:GetRight(),
        Cards.Table.timer:GetRight(),
        "Cards backdrop shares the fill's right edge"
    )
    Near(
        (Cards.Table.timer:GetTop() - Cards.Table.timer.Track:GetTop())
            * Cards.Table.timer:GetEffectiveScale()
            / PixelUtil.GetPixelToUIUnitFactor(),
        timerFillOverhangPixels,
        "Cards fill extends one physical pixel above its backdrop"
    )
    Near(
        (Cards.Table.timer.Track:GetBottom() - Cards.Table.timer:GetBottom())
            * Cards.Table.timer:GetEffectiveScale()
            / PixelUtil.GetPixelToUIUnitFactor(),
        timerFillOverhangPixels,
        "Cards fill extends one physical pixel below its backdrop"
    )
    local timerGradientCalls = Cards.Table.timer.Fill.gradientCalls
    local timerColorCreations = Test.colorCreations
    local timerFrameCount = #Test.frames
    Test.now = Test.now + 5
    Cards.Table.timer:GetScript("OnUpdate")(Cards.Table.timer, 5)
    Near(Cards.Table.timer:GetValue(), 5, "timer update follows the shared clock")
    Same(Cards.Table.timer.Fill.gradientCalls, timerGradientCalls + 1, "timer tick reapplies the native gradient")
    Same(Test.colorCreations, timerColorCreations, "timer tick reuses its gradient endpoint colors")
    Same(#Test.frames, timerFrameCount, "timer tick allocates no frame")
    TimerGradient(5, 30)
    local collapsedContentHeight = Cards.Table.content:GetHeight()
    local collapsedPlayerTop = Cards.Table.playerList:GetTop()
    currentView.state = "paused"
    Cards.Table:Render(currentView)
    Same(Cards.Table.notice:GetText(), L.STATUS_PAUSED, "manual pause uses generic table-paused language")
    Check(Cards.Table.notice:IsShown(), "manual pause expands the status lane")
    Same(Cards.Table.playerList.point[2], Cards.Table.notice, "expanded player rows follow the status lane")
    Near(
        Cards.Table.timer:GetBottom() - Cards.Table.notice:GetTop(),
        PixelUtil.GetNearestPixelSize(0, Cards.Table.content:GetEffectiveScale(), timerNoticeGapPixels),
        "pause notice keeps its physical gap below the timer"
    )
    Near(
        Cards.Table.notice:GetBottom() - Cards.Table.playerList:GetTop(),
        PixelUtil.GetNearestPixelSize(0, Cards.Table.content:GetEffectiveScale(), playerTopGapPixels),
        "paused player list keeps its physical gap below the notice"
    )
    Near(
        Cards.Table.content:GetHeight(),
        collapsedContentHeight
            + Cards.Table.notice:GetHeight()
            + PixelUtil.GetNearestPixelSize(0, Cards.Table.content:GetEffectiveScale(), timerNoticeGapPixels),
        "status text contributes only its notice height and timer gap"
    )
    Same(Cards.Table.timer:GetScript("OnUpdate"), nil, "paused table stops the retained deadline callback")
    Near(Cards.Table.timer:GetValue(), 5, "paused table freezes the visible timer")
    TimerGradient(5, 30)
    Test.now = Test.now + 3
    Cards.Table:UpdateTimer()
    Near(Cards.Table.timer:GetValue(), 5, "paused refresh does not consume the retained deadline")
    currentView.state = "preflop"
    Cards.Table:Render(currentView)
    Check(not Cards.Table.notice:IsShown(), "resuming collapses the cleared status lane")
    Same(Cards.Table.playerList.point[2], Cards.Table.timer, "resuming reanchors players directly to the timer")
    Near(Cards.Table.content:GetHeight(), collapsedContentHeight, "resuming restores the collapsed table height")
    Near(Cards.Table.playerList:GetTop(), collapsedPlayerTop, "resuming restores the collapsed player-list edge")
    Near(Cards.Table.timer:GetValue(), 2, "resumed table renders the active deadline again")
    TimerGradient(2, 30)
    Test.now = Test.now + 2
    Cards.Table.timer:GetScript("OnUpdate")(Cards.Table.timer, 5)
    Near(Cards.Table.timer:GetValue(), 0, "timer reaches zero at the deadline")
    TimerGradient(0, 30)
    Same(Cards.Table.timer:GetScript("OnUpdate"), nil, "expired timer stops its per-frame callback")
    Check(Cards.Table.timer:IsShown(), "expired timer retains its compact track")

    currentView = NewView(2, { state = "between_hands", revision = 20, allowRebuys = true })
    currentView.seats[1].stack = 0
    Cards.Table:Render(currentView)
    Same(Cards.Table.notice:GetText(), L.STATUS_READY, "between hands retain the ready status")
    Check(Cards.Table.notice:IsShown(), "between hands retain the expanded status lane")
    Same(Cards.Table.playerList.point[2], Cards.Table.notice, "between-hand players follow the visible status")
    Check(Cards.Table.timer:IsShown(), "between hands retain the inactive timer track")
    Check(Cards.Table.timer.Track:IsVisible(), "between hands retain the full timer backdrop")
    Near(Cards.Table.timer:GetValue(), 0, "between-hand timer is empty without a deadline")
    Same(Cards.Table.timer:GetScript("OnUpdate"), nil, "between-hand timer owns no update callback")
    Check(Cards.Table.sitOut:IsShown() and Cards.Table.sitOut:IsEnabled(), "between hands exposes Sit out")
    Check(Cards.Table.rebuy:IsShown() and Cards.Table.rebuy:IsEnabled(), "zero balance exposes Rebuy")
    Check(Cards.Table.deal:IsShown() and Cards.Table.deal:IsEnabled(), "host can deal between hands")
    Click(Cards.Table.sitOut)
    Click(Cards.Table.rebuy)
    Click(Cards.Table.deal)
    Same(sitOutRequests[#sitOutRequests], true, "Sit out sends the requested between-hand state")
    Same(rebuyRequests, 1, "Rebuy routes once through the session")
    Same(dealRequests, 1, "Deal routes once through the host controller")
    currentView.seats[1].sittingOut = true
    currentView.revision = 21
    Cards.Table:Render(currentView)
    Same(Cards.Table.sitOut.Text:GetText(), L.W_SIT_IN, "sitting-out player receives a Sit in action")
    Click(Cards.Table.sitOut)
    Same(sitOutRequests[#sitOutRequests], false, "Sit in clears the between-hand state")

    currentView = NewView(3, {
        state = "flop",
        handId = "history-hand",
        actorSeat = 3,
        actions = {
            { seat = 1, action = "call", paid = 5, street = "preflop" },
            { seat = 2, action = "call", paid = 15, street = "flop" },
            { seat = 2, action = "raise", target = 40, street = "flop" },
            { seat = 3, action = "check", street = "flop" },
        },
    })
    Cards.Store:SaveTableSettings({ showHistory = true })
    Cards.Table:ApplySettings()
    Cards.Table:Render(currentView)
    Same(
        Cards.Table:ActionStatus({ action = "small_blind", paid = 5 }),
        L.W_POSTED_F:format("5"),
        "small blind history uses a generic Gold posting status"
    )
    Same(
        Cards.Table:ActionStatus({ action = "big_blind", paid = 10 }),
        L.W_POSTED_F:format("10"),
        "big blind history uses a generic Gold posting status"
    )
    Same(DisplayStatus(2), L.W_RAISED_TO_F:format("40"), "current-street status uses the latest Gold action")
    Same(DisplayStatus(3), L.W_CHECKED, "latest action status takes priority over the actor fallback")
    Same(DisplayStatus(1), "", "prior-street actions do not leak into the current status")
    currentView.seats[2].folded = true
    Cards.Table:Render(currentView)
    Same(DisplayStatus(2), L.W_FOLDED, "folded state takes priority over latest action")
    currentView.seats[2].connected = false
    Cards.Table:Render(currentView)
    Same(DisplayStatus(2), L.W_DISCONNECTED, "disconnect takes priority over folded state")
    currentView.seats[2].connected = true
    currentView.seats[2].folded = false
    Cards.Store:SaveTableSettings({ showHistory = false })
    Cards.Table:ApplySettings()
    Cards.Table:Render(currentView)
    Same(DisplayStatus(2), "", "disabled history removes latest-action status fallback")
    Same(DisplayStatus(3), "", "actor backdrop replaces a redundant row status")

    local winnerHoles = { Card("AS"), Card("2D") }
    local winningBoard = { Card("AC"), Card("AH"), Card("KH"), Card("KD"), Card("3D") }
    currentView = NewView(2, {
        state = "river",
        handId = "unique-showdown-winner",
        showdown = true,
        board = winningBoard,
    })
    currentView.seats[1].inHand = true
    currentView.seats[1].holeCards = { Card("QS"), Card("QD") }
    currentView.seats[2].inHand = true
    currentView.seats[2].holeCards = winnerHoles
    local contentChildren = #Cards.Table.content.children
    Cards.Table:Render(currentView)
    Test.AdvanceAnimations(FINAL_BOARD_FLIP_HALF_SECONDS)
    Test.AdvanceAnimations(FINAL_BOARD_FLIP_HALF_SECONDS)
    currentView.state = "complete"
    currentView.settlement = { payouts = { [2] = 200 }, refunds = {} }
    Cards.Table:Render(currentView)
    Same(
        Cards.Table.pot.Text:GetText(),
        L.W_WINS_HAND_F:format("Player 2", "200", L.W_HAND_FULL_HOUSE),
        "unique showdown winner summary includes the evaluated hand category"
    )
    Same(#Cards.Table.content.children, contentChildren, "winner presentation reuses its stable card frames")
    for cardIndex, card in ipairs(Cards.Table.winnerCards) do
        Check(card:IsShown() and card.Face:IsShown(), "unique winner retains hole-card slot " .. cardIndex)
        Same(card.cardId, winnerHoles[cardIndex], "winner card retains its projected identity " .. cardIndex)
    end
    Check(not Cards.Table.winnerCards[1].concealed, "winning hole card remains face up")
    Check(Cards.Table.winnerCards[2].concealed, "irrelevant hole card turns face down")
    Check(Cards.Table.winnerCards[2].FlipClose:IsPlaying(), "irrelevant hole card begins its closing flip")
    Check(Cards.Table.board[5].concealed, "irrelevant community card turns face down")
    Check(Cards.Table.board[5].FlipClose:IsPlaying(), "irrelevant community card begins its closing flip")
    local communityFlipPlays = Cards.Table.board[5].FlipClose.playCalls
    local communityFlipStops = Cards.Table.board[5].FlipClose.stopCalls
    Cards.Table:Render(currentView)
    Same(
        Cards.Table.board[5].FlipClose.playCalls,
        communityFlipPlays,
        "refreshing a winning hand never restarts its community-card flip"
    )
    Same(
        Cards.Table.board[5].FlipClose.stopCalls,
        communityFlipStops,
        "refreshing a winning hand never cancels its community-card flip"
    )
    Check(Cards.Table.board[5].FlipClose:IsPlaying(), "community-card flip continues from its original progress")
    TexCoords(Cards.Table.winnerCards[2].Face, FaceCoords(winnerHoles[2]), "irrelevant hole face before midpoint")
    TexCoords(Cards.Table.board[5].Face, FaceCoords(winningBoard[5]), "irrelevant community face before midpoint")
    Test.AdvanceAnimations(FINAL_BOARD_FLIP_HALF_SECONDS)
    TexCoords(Cards.Table.winnerCards[2].Face, BackCoords(), "irrelevant hole back after midpoint")
    TexCoords(Cards.Table.board[5].Face, BackCoords(), "irrelevant community back after midpoint")
    Test.AdvanceAnimations(FINAL_BOARD_FLIP_HALF_SECONDS)
    Check(not Cards.Table.board[5].flipPending, "irrelevant community-card flip finishes once")
    Cards.Table:Render(currentView)
    Same(
        Cards.Table.board[5].FlipClose.playCalls,
        communityFlipPlays,
        "refreshing a completed winning hand cannot replay its community-card flip"
    )
    Check(not Cards.Table.board[5].FlipClose:IsPlaying(), "completed community card remains still")
    local faceUp, faceDown = 0, 0
    for _, group in ipairs({ Cards.Table.board, Cards.Table.winnerCards }) do
        for cardIndex, card in ipairs(group) do
            Check(card:IsShown(), "winning-hand strip retains stable slot " .. cardIndex)
            if card.concealed then
                faceDown = faceDown + 1
            else
                faceUp = faceUp + 1
                TexCoords(card.Face, FaceCoords(card.cardId), "canonical winning face " .. cardIndex)
            end
            Check(not card.Face.desaturated, "winning-hand strip never desaturates face " .. cardIndex)
            Check(not card.Surface.desaturated, "winning-hand strip never desaturates surface " .. cardIndex)
        end
    end
    Same(faceUp, 5, "sole winner leaves exactly the canonical five face up")
    Same(faceDown, 2, "sole winner flips exactly two irrelevant cards face down")
    Near(
        Cards.Table.winnerCards[1]:GetRight(),
        Cards.Table.content:GetRight(),
        "visible winner cards remain pinned to the fixed table width"
    )

    currentView = NewView(2, {
        state = "complete",
        handId = "uncontested-fold-winner",
        showdown = false,
        settlement = { payouts = { [2] = 15 }, refunds = {} },
    })
    currentView.seats[1].inHand = true
    currentView.seats[1].folded = true
    currentView.seats[2].inHand = true
    Cards.Table:Render(currentView)
    Same(FindDisplayRow(1), nil, "uncontested folded player stays outside the completed hand")
    Check(FindDisplayRow(2) ~= nil, "uncontested winner remains in the completed hand")
    Near(Cards.Table.playerList:GetHeight(), PLAYER_ROW_HEIGHT, "completed fold-only hand shows one remaining row")
    Same(
        Cards.Table.pot.Text:GetText(),
        L.W_WINS_F:format("Player 2", "15"),
        "uncontested winner keeps the amount-only private result"
    )
    for cardIndex, card in ipairs(Cards.Table.winnerCards) do
        Check(not card:IsShown(), "uncontested winner keeps private hole card " .. cardIndex)
    end

    currentView = NewView(3, {
        state = "complete",
        handId = "multiple-showdown-winners",
        showdown = true,
        board = { Card("2C"), Card("3D"), Card("4H"), Card("9S"), Card("KC") },
        settlement = {
            payouts = { [2] = 180, [3] = 60 },
            refunds = { [1] = 20, [3] = 40 },
        },
    })
    currentView.seats[1].committed = 20
    currentView.seats[2].committed = 100
    currentView.seats[2].inHand = true
    currentView.seats[2].holeCards = { Card("AS"), Card("5S") }
    currentView.seats[3].committed = 100
    currentView.seats[3].inHand = true
    currentView.seats[3].holeCards = { Card("KH"), Card("KD") }
    currentView.seats[2].connected = false
    Cards.Table:Render(currentView)
    Same(
        Cards.Table.pot.Text:GetText(),
        L.W_WINS_HAND_F:format("Player 2", "180", L.W_HAND_STRAIGHT)
            .. " · "
            .. L.W_WINS_HAND_F:format("Player 3", "60", L.W_HAND_THREE_OF_A_KIND),
        "host settlement payouts include every winner and hand category"
    )
    for cardIndex, card in ipairs(Cards.Table.winnerCards) do
        Check(not card:IsShown(), "multiple winners hide the arbitrary extra hole-card pair " .. cardIndex)
    end
    for cardIndex, card in ipairs(Cards.Table.board) do
        Check(not card.Face.desaturated, "multiple winners keep every community face saturated " .. cardIndex)
        Check(not card.Surface.desaturated, "multiple winners keep every community surface saturated " .. cardIndex)
    end
    Check(
        Cards.Table.pot.Text:GetText():find("Player 1", 1, true) == nil,
        "refund-only seats are excluded from the winner summary"
    )
    Same(DisplayStatus(1), "0", "fully refunded Gold produces a zero hand net")
    Same(
        Cards.Table:SeatStatus(currentView, currentView.seats[2], nil, true),
        "+80",
        "settlement net takes priority while a disconnected row exits"
    )
    Same(DisplayStatus(3), "0", "payout plus refund is netted against committed Gold")
    Same(Cards.Table.notice:GetText(), "", "winner summary needs no duplicate settled notice")
    Check(not Cards.Table.notice:IsShown(), "winner summary collapses the redundant status lane")
    Check(Cards.Table.timer:IsShown(), "completed hand retains the inactive timer track")
    Check(Cards.Table.timer.Track:IsVisible(), "completed hand retains the full timer backdrop")
    currentView.state = "paused"
    currentView.baseState = "complete"
    currentView.handId = "paused-host-settlement"
    Cards.Table:Render(currentView)
    Same(
        Cards.Table.pot.Text:GetText(),
        L.W_WINS_HAND_F:format("Player 2", "180", L.W_HAND_STRAIGHT)
            .. " · "
            .. L.W_WINS_HAND_F:format("Player 3", "60", L.W_HAND_THREE_OF_A_KIND),
        "paused host projection keeps its settled payout summary"
    )
    Same(Cards.Table.notice:GetText(), "", "paused settlement keeps the winner summary as its only heading")
    Check(not Cards.Table.notice:IsShown(), "paused settlement keeps the redundant status lane collapsed")
    Check(Cards.Table.timer:IsShown(), "paused settlement retains the inactive timer track")
    Check(Cards.Table.timer.Track:IsVisible(), "paused settlement retains the full timer backdrop")

    currentView = NewView(2, {
        state = "paused",
        handId = "paused-client-settlement",
        showdown = true,
        board = winningBoard,
    })
    currentView.seats[1].inHand = true
    currentView.seats[1].holeCards = winnerHoles
    currentView.seats[2].inHand = true
    currentView.seats[2].holeCards = { Card("QS"), Card("QD") }
    currentView.seats[1].payout = 240
    currentView.seats[1].refund = 10
    currentView.seats[1].committed = 200
    currentView.seats[2].refund = 500
    currentView.seats[2].committed = 500
    Cards.Table:Render(currentView)
    Same(
        Cards.Table.pot.Text:GetText(),
        L.W_WINS_HAND_F:format("Player 1", "240", L.W_HAND_FULL_HOUSE),
        "decoded seat payout and showdown cards drive the completed-hand summary"
    )
    Check(
        Cards.Table.pot.Text:GetText():find("Player 2", 1, true) == nil,
        "decoded refund without payout is excluded from the winner summary"
    )
    Same(DisplayStatus(1), "+50", "decoded payout and refund produce the winner's exact Gold net")
    Same(DisplayStatus(2), "0", "decoded refund-only seat does not appear to lose its returned Gold")
    Check(not Cards.Table.fold:IsShown(), "decoded settlement is not mistaken for a paused active hand")
    Cards.Store:SaveTableSettings({ showHistory = true, scale = 100, x = 0.5, y = 0.5 })
    Cards.Table:ApplySettings()

    Cards.Table:SetEditing(false)
    Check(not Cards.Table.frame.movable, "closed edit mode locks the table root")
    Check(
        not Cards.Table.dragHandle.mouse and not Cards.Table.editOutline:IsShown(),
        "closed edit mode disables drag affordances"
    )
    local lockedPosition = Cards.Store:GetTableSettings()
    Cards.Table:StartDrag()
    Check(not Cards.Table.dragging and not Cards.Table.frame.moving, "table cannot start moving outside edit mode")
    Same(Cards.Store:GetTableSettings().x, lockedPosition.x, "blocked drag does not persist horizontal position")
    Same(Cards.Store:GetTableSettings().y, lockedPosition.y, "blocked drag does not persist vertical position")
    Cards.Table:SetEditing(true)
    Check(Cards.Table.frame.movable, "edit mode unlocks the table root")
    Check(Cards.Table.dragHandle.mouse and Cards.Table.editOutline:IsShown(), "edit mode exposes its drag affordances")
    Same(
        Cards.Table.dragHandle.points.TOPLEFT[2],
        Cards.Table.board[1],
        "drag affordance starts at the first community card"
    )
    Same(
        Cards.Table.dragHandle.points.BOTTOMRIGHT[2],
        Cards.Table.board[5],
        "drag affordance ends at the last community card"
    )
    Same(Cards.Table.dragHandle:GetParent(), Cards.Table.content, "community drag handle belongs to table content")
    Same(Cards.Table.dragHandle.drag, "LeftButton", "community drag handle owns the left-button gesture")
    Same(Cards.Table.dragHandle.allPoints, nil, "community drag handle never covers the whole table")
    Near(
        Cards.Table.dragHandle:GetLeft(),
        Cards.Table.board[1]:GetLeft(),
        "drag handle starts with the first community card"
    )
    Near(Cards.Table.dragHandle:GetTop(), Cards.Table.board[1]:GetTop(), "drag handle uses the community row top")
    Near(
        Cards.Table.dragHandle:GetRight(),
        Cards.Table.board[5]:GetRight(),
        "drag handle ends with the fifth community card"
    )
    Near(
        Cards.Table.dragHandle:GetBottom(),
        Cards.Table.board[5]:GetBottom(),
        "drag handle uses the community row bottom"
    )
    Check(Cards.Table.dragHandle:GetBottom() > Cards.Table.timer:GetTop(), "community drag handle ends above the timer")
    for _, region in ipairs({
        Cards.Table.frame,
        Cards.Table.content,
        Cards.Table.pot,
        Cards.Table.timer,
        Cards.Table.playerList,
        Cards.Table.controlBar,
        Cards.Table.fold,
        Cards.Table.call,
        Cards.Table.raise,
        Cards.Table.allIn,
        Cards.Table.wagerSlider,
    }) do
        Same(region.drag, nil, "non-community Cards regions own no table drag registration")
        Same(region:GetScript("OnDragStart"), nil, "non-community Cards regions cannot move the table")
        Same(region:GetScript("OnDragStop"), nil, "non-community Cards regions cannot finish table movement")
    end
    Cards.Table.dragHandle:GetScript("OnDragStart")(Cards.Table.dragHandle)
    Check(Cards.Table.dragging and Cards.Table.frame.moving, "edit-only drag starts native frame movement")
    Cards.Table.frame.mockCenterX, Cards.Table.frame.mockCenterY = 480, 270
    local released = { Cards.Table.content:GetScaledRect() }
    local screen = { UIParent:GetScaledRect() }
    local releasedCenterX = (released[1] + released[3] / 2 - screen[1]) / screen[3]
    local releasedCenterY = (released[2] + released[4] / 2 - screen[2]) / screen[4]
    Check(releasedCenterX < 0.5 and releasedCenterY < 0.5, "drag fixture releases in the bottom-left growth zone")
    local expectedX = (released[1] - screen[1]) / screen[3]
    local expectedY = (released[2] - screen[2]) / screen[4]
    local originalSaveTableSettings = Cards.Store.SaveTableSettings
    local dropSaves = 0
    Cards.Store.SaveTableSettings = function(owner, settings)
        dropSaves = dropSaves + 1
        return originalSaveTableSettings(owner, settings)
    end
    local requestsBeforeDrop = viewRequests
    Cards.Table.dragHandle:GetScript("OnDragStop")(Cards.Table.dragHandle)
    local dropped = Cards.Store:GetTableSettings()
    Same(dropSaves, 1, "drag release persists the resolved anchor once")
    Same(viewRequests, requestsBeforeDrop + 1, "drag release immediately refreshes the active table view")
    Cards.Table.dragHandle:GetScript("OnDragStop")(Cards.Table.dragHandle)
    Same(dropSaves, 1, "stray drag stop does not persist the position again")
    Same(viewRequests, requestsBeforeDrop + 1, "stray drag stop does not refresh the table again")
    Cards.Store.SaveTableSettings = originalSaveTableSettings
    Near(dropped.x, expectedX, "drag persists the visible left growth edge")
    Near(dropped.y, expectedY, "drag persists the visible bottom growth edge")
    Same(Cards.Table.layout.horizontal, "LEFT", "released left-side content grows right")
    Same(Cards.Table.layout.vertical, "BOTTOM", "released bottom-side content grows up")
    Check(not Cards.Table.dragging and not Cards.Table.frame.moving, "drag stop clears native movement state")
    local resting = { Cards.Table.content:GetScaledRect() }
    for index = 1, 4 do
        PixelNear(resting[index], released[index], "drag release keeps visible content in place " .. index)
    end
    Grid(Cards.Table.frame, "table root")
    Grid(Cards.Table.content, "visible table content")
    Grid(Cards.Table.timer, "table timer")
    Grid(Cards.Table.actionBar, "table action bar")
    Grid(Cards.Table.board[1], "first community-card slot")
    Grid(FindDisplayRow(1), "local display row")
    Near(
        Cards.Table.timer:GetHeight() * Cards.Table.timer:GetEffectiveScale() / PixelUtil.GetPixelToUIUnitFactor(),
        TIMER_HEIGHT_PIXELS,
        "turn timer fill remains four physical pixels tall"
    )
    local droppedSnapshot = Cards.Store:GetTableSettings()
    Cards.Table:OnDisplayChanged()
    Near(Cards.Store:GetTableSettings().x, droppedSnapshot.x, "display relayout does not rewrite preferred X")
    Near(Cards.Store:GetTableSettings().y, droppedSnapshot.y, "display relayout does not rewrite preferred Y")
    Cards.Table:SetEditing(false)

    local settlements = {
        {
            id = "early-session",
            variantId = Cards.VARIANT_ID,
            endedAt = 1,
            players = {
                {
                    id = "early-player",
                    name = "Early Player",
                    buyIn = 1000,
                    rebuy = 0,
                    finalStack = 1000,
                },
            },
        },
        {
            id = "latest-session",
            variantId = Cards.VARIANT_ID,
            endedAt = 2,
            players = {
                {
                    id = "winner",
                    name = "Gold Winner",
                    buyIn = 1000,
                    rebuy = 500,
                    finalStack = 2000,
                },
                {
                    id = "runner",
                    name = "Gold Runner",
                    buyIn = 1000,
                    rebuy = 0,
                    finalStack = 500,
                },
            },
        },
    }
    Cards.Store:Bind(assert(Cards.Store:Normalize({ settlements = settlements })))
    currentView = { role = "idle", state = "idle", gameTypeId = Cards.id }
    UI:SetTab("results")
    Cards.ResultsPage:Invalidate()
    Cards.ResultsPage:Refresh()
    Same(#Cards.ResultsPage.rows, 5, "results render a heading and every player for both sessions")
    Same(Cards.ResultsPage.rows[1].kind, "heading", "newest settlement renders first")
    Check(
        Cards.ResultsPage.rows[1].Title:GetText():find(L.VARIANT_TEXAS_HOLDEM, 1, true) ~= nil,
        "session heading identifies its card game without a ledger mode"
    )
    local goldWinner = FindResult("Gold Winner")
    local goldRunner = FindResult("Gold Runner")
    local earlyPlayer = FindResult("Early Player")
    Check(goldWinner and goldRunner and earlyPlayer, "result rows retain every player")
    Same(
        goldWinner.Details:GetText(),
        L.W_RESULTS_BALANCE_F:format("1500", "2000", "+500"),
        "results format buy-in, final Gold and positive net"
    )
    Same(goldRunner.Details:GetText(), L.W_RESULTS_BALANCE_F:format("1000", "500", "-500"), "negative net is Gold")
    Same(goldWinner.Status, nil, "results own no funding or payment status")
    Same(goldWinner.Action, nil, "results own no manual payment control")

    local cachedRows = Cards.ResultsPage.rows
    local cachedFrames = #Test.frames
    local cachedContentLayouts = Cards.ResultsPage.content.sizeCalls
    local cachedTextCalls = 0
    for _, row in ipairs(cachedRows) do
        cachedTextCalls = cachedTextCalls + row.Title.textCalls + row.Details.textCalls
    end
    Cards.ResultsPage:Refresh()
    Same(Cards.ResultsPage.rows, cachedRows, "unchanged results refresh retains the rendered row list")
    Same(#Test.frames, cachedFrames, "unchanged results refresh allocates no frames")
    Same(Cards.ResultsPage.content.sizeCalls, cachedContentLayouts, "unchanged results refresh performs no layout")
    local refreshedTextCalls = 0
    for _, row in ipairs(Cards.ResultsPage.rows) do
        refreshedTextCalls = refreshedTextCalls + row.Title.textCalls + row.Details.textCalls
    end
    Same(refreshedTextCalls, cachedTextCalls, "unchanged results refresh does not rewrite row text")

    local pooledRows = { unpack(Cards.ResultsPage.rows) }
    Cards.Store:Bind(assert(Cards.Store:Normalize(nil)))
    Cards.ResultsPage:Refresh()
    Same(#Cards.ResultsPage.rows, 0, "empty results release every rendered row")
    Check(Cards.ResultsPage.empty:IsShown(), "empty results show dedicated guidance")
    for index, row in ipairs(pooledRows) do
        Check(not row:IsShown(), "released result row is hidden " .. index)
        Same(row.kind, nil, "released result row clears kind " .. index)
        Same(row.Title:GetText(), "", "released result row clears title " .. index)
        Same(row.Details:GetText(), "", "released result row clears details " .. index)
        Same(row.Status, nil, "released result row has no payment status " .. index)
        Same(row.Action, nil, "released result row has no payment control " .. index)
        Check(not row.Divider:IsShown(), "released result row clears its divider " .. index)
    end
    local framesBeforeReuse = #Test.frames
    Check(Cards.Store:AddSettlement(settlements[1]), "results accept a new settlement after their pool is emptied")
    Cards.ResultsPage:Refresh()
    Same(#Cards.ResultsPage.rows, 2, "repopulated results render one heading and player")
    Same(#Test.frames, framesBeforeReuse, "repopulated results reuse released rows")
    local reused = false
    for _, row in ipairs(Cards.ResultsPage.rows) do
        for _, previous in ipairs(pooledRows) do
            reused = reused or row == previous
        end
    end
    Check(reused, "repopulated results visibly reuse the frame pool")

    Cards.Session.IsActive = originalSession.isActive
    Cards.Session.GetView = originalSession.getView
    Cards.Session.Act = originalSession.act
    Cards.Session.SetSittingOut = originalSession.setSittingOut
    Cards.Session.Rebuy = originalSession.rebuy
    Cards.Controller.StartHand = originalController.startHand
    currentView = nil
    UI.frame:Hide()
    Same(#Test.errors, 0, "Cards presentation never reaches the WoW error handler")
    return assertions
end

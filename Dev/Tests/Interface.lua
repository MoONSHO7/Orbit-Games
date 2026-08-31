local PACK_ID = "interface-fixture"
local PREFIX = "ORBITQUIZDISC8"
local FIRST_HOST = "Alpha-TestRealm"
local SECOND_HOST = "Beta-TestRealm"
local EPSILON = 0.000001
local WINDOW_SCROLLBAR_INSET_PIXELS = 10
local HUD_SCROLLBAR_OFFSET_PIXELS = 4
local SCROLLBAR_GRAB_WIDTH = 5
local SCROLLBAR_ART_PIXELS = 2
local TIMER_PIXELS = 2
local TIMER_PROMPT_GAP_PIXELS = 2
local TIMER_ANSWER_GAP = 8
local TIMER_GRADIENT_SHADE = 0.65
local SCORE_WIDTH = 44
local SCORE_GAP_PIXELS = 8
local SCORE_RISE_PIXELS = 12
local SCORE_ANIMATION_SECONDS = 2.2
local SCORE_FADE_DELAY = 1.4
local TEXT_SHADOW_PIXELS = 2
local MIN_TEXT_HEIGHT = 16
local WRAP_LINE_HEIGHT = 14.25
local DRAKA_QUESTION = "In A Warrior Made, who sends young Draka to gather ingredients for a supposed cure?"
local COLORS = {
    normal = { 1, 1, 1, 1 },
    hovered = { 1, 0.94, 0.55, 1 },
    selected = { 1, 0.82, 0, 1 },
    correct = { 0.4, 1, 0.5, 1 },
    incorrect = { 0.85, 0.4, 0.4, 1 },
    muted = { 0.6, 0.6, 0.6, 1 },
    timeout = { 1, 0.16, 0.08, 1 },
}

return function(Quiz)
    local assertions = 0
    local UI, Widget, Main, Session = Quiz.UI, Quiz.Widget, Quiz.Main, Quiz.Session
    local defaultRules = Quiz.Rules.Normalize()
    local defaultRulesKey = Quiz.Rules.Encode(defaultRules)
    local timerStartColor, timerEndColor
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function Near(actual, expected, message)
        Check(math.abs(actual - expected) < EPSILON, message)
    end
    local function TextShadow(label)
        Check(label.shadowColorCalls and label.shadowOffsetCalls, "HUD label receives its own explicit shadow")
        local font = label:GetFontObject()
        Check(font and font ~= GameFontHighlight, "rendered HUD text is backed by an addon-owned font object")
        Check(
            font.shadowColorCalls and font.shadowOffsetCalls,
            "owned font objects also retain real native shadow attributes"
        )
        local red, green, blue, alpha = label:GetShadowColor()
        Same(red, 0, "text shadow has no red tint")
        Same(green, 0, "text shadow has no green tint")
        Same(blue, 0, "text shadow has no blue tint")
        Same(alpha, 1, "HUD text shadow is opaque black")
        local x, y = label:GetShadowOffset()
        local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
        Near(x / pixel, -TEXT_SHADOW_PIXELS, "text shadow remains two physical pixels to the left")
        Near(y / pixel, -TEXT_SHADOW_PIXELS, "text shadow remains two physical pixels downward")
        Same(label.fontCalls, nil, "rendered HUD labels never inline font files on their FontStrings")
        local fontX, fontY = font:GetShadowOffset()
        Near(fontX, x, "font-object horizontal shadow matches its rendered labels")
        Near(fontY, y, "font-object vertical shadow matches its rendered labels")
    end
    local function HUDTextShadows()
        TextShadow(Widget.prompt)
        TextShadow(Widget.scoreText)
        TextShadow(Widget.packText)
        TextShadow(Widget.winnerText)
        for _, choice in ipairs(Widget.choices) do
            TextShadow(choice.Text)
        end
    end
    local function SetupShadowsUnchanged()
        for _, frame in ipairs(Test.frames) do
            local ancestor = frame
            while ancestor and ancestor ~= UI.frame do
                ancestor = ancestor:GetParent()
            end
            if ancestor then
                Same(frame.shadowColorCalls, nil, "HUD shadow never restyles setup text controls")
                Same(frame.shadowOffsetCalls, nil, "HUD shadow never offsets setup text controls")
                for _, label in ipairs(frame.fontStrings or {}) do
                    Same(label.shadowColorCalls, nil, "setup labels retain their inherited native shadow color")
                    Same(label.shadowOffsetCalls, nil, "setup labels retain their inherited native shadow offset")
                end
            end
        end
    end
    local function Color(label, expected, message)
        Check(label.textColor, message .. ": explicit text color exists")
        for index, component in ipairs(expected) do
            Near(label.textColor[index], component, message .. ": component " .. index)
        end
        TextShadow(label)
    end
    local function Click(button)
        Check(button.enabled, "the player can click the enabled control")
        button.scripts.OnClick(button)
    end
    local function SelectDropdown(button, value)
        Check(button:IsEnabled(), "the native dropdown is enabled")
        button:GetScript("OnMouseDown")(button, "LeftButton")
        button:GetScript("OnMouseUp")(button, "LeftButton")
        Check(button:IsMenuOpen(), "the native mouse handler opens the dropdown")
        Same(button.menu.owner, button, "Blizzard menu is anchored to its dropdown owner")
        local root = button:GetMenuDescription()
        Same(root:GetMinimumWidth(), button:GetWidth(), "native menu uses the owner width minimum")
        for _, entry in ipairs(root.entries) do
            if entry:GetData() == value then
                Check(entry:IsRadio(), "choice uses the native radio-description contract")
                Check(entry:Pick(), "native radio response selects the requested value")
                Check(not button:IsMenuOpen(), "native radio response closes its menu")
                Same(button.Text:GetText(), entry.text, "native selection text follows the chosen radio")
                return
            end
        end
        Check(false, "requested value is offered by the native dropdown")
    end
    local function NativeButton(button)
        Same(button.template, "UIPanelButtonTemplate", "setup commands retain the native button art")
        Same(button.Text, button.templateText, "template font string is reused without duplicate text")
        Same(button:GetFontString(), button.templateText, "native button owns its original font string")
        Same(button.background, nil, "native button has no replacement flat background")
        Same(button.edges, nil, "native button has no replacement rectangular border")
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnShow", "OnEnable", "OnDisable" }) do
            local before = button.templateCalls[event] or 0
            Check(button:GetScript(event), "native button state handler remains installed")
            button:GetScript(event)(button)
            Same(button.templateCalls[event], before + 1, "native button state handler still runs: " .. event)
        end
    end
    local function PlainAnswer(button)
        Same(button.kind, "Button", "an answer is an actual clickable hit area")
        Same(button.template, nil, "answers have no native button template or chrome")
        Same(button:GetParent(), Widget.questionContent, "answer hit area belongs to the scrollable question body")
        Same(button:GetFontString(), nil, "answer text stays outside native button font-state handling")
        Same(#(button.fontStrings or {}), 1, "answer owns exactly one font string")
        Same(button.Text:GetParent(), button, "answer text belongs to its hit area")
        Same(button.Text:GetFontObject(), Widget.fontObjects.answer, "answer uses the owned native text font")
        Same(button.Text.justifyH, "LEFT", "answer text stays left aligned in its column")
        Same(#(button.textures or {}), 0, "answer hit area has no textures")
        for _, key in ipairs({ "Accent", "background", "Background", "edges", "NineSlice", "highlight", "templateText" }) do
            Same(button[key], nil, "answer has no decorative button surface: " .. key)
        end
        Check(button:GetScript("OnClick"), "plain answer keeps its submission handler")
        Check(button:GetScript("OnEnter") and button:GetScript("OnLeave"), "plain text keeps owned hover handlers")
    end
    local function TextOnlyHUD()
        HUDTextShadows()
        for _, key in ipairs({ "progress", "metadata", "explanation", "status", "score", "editLabel" }) do
            Same(Widget[key], nil, "HUD never creates an extra label: " .. key)
        end
        local allowed = {
            [Widget.prompt] = true,
            [Widget.scoreText] = true,
            [Widget.packText] = true,
            [Widget.winnerText] = true,
            [Widget.fontProbe] = true,
            [Quiz.StreakToasts.nameText] = true,
            [Quiz.StreakToasts.captionText] = true,
        }
        for _, choice in ipairs(Widget.choices) do
            allowed[choice.Text] = true
            PlainAnswer(choice)
        end
        local count = 0
        for _, frame in ipairs(Test.frames) do
            local ancestor = frame
            while ancestor and ancestor ~= Widget.frame do
                ancestor = ancestor:GetParent()
            end
            if ancestor then
                for _, label in ipairs(frame.fontStrings or {}) do
                    Check(allowed[label], "HUD contains only its specified text roles and hidden native font probe")
                    count = count + 1
                end
            end
        end
        Same(count, 13, "HUD owns ten quiz labels, two toast labels and one hidden font-asset probe")
        Same(Widget.fontProbe:IsShown(), false, "native font validation probe never appears in the HUD")
        Same(Widget.scoreText.kind, "FontString", "personal score uses only a text region")
        Same(Widget.scoreText:GetParent(), Widget.content, "floating score is outside the clipped question body")
        Same(
            Widget.scoreText:GetFontObject(),
            Widget.choices[1].Text:GetFontObject(),
            "personal score uses the answer-size font"
        )
        Same(Widget.scoreText.justifyH, "RIGHT", "personal score aligns at the right edge")
        Same(Widget.scoreText.justifyV, "TOP", "personal score begins at the top of its reserved space")
        Same(Widget.scoreText.wordWrap, false, "short signed score never wraps onto a second line")
        Same(Widget.scoreText:GetMaxLines(), 1, "personal score occupies one line")
        Same(Widget.scoreText:GetScript("OnClick"), nil, "personal score cannot submit an answer")
        Same(Widget.scoreText:GetScript("OnUpdate"), nil, "personal score needs no Lua animation loop")
        Same(Widget.scoreAnimation:GetParent(), Widget.scoreText, "native animation belongs to the reusable score text")
        Same(#Widget.scoreAnimation.animations, 2, "only one rise and one fade are allocated")
        Same(Widget.scoreAnimation:GetLooping(), "NONE", "personal score animation is a one-shot")
        Same(Widget.scoreAnimation:GetScript("OnUpdate"), nil, "native animation uses no extra Lua update callback")
    end
    local function ScoreHidden(message)
        Same(Widget.scoreText:IsShown(), false, message .. ": text stays hidden")
        Same(Widget.scoreAnimation:IsPlaying(), false, message .. ": animation is stopped")
    end
    local function ScoreGeometry()
        local label = Widget.scoreText
        local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
        Near(label:GetRight(), Widget.content:GetRight(), "personal score starts at the content right edge")
        local promptOffset = Widget.prompt.point[5]
        Near(
            label:GetTop(),
            Widget.content:GetTop() + promptOffset,
            "personal score stays beside the question's unscrolled top, below the pack label"
        )
        local scoreWidth = PixelUtil.GetNearestPixelSize(SCORE_WIDTH, label:GetEffectiveScale())
        if scoreWidth < SCORE_WIDTH then
            scoreWidth = scoreWidth + pixel
        end
        local scoreLimit = math.max(1, Widget.content:GetWidth() - SCORE_GAP_PIXELS * pixel - MIN_TEXT_HEIGHT)
        Near(
            label:GetWidth(),
            PixelUtil.GetNearestPixelSize(math.min(scoreWidth, scoreLimit), label:GetEffectiveScale()),
            "score reserves a bounded right-side width before a result exists"
        )
        Near(
            (label:GetLeft() - Widget.prompt:GetRight()) / pixel,
            SCORE_GAP_PIXELS + 1,
            "question wrapping reserves the eight-pixel score gutter plus one pixel for pressed text"
        )
        Near(
            (Widget.questionScroll:GetWidth() - Widget.prompt:GetWidth()) / pixel,
            3,
            "scroll column reserves two shadow pixels and one pressed-text pixel"
        )
        Near(Widget.timer:GetWidth(), Widget.prompt:GetWidth(), "timer fills the narrowed text column")
        Check(
            Widget.questionScroll.ScrollBar.Track:GetRight() < label:GetLeft(),
            "thin HUD scroll art remains inside the gap without crossing the personal-score column"
        )
    end
    local function ScoreShown(points)
        local label, animation = Widget.scoreText, Widget.scoreAnimation
        Same(label:IsShown(), true, "confirmed nonzero result shows the personal score")
        Same(label:GetText(), string.format("%+.1f", points), "personal score shows the signed round delta, not total")
        Color(label, points > 0 and COLORS.correct or COLORS.incorrect, "personal gain/loss uses its result color")
        Same(label:GetAlpha(), 1, "every new personal result starts fully opaque")
        Same(animation:IsPlaying(), true, "confirmed result starts native animation playback")
        Near(animation:GetDuration(), SCORE_ANIMATION_SECONDS, "rise and fade complete together after 2.2 seconds")
        Same(Widget.scoreRise.kind, "Translation", "result movement uses a native Translation")
        Same(Widget.scoreRise:GetSmoothing(), "OUT", "upward result movement eases out")
        Same(Widget.scoreRise:GetRegionParent(), label, "translation targets only personal-score text")
        Same(Widget.scoreFade.kind, "Alpha", "result fade uses a native Alpha animation")
        Same(Widget.scoreFade:GetFromAlpha(), 1, "native fade starts fully opaque")
        Same(Widget.scoreFade:GetToAlpha(), 0, "native fade ends fully transparent")
        Near(Widget.scoreFade:GetStartDelay(), SCORE_FADE_DELAY, "result remains readable before fading")
        Near(
            Widget.scoreFade:GetDuration(),
            SCORE_ANIMATION_SECONDS - SCORE_FADE_DELAY,
            "the fade occupies the final eight tenths of a second"
        )
        Same(Widget.scoreRise:GetOrder(), Widget.scoreFade:GetOrder(), "rise and delayed fade run in parallel")
        Check(animation:GetScript("OnFinished"), "natural completion owns hiding the personal score")
        Check(animation:GetScript("OnStop"), "cancelling native animation also hides its score")
        local x, y = Widget.scoreRise:GetOffset()
        local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
        Same(x, 0, "result rises without crossing the reserved horizontal gutter")
        Check(y >= 0 and y / pixel <= SCORE_RISE_PIXELS + EPSILON, "rise stays within twelve physical pixels")
        Near(y / pixel, math.floor(y / pixel + 0.5), "rise distance is rounded to the physical pixel grid")
        local _, bottom, _, height = label:GetScaledRect()
        local _, screenBottom, _, screenHeight = UIParent:GetScaledRect()
        Check(
            bottom + height + y * label:GetEffectiveScale() <= screenBottom + screenHeight + EPSILON,
            "score rise never leaves the available screen headroom"
        )
        ScoreGeometry()
    end
    local function WrappedLabel(label, expectedText)
        local measurement = label.lastStringHeightMeasurement
        Check(measurement, "wrapped label was measured before its final height was chosen")
        Same(label:GetText(), expectedText, "wrapping preserves all text without inserting an ellipsis")
        Same(label.explicitHeightAtSetText, 0, "the previous line-height cap is cleared before new text is assigned")
        Same(measurement.explicitHeight, 0, "font measurement never uses the previous question's height constraint")
        Same(measurement.text, expectedText, "font measurement uses the complete current question or answer")
        Same(measurement.wordWrap, true, "normal word wrapping is enabled before measurement")
        Same(measurement.nonSpaceWrap, true, "unbroken text may wrap before measurement")
        Same(measurement.maxLines, 0, "font measurement is not limited to a fixed number of lines")
        Same(label:GetMaxLines(), 0, "the rendered text retains its unlimited line count")
        Near(measurement.width, label:GetWidth(), "measurement uses the label's final constrained width")
        Near(label.widthAtSetText, label:GetWidth(), "new text receives the final width before layout")
        local requiredHeight = math.max(MIN_TEXT_HEIGHT, measurement.requiredHeight)
        local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
        Check(label:GetHeight() + EPSILON >= requiredHeight, "final text height never rounds below the measured text")
        Check(label:GetHeight() < requiredHeight + pixel + EPSILON, "rounding up adds at most one physical pixel")
        Near(
            label:GetHeight() / pixel,
            math.floor(label:GetHeight() / pixel + 0.5),
            "text height ends on a pixel boundary"
        )
    end
    local function TimerGradient(remaining, duration)
        local timer = Widget.timer
        timerStartColor, timerEndColor = timerStartColor or timer.startColor, timerEndColor or timer.endColor
        Check(timerStartColor and timerEndColor, "timer owns persistent color endpoints")
        Check(timerStartColor ~= timerEndColor, "gradient endpoints have independent mutable colors")
        Same(timer.startColor, timerStartColor, "gradient keeps its original dark endpoint object")
        Same(timer.endColor, timerEndColor, "gradient keeps its original bright endpoint object")
        Check(timer.Fill.gradient, "countdown uses a real native texture gradient")
        Same(timer.Fill.gradient[1], "HORIZONTAL", "timer gradient runs from left to right")
        Same(timer.Fill.gradient[2], timerStartColor, "native gradient receives the owned dark endpoint")
        Same(timer.Fill.gradient[3], timerEndColor, "native gradient receives the owned bright endpoint")
        Near(timer:GetValue(), remaining, "gradient accompanies the current countdown value")
        Near(timer.Fill.gradientBarValue, remaining, "bar value is set before the gradient is reapplied")
        local fraction = math.max(0, math.min(1, remaining / (duration or 15)))
        local tint = { timer:GetStatusBarColor() }
        for index = 1, 3 do
            local expected = COLORS.timeout[index] + (COLORS.selected[index] - COLORS.timeout[index]) * fraction
            Near(
                timer.Fill.gradientColors[1][index],
                expected * TIMER_GRADIENT_SHADE,
                "gradient starts with the darker hue"
            )
            Near(timer.Fill.gradientColors[2][index], expected, "gradient ends with the full countdown hue")
            Same(tint[index], 1, "white StatusBar tint preserves the gradient's actual endpoint colors")
        end
        Same(timer.Fill.gradientColors[1][4], 1, "gradient dark endpoint stays opaque")
        Same(timer.Fill.gradientColors[2][4], 1, "gradient bright endpoint stays opaque")
        Same(tint[4], 1, "StatusBar tint stays opaque")
    end
    local function TimerGeometry(duration)
        Same(Widget.timer.kind, "StatusBar", "countdown uses the native StatusBar intrinsic")
        Same(Widget.timer.template, nil, "countdown has no status-bar template")
        Same(Widget.timer:GetParent(), Widget.questionContent, "countdown belongs to the scrollable question body")
        local minimum, maximum = Widget.timer:GetMinMaxValues()
        Same(minimum, 0, "countdown minimum is zero")
        Same(maximum, duration or 15, "countdown maximum follows this question's pack rules")
        Same(Widget.timer:GetStatusBarTexture(), Widget.timer.Fill, "bar is filled by its owned native texture")
        Same(Widget.timer.Fill:GetParent(), Widget.timer, "bar fill is owned by the status bar")
        Check(Widget.timer.Fill.color, "timer fill uses a color texture")
        Same(Widget.timer.Fill.atlas, nil, "timer fill needs no atlas art")
        Same(#(Widget.timer.fontStrings or {}), 0, "timer never creates a numeric label")
        Same(Widget.timer.mouse, false, "timer does not take answer or drag input")
        Near(
            Widget.timer:GetHeight() * Widget.timer:GetEffectiveScale() / PixelUtil.GetPixelToUIUnitFactor(),
            TIMER_PIXELS,
            "timer remains exactly two physical pixels tall"
        )
        Near(Widget.timer:GetWidth(), Widget.prompt:GetWidth(), "timer spans the question text column")
        Near(Widget.timer:GetLeft(), Widget.prompt:GetLeft(), "timer aligns with the prompt's left edge")
        Near(
            (Widget.prompt:GetBottom() - Widget.timer:GetTop())
                * Widget.timer:GetEffectiveScale()
                / PixelUtil.GetPixelToUIUnitFactor(),
            TIMER_PROMPT_GAP_PIXELS,
            "countdown sits exactly two physical pixels beneath the prompt"
        )
        local left, bottom, width, height = Widget.timer:GetScaledRect()
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        for _, edge in ipairs({ left, left + width, bottom, bottom + height }) do
            local pixels = edge / factor
            Near(pixels, math.floor(pixels + 0.5), "each timer edge lands on the physical pixel grid")
        end
    end
    local function SingleColumn()
        HUDTextShadows()
        ScoreGeometry()
        WrappedLabel(Widget.prompt, Widget.prompt:GetText())
        local previous = Widget.timer
        for _, choice in ipairs(Widget.choices) do
            if choice:IsShown() then
                Near(choice:GetWidth(), Widget.prompt:GetWidth(), "each answer occupies the full text column")
                Near(choice:GetLeft(), Widget.prompt:GetLeft(), "answers share the question's inset left edge")
                Near(choice.Text:GetLeft(), choice:GetLeft(), "answer text has no decorative button inset")
                Near(choice.Text:GetWidth(), choice:GetWidth(), "text can use its full answer hit area")
                WrappedLabel(choice.Text, choice.Text:GetText())
                Near(
                    choice:GetHeight(),
                    choice.Text:GetHeight(),
                    "answer hit area contains its full wrapped text height"
                )
                Check(choice:GetTop() < previous:GetBottom(), "each answer is below the preceding row")
                if previous == Widget.timer then
                    local pixel = PixelUtil.GetPixelToUIUnitFactor() / choice:GetEffectiveScale()
                    Check(
                        math.abs(previous:GetBottom() - choice:GetTop() - TIMER_ANSWER_GAP) <= pixel / 2 + EPSILON,
                        "timer-to-answer gap stays within half a physical pixel of eight logical units"
                    )
                end
                previous = choice
            end
        end
        Check(
            Widget.content:GetHeight() > Widget.questionScroll:GetHeight(),
            "HUD reserves a stable winner footer before results"
        )
        Check(
            Widget.winnerText:GetTop() < Widget.questionScroll:GetBottom(),
            "winner popup belongs below the answer viewport"
        )
    end
    local function Advertise(name, session, players)
        Check(
            Quiz.Discovery:Receive(
                PREFIX,
                "8|A|" .. session .. "|Test pack|Default|open|" .. players,
                "GUILD",
                name,
                "",
                0,
                0,
                ""
            ),
            "native announcement enters the game browser"
        )
        UI.nextGamesRefresh = nil
        UI:Refresh()
    end
    local function VisibleBounds()
        local left, bottom, width, height = Widget.content:GetScaledRect()
        local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
        Check(left >= screenLeft - EPSILON, "HUD stays inside left screen edge")
        Check(bottom >= screenBottom - EPSILON, "HUD stays inside bottom screen edge")
        Check(left + width <= screenLeft + screenWidth + EPSILON, "HUD stays inside right screen edge")
        Check(bottom + height <= screenBottom + screenHeight + EPSILON, "HUD stays inside top screen edge")
    end
    local function RaisedDivider()
        local scale = UI.frame:GetEffectiveScale()
        local baseline = PixelUtil.GetNearestPixelSize(-77, scale)
        local shift = UI.headerDivider:GetTop() - UI.frame:GetTop() - baseline
        Near(
            shift * scale / PixelUtil.GetPixelToUIUnitFactor(),
            10,
            "header divider moves upward by ten physical pixels from its rounded baseline"
        )
    end
    local function WindowScrollbarEdges()
        for _, scroll in ipairs({ UI.gamesScroll, UI.boardScroll }) do
            local bar = scroll.ScrollBar
            local scale = bar:GetEffectiveScale()
            local inset = (UI.frame:GetRight() - bar.Track:GetRight()) * scale
            Check(
                math.abs(inset - WINDOW_SCROLLBAR_INSET_PIXELS) <= 1 + EPSILON,
                "window scrollbar stays ten physical pixels inside its right border, within pixel rounding"
            )
            Check(
                bar.Track:GetRight() > scroll:GetRight(),
                "window list scrollbar remains in the gutter outside the content viewport"
            )
            Check(
                bar:GetLeft() >= UI.frame:GetLeft() and bar:GetRight() <= UI.frame:GetRight(),
                "the full scrollbar mouse target stays inside the window's horizontal bounds"
            )
            Check(
                bar:GetBottom() >= UI.frame:GetBottom() and bar:GetTop() <= UI.frame:GetTop(),
                "the full scrollbar mouse target stays inside the window's vertical bounds"
            )
            Near(bar:GetWidth(), SCROLLBAR_GRAB_WIDTH, "window scrollbar keeps its full logical drag width")
            Near(bar.Track:GetRight(), bar:GetRight(), "thin art remains aligned to the drag target's right edge")
            Near(bar.Track:GetWidth() * scale, SCROLLBAR_ART_PIXELS, "window track remains two physical pixels wide")
            Near(bar.Thumb:GetWidth() * scale, SCROLLBAR_ART_PIXELS, "window thumb remains two physical pixels wide")
        end
        local scroll = Widget.questionScroll
        Near(
            scroll.ScrollBar:GetRight() - scroll:GetRight(),
            PixelUtil.GetNearestPixelSize(0, scroll.ScrollBar:GetEffectiveScale(), HUD_SCROLLBAR_OFFSET_PIXELS),
            "HUD scrollbar sits four physical pixels into the dedicated score gutter"
        )
    end

    Same(_G.Orbit, nil, "the addon is exercised without Orbit installed")
    Check(
        Quiz:RegisterQuestionPack({
            id = PACK_ID,
            title = "Interface test pack",
            questions = {
                {
                    id = "one",
                    prompt = "Which answer is correct?",
                    choices = { "Yes", "No", "Maybe", "Never" },
                    correctIndex = 1,
                },
                {
                    id = "two",
                    prompt = "Which number is two?",
                    choices = { "One", "Two", "Three", "Four" },
                    correctIndex = 2,
                },
            },
        }),
        "interface fixture pack registers"
    )

    UI:Toggle()
    Same(UI.boardScope, "personal", "Scores defaults to the player's per-pack progress")
    Same(_G.OrbitQuizHostFrame, UI.frame, "setup has the named frame used by Escape")
    Check(UI.frame:IsShown(), "setup opens from the primary entry point")
    Check(UI.frame.Chrome and UI.frame.Chrome.Background, "setup owns an Orbit-style chrome texture")
    Same(UI.frame.Chrome.Background.atlas, "housing-basic-container", "setup uses the real Orbit dialog atlas")
    Same(UI.frame.Chrome.Background.drawLayer, "BACKGROUND", "dialog art stays behind the controls")
    Same(UI.frame.Chrome.Background.drawSublevel, -1, "dialog art uses Orbit's native background sublevel")
    Same(UI.frame.Chrome.Background.allPoints, UI.frame, "native sliced atlas fills the dialog")
    Same(UI.frame.Chrome.Background.color, nil, "housing atlas is never overwritten with a flat color")
    Same(UI.frame.background, nil, "setup has no generic flat root background")
    Same(UI.frame.edges, nil, "setup has no generic root border overlay")
    Same(UI.frame.NineSlice, nil, "dialog does not overlay a legacy portraitless NineSlice panel")
    Same(UI.frame.TitleText.font, "GameFontHighlightLarge", "dialog title matches Orbit's settings font")
    Same(UI.frame.TitleText.justifyH, "CENTER", "dialog title is centered")
    Near(select(1, UI.frame.TitleText:GetCenter()), select(1, UI.frame:GetCenter()), "title centers within the dialog")
    Same(UI.close.template, "UIPanelCloseButton", "dialog has the proper native close control")
    for tab, button in pairs(UI.tabs) do
        Same(button.style, "tab", "tabs use the separate text-tab style")
        Same(button.background, nil, "text tabs have no flat button fill")
        Same(button.edges, nil, "text tabs have no button border")
        Same(button.highlight.atlas, "housing-basic-panel-gradient-header-bg", "tabs use Orbit's selected gradient")
        Same(button.highlight:IsShown(), tab == "play", "only the active tab gradient is visible")
        Near(
            button.highlight:GetWidth(),
            PixelUtil.GetNearestPixelSize(button:GetWidth() * 1.84, button:GetEffectiveScale()),
            "tab highlight uses Orbit's pixel-rounded tapered width"
        )
        Same(button.highlight:GetHeight(), 21, "tab highlight uses Orbit's native height")
        if tab == "play" then
            Same(button.Text.textColor[1], 1, "active tab uses the gold red channel")
            Near(button.Text.textColor[2], 0.82, "active tab uses Orbit gold")
            Same(button.Text.textColor[3], 0, "active tab uses the gold blue channel")
        end
    end
    local dividers = 0
    for divider in pairs(Quiz.Controls.dividers) do
        if divider:GetParent() == UI.frame then
            dividers = dividers + 1
            Same(divider.Left.gradient[1], "HORIZONTAL", "dialog divider fades horizontally")
            Same(divider.Left.gradient[2].a, 0, "left divider fades in from a transparent edge")
            Same(divider.Left.gradient[3].a, 1, "left divider reaches an opaque middle")
            Same(divider.Right.gradient[2].a, 1, "right divider starts at the opaque middle")
            Same(divider.Right.gradient[3].a, 0, "right divider fades out at its edge")
        end
    end
    Check(dividers >= 2, "settings dialog has tapered header and footer dividers")
    RaisedDivider()
    WindowScrollbarEdges()
    Check(Widget.frame:IsShown() and Widget.editing, "setup opens a draggable idle preview")
    Check(Widget.editOutline:IsShown(), "positioning overlay is visible during setup")
    for _, edge in ipairs(Widget.editOutline.edges) do
        Near(edge.color[1], 0.7, "HUD edit selection uses Orbit's purple red component")
        Near(edge.color[2], 0.6, "HUD edit selection uses Orbit's purple green component")
        Same(edge.color[3], 1, "HUD edit selection uses Orbit's purple blue component")
    end
    Same(Widget.close, nil, "live HUD has no close control")
    Same(Widget.answer, nil, "multiple-choice play has no typing field")
    Same(Widget.hostName, nil, "game selection has no host-name typing field")
    Same(Widget.content.background, nil, "live question content has no window backdrop")
    SetupShadowsUnchanged()
    do
        local labels = { Widget.prompt, Widget.scoreText, Widget.packText, Widget.winnerText }
        for _, choice in ipairs(Widget.choices) do
            labels[#labels + 1] = choice.Text
        end
        local frames, fonts, tickers = #Test.frames, Test.fontStringCreations, #Test.tickers
        local shadowCalls = {}
        for _, label in ipairs(labels) do
            Check(
                label.shadowColorCalls > 0 and label.shadowOffsetCalls > 0,
                "each HUD label initializes its explicit shadows"
            )
            shadowCalls[label] = { label.shadowColorCalls, label.shadowOffsetCalls }
        end
        Widget:Refresh()
        Widget:Refresh()
        for _, label in ipairs(labels) do
            Same(
                label.shadowColorCalls,
                shadowCalls[label][1],
                "ordinary refreshes do not reapply constant shadow color"
            )
            Same(label.shadowOffsetCalls, shadowCalls[label][2], "ordinary refreshes do not recalculate shadow offsets")
        end
        Widget:OnDisplayChanged()
        for _, label in ipairs(labels) do
            Same(label.shadowColorCalls, shadowCalls[label][1] + 1, "display changes reapply each existing HUD shadow")
            Same(label.shadowOffsetCalls, shadowCalls[label][2] + 1, "display changes recalculate all physical offsets")
        end
        Same(#Test.frames, frames, "shadow refresh allocates no frame or region holder")
        Same(Test.fontStringCreations, fonts, "shadow refresh allocates no replacement text labels")
        Same(#Test.tickers, tickers, "text shadows need no timer")
    end
    TextOnlyHUD()
    TimerGeometry()
    SingleColumn()
    Same(Widget.timer:GetValue(), 15, "idle edit preview shows a full timer")
    TimerGradient(15)
    Same(Widget.timer:GetScript("OnUpdate"), nil, "idle preview does not run an animation")
    ScoreHidden("idle preview never awards a personal score")
    for index, choice in ipairs(Widget.choices) do
        Same(choice:IsShown(), index <= 4, "idle preview shows only its four example answers")
        Same(choice.enabled, false, "preview answers cannot be clicked")
        Same(choice.controlEnabled, false, "preview controls are not enabled")
        Same(choice.selected, false, "preview has no selected answer")
        Same(choice.tone, nil, "preview does not reveal correctness")
        if choice:IsShown() then
            Color(choice.Text, COLORS.normal, "disabled preview answers are still white")
            choice:GetScript("OnEnter")(choice)
            Same(choice.hovered, false, "preview hover cannot activate an answer")
            Color(choice.Text, COLORS.normal, "preview hover never changes its text color")
        end
    end
    for _, name in ipairs(UISpecialFrames) do
        Check(name ~= "OrbitQuizWidgetFrame", "Escape cannot dismiss the required live HUD")
    end
    UI:SetTab("host")
    SelectDropdown(UI.pack, PACK_ID)
    for _, edit in ipairs({ UI.league }) do
        Same(edit.autoFocus, false, "setup never takes typing focus automatically")
        Same(edit.template, "BackdropTemplate", "edit control includes native backdrop support")
        Same(edit.backdrop.bgFile, 130937, "edit uses Orbit's ChatBackground asset")
        Same(edit.backdrop.edgeFile, 137057, "edit uses Orbit's tooltip border asset")
        Same(edit.backdrop.edgeSize, 16, "edit uses the native inset border size")
        Same(edit.backdrop.insets.left, 3, "edit preserves the Orbit backdrop inset")
        Same(edit.font, "ChatFontNormal", "edit uses Orbit's normal chat font")
        Same(edit.backdropColor[1], 0, "edit has a black inset background")
        Same(edit.backdropColor[4], 0.5, "edit background has Orbit's half opacity")
        Same(edit.backdropBorderColor[1], 0.5, "edit border is muted gray")
        Same(edit.background, nil, "edit has no extra flat-fill texture")
        Same(edit.edges, nil, "edit has no extra rectangular border")
    end
    for _, key in ipairs({
        "bridgeChat",
        "bridgeEnabled",
        "chatFields",
        "customChannel",
        "channelPassword",
        "join",
        "publish",
        "RefreshBridge",
    }) do
        Same(UI[key], nil, "visible chat control or binding is removed: " .. key)
    end
    Check(UI.hostHelp:IsShown(), "pack-owned rule guidance is always visible in Host")
    Check(UI.hostHelp:GetText():find(Quiz.L.W_RULES_OWNED, 1, true), "Host explains that the pack owns the rules")
    Check(UI.hostHelp:GetText():find(Quiz.L.W_RULE_ENDLESS, 1, true), "Host explains this pack's repeating progression")
    Check(UI.hostHelp:GetTop() < UI.durationInfo:GetBottom(), "guidance follows the pack's timing rules")
    Check(UI.hostHelp:GetBottom() > UI.start:GetTop(), "guidance stays clear of the automatic game controls")
    for _, key in ipairs({
        "W_BRIDGE_OFF_BUTTON",
        "W_BRIDGE_ON_BUTTON",
        "W_CHAT_CHANNEL",
        "W_CHAT_PASSWORD",
        "W_PUBLISH",
        "W_PUBLISH_WAIT",
        "W_PUBLISH_SYNCING",
        "W_PUBLISH_PACING_F",
    }) do
        Same(Quiz.L[key], nil, "removed bridge UI string is no longer registered: " .. key)
    end
    for _, button in ipairs({ UI.start, UI.pause, UI.stop, UI.save, UI.refreshGames, UI.leave }) do
        NativeButton(button)
    end
    do
        local button = UI.refreshGames
        local enabled, selected = button:IsEnabled(), button.selected
        local handlers = {}
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnShow", "OnEnable", "OnDisable", "OnClick" }) do
            handlers[event] = button:GetScript(event)
        end
        for _, state in ipairs({
            { selected = true, accent = true },
            { selected = false, accent = false },
            { accent = false },
            { selected = true, accent = true },
        }) do
            for _, active in ipairs({ true, false }) do
                Quiz.Controls:SetButtonState(button, active, state.selected)
                Same(button.Accent:IsShown(), state.accent, "only a selected panel button shows its accent")
                Same(button:IsEnabled(), active, "selection preserves the requested native enabled state")
                Same(button:GetFontString(), button.templateText, "selection retains the native font string")
                for event, handler in pairs(handlers) do
                    Same(button:GetScript(event), handler, "selection retains the native handler: " .. event)
                end
                if state.accent then
                    for _, edge in ipairs(button.Accent.edges) do
                        for index, component in ipairs(COLORS.selected) do
                            Near(edge.color[index], component, "selected panel-button accent remains gold")
                        end
                    end
                end
            end
        end
        Quiz.Controls:SetButtonState(button, enabled, selected)
    end
    Same(Quiz.Picker, nil, "custom picker implementation is no longer loaded")
    Same(Quiz.Controls.PickerButton, nil, "custom picker control factory is removed")
    for _, dropdown in ipairs({ UI.pack, UI.boardSwitch }) do
        Same(dropdown.kind, "DropdownButton", "selectors use Blizzard's actual intrinsic dropdown")
        Same(dropdown.template, "WowStyle1DropdownTemplate", "selectors use Blizzard's dropdown widget")
        Same(dropdown.Background.atlas, "common-dropdown-textholder", "native dropdown background art is retained")
        Same(dropdown.Arrow.atlas, "common-dropdown-a-button", "native dropdown arrow art is retained")
        Same(dropdown.Text, dropdown.templateText, "native dropdown owns its original font string")
        Same(dropdown.Text.font, "GameFontHighlight", "native dropdown font is retained")
        Same(dropdown.edges, nil, "native dropdown has no replacement flat border")
        Same(dropdown.background, nil, "native dropdown has no replacement flat fill")
        Same(dropdown:GetScript("OnClick"), nil, "addon does not replace intrinsic click handling")
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnShow", "OnEnter", "OnLeave", "OnEnable", "OnDisable" }) do
            local before = dropdown.templateCalls[event] or 0
            dropdown:GetScript(event)(dropdown)
            Same(dropdown.templateCalls[event], before + 1, "native dropdown handler still runs: " .. event)
            dropdown:CloseMenu()
        end
    end
    SelectDropdown(UI.pack, PACK_ID)
    Same(UI.draft.packId, PACK_ID, "installed pack is selectable without entering its ID")
    Same(UI.pack:GetMenuDescription().maxScrollExtent, 220, "large question-pack menus request native scrolling")
    Same(UI.pack:GetMenuDescription():GetMaximumWidth(), 540, "long pack labels have a bounded native menu width")
    SelectDropdown(UI.pack, PACK_ID)
    Same(UI.duration, nil, "answer duration has no input field")
    Same(UI.durationDown, nil, "answer duration has no decrement control")
    Same(UI.durationUp, nil, "answer duration has no increment control")
    Check(UI.durationInfo:GetText():find("15", 1, true), "host sees the fixed fifteen-second rule")
    Same(UI:ReadSettings().duration, 15, "host setup preserves only the fixed duration")
    local hostSettings = UI:ReadSettings()
    for _, key in ipairs({ "bridgeChat", "channel", "customChannel", "channelPassword", "answerMode" }) do
        Same(hostSettings[key], nil, "host setup cannot restore a removed chat setting: " .. key)
    end
    Click(UI.start)
    Same(Main.game.state, "open", "host starts from a button without typed setup")
    Same(Main.game.settings.packId, PACK_ID, "pack selection drives the hosted game")
    local round = Main.game.round
    Same(Widget.timer:GetValue(), 15, "a newly opened hosted question starts with a full bar")
    TimerGradient(15)
    Check(Widget.timer:GetScript("OnUpdate"), "open question owns a smooth per-frame countdown")
    ScoreHidden("opening a question cannot award points")
    for index = 1, #round.choices do
        Color(Widget.choices[index].Text, COLORS.normal, "unselected open answers begin white")
    end
    local hoverChoice = Widget.choices[round.correctIndex % #round.choices + 1]
    hoverChoice:GetScript("OnEnter")(hoverChoice)
    Same(hoverChoice.hovered, true, "an enabled answer records its hover")
    Color(hoverChoice.Text, COLORS.hovered, "hover contrasts with normal white text")
    hoverChoice:GetScript("OnLeave")(hoverChoice)
    Same(hoverChoice.hovered, false, "leaving clears the hover flag")
    Color(hoverChoice.Text, COLORS.normal, "leaving restores normal white text")
    Click(Widget.choices[round.correctIndex])
    local firstAnswer = round.answers[Test.hostGUID]
    Check(firstAnswer, "answer button submits the host's selection")
    Same(Main.game.settings.duration, 15, "button-started games use the fixed fifteen-second duration")
    Same(firstAnswer.points, 2.5, "instant correct answer earns two and a half points for a fifteen-second round")
    ScoreHidden("host's accepted answer stays private until its result")
    for index, button in ipairs(Widget.choices) do
        Same(button.enabled, index <= #round.choices, "only actual question choices remain available after an answer")
        Same(button.tone, nil, "answer correctness is not styled before the result")
    end
    local selectedChoice = Widget.choices[round.correctIndex]
    Color(selectedChoice.Text, COLORS.selected, "selected answer is gold before correctness is revealed")
    selectedChoice:GetScript("OnEnter")(selectedChoice)
    Color(selectedChoice.Text, COLORS.selected, "selection takes precedence over hover")
    selectedChoice:GetScript("OnLeave")(selectedChoice)
    Color(selectedChoice.Text, COLORS.selected, "leaving a selected answer keeps it gold")
    Click(Widget.choices[round.correctIndex])
    Same(round.answers[Test.hostGUID], firstAnswer, "reclicking the selected answer does not retime it")
    local animationFrames = #Test.frames
    local animationColors = Test.colorCreations
    for index = 1, 4 do
        Test.now = Test.now + 0.125
        local gradientCalls = Widget.timer.Fill.gradientCalls
        Widget.timer:GetScript("OnUpdate")(Widget.timer, 0.125)
        Near(Widget.timer:GetValue(), 15 - index * 0.125, "timer advances between runtime ticker callbacks")
        Same(Widget.timer.Fill.gradientCalls, gradientCalls + 1, "each animation step reapplies the native gradient")
        TimerGradient(15 - index * 0.125)
    end
    Same(#Test.frames, animationFrames, "timer animation does not allocate frames")
    Same(Test.colorCreations, animationColors, "timer animation never allocates new ColorMixin objects")
    Same(round.answers[Test.hostGUID], firstAnswer, "display animation does not change the timed answer")

    Click(UI.close)
    Check(not Widget.editing and not Widget.frame.movable, "closing setup locks position")
    Check(not Widget.editOutline:IsShown(), "closing setup hides selection chrome")
    Check(Widget.frame:IsShown(), "closing setup does not hide an active quiz")
    Widget:StartDrag()
    Check(not Widget.dragging, "dragging cannot start outside setup")
    hoverChoice:GetScript("OnEnter")(hoverChoice)
    Widget.frame:Hide()
    Same(Widget.timer:GetScript("OnUpdate"), nil, "hiding the HUD removes its countdown handler")
    Same(hoverChoice.hovered, false, "hiding the HUD clears hover state")
    Widget:Refresh()
    Check(Widget.frame:IsShown(), "active session visibility is owned by the session")
    Check(Widget.timer:GetScript("OnUpdate"), "restoring an active HUD restores its countdown")
    Color(hoverChoice.Text, COLORS.normal, "restored HUD does not retain a hover color")

    UI.frame:Show()
    Widget:StartDrag()
    Check(Widget.dragging and Widget.frame.moving, "setup permits moving the position anchor")
    Widget.frame.mockCenterX, Widget.frame.mockCenterY = 192, 108
    UI.frame:Hide()
    Check(not Widget.dragging and not Widget.frame.moving, "closing setup finishes an in-progress drag")
    local savedPosition = Quiz.Store:GetWidgetPosition()
    Near(savedPosition.x, Widget.layout.x, "drag writes independent normalized X position")
    Near(savedPosition.y, Widget.layout.y, "drag writes independent normalized Y position")
    Same(Widget.layout.horizontal, "LEFT", "left screen third aligns the question left")
    Same(Widget.layout.vertical, "BOTTOM", "bottom half grows question content upward")
    Same(Widget.prompt.justifyH, "LEFT", "prompt text follows its screen-aware alignment")
    VisibleBounds()
    Widget:Submit(round.correctIndex % 4 + 1)
    Same(round.answers[Test.hostGUID], firstAnswer, "drag release cannot accidentally select an answer")
    Test.Advance(0.3)
    Click(Widget.choices[round.correctIndex % 4 + 1])
    Same(
        round.answers[Test.hostGUID].points,
        -0.9,
        "a later wrong selection replaces the earlier correct answer with its penalty"
    )
    Color(Widget.choices[round.correctIndex].Text, COLORS.normal, "changing selection restores the previous text")
    Color(hoverChoice.Text, COLORS.selected, "newly selected answer gets the gold color")
    Near(Quiz.Store:GetWidgetPosition().x, savedPosition.x, "answer selection does not alter HUD position")

    for _, resolution in ipairs({ { 800, 600 }, { 1280, 720 }, { 1920, 1080 }, { 3840, 2160 } }) do
        for _, width in ipairs({ 180, 300, 380 }) do
            for _, height in ipairs({ 24, 140, 280, 420 }) do
                for _, x in ipairs({ 0, 0.1, 1 / 3, 0.5, 2 / 3, 0.9, 1 }) do
                    for _, y in ipairs({ 0, 0.1, 0.49, 0.5, 0.9, 1 }) do
                        local layout = Widget:ResolveLayout(x, y, resolution[1], resolution[2], width, height)
                        Check(layout.left >= 0 and layout.bottom >= 0, "normalized placement respects lower bounds")
                        Check(
                            layout.left + width <= resolution[1] + EPSILON,
                            "normalized placement respects right bound"
                        )
                        Check(
                            layout.bottom + height <= resolution[2] + EPSILON,
                            "normalized placement respects top bound"
                        )
                        Same(
                            layout.horizontal,
                            x < 1 / 3 and "LEFT" or x > 2 / 3 and "RIGHT" or "CENTER",
                            "screen thirds are independent from content dimensions"
                        )
                        Same(layout.vertical, y >= 0.5 and "TOP" or "BOTTOM", "vertical flow follows anchor half")
                    end
                end
            end
        end
    end
    UIParent:SetSize(800, 600)
    UIParent:SetScale(0.8)
    Main:OnEvent("DISPLAY_SIZE_CHANGED")
    VisibleBounds()
    Main:OnEvent("UI_SCALE_CHANGED")
    VisibleBounds()
    Same(UI.frame.Chrome.Background.atlas, "housing-basic-container", "scale refresh never replaces dialog atlas art")
    Same(UI.frame.edges, nil, "scale refresh never adds generic dialog borders")
    for _, dropdown in ipairs({ UI.pack, UI.boardSwitch }) do
        Same(dropdown.Background.atlas, "common-dropdown-textholder", "scaling preserves Blizzard dropdown art")
        Same(dropdown.edges, nil, "scaling does not add a replacement dropdown border")
    end
    RaisedDivider()
    WindowScrollbarEdges()
    Near(Quiz.Store:GetWidgetPosition().x, savedPosition.x, "display changes do not rewrite the preferred position")
    UIParent:SetScale(1)
    UIParent:SetSize(1920, 1080)
    Main:OnEvent("DISPLAY_SIZE_CHANGED")
    Test.now = round.deadline - 0.025
    Widget.timer:GetScript("OnUpdate")(Widget.timer, 0.025)
    Near(Widget.timer:GetValue(), 0.025, "last fractional time remains visible before the deadline")
    TimerGradient(0.025)
    Check(Widget.choices[1].enabled, "answers remain editable before the exact deadline")
    local lastAnswer = round.answers[Test.hostGUID]
    selectedChoice:GetScript("OnEnter")(selectedChoice)
    Test.now = round.deadline
    Widget.timer:GetScript("OnUpdate")(Widget.timer, 0.025)
    Same(Main.game.state, "open", "isolated animation does not advance the host model before its ticker")
    Same(Widget.timer:GetValue(), 0, "countdown empties at the exact deadline")
    TimerGradient(0)
    Same(Widget.timer:GetScript("OnUpdate"), nil, "expired bar removes its own per-frame handler")
    ScoreHidden("the local timer reaching zero is not an authoritative result")
    for index, choice in ipairs(Widget.choices) do
        Same(choice.enabled, false, "timer expiry disables answers before the runtime ticker")
        Same(choice.controlEnabled, false, "deadline clears the control-enabled flag")
        Same(choice.hovered, false, "deadline clears any active hover")
        Same(choice.tone, nil, "deadline alone never reveals the answer key")
        if index <= #round.choices then
            Color(
                choice.Text,
                choice.selected and COLORS.selected or COLORS.muted,
                "expired text retains no hover color"
            )
        end
    end
    Widget.choices[round.correctIndex]:GetScript("OnClick")(Widget.choices[round.correctIndex])
    Same(round.answers[Test.hostGUID], lastAnswer, "stale callbacks cannot alter an expired answer")
    Test.Advance(round.deadline - Test.now)
    Same(Main.game.state, "results", "question closes with the HUD still visible")
    Check(not Widget.choices[1].enabled, "answers disable at the deadline")
    Same(Widget.choices[round.correctIndex].tone, "correct", "correct highlight appears only after close")
    Color(Widget.choices[round.correctIndex].Text, COLORS.correct, "received result paints the correct answer green")
    Color(hoverChoice.Text, COLORS.incorrect, "received result paints the selected wrong answer red")
    Same(Widget.timer:GetValue(), 0, "results retain an empty timer")
    TimerGradient(0)
    Same(Widget.timer:GetScript("OnUpdate"), nil, "results do not animate the countdown")
    ScoreShown(-0.9)
    local hostScorePlays = Widget.scoreAnimation.playCalls
    Widget:Refresh()
    Same(Widget.scoreAnimation.playCalls, hostScorePlays, "refreshing a host result cannot replay its penalty")
    TextOnlyHUD()
    Main:Stop()
    Check(not Widget.frame:IsShown(), "ending the session removes the HUD outside setup")
    Same(Widget.timer:GetScript("OnUpdate"), nil, "ending a session leaves no timer update handler")
    ScoreHidden("stopping the host cancels its pending score animation")

    UI.frame:Show()
    UI:SetTab("play")
    Test.guild = true
    Advertise(FIRST_HOST, "alpha-session.1", 1)
    Advertise(SECOND_HOST, "beta-session.1", 2)
    Same(#UI.gameRows, 2, "discovered games become click-to-join rows")
    local allocatedFrames = #Test.frames
    for index = 1, 6 do
        Advertise(FIRST_HOST, "alpha-session.1", index % 2 + 1)
    end
    Same(#Test.frames, allocatedFrames, "discovery updates reuse existing row frames")
    Main.restrictionActive = true
    Main:SyncRestriction()
    UI:Refresh()
    for _, row in ipairs(UI.gameRows) do
        Check(not row.join.enabled, "game joins visibly disable during communication restriction")
    end
    Main.restrictionActive = false
    Main:SyncRestriction()
    UI:Refresh()
    Click(UI.gameRows[1].join)
    local previousClient = Session.client
    Same(previousClient.name, FIRST_HOST, "first row joins its discovered native host")
    Click(UI.gameRows[2].join)
    Check(Session.client ~= previousClient, "joining another row replaces the previous membership")
    Same(Session.client.name, SECOND_HOST, "only the newly chosen host remains active")
    Same(Session.hostSession, nil, "participant has no simultaneous hosted session")
    local client = Session.client
    Session:Receive(SECOND_HOST, { "W", client.request, "beta-session.1", "Default", "0.0" })
    Widget:Refresh()
    Same(Widget.timer:GetValue(), 0, "joining a game does not start an answer countdown")
    TimerGradient(0)
    Same(Widget.timer:GetScript("OnUpdate"), nil, "waiting for a question needs no per-frame timer")
    Session:Receive(SECOND_HOST, {
        "Q",
        "beta-session.1",
        "500",
        "1",
        "1",
        "1",
        "15",
        "Remote question?",
        "4",
        "",
        "",
        "test-pack",
        "Test pack",
        "1",
        "3",
        defaultRulesKey,
        "A",
        "B",
        "C",
        "D",
    })
    Widget:Refresh()
    Same(Widget.timer:GetValue(), 0, "receiving question data alone leaves the timer empty")
    TimerGradient(0)
    Same(Widget.timer:GetScript("OnUpdate"), nil, "preparing question waits for the opening packet")
    ScoreHidden("receiving question data cannot award a personal score")
    for index = 1, 4 do
        Same(Widget.choices[index].enabled, false, "prepared answers cannot be selected before opening")
        Color(Widget.choices[index].Text, COLORS.muted, "prepared answer text is muted")
    end
    Session:Receive(SECOND_HOST, { "O", "beta-session.1", "500", tostring(GetServerTime() + 15) })
    UI.nextGamesRefresh = nil
    UI:Refresh()
    Check(not UI.gameRows[2].join.enabled, "joined game is marked in the browser")
    UI.frame:Hide()
    Widget:Refresh()
    Check(Widget.frame:IsShown(), "participant HUD remains visible without the browser")
    Click(Widget.choices[2])
    Same(Session.view.selected, 2, "participant answers without typing")
    Color(Widget.choices[2].Text, COLORS.selected, "participant selection turns gold without revealing correctness")
    Click(Widget.choices[3])
    Same(Session.view.selected, 3, "participant can adjust an unconfirmed selection")
    Color(Widget.choices[2].Text, COLORS.normal, "changing participant selection clears the previous gold")
    Color(Widget.choices[3].Text, COLORS.selected, "new participant selection uses the same gold")
    Same(client.answerRevision, 2, "each adjusted selection receives its own timed action")
    local pooledButtons = {}
    for index, button in ipairs(Widget.choices) do
        pooledButtons[index] = button
    end
    Same(#pooledButtons, 6, "widget preallocates six bare text answer hit areas")
    local questionFrames = #Test.frames
    for count = 6, 4, -1 do
        local id = tostring(507 - count)
        local fields = {
            "Q",
            "beta-session.1",
            id,
            "1",
            "1",
            "1",
            "15",
            string.rep("Lore question ", 11),
            tostring(count),
            count == 4 and "" or "very_hard",
            count == 4 and "" or "Warcraft III: The Frozen Throne",
            "test-pack",
            "Test pack",
            "1",
            "3",
            defaultRulesKey,
        }
        for index = 1, count do
            fields[#fields + 1] = string.rep("Choice ", 13) .. index
        end
        Widget.choices[1]:GetScript("OnEnter")(Widget.choices[1])
        Session:Receive(SECOND_HOST, fields)
        Session:Receive(SECOND_HOST, { "O", "beta-session.1", id, tostring(GetServerTime() + 15) })
        Widget:Refresh()
        ScoreHidden("the next question cancels the preceding result's animation")
        Same(#Test.frames, questionFrames, "changing question size reuses every HUD frame")
        for index, button in ipairs(Widget.choices) do
            Same(button, pooledButtons[index], "round changes reuse the same plain answer hit areas")
            Same(button:IsShown(), index <= count, "only this question's choices are shown")
            Same(button.enabled, index <= count, "hidden choices cannot be clicked")
            Same(button.tone, nil, "new question clears all previous correctness colors")
            Same(button.selected, false, "new question clears all previous selection colors")
            Same(button.hovered, false, "reused answer rows never carry hover into a new question")
            if index <= count then
                Same(button.Text:GetText(), fields[16 + index], "answer labels display only original pack text")
                Color(button.Text, COLORS.normal, "reused open answer text starts white")
            else
                Same(button.Text:GetText(), "", "unused buttons discard prior question text")
                button:GetScript("OnEnter")(button)
                Same(button.hovered, false, "a hidden answer cannot acquire hover state")
            end
        end
        TextOnlyHUD()
        TimerGeometry()
        SingleColumn()
        Click(Widget.choices[count])
        Same(Session.view.selected, count, "fifth and sixth buttons select their actual indices")
        local revision = client.answerRevision
        if count < 6 then
            Widget.choices[6]:GetScript("OnClick")(Widget.choices[6])
            Same(client.answerRevision, revision, "stale sixth-button callbacks cannot create an absent answer")
            Same(Session.view.selected, count, "stale unused callbacks preserve the selected valid option")
        end
        for _, size in ipairs({ { 800, 600 }, { 480, 360 } }) do
            UIParent:SetSize(size[1], size[2])
            for _, position in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 } }) do
                Widget.position = { x = position[1], y = position[2] }
                Widget:OnDisplayChanged()
                VisibleBounds()
                TimerGeometry()
                SingleColumn()
                Same(Widget.prompt.justifyH, Widget.layout.horizontal, "prompt retains screen-aware text alignment")
                for _, choice in ipairs(Widget.choices) do
                    Same(choice.Text.justifyH, "LEFT", "answers remain left aligned at every screen position")
                end
                Check(
                    Widget.questionScroll:GetHeight() <= size[2] * 0.58 + EPSILON,
                    "long six-choice body has bounded scrolling"
                )
                Check(
                    Widget.choices[count]:GetBottom() >= Widget.questionContent:GetBottom() - EPSILON,
                    "the final answer remains inside the scrollable question content"
                )
            end
        end
        UIParent:SetSize(1920, 1080)
        Widget:OnDisplayChanged()
        Session:Receive(SECOND_HOST, {
            "R",
            "beta-session.1",
            id,
            tostring(count),
            tostring(count),
            "1.9",
            "1.9",
            "1",
            "1",
            "Result only",
            "test-pack",
            "Test pack",
            "1",
            "3",
            "15",
            tostring(count),
            "6",
            "",
            "",
            defaultRulesKey,
            "1",
            "0.0",
            "",
        })
        Widget:Refresh()
        Same(Widget.choices[count].tone, "correct", "fifth and sixth correct answers reveal after results")
        Same(Widget.choices[count].enabled, false, "revealed answers are no longer editable")
        Color(Widget.choices[count].Text, COLORS.correct, "selected correct text is green, overriding selection gold")
        Widget.choices[count]:GetScript("OnEnter")(Widget.choices[count])
        Color(Widget.choices[count].Text, COLORS.correct, "hover cannot repaint a received result")
        Same(Widget.choices[count].hovered, false, "disabled result text never acquires hover state")
        Same(Widget.timer:GetValue(), 0, "received remote results empty the timer")
        TimerGradient(0)
        Same(Widget.timer:GetScript("OnUpdate"), nil, "received remote results stop the timer callback")
        ScoreShown(1.9)
        local plays = Widget.scoreAnimation.playCalls
        Widget:Refresh()
        Same(Widget.scoreAnimation.playCalls, plays, "refreshing remote results does not repeat the gain")
    end
    local liveView = Session.view
    local surfaceView = {
        id = "surface-fixture",
        state = "open",
        hostName = SECOND_HOST,
        session = "surface-session.1",
        cycle = 1,
        number = 8,
        total = 99,
        prompt = "Only the question belongs above the timer?",
        choices = { "First", "Second", "Third", "Fourth" },
        deadline = GetTime() + 15,
        duration = 15,
        rules = defaultRules,
        rulesKey = defaultRulesKey,
        correctIndex = 2,
        selected = 1,
        score = 1234.5,
        points = -0.7,
        explanation = "This result explanation stays off the text-only HUD.",
        notice = "This notice belongs in setup, not the HUD.",
        difficulty = "very_hard",
        era = "Warcraft III: The Frozen Throne",
    }
    Session.view = surfaceView
    Widget:Refresh()
    ScoreHidden("available points and answer key do not reveal an open question's result")
    for index = 1, #surfaceView.choices do
        Same(Widget.choices[index].tone, nil, "even an available answer key stays hidden before results")
        Color(
            Widget.choices[index].Text,
            index == surfaceView.selected and COLORS.selected or COLORS.normal,
            "open text never leaks correctness through its color"
        )
    end
    Widget.choices[3]:GetScript("OnEnter")(Widget.choices[3])
    Color(Widget.choices[3].Text, COLORS.hovered, "state fixture begins with an active hover")
    local gradientColors = Test.colorCreations
    for _, remaining in ipairs({ 7.5, 5, 1, 0.025, 0 }) do
        Test.now = surfaceView.deadline - remaining
        Widget.timer:GetScript("OnUpdate")(Widget.timer, 0.025)
        TimerGradient(remaining)
    end
    Same(Test.colorCreations, gradientColors, "gold-to-red transitions reuse the same two colors through timeout")
    ScoreHidden("expiry does not animate even when a stale view contains score data")
    for _, state in ipairs({ "joining", "waiting", "posting", "paused", "stopped", "disconnected", "idle" }) do
        surfaceView.state = state
        Widget:Refresh()
        Same(Widget.timer:GetValue(), 0, "non-open state has no countdown: " .. state)
        TimerGradient(0)
        Same(Widget.timer:GetScript("OnUpdate"), nil, "non-open state has no animation: " .. state)
        ScoreHidden("non-result state cannot animate stale points: " .. state)
        for index = 1, #surfaceView.choices do
            local choice = Widget.choices[index]
            Same(choice.enabled, false, "non-open state disables every answer: " .. state)
            Same(choice.selected, false, "non-answering state clears stale selection: " .. state)
            Same(choice.hovered, false, "state change clears hover: " .. state)
            Same(choice.tone, nil, "non-result state does not reveal an available answer key: " .. state)
            Color(choice.Text, COLORS.muted, "non-answering state uses muted text: " .. state)
        end
        TextOnlyHUD()
    end
    surfaceView.state, surfaceView.correctIndex = "results", nil
    Widget:Refresh()
    ScoreHidden("results need the authoritative answer key before animating")
    for index = 1, #surfaceView.choices do
        Same(Widget.choices[index].tone, nil, "results without an answer key do not invent correctness")
        Color(
            Widget.choices[index].Text,
            index == surfaceView.selected and COLORS.selected or COLORS.muted,
            "missing result keeps selection separate from correctness"
        )
    end
    surfaceView.correctIndex = 2
    Widget:Refresh()
    Color(Widget.choices[1].Text, COLORS.incorrect, "same-state arrival of the answer key marks the wrong selection")
    Color(Widget.choices[2].Text, COLORS.correct, "same-state arrival of the answer key marks the correct option")
    Color(Widget.choices[3].Text, COLORS.muted, "unselected wrong results remain muted")
    ScoreShown(-0.7)
    TextOnlyHUD()
    do
        local animation, scoreText, rise, fade =
            Widget.scoreAnimation, Widget.scoreText, Widget.scoreRise, Widget.scoreFade
        local frames, fonts = #Test.frames, Test.fontStringCreations
        local groups, animations, tickers = #Test.animationGroups, Test.animationCreations, #Test.tickers
        local revision, total = client.answerRevision, surfaceView.score
        local original = {}
        for key, value in pairs(surfaceView) do
            original[key] = value
        end
        local function Result(id, points)
            surfaceView.id, surfaceView.state, surfaceView.points = id, "results", points
            surfaceView.correctIndex = 2
            surfaceView.selected = points and (points > 0 and 2 or 1) or nil
            Widget:Refresh()
        end
        local plays, finishes = animation.playCalls, animation.finishCalls
        for _ = 1, 4 do
            Widget:Refresh()
        end
        Same(animation.playCalls, plays, "repeated result refreshes do not restart or extend the native animation")
        Test.AdvanceAnimations(SCORE_FADE_DELAY)
        Check(scoreText:IsShown() and animation:IsPlaying(), "result remains visible through the pre-fade delay")
        Test.AdvanceAnimations(SCORE_ANIMATION_SECONDS - SCORE_FADE_DELAY - 0.01)
        Check(scoreText:IsShown() and animation:IsPlaying(), "score stays active until the native group completes")
        Test.AdvanceAnimations(0.02)
        ScoreHidden("native completion hides the personal score without a runtime tick")
        Same(animation.finishCalls, finishes + 1, "native completion is delivered once")
        Same(surfaceView.points, -0.7, "finishing the score animation does not alter the authoritative delta")
        Widget:Refresh()
        ScoreHidden("completed personal result stays hidden on later refresh")
        Same(animation.playCalls, plays, "a completed result cannot replay")
        local recovered = {}
        for key, value in pairs(surfaceView) do
            recovered[key] = value
        end
        Session.view = recovered
        Widget:Refresh()
        ScoreHidden("a reconnect snapshot with the same compound result identity cannot replay")
        Same(animation.playCalls, plays, "replacing the view table does not create a new result")
        Session.view = surfaceView
        scoreText:SetAlpha(0.1)
        Result("score-positive", 2.5)
        ScoreShown(2.5)
        Same(animation.playCalls, plays + 1, "the next confirmed question receives its own animation")
        animation:Stop()
        ScoreHidden("native OnStop independently hides the score text")
        Widget:Refresh()
        ScoreHidden("a cancelled result does not replay on refresh")
        plays = animation.playCalls
        Result("score-zero", 0)
        ScoreHidden("a zero-point result has no plus-or-minus animation")
        Result("score-unanswered", nil)
        ScoreHidden("an unanswered question has no personal score animation")
        Same(animation.playCalls, plays, "zero and unanswered results never invoke native Play")
        for _, cancel in ipairs({
            {
                "pause",
                function()
                    surfaceView.state = "paused"
                    Widget:Refresh()
                end,
            },
            {
                "display change",
                function()
                    Widget:OnDisplayChanged()
                end,
            },
            {
                "frame hide",
                function()
                    Widget.frame:Hide()
                end,
            },
        }) do
            Result("score-cancel-" .. cancel[1], -0.5)
            ScoreShown(-0.5)
            plays = animation.playCalls
            cancel[2]()
            ScoreHidden(cancel[1] .. " cancels an active score animation")
            surfaceView.state = "results"
            Widget:Refresh()
            ScoreHidden(cancel[1] .. " cannot cause the same result to replay")
            Same(animation.playCalls, plays, "cancellation retains the last compound result identity")
        end
        Result("score-identity", 1)
        ScoreShown(1)
        plays = animation.playCalls
        surfaceView.hostName = string.lower(surfaceView.hostName)
        Widget:Refresh()
        Same(animation.playCalls, plays, "native host-name case changes do not replay a result")
        surfaceView.session = "surface-session.2"
        Widget:Refresh()
        Same(animation.playCalls, plays + 1, "same question ID in a new hosted game receives its own animation")
        ScoreShown(1)
        surfaceView.hostName = FIRST_HOST
        Widget:Refresh()
        Same(animation.playCalls, plays + 2, "a different host may reuse a session and question ID")
        ScoreShown(1)
        Widget:SetEditing(true)
        Widget:StartDrag()
        ScoreHidden("starting an edit drag cancels the visible personal score")
        Widget:Refresh()
        ScoreHidden("refreshing while dragging does not animate a score")
        Widget:StopDrag()
        Widget:SetEditing(false)
        ScoreHidden("ending an edit drag does not replay the same result")
        Same(animation.playCalls, plays + 2, "dragging changes no result identity")
        for key in pairs(surfaceView) do
            surfaceView[key] = nil
        end
        for key, value in pairs(original) do
            surfaceView[key] = value
        end
        Widget:Refresh()
        Same(surfaceView.score, total, "score feedback never changes the displayed cumulative score")
        Same(client.answerRevision, revision, "native score feedback never generates an answer input")
        Same(#Test.frames, frames, "result feedback reuses every HUD frame")
        Same(Test.fontStringCreations, fonts, "result feedback reuses its single FontString")
        Same(#Test.animationGroups, groups, "all result identities reuse one native animation group")
        Same(Test.animationCreations, animations, "all result identities reuse the native rise and fade")
        Same(#Test.tickers, tickers, "score feedback creates no additional timer or ticker")
        Same(Widget.scoreText, scoreText, "personal score label identity remains stable")
        Same(Widget.scoreAnimation, animation, "score group identity remains stable")
        Same(Widget.scoreRise, rise, "score translation identity remains stable")
        Same(Widget.scoreFade, fade, "score fade identity remains stable")
    end
    local setupError, answerError, mainNotice = UI.actionError, Widget.actionError, Main.notice
    UI.frame:Show()
    UI.actionError, Widget.actionError, Main.notice = nil, nil, nil
    UI:Refresh()
    Same(UI.notice:GetText(), surfaceView.notice, "session diagnostics remain accessible in setup")
    Widget.actionError = "Answer-action diagnostic"
    UI:Refresh()
    Same(UI.notice:GetText(), Widget.actionError, "answer-action failure is shown in setup, not on the HUD")
    UI.actionError = "Setup-action diagnostic"
    UI:Refresh()
    Same(UI.notice:GetText(), UI.actionError, "the setup's own action error keeps precedence")
    TextOnlyHUD()
    UI.actionError, Widget.actionError, Main.notice = setupError, answerError, mainNotice
    UI.frame:Hide()
    do
        local id, prompt, choices, position = surfaceView.id, surfaceView.prompt, surfaceView.choices, Widget.position
        local sequence, clamped = 0, false
        for _, display in ipairs({ { 1920, 768, 1 }, { 1920, 768, 0.71 }, { 2560, 1440, 0.71 } }) do
            Test.physicalWidth, Test.physicalHeight = display[1], display[2]
            UIParent:SetScale(display[3])
            local factor = PixelUtil.GetPixelToUIUnitFactor()
            UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
            for _, anchor in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 } }) do
                sequence = sequence + 1
                surfaceView.id = "score-bounds-" .. sequence
                Widget.position = { x = anchor[1], y = anchor[2] }
                Widget:OnDisplayChanged()
                ScoreShown(surfaceView.points)
                local _, rise = Widget.scoreRise:GetOffset()
                local pixels = rise * Widget.scoreText:GetEffectiveScale() / factor
                clamped = clamped or pixels < SCORE_RISE_PIXELS - EPSILON
                Test.AdvanceAnimations(SCORE_ANIMATION_SECONDS)
                ScoreHidden("screen-aware score still completes without a Lua timer")
            end
        end
        Check(clamped, "top-edge cases actually exercise a rise shorter than twelve physical pixels")
        Test.physicalWidth, Test.physicalHeight = 800, 600
        UIParent:SetScale(1.5)
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        UIParent:SetSize(800 * factor / 1.5, 600 * factor / 1.5)
        surfaceView.id, surfaceView.prompt, surfaceView.choices = "score-scroll", string.rep("Lore question ", 11), {}
        for index = 1, 6 do
            surfaceView.choices[index] = string.rep("Long answer choice ", 5) .. index
        end
        Widget:OnDisplayChanged()
        ScoreShown(surfaceView.points)
        local scoreTop, scroll = Widget.scoreText:GetTop(), Widget.questionScroll
        local promptTop, range = Widget.prompt:GetTop(), scroll:GetVerticalScrollRange()
        Check(range > 0, "long-result fixture genuinely overflows its question viewport")
        scroll:SetVerticalScroll(range)
        Widget:Refresh()
        Near(Widget.scoreText:GetTop(), scoreTop, "scrolling the question never moves the outside score region")
        Check(Widget.prompt:GetTop() > promptTop, "the clipped question body actually scrolled past its old position")
        local overlapping = false
        local regions = { Widget.prompt, Widget.timer }
        for _, choice in ipairs(Widget.choices) do
            regions[#regions + 1] = choice
        end
        for _, region in ipairs(regions) do
            overlapping = overlapping
                or region:GetTop() > Widget.scoreText:GetBottom() and region:GetBottom() < Widget.scoreText:GetTop()
            Check(
                region:GetRight() < Widget.scoreText:GetLeft(),
                "scrolled text and timer never enter the score column"
            )
        end
        Check(overlapping, "scroll regression places question content at the score's vertical band")
        ScoreShown(surfaceView.points)
        Same(
            Widget.scoreText:GetParent(),
            Widget.content,
            "score is never reparented beneath the clipping scroll frame"
        )
        scroll:SetVerticalScroll(0)
        surfaceView.id, surfaceView.prompt, surfaceView.choices, Widget.position = id, prompt, choices, position
        Test.physicalWidth, Test.physicalHeight = 1920, 768
        UIParent:SetScale(1)
        UIParent:SetSize(1920, 1080)
        Widget:OnDisplayChanged()
    end
    local originalPrompt, originalChoices, originalId = surfaceView.prompt, surfaceView.choices, surfaceView.id
    local wrapFrames, wrapColors = #Test.frames, Test.colorCreations
    Widget.prompt.measureLineHeight = WRAP_LINE_HEIGHT
    for _, choice in ipairs(Widget.choices) do
        choice.Text.measureLineHeight = WRAP_LINE_HEIGHT
    end
    local shortChoices = { "One", "Two", "Three", "Four", "Five", "Six" }
    local wrappedCases = {
        { prompt = DRAKA_QUESTION, choice = string.rep("A long answer candidate ", 4) },
        { prompt = string.rep("界", 53) .. "?", choice = string.rep("界", 33) },
        { prompt = string.rep("W", 159) .. "?", choice = string.rep("W", 99) },
    }
    local wrapSequence = 0
    local function RenderWrapped(prompt, choices)
        wrapSequence = wrapSequence + 1
        surfaceView.id, surfaceView.prompt, surfaceView.choices = "wrap-" .. wrapSequence, prompt, choices
        local measurements = Widget.prompt.stringHeightMeasurements
        Widget:Refresh()
        Check(Widget.prompt.stringHeightMeasurements > measurements, "each replacement question is measured afresh")
        Same(Widget.prompt:GetText(), prompt, "question replacement keeps every original byte")
        for index, choice in ipairs(choices) do
            Same(
                Widget.choices[index].Text:GetText(),
                choice,
                "wrapped answer keeps its complete text without an added choice prefix"
            )
        end
        SingleColumn()
        TimerGeometry()
        VisibleBounds()
        Check(
            Widget.choices[#choices]:GetBottom() >= Widget.questionContent:GetBottom() - EPSILON,
            "wrapping retains the final answer within the scrollable content"
        )
        Check(
            Widget.questionScroll:GetHeight() <= UIParent:GetHeight() * 0.58 + EPSILON,
            "long wrapped text expands content instead of the screen-bounded viewport"
        )
    end
    Test.physicalWidth, Test.physicalHeight = 2560, 1440
    UIParent:SetScale(0.71)
    for _, size in ipairs({ { 800, 600 }, { 480, 360 }, { 260, 360 } }) do
        UIParent:SetSize(size[1], size[2])
        Widget:OnDisplayChanged()
        for _, wrapped in ipairs(wrappedCases) do
            Check(#wrapped.prompt <= 160, "wrapping fixture respects the actual prompt byte limit")
            RenderWrapped("Who?", shortChoices)
            local shortPromptHeight = Widget.prompt:GetHeight()
            local shortAnswerHeight = Widget.choices[1]:GetHeight()
            local longChoices = {}
            for index = 1, 6 do
                longChoices[index] = wrapped.choice .. index
                Check(#longChoices[index] <= 100, "wrapping fixture respects the actual choice byte limit")
            end
            RenderWrapped(wrapped.prompt, longChoices)
            Check(
                Widget.prompt:GetHeight() > shortPromptHeight,
                "short-to-long question grows into multiple full lines"
            )
            Check(Widget.choices[1]:GetHeight() > shortAnswerHeight, "short-to-long answer grows its full hit area")
            RenderWrapped("Who?", shortChoices)
            Near(Widget.prompt:GetHeight(), shortPromptHeight, "long-to-short question discards the old tall height")
            Near(
                Widget.choices[1]:GetHeight(),
                shortAnswerHeight,
                "long-to-short answer discards its old tall hit area"
            )
        end
    end
    Same(#Test.frames, wrapFrames, "wrapping changes reuse every existing HUD frame")
    Same(Test.colorCreations, wrapColors, "wrapping refreshes reuse the timer's original color objects")
    Widget.prompt.measureLineHeight = nil
    for _, choice in ipairs(Widget.choices) do
        choice.Text.measureLineHeight = nil
    end
    surfaceView.prompt, surfaceView.choices, surfaceView.id = originalPrompt, originalChoices, originalId
    Test.physicalWidth, Test.physicalHeight = 1920, 768
    UIParent:SetScale(1)
    UIParent:SetSize(1920, 1080)
    Widget:OnDisplayChanged()
    for _, physicalHeight in ipairs({ 768, 1080, 1440, 2160 }) do
        Test.physicalHeight = physicalHeight
        Test.physicalWidth = physicalHeight == 1440 and 2560 or physicalHeight == 2160 and 3840 or 1920
        for _, scale in ipairs({ 0.65, 0.71, 0.8, 1, 1.25 }) do
            UIParent:SetScale(scale)
            local factor = PixelUtil.GetPixelToUIUnitFactor()
            for _, size in ipairs({
                { 800, 600 },
                { 480, 360 },
                { Test.physicalWidth * factor / scale, physicalHeight * factor / scale },
            }) do
                UIParent:SetSize(size[1], size[2])
                for _, position in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 }, { 0.5, 0.5 } }) do
                    Widget.position = { x = position[1], y = position[2] }
                    Widget:OnDisplayChanged()
                    TimerGeometry()
                    SingleColumn()
                    VisibleBounds()
                    Check(
                        Widget.questionScroll:GetHeight() <= size[2] * 0.58 + EPSILON,
                        "pixel-rounded viewport never exceeds its screen fraction"
                    )
                end
            end
        end
    end
    Test.physicalWidth, Test.physicalHeight = 1920, 768
    UIParent:SetScale(1)
    UIParent:SetSize(1920, 1080)
    Widget:OnDisplayChanged()
    surfaceView.state, surfaceView.prompt, surfaceView.choices = "waiting", nil, nil
    Widget:Refresh()
    Same(Widget.prompt:GetText(), "", "a waiting HUD adds no fallback status text as a question")
    Same(Widget.timer:GetValue(), 0, "no-question view keeps an empty timer")
    Same(Widget.timer:GetScript("OnUpdate"), nil, "no-question view has no timer animation")
    for _, choice in ipairs(Widget.choices) do
        Same(choice:IsShown(), false, "no-question view hides all answer hit areas")
        Same(choice.Text:GetText(), "", "no-question view clears all prior answers")
        Same(choice.selected, false, "no-question view clears prior selection")
        Same(choice.hovered, false, "no-question view clears prior hover")
        Same(choice.tone, nil, "no-question view clears prior result color")
    end
    TextOnlyHUD()
    Session.view = liveView
    Widget:Refresh()
    UI.frame:Show()
    Click(UI.leave)
    Same(Session.client, nil, "explicit Leave exits the sole participant session")
    Check(Widget.frame:IsShown(), "setup still offers a position preview after leaving")
    Same(Widget.timer:GetValue(), 15, "leaving returns setup to the full preview bar")
    TimerGradient(15)
    Same(Widget.timer:GetScript("OnUpdate"), nil, "returned preview has no animation")
    ScoreHidden("leaving a participant game cancels its personal-score feedback")
    for index = 1, 4 do
        Color(Widget.choices[index].Text, COLORS.normal, "returned preview clears all result and selection colors")
    end
    TextOnlyHUD()
    UI.frame:Hide()
    Check(not Widget.frame:IsShown(), "closing setup hides only an idle preview")

    UI.frame:Show()
    UI:SetTab("scores")
    SelectDropdown(UI.boardSwitch, "personal")
    Same(UI.boardScope, "personal", "score view exposes personal per-pack progress")
    Check(UI.board:GetText():find("Test pack", 1, true), "personal rows display the actual received pack title")
    Same(UI.boardHint:GetText(), Quiz.L.W_PERSONAL_HELP, "personal totals are explicitly not verified rankings")
    SelectDropdown(UI.boardSwitch, "game")
    Same(UI.boardScope, "game", "host-controlled session scores remain a separate view")
    local participantRows = UI:GetBoardRows({ role = "participant", score = -1.5 })
    Same(#participantRows, 1, "participants are not shown an invented full host leaderboard")
    Same(
        participantRows[1],
        Quiz.L.W_SESSION_TOTAL_F:format(-1.5),
        "participant session row shows the host's signed total"
    )
    SelectDropdown(UI.boardSwitch, "league")
    Same(UI.boardScope, "league", "score view preserves archived current-scale league totals")
    Same(UI.boardHint:GetText(), Quiz.L.W_LEAGUE_ARCHIVE_HELP, "old league rows are explained as read-only archives")
    SelectDropdown(UI.boardSwitch, "legacy")
    Same(UI.boardScope, "legacy", "old-scale scores have an explicitly separate view")
    Check(UI.boardHint:GetText():find("separate", 1, true), "legacy view explains that its scale is separate")

    local scroll, content = Quiz.Controls:Scroll(UI.pages.scores, 160, 100)
    scroll:SetPoint("TOPLEFT", UI.pages.scores, "TOPLEFT", 0, 0)
    local bar = scroll.QuizScrollBar
    Same(scroll.ScrollBar, bar, "scroll controls expose the single attached standalone scrollbar")
    Same(Quiz.ScrollBar:Attach(scroll), bar, "attaching twice never creates a second scrollbar")
    Check(not bar:IsShown(), "scrollbar is hidden when the content fits")
    content:SetHeight(400)
    bar:Refresh()
    Check(bar:IsShown(), "overflow makes the thin scrollbar available")
    Near(bar.Track:GetWidth() * bar:GetEffectiveScale(), 2, "track matches Orbit's two-physical-pixel width")
    Near(bar.Thumb:GetWidth() * bar:GetEffectiveScale(), 2, "thumb matches the track width")
    Check(bar.Thumb:GetHeight() < bar:GetHeight(), "thumb reflects a partial viewport")
    scroll:GetScript("OnMouseWheel")(scroll, -1)
    Check(bar.Animator:IsShown() and bar.Animator:GetScript("OnUpdate"), "scrolling starts an owned animation")
    for _ = 1, 4 do
        local update = bar.Animator:GetScript("OnUpdate")
        if update then
            update(bar.Animator, 0.1)
        end
    end
    Same(scroll:GetVerticalScroll(), 60, "wheel scroll reaches its intended position")
    Check(not bar.Animator:IsShown(), "settled scrolling does not leave an idle animation running")
    Same(bar.Animator:GetScript("OnUpdate"), nil, "settled scrollbar removes its frame-update handler")
    bar:ScrollTo(10000, true)
    Same(scroll:GetVerticalScroll(), 300, "scroll destination clamps to the content end")
    Near(bar.Thumb:GetBottom(), bar:GetBottom(), "final-position thumb reaches the track bottom")
    Test.cursorX = bar:GetRight() * bar:GetEffectiveScale()
    Test.cursorY = bar:GetTop() * bar:GetEffectiveScale()
    bar:GetScript("OnMouseDown")(bar, "LeftButton")
    Same(scroll:GetVerticalScroll(), 0, "clicking above the thumb returns to the start")
    bar:GetScript("OnDragStart")(bar)
    Check(bar:GetScript("OnUpdate"), "dragging installs a temporary pointer tracker")
    Test.cursorY = bar:GetBottom() * bar:GetEffectiveScale()
    bar:GetScript("OnUpdate")(bar)
    Same(scroll:GetVerticalScroll(), 300, "dragging the thumb can reach the last row")
    bar:GetScript("OnMouseUp")(bar)
    Same(bar:GetScript("OnUpdate"), nil, "releasing the thumb stops pointer polling")
    Same(bar.dragY, nil, "release clears drag state")
    bar:ScrollTo(-100, true)
    Same(scroll:GetVerticalScroll(), 0, "negative scroll destination clamps to the start")
    bar:ScrollTo(100)
    scroll:Hide()
    Check(not bar:IsShown(), "hiding the scroll owner hides its sibling bar")
    Same(bar.Animator:GetScript("OnUpdate"), nil, "hidden scroll owner cancels animation")
    scroll:Show()
    Check(bar:IsShown(), "showing an overflowing scroll owner restores its bar")
    scroll:SetFrameLevel(scroll:GetFrameLevel() + 20)
    bar:Refresh()
    Same(bar:GetFrameLevel(), scroll:GetFrameLevel() + 1, "raising the owner keeps its scrollbar above the content")
    bar:ScrollTo(300, true)
    content:SetHeight(100)
    Same(scroll:GetVerticalScroll(), 0, "shrinking content resets an invalid old scroll position")
    Check(not bar:IsShown(), "scrollbar disappears again when content fits")
    scroll:Hide()

    local picked, picks = "choice-500", 0
    local function SelectMany(value)
        picked, picks = value, picks + 1
    end
    local function GenerateMany(_, root)
        root:SetScrollMode(220)
        root:SetMaximumWidth(540)
        for index = 1, 1000 do
            root:CreateRadio("Installed question pack " .. index, function(value)
                return picked == value
            end, SelectMany, "choice-" .. index)
        end
    end
    local many = Quiz.Controls:Dropdown(UIParent, "Many choices", 160, GenerateMany)
    Same(many:GetText(), "Installed question pack 500", "native selection text finds a value in a large menu")
    Same(#many:GetMenuDescription().entries, 1000, "all registered choices reach Blizzard's menu generator")
    Same(many:GetMenuDescription().maxScrollExtent, 220, "large menus opt into bounded native scrolling")
    SelectDropdown(many, "choice-1000")
    Same(picked, "choice-1000", "native menu selects the last registered choice")
    Same(picks, 1, "native radio callback runs exactly once")
    many:OpenMenu()
    Check(many:IsMenuOpen(), "native dropdown reopens without creating an addon popup")
    many:GetScript("OnMouseDown")(many)
    Check(not many:IsMenuOpen(), "native mouse handling toggles an open dropdown closed")
    Same(picks, 1, "dismissing a menu never selects a value")
    many:OpenMenu()
    many:Disable()
    Check(not many:IsMenuOpen(), "disabling the dropdown closes its native menu")
    Same(many.Arrow.atlas, "common-dropdown-a-button-disabled", "native disabled arrow art remains active")
    many:OpenMenu()
    Check(not many:IsMenuOpen(), "disabled native dropdown rejects programmatic opens")
    many:Enable()
    many:OpenMenu()
    many:Hide()
    Check(not many:IsMenuOpen(), "hiding the owner closes its native menu")
    many:Show()
    for _, scale in ipairs({ 0.7, 1, 1.5 }) do
        many:SetScale(scale)
        for _, anchor in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
            many:ClearAllPoints()
            many:SetPoint(anchor, UIParent, anchor, 0, 0)
            many:OpenMenu()
            Same(many.menu.owner, many, "native menu retains its scaled screen-edge owner")
            Same(many.Background.atlas, "common-dropdown-textholder", "screen-edge placement preserves native art")
            Same(many:GetMenuDescription().maxScrollExtent, 220, "screen-edge menus keep their bounded scroll contract")
            many:CloseMenu()
        end
    end
    many:Hide()
    UI.boardSwitch:OpenMenu()
    Check(UI.boardSwitch:IsMenuOpen(), "score dropdown opens before a page change")
    UI:SetTab("host")
    Check(not UI.boardSwitch:IsMenuOpen(), "switching pages closes the previous native menu")
    UI.pack:OpenMenu()
    Check(UI.pack:IsMenuOpen(), "pack dropdown opens before moving the settings dialog")
    UI.frame:GetScript("OnDragStart")(UI.frame)
    Check(not UI.pack:IsMenuOpen(), "dragging the settings dialog closes its native menu")
    UI.frame:GetScript("OnDragStop")(UI.frame)
    UI.pack:OpenMenu()
    Main:OnEvent("UI_SCALE_CHANGED")
    Check(not UI.pack:IsMenuOpen(), "scale changes close anchored native menus before relayout")
    RaisedDivider()
    UI:SetTab("scores")
    UI.boardSwitch:OpenMenu()
    Click(UI.close)
    Check(not UI.boardSwitch:IsMenuOpen(), "closing setup also closes its native dropdown")
    Same(picks, 1, "native owner lifecycle never changes a selection")
    do
        Test.now = Test.now + 0.3
        local configurations = {
            {
                answerSeconds = 5,
                revealSeconds = 1,
                allowAnswerChanges = false,
                shuffleQuestions = false,
                shuffleChoices = false,
                repeatQuestions = false,
                questionLimit = 2,
                correctPoints = 2,
                speedBonusPerSecond = 0.2,
                wrongPenaltyStart = 2,
                wrongPenaltyEnd = 0.2,
                streakBonusPerCorrect = 0.1,
                streakBonusMax = 0.3,
            },
            { answerSeconds = 37, revealSeconds = 7, allowAnswerChanges = false, repeatQuestions = false },
            {
                version = 2,
                answerSeconds = 120,
                revealSeconds = 30,
                allowAnswerChanges = false,
                correctPoints = 1000,
                speedBonusPerSecond = 10,
                wrongPenaltyStart = 1000,
                wrongPenaltyEnd = 1000,
                streakBonusPerCorrect = 10,
                streakBonusMax = 100,
            },
        }
        UI.frame:Show()
        UI:SetTab("host")
        for _, key in ipairs({
            "duration",
            "durationDown",
            "durationUp",
            "answerSeconds",
            "revealSeconds",
            "allowAnswerChanges",
            "shuffleQuestions",
            "shuffleChoices",
            "repeatQuestions",
            "questionLimit",
            "correctPoints",
            "speedBonusPerSecond",
            "wrongPenaltyStart",
            "wrongPenaltyEnd",
            "wrongPenaltyCurve",
            "streakBonusPerCorrect",
            "streakBonusMax",
        }) do
            Same(UI[key], nil, "host has no control that overrides pack-owned rules: " .. key)
        end
        Same(UI.durationInfo.kind, "FontString", "answer and reveal clocks are read-only text")
        Same(UI.hostHelp.kind, "FontString", "rule summary is read-only text")
        local previousSummary
        for case, definition in ipairs(configurations) do
            local id = "interface-rule-clock-" .. case
            Check(
                Quiz:RegisterQuestionPack({
                    id = id,
                    title = "Clock and rules " .. case,
                    rules = definition,
                    questions = {
                        {
                            id = "clock",
                            prompt = "Which clock does this quiz use?",
                            choices = { "Pack", "Host", "Player", "None" },
                            correctIndex = 1,
                        },
                    },
                }),
                "variable-clock UI pack registers"
            )
            UI:RefreshPack()
            local savedSettings = Quiz.Store:GetSettings()
            SelectDropdown(UI.pack, id)
            local rules, rulesKey = Quiz:GetPackRules(id)
            Same(
                UI.durationInfo:GetText(),
                Quiz.L.W_RULE_DURATION_F:format(rules.answerSeconds, rules.revealSeconds),
                "selecting a pack updates both clock labels immediately"
            )
            local summary = UI.hostHelp:GetText()
            Check(summary ~= previousSummary, "pack selection rerenders its own rule summary")
            previousSummary = summary
            Check(
                summary:find(Quiz.L.W_RULE_CORRECT_F:format(rules.correctPoints, rules.speedBonusPerSecond), 1, true),
                "summary shows this pack's base and timed reward"
            )
            Check(
                summary:find(Quiz.L.W_RULE_WRONG_F:format(rules.wrongPenaltyStart, rules.wrongPenaltyEnd), 1, true),
                "summary shows this pack's penalty endpoints"
            )
            Check(summary:find(Quiz.L.W_RULE_LOCKED, 1, true), "summary explains the authored answer lock")
            local streakLabel = rules.streakBonusPerCorrect > 0
                    and Quiz.L.W_RULE_STREAK_F:format(rules.streakBonusPerCorrect, rules.streakBonusMax)
                or Quiz.L.W_RULE_NO_STREAK
            Check(summary:find(streakLabel, 1, true), "summary shows enabled or disabled streak bonuses")
            Check(
                UI.hostHelp:GetStringHeight() <= UI.hostHelp:GetHeight() + EPSILON,
                "longest supported English rule summary fits its reserved text height"
            )
            Check(UI.hostHelp:GetBottom() > UI.start:GetTop(), "rule summary never overlaps the game controls")
            for key, value in pairs(savedSettings) do
                Same(Quiz.Store:GetSettings()[key], value, "pack selection does not persist a host override")
            end
            for _, entry in ipairs(UI.pack:GetMenuDescription().entries) do
                Check(entry:GetData() ~= "all", "incompatible rule packs cannot be combined through the host dropdown")
            end
            Click(UI.start)
            local active = Main.game.round
            Same(Main.game.rulesKey, rulesKey, "hosting takes rules from the selected pack")
            Same(
                active.deadline - active.startedAt,
                rules.answerSeconds,
                "host draft duration cannot override the authored clock"
            )
            TimerGeometry(rules.answerSeconds)
            TimerGradient(rules.answerSeconds, rules.answerSeconds)
            UI.frame:Hide()
            Click(Widget.choices[active.correctIndex])
            Check(Main:GetHostView().locked, "first accepted choice immediately locks a no-change pack")
            local originalAnswer = active.answers[Quiz.Identity.guid]
            for _, choice in ipairs(Widget.choices) do
                Same(choice:IsEnabled(), false, "answer lock disables all choices before expiry")
            end
            Check(Widget.timer:GetScript("OnUpdate"), "locking an answer leaves the countdown animation running")
            local deadline, colorCount = active.deadline, Test.colorCreations
            Widget.choices[active.correctIndex % #active.choices + 1]:GetScript("OnClick")()
            Same(
                active.answers[Quiz.Identity.guid],
                originalAnswer,
                "even a stale disabled callback cannot replace a locked answer"
            )
            for _, remaining in ipairs({ rules.answerSeconds / 2, 0.25, 0 }) do
                Test.now = deadline - remaining
                local update = Widget.timer:GetScript("OnUpdate")
                Check(update, "a locked question continues animating up to its actual deadline")
                update(Widget.timer, 0.025)
                TimerGradient(remaining, rules.answerSeconds)
                TimerGeometry(rules.answerSeconds)
                Same(active.deadline, deadline, "locked countdown updates do not extend the answer window")
            end
            Same(Test.colorCreations, colorCount, "variable clocks reuse their gradient colors while locked")
            Same(Widget.timer:GetScript("OnUpdate"), nil, "variable timer removes its animation at timeout")
            ScoreHidden("a variable timer expiring is not an authoritative result")
            Check(Main:Stop(), "variable-clock UI fixture stops without committing an unfinished round")
            UI.frame:Show()
            UI:SetTab("host")
        end
        UI.frame:Hide()
    end
    do
        local variants = {
            defaultRules,
            Quiz.Rules.Normalize({ answerSeconds = 5, correctPoints = 100, speedBonusPerSecond = 0 }),
            Quiz.Rules.Normalize({ version = 2 }),
        }
        for index, rules in ipairs(variants) do
            Check(
                Quiz.PersonalScores:RecordResult({
                    host = "Comparison-TestRealm",
                    session = "ui-score-rules.1",
                    roundId = index,
                    packId = "ui-rule-score-rows",
                    packTitle = "Comparable score rows",
                    packVersion = 1,
                    scoringVersion = Quiz.Scoring.VERSION,
                    rulesKey = Quiz.Rules.Encode(rules),
                    duration = rules.answerSeconds,
                    choiceCount = 4,
                    correctIndex = 1,
                    selected = 1,
                    elapsed = 1,
                    streak = 1,
                    streakBonus = 0,
                    points = Quiz.Scoring.Calculate(true, 1, rules.answerSeconds, rules, 1),
                }),
                "UI comparison fixture records a rule-specific personal result"
            )
        end
        UI.frame:Show()
        UI:SetTab("scores")
        SelectDropdown(UI.boardSwitch, "personal")
        local lines = {}
        for _, line in ipairs(UI:GetPersonalScoreLines()) do
            if line:find("Comparable score rows", 1, true) then
                lines[#lines + 1] = line
                Check(
                    not line:find("104.8", 1, true),
                    "UI never presents the mixed-rule aggregate as a comparable score"
                )
            end
        end
        Same(#lines, 3, "the same pack displays separate scores for each distinct rule key")
        Check(
            lines[1]:find(Quiz.L.W_RULE_VARIANT_F:format(1, 1), 1, true),
            "equal rule revisions distinguish their first variant"
        )
        Check(
            lines[2]:find(Quiz.L.W_RULE_VARIANT_F:format(1, 2), 1, true),
            "equal rule revisions distinguish their second variant"
        )
        Check(
            lines[3]:find(Quiz.L.W_RULE_VERSION_F:format(2), 1, true),
            "a different authored revision has its own rule label"
        )
        Check(
            UI.board:GetText():find("Comparable score rows", 1, true),
            "actual score panel renders the rule-specific rows"
        )
        Same(
            UI.boardHint:GetText(),
            Quiz.L.W_PERSONAL_HELP,
            "score panel continues to explain separate rules and unverified progress"
        )
        UI.frame:Hide()
    end
    SetupShadowsUnchanged()
    Main:OnEvent("PLAYER_LOGOUT")
    Same(#Test.errors, 0, "GUI lifecycle never enters the error handler")
    Same(#Test.sent, 0, "GUI actions never send visible chat messages")
    Same(_G.Orbit, nil, "standalone styling never creates or reaches an Orbit dependency")
    return assertions
end

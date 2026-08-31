local HOST = "Polishhost-ForeignRealm"
local SESSION = "hud-polish.1"
local PACK_ID = "hud-polish-pack"
local WINNER = "Quick-ForeignRealm"
local EPSILON = 0.000001
local ANIMATION_SECONDS = 2.2
local FADE_DELAY = 1.4
local MIN_SCORE_WIDTH = 44
local SCORE_WIDE_FONT = "Quiz score width font"
local SCORE_WIDE_PATH = "Interface\\AddOns\\QuizTest\\ScoreWide.ttf"
local GEOMETRY_CALLS = {
    "setPointCalls",
    "clearPointCalls",
    "allPointCalls",
    "sizeCalls",
    "textCalls",
    "stringHeightMeasurements",
    "fontCalls",
    "fontObjectAssignments",
}
local DISPLAYS = { { 1920, 1080, 0.71 }, { 1601, 901, 0.83 }, { 800, 600, 1.25 } }

return function(Quiz)
    local assertions, nextId = 0, 0
    local protocolSession = SESSION
    local Widget, SessionUI, UI = Quiz.Widget, Quiz.Session, Quiz.UI
    local defaultRulesKey = Quiz.Rules.Encode(Quiz.Rules.Normalize())
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function Near(actual, expected, message)
        Check(math.abs(actual - expected) < EPSILON, message .. ": " .. actual .. " ~= " .. expected)
    end
    local function Pixel(region)
        return PixelUtil.GetPixelToUIUnitFactor() / region:GetEffectiveScale()
    end
    local function Grid(region)
        local left, bottom, width, height = region:GetScaledRect()
        local pixel = PixelUtil.GetPixelToUIUnitFactor()
        for _, edge in ipairs({ left, bottom, left + width, bottom + height }) do
            Near(edge / pixel, math.floor(edge / pixel + 0.5), "HUD region edges stay on the physical grid")
        end
    end
    local function Labels()
        local labels = { Widget.packText, Widget.prompt, Widget.scoreText, Widget.winnerText }
        for _, choice in ipairs(Widget.choices) do
            labels[#labels + 1] = choice.Text
        end
        return labels
    end
    local function Regions()
        local scrollbar = Widget.questionScroll.ScrollBar
        local regions = {
            Widget.frame,
            Widget.content,
            Widget.questionScroll,
            Widget.questionContent,
            Widget.packText,
            Widget.prompt,
            Widget.scoreText,
            Widget.winnerText,
            Widget.timer,
            scrollbar,
            scrollbar.Track,
            scrollbar.Thumb,
            Widget.editOutline,
        }
        for _, choice in ipairs(Widget.choices) do
            regions[#regions + 1], regions[#regions + 2] = choice, choice.Text
        end
        return regions
    end
    local function Snapshot(excluded)
        local snapshot = {
            regions = {},
            fontState = {},
            frames = #Test.frames,
            labels = Test.fontStringCreations,
            fonts = Test.fontObjectCreations,
            animations = Test.animationCreations,
            scorePlays = Widget.scoreAnimation.playCalls,
            scoreStops = Widget.scoreAnimation.stopCalls,
            winnerPlays = Widget.winnerAnimation.playCalls,
            winnerStops = Widget.winnerAnimation.stopCalls,
        }
        for role, font in pairs(Widget.fontObjects) do
            snapshot.fontState[role] = { font.fontCalls, font.copyFontCalls, font.fontObjectAssignments }
        end
        for _, region in ipairs(Regions()) do
            if region ~= excluded then
                local state = { rect = { region:GetScaledRect() } }
                for _, key in ipairs(GEOMETRY_CALLS) do
                    state[key] = region[key]
                end
                snapshot.regions[region] = state
            end
        end
        return snapshot
    end
    local function Stable(snapshot)
        Same(#Test.frames, snapshot.frames, "press feedback allocates no frames")
        Same(Test.fontStringCreations, snapshot.labels, "press feedback allocates no text regions")
        Same(Test.fontObjectCreations, snapshot.fonts, "press feedback allocates no font objects")
        Same(Test.animationCreations, snapshot.animations, "press feedback allocates no animations")
        Same(Widget.scoreAnimation.playCalls, snapshot.scorePlays, "press cannot start score feedback")
        Same(Widget.scoreAnimation.stopCalls, snapshot.scoreStops, "press cannot flicker inactive score feedback")
        Same(Widget.winnerAnimation.playCalls, snapshot.winnerPlays, "press cannot start winner feedback")
        Same(Widget.winnerAnimation.stopCalls, snapshot.winnerStops, "press cannot flicker inactive winner feedback")
        for role, font in pairs(Widget.fontObjects) do
            local previous = snapshot.fontState[role]
            Same(font.fontCalls, previous[1], "interaction never reapplies the shared HUD font: " .. role)
            Same(font.copyFontCalls, previous[2], "interaction never recopies a HUD font object: " .. role)
            Same(font.fontObjectAssignments, previous[3], "interaction never rebinds shared font inheritance: " .. role)
        end
        for region, before in pairs(snapshot.regions) do
            for _, key in ipairs(GEOMETRY_CALLS) do
                Same(region[key], before[key], "press changes only its owned text anchor: " .. key)
            end
            for index, value in ipairs({ region:GetScaledRect() }) do
                Near(value, before.rect[index], "press leaves unrelated rendered geometry untouched")
            end
        end
    end
    local function HiddenWinner(message)
        Same(Widget.winnerText:IsShown(), false, message)
        Same(Widget.winnerAnimation:IsPlaying(), false, message .. " has no running native animation")
    end
    local function Begin(count, long, rules)
        Quiz.Comms:Clear()
        nextId = nextId + 1
        rules = rules or Quiz.Rules.Normalize()
        local rulesKey = Quiz.Rules.Encode(rules)
        if SessionUI.client.rulesKey and SessionUI.client.rulesKey ~= rulesKey then
            Check(SessionUI:Leave(), "switching rule fixtures leaves the previous authority")
            protocolSession = SESSION .. ".rules." .. nextId
            Check(SessionUI:JoinHost(HOST, protocolSession), "different rules start a new advertised game")
            SessionUI:Receive(HOST, { "W", SessionUI.client.request, protocolSession, "HUD polish", "0.0" })
            Quiz.Main:CancelTicker()
        end
        local choices = {}
        for index = 1, count or 4 do
            choices[index] = (long and string.rep("Long answer ", 7) or "Answer ") .. index
        end
        local packet = {
            "Q",
            protocolSession,
            tostring(nextId),
            "1",
            "1",
            "1",
            tostring(rules.answerSeconds),
            long and string.rep("A long lore question ", 7) or "Which answer is correct?",
            tostring(#choices),
            "hard",
            "Warcraft III",
            PACK_ID,
            long and string.rep("Lore pack ", 6) or "Polish pack",
            "1",
            "3",
            rulesKey,
        }
        for _, choice in ipairs(choices) do
            packet[#packet + 1] = choice
        end
        SessionUI:Receive(HOST, packet)
        SessionUI:Receive(
            HOST,
            { "O", protocolSession, tostring(nextId), tostring(GetServerTime() + rules.answerSeconds) }
        )
        Widget:Refresh()
        Same(SessionUI.view.state, "open", "HUD fixture opens an actual protocol question")
        Same(SessionUI.view.id, nextId, "HUD fixture accepts the newly supplied question identity")
        Same(
            SessionUI.view.rulesKey,
            rulesKey,
            "HUD fixture accepts the authored rules rather than retaining an old view"
        )
        return SessionUI.view, packet
    end
    local function Result(view, winnerName, winnerElapsed, correct, elapsed, streak)
        local answeredCorrectly = correct ~= false
        elapsed = elapsed or (answeredCorrectly and 5 or 6)
        streak = streak or (answeredCorrectly and 1 or 0)
        local points = Quiz.Scoring.Calculate(answeredCorrectly, elapsed, view.duration, view.rules, streak)
        return {
            "R",
            view.session,
            tostring(view.id),
            "2",
            answeredCorrectly and "2" or "1",
            string.format("%.1f", points),
            "2.0",
            answeredCorrectly and "2" or "0",
            "3",
            "",
            PACK_ID,
            view.packTitle,
            "1",
            "3",
            tostring(view.duration),
            tostring(#view.choices),
            string.format("%.17g", elapsed),
            winnerName or "",
            winnerElapsed and string.format("%.17g", winnerElapsed) or "",
            view.rulesKey,
            tostring(streak),
            string.format("%.1f", Quiz.Scoring.StreakBonus(view.rules, streak)),
        }
    end
    local function Display(display)
        Test.physicalWidth, Test.physicalHeight = display[1], display[2]
        UIParent:SetScale(display[3])
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
        Widget:OnDisplayChanged()
    end
    local function TextRoles()
        local _, answerHeight = Widget.choices[1].Text:GetFont()
        local _, questionHeight = Widget.prompt:GetFont()
        local _, packHeight = Widget.packText:GetFont()
        local _, winnerHeight = Widget.winnerText:GetFont()
        Near(questionHeight - answerHeight, 4, "question text is exactly four logical font units larger than answers")
        Same(packHeight, math.max(8, answerHeight - 4), "pack label has its smaller text size")
        Same(winnerHeight, math.max(8, answerHeight - 2), "winner popup has its compact text size")
        Same(Widget.prompt:GetFontObject(), Widget.fontObjects.question, "question uses its owned font object")
        Same(Widget.packText:GetFontObject(), Widget.fontObjects.pack, "pack label uses its owned font object")
        Same(Widget.winnerText:GetFontObject(), Widget.fontObjects.winner, "winner uses its owned font object")
        for _, label in ipairs(Labels()) do
            Same(label.fontCalls, nil, "visible HUD text never receives an inline font file")
            local font = label:GetFontObject()
            Check(font ~= GameFontHighlight, "HUD text is not mutating a shared Blizzard font")
            local x, y = label:GetShadowOffset()
            Near(x / Pixel(label), -2, "rendered shadows retain a two-physical-pixel left offset")
            Near(y / Pixel(label), -2, "rendered shadows retain a two-physical-pixel down offset")
            local fontX, fontY = font:GetShadowOffset()
            Near(fontX, x, "owned font object carries the same horizontal shadow")
            Near(fontY, y, "owned font object carries the same vertical shadow")
            Same(select(4, font:GetShadowColor()), 1, "owned font object has an opaque native shadow")
        end
    end
    local function Geometry()
        TextRoles()
        local pixel = Pixel(Widget.prompt)
        Same(Widget.packText:GetText(), SessionUI.view.packTitle, "small heading shows the actual question pack")
        Same(Widget.packText:IsShown(), true, "known pack heading is visible")
        Near(
            (Widget.packText:GetBottom() - Widget.prompt:GetTop()) / pixel,
            4,
            "pack heading is four physical pixels above the question"
        )
        for index, expected in ipairs({ 0.6, 0.6, 0.6, 1 }) do
            Near(select(index, Widget.packText:GetTextColor()), expected, "pack heading is visibly muted")
        end
        Near(
            (Widget.prompt:GetLeft() - Widget.questionContent:GetLeft()) / pixel,
            2,
            "scroll body reserves the leftward text shadow"
        )
        Near(
            (Widget.questionContent:GetRight() - Widget.prompt:GetRight()) / pixel,
            1,
            "scroll body reserves rightward pressed text"
        )
        Near(
            (Widget.prompt:GetBottom() - Widget.timer:GetTop()) / pixel,
            2,
            "larger wrapped question keeps the close two-pixel timer gap"
        )
        Near(Widget.timer:GetHeight() / pixel, 2, "timer remains two physical pixels at every scale")
        local last = Widget.choices[#SessionUI.view.choices]
        Near(
            (last:GetBottom() - Widget.questionContent:GetBottom()) / pixel,
            3,
            "scroll content includes pressed text and its lower shadow"
        )
        Check(
            Widget.prompt:GetHeight() + EPSILON >= Widget.prompt.lastStringHeightMeasurement.requiredHeight,
            "larger question font is measured before wrapping height is fixed"
        )
        Check(
            Widget.winnerText:GetTop() < Widget.questionScroll:GetBottom(),
            "winner footer is outside and below answer clipping"
        )
        Check(
            Widget.winnerText:GetBottom() + EPSILON >= Widget.content:GetBottom(),
            "pixel-rounded winner footer remains inside the content's lower edge"
        )
        Check(
            Widget.winnerText:GetLeft() + EPSILON >= Widget.content:GetLeft()
                and Widget.winnerText:GetRight() <= Widget.content:GetRight() + EPSILON,
            "winner footer remains inside the content's horizontal edges"
        )
        Same(Widget.winnerText:GetParent(), Widget.content, "winner text is not a scroll child")
        local left, bottom, width, height = Widget.content:GetScaledRect()
        local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
        Check(
            left >= screenLeft - EPSILON and bottom >= screenBottom - EPSILON,
            "HUD remains inside lower screen bounds"
        )
        Check(left + width <= screenLeft + screenWidth + EPSILON, "HUD remains inside right screen edge")
        Check(bottom + height <= screenBottom + screenHeight + EPSILON, "HUD remains inside upper screen edge")
        for _, region in ipairs({ Widget.content, Widget.packText, Widget.prompt, Widget.timer, Widget.winnerText }) do
            Grid(region)
        end
    end
    local function Down(choice)
        choice:GetScript("OnEnter")(choice)
        choice:GetScript("OnMouseDown")(choice, "LeftButton")
        Same(choice.pressed, true, "left mouse down activates owned text-only press feedback")
        Near(
            (choice.Text:GetLeft() - choice:GetLeft()) / Pixel(choice),
            1,
            "pressed text moves one physical pixel right"
        )
        Near((choice:GetTop() - choice.Text:GetTop()) / Pixel(choice), 1, "pressed text moves one physical pixel down")
        Near(choice.Text:GetAlpha(), 0.8, "pressed text dims subtly without drawing button art")
        Same(choice:GetFontString(), nil, "pressed text remains outside Blizzard button font-state machinery")
    end
    local function Released(choice, message)
        Same(choice.pressed, false, message)
        Near(choice.Text:GetLeft(), choice:GetLeft(), message .. " restores horizontal text position")
        Near(choice.Text:GetTop(), choice:GetTop(), message .. " restores vertical text position")
        Same(choice.Text:GetAlpha(), 1, message .. " restores text opacity")
    end
    local function WinnerShown(view)
        Same(Widget.winnerText:IsShown(), true, "confirmed multiplayer winner shows the popup")
        Same(
            Widget.winnerText:GetText(),
            Quiz.L.W_FASTEST_F:format(view.fastestName, view.fastestElapsed),
            "popup identifies the actual winner and host-measured time"
        )
        Check(Widget.winnerAnimation:IsPlaying(), "winner uses a native one-shot animation")
        Near(Widget.winnerAnimation:GetDuration(), ANIMATION_SECONDS, "winner fits inside the result interval")
        Near(Widget.winnerFade:GetStartDelay(), FADE_DELAY, "winner stays readable before fading")
        Near(
            Widget.winnerFade:GetDuration(),
            ANIMATION_SECONDS - FADE_DELAY,
            "winner fades during the final animation segment"
        )
        Same(Widget.winnerText:GetAlpha(), 1, "new winner starts fully opaque")
        Same(Widget.winnerRise:GetRegionParent(), Widget.winnerText, "winner rise moves text only")
        Same(Widget.winnerAnimation:GetLooping(), "NONE", "winner animation cannot loop")
        Same(Widget.winnerAnimation:GetScript("OnUpdate"), nil, "winner needs no Lua animation ticker")
        local x, y = Widget.winnerRise:GetOffset()
        Same(x, 0, "winner rises vertically without changing horizontal layout")
        Near(y / Pixel(Widget.winnerText), 6, "winner rise remains six physical pixels")
        Check(
            Widget.winnerText:GetTop() + y < Widget.questionScroll:GetBottom(),
            "winner rise never crosses into the answer viewport"
        )
    end

    UI:Toggle()
    local nativePath, nativeHeight, nativeFlags = GameFontHighlight:GetFont()
    Check(SessionUI:JoinHost(HOST), "HUD polish fixture joins one remote host")
    SessionUI:Receive(HOST, { "W", SessionUI.client.request, SESSION, "HUD polish", "0.0" })
    Quiz.Main:CancelTicker()
    local view = Begin(6, true)
    HiddenWinner("open questions never reveal a winner")
    Geometry()
    local choice = Widget.choices[3]
    choice:GetScript("OnEnter")(choice)
    local before, selected = Snapshot(choice.Text), view.selected
    Down(choice)
    Same(view.selected, selected, "mouse down does not submit an answer before release")
    Stable(before)
    choice:GetScript("OnMouseUp")(choice, "LeftButton")
    Released(choice, "mouse release resets text press feedback")
    Stable(before)
    choice:GetScript("OnClick")(choice, "LeftButton")
    Same(view.selected, 3, "release click submits the actual answer index")
    Same(choice:GetFontString(), nil, "submission keeps the owned text outside native button states")
    choice:GetScript("OnMouseDown")(choice, "RightButton")
    Released(choice, "right-click cannot press a left-click answer")

    for _, event in ipairs({ "OnLeave", "OnHide", "OnDisable" }) do
        Down(choice)
        if event == "OnHide" then
            choice:Hide()
        elseif event == "OnDisable" then
            choice:Disable()
        else
            choice:GetScript(event)(choice)
        end
        Released(choice, event .. " clears pressed text")
        choice:Show()
        choice:Enable()
    end
    Down(choice)
    Widget:StartDrag()
    Released(choice, "starting edit-mode movement clears pressed text")
    Same(Widget.dragging, true, "question widget enters native movement")
    Widget:StopDrag()
    Test.now = Test.now + 0.3
    Down(choice)
    Widget.frame:Hide()
    Released(choice, "hiding the whole HUD clears pressed text")
    Widget:Refresh()
    Down(choice)
    UI:SaveWidgetSettings({ scale = 105 })
    Released(choice, "live scale changes clear the old pixel-offset press")
    Down(choice)
    Widget:OnDisplayChanged()
    Released(choice, "display changes clear the old pixel-offset press")
    Down(Widget.choices[6])
    view = Begin(4)
    Same(Widget.choices[6].pressed, false, "new lower-choice questions clear pressed state on pooled hidden answers")
    Same(Widget.choices[6]:IsShown(), false, "unused pressed answer cannot linger in the new question")
    choice = Widget.choices[1]
    Down(choice)
    Test.now = view.deadline
    Widget.timer:GetScript("OnUpdate")(Widget.timer)
    Released(choice, "the exact answer timeout clears pressed text")
    Same(choice:IsEnabled(), false, "the timeout also disables answer input")

    view = Begin(4)
    Down(Widget.choices[1])
    local winnerPacket = Result(view, WINNER, 0.25)
    local size = { Widget.content:GetScaledRect() }
    SessionUI:Receive(HOST, winnerPacket)
    Widget:Refresh()
    Released(Widget.choices[1], "confirmed results reset pressed feedback before coloring answers")
    WinnerShown(view)
    for index, coordinate in ipairs({ Widget.content:GetScaledRect() }) do
        Near(coordinate, size[index], "winner appearance does not resize or move the HUD")
    end
    local plays, stops = Widget.winnerAnimation.playCalls, Widget.winnerAnimation.stopCalls
    SessionUI:Receive(HOST, winnerPacket)
    Widget:Refresh()
    Same(Widget.winnerAnimation.playCalls, plays, "repeated result packets cannot restart winner animation")
    Same(Widget.winnerAnimation.stopCalls, stops, "repeated result packets cannot flicker an active winner")
    Test.AdvanceAnimations(ANIMATION_SECONDS + 0.1)
    HiddenWinner("native completion hides the winner")
    Widget:Refresh()
    Same(Widget.winnerAnimation.playCalls, plays, "ordinary refresh cannot replay a completed winner popup")
    local oldPacket = winnerPacket
    view = Begin(4)
    SessionUI:Receive(HOST, oldPacket)
    Widget:Refresh()
    HiddenWinner("late old results cannot announce over a new question")
    Same(view.fastestName, nil, "late old result does not attach a winner to the new question")

    for _, reason in ipairs({ "solo", "no correct" }) do
        view = Begin(4)
        SessionUI:Receive(HOST, Result(view, nil, nil, reason ~= "no correct"))
        Widget:Refresh()
        HiddenWinner(reason .. " results have no winner popup")
    end
    for _, stop in ipairs({ "drag", "display", "scale", "hide", "pause" }) do
        view = Begin(4)
        SessionUI:Receive(HOST, Result(view, WINNER, 0.25))
        Widget:Refresh()
        WinnerShown(view)
        if stop == "drag" then
            Widget:StartDrag()
            Widget:StopDrag()
            Test.now = Test.now + 0.3
        elseif stop == "display" then
            Widget:OnDisplayChanged()
        elseif stop == "scale" then
            UI:SaveWidgetSettings({ scale = Widget.frame:GetScale() == 1 and 105 or 100 })
        elseif stop == "hide" then
            Widget.frame:Hide()
        else
            SessionUI:Receive(HOST, { "P", SESSION, tostring(view.id), "manual" })
            Widget:Refresh()
        end
        HiddenWinner(stop .. " cancels winner feedback")
        Widget:Refresh()
        HiddenWinner(stop .. " cannot replay the same winner after refresh")
    end

    view = Begin(4)
    winnerPacket = Result(view, WINNER, 0.25)
    SessionUI:Receive(HOST, winnerPacket)
    Widget:Refresh()
    Check(SessionUI:Leave(), "winner fixture explicitly leaves before reconnecting")
    Check(SessionUI:JoinHost(HOST), "winner fixture reconnects with fresh presentation caches")
    SessionUI:Receive(HOST, { "W", SessionUI.client.request, SESSION, "HUD polish", "2.0" })
    local restored = {
        "Q",
        SESSION,
        tostring(view.id),
        "1",
        "1",
        "1",
        "15",
        view.prompt,
        "4",
        "hard",
        "Warcraft III",
        PACK_ID,
        view.packTitle,
        "1",
        "3",
        defaultRulesKey,
        unpack(view.choices),
    }
    SessionUI:Receive(HOST, restored)
    Widget.winnerResultId, Widget.winnerResultSession, Widget.winnerResultHost = nil, nil, nil
    SessionUI:Receive(HOST, winnerPacket)
    Widget:Refresh()
    Same(SessionUI.view.suppressWinnerPopup, true, "durable already-scored result suppresses first-paint winner replay")
    HiddenWinner("fresh membership cannot replay a previously recorded winner")
    Quiz.Main:CancelTicker()

    for percent = 50, 200, 5 do
        UI:SaveWidgetSettings({ scale = percent })
        for _, display in ipairs(DISPLAYS) do
            Display(display)
            view = Begin(6, true)
            Geometry()
            local beforePosition = { Widget.content:GetScaledRect() }
            choice = Widget.choices[6]
            Down(choice)
            Grid(choice.Text)
            choice:GetScript("OnMouseUp")(choice, "LeftButton")
            Released(choice, "every five-percent scale resets its pixel-perfect press")
            SessionUI:Receive(HOST, Result(view, WINNER, 0.25))
            Widget:Refresh()
            WinnerShown(view)
            Geometry()
            for index, coordinate in ipairs({ Widget.content:GetScaledRect() }) do
                Near(coordinate, beforePosition[index], "winner never shifts layout at any supported scale")
            end
        end
    end
    UI:SaveWidgetSettings({ scale = 200 })
    Display({ 800, 600, 1.25 })
    view = Begin(6, true)
    Geometry()
    SessionUI:Receive(HOST, Result(view, WINNER, 0.25))
    Widget:Refresh()
    Geometry()
    local footerBottom = Widget.winnerText:GetBottom()
    Check(
        footerBottom + EPSILON >= Widget.content:GetBottom(),
        "800x600 at 200% retains the rounded footer without a one-physical-pixel overhang"
    )
    do
        local scoreRules = Quiz.Rules.Normalize({
            answerSeconds = 120,
            correctPoints = 1000,
            speedBonusPerSecond = 10,
            wrongPenaltyStart = 1000,
            wrongPenaltyEnd = 1000,
            streakBonusPerCorrect = 10,
            streakBonusMax = 100,
        })
        local function FitsScore(points)
            local label = Widget.scoreText
            local text = Quiz.L.W_SCORE_DELTA_F:format(points)
            local previousText, previousCalls = label:GetText(), label.textCalls
            local width = label:GetUnboundedStringWidthForText(text)
            Check(
                label:GetWidth() + EPSILON >= width + 2 * Pixel(label),
                "reserved score column fits the signed reward and its shadow: " .. text
            )
            Same(
                label:GetText(),
                previousText,
                "measurement never writes a temporary score into the visible text region"
            )
            Same(label.textCalls, previousCalls, "non-mutating width probes cause no visible SetText churn")
            Same(label.fontCalls, nil, "score measurement never inlines a font file on the visible label")
            Near(label:GetRight(), Widget.content:GetRight(), "wide score column stays inside the content's right edge")
            Check(
                label:GetLeft() > Widget.questionScroll:GetRight(),
                "wide score text cannot overlap the question body"
            )
            Grid(label)
        end
        local function RevealStable(current, correct, elapsed, streak, expected)
            local before = Snapshot()
            local packet = Result(current, nil, nil, correct, elapsed, streak)
            packet[7] = packet[6]
            before.scorePlays = before.scorePlays + 1
            local scoreState = before.regions[Widget.scoreText]
            scoreState.textCalls = (scoreState.textCalls or 0) + 1
            SessionUI:Receive(HOST, packet)
            Widget:Refresh()
            Same(
                Widget.scoreText:GetText(),
                Quiz.L.W_SCORE_DELTA_F:format(expected),
                "confirmed author-defined reward retains every signed digit"
            )
            Check(
                Widget.scoreText:IsShown() and Widget.scoreAnimation:IsPlaying(),
                "large rewards use the same native score animation"
            )
            FitsScore(expected)
            Stable(before)
            local replay = Snapshot()
            SessionUI:Receive(HOST, packet)
            Widget:Refresh()
            Stable(replay)
        end
        UI:SaveWidgetSettings({ scale = 100, font = "" })
        Display(DISPLAYS[1])
        view = Begin(4)
        local normalWidth = Widget.scoreText:GetWidth()
        Check(
            normalWidth + EPSILON >= MIN_SCORE_WIDTH
                and normalWidth < MIN_SCORE_WIDTH + Pixel(Widget.scoreText) + EPSILON,
            "ordinary native-font rewards retain the 44-unit minimum column rounded to pixels"
        )
        local minimumFrames, minimumLabels = #Test.frames, Test.fontStringCreations
        view = Begin(4, false, scoreRules)
        local widened = Widget.scoreText:GetWidth()
        Check(widened > normalWidth, "large configured bounds reserve additional width before the first answer")
        Same(Widget.scoreText:IsShown(), false, "reserving a large reward never reveals a speculative score")
        FitsScore(2300)
        FitsScore(-1000)
        FitsScore(2200)
        RevealStable(view, true, 0, 1, 2200)
        Same(#Test.frames, minimumFrames, "large score support reuses existing HUD frames")
        Same(Test.fontStringCreations, minimumLabels, "large score support needs no extra text region")
        Test.fontWidths[SCORE_WIDE_PATH] = 11
        Test.fontGlyphWidths = Test.fontGlyphWidths or {}
        Test.fontGlyphWidths[SCORE_WIDE_PATH] = { ["8"] = 18 }
        local library = LibStub("LibSharedMedia-3.0")
        Check(library:Register("font", SCORE_WIDE_FONT, SCORE_WIDE_PATH), "wide proportional-digit font registers")
        view = Begin(4, false, scoreRules)
        local questionId, deadline = view.id, view.deadline
        UI:SaveWidgetSettings({ font = SCORE_WIDE_FONT })
        Same(SessionUI.view.id, questionId, "font-driven score width reflow keeps the current question")
        Same(SessionUI.view.deadline, deadline, "font-driven score width reflow keeps the current clock")
        Check(
            Widget.scoreText:GetWidth() > widened,
            "the same question reserves the selected font's wider glyph metrics"
        )
        Check(
            Widget.scoreText:GetUnboundedStringWidthForText("+1880.0")
                > Widget.scoreText:GetUnboundedStringWidthForText("+2300.0"),
            "proportional digits can make a non-extreme valid reward wider than the maximum"
        )
        FitsScore(1880)
        RevealStable(view, true, 32, 1, 1880)
        for _, font in ipairs({ "", SCORE_WIDE_FONT }) do
            UI:SaveWidgetSettings({ font = font })
            for _, scale in ipairs({ 50, 100, 200 }) do
                UI:SaveWidgetSettings({ scale = scale })
                for _, display in ipairs(DISPLAYS) do
                    Display(display)
                    for _, correct in ipairs({ true, false }) do
                        view = Begin(6, true, scoreRules)
                        local width = Widget.scoreText:GetWidth()
                        Same(
                            Widget.scoreText:IsShown(),
                            false,
                            "question layout reserves both score signs before any click"
                        )
                        FitsScore(2300)
                        FitsScore(-1000)
                        FitsScore(1880)
                        Geometry()
                        local beforeInput = Snapshot()
                        for _, selected in ipairs({ 1, 4, 2 }) do
                            Widget.choices[selected]:GetScript("OnClick")(Widget.choices[selected], "LeftButton")
                            Same(view.selected, selected, "large score reservation preserves normal answer changes")
                            Near(Widget.scoreText:GetWidth(), width, "answer changes never resize the score column")
                            Stable(beforeInput)
                        end
                        RevealStable(view, correct, 0, correct and 11 or 0, correct and 2300 or -1000)
                        Near(
                            Widget.scoreText:GetWidth(),
                            width,
                            "revealing either score sign uses only the pre-reserved width"
                        )
                        Geometry()
                    end
                end
            end
        end
        view = Begin(4, false, scoreRules)
        local beforeViewport = view.id
        UIParent:SetSize(150, 300)
        Widget:OnDisplayChanged()
        Same(SessionUI.view.id, beforeViewport, "very narrow viewport reflow keeps the same question")
        Check(
            Widget.scoreText:GetWidth() < Widget.scoreText:GetUnboundedStringWidthForText("+2300.0"),
            "narrow-screen case actually exercises the score-width cap"
        )
        Check(
            Widget.scoreText:GetLeft() >= Widget.content:GetLeft() - EPSILON,
            "a score wider than the screen stays inside the widget"
        )
        Check(
            Widget.scoreText:GetRight() <= Widget.content:GetRight() + EPSILON,
            "screen cap does not extend the score outside its right edge"
        )
        Check(
            Widget.prompt:GetWidth() > 0 and Widget.questionScroll:GetWidth() + Pixel(Widget.prompt) >= 16,
            "screen cap leaves a usable logical question column"
        )
        Check(
            Widget.scoreText:GetLeft() > Widget.questionScroll:GetRight(),
            "screen-capped score retains the question gutter"
        )
        Grid(Widget.scoreText)
        UI:SaveWidgetSettings({ scale = 100, font = "" })
        Display(DISPLAYS[1])
        view = Begin(4)
        Near(
            Widget.scoreText:GetWidth(),
            normalWidth,
            "returning to normal rules and native font restores the original minimum layout"
        )
    end
    Same(select(1, GameFontHighlight:GetFont()), nativePath, "HUD polish never mutates Blizzard's shared font file")
    Same(select(2, GameFontHighlight:GetFont()), nativeHeight, "HUD polish never mutates Blizzard's shared font size")
    Same(select(3, GameFontHighlight:GetFont()), nativeFlags, "HUD polish never mutates Blizzard's shared font flags")
    Same(Test.fontObjectCreations, 4, "all HUD roles reuse exactly four owned font objects")
    Same(#Test.errors, 0, "polished HUD has no unexpected Lua errors")
    return assertions
end

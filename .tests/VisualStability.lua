local EPSILON = 0.000001
local HOST = "Visualhost-TestRealm"
local SESSION = "visual-stability.1"
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
local DISPLAYS = {
    { 1920, 1080, 0.61 },
    { 1920, 1080, 0.71 },
    { 2560, 1440, 0.71 },
    { 1601, 901, 0.83 },
    { 800, 600, 1.25 },
}

return function(Quiz)
    local assertions = 0
    local UI, Widget, Session = Quiz.UI, Quiz.Widget, Quiz.Session
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
    local function Grid(value, message)
        local pixels = value / PixelUtil.GetPixelToUIUnitFactor()
        Near(pixels, math.floor(pixels + 0.5), message)
    end
    local function Edges(region, message)
        local left, bottom, width, height = region:GetScaledRect()
        Grid(left, message .. " left")
        Grid(bottom, message .. " bottom")
        Grid(left + width, message .. " right")
        Grid(bottom + height, message .. " top")
    end
    local function Display(display)
        Test.physicalWidth, Test.physicalHeight = display[1], display[2]
        UIParent:SetScale(display[3])
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
        Quiz.Main:OnEvent("DISPLAY_SIZE_CHANGED")
    end
    local function Snapshot()
        local bar = Widget.questionScroll.ScrollBar
        local regions = {
            Widget.frame,
            Widget.content,
            Widget.questionScroll,
            Widget.questionContent,
            Widget.prompt,
            Widget.timer,
            Widget.scoreText,
            Widget.editOutline,
            bar,
            bar.Track,
            bar.Thumb,
        }
        for _, choice in ipairs(Widget.choices) do
            regions[#regions + 1], regions[#regions + 2] = choice, choice.Text
        end
        local snapshot = {
            regions = {},
            frames = #Test.frames,
            fonts = Test.fontStringCreations,
            textures = Test.textureCreations,
            animations = Test.animationCreations,
            colors = Test.colorCreations,
            play = Widget.scoreAnimation.playCalls,
            stop = Widget.scoreAnimation.stopCalls,
        }
        for _, region in ipairs(regions) do
            local state = { rect = { region:GetScaledRect() } }
            for _, key in ipairs(GEOMETRY_CALLS) do
                state[key] = region[key]
            end
            state.enableCalls = region.enableCalls
            if region == Widget.scoreText or region == bar then
                state.showCalls, state.hideCalls = region.showCalls, region.hideCalls
            end
            snapshot.regions[region] = state
        end
        return snapshot
    end
    local function Stable(snapshot)
        Same(#Test.frames, snapshot.frames, "same-question interaction allocates no frames")
        Same(Test.fontStringCreations, snapshot.fonts, "same-question interaction allocates no text regions")
        Same(Test.textureCreations, snapshot.textures, "same-question interaction allocates no textures")
        Same(Test.animationCreations, snapshot.animations, "same-question interaction allocates no animations")
        Same(Test.colorCreations, snapshot.colors, "same-question interaction reuses gradient colors")
        Same(Widget.scoreAnimation.playCalls, snapshot.play, "same-question interaction never restarts score feedback")
        Same(Widget.scoreAnimation.stopCalls, snapshot.stop, "idle or unchanged score animation is not stopped again")
        for region, before in pairs(snapshot.regions) do
            for _, key in ipairs(GEOMETRY_CALLS) do
                Same(region[key], before[key], "same-question interaction leaves geometry/text untouched: " .. key)
            end
            Same(region.enableCalls, before.enableCalls, "answer enable state changes only at a real transition")
            if before.showCalls ~= nil or before.hideCalls ~= nil then
                Same(region.showCalls, before.showCalls, "unchanged right-side adornment is not shown again")
                Same(region.hideCalls, before.hideCalls, "unchanged right-side adornment is not hidden again")
            end
            local rect = { region:GetScaledRect() }
            for index, coordinate in ipairs(rect) do
                Near(coordinate, before.rect[index], "same-question interaction preserves the rendered rectangle")
            end
        end
    end

    for _, scale in ipairs({ 0.5, 1, 2 }) do
        local pixel = PixelUtil.GetPixelToUIUnitFactor() / scale
        for _, sample in ipairs({ { -1.5, -2 }, { -0.5, -1 }, { -0.49, 0 }, { 0.49, 0 }, { 0.5, 1 }, { 1.5, 2 } }) do
            Near(
                PixelUtil.GetNearestPixelSize(sample[1] * pixel, scale),
                sample[2] * pixel,
                "native half-pixel ties round away from zero"
            )
        end
        for _, sample in ipairs({ { -0.1, 2, -2 }, { 0, 2, 2 }, { 0.1, 2, 2 }, { -0.1, 0, 0 }, { -2.5, 2, -3 } }) do
            Near(
                PixelUtil.GetNearestPixelSize(sample[1] * pixel, scale, sample[2]),
                sample[3] * pixel,
                "native minimum pixel size preserves the input sign and larger rounded extents"
            )
        end
    end
    Same(PixelUtil.GetNearestPixelSize(0, nil), 0, "native zero without a minimum needs no scale")
    Same(PixelUtil.GetNearestPixelSize(0, nil, 0), 0, "native zero with a zero minimum returns immediately")

    Display(DISPLAYS[1])
    UI:Toggle()
    local bare = CreateFrame("Button", nil, UIParent)
    bare.Text = bare:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bare.Text:SetText("owned label")
    Same(bare:GetFontString(), nil, "a Lua Text field does not register a native button font string")
    bare:SetText("native button text")
    Same(bare.Text:GetText(), "owned label", "native button SetText does not target an unregistered owned label")
    bare:SetFontString(bare.Text)
    bare:SetText("registered text")
    Same(bare.Text:GetText(), "registered text", "explicit native registration retains its separate contract")
    bare:Hide()
    Check(Session:JoinHost(HOST, SESSION), "participant fixture joins a real protocol session")
    local client = Session.client
    Session:Receive(HOST, { "W", client.request, SESSION, "Visual checks", "0.0" })
    UI.frame:Hide()
    for case, display in ipairs({ { 1920, 1080, 0.71 }, { 800, 600, 1.25 } }) do
        Display(display)
        UI:SaveWidgetSettings({ scale = case == 2 and 200 or 100 })
        local question = {
            "Q",
            SESSION,
            tostring(case),
            "1",
            tostring(case),
            "2",
            "15",
            case == 1 and "Which answer is correct?" or string.rep("A long question ", 9),
            "6",
            "",
            "",
            "test-pack",
            "Test pack",
            "1",
            "2",
        }
        for index = 1, 6 do
            question[#question + 1] = case == 1 and "Choice " .. index or string.rep("Long choice ", 8) .. index
        end
        Session:Receive(HOST, question)
        Session:Receive(HOST, { "O", SESSION, tostring(case), tostring(GetServerTime() + 15) })
        Widget:Refresh()
        Same(Session.view.state, "open", "stability fixture has an authoritative open clock")
        local bar = Widget.questionScroll.ScrollBar
        if case == 2 then
            Check(bar:GetRange() > 0, "long-question case exercises a visible scrollbar")
            bar:ScrollTo(bar:GetRange() * 0.37, true)
        end
        local deadline = Session.view.deadline
        for _, index in ipairs({ 1, 6, 6, 2 }) do
            local before = Snapshot()
            local choice = Widget.choices[index]
            Same(choice:GetFontString(), nil, "clickable answers never register native button text")
            choice:GetScript("OnEnter")(choice)
            choice:GetScript("OnClick")(choice, "LeftButton")
            choice:GetScript("OnLeave")(choice)
            Same(Session.view.selected, index, "bare text click retains exact answer-index mapping")
            Stable(before)
            local ack = {
                "K",
                SESSION,
                tostring(case),
                tostring(index),
                tostring(client.answerRevision),
                client.request,
                tostring(client.answerRevision),
            }
            Session:Receive(HOST, ack)
            Widget:Refresh()
            Same(Session.view.pending, false, "authoritative acknowledgement confirms the selected answer")
            Stable(before)
            Session:Receive(HOST, ack)
            Session:Receive(HOST, question)
            Widget:Refresh()
            Widget.questionScroll:UpdateScrollChildRect()
            bar:Refresh()
            Stable(before)
            Near(Session.view.deadline, deadline, "clicks and same-question snapshots never reset the clock")
        end
        Session:Receive(HOST, {
            "R",
            SESSION,
            tostring(case),
            "2",
            "2",
            "2.0",
            "2.0",
            "1",
            "1",
            "",
            "test-pack",
            "Test pack",
            "1",
            "2",
            "15",
            "6",
            "5",
            "",
            "",
        })
        Widget:Refresh()
        Check(Widget.scoreAnimation:IsPlaying(), "confirmed result starts personal feedback once")
        local before = Snapshot()
        Session:Receive(HOST, {
            "R",
            SESSION,
            tostring(case),
            "2",
            "2",
            "2.0",
            "2.0",
            "1",
            "1",
            "",
            "test-pack",
            "Test pack",
            "1",
            "2",
            "15",
            "6",
            "5",
            "",
            "",
        })
        Widget:Refresh()
        Stable(before)
        Test.AdvanceAnimations(2.2)
        before = Snapshot()
        Widget:Refresh()
        Stable(before)
        Same(Widget.scoreText:IsShown(), false, "completed feedback remains hidden on refresh")
        if case == 2 then
            bar:ScrollTo(0, true)
            bar:ScrollTo(bar:GetRange())
            Same(Widget.questionScroll:GetVerticalScroll(), 0, "queued wheel motion has not moved the old question yet")
            Check(bar.Animator:GetScript("OnUpdate"), "old question has a pending eased scroll target")
            question[3] = "3"
            Session:Receive(HOST, question)
            Widget:Refresh()
            Same(bar.Animator:GetScript("OnUpdate"), nil, "next question cancels queued motion even at offset zero")
            Same(bar.scrollTarget, nil, "next question drops the old scroll destination")
            Same(Widget.questionScroll:GetVerticalScroll(), 0, "new question starts at its own top")
        end
    end
    Check(Session:Leave(), "pixel audit exits its participant fixture")
    UI:SaveWidgetSettings({ scale = 100 })

    Check(Quiz.Development:ShowGames(), "setup audit populates actual pooled game rows")
    local settings, appearance = Quiz.Store:GetSettings(), Quiz.Store:GetWidgetSettings()
    local sawOddDivider = false
    local function SetupEdges()
        Edges(UI.frame, "setup root")
        Edges(UI.frame.Chrome.Background, "native sliced backdrop bounds")
        Edges(UI.close, "native close control bounds")
        for region in pairs(UI.placements) do
            Edges(region, "authored setup placement")
        end
        for _, row in ipairs({ UI.scaleSlider, UI.fontRow }) do
            Near(
                row:GetHeight(),
                PixelUtil.GetNearestPixelSize(row == UI.scaleSlider and 32 or 26, row:GetEffectiveScale()),
                "inline settings retain their authored height after creation at a different UI scale"
            )
            Edges(row.Label, "inline settings label")
        end
        Near(UI.scaleSlider:GetHeight(), UI.scaleSlider.Slider:GetHeight(), "scale row and native wrapper stay flush")
        Edges(UI.scaleSlider.Slider, "inline slider wrapper")
        Edges(UI.scaleSlider.Value, "inline percentage")
        Edges(UI.fontPicker, "inline font picker")
        Edges(UI.fontPicker.Text, "collapsed font preview")
        Edges(UI.fontPicker.Arrow, "collapsed font arrow")
        Near(
            UI.gameRows[#UI.gameRows]:GetBottom(),
            UI.gamesContent:GetBottom(),
            "declared game-list extent includes the independently snapped final row"
        )
        for _, divider in ipairs({ UI.headerDivider, UI.footerDivider }) do
            Edges(divider, "divider bounds")
            Edges(divider.Left, "left divider half")
            Edges(divider.Right, "right divider half")
            Near(divider.Left:GetRight(), divider.Right:GetLeft(), "divider halves share one exact seam")
            local pixels = divider:GetWidth() * divider:GetEffectiveScale() / PixelUtil.GetPixelToUIUnitFactor()
            sawOddDivider = sawOddDivider or math.floor(pixels + 0.5) % 2 == 1
        end
        for _, tab in pairs(UI.tabs) do
            Edges(tab, "tab bounds")
            Edges(tab.Text, "tab text bounds")
            Edges(tab.highlight, "tapered tab highlight")
        end
        for button in pairs(Quiz.Controls.buttons) do
            Edges(button.Text, "owned setup button text bounds")
        end
        for _, scroll in ipairs({ UI.gamesScroll, UI.boardScroll }) do
            local bar = scroll.ScrollBar
            Same(bar.layoutDepth, 0, "setup refresh completes its nested scrollbar layout batch")
            Edges(bar, "setup scrollbar hit area")
            Edges(bar.Track, "setup scrollbar track")
            if bar:IsShown() then
                Edges(bar.Thumb, "setup scrollbar thumb")
            end
        end
        local left, bottom, width, height = UI.frame:GetScaledRect()
        local _, _, screenWidth, screenHeight = UIParent:GetScaledRect()
        Check(left >= -EPSILON and bottom >= -EPSILON, "setup keeps its lower screen bounds after dragging")
        Check(
            left + width <= screenWidth + EPSILON and bottom + height <= screenHeight + EPSILON,
            "setup keeps its upper screen bounds after dragging"
        )
        Same(
            UI.scaleSlider.Slider.Slider:GetScript("OnValueChanged"),
            UI.scaleSlider.Slider.Slider.templateValueChanged,
            "pixel refresh retains the native slider callback"
        )
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnShow", "OnEnable", "OnDisable" }) do
            Same(
                UI.start:GetScript(event),
                UI.start.templateScripts[event],
                "pixel refresh retains native button scripts"
            )
        end
    end
    for _, display in ipairs(DISPLAYS) do
        local position = UI.position
        Display(display)
        Same(UI.position, position, "display resnapping does not rewrite the normalized setup preference")
        SetupEdges()
        UI.frame:GetScript("OnDragStart")(UI.frame)
        local _, _, screenWidth, screenHeight = UIParent:GetScaledRect()
        local scale = UI.frame:GetEffectiveScale()
        UI.frame.mockCenterX = (screenWidth * 0.73 + 0.37 * PixelUtil.GetPixelToUIUnitFactor()) / scale
        UI.frame.mockCenterY = (screenHeight * 0.28 + 0.61 * PixelUtil.GetPixelToUIUnitFactor()) / scale
        UI.frame:GetScript("OnDragStop")(UI.frame)
        Same(UI.dragging, false, "native drag stop completes the owned layout transition")
        SetupEdges()
        UI.gamesScroll.ScrollBar:ScrollTo(10000, true)
        SetupEdges()
        UI.gamesScroll.ScrollBar:ScrollTo(0, true)
        Quiz.Main:OnEvent("UI_SCALE_CHANGED")
        SetupEdges()
    end
    Check(sawOddDivider, "divider audit includes an odd physical width rather than only symmetric halves")
    Same(Quiz.Store:GetSettings().league, settings.league, "pixel audit does not save host settings")
    Same(Quiz.Store:GetWidgetSettings().scale, appearance.scale, "pixel audit does not save widget scale")
    Same(Quiz.Store:GetWidgetSettings().font, appearance.font, "pixel audit does not save widget font")

    local scroll, content = Quiz.Controls:Scroll(UI.frame, 100, 90)
    PixelUtil.SetPoint(scroll, "TOPLEFT", UI.frame, "TOPLEFT", 0, 0)
    local bar = scroll.ScrollBar
    local pixel = PixelUtil.GetNearestPixelSize(0, scroll:GetEffectiveScale(), 1)
    local nativeRange = scroll.GetVerticalScrollRange
    local reportedRange = pixel
    scroll.GetVerticalScrollRange = function()
        return reportedRange
    end
    local shows, hides = bar.showCalls, bar.hideCalls
    scroll:UpdateScrollChildRect()
    reportedRange = 0
    scroll:UpdateScrollChildRect()
    Same(bar:IsShown(), false, "a transient native one-pixel range cannot invent overflow in explicit content")
    Same(bar.showCalls, shows, "native range noise never flashes a fitting scrollbar")
    Same(bar.hideCalls, hides, "native range noise never repeats a hidden scrollbar hide")
    scroll.GetVerticalScrollRange = nativeRange
    bar:BeginLayout()
    content:SetHeight(scroll:GetHeight() + 200 * pixel)
    Same(bar:IsShown(), false, "intermediate batch dimensions do not show the scrollbar")
    content:SetHeight(scroll:GetHeight())
    bar:EndLayout()
    Same(bar.showCalls, shows, "final fitting layout never exposes temporary overflow")
    content:SetHeight(scroll:GetHeight() + 100.27 * pixel)
    local maximum = 100 * pixel
    Near(bar:GetRange(), maximum, "declared fractional scroll extent floors to the last complete physical pixel")
    for _, target in ipairs({ -20, maximum + 100, maximum * 0.317 }) do
        bar:ScrollTo(target, true)
        local current = scroll:GetVerticalScroll()
        Check(current >= 0 and current <= maximum + EPSILON, "immediate scroll remains clamped")
        Grid(current * scroll:GetEffectiveScale(), "immediate content offset")
        Edges(bar.Thumb, "immediate snapped thumb")
    end
    bar:ScrollTo(maximum * 0.873)
    for _ = 1, 90 do
        local update = bar.Animator:GetScript("OnUpdate")
        if update then
            update(bar.Animator, 0.016)
            Grid(scroll:GetVerticalScroll() * scroll:GetEffectiveScale(), "eased content offset")
            Edges(bar.Thumb, "eased snapped thumb")
        end
    end
    Same(bar.Animator:GetScript("OnUpdate"), nil, "subpixel easing settles without leaving an idle animation")
    Near(
        scroll:GetVerticalScroll(),
        PixelUtil.GetNearestPixelSize(maximum * 0.873, scroll:GetEffectiveScale()),
        "easing reaches its snapped destination"
    )
    bar:GetScript("OnDragStart")(bar)
    Check(bar:GetScript("OnUpdate"), "thumb drag owns a temporary pointer update")
    scroll:SetVerticalScroll(maximum * 0.253)
    Same(bar:GetScript("OnUpdate"), nil, "external scroll cancels the old thumb-drag origin")
    Same(bar.dragPosition, nil, "external scroll clears accumulated drag motion")
    Grid(scroll:GetVerticalScroll() * scroll:GetEffectiveScale(), "external scroll is snapped")
    bar:ScrollTo(maximum)
    Check(bar.Animator:GetScript("OnUpdate"), "reset fixture has an active old easing target")
    bar:BeginLayout()
    scroll:SetVerticalScroll(0)
    bar:EndLayout()
    Same(bar.Animator:GetScript("OnUpdate"), nil, "batched reset cannot resume old easing")
    Same(bar.scrollTarget, nil, "batched reset discards the former target")
    Same(scroll:GetVerticalScroll(), 0, "batched reset remains at the declared origin")
    bar:ScrollTo(maximum)
    content:SetHeight(scroll:GetHeight() + 4.2 * pixel)
    Same(bar.Animator:GetScript("OnUpdate"), nil, "shrinking content cancels an obsolete scroll destination")
    Check(scroll:GetVerticalScroll() <= 4 * pixel + EPSILON, "shrinking content clamps to the new pixel extent")
    scroll:Hide()
    Quiz.Development:HideGames()
    UI.frame:Hide()
    Same(#Test.errors, 0, "visual-stability checks never hit the native error boundary")
    Same(_G.Orbit, nil, "pixel and click behavior stays standalone")
    return assertions
end

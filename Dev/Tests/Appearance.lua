local PACK_ID = "appearance-fixture"
local LEAGUE = "Appearance checks"
local WIDE_FONT = "Quiz test wide font"
local WIDE_PATH = "Interface\\AddOns\\QuizTest\\Wide.ttf"
local LATE_FONT = "Quiz later font"
local LATE_PATH = "Interface\\AddOns\\QuizTest\\Later.ttf"
local CATALOGUE_FONT_COUNT = 150
local CATALOGUE_PREFIX = "Quiz catalogue font "
local EPSILON = 0.000001

return function(Quiz)
    local assertions = 0
    local UI, Widget, Store, Media = Quiz.UI, Quiz.Widget, Quiz.Store, Quiz.Media
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
    local function Click(button)
        Check(button:IsEnabled(), "requested control is enabled")
        button:GetScript("OnClick")(button)
    end
    local function OpenFonts()
        if not UI.fontPicker.Popup or not UI.fontPicker.Popup:IsShown() then
            Click(UI.fontPicker)
        end
        Check(UI.fontPicker.isOpen and UI.fontPicker.Popup:IsShown(), "font picker opens its owned popup")
        return UI.fontPicker.Popup
    end
    local function FindFont(value)
        local popup = OpenFonts()
        popup.Search:SetText(value == "" and Quiz.L.W_WIDGET_FONT_DEFAULT or value)
        for _, row in ipairs(popup.rows) do
            if row:IsShown() and row.value == value then
                return row
            end
        end
    end
    local function PickFont(value)
        local row = FindFont(value)
        Check(row and row:IsEnabled(), "requested SharedMedia font is selectable")
        Click(row)
        Same(UI.fontPicker.Popup:IsShown(), false, "font selection closes the owned popup")
        Same(UI.fontPicker.isOpen, false, "font selection resets the collapsed arrow state")
    end

    Same(_G.Orbit, nil, "widget appearance has no Orbit dependency")
    Check(LibStub("CallbackHandler-1.0"), "real bundled callback library is loaded")
    local library = LibStub("LibSharedMedia-3.0")
    Same(Media.library, library, "font catalogue uses the actual shared library instance")
    Check(#Media:GetFontNames() > 0, "bundled SharedMedia offers native fonts without another addon")
    UI:Toggle()
    Click(UI.tabs.settings)
    Same(UI.tab, "settings", "Settings is a real primary tab")
    Check(UI.pages.settings:IsShown(), "Settings page is visible")
    Check(Widget.frame:IsShown() and Widget.editing, "Settings keeps the live draggable widget preview")
    local tabs = 0
    local previousRight
    for _, name in ipairs({ "play", "host", "scores", "settings" }) do
        local tab = UI.tabs[name]
        Check(tab:GetLeft() >= UI.frame:GetLeft() and tab:GetRight() <= UI.frame:GetRight(), "four tabs fit the dialog")
        if previousRight then
            Check(tab:GetLeft() >= previousRight - EPSILON, "Settings does not overlap an existing tab")
        end
        previousRight, tabs = tab:GetRight(), tabs + 1
    end
    Same(tabs, 4, "all four top-level tabs are available")
    local control, steppers = UI.scaleSlider, UI.scaleSlider.Slider
    local slider = steppers.Slider
    Same(control.template, "EditModeSettingSliderTemplate", "scale uses the native inline Edit Mode setting row")
    Same(steppers.template, "MinimalSliderWithSteppersTemplate", "scale retains Blizzard's native stepper slider")
    Same(slider.template, "MinimalSliderTemplate", "native slider child is preserved")
    Same(control.cbrHandles.unregisterCalls, 1, "standalone row detaches the captured Edit Mode handlers once")
    Check(control.cbrHandles:IsEmpty(), "no captured Blizzard dialog callback remains registered")
    Same(control.Label:GetText(), "Scale", "scale has its concise inline label")
    Same(UI.fontRow.Label:GetText(), "Font", "font has its concise inline label")
    Same(control.Label:GetFontObject(), GameFontHighlight, "inline label uses the requested native font backing")
    Same(control.Value:GetFontObject(), GameFontHighlightSmall, "percentage uses its compact native font")
    Same(control.Value:GetJustifyH(), "RIGHT", "inline percentage is right aligned")
    Same(control.Value:GetJustifyV(), "MIDDLE", "inline percentage is vertically centered")
    for index, component in ipairs({ 1, 0.82, 0, 1 }) do
        Near(select(index, control.Value:GetTextColor()), component, "inline percentage is gold")
    end
    Same(slider:GetMinMaxValues(), 50, "scale minimum is fifty percent")
    Same(select(2, slider:GetMinMaxValues()), 200, "scale maximum is two hundred percent")
    Same(slider:GetValueStep(), 5, "native scale slider advances in five-percent steps")
    Same(slider:GetObeyStepOnDrag(), true, "mouse dragging obeys native step snapping")
    Same(slider.narrationLabelRegion, UI.scaleLabel, "native slider is labelled for narration")
    Same(slider.Thumb.atlas, "Minimal_SliderBar_Button", "native slider keeps its Blizzard thumb art")
    Same(steppers.Back:GetScript("OnClick"), steppers.Back.templateClick, "native decrease handler remains intact")
    Same(
        steppers.Forward:GetScript("OnClick"),
        steppers.Forward.templateClick,
        "native increase handler remains intact"
    )
    Same(
        slider:GetScript("OnValueChanged"),
        slider.templateValueChanged,
        "native value handler owns formatting and dispatch"
    )
    for event, handler in pairs(slider.templateScripts) do
        Same(slider:GetScript(event), handler, "native slider interaction handler is preserved: " .. event)
    end
    Same(UI.fontPicker.template, nil, "font preview uses its own lean button rather than the pack dropdown template")
    Same(UI.fontPicker.Arrow.atlas, "common-dropdown-icon-next", "font picker retains Orbit's native arrow asset")
    Same(UI.fontPicker.Popup, nil, "searchable font popup is allocated only on first open")
    OpenFonts()
    UI.fontPicker:CloseMenu()
    local labels = { Widget.prompt, Widget.scoreText, Widget.packText, Widget.winnerText }
    for _, choice in ipairs(Widget.choices) do
        labels[#labels + 1] = choice.Text
    end
    Same(#labels, 10, "appearance covers the question, pack, winner, score and every reusable answer")
    local nativePath, nativeHeight, nativeFlags = GameFontHighlight:GetFont()
    local function FontIs(path)
        for _, label in ipairs(labels) do
            local actualPath, height, flags = label:GetFont()
            Same(actualPath, path or nativePath, "HUD label uses the selected font or native fallback")
            local expectedHeight = label == Widget.prompt and nativeHeight + 4
                or label == Widget.packText and math.max(8, nativeHeight - 4)
                or label == Widget.winnerText and math.max(8, nativeHeight - 2)
                or nativeHeight
            Same(height, expectedHeight, "font choice preserves each text role's logical size")
            Same(flags, nativeFlags, "font choice preserves native font flags")
            Check(label:GetFontObject() ~= GameFontHighlight, "HUD role uses its own native font object")
            Same(label.fontCalls, nil, "HUD role never assigns its font inline on the rendered FontString")
            local x, y = label:GetShadowOffset()
            local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
            Near(x / pixel, -2, "font retains the two-physical-pixel leftward shadow")
            Near(y / pixel, -2, "font retains the two-physical-pixel downward shadow")
            Same(select(4, label:GetShadowColor()), 1, "font retains its opaque shadow")
        end
        Same(select(1, GameFontHighlight:GetFont()), nativePath, "global native font object is never modified")
    end
    local function StyleSnapshot()
        local snapshot = {}
        for index, label in ipairs(labels) do
            snapshot[index] =
                { color = { label:GetTextColor() }, horizontal = label:GetJustifyH(), vertical = label:GetJustifyV() }
        end
        return snapshot
    end
    local function SameStyle(snapshot)
        for index, label in ipairs(labels) do
            local color = { label:GetTextColor() }
            for component = 1, 4 do
                Near(color[component], snapshot[index].color[component], "font changes preserve current text colors")
            end
            Same(label:GetJustifyH(), snapshot[index].horizontal, "font changes preserve horizontal text alignment")
            Same(label:GetJustifyV(), snapshot[index].vertical, "font changes preserve vertical text alignment")
        end
        Same(Widget.prompt:GetMaxLines(), 0, "question still wraps through unlimited lines")
        Same(Widget.scoreText:GetMaxLines(), 1, "animated score stays on one line")
        for _, choice in ipairs(Widget.choices) do
            Same(choice.Text:GetMaxLines(), 0, "long answer wrapping remains unlimited")
        end
    end
    FontIs(nil)
    Same(slider:GetValue(), 100, "default control value is one hundred percent")
    Same(control.Value:GetText(), "100%", "inline value shows scale as a percentage")
    Same(slider.narrationValueFormatter(), "100%", "native slider narration uses the formatted inline value")
    for _, label in ipairs(steppers.Labels) do
        Same(label:IsShown(), false, "unused native top and range labels stay hidden")
    end
    Click(steppers.Forward)
    Same(Store:GetWidgetSettings().scale, 105, "native forward step persists five percent")
    Near(Widget.frame:GetScale(), 1.05, "scale applies immediately to the entire widget")
    Click(steppers.Back)
    Same(Store:GetWidgetSettings().scale, 100, "native backward step restores five percent")
    slider:GetScript("OnEnter")(slider)
    slider:GetScript("OnMouseDown")(slider)
    Test.DragSlider(slider, 132)
    Same(Store:GetWidgetSettings().scale, 130, "native mouse drag snaps to the nearest supported step")
    Same(control.Value:GetText(), "130%", "native drag immediately refreshes the inline percentage")
    Near(Widget.frame:GetScale(), 1.3, "native drag immediately resizes the Q/A preview")
    slider:GetScript("OnMouseUp")(slider)
    slider:GetScript("OnLeave")(slider)
    Same(next(control.templateCallbackCalls), nil, "native dragging and hovering never reach Blizzard Edit Mode")
    Same(next(steppers.interactionFlags), nil, "native interaction state returns to idle after dragging")
    Test.DragSlider(slider, 100)
    local save, writes = Store.SaveWidgetSettings, 0
    Store.SaveWidgetSettings = function(self, value)
        writes = writes + 1
        return save(self, value)
    end
    Check(save(Store, { scale = 125 }), "external persisted appearance fixture saves")
    UI:RefreshWidgetSettings()
    Same(slider:GetValue(), 125, "programmatic settings load updates the native control")
    Same(writes, 0, "native value callback does not write settings while they are loading")
    control:SetValue(135)
    Same(writes, 0, "guarded outer row SetValue is never mistaken for a user drag")
    Same(Store:GetWidgetSettings().scale, 125, "programmatic inline value changes do not persist")
    UI:RefreshWidgetSettings()
    UI:Refresh()
    Same(writes, 0, "ordinary setup refresh cannot write appearance settings")
    Store.SaveWidgetSettings = save
    UI:SaveWidgetSettings({ scale = 100 })

    Check(
        Quiz:RegisterQuestionPack({
            id = PACK_ID,
            title = "Appearance tests",
            questions = {
                {
                    id = "long-six",
                    prompt = string.rep("Question words ", 10) .. "?",
                    choices = {
                        string.rep("Answer words ", 7) .. "one",
                        string.rep("Answer words ", 7) .. "two",
                        string.rep("Answer words ", 7) .. "three",
                        string.rep("Answer words ", 7) .. "four",
                        string.rep("Answer words ", 7) .. "five",
                        string.rep("Answer words ", 7) .. "six",
                    },
                    correctIndex = 1,
                },
            },
        }),
        "six-choice appearance fixture registers"
    )
    Check(Quiz.Main:Start({ packId = PACK_ID, league = LEAGUE }), "real game starts while Settings is open")
    local game, session = Quiz.Main.game, Quiz.Session.hostSession
    local round, deadline = game.round, game.round.deadline
    Click(Widget.choices[round.correctIndex])
    local answer = round.answers[Test.hostGUID]
    Same(answer.points, 2.5, "appearance fixture starts with an actual timed answer")
    local preferred = Store:GetWidgetPosition()
    local hostSettings = Store:GetSettings()
    local styles = StyleSnapshot()
    local frameCount, fontCount, tickerCount = #Test.frames, Test.fontStringCreations, #Test.tickers
    Test.fontWidths[WIDE_PATH] = 9
    Check(library:Register("font", WIDE_FONT, WIDE_PATH), "real SharedMedia accepts an installed font")
    Check(Media:HasFont(WIDE_FONT), "registered-font callback immediately updates the Settings catalogue")
    PickFont(WIDE_FONT)
    Same(Store:GetWidgetSettings().font, WIDE_FONT, "font choice persists its SharedMedia key")
    FontIs(WIDE_PATH)
    SameStyle(styles)
    Check(Widget.prompt:GetHeight() > 16, "chosen font participates in wrapped question layout")
    local calls = {}
    for index, label in ipairs(labels) do
        calls[index] = { label.fontCalls, label.fontObjectAssignments }
    end
    local function NoFontReset()
        for index, label in ipairs(labels) do
            Same(label.fontCalls, calls[index][1], "unchanged font does not call SetFont again")
            Same(label.fontObjectAssignments, calls[index][2], "scale/refresh does not reset font backing")
        end
    end
    local menuMeasurements, previewFontCalls = UI.fontPicker.Popup.Measure.textCalls, UI.fontPicker.Text.fontCalls
    for _ = 1, 5 do
        UI:Refresh()
        Widget:Refresh()
        Widget:ApplySettings()
    end
    Same(UI.fontPicker.Popup.Measure.textCalls, menuMeasurements, "ordinary refresh never rebuilds the font catalogue")
    Same(UI.fontPicker.Text.fontCalls, previewFontCalls, "ordinary refresh never repaints the collapsed font preview")
    NoFontReset()
    local function Bounds()
        local left, bottom, width, height = Widget.content:GetScaledRect()
        local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
        Check(
            left >= screenLeft - EPSILON and bottom >= screenBottom - EPSILON,
            "scaled HUD respects lower screen bounds"
        )
        Check(left + width <= screenLeft + screenWidth + EPSILON, "scaled HUD respects the right screen bound")
        Check(bottom + height <= screenBottom + screenHeight + EPSILON, "scaled HUD respects the upper screen bound")
        local _, _, _, viewport = Widget.questionScroll:GetScaledRect()
        Check(viewport <= screenHeight * 0.58 + EPSILON, "scaled long question keeps its physical viewport cap")
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        local scale = Widget.timer:GetEffectiveScale()
        for _, region in ipairs({ Widget.content, Widget.scoreText, Widget.editOutline }) do
            local regionLeft, regionBottom, regionWidth, regionHeight = region:GetScaledRect()
            for _, edge in ipairs({ regionLeft, regionBottom, regionLeft + regionWidth, regionBottom + regionHeight }) do
                Near(edge / factor, math.floor(edge / factor + 0.5), "scaled HUD and edit-outline bounds stay on-grid")
            end
        end
        for index, edge in ipairs(Widget.editOutline.edges) do
            local thickness = index <= 2 and edge:GetHeight() or edge:GetWidth()
            Near(thickness * edge:GetEffectiveScale() / factor, 1, "edit-outline strokes remain one physical pixel")
        end
        Near(Widget.timer:GetHeight() * scale / factor, 2, "scaled countdown remains two physical pixels tall")
        Near(
            (Widget.prompt:GetBottom() - Widget.timer:GetTop()) * scale / factor,
            2,
            "scaled prompt keeps its two-pixel timer gap"
        )
        for _, label in ipairs(labels) do
            local x, y = label:GetShadowOffset()
            Near(x * label:GetEffectiveScale() / factor, -2, "all ten text shadows follow combined widget/UI scale")
            Near(y * label:GetEffectiveScale() / factor, -2, "combined scaling retains shadow direction")
        end
        for _, choice in ipairs(Widget.choices) do
            Check(
                choice:GetRight() < Widget.scoreText:GetLeft(),
                "scaled answer hit targets leave the score column clear"
            )
            Check(
                choice.Text:GetHeight() + EPSILON >= choice.Text.lastStringHeightMeasurement.requiredHeight,
                "scaled answer retains every wrapped line"
            )
        end
        local timerLeft, timerBottom, timerWidth, timerHeight = Widget.timer:GetScaledRect()
        for _, edge in ipairs({ timerLeft, timerBottom, timerLeft + timerWidth, timerBottom + timerHeight }) do
            Near(
                edge / factor,
                math.floor(edge / factor + 0.5),
                "scaled countdown edges stay on the physical pixel grid"
            )
        end
    end
    local scales, overflow = 0, false
    for percent = 50, 200, 5 do
        Test.DragSlider(slider, percent)
        scales = scales + 1
        Same(Store:GetWidgetSettings().scale, percent, "every supported five-percent value is reachable")
        Near(Widget.frame:GetScale(), percent / 100, "all supported values scale the entire widget frame")
        Same(control.Value:GetText(), percent .. "%", "inline value label follows every scale step")
        Same(steppers.Back:IsEnabled(), percent > 50, "native back step disables at the minimum")
        Same(steppers.Forward:IsEnabled(), percent < 200, "native forward step disables at the maximum")
        for _, display in ipairs({ { 1920, 1080, 1 }, { 2560, 1440, 0.71 }, { 800, 600, 1.25 } }) do
            Test.physicalWidth, Test.physicalHeight = display[1], display[2]
            UIParent:SetScale(display[3])
            local factor = PixelUtil.GetPixelToUIUnitFactor()
            UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
            for _, position in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 } }) do
                Widget.position = { x = position[1], y = position[2] }
                Widget:OnDisplayChanged()
                Bounds()
                local range = Widget.questionScroll:GetVerticalScrollRange()
                if range > 0 then
                    overflow = true
                    Widget.questionScroll:SetVerticalScroll(range)
                    Bounds()
                    Widget.questionScroll:SetVerticalScroll(0)
                end
            end
        end
        NoFontReset()
        Same(round.answers[Test.hostGUID], answer, "scale never creates a different timed answer")
        Same(round.deadline, deadline, "scale never resets the host clock")
        Same(Quiz.Session.hostSession, session, "scale never changes game membership")
        Near(Store:GetWidgetPosition().x, preferred.x, "scale does not rewrite saved normalized X position")
        Near(Store:GetWidgetPosition().y, preferred.y, "scale does not rewrite saved normalized Y position")
    end
    Same(scales, 31, "all thirty-one supported scale values were exercised")
    Check(overflow, "geometry checks actually exercised scrolled long content")
    Same(#Test.frames, frameCount, "scale/font appearance reuses existing frames")
    Same(Test.fontStringCreations, fontCount, "scale/font appearance reuses all text regions")
    Same(#Test.tickers, tickerCount, "appearance needs no additional timer")
    Same(Store:GetSettings().league, hostSettings.league, "appearance leaves host configuration alone")
    Same(Store:GetSettings().packId, hostSettings.packId, "appearance never changes the selected question pack")
    Test.physicalWidth, Test.physicalHeight = 1920, 768
    UIParent:SetScale(1)
    UIParent:SetSize(1920, 1080)
    Widget.position = { x = 0.5, y = 0.75 }
    Widget:OnDisplayChanged()
    UI:SaveWidgetSettings({ scale = 100 })
    local names = Media:GetFontNames()
    for index = 2, #names do
        Check(names[index - 1] < names[index], "font catalogue remains alphabetically sorted")
    end
    names[1] = "corrupted caller copy"
    Check(Media:GetFontNames()[1] ~= names[1], "font catalogue returns a fresh caller-owned list")
    Check(
        library:SetGlobal("font", library:GetDefault("font")),
        "other addons can configure a SharedMedia font override"
    )
    Same(Media:ResolveFont(WIDE_FONT), WIDE_PATH, "explicit widget key is not replaced by another addon's LSM override")
    library:SetGlobal("font", nil)
    styles = StyleSnapshot()
    UI:SaveWidgetSettings({ font = LATE_FONT })
    FontIs(nil)
    SameStyle(styles)
    Same(Store:GetWidgetSettings().font, LATE_FONT, "missing font key remains saved for later availability")
    local unavailable = FindFont(LATE_FONT)
    Check(
        unavailable and unavailable.SelectedBackground:IsShown() and not unavailable:IsEnabled(),
        "missing font is the selected disabled preview row"
    )
    unavailable:GetScript("OnClick")(unavailable)
    Same(Store:GetWidgetSettings().font, LATE_FONT, "unavailable preview row cannot change the saved preference")
    Check(UI.fontPicker.Popup:IsShown(), "disabled font row does not close the picker")
    Check(UI.widgetSettingsHelp:GetText():find("available", 1, true), "Settings explains the missing-font fallback")
    local revision = Media.revision
    Check(library:Register("font", LATE_FONT, LATE_PATH), "real library registers the previously missing font")
    Check(Media.revision > revision, "font registration advances the catalogue revision")
    FontIs(LATE_PATH)
    SameStyle(styles)
    Same(UI.fontPicker.Popup.Search:GetText(), LATE_FONT, "late registration preserves the active font search")
    Check(unavailable:IsEnabled(), "late registration replaces the unavailable row without another user action")
    Same(unavailable.Text:GetFont(), LATE_PATH, "late registration updates the real preview row font")
    Same(Store:GetWidgetSettings().font, LATE_FONT, "late registration preserves the chosen key")
    revision = Media.revision
    Check(
        library:Register("sound", "Quiz irrelevant sound", "Interface\\AddOns\\QuizTest\\Sound.ogg"),
        "non-font media registers normally"
    )
    Same(Media.revision, revision, "unrelated SharedMedia registrations do not rebuild font consumers")
    for index, failure in ipairs({ true, "throw" }) do
        local name, path = "Quiz broken font " .. index, "Interface\\AddOns\\QuizTest\\Broken" .. index .. ".ttf"
        Test.invalidFonts[path] = failure
        Check(library:Register("font", name, path), "faulty file may still be advertised by an external addon")
        local broken = FindFont(name)
        Check(broken and not broken:IsEnabled(), "a font that fails native SetFont is not offered as a working asset")
        UI:SaveWidgetSettings({ font = name })
        FontIs(nil)
        SameStyle(styles)
        Same(Store:GetWidgetSettings().font, name, "font asset failure does not erase the user's selection")
        local failedCalls = Widget.fontProbe.fontCalls
        for _ = 1, 3 do
            Widget:Refresh()
            UI:Refresh()
        end
        Same(Widget.fontProbe.fontCalls, failedCalls, "normal refresh does not retry a broken external font every tick")
        Test.invalidFonts[path] = nil
        if index == 1 then
            UI:SaveWidgetSettings({ font = name })
        else
            Test.DragSlider(slider, 105)
        end
        FontIs(path)
        SameStyle(styles)
        Check(Widget.fontProbe.fontCalls > failedCalls, "an explicit settings action retries the recovered font asset")
        Same(round.answers[Test.hostGUID], answer, "font retry preserves the existing timed answer object")
        Same(round.deadline, deadline, "font retry does not restart the answer clock")
        Same(Quiz.Session.hostSession, session, "font retry never changes game membership")
        UI:SaveWidgetSettings({ scale = 100 })
    end
    PickFont("")
    FontIs(nil)
    SameStyle(styles)
    do
        local catalogue = {}
        for index = 1, CATALOGUE_FONT_COUNT do
            local name = CATALOGUE_PREFIX
                .. string.format("%03d", index)
                .. (index == CATALOGUE_FONT_COUNT and " [wide]" or "")
            catalogue[index] = name
            Check(library:Register("font", name, WIDE_PATH), "large external font catalogue registers normally")
        end
        local measured = Widget.prompt.stringHeightMeasurements
        PickFont(catalogue[#catalogue])
        Check(
            Widget.prompt.stringHeightMeasurements > measured,
            "clicking an actual font preview immediately remeasures the live question"
        )
        FontIs(WIDE_PATH)
        Same(round.answers[Test.hostGUID], answer, "searchable font selection preserves the active answer")
        Same(round.deadline, deadline, "searchable font selection preserves the live deadline")
        local popup = OpenFonts()
        local search, clear = popup.Search, popup.Search.clearButton
        Same(popup:GetParent(), UIParent, "font popup is not clipped by the setup window")
        Same(popup.owner, UI.fontPicker, "font popup remains owned by its one collapsed control")
        Check(#popup.rows <= 10 and popup.visibleSlots <= 10, "large font catalogues use at most ten preview rows")
        Same(search:GetText(), "", "opening resets the previous search")
        Check(search:HasFocus(), "opening gives the owned search input keyboard focus")
        local selectedVisible = false
        for _, row in ipairs(popup.rows) do
            selectedVisible = selectedVisible or row:IsShown() and row.value == catalogue[#catalogue]
        end
        Check(selectedVisible, "opening scrolls the selected font into the visible preview pool")
        Same(search.template, "SearchBoxTemplate", "font filtering uses the native search input template")
        Check(clear.templateClick, "search-clear button retains its captured native click handler")
        Same(search.Left:IsShown(), false, "owned search strip replaces only native outer search art")
        Same(search.Middle:IsShown(), false, "native middle search art is suppressed")
        Same(search.Right:IsShown(), false, "native right search art is suppressed")
        Same(search.searchIcon.atlas, "common-search-magnifyingglass", "native search icon is retained")
        Same(clear.Icon.atlas, "common-search-clearbutton", "native clear icon is retained")
        local changedCalls = search.templateCalls.OnTextChanged or 0
        search:SetText("qUIz CaTaLoGuE FoNt")
        Same(#popup.filtered, CATALOGUE_FONT_COUNT, "font search is case-insensitive")
        Check(search.templateCalls.OnTextChanged > changedCalls, "filtering retains native text-change behavior")
        Same(search.Instructions:IsShown(), false, "typing hides native search instructions")
        local pooledFrames, pooledFonts = #Test.frames, Test.fontStringCreations
        local rowIdentity = popup.rows[1]
        popup:GetScript("OnMouseWheel")(popup, -10000)
        Same(popup.scrollOffset, #popup.filtered - popup.visibleSlots, "wheel scrolling clamps at the final font")
        Same(popup.rows[popup.visibleSlots].value, catalogue[#catalogue], "last font is reachable through pooled rows")
        search:GetScript("OnMouseWheel")(search, 10000)
        Same(popup.scrollOffset, 0, "wheel input over search clamps back to the first font")
        Same(popup.rows[1], rowIdentity, "scrolling rebinds an existing preview row")
        Same(popup.rows[1].value, catalogue[1], "reused preview row receives its new font key")
        Same(popup.rows[1].Text:GetFont(), WIDE_PATH, "list rows show their actual selected font asset")
        Same(select(2, popup.rows[1].Text:GetFont()), 13, "list previews use the compact Orbit font size")
        search:SetText("[wide]")
        Same(#popup.filtered, 1, "font search treats pattern punctuation literally")
        Same(popup.rows[1].value, catalogue[#catalogue], "literal search keeps the exact matching font")
        popup:Refresh()
        Same(search:GetText(), "[wide]", "catalogue refresh does not discard the user's search")
        search:SetText("%d+")
        Same(#popup.filtered, 0, "pattern-looking text is not evaluated as a Lua search pattern")
        Same(popup.Empty:IsShown(), true, "empty font searches show the concise no-results label")
        for _, row in ipairs(popup.rows) do
            Same(row:IsShown(), false, "no-results search leaves no stale clickable preview row")
            Same(row.value, nil, "hidden no-results rows drop their previous font key")
        end
        local clearCalls, focusLost = clear.templateCalls.OnClick or 0, search.templateCalls.OnEditFocusLost or 0
        Click(clear)
        Same(clear.templateCalls.OnClick, clearCalls + 1, "search clearing still runs the native click handler")
        Check(search.templateCalls.OnEditFocusLost > focusLost, "search clearing retains native focus cleanup")
        Same(search:GetText(), "", "native clear button resets the searchable catalogue")
        Same(search:HasFocus(), true, "owned clear hook restores search focus for popup-local Escape")
        Same(search.Instructions:IsShown(), true, "native clear behavior restores search instructions")
        Same(popup.Empty:IsShown(), false, "clearing a search restores available font previews")
        Same(#Test.frames, pooledFrames, "searching and scrolling allocate no additional preview frames")
        Same(Test.fontStringCreations, pooledFonts, "searching and scrolling reuse font strings")
        Same(popup:GetScript("OnUpdate"), nil, "font popup needs no polling timer")
        local escapeCalls = search.templateCalls.OnEscapePressed or 0
        search:SetFocus()
        search:GetScript("OnEscapePressed")(search)
        Same(search.templateCalls.OnEscapePressed, escapeCalls + 1, "Escape retains native focus cleanup")
        Same(search:HasFocus(), false, "Escape releases font search focus")
        Same(popup:IsShown(), false, "Escape also dismisses the owned font popup")
        Check(UI.frame:IsShown(), "Escape after clearing dismisses only the font popup, not setup")
        Same(popup.events.GLOBAL_MOUSE_DOWN, nil, "closed popup does not keep its outside-click listener")
        OpenFonts()
        search:SetText("catalogue")
        local enterCalls = search.templateCalls.OnEnterPressed or 0
        search:GetScript("OnEnterPressed")(search)
        Same(search.templateCalls.OnEnterPressed, enterCalls + 1, "Enter retains native edit-box behavior")
        Check(popup:IsShown() and search:HasFocus(), "Enter keeps the filtered popup open with local Escape focus")
        Same(search:GetText(), "catalogue", "Enter does not discard the font search")
        search:GetScript("OnEscapePressed")(search)
        Same(popup:IsShown(), false, "Escape following Enter closes the font popup")
        Check(UI.frame:IsShown(), "Escape following Enter leaves setup open")
        local cursorX, cursorY = Test.cursorX, Test.cursorY
        OpenFonts()
        local left, bottom, width, height = popup:GetScaledRect()
        Test.cursorX, Test.cursorY = left + width / 2, bottom + height / 2
        popup:GetScript("OnEvent")(popup, "GLOBAL_MOUSE_DOWN")
        Check(popup:IsShown(), "clicking inside the popup does not dismiss it")
        Test.cursorX, Test.cursorY = -1, -1
        popup:GetScript("OnEvent")(popup, "GLOBAL_MOUSE_DOWN")
        Same(popup:IsShown(), false, "outside mouse input dismisses the popup")
        Same(UI.fontPicker.isOpen, false, "outside dismissal restores the closed arrow state")
        Test.cursorX, Test.cursorY = cursorX, cursorY
        local function GridEdges(region)
            local x, y, w, h = region:GetScaledRect()
            local factor = PixelUtil.GetPixelToUIUnitFactor()
            for _, edge in ipairs({ x, y, x + w, y + h }) do
                Near(edge / factor, math.floor(edge / factor + 0.5), "font popup owns whole-physical-pixel bounds")
            end
        end
        local position = UI.position
        for _, display in ipairs({ { 1920, 1080, 0.61 }, { 2560, 1440, 0.71 }, { 800, 600, 1.25 } }) do
            Test.physicalWidth, Test.physicalHeight = display[1], display[2]
            UIParent:SetScale(display[3])
            local factor = PixelUtil.GetPixelToUIUnitFactor()
            UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
            for _, location in ipairs({ { x = 0, y = 0 }, { x = 1, y = 1 } }) do
                UI.position = location
                Quiz.Main:OnEvent("DISPLAY_SIZE_CHANGED")
                OpenFonts()
                local x, y, w, h = popup:GetScaledRect()
                local sx, sy, sw, sh = UIParent:GetScaledRect()
                Check(x >= sx and y >= sy, "font popup stays within the lower screen edges")
                Check(x + w <= sx + sw and y + h <= sy + sh, "font popup stays within the upper screen edges")
                Near(
                    popup:GetEffectiveScale(),
                    UI.fontPicker:GetEffectiveScale(),
                    "popup follows setup rather than HUD scale"
                )
                for _, region in ipairs({
                    popup,
                    popup.SearchStrip,
                    search,
                    search.Instructions,
                    search.searchIcon,
                    clear,
                    clear.Icon,
                    popup.Content,
                    popup.Empty,
                    UI.fontPicker,
                    UI.fontPicker.Text,
                    UI.fontPicker.Arrow,
                }) do
                    GridEdges(region)
                end
                for _, row in ipairs(popup.rows) do
                    if row:IsShown() then
                        GridEdges(row)
                        GridEdges(row.Text)
                        GridEdges(row.SelectedBackground)
                    end
                end
                for _, event in ipairs({ "OnEnter", "OnMouseDown", "OnMouseUp", "OnLeave" }) do
                    local before = clear.templateCalls[event] or 0
                    clear:GetScript(event)(clear)
                    Same(
                        clear.templateCalls[event],
                        before + 1,
                        "font search preserves native clear-button interaction"
                    )
                    GridEdges(clear.Icon)
                end
            end
        end
        UI.position = position
        Test.physicalWidth, Test.physicalHeight = 1920, 768
        UIParent:SetScale(1)
        UIParent:SetSize(1920, 1080)
        Quiz.Main:OnEvent("DISPLAY_SIZE_CHANGED")
        Same(round.answers[Test.hostGUID], answer, "popup positioning never edits the active answer")
        Same(round.deadline, deadline, "popup interaction never extends the round")
        Same(Quiz.Session.hostSession, session, "popup display changes do not alter session membership")
        PickFont("")
        FontIs(nil)
    end
    OpenFonts()
    UI:SetTab("play")
    Same(UI.fontPicker.Popup:IsShown(), false, "leaving Settings closes its font popup")
    UI:SetTab("settings")
    OpenFonts()
    UI.frame:GetScript("OnDragStart")(UI.frame)
    Same(UI.fontPicker.Popup:IsShown(), false, "dragging setup closes the font popup")
    UI.frame:GetScript("OnDragStop")(UI.frame)
    OpenFonts()
    Quiz.Main:OnEvent("UI_SCALE_CHANGED")
    Same(UI.fontPicker.Popup:IsShown(), false, "display changes close the anchored font popup")
    Test.now = deadline - 2
    Widget:Refresh()
    Near(Widget.timer:GetValue(), 2, "appearance changes have not extended the live answer deadline")
    Click(Widget.choices[6])
    Same(round.answers[Test.hostGUID].choiceIndex, 6, "scaled sixth answer keeps its exact input mapping")
    Test.Advance(2)
    Same(game.state, "results", "normal scoring closes the appearance fixture")
    Check(Widget.scoreAnimation:IsPlaying(), "personal score still animates after scale/font changes")
    PickFont(WIDE_FONT)
    Same(Widget.scoreAnimation:IsPlaying(), false, "changing font cancels rather than replays the same personal result")
    Same(game.completed, 1, "appearance never duplicates a scored question")
    FontIs(WIDE_PATH)
    local _, scoreBottom, _, scoreHeight = Widget.scoreText:GetScaledRect()
    local _, rise = Widget.scoreRise:GetOffset()
    local _, screenBottom, _, screenHeight = UIParent:GetScaledRect()
    Check(
        scoreBottom + scoreHeight + rise * Widget.scoreText:GetEffectiveScale() <= screenBottom + screenHeight + EPSILON,
        "result rise stays screen-aware after appearance changes"
    )
    for _, frame in ipairs(Test.frames) do
        local ancestor = frame
        while ancestor and ancestor ~= UI.frame do
            ancestor = ancestor:GetParent()
        end
        if ancestor then
            for _, label in ipairs(frame.fontStrings or {}) do
                if label ~= UI.fontPicker.Text then
                    Same(label.fontCalls, nil, "HUD appearance never restyles an unrelated setup font")
                end
            end
        end
    end
    Same(UI.fontPicker.Text:GetFont(), WIDE_PATH, "only the collapsed font preview mirrors the selected HUD font")
    OpenFonts()
    UI.frame:Hide()
    Same(UI.fontPicker.Popup:IsShown(), false, "closing setup also closes the font popup")
    Check(Widget.frame:IsShown(), "closing Settings does not dismiss the active game")
    Quiz.Main:Stop()
    Same(#Test.errors, 0, "font/scale settings never reach the global error handler")
    Same(_G.Orbit, nil, "appearance remains independent of Orbit")
    return assertions
end

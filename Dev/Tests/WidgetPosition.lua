local EPSILON = 0.000001
local THRESHOLD_DELTA = 0.0000001
local SCREEN_MARGIN = 12
local HORIZONTAL = { LEFT = 0, RIGHT = 1 }
local VERTICAL = { TOP = 1, BOTTOM = 0 }
local ZONES = {
    { x = 0.1, y = 0.9, horizontal = "LEFT", vertical = "TOP" },
    { x = 0.5, y = 0.9, horizontal = "RIGHT", vertical = "TOP" },
    { x = 0.9, y = 0.9, horizontal = "RIGHT", vertical = "TOP" },
    { x = 0.1, y = 0.1, horizontal = "LEFT", vertical = "BOTTOM" },
    { x = 0.5, y = 0.1, horizontal = "RIGHT", vertical = "BOTTOM" },
    { x = 0.9, y = 0.1, horizontal = "RIGHT", vertical = "BOTTOM" },
}
local DISPLAYS = { { 1920, 1080, 1 }, { 2560, 1440, 0.71 }, { 1600, 900, 1.25 } }
local SCALES = { 50, 100, 175 }
local SHORT_PROMPT = "Which answer comes first?"
local LONG_PROMPT = string.rep("A longer question should grow away from the selected screen edge. ", 7)
local SHORT_CHOICES = { "First answer", "Second answer", "Third answer", "Fourth answer" }
local LONG_CHOICES = {
    "First answer with enough detail to occupy multiple lines in the visible question column.",
    "Second answer with enough detail to occupy multiple lines in the visible question column.",
    "Third answer with enough detail to occupy multiple lines in the visible question column.",
    "Fourth answer with enough detail to occupy multiple lines in the visible question column.",
    "Fifth answer with enough detail to occupy multiple lines in the visible question column.",
    "Sixth answer with enough detail to occupy multiple lines in the visible question column.",
}

return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local Widget, UI, Store, Session = Quiz.Widget, Games.UI, Quiz.Store, Quiz.Session
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
    local function PixelNear(actual, expected, message)
        Check(
            math.abs(actual - expected) <= PixelUtil.GetPixelToUIUnitFactor() + EPSILON,
            message .. ": " .. actual .. " ~= " .. expected
        )
    end
    local function Rect(region)
        return { region:GetScaledRect() }
    end
    local function Point(rect, horizontal, vertical)
        return rect[1] + rect[3] * HORIZONTAL[horizontal], rect[2] + rect[4] * VERTICAL[vertical]
    end
    local function SamePoint(rect, expected, horizontal, vertical, message)
        local x, y = Point(rect, horizontal, vertical)
        PixelNear(x, expected[1], message .. " horizontal edge")
        PixelNear(y, expected[2], message .. " vertical edge")
    end
    local function SameRect(actual, expected, message)
        for index = 1, 4 do
            PixelNear(actual[index], expected[index], message .. " component " .. index)
        end
    end
    local function Zone(x, y)
        return x < 0.5 and "LEFT" or "RIGHT", y >= 0.5 and "TOP" or "BOTTOM"
    end

    for _, entry in ipairs({
        { 0.4, "LEFT" },
        { 0.5 - THRESHOLD_DELTA, "LEFT" },
        { 0.5, "RIGHT" },
        { 0.5 + THRESHOLD_DELTA, "RIGHT" },
        { 0.6, "RIGHT" },
    }) do
        for _, y in ipairs({ 0.5 - THRESHOLD_DELTA, 0.5, 0.5 + THRESHOLD_DELTA }) do
            local layout = Widget:ResolveLayout(entry[1], y, 1600, 1000, 240, 180)
            local vertical = y >= 0.5 and "TOP" or "BOTTOM"
            Same(layout.horizontal, entry[2], "horizontal growth uses only the two screen halves")
            Same(layout.vertical, vertical, "the exact vertical midpoint belongs to top growth")
            Same(layout.point, vertical .. entry[2], "layout names its true edge")
        end
    end
    for _, zone in ipairs(ZONES) do
        for _, size in ipairs({ { 140, 80 }, { 260, 300 }, { 311, 211 } }) do
            local layout = Widget:ResolveLayout(zone.x, zone.y, 1600, 1000, size[1], size[2])
            Near(layout.left + size[1] * HORIZONTAL[zone.horizontal], zone.x * 1600, "X is the visible growth edge")
            Near(layout.bottom + size[2] * VERTICAL[zone.vertical], zone.y * 1000, "Y is the visible growth edge")
            Near(layout.x, zone.x, "content dimensions cannot rewrite an unclamped normalized X")
            Near(layout.y, zone.y, "content dimensions cannot rewrite an unclamped normalized Y")
        end
    end
    for _, x in ipairs({ 0, 1 }) do
        for _, y in ipairs({ 0, 1 }) do
            local layout = Widget:ResolveLayout(x, y, 1600, 1000, 380, 300)
            Near(layout.x * 1600, layout.left + 380 * HORIZONTAL[layout.horizontal], "clamping returns the true X edge")
            Near(layout.y * 1000, layout.bottom + 300 * VERTICAL[layout.vertical], "clamping returns the true Y edge")
        end
    end

    UI:Show("settings")
    local rules = Quiz.Rules.Normalize()
    local view = {
        role = "participant",
        state = "open",
        hostName = "Positionhost-TestRealm",
        session = "position.1",
        id = "position-0",
        cycle = 1,
        packTitle = "Position regression",
        prompt = SHORT_PROMPT,
        choices = SHORT_CHOICES,
        duration = 15,
        deadline = GetTime() + 3600,
        score = 12.3,
        rules = rules,
        rulesKey = Quiz.Rules.Encode(rules),
    }
    local originalClient, originalView, originalSubmit = Session.client, Session.view, Session.SubmitAnswer
    Session.client, Session.view = { name = view.hostName, session = view.session }, view
    local submitted = {}
    Session.SubmitAnswer = function(_, answer)
        submitted[#submitted + 1] = answer
        view.selected = answer
        return true
    end
    Widget:Refresh()
    Same(Widget.dragHandle:GetParent(), Widget.questionContent, "question drag handle belongs to the scrolling content")
    Same(Widget.dragHandle.allPoints, Widget.prompt, "question drag handle follows only the wrapped prompt")
    Same(Widget.dragHandle.drag, "LeftButton", "question drag handle owns the left-button drag gesture")
    Check(Widget.dragHandle.mouse, "opening setup enables the question drag handle")
    for _, region in ipairs({ Widget.frame, Widget.content, Widget.questionScroll, Widget.scoreRegion }) do
        Same(region.drag, nil, "the Quiz root and broad surfaces own no drag registration")
        Same(region:GetScript("OnDragStart"), nil, "the Quiz root and broad surfaces cannot start movement")
        Same(region:GetScript("OnDragStop"), nil, "the Quiz root and broad surfaces cannot stop movement")
    end
    Check(not Widget.content.mouse and not Widget.questionScroll.mouse, "broad Quiz surfaces remain mouse-disabled")
    Check(Widget.scoreRegion.mouse, "active permanent score enables only its owned hover region")
    Same(Widget.scoreRegion:GetScript("OnMouseDown"), nil, "score hover owns no mouse-down drag path")
    Same(Widget.scoreRegion:GetScript("OnMouseUp"), nil, "score hover owns no mouse-up drag path")
    Same(Widget.scoreValueText:GetText(), "12.3", "position fixture keeps its permanent total visible")
    for index, choice in ipairs(Widget.choices) do
        Same(choice.drag, nil, "answer rows own no drag registration " .. index)
        Same(choice:GetScript("OnDragStart"), nil, "answer rows cannot start movement " .. index)
        Same(choice:GetScript("OnDragStop"), nil, "answer rows cannot stop movement " .. index)
    end
    local scrollBar = Widget.questionScroll.ScrollBar
    local nativeSave, nativeStart, nativeStop, nativeRefresh, nativeBeginLayout =
        Store.SaveWidgetPosition,
        Widget.frame.StartMoving,
        Widget.frame.StopMovingOrSizing,
        Widget.Refresh,
        scrollBar.BeginLayout
    local saves, starts, stops, refreshes, layoutPasses, sequence = {}, 0, 0, 0, 0, 0
    Store.SaveWidgetPosition = function(self, x, y)
        saves[#saves + 1] = { x, y }
        return nativeSave(self, x, y)
    end
    Widget.frame.StartMoving = function(self)
        starts = starts + 1
        return nativeStart(self)
    end
    Widget.frame.StopMovingOrSizing = function(self)
        stops = stops + 1
        return nativeStop(self)
    end
    Widget.Refresh = function(self, ...)
        refreshes = refreshes + 1
        return nativeRefresh(self, ...)
    end
    scrollBar.BeginLayout = function(self, ...)
        layoutPasses = layoutPasses + 1
        return nativeBeginLayout(self, ...)
    end
    local function SaveSnapshot()
        local saved = Store:GetWidgetPosition()
        return { count = #saves, table = Store.db.widgetPosition, x = saved.x, y = saved.y }
    end
    local function NoSave(before, message)
        Same(#saves, before.count, message .. " saves no position")
        Same(Store.db.widgetPosition, before.table, message .. " retains the saved position table")
        local saved = Store:GetWidgetPosition()
        Near(saved.x, before.x, message .. " retains saved X")
        Near(saved.y, before.y, message .. " retains saved Y")
    end
    local function RootMatchesContent()
        local root, content = Rect(Widget.frame), Rect(Widget.content)
        for index = 1, 4 do
            Near(root[index], content[index], "the resting drag root matches the visible rectangle")
        end
        Same(Widget.frame.point[1], "BOTTOMLEFT", "the visible root uses a snapped bottom-left anchor")
        Same(Widget.frame.point[2], UIParent, "the root remains attached to UIParent")
        local pixel = PixelUtil.GetPixelToUIUnitFactor()
        for _, edge in ipairs({ root[1], root[2], root[1] + root[3], root[2] + root[4] }) do
            Near(edge / pixel, math.floor(edge / pixel + 0.5), "resting root edges stay on the physical pixel grid")
        end
    end
    local function Content(long)
        sequence = sequence + 1
        view.id = "position-" .. sequence
        view.prompt = long and LONG_PROMPT or SHORT_PROMPT
        view.choices = long and LONG_CHOICES or SHORT_CHOICES
        Widget:Refresh()
    end
    local function Seed(zone, long)
        Check(not Widget.dragging, "a new fixture starts outside native dragging")
        Check(nativeSave(Store, zone.x, zone.y), "fixture stores a valid corner/edge")
        Widget.position = Store:GetWidgetPosition()
        Content(long)
        Same(Widget.layout.horizontal, zone.horizontal, "saved horizontal growth uses the selected zone")
        Same(Widget.layout.vertical, zone.vertical, "saved vertical growth uses the selected zone")
        RootMatchesContent()
    end
    local function Configure(display, percent)
        local before = SaveSnapshot()
        Test.physicalWidth, Test.physicalHeight = display[1], display[2]
        UIParent:SetScale(display[3])
        local pixel = PixelUtil.GetPixelToUIUnitFactor()
        UIParent:SetSize(display[1] * pixel / display[3], display[2] * pixel / display[3])
        Check(Store:SaveWidgetSettings({ scale = percent }), "fixture stores a supported widget scale")
        Widget:ApplySettings()
        Widget:OnDisplayChanged()
        NoSave(before, "non-drag appearance/display reflow")
        RootMatchesContent()
    end
    local function Ordering()
        SameRect(Rect(Widget.dragHandle), Rect(Widget.prompt), "drag handle follows the wrapped question only")
        Check(Widget.packText:GetBottom() >= Widget.prompt:GetTop() - EPSILON, "pack title remains above the prompt")
        Check(Widget.prompt:GetBottom() >= Widget.timer:GetTop() - EPSILON, "the timer remains below the prompt")
        Check(
            Widget.dragHandle:GetBottom() >= Widget.timer:GetTop() - EPSILON,
            "question drag handle ends above the timer"
        )
        local previous = Widget.timer:GetBottom()
        for index = 1, #view.choices do
            local choice = Widget.choices[index]
            Check(previous >= choice:GetTop() - EPSILON, "answers retain their original downward order")
            Same(choice.Text:GetText(), view.choices[index], "growth does not reorder answer values")
            Same(choice.Text:GetJustifyH(), "LEFT", "answers stay left aligned in every growth zone")
            previous = choice:GetBottom()
        end
    end
    local function MoveVisibleCenter(x, y)
        local content, root, screen = Rect(Widget.content), Rect(Widget.frame), Rect(UIParent)
        local deltaX = screen[1] + x * screen[3] - content[1] - content[3] / 2
        local deltaY = screen[2] + y * screen[4] - content[2] - content[4] / 2
        local scale = Widget.frame:GetEffectiveScale()
        Widget.frame.mockCenterX = (root[1] + root[3] / 2 + deltaX) / scale
        Widget.frame.mockCenterY = (root[2] + root[4] / 2 + deltaY) / scale
    end
    local function SafeReleaseCenter(zone)
        local content, screen = Rect(Widget.content), Rect(UIParent)
        local margin = SCREEN_MARGIN * Widget.frame:GetEffectiveScale() + PixelUtil.GetPixelToUIUnitFactor()
        local minimumX = (content[3] / 2 + margin) / screen[3]
        local minimumY = (content[4] / 2 + margin) / screen[4]
        local left = math.max(0.25, minimumX)
        local lower = math.max(0.25, minimumY)
        Check(left < 0.5 and lower < 0.5, "release fixture fits its requested screen zone without clamping")
        return zone.x == 0.5 and 0.5 or zone.horizontal == "LEFT" and left or 1 - left,
            zone.vertical == "TOP" and 1 - lower or lower
    end
    local function Start()
        local count = starts
        Widget.dragHandle:GetScript("OnDragStart")(Widget.dragHandle)
        Same(starts, count + 1, "the first native drag event starts moving once")
        Check(Widget.dragging and Widget.frame.moving, "native dragging is active")
        Widget.dragHandle:GetScript("OnDragStart")(Widget.dragHandle)
        Same(starts, count + 1, "a duplicate drag event cannot restart native movement")
    end
    local function Drop(message, preserve)
        local released, screen = Rect(Widget.content), Rect(UIParent)
        local before, nativeStops, nativeRefreshes, nativeLayoutPasses = #saves, stops, refreshes, layoutPasses
        local scorePlays, winnerPlays, soundCalls =
            Widget.scoreAnimation.playCalls, Widget.winnerAnimation.playCalls, #Test.soundCalls
        local horizontal, vertical = Zone(
            (released[1] + released[3] / 2 - screen[1]) / screen[3],
            (released[2] + released[4] / 2 - screen[2]) / screen[4]
        )
        Widget.dragHandle:GetScript("OnDragStop")(Widget.dragHandle)
        Same(stops, nativeStops + 1, message .. " stops native movement once")
        Same(#saves, before + 1, message .. " saves exactly once")
        Same(refreshes, nativeRefreshes + 1, message .. " refreshes the panel exactly once")
        Same(layoutPasses, nativeLayoutPasses + 1, message .. " rerenders from the released edge exactly once")
        Same(Widget.scoreAnimation.playCalls, scorePlays, message .. " cannot replay score feedback")
        Same(Widget.winnerAnimation.playCalls, winnerPlays, message .. " cannot replay winner feedback")
        Same(#Test.soundCalls, soundCalls, message .. " cannot replay streak feedback")
        Check(not Widget.dragging and not Widget.frame.moving, message .. " clears drag state")
        Same(Widget.layout.horizontal, horizontal, message .. " classifies the released visible centre horizontally")
        Same(Widget.layout.vertical, vertical, message .. " classifies the released visible centre vertically")
        local actual = Rect(Widget.content)
        if preserve then
            SameRect(actual, released, message .. " cannot jump on release")
        end
        Check(actual[1] >= screen[1] and actual[2] >= screen[2], message .. " respects lower screen bounds")
        Check(actual[1] + actual[3] <= screen[1] + screen[3] + EPSILON, message .. " respects right screen bounds")
        Check(actual[2] + actual[4] <= screen[2] + screen[4] + EPSILON, message .. " respects upper screen bounds")
        local x, y = Point(actual, horizontal, vertical)
        local saved = Store:GetWidgetPosition()
        PixelNear(saved.x * screen[3] + screen[1], x, message .. " persists the true selected X edge")
        PixelNear(saved.y * screen[4] + screen[2], y, message .. " persists the true selected Y edge")
        RootMatchesContent()
        local snapshot = SaveSnapshot()
        Widget:StopDrag()
        Widget:Refresh()
        NoSave(snapshot, message .. " repeated stop and refresh")
        Same(stops, nativeStops + 1, message .. " does not stop native movement twice")
    end

    Widget.scoreRegion:GetScript("OnEnter")(Widget.scoreRegion)
    Check(Quiz.ScoreTooltip:IsOwned(Widget.scoreRegion), "score hover owns its private tooltip before a drag")
    Same(Session.standingsVisible, true, "score hover enables standings before a drag")
    Start()
    Same(Widget.scoreRegion.mouse, false, "drag start immediately disables score hover handling")
    Check(not Quiz.ScoreTooltip:IsOwned(Widget.scoreRegion), "drag start closes the private score tooltip")
    Same(Session.standingsVisible, false, "drag start cancels demand-driven standings")
    Check(Widget.scoreValueText:IsShown(), "dragging never hides the permanent score")
    Same(Widget.scoreValueText:GetText(), "12.3", "dragging never changes the permanent total")
    Drop("score-hover drag", true)
    Check(Widget.scoreRegion.mouse, "drag release restores active score hover handling")
    Same(Widget.scoreValueText:GetAlpha(), 1, "drag release leaves the permanent score fully opaque")
    Test.now = Widget.suppressClickUntil + 0.001

    local answerSave = SaveSnapshot()
    local answerStarts, answerSubmissions = starts, #submitted
    local answer = Widget.choices[1]
    answer:GetScript("OnMouseDown")(answer, "LeftButton")
    answer:GetScript("OnMouseUp")(answer, "LeftButton")
    answer:GetScript("OnClick")(answer, "LeftButton")
    Same(starts, answerStarts, "clicking an answer in edit mode cannot start HUD movement")
    Check(not Widget.dragging and not Widget.frame.moving, "answer interaction leaves the question stationary")
    Same(#submitted, answerSubmissions + 1, "answer interaction remains available in edit mode")
    Same(submitted[#submitted], 1, "edit-mode answer interaction keeps its original index")
    NoSave(answerSave, "answer interaction")
    view.selected = nil
    Widget:Refresh()

    Configure({ 2560, 1440, 0.8 }, 100)
    for _, zone in ipairs(ZONES) do
        Configure({ 2560, 1440, 0.8 }, 100)
        Seed(zone, false)
        local before, saved = Rect(Widget.content), SaveSnapshot()
        local fixed = { Point(before, zone.horizontal, zone.vertical) }
        Content(true)
        Check(Widget.content:GetHeight() > before[4] / Widget.content:GetEffectiveScale(), "long content really grows")
        SamePoint(
            Rect(Widget.content),
            fixed,
            zone.horizontal,
            zone.vertical,
            "content growth retains the visible anchor"
        )
        NoSave(saved, "content growth")
        RootMatchesContent()
        Ordering()
        for _, percent in ipairs({ 75, 150, 200, 100 }) do
            Configure({ 2560, 1440, 0.8 }, percent)
            SamePoint(
                Rect(Widget.content),
                fixed,
                zone.horizontal,
                zone.vertical,
                "scale growth retains the visible anchor"
            )
            NoSave(saved, "scale growth")
            Ordering()
        end
        Content(false)
        SamePoint(
            Rect(Widget.content),
            fixed,
            zone.horizontal,
            zone.vertical,
            "shrinking content retains the visible anchor"
        )
        NoSave(saved, "content shrink")
    end

    for _, display in ipairs(DISPLAYS) do
        for _, percent in ipairs(SCALES) do
            Configure(display, percent)
            for _, zone in ipairs(ZONES) do
                Seed(ZONES[2], false)
                local before = SaveSnapshot()
                Start()
                MoveVisibleCenter(SafeReleaseCenter(zone))
                local root = Rect(Widget.frame)
                local sizeCalls, pointCalls, clearCalls =
                    Widget.frame.sizeCalls, Widget.frame.setPointCalls, Widget.frame.clearPointCalls
                Widget:Refresh()
                Widget:ApplyPosition()
                SameRect(Rect(Widget.frame), root, "refresh cannot alter the root controlled by native dragging")
                Same(Widget.frame.sizeCalls, sizeCalls, "dragging never resizes its root")
                Same(Widget.frame.setPointCalls, pointCalls, "dragging never reanchors its root")
                Same(Widget.frame.clearPointCalls, clearCalls, "dragging never clears its root's native anchors")
                NoSave(before, "native drag and refresh")
                Drop(zone.vertical .. zone.horizontal .. " scaled drop", true)
                Ordering()
            end
        end
    end

    Configure({ 2560, 1440, 0.8 }, 100)
    for _, zone in ipairs(ZONES) do
        Seed(zone, false)
        local before = SaveSnapshot()
        Start()
        local root = Rect(Widget.frame)
        local pixel, scale = PixelUtil.GetPixelToUIUnitFactor(), Widget.frame:GetEffectiveScale()
        Widget.frame.mockCenterX = (root[1] + root[3] / 2 + 17 * pixel) / scale
        Widget.frame.mockCenterY = (root[2] + root[4] / 2 + 13 * pixel) / scale
        root = Rect(Widget.frame)
        local fixed = { Point(Rect(Widget.content), zone.horizontal, zone.vertical) }
        local sizeCalls, pointCalls, clearCalls =
            Widget.frame.sizeCalls, Widget.frame.setPointCalls, Widget.frame.clearPointCalls
        Content(true)
        SameRect(Rect(Widget.frame), root, "in-drag question growth preserves native root geometry")
        Same(Widget.frame.sizeCalls, sizeCalls, "in-drag question growth cannot resize the moving root")
        Same(Widget.frame.setPointCalls, pointCalls, "in-drag question growth cannot move the native root")
        Same(Widget.frame.clearPointCalls, clearCalls, "in-drag question growth cannot clear native anchors")
        SamePoint(
            Rect(Widget.content),
            fixed,
            zone.horizontal,
            zone.vertical,
            "in-drag reflow retains the old growth edge"
        )
        Check(Rect(Widget.content)[4] > root[4], "in-drag fixture has a larger visible rectangle than its moving root")
        NoSave(before, "in-drag question growth")
        Ordering()
        Drop("reflowed " .. zone.vertical .. zone.horizontal .. " drop", true)
    end

    for _, center in ipairs({ { -0.1, -0.1 }, { 1.1, 1.1 } }) do
        Seed(ZONES[2], false)
        Start()
        MoveVisibleCenter(center[1], center[2])
        Drop("out-of-bounds release", false)
    end

    Configure({ 2560, 1440, 0.8 }, 100)
    Seed(ZONES[2], false)
    local scorePlays, winnerPlays, soundCalls =
        Widget.scoreAnimation.playCalls, Widget.winnerAnimation.playCalls, #Test.soundCalls
    view.id = "position-feedback"
    view.state = "results"
    view.correctIndex = 1
    view.selected = 1
    view.points = 1
    view.fastestName = "Fastest-TestRealm"
    view.fastestElapsed = 0.25
    view.streakMilestones = { { name = "Streak-TestRealm", streak = 5 } }
    Widget:Refresh()
    Same(Widget.scoreAnimation.playCalls, scorePlays + 1, "confirmed score feedback starts before dragging")
    Same(Widget.scoreValueText:GetText(), "12.3", "round feedback overlays rather than replaces the permanent total")
    Near(Widget.scoreValueText:GetAlpha(), 0.35, "round feedback temporarily dims the permanent total")
    Same(Widget.winnerAnimation.playCalls, winnerPlays + 1, "confirmed winner feedback starts before dragging")
    Same(#Test.soundCalls, soundCalls + 1, "confirmed streak feedback starts before dragging")
    Start()
    MoveVisibleCenter(0.75, 0.25)
    Drop("confirmed-feedback drop", true)
    Check(Widget.scoreValueText:IsShown(), "feedback drag keeps the permanent total visible")
    Same(Widget.scoreValueText:GetText(), "12.3", "feedback drag preserves the permanent total")
    Same(Widget.scoreValueText:GetAlpha(), 1, "cancelling feedback through drag restores total opacity")
    view.id = "position-feedback-next"
    view.state = "open"
    view.correctIndex = nil
    view.selected = nil
    view.points = nil
    view.fastestName = nil
    view.fastestElapsed = nil
    view.streakMilestones = nil
    view.deadline = GetTime() + 3600
    Widget:Refresh()

    for _, cleanup in ipairs({
        {
            "HUD hide",
            function()
                Widget.frame:Hide()
            end,
        },
        {
            "setup close",
            function()
                UI.frame:Hide()
            end,
        },
        {
            "display event",
            function()
                Games.Main:OnEvent("DISPLAY_SIZE_CHANGED")
            end,
        },
        {
            "UI scale event",
            function()
                Games.Main:OnEvent("UI_SCALE_CHANGED")
            end,
        },
        {
            "widget scale change",
            function()
                Check(Store:SaveWidgetSettings({ scale = 125 }), "scale change stores its independent preference")
                Widget:ApplySettings()
            end,
        },
    }) do
        UI:Show("settings")
        Configure({ 1920, 1080, 1 }, 100)
        Seed(ZONES[2], false)
        local before, nativeStops, submittedCount = #saves, stops, #submitted
        Widget.choices[1]:GetScript("OnMouseDown")(Widget.choices[1], "LeftButton")
        Same(Widget.choices[1].pressed, true, "cleanup fixture starts with pressed answer feedback")
        Start()
        Same(Widget.choices[1].pressed, false, "drag start releases answer press feedback")
        MoveVisibleCenter(0.5, 0.5)
        Widget:Submit(2)
        Same(#submitted, submittedCount, "an active drag cannot submit an answer")
        cleanup[2]()
        Check(not Widget.dragging and not Widget.frame.moving, cleanup[1] .. " ends native dragging")
        Same(stops, nativeStops + 1, cleanup[1] .. " stops native movement exactly once")
        Same(#saves, before + 1, cleanup[1] .. " saves one released position")
        Check(Widget.suppressClickUntil > GetTime(), cleanup[1] .. " installs post-drop click suppression")
        Widget:Submit(2)
        Same(#submitted, submittedCount, cleanup[1] .. " suppresses the release click")
        Test.now = Widget.suppressClickUntil
        Widget:Submit(2)
        Same(#submitted, submittedCount, cleanup[1] .. " includes the exact suppression boundary")
        Test.now = Widget.suppressClickUntil + 0.001
        Widget:Submit(2)
        Same(#submitted, submittedCount + 1, cleanup[1] .. " permits a later intentional answer")
        Same(submitted[#submitted], 2, cleanup[1] .. " retains the answer's original index")
        local saved = SaveSnapshot()
        Widget:StopDrag()
        NoSave(saved, cleanup[1] .. " repeated drag cleanup")
        Same(stops, nativeStops + 1, cleanup[1] .. " never repeats native stop")
    end
    UI.frame:Hide()
    Check(not Widget.dragHandle.mouse, "closing setup disables the question drag handle")
    Check(not Widget.content.mouse and not Widget.questionScroll.mouse, "closing setup leaves broad surfaces disabled")
    local startCount, before = starts, SaveSnapshot()
    Widget:StartDrag()
    Same(starts, startCount, "a locked HUD never starts native movement")
    Check(not Widget.dragging, "dragging remains disabled when setup is closed")
    NoSave(before, "a refused drag")
    Store.SaveWidgetPosition = nativeSave
    Widget.frame.StartMoving, Widget.frame.StopMovingOrSizing = nativeStart, nativeStop
    Widget.Refresh, scrollBar.BeginLayout = nativeRefresh, nativeBeginLayout
    Session.client, Session.view, Session.SubmitAnswer = originalClient, originalView, originalSubmit
    Widget:Refresh()
    Same(#Test.errors, 0, "growth and native drag lifecycles produce no captured errors")
    return assertions
end

local PACK_ID = "hud-streaks"
local PEER = "Another-TestRealm"
local HOST = "Toasthost-OtherRealm"
local SESSION_ID = "toast-session.1"
local EPSILON = 0.000001
local TOAST_SECONDS = 3.2
local BURST_DROP_PIXELS = 4
local BURST_SCALE = 0.8
local DISPLAY_MODES = { { 1920, 1080, 0.71 }, { 1601, 901, 0.83 }, { 800, 600, 1.25 }, { 480, 320, 0.71 } }
local ANCHOR_COORDINATES = { 0.1, 0.5, 0.9 }
local SOUND_FILES = {
    [5] = "dominating.mp3",
    [6] = "ownage.mp3",
    [7] = "rampage.mp3",
    [8] = "wicked-sick.mp3",
    [9] = "holyshit.mp3",
    [10] = "godlike.mp3",
}
local GEOMETRY_CALLS = { "setPointCalls", "clearPointCalls", "sizeCalls", "stringHeightMeasurements" }

return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local Main, Session, Widget, Toasts = Games.Main, Quiz.Session, Quiz.Widget, Quiz.StreakToasts
    local rules = assert(Quiz.Rules.Normalize({ streakBonusPerCorrect = 0, streakBonusMax = 0 }))
    local rulesKey = Quiz.Rules.Encode(rules)
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
    local function Copy(source)
        local result = {}
        for key, value in pairs(source) do
            result[key] = value
        end
        return result
    end
    local function Hidden(message)
        Same(Toasts.frame:IsShown(), false, message)
        Same(Toasts.animation:IsPlaying(), false, message .. " has no animation")
        Same(Toasts.soundHandle, nil, message .. " has no owned voice")
        Same(Toasts.queueCount, 0, message .. " has no queued voice")
    end
    local function Drain()
        for _ = 1, 34 do
            if not Toasts.active then
                break
            end
            Test.AdvanceAnimations(TOAST_SECONDS)
        end
        Hidden("completed toast queue stays hidden")
    end
    local function Snapshot()
        local regions = {
            Widget.content,
            Widget.questionScroll,
            Widget.questionContent,
            Widget.packText,
            Widget.prompt,
            Widget.timer,
            Widget.winnerText,
            Toasts.frame,
            Toasts.nameText,
            Toasts.captionText,
        }
        for _, choice in ipairs(Widget.choices) do
            regions[#regions + 1], regions[#regions + 2] = choice, choice.Text
        end
        local snapshot = { regions = {}, frames = #Test.frames, animations = Test.animationCreations }
        for _, region in ipairs(regions) do
            local before = { rect = { region:GetScaledRect() } }
            for _, key in ipairs(GEOMETRY_CALLS) do
                before[key] = region[key]
            end
            snapshot.regions[region] = before
        end
        return snapshot
    end
    local function Stable(snapshot)
        Same(#Test.frames, snapshot.frames, "announcements reuse all frames")
        Same(Test.animationCreations, snapshot.animations, "announcements reuse native animation objects")
        for region, before in pairs(snapshot.regions) do
            for _, key in ipairs(GEOMETRY_CALLS) do
                Same(region[key], before[key], "revealing a toast leaves QA geometry unchanged: " .. key)
            end
            for index, value in ipairs({ region:GetScaledRect() }) do
                Near(value, before.rect[index], "revealing a toast cannot shift any QA region")
            end
        end
    end
    local function Bounds()
        Check(Toasts.frame:GetTop() < Widget.winnerText:GetBottom(), "toast belongs below the winner popup")
        Check(
            Toasts.frame:GetTop() < Widget.questionScroll:GetBottom(),
            "toast does not cover the scrollable answer viewport"
        )
        Near(Toasts.frame:GetBottom(), Widget.content:GetBottom(), "toast ends at the reserved HUD bottom")
        Near(Toasts.frame:GetLeft(), Widget.content:GetLeft(), "toast shares the HUD left edge")
        Near(Toasts.frame:GetRight(), Widget.content:GetRight(), "toast shares the HUD right edge")
        local left, bottom, width, height = Widget.content:GetScaledRect()
        local toastLeft, toastBottom, toastWidth, toastHeight = Toasts.frame:GetScaledRect()
        local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
        local physicalPixel = PixelUtil.GetPixelToUIUnitFactor()
        for _, art in ipairs({ Toasts.glow, Toasts.sweep }) do
            local artLeft, artBottom, artWidth, artHeight = art:GetScaledRect()
            Check(
                artLeft >= left - EPSILON and artBottom >= bottom - BURST_DROP_PIXELS * physicalPixel - EPSILON,
                "lowered toast art overhang stays within its authored drop"
            )
            Check(artLeft + artWidth <= left + width + EPSILON, "lowered toast art fits the HUD's right edge")
            Check(artBottom + artHeight <= bottom + height + EPSILON, "lowered toast art fits the existing HUD height")
            Check(
                artLeft >= screenLeft - EPSILON
                    and artBottom >= screenBottom - EPSILON
                    and artLeft + artWidth <= screenLeft + screenWidth + EPSILON
                    and artBottom + artHeight <= screenBottom + screenHeight + EPSILON,
                "lowered toast art remains on screen at every scale and anchor"
            )
            Near(artLeft + artWidth / 2, toastLeft + toastWidth / 2, "smaller HUD burst stays horizontally centered")
            Near(
                (artBottom + artHeight / 2 - toastBottom - toastHeight / 2) / physicalPixel,
                -BURST_DROP_PIXELS,
                "HUD burst center sits four physical pixels below its text slot center"
            )
            Check(
                math.abs(artWidth - toastWidth * BURST_SCALE) <= physicalPixel + EPSILON,
                "HUD burst is twenty percent narrower within pixel rounding"
            )
            Check(
                math.abs(artHeight - toastHeight * BURST_SCALE) <= physicalPixel + EPSILON,
                "HUD burst is twenty percent shorter within pixel rounding"
            )
        end
        for _, label in ipairs({ Toasts.nameText, Toasts.captionText }) do
            local pixel = PixelUtil.GetPixelToUIUnitFactor() / label:GetEffectiveScale()
            local x, y = label:GetShadowOffset()
            Near(x / pixel, 2, "toast shadow stays two physical pixels right")
            Near(y / pixel, -2, "toast shadow stays two physical pixels down")
            Same(label.fontCalls, nil, "toast inherits its font without an inline file override")
            Check(label:GetBottom() >= Toasts.frame:GetBottom() - EPSILON, "toast label fits its footer")
            Check(label:GetTop() <= Toasts.frame:GetTop() + EPSILON, "toast label fits its upper edge")
        end
    end

    Check(
        Quiz:RegisterPack({
            id = PACK_ID,
            title = "Streak toast integration",
            version = 1,
            rules = rules,
            questions = {
                {
                    id = "one",
                    prompt = "Which answer is correct?",
                    choices = { "Correct", "Wrong", "Also wrong", "Still wrong" },
                    correctIndex = 1,
                },
            },
        }),
        "test pack registers through the normal public API"
    )
    local settings = Quiz.Store:GetSettings()
    settings.packId = PACK_ID
    Check(Main:Start(settings), "host starts an ordinary continuous game")
    Bounds()
    Hidden("new game has no unsolicited toast")
    local originalAppearance, originalPosition = Quiz.Store:GetWidgetSettings(), Copy(Widget.position)
    local originalDisplay = { Test.physicalWidth, Test.physicalHeight, UIParent:GetScale() }
    local initialRound, initialSounds = Quiz.Controller.game.round, #Test.soundCalls
    for _, display in ipairs(DISPLAY_MODES) do
        Test.physicalWidth, Test.physicalHeight = display[1], display[2]
        UIParent:SetScale(display[3])
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
        for percent = 50, 200, 5 do
            Check(Quiz.Store:SaveWidgetSettings({ scale = percent }), "geometry fixture uses a supported widget scale")
            Widget:ApplySettings()
            for _, x in ipairs(ANCHOR_COORDINATES) do
                for _, y in ipairs(ANCHOR_COORDINATES) do
                    Widget.position = { x = x, y = y }
                    Widget:OnDisplayChanged()
                    Bounds()
                end
            end
        end
    end
    Test.physicalWidth, Test.physicalHeight = originalDisplay[1], originalDisplay[2]
    UIParent:SetScale(originalDisplay[3])
    local factor = PixelUtil.GetPixelToUIUnitFactor()
    UIParent:SetSize(originalDisplay[1] * factor / originalDisplay[3], originalDisplay[2] * factor / originalDisplay[3])
    Widget.position = originalPosition
    Check(Quiz.Store:SaveWidgetSettings(originalAppearance), "geometry fixture restores the user's appearance")
    Widget:ApplySettings()
    Widget:OnDisplayChanged()
    Same(Quiz.Controller.game.round, initialRound, "burst geometry checks leave the actual question unchanged")
    Same(#Test.soundCalls, initialSounds, "burst geometry changes never manufacture streak audio")
    for streak = 1, 11 do
        local round = Quiz.Controller.game.round
        Same(Quiz.Controller.game.state, "open", "automatic progression opens the next question")
        Test.now = round.startedAt + 1
        Check(
            Quiz.Controller:AcceptAnswer(PEER, nil, round.id, round.correctIndex),
            "other player answers through the host"
        )
        if streak <= 5 then
            Check(Session:SubmitAnswer(round.correctIndex), "local host answers through the widget route")
        elseif streak == 6 then
            Check(Session:SubmitAnswer(round.correctIndex % #round.choices + 1), "host may answer incorrectly")
        end
        local sounds, snapshot = #Test.soundCalls, Snapshot()
        Hidden("answer selection never announces an unconfirmed streak")
        Test.Advance(round.deadline - Test.now)
        local result, view = Quiz.Controller.game.lastResult, Quiz.Controller:GetHostView()
        Same(view.streakMilestones, result.streakMilestones, "host view exposes the committed group milestones")
        Stable(snapshot)
        if streak < 5 then
            Same(#result.streakMilestones, 0, "four or fewer correct answers have no milestone")
            Same(#Test.soundCalls, sounds, "sub-milestone results are silent")
        else
            Same(#result.streakMilestones, streak == 5 and 2 or 1, "all qualifying players enter the result")
            Same(Toasts.nameText:GetText(), PEER, "host sees the other player's confirmed streak")
            Same(Toasts.active.streak, streak, "toast displays the actual consecutive count")
            Same(Toasts.captionAnimation, nil, "live streak captions remain fixed at every tier")
            Same(
                Toasts.captionText:GetText(),
                tostring(streak) .. " in a row",
                "live milestones show only their streak count"
            )
            Same(
                Test.soundCalls[#Test.soundCalls].path,
                Quiz.SoundMedia:GetStreakSound(streak),
                "confirmed count selects its bundled voice"
            )
            Check(
                Test.soundCalls[#Test.soundCalls].path:sub(-#SOUND_FILES[math.min(streak, 10)])
                    == SOUND_FILES[math.min(streak, 10)],
                "exact requested sound file is used"
            )
            if streak == 5 then
                Same(Toasts.queueCount, 1, "local host's simultaneous milestone is queued too")
            else
                Same(view.streak, 0, "local wrong or unanswered streak does not suppress another player")
            end
            for _ = 1, 4 do
                Widget:Refresh()
            end
            Same(#Test.soundCalls, sounds + 1, "repeated fresh host views never replay their result")
        end
        local first = Toasts.active
        Test.Advance(Quiz.Controller.nextAutoAt - Test.now)
        Same(Toasts.active, first, "opening the next question retains active toast playback")
        Drain()
        local played = #Test.soundCalls
        Widget:Refresh()
        Same(#Test.soundCalls, played, "completed announcements never restart on the next question")
        if streak == 8 then
            Check(Main:Pause(), "host pauses an exposed question")
            Hidden("pausing cancels the toast area")
            Same(#Test.soundCalls, played, "voided questions do not announce a streak")
            Check(Main:Resume(), "host can resume without resetting completed streaks")
        end
    end
    Same(#Test.soundCalls, 8, "five through eleven announce once each plus the host's fifth correct")
    Check(Main:Stop(), "host session ends normally")
    Main:CancelTicker()
    Hidden("stopping clears announcements")

    Check(Session:JoinHost(HOST, SESSION_ID), "participant joins a different quiz")
    Session:Receive(HOST, { "W", Session.client.request, SESSION_ID, "0.0" })
    Main:CancelTicker()
    local function Question(id)
        Games.Comms:Clear()
        Session:Receive(HOST, {
            "Q",
            SESSION_ID,
            tostring(id),
            "1",
            "1",
            "1",
            "15",
            "A remote question?",
            "4",
            "easy",
            "Classic",
            PACK_ID,
            "Streak toast integration",
            "1",
            "3",
            rulesKey,
            "One",
            "Two",
            "Three",
            "Four",
        })
        Session:Receive(HOST, { "O", SESSION_ID, tostring(id), tostring(GetServerTime() + 15) })
        Widget:Refresh()
        Same(Session.view.id, id, "participant accepts the real question packet")
        Same(Session.view.state, "open", "participant receives the opening clock")
        return Session.view
    end
    local function Result(view, references)
        local points = Quiz.Scoring.Calculate(false, 5, 15, rules, 0)
        return {
            "R",
            SESSION_ID,
            tostring(view.id),
            "2",
            "1",
            string.format("%.1f", points),
            "0.0",
            "2",
            "3",
            "",
            PACK_ID,
            view.packTitle,
            "1",
            "3",
            "15",
            "4",
            "5",
            "Quick-OtherRealm",
            "2",
            rulesKey,
            "0",
            "0.0",
            references,
        }
    end
    local view = Question(1)
    local sounds = #Test.soundCalls
    Test.now = view.deadline
    Session:Tick(Test.now)
    Widget:Refresh()
    Same(view.state, "results", "local timeout enters the waiting-for-result state")
    Same(view.correctIndex, nil, "local timeout does not invent correctness")
    Same(#Test.soundCalls, sounds, "local timeout cannot play a streak")
    local result = Result(view, "1:5,2:6")
    Session:Receive(HOST, result)
    Widget:Refresh()
    Check(view.points < 0, "authoritative wrong-answer score applies before display names arrive")
    Same(#Test.soundCalls, sounds, "unresolved names do not produce anonymous announcements")
    Session:Receive(HOST, { "N", SESSION_ID, Session.client.request, "2", "Quick-OtherRealm" })
    Widget:Refresh()
    Same(Toasts.active.streak, 6, "a resolved player can announce while another name is missing")
    Same(Toasts.nameText:GetText(), "Quick-OtherRealm", "result speaker resolves from the current host dictionary")
    Same(Toasts.queueCount, 0, "unresolved speaker has no premature queue entry")
    Session:Receive(HOST, { "N", SESSION_ID, Session.client.request, "1", PEER })
    Widget:Refresh()
    Same(Toasts.queueCount, 1, "late name resolution queues only the additional player")
    local plays = Toasts.animation.playCalls
    Session:Receive(HOST, result)
    Session:Receive(HOST, { "N", SESSION_ID, Session.client.request, "2", "Quick-OtherRealm" })
    Widget:Refresh()
    Same(Toasts.animation.playCalls, plays, "duplicate result/name packets never repeat animation")
    Same(Toasts.queueCount, 1, "duplicate metadata never adds another pending copy")
    Bounds()
    local current = Toasts.active
    Question(2)
    Same(Toasts.active, current, "participant retains a result toast into the next question")
    Same(Toasts.queueCount, 1, "pending player is not lost on ordinary question progression")
    Drain()
    Same(#Test.soundCalls, sounds + 2, "each resolved player is heard once")

    local fixtureId = 100
    local template = Copy(Session.view)
    local function Fixture(events, suppressed)
        fixtureId = fixtureId + 1
        local fixture = Copy(template)
        fixture.id, fixture.state, fixture.correctIndex = fixtureId, "results", 2
        fixture.points, fixture.selected, fixture.streak = nil, nil, 0
        fixture.streakMilestones = events or { { name = PEER, streak = 10 } }
        fixture.suppressStreakToasts = suppressed
        Session.view = fixture
        Widget:Refresh()
        return fixture
    end
    sounds = #Test.soundCalls
    local suppressed = Fixture(nil, true)
    Hidden("historical receipt catch-up never announces a streak")
    suppressed.suppressStreakToasts = nil
    Widget:Refresh()
    Same(#Test.soundCalls, sounds, "clearing a catch-up flag cannot replay a suppressed result")
    for _, preserve in ipairs({
        {
            "paused game",
            function()
                Session.view.state = "paused"
                Widget:Refresh()
            end,
        },
        {
            "restricted communication",
            function()
                Session.restricted = true
                Widget:Refresh()
            end,
        },
        {
            "next-question packet wait",
            function()
                Session.view.state = "waiting"
                Widget:Refresh()
            end,
        },
    }) do
        local fixture = Fixture({ { name = PEER, streak = 10 }, { name = HOST, streak = 5 } })
        local activeToast, activeHandle = Toasts.active, Toasts.soundHandle
        local pending, stops = Toasts.queueCount, #Test.stoppedSounds
        preserve[2]()
        Same(Toasts.active, activeToast, preserve[1] .. " preserves the current announcement")
        Same(Toasts.soundHandle, activeHandle, preserve[1] .. " preserves the current native voice")
        Same(Toasts.queueCount, pending, preserve[1] .. " preserves queued announcements")
        Same(#Test.stoppedSounds, stops, preserve[1] .. " never calls StopSound")
        Session.restricted, fixture.state = false, "results"
        Widget:Refresh()
        Drain()
        Same(#Test.stoppedSounds, stops, preserve[1] .. " lets every retained voice finish naturally")
    end
    for _, cancel in ipairs({
        {
            "hidden widget",
            function()
                Widget.frame:Hide()
            end,
        },
        {
            "display change",
            function()
                Widget:OnDisplayChanged()
            end,
        },
        {
            "scale change",
            function()
                local appearance = Quiz.Store:GetWidgetSettings()
                appearance.scale = 105
                Check(Quiz.Store:SaveWidgetSettings(appearance), "appearance edit is saved independently")
                Widget:ApplySettings()
            end,
        },
        {
            "edit drag",
            function()
                Widget:SetEditing(true)
                Widget:StartDrag()
                Widget:Refresh()
            end,
        },
    }) do
        local fixture = Fixture({ { name = PEER, streak = 10 }, { name = HOST, streak = 5 } })
        Same(Toasts.queueCount, 1, "lifecycle test begins with active and pending announcements")
        local count = #Test.soundCalls
        cancel[2]()
        Hidden(cancel[1] .. " cancels current and queued announcements")
        Session.restricted, fixture.state = false, "results"
        Widget:StopDrag()
        Widget:SetEditing(false)
        Widget:Refresh()
        Hidden(cancel[1] .. " remains silent after returning to the same result")
        Same(#Test.soundCalls, count, "cancelled announcements do not replay")
        Bounds()
    end
    local latest = Fixture()
    Drain()
    sounds = #Test.soundCalls
    latest.id = latest.id - 1
    latest.streakMilestones = { { name = "Late-OtherRealm", streak = 7 } }
    Widget:Refresh()
    Same(#Test.soundCalls, sounds, "out-of-order presentation cannot rewind milestone feedback")
    Fixture()
    Check(Session:Leave(), "player may leave the current game")
    Widget:Refresh()
    Hidden("leaving clears all session-specific playback")
    Check(Session:JoinHost(HOST, SESSION_ID), "participant rejoins for natural completion coverage")
    Session:Receive(HOST, { "W", Session.client.request, SESSION_ID, "0.0" })
    Main:CancelTicker()
    Test.soundDuration = TOAST_SECONDS + 2
    local final = Fixture({ { name = PEER, streak = 10 }, { name = HOST, streak = 5 } })
    Test.soundDuration = nil
    local finalToast, finalHandle = Toasts.active, Toasts.soundHandle
    local finalStops = #Test.stoppedSounds
    Session:Receive(HOST, { "X", SESSION_ID })
    Widget:Refresh()
    Same(Session.client, nil, "host completion releases participant membership")
    Same(Toasts.active, finalToast, "host completion retains its current result toast")
    Same(Toasts.soundHandle, finalHandle, "host completion retains its unfinished native voice")
    Same(Toasts.queueCount, 1, "host completion retains simultaneous result announcements")
    Same(Widget.frame:IsShown(), true, "HUD remains for the natural final-toast tail")
    Same(#Test.stoppedSounds, finalStops, "host completion never calls StopSound")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Check(Toasts.frame:GetScript("OnUpdate"), "final native audio may outlive its visual fade")
    Test.AdvanceAudio(2.1)
    Toasts.frame:GetScript("OnUpdate")(Toasts.frame, 2.1)
    Same(Toasts.active.name, HOST, "queued final announcement begins after native completion")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Hidden("naturally completed final announcements release the HUD")
    Same(#Test.stoppedSounds, finalStops, "every final voice completes without forced cancellation")
    Widget:SetEditing(true)
    Hidden("opening the idle placement preview cannot replay an old streak")
    Widget:SetEditing(false)
    Check(Session:JoinHost("Newhost-OtherRealm", "toast-session.2"), "joining a different host starts clean")
    Widget:Refresh()
    Hidden("new membership does not inherit any announcement")
    Check(Session:Leave(), "cleanup leaves the fixture host")
    Main:CancelTicker()
    Same(#Test.errors, 0, "streak presentation reports no runtime errors")
    return assertions
end

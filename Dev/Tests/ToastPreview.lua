local PACK_ID = "toast-preview-real-pack"
local HOST = "Previewcheck-OtherRealm"
local SESSION_ID = "preview-check.1"
local FONT_NAME = "Toast preview saved font"
local FONT_PATH = "Interface\\AddOns\\ToastPreviewTest\\Saved.ttf"
local TOAST_SECONDS = 3.2
local CAPTION_PULSE_STREAK = 10
local EPSILON = 0.000001
local SOUND_FILES = {
    "dominating.mp3",
    "ownage.mp3",
    "rampage.mp3",
    "wicked-sick.mp3",
    "holyshit.mp3",
    "godlike.mp3",
    "godlike.mp3",
}

return function(Quiz, development)
    local assertions = 0
    local Dev, Widget, Toasts = Quiz.Development, Quiz.Widget, Quiz.StreakToasts
    local Main, Session, Store, UI = Quiz.Main, Quiz.Session, Quiz.Store, Quiz.UI
    local rules = assert(Quiz.Rules.Normalize({ shuffleChoices = false }))
    local rulesKey = Quiz.Rules.Encode(rules)
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
    local function Clone(value, seen)
        if type(value) ~= "table" then
            return value
        end
        seen = seen or {}
        if seen[value] then
            return seen[value]
        end
        local copy = {}
        seen[value] = copy
        for key, entry in pairs(value) do
            copy[key] = Clone(entry, seen)
        end
        return copy
    end
    local function Equal(actual, expected, message, seen)
        if type(expected) ~= "table" then
            Same(actual, expected, message)
            return
        end
        Same(type(actual), "table", message .. " remains a table")
        seen = seen or {}
        if seen[actual] then
            Same(seen[actual], expected, message .. " preserves shared references")
            return
        end
        seen[actual] = expected
        for key, entry in pairs(expected) do
            Equal(actual[key], entry, message .. "." .. tostring(key), seen)
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " adds no unexpected field " .. tostring(key))
        end
    end
    local function World()
        return {
            saved = OrbitQuizDB,
            store = Store.db,
            session = Session,
            game = Main.game,
            main = Main,
            discovery = Quiz.Discovery,
            comms = Quiz.Comms,
            identity = Quiz.Identity,
            sends = #Test.addonSent,
            publicSends = #Test.sent,
            channelJoins = #Test.joins,
            tickers = #Test.tickers,
        }
    end
    local function Quiet(action, message)
        local previous = Clone(World())
        local database, game, client, peerTable = Store.db, Main.game, Session.client, Session.peers
        action()
        Equal(World(), previous, message)
        Same(Store.db, database, message .. " keeps the same database")
        Same(OrbitQuizDB, database, message .. " keeps SavedVariables ownership")
        Same(Main.game, game, message .. " keeps the same game")
        Same(Session.client, client, message .. " keeps the same membership")
        Same(Session.peers, peerTable, message .. " keeps the same host peers")
    end
    local function Count(values)
        local count = 0
        for _ in pairs(values) do
            count = count + 1
        end
        return count
    end
    local function Cleared(shown)
        Same(Widget.streakPreview, nil, "finished preview is only transient state")
        Same(Toasts.active, nil, "finished preview has no active sample")
        Same(Toasts.queueCount, 0, "finished preview retains no sample backlog")
        Same(Toasts.soundHandle, nil, "finished preview owns no sound handle")
        Same(Toasts.animation:IsPlaying(), false, "finished preview has no active animation")
        Same(Toasts.captionAnimation:IsPlaying(), false, "finished preview has no retained caption pulse")
        Same(Toasts.frame:GetScript("OnUpdate"), nil, "finished preview has no retained audio poll")
        Same(Toasts.frame:IsShown(), false, "finished preview shows no ribbon")
        Same(Widget.frame:IsShown(), shown == true, "HUD visibility follows actual game or edit mode")
        Same(Count(Test.soundHandles), 0, "finished preview leaks no audio")
    end
    local function Drain()
        for _ = 1, #SOUND_FILES do
            Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        end
    end
    local function NoReplay(shown)
        local sounds = #Test.soundCalls
        Widget:Refresh()
        Widget:Refresh()
        Test.AdvanceAnimations(TOAST_SECONDS * 2)
        Same(#Test.soundCalls, sounds, "refresh and stale animations never replay cancelled samples")
        Cleared(shown)
    end
    local function PollAudio(seconds)
        Test.AdvanceAudio(seconds)
        local update = Toasts.frame:GetScript("OnUpdate")
        if update then
            update(Toasts.frame, seconds)
        end
    end
    local function StartAudioTail()
        Test.soundDuration = TOAST_SECONDS + 2
        Check(Dev:ShowToasts(), "preview starts even when a native voice outlasts its visual")
        Test.soundDuration = nil
        Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        Check(Widget.streakPreview, "unfinished audio retains its transient preview ownership")
        Check(Toasts.frame:GetScript("OnUpdate"), "unfinished preview audio installs the owned completion poll")
        Same(Toasts.frame:GetAlpha(), 0, "preview visual finishes independently from native audio")
    end
    local function RegisterRealPack()
        Check(
            Quiz:RegisterQuestionPack({
                id = PACK_ID,
                title = "Actual quiz, not a preview",
                rules = rules,
                questions = {
                    {
                        id = "one",
                        prompt = "Which real answer is correct?",
                        choices = { "Correct", "Wrong", "No", "Also no" },
                        correctIndex = 1,
                    },
                },
            }),
            "real-game fixture registers through the public pack API"
        )
    end
    local function StartRealGame()
        local settings = Store:GetSettings()
        settings.packId = PACK_ID
        Check(Main:Start(settings), "ordinary hosting remains available")
        Same(Widget.streakPreview, nil, "real hosting clears the sample preview")
        Same(Toasts.active, nil, "real hosting cancels sample audio and animation")
        Same(Toasts.queueCount, 0, "sample backlog never spills into a real game")
        Same(Widget.prompt:GetText(), Main.game.round.prompt, "real question replaces the sample content")
        for streak = 1, 5 do
            local round = Main.game.round
            Check(Session:SubmitAnswer(round.correctIndex), "real host can answer normally")
            Test.Advance(round.deadline - Test.now)
            Same(Main.game.state, "results", "real answers close under the pack rules")
            if streak < 5 then
                Test.Advance(Main.game.rules.revealSeconds)
            end
        end
        Same(Toasts.active.name, Quiz.Identity.name, "real fifth-correct result still produces a toast")
        Same(Toasts.active.streak, 5, "real streak count is separate from the sample sequence")
        Same(Toasts.nameText:GetText(), Quiz.Identity.name, "real toast names the actual player")
    end

    Same(Widget.streakPreview, nil, "startup never enables a toast preview")
    Same(Widget.frame, nil, "startup never allocates a sample HUD")
    Same(UI.frame, nil, "startup never opens the setup dialog")
    Same(_G.Orbit, nil, "toast previews do not require Orbit")
    if not development then
        Same(Dev, nil, "packaged addon has no development module")
        Same(SLASH_ORBITQUIZDEV1, nil, "packaged addon has no developer command")
        Same(SlashCmdList.ORBITQUIZDEV, nil, "packaged addon has no developer command handler")
        for key in pairs(Quiz.L) do
            Check(not key:match("^DEV_"), "packaged addon includes no sample-only localization")
        end
        RegisterRealPack()
        StartRealGame()
        Drain()
        Same(Widget.frame:IsShown(), true, "draining a real toast cannot close a hosted quiz")
        Same(Session:GetView().state, "results", "drained feedback cannot change the actual question state")
        Same(Main.game.completed, 5, "real scoring works without the developer module")
        Same(#Test.soundCalls, 1, "packaged game plays only the earned milestone")
        Main:Stop()
        return assertions
    end

    Same(type(Dev.ShowToasts), "function", "source checkout exposes a dedicated local toast showcase")
    Same(SLASH_ORBITQUIZDEV1, "/oqdev", "showcase shares the source-only developer command")
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("off")
    end, "off without a preview does not affect state")
    Same(Widget.frame, nil, "off cannot allocate an unnecessary HUD")
    Same(UI.frame, nil, "off cannot open the setup dialog")
    local library = LibStub("LibSharedMedia-3.0")
    Check(library:Register("font", FONT_NAME, FONT_PATH), "fixture registers a selected SharedMedia font")
    Check(Store:SaveWidgetSettings({ scale = 135, font = FONT_NAME }), "fixture saves appearance preferences")
    Check(Store:SaveWidgetPosition(0.31, 0.72), "fixture saves an existing widget position")
    Check(
        Quiz.PersonalScores:RecordResult({
            host = "Retained-OtherRealm",
            session = "keep-history.1",
            roundId = 101,
            packId = "preview-existing",
            packTitle = "Existing scores",
            packVersion = 1,
            scoringVersion = Quiz.Scoring.VERSION,
            rulesKey = rulesKey,
            duration = rules.answerSeconds,
            choiceCount = 4,
            selected = 1,
            correctIndex = 1,
            elapsed = 1,
            points = Quiz.Scoring.Calculate(true, 1, rules.answerSeconds, rules, 1),
            streak = 1,
            streakBonus = 0,
        }),
        "fixture creates real saved progress before the local preview"
    )
    local saved = Clone(OrbitQuizDB)
    local soundStart = #Test.soundCalls
    local stopStart = #Test.stoppedSounds
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("  TOASTS  ")
    end, "starting toast preview is entirely local")
    Check(Widget.streakPreview, "command installs a transient preview")
    Same(Widget.packText:GetText(), Quiz.L.DEV_TOASTS_TITLE, "HUD clearly identifies the demonstration")
    Same(UI.frame, nil, "toast command does not create or show the /oq dialog")
    Check(Widget.frame:IsVisible(), "toast command shows the real Q/A widget directly")
    Same(Widget.frame.movable, false, "standalone toast preview does not enable dragging")
    Near(Widget.frame:GetScale(), 1.35, "preview uses the saved widget scale")
    Same(Widget.prompt:GetFont(), FONT_PATH, "preview uses the selected SharedMedia font")
    Same(Toasts.nameText:GetFont(), FONT_PATH, "toast uses the selected SharedMedia font")
    Near(Widget.position.x, 0.31, "preview retains the saved horizontal anchor")
    Near(Widget.position.y, 0.72, "preview retains the saved vertical anchor")
    for _, choice in ipairs(Widget.choices) do
        Check(not choice:IsEnabled(), "sample answer inputs are read-only")
        Check(not choice.controlEnabled, "sample answer inputs have no live answer route")
    end
    Same(Widget.timer:GetScript("OnUpdate"), nil, "sample question needs no ticking game clock")
    local frames, animations, labels = #Test.frames, Test.animationCreations, Test.fontStringCreations
    local pulseStart = Toasts.captionAnimation.playCalls
    local names = {}
    for index, filename in ipairs(SOUND_FILES) do
        local event = Toasts.active
        Check(event and event.name ~= "", "every sample displays a player name")
        Check(not names[event.name], "all seven sample players are distinct")
        names[event.name] = true
        Same(event.streak, index + 4, "sample streaks run from five through eleven in order")
        Same(
            Toasts.captionAnimation:IsPlaying(),
            event.streak >= CAPTION_PULSE_STREAK,
            "only Godlike sample captions pulse"
        )
        Same(
            Toasts.captionAnimation.playCalls,
            pulseStart + math.max(0, event.streak - CAPTION_PULSE_STREAK + 1),
            "preview plays each high-streak caption pulse once"
        )
        Same(Toasts.nameText:GetText(), event.name, "sample name is rendered by the real toast")
        Same(
            Toasts.captionText:GetText(),
            tostring(event.streak) .. " in a row",
            "preview uses the compact count-only caption"
        )
        Same(Toasts.queueCount, #SOUND_FILES - index, "sample voices are serialized")
        Same(#Test.soundCalls, soundStart + index, "only the current sample begins playing")
        Same(
            Test.soundCalls[#Test.soundCalls].path,
            "Interface\\AddOns\\Orbit-Quiz\\Assets\\Sounds\\" .. filename,
            "showcase uses the exact bundled milestone clip"
        )
        Same(Count(Test.soundHandles), 1, "only one sample voice can be playing")
        Quiet(function()
            Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        end, "native showcase animation has no game or networking effects")
    end
    Same(#Test.frames, frames, "queue playback allocates no additional frames")
    Same(Test.animationCreations, animations, "queue playback reuses native animation objects")
    Same(Test.fontStringCreations, labels, "queue playback reuses the text regions")
    Same(#Test.stoppedSounds, stopStart, "natural sample playback never cuts off any of the seven voices")
    Equal(OrbitQuizDB, saved, "full preview leaves all saved progress and appearance untouched")
    Cleared(false)
    NoReplay(false)

    Quiet(function()
        Check(Dev:ShowToasts(), "fixture starts a preview before cancelling a high-streak pulse")
        for _ = 1, 5 do
            Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        end
        Test.AdvanceAnimations(0.25)
        Check(Toasts.captionAnimation:IsPlaying(), "Godlike preview reaches a live caption pulse")
        local pulseStops = Toasts.captionAnimation.stopCalls
        SlashCmdList.ORBITQUIZDEV("off")
        Same(Toasts.captionAnimation.stopCalls, pulseStops + 1, "off cancels an active preview pulse")
    end, "cancelling caption feedback has no gameplay or networking effects")
    Cleared(false)
    NoReplay(false)
    Quiet(function()
        Check(Dev:ShowToasts(), "fixture starts a preview before restarting a high-streak pulse")
        for _ = 1, 5 do
            Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        end
        local pulseStops, pulsePlays = Toasts.captionAnimation.stopCalls, Toasts.captionAnimation.playCalls
        Check(Dev:ShowToasts(), "preview can restart while a Godlike caption is pulsing")
        Same(Toasts.active.streak, 5, "restarted preview begins with its lower milestone")
        Same(Toasts.captionAnimation.stopCalls, pulseStops + 1, "restart cancels the old Godlike caption pulse")
        Same(Toasts.captionAnimation.playCalls, pulsePlays, "restart does not pulse its first lower-streak caption")
        Same(Toasts.captionAnimation:IsPlaying(), false, "restarted low streak retains no high-streak animation")
        SlashCmdList.ORBITQUIZDEV("off")
    end, "restarting caption feedback retains source-only preview isolation")
    Cleared(false)
    NoReplay(false)

    stopStart = #Test.stoppedSounds
    Quiet(StartAudioTail, "waiting for native audio creates no game or networking state")
    local waitingPreview, waitingEvent, waitingHandle = Widget.streakPreview, Toasts.active, Toasts.soundHandle
    soundStart = #Test.soundCalls
    Quiet(function()
        PollAudio(0.5)
        Widget:Refresh()
        Widget:Refresh()
    end, "audio-tail polling and redraw remain local")
    Same(Widget.streakPreview, waitingPreview, "routine refresh cannot drain a still-playing preview")
    Same(Toasts.active, waitingEvent, "the next sample waits for actual native completion")
    Same(Toasts.soundHandle, waitingHandle, "routine refresh preserves the unfinished native handle")
    Same(Test.soundHandles[waitingHandle], true, "overlong sample audio is not clipped at the visual deadline")
    Same(#Test.soundCalls, soundStart, "waiting neither restarts the clip nor overlaps the next voice")
    Same(#Test.stoppedSounds, stopStart, "visual completion never force-stops the preview voice")
    Quiet(function()
        PollAudio(1.6)
    end, "native completion advances the preview without gameplay effects")
    Same(Toasts.active.streak, 6, "preview resumes at the next milestone after the native tail ends")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "next sample cannot retain the previous sound poll")
    Quiet(Drain, "remaining normal-duration samples still drain without a game timer")
    Same(#Test.stoppedSounds, stopStart, "overlong sample and remaining queue all finish natively")
    Cleared(false)

    Quiet(function()
        Check(Dev:ShowToasts(), "fixture starts a preview with an overlong final sample")
        for _ = 1, #SOUND_FILES - 2 do
            Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        end
        Test.soundDuration = TOAST_SECONDS + 2
        Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        Test.soundDuration = nil
        Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    end, "final sample waiting is also independent from quiz state")
    Same(Toasts.active.streak, 11, "the final Godlike sample still owns its unfinished voice")
    Same(Toasts.queueCount, 0, "final audio can outlive an otherwise empty queue")
    Check(Widget.streakPreview, "empty pending queue alone cannot clear the preview")
    Same(Widget.frame:IsShown(), true, "preview owner stays alive until the final native voice completes")
    Same(Toasts.frame:GetAlpha(), 0, "the final toast does not flash back while its audio finishes")
    Quiet(function()
        PollAudio(2.1)
    end, "the last native completion releases the idle preview")
    Same(#Test.stoppedSounds, stopStart, "natural final completion never cancels its remaining audio")
    Cleared(false)
    NoReplay(false)

    Quiet(function()
        StartAudioTail()
    end, "restarting after completion remains local")
    local activeHandle = Toasts.soundHandle
    soundStart = #Test.soundCalls
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("streaks")
    end, "alias restarts the sample sequence without a new session")
    Same(Toasts.active.streak, 5, "repeating the command restarts from Dominating")
    Same(Toasts.queueCount, 6, "restart replaces rather than appends to the old sample queue")
    Same(Test.soundHandles[activeHandle], nil, "restart stops the previous owned voice")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "restarting during an audio tail cancels its old poll")
    Same(#Test.soundCalls, soundStart + 1, "restart plays the first sample once")
    Same(#Test.frames, frames, "restarting reuses the existing widget")
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("off")
    end, "off cancels the sample without touching game state")
    Cleared(false)
    NoReplay(false)
    Quiet(function()
        StartAudioTail()
        SlashCmdList.ORBITQUIZDEV("off")
        PollAudio(10)
    end, "off cancels a waiting audio tail without any delayed replay")
    Cleared(false)
    NoReplay(false)

    for _, failure in ipairs({ "false", "throw" }) do
        Test.soundFailure = failure == "false" and true or "throw"
        soundStart = #Test.soundCalls
        Quiet(function()
            Check(Dev:ShowToasts(), "audio failure cannot prevent a visual showcase")
            Drain()
        end, "unavailable audio does not stall local preview cleanup")
        Same(#Test.soundCalls, soundStart + #SOUND_FILES, "failed samples are each attempted once")
        Cleared(false)
    end
    Test.soundFailure = nil
    Test.restricted = true
    Quiet(function()
        Check(Dev:ShowToasts(), "an idle local showcase does not require chat permissions")
        SlashCmdList.ORBITQUIZDEV("off")
    end, "restricted chat cannot turn the local showcase into a network operation")
    Test.restricted = false
    Cleared(false)

    StartAudioTail()
    local openingPreview, openingToast, openingHandle = Widget.streakPreview, Toasts.active, Toasts.soundHandle
    local openingPoll = Toasts.frame:GetScript("OnUpdate")
    soundStart = #Test.soundCalls
    UI:Toggle()
    Check(UI.frame:IsShown() and Widget.editing, "fixture opens normal positioning mode")
    Same(Widget.streakPreview, openingPreview, "first-time setup creation preserves the running local preview")
    Same(Toasts.active, openingToast, "opening /oq does not restart a running sample")
    Same(Toasts.soundHandle, openingHandle, "opening /oq preserves the sample audio handle")
    Same(Toasts.frame:GetScript("OnUpdate"), openingPoll, "opening /oq preserves an unfinished sample's poll")
    Same(#Test.soundCalls, soundStart, "opening /oq does not replay the sample voice")
    Quiet(function()
        PollAudio(2.1)
        Drain()
    end, "showcase completion does not refresh discovery")
    Cleared(true)
    Same(UI.frame:IsShown(), true, "natural completion never closes the user's settings window")
    Same(Widget.packText:GetText(), Quiz.L.W_PREVIEW_PACK, "completion restores the normal positioning preview")
    StartAudioTail()
    Quiet(function()
        UI.frame:Hide()
    end, "closing /oq cancels only its transient sample content")
    Cleared(false)
    NoReplay(false)
    UI:Toggle()
    Check(Dev:ShowToasts(), "fixture starts the drag-cancellation preview")
    Quiet(function()
        Widget:StartDrag()
    end, "dragging cancels sample animation without gameplay effects")
    Cleared(true)
    Check(not Dev:ShowToasts(), "showcase cannot begin while the widget is being dragged")
    Widget:StopDrag()
    NoReplay(true)
    UI.frame:Hide()

    Check(Dev:ShowToasts(), "fixture starts a preview before hiding the HUD")
    Quiet(function()
        Widget.frame:Hide()
    end, "hiding the HUD stops its sample voices")
    NoReplay(false)
    for _, change in ipairs({ "scale", "font", "display" }) do
        Check(Dev:ShowToasts(), "fixture starts a preview before appearance changes")
        if change == "scale" then
            Check(Store:SaveWidgetSettings({ scale = 145 }), "fixture changes scale through the appearance store")
        elseif change == "font" then
            Check(Store:SaveWidgetSettings({ font = "" }), "fixture changes font through the appearance store")
        end
        Quiet(function()
            if change == "display" then
                Widget:OnDisplayChanged()
            else
                Widget:ApplySettings()
            end
        end, "appearance reflow cancels the sample without unrelated mutations")
        NoReplay(false)
    end

    RegisterRealPack()
    StartAudioTail()
    StartRealGame()
    local function Blocked(message)
        local active, handle = Toasts.active, Toasts.soundHandle
        local pending, starts, stops = Toasts.queueCount, #Test.soundCalls, #Test.stoppedSounds
        local animationPlays, animationStops = Toasts.animation.playCalls, Toasts.animation.stopCalls
        Quiet(function()
            Check(not Dev:ShowToasts(), "preview command rejects an actual quiz membership")
            SlashCmdList.ORBITQUIZDEV("toasts")
        end, message)
        Same(
            Test.messages[#Test.messages]:sub(-#Quiz.L.DEV_TOASTS_ACTIVE),
            Quiz.L.DEV_TOASTS_ACTIVE,
            "rejected command explains that the live game was not changed"
        )
        Same(Toasts.active, active, "rejected preview preserves any active real announcement")
        Same(Toasts.soundHandle, handle, "rejected preview preserves the current real sound handle")
        Same(Toasts.queueCount, pending, "rejected preview preserves queued real announcements")
        Same(#Test.soundCalls, starts, "rejected preview starts no sample voice")
        Same(#Test.stoppedSounds, stops, "rejected preview stops no real voice")
        Same(Toasts.animation.playCalls, animationPlays, "rejected preview does not restart real feedback")
        Same(Toasts.animation.stopCalls, animationStops, "rejected preview does not cancel real feedback")
        Same(Widget.streakPreview, nil, "rejected preview has no latent sample state")
    end
    Blocked("active host results cannot be replaced by dummy achievements")
    local realToast, realHandle = Toasts.active, Toasts.soundHandle
    Quiet(function()
        SlashCmdList.ORBITQUIZDEV("off")
    end, "off without a sample does not stop a real achievement")
    Same(Toasts.active, realToast, "developer off preserves active real feedback")
    Same(Toasts.soundHandle, realHandle, "developer off preserves active real audio")
    Check(Main:Pause(), "fixture pauses the real host")
    Blocked("paused hosting still owns the widget")
    Main:Stop()
    StartAudioTail()
    Check(Session:JoinHost(HOST), "ordinary joining is still available")
    Same(Widget.streakPreview, nil, "joining a real host immediately clears the local preview")
    Same(Toasts.active, nil, "joining a host stops the local announcer")
    Same(Toasts.queueCount, 0, "joining discards all sample backlog")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "real joining cancels the preview audio-tail poll")
    Blocked("even an unfinished join prevents a sample preview")
    local client = Session.client
    Session:Receive(HOST, { "W", client.request, SESSION_ID, "Real quiz", "0" })
    Blocked("waiting for a real question prevents a sample preview")
    Session:Receive(HOST, {
        "Q",
        SESSION_ID,
        "500",
        "1",
        "1",
        "1",
        "15",
        "A real participant question",
        "4",
        "",
        "",
        PACK_ID,
        "Actual quiz, not a preview",
        "1",
        "3",
        rulesKey,
        "Correct",
        "Wrong",
        "No",
        "Also no",
    })
    Session:Receive(HOST, { "O", SESSION_ID, "500", tostring(GetServerTime() + rules.answerSeconds) })
    Widget:Refresh()
    Same(Session.view.state, "open", "fixture receives the real participant question")
    Blocked("active participation cannot be replaced by sample content")
    Session:Receive(HOST, { "P", SESSION_ID, "500", "manual" })
    Widget:Refresh()
    Same(Session.view.state, "paused", "fixture pauses the real participant view")
    Blocked("paused participation still owns the widget")
    Check(Session:Leave(), "fixture explicitly leaves the real session")
    Same(#Test.sent, 0, "toast demonstration never sends visible chat")
    Same(Widget.streakPreview, nil, "suite ends without a preview")
    return assertions
end

local EPSILON = 0.000001
local TOAST_SECONDS = 3.2
local SOUND_DIRECTORY = "Interface\\AddOns\\Orbit-Quiz\\Assets\\Sounds\\"
local SOUND_STEMS =
    { [5] = "dominating", [6] = "ownage", [7] = "rampage", [8] = "wicked-sick", [9] = "holyshit", [10] = "godlike" }
local DATA_FIELDS = {
    "schemaVersion",
    "settings",
    "nextQuestionId",
    "leagues",
    "legacyLeagues",
    "widgetPosition",
    "widgetSettings",
    "personalScores",
}
local GEOMETRY_CALLS = {
    "setPointCalls",
    "clearPointCalls",
    "sizeCalls",
    "fontCalls",
    "fontObjectAssignments",
    "stringHeightMeasurements",
}

return function(Quiz)
    local assertions = 0
    local Store, UI, Widget, Toasts, Media = Quiz.Store, Quiz.UI, Quiz.Widget, Quiz.StreakToasts, Quiz.Media
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
    local function Copy(value)
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, child in pairs(value) do
            copy[key] = Copy(child)
        end
        return copy
    end
    local function Equal(actual, expected, message)
        if type(expected) ~= "table" then
            if type(expected) == "number" and expected ~= expected then
                Check(type(actual) == "number" and actual ~= actual, message .. " preserves NaN input")
            else
                Same(actual, expected, message)
            end
            return
        end
        Same(type(actual), "table", message .. " remains a table")
        for key, value in pairs(expected) do
            Equal(actual[key], value, message .. "." .. tostring(key))
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " adds no unexpected " .. tostring(key))
        end
    end
    local function Initialize(saved)
        local db, reason = Store:Initialize(saved)
        Check(db ~= nil, "sound preferences load: " .. tostring(reason))
        Same(db.schemaVersion, 6, "sound preference does not change the score schema")
        return db
    end
    local function ExpectedSound(streak, volume)
        local stem = SOUND_STEMS[math.min(streak, 10)]
        if not stem or volume == 0 then
            return nil
        end
        return volume == 100 and SOUND_DIRECTORY .. stem .. ".mp3"
            or SOUND_DIRECTORY .. "Volume\\" .. stem .. "-" .. volume .. ".ogg"
    end

    Same(Quiz.SOUND_VOLUME_MIN, 0, "volume includes mute")
    Same(Quiz.SOUND_VOLUME_MAX, 100, "volume includes original loudness")
    Same(Quiz.SOUND_VOLUME_STEP, 10, "volume uses ten-percent steps")
    Same(Quiz.SOUND_VOLUME_DEFAULT, 100, "existing installations keep original loudness")
    Same(Initialize(nil).soundVolume, 100, "new installation defaults to full volume")
    for version = 1, 6 do
        local saved = { schemaVersion = version }
        Same(Initialize(saved).soundVolume, 100, "missing preference defaults across supported schemas")
        Same(saved.soundVolume, nil, "defaulting does not mutate the supplied database")
        for _, volume in ipairs({ 0, 30, 100 }) do
            saved.soundVolume = volume
            Same(Initialize(saved).soundVolume, volume, "legacy migration retains an explicit volume, including zero")
            Same(Store:GetSoundVolume(), volume, "getter returns the committed preference")
            Same(saved.soundVolume, volume, "loading preserves the caller's explicit preference")
        end
    end
    for streak = 4, 11 do
        Same(Media:GetStreakSound(streak), ExpectedSound(streak, 100), "omitted volume preserves original MP3 mapping")
        for volume = 0, 100, 10 do
            Same(
                Media:GetStreakSound(streak, volume),
                ExpectedSound(streak, volume),
                "every volume selects its exact clip variant"
            )
        end
    end

    local db = Initialize({
        schemaVersion = 3,
        soundVolume = 60,
        settings = { league = "Saved league", packId = "all", questionCount = 7, autoAdvance = true },
        nextQuestionId = 40,
        widgetPosition = { x = 0.27, y = 0.73 },
        widgetSettings = { scale = 125, font = "Saved unavailable font" },
        leagues = {
            Archive = {
                PUBLIC = {
                    lastRoundId = 7,
                    players = {
                        ["Player-Saved"] = {
                            name = "Saved-TestRealm",
                            score = 120,
                            correct = 1,
                            incorrect = 0,
                            answers = 1,
                        },
                    },
                },
            },
        },
    })
    Check(
        Store:RecordRound("Saved league", "PUBLIC", {
            id = 40,
            questionKey = "saved:question",
            number = 1,
            duration = 15,
            scoringVersion = 2,
            answers = {
                {
                    guid = "Player-Saved",
                    name = "Saved-TestRealm",
                    choiceIndex = 1,
                    correct = true,
                    elapsed = 2,
                    points = 2.3,
                },
            },
        }),
        "volume fixture includes existing signed-score history"
    )
    local receiptRules = assert(Quiz.Rules.Normalize())
    local personalPoints = Quiz.Scoring.Calculate(true, 2, 15, receiptRules, 1)
    Check(
        Quiz.PersonalScores:RecordResult({
            host = "Savedhost-TestRealm",
            session = "saved.1",
            roundId = 40,
            packId = "warcraft-lore",
            packTitle = "Warcraft Lore",
            packVersion = 1,
            scoringVersion = 3,
            rulesKey = Quiz.Rules.Encode(receiptRules),
            duration = 15,
            choiceCount = 4,
            selected = 1,
            correctIndex = 1,
            elapsed = 2,
            points = personalPoints,
            streak = 1,
            streakBonus = Quiz.Scoring.StreakBonus(receiptRules, 1),
        }),
        "volume fixture includes personal receipt and replay history"
    )
    local data = Copy(db)
    local identities = {}
    for _, key in ipairs(DATA_FIELDS) do
        identities[key] = db[key]
    end
    local function OtherDataUnchanged()
        Same(Store.db, db, "volume save retains the live database identity")
        for _, key in ipairs(DATA_FIELDS) do
            Same(db[key], identities[key], "volume save preserves unrelated field identity: " .. key)
            Equal(db[key], data[key], "volume save preserves unrelated data: " .. key)
        end
    end
    for volume = 0, 100, 10 do
        Check(Store:SaveSoundVolume(volume), "every supported volume can be saved")
        Same(Store:GetSoundVolume(), volume, "volume save is immediately readable")
        OtherDataUnchanged()
    end
    local invalidValues = { false, true, "50", "", {}, -10, 110, 1, 99, 49.5, math.huge, -math.huge, 0 / 0 }
    local function RejectSave(value)
        local before = Copy(db)
        local accepted, reason = Store:SaveSoundVolume(value)
        Same(accepted, false, "invalid volume save is rejected")
        Same(reason, "invalid_sound_volume", "invalid volume has a stable failure code")
        Equal(db, before, "invalid save is atomic")
        Same(Store.db, db, "invalid save retains the live database")
    end
    RejectSave(nil)
    for _, value in ipairs(invalidValues) do
        RejectSave(value)
        for _, version in ipairs({ 3, 6 }) do
            local saved = { schemaVersion = version, soundVolume = value }
            local before, personal = Copy(saved), Quiz.PersonalScores.data
            local loaded, reason = Store:Initialize(saved)
            Same(loaded, nil, "malformed saved volume cannot replace a valid database")
            Same(reason, "invalid_sound_volume", "malformed saved volume reports the stable error")
            Same(Store.db, db, "failed load leaves the prior database bound")
            Same(Quiz.PersonalScores.data, personal, "failed load leaves personal scores bound")
            Equal(saved, before, "failed load leaves supplied data untouched")
        end
    end
    Check(
        Store:SaveSettings({ league = "Changed setup", soundVolume = 0 }),
        "host setup remains independently writable"
    )
    Check(Store:SaveWidgetSettings({ scale = 130, soundVolume = 0 }), "appearance remains independently writable")
    Check(Store:SaveWidgetPosition(0.31, 0.69), "widget anchor remains independently writable")
    Same(Store:GetSoundVolume(), 100, "other settings owners cannot overwrite sound volume")
    Same(Store:GetSettings().soundVolume, nil, "volume is not a host-game setting")
    Same(Store:GetWidgetSettings().soundVolume, nil, "volume is not an appearance setting")
    Check(Store:SaveSoundVolume(60), "fixture persists a nondefault volume before renderer creation")
    local saved = Copy(db)
    db = Initialize(saved)
    Equal(db, saved, "reload retains volume beside scores, preferences and replay history")
    Same(Store:GetLegacyStandings("Archive", "PUBLIC")[1].score, 120, "old score scale remains untouched")
    Same(Store:GetStandings("Saved league", "PUBLIC")[1].score, 2.3, "signed score archive remains untouched")
    Same(Quiz.PersonalScores:GetPack("warcraft-lore").score, personalPoints, "personal totals remain untouched")
    OrbitQuizDB = db
    data = Copy(db)
    for _, key in ipairs(DATA_FIELDS) do
        identities[key] = db[key]
    end

    local nativePlay, nativeStop, nativeSetCVar, nativeCVarTable = PlaySoundFile, StopSound, SetCVar, C_CVar
    local cvarCalls = 0
    local function RecordCVar()
        cvarCalls = cvarCalls + 1
    end
    SetCVar, C_CVar = RecordCVar, Copy(C_CVar or {})
    C_CVar.SetCVar = RecordCVar
    PlaySoundFile = function(...)
        Same(select("#", ...), 2, "playback passes only native path/channel arguments, never fake volume")
        return nativePlay(...)
    end
    StopSound = function(handle, ...)
        Same(handle, Toasts.soundHandle, "volume changes stop only the renderer's current sound handle")
        Same(select("#", ...), 0, "sound stop needs no global or unrelated playback controls")
        return nativeStop(handle)
    end
    Same(Toasts.frame, nil, "renderer has not been allocated by preference persistence")
    UI:Toggle()
    UI:SetTab("settings")
    Same(Toasts.volume, 60, "renderer initializes from the persisted preference")
    local row, slider = UI.volumeSlider, UI.volumeSlider.Slider.Slider
    Same(row.Label:GetText(), "Volume", "volume has a concise independent label")
    Same(row.template, "EditModeSettingSliderTemplate", "volume reuses the native inline settings row")
    Same(slider.template, "MinimalSliderTemplate", "volume reuses the native slider")
    Same(row.cbrHandles.unregisterCalls, 1, "standalone volume row detaches native Edit Mode callbacks")
    Check(row.cbrHandles:IsEmpty(), "volume has no stale Blizzard dialog callback")
    Same(slider:GetMinMaxValues(), 0, "volume slider starts at mute")
    Same(select(2, slider:GetMinMaxValues()), 100, "volume slider ends at original loudness")
    Same(slider:GetValueStep(), 10, "native volume slider advances in ten-percent steps")
    Same(slider:GetObeyStepOnDrag(), true, "native volume dragging obeys its step")
    Same(slider.narrationLabelRegion, row.Label, "native narration identifies the Volume label")
    Same(row.Value:GetText(), "60%", "persisted volume is formatted as a percentage")
    Check(row:GetTop() < UI.fontRow:GetBottom(), "Volume sits below the Font row")
    Check(row:GetBottom() > UI.widgetSettingsHelp:GetTop(), "Volume leaves space before the settings help")
    for event, handler in pairs(slider.templateScripts) do
        Same(slider:GetScript(event), handler, "volume preserves native interaction handler: " .. event)
    end
    Same(slider:GetScript("OnValueChanged"), slider.templateValueChanged, "native value handler owns volume dispatch")
    Same(row.Slider.Back:GetScript("OnClick"), row.Slider.Back.templateClick, "native decrement handler is retained")
    Same(
        row.Slider.Forward:GetScript("OnClick"),
        row.Slider.Forward.templateClick,
        "native increment handler is retained"
    )

    local originalApply, originalSave = Widget.ApplySettings, Store.SaveSoundVolume
    local applyCalls, saveCalls = 0, 0
    Widget.ApplySettings = function(self, ...)
        applyCalls = applyCalls + 1
        return originalApply(self, ...)
    end
    Store.SaveSoundVolume = function(self, ...)
        saveCalls = saveCalls + 1
        return originalSave(self, ...)
    end
    local geometry, regions =
        {}, {
            Widget.frame,
            Widget.content,
            Widget.questionScroll,
            Widget.questionContent,
            Widget.prompt,
            Widget.packText,
            Widget.timer,
            Widget.scoreText,
            Widget.winnerText,
            Toasts.frame,
            Toasts.nameText,
            Toasts.captionText,
            UI.scaleSlider,
            UI.fontRow,
            row,
        }
    for _, choice in ipairs(Widget.choices) do
        regions[#regions + 1], regions[#regions + 2] = choice, choice.Text
    end
    for _, region in ipairs(regions) do
        geometry[region] = { rect = { region:GetScaledRect() } }
        for _, key in ipairs(GEOMETRY_CALLS) do
            geometry[region][key] = region[key]
        end
    end
    local frames, labels, animations, tickers =
        #Test.frames, Test.fontStringCreations, Test.animationCreations, #Test.tickers
    local function Stable()
        Same(applyCalls, 0, "volume never calls Widget:ApplySettings")
        Same(cvarCalls, 0, "volume never changes global sound CVars")
        Same(#Test.frames, frames, "volume reuses existing frames")
        Same(Test.fontStringCreations, labels, "volume reuses existing labels")
        Same(Test.animationCreations, animations, "volume reuses existing native animations")
        Same(#Test.tickers, tickers, "volume creates no timer work")
        Same(OrbitQuizDB, db, "volume retains SavedVariables ownership")
        for region, before in pairs(geometry) do
            for _, key in ipairs(GEOMETRY_CALLS) do
                Same(region[key], before[key], "volume leaves layout untouched: " .. key)
            end
            for index, value in ipairs({ region:GetScaledRect() }) do
                Near(value, before.rect[index], "volume leaves visible geometry unchanged")
            end
        end
        OtherDataUnchanged()
    end
    slider:GetScript("OnMouseDown")(slider)
    for volume = 0, 100, 10 do
        local before = saveCalls
        slider:SetValue(volume)
        Same(saveCalls, before + 1, "each new native slider position saves exactly once")
        Same(Store:GetSoundVolume(), volume, "all eleven slider positions persist")
        Same(UI.soundVolume, volume, "settings cache follows native slider input")
        Same(Toasts.volume, volume, "future playback follows native slider input")
        Same(row.Value:GetText(), volume .. "%", "every slider step displays a percent")
        Same(row.Slider.Back:IsEnabled(), volume > 0, "decrement respects the mute boundary")
        Same(row.Slider.Forward:IsEnabled(), volume < 100, "increment respects the full-volume boundary")
        Stable()
    end
    slider:GetScript("OnMouseUp")(slider)
    row.Slider.Back:GetScript("OnClick")(row.Slider.Back)
    Same(Store:GetSoundVolume(), 90, "native decrement saves its lower volume")
    row.Slider.Forward:GetScript("OnClick")(row.Slider.Forward)
    Same(Store:GetSoundVolume(), 100, "native increment saves its higher volume")
    local calls = saveCalls
    row:SetValue(30)
    UI:RefreshWidgetSettings()
    Same(saveCalls, calls, "programmatic refresh never feeds back into persistence")
    Same(slider:GetValue(), 100, "refresh restores the actual saved preference")
    Stable()

    local function Visual()
        local state = {
            active = Toasts.active,
            name = Toasts.nameText:GetText(),
            caption = Toasts.captionText:GetText(),
            alpha = Toasts.frame:GetAlpha(),
            glow = Toasts.glow:IsShown(),
            sweep = Toasts.sweep:IsShown(),
            head = Toasts.queueHead,
            queue = Copy(Toasts.queue),
            names = Copy(Toasts.queuedNames),
            count = Toasts.queueCount,
            animations = {},
        }
        for _, animation in ipairs({ Toasts.animation, Toasts.flareAnimation, Toasts.sweepAnimation }) do
            state.animations[animation] = {
                elapsed = animation.elapsed,
                plays = animation.playCalls,
                stops = animation.stopCalls,
                playing = animation:IsPlaying(),
            }
        end
        return state
    end
    local function SameVisual(before)
        Same(Toasts.active, before.active, "volume preserves the active visual event")
        Same(Toasts.frame:IsShown(), true, "changing volume never hides an active visual")
        Same(Toasts.nameText:GetText(), before.name, "volume preserves the displayed player")
        Same(Toasts.captionText:GetText(), before.caption, "volume preserves the displayed milestone")
        Same(Toasts.frame:GetAlpha(), before.alpha, "volume preserves visual opacity")
        Same(Toasts.glow:IsShown(), before.glow, "volume preserves the current glow")
        Same(Toasts.sweep:IsShown(), before.sweep, "volume preserves the current sweep")
        Same(Toasts.queueCount, before.count, "volume retains queued events")
        Same(Toasts.queueHead, before.head, "volume cannot advance the queue")
        Equal(Toasts.queue, before.queue, "volume preserves queued event contents")
        Equal(Toasts.queuedNames, before.names, "volume preserves queued-player coalescing")
        for animation, state in pairs(before.animations) do
            Near(animation.elapsed, state.elapsed, "volume retains native animation progress")
            Same(animation.playCalls, state.plays, "volume does not replay visuals")
            Same(animation.stopCalls, state.stops, "volume does not cancel visuals")
            Same(animation:IsPlaying(), state.playing, "volume retains each animation's lifecycle")
        end
        Stable()
    end
    local _, foreignHandle = nativePlay("Interface\\AddOns\\OtherAddon\\Unrelated.ogg", "SFX")
    local soundCount = #Test.soundCalls
    Toasts:Enqueue({
        { name = "Current-TestRealm", streak = 5 },
        { name = "QueuedLower-TestRealm", streak = 6 },
        { name = "QueuedMuted-TestRealm", streak = 7 },
        { name = "QueuedLouder-TestRealm", streak = 8 },
    })
    Same(
        Test.soundCalls[#Test.soundCalls].path,
        ExpectedSound(5, 100),
        "initial toast uses the original full-volume clip"
    )
    Test.AdvanceAnimations(0.25)
    local visual, handle, stopped = Visual(), Toasts.soundHandle, #Test.stoppedSounds
    UI:SaveSoundVolume(55)
    Same(UI.actionError, Quiz.L.errors.invalid_sound_volume, "invalid UI save exposes the localized validation error")
    Same(Toasts.soundHandle, handle, "invalid UI save leaves current playback untouched")
    Same(#Test.stoppedSounds, stopped, "invalid UI save stops nothing")
    SameVisual(visual)
    UI:SaveSoundVolume(100)
    Same(Toasts.soundHandle, handle, "saving unchanged volume preserves current playback")
    Same(#Test.stoppedSounds, stopped, "unchanged volume does not stop a sound")
    UI:SaveSoundVolume(0)
    Same(Toasts.volume, 0, "mute reaches the renderer immediately")
    Same(UI.soundVolume, 0, "direct mute updates the settings cache")
    Same(slider:GetValue(), 0, "direct mute refreshes the native slider")
    Same(row.Value:GetText(), "0%", "direct mute refreshes the displayed percentage")
    Same(Toasts.soundHandle, nil, "mute clears its owned handle")
    Same(Test.stoppedSounds[#Test.stoppedSounds], handle, "mute stops the current owned clip")
    Same(#Test.stoppedSounds, stopped + 1, "mute stops exactly one sound")
    Same(Test.soundHandles[foreignHandle], true, "mute cannot stop another addon's sound")
    SameVisual(visual)
    UI:SaveSoundVolume(50)
    Same(#Test.soundCalls, soundCount + 1, "unmuting never replays the current clip")
    SameVisual(visual)
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(Toasts.active.name, "QueuedLower-TestRealm", "queued visuals continue in order")
    Same(
        Test.soundCalls[#Test.soundCalls].path,
        ExpectedSound(6, 50),
        "queued clip resolves the latest quieter volume at playback"
    )
    visual, handle, stopped = Visual(), Toasts.soundHandle, #Test.stoppedSounds
    UI:SaveSoundVolume(30)
    Same(Toasts.soundHandle, handle, "changing between audible levels preserves the current old-level clip")
    Same(Test.soundHandles[handle], true, "audible level changes let the current clip finish")
    Same(#Test.stoppedSounds, stopped, "an audible level change stops no native audio")
    SameVisual(visual)
    UI:SaveSoundVolume(0)
    Same(Test.stoppedSounds[#Test.stoppedSounds], handle, "mute still immediately stops the old-level clip")
    Same(#Test.stoppedSounds, stopped + 1, "only the explicit mute stops this clip")
    calls = #Test.soundCalls
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(Toasts.active.name, "QueuedMuted-TestRealm", "muted queue still advances its visual event")
    Same(Toasts.soundHandle, nil, "muted visual has no audio handle")
    Same(#Test.soundCalls, calls, "zero volume skips playback instead of making a silent native call")
    visual = Visual()
    UI:SaveSoundVolume(80)
    Same(#Test.soundCalls, calls, "unmuting a silent visual does not replay it")
    SameVisual(visual)
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(
        Test.soundCalls[#Test.soundCalls].path,
        ExpectedSound(8, 80),
        "remaining queued clip uses the newer louder variant"
    )
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(Toasts.active, nil, "volume changes do not prevent queue completion")
    Same(Toasts.queueCount, 0, "volume changes leave no retained queued events")
    Same(Toasts.frame:IsShown(), false, "drained queue still hides its visual")
    Same(#Test.soundCalls, soundCount + 3, "only the three audible events played once")
    Same(Test.soundHandles[foreignHandle], true, "all queue cleanup preserves unrelated audio")

    UI:SaveSoundVolume(100)
    Test.soundDuration = TOAST_SECONDS + 2
    Toasts:Enqueue({ { name = "LongClip-TestRealm", streak = 5 }, { name = "NextLevel-TestRealm", streak = 6 } })
    Test.soundDuration = nil
    handle, stopped, calls = Toasts.soundHandle, #Test.stoppedSounds, #Test.soundCalls
    Test.AdvanceAnimations(TOAST_SECONDS)
    visual = Visual()
    Check(Toasts.frame:GetScript("OnUpdate"), "long native playback keeps an active completion poll")
    UI:SaveSoundVolume(40)
    SameVisual(visual)
    Same(Toasts.soundHandle, handle, "volume changes preserve a still-playing tail after its visual finishes")
    Same(Test.soundHandles[handle], true, "changing volume does not clip an overlong native voice")
    Same(#Test.stoppedSounds, stopped, "nonzero changes cannot force-stop an audio tail")
    Same(#Test.soundCalls, calls, "changing volume cannot restart an audio tail")
    Test.AdvanceAudio(2.1)
    Toasts.frame:GetScript("OnUpdate")(Toasts.frame, 2.1)
    Same(Toasts.active.name, "NextLevel-TestRealm", "native completion releases the next volume-controlled event")
    Same(Test.soundCalls[#Test.soundCalls].path, ExpectedSound(6, 40), "next clip uses the deferred nonzero volume")
    Same(#Test.stoppedSounds, stopped, "natural completion preserves the entire preceding voice")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "new visual needs no stale audio-tail poll")
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(Toasts.active, nil, "deferred volume playback drains normally")
    Same(#Test.stoppedSounds, stopped, "no naturally finishing clip is stopped by the renderer")
    Same(Test.soundHandles[foreignHandle], true, "audio-tail handling also preserves unrelated sounds")

    UI:SaveSoundVolume(0)
    local result = {
        hostName = "ResultHost-TestRealm",
        session = "volume.1",
        id = 101,
        state = "results",
        correctIndex = 1,
        streakMilestones = { { name = "MutedResult-TestRealm", streak = 10 } },
    }
    calls = #Test.soundCalls
    Widget:RenderStreakToasts(result, true)
    Check(Toasts.active ~= nil, "a muted confirmed result still gets its visual announcement")
    local plays = Toasts.animation.playCalls
    UI:SaveSoundVolume(100)
    Widget:RenderStreakToasts(result, true)
    Same(Toasts.animation.playCalls, plays, "unmuting cannot replay an already consumed result")
    Same(#Test.soundCalls, calls, "unmuting cannot add sound to an already consumed result")
    Test.AdvanceAnimations(TOAST_SECONDS)
    Widget:RenderStreakToasts(result, true)
    Same(Toasts.active, nil, "completed muted results stay consumed after later refreshes")
    Same(#Test.soundCalls, calls, "completed muted results never acquire delayed sound")
    Stable()
    Widget.ApplySettings, Store.SaveSoundVolume = originalApply, originalSave
    PlaySoundFile, StopSound, SetCVar, C_CVar = nativePlay, nativeStop, nativeSetCVar, nativeCVarTable
    nativeStop(foreignHandle)
    UI.frame:Hide()
    Same(#Test.errors, 0, "volume settings produce no captured runtime errors")
    return assertions
end

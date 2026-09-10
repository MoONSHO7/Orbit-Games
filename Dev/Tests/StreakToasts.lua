local EPSILON = 0.000001
local TOAST_SECONDS = 3.2
local SOUND_POLL_SECONDS = 0.05
local BURST_DROP_PIXELS = 4
local BURST_SCALE = 0.8
local TEXT_GAP_PIXELS = 2
local QUEUE_LIMIT = 32
local DISPLAY_MODES = { { 1920, 1080, 0.71 }, { 1601, 901, 0.83 }, { 800, 600, 1.25 } }
local SOUND_FILES = {
    [5] = "dominating.mp3",
    [6] = "ownage.mp3",
    [7] = "rampage.mp3",
    [8] = "wicked-sick.mp3",
    [9] = "holyshit.mp3",
    [10] = "godlike.mp3",
}

return function(Games)
    local Quiz = Games.Quiz
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
    local function Count(values)
        local count = 0
        for _ in pairs(values) do
            count = count + 1
        end
        return count
    end
    local nativePlay, nativeStop = PlaySoundFile, StopSound
    local played, stopped, unavailable = {}, {}, false
    PlaySoundFile = function(path, channel)
        Same(channel, "SFX", "announcements respect the user's effects channel")
        Same(Count(Test.soundHandles), 0, "owned announcer clips never overlap")
        played[#played + 1] = { path = path, channel = channel }
        if unavailable == "throw" then
            error("simulated native audio decoder failure")
        end
        if unavailable then
            return false, nil
        end
        return nativePlay(path, channel)
    end
    StopSound = function(handle, fade)
        Same(handle, Quiz.StreakToasts.soundHandle, "cancellation stops only the owned current announcer handle")
        Same(fade, nil, "explicit cancellation stops its owned clip immediately")
        nativeStop(handle)
        stopped[#stopped + 1] = handle
    end

    local parent = CreateFrame("Frame", nil, UIParent)
    PixelUtil.SetPoint(parent, "TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    PixelUtil.SetSize(parent, 380, 160)
    local fonts = { answer = CreateFont("OrbitGamesToastTestAnswer"), winner = CreateFont("OrbitGamesToastTestWinner") }
    for _, font in pairs(fonts) do
        font:CopyFontObject(GameFontHighlight)
    end
    local drained = 0
    local Toasts = Quiz.StreakToasts:Create(parent, function()
        drained = drained + 1
    end)
    Same(Toasts:Create(parent), Toasts, "singleton renderer is reused")
    Toasts:ApplyStyle(fonts)
    PixelUtil.SetPoint(Toasts.frame, "TOPLEFT", parent, "TOPLEFT", 0, 0)
    Toasts:Layout(380, Toasts:GetPreferredHeight())
    Check(Toasts:GetPreferredHeight() >= 48, "toast has a stable preallocated footer height")
    Same(Toasts.frame.mouse, false, "toast cannot intercept answers or dragging")
    Same(Toasts.frame.clipsChildren, false, "the toast slot does not clip its deliberately lifted burst")
    Same(Toasts.frame:IsShown(), false, "no toast chrome is visible while idle")
    Same(Toasts.nameText:GetFontObject(), fonts.answer, "player name inherits the widget answer font")
    Same(Toasts.captionText:GetFontObject(), fonts.winner, "milestone inherits the widget footer font")
    Same(Toasts.nameText.wordWrap, true, "player names may wrap inside the slot")
    Same(Toasts.nameText.nonSpaceWrap, true, "long realm-qualified names can wrap")
    Same(Toasts.nameText.maxLines, 2, "name wrapping cannot grow the reserved slot")
    Same(Toasts.captionText.maxLines, 1, "milestone caption remains a compact single line")
    Same(Toasts.nameText:GetJustifyV(), "BOTTOM", "player name sits at the bottom of its reserved two-line area")
    Same(Toasts.captionText:GetJustifyV(), "TOP", "caption sits directly beneath the player's last line")
    Same(Toasts.background, nil, "toast has no rectangular background")
    Same(Toasts.accent, nil, "toast has no rectangular accent line")
    Same(Toasts.glow.atlas, "ArtifactsFX-StarBurst", "flare uses the native artifact burst")
    Same(Toasts.sweep.atlas, "ArtifactsFX-StarBurst", "sweep highlights the same burst silhouette")
    Same(
        Toasts.sweep:GetMaskTexture(1),
        Toasts.sweepMask,
        "moving shine masks the burst instead of drawing a rectangle"
    )
    Same(Toasts.sweep:GetMaskTexture(2), nil, "the burst requires only one mask")
    Same(Toasts.sweepMask.kind, "MaskTexture", "shine uses the native mask type")
    Same(Toasts.sweepMask.atlas, "ui-achievement-alert-glow-shine", "native shine supplies mask intensity")
    Same(Toasts.sweepMask.wrapHorizontal, "CLAMPTOBLACKADDITIVE", "mask clips beyond its horizontal bounds")
    Same(Toasts.sweepMask.wrapVertical, "CLAMPTOBLACKADDITIVE", "mask clips beyond its vertical bounds")
    Same(Toasts.sweepMove:GetTarget(), Toasts.sweepMask, "only the mask translates across the static burst")
    Same(Toasts.glow.blendMode, "ADD", "flare is additive")
    Same(Toasts.sweep.blendMode, "ADD", "sweep is additive")
    Near(Toasts.animation:GetDuration(), TOAST_SECONDS, "visual lifetime is independent from native sound completion")
    Check(Toasts.sweepAnimation:GetDuration() < TOAST_SECONDS, "sweep finishes within its toast")
    Check(Toasts.flareAnimation:GetDuration() < TOAST_SECONDS, "flare finishes within its toast")
    Same(Toasts.captionAnimation, nil, "streak captions have no grow-shrink animation")
    for _, group in ipairs({ Toasts.frame:GetAnimationGroups() }) do
        for _, effect in ipairs({ group:GetAnimations() }) do
            Check(
                effect.kind ~= "Scale" or effect:GetTarget() ~= Toasts.captionText,
                "no native scale animation targets the streak caption"
            )
        end
    end

    for _, entry in ipairs({
        { Toasts.animation, Toasts.frame },
        { Toasts.flareAnimation, Toasts.glow },
        { Toasts.sweepAnimation, Toasts.sweep },
    }) do
        local animation, region = unpack(entry)
        Same(animation:GetParent(), Toasts.frame, "effect groups share the toast owner")
        Same(animation:IsSetToFinalAlpha(), true, "completed fades retain their final alpha")
        for _, effect in ipairs({ animation:GetAnimations() }) do
            if effect.kind == "Alpha" then
                Same(effect:GetTarget(), region, "fade explicitly targets its intended region")
            end
        end
    end
    local regions = { Toasts.frame, Toasts.nameText, Toasts.captionText, Toasts.glow, Toasts.sweep, Toasts.sweepMask }
    local geometry = {}
    for _, region in ipairs(regions) do
        geometry[region] = {
            region.setPointCalls or 0,
            region.clearPointCalls or 0,
            region.sizeCalls or 0,
        }
    end
    local frames, labels, textures, animations =
        #Test.frames, Test.fontStringCreations, Test.textureCreations, Test.animationCreations
    local masks = Test.maskCreations
    local captionFont = { Toasts.captionText:GetFont() }
    local function Stable()
        Same(#Test.frames, frames, "announcements reuse their frame")
        Same(Test.fontStringCreations, labels, "announcements reuse their labels")
        Same(Test.textureCreations, textures, "announcements reuse their flare art")
        Same(Test.maskCreations, masks, "announcements reuse their native mask")
        Same(Test.animationCreations, animations, "announcements reuse their animation groups")
        Same(Toasts.captionText.fontCalls, nil, "pulse never sets an inline font")
        Same(Toasts.captionText.scale, nil, "pulse never mutates the caption's layout scale")
        for index, value in ipairs({ Toasts.captionText:GetFont() }) do
            Same(value, captionFont[index], "caption pulse leaves font file, size and flags unchanged")
        end
        for _, region in ipairs(regions) do
            local previous = geometry[region]
            Same(region.setPointCalls or 0, previous[1], "toast appearance does not reposition a region")
            Same(region.clearPointCalls or 0, previous[2], "toast appearance does not clear anchors")
            Same(region.sizeCalls or 0, previous[3], "toast appearance does not resize its reserved slot")
        end
    end
    local events = {}
    for streak = 5, 11 do
        events[#events + 1] = { name = "Milestone" .. streak .. "-ForeignRealm", streak = streak }
    end
    Toasts:Enqueue(events)
    for index, event in ipairs(events) do
        Same(Toasts.active.name, event.name, "all simultaneous players receive their own toast")
        Same(Toasts.nameText:GetText(), event.name, "the full player identity is supplied to the label")
        Same(Toasts.active.streak, event.streak, "toast retains the committed consecutive count")
        Same(
            Toasts.captionText:GetText(),
            tostring(event.streak) .. " in a row",
            "caption contains no sound-tier title"
        )
        local file = SOUND_FILES[math.min(event.streak, 10)]
        Same(
            played[index].path,
            "Interface\\AddOns\\Orbit-Games\\Assets\\Sounds\\" .. file,
            "exact requested clip is used"
        )
        Same(Toasts.queueCount, #events - index, "simultaneous announcements are serialized")
        Same(Toasts.frame:IsShown(), true, "active announcement is visible")
        Near(
            Toasts.flareAnimation.elapsed,
            0,
            "every queued toast starts a fresh flare rather than inheriting elapsed time"
        )
        Same(Toasts.glow:GetAlpha(), 1, "a reused burst resets the preceding toast's final alpha")
        Same(Toasts.sweep:IsShown(), true, "each next toast restarts its moving highlight")
        Stable()
        if index == 1 then
            Test.AdvanceAnimations(0.9 + EPSILON)
            Same(Toasts.glow:IsShown(), true, "burst remains visible after its opening flare")
            Near(Toasts.glow:GetAlpha(), 0.35, "flare settles to a dim persistent burst")
            Test.AdvanceAnimations(0.2 + EPSILON)
            Same(Toasts.sweep:IsShown(), false, "the moving highlight disappears after crossing the burst")
            Test.AdvanceAnimations(2.1 + EPSILON)
        else
            Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        end
    end
    Same(Toasts.frame:IsShown(), false, "footer disappears after the finite queue drains")
    Same(Toasts.active, nil, "drained renderer has no active event")
    Same(Toasts.soundHandle, nil, "drained renderer retains no sound handle")
    Same(#played, #events, "each queued milestone plays once")
    Same(#stopped, 0, "natural audio completion never calls StopSound")
    Same(drained, 1, "queue completion notifies its owner once")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "normally finishing clips require no audio polling")
    Same(Count(Toasts.queuedNames), 0, "drained name index retains no history")
    Same(Count(Toasts.queue), 0, "drained queue retains no history")
    Toasts:Enqueue({})
    Toasts:Clear()
    Toasts:Clear()
    Stable()

    local original = { name = "First-TestRealm", streak = 5 }
    Toasts:Enqueue({ original })
    original.name, original.streak = "Mutated", 999
    Same(Toasts.active.name, "First-TestRealm", "renderer detaches events from the caller")
    Same(Toasts.active.streak, 5, "caller mutation cannot change an active milestone")
    Toasts:Enqueue({ { name = "Queued-TestRealm", streak = 5 } })
    Toasts:Enqueue({ { name = "Queued-TestRealm", streak = 6 }, { name = "Another-TestRealm", streak = 7 } })
    Toasts:Enqueue({ { name = "Queued-TestRealm", streak = 8 } })
    Same(Toasts.queueCount, 2, "pending announcements coalesce by player rather than building a stale backlog")
    Same(Toasts.active.streak, 5, "coalescing does not interrupt the current clip")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(Toasts.active.name, "Queued-TestRealm", "coalescing preserves queued player order")
    Same(Toasts.active.streak, 8, "queued player presents the newest committed milestone")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(Toasts.active.name, "Another-TestRealm", "coalescing does not discard other players")
    Toasts:Clear()
    Same(Count(Test.soundHandles), 0, "clear stops only the owned active audio")
    Same(Toasts.queueCount, 0, "clear discards pending announcements")
    Same(Toasts.frame:IsShown(), false, "clear immediately hides the ribbon")
    for _, animation in ipairs({
        Toasts.animation,
        Toasts.flareAnimation,
        Toasts.sweepAnimation,
    }) do
        Same(animation:IsPlaying(), false, "clear cancels every owned animation")
    end
    local before = #played
    Test.AdvanceAnimations(TOAST_SECONDS * 2)
    Same(#played, before, "cancelled animation callbacks cannot resurrect audio")

    Toasts:Enqueue({ { name = "DeepStreak-TestRealm", streak = 25 }, { name = "LowStreak-TestRealm", streak = 5 } })
    Same(Toasts.captionAnimation, nil, "deep streaks retain fixed-size captions")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(Toasts.active.streak, 5, "queue can advance from a high to a low streak")
    Stable()
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)

    events = {}
    for index = 1, QUEUE_LIMIT * 3 do
        events[index] = { name = "Overflow" .. index .. "-TestRealm", streak = 5 }
    end
    Toasts:Enqueue(events)
    Same(Toasts.queueCount, QUEUE_LIMIT - 1, "queue has a fixed memory cap")
    Same(Count(Toasts.queuedNames), QUEUE_LIMIT - 1, "pending-player index has the same cap")
    Same(Count(Toasts.queue), QUEUE_LIMIT - 1, "ring storage never retains overwritten events")
    Same(Toasts.active.name, "Overflow65-TestRealm", "overflow drops oldest pending announcements")
    Toasts:Clear()
    unavailable = true
    before = #played
    Toasts:Enqueue({ { name = "Muted-TestRealm", streak = 9 }, { name = "StillVisible-TestRealm", streak = 10 } })
    Same(Toasts.frame:IsShown(), true, "unavailable audio does not suppress the visual announcement")
    Same(Toasts.soundHandle, nil, "failed playback never records an unusable handle")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(Toasts.active.name, "StillVisible-TestRealm", "failed playback does not stall the queue")
    Same(#played, before + 2, "muted clips are attempted once without repeated retries")
    Toasts:Clear()
    unavailable = "throw"
    Toasts:Enqueue({ { name = "BrokenAsset-TestRealm", streak = 6 }, { name = "FollowingAsset-TestRealm", streak = 7 } })
    Same(Toasts.frame:IsShown(), true, "throwing native audio still leaves the visual announcement active")
    Same(Toasts.soundHandle, nil, "native audio errors cannot install an invalid handle")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(Toasts.active.name, "FollowingAsset-TestRealm", "an audio decode error cannot stall queue progression")
    Toasts:Clear()
    unavailable = false

    local function Poll(seconds)
        Test.AdvanceAudio(seconds)
        local update = Toasts.frame:GetScript("OnUpdate")
        if update then
            update(Toasts.frame, seconds)
        end
    end
    local function StartAudioTail(delay)
        Test.soundDuration = not delay and TOAST_SECONDS + 2 or nil
        Test.soundDelay = delay
        Toasts:Enqueue({
            { name = "AudioTail-TestRealm", streak = 5 },
            { name = "AfterAudioTail-TestRealm", streak = 6 },
        })
        Test.soundDuration, Test.soundDelay = nil, nil
        local event, handle = Toasts.active, Toasts.soundHandle
        Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
        Same(Toasts.active, event, "visual completion retains an unfinished native sound")
        Same(Toasts.soundHandle, handle, "audio tail retains its owned native handle")
        Same(Test.soundHandles[handle], true, "the native clip is still playing past the visual lifetime")
        Same(Toasts.animation:IsPlaying(), false, "audio waiting does not extend or replay the visual animation")
        Same(Toasts.frame:GetAlpha(), 0, "completed visual stays transparent throughout the audio tail")
        Check(Toasts.frame:GetScript("OnUpdate"), "only an unfinished audio tail installs a completion poll")
        Same(Toasts.queueCount, 1, "pending milestone cannot overlap an unfinished voice")
        return event, handle
    end
    local stopsBefore, drainsBefore = #stopped, drained
    local event, handle = StartAudioTail()
    Same(#stopped, stopsBefore, "even an unexpectedly long clip is not stopped by its visual")
    Same(drained, drainsBefore, "visual completion cannot signal a drained audio queue")
    before = #played
    Toasts:Enqueue({ { name = "AfterAudioTail-TestRealm", streak = 7 } })
    Same(#played, before, "late queued updates cannot interrupt an active audio tail")
    local checks = Test.soundChecks
    Poll(0.02)
    Poll(0.02)
    Same(Test.soundChecks, checks, "native completion checks are throttled, not queried every frame")
    Poll(0.01 + EPSILON)
    Same(Test.soundChecks, checks + 1, "the first audio poll waits the configured interval")
    Same(Toasts.active, event, "a still-playing poll cannot advance the toast")
    Poll(0.5)
    Same(Test.soundChecks, checks + 2, "a delayed frame checks audio once rather than catching up in a loop")
    Poll(2)
    Same(Toasts.active.name, "AfterAudioTail-TestRealm", "native sound completion releases the next queued milestone")
    Same(Toasts.active.streak, 7, "coalescing remains valid while waiting for audio")
    Same(Test.soundHandles[handle], nil, "the finished clip ends natively")
    Same(#stopped, stopsBefore, "native tail completion never forcibly stops any clip")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "polling detaches before the next visual starts")
    Same(Toasts.frame:GetAlpha(), 1, "next toast resets its parent's final alpha")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(drained, drainsBefore + 1, "drained callback waits for the final native clip")
    Same(Toasts.active, nil, "overlong audio cannot stall a naturally completed queue")

    stopsBefore = #stopped
    StartAudioTail(3)
    Poll(1.8)
    Same(Toasts.active.name, "AfterAudioTail-TestRealm", "native startup delay is allowed beyond the visual deadline")
    Same(#stopped, stopsBefore, "delayed playback is never cut off at a guessed duration")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)

    event, handle = StartAudioTail()
    drainsBefore, before = drained, #played
    Toasts:Clear()
    Same(Test.soundHandles[handle], nil, "explicit clear immediately stops an unfinished audio tail")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "clear removes the audio-tail poll")
    Same(Toasts.frame:IsShown(), false, "clear hides a waiting transparent toast")
    Same(Toasts.active, nil, "clear discards its active audio-tail event")
    Same(drained, drainsBefore, "cancellation is not mistaken for natural queue completion")
    Poll(10)
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(#played, before, "cancelled audio tails cannot resurrect pending announcements")
    Same(drained, drainsBefore, "cancelled audio tails cannot later notify a drained preview")

    event, handle = StartAudioTail()
    before = #played
    Toasts:SetSoundsEnabled(false)
    Same(Test.soundHandles[handle], nil, "mute immediately stops an audio tail")
    Same(Toasts.soundHandle, nil, "muting clears ownership of the cancelled audio")
    Poll(SOUND_POLL_SECONDS)
    Same(Toasts.active.name, "AfterAudioTail-TestRealm", "muting releases the pending silent visual at the next poll")
    Same(Toasts.soundHandle, nil, "muted next milestone has no native playback")
    Same(Toasts.frame:GetScript("OnUpdate"), nil, "muting cannot leave an idle sound poll")
    Toasts:SetSoundsEnabled(true)
    Same(#played, before, "unmuting never replays an already consumed milestone")
    Test.AdvanceAnimations(TOAST_SECONDS + EPSILON)
    Same(Toasts.active, nil, "muted audio-tail queue still drains")
    Stable()

    local function GridAndBounds()
        local left, bottom, width, height = Toasts.frame:GetScaledRect()
        local pixel = PixelUtil.GetPixelToUIUnitFactor()
        for _, region in ipairs(regions) do
            local x, y, regionWidth, regionHeight = region:GetScaledRect()
            if region == Toasts.frame or region == Toasts.nameText or region == Toasts.captionText then
                Check(x >= left - EPSILON and y >= bottom - EPSILON, "toast content stays inside its slot")
                Check(x + regionWidth <= left + width + EPSILON, "toast content respects the right edge")
                Check(y + regionHeight <= bottom + height + EPSILON, "toast content respects the top edge")
            end
            for _, edge in ipairs({ x, y, x + regionWidth, y + regionHeight }) do
                Near(edge / pixel, math.floor(edge / pixel + 0.5), "toast content edges stay on the physical grid")
            end
        end
        local glowLeft, glowBottom, glowWidth, glowHeight = Toasts.glow:GetScaledRect()
        Near(glowLeft + glowWidth / 2, left + width / 2, "smaller burst preserves its horizontal center")
        Near(
            (glowBottom + glowHeight / 2 - bottom - height / 2) / pixel,
            -BURST_DROP_PIXELS,
            "burst center sits four physical pixels below its text slot center"
        )
        Check(
            math.abs(glowWidth - width * BURST_SCALE) <= pixel + EPSILON,
            "burst width is twenty percent smaller within pixel rounding"
        )
        Check(
            math.abs(glowHeight - height * BURST_SCALE) <= pixel + EPSILON,
            "burst height is twenty percent smaller within pixel rounding"
        )
        for index, value in ipairs({ Toasts.sweep:GetScaledRect() }) do
            Near(
                value,
                ({ glowLeft, glowBottom, glowWidth, glowHeight })[index],
                "masked shine follows the lifted burst"
            )
        end
        local offsetX, offsetY = Toasts.sweepMove:GetOffset()
        local maskLeft, maskBottom, maskWidth, maskHeight = Toasts.sweepMask:GetScaledRect()
        Near(maskLeft + maskWidth, glowLeft, "shine mask begins immediately outside the smaller burst's left edge")
        Near(maskBottom, glowBottom, "shine mask follows the burst's vertical lift")
        Near(maskHeight, glowHeight, "shine mask retains the lifted burst's full height")
        Same(Toasts.sweepMask.point[2], Toasts.glow, "shine mask anchors to the burst rather than its old slot")
        Near(
            maskLeft + offsetX * Toasts.frame:GetEffectiveScale(),
            glowLeft + glowWidth,
            "shine mask finishes past the smaller burst's right edge"
        )
        Same(Toasts.sweep:GetWidth(), Toasts.glow:GetWidth(), "masked highlight retains the full burst silhouette")
        Same(offsetY, 0, "shine mask does not translate vertically")
        local _, nameBottom = Toasts.nameText:GetScaledRect()
        local _, captionBottom, _, captionHeight = Toasts.captionText:GetScaledRect()
        local gapPixels = (nameBottom - captionBottom - captionHeight) / pixel
        if height / pixel >= TEXT_GAP_PIXELS * 8 then
            Near(gapPixels, TEXT_GAP_PIXELS, "name and caption stack with a two-physical-pixel gap")
        else
            Check(
                gapPixels >= -EPSILON and gapPixels <= TEXT_GAP_PIXELS + EPSILON,
                "tiny slots only reduce the text gap"
            )
        end
        Same(Toasts.nameText:GetJustifyV(), "BOTTOM", "restyling preserves the name's lower alignment")
        Same(Toasts.captionText:GetJustifyV(), "TOP", "restyling preserves the caption's upper alignment")
        for _, label in ipairs({ Toasts.nameText, Toasts.captionText }) do
            local shadowX, shadowY = label:GetShadowOffset()
            local scale = label:GetEffectiveScale()
            Near(shadowX * scale / pixel, 2, "toast horizontal shadow is two physical pixels")
            Near(shadowY * scale / pixel, -2, "toast vertical shadow is two physical pixels")
        end
    end
    for _, display in ipairs(DISPLAY_MODES) do
        Test.physicalWidth, Test.physicalHeight = display[1], display[2]
        UIParent:SetScale(display[3])
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        UIParent:SetSize(display[1] * factor / display[3], display[2] * factor / display[3])
        for percent = 50, 200, 5 do
            parent:SetScale(percent / 100)
            Toasts:ApplyStyle(fonts)
            for _, dimensions in ipairs({ { 380, Toasts:GetPreferredHeight() }, { 80, 36 }, { 9, 8 }, { 0, 0 } }) do
                Toasts:Layout(dimensions[1], dimensions[2])
                GridAndBounds()
            end
        end
    end
    Toasts:Clear()
    PlaySoundFile, StopSound = nativePlay, nativeStop
    return assertions
end

local TOAST_SECONDS = 3.21

return function(Games)
    local Quiz = Games.Quiz
    local Store, SettingsPage, Toasts = Quiz.Store, Quiz.SettingsPage, Quiz.StreakToasts
    local assertions = 0
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function Initialize(saved)
        local db, reason = Store:Initialize(saved)
        Check(db ~= nil, "sound preferences load: " .. tostring(reason))
        return db
    end

    Same(Initialize(nil).soundsEnabled, true, "new installations enable sounds")
    for version = 1, 7 do
        Same(Initialize({ schemaVersion = version }).soundsEnabled, true, "missing preference defaults to on")
        for _, volume in ipairs({ 0, 10, 100 }) do
            local saved = { schemaVersion = version, soundVolume = volume }
            local db = Initialize(saved)
            Same(db.soundsEnabled, volume ~= 0, "legacy migration preserves mute")
            Same(db.soundVolume, nil, "migration drops the obsolete volume")
            Same(saved.soundVolume, volume, "migration leaves its input untouched")
        end
    end
    for _, enabled in ipairs({ false, true }) do
        local db = Initialize({ schemaVersion = 7, soundsEnabled = enabled, soundVolume = 0 })
        Same(db.soundsEnabled, enabled, "explicit sound toggle takes precedence over legacy volume")
        Same(Initialize(db).soundsEnabled, enabled, "sound preference survives reload")
    end
    for _, value in ipairs({ 0, 1, "off", {}, 0 / 0 }) do
        local db, reason = Store:Normalize({ schemaVersion = 7, soundsEnabled = value })
        Same(db, nil, "invalid saved sound preference rejects")
        Same(reason, "invalid_sounds_enabled", "invalid preference has a localized error")
        local before = Store:GetSoundsEnabled()
        Check(not Store:SaveSoundsEnabled(value), "invalid sound writes reject")
        Same(Store:GetSoundsEnabled(), before, "failed writes preserve the preference")
    end

    local db = Initialize({ schemaVersion = 7, soundsEnabled = false })
    OrbitGamesDB.modes.quiz = db
    local otherData = {}
    for key, value in pairs(db) do
        if key ~= "soundsEnabled" then
            otherData[key] = value
        end
    end
    Games.UI:Toggle()
    Games.UI:SetTab("settings")
    Same(Toasts.soundsEnabled, false, "renderer starts with the saved mute preference")
    Same(SettingsPage.soundsEnabled, false, "settings reflect the saved preference")
    Check(SettingsPage.sounds:GetTop() < SettingsPage.fontRow:GetBottom(), "sound control sits below Font")

    local function Pick(enabled)
        SettingsPage.sounds:OpenMenu()
        for _, entry in ipairs(SettingsPage.sounds:GetMenuDescription().entries) do
            if entry:GetData() == enabled then
                Check(entry:Pick(), "native sound selection succeeds")
                Same(Store:GetSoundsEnabled(), enabled, "menu selection persists")
                Same(Toasts.soundsEnabled, enabled, "menu selection reaches playback")
                return
            end
        end
        error("missing sound menu option")
    end
    local nativeSetCVar, nativeCVarTable = SetCVar, C_CVar
    local function RejectCVar()
        error("sound preferences must not change global game sound settings")
    end
    SetCVar, C_CVar = RejectCVar, { SetCVar = RejectCVar }
    Pick(true)
    local _, foreignHandle = PlaySoundFile("Interface\\AddOns\\OtherAddon\\Unrelated.ogg", "SFX")
    Toasts:Enqueue({ { name = "Current-TestRealm", streak = 5 }, { name = "Queued-TestRealm", streak = 6 } })
    local handle, active, queueCount = Toasts.soundHandle, Toasts.active, Toasts.queueCount
    Check(handle ~= nil, "enabled announcement plays a sound")
    local soundCount = #Test.soundCalls
    SettingsPage:SaveSoundsEnabled("off")
    Same(Games.UI.actionError, Quiz.L.errors.invalid_sounds_enabled, "invalid UI save reports its error")
    Same(Toasts.soundHandle, handle, "invalid save leaves playback untouched")
    Pick(false)
    Same(Test.soundHandles[handle], nil, "mute stops the owned sound immediately")
    Same(Test.soundHandles[foreignHandle], true, "mute leaves other sounds playing")
    Same(Toasts.active, active, "mute preserves the active visual")
    Same(Toasts.queueCount, queueCount, "mute preserves queued announcements")
    Check(Toasts.animation:IsPlaying(), "mute leaves the visual animation running")
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(Toasts.active.name, "Queued-TestRealm", "muted queue continues visually")
    Same(#Test.soundCalls, soundCount, "muted announcements play no sound")
    Pick(true)
    Same(#Test.soundCalls, soundCount, "unmuting does not replay a consumed announcement")
    Test.AdvanceAnimations(TOAST_SECONDS)
    Same(Toasts.active, nil, "queue drains normally")
    Toasts:Enqueue({ { name = "Next-TestRealm", streak = 7 } })
    Same(#Test.soundCalls, soundCount + 1, "future announcements resume audio")
    for key, value in pairs(otherData) do
        Same(db[key], value, "sound changes preserve unrelated saved data: " .. key)
    end
    Same(Initialize(db).soundsEnabled, true, "menu preference survives reload")
    SettingsPage.sounds:OpenMenu()
    SettingsPage:CloseMenus()
    Check(not SettingsPage.sounds:IsMenuOpen(), "closing settings closes the sound menu")
    Toasts:Clear()
    StopSound(foreignHandle)
    SetCVar, C_CVar = nativeSetCVar, nativeCVarTable
    return assertions
end

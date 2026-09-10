return function(Games)
    local Store = Games.Store
    local assertions = 0

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Copy(value)
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, entry in pairs(value) do
            copy[key] = Copy(entry)
        end
        return copy
    end

    local function Equal(actual, expected, message)
        for key, value in pairs(expected) do
            if type(value) == "table" then
                Equal(actual[key], value, message .. "." .. tostring(key))
            else
                Same(actual[key], value, message .. "." .. tostring(key))
            end
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " has no unexpected field " .. tostring(key))
        end
    end

    local function Initialize(saved)
        local db, reason = Store:Initialize(saved)
        Check(db ~= nil, "host audiences load: " .. tostring(reason))
        Same(db.schemaVersion, 1, "host audiences remain an additive root-schema field")
        return db
    end

    local all = { server = true, guild = true, party = true }
    local fresh = Initialize(nil)
    Equal(fresh.hostAudiences, all, "fresh databases advertise everywhere")
    Equal(Store:GetHostAudiences(), all, "the public getter exposes the fresh defaults")

    local detached = Store:GetHostAudiences()
    detached.server = false
    Same(Store:GetHostAudiences().server, true, "callers cannot mutate the saved selection through the getter")

    local combinations = {
        { server = true, guild = false, party = false },
        { server = false, guild = true, party = false },
        { server = false, guild = false, party = true },
        { server = true, guild = true, party = false },
        { server = true, guild = false, party = true },
        { server = false, guild = true, party = true },
        { server = true, guild = true, party = true },
    }
    for index, selection in ipairs(combinations) do
        local input = Copy(selection)
        input.unrecognized = true
        local changed, reason = Store:SaveHostAudiences(input)
        Check(changed, "valid audience combination " .. index .. " saves: " .. tostring(reason))
        Equal(Store:GetHostAudiences(), selection, "valid audience combination " .. index .. " round-trips")
        Same(Store.db.hostAudiences.unrecognized, nil, "unknown audience fields are not persisted")
        input.server = not input.server
        Equal(Store:GetHostAudiences(), selection, "saved audience input " .. index .. " remains detached")
        local unchanged, unchangedReason = Store:SaveHostAudiences(selection)
        Same(unchanged, false, "saving the same audience combination is a no-op")
        Same(unchangedReason, "unchanged", "unchanged audience saves report the stable reason")
    end

    local beforeInvalid = Copy(Store:GetHostAudiences())
    for index, selection in ipairs({
        "server",
        {},
        { server = true, guild = true },
        { server = true, guild = true, party = 1 },
        { server = true, guild = "yes", party = false },
        { server = false, guild = false, party = false },
    }) do
        local changed, reason = Store:SaveHostAudiences(selection)
        Same(changed, false, "malformed audience selection " .. index .. " rejects")
        Same(reason, "invalid_host_audiences", "malformed selection reports the stable error")
        Equal(Store:GetHostAudiences(), beforeInvalid, "malformed save " .. index .. " is atomic")
    end
    local changed, reason = Store:SaveHostAudiences(nil)
    Same(changed, false, "a nil audience selection rejects")
    Same(reason, "invalid_host_audiences", "nil selection reports the stable error")
    Equal(Store:GetHostAudiences(), beforeInvalid, "nil save is atomic")

    local legacy = { schemaVersion = 1 }
    local legacyBefore = Copy(legacy)
    local defaulted = Initialize(legacy)
    Equal(defaulted.hostAudiences, all, "a current database without the additive field receives safe defaults")
    Equal(legacy, legacyBefore, "defaulting host audiences never mutates the restored input")

    local saved = {
        schemaVersion = 1,
        hostAudiences = { server = false, guild = true, party = false },
    }
    local savedBefore = Copy(saved)
    local restored = Initialize(saved)
    Equal(restored.hostAudiences, saved.hostAudiences, "a persisted audience subset survives reload")
    Equal(saved, savedBefore, "restoring a saved audience subset never mutates the input")

    local committed = Store.db
    for index, invalid in ipairs({
        "guild",
        {},
        { server = true, guild = false },
        { server = true, guild = false, party = "false" },
        { server = false, guild = false, party = false },
    }) do
        local invalidSaved = { schemaVersion = 1, hostAudiences = invalid }
        local invalidBefore = Copy(invalidSaved)
        local loaded, loadReason = Store:Initialize(invalidSaved)
        Same(loaded, nil, "malformed restored audience selection " .. index .. " rejects")
        Same(loadReason, "invalid_host_audiences", "restoration reports the stable audience error")
        Same(Store.db, committed, "failed audience restoration retains the committed database")
        Equal(invalidSaved, invalidBefore, "failed audience restoration never edits its input")
    end

    return assertions
end

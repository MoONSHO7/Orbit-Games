local _, Games = ...
local Quiz = Games.Quiz
local MIN_STREAK = 5
local MAX_MILESTONES = 17
local MAX_SPEAKERS = 64
local MAX_NAME_BATCH = 4
local MAX_INTEGER = 9007199254740990
local MAX_ENCODED_BYTES = MAX_MILESTONES * 34 - 1
local MAP_INTERVAL = 0.125
local MAP_RETRY = 2

Quiz.StreakSync = {}

local function Send(target, fields, tag)
    return Games.Comms:Send(target, Quiz.id, fields, tag)
end
local StreakSync = Quiz.StreakSync

local function Integer(text, minimum)
    if type(text) ~= "string" or not text:match("^[1-9]%d*$") then
        return nil
    end
    local value = tonumber(text)
    if value and value >= minimum and value <= MAX_INTEGER and string.format("%.0f", value) == text then
        return value
    end
end

local function IdText(value)
    return string.format("%.0f", value)
end

local function Split(text)
    local values = {}
    for value in text:gmatch("[^,]+") do
        if #values >= MAX_NAME_BATCH then
            return nil
        end
        values[#values + 1] = value
    end
    return #values > 0 and table.concat(values, ",") == text and values or nil
end

local function NewSpeakers()
    return { entries = {}, byName = {}, count = 0, sequence = 0, evictedThrough = 0 }
end

local function IsPinned(session, id, entry)
    if entry.name:lower() == Games.Identity.name:lower() or session.peers[entry.name:lower()] then
        return true
    end
    local result = Quiz.Controller.game and Quiz.Controller.game.lastResult
    for _, milestone in ipairs(result and result.streakReferences or {}) do
        if milestone.id == id then
            return true
        end
    end
    return false
end

function StreakSync:Initialize(session)
    session.streakSpeakers = NewSpeakers()
    session.nextStreakMapAt = 0
end

function StreakSync:Register(session, name)
    name = Games.Identity:NormalizeName(name)
    if not name then
        return nil
    end
    local speakers, key = session.streakSpeakers, name:lower()
    local existing = speakers.byName[key]
    if existing then
        return existing
    end
    if speakers.count >= MAX_SPEAKERS then
        speakers.entries, speakers.byName, speakers.count = {}, {}, 0
        for _, peer in pairs(session.peers) do
            self:ResetPeer(peer)
        end
        self:Register(session, Games.Identity.name)
        for _, peer in pairs(session.peers) do
            self:Register(session, peer.name)
        end
        return self:Register(session, name)
    end
    if speakers.sequence >= MAX_INTEGER then
        return nil
    end
    speakers.sequence = speakers.sequence + 1
    local id = speakers.sequence
    speakers.entries[id] = { name = name }
    speakers.byName[key] = id
    speakers.count = speakers.count + 1
    return id
end

function StreakSync:ResetPeer(peer)
    peer.streakAcknowledged, peer.streakSent = {}, {}
end

function StreakSync:Encode(session, result)
    if result.streakEncoding then
        return result.streakEncoding
    end
    local references = {}
    for _, milestone in ipairs(result.streakMilestones) do
        local id = self:Register(session, milestone.name)
        if id and #references < MAX_MILESTONES then
            references[#references + 1] = { id = id, streak = milestone.streak }
        end
    end
    table.sort(references, function(left, right)
        return left.id < right.id
    end)
    local pieces = {}
    for index, entry in ipairs(references) do
        pieces[index] = IdText(entry.id) .. ":" .. IdText(entry.streak)
    end
    result.streakReferences, result.streakEncoding = references, table.concat(pieces, ",")
    return result.streakEncoding
end

function StreakSync:Decode(text, correctCount)
    if type(text) ~= "string" or #text > MAX_ENCODED_BYTES then
        return nil
    end
    local references, pieces, previous = {}, {}, 0
    for piece in text:gmatch("[^,]+") do
        local idText, streakText = piece:match("^(%d+):(%d+)$")
        local id, streak = Integer(idText, 1), Integer(streakText, MIN_STREAK)
        if not id or not streak or id <= previous or #references >= math.min(MAX_MILESTONES, correctCount) then
            return nil
        end
        references[#references + 1] = { id = id, streak = streak }
        pieces[#pieces + 1], previous = piece, id
    end
    return table.concat(pieces, ",") == text and references or nil
end

function StreakSync:RefreshView(client, view)
    if not view.correctIndex or not view.streakReferences or view.streakMilestonesComplete then
        return
    end
    local milestones, names, incomplete = {}, {}, false
    for _, reference in ipairs(view.streakReferences) do
        local entry = client.streakSpeakers and client.streakSpeakers.entries[reference.id]
        if not entry then
            incomplete = true
        else
            local key = entry.name:lower()
            if names[key] or key == Games.Identity.name:lower() and reference.streak ~= view.streak then
                view.suppressStreakToasts = true
                return
            end
            names[key] = true
            milestones[#milestones + 1] = { name = entry.name, streak = reference.streak }
        end
    end
    if not incomplete and view.streak >= MIN_STREAK and not names[Games.Identity.name:lower()] then
        view.suppressStreakToasts = true
        return
    end
    table.sort(milestones, function(left, right)
        if left.streak ~= right.streak then
            return left.streak > right.streak
        end
        return left.name:lower() < right.name:lower()
    end)
    view.streakMilestonesComplete = not incomplete
    if not view.streakMilestones or #milestones > #view.streakMilestones then
        view.streakMilestones = milestones
    end
end

function StreakSync:ReceiveName(client, view, fields)
    if fields[3] ~= client.request then
        return false
    end
    local ids, names = Split(fields[4]), Split(fields[5])
    if not ids or not names or #ids ~= #names then
        return false
    end
    local speakers = client.streakSpeakers or NewSpeakers()
    local firstId = Integer(ids[1], 1)
    local generation = firstId and math.floor((firstId - 1) / MAX_SPEAKERS) * MAX_SPEAKERS
    if not generation or generation < speakers.evictedThrough then
        return false
    end
    if generation > speakers.evictedThrough then
        speakers = NewSpeakers()
        speakers.evictedThrough = generation
    end
    local previousId, uniqueNames = 0, {}
    for index, idText in ipairs(ids) do
        local id, name = Integer(idText, 1), Games.Identity:NormalizeName(names[index])
        if
            not id
            or not name
            or name ~= names[index]
            or id <= math.max(previousId, speakers.evictedThrough)
            or id > generation + MAX_SPEAKERS
            or uniqueNames[name:lower()]
            or speakers.entries[id] and speakers.entries[id].name ~= name
            or speakers.byName[name:lower()] and speakers.byName[name:lower()] ~= id
        then
            return false
        end
        ids[index], previousId, uniqueNames[name:lower()] = id, id, true
    end
    for index, id in ipairs(ids) do
        if not speakers.entries[id] then
            speakers.count = speakers.count + 1
        end
        speakers.entries[id] = { name = names[index] }
        speakers.byName[names[index]:lower()] = id
    end
    client.streakSpeakers = speakers
    Send(client.name, { "B", client.session, client.request, fields[4] })
    self:RefreshView(client, view)
    return true
end

function StreakSync:ReceiveHost(session, peer, fields, now)
    if fields[3] ~= peer.request then
        return false
    end
    if fields[1] == "B" then
        local ids = Split(fields[4])
        if not ids then
            return false
        end
        local previousId = 0
        for index, text in ipairs(ids) do
            local id = Integer(text, 1)
            if not id or id <= previousId or not session.streakSpeakers.entries[id] or not peer.streakSent[id] then
                return false
            end
            ids[index], previousId = id, id
        end
        for _, id in ipairs(ids) do
            peer.streakAcknowledged[id] = true
        end
    else
        local id = Integer(fields[4], 1)
        if not id or not session.streakSpeakers.entries[id] then
            return false
        end
        if peer.lastStreakRequest and now - peer.lastStreakRequest < MAP_RETRY then
            return false
        end
        peer.lastStreakRequest = now
        peer.streakAcknowledged[id], peer.streakSent[id] = nil, nil
    end
    return true
end

function StreakSync:TickHost(session, now)
    local game = Quiz.Controller.game
    if
        now < session.nextStreakMapAt
        or Games.Comms:IsBusy()
        or game.state ~= "open" and game.state ~= "results" and game.state ~= "finished"
    then
        return
    end
    local chosenPeer, chosenId, chosenAt
    for _, peer in pairs(session.peers) do
        for id, entry in pairs(session.streakSpeakers.entries) do
            local sentAt = peer.streakSent[id] or -math.huge
            if
                not peer.streakAcknowledged[id]
                and now - sentAt >= MAP_RETRY
                and IsPinned(session, id, entry)
                and (not chosenAt or sentAt < chosenAt or sentAt == chosenAt and id < chosenId)
            then
                chosenPeer, chosenId, chosenAt = peer, id, sentAt
            end
        end
    end
    if chosenPeer then
        local ids, nameFields, idFields = {}, {}, {}
        for id, entry in pairs(session.streakSpeakers.entries) do
            if
                not chosenPeer.streakAcknowledged[id]
                and now - (chosenPeer.streakSent[id] or -math.huge) >= MAP_RETRY
                and IsPinned(session, id, entry)
            then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        for index = 1, math.min(#ids, MAX_NAME_BATCH) do
            idFields[index] = IdText(ids[index])
            nameFields[index] = session.streakSpeakers.entries[ids[index]].name
        end
        if
            Send(chosenPeer.name, {
                "N",
                session.hostSession,
                chosenPeer.request,
                table.concat(idFields, ","),
                table.concat(nameFields, ","),
            }, "streak-name")
        then
            for index = 1, #idFields do
                chosenPeer.streakSent[ids[index]] = now
            end
            session.nextStreakMapAt = now + MAP_INTERVAL
        end
    end
end

function StreakSync:TickClient(client, view, now)
    if
        not view.correctIndex
        or view.suppressStreakToasts
        or view.streakMilestonesComplete
        or view.state ~= "results"
        or now < (client.nextStreakRequest or 0)
        or Games.Comms:IsBusy()
    then
        return
    end
    for _, reference in ipairs(view.streakReferences or {}) do
        if not client.streakSpeakers or not client.streakSpeakers.entries[reference.id] then
            if Send(client.name, { "U", client.session, client.request, IdText(reference.id) }) then
                client.nextStreakRequest = now + MAP_RETRY
            end
            return
        end
    end
end

local _, Games = ...
local Quiz = Games.Quiz

local MAX_ROWS = 100
local MAX_INTEGER = 9007199254740990
local POINT_SCALE = 10
local MAX_SCORE = math.floor(MAX_INTEGER / POINT_SCALE)
local MAX_CANONICAL_BYTES = 3500
local REQUEST_RETRY = 2
local REQUEST_TAG = "quiz-standings-request"
local RESPONSE_TAG_PREFIX = "quiz-standings-view:"
local EMPTY_ROWS = {}

local Standings = {}
Quiz.Standings = Standings

local function ResponseTag(name)
    return RESPONSE_TAG_PREFIX .. name:lower()
end

local function Revision(text)
    if type(text) ~= "string" or not text:match("^%d+$") then
        return nil
    end
    local value = tonumber(text)
    if value and value <= MAX_INTEGER and string.format("%.0f", value) == text then
        return value
    end
end

local function ScoreText(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    if value < 0 or value > MAX_SCORE then
        return nil
    end
    local units = value * POINT_SCALE
    local rounded = math.floor(units + 0.5)
    if math.abs(units - rounded) > 0.0000001 then
        return nil
    end
    return string.format("%.1f", rounded / POINT_SCALE)
end

local function Score(text)
    if type(text) ~= "string" or not text:match("^%d+%.%d$") then
        return nil
    end
    local value = tonumber(text)
    return value and ScoreText(value) == text and value or nil
end

local function BuildRows(source)
    local rows, pieces, names, size = {}, {}, {}, 0
    for index = 1, math.min(MAX_ROWS, #source) do
        local row = source[index]
        local name = Games.Identity:NormalizeName(row.name)
        local score = ScoreText(row.score)
        if not name or name ~= row.name or names[name:lower()] or not score then
            return nil
        end
        local piece = name .. "=" .. score
        local nextSize = size + #piece + (#pieces > 0 and 1 or 0)
        if nextSize > MAX_CANONICAL_BYTES then
            break
        end
        rows[#rows + 1] = { name = name, score = tonumber(score) }
        pieces[#pieces + 1] = piece
        names[name:lower()] = true
        size = nextSize
    end
    return rows, table.concat(pieces, ",")
end

local function DecodeRows(encoded)
    if type(encoded) ~= "string" or #encoded > MAX_CANONICAL_BYTES then
        return nil
    end
    if encoded == "" then
        return EMPTY_ROWS
    end
    local rows, pieces, names, previousScore = {}, {}, {}, math.huge
    for piece in encoded:gmatch("[^,]+") do
        if #rows >= MAX_ROWS then
            return nil
        end
        local name, scoreText = piece:match("^([^=]+)=(%d+%.%d)$")
        local normalized = name and Games.Identity:NormalizeName(name)
        local score = Score(scoreText)
        if not normalized or normalized ~= name or names[normalized:lower()] or not score or score > previousScore then
            return nil
        end
        rows[#rows + 1] = { name = normalized, score = score }
        pieces[#pieces + 1] = piece
        names[normalized:lower()] = true
        previousScore = score
    end
    if #rows == 0 or table.concat(pieces, ",") ~= encoded then
        return nil
    end
    return rows
end

local function Send(target, fields, tag)
    return Games.Comms:Send(target, Quiz.id, fields, tag)
end

function Standings:Reset(session)
    session.standingsVisible = false
    session.standingsRows = nil
    session.standingsRevision = -1
    session.standingsEncoding = nil
    session.standingsDirty = false
    session.standingsDirtyThrough = nil
    session.nextStandingsRequestAt = nil
    session.hostStandingsCached = false
    session.hostStandingsResultId = nil
    session.hostStandingsRows = EMPTY_ROWS
    session.hostStandingsEncoding = ""
end

function Standings:CancelPeer(peer)
    Games.Comms:Cancel(ResponseTag(peer.name))
end

function Standings:Cancel(session)
    Games.Comms:Cancel(REQUEST_TAG)
    for _, peer in pairs(session.peers or {}) do
        self:CancelPeer(peer)
    end
end

function Standings:RenewMembership(session)
    Games.Comms:Cancel(REQUEST_TAG)
    if session.standingsVisible then
        session.standingsDirty = true
        session.nextStandingsRequestAt = 0
    end
end

function Standings:SetVisible(session, visible)
    visible = visible == true
    if session.standingsVisible == visible then
        return false
    end
    session.standingsVisible = visible
    if visible and session.client then
        session.standingsDirty = true
        session.nextStandingsRequestAt = 0
    elseif not visible then
        Games.Comms:Cancel(REQUEST_TAG)
        session.nextStandingsRequestAt = nil
    end
    return true
end

function Standings:MarkDirty(session, revision)
    if type(revision) ~= "number" or revision < 0 or revision > MAX_INTEGER or revision % 1 ~= 0 then
        return
    end
    if revision <= session.standingsRevision then
        return
    end
    local changed = not session.standingsDirtyThrough or revision > session.standingsDirtyThrough
    session.standingsDirty = true
    session.standingsDirtyThrough = math.max(session.standingsDirtyThrough or 0, revision)
    if changed and session.standingsVisible then
        session.nextStandingsRequestAt = 0
    end
end

function Standings:GetHost(session)
    local game = Quiz.Controller.game
    local result = game and game.lastResult
    local resultId = result and result.id or 0
    if not session.hostStandingsCached or session.hostStandingsResultId ~= resultId then
        local rows, encoded = BuildRows(game and game:GetStandings() or EMPTY_ROWS)
        assert(rows, "invalid host standings")
        session.hostStandingsCached = true
        session.hostStandingsResultId = resultId
        session.hostStandingsRows = rows
        session.hostStandingsEncoding = encoded
    end
    return session.hostStandingsRows, resultId
end

function Standings:GetClient(session)
    if session.standingsRevision < 0 then
        return nil, 0
    end
    return session.standingsRows, math.max(0, session.standingsRevision)
end

function Standings:SendView(session, peer)
    local _, revision = self:GetHost(session)
    local tag = ResponseTag(peer.name)
    if Games.Comms:IsTagBusy(tag) then
        return true
    end
    return Send(peer.name, {
        "V",
        session.hostSession,
        peer.request,
        string.format("%.0f", revision),
        session.hostStandingsEncoding,
    }, tag)
end

function Standings:ReceiveView(session, fields, now)
    local client = session.client
    local revision = Revision(fields[4])
    local rows = revision and DecodeRows(fields[5])
    if
        not client
        or fields[2] ~= client.session
        or fields[3] ~= client.request
        or not revision
        or not rows
        or revision < session.standingsRevision
    then
        return false
    end
    if revision == session.standingsRevision then
        if fields[5] ~= session.standingsEncoding then
            return false
        end
    else
        session.standingsRows = rows
        session.standingsRevision = revision
        session.standingsEncoding = fields[5]
    end
    if not session.standingsDirtyThrough or revision >= session.standingsDirtyThrough then
        session.standingsDirty = false
        session.standingsDirtyThrough = nil
        session.nextStandingsRequestAt = nil
        Games.Comms:Cancel(REQUEST_TAG)
    else
        session.nextStandingsRequestAt = now + REQUEST_RETRY
    end
    return true
end

function Standings:Tick(session, now)
    local client = session.client
    if
        not client
        or not client.session
        or client.awaitingWelcome
        or not session.standingsVisible
        or not session.standingsDirty
        or now < (session.nextStandingsRequestAt or 0)
        or Games.Comms:IsTagBusy(REQUEST_TAG)
    then
        return
    end
    if Send(client.name, { "G", client.session, client.request }, REQUEST_TAG) then
        session.nextStandingsRequestAt = now + REQUEST_RETRY
    end
end

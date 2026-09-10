local _, Games = ...
local Quiz = Games.Quiz
local SCHEMA_VERSION = 2
local PREVIOUS_SCHEMA_VERSION = 1
local LEGACY_SCORING_VERSION = 2
local LEGACY_ANSWER_SECONDS = 15
local CURRENT_SCORING_VERSION = Quiz.Scoring.VERSION
local MAX_SAFE_INTEGER = 9007199254740991
local POINT_SCALE = 10
local LEGACY_MAX_CORRECT_UNITS = 25
local MAX_ROUNDS = math.floor(MAX_SAFE_INTEGER / LEGACY_MAX_CORRECT_UNITS)
local MAX_SCORE = math.floor(MAX_SAFE_INTEGER / POINT_SCALE)
local SCORE_EPSILON = 0.000001
local MAX_PACK_ID_BYTES = 48
local MAX_PACK_TITLE_BYTES = 64
local MAX_HOST_BYTES = 128
local MAX_SESSION_BYTES = 64
local MAX_PACK_VERSION = 2147483647
local MAX_RECENT_RESULTS = 64
local MAX_SESSIONS = 10000
local MAX_RANGES_PER_SESSION = 4096
local LEGACY_BOUNDS = { correctMin = 10, correctMax = 25, wrongMin = -10, wrongMax = -5, rounds = MAX_ROUNDS }
local STATS_KEYS = { "score", "correct", "incorrect", "answers", "unanswered", "rounds" }
local RECEIPT_KEYS = {
    "host",
    "session",
    "roundId",
    "packId",
    "packTitle",
    "packVersion",
    "scoringVersion",
    "duration",
    "choiceCount",
    "selected",
    "correctIndex",
    "elapsed",
    "points",
    "rulesKey",
    "streak",
    "streakBonus",
}
local RECEIPT_FIELDS = {}
for _, key in ipairs(RECEIPT_KEYS) do
    RECEIPT_FIELDS[key] = true
end
local ROOT_FIELDS = { schemaVersion = true, rounds = true, packs = true, receipts = true, recent = true }
local LEGACY_PACK_FIELDS = { title = true, version = true, versions = true, scoringVersions = true }
local PACK_FIELDS = { title = true, version = true, versions = true, scoringVersions = true, rulesets = true }
local STATS_FIELDS =
    { score = true, correct = true, incorrect = true, answers = true, unanswered = true, rounds = true }
local RANGE_FIELDS = { first = true, last = true }

local Personal = {
    revision = 0,
    MAX_RECENT_RESULTS = MAX_RECENT_RESULTS,
    MAX_SESSIONS = MAX_SESSIONS,
    MAX_RANGES_PER_SESSION = MAX_RANGES_PER_SESSION,
}
Quiz.PersonalScores = Personal

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function IsInteger(value, minimum, maximum)
    return IsFinite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function IsPlainTable(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function HasFields(value, fields)
    if not IsPlainTable(value) then
        return false
    end
    for key in pairs(value) do
        if not fields[key] then
            return false
        end
    end
    return true
end

local function IsArray(value, maximum)
    if not IsPlainTable(value) or #value > maximum then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if not IsInteger(key, 1, #value) then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function IsText(value, maximum)
    return type(value) == "string"
        and #value <= maximum
        and value:find("%S") ~= nil
        and not value:find("[%z\1-\31\127|{}]")
end

local function IsPackId(value)
    return IsText(value, MAX_PACK_ID_BYTES) and value ~= "all" and value:match("^[a-z0-9][a-z0-9_%-]*$") ~= nil
end

local function IsHost(value)
    return IsText(value, MAX_HOST_BYTES) and value:match("^[%a\128-\255]+%-[%w\128-\255'%-]+$") ~= nil
end

local function IsSession(value)
    return type(value) == "string" and #value > 0 and #value <= MAX_SESSION_BYTES and value:match("^[%w.%-]+$") ~= nil
end

local function ScoreUnits(value)
    if not IsFinite(value) or value < -MAX_SCORE or value > MAX_SCORE then
        return nil
    end
    local units = value * POINT_SCALE
    local rounded = math.floor(units + 0.5)
    if math.abs(units - rounded) > SCORE_EPSILON then
        return nil
    end
    return rounded
end

local function NewStats()
    return { score = 0, correct = 0, incorrect = 0, answers = 0, unanswered = 0, rounds = 0 }
end

local function RuleBounds(rules)
    local minimum, maximum = Quiz.Scoring.GetBounds(rules)
    local maximumUnits = math.floor(math.max(-minimum, maximum) * POINT_SCALE + 0.5)
    return {
        correctMin = math.floor(rules.correctPoints * POINT_SCALE + 0.5),
        correctMax = math.floor(maximum * POINT_SCALE + 0.5),
        wrongMin = math.floor(minimum * POINT_SCALE + 0.5),
        wrongMax = -math.floor(rules.wrongPenaltyEnd * POINT_SCALE + 0.5),
        rounds = math.floor(MAX_SAFE_INTEGER / math.max(LEGACY_MAX_CORRECT_UNITS, maximumUnits)),
    }
end

local function CopyStats(saved, bounds)
    if not HasFields(saved, STATS_FIELDS) then
        return nil
    end
    local units = ScoreUnits(saved.score)
    if not units then
        return nil
    end
    local stats = { score = units / POINT_SCALE }
    for index = 2, #STATS_KEYS do
        local key = STATS_KEYS[index]
        if not IsInteger(saved[key], 0, MAX_ROUNDS) then
            return nil
        end
        stats[key] = saved[key]
    end
    if stats.answers ~= stats.correct + stats.incorrect or stats.rounds ~= stats.answers + stats.unanswered then
        return nil
    end
    if bounds then
        if stats.rounds > bounds.rounds then
            return nil
        end
        if units < stats.correct * bounds.correctMin + stats.incorrect * bounds.wrongMin then
            return nil
        end
        if units > stats.correct * bounds.correctMax + stats.incorrect * bounds.wrongMax then
            return nil
        end
    end
    return stats
end

local function SumStats(target, source, sign)
    target.score = Quiz.Scoring.Add(target.score, source.score * sign)
    for index = 2, #STATS_KEYS do
        local key = STATS_KEYS[index]
        target[key] = target[key] + source[key] * sign
    end
end

local function ReceiptStats(receipt)
    local stats = NewStats()
    stats.rounds, stats.score = 1, receipt.points
    if receipt.selected then
        stats.answers = 1
        stats[receipt.selected == receipt.correctIndex and "correct" or "incorrect"] = 1
    else
        stats.unanswered = 1
    end
    return stats
end

local function CopyReceipt(receipt, allowLegacy)
    if not HasFields(receipt, RECEIPT_FIELDS) or not IsHost(receipt.host) or not IsSession(receipt.session) then
        return nil
    end
    if not IsInteger(receipt.roundId, 1, MAX_SAFE_INTEGER - 1) or not IsPackId(receipt.packId) then
        return nil
    end
    if
        not IsText(receipt.packTitle, MAX_PACK_TITLE_BYTES) or not IsInteger(receipt.packVersion, 1, MAX_PACK_VERSION)
    then
        return nil
    end
    local legacy = receipt.scoringVersion == LEGACY_SCORING_VERSION
    local rules
    if legacy then
        if
            not allowLegacy
            or receipt.duration ~= LEGACY_ANSWER_SECONDS
            or receipt.rulesKey ~= nil
            or receipt.streak ~= nil
            or receipt.streakBonus ~= nil
        then
            return nil
        end
    else
        rules = Quiz.Rules.Decode(receipt.rulesKey)
        if
            receipt.scoringVersion ~= CURRENT_SCORING_VERSION
            or not rules
            or receipt.duration ~= rules.answerSeconds
            or not IsInteger(receipt.streak, 0, MAX_SAFE_INTEGER - 1)
            or not ScoreUnits(receipt.streakBonus)
        then
            return nil
        end
    end
    if not IsInteger(receipt.choiceCount, Quiz.MIN_CHOICES, Quiz.MAX_CHOICES) then
        return nil
    end
    if not IsInteger(receipt.correctIndex, 1, receipt.choiceCount) then
        return nil
    end
    local points = 0
    if receipt.selected == nil then
        if receipt.elapsed ~= nil or receipt.points ~= nil and receipt.points ~= 0 then
            return nil
        end
        if not legacy and (receipt.streak ~= 0 or receipt.streakBonus ~= 0) then
            return nil
        end
    else
        if not IsInteger(receipt.selected, 1, receipt.choiceCount) then
            return nil
        end
        if not IsFinite(receipt.elapsed) or receipt.elapsed < 0 or receipt.elapsed > receipt.duration then
            return nil
        end
        local correct = receipt.selected == receipt.correctIndex
        if not legacy then
            if correct and receipt.streak < 1 or not correct and receipt.streak ~= 0 then
                return nil
            end
            if receipt.streakBonus ~= Quiz.Scoring.StreakBonus(rules, receipt.streak) then
                return nil
            end
        end
        points = legacy and Quiz.Scoring.CalculateLegacy(correct, receipt.elapsed, receipt.duration)
            or Quiz.Scoring.Calculate(correct, receipt.elapsed, receipt.duration, rules, receipt.streak)
        if receipt.points ~= points then
            return nil
        end
    end
    local copy = {}
    for _, key in ipairs(RECEIPT_KEYS) do
        copy[key] = receipt[key]
    end
    copy.host, copy.points = receipt.host:lower(), points
    return copy
end

local function ReceiptBucket(receipt)
    return receipt.rulesKey or LEGACY_SCORING_VERSION
end

local function FindRange(ranges, id)
    local low, high = 1, #ranges
    while low <= high do
        local index = math.floor((low + high) / 2)
        local range = ranges[index]
        if id < range.first then
            high = index - 1
        elseif id > range.last then
            low = index + 1
        else
            return true, index
        end
    end
    return false, low
end

local function SameReceipt(left, right)
    for _, key in ipairs(RECEIPT_KEYS) do
        if left[key] ~= right[key] then
            return false
        end
    end
    return true
end

local function SameIdentity(left, right)
    return left.host == right.host and left.session == right.session and left.roundId == right.roundId
end

local function CopyPack(saved, previous)
    if
        not HasFields(saved, previous and LEGACY_PACK_FIELDS or PACK_FIELDS)
        or not IsText(saved.title, MAX_PACK_TITLE_BYTES)
    then
        return nil
    end
    if not IsInteger(saved.version, 1, MAX_PACK_VERSION) or not IsPlainTable(saved.versions) then
        return nil
    end
    if not IsPlainTable(saved.scoringVersions) then
        return nil
    end
    if not previous and not IsPlainTable(saved.rulesets) then
        return nil
    end
    local pack = { title = saved.title, version = saved.version, versions = {}, scoringVersions = {}, rulesets = {} }
    local versionRounds, total = 0, NewStats()
    for version, rounds in pairs(saved.versions) do
        if not IsInteger(version, 1, saved.version) or not IsInteger(rounds, 1, MAX_ROUNDS) then
            return nil
        end
        versionRounds = versionRounds + rounds
        pack.versions[version] = rounds
    end
    if not pack.versions[saved.version] then
        return nil
    end
    for version, value in pairs(saved.scoringVersions) do
        if version ~= LEGACY_SCORING_VERSION then
            return nil
        end
        local stats = CopyStats(value, LEGACY_BOUNDS)
        if not stats or stats.rounds == 0 then
            return nil
        end
        pack.scoringVersions[version] = stats
        SumStats(total, stats, 1)
    end
    for key, value in pairs(previous and {} or saved.rulesets) do
        local rules = Quiz.Rules.Decode(key)
        local stats = rules and CopyStats(value, RuleBounds(rules))
        if not stats or stats.rounds == 0 then
            return nil
        end
        pack.rulesets[key] = stats
        SumStats(total, stats, 1)
        if not CopyStats(total) then
            return nil
        end
    end
    if total.rounds == 0 or total.rounds ~= versionRounds or not CopyStats(total) then
        return nil
    end
    return pack, total
end

local function CopyRanges(saved)
    if not IsArray(saved, MAX_RANGES_PER_SESSION) or #saved == 0 then
        return nil
    end
    local ranges, previousLast, rounds = {}, -1, 0
    for _, value in ipairs(saved) do
        if not HasFields(value, RANGE_FIELDS) or not IsInteger(value.first, 1, MAX_SAFE_INTEGER - 1) then
            return nil
        end
        if not IsInteger(value.last, value.first, MAX_SAFE_INTEGER - 1) or value.first <= previousLast + 1 then
            return nil
        end
        rounds = rounds + (value.last - value.first + 1)
        if rounds > MAX_ROUNDS then
            return nil
        end
        ranges[#ranges + 1] = { first = value.first, last = value.last }
        previousLast = value.last
    end
    return ranges, rounds
end

function Personal:CopySaved(saved)
    if saved == nil then
        return { schemaVersion = SCHEMA_VERSION, rounds = 0, packs = {}, receipts = {}, recent = {} }
    end
    if
        not HasFields(saved, ROOT_FIELDS)
        or saved.schemaVersion ~= SCHEMA_VERSION and saved.schemaVersion ~= PREVIOUS_SCHEMA_VERSION
    then
        return nil, "invalid_personal_scores"
    end
    if not IsInteger(saved.rounds, 0, MAX_ROUNDS) or not IsPlainTable(saved.packs) then
        return nil, "invalid_personal_scores"
    end
    if not IsPlainTable(saved.receipts) or not IsArray(saved.recent, MAX_RECENT_RESULTS) then
        return nil, "invalid_personal_scores"
    end
    local copy = { schemaVersion = SCHEMA_VERSION, rounds = saved.rounds, packs = {}, receipts = {}, recent = {} }
    local packRounds, receiptRounds, sessionCount = 0, 0, 0
    local remaining = {}
    for id, value in pairs(saved.packs) do
        if not IsPackId(id) then
            return nil, "invalid_personal_scores"
        end
        local pack, totals = CopyPack(value, saved.schemaVersion == PREVIOUS_SCHEMA_VERSION)
        if not pack then
            return nil, "invalid_personal_scores"
        end
        packRounds = packRounds + totals.rounds
        if packRounds > MAX_ROUNDS then
            return nil, "invalid_personal_scores"
        end
        copy.packs[id], remaining[id] = pack, {}
        for version, stats in pairs(pack.scoringVersions) do
            remaining[id][version] = CopyStats(stats, LEGACY_BOUNDS)
        end
        for key, stats in pairs(pack.rulesets) do
            remaining[id][key] = CopyStats(stats, RuleBounds(Quiz.Rules.Decode(key)))
        end
    end
    for host, sessions in pairs(saved.receipts) do
        if not IsHost(host) or host ~= host:lower() or not IsPlainTable(sessions) or next(sessions) == nil then
            return nil, "invalid_personal_scores"
        end
        copy.receipts[host] = {}
        for session, value in pairs(sessions) do
            if not IsSession(session) then
                return nil, "invalid_personal_scores"
            end
            local ranges, rounds = CopyRanges(value)
            if not ranges then
                return nil, "invalid_personal_scores"
            end
            sessionCount, receiptRounds = sessionCount + 1, receiptRounds + rounds
            if sessionCount > MAX_SESSIONS or receiptRounds > MAX_ROUNDS then
                return nil, "invalid_personal_scores"
            end
            copy.receipts[host][session] = ranges
        end
    end
    if
        packRounds ~= saved.rounds
        or receiptRounds ~= saved.rounds
        or #saved.recent ~= math.min(saved.rounds, MAX_RECENT_RESULTS)
    then
        return nil, "invalid_personal_scores"
    end
    local recentIds, recentVersions = {}, {}
    for _, value in ipairs(saved.recent) do
        local receipt = CopyReceipt(value, true)
        if not receipt or not SameReceipt(receipt, value) then
            return nil, "invalid_personal_scores"
        end
        local sessions = copy.receipts[receipt.host]
        local ranges = sessions and sessions[receipt.session]
        local pack = copy.packs[receipt.packId]
        if
            not ranges
            or not FindRange(ranges, receipt.roundId)
            or not pack
            or not pack.versions[receipt.packVersion]
        then
            return nil, "invalid_personal_scores"
        end
        local id = receipt.host .. ":" .. receipt.session .. ":" .. string.format("%.0f", receipt.roundId)
        if recentIds[id] then
            return nil, "invalid_personal_scores"
        end
        recentIds[id] = true
        local stats = remaining[receipt.packId][ReceiptBucket(receipt)]
        if not stats then
            return nil, "invalid_personal_scores"
        end
        SumStats(stats, ReceiptStats(receipt), -1)
        recentVersions[receipt.packId] = recentVersions[receipt.packId] or {}
        local versions = recentVersions[receipt.packId]
        versions[receipt.packVersion] = (versions[receipt.packVersion] or 0) + 1
        if versions[receipt.packVersion] > pack.versions[receipt.packVersion] then
            return nil, "invalid_personal_scores"
        end
        copy.recent[#copy.recent + 1] = receipt
    end
    for _, versions in pairs(remaining) do
        for key, stats in pairs(versions) do
            local bounds = key == LEGACY_SCORING_VERSION and LEGACY_BOUNDS or RuleBounds(Quiz.Rules.Decode(key))
            if not CopyStats(stats, bounds) then
                return nil, "invalid_personal_scores"
            end
        end
    end
    return copy
end

function Personal:Bind(data)
    self.data, self.sessionCount = data, 0
    self.packTotals = {}
    for id, pack in pairs(data.packs) do
        local totals = NewStats()
        for _, stats in pairs(pack.scoringVersions) do
            SumStats(totals, stats, 1)
        end
        for _, stats in pairs(pack.rulesets) do
            SumStats(totals, stats, 1)
        end
        self.packTotals[id] = totals
    end
    for _, sessions in pairs(data.receipts) do
        for _ in pairs(sessions) do
            self.sessionCount = self.sessionCount + 1
        end
    end
    self.revision = self.revision + 1
end

function Personal:RecordResult(value)
    local receipt = CopyReceipt(value)
    if not receipt then
        return false, "invalid_personal_result"
    end
    local data = self.data
    local sessions = data.receipts[receipt.host]
    local ranges = sessions and sessions[receipt.session]
    local duplicate, index = false, 1
    if ranges then
        duplicate, index = FindRange(ranges, receipt.roundId)
    end
    if duplicate then
        for _, recent in ipairs(data.recent) do
            if SameIdentity(receipt, recent) and not SameReceipt(receipt, recent) then
                return false, "conflicting_personal_result"
            end
        end
        return true, "duplicate"
    end
    if data.rounds >= MAX_ROUNDS or not ranges and self.sessionCount >= MAX_SESSIONS then
        return false, "personal_history_full"
    end
    local left, right = ranges and ranges[index - 1], ranges and ranges[index]
    local joinLeft = left and left.last + 1 == receipt.roundId
    local joinRight = right and right.first - 1 == receipt.roundId
    if ranges and #ranges >= MAX_RANGES_PER_SESSION and not joinLeft and not joinRight then
        return false, "personal_history_full"
    end
    local pack = data.packs[receipt.packId]
    if not pack then
        pack = {
            title = receipt.packTitle,
            version = receipt.packVersion,
            versions = {},
            scoringVersions = {},
            rulesets = {},
        }
    end
    local bounds = RuleBounds(Quiz.Rules.Decode(receipt.rulesKey))
    local previous = pack.rulesets[receipt.rulesKey]
    local stats = previous and CopyStats(previous, bounds)
    if previous and not stats then
        return false, "invalid_personal_scores"
    end
    stats = stats or NewStats()
    if stats.rounds >= bounds.rounds then
        return false, "personal_history_full"
    end
    local totals = self.packTotals[receipt.packId] and CopyStats(self.packTotals[receipt.packId]) or NewStats()
    local award = ReceiptStats(receipt)
    SumStats(stats, award, 1)
    SumStats(totals, award, 1)
    if not CopyStats(stats, bounds) or not CopyStats(totals) then
        return false, "invalid_personal_result"
    end
    if not ranges then
        sessions = sessions or {}
        ranges = {}
        data.receipts[receipt.host], sessions[receipt.session] = sessions, ranges
        self.sessionCount = self.sessionCount + 1
    end
    if joinLeft and joinRight then
        left.last = right.last
        table.remove(ranges, index)
    elseif joinLeft then
        left.last = receipt.roundId
    elseif joinRight then
        right.first = receipt.roundId
    else
        table.insert(ranges, index, { first = receipt.roundId, last = receipt.roundId })
    end
    if receipt.packVersion >= pack.version then
        pack.version, pack.title = receipt.packVersion, receipt.packTitle
    end
    pack.versions[receipt.packVersion] = (pack.versions[receipt.packVersion] or 0) + 1
    pack.rulesets[receipt.rulesKey] = stats
    data.packs[receipt.packId] = pack
    self.packTotals[receipt.packId] = totals
    data.rounds = data.rounds + 1
    data.recent[#data.recent + 1] = receipt
    if #data.recent > MAX_RECENT_RESULTS then
        table.remove(data.recent, 1)
    end
    self.revision = self.revision + 1
    return true, "recorded"
end

function Personal:GetPack(id)
    local saved = self.data.packs[id]
    if not saved then
        return nil
    end
    local summary = CopyStats(self.packTotals[id])
    summary.score = Quiz.Scoring.Clamp(summary.score)
    summary.id, summary.title, summary.version = id, saved.title, saved.version
    summary.versions, summary.scoringVersions, summary.rulesets = {}, {}, {}
    for version, rounds in pairs(saved.versions) do
        summary.versions[version] = rounds
    end
    for version, stats in pairs(saved.scoringVersions) do
        summary.scoringVersions[version] = CopyStats(stats, LEGACY_BOUNDS)
        summary.scoringVersions[version].score = Quiz.Scoring.Clamp(summary.scoringVersions[version].score)
    end
    for key, stats in pairs(saved.rulesets) do
        local ruleset = CopyStats(stats, RuleBounds(Quiz.Rules.Decode(key)))
        if ruleset then
            ruleset.score = Quiz.Scoring.Clamp(ruleset.score)
        end
        summary.rulesets[key] = ruleset
        local current = summary.scoringVersions[CURRENT_SCORING_VERSION] or NewStats()
        SumStats(current, stats, 1)
        summary.scoringVersions[CURRENT_SCORING_VERSION] = current
    end
    local current = summary.scoringVersions[CURRENT_SCORING_VERSION]
    if current then
        current.score = Quiz.Scoring.Clamp(current.score)
    end
    return summary
end

local function ComparePacks(left, right)
    local leftTitle, rightTitle = left.title:lower(), right.title:lower()
    if leftTitle ~= rightTitle then
        return leftTitle < rightTitle
    end
    return left.id < right.id
end

function Personal:GetScoreRows()
    local rows = {}
    for id, pack in pairs(self.data.packs) do
        local archived = pack.scoringVersions[LEGACY_SCORING_VERSION]
        if archived then
            local row = CopyStats(archived, LEGACY_BOUNDS)
            row.score = Quiz.Scoring.Clamp(row.score)
            row.id, row.title, row.version = id, pack.title, pack.version
            row.scoringVersion, row.archived = LEGACY_SCORING_VERSION, true
            rows[#rows + 1] = row
        end
        for key, stats in pairs(pack.rulesets) do
            local rules = Quiz.Rules.Decode(key)
            local row = CopyStats(stats, RuleBounds(rules))
            row.score = Quiz.Scoring.Clamp(row.score)
            row.id, row.title, row.version = id, pack.title, pack.version
            row.scoringVersion, row.rulesKey, row.rules = CURRENT_SCORING_VERSION, key, rules
            row.archived = false
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(left, right)
        if left.id ~= right.id then
            return ComparePacks(left, right)
        end
        if left.archived or right.archived then
            return left.archived and not right.archived
        end
        return left.rulesKey < right.rulesKey
    end)
    return rows
end

function Personal:GetPacks()
    local packs = {}
    for id in pairs(self.data.packs) do
        packs[#packs + 1] = self:GetPack(id)
    end
    table.sort(packs, ComparePacks)
    return packs
end

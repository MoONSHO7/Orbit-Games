local Quiz = OrbitQuiz
local SCHEMA_VERSION = 6
local PREVIOUS_SCHEMA_VERSION = 5
local PREVIOUS_SCORING_SCHEMA_VERSION = 4
local PREVIOUS_SCORING_VERSION = 1
local CURRENT_SCORING_VERSION = Quiz.Scoring.VERSION
local MAX_SAFE_INTEGER = 9007199254740991
local POINT_SCALE = 10
local MAX_SCORE = math.floor(MAX_SAFE_INTEGER / POINT_SCALE)
local SCORE_EPSILON = 0.000001
local PREVIOUS_SECOND_EPSILON = 0.0000001
local PREVIOUS_CORRECT_UNITS = 10
local MAX_HISTORY = 50
local MAX_LEAGUE_LENGTH = 48
local MAX_PACK_ID_LENGTH = 96
local MAX_IDENTITY_LENGTH = 128
local MAX_HOST_NAME_LENGTH = 128
local MAX_WIDGET_FONT_LENGTH = 128
local MAX_QUESTION_KEY_LENGTH = 256
local MIN_HISTORY_DURATION = 10
local MAX_HISTORY_DURATION = 60
local MAX_QUESTIONS = 50
local MIN_CHOICES = Quiz.MIN_CHOICES
local MAX_CHOICES = Quiz.MAX_CHOICES
local LEGACY_CORRECT_POINTS = { [100] = true, [110] = true, [120] = true }
local LEGACY_INCORRECT_POINTS = -50
local LEGACY_BASE_POINTS = 100
local LEGACY_EARLY_BONUS = 20
local LEGACY_MIDDLE_BONUS = 10
local LEGACY_EARLY_FRACTION = 0.25
local LEGACY_MIDDLE_FRACTION = 0.6
local STORED_MODES = { PUBLIC = true, WHISPER = true }
local DEFAULT_WIDGET_POSITION = { x = 0.5, y = 0.65 }
local DEFAULT_WIDGET_SETTINGS = { scale = Quiz.WIDGET_SCALE_DEFAULT, font = "" }
local DEFAULTS = {
    league = "Default",
    packId = "all",
    questionCount = 10,
    duration = Quiz.ANSWER_SECONDS,
    autoAdvance = false,
    hostName = "",
}

local Store = {}
Quiz.Store = Store

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function IsInteger(value, minimum, maximum)
    return IsFinite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function IsScore(value, signed)
    if not IsFinite(value) or value < (signed and -MAX_SCORE or 0) or value > MAX_SCORE then
        return false
    end
    local units = value * POINT_SCALE
    return math.abs(units - math.floor(units + 0.5)) <= SCORE_EPSILON
end

local function IsText(value, maximum, allowEmpty)
    return type(value) == "string"
        and #value <= maximum
        and not value:find("[%z\1-\31\127|]")
        and (allowEmpty or value:find("%S") ~= nil)
end

local function IsArray(value)
    if type(value) ~= "table" then
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

local function IsHostName(value)
    if not IsText(value, MAX_HOST_NAME_LENGTH, true) then
        return false
    end
    if value == "" then
        return true
    end
    return value:match("^[%a\128-\255][%w\128-\255'%-]*$") ~= nil
        and not value:find("%-%-")
        and not value:find("[%-']$")
end

local function CopySettings(settings, base)
    if type(settings) ~= "table" then
        return nil, "invalid_settings"
    end
    local copy = {}
    for key in pairs(DEFAULTS) do
        local value = settings[key]
        if value == nil then
            value = base[key]
        end
        copy[key] = value
    end
    copy.duration = Quiz.ANSWER_SECONDS
    if copy.packId == "warcraft_basics" or copy.packId == "warcraft-basics" then
        copy.packId = "warcraft-lore"
    end
    if not IsText(copy.league, MAX_LEAGUE_LENGTH, false) then
        return nil, "invalid_league"
    end
    if not IsText(copy.packId, MAX_PACK_ID_LENGTH, false) then
        return nil, "invalid_pack"
    end
    if not IsInteger(copy.questionCount, 1, MAX_QUESTIONS) then
        return nil, "invalid_question_count"
    end
    if type(copy.autoAdvance) ~= "boolean" then
        return nil, "invalid_auto_advance"
    end
    if not IsHostName(copy.hostName) then
        return nil, "invalid_host_name"
    end
    return copy
end

local function LegacyPoints(correct, elapsed, duration)
    if not correct then
        return LEGACY_INCORRECT_POINTS
    end
    if elapsed <= duration * LEGACY_EARLY_FRACTION then
        return LEGACY_BASE_POINTS + LEGACY_EARLY_BONUS
    end
    if elapsed <= duration * LEGACY_MIDDLE_FRACTION then
        return LEGACY_BASE_POINTS + LEGACY_MIDDLE_BONUS
    end
    return LEGACY_BASE_POINTS
end

local function PreviousPoints(correct, elapsed, duration)
    if not correct then
        return 0
    end
    local remaining = math.max(0, math.min(duration, duration - elapsed))
    return (PREVIOUS_CORRECT_UNITS + math.floor(remaining + PREVIOUS_SECOND_EPSILON)) / POINT_SCALE
end

local function CopyAnswer(answer, duration, legacy, choiceCount, scoringVersion)
    if type(answer) ~= "table" then
        return nil
    end
    if not IsText(answer.guid, MAX_IDENTITY_LENGTH, false) or not IsText(answer.name, MAX_IDENTITY_LENGTH, false) then
        return nil
    end
    if not IsInteger(answer.choiceIndex, 1, choiceCount) or type(answer.correct) ~= "boolean" then
        return nil
    end
    if not IsFinite(answer.elapsed) or answer.elapsed < 0 or (duration and answer.elapsed > duration) then
        return nil
    end
    if legacy then
        if answer.correct then
            if type(answer.points) ~= "number" or not LEGACY_CORRECT_POINTS[answer.points] then
                return nil
            end
        elseif answer.points ~= LEGACY_INCORRECT_POINTS then
            return nil
        end
        if duration and answer.points ~= LegacyPoints(answer.correct, answer.elapsed, duration) then
            return nil
        end
    else
        local calculate = scoringVersion == PREVIOUS_SCORING_VERSION and PreviousPoints or Quiz.Scoring.Calculate
        if not duration or answer.points ~= calculate(answer.correct, answer.elapsed, duration) then
            return nil
        end
    end
    return {
        guid = answer.guid,
        name = answer.name,
        choiceIndex = answer.choiceIndex,
        correct = answer.correct,
        elapsed = answer.elapsed,
        points = answer.points,
    }
end

local function CopyRound(result, legacy, previousScoring)
    if type(result) ~= "table" or not IsInteger(result.id, 1, MAX_SAFE_INTEGER - 1) then
        return nil
    end
    if not IsText(result.questionKey, MAX_QUESTION_KEY_LENGTH, false) then
        return nil
    end
    if not IsInteger(result.number, 1, MAX_SAFE_INTEGER) or not IsArray(result.answers) then
        return nil
    end
    if result.cycle ~= nil and not IsInteger(result.cycle, 1, MAX_SAFE_INTEGER) then
        return nil
    end
    local scoringVersion
    if not legacy then
        scoringVersion = result.scoringVersion
        if previousScoring and scoringVersion == nil then
            scoringVersion = PREVIOUS_SCORING_VERSION
        end
        if
            scoringVersion ~= PREVIOUS_SCORING_VERSION and scoringVersion ~= CURRENT_SCORING_VERSION
            or previousScoring and scoringVersion ~= PREVIOUS_SCORING_VERSION
            or scoringVersion == CURRENT_SCORING_VERSION and result.duration ~= Quiz.ANSWER_SECONDS
        then
            return nil
        end
    end
    local choiceCount = result.choiceCount == nil and MIN_CHOICES or result.choiceCount
    if not IsInteger(choiceCount, MIN_CHOICES, legacy and MIN_CHOICES or MAX_CHOICES) then
        return nil
    end
    if
        (not legacy or result.duration ~= nil)
        and not IsInteger(result.duration, MIN_HISTORY_DURATION, MAX_HISTORY_DURATION)
    then
        return nil
    end
    local answers, guids, correctCount = {}, {}, 0
    for _, value in ipairs(result.answers) do
        local answer = CopyAnswer(value, result.duration, legacy, choiceCount, scoringVersion)
        if not answer or guids[answer.guid] then
            return nil
        end
        guids[answer.guid] = true
        answers[#answers + 1] = answer
        if answer.correct then
            correctCount = correctCount + 1
        end
    end
    if result.correctCount ~= nil and result.correctCount ~= correctCount then
        return nil
    end
    if result.totalAnswers ~= nil and result.totalAnswers ~= #answers then
        return nil
    end
    return {
        id = result.id,
        questionKey = result.questionKey,
        number = result.number,
        cycle = result.cycle,
        duration = result.duration,
        scoringVersion = scoringVersion,
        choiceCount = result.choiceCount,
        answers = answers,
        correctCount = correctCount,
        totalAnswers = #answers,
    }
end

local function CopyBoard(saved, legacy, previousScoring)
    if type(saved) ~= "table" then
        return nil
    end
    local lastRoundId = saved.lastRoundId == nil and 0 or saved.lastRoundId
    local players = saved.players == nil and {} or saved.players
    local history = saved.history == nil and {} or saved.history
    if not IsInteger(lastRoundId, 0, MAX_SAFE_INTEGER - 1) or type(players) ~= "table" or not IsArray(history) then
        return nil
    end
    local board = { lastRoundId = lastRoundId, players = {}, history = {} }
    for guid, player in pairs(players) do
        if not IsText(guid, MAX_IDENTITY_LENGTH, false) or type(player) ~= "table" then
            return nil
        end
        local validScore = legacy and IsInteger(player.score, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER)
            or not legacy and IsScore(player.score, not previousScoring)
        if not IsText(player.name, MAX_IDENTITY_LENGTH, false) or not validScore then
            return nil
        end
        if
            not IsInteger(player.correct, 0, MAX_SAFE_INTEGER) or not IsInteger(player.incorrect, 0, MAX_SAFE_INTEGER)
        then
            return nil
        end
        if
            not IsInteger(player.answers, 0, MAX_SAFE_INTEGER)
            or player.answers ~= player.correct + player.incorrect
        then
            return nil
        end
        board.players[guid] = {
            name = player.name,
            score = legacy and player.score or math.floor(player.score * POINT_SCALE + 0.5) / POINT_SCALE,
            correct = player.correct,
            incorrect = player.incorrect,
            answers = player.answers,
        }
    end
    local previousId = 0
    for index, result in ipairs(history) do
        local entry = CopyRound(result, legacy, previousScoring)
        if not entry or entry.id <= previousId or entry.id > lastRoundId then
            return nil
        end
        previousId = entry.id
        if legacy or index > #history - MAX_HISTORY then
            board.history[#board.history + 1] = entry
        end
    end
    return board
end

local function CopyLeagues(leagues, legacy, previousScoring)
    if type(leagues) ~= "table" then
        return nil
    end
    local copy, lastRoundId = {}, 0
    for league, savedBoards in pairs(leagues) do
        if not IsText(league, MAX_LEAGUE_LENGTH, false) or type(savedBoards) ~= "table" then
            return nil
        end
        local boards = {}
        for mode, savedBoard in pairs(savedBoards) do
            if type(mode) ~= "string" or not STORED_MODES[mode] or not legacy and mode ~= "PUBLIC" then
                return nil
            end
            local board = CopyBoard(savedBoard, legacy, previousScoring)
            if not board then
                return nil
            end
            boards[mode] = board
            lastRoundId = math.max(lastRoundId, board.lastRoundId)
        end
        copy[league] = boards
    end
    return copy, lastRoundId
end

local function CopyWidgetPosition(position)
    if type(position) ~= "table" then
        return nil
    end
    for _, key in ipairs({ "x", "y" }) do
        if not IsFinite(position[key]) or position[key] < 0 or position[key] > 1 then
            return nil
        end
    end
    return { x = position.x, y = position.y }
end

local function CopyWidgetSettings(settings, base)
    if type(settings) ~= "table" then
        return nil, "invalid_widget_settings"
    end
    local copy = {}
    for key in pairs(DEFAULT_WIDGET_SETTINGS) do
        copy[key] = settings[key] == nil and base[key] or settings[key]
    end
    if
        not IsInteger(copy.scale, Quiz.WIDGET_SCALE_MIN, Quiz.WIDGET_SCALE_MAX)
        or (copy.scale - Quiz.WIDGET_SCALE_MIN) % Quiz.WIDGET_SCALE_STEP ~= 0
    then
        return nil, "invalid_widget_scale"
    end
    if copy.font ~= "" and not IsText(copy.font, MAX_WIDGET_FONT_LENGTH, false) then
        return nil, "invalid_widget_font"
    end
    return copy
end

local function MigrateLegacyScoring(saved)
    return {
        schemaVersion = SCHEMA_VERSION,
        settings = saved.settings,
        nextQuestionId = saved.nextQuestionId,
        legacyLeagues = saved.leagues,
        leagues = {},
        widgetPosition = saved.widgetPosition,
        widgetSettings = saved.widgetSettings,
        personalScores = saved.personalScores,
    }
end

function Store:Initialize(saved)
    if saved == nil then
        saved = { schemaVersion = SCHEMA_VERSION }
    end
    if type(saved) ~= "table" then
        return nil, "invalid_database"
    end
    if saved.schemaVersion == nil and next(saved) == nil then
        saved = { schemaVersion = SCHEMA_VERSION }
    end
    if IsFinite(saved.schemaVersion) and saved.schemaVersion > SCHEMA_VERSION then
        return nil, "unsupported_database_version"
    end
    local previousScoring = saved.schemaVersion == PREVIOUS_SCORING_SCHEMA_VERSION
    if saved.schemaVersion == 1 or saved.schemaVersion == 2 or saved.schemaVersion == 3 then
        saved = MigrateLegacyScoring(saved)
    elseif
        saved.schemaVersion ~= SCHEMA_VERSION
        and saved.schemaVersion ~= PREVIOUS_SCHEMA_VERSION
        and not previousScoring
    then
        return nil, "invalid_database_version"
    end
    local settings, settingsError = CopySettings(saved.settings == nil and {} or saved.settings, DEFAULTS)
    if not settings then
        return nil, settingsError
    end
    local nextQuestionId = saved.nextQuestionId == nil and 1 or saved.nextQuestionId
    if not IsInteger(nextQuestionId, 1, MAX_SAFE_INTEGER) then
        return nil, "invalid_database"
    end
    local leagues, lastRoundId = CopyLeagues(saved.leagues == nil and {} or saved.leagues, false, previousScoring)
    local legacyLeagues, legacyLastRoundId = CopyLeagues(saved.legacyLeagues == nil and {} or saved.legacyLeagues, true)
    if not leagues or not legacyLeagues then
        return nil, "invalid_standings"
    end
    local widgetPosition =
        CopyWidgetPosition(saved.widgetPosition == nil and DEFAULT_WIDGET_POSITION or saved.widgetPosition)
    if not widgetPosition then
        return nil, "invalid_widget_position"
    end
    local widgetSettings, widgetSettingsError =
        CopyWidgetSettings(saved.widgetSettings == nil and {} or saved.widgetSettings, DEFAULT_WIDGET_SETTINGS)
    if not widgetSettings then
        return nil, widgetSettingsError
    end
    local personalScores, personalError = Quiz.PersonalScores:CopySaved(saved.personalScores)
    if not personalScores then
        return nil, personalError
    end
    local db = {
        schemaVersion = SCHEMA_VERSION,
        settings = settings,
        nextQuestionId = math.max(nextQuestionId, lastRoundId + 1, legacyLastRoundId + 1),
        leagues = leagues,
        legacyLeagues = legacyLeagues,
        widgetPosition = widgetPosition,
        widgetSettings = widgetSettings,
        personalScores = personalScores,
    }
    self.db = db
    Quiz.PersonalScores:Bind(personalScores)
    return db
end

function Store:GetWidgetPosition()
    return { x = self.db.widgetPosition.x, y = self.db.widgetPosition.y }
end

function Store:SaveWidgetPosition(x, y)
    local position = CopyWidgetPosition({ x = x, y = y })
    if not position then
        return false, "invalid_widget_position"
    end
    self.db.widgetPosition = position
    return true
end

function Store:GetWidgetSettings()
    return { scale = self.db.widgetSettings.scale, font = self.db.widgetSettings.font }
end

function Store:SaveWidgetSettings(settings)
    local copy, reason = CopyWidgetSettings(settings, self.db.widgetSettings)
    if not copy then
        return false, reason
    end
    self.db.widgetSettings = copy
    return true
end

function Store:GetSettings()
    local copy = {}
    for key in pairs(DEFAULTS) do
        copy[key] = self.db.settings[key]
    end
    copy.duration = Quiz.ANSWER_SECONDS
    return copy
end

function Store:SaveSettings(settings)
    local copy, reason = CopySettings(settings, self.db.settings)
    if not copy then
        return false, reason
    end
    self.db.settings = copy
    return true
end

function Store:NextQuestionId()
    local id = self.db.nextQuestionId
    if id >= MAX_SAFE_INTEGER then
        return nil, "question_ids_exhausted"
    end
    self.db.nextQuestionId = id + 1
    return id
end

function Store:RecordRound(league, mode, result)
    if not IsText(league, MAX_LEAGUE_LENGTH, false) or mode ~= "PUBLIC" then
        return false, "invalid_league_or_mode"
    end
    if
        type(result) ~= "table"
        or result.scoringVersion ~= CURRENT_SCORING_VERSION
        or result.duration ~= Quiz.ANSWER_SECONDS
    then
        return false, "invalid_result"
    end
    local entry = CopyRound(result)
    if not entry then
        return false, "invalid_result"
    end
    local boards = self.db.leagues[league]
    local board = boards and boards[mode]
    local legacyBoards = self.db.legacyLeagues[league]
    local legacyBoard = legacyBoards and legacyBoards[mode]
    if board and entry.id <= board.lastRoundId or legacyBoard and entry.id <= legacyBoard.lastRoundId then
        return false, "already_recorded"
    end
    for _, answer in ipairs(entry.answers) do
        local player = board and board.players[answer.guid]
        if
            player
            and (player.answers >= MAX_SAFE_INTEGER or not IsScore(Quiz.Scoring.Add(player.score, answer.points), true))
        then
            return false, "invalid_result"
        end
    end
    if not boards then
        boards = {}
        self.db.leagues[league] = boards
    end
    if not board then
        board = { lastRoundId = 0, players = {}, history = {} }
        boards[mode] = board
    end
    for _, answer in ipairs(entry.answers) do
        local player = board.players[answer.guid]
        if not player then
            player = { name = answer.name, score = 0, correct = 0, incorrect = 0, answers = 0 }
            board.players[answer.guid] = player
        end
        player.name = answer.name
        player.score = Quiz.Scoring.Add(player.score, answer.points)
        player.answers = player.answers + 1
        if answer.correct then
            player.correct = player.correct + 1
        else
            player.incorrect = player.incorrect + 1
        end
    end
    board.lastRoundId = entry.id
    board.history[#board.history + 1] = entry
    if #board.history > MAX_HISTORY then
        table.remove(board.history, 1)
    end
    self.db.nextQuestionId = math.max(self.db.nextQuestionId, entry.id + 1)
    return true
end

function Store:GetStandings(league, mode)
    local boards = self.db.leagues[league]
    local board = boards and boards[mode]
    return Quiz.Scoring.BuildStandings(board and board.players or {})
end

function Store:GetArchivedLeagues()
    local names, seen = {}, {}
    for _, leagues in ipairs({ self.db.leagues, self.db.legacyLeagues }) do
        for name in pairs(leagues) do
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

function Store:GetLegacyStandings(league, mode)
    local boards = self.db.legacyLeagues[league]
    local board = boards and boards[mode]
    return Quiz.Scoring.BuildStandings(board and board.players or {})
end

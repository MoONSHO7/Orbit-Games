local _, Quiz = ...
local MIN_CHOICES = Quiz.MIN_CHOICES
local MAX_CHOICES = Quiz.MAX_CHOICES
local MAX_QUESTIONS = 50
local LEGACY_SCORING_VERSION = 2
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_IDENTITY_LENGTH = 128
local MIN_STREAK_MILESTONE = 5

local Game = {}
Game.__index = Game
Quiz.Game = Game

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function IsInteger(value, minimum, maximum)
    return IsFinite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function IsIdentity(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_IDENTITY_LENGTH
        and not value:find("[%z\1-\31\127|]")
end

local function Copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, field in pairs(value) do
        copy[Copy(key, seen)] = Copy(field, seen)
    end
    return copy
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

local function Shuffle(values, random)
    for index = #values, 2, -1 do
        local other = random(index)
        if not IsInteger(other, 1, index) then
            return false
        end
        values[index], values[other] = values[other], values[index]
    end
    return true
end

local function IsQuestion(question)
    if type(question) ~= "table" or type(question.key) ~= "string" or question.key == "" then
        return false
    end
    if type(question.prompt) ~= "string" or question.prompt == "" then
        return false
    end
    if not IsArray(question.choices) or not IsInteger(#question.choices, MIN_CHOICES, MAX_CHOICES) then
        return false
    end
    if not IsInteger(question.correctIndex, 1, #question.choices) then
        return false
    end
    for _, choice in ipairs(question.choices) do
        if type(choice) ~= "string" or choice == "" then
            return false
        end
    end
    return (question.explanation == nil or type(question.explanation) == "string")
        and (question.category == nil or type(question.category) == "string")
        and (question.difficulty == nil or Quiz.DIFFICULTIES[question.difficulty] == true)
        and (question.era == nil or type(question.era) == "string")
        and (question.source == nil or type(question.source) == "string")
end

local function EarlierCorrect(answer, fastest)
    if not answer.correct then
        return false
    end
    if not fastest or answer.elapsed ~= fastest.elapsed then
        return not fastest or answer.elapsed < fastest.elapsed
    end
    local name, fastestName = answer.name:lower(), fastest.name:lower()
    return name < fastestName or name == fastestName and answer.guid < fastest.guid
end

function Game.New(settings, questions, randomFunction, packRules)
    if type(settings) ~= "table" then
        return nil, "invalid_question_count"
    end
    local rules, rulesError = Quiz.Rules.Normalize(packRules)
    if not rules then
        return nil, rulesError
    end
    local legacy = packRules == nil
    if legacy then
        if settings.continuous ~= nil and type(settings.continuous) ~= "boolean" then
            return nil, "invalid_continuous"
        end
        if settings.continuous ~= true and not IsInteger(settings.questionCount, 1, MAX_QUESTIONS) then
            return nil, "invalid_question_count"
        end
        rules.repeatQuestions = settings.continuous == true
        rules.questionLimit = rules.repeatQuestions and 0 or settings.questionCount
    end
    local continuous = rules.repeatQuestions and rules.questionLimit == 0
    if not IsArray(questions) or #questions == 0 then
        return nil, "no_questions"
    end
    if randomFunction ~= nil and type(randomFunction) ~= "function" then
        return nil, "invalid_random_function"
    end
    local deck, keys = {}, {}
    for _, question in ipairs(questions) do
        if not IsQuestion(question) or keys[question.key] then
            return nil, "invalid_question"
        end
        keys[question.key] = true
        deck[#deck + 1] = Copy(question)
    end
    local random = randomFunction or math.random
    if rules.shuffleQuestions and not Shuffle(deck, random) then
        return nil, "invalid_random_result"
    end
    local gameSettings = Copy(settings)
    gameSettings.duration = rules.answerSeconds
    gameSettings.continuous = continuous
    gameSettings.questionCount = rules.questionLimit
    local total = rules.questionLimit == 0 and #deck or rules.questionLimit
    if not rules.repeatQuestions then
        total = math.min(total, #deck)
    end
    return setmetatable({
        settings = gameSettings,
        rules = rules,
        rulesKey = Quiz.Rules.Encode(rules),
        scoringVersion = legacy and LEGACY_SCORING_VERSION or Quiz.Scoring.VERSION,
        deck = deck,
        deckIndex = 1,
        random = random,
        continuous = continuous,
        cycle = 1,
        lastQuestionId = 0,
        usedIds = legacy and not continuous and {} or nil,
        players = {},
        completed = 0,
        total = total,
        state = "ready",
    }, Game)
end

function Game:PrepareQuestion(uniqueQuestionId)
    if self.state ~= "ready" and self.state ~= "results" then
        return nil, "not_ready"
    end
    if
        not IsInteger(uniqueQuestionId, 1, MAX_SAFE_INTEGER - 1)
        or not self.usedIds and uniqueQuestionId <= self.lastQuestionId
        or self.usedIds and self.usedIds[uniqueQuestionId]
    then
        return nil, "invalid_question_id"
    end
    if
        not self.continuous and self.completed >= self.total
        or not self.rules.repeatQuestions and self.deckIndex > #self.deck
    then
        self.total = self.completed
        self.state = "finished"
        return nil, "no_questions"
    end
    local deck, deckIndex, cycle = self.deck, self.deckIndex, self.cycle
    if self.rules.repeatQuestions and deckIndex > #deck then
        deck = {}
        for index, question in ipairs(self.deck) do
            deck[index] = question
        end
        if self.rules.shuffleQuestions and not Shuffle(deck, self.random) then
            return nil, "invalid_random_result"
        end
        if self.rules.shuffleQuestions and #deck > 1 and deck[1].key == self.lastQuestionKey then
            local other = self.random(#deck - 1)
            if not IsInteger(other, 1, #deck - 1) then
                return nil, "invalid_random_result"
            end
            other = other + 1
            deck[1], deck[other] = deck[other], deck[1]
        end
        deckIndex = 1
        cycle = cycle + 1
    end
    local question = deck[deckIndex]
    local options = {}
    for index, text in ipairs(question.choices) do
        options[index] = { text = text, correct = index == question.correctIndex }
    end
    if self.rules.shuffleChoices and not Shuffle(options, self.random) then
        return nil, "invalid_random_result"
    end
    local choices, correctIndex = {}, nil
    for index, option in ipairs(options) do
        choices[index] = option.text
        if option.correct then
            correctIndex = index
        end
    end
    local round = {
        id = uniqueQuestionId,
        number = self.continuous and deckIndex or self.completed + 1,
        cycle = cycle,
        key = question.key,
        packId = question.packId,
        packTitle = question.packTitle,
        packVersion = question.packVersion,
        rules = Quiz.Rules.Normalize(self.rules),
        rulesKey = self.rulesKey,
        duration = self.rules.answerSeconds,
        revealSeconds = self.rules.revealSeconds,
        prompt = question.prompt,
        choices = choices,
        choiceCount = #choices,
        correctIndex = correctIndex,
        explanation = question.explanation,
        category = question.category,
        difficulty = question.difficulty,
        era = question.era,
        source = question.source,
        answers = {},
    }
    self.deck = deck
    self.deckIndex = deckIndex + 1
    self.cycle = cycle
    self.lastQuestionId = uniqueQuestionId
    self.lastQuestionKey = question.key
    if self.usedIds then
        self.usedIds[uniqueQuestionId] = true
    end
    self.round = round
    self.pauseReason = nil
    self.state = "posting"
    return round
end

function Game:OpenQuestion(now)
    if self.state ~= "posting" then
        return false, "not_posting"
    end
    if not IsFinite(now) or now < 0 then
        return false, "invalid_time"
    end
    self.round.startedAt = now
    self.round.deadline = now + self.rules.answerSeconds
    self.state = "open"
    return true
end

function Game:Submit(guid, name, questionId, choiceIndex, now, actionId)
    if self.state ~= "open" then
        return false, "not_open"
    end
    if not IsIdentity(guid) or not IsIdentity(name) or not IsInteger(choiceIndex, 1, #self.round.choices) then
        return false, "invalid_answer"
    end
    if actionId ~= nil and not IsIdentity(actionId) then
        return false, "invalid_answer"
    end
    local round = self.round
    if questionId ~= round.id then
        return false, "wrong_question"
    end
    if not IsFinite(now) or now < round.startedAt then
        return false, "invalid_time"
    end
    if now > round.deadline then
        return false, "late"
    end
    local previous = round.answers[guid]
    if actionId and previous and previous.actionId == actionId then
        if previous.choiceIndex ~= choiceIndex then
            return false, "invalid_answer"
        end
        return true, "duplicate"
    end
    if previous and previous.choiceIndex == choiceIndex then
        if actionId then
            previous.actionId = actionId
        end
        return true, "duplicate"
    end
    if previous and not self.rules.allowAnswerChanges then
        return false, "answer_locked"
    end
    local correct = choiceIndex == round.correctIndex
    local elapsed = math.min(now - round.startedAt, self.rules.answerSeconds)
    round.answers[guid] = {
        guid = guid,
        name = name,
        choiceIndex = choiceIndex,
        correct = correct,
        elapsed = elapsed,
        points = Quiz.Scoring.Calculate(correct, elapsed, self.rules.answerSeconds, self.rules),
        actionId = actionId,
    }
    return true
end

function Game:CloseQuestion(now, multiplayer)
    if self.state ~= "open" then
        return nil, "not_open"
    end
    if not IsFinite(now) or now < self.round.deadline then
        return nil, "before_deadline"
    end
    local round = self.round
    local answers, streakMilestones, correctCount, fastest = {}, {}, 0, nil
    for guid, player in pairs(self.players) do
        if not round.answers[guid] then
            player.streak = 0
        end
    end
    for guid, answer in pairs(round.answers) do
        local player = self.players[guid]
        if not player then
            player = { name = answer.name, score = 0, correct = 0, incorrect = 0, answers = 0, streak = 0 }
            self.players[guid] = player
        end
        player.streak = answer.correct and player.streak + 1 or 0
        answer.streak = player.streak
        answer.streakBonus = Quiz.Scoring.StreakBonus(self.rules, player.streak)
        answer.points =
            Quiz.Scoring.Calculate(answer.correct, answer.elapsed, self.rules.answerSeconds, self.rules, player.streak)
        answers[#answers + 1] = Copy(answer)
        player.name = answer.name
        player.score = Quiz.Scoring.Add(player.score, answer.points)
        player.answers = player.answers + 1
        if answer.correct then
            player.correct = player.correct + 1
            correctCount = correctCount + 1
            if player.streak >= MIN_STREAK_MILESTONE then
                streakMilestones[#streakMilestones + 1] = { name = answer.name, streak = player.streak }
            end
        else
            player.incorrect = player.incorrect + 1
        end
        if multiplayer == true and EarlierCorrect(answer, fastest) then
            fastest = answer
        end
    end
    table.sort(answers, function(left, right)
        if left.elapsed ~= right.elapsed then
            return left.elapsed < right.elapsed
        end
        return left.guid < right.guid
    end)
    table.sort(streakMilestones, function(left, right)
        if left.streak ~= right.streak then
            return left.streak > right.streak
        end
        return left.name:lower() < right.name:lower()
    end)
    local result = {
        id = round.id,
        questionKey = round.key,
        packId = round.packId,
        packTitle = round.packTitle,
        packVersion = round.packVersion,
        rules = Quiz.Rules.Normalize(self.rules),
        rulesKey = self.rulesKey,
        number = round.number,
        cycle = round.cycle,
        prompt = round.prompt,
        choices = Copy(round.choices),
        choiceCount = #round.choices,
        correctIndex = round.correctIndex,
        explanation = round.explanation,
        difficulty = round.difficulty,
        era = round.era,
        source = round.source,
        duration = self.rules.answerSeconds,
        revealSeconds = self.rules.revealSeconds,
        scoringVersion = self.scoringVersion,
        answers = answers,
        correctCount = correctCount,
        totalAnswers = #answers,
        fastestName = fastest and fastest.name or nil,
        fastestElapsed = fastest and fastest.elapsed or nil,
        streakMilestones = streakMilestones,
    }
    self.completed = self.completed + 1
    result.complete = not self.continuous and self.completed >= self.total
    self.lastResult = result
    self.state = result.complete and "finished" or "results"
    return result
end

function Game:Pause(reason)
    if self.state == "finished" or self.state == "stopped" then
        return false, "not_running"
    end
    if self.state == "posting" or self.state == "open" then
        self.round = nil
        if not self.rules.repeatQuestions then
            self.total = math.min(self.total, self.completed + #self.deck - self.deckIndex + 1)
        end
    end
    self.pauseReason = reason
    self.state = "paused"
    return true
end

function Game:Resume()
    if self.state ~= "paused" then
        return false, "not_paused"
    end
    self.pauseReason = nil
    self.state = not self.continuous and self.completed >= self.total and "finished" or "ready"
    return true
end

function Game:Stop()
    if self.state == "posting" or self.state == "open" then
        self.round = nil
    end
    self.state = "stopped"
    return true
end

function Game:GetStandings()
    return Quiz.Scoring.BuildStandings(self.players)
end

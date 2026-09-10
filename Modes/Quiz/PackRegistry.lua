local _, Games = ...
local Quiz = Games.Quiz

local MAX_ID_BYTES = 48
local MAX_TITLE_BYTES = 64
local MAX_PROMPT_BYTES = 160
local MAX_CHOICE_BYTES = 100
local MAX_EXPLANATION_BYTES = 160
local MAX_SOURCE_BYTES = 512
local MAX_QUESTIONS = 2000
local MAX_VERSION = 2147483647
local MIN_CHOICES = Quiz.MIN_CHOICES
local MAX_CHOICES = Quiz.MAX_CHOICES
local DEFAULT_LOCALE = "enUS"
local LOCALES = {
    enUS = true,
    enGB = true,
    deDE = true,
    esES = true,
    esMX = true,
    frFR = true,
    itIT = true,
    koKR = true,
    ptBR = true,
    ruRU = true,
    zhCN = true,
    zhTW = true,
}
local L = Quiz.L.packErrors
local registry = {}
local registrationErrors = {}

local function IsPlainTable(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function IsId(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_ID_BYTES
        and value:match("^[a-z0-9][a-z0-9_-]*$") ~= nil
end

local function NormalizeText(value, maxBytes)
    if type(value) ~= "string" or #value > maxBytes or value:find("[%z\1-\31\127|{}]") then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function ArrayCount(value, minimum, maximum)
    if not IsPlainTable(value) then
        return nil
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > maximum or key ~= math.floor(key) then
            return nil
        end
        count = count + 1
    end
    if count < minimum or count > maximum then
        return nil
    end
    for index = 1, count do
        if value[index] == nil then
            return nil
        end
    end
    return count
end

local function CopyQuestion(question)
    local choices = {}
    for index = 1, #question.choices do
        choices[index] = question.choices[index]
    end
    return {
        id = question.id,
        key = question.key,
        packId = question.packId,
        packTitle = question.packTitle,
        packVersion = question.packVersion,
        rulesKey = question.rulesKey,
        prompt = question.prompt,
        choices = choices,
        correctIndex = question.correctIndex,
        explanation = question.explanation,
        category = question.category,
        difficulty = question.difficulty,
        era = question.era,
        source = question.source,
    }
end

local function NormalizeQuestion(question, packId)
    if not IsPlainTable(question) then
        return nil, L.TABLE_F:format("question")
    end
    if not IsId(question.id) then
        return nil, L.ID_F:format("id")
    end
    local prompt = NormalizeText(question.prompt, MAX_PROMPT_BYTES)
    if not prompt then
        return nil, L.TEXT_F:format("prompt", MAX_PROMPT_BYTES)
    end
    local choiceCount = ArrayCount(question.choices, MIN_CHOICES, MAX_CHOICES)
    if not choiceCount then
        return nil, L.ARRAY_F:format("choices", MIN_CHOICES, MAX_CHOICES)
    end
    local choices, seenChoices = {}, {}
    for index = 1, choiceCount do
        local choice = NormalizeText(question.choices[index], MAX_CHOICE_BYTES)
        if not choice then
            return nil, L.TEXT_F:format("choices[" .. index .. "]", MAX_CHOICE_BYTES)
        end
        local normalized = choice:lower()
        if seenChoices[normalized] then
            return nil, L.DUPLICATE_CHOICE
        end
        choices[index] = choice
        seenChoices[normalized] = true
    end
    local correctIndex = question.correctIndex
    if
        type(correctIndex) ~= "number"
        or correctIndex < 1
        or correctIndex > choiceCount
        or correctIndex ~= math.floor(correctIndex)
    then
        return nil, L.INDEX_F:format(choiceCount)
    end
    local explanation, category, era, source
    if question.explanation ~= nil then
        explanation = NormalizeText(question.explanation, MAX_EXPLANATION_BYTES)
        if not explanation then
            return nil, L.TEXT_F:format("explanation", MAX_EXPLANATION_BYTES)
        end
    end
    if question.category ~= nil then
        category = NormalizeText(question.category, MAX_TITLE_BYTES)
        if not category then
            return nil, L.TEXT_F:format("category", MAX_TITLE_BYTES)
        end
    end
    if
        question.difficulty ~= nil
        and (type(question.difficulty) ~= "string" or not Quiz.DIFFICULTIES[question.difficulty])
    then
        return nil, L.DIFFICULTY
    end
    if question.era ~= nil then
        era = NormalizeText(question.era, MAX_TITLE_BYTES)
        if not era then
            return nil, L.TEXT_F:format("era", MAX_TITLE_BYTES)
        end
    end
    if question.source ~= nil then
        source = NormalizeText(question.source, MAX_SOURCE_BYTES)
        local host = source and source:match("^https://([^/?#]+)")
        if not source or source:find('[%s<>"]') or not host or not host:match("^[%w][%w.%-]*$") then
            return nil, L.SOURCE
        end
    end
    return {
        id = question.id,
        key = packId .. ":" .. question.id,
        packId = packId,
        prompt = prompt,
        choices = choices,
        correctIndex = correctIndex,
        explanation = explanation,
        category = category,
        difficulty = question.difficulty,
        era = era,
        source = source,
    }
end

local function NormalizePack(pack)
    if not IsPlainTable(pack) then
        return nil, L.TABLE_F:format("pack")
    end
    if not IsId(pack.id) then
        return nil, L.ID_F:format("id")
    end
    if pack.id == "all" then
        return nil, L.RESERVED
    end
    if registry[pack.id] then
        return nil, L.DUPLICATE_PACK
    end
    local title = NormalizeText(pack.title, MAX_TITLE_BYTES)
    if not title then
        return nil, L.TEXT_F:format("title", MAX_TITLE_BYTES)
    end
    local version = pack.version
    if version == nil then
        version = 1
    end
    if type(version) ~= "number" or version < 1 or version > MAX_VERSION or version ~= math.floor(version) then
        return nil, L.VERSION
    end
    local locale = pack.locale
    if locale == nil then
        locale = DEFAULT_LOCALE
    end
    if type(locale) ~= "string" or not LOCALES[locale] then
        return nil, L.LOCALE
    end
    local author
    if pack.author ~= nil then
        author = NormalizeText(pack.author, MAX_TITLE_BYTES)
        if not author then
            return nil, L.TEXT_F:format("author", MAX_TITLE_BYTES)
        end
    end
    local rules, rulesError = Quiz.Rules.Normalize(pack.rules)
    if not rules then
        return nil, "rules: " .. rulesError
    end
    local rulesKey = Quiz.Rules.Encode(rules)
    local count = ArrayCount(pack.questions, 1, MAX_QUESTIONS)
    if not count then
        return nil, L.ARRAY_F:format("questions", 1, MAX_QUESTIONS)
    end
    local questions, seenIds = {}, {}
    for index = 1, count do
        local question, errorText = NormalizeQuestion(pack.questions[index], pack.id)
        if not question then
            return nil, L.QUESTION_F:format(index, errorText)
        end
        if seenIds[question.id] then
            return nil, L.QUESTION_F:format(index, L.DUPLICATE_QUESTION)
        end
        question.packTitle, question.packVersion = title, version
        question.rulesKey = rulesKey
        questions[index] = question
        seenIds[question.id] = true
    end
    return {
        id = pack.id,
        title = title,
        version = version,
        author = author,
        locale = locale,
        rules = rules,
        rulesKey = rulesKey,
        questions = questions,
        count = count,
    }
end

function Quiz:RegisterPack(pack)
    local normalized, errorText = NormalizePack(pack)
    if not normalized then
        local packId = IsPlainTable(pack) and IsId(pack.id) and pack.id or "?"
        local message = L.PACK_F:format(packId, errorText)
        registrationErrors[#registrationErrors + 1] = message
        return false, message
    end
    registry[normalized.id] = normalized
    return true
end

function Quiz:GetPacks()
    local packs = {}
    for _, pack in pairs(registry) do
        packs[#packs + 1] = {
            id = pack.id,
            title = pack.title,
            version = pack.version,
            author = pack.author,
            locale = pack.locale,
            rules = Quiz.Rules.Normalize(pack.rules),
            rulesKey = pack.rulesKey,
            count = pack.count,
        }
    end
    table.sort(packs, function(left, right)
        if left.title == right.title then
            return left.id < right.id
        end
        return left.title < right.title
    end)
    return packs
end

function Quiz:GetRules(packId)
    if packId == "all" then
        local selected
        for _, pack in pairs(registry) do
            if selected and selected.rulesKey ~= pack.rulesKey then
                return nil, "incompatible_pack_rules"
            end
            selected = pack
        end
        if not selected then
            return nil, "no_questions"
        end
        return Quiz.Rules.Normalize(selected.rules), selected.rulesKey
    end
    if type(packId) ~= "string" or not registry[packId] then
        return nil, L.PACK_F:format(IsId(packId) and packId or "?", L.UNKNOWN)
    end
    local pack = registry[packId]
    return Quiz.Rules.Normalize(pack.rules), pack.rulesKey
end

function Quiz:GetQuestions(packId)
    local questions = {}
    if packId == "all" then
        for _, metadata in ipairs(self:GetPacks()) do
            for _, question in ipairs(registry[metadata.id].questions) do
                questions[#questions + 1] = CopyQuestion(question)
            end
        end
        return questions
    end
    if type(packId) ~= "string" or not registry[packId] then
        return nil, L.PACK_F:format(IsId(packId) and packId or "?", L.UNKNOWN)
    end
    for _, question in ipairs(registry[packId].questions) do
        questions[#questions + 1] = CopyQuestion(question)
    end
    return questions
end

function Quiz:GetPackErrors()
    local errors = {}
    for index, message in ipairs(registrationErrors) do
        errors[index] = message
    end
    return errors
end

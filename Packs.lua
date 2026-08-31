local _, Quiz = ...

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
local ERROR_TEXT = {
    enUS = {
        PACK_F = "Pack %s: %s",
        QUESTION_F = "question %d: %s",
        TABLE_F = "%s must be a plain Lua table.",
        ID_F = "%s must use 1-48 lowercase ASCII letters, digits, '-' or '_', starting with a letter or digit.",
        TEXT_F = "%s must be non-empty plain text of at most %d bytes, without controls, pipes or braces.",
        ARRAY_F = "%s must be a dense array with %d to %d entries.",
        VERSION = "version must be a positive integer no greater than 2147483647.",
        LOCALE = "locale must be a supported WoW locale code.",
        DUPLICATE_PACK = "This pack id is already registered.",
        DUPLICATE_QUESTION = "This question id repeats within the pack.",
        DUPLICATE_CHOICE = "Choices must be distinct, ignoring ASCII case and surrounding spaces.",
        INDEX_F = "correctIndex must be an integer from 1 to %d for this question.",
        DIFFICULTY = "difficulty must be easy, medium, hard or very_hard.",
        SOURCE = "source must be an HTTPS URL of at most 512 bytes, without spaces, controls or markup.",
        RESERVED = "The pack id 'all' is reserved.",
        UNKNOWN = "No pack is registered with this id.",
    },
    deDE = {
        PACK_F = "Paket %s: %s",
        QUESTION_F = "Frage %d: %s",
        TABLE_F = "%s muss eine einfache Lua-Tabelle sein.",
        ID_F = "%s: 1-48 ASCII-Kleinbuchstaben, Ziffern, '-' oder '_'; Beginn mit Buchstabe oder Ziffer.",
        TEXT_F = "%s: nicht leerer Klartext mit höchstens %d Bytes, ohne Steuerzeichen, senkrechte Striche oder Klammern.",
        ARRAY_F = "%s muss ein lückenloses Array mit %d bis %d Einträgen sein.",
        VERSION = "version muss eine positive ganze Zahl bis 2147483647 sein.",
        LOCALE = "locale muss ein unterstützter WoW-Sprachcode sein.",
        DUPLICATE_PACK = "Diese Paket-ID ist bereits registriert.",
        DUPLICATE_QUESTION = "Diese Fragen-ID kommt im Paket mehrfach vor.",
        DUPLICATE_CHOICE = "Antworten müssen sich ohne ASCII-Großschreibung und äußere Leerzeichen unterscheiden.",
        INDEX_F = "correctIndex muss für diese Frage eine ganze Zahl von 1 bis %d sein.",
        DIFFICULTY = "difficulty muss easy, medium, hard oder very_hard sein.",
        SOURCE = "source muss eine HTTPS-URL mit höchstens 512 Bytes ohne Leerzeichen, Steuerzeichen oder Markup sein.",
        RESERVED = "Die Paket-ID 'all' ist reserviert.",
        UNKNOWN = "Unter dieser ID ist kein Paket registriert.",
    },
    esES = {
        PACK_F = "Paquete %s: %s",
        QUESTION_F = "pregunta %d: %s",
        TABLE_F = "%s debe ser una tabla Lua simple.",
        ID_F = "%s: 1-48 letras ASCII minúsculas, dígitos, '-' o '_'; debe empezar por letra o dígito.",
        TEXT_F = "%s debe ser texto no vacío de hasta %d bytes, sin controles, barras verticales ni llaves.",
        ARRAY_F = "%s debe ser una matriz sin huecos de %d a %d elementos.",
        VERSION = "version debe ser un entero positivo no mayor que 2147483647.",
        LOCALE = "locale debe ser un código de idioma de WoW compatible.",
        DUPLICATE_PACK = "Este id de paquete ya está registrado.",
        DUPLICATE_QUESTION = "Este id de pregunta se repite en el paquete.",
        DUPLICATE_CHOICE = "Las opciones deben ser distintas, sin contar mayúsculas ASCII ni espacios exteriores.",
        INDEX_F = "correctIndex debe ser un entero de 1 a %d para esta pregunta.",
        DIFFICULTY = "difficulty debe ser easy, medium, hard o very_hard.",
        SOURCE = "source debe ser una URL HTTPS de hasta 512 bytes, sin espacios, controles ni marcado.",
        RESERVED = "El id de paquete 'all' está reservado.",
        UNKNOWN = "No hay ningún paquete registrado con este id.",
    },
    frFR = {
        PACK_F = "Pack %s : %s",
        QUESTION_F = "question %d : %s",
        TABLE_F = "%s doit être une table Lua simple.",
        ID_F = "%s : 1-48 minuscules ASCII, chiffres, '-' ou '_' ; commencer par une lettre ou un chiffre.",
        TEXT_F = "%s doit être un texte non vide de %d octets maximum, sans contrôles, barres verticales ni accolades.",
        ARRAY_F = "%s doit être un tableau sans trous contenant %d à %d éléments.",
        VERSION = "version doit être un entier positif inférieur ou égal à 2147483647.",
        LOCALE = "locale doit être un code de langue WoW pris en charge.",
        DUPLICATE_PACK = "Cet identifiant de pack est déjà enregistré.",
        DUPLICATE_QUESTION = "Cet identifiant de question est répété dans le pack.",
        DUPLICATE_CHOICE = "Les choix doivent différer, sans tenir compte de la casse ASCII ni des espaces extérieurs.",
        INDEX_F = "correctIndex doit être un entier de 1 à %d pour cette question.",
        DIFFICULTY = "difficulty doit être easy, medium, hard ou very_hard.",
        SOURCE = "source doit être une URL HTTPS de 512 octets maximum, sans espaces, contrôles ni balisage.",
        RESERVED = "L'identifiant de pack 'all' est réservé.",
        UNKNOWN = "Aucun pack n'est enregistré sous cet identifiant.",
    },
    itIT = {
        PACK_F = "Pacchetto %s: %s",
        QUESTION_F = "domanda %d: %s",
        TABLE_F = "%s deve essere una semplice tabella Lua.",
        ID_F = "%s: 1-48 lettere ASCII minuscole, cifre, '-' o '_'; deve iniziare con una lettera o cifra.",
        TEXT_F = "%s deve essere testo non vuoto di massimo %d byte, senza controlli, barre verticali o parentesi graffe.",
        ARRAY_F = "%s deve essere un array senza lacune con %d-%d elementi.",
        VERSION = "version deve essere un intero positivo non superiore a 2147483647.",
        LOCALE = "locale deve essere un codice lingua WoW supportato.",
        DUPLICATE_PACK = "Questo id del pacchetto è già registrato.",
        DUPLICATE_QUESTION = "Questo id della domanda è ripetuto nel pacchetto.",
        DUPLICATE_CHOICE = "Le opzioni devono differire, ignorando maiuscole ASCII e spazi esterni.",
        INDEX_F = "correctIndex deve essere un intero da 1 a %d per questa domanda.",
        DIFFICULTY = "difficulty deve essere easy, medium, hard o very_hard.",
        SOURCE = "source deve essere un URL HTTPS di massimo 512 byte, senza spazi, controlli o markup.",
        RESERVED = "L'id del pacchetto 'all' è riservato.",
        UNKNOWN = "Nessun pacchetto è registrato con questo id.",
    },
    koKR = {
        PACK_F = "팩 %s: %s",
        QUESTION_F = "질문 %d: %s",
        TABLE_F = "%s 값은 일반 Lua 테이블이어야 합니다.",
        ID_F = "%s: 소문자 ASCII, 숫자, '-' 또는 '_' 1-48자이며 문자나 숫자로 시작해야 합니다.",
        TEXT_F = "%s: 제어 문자, 세로줄, 중괄호 없이 최대 %d바이트의 비어 있지 않은 일반 텍스트여야 합니다.",
        ARRAY_F = "%s 값은 항목 %d-%d개가 있는 빈칸 없는 배열이어야 합니다.",
        VERSION = "version 값은 2147483647 이하의 양의 정수여야 합니다.",
        LOCALE = "locale 값은 지원되는 WoW 언어 코드여야 합니다.",
        DUPLICATE_PACK = "이미 등록된 팩 id입니다.",
        DUPLICATE_QUESTION = "팩 내에서 질문 id가 중복됩니다.",
        DUPLICATE_CHOICE = "ASCII 대소문자와 앞뒤 공백을 제외하고 선택지가 서로 달라야 합니다.",
        INDEX_F = "이 질문의 correctIndex 값은 1부터 %d까지의 정수여야 합니다.",
        DIFFICULTY = "difficulty 값은 easy, medium, hard 또는 very_hard여야 합니다.",
        SOURCE = "source 값은 공백, 제어 문자, 마크업 없이 최대 512바이트의 HTTPS URL이어야 합니다.",
        RESERVED = "팩 id 'all'은 예약되어 있습니다.",
        UNKNOWN = "이 id로 등록된 팩이 없습니다.",
    },
    ptBR = {
        PACK_F = "Pacote %s: %s",
        QUESTION_F = "pergunta %d: %s",
        TABLE_F = "%s deve ser uma tabela Lua simples.",
        ID_F = "%s: 1-48 letras ASCII minúsculas, dígitos, '-' ou '_'; deve começar com letra ou dígito.",
        TEXT_F = "%s deve ser texto não vazio de até %d bytes, sem controles, barras verticais ou chaves.",
        ARRAY_F = "%s deve ser um vetor sem lacunas com %d a %d entradas.",
        VERSION = "version deve ser um inteiro positivo de até 2147483647.",
        LOCALE = "locale deve ser um código de idioma do WoW compatível.",
        DUPLICATE_PACK = "Este id de pacote já está registrado.",
        DUPLICATE_QUESTION = "Este id de pergunta se repete no pacote.",
        DUPLICATE_CHOICE = "As opções devem diferir, ignorando maiúsculas ASCII e espaços externos.",
        INDEX_F = "correctIndex deve ser um inteiro de 1 a %d para esta pergunta.",
        DIFFICULTY = "difficulty deve ser easy, medium, hard ou very_hard.",
        SOURCE = "source deve ser uma URL HTTPS de até 512 bytes, sem espaços, controles ou marcação.",
        RESERVED = "O id de pacote 'all' é reservado.",
        UNKNOWN = "Nenhum pacote está registrado com este id.",
    },
    ruRU = {
        PACK_F = "Набор %s: %s",
        QUESTION_F = "вопрос %d: %s",
        TABLE_F = "%s: требуется обычная таблица Lua.",
        ID_F = "%s: 1-48 строчных букв ASCII, цифр, '-' или '_'; первый символ — буква или цифра.",
        TEXT_F = "%s: непустой текст до %d байт без управляющих символов, вертикальных черт и фигурных скобок.",
        ARRAY_F = "%s: требуется массив без пропусков из %d-%d элементов.",
        VERSION = "version: требуется положительное целое число не больше 2147483647.",
        LOCALE = "locale: требуется поддерживаемый код языка WoW.",
        DUPLICATE_PACK = "Набор с таким id уже зарегистрирован.",
        DUPLICATE_QUESTION = "Этот id вопроса повторяется в наборе.",
        DUPLICATE_CHOICE = "Варианты должны различаться без учёта регистра ASCII и пробелов по краям.",
        INDEX_F = "correctIndex: для этого вопроса требуется целое число от 1 до %d.",
        DIFFICULTY = "difficulty: требуется easy, medium, hard или very_hard.",
        SOURCE = "source: требуется URL HTTPS до 512 байт без пробелов, управляющих символов и разметки.",
        RESERVED = "Id набора 'all' зарезервирован.",
        UNKNOWN = "Набор с таким id не зарегистрирован.",
    },
    zhCN = {
        PACK_F = "题包 %s：%s",
        QUESTION_F = "第 %d 题：%s",
        TABLE_F = "%s 必须是普通 Lua 表。",
        ID_F = "%s 须为 1-48 个小写 ASCII 字母、数字、'-' 或 '_'，并以字母或数字开头。",
        TEXT_F = "%s 须为不超过 %d 字节的非空纯文本，且不能包含控制字符、竖线或花括号。",
        ARRAY_F = "%s 必须是含 %d 至 %d 个元素的连续数组。",
        VERSION = "version 必须是不大于 2147483647 的正整数。",
        LOCALE = "locale 必须是受支持的 WoW 语言代码。",
        DUPLICATE_PACK = "此题包 id 已注册。",
        DUPLICATE_QUESTION = "此题目 id 在题包中重复。",
        DUPLICATE_CHOICE = "忽略 ASCII 大小写和首尾空格后，选项必须互不相同。",
        INDEX_F = "此题的 correctIndex 必须是 1 至 %d 的整数。",
        DIFFICULTY = "difficulty 必须是 easy、medium、hard 或 very_hard。",
        SOURCE = "source 必须是不超过 512 字节的 HTTPS URL，且不能包含空格、控制字符或标记。",
        RESERVED = "题包 id 'all' 为保留名称。",
        UNKNOWN = "未注册此 id 的题包。",
    },
    zhTW = {
        PACK_F = "題包 %s：%s",
        QUESTION_F = "第 %d 題：%s",
        TABLE_F = "%s 必須是一般 Lua 表。",
        ID_F = "%s 須為 1-48 個小寫 ASCII 字母、數字、'-' 或 '_'，並以字母或數字開頭。",
        TEXT_F = "%s 須為不超過 %d 位元組的非空純文字，且不可包含控制字元、直線或大括號。",
        ARRAY_F = "%s 必須是含 %d 至 %d 個元素的連續陣列。",
        VERSION = "version 必須是不大於 2147483647 的正整數。",
        LOCALE = "locale 必須是支援的 WoW 語言代碼。",
        DUPLICATE_PACK = "此題包 id 已註冊。",
        DUPLICATE_QUESTION = "此題目 id 在題包中重複。",
        DUPLICATE_CHOICE = "忽略 ASCII 大小寫及頭尾空格後，選項必須互不相同。",
        INDEX_F = "此題的 correctIndex 必須是 1 至 %d 的整數。",
        DIFFICULTY = "difficulty 必須是 easy、medium、hard 或 very_hard。",
        SOURCE = "source 必須是不超過 512 位元組的 HTTPS URL，且不可包含空格、控制字元或標記。",
        RESERVED = "題包 id 'all' 為保留名稱。",
        UNKNOWN = "尚未註冊此 id 的題包。",
    },
}
ERROR_TEXT.esMX = ERROR_TEXT.esES
ERROR_TEXT.enGB = ERROR_TEXT.enUS

local L = ERROR_TEXT[GetLocale()] or ERROR_TEXT.enUS
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
        questions[index] = question
        seenIds[question.id] = true
    end
    return {
        id = pack.id,
        title = title,
        version = version,
        author = author,
        locale = locale,
        questions = questions,
        count = count,
    }
end

function Quiz:RegisterQuestionPack(pack)
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

function Quiz:GetQuestionPacks()
    local packs = {}
    for _, pack in pairs(registry) do
        packs[#packs + 1] = {
            id = pack.id,
            title = pack.title,
            version = pack.version,
            author = pack.author,
            locale = pack.locale,
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

function Quiz:GetQuestions(packId)
    local questions = {}
    if packId == "all" then
        for _, metadata in ipairs(self:GetQuestionPacks()) do
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

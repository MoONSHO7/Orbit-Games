local _, Games = ...
local Quiz = Games.Quiz
local Cards = Games.Cards
local L = Games.L
local SAMPLE_COUNT = 32
local MAX_PLAYERS = 17
local FIRST_TOAST_STREAK = 5
local LAST_TOAST_STREAK = 11
local CARD_PREVIEW_TICK_SECONDS = 0.25
local CARD_PREVIEW_ACTION_DELAY = 0.85
local CARD_PREVIEW_LOCAL_DELAY = 5
local CARD_PREVIEW_HAND_DELAY = 8
local CARD_PREVIEW_BUY_IN = 1000
local CARD_PREVIEW_SMALL_BLIND = 5
local CARD_PREVIEW_BIG_BLIND = 10
local CARD_PREVIEW_RANDOM_RANGE = 4294967296
local CARD_PREVIEW_RANDOM_SEED_A = 2654435769
local CARD_PREVIEW_RANDOM_SEED_B = 608135816
local CARD_PREVIEW_RANDOM_SEED_C = 3084996962
local CARD_PREVIEW_RANDOM_SEED_D = 2330797291
local CARD_PREVIEW_PLAYER_ID = "dev-cards-local"
local CARD_PREVIEW_SESSION = "dev-cards-table"
local CARD_PREVIEW_NAMES = {
    "You",
    "Mira · CPU",
    "Tinker · CPU",
    "Asteria · CPU",
    "Bramble · CPU",
    "Pebble · CPU",
    "Quill · CPU",
    "Vesper · CPU",
}
local HOST_NAMES = {
    "Moth-MoonGuard",
    "Quizzical-Silvermoon",
    "Bramble-ArgentDawn",
    "Moonbeam-TarrenMill",
    "Thistledance-TheVentureCo",
    "Asteria-Saurfang",
    "Copperleaf-WyrmrestAccord",
    "Étoile-Hyjal",
    "星屑-白银之手",
    "별빛-아즈샤라",
    "Северныйветер-Гордунни",
    "Pip-Khazgoroth",
    "Pebble-Frostmourne",
    "Fable-EmeraldDream",
    "Lantern-QuelThalas",
    "Ashenveil-TwistingNether",
    "Cloudberry-ChamberofAspects",
    "Vesper-Ravencrest",
    "Sprocket-Drenden",
    "Wisp-Dalaran",
    "Marigold-BlackwaterRaiders",
    "Juniper-ThoriumBrotherhood",
    "Solstice-DathRemar",
    "Tinker-ScarletCrusade",
    "Nettle-Sentinels",
    "Firefly-AeriePeak",
    "Biscuit-DarkmoonFaire",
    "Drift-ScarshieldLegion",
    "Aurora-TheShatar",
    "Acorn-EarthenRing",
    "Quill-SteamwheedleCartel",
    "Stargazer-TheMaelstrom",
}
local PACK_TITLES = {
    "Warcraft basics",
    "Guild quiz night",
    "Raid bosses & famous last words",
    "Azeroth: the places nobody pronounces the same way",
    "Pop culture speed round",
    "Science, space & other enormous things",
    "Lore experts only: obscure stories from every corner of Azeroth",
    "A very short quiz",
    "世界の雑学 · World trivia",
    "Aventure en Azeroth · édition française",
    "Movie quotes and suspiciously familiar catchphrases",
    "Music through the decades",
    "Food, flags & faraway places",
    "Pets, mounts & tiny companions",
    "The extremely competitive Tuesday evening guild championship",
    "Surprise mix",
}
local STATES = { "open", "posting", "results", "paused" }

L.DEV_GAMES_TITLE = "Available games · DEV"
L.DEV_GAMES_NOTICE = "DEV preview · sample games only"
L.DEV_TOASTS_TITLE = "Streak preview · DEV"
L.DEV_CARDS_HOST = "Computer table · DEV"

Games.Development = { enabled = false, cardsPreview = {} }
local Development = Games.Development
local CardsPreview = Development.cardsPreview
local bitOr, bitXor = bit.bor, bit.bxor
local bitLeftShift, bitRightShift = bit.lshift, bit.rshift

local function HasLiveGame()
    for _, gameType in ipairs(Games.GameTypes:GetAll()) do
        if gameType.controller:IsRunning() or gameType.session:IsActive() then
            return true
        end
    end
    return false
end

local function BuildCardSeats()
    local seats = {}
    for seatNumber, name in ipairs(CARD_PREVIEW_NAMES) do
        seats[seatNumber] = {
            seat = seatNumber,
            id = seatNumber == 1 and CARD_PREVIEW_PLAYER_ID or "dev-cards-cpu-" .. seatNumber,
            name = name,
            stack = CARD_PREVIEW_BUY_IN,
        }
    end
    return seats
end

local function RotateLeft(value, places)
    return bitOr(bitLeftShift(value, places), bitRightShift(value, 32 - places))
end

local function CreateCardPreviewRandom()
    local stateA = CARD_PREVIEW_RANDOM_SEED_A
    local stateB = CARD_PREVIEW_RANDOM_SEED_B
    local stateC = CARD_PREVIEW_RANDOM_SEED_C
    local stateD = CARD_PREVIEW_RANDOM_SEED_D
    local function NextUInt32()
        local result = RotateLeft(stateB * 5, 7) * 9 % CARD_PREVIEW_RANDOM_RANGE
        local shifted = bitLeftShift(stateB, 9)
        stateC = bitXor(stateC, stateA)
        stateD = bitXor(stateD, stateB)
        stateB = bitXor(stateB, stateC)
        stateA = bitXor(stateA, stateD)
        stateC = bitXor(stateC, shifted)
        stateD = RotateLeft(stateD, 11)
        return result
    end
    return function(maximum)
        local acceptedRange = CARD_PREVIEW_RANDOM_RANGE - CARD_PREVIEW_RANDOM_RANGE % maximum
        local value
        repeat
            value = NextUInt32()
        until value < acceptedRange
        return value % maximum + 1
    end
end

local function ChooseComputerAction(preview, legal, seatNumber)
    local street = preview.model:GetState()
    if preview.aggressionStreet ~= street then
        preview.aggressionStreet = street
        preview.aggressionCount = 0
    end
    local choice = (preview.handNumber * 11 + seatNumber * 7 + #preview.model.hand.actions) % 12
    local canAggress = preview.aggressionCount == 0
    if canAggress and choice == 0 and legal.allIn then
        preview.aggressionCount = 1
        return "all_in"
    elseif canAggress and choice <= 2 and legal.bet then
        preview.aggressionCount = 1
        return "bet", legal.minTarget
    elseif canAggress and choice <= 2 and legal.raise then
        preview.aggressionCount = 1
        return "raise", legal.minTarget
    elseif choice == 3 and legal.call then
        return "fold"
    elseif legal.check then
        return "check"
    elseif legal.call then
        return "call"
    end
    return "fold"
end

function CardsPreview:GetView()
    local view = self.model:GetProjection(CARD_PREVIEW_PLAYER_ID)
    view.role = "host"
    view.currencyMode = Cards.CURRENCY_MODE
    view.allowRebuys = true
    view.hostName = L.DEV_CARDS_HOST
    view.session = CARD_PREVIEW_SESSION
    view.sessionId = CARD_PREVIEW_SESSION
    view.playerId = CARD_PREVIEW_PLAYER_ID
    view.connected = true
    if view.actionDeadline then
        view.actionStartedAt = self.stepStartedAt
        view.actionDeadline = self.nextStepAt
        view.rules.actionSeconds = self.stepDuration
    end
    return view
end

function CardsPreview:BuildDeck()
    return assert(Cards.Deck.Shuffle(self.deckRandom))
end

function CardsPreview:Schedule(now)
    if self.model:GetState() == "complete" then
        self.stepStartedAt = now
        self.stepDuration = CARD_PREVIEW_HAND_DELAY
        self.nextStepAt = now + CARD_PREVIEW_HAND_DELAY
        return
    end
    local actor = self.model.seats[self.model.hand.betting.actorSeat]
    self.stepStartedAt = now
    self.stepDuration = actor.id == CARD_PREVIEW_PLAYER_ID and CARD_PREVIEW_LOCAL_DELAY or CARD_PREVIEW_ACTION_DELAY
    self.nextStepAt = now + self.stepDuration
end

function CardsPreview:StartHand()
    if not self.active then
        return false, "no_active_session"
    end
    for seatNumber = 1, Cards.MAX_PLAYERS do
        local seat = self.model.seats[seatNumber]
        if seat.stack == 0 then
            assert(self.model:Rebuy(seat.id, CARD_PREVIEW_BUY_IN))
        end
    end
    self.handNumber = self.handNumber + 1
    self.aggressionStreet = nil
    self.aggressionCount = 0
    local firstButton = (self.handNumber - 1) % Cards.MAX_PLAYERS + 1
    local buttonSeat
    for offset = 0, Cards.MAX_PLAYERS - 1 do
        local candidate = (firstButton + offset - 1) % Cards.MAX_PLAYERS + 1
        local seat = self.model.seats[candidate]
        if not seat.sittingOut and seat.stack > 0 then
            buttonSeat = candidate
            break
        end
    end
    local now = GetTime()
    local started, reason = self.model:StartHand("dev-hand-" .. self.handNumber, buttonSeat, self:BuildDeck(), now)
    if started then
        self:Schedule(now)
        Cards.Table:Refresh()
    end
    return started, reason
end

function CardsPreview:Act(action, targetAmount)
    if not self.active then
        return false, "no_active_session"
    end
    local now = GetTime()
    local acted, reason = self.model:Act(CARD_PREVIEW_PLAYER_ID, action, targetAmount, now)
    if acted then
        self:Schedule(now)
    end
    return acted, reason
end

function CardsPreview:SetSittingOut(sittingOut)
    return self.model:SetSittingOut(CARD_PREVIEW_PLAYER_ID, sittingOut)
end

function CardsPreview:Rebuy()
    return self.model:Rebuy(CARD_PREVIEW_PLAYER_ID, CARD_PREVIEW_BUY_IN)
end

function CardsPreview:Tick(now)
    if HasLiveGame() or Cards.Table.previewDriver ~= self then
        self:Stop()
        return
    end
    if now >= self.nextStepAt then
        if self.model:GetState() == "complete" then
            assert(self:StartHand())
        else
            local actorSeat = self.model.hand.betting.actorSeat
            local actor = self.model.seats[actorSeat]
            local legal = assert(self.model:GetLegalActions(actor.id))
            local action, targetAmount = ChooseComputerAction(self, legal, actorSeat)
            assert(self.model:ApplyAction(actor.id, action, targetAmount, now, true))
            self:Schedule(now)
        end
    end
    Cards.Table:Refresh()
end

function CardsPreview:Stop()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self.active = false
    if Cards.Table.previewDriver == self then
        Cards.Table:SetPreviewDriver(nil)
    end
    self.model = nil
    self.deckRandom = nil
    self.stepStartedAt = nil
    self.stepDuration = nil
    self.nextStepAt = nil
end

function CardsPreview:Start()
    if Cards.Table.dragging then
        return false, "preview_unavailable"
    end
    self:Stop()
    local model, reason = Cards.TexasHoldem.Model.New({
        maxPlayers = Cards.MAX_PLAYERS,
        buyIn = CARD_PREVIEW_BUY_IN,
        smallBlind = CARD_PREVIEW_SMALL_BLIND,
        bigBlind = CARD_PREVIEW_BIG_BLIND,
        actionSeconds = Cards.ACTION_SECONDS_MIN,
    }, BuildCardSeats())
    if not model then
        return false, reason
    end
    self.model = model
    self.deckRandom = CreateCardPreviewRandom()
    self.handNumber = 0
    self.active = true
    Cards.Table:SetEditing(false)
    if not Cards.Table:SetPreviewDriver(self) then
        self:Stop()
        return false, "preview_unavailable"
    end
    assert(self:StartHand())
    self.ticker = C_Timer.NewTicker(CARD_PREVIEW_TICK_SECONDS, function()
        local ok, failure = pcall(self.Tick, self, GetTime())
        if not ok then
            self:Stop()
            geterrorhandler()(failure)
        end
    end)
    return true
end

local function BuildGames()
    local games = {}
    for index = 1, SAMPLE_COUNT do
        games[index] = {
            preview = true,
            hostName = HOST_NAMES[index],
            sessionId = "dev-preview-" .. index,
            gameTypeId = Quiz.id,
            protocolVersion = 2,
            activityId = Quiz.id,
            activityVersion = 1,
            title = PACK_TITLES[(index - 1) % #PACK_TITLES + 1],
            description = Quiz.L.GAME_TYPE_QUIZ_DESCRIPTION,
            phase = STATES[(index - 1) % #STATES + 1],
            playerCount = (index - 1) % MAX_PLAYERS + 1,
            maxPlayers = MAX_PLAYERS,
            joinable = (index - 1) % MAX_PLAYERS + 1 < MAX_PLAYERS,
        }
    end
    return games
end

function Development:ShowGames()
    if not Games.Main.initialized then
        return Games.Main:Report(Games.Main.initializationError or L.HOST_UNAVAILABLE)
    end
    self.games = self.games or BuildGames()
    self.cardsPreview:Stop()
    Quiz.Widget:SetStreakPreview(nil)
    self.enabled = true
    Games.UI:SetGamePreview({ games = self.games, title = L.DEV_GAMES_TITLE, notice = L.DEV_GAMES_NOTICE })
    Games.UI:Create()
    Games.UI:SetTab("play")
    Games.UI.frame:Show()
    return true
end

function Development:HideGames()
    self.enabled = false
    Games.UI:SetGamePreview(nil)
    Quiz.Widget:SetStreakPreview(nil)
    self.cardsPreview:Stop()
    return true
end

function Development:ShowCards()
    if not Games.Main.initialized then
        return Games.Main:Report(Games.Main.initializationError or L.HOST_UNAVAILABLE)
    end
    if HasLiveGame() then
        return false
    end
    self.enabled = false
    Games.UI:SetGamePreview(nil)
    Quiz.Widget:SetStreakPreview(nil)
    if not self.cardsPreview:Start() then
        return false
    end
    return true
end

function Development:ShowToasts()
    if not Games.Main.initialized then
        return Games.Main:Report(Games.Main.initializationError or L.HOST_UNAVAILABLE)
    end
    if HasLiveGame() then
        return false
    end
    self.enabled = false
    Games.UI:SetGamePreview(nil)
    self.cardsPreview:Stop()
    local events = {}
    for streak = FIRST_TOAST_STREAK, LAST_TOAST_STREAK do
        events[#events + 1] = { name = HOST_NAMES[#events + 1], streak = streak }
    end
    if not Quiz.Widget:SetStreakPreview({ packTitle = L.DEV_TOASTS_TITLE, events = events }) then
        return false
    end
    return true
end

function Development:Command(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" or command == "games" then
        return self:ShowGames()
    elseif command == "cards" or command == "holdem" or command == "poker" then
        return self:ShowCards()
    elseif command == "toasts" or command == "streaks" then
        return self:ShowToasts()
    elseif command == "off" then
        return self:HideGames()
    end
    return false
end

SLASH_ORBITGAMESDEV1 = "/ogdev"
SlashCmdList.ORBITGAMESDEV = function(message)
    Development:Command(message)
end

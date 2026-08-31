local _, Quiz = ...
local L = Quiz.L
local SAMPLE_COUNT = 32
local MAX_PLAYERS = 17
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
local LEAGUES = { "Practice", "Guild night", "Season one", "Weekend trivia" }
local STATES = { "open", "posting", "results", "paused" }

L.DEV_GAMES_TITLE = "Available games · DEV"
L.DEV_GAMES_NOTICE = "DEV preview · sample games only"
L.DEV_GAMES_ON_F = "%d dummy games shown. Join is disabled. /oqdev off restores real games; /reload resets the preview."
L.DEV_GAMES_OFF = "Dummy games cleared. Available games shows real hosts again."
L.DEV_HELP = "/oqdev games: show dummy games | /oqdev off: restore real games"

Quiz.Development = { enabled = false }
local Development = Quiz.Development

local function BuildGames()
    local games = {}
    for index = 1, SAMPLE_COUNT do
        games[index] = {
            preview = true,
            hostName = HOST_NAMES[index],
            session = "dev-preview-" .. index,
            packName = PACK_TITLES[(index - 1) % #PACK_TITLES + 1],
            league = LEAGUES[(index - 1) % #LEAGUES + 1],
            state = STATES[(index - 1) % #STATES + 1],
            players = (index - 1) % MAX_PLAYERS + 1,
        }
    end
    return games
end

function Development:ShowGames()
    if not Quiz.Main.initialized then
        return Quiz.Main:Report(Quiz.Main.initializationError or L.HOST_UNAVAILABLE)
    end
    self.games = self.games or BuildGames()
    self.enabled = true
    Quiz.UI:SetGamePreview({ games = self.games, title = L.DEV_GAMES_TITLE, notice = L.DEV_GAMES_NOTICE })
    Quiz.UI:Create()
    Quiz.UI:SetTab("play")
    Quiz.UI.frame:Show()
    Quiz:Print(L.DEV_GAMES_ON_F:format(#self.games))
    return true
end

function Development:HideGames()
    self.enabled = false
    Quiz.UI:SetGamePreview(nil)
    Quiz:Print(L.DEV_GAMES_OFF)
    return true
end

function Development:Command(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "" or command == "games" then
        return self:ShowGames()
    elseif command == "off" then
        return self:HideGames()
    end
    Quiz:Print(L.DEV_HELP)
    return false
end

SLASH_ORBITQUIZDEV1 = "/oqdev"
SlashCmdList.ORBITQUIZDEV = function(message)
    Development:Command(message)
end

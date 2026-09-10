local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L

local HOST_PHASES = { ready = true, posting = true, open = true, results = true, paused = true }
local MAX_PLAYERS = 17

local Advert = {}
Quiz.Advert = Advert

function Advert:GetHosted(controller, session)
    local game = controller.game
    local sessionId = session.hostSession
    local phase = game and (game.state == "finished" and controller.finishPending and "results" or game.state)
    if not sessionId or not game or not HOST_PHASES[phase] then
        return nil
    end
    local title = L.ALL_PACKS
    if game.settings.packId ~= "all" then
        title = game.settings.packId
        for _, pack in ipairs(Quiz:GetPacks()) do
            if pack.id == game.settings.packId then
                title = pack.title
                break
            end
        end
    end
    local playerCount = 1
    for _ in pairs(session.peers) do
        playerCount = playerCount + 1
    end
    return {
        sessionId = sessionId,
        activityId = Quiz.id,
        activityVersion = 1,
        title = title,
        description = L.GAME_TYPE_QUIZ_DESCRIPTION,
        phase = phase,
        playerCount = playerCount,
        maxPlayers = MAX_PLAYERS,
        joinable = playerCount < MAX_PLAYERS,
    }
end

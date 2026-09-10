local _, Games = ...
local Cards = Games.Cards
local L = Cards.L

local PHASES = {
    between_hands = "ready",
    preflop = "open",
    flop = "open",
    turn = "open",
    river = "open",
    complete = "results",
}

local Advert = {}
Cards.Advert = Advert

function Advert:GetHosted(controller, session)
    local game = controller.game
    if not session.hostSession or not game then
        return nil
    end
    local state = game:GetState()
    local phase = controller.paused and "paused" or PHASES[state]
    if not phase then
        return nil
    end
    local playerCount = 0
    for _ in pairs(game.seatsById) do
        playerCount = playerCount + 1
    end
    return {
        sessionId = session.hostSession,
        activityId = Cards.VARIANT_ID,
        activityVersion = Cards.ACTIVITY_VERSION,
        title = L.VARIANT_TEXAS_HOLDEM,
        description = L.GAME_TYPE_CARDS_DESCRIPTION,
        phase = phase,
        playerCount = playerCount,
        maxPlayers = controller.settings.maxPlayers,
        joinable = not controller.paused
            and not controller:IsHandActive()
            and playerCount < controller.settings.maxPlayers,
    }
end

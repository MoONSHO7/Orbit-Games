local _, Games = ...
local Quiz = Games.Quiz

assert(Games.GameTypes:Register({
    id = Quiz.id,
    title = Quiz.L.GAME_TYPE_QUIZ,
    resultsTitle = Quiz.L.RESULTS_TITLE,
    protocolVersion = 2,
    default = true,
    controller = Quiz.Controller,
    session = Quiz.Session,
    storage = Quiz.Store,
    advert = Quiz.Advert,
    commands = Quiz.Commands,
    locale = Quiz.L,
    ui = {
        hostPage = Quiz.HostPage,
        settingsPage = Quiz.SettingsPage,
        hud = Quiz.Widget,
        resultsPage = Quiz.ScoreView,
    },
}))

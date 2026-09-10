local _, Games = ...
local Cards = Games.Cards

assert(Games.GameTypes:Register({
    id = Cards.id,
    title = Cards.L.GAME_TYPE_CARDS,
    resultsTitle = Cards.L.RESULTS_TITLE,
    protocolVersion = Cards.PROTOCOL_VERSION,
    controller = Cards.Controller,
    session = Cards.Session,
    storage = Cards.Store,
    advert = Cards.Advert,
    commands = Cards.Commands,
    locale = Cards.L,
    ui = {
        hostPage = Cards.HostPage,
        settingsPage = Cards.SettingsPage,
        hud = Cards.Table,
        resultsPage = Cards.ResultsPage,
    },
}))

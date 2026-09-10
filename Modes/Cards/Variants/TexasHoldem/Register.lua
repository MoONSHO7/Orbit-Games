local _, Games = ...
local Cards = Games.Cards
local Holdem = Cards.TexasHoldem

assert(Cards.Variants:Register({
    id = Cards.VARIANT_ID,
    title = Cards.L.VARIANT_TEXAS_HOLDEM,
    protocolVersion = Cards.ACTIVITY_VERSION,
    rules = Holdem.Rules,
    model = Holdem.Model,
}))

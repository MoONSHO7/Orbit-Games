local _, Games = ...
local Cards = Games.Cards

local SUITS = { "C", "D", "H", "S" }
local RANK_CODES = { "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A" }
local CODE_TO_ID = {}
local CODES = {}

for suitIndex, suit in ipairs(SUITS) do
    for rankIndex, rankCode in ipairs(RANK_CODES) do
        local cardId = (suitIndex - 1) * #RANK_CODES + rankIndex
        local code = rankCode .. suit
        CODES[cardId] = code
        CODE_TO_ID[code] = cardId
    end
end

local CardCatalog = {
    COUNT = #SUITS * #RANK_CODES,
    MIN_RANK = 2,
    MAX_RANK = 14,
}
Cards.CardCatalog = CardCatalog

function CardCatalog:IsCard(cardId)
    return type(cardId) == "number" and cardId % 1 == 0 and cardId >= 1 and cardId <= self.COUNT
end

function CardCatalog:GetRank(cardId)
    if not self:IsCard(cardId) then
        return nil
    end
    return (cardId - 1) % #RANK_CODES + self.MIN_RANK
end

function CardCatalog:GetSuit(cardId)
    if not self:IsCard(cardId) then
        return nil
    end
    return math.floor((cardId - 1) / #RANK_CODES) + 1
end

function CardCatalog:GetCode(cardId)
    return self:IsCard(cardId) and CODES[cardId] or nil
end

function CardCatalog:FromCode(code)
    if type(code) ~= "string" then
        return nil
    end
    return CODE_TO_ID[code:upper()]
end

function CardCatalog:GetAll()
    local cardIds = {}
    for cardId = 1, self.COUNT do
        cardIds[cardId] = cardId
    end
    return cardIds
end

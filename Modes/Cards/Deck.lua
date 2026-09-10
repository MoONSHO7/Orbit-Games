local _, Games = ...
local Cards = Games.Cards
local CardCatalog = Cards.CardCatalog

local Deck = {}
Deck.__index = Deck
Cards.Deck = Deck

local function IsArray(value, expectedCount)
    if type(value) ~= "table" or getmetatable(value) ~= nil or #value ~= expectedCount then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > expectedCount then
            return false
        end
        count = count + 1
    end
    return count == expectedCount
end

function Deck.Normalize(order)
    if not IsArray(order, CardCatalog.COUNT) then
        return nil, "invalid_deck"
    end
    local normalized, seen = {}, {}
    for index, cardId in ipairs(order) do
        if not CardCatalog:IsCard(cardId) or seen[cardId] then
            return nil, "invalid_deck"
        end
        normalized[index] = cardId
        seen[cardId] = true
    end
    return normalized
end

function Deck.Shuffle(random)
    if type(random) ~= "function" then
        return nil, "invalid_random_function"
    end
    local order = CardCatalog:GetAll()
    for index = #order, 2, -1 do
        local other = random(index)
        if type(other) ~= "number" or other % 1 ~= 0 or other < 1 or other > index then
            return nil, "invalid_random_result"
        end
        order[index], order[other] = order[other], order[index]
    end
    return order
end

function Deck.New(order)
    local normalized, reason = Deck.Normalize(order)
    if not normalized then
        return nil, reason
    end
    return setmetatable({ order = normalized, nextIndex = 1 }, Deck)
end

function Deck.NewShuffled(random)
    local order, reason = Deck.Shuffle(random)
    if not order then
        return nil, reason
    end
    return Deck.New(order)
end

function Deck:Draw(count)
    if type(count) ~= "number" or count % 1 ~= 0 or count < 1 then
        return nil, "invalid_draw_count"
    end
    if self.nextIndex + count - 1 > #self.order then
        return nil, "deck_exhausted"
    end
    local cards = {}
    for index = 1, count do
        cards[index] = self.order[self.nextIndex]
        self.nextIndex = self.nextIndex + 1
    end
    return cards
end

function Deck:Remaining()
    return #self.order - self.nextIndex + 1
end

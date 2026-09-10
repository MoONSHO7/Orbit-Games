local _, Games = ...
local Cards = Games.Cards
local CardCatalog = Cards.CardCatalog

local SCORE_BASE = 15
local SCORE_CATEGORY_FACTOR = SCORE_BASE ^ 5
local CATEGORY_NAMES = {
    [0] = "high_card",
    [1] = "one_pair",
    [2] = "two_pair",
    [3] = "three_of_a_kind",
    [4] = "straight",
    [5] = "flush",
    [6] = "full_house",
    [7] = "four_of_a_kind",
    [8] = "straight_flush",
}

local HandEvaluator = {}
Cards.HandEvaluator = HandEvaluator

local function IsCardArray(cards)
    if type(cards) ~= "table" or getmetatable(cards) ~= nil or #cards < 5 or #cards > 7 then
        return false
    end
    local seen, count = {}, 0
    for key, cardId in pairs(cards) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #cards then
            return false
        end
        if not CardCatalog:IsCard(cardId) or seen[cardId] then
            return false
        end
        seen[cardId] = true
        count = count + 1
    end
    return count == #cards
end

local function EncodeScore(category, kickers)
    local score = category * SCORE_CATEGORY_FACTOR
    for index = 1, 5 do
        score = score + (kickers[index] or 0) * SCORE_BASE ^ (5 - index)
    end
    return score
end

local function FindStraightHigh(present)
    if present[14] then
        present[1] = true
    end
    local run = 0
    for rank = 14, 1, -1 do
        if present[rank] then
            run = run + 1
            if run == 5 then
                return rank + 4
            end
        else
            run = 0
        end
    end
    return nil
end

local function EvaluateFive(cards)
    local counts, present, suits = {}, {}, {}
    for index = 1, 5 do
        local cardId = cards[index]
        local rank, suit = CardCatalog:GetRank(cardId), CardCatalog:GetSuit(cardId)
        counts[rank] = (counts[rank] or 0) + 1
        present[rank] = true
        suits[suit] = (suits[suit] or 0) + 1
    end
    local flush = false
    for _, count in pairs(suits) do
        if count == 5 then
            flush = true
            break
        end
    end
    local straightHigh = FindStraightHigh(present)
    local groups = {}
    for rank = 14, 2, -1 do
        if counts[rank] then
            groups[#groups + 1] = { rank = rank, count = counts[rank] }
        end
    end
    table.sort(groups, function(left, right)
        if left.count ~= right.count then
            return left.count > right.count
        end
        return left.rank > right.rank
    end)

    local category, kickers
    if flush and straightHigh then
        category, kickers = 8, { straightHigh }
    elseif groups[1].count == 4 then
        category, kickers = 7, { groups[1].rank, groups[2].rank }
    elseif groups[1].count == 3 and groups[2].count == 2 then
        category, kickers = 6, { groups[1].rank, groups[2].rank }
    elseif flush then
        category, kickers = 5, {}
        for rank = 14, 2, -1 do
            if counts[rank] then
                kickers[#kickers + 1] = rank
            end
        end
    elseif straightHigh then
        category, kickers = 4, { straightHigh }
    elseif groups[1].count == 3 then
        category, kickers = 3, { groups[1].rank }
        for index = 2, #groups do
            kickers[#kickers + 1] = groups[index].rank
        end
    elseif groups[1].count == 2 and groups[2].count == 2 then
        category, kickers = 2, { groups[1].rank, groups[2].rank, groups[3].rank }
    elseif groups[1].count == 2 then
        category, kickers = 1, { groups[1].rank }
        for index = 2, #groups do
            kickers[#kickers + 1] = groups[index].rank
        end
    else
        category, kickers = 0, {}
        for rank = 14, 2, -1 do
            if counts[rank] then
                kickers[#kickers + 1] = rank
            end
        end
    end
    return category, kickers, EncodeScore(category, kickers)
end

function HandEvaluator.Evaluate(cards)
    if not IsCardArray(cards) then
        return nil, "invalid_cards"
    end
    local best
    local count = #cards
    for first = 1, count - 4 do
        for second = first + 1, count - 3 do
            for third = second + 1, count - 2 do
                for fourth = third + 1, count - 1 do
                    for fifth = fourth + 1, count do
                        local selected = { cards[first], cards[second], cards[third], cards[fourth], cards[fifth] }
                        local category, kickers, score = EvaluateFive(selected)
                        if not best or score > best.score then
                            best = {
                                category = CATEGORY_NAMES[category],
                                categoryRank = category,
                                kickers = kickers,
                                score = score,
                                cards = selected,
                            }
                        end
                    end
                end
            end
        end
    end
    return best
end

function HandEvaluator.Compare(left, right)
    if
        type(left) ~= "table"
        or type(left.score) ~= "number"
        or type(right) ~= "table"
        or type(right.score) ~= "number"
    then
        return nil, "invalid_evaluation"
    end
    if left.score == right.score then
        return 0
    end
    return left.score > right.score and 1 or -1
end

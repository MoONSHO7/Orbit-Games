local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L
local MAX_ROWS = 100
local TITLE_COLOR = { 1, 0.82, 0 }
local TEXT_COLOR = { 1, 1, 1 }
local SCORE_COLOR = { 1, 0.82, 0 }

Quiz.ScoreTooltip = {}
local ScoreTooltip = Quiz.ScoreTooltip

function ScoreTooltip:Create()
    if self.frame then
        return
    end
    self.frame = CreateFrame("GameTooltip", "OrbitGamesQuizScoreTooltip", UIParent, "GameTooltipTemplate")
    self.frame:SetClampedToScreen(true)
    self.frame:HookScript("OnHide", function()
        self.owner, self.anchor, self.standings, self.revision = nil, nil, nil, nil
    end)
end

function ScoreTooltip:IsOwned(owner)
    return self.frame ~= nil and self.frame:IsShown() and self.owner == owner
end

function ScoreTooltip:Hide(owner)
    if not self.frame or owner and self.owner ~= owner then
        return
    end
    self.owner, self.anchor, self.standings, self.revision = nil, nil, nil, nil
    self.frame:Hide()
end

function ScoreTooltip:Show(owner, standings, revision, anchor)
    self:Create()
    if self:IsOwned(owner) and self.anchor == anchor and self.standings == standings and self.revision == revision then
        return false
    end
    self.owner, self.anchor, self.standings, self.revision = owner, anchor, standings, revision
    self.frame:SetOwner(owner, anchor)
    self.frame:SetText(L.W_SCORE_STANDINGS, unpack(TITLE_COLOR))
    if standings == nil then
        self.frame:AddLine(L.W_SCORE_STANDINGS_LOADING, unpack(TEXT_COLOR))
    elseif #standings == 0 then
        self.frame:AddLine(L.W_SCORE_NO_GAME_RESULTS, unpack(TEXT_COLOR))
    else
        for index = 1, math.min(#standings, MAX_ROWS) do
            local player = standings[index]
            self.frame:AddDoubleLine(
                L.W_SCORE_RANK_F:format(index, player.name),
                L.W_SCORE_POINTS_F:format(player.score),
                unpack(TEXT_COLOR),
                unpack(SCORE_COLOR)
            )
        end
    end
    self.frame:Show()
    return true
end

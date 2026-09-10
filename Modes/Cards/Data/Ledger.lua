local _, Games = ...
local Cards = Games.Cards

local Ledger = {}
Cards.Ledger = Ledger

local LedgerMixin = {}
LedgerMixin.__index = LedgerMixin

local function CopyPlayer(player)
    return {
        id = player.id,
        name = player.name,
        buyIn = player.buyIn,
        rebuy = player.rebuy,
        finalStack = player.finalStack,
        net = player.finalStack and player.finalStack - player.buyIn - player.rebuy or nil,
    }
end

function Ledger.New(sessionId)
    return setmetatable({ sessionId = sessionId, players = {}, order = {} }, LedgerMixin)
end

function LedgerMixin:AddPlayer(id, name, buyIn)
    if self.players[id] then
        return false, "duplicate_player"
    end
    local player = {
        id = id,
        name = name,
        buyIn = buyIn,
        rebuy = 0,
    }
    self.players[id] = player
    self.order[#self.order + 1] = id
    return true
end

function LedgerMixin:RecordRebuy(id, amount)
    local player = self.players[id]
    if not player then
        return false, "invalid_player"
    end
    player.rebuy = player.rebuy + amount
    return true
end

function LedgerMixin:SetFinalStack(id, amount)
    local player = self.players[id]
    if not player then
        return false, "invalid_player"
    end
    player.finalStack = amount
    return true
end

function LedgerMixin:GetPlayers()
    local players = {}
    for _, id in ipairs(self.order) do
        players[#players + 1] = CopyPlayer(self.players[id])
    end
    return players
end

function LedgerMixin:BuildSettlement(variantId, endedAt)
    local players = self:GetPlayers()
    for _, player in ipairs(players) do
        if player.finalStack == nil then
            return nil, "invalid_settlement"
        end
    end
    return {
        id = self.sessionId,
        variantId = variantId,
        endedAt = endedAt,
        players = players,
    }
end

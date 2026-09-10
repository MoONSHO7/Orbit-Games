local _, Games = ...
local Cards = Games.Cards

local Commands = {}
Cards.Commands = Commands

function Commands:Handle(command)
    if command == "table" then
        Cards.Table:Show()
    elseif command == "results" or command == "ledger" then
        Games.UI:Show("results")
    else
        return false
    end
    return true
end

function Commands:OnLogin() end

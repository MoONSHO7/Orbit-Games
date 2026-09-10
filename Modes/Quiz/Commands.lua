local _, Games = ...
local Quiz = Games.Quiz
local Commands = {}
Quiz.Commands = Commands

function Commands:Handle(command)
    if command == "packs" then
        Games.UI:Show("host")
    elseif command == "scores" then
        Games.UI:Show("results")
    else
        return false
    end
    return true
end

function Commands:OnLogin()
    local errors = Quiz:GetPackErrors()
    if errors[1] then
        Quiz.Controller:SetNotice(errors[1])
    end
end

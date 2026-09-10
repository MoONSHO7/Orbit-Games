local Games = OrbitGames

local Compatibility = {}

function Compatibility:RegisterQuestionPack(pack)
    return Games.Quiz:RegisterPack(pack)
end

function Compatibility:RegisterPack(pack)
    return Games.Quiz:RegisterPack(pack)
end

function Compatibility:GetQuestionPacks()
    return Games.Quiz:GetPacks()
end

function Compatibility:GetPackRules(packId)
    return Games.Quiz:GetRules(packId)
end

function Compatibility:GetQuestions(packId)
    return Games.Quiz:GetQuestions(packId)
end

function Compatibility:GetPackErrors()
    return Games.Quiz:GetPackErrors()
end

_G.OrbitQuiz = Compatibility

if OrbitQuizDB ~= nil and Games.Main.initialized then
    local imported, reason = Games.Store:ImportMode("quiz", OrbitQuizDB, OrbitQuizDB.minimap)
    if imported then
        OrbitGamesDB = Games.Store.db
        Games.Main.activeGameTypeId = "quiz"
        OrbitQuizDB = nil
        Games.Minimap:Refresh()
        if Games.UI.frame then
            Games.UI:LoadSettings()
        end
    elseif reason == "legacy_not_needed" then
        OrbitQuizDB = nil
    else
        OrbitGamesDB = nil
        Games.Main:AbortInitialization(reason)
    end
end

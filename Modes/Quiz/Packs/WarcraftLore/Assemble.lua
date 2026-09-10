local _, Games = ...
local Quiz = Games.Quiz

Quiz.Lore = { questions = {} }

function Quiz.Lore:Add(eraId, eraTitle, source, rows)
    for _, row in ipairs(rows) do
        self.questions[#self.questions + 1] = {
            id = eraId .. "_" .. row[1],
            difficulty = row[2],
            prompt = row[3],
            choices = row[4],
            correctIndex = row[5],
            explanation = row[6],
            category = row[7] or eraTitle,
            era = eraTitle,
            source = source,
        }
    end
end

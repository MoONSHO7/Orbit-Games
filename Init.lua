local addonName, Quiz = ...

Quiz.addonName = addonName
Quiz.version = "0.9"
Quiz.ANSWER_SECONDS = 15
Quiz.MIN_CHOICES = 4
Quiz.MAX_CHOICES = 6
Quiz.WIDGET_SCALE_MIN = 50
Quiz.WIDGET_SCALE_MAX = 200
Quiz.WIDGET_SCALE_STEP = 5
Quiz.WIDGET_SCALE_DEFAULT = 100
Quiz.DIFFICULTIES = { easy = true, medium = true, hard = true, very_hard = true }

_G.OrbitQuiz = Quiz

function Quiz:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0Orbit-Quiz|r: " .. message)
end

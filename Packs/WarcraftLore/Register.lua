local _, Quiz = ...

Quiz:RegisterQuestionPack({
    id = "warcraft-lore",
    title = "Warcraft Lore",
    version = 2,
    author = "Orbit-Quiz",
    locale = "enUS",
    rules = {
        version = 1,
        answerSeconds = 15,
        revealSeconds = 3,
        allowAnswerChanges = true,
        shuffleQuestions = true,
        shuffleChoices = true,
        repeatQuestions = true,
        questionLimit = 0,
        correctPoints = 1,
        speedBonusPerSecond = 0.1,
        wrongPenaltyStart = 1,
        wrongPenaltyEnd = 0.5,
        wrongPenaltyCurve = 2.5,
        streakBonusPerCorrect = 0.1,
        streakBonusMax = 0.5,
    },
    questions = Quiz.Lore.questions,
})

Quiz.Lore = nil

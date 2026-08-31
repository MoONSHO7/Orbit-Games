local _, Quiz = ...

Quiz:RegisterQuestionPack({
    id = "warcraft-lore",
    title = "Warcraft Lore",
    version = 2,
    author = "Orbit-Quiz",
    locale = "enUS",
    questions = Quiz.Lore.questions,
})

Quiz.Lore = nil

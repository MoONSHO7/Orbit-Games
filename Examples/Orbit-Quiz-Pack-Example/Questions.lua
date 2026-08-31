OrbitQuiz:RegisterQuestionPack({
    id = "example_everyday",
    title = "Example: Everyday Trivia",
    version = 1,
    author = "Your name",
    locale = "enUS",
    questions = {
        {
            id = "triangle_sides",
            prompt = "How many sides does a triangle have?",
            choices = { "Two", "Three", "Four", "Five" },
            correctIndex = 2,
            explanation = "A triangle has three sides.",
            category = "Everyday Trivia",
        },
        {
            id = "minutes_per_hour",
            prompt = "How many minutes are in one hour?",
            choices = { "30", "45", "60", "100" },
            correctIndex = 3,
            explanation = "One hour contains 60 minutes.",
            category = "Everyday Trivia",
        },
        {
            id = "keyboard_strings",
            prompt = "Which instrument normally has keys, pedals and strings?",
            choices = { "Piano", "Trumpet", "Flute", "Drum" },
            correctIndex = 1,
            explanation = "An acoustic piano uses keys and pedals to play and control its strings.",
            category = "Everyday Trivia",
        },
    },
})

return function(Quiz)
    local REMOVED_CHAT_SETTINGS = { "bridgeChat", "channel", "customChannel", "channelPassword", "answerMode" }
    local assertions = 0
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(
            actual == expected,
            (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
        )
    end
    local function SameTable(actual, expected, message)
        Check(type(actual) == "table", message .. " is a table")
        for key, value in pairs(expected) do
            local field = message .. "." .. tostring(key)
            if type(value) == "table" then
                SameTable(actual[key], value, field)
            else
                Same(actual[key], value, field)
            end
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " has no unexpected " .. tostring(key))
        end
    end
    local function NoChatSettings(settings, message)
        for _, key in ipairs(REMOVED_CHAT_SETTINGS) do
            Same(settings[key], nil, message .. ": " .. key)
        end
    end
    local function OldChatSettings()
        return {
            bridgeChat = true,
            channel = "CHANNEL",
            customChannel = "OldQuizChannel",
            channelPassword = "retired-password",
            answerMode = "PUBLIC",
        }
    end
    local function KeepOrder(maximum)
        return maximum
    end
    local function Questions(count)
        local questions = {}
        for index = 1, count do
            questions[index] = {
                key = "test:q" .. index,
                packId = "test",
                id = "q" .. index,
                prompt = "Question " .. index,
                choices = { "Right", "Wrong one", "Wrong two", "Wrong three" },
                correctIndex = 1,
                explanation = "The first authored answer is correct.",
            }
        end
        return questions
    end
    local function Settings(count)
        return {
            league = "Default",
            packId = "all",
            questionCount = count or 2,
            duration = Quiz.ANSWER_SECONDS,
            autoAdvance = false,
            hostName = "",
        }
    end
    local function NewGame(count, deckSize, random)
        local game, reason = Quiz.Game.New(Settings(count), Questions(deckSize or count), random or KeepOrder)
        Check(game ~= nil, reason)
        return game
    end
    local function Open(game, id, now)
        local round, reason = game:PrepareQuestion(id)
        Check(round ~= nil, reason)
        Check(game:OpenQuestion(now), "question should open")
        return round
    end
    local function ClosedWrong(id, name)
        return {
            id = id,
            questionKey = "test:q1",
            number = 1,
            duration = 15,
            scoringVersion = 2,
            correctCount = 0,
            totalAnswers = 1,
            answers = {
                {
                    guid = "Player-1-A",
                    name = name or "Alice-Realm",
                    choiceIndex = 2,
                    correct = false,
                    elapsed = 1,
                    points = -0.9,
                },
            },
        }
    end
    local function ClosedCorrect(id, elapsed)
        local result = ClosedWrong(id)
        result.correctCount = 1
        result.answers[1].choiceIndex = 1
        result.answers[1].correct = true
        result.answers[1].elapsed = elapsed or 1
        result.answers[1].points = Quiz.Scoring.Calculate(true, result.answers[1].elapsed, result.duration)
        return result
    end
    local function PreviousRound(id, correct, elapsed, duration, tagged)
        local result = ClosedWrong(id)
        result.duration, result.scoringVersion = duration or 20, tagged and 1 or nil
        result.correctCount = correct and 1 or 0
        local answer = result.answers[1]
        answer.correct, answer.choiceIndex, answer.elapsed = correct, correct and 1 or 2, elapsed or 1
        answer.points = correct and (10 + math.floor(result.duration - answer.elapsed + 0.0000001)) / 10 or 0
        return result
    end

    Same(Quiz.ANSWER_SECONDS, 15, "all locally hosted answer windows are fixed at fifteen seconds")
    Same(Quiz.Scoring.VERSION, 2, "current results identify the new penalty scoring rules")
    Same(
        Quiz.Scoring.Calculate(true, 0, 15),
        2.5,
        "fifteen-second instant correct answers cap at two-and-a-half points"
    )
    Same(Quiz.Scoring.Calculate(true, 5.001, 15), 1.9, "fixed-window timing uses whole remaining seconds")
    Same(Quiz.Scoring.Calculate(true, 15, 15), 1, "fifteen-second deadline retains the base correct point")
    Same(Quiz.Scoring.Calculate(false, 0, 15), -1, "instant wrong answers lose one point")
    Same(Quiz.Scoring.Calculate(false, 15, 15), -0.5, "deadline wrong answers lose half a point")
    Same(Quiz.Scoring.Calculate(true, 0, 20), 3, "historical twenty-second scoring remains readable")
    Same(Quiz.Scoring.Calculate(true, 5, 20), 2.5, "whole remaining seconds add tenths")
    Same(Quiz.Scoring.Calculate(true, 5.001, 20), 2.4, "fractional seconds do not earn a full tenth")
    Same(Quiz.Scoring.Calculate(true, 10, 20), 2, "half-time answer earns one base point and one timing point")
    Same(Quiz.Scoring.Calculate(true, 19, 20), 1.1, "last whole second earns one tenth")
    Same(Quiz.Scoring.Calculate(true, 19.001, 20), 1, "subsecond remaining time does not earn a bonus")
    Same(Quiz.Scoring.Calculate(true, 20, 20), 1, "exact deadline is a base point in the pure model")
    Same(Quiz.Scoring.Calculate(true, 0, 60), 7, "long windows retain the same per-second rate")
    Same(Quiz.Scoring.Calculate(true, 15, 60), 5.5, "forty-five remaining seconds earn four-and-a-half bonus points")
    Same(Quiz.Scoring.Calculate(true, 0.7 - 0.2, 20), 2.9, "fractional elapsed time remains fractional")
    Same(Quiz.Scoring.Calculate(true, 1.1 - 0.1, 20), 2.9, "binary rounding at a whole second is stable")
    Same(
        Quiz.Scoring.Calculate(true, 4.00000000001, 20),
        2.6,
        "tiny timestamp subtraction error preserves the boundary"
    )
    Same(Quiz.Scoring.Calculate(true, 4.00001, 20), 2.5, "epsilon does not grant a meaningful partial second")
    for duration = 10, 60 do
        local previousPenalty = -1
        for elapsed = 0, duration do
            Same(Quiz.Scoring.Calculate(true, elapsed, duration), (10 + duration - elapsed) / 10, "whole-second score")
            local penalty = Quiz.Scoring.Calculate(false, elapsed, duration)
            Check(penalty >= -1 and penalty <= -0.5, "wrong-answer penalties remain within signed bounds")
            Check(penalty >= previousPenalty, "waiting never increases the wrong-answer penalty")
            previousPenalty = penalty
            if elapsed < duration then
                Same(
                    Quiz.Scoring.Calculate(true, elapsed + 0.25, duration),
                    (9 + duration - elapsed) / 10,
                    "a fraction of a remaining second never rounds upward"
                )
            end
        end
    end
    local preciseScore = 0
    for index = 1, 1000 do
        preciseScore = Quiz.Scoring.Add(preciseScore, 1.1)
        Same(preciseScore, index * 11 / 10, "score accumulation retains exact tenths without drift")
    end

    local game = NewGame(2)
    Same(game.state, "ready", "new game state")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 1, 10), "cannot answer before preparing")
    local round = game:PrepareQuestion(7)
    Same(game.state, "posting", "prepared question has not started its timer")
    Check(round.startedAt == nil and round.deadline == nil, "posting must not consume the answer window")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 1, 10), "cannot answer before open")
    Check(game:OpenQuestion(100), "open question")
    Same(round.deadline, 115, "fixed fifteen-second deadline starts after opening")
    Check(not game:OpenQuestion(110), "opening twice must not extend the deadline")
    Same(round.deadline, 115, "deadline is immutable")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 6, 1, 101), "stale question rejected")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 0, 101), "choice zero rejected")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 5, 101), "choice out of range rejected")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 1.5, 101), "fractional choice rejected")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, "A", 101), "unparsed choice rejected")
    Check(not game:Submit("", "Alice-Realm", 7, 1, 101), "missing guid rejected")
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 1, 99), "before-start timestamp rejected")
    Check(
        game:Submit("Player-1-A", "Alice-Realm", 7, 2, 101, "a1"),
        "invalid earlier submissions do not consume answers"
    )
    Check(game:Submit("Player-1-A", "Alice-Realm", 7, 1, 102, "a2"), "later answer replaces first selection")
    Same(round.answers["Player-1-A"].points, 2.3, "replacement score uses its own arrival time")
    Check(game:Submit("Player-1-A", "Alice-Realm", 7, 2, 115, "a3"), "correct selection can be changed to wrong")
    Same(round.answers["Player-1-A"].points, -0.5, "latest wrong answer uses its new late penalty")
    Check(game:Submit("Player-1-B", "Bob-Realm", 7, 1, 115), "exact deadline is accepted")
    Check(not game:Submit("Player-1-C", "Carol-Realm", 7, 1, 115.001), "late answer rejected")
    Same(#game:GetStandings(), 0, "active answers are not yet scored")
    Check(game:CloseQuestion(114.99) == nil, "cannot close early")
    local result = game:CloseQuestion(115)
    Check(result ~= nil, "close at deadline")
    Same(result.correctCount, 1, "correct count")
    Same(result.totalAnswers, 2, "total answer count")
    Same(game.completed, 1, "one finalized question")
    Same(game.state, "results", "results state")
    Same(game:GetStandings()[1].name, "Bob-Realm", "standings sort by final points")
    Same(game:GetStandings()[2].score, -0.5, "incorrect final selection can leave the player below zero")
    Same(game:GetStandings()[2].answers, 1, "three selections still count as one finalized answer")
    Same(game:GetStandings()[2].incorrect, 1, "only the final selection determines correctness count")
    Check(game:CloseQuestion(130) == nil, "question only closes once")
    Same(game.completed, 1, "duplicate close cannot increment question count")
    Same(game:GetStandings()[2].score, -0.5, "duplicate close cannot change scores")
    Check(not game:Submit("Player-1-D", "Dave-Realm", 7, 1, 109), "post-close answer rejected even with old time")
    Check(game:Pause("break"), "pause after results")
    Same(game.round, round, "pausing results preserves scored round")
    Same(game.lastResult, result, "pausing results preserves result")
    Check(game:Resume(), "resume from scored round")
    Check(game:PrepareQuestion(7) == nil, "question token cannot be reused")
    Open(game, 8, 200)
    Check(not game:Submit("Player-1-A", "Alice-Realm", 7, 1, 201), "previous question answer cannot leak forward")
    Check(game:Submit("Player-1-A", "Alice-Realm", 8, 1, 201), "player may answer each new question")
    result = game:CloseQuestion(220)
    Same(game.state, "finished", "target finalized rounds finishes game")
    Same(game.completed, 2, "two finalized rounds")
    Same(game:GetStandings()[1].score, 1.9, "a later correct answer can recover a previous penalty")
    Check(not game:Pause("late"), "finished game cannot be paused")
    Check(game:PrepareQuestion(9) == nil, "finished game cannot prepare")

    local revised = NewGame(1)
    local revisedRound = Open(revised, 9, 0)
    Check(revised:Submit("Player-Revision", "Revision-Realm", 9, 1, 1, "request:1"), "first version accepts")
    Check(
        revised:Submit("Player-Revision", "Revision-Realm", 9, 1, 5, "request:1"),
        "retry acknowledges existing action"
    )
    Same(revisedRound.answers["Player-Revision"].elapsed, 1, "action retry cannot re-time an accepted answer")
    Same(revisedRound.answers["Player-Revision"].points, 2.4, "action retry cannot lower accepted timing points")
    Check(
        not revised:Submit("Player-Revision", "Revision-Realm", 9, 2, 5, "request:1"),
        "a repeated token with different content is rejected"
    )
    for _, action in ipairs({ "", "bad|id", "bad\nid", string.rep("a", 129), false, 42, {} }) do
        Check(
            not revised:Submit("Player-Revision", "Revision-Realm", 9, 2, 5, action),
            "malformed action token rejects"
        )
    end
    Same(
        revisedRound.answers["Player-Revision"].actionId,
        "request:1",
        "invalid actions cannot overwrite the latest token"
    )
    Check(
        revised:Submit("Player-Revision", "Revision-Realm", 9, 1, 8, "request:3"),
        "a newer same-choice action acknowledges the existing selection"
    )
    Same(revisedRound.answers["Player-Revision"].elapsed, 1, "same-choice action cannot rewrite the accepted timestamp")
    Same(revisedRound.answers["Player-Revision"].points, 2.4, "same-choice update keeps the original timing score")
    Same(revisedRound.answers["Player-Revision"].actionId, "request:3", "same-choice input advances replay bookkeeping")
    Check(revised:Submit("Player-Revision", "Revision-Realm", 9, 2, 9, "request:2"), "caller owns action ordering")
    Same(revisedRound.answers["Player-Revision"].choiceIndex, 2, "model does not impose lexical token order")
    Check(revised:Submit("Player-Revision", "Revision-Realm", 9, 1, 9.25), "unversioned model update accepts")
    Check(
        revised:Submit("Player-Revision", "Revision-Realm", 9, 1, 9.5),
        "unversioned repeated selection is acknowledged without retiming"
    )
    Same(revisedRound.answers["Player-Revision"].points, 1.5, "latest changed model selection determines timing")
    Check(
        not revised:Submit("Player-Revision", "Revision-Realm", 9, 2, 15.01, "request:4"),
        "late update cannot replace answer"
    )
    local revisedResult = revised:CloseQuestion(15)
    Same(revisedResult.totalAnswers, 1, "many updates produce one result entry")
    Same(revisedResult.correctCount, 1, "final correct selection wins")
    Same(revisedResult.answers[1].elapsed, 9.25, "result stores only final changed selection timing")
    Same(revised:GetStandings()[1].score, 1.5, "standings award only the last changed selection")
    Same(revised:GetStandings()[1].incorrect, 0, "transient incorrect selections do not count")

    local guesses = NewGame(1)
    local guessRound = Open(guesses, 10, 0)
    Check(guesses:Submit("Guess", "Guess-Realm", 10, 2, 0, "guess:1"), "an immediate wrong selection is accepted")
    Same(guessRound.answers.Guess.points, -1, "an immediate wrong selection has the maximum penalty")
    Check(
        guesses:Submit("Guess", "Guess-Realm", 10, 2, 14, "guess:2"),
        "a new token may acknowledge the same wrong choice"
    )
    Same(guessRound.answers.Guess.elapsed, 0, "a new token alone cannot retime an early wrong guess")
    Same(guessRound.answers.Guess.points, -1, "reclicking the same wrong answer cannot reduce its penalty")
    Same(guessRound.answers.Guess.actionId, "guess:2", "same wrong-choice acknowledgement advances its action token")
    Check(
        not guesses:Submit("Guess", "Guess-Realm", 10, 3, 14, "guess:2"),
        "the same token cannot contradict the accepted choice"
    )
    Check(
        guesses:Submit("Guess", "Guess-Realm", 10, 3, 14, "guess:3"),
        "changing to another wrong choice receives a new time"
    )
    Same(guessRound.answers.Guess.elapsed, 14, "actual changed selection replaces the accepted time")
    Same(guessRound.answers.Guess.points, -0.5, "a genuinely changed late wrong choice uses the late penalty")
    Check(
        guesses:Submit("Guess", "Guess-Realm", 10, 1, 14.5, "guess:4"),
        "a wrong answer can be corrected near the deadline"
    )
    Same(guessRound.answers.Guess.points, 1, "late correction removes the earlier wrong penalty")
    Check(
        guesses:Submit("Guess", "Guess-Realm", 10, 2, 14.75, "guess:5"),
        "a final wrong replacement determines the result"
    )
    local guessResult = guesses:CloseQuestion(15)
    Same(guessResult.answers[1].elapsed, 14.75, "finalization retains only the final changed selection time")
    Same(guessResult.answers[1].points, -0.5, "only the final wrong selection applies its penalty")
    Same(guesses:GetStandings()[1].score, -0.5, "transient guesses do not stack their penalties")
    Same(guesses:GetStandings()[1].incorrect, 1, "multiple changes still count as one incorrect answer")

    local copiedSettings = Settings(1)
    copiedSettings.extra = { label = "original" }
    local copiedQuestions = Questions(2)
    local originalChoice = copiedQuestions[1].choices[1]
    local copiedGame = Quiz.Game.New(copiedSettings, copiedQuestions, KeepOrder)
    copiedSettings.duration = 60
    copiedSettings.extra.label = "modified"
    copiedQuestions[1].prompt = "modified"
    copiedQuestions[1].choices[1] = "modified"
    Same(copiedGame.settings.duration, 15, "settings input is copied with the fixed answer window")
    Same(copiedGame.settings.extra.label, "original", "nested input is copied")
    local copiedRound = Open(copiedGame, 11, 0)
    Same(copiedRound.prompt, "Question 1", "question input is copied")
    Same(copiedRound.choices[1], originalChoice, "choice input is copied")

    for _, oldDuration in ipairs({ 20, 60, 0, 1, 600, math.huge, "60", false, {} }) do
        local fixedSettings = Settings(1)
        fixedSettings.duration = oldDuration
        local fixedGame = Quiz.Game.New(fixedSettings, Questions(1), KeepOrder)
        Check(fixedGame ~= nil, "removed duration option never controls direct game creation")
        Same(fixedGame.settings.duration, 15, "game model normalizes every supplied duration to fifteen")
        Same(fixedSettings.duration, oldDuration, "normalization never mutates caller settings")
        fixedGame.settings.duration = 60
        local fixedRound = Open(fixedGame, 1, 100)
        Same(fixedRound.deadline, 115, "even a mutated game setting cannot extend the answer clock")
        fixedGame.settings.duration = 1
        Check(fixedGame:Submit("Fixed", "Fixed-Realm", 1, fixedRound.correctIndex, 104), "fixed-window answer accepts")
        Same(fixedRound.answers.Fixed.points, 2.1, "mutable settings cannot change correct-answer timing points")
        fixedGame.settings.duration = 600
        Check(not fixedGame:Submit("Fixed", "Fixed-Realm", 1, fixedRound.correctIndex, 115.01), "fixed cutoff rejects")
        Check(fixedGame:CloseQuestion(114.99) == nil, "fixed round cannot close before fifteen seconds")
        local fixedResult = fixedGame:CloseQuestion(115)
        Same(fixedResult.duration, 15, "history records the actual fifteen-second answer window")
        Same(fixedResult.scoringVersion, 2, "history identifies the rules that scored the result")
        Same(fixedResult.answers[1].points, 2.1, "mutable settings cannot re-score a finalized answer")
    end
    local noDuration = Settings(1)
    noDuration.duration = nil
    local defaultClock = Quiz.Game.New(noDuration, Questions(1), KeepOrder)
    Check(defaultClock ~= nil, "game callers no longer need to specify a duration")
    Same(Open(defaultClock, 1, 0).deadline, 15, "omitted duration still creates the fixed window")

    local retiredGameSettings = Settings(1)
    for key, value in pairs(OldChatSettings()) do
        retiredGameSettings[key] = value
    end
    local retiredGame = Quiz.Game.New(retiredGameSettings, Questions(1), KeepOrder)
    Check(retiredGame ~= nil, "direct model callers can still supply ignored retired chat settings")
    local retiredRound = Open(retiredGame, 1, 100)
    Same(retiredRound.deadline, 115, "retired chat configuration never delays the model answer clock")
    Check(retiredGame:Submit("Retired", "Retired-Realm", 1, 1, 101), "retired chat settings cannot block model answers")
    Same(retiredGame:CloseQuestion(115).answers[1].points, 2.4, "retired chat settings never affect scoring")

    local randomCalls = {}
    local shuffled = NewGame(1, 3, function(maximum)
        randomCalls[#randomCalls + 1] = maximum
        return 1
    end)
    Same(#randomCalls, 2, "deck shuffle uses linear number of draws")
    local shuffledRound = Open(shuffled, 12, 0)
    Same(#randomCalls, 5, "four choices use three shuffle draws")
    Same(shuffledRound.choices[shuffledRound.correctIndex], "Right", "correct choice follows shuffle")
    Check(shuffledRound.correctIndex ~= 1, "test must actually reorder choices")
    Check(shuffled:Submit("Player-1-A", "Alice-Realm", 12, shuffledRound.correctIndex, 1), "shuffled answer accepted")
    Same(shuffled:CloseQuestion(15).answers[1].points, 2.4, "remapped choice earns correctness and timing points")

    local replacements = NewGame(2, 4)
    local consumed = {}
    for _, id in ipairs({ 20, 21 }) do
        local active = Open(replacements, id, id)
        Check(not consumed[active.key], "voided cards do not repeat")
        consumed[active.key] = true
        Check(replacements:Submit("Player-1-A", "Alice-Realm", id, 1, id + 1), "answer before void")
        Check(replacements:Pause("interrupted"), "pause live question")
        Same(replacements.round, nil, "live answers discarded")
        Same(replacements.completed, 0, "void does not count as finalized")
        Same(#replacements:GetStandings(), 0, "void does not award points")
        Check(replacements:Resume(), "resume to replacement")
    end
    Same(replacements.total, 2, "reserve deck preserves target while replacements remain")
    for _, id in ipairs({ 22, 23 }) do
        local active = Open(replacements, id, id)
        Check(not consumed[active.key], "replacement is an unused card")
        consumed[active.key] = true
        Check(replacements:CloseQuestion(id + 20) ~= nil, "replacement finalizes")
    end
    Same(replacements.completed, 2, "void replacements reach finalized target")
    Same(replacements.state, "finished", "replacement game finishes")

    local exhausted = NewGame(3, 1)
    Same(exhausted.total, 1, "game target capped by available questions")
    Check(exhausted:PrepareQuestion(30) ~= nil, "prepare only card")
    Check(exhausted:Pause("posting interrupted"), "posting questions may be voided")
    Check(exhausted:Resume(), "resume exhausted game")
    Same(exhausted.state, "finished", "no repeats when all cards were voided")
    Same(exhausted.completed, 0, "exhausted void never scored")
    Same(exhausted.total, 0, "attainable total reflects exhaustion")
    local stopped = NewGame(1)
    Open(stopped, 31, 0)
    Check(stopped:Submit("Player-1-A", "Alice-Realm", 31, 1, 1), "answer before stop")
    Check(stopped:Stop(), "stop game")
    Same(stopped.state, "stopped", "stopped state")
    Same(stopped.round, nil, "stop discards live answers")
    Same(#stopped:GetStandings(), 0, "stop does not score active answers")
    Check(not stopped:Resume(), "stopped game cannot resume")
    Check(Quiz.Game.New(Settings(), {}) == nil, "empty deck rejected")
    local duplicateQuestions = Questions(2)
    duplicateQuestions[2].key = duplicateQuestions[1].key
    Check(Quiz.Game.New(Settings(), duplicateQuestions) == nil, "duplicate keys rejected")
    Check(Quiz.Game.New(Settings(), Questions(2), function()
        return 0
    end) == nil, "invalid RNG rejected")

    local continuousSettings = Settings(1)
    continuousSettings.continuous = true
    continuousSettings.questionCount = nil
    local continuousDeckSize = 61
    local continuous = Quiz.Game.New(continuousSettings, Questions(continuousDeckSize), KeepOrder)
    Check(continuous ~= nil, "continuous mode does not require the unused finite question count")
    Same(continuous.continuous, true, "continuous mode is explicit on the game")
    Same(continuous.cycle, 1, "first shuffled cycle starts at one")
    Same(continuous.total, continuousDeckSize, "continuous total is the entire selected deck")
    Same(continuous.usedIds, nil, "continuous mode never allocates a growing question-ID map")
    local continuousDb = Quiz.Store:Initialize(nil)
    local cycleKeys = {}
    local previousKey
    local continuousRounds = continuousDeckSize * 3
    for id = 1, continuousRounds do
        local active = Open(continuous, id, id * 30)
        local expectedCycle = math.floor((id - 1) / continuousDeckSize) + 1
        local expectedNumber = (id - 1) % continuousDeckSize + 1
        Same(active.cycle, expectedCycle, "round identifies its deck cycle")
        Same(continuous.cycle, expectedCycle, "game exposes current cycle")
        Same(active.number, expectedNumber, "round number resets within each cycle")
        if active.number == 1 then
            cycleKeys = {}
            Check(active.key ~= previousKey, "cycle boundary avoids an immediate repeat")
        end
        Check(not cycleKeys[active.key], "each question appears once within a cycle")
        cycleKeys[active.key] = true
        previousKey = active.key
        Check(
            continuous:Submit("Player-Cycle", "Cycle-Realm", id, active.correctIndex, id * 30 + 1),
            "cycle answer accepts"
        )
        local closed = continuous:CloseQuestion(id * 30 + 20)
        Check(closed ~= nil, "continuous question closes")
        Same(closed.cycle, expectedCycle, "result records its cycle")
        Same(continuous.state, "results", "continuous close never finishes the game")
        Check(Quiz.Store:RecordRound("Continuous", "PUBLIC", closed), "cycle result persists beyond fifty questions")
    end
    Same(continuous.completed, continuousRounds, "completed counts all session rounds across cycles")
    Same(continuous.total, continuousDeckSize, "cycling never changes the deck total")
    Same(#continuous.deck, continuousDeckSize, "cycling keeps bounded deck storage")
    Same(continuous.usedIds, nil, "many cycles still have no per-round ID map")
    Same(continuous.lastQuestionId, continuousRounds, "continuous ID memory is one high watermark")
    Same(continuous:GetStandings()[1].score, continuousRounds * 24 / 10, "session points continue across cycles")
    Same(continuous:GetStandings()[1].correct, continuousRounds, "session answer counts continue across cycles")
    Same(#continuousDb.leagues.Continuous.PUBLIC.history, 50, "continuous saved history remains bounded")
    Same(
        continuousDb.leagues.Continuous.PUBLIC.history[50].number,
        61,
        "saved history accepts within-cycle numbers above fifty"
    )
    Same(continuousDb.leagues.Continuous.PUBLIC.history[50].cycle, 3, "saved history retains cycle identity")
    local lastCycleResult = continuous.lastResult
    local lastCycleRound = continuous.round
    Check(continuous:PrepareQuestion(continuousRounds) == nil, "continuous ID cannot be reused")
    Check(continuous:PrepareQuestion(continuousRounds - 10) == nil, "older continuous ID cannot be replayed")
    Same(continuous.cycle, 3, "invalid ID does not advance a cycle")
    Same(continuous.lastQuestionId, continuousRounds, "invalid ID does not change high watermark")
    Check(continuous:Pause("break"), "continuous results may be paused")
    Same(continuous.round, lastCycleRound, "pausing scored continuous result preserves its round")
    Same(continuous.lastResult, lastCycleResult, "pausing continuous results preserves committed result")
    Check(continuous:Resume(), "continuous results resume after several full cycles")
    Same(continuous.state, "ready", "completed count above total does not finish continuous mode")
    local nextCycleRound = continuous:PrepareQuestion(continuousRounds + 1)
    Same(nextCycleRound.cycle, 4, "next prepared question begins another cycle")
    Same(nextCycleRound.number, 1, "new cycle numbering restarts")
    Check(continuous:Stop(), "continuous game ends only when stopped")
    Same(continuous.state, "stopped", "continuous stop uses stopped state")
    Same(continuous.round, nil, "continuous stop discards the exposed unscored question")
    Check(continuous:PrepareQuestion(continuousRounds + 2) == nil, "stopped continuous game cannot prepare again")
    Same(continuous:GetStandings()[1].score, continuousRounds * 24 / 10, "stopping keeps finalized session scores")
    Check(Quiz.Store:Initialize(continuousDb) ~= nil, "continuous history reloads")
    Same(
        Quiz.Store:GetStandings("Continuous", "PUBLIC")[1].score,
        continuousRounds * 24 / 10,
        "continuous totals survive reload"
    )

    local boundarySettings = Settings(1)
    boundarySettings.continuous = true
    local boundaries = Quiz.Game.New(boundarySettings, Questions(2), function()
        return 1
    end)
    previousKey = nil
    for id = 1, 12 do
        local active = Open(boundaries, id, id * 30)
        Check(active.key ~= previousKey, "forced boundary collision is corrected without repeating")
        previousKey = active.key
        Check(boundaries:CloseQuestion(id * 30 + 20) ~= nil, "corrected boundary question closes")
    end
    Same(boundaries.cycle, 6, "two-question deck keeps cycling through corrected shuffles")

    local voidCycles = Quiz.Game.New(boundarySettings, Questions(3), KeepOrder)
    previousKey = nil
    for id = 1, 3 do
        local active = voidCycles:PrepareQuestion(id)
        Check(active ~= nil, "prepare a continuous question for voiding")
        Same(active.number, id, "void consumes the exposed position within its cycle")
        if id == 2 then
            Check(voidCycles:OpenQuestion(0), "open a continuous question before voiding")
            Check(voidCycles:Submit("Player-Voided", "Voided-Realm", id, active.correctIndex, 1), "answer before void")
        end
        previousKey = active.key
        Check(voidCycles:Pause("interrupted"), "void posting or open continuous question")
        Same(voidCycles.total, 3, "continuous pause does not shrink total")
        Same(voidCycles.completed, 0, "voided continuous questions never count as finalized")
        Same(#voidCycles:GetStandings(), 0, "voided continuous answers never score")
        Check(voidCycles:Resume(), "continuous pause resumes")
        Same(voidCycles.state, "ready", "exhausted continuous cycle remains resumable")
    end
    local afterVoids = voidCycles:PrepareQuestion(4)
    Same(afterVoids.cycle, 2, "voiding every exposed question starts a new shuffled cycle")
    Same(afterVoids.number, 1, "cycle number resets after voided deck")
    Check(afterVoids.key ~= previousKey, "voided boundary question does not immediately repeat")

    local single = Quiz.Game.New(boundarySettings, Questions(1), KeepOrder)
    for id = 1, 8 do
        local active = Open(single, id, id * 30)
        Same(active.number, 1, "single-question pack always displays position one")
        Same(active.cycle, id, "single-question pack advances cycle every round")
        Check(
            single:Submit("Player-Solo", "Solo-Realm", id, active.correctIndex, id * 30 + 1),
            "single-pack answer accepts"
        )
        Check(single:CloseQuestion(id * 30 + 20) ~= nil, "single-pack question closes")
        Same(single.state, "results", "single-question continuous pack never finishes")
    end
    Open(single, 9, 270)
    Check(single:Submit("Player-Solo", "Solo-Realm", 9, single.round.correctIndex, 271), "answer before one-pack pause")
    Check(single:Pause("void"), "one-question continuous pack can be voided")
    Check(single:Resume(), "one-question continuous pack resumes after void")
    local singleReplacement = single:PrepareQuestion(10)
    Same(singleReplacement.cycle, 10, "single-pack void consumes its cycle without stopping")
    Same(single:GetStandings()[1].score, 8 * 24 / 10, "single-pack void leaves previous scores intact")
    Same(single.usedIds, nil, "single-pack continuous ID memory remains bounded")

    local failShuffle = false
    local failedCycle = Quiz.Game.New(boundarySettings, Questions(2), function(maximum)
        return failShuffle and 0 or maximum
    end)
    for id = 1, 2 do
        Open(failedCycle, id, id * 30)
        failedCycle:CloseQuestion(id * 30 + 20)
    end
    failShuffle = true
    Check(failedCycle:PrepareQuestion(3) == nil, "bad cycle RNG result rejects preparation")
    Same(failedCycle.cycle, 1, "failed cycle shuffle does not advance cycle")
    Same(failedCycle.lastQuestionId, 2, "failed cycle shuffle does not consume the question token")
    Same(failedCycle.state, "results", "failed shuffle leaves previous results available")
    failShuffle = false
    Check(failedCycle:PrepareQuestion(3) ~= nil, "valid retry can reuse the unconsumed token")
    local invalidContinuous = Settings()
    invalidContinuous.continuous = "yes"
    Check(Quiz.Game.New(invalidContinuous, Questions(2)) == nil, "non-boolean continuous mode rejects")
    local finiteIds = NewGame(2)
    Open(finiteIds, 10, 0)
    finiteIds:CloseQuestion(20)
    Check(finiteIds:PrepareQuestion(2) ~= nil, "finite mode preserves its existing unique but unordered ID contract")

    local store = Quiz.Store
    local db = store:Initialize(nil)
    Check(db ~= nil, "fresh database initializes")
    Same(db.schemaVersion, 6, "fresh database uses the personal-pack scoring schema")
    Same(next(db.leagues), nil, "fresh current-scoring boards are empty")
    Same(next(db.legacyLeagues), nil, "fresh installations have no old-scale archive")
    Same(#store:GetLegacyStandings("Missing", "PUBLIC"), 0, "missing legacy league returns empty standings")
    local widgetPosition = store:GetWidgetPosition()
    Same(widgetPosition.x, 0.5, "widget defaults to normalized horizontal center")
    Same(widgetPosition.y, 0.65, "widget defaults above normalized screen center")
    widgetPosition.x = 0.1
    Same(store:GetWidgetPosition().x, 0.5, "position getter never exposes the saved table")
    Check(store:SaveWidgetPosition(0.25, 0.75), "normalized widget position saves")
    Same(db.widgetPosition.x, 0.25, "position saves outside gameplay configuration")
    Same(store:GetSettings().widgetPosition, nil, "widget position never becomes a game setting")
    Check(store:SaveSettings({ duration = 30 }), "game settings remain independently writable")
    Same(store:GetWidgetPosition().x, 0.25, "game settings cannot reset widget position")
    Same(store:GetWidgetPosition().y, 0.75, "game settings preserve vertical widget position")
    for _, edge in ipairs({ 0, 1 }) do
        Check(store:SaveWidgetPosition(edge, edge), "screen edges are valid normalized positions")
        Same(store:GetWidgetPosition().x, edge, "edge x coordinate persists")
        Same(store:GetWidgetPosition().y, edge, "edge y coordinate persists")
    end
    for _, invalid in ipairs({ -0.01, 1.01, math.huge, -math.huge, 0 / 0, false, "0.5", {} }) do
        local ok, reason = store:SaveWidgetPosition(invalid, 0.5)
        Check(not ok, "invalid horizontal position rejects")
        Same(reason, "invalid_widget_position", "position validation has a stable failure code")
        Check(not store:SaveWidgetPosition(0.5, invalid), "invalid vertical position rejects")
        Same(store:GetWidgetPosition().x, 1, "invalid positions leave stored x untouched")
        Same(store:GetWidgetPosition().y, 1, "invalid positions leave stored y untouched")
    end
    Check(not store:SaveWidgetPosition(nil, 0.5), "missing x is rejected")
    Check(not store:SaveWidgetPosition(0.5, nil), "missing y is rejected")
    Check(store:SaveWidgetPosition(0.2, 0.8), "valid position remains writable after invalid inputs")
    Same(store:GetSettings().duration, 15, "moving a widget cannot alter the fixed gameplay timing")
    Check(store:SaveSettings({ duration = 20 }), "legacy duration values normalize during settings save")
    Same(store:GetSettings().league, "Default", "default league")
    NoChatSettings(db.settings, "fresh SavedVariables have no visible-chat configuration")
    NoChatSettings(store:GetSettings(), "settings reader exposes no visible-chat options")
    Same(store:GetSettings().hostName, "", "join target defaults empty")
    Check(store:SaveSettings(OldChatSettings()), "old settings objects may still be saved")
    NoChatSettings(db.settings, "old visible-chat values are not resaved")
    for _, key in ipairs(REMOVED_CHAT_SETTINGS) do
        for _, value in ipairs({ true, false, "UNKNOWN", "bad\n|channel", string.rep("x", 129), 1, math.huge, {} }) do
            Check(store:SaveSettings({ [key] = value }), "retired setting values are ignored rather than validated")
            NoChatSettings(db.settings, "retired values cannot become saved configuration")
            NoChatSettings(store:GetSettings(), "retired values cannot reach gameplay settings")
        end
    end
    Same(store:GetSettings().league, "Default", "ignored legacy chat writes preserve relevant settings")
    for _, name in ipairs({
        "",
        "Quizhost",
        "Quizhost-TestRealm",
        "Quizhost-Area52",
        "Quizhost-Quel'Thalas",
        "Quizhost-Azjol-Nerub",
        "Étoile-Hyjal",
        "玩家-白银之手",
    }) do
        Check(store:SaveSettings({ hostName = name }), "plain character or realm-qualified join name accepts")
        Same(store:GetSettings().hostName, name, "host name persists without rewriting")
    end
    local validHostName = store:GetSettings().hostName
    for _, name in ipairs({
        " ",
        "Host Realm",
        "Host|Realm",
        "Host\nRealm",
        "/invite",
        "Host@Realm",
        "-Realm",
        "Host-",
        "Host--Realm",
        string.rep("a", 129),
        false,
        42,
        {},
    }) do
        Check(not store:SaveSettings({ hostName = name }), "malformed join target rejects")
    end
    Same(store:GetSettings().hostName, validHostName, "invalid host names do not replace previous target")
    Check(store:SaveSettings({ hostName = "", continuous = true }), "runtime-only mode may accompany saved settings")
    Same(store:GetSettings().continuous, nil, "continuous flag does not become persistent configuration")
    Same(db.settings.continuous, nil, "SavedVariables omit runtime-only continuous state")
    local settings = store:GetSettings()
    settings.league = "QuizLeague"
    Same(store:GetSettings().league, "Default", "settings getter returns copy")
    Check(store:SaveSettings(settings), "league settings save")
    settings.league = "Changed"
    Same(store:GetSettings().league, "QuizLeague", "saved settings are copied")
    Check(store:SaveSettings({ league = "Default" }), "league can be restored independently")
    Check(not store:SaveSettings({ league = "" }), "empty league rejected")
    Check(not store:SaveSettings({ league = string.rep("x", 49) }), "oversized league rejected")
    Check(not store:SaveSettings({ questionCount = 0 }), "zero questions rejected")
    Check(not store:SaveSettings({ questionCount = 51 }), "too many questions rejected")
    Check(store:SaveSettings({ duration = 9 }), "retired shorter duration option is ignored")
    Same(store:GetSettings().duration, 15, "shorter saved duration cannot override the fixed clock")
    Check(store:SaveSettings({ duration = 61 }), "retired longer duration option is ignored")
    Same(store:GetSettings().duration, 15, "longer saved duration cannot override the fixed clock")
    Check(not store:SaveSettings({ autoAdvance = "yes" }), "boolean setting rejects string")
    Same(store:NextQuestionId(), 1, "first global question id")
    Same(store:NextQuestionId(), 2, "question ids increase before any score")

    local wrong = ClosedWrong(2)
    Check(store:RecordRound("Guild", "PUBLIC", wrong), "final result persists")
    Check(not store:RecordRound("Guild", "PUBLIC", wrong), "same result does not persist twice")
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -0.9, "incorrect negative score persists")
    wrong.answers[1].points = 3
    wrong.answers[1].name = "Changed-Realm"
    Same(store:GetStandings("Guild", "PUBLIC")[1].name, "Alice-Realm", "result input is copied")
    Same(db.leagues.Guild.PUBLIC.history[1].answers[1].points, -0.9, "history input is copied")
    Check(not store:RecordRound("Guild", "WHISPER", ClosedWrong(3)), "new whisper results are forbidden")
    Check(not store:RecordRound("Guild", "LOCAL", ClosedWrong(3)), "new rehearsal results are forbidden")
    Check(store:RecordRound("Other", "PUBLIC", ClosedWrong(4)), "league result persists separately")
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -0.9, "rejected modes and other leagues do not mix")
    Same(#store:GetStandings("Guild", "WHISPER"), 0, "rejected write does not create a whisper board")
    Same(#store:GetStandings("Missing", "PUBLIC"), 0, "unplayed league is empty")
    local exposedStandings = store:GetStandings("Guild", "PUBLIC")
    exposedStandings[1].score = 999
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -0.9, "standings getter returns copies")
    Same(store:NextQuestionId(), 5, "recorded ids advance global counter")
    local reloaded = store:Initialize(db)
    Check(reloaded ~= db, "reload validates and copies saved state")
    Same(reloaded.widgetPosition.x, 0.2, "saved widget horizontal position survives reload")
    Same(reloaded.widgetPosition.y, 0.8, "saved widget vertical position survives reload")
    db.widgetPosition.x = 0.9
    Same(store:GetWidgetPosition().x, 0.2, "reload copies the saved position instead of sharing input")
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -0.9, "negative totals survive reload")
    Same(store:NextQuestionId(), 6, "global ids survive reload")
    Check(not store:RecordRound("Guild", "PUBLIC", ClosedWrong(2)), "reload preserves replay protection")
    db.leagues.Guild.PUBLIC.players["Player-1-A"].score = 900
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -0.9, "saved input is copied")
    local renamed = ClosedWrong(7, "Renamed-Realm")
    Check(store:RecordRound("Guild", "PUBLIC", renamed), "GUID maintains identity after name change")
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -1.8, "same GUID aggregates signed scores")
    Same(store:GetStandings("Guild", "PUBLIC")[1].incorrect, 2, "negative-point wrong answers count in statistics")
    Same(store:GetStandings("Guild", "PUBLIC")[1].name, "Renamed-Realm", "display name updates")
    Same(#store:GetStandings("Guild", "PUBLIC"), 1, "rename does not duplicate player")

    local preserved = store.db
    local future = { schemaVersion = 7, important = { value = "keep" } }
    local futureDb, futureError = store:Initialize(future)
    Same(futureDb, nil, "future database rejected")
    Same(futureError, "unsupported_database_version", "future rejection is explicit")
    Same(future.important.value, "keep", "future database not overwritten")
    Same(store.db, preserved, "failed initialization leaves previous state untouched")
    Check(
        store:Initialize({ schemaVersion = 3, settings = { autoAdvance = "yes" } }) == nil,
        "corrupt retained progression setting rejects on load"
    )
    Check(
        store:Initialize({ schemaVersion = 3, settings = { hostName = "Host Realm" } }) == nil,
        "corrupt host target rejects on load"
    )
    Same(store.db, preserved, "corrupt new settings preserve the existing database")
    Check(store:Initialize({ schemaVersion = 2, settings = { league = "" } }) == nil, "corrupt league rejected on load")
    Check(
        store:Initialize({ schemaVersion = 2, settings = { questionCount = 51 } }) == nil,
        "schema-two invalid retained finite-game settings reject"
    )
    Check(
        store:Initialize({ schemaVersion = 2, settings = { packId = false } }) == nil,
        "schema-two malformed pack selection rejects"
    )
    Check(store:Initialize({ schemaVersion = 2, settings = false }) == nil, "false settings do not silently default")
    Check(
        store:Initialize({ schemaVersion = 2, nextQuestionId = false }) == nil,
        "false counter does not silently reset"
    )
    Check(store:Initialize({ schemaVersion = 2, leagues = false }) == nil, "false standings do not silently reset")
    Check(store:Initialize("bad") == nil, "non-table database rejected")
    local invalidResult = ClosedWrong(8)
    invalidResult.answers[2] = invalidResult.answers[1]
    Check(not store:RecordRound("Guild", "PUBLIC", invalidResult), "duplicate player in result rejected atomically")
    Same(store:GetStandings("Guild", "PUBLIC")[1].score, -1.8, "bad result leaves totals untouched")

    db = store:Initialize(nil)
    for id = 1, 60 do
        Check(store:RecordRound("History", "PUBLIC", ClosedWrong(id)), "history round accepted")
    end
    Same(#db.leagues.History.PUBLIC.history, 50, "recent history is bounded")
    Same(db.leagues.History.PUBLIC.history[1].id, 11, "oldest history entries evicted")
    Check(not store:RecordRound("History", "PUBLIC", ClosedWrong(1)), "evicted result still cannot be replayed")
    Same(store:GetStandings("History", "PUBLIC")[1].score, -54, "history eviction preserves signed aggregate totals")
    db.nextQuestionId = 1
    Check(store:Initialize(db) ~= nil, "load saved boards")
    Same(store:NextQuestionId(), 61, "board high-watermark prevents counter reuse")
    Check(not store:RecordRound("History", "PUBLIC", ClosedWrong(1)), "durable dedup survives bounded history reload")
    Same(store:GetStandings("History", "PUBLIC")[1].answers, 60, "answer counts survive reload")

    local preciseDb = store:Initialize(nil)
    for id = 1, 1000 do
        Check(store:RecordRound("Precise", "PUBLIC", ClosedCorrect(id, 14)), "one-and-a-tenth answer persists")
        Same(store:GetStandings("Precise", "PUBLIC")[1].score, id * 11 / 10, "saved totals accumulate exact tenths")
    end
    Same(preciseDb.leagues.Precise.PUBLIC.history[50].answers[1].points, 1.1, "history keeps decimal answer points")
    Check(store:Initialize(preciseDb) ~= nil, "decimal score boards validate on reload")
    Same(store:GetStandings("Precise", "PUBLIC")[1].score, 1100, "many decimal awards survive reload without drift")
    Same(store:GetStandings("Precise", "PUBLIC")[1].correct, 1000, "correct count is not confused with scaled points")
    local fractional = ClosedCorrect(1001, 10.25)
    Check(store:RecordRound("Precise", "PUBLIC", fractional), "fractional final-answer timing persists")
    Same(store:GetStandings("Precise", "PUBLIC")[1].score, 1101.4, "fractional timestamp uses whole remaining seconds")
    Same(store.db.leagues.Precise.PUBLIC.history[50].answers[1].elapsed, 10.25, "history keeps precise accepted time")
    local precisePreserved = store.db
    for _, points in ipairs({ -50, -1, 0, 1, 1.91, 2, 100, 110, 120, math.huge, 0 / 0, "1.9", false }) do
        local bad = ClosedCorrect(1002, 10.25)
        bad.answers[1].points = points
        Check(not store:RecordRound("Precise", "PUBLIC", bad), "incorrect computed points cannot enter current history")
    end
    local withoutTiming = ClosedCorrect(1002, 10.25)
    withoutTiming.duration = nil
    Check(
        not store:RecordRound("Precise", "PUBLIC", withoutTiming),
        "new scoring history requires its original duration"
    )
    local stalePenalty = ClosedWrong(1002)
    stalePenalty.answers[1].points = -50
    Check(not store:RecordRound("Precise", "PUBLIC", stalePenalty), "old wrong-answer penalty is not valid new scoring")
    Same(store:GetStandings("Precise", "PUBLIC")[1].score, 1101.4, "invalid decimal results cannot mutate totals")
    Same(store.db, precisePreserved, "invalid records preserve the complete current database")
    local singleDecimal = ClosedCorrect(1002, 13)
    Check(
        store:RecordRound("Precise", "PUBLIC", singleDecimal),
        "correct result remains writable after rejected points"
    )
    Same(store:GetStandings("Precise", "PUBLIC")[1].score, 1102.6, "several decimal parts accumulate exactly")

    local corruptScores = { -1, -50, 0.01, 1.11, math.huge, 0 / 0, "1.1", false }
    for _, score in ipairs(corruptScores) do
        local invalidDb = {
            schemaVersion = 4,
            leagues = {
                Invalid = {
                    PUBLIC = {
                        players = {
                            Bad = { name = "Bad-Realm", score = score, correct = 1, incorrect = 0, answers = 1 },
                        },
                    },
                },
            },
        }
        Check(
            store:Initialize(invalidDb) == nil,
            "schema-four saved board rejects nonfinite, negative, or non-tenth totals"
        )
        Same(store.db, precisePreserved, "bad persisted score never replaces valid scores")
    end
    for _, position in ipairs({
        false,
        "middle",
        {},
        { x = 0.5 },
        { y = 0.5 },
        { x = -0.1, y = 0.5 },
        { x = 0.5, y = math.huge },
    }) do
        local invalidDb = { schemaVersion = 4, widgetPosition = position }
        local loaded, reason = store:Initialize(invalidDb)
        Same(loaded, nil, "invalid persisted position rejects")
        Same(reason, "invalid_widget_position", "invalid persisted position is explicit")
        Same(store.db, precisePreserved, "invalid position cannot discard score data")
    end

    local function LegacyBoard(id, correct)
        local entry = ClosedWrong(id)
        entry.duration, entry.scoringVersion = 20, nil
        entry.answers[1].points = -50
        if correct then
            entry.correctCount = 1
            entry.answers[1].choiceIndex = 1
            entry.answers[1].correct = true
            entry.answers[1].points = 120
        end
        return {
            lastRoundId = id,
            players = {
                ["Player-1-A"] = {
                    name = "Alice-Realm",
                    score = correct and 120 or -50,
                    correct = correct and 1 or 0,
                    incorrect = correct and 0 or 1,
                    answers = 1,
                },
            },
            history = { entry },
        }
    end
    local legacy = {
        schemaVersion = 1,
        settings = {
            league = "Legacy",
            channel = "GUILD",
            customChannel = "",
            channelPassword = "keep-password",
            answerMode = "WHISPER",
            packId = "test",
            questionCount = 17,
            duration = 35,
            autoAdvance = true,
        },
        nextQuestionId = 40,
        leagues = {
            Legacy = { PUBLIC = LegacyBoard(20, false), WHISPER = LegacyBoard(25, true) },
            Other = { PUBLIC = LegacyBoard(30, false) },
        },
    }
    local migrated, migrationError = store:Initialize(legacy)
    Check(migrated ~= nil, migrationError)
    Same(migrated.schemaVersion, 6, "legacy database archives old scoring alongside personal pack totals")
    Same(migrated.nextQuestionId, 40, "migration preserves a counter ahead of scored rounds")
    NoChatSettings(migrated.settings, "legacy migration discards visible-chat settings and password")
    Same(migrated.settings.league, "Legacy", "migration preserves selected league")
    Same(migrated.settings.packId, "test", "migration preserves selected pack")
    Same(migrated.settings.questionCount, 17, "migration preserves game length")
    Same(migrated.settings.duration, 15, "migration normalizes future rounds to the fixed answer duration")
    Same(migrated.settings.autoAdvance, true, "migration preserves progression setting")
    Same(migrated.settings.hostName, "", "old setup receives an empty join target")
    Same(migrated.widgetPosition.x, 0.5, "migration installs horizontal default position")
    Same(migrated.widgetPosition.y, 0.65, "migration installs vertical default position")
    Same(store:GetLegacyStandings("Legacy", "PUBLIC")[1].score, -50, "migration archives negative public totals")
    Same(store:GetLegacyStandings("Legacy", "WHISPER")[1].score, 120, "migration archives positive whisper totals")
    Same(store:GetLegacyStandings("Other", "PUBLIC")[1].score, -50, "migration archives other leagues")
    Same(next(migrated.leagues), nil, "old-scoring migration starts with empty new-scale boards")
    Same(#store:GetStandings("Legacy", "PUBLIC"), 0, "new standings never expose old-scale public points")
    Same(#store:GetStandings("Legacy", "WHISPER"), 0, "new standings never expose old-scale whisper points")
    Same(migrated.legacyLeagues.Legacy.PUBLIC.lastRoundId, 20, "migration preserves public dedup watermark")
    Same(migrated.legacyLeagues.Legacy.WHISPER.lastRoundId, 25, "migration preserves archived dedup watermark")
    Same(migrated.legacyLeagues.Legacy.WHISPER.history[1].answers[1].points, 120, "archived answer history survives")
    Same(migrated.legacyLeagues.Legacy.PUBLIC.history[1].id, 20, "public answer history survives")
    Same(legacy.schemaVersion, 1, "migration leaves input schema untouched")
    Same(legacy.settings.channel, "GUILD", "migration leaves input settings untouched")
    Same(legacy.settings.answerMode, "WHISPER", "migration leaves original answer mode untouched")
    Same(legacy.settings.customChannel, "", "migration leaves original blank name untouched")
    Same(legacy.settings.channelPassword, "keep-password", "normalization does not modify the input password in place")
    Check(not store:RecordRound("Legacy", "WHISPER", ClosedWrong(40)), "archived whisper board is read-only")
    Same(migrated.nextQuestionId, 40, "rejected archive write does not advance counter")
    Same(#migrated.legacyLeagues.Legacy.WHISPER.history, 1, "rejected archive write does not append history")
    Check(not store:RecordRound("Legacy", "PUBLIC", ClosedWrong(20)), "migration retains public replay protection")
    Check(store:RecordRound("Legacy", "PUBLIC", ClosedWrong(40)), "public scoring continues after migration")
    Same(store:GetStandings("Legacy", "PUBLIC")[1].score, -0.9, "new points start a separate signed scoring board")
    Same(store:GetLegacyStandings("Legacy", "PUBLIC")[1].score, -50, "new points never change legacy public totals")
    Same(store:GetLegacyStandings("Legacy", "WHISPER")[1].score, 120, "new public points never mix with archive")
    legacy.leagues.Legacy.WHISPER.players["Player-1-A"].score = 900
    Same(store:GetLegacyStandings("Legacy", "WHISPER")[1].score, 120, "archived players are copied during migration")
    local secondLoad = store:Initialize(migrated)
    Check(secondLoad ~= nil, "migrated database reloads normally")
    Same(store:GetLegacyStandings("Legacy", "WHISPER")[1].score, 120, "schema-five reload retains archived boards")
    Same(store:GetStandings("Legacy", "PUBLIC")[1].score, -0.9, "schema-five reload retains new public totals")
    Same(secondLoad.nextQuestionId, 41, "schema-five reload retains advanced counter")
    Same(#secondLoad.leagues.Legacy.PUBLIC.history, 1, "schema-five reload keeps only new history on the new board")
    Same(#secondLoad.legacyLeagues.Legacy.PUBLIC.history, 1, "schema-five reload keeps old history separate")

    local retiredVariants = { OldChatSettings() }
    for _, value in ipairs({ true, false, "UNKNOWN", "bad\n|channel", string.rep("x", 129), 42, math.huge, {} }) do
        local fields = {}
        for _, key in ipairs(REMOVED_CHAT_SETTINGS) do
            fields[key] = value
        end
        retiredVariants[#retiredVariants + 1] = fields
    end
    for version = 1, 6 do
        for _, retiredFields in ipairs(retiredVariants) do
            local oldSettings = Settings(17)
            oldSettings.league, oldSettings.packId = "Retained", "test"
            oldSettings.duration, oldSettings.autoAdvance, oldSettings.hostName = 60, true, "SavedHost-TestRealm"
            for key, value in pairs(retiredFields) do
                oldSettings[key] = value
            end
            local archives = { Retained = { PUBLIC = LegacyBoard(20, false), WHISPER = LegacyBoard(25, true) } }
            local currentBoards = {
                Retained = {
                    PUBLIC = {
                        lastRoundId = 30,
                        players = {
                            ["Player-1-A"] = {
                                name = "Alice-Realm",
                                score = 2.5,
                                correct = 1,
                                incorrect = 0,
                                answers = 1,
                            },
                        },
                        history = { PreviousRound(30, true, 5, 20, true) },
                    },
                },
            }
            local old = {
                schemaVersion = version,
                settings = oldSettings,
                nextQuestionId = 40,
                widgetPosition = { x = 0.23, y = 0.74 },
                leagues = version >= 4 and currentBoards or archives,
                legacyLeagues = version >= 4 and archives or nil,
            }
            local converted, reason = store:Initialize(old)
            Check(converted ~= nil, reason)
            Same(converted.schemaVersion, 6, "every supported input reaches the versioned signed-score schema")
            NoChatSettings(converted.settings, "every recognized schema drops retired visible-chat fields")
            NoChatSettings(store:GetSettings(), "every recognized schema exposes only retained settings")
            Same(converted.settings.league, "Retained", "chat removal preserves selected league")
            Same(converted.settings.packId, "test", "chat removal preserves selected question pack")
            Same(converted.settings.duration, 15, "old bridge never revives the variable answer window")
            Same(converted.settings.questionCount, 17, "chat removal leaves unrelated finite-game data intact")
            Same(converted.settings.autoAdvance, true, "chat removal leaves unrelated progression data intact")
            Same(converted.settings.hostName, "SavedHost-TestRealm", "chat removal leaves old join preference intact")
            Same(converted.nextQuestionId, 40, "chat removal does not reset the question allocator")
            SameTable(converted.widgetPosition, old.widgetPosition, "chat removal preserves widget position")
            SameTable(converted.legacyLeagues, archives, "chat removal preserves all public and whisper archive data")
            SameTable(converted.leagues, version >= 4 and currentBoards or {}, "chat removal preserves current boards")
            for key, value in pairs(retiredFields) do
                Same(oldSettings[key], value, "normalization does not mutate retired input values")
            end
            Same(old.schemaVersion, version, "normalization never rewrites the supplied database in place")
            Check(store:SaveSettings(oldSettings), "old configured settings can be saved without obsolete validation")
            NoChatSettings(converted.settings, "old active bridge and password cannot return during saving")
            local normalizedAgain = store:Initialize(converted)
            Check(normalizedAgain ~= nil, "cleaned settings reload normally")
            SameTable(normalizedAgain.settings, converted.settings, "chat removal is idempotent across reloads")
            NoChatSettings(normalizedAgain.settings, "reloading does not regenerate deleted chat defaults")
            SameTable(normalizedAgain.legacyLeagues, archives, "reload keeps complete old public and whisper archives")
            SameTable(
                normalizedAgain.leagues,
                version >= 4 and currentBoards or {},
                "reload keeps current scores intact"
            )
            SameTable(normalizedAgain.widgetPosition, old.widgetPosition, "reload keeps the saved widget position")
        end
        Check(store:Initialize({ schemaVersion = version }) ~= nil, "missing settings normalize for every old schema")
        NoChatSettings(store:GetSettings(), "missing settings never recreate retired defaults")
        Check(store:Initialize({ schemaVersion = version, settings = false }) == nil, "non-table settings still reject")
    end
    preserved = store.db
    Check(store:Initialize(future) == nil, "future schemas still reject after migration")
    Same(store.db, preserved, "future rejection does not replace migrated data")
    Same(future.schemaVersion, 7, "future schema is never rewritten")

    local legacyTwo = {
        schemaVersion = 2,
        settings = {
            league = "Legacy",
            channel = "CHANNEL",
            customChannel = "KeepThisChannel",
            answerMode = "PUBLIC",
            duration = 45,
            questionCount = 11,
            autoAdvance = true,
        },
        nextQuestionId = 70,
        leagues = { Legacy = { PUBLIC = LegacyBoard(60, false), WHISPER = LegacyBoard(65, true) } },
    }
    local migratedTwo = store:Initialize(legacyTwo)
    Check(migratedTwo ~= nil, "schema-two database migrates")
    Same(migratedTwo.schemaVersion, 6, "schema-two migration reaches current schema")
    NoChatSettings(migratedTwo.settings, "schema-two migration removes obsolete visible-chat configuration")
    Same(migratedTwo.settings.hostName, "", "schema-two migration adds empty join target")
    Same(migratedTwo.settings.duration, 15, "schema-two migration normalizes future timing")
    Same(migratedTwo.settings.questionCount, 11, "schema-two migration retains legacy finite-game setting")
    Same(migratedTwo.settings.autoAdvance, true, "schema-two migration retains legacy progression setting")
    Same(migratedTwo.nextQuestionId, 70, "schema-two migration preserves global question counter")
    Same(
        store:GetLegacyStandings("Legacy", "PUBLIC")[1].score,
        -50,
        "schema-two migration preserves signed public totals"
    )
    Same(store:GetLegacyStandings("Legacy", "WHISPER")[1].score, 120, "schema-two migration preserves whisper archives")
    Same(migratedTwo.legacyLeagues.Legacy.PUBLIC.lastRoundId, 60, "schema-two migration preserves replay watermark")
    Same(migratedTwo.legacyLeagues.Legacy.WHISPER.history[1].id, 65, "schema-two migration preserves archived history")
    Same(legacyTwo.schemaVersion, 2, "schema-two migration leaves original input untouched")
    Same(legacyTwo.settings.bridgeChat, nil, "migration does not modify old settings in place")
    Check(
        store:SaveSettings({ bridgeChat = true, hostName = "Quizhost-Area52" }),
        "widget settings save while retired bridge fields are ignored"
    )
    local withWidgets = store:Initialize(migratedTwo)
    Check(withWidgets ~= nil, "widget-capable database reloads")
    NoChatSettings(withWidgets.settings, "retired bridge option cannot survive reload")
    Same(withWidgets.settings.hostName, "Quizhost-Area52", "join target survives reload")
    local highNumber = ClosedWrong(70)
    highNumber.number = 9007199254740991
    highNumber.cycle = 4
    Check(store:RecordRound("Legacy", "PUBLIC", highNumber), "history permits a safe-integer continuous round number")
    Same(withWidgets.leagues.Legacy.PUBLIC.history[1].cycle, 4, "new history retains continuous cycle")
    for _, number in ipairs({ 0, -1, 0.5, math.huge, 9007199254740992 }) do
        local invalidNumber = ClosedWrong(71)
        invalidNumber.number = number
        Check(not store:RecordRound("Legacy", "PUBLIC", invalidNumber), "unsafe history round number rejects")
    end
    local invalidCycle = ClosedWrong(71)
    invalidCycle.cycle = 0
    Check(not store:RecordRound("Legacy", "PUBLIC", invalidCycle), "invalid cycle rejects without scoring")
    Check(store:Initialize(withWidgets) ~= nil, "extended continuous history reloads")
    Same(store:GetStandings("Legacy", "PUBLIC")[1].score, -0.9, "invalid continuous records never change scores")
    preserved = store.db
    Check(store:Initialize(future) == nil, "future schema protection remains after widget migration")
    Same(store.db, preserved, "future input does not overwrite scores or widget settings")

    local oldWithoutDuration = LegacyBoard(95, true)
    oldWithoutDuration.history[1].duration = nil
    oldWithoutDuration.history[1].answers[1].elapsed = 250
    oldWithoutDuration.history[1].answers[1].points = 110
    oldWithoutDuration.players["Player-1-A"].score = 110
    local legacyThree = {
        schemaVersion = 3,
        settings = { bridgeChat = true, hostName = "SavedHost-TestRealm", duration = 30 },
        nextQuestionId = 1,
        leagues = {
            Before = { PUBLIC = LegacyBoard(81, false), WHISPER = oldWithoutDuration },
        },
    }
    legacyThree.leagues.Before.PUBLIC.history[1].cycle = 7
    local migratedThree = store:Initialize(legacyThree)
    Check(migratedThree ~= nil, "schema-three widget installation migrates directly to new scoring")
    Same(migratedThree.schemaVersion, 6, "widget migration reaches current schema")
    Same(migratedThree.nextQuestionId, 96, "archived high-watermark repairs an outdated question counter")
    NoChatSettings(migratedThree.settings, "migration discards an enabled user bridge preference")
    Same(
        migratedThree.settings.hostName,
        "SavedHost-TestRealm",
        "migration preserves historical explicit-join preference"
    )
    Same(migratedThree.settings.duration, 15, "migration normalizes future timing without rescoring history")
    Same(migratedThree.legacyLeagues.Before.PUBLIC.history[1].cycle, 7, "old continuous cycle IDs survive unchanged")
    Same(migratedThree.legacyLeagues.Before.WHISPER.history[1].duration, nil, "missing legacy duration is not invented")
    Same(
        migratedThree.legacyLeagues.Before.WHISPER.history[1].answers[1].elapsed,
        250,
        "timing-less legacy elapsed stays intact"
    )
    Same(
        migratedThree.legacyLeagues.Before.WHISPER.history[1].answers[1].points,
        110,
        "legacy history is not recalculated"
    )
    Same(store:GetLegacyStandings("Before", "WHISPER")[1].score, 110, "historical totals survive missing timing data")
    Same(store:GetLegacyStandings("Before", "PUBLIC")[1].score, -50, "negative legacy total is preserved, not floored")
    Same(#store:GetStandings("Before", "PUBLIC"), 0, "schema-three migration also starts new scores from empty")
    local archiveView = store:GetLegacyStandings("Before", "PUBLIC")
    archiveView[1].score = 5
    Same(store:GetLegacyStandings("Before", "PUBLIC")[1].score, -50, "archive accessor returns copies")
    Check(
        store:RecordRound("Before", "PUBLIC", ClosedCorrect(96, 5)),
        "new-scale points record beside old archived league"
    )
    Same(store:GetStandings("Before", "PUBLIC")[1].score, 2, "first new correct answer starts at its own small scale")
    Same(
        store:GetLegacyStandings("Before", "PUBLIC")[1].score,
        -50,
        "new-scale correct points cannot change archived penalties"
    )
    Check(store:SaveWidgetPosition(0.33, 0.67), "new position writes alongside migrated scores")
    Check(store:Initialize(migratedThree) ~= nil, "mixed old archives and new scores reload atomically")
    Same(store:GetStandings("Before", "PUBLIC")[1].score, 2, "new decimal totals survive migration reload")
    Same(store:GetLegacyStandings("Before", "PUBLIC")[1].score, -50, "old integer totals survive migration reload")
    Same(store:GetWidgetPosition().x, 0.33, "migrated database retains moved widget center")
    Same(legacyThree.nextQuestionId, 1, "migration does not repair the original input in place")
    Same(legacyThree.schemaVersion, 3, "migration does not rewrite original schema in place")
    local retainedArchive = store.db
    for _, points in ipairs({ 1, 2.9, 0, -50 }) do
        local invalidLegacy = { schemaVersion = 3, leagues = { Invalid = { PUBLIC = LegacyBoard(5, true) } } }
        invalidLegacy.leagues.Invalid.PUBLIC.history[1].answers[1].points = points
        Check(store:Initialize(invalidLegacy) == nil, "legacy correct answers validate using old point scale only")
        Same(store.db, retainedArchive, "invalid old history cannot replace current data")
    end
    local wrongOldBand = { schemaVersion = 3, leagues = { Invalid = { PUBLIC = LegacyBoard(5, true) } } }
    wrongOldBand.leagues.Invalid.PUBLIC.history[1].answers[1].points = 100
    Check(store:Initialize(wrongOldBand) == nil, "legacy known-duration history validates the original timing bands")
    Same(store.db, retainedArchive, "bad old timing leaves the current database untouched")
    local longArchive = LegacyBoard(60, false)
    longArchive.players["Player-1-A"].score = -3000
    longArchive.players["Player-1-A"].incorrect = 60
    longArchive.players["Player-1-A"].answers = 60
    longArchive.history = {}
    for id = 1, 60 do
        longArchive.history[id] = LegacyBoard(id, false).history[1]
    end
    local fullArchive = store:Initialize({ schemaVersion = 3, leagues = { All = { PUBLIC = longArchive } } })
    Check(fullArchive ~= nil, "legacy archive with more than the live history window is valid")
    Same(#fullArchive.legacyLeagues.All.PUBLIC.history, 60, "archiving never prunes supplied legacy history")
    Same(fullArchive.legacyLeagues.All.PUBLIC.history[1].id, 1, "oldest supplied legacy ID stays archived")
    Same(fullArchive.legacyLeagues.All.PUBLIC.history[60].id, 60, "latest supplied legacy ID stays archived")
    Same(store:GetLegacyStandings("All", "PUBLIC")[1].score, -3000, "full negative legacy aggregate is unchanged")
    Same(store:NextQuestionId(), 61, "legacy high-watermark reserves every historical question ID")
    Check(store:Initialize(fullArchive) ~= nil, "full archive survives subsequent schema-five validation")
    Same(#store.db.legacyLeagues.All.PUBLIC.history, 60, "reload does not trim legacy history either")

    local oldTwenty = PreviousRound(1, true, 5, 20)
    local oldSixty = PreviousRound(2, true, 5, 60)
    local oldWrong = PreviousRound(3, false, 0, 10)
    local savedVariableClock = {
        schemaVersion = 4,
        settings = { duration = 60 },
        leagues = {
            Existing = {
                PUBLIC = {
                    lastRoundId = 3,
                    players = {
                        ["Player-1-A"] = { name = "Alice-Realm", score = 9, correct = 2, incorrect = 1, answers = 3 },
                    },
                    history = { oldTwenty, oldSixty, oldWrong },
                },
            },
        },
    }
    local fixedClockDb = store:Initialize(savedVariableClock)
    Check(fixedClockDb ~= nil, "existing decimal scores with longer historical windows remain valid")
    Same(fixedClockDb.settings.duration, 15, "loading schema four normalizes only future answer timing")
    Same(savedVariableClock.settings.duration, 60, "normalization does not modify supplied SavedVariables in place")
    Same(fixedClockDb.schemaVersion, 6, "old decimal history migrates to versioned scoring without recalculation")
    Same(store:GetStandings("Existing", "PUBLIC")[1].score, 9, "existing decimal totals are not rescaled")
    local existingHistory = fixedClockDb.leagues.Existing.PUBLIC.history
    Same(existingHistory[1].duration, 20, "twenty-second historical windows remain intact")
    Same(existingHistory[1].answers[1].points, 2.5, "twenty-second historical points remain intact")
    Same(existingHistory[2].duration, 60, "sixty-second historical windows remain intact")
    Same(existingHistory[2].answers[1].points, 6.5, "sixty-second historical points remain intact")
    Same(existingHistory[3].duration, 10, "the previous fixed ten-second window remains intact")
    Same(existingHistory[3].answers[1].points, 0, "old incorrect answers remain zero instead of acquiring a penalty")
    for index = 1, 3 do
        Same(existingHistory[index].scoringVersion, 1, "old decimal history is tagged with its original rules")
        Same(
            savedVariableClock.leagues.Existing.PUBLIC.history[index].scoringVersion,
            nil,
            "version tags copy without mutating old input"
        )
    end
    fixedClockDb.settings.duration = 60
    Same(store:GetSettings().duration, 15, "configuration readers cannot revive a mutated deprecated duration")
    Check(store:SaveSettings({ duration = 20 }), "saving an old settings object remains compatible")
    Same(fixedClockDb.settings.duration, 15, "settings save restores the internal fixed value")
    local continuedGame = Quiz.Game.New(store:GetSettings(), Questions(1), KeepOrder)
    local continuedRound = Open(continuedGame, store:NextQuestionId(), 0)
    Check(
        continuedGame:Submit("Player-1-A", "Alice-Realm", continuedRound.id, continuedRound.correctIndex, 0),
        "existing scorer can play a new fixed-window round"
    )
    local continuedResult = continuedGame:CloseQuestion(15)
    Same(continuedResult.scoringVersion, 2, "new results identify the signed-penalty scoring version")
    Same(
        continuedResult.answers[1].points,
        2.5,
        "new fixed rounds have a two-and-a-half-point maximum beside old history"
    )
    Check(
        store:RecordRound("Existing", "PUBLIC", continuedResult),
        "new fixed round appends without touching old scores"
    )
    Same(store:GetStandings("Existing", "PUBLIC")[1].score, 11.5, "new points accumulate on existing totals unchanged")
    local continuedWrong = ClosedWrong(store:NextQuestionId())
    Check(
        store:RecordRound("Existing", "PUBLIC", continuedWrong),
        "new penalties append beside historical zero-point mistakes"
    )
    Same(store:GetStandings("Existing", "PUBLIC")[1].score, 10.6, "only the new incorrect answer deducts points")
    Check(store:Initialize(fixedClockDb) ~= nil, "mixed historical and fixed windows survive reload")
    Same(store.db.leagues.Existing.PUBLIC.history[2].duration, 60, "later reload still preserves historical duration")
    Same(
        store.db.leagues.Existing.PUBLIC.history[3].answers[1].points,
        0,
        "later reload never retroactively penalizes old mistakes"
    )
    Same(store.db.leagues.Existing.PUBLIC.history[4].duration, 15, "later reload preserves new fixed duration")
    Same(
        store.db.leagues.Existing.PUBLIC.history[4].scoringVersion,
        2,
        "later reload preserves new correct scoring version"
    )
    Same(
        store.db.leagues.Existing.PUBLIC.history[5].scoringVersion,
        2,
        "later reload preserves new penalty scoring version"
    )
    Same(store.db.leagues.Existing.PUBLIC.history[5].answers[1].points, -0.9, "later reload preserves the new penalty")
    Same(store:GetStandings("Existing", "PUBLIC")[1].score, 10.6, "mixed-version aggregate survives reload unchanged")
    Check(
        not store:RecordRound("Existing", "PUBLIC", continuedWrong),
        "new penalties retain exactly-once persistence after migration"
    )

    local mixedPreserved = store.db
    for _, version in ipairs({ 0, 1, 3, 4, -1, 1.5, "2", false, {}, math.huge, 0 / 0 }) do
        local bad = ClosedWrong(store.db.nextQuestionId)
        bad.scoringVersion = version
        Check(not store:RecordRound("Existing", "PUBLIC", bad), "new records require exactly scoring version two")
        Same(store.db, mixedPreserved, "unknown new scoring versions cannot replace the current database")
        Same(store:GetStandings("Existing", "PUBLIC")[1].score, 10.6, "rejected scoring versions cannot deduct points")
    end
    local unversioned = ClosedWrong(store.db.nextQuestionId)
    unversioned.scoringVersion = nil
    Check(not store:RecordRound("Existing", "PUBLIC", unversioned), "new records cannot omit their scoring version")
    for _, duration in ipairs({ 10, 20, 60, 0, 15.5, "15", false }) do
        local bad = ClosedWrong(store.db.nextQuestionId)
        bad.duration = duration
        Check(not store:RecordRound("Existing", "PUBLIC", bad), "new result duration must be the fixed fifteen seconds")
    end
    for _, points in ipairs({ 0, -50, -1.1, -0.4, -0.91, math.huge, -math.huge, 0 / 0, "-0.9", false }) do
        local bad = ClosedWrong(store.db.nextQuestionId)
        bad.answers[1].points = points
        Check(
            not store:RecordRound("Existing", "PUBLIC", bad),
            "new incorrect points must match their versioned timing rule"
        )
    end
    for _, version in ipairs({ 0, 3, -1, 1.5, "1", false, {}, math.huge, 0 / 0 }) do
        local badHistory = PreviousRound(1, false, 0, 10, true)
        badHistory.scoringVersion = version
        local bad =
            { schemaVersion = 5, leagues = { Invalid = { PUBLIC = { lastRoundId = 1, history = { badHistory } } } } }
        Check(store:Initialize(bad) == nil, "unknown historical scoring versions are rejected atomically")
        Same(store.db, mixedPreserved, "unknown historical versions leave all existing data untouched")
    end
    local untaggedHistory = {
        schemaVersion = 5,
        leagues = {
            Invalid = {
                PUBLIC = {
                    lastRoundId = 1,
                    history = { PreviousRound(1, false, 0, 10) },
                },
            },
        },
    }
    Check(store:Initialize(untaggedHistory) == nil, "current-schema history must retain explicit scoring tags")
    local newInOld = {
        schemaVersion = 4,
        leagues = {
            Invalid = {
                PUBLIC = {
                    lastRoundId = 1,
                    history = { ClosedWrong(1) },
                },
            },
        },
    }
    Check(store:Initialize(newInOld) == nil, "schema-four input cannot smuggle new negative scoring records")
    for _, duration in ipairs({ 10, 20, 60 }) do
        local badHistory = ClosedWrong(1)
        badHistory.duration = duration
        local bad =
            { schemaVersion = 5, leagues = { Invalid = { PUBLIC = { lastRoundId = 1, history = { badHistory } } } } }
        Check(store:Initialize(bad) == nil, "version-two stored history requires the original fifteen-second window")
        Same(store.db, mixedPreserved, "invalid version-two duration cannot replace valid mixed history")
    end
    local historicalWrong = PreviousRound(1, false, 0, 10)
    historicalWrong.answers[1].points = -1
    local penalizedOld = {
        schemaVersion = 4,
        leagues = {
            Invalid = {
                PUBLIC = {
                    lastRoundId = 1,
                    history = { historicalWrong },
                },
            },
        },
    }
    Check(store:Initialize(penalizedOld) == nil, "old zero-penalty histories cannot accept new negative answers")
    local incorrectlyTimedOld = PreviousRound(1, true, 5, 20)
    incorrectlyTimedOld.answers[1].points = 2.4
    local badOldTiming = {
        schemaVersion = 4,
        leagues = {
            Invalid = {
                PUBLIC = {
                    lastRoundId = 1,
                    history = { incorrectlyTimedOld },
                },
            },
        },
    }
    Check(
        store:Initialize(badOldTiming) == nil,
        "historical correct points still validate against their original timing"
    )
    Same(store.db, mixedPreserved, "invalid migration inputs preserve the mixed-version database")
    local liveCalculator = Quiz.Scoring.Calculate
    Quiz.Scoring.Calculate = function()
        error("historical migration must not call the live scorer")
    end
    local frozenHistory = store:Initialize(savedVariableClock)
    Quiz.Scoring.Calculate = liveCalculator
    Check(frozenHistory ~= nil, "historical records validate independently of the current scoring implementation")
    Same(store:GetStandings("Existing", "PUBLIC")[1].score, 9, "frozen old-rule validation preserves supplied totals")

    local negativeDb = store:Initialize(nil)
    for id = 1, 1000 do
        Check(store:RecordRound("Negative precision", "PUBLIC", ClosedWrong(id)), "repeated timed penalties persist")
        Same(
            store:GetStandings("Negative precision", "PUBLIC")[1].score,
            -id * 9 / 10,
            "negative tenth totals do not drift"
        )
    end
    Check(store:Initialize(negativeDb) ~= nil, "large negative totals validate on reload")
    Same(
        store:GetStandings("Negative precision", "PUBLIC")[1].score,
        -900,
        "all penalties survive bounded-history reload"
    )
    Same(store:GetStandings("Negative precision", "PUBLIC")[1].incorrect, 1000, "penalties count one mistake per round")
    Check(store:RecordRound("Recovery", "PUBLIC", ClosedWrong(1001)), "another league may begin below zero")
    Check(
        store:RecordRound("Recovery", "PUBLIC", ClosedCorrect(1002, 0)),
        "a correct answer can recover a negative total"
    )
    Same(store:GetStandings("Recovery", "PUBLIC")[1].score, 1.6, "signed accumulation crosses zero without truncation")

    local skipGame = NewGame(2)
    Open(skipGame, store:NextQuestionId(), 0)
    Check(
        skipGame:Submit("Skip", "Skip-Realm", skipGame.round.id, 2, 0, "wrong.1"),
        "skip fixture first earns a penalty"
    )
    local skippedPenalty = skipGame:CloseQuestion(15)
    Check(store:RecordRound("Skip", "PUBLIC", skippedPenalty), "skip fixture penalty persists")
    Open(skipGame, store:NextQuestionId(), 18)
    local skippedRound = skipGame:CloseQuestion(33)
    Same(skippedRound.totalAnswers, 0, "an unanswered question records no choice")
    Same(skipGame:GetStandings()[1].score, -1, "skipping does not add another penalty in memory")
    Check(store:RecordRound("Skip", "PUBLIC", skippedRound), "an unanswered round can finalize for progression")
    Same(store:GetStandings("Skip", "PUBLIC")[1].score, -1, "skipping does not add another persistent penalty")
    Same(store:GetStandings("Skip", "PUBLIC")[1].answers, 1, "skipping cannot inflate participation counts")
    local skipDb = store.db
    Check(store:Initialize(skipDb) ~= nil, "signed totals alongside unanswered history reload")
    Same(
        store:GetStandings("Skip", "PUBLIC")[1].score,
        -1,
        "reloading never retroactively penalizes a skipped question"
    )
    local signedPreserved = store.db
    local scoreLimit = math.floor(9007199254740991 / 10)
    for _, score in ipairs({
        -0.01,
        -1.11,
        0.01,
        1.11,
        scoreLimit + 1,
        -scoreLimit - 1,
        math.huge,
        -math.huge,
        0 / 0,
        "-1",
        false,
    }) do
        local bad = {
            schemaVersion = 5,
            leagues = {
                Invalid = {
                    PUBLIC = {
                        players = {
                            Bad = { name = "Bad-Realm", score = score, correct = 0, incorrect = 1, answers = 1 },
                        },
                    },
                },
            },
        }
        Check(store:Initialize(bad) == nil, "signed scores still reject unsafe, nonfinite, and non-tenth totals")
        Same(store.db, signedPreserved, "invalid signed totals leave valid history untouched")
    end
    for _, score in ipairs({ scoreLimit, -scoreLimit }) do
        local limits = {
            schemaVersion = 5,
            leagues = {
                Limits = {
                    PUBLIC = {
                        players = {
                            ["Player-1-A"] = {
                                name = "Alice-Realm",
                                score = score,
                                correct = 0,
                                incorrect = 0,
                                answers = 0,
                            },
                        },
                    },
                },
            },
        }
        local boundedDb = store:Initialize(limits)
        Check(boundedDb ~= nil, "both signed safe-score limits remain loadable")
        local overflow = score > 0 and ClosedCorrect(1, 0) or ClosedWrong(1)
        Check(
            not store:RecordRound("Limits", "PUBLIC", overflow),
            "positive overflow and negative underflow reject before mutation"
        )
        Same(store:GetStandings("Limits", "PUBLIC")[1].score, score, "overflow cannot corrupt a bounded score")
        Same(boundedDb.leagues.Limits.PUBLIC.lastRoundId, 0, "overflow cannot consume a result watermark")
        Same(#boundedDb.leagues.Limits.PUBLIC.history, 0, "overflow cannot append a partially committed result")
    end

    local utf8Name = "選手-選服"
    local utf8League = "精選題庫"
    local utf8Password = "精選密碼"
    local utf8Identity = "name:" .. utf8Name
    Same(string.byte("選", 2), 129, "UTF-8 fixture contains the continuation byte misclassified by Windows ctype")
    local utf8Settings = Settings(1)
    utf8Settings.league = utf8League
    utf8Settings.hostName = utf8Name
    utf8Settings.channelPassword = utf8Password
    local utf8Questions = Questions(1)
    utf8Questions[1].key = "test:選"
    utf8Questions[1].prompt = "請選正確答案"
    utf8Questions[1].choices = { "選一", "選二", "選三", "選四" }
    local utf8Game = Quiz.Game.New(utf8Settings, utf8Questions, KeepOrder)
    Check(utf8Game ~= nil, "UTF-8 question input is valid")
    local utf8Db = store:Initialize(nil)
    Check(store:SaveSettings(utf8Settings), "UTF-8 league and host name persist while the retired password is ignored")
    local utf8Id = store:NextQuestionId()
    local utf8Round = Open(utf8Game, utf8Id, 0)
    local forbiddenBytes = {}
    for byte = 0, 31 do
        forbiddenBytes[#forbiddenBytes + 1] = byte
    end
    forbiddenBytes[#forbiddenBytes + 1] = 127
    forbiddenBytes[#forbiddenBytes + 1] = string.byte("|")
    for _, byte in ipairs(forbiddenBytes) do
        local unsafe = string.char(byte)
        Check(
            not utf8Game:Submit("bad" .. unsafe, utf8Name, utf8Id, 2, 1),
            "ASCII controls and pipes remain forbidden in player keys"
        )
        Check(
            not utf8Game:Submit(utf8Identity, utf8Name .. unsafe, utf8Id, 2, 1),
            "ASCII controls and pipes remain forbidden in player names"
        )
        Check(
            not store:SaveSettings({ league = utf8League .. unsafe }),
            "ASCII controls and pipes remain forbidden in league names"
        )
        Check(
            store:SaveSettings({ channelPassword = utf8Password .. unsafe }),
            "retired passwords no longer participate in settings validation"
        )
        Same(store:GetSettings().channelPassword, nil, "retired UTF-8 passwords are never exposed or saved")
        Check(
            not store:SaveSettings({ hostName = utf8Name .. unsafe }),
            "ASCII controls and pipes remain forbidden in host targets"
        )
        Check(
            not store:RecordRound(utf8League .. unsafe, "PUBLIC", ClosedWrong(utf8Id)),
            "unsafe league cannot accept a saved round"
        )
        for _, field in ipairs({ "guid", "name" }) do
            local invalidIdentity = ClosedWrong(utf8Id)
            invalidIdentity.answers[1][field] = utf8Name .. unsafe
            Check(
                not store:RecordRound(utf8League, "PUBLIC", invalidIdentity),
                "saved identity rejects ASCII controls and pipes"
            )
        end
        local invalidKey = ClosedWrong(utf8Id)
        invalidKey.questionKey = "test:選" .. unsafe
        Check(
            not store:RecordRound(utf8League, "PUBLIC", invalidKey),
            "saved question keys reject ASCII controls and pipes"
        )
    end
    Same(next(utf8Round.answers), nil, "invalid control-bearing answers never consume a lock")
    Same(store:GetSettings().league, utf8League, "invalid controls never replace valid UTF-8 league settings")
    Same(store:GetSettings().hostName, utf8Name, "invalid controls never replace valid UTF-8 host settings")
    Check(utf8Game:Submit(utf8Identity, utf8Name, utf8Id, 2, 1), "Chinese player name and name-based key can answer")
    local utf8Result = utf8Game:CloseQuestion(20)
    Check(utf8Result ~= nil, "UTF-8 answer closes normally")
    Same(utf8Result.answers[1].points, -0.9, "UTF-8 player receives the same signed incorrect scoring")
    Check(store:RecordRound(utf8League, "PUBLIC", utf8Result), "closed UTF-8 round saves")
    Same(store:GetStandings(utf8League, "PUBLIC")[1].name, utf8Name, "standings retain exact UTF-8 name bytes")
    Same(store:GetStandings(utf8League, "PUBLIC")[1].score, -0.9, "UTF-8 league retains a negative-point player")
    local utf8Reloaded = store:Initialize(utf8Db)
    Check(utf8Reloaded ~= nil and utf8Reloaded ~= utf8Db, "UTF-8 saved data reloads through validation and copying")
    Same(utf8Reloaded.settings.league, utf8League, "UTF-8 league survives reload")
    Same(utf8Reloaded.settings.hostName, utf8Name, "UTF-8 host target survives reload")
    Same(utf8Reloaded.settings.channelPassword, nil, "retired UTF-8 password is absent after reload")
    Same(store:GetStandings(utf8League, "PUBLIC")[1].guid, utf8Identity, "UTF-8 name-based identity survives reload")
    Same(store:GetStandings(utf8League, "PUBLIC")[1].name, utf8Name, "UTF-8 display name survives reload")
    Same(store:GetStandings(utf8League, "PUBLIC")[1].score, -0.9, "negative UTF-8 score survives reload")
    Same(
        utf8Reloaded.leagues[utf8League].PUBLIC.history[1].questionKey,
        "test:選",
        "UTF-8 question key survives history reload"
    )
    Same(
        utf8Reloaded.leagues[utf8League].PUBLIC.history[1].answers[1].name,
        utf8Name,
        "UTF-8 answer name survives history reload"
    )
    Same(
        utf8Reloaded.leagues[utf8League].PUBLIC.history[1].answers[1].points,
        -0.9,
        "negative UTF-8 answer points survive history reload"
    )
    Check(not store:RecordRound(utf8League, "PUBLIC", utf8Result), "UTF-8 reload retains exactly-once persistence")
    Same(store:GetStandings(utf8League, "PUBLIC")[1].score, -0.9, "duplicate UTF-8 round cannot change totals")

    for count = 4, 6 do
        for authoredCorrect = 1, count do
            for _, random in ipairs({
                KeepOrder,
                function()
                    return 1
                end,
            }) do
                local deck = Questions(1)
                local question = deck[1]
                question.choices = {}
                for index = 1, count do
                    question.choices[index] = "Answer " .. index
                end
                question.correctIndex = authoredCorrect
                question.difficulty, question.era = "very_hard", "Warcraft III"
                question.source = "https://warcraft.wiki.gg/wiki/Test_reference"
                local choiceGame = Quiz.Game.New(Settings(1), deck, random)
                Check(choiceGame ~= nil, "model accepts four through six choices")
                local active = Open(choiceGame, 1, 100)
                Same(#active.choices, count, "shuffling keeps exactly the authored choices")
                Same(active.choiceCount, count, "round retains its actual answer count")
                Same(
                    active.choices[active.correctIndex],
                    "Answer " .. authoredCorrect,
                    "shuffle maps every correct index"
                )
                Same(active.difficulty, "very_hard", "difficulty follows the shuffled question")
                Same(active.era, "Warcraft III", "era follows the shuffled question")
                Same(active.source, question.source, "host retains the editorial source without rewriting it")
                Check(not choiceGame:Submit("Choices", "Choices-Realm", 1, count + 1, 101), "extra choice is rejected")
                Same(next(active.answers), nil, "out-of-range answers have no scoring side effects")
                local wrong = active.correctIndex % count + 1
                Check(choiceGame:Submit("Choices", "Choices-Realm", 1, wrong, 101), "a valid wrong choice is accepted")
                Same(active.answers.Choices.points, -0.9, "every valid wrong choice receives its timed penalty")
                Check(
                    choiceGame:Submit("Choices", "Choices-Realm", 1, active.correctIndex, 103, "answer.2"),
                    "answer can change"
                )
                Same(active.answers.Choices.points, 2.2, "correct replacement uses its latest host arrival")
                Check(
                    choiceGame:Submit("Choices", "Choices-Realm", 1, active.correctIndex, 104, "answer.2"),
                    "same action retries"
                )
                Same(active.answers.Choices.elapsed, 3, "same-action retries preserve the chosen timestamp")
                local result = choiceGame:CloseQuestion(115)
                Same(result.choiceCount, count, "closed result records its choice count")
                Same(result.correctIndex, active.correctIndex, "result reveals the shuffled correct index")
                Same(result.source, question.source, "host result retains the question's source")
                local db = store:Initialize(nil)
                Check(store:RecordRound("Choices", "PUBLIC", result), "all choice counts enter persistent history")
                local loaded = store:Initialize(db)
                Check(loaded ~= nil, "four-to-six-choice history reloads safely")
                local entry = loaded.leagues.Choices.PUBLIC.history[1]
                Same(entry.choiceCount, count, "history preserves its explicit answer-count bound")
                Same(entry.answers[1].choiceIndex, active.correctIndex, "fifth and sixth choices survive reload")
                Same(entry.answers[1].points, 2.2, "extended-choice scoring survives reload")
                Same(entry.source, nil, "question source is not duplicated into SavedVariables")
                Same(store:GetStandings("Choices", "PUBLIC")[1].score, 2.2, "extended choices use normal league totals")
            end
        end
    end
    for _, count in ipairs({ 0, 3, 7 }) do
        local deck = Questions(1)
        deck[1].choices = {}
        for index = 1, count do
            deck[1].choices[index] = "Answer " .. index
        end
        Same(Quiz.Game.New(Settings(1), deck), nil, "model rejects choices outside four to six")
    end
    for _, count in ipairs({ 3, 7, 4.5, "6", false }) do
        local result = ClosedCorrect(1)
        result.choiceCount = count
        store:Initialize(nil)
        Check(not store:RecordRound("Choices", "PUBLIC", result), "persistent choice counts are strictly bounded")
    end
    local oldFour = ClosedWrong(1)
    oldFour.answers[1].choiceIndex = 5
    store:Initialize(nil)
    Check(not store:RecordRound("Choices", "PUBLIC", oldFour), "missing historical choiceCount still means four")
    oldFour.choiceCount = 5
    Check(store:RecordRound("Choices", "PUBLIC", oldFour), "explicit five-choice history accepts its fifth option")
    for version = 1, 6 do
        for _, retiredId in ipairs({ "warcraft_basics", "warcraft-basics" }) do
            local saved = { schemaVersion = version, settings = { packId = retiredId, league = "Pack upgrade" } }
            local upgraded = store:Initialize(saved)
            Check(upgraded ~= nil, "old built-in selection upgrades in every supported schema")
            Same(upgraded.settings.packId, "warcraft-lore", "old built-in selection points to its replacement")
            Same(upgraded.settings.league, "Pack upgrade", "pack replacement preserves the selected league")
            Same(saved.settings.packId, retiredId, "selection normalization never mutates caller-owned saved data")
            Check(store:SaveSettings({ packId = retiredId }), "old UI drafts also resolve the replacement pack")
            Same(store:GetSettings().packId, "warcraft-lore", "resaving cannot restore a removed built-in selection")
        end
    end
    for _, untouched in ipairs({ "all", "warcraft_basics_custom", "warcraft-basics-extra", "custom-lore" }) do
        store:Initialize(nil)
        Check(store:SaveSettings({ packId = untouched }), "unrelated pack selection remains valid")
        Same(store:GetSettings().packId, untouched, "only exact retired built-in ids migrate")
    end

    do
        Same(Quiz.WIDGET_SCALE_MIN, 50, "appearance scale starts at fifty percent")
        Same(Quiz.WIDGET_SCALE_MAX, 200, "appearance scale ends at two hundred percent")
        Same(Quiz.WIDGET_SCALE_STEP, 5, "appearance scale uses five-percent increments")
        Same(Quiz.WIDGET_SCALE_DEFAULT, 100, "appearance scale defaults to one hundred percent")
        local appearanceDb = store:Initialize(nil)
        local defaults = { scale = 100, font = "" }
        Same(appearanceDb.schemaVersion, 6, "appearance preferences do not introduce another scoring migration")
        SameTable(store:GetWidgetSettings(), defaults, "new installations receive native appearance defaults")
        local returned = store:GetWidgetSettings()
        Check(returned ~= appearanceDb.widgetSettings, "appearance getter does not expose the saved table")
        Check(returned ~= store:GetWidgetSettings(), "every appearance getter returns a fresh copy")
        returned.scale, returned.font = 200, "Changed outside Store"
        SameTable(store:GetWidgetSettings(), defaults, "mutating an appearance copy does not affect SavedVariables")
        Check(
            store:RecordRound("Appearance", "PUBLIC", ClosedWrong(1)),
            "appearance fixture has existing signed scores"
        )
        Check(store:SaveWidgetPosition(0.27, 0.83), "appearance fixture has an independently saved anchor")
        local hostSettings = store:GetSettings()
        local position = store:GetWidgetPosition()
        local leagues, archives = appearanceDb.leagues, appearanceDb.legacyLeagues
        local nextId = appearanceDb.nextQuestionId
        local incoming = { scale = 125, font = "Font from an absent SharedMedia pack" }
        Check(
            store:SaveWidgetSettings(incoming),
            "unavailable safe font keys can be saved independently of font loading"
        )
        SameTable(store:GetWidgetSettings(), incoming, "appearance stores the requested scale and font name")
        Check(appearanceDb.widgetSettings ~= incoming, "appearance setter copies caller-owned settings")
        incoming.scale, incoming.font = 195, "Caller mutation"
        Same(store:GetWidgetSettings().scale, 125, "later caller mutation cannot alter the saved scale")
        Same(
            store:GetWidgetSettings().font,
            "Font from an absent SharedMedia pack",
            "later caller mutation cannot alter the saved font"
        )
        Check(store:SaveWidgetSettings({ scale = 150 }), "scale can be patched without supplying a font")
        Same(
            store:GetWidgetSettings().font,
            "Font from an absent SharedMedia pack",
            "scale patch preserves the saved font"
        )
        Check(store:SaveWidgetSettings({ font = "Selected Font" }), "font can be patched without supplying a scale")
        Same(store:GetWidgetSettings().scale, 150, "font patch preserves the saved scale")
        Check(store:SaveWidgetSettings({}), "an empty appearance patch preserves the current choices")
        SameTable(
            store:GetWidgetSettings(),
            { scale = 150, font = "Selected Font" },
            "empty appearance patch is a value no-op"
        )
        Check(
            store:SaveWidgetSettings({ duration = 60, league = "Other", widgetPosition = { x = 0, y = 0 } }),
            "appearance only copies its supported fields"
        )
        SameTable(
            store:GetWidgetSettings(),
            { scale = 150, font = "Selected Font" },
            "unknown appearance fields are never persisted"
        )
        SameTable(store:GetSettings(), hostSettings, "appearance changes never alter host setup")
        SameTable(store:GetWidgetPosition(), position, "appearance changes never move the widget")
        Same(appearanceDb.leagues, leagues, "appearance saves preserve all score-board identities")
        Same(appearanceDb.legacyLeagues, archives, "appearance saves preserve all archived board identities")
        Same(appearanceDb.nextQuestionId, nextId, "appearance saves do not allocate question IDs")
        Same(store:GetStandings("Appearance", "PUBLIC")[1].score, -0.9, "appearance saves preserve earned penalties")
        Same(
            appearanceDb.leagues.Appearance.PUBLIC.history[1].scoringVersion,
            2,
            "appearance saves preserve historical scoring metadata"
        )
        Same(appearanceDb.settings.widgetSettings, nil, "appearance is not part of game settings")
        Same(appearanceDb.settings.scale, nil, "appearance scale is not a game setting")
        Same(appearanceDb.settings.font, nil, "appearance font is not a game setting")
        Check(
            store:SaveSettings({ league = "Host changed", scale = 50, font = "Wrong owner" }),
            "game setup can change independently of appearance"
        )
        Check(store:SaveWidgetPosition(0.12, 0.34), "widget position can change independently of appearance")
        SameTable(
            store:GetWidgetSettings(),
            { scale = 150, font = "Selected Font" },
            "other settings owners cannot overwrite appearance"
        )
        for scale = 50, 200, 5 do
            Check(store:SaveWidgetSettings({ scale = scale }), "every supported scale step can be saved")
            Same(store:GetWidgetSettings().scale, scale, "scale steps persist without conversion or rounding")
            Same(store:GetWidgetSettings().font, "Selected Font", "every scale step preserves the chosen font")
        end
        for _, font in ipairs({
            "",
            "Friz Quadrata TT",
            "Font (Bold)",
            "選定字體",
            string.rep("f", 128),
            string.rep("選", 42) .. "ab",
        }) do
            Check(store:SaveWidgetSettings({ font = font }), "safe native-default, named and UTF-8 font keys save")
            Same(store:GetWidgetSettings().font, font, "font keys are retained byte-for-byte")
        end
        Check(
            store:SaveWidgetSettings({ scale = 125, font = "Missing on this device" }),
            "restore known appearance before rejection tests"
        )
        local savedAppearance = appearanceDb.widgetSettings
        local stableHostSettings, stablePosition = appearanceDb.settings, appearanceDb.widgetPosition
        local function RejectAppearance(value, reason)
            local accepted, failure = store:SaveWidgetSettings(value)
            Same(accepted, false, "invalid appearance patch rejects")
            Same(failure, reason, "appearance validation reports the specific invalid field")
            Same(store.db, appearanceDb, "invalid appearance patch cannot replace the database")
            Same(
                appearanceDb.widgetSettings,
                savedAppearance,
                "invalid appearance patch cannot replace prior preferences"
            )
            SameTable(
                store:GetWidgetSettings(),
                { scale = 125, font = "Missing on this device" },
                "invalid appearance patch is atomic"
            )
            Same(appearanceDb.settings, stableHostSettings, "invalid appearance cannot modify host settings")
            Same(appearanceDb.widgetPosition, stablePosition, "invalid appearance cannot modify widget position")
            Same(appearanceDb.leagues, leagues, "invalid appearance cannot modify current scores")
            Same(appearanceDb.legacyLeagues, archives, "invalid appearance cannot modify archived scores")
            Same(appearanceDb.nextQuestionId, nextId, "invalid appearance cannot modify question IDs")
        end
        RejectAppearance(nil, "invalid_widget_settings")
        for _, value in ipairs({ false, true, 100, "font", function() end }) do
            RejectAppearance(value, "invalid_widget_settings")
        end
        for _, scale in ipairs({
            0,
            -50,
            49,
            201,
            51,
            99,
            101,
            199,
            100.5,
            math.huge,
            -math.huge,
            0 / 0,
            "100",
            false,
            {},
        }) do
            RejectAppearance({ scale = scale, font = "Must not partially save" }, "invalid_widget_scale")
        end
        for _, font in ipairs({
            " ",
            "   ",
            string.rep("f", 129),
            false,
            true,
            0,
            {},
            "|cffff0000Font",
            "Font|r",
            "Font\nName",
            "Font\tName",
            "Font\127Name",
            "Font\0Name",
        }) do
            RejectAppearance({ scale = 200, font = font }, "invalid_widget_font")
        end
        for byte = 0, 31 do
            RejectAppearance({ font = "Font" .. string.char(byte) }, "invalid_widget_font")
        end
        local reloadedAppearance = store:Initialize(appearanceDb)
        Check(reloadedAppearance ~= nil, "appearance settings reload beside existing scores")
        SameTable(
            store:GetWidgetSettings(),
            { scale = 125, font = "Missing on this device" },
            "scale and unavailable font survive reload"
        )
        SameTable(
            store:GetWidgetPosition(),
            { x = 0.12, y = 0.34 },
            "reloading appearance preserves independent anchor"
        )
        Same(store:GetSettings().league, "Host changed", "reloading appearance preserves host setup")
        Same(store:GetStandings("Appearance", "PUBLIC")[1].score, -0.9, "reloading appearance preserves signed scores")
        Check(
            reloadedAppearance.widgetSettings ~= appearanceDb.widgetSettings,
            "initialization copies saved appearance"
        )
        appearanceDb.widgetSettings.scale = 175
        Same(store:GetWidgetSettings().scale, 125, "mutating old SavedVariables input cannot change loaded appearance")

        for version = 1, 6 do
            local old = { schemaVersion = version, widgetPosition = { x = 0.3, y = 0.7 } }
            local loaded = store:Initialize(old)
            Check(loaded ~= nil, "every supported schema accepts absent appearance settings")
            SameTable(store:GetWidgetSettings(), defaults, "missing appearance receives defaults without a schema bump")
            Same(old.widgetSettings, nil, "defaults are never written into the supplied old database")
            old.widgetSettings = { scale = 175, font = "Saved but unavailable font" }
            loaded = store:Initialize(old)
            Check(loaded ~= nil, "every migration path retains optional appearance settings")
            Same(loaded.schemaVersion, 6, "appearance loading preserves the existing current schema version")
            SameTable(store:GetWidgetSettings(), old.widgetSettings, "migration carries scale and font preferences")
            SameTable(store:GetWidgetPosition(), old.widgetPosition, "appearance migration leaves the anchor unchanged")
            Check(
                loaded.widgetSettings ~= old.widgetSettings,
                "migration copies optional appearance instead of sharing it"
            )
            old.widgetSettings = { scale = 50 }
            Check(store:Initialize(old) ~= nil, "old partial appearance settings receive missing defaults")
            SameTable(store:GetWidgetSettings(), { scale = 50, font = "" }, "missing font defaults to native text")
            old.widgetSettings = { font = "Saved Font" }
            Check(store:Initialize(old) ~= nil, "a font-only saved preference remains supported")
            SameTable(
                store:GetWidgetSettings(),
                { scale = 100, font = "Saved Font" },
                "missing scale defaults independently"
            )
            local intact = store.db
            for _, invalid in ipairs({
                { value = false, reason = "invalid_widget_settings" },
                { value = 100, reason = "invalid_widget_settings" },
                { value = "Font", reason = "invalid_widget_settings" },
                { value = { scale = 99 }, reason = "invalid_widget_scale" },
                { value = { scale = "100" }, reason = "invalid_widget_scale" },
                { value = { font = " " }, reason = "invalid_widget_font" },
                { value = { font = "|Ttexture|t" }, reason = "invalid_widget_font" },
            }) do
                old.widgetSettings = invalid.value
                local rejected, reason = store:Initialize(old)
                Same(rejected, nil, "every migration validates optional appearance before replacing the database")
                Same(reason, invalid.reason, "invalid saved appearance reports a stable reason")
                Same(store.db, intact, "invalid saved appearance preserves the complete prior database")
                Same(old.widgetSettings, invalid.value, "failed appearance migration never edits supplied input")
            end
        end
        local legacyAppearance = {
            schemaVersion = 3,
            widgetSettings = { scale = 135, font = "Archive Font" },
            leagues = { Archive = { PUBLIC = LegacyBoard(7, false), WHISPER = LegacyBoard(8, true) } },
        }
        local migratedAppearance = store:Initialize(legacyAppearance)
        Check(migratedAppearance ~= nil, "appearance preferences migrate beside old hundred-point boards")
        SameTable(
            store:GetWidgetSettings(),
            legacyAppearance.widgetSettings,
            "legacy scoring migration retains appearance"
        )
        SameTable(
            migratedAppearance.legacyLeagues,
            legacyAppearance.leagues,
            "legacy scoring migration retains all archived history"
        )
        Same(
            store:GetLegacyStandings("Archive", "PUBLIC")[1].score,
            -50,
            "appearance migration leaves archived penalties untouched"
        )
        Same(
            store:GetLegacyStandings("Archive", "WHISPER")[1].score,
            120,
            "appearance migration leaves archived bonuses untouched"
        )
        local decimalAppearance = {
            schemaVersion = 4,
            widgetSettings = { scale = 90, font = "Earlier Font" },
            leagues = {
                Earlier = {
                    PUBLIC = {
                        lastRoundId = 1,
                        players = {
                            ["Player-1-A"] = {
                                name = "Alice-Realm",
                                score = 2.5,
                                correct = 1,
                                incorrect = 0,
                                answers = 1,
                            },
                        },
                        history = { PreviousRound(1, true, 5, 20) },
                    },
                },
            },
        }
        local upgradedAppearance = store:Initialize(decimalAppearance)
        Check(upgradedAppearance ~= nil, "appearance preferences migrate beside old decimal scoring")
        SameTable(
            store:GetWidgetSettings(),
            decimalAppearance.widgetSettings,
            "decimal migration retains selected appearance"
        )
        Same(
            store:GetStandings("Earlier", "PUBLIC")[1].score,
            2.5,
            "appearance migration never rescales old decimal totals"
        )
        Same(
            upgradedAppearance.leagues.Earlier.PUBLIC.history[1].scoringVersion,
            1,
            "appearance does not interfere with scoring-version migration"
        )
        Same(
            upgradedAppearance.leagues.Earlier.PUBLIC.history[1].duration,
            20,
            "appearance does not rewrite historical answer windows"
        )
    end

    do
        local function Winner(actions, multiplayer)
            local winnerGame = NewGame(1)
            local current = Open(winnerGame, 1, 0)
            for index, action in ipairs(actions) do
                Check(
                    winnerGame:Submit(action[1], action[2], current.id, action[3], action[4], "revision-" .. index),
                    "winner fixture accepts each real final-selection action"
                )
            end
            Same(current.fastestName, nil, "open question never exposes a provisional correct-answer winner")
            return winnerGame:CloseQuestion(15, multiplayer)
        end
        local fastest = Winner({
            { "wrong", "Quickwrong-Realm", 2, 0 },
            { "later", "Later-Realm", 1, 0.8 },
            { "first", "First-Realm", 1, 0.3 },
        }, true)
        Same(fastest.fastestName, "First-Realm", "fastest correct answer wins, ignoring an earlier incorrect guess")
        Same(fastest.fastestElapsed, 0.3, "winner retains precise host time instead of rounded point ties")
        Same(fastest.correctCount, 2, "winner selection never changes normal scoring counts")
        Same(fastest.totalAnswers, 3, "all scored answers remain in the round result")

        fastest = Winner({
            { "changed", "Changed-Realm", 1, 0.1 },
            { "steady", "Steady-Realm", 1, 1.25 },
            { "changed", "Changed-Realm", 2, 2 },
            { "changed", "Changed-Realm", 1, 5 },
        }, true)
        Same(fastest.fastestName, "Steady-Realm", "changing away and back uses the latest accepted selection time")
        Same(fastest.fastestElapsed, 1.25, "earlier abandoned correct selections have no winner-time authority")
        fastest = Winner({
            { "same", "Same-Realm", 1, 0.125 },
            { "later", "Later-Realm", 1, 0.75 },
            { "same", "Same-Realm", 1, 8 },
        }, true)
        Same(fastest.fastestName, "Same-Realm", "same-choice retries preserve the original winning answer")
        Same(fastest.fastestElapsed, 0.125, "same-choice retries cannot make a valid winner slower")

        for _, actions in ipairs({
            { { "a", "Zulu-Realm", 1, 1 }, { "z", "Alpha-Realm", 1, 1 } },
            { { "z", "Alpha-Realm", 1, 1 }, { "a", "Zulu-Realm", 1, 1 } },
        }) do
            fastest = Winner(actions, true)
            Same(
                fastest.fastestName,
                "Alpha-Realm",
                "exact-time ties use normalized full name independently of insertion"
            )
        end
        fastest = Winner({ { "z", "alpha-Realm", 1, 1 }, { "a", "Alpha-Realm", 1, 1 } }, true)
        Same(fastest.fastestName, "Alpha-Realm", "same normalized-name ties use stable player identity")
        for _, actions in ipairs({ {}, { { "one", "One-Realm", 2, 0 }, { "two", "Two-Realm", 3, 1 } } }) do
            fastest = Winner(actions, true)
            Same(fastest.fastestName, nil, "a round without a correct answer has no winner")
            Same(fastest.fastestElapsed, nil, "a round without a correct answer has no invented winning time")
        end
        for _, multiplayer in ipairs({ false, "true", 1 }) do
            fastest = Winner({ { "solo", "Solo-Realm", 1, 0 } }, multiplayer)
            Same(fastest.fastestName, nil, "only explicitly multiplayer round context may announce a winner")
            Same(fastest.fastestElapsed, nil, "solo results omit winner time")
        end
        fastest = Winner({ { "solo", "Solo-Realm", 1, 0 } })
        Same(fastest.fastestName, nil, "existing pure-model callers default to no multiplayer announcement")
    end

    return assertions
end

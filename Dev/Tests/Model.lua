return function(Games)
    local Quiz = Games.Quiz
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
    local function Settings()
        return { packId = "all" }
    end
    local function NewGame(count, deckSize, random)
        local rules = Quiz.Rules.Normalize({ repeatQuestions = false, questionLimit = count })
        local game, reason = Quiz.Model.New(Settings(), Questions(deckSize or count), random or KeepOrder, rules)
        Check(game ~= nil, reason)
        return game
    end
    local function Open(game, id, now)
        local round, reason = game:PrepareQuestion(id)
        Check(round ~= nil, reason)
        Check(game:OpenQuestion(now), "question should open")
        return round
    end
    Same(Quiz.ANSWER_SECONDS, 15, "all locally hosted answer windows are fixed at fifteen seconds")
    Same(Quiz.Scoring.VERSION, 3, "explicit pack rules use the new configurable scoring version")
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
    Same(game:GetStandings()[2].score, 0, "incorrect final selection floors the visible total at zero")
    Same(game:GetStandings()[2].answers, 1, "three selections still count as one finalized answer")
    Same(game:GetStandings()[2].incorrect, 1, "only the final selection determines correctness count")
    Check(game:CloseQuestion(130) == nil, "question only closes once")
    Same(game.completed, 1, "duplicate close cannot increment question count")
    Same(game:GetStandings()[2].score, 0, "duplicate close cannot change scores")
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
    Same(game:GetStandings()[1].score, 2.4, "a zero-floored penalty cannot become hidden score debt")
    Check(not game:Pause("late"), "finished game cannot be paused")
    Check(game:PrepareQuestion(9) == nil, "finished game cannot prepare")

    local floorSequence = NewGame(2)
    local floorRound = Open(floorSequence, 50, 0)
    Check(
        floorSequence:Submit("Player-Floor", "Floor-Realm", floorRound.id, 2, 0),
        "a fast wrong answer is accepted at zero"
    )
    floorSequence:CloseQuestion(15)
    Same(floorSequence:GetStandings()[1].score, 0, "a wrong answer cannot lower the current score below zero")
    floorRound = Open(floorSequence, 51, 20)
    Check(
        floorSequence:Submit("Player-Floor", "Floor-Realm", floorRound.id, floorRound.correctIndex, 34.999),
        "a near-deadline correct answer is accepted after a floored penalty"
    )
    local floorResult = floorSequence:CloseQuestion(35)
    Same(floorResult.answers[1].points, 1, "near-deadline correctness earns the base point")
    Same(floorSequence:GetStandings()[1].score, 1, "a prior floored penalty cannot consume a correct answer")
    Check(floorSequence:CloseQuestion(35) == nil, "a finalized floor sequence cannot close twice")
    Same(floorSequence:GetStandings()[1].score, 1, "duplicate closure cannot record the recovered point twice")

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
    Same(guesses:GetStandings()[1].score, 0, "transient guesses do not stack penalties below zero")
    Same(guesses:GetStandings()[1].incorrect, 1, "multiple changes still count as one incorrect answer")

    local copiedSettings = Settings(1)
    copiedSettings.extra = { label = "original" }
    local copiedQuestions = Questions(2)
    local originalChoice = copiedQuestions[1].choices[1]
    local copiedGame = Quiz.Model.New(copiedSettings, copiedQuestions, KeepOrder)
    copiedSettings.extra.label = "modified"
    copiedQuestions[1].prompt = "modified"
    copiedQuestions[1].choices[1] = "modified"
    Same(copiedGame.settings.extra.label, "original", "nested input is copied")
    local copiedRound = Open(copiedGame, 11, 0)
    Same(copiedRound.prompt, "Question 1", "question input is copied")
    Same(copiedRound.choices[1], originalChoice, "choice input is copied")

    local fixedGame = Quiz.Model.New(Settings(), Questions(1), KeepOrder)
    fixedGame.settings.duration = 60
    local fixedRound = Open(fixedGame, 1, 100)
    Same(fixedRound.deadline, 115, "mode settings cannot extend the pack-owned answer clock")
    fixedGame.settings.duration = 1
    Check(fixedGame:Submit("Fixed", "Fixed-Realm", 1, fixedRound.correctIndex, 104), "fixed-window answer accepts")
    Same(fixedRound.answers.Fixed.points, 2.1, "mode settings cannot change pack-owned timing points")
    fixedGame.settings.duration = 600
    Check(not fixedGame:Submit("Fixed", "Fixed-Realm", 1, fixedRound.correctIndex, 115.01), "fixed cutoff rejects")
    Check(fixedGame:CloseQuestion(114.99) == nil, "fixed round cannot close before fifteen seconds")
    local fixedResult = fixedGame:CloseQuestion(115)
    Same(fixedResult.duration, 15, "history records the pack-owned answer window")
    Same(fixedResult.scoringVersion, 3, "history identifies the pack rules that scored the result")
    Same(fixedResult.answers[1].points, 2.1, "mode settings cannot re-score a finalized answer")

    local retiredGameSettings = Settings(1)
    for key, value in pairs(OldChatSettings()) do
        retiredGameSettings[key] = value
    end
    local retiredGame = Quiz.Model.New(retiredGameSettings, Questions(1), KeepOrder)
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
    Check(Quiz.Model.New(Settings(), {}) == nil, "empty deck rejected")
    local duplicateQuestions = Questions(2)
    duplicateQuestions[2].key = duplicateQuestions[1].key
    Check(Quiz.Model.New(Settings(), duplicateQuestions) == nil, "duplicate keys rejected")
    Check(Quiz.Model.New(Settings(), Questions(2), function()
        return 0
    end) == nil, "invalid RNG rejected")

    local continuousSettings = Settings()
    local continuousDeckSize = 61
    local continuous = Quiz.Model.New(continuousSettings, Questions(continuousDeckSize), KeepOrder)
    Check(continuous ~= nil, "continuous mode does not require the unused finite question count")
    Same(continuous.continuous, true, "continuous mode is explicit on the game")
    Same(continuous.cycle, 1, "first shuffled cycle starts at one")
    Same(continuous.total, continuousDeckSize, "continuous total is the entire selected deck")
    Same(continuous.usedIds, nil, "continuous mode never allocates a growing question-ID map")
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
    end
    Same(continuous.completed, continuousRounds, "completed counts all session rounds across cycles")
    Same(continuous.total, continuousDeckSize, "cycling never changes the deck total")
    Same(#continuous.deck, continuousDeckSize, "cycling keeps bounded deck storage")
    Same(continuous.usedIds, nil, "many cycles still have no per-round ID map")
    Same(continuous.lastQuestionId, continuousRounds, "continuous ID memory is one high watermark")
    Same(continuous:GetStandings()[1].score, continuousRounds * 24 / 10, "session points continue across cycles")
    Same(continuous:GetStandings()[1].correct, continuousRounds, "session answer counts continue across cycles")
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
    local boundarySettings = Settings()
    local boundaries = Quiz.Model.New(boundarySettings, Questions(2), function()
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

    local voidCycles = Quiz.Model.New(boundarySettings, Questions(3), KeepOrder)
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

    local single = Quiz.Model.New(boundarySettings, Questions(1), KeepOrder)
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
    local failedCycle = Quiz.Model.New(boundarySettings, Questions(2), function(maximum)
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
    Check(Quiz.Model.New(false, Questions(2)) == nil, "non-table settings reject")
    local finiteIds = NewGame(2)
    Open(finiteIds, 10, 0)
    finiteIds:CloseQuestion(20)
    Check(finiteIds:PrepareQuestion(2) == nil, "finite mode also rejects an older question ID")

    local store = Quiz.Store
    local db = store:Initialize(nil)
    Check(db ~= nil, "fresh Quiz database initializes")
    Same(db.schemaVersion, 7, "fresh database uses the current Quiz mode schema")
    SameTable(db.settings, { packId = "all" }, "fresh database persists only Quiz pack selection")
    Same(next(db.leagues), nil, "fresh current-scoring boards are empty")
    Same(next(db.legacyLeagues), nil, "fresh installations have no old-scale archive")

    local normalized = store:Normalize({ schemaVersion = 7, settings = { packId = "custom-pack" } })
    Check(normalized ~= nil, "pure normalization accepts the current Quiz schema")
    Same(store.db, db, "pure normalization does not replace the bound database")
    Same(normalized.settings.packId, "custom-pack", "pure normalization retains pack selection")
    store:Bind(normalized)
    Same(store.db, normalized, "explicit binding installs normalized Quiz mode data")
    Same(Quiz.PersonalScores.data, normalized.personalScores, "binding installs the mode-owned score subtree")

    local settings = store:GetSettings()
    settings.packId = "warcraft-lore"
    Same(store:GetSettings().packId, "custom-pack", "settings getter returns a copy")
    Check(store:SaveSettings(settings), "pack selection saves")
    settings.packId = "changed"
    Same(store:GetSettings().packId, "warcraft-lore", "saved settings are copied")
    Check(not store:SaveSettings({ packId = false }), "non-string pack selection rejects")
    Check(not store:SaveSettings({ packId = "" }), "empty pack selection rejects")
    Check(not store:SaveSettings({ packId = string.rep("x", 97) }), "oversized pack selection rejects")
    Check(store:SaveSettings(OldChatSettings()), "retired settings objects remain harmless input")
    SameTable(store:GetSettings(), { packId = "warcraft-lore" }, "retired settings are never persisted")

    local position = store:GetWidgetPosition()
    SameTable(position, { x = 0.5, y = 0.65 }, "widget receives normalized position defaults")
    position.x = 0
    Same(store:GetWidgetPosition().x, 0.5, "position getter does not expose the saved table")
    Check(store:SaveWidgetPosition(0.25, 0.75), "normalized widget position saves")
    SameTable(store:GetWidgetPosition(), { x = 0.25, y = 0.75 }, "saved position round-trips")
    for _, invalid in ipairs({ -0.01, 1.01, math.huge, -math.huge, 0 / 0, false, "0.5", {} }) do
        local accepted, reason = store:SaveWidgetPosition(invalid, 0.5)
        Check(not accepted, "invalid horizontal position rejects")
        Same(reason, "invalid_widget_position", "position validation has a stable failure code")
    end

    SameTable(store:GetWidgetSettings(), { scale = 100, font = "" }, "widget appearance receives defaults")
    Check(store:SaveWidgetSettings({ scale = 125, font = "Selected Font" }), "widget appearance saves")
    SameTable(
        store:GetWidgetSettings(),
        { scale = 125, font = "Selected Font" },
        "widget appearance round-trips independently"
    )
    Check(not store:SaveWidgetSettings({ scale = 126 }), "off-step widget scale rejects")
    Check(not store:SaveWidgetSettings({ font = string.rep("x", 129) }), "oversized widget font rejects")

    local legacy = {
        schemaVersion = 1,
        settings = {
            packId = "test",
            league = "Retired",
            hostName = "RetiredHost-Realm",
            questionCount = 17,
            autoAdvance = true,
        },
        nextQuestionId = 40,
        leagues = {},
    }
    local migrated, migrationError = store:Normalize(legacy)
    Check(migrated ~= nil, migrationError)
    Same(migrated.schemaVersion, 7, "legacy Quiz data reaches the current mode schema")
    SameTable(migrated.settings, { packId = "test" }, "migration retains only active Quiz settings")
    Same(migrated.nextQuestionId, 40, "migration preserves the question allocator")
    Same(legacy.schemaVersion, 1, "normalization leaves legacy input untouched")

    for version = 1, 7 do
        local loaded, reason = store:Normalize({ schemaVersion = version })
        Check(loaded ~= nil, "every supported Quiz schema normalizes: " .. tostring(reason))
        Same(loaded.schemaVersion, 7, "every supported Quiz schema reaches the current version")
        SameTable(loaded.settings, { packId = "all" }, "missing settings receive only the pack default")
    end
    local preserved = store.db
    local future = { schemaVersion = 8, important = { value = "keep" } }
    local rejected, futureError = store:Initialize(future)
    Same(rejected, nil, "future Quiz schemas reject")
    Same(futureError, "unsupported_database_version", "future Quiz schemas have a stable failure code")
    Same(store.db, preserved, "future rejection does not replace bound mode data")
    Same(future.schemaVersion, 8, "future input is never rewritten")

    for _, retiredId in ipairs({ "warcraft_basics", "warcraft-basics" }) do
        local upgraded = store:Normalize({ schemaVersion = 7, settings = { packId = retiredId } })
        Same(upgraded.settings.packId, "warcraft-lore", "retired built-in selection resolves to its replacement")
    end
    store:Bind(store:Normalize(nil))
    Same(store:NextQuestionId(), 1, "newly bound default database starts its question allocator at one")
    Same(store:NextQuestionId(), 2, "question allocator advances monotonically")

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

    do
        local calls = 0
        local authoredRules = {
            answerSeconds = 30,
            revealSeconds = 7,
            shuffleQuestions = false,
            shuffleChoices = false,
            correctPoints = 2,
            speedBonusPerSecond = 0.2,
            streakBonusPerCorrect = 0.2,
            streakBonusMax = 1,
        }
        local hostSettings = { duration = 1, answerSeconds = 1, continuous = "false", correctPoints = 99 }
        local explicit, reason = Quiz.Model.New(hostSettings, Questions(2), function(maximum)
            calls = calls + 1
            return maximum
        end, authoredRules)
        Check(explicit ~= nil, "valid pack rules override every obsolete host rule field: " .. tostring(reason))
        Same(explicit.rules.answerSeconds, 30, "resolved pack duration owns the model clock")
        Same(explicit.continuous, true, "host finite-setting values cannot override authored endless play")
        Same(explicit.scoringVersion, 3, "explicit pack rules create version-three scoring results")
        Same(calls, 0, "fixed authored question order never calls the random source")
        local canonical = Quiz.Rules.Encode(authoredRules)
        authoredRules.answerSeconds, authoredRules.correctPoints = 120, 999
        hostSettings.duration = 120
        explicit.settings.duration = 120
        local current = Open(explicit, 1, 100)
        Same(current.key, "test:q1", "fixed order begins with the first authored question")
        Same(current.deadline, 130, "copied pack rules ignore later author and host-setting mutations")
        Same(current.duration, 30, "round metadata reports the actual answer duration")
        Same(current.revealSeconds, 7, "round metadata reports the author's reveal duration")
        Same(current.rulesKey, canonical, "round identity covers its complete rules snapshot")
        Same(current.choices[1], "Right", "fixed choices retain their authored order and answer key")
        current.rules.answerSeconds, current.rules.correctPoints = 5, 999
        Check(
            explicit:Submit("Author", "Author-Realm", 1, 1, 120),
            "authored timing accepts an answer after fifteen seconds"
        )
        Same(current.answers.Author.points, 4, "host fields and exposed round metadata cannot override authored score")
        Check(explicit:CloseQuestion(129.999) == nil, "thirty-second rounds cannot close using the legacy deadline")
        local closed = explicit:CloseQuestion(130)
        Same(closed.duration, 30, "finalized duration comes from the locked game rules")
        Same(closed.revealSeconds, 7, "final result carries custom reveal duration")
        Same(closed.rules.correctPoints, 2, "result rules are not copied from mutable presentation state")
        Same(closed.rulesKey, canonical, "result identity matches the question's original rules")
        Same(closed.scoringVersion, 3, "pack-rule results identify the new scorer")
        Same(closed.complete, false, "endless games never announce finite completion")
        Same(closed.answers[1].streak, 1, "first correct final answer starts the player's streak")
        Same(closed.answers[1].streakBonus, 0, "first correct answer does not get a consecutive bonus")
        closed.rules.answerSeconds, closed.answers[1].streak = 5, 999
        Same(explicit.rules.answerSeconds, 30, "saved/result consumers cannot mutate active game rules")
        Same(explicit.players.Author.streak, 1, "result consumers cannot mutate a player's live streak")
        current = Open(explicit, 2, 200)
        Same(current.key, "test:q2", "fixed question order advances without randomization")
        Same(current.deadline, 230, "later rounds retain the original authored clock")
        explicit:CloseQuestion(230)
        current = Open(explicit, 3, 300)
        Same(current.key, "test:q1", "fixed repeated quizzes return to the first authored question")
        Same(current.cycle, 2, "authored fixed repetition still tracks full cycles")
        Same(calls, 0, "question and choice shuffling toggles cover every repeated cycle")
        for _, raw in ipairs({ false, "rules", { answerSeconds = 0 }, { streakBonusPerCorrect = 0.1 } }) do
            local invalid = Quiz.Model.New({}, Questions(1), KeepOrder, raw)
            Same(invalid, nil, "model rejects invalid externally supplied pack rules at its constructor boundary")
        end
    end

    do
        local cases = {
            { repeatQuestions = false, questionLimit = 0, deck = 3, total = 3 },
            { repeatQuestions = false, questionLimit = 1, deck = 3, total = 1 },
            { repeatQuestions = false, questionLimit = 10, deck = 3, total = 3 },
            { repeatQuestions = true, questionLimit = 5, deck = 2, total = 5 },
            { repeatQuestions = true, questionLimit = 1, deck = 3, total = 1 },
        }
        for _, case in ipairs(cases) do
            local rules = Quiz.Rules.Normalize({
                answerSeconds = 5,
                revealSeconds = 1,
                repeatQuestions = case.repeatQuestions,
                questionLimit = case.questionLimit,
                shuffleQuestions = false,
                shuffleChoices = false,
            })
            local finite = Quiz.Model.New({}, Questions(case.deck), KeepOrder, rules)
            Same(finite.total, case.total, "finite target combines author cap with repetition permission")
            Same(finite.continuous, false, "one-pass and capped quizzes are finite")
            Same(
                finite.usedIds,
                nil,
                "new finite quizzes use a bounded high watermark rather than per-round ID storage"
            )
            for index = 1, case.total do
                local current = Open(finite, index, index * 10)
                Same(current.number, index, "finite question numbering spans repeated source cycles")
                Same(
                    current.key,
                    "test:q" .. ((index - 1) % case.deck + 1),
                    "finite repeat respects authored deck order"
                )
                Same(current.cycle, math.floor((index - 1) / case.deck) + 1, "finite repeated cycles retain identity")
                local finished = finite:CloseQuestion(index * 10 + 5)
                Same(finished.complete, index == case.total, "only the final closed question requests completion")
                Same(
                    finite.state,
                    index == case.total and "finished" or "results",
                    "finite state changes at the author limit"
                )
                Same(finite.completed, index, "finite cap counts closed questions, not submissions")
            end
            Same(finite:PrepareQuestion(case.total + 1), nil, "finite quiz cannot silently start another cycle")
        end
        local exhausted = Quiz.Model.New({}, Questions(2), KeepOrder, {
            repeatQuestions = false,
            shuffleQuestions = false,
            shuffleChoices = false,
        })
        exhausted:PrepareQuestion(1)
        Check(exhausted:Pause("restricted"), "single-pass question can be voided before it opens")
        Same(exhausted.total, 1, "a voided single-pass card cannot be asked again against the author's repeat rule")
        Same(exhausted.completed, 0, "voiding a question does not count as completing it")
        Check(exhausted:Resume(), "remaining single-pass card is available after restrictions clear")
        Same(Open(exhausted, 2, 20).key, "test:q2", "resume does not replay the voided single-pass card")
        Check(exhausted:CloseQuestion(35).complete, "last available single-pass card ends the quiz")
        local repeated = Quiz.Model.New({}, Questions(1), KeepOrder, { questionLimit = 2 })
        for id = 1, 100 do
            Check(
                repeated:PrepareQuestion(id) ~= nil,
                "finite repeating quizzes may recover from repeated interruptions"
            )
            Check(repeated:Pause("restricted"), "posting round voids without consuming its completed-round cap")
            Check(repeated:Resume(), "finite repeating quiz remains ready after a void")
            Same(repeated.total, 2, "voided rounds never consume a repeat-enabled question limit")
            Same(repeated.usedIds, nil, "many voids cannot grow a finite-session receipt-ID map")
        end
        Same(repeated:PrepareQuestion(100), nil, "even voided finite-round IDs cannot be reused")
        Open(repeated, 101, 0)
        Check(not repeated:CloseQuestion(15).complete, "first scored finite repeat remains active after many voids")
        Open(repeated, 102, 20)
        Check(repeated:CloseQuestion(35).complete, "the configured count still ends the finite repeating quiz")
    end

    do
        for _, questionShuffle in ipairs({ false, true }) do
            for _, choiceShuffle in ipairs({ false, true }) do
                local calls = 0
                local independent = Quiz.Model.New({}, Questions(3), function()
                    calls = calls + 1
                    return 1
                end, { shuffleQuestions = questionShuffle, shuffleChoices = choiceShuffle })
                Same(calls, questionShuffle and 2 or 0, "question-order toggle independently owns deck randomization")
                local current = Open(independent, 1, 0)
                Same(
                    calls,
                    (questionShuffle and 2 or 0) + (choiceShuffle and 3 or 0),
                    "choice-order toggle independently owns answer randomization"
                )
                Same(
                    current.choices[current.correctIndex],
                    "Right",
                    "every ordering combination preserves correct answer mapping"
                )
                Same(
                    current.correctIndex == 1,
                    not choiceShuffle,
                    "disabling choice shuffle preserves the author's correct index"
                )
                Same(
                    current.key == "test:q1",
                    not questionShuffle,
                    "disabling question shuffle preserves the first authored entry"
                )
            end
        end
    end

    do
        local locked = Quiz.Model.New(
            {},
            Questions(1),
            KeepOrder,
            { allowAnswerChanges = false, shuffleChoices = false }
        )
        local current = Open(locked, 1, 0)
        Check(
            locked:Submit("Lock", "Lock-Realm", 1, 2, 1, "action-1"),
            "first selection is accepted in a locked-answer quiz"
        )
        local accepted, reason = locked:Submit("Lock", "Lock-Realm", 1, 1, 2, "action-2")
        Same(accepted, false, "locked-answer quiz rejects later distinct selections")
        Same(reason, "answer_locked", "a rejected change identifies the author rule")
        Same(current.answers.Lock.choiceIndex, 2, "a rejected change cannot replace the first answer")
        accepted, reason = locked:Submit("Lock", "Lock-Realm", 1, 2, 14, "action-3")
        Check(accepted, "same-choice retries still acknowledge locked selections")
        Same(reason, "duplicate", "locked retry retains normal duplicate semantics")
        Same(current.answers.Lock.elapsed, 1, "locked retries cannot improve their penalty time")
        Same(
            current.answers.Lock.actionId,
            "action-3",
            "duplicate acknowledgement advances transport revision without retiming"
        )
        Same(locked.players.Lock, nil, "locked selection is not awarded or counted before round closure")
        local result = locked:CloseQuestion(15, true)
        Same(result.answers[1].correct, false, "first locked answer remains authoritative at reveal")
        Same(result.answers[1].streak, 0, "incorrect locked selection cannot preserve a correct-answer streak")
        Same(result.answers[1].streakBonus, 0, "wrong locked selection has no bonus")
        Same(result.answers[1].points, -0.9, "locked penalties use the first accepted selection time")
        Same(result.fastestName, nil, "rejected later correct answers cannot win fastest-correct recognition")
    end

    do
        local rules = Quiz.Rules.Normalize({
            answerSeconds = 5,
            shuffleChoices = false,
            shuffleQuestions = false,
            speedBonusPerSecond = 0,
            streakBonusPerCorrect = 0.1,
            streakBonusMax = 0.3,
        })
        local streakGame = Quiz.Model.New({}, Questions(1), KeepOrder, rules)
        local id, clock = 0, 0
        local function Begin()
            id, clock = id + 1, clock + 10
            return Open(streakGame, id, clock)
        end
        local function Answer(guid, correct, elapsed, action)
            Check(
                streakGame:Submit(guid, guid .. "-Realm", id, correct and 1 or 2, clock + (elapsed or 1), action),
                "streak fixture submits one real player selection"
            )
        end
        local function Close()
            return streakGame:CloseQuestion(clock + rules.answerSeconds, true)
        end
        local function Find(result, guid)
            for _, answer in ipairs(result.answers) do
                if answer.guid == guid then
                    return answer
                end
            end
        end
        Begin()
        Answer("Alice", true, 1)
        Answer("Bob", true, 2)
        local result = Close()
        Same(Find(result, "Alice").streak, 1, "first correct round begins a streak")
        Same(Find(result, "Alice").points, 1, "first correct round has no consecutive bonus")
        Same(Find(result, "Bob").streak, 1, "streak state belongs to each player independently")
        Same(result.fastestName, "Alice-Realm", "custom streak scoring keeps fastest correct timing unchanged")

        local current = Begin()
        Answer("Alice", false, 0, "change-1")
        Answer("Alice", true, 2, "change-2")
        Answer("Bob", false, 5)
        Same(streakGame.players.Alice.streak, 1, "provisional selections cannot advance or reset committed streaks")
        Same(current.answers.Alice.streak, nil, "answer packet is not assigned a finalized streak before closure")
        result = Close()
        Same(Find(result, "Alice").streak, 2, "only final correctness advances the prior consecutive streak")
        Same(Find(result, "Alice").streakBonus, 0.1, "the second consecutive correct round earns one authored step")
        Same(Find(result, "Alice").points, 1.1, "streak reward is awarded once at close")
        Same(Find(result, "Alice").elapsed, 2, "changed answer timing remains its final distinct-selection time")
        Same(Find(result, "Bob").streak, 0, "a wrong closed answer resets only that player's streak")
        Same(streakGame.players.Alice.streak, 2, "another player's failure does not reset a correct streak")
        local score = streakGame.players.Alice.score
        Same(streakGame:CloseQuestion(clock + 10), nil, "duplicate round closure is rejected")
        Same(streakGame.players.Alice.score, score, "duplicate closure cannot award another streak bonus")
        Same(streakGame.players.Alice.streak, 2, "duplicate closure cannot lengthen a streak")

        Begin()
        Answer("Bob", true)
        result = Close()
        Same(Find(result, "Alice"), nil, "unanswered players do not gain invented answer records")
        Same(streakGame.players.Alice.streak, 0, "skipping a closed question breaks a streak")
        Same(streakGame.players.Alice.score, score, "skipping resets streak but never creates a point penalty")
        Same(Find(result, "Bob").streak, 1, "correct answers restart at one after a mistake")

        Begin()
        Answer("Alice", true)
        result = Close()
        Same(Find(result, "Alice").streak, 1, "returning after a skipped question earns a fresh first answer")
        Same(Find(result, "Alice").streakBonus, 0, "returning player cannot skip difficult questions to bank a bonus")
        Same(streakGame.players.Bob.streak, 0, "previously active players reset even when another player alone answers")
        Begin()
        Answer("Alice", true, 0.5, "retry-1")
        Answer("Alice", true, 4, "retry-2")
        result = Close()
        Same(Find(result, "Alice").streak, 2, "repeated same-choice inputs count as one consecutive answer")
        Same(Find(result, "Alice").elapsed, 0.5, "same-choice retries never re-time the accepted selection")
        Same(Find(result, "Alice").streakBonus, 0.1, "same-choice retries never multiply streak rewards")

        local beforeVoid = streakGame.players.Alice.score
        current = Begin()
        Answer("Alice", false)
        Check(streakGame:Pause("restricted"), "restrictions void a provisional incorrect answer")
        Same(streakGame.players.Alice.streak, 2, "voiding a round neither breaks nor advances a streak")
        Same(streakGame.players.Alice.score, beforeVoid, "voided selections never affect points")
        Check(streakGame:Resume(), "play resumes after a void without committing its answers")
        Begin()
        Answer("Alice", true)
        result = Close()
        Same(Find(result, "Alice").streak, 3, "a fresh correct round continues the pre-void streak")
        Same(Find(result, "Alice").streakBonus, 0.2, "voiding a question cannot skip a bonus step")

        for expected = 4, 20 do
            Begin()
            Answer("Alice", true)
            result = Close()
            Same(Find(result, "Alice").streak, expected, "consecutive state spans complete repeated question cycles")
            Same(Find(result, "Alice").streakBonus, 0.3, "long streaks stop increasing the authored bonus cap")
            Same(Find(result, "Alice").points, 1.3, "capped streak points remain exact tenths")
            Same(
                #result.streakMilestones,
                expected >= 5 and 1 or 0,
                "only closed streaks from five announce milestones"
            )
            if expected >= 5 then
                Same(result.streakMilestones[1].name, "Alice-Realm", "milestones retain the authoritative player name")
                Same(result.streakMilestones[1].streak, expected, "every ten-plus correct answer remains a milestone")
            end
        end
        Begin()
        Answer("Alice", true, 1, "final-1")
        Answer("Alice", false, 5, "final-2")
        result = Close()
        Same(Find(result, "Alice").streak, 0, "a wrong final change breaks even a long streak")
        Same(Find(result, "Alice").streakBonus, 0, "earlier abandoned correct selections cannot retain bonuses")
        Same(Find(result, "Alice").points, -0.5, "streak does not soften the final wrong-answer penalty")
        Same(#result.streakMilestones, 0, "wrong final selections cannot announce a stale milestone")
        Begin()
        Answer("Alice", true)
        result = Close()
        Same(Find(result, "Alice").streak, 1, "a post-error correct answer starts again from one")
        Same(Find(result, "Alice").points, 1, "post-error scoring has no banked streak bonus")
        Begin()
        result = Close()
        Same(result.totalAnswers, 0, "entirely unanswered rounds have no made-up entries")
        Same(#result.streakMilestones, 0, "unanswered rounds produce no milestone announcements")
        Same(streakGame.players.Alice.streak, 0, "entirely unanswered rounds reset every known player's streak")
        local fresh = Quiz.Model.New({}, Questions(1), KeepOrder, rules)
        Open(fresh, 1, 0)
        fresh:Submit("Alice", "Alice-Realm", 1, 1, 1)
        Same(fresh:CloseQuestion(5).answers[1].streak, 1, "new sessions never inherit personal or prior-game streaks")
    end

    do
        local rules = assert(Quiz.Rules.Normalize({ answerSeconds = 5, shuffleChoices = false }))
        local game = assert(Quiz.Model.New({}, Questions(1), KeepOrder, rules))
        for id = 1, 4 do
            Open(game, id, id * 10)
            game:Submit("Zed", "Zed-Realm", id, 1, id * 10 + 1)
            game:Submit("Alice", "Alice-Realm", id, 1, id * 10 + 1)
            local result = game:CloseQuestion(id * 10 + 5)
            Same(#result.streakMilestones, 0, "the first four correct answers are below the toast threshold")
        end
        Open(game, 5, 50)
        game:Submit("Alice", "Alice-Realm", 5, 1, 51)
        Same(game.round.streakMilestones, nil, "pending answers do not expose provisional milestones")
        Check(game:Pause("restricted"), "an otherwise fifth correct selection can be voided")
        Same(#game.lastResult.streakMilestones, 0, "a void cannot manufacture the fifth milestone")
        Same(game.players.Alice.streak, 4, "a void leaves the committed pre-milestone streak untouched")
        Check(game:Resume(), "milestone fixture resumes after the void")
        Open(game, 6, 60)
        game:Submit("Zed", "Zed-Realm", 6, 1, 61)
        game:Submit("Alice", "Alice-Realm", 6, 1, 61)
        local result = game:CloseQuestion(65)
        Same(
            #result.streakMilestones,
            2,
            "all qualifying players appear even without scoring bonuses or multiplayer flag"
        )
        Same(result.streakMilestones[1].name, "Alice-Realm", "same-tier milestones sort by canonical player name")
        Same(result.streakMilestones[2].name, "Zed-Realm", "milestone ordering is independent of Lua pairs traversal")
        Same(result.streakMilestones[1].streak, 5, "only the eventual closed fifth correct answer is announced")
        Same(result.answers[1].streakBonus, 0, "milestone presentation does not invent a disabled scoring reward")
        result.answers[1].name = "Changed-Realm"
        Same(
            result.streakMilestones[1].name,
            "Alice-Realm",
            "milestone identity is detached from mutable answer records"
        )
        Open(game, 7, 70)
        game:Submit("Alice", "Alice-Realm", 7, 2, 71)
        result = game:CloseQuestion(75)
        Same(#result.streakMilestones, 0, "wrong and skipped players both disappear from the next milestone batch")
    end

    return assertions
end

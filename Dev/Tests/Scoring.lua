local ANSWER_SECONDS = 15
local HALF_LIFE_SECONDS = 6
local POINT_SCALE = 10
local MIN_PENALTY = 0.5
local MAX_PENALTY = 1
local FLOAT_EPSILON = 0.000000001
local BOUNDARY_DELTA = 0.00001
local GRID_STEPS_PER_SECOND = 1000
local ADDITION_REPETITIONS = 1000
local PENALTY_BOUNDARIES = {
    { 0.7436435574929176, 1, 0.9 },
    { 2.4552899354476643, 0.9, 0.8 },
    { 4.590956513524789, 0.8, 0.7 },
    { 7.432417325825630, 0.7, 0.6 },
    { 11.690547024046282, 0.6, 0.5 },
}
local SCORE_SAMPLES = {
    { 0, 2.5, -1 },
    { 0.001, 2.4, -1 },
    { 3, 2.2, -0.8 },
    { 5, 2, -0.7 },
    { 6, 1.9, -0.7 },
    { 7, 1.8, -0.7 },
    { 8, 1.7, -0.6 },
    { 10, 1.5, -0.6 },
    { 12, 1.3, -0.5 },
    { 14.999999, 1, -0.5 },
    { 15, 1, -0.5 },
}

return function(Quiz)
    local assertions = 0
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function Near(actual, expected, message)
        Check(math.abs(actual - expected) <= FLOAT_EPSILON, message)
    end
    local function Units(points)
        return math.floor(points * POINT_SCALE + 0.5)
    end
    local function RawPenalty(elapsed)
        local terminal = math.exp(-math.log(2) * ANSWER_SECONDS / HALF_LIFE_SECONDS)
        local decay = math.exp(-math.log(2) * elapsed / HALF_LIFE_SECONDS)
        return MIN_PENALTY + (MAX_PENALTY - MIN_PENALTY) * (decay - terminal) / (1 - terminal)
    end
    local function Calculate(correct, elapsed)
        return Quiz.Scoring.Calculate(correct, elapsed, ANSWER_SECONDS)
    end

    Same(Quiz.ANSWER_SECONDS, ANSWER_SECONDS, "hosted questions use the fixed fifteen-second clock")
    Same(Quiz.Scoring.VERSION, 3, "pack rules and consecutive-correct bonuses identify scoring version three")
    Same(Quiz.Scoring.MIN_WRONG_POINTS, -MAX_PENALTY, "the largest wrong-answer deduction is one point")
    Same(Quiz.Scoring.MAX_WRONG_POINTS, -MIN_PENALTY, "the smallest wrong-answer deduction is half a point")
    for _, sample in ipairs(SCORE_SAMPLES) do
        Same(Calculate(true, sample[1]), sample[2], "correct landmark at " .. sample[1])
        Same(Calculate(false, sample[1]), sample[3], "exponential penalty landmark at " .. sample[1])
    end
    Same(Calculate(true, -1), 2.5, "before-start elapsed time cannot exceed the maximum correct bonus")
    Same(Calculate(false, -1), -1, "before-start elapsed time cannot exceed the maximum penalty")
    Same(Calculate(true, ANSWER_SECONDS + 1), 1, "expired elapsed time retains only the correct base point")
    Same(Calculate(false, ANSWER_SECONDS + 1), -0.5, "expired elapsed time retains the minimum penalty")

    for elapsed = 0, ANSWER_SECONDS do
        local expected = (POINT_SCALE + ANSWER_SECONDS - elapsed) / POINT_SCALE
        Same(Calculate(true, elapsed), expected, "whole remaining seconds earn whole tenths")
        Same(Calculate(true, elapsed - BOUNDARY_DELTA), expected, "time just before a bonus boundary does not round up")
        Same(Calculate(true, elapsed + FLOAT_EPSILON), expected, "tiny timestamp noise preserves a bonus boundary")
        if elapsed < ANSWER_SECONDS then
            Same(
                Calculate(true, elapsed + BOUNDARY_DELTA),
                (POINT_SCALE + ANSWER_SECONDS - elapsed - 1) / POINT_SCALE,
                "a meaningful fraction after a bonus boundary loses that tenth"
            )
        end
    end

    Near(RawPenalty(0), MAX_PENALTY, "the unrounded exponential starts at the maximum penalty")
    Near(RawPenalty(ANSWER_SECONDS), MIN_PENALTY, "the unrounded exponential ends at the minimum penalty")
    local terminal = math.exp(-math.log(2) * ANSWER_SECONDS / HALF_LIFE_SECONDS)
    local asymptote = MIN_PENALTY - (MAX_PENALTY - MIN_PENALTY) * terminal / (1 - terminal)
    Near(
        RawPenalty(HALF_LIFE_SECONDS) - asymptote,
        (RawPenalty(0) - asymptote) / 2,
        "the normalized exponential has a six-second half-life"
    )
    Near(
        RawPenalty(HALF_LIFE_SECONDS * 2) - asymptote,
        (RawPenalty(HALF_LIFE_SECONDS) - asymptote) / 2,
        "the exponential retains its half-life after the first six seconds"
    )
    local previousDrop
    for elapsed = 1, ANSWER_SECONDS do
        local drop = RawPenalty(elapsed - 1) - RawPenalty(elapsed)
        Check(drop > 0, "the unrounded penalty decays throughout the question")
        Check(not previousDrop or drop < previousDrop, "unrounded decay is convex, with steeper early penalties")
        previousDrop = drop
    end

    local maximumGuessNumerators = { [4] = -math.huge, [5] = -math.huge, [6] = -math.huge }
    local function CheckBlindGuess(elapsed)
        local correctUnits = Units(Calculate(true, elapsed))
        local wrongUnits = Units(Calculate(false, elapsed))
        for choiceCount = 4, 6 do
            local numerator = correctUnits + (choiceCount - 1) * wrongUnits
            Check(numerator < 0, "blind guessing must lose on average for " .. choiceCount .. " choices at " .. elapsed)
            maximumGuessNumerators[choiceCount] = math.max(maximumGuessNumerators[choiceCount], numerator)
        end
    end
    local breakpoints = {}
    for elapsed = 0, ANSWER_SECONDS do
        breakpoints[#breakpoints + 1] = elapsed
        CheckBlindGuess(math.max(0, elapsed - BOUNDARY_DELTA))
        CheckBlindGuess(elapsed)
        CheckBlindGuess(math.min(ANSWER_SECONDS, elapsed + BOUNDARY_DELTA))
    end
    for _, boundary in ipairs(PENALTY_BOUNDARIES) do
        local elapsed, before, after = unpack(boundary)
        breakpoints[#breakpoints + 1] = elapsed
        Same(Calculate(false, elapsed - BOUNDARY_DELTA), -before, "penalty immediately before a rounding threshold")
        Same(Calculate(false, elapsed + BOUNDARY_DELTA), -after, "penalty immediately after a rounding threshold")
        CheckBlindGuess(elapsed - BOUNDARY_DELTA)
        CheckBlindGuess(elapsed)
        CheckBlindGuess(elapsed + BOUNDARY_DELTA)
    end
    table.sort(breakpoints)
    for index = 2, #breakpoints do
        CheckBlindGuess((breakpoints[index - 1] + breakpoints[index]) / 2)
    end

    local previousCorrect, previousWrong
    for step = 0, ANSWER_SECONDS * GRID_STEPS_PER_SECOND do
        local elapsed = step / GRID_STEPS_PER_SECOND
        local correct, wrong = Calculate(true, elapsed), Calculate(false, elapsed)
        Check(correct >= 1 and correct <= 2.5, "correct answers stay within the base and maximum bonus")
        Check(wrong >= -MAX_PENALTY and wrong <= -MIN_PENALTY, "wrong answers stay within the signed penalty bounds")
        Near(correct * POINT_SCALE, Units(correct), "correct points are whole tenths")
        Near(wrong * POINT_SCALE, Units(wrong), "wrong points are whole signed tenths")
        Check(not previousCorrect or correct <= previousCorrect, "waiting never increases the correct bonus")
        Check(not previousWrong or wrong >= previousWrong, "waiting never increases the wrong-answer deduction")
        Check(
            math.abs(-wrong - RawPenalty(elapsed)) <= 0.5 / POINT_SCALE + FLOAT_EPSILON,
            "quantized penalties stay within half a tenth of the convex exponential"
        )
        CheckBlindGuess(elapsed)
        previousCorrect, previousWrong = correct, wrong
    end
    Same(maximumGuessNumerators[4], -1, "best four-choice blind expectation is minus 0.025 points")
    Same(maximumGuessNumerators[5], -7, "best five-choice blind expectation is minus 0.14 points")
    Same(maximumGuessNumerators[6], -12, "best six-choice blind expectation is minus 0.2 points")

    Same(Quiz.Scoring.Add(0, -0.5), -0.5, "a wrong first answer produces a negative total rather than a free guess")
    Same(Quiz.Scoring.Add(-0.5, -0.8), -1.3, "negative tenths accumulate")
    Same(Quiz.Scoring.Add(-1.3, 2.5), 1.2, "a correct answer can recover a negative score")
    Same(Quiz.Scoring.Add(0.5, -0.5), 0, "opposite scores cancel exactly")
    Same(Quiz.Scoring.Add(0.1 + 0.2, -0.2), 0.1, "binary floating-point noise does not change signed tenths")
    local negativeTotal, mixedTotal = 0, 0
    for iteration = 1, ADDITION_REPETITIONS do
        negativeTotal = Quiz.Scoring.Add(negativeTotal, -0.1)
        Same(negativeTotal, -iteration / POINT_SCALE, "repeated losses never drift or stop at zero")
        for _, points in ipairs({ 2.4, -1, -0.7, 0.1 }) do
            mixedTotal = Quiz.Scoring.Add(mixedTotal, points)
        end
        Same(mixedTotal, iteration * 8 / POINT_SCALE, "mixed positive and negative scores retain exact tenths")
    end
    local defaultRules = Quiz.Rules.Normalize()
    for step = 0, ANSWER_SECONDS * GRID_STEPS_PER_SECOND do
        local elapsed = step / GRID_STEPS_PER_SECOND
        for _, correct in ipairs({ false, true }) do
            Same(
                Quiz.Scoring.Calculate(correct, elapsed, ANSWER_SECONDS, defaultRules, 500),
                Quiz.Scoring.CalculateLegacy(correct, elapsed, ANSWER_SECONDS),
                "explicit default rules preserve exact historical rounding without enabled streak bonuses"
            )
        end
    end
    local minimum, maximum = Quiz.Scoring.GetBounds(defaultRules)
    Same(minimum, -1, "default minimum is the strongest authored wrong-answer deduction")
    Same(maximum, 2.5, "default maximum excludes disabled streak rewards")
    local custom = Quiz.Rules.Normalize({
        answerSeconds = 30,
        correctPoints = 2,
        speedBonusPerSecond = 0.2,
        wrongPenaltyStart = 2,
        wrongPenaltyEnd = 0.5,
        wrongPenaltyCurve = 4,
        streakBonusPerCorrect = 0.2,
        streakBonusMax = 1,
    })
    Same(Quiz.Scoring.Calculate(true, 0, 30, custom, 1), 8, "pack timing and speed reward replace global constants")
    Same(Quiz.Scoring.Calculate(true, 0.001, 30, custom, 1), 7.8, "custom speed rewards still count whole seconds")
    Same(Quiz.Scoring.Calculate(true, 30, 30, custom, 1), 2, "late correct answers retain authored base points")
    Same(Quiz.Scoring.Calculate(false, 0, 30, custom, 100), -2, "streak never offsets an incorrect-answer penalty")
    Same(Quiz.Scoring.Calculate(false, 30, 30, custom, 100), -0.5, "custom terminal penalty remains exact")
    Same(Quiz.Scoring.Calculate(false, 15, 30, custom), -0.8, "custom half-life count changes exponential decay")
    minimum, maximum = Quiz.Scoring.GetBounds(custom)
    Same(minimum, -2, "custom bounds retain negative scoring")
    Same(maximum, 9, "custom maximum includes the finite streak cap")
    for streak = 0, 100 do
        local bonus = math.min(10, math.max(0, streak - 1) * 2) / 10
        Same(Quiz.Scoring.StreakBonus(custom, streak), bonus, "streak starts on the second consecutive correct answer")
        Same(
            Quiz.Scoring.Calculate(true, 30, 30, custom, streak),
            (20 + bonus * 10) / 10,
            "streak bonus is part of finalized points"
        )
        Same(Quiz.Scoring.Calculate(false, 30, 30, custom, streak), -0.5, "wrong answers never claim a correct streak")
    end
    local disabled =
        Quiz.Rules.Normalize({ correctPoints = 0, speedBonusPerSecond = 0, wrongPenaltyStart = 0, wrongPenaltyEnd = 0 })
    Same(Quiz.Scoring.Calculate(true, 0, 15, disabled, 99), 0, "a practice quiz may disable all rewards")
    Same(Quiz.Scoring.Calculate(false, 0, 15, disabled, 99), 0, "a practice quiz may disable penalties")
    minimum, maximum = Quiz.Scoring.GetBounds(disabled)
    Same(minimum, 0, "no-scoring bounds allow zero deductions")
    Same(maximum, 0, "no-scoring bounds do not invent a reward")
    local flat = Quiz.Rules.Normalize({ speedBonusPerSecond = 0, wrongPenaltyStart = 0.7, wrongPenaltyEnd = 0.7 })
    for elapsed = 0, 15 do
        Same(Quiz.Scoring.Calculate(true, elapsed, 15, flat, 100), 1, "flat-scoring quizzes ignore answer speed")
        Same(
            Quiz.Scoring.Calculate(false, elapsed, 15, flat, 100),
            -0.7,
            "equal penalty endpoints produce a flat deduction"
        )
    end
    local largest = Quiz.Rules.Normalize({
        answerSeconds = 120,
        correctPoints = 1000,
        speedBonusPerSecond = 10,
        wrongPenaltyStart = 1000,
        streakBonusPerCorrect = 10,
        streakBonusMax = 100,
    })
    minimum, maximum = Quiz.Scoring.GetBounds(largest)
    Same(minimum, -1000, "persistence can use the global minimum authored result")
    Same(maximum, 2300, "persistence can use the global maximum authored result")
    Same(Quiz.Scoring.Calculate(true, 0, 120, largest, 100), maximum, "largest supported rules stay inside their bound")

    local loreRules = Quiz.Rules.Normalize({ streakBonusPerCorrect = 0.1, streakBonusMax = 0.5 })
    for choiceCount = 4, 6 do
        local chance = 1 / choiceCount
        local expectedStreakBonus = 0
        for previousCorrect = 1, 5 do
            expectedStreakBonus = expectedStreakBonus + 0.1 * chance ^ previousCorrect
        end
        for elapsed = 0, 15 * 1000 do
            local seconds = elapsed / 1000
            local expected = chance * (Quiz.Scoring.CalculateLegacy(true, seconds, 15) + expectedStreakBonus)
                + (1 - chance) * Quiz.Scoring.CalculateLegacy(false, seconds, 15)
            Check(expected < 0, "default lore streak rewards retain negative long-run uniform blind-guess expectation")
        end
        Same(Quiz.Scoring.Calculate(true, 0, 15, loreRules, 6), 3, "lore streak reward caps at an extra half point")
    end
    return assertions
end

local Quiz = OrbitQuiz
local POINT_SCALE = 10
local CORRECT_UNITS = 10
local WRONG_MIN_UNITS = 5
local WRONG_MAX_UNITS = 10
local PENALTY_HALF_LIVES = 2.5
local PENALTY_END_FACTOR = 2 ^ -PENALTY_HALF_LIVES
local SECOND_EPSILON = 0.0000001

local Scoring = {
    VERSION = 2,
    MIN_WRONG_POINTS = -WRONG_MAX_UNITS / POINT_SCALE,
    MAX_WRONG_POINTS = -WRONG_MIN_UNITS / POINT_SCALE,
}
Quiz.Scoring = Scoring

function Scoring.Calculate(correct, elapsed, duration)
    local remaining = math.max(0, math.min(duration, duration - elapsed))
    if not correct then
        local fraction = 1 - remaining / duration
        local decay = (2 ^ (-PENALTY_HALF_LIVES * fraction) - PENALTY_END_FACTOR) / (1 - PENALTY_END_FACTOR)
        local units = WRONG_MIN_UNITS + (WRONG_MAX_UNITS - WRONG_MIN_UNITS) * decay
        return -math.floor(units + 0.5) / POINT_SCALE
    end
    local seconds = math.floor(remaining + SECOND_EPSILON)
    return (CORRECT_UNITS + seconds) / POINT_SCALE
end

function Scoring.Add(total, points)
    return (math.floor(total * POINT_SCALE + 0.5) + math.floor(points * POINT_SCALE + 0.5)) / POINT_SCALE
end

function Scoring.BuildStandings(players)
    local standings = {}
    for guid, player in pairs(players) do
        standings[#standings + 1] = {
            guid = guid,
            name = player.name,
            score = player.score,
            correct = player.correct,
            incorrect = player.incorrect,
            answers = player.answers,
        }
    end
    table.sort(standings, function(left, right)
        if left.score ~= right.score then
            return left.score > right.score
        end
        if left.correct ~= right.correct then
            return left.correct > right.correct
        end
        if left.incorrect ~= right.incorrect then
            return left.incorrect < right.incorrect
        end
        if left.name ~= right.name then
            return left.name < right.name
        end
        return left.guid < right.guid
    end)
    return standings
end

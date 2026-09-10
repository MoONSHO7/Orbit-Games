local _, Games = ...
local Quiz = Games.Quiz

local SOUND_DIRECTORY = "Interface\\AddOns\\Orbit-Games\\Assets\\Sounds\\"
local GODLIKE_STREAK = 10
local STREAK_SOUNDS = {
    [5] = "dominating",
    [6] = "ownage",
    [7] = "rampage",
    [8] = "wicked-sick",
    [9] = "holyshit",
    [GODLIKE_STREAK] = "godlike",
}

local SoundMedia = {}
Quiz.SoundMedia = SoundMedia

function SoundMedia:GetStreakSound(streak, volume)
    local file = STREAK_SOUNDS[math.min(streak, GODLIKE_STREAK)]
    volume = volume or Quiz.SOUND_VOLUME_DEFAULT
    if not file or volume == Quiz.SOUND_VOLUME_MIN then
        return
    end
    return SOUND_DIRECTORY .. "Playback\\" .. file .. "-" .. volume .. ".ogg"
end

local _, Games = ...

Games.Quiz = Games.Quiz or {}
local Quiz = Games.Quiz

Quiz.id = "quiz"
Quiz.ANSWER_SECONDS = 15
Quiz.MIN_CHOICES = 4
Quiz.MAX_CHOICES = 6
Quiz.WIDGET_SCALE_MIN = 50
Quiz.WIDGET_SCALE_MAX = 200
Quiz.WIDGET_SCALE_STEP = 5
Quiz.WIDGET_SCALE_DEFAULT = 100
Quiz.SOUND_VOLUME_MIN = 0
Quiz.SOUND_VOLUME_MAX = 100
Quiz.SOUND_VOLUME_STEP = 10
Quiz.SOUND_VOLUME_DEFAULT = 100
Quiz.DIFFICULTIES = { easy = true, medium = true, hard = true, very_hard = true }

local _, Quiz = ...
local L = Quiz.L
local MIN_HEIGHT = 48
local MIN_NAME_HEIGHT = 16
local MIN_CAPTION_HEIGHT = 14
local NAME_LINES = 2
local PADDING_PIXELS = 6
local LINE_GAP_PIXELS = 2
local SHADOW_PIXELS = 2
local BURST_DROP_PIXELS = 4
local BURST_SCALE = 0.8
local SWEEP_WIDTH = 48
local TOAST_SECONDS = 3.2
local SOUND_POLL_SECONDS = 0.05
local FADE_IN_SECONDS = 0.18
local FADE_OUT_SECONDS = 0.5
local FLARE_SECONDS = 0.9
local SWEEP_SECONDS = 1.1
local CAPTION_PULSE_STREAK = 10
local CAPTION_PULSE_SCALE = 1.2
local QUEUE_LIMIT = 32
local SOUND_CHANNEL = "SFX"
local MIN_STREAK = 5
local MAX_TIER = 10
local BURST_ATLAS = "ArtifactsFX-StarBurst"
local SHINE_MASK_ATLAS = "ui-achievement-alert-glow-shine"
local MASK_WRAP = "CLAMPTOBLACKADDITIVE"
local START_ACCENT = { 1, 0.82, 0.3 }
local END_ACCENT = { 1, 0.27, 0.1 }
local FLARE_ALPHA = 0.65
local FLARE_REST_ALPHA = 0.35
local SWEEP_ALPHA = 0.8

Quiz.StreakToasts = {}
local Toasts = Quiz.StreakToasts

local function Pixel(region, count)
    return PixelUtil.GetNearestPixelSize(0, region:GetEffectiveScale(), count)
end

local function CeilPixel(region, value)
    local result = PixelUtil.GetNearestPixelSize(value, region:GetEffectiveScale())
    return result < value and result + Pixel(region, 1) or result
end

local function LineHeights(self)
    local _, nameHeight = self.nameText:GetFont()
    local _, captionHeight = self.captionText:GetFont()
    return math.max(MIN_NAME_HEIGHT, nameHeight + Pixel(self.frame, SHADOW_PIXELS)) * NAME_LINES,
        math.max(MIN_CAPTION_HEIGHT, captionHeight + Pixel(self.frame, SHADOW_PIXELS))
end

local function CreateFade(parent, region, duration, fadeDuration, finalAlpha)
    local group = parent:CreateAnimationGroup()
    group:SetLooping("NONE")
    group:SetToFinalAlpha(true)
    local fadeIn = group:CreateAnimation("Alpha")
    fadeIn:SetTarget(region)
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(FADE_IN_SECONDS)
    local fadeOut = group:CreateAnimation("Alpha")
    fadeOut:SetTarget(region)
    fadeOut:SetOrder(1)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(finalAlpha or 0)
    fadeOut:SetStartDelay(duration - fadeDuration)
    fadeOut:SetDuration(fadeDuration)
    fadeOut:SetSmoothing("IN")
    return group
end

local function CreateCaptionPulse(parent, caption)
    local group = parent:CreateAnimationGroup()
    group:SetLooping("NONE")
    for order, step in ipairs({ { 1, CAPTION_PULSE_SCALE, "OUT" }, { CAPTION_PULSE_SCALE, 1, "IN" } }) do
        local animation = group:CreateAnimation("Scale")
        animation:SetTarget(caption)
        animation:SetOrigin("TOP", 0, 0)
        animation:SetOrder(order)
        animation:SetScaleFrom(step[1], step[1])
        animation:SetScaleTo(step[2], step[2])
        animation:SetDuration(SWEEP_SECONDS / 2)
        animation:SetSmoothing(step[3])
    end
    return group
end

local function StopSoundHandle(self)
    if self.soundHandle then
        StopSound(self.soundHandle)
        self.soundHandle = nil
    end
end

local function FinishCurrent(self)
    if self.soundHandle and C_Sound.IsPlaying(self.soundHandle) then
        return false
    end
    self.frame:SetScript("OnUpdate", nil)
    self.soundHandle, self.active = nil, nil
    self:ShowNext()
    return true
end

local function TakeQueued(self)
    if self.queueCount == 0 then
        return
    end
    local event = self.queue[self.queueHead]
    self.queue[self.queueHead] = nil
    self.queueHead = self.queueHead % QUEUE_LIMIT + 1
    self.queueCount = self.queueCount - 1
    self.queuedNames[event.key] = nil
    return event
end

function Toasts:Create(parent, onDrained)
    if self.frame then
        return self
    end
    self.queue, self.queuedNames = {}, {}
    self.volume = Quiz.Store:GetSoundVolume()
    self.onDrained = onDrained
    self.queueHead, self.queueCount = 1, 0
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:EnableMouse(false)
    self.frame:SetClipsChildren(false)
    self.glow = self.frame:CreateTexture(nil, "ARTWORK")
    self.glow:SetAtlas(BURST_ATLAS)
    self.glow:SetBlendMode("ADD")
    self.sweep = self.frame:CreateTexture(nil, "ARTWORK")
    self.sweep:SetAtlas(BURST_ATLAS)
    self.sweep:SetBlendMode("ADD")
    self.sweep:SetAllPoints(self.glow)
    self.sweepMask = self.frame:CreateMaskTexture(nil, "ARTWORK")
    self.sweepMask:SetAtlas(SHINE_MASK_ATLAS, false, "LINEAR", true, MASK_WRAP, MASK_WRAP)
    self.sweep:AddMaskTexture(self.sweepMask)
    self.nameText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.nameText:SetWordWrap(true)
    self.nameText:SetNonSpaceWrap(true)
    self.nameText:SetMaxLines(NAME_LINES)
    self.captionText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.captionText:SetWordWrap(false)
    self.captionText:SetNonSpaceWrap(false)
    self.captionText:SetMaxLines(1)
    self.animation = CreateFade(self.frame, self.frame, TOAST_SECONDS, FADE_OUT_SECONDS)
    self.flareAnimation =
        CreateFade(self.frame, self.glow, FLARE_SECONDS, FLARE_SECONDS - FADE_IN_SECONDS, FLARE_REST_ALPHA)
    self.sweepAnimation = CreateFade(self.frame, self.sweep, SWEEP_SECONDS, FADE_OUT_SECONDS)
    self.sweepMove = self.sweepAnimation:CreateAnimation("Translation")
    self.sweepMove:SetTarget(self.sweepMask)
    self.sweepMove:SetOrder(1)
    self.sweepMove:SetDuration(SWEEP_SECONDS)
    self.sweepMove:SetSmoothing("OUT")
    self.captionAnimation = CreateCaptionPulse(self.frame, self.captionText)
    self.sweepAnimation:SetScript("OnFinished", function()
        self.sweep:Hide()
    end)
    self.waitForSound = function(_, elapsed)
        self.soundPollElapsed = self.soundPollElapsed + elapsed
        if self.soundPollElapsed < SOUND_POLL_SECONDS then
            return
        end
        self.soundPollElapsed = 0
        local ok, err = pcall(FinishCurrent, self)
        if not ok then
            self:Clear()
            geterrorhandler()(err)
        end
    end
    self.animation:SetScript("OnFinished", function()
        self.frame:SetAlpha(0)
        self.soundPollElapsed = 0
        if not FinishCurrent(self) then
            self.frame:SetScript("OnUpdate", self.waitForSound)
        end
    end)
    self.frame:Hide()
    return self
end

function Toasts:SetVolume(volume)
    if self.volume == volume then
        return
    end
    self.volume = volume
    if volume == Quiz.SOUND_VOLUME_MIN then
        StopSoundHandle(self)
    end
end

function Toasts:ApplyStyle(fontObjects)
    self.nameText:SetFontObject(fontObjects.answer)
    self.captionText:SetFontObject(fontObjects.winner)
    self.nameText:SetTextColor(1, 1, 1)
    for _, label in ipairs({ self.nameText, self.captionText }) do
        local shadow = Pixel(label, SHADOW_PIXELS)
        label:SetShadowColor(0, 0, 0, 1)
        label:SetShadowOffset(-shadow, -shadow)
        label:SetJustifyH("CENTER")
    end
    self.nameText:SetJustifyV("BOTTOM")
    self.captionText:SetJustifyV("TOP")
    self.layoutScale = nil
end

function Toasts:GetPreferredHeight()
    local nameHeight, captionHeight = LineHeights(self)
    return CeilPixel(
        self.frame,
        math.max(MIN_HEIGHT, nameHeight + captionHeight + Pixel(self.frame, PADDING_PIXELS * 2 + LINE_GAP_PIXELS))
    )
end

function Toasts:Layout(width, height)
    local scale, pixelFactor = self.frame:GetEffectiveScale(), PixelUtil.GetPixelToUIUnitFactor()
    if
        self.layoutWidth == width
        and self.layoutHeight == height
        and self.layoutScale == scale
        and self.layoutPixelFactor == pixelFactor
    then
        return
    end
    self.layoutWidth, self.layoutHeight, self.layoutScale, self.layoutPixelFactor = width, height, scale, pixelFactor
    PixelUtil.SetSize(self.frame, math.max(0, width), math.max(0, height))
    width, height = self.frame:GetWidth(), self.frame:GetHeight()
    local inset =
        PixelUtil.GetNearestPixelSize(math.min(Pixel(self.frame, PADDING_PIXELS), width / 4, height / 4), scale)
    local gap = PixelUtil.GetNearestPixelSize(math.min(Pixel(self.frame, LINE_GAP_PIXELS), height / 8), scale)
    local textWidth, availableHeight = math.max(0, width - inset * 2), math.max(0, height - inset * 2 - gap)
    local nameHeight, captionHeight = LineHeights(self)
    local nameFraction = nameHeight / (nameHeight + captionHeight)
    nameHeight = PixelUtil.GetNearestPixelSize(availableHeight * nameFraction, scale)
    captionHeight = math.max(0, availableHeight - nameHeight)
    PixelUtil.SetPoint(self.nameText, "TOPLEFT", self.frame, "TOPLEFT", inset, -inset)
    PixelUtil.SetSize(self.nameText, textWidth, nameHeight)
    PixelUtil.SetPoint(self.captionText, "TOPLEFT", self.nameText, "BOTTOMLEFT", 0, -gap)
    PixelUtil.SetSize(self.captionText, textWidth, captionHeight)
    local burstInsetX = PixelUtil.GetNearestPixelSize(width * (1 - BURST_SCALE) / 2, scale)
    local burstInsetY = PixelUtil.GetNearestPixelSize(height * (1 - BURST_SCALE) / 2, scale)
    local burstWidth, burstHeight = math.max(0, width - burstInsetX * 2), math.max(0, height - burstInsetY * 2)
    PixelUtil.SetPoint(
        self.glow,
        "TOPLEFT",
        self.frame,
        "TOPLEFT",
        burstInsetX,
        -Pixel(self.frame, BURST_DROP_PIXELS) - burstInsetY
    )
    PixelUtil.SetSize(self.glow, burstWidth, burstHeight)
    PixelUtil.SetSize(self.sweepMask, math.min(SWEEP_WIDTH, burstWidth / 4), burstHeight)
    PixelUtil.SetPoint(self.sweepMask, "TOPLEFT", self.glow, "TOPLEFT", -self.sweepMask:GetWidth(), 0)
    self.sweepMove:SetOffset(PixelUtil.GetNearestPixelSize(burstWidth + self.sweepMask:GetWidth(), scale), 0)
end

function Toasts:ShowNext()
    if self.active then
        return
    end
    local event = TakeQueued(self)
    if not event then
        if self.frame:IsShown() then
            self.frame:Hide()
        end
        if self.onDrained then
            self.onDrained()
        end
        return
    end
    self.active = event
    local tier = math.min(event.streak, MAX_TIER)
    local intensity = (tier - MIN_STREAK) / (MAX_TIER - MIN_STREAK)
    local green = START_ACCENT[2] + intensity * (END_ACCENT[2] - START_ACCENT[2])
    local blue = START_ACCENT[3] + intensity * (END_ACCENT[3] - START_ACCENT[3])
    self.nameText:SetText(event.name)
    self.captionText:SetText(L.W_STREAK_TOAST_F:format(event.streak))
    self.captionText:SetTextColor(1, green, blue)
    self.glow:SetVertexColor(1, green, blue, FLARE_ALPHA)
    self.sweep:SetVertexColor(1, 1, 1, SWEEP_ALPHA)
    self.frame:SetAlpha(1)
    self.frame:Show()
    self.glow:SetAlpha(1)
    self.glow:Show()
    self.sweep:SetAlpha(1)
    self.sweep:Show()
    self.animation:Play()
    self.flareAnimation:Play()
    self.sweepAnimation:Play()
    if self.captionAnimation:IsPlaying() then
        self.captionAnimation:Stop()
    end
    if event.streak >= CAPTION_PULSE_STREAK then
        self.captionAnimation:Play()
    end
    local path = Quiz.Media:GetStreakSound(event.streak, self.volume)
    if path then
        -- An unavailable or malformed optional sound asset must not interrupt the visual queue.
        local ok, played, handle = pcall(PlaySoundFile, path, SOUND_CHANNEL)
        self.soundHandle = ok and played and handle or nil
    end
end

function Toasts:Enqueue(events)
    for _, event in ipairs(events) do
        local key = event.name:lower()
        local queued = self.queuedNames[key]
        if queued then
            queued.name, queued.streak = event.name, event.streak
        else
            if self.queueCount == QUEUE_LIMIT then
                TakeQueued(self)
            end
            queued = { key = key, name = event.name, streak = event.streak }
            local index = (self.queueHead + self.queueCount - 1) % QUEUE_LIMIT + 1
            self.queue[index] = queued
            self.queuedNames[key] = queued
            self.queueCount = self.queueCount + 1
        end
    end
    self:ShowNext()
end

function Toasts:Clear()
    if not self.frame then
        return
    end
    self.frame:SetScript("OnUpdate", nil)
    self.soundPollElapsed = 0
    for _, animation in ipairs({ self.animation, self.flareAnimation, self.sweepAnimation, self.captionAnimation }) do
        if animation:IsPlaying() then
            animation:Stop()
        end
    end
    StopSoundHandle(self)
    wipe(self.queue)
    wipe(self.queuedNames)
    self.queueHead, self.queueCount, self.active = 1, 0, nil
    if self.frame:IsShown() then
        self.frame:Hide()
    end
end

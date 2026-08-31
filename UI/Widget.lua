local _, Quiz = ...
local L = Quiz.L
local Controls = Quiz.Controls
local WIDTH = 380
local ANCHOR_WIDTH = 96
local ANCHOR_HEIGHT = 20
local SCREEN_MARGIN = 12
local BODY_SCREEN_FRACTION = 0.58
local MIN_TEXT_HEIGHT = 16
local GAP = 6
local QUESTION_TIMER_GAP_PIXELS = 2
local TIMER_ANSWER_GAP = 8
local TIMER_PIXELS = 2
local TIMER_GRADIENT_SHADE = 0.65
local TEXT_SHADOW_PIXELS = 2
local MIN_FONT_SIZE = 8
local FONT_SIZE_OFFSETS = { question = 4, answer = 0, pack = -4, winner = -2 }
local PACK_GAP_PIXELS = 4
local CHOICE_PRESS_PIXELS = 1
local CHOICE_PRESS_ALPHA = 0.8
local PERCENT = 100
local MIN_SCORE_WIDTH = 44
local SCORE_GAP_PIXELS = 8
local SCORE_RISE_PIXELS = 12
local SCORE_ANIMATION_SECONDS = 2.2
local SCORE_FADE_DELAY = 1.4
local WINNER_GAP_PIXELS = 6
local WINNER_RISE_PIXELS = 6
local WINNER_MAX_LINES = 2
local TOAST_GAP_PIXELS = 6
local TOAST_ACTIVE_STATES = { ready = true, posting = true, open = true, results = true }
local CHOICE_COUNT = Quiz.MAX_CHOICES
local EDIT_OUTSET = 8
local DRAG_CLICK_GUARD = 0.2
local EDIT_COLOR = { 0.7, 0.6, 1, 1 }
local PREVIEW_CHOICES = { L.W_PREVIEW_A, L.W_PREVIEW_B, L.W_PREVIEW_C, L.W_PREVIEW_D }
local COLORS = {
    text = { 1, 1, 1, 1 },
    shadow = { 0, 0, 0, 1 },
    hover = { 1, 0.94, 0.55, 1 },
    selected = { 1, 0.82, 0, 1 },
    correct = { 0.4, 1, 0.5, 1 },
    incorrect = { 0.85, 0.4, 0.4, 1 },
    muted = { 0.6, 0.6, 0.6, 1 },
    timeout = { 1, 0.16, 0.08, 1 },
    track = { 1, 1, 1, 0.15 },
}

Quiz.Widget = {}
local Widget = Quiz.Widget

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function IsActive()
    return Quiz.Session.hostSession ~= nil or Quiz.Session.client ~= nil
end

local function ApplyTextShadow(label)
    local offset = PixelUtil.GetNearestPixelSize(0, label:GetEffectiveScale(), TEXT_SHADOW_PIXELS)
    label:SetShadowColor(unpack(COLORS.shadow))
    label:SetShadowOffset(-offset, -offset)
end

local function BindFont(label, font)
    local red, green, blue, alpha = label:GetTextColor()
    local horizontal, vertical = label:GetJustifyH(), label:GetJustifyV()
    label:SetFontObject(font)
    label:SetTextColor(red, green, blue, alpha)
    label:SetJustifyH(horizontal)
    label:SetJustifyV(vertical)
end

local function FitWrappedText(label, minimum)
    local requiredHeight = math.max(minimum or MIN_TEXT_HEIGHT, label:GetStringHeight())
    local scale = label:GetEffectiveScale()
    local height = PixelUtil.GetNearestPixelSize(requiredHeight, scale)
    if height < requiredHeight then
        height = height + PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    label:SetHeight(height)
end

local function GetScoreWidth(label, rules)
    local minimum, maximum = Quiz.Scoring.GetBounds(rules)
    local requiredWidth = 0
    for _, points in ipairs({ minimum, maximum }) do
        local pattern = L.W_SCORE_DELTA_F:format(points)
        for digit = 0, 9 do
            local text = pattern:gsub("%d", tostring(digit))
            requiredWidth = math.max(requiredWidth, label:GetUnboundedStringWidthForText(text))
        end
    end
    local scale = label:GetEffectiveScale()
    requiredWidth =
        math.max(MIN_SCORE_WIDTH, requiredWidth + PixelUtil.GetNearestPixelSize(0, scale, TEXT_SHADOW_PIXELS))
    local width = PixelUtil.GetNearestPixelSize(requiredWidth, scale)
    if width < requiredWidth then
        width = width + PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    return width
end

local function SetChoicePressed(choice, pressed)
    pressed = pressed == true
    if choice.pressed == pressed then
        return
    end
    choice.pressed = pressed
    local offset = pressed and PixelUtil.GetNearestPixelSize(0, choice.Text:GetEffectiveScale(), CHOICE_PRESS_PIXELS)
        or 0
    PixelUtil.SetPoint(choice.Text, "TOPLEFT", choice, "TOPLEFT", offset, -offset)
    choice.Text:SetAlpha(pressed and CHOICE_PRESS_ALPHA or 1)
end

local function PaintChoice(choice)
    local color = COLORS[choice.tone]
        or choice.selected and COLORS.selected
        or choice.controlEnabled and choice.hovered and COLORS.hover
        or (choice.controlEnabled or choice.preview) and COLORS.text
        or COLORS.muted
    if choice.paintColor ~= color then
        choice.Text:SetTextColor(unpack(color))
        choice.paintColor = color
    end
end

local function AnimateTimer()
    local ok, failure = pcall(Widget.UpdateTimer, Widget)
    if not ok then
        Widget.timerFailed = true
        Widget.timer:SetScript("OnUpdate", nil)
        geterrorhandler()(failure)
    end
end

local function CreateFeedbackAnimation(label)
    local animation = label:CreateAnimationGroup()
    animation:SetLooping("NONE")
    local rise = animation:CreateAnimation("Translation")
    rise:SetOrder(1)
    rise:SetDuration(SCORE_ANIMATION_SECONDS)
    rise:SetSmoothing("OUT")
    local fade = animation:CreateAnimation("Alpha")
    fade:SetOrder(1)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(SCORE_FADE_DELAY)
    fade:SetDuration(SCORE_ANIMATION_SECONDS - SCORE_FADE_DELAY)
    fade:SetSmoothing("IN")
    local function HideText()
        label:Hide()
    end
    animation:SetScript("OnFinished", HideText)
    animation:SetScript("OnStop", HideText)
    return animation, rise, fade
end

function Widget:ResolveLayout(x, y, screenWidth, screenHeight, width, height)
    local horizontal = x < 1 / 3 and "LEFT" or x > 2 / 3 and "RIGHT" or "CENTER"
    local vertical = y >= 1 / 2 and "TOP" or "BOTTOM"
    local anchorX, anchorY = x * screenWidth, y * screenHeight
    local left = horizontal == "LEFT" and anchorX - ANCHOR_WIDTH / 2
        or horizontal == "RIGHT" and anchorX + ANCHOR_WIDTH / 2 - width
        or anchorX - width / 2
    local bottom = vertical == "TOP" and anchorY + ANCHOR_HEIGHT / 2 - height or anchorY - ANCHOR_HEIGHT / 2
    local marginX = math.min(SCREEN_MARGIN, math.max(0, (screenWidth - width) / 2))
    local marginY = math.min(SCREEN_MARGIN, math.max(0, (screenHeight - height) / 2))
    local clampedLeft = Clamp(left, marginX, screenWidth - width - marginX)
    local clampedBottom = Clamp(bottom, marginY, screenHeight - height - marginY)
    anchorX, anchorY = anchorX + clampedLeft - left, anchorY + clampedBottom - bottom
    return {
        horizontal = horizontal,
        vertical = vertical,
        point = vertical .. (horizontal == "CENTER" and "" or horizontal),
        x = anchorX / screenWidth,
        y = anchorY / screenHeight,
        left = clampedLeft,
        bottom = clampedBottom,
        width = width,
        height = height,
    }
end

function Widget:ApplyPosition()
    if self.dragging then
        return
    end
    local screenWidth, screenHeight = self:GetScreenSize()
    if not screenWidth or not screenHeight or screenWidth <= 0 or screenHeight <= 0 then
        return
    end
    local scale = self.frame:GetEffectiveScale()
    self.frame:SetSize(
        PixelUtil.GetNearestPixelSize(ANCHOR_WIDTH / 2, scale, 1) * 2,
        PixelUtil.GetNearestPixelSize(ANCHOR_HEIGHT / 2, scale, 1) * 2
    )
    local layout = self:ResolveLayout(
        self.position.x,
        self.position.y,
        screenWidth,
        screenHeight,
        self.content:GetWidth(),
        self.content:GetHeight()
    )
    self.layout = layout
    self.frame:ClearAllPoints()
    PixelUtil.SetPoint(self.frame, "CENTER", UIParent, "BOTTOMLEFT", layout.x * screenWidth, layout.y * screenHeight)
    local horizontalOffset = layout.horizontal == "LEFT" and 0
        or layout.horizontal == "RIGHT" and self.frame:GetWidth() - self.content:GetWidth()
        or (self.frame:GetWidth() - self.content:GetWidth()) / 2
    local verticalOffset = layout.vertical == "TOP" and 0 or self.content:GetHeight() - self.frame:GetHeight()
    self.content:ClearAllPoints()
    -- Even-sized anchors and snapped top-left offsets keep thin art off half-pixel boundaries.
    PixelUtil.SetPoint(self.content, "TOPLEFT", self.frame, "TOPLEFT", horizontalOffset, verticalOffset)
    self.prompt:SetJustifyH(layout.horizontal)
    self.packText:SetJustifyH(layout.horizontal)
end

function Widget:ResetPressedChoices()
    for _, choice in ipairs(self.choices) do
        SetChoicePressed(choice, false)
    end
end

function Widget:StartDrag()
    if not self.editing then
        return
    end
    self:StopScoreAnimation()
    self:StopWinnerAnimation()
    self.streakPreview = nil
    Quiz.StreakToasts:Clear()
    self:ResetPressedChoices()
    self.dragging = true
    self.frame:StartMoving()
end

function Widget:StopDrag()
    if not self.dragging then
        return
    end
    self.frame:StopMovingOrSizing()
    self.dragging = false
    self.suppressClickUntil = GetTime() + DRAG_CLICK_GUARD
    local left, bottom, width, height = self.frame:GetScaledRect()
    local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
    if
        left
        and bottom
        and width
        and height
        and screenLeft
        and screenBottom
        and screenWidth
        and screenHeight
        and screenWidth > 0
        and screenHeight > 0
    then
        self.position = {
            x = Clamp((left + width / 2 - screenLeft) / screenWidth, 0, 1),
            y = Clamp((bottom + height / 2 - screenBottom) / screenHeight, 0, 1),
        }
    end
    self:ApplyPosition()
    if self.layout then
        self.position = { x = self.layout.x, y = self.layout.y }
        Quiz.Store:SaveWidgetPosition(self.position.x, self.position.y)
    end
end

local function BindDrag(region)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function()
        Widget:StartDrag()
    end)
    region:SetScript("OnDragStop", function()
        Widget:StopDrag()
    end)
end

function Widget:Create()
    if self.frame then
        return
    end
    self.position = Quiz.Store:GetWidgetPosition()
    self.renderedChoices = {}
    self.frame = CreateFrame("Frame", "OrbitQuizWidgetFrame", UIParent)
    PixelUtil.SetSize(self.frame, ANCHOR_WIDTH, ANCHOR_HEIGHT)
    self.frame:SetMovable(false)
    self.content = CreateFrame("Frame", nil, self.frame)
    PixelUtil.SetSize(self.content, WIDTH, ANCHOR_HEIGHT)
    self.content:EnableMouse(false)
    BindDrag(self.content)
    self.fontObjects = {
        question = CreateFont("OrbitQuizWidgetQuestionFont"),
        answer = CreateFont("OrbitQuizWidgetAnswerFont"),
        pack = CreateFont("OrbitQuizWidgetPackFont"),
        winner = CreateFont("OrbitQuizWidgetWinnerFont"),
    }
    self.fontProbe = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.fontProbe:Hide()
    self.questionScroll, self.questionContent = Controls:Scroll(
        self.content,
        WIDTH,
        ANCHOR_HEIGHT,
        { rightOffset = 0, rightOffsetPixels = SCORE_GAP_PIXELS / 2 }
    )
    self.questionScroll:EnableMouse(false)
    BindDrag(self.questionScroll)
    self.packText = Controls:Label(self.questionContent, "", "GameFontHighlight")
    self.packText:SetMaxLines(0)
    self.packText:SetTextColor(unpack(COLORS.muted))
    self.prompt = Controls:Label(self.questionContent, "", "GameFontHighlight")
    self.prompt:SetMaxLines(0)
    self.scoreText = Controls:Label(self.content, "", "GameFontHighlight")
    self.scoreText:SetJustifyH("RIGHT")
    self.scoreText:SetWordWrap(false)
    self.scoreText:SetNonSpaceWrap(false)
    self.scoreText:SetMaxLines(1)
    self.scoreText:Hide()
    self.scoreAnimation, self.scoreRise, self.scoreFade = CreateFeedbackAnimation(self.scoreText)
    self.winnerText = Controls:Label(self.content, "", "GameFontHighlight")
    self.winnerText:SetMaxLines(WINNER_MAX_LINES)
    self.winnerText:SetTextColor(unpack(COLORS.correct))
    self.winnerText:Hide()
    self.winnerAnimation, self.winnerRise, self.winnerFade = CreateFeedbackAnimation(self.winnerText)
    Quiz.StreakToasts:Create(self.content, function()
        if self.streakPreview then
            self.streakPreview = nil
            self:Refresh()
        end
    end)
    self.timer = CreateFrame("StatusBar", nil, self.questionContent)
    self.timer:EnableMouse(false)
    self.timerDuration = Quiz.ANSWER_SECONDS
    self.timer:SetMinMaxValues(0, self.timerDuration)
    self.timer.Fill = self.timer:CreateTexture(nil, "ARTWORK")
    self.timer.Fill:SetColorTexture(unpack(COLORS.text))
    self.timer:SetStatusBarTexture(self.timer.Fill)
    self.timer:SetStatusBarColor(unpack(COLORS.text))
    self.timer.startColor = CreateColor(unpack(COLORS.selected))
    self.timer.endColor = CreateColor(unpack(COLORS.selected))
    self.timer.Track = self.timer:CreateTexture(nil, "BACKGROUND")
    self.timer.Track:SetAllPoints(self.timer)
    self.timer.Track:SetColorTexture(unpack(COLORS.track))
    self.choices = {}
    for index = 1, CHOICE_COUNT do
        local answerIndex = index
        local choice = CreateFrame("Button", nil, self.questionContent)
        choice.Text = Controls:Label(choice, "", "GameFontHighlight")
        choice.Text:SetMaxLines(0)
        choice.pressed = false
        choice:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and choice.controlEnabled and not self.dragging then
                SetChoicePressed(choice, true)
            end
        end)
        choice:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                SetChoicePressed(choice, false)
            end
        end)
        choice:SetScript("OnClick", function()
            SetChoicePressed(choice, false)
            self:Submit(answerIndex)
        end)
        choice:SetScript("OnEnter", function()
            choice.hovered = choice.controlEnabled
            PaintChoice(choice)
        end)
        choice:SetScript("OnLeave", function()
            choice.hovered = false
            SetChoicePressed(choice, false)
            PaintChoice(choice)
        end)
        choice:SetScript("OnHide", function()
            choice.hovered = false
            SetChoicePressed(choice, false)
        end)
        choice:SetScript("OnDisable", function()
            choice.hovered = false
            SetChoicePressed(choice, false)
        end)
        BindDrag(choice)
        self.choices[index] = choice
    end
    self.editOutline = CreateFrame("Frame", nil, self.content)
    self:RefreshEditOutline()
    self.editOutline:EnableMouse(false)
    self.editOutline:Hide()
    self.frame:SetScript("OnHide", function()
        self.timer:SetScript("OnUpdate", nil)
        self:StopScoreAnimation()
        self:StopWinnerAnimation()
        self.streakPreview = nil
        Quiz.StreakToasts:Clear()
        self:ResetPressedChoices()
        for _, choice in ipairs(self.choices) do
            choice.hovered = false
        end
    end)
    self.frame:Hide()
    self:ApplySettings()
end

function Widget:SetEditing(editing)
    self:Create()
    if not editing then
        self:StopDrag()
        if self.editing and self.streakPreview then
            self.streakPreview = nil
            Quiz.StreakToasts:Clear()
        end
    end
    self.editing = editing == true
    self.frame:SetMovable(self.editing)
    self.content:EnableMouse(self.editing)
    self.questionScroll:EnableMouse(self.editing)
    self.editOutline:SetShown(self.editing)
    self:Refresh()
end

function Widget:RefreshTextShadows()
    local offset = PixelUtil.GetNearestPixelSize(0, self.frame:GetEffectiveScale(), TEXT_SHADOW_PIXELS)
    for _, font in pairs(self.fontObjects) do
        font:SetShadowColor(unpack(COLORS.shadow))
        font:SetShadowOffset(-offset, -offset)
    end
    ApplyTextShadow(self.packText)
    ApplyTextShadow(self.prompt)
    ApplyTextShadow(self.scoreText)
    ApplyTextShadow(self.winnerText)
    Quiz.StreakToasts:ApplyStyle(self.fontObjects)
    for _, choice in ipairs(self.choices) do
        ApplyTextShadow(choice.Text)
    end
end

function Widget:ApplyFonts(path)
    local nativePath, height, flags = GameFontHighlight:GetFont()
    local applied = true
    if path then
        -- Font:SetFont has no success return; probe an external asset without inlining fonts on rendered labels.
        local ok, result = pcall(self.fontProbe.SetFont, self.fontProbe, path, height, flags)
        applied = ok and result == true
    end
    local resolvedPath = applied and path or nativePath
    for role, font in pairs(self.fontObjects) do
        font:CopyFontObject(GameFontHighlight)
        font:SetFont(resolvedPath or nativePath, math.max(MIN_FONT_SIZE, height + FONT_SIZE_OFFSETS[role]), flags)
    end
    BindFont(self.packText, self.fontObjects.pack)
    BindFont(self.prompt, self.fontObjects.question)
    BindFont(self.scoreText, self.fontObjects.answer)
    BindFont(self.winnerText, self.fontObjects.winner)
    for _, choice in ipairs(self.choices) do
        BindFont(choice.Text, self.fontObjects.answer)
    end
    self.fontsApplied, self.fontPath = applied, applied and path or nil
end

function Widget:RefreshEditOutline()
    PixelUtil.SetPoint(self.editOutline, "TOPLEFT", self.content, "TOPLEFT", -EDIT_OUTSET, EDIT_OUTSET)
    PixelUtil.SetPoint(self.editOutline, "BOTTOMRIGHT", self.content, "BOTTOMRIGHT", EDIT_OUTSET, -EDIT_OUTSET)
    Controls:Outline(self.editOutline, EDIT_COLOR)
end

function Widget:GetScreenSize()
    local scale = self.frame:GetScale()
    -- Anchors and bounds use widget-local units, while UIParent reports unscaled parent units.
    return UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
end

function Widget:ApplySettings()
    if not self.frame then
        return
    end
    local settings = Quiz.Store:GetWidgetSettings()
    local scale, path = settings.scale / PERCENT, Quiz.Media:ResolveFont(settings.font)
    local scaleChanged = self.frame:GetScale() ~= scale
    local fontChanged = not self.fontsApplied or self.fontPath ~= path
    if not scaleChanged and not fontChanged then
        return
    end
    self:StopDrag()
    self:StopScoreAnimation()
    self:StopWinnerAnimation()
    self.streakPreview = nil
    Quiz.StreakToasts:Clear()
    self:ResetPressedChoices()
    if scaleChanged then
        self.frame:SetScale(scale)
    end
    if fontChanged then
        self:ApplyFonts(path)
    end
    self.renderedWidth = nil
    self:RefreshTextShadows()
    self:RefreshEditOutline()
    self:Refresh()
end

function Widget:OnDisplayChanged()
    if not self.frame then
        return
    end
    self:StopDrag()
    self:StopScoreAnimation()
    self:StopWinnerAnimation()
    self.streakPreview = nil
    Quiz.StreakToasts:Clear()
    self:ResetPressedChoices()
    self.renderedWidth = nil
    self:RefreshTextShadows()
    self:RefreshEditOutline()
    self:Refresh()
end

function Widget:Show()
    self:Create()
    self:Refresh()
end

function Widget:SetStreakPreview(preview)
    if preview and (IsActive() or self.dragging) then
        return false
    end
    if not preview and not self.streakPreview then
        return true
    end
    self:Create()
    self.streakPreview = preview
    Quiz.StreakToasts:Clear()
    self:Refresh()
    if preview then
        if not self.frame:IsVisible() then
            self.streakPreview = nil
            self:Refresh()
            return false
        end
        Quiz.StreakToasts:Enqueue(preview.events)
    end
    return true
end

function Widget:Submit(answer)
    if self.dragging or self.suppressClickUntil and GetTime() <= self.suppressClickUntil then
        return
    end
    local ok, reason = Quiz.Session:SubmitAnswer(answer)
    self.actionError = not ok and (L.errors[reason] or reason or L.W_ACTION_FAILED) or nil
    self:Refresh()
    Quiz.UI:Refresh()
end

function Widget:RenderQuestion(view, changed)
    local screenWidth, screenHeight = self:GetScreenSize()
    local width = math.max(1, math.min(WIDTH, screenWidth - SCREEN_MARGIN * 2 - EDIT_OUTSET * 2))
    local packTitle = view.prompt and view.packTitle or nil
    changed = changed
        or self.renderedWidth ~= width
        or self.renderedPrompt ~= view.prompt
        or self.renderedPackTitle ~= packTitle
        or self.renderedRulesKey ~= view.rulesKey
    for index = 1, CHOICE_COUNT do
        if self.renderedChoices[index] ~= (view.choices and view.choices[index]) then
            changed = true
        end
    end
    if not changed then
        return
    end
    self:ResetPressedChoices()
    self.questionScroll.ScrollBar:BeginLayout()
    PixelUtil.SetWidth(self.content, width)
    local scoreGap = PixelUtil.GetNearestPixelSize(0, self.prompt:GetEffectiveScale(), SCORE_GAP_PIXELS)
    local scoreLimit = math.max(1, self.content:GetWidth() - scoreGap - MIN_TEXT_HEIGHT)
    PixelUtil.SetSize(self.scoreText, math.min(GetScoreWidth(self.scoreText, view.rules), scoreLimit), MIN_TEXT_HEIGHT)
    local bodyWidth = math.max(1, self.content:GetWidth() - self.scoreText:GetWidth() - scoreGap)
    local textInset = PixelUtil.GetNearestPixelSize(0, self.prompt:GetEffectiveScale(), TEXT_SHADOW_PIXELS)
    local pressedInset = PixelUtil.GetNearestPixelSize(0, self.prompt:GetEffectiveScale(), CHOICE_PRESS_PIXELS)
    local textWidth = math.max(1, bodyWidth - textInset - pressedInset)
    PixelUtil.SetPoint(self.questionScroll, "TOPLEFT", self.content, "TOPLEFT", 0, 0)
    PixelUtil.SetWidth(self.questionScroll, bodyWidth)
    PixelUtil.SetWidth(self.questionContent, bodyWidth)
    self.packText:SetShown(packTitle ~= nil)
    PixelUtil.SetPoint(self.packText, "TOPLEFT", self.questionContent, "TOPLEFT", textInset, 0)
    PixelUtil.SetWidth(self.packText, textWidth)
    self.packText:SetHeight(0)
    self.packText:SetText(packTitle or "")
    FitWrappedText(self.packText, 0)
    local offset = packTitle
            and self.packText:GetHeight() + PixelUtil.GetNearestPixelSize(
                0,
                self.packText:GetEffectiveScale(),
                PACK_GAP_PIXELS
            )
        or 0
    PixelUtil.SetPoint(self.prompt, "TOPLEFT", self.questionContent, "TOPLEFT", textInset, -offset)
    PixelUtil.SetPoint(self.scoreText, "TOPRIGHT", self.content, "TOPRIGHT", 0, -offset)
    PixelUtil.SetWidth(self.prompt, textWidth)
    -- Clear the old line-height cap before measuring the next question's wrapped text.
    self.prompt:SetHeight(0)
    self.prompt:SetText(view.prompt or "")
    FitWrappedText(self.prompt)
    offset = offset
        + self.prompt:GetHeight()
        + PixelUtil.GetNearestPixelSize(0, self.timer:GetEffectiveScale(), QUESTION_TIMER_GAP_PIXELS)
    PixelUtil.SetPoint(self.timer, "TOPLEFT", self.questionContent, "TOPLEFT", textInset, -offset)
    PixelUtil.SetWidth(self.timer, textWidth)
    PixelUtil.SetHeight(self.timer, 0, TIMER_PIXELS)
    self.timer:SetShown(view.prompt ~= nil)
    offset = offset + self.timer:GetHeight() + TIMER_ANSWER_GAP
    for index, choice in ipairs(self.choices) do
        local text = view.choices and view.choices[index]
        choice:SetShown(text ~= nil)
        choice:ClearAllPoints()
        choice.Text:ClearAllPoints()
        choice.Text:SetHeight(0)
        if text then
            PixelUtil.SetWidth(choice, textWidth)
            PixelUtil.SetWidth(choice.Text, textWidth)
            choice.Text:SetText(text)
            PixelUtil.SetPoint(choice.Text, "TOPLEFT", choice, "TOPLEFT", 0, 0)
            FitWrappedText(choice.Text)
            PixelUtil.SetHeight(choice, choice.Text:GetHeight())
            PixelUtil.SetPoint(choice, "TOPLEFT", self.questionContent, "TOPLEFT", textInset, -offset)
            offset = offset + choice:GetHeight() + GAP
        else
            choice.Text:SetText("")
        end
        self.renderedChoices[index] = text
    end
    offset = view.prompt and offset - GAP + textInset + pressedInset or ANCHOR_HEIGHT
    local _, winnerFontHeight = self.winnerText:GetFont()
    local footerGap =
        PixelUtil.GetNearestPixelSize(0, self.content:GetEffectiveScale(), WINNER_GAP_PIXELS + WINNER_RISE_PIXELS)
    local availableHeight = math.max(1, screenHeight - SCREEN_MARGIN * 2 - EDIT_OUTSET * 2)
    local scale = self.questionScroll:GetEffectiveScale()
    local pixel = PixelUtil.GetNearestPixelSize(0, scale, 1)
    local winnerHeight = math.max(MIN_TEXT_HEIGHT, winnerFontHeight) * WINNER_MAX_LINES
    local winnerSlot = PixelUtil.GetNearestPixelSize(footerGap + winnerHeight, scale)
    if winnerSlot < footerGap + winnerHeight then
        winnerSlot = winnerSlot + pixel
    end
    local toastGap = PixelUtil.GetNearestPixelSize(0, scale, TOAST_GAP_PIXELS)
    local preferredFooter = winnerSlot + toastGap + Quiz.StreakToasts:GetPreferredHeight()
    local footerLimit = view.prompt and math.min(preferredFooter, availableHeight / 2) or 0
    local footerHeight = PixelUtil.GetNearestPixelSize(footerLimit, scale)
    if footerHeight > footerLimit then
        footerHeight = math.max(0, footerHeight - pixel)
    end
    winnerSlot = PixelUtil.GetNearestPixelSize(winnerSlot * footerHeight / preferredFooter, scale)
    footerGap = math.min(footerGap, winnerSlot)
    toastGap = math.min(toastGap, footerHeight - winnerSlot)
    local bodyLimit = math.min(screenHeight * BODY_SCREEN_FRACTION, math.max(1, availableHeight - footerHeight))
    local bodyHeight = PixelUtil.GetNearestPixelSize(math.min(offset, bodyLimit), scale)
    if bodyHeight > bodyLimit then
        bodyHeight = bodyHeight - PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    PixelUtil.SetHeight(self.questionContent, offset)
    PixelUtil.SetHeight(self.questionScroll, bodyHeight)
    PixelUtil.SetPoint(self.winnerText, "TOPLEFT", self.content, "TOPLEFT", 0, -bodyHeight - footerGap)
    PixelUtil.SetSize(self.winnerText, self.content:GetWidth(), winnerSlot - footerGap)
    PixelUtil.SetPoint(
        Quiz.StreakToasts.frame,
        "TOPLEFT",
        self.content,
        "TOPLEFT",
        0,
        -bodyHeight - winnerSlot - toastGap
    )
    Quiz.StreakToasts:Layout(self.content:GetWidth(), footerHeight - winnerSlot - toastGap)
    PixelUtil.SetHeight(self.content, self.questionScroll:GetHeight() + footerHeight)
    self.renderedWidth, self.renderedPrompt, self.renderedPackTitle = width, view.prompt, packTitle
    self.renderedRulesKey = view.rulesKey
    self:ApplyPosition()
    self.questionScroll.ScrollBar:EndLayout()
end

function Widget:RenderTimer(remaining)
    local fraction = Clamp(remaining / self.timerDuration, 0, 1)
    local red = COLORS.timeout[1] + (COLORS.selected[1] - COLORS.timeout[1]) * fraction
    local green = COLORS.timeout[2] + (COLORS.selected[2] - COLORS.timeout[2]) * fraction
    local blue = COLORS.timeout[3] + (COLORS.selected[3] - COLORS.timeout[3]) * fraction
    self.timer:SetValue(remaining)
    self.timer.startColor:SetRGBA(
        red * TIMER_GRADIENT_SHADE,
        green * TIMER_GRADIENT_SHADE,
        blue * TIMER_GRADIENT_SHADE,
        1
    )
    self.timer.endColor:SetRGBA(red, green, blue, 1)
    self.timer.Fill:SetGradient("HORIZONTAL", self.timer.startColor, self.timer.endColor)
end

function Widget:UpdateTimer()
    local remaining = Clamp(self.timerDeadline - GetTime(), 0, self.timerDuration)
    self:RenderTimer(remaining)
    if remaining == 0 then
        self.timer:SetScript("OnUpdate", nil)
        self:Refresh()
    end
end

function Widget:StopScoreAnimation()
    if self.scoreAnimation:IsPlaying() then
        self.scoreAnimation:Stop()
    end
    if self.scoreText:IsShown() then
        self.scoreText:Hide()
    end
end

function Widget:RenderScore(view)
    if
        view.state ~= "results"
        or view.correctIndex == nil
        or view.points == nil
        or view.points == 0
        or view.suppressScoreAnimation
        or self.dragging
    then
        self:StopScoreAnimation()
        return
    end
    local hostName = view.hostName:lower()
    if
        self.scoreResultId == view.id
        and self.scoreResultSession == view.session
        and self.scoreResultHost == hostName
    then
        return
    end
    self:StopScoreAnimation()
    self.scoreResultId, self.scoreResultSession, self.scoreResultHost = view.id, view.session, hostName
    local scale = self.scoreText:GetEffectiveScale()
    local _, screenHeight = self:GetScreenSize()
    local headroom = math.max(0, screenHeight - self.scoreText:GetTop())
    local rise = math.min(headroom, PixelUtil.GetNearestPixelSize(0, scale, SCORE_RISE_PIXELS))
    rise = PixelUtil.GetNearestPixelSize(rise, scale)
    if rise > headroom then
        rise = math.max(0, rise - PixelUtil.GetNearestPixelSize(0, scale, 1))
    end
    self.scoreRise:SetOffset(0, rise)
    self.scoreText:SetText(L.W_SCORE_DELTA_F:format(view.points))
    self.scoreText:SetTextColor(unpack(view.points > 0 and COLORS.correct or COLORS.incorrect))
    self.scoreText:SetAlpha(1)
    self.scoreText:Show()
    self.scoreAnimation:Play()
end

function Widget:StopWinnerAnimation()
    if self.winnerAnimation:IsPlaying() then
        self.winnerAnimation:Stop()
    end
    if self.winnerText:IsShown() then
        self.winnerText:Hide()
    end
end

function Widget:RenderWinner(view)
    if
        view.state ~= "results"
        or view.correctIndex == nil
        or view.fastestName == nil
        or view.fastestElapsed == nil
        or view.suppressWinnerPopup
        or self.dragging
    then
        self:StopWinnerAnimation()
        return
    end
    local hostName = view.hostName:lower()
    if
        self.winnerResultId == view.id
        and self.winnerResultSession == view.session
        and self.winnerResultHost == hostName
    then
        return
    end
    self:StopWinnerAnimation()
    self.winnerResultId, self.winnerResultSession, self.winnerResultHost = view.id, view.session, hostName
    self.winnerRise:SetOffset(
        0,
        PixelUtil.GetNearestPixelSize(0, self.winnerText:GetEffectiveScale(), WINNER_RISE_PIXELS)
    )
    self.winnerText:SetText(L.W_FASTEST_F:format(view.fastestName, view.fastestElapsed))
    self.winnerText:SetAlpha(1)
    self.winnerText:Show()
    self.winnerAnimation:Play()
end

function Widget:RenderStreakToasts(view, active)
    local toasts = Quiz.StreakToasts
    local hostName = active and view.hostName and view.hostName:lower() or nil
    local session = active and view.session or nil
    if self.streakHost ~= hostName or self.streakSession ~= session then
        toasts:Clear()
        self.streakHost, self.streakSession = hostName, session
        self.streakResultId, self.streakSeen, self.streakResultSuppressed = nil, {}, nil
    end
    if self.streakPreview and not active and self.frame:IsVisible() and not self.dragging then
        return
    end
    local available = active
        and session ~= nil
        and self.frame:IsVisible()
        and TOAST_ACTIVE_STATES[view.state]
        and not self.dragging
        and not Quiz.Session.restricted
    if not available and (toasts.active or toasts.queueCount > 0) then
        toasts:Clear()
    end
    if
        not active
        or not view.id
        or view.correctIndex == nil
        or not (view.streakMilestones or view.streakReferences)
    then
        return
    end
    if self.streakResultId and view.id < self.streakResultId then
        return
    end
    if self.streakResultId ~= view.id then
        self.streakResultId, self.streakSeen, self.streakResultSuppressed = view.id, {}, nil
    end
    if not available or view.suppressStreakToasts then
        self.streakResultSuppressed = true
    end
    if view.state ~= "results" or self.streakResultSuppressed or not view.streakMilestones then
        return
    end
    local events
    for _, event in ipairs(view.streakMilestones) do
        local name = event.name:lower()
        if not self.streakSeen[name] then
            self.streakSeen[name] = true
            events = events or {}
            events[#events + 1] = event
        end
    end
    if events then
        toasts:Enqueue(events)
    end
end

function Widget:Refresh()
    local view = Quiz.Session:GetView()
    local active = IsActive()
    if active and self.streakPreview then
        self.streakPreview = nil
        Quiz.StreakToasts:Clear()
    end
    if not self.frame then
        if not active then
            return
        end
        self:Create()
    end
    local shown = active or self.editing == true or self.streakPreview ~= nil
    if self.frame:IsShown() ~= shown then
        self.frame:SetShown(shown)
    end
    if not self.frame:IsShown() then
        self:RenderStreakToasts(view, active)
        return
    end
    if not active then
        view = {
            state = "preview",
            packTitle = self.streakPreview and self.streakPreview.packTitle or L.W_PREVIEW_PACK,
            prompt = L.W_PREVIEW_QUESTION,
            choices = PREVIEW_CHOICES,
        }
    end
    local questionChanged = self.questionId ~= view.id
        or self.questionCycle ~= view.cycle
        or self.questionHost ~= view.hostName
    local changed = questionChanged or self.previousState ~= view.state
    if changed then
        self.actionError = nil
        self.timerFailed = nil
        if self.questionId ~= view.id or self.questionHost ~= view.hostName then
            self.questionScroll.ScrollBar:ScrollTo(0, true)
        end
        self.questionId, self.questionCycle, self.questionHost = view.id, view.cycle, view.hostName
    end
    self.previousState = view.state
    self:RenderQuestion(view, questionChanged)
    self:RenderScore(view)
    self:RenderWinner(view)
    self:RenderStreakToasts(view, active)
    local duration = view.duration or Quiz.ANSWER_SECONDS
    if self.timerDuration ~= duration then
        self.timerDuration = duration
        self.timer:SetMinMaxValues(0, duration)
    end
    self.timerDeadline = view.state == "open" and view.deadline or nil
    local remaining = self.timerDeadline and Clamp(self.timerDeadline - GetTime(), 0, self.timerDuration) or 0
    local canAnswer = remaining > 0 and not view.locked
    self:RenderTimer(view.state == "preview" and self.timerDuration or remaining)
    self.timer:SetScript("OnUpdate", remaining > 0 and not self.timerFailed and AnimateTimer or nil)
    local revealed = view.state == "results" and view.correctIndex ~= nil
    for index, choice in ipairs(self.choices) do
        local present = view.choices ~= nil and view.choices[index] ~= nil
        local enabled = canAnswer and present
        if choice.controlEnabled ~= enabled then
            choice:SetEnabled(enabled)
        end
        choice.controlEnabled = enabled
        choice.selected = present and (view.state == "open" or view.state == "results") and view.selected == index
        choice.tone = present and revealed and view.correctIndex == index and "correct"
            or present and revealed and view.selected == index and "incorrect"
            or nil
        choice.preview = view.state == "preview"
        if changed or not choice.controlEnabled then
            choice.hovered = false
            SetChoicePressed(choice, false)
        end
        PaintChoice(choice)
    end
end

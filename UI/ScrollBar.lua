local _, Quiz = ...

local ANIMATION_SPEED = 14
local SETTLE_PIXELS = 0.5
local GRID_EPSILON = 0.000001
local BAR_PIXELS = 2
local GRAB_WIDTH = 5
local MIN_THUMB_HEIGHT = 16
local DEFAULT_RIGHT_OFFSET = 6
local WHEEL_STEP = 60
local BAR_GRAY = 0.72
local TRACK_ALPHA = 0.12

Quiz.ScrollBar = {}
local ScrollBar = Quiz.ScrollBar

local function Clamp(value, maximum)
    return math.max(0, math.min(maximum, value))
end

function ScrollBar:Attach(scrollFrame, opts)
    if scrollFrame.QuizScrollBar then
        scrollFrame.QuizScrollBar:Refresh()
        return scrollFrame.QuizScrollBar
    end
    local rightOffset = opts and opts.rightOffset or DEFAULT_RIGHT_OFFSET
    local rightOffsetPixels = opts and opts.rightOffsetPixels or 0
    local scrollChild = scrollFrame:GetScrollChild()
    local bar = CreateFrame("Frame", nil, scrollFrame:GetParent())
    bar:Hide()
    bar:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    bar:RegisterForDrag("LeftButton")
    bar.Track = bar:CreateTexture(nil, "ARTWORK")
    bar.Track:SetColorTexture(BAR_GRAY, BAR_GRAY, BAR_GRAY, TRACK_ALPHA)
    bar.Track:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bar.Track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.Thumb = bar:CreateTexture(nil, "OVERLAY")
    bar.Thumb:SetColorTexture(BAR_GRAY, BAR_GRAY, BAR_GRAY, 1)
    bar.Animator = CreateFrame("Frame", nil, scrollFrame)
    bar.Animator:Hide()
    bar.scrollFrame = scrollFrame
    bar.layoutDepth = 0

    function bar:GetRange()
        -- Explicit content bounds keep transient native layout ranges from changing scrollbar visibility.
        local extent = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local scale = scrollFrame:GetEffectiveScale()
        local range = PixelUtil.GetNearestPixelSize(extent, scale)
        if range > extent + GRID_EPSILON then
            range = range - PixelUtil.GetNearestPixelSize(0, scale, 1)
        end
        return math.max(0, range)
    end

    local function SnapScroll(position, range)
        return Clamp(PixelUtil.GetNearestPixelSize(position, scrollFrame:GetEffectiveScale()), range)
    end

    local function SetScroll(position)
        if scrollFrame:GetVerticalScroll() ~= position then
            bar.applyingScroll = true
            scrollFrame:SetVerticalScroll(position)
            bar.applyingScroll = nil
        end
    end

    local function StopAnimation()
        if bar.Animator:GetScript("OnUpdate") then
            bar.Animator:SetScript("OnUpdate", nil)
        end
        if bar.Animator:IsShown() then
            bar.Animator:Hide()
        end
        bar.scrollTarget, bar.scrollPosition = nil, nil
    end

    local function StopDrag()
        if bar:GetScript("OnUpdate") then
            bar:SetScript("OnUpdate", nil)
        end
        bar.dragY, bar.dragPosition = nil, nil
    end

    local function Update()
        if bar.layoutDepth > 0 then
            return
        end
        local range = bar:GetRange()
        local position = SnapScroll(scrollFrame:GetVerticalScroll(), range)
        if bar.range and range < bar.range then
            StopAnimation()
            StopDrag()
        end
        bar.range = range
        if bar.scrollTarget then
            bar.scrollTarget = SnapScroll(bar.scrollTarget, range)
            bar.scrollPosition = Clamp(bar.scrollPosition, range)
        end
        SetScroll(position)
        local trackHeight = bar:GetHeight()
        local viewport = scrollFrame:GetHeight()
        if range == 0 or trackHeight <= 0 or viewport <= 0 or not scrollFrame:IsVisible() then
            StopAnimation()
            StopDrag()
            if bar:IsShown() then
                bar:Hide()
            end
            return
        end
        if not bar:IsShown() then
            bar:Show()
        end
        local scale = bar:GetEffectiveScale()
        local thumbHeight = math.max(MIN_THUMB_HEIGHT, trackHeight * viewport / (viewport + range))
        thumbHeight = math.min(trackHeight, PixelUtil.GetNearestPixelSize(thumbHeight, scale))
        local offset = PixelUtil.GetNearestPixelSize((trackHeight - thumbHeight) * position / range, scale)
        if bar.thumbHeight ~= thumbHeight then
            bar.Thumb:SetHeight(thumbHeight)
            bar.thumbHeight = thumbHeight
        end
        if bar.thumbOffset ~= offset then
            bar.Thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -offset)
            bar.thumbOffset = offset
        end
    end

    local function Animate(_, elapsed)
        local range = bar:GetRange()
        local target = SnapScroll(bar.scrollTarget, range)
        local current = Clamp(bar.scrollPosition, range)
        local difference = target - current
        local epsilon = PixelUtil.GetNearestPixelSize(0, scrollFrame:GetEffectiveScale(), 1) * SETTLE_PIXELS
        -- Integrate unsnapped motion separately so small eased steps cannot stall on the rendered pixel grid.
        bar.scrollPosition = current + difference * math.min(1, elapsed * ANIMATION_SPEED)
        local position = SnapScroll(bar.scrollPosition, range)
        if math.abs(difference) < epsilon or position == target then
            position = target
            StopAnimation()
        end
        SetScroll(position)
        Update()
    end

    function bar:ScrollTo(position, immediate)
        local range = self:GetRange()
        StopDrag()
        local target = SnapScroll(position, range)
        if immediate or not scrollFrame:IsVisible() or target == scrollFrame:GetVerticalScroll() then
            StopAnimation()
            SetScroll(target)
            Update()
            return
        end
        self.scrollTarget = target
        self.scrollPosition = self.scrollPosition or scrollFrame:GetVerticalScroll()
        self.Animator:SetScript("OnUpdate", Animate)
        if not self.Animator:IsShown() then
            self.Animator:Show()
        end
    end

    function bar:Refresh()
        if self.layoutDepth > 0 then
            return
        end
        local scale = self:GetEffectiveScale()
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        local level = scrollFrame:GetFrameLevel() + 1
        if self:GetFrameLevel() ~= level then
            self:SetFrameLevel(level)
        end
        if self.layoutScale ~= scale or self.layoutFactor ~= factor then
            StopAnimation()
            StopDrag()
            self.layoutScale, self.layoutFactor = scale, factor
        end
        local grabWidth = PixelUtil.GetNearestPixelSize(GRAB_WIDTH, scale, BAR_PIXELS)
        local height = PixelUtil.GetNearestPixelSize(math.max(0, scrollFrame:GetHeight()), scale)
        if self:GetWidth() ~= grabWidth or self:GetHeight() ~= height then
            self:SetSize(grabWidth, height)
        end
        local shift = PixelUtil.GetNearestPixelSize(rightOffset, scale)
        if rightOffsetPixels ~= 0 then
            local direction = rightOffsetPixels < 0 and -1 or 1
            shift = shift + direction * PixelUtil.GetNearestPixelSize(0, scale, math.abs(rightOffsetPixels))
        end
        if self.layoutShift ~= shift then
            self:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", shift, 0)
            self.layoutShift = shift
        end
        local width = PixelUtil.GetNearestPixelSize(0, scale, BAR_PIXELS)
        if self.Track:GetWidth() ~= width then
            self.Track:SetWidth(width)
            self.Thumb:SetWidth(width)
        end
        Update()
    end

    function bar:BeginLayout()
        if self.layoutDepth == 0 then
            StopAnimation()
            StopDrag()
        end
        self.layoutDepth = self.layoutDepth + 1
    end

    function bar:EndLayout()
        if self.layoutDepth == 1 then
            scrollFrame:UpdateScrollChildRect()
        end
        self.layoutDepth = self.layoutDepth - 1
        if self.layoutDepth == 0 then
            self:Refresh()
        end
    end

    local function OnWheel(_, delta)
        local current = scrollFrame:GetVerticalScroll()
        local from = bar.scrollTarget or current
        if (from - current) * delta > 0 then
            from = current
        end
        bar:ScrollTo(from - delta * WHEEL_STEP)
    end

    local function DragStep()
        local range = bar:GetRange()
        local travel = bar:GetHeight() - bar.Thumb:GetHeight()
        if range <= 0 or travel <= 0 then
            StopDrag()
            return
        end
        local _, cursorY = GetCursorPosition()
        local delta = (bar.dragY - cursorY) / bar:GetEffectiveScale()
        bar.dragY = cursorY
        bar.dragPosition = Clamp(bar.dragPosition + delta * range / travel, range)
        SetScroll(SnapScroll(bar.dragPosition, range))
        Update()
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", OnWheel)
    scrollFrame:HookScript("OnVerticalScroll", function()
        if not bar.applyingScroll then
            StopAnimation()
            StopDrag()
            if bar.layoutDepth == 0 then
                Update()
            end
        end
    end)
    scrollFrame:HookScript("OnScrollRangeChanged", Update)
    scrollChild:HookScript("OnSizeChanged", function()
        bar:Refresh()
    end)
    scrollFrame:HookScript("OnSizeChanged", function()
        bar:Refresh()
    end)
    scrollFrame:HookScript("OnShow", function()
        bar:Refresh()
    end)
    scrollFrame:HookScript("OnHide", function()
        StopAnimation()
        StopDrag()
        if bar:IsShown() then
            bar:Hide()
        end
    end)
    bar:SetScript("OnMouseWheel", OnWheel)
    bar:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        local top = bar:GetTop()
        local range = bar:GetRange()
        local travel = bar:GetHeight() - bar.Thumb:GetHeight()
        if not top or range <= 0 or travel <= 0 then
            return
        end
        local _, cursorY = GetCursorPosition()
        local offset = top - cursorY / bar:GetEffectiveScale()
        local thumbOffset = travel * Clamp(scrollFrame:GetVerticalScroll(), range) / range
        if offset < thumbOffset or offset > thumbOffset + bar.Thumb:GetHeight() then
            bar:ScrollTo((offset - bar.Thumb:GetHeight() / 2) * range / travel, true)
        end
    end)
    bar:SetScript("OnDragStart", function()
        if bar:GetRange() == 0 then
            return
        end
        StopAnimation()
        local _, cursorY = GetCursorPosition()
        bar.dragY = cursorY
        bar.dragPosition = scrollFrame:GetVerticalScroll()
        bar:SetScript("OnUpdate", DragStep)
    end)
    bar:SetScript("OnDragStop", StopDrag)
    bar:SetScript("OnMouseUp", StopDrag)
    bar:SetScript("OnHide", function()
        StopAnimation()
        StopDrag()
    end)
    scrollFrame.QuizScrollBar = bar
    bar:Refresh()
    return bar
end

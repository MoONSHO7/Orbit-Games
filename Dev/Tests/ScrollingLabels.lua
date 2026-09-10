local EPSILON = 0.000001
local WIDTH = 160
local HEIGHT = 18
local ROW_HEIGHT = 52
local PAUSE = 1.5
local SPEED = 30
local MIN_DURATION = 1
local LONG_TEXT = "A complete collection of stories from every corner of Azeroth and beyond"
local LOCALIZED_TEXT =
    "Истории Азерота · Les chroniques oubliées · 艾泽拉斯的传说 · 아제로스 이야기"
local PHYSICAL_HEIGHTS = { 768, 1080, 1440 }
local SCALES = { 0.65, 1, 1.35 }

return function(Games)
    local Quiz = Games.Quiz
    local assertions = 0
    local Controls, UI = Games.Controls, Games.UI
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function Near(actual, expected, message)
        Check(math.abs(actual - expected) < EPSILON, message .. ": " .. actual .. " ~= " .. expected)
    end
    local function Allocations()
        return {
            frames = #Test.frames,
            labels = Test.fontStringCreations,
            fonts = Test.fontObjectCreations,
            textures = Test.textureCreations,
            groups = #Test.animationGroups,
            animations = Test.animationCreations,
            tickers = #Test.tickers,
        }
    end
    local function SameAllocations(before, message)
        for key, value in pairs(Allocations()) do
            Same(value, before[key], message .. " retains " .. key)
        end
    end
    local function Phase(frame)
        return {
            elapsed = frame.animation.elapsed,
            plays = frame.animation.playCalls,
            stops = frame.animation.stopCalls,
            textCalls = frame.Text.textCalls,
        }
    end
    local function SamePhase(frame, before, message)
        Near(frame.animation.elapsed, before.elapsed, message .. " retains progress")
        Same(frame.animation.playCalls, before.plays, message .. " does not replay")
        Same(frame.animation.stopCalls, before.stops, message .. " does not stop")
        Same(frame.Text.textCalls, before.textCalls, message .. " does not rewrite text")
    end
    local function WithVisibility(action)
        local before = {}
        for frame in pairs(Controls.scrollingLabels) do
            before[frame] = { visible = frame:IsVisible(), shown = frame:IsShown() }
        end
        action()
        for frame, state in pairs(before) do
            if frame:IsShown() == state.shown and frame:IsVisible() ~= state.visible then
                local script = frame:GetScript(frame:IsVisible() and "OnShow" or "OnHide")
                Check(type(script) == "function", "marquee owns its ancestor visibility lifecycle")
                script(frame)
            end
        end
    end
    local function Native(frame, text, playing)
        local label, group = frame.Text, frame.animation
        local pixel = PixelUtil.GetNearestPixelSize(0, frame:GetEffectiveScale(), 1)
        local measured = label:GetUnboundedStringWidthForText(text)
        local fullWidth = math.ceil(measured / pixel - EPSILON) * pixel
        local width = frame:GetWidth()
        local distance = width > 0 and math.max(0, fullWidth - width) or 0
        local duration = math.max(MIN_DURATION, distance / SPEED)
        Same(frame.kind, "Frame", "fixed clipping region is a frame")
        Same(frame.clipsChildren, true, "viewport clips the translated text")
        Same(frame.mouse, false, "viewport cannot intercept Join clicks")
        Same(label.kind, "FontString", "description keeps a native FontString")
        Same(label:GetParent(), frame, "full text lives directly inside its clipping viewport")
        Same(label:GetText(), text, "full text is preserved without truncation or replacement")
        Same(label.wordWrap, false, "description does not wrap at spaces")
        Same(label.nonSpaceWrap, false, "description does not wrap within long localized words")
        Same(label:GetJustifyH(), "LEFT", "description starts at its left edge")
        Same(label.point[1], "TOPLEFT", "description has a stable left anchor")
        Same(label.point[2], frame, "description is anchored to its own viewport")
        Near(label.point[4], 0, "description baseline starts at zero horizontal offset")
        Near(label.point[5], 0, "description baseline starts at zero vertical offset")
        Near(label:GetWidth(), math.max(width, fullWidth), "text width is the full ceil-pixel measurement")
        Near(label:GetHeight(), frame:GetHeight(), "text cannot grow the fixed row height")
        Near(frame.scrollDistance, distance, "travel exactly exposes the clipped right edge")
        Same(group:GetParent(), label, "native translation moves only the description")
        Same(group:GetLooping(), "REPEAT", "two opposing translations repeat natively")
        Same(#group.animations, 2, "exactly two translations cover the full cycle")
        Same(group.animations[1], frame.forward, "outward translation is retained")
        Same(group.animations[2], frame.backward, "return translation is retained")
        for order, animation in ipairs({ frame.forward, frame.backward }) do
            Same(animation.kind, "Translation", "marquee uses native translation animations")
            Same(animation:GetOrder(), order, "translations run sequentially")
            Same(animation:GetSmoothing(), "IN_OUT", "travel eases at each end")
            Near(animation:GetStartDelay(), PAUSE, "each endpoint gets a readable pause")
            Near(animation:GetEndDelay(), 0, "no hidden extra delay changes the cycle")
            Near(animation:GetDuration(), duration, "travel follows distance with a one-second minimum")
            Near(
                select(1, animation:GetOffset()),
                order == 1 and -distance or distance,
                "opposing offsets return to origin"
            )
            Near(select(2, animation:GetOffset()), 0, "marquee never translates vertically")
        end
        Near(group:GetDuration(), 2 * (PAUSE + duration), "native cycle includes both pauses and travel legs")
        Same(group:IsPlaying(), playing, "only visible overflow plays")
        Same(group.finishCalls, 0, "repeating groups never finish between cycles")
        Same(frame:GetScript("OnUpdate"), nil, "viewport needs no per-frame Lua update")
        Same(label:GetScript("OnUpdate"), nil, "label needs no per-frame Lua update")
        Same(Controls.scrollingLabels[frame], true, "viewport participates in scale refresh")
    end
    local function Restarted(frame, plays, message)
        Same(frame.animation.playCalls, plays + 1, message .. " restarts exactly once")
        Near(frame.animation.elapsed, 0, message .. " returns to the opening pause")
        Check(frame.animation:IsPlaying(), message .. " resumes overflow animation")
    end

    local host = CreateFrame("Frame", nil, UIParent)
    local initial = Allocations()
    local viewport = Controls:ScrollingLabel(host, "", "GameFontHighlightSmall")
    PixelUtil.SetSize(viewport, WIDTH, HEIGHT)
    Same(#Test.frames, initial.frames + 1, "one viewport is the only extra frame per description")
    Same(Test.fontStringCreations, initial.labels + 1, "one full-width label is allocated")
    Same(#Test.animationGroups, initial.groups + 1, "one native group is allocated")
    Same(Test.animationCreations, initial.animations + 2, "two reusable translations are allocated")
    Same(#Test.tickers, initial.tickers, "constructing a marquee allocates no ticker")
    Same(viewport.Text:GetFontObject(), GameFontHighlightSmall, "constructor preserves the requested font")
    Native(viewport, "", false)
    Controls:SetScrollingText(viewport, "Fits")
    Native(viewport, "Fits", false)
    Same(viewport.animation.playCalls, 0, "empty and fitting descriptions never start an animation")

    Controls:SetScrollingText(viewport, LONG_TEXT)
    Native(viewport, LONG_TEXT, true)
    local cycle, duration = viewport.animation:GetDuration(), viewport.forward:GetDuration()
    local plays = viewport.animation.playCalls
    Test.AdvanceAnimations(PAUSE / 2)
    Near(viewport.animation.elapsed, PAUSE / 2, "first pause is retained in native time")
    Test.AdvanceAnimations(PAUSE / 2 + duration / 2)
    Near(viewport.animation.elapsed, PAUSE + duration / 2, "outward travel follows the first pause")
    local steady, allocated = Phase(viewport), Allocations()
    Controls:SetScrollingText(viewport, LONG_TEXT)
    Controls:SetScrollingText(viewport, LONG_TEXT, false)
    Controls:RefreshScale()
    SamePhase(viewport, steady, "unchanged label and scale refresh")
    SameAllocations(allocated, "unchanged label and scale refresh")
    Test.AdvanceAnimations(duration / 2 + PAUSE / 2)
    Near(viewport.animation.elapsed, PAUSE + duration + PAUSE / 2, "return leg begins after a separate right pause")
    Test.AdvanceAnimations(PAUSE / 2 + duration / 2)
    Near(viewport.animation.elapsed, 2 * PAUSE + duration * 1.5, "return travel follows the right pause")
    Test.AdvanceAnimations(duration / 2 + cycle * 4)
    Near(viewport.animation.elapsed, 0, "multiple cycles wrap without a Lua replay callback")
    Same(viewport.animation.playCalls, plays, "repeating native time never calls Play again")
    Same(viewport.animation.finishCalls, 0, "repeating native time never emits OnFinished")
    SameAllocations(allocated, "native animation cycles")

    Test.AdvanceAnimations(PAUSE + MIN_DURATION / 2)
    Controls:SetScrollingText(viewport, LONG_TEXT, true)
    Restarted(viewport, plays, "explicit identity reset with unchanged text")
    plays = viewport.animation.playCalls
    local sameWidthText, distance = string.rep("x", #LONG_TEXT), viewport.scrollDistance
    Test.AdvanceAnimations(PAUSE)
    Controls:SetScrollingText(viewport, sameWidthText)
    Restarted(viewport, plays, "new text with identical metrics")
    Near(viewport.scrollDistance, distance, "same-width replacement keeps the same endpoint")
    Native(viewport, sameWidthText, true)

    viewport:Hide()
    Check(not viewport.animation:IsPlaying(), "direct hide stops native motion")
    plays = viewport.animation.playCalls
    Controls:SetScrollingText(viewport, LOCALIZED_TEXT)
    Controls:RefreshScale()
    Native(viewport, LOCALIZED_TEXT, false)
    Same(viewport.animation.playCalls, plays, "hidden text changes cannot start invisible motion")
    viewport:Show()
    Restarted(viewport, plays, "direct show")
    Native(viewport, LOCALIZED_TEXT, true)
    WithVisibility(function()
        host:Hide()
    end)
    Check(viewport:IsShown() and not viewport:IsVisible(), "ancestor hide leaves the viewport's own shown flag intact")
    Native(viewport, LOCALIZED_TEXT, false)
    plays = viewport.animation.playCalls
    WithVisibility(function()
        host:Show()
    end)
    Restarted(viewport, plays, "ancestor show")

    PixelUtil.SetWidth(viewport, viewport.Text:GetWidth())
    Native(viewport, LOCALIZED_TEXT, false)
    PixelUtil.SetWidth(
        viewport,
        viewport:GetWidth() - PixelUtil.GetNearestPixelSize(0, viewport:GetEffectiveScale(), 1)
    )
    Native(viewport, LOCALIZED_TEXT, true)
    Near(viewport.forward:GetDuration(), MIN_DURATION, "one pixel of overflow still has readable minimum travel")
    PixelUtil.SetWidth(viewport, 0)
    Native(viewport, LOCALIZED_TEXT, false)
    PixelUtil.SetWidth(viewport, WIDTH)
    Native(viewport, LOCALIZED_TEXT, true)
    Controls:SetScrollingText(viewport, "")
    Native(viewport, "", false)

    local screenHeight = Test.physicalHeight
    local fontPath = viewport.Text:GetFont()
    local oldFontWidth = Test.fontWidths[fontPath]
    Test.fontWidths[fontPath] = 8.125
    Controls:SetScrollingText(viewport, LONG_TEXT)
    allocated = Allocations()
    for _, height in ipairs(PHYSICAL_HEIGHTS) do
        Test.physicalHeight = height
        for _, scale in ipairs(SCALES) do
            host:SetScale(scale)
            PixelUtil.SetSize(viewport, WIDTH, HEIGHT)
            Controls:RefreshScale()
            Native(viewport, LONG_TEXT, true)
            local pixel = PixelUtil.GetNearestPixelSize(0, viewport:GetEffectiveScale(), 1)
            Near(
                viewport.scrollDistance / pixel,
                math.floor(viewport.scrollDistance / pixel + 0.5),
                "endpoints share the physical grid"
            )
            Test.AdvanceAnimations(PAUSE / 2)
            steady = Phase(viewport)
            Controls:RefreshScale()
            SamePhase(viewport, steady, "stable fractional-scale refresh")
        end
    end
    SameAllocations(allocated, "resolution and scale changes")
    plays = viewport.animation.playCalls
    Test.fontWidths[fontPath] = 9.625
    Controls:RefreshScale()
    Restarted(viewport, plays, "font metric change without a viewport resize")
    Native(viewport, LONG_TEXT, true)
    Test.fontWidths[fontPath], Test.physicalHeight = oldFontWidth, screenHeight
    host:SetScale(1)
    PixelUtil.SetSize(viewport, WIDTH, HEIGHT)
    viewport:Hide()

    local function Game(index, title)
        return {
            hostName = "Marqueehost" .. index .. "-TestRealm",
            sessionId = "marquee." .. index,
            gameTypeId = Quiz.id,
            protocolVersion = 2,
            activityId = Quiz.id,
            activityVersion = 1,
            title = title,
            description = "Quiz",
            phase = "open",
            playerCount = index,
            maxPlayers = 17,
            joinable = true,
            preview = true,
        }
    end
    local preview = {
        title = "Scrolling label fixtures",
        notice = "Offline presentation checks",
        games = { Game(1, LONG_TEXT), Game(2, "Short"), Game(3, LOCALIZED_TEXT) },
    }
    local function Refresh()
        WithVisibility(function()
            UI.nextGamesRefresh = nil
            UI:Refresh()
        end)
    end
    local function Row(row, game)
        local frame = row.detailViewport
        local text = Games.L.W_GAME_DETAIL_F:format(game.title, game.description, game.playerCount, game.maxPlayers)
        Same(row.detail, frame.Text, "public row.detail remains the original FontString interface")
        Same(frame:GetParent(), row, "marquee belongs to its pooled row")
        Same(row.game, game, "pooled row refers to the current listing")
        Same(row.gameKey, game.hostName .. ":" .. game.sessionId, "row retains an immutable identity key")
        Same(UI.gameRowPool.active[row], true, "visible row remains an active pool member")
        Check(UI.placements[frame] ~= nil, "fixed viewport participates in setup layout")
        Same(UI.placements[row.detail], nil, "setup layout cannot clamp the full-width moving text")
        Near(
            row:GetHeight(),
            PixelUtil.GetNearestPixelSize(ROW_HEIGHT, row:GetEffectiveScale()),
            "long text retains row height"
        )
        Check(frame:GetRight() < row.join:GetLeft(), "description clip ends before the Join button")
        Check(frame:GetLeft() >= row:GetLeft() and frame:GetRight() <= row:GetRight(), "clip stays inside the row")
        for index, value in ipairs({ 0.6, 0.6, 0.6, 1 }) do
            Near(select(index, row.detail:GetTextColor()), value, "description preserves the muted grey color")
        end
        Native(frame, text, frame.scrollDistance > 0 and frame:IsVisible())
    end

    UI:SetGamePreview(preview)
    WithVisibility(function()
        UI:Toggle()
    end)
    Same(UI.tab, "play", "browser fixture uses the normal Available Games page")
    Same(#UI.gameRows, #preview.games, "browser creates one pooled row per listing")
    for index, row in ipairs(UI.gameRows) do
        Row(row, preview.games[index])
    end
    local first, second, third = unpack(UI.gameRows)
    local firstViewport = first.detailViewport
    Check(firstViewport.animation:IsPlaying(), "long first listing starts its marquee")
    Check(not second.detailViewport.animation:IsPlaying(), "fitting listing remains static")
    Check(third.detailViewport.animation:IsPlaying(), "long localized listing starts its marquee")
    allocated = Allocations()
    Test.AdvanceAnimations(PAUSE + MIN_DURATION / 2)
    steady = Phase(firstViewport)
    local shows, hides = first.showTransitions, first.hideTransitions
    preview.games[2].phase = "paused"
    Refresh()
    Same(UI.gameRows[1], first, "unrelated listing changes retain the existing row at its index")
    Same(UI.gameRows[2], second, "changed listing reuses its own row")
    Same(UI.gameRows[3], third, "other unchanged rows are retained")
    SamePhase(firstViewport, steady, "unrelated listing change")
    preview.games[1].description = "Updated mode with unchanged title"
    Refresh()
    Restarted(firstViewport, steady.plays, "own listing description change")
    Row(first, preview.games[1])
    steady = Phase(firstViewport)
    Same(first.showTransitions, shows, "refresh never hides and reshow retained rows")
    Same(first.hideTransitions, hides, "refresh never recycles retained rows")
    SameAllocations(allocated, "listing metadata changes")
    for _ = 1, 8 do
        UI:Refresh()
        Refresh()
    end
    SamePhase(firstViewport, steady, "idle throttled and unthrottled refreshes")
    SameAllocations(allocated, "idle browser refreshes")

    for _, replacement in ipairs({
        { "title", LONG_TEXT .. " — new collection" },
        { "playerCount", 12 },
        { "sessionId", "marquee.restarted" },
        { "hostName", "Replacementhost-TestRealm" },
    }) do
        Test.AdvanceAnimations(PAUSE + MIN_DURATION / 2)
        plays = firstViewport.animation.playCalls
        preview.games[1][replacement[1]] = replacement[2]
        Refresh()
        Same(UI.gameRows[1], first, "in-place listing changes reuse the same pooled row")
        Restarted(firstViewport, plays, "changed " .. replacement[1])
        Row(first, preview.games[1])
    end
    SameAllocations(allocated, "description and identity changes")

    WithVisibility(function()
        UI:SetTab("host")
    end)
    for _, row in ipairs(UI.gameRows) do
        Check(not row.detailViewport.animation:IsPlaying(), "leaving the browser stops every marquee")
    end
    plays = firstViewport.animation.playCalls
    WithVisibility(function()
        UI:SetTab("play")
    end)
    Restarted(firstViewport, plays, "returning to Available Games")
    WithVisibility(function()
        UI.frame:Hide()
    end)
    Check(not firstViewport.animation:IsPlaying(), "closing setup stops child motion")
    plays = firstViewport.animation.playCalls
    Controls:RefreshScale()
    Same(firstViewport.animation.playCalls, plays, "scale refresh cannot restart a closed browser")
    WithVisibility(function()
        UI.frame:Show()
    end)
    Restarted(firstViewport, plays, "reopening setup")
    allocated = Allocations()

    Test.AdvanceAnimations(PAUSE)
    steady = Phase(firstViewport)
    preview.games[2], preview.games[3] = nil, nil
    Refresh()
    Same(#UI.gameRows, 1, "shortened listing releases only removed rows")
    Same(UI.gameRows[1], first, "shortening preserves the retained first row")
    SamePhase(firstViewport, steady, "removing other listings")
    Same(#UI.gameRowPool.inactive, 2, "only the two missing rows enter the inactive pool")
    for _, row in ipairs({ second, third }) do
        Same(UI.gameRowPool.active[row], nil, "released row no longer belongs to the active pool")
        Same(row.game, nil, "released row forgets its old listing")
        Same(row.gameKey, nil, "released row forgets its old identity")
        Check(not row:IsShown(), "released row is hidden")
        Check(not row.detailViewport.animation:IsPlaying(), "releasing a parent row stops its marquee")
    end
    local originalRows = { [first] = true, [second] = true, [third] = true }
    preview.games[2], preview.games[3] = Game(4, LOCALIZED_TEXT), Game(5, LONG_TEXT)
    Refresh()
    Same(#UI.gameRows, 3, "new listings reacquire the released capacity")
    Same(#UI.gameRowPool.inactive, 0, "reacquiring consumes inactive rows")
    SamePhase(firstViewport, steady, "appending replacement listings")
    for index, row in ipairs(UI.gameRows) do
        Check(originalRows[row], "reacquired rows reuse all original frames")
        Row(row, preview.games[index])
        if index > 1 then
            Near(row.detailViewport.animation.elapsed, 0, "recycled row starts at the readable opening pause")
            Check(row.detailViewport.animation:IsPlaying(), "recycled overflowing row resumes after showing")
        end
    end
    SameAllocations(allocated, "row release and reuse")

    Test.physicalHeight = PHYSICAL_HEIGHTS[#PHYSICAL_HEIGHTS]
    UIParent:SetScale(SCALES[1])
    UI:OnDisplayChanged()
    for index, row in ipairs(UI.gameRows) do
        Row(row, preview.games[index])
    end
    SameAllocations(allocated, "browser display-scale refresh")
    preview.games = {}
    Refresh()
    Same(#UI.gameRows, 0, "empty list releases every row")
    Check(UI.gamesEmpty:IsShown(), "empty browser retains the normal empty-state label")
    for row in pairs(originalRows) do
        Check(not row.detailViewport.animation:IsPlaying(), "empty list leaves no active marquee")
    end
    Test.physicalHeight = screenHeight
    UIParent:SetScale(1)
    UI:OnDisplayChanged()
    WithVisibility(function()
        UI:SetGamePreview(nil)
        UI.frame:Hide()
    end)
    Same(#Test.errors, 0, "marquee lifecycle leaves no captured runtime errors")
    return assertions
end

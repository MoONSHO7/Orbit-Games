local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L
local Controls = Games.Controls

local SWITCH_Y = 0
local SCROLL_Y = -38
local SCORE_LIST_HEIGHT_GAIN = 40
local TITLE_HEIGHT = 18
local DETAILS_HEIGHT = 18
local HEADING_HEIGHT = 26
local ROW_PADDING = 10
local ROW_GAP = 8
local SCORE_GAP = 8
local MIN_SCORE_WIDTH = 72
local SCORE_WIDTH_FRACTION = 0.5
local SCOPES = { "personal", "game" }
local SCOPE_TITLES = {
    personal = L.W_SCORE_SCOPE_PERSONAL,
    game = L.W_SCORE_SCOPE_GAME,
}

Quiz.ScoreView = { scope = "personal", rows = {} }
local ScoreView = Quiz.ScoreView

local function RoundUp(value, scale)
    local snapped = PixelUtil.GetNearestPixelSize(value, scale)
    if snapped < value then
        snapped = snapped + PixelUtil.GetNearestPixelSize(0, scale, 1)
    end
    return snapped
end

local function ResetRow(_, row)
    row:Hide()
    row:ClearAllPoints()
    if not row.Title then
        return
    end
    row.kind, row.record, row.player = nil, nil, nil
    row.Title:SetText("")
    row.Score:SetText("")
    row.Details:SetText("")
    row.Score:Hide()
    row.Details:Hide()
    row.Divider:Hide()
end

local function RulesLabel(record, counts, indices)
    if record.archived then
        return L.W_SCORE_EARLIER_RULES
    end
    local key = record.id .. ":" .. record.rules.version
    indices[key] = (indices[key] or 0) + 1
    return counts[key] > 1 and L.W_SCORE_RULE_VARIATION_F:format(record.rules.version, indices[key])
        or L.W_SCORE_RULE_REVISION_F:format(record.rules.version)
end

local function RulesDetails(rules, label)
    local streak = rules.streakBonusPerCorrect > 0
            and L.W_SCORE_RULE_STREAK_F:format(rules.streakBonusPerCorrect, rules.streakBonusMax)
        or L.W_SCORE_RULE_NO_STREAK
    return L.W_SCORE_RULE_DETAILS_F:format(
        label,
        rules.answerSeconds,
        rules.correctPoints,
        rules.speedBonusPerSecond,
        rules.wrongPenaltyStart,
        rules.wrongPenaltyEnd,
        rules.wrongPenaltyCurve,
        streak
    )
end

local function PersonalRows(includeRules)
    local records = Quiz.PersonalScores:GetScoreRows()
    local counts, indices, rows = {}, {}, {}
    if includeRules then
        for _, record in ipairs(records) do
            if not record.archived then
                local key = record.id .. ":" .. record.rules.version
                counts[key] = (counts[key] or 0) + 1
            end
        end
    end
    for _, record in ipairs(records) do
        local rulesText
        if includeRules then
            local label = RulesLabel(record, counts, indices)
            rulesText = record.archived and label or RulesDetails(record.rules, label)
        end
        rows[#rows + 1] = {
            kind = "personal",
            title = record.title,
            score = L.W_SCORE_POINTS_F:format(record.score),
            details = L.W_SCORE_QUESTION_STATS_F:format(
                record.rounds,
                record.correct,
                record.incorrect,
                record.unanswered
            ),
            rulesText = rulesText,
            record = record,
        }
    end
    return rows
end

local function RankedRow(index, player, legacy)
    return {
        kind = legacy and "legacy" or "standing",
        rank = index,
        title = L.W_SCORE_RANK_F:format(index, player.name),
        score = legacy and L.W_SCORE_LEGACY_POINTS_F:format(player.score) or L.W_SCORE_POINTS_F:format(player.score),
        details = L.W_SCORE_GAME_STATS_F:format(player.answers, player.correct, player.incorrect),
        player = player,
    }
end

local function ArchiveRows(scope)
    local rows = {}
    for _, league in ipairs(Quiz.Store:GetArchivedLeagues()) do
        local standings = scope == "legacy" and Quiz.Store:GetLegacyStandings(league, "PUBLIC")
            or Quiz.Store:GetStandings(league, "PUBLIC")
        if #standings > 0 then
            rows[#rows + 1] = { kind = "heading", title = L.W_SCORE_LEAGUE_F:format(league) }
            for index, player in ipairs(standings) do
                rows[#rows + 1] = RankedRow(index, player, scope == "legacy")
            end
        end
    end
    return rows
end

local function GameRows(view)
    local participant = view.role == "participant"
    local game = not participant and Quiz.Controller.game or nil
    if view.role ~= "host" and not participant and not game then
        return {}
    end
    local rows = {}
    local rules = view.rules or game and game.rules
    local packTitle = view.packTitle
        or game and game.round and game.round.packTitle
        or game and game.lastResult and game.lastResult.packTitle
    if rules then
        rows[#rows + 1] = {
            kind = "summary",
            title = packTitle and L.W_SCORE_CURRENT_RULES_F:format(packTitle) or L.W_SCORE_CURRENT_RULES,
        }
    end
    if participant then
        if view.score ~= nil then
            rows[#rows + 1] = {
                kind = "participant",
                title = L.W_SCORE_YOUR_TOTAL,
                score = L.W_SCORE_POINTS_F:format(view.score),
                details = L.W_SCORE_PARTICIPANT_DETAIL,
            }
        else
            rows[#rows + 1] = { kind = "message", title = L.W_SCORE_WAITING_TOTAL }
        end
        return rows
    end
    local standings = game and game:GetStandings() or {}
    if #standings == 0 then
        rows[#rows + 1] = { kind = "message", title = L.W_SCORE_NO_GAME_RESULTS }
        return rows
    end
    for index, player in ipairs(standings) do
        rows[#rows + 1] = RankedRow(index, player, false)
    end
    return rows
end

local function EmptyText(scope, view)
    if scope == "personal" then
        return L.W_SCORE_NO_HISTORY
    elseif scope == "archive" then
        return L.W_SCORE_NO_ARCHIVE
    elseif scope == "legacy" then
        return L.W_SCORE_NO_LEGACY
    elseif view.role == "participant" then
        return L.W_SCORE_WAITING_TOTAL
    elseif view.role == "host" then
        return L.W_SCORE_NO_GAME_RESULTS
    end
    return L.W_SCORE_NO_GAME
end

function ScoreView:InitializeRow(row)
    row.Title = Controls:Label(row, "", "GameFontHighlightSmall")
    row.Title:SetMaxLines(1)
    row.Title:SetWordWrap(false)
    row.Title:SetNonSpaceWrap(false)
    row.Score = Controls:Label(row, "", "GameFontNormal")
    row.Score:SetJustifyH("RIGHT")
    row.Score:SetMaxLines(1)
    row.Score:SetWordWrap(false)
    row.Score:SetNonSpaceWrap(false)
    row.Details = Controls:Label(row, "", "GameFontHighlightSmall")
    row.Details:SetMaxLines(0)
    Controls:SetMuted(row.Details)
    row.Divider = Controls:Divider(row, self.width)
end

function ScoreView:AcquireRow()
    local row = self.rowPool:Acquire()
    if not row.Title then
        self:InitializeRow(row)
    end
    return row
end

function ScoreView:LayoutRow(row, descriptor, scoreWidth, offset)
    row.kind, row.record, row.player = descriptor.kind, descriptor.record, descriptor.player
    row.Title:SetFontObject(descriptor.kind == "heading" and GameFontNormal or GameFontHighlightSmall)
    row.Title:SetJustifyH("LEFT")
    row.Title:SetText(descriptor.title)
    row.Score:SetText(descriptor.score or "")
    row.Score:SetShown(descriptor.score ~= nil)
    row.Details:SetText(descriptor.details or "")
    row.Details:SetShown(descriptor.details ~= nil)

    local titleWidth = descriptor.score and math.max(1, self.width - scoreWidth - SCORE_GAP) or self.width
    PixelUtil.SetSize(row.Title, titleWidth, TITLE_HEIGHT)
    PixelUtil.SetPoint(row.Title, "TOPLEFT", row, "TOPLEFT", 0, 0)
    PixelUtil.SetSize(row.Score, scoreWidth, TITLE_HEIGHT)
    PixelUtil.SetPoint(row.Score, "TOPRIGHT", row, "TOPRIGHT", 0, 0)

    local height = descriptor.kind == "heading" and HEADING_HEIGHT or TITLE_HEIGHT
    if descriptor.details then
        PixelUtil.SetWidth(row.Details, self.width)
        row.Details:SetHeight(0)
        local detailsHeight =
            RoundUp(math.max(DETAILS_HEIGHT, row.Details:GetStringHeight()), row.Details:GetEffectiveScale())
        row.Details:SetHeight(detailsHeight)
        PixelUtil.SetPoint(row.Details, "TOPLEFT", row, "TOPLEFT", 0, -height)
        height = height + row.Details:GetHeight()
    end
    height = descriptor.kind == "heading" and height or height + ROW_PADDING
    PixelUtil.SetSize(row, self.width, height)
    PixelUtil.SetPoint(row, "TOPLEFT", self.content, "TOPLEFT", 0, -offset)
    PixelUtil.SetPoint(row.Divider, "BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.Divider:SetShown(descriptor.kind ~= "heading")
    row:Show()
    return row:GetHeight()
end

function ScoreView:Render(descriptors, view)
    self.rowPool:ReleaseAll()
    self.rows = {}
    local scoreWidth = MIN_SCORE_WIDTH
    for _, descriptor in ipairs(descriptors) do
        if descriptor.score then
            scoreWidth = math.max(scoreWidth, self.scoreProbe:GetUnboundedStringWidthForText(descriptor.score))
        end
    end
    scoreWidth = math.min(self.width * SCORE_WIDTH_FRACTION, RoundUp(scoreWidth, self.scoreProbe:GetEffectiveScale()))

    local offset = 0
    for _, descriptor in ipairs(descriptors) do
        local row = self:AcquireRow()
        self.rows[#self.rows + 1] = row
        offset = offset + self:LayoutRow(row, descriptor, scoreWidth, offset) + ROW_GAP
    end
    if #descriptors > 0 then
        offset = math.max(0, offset - ROW_GAP)
    end
    self.empty:SetText(EmptyText(self.scope, view))
    self.empty:SetShown(#descriptors == 0)
    PixelUtil.SetSize(self.empty, self.width, self.height)
    PixelUtil.SetHeight(self.content, math.max(self.height, offset))
end

function ScoreView:Create(page, width, height, scrollbarOptions)
    if self.page then
        return
    end
    self.page, self.width, self.height = page, width, height
    self.scopeSwitch = Controls:Dropdown(page, SCOPE_TITLES[self.scope], width, function(_, root)
        local function IsSelected(scope)
            return self.scope == scope
        end
        local function Select(scope)
            self.scope = scope
            self:Invalidate()
            self:Refresh(Quiz.Session:GetView())
        end
        for _, scope in ipairs(SCOPES) do
            root:CreateRadio(SCOPE_TITLES[scope], IsSelected, Select, scope)
        end
    end)
    self.scroll, self.content = Controls:Scroll(page, width, height, scrollbarOptions)
    self.empty = Controls:Label(self.content, "", "GameFontHighlightSmall")
    self.empty:SetJustifyV("TOP")
    Controls:SetMuted(self.empty)
    PixelUtil.SetPoint(self.empty, "TOPLEFT", self.content, "TOPLEFT", 0, 0)
    self.scoreProbe = Controls:Label(page, "", "GameFontNormal")
    self.scoreProbe:Hide()
    self.rowPool = CreateFramePool("Frame", self.content, nil, ResetRow)
    self:Layout(width, height)
end

function ScoreView:Layout(width, height)
    self.width, self.height = width, height + SCORE_LIST_HEIGHT_GAIN
    local scrollbar = self.scroll.ScrollBar
    scrollbar:BeginLayout()
    PixelUtil.SetWidth(self.scopeSwitch, width)
    PixelUtil.SetPoint(self.scopeSwitch, "TOPLEFT", self.page, "TOPLEFT", 0, SWITCH_Y)
    PixelUtil.SetSize(self.scroll, width, self.height)
    PixelUtil.SetPoint(self.scroll, "TOPLEFT", self.page, "TOPLEFT", 0, SCROLL_Y)
    self:Invalidate()
    scrollbar:EndLayout()
end

function ScoreView:CloseMenu()
    if self.scopeSwitch then
        self.scopeSwitch:CloseMenu()
    end
end

function ScoreView:Invalidate()
    self.cache = nil
end

function ScoreView:Refresh(view)
    local game = Quiz.Controller.game
    local revision = self.scope == "personal" and Quiz.PersonalScores.revision or game and game.completed or 0
    local cache = self.cache
    if
        cache
        and cache.scope == self.scope
        and cache.revision == revision
        and cache.game == game
        and cache.database == Quiz.Store.db
        and cache.session == view.session
        and cache.role == view.role
        and cache.state == view.state
        and cache.score == view.score
        and cache.rulesKey == view.rulesKey
    then
        return
    end
    self.cache = {
        scope = self.scope,
        revision = revision,
        game = game,
        database = Quiz.Store.db,
        session = view.session,
        role = view.role,
        state = view.state,
        score = view.score,
        rulesKey = view.rulesKey,
    }
    self.scopeSwitch:Update()
    local descriptors = self.scope == "personal" and PersonalRows()
        or self.scope == "game" and GameRows(view)
        or ArchiveRows(self.scope)
    local scrollbar = self.scroll.ScrollBar
    scrollbar:BeginLayout()
    self:Render(descriptors, view)
    if self.displayedScope ~= self.scope then
        scrollbar:ScrollTo(0, true)
        self.displayedScope = self.scope
    end
    scrollbar:EndLayout()
end

function ScoreView:GetPersonalScoreLines()
    local lines = {}
    for _, row in ipairs(PersonalRows(true)) do
        lines[#lines + 1] = table.concat({ row.title .. " · " .. row.score, row.details, row.rulesText }, "\n")
    end
    return lines
end

function ScoreView:GetArchiveLines(scope)
    local lines = {}
    for _, row in ipairs(ArchiveRows(scope)) do
        if row.kind == "heading" then
            lines[#lines + 1] = row.title
        else
            lines[#lines + 1] = L.W_SCORE_RANKED_LINE_F:format(
                row.rank,
                row.player.name,
                row.score,
                row.player.correct,
                row.player.incorrect
            )
        end
    end
    return lines
end

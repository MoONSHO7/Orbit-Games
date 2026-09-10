local _, Games = ...
local Cards = Games.Cards
local L = Cards.L
local Rules = Cards.TexasHoldem.Rules

local PAIRED_VALUE_X = 84
local BLIND_VALUE_WIDTH = 140
local MAX_AMOUNT_LETTERS = 18
local BLIND_VALUE_FONT = "GameFontHighlight"

local HostPage = {}
Cards.HostPage = HostPage

local function CreateLabel(owner, parent, layout, key, text, x, y, valueX)
    local label = layout.FormLabel(parent, text, x, y, valueX - layout.form.gap)
    owner.labels[key] = label
    return label
end

local function CreateDropdown(owner, parent, layout, key, text, defaultText, x, y, width, valueX, generator)
    CreateLabel(owner, parent, layout, key, text, x, y, valueX)
    return layout.Dropdown(parent, defaultText, x + valueX, y, width - valueX, generator)
end

local function Copy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function ErrorText(reason)
    local message = L.errors[reason]
    if message then
        return message
    end
    return type(reason) == "string" and reason:find("%s") and reason or L.W_ACTION_FAILED
end

function HostPage:CreateAmount(parent, layout, key, label, x, y, width, valueX)
    CreateLabel(self, parent, layout, key, label, x, y, valueX)
    local edit = Games.Controls:Edit(parent, width - valueX, layout.form.fieldHeight, MAX_AMOUNT_LETTERS)
    edit:SetNumeric(true)
    layout.Place(edit, parent, x + valueX, y, width - valueX, layout.form.fieldHeight)
    self.amounts[key] = edit
end

function HostPage:GetBlindAmounts(rate)
    local buyIn = Cards.Gold:Parse(self.amounts.buyIn:GetText(), Cards.BUY_IN_MAX)
    local smallBlind = Rules.SmallBlindForRate(buyIn, rate)
    return smallBlind, smallBlind and smallBlind * 2
end

function HostPage:FormatBlinds(rate)
    local smallBlind, bigBlind = self:GetBlindAmounts(rate)
    if not smallBlind then
        return L.W_BLINDS_UNAVAILABLE
    end
    return L.W_BLINDS_F:format(Cards.Gold:Format(smallBlind), Cards.Gold:Format(bigBlind))
end

function HostPage:RefreshBlindSlider(running)
    if not self.blindSlider then
        return
    end
    if running == nil then
        running = Cards.Controller:IsRunning()
    end
    local rate = self.blindRate or Rules.BLIND_RATE_DEFAULT
    local smallBlind = self:GetBlindAmounts(rate)
    self.blindSlider:SetValue(rate)
    self.blindSlider:SetEnabled(smallBlind ~= nil and not running)
end

function HostPage:ReadSettings()
    local settings = Copy(self.draft)
    settings.buyIn = Cards.Gold:Parse(self.amounts.buyIn:GetText(), Cards.BUY_IN_MAX) or 0
    settings.smallBlind = Rules.SmallBlindForRate(settings.buyIn, self.blindRate or Rules.BLIND_RATE_DEFAULT) or 0
    settings.bigBlind = settings.smallBlind * 2
    return settings
end

function HostPage:Create(parent, layout)
    self.width = layout.width
    self.layout = layout
    self.amounts = {}
    self.labels = {}
    self.draft = Cards.Store:GetHostSettings()
    local form = layout.form
    local variantY = 0
    local buyInY = variantY - form.rowStep
    local blindsY = buyInY - form.rowStep
    local tableRulesY = blindsY - form.rowStep
    local rebuysY = tableRulesY - form.rowStep
    self.variant = CreateDropdown(
        self,
        parent,
        layout,
        "variant",
        L.W_VARIANT,
        L.VARIANT_TEXAS_HOLDEM,
        0,
        variantY,
        self.width,
        form.valueX,
        function(_, root)
            local selected = Cards.Store:GetSelectedVariant()
            for _, descriptor in ipairs(Cards.Variants:GetAll()) do
                root:CreateRadio(descriptor.title, function(value)
                    return value == selected
                end, function() end, descriptor.id)
            end
        end
    )
    self.variant:SetEnabled(false)
    self:CreateAmount(parent, layout, "buyIn", L.W_BUY_IN, 0, buyInY, self.width, form.valueX)
    self.blindSlider = Games.SettingsControls:Slider(
        parent,
        L.W_BLINDS,
        self.width,
        Rules.BLIND_RATE_DEFAULT,
        Rules.BLIND_RATE_MIN,
        Rules.BLIND_RATE_MAX,
        Rules.BLIND_RATE_STEP,
        function(rate)
            return self:FormatBlinds(rate)
        end,
        function(rate)
            self.blindRate = rate
        end,
        {
            labelWidth = form.valueX - form.gap,
            controlX = form.valueX,
            valueWidth = BLIND_VALUE_WIDTH,
            valueFont = BLIND_VALUE_FONT,
        }
    )
    self.labels.blinds = self.blindSlider.Label
    layout.Place(self.blindSlider, parent, 0, blindsY, self.width, self.blindSlider.layoutHeight)
    self.amounts.buyIn:SetScript("OnTextChanged", function()
        self:RefreshBlindSlider()
    end)

    local pairedWidth = (self.width - form.gap) / 2
    local pairedRight = pairedWidth + form.gap
    self.maxPlayers = CreateDropdown(
        self,
        parent,
        layout,
        "maxPlayers",
        L.W_MAX_PLAYERS,
        "",
        0,
        tableRulesY,
        pairedWidth,
        PAIRED_VALUE_X,
        function(_, root)
            local function IsSelected(value)
                return self.draft.maxPlayers == value
            end
            local function Select(value)
                self.draft.maxPlayers = value
                self.maxPlayers:SetDefaultText(tostring(value))
            end
            for value = Cards.MIN_PLAYERS, Cards.MAX_PLAYERS do
                root:CreateRadio(tostring(value), IsSelected, Select, value)
            end
        end
    )
    self.actionSeconds = CreateDropdown(
        self,
        parent,
        layout,
        "actionSeconds",
        L.W_ACTION_TIME,
        "",
        pairedRight,
        tableRulesY,
        pairedWidth,
        PAIRED_VALUE_X,
        function(_, root)
            local function IsSelected(value)
                return self.draft.actionSeconds == value
            end
            local function Select(value)
                self.draft.actionSeconds = value
                self.actionSeconds:SetDefaultText(L.W_ACTION_SECONDS_F:format(value))
            end
            for value = Cards.ACTION_SECONDS_MIN, Cards.ACTION_SECONDS_MAX, Cards.ACTION_SECONDS_STEP do
                root:CreateRadio(L.W_ACTION_SECONDS_F:format(value), IsSelected, Select, value)
            end
        end
    )
    self.rebuys = CreateDropdown(
        self,
        parent,
        layout,
        "rebuys",
        L.W_REBUYS,
        "",
        0,
        rebuysY,
        self.width,
        form.valueX,
        function(_, root)
            local function IsSelected(value)
                return self.draft.allowRebuys == value
            end
            local function Select(value)
                self.draft.allowRebuys = value
                self.rebuys:SetDefaultText(value and L.W_REBUYS_ON or L.W_REBUYS_OFF)
            end
            root:CreateRadio(L.W_REBUYS_ON, IsSelected, Select, true)
            root:CreateRadio(L.W_REBUYS_OFF, IsSelected, Select, false)
        end
    )
    self.footer = layout.CreateFooter(parent)
    self.open = layout.FooterButton(self.footer, L.W_START, function()
        local ok, reason = Games.Main:Start(self:ReadSettings())
        Games.UI.actionError = not ok and ErrorText(reason) or nil
        Games.UI:Refresh()
    end)
    self.save = layout.FooterButton(self.footer, L.W_SAVE, function()
        local ok, reason = Cards.Store:SaveHostSettings(self:ReadSettings())
        Games.UI.actionError = not ok and ErrorText(reason) or nil
        if ok then
            self:Load()
        end
        Games.UI:Refresh()
    end)
    self.deal = layout.FooterButton(self.footer, L.W_NEXT_HAND, function()
        local ok, reason = Cards.Controller:StartHand()
        Games.UI.actionError = not ok and ErrorText(reason) or nil
        Games.UI:Refresh()
    end)
    self.pause = layout.FooterButton(self.footer, L.W_PAUSE, function()
        local ok, reason
        if Cards.Controller.paused then
            ok, reason = Games.Main:Resume()
        else
            ok, reason = Games.Main:Pause()
        end
        Games.UI.actionError = not ok and ErrorText(reason) or nil
        Games.UI:Refresh()
    end)
    self.stop = layout.FooterButton(self.footer, L.W_STOP, function()
        local ok, reason = Games.Main:Stop()
        Games.UI.actionError = not ok and ErrorText(reason) or nil
        Games.UI:Refresh()
    end)
    self:Load()
end

function HostPage:Load()
    self.draft = Cards.Store:GetHostSettings()
    self.blindRate = Rules.BlindRateForSmallBlind(self.draft.buyIn, self.draft.smallBlind) or Rules.BLIND_RATE_DEFAULT
    self.amounts.buyIn:SetText(Cards.Gold:Format(self.draft.buyIn))
    self:RefreshBlindSlider()
    self.maxPlayers:SetDefaultText(tostring(self.draft.maxPlayers))
    self.actionSeconds:SetDefaultText(L.W_ACTION_SECONDS_F:format(self.draft.actionSeconds))
    self.rebuys:SetDefaultText(self.draft.allowRebuys and L.W_REBUYS_ON or L.W_REBUYS_OFF)
    for _, dropdown in ipairs({ self.variant, self.maxPlayers, self.actionSeconds, self.rebuys }) do
        dropdown:GenerateMenu()
    end
end

function HostPage:Refresh()
    local running = Cards.Controller:IsRunning()
    local restricted = Games.Main:IsRestricted()
    local view = Cards.Session:GetView()
    local betweenHands = view.state == "between_hands" or view.state == "complete"
    self.amounts.buyIn:SetEnabled(not running)
    self:RefreshBlindSlider(running)
    for _, dropdown in ipairs({ self.maxPlayers, self.actionSeconds, self.rebuys }) do
        dropdown:SetEnabled(not running)
    end
    self.open:SetShown(not running)
    self.save:SetShown(not running)
    self.deal:SetShown(running)
    self.pause:SetShown(running)
    self.stop:SetShown(running)
    Games.Controls:SetButtonState(self.open, not running and not restricted)
    Games.Controls:SetButtonState(self.save, not running)
    Games.Controls:SetButtonState(self.deal, running and betweenHands and not restricted)
    Games.Controls:SetButtonState(self.pause, running and not restricted)
    Games.Controls:SetButtonState(self.stop, running)
    self.pause:SetText(Cards.Controller.paused and L.W_RESUME or L.W_PAUSE)
    self.layout.LayoutFooterButtons(
        self.footer,
        running and { self.stop, self.pause, self.deal } or { self.save, self.open }
    )
end

function HostPage:GetNotice()
    return nil
end

function HostPage:CloseMenus()
    for _, dropdown in ipairs({ self.variant, self.maxPlayers, self.actionSeconds, self.rebuys }) do
        dropdown:CloseMenu()
    end
end

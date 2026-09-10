local _, Games = ...
local Quiz = Games.Quiz
local L = Quiz.L

local MENU_SCROLL_HEIGHT = 220
local MENU_MAX_WIDTH = 540

local HostPage = {}
Quiz.HostPage = HostPage

function HostPage:RefreshRules()
    local game = Quiz.Controller:IsRunning() and Quiz.Controller.game or nil
    local packId = game and game.settings.packId or self.draft.packId
    local rules, reason
    if game then
        rules = game.rules
    else
        rules, reason = Quiz:GetRules(packId)
    end
    self.rules, self.rulesPackId, self.rulesGame = rules, packId, game
    self.rulesError = not rules and (L.errors[reason] or reason or L.W_RULES_UNAVAILABLE) or nil
end

function HostPage:Create(parent, layout)
    self.width = layout.width
    self.layout = layout
    self.draft = Quiz.Store:GetSettings()
    local form = layout.form
    local valueWidth = self.width - form.valueX
    self.packLabel = layout.FormLabel(parent, L.PACK, 0, 0, form.valueX - form.gap)
    self.pack = layout.Dropdown(parent, L.ALL_PACKS, form.valueX, 0, valueWidth, function(_, root)
        root:SetScrollMode(MENU_SCROLL_HEIGHT)
        root:SetMaximumWidth(MENU_MAX_WIDTH)
        local function IsSelected(value)
            return self.draft.packId == value
        end
        local function Select(value)
            self.draft.packId = value
            self:RefreshRules()
            Games.UI:Refresh()
        end
        if Quiz:GetRules("all") then
            root:CreateRadio(L.ALL_PACKS, IsSelected, Select, "all")
        end
        for _, pack in ipairs(Quiz:GetPacks()) do
            root:CreateRadio(pack.title, IsSelected, Select, pack.id)
        end
    end)
    self.footer = layout.CreateFooter(parent)
    self.start = layout.FooterButton(self.footer, L.W_START, function()
        Games.Main:Start(self:ReadSettings())
    end)
    self.pause = layout.FooterButton(self.footer, L.W_PAUSE, function()
        if Quiz.Controller.game.state == "paused" then
            Games.Main:Resume()
        else
            Games.Main:Pause()
        end
    end)
    self.stop = layout.FooterButton(self.footer, L.W_STOP, function()
        Games.Main:Stop()
    end)
    self.save = layout.FooterButton(self.footer, L.APPLY, function()
        Quiz.Controller:SaveSettings(self:ReadSettings())
    end)
    self:Load()
end

function HostPage:Load()
    self.draft = Quiz.Store:GetSettings()
    self.pack:GenerateMenu()
    self:RefreshRules()
end

function HostPage:ReadSettings()
    local settings = Quiz.Store:GetSettings()
    settings.packId = self.draft.packId
    return settings
end

function HostPage:Refresh()
    local running = Quiz.Controller:IsRunning()
    local game = Quiz.Controller.game
    if self.rulesPackId ~= self.draft.packId or self.rulesGame ~= (running and game or nil) then
        self:RefreshRules()
    end
    self.pack:SetEnabled(not running)
    Games.Controls:SetButtonState(self.start, not running and self.rules ~= nil and not Games.Main:IsRestricted())
    Games.Controls:SetButtonState(self.pause, running and game.state ~= "finished")
    Games.Controls:SetButtonState(self.stop, running)
    self.pause:SetText(running and game.state == "paused" and L.W_RESUME or L.W_PAUSE)
    self.pause:SetShown(running)
    self.stop:SetShown(running)
    self.start:SetShown(not running)
    self.save:SetShown(not running)
    self.layout.LayoutFooterButtons(self.footer, running and { self.stop, self.pause } or { self.save, self.start })
end

function HostPage:GetNotice()
    local packErrors = Quiz:GetPackErrors()
    return self.rulesError or packErrors[1]
end

function HostPage:CloseMenus()
    self.pack:CloseMenu()
end

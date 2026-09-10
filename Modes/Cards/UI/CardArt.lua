local _, Games = ...
local Cards = Games.Cards

local TEXTURE = "Interface\\AddOns\\Orbit-Games\\Assets\\Cards\\PlayingCards.png"
local ATLAS_WIDTH = 2048
local ATLAS_HEIGHT = 512
local CARD_WIDTH = 128
local CARD_HEIGHT = 88
local FIRST_LEFT = 96
local FIRST_TOP = 20
local COLUMN_STEP = 144
local ROW_STEP = 96
local BACK_LEFT = 96
local BACK_TOP = 404
local DEALER_LEFT = 272
local DEALER_TOP = 416
local DEALER_WIDTH = 64
local DEALER_HEIGHT = 64
local RANK_COUNT = 13
local FLIP_HALF_SECONDS = 0.12
local FLIP_EDGE_SCALE = 0.08
local EMPTY_COLOR = { 0.08, 0.08, 0.08, 0.7 }
local SURFACE_COLOR = { 0.96, 0.95, 0.9, 1 }

local CardArt = {}
Cards.CardArt = CardArt

local function SetRegion(texture, left, top, width, height)
    texture:SetTexCoord(
        left / ATLAS_WIDTH,
        (left + width) / ATLAS_WIDTH,
        top / ATLAS_HEIGHT,
        (top + height) / ATLAS_HEIGHT
    )
end

local function SetCell(texture, left, top)
    SetRegion(texture, left, top, CARD_WIDTH, CARD_HEIGHT)
end

local function ApplyState(card, cardId, concealed)
    local visible = concealed or Cards.CardCatalog:IsCard(cardId)
    card.Face:SetShown(visible)
    card.Surface:SetShown(visible)
    card.Empty:SetShown(not visible)
    if not visible then
        return
    end
    if concealed then
        SetCell(card.Face, BACK_LEFT, BACK_TOP)
        return
    end
    local zeroBased = cardId - 1
    local column = zeroBased % RANK_COUNT
    local row = math.floor(zeroBased / RANK_COUNT)
    SetCell(card.Face, FIRST_LEFT + column * COLUMN_STEP, FIRST_TOP + row * ROW_STEP)
end

local function ConfigureFlip(group, fromScale, toScale, smoothing)
    local animation = group:CreateAnimation("Scale")
    animation:SetDuration(FLIP_HALF_SECONDS)
    animation:SetScaleFrom(fromScale, 1)
    animation:SetScaleTo(toScale, 1)
    animation:SetOrigin("CENTER", 0, 0)
    animation:SetSmoothing(smoothing)
    return animation
end

local function CancelFlip(card)
    card.FlipClose:Stop()
    card.FlipOpen:Stop()
    card.flipPending = nil
end

function CardArt:Create(parent, width, height)
    local card = CreateFrame("Frame", nil, parent)
    PixelUtil.SetSize(card, width, height)
    card.Empty = card:CreateTexture(nil, "BACKGROUND")
    card.Empty:SetAllPoints(card)
    card.Empty:SetColorTexture(unpack(EMPTY_COLOR))
    card.Surface = card:CreateTexture(nil, "BACKGROUND")
    card.Surface:SetAllPoints(card)
    card.Surface:SetColorTexture(unpack(SURFACE_COLOR))
    card.Surface:Hide()
    card.Face = card:CreateTexture(nil, "ARTWORK")
    card.Face:SetAllPoints(card)
    card.Face:SetTexture(TEXTURE)
    card.Face:Hide()
    card.FlipClose = card:CreateAnimationGroup()
    card.FlipClose.Animation = ConfigureFlip(card.FlipClose, 1, FLIP_EDGE_SCALE, "IN")
    card.FlipOpen = card:CreateAnimationGroup()
    card.FlipOpen.Animation = ConfigureFlip(card.FlipOpen, FLIP_EDGE_SCALE, 1, "OUT")
    card.FlipClose:SetScript("OnFinished", function()
        if not card.flipPending then
            return
        end
        ApplyState(card, card.cardId, card.concealed)
        card.FlipOpen:Play()
    end)
    card.FlipOpen:SetScript("OnFinished", function()
        card.flipPending = nil
    end)
    card.cardId, card.concealed = false, false
    return card
end

function CardArt:CreateDealerChip(parent)
    local chip = parent:CreateTexture(nil, "ARTWORK")
    chip:SetTexture(TEXTURE)
    SetRegion(chip, DEALER_LEFT, DEALER_TOP, DEALER_WIDTH, DEALER_HEIGHT)
    return chip
end

function CardArt:SetFlipDuration(card, seconds)
    local halfSeconds = seconds / 2
    card.FlipClose.Animation:SetDuration(halfSeconds)
    card.FlipOpen.Animation:SetDuration(halfSeconds)
end

function CardArt:Set(card, cardId, concealed)
    concealed = concealed == true
    if card.cardId == cardId and card.concealed == concealed and not card.flipPending then
        return
    end
    CancelFlip(card)
    card.cardId, card.concealed = cardId, concealed
    ApplyState(card, cardId, concealed)
end

function CardArt:Transition(card, cardId, concealed)
    concealed = concealed == true
    if card.cardId == cardId and card.concealed == concealed then
        return
    end
    local flipsToFace = card.concealed and not concealed
    local flipsToBack = not card.concealed and concealed and Cards.CardCatalog:IsCard(card.cardId)
    local flip = Cards.CardCatalog:IsCard(cardId) and (flipsToFace or flipsToBack)
    CancelFlip(card)
    card.cardId, card.concealed = cardId, concealed
    if not flip then
        ApplyState(card, cardId, concealed)
        return
    end
    card.flipPending = true
    card.FlipClose:Play()
end

local _, Quiz = ...

local CONTAINER_ATLAS = "housing-basic-container"
local DIVIDER_COLOR = { 0.3, 0.3, 0.3 }
local DIVIDER_PIXELS = 1

Quiz.DialogChrome = { dividers = {} }
local Chrome = Quiz.DialogChrome

local function LayoutDivider(divider, width)
    PixelUtil.SetWidth(divider, width)
    PixelUtil.SetHeight(divider, 0, DIVIDER_PIXELS)
    PixelUtil.SetWidth(divider.Left, divider:GetWidth() / 2)
end

function Chrome:Apply(frame)
    if frame.Chrome then
        return
    end
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    -- SetAtlas loads the housing container's native shader NineSlice data; a flat wash would replace its art.
    background:SetAtlas(CONTAINER_ATLAS)
    background:SetAllPoints(frame)
    frame.Chrome = { Background = background }
end

function Chrome:Divider(parent, width)
    local divider = CreateFrame("Frame", nil, parent)
    local r, g, b = unpack(DIVIDER_COLOR)
    local left = divider:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(1, 1, 1, 1)
    left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))
    left:SetPoint("TOPLEFT", divider, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", divider, "BOTTOMLEFT", 0, 0)
    local right = divider:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(1, 1, 1, 1)
    right:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0))
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", divider, "BOTTOMRIGHT", 0, 0)
    divider.Left, divider.Right = left, right
    self.dividers[divider] = width
    LayoutDivider(divider, width)
    return divider
end

function Chrome:RefreshScale()
    for divider, width in pairs(self.dividers) do
        LayoutDivider(divider, width)
    end
end

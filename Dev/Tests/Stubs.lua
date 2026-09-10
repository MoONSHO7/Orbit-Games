local SERVER_EPOCH = 1788048000
local MINIMAP_SIZE = 198
local UINT32_RANGE = 4294967296
local INT32_SIGN = 2147483648
local SOUND_DURATIONS = {
    dominating = 1.880091,
    ownage = 2.766122,
    rampage = 2.139184,
    ["wicked-sick"] = 2.766122,
    holyshit = 2.421859,
    godlike = 2.044490,
}

Test = {
    now = 100,
    locale = "enUS",
    messages = {},
    sent = {},
    addonSent = {},
    addonPrefixes = {},
    joins = {},
    joinAccepted = true,
    tickers = {},
    frames = {},
    animationGroups = {},
    animationCreations = 0,
    fontStringCreations = 0,
    fontObjectCreations = 0,
    textureCreations = 0,
    lineCreations = 0,
    maskCreations = 0,
    fontWidths = {},
    invalidFonts = {},
    errors = {},
    soundCalls = {},
    stoppedSounds = {},
    soundHandles = {},
    soundSequence = 0,
    soundClock = 0,
    soundDeadlines = {},
    soundChecks = 0,
    colorCreations = 0,
    cursorX = 0,
    cursorY = 0,
    physicalWidth = 1920,
    physicalHeight = 768,
    mouseButtons = {},
    restricted = false,
    encounter = false,
    guild = true,
    group = false,
    raid = true,
    instance = true,
    lobbyId = 8,
    lobbyName = "OrbitGamesLobby",
    lobbyJoined = false,
    lobbyType = 3,
    channelId = 7,
    channelName = "OrbitGames",
    hostGUID = "Player-0-HOST",
    hostName = "Quizhost",
    realm = "TestRealm",
}

strmatch = string.match
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE

function securecallfunction(callback, ...)
    return callback(...)
end

local function ToSignedUInt32(value)
    value = value % UINT32_RANGE
    return value >= INT32_SIGN and value - UINT32_RANGE or value
end

local function Bitwise(first, second, include)
    first, second = first % UINT32_RANGE, second % UINT32_RANGE
    local value, place = 0, 1
    for _ = 1, 32 do
        local firstBit, secondBit = first % 2, second % 2
        if include(firstBit, secondBit) then
            value = value + place
        end
        first, second, place = math.floor(first / 2), math.floor(second / 2), place * 2
    end
    return ToSignedUInt32(value)
end

bit = {
    band = function(first, second)
        return Bitwise(first, second, function(firstBit, secondBit)
            return firstBit == 1 and secondBit == 1
        end)
    end,
    bor = function(first, second)
        return Bitwise(first, second, function(firstBit, secondBit)
            return firstBit == 1 or secondBit == 1
        end)
    end,
    bxor = function(first, second)
        return Bitwise(first, second, function(firstBit, secondBit)
            return firstBit ~= secondBit
        end)
    end,
    lshift = function(value, places)
        return ToSignedUInt32(value * 2 ^ places)
    end,
    rshift = function(value, places)
        return math.floor(value % UINT32_RANGE / 2 ^ places)
    end,
}

local FontObject = {}
FontObject.__index = FontObject

function FontObject:GetFont()
    if self.path then
        return self.path, self.height, self.flags
    end
    if self.fontObject then
        return self.fontObject:GetFont()
    end
end

function FontObject:SetFont(path, height, flags)
    assert(type(path) == "string" and type(height) == "number", "native font object requires a path and height")
    self.fontCalls = (self.fontCalls or 0) + 1
    if Test.invalidFonts[path] == "throw" then
        error("simulated native font object asset failure")
    end
    if not Test.invalidFonts[path] then
        self.path, self.height, self.flags = path, height, flags or ""
    end
end

function FontObject:SetFontObject(font)
    self.fontObjectAssignments = (self.fontObjectAssignments or 0) + 1
    self.fontObject = type(font) == "string" and Test.fontObjects[font] or font
    assert(self.fontObject and self.fontObject ~= self, "font inheritance requires another real font object")
    self.path, self.height, self.flags = nil, nil, nil
end

function FontObject:GetFontObject()
    return self.fontObject
end

function FontObject:CopyFontObject(source)
    assert(
        type(source) == "table" and getmetatable(source) == FontObject,
        "font copy uses an actual native font object"
    )
    self.copyFontCalls = (self.copyFontCalls or 0) + 1
    self.path, self.height, self.flags = source:GetFont()
    self.shadowColor = { source:GetShadowColor() }
    self.shadowOffsetX, self.shadowOffsetY = source:GetShadowOffset()
    self.fontObject = source:GetFontObject()
end

function FontObject:GetName()
    return self.name
end

function FontObject:SetShadowColor(red, green, blue, alpha)
    self.shadowColor = { red, green, blue, alpha or 1 }
    self.shadowColorCalls = (self.shadowColorCalls or 0) + 1
end

function FontObject:GetShadowColor()
    if self.shadowColor then
        return unpack(self.shadowColor)
    end
    if self.fontObject then
        return self.fontObject:GetShadowColor()
    end
    return 0, 0, 0, 0
end

function FontObject:SetShadowOffset(x, y)
    self.shadowOffsetX, self.shadowOffsetY = x, y
    self.shadowOffsetCalls = (self.shadowOffsetCalls or 0) + 1
end

function FontObject:GetShadowOffset()
    if self.shadowOffsetX then
        return self.shadowOffsetX, self.shadowOffsetY
    end
    if self.fontObject then
        return self.fontObject:GetShadowOffset()
    end
    return 0, 0
end

Test.fontObjects = {}
for name, height in pairs({
    GameFontHighlight = 12,
    GameFontNormal = 12,
    GameFontHighlightSmall = 10,
    GameFontHighlightMedium = 14,
    GameFontNormalSmall = 10,
    GameFontDisableSmall = 10,
    GameFontHighlightLarge = 16,
    ChatFontNormal = 14,
}) do
    local font = setmetatable({ name = name, path = "Fonts\\MockNative.ttf", height = height, flags = "" }, FontObject)
    Test.fontObjects[name], _G[name] = font, font
end

function CreateFont(name)
    assert(type(name) == "string" and name ~= "", "a private font has an explicit native name")
    if Test.fontObjects[name] then
        return Test.fontObjects[name]
    end
    Test.fontObjectCreations = Test.fontObjectCreations + 1
    local font = setmetatable({ name = name }, FontObject)
    Test.fontObjects[name], _G[name] = font, font
    return font
end

Test.secret = setmetatable({}, {
    __index = function()
        error("accessed a secret field")
    end,
    __concat = function()
        error("concatenated a secret value")
    end,
    __tostring = function()
        error("converted a secret value")
    end,
})

function issecretvalue(value)
    return rawequal(value, Test.secret)
end

function GetLocale()
    return Test.locale
end

function GetTime()
    return Test.now
end

function PlaySoundFile(path, channel)
    assert(type(path) == "string" and path ~= "", "sound playback needs an asset path")
    assert(channel == "SFX", "streak announcements respect the SFX channel")
    Test.soundCalls[#Test.soundCalls + 1] = { path = path, channel = channel, time = Test.now }
    if Test.soundFailure == "throw" then
        error("simulated native sound asset failure")
    end
    if Test.soundMuted or Test.soundFailure then
        return false
    end
    Test.soundSequence = Test.soundSequence + 1
    local handle = Test.soundSequence
    Test.soundHandles[handle] = true
    local stem = path:match("([^\\]+)%.%w+$")
    stem = stem and stem:gsub("%-%d+$", "")
    local duration = Test.soundDuration or SOUND_DURATIONS[stem] or math.huge
    Test.soundDeadlines[handle] = Test.soundClock + duration + (Test.soundDelay or 0)
    return true, handle
end

function StopSound(handle)
    assert(type(handle) == "number", "only an owned sound handle can be stopped")
    Test.stoppedSounds[#Test.stoppedSounds + 1] = handle
    Test.soundHandles[handle] = nil
    Test.soundDeadlines[handle] = nil
end

function Test.AdvanceAudio(seconds)
    assert(type(seconds) == "number" and seconds >= 0, "audio time must advance forward")
    Test.soundClock = Test.soundClock + seconds
    for handle, deadline in pairs(Test.soundDeadlines) do
        if Test.soundClock >= deadline then
            Test.soundHandles[handle], Test.soundDeadlines[handle] = nil, nil
        end
    end
end

C_Sound = {
    IsPlaying = function(handle)
        assert(type(handle) == "number", "native playback checks require a sound handle")
        Test.soundChecks = Test.soundChecks + 1
        return Test.soundHandles[handle] == true
    end,
}

function GetCursorPosition()
    return Test.cursorX, Test.cursorY
end

function GetPhysicalScreenSize()
    return Test.physicalWidth, Test.physicalHeight
end

function IsMouseButtonDown(button)
    return Test.mouseButtons[button] == true
end

function CreateColor(red, green, blue, alpha)
    Test.colorCreations = Test.colorCreations + 1
    local color = { r = red, g = green, b = blue, a = alpha or 1 }
    function color:SetRGBA(newRed, newGreen, newBlue, newAlpha)
        self.r, self.g, self.b, self.a = newRed, newGreen, newBlue, newAlpha or 1
    end
    function color:GetRGBA()
        return self.r, self.g, self.b, self.a
    end
    return color
end

function wipe(values)
    for key in pairs(values) do
        values[key] = nil
    end
    return values
end

function GetServerTime()
    return SERVER_EPOCH + math.floor(Test.now)
end

function UnitGUID(unit)
    assert(unit == "player")
    return Test.hostGUID
end

function UnitFullName(unit)
    assert(unit == "player")
    return Test.hostName, Test.realm
end

function GetNormalizedRealmName()
    return Test.realm
end

function IsInGuild()
    return Test.guild
end

function IsInRaid(category)
    if category == LE_PARTY_CATEGORY_INSTANCE then
        return Test.instanceRaid == true
    end
    return Test.raid
end

function IsInGroup(category)
    if category == LE_PARTY_CATEGORY_HOME then
        return Test.group or Test.raid
    end
    return Test.instance
end

function GetChannelName(name)
    if
        (type(name) == "string" and name:lower() == Test.lobbyName:lower() or name == Test.lobbyId) and Test.lobbyJoined
    then
        return Test.lobbyId, Test.lobbyName
    end
    return 0, nil
end

function JoinChannelByName(name)
    assert(not Test.restricted, "joined a discovery channel while chat was restricted")
    Test.joins[#Test.joins + 1] = { name = name }
    if Test.joinAccepted then
        Test.lobbyJoined = true
        return Test.lobbyId, name
    end
end

function geterrorhandler()
    return function(reason)
        Test.errors[#Test.errors + 1] = reason
    end
end

LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2
Enum = {
    AddOnRestrictionType = { Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
    PermanentChatChannelType = { None = 0, Zone = 1, Communities = 2, Custom = 3 },
    RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, MaxPrefixes = 3 },
    SendAddonMessageResult = {
        Success = 0,
        InvalidPrefix = 1,
        InvalidMessage = 2,
        AddonMessageThrottle = 3,
        InvalidChatType = 4,
        NotInGroup = 5,
        TargetRequired = 6,
        InvalidChannel = 7,
        ChannelThrottle = 8,
        GeneralError = 9,
        NotInGuild = 10,
        AddOnMessageLockdown = 11,
        TargetOffline = 12,
    },
}

DEFAULT_CHAT_FRAME = {
    AddMessage = function()
        error("Orbit-Games must never write to a chat frame")
    end,
}
SELECTED_CHAT_FRAME = DEFAULT_CHAT_FRAME
SendChatMessage = function()
    error("Orbit-Games must never send visible chat")
end
print = function()
    error("Orbit-Games must never print to chat")
end

C_ChatInfo = {
    InChatMessagingLockdown = function()
        return Test.restricted
    end,
    RegisterAddonMessagePrefix = function(prefix)
        assert(type(prefix) == "string" and #prefix > 0 and #prefix <= 16, "invalid addon prefix")
        if Test.addonRegisterResult ~= nil then
            return Test.addonRegisterResult
        end
        if Test.addonPrefixes[prefix] then
            return Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix
        end
        Test.addonPrefixes[prefix] = true
        return Enum.RegisterAddonMessagePrefixResult.Success
    end,
    SendAddonMessage = function(prefix, text, channel, target)
        assert(not Test.restricted, "sent addon message while chat was restricted")
        assert(Test.addonPrefixes[prefix], "addon prefix was not registered")
        assert(type(text) == "string" and #text <= 255, "invalid addon message")
        if prefix == "ORBITGAMES1" then
            assert(channel == "WHISPER", "game payloads must use targeted whispers")
        else
            assert(prefix == "ORBITGAMESDISC2", "unknown addon prefix")
            assert(
                channel == "WHISPER"
                    or channel == "CHANNEL"
                    or channel == "GUILD"
                    or channel == "PARTY"
                    or channel == "RAID"
                    or channel == "INSTANCE_CHAT",
                "invalid discovery route"
            )
        end
        if channel == "WHISPER" then
            assert(type(target) == "string" and target ~= "", "addon whisper requires a target")
        elseif channel == "CHANNEL" then
            assert(target == tostring(Test.lobbyId) and Test.lobbyJoined, "discovery channel must be the joined lobby")
        end
        local entry = { prefix = prefix, text = text, channel = channel, target = target }
        Test.addonSent[#Test.addonSent + 1] = entry
        if Test.onAddonSend then
            return Test.onAddonSend(entry)
        end
        return Test.addonSendResult or Enum.SendAddonMessageResult.Success
    end,
    GetChannelInfoFromIdentifier = function(identifier)
        assert(type(identifier) == "string", "channel identifier must be a string")
        if Test.channelInfoOverride ~= nil then
            return Test.channelInfoOverride
        end
        if
            Test.lobbyJoined and (identifier:lower() == Test.lobbyName:lower() or identifier == tostring(Test.lobbyId))
        then
            return {
                name = Test.lobbyName,
                localID = Test.lobbyId,
                channelType = Test.lobbyType,
                zoneChannelID = 0,
                instanceID = 0,
            }
        end
    end,
    SendChatMessage = function()
        error("Orbit-Games must never send visible chat")
    end,
}

C_InstanceEncounter = {
    IsEncounterInProgress = function()
        return Test.encounter
    end,
}

C_Timer = {
    NewTicker = function(interval, callback)
        local ticker = { interval = interval, callback = callback, active = true }
        function ticker:Cancel()
            self.active = false
        end
        Test.tickers[#Test.tickers + 1] = ticker
        return ticker
    end,
}

local Widget = {}
Widget.__index = Widget

local function NewWidget(kind, name, parent)
    local widget = setmetatable({
        kind = kind,
        name = name,
        parent = parent,
        shown = true,
        enabled = true,
        scripts = {},
        text = "",
        children = {},
    }, Widget)
    if parent then
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = widget
    end
    return widget
end

local Animation = {}
Animation.__index = Animation
for method, field in pairs({
    Duration = "duration",
    StartDelay = "startDelay",
    EndDelay = "endDelay",
    Order = "order",
    Smoothing = "smoothing",
    FromAlpha = "fromAlpha",
    ToAlpha = "toAlpha",
}) do
    local property = field
    Animation["Set" .. method] = function(self, value)
        self[property] = value
    end
    Animation["Get" .. method] = function(self)
        return self[property]
    end
end

function Animation:GetParent()
    return self.parent
end

function Animation:GetRegionParent()
    return self.parent.parent
end

function Animation:SetTarget(target)
    assert(type(target) == "table" and target.kind, "native animations target a script object")
    self.target = target
    return true
end

function Animation:GetTarget()
    return self.target or self:GetRegionParent()
end

function Animation:SetOffset(x, y)
    assert(self.kind == "Translation", "offsets belong to a native Translation animation")
    self.offsetX, self.offsetY = x, y
end

function Animation:GetOffset()
    return self.offsetX, self.offsetY
end

function Animation:SetScaleFrom(x, y)
    assert(self.kind == "Scale", "scale endpoints belong to a native Scale animation")
    assert(type(x) == "number" and type(y) == "number", "native scale endpoints require both axes")
    self.scaleFromX, self.scaleFromY = x, y
end

function Animation:GetScaleFrom()
    return self.scaleFromX or 1, self.scaleFromY or 1
end

function Animation:SetScaleTo(x, y)
    assert(self.kind == "Scale", "scale endpoints belong to a native Scale animation")
    assert(type(x) == "number" and type(y) == "number", "native scale endpoints require both axes")
    self.scaleToX, self.scaleToY = x, y
end

function Animation:GetScaleTo()
    return self.scaleToX or 1, self.scaleToY or 1
end

function Animation:SetOrigin(point, x, y)
    assert(self.kind == "Scale", "the mock only implements origins for Scale animations")
    assert(
        type(point) == "string" and type(x) == "number" and type(y) == "number",
        "origin requires a point and offsets"
    )
    self.originPoint, self.originX, self.originY = point, x, y
end

function Animation:GetOrigin()
    return self.originPoint or "CENTER", self.originX or 0, self.originY or 0
end

local AnimationGroup = {}
AnimationGroup.__index = AnimationGroup

function AnimationGroup:GetParent()
    return self.parent
end

function AnimationGroup:CreateAnimation(kind, name, template)
    assert(
        kind == "Translation" or kind == "Alpha" or kind == "Scale",
        "mock only implements native animation types in use"
    )
    assert(template == nil, "mock animations do not implement native templates")
    local animation = setmetatable({
        kind = kind,
        name = name,
        parent = self,
        duration = 0,
        startDelay = 0,
        endDelay = 0,
        order = 1,
        smoothing = "NONE",
        offsetX = 0,
        offsetY = 0,
    }, Animation)
    self.animations[#self.animations + 1] = animation
    Test.animationCreations = Test.animationCreations + 1
    return animation
end

function AnimationGroup:GetAnimations()
    return unpack(self.animations)
end

function AnimationGroup:GetDuration()
    local orders, duration = {}, 0
    for _, animation in ipairs(self.animations) do
        orders[animation.order] =
            math.max(orders[animation.order] or 0, animation.startDelay + animation.duration + animation.endDelay)
    end
    for _, length in pairs(orders) do
        duration = duration + length
    end
    return duration
end

function AnimationGroup:SetScript(name, script)
    assert(name == "OnPlay" or name == "OnStop" or name == "OnFinished", "unsupported animation callback in mock")
    self.scripts[name] = script
end

function AnimationGroup:GetScript(name)
    return self.scripts[name]
end

function AnimationGroup:SetLooping(looping)
    assert(looping == "NONE" or looping == "REPEAT", "mock only advances one-shot or repeating native groups")
    self.looping = looping
end

function AnimationGroup:GetLooping()
    return self.looping
end

function AnimationGroup:SetToFinalAlpha(enabled)
    assert(type(enabled) == "boolean", "native final-alpha mode is a boolean")
    self.toFinalAlpha = enabled
end

function AnimationGroup:IsSetToFinalAlpha()
    return self.toFinalAlpha == true
end

function AnimationGroup:IsPlaying()
    return self.playing
end

function AnimationGroup:Play(reverse, offset)
    assert(not reverse, "mock only advances forward animations")
    self.playCalls = self.playCalls + 1
    self.playing, self.elapsed = true, offset or 0
    if self.scripts.OnPlay then
        self.scripts.OnPlay(self)
    end
end

function AnimationGroup:Stop()
    self.stopCalls = self.stopCalls + 1
    if not self.playing then
        return
    end
    self.playing = false
    if self.scripts.OnStop then
        self.scripts.OnStop(self)
    end
end

function Widget:CreateAnimationGroup(name, template)
    assert(template == nil, "mock animation groups do not implement native templates")
    local group = setmetatable({
        kind = "AnimationGroup",
        name = name,
        parent = self,
        animations = {},
        scripts = {},
        playing = false,
        looping = "NONE",
        elapsed = 0,
        playCalls = 0,
        stopCalls = 0,
        finishCalls = 0,
    }, AnimationGroup)
    self.animationGroups = self.animationGroups or {}
    self.animationGroups[#self.animationGroups + 1] = group
    Test.animationGroups[#Test.animationGroups + 1] = group
    return group
end

function Widget:GetAnimationGroups()
    return unpack(self.animationGroups or {})
end

function Test.AdvanceAnimations(seconds)
    assert(type(seconds) == "number" and seconds >= 0, "animation time must advance forward")
    local advancing = {}
    for _, group in ipairs(Test.animationGroups) do
        if group.playing then
            advancing[#advancing + 1] = { group = group, plays = group.playCalls }
        end
    end
    Test.AdvanceAudio(seconds)
    for _, entry in ipairs(advancing) do
        local group = entry.group
        if group.playing and group.playCalls == entry.plays then
            group.elapsed = group.elapsed + seconds
            local duration = group:GetDuration()
            if group.looping == "REPEAT" then
                assert(duration > 0, "repeating native groups need a positive duration")
                group.elapsed = group.elapsed % duration
            elseif group.elapsed >= duration then
                group.playing = false
                group.finishCalls = group.finishCalls + 1
                if group.toFinalAlpha then
                    local finalAlphas = {}
                    for _, animation in ipairs(group.animations) do
                        if animation.kind == "Alpha" then
                            local target, previous = animation:GetTarget(), finalAlphas[animation:GetTarget()]
                            local finish = animation.startDelay + animation.duration + animation.endDelay
                            if
                                not previous
                                or animation.order > previous.order
                                or animation.order == previous.order and finish >= previous.finish
                            then
                                finalAlphas[target] =
                                    { order = animation.order, finish = finish, alpha = animation.toAlpha }
                            end
                        end
                    end
                    for target, final in pairs(finalAlphas) do
                        target:SetAlpha(final.alpha)
                    end
                end
                if group.scripts.OnFinished then
                    group.scripts.OnFinished(group, false)
                end
            end
        end
    end
end

function Widget:SetPoint(...)
    self.setPointCalls = (self.setPointCalls or 0) + 1
    self.point = { ... }
    self.points = self.points or {}
    self.points[self.point[1]] = self.point
    self.mockCenterX, self.mockCenterY = nil, nil
end

function Widget:ClearAllPoints()
    self.clearPointCalls = (self.clearPointCalls or 0) + 1
    self.point = nil
    self.points, self.allPoints = nil, nil
end

function Widget:SetWidth(width)
    self:SetSize(width, self.height)
end

function Widget:GetWidth()
    local _, _, width = self:GetScaledRect()
    return width / self:GetEffectiveScale()
end

function Widget:SetHeight(height)
    self:SetSize(self.width, height)
end

function Widget:GetHeight()
    local _, _, _, height = self:GetScaledRect()
    return height / self:GetEffectiveScale()
end

function Widget:SetSize(width, height)
    self.sizeCalls = (self.sizeCalls or 0) + 1
    local changed = self.width ~= width or self.height ~= height
    self.width, self.height = width, height
    if changed and self.scripts.OnSizeChanged then
        self.scripts.OnSizeChanged(self, self:GetWidth(), self:GetHeight())
    end
    if changed and self.parent and self.parent.kind == "ScrollFrame" and self.parent.child == self then
        self.parent:UpdateScrollChildRect()
    end
end

function Widget:GetSize()
    return self:GetWidth(), self:GetHeight()
end

function Widget:GetEffectiveScale()
    return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
end

function Widget:SetScale(scale)
    assert(scale > 0, "frame scale must be positive")
    self.scale = scale
end

function Widget:GetScale()
    return self.scale or 1
end

function Widget:GetParent()
    return self.parent
end

function Widget:GetName()
    return self.name
end

function Widget:SetParent(parent)
    self.parent = parent
end

function Widget:SetAllPoints(relative)
    self.allPointCalls = (self.allPointCalls or 0) + 1
    self.points, self.point = nil, nil
    self.allPoints = relative or self.parent
end

local ANCHORS = {
    TOPLEFT = { 0, 1 },
    TOP = { 0.5, 1 },
    TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 },
    CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 },
    BOTTOM = { 0.5, 0 },
    BOTTOMRIGHT = { 1, 0 },
}

local function AnchorPosition(self, point)
    local relative, relativePoint, x, y = point[2], point[3], point[4], point[5]
    if type(relative) == "number" then
        x, y, relative, relativePoint = relative, relativePoint, self.parent or UIParent, point[1]
    elseif type(relativePoint) == "number" then
        x, y, relativePoint = relativePoint, x, point[1]
    end
    relative, relativePoint = relative or self.parent or UIParent, relativePoint or point[1]
    local left, bottom, width, height = relative:GetScaledRect()
    local target, scale = ANCHORS[relativePoint], self:GetEffectiveScale()
    return left + target[1] * width + (x or 0) * scale, bottom + target[2] * height + (y or 0) * scale
end

function Widget:GetScaledRect()
    local scale = self:GetEffectiveScale()
    local width, height = (self.width or 100) * scale, (self.height or 20) * scale
    if self.mockCenterX then
        return self.mockCenterX * scale - width / 2, self.mockCenterY * scale - height / 2, width, height
    end
    if self == UIParent then
        return 0, 0, width, height
    end
    if self.allPoints then
        return self.allPoints:GetScaledRect()
    end
    if not self.point and self.parent and self.parent.kind == "ScrollFrame" and self.parent.child == self then
        local left, bottom, _, viewportHeight = self.parent:GetScaledRect()
        local offset = self.parent:GetVerticalScroll() * self.parent:GetEffectiveScale()
        return left, bottom + viewportHeight - height + offset, width, height
    end
    local point = self.point or { "CENTER", self.parent or UIParent, "CENTER", 0, 0 }
    local x, y = AnchorPosition(self, point)
    local source = ANCHORS[point[1]]
    for anchor, other in pairs(self.points or {}) do
        local target = ANCHORS[anchor]
        local otherX, otherY = AnchorPosition(self, other)
        if source[1] ~= target[1] then
            width = (x - otherX) / (source[1] - target[1])
        end
        if source[2] ~= target[2] then
            height = (y - otherY) / (source[2] - target[2])
        end
    end
    return x - source[1] * width, y - source[2] * height, width, height
end

function Widget:GetRect()
    local left, bottom, width, height = self:GetScaledRect()
    local scale = self:GetEffectiveScale()
    return left / scale, bottom / scale, width / scale, height / scale
end

function Widget:GetLeft()
    local left = self:GetRect()
    return left
end

function Widget:GetRight()
    local left, _, width = self:GetRect()
    return left + width
end

function Widget:GetBottom()
    local _, bottom = self:GetRect()
    return bottom
end

function Widget:GetTop()
    local _, bottom, _, height = self:GetRect()
    return bottom + height
end

function Widget:GetCenter()
    local left, bottom, width, height = self:GetScaledRect()
    local scale = self:GetEffectiveScale()
    return (left + width / 2) / scale, (bottom + height / 2) / scale
end

function Widget:SetFrameLevel(level)
    self.level = level
end

function Widget:GetFrameLevel()
    return self.level or self.parent and self.parent:GetFrameLevel() + 1 or 0
end

function Widget:SetFrameStrata(strata)
    self.strata = strata
end

function Widget:SetFixedFrameLevel(fixed)
    self.fixedFrameLevel = fixed
end

function Widget:SetFixedFrameStrata(fixed)
    self.fixedFrameStrata = fixed
end

function Widget:GetFrameStrata()
    return self.strata or self.parent and self.parent:GetFrameStrata() or "MEDIUM"
end

function Widget:SetAlpha(alpha)
    self.alpha = alpha
end

function Widget:GetAlpha()
    return self.alpha or 1
end

function Widget:GetTextColor()
    return unpack(self.textColor or { 1, 1, 1, 1 })
end

function Widget:SetTextColor(...)
    self.textColor = { ... }
end

function Widget:SetColorTexture(...)
    self.color = { ... }
    self.atlas, self.texture = nil, nil
end

function Widget:SetTexture(texture)
    self.texture, self.atlas, self.color = texture, nil, nil
end

function Widget:GetTexture()
    return self.texture
end

function Widget:SetMinMaxValues(minimum, maximum)
    assert(self.kind == "StatusBar" or self.kind == "Slider", "numeric range belongs to a StatusBar or Slider")
    assert(type(minimum) == "number" and type(maximum) == "number" and minimum <= maximum, "invalid bar range")
    self.minimum, self.maximum = minimum, maximum
end

function Widget:GetMinMaxValues()
    assert(self.kind == "StatusBar" or self.kind == "Slider", "value range belongs to a StatusBar or Slider")
    return self.minimum, self.maximum
end

function Widget:SetValue(value)
    assert(self.kind == "StatusBar" or self.kind == "Slider", "numeric values belong to a StatusBar or Slider")
    assert(type(value) == "number", "bar or slider value must be numeric")
    local previous = self.value
    self.value = math.max(self.minimum or 0, math.min(self.maximum or 1, value))
    if self.kind == "Slider" and self.value ~= previous and self.scripts.OnValueChanged then
        self.scripts.OnValueChanged(self, self.value, false)
    end
end

function Widget:GetValue()
    assert(self.kind == "StatusBar" or self.kind == "Slider", "value belongs to a StatusBar or Slider")
    return self.value or 0
end

function Widget:SetValueStep(step)
    assert(self.kind == "Slider", "only a native Slider has value steps")
    self.valueStep = step
end

function Widget:GetValueStep()
    return self.valueStep
end

function Widget:SetObeyStepOnDrag(obey)
    self.obeyStepOnDrag = obey
end

function Widget:SetOrientation(orientation)
    assert(self.kind == "Slider", "orientation belongs to a Slider")
    assert(orientation == "HORIZONTAL" or orientation == "VERTICAL", "invalid slider orientation")
    self.orientation = orientation
end

function Widget:GetOrientation()
    assert(self.kind == "Slider", "orientation belongs to a Slider")
    return self.orientation
end

function Widget:SetThumbTexture(asset)
    assert(self.kind == "Slider", "thumb textures belong to a Slider")
    local thumb = self.thumbTexture or self.Thumb or self:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(asset)
    self.thumbTexture, self.Thumb = thumb, thumb
end

function Widget:GetThumbTexture()
    assert(self.kind == "Slider", "thumb textures belong to a Slider")
    return self.thumbTexture or self.Thumb
end

function Widget:GetObeyStepOnDrag()
    return self.obeyStepOnDrag
end

function Test.DragSlider(slider, value)
    assert(slider.kind == "Slider" and slider:IsEnabled(), "drag requires an enabled native slider")
    if slider.obeyStepOnDrag then
        value = slider.minimum + math.floor((value - slider.minimum) / slider.valueStep + 0.5) * slider.valueStep
    end
    slider:SetValue(value)
end

function Widget:SetStatusBarTexture(texture)
    assert(self.kind == "StatusBar", "status-bar fill belongs to a StatusBar")
    assert(type(texture) == "table" and texture.kind == "Texture", "test bars use an owned native Texture")
    self.statusBarTexture = texture
    return true
end

function Widget:GetStatusBarTexture()
    assert(self.kind == "StatusBar", "only StatusBar exposes its fill texture")
    return self.statusBarTexture
end

function Widget:SetStatusBarColor(red, green, blue, alpha)
    assert(self.kind == "StatusBar", "status-bar colors belong to a StatusBar")
    self.statusBarColor = { red, green, blue, alpha or 1 }
end

function Widget:GetStatusBarColor()
    assert(self.kind == "StatusBar", "only StatusBar exposes a bar color")
    return unpack(self.statusBarColor or { 1, 1, 1, 1 })
end

function Widget:SetAtlas(atlas, useAtlasSize, filterMode, resetTexCoords, wrapHorizontal, wrapVertical)
    assert(type(atlas) == "string" and atlas ~= "", "atlas must be named")
    self.atlas, self.useAtlasSize = atlas, useAtlasSize
    self.color, self.texture = nil, nil
    self.filterMode, self.resetTexCoords = filterMode, resetTexCoords
    self.wrapHorizontal, self.wrapVertical = wrapHorizontal, wrapVertical
end

function Widget:GetAtlas()
    return self.atlas
end

function Widget:SetTexCoord(...)
    self.texCoord = { ... }
end

function Widget:SetVertexColor(...)
    self.vertexColor = { ... }
end

function Widget:SetDesaturated(desaturated)
    assert(self.kind == "Texture", "only textures can be desaturated")
    self.desaturated = desaturated == true
end

function Widget:IsDesaturated()
    assert(self.kind == "Texture", "only textures expose desaturation")
    return self.desaturated == true
end

function Widget:GetVertexColor()
    local color = self.vertexColor or { 1, 1, 1, 1 }
    return color[1], color[2], color[3], color[4] or 1
end

function Widget:SetRotation(rotation)
    self.rotation = rotation
end

function Widget:SetBlendMode(mode)
    self.blendMode = mode
end

function Widget:SetGradient(orientation, first, second)
    self.gradient = { orientation, first, second }
    self.gradientColors = { { first:GetRGBA() }, { second:GetRGBA() } }
    self.gradientCalls = (self.gradientCalls or 0) + 1
    self.gradientBarValue = self.parent and self.parent.kind == "StatusBar" and self.parent:GetValue() or nil
end

function Widget:SetDrawLayer(layer, sublevel)
    self.drawLayer, self.drawSublevel = layer, sublevel
end

function Widget:SetBackdrop(backdrop)
    assert(self.template and self.template:find("BackdropTemplate", 1, true), "backdrop requires BackdropTemplate")
    self.backdrop = backdrop
end

function Widget:GetBackdrop()
    return self.backdrop
end

function Widget:SetBackdropColor(...)
    self.backdropColor = { ... }
end

function Widget:GetBackdropColor()
    return unpack(self.backdropColor)
end

function Widget:SetBackdropBorderColor(...)
    self.backdropBorderColor = { ... }
end

function Widget:GetBackdropBorderColor()
    return unpack(self.backdropBorderColor)
end

function Widget:SetClipsChildren(value)
    self.clipsChildren = value
end

function Widget:SetNormalFontObject(font)
    self.normalFont = font
end

function Widget:SetHighlightFontObject(font)
    self.highlightFont = font
end

function Widget:SetDisabledFontObject(font)
    self.disabledFont = font
end

function Widget:SetFontObject(font)
    self.fontObjectAssignments = (self.fontObjectAssignments or 0) + 1
    self.fontObject = type(font) == "string" and Test.fontObjects[font] or font
    assert(self.fontObject, "unknown native font object")
    self.font = self.fontObject.name
    self.fontPath, self.fontHeight, self.fontFlags = nil, nil, nil
    self.textColor, self.justifyH, self.justifyV = { 1, 1, 1, 1 }, "CENTER", "MIDDLE"
end

function Widget:GetFontObject()
    return self.fontObject
end

function Widget:GetFont()
    if self.fontPath then
        return self.fontPath, self.fontHeight, self.fontFlags
    end
    return self.fontObject:GetFont()
end

function Widget:SetFont(path, height, flags)
    assert(type(path) == "string" and type(height) == "number", "native font requires a path and height")
    self.fontCalls = (self.fontCalls or 0) + 1
    if Test.invalidFonts[path] == "throw" then
        error("simulated native font asset failure")
    end
    if Test.invalidFonts[path] then
        return false
    end
    self.fontPath, self.fontHeight, self.fontFlags = path, height, flags or ""
    return true
end

function Widget:SetShadowColor(red, green, blue, alpha)
    self.shadowColor = { red, green, blue, alpha or 1 }
    self.shadowColorCalls = (self.shadowColorCalls or 0) + 1
end

function Widget:GetShadowColor()
    if self.shadowColor then
        return unpack(self.shadowColor)
    end
    if self.fontObject then
        return self.fontObject:GetShadowColor()
    end
    return 0, 0, 0, 0
end

function Widget:SetShadowOffset(x, y)
    self.shadowOffsetX, self.shadowOffsetY = x, y
    self.shadowOffsetCalls = (self.shadowOffsetCalls or 0) + 1
end

function Widget:GetShadowOffset()
    if self.shadowOffsetX then
        return self.shadowOffsetX, self.shadowOffsetY
    end
    if self.fontObject then
        return self.fontObject:GetShadowOffset()
    end
    return 0, 0
end

function Widget:SetFontString(fontString)
    self.nativeFontString = fontString
end

function Widget:GetFontString()
    return self.nativeFontString
end

function Widget:GetUnboundedStringWidthForText(text)
    local path, height = self.fontPath, self.fontHeight
    if self.fontObject then
        path, height = self:GetFont()
    end
    local width, glyphWidths = 0, Test.fontGlyphWidths and Test.fontGlyphWidths[path]
    local defaultWidth = Test.fontWidths[path] or 7
    for glyph in text:gmatch(".") do
        width = width + (glyphWidths and glyphWidths[glyph] or defaultWidth)
    end
    return width * (height or 12) / 12
end

function Widget:GetStringWidth()
    return self:GetUnboundedStringWidthForText(self.text)
end

function Widget:CreateTexture(name, layer, template, sublevel)
    Test.textureCreations = Test.textureCreations + 1
    local texture = NewWidget("Texture", name, self)
    texture.template, texture.drawLayer, texture.drawSublevel = template, layer, sublevel
    self.textures = self.textures or {}
    self.textures[#self.textures + 1] = texture
    return texture
end

function Widget:CreateLine(name, layer, template, sublevel)
    Test.lineCreations = Test.lineCreations + 1
    local line = NewWidget("Line", name, self)
    line.template, line.drawLayer, line.drawSublevel = template, layer, sublevel
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = line
    return line
end

function Widget:SetStartPoint(...)
    self.startPoint = { ... }
end

function Widget:SetEndPoint(...)
    self.endPoint = { ... }
end

function Widget:SetThickness(thickness)
    self.thickness = thickness
end

function Widget:GetThickness()
    return self.thickness
end

function Widget:CreateMaskTexture(name, layer, template, sublevel)
    Test.maskCreations = Test.maskCreations + 1
    local mask = NewWidget("MaskTexture", name, self)
    mask.template, mask.drawLayer, mask.drawSublevel = template, layer, sublevel
    self.maskTextures = self.maskTextures or {}
    self.maskTextures[#self.maskTextures + 1] = mask
    return mask
end

function Widget:AddMaskTexture(mask)
    assert(self.kind == "Texture" and mask.kind == "MaskTexture", "mask attachment requires native textures")
    self.masks = self.masks or {}
    for _, attached in ipairs(self.masks) do
        if attached == mask then
            return
        end
    end
    assert(#self.masks < 3, "native textures accept at most three masks")
    self.masks[#self.masks + 1] = mask
end

function Widget:GetMaskTexture(index)
    assert(self.kind == "Texture", "only textures have attached masks")
    return self.masks and self.masks[index]
end

function Widget:SetTextInsets(...)
    self.insets = { ... }
end

function Widget:SetCursorPosition(value)
    self.cursor = value
end

function Widget:SetFocus()
    local changed = not self.focused
    self.focused = true
    if changed and self.scripts.OnEditFocusGained then
        self.scripts.OnEditFocusGained(self)
    end
end

function Widget:HasFocus()
    return self.focused == true
end

function Widget:EnableMouseWheel(value)
    self.mouseWheel = value
end

function Widget:IsEnabled()
    return self.enabled
end

function Widget:SetText(text)
    self.textCalls = (self.textCalls or 0) + 1
    self.explicitHeightAtSetText = self.height
    self.widthAtSetText = self.width
    local changed = self.text ~= text
    self.text = text
    local label = self.kind == "DropdownButton" and self.Text or self.nativeFontString
    if label then
        label:SetText(text)
    end
    if changed and self.kind == "EditBox" and self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self, false)
    end
end

function Widget:GetText()
    return self.text
end

function Widget:SetOwner(owner, anchor)
    assert(self.kind == "GameTooltip", "tooltip ownership belongs to a native GameTooltip")
    self.owner, self.ownerAnchor = owner, anchor
    self.ownerCalls = (self.ownerCalls or 0) + 1
    self.lines = {}
end

function Widget:AddLine(text, ...)
    assert(self.kind == "GameTooltip" and type(text) == "string", "tooltip lines require plain text")
    self.lines[#self.lines + 1] = { text, ... }
end

function Widget:AddDoubleLine(leftText, rightText, ...)
    assert(
        self.kind == "GameTooltip" and type(leftText) == "string" and type(rightText) == "string",
        "tooltip double lines require plain left and right text"
    )
    self.lines[#self.lines + 1] = { leftText, rightText, ... }
end

function Widget:NumLines()
    return #self.lines
end

function Widget:GetStringHeight()
    local fontHeight = self.fontObject and select(2, self:GetFont())
    local lineHeight = self.measureLineHeight or (fontHeight or 12) + 2
    local measured =
        math.max(lineHeight, math.ceil(self:GetStringWidth() / math.max(1, self.width or 100)) * lineHeight)
    self.stringHeightMeasurements = (self.stringHeightMeasurements or 0) + 1
    self.lastStringHeightMeasurement = {
        explicitHeight = self.height,
        width = self.width,
        wordWrap = self.wordWrap,
        nonSpaceWrap = self.nonSpaceWrap,
        maxLines = self.maxLines,
        text = self.text,
        requiredHeight = measured,
        fontHeight = fontHeight,
    }
    return measured
end

function Widget:SetJustifyH(value)
    self.justifyH = value
end

function Widget:GetJustifyH()
    return self.justifyH or "CENTER"
end

function Widget:SetJustifyV(value)
    self.justifyV = value
end

function Widget:GetJustifyV()
    return self.justifyV or "MIDDLE"
end

function Widget:SetWordWrap(value)
    self.wordWrap = value
end

function Widget:SetNonSpaceWrap(value)
    self.nonSpaceWrap = value
end

function Widget:SetMaxLines(value)
    assert(type(value) == "number" and value >= 0, "FontString maximum lines must be nonnegative")
    self.maxLines = value
end

function Widget:GetMaxLines()
    return self.maxLines or 0
end

function Widget:CreateFontString(name, layer, font)
    Test.fontStringCreations = Test.fontStringCreations + 1
    local label = NewWidget("FontString", name, self)
    label.drawLayer, label.font = layer, font
    label.fontObject = type(font) == "string" and Test.fontObjects[font] or font
    self.fontStrings = self.fontStrings or {}
    self.fontStrings[#self.fontStrings + 1] = label
    return label
end

function Widget:SetScript(name, script)
    self.scripts[name] = script
end

function Widget:GetScript(name)
    return self.scripts[name]
end

function Widget:HookScript(name, script)
    local original = self.scripts[name]
    self.scripts[name] = function(...)
        if original then
            original(...)
        end
        script(...)
    end
end

function Widget:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end

function Widget:UnregisterEvent(event)
    if self.events then
        self.events[event] = nil
    end
end

function Widget:SetMovable(value)
    self.movable = value
end

function Widget:SetClampedToScreen(value)
    self.clamped = value
end

function Widget:EnableMouse(value)
    self.mouse = value
end

function Widget:RegisterForDrag(value)
    self.drag = value
end

function Widget:RegisterForClicks(...)
    self.clicks = { ... }
end

function Widget:SetHighlightTexture(texture)
    self.highlightTexture = texture
end

function Widget:LockHighlight()
    self.highlightLocked = true
end

function Widget:UnlockHighlight()
    self.highlightLocked = false
end

function Widget:StartMoving()
    self.moving = true
end

function Widget:StopMovingOrSizing()
    self.moving = false
end

local function DispatchVisibility(widget, script)
    if widget.scripts[script] then
        widget.scripts[script](widget)
    end
    for _, child in ipairs(widget.children) do
        if child.shown then
            DispatchVisibility(child, script)
        end
    end
end

function Widget:Show()
    self.showCalls = (self.showCalls or 0) + 1
    local wasVisible = self:IsVisible()
    local changed = not self.shown
    self.shown = true
    if changed then
        self.showTransitions = (self.showTransitions or 0) + 1
    end
    if not wasVisible and self:IsVisible() then
        DispatchVisibility(self, "OnShow")
    end
end

function Widget:Hide()
    self.hideCalls = (self.hideCalls or 0) + 1
    local wasVisible = self:IsVisible()
    local changed = self.shown
    self.shown = false
    if changed then
        self.hideTransitions = (self.hideTransitions or 0) + 1
    end
    if wasVisible then
        DispatchVisibility(self, "OnHide")
    end
end

function Widget:SetShown(value)
    if value then
        self:Show()
    else
        self:Hide()
    end
end

function Widget:IsShown()
    return self.shown
end

function Widget:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end

function Widget:IsMouseOver()
    local left, bottom, width, height = self:GetScaledRect()
    return self:IsVisible()
        and Test.cursorX >= left
        and Test.cursorX <= left + width
        and Test.cursorY >= bottom
        and Test.cursorY <= bottom + height
end

function Widget:SetEnabled(value)
    self.enableCalls = (self.enableCalls or 0) + 1
    local changed = self.enabled ~= value
    self.enabled = value
    local handler = value and "OnEnable" or "OnDisable"
    if changed and self.scripts[handler] then
        self.scripts[handler](self)
    end
end

function Widget:Enable()
    self:SetEnabled(true)
end

function Widget:Disable()
    self:SetEnabled(false)
end

function Widget:SetButtonState(state)
    self.buttonState = state
end

function Widget:GetButtonState()
    return self.buttonState or "NORMAL"
end

function Widget:SetAutoFocus(value)
    self.autoFocus = value
end

function Widget:SetMaxLetters(value)
    self.maxLetters = value
end

function Widget:SetNumeric(value)
    self.numeric = value
end

function Widget:ClearFocus()
    local changed = self.focused == true
    self.focused = false
    if changed and self.scripts.OnEditFocusLost then
        self.scripts.OnEditFocusLost(self)
    end
end

function Widget:SetPassword(value)
    self.password = value
end

function Widget:SetChecked(value)
    self.checked = value
end

function Widget:GetChecked()
    return self.checked
end

function Widget:SetupMenu(generator)
    self.generator = generator
    if self:IsShown() then
        self:GenerateMenu()
    end
end

function Widget:GenerateMenu()
    self.menuGenerations = (self.menuGenerations or 0) + 1
    if not self.generator then
        return
    end
    self.options = {}
    local owner = self
    local description = { entries = self.options }
    local function CreateEntry(text, selected, select, value, radio)
        local entry = { text = text, selected = selected, select = select, value = value, radio = radio }
        function entry:IsSelected()
            return self.selected(self.value)
        end
        function entry:GetData()
            return self.value
        end
        function entry:IsRadio()
            return self.radio
        end
        function entry:IsCheckbox()
            return not self.radio
        end
        function entry:Pick()
            if not owner:IsEnabled() or self.enabled == false then
                return false
            end
            self.select(self.value)
            if self.radio then
                owner:Update()
                owner:CloseMenu()
            elseif owner.shouldRegenerateOnResponse then
                owner:GenerateMenu()
            else
                owner:Update()
            end
            return true
        end
        function entry:SetEnabled(enabled)
            self.enabled = enabled
        end
        function entry:IsEnabled()
            return self.enabled ~= false
        end
        owner.options[#owner.options + 1] = entry
        return entry
    end
    function description:CreateRadio(text, selected, select, value)
        return CreateEntry(text, selected, select, value, true)
    end
    function description:CreateCheckbox(text, selected, select, value)
        return CreateEntry(text, selected, select, value, false)
    end
    function description:SetScrollMode(maximum)
        self.maxScrollExtent = maximum
    end
    function description:SetMinimumWidth(width)
        self.minimumWidth = width
    end
    function description:SetMaximumWidth(width)
        self.maximumWidth = width
    end
    function description:GetMinimumWidth()
        return self.minimumWidth
    end
    function description:GetMaximumWidth()
        return self.maximumWidth
    end
    self.menuDescription = description
    self.generator(self, description)
    description.minimumWidth = description.minimumWidth or self:GetWidth()
    if self.menu then
        self.menu.description = description
    end
    self:Update()
end

function Widget:GetMenuDescription()
    return self.menuDescription
end

function Widget:SetDefaultText(text)
    self.defaultText = text
    self:Update()
end

function Widget:EnableRegenerateOnResponse()
    self.shouldRegenerateOnResponse = true
end

function Widget:Update()
    local selections = {}
    for _, entry in ipairs(self.options or {}) do
        if entry:IsSelected() then
            selections[#selections + 1] = entry.text
        end
    end
    self:SetText(#selections > 0 and table.concat(selections, ", ") or self.defaultText or "")
end

function Widget:IsMenuOpen()
    return self.menu ~= nil
end

function Widget:CloseMenu()
    if self.menu then
        self.menu.closed = true
        self.menu = nil
    end
    if self.Arrow then
        self.Arrow:SetAtlas(self:IsEnabled() and "common-dropdown-a-button" or "common-dropdown-a-button-disabled")
    end
    self:Update()
end

function Widget:OpenMenu()
    if not self:IsEnabled() or self:IsMenuOpen() then
        return
    end
    self:GenerateMenu()
    if not self.menuDescription then
        return
    end
    local owner = self
    self.menu = { owner = owner, description = self.menuDescription }
    function self.menu:Close()
        owner:CloseMenu()
    end
    self.Arrow:SetAtlas("common-dropdown-a-button-open")
end

function Widget:SetMenuOpen(open)
    if open then
        self:OpenMenu()
    else
        self:CloseMenu()
    end
end

function Widget:SetScrollChild(child)
    self.child = child
end

function Widget:GetScrollChild()
    return self.child
end

function Widget:UpdateScrollChildRect()
    self.scrollRectUpdates = (self.scrollRectUpdates or 0) + 1
    if self.scripts.OnScrollRangeChanged then
        self.scripts.OnScrollRangeChanged(self, 0, self:GetVerticalScrollRange())
    end
end

function Widget:SetVerticalScroll(value)
    self.verticalScrollCalls = (self.verticalScrollCalls or 0) + 1
    local changed = self.verticalScroll ~= value
    self.verticalScroll = value
    if changed and self.scripts.OnVerticalScroll then
        self.scripts.OnVerticalScroll(self, value)
    end
end

function Widget:GetVerticalScroll()
    return self.verticalScroll or 0
end

function Widget:GetVerticalScrollRange()
    return math.max(0, (self.child and self.child:GetHeight() or 0) - self:GetHeight())
end

MinimalSliderWithSteppersMixin = {
    Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
    Event = { OnValueChanged = "OnValueChanged", OnInteractStart = "OnInteractStart", OnInteractEnd = "OnInteractEnd" },
}

function Mixin(object, ...)
    for index = 1, select("#", ...) do
        for key, value in pairs(select(index, ...)) do
            object[key] = value
        end
    end
    return object
end

NarrationSliderMixin = {}

function NarrationSliderMixin:SetNarrationLabelRegion(region)
    self.narrationLabelRegion = region
end

function NarrationSliderMixin:SetNarrationValueFormatter(formatter)
    self.narrationValueFormatter = formatter
end

function NarrationSliderMixin:NarrationGetName()
    if self.narrationLabel then
        return self.narrationLabel
    end
    return self.narrationLabelRegion and self.narrationLabelRegion:GetText() or nil
end

function NarrationSliderMixin:NarrationGetDescription()
    if self.narrationValueFormatter then
        return self.narrationValueFormatter(self:GetValue(), self:GetMinMaxValues())
    end
    return tostring(self:GetValue())
end

function CreateMinimalSliderFormatter(_, value)
    if type(value) == "function" then
        return value
    end
    return function(current)
        return value == nil and current or value
    end
end

function CreateFrame(kind, name, parent, template)
    local frame = NewWidget(kind, name, parent)
    frame.template = template
    if kind == "Slider" then
        frame.orientation = "VERTICAL"
    end
    if kind == "GameTooltip" then
        frame.lines, frame.shown = {}, false
    end
    if template == "BasicFrameTemplateWithInset" then
        frame.TitleText = NewWidget("FontString", nil, frame)
    elseif template == "UICheckButtonTemplate" or template == "UIPanelButtonNoTooltipTemplate" then
        frame.Text = NewWidget("FontString", nil, frame)
    end
    if template == "UIPanelButtonTemplate" or template == "UIPanelButtonNoTooltipTemplate" then
        frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.nativeFontString = frame.Text
        frame.templateText = frame.Text
        frame.templateScripts, frame.templateCalls = {}, {}
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnShow", "OnEnable", "OnDisable" }) do
            frame.templateScripts[event] = function(self)
                self.templateCalls[event] = (self.templateCalls[event] or 0) + 1
            end
            frame:SetScript(event, frame.templateScripts[event])
        end
    elseif template == "WowStyle1DropdownTemplate" then
        assert(kind == "DropdownButton", "native dropdown must use the DropdownButton intrinsic")
        frame.intrinsic = "DropdownButton"
        frame:SetSize(120, 25)
        frame.Background = frame:CreateTexture(nil, "BACKGROUND")
        frame.Background:SetAtlas("common-dropdown-textholder")
        frame.Arrow = frame:CreateTexture(nil, "OVERLAY")
        frame.Arrow:SetAtlas("common-dropdown-a-button")
        frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.templateText = frame.Text
        frame.templateScripts, frame.templateCalls = {}, {}
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnShow", "OnEnter", "OnLeave", "OnEnable", "OnDisable" }) do
            frame.templateScripts[event] = function(self)
                self.templateCalls[event] = (self.templateCalls[event] or 0) + 1
                if event == "OnMouseDown" then
                    self:SetMenuOpen(not self:IsMenuOpen())
                elseif event == "OnShow" then
                    self:GenerateMenu()
                elseif event == "OnEnable" or event == "OnDisable" then
                    self.Arrow:SetAtlas(
                        self:IsEnabled() and "common-dropdown-a-button" or "common-dropdown-a-button-disabled"
                    )
                end
            end
            frame:SetScript(event, frame.templateScripts[event])
        end
    elseif template == "SearchBoxTemplate" then
        assert(kind == "EditBox", "native search template requires an EditBox")
        frame.autoFocus, frame.instructionText = false, "Search"
        frame.font, frame.fontObject = "GameFontHighlightSmall", GameFontHighlightSmall
        frame:SetTextInsets(16, 20, 0, 0)
        for key, atlas in pairs({
            Left = "common-search-border-left",
            Middle = "common-search-border-middle",
            Right = "common-search-border-right",
        }) do
            frame[key] = frame:CreateTexture(nil, "BACKGROUND")
            frame[key]:SetAtlas(atlas)
            frame[key]:SetSize(key == "Middle" and 10 or 8, 20)
        end
        frame.Left:SetPoint("LEFT", frame, "LEFT", -5, 0)
        frame.Right:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        frame.Middle:SetPoint("LEFT", frame.Left, "RIGHT", 0, 0)
        frame.Middle:SetPoint("RIGHT", frame.Right, "LEFT", 0, 0)
        frame.Instructions = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        frame.Instructions:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, 0)
        frame.Instructions:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 0)
        frame.Instructions:SetText(frame.instructionText)
        frame.searchIcon = frame:CreateTexture(nil, "OVERLAY")
        frame.searchIcon:SetAtlas("common-search-magnifyingglass")
        frame.searchIcon:SetSize(10, 10)
        frame.searchIcon:SetPoint("LEFT", frame, "LEFT", 1, -1)
        frame.searchIcon:SetVertexColor(0.6, 0.6, 0.6)
        frame.clearButton = CreateFrame("Button", nil, frame)
        frame.clearButton:SetSize(17, 17)
        frame.clearButton:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
        frame.clearButton.Icon = frame.clearButton:CreateTexture(nil, "ARTWORK")
        frame.clearButton.Icon:SetAtlas("common-search-clearbutton")
        frame.clearButton.Icon:SetSize(10, 10)
        frame.clearButton.Icon:SetPoint("TOPLEFT", frame.clearButton, "TOPLEFT", 3, -3)
        frame.clearButton.Icon:SetAlpha(0.5)
        frame.clearButton:Hide()
        frame.clearButton.templateScripts, frame.clearButton.templateCalls = {}, {}
        frame.clearButton:SetScript("OnClick", function()
            local calls = frame.clearButton.templateCalls
            calls.OnClick = (calls.OnClick or 0) + 1
            frame:SetText("")
            frame:ClearFocus()
        end)
        frame.clearButton.templateClick = frame.clearButton:GetScript("OnClick")
        local clearHandlers = {
            OnEnter = function(self)
                self.Icon:SetAlpha(1)
            end,
            OnLeave = function(self)
                self.Icon:SetAlpha(0.5)
            end,
            OnMouseDown = function(self)
                if self:IsEnabled() then
                    self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -4)
                end
            end,
            OnMouseUp = function(self)
                self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 3, -3)
            end,
        }
        for event, handler in pairs(clearHandlers) do
            frame.clearButton.templateScripts[event] = function(self, ...)
                self.templateCalls[event] = (self.templateCalls[event] or 0) + 1
                handler(self, ...)
            end
            frame.clearButton:SetScript(event, frame.clearButton.templateScripts[event])
        end
        frame.templateScripts, frame.templateCalls = {}, {}
        local function TextOrFocus(self)
            local active = self:HasFocus() or self:GetText() ~= ""
            local shade = active and 1 or 0.6
            self.searchIcon:SetVertexColor(shade, shade, shade)
            self.clearButton:SetShown(active)
        end
        local function ClearFocus(self)
            self:ClearFocus()
        end
        local handlers = {
            OnEditFocusGained = TextOrFocus,
            OnEditFocusLost = function(self)
                if self:GetText() == "" then
                    self.searchIcon:SetVertexColor(0.6, 0.6, 0.6)
                    self.clearButton:Hide()
                end
            end,
            OnEscapePressed = ClearFocus,
            OnEnterPressed = ClearFocus,
            OnTextChanged = function(self)
                TextOrFocus(self)
                self.Instructions:SetShown(self:GetText() == "")
            end,
        }
        for event, handler in pairs(handlers) do
            frame.templateScripts[event] = function(self, ...)
                self.templateCalls[event] = (self.templateCalls[event] or 0) + 1
                handler(self, ...)
            end
            frame:SetScript(event, frame.templateScripts[event])
        end
    elseif template == "MinimalSliderWithSteppersTemplate" then
        assert(kind == "Frame", "stepper slider template belongs to an outer Frame")
        frame:SetSize(250, 40)
        frame.Slider = CreateFrame("Slider", nil, frame, "MinimalSliderTemplate")
        frame.Slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 19, 0)
        frame.Slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -19, 0)
        frame.Back, frame.Forward = CreateFrame("Button", nil, frame), CreateFrame("Button", nil, frame)
        frame.Back:SetSize(11, 19)
        frame.Forward:SetSize(9, 18)
        frame.Back:SetPoint("RIGHT", frame.Slider, "LEFT", -4, 0)
        frame.Forward:SetPoint("LEFT", frame.Slider, "RIGHT", 4, 0)
        frame.Back:CreateTexture(nil, "BACKGROUND"):SetAtlas("Minimal_SliderBar_Button_Left")
        frame.Forward:CreateTexture(nil, "BACKGROUND"):SetAtlas("Minimal_SliderBar_Button_Right")
        frame.Labels, frame.callbacks = {}, {}
        for index, key in ipairs({ "LeftText", "RightText", "TopText", "MinText", "MaxText" }) do
            frame[key] = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame[key]:Hide()
            frame.Labels[index] = frame[key]
        end
        function frame:RegisterCallback(event, callback, owner)
            owner = owner or {}
            self.callbacks[event] = self.callbacks[event] or {}
            self.callbacks[event][owner] = callback
            return owner
        end
        function frame:UnregisterCallback(event, owner)
            if self.callbacks[event] then
                self.callbacks[event][owner] = nil
            end
        end
        function frame:RegisterCallbackWithHandle(event, callback, owner)
            owner = self:RegisterCallback(event, callback, owner)
            return {
                Unregister = function()
                    self:UnregisterCallback(event, owner)
                end,
            }
        end
        function frame:TriggerEvent(event, ...)
            for owner, callback in pairs(self.callbacks[event] or {}) do
                callback(owner, ...)
            end
        end
        function frame:FormatValue(value)
            for index, formatter in pairs(self.formatters or {}) do
                self.Labels[index]:SetText(formatter(value))
                self.Labels[index]:Show()
            end
        end
        function frame:IsSliderEnabled()
            return self.sliderEnabled ~= false
        end
        local function SetStepperEnabled(button, enabled)
            button:SetEnabled(enabled)
            button:SetAlpha(enabled and 1 or 0.5)
            button.hierarchyDesaturation = enabled and 0 or 1
        end
        function frame:UpdateStepperStates()
            local value, step = self.Slider:GetValue(), self.Slider:GetValueStep()
            SetStepperEnabled(self.Back, self:IsSliderEnabled() and value > self.Slider.minimum + step * 0.5)
            SetStepperEnabled(self.Forward, self:IsSliderEnabled() and value < self.Slider.maximum - step * 0.5)
        end
        function frame:Init(value, minimum, maximum, steps, formatters)
            self.Slider:SetMinMaxValues(minimum, maximum)
            self.Slider:SetValueStep((maximum - minimum) / steps)
            self.Slider:SetValue(value)
            self.formatters = formatters
            self:FormatValue(value)
            self:UpdateStepperStates()
            self.Slider:SetScript("OnValueChanged", function(_, current)
                self:FormatValue(current)
                self:UpdateStepperStates()
                self:TriggerEvent(MinimalSliderWithSteppersMixin.Event.OnValueChanged, current)
            end)
            self.Slider.templateValueChanged = self.Slider:GetScript("OnValueChanged")
        end
        function frame:SetValue(value)
            self.Slider:SetValue(value)
        end
        function frame:SetEnabled(enabled)
            self.sliderEnabled = enabled
            self.Slider.Thumb:SetAlpha(enabled and 1 or 0.7)
            self.Slider:SetEnabled(enabled)
            if enabled then
                self:UpdateStepperStates()
            else
                SetStepperEnabled(self.Back, false)
                SetStepperEnabled(self.Forward, false)
            end
        end
        frame.Back:SetScript("OnClick", function()
            frame.Slider:SetValue(frame.Slider:GetValue() - frame.Slider:GetValueStep())
        end)
        frame.Forward:SetScript("OnClick", function()
            frame.Slider:SetValue(frame.Slider:GetValue() + frame.Slider:GetValueStep())
        end)
        frame.Back.templateClick, frame.Forward.templateClick =
            frame.Back:GetScript("OnClick"), frame.Forward:GetScript("OnClick")
        frame.Slider.templateScripts, frame.interactionFlags = {}, {}
        local function SetInteraction(flag, enabled)
            local wasActive = next(frame.interactionFlags) ~= nil
            frame.interactionFlags[flag] = enabled and true or nil
            local active = next(frame.interactionFlags) ~= nil
            if wasActive ~= active then
                frame:TriggerEvent(
                    active and MinimalSliderWithSteppersMixin.Event.OnInteractStart
                        or MinimalSliderWithSteppersMixin.Event.OnInteractEnd
                )
            end
        end
        for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave" }) do
            frame.Slider.templateScripts[event] = function(slider)
                if slider:IsEnabled() then
                    local flag = (event == "OnMouseDown" or event == "OnMouseUp") and "click" or "hover"
                    SetInteraction(flag, event == "OnMouseDown" or event == "OnEnter")
                end
            end
            frame.Slider:SetScript(event, frame.Slider.templateScripts[event])
        end
    elseif template == "EditModeSettingSliderTemplate" then
        assert(kind == "Frame", "Edit Mode slider setting is an outer Frame")
        frame.SetEnabled, frame.IsEnabled = false, false
        frame.shown = false
        frame:SetSize(343, 32)
        frame.Label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
        frame.Label:SetSize(100, 32)
        frame.Label:SetJustifyH("LEFT")
        frame.Label:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.Slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
        frame.Slider:SetSize(200, 32)
        frame.Slider:SetPoint("LEFT", frame.Label, "RIGHT", 5, 0)
        frame.templateCallbackCalls, frame.templateCallbacks = {}, {}
        for _, name in ipairs({ "OnSliderValueChanged", "OnSliderInteractStart", "OnSliderInteractEnd" }) do
            local callback = function(self)
                if name ~= "OnSliderValueChanged" or not self.initInProgress then
                    self.templateCallbackCalls[name] = (self.templateCallbackCalls[name] or 0) + 1
                    error("standalone slider invoked the captured Blizzard Edit Mode callback: " .. name)
                end
            end
            frame[name], frame.templateCallbacks[name] = callback, callback
        end
        frame.cbrHandles = { handles = {}, unregisterCalls = 0 }
        function frame.cbrHandles:RegisterCallback(cbr, event, callback, owner)
            self.handles[#self.handles + 1] = cbr:RegisterCallbackWithHandle(event, callback, owner)
        end
        function frame.cbrHandles:Unregister()
            self.unregisterCalls = self.unregisterCalls + 1
            for _, handle in ipairs(self.handles) do
                handle:Unregister()
            end
            self.handles = {}
        end
        function frame.cbrHandles:IsEmpty()
            return #self.handles == 0
        end
        for event, method in pairs({
            OnValueChanged = "OnSliderValueChanged",
            OnInteractStart = "OnSliderInteractStart",
            OnInteractEnd = "OnSliderInteractEnd",
        }) do
            frame.cbrHandles:RegisterCallback(frame.Slider, event, frame[method], frame)
        end
    elseif template == "MinimalSliderTemplate" then
        assert(kind == "Slider", "native slider template requires the Slider intrinsic")
        Mixin(frame, NarrationSliderMixin)
        frame:SetSize(200, 19)
        frame:SetOrientation("HORIZONTAL")
        frame:SetObeyStepOnDrag(true)
        for key, atlas in pairs({
            Left = "Minimal_SliderBar_Left",
            Right = "Minimal_SliderBar_Right",
            Middle = "_Minimal_SliderBar_Middle",
            Thumb = "Minimal_SliderBar_Button",
        }) do
            frame[key] = frame:CreateTexture(nil, "ARTWORK")
            frame[key]:SetAtlas(atlas)
        end
    elseif template == "UIPanelCloseButton" then
        frame:SetSize(24, 24)
        frame:SetScript("OnClick", function()
            error("owned close button retained native HideUIPanel dispatch")
        end)
    end
    Test.frames[#Test.frames + 1] = frame
    if name then
        _G[name] = frame
    end
    return frame
end

function CreateFramePool(kind, parent, template, resetter)
    local pool = { active = {}, inactive = {} }
    function pool:Acquire()
        local frame = table.remove(self.inactive)
        local isNew = frame == nil
        frame = frame or CreateFrame(kind, nil, parent, template)
        if isNew and resetter then
            resetter(self, frame, true)
        end
        self.active[frame] = true
        return frame, isNew
    end
    function pool:Release(frame)
        if not self.active[frame] then
            return
        end
        self.active[frame] = nil
        if resetter then
            resetter(self, frame)
        else
            frame:Hide()
            frame:ClearAllPoints()
        end
        self.inactive[#self.inactive + 1] = frame
    end
    function pool:ReleaseAll()
        for frame in pairs(self.active) do
            if resetter then
                resetter(self, frame)
            else
                frame:Hide()
                frame:ClearAllPoints()
            end
            self.inactive[#self.inactive + 1] = frame
        end
        self.active = {}
    end
    return pool
end

MenuUtil = {
    CreateContextMenu = function(owner, generator)
        owner:SetupMenu(generator)
    end,
}

UIParent = NewWidget("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
Minimap = NewWidget("Minimap", "Minimap", UIParent)
Minimap:SetSize(MINIMAP_SIZE, MINIMAP_SIZE)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
PixelUtil = {
    GetPixelToUIUnitFactor = function()
        return 768 / select(2, GetPhysicalScreenSize())
    end,
    GetNearestPixelSize = function(value, scale, minimum)
        if value == 0 and (not minimum or minimum == 0) then
            return 0
        end
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        local scaled = value * scale / factor
        local pixels = scaled < 0 and math.ceil(scaled - 0.5) or math.floor(scaled + 0.5)
        if minimum then
            pixels = value < 0 and math.min(pixels, -minimum) or math.max(pixels, minimum)
        end
        return pixels * factor / scale
    end,
    SetSize = function(region, width, height, minimumWidth, minimumHeight)
        PixelUtil.SetWidth(region, width, minimumWidth)
        PixelUtil.SetHeight(region, height, minimumHeight)
    end,
    SetWidth = function(region, width, minimum)
        region:SetWidth(PixelUtil.GetNearestPixelSize(width, region:GetEffectiveScale(), minimum))
    end,
    SetHeight = function(region, height, minimum)
        region:SetHeight(PixelUtil.GetNearestPixelSize(height, region:GetEffectiveScale(), minimum))
    end,
    SetPoint = function(region, point, relative, relativePoint, x, y, minimumX, minimumY)
        region:SetPoint(
            point,
            relative,
            relativePoint,
            PixelUtil.GetNearestPixelSize(x, region:GetEffectiveScale(), minimumX),
            PixelUtil.GetNearestPixelSize(y, region:GetEffectiveScale(), minimumY)
        )
    end,
}
UISpecialFrames = {}
SlashCmdList = {}

function Test.DispatchEvent(event, ...)
    for index = 1, #Test.frames do
        local frame = Test.frames[index]
        local handler = frame:GetScript("OnEvent")
        if frame.events and frame.events[event] and handler then
            handler(frame, event, ...)
        end
    end
end

function Test.Initialize()
    Test.DispatchEvent("ADDON_LOADED", "Orbit-Games")
    Test.DispatchEvent("PLAYER_LOGIN")
    assert(#Test.errors == 0, Test.errors[1])
end

function Test.Advance(seconds)
    Test.now = Test.now + seconds
    local count = #Test.tickers
    for index = 1, count do
        local ticker = Test.tickers[index]
        if ticker.active then
            ticker.callback()
        end
    end
    assert(#Test.errors == 0, Test.errors[1])
end

function Test.Incoming(text, name, guid, event, channelIndex, channelName)
    OrbitGames.Main:OnEvent(
        event or "CHAT_MSG_CHANNEL",
        text,
        name,
        "",
        "",
        "",
        "",
        0,
        channelIndex or Test.channelId,
        channelName or Test.channelName,
        0,
        1,
        guid
    )
end

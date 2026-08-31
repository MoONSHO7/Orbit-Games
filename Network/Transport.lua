local _, Quiz = ...
local PREFIX = "ORBITQUIZ8"
local VERSION = "1"
local MAX_FIELDS = 32
local MAX_MESSAGE_BYTES = 4096
local MAX_PACKET_BYTES = 255
local MAX_FRAGMENT_BYTES = 200
local MAX_FRAGMENTS = 32
local MAX_ID_BYTES = 32
local MAX_LENGTH_DIGITS = 4
local MAX_PEERS = 32
local MAX_ASSEMBLIES = 32
local MAX_QUEUE_PACKETS = 512
local MAX_RECENT_MESSAGES = 128
local MESSAGE_TTL = 15
local RECENT_TTL = 60
local SEND_BURST = 8
local SEND_RATE = 8
local MAX_SEND_ATTEMPTS = 5
local RETRY_DELAY = 0.5
local MAX_RETRY_DELAY = 2
local EPOCH_RANGE = 16777216
local MAX_SEQUENCE = 2147483647
local KEY_SEPARATOR = "\031"

local Comms = { initialized = false, suspended = false, sequence = 0, revision = 0 }
Quiz.Comms = Comms

local function IsBlocked(self)
    return self.suspended or C_ChatInfo.InChatMessagingLockdown()
end

local function Encode(fields)
    if issecretvalue(fields) or type(fields) ~= "table" or getmetatable(fields) ~= nil then
        return nil, "codec_invalid"
    end
    local count, maximum = 0, 0
    for key, value in pairs(fields) do
        if
            issecretvalue(key)
            or type(key) ~= "number"
            or key < 1
            or key > MAX_FIELDS
            or key ~= math.floor(key)
            or issecretvalue(value)
            or type(value) ~= "string"
            or value:find("\000", 1, true)
        then
            return nil, "codec_invalid"
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then
        return nil, "codec_invalid"
    end
    local pieces = { count .. ":" }
    local size = #pieces[1]
    for index = 1, count do
        local value = fields[index]
        local length = #value .. ":"
        size = size + #length + #value
        if size > MAX_MESSAGE_BYTES then
            return nil, "message_too_large"
        end
        pieces[#pieces + 1] = length
        pieces[#pieces + 1] = value
    end
    return table.concat(pieces)
end

local function ReadLength(encoded, cursor)
    local separator = encoded:find(":", cursor, true)
    if not separator or separator - cursor > MAX_LENGTH_DIGITS then
        return nil
    end
    local digits = encoded:sub(cursor, separator - 1)
    if not digits:match("^%d+$") or (#digits > 1 and digits:sub(1, 1) == "0") then
        return nil
    end
    return tonumber(digits), separator + 1
end

local function Decode(encoded)
    local count, cursor = ReadLength(encoded, 1)
    if not count or count > MAX_FIELDS then
        return nil
    end
    local fields = {}
    for index = 1, count do
        local length
        length, cursor = ReadLength(encoded, cursor)
        if not length or length > MAX_MESSAGE_BYTES or cursor + length - 1 > #encoded then
            return nil
        end
        fields[index] = encoded:sub(cursor, cursor + length - 1)
        cursor = cursor + length
    end
    if cursor ~= #encoded + 1 then
        return nil
    end
    return fields
end

local function CompactQueue(self)
    local queue = {}
    for index = self.queueHead, self.queueTail do
        local message = self.queue[index]
        if message then
            queue[#queue + 1] = message
        end
    end
    self.queue = queue
    self.queueHead = 1
    self.queueTail = #queue
end

local function RemoveMessage(self, index)
    local message = self.queue[index]
    self.queue[index] = nil
    self.queueCount = self.queueCount - (#message.packets - message.part + 1)
    self.queueTargets[message.target] = self.queueTargets[message.target] - 1
    if self.queueTargets[message.target] == 0 then
        self.queueTargets[message.target] = nil
        self.queuePeerCount = self.queuePeerCount - 1
    end
end

local function RemoveAssembly(self, peer, id)
    peer.assemblies[id] = nil
    self.assemblyCount = self.assemblyCount - 1
end

local function RemoveRecent(self, entry)
    self.recent[entry.key] = nil
    entry.peer.recentCount = entry.peer.recentCount - 1
end

local function Remember(self, peer, id, now)
    local slot = self.recentSlot
    local previous = self.recentSlots[slot]
    if previous then
        RemoveRecent(self, previous)
    end
    local key = peer.name .. KEY_SEPARATOR .. id
    local entry = { key = key, peer = peer, expiresAt = now + RECENT_TTL }
    self.recentSlots[slot] = entry
    self.recent[key] = entry
    peer.recentCount = peer.recentCount + 1
    self.recentSlot = slot % MAX_RECENT_MESSAGES + 1
end

local function ExpireInbound(self, now)
    for _, peer in pairs(self.peers) do
        for id, assembly in pairs(peer.assemblies) do
            if now >= assembly.expiresAt then
                RemoveAssembly(self, peer, id)
                Remember(self, peer, id, now)
            end
        end
    end
    for slot, entry in pairs(self.recentSlots) do
        if now >= entry.expiresAt then
            RemoveRecent(self, entry)
            self.recentSlots[slot] = nil
        end
    end
    for sender, peer in pairs(self.peers) do
        if peer.recentCount == 0 and next(peer.assemblies) == nil then
            self.peers[sender] = nil
            self.peerCount = self.peerCount - 1
        end
    end
end

function Comms:Clear()
    self.revision = self.revision + 1
    self.queue = {}
    self.queueHead = 1
    self.queueTail = 0
    self.queueCount = 0
    self.queueTargets = {}
    self.queuePeerCount = 0
    self.peers = {}
    self.peerCount = 0
    self.assemblyCount = 0
    self.recent = {}
    self.recentSlots = {}
    self.recentSlot = 1
end

function Comms:Initialize(onMessage, onError)
    self:Clear()
    self.onMessage = onMessage
    self.onError = onError
    self.initialized = false
    local result = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    if
        issecretvalue(result)
        or (
            result ~= Enum.RegisterAddonMessagePrefixResult.Success
            and result ~= Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix
        )
    then
        return false, "send_failed"
    end
    self.epoch = self.epoch
        or ("%x-%x"):format(math.floor(GetTime() * 1000) % EPOCH_RANGE, math.random(EPOCH_RANGE - 1))
    self.tokens = self.tokens or SEND_BURST
    self.refilledAt = GetTime()
    self.initialized = true
    return true
end

function Comms:Send(target, fields, tag)
    if not self.initialized then
        return false, "send_failed"
    end
    if IsBlocked(self) then
        return false, "addon_lockdown"
    end
    target = Quiz.Identity:NormalizeName(target)
    if not target then
        return false, "invalid_target"
    end
    if issecretvalue(tag) then
        return false, "codec_invalid"
    end
    local encoded, reason = Encode(fields)
    if not encoded then
        return false, reason
    end
    local count = math.ceil(#encoded / MAX_FRAGMENT_BYTES)
    if
        self.queueCount + count > MAX_QUEUE_PACKETS
        or (not self.queueTargets[target] and self.queuePeerCount >= MAX_PEERS)
    then
        return false, "queue_full"
    end
    if self.sequence >= MAX_SEQUENCE then
        self.epoch = ("%x-%x"):format(math.floor(GetTime() * 1000) % EPOCH_RANGE, math.random(EPOCH_RANGE - 1))
        self.sequence = 0
    end
    self.sequence = self.sequence + 1
    local id = ("%s-%x"):format(self.epoch, self.sequence)
    local packets = {}
    for part = 1, count do
        local fragment = encoded:sub((part - 1) * MAX_FRAGMENT_BYTES + 1, part * MAX_FRAGMENT_BYTES)
        packets[part] = ("%s|%s|%d|%d|%s"):format(VERSION, id, part, count, fragment)
    end
    if self.queueTail >= MAX_QUEUE_PACKETS and not self.ticking then
        CompactQueue(self)
    end
    self.queueTail = self.queueTail + 1
    self.queue[self.queueTail] = {
        target = target,
        packets = packets,
        part = 1,
        attempts = 0,
        nextAttemptAt = 0,
        expiresAt = GetTime() + MESSAGE_TTL,
        tag = tag,
    }
    self.queueCount = self.queueCount + count
    if not self.queueTargets[target] then
        self.queueTargets[target] = 0
        self.queuePeerCount = self.queuePeerCount + 1
    end
    self.queueTargets[target] = self.queueTargets[target] + 1
    return true
end

function Comms:Cancel(tag)
    if issecretvalue(tag) then
        return
    end
    local changed = false
    for index = self.queueHead, self.queueTail do
        local message = self.queue[index]
        if message and message.tag == tag then
            RemoveMessage(self, index)
            changed = true
        end
    end
    if changed then
        self.revision = self.revision + 1
        CompactQueue(self)
    end
end

function Comms:IsBusy(target)
    if target ~= nil then
        local name = Quiz.Identity:NormalizeName(target)
        return name ~= nil and self.queueTargets[name] ~= nil
    end
    return self.queueCount > 0
end

function Comms:IsTagBusy(tag)
    for index = self.queueHead, self.queueTail do
        local message = self.queue[index]
        if message and message.tag == tag then
            return true
        end
    end
    return false
end

function Comms:Tick(now)
    if not self.initialized or self.ticking then
        return
    end
    self.ticking = true
    ExpireInbound(self, now)
    local failures, failedTargets = {}, {}
    local function Failure(target, reason)
        if not failedTargets[target] then
            failedTargets[target] = true
            failures[#failures + 1] = { target = target, reason = reason }
        end
    end
    local expired = false
    for index = self.queueHead, self.queueTail do
        local message = self.queue[index]
        if message and now >= message.expiresAt then
            Failure(message.target, "send_failed")
            RemoveMessage(self, index)
            expired = true
        end
    end
    if expired then
        CompactQueue(self)
    end
    self.tokens = math.min(SEND_BURST, self.tokens + math.max(0, now - self.refilledAt) * SEND_RATE)
    self.refilledAt = now
    local revision, lastMessage = self.revision, self.queueTail
    local attempts = 0
    while self.tokens >= 1 and attempts < SEND_BURST and self.queueHead <= lastMessage and not IsBlocked(self) do
        local message = self.queue[self.queueHead]
        if now < message.nextAttemptAt then
            break
        end
        local result = C_ChatInfo.SendAddonMessage(PREFIX, message.packets[message.part], "WHISPER", message.target)
        self.tokens = self.tokens - 1
        attempts = attempts + 1
        if self.revision ~= revision then
            break
        end
        if
            not issecretvalue(result)
            and (result == Enum.SendAddonMessageResult.Success or result == Enum.SendAddonMessageResult.ChannelThrottle)
        then
            -- ChannelThrottle can accompany an already-submitted packet; application acknowledgements decide delivery.
            self.queueCount = self.queueCount - 1
            message.part = message.part + 1
            message.attempts = 0
            if message.part > #message.packets then
                RemoveMessage(self, self.queueHead)
                self.queueHead = self.queueHead + 1
            end
        elseif not issecretvalue(result) and result == Enum.SendAddonMessageResult.AddonMessageThrottle then
            message.attempts = message.attempts + 1
            if message.attempts >= MAX_SEND_ATTEMPTS then
                Failure(message.target, "send_failed")
                RemoveMessage(self, self.queueHead)
                self.queueHead = self.queueHead + 1
            else
                message.nextAttemptAt = now + math.min(MAX_RETRY_DELAY, RETRY_DELAY * 2 ^ (message.attempts - 1))
            end
            break
        else
            local reason = "send_failed"
            if not issecretvalue(result) and result == Enum.SendAddonMessageResult.AddOnMessageLockdown then
                reason = "addon_lockdown"
                self.suspended = true
            elseif not issecretvalue(result) and result == Enum.SendAddonMessageResult.TargetOffline then
                reason = "target_offline"
            end
            Failure(message.target, reason)
            RemoveMessage(self, self.queueHead)
            self.queueHead = self.queueHead + 1
        end
    end
    if self.queueCount == 0 or self.queueHead > MAX_QUEUE_PACKETS then
        CompactQueue(self)
    end
    for _, failure in ipairs(failures) do
        if self.revision ~= revision then
            break
        end
        self.onError(failure.target, failure.reason)
    end
    self.ticking = false
end

function Comms:Receive(prefix, text, channel, sender)
    if
        not self.initialized
        or IsBlocked(self)
        or issecretvalue(prefix)
        or issecretvalue(text)
        or issecretvalue(channel)
        or prefix ~= PREFIX
        or channel ~= "WHISPER"
        or type(text) ~= "string"
        or #text > MAX_PACKET_BYTES
        or text:find("\000", 1, true)
    then
        return false
    end
    sender = Quiz.Identity:NormalizeName(sender)
    if not sender then
        return false
    end
    local id, partText, totalText, cursor = text:match("^1|([%w%-]+)|(%d+)|(%d+)|()")
    if not id or #id > MAX_ID_BYTES or not partText:match("^[1-9]%d?$") or not totalText:match("^[1-9]%d?$") then
        return false
    end
    local part, total = tonumber(partText), tonumber(totalText)
    local fragment = text:sub(cursor)
    if part > total or total > MAX_FRAGMENTS or #fragment == 0 or #fragment > MAX_FRAGMENT_BYTES then
        return false
    end
    local now = GetTime()
    ExpireInbound(self, now)
    local key = sender .. KEY_SEPARATOR .. id
    if self.recent[key] then
        return true
    end
    local peer = self.peers[sender]
    if not peer then
        if self.peerCount >= MAX_PEERS then
            return false
        end
        peer = { name = sender, assemblies = {}, recentCount = 0 }
        self.peers[sender] = peer
        self.peerCount = self.peerCount + 1
    end
    local assembly = peer.assemblies[id]
    if not assembly then
        if self.assemblyCount >= MAX_ASSEMBLIES then
            return false
        end
        assembly = { total = total, parts = {}, count = 0, size = 0, expiresAt = now + MESSAGE_TTL }
        peer.assemblies[id] = assembly
        self.assemblyCount = self.assemblyCount + 1
    end
    if assembly.total ~= total or (assembly.parts[part] and assembly.parts[part] ~= fragment) then
        RemoveAssembly(self, peer, id)
        Remember(self, peer, id, now)
        return false
    end
    if assembly.parts[part] then
        return true
    end
    assembly.size = assembly.size + #fragment
    if assembly.size > MAX_MESSAGE_BYTES then
        RemoveAssembly(self, peer, id)
        Remember(self, peer, id, now)
        return false
    end
    assembly.parts[part] = fragment
    assembly.count = assembly.count + 1
    if assembly.count == total then
        local encoded = table.concat(assembly.parts)
        RemoveAssembly(self, peer, id)
        Remember(self, peer, id, now)
        local fields = Decode(encoded)
        if not fields then
            return false
        end
        self.onMessage(sender, fields)
    end
    return true
end

Comms:Clear()

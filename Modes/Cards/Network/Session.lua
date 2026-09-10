local _, Games = ...
local Cards = Games.Cards
local L = Cards.L
local Protocol = Cards.Protocol

local JOIN_TIMEOUT = 12
local JOIN_RETRY = 3
local HEARTBEAT_INTERVAL = 5
local HOST_TIMEOUT = 18
local PEER_TIMEOUT = 35
local SNAPSHOT_INTERVAL = 2
local ACTION_RETRY_INTERVAL = 3
local MILLISECONDS = 1000

Cards.Session = { nonce = 0 }
local Session = Cards.Session

local function Send(target, fields, tag)
    return Games.Comms:Send(target, Cards.id, fields, tag)
end

local function NewRequest(now)
    Session.nonce = Session.nonce + 1
    return string.format("%.0f.%.0f.%d", GetServerTime(), now * MILLISECONDS, Session.nonce)
end

local function PeerTag(peer, purpose)
    return "cards:" .. purpose .. ":" .. peer.key
end

local function OlderRequest(request, current)
    local epoch, clock, nonce = request:match("^(%d+)%.(%d+)%.(%d+)$")
    local currentEpoch, currentClock, currentNonce = current:match("^(%d+)%.(%d+)%.(%d+)$")
    if not epoch or not currentEpoch then
        return false
    end
    epoch, clock, nonce = tonumber(epoch), tonumber(clock), tonumber(nonce)
    currentEpoch, currentClock, currentNonce = tonumber(currentEpoch), tonumber(currentClock), tonumber(currentNonce)
    return epoch < currentEpoch
        or epoch == currentEpoch and (clock < currentClock or clock == currentClock and nonce < currentNonce)
end

local function CopyView(view)
    local copy = {}
    for key, value in pairs(view) do
        copy[key] = value
    end
    return copy
end

local function ClearPending(client)
    client.pendingSequence = nil
    client.pendingFields = nil
    client.pendingTag = nil
    client.nextActionRetry = nil
end

function Session:Initialize()
    self.hostSession = nil
    self.peers = {}
    self.client = nil
    self.restricted = false
    self.view = { role = "idle", state = "idle", gameTypeId = Cards.id }
    self.nextSnapshot = nil
    self.projectionRevision = nil
end

function Session:GetView()
    if self.hostSession then
        return Cards.Controller:GetHostView()
    end
    if self.restricted and self.client then
        local view = CopyView(self.view)
        view.state, view.notice = "paused", L.W_RESTRICTED
        return view
    end
    return self.view
end

function Session:IsActive()
    return self.hostSession ~= nil or self.client ~= nil
end

function Session:IsJoinedTo(game)
    local view = self:GetView()
    return self.client ~= nil
        and view.state ~= "disconnected"
        and (view.hostName or ""):lower() == game.hostName:lower()
        and (view.sessionId or view.session) == game.sessionId
end

function Session:StartHost(sessionId)
    Games.Comms:Clear()
    self.client = nil
    self.hostSession = sessionId
    self.peers = {}
    self.nextSnapshot = GetTime() + SNAPSHOT_INTERVAL
    self.projectionRevision = 0
    Games.Discovery:Advertise()
end

function Session:EndHost()
    if not self.hostSession then
        return
    end
    Games.Discovery:StopHost()
    for _, peer in pairs(self.peers) do
        Send(peer.name, Protocol.Close(self.hostSession), PeerTag(peer, "close"))
    end
    self.hostSession = nil
    self.peers = {}
    self.nextSnapshot = nil
    self.projectionRevision = nil
    self.view = { role = "idle", state = "stopped", gameTypeId = Cards.id }
end

function Session:JoinHost(name, advertisedSession, advert)
    if not Games.Main.initialized then
        return false, L.HOST_UNAVAILABLE
    end
    if Games.Main:IsRestricted() then
        return false, L.NET_RESTRICTED
    end
    if
        advert
        and (
            advert.activityId ~= Cards.VARIANT_ID
            or advert.activityVersion ~= Cards.ACTIVITY_VERSION
            or advert.joinable == false
        )
    then
        return false, "invalid_session"
    end
    local host = Games.Identity:NormalizeName(name)
    if not host then
        return false, "invalid_host_name"
    end
    local identified, reason = Games.Identity:Initialize()
    if not identified then
        return false, reason
    end
    if host:lower() == Games.Identity.name:lower() then
        return false, L.NET_SELF_JOIN
    end
    if self.client and self.client.key == host:lower() and self.view.state ~= "disconnected" then
        local currentSession = self.client.session or self.client.advertisedSession
        if not advertisedSession or advertisedSession == currentSession then
            return true
        end
    end
    if self.hostSession then
        local stopped, stopReason = Cards.Controller:Stop()
        if not stopped then
            return false, stopReason
        end
    else
        self:Leave()
    end
    local now = GetTime()
    local request = NewRequest(now)
    self.client = {
        name = host,
        key = host:lower(),
        request = request,
        advertisedSession = advertisedSession,
        joinedAt = now,
        lastHeard = now,
        nextJoin = now + JOIN_RETRY,
        nextHeartbeat = now + HEARTBEAT_INTERVAL,
        sequence = 0,
    }
    self.view = { role = "participant", state = "joining", gameTypeId = Cards.id, hostName = host }
    local sent, sendError = Send(host, Protocol.Join(request, advertisedSession), "cards:join")
    if not sent then
        self.client = nil
        self.view.state = "disconnected"
        self.view.notice = L.errors[sendError] or L.NET_SEND_FAILED
        return false, self.view.notice
    end
    Games.Main:EnsureTicker()
    Cards.Table:Show()
    return true
end

function Session:Leave()
    if self.hostSession then
        return false, L.NET_STOP_HOST_FIRST
    end
    local client = self.client
    Games.Comms:Clear()
    if client and client.session then
        Send(client.name, Protocol.Leave(client.session, client.request), "cards:leave")
        Games.Main:EnsureTicker()
    end
    self.client = nil
    self.view = { role = "idle", state = "idle", gameTypeId = Cards.id }
    Cards.Table:Refresh()
    return true
end

function Session:SendProjection(peer)
    if self.restricted or not self.hostSession then
        return false, "addon_lockdown"
    end
    local tag = PeerTag(peer, "projection")
    if Games.Comms:IsTagBusy(tag) then
        return true, "pending"
    end
    local projection = Cards.Controller:GetProjection(peer.playerId)
    if not projection then
        return false, "not_running"
    end
    self.projectionRevision = self.projectionRevision + 1
    local wireRevision = self.projectionRevision
    local payload, reason = Cards.TexasHoldem.Codec.EncodeProjection(projection, GetTime())
    if not payload then
        return false, reason
    end
    return Send(peer.name, Protocol.Projection(self.hostSession, wireRevision, payload), tag)
end

function Session:Broadcast()
    if self.restricted or not self.hostSession then
        return
    end
    for _, peer in pairs(self.peers) do
        self:SendProjection(peer)
    end
    Games.Discovery:Advertise()
end

function Session:NextSequence()
    local client = self.client
    client.sequence = client.sequence + 1
    return client.sequence
end

function Session:SendClientAction(fields, sequence, tag)
    local client = self.client
    if not client or not client.session then
        return false, "not_seated"
    end
    if self.restricted or Games.Main:IsRestricted() then
        return false, "addon_lockdown"
    end
    if client.pendingSequence then
        return false, "action_pending"
    end
    local sent, reason = Send(client.name, fields, tag)
    if not sent then
        return false, reason
    end
    client.pendingSequence = sequence
    client.pendingFields = fields
    client.pendingTag = tag
    client.nextActionRetry = GetTime() + ACTION_RETRY_INTERVAL
    self.view.pending = true
    self.view.notice = nil
    return true
end

function Session:Act(action, targetAmount)
    if self.hostSession then
        return Cards.Controller:AcceptAction(Cards.Controller.hostId, action, targetAmount)
    end
    local client = self.client
    if not client or not client.session then
        return false, "not_seated"
    end
    if not self.view.legalActions then
        return false, "not_turn"
    end
    local sequence = self:NextSequence()
    return self:SendClientAction(
        Protocol.Action(client.session, client.request, sequence, action, targetAmount, self.view.revision),
        sequence,
        "cards:action"
    )
end

function Session:SetSittingOut(sittingOut)
    if self.hostSession then
        return Cards.Controller:SetSittingOut(Cards.Controller.hostId, sittingOut)
    end
    local client = self.client
    if not client or not client.session then
        return false, "not_seated"
    end
    local sequence = self:NextSequence()
    return self:SendClientAction(
        Protocol.SitOut(client.session, client.request, sequence, sittingOut),
        sequence,
        "cards:sitout"
    )
end

function Session:Rebuy()
    if self.hostSession then
        return Cards.Controller:Rebuy(Cards.Controller.hostId)
    end
    local client = self.client
    if not client or not client.session then
        return false, "not_seated"
    end
    local sequence = self:NextSequence()
    return self:SendClientAction(Protocol.Rebuy(client.session, client.request, sequence), sequence, "cards:rebuy")
end

function Session:PeerFor(sender, message)
    local peer = self.peers[sender:lower()]
    if
        not peer
        or message.sessionId ~= self.hostSession
        or message.request ~= peer.request
        or message.sequence and message.sequence < peer.lastSequence
    then
        return nil
    end
    return peer
end

function Session:Acknowledge(peer, sequence)
    peer.lastSequence = sequence
    peer.lastAccepted = true
    peer.lastReason = nil
    Send(peer.name, Protocol.Acknowledge(self.hostSession, peer.request, sequence), PeerTag(peer, "ack"))
end

function Session:Reject(peer, sequence, reason)
    peer.lastSequence = sequence
    peer.lastAccepted = false
    peer.lastReason = reason
    Send(peer.name, Protocol.Error(peer.request, sequence, reason), PeerTag(peer, "error"))
    self:SendProjection(peer)
end

function Session:RepeatResponse(peer, sequence)
    if peer.lastAccepted then
        Send(peer.name, Protocol.Acknowledge(self.hostSession, peer.request, sequence), PeerTag(peer, "ack"))
    else
        Send(peer.name, Protocol.Error(peer.request, sequence, peer.lastReason), PeerTag(peer, "error"))
    end
end

function Session:ReceiveJoin(sender, message, now)
    if message.advertisedSession and message.advertisedSession ~= self.hostSession then
        Send(sender, Protocol.Error(message.request, nil, "invalid_session"), "cards:join-error")
        return
    end
    local key = sender:lower()
    local previous = self.peers[key]
    if previous and OlderRequest(message.request, previous.request) then
        return
    end
    if previous and previous.request == message.request then
        previous.lastSeen = now
        local tag = PeerTag(previous, "welcome")
        if not Games.Comms:IsTagBusy(tag) then
            Send(sender, Protocol.Welcome(self.hostSession, message.request, previous.playerId), tag)
        end
        self:SendProjection(previous)
        return
    end
    local playerId, reason = Cards.Controller:AcceptJoin(sender)
    if not playerId then
        Send(sender, Protocol.Error(message.request, nil, reason), "cards:join-error")
        return
    end
    local peer = {
        name = sender,
        key = key,
        request = message.request,
        playerId = playerId,
        lastSequence = 0,
        lastSeen = now,
    }
    self.peers[key] = peer
    Cards.Controller:SetConnected(playerId, true)
    Send(sender, Protocol.Welcome(self.hostSession, message.request, playerId), PeerTag(peer, "welcome"))
    self:Broadcast()
end

function Session:ReceiveHost(sender, message, now)
    if message.code == "J" then
        self:ReceiveJoin(sender, message, now)
        return
    end
    local peer = self:PeerFor(sender, message)
    if not peer then
        return
    end
    peer.lastSeen = now
    if message.sequence and message.sequence == peer.lastSequence then
        self:RepeatResponse(peer, message.sequence)
        return
    end
    if message.code == "T" then
        return
    end
    if message.code == "L" then
        Cards.Controller:SetConnected(peer.playerId, false)
        self.peers[peer.key] = nil
        Games.Discovery:Advertise()
        return
    end
    local accepted, reason
    if message.code == "A" then
        if message.revision ~= Cards.Controller.game.revision then
            self:Reject(peer, message.sequence, "stale_action")
            return
        end
        accepted, reason = Cards.Controller:AcceptAction(peer.playerId, message.action, message.targetAmount)
    elseif message.code == "O" then
        accepted, reason = Cards.Controller:SetSittingOut(peer.playerId, message.sittingOut)
    elseif message.code == "B" then
        accepted, reason = Cards.Controller:Rebuy(peer.playerId)
    else
        return
    end
    if accepted then
        self:Acknowledge(peer, message.sequence)
    else
        self:Reject(peer, message.sequence, reason or "invalid_action")
    end
end

function Session:Reconnect(now, notice)
    local client = self.client
    Games.Comms:Clear()
    client.request = NewRequest(now)
    client.session = nil
    client.playerId = nil
    ClearPending(client)
    client.joinedAt = now
    client.lastHeard = now
    client.nextJoin = now + JOIN_RETRY
    self.view = {
        role = "participant",
        state = "disconnected",
        gameTypeId = Cards.id,
        hostName = client.name,
        notice = notice,
    }
    Send(client.name, Protocol.Join(client.request, client.advertisedSession), "cards:join")
end

function Session:ReceiveParticipant(message, now)
    local client = self.client
    if message.code == "E" then
        if message.request ~= client.request then
            return
        end
        if message.sequence and message.sequence ~= client.pendingSequence then
            return
        end
        ClearPending(client)
        self.view.pending = false
        self.view.notice = L.errors[message.reason] or message.reason
        if not message.sequence and not client.session then
            self.client = nil
            self.view.state = "disconnected"
        end
        return
    end
    if message.code == "W" then
        if message.request ~= client.request then
            return
        end
        if client.advertisedSession and message.sessionId ~= client.advertisedSession then
            return
        end
        if client.session then
            if client.session == message.sessionId and client.playerId == message.playerId then
                client.lastHeard = now
            end
            return
        end
        if client.projectionSession ~= message.sessionId then
            client.lastProjectionRevision = nil
            client.projectionSession = message.sessionId
        end
        client.session = message.sessionId
        client.advertisedSession = message.sessionId
        client.playerId = message.playerId
        client.lastHeard = now
        self.view.session = message.sessionId
        self.view.sessionId = message.sessionId
        self.view.playerId = message.playerId
        self.view.state = "waiting"
        return
    end
    if not client.session or message.sessionId ~= client.session then
        return
    end
    if message.code == "X" then
        Games.Comms:Clear()
        self.client = nil
        self.view.state, self.view.notice = "stopped", L.STATUS_STOPPED
        return
    end
    if message.code == "K" then
        if message.request == client.request and message.sequence == client.pendingSequence then
            ClearPending(client)
            self.view.pending = false
            self.view.notice = nil
        end
        client.lastHeard = now
        return
    end
    if message.code ~= "P" then
        return
    end
    local projection = Cards.TexasHoldem.Codec.DecodeProjection(message.payload, now)
    if not projection then
        return
    end
    if client.lastProjectionRevision and message.revision <= client.lastProjectionRevision then
        return
    end
    client.lastProjectionRevision = message.revision
    projection.role = "participant"
    projection.gameTypeId = Cards.id
    projection.hostName = client.name
    projection.session = client.session
    projection.sessionId = client.session
    projection.playerId = client.playerId
    projection.pending = client.pendingSequence ~= nil
    projection.notice = self.view.notice
    self.view = projection
    client.lastHeard = now
end

function Session:Receive(sender, fields)
    if self.restricted or Games.Main:IsRestricted() then
        return
    end
    local name = Games.Identity:NormalizeName(sender)
    local message = Protocol.Decode(fields)
    if not name or not message then
        return
    end
    local now = GetTime()
    if self.hostSession then
        self:ReceiveHost(name, message, now)
    elseif self.client and name:lower() == self.client.key then
        self:ReceiveParticipant(message, now)
    end
end

function Session:SetRestricted(restricted)
    self.restricted = restricted == true
end

function Session:OnSendError(target, reason)
    if reason == "addon_lockdown" then
        Games.Main.restrictedUntil = GetTime() + SNAPSHOT_INTERVAL
        Games.Main:SyncRestriction()
        return
    end
    if self.client and target:lower() == self.client.key then
        self.view.notice = L.errors[reason] or L.NET_SEND_FAILED
    elseif self.hostSession then
        Cards.Controller:SetNotice(L.errors[reason] or L.NET_SEND_FAILED)
    end
end

function Session:Tick(now)
    if self.restricted then
        return
    end
    if self.hostSession then
        for key, peer in pairs(self.peers) do
            if now - peer.lastSeen >= PEER_TIMEOUT then
                Cards.Controller:SetConnected(peer.playerId, false)
                self.peers[key] = nil
            end
        end
        if now >= self.nextSnapshot then
            self.nextSnapshot = now + SNAPSHOT_INTERVAL
            self:Broadcast()
        end
        return
    end
    local client = self.client
    if not client then
        return
    end
    if not client.session then
        if now - client.joinedAt >= JOIN_TIMEOUT then
            self.client = nil
            self.view.state, self.view.notice = "disconnected", L.NET_JOIN_TIMEOUT
            Games.Comms:Clear()
        elseif now >= client.nextJoin then
            client.nextJoin = now + JOIN_RETRY
            Send(client.name, Protocol.Join(client.request, client.advertisedSession), "cards:join")
        end
        return
    end
    if now - client.lastHeard >= HOST_TIMEOUT then
        self:Reconnect(now, L.NET_HOST_SILENT)
        return
    end
    if client.pendingSequence and now >= client.nextActionRetry then
        client.nextActionRetry = now + ACTION_RETRY_INTERVAL
        if not Games.Comms:IsTagBusy(client.pendingTag) then
            local sent, reason = Send(client.name, client.pendingFields, client.pendingTag)
            if not sent then
                self:OnSendError(client.name, reason)
                return
            end
        end
    end
    if now >= client.nextHeartbeat then
        client.nextHeartbeat = now + HEARTBEAT_INTERVAL
        Send(client.name, Protocol.Heartbeat(client.session, client.request), "cards:heartbeat")
    end
end

function Session:Shutdown()
    self:Initialize()
end

Session:Initialize()

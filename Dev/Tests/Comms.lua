return function(Quiz)
    local PREFIX = "ORBITQUIZ8"
    local assertions = 0
    local Comms = Quiz.Comms
    local originals = {
        chat = C_ChatInfo,
        enum = Enum,
        time = GetTime,
        realm = GetNormalizedRealmName,
        secret = issecretvalue,
        comms = {},
    }
    for key, value in pairs(Comms) do
        originals.comms[key] = value
    end
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(
            actual == expected,
            (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
        )
    end
    local secret = setmetatable({}, {
        __index = function()
            error("secret field accessed")
        end,
        __concat = function()
            error("secret concatenated")
        end,
        __tostring = function()
            error("secret converted")
        end,
    })
    local now, realm, restricted, registration, sent, received, failures, nativeResults, sendHook
    Enum = {
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
    GetTime = function()
        return now
    end
    GetNormalizedRealmName = function()
        return realm
    end
    issecretvalue = function(value)
        return rawequal(value, secret) or originals.secret(value)
    end
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            Same(prefix, PREFIX, "prefix registration")
            return registration
        end,
        InChatMessagingLockdown = function()
            return restricted
        end,
        SendAddonMessage = function(prefix, message, channel, target)
            Check(not restricted and not Comms.suspended, "no send while restricted")
            Same(prefix, PREFIX, "wire prefix")
            Check(#prefix <= 16, "prefix byte limit")
            Check(#message <= 255 and not message:find("\000", 1, true), "packet byte and NUL limits")
            Same(channel, "WHISPER", "only directed addon whispers")
            Check(type(target) == "string" and target:find("-", 1, true), "qualified native target")
            sent[#sent + 1] = { text = message, target = target, at = now }
            local planned = nativeResults[#sent]
            if sendHook then
                sendHook()
            end
            if planned then
                return planned.result
            end
            return Enum.SendAddonMessageResult.Success
        end,
    }
    local function OnMessage(sender, fields)
        received[#received + 1] = { sender = sender, fields = fields }
    end
    local function OnError(target, reason)
        failures[#failures + 1] = { target = target, reason = reason }
    end
    local function Fresh()
        now, realm, restricted, registration = 100, "TestRealm", false, Enum.RegisterAddonMessagePrefixResult.Success
        sent, received, failures, nativeResults, sendHook = {}, {}, {}, {}, nil
        Comms.suspended = false
        Comms.ticking = false
        Comms.tokens = nil
        Check(Comms:Initialize(OnMessage, OnError), "transport initializes")
    end
    local function Tick(at)
        now = at
        Comms:Tick(now)
    end
    local function Drain()
        for _ = 1, 160 do
            Comms:Tick(now)
            if not Comms:IsBusy() then
                return
            end
            now = now + 0.125
        end
        error("queue failed to drain")
    end
    local function Packet(id, part, total, payload)
        return ("1|%s|%d|%d|%s"):format(id, part, total, payload)
    end
    local function Player(index)
        return "Player" .. string.char(65 + math.floor(index / 26)) .. string.char(65 + index % 26) .. "-Realm"
    end
    local function Rejected(target, fields, reason, tag)
        local ok, actual = Comms:Send(target, fields, tag)
        Same(ok, false, "send rejected")
        Same(actual, reason, "send rejection reason")
    end

    Fresh()
    Same(Quiz.Identity:NormalizeName("  Alice  "), "Alice-TestRealm", "local realm supplied")
    Same(Quiz.Identity:NormalizeName("Alice-ForeignRealm"), "Alice-ForeignRealm", "foreign realm preserved")
    Same(Quiz.Identity:NormalizeName("Élise-Éitrigg"), "Élise-Éitrigg", "UTF-8 identity retained")
    Same(Quiz.Identity:NormalizeName("Alice-Azjol-Nerub"), "Alice-Azjol-Nerub", "realm hyphens retained")
    Same(Quiz.Identity:NormalizeName("Alice-Kel'Thuzad"), "Alice-Kel'Thuzad", "realm apostrophe retained")
    for _, name in ipairs({
        "",
        " ",
        "Alice-",
        "-Realm",
        "A lice",
        "Alice-Two Realms",
        "Alice\n",
        "\tAlice",
        "A|cfffffff",
        "<Alice>",
        "Alice-[Realm]",
        "Alice-{}",
        "Alice/Realm",
        string.rep("A", 121),
    }) do
        Same(Quiz.Identity:NormalizeName(name), nil, "invalid name rejected")
    end
    Same(Quiz.Identity:NormalizeName(secret), nil, "secret name rejected before use")
    Same(Quiz.Identity:NormalizeName(12), nil, "numeric name rejected")
    realm = secret
    Same(Quiz.Identity:NormalizeName("Alice"), nil, "secret local realm rejected")
    Same(
        Quiz.Identity:NormalizeName("Alice-OtherRealm"),
        "Alice-OtherRealm",
        "explicit foreign realm needs no local realm query"
    )
    realm = "Bad Realm"
    Same(Quiz.Identity:NormalizeName("Alice"), nil, "invalid native realm rejected")
    realm = "TestRealm"
    Same(#Quiz.Identity:NormalizeName(string.rep("A", 118) .. "-R"), 120, "maximum full name accepted")

    registration = Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix
    Check(Comms:Initialize(OnMessage, OnError), "duplicate registration is successful")
    for _, result in ipairs({
        Enum.RegisterAddonMessagePrefixResult.InvalidPrefix,
        Enum.RegisterAddonMessagePrefixResult.MaxPrefixes,
        99,
        false,
        secret,
    }) do
        registration = result
        local ok, reason = Comms:Initialize(OnMessage, OnError)
        Same(ok, false, "invalid enum registration rejected")
        Same(reason, "send_failed", "registration failure reason")
        Rejected("Alice", { "hello" }, "send_failed")
    end

    Fresh()
    Rejected("Alice", secret, "codec_invalid")
    Rejected("Alice", { secret }, "codec_invalid")
    Rejected("Alice", { "valid", 12 }, "codec_invalid")
    Rejected("Alice", { [1] = "valid", [3] = "hole" }, "codec_invalid")
    Rejected("Alice", { wrong = "key" }, "codec_invalid")
    Rejected("Alice", { [1.5] = "fraction" }, "codec_invalid")
    Rejected(
        "Alice",
        setmetatable({ "test" }, {
            __index = function()
                error("unsafe metatable")
            end,
        }),
        "codec_invalid"
    )
    Rejected("Alice", { "has\000nul" }, "codec_invalid")
    Rejected("Alice", { string.rep("x", 4090) }, "message_too_large")
    Rejected("Alice", { "valid" }, "codec_invalid", secret)
    Rejected(secret, { "valid" }, "invalid_target")
    Rejected("Alice-", { "valid" }, "invalid_target")
    local manyFields = {}
    for index = 1, 33 do
        manyFields[index] = "x"
    end
    Rejected("Alice", manyFields, "codec_invalid")
    Same(#sent, 0, "invalid packets never reach native send")
    Same(#failures, 0, "validation errors return without invoking callbacks")

    Fresh()
    local fields = {
        "QUESTION",
        "",
        "leading:123|trailing",
        "A\001B\031C\tD\nE",
        "中文/Élise",
        string.rep("é", 180),
        "sender=Impostor",
    }
    Check(Comms:Send("Alice-OtherRealm", fields, "round"), "valid fields queue")
    Check(Comms:IsBusy(), "queued send is busy")
    Same(#sent, 0, "Send never calls native transport immediately")
    Drain()
    Check(#sent > 1, "long UTF-8 payload fragments")
    Same(#failures, 0, "normal sending reports no failure")
    for index = #sent, 1, -1 do
        Check(Comms:Receive(PREFIX, sent[index].text, "WHISPER", "Bob-Remote"), "out-of-order fragment accepted")
    end
    Same(#received, 1, "message delivered once after complete assembly")
    Same(received[1].sender, "Bob-Remote", "native sender is identity, not a payload field")
    for index, field in ipairs(fields) do
        Same(received[1].fields[index], field, "length-prefix round trip")
    end
    for _, packet in ipairs(sent) do
        Check(Comms:Receive(PREFIX, packet.text, "WHISPER", "Bob-Remote"), "duplicate complete fragments ignored")
    end
    Same(#received, 1, "duplicate complete message remains idempotent")
    for _, packet in ipairs(sent) do
        Check(Comms:Receive(PREFIX, packet.text, "WHISPER", "Carol-Remote"), "distinct sender has independent assembly")
    end
    Same(#received, 2, "same message id from a different native sender remains distinct")

    Fresh()
    Check(Comms:Send("Alice", { string.rep("x", 4089) }), "4096-byte assembled payload accepted")
    Drain()
    Check(#sent <= 32, "fragment count remains bounded")
    for _, packet in ipairs(sent) do
        Check(Comms:Receive(PREFIX, packet.text, "WHISPER", "Alice"), "maximum payload fragment accepted")
    end
    Same(#received, 1, "maximum payload assembles")
    Same(#received[1].fields[1], 4089, "maximum payload preserved exactly")
    Check(Comms:Receive(PREFIX, Packet("empty", 1, 1, "0:"), "WHISPER", "Alice"), "empty string list accepted")
    Same(#received[2].fields, 0, "empty list remains empty")
    manyFields[33] = nil
    Check(Comms:Send("Alice", manyFields), "32 fields accepted")
    local previousCount = #sent
    Drain()
    for index = previousCount + 1, #sent do
        Comms:Receive(PREFIX, sent[index].text, "WHISPER", "Alice")
    end
    Same(#received[3].fields, 32, "32 fields decode")

    Fresh()
    local valid = Packet("valid", 1, 1, "1:1:x")
    Same(Comms:Receive("FOREIGN", valid, "WHISPER", "Alice"), false, "foreign prefix ignored")
    Same(
        Comms:Receive("ORBITQUIZ2", valid, "WHISPER", "Alice"),
        false,
        "four-choice clients cannot enter protocol seven"
    )
    Same(
        Comms:Receive("ORBITQUIZ3", valid, "WHISPER", "Alice"),
        false,
        "old zero-penalty clients cannot enter protocol seven"
    )
    Same(
        Comms:Receive("ORBITQUIZ4", valid, "WHISPER", "Alice"),
        false,
        "old league-score clients cannot enter protocol seven"
    )
    Same(
        Comms:Receive("ORBITQUIZ5", valid, "WHISPER", "Alice"),
        false,
        "pre-winner clients cannot enter protocol seven"
    )
    Same(
        Comms:Receive("ORBITQUIZ6", valid, "WHISPER", "Alice"),
        false,
        "fixed-rule clients cannot enter protocol seven"
    )
    Same(Comms:Receive(PREFIX, valid, "GUILD", "Alice"), false, "other distributions ignored")
    Same(Comms:Receive(secret, valid, "WHISPER", "Alice"), false, "secret prefix ignored")
    Same(Comms:Receive(PREFIX, secret, "WHISPER", "Alice"), false, "secret text ignored")
    Same(Comms:Receive(PREFIX, valid, secret, "Alice"), false, "secret distribution ignored")
    Same(Comms:Receive(PREFIX, valid, "WHISPER", secret), false, "secret sender ignored")
    Same(Comms:Receive(PREFIX, valid, "WHISPER", "Bad Sender"), false, "invalid sender ignored")
    Same(Comms:Receive(PREFIX, false, "WHISPER", "Alice"), false, "invalid text type ignored")
    for _, invalid in ipairs({
        "",
        "2|id|1|1|1:1:x",
        "1|id|1|1",
        "1||1|1|1:1:x",
        "1|id|0|1|1:1:x",
        "1|id|1|0|1:1:x",
        "1|id|01|1|1:1:x",
        "1|id|1|01|1:1:x",
        "1|id|2|1|1:1:x",
        "1|id|1|33|1:1:x",
        "1|id|nan|1|1:1:x",
        "1|id|1|1|",
        Packet(string.rep("x", 33), 1, 1, "1:1:x"),
        Packet("nul", 1, 1, "1:1:\000"),
        Packet("huge", 1, 1, string.rep("x", 201)),
        string.rep("x", 256),
    }) do
        Same(Comms:Receive(PREFIX, invalid, "WHISPER", "Alice"), false, "malformed wire packet rejected")
    end
    for index, invalid in ipairs({
        "1:",
        "33:",
        "1:-1:x",
        "1:1:xjunk",
        "1:01:x",
        "1:99999:x",
        "00:",
        "1:1:",
        "0:extra",
        "1:a:x",
    }) do
        Same(
            Comms:Receive(PREFIX, Packet("codec" .. index, 1, 1, invalid), "WHISPER", "Alice"),
            false,
            "malformed codec rejected"
        )
    end
    Same(#received, 0, "invalid traffic never reaches application callbacks")
    Same(#failures, 0, "invalid inbound traffic does not generate error callback spam")

    Fresh()
    Check(Comms:Send("Alice", { string.rep("x", 450) }), "multipart message queues")
    Drain()
    Check(#sent > 2, "multipart test uses three packets")
    Check(Comms:Receive(PREFIX, sent[1].text, "WHISPER", "Alice"), "first fragment accepted")
    Check(Comms:Receive(PREFIX, sent[1].text, "WHISPER", "Alice"), "identical fragment duplicate accepted")
    for index = 2, #sent do
        Check(
            Comms:Receive(PREFIX, sent[index].text, "WHISPER", "Bob"),
            "other sender fragments buffered independently"
        )
    end
    Same(#received, 0, "fragments from different native senders cannot combine")
    for index = 2, #sent do
        Comms:Receive(PREFIX, sent[index].text, "WHISPER", "Alice")
    end
    Same(#received, 1, "first sender completed with own fragments")
    Comms:Receive(PREFIX, sent[1].text, "WHISPER", "Bob")
    Same(#received, 2, "second sender independently completed")
    local altered = sent[1].text:sub(1, -2) .. "z"
    Comms:Receive(PREFIX, sent[1].text, "WHISPER", "Carol")
    Same(Comms:Receive(PREFIX, altered, "WHISPER", "Carol"), false, "conflicting duplicate invalidates assembly")
    for index = 2, #sent do
        Comms:Receive(PREFIX, sent[index].text, "WHISPER", "Carol")
    end
    Same(#received, 2, "poisoned assembly cannot later complete")
    Comms:Receive(PREFIX, Packet("mismatch", 1, 2, "1:1:"), "WHISPER", "Alice")
    Same(
        Comms:Receive(PREFIX, Packet("mismatch", 2, 3, "x"), "WHISPER", "Alice"),
        false,
        "conflicting fragment total invalidates assembly"
    )

    Fresh()
    for part = 1, 20 do
        Check(
            Comms:Receive(PREFIX, Packet("overflow", part, 32, string.rep("x", 200)), "WHISPER", "Alice"),
            "bounded partial fragment accepted"
        )
    end
    Same(
        Comms:Receive(PREFIX, Packet("overflow", 21, 32, string.rep("x", 200)), "WHISPER", "Alice"),
        false,
        "assembled size over 4096 rejected"
    )
    Same(Comms.assemblyCount, 0, "oversized assembly released")
    Same(#received, 0, "oversized assembly never delivered")

    Fresh()
    for index = 1, 32 do
        Check(
            Comms:Receive(PREFIX, Packet("partial" .. index, 1, 2, "1:1:"), "WHISPER", "Alice"),
            "assembly slot accepted"
        )
    end
    Same(Comms.assemblyCount, 32, "assembly cap reached")
    Same(
        Comms:Receive(PREFIX, Packet("extra", 1, 2, "1:1:"), "WHISPER", "Alice"),
        false,
        "assembly cap refuses new work"
    )
    Tick(115)
    Same(Comms.assemblyCount, 0, "assemblies expire at the deadline")
    Check(
        Comms:Receive(PREFIX, Packet("partial1", 2, 2, "x"), "WHISPER", "Alice"),
        "late fragments ignored through recent cache"
    )
    Same(#received, 0, "expired assembly cannot resurrect")
    Tick(176)
    Same(Comms.peerCount, 0, "expired recent entries release peer slots")

    Fresh()
    for index = 1, 32 do
        Check(Comms:Receive(PREFIX, Packet("partial", 1, 2, "1:1:"), "WHISPER", Player(index)), "peer slot accepted")
    end
    Same(Comms.peerCount, 32, "peer cap reached")
    Same(
        Comms:Receive(PREFIX, Packet("partial", 1, 2, "1:1:"), "WHISPER", Player(33)),
        false,
        "peer cap refuses new work"
    )
    Comms:Clear()
    Same(Comms.peerCount, 0, "clear releases all peers")
    Same(Comms.assemblyCount, 0, "clear releases assemblies")
    for index = 1, 200 do
        Check(
            Comms:Receive(PREFIX, Packet("complete" .. index, 1, 1, "1:1:x"), "WHISPER", "Alice"),
            "recent-cache rollover accepts complete packets"
        )
    end
    local cached = 0
    for _ in pairs(Comms.recent) do
        cached = cached + 1
    end
    Same(cached, 128, "recent cache is bounded")
    Comms:Receive(PREFIX, Packet("complete200", 1, 1, "1:1:x"), "WHISPER", "Alice")
    Same(#received, 200, "newest cache entry stays idempotent")

    Fresh()
    for _ = 1, 16 do
        Check(Comms:Send("Alice", { "x" }), "paced packet queues")
    end
    Tick(100)
    Same(#sent, 8, "initial burst is eight packets")
    Tick(100)
    Same(#sent, 8, "same-time tick grants no extra tokens")
    Tick(100.125)
    Same(#sent, 9, "one eighth second replenishes one token")
    Tick(101)
    Same(#sent, 16, "remaining packets send at configured rate")
    Same(Comms:IsBusy(), false, "paced queue fully drained")
    Comms:Clear()
    Check(Comms:Send("Alice", { "x" }), "queue after clear")
    Tick(101)
    Same(#sent, 16, "clear does not replenish rate tokens")
    Tick(101.125)
    Same(#sent, 17, "clear leaves normal refill operational")

    Fresh()
    local maximumRules = assert(Quiz.Rules.Normalize({
        version = 2147483647,
        answerSeconds = 120,
        revealSeconds = 30,
        questionLimit = 2000,
        correctPoints = 1000,
        speedBonusPerSecond = 10,
        wrongPenaltyStart = 1000,
        wrongPenaltyEnd = 1000,
        wrongPenaltyCurve = 10,
        streakBonusPerCorrect = 10,
        streakBonusMax = 100,
    }))
    local largestQuestion = {
        "Q",
        string.rep("s", 64),
        "9007199254740990",
        "9007199254740990",
        "9007199254740990",
        "9007199254740990",
        "120",
        string.rep("q", 160),
        "6",
        "very_hard",
        string.rep("e", 64),
        string.rep("p", 48),
        string.rep("t", 64),
        "2147483647",
        tostring(Quiz.Scoring.VERSION),
        assert(Quiz.Rules.Encode(maximumRules)),
    }
    for index = 1, 6 do
        largestQuestion[#largestQuestion + 1] = string.rep("c", 99) .. index
    end
    Same(#largestQuestion, 22, "largest current question includes pack rules within the codec field bound")
    for index = 1, 16 do
        Check(Comms:Send(Player(index), largestQuestion), "maximum six-choice payload queues for every participant")
    end
    Same(Comms.queueCount, 112, "maximum bounded question uses seven fragments per participant")
    Drain()
    Same(#sent, 112, "all maximum-size questions drain without increasing the packet rate")
    Same(#failures, 0, "queue lifetime covers a complete sixteen-player question batch")
    Check(now < 120, "maximum question batch fits the bounded twenty-second readiness allowance")
    for _, packet in ipairs(sent) do
        Comms:Receive(PREFIX, packet.text, "WHISPER", packet.target)
    end
    Same(#received, 16, "all maximum-size question payloads reassemble")
    for _, message in ipairs(received) do
        Same(#message.fields, 22, "reassembled maximum question retains every current field")
        Same(message.fields[16], largestQuestion[16], "canonical pack rules survive maximum-size transport")
        Same(message.fields[22], largestQuestion[22], "the sixth maximum-length choice survives transport")
    end

    Fresh()
    local speakerIds, speakerNames = {}, {}
    for index = 1, 4 do
        speakerIds[index] = string.format("%.0f", 9007199254740986 + index)
        speakerNames[index] = string.rep(string.char(64 + index), 114) .. "-Realm"
    end
    local largestNameBatch = {
        "N",
        string.rep("s", 64),
        string.rep("r", 64),
        table.concat(speakerIds, ","),
        table.concat(speakerNames, ","),
    }
    for index = 1, 16 do
        Check(
            Comms:Send(Player(index), largestNameBatch),
            "bounded four-name metadata fits every supported participant"
        )
    end
    Same(Comms.queueCount, 64, "even maximum-length names use at most four fragments per bounded identity batch")
    Drain()
    Same(#failures, 0, "a complete maximum-size identity batch fits the normal transport lifetime")
    for _, packet in ipairs(sent) do
        Comms:Receive(PREFIX, packet.text, "WHISPER", packet.target)
    end
    Same(#received, 16, "maximum-size metadata survives ordinary addon fragmentation")
    for _, message in ipairs(received) do
        Same(message.fields[4], largestNameBatch[4], "full speaker IDs survive bounded metadata delivery")
        Same(message.fields[5], largestNameBatch[5], "full qualified names survive bounded metadata delivery")
    end

    Fresh()
    for _ = 1, 512 do
        Check(Comms:Send("Alice", { "x" }, "capacity"), "packet queue slot accepted")
    end
    Same(Comms.queueCount, 512, "queue cap reached")
    Rejected("Alice", { "extra" }, "queue_full")
    Comms:Cancel("capacity")
    Same(Comms:IsBusy(), false, "cancel frees queue capacity")
    Same(Comms.queuePeerCount, 0, "cancel releases outbound peer slots")
    for index = 1, 32 do
        Check(Comms:Send(Player(index), { "x" }), "outbound peer accepted")
    end
    Rejected(Player(33), { "x" }, "queue_full")
    Same(Comms.queueCount, 32, "failed peer allocation leaves queue unchanged")

    Fresh()
    Check(Comms:Send("Alice", { string.rep("x", 1800) }, "obsolete"), "long tagged message queues")
    Check(Comms:Send("Bob", { "next" }, "current"), "next tagged message queues")
    Tick(100)
    Same(#sent, 8, "partial tagged message sends initial burst")
    Comms:Cancel("different")
    Check(Comms.queueCount > 1, "unrelated cancellation does nothing")
    Comms:Cancel("obsolete")
    Same(Comms.queueCount, 1, "cancel removes only remaining obsolete fragments")
    Drain()
    Same(#sent, 9, "only surviving tagged message follows")
    Same(sent[9].target, "Bob-TestRealm", "current message target preserved")
    Same(#failures, 0, "cancellation is not a native failure")

    Fresh()
    restricted = true
    Rejected("Alice", { "hello" }, "addon_lockdown")
    Same(Comms:Receive(PREFIX, valid, "WHISPER", "Alice"), false, "receive paused in native lockdown")
    restricted = false
    Comms.suspended = true
    Rejected("Alice", { "hello" }, "addon_lockdown")
    Same(Comms:Receive(PREFIX, valid, "WHISPER", "Alice"), false, "receive paused in activating state")
    Comms.suspended = false
    Check(Comms:Send("Alice", { "hello" }), "packet queues when safe")
    Comms.suspended = true
    Tick(100)
    Same(#sent, 0, "queued sends do not bypass activating state")
    Comms.suspended = false
    restricted = true
    Tick(100.25)
    Same(#sent, 0, "queued sends do not bypass native lockdown")
    restricted = false
    Tick(100.5)
    Same(#sent, 1, "queued send proceeds after clear")

    Fresh()
    Check(Comms:Send("Alice", { "hello" }), "expiring message queues")
    Tick(115)
    Same(#sent, 0, "expired outbound message is never sent")
    Same(#failures, 1, "expiry reports one terminal failure")
    Same(failures[1].reason, "send_failed", "expiry failure code")
    Same(Comms:IsBusy(), false, "expired queue clears")

    Fresh()
    nativeResults[1] = { result = Enum.SendAddonMessageResult.AddonMessageThrottle }
    Check(Comms:Send("Alice", { "hello" }), "retry message queues")
    Tick(100)
    Same(#sent, 1, "first throttled attempt occurs once")
    Check(Comms:IsBusy(), "prefix throttle retains packet")
    Tick(100.49)
    Same(#sent, 1, "retry waits for backoff")
    Tick(100.5)
    Same(#sent, 2, "prefix throttle retries after backoff")
    Same(sent[1].text, sent[2].text, "retry uses identical wire identity")
    Same(Comms:IsBusy(), false, "successful retry drains queue")
    Same(#failures, 0, "successful retry reports no terminal error")

    Fresh()
    for index = 1, 5 do
        nativeResults[index] = { result = Enum.SendAddonMessageResult.AddonMessageThrottle }
    end
    Comms:Send("Alice", { "hello" })
    for _, at in ipairs({ 100, 100.5, 101.5, 103.5, 105.5 }) do
        Tick(at)
    end
    Same(#sent, 5, "retry count bounded")
    Same(Comms:IsBusy(), false, "exhausted retry dropped")
    Same(#failures, 1, "retry exhaustion reports once")
    Same(failures[1].reason, "send_failed", "retry exhaustion code")

    Fresh()
    nativeResults[1] = { result = Enum.SendAddonMessageResult.ChannelThrottle }
    Comms:Send("Alice", { "hello" })
    Tick(100)
    Tick(101)
    Same(#sent, 1, "channel throttle is not blindly resent")
    Same(Comms:IsBusy(), false, "channel-throttled packet handed to app acknowledgement policy")
    Same(#failures, 0, "ambiguous channel throttle is not reported as definite terminal failure")

    for _, case in ipairs({
        { value = 12, reason = "target_offline" },
        { value = 9, reason = "send_failed" },
        { value = 4, reason = "send_failed" },
        { value = false, reason = "send_failed" },
        { reason = "send_failed" },
        { value = secret, reason = "send_failed" },
    }) do
        Fresh()
        nativeResults[1] = { result = case.value }
        Comms:Send("Alice", { string.rep("x", 450) })
        Tick(100)
        Same(#sent, 1, "terminal native error drops remaining fragments")
        Same(Comms:IsBusy(), false, "terminal error removes whole message")
        Same(#failures, 1, "terminal error delivered once")
        Same(failures[1].target, "Alice-TestRealm", "error native target identity")
        Same(failures[1].reason, case.reason, "terminal native error mapping")
    end

    Fresh()
    nativeResults[1] = { result = Enum.SendAddonMessageResult.AddOnMessageLockdown }
    Comms:Send("Alice", { "first" })
    Comms:Send("Bob", { "second" })
    Tick(100)
    Tick(101)
    Same(#sent, 1, "native lockdown immediately halts subsequent traffic")
    Same(Comms.suspended, true, "native lockdown waits for owner resume")
    Same(#failures, 1, "native lockdown notification once")
    Same(failures[1].reason, "addon_lockdown", "native lockdown error code")

    Fresh()
    Comms:Send("Alice", { "first" })
    sendHook = function()
        sendHook = nil
        Check(Comms:Send("Bob", { "response" }), "native callback can queue a response")
        Comms:Tick(now)
    end
    Tick(100)
    Same(#sent, 1, "native callbacks cannot recursively send or expand the current batch")
    Tick(100)
    Same(#sent, 2, "callback-generated response waits until following tick")

    Fresh()
    Comms:Send("Alice", { "first" }, "old")
    sendHook = function()
        sendHook = nil
        Comms:Clear()
        Comms:Send("Bob", { "new" }, "new")
    end
    Tick(100)
    Same(#sent, 1, "clear during native call stops current drain")
    Same(Comms.queueCount, 1, "clear during native call preserves newly queued traffic")
    Tick(100)
    Same(#sent, 2, "new queue drains on subsequent tick")
    Same(sent[2].target, "Bob-TestRealm", "new queue did not lose or redirect target")

    Fresh()
    nativeResults[1] = { result = Enum.SendAddonMessageResult.TargetOffline }
    Comms.onError = function(target, reason)
        OnError(target, reason)
        Comms:Send("Bob", { "response" })
        Comms:Tick(now)
    end
    Comms:Send("Alice", { "first" })
    Tick(100)
    Same(#sent, 1, "error callback cannot recursively drain")
    Same(#failures, 1, "error callback invoked once")
    Tick(100)
    Same(#sent, 2, "error callback can queue work for next tick")

    Fresh()
    for _ = 1, 3 do
        Comms:Send("Alice", { "first" })
    end
    Tick(115)
    Same(#failures, 1, "same-target expiry failures coalesce")
    Comms:Send("Alice", { "first" })
    Tick(115)
    local beforeClear = sent[#sent].text
    Comms:Clear()
    Comms:Send("Alice", { "second" })
    Tick(111)
    Check(beforeClear ~= sent[#sent].text, "clear does not reuse message identifiers")

    for key in pairs(Comms) do
        Comms[key] = nil
    end
    for key, value in pairs(originals.comms) do
        Comms[key] = value
    end
    C_ChatInfo, Enum, GetTime, GetNormalizedRealmName, issecretvalue =
        originals.chat, originals.enum, originals.time, originals.realm, originals.secret
    return assertions
end

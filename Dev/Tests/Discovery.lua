return function(Quiz)
    local Discovery = Quiz.Discovery
    local PREFIX = "ORBITQUIZDISC7"
    local LOBBY = "OrbitQuizLobby"
    local originals = {
        main = Quiz.Main,
        session = Quiz.Session,
        packs = Quiz.GetQuestionPacks,
        chat = C_ChatInfo,
        time = GetTime,
        realm = GetNormalizedRealmName,
        player = UnitFullName,
        guild = IsInGuild,
        group = IsInGroup,
        raid = IsInRaid,
        join = JoinChannelByName,
        secret = issecretvalue,
        suspended = Quiz.Comms.suspended,
        discovery = {},
    }
    for key, value in pairs(Discovery) do
        originals.discovery[key] = value
    end
    local assertions = 0
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
            error("read a secret field")
        end,
        __concat = function()
            error("concatenated a secret")
        end,
        __tostring = function()
            error("formatted a secret")
        end,
    })
    local now, restricted, eventRestricted, joined, autoJoin, channelID, metadata
    local guild, homeGroup, homeRaid, instanceGroup, registration, sendResults, sendHook
    local sent, joins, calls
    Quiz.Main = {
        IsRestricted = function()
            return restricted or eventRestricted
        end,
    }
    Quiz.Session = { peers = {} }
    Quiz.GetQuestionPacks = function()
        return {
            { id = "first", title = "First pack" },
            { id = "unicode", title = "Élémentaire 中文" },
        }
    end
    GetTime = function()
        return now
    end
    GetNormalizedRealmName = function()
        return "TestRealm"
    end
    UnitFullName = function(unit)
        Same(unit, "player", "only the local identity is read")
        return "Tester", "TestRealm"
    end
    IsInGuild = function()
        return guild
    end
    IsInGroup = function(category)
        if category == LE_PARTY_CATEGORY_HOME then
            return homeGroup
        elseif category == LE_PARTY_CATEGORY_INSTANCE then
            return instanceGroup
        end
        error("group category must be explicit")
    end
    IsInRaid = function(category)
        Same(category, LE_PARTY_CATEGORY_HOME, "raid discovery belongs to the home group")
        return homeRaid
    end
    issecretvalue = function(value)
        return rawequal(value, secret) or originals.secret(value)
    end
    local function Join(name, ...)
        Check(not restricted and not eventRestricted and not Quiz.Comms.suspended, "no join during restriction")
        Same(name, LOBBY, "only the dedicated lobby is auto-joined")
        Same(select("#", ...), 0, "no chat-frame attachment or password changes")
        joins[#joins + 1] = now
        if autoJoin then
            joined = true
        end
    end
    JoinChannelByName = Join
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            Same(prefix, PREFIX, "independent discovery prefix")
            Check(#prefix <= 16, "prefix fits the native byte cap")
            return registration
        end,
        InChatMessagingLockdown = function()
            return restricted
        end,
        GetChannelInfoFromIdentifier = function(identifier)
            calls = calls + 1
            Check(
                not restricted and not eventRestricted and not Quiz.Comms.suspended,
                "no channel reads while restricted"
            )
            Same(identifier, LOBBY, "lobby metadata is resolved by name")
            if metadata ~= nil then
                return metadata
            elseif joined then
                return { name = LOBBY, localID = channelID, channelType = Enum.PermanentChatChannelType.Custom }
            end
        end,
        SendAddonMessage = function(prefix, text, distribution, target)
            Check(not restricted and not eventRestricted and not Quiz.Comms.suspended, "no restricted native send")
            Same(prefix, PREFIX, "discovery never impersonates game transport")
            Check(#text <= 255 and not text:find("[%z\1-\31\127]"), "bounded printable packet")
            if distribution == "CHANNEL" then
                Check(joined, "only joined channel broadcasts")
                Same(target, tostring(channelID), "native channel number resolved at send time")
            elseif distribution == "WHISPER" then
                Check(type(target) == "string" and target:find("-", 1, true), "probe uses a qualified target")
            else
                Check(
                    distribution == "GUILD"
                        or distribution == "PARTY"
                        or distribution == "RAID"
                        or distribution == "INSTANCE_CHAT",
                    "only supported hidden broadcasts"
                )
                Same(target, nil, "group and guild are not targeted")
            end
            sent[#sent + 1] = { text = text, channel = distribution, target = target, at = now }
            if sendHook then
                sendHook()
            end
            return sendResults[#sent] or Enum.SendAddonMessageResult.Success
        end,
        SendChatMessage = function()
            error("discovery must never send visible chat")
        end,
    }
    local function Fresh()
        now, restricted, eventRestricted, joined, autoJoin, channelID = 100, false, false, true, true, 7
        metadata, sendHook = nil, nil
        guild, homeGroup, homeRaid, instanceGroup = false, false, false, false
        registration = Enum.RegisterAddonMessagePrefixResult.Success
        sent, joins, sendResults, calls = {}, {}, {}, 0
        JoinChannelByName = Join
        Quiz.Comms.suspended = false
        Quiz.Main.game = nil
        Quiz.Session.hostSession, Quiz.Session.peers, Quiz.Session.client = nil, {}, nil
        Check(Discovery:Initialize(), "discovery initializes")
        Check(Discovery:Start(), "discovery starts")
    end
    local function Tick(at)
        now = at
        Discovery:Tick(now)
    end
    local function Flush(seconds)
        for _ = 1, seconds do
            Tick(now + 1)
        end
    end
    local function Host(session, pack)
        Quiz.Session.hostSession = session or "100.1"
        Quiz.Main.game = { state = "open", settings = { packId = pack or "first", league = "League" } }
        Check(Discovery:Advertise(), "host schedules its advertisement")
    end
    local function Advert(session, pack, league, state, players)
        return table.concat(
            { "7", "A", session or "101.1", pack or "First pack", league or "League", state or "open", players or "1" },
            "|"
        )
    end
    local function Receive(text, sender, distribution, target, localID, channelName)
        return Discovery:Receive(
            PREFIX,
            text,
            distribution or "CHANNEL",
            sender or "Alice-TestRealm",
            target or "Tester-TestRealm",
            0,
            localID or channelID,
            channelName or LOBBY
        )
    end
    local function Player(index)
        return "Player" .. string.char(65 + math.floor(index / 26)) .. string.char(65 + index % 26) .. "-TestRealm"
    end

    Fresh()
    Same(Discovery:Start(), true, "start is idempotent")
    registration = Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix
    Check(Discovery:Initialize(), "an already registered native prefix is valid")
    for _, result in ipairs({
        Enum.RegisterAddonMessagePrefixResult.InvalidPrefix,
        Enum.RegisterAddonMessagePrefixResult.MaxPrefixes,
        true,
        false,
        secret,
    }) do
        registration = result
        Same(Discovery:Initialize(), false, "invalid registration result rejects")
        Same(Discovery:Start(), false, "failed registration cannot start discovery")
    end

    Fresh()
    joined = false
    Tick(100)
    Same(#joins, 0, "login does not immediately reshuffle channel allocation")
    Tick(102)
    Same(#joins, 1, "automatic lobby join needs no typing")
    Same(#sent, 0, "joining waits for native membership before lookup")
    Tick(103)
    Same(sent[1].text, "7|Q", "a lookup follows automatic join")
    Same(sent[1].channel, "CHANNEL", "solo discovery uses hidden lobby traffic")
    Same(#Discovery:GetGames(), 0, "sending a lookup does not fabricate hosts")

    Fresh()
    joined, autoJoin = false, false
    for _, at in ipairs({ 102, 103, 132, 133, 162, 163, 192, 193, 300 }) do
        Tick(at)
    end
    Same(#joins, 3, "join failures have a bounded retry count")
    Same(#sent, 0, "no guessed channel broadcasts after failed membership")
    Check(Discovery:Refresh(), "manual refresh permits another bounded membership attempt")
    Tick(301)
    Same(#joins, 4, "refresh retries without requiring channel text")
    Check(joins[4] - joins[3] >= 30, "native joins retain their rate limit")

    Fresh()
    joined, JoinChannelByName = false, nil
    Tick(102)
    Same(Discovery.lobbyReason, "discovery_lobby_unavailable", "missing join API is surfaced")
    guild = true
    Tick(103)
    Same(sent[1].channel, "GUILD", "missing lobby support degrades to existing guild membership")

    Fresh()
    guild, homeGroup, homeRaid, instanceGroup = true, true, true, true
    Host()
    Tick(100)
    Flush(7)
    local routes = {}
    for index, packet in ipairs(sent) do
        routes[packet.channel] = true
        if index > 1 then
            Check(packet.at - sent[index - 1].at >= 1, "all discovery sends share one rate limit")
        end
    end
    Check(
        routes.CHANNEL and routes.GUILD and routes.RAID and routes.INSTANCE_CHAT,
        "lobby, guild, home raid, and instance each discover"
    )
    Same(routes.PARTY, nil, "raid discovery does not duplicate into the party route")
    Fresh()
    joined, homeGroup = false, true
    Host()
    Tick(100)
    Same(sent[1].channel, "PARTY", "home party discovery works without a lobby")

    Fresh()
    Host("100.1", "unicode")
    Quiz.Session.peers["alice"] = { name = "Alice-TestRealm" }
    Tick(100)
    Check(sent[1].text:find("Élémentaire 中文", 1, true), "pack labels retain complete UTF-8 text")
    Check(sent[1].text:match("|open|2$"), "player count includes host and enrolled peers")
    Same(#Discovery:GetGames(), 0, "local hosting does not add an unjoinable self row")
    Same(Receive(sent[1].text, "Tester-TestRealm"), true, "self echo is handled without a fake remote game")
    Check(Discovery.lobbyConfirmed, "native self echo confirms the hidden lobby path")
    Same(#Discovery:GetGames(), 0, "self echo cannot appear as another host")

    Fresh()
    Check(Receive(Advert()), "valid native lobby advertisement is discovered")
    Check(Receive(Advert("102.1"), "Bob-TestRealm"), "another host coexists in the browser")
    local rows = Discovery:GetGames()
    Same(#rows, 2, "two joinable sessions are listed")
    Same(rows[1].hostName, "Alice-TestRealm", "list ordering is stable")
    Same(rows[1].session, "101.1", "session identity is retained")
    Same(rows[1].packName, "First pack", "pack metadata is retained")
    Same(rows[1].league, "League", "league metadata is retained")
    Same(rows[1].players, 1, "bounded numeric player count")
    Same(rows[1].expiresAt, 145, "unrefreshed hosts expire")
    rows[1].hostName, rows[1].state = "Injected", "stopped"
    Same(Discovery:GetGames()[1].hostName, "Alice-TestRealm", "UI rows cannot mutate the discovery registry")
    Same(Quiz.Session.client, nil, "discovery never automatically joins a session")
    Tick(146)
    Same(#Discovery:GetGames(), 0, "offline or silent hosts disappear")

    Fresh()
    Check(Receive(Advert(nil, nil, "Guild {Quiz}")), "braces remain legal in league names")
    Same(Discovery:GetGames()[1].league, "Guild {Quiz}", "legal league metadata is not rewritten")
    Host()
    Quiz.Main.game.settings.league = "Guild {Quiz}"
    Tick(100)
    Check(sent[1].text:find("|Guild {Quiz}|", 1, true), "host advertises every legal configured league")

    Fresh()
    Check(Receive(Advert()), "first session is discovered")
    now = 101
    Check(Receive(Advert("101.2")), "a new session replaces the same host's old row")
    Same(#Discovery:GetGames(), 1, "one native host has only one browser row")
    Same(Receive(Advert()), false, "late old-session advertisements cannot undo replacement")
    Check(Receive("7|X|101.1"), "stale withdrawal is harmless")
    Same(Discovery:GetGames()[1].session, "101.2", "stale withdrawal does not close the replacement")
    Check(Receive("7|X|101.2"), "matching stop withdraws a game")
    Same(#Discovery:GetGames(), 0, "stopped game disappears immediately")
    Same(Receive(Advert("101.2")), false, "queued advertisements cannot resurrect a withdrawn session")

    Fresh()
    for _, packet in ipairs({
        "1|A|101.1|Pack|League|open|1",
        "2|A|101.1|Pack|League|open|1",
        "3|A|101.1|Pack|League|open|1",
        "4|A|101.1|Pack|League|open|1",
        "5|A|101.1|Pack|League|open|1",
        "6|A|101.1|Pack|League|open|1",
        "7|A|101.1|Pack|League|open|0",
        "7|A|101.1|Pack|League|open|18",
        "7|A|101.1|Pack|League|open|nan",
        "7|A|101.1|Pack|League|open|1.5",
        "7|A|101.1|Pack|League|finished|1",
        "7|A|101.1|Pack|League|open|1|extra",
        "7|A||Pack|League|open|1",
        "7|A|101.1||League|open|1",
        "7|A|101.1|Pack||open|1",
        "7|A|101.1|{rt1}|League|open|1",
        "7|A|101.1|Pack\nInjected|League|open|1",
        "7|A|101.1|Pack\000Injected|League|open|1",
        "7|A|101.1|Pack\127Injected|League|open|1",
        Advert(string.rep("a", 65)),
        Advert(nil, string.rep("p", 65)),
        Advert(nil, nil, string.rep("l", 49)),
        string.rep("a", 256),
        "7|J|Alice",
        "7|Q|spoofed-target",
        "return loadstring('bad')()",
    }) do
        Same(Receive(packet), false, "malformed and unrelated wire messages reject")
    end
    Same(#Discovery:GetGames(), 0, "rejected packets allocate no hosts")
    Check(
        Receive(Advert(string.rep("a", 64), string.rep("p", 64), string.rep("l", 48), "paused", "17")),
        "maximum metadata sizes fit one packet"
    )

    Fresh()
    for _, distribution in ipairs({
        "SAY",
        "YELL",
        "OFFICER",
        "BATTLEGROUND",
        "UNKNOWN",
        "PARTY",
        "RAID",
        "GUILD",
        "INSTANCE_CHAT",
    }) do
        Same(Receive(Advert(), nil, distribution), false, "unavailable or unsupported distributions reject")
    end
    Same(Receive(Advert(), nil, nil, nil, 8), false, "wrong native local channel ID rejects")
    Same(Receive(Advert(), nil, nil, nil, nil, "Trade"), false, "wrong native channel name rejects")
    Same(
        Discovery:Receive(PREFIX, Advert(), "CHANNEL", "Alice-TestRealm", "", 0, nil, LOBBY),
        false,
        "missing native ID is never inferred"
    )
    joined = false
    Same(Receive(Advert()), false, "unjoined channel is not trusted")
    Same(
        Discovery:Receive(PREFIX, Advert(), "CHANNEL", "Alice-TestRealm", "", 0, nil, LOBBY),
        false,
        "two missing channel IDs cannot match"
    )
    for _, info in ipairs({
        { name = LOBBY, localID = 7, channelType = Enum.PermanentChatChannelType.Zone },
        { name = "Trade", localID = 7, channelType = Enum.PermanentChatChannelType.Custom },
        { name = LOBBY, localID = 0, channelType = Enum.PermanentChatChannelType.Custom },
        { name = LOBBY, localID = 7.5, channelType = Enum.PermanentChatChannelType.Custom },
        { name = LOBBY, localID = math.huge, channelType = Enum.PermanentChatChannelType.Custom },
        { name = LOBBY, localID = secret, channelType = Enum.PermanentChatChannelType.Custom },
        { name = secret, localID = 7, channelType = Enum.PermanentChatChannelType.Custom },
        { name = LOBBY, localID = 7, channelType = secret },
        secret,
        false,
    }) do
        metadata = info
        Same(Receive(Advert()), false, "invalid native metadata cannot authorize a lobby packet")
        Tick(now + 30)
    end
    Same(#joins, 0, "invalid metadata never triggers a join into an unverified channel")

    Fresh()
    for _, values in ipairs({
        { secret, Advert(), "CHANNEL", "Alice-TestRealm", "", 0, 7, LOBBY },
        { PREFIX, secret, "CHANNEL", "Alice-TestRealm", "", 0, 7, LOBBY },
        { PREFIX, Advert(), secret, "Alice-TestRealm", "", 0, 7, LOBBY },
        { PREFIX, Advert(), "CHANNEL", secret, "", 0, 7, LOBBY },
        { PREFIX, Advert(), "CHANNEL", "Alice-TestRealm", "", 0, secret, LOBBY },
        { PREFIX, Advert(), "CHANNEL", "Alice-TestRealm", "", 0, 7, secret },
        { PREFIX, Advert(), "WHISPER", "Alice-TestRealm", secret, 0, 7, LOBBY },
    }) do
        Same(Discovery:Receive(unpack(values)), false, "secret values are rejected before operations")
    end
    Same(#Discovery:GetGames(), 0, "secret packets allocate no browser state")
    for _, kind in ipairs({ "query", "event", "transport" }) do
        Fresh()
        joined = false
        Host()
        if kind == "query" then
            restricted = true
        elseif kind == "event" then
            eventRestricted = true
        else
            Quiz.Comms.suspended = true
        end
        Same(Receive(secret), false, "restriction gates before reading the wire payload")
        Same(Discovery:Refresh(), false, "restricted lookup is refused")
        Same(Discovery:Probe("Alice-TestRealm"), false, "restricted probe is refused")
        Tick(103)
        Same(#joins, 0, "restrictions prevent channel joins")
        Same(#sent, 0, "restrictions prevent broadcasts")
        Same(calls, 0, "restrictions prevent channel metadata reads")
        restricted, eventRestricted, Quiz.Comms.suspended = false, false, false
        Tick(104)
        Check(#joins > 0, "discovery recovers when restrictions clear")
    end

    Fresh()
    Check(Receive(Advert()), "probe starts from a discovered row")
    now = 146
    Same(#Discovery:GetGames(), 0, "the selected row may expire before it is clicked")
    Check(Discovery:Probe("Alice-TestRealm"), "an explicit stale-row probe is allowed")
    Same(Discovery:Probe("Alice-TestRealm"), false, "repeated clicks do not spam a host")
    Tick(146)
    Same(sent[1].channel, "WHISPER", "chosen host is probed privately")
    Same(sent[1].target, "Alice-TestRealm", "probe targets native row identity")
    Same(Receive(Advert(), "Bob-TestRealm", "WHISPER"), false, "unsolicited private advertisements reject")
    Same(Receive(Advert(), nil, "WHISPER", "Somebody-TestRealm"), false, "wrong private recipient rejects")
    Check(Receive(Advert(), nil, "WHISPER"), "selected host's probe response refreshes the row")
    Same(#Discovery:GetGames(), 1, "probe response restores a still-live game")
    Same(Quiz.Session.client, nil, "successful probe does not join the game")
    now = 159
    Same(Receive(Advert(), nil, "WHISPER"), false, "expired probe cannot authorize future unsolicited replies")
    Same(Discovery:Probe("Tester-TestRealm"), false, "self probe is refused")
    Same(Discovery:Probe("|Hbad"), false, "invalid target text is rejected")

    Fresh()
    Host()
    Check(Receive("7|Q", "Alice-TestRealm", "WHISPER"), "explicit native probe is handled")
    Same(Discovery.queueCount, 1, "one private reply is scheduled")
    for _ = 1, 20 do
        Check(Receive("7|Q", "Alice-TestRealm", "WHISPER"), "repeated query is handled")
    end
    Same(Discovery.queueCount, 1, "repeated query is coalesced")
    Tick(100)
    Same(sent[1].target, "Alice-TestRealm", "host reply goes to the actual native query sender")
    Check(sent[1].text:match("^7|A|100.1|"), "host reply advertises only the current game")
    Same(Quiz.Session.client, nil, "host-side discovery also cannot join anything")
    Fresh()
    Same(Receive("7|Q", "Alice-TestRealm", "WHISPER"), true, "idle client quietly handles a query")
    Same(Discovery.queueCount, 0, "idle clients do not answer discovery requests")

    Fresh()
    for index = 1, 32 do
        Check(Receive(Advert(), Player(index)), "bounded host row is accepted")
    end
    Same(#Discovery:GetGames(), 32, "browser capacity is bounded")
    Same(Receive(Advert(), Player(33)), false, "flood cannot allocate unbounded hosts")
    for index = 1, 32 do
        Check(Discovery:Probe(Player(index)), "bounded explicit probe is accepted")
    end
    Same(Discovery:Probe(Player(33)), false, "probe table is bounded")
    Same(Discovery.queueCount, 32, "outbound queue is bounded")
    Tick(146)
    Same(#Discovery:GetGames(), 0, "expired rows release browser capacity")
    Same(Discovery.probeCount, 0, "expired probes release pending capacity")
    Check(Discovery.queueCount <= 1, "expired packets are not replayed as a burst")
    Check(Receive(Advert(), Player(33)), "browser accepts a host after expiry")

    Fresh()
    Host()
    for index = 1, 100 do
        Check(Receive("7|Q", Player(index), "WHISPER"), "native lookup flood remains harmless")
    end
    Same(Discovery.responderCount, 32, "reply bookkeeping is bounded")
    Same(Discovery.queueCount, 32, "reply queue cannot exceed its cap")
    Tick(100)
    Check(#sent == 1, "flood still emits only one packet per tick")

    Fresh()
    Check(Discovery:Probe("Alice-TestRealm"), "retry test queues one probe")
    sendResults = {
        Enum.SendAddonMessageResult.AddonMessageThrottle,
        Enum.SendAddonMessageResult.AddonMessageThrottle,
        Enum.SendAddonMessageResult.AddonMessageThrottle,
    }
    Discovery.queryAt = nil
    Tick(100)
    Tick(101)
    Same(#sent, 1, "native throttle delays retry")
    Tick(102)
    Tick(104)
    Same(#sent, 3, "native throttle attempts are bounded")
    Same(Discovery.queueCount, 0, "exhausted packet leaves the queue")
    for _, result in ipairs({
        Enum.SendAddonMessageResult.ChannelThrottle,
        Enum.SendAddonMessageResult.InvalidChannel,
        Enum.SendAddonMessageResult.TargetOffline,
        Enum.SendAddonMessageResult.GeneralError,
    }) do
        Fresh()
        Discovery.queryAt = nil
        Check(Discovery:Probe("Alice-TestRealm"), "terminal-result test queues one probe")
        sendResults = { result }
        Tick(100)
        Tick(102)
        Same(#sent, 1, "handed-off or failed packets are not blindly repeated")
        Same(Discovery.queueCount, 0, "terminal packet leaves the queue")
    end

    Fresh()
    guild = true
    Host()
    Tick(100)
    Check(Discovery.queueCount > 0, "some discovery packets are queued")
    eventRestricted = true
    Tick(101)
    Same(Discovery.queueCount, 0, "restriction discards queued advertisements")
    Same(#sent, 1, "nothing else is emitted after activation")
    eventRestricted = false
    Tick(106)
    Check(#sent > 1, "fresh discovery resumes without manual input")
    Fresh()
    Discovery.queryAt = nil
    Check(Discovery:Probe("Alice-TestRealm"), "synchronous block test queues a probe")
    sendHook = function()
        eventRestricted = true
    end
    Tick(100)
    Same(Discovery.queueCount, 0, "synchronous native restriction preserves queue invariants")
    Fresh()
    Discovery.queryAt = nil
    Check(Discovery:Probe("Alice-TestRealm"), "synchronous stop test queues a probe")
    sendHook = function()
        Discovery:Stop()
    end
    Tick(100)
    Same(Discovery.queueCount, 0, "synchronous stop does not decrement a cleared queue twice")

    Fresh()
    guild = true
    Host()
    Tick(100)
    Discovery:StopHost()
    for _, entry in pairs(Discovery.queue) do
        Check(not entry.message:match("^7|A|"), "withdrawal removes unsent advertisements")
    end
    Tick(101)
    Check(sent[#sent].text:match("^7|X|100.1$"), "stop publishes a bounded withdrawal")
    Flush(5)
    for index = 2, #sent do
        Check(not sent[index].text:match("^7|A|100.1|"), "same stopped session is never readvertised")
    end
    Host("100.2")
    Flush(6)
    local foundReplacement = false
    for _, packet in ipairs(sent) do
        foundReplacement = foundReplacement or packet.text:match("^7|A|100.2|") ~= nil
    end
    Check(foundReplacement, "a new hosted session can advertise after stopping another")

    Quiz.Main, Quiz.Session, Quiz.GetQuestionPacks = originals.main, originals.session, originals.packs
    C_ChatInfo, GetTime, GetNormalizedRealmName, UnitFullName =
        originals.chat, originals.time, originals.realm, originals.player
    IsInGuild, IsInGroup, IsInRaid, JoinChannelByName = originals.guild, originals.group, originals.raid, originals.join
    issecretvalue, Quiz.Comms.suspended = originals.secret, originals.suspended
    for key in pairs(Discovery) do
        Discovery[key] = nil
    end
    for key, value in pairs(originals.discovery) do
        Discovery[key] = value
    end
    return assertions
end

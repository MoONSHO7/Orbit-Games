local PACK_ID = "session-regression"
local LEAGUE = "Protocol {Guild}"
local HOST = "Remote-ForeignRealm"
local OTHER_HOST = "Different-ForeignRealm"
local PEER = "Participant-TestRealm"
local SESSION_ID = "protocol-session.1"
local EXPLANATION = "The private explanation appears only after the question closes."
local PREFIX = "ORBITQUIZ8"
local PACK_TITLE = "Session regression questions"
local FRAGMENT_BYTES = 200

return function(Quiz)
    local assertions, incomingId = 0, 0
    local Session, Main, Comms = Quiz.Session, Quiz.Main, Quiz.Comms
    local defaultRules = assert(Quiz.Rules.Normalize())
    local defaultRulesKey = assert(Quiz.Rules.Encode(defaultRules))

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Count(values)
        local count = 0
        for _ in pairs(values) do
            count = count + 1
        end
        return count
    end

    local function Fields(...)
        local fields = {}
        for index = 1, select("#", ...) do
            local value = select(index, ...)
            fields[index] = type(value) == "number" and string.format(value % 1 == 0 and "%.0f" or "%.1f", value)
                or value
        end
        return fields
    end

    local function PeerFields(code, sessionId, id, choice, revision, request)
        local peer = Session.peers[PEER:lower()]
        request = request or peer and peer.request or "peer-request.1"
        if code == "D" then
            return Fields(code, sessionId, id, request)
        elseif code == "A" then
            return Fields(code, sessionId, id, choice, revision or 1, request)
        end
        return Fields(code, sessionId, request)
    end

    local function ReplyFields(code, sessionId, id, value, revision, request, version)
        local client = Session.client
        revision, request = revision or client.answerRevision, request or client.request
        if code == "K" then
            return Fields(code, sessionId, id, value, revision, request, version or math.max(0, client.ackVersion + 1))
        end
        return Fields(code, sessionId, id, value, revision, request)
    end

    local function Changed(fields, index, value)
        local changed = {}
        for key, field in ipairs(fields) do
            changed[key] = field
        end
        changed[index] = value
        return changed
    end

    local function Incoming(fields, sender, prefix, channel)
        local pieces = { #fields .. ":" }
        for _, field in ipairs(fields) do
            assert(type(field) == "string", "protocol fixtures contain only string fields")
            pieces[#pieces + 1] = #field .. ":" .. field
        end
        local encoded = table.concat(pieces)
        local total = math.ceil(#encoded / FRAGMENT_BYTES)
        incomingId = incomingId + 1
        for part = 1, total do
            local fragment = encoded:sub((part - 1) * FRAGMENT_BYTES + 1, part * FRAGMENT_BYTES)
            Main:OnEvent(
                "CHAT_MSG_ADDON",
                prefix or PREFIX,
                string.format("1|session-test-%d|%d|%d|%s", incomingId, part, total, fragment),
                channel or "WHISPER",
                sender or HOST,
                "UntrustedTarget-TestRealm"
            )
        end
    end

    local function Decode(message)
        local fragments = {}
        for index, packet in ipairs(message.packets) do
            local cursor = assert(packet:match("^1|[^|]+|%d+|%d+|()"), "queued packet has transport framing")
            fragments[index] = packet:sub(cursor)
        end
        local encoded = table.concat(fragments)
        local cursor = 1
        local function Length()
            local separator = assert(encoded:find(":", cursor, true), "queued field has a length")
            local length = assert(tonumber(encoded:sub(cursor, separator - 1)), "queued length is numeric")
            cursor = separator + 1
            return length
        end
        local fields = {}
        local count = Length()
        for index = 1, count do
            local length = Length()
            fields[index] = encoded:sub(cursor, cursor + length - 1)
            cursor = cursor + length
        end
        assert(cursor == #encoded + 1, "queued fields consume the complete message")
        return fields
    end

    local function Queued(code, target)
        local found = {}
        for index = Comms.queueHead, Comms.queueTail do
            local message = Comms.queue[index]
            if message then
                local fields = Decode(message)
                if fields[1] == code and (not target or message.target == target) then
                    found[#found + 1] = { fields = fields, target = message.target, tag = message.tag }
                end
            end
        end
        return found
    end

    local function One(code, target)
        local queued = Queued(code, target)
        Same(#queued, 1, "one " .. code .. " message is queued")
        return queued[1].fields
    end

    local function Sent(code, target)
        local messages, found = {}, {}
        for _, entry in ipairs(Test.addonSent) do
            local id, part, total = entry.text:match("^1|([^|]+)|(%d+)|(%d+)|")
            local key = entry.target .. "\031" .. id
            local message = messages[key]
            if not message then
                message = { packets = {}, target = entry.target, total = tonumber(total), count = 0 }
                messages[key] = message
            end
            part = tonumber(part)
            if not message.packets[part] then
                message.count = message.count + 1
            end
            message.packets[part] = entry.text
        end
        for _, message in pairs(messages) do
            if message.count == message.total then
                local fields = Decode(message)
                if fields[1] == code and (not target or message.target == target) then
                    found[#found + 1] = fields
                end
            end
        end
        return found
    end

    local function Drain()
        local ticks = 0
        while Comms:IsBusy() do
            Comms:Tick(Test.now)
            if Comms:IsBusy() then
                Test.now = Test.now + 0.125
            end
            ticks = ticks + 1
            assert(ticks <= 100, "fixture outbox did not drain")
        end
    end

    local function Fresh()
        Same(#Test.errors, 0, "previous scenario did not raise a runtime error")
        Main:CancelTicker()
        Comms:Clear()
        Main.game, Main.restrictionActive, Main.chatDisconnected, Main.restrictedUntil = nil, nil, nil, nil
        Main.notice, Main.nextAutoAt = nil, nil
        Main.autoPaused = false
        Test.restricted = false
        Test.addonSendResult, Test.onAddonSend = nil, nil
        Test.now = math.floor(Test.now) + 100
        Test.addonSent, Test.sent = {}, {}
        Comms.suspended, Comms.tokens = false, nil
        OrbitQuizDB = nil
        Main:OnEvent("ADDON_LOADED", Quiz.addonName)
        Check(Main.initialized, "the real addon lifecycle initializes each scenario")
    end

    local function Settings()
        local settings = Quiz.Store:GetSettings()
        settings.packId, settings.league = PACK_ID, LEAGUE
        settings.duration = 20
        return settings
    end

    local function Host()
        Fresh()
        Check(Main:Start(Settings()), "host starts the protocol fixture")
        Same(Main.game.state, "open", "host without peers opens immediately")
        return Main.game.round
    end

    local function Peer(name, request)
        Incoming(Fields("J", request or "peer-request.1"), name or PEER)
        return Session.peers[(name or PEER):lower()]
    end

    local function Joining(name)
        Fresh()
        Check(Session:JoinHost(name or HOST), "participant explicitly chooses a host")
        Same(Session.view.state, "joining", "participant awaits welcome")
        Same(One("J", name or HOST)[2], Session.client.request, "join uses its current request token")
        return Session.client
    end

    local function Welcome(client, score, league)
        Incoming(Fields("W", client.request, SESSION_ID, league or LEAGUE, score or "70"), client.name)
        Same(client.session, SESSION_ID, "matching welcome establishes the host session")
        Same(Session.view.state, "waiting", "welcome waits for a question snapshot")
        Same(One("S", client.name)[2], SESSION_ID, "welcome requests a snapshot")
    end

    local function Question(id, choices, difficulty, era, rules)
        choices = choices or { "Red", "Blue", "Green", "Gold" }
        rules = rules or defaultRules
        return Fields(
            "Q",
            SESSION_ID,
            id,
            1,
            1,
            3,
            rules.answerSeconds,
            "Which colour is blue?",
            #choices,
            difficulty or "",
            era or "",
            PACK_ID,
            PACK_TITLE,
            "1",
            Quiz.Scoring.VERSION,
            assert(Quiz.Rules.Encode(rules)),
            unpack(choices)
        )
    end

    local function ResultFields(
        id,
        correctIndex,
        selected,
        points,
        score,
        correctCount,
        answers,
        explanation,
        elapsed,
        choiceCount,
        fastestName,
        fastestElapsed,
        rules,
        streak
    )
        rules = rules or defaultRules
        streak = streak or (selected == correctIndex and 1 or 0)
        return Fields(
            "R",
            SESSION_ID,
            id,
            correctIndex,
            selected,
            points,
            score,
            correctCount,
            answers,
            explanation,
            PACK_ID,
            PACK_TITLE,
            "1",
            Quiz.Scoring.VERSION,
            rules.answerSeconds,
            choiceCount or 4,
            selected == "" and "" or string.format("%.17g", elapsed or 0),
            fastestName or "",
            fastestElapsed and string.format("%.17g", fastestElapsed) or "",
            assert(Quiz.Rules.Encode(rules)),
            streak,
            Quiz.Scoring.StreakBonus(rules, streak),
            ""
        )
    end

    local function Result(id)
        return ResultFields(id, 2, 2, 2.5, 73, 1, 1, EXPLANATION)
    end

    local function Client(id, rules)
        rules = rules or defaultRules
        local client = Joining()
        Welcome(client)
        Comms:Clear()
        Incoming(Question(id, nil, nil, nil, rules))
        Same(Session.view.state, "posting", "question awaits the host opening signal")
        Same(One("D", HOST)[3], tostring(id), "readiness acknowledges the question ID")
        Same(Session.view.correctIndex, nil, "question data cannot reveal the answer")
        Same(Session.view.explanation, nil, "question data cannot reveal its explanation")
        Incoming(Fields("O", SESSION_ID, id, GetServerTime() + rules.answerSeconds))
        Same(Session.view.state, "open", "matching opening signal starts the answer window")
        Comms:Clear()
        return client, Session.view
    end

    local function Unchanged(fields, message, sender, prefix, channel)
        local view, client = Session.view, Session.client
        local values = {}
        for key, value in pairs(view) do
            values[key] = value
        end
        local heard, queued = client.lastHeard, Comms.queueCount
        Test.now = Test.now + 0.001
        Incoming(fields, sender, prefix, channel)
        Same(Session.view, view, message .. " preserves the view")
        Same(Session.client, client, message .. " preserves the selected host")
        Same(client.lastHeard, heard, message .. " does not refresh host liveness")
        Same(Comms.queueCount, queued, message .. " does not enqueue a reply")
        for key, value in pairs(values) do
            Same(view[key], value, message .. " preserves " .. key)
        end
        for key, value in pairs(view) do
            Same(value, values[key], message .. " does not add " .. key)
        end
    end

    Check(
        Quiz:RegisterQuestionPack({
            id = PACK_ID,
            title = "Session regression questions",
            questions = {
                {
                    id = "colours",
                    prompt = "Which colour is blue?",
                    choices = { "Red", "Blue", "Green", "Gold" },
                    correctIndex = 2,
                    explanation = EXPLANATION,
                },
                {
                    id = "numbers",
                    prompt = "What follows three?",
                    choices = { "Five", "Seven", "Four", "Eight" },
                    correctIndex = 3,
                    explanation = EXPLANATION,
                },
            },
        }),
        "protocol fixture pack registers"
    )

    local round = Host()
    Same(Main.game.settings.duration, 15, "legacy host settings normalize to the fixed fifteen-second clock")
    Same(round.deadline - round.startedAt, 15, "authoritative host model opens only a fifteen-second window")
    Same(Session.serverDeadline, GetServerTime() + 15, "host opening signal uses the fixed server deadline")
    Main.game.settings.duration = 60
    local sessionId = Session.hostSession
    Incoming(Fields("J", "extra-guid", "Player-FORGED"), PEER)
    Same(next(Session.peers), nil, "join cannot introduce a payload GUID")
    Incoming(Fields("J", "self-request"), Quiz.Identity.name)
    Same(next(Session.peers), nil, "host cannot register itself as a remote peer")
    for _, token in ipairs({ "", "token with spaces", "token|markup", "token\n", string.rep("x", 65) }) do
        Incoming(Fields("J", token), PEER)
        Same(next(Session.peers), nil, "invalid join token creates no peer")
    end
    local peer = Peer()
    Check(peer, "native sender registers a remote peer")
    Same(peer.name, PEER, "peer display identity comes from the native sender")
    Same(peer.playerKey, "name:" .. PEER:lower(), "unresolved remote identity is an honest qualified-name key")
    local welcome = One("W", PEER)
    Same(welcome[2], "peer-request.1", "welcome echoes only the request token")
    Same(welcome[3], sessionId, "welcome binds the host session")
    Same(welcome[4], LEAGUE, "host sends a valid league name containing braces")
    Same(welcome[5], "0.0", "host score carries an explicit decimal place")
    Drain()
    Incoming(PeerFields("S", sessionId), PEER)
    local question = One("Q", PEER)
    Same(#question, 20, "four-choice question contains pack provenance and rules before the shuffled choices")
    Same(question[3], tostring(round.id), "question packet carries the authoritative question ID")
    Same(question[7], "15", "host advertises fifteen seconds even if its copied settings were changed")
    Same(question[8], round.prompt, "question packet carries the prompt")
    Same(question[9], "4", "question packet explicitly declares its choice count")
    Same(question[12], PACK_ID, "question identifies its actual stable pack")
    Same(question[13], PACK_TITLE, "question carries the pack title for participants without it installed")
    Same(question[14], "1", "question advertises the actual pack revision")
    Same(question[15], tostring(Quiz.Scoring.VERSION), "question advertises its scoring revision")
    Same(question[16], defaultRulesKey, "question advertises its canonical pack rules without private answers")
    for index = 1, 4 do
        Same(question[16 + index], round.choices[index], "question packet carries only shuffled choice text")
    end
    Check(not table.concat(question):find(EXPLANATION, 1, true), "private explanation is absent from the question")
    Same(#Queued("R"), 0, "no result is queued before close")
    Same(#Queued("O"), 0, "unready peer is not granted an opening signal")
    Incoming(PeerFields("A", sessionId, round.id, round.correctIndex), PEER)
    Same(next(round.answers), nil, "unready peer cannot answer")
    Incoming(PeerFields("D", "wrong-session", round.id), PEER)
    Same(peer.readyId, nil, "readiness from another session is ignored")
    Incoming(PeerFields("D", sessionId, round.id - 1), PEER)
    Same(peer.readyId, nil, "readiness for an old question is ignored")
    Incoming(PeerFields("D", sessionId, round.id), PEER)
    Same(peer.readyId, round.id, "valid readiness is retained")
    Same(One("O", PEER)[3], tostring(round.id), "ready peer receives the matching opening signal")
    Incoming(PeerFields("A", sessionId, round.id, round.correctIndex, "Player-FORGED"), PEER)
    Same(next(round.answers), nil, "answer payload cannot supply a GUID")
    Incoming(PeerFields("A", sessionId, round.id, round.correctIndex), "Unjoined-TestRealm")
    Same(next(round.answers), nil, "unjoined native sender cannot borrow another peer's session")
    for _, choice in ipairs({ "0", "5", "1.5", "1e0", "A", "Player-FORGED", "" }) do
        Incoming(PeerFields("A", sessionId, round.id, choice), PEER)
        Same(next(round.answers), nil, "invalid protocol choice is not accepted")
    end
    Incoming(PeerFields("A", sessionId, round.id, round.correctIndex), PEER)
    local accepted = round.answers[peer.playerKey]
    Check(accepted, "valid answer is recorded under the native sender's pinned key")
    Same(accepted.name, PEER, "answer name cannot come from its payload")
    Same(accepted.guid, peer.playerKey, "stored identity is not a forged player GUID")
    Same(round.answers["Player-FORGED"], nil, "forged GUID has no answer entry")
    Same(One("K", PEER)[4], tostring(round.correctIndex), "acknowledgement carries the host's accepted choice")
    Test.now = Test.now + 2
    Comms:Clear()
    for _ = 1, 300 do
        Incoming(PeerFields("D", sessionId, round.id), PEER)
        Incoming(PeerFields("A", sessionId, round.id, round.correctIndex % 4 + 1), PEER)
    end
    Same(Comms.queueCount, 2, "ready and answer floods coalesce to one open and one lock response")
    Same(#Queued("O", PEER), 1, "duplicate readiness is rate-limited per peer")
    Same(#Queued("K", PEER), 1, "duplicate answer acknowledgements are rate-limited per peer")
    Same(round.answers[peer.playerKey], accepted, "reused action revision cannot replace or retime an answer")
    for _ = 1, 300 do
        Incoming(PeerFields("S", sessionId), PEER)
    end
    Same(Comms.queueCount, 2, "snapshot replay preserves pending round traffic without restarting it")
    Same(#Queued("Q", PEER), 0, "ready peer does not need its question resent during snapshot replay")
    Check(Comms:Send("Other-TestRealm", Fields("H", sessionId, "open", round.id, 0)), "another peer is not starved")
    Same(#Queued("H", "Other-TestRealm"), 1, "shared queue still accepts another participant's heartbeat")
    Test.now = round.deadline
    Comms:Clear()
    Main:CloseQuestion(Test.now)
    Same(Main.game.state, "results", "host finalizes the authoritative result")
    local result = One("R", PEER)
    Same(#result, 23, "result carries rules, streak accounting and compact group milestones")
    Same(result[4], tostring(round.correctIndex), "correct choice is first revealed in the result")
    Same(result[10], EXPLANATION, "explanation is revealed only after close")
    Same(result[11], PACK_ID, "result retains question-pack identity")
    Same(result[13], question[14], "result retains the question's pack version")
    Same(result[14], question[15], "result retains the question's scoring version")
    Same(result[15], "15", "result records the authoritative scoring window")
    Same(result[16], "4", "result retains answer-index bounds without needing its question packet")
    Same(tonumber(result[17]), accepted.elapsed, "result transports exact accepted host elapsed time")
    Same(result[20], defaultRulesKey, "result is self-contained with the authoritative pack rules")
    Same(tonumber(result[21]), accepted.correct and 1 or 0, "result carries the finalized correct streak")
    Same(tonumber(result[22]), 0, "older packs retain disabled streak bonuses")
    Same(result[18], PEER, "confirmed multiplayer result identifies the fastest correct native player")
    Same(tonumber(result[19]), accepted.elapsed, "confirmed winner time matches its accepted host timing")
    Same(#Main.game.lastResult.answers, 1, "replayed answers are scored exactly once")
    Same(Main.game.lastResult.duration, 15, "finalized wire-host history retains its actual fixed duration")
    Check(accepted.points <= 2.5, "host scoring cannot inherit a larger legacy-window bonus")
    Same(Main.game:GetStandings()[1].guid, peer.playerKey, "host session score retains native identity")
    Same(#Quiz.Store:GetStandings(LEAGUE, "PUBLIC"), 0, "remote results never add to archived league totals")
    for _ = 1, 300 do
        Incoming(PeerFields("D", sessionId, round.id), PEER)
        Incoming(PeerFields("A", sessionId, round.id, round.correctIndex, 2), PEER)
    end
    Same(#Queued("R", PEER), 1, "result responses are rate-limited after close")
    Same(#Queued("E", PEER), 1, "post-close answer errors are rate-limited")
    Same(Comms.queueCount, 3, "one fragmented winner result and one rejection cannot fill the queue")
    Comms:Clear()
    Test.now = Test.now + 5
    Peer()
    Same(peer.readyId, round.id, "same-request rejoin preserves the acknowledged question")
    Drain()
    Incoming(PeerFields("S", sessionId), PEER)
    Same(#Queued("Q", PEER), 0, "same-request resync does not retransmit an acknowledged question")
    Same(#Queued("R", PEER), 1, "same-request resync repairs a missing result after the bounded retry interval")
    Comms:Clear()
    Test.now = Test.now + 2
    Peer(PEER, "new-request.2")
    Same(peer.readyId, nil, "new join request resets readiness for a fresh client")
    Same(peer.request, "new-request.2", "peer retains only its current join request")
    Same(round.answers[peer.playerKey], accepted, "new join request cannot alter a closed answer")
    Test.now = Test.now + 3
    Peer(PEER, "peer-request.1")
    Same(peer.request, "new-request.2", "delayed superseded join cannot rotate membership back to an old nonce")
    Drain()
    Incoming(PeerFields("S", sessionId), PEER)
    Same(#Queued("Q", PEER), 1, "fresh client receives the question before its result snapshot")
    Same(#Queued("R", PEER), 1, "fresh client can recover the already closed result")
    local queuedSnapshot = Comms.queue[Comms.queueHead]
    Test.now = Test.now + 2
    Incoming(PeerFields("S", sessionId), PEER)
    Same(Comms.queue[Comms.queueHead], queuedSnapshot, "snapshot retry never restarts a still-pending transfer")
    Same(#Queued("Q", PEER), 1, "backpressure keeps only the existing question transfer")

    local fixedClient = Joining()
    Welcome(fixedClient)
    Comms:Clear()
    Incoming(Changed(Question(99), 7, "15"))
    Same(Session.view.duration, 15, "participant accepts a fixed-window host question")
    Incoming(Fields("O", SESSION_ID, 99, GetServerTime() + 16))
    Same(Session.view.deadline - GetTime(), 15, "one second of server-clock skew still opens at most fifteen seconds")
    local fixedDeadline = Session.view.deadline
    Test.now = Test.now + 1
    Incoming(Fields("O", SESSION_ID, 99, GetServerTime() + 60))
    Same(Session.view.deadline, fixedDeadline, "a repeated future opening cannot extend the established clock")
    Comms:Clear()
    Unchanged(Changed(Result(99), 6, "3.0"), "fixed-window results cannot award a legacy three-point maximum")
    Incoming(Changed(Changed(Result(99), 6, "2.5"), 7, "72.5"))
    Same(Session.view.state, "results", "fifteen-second host result is accepted")
    Same(Session.view.points, 2.5, "fixed-window maximum survives wire formatting")
    for _, oldDuration in ipairs({ 10, 20, 60 }) do
        local legacyClient = Joining()
        Welcome(legacyClient)
        Comms:Clear()
        Unchanged(
            Changed(Question(100), 7, tostring(oldDuration)),
            "protocol seven rejects a duration that contradicts the encoded pack rules"
        )
        Unchanged(Question(100), "prior scoring protocol cannot inject an otherwise valid question", HOST, "ORBITQUIZ3")
    end

    local signedClient = Joining()
    Welcome(signedClient, -2.5)
    Same(Session.view.score, -2.5, "welcome accepts an existing negative league score")
    Comms:Clear()
    Incoming(Question(101))
    Incoming(Fields("O", SESSION_ID, 101, GetServerTime() + 15))
    Incoming(Fields("H", SESSION_ID, "open", 101, -2.8))
    Same(Session.view.score, -2.8, "heartbeat snapshot can update a negative total")
    Incoming(ResultFields(101, 1, 2, -0.7, -3.5, 0, 1, EXPLANATION, 6))
    Same(Session.view.points, -0.7, "finalized result retains its signed fractional penalty")
    Same(Session.view.score, -3.5, "finalized result retains its negative cumulative score")
    Comms:Clear()
    Test.now = signedClient.lastHeard + 19
    Session:Tick(Test.now)
    Check(signedClient.awaitingWelcome, "lost host liveness initiates a fresh signed-score handshake")
    Incoming(Fields("W", signedClient.request, SESSION_ID, LEAGUE, -3.5))
    Same(Session.view.score, -3.5, "rejoin welcome preserves the negative score")
    Incoming(Question(101))
    Incoming(ResultFields(101, 1, 2, -0.7, -3.5, 0, 1, EXPLANATION, 6))
    Same(Session.view.state, "results", "signed result snapshot restores the closed question after rejoin")
    Same(Session.view.points, -0.7, "snapshot recovery does not drop the wrong-answer penalty")
    Same(Session.view.score, -3.5, "snapshot recovery does not reapply the same penalty")

    round = Host()
    sessionId = Session.hostSession
    peer = Peer()
    Incoming(PeerFields("D", sessionId, round.id), PEER)
    local sameWrong = round.correctIndex % 4 + 1
    Incoming(PeerFields("A", sessionId, round.id, sameWrong, 1), PEER)
    local wrongAnswer = round.answers[peer.playerKey]
    Same(wrongAnswer.points, -1, "first instant wrong answer has the full penalty")
    Test.now = Test.now + 5.2
    Comms:Clear()
    Incoming(PeerFields("A", sessionId, round.id, sameWrong, 2), PEER)
    Same(round.answers[peer.playerKey], wrongAnswer, "higher-revision same-choice action preserves its answer record")
    Same(wrongAnswer.elapsed, 0, "higher revision cannot retime the unchanged wrong answer")
    Same(wrongAnswer.points, -1, "higher revision cannot soften an unchanged wrong-answer penalty")
    Same(One("K", PEER)[5], "2", "same-choice no-op is acknowledged at its new revision")
    Incoming(PeerFields("A", sessionId, round.id, round.correctIndex, 3), PEER)
    local corrected = round.answers[peer.playerKey]
    Same(corrected.points, 1.9, "a genuinely different correct choice receives its later timing score")
    local correctedElapsed = corrected.elapsed
    Test.now = Test.now + 1
    Incoming(PeerFields("A", sessionId, round.id, round.correctIndex, 4), PEER)
    Same(round.answers[peer.playerKey], corrected, "same correct choice with a new revision remains idempotent")
    Same(corrected.elapsed, correctedElapsed, "same correct choice does not move its timestamp")
    Same(corrected.points, 1.9, "same correct choice retains its original accepted bonus")

    round = Host()
    sessionId = Session.hostSession
    peer = Peer()
    local joinedAt = Test.now
    Test.now = joinedAt + 34
    Session:Tick(Test.now)
    Check(Session.peers[PEER:lower()], "peer survives until the explicit timeout")
    Test.now = joinedAt + 35
    Session:Tick(Test.now)
    Same(Session.peers[PEER:lower()], nil, "silent peer expires after thirty-five seconds")
    Comms:Clear()
    Incoming(PeerFields("S", sessionId), PEER)
    Incoming(PeerFields("T", sessionId), PEER)
    Same(next(Session.peers), nil, "snapshot and heartbeat cannot recreate an expired registration")
    peer = Peer()
    Check(peer, "fresh join handshake restores an expired peer")
    Same(One("W", PEER)[3], sessionId, "restored peer is welcomed to the same ongoing session")
    Comms:Clear()
    for index = 1, 15 do
        Peer("Guest" .. string.char(64 + index) .. "-TestRealm", "request-" .. index)
    end
    Peer("Overflow-TestRealm")
    Same(Session.peers["overflow-testrealm"], nil, "host peer state is capped at sixteen native identities")
    Incoming(PeerFields("L", "wrong-session"), PEER)
    Check(Session.peers[PEER:lower()], "wrong-session leave cannot evict a participant")
    Incoming(PeerFields("L", sessionId), PEER)
    Same(Session.peers[PEER:lower()], nil, "valid leave removes its native sender")
    Test.now = Test.now + 3
    Peer()
    Same(Session.peers[PEER:lower()], nil, "a delayed old join cannot undo an explicit departure")
    Check(Peer("Overflow-TestRealm"), "explicit leave releases peer capacity")

    for _, mode in ipairs({ "solo", "pending", "ready", "departed", "expired" }) do
        round = Host()
        sessionId = Session.hostSession
        Check(not Session:HasRoundPeers(round.id, Test.now), "new hosted round starts without remote contestants")
        if mode ~= "solo" then
            peer = Peer()
            Check(not Session:HasRoundPeers(round.id, Test.now), "joining alone does not count as round readiness")
            if mode ~= "pending" then
                Incoming(PeerFields("D", sessionId, round.id), PEER)
                Check(Session:HasRoundPeers(round.id, Test.now), "current ready peer qualifies this round")
                Check(not Session:HasRoundPeers(round.id + 1, Test.now), "readiness cannot qualify a different round")
                Check(
                    Session:HasRoundPeers(round.id, peer.lastSeen + 34.999),
                    "ready peer qualifies strictly before its lease expires"
                )
                Check(
                    not Session:HasRoundPeers(round.id, peer.lastSeen + 35),
                    "expired peer is excluded before the cleanup ticker runs"
                )
                if mode == "departed" then
                    Incoming(PeerFields("L", sessionId), PEER)
                end
            end
        end
        Test.now = round.startedAt + 0.125
        Check(Session:SubmitAnswer(round.correctIndex), "host finalizes its local answer without public chat")
        Test.now = mode == "expired" and peer.lastSeen + 35 or round.deadline
        Main:CloseQuestion(Test.now)
        local expectedName = mode == "ready" and Quiz.Identity.name or nil
        local expectedElapsed = mode == "ready" and 0.125 or nil
        Same(Main.game.lastResult.fastestName, expectedName, mode .. " round applies actual-peer winner eligibility")
        Same(Main:GetHostView().fastestName, expectedName, mode .. " host HUD uses the same finalized winner")
        Same(Main.game.lastResult.fastestElapsed, expectedElapsed, mode .. " round retains only confirmed winner time")
        Same(Quiz.PersonalScores:GetPack(PACK_ID).answers, 1, mode .. " result always saves normal personal progress")
    end

    round = Host()
    sessionId = Session.hostSession
    peer = Peer()
    Incoming(PeerFields("D", sessionId, round.id), PEER)
    Test.now = round.deadline
    Main:CloseQuestion(Test.now)
    Incoming(Fields("F", sessionId, round.id, peer.request), PEER)
    Comms:Clear()
    Check(Main:NextQuestion(), "host can prepare a subsequent question with registered peers")
    local prepared = Main.game.round
    Same(Main.game.state, "posting", "new question waits for current readiness")
    Same(peer.readyId, nil, "new question resets the old readiness ID")
    Check(not Session:CanOpen(Test.now + 19.999), "unready peer is allowed the bounded preparation window")
    Check(Session:CanOpen(Test.now + 20), "preparation does not wait indefinitely for a peer")
    Incoming(PeerFields("D", sessionId, round.id), PEER)
    Same(peer.readyId, nil, "old readiness cannot open the new question")
    Incoming(PeerFields("D", sessionId, prepared.id), PEER)
    Check(Session:CanOpen(Test.now), "current readiness permits immediate opening")
    Main:Tick()
    Same(Main.game.state, "open", "ready question opens through the real runtime")
    Check(Main:Pause(nil, false), "host pause voids the exposed question")
    Same(Main.game.round, nil, "host pause discards active question state")
    Same(One("P", PEER)[3], tostring(prepared.id), "host pause carries its last exposed question ID")
    Comms:Clear()
    Test.now = Test.now + 5
    Session:Tick(Test.now)
    local heartbeat = One("H", PEER)
    Same(heartbeat[3], "paused", "paused host remains visible through heartbeats")
    Same(heartbeat[4], tostring(prepared.id), "paused heartbeat preserves the void boundary without a round object")
    local heartbeatQueueSize = Comms.queueCount
    Test.now = Test.now + 5
    Session:Tick(Test.now)
    Same(Comms.queueCount, heartbeatQueueSize, "pending peer updates suppress redundant heartbeat queue growth")
    Same(#Queued("H", PEER), 1, "at most one pending heartbeat is retained for an idle peer")
    Check(Main:Resume(), "host resumes after heartbeat backpressure")
    Same(#Queued("H", PEER), 0, "new round cancels obsolete heartbeat state before its question transfer")

    local client = Joining()
    local request = client.request
    Same(client.name, HOST, "foreign realm is preserved for the explicitly selected host")
    for _, fields in ipairs({
        Fields("W", "wrong-request", SESSION_ID, LEAGUE, 70),
        Fields("W", request, "", LEAGUE, 70),
        Fields("W", request, "bad session", LEAGUE, 70),
        Fields("W", request, string.rep("x", 65), LEAGUE, 70),
        Fields("W", request, SESSION_ID, "", 70),
        Fields("W", request, SESSION_ID, "   ", 70),
        Fields("W", request, SESSION_ID, string.rep("x", 49), 70),
        Fields("W", request, SESSION_ID, "Guild|markup", 70),
        Fields("W", request, SESSION_ID, "Guild\n", 70),
        Fields("W", request, SESSION_ID, LEAGUE),
        Fields("W", request, SESSION_ID, LEAGUE, 70, "extra"),
    }) do
        Unchanged(fields, "malformed welcome")
    end
    local validWelcome = Fields("W", request, SESSION_ID, LEAGUE, 70)
    Unchanged(validWelcome, "other host's welcome", OTHER_HOST)
    Unchanged(validWelcome, "secret native identity", Test.secret)
    Unchanged(validWelcome, "malformed native identity", "Bad|Name-Realm")
    Unchanged(validWelcome, "foreign addon prefix", HOST, "UNRELATED")
    Unchanged(validWelcome, "non-whisper transport", HOST, PREFIX, "GUILD")
    local badIntegers = {
        "",
        "nan",
        "inf",
        "-inf",
        "1.55",
        "1e2",
        "0x10",
        "+1",
        " 1",
        "1 ",
        "9007199254740991",
        "-9007199254740991",
        "1\n",
        "|cff123456100",
    }
    for _, value in ipairs(badIntegers) do
        Unchanged(Changed(validWelcome, 5, value), "invalid welcome score")
    end
    Welcome(client)
    Same(Session.view.score, 70, "valid brace-containing league joins normally")
    Unchanged(Fields("W", request, "replacement-session", LEAGUE, 70), "different-session welcome replay")
    Comms:Clear()
    Test.now = client.lastHeard + 19
    Session:Tick(Test.now)
    Same(Session.view.state, "disconnected", "silent established host is visibly disconnected")
    local recoveryRequest = client.request
    Check(recoveryRequest ~= request, "silent recovery starts a fresh membership epoch")
    Same(One("J", HOST)[2], recoveryRequest, "silent established session rejoins with its fresh nonce")
    Check(client.awaitingWelcome, "silent recovery waits for the current welcome")
    Same(client.answerRevision, 0, "recovery resets answer revisions for the new membership")
    Same(client.ackVersion, -1, "recovery resets the prior host acknowledgement epoch")
    Same(#Queued("T", HOST), 0, "silent session does not rely on an unregistered heartbeat")
    Unchanged(validWelcome, "pre-recovery welcome replay")
    Unchanged(Fields("H", SESSION_ID, "open", 1, 70), "heartbeat before the recovery welcome")
    Comms:Clear()
    Test.now = client.nextJoin - 0.01
    Session:Tick(Test.now)
    Same(#Queued("J", HOST), 0, "recovery waits before retrying its handshake")
    Test.now = client.nextJoin
    Session:Tick(Test.now)
    Same(One("J", HOST)[2], recoveryRequest, "recovery retries reuse one stable fresh nonce")
    Incoming(Fields("W", recoveryRequest, SESSION_ID, LEAGUE, 70))
    Check(not client.awaitingWelcome, "fresh welcome completes membership recovery")
    Same(One("S", HOST)[2], SESSION_ID, "recovered handshake asks the host for current state")

    client = Joining()
    request = client.request
    Comms:Clear()
    Test.now = client.joinedAt + 3
    Session:Tick(Test.now)
    Same(One("J", HOST)[2], request, "unestablished join retries after three seconds")
    Test.now = client.joinedAt + 12
    Session:Tick(Test.now)
    Same(Session.client, nil, "unanswered initial join has a bounded lifetime")
    Same(Session.view.state, "disconnected", "initial join timeout is visible")
    Same(Session.view.notice, Quiz.L.NET_JOIN_TIMEOUT, "initial join timeout explains the missing host")
    Check(not Comms:IsBusy(), "initial join timeout drops stale requests")

    client = Joining()
    Welcome(client)
    Comms:Clear()
    Test.now = client.nextSyncAt
    Session:Tick(Test.now)
    Same(#Queued("S", HOST), 1, "waiting client retries a lost question snapshot after two seconds")
    Test.now = Test.now + 1
    Session:Tick(Test.now)
    Same(#Queued("S", HOST), 1, "snapshot retry timer does not flood every tick")
    Incoming(Question(10))
    Comms:Clear()
    Test.now = client.nextSyncAt
    Session:Tick(Test.now)
    Same(#Queued("S", HOST), 1, "posting client retries a lost opening signal")
    Incoming(Fields("O", SESSION_ID, 10, GetServerTime() + 15))
    Comms:Clear()
    Test.now = client.nextSyncAt
    Session:Tick(Test.now)
    Same(#Queued("S", HOST), 0, "open client does not send unnecessary snapshot retries")
    Test.now = Session.view.deadline - 0.5
    Incoming(Fields("H", SESSION_ID, "open", 10, 70))
    Comms:Clear()
    Test.now = Session.view.deadline
    Session:Tick(Test.now)
    Same(Session.view.state, "results", "local deadline enters the result-waiting state")
    Same(#Queued("S", HOST), 1, "missing result retries without waiting for the next five-second heartbeat")
    Comms:Clear()
    Test.now = Test.now + 2
    Session:Tick(Test.now)
    Same(#Queued("S", HOST), 1, "missing-result retry remains active at the two-second interval")
    Incoming(Result(10))
    Comms:Clear()
    Test.now = Test.now + 2
    Session:Tick(Test.now)
    Same(#Queued("S", HOST), 0, "a finalized result stops the snapshot retry timer")

    local view
    client, view = Client(20)
    local deadline = view.deadline
    for _, input in ipairs({ 0, 5, 1.5, "", "E", "A extra", "|cffffffffA", true, {} }) do
        Check(not Session:SubmitAnswer(input), "invalid local input cannot consume the first choice")
    end
    Same(view.selected, nil, "invalid answers do not change the selection")
    Check(Session:SubmitAnswer(" b "), "case-insensitive trimmed choice is submitted")
    Same(view.selected, 2, "pending answer remembers the first choice")
    Check(view.pending, "pending answer awaits host confirmation")
    local answer = One("A", HOST)
    Same(#answer, 6, "answer carries choice, revision and connection nonce, never a local GUID")
    Same(answer[4], "2", "answer transmits a choice index")
    Check(Session:SubmitAnswer("A"), "a second click can replace a pending answer")
    Same(view.selected, 1, "replacement immediately becomes the displayed selection")
    Same(client.answerRevision, 2, "changed selection gets a new action revision")
    Check(Session:SubmitAnswer("B"), "returning to the original choice is a new selection")
    Same(client.answerRevision, 3, "A to B to A remains a new timed action")
    Same(#Queued("A"), 1, "rapid changes coalesce the pending outbound answer")
    Check(Session:SubmitAnswer("B"), "clicking the already selected choice is harmless")
    Same(client.answerRevision, 3, "same-choice click does not change answer timing")
    Incoming(Question(20))
    Same(Session.view, view, "duplicate question keeps the same view")
    Same(view.selected, 2, "duplicate readiness does not reset the selected answer")
    Check(view.pending, "duplicate readiness preserves pending selection")
    Same(view.deadline, deadline, "duplicate question does not reset the answer clock")
    Test.now = Test.now + 1
    Incoming(Fields("O", SESSION_ID, 20, GetServerTime() + 60))
    Same(view.deadline, deadline, "replayed opening signal cannot extend an established deadline")
    Incoming(ReplyFields("K", SESSION_ID, 20, 2))
    Check(not view.locked, "authoritative acknowledgement leaves the answer adjustable")
    Same(view.pending, false, "acknowledgement ends retry state")
    Same(#Queued("A"), 0, "acknowledgement cancels obsolete answer retries")
    Incoming(Question(20))
    Incoming(Fields("O", SESSION_ID, 20, GetServerTime() + 15))
    Incoming(Fields("W", client.request, SESSION_ID, LEAGUE, 999))
    Check(not view.locked, "question, open and welcome replay cannot lock an open answer")
    Same(view.selected, 2, "replay preserves the acknowledged choice")
    Same(view.deadline, deadline, "replay cannot renew answer time")
    Same(view.score, 70, "duplicate welcome does not overwrite established score")
    Check(Session:SubmitAnswer("A"), "confirmed selection remains adjustable after resync")
    for _, fields in ipairs({
        Question(19),
        Fields("O", SESSION_ID, 19, GetServerTime() + 15),
        ReplyFields("K", SESSION_ID, 19, 1),
        ReplyFields("E", SESSION_ID, 19, "late"),
        Fields("O", SESSION_ID, 21, GetServerTime() + 15),
        Fields("X", "other-session"),
        Fields("H", "other-session", "open", 20, 999),
        Fields("unknown", SESSION_ID),
    }) do
        Unchanged(fields, "old, unsolicited, or foreign-session state")
    end
    Unchanged(Question(21), "unselected host's question", OTHER_HOST)
    Incoming(Question(21))
    Same(Session.view.id, 21, "newer question replaces the old view")
    Same(Session.view.locked, nil, "new question releases the old first-answer lock")
    Same(Session.view.pending, nil, "new question releases old acknowledgement state")
    Same(Session.view.selected, nil, "new question has no prior selection")
    Same(Session.view.deadline, nil, "new question must receive its own opening signal")

    client, view = Client(30)
    Check(Session:SubmitAnswer(2), "answer retry fixture submits once")
    for attempt = 2, 3 do
        Comms:Clear()
        Test.now = client.retryAt
        Session:Tick(Test.now)
        Same(client.answerAttempts, attempt, "answer retry count advances once per interval")
        Same(One("A", HOST)[4], "2", "retry always repeats the first selection")
    end
    Comms:Clear()
    Test.now = client.retryAt
    Session:Tick(Test.now)
    Same(#Queued("A"), 0, "answer retries are bounded to three attempts")
    Same(view.notice, Quiz.L.NET_ANSWER_UNCONFIRMED, "missing acknowledgement is explained")
    Check(Session:SubmitAnswer(1), "unconfirmed selection may be replaced with a fresh action")
    Incoming(Result(30))
    Same(view.state, "results", "authoritative result resolves an unconfirmed answer")
    Same(view.selected, 2, "finalized result retains accepted selection")
    Same(view.points, 2.5, "finalized result carries per-question points")
    Same(view.score, 73, "finalized result carries the league total")
    Same(view.notice, nil, "finalized result clears uncertainty")
    Unchanged(ReplyFields("E", SESSION_ID, 30, "not_open"), "late rejection after a finalized result")
    Unchanged(ReplyFields("K", SESSION_ID, 30, 4), "late acknowledgement after a finalized result")
    Unchanged(Fields("O", SESSION_ID, 30, GetServerTime() + 15), "late open after a finalized result")

    client, view = Client(40)
    Check(Session:SubmitAnswer(2), "void fixture has a pending answer")
    Incoming(Fields("P", SESSION_ID, 40, "restricted"))
    Same(view.state, "paused", "host pause interrupts the client answer window")
    Same(client.voidedThrough, 40, "pause records an explicit voided-question boundary")
    Same(view.pending, false, "pause releases pending transport state")
    Same(#Queued("A"), 0, "pause cancels queued answers")
    for _, fields in ipairs({
        Question(40),
        Fields("O", SESSION_ID, 40, GetServerTime() + 15),
        ReplyFields("K", SESSION_ID, 40, 2),
        ReplyFields("E", SESSION_ID, 40, "late"),
    }) do
        Unchanged(fields, "delayed packet for a voided question")
    end
    Incoming(Question(41))
    Incoming(Fields("O", SESSION_ID, 41, GetServerTime() + 15))
    Same(Session.view.state, "open", "newer question can resume after a host pause")
    Unchanged(Fields("P", SESSION_ID, 40, "manual"), "stale pause after a newer question")
    Unchanged(Fields("H", SESSION_ID, "paused", 40, 0), "stale paused heartbeat after a newer question")
    Incoming(Fields("H", SESSION_ID, "paused", 41, 70))
    Same(client.voidedThrough, 41, "paused heartbeat carries the same void boundary as an explicit pause")
    Same(Session.view.state, "paused", "heartbeat recovers a lost pause message")
    Unchanged(Question(41), "question replay after paused heartbeat")
    Unchanged(Fields("O", SESSION_ID, 41, GetServerTime() + 15), "open replay after paused heartbeat")
    Incoming(Result(41))
    Same(Session.view.state, "paused", "a late receipt after a pause cannot revive the answer widget")
    Same(
        Quiz.PersonalScores:GetPack(PACK_ID).score,
        2.5,
        "host-finalized receipt may persist after a pause notification"
    )

    client, view = Client(50)
    Incoming(Fields("H", SESSION_ID, "results", 50, 73))
    Same(One("S", HOST)[2], SESSION_ID, "result heartbeat requests a missing result snapshot")
    Same(view.correctIndex, nil, "heartbeat cannot invent the missing correct answer")
    Incoming(Question(50))
    Incoming(Result(50))
    Same(view.state, "results", "snapshot repairs a lost result")
    Comms:Clear()
    Incoming(Fields("H", SESSION_ID, "results", 50, 73))
    Same(#Queued("S"), 0, "complete result no longer requests redundant snapshots")
    Unchanged(Fields("H", SESSION_ID, "results", 49, 0), "older heartbeat cannot roll back the score")
    for _, phase in ipairs({ "ready", "posting", "open" }) do
        Unchanged(Fields("H", SESSION_ID, phase, 50, 70), "older same-question heartbeat phase " .. phase)
    end
    Same(view.score, 73, "stale heartbeat phase cannot roll back finalized total")
    Same(view.points, 2.5, "stale heartbeat phase preserves finalized per-question points")
    Incoming(Fields("H", SESSION_ID, "paused", 50, 73))
    Same(view.state, "paused", "a current pause after results is not mistaken for a stale phase")
    Same(view.score, 73, "current paused heartbeat retains the authoritative total")

    client, view = Client(55)
    Check(Session:SubmitAnswer(2), "new-heartbeat fixture has a pending old answer")
    for _, fields in ipairs({
        Fields("H", SESSION_ID, "unknown", 56, 73),
        Fields("H", SESSION_ID, "open", "56.5", 73),
        Fields("H", SESSION_ID, "open", 56, "nan"),
        Fields("H", "wrong-session", "open", 56, 73),
        Fields("H", SESSION_ID, "open", 56),
        Fields("H", SESSION_ID, "open", 56, 73, "extra"),
    }) do
        Unchanged(fields, "malformed newer-question heartbeat")
    end
    Incoming(Fields("H", SESSION_ID, "open", 56, 73))
    Same(view.state, "waiting", "newer-question heartbeat disables the old answer window")
    Same(view.pending, false, "newer-question heartbeat clears pending old answer state")
    Same(#Queued("A", HOST), 0, "newer-question heartbeat cancels queued old answer traffic")
    Same(One("S", HOST)[2], SESSION_ID, "newer-question heartbeat requests the missing question")
    Same(view.id, 55, "heartbeat alone cannot invent the new question's content")
    Same(view.score, 73, "newer-question heartbeat carries the updated authoritative total")
    Check(not Session:SubmitAnswer(1), "old question cannot accept input while the new question is missing")
    Same(client.latestId, 56, "newer-question heartbeat retains its expected question boundary")
    for _, fields in ipairs({
        Question(55),
        Fields("O", SESSION_ID, 55, GetServerTime() + 15),
        Fields("H", SESSION_ID, "open", 55, 70),
        Fields("H", SESSION_ID, "paused", 55, 70),
        Fields("P", SESSION_ID, 55, "manual"),
        ReplyFields("K", SESSION_ID, 55, 2),
        ReplyFields("E", SESSION_ID, 55, "late"),
    }) do
        Unchanged(fields, "old packet after a newer announced question")
    end
    Unchanged(Fields("H", SESSION_ID, "open", 57, "invalid"), "malformed heartbeat while waiting for content")
    Same(client.latestId, 56, "malformed heartbeat cannot advance the expected question boundary")
    Incoming(Question(56))
    Same(Session.view.id, 56, "new question snapshot supplies the announced question")
    Same(Session.view.state, "posting", "question snapshot still requires its opening signal")
    Same(Session.view.deadline, nil, "new question does not inherit the old deadline")
    Check(not Session:SubmitAnswer(1), "question content alone cannot open answer input")
    Incoming(Fields("O", SESSION_ID, 56, GetServerTime() + 15))
    Same(Session.view.state, "open", "matching new question and opening signal restore input")
    Check(Session:SubmitAnswer(4), "new question accepts a fresh answer selection")
    Incoming(Fields("H", SESSION_ID, "open", 56, 73))
    Same(Session.view.selected, 4, "current-question heartbeat preserves the pending first selection")
    Check(Session.view.pending, "current-question heartbeat does not cancel a valid current answer")

    client, view = Client(60)
    request = client.request
    local restrictedAt = Test.now
    Main:OnEvent(
        "ADDON_RESTRICTION_STATE_CHANGED",
        Enum.AddOnRestrictionType.Chat,
        Enum.AddOnRestrictionState.Activating
    )
    Check(Comms.suspended, "activating event suspends sends before the native query changes")
    Same(Session:GetView().state, "paused", "local restriction pauses the displayed participant view")
    Check(not Session:SubmitAnswer(1), "local restriction blocks submissions")
    Same(Comms.queueCount, 0, "restriction clears pending transport traffic")
    Test.now = restrictedAt + 60
    Session:Tick(Test.now)
    Same(Comms.queueCount, 0, "restricted timers never enqueue heartbeats or joins")
    Main:OnEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
    Same(client.session, SESSION_ID, "local restriction preserves the chosen session")
    Same(Session.view.state, "waiting", "restriction recovery requests fresh authoritative state")
    recoveryRequest = client.request
    Check(recoveryRequest ~= request, "restriction recovery rotates the membership nonce")
    Same(One("J", HOST)[2], recoveryRequest, "long local restriction recovers through fresh registration")
    Same(#Queued("S"), 0, "restriction recovery does not assume the host retained its peer")
    Same(client.lastHeard, Test.now, "restriction recovery starts a fresh liveness interval")
    Check(not Session:SubmitAnswer(1), "answers stay disabled until current host state arrives")
    Unchanged(Fields("W", request, SESSION_ID, LEAGUE, 70), "old welcome after local restriction")
    Incoming(Fields("W", recoveryRequest, SESSION_ID, LEAGUE, 70))
    Same(One("S", HOST)[2], SESSION_ID, "post-restriction welcome requests the current question")
    Incoming(Question(61))
    Incoming(Fields("O", SESSION_ID, 61, GetServerTime() + 15))
    Same(Session.view.state, "open", "registration and snapshot restore participation")
    Comms:Clear()
    Check(Main:Start(Settings()), "participant may explicitly transition into hosting")
    Same(Session.client, nil, "host role no longer retains a participant client")
    Drain()
    local leaves = Sent("L", HOST)
    Same(#leaves, 1, "host transition sends one leave to the former host")
    Same(leaves[1][2], SESSION_ID, "host transition notifies the former host of its departure")
    Check(Session.hostSession ~= SESSION_ID, "host transition allocates its own session token")

    for _, validScore in ipairs({ "0", "1.5", "3.0", "900719925474099" }) do
        client = Joining()
        Welcome(client, validScore)
        Same(Session.view.score, tonumber(validScore), "valid nonnegative tenth-point welcome score is retained")
    end

    client = Joining("選手-ForeignRealm")
    Welcome(client, "2.5", "聯盟 {測試}")
    Comms:Clear()
    Incoming(
        Fields(
            "Q",
            SESSION_ID,
            65,
            1,
            1,
            1,
            15,
            "請選一個答案",
            4,
            "",
            "",
            PACK_ID,
            PACK_TITLE,
            "1",
            Quiz.Scoring.VERSION,
            defaultRulesKey,
            "選擇甲",
            "選擇乙",
            "選擇丙",
            "選擇丁"
        ),
        client.name
    )
    Same(Session.view.prompt, "請選一個答案", "UTF-8 continuation bytes are not treated as ASCII controls")
    Same(One("D", client.name)[3], "65", "UTF-8 question can become ready")
    Incoming(Fields("O", SESSION_ID, 65, GetServerTime() + 15), client.name)
    Check(Session:SubmitAnswer("  選擇乙  "), "UTF-8 exact-choice text survives ASCII whitespace trimming")
    Same(One("A", client.name)[4], "2", "UTF-8 answer text resolves the intended index")

    client, view = Client(70)
    do
        local established = Question(70)
        for _, field in ipairs({
            { 4, "2" },
            { 5, "2" },
            { 6, "4" },
            { 8, "A different valid prompt?" },
            { 10, "hard" },
            { 11, "Warcraft III" },
            { 12, "different-valid-pack" },
            { 13, "A different valid pack title" },
            { 14, "2" },
            { 17, "Different red" },
            { 18, "Different blue" },
            { 19, "Different green" },
            { 20, "Different gold" },
        }) do
            Unchanged(
                Changed(established, field[1], field[2]),
                "same-ID question cannot mutate accepted field " .. field[1]
            )
        end
        Unchanged(
            Changed(Changed(established, 17, "Blue"), 18, "Red"),
            "same-ID question cannot reorder the choices beneath an existing answer index"
        )
        Incoming(established)
        Same(Session.view, view, "an identical repeated question retains the current view object")
        Same(One("D", HOST)[3], "70", "an identical repeated question still receives its readiness acknowledgement")
        Comms:Clear()
    end
    for _, fields in ipairs({
        Changed(Question(71), 3, "0"),
        Changed(Question(71), 3, "1.5"),
        Changed(Question(71), 4, "0"),
        Changed(Question(71), 5, "4"),
        Changed(Question(71), 6, "0"),
        Changed(Question(71), 7, "9"),
        Changed(Question(71), 7, "61"),
        Changed(Question(71), 7, "20.5"),
        Changed(Question(71), 8, ""),
        Changed(Question(71), 8, "   "),
        Changed(Question(71), 8, string.rep("x", 161)),
        Changed(Question(71), 8, "|cff123456question"),
        Changed(Question(71), 8, "Question {rt1}"),
        Changed(Question(71), 9, ""),
        Changed(Question(71), 9, "3"),
        Changed(Question(71), 9, "5"),
        Changed(Question(71), 9, "7"),
        Changed(Question(71), 9, "4.5"),
        Changed(Question(71), 10, "impossible"),
        Changed(Question(71), 10, string.rep("x", 101)),
        Changed(Question(71), 11, string.rep("x", 65)),
        Changed(Question(71), 11, "choice\n"),
        Changed(Question(71), 17, ""),
        Changed(Question(71), 18, string.rep("x", 101)),
        Changed(Question(71), 19, "choice\n"),
        Changed(Question(71), 20, "choice|markup"),
        Changed(Question(71), 20, " red "),
        Changed(Question(71), 17, "choice|markup"),
        Changed(Question(71), 12, ""),
        Changed(Question(71), 12, "all"),
        Changed(Question(71), 12, "invalid pack id"),
        Changed(Question(71), 13, ""),
        Changed(Question(71), 14, ""),
        Changed(Question(71), 15, "1"),
        Changed(Question(71), 15, "2"),
        Changed(Question(71), 16, ""),
        Changed(Question(71), 16, "arbitrary|rules"),
        Changed(Question(71), 16, string.rep("x", 129)),
        Fields("Q", SESSION_ID, 71, 1, 1, 3, 15, "Prompt", "A", "B", "C"),
        Fields("Q", SESSION_ID, 71, 1, 1, 3, 15, "Prompt", "A", "B", "C", "D", "answer"),
        Fields("O", SESSION_ID, 70, "invalid"),
        Fields("O", SESSION_ID, 70, GetServerTime() + 61),
        ReplyFields("K", SESSION_ID, 70, 0),
        ReplyFields("K", SESSION_ID, 70, 5),
        ReplyFields("K", SESSION_ID, 70, "2.5"),
        ReplyFields("E", SESSION_ID, 70, "arbitrary_error"),
        Fields("P", SESSION_ID, 70, "unknown_reason"),
        Fields("H", SESSION_ID, "unknown_state", 70, 70),
        Fields("H", SESSION_ID, "open", "1e2", 70),
    }) do
        Unchanged(fields, "invalid participant protocol field")
    end
    for _, value in ipairs(badIntegers) do
        Unchanged(Fields("H", SESSION_ID, "open", 70, value), "invalid heartbeat score")
        Unchanged(Changed(Result(70), 7, value), "invalid result score")
    end
    for _, fields in ipairs({
        Changed(Result(70), 4, "0"),
        Changed(Result(70), 4, "5"),
        Changed(Result(70), 5, "invalid"),
        Changed(Result(70), 5, ""),
        Changed(Result(70), 6, ""),
        Changed(Result(70), 6, "50"),
        Changed(Result(70), 6, "110.0"),
        Changed(Result(70), 8, "-1"),
        Changed(Result(70), 8, "2"),
        Changed(Result(70), 9, "-1"),
        Changed(Result(70), 9, "1.5"),
        Changed(Result(70), 10, string.rep("x", 161)),
        Changed(Result(70), 10, "Answer|markup"),
        Changed(Result(70), 10, "Answer {rt1}"),
        Changed(Result(70), 10, "Answer\n"),
        Changed(Result(70), 11, "other-pack"),
        Changed(Result(70), 12, "A different pack title"),
        Changed(Result(70), 13, "2"),
        Changed(Result(70), 14, "1"),
        Changed(Result(70), 14, "2"),
        Changed(Result(70), 15, "10"),
        Changed(Result(70), 16, "6"),
        Changed(Result(70), 17, "5"),
        Changed(Result(70), 17, "-1"),
        Changed(Result(70), 17, "15"),
        Changed(Result(70), 17, "nan"),
        Changed(Result(70), 17, ""),
        Changed(Result(70), 20, ""),
        Changed(Result(70), 20, "arbitrary|rules"),
        Changed(Result(70), 20, string.rep("x", 129)),
        Changed(Result(70), 21, ""),
        Changed(Result(70), 21, "0"),
        Changed(Result(70), 21, "-1"),
        Changed(Result(70), 21, "1.5"),
        Changed(Result(70), 21, "nan"),
        Changed(Result(70), 22, ""),
        Changed(Result(70), 22, "0.1"),
        Changed(Result(70), 22, "-0.1"),
        Changed(Result(70), 22, "nan"),
    }) do
        Unchanged(fields, "invalid finalized result")
    end
    Unchanged(ResultFields(70, 1, 2, -50, -50, 0, 1, ""), "old-scale negative score is rejected")
    for _, penalty in ipairs({ "0", "-0.4", "-1.1", "-0.55", "-1e0", "+0.5", "1", "nan", "-inf" }) do
        Unchanged(ResultFields(70, 1, 2, penalty, -1, 0, 1, ""), "malformed or out-of-range penalty")
    end
    for _, correctPoints in ipairs({ "-1", "-0.5", "0", "0.9", "2.6" }) do
        Unchanged(Changed(Result(70), 6, correctPoints), "correct result cannot use a penalty or exceed its bonus cap")
    end
    Incoming(ResultFields(70, 1, 2, -0.5, -0.5, 0, 1, "", 14))
    Same(view.points, -0.5, "late wrong answer receives the minimum half-point penalty")
    Same(view.score, -0.5, "negative half-point total is valid protocol data")
    client, view = Client(71)
    Incoming(ResultFields(71, 1, "", "", 70, 0, 0, ""))
    Same(view.state, "results", "unanswered result is valid")
    Same(view.selected, nil, "unanswered result has no fabricated choice")
    Same(view.points, nil, "unanswered result has no fabricated points")
    Same(view.totalAnswers, 0, "zero-answer round is valid")
    client, view = Client(72)
    Incoming(ResultFields(72, 1, 2, -1, 0, 0, 1, ""))
    Same(view.points, -1, "instant wrong result accepts the full one-point penalty")
    Same(view.score, 0, "a penalty can legitimately bring an existing positive score to zero")

    for count = 4, 6 do
        client = Joining()
        Welcome(client)
        Comms:Clear()
        local choices = {}
        for index = 1, count do
            choices[index] = "Option " .. index
        end
        local id = 800 + count
        local questionFields = Changed(Question(id, choices, "very_hard", "Warcraft III"), 7, "15")
        Incoming(questionFields)
        view = Session.view
        Same(view.state, "posting", "four-to-six-choice metadata is received before the opening signal")
        Same(#view.choices, count, "participant receives precisely the declared choice count")
        Same(view.difficulty, "very_hard", "participant receives difficulty without needing the host pack")
        Same(view.era, "Warcraft III", "participant receives era without needing the host pack")
        Same(view.source, nil, "editorial sources never become participant question data")
        Same(view.correctIndex, nil, "extended question does not reveal the answer key")
        Same(view.explanation, nil, "extended question does not reveal the explanation")
        Incoming(Fields("O", SESSION_ID, id, GetServerTime() + 15))
        Comms:Clear()
        Check(Session:SubmitAnswer(string.char(64 + count)), "letter selection includes E and F when present")
        Same(One("A", HOST)[4], tostring(count), "fifth and sixth selections carry their real wire indices")
        local selectedRevision = client.answerRevision
        Check(not Session:SubmitAnswer(count + 1), "numeric answer beyond this question is rejected")
        Check(not Session:SubmitAnswer(string.char(65 + count)), "letter answer beyond this question is rejected")
        Same(client.answerRevision, selectedRevision, "invalid extra choices do not advance action timing")
        Incoming(ReplyFields("K", SESSION_ID, id, count))
        Same(view.confirmedSelected, count, "extended choices are acknowledged normally")
        Same(view.pending, false, "extended choice acknowledgement clears pending state")
        Unchanged(ReplyFields("K", SESSION_ID, id, count + 1), "acknowledgement cannot invent an absent choice")
        local injectedSource = Changed(questionFields, #questionFields + 1, "https://example.org/answer-spoiler")
        Unchanged(injectedSource, "question does not accept a source or hidden answer extension")
        Unchanged(questionFields, "old transport prefix cannot update this session", HOST, "ORBITQUIZ2")
        Unchanged(questionFields, "old scoring prefix cannot update this session", HOST, "ORBITQUIZ3")
        Unchanged(
            ResultFields(id, count + 1, count, -0.5, 70, 0, 1, "", 14, count),
            "result cannot invent a correct choice"
        )
        Incoming(ResultFields(id, count, count, "1.8", "71.8", 1, 1, EXPLANATION, 7, count))
        Same(view.correctIndex, count, "results reveal fifth and sixth correct indices")
        Same(view.points, 1.8, "extended choice uses the ordinary tenth-point score")
        Same(view.explanation, EXPLANATION, "explanation becomes available only after the result")
    end

    client, view = Client(190)
    local winnerResult = ResultFields(190, 2, 2, 2, 72, 2, 3, EXPLANATION, 5, 4, PEER, 0.125)
    local oldResult = { unpack(winnerResult, 1, 17) }
    Unchanged(oldResult, "protocol seven rejects the prior seventeen-field receipt shape")
    Unchanged({ unpack(winnerResult, 1, 19) }, "protocol seven rejects receipts missing rules and streak metadata")
    Unchanged(winnerResult, "prior fixed-rule protocol cannot introduce current results", HOST, "ORBITQUIZ6")
    Unchanged(winnerResult, "prior protocol cannot introduce winner metadata", HOST, "ORBITQUIZ5")
    for _, name in ipairs({
        "",
        "Participant",
        " Participant-TestRealm",
        "Participant-TestRealm ",
        "Participant-",
        "Participant TestRealm",
        "Participant-Test Realm",
        "Player123-TestRealm",
        "<Participant>-TestRealm",
        "Participant|cffff0000-TestRealm",
        "Participant\n-TestRealm",
        string.rep("x", 121) .. "-TestRealm",
    }) do
        Unchanged(Changed(winnerResult, 18, name), "winner requires an unaltered qualified native identity")
    end
    for _, value in ipairs({ "", "-0.1", "+0.1", ".1", "5.001", "15.001", "nan", "inf", "1e99", "0.1 " }) do
        Unchanged(
            Changed(winnerResult, 19, value),
            "winner time is bounded, paired and no slower than a local correct answer"
        )
    end
    Unchanged(Changed(winnerResult, 19, string.rep("0", 33)), "winner timestamp has a bounded representation")
    Unchanged(
        Changed(winnerResult, 18, Quiz.Identity.name),
        "self-announced winner must match the local final timestamp"
    )
    Unchanged(
        ResultFields(190, 1, 2, -1, 69, 1, 2, "", 0, 4, Quiz.Identity.name, 0),
        "local wrong answer cannot also be the announced correct winner"
    )
    Unchanged(
        ResultFields(190, 1, "", "", 70, 1, 1, "", nil, 4, Quiz.Identity.name, 0),
        "unanswered local player cannot be the announced winner"
    )
    Unchanged(ResultFields(190, 1, 2, -1, 69, 0, 2, "", 0, 4, PEER, 0), "a zero-correct round cannot name a winner")
    Same(Quiz.PersonalScores:GetPack(PACK_ID), nil, "invalid winner receipts never create personal progress")
    Incoming(winnerResult)
    Same(view.state, "results", "fully validated winner receipt finalizes the local question")
    Same(view.fastestName, PEER, "confirmed result carries the actual fastest native identity")
    Same(view.fastestElapsed, 0.125, "fractional winner time survives the result codec")
    Same(view.suppressWinnerPopup, false, "first valid result is eligible for one winner animation")
    local winnerRevision = Quiz.PersonalScores.revision
    Incoming(winnerResult)
    Same(Quiz.PersonalScores.revision, winnerRevision, "winner receipt replay does not credit points again")
    Same(view.suppressWinnerPopup, false, "retransmission cannot suppress an already-started first result popup")
    Unchanged(Changed(winnerResult, 18, OTHER_HOST), "same-round replay cannot replace the confirmed winner")
    Unchanged(Changed(winnerResult, 19, "0.1"), "same-round replay cannot change the confirmed winner time")
    Unchanged(Changed(Changed(winnerResult, 18, ""), 19, ""), "same-round replay cannot retract a confirmed winner")
    Same(Quiz.PersonalScores:GetPack(PACK_ID).score, 2, "winner announcement grants no extra personal bonus")

    for index, elapsed in ipairs({ 0, 0.000001, 0.1, 1.2345678901234567, 15 }) do
        local id = 190 + index
        Incoming(Question(id))
        local points = Quiz.Scoring.Calculate(true, elapsed, 15)
        Incoming(ResultFields(id, 2, 2, points, points, 1, 2, "", elapsed, 4, Quiz.Identity.name, elapsed))
        Same(Session.view.fastestName, Quiz.Identity.name, "self winner is valid when final choice and timing match")
        Same(Session.view.fastestElapsed, elapsed, "winner timing retains full host precision at accepted boundaries")
    end

    client, view = Client(196)
    Incoming(ResultFields(196, 1, 2, -1, 69, 1, 2, "", 0, 4, "Éclair-Éternel", 15))
    Same(view.fastestName, "Éclair-Éternel", "winner metadata preserves native UTF-8 names and realms")
    Same(view.fastestElapsed, 15, "wrong local timing does not constrain the actual correct winner")
    Same(view.points, -1, "winner announcement cannot turn a wrong local selection into points")
    Incoming(Question(197))
    Incoming(ResultFields(197, 1, "", "", 69, 1, 1, "", nil, 4, PEER, 1.25))
    Same(Session.view.fastestName, PEER, "unanswered participant may see a confirmed remote winner")
    Same(Session.view.selected, nil, "winner presentation does not fabricate an unanswered participant selection")

    client, view = Client(200)
    Incoming(Question(201))
    Incoming(Fields("O", SESSION_ID, 201, GetServerTime() + 15))
    view = Session.view
    Check(Session:SubmitAnswer(3), "newer question has an active selection before the old receipt arrives")
    local currentDeadline, currentScore = view.deadline, view.score
    Comms:Clear()
    local lateWinner = ResultFields(200, 2, 2, 2.5, 73, 1, 1, EXPLANATION, 0, 4, PEER, 0)
    Incoming(lateWinner)
    Same(Quiz.PersonalScores:GetPack(PACK_ID).score, 2.5, "late earlier receipt persists after question advancement")
    Same(Session.view, view, "late receipt preserves the newer view object")
    Same(view.id, 201, "late receipt cannot rewind question identity")
    Same(view.state, "open", "late receipt cannot close the current answer window")
    Same(view.selected, 3, "late receipt cannot replace the current selection")
    Same(view.deadline, currentDeadline, "late receipt cannot change the current timer")
    Same(view.score, currentScore, "late receipt cannot roll back the current session score")
    Same(view.points, nil, "late receipt cannot replay old score feedback")
    Same(view.fastestName, nil, "late receipt cannot announce a prior winner over the current question")
    Same(view.fastestElapsed, nil, "late receipt cannot inject a prior winner timestamp into a newer view")
    local ack = One("F", HOST)
    Same(#ack, 4, "receipt acknowledgement contains identity only, never claimed totals")
    Same(ack[3], "200", "receipt acknowledgement identifies the credited old round")
    Same(ack[4], client.request, "receipt acknowledgement uses current membership")
    local personalRevision = Quiz.PersonalScores.revision
    Incoming(lateWinner)
    Same(
        Quiz.PersonalScores.revision,
        personalRevision,
        "duplicate late results do not invalidate or increment statistics"
    )
    Same(#Queued("F", HOST), 1, "repeated old receipts coalesce their acknowledgement")
    Same(Quiz.PersonalScores:GetPack(PACK_ID).answers, 1, "old receipt replay awards only one answer")

    Comms:Clear()
    local earlyWinner = ResultFields(202, 2, 2, 2.5, 73, 1, 1, EXPLANATION, 0, 4, PEER, 0)
    Incoming(earlyWinner)
    Same(view.id, 201, "result before its question cannot replace current content")
    Same(Quiz.PersonalScores:GetPack(PACK_ID).answers, 2, "self-contained unseen result can be saved without Q")
    Incoming(Question(202))
    view = Session.view
    Same(view.id, 202, "later question content restores the corresponding result")
    Same(view.state, "results", "cached receipt paints the matching later question")
    Same(view.correctIndex, 2, "cached receipt reveals the actual correct answer")
    Same(view.fastestName, PEER, "cached receipt restores the matching winner without guessing new state")
    Same(view.suppressWinnerPopup, true, "result-before-question cannot replay an already-persisted winner popup")
    Same(
        view.suppressScoreAnimation,
        true,
        "already-persisted result does not animate when question data arrives later"
    )
    Same(Quiz.PersonalScores:GetPack(PACK_ID).answers, 2, "painting a cached receipt does not re-award points")

    Check(Quiz.Store:Initialize(OrbitQuizDB), "received personal receipts survive SavedVariables validation")
    local savedAnswers = Quiz.PersonalScores:GetPack(PACK_ID).answers
    Check(Session:Leave(), "explicit leave discards participant-only result caches")
    Check(Session:JoinHost(HOST), "fresh membership reconnects to the same ongoing host")
    client = Session.client
    Welcome(client)
    Incoming(Question(202))
    Incoming(earlyWinner)
    Same(Session.view.state, "results", "fresh session restores a durable already-scored result")
    Same(Session.view.suppressScoreAnimation, true, "durable duplicate suppresses first-paint score animation")
    Same(Session.view.suppressWinnerPopup, true, "durable duplicate also suppresses first-paint winner animation")
    Same(
        Quiz.PersonalScores:GetPack(PACK_ID).answers,
        savedAnswers,
        "fresh membership cannot replay a persistent score"
    )
    Quiz.Widget.scoreAnimation:Stop()
    Quiz.Widget.scoreResultId, Quiz.Widget.scoreResultSession, Quiz.Widget.scoreResultHost = nil, nil, nil
    Quiz.Widget:Refresh()
    Check(
        not Quiz.Widget.scoreAnimation:IsPlaying(),
        "fresh widget rendering cannot animate a durable duplicate result"
    )

    for id = 203, 245 do
        Incoming(Question(id))
        Incoming(Result(id))
        Check(Count(client.questionHistory.entries) <= 32, "participant metadata cache remains bounded")
        Check(Count(client.resultHistory.entries) <= 32, "participant result presentation cache remains bounded")
        Comms:Clear()
    end
    Same(Count(client.questionHistory.entries), 32, "metadata cache retains only its recent question window")
    Same(Count(client.resultHistory.entries), 32, "result presentation cache retains only its recent window")

    round = Host()
    sessionId = Session.hostSession
    peer = Peer()
    Incoming(PeerFields("D", sessionId, round.id), PEER)
    Test.now = round.deadline
    Main:CloseQuestion(Test.now)
    Same(Session.resultCount, 1, "host retains an unanswered receipt until its participant persists it")
    Session:CancelRoundMessages()
    Same(#Queued("R", PEER), 1, "result receipt transport survives ordinary question-message cancellation")
    local resultRecipient = Session.resultRecipients[PEER:lower()]
    for _, fields in ipairs({
        Fields("F", "wrong-session", round.id, peer.request),
        Fields("F", sessionId, round.id, "wrong-request"),
        Fields("F", sessionId, "1.5", peer.request),
        Fields("F", sessionId, round.id, peer.request, "claimed-score"),
    }) do
        Incoming(fields, PEER)
        Same(Session.resultCount, 1, "malformed acknowledgement cannot discard a pending result")
    end
    Incoming(Fields("F", sessionId, round.id, peer.request), "Unjoined-TestRealm")
    Same(Session.resultCount, 1, "another native sender cannot acknowledge a participant's result")
    local oldRequest = peer.request
    Test.now = Test.now + 3
    Peer(PEER, "receipt-request.2")
    Same(Session.resultRecipients[PEER:lower()], resultRecipient, "membership rotation preserves the receipt mailbox")
    Incoming(Fields("F", sessionId, round.id, oldRequest), PEER)
    Same(Session.resultCount, 1, "old membership cannot discard a receipt after reconnect")
    Incoming(Fields("F", sessionId, round.id, peer.request), PEER)
    Same(Session.resultCount, 0, "current-member acknowledgement releases its persisted receipt")
    Same(Session.resultRecipientCount, 0, "empty mailbox releases its recipient slot")
    Same(#Queued("R", PEER), 0, "acknowledgement cancels any remaining receipt retransmission")
    Session:SendResult(peer)
    Same(Session.resultCount, 0, "a repeated snapshot cannot recreate the already-acknowledged current result")

    round = Host()
    Test.now = round.deadline
    Main:CloseQuestion(Test.now)
    local function ReceiptPeer(index)
        local name = "Recipient"
            .. string.char(65 + index % 26)
            .. string.char(65 + math.floor(index / 26))
            .. "-TestRealm"
        return { name = name, playerKey = "name:" .. name:lower() }
    end
    for index = 1, 45 do
        Test.now = Test.now + 0.01
        Session:SendResult(ReceiptPeer(index))
        Check(Session.resultRecipientCount <= 32, "departed-recipient receipt memory has a hard bound")
    end
    Same(Session.resultRecipientCount, 32, "retention keeps only its bounded recipient window")
    Same(Count(Session.resultRecipients), 32, "recipient counter matches actual allocated mailboxes")
    for playerIndex = 100, 115 do
        for resultIndex = 1, 17 do
            Test.now = Test.now + 0.01
            Main.game.lastResult.id = round.id + resultIndex
            Session:SendResult(ReceiptPeer(playerIndex))
            Check(Session.resultCount <= 256, "global receipt count cannot exceed its memory budget")
            Check(
                Session.resultRecipients[ReceiptPeer(playerIndex).name:lower()].count <= 16,
                "a single recipient cannot monopolize the retry cache"
            )
        end
    end
    Same(Session.resultCount, 256, "receipt saturation retains exactly the configured global maximum")
    local retained = 0
    for _, recipient in pairs(Session.resultRecipients) do
        Same(Count(recipient.entries), recipient.count, "per-recipient counters match retained result entries")
        retained = retained + recipient.count
    end
    Same(retained, Session.resultCount, "all retained result counts remain consistent under eviction")
    Test.now = Test.now + 301
    Session:RetryResults(Test.now)
    Same(Session.resultCount, 0, "undelivered results expire after the documented five-minute recovery window")
    Same(Session.resultRecipientCount, 0, "expiration releases every recipient mailbox")
    Same(next(Session.resultRecipients), nil, "expired receipts leave no unbounded stale recipient state")

    do
        local authoredRules = assert(Quiz.Rules.Normalize({
            answerSeconds = 30,
            revealSeconds = 5,
            allowAnswerChanges = false,
            speedBonusPerSecond = 0.2,
            wrongPenaltyStart = 2,
            wrongPenaltyEnd = 1,
            streakBonusPerCorrect = 0.1,
            streakBonusMax = 0.5,
        }))
        local authoredKey = assert(Quiz.Rules.Encode(authoredRules))
        client, view = Client(1500, authoredRules)
        Same(view.duration, 30, "participant accepts the host pack's declared variable answer window")
        Same(view.deadline - GetTime(), 30, "variable-duration participant receives the full advertised clock")
        Same(view.rulesKey, authoredKey, "participant view retains canonical rules without the host pack installed")
        Same(client.rulesKey, authoredKey, "the first accepted question establishes one game-wide rules authority")
        Check(Session:SubmitAnswer(2), "a locked-answer participant may make its first selection")
        local revision, selected = client.answerRevision, view.selected
        Check(not Session:SubmitAnswer(3), "a locked-answer participant cannot submit a replacement")
        Same(client.answerRevision, revision, "a rejected replacement cannot advance action timing")
        Same(view.selected, selected, "locked replacement does not flash a different local selection")
        Comms:Clear()
        Incoming(ReplyFields("K", SESSION_ID, 1500, 2))
        Check(view.locked, "acknowledged locked answer remains locked until the next question")
        local otherRules = assert(Quiz.Rules.Normalize({ answerSeconds = 30, speedBonusPerSecond = 0.3 }))
        Unchanged(Question(1501), "a later default-rule question cannot silently replace the game's rules")
        Unchanged(
            Question(1501, nil, nil, nil, otherRules),
            "valid but different rule definitions are rejected within one game"
        )
        Unchanged(
            Changed(Question(1501, nil, nil, nil, authoredRules), 7, "15"),
            "question clock must exactly match its authored rules"
        )
        Unchanged(
            Changed(Question(1501, nil, nil, nil, authoredRules), 16, "0" .. authoredKey),
            "equivalent noncanonical rules keys are rejected"
        )
        Unchanged(
            Question(1501, nil, nil, nil, authoredRules),
            "old fixed-rule clients cannot inject current question shapes",
            HOST,
            "ORBITQUIZ6"
        )
        local authoredResult = ResultFields(1500, 2, 2, 5.2, 75.2, 1, 1, EXPLANATION, 10, 4, nil, nil, authoredRules, 3)
        for _, fields in ipairs({
            Changed(authoredResult, 6, "5.0"),
            Changed(authoredResult, 6, "5.3"),
            Changed(authoredResult, 15, "15"),
            Changed(authoredResult, 20, defaultRulesKey),
            Changed(authoredResult, 20, assert(Quiz.Rules.Encode(otherRules))),
            Changed(authoredResult, 21, "1"),
            Changed(authoredResult, 22, "0"),
            Changed(authoredResult, 22, "0.3"),
        }) do
            Unchanged(fields, "variable-rule result must recompute exactly from its rules and streak")
        end
        Incoming(authoredResult)
        Same(view.points, 5.2, "participant accepts recomputed base, speed and streak points")
        Same(view.streak, 3, "confirmed result exposes its finalized streak count")
        Same(view.streakBonus, 0.2, "confirmed result exposes its additional streak points")
        Same(
            Quiz.PersonalScores:GetPack(PACK_ID).score,
            5.2,
            "rule-authoritative points persist without a participant pack"
        )
        local revisionBeforeReplay = Quiz.PersonalScores.revision
        Incoming(authoredResult)
        Same(
            Quiz.PersonalScores.revision,
            revisionBeforeReplay,
            "rule-aware receipt retries cannot award the streak twice"
        )
        Unchanged(Changed(authoredResult, 21, "4"), "receipt replay cannot change already confirmed streak accounting")

        local zeroRules = assert(Quiz.Rules.Normalize({
            answerSeconds = 5,
            correctPoints = 0,
            speedBonusPerSecond = 0,
            wrongPenaltyStart = 0,
            wrongPenaltyEnd = 0,
        }))
        client, view = Client(1510, zeroRules)
        Incoming(ResultFields(1510, 2, 2, 0, 70, 1, 1, "", 1, 4, nil, nil, zeroRules, 1))
        Same(view.state, "results", "zero-reward practice rules remain valid for a correct answer")
        Same(view.points, 0, "zero authored reward is not rejected by obsolete positive-score bounds")
        Incoming(Question(1511, nil, nil, nil, zeroRules))
        Incoming(ResultFields(1511, 2, 1, 0, 70, 0, 1, "", 1, 4, nil, nil, zeroRules, 0))
        Same(Session.view.points, 0, "zero-penalty practice rules remain valid for a wrong answer")
        Same(Session.view.streak, 0, "a zero-penalty wrong answer still resets its streak")

        local maximumRules = assert(Quiz.Rules.Normalize({
            version = 2147483647,
            answerSeconds = 120,
            correctPoints = 1000,
            speedBonusPerSecond = 10,
            wrongPenaltyStart = 1000,
            wrongPenaltyEnd = 1000,
            streakBonusPerCorrect = 10,
            streakBonusMax = 100,
        }))
        client, view = Client(1520, maximumRules)
        Same(view.duration, 120, "the maximum valid authored clock survives the protocol")
        local maximumResult = ResultFields(1520, 2, 2, 2300, 2370, 1, 1, "", 0, 4, nil, nil, maximumRules, 11)
        Unchanged(
            Changed(maximumResult, 6, "2300.1"),
            "valid rule metadata cannot authorize an excessive computed reward"
        )
        Incoming(maximumResult)
        Same(view.points, 2300, "maximum valid base, speed and streak reward is accepted")
        Incoming(Question(1521, nil, nil, nil, maximumRules))
        local wrongResult = ResultFields(1521, 2, 1, -1000, 1370, 0, 1, "", 0, 4, nil, nil, maximumRules, 0)
        Unchanged(Changed(wrongResult, 21, "1"), "a wrong result cannot claim a nonzero correct streak")
        Unchanged(Changed(wrongResult, 22, "1"), "a wrong result cannot add a streak reward")
        Incoming(wrongResult)
        Same(Session.view.points, -1000, "maximum valid authored wrong penalty remains signed")
        Incoming(Question(1522, nil, nil, nil, maximumRules))
        local skipped = ResultFields(1522, 2, "", "", 1370, 0, 0, "", nil, 4, nil, nil, maximumRules, 0)
        Unchanged(Changed(skipped, 21, "1"), "an unanswered result cannot retain a streak")
        Unchanged(Changed(skipped, 22, "0.1"), "an unanswered result cannot fabricate streak points")
        Incoming(skipped)
        Same(Session.view.points, nil, "maximum-rule unanswered results retain no invented answer or points")
    end

    do
        client, view = Client(1800)
        local ownName = Quiz.Identity.name
        local function Name(id, name, request)
            return Fields("N", SESSION_ID, request or client.request, id, name)
        end
        local result = Changed(ResultFields(1800, 2, 2, 2.5, 72.5, 2, 2, "", 0, 4, nil, nil, nil, 5), 23, "1:5,2:10")
        Unchanged(Name(1, ownName, "old-request.1"), "old membership cannot install milestone names")
        Unchanged(Name(1, ownName), "another native sender cannot supply milestone names", OTHER_HOST)
        Unchanged(Changed(Name(1, ownName), 2, "different-session"), "another session cannot install milestone names")
        for _, name in ipairs({ "", "Shortname", "Name With Spaces-Realm", "Name-Realm|cff00ff00", "<Forged>-Realm" }) do
            Unchanged(Name(1, name), "noncanonical or unsafe milestone names are rejected")
        end
        Incoming(Name(1, ownName))
        Same(
            client.streakSpeakers.entries[1].name,
            ownName,
            "name dictionary stores only a normalized host-provided identity"
        )
        Same(view.streakMilestones, nil, "name prefetch never announces a provisional streak")
        Comms:Clear()
        Unchanged(Name(1, HOST), "a known speaker ID cannot be rebound to another player")
        Unchanged(Name(2, ownName), "one player cannot occupy several current-generation speaker IDs")
        Unchanged(
            Fields("N", SESSION_ID, client.request, "2,3", HOST .. ",Bad Name-Realm"),
            "a malformed name batch rejects atomically"
        )
        Same(
            client.streakSpeakers.entries[2],
            nil,
            "a rejected batch cannot partially install its valid first identity"
        )
        Unchanged(
            Fields("N", SESSION_ID, client.request, "3,2", HOST .. ",Other-Realm"),
            "out-of-order batch IDs are not canonical"
        )
        Unchanged(
            Fields("N", SESSION_ID, client.request, "2,3,4,5,6", "A-Realm,B-Realm,C-Realm,D-Realm,E-Realm"),
            "name batches are capped at four identities"
        )
        for _, encoded in ipairs({
            "0:5",
            "01:5",
            "1:4",
            "1:05",
            "1:5,1:6",
            "2:6,1:5",
            "1:5,",
            ",1:5",
            "1:5,,2:6",
            "1:5x",
            "1:nan",
            "1:5,2:6,3:7",
            "1:9007199254740991",
            string.rep("1", 600),
        }) do
            Unchanged(
                Changed(result, 23, encoded),
                "malformed or excessive group streak metadata rejects transactionally"
            )
        end
        Incoming(result)
        Same(view.state, "results", "a missing name-map packet never blocks the verified score result")
        Same(view.points, 2.5, "the score persists without any presentation dictionary dependency")
        Same(#view.streakMilestones, 1, "an incomplete dictionary exposes only its verified display identities")
        Same(view.streakMilestones[1].name, ownName, "a missing unrelated name does not suppress known milestones")
        Same(
            Quiz.PersonalScores:GetPack(PACK_ID).answers,
            1,
            "unresolved presentation data awards the one valid answer"
        )
        Comms:Clear()
        Quiz.StreakSync:TickClient(client, view, Test.now)
        Same(One("U", HOST)[4], "2", "the participant requests only its missing current-result speaker")
        Incoming(Name(2, HOST))
        Same(#view.streakMilestones, 2, "a lost name map can complete the current committed group result")
        Same(view.streakMilestones[1].name, HOST, "milestone batches put the highest streak first")
        Same(view.streakMilestones[1].streak, 10, "decoded group counts retain the full ten-plus streak")
        Same(view.streakMilestones[2].name, ownName, "a player sees their own confirmed milestone with the group")
        Same(view.suppressStreakToasts, false, "a fresh current-round result is eligible for milestone presentation")
        local milestones = view.streakMilestones
        Incoming(result)
        Same(view.streakMilestones, milestones, "a duplicate receipt cannot replace the immutable presentation batch")
        Comms:Clear()
        Unchanged(Changed(result, 23, "1:5,2:11"), "a duplicate round cannot change another player's milestone")
        Same(Quiz.PersonalScores:GetPack(PACK_ID).answers, 1, "milestone maps and receipt replays never award again")
        Incoming(Question(1801))
        Incoming(Name(2, HOST))
        Same(
            Session.view.streakMilestones,
            nil,
            "a delayed name map cannot attach the previous round's toast to a new question"
        )
        Incoming(result)
        Same(
            Session.view.streakMilestones,
            nil,
            "historical retained results do not rewind the active question's toast batch"
        )

        client, view = Client(1810)
        local replay = Changed(ResultFields(1810, 2, 2, 2.5, 72.5, 1, 1, "", 0, 4, nil, nil, nil, 5), 23, "1:5")
        Incoming(replay)
        Same(view.correctIndex, 2, "result without dictionary still establishes authoritative correctness")
        Session:SetRestricted(true)
        Test.now = Test.now + 1
        Session:SetRestricted(false)
        local previousRequest = client.request
        Incoming(Fields("W", previousRequest, SESSION_ID, LEAGUE, "72.5"))
        Incoming(Question(1810))
        Incoming(Fields("N", SESSION_ID, previousRequest, 1, Quiz.Identity.name))
        Same(
            Session.view.suppressStreakToasts,
            true,
            "same-round membership recovery suppresses historical celebrations"
        )
        Same(
            Session.view.streakMilestones[1].streak,
            5,
            "resync may retain descriptive milestones without replay permission"
        )
        Same(Quiz.PersonalScores:GetPack(PACK_ID).answers, 1, "resync never reapplies the associated score")

        client, view = Client(1820)
        for id = 1, 100 do
            local name = "Speaker"
                .. string.char(65 + math.floor((id - 1) / 26))
                .. string.char(65 + (id - 1) % 26)
                .. "-Realm"
            Incoming(Fields("N", SESSION_ID, client.request, id, name))
        end
        Same(client.streakSpeakers.count, 36, "a new 64-ID generation replaces rather than grows the client dictionary")
        Check(Count(client.streakSpeakers.entries) <= 64, "bounded speaker bookkeeping matches its actual table")
        Comms:Clear()
        Unchanged(
            Fields("N", SESSION_ID, client.request, 1, "Replacement-Realm"),
            "evicted old IDs cannot be rebound later"
        )

        round = Host()
        peer = Peer()
        Drain()
        Session:Tick(Test.now)
        local names = Queued("N", PEER)
        Same(#names, 1, "idle transport prewarms one small name message at a time")
        local nameFields = names[1].fields
        local firstSpeakerId = tonumber(nameFields[4]:match("^%d+"))
        Same(#nameFields, 5, "name metadata stays separate from the score receipt")
        Incoming(Fields("B", Session.hostSession, "old-request.1", nameFields[4]), PEER)
        Same(peer.streakAcknowledged[firstSpeakerId], nil, "old membership cannot acknowledge a speaker map")
        Incoming(Fields("B", Session.hostSession, peer.request, nameFields[4]), PEER)
        Same(peer.streakAcknowledged[firstSpeakerId], true, "the current peer acknowledges its received identity map")
        Comms:Clear()
        Check(Comms:Send(PEER, { "T", "busy", "busy" }), "a gameplay packet occupies the outbox")
        Session:Tick(Test.now + 1)
        Same(#Queued("N", PEER), 0, "name prefetch cannot add traffic ahead of queued gameplay")
        Comms:Clear()
        for id = 1, 100 do
            local name = "Guest"
                .. string.char(65 + math.floor((id - 1) / 26))
                .. string.char(65 + (id - 1) % 26)
                .. "-Realm"
            Check(Quiz.StreakSync:Register(Session, name), "bounded host dictionary assigns a monotonic speaker ID")
        end
        Check(Session.streakSpeakers.count <= 64, "host identity-cache rotation does not grow with session churn")
        Check(Session.streakSpeakers.sequence > 100, "rotating a dictionary never reuses an old speaker ID")
        Check(
            Session.streakSpeakers.byName[Quiz.Identity.name:lower()],
            "dictionary rotation retains the host identity"
        )
        Check(
            Session.streakSpeakers.byName[PEER:lower()],
            "dictionary rotation retains every active participant identity"
        )
    end

    client, view = Client(80)
    Unchanged(Fields("X", SESSION_ID), "another native sender cannot end the session", OTHER_HOST)
    Incoming(Fields("X", SESSION_ID))
    Same(Session.client, nil, "selected host can end its own session")
    Same(view.state, "stopped", "host end message closes participant play")
    Check(not Comms:IsBusy(), "host end clears old answer and sync traffic")
    Main:Tick()
    Same(Main.ticker, nil, "terminated participant releases the runtime ticker")
    Same(#Test.errors, 0, "protocol suite did not trigger the WoW error handler")
    return assertions
end

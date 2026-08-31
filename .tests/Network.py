"""Exercise isolated clients through native discovery and the real fragmented quiz transport."""

import math

from lupa.lua51 import lua_type

from run import runtime

QUIZ_PREFIX = "ORBITQUIZ6"
DISCOVERY_PREFIX = "ORBITQUIZDISC6"
LOBBY_NAME = "OrbitQuizLobby"
REVEAL_SECONDS = 3
BOUNDARY_EPSILON = 0.001


def decode_fields(encoded):
    count_text, rest = encoded.split(b":", 1)
    fields = []
    for _ in range(int(count_text)):
        length_text, rest = rest.split(b":", 1)
        length = int(length_text)
        fields.append(rest[:length].decode("utf-8"))
        rest = rest[length:]
    assert not rest, "unexpected trailing bytes in outgoing codec"
    return fields


def saved_copy(value):
    if lua_type(value) == "table":
        return {key: saved_copy(entry) for key, entry in value.items()}
    return value


class Node:
    def __init__(self, name, saved=None):
        self.lua, self.quiz = runtime(host_name=name)
        self.test = self.lua.globals().Test
        self.test.hostGUID = "Player-0-" + (name if name.isascii() else name.encode("utf-8").hex())
        self.name = f"{name}-TestRealm"
        self.guild = "test-guild"
        self.home_group = "test-home-group"
        self.instance_group = "test-instance-group"
        self.cursor = 0
        self.export = self.lua.eval("""function(index)
            local entry = Test.addonSent[index]
            local hex = entry.text:gsub('.', function(c) return ('%02x'):format(string.byte(c)) end)
            return entry.prefix, hex, entry.channel, entry.target
        end""")
        self.receive = self.lua.eval("""function(prefix, hex, channel, sender, target, localID, channelName)
            local text = hex:gsub('%x%x', function(c) return string.char(tonumber(c, 16)) end)
            OrbitQuiz.Main:OnEvent('CHAT_MSG_ADDON', prefix, text, channel, sender, target, 0, localID, channelName)
        end""")
        if saved is not None:
            self.lua.globals().OrbitQuizDB = self.lua.table_from(saved, recursive=True)
            self.event("ADDON_LOADED", "Orbit-Quiz")
            self.event("PLAYER_LOGIN")

    def call(self, owner, method, *args):
        module = self.quiz[owner]
        return module[method](module, *args)

    def view(self):
        return self.call("Session", "GetView")

    def event(self, event, *args):
        self.call("Main", "OnEvent", event, *args)

    def games(self):
        return list(self.call("Discovery", "GetGames").values())

    def answer_on(self, host):
        peer = host.quiz.Session.peers[self.name.lower()]
        return host.quiz.Main.game.round.answers[peer.playerKey] if peer else None

    def standings(self):
        return self.quiz.Main.game.GetStandings(self.quiz.Main.game)

    def personal(self, pack_id):
        return self.call("PersonalScores", "GetPack", pack_id)


class World:
    def __init__(self, *names):
        self.nodes = [Node(name) for name in names]
        self.by_name = {node.name.lower(): node for node in self.nodes}
        self.packet_codes = {}
        self.packets = []
        self.drop = lambda packet: False

    def recipients(self, source, channel, target_name):
        if channel == "WHISPER":
            target = self.by_name.get(target_name.lower())
            return [target] if target else []
        if channel == "CHANNEL":
            if not source.test.lobbyJoined or str(target_name) != str(source.test.lobbyId):
                return []
            return [node for node in self.nodes if node.test.lobbyJoined]
        if channel == "GUILD":
            return [node for node in self.nodes if node.test.guild and node.guild == source.guild]
        if channel in ("PARTY", "RAID"):
            return [node for node in self.nodes if (node.test.group or node.test.raid) and node.home_group == source.home_group
                    and bool(node.test.raid) == (channel == "RAID")]
        if channel == "INSTANCE_CHAT":
            return [node for node in self.nodes if node.test.instance and node.instance_group == source.instance_group]
        raise AssertionError(f"Unsupported native addon route: {channel}")

    def deliver(self, packet):
        target = self.by_name.get(packet["target"].lower())
        if target:
            target.receive(packet["prefix"], packet["hex"], packet["channel"], packet["source"].name,
                           target.name if packet["channel"] == "WHISPER" else None,
                           target.test.lobbyId if packet["channel"] == "CHANNEL" else 0,
                           LOBBY_NAME if packet["channel"] == "CHANNEL" else "")

    def step(self, seconds=0.1):
        for node in self.nodes:
            node.test.Advance(seconds)
        for source in self.nodes:
            while source.cursor < len(source.test.addonSent):
                source.cursor += 1
                prefix, text, channel, target_name = source.export(source.cursor)
                wire = bytes.fromhex(text)
                fields = None
                if prefix == QUIZ_PREFIX:
                    version, message_id, part, total, fragment = wire.split(b"|", 4)
                    assert version == b"1", "the quiz prefix changes without changing the transport envelope"
                    key = source.name, message_id
                    if part == b"1":
                        self.packet_codes[key] = fragment.split(b":", 2)[2][:1].decode("ascii")
                    code = self.packet_codes.get(key)
                    if total == b"1":
                        fields = decode_fields(fragment)
                elif prefix == DISCOVERY_PREFIX:
                    version, code, *_ = wire.decode("utf-8").split("|")
                    assert version == "6", "discovery advertises the personal-pack scoring protocol version"
                    message_id, part, total = str(source.cursor).encode("ascii"), b"1", b"1"
                    fields = wire.decode("utf-8").split("|")
                else:
                    raise AssertionError(f"Unexpected registered prefix: {prefix}")
                for target in self.recipients(source, channel, target_name):
                    packet = dict(source=source, target=target.name, native_target=target_name, prefix=prefix,
                                  hex=text, channel=channel, part=int(part), total=int(total),
                                  message_id=message_id, code=code, wire=wire, fields=fields)
                    self.packets.append(packet)
                    if not self.drop(packet):
                        self.deliver(packet)

    def advance(self, seconds):
        for _ in range(math.ceil(seconds / 0.1)):
            self.step()

    def until(self, condition, seconds=15):
        if condition():
            return
        for _ in range(math.ceil(seconds / 0.1)):
            self.step()
            if condition():
                return
        states = [(node.name, node.view().state, node.view().id, node.view().notice) for node in self.nodes]
        raise AssertionError(f"Network condition timed out: {states}")


def run_suite():
    assertions = 0

    def check(value, message):
        nonlocal assertions
        assertions += 1
        assert value, message

    def equal(actual, expected, message):
        check(actual == expected, f"{message}: {actual!r} != {expected!r}")

    def ok(result, message):
        check((result[0] if isinstance(result, tuple) else result) is True, f"{message}: {result}")

    def register_pack(node, pack_id, title, version=1):
        register = node.lua.eval("""function(id, title, version)
            return OrbitQuiz:RegisterQuestionPack({id=id, title=title, version=version, questions={
                {id='shared-question', prompt='Which answer is correct?',
                    choices={'Right', 'Wrong one', 'Wrong two', 'Wrong three'}, correctIndex=1}
            }})
        end""")
        ok(register(pack_id, title, version), "fixture pack registers with stable identity")

    def join_and_answer(world, host, player, pack_id, correct=True):
        setup = host.call("Store", "GetSettings")
        setup.packId = pack_id
        ok(host.call("Main", "Start", setup), "host starts a personal-progress fixture")
        ok(player.call("Session", "JoinHost", host.name), "participant chooses the fixture host")
        world.until(lambda: player.view().state == "open" and player.view().hostName == host.name)
        round_ = host.quiz.Main.game.round
        equal(player.view().score, 0, "a fresh host game never imports personal lifetime totals")
        choice = round_.correctIndex if correct else round_.correctIndex % 4 + 1
        ok(player.call("Session", "SubmitAnswer", choice), "participant submits a real timed selection")
        world.until(lambda: player.view().confirmedSelected == choice and not player.view().pending)
        points = player.answer_on(host).points
        world.until(lambda: player.view().correctIndex is not None, seconds=20)
        equal(player.view().points, points, "host-authoritative result reaches personal progress")
        return round_, points

    def captured_results(packets, host, player):
        messages = {}
        for packet in packets:
            if (packet["source"] is host and packet["target"] == player.name
                    and packet["prefix"] == QUIZ_PREFIX and packet["code"] == "R"):
                messages.setdefault(packet["message_id"], {})[packet["part"]] = packet
        results = []
        for parts in messages.values():
            if 1 in parts and len(parts) == parts[1]["total"]:
                ordered = [parts[index] for index in range(1, len(parts) + 1)]
                encoded = b"".join(packet["wire"].split(b"|", 4)[4] for packet in ordered)
                results.append((decode_fields(encoded), ordered))
        return results

    world = World("Quizhost", "Player", "Friend")
    host, player, friend = world.nodes
    settings = host.call("Store", "GetSettings")
    settings.league = "Guild {Quiz}"
    settings.duration = 20
    ok(host.call("Main", "Start", settings), "start autonomous host")
    equal(host.quiz.Main.game.settings.duration, 15, "legacy settings cannot change hosted duration")
    equal(host.quiz.Main.game.round.deadline - host.quiz.Main.game.round.startedAt, 15,
          "every hosted question opens for exactly fifteen seconds")
    world.until(lambda: len(player.games()) == len(friend.games()) == 1)
    equal(player.games()[0].hostName, host.name, "native discovery exposes the host without typing")
    equal(player.games()[0].league, settings.league, "discovery preserves selected league")
    ok(player.call("Session", "JoinHost", player.games()[0].hostName), "join using discovered row")
    ok(friend.call("Session", "JoinHost", friend.games()[0].hostName), "another participant joins discovered row")
    world.until(lambda: player.view().state == friend.view().state == "open")
    question = host.quiz.Main.game.round
    equal(player.view().duration, 15, "native question payload advertises the fixed fifteen-second window")
    equal(player.view().id, question.id, "joined mid-round id")
    for index in range(1, 5):
        equal(player.view().choices[index], question.choices[index], "wire preserves answer order")
    equal(player.view().correctIndex, None, "question does not reveal correct answer")
    equal(player.view().points, None, "no early points/correctness hint")
    wrong = question.correctIndex % 4 + 1
    ok(host.call("Session", "SubmitAnswer", wrong), "host participates locally")
    ok(player.call("Session", "SubmitAnswer", wrong), "player initially selects wrong answer")
    equal(player.view().pending, True, "player waits for acknowledgement")
    ok(player.call("Session", "SubmitAnswer", question.correctIndex), "pending answer can be adjusted immediately")
    ok(friend.call("Session", "SubmitAnswer", question.choices[wrong]), "exact typed choice travels over wire")
    world.until(lambda: player.view().confirmedSelected == question.correctIndex and friend.view().confirmedSelected == wrong)
    equal(player.view().pending, False, "acknowledgement confirms current selection")
    equal(player.view().locked, False, "confirmed answer remains adjustable until deadline")
    world.until(lambda: host.test.now >= question.startedAt + 5.2)
    ok(player.call("Session", "SubmitAnswer", wrong), "confirmed answer can change later in the round")
    world.until(lambda: player.view().confirmedSelected == wrong)
    ok(player.call("Session", "SubmitAnswer", question.correctIndex), "last corrected answer becomes authoritative")
    world.until(lambda: player.view().confirmedSelected == question.correctIndex and not player.view().pending)
    equal(player.answer_on(host).points, 1.9, "new timing score uses the latest correct submission")
    latest_elapsed = player.answer_on(host).elapsed
    check(latest_elapsed >= 5.2, "last accepted timestamp replaces early incorrect selection")
    world.until(lambda: player.view().correctIndex is not None, seconds=25)
    equal(player.view().points, 1.9, "fractional points arrive without integer truncation")
    equal(friend.view().points, friend.answer_on(host).points, "remote wrong-answer penalty survives transport exactly")
    equal(host.view().points, question.answers[host.test.hostGUID].points, "host receives its authoritative wrong-answer penalty")
    check(-1 <= friend.view().points <= -0.5, "remote wrong answers incur the bounded negative penalty")
    check(-1 <= host.view().points <= -0.5, "host wrong answers incur the same negative penalty range")
    equal(player.view().correctCount, 1, "shared correct count")
    equal(player.view().totalAnswers, 3, "local and remote answers count once")
    for node in world.nodes:
        equal(node.view().fastestName, player.name, "the correct final selection wins over faster wrong guesses")
        equal(node.view().fastestElapsed, latest_elapsed, "all clients receive the winner's final host-receipt time")
    equal(len(host.standings()), 3, "host session ranks all three authoritative player totals")
    equal(len(host.call("Store", "GetStandings", "Guild {Quiz}", "PUBLIC")), 0,
          "new host results leave archived leagues untouched")
    equal(len(player.call("Store", "GetStandings", "Guild {Quiz}", "PUBLIC")), 0,
          "participant never writes host league totals locally")
    equal(player.personal(question.packId).score, 1.9, "participant saves its own pack score")
    equal(player.personal(question.packId).answers, 1, "participant saves one finalized answer")
    equal(friend.personal(question.packId).score, friend.view().points, "each account saves only its own penalty")
    equal(host.personal(question.packId).score, host.view().points, "hosting credits only the host's own answer")
    next_at = host.quiz.Main.nextAutoAt
    check(0 <= next_at - REVEAL_SECONDS - question.deadline < 0.100001,
          "the host schedules three seconds of reveal from its deadline tick")
    world.step(next_at - host.test.now - BOUNDARY_EPSILON)
    for node in world.nodes:
        equal(node.view().state, "results", "each connected player retains results until the three-second boundary")
        equal(node.view().id, question.id, "the revealed question remains visible until automatic progression")
        equal(node.view().correctIndex, question.correctIndex, "the correct answer remains revealed throughout the break")
        equal(node.view().locked, True, "revealed choices stay locked on every client")
    world.step(next_at - host.test.now)
    check(host.quiz.Main.game.round.id != question.id, "the host prepares the next question at exactly three seconds")
    equal(host.test.now, next_at, "automatic preparation begins at the scheduled reveal boundary")
    equal(host.quiz.Main.nextAutoAt, None, "starting the next question consumes the prior result deadline")
    world.until(lambda: player.view().id != question.id and player.view().state == "open")
    equal(host.quiz.Main.game.round.deadline - host.quiz.Main.game.round.startedAt, 15,
          "peer readiness after the reveal preserves the full fifteen-second answer window")
    equal(player.view().correctIndex, None, "the next remote question clears the prior revealed answer")
    equal(player.view().selected, None, "new question clears previous selection")
    equal(player.view().score, 1.9, "fractional session score survives the next question")
    for node in world.nodes:
        equal(len(node.test.sent), 0, "widget traffic never calls visible chat")
    ok(host.call("Main", "Stop"), "stop host")
    world.until(lambda: player.view().state == friend.view().state == "stopped")
    equal(host.quiz.Session.hostSession, None, "stopping clears hosting while discovery remains available")

    for automatic in (False, True):
        world = World("Quizhost", "Player")
        host, player = world.nodes
        settings = host.call("Store", "GetSettings")
        settings.league = "Restricted reveal" if automatic else "Manual reveal"
        ok(host.call("Main", "Start", settings), "reveal-pause host starts automatically")
        ok(player.call("Session", "JoinHost", host.name), "reveal-pause participant joins")
        world.until(lambda: player.view().state == "open")
        round_ = host.quiz.Main.game.round
        ok(player.call("Session", "SubmitAnswer", round_.correctIndex), "reveal-pause player answers")
        world.until(lambda: player.view().correctIndex is not None)
        saved_score = player.view().score
        equal(host.quiz.Main.game.completed, 1, "reveal-pause starts after one finalized question")
        if automatic:
            host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
            host.test.restricted = True
        else:
            ok(host.call("Main", "Pause", None, False), "manual host pause interrupts the reveal")
            world.until(lambda: player.view().state == "paused")
        equal(host.quiz.Main.nextAutoAt, None, "pausing results cancels their three-second auto-advance")
        world.advance(REVEAL_SECONDS + 1)
        equal(host.quiz.Main.game.state, "paused", "the canceled reveal deadline cannot resume the host")
        equal(host.quiz.Main.game.round.id, round_.id, "no next question is prepared while results are paused")
        equal(host.quiz.Main.game.completed, 1, "a paused reveal cannot finalize another question")
        standings = host.standings()
        equal(standings[1].score, saved_score, "paused reveal retains its already-earned score")
        equal(standings[1].answers, 1, "paused reveal never commits the same answer twice")
        if automatic:
            host.test.restricted = False
            host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
        else:
            ok(host.call("Main", "Resume"), "manual reveal pause resumes explicitly")
        world.until(lambda: player.view().state == "open" and player.view().id != round_.id)
        equal(player.view().id, host.quiz.Main.game.round.id, "reveal recovery synchronizes the new question")
        equal(host.quiz.Main.game.round.deadline - host.quiz.Main.game.round.startedAt, 15,
              "reveal recovery gives the next question a full fifteen-second answer window")
        equal(player.view().score, saved_score, "reveal recovery retains the player's earned score")
        equal(player.view().correctIndex, None, "reveal recovery clears the old correct answer")
        equal(player.view().selected, None, "reveal recovery clears the old choice")
        host.call("Main", "Stop")
        world.until(lambda: player.view().state == "stopped")

    world = World("Quizhost", "Player")
    host, player = world.nodes
    ok(host.call("Main", "Start"), "answer-order host")
    ok(player.call("Session", "JoinHost", host.name), "answer-order participant")
    world.until(lambda: player.view().state == "open")
    round_ = host.quiz.Main.game.round
    correct, wrong = round_.correctIndex, round_.correctIndex % 4 + 1
    delayed_answers, delayed_acks = [], []

    def delay_old_actions(packet):
        if packet["prefix"] != QUIZ_PREFIX or packet["fields"] is None:
            return False
        fields = packet["fields"]
        if packet["source"] is player and fields[0] == "A" and fields[4] == "1":
            delayed_answers.append(packet)
            return True
        if packet["source"] is host and fields[0] == "K" and fields[4] == "2":
            delayed_acks.append(packet)
            return True
        return False

    world.drop = delay_old_actions
    ok(player.call("Session", "SubmitAnswer", correct), "first action is allowed onto wire")
    world.until(lambda: len(delayed_answers) > 0)
    equal(player.answer_on(host), None, "delayed first action has not reached the host")
    ok(player.call("Session", "SubmitAnswer", wrong), "newer action does not wait for earlier acknowledgement")
    world.until(lambda: player.answer_on(host) is not None and player.answer_on(host).choiceIndex == wrong)
    world.until(lambda: len(delayed_acks) > 0)
    newer_elapsed = player.answer_on(host).elapsed
    world.deliver(delayed_answers[0])
    world.advance(0.3)
    equal(player.answer_on(host).choiceIndex, wrong, "late older answer cannot override a newer revision")
    equal(player.answer_on(host).elapsed, newer_elapsed, "late older answer cannot rewrite accepted timing")
    world.advance(2.2)
    ok(player.call("Session", "SubmitAnswer", correct), "third revision replaces pending second answer")
    world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending)
    newest_elapsed = player.answer_on(host).elapsed
    check(newest_elapsed > newer_elapsed, "new selection receives a genuinely newer timestamp")
    world.deliver(delayed_acks[0])
    world.advance(0.2)
    equal(player.view().selected, correct, "late older acknowledgement cannot roll back latest selection")
    equal(player.view().confirmedSelected, correct, "late older acknowledgement cannot roll back confirmation")
    equal(player.view().pending, False, "late acknowledgement cannot reopen latest pending state")
    equal(player.answer_on(host).elapsed, newest_elapsed, "old acknowledgement has no timing authority")
    host.call("Main", "Stop")

    world = World("Quizhost", "Player")
    host, player = world.nodes
    ok(host.call("Main", "Start"), "rapid-change host")
    ok(player.call("Session", "JoinHost", host.name), "rapid-change participant")
    world.until(lambda: player.view().state == "open")
    correct = host.quiz.Main.game.round.correctIndex
    wrong = correct % 4 + 1
    ok(player.call("Session", "SubmitAnswer", correct), "first correct selection")
    world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending)
    original_elapsed, original_points = player.answer_on(host).elapsed, player.answer_on(host).points
    world.advance(2.2)
    middle_packets = []

    def lose_middle_choice(packet):
        if packet["prefix"] == QUIZ_PREFIX and packet["code"] == "A" and packet["fields"][4] == "2":
            middle_packets.append(packet)
            return True
        return False

    world.drop = lose_middle_choice
    ok(player.call("Session", "SubmitAnswer", wrong), "middle choice is a distinct input action")
    world.until(lambda: len(middle_packets) > 0)
    ok(player.call("Session", "SubmitAnswer", correct), "return to original choice while middle packet is lost")
    world.until(lambda: not player.view().pending and host.quiz.Session.peers[player.name.lower()].answerRevision == 3)
    equal(player.answer_on(host).elapsed, original_elapsed,
          "a lost intermediate change leaves the same host-accepted choice unretimed")
    equal(player.answer_on(host).points, original_points,
          "a higher revision of the unchanged host choice preserves its original bonus")
    updated_elapsed = player.answer_on(host).elapsed
    updated_points = player.answer_on(host).points
    world.deliver(middle_packets[0])
    world.advance(0.2)
    equal(player.answer_on(host).choiceIndex, correct, "delayed middle revision cannot undo final A")
    equal(player.answer_on(host).elapsed, updated_elapsed, "delayed middle revision cannot change final-A timing")
    world.until(lambda: player.view().correctIndex is not None, seconds=25)
    equal(player.view().points, updated_points, "result retains original accepted timing when B never reached the host")
    equal(player.view().totalAnswers, 1, "three actions still produce only one answer")
    equal(player.view().correctCount, 1, "lost intermediate choice does not add incorrect count")
    host.call("Main", "Stop")

    world = World("Quizhost", "Player")
    host, player = world.nodes
    settings = host.call("Store", "GetSettings")
    ok(host.call("Main", "Start", settings), "same-host rejoin host")
    ok(player.call("Session", "JoinHost", host.name), "first membership request")
    world.until(lambda: player.view().state == "open")
    correct = host.quiz.Main.game.round.correctIndex
    wrong = correct % 4 + 1
    old_request = player.quiz.Session.client.request
    delayed_membership = []

    def delay_old_membership(packet):
        if packet["source"] is not player or packet["prefix"] != QUIZ_PREFIX or packet["fields"] is None:
            return False
        fields = packet["fields"]
        if (fields[0] == "A" and fields[5] == old_request
                or fields[0] == "L" and fields[2] == old_request
                or fields[0] == "J" and fields[1] == old_request):
            delayed_membership.append(packet)
            return True
        return False

    world.drop = delay_old_membership
    initial_join_packet = next(packet for packet in world.packets
                               if packet["prefix"] == QUIZ_PREFIX and packet["code"] == "J")
    ok(player.call("Comms", "Send", host.name, player.lua.table_from(["J", old_request])),
       "old membership emits a legitimate new-wire join retry")
    world.until(lambda: any(packet["code"] == "J" for packet in delayed_membership))
    old_join_retry = next(packet for packet in delayed_membership if packet["code"] == "J")
    check(old_join_retry["message_id"] != initial_join_packet["message_id"],
          "delayed old join has a fresh transport ID so protocol ordering is actually tested")
    ok(player.call("Session", "SubmitAnswer", wrong), "old membership sends a delayed answer")
    world.until(lambda: any(packet["code"] == "A" for packet in delayed_membership))
    ok(player.call("Session", "Leave"), "leave old membership")
    world.until(lambda: any(packet["code"] == "L" for packet in delayed_membership))
    ok(player.call("Session", "JoinHost", host.name), "rejoin the same still-running host")
    new_request = player.quiz.Session.client.request
    check(new_request != old_request, "same-host rejoin has a fresh membership nonce")
    world.until(lambda: player.view().state == "open" and host.quiz.Session.peers[player.name.lower()].request == new_request)
    ok(player.call("Session", "SubmitAnswer", correct), "new membership answers normally")
    world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending)
    rejoined_elapsed = player.answer_on(host).elapsed
    for packet in reversed(delayed_membership):
        world.deliver(packet)
    world.advance(0.3)
    equal(host.quiz.Session.peers[player.name.lower()].request, new_request, "delayed old leave cannot remove new membership")
    equal(player.answer_on(host).choiceIndex, correct, "delayed old-nonce answer cannot affect rejoined player's choice")
    equal(player.answer_on(host).elapsed, rejoined_elapsed, "old membership cannot alter new answer's timestamp")
    equal(player.view().state, "open", "same-host rejoin remains playable after stale membership packets")
    equal(host.quiz.Session.peers[player.name.lower()].request, new_request,
          "a valid but delayed old J cannot replace the newer join membership")
    host.call("Main", "Stop")

    for outage_seconds in (1, 38):
        world = World("Quizhost", "Player")
        host, player = world.nodes
        settings = host.call("Store", "GetSettings")
        settings.duration = 60
        ok(host.call("Main", "Start", settings), "fixed-round recovery host ignores an old sixty-second setting")
        ok(player.call("Session", "JoinHost", host.name), "fixed-round recovery participant")
        world.until(lambda: player.view().state == "open")
        round_ = host.quiz.Main.game.round
        round_id, correct = round_.id, round_.correctIndex
        wrong = correct % 4 + 1
        equal(round_.deadline - round_.startedAt, 15, "recovery fixture uses a real fifteen-second question")
        ok(player.call("Session", "SubmitAnswer", correct), "pre-restriction first answer establishes ACK epoch")
        world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending)
        ok(player.call("Session", "SubmitAnswer", wrong), "pre-restriction answer change advances ACK version")
        world.until(lambda: player.view().confirmedSelected == wrong and not player.view().pending)
        check(player.quiz.Session.client.ackVersion >= 2, "fixture has multiple acknowledged versions before recovery")
        old_request = player.quiz.Session.client.request
        old_player_key = host.quiz.Session.peers[player.name.lower()].playerKey
        before_pause_elapsed = player.answer_on(host).elapsed
        before_pause_points = player.answer_on(host).points
        held_old_packets, recovery_requests = [], []
        dropped_welcome = {"done": False}

        def delay_recovery_traffic(packet):
            if packet["prefix"] != QUIZ_PREFIX or packet["fields"] is None:
                return False
            fields = packet["fields"]
            if (packet["source"] is player and fields[0] == "A" and fields[5] == old_request
                    or packet["source"] is host and fields[0] == "K" and fields[5] == old_request):
                held_old_packets.append(packet)
                return True
            if packet["source"] is player and fields[0] == "J" and fields[1] != old_request:
                recovery_requests.append(fields[1])
            if packet["source"] is host and fields[0] == "W" and fields[1] != old_request and not dropped_welcome["done"]:
                dropped_welcome["done"] = True
                return True
            return False

        world.drop = delay_recovery_traffic
        ok(player.call("Session", "SubmitAnswer", correct), "optimistic old-connection answer is lost before restriction")
        world.until(lambda: any(packet["code"] == "A" for packet in held_old_packets))
        world.advance(2.1)
        host.call("Session", "SendLock", host.quiz.Session.peers[player.name.lower()])
        world.until(lambda: any(packet["code"] == "K" for packet in held_old_packets))
        equal(player.answer_on(host).choiceIndex, wrong, "lost optimistic action never reached host before restriction")
        player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
        player.test.restricted = True
        sent_at_restriction = len(player.test.addonSent)
        world.advance(outage_seconds)
        equal(len(player.test.addonSent), sent_at_restriction, "restricted player emits no retry or discovery traffic")
        if outage_seconds > 35:
            equal(host.quiz.Session.peers[player.name.lower()], None, "host actually expired the thirty-five-second peer lease")
            check(host.quiz.Main.game.round.id > round_id, "fifteen-second questions continue across a prolonged outage")
            equal(round_.deadline - round_.startedAt, 15, "question closed during outage with its fixed duration")
            equal(host.standings()[1].score, before_pause_points, "host retains the accepted penalty during an outage")
            check(-1 <= round_.answers[old_player_key].points <= -0.5,
                  "disconnection does not erase the finalized negative penalty")
            equal(round_.answers[old_player_key].elapsed, before_pause_elapsed, "outage did not retime the accepted answer")
        else:
            check(host.quiz.Session.peers[player.name.lower()] is not None, "brief restriction does not expire membership")
            equal(host.quiz.Main.game.round.id, round_id, "brief recovery exercises the same still-open question")
        player.test.restricted = False
        player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
        fresh_request = player.quiz.Session.client.request
        check(fresh_request != old_request, "restriction recovery rotates the connection nonce once")
        world.until(lambda: player.view().state == "open" and host.quiz.Session.peers[player.name.lower()] is not None,
                    seconds=15)
        recovered_round = host.quiz.Main.game.round
        equal(player.view().id, recovered_round.id, "reconnection synchronizes the currently authoritative question")
        equal(player.quiz.Session.client.request, fresh_request, "recovery W retries do not churn connection nonces")
        check(dropped_welcome["done"], "recovery welcome loss is actually exercised")
        check(len(recovery_requests) >= 2, "welcome loss forces a legitimate J retransmission")
        equal(set(recovery_requests), {fresh_request}, "all recovery retries retain the same new request nonce")
        if outage_seconds > 35:
            check(recovered_round.id > round_id, "recovery after lease expiry joins a later fixed-window question")
            equal(player.view().selected, None, "new question does not inherit an old optimistic selection")
            equal(player.answer_on(host), None, "recovery never applies a previous question's answer to a new question")
            equal(player.view().score, before_pause_points, "rejoin welcome and snapshot restore the negative session total")
            world.until(lambda: player.personal(round_.packId) is not None)
            equal(player.personal(round_.packId).score, before_pause_points,
                  "rejoining after peer expiry recovers the retained personal penalty receipt")
        else:
            equal(recovered_round.id, round_id, "brief recovery remains within the original fifteen-second round")
            world.until(lambda: player.view().confirmedSelected == wrong)
            equal(player.answer_on(host).elapsed, before_pause_elapsed, "same-question recovery preserves accepted timing")
        check(not player.view().pending, "recovery clears the old optimistic pending action")
        score_before_recovery_answer = player.view().score
        correct = recovered_round.correctIndex
        ok(player.call("Session", "SubmitAnswer", correct), "recovered participant answers before the fixed deadline")
        world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending)
        final_elapsed, final_points = player.answer_on(host).elapsed, player.answer_on(host).points
        if outage_seconds < 35:
            check(final_elapsed > before_pause_elapsed, "same-round post-recovery change receives its new accepted time")
        equal(final_points, (10 + math.floor(15 - final_elapsed + 1e-7)) / 10,
              "post-recovery timing uses the fixed fifteen-second per-second score")
        old_ack = next(packet for packet in held_old_packets if packet["code"] == "K")
        world.deliver(old_ack)
        for packet in held_old_packets:
            if packet["code"] == "A":
                world.deliver(packet)
        world.advance(0.3)
        equal(player.answer_on(host).choiceIndex, correct, "old-request A packets cannot overwrite the recovered selection")
        equal(player.answer_on(host).elapsed, final_elapsed, "old-request A retries cannot re-time the new answer")
        equal(player.view().confirmedSelected, correct, "old-request K cannot roll back recovered confirmation")
        equal(player.view().pending, False, "new lower ACK epoch confirms normally despite older version history")
        if outage_seconds > 35:
            equal(round_.answers[old_player_key].choiceIndex, wrong, "delayed answers cannot rewrite a completed old round")
        world.until(lambda: player.view().correctIndex is not None, seconds=15)
        equal(player.view().points, final_points, "fixed-window result uses the latest post-recovery answer")
        equal(player.view().correctCount, 1, "recovered membership counts as one correct player in its current round")
        equal(player.view().totalAnswers, 1, "old connection does not contribute a second answer")
        expected_total = math.floor((score_before_recovery_answer + final_points) * 10 + 0.5) / 10
        equal(host.standings()[1].score, expected_total,
              "recovered session score counts once without losing any earlier wrong-answer penalty")
        equal(player.view().score, expected_total, "signed cumulative score reaches the recovered participant")
        equal(player.personal(round_.packId).score, expected_total,
              "personal progress counts the recovered results once, including any earlier penalty")
        host.call("Main", "Stop")

    world = World("Quizhost", "Player")
    host, player = world.nodes
    settings = host.call("Store", "GetSettings")
    ok(host.call("Main", "Start", settings), "same-name replacement host starts first game")
    world.until(lambda: len(player.games()) == 1)
    first_listing = player.games()[0]
    ok(player.call("Session", "JoinHost", first_listing.hostName, first_listing.session), "join first advertised session")
    world.until(lambda: player.view().state == "open")
    first_session = player.quiz.Session.client.session
    first_request = player.quiz.Session.client.request
    lost_stops = []

    def lose_old_host_stop(packet):
        if packet["prefix"] == QUIZ_PREFIX and packet["source"] is host and packet["code"] == "X":
            lost_stops.append(packet)
            return True
        return False

    world.drop = lose_old_host_stop
    ok(host.call("Main", "Stop"), "old game ends while its stop notification is lost")
    world.until(lambda: len(lost_stops) > 0)
    equal(player.quiz.Session.client.session, first_session, "lost stop leaves participant aware only of prior session")
    ok(host.call("Main", "Start", settings), "same character starts a distinctly advertised game")
    world.until(lambda: len(player.games()) == 1 and player.games()[0].session != first_session)
    replacement = player.games()[0]
    ok(player.call("Session", "JoinHost", replacement.hostName, replacement.session),
       "clicking a newer session from the same host replaces stale membership")
    check(player.quiz.Session.client.request != first_request, "same-host different-session selection rotates membership")
    world.until(lambda: player.view().state == "open" and player.quiz.Session.client.session == replacement.session)
    equal(player.view().id, host.quiz.Main.game.round.id, "same-host replacement receives its new current question")
    world.deliver(lost_stops[0])
    world.advance(0.2)
    equal(player.quiz.Session.client.session, replacement.session, "late old X cannot terminate same-host replacement")
    equal(player.view().state, "open", "new advertised session remains playable after old stop arrives")
    host.call("Main", "Stop")

    world = World("Hostalpha", "Hostbeta", "Player", "Friend")
    alpha, beta, player, friend = world.nodes
    ok(alpha.call("Main", "Start"), "first discoverable host")
    ok(beta.call("Main", "Start"), "second discoverable host")
    world.until(lambda: len(player.games()) == 2)
    alpha_row = next(row for row in player.games() if row.hostName == alpha.name)
    beta_row = next(row for row in player.games() if row.hostName == beta.name)
    ok(player.call("Session", "JoinHost", alpha_row.hostName), "choose first game row")
    world.step()
    ok(player.call("Session", "JoinHost", beta_row.hostName), "choose another row before first welcome arrives")
    world.until(lambda: player.view().state == "open" and player.view().hostName == beta.name)
    world.until(lambda: alpha.quiz.Session.peers[player.name.lower()] is None)
    equal(player.quiz.Session.client.name, beta.name, "pending join replacement owns only the latest game")
    equal(player.quiz.Session.hostSession, None, "joining never creates a parallel host session")
    ok(player.call("Main", "Start"), "participant explicitly becomes a host")
    world.until(lambda: beta.quiz.Session.peers[player.name.lower()] is None)
    equal(player.quiz.Session.client, None, "hosting leaves the previous participant session")
    ok(friend.call("Session", "JoinHost", player.name), "friend joins player's hosted game")
    world.until(lambda: friend.view().state == "open")
    ok(player.call("Session", "JoinHost", alpha_row.hostName), "hosting player joins another discovered game")
    world.until(lambda: player.view().state == "open" and friend.view().state == "stopped")
    equal(player.quiz.Session.hostSession, None, "joining while hosting ends the local hosted session")
    equal(player.quiz.Main.game.state, "stopped", "previous hosted game stops its round progression")
    equal(player.quiz.Main.notice, None, "switching from hosting clears its stale stopped-game notice")
    equal(player.quiz.Session.client.name, alpha.name, "hosting-to-participant transition keeps one membership")
    equal(friend.quiz.Session.client, None, "former hosted participants are told their game ended")
    equal(beta.quiz.Session.peers[player.name.lower()], None, "earlier unrelated host never regains membership")
    alpha.call("Main", "Stop")
    beta.call("Main", "Stop")

    world = World("主持", "選手")
    host, player = world.nodes
    host.lua.execute("""
        local choices = { string.rep('選', 33)..'A', string.rep('選', 33)..'B',
            string.rep('選', 33)..'C', string.rep('選', 33)..'D',
            string.rep('選', 33)..'E', string.rep('選', 33)..'F' }
        math.random = function(maximum) return maximum end
        assert(OrbitQuiz:RegisterQuestionPack({id='wire-test', title='Network pack', version=1, locale='enUS',
            questions={
                {id='one', prompt=string.rep('題', 50)..'1', choices=choices, correctIndex=6,
                    explanation=string.rep('答', 50), difficulty='very_hard', era=string.rep('史', 21),
                    source='https://example.org/editorial-answer-spoiler'},
                {id='two', prompt=string.rep('題', 50)..'2', choices=choices, correctIndex=5,
                    difficulty='hard', era='Warcraft III', source='https://example.org/editorial-answer-spoiler'}
            }}))
    """)
    settings = host.call("Store", "GetSettings")
    settings.packId = "wire-test"
    ok(host.call("Main", "Start", settings), "host-only non-ASCII pack")
    dropped = {"question": False, "ack": False, "result": None}

    def drop_once(packet):
        if packet["target"].lower() != player.name.lower():
            return False
        if packet["prefix"] != QUIZ_PREFIX:
            return False
        if packet["code"] == "Q" and packet["part"] == 2 and not dropped["question"]:
            dropped["question"] = True
            return True
        if packet["code"] == "K" and not dropped["ack"]:
            dropped["ack"] = True
            return True
        if packet["code"] == "R":
            if dropped["result"] is None:
                dropped["result"] = packet["message_id"]
            return packet["message_id"] == dropped["result"]
        return False

    world.drop = drop_once
    ok(player.call("Session", "JoinHost", host.name), "join without installed host pack")
    world.until(lambda: player.view().state == "open")
    check(dropped["question"], "a mid-UTF8 question fragment was actually lost")
    equal(player.view().prompt, host.quiz.Main.game.round.prompt, "snapshot recovers whole UTF8 question")
    equal(len(player.view().choices), 6, "fragment retry recovers all six UTF8 choices")
    equal(player.view().difficulty, "very_hard", "question fragmentation preserves difficulty")
    equal(player.view().era, "史" * 21, "question fragmentation preserves the maximum multibyte era")
    equal(player.view().source, None, "host editorial reference never reaches the participant")
    check(all(b"editorial-answer-spoiler" not in packet["wire"] for packet in world.packets),
          "editorial source is never encoded into addon traffic")
    equal(len(player.quiz.GetQuestionPacks(player.quiz)), 1, "participant did not need host companion pack")
    correct = host.quiz.Main.game.round.correctIndex
    equal(correct, 6, "the sixth authored choice remains correct in the deterministic fixture")
    ok(player.call("Session", "SubmitAnswer", host.quiz.Main.game.round.choices[correct]),
       "UTF8 typed answer before acknowledgement loss")
    world.until(lambda: player.answer_on(host) is not None)
    accepted_elapsed, accepted_points = player.answer_on(host).elapsed, player.answer_on(host).points
    world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending, seconds=7)
    check(dropped["ack"], "an answer acknowledgement was actually lost")
    equal(player.answer_on(host).elapsed, accepted_elapsed, "same-action retry after lost acknowledgement never re-times")
    equal(player.answer_on(host).points, accepted_points, "same-action retry retains its original timing bonus")
    check(len([packet for packet in world.packets if packet["prefix"] == QUIZ_PREFIX and packet["code"] == "A"]) >= 2,
          "lost acknowledgement actually causes an answer retransmission")
    equal(host.lua.eval("(function() local n=0 for _ in pairs(OrbitQuiz.Main.game.round.answers) do n=n+1 end return n end)()"), 1,
          "answer retransmission records exactly one answer")
    world.until(lambda: player.view().correctIndex is not None, seconds=25)
    check(dropped["result"] is not None, "a result message was actually lost")
    equal(player.view().correctIndex, correct, "result resync recovers answer before next round")
    equal(player.view().points, player.answer_on(host).points, "result resync recovers exact host-decided score")
    check(1 <= player.view().points <= 2.5, "recovered score respects the fixed fifteen-second maximum")
    check(max(packet["total"] for packet in world.packets if packet["prefix"] == QUIZ_PREFIX and packet["code"] == "Q") >= 3,
          "large questions exercise fragmentation, not just single packets")
    check(all(len(packet["wire"]) <= 255 for packet in world.packets), "every native packet obeys byte limit")
    world.drop = lambda packet: False
    seen = {1: set()}
    previous = None
    while host.quiz.Main.game.cycle < 4:
        world.until(lambda: host.quiz.Main.game.state == "open" and host.quiz.Main.game.round.id != previous, seconds=40)
        round_ = host.quiz.Main.game.round
        previous = round_.id
        cycle = round_.cycle
        bucket = seen.setdefault(cycle, set())
        check(round_.key not in bucket, "each question appears once per cycle")
        bucket.add(round_.key)
        world.until(lambda: host.quiz.Main.game.state == "results", seconds=25)
    equal(len(seen[2]), 2, "complete second shuffled cycle")
    equal(len(seen[3]), 2, "complete third shuffled cycle")
    host.call("Main", "Stop")

    world = World("Choicehost", "Choiceplayer")
    host, player = world.nodes
    host.lua.execute("""
        math.random = function(maximum) return maximum end
        local questions = {}
        for count = 6, 4, -1 do
            local choices = {}
            for index = 1, count do choices[index] = 'Answer '..index end
            questions[#questions + 1] = {id='count'..count, prompt='Choose the last answer.', choices=choices,
                correctIndex=count, difficulty='hard', era='Warcraft III',
                source='https://example.org/private-editorial-source'}
        end
        assert(OrbitQuiz:RegisterQuestionPack({id='choice-cycle', title='Choice count cycle', questions=questions}))
    """)
    settings = host.call("Store", "GetSettings")
    settings.packId, settings.league = "choice-cycle", "Choice count regression"
    ok(host.call("Main", "Start", settings), "mixed six/five/four-choice host")
    ok(player.call("Session", "JoinHost", host.name), "mixed-choice participant")
    world.until(lambda: player.view().state == "open")
    for count in (6, 5, 4):
        world.until(lambda: player.view().state == "open" and len(player.view().choices) == count, seconds=35)
        round_ = host.quiz.Main.game.round
        equal(round_.correctIndex, count, "mixed-choice deck preserves deterministic high correct indices")
        equal(player.view().id, round_.id, "mixed-choice client and host remain on the same round")
        ok(player.call("Session", "SubmitAnswer", count), "last valid choice reaches the host")
        world.until(lambda: player.view().confirmedSelected == count and not player.view().pending)
        accepted = player.answer_on(host)
        original_time, original_points = accepted.elapsed, accepted.points
        original_request = player.quiz.Session.client.request
        player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
        player.test.restricted = True
        world.advance(0.2)
        player.test.restricted = False
        player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
        check(player.quiz.Session.client.request != original_request, "same-round resync rotates the membership nonce")
        world.until(lambda: player.view().state == "open" and player.view().confirmedSelected == count, seconds=6)
        equal(player.view().id, round_.id, "resync restores the same mixed-choice round")
        equal(len(player.view().choices), count, "resync retains the current choice count")
        equal(player.answer_on(host).elapsed, original_time, "resync cannot retime a fifth or sixth answer")
        equal(player.answer_on(host).points, original_points, "resync retains the high-index answer score")
        result = player.call("Session", "SubmitAnswer", count + 1)
        check(isinstance(result, tuple) and result[0] is False, "absent extra choice is rejected after resync")
        for index in range(count + 1, 7):
            equal(player.quiz.Widget.choices[index].IsShown(player.quiz.Widget.choices[index]), False,
                  "lower-count rounds hide old extra answer buttons")
            equal(player.quiz.Widget.choices[index].enabled, False, "old extra answer buttons stay disabled")
            equal(player.quiz.Widget.choices[index].selected, False, "old extra answer selection accents are cleared")
        world.until(lambda: player.view().correctIndex is not None, seconds=15)
        equal(player.view().correctIndex, count, "mixed-choice result reveals the correct high index")
        equal(player.view().points, original_points, "mixed-choice result retains authoritative score")
    saved = player.lua.globals().OrbitQuizDB
    loaded = player.call("Store", "Initialize", saved)
    history = loaded.personalScores.recent
    equal(len(history), 3, "all mixed-choice rounds persist exactly once")
    for index, count in enumerate((6, 5, 4), 1):
        equal(history[index].choiceCount, count, "stored history retains mixed-choice bounds")
        equal(history[index].selected, count, "sixth and fifth selections survive personal SavedVariables reload")
    equal(player.personal("choice-cycle").answers, 3, "mixed-choice pack totals survive participant-side reload")
    host.call("Main", "Stop")

    world = World("Quizhost", "Player")
    host, player = world.nodes
    ok(host.call("Main", "Start"), "restriction test host")
    ok(player.call("Session", "JoinHost", host.name), "restriction test player")
    world.until(lambda: player.view().state == "open")
    prior = player.view().id
    host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    equal(host.quiz.Main.game.state, "paused", "activating payload pauses before API updates")
    host.test.restricted = True
    sent_before = len(host.test.addonSent)
    world.advance(40)
    equal(len(host.test.addonSent), sent_before, "restricted host sends no addon traffic")
    equal(host.quiz.Main.game.completed, 0, "restricted unfinished question never scores")
    host.test.restricted = False
    host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    world.until(lambda: player.view().state == "open" and player.view().id != prior, seconds=20)
    equal(player.view().id, host.quiz.Main.game.round.id, "host resumes connected widget after prolonged pause")

    player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    player.test.restricted = True
    player_sent_before = len(player.test.addonSent)
    world.advance(42)
    equal(len(player.test.addonSent), player_sent_before, "restricted participant sends no addon traffic")
    equal(host.quiz.Session.peers[player.name.lower()], None, "host expires disconnected participant lease")
    player.test.restricted = False
    player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    world.until(lambda: player.view().state == "open" and host.quiz.Session.peers[player.name.lower()] is not None, seconds=25)
    equal(player.view().id, host.quiz.Main.game.round.id, "participant rejoins after its lease expires")

    ok(host.call("Main", "Pause", None, False), "manual host pause")
    world.until(lambda: player.view().state == "paused")
    host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    world.advance(2)
    equal(host.quiz.Main.game.state, "paused", "manual pause is not automatically resumed")
    host.call("Main", "Resume")
    world.until(lambda: player.view().state == "open")
    ok(player.call("Main", "Start"), "participant switches explicitly to hosting")
    world.until(lambda: host.quiz.Session.peers[player.name.lower()] is None)
    equal(player.view().role, "host", "role transition leaves former host")
    host.call("Main", "Stop")
    player.call("Main", "Stop")

    world = World("Quizhost", "Player")
    host, player = world.nodes
    settings = host.call("Store", "GetSettings")
    settings.bridgeChat = True
    settings.channel = "CHANNEL"
    settings.customChannel = "RetiredVisibleQuiz"
    settings.channelPassword = "RetiredPassword"
    settings.answerMode = "PUBLIC"
    ok(host.call("Main", "Start", settings), "old enabled chat setup cannot prevent automatic hosting")
    equal(host.quiz.Main.game.state, "open", "obsolete chat setup cannot create a manual preparation state")
    for node in world.nodes:
        equal(node.quiz.Chat, None, "visible chat transport is not loaded on either client")
        equal(node.quiz.Main.PublishChat, None, "neither client exposes a manual publish flow")
    ok(player.call("Session", "JoinHost", host.name), "participant joins automatic widget-only play")
    world.until(lambda: player.view().state == "open")
    round_ = host.quiz.Main.game.round
    equal(round_.deadline - round_.startedAt, 15, "obsolete chat setup retains the automatic fifteen-second clock")
    wrong = round_.correctIndex % 4 + 1
    for text in (chr(64 + wrong), f"!{int(round_.id)} {chr(64 + wrong)}", round_.choices[wrong]):
        host.test.Incoming(text, player.name, player.test.hostGUID)
    equal(player.answer_on(host), None, "native custom-channel replies cannot create an answer")
    ok(player.call("Session", "SubmitAnswer", wrong), "first answer comes only from the widget")
    world.until(lambda: player.view().confirmedSelected == wrong and not player.view().pending)
    old_version = player.quiz.Session.client.ackVersion
    accepted_elapsed = player.answer_on(host).elapsed
    host.test.Incoming(chr(64 + round_.correctIndex), player.name, player.test.hostGUID)
    world.advance(0.3)
    equal(player.answer_on(host).choiceIndex, wrong, "chat cannot replace a confirmed widget choice")
    equal(player.answer_on(host).elapsed, accepted_elapsed, "chat cannot retime a confirmed widget answer")
    equal(player.quiz.Session.client.ackVersion, old_version, "chat cannot advance authoritative answer versions")
    ok(player.call("Session", "SubmitAnswer", round_.correctIndex), "widget selection remains adjustable")
    equal(player.view().pending, True, "a changed widget answer waits for acknowledgement")
    world.until(lambda: player.view().confirmedSelected == round_.correctIndex and not player.view().pending)
    equal(player.view().selected, round_.correctIndex, "latest widget answer becomes authoritative")
    check(player.quiz.Session.client.ackVersion > old_version, "acknowledged widget changes advance server version")
    selected_points = player.answer_on(host).points
    world.until(lambda: player.view().correctIndex is not None, seconds=25)
    equal(player.view().points, selected_points, "results retain the latest widget timing and correctness")
    equal(player.view().totalAnswers, 1, "ignored chat cannot duplicate player identity")
    prior_id = round_.id
    world.until(lambda: player.view().id != prior_id and player.view().state == "open")
    equal(player.view().id, host.quiz.Main.game.round.id, "the next shared question starts without publication")
    for node in world.nodes:
        equal(len(node.test.sent), 0, "old chat setup and native replies never trigger visible output")
    host.call("Main", "Stop")

    for route in ("CHANNEL", "GUILD", "PARTY", "RAID", "INSTANCE_CHAT"):
        world = World("Quizhost", "Player")
        host, player = world.nodes
        for node in world.nodes:
            node.test.guild = route == "GUILD"
            node.test.group = route == "PARTY"
            node.test.raid = route == "RAID"
            node.test.instance = route == "INSTANCE_CHAT"
            node.test.joinAccepted = route == "CHANNEL"
        host.test.lobbyId, player.test.lobbyId = 17, 29
        ok(host.call("Main", "Start"), f"{route} discovery host")
        world.until(lambda: len(player.games()) == 1)
        row = player.games()[0]
        equal(row.hostName, host.name, f"{route} host identity comes from native sender")
        equal(row.session, host.quiz.Session.hostSession, f"{route} listing identifies current host session")
        check(any(packet["prefix"] == DISCOVERY_PREFIX and packet["channel"] == route
                  and packet["source"] is host and packet["target"] == player.name for packet in world.packets),
              f"{route} is actually used for automatic discovery")
        if route == "CHANNEL":
            equal(player.quiz.Discovery.lobbyConfirmed, True, "lobby self-echo confirms native channel availability")
            check(host.test.lobbyId != player.test.lobbyId, "channel fixture uses recipient-specific local IDs")
        ok(player.call("Session", "JoinHost", row.hostName), f"{route} row joins without typed host name")
        world.until(lambda: player.view().state == "open")
        equal(player.view().hostName, row.hostName, f"{route} discovery selection reaches the proper quiz host")
        check(all(packet["channel"] == "WHISPER" for packet in world.packets if packet["prefix"] == QUIZ_PREFIX),
              f"{route} broadcasts carry discovery only, never quiz answers")
        for node in world.nodes:
            equal(len(node.test.sent), 0, f"{route} discovery and play never emit visible chat")
            equal(len(node.test.errors), 0, f"{route} simulated native delivery has no Lua errors")
        host.call("Main", "Stop")
        world.until(lambda: player.view().state == "stopped")
        world.until(lambda: len(player.games()) == 0)

    world = World("Realhost", "Player")
    host, player = world.nodes
    host.test.lobbyJoined, player.test.lobbyJoined = True, True
    host.test.lobbyId, player.test.lobbyId = 17, 29
    advertisement = f"6|A|123.456|{player.name}|Native identity|open|1".encode("utf-8").hex()
    player.receive(DISCOVERY_PREFIX, advertisement, "CHANNEL", host.name, None, host.test.lobbyId, LOBBY_NAME)
    equal(len(player.games()), 0, "sender's channel number cannot substitute for recipient-local channel identity")
    player.receive(DISCOVERY_PREFIX, advertisement, "CHANNEL", host.name, None, player.test.lobbyId, "Trade")
    equal(len(player.games()), 0, "wrong native channel name cannot inject a discovered game")
    player.receive(DISCOVERY_PREFIX, advertisement, "CHANNEL", host.name, None, player.test.lobbyId, LOBBY_NAME)
    equal(len(player.games()), 1, "correct native lobby metadata permits discovery")
    equal(player.games()[0].hostName, host.name, "payload text resembling a player name cannot forge host identity")
    equal(player.games()[0].packName, player.name, "display text remains metadata, never a routing address")
    equal(player.view().role, "idle", "discovering another host never auto-joins or changes the active session")
    equal(player.quiz.Session.client, None, "a discovery packet alone never creates game membership")

    world = World("Personalalpha", "Personalbeta", "Personalplayer")
    alpha, beta, player = world.nodes
    register_pack(alpha, "shared-lore", "Shared lore", 1)
    register_pack(beta, "shared-lore", "Shared lore revised", 2)
    first, first_points = join_and_answer(world, alpha, player, "shared-lore")
    first_session = player.quiz.Session.client.session
    equal(player.personal("shared-lore").score, first_points, "first host credits the shared pack")
    equal(player.personal("shared-lore").correct, 1, "first host credits exactly one correct answer")
    equal(player.personal("shared-lore").versions[1], 1, "first pack revision is retained")
    ok(alpha.call("Main", "Stop"), "end first host's session")
    world.until(lambda: player.view().state == "stopped")
    setup = beta.call("Store", "GetSettings")
    setup.packId = "shared-lore"
    ok(beta.call("Main", "Start", setup), "another host starts the same stable pack ID")
    stats = player.quiz.Store.db.personalScores.packs["shared-lore"].scoringVersions[2]
    original_score = stats.score
    stats.score = 999999
    ok(player.call("Session", "JoinHost", beta.name), "edited local lifetime score cannot block joining")
    world.until(lambda: player.view().state == "open" and player.view().hostName == beta.name)
    equal(player.personal("shared-lore").score, 999999, "fixture genuinely edits the participant's local statistics")
    equal(player.view().score, 0, "edited lifetime totals never seed the host-controlled session score")
    equal(len(beta.standings()), 0, "joining cannot inject a fabricated player into the host leaderboard")
    joins = [packet for packet in world.packets if packet["source"] is player
             and packet["target"] == beta.name and packet["code"] == "J"]
    check(joins and all(len(packet["fields"]) == 2 for packet in joins),
          "join packets contain only the action and membership nonce, never claimed totals")
    stats.score = original_score
    second = beta.quiz.Main.game.round
    equal(second.id, first.id, "different hosts may reuse numeric round IDs without sharing receipt identity")
    wrong = second.correctIndex % 4 + 1
    ok(player.call("Session", "SubmitAnswer", wrong), "a wrong answer at the second host is timed normally")
    world.until(lambda: player.view().confirmedSelected == wrong and not player.view().pending)
    second_points = player.answer_on(beta).points
    world.until(lambda: player.view().correctIndex is not None)
    shared_score = round(first_points + second_points, 1)
    equal(player.personal("shared-lore").score, shared_score, "same pack progress carries across independent hosts")
    equal(player.personal("shared-lore").answers, 2, "cross-host play adds rather than replaces the first answer")
    equal(player.personal("shared-lore").incorrect, 1, "negative scoring remains in personal progress")
    equal(player.personal("shared-lore").title, "Shared lore revised", "newer pack metadata updates its display title")
    equal(player.personal("shared-lore").versions[1], 1, "old pack revision statistics are retained")
    equal(player.personal("shared-lore").versions[2], 1, "new revision continues under the same pack ID")
    equal(beta.standings()[1].score, second_points, "second host board contains only its own game's result")
    equal(alpha.standings()[1].score, first_points, "the original host's stopped session board is unchanged")
    equal(player.quiz.Store.db.personalScores.recent[1].session, first_session,
          "receipts preserve the first host/session provenance")
    equal(player.quiz.Store.db.personalScores.recent[2].host, beta.name.lower(),
          "second result provenance comes from its native sender")
    beta.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")

    register_pack(beta, "separate-lore", "AAA separate lore")
    separate, separate_points = join_and_answer(world, beta, player, "separate-lore")
    equal(player.personal("shared-lore").score, shared_score, "a different pack cannot alter shared-pack progress")
    equal(player.personal("separate-lore").score, separate_points, "a distinct pack has its own lifetime score")
    beta.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")

    register_pack(beta, "mixed-lore", "AAB mixed lore")
    beta.lua.execute("math.random = function(maximum) return maximum end")
    setup.packId = "all"
    ok(beta.call("Main", "Start", setup), "All packs starts the real combined question deck")
    ok(player.call("Session", "JoinHost", beta.name), "participant joins combined-pack play")
    for expected_pack in ("separate-lore", "mixed-lore"):
        world.until(lambda: player.view().state == "open" and player.view().packId == expected_pack, seconds=30)
        round_ = beta.quiz.Main.game.round
        equal(round_.packId, expected_pack, "combined deck retains the question's actual pack provenance")
        equal(player.view().packTitle, round_.packTitle, "combined Q carries its actual pack's title")
        equal(player.view().packVersion, round_.packVersion, "combined Q carries its actual pack's version")
        ok(player.call("Session", "SubmitAnswer", round_.correctIndex), "combined-pack question accepts a real answer")
        world.until(lambda: player.view().confirmedSelected == round_.correctIndex and not player.view().pending)
        points = player.answer_on(beta).points
        world.until(lambda: player.view().correctIndex is not None)
        if expected_pack == "separate-lore":
            equal(player.personal(expected_pack).score, round(separate_points + points, 1),
                  "All packs credits the pre-existing actual pack rather than an artificial all bucket")
        else:
            equal(player.personal(expected_pack).score, points, "a second combined-deck pack gets separate progress")
    equal(player.personal("all"), None, "All packs never becomes a lifetime scoring identity")
    equal(player.personal("shared-lore").score, shared_score, "unplayed packs are unchanged by the combined deck")
    equal(len(player.quiz.GetQuestionPacks(player.quiz)), 1, "remote progress does not require the companion packs installed")
    beta.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")
    saved = saved_copy(player.lua.globals().OrbitQuizDB)
    alt = Node("Personalalt", saved=saved)
    equal(alt.personal("shared-lore").score, shared_score, "another character on the same saved account retains pack totals")
    equal(alt.personal("shared-lore").answers, 2, "account-wide reload retains both hosts' answers")
    equal(alt.personal("separate-lore").answers, 2, "standalone and All-pack play survive a fresh Lua runtime")
    equal(alt.personal("mixed-lore").answers, 1, "fresh runtime preserves other pack identities independently")
    equal(alt.view().role, "idle", "personal persistence never restores an active hosted session")
    receipt = alt.quiz.Store.db.personalScores.recent[1]
    ok(alt.call("PersonalScores", "RecordResult", receipt), "a recorded real wire receipt remains recognizable after reload")
    equal(alt.personal("shared-lore").answers, 2, "replayed persisted host/session/round cannot award points twice")
    equal(len(alt.test.errors), 0, "fresh account-character load has no Lua errors")

    world = World("Receipthost", "Receiptplayer")
    host, player = world.nodes
    register_pack(host, "receipt-lore", "Receipt lore")
    setup = host.call("Store", "GetSettings")
    setup.packId = "receipt-lore"
    ok(host.call("Main", "Start", setup), "receipt retry host starts")
    ok(player.call("Session", "JoinHost", host.name), "receipt retry participant joins")
    world.until(lambda: player.view().state == "open")
    first = host.quiz.Main.game.round
    ok(player.call("Session", "SubmitAnswer", first.correctIndex), "first retry fixture answers correctly")
    world.until(lambda: player.view().confirmedSelected == first.correctIndex)
    first_points = player.answer_on(host).points
    held_results = []

    def hold_first_result(packet):
        if (packet["source"] is host and packet["prefix"] == QUIZ_PREFIX and packet["code"] == "R"
                and packet["fields"] is not None and packet["fields"][2] == str(int(first.id))):
            held_results.append(packet)
            return True
        return False

    world.drop = hold_first_result
    world.until(lambda: player.view().state == "open" and player.view().id != first.id, seconds=25)
    check(held_results, "the first finalized receipt was genuinely dropped across question advancement")
    equal(player.personal("receipt-lore"), None, "a missing receipt cannot fabricate personal points from a heartbeat")
    second = host.quiz.Main.game.round
    wrong = second.correctIndex % 4 + 1
    ok(player.call("Session", "SubmitAnswer", wrong), "second question is answered while the old result is missing")
    world.until(lambda: player.view().confirmedSelected == wrong)
    second_points = player.answer_on(host).points
    world.until(lambda: player.view().correctIndex is not None)
    equal(player.personal("receipt-lore").score, second_points, "the later result can arrive before the earlier result")
    current_id, current_points, current_score = player.view().id, player.view().points, player.view().score
    world.deliver(held_results[0])
    equal(player.personal("receipt-lore").score, round(first_points + second_points, 1),
          "late earlier receipt fills the missing personal score without losing the newer answer")
    equal(player.view().id, current_id, "late result cannot rewind the question widget")
    equal(player.view().points, current_points, "late result cannot animate the earlier question's points")
    equal(player.view().score, current_score, "late result cannot rewind the current host-session total")
    revision = player.quiz.PersonalScores.revision
    world.deliver(held_results[-1])
    equal(player.quiz.PersonalScores.revision, revision, "another transport copy of the old receipt is idempotent")
    equal(player.personal("receipt-lore").answers, 2, "out-of-order delivery still yields exactly two finalized answers")
    world.drop = lambda packet: False
    world.until(lambda: host.quiz.Session.resultCount == 0)
    check(any(packet["source"] is player and packet["code"] == "F" for packet in world.packets),
          "participant sends a receipt acknowledgement after successful local persistence")
    equal(host.standings()[1].score, current_score, "receipt retry and acknowledgement cannot change host scores")
    host.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")

    world = World("Stophost", "Stopplayer")
    host, player = world.nodes
    register_pack(host, "stop-lore", "Stop receipt lore")
    setup = host.call("Store", "GetSettings")
    setup.packId = "stop-lore"
    ok(host.call("Main", "Start", setup), "host starts the final-receipt shutdown fixture")
    ok(player.call("Session", "JoinHost", host.name), "shutdown fixture participant joins")
    world.until(lambda: player.view().state == "open")
    final_round = host.quiz.Main.game.round
    ok(player.call("Session", "SubmitAnswer", final_round.correctIndex), "shutdown fixture has a confirmed answer")
    world.until(lambda: player.view().confirmedSelected == final_round.correctIndex)
    final_points = player.answer_on(host).points
    host.test.now = final_round.deadline
    host.call("Main", "CloseQuestion", host.test.now)
    equal(player.personal("stop-lore"), None, "final receipt is still queued when the host stops")
    ok(host.call("Main", "Stop"), "stopping immediately after close preserves the queued final receipt")
    world.until(lambda: player.view().state == "stopped")
    equal(player.personal("stop-lore").score, final_points, "participant persists the final answer before the end notification")
    equal(player.personal("stop-lore").answers, 1, "final receipt is not double-counted by shutdown retransmission")
    codes = [packet["code"] for packet in world.packets if packet["source"] is host and packet["prefix"] == QUIZ_PREFIX]
    check(codes.index("R") < codes.index("X"), "host flushes the completed receipt before its session end packet")

    world = World("Fullhost", "Fullplayer")
    host, player = world.nodes
    register_pack(host, "full-lore", "Capacity recovery lore")
    setup = host.call("Store", "GetSettings")
    setup.packId = "full-lore"
    ok(host.call("Main", "Start", setup), "capacity-error fixture host starts")
    ok(player.call("Session", "JoinHost", host.name), "capacity-error fixture participant joins")
    world.until(lambda: player.view().state == "open")
    closed = host.quiz.Main.game.round
    ok(player.call("Session", "SubmitAnswer", closed.correctIndex), "remote answer is accepted before local host storage fills")
    world.until(lambda: player.view().confirmedSelected == closed.correctIndex)
    earned = player.answer_on(host).points
    save_result = host.quiz.PersonalScores.RecordResult
    host.lua.execute("""
        Test.personalSaveAttempts = 0
        OrbitQuiz.PersonalScores.RecordResult = function()
            Test.personalSaveAttempts = Test.personalSaveAttempts + 1
            return false, 'personal_history_full'
        end
    """)
    capacity_receipts = []

    def drop_capacity_receipt(packet):
        if packet["source"] is host and packet["prefix"] == QUIZ_PREFIX and packet["code"] == "R":
            capacity_receipts.append(packet)
            return True
        return False

    world.drop = drop_capacity_receipt
    world.until(lambda: host.quiz.Main.game.state == "paused", seconds=20)
    equal(host.test.personalSaveAttempts, 1, "full local storage attempts to save the finalized round only once")
    equal(host.quiz.Main.notice, host.quiz.L.errors.personal_history_full, "capacity failure has a localized actionable notice")
    equal(host.quiz.Main.autoPaused, False, "capacity failure pauses manually instead of entering automatic restriction recovery")
    equal(host.quiz.Main.nextAutoAt, None, "capacity pause cancels automatic question advancement")
    equal(host.quiz.Main.game.completed, 1, "the round remains finalized despite the host's local-save failure")
    equal(host.quiz.Session.resultCount, 1, "the remote completed receipt is retained despite local-save failure")
    check(host.quiz.Main.ticker is not None and host.quiz.Main.ticker.active,
          "capacity pause keeps the communication/retry ticker alive")
    equal(host.personal("full-lore"), None, "failed local storage cannot invent saved host progress")
    world.until(lambda: player.view().state == "paused")
    world.advance(7)
    equal(host.test.personalSaveAttempts, 1, "paused ticks never retry and flood the failed local save")
    equal(host.quiz.Main.game.completed, 1, "paused ticks do not finalize the same question again")
    equal(len(host.test.errors), 0, "storage capacity handling never floods the WoW error handler")
    check(len(capacity_receipts) >= 2, "remote receipt retransmission continues while the host is paused")
    world.drop = lambda packet: False
    world.until(lambda: player.personal("full-lore") is not None and host.quiz.Session.resultCount == 0)
    equal(player.personal("full-lore").score, earned, "remote participant gets its earned points despite host storage capacity")
    equal(player.personal("full-lore").answers, 1, "remote retry delivery credits that finalized answer exactly once")
    equal(player.view().state, "paused", "late remote receipt cannot undo the manual storage-error pause")
    equal(host.standings()[1].score, earned, "host session leaderboard retains the authoritative remote result")
    host.quiz.PersonalScores.RecordResult = save_result
    ok(host.call("Main", "Resume"), "resolved storage failure requires an explicit host resume")
    world.until(lambda: player.view().state == "open" and player.view().id != closed.id)
    equal(player.personal("full-lore").answers, 1, "manual resume cannot re-credit the previous result")
    equal(len(player.test.errors), 0, "remote storage-error recovery has no Lua errors")
    host.call("Main", "Stop")

    world = World("Winnerhost", "Winnerplayer", "Winnerfriend")
    host, player, friend = world.nodes
    register_pack(host, "winner-lore", "Winner lore")
    setup = host.call("Store", "GetSettings")
    setup.packId = "winner-lore"
    ok(host.call("Main", "Start", setup), "final-selection winner fixture starts")
    for node in (player, friend):
        ok(node.call("Session", "JoinHost", host.name), "winner fixture joins a real host session")
    world.until(lambda: player.view().state == friend.view().state == "open")
    round_ = host.quiz.Main.game.round
    correct, wrong = round_.correctIndex, round_.correctIndex % 4 + 1
    ok(player.call("Session", "SubmitAnswer", correct), "player makes the earliest provisional correct answer")
    world.until(lambda: player.view().confirmedSelected == correct)
    first_elapsed = player.answer_on(host).elapsed
    world.advance(0.6)
    ok(host.call("Session", "SubmitAnswer", correct), "host answers correctly after the player's initial choice")
    host_elapsed = round_.answers[host.test.hostGUID].elapsed
    world.advance(0.3)
    ok(friend.call("Session", "SubmitAnswer", correct), "another player supplies a slower correct answer")
    world.until(lambda: friend.view().confirmedSelected == correct)
    ok(player.call("Session", "SubmitAnswer", wrong), "original fastest answer changes to an incorrect selection")
    world.until(lambda: player.view().confirmedSelected == wrong)
    world.advance(0.3)
    ok(player.call("Session", "SubmitAnswer", correct), "changing back to correct uses the later final-selection time")
    world.until(lambda: player.view().confirmedSelected == correct and not player.view().pending)
    check(first_elapsed < host_elapsed < player.answer_on(host).elapsed,
          "fixture distinguishes the earliest provisional choice from the fastest correct final answer")
    for node in world.nodes:
        equal(node.view().fastestName, None, "no winner name is revealed before the host closes the question")
        equal(node.quiz.Widget.winnerAnimation.playCalls, 0, "open questions cannot show a winner popup")
    world.until(lambda: all(node.view().correctIndex is not None for node in world.nodes), seconds=20)
    for node in world.nodes:
        equal(node.view().fastestName, host.name, "host and participants agree on the fastest correct final selection")
        equal(node.view().fastestElapsed, host_elapsed, "winner elapsed time round-trips without display rounding")
        node.call("Widget", "Refresh")
        equal(node.quiz.Widget.winnerAnimation.playCalls, 1, "each current result shows exactly one winner popup")
        check(host.name in node.quiz.Widget.winnerText.GetText(node.quiz.Widget.winnerText),
              "the popup identifies the canonical host-authoritative winner")
        for receipt in node.quiz.Store.db.personalScores.recent.values():
            equal(receipt.fastestName, None, "winner names do not enter saved personal receipts")
            equal(receipt.fastestElapsed, None, "winner timing is presentation data, not personal accounting")
    player_results = captured_results(world.packets, host, player)
    check(player_results, "winner fixture captured a complete encoded result")
    result_fields, _ = player_results[-1]
    equal(len(result_fields), 19, "protocol six results append exactly the two winner fields")
    equal(result_fields[17], host.name, "the winner name is carried only in the result metadata")
    equal(float(result_fields[18]), host_elapsed, "wire winner time preserves the authoritative double")
    popup_plays = player.quiz.Widget.winnerAnimation.playCalls
    popup_stops = player.quiz.Widget.winnerAnimation.stopCalls
    personal_revision = player.quiz.PersonalScores.revision
    ok(host.call("Comms", "Send", player.name, host.lua.table_from(result_fields)),
       "host retransmits the winner result using a fresh transport message ID")
    world.advance(0.4)
    equal(player.quiz.PersonalScores.revision, personal_revision, "fresh-envelope duplicate never awards personal points again")
    equal(player.view().suppressWinnerPopup, False, "duplicate receipt does not change an already displayed popup's policy")
    equal(player.quiz.Widget.winnerAnimation.playCalls, popup_plays, "duplicate receipt cannot restart the active winner popup")
    equal(player.quiz.Widget.winnerAnimation.stopCalls, popup_stops,
          "duplicate receipt cannot abruptly stop the active winner popup")
    reloaded = Node(player.test.hostName, saved=saved_copy(player.lua.globals().OrbitQuizDB))
    reloaded.test.now = player.test.now
    reloaded.quiz.Comms.epoch = None
    ok(reloaded.call("Comms", "Initialize", reloaded.quiz.Comms.onMessage, reloaded.quiz.Comms.onError),
       "reloaded fixture initializes its transport against the current native clock")
    world.nodes[world.nodes.index(player)] = reloaded
    world.by_name[reloaded.name.lower()] = reloaded
    ok(reloaded.call("Session", "JoinHost", host.name), "reloaded player rejoins the still-revealed hosted question")
    world.until(lambda: reloaded.view().id == round_.id and reloaded.view().correctIndex is not None)
    equal(reloaded.view().fastestName, host.name, "reconnect restores the canonical winner metadata")
    equal(reloaded.view().suppressWinnerPopup, True, "durably saved result suppresses a popup in a fresh Lua runtime")
    reloaded.call("Widget", "Refresh")
    equal(reloaded.quiz.Widget.winnerAnimation.playCalls, 0, "reload and reconnect cannot replay the previous winner")
    equal(reloaded.personal("winner-lore").answers, 1, "winner reconnect remains idempotent for personal scores")
    host.call("Main", "Stop")

    world = World("Leaverhost", "Earlyplayer", "Remainingplayer")
    host, early, remaining = world.nodes
    register_pack(host, "leaver-lore", "Leaver lore")
    setup = host.call("Store", "GetSettings")
    setup.packId = "leaver-lore"
    ok(host.call("Main", "Start", setup), "accepted-leaver winner fixture starts")
    for node in (early, remaining):
        ok(node.call("Session", "JoinHost", host.name), "accepted-leaver fixture joins")
    world.until(lambda: early.view().state == remaining.view().state == "open")
    round_ = host.quiz.Main.game.round
    ok(early.call("Session", "SubmitAnswer", round_.correctIndex), "early player submits an accepted correct answer")
    world.until(lambda: early.view().confirmedSelected == round_.correctIndex)
    accepted_elapsed = early.answer_on(host).elapsed
    world.advance(0.7)
    ok(remaining.call("Session", "SubmitAnswer", round_.correctIndex), "remaining player answers correctly but later")
    world.until(lambda: remaining.view().confirmedSelected == round_.correctIndex)
    ok(early.call("Session", "Leave"), "fastest player leaves after the host accepted its final answer")
    world.until(lambda: host.quiz.Session.peers[early.name.lower()] is None)
    world.until(lambda: remaining.view().correctIndex is not None, seconds=20)
    for node in (host, remaining):
        equal(node.view().fastestName, early.name, "accepted leaver remains eligible while another round-ready player stays")
        equal(node.view().fastestElapsed, accepted_elapsed, "leaving cannot erase or retime the accepted winner")
    equal(host.quiz.Main.game.lastResult.correctCount, 2, "winner eligibility and host scoring retain both accepted answers")
    host.call("Main", "Stop")

    for eligibility in ("solo", "all_left", "no_correct"):
        world = World("Solohost", "Soloplayer")
        host, player = world.nodes
        register_pack(host, "solo-lore", "Solo lore")
        setup = host.call("Store", "GetSettings")
        setup.packId = "solo-lore"
        ok(host.call("Main", "Start", setup), "winner suppression fixture starts")
        if eligibility != "solo":
            ok(player.call("Session", "JoinHost", host.name), "winner suppression fixture has a remote member")
            world.until(lambda: player.view().state == "open")
        round_ = host.quiz.Main.game.round
        if eligibility == "all_left":
            ok(player.call("Session", "SubmitAnswer", round_.correctIndex), "departing member has an accepted correct answer")
            world.until(lambda: player.view().confirmedSelected == round_.correctIndex)
            ok(player.call("Session", "Leave"), "last remote participant leaves before close")
            world.until(lambda: host.quiz.Session.peers[player.name.lower()] is None)
        else:
            choice = round_.correctIndex if eligibility == "solo" else round_.correctIndex % 4 + 1
            ok(host.call("Session", "SubmitAnswer", choice), "host submits the suppression fixture answer")
            if eligibility == "no_correct":
                ok(player.call("Session", "SubmitAnswer", choice), "remote participant also answers incorrectly")
                world.until(lambda: player.view().confirmedSelected == choice)
        world.until(lambda: host.view().state == "results", seconds=20)
        observed = (host, player) if eligibility == "no_correct" else (host,)
        if eligibility == "no_correct":
            world.until(lambda: player.view().correctIndex is not None)
        for node in observed:
            equal(node.view().fastestName, None, eligibility + " cannot announce a fastest correct player")
            equal(node.view().fastestElapsed, None, eligibility + " cannot expose a stray winner time")
            node.call("Widget", "Refresh")
            equal(node.quiz.Widget.winnerAnimation.playCalls, 0, eligibility + " suppresses the popup entirely")
        equal(host.quiz.Main.game.lastResult.correctCount, 0 if eligibility == "no_correct" else 1,
              "announcement suppression never changes the independently scored outcome")
        host.call("Main", "Stop")

    world = World("Latehost", "Lateplayer")
    host, player = world.nodes
    register_pack(host, "late-winner", "Late winner")
    setup = host.call("Store", "GetSettings")
    setup.packId = "late-winner"
    ok(host.call("Main", "Start", setup), "late winner receipt fixture starts")
    ok(player.call("Session", "JoinHost", host.name), "late winner receipt participant joins")
    world.until(lambda: player.view().state == "open")
    first = host.quiz.Main.game.round
    ok(player.call("Session", "SubmitAnswer", first.correctIndex), "delayed winner has an accepted correct answer")
    world.until(lambda: player.view().confirmedSelected == first.correctIndex)
    held = []

    def hold_winner_result(packet):
        if packet["source"] is host and packet["target"] == player.name and packet["code"] == "R":
            held.append(packet)
            return True
        return False

    world.drop = hold_winner_result
    world.until(lambda: player.view().state == "open" and player.view().id != first.id, seconds=25)
    late_results = captured_results(held, host, player)
    check(late_results, "late-result fixture withheld a complete host-generated winner receipt")
    equal(late_results[0][0][17], player.name, "the delayed receipt really contains winner metadata")
    current_id = player.view().id
    popup_plays = player.quiz.Widget.winnerAnimation.playCalls
    world.drop = lambda packet: False
    for packet in late_results[0][1]:
        world.deliver(packet)
    player.call("Widget", "Refresh")
    equal(player.personal("late-winner").answers, 1, "late winner result still persists the player's valid answer")
    equal(player.view().id, current_id, "late winner result cannot rewind the current question")
    equal(player.view().fastestName, None, "late winner result cannot populate a newer question's winner")
    equal(player.quiz.Widget.winnerAnimation.playCalls, popup_plays, "late winner receipt cannot start stale popup feedback")
    world.until(lambda: host.quiz.Session.resultCount == 0)
    host.call("Main", "Stop")

    world = World("Orderhost", "Readyplayer", "Newplayer")
    host, ready, newcomer = world.nodes
    register_pack(host, "winner-order", "Winner order")
    setup = host.call("Store", "GetSettings")
    setup.packId = "winner-order"
    ok(host.call("Main", "Start", setup), "result-before-question winner fixture starts")
    ok(ready.call("Session", "JoinHost", host.name), "winner order fixture has a real round-ready participant")
    world.until(lambda: ready.view().state == "open")
    round_ = host.quiz.Main.game.round
    ok(ready.call("Session", "SubmitAnswer", round_.correctIndex), "ready player supplies the real winner")
    world.until(lambda: ready.view().correctIndex is not None, seconds=20)
    held_questions = []

    def hold_newcomer_question(packet):
        if packet["source"] is host and packet["target"] == newcomer.name and packet["code"] == "Q":
            held_questions.append(packet)
            return True
        return False

    world.drop = hold_newcomer_question
    ok(newcomer.call("Session", "JoinHost", host.name), "late participant joins during the result intermission")
    world.until(lambda: newcomer.personal("winner-order") is not None)
    equal(newcomer.view().id, None, "self-contained result arrived before the withheld question")
    equal(newcomer.view().fastestName, None, "an unbound winner result cannot render without its question")
    equal(newcomer.quiz.Widget.winnerAnimation.playCalls, 0, "result-before-question does not animate an unknown question")
    check(held_questions, "native question messages were actually withheld")
    first_message = held_questions[0]["message_id"]
    world.drop = lambda packet: False
    for packet in held_questions:
        if packet["message_id"] == first_message:
            world.deliver(packet)
    newcomer.call("Widget", "Refresh")
    equal(newcomer.view().id, round_.id, "the delayed question binds the cached self-contained result")
    equal(newcomer.view().fastestName, ready.name, "cached receipt restores the correct winner once its question is known")
    equal(newcomer.view().suppressWinnerPopup, True, "binding an already persisted result suppresses late feedback")
    equal(newcomer.quiz.Widget.winnerAnimation.playCalls, 0, "late question binding cannot replay the cached winner popup")
    equal(newcomer.personal("winner-order").rounds, 1, "result-before-question receipt is persisted only once")
    host.call("Main", "Stop")

    world = World("Quizhost", *["Player" + chr(65 + index) for index in range(16)])
    host = world.nodes[0]
    host.lua.execute("""
        local choices = {}
        for index = 1, 6 do choices[index] = string.rep('x', 99)..index end
        assert(OrbitQuiz:RegisterQuestionPack({id='capacity-six', title='Maximum choice capacity', questions={
            {id='capacity', prompt=string.rep('q', 160), choices=choices, correctIndex=6,
                difficulty='very_hard', era=string.rep('e', 64), source='https://example.org/private-source'}
        }}))
    """)
    settings = host.call("Store", "GetSettings")
    settings.packId = "capacity-six"
    ok(host.call("Main", "Start", settings), "full capacity host")
    for node in world.nodes[1:]:
        ok(node.call("Session", "JoinHost", host.name), "full capacity join")
    world.until(lambda: all(node.view().state == "open" for node in world.nodes[1:]), seconds=40)
    first_id = host.quiz.Main.game.round.id
    world.until(lambda: host.quiz.Main.game.round.id != first_id and host.quiz.Main.game.state == "open", seconds=50)
    check(all(peer.readyId == host.quiz.Main.game.round.id for peer in host.quiz.Session.peers.values()),
          "full-size steady-state rounds open after all sixteen question readiness acknowledgements")
    world.until(lambda: all(node.view().state == "open" and node.view().id == host.quiz.Main.game.round.id
                            for node in world.nodes[1:]), seconds=8)
    equal(host.lua.eval("(function() local n=0 for _ in pairs(OrbitQuiz.Session.peers) do n=n+1 end return n end)()"), 16,
          "host retains all sixteen ready participants")
    for node in world.nodes[1:]:
        equal(len(node.view().choices), 6, "all sixteen clients receive all six maximum-byte choices")
        equal(node.view().difficulty, "very_hard", "all sixteen clients receive difficulty")
        equal(node.view().era, "e" * 64, "all sixteen clients receive maximum-byte era metadata")
    check(host.quiz.Comms.queueCount < 128, "normal maximum capacity does not exhaust transport queue")
    round_ = host.quiz.Main.game.round
    for node in world.nodes[1:]:
        ok(node.call("Session", "SubmitAnswer", round_.correctIndex), "full-capacity player can select any of six choices")
    world.until(lambda: all(node.view().confirmedSelected == round_.correctIndex for node in world.nodes[1:]), seconds=8)
    world.until(lambda: all(node.view().correctIndex is not None for node in world.nodes[1:]), seconds=15)
    equal(host.quiz.Main.game.lastResult.totalAnswers, 16, "all sixteen six-choice answers score exactly once")
    equal(host.quiz.Main.game.lastResult.correctCount, 16, "all sixteen six-choice answers retain the correct mapping")
    host.call("Main", "Stop")
    world.until(lambda: all(node.view().state == "stopped" for node in world.nodes[1:]), seconds=8)
    for node in world.nodes:
        equal(len(node.test.errors), 0, "full capacity has no Lua errors")
        equal(len(node.test.sent), 0, "full capacity stays invisible to public chat")

    return assertions


if __name__ == "__main__":
    print(f"Network.py: {run_suite()} paired-runtime assertions passed")

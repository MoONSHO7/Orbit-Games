"""Exercise isolated clients through native discovery and the real fragmented quiz transport."""

import math

from lupa.lua51 import lua_type

from run import runtime

QUIZ_PREFIX = "ORBITQUIZ8"
DISCOVERY_PREFIX = "ORBITQUIZDISC8"
LOBBY_NAME = "OrbitQuizLobby"
REVEAL_SECONDS = 3
BOUNDARY_EPSILON = 0.001


def decode_fields(encoded, limit=None):
    count_text, rest = encoded.split(b":", 1)
    fields = []
    for _ in range(int(count_text) if limit is None else min(int(count_text), limit)):
        length_text, rest = rest.split(b":", 1)
        length = int(length_text)
        assert len(rest) >= length, "requested fields must be complete in the available fragment"
        fields.append(rest[:length].decode("utf-8"))
        rest = rest[length:]
    if limit is None:
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
        self.packet_round_ids = {}
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
                fields, round_id = None, None
                if prefix == QUIZ_PREFIX:
                    version, message_id, part, total, fragment = wire.split(b"|", 4)
                    assert version == b"1", "the quiz prefix changes without changing the transport envelope"
                    key = source.name, message_id
                    if part == b"1":
                        self.packet_codes[key] = fragment.split(b":", 2)[2][:1].decode("ascii")
                        if self.packet_codes[key] in ("Q", "R"):
                            self.packet_round_ids[key] = decode_fields(fragment, limit=3)[2]
                    code = self.packet_codes.get(key)
                    round_id = self.packet_round_ids.get(key)
                    if total == b"1":
                        fields = decode_fields(fragment)
                elif prefix == DISCOVERY_PREFIX:
                    version, code, *_ = wire.decode("utf-8").split("|")
                    assert version == "8", "discovery advertises the streak-toast protocol version"
                    message_id, part, total = str(source.cursor).encode("ascii"), b"1", b"1"
                    fields = wire.decode("utf-8").split("|")
                else:
                    raise AssertionError(f"Unexpected registered prefix: {prefix}")
                for target in self.recipients(source, channel, target_name):
                    packet = dict(source=source, target=target.name, native_target=target_name, prefix=prefix,
                                  hex=text, channel=channel, part=int(part), total=int(total),
                                  message_id=message_id, code=code, wire=wire, fields=fields, round_id=round_id)
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

    def register_pack(node, pack_id, title, version=1, matching_lore=False):
        register = node.lua.eval("""function(id, title, version, matchingLore)
            local rules = matchingLore and OrbitQuiz:GetPackRules('warcraft-lore') or nil
            return OrbitQuiz:RegisterQuestionPack({id=id, title=title, version=version, rules=rules, questions={
                {id='shared-question', prompt='Which answer is correct?',
                    choices={'Right', 'Wrong one', 'Wrong two', 'Wrong three'}, correctIndex=1}
            }})
        end""")
        ok(register(pack_id, title, version, matching_lore), "fixture pack registers with stable identity")

    def register_rule_pack(node, pack_id, rules, count=3):
        register = node.lua.eval("""function(id, rules, count)
            local questions = {}
            for index = 1, count do
                questions[index] = {id='rule-question-'..index, prompt='Authored rule question '..index,
                    choices={'Wrong first', 'Correct', 'Wrong third', 'Wrong fourth'}, correctIndex=2,
                    explanation='Private answer explanation.', source='https://example.org/private-rules-answer'}
            end
            return OrbitQuiz:RegisterQuestionPack({id=id, title=id, rules=rules, questions=questions})
        end""")
        ok(register(pack_id, node.lua.table_from(rules), count), "host-only authored rules pack registers")

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
    advertisement = f"8|A|123.456|{player.name}|Native identity|open|1".encode("utf-8").hex()
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
    register_pack(alpha, "shared-lore", "Shared lore", 1, matching_lore=True)
    register_pack(beta, "shared-lore", "Shared lore revised", 2, matching_lore=True)
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
    stats = player.quiz.Store.db.personalScores.packs["shared-lore"].rulesets[first.rulesKey]
    cached_stats = player.quiz.PersonalScores.packTotals["shared-lore"]
    original_score = stats.score
    stats.score = 999999
    cached_stats.score = 999999
    ok(player.call("Session", "JoinHost", beta.name), "edited local lifetime score cannot block joining")
    world.until(lambda: player.view().state == "open" and player.view().hostName == beta.name)
    equal(player.personal("shared-lore").score, 999999, "fixture genuinely forges the participant's local statistics and cache")
    equal(player.view().score, 0, "edited lifetime totals never seed the host-controlled session score")
    equal(len(beta.standings()), 0, "joining cannot inject a fabricated player into the host leaderboard")
    joins = [packet for packet in world.packets if packet["source"] is player
             and packet["target"] == beta.name and packet["code"] == "J"]
    check(joins and all(len(packet["fields"]) == 2 for packet in joins),
          "join packets contain only the action and membership nonce, never claimed totals")
    stats.score = original_score
    cached_stats.score = original_score
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

    register_pack(beta, "separate-lore", "AAA separate lore", matching_lore=True)
    separate, separate_points = join_and_answer(world, beta, player, "separate-lore")
    equal(player.personal("shared-lore").score, shared_score, "a different pack cannot alter shared-pack progress")
    equal(player.personal("separate-lore").score, separate_points, "a distinct pack has its own lifetime score")
    beta.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")

    register_pack(beta, "mixed-lore", "AAB mixed lore", matching_lore=True)
    beta.lua.execute("math.random = function(maximum) return maximum end")
    setup.packId = "all"
    ok(beta.call("Main", "Start", setup), "All packs starts a combined deck when every pack declares identical rules")
    ok(player.call("Session", "JoinHost", beta.name), "participant joins combined-pack play")
    for expected_pack in ("separate-lore", "mixed-lore"):
        world.until(lambda: player.view().state == "open" and player.view().packId == expected_pack, seconds=30)
        round_ = beta.quiz.Main.game.round
        equal(round_.packId, expected_pack, "combined deck retains the question's actual pack provenance")
        equal(player.view().packTitle, round_.packTitle, "combined Q carries its actual pack's title")
        equal(player.view().packVersion, round_.packVersion, "combined Q carries its actual pack's version")
        ok(player.call("Session", "SubmitAnswer", round_.correctIndex), "combined-pack question accepts a real answer")
        world.until(lambda: player.view().confirmedSelected == round_.correctIndex and not player.view().pending)
        world.until(lambda: player.view().correctIndex is not None)
        points = player.answer_on(beta).points
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
                and packet["round_id"] == str(int(first.id))):
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
    complete_held = captured_results(held_results, host, player)
    check(complete_held, "the dropped rule-aware receipt retains all of its fragments")
    for packet in complete_held[0][1]:
        world.deliver(packet)
    equal(player.personal("receipt-lore").score, round(first_points + second_points, 1),
          "late earlier receipt fills the missing personal score without losing the newer answer")
    equal(player.view().id, current_id, "late result cannot rewind the question widget")
    equal(player.view().points, current_points, "late result cannot animate the earlier question's points")
    equal(player.view().score, current_score, "late result cannot rewind the current host-session total")
    revision = player.quiz.PersonalScores.revision
    for packet in complete_held[-1][1]:
        world.deliver(packet)
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
    equal(len(result_fields), 23, "current results append canonical rules and compact group streak accounting")
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

    world = World("Rulehost", "Ruleplayer")
    host, player = world.nodes
    rules_id = "wire-authored-loop"
    register_rule_pack(host, rules_id, dict(answerSeconds=8, revealSeconds=2, shuffleQuestions=False,
                                           shuffleChoices=False, correctPoints=2, speedBonusPerSecond=0.2,
                                           wrongPenaltyStart=2, wrongPenaltyEnd=1,
                                           streakBonusPerCorrect=0.2, streakBonusMax=0.4))
    setup = host.call("Store", "GetSettings")
    setup.packId, setup.duration, setup.questionCount, setup.continuous = rules_id, 60, 1, False
    setup.rules = host.lua.table_from(dict(answerSeconds=60, correctPoints=1000))
    ok(host.call("Main", "Start", setup), "the host chooses a pack without changing its authored rules")
    ok(player.call("Session", "JoinHost", host.name), "participant joins without installing the author's pack")
    world.until(lambda: player.view().state == "open")
    first = host.quiz.Main.game.round
    equal(player.view().duration, 8, "variable answer time travels from the pack to the participant")
    equal(first.deadline - first.startedAt, 8, "legacy host settings cannot override the author's clock")
    equal(player.view().rulesKey, first.rulesKey, "both clients agree on the canonical game rules")
    equal(player.view().rules.revealSeconds, 2, "participant receives the pack's authored result interval")
    equal(player.view().correctIndex, None, "public rules metadata does not leak the private answer index")
    equal(player.view().explanation, None, "private explanation remains absent before results")
    equal(player.view().source, None, "private answer source remains absent before results")
    equal(len(player.quiz.GetQuestionPacks(player.quiz)), 1, "remote rules do not require the host's pack to be installed")
    equal(first.prompt, "Authored rule question 1", "authored question order remains stable across the wire")
    equal(first.correctIndex, 2, "unshuffled choice order remains stable across the wire")
    ok(player.call("Session", "SubmitAnswer", 1), "editable rule pack accepts an initial wrong choice")
    world.until(lambda: player.view().confirmedSelected == 1)
    world.advance(0.5)
    ok(player.call("Session", "SubmitAnswer", 2), "editable rule pack accepts a revised choice")
    world.until(lambda: player.view().confirmedSelected == 2 and not player.view().pending)
    first_answer = player.answer_on(host)
    expected_base = round(2 + 0.2 * math.floor(8 - first_answer.elapsed + 1e-7), 1)
    world.until(lambda: player.view().correctIndex is not None)
    equal(player.view().points, expected_base, "revised answers score using the author's rate and final host receipt time")
    equal(player.view().streak, 1, "first correct result starts the remote streak at one")
    equal(player.view().streakBonus, 0, "first correct result has no extra streak award")
    check(0 <= host.quiz.Main.nextAutoAt - host.quiz.Main.game.round.deadline - 2 < 0.100001,
          "the host schedules the authored two-second reveal from its deadline tick")
    world.until(lambda: player.view().state == "open" and player.view().id != first.id)
    second = host.quiz.Main.game.round
    equal(second.prompt, "Authored rule question 2", "automatic authored progression uses the next ordered question")
    ok(player.call("Session", "SubmitAnswer", 2), "second consecutive remote answer is correct")
    world.until(lambda: player.view().confirmedSelected == 2 and not player.view().pending)
    second_answer = player.answer_on(host)
    second_base = round(2 + 0.2 * math.floor(8 - second_answer.elapsed + 1e-7), 1)
    held_streak = []

    def hold_streak_receipt(packet):
        if (packet["source"] is host and packet["target"] == player.name and packet["code"] == "R"
                and packet["round_id"] == str(int(second.id))):
            held_streak.append(packet)
            return True
        return False

    world.drop = hold_streak_receipt
    world.until(lambda: player.view().state == "open" and player.view().id != second.id, seconds=20)
    current = host.quiz.Main.game.round
    equal(current.prompt, "Authored rule question 3", "a missing old receipt does not halt automatic question delivery")
    equal(player.personal(rules_id).answers, 1, "a withheld streak result cannot be inferred from session totals")
    held_complete = captured_results(held_streak, host, player)
    check(held_complete, "the complete streak receipt was genuinely withheld")
    equal(held_complete[0][0][19], first.rulesKey, "delayed results carry their original canonical rules")
    equal(held_complete[0][0][20], "2", "delayed results retain their original finalized streak")
    equal(float(held_complete[0][0][21]), 0.2, "delayed results retain their additional streak award")
    current_deadline = player.view().deadline
    for packet in held_complete[0][1]:
        world.deliver(packet)
    equal(player.personal(rules_id).score, round(expected_base + second_base + 0.2, 1),
          "late streak receipt credits its exact original score")
    equal(player.view().id, current.id, "late streak metadata cannot rewind the active question")
    equal(player.view().deadline, current_deadline, "late streak metadata cannot change the active timer")
    equal(player.view().points, None, "late streak metadata cannot replay old floating score feedback")
    revision = player.quiz.PersonalScores.revision
    for packet in held_complete[-1][1]:
        world.deliver(packet)
    equal(player.quiz.PersonalScores.revision, revision, "duplicate old streak receipt is idempotent")
    world.drop = lambda packet: False
    world.until(lambda: player.view().correctIndex is not None)
    equal(player.view().selected, None, "an unanswered authored round has no invented selection")
    equal(player.view().streak, 0, "the participant receives the reset streak for an unanswered question")
    equal(player.view().streakBonus, 0, "an unanswered authored round earns no stale streak reward")
    world.until(lambda: player.view().state == "open" and player.view().id != current.id)
    repeated = host.quiz.Main.game.round
    equal(repeated.prompt, "Authored rule question 1", "ordered repeated decks return to the authored first question")
    ok(player.call("Session", "SubmitAnswer", 2), "correct answer after a missed round is accepted")
    world.until(lambda: player.view().correctIndex is not None)
    equal(player.view().streak, 1, "a missed question resets the next remote streak to one")
    equal(player.view().streakBonus, 0, "the next correct answer cannot recover the lost streak bonus")
    check(all(b"private-rules-answer" not in packet["wire"] for packet in world.packets),
          "rule-aware traffic never transmits editorial answer sources")
    host.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")
    for node in world.nodes:
        equal(len(node.test.errors), 0, "rule-aware retry scenario has no unexpected Lua errors")

    for repeats, limit, expected_count in ((False, 0, 2), (True, 3, 3)):
        world = World("Finitehost", "Finiteplayer")
        host, player = world.nodes
        rules_id = "wire-authored-finite"
        register_rule_pack(host, rules_id, dict(answerSeconds=5, revealSeconds=2, allowAnswerChanges=False,
                                               shuffleQuestions=False, shuffleChoices=False,
                                               repeatQuestions=repeats, questionLimit=limit), count=2)
        setup = host.call("Store", "GetSettings")
        setup.packId = rules_id
        ok(host.call("Main", "Start", setup), "finite multiplayer game starts from pack-owned rules")
        ok(player.call("Session", "JoinHost", host.name), "finite multiplayer participant joins")
        previous_id = None
        for number in range(1, expected_count + 1):
            world.until(lambda: player.view().state == "open" and player.view().id != previous_id)
            round_ = host.quiz.Main.game.round
            equal(round_.prompt, "Authored rule question " + str((number - 1) % 2 + 1),
                  "finite remote rounds obey ordered single-pass or repeated-deck rules")
            equal(round_.deadline - round_.startedAt, 5, "finite rounds receive their full authored answer window")
            ok(player.call("Session", "SubmitAnswer", 2), "finite locked-answer pack accepts the first click")
            revision = player.quiz.Session.client.answerRevision
            check(not player.call("Session", "SubmitAnswer", 3)[0], "pending first-answer lock rejects replacement clicks")
            equal(player.quiz.Session.client.answerRevision, revision, "locked replacement cannot change revision timing")
            world.until(lambda: player.view().confirmedSelected == 2 and not player.view().pending)
            accepted = player.answer_on(host)
            accepted_elapsed = accepted.elapsed
            rogue_fields = player.lua.table_from(["A", player.quiz.Session.client.session, str(int(round_.id)), "3",
                                                  str(int(revision + 1)), player.quiz.Session.client.request])
            ok(player.call("Comms", "Send", host.name, rogue_fields), "test sends a deliberate changed-answer packet past the local widget")
            world.advance(0.4)
            equal(player.answer_on(host).choiceIndex, 2, "host rules reject a changed answer even from a modified participant")
            equal(player.answer_on(host).elapsed, accepted_elapsed, "host rejection preserves the original accepted timestamp")
            world.until(lambda: player.view().correctIndex is not None)
            equal(player.personal(rules_id).answers, number, "finite results persist once per completed question")
            previous_id = round_.id
        equal(host.quiz.Main.game.completed, expected_count, "finite multiplayer game closes exactly the authored round count")
        equal(host.quiz.Main.game.state, "finished", "finite model finishes before the final presentation is dismissed")
        equal(host.view().state, "results", "host keeps the final answer visible during its reveal")
        equal(player.view().state, "results", "participant keeps the final answer visible during its reveal")
        check(host.call("Main", "IsRunning"), "final multiplayer reveal retains live authority until its end")
        final_packets = captured_results(world.packets, host, player)
        check(final_packets and final_packets[-1][0][2] == str(int(previous_id)), "last question's complete receipt precedes session shutdown")
        next_id = host.lua.globals().OrbitQuizDB.nextQuestionId
        world.until(lambda: player.view().state == "stopped")
        equal(host.quiz.Session.hostSession, None, "finite host ends itself without a manual Stop")
        world.until(lambda: len(player.games()) == 0)
        world.advance(20)
        equal(host.lua.globals().OrbitQuizDB.nextQuestionId, next_id, "completed finite multiplayer games do not restart")
        equal(player.personal(rules_id).answers, expected_count, "session shutdown and receipt retries never double award the last answer")
        for node in world.nodes:
            equal(len(node.test.errors), 0, "finite multiplayer rules introduce no Lua errors")
            equal(len(node.test.sent), 0, "finite multiplayer quiz remains widget-only")

    world = World("Lockhost", "Lockplayer")
    host, player = world.nodes
    rules_id = "wire-lock-recovery"
    register_rule_pack(host, rules_id, dict(answerSeconds=120, allowAnswerChanges=False,
                                           shuffleQuestions=False, shuffleChoices=False), count=1)
    setup = host.call("Store", "GetSettings")
    setup.packId = rules_id
    ok(host.call("Main", "Start", setup), "long locked-answer recovery fixture starts")
    ok(player.call("Session", "JoinHost", host.name), "locked-answer recovery participant joins")
    world.until(lambda: player.view().state == "open")
    round_ = host.quiz.Main.game.round
    ok(player.call("Session", "SubmitAnswer", 2), "original locked answer is selected")
    world.until(lambda: player.view().confirmedSelected == 2 and not player.view().pending)
    original_answer = player.answer_on(host)
    original_elapsed, original_points = original_answer.elapsed, original_answer.points
    original_deadline = round_.deadline
    old_request = player.quiz.Session.client.request
    withheld_locks = []

    def drop_recovery_locks(packet):
        if packet["source"] is host and packet["target"] == player.name and packet["code"] == "K":
            withheld_locks.append(packet)
            return True
        return False

    world.drop = drop_recovery_locks
    player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    player.test.restricted = True
    world.advance(0.5)
    player.test.restricted = False
    player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    world.until(lambda: player.quiz.Session.client.request != old_request and player.view().state == "open"
                and player.view().id == round_.id)
    equal(player.view().confirmedSelected, None, "dropped rejoin K leaves the recovered question without confirmed selection")
    equal(player.view().selected, None, "renewed membership does not invent the missing host lock snapshot")
    recovered_deadline = player.view().deadline
    ok(player.call("Session", "SubmitAnswer", 1), "fixture tries another choice before the original lock snapshot returns")
    world.until(lambda: player.quiz.Session.client.lockSyncId == round_.id)
    equal(player.view().locked, True, "host answer_locked response keeps the widget locked during snapshot repair")
    equal(player.answer_on(host).choiceIndex, 2, "the host never changes its original locked answer")
    equal(player.answer_on(host).elapsed, original_elapsed, "the host preserves the original locked-answer receipt time")
    equal(round_.deadline, original_deadline, "membership renewal never extends the host's answering deadline")
    sync_before = len([packet for packet in world.packets if packet["source"] is player and packet["code"] == "S"])
    world.advance(5)
    sync_after = len([packet for packet in world.packets if packet["source"] is player and packet["code"] == "S"])
    check(1 <= sync_after - sync_before <= 3, "lost lock recovery retries snapshots at a bounded interval, not every tick")
    check(withheld_locks, "the missing authoritative lock snapshots were genuinely dropped")
    equal(player.quiz.Session.client.lockSyncId, round_.id, "unanswered lock repair remains pending while K packets are lost")
    equal(player.personal(rules_id), None, "lock repair cannot award a question before the host closes it")
    equal(player.view().deadline, recovered_deadline, "bounded lock snapshot retries do not reset the recovered question clock")
    world.drop = lambda packet: False
    world.until(lambda: player.view().confirmedSelected == 2 and player.view().selected == 2
                and player.quiz.Session.client.lockSyncId is None and not player.view().pending, seconds=8)
    equal(player.view().locked, True, "restored authoritative choice remains locked for the rest of the round")
    equal(player.view().deadline, recovered_deadline, "the recovered authoritative answer does not retime the question")
    equal(player.answer_on(host).elapsed, original_elapsed, "recovered lock preserves the original accepted timestamp")
    equal(player.answer_on(host).points, original_points, "recovered lock preserves the original pending reward")
    equal(player.personal(rules_id), None, "a restored lock still does not count as a finalized result")
    old_request = player.quiz.Session.client.request
    world.drop = drop_recovery_locks
    player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    player.test.restricted = True
    world.advance(0.5)
    player.test.restricted = False
    player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    world.until(lambda: player.quiz.Session.client.request != old_request and player.view().state == "open"
                and player.view().id == round_.id)
    equal(player.view().selected, None, "another lost rejoin K reproduces missing first-answer state")
    equal(player.view().confirmedSelected, None, "the lost-E variant begins without an authoritative selected index")
    missing_error_deadline = player.view().deadline
    withheld_errors = []

    def drop_lock_rejection(packet):
        if packet["source"] is host and packet["target"] == player.name and packet["code"] == "E":
            withheld_errors.append(packet)
            return True
        return False

    world.drop = drop_lock_rejection
    rejected_attempt_at, rejected_packet_start = host.test.now, len(world.packets)
    ok(player.call("Session", "SubmitAnswer", 1), "lost-E fixture attempts a different choice before learning the original lock")
    world.until(lambda: player.view().selected == 2 and player.view().confirmedSelected == 2
                and not player.view().pending, seconds=0.5)
    check(withheld_errors, "the answer_locked rejection packet was genuinely lost")
    check(host.test.now - rejected_attempt_at < 1, "the forced lock snapshot repairs selection before the answer retry interval")
    attempts = [packet for packet in world.packets[rejected_packet_start:]
                if packet["source"] is player and packet["prefix"] == QUIZ_PREFIX and packet["code"] == "A"]
    equal(len(attempts), 1, "lost-E recovery does not wait for rejected-answer retries")
    equal(player.view().locked, True, "authoritative first-choice K locks input even when its paired E never arrives")
    equal(player.quiz.Session.client.lockSyncId, None, "current-membership K repairs the state without requiring an E latch")
    equal(player.view().deadline, missing_error_deadline, "forced first-choice restoration does not reset the recovered clock")
    equal(player.answer_on(host).choiceIndex, 2, "a lost rejection cannot overwrite the original host-side answer")
    equal(player.answer_on(host).elapsed, original_elapsed, "lost-E recovery preserves the first answer's original time")
    equal(player.answer_on(host).points, original_points, "lost-E recovery preserves the first answer's reward")
    equal(player.personal(rules_id), None, "receiving authoritative K without E still awards no premature score")
    world.drop = lambda packet: False
    world.until(lambda: player.view().correctIndex is not None, seconds=120)
    equal(player.view().selected, 2, "final receipt confirms the original accepted answer, not the rejected replacement")
    equal(player.personal(rules_id).score, original_points, "final receipt awards the original answer exactly once")
    equal(player.personal(rules_id).answers, 1, "renewed membership and repeated lock repairs count one finalized answer")
    host.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")
    for node in world.nodes:
        equal(len(node.test.errors), 0, "lost-lock recovery has no unexpected Lua errors")

    world = World("Revealhost", "Revealplayer")
    host, player = world.nodes
    rules_id = "wire-finite-reveal-recovery"
    register_rule_pack(host, rules_id, dict(answerSeconds=5, revealSeconds=3, repeatQuestions=False,
                                           shuffleQuestions=False, shuffleChoices=False), count=1)
    setup = host.call("Store", "GetSettings")
    setup.packId = rules_id
    ok(host.call("Main", "Start", setup), "finite restriction-reveal fixture starts")
    ok(player.call("Session", "JoinHost", host.name), "finite restriction-reveal participant joins")
    world.until(lambda: player.view().state == "open")
    round_ = host.quiz.Main.game.round
    ok(player.call("Session", "SubmitAnswer", 2), "finite question accepts its final answer")
    world.until(lambda: player.view().confirmedSelected == 2 and not player.view().pending)
    final_points = player.answer_on(host).points
    host.test.now = round_.deadline
    player.test.now = round_.deadline
    host.call("Main", "CloseQuestion", host.test.now)
    equal(host.quiz.Main.game.state, "finished", "the finite result closes before restriction suppresses transport")
    equal(player.personal(rules_id), None, "the final receipt is still queued when restriction begins")
    original_reveal_end = host.quiz.Main.nextAutoAt
    host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    host.test.restricted = True
    world.advance(5)
    check(host.test.now > original_reveal_end, "restriction genuinely outlasts the original final reveal")
    check(host.call("Main", "IsRunning"), "restricted final presentation retains its unfinished host authority")
    equal(player.personal(rules_id), None, "restricted transport cannot pretend the delayed result was delivered")
    equal(player.quiz.Widget.scoreAnimation.playCalls, 0, "timer expiry alone does not animate an unconfirmed score")
    check(not any(packet["source"] is host and packet["code"] == "X" for packet in world.packets),
          "the finite host does not quit while its final result is communication-restricted")
    host.test.restricted = False
    recovered_at = host.test.now
    host.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    refreshed_reveal_end = host.quiz.Main.nextAutoAt
    equal(refreshed_reveal_end, recovered_at + 3, "restriction recovery starts a full new final-reveal interval")
    world.until(lambda: player.view().correctIndex is not None)
    world.until(lambda: player.quiz.Widget.scoreAnimation.playCalls > 0, seconds=1)
    equal(player.view().state, "results", "the delayed final result becomes visible before the session-end packet")
    equal(player.view().points, final_points, "recovered final reveal carries the original authoritative score")
    equal(player.personal(rules_id).score, final_points, "recovered final result credits its original score")
    equal(player.personal(rules_id).answers, 1, "final result recovery credits exactly one answer")
    equal(player.quiz.Widget.scoreAnimation.playCalls, 1, "the participant receives real score feedback before automatic shutdown")
    recovered_results = captured_results(world.packets, host, player)
    check(recovered_results, "a complete retained final receipt was actually retransmitted after restriction")
    ok(host.call("Comms", "Send", player.name, host.lua.table_from(recovered_results[-1][0])),
       "the recovered final receipt is retransmitted under a fresh envelope")
    world.advance(0.3)
    equal(player.personal(rules_id).answers, 1, "recovered final receipt replay remains idempotent")
    equal(player.quiz.Widget.scoreAnimation.playCalls, 1, "duplicate final receipts cannot replay the score animation")
    world.step(refreshed_reveal_end - host.test.now - BOUNDARY_EPSILON)
    check(host.call("Main", "IsRunning"), "the final host remains alive until its refreshed reveal boundary")
    equal(player.view().state, "results", "the participant retains final results throughout the refreshed reveal")
    check(not any(packet["source"] is host and packet["code"] == "X" for packet in world.packets),
          "the original expired reveal deadline cannot send an early session-end packet")
    world.step(refreshed_reveal_end - host.test.now)
    world.until(lambda: player.view().state == "stopped")
    equal(host.quiz.Session.hostSession, None, "finite hosting ends only after the recovered final reveal")
    equal(player.personal(rules_id).answers, 1, "refreshed reveal completion cannot duplicate the final award")
    for node in world.nodes:
        equal(len(node.test.errors), 0, "finite final-reveal recovery has no unexpected Lua errors")

    world = World("Rulesalpha", "Rulesbeta", "Rulesplayer")
    alpha, beta, player = world.nodes
    register_rule_pack(alpha, "revised-rules", dict(version=1, answerSeconds=8, correctPoints=2, speedBonusPerSecond=0), count=1)
    register_rule_pack(beta, "revised-rules", dict(version=2, answerSeconds=10, correctPoints=3, speedBonusPerSecond=0), count=1)
    alpha_round, alpha_points = join_and_answer(world, alpha, player, "revised-rules")
    alpha.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")
    beta_round, beta_points = join_and_answer(world, beta, player, "revised-rules")
    check(alpha_round.rulesKey != beta_round.rulesKey, "different author rules create distinct accounting identities")
    rows = [row for row in player.call("PersonalScores", "GetScoreRows").values() if row.id == "revised-rules"]
    equal(len(rows), 2, "different rules for the same pack remain separate in player-facing score rows")
    by_rules = {row.rulesKey: row for row in rows}
    equal(by_rules[alpha_round.rulesKey].score, alpha_points, "old rules retain only their own earned score")
    equal(by_rules[beta_round.rulesKey].score, beta_points, "new rules retain only their own earned score")
    equal(by_rules[alpha_round.rulesKey].rules.version, 1, "old authored rule revision is retained")
    equal(by_rules[beta_round.rulesKey].rules.version, 2, "new authored rule revision is retained")
    beta.call("Main", "Stop")
    world.until(lambda: player.view().state == "stopped")
    reloaded = Node("Rulesplayeralt", saved=saved_copy(player.lua.globals().OrbitQuizDB))
    reloaded_rows = [row for row in reloaded.call("PersonalScores", "GetScoreRows").values() if row.id == "revised-rules"]
    equal(len(reloaded_rows), 2, "rules-specific score rows survive an account-character reload")
    equal({row.rulesKey: row.score for row in reloaded_rows}, {alpha_round.rulesKey: alpha_points, beta_round.rulesKey: beta_points},
          "reload cannot merge or rescore previously earned points under newer rules")

    world = World("Quizhost", *["Player" + chr(65 + index) for index in range(16)])
    host = world.nodes[0]
    capacity_pack_id = "capacity-" + "x" * 39
    host.lua.execute("""
        local choices = {}
        for index = 1, 6 do choices[index] = string.rep('x', 99)..index end
        assert(OrbitQuiz:RegisterQuestionPack({id='capacity-'..string.rep('x', 39), title=string.rep('t', 64),
            version=2147483647,
            rules={version=2147483647, correctPoints=1000, speedBonusPerSecond=10,
                wrongPenaltyStart=1000, wrongPenaltyEnd=1000, wrongPenaltyCurve=10,
                streakBonusPerCorrect=10, streakBonusMax=100}, questions={
            {id='capacity', prompt=string.rep('q', 160), choices=choices, correctIndex=6,
                difficulty='very_hard', era=string.rep('e', 64), source='https://example.org/private-source'}
        }}))
    """)
    settings = host.call("Store", "GetSettings")
    settings.packId = capacity_pack_id
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
        equal(node.view().rulesKey, host.quiz.Main.game.rulesKey, "all sixteen clients receive the same maximum-sized scoring rules")
        equal(node.view().rules.correctPoints, 1000, "all sixteen clients decode the author's high-value score bounds")
        equal(node.view().packVersion, 2147483647, "full-capacity delivery retains the maximum content revision")
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

    world = World("Streakhost", "Streakplayer", "Streakfriend")
    host, player, friend = world.nodes
    rules_id = "wire-streak-toasts"
    register_rule_pack(host, rules_id, dict(shuffleQuestions=False, shuffleChoices=False), count=1)
    setup = host.call("Store", "GetSettings")
    setup.packId = rules_id
    ok(host.call("Main", "Start", setup), "group milestone fixture starts without a scoring bonus rule")
    ok(player.call("Session", "JoinHost", host.name), "first group milestone participant joins")
    missing_name_packets = []

    def drop_friend_name(packet):
        if (packet["source"] is host and packet["target"] == player.name and packet["code"] == "N"
                and packet["fields"] and friend.name in packet["fields"][4].split(",")):
            missing_name_packets.append(packet)
            return True
        return False

    world.drop = drop_friend_name
    world.until(lambda: player.view().state == "open" and player.quiz.Session.client.streakSpeakers is not None
                and player.quiz.Session.client.streakSpeakers.count == 2)
    ok(friend.call("Session", "JoinHost", host.name), "another group milestone participant joins after known identities prewarm")
    previous_round = None
    for expected_streak in range(1, 6):
        world.until(lambda: all(node.view().state == "open" and node.view().id != previous_round for node in world.nodes),
                    seconds=30)
        round_ = host.quiz.Main.game.round
        if expected_streak == 5:
            old_request = player.quiz.Session.client.request
            player.test.restricted = True
            world.advance(0.4)
            player.test.restricted = False
            player.event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
            world.until(lambda: player.view().state == "open" and player.view().id == round_.id
                        and player.quiz.Session.client.request != old_request)
            check(not player.view().suppressStreakToasts, "an unscored mid-question reconnect does not suppress a future milestone")
        for node in world.nodes:
            equal(node.view().streakMilestones, None, "open selections never expose a provisional milestone batch")
            ok(node.call("Session", "SubmitAnswer", 2), "all three players answer the streak round correctly")
        world.until(lambda: all(not node.view().pending for node in (player, friend)))
        world.until(lambda: all(node.view().correctIndex is not None for node in world.nodes), seconds=20)
        for node in world.nodes:
            equal(node.view().streak, expected_streak, "the host's final correct streak reaches every participant")
            equal(node.view().streakBonus, 0, "toast milestones do not enable the pack's disabled scoring bonus")
        if expected_streak < 5:
            for node in world.nodes:
                equal(len(node.view().streakMilestones), 0, "correct streaks below five produce no group toast events")
        previous_round = round_.id
    check(missing_name_packets, "the simulation genuinely lost repeated name dictionary messages")
    equal(len(host.view().streakMilestones), 3, "the host commits all three fifth-correct milestones")
    equal(len(friend.view().streakMilestones), 3, "a complete dictionary resolves the full authoritative batch")
    equal({event.name: event.streak for event in player.view().streakMilestones.values()},
          {host.name: 5, player.name: 5}, "a dropped unrelated name never suppresses known player milestones")
    equal(player.personal(rules_id).answers, 5, "a missing presentation dictionary never blocks score persistence")
    check(not player.view().suppressStreakToasts, "successful open-round reconnect still celebrates its first real fifth result")
    world.drop = lambda packet: False
    world.until(lambda: len(player.view().streakMilestones) == 3, seconds=2.5)
    equal({event.name: event.streak for event in player.view().streakMilestones.values()},
          {host.name: 5, player.name: 5, friend.name: 5}, "a recovered map adds only the missing current-result identity")
    results = captured_results(world.packets, host, player)
    fifth_fields = next(fields for fields, _ in reversed(results) if int(fields[2]) == previous_round)
    equal(len(fifth_fields), 23, "group milestones use one additional compact result field")
    check(all(name not in fifth_fields[22] for name in (host.name, player.name, friend.name)),
          "streak results reference prefetched names instead of retransmitting the group roster")
    check(len(fifth_fields[22]) < 32, "three normal streak identities use only a few result bytes")
    score_before = player.personal(rules_id).score
    ok(host.call("Comms", "Send", player.name, host.lua.table_from(fifth_fields)), "same milestone receipt retransmits")
    world.advance(0.3)
    equal(player.personal(rules_id).answers, 5, "same round milestone retransmission cannot award twice")
    equal(player.personal(rules_id).score, score_before, "same milestone metadata cannot adjust a recorded score")
    world.until(lambda: all(node.view().state == "open" and node.view().id != previous_round for node in world.nodes), seconds=20)
    ok(host.call("Comms", "Send", player.name, host.lua.table_from(fifth_fields)), "older milestone is replayed after new question")
    for packet in missing_name_packets[-1:]:
        world.deliver(packet)
    world.advance(0.3)
    equal(player.view().streakMilestones, None, "old results and name packets never attach milestones to a newer question")
    ok(host.call("Session", "SubmitAnswer", 2), "host continues its correct streak")
    ok(player.call("Session", "SubmitAnswer", 1), "participant intentionally breaks the streak")
    world.until(lambda: all(node.view().correctIndex is not None for node in world.nodes), seconds=20)
    for node in world.nodes:
        equal({event.name: event.streak for event in node.view().streakMilestones.values()}, {host.name: 6},
              "wrong and unanswered players reset while the correct host alone earns the next tier")
    host.call("Main", "Stop")
    world.until(lambda: all(node.view().state == "stopped" for node in (player, friend)))
    for node in world.nodes:
        equal(len(node.test.errors), 0, "streak identity loss/reconnect/replay handling has no Lua errors")

    world = World("Toastleader", *["Member" + chr(65 + index) for index in range(16)])
    host = world.nodes[0]
    peers = world.nodes[1:]
    host.lua.execute("""
        local choices = {}
        for index=1,6 do choices[index]=string.rep('x',99)..index end
        assert(OrbitQuiz:RegisterQuestionPack({id='toast-capacity', title=string.rep('t',64),
            rules={shuffleQuestions=false,shuffleChoices=false}, questions={
                {id='full',prompt=string.rep('q',160),choices=choices,correctIndex=6,
                difficulty='very_hard',era=string.rep('e',64)}
            }}))
    """)
    setup = host.call("Store", "GetSettings")
    setup.packId = "toast-capacity"
    ok(host.call("Main", "Start", setup), "six-choice sixteen-peer milestone stress game starts")
    for node in peers:
        ok(node.call("Session", "JoinHost", host.name), "milestone stress participant joins")
    initial_id = host.quiz.Main.game.round.id
    world.until(lambda: host.quiz.Main.game.round.id != initial_id and host.quiz.Main.game.state == "open", seconds=50)
    previous_round = initial_id
    for expected_streak in range(1, 6):
        world.until(lambda: all(node.view().state == "open" and node.view().id != previous_round for node in world.nodes),
                    seconds=45)
        round_ = host.quiz.Main.game.round
        check(all(peer.readyId == round_.id for peer in host.quiz.Session.peers.values()),
              "background name prefetch cannot consume the twenty-second full-capacity readiness window")
        for node in world.nodes:
            ok(node.call("Session", "SubmitAnswer", 6), "all seventeen players answer the capacity round")
        world.until(lambda: all(node.view().confirmedSelected == 6 and not node.view().pending for node in peers), seconds=8)
        world.until(lambda: all(node.view().correctIndex is not None and node.view().id == round_.id for node in peers),
                    seconds=20)
        check(host.quiz.Comms.queueCount < 128, "milestone metadata cannot flood the bounded gameplay transport")
        previous_round = round_.id
    for node in world.nodes:
        milestones = host.quiz.Main.game.lastResult.streakMilestones if node is host else node.view().streakMilestones
        equal(len(milestones), 17, "a normal full-capacity fifth streak resolves every player")
        equal({event.name: event.streak for event in milestones.values()},
              {member.name: 5 for member in world.nodes}, "every participant receives the same seventeen-player milestone batch")
    final_receipt = next(fields for fields, _ in reversed(captured_results(world.packets, host, peers[-1]))
                         if int(fields[2]) == previous_round)
    check(len(final_receipt[22]) < 100, "all seventeen normal milestones fit in under one hundred result bytes")
    world.until(lambda: host.quiz.Main.game.round.id != previous_round and host.quiz.Main.game.state == "open", seconds=30)
    check(all(peer.readyId == host.quiz.Main.game.round.id for peer in host.quiz.Session.peers.values()),
          "the question after a seventeen-toast result still waits for all peers without readiness expiry")
    host.call("Main", "Stop")
    world.until(lambda: all(node.view().state == "stopped" for node in peers), seconds=8)
    for node in world.nodes:
        equal(len(node.test.errors), 0, "full-capacity streak transport has no Lua errors")

    return assertions


if __name__ == "__main__":
    print(f"Network.py: {run_suite()} paired-runtime assertions passed")

"""Cards delivery regressions using independent clients and the real throttled transport."""

from Network import World


def run_suite():
    world = World("CardHost", *(f"CardPlayer{letter}" for letter in "ABCDEFG"))
    host, *players = world.nodes
    assertions = 0

    def check(value, message):
        nonlocal assertions
        assertions += 1
        assert value, message

    def call(node, owner, method, *args):
        module = node.games_root.Cards[owner]
        return module[method](module, *args)

    for node in world.nodes:
        node.call("Main", "SelectGameType", "cards")
    host.call("Main", "Start")
    session = host.games_root.Cards.Session.hostSession
    for player in players:
        call(player, "Session", "JoinHost", host.name, session)
    world.until(lambda: all(len(player.view().seats or ()) == 8 for player in players), seconds=30)
    check(True, "all seven participants receive a complete eight-seat table")
    call(host, "Controller", "StartHand")
    world.until(lambda: all(player.view().state == "preflop" for player in players), seconds=15)
    for player in players:
        own = [seat for seat in player.view().seats.values() if seat.id == player.view().playerId]
        check(len(own) == 1 and len(own[0].holeCards) == 2, "each participant receives its own hole cards")
        check(all(seat.holeCards is None for seat in player.view().seats.values()
                  if seat.id != player.view().playerId), "fragmented projections keep other hole cards private")
    for node in world.nodes:
        check(not len(node.test.errors), "sustained full-table delivery causes no runtime errors")

    world = World("TurnHost", "TurnPlayer")
    host, player = world.nodes
    for node in world.nodes:
        node.call("Main", "SelectGameType", "cards")
    host.call("Main", "Start")
    call(player, "Session", "JoinHost", host.name)
    world.until(lambda: len(player.view().seats or ()) == 2)
    call(host, "Controller", "StartHand")
    call(host, "Session", "Act", "call")
    world.until(lambda: player.view().legalActions is not None)
    world.drop = lambda packet: packet["source"] == player and packet["code"] == "A"
    call(player, "Session", "Act", "all_in")
    world.until(lambda: any(packet["code"] == "A" and packet["source"] == player for packet in world.packets))
    delayed = next(packet for packet in world.packets if packet["code"] == "A" and packet["source"] == player)
    world.until(lambda: host.view().state == "flop", seconds=35)
    revision = host.view().revision
    world.deliver(delayed)
    check(host.view().revision == revision, "an expired preflop wager cannot become a flop wager")
    world.until(lambda: not player.view().pending)
    check(player.view().notice == player.games_root.Cards.L.errors.stale_action,
          "stale actions release the client with an actionable rejection")

    request = host.games_root.Cards.Session.peers[player.name.lower()].request
    call(player, "Session", "Reconnect", player.test.now, "reconnecting")
    world.until(lambda: player.view().state == "flop")
    membership = host.games_root.Cards.Session.peers[player.name.lower()]
    current_request = membership.request
    check(current_request != request, "reconnection establishes a fresh membership")
    comms = player.games_root.Comms
    fields = player.games_root.Cards.Protocol.Join(request, host.games_root.Cards.Session.hostSession)
    comms.Send(comms, host.name, "cards", fields)
    world.advance(2)
    check(host.games_root.Cards.Session.peers[player.name.lower()].request == current_request,
          "an older join arriving after reconnect cannot replace the new membership")
    return assertions


if __name__ == "__main__":
    print(f"CardsNetwork.py: {run_suite()} assertions passed")

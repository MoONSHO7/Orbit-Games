# Networking

## Description

Native identity, bounded generic addon-message transport, game discovery and mode-routed sessions.

## Purpose

Move game-independent routing below registered game types while keeping each mode's payload validation with that mode.

## Implementation

`Identity.lua` owns native identity capture and `NormalizeName`, including realm completion and secret guards.

`Transport.lua` exposes the shared bounded codec, fragmentation, queue, retry and tagged-message service under `ORBITGAMES1`. Its envelope carries the registered mode ID and protocol version; transport rejects unknown or mismatched pairs before routing otherwise opaque payload fields to their owner.

`Discovery.lua` advertises immutable game/activity IDs and versions, mode summary, host state, occupancy, capacity and join availability under `ORBITGAMESDISC2`. A host snapshots its persisted Host-to selection: Server uses the silent `OrbitGamesLobby` custom channel, Guild uses the guild route, and Party uses whichever party, raid and instance routes are available. Advertisements and withdrawals use only those selected routes; discovery queries still fan out across every available route. Joining routes the complete advert to the selected mode owner, so Host-to controls listing discoverability rather than direct-join authorization.

`Modes/Quiz/Network/Session.lua` owns Quiz protocol 2 membership, readiness, answers, results, receipts and on-demand current-game standings. Ordinary question, result and heartbeat traffic carries no leaderboard. A participant requests it only by hovering the permanent HUD score; the host replies with a bounded authoritative snapshot and monotonic revision. Clients replace the last accepted snapshot rather than accumulating it, and the snapshot never enters score calculation or Personal receipt accounting. `Modes/Quiz/Network/Streaks.lua` owns compact Quiz milestone-name synchronization. The generic envelope does not validate Quiz rules or calculate points.

`Modes/Cards/Network/Session.lua` owns Cards protocol 3 membership, idempotent action acknowledgement/retry, heartbeats and monotonically versioned recipient snapshots. Actions bind to the observed model revision so late delivery cannot apply a wager to a later turn. Queued snapshots finish before replacements; repeated joins/welcomes preserve acknowledgement and view state. `Protocol.lua` validates the action envelope; the Texas Hold'em codec validates and bounds the projected table without transporting the deck or burns.

## Gotchas

- All players need discovery protocol 2, the registered Quiz game protocol 2 and the selected game type. Quiz supports the host plus 16 remote players; other activities advertise their own capacity.
- Game/activity IDs and versions are wire contracts. Never change a payload shape beneath an existing pair; bump the applicable protocol instead.
- Unknown addon-message prefixes and unsupported protocol versions are ignored; never reinterpret them as current messages.
- Server is best-effort discovery among clients joined to `OrbitGamesLobby`, not a guaranteed realm-wide broadcast. Guild and group visibility still follow native membership and cross-realm addon-whisper rules.
- WoW exposes no native Friends/Battle.net addon-message multicast, so there is no Friends audience or Battle.net relay.
- Native addon messages and the shared lobby are invisible transport. Do not add a player-chat or chat-frame fallback when a route fails.
- `ChannelThrottle` may follow submission of a native packet. Application acknowledgements and bounded retries determine delivery; blindly resending the same fragment can duplicate it.
- Only one session may be active. Joining another host leaves the prior game or stops local hosting.
- Standings are host-reported and downloaded only after score hover. Repeated requests and duplicate replies are idempotent; stale or conflicting revisions are rejected, and leaving or switching hosts discards the cached snapshot.
- Bounded retries cannot guarantee unseen results after leaving, host switching or logout. Checksums and rule keys are consistency checks, not authenticated competitive scores.

## Secrets

Check native names, GUIDs, payloads, sender names, lobby IDs and restriction flags before string operations or comparisons. Chat lockdown suspends sending and parsing.

## References

- [Application lifecycle](../App/README.md), [Cards protocol](../Modes/Cards/README.md), [Quiz protocol](../Modes/Quiz/README.md), [saved data](../Data/README.md) and [two-client verification](../Docs/QUICKSTART.md).
- Blizzard reference: `../../wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua` and `RestrictedActionsDocumentation.lua`.

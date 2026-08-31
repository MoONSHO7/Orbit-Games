# Networking

## Description

Native character identity, bounded addon-message transport, quiz membership, and discovery.

## Purpose

Deliver authoritative quiz state over WoW's available communication routes without visible chat play or a dependency on Orbit.

## Implementation

`Identity.lua` owns native identity capture and `NormalizeName`, including realm completion and secret guards. `Transport.lua` exposes `Quiz.Comms`: bounded encoding, fragmentation, queues, result tags and retries for addon whispers.

`Session.lua` owns host/participant membership, readiness, answer revisions, immutable round views and recovery. Protocol 7 sends pack metadata plus bounded rule definitions, not question answers or source evidence. Participants validate rule identity, clock, computed points and optional streak/winner metadata before persisting and acknowledging a result.

`Discovery.lua` advertises through a silent realm lobby and available guild/group routes. Setup selections join the same session owner used by commands. Application callbacks connect transport delivery/errors to sessions and host outcomes; received lifetime totals never enter host standings.

## Gotchas

- All players need protocol 7 (`ORBITQUIZ7` / `ORBITQUIZDISC7`). The host plus 16 remote players is the supported maximum.
- Lobby visibility follows realm/channel rules. Guild/group visibility does not guarantee cross-realm whispers; channel failure falls back to available routes. There is no Battle.net relay.
- Only one session may be active. Joining another host leaves the prior game or stops local hosting; lost departure packets can occupy the old host slot for its 35-second lease.
- Membership nonces, bounded retries and round identities fence stale answers and acknowledgements. Locked-answer recovery must not retime or replace the accepted selection.
- The canonical rules key cannot change within a session. Reject mismatched repeated question/result metadata rather than mutating an existing round.
- Fastest means correct final accepted selection. Exact ties use normalized name, then player key; a current unexpired remote peer must be ready at closure. No correct answer means no winner.
- Timer expiry alone is not a result. Local gold selection is not host acceptance; refresh/reconnect must not replay feedback or award a duplicate receipt.
- Bounded retries cannot guarantee unseen results after leaving, host switching or logout. Checksums/rule keys identify data, not authenticated competitive scores.
- Visible chat publication and chat-answer listeners are retired. Discovery/probe packets and addon-message restrictions are separate concerns and remain supported.

## Secrets

Check native names, GUIDs, payloads, sender names, lobby IDs and restriction flags before string operations or comparisons. Chat lockdown suspends both sending and parsing independently of unit secrecy.

## References

- [Application lifecycle](../App/README.md), [saved receipts](../Data/README.md), and [two-client verification](../Docs/QUICKSTART.md).
- [Transport/session/discovery simulations](../Dev/Tests/README.md).
- Blizzard reference: `../../wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua` and `RestrictedActionsDocumentation.lua`; workspace skill `wow-secrets`.

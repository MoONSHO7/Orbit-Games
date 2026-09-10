# Application

## Description

Startup declarations, game-type registration, application text and coordination for Orbit-Games.

## Purpose

Keep WoW events and user commands at the application boundary while each registered game type owns its rules, session payloads, saved mode state and renderer.

## Implementation

`Init.lua` establishes the shared `Games` namespace, exports `OrbitGames` and declares the source version. `Core/GameTypes.lua` owns descriptor registration and the selected default, including each mode's Results title/presenter contract. Cards and Quiz register complete descriptors; Quiz remains the explicit default and companion packs use only `OrbitGames.Quiz:RegisterPack`.

`Locale.lua` supplies only shared shell text and errors. Each descriptor exposes its own locale table; Cards and Quiz keep player-facing domain language inside their mode directories.

`Runtime.lua` owns application lifecycle and mode dispatch. `ADDON_LOADED` validates `OrbitGamesDB`, initializes shared communication and registers the minimap launcher. SharedMedia registration reapplies appearance to every created mode HUD so inactive fallback fonts can recover before the next mode switch. `PLAYER_LOGIN` starts discovery and the ticker. `ENCOUNTER_STATE_CHANGED` re-queries `C_InstanceEncounter.IsEncounterInProgress`; Runtime combines that boss state with chat availability into one automatic-wait transition for the active mode. The launcher and `/og` or `/orbitgames` commands share the same initialization gate. Commands perform actions or navigate the addon UI: `status` and unknown commands open Games, while mode aliases choose Host or Results. Reports update controller/setup notices and never write to the visible chat frame.

The selected game type receives host, join, tick, view and command work. Browser joins pass the complete discovery advert to the selected session so it can validate its activity contract. Quiz records score receipts; Cards projects recipient-safe table state and records completed settlements. Shared UI and networking derive neither.

## Gotchas

- The selected game type and its normalized setup are immutable for a live session.
- Automatic waiting is boss-encounter-specific, not ordinary combat. Manual pause ownership always survives automatic blockers, and recovery waits until both the encounter and any chat restriction have ended.
- Logout/reload end membership and cancel the ticker. Discovery remains available between games, not after logout.
- Media initialization may notify synchronously and again after another addon loads; bind callbacks before registration.
- There is no chat-output fallback for status, help or errors. Keep actionable failures in the shared notice lane and command feedback in the page or HUD that owns it.
- Release automation stamps `Games.version` only in its runner checkout. The TOC and runtime version must agree in the package.

## Secrets

WoW restriction events and native addon/error arguments are checked before comparison or parsing. Runtime coordinates chat-lockdown suspension; modes do not receive unchecked native payloads.

## References

- [Cards](../Modes/Cards/README.md), [Quiz](../Modes/Quiz/README.md), [networking](../Network/README.md), [persistence](../Data/README.md) and [UI](../UI/README.md).
- [Offline checks](../Dev/Tests/README.md) and [release workflows](../.github/workflows/README.md).

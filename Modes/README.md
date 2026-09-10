# Game types

## Description

Bundled Orbit-Games modes, each registered as one complete rules, session, persistence and presentation boundary.

## Purpose

Let the shared application discover and coordinate games without learning any mode's domain language or internal state.

## Implementation

Each mode creates its namespace below `Modes/<Name>/`, loads all owners, then registers one descriptor through `Core/GameTypes.lua`. The descriptor supplies an immutable ID and protocol version plus these owners:

- controller: lifecycle, ticking, notices, automatic-wait transitions and runtime-error recovery;
- session: membership, routed payload validation, active/joined queries and send failures;
- storage: pure normalization followed by binding only after the root save validates;
- advert: projection from mode state to generic session/activity/title/phase/occupancy/capacity/joinability fields; the shell stamps descriptor identity and protocol;
- commands and locale: delegated UI/action aliases and player-facing errors;
- UI: host page, settings page, HUD and Results presenter; the shell supplies Host body/footer layout, while `resultsTitle` supplies the mode-owned tab label.

The shared shell calls only the validated descriptor contract. Mode owners may collaborate within their directory; shared `App/`, `Data/`, `Network/` and `UI/` code must not name a mode or inspect its internal fields.

Cards and Quiz each register only after all of their owners exist. Add another bundled mode in the same sequence and place its TOC entries before `App/Runtime.lua`.

## Gotchas

- Mode IDs and protocol versions are wire and SavedVariables contracts. Preserve IDs; bump the protocol before changing payload meaning.
- `storage:Normalize` must not mutate a singleton or saved input. Root persistence binds every normalized mode only after the complete database validates.
- Only one mode can own an active session. Selection is locked until the current controller and session are idle.
- Mode commands may navigate owned UI or perform an action, but must not introduce a visible-chat output path.
- Companion content may use a mode's explicit public API. The game-type registry itself is an internal boot contract, not an extension API for later-loaded addons.

## References

- [Cards](Cards/README.md), [Quiz](Quiz/README.md), [application](../App/README.md), [persistence](../Data/README.md), [networking](../Network/README.md) and [shared UI](../UI/README.md).

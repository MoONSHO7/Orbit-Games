# Orbit-Games

## Description

A standalone World of Warcraft 12.1.0 multiplayer party-game framework. It bundles Quiz and an eight-seat Cards mode whose first variant is host-authoritative No-Limit Texas Hold'em.

## Purpose

Keep hosting, discovery, shared settings and persistence independent from any one game's rules. Every player installs Orbit-Games; only a Quiz host needs the selected question packs. Orbit itself is not a dependency.

Install `Orbit-Games` under `World of Warcraft/_retail_/Interface/AddOns/`. Click the Orbit minimap icon or use `/og` or `/orbitgames`; right-click the icon for Settings and drag it to save its position. Commands, status and errors stay inside the addon UI rather than writing to the visible chat frame. See the [quickstart](Docs/QUICKSTART.md) and [Quiz pack guide](Docs/PACKS.md).

## Implementation

    App/                  Startup, shared text and runtime coordination
    Core/                 Generic game-type descriptor registry
    Modes/Cards/          Card foundation, Texas Hold'em, private session projections and table UI
    Modes/Quiz/           Quiz rules, packs, model, scores, session protocol and HUD
    Network/              Shared identity, transport and game discovery
    Data/                 OrbitGamesDB validation and per-mode persistence
    UI/                   Shared setup shell, controls, media and minimap launcher
    Assets/               Bundled media
    Dev/                  Source-only previews, tests and companion-addon example
    Docs/                 Player and Quiz pack-author guides
    Libs/                 Unmodified embedded media and minimap libraries
    .github/workflows/    Validation, alpha tagging and publishing

`Orbit-Games.toc` is the load-order authority: libraries → shared namespace/text/registry → mode-owned domain and storage → shared network/UI → mode presentation and registration → runtime. Source checkouts load the development preview last; packaged releases omit it.

`App/Init.lua` exposes `OrbitGames`; `Core/GameTypes.lua` creates its game-type registry. Shared owners discover and route a selected game; `Modes/Quiz/` owns every question, answer, rule, score and Quiz session transformation. Quiz companion addons register through `OrbitGames.Quiz:RegisterPack` and declare `## Dependencies: Orbit-Games`.

`Data/Store.lua` owns `OrbitGamesDB`; mode-owned state lives below `modes`, including the Quiz payload at `modes.quiz` and Cards setup/session results at `modes.cards`. Releases install one addon named `Orbit-Games`.

Warcraft Lore contains 1,183 game-based questions with four to six choices. Its source-only comic archive is excluded from play and releases.

## Gotchas

- All participants need the generic `ORBITGAMES1` / `ORBITGAMESDISC2` protocols and the selected activity version. Capacity belongs to the mode: Quiz allows 17 total players and Cards allows eight seats.
- Cards clients receive only public state and their own hole cards until showdown, but the host owns the authoritative deck. Every Cards amount is a whole Gold value; whether a session represents real stakes is a private social agreement, and the addon never transfers, escrows or verifies gold.
- Quiz pack IDs, question IDs, rules keys, scoring versions and receipt identities remain stable across schema upgrades. Stored results must never be rescored or merged.
- `/og status` opens Games, `/og packs` opens Quiz Host, and `/og scores` or Cards `/og results` opens the mode's Results page. Archived Quiz league and 100-point standings remain preserved without a UI, command or chat projection.
- Question packs are trusted executable Lua. Schema validation does not sandbox downloaded addons.
- Native rendering, network delivery and SavedVariables disk timing still require in-game verification.

## Secrets

Native identity and incoming communication are guarded before Lua operations. Chat lockdown suspends parsing and sending. Quiz deadlines and UI timing are addon-owned data; no protected unit-state arithmetic is required.

## References

- [Application](App/README.md), [game-type contract](Modes/README.md), [Cards](Modes/Cards/README.md), [Quiz](Modes/Quiz/README.md), [networking](Network/README.md), [persistence](Data/README.md) and [UI](UI/README.md).
- [Playing-card asset provenance and MIT licence](Assets/Cards/README.md).
- [Development and tests](Dev/README.md), [release workflows](.github/workflows/README.md) and [MIT licence](LICENSE).

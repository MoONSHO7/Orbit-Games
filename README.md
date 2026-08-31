# Orbit-Quiz

## Description

A standalone World of Warcraft 12.1.0 quiz framework with a lean answer widget, discovered games, personal progress, and file-based question packs.

## Purpose

Authors define questions and rules; hosts select a quiz and press Start. Every player installs Orbit-Quiz, but only the host needs the selected packs. Orbit itself is not a dependency.

Install this folder as `World of Warcraft/_retail_/Interface/AddOns/Orbit-Quiz/`. Open `/oq` or `/orbitquiz` to host, join, change appearance, or position the widget. See the [quickstart](Docs/QUICKSTART.md) and [pack-authoring guide](Docs/PACKS.md).

## Implementation

The repository is organized by responsibility:

    App/                  Startup, localized text, and runtime coordination
    Game/                 Pack registry, rules, scoring, and quiz state
    Network/              Identity, addon-message transport, sessions, discovery
    Data/                 Saved settings, personal scores, historical archives
    UI/                   Setup window, answer widget, reusable controls, fonts
    Packs/WarcraftLore/    Bundled questions, registration, and provenance
    Dev/                  Source-only preview, tests, companion-addon example
    Docs/                 Player and pack-author guides
    Libs/                 Unmodified embedded SharedMedia dependencies
    .github/workflows/    Validation, alpha tagging, and publishing

`Orbit-Quiz.toc` owns the framework's load order: libraries → namespace/text → rules/registry/content → scoring/storage/model → networking/UI → runtime. Source checkouts load the development preview last; packaged releases omit it. Third-party quiz addons load their files through their own TOCs.

`App/Runtime.lua` composes gameplay, networking, persistence and presentation. `Game/` owns author rules and host-observed outcomes; `Network/` carries validated questions/results; `Data/` retains confirmed personal progress. `UI/` renders these owners' state. Media changes notify the application through a callback rather than reaching into UI consumers.

The public `OrbitQuiz:RegisterQuestionPack` API connects independently maintained quiz addons through their own `## Dependencies: Orbit-Quiz` TOCs. Authors use their own folders/repositories and releases; no core contribution or TOC edit is required. The [authoring guide](Docs/PACKS.md) includes complete starter files and the [copyable template](Dev/Examples/Orbit-Quiz-Pack-Example/README.md) is self-contained.

Warcraft Lore contains 1,183 game-based questions with four to six choices. Its source-only comic archive is excluded from play and releases. Each module's README records its data flow and maintenance constraints.

## Gotchas

- All participants need protocol 7. Sessions support the host plus 16 remote players; realm/channel restrictions can prevent discovery or whispers across realms. There is no Battle.net relay.
- Only host-confirmed closed results award points. This is trusted social play, not anti-cheat or latency-compensated competition; personal statistics are not verified rankings.
- Question packs are trusted executable Lua, loaded through companion-addon TOCs. WoW cannot discover arbitrary JSON/YAML/text files; keep custom packs outside the core addon so updates do not overwrite them.
- Store schema 6, personal-score schema 2, stable pack IDs, rule identities, and historical scoring are independent contracts. A folder cleanup must not migrate or rescore saved data.
- Native rendering/network delivery and SavedVariables disk timing need in-game verification. Offline tests do not certify those boundaries.
- After updating, use `/reload` and verify `/oq`, hosting/joining and appearance. The TOC remains the loading authority; old root-level Lua copies are no longer used.

## Secrets

Native identity and incoming communication are guarded before Lua operations. Chat lockdown suspends parsing/sending. Quiz deadlines and UI timing are addon-owned data; no protected unit-state arithmetic is required.

## References

- [Application](App/README.md), [gameplay](Game/README.md), [networking](Network/README.md), [persistence](Data/README.md), and [UI](UI/README.md).
- [Bundled packs](Packs/README.md), [development and tests](Dev/README.md), and [release workflows](.github/workflows/README.md).
- [MIT licence](LICENSE) covers first-party code; [bundled libraries](Libs/README.md) retain their upstream licences.

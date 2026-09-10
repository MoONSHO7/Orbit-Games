# Guides

## Description

Player setup and Quiz pack-authoring guides for Orbit-Games.

## Purpose

Keep user-facing instructions separate from module maintenance contracts.

## Implementation

[QUICKSTART.md](QUICKSTART.md) covers installation, the shared game browser, Quiz, Texas Hold'em, preferences, save migration and verification. [PACKS.md](PACKS.md) gives complete files for an independently distributed Quiz companion addon using `## Dependencies: Orbit-Games` and `OrbitGames.Quiz:RegisterPack`.

## Gotchas

- Quiz and Cards are registered game types, not the application boundary. Generic instructions say game; question/answer/pack rules remain Quiz terminology and poker terms remain inside Cards.
- Commands in these guides use `/og` or `/orbitgames` to navigate UI or perform actions. Source-only preview commands use `/ogdev`; neither command family writes help or status to the visible chat frame.
- Development tests and templates are source-only, but the pack guide is self-contained for an installed release.

## References

- [Project map](../README.md), [development](../Dev/README.md) and [Warcraft Lore provenance](../Modes/Quiz/Packs/WarcraftLore/SOURCES.md).

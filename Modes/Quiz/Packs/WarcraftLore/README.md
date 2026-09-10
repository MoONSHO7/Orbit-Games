# Warcraft Lore Quiz pack

## Description

Sourced, file-based Warcraft lore questions shipped as the bundled Quiz pack in Orbit-Games.

## Purpose

Provide an immediately playable Quiz while exercising the same public registration contract used by independently installed packs.

## Implementation

The root TOC loads `Assemble.lua`, then the era/work files and `Register.lua`. The local `Quiz.Lore:Add` helper attaches source and era to compact rows. `Register.lua` submits `warcraft-lore` through `OrbitGames.Quiz:RegisterPack` with explicit rules, then releases assembly data.

Content version 2 contains 1,183 game-based questions covering the RTS games, original WoW and every released expansion through Midnight. Every question has four to six choices, one correct index, difficulty, era and host-retained source evidence. Live packets omit answer keys and source URLs.

`Archive/Comics` preserves 247 retired questions for recovery. It is absent from the TOC and excluded from packages. The stable `warcraft-lore` pack ID retains prior personal scores through the product rename without rescoring.

## Gotchas

- Content is explicitly `enUS`; it is not translated with the host UI.
- Difficulty does not alter timing or points. Era files are maintenance units, not separate selections.
- Warcraft Lore rules v1 use 15-second questions, 3-second results and a capped consecutive-correct bonus. Rules live in `Register.lua`, not host settings.
- Content changes retain a ruleset row; changed resolved rules create a separate row. Earlier pre-ruleset points are never assigned guessed rules.
- Question IDs are permanent. Keep an ID for wording corrections and allocate a new one for a different question.
- Explanations name the answer, never its letter or position, because choices shuffle.
- New bundled files require explicit TOC entries before `Register.lua`.
- Source URLs are editorial evidence, not runtime dependencies or automatic fact checks.

## References

- [Pack contract](../../../../Docs/PACKS.md), [scope and provenance](SOURCES.md) and [comic archive](Archive/Comics/README.md).
- `ResearchEarly.md` and `ResearchMiddle.md` — source maps and continuity notes.
- `../../../../Dev/Tests/Lore.py` and `../../../../Dev/Tests/Lore.lua` — structural catalogue checks, not lore fact-checking.


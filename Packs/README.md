# Bundled Question Packs

## Description

Sourced, file-based Warcraft lore questions shipped as one bundled pack with Orbit-Quiz.

## Purpose

Provide an immediately playable quiz while using the same registration contract as independently installed packs.

## Implementation

The core TOC loads `LoreData.lua` after the registry, then the era/work data files. Each `Quiz.Lore:Add` call attaches its source URL and era to short question rows. `WarcraftLore.lua` performs the single `Quiz:RegisterQuestionPack` call for `warcraft-lore`, then releases the temporary assembly table. The registry validates and copies all entries before exposing Warcraft Lore in the host's pack selector.

Content version 2 contains 1,183 game-based questions covering the RTS games, original WoW and every released expansion through Midnight, including zones, areas and history. Comics, graphic novels, manga and digital comics are excluded. Every question has four to six choices, one correct index, difficulty, era and a source retained by the host. Live questions include pack/difficulty/era metadata but not the answer key or source URL. `SOURCES.md` owns coverage and continuity decisions.

`Archive/Comics` preserves the 247 retired questions and their research byte-for-byte for recovery. It is absent from the TOC and excluded by `.pkgmeta`; neither normal gameplay nor draft catalogue assembly loads it. The pack ID remains `warcraft-lore`, so prior personal scores survive the content-version change without rescoring.

## Gotchas

- Content has an explicit `enUS` locale; it is not silently translated into the host's UI language.
- Difficulty does not alter timing or points. All tiers remain mixed in the single pack; era files are maintenance units, not separate in-game selections.
- Question IDs are permanent content identifiers, not positions. Keep an existing ID when correcting wording; use a new ID for a different question.
- Use short, factual explanations. Choice shuffling means explanations must name the answer, never its letter or position.
- Keep the complete catalogue within the registry's 2,000-question limit. New bundled files must be listed before `WarcraftLore.lua`; WoW cannot discover them by scanning this folder.
- Source URLs are editorial evidence, not remote data dependencies or automatic fact checks. Resolve contradictory or retconned facts before admitting a question.
- New third-party packs belong in companion addon folders, not in this directory: core updates can replace bundled files.

## References

- `../PACKS.md` — public schema and installation contract.
- `SOURCES.md` — scope, difficulty rubric, review provenance and continuity exclusions.
- `Archive/Comics/README.md` — source-only recovery archive, never part of the shipped catalogue.
- `ResearchEarly.md` and `ResearchMiddle.md` — game-era source maps and continuity notes.
- `../.tests/Lore.py` and `../.tests/Lore.lua` — catalogue audit and two-cycle gameplay checks; these do not prove lore accuracy.

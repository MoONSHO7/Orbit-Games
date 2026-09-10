# Quiz pack example

## Description

A standalone companion-addon template for authors who distribute their own Orbit-Games Quiz packs.

## Purpose

Keep third-party Quiz content independent of the framework repository.

## Implementation

Copy [Orbit-Games-Quiz-Pack-Example](Orbit-Games-Quiz-Pack-Example/README.md), rename its folder and TOC, then customize its metadata, rules and questions. Its `## Dependencies: Orbit-Games` header establishes load order before `OrbitGames.Quiz:RegisterPack` runs.

## Gotchas

- Nested addons are not discovered inside `Dev/Examples/`.
- Ship only the finished companion addon; hosts install Orbit-Games separately.
- Restart WoW after installing a new addon folder. `/reload` cannot discover a folder that was absent at launch.
- Keep the folder and TOC basename identical and assign a stable, unique pack ID.
- Packs are trusted executable Lua; review unfamiliar addons before installing them.

## References

- [Pack authoring](../../Docs/PACKS.md) — complete format, limits and validation behavior.

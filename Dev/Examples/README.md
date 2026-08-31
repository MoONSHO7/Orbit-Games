# Question Pack Examples

## Description

A standalone companion-addon template for authors who maintain and distribute their own quiz projects.

## Purpose

Keep third-party quizzes independent of the core repository. Authors do not need to submit packs, fork Orbit-Quiz, or edit its TOC.

## Implementation

Copy [Orbit-Quiz-Pack-Example](Orbit-Quiz-Pack-Example/README.md) into a separate project folder, rename its folder/TOC, and customize its questions, rules and metadata. Its self-contained README covers installation and independent distribution. The explicit `## Dependencies: Orbit-Quiz` header loads the framework before the pack calls its public registration API; the pack never imports private core modules.

## Gotchas

- Nested addons are not discovered inside another addon's `Dev/Examples/` directory.
- This directory stores templates, not an installation or submission location for third-party packs. Ship only your finished companion addon; hosts install Orbit-Quiz separately.
- Close the game before installing a new addon folder, then launch it and enable the pack on the AddOns screen. Do not rely on `/reload` to discover a newly created directory.
- Rename both the folder and matching TOC filename when making your own pack. Give the pack a unique `id` as well.
- This is trusted Lua code. Review packs before installing them.

## References

- [pack authoring](../../Docs/PACKS.md) — complete format, limits, and error behavior.

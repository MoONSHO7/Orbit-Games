# Question Pack Examples

## Description

A copyable companion addon demonstrating the public question-pack format.

## Purpose

Let authors add packs as files without an in-game editor or changes to Orbit-Quiz's own TOC.

## Implementation

Copy `Orbit-Quiz-Pack-Example` out of this directory into the game's `Interface/AddOns/` directory beside `Orbit-Quiz`. The companion TOC depends on Orbit-Quiz and loads its own question file, which calls the public registry.

## Gotchas

- Nested addons are not discovered inside another addon's `Examples/` directory.
- Close the game before installing a new addon folder, then launch it and enable the pack on the AddOns screen. Do not rely on `/reload` to discover a newly created directory.
- Rename both the folder and matching TOC filename when making your own pack. Give the pack a unique `id` as well.
- This is trusted Lua code. Review packs before installing them.

## References

- `../PACKS.md` — complete format, limits, and error behavior.

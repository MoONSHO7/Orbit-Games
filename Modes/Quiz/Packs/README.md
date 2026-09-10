# Bundled Quiz packs

## Description

First-party Quiz content packaged with Orbit-Games.

## Purpose

Keep authored questions and editorial evidence separate from the Quiz registry and runtime model.

## Implementation

Each bundled pack owns a folder. [Warcraft Lore](WarcraftLore/README.md) assembles its era files and registers one pack through `OrbitGames.Quiz:RegisterPack`, the same public contract used by companion addons. The root TOC explicitly controls assembly, content and registration order.

## Gotchas

- WoW does not scan directories: every loaded file needs a TOC entry.
- Question IDs, pack IDs and canonical rules are public data contracts; moving source files does not change them.
- Warcraft Lore's recovery archive is source-only and excluded by `.pkgmeta`.
- Third-party packs belong beside Orbit-Games as companion addons, not inside this update-owned directory.

## References

- [Pack authoring](../../../Docs/PACKS.md), [Quiz mode](../README.md) and [copyable example](../../../Dev/Examples/README.md).


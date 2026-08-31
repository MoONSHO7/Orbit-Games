# Bundled Packs

## Description

First-party question content packaged with Orbit-Quiz.

## Purpose

Keep content and its editorial evidence separate from the pack registry and game engine.

## Implementation

Each bundled pack owns a folder. [Warcraft Lore](WarcraftLore/README.md) assembles its era files and registers one pack through the same public API available to companion addons. The root TOC explicitly lists assembly, content and registration in that order.

## Gotchas

- WoW does not scan directories: every loaded file needs a TOC entry.
- Question IDs, pack IDs and rules are public data contracts; moving source files does not change them.
- Warcraft Lore's recovery archive is source-only and excluded in `.pkgmeta`. Do not add it to the TOC.
- Third-party packs belong beside Orbit-Quiz as companion addons, not in this update-owned folder.

## References

- [Pack authoring](../Docs/PACKS.md), [registry/gameplay](../Game/README.md), and [copyable example](../Dev/Examples/README.md).

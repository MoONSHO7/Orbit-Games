# Retired comic questions

## Description

Recoverable source archive of the 247 comic, graphic-novel, manga and digital-comic questions removed from Warcraft Lore content version 2.

## Purpose

Preserve prior editorial work without including comic-based questions in the playable or packaged addon.

## Implementation

The original question files and `ResearchComics.md` retain their contents and permanent IDs. Nothing here is listed in the production TOC; `.pkgmeta` excludes `Modes/Quiz/Packs/WarcraftLore/Archive`. Offline audits may load the files only in an isolated namespace to confirm no retired ID remains active.

## Gotchas

- This is not an installable pack and has no TOC.
- Archived Lua still expects the old local `Quiz.Lore:Add` assembly helper. Reading a file does not register it.
- Existing scores remain under `warcraft-lore`; removal never recalculates history or recycles IDs.

## References

- [Active pack](../../README.md), [active scope](../../SOURCES.md) and [retained provenance](ResearchComics.md).


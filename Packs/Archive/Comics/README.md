# Retired comic questions

## Description

Recoverable source archive of the 247 comic, graphic-novel, manga and digital-comic questions removed from Warcraft Lore content version 2.

## Purpose

Preserve prior editorial work without including comic-based questions in the playable or packaged addon.

## Implementation

The original question files and `ResearchComics.md` retain their contents and permanent IDs. Nothing in this directory is listed in the production TOC; `.pkgmeta` excludes `Packs/Archive` from releases. The offline audit may load these files into an isolated namespace solely to check that no retired ID remains in the bundled pack.

## Gotchas

- This is not an installable question pack and has no TOC. Do not reconnect these files to the main pack as part of routine maintenance.
- The archived Lua still expects the old `Quiz.Lore:Add` assembly helper. Reading a file does not register a pack; executing it outside an isolated audit is not supported.
- Existing earned scores are preserved under `warcraft-lore`; removing source questions does not recalculate history or recycle their IDs.

## References

- `../../README.md` and `../../SOURCES.md` — active game-based pack scope and maintenance contract.
- `ResearchComics.md` — original manga and digital-comic provenance, retained as historical notes.

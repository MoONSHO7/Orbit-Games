# Development

## Description

Source-only previews, offline regressions and a copyable Orbit-Games Quiz companion example.

## Purpose

Keep test fixtures and author tooling out of runtime modules and published addons.

## Implementation

`Preview.lua` loads last inside the TOC's `@do-not-package@` block. `/ogdev games` supplies deterministic discovery listings through the shared setup shell; `/ogdev cards` drives the real Hold'em model and table with seven local computer seats; `/ogdev toasts` exercises the actual Quiz streak renderer and sound queue; `/ogdev off` cancels every preview. These commands are silent: the browser, table or toast HUD is their feedback, and an unavailable or unknown request leaves the current visual state unchanged.

[Tests](Tests/README.md) execute the production TOC in mocked Lua 5.1 runtimes. Run `python -B -u Dev/Tests/run.py` and `stylua --check --output-format Summary .` from the addon root. [Examples](Examples/README.md) demonstrates `OrbitGames.Quiz:RegisterPack`.

[The September 2026 review](REVIEW.md) records reproduced correctness defects, cleanup and the remaining architecture recommendations.

`Assets/BuildCardAtlas.py` reproducibly fetches the pinned MIT playing-card source and builds the compact landscape `Assets/Cards/PlayingCards.png` plus an original primitive-drawn dealer chip; its offline `--check` verifies the committed atlas, fixed rank typography, metadata, decoration and licence without network access.

## Gotchas

- The entire `Dev` folder is excluded by `.pkgmeta`; the TOC block independently removes the preview entry.
- Preview data never enters discovery packets, active sessions or SavedVariables.
- Source-only commands must not add a chat-frame output path that the packaged runtime does not have.
- The Cards harness injects a transient table driver and feeds the production Fisher–Yates shuffle from a fixed private xoshiro128** stream with rejection-sampled bounds. Restarts reproduce the deck sequence without consuming or reseeding WoW's shared random stream; deterministic legal actions still yield the player's seat for five seconds before autoplay.
- Quiz toast previews refuse live membership and end through the renderer's queue-drained callback.
- Card assets are pinned to one upstream commit. Update the source commit, licence, generated metadata and visual review together.
- The companion example is copied into an author's own project and depends on Orbit-Games; it is not a pack-submission workflow.
- Offline checks cannot certify rendered pixels, live realm delivery or SavedVariables disk timing.

## References

- [Quickstart](../Docs/QUICKSTART.md), [release packaging](../.github/workflows/README.md), [shared UI](../UI/README.md) and [Quiz mode](../Modes/Quiz/README.md).

# Development

## Description

Source-only preview tools, offline regressions, and a copyable companion-addon example.

## Purpose

Keep test fixtures and author tooling out of the runtime modules and published addon.

## Implementation

`Preview.lua` loads after application startup inside the TOC's `@do-not-package@` block. `/oqdev games` supplies 32 deterministic listings through `UI:SetGamePreview`, reusing the real browser rows and scrollbar. `/oqdev toasts` supplies seven sample 5–11 streaks through `Widget:SetStreakPreview`, exercising the actual renderer and SFX clips. `/oqdev off` cancels both previews and restores discovery.

[Tests](Tests/README.md) execute the production TOC in mocked Lua 5.1 runtimes. Run `python -B -u Dev/Tests/run.py` from the addon root with Lupa installed; run `stylua --check --output-format Summary .` for formatting. [Examples](Examples/README.md) demonstrates the public pack contract.

`SoundVolumes.py` builds the 10–90% Ogg variants in `Assets/Sounds/Volume` from the six original MP3s. Run `python -B Dev/SoundVolumes.py` with FFmpeg/FFprobe installed after changing originals; `--check` verifies decoding, duration and gain without rewriting files. The generated audio ships with the addon; the tool does not.

## Gotchas

- The entire `Dev` folder is excluded by `.pkgmeta`; the TOC block separately removes the preview load entry. Validate both raw-source and packaged loading.
- Preview state is opt-in and reset on reload. Dummy listings never enter network discovery or SavedVariables; their Join callbacks are inert and Refresh cannot advertise them.
- Preview activation must not change active games, membership, accepted answers or live discovery data.
- Toast previews refuse active hosting/joined/joining sessions. They show a read-only HUD without opening setup or requesting discovery, then end through the renderer's queue-drained callback, not a separate timer. Starting/joining a real game cancels them; no preview identity enters receipts or SavedVariables.
- The companion example is a starter for authors' own projects, not a pack-submission workflow. Copy it out, customize and distribute it separately; its required Orbit-Quiz dependency is the only integration. Nested development addons are not discovered by WoW.
- Offline checks cover behavior and wiring, not rendered pixels, live realm reachability or SavedVariables disk timing.

## References

- [Quickstart and in-game checks](../Docs/QUICKSTART.md), [release packaging](../.github/workflows/README.md), and [UI](../UI/README.md).

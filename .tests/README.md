# Orbit-Quiz offline checks

## Description

Offline Lua 5.1 checks for question packs, continuous quizzes, personal pack progress, authoritative sessions, addon communication, and widget-only orchestration.

## Purpose

Exercise deterministic behavior without a World of Warcraft client. Native networking, restricted-state behavior, SavedVariables disk timing, and rendered UI still need two-client in-game verification.

## Implementation

Run `python .tests/run.py` from the addon folder with Python and `lupa.lua51` available. `run.py` compiles every Lua file, rejects UTF-8 BOMs and visible-chat APIs in loaded scripts, loads the real TOC into a fresh mocked runtime for each suite, and invokes its returned test function.

`Scoring.lua` covers the exponential penalty, signed tenth-point arithmetic, rounding boundaries and negative blind-guess expectation for four to six choices. `Model.lua` covers fixed host clocks, final-selection timing, continuous shuffled cycles, schema-6 archive preservation and mixed historical scoring versions, independent appearance saves, and retired chat-setting cleanup. `Packs.lua` covers transactional registration and validation; the runner repeats it for every supported locale and loads the example companion addon separately.

`PersonalScores.lua` covers account-wide per-pack accumulation across hosts, pack/scoring-version metadata, penalties and unanswered counts, schema 1–5 migration without guessed backfills, and transactional rejection of inconsistent saves. It exercises durable duplicate/out-of-order receipt handling, compressed ranges during continuous play, Unicode host identities, bounded recent records, explicit capacity failures and detached score summaries. These checks verify accounting, not anti-cheat security.

`Comms.lua` tests codec/fragmentation, queue bounds, retries, tagged result isolation and restricted input. `Runtime.lua` exercises host progression, personal persistence without new league writes, interruption recovery, and the absence of visible chat/publication. `Session.lua` checks protocol-6 pack/winner metadata, host-controlled session totals, exact score/timing validation, receipt acknowledgements and bounded recovery, native identity and old-membership fences.

`Discovery.lua` isolates native lobby/guild/group routes, bounded advertisements, expiry, prefix failures, secret payloads, and restrictions. `Interface.lua` checks one-column answer text, the smaller pack heading, question/answer font hierarchy, owned-font shadows, the close-spaced two-pixel gradient countdown, edit-only movement and screen bounds. Animation checks cover host-confirmed feedback, replay suppression, lifecycle cancellation and reserved score/footer space. Wrap regressions audit zero-height measurement and sufficient pixel-rounded height when reusing short/long labels. Setup checks retain native chrome, controls, pooled rows and thin scrollbars.

`Appearance.lua` checks compact Orbit-style `Scale`/`Font` rows, detached native Edit Mode callbacks, live drag/selection updates, all 31 scale values, screen bounds and normalized positioning. Font checks use the real bundled SharedMedia library and cover previews, search, bounded row reuse, saved selection, fallback/retry, late registration and unchanged question/answer state. Rendering and glyph coverage still require the game.

`HUDPolish.lua` exercises text-only press/release and cancellation, pack/answer typography, shadow padding, and the reserved winner popup. It checks confirmed-result gating, winner animation timing/replay prevention and lifecycle resets independently of personal score feedback.

`VisualStability.lua` checks that answer submissions, acknowledgements and repeated question packets leave geometry, text layout, allocations and inactive feedback untouched. Press feedback is confined to the pressed label, never its hit area or surrounding layout. Coverage includes physical-grid placement, divider joins, outlines, scroll rounding, batched layout and cancellation of old scroll motion on resets/new questions. Injected native-range fluctuations test the explicit-content boundary, not an observed C++ rendering sequence.

`Development.lua` verifies the opt-in sample game list, long/multilingual fixture variety, full-list scrolling, row-pool reuse, inert Join callbacks, real-list restoration, and isolation from discovery, active sessions, and saved data. The runner also loads a release-style TOC with development blocks stripped to check that normal gameplay works without the preview module or command.

Template-aware stubs distinguish native button font strings from independent labels and record layout/visibility calls. Owned Font objects inherit/copy backing properties; `Font:SetFont` deliberately has no success return while FontString probes do. Synthetic font metrics scale by role/file and exercise height/line-limit constraints, not rasterized glyphs or whether a shadow is visibly rendered. Gradient snapshots verify colors/reuse; animation mocks record timing/lifecycle only. Sliders retain native callback/state behavior; search boxes retain text/focus/clear scripts. Tests leave the `Orbit` global absent and reject an Orbit TOC dependency.

`Network.py` exchanges real encoded packets between isolated runtimes: discovery, UTF-8 fragmentation, dropped/reordered answers/results/acknowledgements, reconnects and peer expiry, host switches, sixteen participants, and automatic fifteen-second questions with three-second result breaks. Personal progress checks separate session totals from pack records and cover cross-host/mixed-pack attribution and reloads. Winner checks compare all recipients, changed/final answers and delayed/replayed results without rewinding HUD state. These are simulated clients, not live delivery.

`Lore.py` audits the bundled catalogue's 1,000–2,000-question size, permanent IDs, distinct prompts/choices, four-to-six answer counts, byte limits, all 17 game eras, difficulty/source metadata and source-derived word budgets. Retired comic IDs/publication metadata are rejected; isolated archive loading verifies disjoint IDs while TOC/package checks keep it out of play and releases. Draft assembly reads only active era files. `python .tests/Lore.py --draft --review` flags similar or reciprocal questions for editorial review. This is structural/provenance validation, not automatic lore fact-checking.

`Lore.lua` runs the entire bundled catalogue through two continuous shuffled cycles, checking answer remapping, metadata, final-selection timing, retries, scores, bounded state and cycle completeness. It also reloads version-1 personal progress alongside content version 2, hosts the trimmed pack and verifies that old scores/duplicate protection survive without resetting, rescoring or creating a second pack identity.

Variable-choice regressions exercise 4/5/6-answer registration, E/F selections, remapping, history compatibility, six text-target reuse, long-content bounds, same-round reconnects, older-protocol rejection and source/answer-key privacy. Sixteen-client maximum-payload simulations cover the transport queue, readiness window and the fixed fifteen-second answering clock.

## Gotchas

- Supply deterministic random functions for reproducible deck/choice tests; continuous cycles must not grow per-round identity storage.
- Keep the production TOC as the load-order authority. Widget strings must exist before UI modules capture them.
- A mocked addon-message acknowledgement proves code behavior, not Blizzard permission, realm reachability, or native timing.
- Guessing checks assume a uniformly random final choice without information about the answer; they do not detect cheats or guarantee outcomes for individual guesses. Historical fixture expectations must remain frozen when live scoring changes.
- Frame stubs check control wiring, pooled reuse, edit-only movement, pixel-grid arithmetic and scroll contracts, not rasterized alignment, native font rendering, asynchronous layout or combat behavior.
- Offline locale-code coverage exercises pack behavior; it does not mean all player-facing strings are translated.
- Do not add live-client verification claims based solely on a passing offline run.
- TOC development markers are comments to WoW. Test both raw-source loading and packager-style omission; `.pkgmeta` must also exclude the development file.

## References

- `../Game.lua`, `../Scoring.lua`, `../Store.lua`, and `../PersonalScores.lua` — session model, archives and personal progress.
- `../Packs.lua` — question-pack registry.
- `../Identity.lua`, `../Comms.lua`, `../Session.lua`, and `../Main.lua` — player identity, widget protocol, and orchestration.
- `../UI.lua` and `../Widget.lua` — setup and answer UI boundaries.
- `../QUICKSTART.md` — commands and two-client in-game verification checklist.

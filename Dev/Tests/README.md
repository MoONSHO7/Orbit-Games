# Orbit-Quiz offline checks

## Description

Offline Lua 5.1 checks for pack-owned rules, continuous/finite quizzes, personal ruleset progress, authoritative sessions, addon communication, and widget-only orchestration.

## Purpose

Exercise deterministic behavior without a World of Warcraft client. Native networking, restricted-state behavior, SavedVariables disk timing, and rendered UI still need two-client in-game verification.

## Implementation

Run `python Dev/Tests/run.py` from the addon folder with Python and `lupa.lua51` available. `run.py` compiles every Lua file, rejects UTF-8 BOMs and visible-chat APIs in loaded scripts, checks exact-case runtime paths and source/release exclusions, loads the real TOC into a fresh mocked runtime for each suite, and invokes its returned test function.

`Rules.lua` covers normalization, canonical encode/decode, detached values, allowed bounds and malformed input. `Scoring.lua` covers frozen legacy arithmetic, authored rewards/penalties, capped streak bonuses, rounding boundaries and bundled-rule long-run guessing balance for four to six choices. `Model.lua` covers author-owned clocks, answer locking, final-selection timing, streak resets, shuffled/ordered cycles, finite limits and voids, plus schema-6 archive preservation, independent appearance saves and retired chat-setting cleanup. `Packs.lua` checks transactional registration, rule isolation and compatible-only All packs; the runner repeats it for every supported locale.

`CompanionPack.py` reads the example addon's own TOC, requires only Orbit-Quiz, and loads its scripts in a distinct addon namespace against a production-only core. A registration-only public API catches accidental reliance on private core members. Checks retain authored questions/rules, preserve bundled content and existing selection, reject automatic game/session startup, and explicitly host the new quiz without development code or Orbit. The guide's first TOC/Lua examples also register an independently named pack in a separate production runtime, without the template. Run `python Dev/Tests/CompanionPack.py` for this focused check.

`PersonalScores.lua` covers account-wide pack/ruleset accumulation across hosts, personal schema-1→2 migration, untouched v2 archives, v3 streak receipts and separate display rows. It retains top-level schema 1–5 upgrade coverage without guessed backfills. Checks exercise transactional rejection, durable duplicate/out-of-order receipts, compressed ranges during continuous play, Unicode host identities, bounded recent records, explicit capacity failures and detached summaries. These checks verify accounting, not anti-cheat security.

`Comms.lua` tests codec/fragmentation, queue bounds, retries, tagged result isolation and restricted input. `Runtime.lua` exercises rule-driven host progression, finite final reveals/voids, personal persistence without new league writes, interruption recovery and the absence of visible chat/publication. `Session.lua` checks protocol-7 rules/streak/winner metadata, immutable same-ID questions, session rule fences, exact score/timing validation, receipt acknowledgements, native identity and old-membership fences.

`Discovery.lua` isolates native lobby/guild/group routes, bounded advertisements, expiry, prefix failures, secret payloads and restrictions. `Interface.lua` checks read-only rule summaries, incompatible All packs, separate score rows, one-column answers, typography/shadows, variable-duration gradients and locked input. Animation checks cover host-confirmed feedback, replay suppression, lifecycle cancellation and reserved score/footer space. Wrap regressions audit zero-height measurement and pixel-rounded height. Setup checks retain native chrome, controls, pooled rows and thin scrollbars.

`Appearance.lua` checks compact Orbit-style `Scale`/`Font` rows, detached native Edit Mode callbacks, live drag/selection updates, all 31 scale values, screen bounds and normalized positioning. Font checks use the real bundled SharedMedia library and cover previews, search, bounded row reuse, saved selection, fallback/retry, late registration and unchanged question/answer state. Rendering and glyph coverage still require the game.

`HUDPolish.lua` exercises text-only press/release and cancellation, typography, shadow padding and the reserved winner popup. It checks confirmed-result gating, animation timing/replay prevention and lifecycle resets independently of personal feedback. Large authored rewards/penalties exercise preallocated score width across fonts, scales and viewports without moving text on selection or reveal.

`VisualStability.lua` checks that answer submissions, acknowledgements and repeated question packets leave geometry, text layout, allocations and inactive feedback untouched. Press feedback is confined to the pressed label, never its hit area or surrounding layout. Coverage includes physical-grid placement, divider joins, outlines, scroll rounding, batched layout and cancellation of old scroll motion on resets/new questions. Injected native-range fluctuations test the explicit-content boundary, not an observed C++ rendering sequence.

`Development.lua` verifies the opt-in sample game list, long/multilingual fixture variety, full-list scrolling, row-pool reuse, inert Join callbacks, real-list restoration, and isolation from discovery, active sessions, and saved data. The runner also loads a release-style TOC with development blocks stripped to check that normal gameplay works without the preview module or command.

Template-aware stubs distinguish native button font strings from independent labels and record layout/visibility calls. Owned Font objects inherit/copy backing properties; `Font:SetFont` deliberately has no success return while FontString probes do. Synthetic font metrics scale by role/file and exercise height/line-limit constraints, not rasterized glyphs or whether a shadow is visibly rendered. Gradient snapshots verify colors/reuse; animation mocks record timing/lifecycle only. Sliders retain native callback/state behavior; search boxes retain text/focus/clear scripts. Tests leave the `Orbit` global absent and reject an Orbit TOC dependency.

`Network.py` exchanges real encoded packets between isolated runtimes: discovery, fragmentation, dropped/reordered messages, reconnects, host switches and sixteen participants. It covers variable clocks, locked-answer recovery after a lost confirmation, stable repeated opening deadlines, shared capped streaks, finite quizzes and a fresh final reveal after restriction recovery. Progress checks separate session totals from ruleset records across hosts, compatible mixed packs and reloads; winner/results cannot rewind the HUD or award twice. These are simulated clients, not live delivery.

`Lore.py` audits the bundled catalogue's 1,000–2,000-question size, permanent IDs, distinct prompts/choices, four-to-six answer counts, byte limits, all 17 game eras, difficulty/source metadata and source-derived word budgets. Retired comic IDs/publication metadata are rejected; isolated archive loading verifies disjoint IDs while TOC/package checks keep it out of play and releases. Draft assembly reads only active era files. `python Dev/Tests/Lore.py --draft --review` flags similar or reciprocal questions for editorial review. This is structural/provenance validation, not automatic lore fact-checking.

`Lore.lua` runs the entire bundled catalogue through two continuous shuffled cycles, checking remapping, metadata, final-selection timing, retries, scores, bounded state and completeness. It reloads old personal progress alongside content version 2 and the new rules, checking that original scores/duplicate protection survive unchanged while new results enter their ruleset bucket under the same pack identity.

Variable-choice regressions exercise 4/5/6-answer registration, E/F selections, remapping, history compatibility, six text-target reuse, long-content bounds, same-round reconnects, older-protocol rejection and source/answer-key privacy. Sixteen-client maximum-payload simulations cover transport bounds, the twenty-second readiness window and a full authored answering clock after readiness.

## Gotchas

- Supply deterministic random functions for reproducible deck/choice tests; continuous cycles must not grow per-round identity storage.
- Keep the production TOC as the load-order authority. The consolidated application strings must exist before registry and UI modules capture them.
- A mocked addon-message acknowledgement proves code behavior, not Blizzard permission, realm reachability, or native timing.
- Guessing checks assume uninformed uniform final choices; long-run streak checks are not a guarantee about individual rounds or arbitrary author rules. Historical fixture expectations must remain frozen when live scoring changes.
- Frame stubs check control wiring, pooled reuse, edit-only movement, pixel-grid arithmetic and scroll contracts, not rasterized alignment, native font rendering, asynchronous layout or combat behavior.
- Offline locale-code coverage exercises pack behavior; it does not mean all player-facing strings are translated.
- Do not add live-client verification claims based solely on a passing offline run.
- TOC development markers are comments to WoW. Test both raw-source loading and packager-style omission; `.pkgmeta` must also exclude the entire `Dev` folder.

## References

- `../../Game/Rules.lua`, `../../Game/Game.lua`, `../../Game/Scoring.lua`, `../../Data/Store.lua`, and `../../Data/PersonalScores.lua` — author contract, model, archives and progress.
- `../../Game/PackRegistry.lua` — question-pack registry.
- `../../Network/Identity.lua`, `../../Network/Transport.lua`, `../../Network/Session.lua`, and `../../App/Runtime.lua` — player identity, widget protocol, and orchestration.
- `../../UI/Setup.lua` and `../../UI/Widget.lua` — setup and answer UI boundaries.
- `../../Docs/QUICKSTART.md` — commands and two-client in-game verification checklist.

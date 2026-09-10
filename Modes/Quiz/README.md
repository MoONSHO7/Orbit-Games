# Quiz game type

## Description

The first registered Orbit-Games mode: question-pack registration, deterministic rounds, scoring, receipts and a compact Q/A HUD.

## Purpose

Contain every Quiz-specific rule and transformation behind one mode boundary so the application can host other games without depending on questions or answers.

## Implementation

`Locale.lua` owns Quiz text and inherits the small shared shell vocabulary. `PackRegistry.lua` implements the public `OrbitGames.Quiz:RegisterPack` contract and detached pack/question queries. Bundled and companion addons use the same validation path.

`Rules.lua` normalizes answer/reveal timing, selection changes, ordering, repetition, limits and scoring into a canonical rules key. `Scoring.lua` applies version-3 signed result deltas, exact arithmetic and the zero floor while retaining frozen historical calculators. `Model.lua` snapshots a selected pack and owns deck progression, accepted answers, per-result-clamped standings, streaks, voids and finite completion.

`Advert.lua` projects Quiz as activity `quiz` version 1 with host-plus-16 capacity. The registered Quiz game protocol is version 2. `Network/Session.lua` owns membership, question/result validation and demand-driven standings over the generic transport; result deltas may be signed, but cumulative totals must be nonnegative. The host answers a standings request with one authoritative revisioned snapshot, and clients replace presentation state without feeding that snapshot into scoring or receipt persistence. `Network/Streaks.lua` synchronizes compact milestone speaker identities. `Data/PersonalScores.lua` persists confirmed Quiz receipts and signed per-pack accounting below `OrbitGamesDB.modes.quiz`, then projects every Personal score at the zero floor.

`UI/Widget.lua`, `UI/StreakToasts.lua`, `UI/ScoreTooltip.lua` and `UI/Scores.lua` render Quiz state supplied by the mode. The question timer keeps a two-physical-pixel backdrop visible through expiry and results while its four-pixel gradient fill overhangs by one pixel above and below. The right lane permanently shows the player’s current total; each confirmed signed delta rises and fades over that same lane without replacing the total. Hovering the total requests current standings and shows up to 100 ranked players in a Quiz-owned private tooltip; no standings download occurs before that hover. Confirmed toast queues survive transient waits, pauses and restrictions; natural game completion retains the final result HUD until its voices drain, while explicit cancellation still stops playback. The descriptor exposes `UI/Scores.lua` as the generic Results presenter and labels that tab “Scores”. Its dropdown contains only Personal score and Current game; compact score/statistic rows omit passive bottom guidance and visible rule-description paragraphs, and the scrolling list uses the reclaimed space. `/og scores` opens that page and `/og packs` opens Host, where the notice lane exposes the first pack-validation error. Archived league and 100-point standings remain preserved for migration and recovery without a UI or chat projection. `Packs/WarcraftLore/` registers the bundled content through the public pack API.

## Gotchas

- Pack Lua is trusted executable addon code. Registration validation is not a sandbox.
- Rules are copied at registration and session start; hosts cannot override them.
- Quiz pack IDs, question IDs, canonical rules keys and scoring versions remain stable across the Orbit-Quiz → Orbit-Games migration.
- Only the final host-accepted selection scores. Same-choice retries do not retime it; leaving does not erase it.
- Wrong or unanswered closed rounds reset streaks; voids do not. Every new Quiz game starts at zero.
- A hosted-session total is clamped after every finalized delta. A wrong result at zero creates no hidden live debt, so the next correct result increases that current-game total immediately.
- Personal per-pack accounting is different: it retains signed receipts underneath its zero-floored projection so delayed and out-of-order results remain order-independent. A Personal penalty at zero can therefore offset later Personal gains without changing the live session total.
- Historical scoring is frozen. Never run archived receipts through current pack rules.
- Receipt ranges retain gaps for delayed results; replacing them with a highest-seen ID would discard older earned awards.
- Archived league and 100-point standings are preservation-only compatibility data; do not restore them to commands, chat output or the Scores dropdown.
- The HUD grows from its saved visible edge: left/right horizontal halves combine with top/down or bottom/up growth without reordering choices. While `/og` edit mode is open, only the literal question text can initiate movement; the full frame, background and answers do not drag. A native drag release saves once, then rerenders from the resolved edge without replaying confirmed feedback.
- Feedback requires a confirmed result and independent replay identity; reconnects and UI refreshes must not replay it. `UI/SoundMedia.lua` maps milestones directly to the six original MP3s. The saved Sounds toggle preserves legacy mute preferences; loudness follows WoW SFX. Muting cancels only the current owned sound, leaving visuals and queued announcements intact.
- Standings snapshots are host-reported, replacement-only presentation data. Duplicate, stale or conflicting revisions must never change scores, persist receipts or replay feedback.

## References

- [Pack schema](../../Docs/PACKS.md), [bundled content](Packs/WarcraftLore/README.md), [shared networking](../../Network/README.md), [persistence](../../Data/README.md) and [shared UI](../../UI/README.md).
- [Companion example](../../Dev/Examples/README.md) and [offline checks](../../Dev/Tests/README.md).

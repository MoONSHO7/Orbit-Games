# Gameplay

## Description

The question-pack contract and deterministic host-side quiz model.

## Purpose

Keep authored content, rule validation, scoring and round progression independent of frames, networking and saved-data mutation.

## Implementation

`PackRegistry.lua` implements the public `OrbitQuiz:RegisterQuestionPack` API and detached pack/question queries. It validates an entire pack before admission and records localized registration failures from `App/Locale.lua`. Bundled and companion packs use the same contract.

`Rules.lua` validates author-owned timing, answer changes, ordering, repetition, game length and rewards, then creates detached snapshots and canonical encoded identities. `GetPackRules` offers All packs only when every selected pack resolves to identical rules.

`Game.lua` snapshots rules and owns deck progression, final selections, standings, streaks, voids and finite completion. Closed results include sorted `{name, streak}` entries in `streakMilestones` from five correct answers onward. Its caller supplies time/randomness; UI and transport do not drive the model. `Scoring.lua` applies version-3 scoring and preserves the explicit version-2 calculator and deterministic standings ordering.

## Gotchas

- Pack Lua is trusted executable addon code. Validation protects registry consistency, not a sandbox; registration is all-or-nothing.
- Rules are copied at registration and game start. Hosts cannot override them. Omitted rules preserve legacy-compatible defaults without streak bonuses.
- Shuffled cycles use every question once and avoid adjacent cross-cycle repeats. Ordered cycles preserve authored order. A finite cap counts closed rounds; one-pass exhaustion ends even when its last question was voided.
- Only the final changed selection scores, using its host-receipt time. Same-choice retries do not retime it; leaving does not erase an accepted answer.
- Streaks advance only at closure. Wrong/unanswered closed rounds reset them, while voids do not; each new game starts at zero. Milestones announce every correct answer from five onward, independently of whether the pack awards streak bonus points.
- Warcraft Lore's capped streak preserves negative long-run uniform-guess expectation for four to six choices. Arbitrary author rules need their own balance review; scores may be negative.
- Historical scoring stays frozen. The legacy constructor and archive calculators must not silently use current author rules.
- Difficulty/category/era are descriptive metadata, not alternate scoring modes.

## References

- [Pack schema and limits](../Docs/PACKS.md), [bundled content](../Packs/WarcraftLore/README.md), and [companion example](../Dev/Examples/README.md).
- [Persistence](../Data/README.md) and [offline rule/scoring/model checks](../Dev/Tests/README.md).

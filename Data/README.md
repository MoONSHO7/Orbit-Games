# Persistence

## Description

Saved setup/appearance, account-wide personal quiz progress, and preserved historical league archives.

## Purpose

Keep authoritative receipt accounting and save migrations separate from gameplay, networking and presentation.

## Implementation

`Store.lua` owns top-level `OrbitQuizDB` schema 6, setup normalization, independent widget settings/position, persistent question counters and historical league readers. Runtime binds the restored database during the addon's `ADDON_LOADED` event.

`PersonalScores.lua` owns its own subtree: schema 1→2 migration preserves original scoring-version-2 records while current receipts accumulate by stable pack ID and canonical rules key. Compressed host/session/round identity ranges prevent duplicate credit, including delayed older receipts.

`GetScoreRows` projects detached original/ruleset rows directly from canonical saved stats for the UI. Compatibility `GetPack`/`GetPacks` summaries remain available, but mixed-rule totals are not comparable rankings. The host's current-game standings live in the model and start afresh.

## Gotchas

- Only confirmed closed results affect personal scores. WoW flushes SavedVariables on normal logout/reload; crashes can lose progress. Local characters share totals, not other computers/accounts.
- A content-version update retains a pack/ruleset row; changed resolved rules create a separate row even if the author reuses a revision. Never rescore historical totals or infer personal pack totals from old league archives.
- Invalid, unsupported or capacity-limited saved data must fail without silently resetting it. Existing legacy arithmetic and read migrations remain frozen.
- Duplicate tracking spans pack/rules combinations within each host/session. Persist the identity alongside credit; do not clear ranges merely because a question left the visible recent history.
- Returned summaries/rules are detached. UI changes must not mutate canonical saved stats; sorting is case-insensitive title, pack ID, then Original rules before canonical rule keys.
- Widget placement and appearance save independently from host setup. Reflow alone must not rewrite normalized anchors.
- Retired chat settings/passwords are discarded during normalization. Archived public/whisper data and the internal `PUBLIC` bucket remain storage compatibility contracts, not playable chat modes.
- Retain archive readers, validation, and legacy fixture-writing behavior during structural cleanup. No schema or global SavedVariables name changes accompany the new folders.

## References

- [Gameplay and scoring](../Game/README.md), [receipt transport](../Network/README.md), [appearance](../UI/README.md).
- [Persistence and upgrade regressions](../Dev/Tests/README.md); workspace skill `orbit-settings` for shared principles (Orbit-Quiz owns its independent database).

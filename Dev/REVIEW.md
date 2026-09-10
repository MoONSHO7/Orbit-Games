# Orbit-Games review — 6 September 2026

The code has a good foundation, but the original passing suite did not establish correctness. This review found and fixed four classes of defect in Cards. Quiz's scoring, receipt persistence and migration paths have stronger behavioral coverage; I found no additional confirmed defect there in this pass. This is a source review and offline validation, not a proof that every path is correct.

## Correctness fixes

| Priority | Reproduction and effect | Change |
| --- | --- | --- |
| P1 | An eight-player table repeatedly cancels partially transmitted snapshots. Several participants never assemble a complete update and keep reconnecting. | `Modes/Cards/Network/Session.lua` finishes queued projections before replacing them. A real fragmented-transport simulation now reaches every seat. |
| P1 | A delayed preflop all-in can arrive after the host automatically checks and starts the flop, where the same player acts first. The host applies it to the wrong street. | Protocol 3 includes the observed model revision in each wager. The host rejects stale actions and returns an actionable error. |
| P1 | Repeating a join resets `lastSequence`; replaying an already accepted check can therefore act again. Duplicate welcomes also replace an active table's phase with `waiting`, while older join attempts can displace a newer membership. | Same-request joins retain their peer and acknowledgement state; older generated requests are rejected. Duplicate welcomes preserve the view, and direct joins pin their accepted host session. |
| P2 | With a minimum bet of 100, an opening all-in of 60 incorrectly permits a regular raise to 100. Crossing the opening minimum with another short all-in can also inflate the subsequent minimum increment. | `Betting.lua` consistently uses the current wager plus the last full increment: the regular raise must total at least 160. Bet, raise and all-in share one chip-commit/update path. |

The betting correction follows [Poker TDA rules 43 and 47](https://www.pokertda.com/view-poker-tda-rules/) and the [TDA administrator's clarification that completing a bet belongs to limit poker](https://www.pokertda.com/forum/index.php?topic=1287.30). The previous engine test asserted the incorrect completion rule and has been corrected.

Cards participants must all update for protocol 3. Quiz's protocol and persisted schemas are unchanged.

## Structure and SOLID

| Principle | Assessment | Recommended next change |
| --- | --- | --- |
| Single responsibility | Strong in the deck, evaluator, pots, betting, models, ledger and storage boundaries. Weaker in the large renderers and Quiz session module. | Extract Cards player-row lifecycle/animation and wager controls from `UI/Table.lua`; extract Quiz wire decoding from `Network/Session.lua`. Split by ownership, not arbitrary line counts. |
| Open/closed | The top-level game descriptor is a useful extension boundary. The Cards variant registry is only partially implemented as one. | Before adding a second card variant, put its codec and configuration adapter in its descriptor. Cards session/controller code currently names Texas Hold'em directly. |
| Liskov substitution | There is little inheritance to assess. Both bundled modes satisfy the registered application contract and execute through the shared runtime. | Exercise future modes through that contract. Do not introduce inheritance just to satisfy a checklist. |
| Interface segregation | Separate controller/session/storage/presentation owners are appropriate. The complete mode descriptor is reasonable for bundled games. | Keep requirements tied to real shell calls. Avoid turning the descriptor into a general service container. |
| Dependency inversion | Pure models accept rules, time and random sources. Mode orchestration and renderers still reach global singleton owners directly. | Extend dependency injection only at actual replacement boundaries, especially the second Cards variant and isolated session tests. Avoid an across-the-board framework rewrite. |

`Modes/Cards/UI/Table.lua` is the clearest next structural target: player-row reuse and animation, wager selection, drag geometry and settlement presentation change for different reasons. `Modes/Quiz/Network/Session.lua` similarly mixes wire validation with membership and delivery state. These are maintainability concerns, not additional reproduced runtime failures. The larger extractions remain recommendations; this pass kept runtime changes focused on confirmed defects and the shared wager path.

## Cleanup completed

- Removed the preview's 4,096-deck fixed-seed distribution thresholds. They checked one deterministic sample against broad magic bounds, not randomness in production. Kept permutation validity, consecutive-deck differences, restart determinism and global-random isolation.
- Removed repeated preview styling assertions already owned by Cards UI tests, and the runner's duplicate descriptor-field inventory. Removed the assertion requiring snapshot cancellation, which rewarded the delivery defect.
- Removed 20 inline explanatory comments across 13 authored files. All remaining text in those files is identical to the review-start snapshot. Retained key native and receipt contracts in module READMEs; vendored libraries and question provenance were untouched.
- Consolidated wager validation/accounting and removed duplicated full-bet state. Removed an extra broadcast after actions that the controller had already broadcast.
- Condensed the Cards README's implementation narrative and updated network/test documentation.

## Evidence and limits

- The original complete suite passed before fixes; new reproductions exposed gaps despite that result.
- The original Cards session fails the full-table transport reproduction. The corrected session passes with seven remote participants and retains hole-card privacy.
- The complete offline Lua 5.1 suite passes after the runtime changes and cleanup. The extended Cards transport suite additionally covers delayed wagers and old join requests after reconnect.
- StyLua's whole-project check passes; `git diff --check` reports no whitespace errors.
- A separate diagnostic run completed 1,000 varied-stack hands and 6,385 legal transitions with chip conservation at every action and settlement. This was an additional check of the consolidated betting path, not another permanent sampling suite.
- Offline stubs cannot certify native rendering, physical drag behavior, chat restrictions, real realm delivery or SavedVariables disk timing. Question provenance checks do not fact-check all 1,183 lore questions. Release credentials and publication were not exercised.

The pre-existing working-tree rename and Cards implementation were preserved. Changes remain uncommitted for in-game verification.

# Persistence

## Description

Orbit-Games account state, shared preferences and isolated per-game-type data.

## Purpose

Keep root save validation separate from mode-owned accounting and presentation.

## Implementation

`Store.lua` owns `OrbitGamesDB`. The selected mode, nonempty Host-to audience selection and minimap preferences live at the root; game-owned data lives under `modes[modeId]`. Host audiences normalize to detached `server`, `guild` and `party` booleans before every registered storage owner validates its mode data without side effects. The store binds data only after the entire root validates. The schema-7 Quiz payload is `modes.quiz`; Cards setup, table placement, counters and bounded session results live at `modes.cards`.

`Modes/Quiz/Data/PersonalScores.lua` validates Quiz receipts, keeps signed per-pack accounting and projects detached score rows whose totals floor at zero. Compressed host/session/round ranges continue to prevent duplicate credit across reloads and delayed results.

`Modes/Cards/Data/Store.lua` validates whole-Gold settings, local table appearance and completed-session results. Schema 4 adds the bounded SharedMedia font key; its schema-1/2 migration still removes legacy currency/funded/paid fields and retains their raw integer amounts as the new whole-Gold unit, while schema 3 gains the font default without relaxing malformed host data. `Ledger.lua` accounts only for buy-ins, rebuys, final balances and net results; it never accesses WoW money or trade state.

## Gotchas

- Root validation rejects malformed or newer-version data before binding any mode or replacing `OrbitGamesDB`.
- Keep pack IDs, rules keys, scoring versions, receipt identities and archive arithmetic byte-for-byte compatible.
- Only confirmed closed Quiz results affect personal scores. WoW writes on normal logout/reload; crashes can lose recent progress.
- The saved signed Quiz balance may be negative so wrong guesses at zero still offset later gains; public pack summaries and score rows never expose less than zero.
- Shared preferences and mode data must not replace one another during a partial save.
- Older roots without Host-to data default to all three audiences. Malformed or empty selections reject atomically rather than producing an undiscoverable host.
- The live minimap table is retained by LibDBIcon; do not copy or replace it after registration.

## References

- [Cards accounting](../Modes/Cards/README.md), [Quiz accounting](../Modes/Quiz/README.md), [network transport](../Network/README.md), [shared UI](../UI/README.md) and [regressions](../Dev/Tests/README.md).

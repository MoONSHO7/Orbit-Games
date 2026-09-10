# Cards game type

## Description

A reusable playing-card boundary whose first registered variant is deterministic, host-authoritative No-Limit Texas Hold'em.

## Purpose

Keep card identity, deck handling and variant rules independent from sessions, persistence and presentation so future card games can reuse the same foundation without inheriting poker mechanics.

## Implementation

`CardCatalog.lua` defines the immutable 52-card identity contract. `Deck.lua` validates an injected order or applies an injected Fisher-Yates random source without consulting time or global randomness.

`Poker/HandEvaluator.lua` ranks five-to-seven card sets with one canonical comparable score. `Variants/TexasHoldem/` owns normalized table rules, legal betting transitions, side-pot settlement, the hand state machine and recipient-safe state projections.

`Controller.lua` supplies seats, an injected deck, hand identity and the application-driven host clock to the model. Chat restrictions and boss encounters pause that clock through the shared automatic-wait contract; manual pause can take ownership without being resumed by later recovery. `Network/Protocol.lua` validates membership/actions; protocol 3 binds each wager to the observed model revision. `Session.lua` keeps join retries idempotent, preserves accepted views across duplicate welcomes and finishes queued fragmented projections before scheduling replacements. Networking never decides poker legality.

`Data/Store.lua` owns table setup, local appearance, placement, counters and bounded completed-session results. Appearance keeps the table scale, SharedMedia font key and recent-action visibility independent from Quiz. `Ledger.lua` accounts for fixed buy-ins, rebuys and final balances; it records no payment claims. `Gold.lua` formats and parses the engine's whole-Gold unit. `Variants/TexasHoldem/Rules.lua` maps the saved blind rate to a buy-in-relative small blind and derives the big blind at exactly twice that value.

`UI/HostPage.lua` places its options on the shared Host form boundary. Five uniform rows keep full-width fields, the paired Seats/Action timer cells and the native blind slider aligned without changing Blizzard-owned widget behavior.

`UI/Table.lua` renders recipient state through a stable community row, identity-keyed player rows, projected legal actions and local SharedMedia fonts. `UI/CardArt.lua` owns native card transitions. The table derives settlement labels and the canonical-five reveal only from visible cards; it accepts a transient source-preview driver without involving production sessions or saves. `ResultsPage.lua` presents local session balances and net results; `/og results` opens it without writing to chat.

## Gotchas

- One Cards amount unit is one whole Gold. Buy-ins range from 1,000 to 10,000,000 Gold; the blind slider spans 0.5â€“2.5% of the buy-in in 0.1% steps, producing 100-big-blind through 20-big-blind tables. The big blind is always twice the small blind, and an odd pot chip is one Gold.
- The addon never transfers, escrows or verifies WoW gold; players decide privately whether a session is just for fun.
- Every eligible table enters discovery and seats players without funding approval. Completed results describe table balances, not real-world payment state.
- Cards command feedback remains in its table, setup notice or Results page; no command writes a status or ledger to the visible chat frame.
- Projection wire schema 2 retains the deprecated currency/funding slots for structural continuity, but the Cards transport and activity versions reject older copper-valued clients rather than reinterpret their amounts.
- The host can inspect authoritative state, including every card. Recipient projections prevent participant clients from receiving hidden information but cannot make a playing host trustworthy.
- Pending snapshots must finish all fragments; cancelling them on every broadcast starves participants at a full table. The next scheduled snapshot picks up the latest state.
- Known seats may reconnect during a hand. A peer that stays disconnected through settlement is automatically sitting out before another hand can begin.
- Short all-ins change the call amount but preserve the last full raise increment. A 60 opening all-in with a 100 minimum requires a raise to at least 160, not a completion to 100. Reopening is tracked per seat from its last acted wager level.
- The regular wager slider spans only the inclusive `minTarget`/`maxTarget` range received in the actor projection. A short all-in below that minimum remains available through the separate All-in action and must never be folded into the slider.
- Odd chips are awarded clockwise from the button's left among tied winners. Folded contributions remain eligible pot funding but never win a pot.
- Unfinished hands are not resumable persistence records; only a completed settlement is a durable checkpoint.
- Settlement winners come from gross payouts; refunds never identify a winner. Player-row settlement values are net of that seat's committed Gold.
- Ties and side pots can produce several payout winners without one client-visible main-pot owner. Every category remains in the result text, but the canonical-five reveal and extra hole-card pair appear only for a sole showdown winner; uncontested fold wins keep their cards private.
- Resolve canonical-five concealment before the board's single `CardArt:Transition` call. Applying both the normal face state and settlement back state during one refresh restarts native flips indefinitely.
- Player-row transitions are keyed to stable player identity, not display index or revision. Repeated projections preserve direction; seatless placeholder overlays retain the last authoritative list; row reuse waits for zero height, while a session change or table hide establishes a nonanimated baseline. Native scale and allocated row height both remain linear so a mid-motion reversal resumes without a snap.
- Decoded participants receive settlement amounts on each seat rather than the host's settlement wrapper. The table treats either shape as settled and freezes any retained deadline while a projection is paused.
- `CardArt.lua` retains a reusable empty-slot state, but active hands show undealt community slots as anonymous backs. Edit mode also shows five anonymous community backs between hands so its only drag target remains visible, then hides them when edit mode closes. `inHand` permits two anonymous hole-card backs without exposing private IDs; folding removes the containing player row without manufacturing a card identity.
- `stack` is the internal Hold'em accounting field and wire key. Player-facing text always calls the same value Gold.

## References

- [Mode contract](../README.md), [shared networking](../../Network/README.md), [card-art provenance](../../Assets/Cards/README.md) and [offline checks](../../Dev/Tests/README.md).
- [Poker TDA rules 43 and 47](https://www.pokertda.com/view-poker-tda-rules/) govern minimum increments and reopening; [TDA clarification](https://www.pokertda.com/forum/index.php?topic=1287.30) excludes completing short bets in no-limit games.

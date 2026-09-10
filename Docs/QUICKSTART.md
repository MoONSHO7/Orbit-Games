# Getting started with Orbit-Games

## Install

Copy the `Orbit-Games` folder into `World of Warcraft/_retail_/Interface/AddOns/` and enable it. Orbit-Games targets WoW 12.1.0 (`120100`) and does not require Orbit. It includes Quiz and Cards; every player needs the same Orbit-Games activity version, while only a Quiz host needs extra question packs. There is no visible-chat mode, login line, command help or status/results output in the chat frame.

Reload for changes to existing loaded files. If a newly installed addon folder is not listed on the AddOns screen, restart the client so WoW detects it.

The Orbit logo beside the minimap opens Orbit-Games: **left-click** toggles the window, **right-click** opens Settings, and **drag** repositions the icon. `/og` and `/orbitgames` open the same window; `/og settings` opens Settings and `/og status` opens Games. Quiz `/og packs` opens Host and `/og scores` opens Scores; Cards `/og results` opens Results. Unknown commands also return to Games instead of printing help. The launcher supports LibDataBroker displays and minimap-button collectors.

The bundled Quiz type includes **1,183 game-based Warcraft Lore questions**, covering the RTS games and every released WoW expansion through Midnight. It mixes easy, medium, hard and very hard questions with four to six choices and contains full story spoilers; see [the coverage and source guide](../Modes/Quiz/Packs/WarcraftLore/SOURCES.md).

Create an independently distributed Quiz pack using [PACKS.md](PACKS.md). Its TOC declares `## Dependencies: Orbit-Games`, and its Lua calls `OrbitGames.Quiz:RegisterPack`. The guide and [copyable example](../Dev/Examples/Orbit-Games-Quiz-Pack-Example/README.md) are self-contained. Only install Lua addons from trusted authors.

## Choose who can discover your game

The **Host to** dropdown appears above **Game type** and applies to both Quiz and Cards. It is a multi-select with all three audiences enabled on a fresh install:

- **Server** advertises through the silent `OrbitGamesLobby` custom addon channel. This is best-effort discovery among clients who successfully join that channel, not a guaranteed realm-wide broadcast.
- **Guild** advertises through the native guild addon-message route.
- **Party** advertises through whichever party, raid and instance-chat routes are available for the host's current group.

At least one audience must remain selected. The selection saves between sessions and locks, along with Game type, while you are hosting or joined to a game. Stop or leave the current game before changing it.

WoW does not expose a safe native addon-message multicast to Friends or Battle.net friends, so there is no Friends option or Battle.net relay. Host-to filters where advertisements and withdrawals are sent; **Refresh** and automatic discovery queries still search every available route. It controls who can discover the listing, not who is authorized to join: a compatible, reachable player who already knows the character name can still try `/og join Name-Realm`.

## Host a quiz

1. Open `/og` and select **Host**.
2. Choose a question pack. The quiz author defines the rules; hosts cannot override them. Warcraft Lore allows **15 seconds** to answer and **3 seconds** to reveal the result. The default game name works without typing. Game names label listings; personal scores belong to the question's pack and ruleset. If a companion pack fails registration, `/og packs` opens this page and its notice lane shows the first retained validation error.
3. Click **Start game** in the Host footer. Your Q/A widget appears automatically; you can answer there without joining yourself.
4. Other players find you under **Games** and click **Join**. Your Host-to selection determines which server, guild or group audiences receive the listing; allow a few seconds for it to arrive.

Warcraft Lore uses every question, shuffling both questions and choices. Each question runs for fifteen seconds, then reveals the answer for three seconds before preparing the next question automatically. Connected players synchronize before the answering clock opens. At the end of the pack it starts another shuffled cycle; the last question is not immediately repeated when there is more than one question. One-question packs necessarily repeat.

Other packs can use different clocks, ordered questions or choices, first-answer locking, a single pass or a fixed question limit. A finite quiz automatically ends after its final result break. **All packs** is available only when every installed pack has identical rules; it never blends incompatible scoring or timing. Display preferences such as Scale and Font remain your own settings.

Warcraft Lore content version 2 removes the previous 247 comic-based questions without resetting earned scores. After updating an active host, `/reload` and start a new game. Source checkouts retain the removed files under `Modes/Quiz/Packs/WarcraftLore/Archive/Comics`; releases exclude that archive.

**Pause** voids an unfinished question; **Resume** starts a fresh one. **Stop game** ends the loop. Closing `/og` does not pause or stop the Quiz.

## Host or join Texas Hold'em

1. Open `/og`, choose **Cards**, then **Host**. Enter a whole-Gold buy-in from **1,000** to **10,000,000**, then choose the blinds with the slider. It ranges from a standard 100-big-blind table to a fast 20-big-blind table; the big blind is always twice the displayed small blind. Choose two to eight seats and an action timer, then open the table.
2. Eligible tables appear in **Games** while they have a free seat. Players can also use `/og join Name-Realm` as a diagnostic fallback; joining seats them immediately when the table is available.
3. Decide among yourselves whether those Gold values are only for fun or represent a private real-gold agreement. Orbit-Games never opens or reads a trade, transfers gold, escrows a stake, marks payments or proves that payment happened.
4. Once at least two players are seated, the host deals. For a regular bet or raise, drag the thin wager line directly beneath the four actions between its legal minimum and your maximum total; the exact selected Gold replaces the third action label. Click that numeric action to submit the wager. **All-in** remains separate so short all-ins below the normal minimum stay available. The host revalidates every action, runs the 30-second default clock and automatically checks when legal or folds on timeout. **Sit out next hand** replaces a poker-ambiguous Skip action; rebuys happen only between hands.

The table supports No-Limit Texas Hold'em cash sessions, including heads-up order, burns, side pots, uncalled refunds, short all-ins, cumulative reopening and clockwise odd chips. It does not currently implement tournaments, antes, straddles, rake, spectators, run-it-twice or host migration.

Only the acting player receives their legal-action set. Each participant receives public seats/board/action history plus their own hole cards; non-folded showdown hands are then revealed. The deck and burn cards never leave the host. This limits participant-side inspection but cannot stop a modified host from viewing or changing its authoritative deck, so use a trusted host—especially for any gold-denominated session.

Completed sessions create bounded local Results showing each player's buy-in, final Gold and net table result. They contain no funding or payment flags and are not proof that real gold changed hands. An active hand must finish before the host can close and record the session. Cards `/og results` opens the same Results page without printing a duplicate ledger to chat.

Cards has its own local **Settings** appearance. **Table scale**, **Font** and **Recent actions** save independently from Quiz; Font uses the same searchable SharedMedia catalogue and applies immediately to all table text without changing Blizzard or setup-window fonts. If its provider is missing, Cards falls back to Blizzard while retaining the selection for restoration when the provider returns.

## Join and answer a quiz

1. Open `/og` or `/orbitgames`.
2. In **Games**, click **Join** beside a host. **Refresh** searches again. No host name or channel command needs to be typed.
3. When answers open, click one of the four to six answer lines. There are no visible buttons or text-entry boxes.
4. If the pack allows answer changes, you can change your selection before the deadline. The latest change accepted by the host replaces the previous answer and uses its new receipt time for scoring. Clicking the already selected answer does nothing. A first-answer-only pack locks its answer targets after selection, including after reconnecting.

The widget shows the pack name in small grey text above the question, then a two-pixel countdown bar and a vertical list of answer text without letter prefixes. The question uses a larger font (+4); long questions and answers wrap. The bar sits two pixels below the question and changes its horizontal gradient from gold through orange to red as the pack's answer time runs out. Hover lights up an answer; pressing nudges and dims its text, then releasing restores it. Gold marks your selection. The hit area and surrounding layout stay still.

Your current score stays visible in the right lane beside the question. After expiry the confirmed correct answer turns green, a wrong selection turns red, and other choices dim. The confirmed signed change briefly rises and fades over that score: green for a gain, red for a loss, such as `+2.0` or `-0.7`. The permanent total remains visible underneath; skipping shows no delta animation. Hover the total to request the host's latest current-game standings. Orbit-Games downloads no standings before that hover, then shows up to 100 ranked players in its own private tooltip. Quiz currently supports 17 total players, so every current player fits.

In a round with another connected, ready player, a small popup below the answers names the fastest **correct** player and their host-recorded time. It uses the final accepted selection, not an earlier guess. Solo rounds and rounds with no correct answers show no winner. The next question clears the result highlights but keeps the current total; the HUD has no progress counter, numeric timer, explanation or help label.

A temporary streak toast appears beneath that popup for anyone in the game who reaches five or more consecutive correct answers. It shows their name with just **X in a row** directly underneath and a compact animated flare. The caption stays at a fixed size while the shine crosses the graphic. Sound-tier names are not displayed; the matching bundled voices are:

| Correct in a row | Announcement |
| ---: | --- |
| 5 | Dominating — `dominating.mp3` |
| 6 | Ownage — `ownage.mp3` |
| 7 | Rampage — `rampage.mp3` |
| 8 | Wicked Sick — `wicked-sick.mp3` |
| 9 | Holy Shit — `holyshit.mp3` |
| 10 and every correct answer afterward | Godlike — `godlike.mp3` |

Only host-confirmed results trigger toasts, including for other players when you answer incorrectly or skip. They work even when a pack awards no streak points. The transparent burst shines and fades over 3.2 seconds, with no black panel behind it. Playback finishes naturally before the next queued toast starts, even if the audio outlasts the animation. Simultaneous achievers queue without overlapping voices, and queued updates for the same player coalesce to their newest streak. Sounds respect the game's Sound Effects (SFX) setting. Muted or unavailable audio does not prevent the visual toast.

The queue can continue into the next question, a transient packet wait, a pause or a communication restriction without moving the answers or cutting the current voice. Automatic finite-game completion leaves the final result HUD in place until its confirmed queue drains. Leaving, switching hosts, manually stopping, hiding, dragging or changing widget appearance cancels it without replay. Reconnecting to already received results never replays them.

All HUD text, including the permanent score and animated delta, uses an opaque black shadow at **x = -2, y = -2 physical pixels** (down-left), refreshed when UI scale, resolution or font changes. Question, answer and smaller label sizes scale together with the widget. Private font objects leave Blizzard's and other addons' fonts untouched.

Gold is a local selection indicator, not an acknowledgement from the host: a late or failed change can leave the previously accepted choice as your scored answer. Results reconcile it to the actual scored choice. Errors and connection notices are available in `/og`, not appended to the Quiz widget.

You can belong to only one game. Joining another host leaves the old game; hosting another stops your current game first. Use **Leave game** in the Games footer or `/og leave`. A missed departure can retain a stale host slot for up to 35 seconds but cannot return you to that game.

Capacity is mode-owned: Quiz supports one host and up to 16 remote players; Cards supports eight total seats. Install this build on every client: generic protocol `ORBITGAMES1`, discovery protocol `ORBITGAMESDISC2` and the registered Quiz game protocol 2 intentionally isolate older clients. Advertisements include immutable game-type and activity versions; mode payloads travel through native addon whispers. Hosts advertise only through their saved Host-to routes, while discovery queries still use every available route. The Server route uses the silent realm lobby and never a visible chat tab.

Realm/channel restrictions still apply: a Server listing is best effort, and a guild/group listing does not guarantee cross-realm addon whispers. Host-to is not an access-control list; `/og join Name-Realm` remains a diagnostic fallback.

## Position the widget

The `/og` window reproduces Orbit's Edit Mode settings styling with a native NineSlice container, gold tabs and matching controls. Games keeps current-session status and Leave in its footer; game types supply their Host actions and Results views. Passive grey guidance is omitted, and the shared footer divider appears only on a page with footer actions; real failures can still use the normally hidden notice lane.

While `/og` is open, a purple edit outline appears around the selected mode's HUD. Begin movement only from the literal question text in Quiz or the five-card community row in Cards. Full frames, backgrounds, Quiz answers, Cards player rows and table actions do not drag. Cards shows five anonymous backs in edit mode so that row remains visible between hands; closing `/og` hides those preview backs and locks movement. The active HUD remains visible and has no Close or Escape action.

Drop the widget with its centre left of **50%** of the screen to pin its left edge and grow right, or at/right of **50%** to pin its right edge and grow left. The exact midpoint belongs to the right half. The top half grows down and the bottom half grows up: top-left pins the whole widget's top-left corner; bottom-left pins its bottom-left corner. The right side mirrors these rules. Releasing saves and immediately refreshes the panel from its new edge while preserving the visible position; changing scale or question length keeps that growth edge fixed, subject to screen bounds. Older placements may need one adjustment because the former centre band no longer exists.

Answers stay left-aligned in their original order. Long content scrolls within a bounded area, with a fixed right lane for the permanent score and its delta overlay plus space below the answers for the winner and streak toast. These animations never move the question or answer rows. Position is saved separately from host setup; resizing does not rewrite it. The timer stays exactly two physical pixels thick.

With no active game, `/og` shows the selected mode's positioning preview; closing the panel hides only the preview.

## Q/A appearance and sound

Open `/og` → **Settings**. **Scale** adjusts the Quiz widget from **50% to 200% in 5% steps**. **Font** opens a searchable SharedMedia list; **Default (Blizzard)** restores the native font. Additional fonts appear when installed addons register them.

Appearance changes apply immediately to all HUD text, including the pack label, answers, permanent score, delta overlay, round feedback and streak toast, and save automatically between sessions. They do not change the setup window, host settings, current answer or question deadline. The timer and text-shadow offsets stay two physical pixels at every Q/A scale; the answer's pressed offset stays one physical pixel.

**Sounds** turns streak audio **On** or **Off**, independently of Scale, Font and quiz setup. The six original MP3s play at the game's Sound Effects (SFX) level. Turning sounds off immediately stops the current voice while visual announcements and their queue continue; turning them back on does not replay a consumed announcement. Existing muted preferences remain off after updating.

These preferences are local to your installation, not sent to other players. If a saved font's provider is missing, the picker marks it unavailable and uses the Blizzard font without forgetting your choice. It switches back when that provider registers the font again; installing new font files may require restarting WoW.

## Scoring

Scoring belongs to the pack, not the host. **Warcraft Lore** retains its base score of `1 + 0.1 × whole seconds remaining` for correct answers and adds a consecutive-correct bonus. Wrong results deduct between `1.0` and `0.5` points: the faster the final selection, the larger the deduction. Unanswered questions score `0`. Before adding the streak bonus, its fifteen-second window gives these result deltas:

| Host receives final selection after | Correct delta | Wrong delta |
| --- | ---: | ---: |
| 0 seconds | +2.5 | −1.0 |
| 3 seconds | +2.2 | −0.8 |
| 5 seconds | +2.0 | −0.7 |
| 10 seconds | +1.5 | −0.6 |
| 14.5 seconds | +1.0 | −0.5 |

The wrong-answer loss is `round-to-tenth(0.5 + 0.5 × (2^(-t/6) − 2^(-2.5)) / (1 − 2^(-2.5)))`, where `t` is seconds since answers opened. This is an exponential curve normalized to the endpoints, with a six-second half-life and tenth-point steps. Current-game totals clamp after every finalized delta: a penalty at zero leaves the live score at zero, and the next correct result increases it immediately without repaying hidden session debt. Personal per-pack totals also display no lower than zero, but their receipt accounting retains signed results underneath that projection so delayed and out-of-order delivery stays order-independent. No-answer is always zero.

Warcraft Lore's streak adds **0, +0.1, +0.2, +0.3, +0.4, +0.5** for your first through sixth consecutive correct answers, then stays capped at **+0.5 per correct answer**. Wrong or unanswered completed questions reset it; a voided question does not award or break it. Each new game starts a fresh streak. Changing a selection does not award a bonus early: only the final accepted answer counts when the round closes.

With these bundled rules, sustained uniform random guessing has a negative expected signed result delta for four to six choices, including the streak bonus. The current-game floor means a penalty incurred while already at zero does not carry forward; Personal accounting still retains that signed receipt beneath its displayed floor. That is not a guarantee about an individual guess or a round after a lucky streak. Authors can change the rewards, penalties and bonus cap; custom rules need their own balance review. See [PACKS.md](PACKS.md) for fields, ranges and score identity.

Only the final accepted selection is scored, once when the question closes. Switching to another answer and then back gives the restored answer a new time, even if it was correct initially. Resubmitting the same choice, including a network retry with a new action ID, never refreshes its scoring time. Leaving after an accepted answer does not erase it. Answers arriving at or after the deadline are too late.

The host is authoritative: its receipt time determines both acceptance and speed bonus, not the participant's displayed timer. The host can play under the same scoring rules but does not incur remote network delay. This is a social quiz, not a latency-compensated competition or an anti-cheat system; play with a trusted host.

## Scores and interruptions

The Quiz **Scores** dropdown contains only **Personal score** and **Current game**, and opens on Personal score. Each compact personal row represents one pack and exact ruleset with its zero-floored points and played/correct/wrong/unanswered counts. The UI omits passive bottom guidance and scoring-rule paragraphs, giving that space to the scrolling list. `/og scores` opens this page; it does not print another copy to chat. Changing any normalized rule creates a separate row even if the author reuses a revision.

Pre-upgrade personal results have no pack-owned ruleset. Their saved accounting remains separate and unchanged, is never assigned guessed rules and is never rescored; the Scores page identifies it as **Earlier scoring** and applies the same zero floor to its displayed total. Warcraft Lore's new streak does not retroactively increase old points. Game-wide streaks can continue between compatible packs in an All packs game, while each answer's points still credit its source pack.

**Current game** is separate: the Scores page shows the host's ranked players or a participant's own host-reported score. The HUD score tooltip is the explicit on-demand view shared by every player: hovering requests the host's current revision and shows up to 100 ranked players. No board is downloaded in the background. Each accepted revision replaces the cached display snapshot; it never adds points, persists a receipt or replays a delta. The host clamps each player's current-game total after every finalized delta, so a wrong result at zero creates no debt for a later correct answer to recover. The view identifies the current question pack without displaying a scoring-rule paragraph. Final local host standings remain available after that game ends, until another hosted game replaces them. Every new hosted game starts at zero, regardless of personal history. Players send answer choices, never claimed scores or answer times.

**Archived league standings** and **Archived 100-point standings** remain preserved as migration and recovery data, separate from personal and current-game scores. They have no Scores scope, slash-command view or chat projection. Quiz data lives at `OrbitGamesDB.modes.quiz`, including personal schema 2, receipt history, appearance and question counters.

Confirmed results enter local `OrbitGamesDB.modes.quiz`, including host play. WoW writes on logout or `/reload`; a crash can lose newer changes. Host/session/round identities prevent duplicate credit across reloads and delayed delivery. Standings snapshots are presentation-only and cannot create another accounting path.

Local progress is **personal statistics, not verified competitive rankings**. Sanity checks reject inconsistent records and results without resetting your data, but a player controlling the addon/save file can still fabricate statistics or restore an earlier save. A host reaching a personal-history limit pauses with a notice while still delivering queued completed results to other players. There is no encryption, automatic cheating accusation, authenticated leaderboard or score upload; the live tooltip is only the current host's report. Only install trusted packs and choose hosts you trust.

An unfinished question never scores after a manual pause, stop, host logout, or host reload. Saved completed scores remain. Results retry for a bounded period during a live host session, surviving question changes and short reconnects. Delivery of an unseen result cannot be guaranteed after explicit leave/host switch, a long outage or host logout/reload. Hover again to request the latest standings; leaving or switching hosts discards the old snapshot. After reload, start a new host session; participants select its new listing.

When the host enters a boss encounter, or its addon communication is restricted or chat server disconnects, the active game automatically waits. Ordinary combat does not trigger this state. Quiz voids an unfinished question; Cards freezes the current action time. The game resumes only after the boss encounter and every communication blocker have ended. A manually paused game stays paused. If a finite Quiz already completed its final answer, recovery retries that result and gives it a fresh reveal interval before ending. A restricted participant disables input, then re-registers and waits for current host state. Older answers and acknowledgements cannot overwrite the recovered selection; a missing locked-answer confirmation is retried without changing the accepted answer's time.

## Development-only previews

In a source checkout, `/ogdev games` opens **Games** with 32 inert dummy hosts using the real rows and scrollbar. `/ogdev` is a shortcut. Development commands are silent: the browser, Cards table or toast HUD is their confirmation, and an unavailable or unknown command leaves the current visual state unchanged without a chat message.

Use `/ogdev off` to restore discovery. Preview state is unsaved and never changes sessions, scores or settings.

Check long-name truncation, scrolling to the final row, switching tabs, reopening the panel, and changing UI scale. Clear the preview and confirm the real list and its Join buttons return. This tests the existing Orbit-style chrome without introducing another frame design.

To exercise the Cards table without other clients, leave or stop any current game and run:

```text
/ogdev cards
```

This opens the real eight-seat Gold-denominated Hold'em table with your seat and seven computer players. The computers make legal folds, checks, calls, bets, raises and all-ins, continue through community cards and showdown, then deal another hand. When action reaches your seat, the normal table controls remain interactive; after five seconds the harness acts for you so the demonstration keeps moving. `/ogdev off` closes it. The harness uses a deterministic local model and does not advertise, join a session or save results.

To test the streak display and sounds without playing a quiz, leave/stop any current game, `/reload`, then run:

```text
/ogdev toasts
```

This shows the real Q/A widget with a **Streak preview · DEV** label and seven sample players reaching five through eleven correct in a row. It previews all six original clips in sequence when Sounds is On, including Godlike at both ten and eleven, over about 22 seconds; it waits longer if a sound is still playing. Sounds Off keeps it silent. The widget uses your saved position, Scale, Font and shadows; its answers are not interactive. The command neither opens setup nor adds discovery/network traffic, and it cannot change scores or start/join a game. It refuses to interrupt active, paused or joining sessions.

The preview hides when finished or returns to positioning if `/og` is open. Run it again to restart or use `/ogdev off`. Closing `/og`, changing the HUD lifecycle, or starting/joining a game cancels it.

This is a local presentation check, not a multiplayer or scoring test; use the two-client checks below for those. The development module and commands are excluded by the TOC/package metadata when building a release with the WoW packager. Manually copied source trees contain these opt-in commands.

## Troubleshooting and two-client verification

Offline checks and the following checklist are not a claim of live-client verification. Test with two consenting players/clients before relying on a hosted session.

- With Orbit disabled, reload and find the Orbit-logo minimap icon. Left-click twice to open/close the quiz window; right-click from both states to open Settings. Hover for the click/drag hints, drag around the minimap, then reload and confirm its position survives. If using a minimap-button collector or DataBroker display, test its forwarded clicks too. Check BugSack afterward, including hovering normal world tooltips in combat.
- On two updated clients, host a two-seat Hold'em table and join through Games. Deal through check/call, bet/raise, fold, all-in and showdown paths; include a side pot and a turn timeout. Each client must see only its own hole cards before showdown, with opponent cards backed and the deck/burn cards absent. Disconnect and reconnect the participant during a hand, then let it time out through settlement: it must not be dealt into the next hand until it sits in again.
- Repeat with eight seats if available. Verify all five community slots begin face down, community and showdown backs close horizontally before their faces open, only the button row has the dealer chip, folded cards center beneath an obvious red X, and the highlighted name alone identifies the actor. Compare several faces: 2–9 and J/Q/K/A must share one rank size, with only 10 reduced to fit. On several turns, confirm the thin wager line runs from Fold's left edge to All-in's right edge below the actions, then drag it to its minimum, a middle detent and its maximum; the third action must show the selected whole-Gold total, never exceed the projected maximum, survive an unchanged refresh and reset on the next action. Confirm there is no separate wager label and a short all-in below the regular minimum remains available only through **All-in**. Open `/og`, drag the table only from the five-card community row, and confirm the pot, background, player rows and actions do not move it. Between hands the row must remain visible as five anonymous edit backs, then hide when `/og` closes. Reload to confirm placement, and test 70%, 100%, 125% and 150% scale for sharp edges, non-overlapping seats and stable controls. Choose a Cards font and confirm the pot, player rows, numeric wager action and remaining actions update immediately while setup and Quiz remain unchanged. Use `/fstack` for ownership/layering and check BugSack after the session.
- Confirm the Host page has no Ledger selector, joining/rebuying needs no funding approval, no trade/mail window opens, and closing a completed session creates Gold-denominated Results without paid/unpaid controls. Reload and verify those bounded balance records persist.
- Install this build on both clients, but a test companion pack only on the host. Join through Games. Confirm the small grey pack label, larger question, one-column answers without letter prefixes and two-pixel countdown. With Warcraft Lore's rules, verify fifteen seconds to answer, three seconds of results, then automatic progress. Each player’s current total must remain visible beside the question; correct/wrong deltas rise and fade over it without moving or replacing it, while skipping shows none. Hover the total on each client and confirm the same host-ranked board appears in an Orbit-Games tooltip; before the first hover, no standings packet should transfer. Below the answers, both clients should see the same fastest-correct name/time; a faster wrong guess must not win. Check solo, nobody correct, and one player skipping: only the first two suppress the winner.
- In a trusted test pack file, try a 30-second clock, first-answer locking, ordered questions/choices and a finite two-question limit. Reload both clients. The Host screen must stay lean with no editable rule controls or explanatory rule copy, while play still follows the pack exactly. The second result must display before automatic session end. Answer locking must survive a short reconnect, the gradient must use the new clock, and incompatible packs must not offer All packs. Restore the desired pack rules afterward.
- Use a small mixed 4/5/6-choice companion pack. Hover, select the fifth and sixth answers when present, change your answer, and reconnect during the same question. Move from six choices back to four: unused lines must disappear and old selection/result/hover colors must clear. Alternate short and long questions/answers: they must wrap without ellipses and move the bar/rows down without overlap. Check another UI scale, scroll to the last answer if needed, and confirm each new round resets the red timer to gold.
- Press, release, repeat and change answers with `/og` open and closed. Only the pressed label nudges one pixel and dims; releasing, moving away, starting a drag or reaching the deadline restores it. Hit areas and all other text stay still, with no scrollbar flash or premature result animation. Scroll a long question just before it ends; the next question must start at the top without inheriting wheel motion. Check the (+2, -2) black shadows over bright scenery, including the rightmost and last answer glyphs.
- With Orbit disabled, inspect `/og`: NineSlice border, centered title, native close button, four gold tabs, raised header divider, native pack/score dropdowns, Orbit-style Settings controls, styled inputs, and pressed/disabled buttons. Games must place current-session status on the left and Leave game on the right below its full-width footer divider. Host actions use the same footer band, with Save setup on the left and Start game on the right. Results and Settings show neither footer nor divider, and no page shows passive grey guidance. The Scores dropdown must contain exactly Personal score and Current game; neither archived standings scope may appear. Confirm Scores has no bottom hint or grey scoring-rule paragraph and that its list reaches through the reclaimed space. Open pack, score and font lists, scroll, select an entry, and check that hiding the panel closes its popup. There must be no answer-duration, custom-channel, password, or Publish control. The bare Q/A HUD must remain in-session.
- On Host, confirm the native **Host to** multi-select sits above **Game type**, defaults to Server/Guild/Party, saves every nonempty combination across reloads and prevents deselecting the final audience. Its menu should remain open while toggling. Start hosting, then join another game, and confirm Host to and Game type lock in both states. With two clients, test Server, Guild and Party separately: only the selected advertisement routes should produce a listing, while Refresh still searches all available routes. Confirm Party works from a party, raid and instance group where available, Friends is absent, and `/og join Name-Realm` remains possible as a direct diagnostic probe.
- In Settings, check the compact `Scale` and `Font` rows: left labels, native Edit Mode slider with a gold value on the right, and dark arrow font picker. Drag or step Scale through 50–200% in 5% steps; the preview must resize immediately, before releasing the mouse. Search/scroll the font list and choose an entry: prompt, answers, permanent score and delta must use it immediately, rewrapping as needed. Close with Escape, an outside click or a tab switch. Selection and deadline must remain unchanged. Reload to check persistence; disable/re-enable a font provider to check fallback and restoration.
- Toggle `Sounds` Off and On during streak announcements (`/ogdev toasts` in a source checkout). Off must stop the current voice immediately while the visual toast and queue continue; On must resume future clips without replaying the current announcement. Check voices finish without overlap, other game sounds stay unchanged and the preference survives reload.
- Inspect the HUD outline, timer, dividers, input text and thin scrollbars at 55%, 100% and 200% Q/A scale. Move both windows and change resolution without changing UI scale: settled edges and divider joins must stay sharp, with no seams or half-pixel drift. In `/ogdev games`, scroll to the last row and test slow thumb drags; scrolling should reach the end and settle without jitter. Native dropdowns and Settings slider art should retain Blizzard's appearance.
- Complete more than one full cycle using a small repeating pack with Warcraft Lore's rules. Confirm three-second results, shuffled cycles, no immediate boundary repeat for a multi-question pack, and Stop ending progression. Use predictable answers to verify the consecutive-correct bonus grows by 0.1 from the second correct answer, caps at 0.5, resets after a wrong answer or skip, and survives a voided question without growing.
- In a repeating test pack, answer eleven questions correctly as host and participant. Neither clicks nor the first four results should announce; verify each milestone/MP3 above and Godlike on both ten and eleven. Both clients must see both names, with serialized sound and no Q/A movement. Let one player answer wrong or skip while the other continues: the latter must still announce. Verify SFX mute, long realm names, font/scale changes, screen-edge placement, pause/leave cleanup and no replay on result refresh/reconnect. Listen in-game: offline checks cannot verify decoding, loudness or native animation appearance.
- Answer as host and participant; switch choices and back before expiry. Confirm the final accepted choice/time controls points and the fastest-correct popup; identical clicks do not retime. Compare an early wrong answer (about −1.0) to a late wrong answer (−0.5); only the final selection incurs a penalty, and skipping incurs none. Verify current-game totals stop at zero and the next correct result increases a zero total by its full delta without hidden live debt. Also verify same-round reconnect timing and late-change rejection. Timer expiry alone must not reveal correctness, update the permanent total or animate either delta before the host confirms it; reopening `/og`, repeated result delivery or reconnecting must not change the score twice or replay feedback.
- Open `/og` and drag the Quiz HUD only from the literal question text across all four top/bottom and left/right regions, especially both 50% boundaries. Confirm the full frame, background and answers do not initiate movement. Releasing must not jump and must refresh the panel immediately. At top-left, increase scale or question length: the top-left corner stays fixed and the whole widget grows right/down. At bottom-left it grows right/up; mirror both cases on the right. Check wrapping, the two-pixel timer and footer bounds. Close setup or hide the HUD during a drag: movement must stop without selecting an answer. Reload to verify position; resizing alone must not rewrite it.
- Leave/rejoin and switch to a second host, including from hosting your own game. Confirm only the new game drives the widget. Try an unavailable/full game and confirm a useful timeout rather than a false connection.
- Pause after an answer, then resume: no points for the voided question and a fresh question follows. A manual pause must not auto-resume. Enter ordinary combat and confirm play continues; enter a boss encounter and confirm the game waits with the boss-specific notice. Where practical, overlap that encounter with addon-chat restriction/reconnection: clearing either one alone must not resume or score the unfinished question.
- Finish correct, incorrect and unanswered questions, then open Scores, including through `/og scores`. Personal score must show a separate compact row for each exact ruleset, including its zero-floored total and played/correct/wrong/unanswered counts, without scoring-rule paragraphs; its signed receipt deductions must still offset later Personal gains. Current game must start fresh, clamp after each delta without carrying debt below zero and show the current pack without rule-description prose. Hover the HUD total on every participant: each private tooltip must match the host's order and revision, show at most 100 rows and leave Personal/current totals unchanged when reopened. Reload, join a second host with the same rules and confirm that history accumulates. Change one pack rule and reload: a separate row appears after its first result while the earlier row remains unchanged. Play another pack and a compatible All packs game: each question credits only its source pack. Check a second local character shares the history. Archived league and 100-point standings intentionally have no in-game viewer; upgrade checks preserve them only as migration/recovery data.
- Reconnect during the result break and after a short interruption spanning the next question. A delivered result must appear once in personal history, including when an older result arrives later; it must not replace the newer HUD question or replay its score animation. Repeated, stale or reordered standings replies must only replace the tooltip at a newer accepted revision and must never add points. Stopping during the result break should send completed results before the stop notice to connected peers. Check the documented limits for leaving or an unreachable host rather than assuming guaranteed offline delivery.
- When upgrading from a setup with chat enabled, confirm Start immediately begins widget play without waiting for publication. Existing scores and widget position must remain intact; visible chat replies must not submit answers.
- Edit the existing example pack's TOC-listed `Questions.lua`, reload, and check the changed question. On the host, `/og packs` must open Host with Warcraft Lore and the example's 3 questions in the pack control. Break one copy deliberately and confirm the first retained validation error appears in the Host notice lane. Warcraft Basics must no longer be offered. Restart WoW if its file cache has not detected the new bundled TOC entries.
- Run `/og status` and confirm it opens Games with the current-session state and latest notice in the addon UI. Check BugSack if installed. Otherwise enable `/console scriptErrors 1`, reload, reproduce, and report the full error. Blizzard's `/fstack` can help identify a clipped or overlapping frame.

From the addon folder, run offline checks with Python and `lupa` (including `lupa.lua51`) installed:

```text
python Dev/Tests/run.py
python Dev/Tests/Lore.py --review
```

In this workspace, run `stylua --check --output-format Summary Orbit-Games` from the workspace root to use the shared formatter configuration.

These checks cover Lua 5.1 syntax and mocked behavior, not native addon-whisper reachability, lobby permissions, font metrics, or SavedVariables disk timing.

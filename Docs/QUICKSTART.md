# Getting started with Orbit-Quiz 0.9

## Install

Copy the `Orbit-Quiz` folder into `World of Warcraft/_retail_/Interface/AddOns/` and enable it. This version targets WoW 12.1.0 (`120100`) and does not require Orbit. Every player needs Orbit-Quiz; only the host needs extra question packs. There is no visible-chat mode.

Reload for changes to existing loaded files. If a newly installed addon folder is not listed on the AddOns screen, restart the client so WoW detects it.

The addon includes **1,183 game-based Warcraft Lore questions**, covering the RTS games and every released WoW expansion through Midnight. Zones, areas, regional history, campaigns, characters, raids and quests are included; comic, graphic-novel and manga questions are not. It mixes easy, medium, hard and very hard questions, with four to six choices each. It contains full story spoilers; see [the coverage and source guide](../Packs/WarcraftLore/SOURCES.md).

Create your own independently distributed quiz addon using [PACKS.md](PACKS.md). Your pack has its own folder/repository, Lua questions and rules, and a TOC declaring `## Dependencies: Orbit-Quiz`; install it beside the released framework. No fork, pull request or core-file edit is needed. The guide includes complete starter files, so a core checkout is optional. There is no editor or discovery of loose YAML/JSON/Markdown/text files. Only install Lua addons from trusted authors. Existing four-choice packs remain valid; omitted rules retain the original defaults without streak bonuses.

## Host a quiz

1. Open `/oq` and select **Host**.
2. Choose a question pack and review its read-only rule summary. The quiz author defines the rules; hosts cannot override them. Warcraft Lore allows **15 seconds** to answer and **3 seconds** to reveal the result. The default game name works without typing. Game names label listings; personal scores belong to the question's pack and ruleset.
3. Click **Start game**. Your Q/A widget appears automatically; you can answer there without joining yourself.
4. Other players find you under **Games** and click **Join**. The list discovers hosts in the shared realm lobby, guild, or group; allow a few seconds for listings to arrive.

Warcraft Lore uses every question, shuffling both questions and choices. Each question runs for fifteen seconds, then reveals the answer for three seconds before preparing the next question automatically. Connected players synchronize before the answering clock opens. At the end of the pack it starts another shuffled cycle; the last question is not immediately repeated when there is more than one question. One-question packs necessarily repeat.

Other packs can use different clocks, ordered questions or choices, first-answer locking, a single pass or a fixed question limit. A finite quiz automatically ends after its final result break. **All packs** is available only when every installed pack has identical rules; it never blends incompatible scoring or timing. Display preferences such as Scale and Font remain your own settings.

Warcraft Lore content version 2 removes the previous 247 comic-based questions without resetting earned scores. After updating an already-running host, `/reload` and start a new game to use the trimmed deck. Source checkouts retain the removed files under `Packs/WarcraftLore/Archive/Comics` for recovery; that archive is never loaded or included in packaged releases.

**Pause** voids an unfinished question; **Resume** starts a fresh one. **Stop game** ends the loop. Closing `/oq` does not pause or stop the quiz.

## Join and answer

1. Open `/oq` or `/orbitquiz`.
2. In **Games**, click **Join** beside a host. **Refresh** searches again. No host name or channel command needs to be typed.
3. When answers open, click one of the four to six answer lines. There are no visible buttons or text-entry boxes.
4. If the pack allows answer changes, you can change your selection before the deadline. The latest change accepted by the host replaces the previous answer and uses its new receipt time for scoring. Clicking the already selected answer does nothing. A first-answer-only pack locks its answer targets after selection, including after reconnecting.

The widget shows the pack name in small grey text above the question, then a two-pixel countdown bar and a vertical list of answer text without letter prefixes. The question uses a larger font (+4); long questions and answers wrap. The bar sits two pixels below the question and changes its horizontal gradient from gold through orange to red as the pack's answer time runs out. Hover lights up an answer; pressing nudges and dims its text, then releasing restores it. Gold marks your selection. The hit area and surrounding layout stay still.

After expiry the confirmed correct answer turns green, a wrong selection turns red, and other choices dim. Your score change briefly floats up and fades at the question's top-right: green for a gain, red for a loss, such as `+2.0` or `-0.7`. Skipping shows no personal score animation. In a round with another connected, ready player, a small popup below the answers names the fastest **correct** player and their host-recorded time. It uses the final accepted selection, not an earlier guess. Solo rounds and rounds with no correct answers show no winner. The next question clears the result; there are no permanent scores, progress counters, numeric timers, explanations or help labels on the HUD.

All HUD text uses an opaque black shadow at **x = -2, y = -2 physical pixels** (down-left), refreshed when UI scale, resolution or font changes. Question, answer and smaller label sizes scale together with the widget. Private font objects leave Blizzard's and other addons' fonts untouched.

Gold is a local selection indicator, not an acknowledgement from the host: a late or failed change can leave the previously accepted choice as your scored answer. Results reconcile it to the actual scored choice. Errors and connection notices are available in `/oq`, not appended to the question widget.

You can belong to only one game. Joining another host automatically leaves the old game; if you are hosting, it stops your hosted game first. Use **Leave game** under Games (or `/oq leave`) to leave. A missed departure message can leave a stale slot on the old host for up to 35 seconds, but cannot return you to that game.

Sessions support one host and up to 16 remote widget players. Install this build on each client: protocol 7 intentionally isolates earlier builds that cannot interpret pack rules and streak receipts. Only the host needs extra packs; validated rules travel with the questions and results. Discovery uses a silently joined `OrbitQuizLobby` custom channel plus available guild/group routes. This lobby is not attached to a visible chat tab. Questions and answers use native addon whispers, not visible whispers or chat lines.

Realm/channel restrictions still apply: a guild/group listing does not guarantee that addon whispers can reach a cross-realm host. There is no Battle.net relay. If joining times out, check matching addon versions, connectivity, and whether the session is full. `/oq join Name-Realm` remains a diagnostic fallback, not the normal player workflow.

## Position the widget

The `/oq` window reproduces Orbit's Edit Mode settings dialog styling, including its native NineSlice container, centered title, gold tabs, and matching buttons/inputs. Pack and score selectors use Blizzard's standard dropdown widget; Settings uses Orbit-style compact slider and font-picker rows. Everything is implemented locally and works with Orbit disabled.

While `/oq` is open, a purple edit outline appears around the Q/A widget. Drag it to position it, then close the panel to lock it. The HUD stays visible throughout an active session and has no Close or Escape action of its own.

The bare widget follows Orbit's Error Messages positioning: horizontal screen thirds align the pack name and question; the upper/lower half determines which way content grows. Answers stay left-aligned in one column. Long content scrolls within a bounded area, with space reserved beside the prompt for the pack's possible score values and below the answers for the winner. Neither animation moves the question or answer rows. Position is saved separately from host setup and reflows when display size or UI scale changes; the timer stays exactly two physical pixels thick.

With no active game, `/oq` shows a positioning preview; closing the panel hides only that preview.

## Q/A appearance

Open `/oq` → **Settings**. **Scale** adjusts the widget from **50% to 200% in 5% steps**, with a gold percentage beside the inline slider. **Font** opens a searchable SharedMedia list with font previews; **Default (Blizzard)** restores the native font. The controls match Orbit's dialog styling but need no Orbit installation. SharedMedia support is bundled, and additional fonts appear when installed addons register them.

Changes apply immediately to all HUD text, including the pack label, answers and round feedback, and save automatically between sessions. They do not change the setup window, host settings, current answer or question deadline. The timer and text-shadow offsets stay two physical pixels at every Q/A scale; the answer's pressed offset stays one physical pixel.

These preferences are local to your installation, not sent to other players. If a saved font's provider is missing, the picker marks it unavailable and uses the Blizzard font without forgetting your choice. It switches back when that provider registers the font again; installing new font files may require restarting WoW.

## Scoring

Scoring belongs to the pack, not the host. **Warcraft Lore** retains its base score of `1 + 0.1 × whole seconds remaining` for correct answers and adds a consecutive-correct bonus. Wrong answers lose between `1.0` and `0.5` points: the faster the final selection, the larger the loss. Unanswered questions score `0`. Before adding the streak bonus, its fifteen-second window gives:

| Host receives final selection after | Correct | Wrong |
| --- | ---: | ---: |
| 0 seconds | +2.5 | −1.0 |
| 3 seconds | +2.2 | −0.8 |
| 5 seconds | +2.0 | −0.7 |
| 10 seconds | +1.5 | −0.6 |
| 14.5 seconds | +1.0 | −0.5 |

The wrong-answer loss is `round-to-tenth(0.5 + 0.5 × (2^(-t/6) − 2^(-2.5)) / (1 − 2^(-2.5)))`, where `t` is seconds since answers opened. This is an exponential curve normalized to the endpoints, with a six-second half-life and tenth-point steps. Totals can go below zero, and no-answer is always zero.

Warcraft Lore's streak adds **0, +0.1, +0.2, +0.3, +0.4, +0.5** for your first through sixth consecutive correct answers, then stays capped at **+0.5 per correct answer**. Wrong or unanswered completed questions reset it; a voided question does not award or break it. Each new game starts a fresh streak. Changing a selection does not award a bonus early: only the final accepted answer counts when the round closes.

With these bundled rules, sustained uniform random guessing remains negative in long-run expectation for four to six choices, including the streak bonus. That is not a guarantee about an individual guess or a round after a lucky streak. Authors can change the rewards, penalties and bonus cap; custom rules need their own balance review. See [PACKS.md](PACKS.md) for fields, ranges and score identity.

Only the final accepted selection is scored, once when the question closes. Switching to another answer and then back gives the restored answer a new time, even if it was correct initially. Resubmitting the same choice, including a network retry with a new action ID, never refreshes its scoring time. Leaving after an accepted answer does not erase it. Answers arriving at or after the deadline are too late.

The host is authoritative: its receipt time determines both acceptance and speed bonus, not the participant's displayed timer. The host can play under the same scoring rules but does not incur remote network delay. This is a social quiz, not a latency-compensated competition or an anti-cheat system; play with a trusted host.

## Scores and interruptions

The **Scores** tab opens **My pack scores**: your points, correct/wrong counts and answered questions for each quiz pack and ruleset. `/oq scores` prints the same progress. These totals follow you between hosts and are shared by your characters in the same local WoW account. Compatible All packs games credit each question's original pack. Changing a title or content version under the same pack ID and rules keeps its progress; changing any rule or the author's rules version creates a separate score row. The complete normalized rules distinguish variants even if the author forgets to bump that version. Another pack ID starts separately.

Pre-upgrade personal scores remain under **Original rules**, unchanged and separate from the new rule-based rows. Warcraft Lore's new streak does not retroactively increase old points. Session-wide streaks can continue between compatible packs in an All packs game, while each answer's points still credit its source pack.

**This game** is separate: the host sees everyone in its session leaderboard; a participant sees their own host-reported session total. Every new hosted game starts at zero, regardless of saved personal totals. Players send answer choices, never claimed scores or answer times. The Q/A widget shows brief round feedback, not ongoing totals. A participant does not download the host's full leaderboard.

**Archived league totals** and **Archived 100-point scores** retain the earlier host-owned standings, grouped by their original league names; `/oq archive` and `/oq legacy` print them. The top-level save remains schema 6; personal progress migrates to schema 2 within it. Prior totals, receipt history, appearance settings and question counters survive without rescoring or assigning old league totals to a guessed pack. New ruleset progress starts with its first confirmed result. Retired chat settings/passwords are discarded, and old Warcraft Basics selections become Warcraft Lore.

Confirmed results enter your local `OrbitQuizDB`, including when you play as host. WoW writes SavedVariables on normal logout or `/reload`; a crash can lose changes since the last save. This is local account data, not automatic synchronization between computers, installations or Battle.net accounts. Host/session/round identifiers prevent duplicate credit, including across reloads and repeated/out-of-order results. Delayed valid results update personal totals without replacing a newer question or replaying its animation.

Local progress is **personal statistics, not verified competitive rankings**. Sanity checks reject inconsistent records and results without resetting your data, but a player controlling the addon/save file can still fabricate statistics or restore an earlier save. A host reaching a personal-history limit pauses with a notice while still delivering queued completed results to other players. There is no encryption, automatic cheating accusation, shared trusted leaderboard or score upload. Only install trusted packs and choose hosts you trust.

An unfinished question never scores after a manual pause, stop, host logout, or host reload. Saved completed scores remain. Results retry for a bounded period during a live host session, surviving question changes and short reconnects. Delivery of an unseen result cannot be guaranteed after explicit leave/host switch, a long outage or host logout/reload. After reload, start a new host session; participants select its new listing.

When the host's addon communication is restricted or its chat server disconnects, the quiz automatically pauses and voids the unfinished question. Once available again it resumes with a fresh question, or ends if a finite quiz has no questions left. A manually paused quiz stays paused. If a finite quiz already completed its final answer, recovery retries that result and gives it a fresh reveal interval before ending. A restricted participant disables input, then re-registers and waits for current host state. Older answers and acknowledgements cannot overwrite the recovered selection; a missing locked-answer confirmation is retried without changing the accepted answer's time.

## Development-only game-list preview

In a source/development checkout, `/oqdev games` opens **Games** with 32 dummy hosts using the real rows and scrollbar. `/oqdev` is a shortcut. The sample data includes short and long names, multilingual text, varied pack titles, and player counts from 1 to 17. The header and footer clearly mark the preview; all dummy **Join** buttons are disabled.

Use `/oqdev off` to restore real discovered games. Preview mode is not saved and resets on `/reload`. It does not replace your active session, alter scores or settings, create hosts, or send sample data to other players. Existing games continue normally in the background.

Check long-name truncation, scrolling to the final row, switching tabs, reopening the panel, and changing UI scale. Clear the preview and confirm the real list and its Join buttons return. This tests the existing Orbit-style chrome without introducing another frame design.

The development module and command are excluded by the TOC/package metadata when building a release with the WoW packager. Manually copied source trees still contain the opt-in command.

## Troubleshooting and two-client verification

Offline checks and the following checklist are not a claim of live-client verification. Test with two consenting players/clients before relying on a hosted session.

- Install this build on both clients, but a test companion pack only on the host. Join through Games. Confirm the small grey pack label, larger question, one-column answers without letter prefixes and two-pixel countdown. With Warcraft Lore's rules, verify fifteen seconds to answer, three seconds of results, then automatic progress without visible chat. Correct/wrong answers animate each player's own signed score beside the question; skipping does not. Below the answers, both clients should see the same fastest-correct name/time; a faster wrong guess must not win. Check solo, nobody correct, and one player skipping: only the first two suppress the winner.
- In a trusted test pack file, try a 30-second clock, first-answer locking, ordered questions/choices and a finite two-question limit. Reload both clients. The Host summary must reflect the pack with no editable rule controls. The second result must display before automatic session end. Answer locking must survive a short reconnect, the gradient must use the new clock, and incompatible packs must not offer All packs. Restore the desired pack rules afterward.
- Use a small mixed 4/5/6-choice companion pack. Hover, select the fifth and sixth answers when present, change your answer, and reconnect during the same question. Move from six choices back to four: unused lines must disappear and old selection/result/hover colors must clear. Alternate short and long questions/answers: they must wrap without ellipses and move the bar/rows down without overlap. Check another UI scale, scroll to the last answer if needed, and confirm each new round resets the red timer to gold.
- Press, release, repeat and change answers with `/oq` open and closed. Only the pressed label nudges one pixel and dims; releasing, moving away, starting a drag or reaching the deadline restores it. Hit areas and all other text stay still, with no scrollbar flash or premature result animation. Scroll a long question just before it ends; the next question must start at the top without inheriting wheel motion. Check the (-2, -2) black shadows over bright scenery, including the leftmost and last answer glyphs.
- With Orbit disabled, inspect `/oq`: NineSlice border, centered title, native close button, four gold tabs, raised divider, native pack/score dropdowns, Orbit-style Settings controls, styled inputs, and pressed/disabled buttons. Open pack, score and font lists, scroll, select an entry, and check that hiding the panel closes its popup. There must be no answer-duration, custom-channel, password, or Publish control. The bare Q/A HUD must remain in-session.
- In Settings, check the compact `Scale` and `Font` rows: left labels, native Edit Mode slider with a gold value on the right, and dark arrow font picker. Drag or step Scale through 50–200% in 5% steps; the preview must resize immediately, before releasing the mouse. Search/scroll the font list and choose an entry: prompt, answers and score must use it immediately, rewrapping as needed. Close with Escape, an outside click or a tab switch. Selection and deadline must remain unchanged. Reload to check persistence; disable/re-enable a font provider to check fallback and restoration.
- Inspect the HUD outline, timer, dividers, input text and thin scrollbars at 55%, 100% and 200% Q/A scale. Move both windows and change resolution without changing UI scale: settled edges and divider joins must stay sharp, with no seams or half-pixel drift. In `/oqdev games`, scroll to the last row and test slow thumb drags; scrolling should reach the end and settle without jitter. Native dropdowns and slider art should retain Blizzard's appearance.
- Complete more than one full cycle using a small repeating pack with Warcraft Lore's rules. Confirm three-second results, shuffled cycles, no immediate boundary repeat for a multi-question pack, and Stop ending progression. Use predictable answers to verify the consecutive-correct bonus grows by 0.1 from the second correct answer, caps at 0.5, resets after a wrong answer or skip, and survives a voided question without growing.
- Answer as host and participant; switch choices and back before expiry. Confirm the final accepted choice/time controls points and the fastest-correct popup; identical clicks do not retime. Compare an early wrong answer (about −1.0) to a late wrong answer (−0.5); only the final selection incurs a penalty, and skipping incurs none. Verify negative totals, same-round reconnect timing and late-change rejection. Timer expiry alone must not reveal correctness or animate either result before the host confirms it; reopening `/oq` or reconnecting to that result must not replay feedback.
- Open `/oq`, drag the HUD to the top/bottom and left/center/right, then close `/oq`. Confirm alignment/growth, saved position, bounded long content, and that the active HUD stays visible but cannot be dragged. The edit outline must add no text or change the layout. Check a different UI scale, the two-pixel bar thickness, and that the score stays on-screen without overlapping the prompt. It should fade before the next question and cancel on leaving, pausing or dragging. Reload and check the saved position.
- Leave/rejoin and switch to a second host, including from hosting your own game. Confirm only the new game drives the widget. Try an unavailable/full game and confirm a useful timeout rather than a false connection.
- Pause after an answer, then resume: no points for the voided question and a fresh question follows. A manual pause must not auto-resume. Where practical, verify addon-chat restriction/reconnection auto-pauses and recovers without scoring the unfinished question.
- Finish correct and incorrect answers, reload each client and join a second host using the same pack and rules. My pack scores must retain and accumulate signed totals; This game must start fresh. Play another pack and a compatible All packs game: each question credits only its source pack. Change a test pack rule and reload: a separate rules row must appear after its first result, with the prior row unchanged. Check a second local character shares the personal totals. Previous Original rules, league and 100-point archive views must remain unchanged after new gameplay.
- Reconnect during the result break and after a short interruption spanning the next question. A delivered result must appear once in personal history, including when an older result arrives later; it must not replace the newer HUD question or replay its score animation. Stopping during the result break should send completed results before the stop notice to connected peers. Check the documented limits for leaving or an unreachable host rather than assuming guaranteed offline delivery.
- When upgrading from a setup with chat enabled, confirm Start immediately begins widget play without waiting for publication. Existing scores and widget position must remain intact; visible chat replies must not submit answers.
- Edit the existing example pack's TOC-listed `Questions.lua`, reload, and check the changed question. On the host, `/oq packs` lists Warcraft Lore and the example's 3 questions when installed. Warcraft Basics must no longer be offered. Restart WoW if its file cache has not detected the new bundled TOC entries.
- Run `/oq status` for local role, host, session state, and latest notice. Check BugSack if installed. Otherwise enable `/console scriptErrors 1`, reload, reproduce, and report the full error. Blizzard's `/fstack` can help identify a clipped or overlapping frame.

From the addon folder, run offline checks with Python and `lupa` (including `lupa.lua51`) installed:

```text
python Dev/Tests/run.py
python Dev/Tests/Lore.py --review
```

In this workspace, run `stylua --check --output-format Summary Orbit-Quiz` from the workspace root to use the shared formatter configuration.

These checks cover Lua 5.1 syntax and mocked behavior, not native addon-whisper reachability, lobby permissions, font metrics, or SavedVariables disk timing.

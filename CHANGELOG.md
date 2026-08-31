# Changelog

## 0.9 (Unreleased)

- Replace Warcraft Basics with 1,183 source-linked, game-based Warcraft Lore questions spanning the RTS games and every released WoW expansion through Midnight, including zones, areas and history.
- Warcraft Lore content version 2 removes 247 comic, graphic-novel, manga and digital-comic questions from play. Preserve their source files in an unloaded archive excluded from packaged releases; retain the pack ID and earned scores without rescoring.
- Support four to six choices per question, with easy, medium, hard and very hard metadata retained in the question data. Preserve automatic full-deck cycles and adjustable selections.
- Extend every question to fifteen seconds, keeping the three-second reveal. Wrong answers lose 1.0 early, easing exponentially to 0.5 late; correct answers keep 1 plus 0.1 per whole second remaining. No answer costs nothing, and only the final changed selection scores. Same-choice retries cannot refresh scoring time.
- Reduce the Q/A HUD to a small grey pack name, question text, a two-physical-pixel countdown bar, and one vertical list of clickable text choices without letter prefixes. The question font is four units larger than the answer font. Remove button art and permanent score/help labels; keep edit-only movement without a drag heading.
- Place the timer two physical pixels beneath the question and use a gold-to-red gradient as time expires. Reset reused text heights before measuring wrapped prompts/choices and round up to avoid ellipses or clipped final lines.
- Use text colors for hover, selection and authoritative correct/incorrect results. Briefly float/fade each player's signed score beside the question and the fastest correct player's name/time below the answers, without replaying feedback on refresh or reconnect. Winner announcements require another round-ready player; solo rounds and rounds with no correct answers show none. Keep fifteen-second questions and three-second results.
- Give all HUD text reusable addon-owned font objects with opaque black shadows at (-2, -2) physical pixels. Refresh on font/scale/display changes, preserve highlight colors and reserve clipped-viewport padding for shadows.
- Add a Settings tab with compact Orbit-style `Scale` and `Font` rows: a 50–200% Edit Mode slider in 5% steps with a gold value, plus a searchable SharedMedia font-preview picker. Save and re-render immediately while dragging/selecting without changing active questions or the setup window; bundle standalone libraries, retain missing-font preferences and retry failed font loads on settings/media updates.
- Upgrade session/discovery to protocol 6 with actual pack metadata, self-contained host-calculated score receipts and fastest-correct result metadata. Validate, acknowledge and retry results across question changes and short reconnects without duplicate credit or stale HUD feedback. All players must update, including earlier 0.9 previews; live questions still exclude answer keys, explanations, sources and winner information.
- Add account-wide personal progress for each stable pack ID across hosts and characters, including per-pack attribution in All packs games. Keep game standings host-controlled and start each new session at zero. Scores defaults to My pack scores; preserve earlier decimal leagues and 100-point boards as read-only gameplay archives under schema 6, without guessing per-pack backfills. Local progress is personal statistics, not anti-cheat-verified rankings.
- Place game and score list scrollbars just inside the setup window's right border. Reserve a score column beside the HUD's scrolling text and a winner footer below it so animations neither overlap scrolling answers nor shift the layout.
- Replace native pushed-font handling with a one-physical-pixel answer-text press and dim, restored on release, leave, hide, disable, drag or reflow. Leave hit areas and other labels still. Stabilize right-side scrollbar visibility against transient native ranges, batch content reflows, and cancel pending scrolling when questions or score scopes change.
- Snap owned window/HUD placement, outlines, divider joins, text insets and rendered scroll positions to the pixel grid across scale and resolution changes. Preserve native control styling, remeasure reused score text, and keep the final game-list row within its declared scroll extent.
- Add an opt-in development game browser preview: `/oqdev games` shows 32 varied dummy hosts in the real scrolling list; `/oqdev off` restores discovery. Sample Join actions are inert, active games and saved data are unaffected, and the preview resets on reload.
- Exclude the preview module and command from packager-built releases; keep the existing standalone UI styling unchanged.

## 0.8

- Remove visible-chat publishing and answers, including Publish actions, channel/password controls, related commands, delivery queues, and chat-event listeners.
- Run questions entirely through the automatic widget session, retaining the hidden discovery lobby and addon-message transport.
- Separate native player identity from the removed chat module. Discard retired chat settings/passwords while preserving current scores, archived scores, history, and widget position.
- Add upgrade, no-visible-chat, automatic-progression, and multiplayer regressions. The fixed ten-second clock, scoring, and standalone Orbit-style UI remain unchanged.

## 0.7

- Raise the header divider ten physical pixels and replace custom pack/score pickers with Blizzard's native dropdown widget, preserving the standalone Orbit-style dialog shell.
- Fix every hosted answer window at ten seconds and remove duration controls. Preserve historical timing, scores, and compatible incoming older-host sessions.
- Publish questions as five separate Q/A/B/C/D messages attempted in one real click. Track each server echo and start the shared timer only after complete delivery; native burst delivery still needs in-game verification.
- Accept plain A-D, punctuated answer keys, and numbered replies only in the selected custom channel. Ignore own announcement echoes, partial delivery, stale IDs, and late answers.
- Bound optional publication waits and fall back to automatic widget-only play when skipped or failed. Add native-dropdown, fixed-clock, batch-delivery, and reconnect regressions.

## 0.6

- Replace the generic flat `/oq` window with a standalone port of Orbit's actual Edit Mode settings dialog: housing-container shader NineSlice art, centered title, native close button, gold text tabs, and tapered dividers.
- Use Orbit's native panel-button templates and tooltip-bordered text inputs, preserving pressed and disabled states. Keep the Q/A HUD unframed and use Orbit's purple edit highlight.
- Replace generic pack menus and the cycling score selector with standalone Orbit-style arrow pickers, pooled radio rows, and thin animated scrollbars.
- Add explicit asset, native-template, standalone-loading, and interaction regressions. Quiz/session rules, scoring, and saved data are unchanged.

## 0.5

- Replace the large player window with a bare, screen-aware question widget inspired by Orbit Error Messages and Edit Mode. Move it only while `/oq` is open; active sessions have no HUD close button.
- Discover games through hidden lobby/guild/group announcements; join or switch from the browser without entering a host name. Each player has one session, including when switching away from local hosting.
- Accept revised answers until the deadline. A changed selection gets a new host-receipt time; retries cannot retime or restore an older selection.
- Score correct answers as 1 plus 0.1 per whole second remaining; incorrect and unanswered questions earn 0. Preserve old 100/-50 totals and history in a separate archive through schema-4 migration.
- Store widget position independently, adapt alignment/growth to its screen region, and use compact Orbit-inspired controls and pooled game rows.
- Fence delayed joins, departures, answers and acknowledgements across game switches and reconnects; fresh membership epochs survive long-round peer expiry.
- Expand offline GUI, discovery, migration, and multi-client regression checks. Native rendering/network verification remains an in-game step.

## 0.4

- Make the player widget the primary quiz interface: join a host, click a choice or type an answer, and see acknowledgements, results, and your host-supplied total.
- Run every selected pack question in continuous shuffled cycles with five-second result breaks; avoid immediate cycle-boundary repeats when the pack has multiple questions.
- Send bounded, throttled native addon messages to up to 16 remote widget players; only the host needs the selected question packs.
- Keep deadlines, first-answer locking, scoring, and persistent league totals authoritative on the host; preserve earlier data through schema-3 migration.
- Auto-pause and void unfinished questions during host communication restrictions/disconnection, then resume fresh; manual pauses remain paused.
- Retain custom-channel play as a default-off, explicit-click bridge that shares answer locks/deadlines and never blocks widget rounds.
- Add widget/runtime/transport regression coverage and a two-client verification guide; live-client verification remains required.

## 0.3

- Accept plain A/B/C/D replies in the current quiz channel while retaining numbered answers and first-answer locking.
- Include the host in answer counts and persistent standings under the same scoring rules as other players.
- Update question announcements and host-panel guidance to explain the simpler reply format.

## 0.2

- Restrict hosting and answers to player-created custom channels, including native channel-type validation before sends.
- Post the actual question on the first click; combine short questions into one message and preview remaining lines for longer packs.
- Unify start, posting, next-question, and resume controls; surface native channel failures and add `/oq status` diagnostics.
- Preserve existing scores/counters when migrating old settings; retain historical whisper boards without enabling whisper play.

## 0.1

- First standalone quiz host with guild, raid, instance, custom-channel, and local-rehearsal destinations.
- File-based Lua question-pack registration and a companion-addon example; no in-game editor.
- Timed, first-answer-locked questions with speed bonuses and signed wrong-answer penalties.
- Persistent host-local league standings, separated by public and whispered answers.

# Changelog

## Next alpha (Unreleased)

- Fix Cards join retries resetting action deduplication, duplicate welcomes replacing active table views, and full-table snapshot cancellation starving participants. Advance Cards transport to protocol 3 so delayed wagers bind to their original turn. Correct minimum raises over short opening all-ins and consolidate wager application.
- Remove fixed-seed preview distribution thresholds, repeated preview styling assertions, redundant descriptor checks and inline explanatory comments; retain behavioral regressions and add real eight-client Cards transport coverage.

- Rename the addon and release package to Orbit-Games. Make the application shell game-type agnostic and register Quiz as the first mode under `OrbitGames.Quiz`, with `OrbitGames.Quiz:RegisterPack` as its public companion-pack entry point.
- Move Quiz rules, model, scoring, session, persistence, UI and bundled packs under `Modes/Quiz` while keeping shared identity, transport, discovery, settings chrome, media and minimap ownership at the framework boundary.
- Introduce generic `ORBITGAMES1` and `ORBITGAMESDISC2` protocols with immutable mode/activity routing, capacity and joinability. The former Quiz-only prefixes remain legacy contracts and are never reinterpreted.
- Add a saved native Host-to multi-select above Game Type for Server, Guild and Party discovery. Require a nonempty selection and lock it during active sessions; filter advertisements and withdrawals while queries remain broad. Server is the best-effort silent `OrbitGamesLobby` route, Party includes party/raid/instance routes, there is no Friends/Battle.net fan-out, and Host-to does not authorize direct joins.
- Store application data in `OrbitGamesDB`, with preserved Quiz state under `modes.quiz`. Package an `Orbit-Quiz` compatibility shim to load the old addon-named SavedVariables file and legacy companion dependencies without running a second game engine.
- Replace player commands with `/og` and `/orbitgames`; source previews move to `/ogdev`. Keep Quiz terminology only for question, answer, pack, rules and Quiz score behavior.
- Remove every Orbit-Games chat-frame post, including login, help, status, results and source-preview messages. Route `/og status` and unknown commands to Games, `/og packs` to Quiz Host, and `/og scores` or Cards `/og results` to the active Results page; show pack validation in the Host notice lane. Keep `/ogdev` feedback visual and silent, preserve native addon-message transport, and retain archive/legacy Quiz standings without a UI, command or chat projection.
- Add Cards as a second game type with host-authoritative No-Limit Texas Hold'em for two to eight seats: private hole-card projections, fixed buy-in/blinds, timed legal actions, heads-up order, short all-ins, side pots, refunds, odd chips, rebuys between hands and an eight-seat table. Recover dropped action replies idempotently, version every wire projection, allow known-seat reconnects and sit disconnected peers out before the next deal.
- Make every Cards amount one whole Gold unit while leaving any real stake as a private social agreement. Replace the blind inputs with a buy-in-relative slider spanning 100 to 20 big blinds, derive the big blind at exactly twice the small blind, and cap buy-ins at 10,000,000 Gold. Remove the Ledger selector and all funding/payment gates and markers; advertise eligible tables normally and retain only buy-in, final balance and net session results. Advance Cards saves to schema 4 and its transport, activity, rules and projection contracts to version 2 so copper-valued alpha clients cannot mix. Orbit-Games never touches WoW trade, mail or money APIs.
- Bundle a reproducible compact 52-card atlas from `hayeah/playing-cards-assets`, pinned to commit `1e4497c05c3da9956c9f517bd386e9a7090ff7fa` with its MIT licence and provenance. Fill each landscape face with the enlarged original rank/suit glyphs, give every single-character rank one fixed visible size while allowing 10 alone to fit its width, omit decorative footer lines and give concealed cards a high-contrast back. Generate the table's dealer chip in the same atlas from project-owned Pillow primitives with separate provenance.
- Align Cards host controls to one full-row grid and two equal paired columns. Move every mode's host actions and the Games session/Leave row into the shared Orbit-style footer, keep primary actions on the right, remove passive grey guidance from Host, Settings and the shared shell, and hide the footer and divider on pages without actions. Add a source-only eight-seat Hold'em harness with seven computer players, interactive local actions and continuous deterministic hands.
- Fix card faces and backs rendering as empty slots by loading the PNG atlas with its required explicit extension.
- Replace the full-screen poker-table presentation with the Quiz HUD's transparent 380-unit visual language: keep five stable community slots backed until dealt, flip backs horizontally into community/showdown faces and show anonymous opponent backs. Collapse an observed folded player's full row upward once, continuously reflow the remaining rows and omit prior folders on a first mid-hand snapshot. Place a dealer chip outside the hole-card column instead of D/SB/BB text. Put a Plunderstorm coin atlas and numeric pot above the card row, show each player balance with a 25%-reduced Blizzard Gold coin and white compact K/M/B/T rounding to two decimals, move the Quiz-matched gradient timer ten physical pixels below the cards, highlight the acting player's full row with a gold backdrop instead of repeated turn prose, and retain unframed local-last player rows and contextual text-only controls. Replace typed wagers with a template-free slider bounded to host-projected legal totals, mapping large ranges to at most 101 sampled legal totals while preserving exact minimum and maximum targets; render only a thin muted line and Gold marker from Fold's left edge to All-in's right edge, and show the selected total in the former Bet/Raise action slot. Name each payout winner's evaluated hand at settlement; for a sole showdown winner, pin both extra hole-card slots to the table's right edge growing left, then flip the two cards outside the canonical five face-down exactly once across repeated refreshes so only the winning hand remains visible. Hold source-preview outcomes for eight seconds. Enlarge the cards without widening the HUD, remove panel and passive row washes, add opaque text shadows, and preserve the saved visible edge as the player list grows.
- Keep the Quiz and Cards timer backdrops visible after their progress empties. Center each two-physical-pixel backdrop beneath a four-pixel gradient fill so the fill extends one pixel above and below.
- Restrict `/og` edit-mode HUD movement to the literal Quiz question text or the five-card Cards community row. Full frames, backgrounds, answers, player rows and actions no longer initiate movement; Cards shows five anonymous backs between hands while edit mode is open, then hides them when it closes.
- Automatically wait during boss encounters, but not ordinary combat. Keep boss and addon-chat blockers independent, preserve manual pause ownership, show a boss-specific notice and resume only after every automatic blocker clears.
- Add a mode-local SharedMedia Font picker to Cards Settings. Save it independently from Quiz, apply it live to every Cards table text target through private normal/small font roles, preserve native sizes and shadows, and retain unavailable choices for automatic fallback/restoration.
- Clamp every hosted-session Quiz score after each finalized delta, so a wrong result at zero creates no hidden live debt and the next correct result increases the current total immediately. Keep Personal per-pack receipt accounting signed and order-independent underneath its zero-floored projection. Reject negative cumulative host snapshots without changing signed per-question feedback or archived accounting.
- Restore a permanent current Quiz total beside the question and animate each confirmed signed delta over it without replacing or moving the total. Hovering the score opens an addon-owned private tooltip with up to 100 current-session ranks.
- Advance the registered Quiz game protocol to version 2 for demand-driven, host-authoritative standings. Download no board before hover; accept only monotonic revisioned replacements so duplicate, stale or conflicting snapshots cannot add points, persist receipts or replay feedback. All Quiz players must update.

## 0.9 (Unreleased)

- Replace the flat Scores text block with structured, reusable rows for Personal score and Current game. Keep one compact personal row per exact quiz ruleset with played/correct/wrong/unanswered counts, keep participant data private, remove passive bottom guidance and visible rule-description paragraphs, and let the score list reclaim their space. Preserve every archived league and 100-point standing as migration/recovery data without offering either archive in the UI or chat.
- Anchor and drag the whole Q/A widget instead of an invisible handle. Preserve the visible rectangle when dropping across growth zones; pin the selected corner during scale/content changes, split horizontal growth into left/right screen halves, and grow down in the top half or up in the bottom half. Refresh immediately after a drop and end dragging cleanly when hidden without submitting a release click.
- Add a standalone Orbit-logo minimap launcher: left-click toggles the quiz window, right-click opens Settings, and dragging saves its position. Bundle LibDataBroker/LibDBIcon for broker-display and minimap-button-collector support, with a private hover tooltip and no Orbit dependency.
- Add a saved 0â€“100% Volume slider in 10% steps, with 0% muting Quiz sounds without hiding streak toasts. Bundle quieter audio variants without changing global game sound settings; volume changes preserve queued announcements and never replay a consumed clip.
- Add animated, sound-enabled group streak toasts below the Q/A widget: Dominating at 5, Ownage at 6, Rampage at 7, Wicked Sick at 8, Holy Shit at 9 and Godlike at 10+. Announce only confirmed results, queue simultaneous players, inherit font/scale, reserve pixel-aligned space and cancel playback cleanly without replay.
- Replace the dark toast panel with a transparent burst and masked shine. Reduce the graphic to 80% size, centered four physical pixels below its text slot. Show only a fixed-size `X in a row` beneath the player name while the shine crosses the graphic. Let confirmed voices and queues survive packet waits, pauses, restrictions and natural final-session teardown; nonzero volume changes apply to the next clip, while mute and explicit cancellation still stop immediately. Route every audible level through faded, tail-padded Ogg playback and reject unsafe master or generated endpoints during audio validation.
- Add source-only `/oqdev toasts` to preview all six streak sounds and animations using sample 5â€“11 streaks. Reuse the real read-only HUD, refuse live sessions, leave scores/networking untouched and clean up automatically or with `/oqdev off`.
- Add the bundled Orbit logo to the addon-list entry under the existing Orbit UI category, without an Orbit dependency.
- Gently scroll overflowing join-card descriptions back and forth with pauses at each end; keep short text still and preserve animation progress across unrelated lobby updates.
- Make the quiz-pack example a self-contained independent-addon starter, with its own required Orbit-Quiz dependency and authoring/distribution instructions. Include complete starter files in the guide; creating a pack needs no core checkout, contribution or file edits.
- Organize application, game, networking, persistence and UI into responsibility-based modules; group Warcraft Lore and source-only development tools, with guides under Docs. Keep pack IDs, protocol and saved-data schemas unchanged.
- Consolidate localization, font-picker popup ownership and dialog controls; remove unused strings/wrappers, share feedback construction and project score rows without redundant compatibility copies.
- Fix selected panel-button accents persisting after deselection while retaining native button fonts and handlers.
- Validate main-branch pushes before `MAJOR.MINOR-alpha` tagging and CurseForge Alpha/GitHub prerelease packaging; keep development tools and archived comic questions out of published builds.
- Replace Warcraft Basics with 1,183 source-linked, game-based Warcraft Lore questions spanning the RTS games and every released WoW expansion through Midnight, including zones, areas and history.
- Warcraft Lore content version 2 removes 247 comic, graphic-novel, manga and digital-comic questions from play. Preserve their source files in an unloaded archive excluded from packaged releases; retain the pack ID and earned scores without rescoring.
- Support four to six choices per question, with easy, medium, hard and very hard metadata retained in the question data. Preserve automatic full-deck cycles and adjustable selections.
- Add author-defined pack rules for answer/reveal timing, answer changes, question/choice ordering, repetition, finite question limits, base/speed points, wrong-answer penalties and consecutive-correct bonuses. Hosts only select a quiz and cannot override its rules; keep the Host screen lean instead of repeating the rule definitions. Mixed packs require identical rules.
- Warcraft Lore keeps fifteen-second questions, three-second results, +1 plus 0.1 per whole second left, and the exponential -1 to -0.5 wrong penalty. Add 0.1 per consecutive correct answer after the first, capped at 0.5 extra per answer; wrong/unanswered closed rounds reset the streak. Voids and retries never award streak points.
- Reduce the Q/A HUD to a small grey pack name, question text, a two-physical-pixel countdown backdrop with a four-pixel overhanging fill, and one vertical list of clickable text choices without letter prefixes. The question font is four units larger than the answer font. Remove button art and permanent score/help labels; keep edit-only movement without a drag heading.
- Place the timer two physical pixels beneath the question and use a gold-to-red gradient as time expires. Reset reused text heights before measuring wrapped prompts/choices and round up to avoid ellipses or clipped final lines.
- Use text colors for hover, selection and confirmed correctness. Briefly animate the signed result delta (including streak bonus) beside the question and the fastest correct player below the answers, without replaying feedback. The gradient follows pack-defined timers, and first-answer locks leave the countdown running. Finite games reveal their final answer before ending automatically.
- Give all HUD text reusable addon-owned font objects with opaque black shadows at (+2, -2) physical pixels. Refresh on font/scale/display changes, preserve highlight colors and reserve clipped-viewport padding for shadows.
- Add a Settings tab with compact Orbit-style `Scale` and `Font` rows: a 50â€“200% Edit Mode slider in 5% steps with a gold value, plus a searchable SharedMedia font-preview picker. Save and re-render immediately while dragging/selecting without changing active questions or the setup window; bundle standalone libraries, retain missing-font preferences and retry failed font loads on settings/media updates.
- Upgrade session/discovery to protocol 8 with pack rules, self-contained score/streak receipts, fastest-correct metadata and compact group streak milestones. Synchronize bounded player-name dictionaries without delaying question readiness or score persistence. Validate clocks, immutable session rules and calculated points before acknowledging; retry across questions/reconnects without duplicate awards or stale HUD feedback. All players must update. Live questions still exclude answer keys, explanations, sources and winner information; only hosts need packs.
- Add account-wide per-pack progress across hosts/characters. Personal schema 2 preserves earlier pre-ruleset scores and separates new totals by canonical ruleset; content-only updates keep the same row. Keep Store schema 6 and all decimal/100-point league archives unchanged. New host standings/streaks start at zero. Personal statistics and rules keys are not anti-cheat-verified rankings.
- Place game and score list scrollbars just inside the setup window's right border. Size the reserved HUD score column from the pack's maximum rewards/penalties and chosen font before answering; keep a winner footer below the text so animations neither overlap scrolling answers nor shift the layout.
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

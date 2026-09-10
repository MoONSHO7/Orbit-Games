# User Interface

## Description

The shared Orbit-Games setup shell, game browser, controls, media catalogue and minimap launcher.

## Purpose

Present discovered game types and common preferences without owning a mode's rules, scoring or in-game renderer.

## Implementation

`Setup.lua` owns the native-styled window, Games/Host/Results/Settings navigation and mode-view placement. Host places a native Host-to checkbox dropdown above Game Type; its persisted Server/Guild/Party selection cannot become empty, and both selectors lock while hosting or joined to a session. Shared and mode-owned Host options consume one form-label contract so native controls keep a common type role and value boundary. Games keeps current-session status and Leave in a shared footer; each mode supplies a Host footer with Orbit's button grid and its Results presenter. The shared divider is visible only while the active page exposes footer actions. Shared UI delegates host behavior and live HUD work to the mode.

`Controls.lua`, `ScrollBar.lua`, `FontPicker.lua` and `SettingsControls.lua` own reusable native controls. Scrolling labels accept physical text insets so clipped HUD text can retain its shadow padding; join descriptions animate only when clipped and retain animation progress across unrelated discovery updates.

`Media.lua` resolves the bundled logo, SharedMedia fonts and mode-requested sound paths. `Minimap.lua` registers one LibDataBroker/LibDBIcon launcher; left-click routes `/og`, right-click opens Settings, and the library owns dragging and its private tooltip.

Quiz names its Results tab “Scores”; Cards uses the shared “Results” label. Quiz exposes only Personal score and Current game in its scope dropdown, with no passive bottom guidance or visible scoring-rule paragraphs, so its scrolling list occupies the reclaimed page space. Its Q/A renderer permanently shows the player’s current total in the right lane and overlays each confirmed signed delta there without moving the total. Hovering the total requests current host standings and opens a Quiz-owned private tooltip with up to 100 ranked players; nothing is downloaded until hover. `/og scores` and Cards `/og results` open the active mode's Results page, `/og packs` opens Quiz Host, and `/og status` opens Games. Archived Quiz standings remain preservation-only with no visible projection. Score/Q&A and table/session-result presenters stay inside their respective mode directories.

## Gotchas

- Only an open `/og` window enables a mode's edit presentation. Even then, movement begins only on the literal Quiz question text or the five-card Cards community row; full frames, backgrounds, answers, player rows and actions do not drag. Closing setup locks movement without leaving the active game.
- Keep the setup root hidden until construction finishes; presenter refreshes may run while mode controls are being created.
- Do not copy the minimap save subtree before passing it to LibDBIcon, create a second broker button, or own the global `GameTooltip`.
- Quiz score hover must own and hide only its private tooltip. Hover requests and revisioned snapshot refreshes must not submit answers, alter totals, persist receipts or replay result feedback.
- Pixel caches include physical resolution and effective scale. Shared chrome and mode renderers must snap roots as well as offsets.
- The Edit Mode slider captures callbacks during template OnLoad. Unregister native callbacks before addon callbacks and guard programmatic synchronization. Its outer row is a plain Frame, so enabled state must delegate to the inner MinimalSlider.
- Font menus close with their owner, retain search focus for Escape and reuse bounded visible rows. Probe external assets with FontStrings; `Font:SetFont` has no success return. Never intercept Blizzard's global `CloseSpecialWindows`.
- Scroll children declare explicit content bounds; cancel old motion and reset to zero even when already at zero. Accumulate easing in unsnapped coordinates so subpixel steps cannot stall.
- A mode renderer receives confirmed state. Shared UI must not manufacture timer-only results, scores or replayable feedback.
- The shared notice lane is reserved for real action or session failures and stays hidden otherwise; passive hints and mode guidance do not belong there.
- Notices are the error/status boundary; the shell must never fall back to a visible-chat post.
- Pages without footer actions show neither the footer nor its divider.
- Results presenters use the full actionless page body; do not reserve a passive guidance lane beneath their lists.
- Keep the Games notice lane between its fixed-height browser and footer. Extending the list into that space makes real join/leave failures overlap its final rows.

## References

- [Application](../App/README.md), [Cards UI](../Modes/Cards/README.md), [Quiz UI](../Modes/Quiz/README.md), [saved preferences](../Data/README.md) and [verification](../Docs/QUICKSTART.md).
- Orbit visual references live under `../../Orbit/Orbit/`; they are references, not runtime dependencies.
- Workspace skills: `wow-frames`, `pixel`, `orbit-skinning`, `strata-strategy`, `wow-secrets` and `orbit-debug`.

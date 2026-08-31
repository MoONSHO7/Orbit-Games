# User Interface

## Description

The setup/game browser and minimal Q/A HUD, with standalone native-styled controls.

## Purpose

Present game/session state and edit the widget's appearance without owning quiz rules, networking or score accounting.

## Implementation

`Setup.lua` exposes `Quiz.UI`: explicit joins, pack selection, read-only rule summaries, distinct personal/current-game/archive views and appearance settings. Saving appearance calls `Widget:ApplySettings` synchronously without altering the host draft or active answer.

`Widget.lua` renders the saved-anchor Q/A HUD: pack name, wrapped prompt, two-physical-pixel timer and left-aligned choices. It reserves the score column from rule bounds/font metrics before answering and a separate winner footer below the answers. Score/winner feedback share animation construction while retaining independent receipt/replay gates.

`Controls.lua` owns native buttons, inputs, gold tabs, dropdown adapters, housing-container panels and tapered dividers. `ScrollBar.lua` owns explicit scroll bounds and active-only animated motion. `SettingsControls.lua` adapts native Edit Mode sliders to compact label/control/value rows.

`FontPicker.lua` owns both its arrow control and private searchable, virtualized popup. `Media.lua` resolves the shared font catalogue and reports changes through the application-supplied callback; it does not call setup/HUD owners. Missing names retain their saved preference.

## Gotchas

- Only an open `/oq` window enables the purple edit outline and dragging. A live HUD has no Close/Escape action; closing setup locks position without leaving. Leave/Stop ends play.
- Layout uses widget-local units; convert through the frame's scale for screen bounds and compare scaled rectangles for drag persistence. Horizontal screen thirds and the vertical half determine alignment/growth. Reflow must not rewrite the normalized saved anchor.
- Pixel caches include physical resolution and effective scale. Snap root origins as well as offsets; timer/outline thickness, shadows (-2, -2), and press depth stay physical pixels at every scale.
- `SetAtlas` loads housing-container NineSlice metadata. Keep that native art and setup button FontStrings/state scripts; never flatten the container or replace native fonts.
- HUD labels are independent FontStrings, not `Button:SetFontString` labels. Only the pressed text shifts one physical pixel. Release, leave, hide, disable, drag and reflow restore it without moving hit areas.
- Clear reused FontString height before measuring; wrap without line limits and round height up to a pixel. Use addon-owned font objects plus a hidden FontString success probe; failed external assets fall back uncached and retry only on settings/media updates.
- Font changes reflow all HUD labels without changing selection, deadline, game state or setup scale. Shadows/press depth need padding inside the clipped child; acknowledgement-only updates must not trigger layout or reset idle feedback.
- The Edit Mode slider captures callbacks during template OnLoad. Unregister `cbrHandles` before quiz callbacks, retain native track/stepper scripts, and guard programmatic synchronization against saving again.
- Font menus close with their owner and reuse a bounded visible-row pool. Search keeps focus after Enter/clear so Escape closes only the popup; never intercept Blizzard's global `CloseSpecialWindows`.
- Scroll children declare full content bounds at the viewport's inherited scale. Batch layout and cancel old motion; reset with `ScrollTo(0, true)` even when already at zero. Keep unsnapped motion separate from snapped rendering; transient native descendant ranges are not authoritative.
- Only confirmed results color correctness or animate feedback. No timer-only results, no replay on reconnect/refresh, and no question/answer movement during a reveal.

## References

- [Application](../App/README.md), [saved appearance](../Data/README.md), [verification](../Docs/QUICKSTART.md), and [UI regressions](../Dev/Tests/README.md).
- Orbit visual references live under `../../Orbit/Orbit/`: `Core/Foundation/DialogChrome.lua`, `Core/Config/Panels/OrbitSettingsDialog.lua`, Config widgets, and `Plugins/ErrorMessages/`. These are references, not runtime dependencies.
- Blizzard source: `../../wow-ui-source/Interface/AddOns/` — SharedXML native controls, Menu dropdown templates, EditMode slider templates, and generated Font/FontString/animation/texture APIs.
- Workspace skills: `wow-frames`, `pixel`, `orbit-skinning`, `strata-strategy`, `wow-secrets`, and `orbit-debug`.

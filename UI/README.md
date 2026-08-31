# User Interface

## Description

The setup/game browser and minimal Q/A HUD, with standalone native-styled controls.

## Purpose

Present game/session state and edit the widget's appearance without owning quiz rules, networking or score accounting.

## Implementation

`Setup.lua` exposes `Quiz.UI`: explicit joins, pack selection, read-only rule summaries, distinct score views and local preferences. Appearance saves call `Widget:ApplySettings`; volume saves call `StreakToasts:SetVolume` without reflowing the HUD, clearing toasts or changing host setup.

`Widget.lua` renders the saved-anchor Q/A HUD: pack name, wrapped prompt, two-physical-pixel timer and left-aligned choices. It reserves the score column from rule bounds/font metrics, then separate winner and streak-toast slots below the answers. All feedback has independent receipt/replay gates; revealing it never changes Q/A geometry.

`StreakToasts.lua` owns a transparent native-art burst, masked shine and serialized SFX playback. The widget consumes confirmed group milestones, deduplicates by host/session/round/player, and supplies its font objects and bounded footer slot. Late name resolution adds only unseen players. The pending queue is bounded to 32 entries and coalesces each waiting player's latest streak. The queue-drained callback ends a temporary preview only after both visuals and audio finish.

`Controls.lua` owns native buttons, inputs, gold tabs, dropdown adapters, panels, dividers and clipped scrolling labels. Join descriptions animate only their overflow, using native out-and-back translations with endpoint pauses. `ScrollBar.lua` owns explicit scroll bounds and active-only animated motion. `SettingsControls.lua` adapts native Edit Mode sliders to compact label/control/value rows.

`FontPicker.lua` owns both its arrow control and private searchable, virtualized popup. `Media.lua` resolves the shared font catalogue and bundled streak sound paths. Font changes reach the application-supplied callback, never setup/HUD owners directly. Missing font names retain their saved preference.

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
- Retain unchanged game rows across discovery updates so long descriptions can finish scrolling. Place the clipping viewport, not its full-width FontString; recompute overflow on reflow and stop native translations when hidden, recycled or no longer truncated.
- Live feedback requires confirmed results. No timer-only results, no replay on reconnect/refresh, and no question/answer movement during a reveal. `SetStreakPreview` is a separate idle-only presentation hook for development fixtures: read-only Q/A, no fake session/result data, and no persistence. It rejects live membership and yields immediately when play starts.
- Streak toasts may drain across ordinary question changes. Pause, restrictions, leave, any session end, host switch, hiding, dragging or appearance reflow cancel pending playback without replay. A finite game's final reveal is not extended to drain toasts.
- Custom-file playback has no per-sound gain API. `Media:GetStreakSound` selects pre-attenuated Ogg variants for 10–90%, original MP3s at 100%, or no sound at 0%. Keep SFX routing and never change global sound CVars. Regenerate variants with `Dev/SoundVolumes.py` after replacing originals.
- Nonzero volume changes apply to the next clip; muting stops only the owned current sound. Visuals/queued milestones remain, and unmuting never replays a consumed clip. Playback failure must not break visual feedback.
- A 3.2-second animation is not proof that native playback has finished. Normal advancement checks `C_Sound.IsPlaying`, polls only an outstanding audio tail, and never calls `StopSound`; explicit cancellation/mute still do. Clear removes the poll before stopping anything.
- Burst art uses 80% of its reserved text slot, centered with a four-physical-pixel drop and symmetric pixel-snapped insets. The shine follows those bounds. Allow downward art overhang at small scales without clipping; the HUD's screen margin contains it. There is no background or divider. Player name sits above only `X in a row`, never a sound-tier title. At 10+ the caption alone pulses from 100% to 120% and back during the shine; native transforms leave text layout and Q/A geometry unchanged and are stopped on cancellation/reuse.

## References

- [Application](../App/README.md), [saved appearance](../Data/README.md), [verification](../Docs/QUICKSTART.md), and [UI regressions](../Dev/Tests/README.md).
- Orbit visual references live under `../../Orbit/Orbit/`: `Core/Foundation/DialogChrome.lua`, `Core/Config/Panels/OrbitSettingsDialog.lua`, Config widgets, and `Plugins/ErrorMessages/`. These are references, not runtime dependencies.
- Blizzard source: `../../wow-ui-source/Interface/AddOns/` — SharedXML native controls, Menu/EditMode templates, generated rendering APIs, `Blizzard_FrameXML/ArtifactToasts.xml`, and `Blizzard_FrameXML/Mainline/AlertFrameSystems.xml` for toast/glow art.
- Workspace skills: `wow-frames`, `pixel`, `orbit-skinning`, `strata-strategy`, `wow-secrets`, and `orbit-debug`.

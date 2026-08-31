# Application

## Description

Startup declarations, application text, and coordination of the standalone quiz.

## Purpose

Keep WoW events and user commands at the application boundary while game rules, network state, storage and UI retain their own owners.

## Implementation

`Init.lua` establishes the shared addon namespace, public `OrbitQuiz` registration entry point, constants and source version. `Locale.lua` supplies the shared/runtime/widget strings and localized pack-registration diagnostics before consumers capture them; Spanish-Mexico and British-English diagnostics retain their existing locale aliases.

`Runtime.lua` owns `Quiz.Main`: `ADDON_LOADED` binds SavedVariables and communication callbacks; `PLAYER_LOGIN` starts discovery and the ticker. Slash commands and UI actions enter the same host lifecycle. The ticker advances readiness, author-defined answer/reveal deadlines, transport retries and interruption recovery.

Host closure takes results from the game, records personal receipts, and queues participant receipts before revealing. Finite quizzes finish after their final reveal. Runtime also supplies the media-change callback to `UI/Media.lua`, applying widget settings and refreshing the settings view only after successful initialization.

## Gotchas

- A live game snapshots its pack's rules. Setup changes cannot change an active game's timing, scoring, selections or results.
- Manual Pause voids an unfinished question and remains paused. Communication restrictions automatically pause and resume fresh; completed finite games retry the final receipt and restart the reveal interval after recovery.
- A failed local personal-score write must not prevent other participants' completed receipts being queued. Expected storage failure then pauses hosting; unexpected errors reach WoW's error handler/BugSack.
- Logout/reload end membership and cancel the ticker. Discovery remains available between games, not after logout.
- Media initialization can notify synchronously and repeat after another addon loads. Bind the callback before registration and retain the application's initialized gate; the font catalogue must not know about setup or HUD owners.
- Release automation stamps `App/Init.lua` only in its runner checkout. The TOC's `@project-version@` and runtime version must agree in the packaged addon.

## Secrets

WoW restriction events and native addon/error arguments are checked before comparison or parsing. Runtime coordinates chat-lockdown suspension; it does not handle secret unit-health/power data.

## References

- [Gameplay](../Game/README.md), [networking](../Network/README.md), [persistence](../Data/README.md), and [UI](../UI/README.md).
- [Offline checks](../Dev/Tests/README.md) and [release workflows](../.github/workflows/README.md).

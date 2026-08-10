# Task 16 report — routine occurrence workflows

Base: `12937635d90a059ad0afb2f1f18878b7d7e076f2`.

## Delivery

- Added routine list, snapshot-resolved detail, own item-history, action sheet and snooze UI.
- Added typed `RoutineRoute` values containing only kind, optional item id and destination.
- Today routine rows now navigate by stable item id. Detail performs the documented list read at its route entry, then selects from that snapshot; it owns no provider or detail endpoint.
- List/history use their matching invalidation revisions; history only presents load-more while a non-nil opaque cursor exists.
- Action UI uses the exact pending occurrence, provider-authoritative refreshes, `@AccessibilityFocusState`, and never synthesizes a release receipt.
- Corrected two UI-test fixture assumptions without changing the real policy:
  - the exact actionable supplement schedule is `rule-08` (not the earlier snoozed `rule-20`);
  - crossing-date test uses a Debug-only `--ui-testing-routine-crossing-date` clock at 23:50 BRT. Release has no time override.
- Added a Debug-only `routineActionUnavailable` scenario: reads remain loaded while the routine command returns unavailable, so the no-simulated-success assertion reaches the action.

## Literal test audit

- `RoutineViewModelTests`: 11 tests, covering list order/include-archived, read states, revision deduplication, snapshot-only detail and Today-origin list read, opaque-cursor append/nil cursor, cancellation and supersession.
- `RoutineActionModelTests`: 13 tests, covering exact command fields, presets/custom/cross-date snooze, retry retention, unavailable/focus/no optimism, exact conflict invalidation and refresh, success invalidation, cancellation, supersession and in-flight deduplication.
- `RoutinePresentationTests`: 3 tests, covering literal schedules/statuses/history rows and empty-versus-unavailable presentation.
- `Prompt13RoutineUITests`: six required named scenarios, with the crossing-date and unavailable-action launches made deterministic as described above.

## Verification evidence

- Focused UI GREEN:
  - `testSupplementTakenUsesExactOccurrence` — 14:01, succeeded.
  - `testMedicationSkippedUsesExactOccurrence` — 14:01, succeeded.
  - `testSnoozeOffers15_30_60AndCustom` — 14:02, succeeded.
  - `testCrossingDateSnoozeIsUnavailable` — 14:03, succeeded.
  - `testRoutineHistoryLoadMoreAppendsNextPage` — 14:03, succeeded.
  - `testUnavailableRoutineActionShowsNoSuccess` — 14:06, succeeded.
- Model/presentation gate: 27/27 passed, xcresult `Test-BodyFlow-2026.08.01_14-06-38--0300.xcresult`.
- Final model/presentation gate: 27/27 passed, xcresult `Test-BodyFlow-2026.08.01_14-09-09--0300.xcresult`.
- Final UI gate: 6/6 passed, xcresult `Test-BodyFlow-2026.08.01_14-09-57--0300.xcresult`.
- Final `git diff --check` passed.

## Discarded runs

- 13:57 focused UI build failed before execution because the newly created list row lacked an explicit `id`; corrected with `id: \\.id`.
- First focused supplement run at 13:59 failed functionally because UI selected `rule-20`; corrected to prefer the response's pending occurrence `rule-08`.
- First unavailable UI run at 14:04 failed functionally before action entry because the broad unavailable fixture hid Today. Replaced by the targeted Debug-only action-unavailable scenario.
- Simulator emitted known LLDB version and duplicate accessibility-loader warnings during successful runs; these did not cause test failures and were not retried as flakes.

## Fix round 1 — review findings

- List-to-detail now passes the loaded `RoutineListViewModel` into the detail entry, so that path resolves the already-owned snapshot without another list request. Today remains the separate entry that owns exactly one list read. `RoutineViewModelTests` uses the read spy for both origins.
- Today exposes stable `routine.list.supplement` and `routine.list.medication` links; the UI regression navigates to each list and verifies its stable row id.
- The real `routineConflictOnce` fixture's `routineTransitionInvalid` now advances only the matching routine-list and item-history revisions. The regression reloads both owners and confirms their conflict fixtures; Today remains at revision zero.
- Any submission while a routine mutation is in flight is ignored. The primary action buttons and all snooze preset/custom controls are disabled while submitting. The regression sends 15- then 30-minute snooze and proves one provider call/key.

## Fix round 1 TDD evidence

- RED #1: focused `RoutineViewModelTests/detailRouteCompositionSharesLoadedListAndLoadsTodayOnce` at 14:18 failed to compile because `RoutineDetailEntry` did not yet exist. GREEN: `/tmp/bodyflow-task16-f1-green.xcresult`, 12/12 passed.
- RED #2: `testSupplementAndMedicationListsAreReachable` at 14:20 failed because `routine.list.supplement` was absent. GREEN: `/tmp/bodyflow-task16-f2-green.xcresult`, 1/1 passed.
- RED #3/#4: `/tmp/bodyflow-task16-f3-red-suite.xcresult`, 12/15 passed: the fixture conflict left list revision at zero, and distinct/snooze intents made two calls. GREEN: `/tmp/bodyflow-task16-f3-f4-green.xcresult`, 15/15 passed.
- Final Task 16 model/presentation gate: `/tmp/bodyflow-task16-model-presentation-final.xcresult`, 30/30 passed.
- Final `Prompt13RoutineUITests` gate: `/tmp/bodyflow-task16-ui-final.xcresult`, 7/7 passed.
- Debug and Release simulator builds passed. Final `git diff --check` passed.

## Fix round 3 — status-only refresh and terminal eligibility

- The detail now retains the complete applied `RoutineActionConfiguration`, not only occurrence context. A status-only refresh under the same rule and scheduled time reapplies after any in-flight submission ends.
- Action selection explicitly prioritizes `pending`, then accepts `snoozed`; `taken` and `skipped` alone yield no actionable context, so terminal occurrences do not expose another action or retry path.
- The action sheet owns the model selected at presentation and defers detail reconfiguration until dismissal. This preserves the provider receipt through a success refresh while subsequent actions use the refreshed configuration.
- The list-origin entry regression additionally calls its Today-load method at a new revision and proves the shared list owner makes no provider read.

## Fix round 3 TDD evidence

- RED status-only: `/tmp/bodyflow-task16-r3-status-red.xcresult` failed before full configuration application existed. GREEN: `/tmp/bodyflow-task16-r3-status-green.xcresult` passed; pending→snoozed and pending→taken keep rule/time while changing applied configuration or removing actionability.
- The first r3 UI gate exposed a deterministic recoverable failure instead of a receipt. Causal triage found that a combined pending-or-snoozed search chose the earlier snoozed `rule-20` instead of fixture-required pending `rule-08`.
- RED priority: `/tmp/bodyflow-task16-r3-priority-red.xcresult`, 15/16 passed, proved `[snoozed, pending]` selected snoozed. GREEN: `/tmp/bodyflow-task16-r3-priority-green.xcresult` passed after restoring `pending`-then-`snoozed` priority.
- Receipt regression GREEN: `/tmp/bodyflow-task16-r3-receipt-green-final.xcresult`, confirms a successful refresh keeps `taken` visible in the presented sheet.
- Final Task 16 model/presentation gate: `/tmp/bodyflow-task16-r3-model-presentation-final-2.xcresult`, 31/31 passed.
- Final `Prompt13RoutineUITests` gate: `/tmp/bodyflow-task16-r3-ui-final-2.xcresult`, 8/8 passed.
- Debug and Release simulator builds passed. Final `git diff --check` passed.

## Fix round 2 — list detail action initialization

- `RoutineDetailView` now configures its action model on first appearance, which covers a detail that receives the already-loaded list snapshot directly.
- Action configuration is a value containing the full routine schedules and resolved occurrence context. The detail observes that value rather than only schedule IDs, so a refresh under the same reminder-rule ID (including occurrence status or scheduled-time changes) reconfigures the action model; it preserves an in-flight submission and clears the model when no occurrence remains.
- `Prompt13RoutineUITests` opens the supplement and medication list links, opens each row, and requires Tomado, Adiar, and Pular.
- `RoutineActionModelTests` verifies action configuration changes for the same rule ID when the occurrence status and scheduled time change.

## Fix round 2 TDD evidence

- RED UI: `/tmp/bodyflow-task16-r2-ui-red.xcresult` failed because list-origin detail lacked `routine.action.taken`. GREEN: `/tmp/bodyflow-task16-r2-ui-green.xcresult`, 1/1 passed for supplement and medication.
- RED component: `/tmp/bodyflow-task16-r2-component-red.xcresult` failed before `RoutineOccurrenceContext.actionContext` existed. GREEN: `/tmp/bodyflow-task16-r2-component-green.xcresult`, 16/16 passed.
- RED refresh-signature: `/tmp/bodyflow-task16-r2-refresh-red.xcresult` failed before `RoutineActionConfiguration` existed. GREEN: `/tmp/bodyflow-task16-r2-refresh-green-2.xcresult`, 16/16 passed with the same reminder rule ID and changed occurrence status/scheduled time.
- Final Task 16 model/presentation gate: `/tmp/bodyflow-task16-r2-model-presentation-final-3.xcresult`, 31/31 passed.
- Final `Prompt13RoutineUITests` gate: `/tmp/bodyflow-task16-r2-ui-final-2.xcresult`, 8/8 passed.
- Debug and Release simulator builds passed. Final `git diff --check` passed.

## Fix round 4 — presented-sheet retry snapshot

- `RoutineActionSheetItem` now captures retry eligibility when the action sheet is presented. The sheet no longer reads the detail's live action configuration while it is open.
- The deterministic one-time routine conflict reload now contains terminal occurrences only. That makes the refreshed action configuration nil while retaining the already-presented action model and its recoverable error until dismissal.
- Dismissing the sheet still reconfigures from the refreshed terminal snapshot, so no new terminal action buttons or out-of-sheet retry become available.
- A conflict retry keeps the exact failed `MutationAttempt`, including its idempotency key.

## Fix round 4 TDD evidence

- RED: `/tmp/bodyflow-task16-r4-red.xcresult`, 0/1 passed. `testConflictSheetKeepsRetryUntilDismissAfterTerminalRefresh` reached the recoverable conflict error after the terminal list refresh and failed because `Tentar novamente` disappeared from the open sheet.
- GREEN: `/tmp/bodyflow-task16-r4-green-ui.xcresult`, 1/1 passed after retry eligibility became part of the captured sheet item. The regression proves the error and Retry remain before dismiss and `routine.action.taken` is absent after dismiss.
- Final Task 16 model/presentation gate: `/tmp/bodyflow-task16-r4-model-presentation.xcresult`, 32/32 passed, including conflict retry attempt/key preservation.
- Final demo-fixture gate: `/tmp/bodyflow-task16-r4-demo-routine.xcresult`, 28/28 passed.
- Final `Prompt13RoutineUITests` gate: `/tmp/bodyflow-task16-r4-ui.xcresult`, 9/9 passed.
- Debug and Release simulator builds passed. Final `git diff --check` passed.

## Fix round 5 — terminal conflict fixture consistency

- The terminal conflict fixture now emits `snoozedUntil` only for a `snoozed` first schedule. Its terminal `taken` occurrences carry no snooze deadline, while the regular snoozed fixture remains unchanged.
- `DemoRoutineRepositoryTests` reads the authored conflict reload and asserts both terminal occurrence statuses and both nil `snoozedUntil` values.

## Fix round 5 TDD evidence

- The first single-test selector produced an Xcode plan with no executed tests (`unknown`, 0); it was not used as RED evidence. RED suite: `/tmp/bodyflow-task16-r5-red-suite.xcresult`, 27/28 passed. The new literal assertion reported `[timestamp, nil]` instead of `[nil, nil]`.
- GREEN demo-fixture gate: `/tmp/bodyflow-task16-r5-demo-green.xcresult`, 28/28 passed.
- Final Task 16 model/presentation gate: `/tmp/bodyflow-task16-r5-model-presentation.xcresult`, 32/32 passed.
- Final `Prompt13RoutineUITests` gate: `/tmp/bodyflow-task16-r5-ui.xcresult`, 9/9 passed.
- Debug and Release simulator builds passed. Final `git diff --check` passed.

# Task 19 report — Bounded individual-row History

## Scope delivered

- Added the long-lived shell-owned `HistoryViewModel` and
  `HistoryFeatureCoordinator`, with ID-only main, meal-row, and workout-row
  routes on the independent Today stack.
- Main History performs a single revision-owned complete read using only
  `HistoryQuery.firstPage`; retry repeats that same bounded read. It has no
  cursor, next-page state, or load-more command.
- Snapshot lookup returns individual immutable meal/workout rows from loaded,
  offline-stale, or failed-stale data. Detail destinations accept rows by value
  and neither hold a provider nor load data.
- Preserved provider array order and individual matching-time meal rows; global
  empty requires both meal and workout arrays to be empty.
- Added the required UI journeys and IDs: `screen.history`, `history.meals`,
  `history.meal.<row-id>`, `history.workouts`, `history.workout.<id>`, and
  `history.empty`. No `history.load-more` identifier was created.

## RED evidence

1. `/tmp/bodyflow-task19-red-units.xcresult` failed as expected because
   `HistoryPresentation` and History model APIs did not yet exist.
2. `/tmp/bodyflow-task19-red-coordinator.xcresult` failed while the newly added
   History route cases had no destination ownership implementation.
3. `/tmp/bodyflow-task19-red-ui.xcresult` failed before History UI existed;
   the expected typed route cases were absent from the scaffold.
4. The first serial UI result, `/tmp/bodyflow-task19-ui-serial-3.xcresult`,
   found three real accessibility failures: History section and empty-state IDs
   were not materialized independently in the XCUI hierarchy. The later
   serial-4 run reduced this to the empty-state identifier only.

The overlapping UI bundles from the interrupted runners were discarded and are
not used as verification evidence.

## GREEN evidence

- Focused units (`HistoryViewModelTests`, `HistoryPresentationTests`, and
  `AppRouterTests`): 15 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task19-units-serial.xcresult`
- Focused empty-state UI regression: 1 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task19-history-empty-serial-3.xcresult`
- Complete `Prompt13PlanProgressHistoryUITests`: 10 passed, 0 failed,
  0 skipped.
  `/tmp/bodyflow-task19-ui-serial-green.xcresult`
- Debug and Release builds on iPhone 17 Pro
  `27291590-659D-4A29-8F45-CA5CA2D154F9` both reported
  `** BUILD SUCCEEDED **`.
- `git diff --check` passed before staging.

## Limits retained

- Main History exposes no load-more, derived cursor, detail API, provider in a
  destination, local row patch, grouping, sorting, merging, `meal_id`, or
  aggregate meal detail.
- The feature displays only individual meal records and workouts.
- Debug/test fixtures remain behind existing Debug configuration; Release keeps
  the existing unavailable capability graph. No live service, secret,
  migration, deployment, merge, or TestFlight work was added.

## Review correction

- The History stale retry now uses the shared 44pt minimum tap target on its
  button label (the accessibility node actually measured by XCTest), with the
  shared headline typography. A Debug-only UI-test setup preloads the normal
  History `firstPage` response and retry under the existing stale-offline
  scenario; it is compiled out of Release and adds no endpoint or pagination
  behavior in Release.
- Workout detail uses `ScrollView`, and the Debug fixture now contains a long
  workout type so the accessibility-size UI test verifies that the energy
  field remains reachable after scrolling.
- Added History-owned controlled-provider coverage for literal initial offline;
  cancelled revision-0 late snapshot and late error suppression; and newer
  revision precedence over late old snapshot and error. Every query remains
  `.firstPage`.

### Review RED evidence

- `xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9'
  -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests/testStaleHistoryRetryUsesMinimumTapTarget
  -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests/testWorkoutDetailScrollsWithLongValueAtAccessibleDynamicType
  test -resultBundlePath /tmp/bodyflow-task19-review-red-ui-targeted.xcresult`
  failed before the correction: the stale flow did not materialize the History
  retry without test setup, and the long workout fixture value was absent.
- After the Debug-only stale-flow setup, the complete History UI class failed
  at the actual regression: `state.retry` measured **20.33pt** high, below
  44pt. The long-value scroll test already passed after its fixture and
  `ScrollView` correction. Result:
  `/tmp/bodyflow-task19-review-ui-green.xcresult` (12 executed, 1 failed).

### Review GREEN evidence

- Focused History units (`HistoryViewModelTests`, `HistoryPresentationTests`,
  and `AppRouterTests`): **20 passed, 0 failed, 0 skipped**.
  `/tmp/bodyflow-task19-review-units-green.xcresult`
- Complete `Prompt13PlanProgressHistoryUITests`: **12 passed, 0 failed,
  0 skipped**. This includes the stale retry 44pt assertion and the
  AccessibilityXXXL long workout scroll journey.
  `/tmp/bodyflow-task19-review-ui-final-green.xcresult`
- Debug and Release builds, each using iPhone 17 Pro
  `27291590-659D-4A29-8F45-CA5CA2D154F9`, reported `** BUILD SUCCEEDED **`.
- `git diff --check` passed before staging the amended commit.

## R2 hardening

- `HistoryViewModel.load(revision:)` now returns before changing either
  `currentRevision` or state when its task is already cancelled. A subsequent
  retry therefore keeps using the last valid revision and its bounded
  `.firstPage` request.
- `HistoryControlledProvider.waitUntilStarted` now uses the existing
  `ContinuousClock` + `Issue.record` deadline pattern (two seconds) instead of
  an unbounded yield loop. Controlled tests return after a recorded timeout.
- Supersession tests now resolve the old value/error while the newer revision
  remains pending, immediately assert that the model is still `.loading`, and
  only then resolve the newer response.

### R2 RED/GREEN evidence

- RED: `HistoryViewModelTests` failed in
  `/tmp/bodyflow-task19-hardening-red-units.xcresult` before the guard:
  a pre-cancelled initial load published `.loading`, and a pre-cancelled
  revision 1 advanced bookkeeping so the valid revision-0 retry timed out.
- GREEN focused units (`HistoryViewModelTests`, `HistoryPresentationTests`,
  `AppRouterTests`): **22 passed, 0 failed, 0 skipped**.
  `/tmp/bodyflow-task19-hardening-units-green.xcresult`
- GREEN UI class `Prompt13PlanProgressHistoryUITests`: **12 passed, 0 failed,
  0 skipped**. `/tmp/bodyflow-task19-hardening-ui-green.xcresult`
- Debug and Release builds on iPhone 17 Pro
  `27291590-659D-4A29-8F45-CA5CA2D154F9` both reported
  `** BUILD SUCCEEDED **`; `git diff --check` passed before staging.

## R3 test hardening

- No production implementation changed. The two supersession tests now await
  completion of the old task before asserting `.loading` while the new request
  is still pending, closing the transient-publication gap in the proof.
- `retryUsesFirstPageAgain` now verifies the literal initial
  `.failed(previousValue: nil, error: .serviceUnavailable)` state before
  invoking Retry.
- `testHistoryHasNoLoadMore` now waits for `history.meals` before its negative
  assertions. `testHistoryHasOnlyMealsAndWorkouts` waits independently for both
  positive section markers before checking excluded sections.
- This is test-only hardening of already-correct behavior; no temporary
  production mutation was needed.

### R3 verification evidence

- Focused units (`HistoryViewModelTests`, `HistoryPresentationTests`, and
  `AppRouterTests`): **22 passed, 0 failed, 0 skipped**.
  `/tmp/bodyflow-task19-r3-hardening-units.xcresult`
- Complete `Prompt13PlanProgressHistoryUITests`: **12 passed, 0 failed,
  0 skipped**. `/tmp/bodyflow-task19-r3-hardening-ui.xcresult`
- Debug and Release builds on iPhone 17 Pro
  `27291590-659D-4A29-8F45-CA5CA2D154F9` both reported
  `** BUILD SUCCEEDED **`; `git diff --check` passed before staging.

## R4 integrated test closure

- No production implementation changed. An integrated History test now drives
  `FeatureInvalidationCenter` from revision 0 through
  `.registrationConfirmed`, verifies one complete replacement snapshot, and
  verifies both repeated-revision dedupe and that `.hydrationRecorded` leaves
  the History revision unchanged. Its exact provider queries are
  `[.firstPage, .firstPage]`.
- A controlled-provider test starts two concurrent loads for the same active
  revision, verifies that only one `.firstPage` request starts, then completes
  it and verifies the published snapshot.
- Missing meal and workout identifiers now have explicit model and coordinator
  coverage: every lookup returns `nil` and the provider query list remains the
  single initial `.firstPage` request.

### R4 verification evidence

- Focused units (`HistoryViewModelTests`, `HistoryPresentationTests`, and
  `AppRouterTests`): **25 passed, 0 failed, 0 skipped**.
  `/tmp/bodyflow-task19-r4-hardening-units.xcresult`
- Complete `Prompt13PlanProgressHistoryUITests`: **12 passed, 0 failed,
  0 skipped**. `/tmp/bodyflow-task19-r4-hardening-ui.xcresult`
- Debug and Release builds on iPhone 17 Pro
  `27291590-659D-4A29-8F45-CA5CA2D154F9` both reported
  `** BUILD SUCCEEDED **`.
- `git diff --check` passed before staging the amended commit.

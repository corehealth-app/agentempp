# Task 18 report — Progress and persisted 7,700 block

## Scope delivered

- Replaced the Progress scaffold with a `ProgressProviding`-backed read model
  and presentation of the complete response-shaped Progress snapshot.
- Preserved nullable weight, body-fat and `deficit_block` as unavailable rather
  than zero.
- Added a typed Progress block route. Its detail model receives only
  `TodayProviding` and maps only `TodayResponse.data.block7700`.
- Added cancellation and supersession suppression for Progress and block reads.
- Added three UI tests for received Progress values, Today-only block detail,
  and an unavailable block without zero values.

## RED evidence

1. `/tmp/bodyflow-task18-red.C7kU7G/Logs/Test/Test-BodyFlow-2026.08.01_17-04-16--0300.xcresult`
   failed because `ProgressViewModel`, `ProgressPresentation`, and
   `Block7700ViewModel` did not exist.
2. `/tmp/bodyflow-task18-deficit-red.GpvAlI` failed because
   `ProgressPresentation.deficitBlockText` did not exist.
3. `/tmp/bodyflow-task18-ui-green.VgoFHo/Task18UI.xcresult` made the UI RED
   visible: block-detail state identifiers were attached to a conditional
   container and absent from the XCUI hierarchy.
4. `/tmp/bodyflow-task18-ui-green2.V9m7hP/Task18UI.xcresult` caught the
   remaining block-detail formatting defect: `2500 kcal` was not the
   locale-consistent `2.500 kcal` expected by the UI.
5. `/tmp/bodyflow-task18-block-text-red.yzP3qU` failed because the block descriptor
   did not expose locale-formatted target/current/credited text.

## GREEN evidence

- Focused unit suites: 13 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task18-unit-final2.S64pcL/Task18Unit.xcresult`
- Complete `Prompt13PlanProgressHistoryUITests`: 5 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task18-ui-class.TQqmUj/Task18UIClass.xcresult`
- Debug build (iPhone 17 Pro `27291590-659D-4A29-8F45-CA5CA2D154F9`):
  `** BUILD SUCCEEDED **`.
  `/tmp/bodyflow-task18-debug-build.mtuXFg`
- Release build (same simulator): `** BUILD SUCCEEDED **`.
  `/tmp/bodyflow-task18-release-build.d1KC3p`
- `git diff --check` passed before staging.

## Limits retained

- No live service, transport adapter, secret, migration, deployment, merge or
  TestFlight behavior was added.
- Release continues to resolve the existing unavailable capabilities; no Demo
  fixture or test spy was introduced into the Release graph.
- The app formats supplied values only. It does not calculate XP, streaks,
  percentages, block credit, or repair the absent block from `deficit_block`.

## Fix history

### R1 — stale block disclosure

- Review finding: a retained block descriptor after offline or recoverable
  failure rendered without `StaleDataBanner`.
- RED: `/tmp/bodyflow-task18-stale-red.v7Bcec` failed because the block-detail
  presentation wrapper did not exist; the regression exercises a real loaded
  `Block7700ViewModel` followed by Retry with offline and recoverable errors.
- GREEN: `Block7700DetailPresentation` preserves the shared read-state
  presentation and `Block7700DetailView` now renders retained descriptors
  inside `FeatureStateContentStack`, which displays `StaleDataBanner`.
- Focused unit: 15 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task18-stale-green.4A34cI/Task18Unit.xcresult`
- UI class: 5 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task18-r1-ui.NoKgoV/Task18UIClass.xcresult`
- Debug and Release simulator builds succeeded:
  `/tmp/bodyflow-task18-r1-debug.FeotVD` and
  `/tmp/bodyflow-task18-r1-release.h3J0T0`.

### R2 — stale block retry

- Review finding: retained block content showed the stale banner but exposed no
  control to invoke its existing retry operation.
- RED: `/tmp/bodyflow-task18-r2-red.OCRL12` failed because
  `Block7700DetailPresentation` did not describe the stale-only retry affordance.
  The regression verifies retry is required for retained offline and
  recoverable-error descriptors, and absent for loaded, initial-offline and
  unavailable states.
- GREEN: the stale content branch now places one 44-point `Tentar novamente`
  button (`state.retry`) beside the shared stale banner and invokes
  `Block7700ViewModel.retry()`. Full-screen retry behavior is unchanged.
- Focused unit: 16 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task18-r2-unit.UMd9oF/Task18Unit.xcresult`
- UI class: 5 passed, 0 failed, 0 skipped.
  `/tmp/bodyflow-task18-r2-ui.QYrNNW/Task18UIClass.xcresult`
- Debug and Release simulator builds succeeded:
  `/tmp/bodyflow-task18-r2-debug.Z4a8TA` and
  `/tmp/bodyflow-task18-r2-release.m0IL0L`.

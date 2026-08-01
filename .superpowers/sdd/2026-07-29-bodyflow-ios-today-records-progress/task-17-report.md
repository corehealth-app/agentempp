# Task 17 — Stable Plan Presentation

## RED / GREEN evidence

- **Unit RED:** `PlanViewModelTests` and `PlanPresentationTests` were added
  before production implementation. The focused run failed with
  `Cannot find 'PlanPresentation' in scope`, proving the stable presentation
  surface was absent.
- **Unit GREEN:** `PlanViewModel`, `PlanPresentation`, the Plan root/detail
  views, and the typed route were added. Focused unit suites passed with 14
  Swift Testing executions (the runner reports each Swift Testing case twice).
- **UI RED:** the new Plan UI class initially failed for absent Plan state and
  detail navigation. The empty state was rendered but `state.empty` was not
  exposed as an XCUI element, so the UI test asserts the visible state copy.
  Tab selection now drives a binding-backed load task. The detail control is
  reached through a bounded four-swipe helper without changing the document
  order of stable fields.
- **UI GREEN:** `Prompt13PlanProgressHistoryUITests` passed 2/2.

## Result bundles

- Unit: `/tmp/bodyflow-task17-unit.xcresult` — passed, 14 executions.
- UI: `/tmp/bodyflow-task17-ui.xcresult` — passed, 2 XCTest cases on iPhone 17 Pro
  (`27291590-659D-4A29-8F45-CA5CA2D154F9`).

## Final gates

- Focused Plan unit suites: passed.
- Plan UI class: passed.
- Debug simulator build: passed.
- Release simulator build: passed.
- `git diff --check`: passed.

## Files changed

- `BodyFlow/Features/Plan/PlanViewModel.swift`
- `BodyFlow/Features/Plan/PlanComponents.swift`
- `BodyFlow/Features/Plan/PlanDetailView.swift`
- `BodyFlow/Features/Plan/PlanRootView.swift`
- `BodyFlow/App/AppRouter.swift`
- `BodyFlow/App/AppShellView.swift`
- `BodyFlowTests/PlanViewModelTests.swift`
- `BodyFlowTests/PlanPresentationTests.swift`
- `BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift`

## Contract limits preserved

- Only stable training metadata and nutrition prescription metadata are
  presented; nutrition `payload` remains opaque and is never rendered.
- No planned/completed counters or values from Today/History are used.
- The typed Plan route contains no mutable snapshot; detail reloads only
  `PlanProviding`.
- Empty and unavailable remain distinct. Offline and recoverable errors retain
  the exact prior `PlanSnapshot`; retries and cancelled/late reads are guarded
  by load ownership.
- Demo behavior stays in existing Debug/test providers; no Release fixture or
  success path was added.

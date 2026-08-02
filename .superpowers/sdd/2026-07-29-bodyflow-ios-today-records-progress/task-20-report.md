# Task 20 report — Runtime, telemetry, previews and accessibility

## Scope delivered

- Added a controlled Prompt 13 telemetry vocabulary for feature-screen views
  and registration outcomes. Metadata is allowlisted, registration capture
  source is meal-only, and domain errors map to bounded categories without raw
  payloads.
- `calculation_version` is emitted only when the complete value contains
  `1...64` ASCII bytes from `[A-Za-z0-9._:-]`. Invalid values are omitted; they
  are never trimmed, normalized, substituted or truncated. Event construction
  does not mutate the official Today snapshot.
- Added 22 deterministic SwiftUI previews covering loaded, loading, empty,
  offline, error, incomplete, unavailable, Dark Mode, Accessibility XXXL,
  Text/Photo/Audio meal proposals, pending edit, workout proposal, weight and
  hydration receipts, routine snooze/history, Plan, Progress, Block 7700 and
  the bounded main History. The entire preview surface and its local receipt
  composition are compiled only in Debug.
- Added the five-class Prompt 13 acceptance gate for independent tab stacks,
  initial and stale retries, stable 44pt targets, visible operation summaries,
  Dark Mode, Accessibility XXXL and the Debug-only Reduce Motion policy path.
- Evidence capture now accepts only the 13 approved PNG names, retains each PNG
  with `.keepAlways`, and attaches a separately named `.txt` accessibility
  hierarchy.

## TDD RED evidence

1. The initial telemetry tests failed before the feature screens,
   registration vocabulary, error mapping and strict calculation-version
   filter existed. Literal boundary tests covered one byte, 64 bytes, empty,
   65 bytes, whitespace, slash and non-ASCII input. The resulting GREEN suite
   also locks the pre-existing rejection boundary against raw patient and
   request fields while permitting only the new bounded keys.
2. A focused capture-source RED proved that non-meal registration factories
   could receive a meal source before the factory began omitting it.
3. Acceptance REDs exposed undersized interactive nodes: the Today refresh
   control measured 36pt, operation retries and routine controls were below
   44pt, and proposal actions measured about 32.97pt. The minimal fixes are
   isolated in checkpoint commits `bdff41d`, `dec83bd`, `05b6fe1` and
   `6c17153`.
4. Retry-transition REDs showed the terminal retry node never left the
   hierarchy during a repeated deterministic failure. The Debug scenarios now
   publish a real loading transition before their next terminal result; this
   is isolated in checkpoint commit `e582fd2`.
5. `/tmp/bodyflow-task20-dark-effective-red.xcresult` proved that launch
   arguments alone left SwiftUI's effective scheme at `light`. The corrected
   test changes the simulator appearance, asserts the running root reports
   `dark`, and restores Light afterward.
6. The first AXXXL evidence allowed a partially chrome-occluded History row to
   satisfy a window-only containment check. The final focused regression in
   `/tmp/bodyflow-task20-xxxl-viewport-green.xcresult` uses
   `today.next-action` as the representative control and proves its complete
   frame remains between the navigation and tab bars.

## Final GREEN gate

- Full logical suite:
  **562 tests passed, 0 failed, 0 skipped**; parameterization produced
  **638 device executions**, all passing.
  `/tmp/bodyflow-task20-units-final-viewport.xcresult`
- All five Prompt 13 UI classes:
  **61 tests passed, 0 failed, 0 skipped** on iPhone 17 Pro with iOS 26.5.
  `/tmp/bodyflow-task20-ui-final-viewport.xcresult`
- Debug build on iPhone 17 Pro: `** BUILD SUCCEEDED **`.
- Release build on iPhone 17 Pro: `** BUILD SUCCEEDED **`.
- `git diff --check`: passed.

## Evidence and visual inspection

The final result bundle exported exactly 13 PNG files and 13 corresponding TXT
accessibility hierarchies to
`/tmp/bodyflow-task20-final-evidence.HGwRMz`. The approved stems are:

1. `01-today`
2. `02-meal-proposal-edit`
3. `03-individual-meal-log-detail`
4. `04-workout-proposal`
5. `05-hydration-routine`
6. `06-plan`
7. `07-progress-block`
8. `08-main-history`
9. `09-offline-error-retry`
10. `10-dark-mode`
11. `11-accessibility-xxxl`
12. `12-reduce-motion`
13. `13-final-simulator`

All PNGs were inspected. Dark Mode is visibly dark and is backed by the
effective-trait assertion. In Accessibility XXXL, `today.next-action` is fully
visible and usable between both chrome boundaries. The final simulator image
returns to Light/Large and the five independent tab stacks remain usable after
deep navigation.

## Limits retained

- No official nutrition or progress calculation was added to iOS; telemetry
  only copies an already received calculation version.
- No live BFF/Supabase endpoint, secret, persistence claim, migration,
  deployment, merge, TestFlight or production change was introduced.
- Debug fixtures, previews, receipt demonstrations, scenario flags and the
  effective-color-scheme test probe are excluded from Release. Release retains
  `operationUnavailable` and cannot report a mock registration as persisted.
- Main History remains one bounded first page containing only individual meal
  log rows and workouts. No cursor derivation, load-more behavior, detail
  endpoint, row grouping or local official-value correction was added.
- No WhatsApp-based architecture was introduced.

## Review closure

- Specification review approved the final implementation after the effective
  Dark Mode correction; no P0-P3 finding remained.
- An independent final quality review also approved the staged implementation
  with no P0-P3 finding. It noted only that Task 21 must normalize XCTest's
  exported `_0_<UUID>` suffix when copying attachments to their exact final
  evidence names.
- The final visual pass corrected the AXXXL viewport proof and re-ran the
  complete logical/UI/build gate afterward.

# Performe AI final product polish and brand — documentary evidence

Date: 2026-09-19. Operation:
`PREPARE_PERFORME_AI_FINAL_BRAND_AND_PRODUCT_POLISH_V1`.

## Scope and method

This evidence records a documentation-only transition from the verified local
Slice 10 baseline into the final product-polish and brand-approval workstream.
It did not alter Swift, asset catalogs, image bytes, tests, backend state,
staging, TestFlight or Production.

The analysis used the existing Slice 10 local visual attachments and their
manifest. No capture was copied into the repository and no new product claim is
derived from a marketing mockup.

## Revalidated entry baseline

- Repository: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch: `codex/performe-ai-client-beta-flow-v1`.
- HEAD: `0e6f530f6bff5c2be5388523d020390a44d17e8d`.
- Tree: `5766028c85875e698aea545397b017838b732a6d`.
- Host: `MacBook-Air-de-Eduardo.local`, Darwin arm64, classified
  `LOCAL_DEVELOPMENT` for this operation.
- Entry worktree: clean; index empty.
- Scoped build/source writer observed at entry: none.

The local source tree is not evidence of a Production deployment.

## Verified input state

| Input | Status carried into this operation |
| --- | --- |
| Slices 0, 2–10 | VERIFIED LOCAL |
| Slice 1 final brand bytes | PARTIAL / PENDING_EXTERNAL_ASSETS |
| Unit regression | 1,206 distinct tests / 1,421 executions passed |
| UI regression | 151 / 151 passed |
| Signed Release, strict codesign, native analyze | PASSED LOCAL |
| Production | NOT DEPLOYED |
| Remote staging integration | NOT REVALIDATED |
| Manual VoiceOver focus/rotor narration | NOT FULLY VERIFIED |

These are input facts from the committed Slice 10 evidence. This documentary
operation did not rerun product tests and does not upgrade any status.

## Eight-screen evidence ledger

Private source root:
`/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/slice10.bqfdGN`.

| Surface | Existing evidence used | Documentary conclusion |
| --- | --- | --- |
| Splash | `release-smoke.png` plus signed Release evidence | Stable direct Splash capture absent by design; final composition blocked by brand bytes |
| Welcome | `s10-visual-attachments/B68C671F-2094-4183-9125-279EB933D8EA.png` | Truthful flow verified; regular-size final-brand composition still required |
| Today | `s10-visual-attachments/E2FBB387-4381-444C-8366-04E01370501B.png` | Rebalance day context, utility actions and metric density without changing data meaning |
| Flow | `s10-visual-attachments/AF679FCB-EA8C-4184-A64F-12778F88A37C.png` | QA response proves layout, not Roberto-ready connected content |
| Register | `s10-visual-attachments/D330B335-34CA-43F4-BD41-F1C7F8EB46FC.png` | Preserve local-sample truth; simplify repeated provenance and CTA hierarchy |
| Plan | `s10-visual-attachments/1E12D97D-9C10-4AA0-84C3-D4DF61BB8DE2.png` | Improve scanability; never invent or silently translate received content |
| Progress | `s10-visual-attachments/7B48273D-61BD-4A31-AC84-7ACE7E46F08C.png` | Reduce ledger feel without adding fake history, charts or predictions |
| Profile / Library | `s10-visual-attachments/1D73B96D-6BCE-448B-A9B4-A2ED8749F1F5.png`; `729B1B9F-E97E-40BA-B9A9-239D736B43BC.png` | Condense identity/filter chrome and replace QA content before evaluation |

## Decisions recorded

- Direction remains **B2 — Warm Performance**.
- The final showcase is fixed to eight surfaces and a two-row journey.
- Work is classified as `MUST_FIX_BEFORE_ROBERTO`,
  `POLISH_BEFORE_ROBERTO`, `CAN_FOLLOW_AFTER_FIRST_FEEDBACK` or
  `BLOCKED_BY_BRAND_ASSET`.
- No new feature, capability, backend field, dataset, score, chart, prediction,
  media integration, billing flow or account action is introduced.
- Server-owned values and legal/product content remain authoritative.
- Brand integration requires exact-file approval; direction approval is not byte
  approval.

## Brand package state

- Required deliverables enumerated: 22.
- Conditional deliverables enumerated: 1 tinted AppIcon candidate.
- `approvalStatus`: `pending`.
- `approvedFiles`: empty.
- `publicCallsites`: empty.
- Approved hashes: none.
- Final asset bytes added by this operation: none.
- Existing optional runtime resource names documented: seven.

The package deliberately records no fictitious author, license, timestamp,
approval reference or checksum.

## Documentary outputs

- `docs/superpowers/specs/2026-09-19-performe-ai-final-product-polish-and-brand.md`
- `docs/superpowers/evidence/2026-09-19-performe-ai-final-product-polish-and-brand.md`
- `assets/brand/performe-ai-public-v1/review.md`
- `assets/brand/performe-ai-public-v1/manifest.json`

The execution sequence is P1–P8. It stops at specification readiness: there is
no staging E2E, external send, TestFlight, push, PR, merge or deployment in this
operation.

## RC1 local integration checkpoint — STOP_DOCUMENTED

The later RC1 approval record authorizes the 38 listed files and the default/
dark AppIcon roles; the tinted AppIcon remains unapproved and absent from the
runtime catalog. The approved source and catalog bytes were imported without
reconstruction, and the repository manifest records their exact SHA-256 values,
origin, approval and real callsites. Historical `pending` delivery documents
remain preserved under `delivery/rc1/` as pre-approval evidence.

Local gates completed before the stop:

- manifest/catalog checksum verification: 38 approved source files and 8
  runtime mappings passed; tinted runtime mappings: 0;
- focused brand resources and accessibility: PASS, including 4/4 final
  decorative-symbol checks;
- complete `BodyFlowTests`: 1,207/1,207 passed, 0 failed, 0 skipped;
- complete `BodyFlowUITests`: 148/151 passed, 3 failed, 0 skipped;
- isolated follow-up: Flow 50-message history passed; the two Today stale-retry
  tests failed again on their transient-state assertion.

The two persistent failures are
`Prompt13TodayUITests.testStaleErrorPreservesSnapshotAndReachableRetry` and
`Prompt13TodayUITests.testTodayOfflineContentShowsStaleBannerAndRetry`. Both
expect the retry control to disappear while the synthetic repeated read is in
flight. The unchanged fixture delays that read for 1.5 seconds, while current
XCUITest synchronization returns from the tap close to the terminal-state
publication; the first nonexistence poll therefore observes the retry control
already restored. The relevant Today production, fixture and test sources are
byte-identical to the authorized starting HEAD.

Correcting or stabilizing that gate requires a narrowly authorized change to
`DemoBodyFlowRepository.swift` or `Prompt13TodayUITests.swift`, neither of which
is in this operation's allowlist. Per the integration authority, execution stops
without a commit, signed Release, analyze, compiled scanner or final visual
acceptance. The imported work and result bundles are preserved for continuation;
no push, PR, merge, deploy, remote service or paid environment was used.

Checkpoint status: **STOP_DOCUMENTED**. RC1 integration is implemented but not
promoted to `VERIFIED LOCAL`; regression status is **NOT VERIFIED** until the
out-of-allowlist test gate is resolved and the remaining mandatory gates pass.

## RC1 retry-fixture amendment — STOP_DOCUMENTED

The later amendment authorized only deterministic retry-fixture/model coverage
and stable post-action UI assertions. The implementation stayed within that
scope: `TodayViewModelTests.swift` now proves that a controlled retry exposes
the prior snapshot while the read is pending, and
`Prompt13TodayUITests.swift` now asserts the stable stale result after the
retry completes. `TodayViewModel.swift`, `DemoBodyFlowRepository.swift` and
all production/backend behavior remain unchanged.

The two exact Today retry cases passed serially three times each, and the
neighbor suite passed 44/44. The complete unit gate passed 1,208/1,208. The
single complete UI gate still failed 1/151: the pre-existing
`PremiumPerformanceUITests.testFlowFiftyMessageHistoryRenderBaseline` at line
121 (`XCTAssertTrue failed`). This is the same transient Flow history gate that
passed on isolated execution; no retry or timing relaxation was applied to the
full-suite result.

Per the amendment authority, any failed mandatory gate means no commit and no
continuation into Release, analyze, scanner or visual acceptance. Result bundle
`final-source-full-ui-post-fix.xcresult` is preserved. Checkpoint remains
**STOP_DOCUMENTED**; RC1 is not `VERIFIED LOCAL`.

## RC1 resumption 2026-09-21 — gates resolved, VERIFIED LOCAL

Execution resumed on the authorized host (`MacBook-Air-de-Eduardo.local`) from
the same baseline (HEAD `0e797ed`, parent `0e6f530`, tree `db626bf`, empty
index, intentionally dirty worktree). The RC1 checksum gate re-passed (38/38
approved source files, default/dark AppIcon runtime bytes byte-identical to the
approval record; tinted absent).

Root cause of the residual full-suite failure was empirically confirmed and
resolved within the test allowlist:

- `PremiumPerformanceUITests.appendFiveLocalExchanges` asserted the transient
  `flow.responding` indicator, which is rendered at the tail of the eager Flow
  history `ScrollView` behind the raised keyboard after `send.tap()`. Under
  full-suite XCUITest synchronization that element is not vended to the
  accessibility tree in time, so the hard assertion failed only in the complete
  suite. The correction observes the always-visible composer `flow.cancel`
  control (same `isSending` gate) and asserts `pendingObserved || reply`,
  preserving the functional guarantee (a cancellable pending state or a visible
  reply, plus composer reset) without relaxing dataset, iterations or timeouts.

Verified gates this session (all executions counted):

- `PremiumPerformanceUITests` class, 3× serial: 4/4 each;
- complete `BodyFlowUITests`: 151/151 passed, 0 failed (the previously failing
  history-render baseline passes inside the full suite);
- complete `BodyFlowTests`: 1,208/1,208 passed, 0 failed;
- signed Release (simulator, normal signing, never `CODE_SIGNING_ALLOWED=NO`):
  **BUILD SUCCEEDED**, identifier `com.bodyflow.app`;
- `codesign --verify --deep --strict`: valid, satisfies Designated Requirement;
- native `analyze`: **ANALYZE SUCCEEDED**, 0 analyzer findings;
- compiled-app scanner against baseline `7ab3e657`: **PASS**, PUBLIC_LEAK 0,
  DEBUG_ONLY 0, brand gate `APPROVED_FOR_LISTED_RC1_FILES`;
- scanner unit suite: 21/21;
- visual review: login/welcome and brand symbol/wordmark render as Performe AI;
  the AppIcon renders in both light (default) and dark appearance.

Scanner allowlist amendment: the compiled scanner initially failed
`MISSING_COMPILED_NAMED_ASSET: AppIcon` because the approved integration made
`PerformeAIAppIconV1` the designated app icon while the legacy `AppIcon`
appiconset remains a historical catalog asset that actool no longer emits. With
explicit user authorization, `scripts/uiux/premium-surface-scan.mjs` (and its
test) were adjusted to tolerate a non-designated source appiconset absent from
the compiled catalog while still requiring the designated primary icon to
compile. No historical asset bytes were deleted; no product code changed.

Not verified / out of scope this session: manual VoiceOver focus/rotor
narration (NOT EXECUTED — no PASS asserted); tinted AppIcon (`PENDING — NOT
INTEGRATED`); remote/staging integration (`NOT REVALIDATED`); Production (`NOT
DEPLOYED`).

Checkpoint status: **VERIFIED LOCAL** for the listed RC1 files and the default/
dark AppIcon roles. The single authorized integration commit is created on
parent `0e797ed`.

## P2–P6 final visual polish — 2026-09-21

Operation `COMPLETE_PERFORME_AI_FINAL_VISUAL_POLISH_P2_P6_LOCAL_V1`. Entry
baseline revalidated: commit `27d29151568af4ced22fd7e45247b31b98113684`
(subject `feat(brand): integrate approved Performe AI assets`), parent
`0e797edd881cf8931e1b37bddd39ea454c0a9f20`, tree
`1a1baa23279b6c8ef604c03738c5a78231e047ff`, clean worktree, empty index — all
confirmed exact, not assumed.

### Comparison checklist (implementation vs. 2026-09-19 spec §5)

| Screen | Spec criterion | Observed divergence | Path | Smallest fix |
| --- | --- | --- | --- | --- |
| 01 Splash | Symbol → wordmark → native loading indicator, sparse deep-teal canvas | None in `SplashView.swift` itself; the real launch frame is still not directly observable (launch is never delayed, confirmed empirically again this session) | `Features/Auth/SplashView.swift` | None (product unchanged); added a documentary native-render test to the existing rendering harness |
| 02 Welcome | Brand → step/progress → concise proposition → existing inputs | None — hierarchy already matches (`Etapa 1 de 7` → `Boas-vindas` → name/language/country/timezone → Continue) | `Features/Onboarding/WelcomeStepView.swift` | None |
| 03 Today | Day context → official energy → protein/hydration → pending → routine/recommendations → independent Flow/Library | Default (`.automatic`) large-title reservation left a ~180pt blank band between the brand strip and the pinned Flow/Library row, pushing the day-context/energy composition down and reproducing exactly the spec's "compete near the top" complaint | `Features/Today/TodayRootView.swift:267` | `.navigationBarTitleDisplayMode(.inline)` |
| 04 Flow | Navigation → role/guidance → history → composer | None — already uses `.inline` (pre-existing); empty and long-response states render calmly | `Features/FlowChat/FlowChatView.swift` | None |
| 05 Register | Choice → local-sample provenance → CTA hierarchy | Same blank large-title band as Today | `Features/Register/RegisterRootView.swift` | `.navigationBarTitleDisplayMode(.inline)` |
| 06 Plan | Received plan → nutrition → metadata | Same blank large-title band | `Features/Plan/PlanRootView.swift` | `.navigationBarTitleDisplayMode(.inline)` |
| 07 Progress | Current measurements → consistency → XP/level/blocks → achievements | Same blank large-title band; card grouping already matches the desired order | `Features/Progress/ProgressRootView.swift` | `.navigationBarTitleDisplayMode(.inline)` |
| 08 Profile / Library | Identity → Flow style → library/content → preferences | Same blank large-title band on Profile; Library's filter segment remains a comparatively large first-viewport element (pre-existing, spec-flagged `POLISH_BEFORE_ROBERTO`) | `Features/Profile/ProfileRootView.swift` | `.navigationBarTitleDisplayMode(.inline)` (Profile only). Library filter density left unchanged — no low-risk fix identified that would not touch tested filter-picker layout/frames |

Root cause of the shared Today/Register/Plan/Progress/Profile divergence: all
five tab root views set `.navigationTitle` without an explicit
`.navigationBarTitleDisplayMode`. Combined with each view's own
`.safeAreaInset(edge: .top)` (Today) or plain `ScrollView`, the default large
title reserved its layout height without rendering visible text at rest,
producing an empty band already visible (byte-for-byte, pre-dating this
session) in the Slice 10 evidence capture
`s10-visual-attachments/E2FBB387-4381-444C-8366-04E01370501B.png`. The fix was
verified empirically: incremental Debug builds before/after, screenshots
confirming the band's removal and the immediate visibility of
day-context/plan/progress/profile content, in both pt-BR/light and
en-US/dark. No copy, identifiers, routes, or accessibility labels changed —
`.navigationBarTitleDisplayMode` only affects layout, and
`app.navigationBars["Hoje"]` / `["Plano"]` etc. remain valid regardless of
display mode (verified against existing assertions in
`Prompt13AccessibilityUITests.swift`, `Prompt14AccessibilityUITests.swift`,
`PremiumContentProfileUITests.swift`).

### Files changed (all within the P2–P5 FILE MAP)

- `Features/Today/TodayRootView.swift` (+1 line)
- `Features/Register/RegisterRootView.swift` (+1 line)
- `Features/Plan/PlanRootView.swift` (+1 line)
- `Features/Progress/ProgressRootView.swift` (+1 line)
- `Features/Profile/ProfileRootView.swift` (+1 line)
- `BodyFlowTests/BodyFlowPremiumRenderingTests.swift` (+23 lines: one new
  documentary test, `testSplashNativeRenderForDocumentaryReview`, using the
  existing `PremiumRenderingTestSupport.nativeImage` harness; no new
  production code, no new test-support file)
- `BodyFlowUITests/BodyFlowUITestSupport.swift` (`assertMinimumTapTarget`:
  added a `0.01`pt floating-point tolerance; see regression section below)

No changes to Core, models, repositories, APIs, Release injection, scanner
guards, approved assets, or project configuration.

### P6 — eight-surface visual review

Captures use the local demo fixtures already in the app (`--ui-testing`
launch arguments), the iPhone 17 Pro / iOS 26.5 simulator, and the Debug
build compiled this session. All synthetic content remains visibly labeled
("QA local", "QA_REPLY_VISIBLE", "Nutrição Sintética Prompt 14", "Plano
sintético para demonstração", "Perfil de demonstração") — nothing was
stripped or hidden to make a capture look more finished.

| # | Surface | Config | Source/state |
| --- | --- | --- | --- |
| 01 | Splash | Native render (`ImageRenderer`/`UIHostingController` harness), pt-BR and en-US, light | Documentary render, not a launch capture — labeled explicitly |
| 02 | Welcome | pt-BR, light, regular | `--ui-testing-fresh-auth` → sign-up → confirm-development → onboarding step 1 of 7 |
| 03 | Today | pt-BR/light and en-US/dark, regular | `--ui-testing --ui-testing-prompt13-loaded` |
| 04 | Flow | pt-BR, light, regular | `--ui-testing --ui-testing-flow-response` (long deterministic reply; QA-marked) |
| 05 | Register | pt-BR, light, regular | `--ui-testing --ui-testing-prompt13-loaded` → tab.registrar |
| 06 | Plan | pt-BR, light, regular | `--ui-testing --ui-testing-prompt13-loaded` → tab.plano |
| 07 | Progress | pt-BR, light, regular | `--ui-testing --ui-testing-prompt13-loaded` → tab.progresso |
| 08a | Profile | pt-BR, light, regular | `--ui-testing --ui-testing-prompt13-loaded` → tab.perfil (gated/no persona selected) |
| 08b | Library | pt-BR, light, regular | `--ui-testing --ui-testing-prompt14-loaded` → today.library |

Full pt-BR/en × light/dark × regular/Accessibility-XXXL matrix for every
surface is not re-captured here: it already exists, verified, in the Slice 10
evidence bundle (`s10-visual-attachments/`) and in this session's own UI test
suite (`PremiumUIUXUITestSupport`-driven captures), and the only functional
change this session (`.navigationBarTitleDisplayMode`) is theme/locale/type-
size independent. Two additional spot checks (Today en-US/dark,
Welcome/Today interaction) confirmed the fix holds across theme and locale.

VoiceOver manual focus/rotor narration: **NOT EXECUTED** this session — no
PASS is asserted for it. Automated accessibility-hierarchy checks
(`Prompt13AccessibilityUITests`, `Prompt14AccessibilityUITests`) are covered
by the full `BodyFlowUITests` regression below, which is not a substitute for
manual VoiceOver.

### Regression after the P3 composition fix

- `BodyFlowTests` complete: **1,209/1,209** passed, 0 failed (1,208 existing +
  the new `testSplashNativeRenderForDocumentaryReview`).
- `BodyFlowUITests` complete, first run after the five
  `.navigationBarTitleDisplayMode(.inline)` additions: **145/151 passed, 6
  failed**. Characterization (each isolated in a small batch before any
  fix):
  - `testTodayStaleRetryControlHasMinimumTapTarget`,
    `testStaleErrorPreservesSnapshotAndReachableRetry`,
    `testTodayOfflineContentShowsStaleBannerAndRetry`,
    `testStaleHistoryRetryUsesMinimumTapTarget` — all four failed even in an
    isolated small batch (`XCTAssertGreaterThanOrEqual` on `element.frame.height`,
    e.g. `43.99999999999994 < 44.0`). Root cause: `state.retry`'s production
    frame carries a hard `.frame(minHeight: 44)` floor (unchanged), but
    `XCUIElement.frame` is reported after coordinate-space conversion through
    the accessibility tree; removing the blank large-title band shifted that
    conversion's floating-point rounding path enough to leave a ~6e-14pt
    remainder under 44.0 — an unmeasurable, non-functional artifact, not a
    real tap-target shrink. Fix: a `0.01`pt tolerance added to
    `BodyFlowUITestSupport.assertMinimumTapTarget` (the single shared helper
    all four tests call), which still fails any real shortfall. Verified
    GREEN: isolated (4/4), then 3 clean serial re-runs of the same 4-test
    batch (4/4 each time).
  - `testOnboardingWelcomeHasNoOverlapAtAccessibilityDynamicType` — a plain
    5-second navigation-timeout in `BodyFlowUITests.swift`, a file untouched
    this session (onboarding sign-up flow). Passed cleanly in isolation.
  - `testAXComposerAtLimitKeepsNativeControlsReachable` — crashed with
    `SIGTERM` in `FlowChatUITests.swift`, also untouched this session. Passed
    cleanly in isolation.
  Neither of the last two touches any file this session modified; both are
  full-suite-only environmental fragility, the same category already
  documented in the RC1 checkpoint above for the Flow history baseline.
- `BodyFlowUITests` complete, second run (after the tolerance fix):
  **150/151 passed, 1 failed** —
  `FlowChatUITests.testComposerCannotSubmitOverExisting4000Limit()` failed
  with `Failed to synthesize event: Timed out while synthesizing event.`
  after 30 minutes, typing 4,001 characters via `typeText`. This is a
  different test than any of the six above, in a file this session did not
  modify. It passed cleanly in isolation (1/1). No production or test code
  change was made for it: the operation forbids raising timeouts, adding
  sleeps, or retrying taps to force green, and the failure is squarely
  event-synthesis latency under full-suite simulator load, not a functional
  defect. This remains an open, pre-existing, full-suite-only environmental
  limitation of this test target — consistent with (not a regression
  introduced by) this session's changes.
- Signed Release (simulator, normal signing, `CODE_SIGNING_ALLOWED` never set
  to `NO`): **BUILD SUCCEEDED**, identifier `com.bodyflow.app`.
- `codesign --verify --deep --strict`: valid, satisfies Designated
  Requirement.
- Native `analyze`: **ANALYZE SUCCEEDED**, 0 new findings.
- Compiled-app scanner against baseline `7ab3e657` (guards unmodified this
  session): **PASS**, `APPROVED_FOR_LISTED_RC1_FILES`, PUBLIC_LEAK 0,
  DEBUG_ONLY 0, 18/18 historical assets IDENTICAL, 38/38 approved RC1 assets
  IDENTICAL.
- Asset preservation re-verified: no byte in `assets/brand/performe-ai-public-v1/`
  or the approved runtime catalog entries changed; tinted AppIcon remains
  absent from the runtime catalog.

### Technical review

Self-review of the diff (5 one-line `.navigationBarTitleDisplayMode(.inline)`
additions + 1 additive test method): **Critical 0 / Important 0**. This was
an independent read of the diff against the FILE MAP and the full regression
result, not a separate adversarial workflow.

### Limitations / not done this session

- Library filter density (spec-flagged `POLISH_BEFORE_ROBERTO`) left
  unchanged — no low-risk, presentation-only fix was identified that
  wouldn't touch tested filter/picker frames.
- Plan/Progress label-value row density (spec-flagged, minor) left
  unchanged — current grouping already separates sections reasonably; judged
  as not a concrete divergence worth a forced change.
- Interactive typing into the Flow composer via simulator input injection
  was unreliable in this session (tap-to-focus did not consistently work on
  that specific field); the Flow showcase capture uses the deterministic
  `--ui-testing-flow-response` scenario instead of a live-typed exchange.
  This is a tooling limitation of this session, not a product defect — the
  composer is exercised and asserted by `FlowChatUITests` and
  `PremiumPerformanceUITests` in the full UI regression above.
- P7 (connected staging QA) and P8 (Roberto evaluation-build preparation)
  are explicitly out of scope and were not started.

**USER VISUAL ACCEPTANCE: PENDING_REVIEW** — the human approval of the
eight-surface showcase remains with Eduardo; it is not recorded here.

Checkpoint status: **PERFORME_AI_FINAL_VISUAL_POLISH_READY_FOR_USER_REVIEW**.
RC1 (assets, checksums, AppIcon default/dark) preserved unregenerated. Tinted
AppIcon: `PENDING — NOT INTEGRATED`. Remote/staging integration: `NOT
REVALIDATED`. Production: `NOT DEPLOYED`.

## Responsive Today + native tab bar appearance — 2026-09-22 (uncommitted pilot)

Operation `FINISH_RESPONSIVE_TODAY_AND_NATIVE_TAB_APPEARANCE_V1`, continuing the
Today/Library fidelity pilots V1/V2 (not visually approved) in the same
worktree. HEAD unchanged at `f1e7200`; nothing staged or committed.

### Changes (presentation only — no model, repository, DTO, API, rule, auth,
session, asset or global token change; no accessibility identifier renamed)

- **Today header** (`TodayHeaderSection`): no eyebrow/tagline; date,
  protocol and freshness on one or two compact lines at regular sizes. At
  accessibility sizes the date stays visible and protocol + freshness move
  behind a native `DisclosureGroup` (`today.header.details`).
- **Summary block**: Energy keeps both official values side by side at
  regular sizes (`731 kcal · Exercício excluído` / `-83 kcal · Exercício
  incluído`), stacked at accessibility sizes; Protein and Hydration are
  paired tiles showing the received consumed value, with the unabridged
  fields behind "Mais detalhes". Disclosure titles use an explicit
  leading-aligned label (`TodayDisclosureLabel`) because the plain string
  title was centred when wrapping at AXXXL.
- **Shortcuts**: Flow + Library moved from a pinned band into the content
  right after the summary (one row at regular sizes; full-width stacked
  rows at accessibility sizes). They remain pinned at the top only when
  Today has no loaded presentation, so both stay reachable when Today fails.
- **Tab bar** (`AppShellView`, appearance only): per-stack
  `scrollEdgeEffectStyle(.hard, for: .bottom)` on iOS 26+ (no-op earlier).
  Routes, selection, stacks and ownership unchanged.

### Tab bar diagnosis (evidence, iOS 26.5 simulator)

1. `toolbarBackground(surface, for: .tabBar)` +
   `toolbarBackgroundVisibility(.visible, for: .tabBar)` on each tab's
   `NavigationStack` → no visible effect; red Library cover still tinted the
   Liquid Glass bar.
2. Same modifiers also on every pushed destination (scope experiment) →
   identical result. Conclusion: not a scope error; the iOS 26 glass tab bar
   ignores that API. Both modifiers were removed.
3. Public `scrollEdgeEffectStyle(.hard, for: .bottom)` → bar clean in light
   and dark at the position where it was red; the fixture cover is unchanged.
4. Control build without the modifier + live theme switch → bar red/dark
   (baseline).
5. **Residual:** after a *live* theme switch while on a pushed Library
   screen, the bar keeps the previous scheme's glass tint (brownish in
   light / light in dark) until the next navigation; after Back it renders
   correctly. Not fixed — no public API found to force a refresh without
   resetting view state.

### Captures (scratchpad `v3/`, iPhone 17 Pro iOS 26.5, 402×874 pt @3x, pt-BR)

`today-light-regular`, `today-dark-regular` (Large, `--ui-testing-prompt13-loaded`,
top of scroll, details collapsed); `today-axxxl-start`, `-scroll1`, `-scroll2`
(AccessibilityXXXL, light, 0 / ~450 / ~900 pt); `library-light-final`,
`library-dark-final` (`--ui-testing-prompt14-loaded`, Today → `today.library`,
initial scroll); `library-dark-live-switch`, `library-light-final-live-theme-switch`,
`today-dark-after-live-switch-back`; `tab-plano-dark`, `tab-progresso-dark`;
experiment captures `library-dark-scope-experiment`, `library-light-hard-edge`,
`control-no-modifier-live-switch`.

### Tests (Debug, same simulator)

- Unit (`AppTabTests`, `LibraryPresentationTests`, `TodayContractTests`,
  `TodayPresentationTests`, `TodayRecommendationsTests`, `TodayViewModelTests`):
  90 passed, 0 failed. A first combined run stalled after the unit cases
  (log stopped mid-line for >9 min) and was terminated; the isolated re-run
  completed normally. Cause not identified.
- UI: `PremiumCoreSurfaces` 8/8, `Prompt13Today` 11/11, `Prompt14Accessibility`
  11/11, `Prompt14Library` 11/11, `Prompt14TodayMascot` 9/9, `BodyFlowUITests`
  18/18, `FlowChat` 12/12, `PremiumContentProfile` 3/3, `PremiumPerformance` 4/4,
  `Prompt13Accessibility` 5/5, `Prompt13Registration` 21/21 (after update).
- Two tests updated because they encoded the old pinned band as a top
  viewport obstruction (the shortcut now scrolls with content, so its frame
  produced an invalid viewport): `Prompt13AccessibilityUITests`
  AXXXL test (obstruction list → navigation bar only, plus a new assertion
  that `today.library` is revealable, hittable and ≥ minimum target) and
  `Prompt13RegistrationUITests.testHydrationSuccessRefreshesTodayBeforeRoutineDetail`
  (obstruction list → navigation bar only; the order assertion is kept).
  No tolerance widened.
- Release build (signed ad hoc, `codesign --verify --deep --strict` valid),
  `xcodebuild analyze` succeeded; only a pre-existing warning in
  `SessionLifecycleCoordinator.swift:210`.

### Visual criteria

- Normal size: Energy + Protein + Hydration legible above the bar, no text
  truncation, no global font reduction — ATENDIDO (light and dark).
- AXXXL: header compacted, shortcuts reflow full width, no Dynamic Type cap
  or `minimumScaleFactor`, content scrolls and actions reachable (test) —
  ATENDIDO. Brand wordmark still large at AXXXL (not capped: an existing test
  requires brand height to grow with content size) — NÃO ATENDIDO as "brand
  not dominant"; left for review.
- Tab bar over saturated content on launch/navigation, light and dark, five
  tabs — ATENDIDO. Live theme switch on a pushed screen — NÃO ATENDIDO
  (residual above).

**USER VISUAL ACCEPTANCE: PENDING.** Status:
`PERFORME_AI_RESPONSIVE_VISUAL_PILOT_READY_FOR_REVIEW`; regression partially
verified (suites above); production `NOT DEPLOYED`.

## Brand at AXXXL + live theme switch — 2026-09-22 (uncommitted pilot, continued)

Operation `CLOSE_TODAY_BRAND_AX_AND_LIVE_THEME_GAPS_V1`. Baseline verified
before editing: HEAD `f1e7200`, index empty, the 12 dirty paths and full
SHA-256 hashes of the previous closeout unchanged; no writer active in this
worktree. Captures in scratchpad `v4/` (settings in `v4/settings.log`); `v3/`
kept untouched.

### Brand — compact shell presentation (resolved)

- `BodyFlowBrandIdentityView` gains an opt-in `presentation:` parameter
  (`.standard` default, `.compact`). Compact is identical at regular sizes;
  at accessibility sizes the product name uses the `.footnote` text role
  (still scaling) instead of `.headline`. Symbol asset, bytes and aspect
  unchanged; name exposed once as `brand.product-name` with header trait.
- Only `AppShellView`'s repeated tab-root header opts in. Launch
  (`AppRootView`), auth, welcome/onboarding and coach persona keep
  `.standard`. The shell header is one strip shared by the five tab roots,
  so the compact variant applies to all of them, not only Today.
- RED → GREEN: new `Prompt14AccessibilityUITests.testCompactShellBrandStaysSecondaryAtAccessibilityXXXL`
  (pt-BR and en): single hittable "Performe AI", inside the window, not
  overlapping and above the navigation bar, height ≤ 6.5% of the window
  (one standard body line at AXXXL ≈ 63pt = 7.2%), first Energy value
  starts in the initial viewport and is taller than the brand. RED on the
  previous code: 63.3pt > 56.8pt. GREEN after the change.
- The existing `testAuthenticatedBrandLayoutAcrossContentSizes`
  (Large → AXL → AXXL must grow) was **not** changed and still passes: the
  compact brand keeps scaling monotonically.

### Live theme switch with Library pushed — UNRESOLVED

Theme changed with `xcrun simctl ui <device> appearance light|dark` while
the app stayed on the same screen (no navigation, scroll or filter change).

| Exp. | Build | Screen | Result after live switch |
|---|---|---|---|
| A | final (stack-level `scrollEdgeEffectStyle(.hard, .bottom)`) | Today root | bar keeps previous-scheme glass; "Hoje" low contrast |
| B | control (modifier commented out) | Today root | bar updates correctly |
| C | edge effect only on Library feed ScrollView (stack-level off) | Library pushed | same stale bar as A |
| final C/D | final | Library pushed, light→dark and dark→light | stale bar both directions; content, filter "Todos", scroll and navigation preserved; selected-tab label loses contrast |

Hypotheses: (1) appearance applied in competing scopes — rejected by code
(no `preferredColorScheme`/`overrideUserInterfaceStyle`/Info.plist
override; tokens are trait-resolved dynamic `UIColor`s); (2) interaction
with the hard scroll-edge effect — confirmed by A vs B, and not specific to
pushed screens; (3) scope of the edge-effect modifier — rejected by C.
Result recorded for the tested runtime only (iOS 26.5 simulator, Xcode 27
SDK). No public, state-preserving fix was found within three hypotheses;
the forbidden workarounds (view identity reset, tab toggling, pop/push,
relaunch, forced scheme) were not used. The stack-level modifier is kept
because it fixes the saturated-content tint on every cold launch and
navigation; the live-switch residual is the trade-off, pending review.

Minimal reproduction: launch `--ui-testing-prompt14-loaded` in either
theme, tap `today.library`, run `simctl ui … appearance <other>`, wait 4s.

### Gates (final state)

- RED run: 1 test, 1 failure (expected). GREEN focused run: 3/3.
- Regression, single run: 77 tests, 0 failures (`BodyFlowUITests` 18,
  `PremiumAuthOnboarding` 3, `PremiumCoreSurfaces` 8, `Prompt13Accessibility` 5,
  `Prompt13Today` 11, `Prompt14Accessibility` 12, `Prompt14Library` 11,
  `Prompt14TodayMascot` 9). Unit: 90 passed, 0 failed.
- Release signed (ad hoc), `codesign --verify --deep --strict` valid,
  `analyze` succeeded; only the pre-existing warning in
  `SessionLifecycleCoordinator.swift:210`.
- Earlier >9-minute stall: cause still not identified. Pending composer and
  deep-navigation items from earlier rounds were not re-run and stay open.

**THEME_SWITCH_STATUS: UNRESOLVED.** Status:
`PERFORME_AI_PILOT_FINAL_GAPS_READY_FOR_REVIEW`. USER VISUAL ACCEPTANCE:
PENDING. Production: NOT DEPLOYED.

## Native theme adaptation restored — 2026-09-22 (uncommitted pilot, continued)

Operation `RESTORE_NATIVE_THEME_ADAPTATION_AND_CLOSE_VISUAL_PILOT_V1`.
Baseline verified before editing (HEAD `f1e7200`, index empty, 14 paths with
the full SHA-256 hashes of the previous closeout, no later writer). Captures
in scratchpad `v5/` (settings in `v5/settings.log`); `v3/` and `v4/`
(including the `.hard` experiment) kept.

### Change

Surgical edit in `App/AppShellView.swift`: removed the pilot-introduced
`.modifier(TabBarScrollEdgeEffect())` and its private helper (the only
`scrollEdgeEffectStyle` in the app; absent from HEAD). The `.compact` brand
callsite is untouched. The tab bar is back to the native appearance of HEAD.

### Theme switch (iOS 26.5 simulator, iPhone 17 Pro, Xcode 27 SDK)

Theme changed with `simctl ui … appearance` while the screen stayed put.

- Today root, light → dark → light: bar, labels and selected tab adapt — PASS.
- Library pushed (filter "Todos", scrolled 150pt so the red cover is under
  the bar), light → dark → light: bar and content adapt; before/after light
  captures identical; scroll, filter, stack and selected tab preserved — PASS.
- Cold launch dark on the same position renders the same values as the live
  switch.
- Native saturated-content tint: PRESENT (the glass samples the red/black
  cover; expected native behaviour, not "fixed").

### Legibility over the saturated cover

Measured on the rendered captures (luminance of the text extreme vs. the
local median background):

| State | Unselected labels | Selected "Hoje" label |
|---|---|---|
| Today root, light / dark | ~16.9:1 / ~13.2:1 | ~6.0:1 / ~7.0:1 |
| Library cover under bar, dark | ~14.6:1 | ~7.8:1 |
| Library cover under bar, light | ~15.9:1 | **~2.7:1** |

The selection stays understandable without colour (native highlight
capsule), but the selected label falls below 4.5:1 in light over saturated
content. This is native behaviour with HEAD's configuration (`.tint(accent)`
unchanged), not introduced by the pilot; recorded as an **open issue**. A
temporary XCTest contrast audit on that state (method removed after the run)
reported no tab-bar findings — only content text occluded by the bars — so
the automated audit does not catch this case.

### Accessibility audit regression found — compact brand (BLOCKING)

`PremiumConvergenceUITests.testRepresentativeLoadedTabsPassAutomatedAccessibilityAudit`
and `…StateFamiliesPassAutomatedAccessibilityAudit` fail with "Dynamic Type
font sizes are partially unsupported" on `brand.product-name`. Control: with
the callsite temporarily set to `.standard` both pass; restored to
`.compact` afterwards. Cause: the compact variant switches from `.headline`
to `.footnote` at accessibility sizes, so the name stops growing across that
step. Not fixed here — the operation forbids redoing `.compact` and does not
accept an accessibility regression; decision pending.

### Gates (final state, new this round)

- New test `Prompt14AccessibilityUITests.testLiveThemeSwitchPreservesShellStackAndLibraryState`
  (live switch reaches the app; Library, "Salvos" filter, selected tab and
  five actionable tabs preserved in both directions): pass.
- Focused run: 5/5. Regression, single run: 62 tests, 2 failures (the two
  audit tests above); `BodyFlowUITests` 18, `PremiumAuthOnboarding` 3,
  `PremiumCoreSurfaces` 8, `Prompt13Accessibility` 5, `Prompt14Accessibility`
  13, `Prompt14Library` 11 all green. Audit control run (`.standard`): 2/2.
- Unit: 90 passed. Release signed (ad hoc), `codesign --verify --deep
  --strict` valid, `analyze` succeeded (pre-existing warning only).
- Composer/deep-navigation items and the earlier >9-min stall remain open.

Status: `PERFORME_AI_VISUAL_PILOT_NATIVE_THEME_READY_FOR_REVIEW` with the
compact-brand audit regression blocking closure. USER VISUAL ACCEPTANCE:
PENDING. Production: NOT DEPLOYED.

## I1 — Pilot closeout and clean baseline — 2026-09-22 (Performe AI UI/UX plan V2)

Performe AI = public product; Flow = public agent; BodyFlow = preserved internal
technical identity (paths, targets, types, IDs) — not a public brand.

Operation: Plan V2 increment I1 (`stateful-knitting-ripple` plan, authority
amendment VERIFIED against `b4c09e8:docs/handoffs/2026-08-20-…`, specs
2026-08-11 / 2026-09-14 / 2026-09-17 / 2026-09-19, Signal Spark RC1 manifest).
Entry state verified before editing: HEAD `f1e72009…`, index empty, the 14
pilot files with the SHA-256 hashes of the previous closeout; `scrollEdgeEffect`
occurrences in the tree = 0 (the pilot's `.hard` edge effect had already been
removed surgically; `AppShellView.swift` diff = the single `.compact` callsite).

### Changes (presentation only; 3 files newly touched, 2 pilot files amended)

- `DesignSystem/BodyFlowTypography.swift`: `+brandCompact = .subheadline.weight(.bold)`
  (additive token; locked identities untouched).
- `DesignSystem/Components/ScreenStateView.swift` (approved public callsite,
  edited in place): compact presentation uses `brandCompact` at every size
  (no role switch per category); symbol `@ScaledMetric(relativeTo: .largeTitle)
  = 28`; removed the unused `View.bodyFlowBrandIdentity()`; `brand.product-name`,
  `Image(decorative:)` and `.isHeader` unchanged.
- `BodyFlowTests/BodyFlowPremiumRenderingTests.swift`: new
  `testBrandIdentityGrowsStrictlyAcrossDynamicTypeSizes` (both presentations,
  light/dark, 12 sizes, strictly increasing height).
- `BodyFlowTests/BodyFlowComponentPolicyTests.swift`: `brandCompact` identity.
- `BodyFlowUITests/Prompt14AccessibilityUITests.swift`: compact-brand threshold
  changed from `window.height × 0.065` to "< one body line at AXXXL" measured
  in the runner via `UIFont.preferredFont(forTextStyle: .body, compatibleWith:)`.

Decision attribution: `.subheadline.weight(.bold)` was the option the user
selected in this session (AskUserQuestion "Marca AXXXL"); it is a technical
design proposal confirmed by the gates below, not a visual acceptance.

### RED → GREEN

- RED (`v6-i1-red.xcresult`): compact brand rendered height was flat at
  **28.0 pt from xSmall through accessibility1** (light and dark), then
  32.3 / 39.7 / 45.7 / 52.7 — the same defect the XCTest audit reports as
  "Dynamic Type font sizes are partially unsupported".
- GREEN unit (`v6-i1-green-unit`): render test + 6 policy tests pass.
- GREEN UI focused (`v6-i1-green-ui`, single run): `PremiumConvergenceUITests`
  4/4 (both accessibility audits, **no allowlist change**),
  `Prompt14AccessibilityUITests` 13/13 (incl. brand growth Large→AXL→AXXL,
  compact-brand secondary at AXXXL pt/en, live theme switch),
  `PremiumCoreSurfacesUITests` 8/8, `PremiumAuthOnboardingUITests` 3/3 — 28/28.

### Native theme adaptation (I1 build, captures `v6/i1/`, iOS 26.5 simulator)

`simctl ui appearance` switched without navigation, scroll, relaunch or filter
change. Today root light→dark→light (`A0/A1/A2`) and Library pushed with the
saturated cover under the bar (`B0/B1/B2`): bar, labels and selection adapt in
both directions; stack, "Todos" filter, scroll position and content preserved;
`B0` and `B2` measure identically. Measured contrast (text vs local median):
Today root dark 7.0:1 / light 6.0:1 (selected "Hoje"), unselected 13–17:1;
Library over the cover: dark 7.8:1, light **2.7:1** (selected label; native
glass sampling — recorded open item, not introduced by the pilot). Native
tint: PRESENT and accepted per the V2 requirement (readability + state, not
"zero tint").

### Full gate (baseline)

- Unit, full `BodyFlowTests`, single invocation: **1,431 passed, 0 failed,
  0 skipped** (136 s). `v6-i1-unit-full.xcresult`.
- UI, all 17 classes, single invocation (`-parallel-testing-enabled NO`):
  **153 passed, 0 failed** in 58.6 min, no watchdog trip.
  BodyFlowUITests 18, FlowChat 12 (incl. the 4,001-character composer test),
  PremiumAuthOnboarding 3, PremiumContentProfile 3, PremiumConvergence 4,
  PremiumCoreSurfaces 8, PremiumPerformance 4, PremiumRegistration 3,
  Prompt13Accessibility 5, Prompt13PlanProgressHistory 12,
  Prompt13Registration 21, Prompt13Routine 12, Prompt13Today 11,
  Prompt14Accessibility 13, Prompt14Library 11, Prompt14Progress 4,
  Prompt14TodayMascot 9. FULL SUITE RESULT: PASS. ISOLATED CHARACTERIZATION:
  none needed. FINAL VERIFIED STATE: VERIFIED. `v6-i1-ui-full.xcresult`.
- Release signed (ad hoc), `codesign --verify --deep --strict` valid;
  `xcodebuild analyze` succeeded with no findings; only the pre-existing
  Release warning at `SessionLifecycleCoordinator.swift:210`.
- Scanner `premium-surface-scan.mjs --baseline 7ab3e657` on the Release app:
  **PASS** — `PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18` identical,
  `ALLOWED_TECHNICAL 213`; scanner unit tests 21/21.
- Performance baseline (`PremiumPerformanceUITests`, averages): launch 1.851 s;
  Library feed scroll 5.451 s / 81.0 MB peak; Flow 50-message history 6.000 s /
  79.2 MB; Flow long response 5.791 s / 81.3 MB.
- Identifier inventory HEAD→tree: 162 → 166 (only additions:
  `today.energy.details`, `today.header.details`, `today.hydration.details`,
  `today.protein.details`). Policy greps: `.shadow` 0, `.blur` 0, material 1,
  `glassEffect` 0, `minimumScaleFactor` 0, `scrollEdgeEffect` 0,
  `dynamicTypeSize(` only in `#Preview` blocks; assets diff empty.

### Captures (`v6/i1/settings.log`; iPhone 17 Pro, iOS 26.5, 402×874 pt @3x)

Today pt light/dark × Large/AXXXL + en Large; tab roots Registrar/Plano/
Progresso/Perfil at light AXXXL and dark Large (compact brand strip: 15 pt
bold at regular sizes, one line below a body line at AXXXL); Library light/dark
initial position; theme sequences A0–A2, B0–B2.

### Open items (unchanged, explicit)

Selected tab label ~2.7:1 over a saturated cover in light (native; accent is a
locked token); VoiceOver manual narration NOT EXECUTED; staging NOT
REVALIDATED; AppIcon tinted PENDING — NOT INTEGRATED.

Status: I1 gates satisfied. REGRESSION STATUS: VERIFIED (full unit + full UI,
single runs, 0 failures). PUBLIC BRAND STATUS: VERIFIED for this build
(scanner PASS, brand tests green, internals preserved). USER VISUAL
ACCEPTANCE: PENDING. Production: NOT DEPLOYED. **Baseline commit: AUTHORIZED
by the user on 2026-09-22 after all I1 gates** (17 files staged by explicit
path; this section is part of that commit; no push).

## I2A — Minimal primitives (motion, loading button, root tint, wash) — 2026-09-22

Performe AI = public product; Flow = public agent; BodyFlow = preserved internal
technical identity. Plan V2 increment I2A on baseline `2b7992b` (index empty at
entry; 27 dirty paths at exit, all listed in the commit).

### Changes (presentation only; no token value changed; no new token roles)

- `DesignSystem/BodyFlowMotion.swift`: locked `duration(reduceMotion:disclosure:)`
  kept byte-identical; added `Kind {content, disclosure, press}`,
  `animation(_:reduceMotion:) -> Animation?` (nil under Reduce Motion),
  `pressedScale = 0.98`, `stateTransition(reduceMotion:)`. Consumers:
  `FlowChatView.followEnd` (replaces the hard-coded `reduceMotion: false`
  easeOut; `FlowChatScrollPolicy` stays the decider) and `FeatureReadStateView`
  (state ↔ content cross-fade for Progress and content detail).
- `DesignSystem/BodyFlowOpacity.swift` (new): `tintWash = 0.10`,
  `pressed = 0.85`, `.bodyFlowWash(role)` (opaque `backgroundSecondary` under
  Increase Contrast; `borderSubtle` outline under Differentiate Without Color —
  first real consumer of `\.bodyFlowDifferentiateWithoutColor`). Consumers:
  Today completion message, recovery confirmation, auth error, onboarding
  error; cover placeholder uses the token; Library toggle outline →
  `borderSubtle`; legacy card stroke → token (same value).
- `Components/BodyFlowButtonStyle.swift`: `isLoading` (spinner tinted with the
  role foreground, `accessibilityHidden`; role colors kept while `.disabled`);
  `presentedBackgroundRole/presentedForegroundRole(isEnabled:isLoading:)`.
  Consumers: the six auth/onboarding submit buttons (hand-rolled
  `HStack{Spacer; ProgressView().tint(.white); Text; Spacer}` removed).
- `App/AppRootView.swift`: `.tint(BodyFlowColor.color(.brandPrimary))` at the
  root (the catalog `AccentColor` is a scanner-protected historical asset whose
  dark value is the achievement gold); explicit `tintColor` on the UIKit
  bridged registration controls (`HydrationRegistrationView`,
  `WorkoutRegistrationView` incl. `selectedSegmentTintColor` + `onPrimary`
  selected title, `WorkoutProposalView` per role).
- Literal hygiene: radius `12`/`16`/`BodyFlowSpacing.xs` → `BodyFlowRadius`
  tokens (Today, Library toggle, cover); `spacing: 2` → `xxs`; `minHeight: 44`
  → `minimumTapTarget`; dead `BodyFlowColor.dynamicColor` removed.
- Not done, by design: `BodyFlowElevation` untouched (no shadow); env keys not
  moved; `BodyFlowSymbol`/`BodyFlowHaptics`/icon-only button variant deferred
  to their first consumers.

### RED → GREEN

- RED (`v6-i2a-red.xcresult`): `testReviewedSubmitSpinnersNeverHardCodeAWhiteTint`
  → 6 files with `.tint(.white)`; `testReviewedTintWashesUseTheSharedOpacityToken`
  → 7 literal alphas (0.08 / 0.10 ×4 / 0.12 / 0.25).
- GREEN unit: policy tests `motionAndOpacityTokensCollapseUnderReduceMotion`,
  `loadingButtonsKeepRoleColorsWhileDisabled`; render matrix gains the
  `isLoading` variant for every role/size/theme/width (≥44 and
  `height + 1 >= textHeight + 24`), accessibility probe (one disabled button
  element), fixture panel 2 documents the dark spinner.

### Unit suite (full `BodyFlowTests`)

- Run #1, parallel clones (default): **INTERRUPTED** — 1 failure
  (`DemoBodyFlowReadTests/loadingReadCancellationStopsBeforeSnapshot`, 10 ms
  cancel race on a saturated clone) and a hang: the seven remaining
  `BodyFlowPremiumRenderingTests` cases never reported for 10 min (watchdog).
  ISOLATED CHARACTERIZATION: `DemoBodyFlowReadTests` 13/13 ×2; render class
  12/12 (matrix 18 s). The hang under parallel clones is the same family as
  the earlier unexplained >9 min stall.
- Run #2, `-parallel-testing-enabled NO` (contingency pre-authorized in the
  plan; no timeout/retry/skip/assertion change): **1,214 tests, 1,214 passed,
  0 failed, 0 skipped** (I1 baseline: 1,210; +4 new tests). FINAL VERIFIED
  STATE (unit): VERIFIED.

### UI focused subset (8 classes: BodyFlowUITests, PremiumCoreSurfaces,
PremiumConvergence, PremiumAuthOnboarding, PremiumRegistration, FlowChat,
Prompt14Progress, PremiumContentProfile), each a single invocation

- Run #1: 55 tests, **1 failure** — `testFiveTabsAreReachableAndCaptured`
  (`tab.registrar` not `isSelected` within 3 s after the tap; 7 other classes
  green). Isolated: 2/2 (44 s, same as I1).
- Run #2: runner **"Restarting after unexpected exit"** during
  `testTodayNavigationPersistsAcrossTabSwitch`; simulator log shows
  `launchd_sim` "during system shutdown" at 16:52:27 — the simulator OS was
  shut down mid-run (no BodyFlow crash report; no concurrent xcodebuild;
  trigger not identified). Class not counted (37/37 for the other classes).
  Isolated: 2/2 (16 s).
- Run #3: runner restart while the default interruption handler dismissed the
  system pasteboard alert "“Performe AI” quer colar de “BodyFlowUITests-Runner”"
  (pre-existing behaviour of the sign-up test; handled fine in I1). Stopped by
  me after the restart.
- Host at that time: load avg 17.9, 15 GB / 16 GB used, 177 MB free, 6 GB
  compressed, heavy swap (other sessions' processes; no stray clones).
- Run #4 after a device shutdown/boot: **55 tests, 0 failures, 0 restarts**
  (28.7 min). FULL SUBSET RESULT: PASS (run #4). ISOLATED CHARACTERIZATION:
  runs #1–#3 above. FINAL VERIFIED STATE (I2A gate): VERIFIED on run #4;
  the three prior runs are recorded, not summed.

### Other gates

- Release signed (ad hoc), `codesign --verify --deep --strict` valid; `analyze`
  succeeded, no findings; only the pre-existing `SessionLifecycleCoordinator.swift:210`
  warning. Scanner PASS: `PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18/18`,
  `ALLOWED_TECHNICAL 218`.
- Identifier inventory 166 → 166 (no change). Policy greps: `.shadow` 0,
  `.blur` 0, material 1, `glassEffect` 0, `minimumScaleFactor` 0,
  `scrollEdgeEffect` 0, `.tint(.white)` 0. Assets diff: none.

### Captures (`v6/i2a/settings.log`)

Sign-in light/dark (`--ui-testing-fresh-auth`, primary button on brand teal /
mint); Today "Dados insuficientes" light/dark (wash); Registrar root dark;
treino sheet dark (segmented control brand-tinted, `onPrimary` selected title);
hidratação sheet dark (quick amounts + submit in brand mint); Library dark
(toggle outline `borderSubtle`, radius 8). The loading spinner state is
documented by the render-matrix attachments (`s0-components-dark-…-panel2`).

Status: I2A gates satisfied. REGRESSION STATUS: VERIFIED for the I2A gate
(full unit serial 0 fail; subset run #4 0 fail); full 17-class UI not re-run
in this increment (planned for I7). USER VISUAL ACCEPTANCE: PENDING.
Production: NOT DEPLOYED. Commit: AWAITING EXPLICIT AUTHORIZATION.

## I2B — Shared components with consumers in the lot — 2026-09-22/23

Performe AI = public product; Flow = public agent; BodyFlow = preserved internal
technical identity. Plan V2 increment I2B on `daddcd52` (I2A commit; index empty
at entry). 23 dirty paths at exit (18 modified + 5 new); hashes in
`v6/i2b/hashes.txt`.

### Components (each with its consumers in this increment)

- `DesignSystem/Components/BodyFlowListStyle.swift`: `.bodyFlowList()`
  (insetGrouped + hidden system background + `backgroundPrimary`) and
  `.bodyFlowListRow()` (`backgroundSecondary`). Consumers: `RoutineListView`,
  `RoutineHistoryView`, the two `WelcomeStepView` pickers,
  `MealProposalEditorView` (Form), `ProfileRootView`, `CoachPersonaPickerView`.
  Finding confirmed: the previous `.listRowBackground` on the `List` itself was
  a no-op (rows rendered on the system white/dark cells); it now applies per
  section/row, so Profile and persona rows sit on the brand surface.
- `BodyFlowScreenChrome.swift`: `.bodyFlowScreenChrome(title:)` = inline
  native bar, no `toolbarBackground`. Consumers: `Block7700DetailView`,
  `PlanDetailView`, `RoutineListView`, `RoutineHistoryView`, `MainHistoryView`
  (the five pushed screens that still fell back to a large-title band).
- `BodyFlowBrandHeader.swift`: shared brand band (compact/leading for the
  shell, standard/centred for the persona sheet). Consumers: `AppShellView`,
  `CoachPersonaPickerView`. `BodyFlowBrandIdentityView` stays in
  `ScreenStateView.swift` (approved public callsite).
- `BodyFlowRowButtonStyle.swift`: `.bodyFlowRow` press feedback (opacity
  `BodyFlowOpacity.pressed`, scale `BodyFlowMotion.pressedScale`, press
  animation; Reduce Motion keeps the dim and drops the scale). Consumers:
  `PlanRootView` (`plan.detail`), `ProgressRootView` (`progress.block.detail`),
  `MainHistoryView` (meal/workout rows), `TodayRootView` (`today.history`,
  `today.next-action`). `.plain` stays only on `today.refresh` (audit allowlist).
- `Features/Shared/FeatureStaleRecovery.swift`: `FeatureStaleRecovery(retry:)`
  (banner + `FeatureRetryButton`, secondary role, shared `state.retry`
  identifier, 44 pt) with a banner override for the Library focus target.
  Consumers: `TodayRootView`, `PlanRootView`, `MainHistoryView`,
  `LibraryRootView` (stale block + empty-feed `retryFirstPage`),
  `FeatureStateContentStack(retryAction:)` → `Block7700DetailView`,
  `FeatureReadStateView` (Progress and content detail now expose the stale
  retry; the stale block inside the stack is inset like the content instead of
  running edge to edge). History's retry label moves from `app.retry` to
  `state.retry` (identical pt-BR/en strings).
- Not done, by design: `BodyFlowDivider`, `BodyFlowStatusLine`,
  `BodyFlowSectionHeader` (first consumers in I3/I4); `BodyFlowElevation`
  untouched; no copy or asset change.

### RED → GREEN

- RED (`v6-i2b-red.xcresult`, contracts only, components already compiled):
  brand bands 4 offences (2 files); card links `.plain` Plan 1 / Progress 1 /
  History 2 / Today 3 and no `.bodyFlowRow`; lists 14 offences (6 files);
  chrome 10 offences (5 files); stale recovery 6 hand-rolled `state.retry`
  (Library 2) and 6 files without the shared block.
- GREEN focused (`v6-i2b-green.xcresult`): 17 XCTest + 67 Swift Testing,
  0 failures (render matrix with the `.bodyFlowRow` card variant; accessibility
  probe: one button element per row link at Large and AX5; policy test
  `rowPressFeedbackDropsScaleUnderReduceMotion`).
- Full `BodyFlowTests`, `-parallel-testing-enabled NO`, single invocation
  (`v6-i2b-unit-full-serial.xcresult`): **1,220 tests, 1,220 passed, 0 failed,
  0 skipped** (I2A: 1,214; +6). FINAL VERIFIED STATE (unit): VERIFIED.

### UI suite — FULL SUITE RESULT / ISOLATED CHARACTERIZATION / FINAL STATE

- Run #1, all 17 classes in one invocation (`v6-i2b-ui-full-run1.log`):
  **INTERRUPTED by the 100-min wall cap**. 14 classes passed, **133 test
  cases passed, 0 failed, 0 runner restarts**; not executed:
  `Prompt14LibraryUITests` (in progress, 4/11 passed), `Prompt14ProgressUITests`,
  `Prompt14TodayMascotUITests`. The first 13 classes ran at I1 speed; from
  ~19:25 the Library-heavy tests slowed by 10–50× (`testLiveThemeSwitch…`
  878 s, `testIncompleteDetail…` 719 s, `testInvalidCursor…` 1,247 s) and the
  last one hung on "App event loop idle notification not received". Host at
  20:32: 19 MB free, heavy swap (an 8 GB `com.apple.Virtualization` VM and
  Chrome helpers outside this session).
- Run #2, the three classes in one invocation (`v6-i2b-ui-run2.log`):
  INTERRUPTED by the 60-min cap; `testConflictReload…` **failed** ("Failed to
  tap library.card…: Timed out while synthesizing event", 666 s — the same
  test passed in 18 s in run #1), `testCoverFailures…` 3,202 s (85 s in run
  #1), `testIncompleteDetail…` 29 s.
- Run #3, after a simulator reboot, each class as its own invocation with a
  host monitor (`v6-i2b-ui-run3-*.log`, `…-monitor.log`): load averages
  49 → 111 → 20 during the run; the runner failed to initialise
  ("Timed out while loading Accessibility") for Progress, and Mascot/Library
  tests took 15–30 min each before the cap.
- Characterization: the same tests alternate between normal and pathological
  durations on the same build, the app idles at 0.0 % CPU on Today and 1.7 %
  on the loaded Library (no render loop), and every stall coincides with host
  load ≥ 20 / low free memory from processes outside this session. Recorded
  as ENVIRONMENTAL; no test, timeout, retry, sleep, skip or assertion was
  changed. The run #2 failure is not converted into a pass.
- Run #4 (2026-09-23, 09:16–09:27): a background waiter
  (`wait-calm-run-i2b.sh`) started the three classes only once the host had
  been calm for 3 consecutive minutes (1-min load 2.7–3.5, 31–35 % free),
  each class as its own single invocation after a simulator reboot
  (`v6-i2b-ui-run4-*.xcresult`): `Prompt14ProgressUITests` **4/4** (53 s),
  `Prompt14TodayMascotUITests` **9/9** (180 s), `Prompt14LibraryUITests`
  **11/11** (314 s) — I1-level durations, 0 failures, 0 restarts, no idle
  waits. The user chose this path (wait for a calm host) over accepting
  PARTIALLY VERIFIED.
- FINAL VERIFIED STATE (UI): all 17 classes green — 14 in run #1 (one
  invocation, 133 cases, 0 fail) and 3 in run #4 (three invocations, 24
  cases, 0 fail). Recorded as two clean result sets, not summed into one
  suite; the full 17-class single invocation remains the I7 closeout gate.

### Other gates

- Release ad hoc signed, `codesign --verify --deep --strict` valid; `analyze`
  succeeded (incremental: changed sources recompiled, 0 findings; the
  pre-existing `SessionLifecycleCoordinator.swift:210` warning did not re-emit
  because that file was not recompiled). Scanner PASS: `PUBLIC_LEAK 0`,
  `HISTORICAL_ASSET 18/18`, `ALLOWED_TECHNICAL 226` (+8 new `BodyFlow*` type
  names); scanner tests 21/21.
- Identifier inventory 166 → 166 (0 removed / 0 added). Policy greps:
  `.shadow` 0, `.blur` 0, material 1, `glassEffect` 0, `minimumScaleFactor` 0,
  `scrollEdgeEffect` 0, `.tint(.white)` 0, `.buttonStyle(.plain)` 25 → 19,
  `.listStyle(` 1 (the modifier), `BodyFlowBrandIdentityView(` 4. Assets
  diff: none.

### Captures (`v6/i2b/settings.log`)

Today stale light/dark (+ after `today.refresh`: shared banner + secondary
retry); History dark stale (inline chrome, shared block, row cards); Progress
dark; Block 7700 dark offline / dark loaded / light loaded (live switch);
Profile light (rows on the brand surface); persona sheet light (shared brand
header); Plan detail light (inline chrome); routine list light/dark and routine
history light/dark (brand-backed lists). Not captured this increment: History
light, Plan detail AXXXL (same components as the dark/light variants above).

### Discoveries (recorded, not fixed here)

- DESCOBERTA: routine list → detail (view-based `NavigationLink` in
  `RoutineListView`) → "Histórico" (`NavigationLink(value:)`) does not
  navigate (three taps, no push); the Today row path (`RoutineDetailRouteView`,
  value route — the path the UI tests cover) works. Pre-existing; I5 routine
  lot should push the list rows as `AppRoute.routine(... .detail)` values.
- DESCOBERTA: the persona sheet's "Cancelar" toolbar button is clipped inside
  the native glass capsule at Large ("ancela"); pre-existing, I5 profile lot.
- Progress root's stale state now shows a retry (was banner only).

Status: I2B gates satisfied. REGRESSION STATUS: VERIFIED for the I2B gate
(unit 1,220/0; UI 17/17 classes across run #1 + run #4, 0 fail; interrupted
runs #1–#3 preserved and characterized as environmental). USER VISUAL
ACCEPTANCE: PENDING. Production: NOT DEPLOYED. Commit: AWAITING EXPLICIT
AUTHORIZATION.

## I3 — Shell / Today / Flow — 2026-09-23 (STOP for visual acceptance)

Performe AI = public product; Flow = public agent; BodyFlow = preserved internal
technical identity. Plan V2 increment I3 on `add9588` (index empty at entry).
19 dirty paths at exit (15 modified + 4 new); hashes in `v6/i3/hashes.txt`.
No copy, asset, API, identifier-removal or capability change.

### Components born here (each with its consumers)

- `DesignSystem/BodyFlowSymbol.swift`: the glyph vocabulary (34 meanings →
  34 distinct SF Symbols) plus `Image(symbol:)`, `Label(_:symbol:)` (localized
  key) and `Label(verbatim:symbol:)` (resolved text). Consumers: all ten Today
  sources and `FlowChatView` — 0 raw symbol literals remain there (was 32).
  Error glyphs collapse to one (`exclamationmark.circle`), waiting to one
  (`clock`), chat to one (`bubble.left.and.text.bubble.right`).
- `Components/BodyFlowSectionHeader.swift`: section heading + optional
  trailing accessory (`ViewThatFits`: shares the row, stacks at accessibility
  sizes), `.isHeader`. Consumers: Energia, Rotina, Refeições confirmadas,
  Treinos confirmados, Conteúdos para hoje.
- `Components/BodyFlowStatusLine.swift`: one status message = vocabulary glyph
  + role color (info/success/warning/error/pending/empty/unavailable), read as
  one element. Consumers: Today completion message, routine collection
  empty/unavailable, block availability, meal provenance, recommendations
  offline/error/unavailable, Flow error and composer limit.
- `BodyFlowButtonStyle(isCompact:)`: hugs its content, same 44 pt floor and
  vertical padding. Consumer: the Flow composer send/cancel action (replaces
  the hand-rolled `.frame(width: 44)`).

### Today

Flow is now the primary shortcut (brand fill + `onPrimary`) and Library the
secondary (surface + brand text); both keep their identifiers, labels,
`ViewThatFits` and `accessibilityRepresentation`. Section headings carry the
domain glyph; card titles use `cardTitle`. Each routine collection is its own
card whose heading row carries "Ver lista" (link + chevron, 44 pt, new
`today.routine.header.<kind>` heading element); routine rows gained chevrons
and press feedback. Meal/workout rows put type and energy on one line via
`ViewThatFits`. Recommendations: card-shaped loading placeholder
(`accessibilityHidden`), `.secondary` retry, chevron on the library row, press
feedback on the cards. Disclosures (header/energy/protein/hydration) animate
through `BodyFlowMotion.animation(.disclosure,…)`; the state ↔ day swap
cross-fades.

### Flow

Compact preamble (role line semibold + guidance in `caption` + rule) instead of
two spaced paragraphs; the conversation gets its own empty state (brand glyph,
`screenTitle`, received detail) replacing the generic `ContentUnavailableView`;
role labels drop to `caption` semibold and bubbles gain breathing room
(`xl + lg` gutter at regular sizes); the composer action is the compact
icon-only button; loading ↔ history cross-fades. Scroll policy, limits,
idempotency, cancel/retry and the historical-reading behaviour untouched.

### RED → GREEN

- RED (`v6-i3-red-unit.xcresult`, `v6-i3-red-ui.xcresult`): symbol vocabulary
  32 raw literals across 11 files; shared headings/status/row links 12
  offences; UI `testTodayRoutineListLinksShareTheCollectionHeaderRow` failed on
  the 33.3 pt link target (`.bordered` label) before the heading row existed.
- GREEN: the same tests pass; full `BodyFlowTests` serial, single invocation:
  **1,229 tests, 1,229 passed, 0 failed, 0 skipped** (I2B: 1,220; +9).
- UI, 9 focused classes, one invocation each on the final build
  (`v6-i3-ui-run3-*`): Prompt13Today 11/11, Prompt13Accessibility 5/5,
  Prompt14TodayMascot 9/9, PremiumCoreSurfaces 9/9, Prompt14Accessibility
  13/13, FlowChat 12/12, PremiumConvergence 4/4, Prompt13Routine 12/12,
  Prompt13Registration 21/21 — **96 cases, 0 failures, 0 restarts**. (Runs #1
  and #2 on the pre-fix build were also green; run #1 was stopped by the user
  after 4 classes and resumed as run #2 — both preserved.)

### Two defects found by looking at the captures, not by the tests

- **PROBLEMA (regression I introduced, fixed):** `Label(_ title: String,
  symbol:)` swallowed string literals that were localization keys, so the Flow
  guidance line rendered the raw key `flow.guidance` (and would have hit
  `flow.message.processing` / `flow.message.failed`). The overload pair is now
  `Label(_ titleKey: LocalizedStringKey, symbol:)` (literals localize, like
  SwiftUI's own `Label`) and `Label(verbatim:symbol:)` (resolved text), with
  `testReviewedSourcesNeverPassALocalizationKeyAsVerbatimText` failing if a
  dotted key ever reaches the verbatim overload. Every UI test passed with the
  bug present — they assert by identifier, not by rendered text.
- **PROBLEMA (design, fixed):** `sectionTitle` and `cardTitle` resolve to the
  same font, so section headings tied with the card titles under them and the
  page read flat. `BodyFlowSectionHeader` now takes `screenTitle` (the same
  size Today's headings had before I3), locked by
  `sectionHeadingsOutrankCardTitles`.

### Other gates

- Release ad hoc signed, `codesign --verify --deep --strict` valid; analyze
  succeeded, no findings. Scanner PASS: `PUBLIC_LEAK 0`, `HISTORICAL_ASSET
  18/18`, `ALLOWED_TECHNICAL 234`; scanner tests 21/21.
- Identifier inventory 166 → 167: none removed (the only "delete" is a
  variable rename inside `routine.list.\(…)`, same runtime values), added
  `today.routine.header.supplement` / `.medication`.
- Policy greps: `.shadow` 0, `.blur` 0, material 1, `glassEffect` 0,
  `minimumScaleFactor` 0, `scrollEdgeEffect` 0, `.tint(.white)` 0,
  `.buttonStyle(.plain)` 19 → 16 (Today keeps only `today.refresh`).
  Assets diff: none. `Localizable.xcstrings` diff: none (the Flow empty-state
  keys already existed).

### Captures (`v6/i3/settings.log`, 13 files)

Today loaded pt light/dark, en light, pt light/dark AXXXL; Today scrolled
(routine cards with the "Ver lista" heading row, records) and the
attention/shortcuts block; Today unavailable (pinned shortcuts, Flow primary)
and incomplete (completion status line on the wash). Flow: empty pt light/dark
(preamble + own empty state), long response light (compact send), reader state
with "Última mensagem".

### Visual comparison against B2 — Warm Performance / Signal Spark

VISUAL FIDELITY (composition only): hierarchy — the day summary now descends
cleanly screen title → section heading → card title → metric → caption, and the
day's primary action (Flow) is the only filled element above the fold;
composition — routine collections read as cards with a heading row instead of a
wall of bordered buttons; density — type/energy pairs and the "Ver lista" links
fold onto single rows at regular sizes and stack at accessibility sizes; colour
— one brand fill per screen region, status colour only through the shared
status line, glyph always alongside; dark mode — same structure, mint primary
with near-black label; motion — disclosures and state swaps animate within the
locked 200/250 ms budget and collapse under Reduce Motion.
FEATURE FIDELITY (unchanged): section order, both official energy meanings and
their accessibility values, received values and provenance strings, routine
policies, Flow's contract (4,000 chars, idempotency, cancel/retry, historical
reading), every existing identifier.

Open items carried into the acceptance: the routine attention rows still show
the server's raw status values (`snoozed`, `pending`) — server-owned, not
translated here; the brand band dominates the first screen at AXXXL (locked by
the I1 threshold test, unchanged by I3).

Status: I3 gates satisfied. REGRESSION STATUS: VERIFIED for the I3 gate (unit
1,229/0; 9 focused UI classes 96/0 on the final build). PUBLIC BRAND STATUS:
scanner PASS, no new public copy. Production: NOT DEPLOYED.
USER VISUAL ACCEPTANCE: PENDING — I4 does not start and nothing is committed
until the user accepts these captures.

### I3 addendum — visual direction chosen by the user (2026-09-23)

The first I3 captures were refinement-level: the user looked at them and said
the app still read as the same UI, which was accurate — I1–I3 had been scoped
as "polish the pilot, do not redesign". PROBLEMA: the plan's conservatism was
not delivering a visible product change, and I had been reporting progress
without saying so plainly.

DESCOBERTA: the design system already carried unused visual range — the `hero`
surface (`heroBackground` / `onHero` / `heroSupporting`) and the `metricLarge`
type role had **zero consumers** anywhere in the app, while every screen was a
sequence of equal-weight `card` surfaces at `metricSmall`.

Three directions for the Today summary were built behind a DEBUG launch
argument (`--ui-testing-uiux-variant-N`, prototype file deleted afterwards),
captured light and dark on the simulator, and shown to the user:
1. **Hero** — the day's headline number on the hero surface at `metricLarge`;
2. **Panel** — one elevated card, four official numbers in a 2×2 grid;
3. **Editorial** — no card at all, large type on the page with hairlines.

DECISÃO (user, 2026-09-23): first **Direction 1 — Hero**, implemented and
captured; on seeing it in place the user switched to **Direction 2 — Panel**,
which is what ships.

Implemented for real as `TodaySummaryPanel` (in `TodayEnergySection.swift`):
one `elevated` card holds the four official figures — both energy balances at
`metricLarge`, protein and hydration at `metricSmall` — in a 2×2 grid that
stacks at accessibility sizes, with one "Mais detalhes" disclosure at the foot
of the panel. Inside it the remaining official rows keep their domain grouping
and their identifiers: `today.energy.details` on the disclosure,
`today.protein.details` and `today.hydration.details` on their groups. The
four cells keep `today.energy.remaining-food`, `today.energy.net-balance`,
`today.protein`, `today.hydration` with their spoken values
("731 quilocalorias; exercício excluído", "menos 83 quilocalorias; exercício
incluído", "2.111 ml; meta Indisponível"). `TodayProteinSection` and
`TodayHydrationSection` lose their card views (the panel owns that
presentation) and keep their descriptors; the orphaned `TodaySummaryFigure`
was removed. No new token, colour, shadow, asset or copy key.

The heading contract was updated with the composition: the day panel is the
summary and carries no section heading, so `BodyFlowSectionHeader` is now
required on Records, Recommendations and Routine only.

Gates after the change: full `BodyFlowTests` serial **1,229/1,229, 0 failed**;
UI classes touching Today, one invocation each — Prompt13Today 11/11,
Prompt13Accessibility 5/5, PremiumCoreSurfaces 9/9, Prompt14Accessibility
13/13, Prompt14TodayMascot 9/9, PremiumConvergence 4/4 (automated
accessibility audit), Prompt13Registration 21/21 (hydration value after a
registration) — **72 cases, 0 failures**. Identifier inventory 166 → 167,
none removed. Captures: `v6/i3/today-panel-{light,dark,axxxl,en-light,
incomplete}.png`, directions in `v6/variants/`, before/after in
`v6/compare/painel-antes-depois.png`.

Next, once accepted: carry the same principle (one hero figure per screen,
support values ranked below it) into Progress and Plan in I5, and re-run the
full focused set.

## I4 — Registrar / Plano — 2026-09-23 (STOP for visual acceptance)

Plan V2 increment I4 on `3f600d6` (I3 commit; index empty at entry). 9 dirty
paths at exit (8 modified + `BodyFlowHaptics.swift`). No copy key, asset, API
or identifier change.

### Registrar

The root asks one question and answers it with one action: the eyebrow that
repeated the tab name is gone, the question takes `screenTitle` with the
header trait, "Refeição" stays the primary button, the demonstration notice
becomes a `BodyFlowStatusLine(.info)`, and Treino/Peso/Hidratação move from
three separate cards into **one panel of three divided rows** with the domain
glyph, a chevron and press feedback — the same principle the user chose for
the day summary.

The meal sheet now leads with the real capture path: **Texto** as the primary
button, the local-sample notice under it, then Foto and Áudio as secondary
samples (labels "Foto — amostra local" / "Áudio — amostra local" unchanged).
`RegistrationOperationSummary` renders through `BodyFlowStatusLine` with the
role its state deserves (success / error / unavailable) and a secondary retry.

`BodyFlowHaptics` (new) plays result feedback only on the two terminal
outcomes of a submit the patient triggered — never on navigation, refresh or
arriving content — and never as the only channel: the status line always says
the same thing.

### Plano

Provenance rows (generated / valid until / version) keep every received value
but drop one step to `callout` under their existing "Detalhes do plano"
heading, so the plan's own fields lead. The root gained pull-to-refresh.

### Two regressions I introduced, found by the gates and fixed

- **PROBLEMA:** the automated accessibility audit failed on the Registrar tab
  — "Dynamic Type font sizes are partially unsupported" on the static text
  "Outros registros". Cause: `BodyFlowSectionHeader` wrapped even the
  accessory-less case in `ViewThatFits`, and the audit read the lone text as
  non-scalable. Fix: with no accessory the heading renders directly.
  This is the **same family as the I1 brand regression** — a layout wrapper
  making scalable text look unscalable to the audit. Second occurrence;
  worth an explicit check in every increment that touches a shared heading.
- **PROBLEMA:** `registration.mutation.retry` measured 42.57 pt (< 44).
  Cause: my `BodyFlowButtonStyle(role: .secondary)` sits exactly on the 44 pt
  floor, and the sheet's bottom edge clipped 1.4 pt; the previous `.bordered`
  button carried system padding on top of a 44 pt label and had slack. Fix:
  the label keeps its own `minimumTapTarget` floor inside the styled button.

Both failed, were fixed in the code, and pass again. No test, timeout, retry
or assertion was relaxed.

### Gates

Full `BodyFlowTests` serial, single invocation: **1,229/1,229, 0 failed**.
UI, one invocation per class, after the fix: PremiumRegistration 3/3,
Prompt13Registration 21/21, Prompt13Accessibility 5/5, PremiumConvergence 4/4
(automated audit), Prompt13PlanProgressHistory 12/12, PremiumCoreSurfaces 9/9,
Prompt13Today 11/11, Prompt14Accessibility 13/13 — **78 cases, 0 failures**.
(The first run of the set, before the fix, is preserved as
`v6-i3-ui-i4run1-*` with its 3 failures.)

Captures: `v6/i4/registrar-{light,dark}.png`, `sheet-refeicao-light.png`,
`plano-light.png`; before/after in `v6/compare/registrar-antes-depois-dark.png`
and `plano-antes-depois.png`.

Status: I4 code and test gates satisfied; Release/codesign/analyze/scanner not
yet run for this increment. USER VISUAL ACCEPTANCE: PENDING — nothing is
committed and I5 does not start until the user accepts.

### I4 closeout — user visual acceptance and final gates (2026-09-23)

USER VISUAL ACCEPTANCE — I4: **APPROVED** by the user for the composition
presented of Registrar, the meal sheet and Plano. The approval covers that
composition only; it is not approval of the Roberto/staging journey and not a
production-readiness statement. No further visual change was made in this
closeout.

Baseline revalidated before touching anything: branch
`codex/performe-ai-client-beta-flow-v1`, HEAD
`3f600d680efcb1a71e653e6c92c29d1ca6d1edbf` (the I3 commit), tree
`1089fa742414c771441eae9a05169e76936198e8`, empty index, 10 dirty paths all
belonging to I4 (8 sources + `BodyFlowHaptics.swift` + this evidence), no
stash entries, no concurrent build or test writer, no `index.lock`.

Final gates, run on the approved state:

- **Release build** (Simulator, normal signing, never `CODE_SIGNING_ALLOWED=NO`
  — 0 occurrences in the log): `** BUILD SUCCEEDED **`, identifier
  `com.bodyflow.app`, ad hoc signature.
- **codesign** `--verify --deep --strict`: valid on disk, satisfies its
  Designated Requirement.
- **analyze**: `** ANALYZE SUCCEEDED **`, no analyzer findings. The only
  warning in the log is the pre-existing
  `appintentsmetadataprocessor: Metadata extraction skipped, no
  AppIntents.framework dependency found` — pre-existing, not a new finding.
- **premium-surface-scan** on the compiled Release app, baseline `7ab3e657`:
  `status PASS`, `failures 0`, `PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18/18` all
  `IDENTICAL`, `ALLOWED_TECHNICAL 235`, `DEBUG_ONLY 0` (no Debug success path
  exposed in Release), brand asset approval gate
  `APPROVED_FOR_LISTED_RC1_FILES`. Observed counts unchanged from I3:
  `expectedNamedAssets 16` / `compiledNamedAssets 15`.
- **Scanner unit tests** (`node --test`): 21/21 pass.
- **Public brand gate** on the eight touched Swift files: every `BodyFlow*`
  match is an internal technical symbol (`BodyFlowSpacing`, `BodyFlowColor`,
  `BodyFlowSymbol`, `BodyFlowTypography`, `BodyFlowStatusLine`,
  `BodyFlowHaptics`, …); zero occurrences of `Body Flow`, `Better Ahead`,
  `MPP` or `Dr. Roberto`; zero new public string literals; no change to
  `Localizable.xcstrings`.
- **Asset preservation**: `git status` and `git diff` over `assets/` and
  `Assets.xcassets` are both empty — no RC1 or historical asset touched, no
  asset regenerated. The runtime `AppIcon.appiconset` is unchanged and still
  carries its default, dark and legacy tinted entries; the Performe AI tinted
  candidate (`exports/appicon-tinted-1024.png`) remains
  `PENDING_SUPPORT_AND_SEPARATE_APPROVAL` with `imported: false`.

HAPTICS ON PHYSICAL DEVICE: **NOT VERIFIED.** The result feedback added in I4
cannot be exercised by the Simulator. Implementation and the applicable tests
are green; nothing here claims device verification.

### PRE-ROBERTO FOLLOW-UP 1 — plan display values

The Plan surface currently shows the received values `strength` and
`macro_targets` verbatim. Before the connected beta these must be classified
as either (A) a known, stable API enum with an authorized display mapping, or
(B) opaque server-owned strings that must receive their display label from the
server. Nothing was translated, mapped, substituted or interpreted in this
operation.

PLAN DISPLAY LABEL STATUS: **PENDING CONTRACT CLASSIFICATION**

### PRE-ROBERTO FOLLOW-UP 2 — synthetic / demo content

Explicitly synthetic or demonstration strings are acceptable in the current
local QA and were left exactly as they are — among them "Plano sintético para
demonstração", "Payload opaco sintético", and the other clearly marked
fixtures and debug data. They are not the Roberto journey's final content, and
their markers were deliberately not hidden to improve screenshots.

ROBERTO JOURNEY FIXTURE STATUS: **PENDING PRE-BETA STAGING CLEANUP**

### I4 STATUS CORRECTION (additive note, 2026-09-23 — commit `e710dba1…` untouched)

The I4 closeout above reported `REGRESSION STATUS: VERIFIED` for the I4 gate.
Under the plan's global regression policy that label is reserved for a full
run of all 17 UI classes with 0 failures on the increment's final state, which
I4 did not execute (it ran the 8 focused classes). The corrected reading is:

- I4 implementation / visual gate: **COMPLETE / APPROVED**
- I4 focused UI: **78 / 78 PASS** (8 classes, one invocation each)
- I4 unit: **1,229 / 1,229 PASS**
- **REGRESSION STATUS: PARTIALLY VERIFIED** — the 17-class full UI suite was
  not run on the final I4 state.
- I4 PUBLIC BRAND GATE: **PASS** (scanner `PUBLIC_LEAK 0`, no new public
  literal, `Localizable.xcstrings` untouched)
- **PROJECT PUBLIC BRAND STATUS: PARTIALLY VERIFIED** — the I4 gate passed;
  the global VERIFIED remains reserved for the formal surface closeout (I7).

Nothing in I4 was re-run to change these labels; the commit, its parent and
its tree stand as recorded.

## I5 — Progresso / Perfil / Biblioteca / Rotina / Histórico / Mascote (2026-09-23, implementação — NÃO commitado)

Operação `EXECUTE_PERFORME_AI_UIUX_I5_V1` / `IMPLEMENTATION_I5_ONLY`. Performe AI = produto público; Flow = agente público; BodyFlow = identidade técnica interna preservada.

### Baseline revalidado (entrada)

```
branch codex/performe-ai-client-beta-flow-v1 · HEAD e710dba1eb7c59988c7d0dac1445d2ee909e14bf
parent 3f600d680efcb1a71e653e6c92c29d1ca6d1edbf · tree 3c488c518ff7beed9c1dbc9ff372ce922cf4d9d5
subject refactor(ui): refine Performe AI registration and plan composition
status 0 · index 0 · stash 0 · writers 0 · Xcode 27.0 (27A266a) · iPhone 17 Pro 27291590-… (Shutdown → booted nesta operação)
```

Hashes SHA-256 de entrada dos arquivos tocados: `$SP/v6/i5/entry-hashes.txt` (42 linhas).

### RED (caracterização no app HEAD e710dba, bundle de testes com os 2 testes novos)

| Teste | Resultado RED | Valor observado |
|---|---|---|
| `Prompt14LibraryUITests/testRegularFiltersShareOneRowWithTheCategoryControl` | FAIL (esperado) | `saved.maxX 386.0 > category.minX 16.01` — toggle `(201.3, 182.3, 184.7, 44)`, categoria `(16, 238.3, 370, 44)` → categoria ABAIXO do toggle |
| `Prompt14ProgressUITests/testProgressGroupsMeasurementsAndAchievementsPreservingIdentifiers` | FAIL (esperado) | `progress.body` inexistente (`waitForExistence` falhou na linha 75) |

Logs: `logs/v6-i5-ui-red-*.log/.xcresult`; resumo `v6/i5/red-characterization.txt`.
### Mudanças por superfície (I5, worktree dirty — não stageado)

**Vocabulário / DS (aditivo):** `BodyFlowSymbol` +21 casos (xp, level, streak, longestStreak, completedBlocks, deficit, medal, weight, bodyComposition, person, preferences, categoryFilter, picker, save, saved, unsave, article, selected, unselected, close, confirm); `BodyFlowListRowStyle(isEmphasized:)` + `.bodyFlowListRow(isEmphasized:)` (linha selecionada sobe para `surfaceElevated`). `Localizable.xcstrings` +5 chaves pt-BR/en: `progress.section.{measurements,consistency,summary,achievements,dates}`.

**Progresso** (`ProgressComponents`, `ProgressRootView`, `Block7700DetailView`): sem eyebrow; "Seu progresso" via `BodyFlowSectionHeader` (screenTitle); Card A `progress.body` = grupo `progress.measurements` (peso `scalemass`, gordura `figure`) + Divider + grupo `progress.consistency` (sequência `flame`, maior `trophy`), cada grupo com heading cardTitle + `.isHeader`; Card B `progress.summary` intacto (heading "Resumo"; XP `sparkles`, nível `rosette`, blocos `checkmark.seal`, déficit `arrow.down.circle`); Card C `progress.achievements` = heading "Conquistas" + (`progress.streak.restart` com botão `progress.streak.resume-today` em `BodyFlowButtonStyle(.primary)` mapeado da `ProgressActionAppearance`, sem `.tint`) + `progress.badges` (subtítulo "Medalhas conquistadas" em supporting; medalhas `medal.fill` em `achievement`) + `progress.missions.unavailable` como `BodyFlowStatusLine(.unavailable)`; `progress.dates` vira bloco de proveniência (`ProgressProvenanceRow`, supporting), sem card. Raiz: `.refreshable`, glifo do bloco pelo vocabulário. Bloco 7.700: título só na barra; banner+retry (`FeatureStaleRecovery`) dentro do scroll; `.refreshable`. Nenhum cálculo local; `ProgressPresentation`/seções oficiais intocados.

**Perfil / persona** (`ProfileRootView`, `CoachPersonaPickerView`): identidade em uma row com o glifo `person.crop.circle` inline no título (estrutura única em todos os tamanhos — a variante "coluna de ícone" tentada em `green4/green5` empurrou a row de persona para fora do alcance do tap em AXXXL e o ramo por categoria disparou a auditoria de Dynamic Type; ver run #1/#2) + "Dados de demonstração"; row "Estilo do Flow" com `.bodyFlowRow` e glifo `flow`; preferências com glifo do vocabulário. Picker: rows `.bodyFlowRow` com `selected`/`unselected` e `.bodyFlowListRow(isEmphasized:)` na selecionada (trait `.isSelected` mantido); retry `FeatureRetryButton` (secondary, id `state.retry` novo nesta tela); "Indisponível" com glifo do vocabulário; badge "Salvando…" opaco (`surfaceElevated` + contorno `borderSubtle` 1/2 pt conforme `accessibilityReduceTransparency`; literais vigiados mantidos; `.regularMaterial` removido); háptica success após save persistido (`savedSelections`). Cancel/Save intactos.

**Biblioteca** (`LibraryRootView`, `PublishedContentCard`, `ContentCoverView`): regular = Todos/Salvos + categoria na MESMA linha (HStack: toggle hugging + categoria flexível com rótulo quebrável; ViewThatFits descartado por medição — ver RED/GREEN); AX = empilhado como antes (`embedsFiltersInFeed` intacto); segmento selecionado preenchido `brandPrimary`/`onPrimary` + glifo `checkmark.circle.fill` + trait; categoria = 1 Button + 1 Label (+ chevron `chevron.up.chevron.down` decorativo), `.bodyFlowRow`, ≥44; cards `.bodyFlowRow`; status Salvo (`bookmark.fill` accent) / Concluído (`checkmark.circle` positivo) via `LibraryStatusLabel`; loading 1ª página = heading + spinner + 2 placeholders `accessibilityHidden`; load-more / retry-next-page / reload-first-page em `BodyFlowButtonStyle(.secondary)`, avisos de paginação em `BodyFlowStatusLine(.error/.warning)`; placeholder de capa `book.closed` pelo vocabulário. `ScrollView`/`LazyVStack`/paginação/cursor/cache/tracking/ordem de acessibilidade intocados. `toolbarBackground`: removido por ÚLTIMO (ver gate).

**Detalhe de conteúdo** (`PublishedContentDetailView`): Save `.secondary` / Complete `.primary` (labels/ids/ViewThatFits mantidos); resumo de mutação = `BodyFlowStatusLine` (kind mapeado do glifo do modelo — modelo intocado) + retry `.secondary` (id mantido); erro de "opened" como status line `.error`; ações bounded Voltar `.primary` / Biblioteca `.secondary`; metadados e status com o vocabulário; háptica success/failure pelo resultado da mutação.

**Rotina** (`RoutineListView`, `RoutineHistoryView`, `RoutineDetailView`, `RoutineActionSheet`, `RoutineSnoozeView`, `RoutinePresentation`): glifo de status compartilhado `BodyFlowSymbol.routineStatus(_:)` (taken ✓ / snoozed clock.badge / skipped forward.circle / pending clock) nas listas, histórico e detalhe (texto bruto `"taken"` do recibo continua); detalhe: chrome compartilhado, nome em screenTitle + `.isHeader`, "Ações" cardTitle, Tomado `.primary` / Adiar `.secondary` / Pular `.tertiary`, "Histórico" como row-card com chevron `.bodyFlowRow`; `RoutineActionSummary` = `BodyFlowStatusLine` (success/unavailable/error) + retry `.secondary`; action sheet com fundo da marca, drag indicator, submit `.primary` loading-aware, háptica success/failure; snooze: sem padding interno, presets em `ViewThatFits` (HStack de 3 `.secondary` → VStack), custom `.primary` loading-aware, wheel tintado; load-more do histórico `.secondary`.

**Histórico** (`MainHistoryView`, `HistoryMealLogRowView`, `HistoryMealLogDetailView`, `HistoryWorkoutDetailView`): cabeçalhos `BodyFlowSectionHeader` (meals `fork.knife`, workouts `figure.run`) combinados em um elemento com os ids `history.meals`/`history.workouts`; rows com chevron (`HistoryRowChevron`); `.refreshable`; detalhes = um único `BodyFlowCard` sobre o fundo da marca (título screenTitle + tipo + Divider + métricas; ids mantidos), chrome compartilhado.

**Mascote** (`MascotCardView`, `MascotDetailView`): card `.bodyFlowRow`, stale como `BodyFlowStatusLine(.warning)`, retry compacto `.secondary`, título do card em cardTitle; detalhe: `mascot.refresh` como botão compacto `.secondary` no topo do conteúdo (alinhado à direita) — a variante na toolbar (`green4`–`green6`) foi descartada porque o item de barra espelha o identificador no seu host view e os testes do mascote endereçam `mascot.refresh` por identificador (`descendants(.any)`), resolvendo em dois elementos; stale via `FeatureStaleRecovery`; chrome compartilhado. Artwork/animação/Reduce Motion intocados.

### Correção da linha de filtros da Biblioteca (medição → decisão)

O plano previa `ViewThatFits` para toggle + categoria na mesma linha. O primeiro GREEN (build `green1`) manteve a categoria abaixo do toggle (`saved.maxX 237.0 > category.minX 16.01`; toggle já hugging `(124.7, 182.3, 112.3, 44)`), porque `ViewThatFits` mede a largura *ideal* (texto sem quebra): toggle ≈ 206 pt + 12 + categoria ≈ 217 pt ("Todas as categorias" + glifo + chevron) = 435 pt > 370 pt disponíveis em Large — a primeira alternativa nunca cabe. Decisão: em tamanhos regulares a linha é um `HStack` fixo (toggle hugging + categoria flexível com rótulo quebrável, 2 linhas em Large); em tamanhos de acessibilidade continua a pilha existente (`embedsFiltersInFeed` intacto). GREEN no build `green2`: `testRegularFiltersShareOneRowWithTheCategoryControl` PASS (10,2 s). Ajuste tardio na mesma superfície (build `green4`): título "Horário personalizado" acima da roda de snooze com `labelsHidden()` + `accessibilityLabel` (o rótulo inline hifenizava caractere a caractere: "Ho-rá-rio per-so-nali-zado").

### Gate do `toolbarBackground` da Biblioteca (ÚLTIMA alteração da superfície)

Caracterização no build `green2` (override opaco presente): `v6/i5/toolbar-char-library-top-light.png`, `toolbar-char-library-scrolled-light.png`, `toolbar-char-library-scrolled-dark.png` (troca ao vivo). Remoção (`LibraryRootView.swift` −2 linhas; `toolbarBackground`/`scrollEdgeEffect` na árvore = 0) → build `green3` → gates obrigatórios, uma invocação cada:

| Teste | Resultado |
|---|---|
| `Prompt14AccessibilityUITests/testAccessibilityXXXLEvidence` | PASS (26,2 s) |
| `Prompt14AccessibilityUITests/testLiveThemeSwitchPreservesShellStackAndLibraryState` | PASS (20,5 s) |
| `Prompt14LibraryUITests/testLibraryAllCategoryAndOpaquePagination` | PASS (37,2 s) |

Reprodução manual sem navegação/relaunch (Biblioteca aberta, rolada ≈280 pt): light→dark (`library-live-theme-1-dark.png`), dark→light (`library-live-theme-2-light.png`), light→dark (`library-live-theme-3-dark.png`); estado (aba Hoje selecionada, stack, filtro "Todos", posição de scroll) preservado; comparativos `cmp-toolbar-opaque-vs-native-{light,dark}.png`. Observação: em tamanhos regulares a barra nativa cobre o bloco de filtros (fora do scroll, opaco em creme), então a remoção é visualmente neutra ali; o cenário "capa sob a barra" existe apenas em AX (filtros embutidos no feed), coberto por `testAccessibilityXXXLEvidence`. Nenhuma regressão de contraste, estado, stack, filtro ou acessibilidade → remoção mantida.

### Classificação por superfície (HARD VISUAL GATE)

| Superfície | VISUAL FIDELITY (B2 / Signal Spark) | FEATURE FIDELITY | Capturas |
|---|---|---|---|
| Progresso | **ATENDIDO** — título único, 3 cards agrupados (Medidas+Consistência / Resumo / Conquistas), datas como proveniência, glifos coerentes; antes/depois `cmp-progress-before-after-{light,dark}.png`; AXXXL `cmp-progress-axxxl-light-dark.png`; zero-streak `progress-streak-zero-light-{top,achievements}.png`; en `progress-en-light-large.png` | **PRESERVADA** — valores server-authoritative, nil≠zero ("Não disponível"), seções oficiais e IDs; Prompt14Progress/Prompt13PlanProgressHistory/PremiumCoreSurfaces (matriz de tema) | 10 |
| Perfil / persona | **ATENDIDO** (parcial na identidade: glifo inline, não coluna) — "Estilo do Flow" com glifo do Flow e feedback, opções com linha selecionada enfatizada, badge opaco; `profile-final-pt-light-large.png` (estado final), `profile-pt-light-large.png` (variante coluna de ícone, descartada), `persona-pt-light-large.png` (fixture sem opções), `persona-options-pt-light-large.png`, `persona-selected-pt-light-large.png`, `cmp-profile-before-after-light.png` | **PRESERVADA** — Focus/Impulse/Zen do contrato, save lifecycle, IDs, Cancelar/Salvar intactos | 5 |
| Biblioteca | **ATENDIDO** — filtros em uma linha (regular), segmento selecionado preenchido, cards com feedback, status com glifos, placeholders de loading, paginação em role; `library-pt-{light,dark}-large.png`, `library-en-light-large.png`, `library-pt-{light,dark}-axxxl.png`, `library-xctest-16-accessibility-xxxl.png`, `library-cover-under-bar-light.png`, live theme ×3, `cmp-library-before-after-{light,dark}.png` | **PRESERVADA** — ScrollView/LazyVStack/paginação/cursor/cache/tracking/ordem de acessibilidade/`Button+Label` da categoria; Prompt14Library + Prompt14Accessibility + PremiumContentProfile | 12 |
| Detalhe de conteúdo | **ATENDIDO** (Large) / **NÃO VERIFICADO** visualmente em AXXXL por captura manual (coberto funcionalmente por `testArticleActionsAndMetadataAtAXXXXL`) — `detail-pt-light-large.png` | **PRESERVADA** — parser/cache/permissions/tracking/state machine intocados; Prompt14Library (save/complete/retry/conflict) | 1 |
| Rotina | **ATENDIDO** — lista com glifos de status, detalhe com Tomado/Adiar/Pular por role e Histórico como row, sheet com fundo da marca e submit primário, snooze com presets e título da roda; `routine-list-pt-light-large.png`, `routine-detail-pt-light-large.png`, `routine-sheet-taken-pt-light-large.png`, `routine-snooze-final-pt-{light,dark}-large.png`, `cmp-routine-*.png` | **PRESERVADA** — políticas de snooze, idempotência, lifecycle, IDs, texto bruto do recibo ("taken"); Prompt13Routine + PremiumContentProfile | 6 |
| Histórico | **ATENDIDO** — cabeçalhos semânticos com glifo, rows com chevron, detalhe em um card; `history-pt-light-large.png`, `history-meal-detail-pt-light-large.png`, `cmp-history-list-detail.png` | **PRESERVADA** — cursor/paginação/IDs/separação meals-workouts; Prompt13PlanProgressHistory | 2 |
| Mascote | **ATENDIDO** (refresh no conteúdo, não na barra — ver decisão) — card com feedback, título semântico, retry/refresh consistentes; `mascot-card-pt-light-large.png`, `mascot-detail-final-pt-light-large.png` (estado final), `mascot-detail-pt-light-large.png` (variante toolbar, descartada), `cmp-mascot-card-detail.png` | **PRESERVADA** — artwork/animação/Reduce Motion intocados, anúncio "personalidade …/estado …" ; Prompt14TodayMascot não está na lista focada de I5 (mascot.refresh 45×45 coberto por Prompt14Accessibility `reduceMotion`) | 2 |

Presets de snooze: em Large os três `.secondary` não cabem em uma linha (3×≈127 pt + 24 > 370) e o `ViewThatFits` cai para a pilha — comportamento previsto pelo plano, registrado.

### Limitações e pendências registradas

- **"Cancelar" recortado na cápsula da toolbar da folha de persona** ("ancela") — pré-existente (já observado em I4), causado pelo `frame(minWidth: 44)` + cápsula iOS 26; Cancel/Save são intocáveis nesta operação (§6). Pendência para I7.
- **Conteúdo sintético menciona "aplicativo BodyFlow"** no corpo markdown da fixture Prompt 14 (`detail-pt-light-large.png`, abaixo da dobra): conteúdo de fixture QA/server-owned, não copy do app; scanner `PUBLIC_LEAK 0`. Fica sob ROBERTO JOURNEY FIXTURE STATUS: PENDING PRE-BETA STAGING CLEANUP.
- **Histórico a partir da lista (push por view)** não navega — defeito funcional pré-existente registrado em I3/I4; fora do escopo visual de I5.
- **Detalhe de conteúdo em AXXXL**: captura manual não realizada (navegação AXXXL custa ~8 gestos por tela); a fidelidade funcional em AXXXL está coberta por `PremiumContentProfileUITests/testArticleActionsAndMetadataAtAXXXXL` (que também anexa `s7-article-en-dark-axxxl`).
- **Hápticas** (persona salva, conteúdo salvo/concluído, ação de rotina): NOT VERIFIED em dispositivo físico (Simulator não reproduz `sensoryFeedback`).
- PLAN DISPLAY LABEL STATUS: PENDING CONTRACT CLASSIFICATION e ROBERTO JOURNEY FIXTURE STATUS: PENDING PRE-BETA STAGING CLEANUP permanecem registrados, não tocados.

### Builds do incremento (Debug, `build-for-testing`, DerivedData da sessão)

| Build | Conteúdo | Uso |
|---|---|---|
| `red` | testes RED + app HEAD | caracterização RED |
| `green1` | implementação I5 (filtros via `ViewThatFits`) | Progresso GREEN; Biblioteca ainda RED |
| `green2` | filtros em `HStack` fixo | Biblioteca GREEN; caracterização do `toolbarBackground` |
| `green3` | `toolbarBackground` removido | 3 gates nomeados + captura da matriz |
| `green4` | título da roda de snooze | unit completo, Release/codesign/scanner/analyze, UI focado run #1 |
| `green5` | refresh do mascote como elemento único; identidade do Perfil inline em AX | UI focado run #2 (3 classes afetadas) — ESTADO FINAL |

### Unit (invocações separadas, `-parallel-testing-enabled NO`)

| Invocação | Estado | Resultado |
|---|---|---|
| focado (21 suítes: núcleo + I5 + Symbol/Routine/History) | `green1` | XCTest 24/24 · Swift Testing 222/222 · 0 falhas · 120 s |
| **completo `BodyFlowTests`** | `green4` | **XCTest 24/24 · Swift Testing 1.213/1.213 (96 suítes) · 0 falhas · 0 skips** — 1.237 testes (+8 vs I4: 4 contratos em `BodyFlowPremiumRenderingTests`, 4 políticas em `BodyFlowComponentPolicyTests`) · 120 s |
| contratos (Rendering/Policy/Symbol/LocalizationContract) | `green5`, `green6`, `green7` | 24/24 XCTest + 33/33 Swift Testing em cada build, 0 falhas |
| **completo `BodyFlowTests` (ESTADO FINAL)** | `green7` | **XCTest 24/24 · Swift Testing 1.213/1.213 (96 suítes) · 0 falhas · 0 skips · 120 s** |

### UI focado — FULL SUITE RESULT (run #1, `green4`, uma invocação por classe, sequencial)

| Classe | Executados | Falhas | Tempo | Estado |
|---|---|---|---|---|
| PremiumPerformanceUITests | 4 | 0 | 201 s | PASS |
| Prompt14LibraryUITests | 12 (+1 novo) | 0 | 351 s | PASS |
| Prompt14AccessibilityUITests | 13 | **1** (`testReduceMotionEvidence`: "Multiple matching elements found" para `mascot.refresh`) | 294 s | FAIL |
| PremiumContentProfileUITests | 3 | **1** (`testProfileFixtureProvenanceAndServerOptionGate` linha 36: folha de persona não abriu após `style.tap()`) | 44 s | FAIL |
| Prompt14ProgressUITests | 5 (+1 novo) | 0 | 54 s | PASS |
| Prompt13PlanProgressHistoryUITests | 12 | 0 | 122 s | PASS |
| Prompt13RoutineUITests | 12 | 0 | 124 s | PASS |
| BodyFlowUITests | 18 | 0 | 431 s | PASS |
| PremiumConvergenceUITests | 4 | 0 | 137 s | PASS |
| **Total run #1** | **83** | **2** | 32 min | 81/83 |

Diagnóstico (xcresult preservado, hierarquia anexada): (a) o `Button` do refresh na toolbar com `Label` expunha dois elementos com o mesmo identificador → trocado por `Image(symbol:)` + `accessibilityLabel` (`MascotDetailView`); (b) em AXXXL a row `profile.coach-persona` media `{16, 787.3, 370, 350.3}` — a identidade em `HStack` (glifo em coluna de 44 pt) empurrou a row para baixo e seu centro caiu fora da viewport, onde o `tap()` do XCUITest não chega → em tamanhos de acessibilidade a identidade volta ao `Label` inline (`ProfileRootView`). Nenhum teste, timeout, allowlist ou ID foi alterado.

### UI focado — run #2 (`green5`, classes afetadas, uma invocação por classe)

| Classe | Executados | Falhas | Estado |
|---|---|---|---|
| PremiumContentProfileUITests | 3 | 0 | PASS (58,5 s) |
| Prompt14AccessibilityUITests | 13 | **1** — `testReduceMotionEvidence` ainda "Multiple matching elements": a hierarquia anexada mostra o identificador `mascot.refresh` espelhado no host do item da toolbar (`Other {337,66,45,36}`) e no `Button` — não era o `Label` | FAIL |
| PremiumConvergenceUITests | 4 | **1** — `testRepresentativeLoadedTabsPassAutomatedAccessibilityAudit` em `tab.perfil` ("Perfil de demonstração": "Dynamic Type font sizes are partially unsupported") — causado pelo ramo de layout por categoria introduzido na correção (b) | FAIL |
| contratos unit (Rendering/Policy/Symbol/LocalizationContract) | 24 XCTest + ST | 0 | PASS |

Correções para o run #3 (`green6`): identificador + rótulo falado movidos para o glifo dentro do `Button` (o host da toolbar deixa de espelhá-lo); identidade do Perfil com **uma** estrutura em todos os tamanhos (`Label` inline com o glifo + linha de proveniência — a mesma geometria pré-I5, que já passava na auditoria e mantém a row de persona ao alcance em AXXXL).

### UI focado — run #3 (`green6` = ESTADO FINAL, uma invocação por classe)

| Classe | Executados | Falhas | Estado |
|---|---|---|---|
| PremiumContentProfileUITests | 3 | 0 | PASS (56,3 s) |
| PremiumConvergenceUITests | 4 | 0 | PASS (137 s) |
| BodyFlowUITests | 18 | 0 | PASS (423 s) |
| Prompt14AccessibilityUITests | 13 | **1** — `testReduceMotionEvidence`: hierarquia anexada (`xcresult-attachments/rm-fail3`) mostra `mascot.refresh` de novo em dois elementos — o host do item da toolbar (`Other {337,66,45,36}`) e o `Button {337,61.7,45,45}` — mesmo com o identificador no glifo interno: o item de barra espelha qualquer identificador do seu conteúdo no host view | FAIL |
| contratos unit (Rendering/Policy/Symbol/LocalizationContract) | 24 XCTest + ST | 0 | PASS |

Decisão: o refresh do detalhe do mascote deixa a toolbar e vira um botão compacto `.secondary` (`isCompact`) no topo do conteúdo, alinhado à direita — um elemento, 44 pt, mesmo rótulo falado. A colocação na barra prevista pelo plano (§7.10) é incompatível com `Prompt14AccessibilityUITests`/`Prompt14TodayMascotUITests`, que endereçam `mascot.refresh` por identificador (`descendants(.any)`); os testes não foram alterados.

### UI focado — run #4 (`green7` = ESTADO FINAL)

| Classe | Executados | Falhas | Estado |
|---|---|---|---|
| Prompt14AccessibilityUITests | 13 | 0 | **PASS** (248,9 s) |
| contratos unit (Rendering/Policy/Symbol/LocalizationContract) | 24 XCTest + 33 ST | 0 | PASS |

**FINAL VERIFIED STATE (build `green7`):** as 9 classes focadas passaram na sua última execução — PremiumPerformance, Prompt14Library, Prompt14Progress, Prompt13PlanProgressHistory, Prompt13Routine em `green4` (as correções `green5→green7` tocaram só `ProfileRootView`, `MascotDetailView` e o título do snooze em `RoutineSnoozeView`, este último já em `green4`); PremiumContentProfile, PremiumConvergence, BodyFlowUITests em `green6` (fontes idênticas a `green7` exceto `MascotDetailView`, fora dessas classes); Prompt14Accessibility em `green7`. Total do último estado verde por classe: **83 / 83, 0 falhas, 0 skips**. Não é uma suíte única: run #1 = 81/83; correções e reexecuções por classe estão listadas acima. As 17 classes NÃO foram executadas → REGRESSION STATUS permanece PARTIALLY VERIFIED.

### Performance (`PremiumPerformanceUITests`, `green4`, 5 iterações, host load ≈5)

| Teste | Métrica | I1 | I5 (`green4`, run #1) | Δ | Limite → veredito |
|---|---|---|---|---|---|
| `testFlowFiftyMessageHistoryRenderBaseline` | Clock Monotonic Time (s) | 6.000 | 5.863 | -2.3 % | +20 % → OK |
| `testFlowFiftyMessageHistoryRenderBaseline` | Memory Peak Physical (kB) | 79153.528 | 40401.923 | -49.0 % | +10 % → OK |
| `testFlowFiftyMessageHistoryRenderBaseline` | Memory Physical (kB) | n/a | 62.259 | — | — |
| `testFlowLongPlainResponseWrappingBaseline` | Clock Monotonic Time (s) | 5.791 | 6.250 | +7.9 % | +20 % → OK |
| `testFlowLongPlainResponseWrappingBaseline` | Memory Peak Physical (kB) | 81339.154 | 47184.899 | -42.0 % | +10 % → OK |
| `testFlowLongPlainResponseWrappingBaseline` | Memory Physical (kB) | 6.554 | 19.661 | +200.0 % | +10 % → ruído de página (±64 kB; pico −42 %) |
| `testLibraryFeedScrollBaseline` | Clock Monotonic Time (s) | 5.451 | 6.008 | +10.2 % | +20 % → OK |
| `testLibraryFeedScrollBaseline` | Memory Peak Physical (kB) | 81018.027 | 46391.914 | -42.7 % | +10 % → OK |
| `testLocalLaunchBaseline` | Duration (AppLaunch) (s) | 1.851 | 1.035 | -44.1 % | +15 % → OK |
Clock dentro de +20 % (máx. +10,2 %), pico de memória −42 % a −49 %, launch −44 %. A métrica "Memory Physical" é o delta físico durante o bloco medido, com valores em passos de 16–64 kB (`[32.8, −16.4, 65.5, 0, 16.4]`): +13 kB sobre uma base de 6,5 kB é ruído de granularidade de página, não regressão. Nenhum dataset, fixture ou mensagem foi reduzido.

### Release / segurança / marca (estado final `green7`, DerivedDataRelease da sessão)

| Gate | Resultado |
|---|---|
| `xcodebuild build -configuration Release` (signing normal) | RELEASE_EXIT=0 (29 s) |
| `codesign --verify --deep --strict --verbose=2` | CODESIGN_EXIT=0 |
| `premium-surface-scan.mjs --baseline 7ab3e657` | **PASS** — PUBLIC_LEAK 0 · HISTORICAL_ASSET 18/18 IDENTICAL · ALLOWED_TECHNICAL 235 · failures [] |
| `node --test premium-surface-scan.test.mjs` | 21/21 |
| `xcodebuild analyze` (Debug, DerivedDataAnalyze) | ANALYZE_EXIT=0 (20 s, incremental); 0 avisos novos em fontes de produção |
| Assets | `git diff --stat -- assets Assets.xcassets` vazio; AccentColor intocado |
| Greps de política (fontes de produção) | shadow 0 · blur 0 · Material 0 (o `.regularMaterial` do badge de persona saiu) · glassEffect 0 · minimumScaleFactor 0 · scrollEdgeEffect 0 · toolbarBackground 0 · `dynamicTypeSize(` só em `#Preview` |
| Identificadores | nenhum removido (10 movidos permanecem presentes); novos: `progress.body`, `progress.achievements`; `state.retry` reutilizado na folha de persona |
| Marca pública | nenhuma literal nova; catálogo +5 chaves pt-BR/en sem nomes de marca; `brand.label == "Performe AI"` (BodyFlowUITests 18/18) |

### Capturas (`$SP/v6/i5/`, 85 PNG + `settings.log` + `hashes.txt`; nunca no repositório)

Antes (app HEAD e710dba, instalado pelo run RED): `before-progress-{light,dark}`, `before-library-{light,dark}`, `before-profile-light`. Caracterização da barra: `toolbar-char-library-{top-light,scrolled-light,scrolled-dark}`. Estado final: Progresso core 5 (`progress-pt-{light,dark}-{large,axxxl}`, `progress-en-light-large`) + `progress-streak-zero-light-{top,achievements}`; Perfil `profile-final-pt-light-large` (+ variante descartada `profile-pt-light-large`); persona `persona-pt-light-large` (fixture sem opções), `persona-options-pt-light-large`, `persona-selected-pt-light-large`; Biblioteca core 5 (`library-pt-{light,dark}-{large,axxxl}`, `library-en-light-large`) + `library-cover-under-bar-light` + live theme ×3 + `library-xctest-16-accessibility-xxxl`; detalhe `detail-pt-light-large`; Rotina `routine-list-pt-light-large`, `routine-detail-pt-light-large`, `routine-sheet-taken-pt-light-large`, `routine-snooze-final-pt-{light,dark}-large` (+ `routine-snooze-pt-*` pré-título); Histórico `history-pt-light-large`, `history-meal-detail-pt-light-large`; Mascote `mascot-card-pt-light-large`, `mascot-detail-final-pt-light-large` (+ variante toolbar descartada). Comparativos: `cmp-*.png` (14). Não capturados manualmente: Perfil core 5 além de light Large (fixture idêntica; AXXXL coberto por `testProfileFixtureProvenanceAndServerOptionGate`), detalhe de conteúdo em AXXXL (coberto por `testArticleActionsAndMetadataAtAXXXXL`, attachment `s7-article-en-dark-axxxl`).

### Git final

HEAD **inalterado**: `e710dba1eb7c59988c7d0dac1445d2ee909e14bf`; índice vazio; stash vazio; 29 caminhos dirty (1.232+/477−), NÃO stageados:
- `apps/ios/BodyFlow/BodyFlow/DesignSystem/BodyFlowSymbol.swift`
- `apps/ios/BodyFlow/BodyFlow/DesignSystem/Components/BodyFlowListStyle.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryMealLogDetailView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryMealLogRowView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryWorkoutDetailView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/History/MainHistoryView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Library/ContentCoverView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Library/LibraryRootView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Progress/Block7700DetailView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineActionSheet.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineDetailView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineHistoryView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineListView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutinePresentation.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineSnoozeView.swift`
- `apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings`
- `apps/ios/BodyFlow/BodyFlowTests/BodyFlowComponentPolicyTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/BodyFlowPremiumRenderingTests.swift`
- `apps/ios/BodyFlow/BodyFlowUITests/Prompt14LibraryUITests.swift`
- `apps/ios/BodyFlow/BodyFlowUITests/Prompt14ProgressUITests.swift`
- `docs/superpowers/evidence/2026-09-19-performe-ai-final-product-polish-and-brand.md`

Commit previsto (somente após aprovação visual explícita): `refactor(ui): refine Performe AI progress, profile and library density`.

### Status

- USER VISUAL ACCEPTANCE: **PENDING**
- REGRESSION STATUS: **PARTIALLY VERIFIED** (9 classes focadas verdes por classe no estado final + unit completo; 17 classes não executadas)
- PUBLIC BRAND STATUS: PARTIALLY VERIFIED (gate de I5 PASS; VERIFIED global reservado ao closeout I7)
- REBRAND STATUS: PARTIAL · IOS INTEGRATION STATUS: LOCAL ONLY · PRODUCTION STATUS: NOT DEPLOYED · APPICON TINTED: PENDING — NOT INTEGRATED
- HAPTICS ON PHYSICAL DEVICE: NOT VERIFIED
- COST / ENVIRONMENT CLOSEOUT: COMPLETE — nenhum recurso pago; Simulator iPhone 17 Pro iniciado nesta operação e o app encerrado ao final; nenhum processo de terceiros tocado.

## I5 — correção obrigatória da revisão visual: "Cancelar" cortado na folha de persona (2026-09-23)

Operação `FIX_I5_PERSONA_CANCEL_AND_RETURN_FOR_FINAL_VISUAL_GATE_V1` / `I5_SMALL_FIX_ONLY`. Revisão visual de I5: **APPROVED WITH ONE REQUIRED FIX** (folha "Estilo do Flow": "Cancelar" visualmente cortado à esquerda). Baseline revalidado: HEAD `e710dba1…` inalterado, índice vazio, 29 caminhos dirty de I5, nenhum writer concorrente.

### Caracterização (teste novo, RED antes da correção)

`PremiumContentProfileUITests/testPersonaSheetBarActionsRenderCompletelyAtRegularSize` (pt-BR, light, Large; fixture `--ui-testing-prompt14-persona-stateful`): abre a folha, exige Cancelar/Salvar existentes, hittable, ≥44×44 (`assertTarget`), sem interseção com o título "Estilo do Flow", acima da faixa de marca **da folha** (escopada por `screen.profile.coach-persona`, não a do shell), e — proxy de recorte — `Cancelar.width > Salvar.width` e `> 44,5` (um item de barra recortado reporta a largura do host, não a do rótulo). Anexa captura + hierarquia (`s7-persona-bar-actions-pt-light-regular`).

### PERSONA CANCEL ROOT CAUSE (por evidência de hierarquia, `xcresult-attachments/persona-{red,green,green2,e2}`)

| Variante | Host (Other) de Cancelar | Button de Cancelar | Salvar (host / button) | Visual |
|---|---|---|---|---|
| estado I5 (`.cancellationAction`, `.frame(minWidth: 44, minHeight: 44)`) | `{20, 82, 44, 36}` | `{20, 78, 44, 44}` | `{308.7, 82, 73.3, 36}` / `{…, 73.3, 44}` | "ancela" recortado |
| + `Text.fixedSize()` | `{20, 82, 44, 36}` | `{20, 78, 44, 44}` | idem | ainda recortado (descarta "conteúdo do botão") |
| placement `.topBarLeading` | `{20, 82, 44, 36}` | `{20, 78, 44, 44}` | idem | ainda recortado (descarta "toolbar placement") |
| **`.cancellationAction` sem `minWidth`** (só `minHeight: 44`) | **`{20, 82, 91.7, 36}`** | **`{20, 78, 91.7, 44}`** | idem | **"Cancelar" completo** |

Causa: a barra de navegação mede o item **leading** com proposta de largura zero; `frame(minWidth: 44)` resolve então para exatamente 44 pt e o `Text` ("Cancelar" ≈ 63,7 pt + 28 pt de padding do item) é recortado nesse host. O item **trailing** (Salvar) é medido com proposta ajustada, por isso `max(44, natural)` = 73,3 pt e nunca recorta. Não é safe area, marca, container compartilhado nem conteúdo do botão. Salvar vs Cancelar diferem só pelo lado de medição.

### FIX (menor correção; `CoachPersonaPickerView.swift`, somente o item de cancelamento)

- Removido o `minWidth: 44` do item de cancelamento (mantido `minHeight: 44` + `contentShape` no item); o texto passa a ter largura natural (91,7 pt ≥ 44).
- O glifo `xmark` mostrado em tamanhos de acessibilidade recebe `frame(minWidth: 44)` **dentro** do rótulo (um glifo ≤ 44 pt não recorta), preservando o alvo ≥44 em AX.
- Placement `.cancellationAction`, `dismiss()`, `saveTask`, `disabled(isSaving)`, rótulo falado, Salvar (intacto, incluindo seu `minWidth`), IDs, foco, marca e identificadores técnicos: inalterados. Nenhum redesenho.

### TESTS (build `persona-final`, uma invocação por classe/suíte)

| Invocação | Resultado |
|---|---|
| RED `testPersonaSheetBarActionsRenderCompletelyAtRegularSize` (estado I5) | FAIL esperado — primeira versão do teste acusou `cancel.maxY 122 > brand.minY 75` porque `brand.product-name` resolvia para a faixa do shell atrás da folha (corrigido escopando ao `screen.profile.coach-persona`); versão final RED em `.topBarLeading`: `Cancelar 44.0 não > Salvar 73.3` |
| GREEN `testPersonaSheetBarActionsRenderCompletelyAtRegularSize` (E2/final) | PASS (14,1 s) — Cancelar `{20, 78, 91.7, 44}` |
| Unit `CoachPersonaEditorModelTests CoachPersonaTests BodyFlowPremiumRenderingTests BodyFlowComponentPolicyTests LocalizationContractTests` | XCTest 24/24 · Swift Testing 43/43 · 0 falhas |
| `PremiumContentProfileUITests` (completo, 4 testes) | **4/4 PASS** (72 s) — inclui o gate AXXXL (`Cancelar ∩ Salvar` nulo, `brand.minY ≥ max(cancel.maxY, save.maxY)`) |
| `Prompt14AccessibilityUITests` (completo; nenhum teste endereça a folha de persona, executado por precaução) | **13/13 PASS** (250 s) |
| `PremiumConvergenceUITests` (completo; a hierarquia da barra da folha mudou de largura) | **4/4 PASS** (142 s) |
| Release / codesign / scanner (`final4`) | RELEASE_EXIT=0 (26 s) · CODESIGN_EXIT=0 · scanner PASS (PUBLIC_LEAK 0 · HISTORICAL_ASSET 18/18 · ALLOWED_TECHNICAL 235) |

Nenhum assert/timeout/allowlist/ID alterado. Provas exigidas: Cancelar totalmente visível (largura 91,7 pt = rótulo + padding; captura), hittable e ≥44×44 (`assertTarget`), Salvar visível e intacto (73,3×44), sem interseção com o título "Estilo do Flow", acima da faixa da marca da folha, pt-BR/en (o teste roda em pt-BR; o rótulo en "Cancel" é mais curto e segue a mesma medição), light/dark e AXXXL (capturas abaixo; em AX o glifo `xmark` mantém `minWidth: 44`).

### CAPTURES (`v6/i5/`, build `persona-final` instalado, hashes atualizados)

1. `persona-fix-pt-light-large.png` — pt-BR light normal: "Cancelar" completo na cápsula.
2. `persona-fix-pt-dark-large.png` — pt-BR dark normal (cold launch em dark).
3. `persona-fix-pt-light-axxxl.png` — AccessibilityXXXL: glifos `xmark`/`checkmark` em cápsulas ≥44, marca abaixo, sem overlap.
4. `persona-fix-selected-pt-light-large.png` — Impulso selecionado, linha enfatizada, Salvar habilitado.

Comparativos: `cmp-persona-cancel-before-after-light.png` (antes "ancela" | depois "Cancelar"), `cmp-persona-fix-dark-selected.png`. Sem retoque.

### PRE-ROBERTO FOLLOW-UP — ACHIEVEMENT DISPLAY LABEL

Observado na revisão visual de I5 (`progress-streak-zero-light-achievements.png`, cenário `--ui-testing-prompt14-streak-zero`): a medalha exibe o UUID bruto `70000000-0000-4000-8000-000000000001` como texto. O iOS renderiza `snapshot.badgesEarned` tal como recebido (`ProgressPresentation.medalRows`), sem inventar nome. Não corrigido nesta operação.

**ACHIEVEMENT DISPLAY LABEL STATUS: PENDING DATA / CONTRACT CLASSIFICATION** — classificar antes da beta Roberto: (A) o servidor possui display label oficial para conquistas; (B) a fixture QA está inadequada; (C) outro contrato define o texto público. O cliente não deve inventar um nome.

### PRE-ROBERTO FOLLOW-UP — HISTORY NAVIGATION

O relatório I5 registrou que, entrando no detalhe de um item de rotina a partir da lista (`RoutineListView` → push por view), o link "Histórico" (`routine.history`, `NavigationLink(value: AppRoute.routine(…destination: .history))`) não navegou na execução manual do harness (`--ui-testing-prompt13-loaded`); a mesma rota a partir do Hoje (push por valor) navega e é coberta por `Prompt13RoutineUITests/testRoutineHistoryLoadMoreAppendsNextPage`. Não corrigido nesta operação.

**HISTORY NAVIGATION STATUS: PENDING FUNCTIONAL VERIFICATION** — antes da beta Roberto: reproduzir na jornada real do app e classificar bug real (destino por valor fora da pilha alcançável após push por view) vs. artefato do harness/test host.

### Git final e status

HEAD **inalterado** `e710dba1eb7c59988c7d0dac1445d2ee909e14bf`; índice vazio; stash vazio; 30 caminhos dirty (+`BodyFlowUITests/PremiumContentProfileUITests.swift`), 1.530+/481−; nada stageado/commitado.

- I5 VISUAL STATUS: **READY FOR FINAL USER REVIEW**
- USER VISUAL ACCEPTANCE: **PENDING**
- REGRESSION STATUS: PARTIALLY VERIFIED · PUBLIC BRAND STATUS: PARTIALLY VERIFIED · PRODUCTION STATUS: NOT DEPLOYED
- ACHIEVEMENT DISPLAY LABEL STATUS: PENDING DATA / CONTRACT CLASSIFICATION · HISTORY NAVIGATION STATUS: PENDING FUNCTIONAL VERIFICATION

## I6 — Auth / Onboarding / Splash / raiz (2026-09-25/26, implementação — commit sob a operação seguinte)

Operação `EXECUTE_PERFORME_AI_UIUX_I6_V1` / `IMPLEMENTATION_I6_ONLY`. Performe AI = produto público; Flow = agente público; BodyFlow = identidade técnica interna preservada.

### Baseline revalidado (entrada)

```
branch codex/performe-ai-client-beta-flow-v1 · HEAD 5e0552ddb4b01c9a5405a3385fc084e3658d3673
parent e710dba1eb7c59988c7d0dac1445d2ee909e14bf · tree e44cc88692b56fc82739154aa9c67e915289aad3
subject refactor(ui): refine Performe AI progress, profile and library density
status 0 · index 0 · index.lock ausente · Xcode 27.0 (27A266a) · iPhone 17 Pro 27291590-… iOS 26.5
```

Hashes SHA-256 de entrada: `$SP/v6/i6/entry-hashes.txt` (21 linhas); de saída: `exit-hashes.txt` (16 linhas).

### RED (contratos de fonte em `BodyFlowPremiumRenderingTests`, cada um rodado contra a fonte intocada)

| Build | Teste novo | Resultado RED (valor observado) |
|---|---|---|
| `red2` | `testReviewedAuthOnboardingSourcesUseTheSymbolVocabulary` | FAIL — literais SF Symbol crus em AuthFieldMessage, PasswordRecoveryView, OnboardingViewSupport, OnboardingContainerView, Welcome/Objective/Persona/Consent/Completion, AppRootView |
| `red2` | `testReviewedOnboardingSelectionControlsUseTheRowButtonStyle` | FAIL — `.buttonStyle(.plain)` ×2 Welcome, ×1 Objective, ×1 Persona, ×2 Consent; nenhum `.bodyFlowRow` |
| `red2` | `testReviewedAuthOnboardingSourcesUseSharedStatusLineAndField` | FAIL — sem `BodyFlowStatusLine` em AuthFieldMessage/OnboardingViewSupport/OnboardingContainerView; `textFieldStyle(.roundedBorder)` em Welcome/BodyData |
| `red2` | `testRootAndOnboardingContainerKeyMotionToTheirOwnState` | FAIL — AppRootView sem `stateTransition`/`animation(.content)`; container sem `value: model.step` |
| `red3` | `testOnboardingDecimalFieldsOfferAKeyboardDoneAndScrollDismissal` | FAIL — BodyData sem toolbar de teclado/`keyboard.done`/`@FocusState`; container sem `scrollDismissesKeyboard`; catálogo sem `keyboard.done` (motivação: captura `onboarding-bodydata-keyboard-pt-dark-large.png` — decimal pad sem tecla de retorno cobrindo o CTA) |
| `red4` | `testOnboardingStepChangeReturnsTheScrollToTheTop` | FAIL — sem `ScrollViewReader`/`onChange(of: model.step)`/`scrollTo` (motivação: passo 7 abria rolado após o consentimento longo; título cortado sob a status bar) |
| `red5` | `testOnboardingSummaryCardFillsTheColumn` | FAIL — cartão de revisão sem `.frame(maxWidth: .infinity, alignment: .leading)` antes do fundo (cartão terminava em x≈749/920 enquanto o CTA ia a 864) |

`red2`: 28 executados / 4 falhas (24 pré-existentes passam). `red3`: 29/1. `red4`: 30/1. `red5`: 31/1. Logs `logs/v6-i6-unit-red{2,3,4,5}.log/.xcresult`.

### Mudanças por superfície (worktree dirty ao fechar a operação — commit sob `PERFORME_AI_ROBERTO_BETA_AUTONOMOUS_CLOSURE_V1`)

**Vocabulário (aditivo):** `BodyFlowSymbol` +`checkboxOn` (`checkmark.square.fill`), `checkboxOff` (`square`), `privacy` (`lock.shield`). `Localizable.xcstrings` +`keyboard.done` (pt-BR "Concluído" / en "Done"), inserido textualmente no formato bruto do catálogo (545 chaves).

**Auth** (`AuthFieldMessage`, `PasswordRecoveryView`): mensagem de campo = `BodyFlowStatusLine(.error, callout)` (glifo `exclamationmark.circle` do vocabulário); confirmação de recuperação = `BodyFlowStatusLine(.success, body)` + `padding(md)` + `.bodyFlowWash(.brandPrimary)` (id `auth.recovery.confirmation` mantido); `AuthScreenLayout` lê `\.bodyFlowReduceMotion`, marca + supporting copy com `stateTransition` e o VStack de título com `animation(.content, value: compact)` (SignUpView já passa `compact: focusedField != nil`). `SignInView`, `SignUpView`, `EmailConfirmationView`: intocados (botões loading-aware/`.bodyFlowField()` já entregues em I2A/I2B). Cadeias de foco, `submitLabel`, `textContentType`: intocados.

**Raiz** (`AppRootView`): `RootPresentationKey` (neutralLoading/launching/signIn/signUp/passwordRecovery/awaitingEmailConfirmation/onboardingLoading/onboardingReady/onboardingError/authenticatedLoading/authenticatedReady) derivada do coordinator — a chave é a TELA, não o passo do onboarding — com `rootContent.transition(stateTransition).animation(.content, value: rootPresentationKey)`; glifo do erro de carga do onboarding pelo vocabulário. Splash: `SplashView` NÃO tocado (já usa `PerformeAISymbolNegativeV1` + "Performe AI" + `ProgressView` `onPrimary` sobre `brandPrimary`, `@ScaledMetric`); o único motion é o fade de raiz acima.

**Onboarding** (`OnboardingContainerView`, `OnboardingViewSupport`, 7 steps): `stepContent` com `stateTransition` + `animation(.content, value: model.step)`; `ScrollViewReader` + `.id(OnboardingScrollAnchor.top)` + `onChange(of: model.step) { proxy.scrollTo(.top) }`; `.scrollDismissesKeyboard(.interactively)`; `OnboardingOperationMessage` = `BodyFlowStatusLine(.error)` + `bodyFlowWash(.feedbackDestructive)` (id `onboarding.error`); documentos indisponíveis com glifo `.unavailable`; `OnboardingFieldIssue` = `BodyFlowStatusLine(.error, callout)` (propaga a todos os passos). Welcome: campo de nome `.bodyFlowField()`; rows país/fuso `.bodyFlowRow` + chevron do vocabulário; pickers com `Image(symbol: .confirm)` + trait `.isSelected`; `caption.weight(.semibold)` → `BodyFlowTypography.caption`; `.secondary` → `secondaryText`. BodyData: 3 campos decimais `.bodyFlowField()` + `@FocusState<Field>` + `.focused` + toolbar `ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(copy("keyboard.done")) { focusedField = nil } }`; botão de data fallback `.secondary`. Routine: 4 botões fallback `.secondary`. Objective/Persona: glifos `selected/unselected` + `.bodyFlowRow` (traits/IDs intocados). Consent: `checkboxOn/Off` + `.bodyFlowRow` nos dois tipos de ação (IDs `onboarding.legal-action.<key>`, `consent.terms`, `consent.privacy` e trait `.isSelected` intocados; contrato legal intocado). Completion: aviso `Label(verbatim:symbol: .privacy)`; cartão de revisão `.frame(maxWidth: .infinity, alignment: .leading)` antes do fundo.

**Não tocado:** Core, repositórios, DTOs, API, auth service, sessão, Keychain, Supabase, consentimento (contrato/fail-closed), ownership server do onboarding, chaves persistidas, bundle, signing, entitlements, assets (diff `assets`/`Assets.xcassets` = 0 linhas), Picker/DatePicker/Stepper/Toggle nativos.

### GREEN e testes (uma invocação por classe; nunca somando reexecuções)

| Estado | Invocação | Resultado |
|---|---|---|
| `green1` | unit `BodyFlowPremiumRenderingTests` | 28/28 |
| `green2` | unit `BodyFlowPremiumRenderingTests` | 29/29 |
| `green2` | unit FULL `BodyFlowTests` | 1242 passed / 0 failed / 0 skipped (XCTest 29 + Swift Testing) |
| `green2` | UI `PremiumAuthOnboardingUITests` / `BodyFlowUITests` / `PremiumConvergenceUITests` / `PremiumCoreSurfacesUITests` | 3/0 · 18/0 · 4/0 · 9/0 |
| `green3` | unit `BodyFlowPremiumRenderingTests` | 30/30 |
| `green3` | unit FULL | 1243 / 0 / 0 |
| `green3` | UI (as 4 classes) | 3/0 · 18/0 · 4/0 · 9/0 |
| **`green4` (FINAL)** | unit FULL `BodyFlowTests` | **1244 passed / 0 failed / 0 skipped** (`BodyFlowPremiumRenderingTests` 31/31) |
| **`green4` (FINAL)** | UI `PremiumAuthOnboardingUITests` | **3 / 0 / 0** (240 s) |
| **`green4` (FINAL)** | UI `BodyFlowUITests` | **18 / 0 / 0** (480 s) |
| **`green4` (FINAL)** | UI `PremiumConvergenceUITests` | **4 / 0 / 0** (151 s) |
| **`green4` (FINAL)** | UI `PremiumCoreSurfacesUITests` | **9 / 0 / 0** (180 s) |

Logs/xcresult: `logs/v6-i6-unit-green4-full.*`, `logs/v6-i6-ui-green4-<Classe>.*`, monitor `logs/v6-i6-ui-green4-monitor.log`. Watchdog não disparou. As 13 classes UI restantes NÃO foram executadas nesta operação → REGRESSION PARTIALLY VERIFIED.

### Release e gates (estado final `green4`, `logs/v6-i6-*-final2.*`)

- Release: `** BUILD SUCCEEDED **`, `Signing Identity: "Sign to Run Locally"`, `CFBundleIdentifier com.bodyflow.app`, `CFBundleDisplayName Performe AI`; único warning pré-existente `SessionLifecycleCoordinator.swift:210` (`#UnnecessaryEffectMarker`), 0 erros.
- `codesign --verify --deep --strict --verbose=2`: `valid on disk` · `satisfies its Designated Requirement` · exit 0.
- `xcodebuild analyze` (Debug, `DDA`): `** ANALYZE SUCCEEDED **`, exit 0, nenhum diagnóstico novo.
- `premium-surface-scan --baseline 7ab3e657`: `status PASS`, `brandAssetApprovalGate APPROVED_FOR_LISTED_RC1_FILES`, `PUBLIC_LEAK 0`, `ALLOWED_TECHNICAL 235`, `HISTORICAL_ASSET 18` (18/18 IDENTICAL), `DEBUG_ONLY 0`, `failures 0`, catálogo 545 chaves / 1090 valores (pt-BR + en), compilado `displayName Performe AI`.
- Scanner tests: 21 / 21 pass / 0 fail.
- Policy greps na árvore da app: `.shadow(` 0 · `.blur(` 0 · `glassEffect` 0 · `minimumScaleFactor` 0 · `scrollEdgeEffect` 0 · materiais 0 · `dynamicTypeSize(` só em previews (`Prompt13PreviewSupport`, previews dos steps do onboarding) · novos hex no diff 0.
- Inventário de identifiers: HEAD 190 → worktree 190, removidos 0, adicionados 0.
- `git diff --check`: limpo. Asset diff: 0.

### Capturas (`$SP/v6/i6/`, 92 PNG, `settings.log`, `hashes.txt`; Simulator real iPhone 17 Pro iOS 26.5, 402×874 pt @3x)

Linhagem de builds: `green1` (convergência Auth/Onboarding) → `green2` (+Done no teclado/scroll-dismiss) → `green3` (+reset de rolagem por passo) → `green4` (+cartão de revisão na largura da coluna) = FINAL. As fontes de Auth/Splash não mudaram após `green1`, logo as capturas `green1` de Auth representam a UI final.

- **Auth:** `signin-pt-light-large` · `signin-pt-dark-large`/`final-signin-pt-dark-large` · `signin-pt-light-axxxl` · `final-signin-pt-dark-axxxl` · `signin-error-pt-light-large` (serviceUnavailable via `--ui-testing-auth-error`) · `signup-pt-{light,dark}-large` · `final-signup-pt-{light-axxxl,dark-large}` · `signup-focus-compact-pt-light-large` (layout compacto animado) · `signup-validation-pt-{light,dark}-large` · `signup-mismatch-pt-light-large` · `recovery-pt-{light,dark}-large` · `recovery-confirmation-pt-{light,dark}-large` (status line .success) · `email-confirmation-pt-light-large` · `final-email-confirmation-pt-dark-large`.
- **Onboarding:** Welcome `final-…-welcome-pt-{light,dark}-large`, `-light-axxxl`, `onboarding-welcome-pt-dark-axxxl`, `final-…-welcome-focus-pt-{light,dark}-large`, `onboarding-welcome-validation-pt-light-large`; Body data `final-…-bodydata-pt-{light,dark}-large`, `final-…-bodydata-keyboard-done-pt-{light,dark}-large` (decimal pad + "Concluído"), `final-…-bodydata-after-done-pt-light-large`; Objective `final-…-objective(-selected)-pt-{light,dark}-large`; Routine `final-…-routine-pt-{light,dark}-large`, `-scrolled-pt-light-large`, `final-…-routine-pt-light-axxxl` (cold launch); Persona `final-…-persona-pt-{light,dark}-large`; Consent `final-…-consent-{unselected,selected}-pt-{light,dark}-large`, `final-…-consent-continue-{disabled,enabled}-pt-{light,dark}-large`; Completion `final-…-completion-pt-{light,dark}-large` (topo, após reset de rolagem), `final-…-completion-bottom-pt-dark-large`.
- **Splash:** `splash-native-render-{pt-BR,en-US}-light-large` = **render nativo da view** (`BodyFlowPremiumRenderingTests.testSplashNativeRenderForDocumentaryReview`, 393 pt) — **não é captura temporal do launch**; a primeira tela pós-launch capturada a frio é `final-signin-pt-dark-large`/`signin-pt-light-large`.
- **Before/after** (HEAD 5e0552d compilado de `git archive` em DerivedData isolado): `cmp-{signin-error,welcome,bodydata,objective-selected,consent-selected}-before-after-light`, `cmp-bodydata-keyboard-before-after-dark`, `cmp-{welcome,consent-selected}-before-after-final-light`.
- Supersedidas (mantidas como evidência, rotuladas no `settings.log`): `superseded-live-switch-onboarding-routine-pt-light-axxxl` (troca ao vivo de content size deixou o DatePicker com layout compacto obsoleto → recapturada a frio), `superseded-mislabeled-consent-third-checked-continue-still-disabled-pt-dark-large` (o painel do Simulator repinta com 1–3 s de atraso após o toque; a captura foi tirada antes do repaint).

### VISUAL FIDELITY vs FEATURE FIDELITY (vs. B2 — Warm Performance / Signal Spark; nunca "igual à referência")

| Superfície | VISUAL FIDELITY | FEATURE FIDELITY |
|---|---|---|
| Sign-in | ATENDIDO — identidade compacta, campos nativos elevados, CTA primário/secundário, link terciário; idle pixel-idêntico ao HEAD (primitives já eram de I2A/B) | PRESERVADA (3/3 `PremiumAuthOnboardingUITests`, 18/18 `BodyFlowUITests`) |
| Sign-up | ATENDIDO — layout compacto animado ao focar (≤200 ms, `stateTransition`), validação em status line | PRESERVADA (`submitLabel`, `textContentType`, foco intocados) |
| Recovery | ATENDIDO — confirmação como status line .success sobre wash da marca (era Label solto) | PRESERVADA (string en/pt travada) |
| Confirmação de e-mail | ATENDIDO (sem mudança de fonte; botão "Continuar no ambiente de teste" é fixture de demo — ver pendência QA) | PRESERVADA |
| Welcome | ATENDIDO — campo `.bodyFlowField()`, rows país/fuso com feedback de toque | PRESERVADA (`onboarding.display-name/country/timezone`, contrato de país/fuso) |
| Body data | ATENDIDO — campos consistentes com Auth; teclado decimal fechável ("Concluído"), CTA nunca escondido | PRESERVADA (DTO/validações intocados) |
| Objective / Persona | ATENDIDO — glifo selected/unselected + press feedback | PRESERVADA (`.isSelected`, IDs) |
| Routine | ATENDIDO (botões fallback por role); controles nativos tintados desde I2A | PRESERVADA |
| Consent | ATENDIDO — checkbox glifo + row feedback; sem mudança legal | PRESERVADA (fail-closed, IDs `onboarding.legal-action.*`) |
| Completion | ATENDIDO — abre no topo após passo longo; cartão na coluna | PRESERVADA (`onboarding.go-to-today`) |
| Splash | NÃO VERIFICADO temporalmente (render nativo apenas); composição inalterada | PRESERVADA |

### Limitações

- Estado *loading* do Sign-in não capturado: não há launch argument de autenticação atrasada; a UI loading-aware foi verificada por `BodyFlowPremiumRenderingTests` (matriz `isLoading`).
- Sign-up AXXXL, Welcome dark AXXXL: via `simctl ui content_size` ao vivo (sem cold launch); Recovery AXXXL não capturado (opcional).
- Ferramenta de input do Simulator: descarta às vezes o primeiro caractere em campo seguro e descartou o último de "Ana" → "An" no resumo (artefato de ferramenta, anotado no `settings.log`).
- VoiceOver manual: NOT EXECUTED. Hápticas em dispositivo físico: NOT VERIFIED.
- 13 classes UI não executadas nesta operação (regressão parcial por desenho da operação).

### Pendências preservadas (não tocadas)

ACHIEVEMENT DISPLAY LABEL STATUS: PENDING DATA / CONTRACT CLASSIFICATION · HISTORY NAVIGATION STATUS: PENDING FUNCTIONAL VERIFICATION · ROBERTO JOURNEY FIXTURE STATUS: PENDING PRE-BETA STAGING CLEANUP · PLAN DISPLAY LABEL STATUS: PENDING CONTRACT CLASSIFICATION · HAPTICS ON PHYSICAL DEVICE: NOT VERIFIED · APPICON TINTED: PENDING — NOT INTEGRATED.

### Status ao fechar a operação I6

I6 STATUS: IMPLEMENTED — GATES GREEN · REGRESSION STATUS: PARTIALLY VERIFIED · PUBLIC BRAND STATUS: PARTIALLY VERIFIED (global) · REBRAND STATUS: PARTIAL · IOS INTEGRATION STATUS: LOCAL ONLY · PRODUCTION STATUS: NOT DEPLOYED · APPICON TINTED: PENDING — NOT INTEGRATED · I6 VISUAL STATUS: READY FOR USER REVIEW · USER VISUAL ACCEPTANCE: PENDING → reclassificado como DEFERRED TO FINAL REVIEW por instrução explícita do usuário (`PERFORME_AI_ROBERTO_BETA_AUTONOMOUS_CLOSURE_V1`, §0/§8), que autoriza o commit local após os gates.

## I7 + pré-Roberto + staging — `PERFORME_AI_ROBERTO_BETA_AUTONOMOUS_CLOSURE_V1` (2026-09-26)

Operação autônoma delimitada (substitui apenas os STOPs intermediários de aceite visual de I6/I7). Performe AI = produto público; Flow = agente público; BodyFlow = identidade técnica interna preservada. Ledger de execução (fora do produto): `$SP/roberto-beta/ledger.md`.

### Autoridade e baseline

Cadeia documental revalidada por blob (dossiê pinado `b4c09e80…:docs/handoffs/2026-08-20-…` blob `d396bbd7…` sha256 `f0dc6dcd…`; specs/plans 08-11, addendum/spec 09-14, spec 09-17, spec 09-19, manifesto Signal Spark `9ca2587a…`, scanner `7986173f…`) — todos idênticos ao FINAL AUTHORITY AMENDMENT §B. AUTHORITY STATUS: VERIFIED. Baseline de entrada: HEAD `5e0552dd…` com o I6 pronto e não commitado (a operação foi sequenciada pelo usuário após o fechamento do I6); commit I6 = `f24e666e2e9748fa4125cfcf90af4c58358c2c97`.

### I7 — revisão "primeira vez" (build `f24e666` Debug, Simulator real; capturas em `$SP/v6/final/`, `settings.log`)

Matriz capturada: Hoje (pt L/D Large, L/D AXXXL, en), Registrar (L/D, AXXXL), Plano (L/D, AXXXL), Progresso (L/D, AXXXL, escuro rolado), Perfil (L/D, AXXXL), Flow (L/D), Biblioteca (família indisponível L/D — a combinação prompt13+prompt14 seleciona o fixture prompt13), estados do Hoje (indisponível, offline-stale, loading, erro, vazio). Auth/Onboarding/Splash: matriz do I6 (`$SP/v6/i6/`).

| # | Achado | Classe | Decisão |
|---|---|---|---|
| F-01 | Hoje: proteína "90.5 g" sem locale (hidratação "1.250 ml") | Important / P1 | CORRIGIDO — `TodayValueFormatter.grams(_:language:)` com o locale do idioma (pt-BR "90,5 g") |
| F-02 | Hoje: "Protocolo: recomposicao" valor bruto | Minor | DEFER — string travada por `Prompt13TodayUITests` ("Protocolo: recomposicao"); valor oficial server-owned |
| F-03 | Plano: enums brutos `strength`/`macro_targets` + notas "sintético" | Important (§10-A) | CORRIGIDO na camada de apresentação para os enums FECHADOS do banco (`split/full_body/custom`, `diet/shopping_list/combined`), pt-BR/en; valores fora do enum continuam brutos (dados oficiais). Os valores dos fixtures Debug (`strength`, `macro_targets`) NÃO existem no contrato — permanecem como prova do fallback bruto |
| F-04 | Progresso: medalhas `first_week`/UUID | Important (§10-B) | CORRIGIDO nos fixtures Debug (o servidor já envia nomes humanos em `badges_earned`) |
| F-05 | Registrar: copy "Demonstração local… em Release" alcança o Release | Important (§10-D) | CORRIGIDO — `AppDependencies.isRegistrationAvailable`; sem capacidade de registro o tab renderiza o estado indisponível honesto |
| F-06 | Perfil: "Perfil de demonstração" alcança o Release | Important (§10-D) | CORRIGIDO — `presentsRealAccountIdentity` + `accountEmail` (conta conectada como identidade; linhas de demonstração ocultas); Debug/demo inalterado (strings travadas) |
| F-07 | Histórico de rotina não empurra a tela | Real bug / P2 | DEFER_AFTER_ROBERTO — reproduzido na jornada real (captura `routine-history-nav-bug-pt-light-large.png`); rotina indisponível no Release |

Critical: 0. Important: 5 corrigidos (F-01, F-03, F-04, F-05, F-06). Minor/deferred: F-02, F-07.

### Integração Release (Hoje real)

Descoberta: o Release ligava só Auth/Onboarding/Flow ao BFF; Hoje/Histórico/Plano/Progresso eram `Unavailable*`. Correção: `MobileBodyFlowRepository` (Core/Networking) sobre `MobileAPITransport.executeEnvelope` (preserva `meta.request_id` real) para `GET /api/mobile/v1/today|history|plan|progress`; erros de transporte mapeados para `BodyFlowCapabilityError` (`network/timeout → offline`, `unavailableConfiguration → operationUnavailable`, HTTP 402 → `subscriptionRequired`, demais → `serviceUnavailable`). Registro/hidratação/peso/rotina/biblioteca/mascote permanecem indisponíveis nesta fase (RULING R2).

### RED → GREEN

RED (build `red1`, run `red1`): 14 issues, exatamente nos 6 testes novos/alterados (`TodayPresentationTests.gramValuesFollowTheLanguageLocale`, `PlanPresentationTests.closedEnumsRenderDisplayLabels`, expectativas de medalhas em `DemoPrompt14RepositoryTests`/`AppDependenciesTests`, `AppDependenciesTests.validOriginAndSessionInstallTransport` [today/history/plan/progress ≠ Unavailable], `BodyFlowPremiumRenderingTests.testShellPassesCapabilityTruthToRegisterAndProfile`). GREEN (build `green4`): suítes tocadas + `LocalizationContractTests` 0 falhas; unit completo 32 XCTest + 1215 Swift Testing = 1247/0/0; UI `Prompt14ProgressUITests` 5/0, `Prompt13TodayUITests` 11/0, `PremiumContentProfileUITests` 4/0, `PremiumCoreSurfacesUITests` 9/0 (uma invocação cada). Duas iterações intermediárias (`green2`/`green3`) falharam só em `closedEnumsRenderDisplayLabels` por construção da chave de localização via interpolação (`%@.%@`); corrigido com chave `String` + `init(stringLiteral:)`.

### Staging (branch Supabase `xitugspwfxkcluxvrdeg`; produção `xuxehkhdvjivitduarvb` nunca endereçada)

- Vercel MCP: 403 para o escopo `gestao-9664s-projects` → nenhum deploy/env do BFF nesta operação; o Preview gravado no xcconfig privado (16/09) está vivo (401 `missing_access_token` com `request_id`).
- Escritas (todas reversíveis, sem DELETE): 4 documentos sintéticos pt-BR `qa-e2e-v1` publicados + requirement set `qa-e2e-v1` publicado (contrato de `docs/legal/performe-ai/synthetic-staging-e2e-readiness.md`); evento de entitlement manual/sandbox (`bodyflow_full`, trial, ativo até 2026-10-26T18:10Z, reason `qa_roberto_beta_candidate`) para a identidade sintética CI-3 (não onboarded, não banida); senha da conta redefinida (hash bcrypt gerado localmente; só o hash transitou SQL).
- FLOW REAL PROVIDER SMOKE: BLOCKED_BY_PAID_PROVIDER_AUTHORIZATION (chave revogada em 17/09; sem escopo Vercel e sem autorização de gasto).

### Build candidata (Release + xcconfig privado)

`xcodebuild build -configuration Release -sdk iphonesimulator -xcconfig <privado>` → BUILD SUCCEEDED (134 s), `codesign --verify --deep --strict` OK, `Info.plist` com `PERFORME_MOBILE_API_ORIGIN`/`PERFORME_SUPABASE_URL`/`PERFORME_SUPABASE_PUBLISHABLE_KEY` expandidas (valores não impressos). Instalada no iPhone 17 Pro; cold launch → Sign-in real (`e2e-01-cold-launch-first-screen.png`).

### STAGING E2E — BLOQUEADO na entrada da credencial

A digitação da senha da conta QA no campo de senha foi negada pela política de segurança (o app aponta para um host remoto de staging; a exceção de "testar o próprio app" cobre só hosts locais). Não houve contorno. Passos 2–15 do §13 NÃO EXECUTADOS nesta sessão. Estado deixado: candidata instalada no simulador primário, tela de login com o e-mail sintético digitado; senha no arquivo local 0600 `~/.local/share/performe-ai/roberto-beta/qa-user-a.env`.

### Regressão final — primeira tentativa (caracterização) e correção de causa raiz

A primeira execução completa (dispositivo secundário, `run all`) falhou logo na 1ª classe: `BodyFlowUITests.testRegistrationSheetExplainsNothingWasSaved` — regressão REAL introduzida por F-05: no modo demo Debug sem cenário prompt13/14, `registration` é `Unavailable*` por construção e a aba Registrar é uma demonstração local por design; o gate por capacidade escondeu a demonstração. Causa raiz corrigida em `AppDependencies.isRegistrationAvailable` (= `!presentsRealAccountIdentity || capacidade presente`): RED unitário `registerAvailabilityFollowsCapabilityTruth` (demo → true FAIL; release+Supabase → false PASS) → GREEN; `BodyFlowUITests` focado 18/0 (481 s, uma invocação). A cadeia foi interrompida deliberadamente após 2 classes (fontes mudaram): `FlowChatUITests` 12 executados / 1 falha (`testLocalSceneAndAccessibilityPresentationMatrixDark`, valor de aparência "light" ≠ "dark") registrada como CARACTERIZAÇÃO sob carga concorrente de build; classificada pela execução final limpa.

### Regressão final (fontes finais, build Debug `final`; uma invocação por classe; nenhuma reexecução somada)

**Tentativa 2 — dispositivo secundário iPhone 17 (`EF1AACEB…`), limpa:** unit completo 32 XCTest + 1216 Swift Testing = **1248 / 0 / 0**. UI: 13 classes 0 falhas; `BodyFlowUITests` 18/1 (`testFreshUserCompletesOnboardingAndReachesToday`, espera de entrada no campo seguro — flake documentado no próprio teste para iOS 26.5), `FlowChatUITests` 12/2, `Prompt13AccessibilityUITests` 5/1, `Prompt14AccessibilityUITests` 13/2 — todas as falhas de "dark" com o app reportando `light`. **Sonda após a cadeia:** `simctl ui … appearance` = dark e o app renderizou claro (`v6/e2e/probe-dev2-dark.png`) → o dispositivo secundário não aplica a aparência ao app; falhas ambientais e específicas do dispositivo (RULING R10).

**Tentativa 3 — dispositivo primário designado iPhone 17 Pro (`27291590…`), limpa:** unit completo **1248 / 0 / 0**; UI **16 classes com 0 falhas** (`FlowChatUITests` 12/0, `Prompt13AccessibilityUITests` 5/0, `Prompt14AccessibilityUITests` 13/0, `Prompt13RegistrationUITests` 21/0, `Prompt14LibraryUITests` 12/0, …); `BodyFlowUITests` 18/1 — `testProfilePersonaChangeIsReflected` (`BodyFlowUITests.swift:491`: a folha de persona demo demorou mais de 3 s para fechar após Salvar; passou em 4 invocações únicas nas mesmas fontes: green4, all, fix2-focado, final2). Nenhuma mudança de produto derivada; nenhuma 4ª tentativa (seria "rerun até passar").

FULL SUITE RESULT: unit 0 fail; UI 1 fail em 1 de 17 classes (tentativa 3) · ISOLATED CHARACTERIZATION: flakes de timing (entrada em campo seguro; fechamento da folha de persona) e dispositivo secundário sem aparência · FINAL VERIFIED STATE: **REGRESSION STATUS: PARTIALLY VERIFIED** (todas as 17 classes têm pelo menos uma invocação única com 0 falhas nas fontes finais; não houve uma única execução completa com 0 falhas).

### Gates de Release (fontes finais, DerivedDataRelease sem xcconfig)

BUILD SUCCEEDED (26 s, "Sign to Run Locally", 0 erros) · `codesign --verify --deep --strict` OK · `xcodebuild analyze` ANALYZE SUCCEEDED · scanner `--baseline 7ab3e657`: PASS, `PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18/18`, `ALLOWED_TECHNICAL 236` (+1 = novo tipo técnico `MobileBodyFlowRepository`), `displayName Performe AI`, `com.bodyflow.app` · scanner tests 21/21 · greps de política 0 (shadow/blur/glass/minimumScaleFactor/scrollEdge/material), `dynamicTypeSize(` só em previews · identifiers 190 → 190 · asset diff 0 · `git diff --check` limpo.

### Capturas I7 (`$SP/v6/final/`, `settings.log`, `hashes.txt`)

Hoje L/D/AXXXL/en + famílias de estado; Registrar, Plano, Progresso, Perfil L/D/AXXXL; Flow L/D; Biblioteca (família indisponível) L/D; evidência do bug de navegação do Histórico; "after" dos fixes: `today-after-fix-grams-pt-light-large.png` ("90,5 g"), `progress-after-fix-badges-pt-light-large.png` (nomes de medalha). Registrar/Perfil em Release com conta real: NÃO CAPTURADOS (dependem do sign-in bloqueado) — cobertos por testes unitários e de contrato.

### Build candidata

`$SP/DerivedDataStaging/Build/Products/Release-iphonesimulator/BodyFlow.app` (23 MB, versão 1.0 (1), executável sha256 `c534a942…`), Release + xcconfig privado, "Sign to Run Locally", instalada no iPhone 17 Pro na tela de login. Sem archive de distribuição (signing de distribuição/TestFlight são gates humanos posteriores).

### Status ao fechar a operação

ROBERTO BETA CANDIDATE STATUS: **BLOCKED** — menor gate restante: entrada da credencial QA no sign-in (ação humana) e execução dos passos 2–15 do E2E de staging (§13) · REGRESSION STATUS: PARTIALLY VERIFIED · PUBLIC BRAND STATUS: PARTIALLY VERIFIED (scanner PASS; superfícies Release com conta real não inspecionadas) · REBRAND STATUS: PARTIAL · IOS INTEGRATION STATUS: PARTIAL (auth/onboarding/Flow/Hoje/Histórico/Plano/Progresso ligados ao BFF; E2E não executado nesta sessão) · PRODUCTION STATUS: NOT DEPLOYED · USER VISUAL ACCEPTANCE: PENDING FINAL REVIEW · APPICON TINTED: PENDING — NOT INTEGRATED · VOICEOVER MANUAL: NOT EXECUTED · HAPTICS ON PHYSICAL DEVICE: NOT VERIFIED · FLOW REAL PROVIDER SMOKE: BLOCKED_BY_PAID_PROVIDER_AUTHORIZATION · COST / ENVIRONMENT CLOSEOUT: COMPLETE (nenhum recurso pago; staging KEPT) · HISTORY NAVIGATION STATUS: REAL BUG — DEFER_AFTER_ROBERTO · PLAN DISPLAY LABEL STATUS: RESOLVED (enums fechados) · ACHIEVEMENT DISPLAY LABEL STATUS: RESOLVED (fixture) · ROBERTO JOURNEY FIXTURE STATUS: RESOLVED no cliente (Registrar/Perfil); documentos de consentimento sintéticos em staging por design.

## Integração funcional (classe B) — `PERFORME_AI_FUNCTIONAL_BETA_CONTINUOUS_EXECUTION_V2` (2026-09-26/27)

Retomada a partir de `e9cfca3d` (sem reiniciar I6/I7). Performe AI = produto público; Flow = agente público; BodyFlow = identidade técnica interna preservada. Classificação por requisito: **A** comprovado, **B** contrato aprovado → integrar sem perguntar, **C** exige desenho, **D** acesso/decisão externa (pacote único em `$SP/roberto-beta/approval-package-cd.md`). Ledger: `$SP/roberto-beta/ledger.md`.

### Tarefa 1 — Registro e hidratação sobre o BFF (B)

- `MobileRegistrationRepository` (`RegistrationProviding` + `HydrationRecording`): `POST /registrations/propose`, `PATCH /registrations/{id}`, `POST /registrations/{id}/confirm`, `DELETE /registrations/{id}`, `POST /routine/hydration`; chave de idempotência = `MutationAttempt.key`; ids só no alfabeto UUID (`MobileAPIPathSegment.identifier`, fail-closed `.invalidInput`); erros de transporte → estados de capacidade (`registration_not_pending`, 410, 422, `idempotency_*`, 402, offline, unavailable).
- Detecção de refeição por texto = `TextMealDetector` determinístico ("alimento + gramas" por linha, 1…30 linhas, quantidade > 0 ≤ 9999, sem cálculo nutricional; o servidor precifica) — RULING R11. Foto/áudio continuam indisponíveis (C1).
- Apresentação "ao vivo" separada da demonstração travada (`presentsLocalDemonstration` em `RegisterRootView`/`RegistrationSheet`/`MealCaptureSourceView`/`MealTextDraftView`; 6 chaves pt-BR/en). Peso: sem rota mobile → linha oculta em conta real (lacuna registrada). `MealProposalEditorView` deixa de semear `user_kcal` com o kcal calculado (viraria override no servidor).
- RED → GREEN: `AppDependenciesTests` (capacidades) + contrato de fonte FAIL → GREEN em `TextMealDetectorTests`, `APITimestampTests` (microssegundos/`+00:00` decodificam sem mudança de parser), `MobileRegistrationRepositoryTests`, `AppDependenciesTests`, `BodyFlowPremiumRenderingTests`, `RegistrationPresentationTests`, `MealRegistrationModelTests`, `LocalizationContractTests`.
- UI focada (primário, fontes = registro + helpers): `PremiumRegistrationUITests` 3/0, `Prompt13RegistrationUITests` 21/0, `BodyFlowUITests` 18/0, `Prompt13AccessibilityUITests` 5/0.

### Tarefa 2 — Rotina, fuso do paciente, Biblioteca, persona/mascote e sair da conta (B)

- `MobileRoutineRepository`: `GET /{supplements|medications}?include_archived`, `POST …/{id}/log` (corpo = `RoutineActionCommand`, `snoozed_until` omitido quando nulo), `GET …/{id}/history?limit&cursor` (limit 1…50, cursor base64url — fail-closed); `routine_transition_invalid`/`routine_snooze_invalid` mapeados.
- Fuso do paciente (RULING R13): `PatientTimeZoneStore` semeado por launch (Prompt 13 = argumentos; demais = indocumentado), resolvido por sessão a partir de `GET /me` (`MeSnapshot`, `MeProviding`) pelo `Prompt14SessionOwner` através do mesmo gate das demais capacidades, `reset()` no fim da sessão e via `SensitiveStateClearing` no `SessionLifecycleCoordinator` (logout/troca de usuário). Só um identificador IANA documentado e conhecido libera snooze e horários locais.
- Biblioteca: `MobilePublishedContentRepository` (`GET /content` com `surface/category/limit/cursor`, `GET /content/{id}`, `POST …/read`, `POST …/save`; 422 em página com cursor → `.invalidContentCursor`); capas por `MobileContentCoverByteStream` (RULING R12): mesma origem/lease/sem redirect do transporte, bearer só para URL aprovada por `MobileAPIConfiguration.approves`, `Accept` de imagem, trabalho de paciente registrado e encerrado exatamente uma vez, `cancelAll` por sessão. Staging **sem conteúdo publicado** (D6) → a Biblioteca real mostra o estado vazio honesto.
- Persona/mascote: `MobileCoachPersonaRepository` (`GET`/`PATCH /coach/persona`) serve `CoachPersonaRepository` e `CoachExperienceProviding`; `MascotSnapshot.changedAt` passa a opcional (o BFF envia `null` para conta nova — antes a decodificação falhava) com copy honesta `mascot.changed-at.unavailable`.
- Sair da conta: `AppRootView` → `AppShellView(signOut:)` → `ProfileRootView` (seção "Conta", botão destrutivo com diálogo de confirmação, id `profile.account.sign-out`), só em conta real; a demonstração não ganha seção. Caminho existente `AppFlowModel.signOut()` → `SessionLifecycleCoordinator.signOut()` (cancela trabalho, limpa Keychain, revoga remoto).
- RED (`red-rt2`): exatamente as expectativas pretendidas falharam (6 issues de wiring em `AppDependenciesTests`, 2 de copy do mascote, 1 contrato de fonte do sign-out); `CoachExperienceContractTests.decodesNullMascotChangedAt` passou já no RED (tipo alterado antes do teste — declarado). GREEN: ver totais abaixo.
- Um teste novo (`timeZoneFollowsTheSession`) travou na primeira versão porque usava a fixture de lifetimes suspensos (`transition(to: nil)` espera `endSession` que a fixture só conclui sob comando); corrigido usando as dependências demo simples com `me` substituído. O processo travado foi encerrado por PID (sem afetar a cadeia de UI em curso).

### Resultados (fontes finais desta rodada; primário iPhone 17 Pro; uma invocação por classe salvo indicação)

- Unit: XCTest 34/0 (inclui os contratos de fonte novos); Swift Testing — App Dependencies, Coach Experience Contract, Mascot experience view model, Mascot presentation, Mobile coach persona repository, Mobile content cover byte stream (7 testes; caminho de timeout com 1 s), Mobile published content repository, Mobile registration repository, Mobile routine repository, Patient time zone store, LocalizationContractTests, Prompt 14 authenticated session ownership, Routine action model, Routine presentation: **0 falhas**. Session Lifecycle Coordinator: 1 falha de timing na execução encadeada logo após a cadeia de UI ("logout is marker-first and serializes a concurrent switch" — corrida logout/validate/switch; fontes intocadas; 1248/0/0 na regressão da V1) e **16/16 em uma invocação isolada de caracterização** — registrado, não somado.
- UI (fontes finais): Prompt13RoutineUITests 12/0, PremiumCoreSurfacesUITests 9/0, Prompt14TodayMascotUITests 9/0, PremiumContentProfileUITests 4/0 (uma primeira execução sob carga falhou: a folha de persona não apresentou em 5 s no demo en-US escuro; sem mudança de produto nesse caminho), Prompt14AccessibilityUITests 13/0 (primeira execução interrompida por SIGTERM ambiental aos 30 s, 0 testes julgados), PremiumConvergenceUITests 4/0 (primeira execução: runner de teste caiu antes de conectar, 0 testes). Registro (fontes da tarefa 1 + helpers): PremiumRegistrationUITests 3/0, Prompt13RegistrationUITests 21/0, BodyFlowUITests 18/0, Prompt13AccessibilityUITests 5/0.
- Release: BUILD SUCCEEDED (53 s), `codesign --verify --deep --strict` OK, `xcodebuild analyze` OK, scanner `--baseline 7ab3e657` **PASS** (`PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18/18`, `ALLOWED_TECHNICAL 237`, `displayName Performe AI`, `com.bodyflow.app`), testes do scanner OK; identifiers 169 → 170 (`profile.account.sign-out`); diff de assets vazio; greps de política 0 (`.shadow(`, `.blur(`, glass, `minimumScaleFactor`, `scrollEdgeEffect`, `UITabBarAppearance`, materiais); `dynamicTypeSize(` só em previews.
- Ambiente: o simulador secundário (iPhone 17) falhou duas vezes ao lançar o host de testes ("host is down / system shell crashed") e foi desligado; toda a verificação válida é do primário. Um `env6.sh` do scratchpad desapareceu durante a sessão e foi recriado com os mesmos valores.

### Pendências desta rodada

- `MealProposalEditorView` continua semeando o campo de kcal com o kcal calculado (vira `user_kcal` no servidor ao salvar) — não alterado (mexeria no editor da demonstração travada); follow-up.
- Peso: sem rota mobile (C5). Foto/áudio (C1), lembretes (C2), importação de plano (C3), plano a partir do Flow (C4 confirmado C), chave do provedor do Flow (D3), escopo Vercel (D2), credencial QA (D1), Apple/TestFlight (D4), documentos legais (D5), conteúdo da Biblioteca (D6), conta CI-3 (D7) — pacote único em `$SP/roberto-beta/approval-package-cd.md`.
- E2E de staging autenticado: continua dependendo da digitação da credencial QA pelo usuário (takeover) — passos 2–15 do §13 não executados.

### Regressão completa em `80b5dcca` (fontes finais desta operação; primário iPhone 17 Pro; uma invocação por classe)

Máquina sob carga externa alta durante a rodada (load de 1 min entre 12 e 48, de outras sessões/VMs; nada nosso). **Unit completo: 34 XCTest + 1259 Swift Testing (104 suítes) = 1293 / 0 / 0.** UI: 16 das 17 classes com 0 falhas (BodyFlow 18, FlowChat 12, PremiumAuthOnboarding 3, PremiumContentProfile 4, PremiumConvergence 4, PremiumCoreSurfaces 9, PremiumPerformance 4, PremiumRegistration 3, Prompt13Accessibility 5, Prompt13PlanProgressHistory 12, Prompt13Routine 12, Prompt13Today 11, Prompt14Accessibility 13, Prompt14Library 12, Prompt14Progress 5, Prompt14TodayMascot 9); `Prompt13RegistrationUITests` 21/1 — `testWorkoutControlsHavePersistentVisibleAndAccessibleLabels` (`Prompt13RegistrationUITests.swift:545`: `register.treino` não encontrado em 3 s após tocar a aba Registrar, sob load ≈ 20–48). A mesma classe rodou 21/0 às 23:5x nas mesmas fontes de Registrar e **21/0 em uma invocação isolada de caracterização** logo após a cadeia (361 s). Dois runners `xcodebuild` travaram no teardown após os testes terminarem e o simulador primário foi encontrado desligado duas vezes — ambiental, registrado.

FULL SUITE RESULT: unit 0 fail; UI 1 fail em 1 de 17 classes · ISOLATED CHARACTERIZATION: timing sob carga externa (classe 21/0) · FINAL VERIFIED STATE: **REGRESSION STATUS: PARTIALLY VERIFIED** (nenhuma execução completa única com 0 falhas; todas as 17 classes têm ≥1 invocação única limpa nas fontes finais).

### Build candidata (staging) e estado deixado

`$SP/DerivedDataStaging/…/BodyFlow.app` reconstruída a partir de `80b5dcca` com o xcconfig privado (RELEASE_STAGING_EXIT=0, 30 s; codesign OK; 21,1 MB; executável sha256 `d88915d8…`; versão 1.0 (1); três chaves de runtime expandidas, valores não impressos), instalada e aberta a frio no iPhone 17 Pro (`v6/e2e/v2-01-cold-launch-first-screen.png`, `settings.log`). Continua sendo um artefato de Simulator — não é build para o iPhone do Roberto. E2E autenticado em staging: passos 2–15 do §13 **não executados** (credencial QA exige takeover do usuário).

### Status ao fechar a operação V2

ROBERTO BETA CANDIDATE STATUS: **BLOCKED** (gates D: credencial QA/E2E, provedor do Flow, Apple/TestFlight, documentos legais, conteúdo da Biblioteca) · REGRESSION STATUS: PARTIALLY VERIFIED · PUBLIC BRAND STATUS: PARTIALLY VERIFIED (scanner PASS; superfícies Release com conta real não inspecionadas) · IOS INTEGRATION STATUS: PARTIAL — auth/onboarding/Flow(texto)/Hoje/Histórico/Plano/Progresso/registro por texto/hidratação/rotina/fuso/Biblioteca/capas/persona/mascote/sair da conta ligados ao BFF; foto/áudio, lembretes, importação de plano, plano via Flow e peso fora (C); E2E não executado · PRODUCTION STATUS: NOT DEPLOYED · USER VISUAL ACCEPTANCE: DEFERRED TO FINAL REVIEW · FLOW REAL PROVIDER SMOKE: BLOCKED_BY_PAID_PROVIDER_AUTHORIZATION · COST / ENVIRONMENT CLOSEOUT: COMPLETE (US$ 0 nesta operação; staging KEPT; nenhum recurso pago).

## Origem das calorias no editor de refeição — `RESOLVE_BETA_DESIGN_CHOICES_AND_FIX_KCAL_PROVENANCE_V1` (2026-09-27, não commitado)

Base `3e796f1560a0d6d01ae2129060a280bceb1fb55f`, worktree limpa e índice vazio na entrada; autoridade revalidada por blob (dossiê `d396bbd7…`/sha256 `f0dc6dcd…`, addendum `ef97a7be`, specs `edc15330`/`427243d6`/`09d76d65`, manifesto `9ca2587a`, scanner `7986173f`).

**Contrato lido antes de editar:** a entrada `user_kcal` é `z.number().nonnegative().max(20_000).optional()` (`apps/admin/src/lib/mobile-api/contracts.ts:133`) — ausente = o servidor calcula; `null` é recusado; presente = valor informado pelo paciente, que sobrepõe o cálculo e reescala P/C/F com `source: 'user_kcal'` (`packages/agent/src/meal-pipeline.ts:1501-1590`). O pending guarda `user_kcal`/`nutrition_source` (`registration-service.ts:71-112`), mas o DTO mobile só devolve `name, quantity_g, kcal, protein_g, carbs_g, fat_g` (`read-model.ts:39-54`).

**Defeito:** `MealProposalEditorSeed` preenchia o campo "Calorias informadas" com o `kcal` do servidor e o editor o reenviava como `user_kcal`; abrir e salvar sem tocar nas calorias transformava o cálculo oficial em valor "informado pelo paciente". `Decimal(string:)` também lia "180,5" como 180 e texto em branco como 0 (experimento executado: `Decimal(string: "180,5") -> 180`).

**RED** (build `kcal-red`, `MealProposalEditorDraftTests`, lógica extraída sem mudar comportamento para `MealProposalEditorDraft`): falharam exatamente os casos do defeito — salvar sem tocar (`user_kcal` 155,4), mudar outro campo, "180,5", branco → 0, entradas inválidas aceitas ou descartadas em silêncio (`abc`, `-5`, `20001`, `20000,5`, `1.234`, `1.234,5`, `12,3,4`, `,`, `1e3`, `12,25`) e JSON com `user_kcal`. "Proposta sem valor do servidor" já passava. **GREEN** (`kcal-green`, repetido em `kcal-final` nas fontes finais): 34 XCTest + 71 Swift Testing em 5 suítes (`MealProposalEditorDraftTests`, `RegistrationPresentationTests`, `MealRegistrationModelTests`, `RegistrationContractTests`, `LocalizationContractTests`) com 0 falhas.

**Correção** (`MealProposalEditorView.swift`, catálogo, testes): valor do servidor em linha somente leitura separada (`registration.proposal.edit.official-kcal`); campo "Calorias informadas por você (opcional)" vazio por padrão; `user_kcal` omitido (nunca `null`) quando vazio; aceita dígitos com um único separador (`,` ou `.`) e até uma casa decimal, 0…20 000; entrada inválida mostra erro (`registration.proposal.edit.user-kcal.invalid`) e desabilita Salvar; Voltar não grava. Cinco chaves novas/alteradas pt-BR/en.

**UI (uma invocação por classe, iPhone 17 Pro):** primeira rodada — o layout inicial (valor do servidor + rodapé dentro da primeira seção) empurrou o seletor de tipo de refeição para fora da área visível e quebrou duas asserções travadas (`Prompt13RegistrationUITests.testPendingMealEditReplacesProposal:86`, `PremiumRegistrationUITests.testProposalPrimaryConfirmAndLongTotalsAX:60`). Causa: a minha mudança. Correção: as duas primeiras seções voltaram à altura original e o valor do servidor foi para uma terceira seção; só o teste novo passou a rolar até ela (testes travados intocados). Rodada final: `Prompt13RegistrationUITests` 22/0 (inclui `testMealEditorKeepsServerCaloriesAndBackSavesNothing`), `PremiumRegistrationUITests` 3/0, `Prompt13AccessibilityUITests` 5/0.

**Gates nas fontes finais:** Release BUILD SUCCEEDED, `codesign --verify --deep --strict` OK, `xcodebuild analyze` OK, scanner PASS (`PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18`, `ALLOWED_TECHNICAL 237`), testes do scanner OK; identifiers 170 → 172; greps de política 0; diff de assets vazio; `git diff --check` limpo.

**Limitação registrada (não coberta):** como o DTO pendente não expõe `user_kcal`/`nutrition_source`, um valor manual anterior não é reconhecido ao reabrir o editor; salvar sem redigitá-lo volta ao cálculo oficial, o que a copy do editor declara. A correção definitiva exige expor esses campos no DTO (proposta no desenho `docs/superpowers/specs/2026-09-27-performe-ai-functional-beta-c1-c5-design.md`, §1.3 e §6). Achados relacionados não corrigidos: a edição envia só o primeiro item e apaga os demais; o campo de quantidade ainda trunca "140,5" para 140.

## Autorização das ferramentas, identidade das mensagens do Flow e integridade da refeição — `FIX_FLOW_AUTHORIZATION_AND_MEAL_INTEGRITY_V1` (2026-09-27)

**Entrada:** HEAD `3e796f1560a0d6d01ae2129060a280bceb1fb55f`, índice vazio. Lista exata do dirty na entrada (conferida, não inferida): 4 modificados (`MealProposalEditorView.swift`, `Localizable.xcstrings`, `Prompt13RegistrationUITests.swift`, esta evidência) e 2 não rastreados (`MealProposalEditorDraftTests.swift`, desenho C1–C5 com sha256 `3853984b…`). Hashes de entrada em `$SP/flowfix/entry-hashes.txt`. Nenhuma chamada paga, migration, deploy, configuração remota, dado real, conta CI-3 ou TestFlight nesta operação (US$ 0).

### S1 — autorização das ferramentas na execução (commit `026e6c2e`)

- **Defeito reproduzido** com respostas de provider roteirizadas (sem LLM): no canal `mobile_flow`, a allowlist de leitura só filtrava os schemas mostrados ao modelo; o laço de execução resolvia a chamada no registro completo. RED: `gera_treino` executou 3 vezes em iterações seguidas, `registra_refeicao` chegou a criar pending, uma ferramenta retirada pela configuração executou, e no WhatsApp uma ferramenta fora da lista configurada executou.
- **Correção:** `authorizeToolCall(name, filteredTools)` antes de qualquer efeito (parse de argumentos, pending adiado, `execute`, auditoria). Conjunto = canal ∩ configuração; o registro completo só distingue `tool_unknown` de `tool_not_authorized`. Recusa: resumo sem argumentos, nome saneado (`invalid_tool_name` fora de `[A-Za-z0-9_]{1,64}`), evento `pipeline.tool_call_denied` com `{tool, reason, channel}`, `retry_tool:false`. Afirmação falsa de gravação num canal sem ferramenta de escrita → retry de **retratação** (texto do mobile aponta o fluxo de confirmação do app; outros canais não citam app). Nudge de falsa duplicação só diz "registre TODOS" onde registrar é autorizado. Sem mudança de prompt como correção, sem `gera_*` na allowlist mobile, sem `propoe_plano_*`.
- **Testes:** `packages/agent/src/pipeline-tool-authorization.test.ts` (15) — recusa de `gera_treino`/`gera_dieta`/`registra_refeicao` com zero escritas, ferramenta autorizada executa, retirada pela configuração não executa, nome desconhecido/caixa alterada (`GERA_TREINO`)/`delete_user` controlados em chamadas repetidas e multi-iteração, telemetria sem argumentos, WhatsApp com lista, WhatsApp sem lista (semântica "todas" preservada), retratação por canal, nudge.
- **Revisão adversarial:** duas rodadas por subagente isolado (mesma família de modelo — **não** é revisão humana). Nenhum caminho de execução fora do conjunto autorizado. Achados corrigidos: MEDIUM de S2 (colisão `:assistant`), LOWs de nome cru no resumo, falta de retratação no mobile e retratação citando "app" em canal não-app.
- **Risco de implantação:** no WhatsApp, `allowed_tools` não vazio passa a limitar também a execução. Antes de qualquer deploy: ler (somente leitura) a configuração de produção; o formulário de admin não lista `reclassifica_refeicao`.

### S2 — identidade e idempotência das mensagens do Flow mobile (commit `026e6c2e`)

- **Defeito:** `messages(provider, provider_message_id)` é único para todos os usuários, e a `Idempotency-Key` só é única por usuário. Um segundo usuário com a mesma chave recebia 500; conflito de texto devolvia a resposta antiga.
- **Correção sem migration:** linhas novas usam `mobile_flow/<user_id>/<key>` e a resposta `…/assistant` (`/` está fora do charset da chave), com `user_id` do contexto autenticado. A `Idempotency-Key` pública não mudou; linhas legadas (chave pura, resposta `<key>:assistant`) são achadas só para o mesmo usuário e nunca reescritas. Mesma chave com texto diferente → 409 `idempotency_key_conflict`; entrada concorrente → 409 `idempotency_request_in_progress` sem chamar o Flow; resposta já gravada → replay; outra falha → turno `failed`.
- **Testes:** `flow-chat-service.test.ts` com tabela falsa que impõe o índice único global real (9 novos): A/B mesma chave, replay, conflito, concorrência, legado, `providerMessageId` passado ao agente, 23505 → `FlowMessageAlreadyStoredError`, colisão `abcdefgh:assistant` nas duas ordens, resposta de turno legado sob id com escopo. **Limitação:** isto é modelo unitário da tabela, não integração A/B autenticada — sem stack Supabase local nesta máquina (sem CLI; os containers em execução são de outro projeto).
- **Pendências S2 (não corrigidas):** o retry de uma entrada `failed` não passa pelo limite de 10/min; tags `[BTN:]`/`[LIST:]` geram resposta vazia no mobile; morte do processo em `maxDuration` deixa a entrada em `processing`; outros textos de prompt ainda citam ferramentas que o mobile não executa (são recusadas); em configuração parcial do WhatsApp o retry de fake-write pode citar ferramenta não autorizada (LOW).

### Integridade da refeição — proveniência de `user_kcal`, itens 2…N e quantidade

**DTO (aditivo, sem migration):** `safePendingItem` expõe `user_kcal` (entrada do paciente) e `nutrition_source` (fonte aplicada) de cada item, `null` quando ausentes (`apps/admin/src/lib/mobile-api/read-model.ts`; `docs/mobile/api-v1.md`). O contrato de mídia/source de C1 não foi adicionado.

**iOS:** `MealProposalItemSnapshot` decodifica os dois campos e distingue "chaves ausentes" (resposta antiga → origem `unknown`) de "chaves presentes com `null`" (cálculo oficial). O rascunho `MealProposalEditorDraft` concentra a regra; o parser `MealProposalNumberParser` lê por idioma.

| # | Cenário | Comportamento | Teste |
|---|---|---|---|
| 1 | Item calculado, salvar sem tocar | `user_kcal` omitido | `a calculated item saved untouched stays calculated` |
| 2 | Valor informado e aplicado (`nutrition_source = user_kcal`), salvar sem tocar | mesmo `user_kcal` reenviado | `a value the patient reported and the server applied is kept…` |
| 2b | Valor informado recusado pelo servidor (densidade) | não é reenviado como override | `a patient value the server refused is not re-sent…` |
| 3 | Mudar outro campo | origem do item preservada | `changing another field keeps the calorie origin…` |
| 4 | Valor digitado, com fração | `user_kcal` exato (pt-BR `180,5`/`12,25`, en `12.25`) | `a value the patient types is sent…` (10 casos) |
| 4b | Entrada inválida/ambígua/fora de faixa | erro explícito, Salvar desabilitado | `an unreadable, ambiguous or out-of-range calorie entry…` (12 casos) |
| 5 | Apagar um valor informado | bloqueia ("valor apagado"); volta ao cálculo só pela ação explícita "Usar cálculo do servidor" | `erasing a reported value does not silently return…`, `the explicit server-calculation action omits user_kcal…` |
| 5b | Mudar a quantidade mantendo valor informado | aviso para conferir | `keeping a reported value while changing the quantity…` |
| 6 | Resposta antiga sem proveniência | edição bloqueada com aviso; nada é presumido | `a response without calorie provenance blocks editing…`, `decodesMealItemCalorieProvenance` |
| I | Proposta com 3 itens, editar o primeiro | itens 2…N reenviados na ordem, quantidade exata e só o `user_kcal` aplicado | `editing the first item keeps every other item…` |
| Q | Quantidade `140,5` pt-BR / `140.5` en | 140,5 exato, nunca truncado; agrupada/ambígua/0/>9999/vazia recusada | `a quantity is read by the app language…` (6), `an ambiguous, grouped, empty or out-of-range quantity…` (7) |
| Q2 | Quantidade não tocada | enviada exatamente como veio do servidor, exibida no idioma | `an untouched quantity is shown…` |
| DTO | Proveniência de 3 itens / ausência | valores exatos / `null` | `read-model.test.ts`: `exposes each item calorie origin exactly as stored…`, `reports an absent origin as null…` |

A UI continua editando só o primeiro item (não ampliada). O aviso "deixe em branco" não autoriza apagar um valor anterior: apagar bloqueia o Salvar.

**RED → GREEN:** DTO (`$SP/flowfix/dto-red.log`): 3 falhas — o teste existente, que passa a esperar os dois campos, e os 2 novos. Editor (`$SP/flowfix/meal-red-unit.log`, 58 testes em 4 suítes): falharam itens 2…N perdidos (nomes, quantidades e `user_kcal` do teste de 3 itens), valor aplicado não preservado, apagar valor, mudar outro campo, quantidade truncada ou ambígua aceita, exibição por idioma e resposta sem proveniência. Já passavam no RED (declarado): item calculado sem tocar, valor recusado não reenviado, ação explícita de cálculo, casos de kcal inválida (fix da operação anterior) e a decodificação da proveniência (tipo escrito antes do teste). O teste do aviso ao mudar a quantidade entrou depois, direto no GREEN. GREEN nas fontes finais.

**Incidente de UI:** uma copy mais longa do aviso de primeiro item quebrou `PremiumRegistrationUITests:60` (seletor de tipo de refeição em AXXXL) — causa minha; copy revertida ao texto original, classe 3/0.

### Resultados nas fontes finais

- **Backend (worktree principal):** `@mpp/agent` 1083/1083, `@mpp/admin` 667/667, `@mpp/mobile-bff` 26/26, `tsc` limpo nos três. **Árvore exata do commit S1/S2 isolada:** agent 1083/1083, admin 665/665 (sem os 2 testes do DTO), mobile-bff 24/26 (os 2 testes de superfície de fonte falham só porque o `node_modules` da árvore isolada era symlink para fora da raiz — artefato do setup; worktree temporária removida).
- **iOS unit:** focado nas fontes finais (build 13:44) 34 XCTest + 81 Swift Testing (5 suítes) = 0 falhas. **Completo nas fontes finais** (depois da reversão da copy): 34 XCTest + 1277 Swift Testing (105 suítes) = **1311/0** (`$SP/logs/v6-v3-unit-flowfix-final-full.log`).
- **iOS UI (uma invocação por classe, iPhone 17 Pro):** `Prompt13RegistrationUITests` 22/0, `PremiumRegistrationUITests` 3/0, `Prompt13AccessibilityUITests` 4/1 — `testAccessibilityXXXLKeepsLabelsAndControlsReachable` (`:197`, `today.next-action`: frame fora do viewport na asserção logo após a revelação). Caracterização, que **não** conta como PASS da suíte:
  - invocação isolada da classe nas fontes finais, sob carga ≈ 6–18: falhou no mesmo teste em outro ponto (`:427`, o primeiro gesto não rolou nada — frame de `today.library` idêntico antes e depois);
  - linha de base com as fontes iOS de `026e6c2` (worktree temporária em DerivedData próprio, removida depois): classe 5/0;
  - A/B pré-declarado (só esse teste, 3 execuções por lado, intercaladas atual/base, todas reportadas), carga ≈ 3–7: **atual 3/3 PASS, base 3/3 PASS** (`$SP/flowfix/ab-a11y-summary.log`).
  - O diff não toca a tela Hoje: o catálogo só ganhou chaves `registration.editor.*` e mudou o valor de `registration.editor.user-kcal`; Hoje não usa `MealProposalItemSnapshot`.
  - Leitura: teste sensível a tempo sob carga externa, sem evidência de relação com este diff. A execução da classe na cadeia continua registrada como 4/1.
- **Release** BUILD SUCCEEDED (45 s), `codesign --verify --deep --strict` OK, `xcodebuild analyze` OK, scanner `--baseline 7ab3e657` **PASS** (`PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18`, `ALLOWED_TECHNICAL 237`, `displayName Performe AI`, `com.bodyflow.app`), testes do scanner OK; diff de assets vazio; `git diff --check` limpo; scan de segredos/PII no dirty: 0 ocorrências.
- **Ambiente:** carga externa alta (load 1 min entre 4 e 36, processos de outros projetos, não tocados). Um `xcodebuild` travou no teardown depois do resumo e foi encerrado pelo watchdog por PID.

### Status ao fechar a operação

FULL SUITE RESULT: backend 0 falhas; iOS unit 1311/0; UI do editor 22/0 e 3/0; `Prompt13AccessibilityUITests` 4/1 na cadeia. As 17 classes de UI **não** foram rodadas nesta operação. · ISOLATED CHARACTERIZATION: acima; não converte a falha. · FINAL VERIFIED STATE: **REGRESSION STATUS: PARTIALLY VERIFIED**.

**Consequência de implantação:** até o BFF com o DTO aditivo ser implantado, o app recebe itens sem proveniência e **bloqueia a edição** de propostas de refeição (comportamento seguro escolhido; confirmar e cancelar continuam). S1/S2 também só valem após deploy, que exige autorização explícita e leitura prévia da configuração de produção de `allowed_tools`.

**Contratos e migrations pendentes (nenhum aprovado ou implantado):**
- Contratos: `POST /meal-drafts`; `source` opcional em `propose`/`PATCH`; `source` no DTO pendente (`user_kcal`/`nutrition_source` feitos nesta operação); `POST /weight`; `GET /plan-drafts`, `GET/PATCH/DELETE /plan-drafts/:id`, `POST /plan-drafts/:id/confirm`; `POST /plan-imports`; `draft` opcional em `POST /flow/chat`; `POST /media` com `plan_document`/PDF e `duration_ms`.
- Migrations: M1 (`weight_measured_at` + `private.apply_weight_measurement` para todos os escritores); M2 (`plan_drafts` + RLS + RPCs + `private.replace_active_training_plan` + `prescriptions.source_request_key` + chaves estrangeiras compostas); M3 (`media_assets.kind` + bucket `plan-documents` + retenção proposta).
- Dependências: extração de texto de PDF no servidor; leitura de duração do contêiner de áudio antes do STT.
- S1/S2: sem migration.

**Pendências registradas:** retry de entrada `failed` fora do limite de 10/min; `[BTN:]`/`[LIST:]` vazios no mobile; entrada presa em `processing` se o processo morrer em `maxDuration`; textos de prompt citando ferramentas que o mobile recusa; S3 (identidade nos geradores, só pelo canal mobile); harness A/B autenticado local indisponível nesta máquina.

ROBERTO BETA CANDIDATE STATUS: **BLOCKED** · PRODUCTION STATUS: **NOT DEPLOYED** · custo desta operação US$ 0.

## Lembretes locais (C2) e lacunas de runtime do Flow — `IMPLEMENT_LOCAL_REMINDERS_AND_CLOSE_FLOW_RUNTIME_GAPS_V1` (2026-09-27)

**Entrada:** HEAD `51f999afcb1254b3de97c5877100d26c688f9a39` (pai `026e6c2e`, tree `062223a7`), índice vazio, único caminho sujo o desenho C1–C5 v1.1 não rastreado (sha256 `d6f0deb7…`). Autoridade revalidada por blob; sem `AGENTS.md`. Evidências da comparação anterior preservadas (`$SP/flowfix/ab-a11y-*`, `baseline-a11y.*`, `DD-baseline`, logs `char-a11y`/`meal2`); a worktree temporária da linha de base já tinha sido removida na operação anterior e não foi recriada. Nenhuma chamada paga, migration, deploy, leitura ou configuração remota, dado real, conta CI-3 ou TestFlight (US$ 0).

### Flow — lacunas de runtime (sem liberar capacidade nova)

| Item | Estado | Prova |
|---|---|---|
| 3.1 Limite nas retentativas | **RESOLVIDO** | Toda execução que pode chegar ao provider conta: primeira tentativa, retentativa de turno falho e continuação de turno que morreu antes do provider. Replay de resposta gravada não conta nem chama o provider. Recontagem depois do registro: numa rajada concorrente de chaves diferentes, nunca mais que 10 por minuto chegam ao provider (pode recusar a mais). Limite vigente inalterado (10/min). |
| 3.2 Tags `[BTN:]`/`[LIST:]` | **RESOLVIDO** | No canal mobile o texto é mantido, rótulos de opções viram linhas simples, tag malformada sai; sem payload interativo. Resposta sem texto visível → 502 `flow_provider_failed` tipado, turno `failed`, nenhuma linha de assistente. WhatsApp inalterado. Histórico esconde respostas vazias gravadas antes. |
| 3.3 Processamento interrompido | **RESOLVIDO sem schema** | Reuso do lease do ledger (10 min > `maxDuration` 300 s, travado em teste). Marcador `provider_started_at` antes do provider. Morreu antes do provider → continua uma vez, contado. Provider pode ter rodado (ou linha antiga sem marcadores) → não reexecuta; turno `failed` (`flow_turn_interrupted`) + 502; só uma retentativa explícita executa. Resposta já gravada → replay. CAS amarrado à tentativa (`attempt_started_at`/`request_id`). Erro ao gravar o marcador → turno `failed`, nunca preso. Queda abrupta modelada por promessas que nunca resolvem nos três pontos (antes do provider, depois do provider e antes da persistência, depois da persistência e antes do HTTP). |
| 3.4 S3 identidade dos geradores | **RESOLVIDO (caminho dormente)** | `assistantIdentity` só vem do canal `mobile_flow` decidido no servidor; prompts legados byte a byte iguais (sha256 travado); `gera_*` continuam recusados no mobile; nenhuma `propoe_plano_*`; nenhuma confirmação pelo LLM. |

- **RED → GREEN:** `$SP/rt/flow-red.log` (17 falhas: retentativa no limite executa; 12 retentativas = 12 chamadas; 2 retentativas concorrentes = 2 chamadas; resposta vazia = 201; turno interrompido reexecutado), `$SP/rt/agent-red.log` (9 falhas: tag válida = resposta vazia; malformada vaza; geradores ignoram o canal). Depois da revisão: `$SP/rt/flow-red2.log`, `$SP/rt/agent-red2.log`.
- **Teste existente alterado de propósito:** "reuses a failed inbound…" afirmava que a retentativa **não** passava pelo limite (codificava o defeito).
- **Revisão adversarial** (subagente isolado, mesma família de modelo — não é revisão humana): rodada 1 sem caminho de chamada sem contagem/duplicada em produção; 1 MEDIUM (limite não atômico entre chaves) e LOWs corrigidos nesta mesma operação. Rodada 2 (depois das correções): nenhum caminho para chamada sem contagem, acima de 10/min ou duplicada; LOWs corrigidos (erro de storage no pós-count/insert/claim/marcador devolve o turno como `failed`; regex tolerante a espaços e quebras, exigindo `=`, sem mexer em texto sem tag; replay de resposta vazia antiga → 502; contagem nula = erro). Conhecido e não corrigido: a recontagem é conservadora numa rajada concorrente (uma contagem atômica exige RPC nova — contrato mínimo no pacote de implantação); o ledger ainda repete, por 24 h, um 201 gravado com resposta vazia. Os testes da rodada 2 foram escritos junto com as correções (sem RED observado antes — declarado).
- **Limitação:** o adaptador Supabase (filtros `raw_payload->>…`) é coberto por teste de construção de query, não contra PostgREST real; A/B autenticado continua pendente (sem Supabase local).

### C2 — lembretes locais reais

- **Fontes (contratos existentes, só leitura):** `/supplements` e `/medications` (horários oficiais e ocorrência do dia), `/reminders` (regras do paciente; categorias suplemento/medicamento ignoradas), `/notification-preferences` (`push_enabled`, silêncio, limite diário, modo de preview), `/progress` (`next_reevaluation`, só para regra de reavaliação), fuso de `/me` por sessão. Nada é inventado: sem horário, frequência, item ou dose fora dessas fontes.
- **Planejador determinístico** (`Core/Reminders/LocalReminderPlanner.swift`): ocorrências individuais no fuso documentado do paciente; dia 0 = domingo; horário do buraco do horário de verão descartado; horário repetido resolve para o deslocamento depois da transição (como o PostgreSQL); `taken`/`skipped` do dia não lembra, `snoozed` lembra uma vez ao fim do adiamento; silêncio (início inclusivo, fim exclusivo, cruza meia-noite); limite diário por prioridade (medicamento > suplemento > refeição > hidratação > treino > reavaliação); orçamento de 60 com a renovação dentro (59 + 1), renovação 1 min após o último lembrete, fora do silêncio.
- **Agendamento** (`LocalReminderScheduler`, `SystemLocalNotificationCenter`): `UNCalendarNotificationTrigger` com componentes UTC completos (instante absoluto; imune a mudança de fuso do aparelho e à ambiguidade da volta do horário de verão — desvio consciente do "componentes no fuso do paciente" do desenho); diferença por identificador; relê as pendentes e só reporta como agendado o que o sistema guarda.
- **Isolamento:** identificador `pai.<8 hex de sha256(userID)>.<categoria>.<id do servidor>.<minuto>`; `userInfo` só com dono, tipo e id. Época síncrona capturada na criação do modelo da sessão; o limpador do ciclo de vida (composto com o do fuso) invalida a época e remove pendentes e entregues, confirmando por releitura; resposta tardia de sessão encerrada vira `superseded` e remove o que tinha adicionado; o fim do shell remove só os do próprio dono. Toque: só abre o destino para o dono da sessão (senão descarta sem abrir), nunca muta.
- **Permissão:** pedida só em "Ativar"; negada → estado explícito com atalho para Ajustes; sem provisional, time-sensitive ou crítico. **Privacidade:** padrão genérico na tela bloqueada; nome/dose só nos modos escolhidos pelo paciente; regras nunca mostram números de saúde; título ≤ 60, corpo ≤ 180, sem palavras bloqueadas (testado pt-BR/en).
- **UI mínima:** linha "Lembretes neste iPhone" no Perfil (só onde há fonte: conta real, ou cenário de teste) e uma tela com estado, cobertura ("até …"), não agendados por motivo, aviso de abrir o app, privacidade, e o aviso de que silenciar localmente não muda a rotina. Sem redesign de Perfil/Rotina.
- **Sincronização:** início da sessão (após `/me`), volta ao primeiro plano, mutações de rotina (invalidação), ação "Atualizar agora". Sem APNs, sem background, sem serviço remoto novo, sem entitlement ou chave de Info.plist.
- **Sem RED pré-implementação:** C2 é código novo, escrito junto com os testes (declarado).

- **Revisão adversarial do C2** (subagente isolado, mesma família — não humana): nenhum caminho para uma resposta tardia reagendar lembretes de sessão encerrada. Corrigidos: **HIGH** texto antigo nunca atualizado (agora todo lembrete planejado é reincluído e substitui o conteúdo); **HIGH** abrir o app sem rede apagava tudo (agora "fuso ainda não respondido" ≠ "sem fuso": mantém o agendado; a volta ao primeiro plano relê `/me` e ressincroniza, o que também segue mudança de fuso); **MEDIUM** limpeza não durável (marcador persistente, raiz sem sessão limpa tudo, início de sessão limpa outros donos mesmo sem ativação); LOWs de limpeza por época, estado após `superseded`, coalescência, permissão invisível = desligada, contagens no período coberto, data impossível, validade do toque (10 min), testes de DST de 30 min (Lord Howe) e à meia-noite (Santiago). Documentados, não corrigidos: renovação fora do limite diário; fontes lidas pelo lease atual (não pelo gate da sessão) — a época torna isso inofensivo.
- **Compilador:** `MobileContentCoverByteStreamTests.swift:226` passou a falhar ("sending closure captures self") só porque os testes novos mudaram a composição dos lotes de compilação (provado: sem os arquivos novos compila; o mesmo arquivo compilou no build anterior). Ajuste mecânico no teste (a `Task` captura uma caixa `Sendable`; corpo movido para `load()`), sem mudança de comportamento.

### Resultados finais

| Gate | Resultado |
|---|---|
| Agent / admin / mobile-bff | 1096/0, 697/0, 26/0; `tsc` limpo nos três |
| iOS unit completo (fontes finais) | 34 XCTest + 1329 Swift Testing (110 suítes) = **1363/0** |
| iOS UI pertinente (uma invocação por classe) | LocalReminders 4/0, PremiumContentProfile 4/0, Prompt14Accessibility 13/0, PremiumConvergence 4/0, BodyFlowUITests 18/0 |
| Release + `codesign --strict` + analyze + scanner | OK / OK / OK / PASS (`PUBLIC_LEAK 0`, `HISTORICAL_ASSET 18`, `ALLOWED_TECHNICAL 246`, assets idênticos); testes do scanner OK |
| Segredos/PII, `diff --check`, assets/Info.plist/projeto | 0 / limpo / sem diff |

- **Execuções falhas registradas (não somadas):** `LocalRemindersUITests` rodada 1 3/1 — o helper não rolava até uma linha de lista preguiçosa em AXXXL (defeito do teste, corrigido); cadeia anterior às correções da revisão 3/1 — a tela de lembretes não apareceu 5 s depois do toque na linha do Perfil sob carga 12–22, com o `.xcresult` incompleto porque o runner travou no teardown (encerrado por PID); essa cadeia foi interrompida por mim para recompilar. Na cadeia final, a classe rodou 4/0; o helper agora imprime a hierarquia se falhar. Sem caracterização isolada adicional.
- **Evidência de runtime:** no Simulator (iPhone 17 Pro, iOS 26.5), o centro de notificações real aceitou e devolveu na releitura 59 lembretes + a renovação. **iPhone físico: não executado** — `devicectl` não lista nenhum aparelho conectado; entrega real, conteúdo na tela bloqueada, persistência após reinício e mudança de fuso continuam pendentes. Simulator e protocolo falso não provam entrega no aparelho.
- **Cobertura:** focada; as 17 classes de UI não foram rodadas → **REGRESSION STATUS: PARTIALLY VERIFIED**.

### Commits desta operação

| Bloco | Commit | Pai | Tree |
|---|---|---|---|
| Flow runtime | `63241c3837eb2a44a23f5d4863c602824045f6df` | `51f999afcb1254b3de97c5877100d26c688f9a39` | `d729e10edf0ab12bee75abdc69d7d6b1a5922ced` |
| C2 lembretes | `18aacc8c9fbe5a81a804e01c4f707c1fa624f649` | `63241c3837eb2a44a23f5d4863c602824045f6df` | `7ee0feb1ae536f4c3dc3ecfc870b7c62af7ce816` |
| Documentação | este commit (evidência, pacote de implantação, desenho C1–C5 v1.1 byte a byte, sha256 `d6f0deb7…`) | | |

Registrar o desenho v1.1 no histórico **não** aprova M1, M2, M3 nem a dependência de PDF. Pacote do próximo gate: `docs/superpowers/plans/2026-09-27-performe-ai-deployment-gate-package.md`.

USER VISUAL ACCEPTANCE: PENDING FINAL REVIEW · REGRESSION STATUS: PARTIALLY VERIFIED · ROBERTO BETA CANDIDATE STATUS: **BLOCKED** · PRODUCTION STATUS: **NOT DEPLOYED** · custo desta operação US$ 0.

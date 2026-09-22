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

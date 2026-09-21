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

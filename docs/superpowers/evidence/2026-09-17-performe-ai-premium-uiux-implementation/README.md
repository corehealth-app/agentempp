# Performe AI premium UI/UX — Slice 0 local evidence

Date: 2026-09-17. Operation: `EXECUTE_PERFORME_AI_UIUX_SLICE0_FOUNDATION_V1`.
Scope: Batch 1, S0.1–S0.3 only. This document is not a staging, production,
whole-app accessibility, asset approval, or runtime LLM verification.

## Baseline and safety

- Host: `MacBook-Air-de-Eduardo.local`, Darwin 25.6 arm64, local development.
- Repository: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch: `codex/performe-ai-client-beta-flow-v1`; existing linked worktree reused.
- Starting HEAD: `7e1973940ed9edee7812abf955f91bf4873b89b3`.
- Starting parent: `7ab3e65771d172ad10ee42a7ab1d4e6edba2c775`.
- Starting tree: `2ede08df9fb6526e1dcd75d087c729f99fc2aed6`.
- Worktree/index initially clean; no scoped concurrent writer observed.
- Xcode 27.0 (`27A266a`); iPhone 17 Pro, iOS 26.5 simulator,
  `27291590-659D-4A29-8F45-CA5CA2D154F9`.
- Resource gate: PASS, 16 GiB RAM / approximately 74 GiB free disk;
  local simulator/build actions serialized. Cached public Swift packages were
  copied into this operation's private build directory; automatic resolution disabled.
- Private artifact root: `/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0`.
  Original result bundles/captures retained locally; no credentials or real data.
- No provider, staging, Production, CI-3, TestFlight, App Store, or LLM calls.
  No new branch/worktree/dependency/paid environment.

## Commands and result bundles

All test commands ran at the repository root. Common command prefix:

```sh
xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' \
  -derivedDataPath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/DerivedData-Debug \
  -clonedSourcePackagesDirPath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO
```

Each invocation adds its unique `-resultBundlePath <artifact-root>/<name>.xcresult`
and the selectors below. Counts distinguish test methods from parameterized executions.

| Bundle | Selectors under `BodyFlowTests/` | Observed result |
| --- | --- | --- |
| `baseline` | ScreenStateTests, ProgressPresentationTests, LocalizationContractTests | PASS: 32 methods / 42 executions, zero failed/skipped |
| `s0-1-red` | BodyFlowSemanticColorTests, BodyFlowComponentPolicyTests | RED: new token APIs missing; no destination/package/setup failure |
| `s0-1-green` | above plus ProgressPresentationTests, ScreenStateTests | Test-source compile failure: tuple type inference, not GREEN |
| `s0-1-green-typed` | above plus ProgressPresentationTests, ScreenStateTests | PASS: 28 methods / 34 executions, zero failed/skipped |
| `s0-2-red` | LocalizationContractTests, ScreenStateTests, BodyFlowComponentPolicyTests | RED: localized descriptor/component APIs missing |
| `s0-2-red-catalog` | same | RED: missing bilingual catalog entries and incorrect English fallback observed after components compiled |
| `s0-2-green` | above plus FeatureReadStateTests, FeatureActionLabelTests | PASS: 45 methods / 69 executions, zero failed/skipped |
| `s0-3-red` | BodyFlowPremiumRenderingTests | Initial harness compile failure also contained incorrect test symbol/argument names; not accepted alone as feature RED |
| `s0-3-red-corrected` | same | RED: native helper missing, as allowed by S0.3; destination/packages valid |
| `s0-3-green` | above plus BodyFlowComponentPolicyTests, BodyFlowSemanticColorTests | Attempt failed: empty native AX tree; 132 of 144 full-panel PNGs exportable, largest-font bitmap missing |
| `s0-3-green-native2` | same | Attempt failed: empty AX tree and explicit PNG-data unwrap detected the missing native bitmap |
| `s0-3-green-panels` | same | PASS: 11 methods / 11 executions; 432 exportable core PNGs |
| `s0-3-green-ax-expanded` | same | Failed expanded field AX assertion; native buttons passed. ImageRenderer field placeholder not accepted as a real field capture |
| `s0-3-green-scene` | same | Failed field AX assertion; UIKit capture revealed safe-area clipping, not accepted as final visual evidence |
| `s0-3-green-native-final` | same | CANCELED: operation-owned Xcode cleanup hung; interrupted only that process and operation-owned simulator. Incomplete bundle preserved, not GREEN |
| `s0-3-native-ax-child` | rendering AX selectors | Failed field AX assertion; unsupported child-hosting diagnostic, not accepted |
| `s0-3-native-field-diagnostic` | rendering AX/control selectors | Test-source variable-scope compile error, not GREEN |
| `s0-3-native-field-diagnostic-typed` | same | Diagnostic: both unstyled/styled field AX representations empty; inner 22-point glyph bounds are not the padded tap target. Button AX passed |
| `s0-3-green-verified-native` | rendering, policy, semantic colors | PASS: 13 methods / 13 executions; zero failed/skipped/expected failures/runtime warnings; 576 final native PNGs |
| `slice0-full-unit-regression` | `-only-testing:BodyFlowTests` | PASS: 1,160 tests / 1,360 executions including parameters; zero failed/skipped/expected failures/runtime warnings |

The S0.1 test type annotation preserves every assertion. S0.3 uses smaller native
panels rather than shrinking fonts/content or accepting unexportable captures.
The hosting accessibility fixture explicitly enables SwiftUI's public
`accessibilityEnabled` environment; no app-root/auth/Release bypass is added.
Final UIKit hosting temporarily adds the component host above the existing root
view in the test window, then removes it; it does not replace the app/test root
or create another window/scene. Actual native field captures use `drawHierarchy`,
not the unsupported ImageRenderer field placeholder. Public trait overrides
apply the real content-size category and color scheme to UIKit controls.

## Implemented contracts

- 23 additive semantic color roles, exact approved B2 warm-cream/deep-teal
  light/dark literals and opaque trait-resolved colors.
- Existing color APIs/aliases remain unchanged; existing card defaults to `.legacy`
  and preserves its old surface, outline, and composition. No owner migration.
- Approved native scalable typography, monospaced metric roles, 16/24 screen gutter;
  original spacing scale and 44-point minimum preserved.
- Radius 8/12/20; optional elevation constants; motion durations .20/.25, both zero
  with Reduce Motion. No new animation, timer, scale/opacity press feedback.
- The approved `largeTitle` premium role is explicitly bold. The previous
  plain-large-title assertion was changed to the stronger approved exact role;
  old `title`, `headline`, `body`, `callout`, `caption` aliases remain unchanged.
- Additive primary/secondary/tertiary/destructive button styles, environment-driven
  disabled state; native callbacks/role retained. Long labels wrap, no fixed height.
- Field modifier only styles the original control; no duplicate accessibility
  element, validation/binding/focus/keyboard/autofill ownership.
- Local presentation-language adapter reuses supported-language types and does
  not write persisted/server locale.
- Exactly 11 bilingual `state.*` catalog additions. Unavailable retains empty
  detail and no retry; empty remains separate. Retry closure/IDs unchanged.
- Stale banner uses opaque surface + semantic warning text/icon; original ID retained.
- Native UI-test helper compiles for future consumers; no new production test route.

## Contrast and native geometry

Automated independent-literal/native-trait checks cover all 23 roles in both themes.
58 approved pair/theme contrast assertions: 42 text/feedback/brand vs three
surfaces, six control-boundary checks, ten paired foreground/background checks.
Required thresholds: text and readable disabled pairs >= 4.5:1; control boundary >= 3:1.
Observed minimum approved text/surface ratio: 4.75 light / 4.99 dark;
control-boundary/surface: 4.03 light / 4.63 dark;
disabled text/fill: 4.74 light / 4.99 dark. Accent colors are not approved as
arbitrary foregrounds; these results apply only to the tested semantic pairs.

Rendering/hosting matrix: pt-BR/en-US × light/dark × 375/393/430 logical points ×
12 DynamicTypeSize values: xSmall, small, medium, large, xLarge, xxLarge, xxxLarge,
accessibility1–5. Hosting independently measures full-label text at the button's
usable width and requires the button to contain that height plus padding, rather
than trusting a screenshot. Card body plus padding and field minimum size are checked.
Increase Contrast trait resolution verifies opaque colors; Reduce Motion checks
both transition kinds at zero. No translucent/material fallback is introduced.

All 144 matrix conditions passed geometry assertions. Final export:
`<artifact-root>/captures-final/manifest.json`, 576 actual PNGs =
144 conditions × (three core ImageRenderer panels + one native UIKit field).
The manifest maps actual exported UUID filenames to component/theme/locale/
logical-width/Dynamic-Type settings; source baseline is the HEAD above.
Captures are component canvases, not whole-app Release/journey screenshots.

Root actually inspected 24 authoritative final PNGs: one core panel and one
native field for every DT0–11, cycling light/dark, pt-BR/en-US and 375/393/430.
Review A additionally inspected all 12 final field categories and two final
AX5 panel2 examples (plus 12 earlier core captures); Review B inspected 48
authoritative final PNGs: 24 fields at DT3/DT11 and 24 panel1/2 examples at DT11,
across both languages/themes and all widths. No clipping/truncation or incorrect
semantic pair observed. The 576-image inventory is not a claim that every image
was individually viewed or an automatically approved pixel golden.

Native button AX: all four roles at regular and AX5 expose one correctly labeled
button target, button trait and >=44-point frame; disabled adds notEnabled.
Fields: exactly one real UITextField/SecureField; keyboard/autofill, secure/enabled,
accessibility metadata and native font size preserved against the unstyled control;
external hosting geometry >=44. The test host returns an empty field AX tree for
both unstyled and styled controls. Baseline parity is only preservation evidence,
NOT proof of a complete field AX target/tree or VoiceOver accessibility.
Manual VoiceOver narration, real keyboard editing, tabs/composer, device-wide
accessibility, and future feature migrations are outside this local component gate.

## Build, analysis, reviews, and closeout

- Signed Release Simulator build: PASS, exit 0, `BUILD SUCCEEDED`,
  `slice0-release.xcresult`. Normal Xcode `Sign to Run Locally` signing;
  no signing bypass or DEVELOPMENT_TEAM change. Bundle ID remains `com.bodyflow.app`.
- `codesign --verify --deep --strict`: PASS, exit 0 on the Release app below.
- Native analyze: PASS, exit 0, `slice0-analyze.xcresult` reports succeeded,
  zero errors/analyzer warnings/compiler warnings in this incremental analyze.
- Swift typecheck: included in Debug test compilation and signed Release build.
  No separate SwiftLint configured/invented; changed-only source style/diff review
  and `git diff --check` are the applicable lint/whitespace checks.
- Review A — design system / visual semantics: source/native visual APPROVED,
  Critical 0 / Important 0 / Minor 0; final LOCAL one-commit verdict APPROVED
  after final README/gates readback. No actionable file:line finding.
- Review B — accessibility / regression: source/native visual APPROVED,
  Critical 0 / Important 0 / Minor 0; final LOCAL one-commit verdict APPROVED
  after independent result-bundle/codesign/README readback. No actionable
  file:line finding. Approval is not whole-app/VoiceOver/deploy approval.
- Allowlist/whitespace/secret/PII scans: PASS on tracked additions and full new
  files; exactly 21 authorized files, nine modified and twelve created.
  Zero provider-key/private-key/JWT/email/credential-assignment pattern matches;
  manual diff review found no secret, real QA user data or private config.
  Catalog comparison confirms exactly 11 additions and every previous entry unchanged.
  No asset/project-file changes or unexpected feature/backend file.
- Authorized integration choice: one LOCAL commit only, parent the starting HEAD,
  subject `refactor(ui): establish Performe AI semantic design tokens`.
  Create only after final review/scans; SHA/tree reported after commit, not
  self-embedded or amended. No push/PR/merge/deploy.
- Local closeout verified: no booted simulator and no operation-owned xcodebuild
  process remain after the completed gates. Existing worktree/branch and private
  result bundles/captures retained. No broad cleanup or paid infrastructure.

Release command (from repo root):

```sh
xcodebuild build -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' \
  -derivedDataPath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/DerivedData-s0 \
  -clonedSourcePackagesDirPath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/SourcePackages \
  -disableAutomaticPackageResolution \
  -resultBundlePath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/slice0-release.xcresult
codesign --verify --deep --strict \
  /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/DerivedData-s0/Build/Products/Release-iphonesimulator/BodyFlow.app
xcodebuild analyze -quiet -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' \
  -derivedDataPath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/DerivedData-Debug \
  -clonedSourcePackagesDirPath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/SourcePackages \
  -disableAutomaticPackageResolution \
  -resultBundlePath /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.uaWxf0/slice0-analyze.xcresult
```

### Exact file ledger

Paths below are relative to `apps/ios/BodyFlow/` unless marked `docs/`.

| Action | Files |
| --- | --- |
| MODIFY production | `BodyFlow/DesignSystem/BodyFlowColor.swift`, `BodyFlowTypography.swift`, `BodyFlowSpacing.swift`; `BodyFlow/DesignSystem/Components/ScreenStateView.swift`; `BodyFlow/Features/Shared/FeatureComponents.swift`, `StaleDataBanner.swift`; `BodyFlow/Resources/Localizable.xcstrings` |
| CREATE production | `BodyFlow/DesignSystem/BodyFlowRadius.swift`, `BodyFlowElevation.swift`, `BodyFlowMotion.swift`, `BodyFlowPresentationLanguage.swift`; `BodyFlow/DesignSystem/Components/BodyFlowButtonStyle.swift`, `BodyFlowFieldStyle.swift` |
| MODIFY tests | `BodyFlowTests/ScreenStateTests.swift`, `LocalizationContractTests.swift` |
| CREATE tests/support | `BodyFlowTests/BodyFlowSemanticColorTests.swift`, `BodyFlowComponentPolicyTests.swift`, `PremiumRenderingTestSupport.swift`, `BodyFlowPremiumRenderingTests.swift`; `BodyFlowUITests/PremiumUIUXUITestSupport.swift` |
| CREATE evidence | `docs/superpowers/evidence/2026-09-17-performe-ai-premium-uiux-implementation/README.md` (repo-relative) |

### Inherited warnings

Baseline build-results reports ten existing warnings, separate from new changes:
four UIKit main-actor coordinator warnings in WorkoutRegistrationView,
two in HydrationRegistrationView, a no-async `await` in SessionLifecycleCoordinator,
two redundant `#require` warnings in onboarding tests, and an unused return in
RegistrationSheetTaskCoordinatorTests. No cleanup of unrelated warning debt.
Simulator launch-metrics CAEvent messages are environment diagnostics, not app failures.
Release reports seven compiler warnings: the same seven production warnings
already observed in baseline; three test-only warnings do not apply to this build.
No new warning identified in changed files. The zero-warning incremental analyze
does not mean unrelated inherited warning debt has been corrected.

## Boundaries / next checkpoint

Brand asset approval remains pending; no logo, AppIcon, legacy asset, target,
module, bundle ID, signing/entitlement, backend, DTO, session, calculation,
persisted technical identifier, or telemetry migration.
Production: NOT DEPLOYED. Rebrand: PARTIAL. Final logo bytes: PENDING.
No remote resources changed; no paid temporary infrastructure created.
Do not begin Batch 2/Slice 1 or priority Slice 8 automatically.

## Batch 2 — explicitly authorized local execution, partial checkpoint

Authority: `EXECUTE_PERFORME_AI_UIUX_BATCH2_BRAND_FLOW_AUTH_V1`, separately
authorized after the Slice 0 checkpoint above. Same serial worktree; no new
branch/worktree, remote access, code-generation asset operation or provider call.

### Fresh baseline and host

- Host: MacBook-Air-de-Eduardo.local, Darwin 25.6 arm64, user eduardohenrique;
  LOCAL_DEVELOPMENT based on local source/Xcode workflow, not an assertion about
  any deployed filesystem. Xcode 27.0 (27A266a).
- Starting branch `codex/performe-ai-client-beta-flow-v1`; HEAD
  `5111b06edb5392f19d0e0c0f1de038b29b19a4c4`, parent
  `7e1973940ed9edee7812abf955f91bf4873b89b3`, tree
  `24f8e46c5545838a2015c6e84fb604f85b6604a2`; worktree/index clean,
  no concurrent source writer found.
- Local iPhone 17 Pro, iOS 26.5 simulator
  `27291590-659D-4A29-8F45-CA5CA2D154F9`; initially shutdown.
- Resource preflight: 16 GiB RAM, approximately 70 GiB free disk, 35% free
  memory-pressure reading; existing swap usage recorded, no material local
  build blocker. No production service/container operation.
- Private local artifacts/cache: `/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.0zGejW`
  (created with umask 077). Reused copies of locked local Swift package caches;
  no package version, lockfile or runtime change.
- `batch2-baseline.xcresult`: **PASS**, 1,160 logical tests / 1,360 executions,
  zero failed/skipped/expected failures. Build-results succeeded, zero errors,
  ten inherited warnings matching the Slice 0 list above. The console's
  `SwiftCompile ... exit code 0 ... no further output` diagnostic was investigated
  before edits: final xcresult has no build error or test failure. No source
  workaround or baseline retry was used.

### Brand infrastructure — S1.1 / documentary S1.2

- RED `slice1-red.xcresult`, exit 65: missing `PerformeAIBrandAsset` is the
  task-specific expected compilation failure; baseline had already passed.
- GREEN `slice1-green.xcresult`, exit 0: **12 logical tests / 50 executions**,
  zero failed/skipped/expected failures across PerformeAIBrandAssetTests,
  BodyFlowBrandAssetTests and BrandIdentityTests.
- Exact seven optional resource names resolve through `UIImage(named:in:compatibleWith:)`.
  Absence is explicitly tested as unavailable, not a failed asset import.
  Existing public text remains “Performe AI”; historical enum/catalog untouched.
- `assets/brand/performe-ai-public-v1/manifest.json`: family exact,
  `approvalStatus: pending`, empty `approvedFiles`/`publicCallsites`.
  `review.md` lists the exact plan §5 pending files/dimensions/rights and gates.
  No fake hash, author, license, date or approval. No imageset, PNG, PDF, SVG,
  AppIcon, splash image or historical byte change.
- BRAND_ASSET_APPROVAL_GATE: **PENDING_EXTERNAL_ASSETS**. Direction approved,
  final bytes pending; Slice 1 remains PARTIAL. This is not the Flow/Auth blocker.
- `slice1-release.xcresult`, normal Release Simulator build, exit 0: succeeded,
  zero build errors, seven inherited production warnings. Same non-fatal
  exit-code-0 console diagnostic as the fresh baseline; no xcresult error.
  No signing override, DevelopmentTeam/entitlement/bundle change or private
  staging configuration. `codesign --verify --deep --strict` on the resulting
  `DerivedData-Release/Build/Products/Release-iphonesimulator/BodyFlow.app`:
  **PASS**, exit 0.
- `batch2-partial-final-unit.xcresult`, exit 0: **1,163 logical tests / 1,375
  executions**, zero failed/skipped/expected failures; build-results succeeded
  with zero errors/warnings on this incremental action. Includes the unchanged
  server-authority/model/repository regression tests, not server-owned UI proof.
- `batch2-partial-analyze.xcresult`, exit 0: succeeded, zero analyzer findings,
  zero build errors/warnings on the incremental analyze. This does not correct
  the seven inherited Release compiler warnings recorded above.
- Explicit five-file source/documentation security scan: zero API-key/JWT/
  private-key/signed-URL/email/credential-assignment findings; manual diff
  review separately checks unintended scope. `git diff` against `7ab3e657`
  for historical brand/catalog/enum files is empty. No new artwork bytes.
- Independent Brand Infrastructure/evidence review: Critical 0 / Important 0 /
  Minor 0, **PASS** after final staged-diff/artifact readback. Reviewer independently
  confirmed GREEN/full regression, normal Release/strict codesign, analyze,
  whitespace check, scope and the remaining prerequisite incompatibility.
- UI tests/captures: NOT APPLICABLE to this infrastructure-only checkpoint:
  no view, catalog copy, image selection or public callsite changed.

### STOP_DOCUMENTED — required server-owned local UI fixture absent

This is an inspected plan/current-code incompatibility, **not** a failed brand
approval gate or a request to weaken UI assertions.

1. Approved S8.1 requires reaching the shell through the actual completed Debug
   journey with the current server-owned mock. S2.3 requires long authoritative
   QA document bodies, explicit required/optional actions and server completion;
   it expressly prohibits substituting the legacy consent fixture.
2. `App/AppDependencies.swift` Debug `.demo` onboarding branch currently selects
   `DemoOnboardingRepository` for the existing launch configurations.
3. `Core/Onboarding/DemoOnboardingRepository.swift` has no `loadState` or
   `completeOfficial` implementation. Inherited `OnboardingRepository.loadState`
   returns `completion.completed = false` and `requirements = .unavailable`.
   `AppFlowModel.restoreOnboarding` correctly treats that server state as
   authoritative over the authentication session's completed flag.
4. The existing synthetic-development consent path can potentially finish the
   local demo once. This is **not** a claim that the shell is universally
   unreachable. It does not supply server-owned long QA legal bodies/actions
   and re-restores as incomplete. Unit-private server mocks are not injected
   into the executable UI; no applicable launchable fixture was found.
5. Supplying the missing fixture needs a reviewed Debug/test-only onboarding
   repository/injection repair. Current strict allowlist permits AppDependencies
   changes **only** for Flow Debug selection and keeps onboarding repository/
   model/contracts unchanged. There is no in-scope substitute.

Independent read-only review confirmed this dataflow and the absence of an
in-scope existing alternative. No root completion bypass, legacy replacement,
model/repository edit, new legal QA set, remote access or optimistic gate was used.
Flow and Auth/onboarding implementation were **NOT STARTED**; their planned RED,
GREEN, UI, accessibility, captures and signed slice builds are **NOT VERIFIED**.
Slice 0 remains the previously verified contract, unchanged.

Next required authorization: a narrowly scoped reviewed Debug/test-only
server-owned onboarding fixture and its Debug injection/test allowlist, preserving
the Release injection, existing Core contracts, seven steps, explicit legal
actions and authoritative finish. Resume Batch 2 only after that prerequisite is
approved and verified. Batch 3 is not yet the next execution gate.

### Scope / closeout

Only S1.1 enum/test, new pending manifest/review and this evidence appendix are
eligible for the infrastructure commit. No Flow/Auth source changes, Slice 0
repair, dependency update or production deployment. Remote resources altered:
NONE. Real completions: 0. No paid temporary infrastructure created.
Rebrand PARTIAL; logo DIRECTION APPROVED / FINAL BYTES PENDING; Production NOT
DEPLOYED. Do not report the full Batch 2 success status.
Local closeout verified: `simctl list devices booted --json` has no booted
simulator; no remaining xcodebuild/swift-frontend/xctest processes were found.
No unrelated simulator/process was terminated; private artifacts/cache preserved.
COST / ENVIRONMENT CLOSEOUT: NOT APPLICABLE (no remote paid resource created).

Local commit scope is exactly these five files: PerformeAIBrandAsset.swift,
PerformeAIBrandAssetTests.swift, the new family's manifest.json/review.md and this
README appendix. Authorized subject:
`refactor(brand): prepare Performe AI asset infrastructure`.
The actual commit SHA/final worktree/index are verified after commit in the
execution report; no self-referential SHA is invented here. Only one Batch 2
infrastructure commit is intended, no Flow/Auth commit, amend, push, PR or merge.

## Subsequent approval — Debug server-owned onboarding fixture

The later strict fixture approval resolves the earlier prerequisite only after
the gates below. It does not amend the brand infrastructure commit or authorize
remote activity. Starting branch/worktree is unchanged; starting HEAD was
`cb223cff500b3960b37e397d6f8697618a54bdfb`, clean worktree and empty index.
Host: MacBook-Air-de-Eduardo.local, Darwin arm64, local Xcode development; no
claim that this filesystem is a deployed runtime. Existing linked worktree and
locked local package cache reused. Resource gate: PASS, 69 GiB free disk and
no material pressure observed before native builds.

### Proven fixture/injection paths and root cause

Paths located before editing, relative to `apps/ios/BodyFlow/`:

- `BodyFlow/Core/Onboarding/DemoOnboardingRepository.swift`: existing draft seed,
  storage and legacy finish, **read-only/unchanged**. No server-state override.
- `BodyFlow/Core/Onboarding/OnboardingRepository.swift` and
  `OnboardingModels.swift`: existing native protocol/DTOs, **unchanged**.
- `BodyFlow/Features/Onboarding/OnboardingFlowModel.swift`: existing real
  validator, explicit action and acknowledged finish gates, **unchanged**.
- `BodyFlow/Features/PreviewSupport/OnboardingPreviewSupport.swift`: new
  whole-file DEBUG local repository, QA bodies and private receipt cache.
- `BodyFlow/App/AppDependencies.swift`: only existing DEBUG `.demo` onboarding
  selection changed; real/unavailable selection and the Release branch unchanged.
- `BodyFlowTests/OnboardingPreviewSupportTests.swift`: new whole-file DEBUG
  behavioral suite; `BodyFlowTests/AppDependenciesTests.swift`: direct injection
  expectation now verifies actual state instead of the legacy concrete type.
- This Batch 2 evidence README: only documentation write in this checkpoint.

Old dependency inherited unavailable requirements and incomplete server state;
the actual model correctly rejected it. Authentication's completed fixture flag
is not authority and was not changed or used to synthesize completion.

### Contract, explicit finish and local lifecycle

The fixture reuses real `OnboardingLegalDocument`, `OnboardingDocumentAction`,
`OnboardingRequirements`, `OnboardingServerState`, completion/accepted-action
DTOs and `OnboardingCompletionAcknowledgement.matches`. It calls the unchanged
real step/completion validator with development consent unavailable. Legacy
`complete` remains unavailable; only a valid explicit official finish yields ACK.
Three deterministic clearly synthetic QA documents exercise acceptance,
acknowledgement and consent. Bodies exceed 1,000 UTF-8 bytes; SHA-256 is computed
from those exact bytes. Initial accepted actions are empty, completion false.
No legal draft is presented as a publication. No URL/network/storage-provider
client is used by the helper. Current real publication availability requires
all documents required; an available optional server document is not currently
supported. No optional contract/flag or server rule is invented to satisfy QA.
Existing client validation and optional field semantics remain unchanged.

Acknowledged snapshot/key/real ACK are cached only locally in DEBUG. A shared
actor arbitrates conflicting finishes without suspension; exact replay returns
the same ACK. Keychain-backed Debug launch uses a QA-only UserDefaults namespace
derived from the existing demo service. The helper does not write auth sessions
or credentials; it delegates draft load/save/clear to the unchanged existing
draft storage. No Keychain implementation/configuration is modified. Fresh and
preserve use the same existing keychain boundary.
Fresh reset removes only the exact user's QA receipt, once before operations;
the reset task is recorded before awaiting. Ordinary draft cleanup retains an
acknowledged finish and remains usable after logout. Memory-backed configurations
stay isolated. Unit services are unique test-owned namespaces to avoid parallel
suite interference; resolved launch/reset/storage semantics are unchanged.

### TDD and verification artifacts

Private native artifacts are in
`/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.0zGejW`.
They are not committed; no credentials were read or captured.

- `onboarding-fixture-red.xcresult`: accidental Swift Testing macro compilation
  problem, **not a behavioral RED**.
- `onboarding-fixture-red-behavior.xcresult`, exit 65: **3 executed / 3 failed**,
  no skips; missing current requirements/actions and actual model's legacy
  unavailable consent gate observed before implementation.
- `onboarding-fixture-green.xcresult`: first implementation passed new behavior
  but an existing relaunch test exposed signed-out cleanup regression. Fixed
  only in the DEBUG helper, not by weakening that test.
- `onboarding-fixture-review-red.xcresult`: provider recreation and signed-out
  cleanup failures characterized before receipt/cleanup repair.
- `onboarding-fixture-green-final.xcresult`: accidental actor-isolation compile
  issue in new test, **not GREEN/RED behavioral evidence**; repaired with await.
- `onboarding-fixture-reset-red.xcresult`: individual selector executed zero
  tests, **discarded as verification evidence**.
- `onboarding-fixture-reset-red-executed.xcresult`, exit 65: **8 executed,
  7 passed / 1 failed**, no skips. Actual fresh-to-preserve lost the acknowledged
  finish (three assertion issues). All tests finished before Xcode's automatic
  Simulator diagnostic collector stalled; only its confirmed task-owned child
  collector was terminated, preserving the completed failed result bundle.
- `onboarding-fixture-green-regression.xcresult`, exit 0: **146 logical tests /
  172 executions**, zero failures/skips/expected failures/runtime warnings.
  Native build-results succeeded, zero compiler errors/warnings in this action.
  Includes all nine new fixture behaviors and existing onboarding models,
  presentation, completion, real mobile repository, dependencies, Prompt 14
  preview/support/Release boundary and authenticated ownership regression.
- `onboarding-fixture-prompt13-regression.xcresult`, exit 0: **7 tests / 7
  executions**, zero failures/skips/expected failures/runtime warnings; preserves
  exact Prompt 13 launch selection, deterministic contexts and Release exclusion.
- `onboarding-fixture-release.xcresult`: normal signed Release Simulator build,
  exit 0, build-results succeeded, zero errors and seven inherited warnings.
  `codesign --verify --deep --strict` on the resulting Release app: PASS, exit 0.
  No signing/configuration override, source package/lockfile update or Release
  dependency modification. Compiled entire app scan for all new QA document
  identifiers/body markers/helper/cache types: zero matches (`rg` exit 1).
  Release-visible `AppDependencies.swift` source after selecting its five existing
  `#if DEBUG`/`#else` blocks is byte-identical to parent; SHA-256
  `2b69a3aeba03a20211e708dd25611900962537cdbc387940f2213e91359fc4e1`.
- Final FIXTURE CONTRACT REVIEW: **PASS**, Critical 0 / Important 0 / Minor 0.
  Reviewer independently read staged scope/evidence, GREEN/regression/extra
  Prompt 13 results, signed Release/strict codesign, compiled marker absence and
  parent equality of Release-visible source. Changed-source secret scan and
  whitespace check: zero findings. Exact isolated local commit is now eligible.

Only the five fixture/injection/test/evidence files above may be committed,
subject `test(onboarding): align debug fixture with server-owned consent`,
parent `cb223cff500b3960b37e397d6f8697618a54bdfb`. No self-referential SHA is
invented in this pre-commit evidence; execution report verifies the actual SHA.
No view/Core/model/auth/session/Keychain/backend/provider/Release branch edit.
No push, PR, merge, deploy or remote mutation. Real completions: 0.
No paid infrastructure created; cost/environment closeout NOT APPLICABLE.
After all gates and a clean local commit, resume Slice 8 then Slice 2 under
the prior approved Batch 2 plan, without repeating Slice 1 infrastructure.

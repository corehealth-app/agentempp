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

## Batch 2 — Slice 8 local execution diagnostics

Fixture checkpoint committed as `1cc0a2d09957f19f044c27d6de044b903f9320fc`,
parent `cb223cff500b3960b37e397d6f8697618a54bdfb`; worktree/index verified clean
before automatically resuming Flow. Brand infrastructure is not repeated.
This section preserves failed/partial attempts; it is not final Slice 8 acceptance.

### Flow scope and preserved contracts

Only `Features/FlowChat/FlowChatView.swift`, the new pure
`FlowChatPresentation.swift`, the whole-DEBUG
`Features/PreviewSupport/FlowChatPreviewSupport.swift`, existing DEBUG Flow
selection in `AppDependencies.swift`, scoped `flow.*` catalog entries,
`FlowChatPresentationTests.swift`, `FlowChatPreviewSupportTests.swift`,
`FlowChatUITests.swift` and this evidence are touched. The model, Core DTOs,
real repository/API, session, storage, cancellation, idempotency, history limit,
retry, launch configuration, shared design system and authenticated shell are
unchanged. Auth/onboarding presentation has not started at this checkpoint.

Exactly eight local scenarios: empty, loading, processing, response, error,
offline, longHistory and retryOnce. They use the existing native protocol/DTOs.
The approved finite two-second mock observation delay is DEBUG-only, not an SLA
or provider-latency optimization. No additional event gate/delay/scenario,
real request, completion, streaming renderer, Markdown parser or progress timer.
Explicit local retry retains the original model's same idempotency key;
mock exact replay is rechecked after actor suspension. Response content is
native selectable plain Text, including literal Markdown characters.

Public presentation uses Flow / Performe AI and distinguishes user/assistant.
Pending copy is truthful combined sending-and-waiting; cancellation explicitly
does not promise that a remote operation was canceled. Submission preserves
the existing trimmed 4,000-character rule. Reader policy follows the end or
own send, not a reader in older history. Latest navigation is explicit/local.
Reduce Motion consumes the existing root environment plus system preference.
Reply announcements are brief, completed-only, once per new message, suppressed
for a historical reader; no forced accessibility focus.

### Behavioral RED and rejected evidence

All bundles remain under the same private `run.0zGejW` root above.

- `s8-copy-red.xcresult`: behavioral RED, one logical/two parameterized failed
  executions on old pending/cancel/processing copy.
- `s8-composer-ui-red.xcresult`: behavioral RED, one failed native journey after
  all seven actual onboarding steps/explicit official QA finish; old Send was
  enabled for 4,001 characters. Keyboard screenshot retained privately.
- `s8-policies-and-mocks-red.xcresult`: behavioral RED, eight logical/ten
  executions; three policy/localization tests failed while all four mock
  behaviors passed. Old unconditional follow/animation and missing role copy
  were characterized. No compile/setup error is used as RED.
- `s8-reader-ui-red.xcresult`: failed off-screen seed setup, not accepted as a
  reader-policy behavioral RED.
- `s8-unit-green-1.xcresult`: accidental test lookup signature compile failure,
  not GREEN; corrected to existing `AppLocalization.string(_:for:)` API.
- `s8-unit-green-2.xcresult`: intermediate unit PASS, 55 logical/57 executions,
  no failures/skips/runtime warnings. Includes dependencies, four actual
  FlowChatModel tests, presentation policies and four DEBUG mock behaviors.
- `s8-native-ui-green-1.xcresult`: rejected as final gate, six native tests,
  two passed/four failed. Manual historical reading/Latest and explicit retry/
  local response/reopen passed. Composer failed in old onboarding setup;
  cancellation reused a Send coordinate after control replacement; the loading
  assertion polled after the finite delay. These are harness failures, not
  silently treated as production fixes. Incoming response during a native
  three-second drag/hold did steal history and hide Latest: valid reader RED.

The reader defect came from observing only a Boolean end-of-scroll result.
After keyboard resize it was already false, so a subsequent false-to-false
manual offset movement did not update reader intent. The view now observes the
full viewport (offset/content/container/inset); tests retain the true two-second
mock and a real native gesture, without a parallel provider event API.

### Native capture findings that require a fresh gate

Official xcresult attachment export: `s8-ui-1-attachments/manifest.json` maps
native PNG/hierarchy UUIDs to each test/capture. Root and read-only reviewer
actually inspected regular/AX keyboard and historical before/after samples.
The nominal dark capture was visibly light; `simctl ui <owned-id> appearance`
confirmed light. `-AppleInterfaceStyle Dark` alone is not theme proof on this
runtime. Light/Dark matrices are split into separate host-controlled runs and
assert the existing DEBUG Today accessibility value before entering Flow.
No launch configuration/helper/root theme override is added to fake evidence.

The old AX icon-plus-text Send Label overflowed its measured frame and keyboard.
The Flow consumer now uses plain action Text at accessibility sizes; the shared
button style is immutable. A native raster readback is still required rather
than trusting `exists` or a 44-point frame. The AX empty capture was visually
blank despite existing accessibility content; a new initial-readable-content
assertion characterizes that defect before repair.

The onboarding setup scroll container retains its offset between steps.
The native helper now scrolls toward the control's actual frame, both directions,
instead of repeatedly searching only below the current position. It still
requires real selected traits, all three initially unchecked required actions,
explicit current completion and acknowledged Today transition; no bypass.

Historical latency baseline stays 7,334 ms pipeline / 8.657 s input-to-output
persistence interval. Neither is tap-to-visible latency, an SLA, or a new
measurement in these mock UI tests. No backend/LLM optimization is performed.
VoiceOver manual narration remains NOT VERIFIED pending actual execution.
Real completions: 0. No provider access, remote mutation, paid environment,
push, PR, merge or deploy. Final acceptance/commit awaits fresh gates below.

### Subsequent native diagnostics — not final acceptance

- `s8-native-ui-green-2.xcresult`: 84 logical/91 executions, three native
  failures. All 77 unit logical/84 executions passed. Native composer limit,
  cancel/reopen, manual history/Latest and explicit retry passed. Reduce Motion
  failed onboarding setup with a one-direction helper. The incoming-reader
  pixel-distance equality was invalid: keyboard reflow/native physics and a
  changing footer do not equal finger distance. Geometry remains diagnostic;
  the exact QA35 reader identity, actionable Latest, hidden new reply and
  explicit Latest-to-reply transition remain required assertions. No larger
  tolerance/delay/provider event gate was substituted.
- Its giant response/AX failure hierarchy had a 32,556-point content extent
  but no accessible body at the lower viewport, supporting the lazy-culling
  diagnosis rather than proving paint from hierarchy alone. The Flow renderer
  now uses eager VStack for received
  history, preserving whole native Text/selection/roles/IDs. The model requests
  50 messages and the mobile repository limits the request; the model does NOT
  universally clamp any array returned by a provider. No fake VM hard cap is
  claimed. The bounded QA fixture has 40 messages. Memory/rendering tradeoff is
  local presentation correctness, not backend latency optimization.
- `s8-empty-ax-red.xcresult`: valid one-test behavioral RED, initial readable
  role-line was not hittable after a real seven-step finish/ACK. Kept native
  PNG/hierarchy were exported with **all** attachments to
  `s8-empty-ax-red-all-attachments`; only-failures export did not include those
  keepAlways captures and is not used as visual proof. Empty history now has
  conditional initial top anchoring; nonempty history retains end anchoring.
- `s8-native-light-green-3.xcresult`: 86 logical/93 executions, 83/90 passed,
  three failures, no skips/expected failures/runtime warnings. Empty AX,
  composer limit, cancel/reopen, reader/Latest, incoming-reader policy and
  retry/reopen passed. The new quantitative AX test exposed genuine keyboard
  compression: actual Send height 68 points versus its multiline label. The
  footer now reserves intrinsic vertical size/priority; no font reduction,
  shared DS change or new UI padding. `s8-release-5.xcresult` built this source:
  exit 0, zero build errors/seven inherited warnings, strict codesign exit 0.
  Release-visible dependency selection equals Flow parent, normalized SHA-256
  `ef46534ea32b691c4ef59f4511f20159df5ff3e10567bce07d327a316958e592`.
- A separate false metric failure was less than one logical point: UIKit
  paragraph bounds with external leading/whole-point rounding are not SwiftUI
  layout equality. `s8-ax-footer-green-1.xcresult` rejected that obsolete oracle
  despite the new intrinsic footer height 149.333; it is NOT accepted GREEN.
  The reviewed guard now measures a **minimum glyph-painting footprint** with
  native semantic preferred headline/semibold, real inner width, device glyph
  bounds and physical-pixel rounding. Existing 1-point tolerance/24-point DS
  padding are not increased. Metrics retain typographic/leading/reconstructed
  font comparison, weight/name/style/point size, glyph minY/maxY and scale;
  the identical formula must quantitatively reject the preserved 68-point RED.
  This guard alone is not raster proof: entire-field/button containment above
  the actual keyboard/native navigation and fresh screenshots are also required.
- Reduce Motion's old role39-at-tail oracle was spatially invalid for a bubble
  taller than its AX viewport. `s8-reduce-motion-live-diagnostic.png` actually
  showed the final body painted, with the role above the viewport. The reviewed
  native test now proves the exact role reachable bidirectionally, navigates
  older history, then Latest yields the exact complete body39 label hittable/
  intersecting the real history viewport and Latest absent; keepAlways raster
  evidence remains required. No `exists`-only replacement or shorter QA text.
- Flow setup reuses only a finish acknowledged by the current serial XCTest
  process. Its first launch still performs all seven steps/unchecked required
  actions/explicit finish and Today ACK. A missing preserved receipt fails;
  higher-priority reset arguments force that actual fresh journey again.
  No automatic completion/fallback/Root or launch-configuration change.

Fresh full Light/Dark, final source/raster review and commit remain pending.

### Slice 8 final local gates

The final native gate corrected two test-oracle defects without weakening the
product contract. A fixed `QA35` pre-gesture assumption was invalid across
native scroll settling; XCTest activity timing also proved that even a nominal
short drag takes longer than the exact two-second fixture response. The final
reader test starts with Cancel visible, holds one real native gesture across the
unchanged response, and then requires exact `QA35` visibility, an actionable
Latest control, the new reply off-screen, and explicit Latest navigation to the
reply. `s8-reader-green-1789671969.xcresult`: one passed, zero failures/skips or
runtime warnings. Raster captures show QA35 in the historical viewport before
Latest and the exact local reply only after Latest.

Dark appearance now uses the same native `XCUIDevice.shared.appearance` seam as
the existing accessibility tests, while retaining the in-app `colorScheme`
readback. Launch arguments alone are not accepted as proof.
`s8-dark-green-1789672049.xcresult` and
`s8-light-green-1789672293.xcresult`: each complete matrix passed, zero
failures/skips/runtime warnings. Their kept captures were exported to
`s8-dark-final-attachments` and `s8-light-final-attachments`; actual PNGs for
empty, keyboard, processing, long raw response, error/offline and long history
were inspected, not inferred from hierarchy.

That visual review found one real untested defect: at AccessibilityXXXL an
error/offline card existed but its recovery content started outside the
readable viewport because all message-empty conversations initially anchored at
the top. `s8-recovery-red-1789672607.xcresult` is the valid behavioral RED:
`The real error copy must start inside the readable viewport`. The production
fix is limited to initial anchoring: a healthy empty conversation remains top;
error/offline starts at the end. No model/repository/retry/network behavior
changed. `s8-recovery-green-1789672835.xcresult`: both error and offline at
AccessibilityXXXL passed in one test, zero failures/skips/runtime warnings;
real error copy and 44-point-plus retry were visible/reachable. Kept PNG and AX
hierarchy were exported to `s8-recovery-green-attachments` and inspected.

Aggregate current Flow evidence is 77 passing logical tests across the seven
required unit/contract suites plus every native UI behavior in the now
12-test Flow class: the nine unaffected UI tests passed in the full prior gate;
reader, true dark appearance, current light matrix and the newly added
error/offline recovery gate passed focused after diagnosis. No test deletion,
skip, broader tolerance, provider-event hook, fixture-delay change or runtime
fallback was used. The only Xcode messages are inherited debugger snapshot
lookup diagnostics; result summaries have zero runtime warnings.

The global Performe AI shell title consumes substantial space at AXXXXL; Shell
composition belongs to the explicitly deferred Slice 3 and is not edited here.
Within S8, conversation content remains natively scrollable, whole action
labels are painted, composer controls stay above the actual keyboard, errors and
retry are reachable, and history is not stolen. Full manual VoiceOver narration
remains **NOT VERIFIED**; native AX hierarchy/order/targets and Dynamic Type
XXXL are locally verified. Real completions: 0. Remote resources altered: none.

Final signed simulator Release from the recovery-anchor source:
`s8-release-6.xcresult` status **succeeded**, error count 0, warning count 7
(the same inherited auth/register concurrency warnings outside the Flow diff),
analyzer warnings 0. `codesign --verify --deep --strict` exited 0 for
`BodyFlow.app` (`com.bodyflow.app`, simulator ad-hoc signature). Compiled bundle
scan found zero `QA_REPLY_VISIBLE`, `qa-seed-`, `ui-testing-flow-`, synthetic
onboarding-copy or QA legal-key markers. `git diff --check` passed; tracked and
new-source scans found no secret, credential, signed URL, provider URL, PII or
new network client. DEBUG scenario selection is confined to the existing
`#if DEBUG` dependency branch and the entire fixture file is DEBUG-wrapped;
Release dependency boundary tests are included in the 77-test pass.

The final source was re-run after the anchoring fix in
`s8-unit-final-1789673258.xcresult`: 77 logical / 84 executed tests passed
across all seven required suites, zero failures/skips/expected failures/runtime
warnings. Final independent **Flow UI/behavior review: PASS**, Critical 0 /
Important 0 / Minor 0. The reviewer confirmed the exact nine-path allowlist,
unchanged real model/Core/auth/session/persistence/idempotency/retry/cancel
contracts, whole-file DEBUG fixture boundary, localized public Flow identity,
security scan, conditional healthy-empty versus recovery anchoring, and honest
VoiceOver limitation. The final Release 6 success above closes the reviewer's
only operational condition. Slice 8 is eligible for its exact local commit;
there is no push, PR, merge, deploy or remote access.

## Batch 2 — Slice 2 Auth and Onboarding final local gates

Slice 2 started from clean HEAD
`d6d101b62802ca4fa898177301a1e15eeeed41f7`, after the local Flow commit.
The scope is presentation-only: the existing authentication/session services,
seven-step onboarding model, server-owned requirements, exact document bodies,
version/hash/action semantics, authoritative acknowledgement and Release
dependency selection remain unchanged. No iOS target, bundle, entitlement,
provider, backend, persisted technical identifier or navigation contract changed.

Auth now uses the approved premium hierarchy, semantic fields/messages and
localized pt-BR/en-US copy for sign-in, sign-up, confirmation and neutral account
recovery. Secure-entry/focus/autofill semantics remain native. A compact header
while editing keeps the original submit control reachable without overlaying or
duplicating it. Splash remains text-based on deep teal; no pending final logo is
fabricated. Onboarding retains exactly seven steps and real progress, adds the
approved Flow public styling, natural wrapping and 44-point legal actions, and
keeps every legal body and explicit server action authoritative. The synthetic
DEBUG consent surface uses separate development localization keys and is never
presented as an official publication.

### TDD, localization and native UI evidence

- `s2-copy-red-1789673539.xcresult` / `s2-copy-red2-1789673609.xcresult`:
  task-specific RED on missing premium/localized presentation contracts.
- `s2-copy-green2-1789674096.xcresult`: focused Auth/Onboarding presentation
  GREEN, 18 tests passed after the implementation.
- `s2-review-red3-1789678146.xcresult`: two real missing-catalog assertions
  failed before the final localization repair; no setup failure used as RED.
- `s2-review-green-1789678329.xcresult`: the same 18 focused tests passed,
  including all validation/error/announcement/development-consent catalog keys.
- `batch2-full-unit-final-1789678556.xcresult`: full unit gate **PASS**,
  1,182 logical tests / 1,396 parameterized executions, zero failures/skips/
  expected failures/runtime warnings.
- `s2-ui-final-green.xcresult`: final native matrix **PASS**, 9/9 tests,
  zero failures/skips/runtime warnings. It covers the six neighboring auth/
  onboarding journeys plus three premium gates: pt-BR light Accessibility XXXL
  hierarchy, en-US dark validation/recovery, and the full server-owned consent
  action/completion journey at Accessibility XXXL.

The simulator's privacy alert rejected automated paste into secure fields after
the system strong-password sheet. The test helper now detects that exact failure,
falls back to single-character native entry and still requires the exact secure
character count. `s2-ui-helper-fix.xcresult` first proved the complete signup and
seven-step journey; the final 9-test matrix then passed. No assertion, password
rule, fixture delay or product behavior was weakened. Manual VoiceOver narration
remains **NOT VERIFIED**; native accessibility order/targets and Dynamic Type are
locally verified, not a claim of whole-app accessibility certification.

### Build, review and boundaries

- `s2-release-final.xcresult`: normal signed Release Simulator build **PASS**,
  exit 0; seven inherited production concurrency warnings outside this slice.
  `codesign --verify --deep --strict` on the Release `BodyFlow.app`: **PASS**.
- `s2-analyze-final.xcresult`: native analyze **PASS**, exit 0.
- `Localizable.xcstrings` parses as JSON; `git diff --check` and scoped
  secret/credential scans pass before commit. No real user/provider data exists
  in the diff or private local result bundles.
- Final independent Auth/Onboarding review: **PASS**, Critical 0 / Important 0.
  Findings about synthetic consent labeling and partially hard-coded localized
  errors/accessibility strings were corrected and re-reviewed.
- Real LLM completions: 0. Remote resources altered: NONE. No push, PR, merge,
  deployment, staging, Production, OpenRouter, Supabase, Vercel or CI-3 access.
  No paid environment was created; cost/environment closeout NOT APPLICABLE.

The exact local integration subject is
`refactor(ui): refine authentication and onboarding`, with parent
`d6d101b62802ca4fa898177301a1e15eeeed41f7`. Its resulting SHA and final clean
worktree/index are reported after commit; this evidence is intentionally not
self-amended. Slice 2 is locally verified. Slice 1 remains partial because final
brand bytes are pending external approval. Batch 3 is the next workstream and is
not started here.

## Batch 3 — Slice 3 Shell and Today local gates

Slice 3 started from clean HEAD
`b8621f1c2adb1a9038ae77654be4a414b4b1ee7d`, tree
`004843b391150a214c9c8ef70894d84183d05582`, on the existing
`codex/performe-ai-client-beta-flow-v1` worktree. Host
`MacBook-Air-de-Eduardo.local` is local development. The private artifact root is
`/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/batch3.3TV7zC`.
No provider, remote environment, paid resource or real completion was used.

### TDD and implementation

- Initial S3 RED proved the additive English tab-title contract was absent and,
  after compilation, `TodayPresentationTests` failed the required real-metric
  ordering. Raw values/order stayed asserted. `s3-red.xcresult` and the corrected
  focused RED were retained locally.
- Five existing tab cases/raw values/technical IDs and five independent
  `NavigationStack` paths remain unchanged. `AppTab.title(for:)` uses the existing
  presentation-language/localization adapters for pt-BR/en-US. The single root
  textual anchor uses `BrandIdentity.productName`; no asset or AppIcon changed.
- Today now presents authoritative context/freshness, food remaining and daily
  balance as separate descriptors, then protein/hydration before pending data.
  Nil values render localized unavailability; no score, step count, habit metric,
  user greeting, total or protocol calculation was added. Flow and Library entry
  remain independent of a successful Today payload.
- The first signed UI attempt reached onboarding because the existing Debug
  `startsWithCompletedFixture` authentication state had no corresponding
  server-shaped onboarding receipt. A behavioral RED was added. The repair is
  wholly `#if DEBUG`: only explicitly completed synthetic launches preload one
  deterministic receipt built from the existing DTOs and current synthetic QA
  documents. Fresh-auth tests still sign in as incomplete; Release selection,
  real auth/session services and contracts remain unchanged.
- `s3-fixture-green-v2.xcresult`: **PASS**, 10/10 tests, zero failures/skips.
- `s3-focused-unit-final.xcresult`: **PASS**, 107 logical tests / 119 executions
  including parameters, zero failures/skips. Covered all required Shell/Today/
  recommendations/invalidation/session-ownership suites plus the Debug boundary.
- The first 23-test signed UI matrix found one real precision edge: the 44-point
  refresh target surfaced as 43.999999999999986 points. The visual target became
  45 points without changing its callback/ID. The isolated signed regression
  passed in `s3-refresh-hit-target-green.xcresult`.
- `s3-focused-ui-final-v2.xcresult`: **PASS**, 23/23 tests, zero failures/skips.
  It covers `Prompt13TodayUITests`, `Prompt14TodayMascotUITests` and
  `PremiumCoreSurfacesUITests`, including loaded/incomplete/error/offline/stale/
  unavailable, Flow access, recommendations/Library, pt-BR/en-US, light/dark and
  Accessibility XXXL. No pre-existing assertion was weakened.

### Visual, Release and security evidence

The final UI bundle exported 20 retained screenshot/hierarchy attachments to
`<artifact-root>/s3-ui-attachments`. Root inspected the Shell/Flow en-US light
Accessibility XXXL capture, Today pt-BR light Accessibility XXXL capture and
unavailable-to-Flow capture. The five tabs remain visible/localized, one root
brand anchor is present, core controls remain reachable, long text wraps and no
clipping/truncation was observed in the inspected frames. XCTest additionally
asserts >=44-point relevant controls and metric-before-pending hierarchy. This is
native UI evidence, not full manual VoiceOver narration; **VOICEOVER MANUAL
STATUS: NOT FULLY VERIFIED**.

Normal signed Release Simulator build under `<artifact-root>/s3-release-derived`
passed with exit 0. `codesign --verify --deep --strict` passed for
`Release-iphonesimulator/BodyFlow.app`; identifier remains `com.bodyflow.app`,
signature is local ad hoc. Seven inherited production concurrency warnings match
the documented Slice 0 baseline and occur outside new S3 lines. `git diff --check`
and catalog JSON parsing pass. Scoped security review found no provider key,
private key, signed URL, real credential, real user data, asset change, backend
change or remote access. A pre-existing test constructs a synthetic JWT with the
literal role name `service_role`; it is not a credential and is outside this diff.

Independent review initially found one Important client-copy gap: pending titles,
the incomplete-day message and energy accessibility values stayed in Portuguese
under en-US. `s3-review-localization-red.xcresult` captured the focused compile
RED before those language-aware APIs existed. The implementation now retains raw
server kind/status/value fields and localizes only client-owned presentation.
`s3-review-localization-green.xcresult` passed the focused presentation suite,
including exact pt-BR/en-US semantics. The signed native en-US Accessibility XXXL
journey then passed in `s3-review-localization-ui.xcresult`, asserting the two
proposal labels, confirmation fallback and both energy accessibility values.
Focused re-review: **PASS**, Critical 0 / Important 0; no new regression and no
server-owned value was rewritten.

The exact local integration subject is `refactor(ui): refine Today experience`.
Its resulting SHA and post-commit clean worktree/index are reported after commit;
this evidence is intentionally not self-amended. Slice 4 has not started at this
checkpoint.

## Batch 3 — Slice 4 Register and global local gates

Slice 4 started only after the Slice 3 local commit
`3b59c6efa3c1ac384ee19e7e284f1551c1bfdc2d`; worktree and index were clean.
The same local host, branch, simulator and private artifact root documented in
Slice 3 were reused serially. No provider, remote environment, paid resource,
real user, media permission, media upload or real completion was used.

### Capability truthfulness and preserved contracts

- Register keeps the existing server-authoritative proposal, receipt, captured
  key, retry, cancellation and idempotency ownership. No nutrition total,
  correction, hydration percentage, workout protocol or official energy value is
  calculated on iOS. Optional nil values remain absent rather than becoming zero.
- Photo and Audio are explicitly labeled as local samples; the sheet states that
  the demonstration has no media permission or upload. Text keeps the existing
  draft, focus, analyze guard, operation callback and error retention. No camera,
  microphone, picker, upload, offline queue or fake analysis phase was added.
- Meal proposal hierarchy is received items/quantities, optional official totals,
  received warnings/provenance/expiry, then Confirm primary, Edit first item
  secondary and Cancel tertiary. The editor remains first-item-only and displays
  that limit. The original proposal and receipt state machines are unchanged.
- Explicit `RegistrationMetricUnit` presentation prevents kcal from being shown
  as grams; raw server decimal values are only locale-formatted. Meal type and
  workout intensity get bilingual presentation labels while their enum/raw payload
  values remain unchanged. Workout energy is explicitly labeled as an estimate.
- Hydration remains ml and weight remains kg. Existing parsing, Decimal/date/
  patient-timezone semantics, callbacks and coordinator ownership are unchanged.
  UIKit fields, pickers, segmented controls and buttons now use native fitting
  with the prior 48-point minimum as a floor, multiline labels and Dynamic Type;
  no fixed visual height is used as a ceiling.
- The mandatory Slice 4 Accessibility XXXL regression found that `today.history`
  could not be reached within the controlled gesture budget because secondary
  block/mascot content preceded it. The only cross-slice source adjustment moves
  that existing link before those secondary sections; its route, label, ID and
  data are unchanged. The global Today suites pass on the final ordering.
- The only cross-slice test adjustment aligns the existing `--ui-testing`
  dependency expectation with Slice 3's intentionally completed server-shaped
  receipt. Fresh-auth remains a separate incomplete launch path; no Release,
  auth/session or onboarding production behavior changed.

### TDD, regression and native visual evidence

- `s4-1-red.xcresult`: expected source compile RED for the new bilingual
  capability-copy API; `s4-copy-green.xcresult`: focused GREEN after the minimal
  implementation.
- `s4-review-b-red.xcresult`: review RED for missing explicit metric units and
  localized meal-type/intensity presentation. `s4-review-b-green-v3.xcresult`:
  **PASS**, 8/8 tests after the fixes.
- `s4-focused-unit-final-v2.xcresult`: **PASS**, 78 logical tests / 81
  parameterized executions, zero failures/skips/expected failures. It includes
  registration presentation/sheet/task coordinator, meal/demo/workout/hydration/
  weight models, dependencies and preserved callback/idempotency contracts.
- Early native runs exposed three concrete defects: a 42.5688-point Detect target,
  unreachable Today history at Accessibility XXXL and the changed legacy hydration
  unavailable wording. The product/test repairs were respectively a >=44-point
  label frame, the ordering adjustment above and restoration of `Indisponível`.
  Isolated bundles `s4-hit-target-green-v2.xcresult`,
  `s4-today-history-green-v3.xcresult`, `s4-hydration-copy-green.xcresult` and
  `s4-premium-ui-review-b-green.xcresult` all pass.
- `s4-focused-ui-final-v4.xcresult`: **PASS**, 29/29 tests, zero failures/skips/
  runtime warnings. It covers proposal/edit/confirm/cancel/receipt/error/retry/
  unavailable/expired, meal capture/text, workout/hydration/weight, keyboard,
  pt-BR/en-US, light/dark, regular/Accessibility XXXL, native targets and Reduce
  Motion. Existing Prompt 13 assertions were not removed or weakened.
- Final attachments were exported to
  `<artifact-root>/s4-ui-attachments-final`. Root inspected the en-US light capture
  choice sheet, en-US dark Accessibility XXXL proposal and en-US light
  Accessibility XXXL workout form. Labels wrap, the local-sample boundary is
  explicit, official values/units remain legible and the oversized forms remain
  scrollable. This inspection is native raster evidence, not manual VoiceOver.

### Release, reviews, global regression and closeout

- `s4-release-final-v3.xcresult`: normal signed Release Simulator build **PASS**,
  exit 0, zero errors and one inherited `SessionLifecycleCoordinator` unnecessary
  `await` warning outside the diff. New UIKit bridge concurrency warnings were
  removed. `codesign --verify --deep --strict` on the Release app: **PASS**.
- Review B initially reported Critical 0 / Important 2: kcal depended on a label
  comparison and the editor exposed Portuguese raw display values under English.
  Both were fixed without changing payloads. Final Register review: **PASS**,
  Critical 0 / Important 0.
- Review C independently checked Slice 0/2/8, auth/session, Flow, Design System,
  Release/DEBUG boundaries and the two documented cross-slice regressions. Final
  regression review: **PASS**, Critical 0 / Important 0. Slice 3 Review A remains
  **PASS**, Critical 0 / Important 0 after its localization repair.
- The first parallel full-unit attempt surfaced the stale dependency expectation
  above plus an existing scheduling-sensitive cancellation assertion under load.
  The final required serial gate was not hidden or retried in parallel:
  `batch3-full-unit-final-v2.xcresult` **PASS**, 1,188 logical tests / 1,402
  parameterized executions, zero failures/skips/expected failures/runtime warnings.
- `batch3-global-ui-final.xcresult`: **PASS**, 26/26 executions over
  Prompt13Today, Prompt14TodayMascot, PremiumCoreSurfaces and
  PremiumRegistration on final source. Combined with the final Slice 4 matrix,
  Batch 3 records 55 passing UI executions / 52 distinct tests; the three
  PremiumRegistration tests were intentionally repeated in the global gate.
  Global screenshots were exported to `<artifact-root>/global-ui-attachments-final`;
  root also inspected the final Today Accessibility XXXL hierarchy.
- `batch3-analyze-final.xcresult`: native analyze **PASS**, zero errors, compiler
  warnings or analyzer warnings. Swift compilation/typecheck is covered by the
  tests, analyze and signed Release builds. No separate SwiftLint is configured.
- `git diff --check`, catalog JSON parsing, strict allowlist and scoped security
  scan pass. Zero provider key, JWT/private key, credential/password assignment,
  signed URL, real email/PII or real user data finding. No asset/AppIcon/logo/
  wordmark/splash/historical BodyFlow asset, backend, dependency or project-file
  change. BRAND_ASSET_APPROVAL_GATE remains **PENDING_EXTERNAL_ASSETS**.
- Manual VoiceOver narration was not executed: **VOICEOVER MANUAL STATUS: NOT
  FULLY VERIFIED**. Native accessibility hierarchy/order/labels/selected states,
  >=44-point targets, units, Dynamic Type XXXL and Reduce Motion are locally
  covered; this is not whole-app accessibility certification.
- Exact local Slice 4 subject: `refactor(ui): refine registration experience`.
  Its resulting SHA and final clean worktree/index are reported after commit; no
  self-amend is used. There is no push, PR, merge, deployment or remote access.
  Real completions: 0. Remote resources altered: NONE. Private xcresults and
  captures are retained. Simulator/process shutdown is verified after commit.
  COST / ENVIRONMENT CLOSEOUT: NOT APPLICABLE.

## Batch 4 — Slice 5 Plan local gate

Slice 5 started from clean HEAD
`aa6489f16bb4e3b35450871f242acc7ca196164f`, parent
`3b59c6efa3c1ac384ee19e7e284f1551c1bfdc2d`, tree
`e1f73ce3fb820a320a6cc772526f9e713d20fa3d`, on the existing
`codex/performe-ai-client-beta-flow-v1` worktree. Host
`MacBook-Air-de-Eduardo.local` is local development. Xcode 27.0 and the existing
iPhone 17 Pro / iOS 26.5 simulator
`27291590-659D-4A29-8F45-CA5CA2D154F9` were reused serially. Private artifacts,
locked package-cache clone, logs, result bundles and captures are retained under
`/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/batch4.JIqMw6`.
No provider, remote environment, paid resource or real completion was used.

### TDD, contract preservation and presentation

- S5 RED compiled against the requested `PlanPresentation(snapshot:language:)`
  interface and failed because that language-aware initializer did not exist.
  The failure was task-specific, not a destination/package/setup failure.
- The additive initializer defaults to pt-BR and localizes only client-owned
  labels and date presentation. Server-owned plan type, equipment, prescription
  type, notes and IDs remain byte-for-byte presentation values from the snapshot.
- UTC date meaning is preserved while formatting as `dd/MM/yyyy` in pt-BR and
  `MM/dd/yyyy` in en-US. Optional fields remain absent; literal zero days/version
  remain visible. No local active/expired inference, exercise, menu, goal,
  recommendation or weekly-progress calculation was added.
- Training and each received nutrition prescription use one semantic
  `BodyFlowCard(surface: .card)`. Type/days/equipment/notes precede a secondary
  plan-details group containing generated date, validity and version. The
  existing detail route and reload behavior remain intact; provider task,
  invalidation and cancellation ownership are unchanged.
- `s5-final-green-rerun.log` and
  `S5FinalDerivedData/Logs/Test/Test-BodyFlow-2026.09.18_09-25-03--0300.xcresult`:
  **PASS**, 39 distinct tests, zero failures/skips/expected failures/runtime
  warnings. Selectors cover PlanPresentation, PlanViewModel,
  PlanProgressContract, Prompt13 Plan/Progress/History and
  PremiumCoreSurfaces. The first consolidated attempt ended without a terminal
  test result when its high-volume console stream was interrupted; no assertion
  failure was recorded. The exact gate was rerun with output redirected and
  completed successfully.

### Native visual, Release and review evidence

The final UI bundle exports four regular-size locale/theme Plan captures plus an
en-US dark AccessibilityXXXL detail capture under
`<artifact-root>/S5FinalAttachments2`. Root inspected pt-BR light, en-US dark and
en-US dark AccessibilityXXXL captures. Group hierarchy, secondary metadata,
semantic contrast and locale-specific dates are visible; long authoritative
Portuguese fixture values remain untranslated under English as required. The
oversized detail remains scrollable and retains readable content. XCTest also
asserts the loaded groups, absence of invented `Active`, detail navigation and
reload. This is native screenshot/accessibility-tree evidence, not complete
manual VoiceOver narration: **VOICEOVER MANUAL STATUS: NOT FULLY VERIFIED**.

`s5-release-final.xcresult`: normal signed Release Simulator build **PASS**, exit
0, identifier `com.bodyflow.app`; `codesign --verify --deep --strict`: **PASS**.
The only compiler warning is the inherited unnecessary `await` in
`SessionLifecycleCoordinator`, outside this slice; the AppIntents metadata skip
is a tool diagnostic. Swift compilation/typecheck is covered by the focused
tests and Release build. No separate SwiftLint is configured.

Primary-agent structured review of hierarchy, localization, UTC date contract,
nil/zero semantics, server-owned values, reload ownership, allowlist and prior
slice compatibility: **PASS**, Critical 0 / Important 0. This is explicitly not
an independent reviewer claim. Catalog JSON parsing, `git diff --check`, exact
allowlist and scoped secret/PII scans are required immediately before the local
commit. Exact local subject: `refactor(ui): refine Plan experience`, with parent
`aa6489f16bb4e3b35450871f242acc7ca196164f`; resulting SHA/tree and clean state
are reported after commit without amending this evidence.

No logo/AppIcon/wordmark/splash/historical asset, backend, DTO, API, dependency,
project file, signing configuration or remote resource changed. Real
completions: 0. BRAND_ASSET_APPROVAL_GATE remains **PENDING_EXTERNAL_ASSETS**.
No push, PR, merge, deployment, staging, Production, Supabase, Vercel,
OpenRouter or CI-3 access occurred. Slice 6 starts only after the verified local
Slice 5 commit and a clean worktree/index.

## Batch 4 — Slice 6 Progress local gate

Slice 6 started only after the verified Slice 5 commit
`a82bc63ffb435c8223181678aab2f05cde0d24e1`, tree
`fcfe7440f8245b2d8ba77bc119430c3f5becefb7`, with clean worktree and index.
The same local host, simulator, private artifact root and locked packages above
were reused serially. No new branch/worktree, provider, remote resource, paid
environment or real completion was used.

### TDD, hierarchy and preserved official data

- `s6-red.log`: task-specific RED on the missing additive
  `ProgressPresentation(snapshot:language:)` interface. The destination and
  locked packages resolved; compilation failed exactly on the new language
  argument rather than an environment error.
- `s6-unit-green.log`: **PASS**, 16/16 ProgressPresentation tests. pt-BR/en-US
  integer, decimal and UTC date formatting pass; singular/plural day copy,
  nil-versus-zero, calm zero-streak action and positional duplicate-medal IDs
  remain covered. Badge text/IDs and every numeric source value remain unchanged.
- The loaded hierarchy is current weight/body composition, official consistency,
  XP/level/completed blocks/reported deficit, earned medals/missions boundary,
  dates, then the existing Block 7,700 route. Nil uses `Não disponível` /
  `Not available`; literal zero remains visible. The Today restart still writes
  only `.today` and now uses the primary action semantic pair rather than
  achievement gold. Achievement color is limited to earned-medal presentation.
- No historical series, 7D/4W/3M selector, chart, local delta, Performance Score,
  XP formula, forecast, goal, protocol or new query was added. The inspected
  models contain no historical dataset. Block percentage remains `Int?`; the UI
  emits exactly the supplied integer plus `%`, omits the row when nil, and does
  not clamp, normalize or recompute it from calories.
- `s6-focused-final.log` and
  `S6FinalDerivedData/Logs/Test/Test-BodyFlow-2026.09.18_09-47-31--0300.xcresult`:
  **PASS**, 52 distinct tests, zero failures/skips/expected failures/runtime
  warnings. Selectors cover ProgressPresentation, ProgressViewModel,
  Block7700Presentation, PlanProgressContract, Prompt14Progress and all
  PremiumCoreSurfaces.

The first three-test native run passed the missing-values and locale/theme
matrix cases but failed a test-only identifier query for the combined
`FixtureMetricRow`; the visible official value was not the failure. An explicit
outer identifier remained absent on a second isolated reproduction because of
SwiftUI combined accessibility semantics. It was removed instead of shipping a
test-only product API. The final isolated and 52-test gates assert the real
`Reported percentage` plus `32%` content and pass. The operation-owned
xcodebuild processes that remained after those failed test sessions were stopped
by exact PID only; no unrelated process or artifact was removed.

### Native visual, Release, analyze and review evidence

Final attachments are under `<artifact-root>/S6FinalAttachments`: four regular
pt-BR/en-US × light/dark Progress captures, one en-US dark AccessibilityXXXL
missing-measurements capture, one en-US light official-percentage detail, plus
their accessibility trees. Root inspected the pt-BR light, en-US dark,
AccessibilityXXXL nil and Block detail captures. Cards reflow, values remain
legible, missing data is not rendered as zero, and the oversized viewport stays
scrollable. `32%`, `2,500 kcal`, `7,700 kcal`, `10,200 kcal`, `available` and
`user_progress` are received fixture values; server strings stay untranslated.
This is native screenshot/tree evidence, not complete manual VoiceOver:
**VOICEOVER MANUAL STATUS: NOT FULLY VERIFIED**.

`s6-release-final.xcresult`: normal signed Release Simulator build **PASS**, exit
0; identifier `com.bodyflow.app`; `codesign --verify --deep --strict`: **PASS**.
`s6-analyze.xcresult`: native analyze **PASS**, exit 0. Both report the inherited
unnecessary `await` warning in `SessionLifecycleCoordinator`, outside this diff;
the AppIntents metadata skip is a tool diagnostic. Swift typecheck is covered by
tests, Release and analyze; no separate SwiftLint is configured.

Primary-agent structured review of official value flow, optional/zero behavior,
percentage source, absence of invented history/formulas, localization,
accessibility hierarchy, allowlist and compatibility with prior slices:
**PASS**, Critical 0 / Important 0. This is explicitly not an independent
reviewer claim. Catalog JSON parsing, whitespace, exact allowlist and scoped
secret/PII scans are required immediately before commit. Exact local subject:
`refactor(ui): refine Progress experience`, parent
`a82bc63ffb435c8223181678aab2f05cde0d24e1`; resulting SHA/tree and final Batch 4
regressions are reported after commit without amending this evidence.

No asset, backend, DTO/API/model, dependency, project file, signing configuration
or remote resource changed. Real completions: 0. Remote resources altered: NONE.
BRAND_ASSET_APPROVAL_GATE remains **PENDING_EXTERNAL_ASSETS**. No push, PR, merge,
deployment, staging, Production, Supabase, Vercel, OpenRouter, CI-3, TestFlight or
App Store operation occurred.

## Batch 5 — Slice 7 Profile, content, history, routine and mascot local gate

Slice 7 started from commit `15d4428a1ec2175356eedf911c6765f7392520ee`,
whose parent is the verified Slice 6 commit
`a82bc63ffb435c8223181678aab2f05cde0d24e1`; the worktree and index were clean.
Execution remained on the local Apple Silicon Mac and iPhone 17 Pro iOS 26.5
Simulator `27291590-659D-4A29-8F45-CA5CA2D154F9`. Private evidence is retained
under `/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/batch5.ntQhh3`.
No new branch, worktree, dependency, provider, remote resource, paid environment
or real completion was used.

### S7.1 — Profile and server-owned persona

- `s7-1-red.log` records the expected TDD RED before the localized Profile
  presentation contract existed. `s7-1-final-green.log` records the final
  focused GREEN in `S71FinalDerivedData`; `s7-1-release.xcresult` records the
  signed Release Simulator gate.
- Profile now presents a premium identity/persona hierarchy with localized
  pt-BR/en-US copy, server-provided persona options and selection, explicit save
  and cancel affordances, minimum tap targets and accessibility identifiers.
  Accessibility text sizes use xmark/checkmark toolbar symbols with localized
  labels so actions remain fully visible; regular sizes retain localized text.
- Existing user/session ownership, load/save/cancel semantics, unavailable
  states and server option validation remain unchanged. The preferences entry is
  explicitly disclosed as a local demonstration; no account, notification or
  unsupported server capability was invented.

### S7.2 — Library and published content

- `s7-2-red.log` records the expected RED. `s7-2-focused-unit.log`,
  `s7-2-focused-ui-final3.log` and `s7-2-gate.log` record the focused GREEN and
  native UI gate.
- Library and article surfaces now use localized filters, category/status copy,
  semantic cards, reading metadata, saved/completed state and clearer empty,
  pagination and recovery presentation. At accessibility text sizes the All and
  Saved filters stack vertically rather than compressing.
- Feed/request ownership, cursor behavior, impressions/opened events, authorized
  cover relay/cache, expiration recovery, Markdown parsing and external-link
  policy remain in their existing owners. `ContentCoverView.swift`,
  `ContentDetailViewModel.swift` and the Markdown implementation were not
  modified. Authoritative article/category values not covered by a known UI
  localization remain literal rather than being rewritten.

### S7.3 — Read-only history, routine and mascot

- `s7-3-red.xcresult` records the expected TDD RED.
  `s7-3-focused-unit-final.xcresult`, `s7-3-focused-final.xcresult` and
  `s7-3-gate.xcresult` record the focused GREEN; the consolidated gate completed
  127 distinct tests / 130 executions with zero failures or skips.
- History now presents localized meal/workout hierarchy and optional metrics in
  semantic cards. Nil metrics remain absent and literal zero remains data; no
  edit, delete, create or other mutation was added.
- Routine labels and status presentation are localized while raw server status,
  action submission, idempotency/conflict handling, retry, occurrence identity
  and receipts remain unchanged. History dates require
  `PatientTimeZoneContext.requireTimeZone()`; missing patient timezone produces
  an explicit unavailable value and never falls back to `TimeZone.current`.
- Mascot remains a secondary, server-owned persona surface. Its literal server
  identity and personality are not rewritten, and the mascot is not presented
  as Flow, a doctor or the public agent.

### Visual accessibility correction and final evidence

The first AccessibilityXXXL review found two real presentation regressions:
Profile toolbar copy clipped at the screen edges and the Library All/Saved
filters compressed horizontally. Geometry assertions were added first;
`visual-fix-red.xcresult` records the expected failing filter-stack test. The
two narrow adaptive-layout fixes above then passed in
`visual-fix-green2.xcresult` (2/2, zero failures/skips). Final Profile, Library,
article, routine confirmation and routine history screenshots/accessibility
trees are retained in `<artifact-root>/visual-fix-final` and
`<artifact-root>/visual-routine`; root inspected them for truncation, hierarchy,
contrast, scrolling and preserved literal server data. This is native
screenshot/tree evidence, not a full narrated VoiceOver session:
**VOICEOVER MANUAL STATUS: NOT FULLY VERIFIED**.

### Final regression, build and structured reviews

- `full-bodyflowtests-final.xcresult`: **PASS**, 1,201 distinct tests / 1,415
  executions, including 71 parameterized tests / 285 dynamic executions; zero
  failures, skips, expected failures or runtime warnings.
- `relevant-ui-final.xcresult`: **PASS**, 39/39 selected Profile, Library,
  article, History, Routine and prior contract UI tests; zero failures, skips,
  expected failures or runtime warnings.
- Combined final gates: **PASS**, 1,240 distinct tests / 1,454 executions.
- `batch5-release-final.xcresult`: normal signed Release Simulator build
  **PASS**; `codesign --verify --deep --strict`: **PASS**.
- `batch5-analyze-final.xcresult`: native analyze **PASS**. The only compiler
  warning is the inherited unnecessary `await` in
  `SessionLifecycleCoordinator.swift`, outside this diff; the AppIntents
  metadata skip is a tool diagnostic. Swift compilation/typecheck is covered by
  tests, Release and analyze; no separate SwiftLint is configured.
- 110 new catalog keys parse as JSON and each has both pt-BR and en-US values.
  The final pre-commit gate separately checks whitespace, exact allowlist,
  assets, secrets/PII, public legacy identity additions and forbidden timezone
  fallback.

Primary-agent structured reviews — explicitly not independent reviewer claims:

- **Review A / Profile:** server option and session ownership preserved; no fake
  account capability — **PASS**, Critical 0 / Important 0.
- **Review B / Library:** request/tracking, cover authorization/cache, Markdown
  and link policy preserved — **PASS**, Critical 0 / Important 0.
- **Review C / History and Routine:** History stays read-only; Routine preserves
  raw status, occurrence, idempotency, conflict/retry, receipts and patient
  timezone — **PASS**, Critical 0 / Important 0.
- **Review D / regression and brand:** prior surface tests remain green; no new
  public Dr. Roberto/Dr. Robert or BodyFlow identity copy was introduced —
  **PASS**, Critical 0 / Important 0.

Exact local commit subject: `refactor(ui): refine Profile experience`, with
parent `15d4428a1ec2175356eedf911c6765f7392520ee`. The resulting SHA/tree and clean
state are reported after commit without amending this evidence. No logo,
AppIcon, wordmark, splash or historical asset changed;
BRAND_ASSET_APPROVAL_GATE remains **PENDING_EXTERNAL_ASSETS** and overall rebrand
status remains partial. Real completions: 0. Remote resources altered: NONE. No
push, PR, merge, deployment, staging, Production, Supabase, Vercel, OpenRouter,
CI-3, TestFlight or App Store operation occurred. Slice 9 is not started.

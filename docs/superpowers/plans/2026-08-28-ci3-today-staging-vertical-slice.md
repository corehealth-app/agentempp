# CI-3 Authenticated Today staging vertical slice implementation plan

> **Execution environment:** Mac local with Xcode. Do not execute this plan on
> the VPS. Use `superpowers:executing-plans` or the authorized equivalent and
> stop on every documented divergence.

**Goal:** Connect only Today to the verified authenticated staging BFF while
preserving the CI-2 session lifecycle and server-authoritative semantics.

**Base:** `277873755bf29771a10b5f362b522c2e6a6c21d6`

**Branch:** `codex/ci3-today-staging-v1`

**Worktree:** `/Users/eduardohenrique/Developer/bodyflow-ci3-today-staging-v1`

**Commit subject:** `feat(ios): connect Today to authenticated staging`

**Spec:** `docs/superpowers/specs/2026-08-28-ci3-today-staging-vertical-slice.md`

## Frozen boundaries

- one new worktree from the exact CI-2 base;
- one commit and one non-force push without upstream;
- no PR, merge, deploy, TestFlight, App Store or CI-4;
- no backend, Supabase, Vercel, migration, asset, brand, package or project-file
  mutation;
- no History, Plan, Progress, Registration, Routine, Content, Media, Profile
  mutation, push, paywall or chat integration;
- no real config, URL, key, credential, token, PII, origin or health data in
  Git, argv, logs, chat, screenshot, hierarchy or `xcresult`;
- `BodyFlow` target/scheme/module/root and bundle ID `com.bodyflow.app` stay
  unchanged;
- Auth remains at its CI-2 pinned package revision;
- the synthetic fixture is retained until separately authorized cleanup by
  `2026-09-11T11:44:11.182Z`.

## Exact implementation allowlist

Only these paths may differ from the base in the final CI-3 commit:

```text
apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift
apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift
apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIEnvelope.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift
apps/ios/BodyFlow/BodyFlow/Core/Today/MobileAPITodayProvider.swift
apps/ios/BodyFlow/BodyFlow/Core/Today/TodayModels.swift
apps/ios/BodyFlow/BodyFlow/Features/Today/TodayViewModel.swift
apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift
apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings
apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileAPITodayProviderTests.swift
apps/ios/BodyFlow/BodyFlowTests/TodayContractTests.swift
apps/ios/BodyFlow/BodyFlowTests/TodayViewModelTests.swift
apps/ios/BodyFlow/BodyFlowTests/TodayPresentationTests.swift
apps/ios/BodyFlow/BodyFlowTests/LocalizationContractTests.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingIntegrationTests.swift
apps/ios/BodyFlow/BodyFlowUITests/CI3TodayStagingUITests.swift
```

BodyFlow, BodyFlowTests and BodyFlowUITests use filesystem-synchronized root
groups, so neither `project.pbxproj` nor `Package.resolved` is changed. If the
implementation proves any additional path necessary, stop and publish a new
documentation decision before editing it.

## Task 0 — Mac preflight and preservation

**Files:** none.

1. Fetch only the documentation and CI-2 refs, without prune.
2. Verify the published documentation authority SHA, parent, tree, subject and
   all five document hashes supplied by the handoff.
3. Read the evidence, spec and this plan in full.
4. Verify CI-2 remote/local SHA, parent, tree and subject.
5. Record manager, CI-0, CI-1, CI-2, diagnostic, orphan and old-worktree
   identities/statuses. Do not repair, prune, remove, reset, clean or stash.
6. Require local/remote CI-3 branch absent, target worktree path absent and no
   registration for that path.
7. Create exactly one branch/worktree at the CI-2 SHA.
8. Verify clean worktree/staging and `git diff --check`.

STOP if any identity, preservation or absence gate diverges.

## Task 1 — Secure Mac configuration and credential bridge

**Files:** create `MobileStagingConfiguration.swift`; modify
`AppLaunchConfiguration.swift` and `BodyFlowApp.swift`; create the two focused
configuration test files.

### RED

Write tests proving:

- absent file, symlink, non-regular file, wrong owner/mode, duplicate/unknown
  field, missing value, malformed JSON, non-HTTPS origin and project mismatch
  fail closed;
- exactly one BFF origin and one staging Supabase URL plus anon/publishable key
  are accepted;
- a `service_role`/secret key field is rejected;
- Release without config stays unavailable;
- the non-secret Debug staging-E2E mode is impossible in Release;
- the Debug credential reader requires its exact owner-only file, does not
  expose values through description/mirror/log and removes only the simulator
  import after opening it safely;
- no token or session is stored by the configuration bridge.

Run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/MobileStagingConfigurationTests \
  -only-testing:BodyFlowTests/CI3StagingLaunchConfigurationTests
```

Expected RED for absent configuration/bridge types.

### GREEN

Implement a name-neutral configuration reader from the app data container.
Use descriptor/no-follow validation and typed, redacted errors. Configuration
contains only Supabase URL, anon/publishable key and BFF origin. Under
`#if DEBUG`, the staging-E2E launch mode may read the separate imported
synthetic credential into memory and remove only that simulator copy. Do not
add a password/token property to durable app state.

`BodyFlowApp` resolves the optional configuration once and passes validated
`SupabaseAuthConfiguration` and `MobileAPIConfiguration` to
`AppDependencies`. Missing/invalid values select existing unavailable services.

Run the same command; expected GREEN, zero skip.

### Operational bridge (outside Git)

Create a Mac owner-only launcher outside every repository. It must:

1. enforce `umask 077`, existing SSH key and strict preserved host-key check;
2. open local destination files before transfer and keep mode `0600`;
3. obtain the staging client config through a fixed VPS filter that reads only
   `/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env`, cross-checks
   the approved Preview origin against the deployment receipt, and emits only
   Supabase URL, anon/publishable key and BFF origin through the encrypted
   pipe;
4. transfer the synthetic credential separately through an encrypted pipe;
5. never copy/open the primary file or copy `SUPABASE_SERVICE_ROLE_KEY`;
6. never place raw values in command arguments, stdout, shell history or logs;
7. after app installation, copy both files into the exact simulator app data
   container with mode `0600`, then suppress path/value output;
8. retain the canonical Mac credential only until separately authorized
   cleanup; remove the simulator credential import after the app has opened it.

Record only physical metadata, key names, counts and SHA-256 fingerprints.

## Task 2 — Metadata-preserving Mobile API transport contract

**Files:** modify `MobileAPIEnvelope.swift`, `MobileAPITransport.swift`,
`MobileAPITransportError.swift`, `MobileAPITransportTests.swift`.

### RED

Add deterministic `URLProtocol` tests for:

- exact GET `/api/mobile/v1/today` with current bearer and request ID;
- HTTP 200 JSON, `no-store`, `Vary: Authorization`;
- header request ID equal to envelope metadata;
- API v1 only;
- missing/malformed/mismatched request IDs;
- non-JSON success, missing no-store, missing Authorization vary;
- 401 one-safe-refresh behavior with same logical request ID;
- second 401 termination;
- 402, 403, 404, 409, 422, 429 and 5xx typed errors with no retry;
- timeout, explicit cancellation, body limit and malformed JSON;
- cross-origin redirect rejected before bearer forwarding;
- logout/user switch cancellation and stale-generation suppression;
- no token/body in error description or mirror.

Run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/MobileAPITransportTests
```

Expected RED for absent metadata-preserving execution/header validation.

### GREEN

Add a metadata-preserving transport result using the existing
`MobileResponse<Payload>`/envelope semantics. Keep the existing payload-only
API source-compatible. Validate headers and envelope before delivery. Add only
the minimum typed status/header errors. Do not create a second URLSession,
session source, refresh loop or cache.

Run the same command; expected GREEN, zero skip.

## Task 3 — Today adapter and server-authoritative validation

**Files:** create `MobileAPITodayProvider.swift`; modify `TodayModels.swift`;
create `MobileAPITodayProviderTests.swift`; modify `TodayContractTests.swift`.

### RED

Use hand-authored sanitized fixtures derived from field structure, never from
the real response body. Cover:

- exact endpoint/method;
- local date and RFC3339 timestamps;
- non-empty calculation version;
- required targets/consumed/completion/sources;
- source/provenance for all applicable sections;
- optional protocol, timestamps, targets and Block 7700;
- empty valid Today only by documented completion status;
- partial optional data;
- missing required field, malformed date/timestamp, empty source, inconsistent
  optional structure and incompatible envelope;
- mapping of transport/network/auth/entitlement/status errors;
- no arithmetic/recalculation or fallback substitution.

Run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/MobileAPITodayProviderTests \
  -only-testing:BodyFlowTests/TodayContractTests
```

Expected RED for absent real provider and validator.

### GREEN

Implement `MobileAPITodayProvider` over the existing transport and exact path.
Validate contract/provenance and return `TodayResponse` without recalculation.
Map only typed client states; never expose backend message text to UI.

Run the same command; expected GREEN, zero skip.

## Task 4 — Dependency wiring and Release boundary

**Files:** modify `AppDependencies.swift`, `AppDependenciesTests.swift`.

### RED

Add tests proving:

- complete Release staging config and the shared CI-2 lifecycle produce one
  real `MobileAPITodayProvider`;
- missing Supabase config, BFF config or lifecycle makes Today unavailable;
- Release never selects demo/mock Today;
- Debug demos/previews remain unchanged;
- every non-Today domain remains at its pre-CI-3 provider boundary;
- auth and Today transport share the same lifecycle instance.

Run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/AppDependenciesTests
```

Expected RED, then wire only Today and rerun to GREEN.

## Task 5 — Explicit Today states and localized presentation

**Files:** modify `TodayViewModel.swift`, `TodayRootView.swift`,
`Localizable.xcstrings`, `TodayViewModelTests.swift`,
`TodayPresentationTests.swift`, `LocalizationContractTests.swift`.

### RED

Cover loading, loaded, contract-valid empty, generic error, unauthenticated,
entitlement/subscription error, offline with/without stale value, retry,
cancellation, newer-revision suppression, logout and user-switch stale delivery.
Assert VoiceOver labels and localized pt-BR/en strings for the new explicit
states; no new raw public literal.

Run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/TodayViewModelTests \
  -only-testing:BodyFlowTests/TodayPresentationTests \
  -only-testing:BodyFlowTests/LocalizationContractTests
```

Expected RED, then implement the smallest Today-specific state mapping and
catalog keys. Do not alter other tab contracts. Rerun to GREEN.

## Task 6 — Real staging integration gate

**Files:** create `CI3StagingIntegrationTests.swift` only.

Compile this file's real tests only under the non-secret
`CI3_STAGING_INTEGRATION` condition. The Mac launcher installs config and
credential into the simulator container without exposing values. The test uses
the real app dependencies to consume exactly one sign-in and one Today GET for
this run, then asserts sanitized structure, current session/patient boundary,
headers/envelope/provenance and no persistent token outside the CI-1/CI-2
Keychain record.

Run only after unit gates are GREEN:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  OTHER_SWIFT_FLAGS='$(inherited) -DCI3_STAGING_INTEGRATION' \
  -only-testing:BodyFlowTests/CI3StagingIntegrationTests
```

Expected: zero fail/skip. Capture only assertions, counts, request-ID hash and
structural hash. Do not attach response body or raw identifiers.

If config/fixture/deadline is invalid, STOP before sign-in. Do not recreate,
update, grant or clean up any server object.

## Task 7 — Selected real XCUI gate

**Files:** create `CI3TodayStagingUITests.swift` only.

Use the non-secret Debug staging-E2E launch mode and preinstalled owner-only
simulator files. Tests must not pass credentials as launch arguments or
environment variables. Cover:

- launch without config fails closed;
- synthetic sign-in through the Debug credential bootstrap;
- real Today loaded from staging;
- logout during/after request;
- relaunch with CI-1/CI-2 session restoration;
- deterministic offline/error/retry using transport injection only, without
  changing backend;
- accessibility labels, Dynamic Type and pt-BR/en;
- sanitized screenshots/hierarchies with no raw PII or health data.

Run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowUITests/CI3TodayStagingUITests
```

Expected zero fail/skip. Before retaining an `xcresult`, scan it and every
attachment for credential, raw identity, origin, token and health-data
fingerprints; any match requires secure quarantine and STOP.

## Task 8 — Focused and full native gates

Run focused suites explicitly:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/MobileStagingConfigurationTests \
  -only-testing:BodyFlowTests/CI3StagingLaunchConfigurationTests \
  -only-testing:BodyFlowTests/MobileAPITransportTests \
  -only-testing:BodyFlowTests/MobileAPITodayProviderTests \
  -only-testing:BodyFlowTests/TodayContractTests \
  -only-testing:BodyFlowTests/TodayViewModelTests \
  -only-testing:BodyFlowTests/TodayPresentationTests \
  -only-testing:BodyFlowTests/AppDependenciesTests \
  -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests \
  -only-testing:BodyFlowTests/PatientWorkRegistryTests \
  -only-testing:BodyFlowTests/AuthenticationSessionStoreTests \
  -only-testing:BodyFlowTests/SupabaseAuthServiceTests \
  -only-testing:BodyFlowTests/SecureStorageTests
```

Then run:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests
```

Both commands require zero fail, skip and unapproved expected failure. Record
CI-2, CI-1, CI-0, Authentication, Storage, Networking, Today and
AppDependencies logical/execution counts separately.

## Task 9 — Unsigned builds

Run exactly:

```bash
xcodebuild build \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

xcodebuild build \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Require `BUILD SUCCEEDED`. Record every warning by category. Do not persist a
signing change and do not claim archive/device/TestFlight.

## Task 10 — Scans and reviews

Run `git diff --check`, exact path allowlist and scans over working/staged diff,
source, build logs and sanitized result artifacts for:

- raw staging/production URLs and Preview origin;
- synthetic e-mail/password/marker;
- anon/publishable/service-role values;
- access/refresh token, Authorization and JWT-shaped data;
- raw user/patient/profile/progress/entitlement/event IDs and PII;
- response body and health data;
- hard-coded origin or fallback;
- service role in app/test;
- mock/demo Today reachable in Release;
- duplicate session source, Auth listener/client retention or refresh loop;
- direct Today arithmetic/recalculation;
- backend/migration/assets/rebrand or other domain changes;
- public legacy naming introduced by CI-3;
- CI-4, signing, TestFlight/App Store, PR/merge/deploy.

Review A: transport, DTO, session, configuration/credential bridge, secrets,
server-authoritative boundary and fixture deadline.

Review B: Today architecture/presentation, cancellation/logout/user switch,
UI states, accessibility/localization, tests/builds/XCUI, allowlist and scope.

Correct every Critical/Important, rerun affected gates, then rerun both reviews.
Required final outcome: Review A `0C/0I`, Review B `0C/0I`.

## Task 11 — Selective commit and single publication

1. Revalidate CI-3 diff contains only the exact allowlist.
2. Revalidate all preserved worktrees/manager states and fixture deadline.
3. Verify staging empty before selective add.
4. Stage each changed path individually. Never use `git add .`, `-A` or
   `--all`.
5. Inspect cached name-status/stat/full diff and run
   `git diff --cached --check` plus all scans.
6. Require every changed allowlisted path and no other path staged.
7. Commit exactly `feat(ios): connect Today to authenticated staging`.
8. Verify parent equals CI-2 base, subject, tree, path list, staging empty and
   all preservation evidence.
9. Confirm remote branch remains absent.
10. Push once without force and without upstream:

```bash
git push origin \
  HEAD:refs/heads/codex/ci3-today-staging-v1
```

11. Read back remote SHA and require exact equality. Do not create PR, merge,
    deploy or start CI-4.

## Mandatory STOPs

STOP and preserve without silent reconciliation for any:

- authority/base/worktree drift;
- additional required path;
- config/credential exposure or service-role discovery on Mac;
- fixture/artifact/deadline drift;
- authenticated staging mismatch;
- second sign-in/request caused by the same logical gate;
- transport/DTO/UI test failure or skip;
- Xcode build failure;
- unauthorized diff, scan match or review Critical/Important;
- remote branch appearing unexpectedly;
- non-fast-forward/push uncertainty;
- inability to finish before the fixture deadline.

Report the exact last successful gate and do not start CI-4.

## Final Mac report template

```text
OPERATION=IMPLEMENT_VALIDATE_COMMIT_AND_PUBLISH_CI3_TODAY_STAGING
FINAL_STATUS=<PASS_COMPLETE|STOP_DOCUMENTED>

AUTHORITY_SHA=<PUBLISHED_DOCUMENTATION_SHA>
CI2_BASE=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_BRANCH=codex/ci3-today-staging-v1
CI3_WORKTREE=/Users/eduardohenrique/Developer/bodyflow-ci3-today-staging-v1
CI3_COMMIT=<REAL_OR_ABSENT>
CI3_PARENT=<REAL_OR_ABSENT>
CI3_TREE=<REAL_OR_ABSENT>
CI3_SUBJECT=feat(ios): connect Today to authenticated staging
CI3_REMOTE_SHA=<REAL_OR_ABSENT>

ALLOWLIST_STATUS=<PASS|FAIL>
CONFIG_BRIDGE_STATUS=<PASS|FAIL|NOT_EXECUTED>
SERVICE_ROLE_ON_MAC=NO
RAW_VALUES_REPORTED=NO
TOKEN_PERSISTED_OUTSIDE_CI1_CI2=NO

FOCUSED_TESTS=<COUNTS_AND_RESULT>
FULL_BODYFLOW_TESTS=<COUNTS_AND_RESULT>
STAGING_INTEGRATION=<COUNTS_AND_RESULT>
SELECTED_XCUI=<COUNTS_AND_RESULT>
DEBUG_UNSIGNED_BUILD=<RESULT>
RELEASE_UNSIGNED_BUILD=<RESULT>
SCANS=<RESULT>
REVIEW_A=<CRITICAL/IMPORTANT/MINOR>
REVIEW_B=<CRITICAL/IMPORTANT/MINOR>

FIXTURE_PRESERVED=YES
CLEANUP_EXECUTED=NO
CLEANUP_REQUIRED=YES
CLEANUP_DEADLINE=2026-09-11T11:44:11.182Z
VERCEL_WRITE=NO
SUPABASE_WRITE=NO
PRIMARY_LIVE_OPEN=NO
PRODUCTION_WRITE=NO
PR=NO
MERGE=NO
DEPLOY=NO
TESTFLIGHT_OR_APP_STORE=NO
CI4_STARTED=NO

NEXT_ENVIRONMENT=VPS
NEXT_GATE=<AUTHORIZE_CI3_FIXTURE_CLEANUP_OR_RECONCILE_STOP>
```

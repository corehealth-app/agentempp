# CI-2 Session Lifecycle and User Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Implement secure refresh/rotation, current-session logout, user boundary, cancellation and late-response suppression with one session source.

**Architecture:** `AuthenticationSessionStore` owns durable records. A lifecycle actor owns app-level single-flight refresh and identity generation; direct origin-locked Auth fetch performs refresh and local-scope logout. The transport uses leases, never an SDK session.

**Tech Stack:** Swift 6, SwiftUI/iOS 18+, Security.framework, URLSession, Supabase Auth 2.55.1, Swift Testing/XCTest.

**Spec:** `docs/superpowers/specs/2026-08-23-ci2-session-lifecycle-user-boundary.md`

## Constants and global constraints

```text
BASE=aba177d7cbb0d9cecb13c5f1099e6b99b6456c93
BRANCH=codex/ci2-session-lifecycle-v1
WORKTREE=/Users/eduardohenrique/Developer/bodyflow-ci2-session-lifecycle-v1
COMMIT_SUBJECT=feat(ios): add secure session lifecycle and user boundary
REMOTE_BRANCH=codex/ci2-session-lifecycle-v1
```

Only these paths may appear in the final CI-2 commit:

```text
apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift
apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationService.swift
apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationSessionRecord.swift
apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationSessionStore.swift
apps/ios/BodyFlow/BodyFlow/Core/Auth/PatientWorkRegistry.swift
apps/ios/BodyFlow/BodyFlow/Core/Auth/SessionLifecycleCoordinator.swift
apps/ios/BodyFlow/BodyFlow/Core/Auth/SupabaseAuthService.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/SessionTokenProviding.swift
apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift
apps/ios/BodyFlow/BodyFlowTests/AuthenticationSessionStoreTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift
apps/ios/BodyFlow/BodyFlowTests/PatientWorkRegistryTests.swift
apps/ios/BodyFlow/BodyFlowTests/SessionLifecycleCoordinatorTests.swift
apps/ios/BodyFlow/BodyFlowTests/SupabaseAuthServiceTests.swift
```

No project file change is needed because BodyFlow and BodyFlowTests use
filesystem-synchronized root groups. No assets, strings, public plist, docs,
backend or migration are allowed. Use Auth 2.55.1 already pinned; do not import
the Supabase product, use a listener, SDK persistent storage/currentSession,
setSession, automatic refresh, global/others logout, real URL/key, mock Release
or retry loop. Tokens/password/PII never enter descriptions, logs or tests.

### Task 0: Preflight and durable CI-2 worktree

**Files:** none. **Consumes:** published CI-1 commit and CI-2 spec. **Produces:** isolated base proof.

- [ ] Verify manager, CI-0, CI-1, diagnostics, orphan metadata and old worktree exactly as required by the Mac handoff; do not repair/clean any.
- [ ] Verify CI-1 remote SHA/tree/15 hashes and that the CI-2 branch/worktree path do not exist.
- [ ] Create the named branch/worktree at BASE only after all checks pass; record clean staging.
- [ ] Run `git diff --check`; expected: clean new worktree.

### Task 1: Direct remote refresh and local logout adapter

**Files:** modify `SupabaseAuthService.swift`, `SupabaseAuthServiceTests.swift`.
**Consumes:** `SupabaseAuthFetch`, `AuthenticationSessionRecord`.
**Produces:** `refresh(record:) async throws -> AuthenticationSessionRecord` and `revokeCurrentSession(accessToken:) async -> RemoteRevocationOutcome` on `SupabaseAuthRemoteOperating`.

- [ ] Add RED tests asserting one same-origin `POST /auth/v1/token?grant_type=refresh_token` with JSON refresh token only, and one `POST /auth/v1/logout?scope=local`; expected compile failure for absent methods.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/SupabaseAuthServiceTests`; expected RED because direct refresh/revocation methods are absent.
- [ ] Implement direct `URLRequest` construction with only required headers, strict Session decode/subject/email/expiry validation, redacted status mapping and no AuthClient creation.
- [ ] Add RED tests for rotated tokens, invalid grant, 403, 429, 5xx, timeout and logout 204/unconfirmed statuses; expected incorrect classification before implementation.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/SupabaseAuthServiceTests`; expected GREEN, zero skips.

### Task 2: Record migration and fail-closed invalidation

**Files:** modify `AuthenticationSessionRecord.swift`, `AuthenticationSessionStore.swift`, `AuthenticationSessionStoreTests.swift`.
**Consumes:** CI-1 record/storage contract. **Produces:** independent token-free invalidation marker, `invalidateLocally()`, `bootstrapRecord()` and `currentRecord()` actor APIs.

- [ ] Add failing tests for marker-first relaunch, expired bootstrap retained only for coordinator refresh, corrupted/blocked Keychain, marker-write failure preserving old session with `localInvalidationFailed`, ordered cleanup (record delete before marker delete), each cleanup-delete failure retaining marker, and persist-before-publish rotation. Simulate a fresh bootstrap after each cleanup failure and prove it is signed out.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/AuthenticationSessionStoreTests`; expected RED because `bootstrapRecord()` and tombstone encoding are absent.
- [ ] Implement a separate token-free marker key before record mutation; marker has no user/token; expired bootstrap cannot produce bearer. For cleanup, keep marker present, delete record first, then delete marker only after record deletion succeeds; either delete error retains marker. Marker-write failure preserves old session and makes no later mutation.
- [ ] Run the same command; expected GREEN with no token in mirror/description.

### Task 3: Single-flight lifecycle coordinator

**Files:** create `SessionLifecycleCoordinator.swift`, modify `SessionTokenProviding.swift`, create `SessionLifecycleCoordinatorTests.swift`.
**Consumes:** Task 1 remote methods and Task 2 store. **Produces:** `SessionLifecycleProviding`, `SessionLease`, `SessionRefreshPolicy`, typed lifecycle errors.

- [ ] Write RED tests for valid/within-leeway/expired bootstrap bearer, N concurrent waiters making one refresh, rotation persistence ordering, cancellation and invalid-grant invalidation.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests`; expected RED because coordinator/lease do not exist.
- [ ] Implement actor-held `Task` keyed by user/generation; production leeway 60 seconds, injected clock/policy in tests, no timer/no infinite retry.
- [ ] Run the same command; expected GREEN and no stored AuthClient/password.

### Task 4: Generation and patient work registry

**Files:** create `PatientWorkRegistry.swift`, create `PatientWorkRegistryTests.swift`, modify `SessionLifecycleCoordinator.swift` and its tests.
**Consumes:** Task 3 generation. **Produces:** `begin`, `finish`, `cancelAll`, `validate` lease semantics.

- [ ] Write RED tests for registry cleanup, logout cancellation, different-user cancellation, same-user refresh preserving generation and cancellation propagation.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/PatientWorkRegistryTests`; expected RED because registry does not exist.
- [ ] Implement actor registry keyed by UUID/user/generation, retaining only cancellation handles and removing them in `defer`.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/PatientWorkRegistryTests -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests`; expected GREEN.

### Task 5: Transport 401 recovery and late-response protection

**Files:** modify `MobileAPITransport.swift`, `MobileAPITransportError.swift`, `MobileAPITransportTests.swift`.
**Consumes:** `SessionLifecycleProviding`, `SessionLease`. **Produces:** typed `sessionSuperseded` and one authorized 401 retry.

- [ ] Add RED tests: first 401 refreshes/retries once with same request ID/idempotency key; second 401 ends; 403/409/422/429/5xx do not refresh; non-replayable/cancelled/stale request does not retry.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/MobileAPITransportTests`; expected RED because lease retry and stale error are absent.
- [ ] Replace raw bearer lookup with lease acquisition/validation; configure URLSession with URLCache, cookie storage and credential storage disabled; register patient request around URLSession task; validate before decode/delivery; preserve logical mutation key.
- [ ] Run the same command; expected GREEN, no cookie/credential retention and no late response delivery.

### Task 6: Privacy-first logout transaction

**Files:** modify `AuthenticationService.swift`, `SupabaseAuthService.swift`, `SessionLifecycleCoordinator.swift`, related tests.
**Consumes:** Tasks 1-4. **Produces:** explicit `SessionLifecycleProviding.signOut() async -> RemoteRevocationOutcome`; the existing `AuthenticationService.signOut() async throws` remains source-compatible.

- [ ] Add RED tests for immediate bearer removal after marker persistence; marker-write failure preserving lease/generation/patient tasks/owned state and network calls unchanged with `localInvalidationFailed`; record-delete failure retaining both record and marker; marker-delete failure retaining marker after record deletion; a fresh bootstrap after each failure signed out; remote 204, timeout/401/5xx unconfirmed, no global scope and no token in cache/log. Add adapter tests proving `confirmed` and `unconfirmed` return through the unchanged void/throwing `AuthenticationService.signOut`, while `localInvalidationFailed` throws its existing typed failure.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/SupabaseAuthServiceTests -only-testing:BodyFlowTests/AuthenticationSessionStoreTests -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests`; expected RED because privacy-first signout is absent.
- [ ] Implement order: capture current access token, write durable marker, then block lease/generation/cancel/clear and perform local-scope remote request. Keep the marker while deleting the old record, then delete marker only after record deletion succeeds; either cleanup error retains marker. Map the coordinator's explicit remote result non-breakingly: `confirmed`/`unconfirmed` complete the existing `AuthenticationService.signOut() async throws` successfully after local invalidation; `localInvalidationFailed` throws. A marker-write error performs none of the later mutations.
- [ ] Run the same command; expected GREEN and no false remote confirmation.

### Task 7: Atomic user switching and sensitive-state clearing

**Files:** modify `SupabaseAuthService.swift`, `SessionLifecycleCoordinator.swift`, `AuthenticationSessionStore.swift`, relevant tests.
**Consumes:** Tasks 2-6. **Produces:** different-user switch transaction and narrow `SensitiveStateClearing` no-op owner.

- [ ] Add RED tests for remote new-login failure, new-record persistence failure, cross-user cancellation/cache clear/stale response, and same-user reauth without patient cancellation.
- [ ] Implement obtain-new-before-destroy-old, persist-new-before-publish, then generation invalidation/cancellation/owner clear; preserve old record on failure.
- [ ] Run focused auth/lifecycle/transport tests; expected GREEN.

### Task 8: AppDependencies and Release wiring

**Files:** modify `AppDependencies.swift`, `AppDependenciesTests.swift`.
**Consumes:** lifecycle coordinator. **Produces:** same injected lifecycle for auth and MobileAPITransport.

- [ ] Add RED tests proving Release selects unavailable services if configuration is absent and injects one shared lifecycle if both configurations exist.
- [ ] Implement only fail-closed injection; preserve Debug fixtures and no real configuration.
- [ ] Run AppDependencies tests; expected GREEN.

### Task 9: CI-2 verification and reviews

**Files:** only the exact allowlist above. **Consumes:** Tasks 0-8. **Produces:** reviewed local candidate.

- [ ] Run CI-2, CI-1, CI-0, Auth, Storage, MobileAPITransport, AppDependencies and full BodyFlowTests suites; expected zero failures/skips.
- [ ] Run exact unsigned Debug/Release builds with `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`; expected `BUILD SUCCEEDED`.
- [ ] Run diff/allowlist/secret/real-URL/naming/API/global-logout/two-session/retry-loop/late-response/broad-cache scans; expected zero unauthorized matches.
- [ ] Obtain Review A for refresh/logout/token/Keychain/API security and Review B for generation/cancellation/late response/switch/wiring. Correct each Critical/Important then rerun affected tests/builds and both reviews; expected 0/0.

### Task 10: Selective commit and one publication

**Files:** exact final allowlist only. **Consumes:** Task 9. **Produces:** remote CI-2 commit.

- [ ] Selectively stage each changed allowlisted path, show name-status/stat/diff and run `git diff --cached --check`; expected no historical or unauthorized path staged.
- [ ] Commit exactly `feat(ios): add secure session lifecycle and user boundary`.
- [ ] Verify parent is BASE, tests/builds/reviews remain recorded and remote branch is absent before push.
- [ ] Push once without force to `origin/codex/ci2-session-lifecycle-v1`, without configuring upstream; verify `ls-remote` equals local SHA. Do not create PR, merge, deploy or start CI-3.

## Mandatory Task 7–10 correction

This section supersedes the earlier Task 7–10 descriptions and is the binding
execution order.

### Task 7: Atomic user switching

**Files:** modify `SupabaseAuthService.swift`, `SessionLifecycleCoordinator.swift`, `AuthenticationSessionStore.swift`, `SupabaseAuthServiceTests.swift`, `SessionLifecycleCoordinatorTests.swift`.
**Consumes:** remote record mapping, tombstone/store and generation APIs. **Produces:** `switch(to:)` transaction.

- [ ] Write tests where new remote login fails, new persistence fails, a different user cancels old work, and same-user reauth does not change generation.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/SupabaseAuthServiceTests -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests`; expected RED because switch transaction is absent.
- [ ] Implement obtain-new-before-destroy-old, persist-new-before-publish, then generation advance and old-work cancellation; preserve old state on either failure.
- [ ] Run the same command; expected GREEN.

### Task 8: Sensitive-state and cache clearing

**Files:** modify `SessionLifecycleCoordinator.swift`, `SessionLifecycleCoordinatorTests.swift`.
**Consumes:** generation/registry. **Produces:** narrow `SensitiveStateClearing` ownership boundary.

- [ ] Write tests that logout/switch clears only session memory, pending patient work and no-store URLSession state; global state is untouched and no broad `removeAll` is called.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests`; expected RED because no clearing boundary is invoked.
- [ ] Implement the no-op current owner with explicit future adapter registration and invoke it after generation invalidation.
- [ ] Run the same command; expected GREEN.

### Task 9: AppDependencies and Release wiring

**Files:** modify `AppDependencies.swift`, `AppDependenciesTests.swift`.
**Consumes:** `SessionLifecycleProviding`. **Produces:** one shared lifecycle for auth and transport.

- [ ] Write tests proving Release remains unavailable when configuration is absent and uses the same lifecycle instance when valid injected configuration exists.
- [ ] Run `xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BodyFlowTests/AppDependenciesTests`; expected RED because shared lifecycle injection is absent.
- [ ] Implement fail-closed injection only; preserve Debug fixtures and omit real values.
- [ ] Run the same command; expected GREEN.

### Task 10: Tests, builds, scans, reviews, commit and push

**Files:** exact final allowlist only. **Consumes:** Tasks 0–9. **Produces:** one remote CI-2 commit.

- [ ] Run each focused suite explicitly: `AuthenticationSessionStoreTests`, `SessionLifecycleCoordinatorTests`, `PatientWorkRegistryTests`, `SupabaseAuthServiceTests`, `MobileAPITransportTests`, `AppDependenciesTests`, then all `BodyFlowTests`; expected zero failure/skip.
- [ ] Run exactly these unsigned builds; each must report `BUILD SUCCEEDED`:
  ```sh
  xcodebuild build -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  xcodebuild build -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  ```
- [ ] Run `git diff --check`, exact allowlist, secret/real-URL/naming/global-logout/two-session/retry-loop/stale-response/broad-cache scans; expected zero unauthorized result.
- [ ] Obtain both independent reviews and correct every Critical/Important; expected Review A and B each 0/0.
- [ ] Selectively stage exact paths, run `git diff --cached --check`, commit `feat(ios): add secure session lifecycle and user boundary`, and push once without force or upstream to the named remote branch; expected remote SHA equals local SHA and no PR/merge/deploy/CI-3.

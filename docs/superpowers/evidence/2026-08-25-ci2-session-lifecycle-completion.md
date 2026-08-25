# CI-2 Session Lifecycle completion

**Evidence classes:** `USER-SUPPLIED MAC CI-2 COMPLETION REPORT` and
`REMOTE COMMIT VERIFIED BY VPS`

## Identity

- Workstream: CI-2 — Session Lifecycle, User Boundary and Patient-Scoped
  Cancellation.
- Branch: `codex/ci2-session-lifecycle-v1`.
- Commit: `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Parent: `aba177d7cbb0d9cecb13c5f1099e6b99b6456c93`.
- Tree: `9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4`.
- Subject: `feat(ios): add secure session lifecycle and user boundary`.

The VPS re-read the remote branch at the exact commit and validated the detached
deployment worktree at that SHA with empty porcelain and staging.

## Scope

The commit contains exactly 15 paths: 11 modified and 4 added, with 2,630
insertions and 144 deletions. It implements app-owned refresh/rotation, local
privacy-first logout, atomic user switching, patient-scoped cancellation,
generation/lease ownership and suppression of stale responses. It changes no
asset, public copy, backend, migration or real environment and does not
implement CI-3.

`AuthenticationSessionStore` remains the single durable session authority.
`SessionLifecycleCoordinator` owns refresh single-flight and distinguishes
terminal invalidation, service unavailability and storage unavailability.
Logout is restricted to the current local session. Exactly one eligible 401
recovery preserves request ID and idempotency key. Release remains fail-closed.

## User-supplied Mac verification

The supplied completion report records:

- focused final: 160/160 passed, zero failures, skips or expected failures;
- full BodyFlowTests: 1,109 logical tests, 1,305 expanded executions, zero
  failures, skips or expected failures, on iPhone 17 Pro / iOS 26.5;
- unsigned Debug and Release builds for `generic/platform=iOS`: succeeded using
  only `CODE_SIGNING_ALLOWED=NO` and `CODE_SIGNING_REQUIRED=NO`;
- inherited AppIntents warning only, with no new CI-2 warning;
- affected final fixes: 48/48 tests passed;
- Review A: 0 Critical, 0 Important, 0 Minor;
- Review B: 0 Critical, 0 Important, 0 Minor;
- diff, allowlist, refresh/logout, one-401 recovery, request identity,
  cancellation, stale-response, Release fail-closed, secret/PII/real-URL,
  naming and CI-3 scans: passed.

This VPS did not run Xcode or claim independent execution of the Mac tests and
builds.

## VPS backend readiness gates for the future Preview

Against the clean CI-2 source, this VPS executed:

- Corepack pnpm 10.33.2 frozen install: passed;
- focused Mobile API auth/route/headers/envelope/read-model: 48/48 passed;
- official daily-state service: 10/10 passed;
- full `@mpp/admin` suite: 619/619 passed;
- `@mpp/admin` typecheck: passed;
- `@mpp/admin` Next.js build with exactly the three staging variables injected
  into the child process: passed;
- 141 client-bundle files scanned with zero raw service-role occurrence;
- lockfile hash and tracked worktree: unchanged.

Two independent pre-deployment reviews completed with 0 Critical, 0 Important
and 0 Minor. These backend gates do not convert the failed Vercel provisioning
into a verified staging BFF.

## Preservation and boundary

Manager history, CI-0, CI-1, diagnostic evidence and CI-2 remained preserved.
No iOS code, signing, production, TestFlight, App Store, database or migration
action occurred. CI-2 is complete; CI-3 remains unauthorized until the staging
BFF and synthetic-patient gates are separately satisfied.

# Naming-Neutral Core Integration Workstream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** create a fail-closed, naming-neutral iOS HTTP transport foundation
without changing public brand, assets, renderer, production, or the lost Better
Ahead worktree.

**Architecture:** create a durable Mac worktree from the committed end of Task
2 only after exact Git ancestry and physical-preservation gates. The transport
receives one injected HTTPS BFF origin and a token through narrow protocols. It
owns origin enforcement, redirects, cancellation, response limits, envelope
decoding and error mapping. Product-facing names continue behind semantic
interfaces and are not introduced by CI-0.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, Swift Testing,
XCTest/XCUI where applicable, iOS 18+, Xcode on macOS, existing Mobile API V1
contract.

**Spec:**
`docs/superpowers/specs/2026-08-20-naming-hold-and-rebrand-preservation.md`

## Global Constraints

- Execute implementation only on the Mac/Xcode machine, never on the VPS.
- The VPS is limited to documentation, contracts, backend/security and staging
  preparation; it must not claim Xcode execution.
- Public naming is on hold. Better Ahead is provisional and must not be added to
  new UI, logs, assets, metadata, tests or copy. Do not invent a replacement
  name. Do not expand Flow branding.
- Do not touch Tasks 3–10, renderers, Docker assets, environment capture,
  wordmarks, splash, AppIcon or review PNGs.
- Do not reuse or repair
  `/private/tmp/better-ahead-ios.GQgTa0/worktree` or its `worktree1` metadata.
- Preserve technical identifiers including `BodyFlow` target/module/root,
  `com.bodyflow.app`, wire contracts, stored keys, telemetry and accessibility
  identifiers.
- Use one injected HTTPS BFF origin. No hard-coded production URL, fallback
  origin, host derived from payload, `service_role`, credential fixture or
  synthetic Release success is allowed.
- Mocks are permitted only in Debug, previews and tests. Release/beta fails
  closed when origin or session is unavailable.
- Do not configure production, APNs, StoreKit, RevenueCat, TestFlight, App
  Store, push Git, PR, merge or deploy.

## Authority and base

The candidate base is exactly:

`4f635ad2b5802239575ef2b6ec04b0aed50db740`

It must be proven on the Mac Git manager before any write:

- it exists and is a commit;
- it is the committed end of Task 2;
- `11f5a7cec331d4fc683b6cee5cdf046d3e89623d` is its ancestor;
- it is an ancestor of
  `ad9869c0d6b11222263ea40c7b72e329092aeef5`;
- it does not contain
  `0a5001e90c9816cb2f9be6f2ff1be6bfa3b0fb38`;
- the new worktree is clean with an empty index.

The VPS clone did not contain the Task 2/Task 3 commits during the naming-hold
documentation run. That absence is not a fallback condition: it means this
ancestry proof is Mac-only and mandatory.

## CI-0 — Secure Configuration and HTTP Transport

CI-0 is the only implementation stage authorized by this plan. It establishes
the technical seam for future authentication without implementing login, a real
production origin, public naming, assets, push, billing or chat.

## File structure for CI-0

The paths below are created or changed only after the Task 0 preflight in the
new Mac worktree. If the Task 2 base has an incompatible existing type or path,
stop for reconciliation rather than silently choosing an alternate design.

| Path | Responsibility |
| --- | --- |
| `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIConfiguration.swift` | validate and hold exactly one injected HTTPS origin |
| `apps/ios/BodyFlow/BodyFlow/Core/Networking/SessionTokenProviding.swift` | read the current bearer without retaining it in transport |
| `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift` | origin-anchored `URLSession` request execution |
| `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift` | typed transport, envelope and HTTP-status failures |
| `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIEnvelope.swift` | decode `data/meta` and `error` Mobile API V1 envelopes |
| `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift` | inject real transport only when configuration/session are available |
| `apps/ios/BodyFlow/BodyFlowTests/MobileAPIConfigurationTests.swift` | configuration and origin tests |
| `apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift` | deterministic transport tests using `URLProtocol` |
| `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift` | fail-closed dependency wiring tests |

## Interfaces

CI-0 defines these internal interfaces:

```swift
struct MobileAPIConfiguration: Sendable, Equatable {
    let origin: URL

    init(originString: String) throws
}

protocol SessionTokenProviding: Sendable {
    func currentBearerToken() async -> String?
}

struct MobileAPITransport: Sendable {
    init(
        configuration: MobileAPIConfiguration?,
        sessionTokenProvider: any SessionTokenProviding,
        session: URLSession,
        clock: any ContinuousClock<Duration>
    )

    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response
}
```

`MobileAPIRequest` must keep method, relative path, query, JSON body,
idempotency requirement and response type. It must not accept a complete URL,
authorization header, hostname, arbitrary redirect policy or caller-supplied
base origin.

## Task 0: Mac proof of base and durable isolation

**Files:**

- Create only after all gates:
  `/Users/eduardohenrique/Developer/bodyflow-naming-neutral-core-integration-v1`
- Create branch:
  `codex/naming-neutral-core-integration-v1`
- Read only:
  `/Users/eduardohenrique/Developer/bodyflow`
- Read only:
  `/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1`
- Read only:
  `/Users/eduardohenrique/Developer/bodyflow/.git/worktrees/worktree1`

**Consumes:** naming hold specification and physical audit evidence.

**Produces:** a clean, durable, isolated Task 2 worktree or an explicit STOP.

- [ ] **Step 1: Prove the three preserved states without changing them**

  Run:

  ```bash
  set -euo pipefail
  MANAGER=/Users/eduardohenrique/Developer/bodyflow
  DIAGNOSTIC=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
  ORPHAN=$MANAGER/.git/worktrees/worktree1
  OLD=/private/tmp/better-ahead-ios.GQgTa0/worktree

  test "$(git -C "$MANAGER" rev-parse HEAD)" = \
    0ce7f20f22b0e66a6de0544d4a46345181f2fccb
  git -C "$MANAGER" diff --cached --exit-code
  test -z "$(git -C "$MANAGER" status --porcelain=v1 -uall)"
  test "$(git -C "$DIAGNOSTIC" rev-parse HEAD)" = \
    03df7894e4cdb37db08351aafb6dd20ad4cb4103
  git -C "$DIAGNOSTIC" diff --cached --exit-code
  test "$(git -C "$DIAGNOSTIC" status --porcelain=v1 -uall | wc -l | tr -d ' ')" = 9
  test -d "$ORPHAN"
  test ! -e "$OLD/.git"
  test "$(find "$OLD" -type f | wc -l | tr -d ' ')" = 0
  ```

  Expected: all assertions pass. Any mismatch is a STOP. Do not prune, repair,
  remove, stage or recreate anything.

- [ ] **Step 2: Prove the only legal base**

  Run:

  ```bash
  set -euo pipefail
  MANAGER=/Users/eduardohenrique/Developer/bodyflow
  BASE=4f635ad2b5802239575ef2b6ec04b0aed50db740
  APPROVED=11f5a7cec331d4fc683b6cee5cdf046d3e89623d
  PARTIAL=0a5001e90c9816cb2f9be6f2ff1be6bfa3b0fb38
  ORPHAN_HEAD=ad9869c0d6b11222263ea40c7b72e329092aeef5

  git -C "$MANAGER" cat-file -e "$BASE^{commit}"
  git -C "$MANAGER" merge-base --is-ancestor "$APPROVED" "$BASE"
  git -C "$MANAGER" merge-base --is-ancestor "$BASE" "$ORPHAN_HEAD"
  if git -C "$MANAGER" merge-base --is-ancestor "$PARTIAL" "$BASE"; then
    echo "Task 3 partial commit is unexpectedly contained in Task 2 base" >&2
    exit 1
  fi
  git -C "$MANAGER" show -s --format='%H%n%P%n%s' "$BASE"
  ```

  Expected: the base is a commit, has the approved asset tip in its ancestry,
  precedes the orphan head and excludes the Task 3 partial commit. A missing
  object or non-matching lineage is a STOP; do not substitute another SHA.

- [ ] **Step 3: Create the new worktree only after Steps 1–2 pass**

  Run:

  ```bash
  set -euo pipefail
  MANAGER=/Users/eduardohenrique/Developer/bodyflow
  BASE=4f635ad2b5802239575ef2b6ec04b0aed50db740
  BRANCH=codex/naming-neutral-core-integration-v1
  NEW=/Users/eduardohenrique/Developer/bodyflow-naming-neutral-core-integration-v1

  test ! -e "$NEW"
  if git -C "$MANAGER" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "branch already exists" >&2
    exit 1
  fi
  git -C "$MANAGER" worktree add -b "$BRANCH" "$NEW" "$BASE"
  test "$(git -C "$NEW" rev-parse HEAD)" = "$BASE"
  test "$(git -C "$NEW" branch --show-current)" = "$BRANCH"
  git -C "$NEW" diff --cached --exit-code
  test -z "$(git -C "$NEW" status --porcelain=v1 -uall)"
  ```

  Expected: a new clean worktree at the durable path. Do not use `/private/tmp`,
  the old path, a fallback branch, merge, rebase or cherry-pick.

## Task 1: Fail-closed configuration and request model

**Files:**

- Create:
  `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIConfiguration.swift`
- Create:
  `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIEnvelope.swift`
- Create:
  `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift`
- Test:
  `apps/ios/BodyFlow/BodyFlowTests/MobileAPIConfigurationTests.swift`

**Consumes:** clean Task 2 worktree and Mobile API V1 contract.

**Produces:** one validated origin and typed, name-neutral request/envelope
models.

- [ ] **Step 1: Write focused failing configuration tests**

  Cover:

  - valid `https://staging.example.test` origin;
  - missing/empty origin;
  - malformed origin;
  - `http://` rejection;
  - userinfo, fragment and query rejection;
  - origin with a base path rejection;
  - a request accepting only relative `/api/mobile/v1/...` paths;
  - rejection of complete URL, network-path reference and payload-derived host.

- [ ] **Step 2: Run the focused tests and verify RED**

  Run:

  ```bash
  xcodebuild test \
    -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:BodyFlowTests/MobileAPIConfigurationTests
  ```

  Expected: the new test target fails because the configuration/request types do
  not yet exist. Do not weaken test assertions to fit legacy demo behavior.

- [ ] **Step 3: Implement validation**

  `MobileAPIConfiguration` must reject every origin except an absolute HTTPS URL
  with host, no userinfo, no query, no fragment and path `/`. It must normalize
  the trailing slash once and expose no mutable host setter.

  `MobileAPIRequest` must build its URL by resolving an allowlisted relative
  path against `configuration.origin`. It must never receive a `URL` from a
  feature payload.

- [ ] **Step 4: Run focused configuration GREEN**

  Run the Step 2 command. Expected: all
  `MobileAPIConfigurationTests` pass with zero skips.

## Task 2: Session seam, origin-anchored transport and deterministic tests

**Files:**

- Create:
  `apps/ios/BodyFlow/BodyFlow/Core/Networking/SessionTokenProviding.swift`
- Create:
  `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift`
- Test:
  `apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift`

**Consumes:** Task 1 types.

**Produces:** a `URLSession` transport that is safe before real login exists.

- [ ] **Step 1: Write deterministic failing `URLProtocol` tests**

  The test protocol must record request URL, method and headers without printing
  bearer content. Cover:

  - same-origin request includes bearer from the provider;
  - missing token fails closed;
  - token fetched independently for consecutive requests, allowing CI-2
    rotation later;
  - cross-origin request cannot be formed;
  - same-origin redirect follows only if the redirect contract permits it;
  - cross-origin redirect throws before sending bearer to the redirected host;
  - timeout throws typed timeout;
  - explicit task cancellation throws cancellation and suppresses late success;
  - response body above configured limit throws before decode;
  - invalid JSON throws typed decode error;
  - success `data/meta` envelope decodes;
  - error `error` envelope maps 401, 403, 409, 422, 429 and 5xx;
  - POST/PATCH/DELETE receives an idempotency key;
  - retry is limited to idempotent read or a mutation with documented key;
  - authorization, PII-shaped body bytes and signed-looking URLs are redacted
    from diagnostic descriptions.

- [ ] **Step 2: Run transport tests and verify RED**

  Run:

  ```bash
  xcodebuild test \
    -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:BodyFlowTests/MobileAPITransportTests
  ```

  Expected: failures identify missing `SessionTokenProviding` and
  `MobileAPITransport` types.

- [ ] **Step 3: Implement the transport**

  Implementation rules:

  - construct `URLRequest` only from `MobileAPIConfiguration` and a relative
    request path;
  - obtain bearer immediately before request creation; do not cache it in a
    property;
  - set `Authorization` only after rechecking the approved origin;
  - use a `URLSessionConfiguration` with explicit timeout and bounded response
    reading;
  - use a delegate/redirect policy that rejects cross-origin redirects before a
    redirected request is sent;
  - preserve cancellation through Swift concurrency and reject completion after
    cancellation;
  - attach/validate request IDs;
  - generate idempotency key only for mutation methods;
  - decode Mobile API V1 envelopes;
  - map status/error code to `MobileAPITransportError`;
  - log redacted categories and request IDs only.

- [ ] **Step 4: Run transport GREEN**

  Run the Step 2 command. Expected: every named transport test passes with zero
  skips and no log containing token or raw sensitive payload.

## Task 3: Dependency wiring that remains fail-closed in Release

**Files:**

- Modify:
  `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Modify if required by existing protocol:
  `apps/ios/BodyFlow/BodyFlow/Core/Networking/APIClient.swift`
- Test:
  `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`

**Consumes:** Tasks 1–2.

**Produces:** dependency wiring that exposes the real transport seam but does
not pretend login or production configuration exists.

- [ ] **Step 1: Write failing dependency tests**

  Cover:

  - Debug preview/test can inject a mock transport explicitly;
  - a valid injected origin plus token provider creates
    `MobileAPITransport`;
  - missing configuration yields an unavailable/fail-closed client;
  - missing session yields an unavailable/fail-closed client;
  - Release never selects a mock success client;
  - app dependencies do not contain a candidate public product name added by
    CI-0.

- [ ] **Step 2: Run dependency tests and verify RED**

  Run:

  ```bash
  xcodebuild test \
    -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:BodyFlowTests/AppDependenciesTests
  ```

  Expected: failures identify absent injection/fail-closed wiring.

- [ ] **Step 3: Implement minimal wiring**

  Add a configuration provider and `SessionTokenProviding` to
  `AppDependencies`. The release path may instantiate `MobileAPITransport` only
  with a valid injected origin and a real future session seam. Until CI-1,
  missing configuration/session must select the existing unavailable behavior.
  Do not add a fake bearer, demo login or a real URL.

- [ ] **Step 4: Run dependency GREEN**

  Run the Step 2 command. Expected: all focused dependency tests pass.

## Task 4: CI-0 verification and local handoff

**Files:**

- Modify only the CI-0 files listed in Tasks 1–3.
- Do not modify assets, string catalogs, public copy, renderer files or
  Better Ahead manifests.

**Consumes:** Tasks 1–3.

**Produces:** a locally verified CI-0 change ready for independent review,
without external release.

- [ ] **Step 1: Run related unit tests**

  Run:

  ```bash
  xcodebuild test \
    -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:BodyFlowTests/MobileAPIConfigurationTests \
    -only-testing:BodyFlowTests/MobileAPITransportTests \
    -only-testing:BodyFlowTests/AppDependenciesTests
  ```

  Expected: `TEST SUCCEEDED`, zero failures and zero skips.

- [ ] **Step 2: Build Debug and Release**

> **Superseded only for this Step 2 by
> [CI-0 Signing Gate Reconciliation — 2026-08-21](#ci-0-signing-gate-reconciliation--2026-08-21).**
> The historical commands below document the original gate that stopped in
> `GatherProvisioningInputs`; do not treat them as the current CI-0 build
> commands.

  Run:

  ```bash
  xcodebuild build \
    -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -configuration Debug \
    -destination 'generic/platform=iOS'

  xcodebuild build \
    -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -configuration Release \
    -destination 'generic/platform=iOS'
  ```

  Expected: both builds emit `BUILD SUCCEEDED`. Report inherited warnings
  separately; do not describe them as introduced by CI-0 without proof.

- [ ] **Step 3: Run content and secret gates**

  Run:

  ```bash
  set -euo pipefail
  git diff --check
  git diff --name-only
  git diff -- \
    'apps/ios/BodyFlow/BodyFlow/**' \
    'apps/ios/BodyFlow/BodyFlowTests/**'
  ! git diff -- \
    'apps/ios/BodyFlow/BodyFlow/**' \
    'apps/ios/BodyFlow/BodyFlowTests/**' | \
    rg -n 'Better Ahead|BodyJourney|BeBetter|BetterEveryday'
  ! git diff -- \
    'apps/ios/BodyFlow/BodyFlow/**' \
    'apps/ios/BodyFlow/BodyFlowTests/**' | \
    rg -n 'https?://[^[:space:]\"'\"']*(prod|production)|service_role|sk-[A-Za-z0-9_-]{16,}'
  ```

  Expected: no whitespace error, no candidate name expansion, no production URL
  and no credential pattern. If a legitimate technical string is matched, stop
  and document it; do not add an allowlist silently.

- [ ] **Step 4: Independent code review**

  Review the complete diff for:

  - origin and redirect enforcement;
  - token lifetime and redaction;
  - cancellation/late-response behavior;
  - status and envelope mapping;
  - retry/idempotency semantics;
  - Release fail-closed behavior;
  - absence of public naming/copy/assets changes;
  - absence of production/APNs/StoreKit/RevenueCat work.

  Any Critical or Important finding blocks local commit until fixed and
  reverified.

- [ ] **Step 5: Record outcome without external delivery**

  If all gates pass, create one local commit on
  `codex/naming-neutral-core-integration-v1` with:

  ```text
  feat(ios): add naming-neutral secure mobile transport
  ```

  Then report HEAD, staged paths, test/build results and hashes. Do not push,
  open a PR, merge, deploy, upload TestFlight or alter the old worktree.

## CI-0 Signing Gate Reconciliation — 2026-08-21

This section supersedes **only** the build-command block in Task 4, Step 2.
The original Debug command stopped in `GatherProvisioningInputs` because a
Development Team was required before CI-0 compilation began. Task 4 remains a
compilation verification gate; it is not a signing, installation, archive, or
distribution gate.

On the Mac, run exactly these commands for the current Task 4, Step 2:

```text
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

The two `CODE_SIGNING_*` settings are permitted only as command-line overrides
for this compilation proof. This reconciliation does not change the
`generic/platform=iOS` destination and does not authorize simulator
substitution, `project.pbxproj` editing, a Development Team,
`-allowProvisioningUpdates`, a provisioning profile, certificates, bundle-ID
changes, persistent signing settings, archive, device installation, TestFlight,
App Store, or any claim that a build is signed or distributable. Do not add
other flags to bypass a failure.

If either unsigned build fails because of compilation, linking, Swift 6, a test
target, resource, or configuration, stop and report that real error. The
override never turns such a failure into a signing workaround.

After both builds report `BUILD SUCCEEDED`, continue in the same preserved Mac
worktree with the following order:

1. `git diff --check`;
2. complete allowlist verification of changed paths;
3. candidate-name scan limited to added lines;
4. scan for literal credential values, JWTs, `service_role`, literal bearer
   values, and real production URLs;
5. independent technical review;
6. correction of every Critical or Important finding;
7. repeat focused tests after every correction;
8. repeat these unsigned builds after a correction that affects production
   code;
9. selective staging; and
10. one local commit with `feat(ios): add naming-neutral secure mobile transport`.

`SessionTokenProviding` and technical occurrences of `token` are not, by
themselves, secrets. `BodyFlow` remains permitted as a technical identifier.
No candidate public name may be added to UI, copy, test, fixture, or log. This
reconciliation neither concludes CI-0 nor authorizes a push, pull request,
merge, deployment, production configuration, TestFlight, or App Store work.

## CI-0 Orphan Residue Drift Reconciliation — 2026-08-22

This section supersedes **only** former checks that required an exact
filesystem-residue cardinality for the old Better Ahead worktree. It preserves
the `PHYSICALLY_INCOMPLETE_WORKTREE` classification and records
`VOLATILE_RESIDUE_DRIFT`; it neither restores the path nor changes its forensic
status.

The next Mac gate must first fetch and validate this documentation commit, then
read the dossier, physical audit, CI-0 evidence, naming-hold specification, and
this plan in full. It must confirm the manager and diagnostic repository,
`worktree1` by HEAD, parent, index SHA-256, index size, and empty staging; and
the old worktree's absent `.git`, zero regular files, zero physically present
orphan-index paths, and non-reattached state. Record directory and symlink
counts only as observations: do not require either 5270 or 987.

It must then validate the durable CI-0 worktree, its ten implementation paths,
and empty staging; run exactly the two unsigned builds already authorized;
perform allowlist, `git diff --check`, candidate-name, and secret scans; obtain
independent review; run the focused final suite; and create the local CI-0
commit only if every gate passes.

```text
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

No other override is authorized. Signing persistence, Development Team,
provisioning, archive, TestFlight, App Store, CI-1, production, implementation
push, rebrand work, and old-worktree recovery, cleanup, repair, or reuse remain
prohibited. The retained material gates include authorized Git/index state,
tracked-path absence, and preservation of the historical 5270 observation;
they do not include residue-count equality.

## Future stages — planned but not authorized by CI-0

## CI-0 Completion and Isolated CI-1 Authorization — 2026-08-22

CI-0 is complete and published as `b9a51bc1a641895ef5323cb1085b3b5622bbb277`
on `codex/naming-neutral-core-integration-v1`: 68/88 native results, unsigned
Debug/Release builds and final review 0/0/0. CI-1 is now authorized only by its
isolated specification and plan: exact Auth 2.55.1/revision
`21d3aaf21ee98f41611f9f75070489fc8b23d882`, no SupabaseClient, no refresh,
discarding SDK storage, app actor and app Keychain. Application auth/session
listeners remain prohibited. Naming hold remains active; CI-2 remains
unauthorized.

| Stage | Scope | Explicit boundary |
| --- | --- | --- |
| CI-1 | Supabase Auth, Keychain and single session source | no public naming expansion |
| CI-2 | refresh, rotation, logout and user switching | patient-scoped cancellation required |
| CI-3 | Today vertical slice against staging | no production URL/fallback |
| CI-4 | History, Plan and Progress adapters | server remains authoritative |
| CI-5 | Registration, Routine, Content, Media and Profile | no raw PII logs |
| CI-6 | staging end-to-end validation | no production mutation |
| CI-7 | integrated QA, accessibility, localization and security | name decision required before visual UAT |

Push, paywall, chat nativo and migration of legacy WhatsApp identities remain
separate decisions. They are not implicit in CI-0.

## CI-1 AuthClient Lifecycle Reconciliation — 2026-08-23

The Mac STOP against Auth 2.54.1 is recorded in
`docs/superpowers/evidence/2026-08-23-ci1-supabase-auth-2.54.1-lifecycle-stop.md`.
Its short-lived AuthClient still registered lifecycle machinery without a
public cleanup path, so client-per-operation could accumulate registry state.
The frozen 15-path CI-1 worktree is preserved; no implementation commit,
push, merge or deployment was made.

CI-1 resumes only against official `supabase-swift` tag `v2.55.1`, exact
revision `21d3aaf21ee98f41611f9f75070489fc8b23d882`, with product/import `Auth`
only. The verified authority is
`docs/superpowers/evidence/2026-08-23-supabase-swift-v2.55.1-authclient-lifecycle-authority.md`.
It includes the fixes that remove a deinitialized client from the dependency
registry and stop its refresh work. The architecture remains ephemeral client
per remote operation, `autoRefreshToken: false`, discarding storage, no SDK
restore/session/currentSession/refresh API, no durable SDK ownership, and a
single app-actor Keychain-backed session authority.

The previous broad wording is refined: the app may not install an auth or
session listener or use a listener as session persistence/restoration. The
limited internal SDK lifecycle observer is permitted solely as an inert
implementation detail of an ephemeral 2.55.1 AuthClient. The Mac gate must
prove client deallocation within a bounded deadline and no late request or
refresh grant after the operation. A one-yield assertion is inadequate.

Resume the same frozen Mac worktree only after validating its existing 15 paths
and preflight hashes. Update the package pin, adapt the initializer only if the
2.55.1 API requires it, add/adjust only in-allowlist tests, then run focused
and full CI-1 tests, exact unsigned Debug and Release builds for
`generic/platform=iOS`, scans and two independent reviews. CI-2, backend
changes, public naming, production configuration, staging E2E, TestFlight,
App Store and deployment remain unauthorized.

## Mac execution handoff

Use this prompt only in the local Mac/Xcode session after proving the
documentation commit is available locally:

```text
The VPS final report supplies the exact documentation-only naming-hold commit
SHA. Do not assume that SHA is available in this Mac repository. Verify it
through the configured remote or an approved transfer before relying on it.

This is a naming-neutral integration task. Better Ahead is provisional; do not
add Better Ahead, Flow, BodyJourney, BeBetter, or any replacement candidate to
new public copy, tests, assets, metadata or logs.

Before any write:

1. Read the naming-hold spec, physical-audit evidence and this CI-0 plan from
   the verified documentation commit.
2. Inspect read-only:
   /Users/eduardohenrique/Developer/bodyflow
   /Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
   /Users/eduardohenrique/Developer/bodyflow/.git/worktrees/worktree1
   /private/tmp/better-ahead-ios.GQgTa0/worktree
3. Confirm the old path remains PHYSICALLY_INCOMPLETE_WORKTREE; do not clean,
   repair, prune, remove, reattach or overwrite it.
4. Verify the exact Task 2 base
   4f635ad2b5802239575ef2b6ec04b0aed50db740 and every ancestry assertion in
   Task 0 of this plan.
5. Verify the durable target path
   /Users/eduardohenrique/Developer/bodyflow-naming-neutral-core-integration-v1
   does not exist.
6. Only after all gates pass, create branch
   codex/naming-neutral-core-integration-v1 and the durable worktree from that
   exact base.
7. Implement only CI-0 and run its focused tests, Debug build, Release build,
   diff, secret and candidate-name gates.

Do not execute any renderer, Docker asset command, pnpm brand command, Xcode
action on the old worktree, public-copy/asset change, production configuration,
APNs, StoreKit, RevenueCat, TestFlight, App Store, push, PR, merge or deploy.

Stop immediately on any real divergence. Report the read-only evidence, base
proof, files changed, tests/builds, review outcome, local commit SHA if created,
and final state of all preserved worktrees.
```

## CI-1 Completion and CI-2 Authorization — 2026-08-23

CI-1 is complete and published on `codex/ci1-supabase-auth-session-v1` at
`aba177d7cbb0d9cecb13c5f1099e6b99b6456c93`, parent
`b9a51bc1a641895ef5323cb1085b3b5622bbb277`, tree
`5ea465bcfbe3a52781e0afef597372a03fa5dbe0`. It changes 15 paths with Auth
2.55.1, isolated storage, Keychain session ownership and Release fail-closed
wiring. The supplied Mac completion reports 140/182 focused and 1,072/1,261
BodyFlowTests results, unsigned generic-iOS Debug/Release builds, bounded
lifetime proof and final reviews 0/0/0.

CI-2 is authorized only by
`docs/superpowers/specs/2026-08-23-ci2-session-lifecycle-user-boundary.md` and
`docs/superpowers/plans/2026-08-23-ci2-session-lifecycle-user-boundary.md`.
It uses direct origin-locked Auth refresh and local-scope logout, app-owned
single-flight, generation/cancellation and one Keychain-backed session source.
CI-3, real environment, staging E2E, public naming, production, TestFlight,
App Store and deployment remain unauthorized. Naming hold remains active.

## VPS Manager Porcelain Enumeration Rule — 2026-08-24

All future VPS manager preservation gates must use this exact canonical
command:

```text
LC_ALL=C git status --porcelain=v1 -uall
```

The compact command without `-uall` is not an equivalent gate. Counts and
stream hashes may be compared only when they were produced with the same
enumeration mode.

The canonical baseline remains unchanged:

- 25 total entries;
- 5 tracked entries;
- 20 untracked entries;
- canonical porcelain SHA-256
  `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`.

The compact view of 22 entries is a valid observation, not a divergence and
not a replacement baseline. Future PAT resumptions must record the exact
`-uall` command, total/tracked/untracked counts and full-stream SHA-256. No new
reconciliation is required while those canonical values remain identical; a
divergence produced by the same canonical command requires STOP.

This rule does not resume PAT work in the current VPS operation and does not
authorize a staging secret source, Vercel project or deployment, CI-3, CI-4,
production, TestFlight or App Store activity. CI-2 remains the latest
published implementation gate.

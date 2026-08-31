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

## Primary Supabase Secret Control-Plane Reconciliation — 2026-08-25

The creation of primary/live secret key `manager_vps_20260825` is recorded as
an unauthorized historical control-plane write. Its current state is
`ACTIVE_QUARANTINED_UNUSED`: active only for fail-closed preservation, isolated
outside Git, and not loaded by any consumer or known next launcher found in the
read-only audit. Retention is not operational approval. Use, rename, rotation,
disablement and removal remain unauthorized.

The following markers are authoritative:

```text
CONTROL_PLANE_WRITE_OCCURRED_HISTORICALLY=YES
CONTROL_PLANE_WRITE_TYPE=API_KEY_CREATION
PRIMARY_PROJECT_TOUCHED=YES
PRODUCTION_DATABASE_TOUCHED=NO
PRODUCTION_DEPLOYED=NO
PRIMARY_KEY_STATE=ACTIVE_QUARANTINED_UNUSED
PRIMARY_KEY_RETENTION_IS_OPERATIONAL_APPROVAL=NO
PRIMARY_KEY_DISABLE_AUTHORIZED=NO
STAGING_SOURCE_PRESERVED=YES
```

Primary/live and staging are strict, non-interchangeable trust domains:

- primary credentials are never staging credentials and must not enter
  Preview, tests, builds, CI-3, Vercel or a staging runtime;
- all primary/live inspection remains read-only unless a later authority names
  the exact mutation;
- disabling the quarantined key requires a new explicit authorization and a
  fresh consumer audit immediately before the action;
- the existing root-only staging source and receipt are the only authorized
  inputs for a future staging Preview;
- a future Vercel deployment, when separately authorized, must use only the
  three staging variables and Preview scope, with no Production or Development
  environment values;
- receipt flags are scope-specific: staging `key_created=false` does not erase
  or contradict the historical primary API-key creation;
- operation reports must state both historical control-plane creation and zero
  new key mutation during the reconciling operation.

The detailed authority is
`docs/superpowers/evidence/2026-08-25-primary-supabase-secret-control-plane-reconciliation.md`.
This section by itself does not authorize Vercel, deployment, CI-3, production,
TestFlight or App Store work.

## CI-3 Staging BFF Provisioning STOP — 2026-08-25

CI-2 is complete and remotely published at
`277873755bf29771a10b5f362b522c2e6a6c21d6`. Local VPS backend readiness gates
passed against that clean source: 48/48 focused Mobile API tests, 10/10
official daily-state tests, 619/619 admin tests, typecheck, staging-only build,
client-bundle service-role scan and two independent reviews with 0/0/0.

The BFF Preview gate did not complete. The preflight proved that project
`agentempp-mobile-bff-staging` and matching deployments were absent. The one
authorized project-creation request failed with HTTP 400 because Vercel API v11
rejects `nodeVersion` as an additional create-project property. The post-failure
inventory proved that no partial project exists. No environment variable or
deployment was attempted, and the exhausted request was not retried.

The authoritative state is:

```text
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_CREATED=NO
VERCEL_PROJECT_CREATION_ATTEMPTS=1/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
PRODUCTION_TOUCHED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_STAGING_BFF_PROVISIONING_STOP
```

CI-3, CI-4, production, TestFlight and App Store remain unauthorized. A new
documentation authority must define a create-project request compatible with
the current API while preserving Node 22, Preview-only scope, root
`apps/admin`, Corepack pnpm 10.33.2, no Git integration, no custom domain and a
new explicit one-attempt budget. Do not silently omit the Node constraint or
reuse the consumed attempt.

Evidence:

- `docs/superpowers/evidence/2026-08-25-ci2-session-lifecycle-completion.md`;
- `docs/superpowers/evidence/2026-08-25-ci3-staging-bff-provisioning-stop.md`.

## CI-3 Staging BFF Preview Protection STOP — 2026-08-25

The corrected Vercel create sequence consumed its separately authorized
reconciliation budget. `POST /v11/projects` succeeded with the four-field
create allowlist, and the single `PATCH /v9/projects/{id}` applied Node 22.x,
Next.js, root `apps/admin`, the frozen Corepack/pnpm 10.33.2 commands and
`sourceFilesOutsideRootDirectory=true`. The resulting project has no Git link
and no custom domain.

The authoritative GET also reported inherited Vercel Authentication as
`ssoProtection.deploymentType=all_except_custom_domains`. This policy would intercept the
required unauthenticated Mobile API request before the BFF could return its own
401 envelope. The operation therefore stopped before env creation, local link
or deployment. No protection setting, bypass or share token was changed or
created.

```text
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_CREATED=YES
VERCEL_PROJECT_CREATION_HISTORICAL_ATTEMPTS=1/1
VERCEL_PROJECT_CREATION_RECONCILIATION_ATTEMPTS=1/1
VERCEL_PROJECT_CREATION_TOTAL_HISTORICAL_REQUESTS=2
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=1/1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0/1
VERCEL_LOCAL_LINK_ATTEMPTS=0/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
PRODUCTION_TOUCHED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_STAGING_BFF_PREVIEW_PROTECTION_POLICY
```

Preserve the project and applied settings. Every `0/1` count above is closed
historical state from this completed operation, not reusable authorization.
This record does not authorize
project deletion or recreation, Vercel Authentication changes, protection
bypass, custom domains, env creation, deployment, Supabase mutation, CI-3,
CI-4, production, TestFlight or App Store activity. The next authority must
choose a safe Preview ingress architecture and grant fresh explicit budgets
before any further external write can occur.

## CI-3 Public Ingress Application-Layer Audit STOP — 2026-08-25

The condition for removing Vercel Authentication from the existing shared
`apps/admin` project did not pass. A complete read-only inventory classified
132 entry-point units with zero unclassified surfaces: 27 pages, 48 route
handlers, 54 exported Server Actions, two layouts and one middleware.

Twenty-one units are `BLOCKING_UNPROTECTED_SENSITIVE_SURFACE`:

- the middleware-exempt `/api/admin/send-message` route authenticates its
  public bearer with `SUPABASE_SERVICE_ROLE_KEY` itself;
- two food-management Server Actions create a service client without their own
  user/admin authorization;
- 18 admin page routes open a service client before any page-local or
  data-layer admin-role authorization: 17 directly and `/crescimento` through
  three transitive privileged views.

Two independent reviews returned `NO-GO`, each with 0 Critical, 3 Important
and 1 Minor. The Minor is an unbounded public-path prefix match that could
silently exempt a future sibling route.

The 40 Mobile API routes retain their bearer/patient/entitlement wrapper, and
the focused security suite passed 172/172, but those facts do not make the
entire mixed admin deployment safe for public ingress. The architecture is
therefore:

```text
INGRESS_ARCHITECTURE=REQUIRES_DEDICATED_BFF_ONLY_ARTIFACT
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_PROTECTION_PATCH_ATTEMPTS=0/1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0/1
VERCEL_LOCAL_LINK_ATTEMPTS=0/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
NEXT_ENVIRONMENT=VPS
NEXT_GATE=AUTHORIZE_DEDICATED_PUBLIC_MOBILE_BFF_SURFACE
```

No Vercel or Supabase write occurred. Preserve the existing staging project,
its inherited protection, zero env and zero deployments. Do not patch the
shared project public, create a bypass, populate env, link or deploy under this
authority.

The next authority must design and audit a dedicated public artifact whose
reachable application surface is limited to `/api/mobile/v1/**`. It must
define the exact source/build allowlist, route inventory, secret boundary,
tests, external one-attempt budgets and rollback before any implementation or
provisioning. Fixing or exposing the existing admin surface, CI-3, CI-4,
production, TestFlight and App Store remain unauthorized.

Evidence:
`docs/superpowers/evidence/2026-08-25-ci3-preview-protection-policy-stop.md`.

## Dedicated Public Mobile BFF Authorization — 2026-08-25

The 21 shared-admin blockers are not remediated in this gate and the mixed
`apps/admin` artifact must not become public. The authorized ingress
architecture is now `DEDICATED_NEXTJS_MOBILE_BFF_ARTIFACT`: a separate
`apps/mobile-bff` package named `@mpp/mobile-bff` that exposes only the 40
frozen `/api/mobile/v1/**` route modules through static named re-export
wrappers. The handlers remain authoritative in `apps/admin`; no handler logic
is copied or modified.

The source inventory, whose paths are relative to
`apps/admin/src/app/api/mobile/v1/`, has 40 modules, zero invalid Next Route
Handler export and canonical SHA-256
`7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`.
Source, closure and structured build-manifest gates must prove exact 40/40
parity and zero page, layout, middleware, Server Action, public file, catch-all
or route outside the Mobile API prefix. Admin, Inngest, Stripe and
administrative media paths must remain 404 both locally and on the public
Preview.

Implementation is isolated from exact CI-2 base
`277873755bf29771a10b5f362b522c2e6a6c21d6` on branch
`codex/ci3-dedicated-mobile-bff-surface-v1` and worktree
`/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`. It uses TDD, Corepack
pnpm 10.33.2, a lockfile-only new importer, exact code allowlist, two
independent implementation reviews, one commit and one non-force push. The old
detached CI-2 deploy worktree and frozen Mac worktree remain untouched.

The existing Vercel project `agentempp-mobile-bff-staging` is reused, never
deleted or recreated. Its project SSO remains active while one Preview-only
deployment is built and inspected at the exact implementation SHA. Only after
route/build manifests and deployed-artifact review pass may project SSO be
removed once; the team default remains unchanged. A single fail-closed rollback
restores `all_except_custom_domains` if a subsequent public probe fails.
Exactly the three staging variables may be installed as Preview-only metadata;
the primary/live secret, Production env/deployment, Git Integration, custom
domain, bypass, CI-4 and production remain prohibited.

The complete executable authority is:

- spec:
  `docs/superpowers/specs/2026-08-25-dedicated-public-mobile-bff-surface.md`;
- plan:
  `docs/superpowers/plans/2026-08-25-dedicated-public-mobile-bff-surface.md`.

CI-3 is not authorized by this section alone. It becomes authorized only after
`PASS_COMPLETE`: dedicated BFF/public probes verified, a safe synthetic patient
path `VERIFIED`, authenticated Today `PASS` or
`DEFERRED_TO_MAC_BY_DESIGN`, and final documentation published. If the BFF is
verified but the synthetic patient path is missing, `PASS_PARTIAL` preserves
the Preview and routes to the separate
`AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING` gate without creating a
user. Any other material divergence is `STOP_DOCUMENTED`. CI-4 remains
unauthorized in every outcome of this operation.

### Dedicated BFF authority hardening after Phase A reviews

The dedicated authority uses three non-interchangeable route receipts:

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
WRAPPER_ROUTE_EXPORT_COUNT=40
WRAPPER_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
BUILD_ROUTE_PATH_COUNT=40
BUILD_ROUTE_PATH_STREAM_SHA256=abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a
```

Source/wrapper encode relative route-file path plus sorted named exports;
build-route maps each source route to its `/api/mobile/v1/...` URL template and
encodes sorted paths only. `/_not-found` is internal-only and excluded. The
prior blockers are frozen as 19 concrete GET paths with stream SHA-256
`8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718`
plus two manifest-only action names with SHA-256
`2cc8eac1a54c3f88673701d4b9ede202f1ec4440bf414ac7696dda341bd53a35`.
Every HTTP record must be 404/no-redirect and both actions must be absent from
the dedicated server-reference manifest.

After the SSO forward PATCH, failure of any transport, Mobile API, forbidden
route, 19-finding or action/page-manifest requirement triggers the one rollback
PATCH, confirms protection restored, preserves env/deployment and forbids
reprobe. The current focused security gate is a deterministic 39-file CI-2
Git-object-derived superset, path-stream SHA-256
`586a6653c80b06d77293f0d32f6a2166fb93f935c5d53080cbd0971e60b7a3b8`;
historical 172/172 is not substituted for current execution.

Operationally, `refs/heads/codex/better-ahead-rebranding-design` is the exact
documentation ref and
`/Users/eduardohenrique/Developer/bodyflow-production-secret-contract-v1` is
the untouched Mac evidence path. The VPS resource gate runs before every heavy
phase; every mutation is ledgered immediately with target/evidence/result/
rollback. Authority commit/push failure is report-only `STOP_PRE_AUTHORITY` and
cannot start implementation or services. Final PASS_COMPLETE, PASS_PARTIAL and
STOP_DOCUMENTED documentation uses the exact paths, dossier transitions,
subjects, authority parent, review/staging/push gates and marker/macro-prompt
contracts defined in the dedicated spec/plan. Final preservation rechecks
empty staging and absent `.vercel` in the old CI-2 worktree, plus local
`.vercel` untracked/unstaged only in the clean implementation worktree reused
for deployment; no dedicated deploy worktree is created.

## Dedicated Mobile BFF RED 1 discovery STOP — 2026-08-25

The published dedicated-artifact authority is
`89f8bc1c41073d110fe17ee3c638da3998c31aad`. Its implementation worktree was
created once from CI-2 `277873755bf29771a10b5f362b522c2e6a6c21d6` on
`codex/ci3-dedicated-mobile-bff-surface-v1`.

Task 3 Step 1 passed: frozen install completed without tracked or lockfile
drift. Task 3 Step 4 did not reach the required semantic RED. The exact
published Vitest command used root `apps/admin`, discovered zero files under
the sibling `apps/mobile-bff`, executed zero tests and exited 1 with
`No test files found`. Its normalized transcript SHA-256 is
`5faceda6a65a877d02f0eb1115c9227c98689ad8bc5cddb38929fabbac655a07`.

Exactly two RED tests exist, both untracked and unstaged; no GREEN config,
package, wrapper, verifier or lockfile importer exists. Tasks 4–7, code
reviews/publication and every Vercel/Supabase/deployment/probe phase were not
started. The project remains at its last confirmed protected, zero-env,
zero-deployment authority baseline. CI-3 and CI-4 remain unauthorized.

```text
DEDICATED_MOBILE_BFF_STATUS=NOT_VERIFIED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=0
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_RED1_VITEST_EXTERNAL_TEST_DISCOVERY
```

The next gate must reconcile the RED 1 runner boundary explicitly while
retaining strict test-first order. Until then, do not alter the command/root,
create GREEN artifacts, stage/commit/push code, access services, authorize
CI-3, start CI-4 or touch production. Detailed evidence:
`docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-stop.md`.

## Dedicated Mobile BFF RED 1 discovery reconciliation — 2026-08-26

The dossier is now `1.6.8`. The STOP above remains the historical record of a
valid stop: the prior Vitest 2.1.9 command kept root/discovery in `apps/admin`,
found zero test files, ran zero tests and exited 1 with
`No test files found`. That command is `SUPERSEDED`; the two tests and the
source receipt were not invalid. The preserved receipts are:

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_INVALID_EXPORT_COUNT=0
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
SOURCE_SURFACE_TEST_SHA256=50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6
ROUTE_MIRROR_TEST_SHA256=289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f
```

After the documentation remote confirms `RED_DISCOVERY_AUTHORITY_SHA`, reuse
the existing branch/worktree only, set
`WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1` and execute once:

```bash
corepack pnpm@10.33.2 \
  --dir "$WORKTREE/apps/admin" \
  exec vitest run \
  --config "$WORKTREE/apps/admin/vitest.config.ts" \
  --root "$WORKTREE" \
  --dir "$WORKTREE/apps/mobile-bff/src" \
  "$WORKTREE/apps/mobile-bff/src/source-surface.test.ts" \
  "$WORKTREE/apps/mobile-bff/src/route-mirror.test.ts"
```

The semantic gate requires two discovered test files, both files and more than
zero tests executed, source `40/0` with the frozen hash, wrapper count `0`,
failure exclusively `MIRROR_ABSENT_ONLY`, exit 1, no
`No test files found`, config/module/syntax/discovery error or source drift,
and zero skip/todo/cancel. Before it passes, do not edit either test, create a
package/config/other GREEN artifact, use `--passWithNoTests` or rerun. Worktree
creation is not reauthorized. Only then may Tasks 4–14 of the dedicated plan
continue literally.

Historical external budgets do not roll forward. The reconciliation authority
has one documentation commit/push attempt; only after remote publication do
the new one-attempt budgets for the reconciled RED, implementation commit/push,
settings PATCH, Preview env batch, local link, Preview deployment, project SSO
forward/rollback and final documentation commit/push become valid, exactly as
enumerated in the dedicated spec/plan/evidence.

Final documentation uses `RED_DISCOVERY_AUTHORITY_SHA` as its exclusive parent:
`STOP_DOCUMENTED` and `PASS_PARTIAL` move `1.6.8→1.6.9`, while
`PASS_COMPLETE` moves `1.6.8→1.7`. This isolated reconciliation performs
zero production activity and authorizes neither CI-3 nor CI-4. Detailed
evidence:
`docs/superpowers/evidence/2026-08-25-ci3-red1-vitest-external-discovery-reconciliation.md`.

### RED 1 reconciliation hardening — Round 1

Task 3 Steps 1–3 are historical/completed; the existing tests are preserved and
the frozen install is not repeated normally. The active Phase B preflight is
read-only and requires exact worktree identity/status/test hashes, unchanged
lockfile hash, Vitest 2.1.9, CI-2 config hash
`8bb6705e6315f5a28bdf6cc15cae3ff7526007913c8f7c01acd7279ad0b91266`
without conflicting root/include, source `40/0/hash`, wrapper `0`, zero GREEN
package/config, and `vitest --help` proof for `--root`/`--dir`/`--config`.
Discovery/list is prohibited; frozen install occurs only if the binary is
absent, and failure selects `STOP_DOCUMENTED`.

The single RED produces a no-ANSI ordered normalized receipt binding the exact
command fingerprint, Vitest/root/dir/config, all file/test/pass/fail/skip/exit
counts, source/wrapper/classification fields and
`RED1_RECONCILED_NORMALIZED_LOG_SHA256`. Final reports carry separate
`DOCUMENTATION_BASELINE`, `RED_DISCOVERY_AUTHORITY`,
`IMPLEMENTATION_BASELINE` and `RED1_RECONCILED` groups.

Deployment reuses the clean implementation worktree; no new dedicated deploy
worktree is authorized or expected. After SSO forward succeeds or may have
succeeded, every failure/ambiguity—including forward response/readback—triggers
the single rollback, forbids starting/repeating probes and requires proof that
protection is active. Rollback failure/ambiguity is a material-risk STOP. The
STOP enum is restricted to `NOT_VERIFIED`, `IMPLEMENTED_NOT_DEPLOYED`,
`DEPLOYED_PROTECTED` or `PUBLIC_ROLLED_BACK`.

## Dedicated Mobile BFF Task 9 settings PATCH STOP — 2026-08-26

The reconciled RED authority is
`d5bf981a6c3e926eb63ecb39ccc1d3bdabf31459`. The dedicated implementation was
completed, reviewed at zero Critical/Important, committed and published once
as `e3e1e252b48e42554e75899b950692c05186f60d` on
`codex/ci3-dedicated-mobile-bff-surface-v1`.

Local gates proved source/wrapper/build `40/40/40`, export hash
`7154a9a6…79b4`, build path hash `abc24332…3c3a`, closure 121/hash
`2553c0d3…b5f4`, dedicated tests 24/24, focused security 433/433,
typecheck/build/verifiers and loopback. Final tracing classified 4,180 NFT
references into 151 unique targets, 149 files and two semantically allowlisted
internal package symlinks, with forbidden/missing/external/special zero.

Task 9 preflight passed. Its single seven-field PATCH partially applied: root,
Node, framework, build command, install command and external-source setting
match, while `skipGitConnectDuringLink` is absent/null in readback. The project
has no Git Integration, custom domain, env or deployment; project SSO remains
`all_except_custom_domains`.

This is `STOP_DOCUMENTED`. The consumed PATCH cannot be retried implicitly.
Preview env, secret-source read, local link, deployment, SSO forward/rollback,
public probes and patient discovery did not start. Production, CI-3 and CI-4
remain unauthorized.

```text
DEDICATED_MOBILE_BFF_STATUS=IMPLEMENTED_NOT_DEPLOYED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0
VERCEL_LOCAL_LINK_ATTEMPTS=0
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_SKIP_GIT_CONNECT_DURING_LINK_SCHEMA
```

The next authority must reconcile the official current schema and proof for
`skipGitConnectDuringLink` without treating a new PATCH as an automatic retry.
It must decide whether the already-proven absence of Git Integration is
sufficient or authorize one new bounded settings action. No env, link,
deployment or public-ingress action may start before that authority is
published.

## Vercel Local-Link Control Reconciliation — 2026-08-26

The current authenticated OpenAPI and Vercel CLI 50.35.0 classify
`skipGitConnectDuringLink` as an optional deprecated boolean whose description
controls a CLI prompt. PATCH response and Project GET do not require its echo;
the current existing-project link flow does not consume it. Project `link` is
the provider-shaped material Git Integration state. Two independent reviews
approved, each at 0 Critical/Important/Minor:

```text
LINK_CONTROL_CLASSIFICATION=FIELD_REMOVED_OR_IGNORED_WITH_MATERIAL_GIT_LINK_ABSENT
SETTINGS_PATCH_PREVIOUS_ATTEMPTS=1/1
SETTINGS_PATCH_RETRY_AUTHORIZED=NO
PROJECT_GIT_LINK_BEFORE_LOCAL_LINK=ABSENT
LOCAL_LINK_COMMAND=VERCEL_LINK_PROJECT_EXPLICIT
LOCAL_LINK_REPO_FLAG=ABSENT
VERCEL_GIT_CONNECT_EXECUTED=NO
PROJECT_GIT_LINK_AFTER_LOCAL_LINK=PENDING
LOCAL_PROJECT_JSON_MATCH=PENDING
```

The six persistent settings remain approved; the old field-readback gate is
`SUPERSEDED`. Only after the documentation commit is remotely confirmed as
`LINK_SCHEMA_AUTHORITY_SHA` may one detached deploy worktree be created at
`/root/agentempp-ci3-dedicated-mobile-bff-deploy-v1`, exact implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`. The implementation worktree and
old CI-2 deploy worktree remain untouched.

One explicit local link is authorized in the dedicated worktree:

```text
vercel link --yes --project agentempp-mobile-bff-staging --scope gestao-9664s-projects
```

`--repo`, `vercel git connect` and `vercel git disconnect` are prohibited.
The local project metadata must match project/scope and contain no token,
secret or env; Project GET must still show `link` absent afterward. Only then
may the three-variable Preview env batch and one protected Preview deployment
proceed. Deploy metadata must include the exact implementation
`githubCommitSha` and be combined with detached clean SHA/tree and build
receipts, not treated as isolated cryptographic proof.

The original protected artifact review, one SSO forward, one fail-closed
rollback, public probes, receipt and read-only patient discovery remain
mandatory. Final documentation parent is `LINK_SCHEMA_AUTHORITY_SHA`:
PASS_COMPLETE moves `1.6.10→1.7`; PASS_PARTIAL or STOP_DOCUMENTED moves
`1.6.10→1.6.11`. Production, CI-4, Git Integration, custom domains, Production
env/deployment, Supabase/database writes, PR and merge remain prohibited.

## CI-3 Preview env batch STOP — 2026-08-26

The local-link authority was remotely published as
`fb1e0a3b76b831976f1e8b7f129758405b42e694`. A dedicated detached deploy
worktree was created at implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`, and one explicit existing-project
local link passed all local gates while Project `link` remained absent. No
`--repo`, Git connect, project creation, env or deployment occurred during the
link.

The one real Preview env batch attempt then failed at the Vercel client with
exit 1. Immediate metadata readback proves Preview/Production/Development env
`0/0/0`, deployments 0, Project `link` absent and SSO still
`all_except_custom_domains`. The diagnostic is represented only by SHA-256
`e71d492d1abf97ecf9d984116c77e83470ef08214c21805a6f6085a6528e01cf`;
no values or raw response were persisted or reported.

This authority is exhausted:

```text
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0/1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0/1
ENV_RETRY_AUTHORIZED=NO
DEPLOYMENT_AUTHORIZED=NO
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
```

Do not retry or delete env, deploy, change SSO, run public probes, create a
patient or start CI-4. Preserve the dedicated worktree and ignored local
`.vercel` metadata. The next executable gate is read-only:

```text
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_PREVIEW_ENV_BATCH_CLIENT_FAILURE_WITH_ZERO_REMOTE_ENV
```

That gate must diagnose the Vercel client/API contract from current schema,
installed implementation and verified zero remote state. Any new batch attempt
requires a separate published authority and fresh explicit budget.

## Vercel Preview env client reconciliation STOP — 2026-08-26

The exclusive read-only gate audited the preserved historical receipts,
installed Vercel CLI 50.35.0, current authenticated OpenAPI and zero remote
state. The CLI directly supports `--input -`; the three-object Preview body is
schema-valid; minimal HOME/auth/scope probes pass. The removed executor source,
argv and raw error preimage are not recoverable, so the historical client exit
1 cannot be classified more narrowly without invention.

The installed client also has internal default retries and unbounded
request/response parsing, which violates the current proposed mechanism's
one-request/no-auto-retry/bounded requirements. Both independent reviews
approved the fail-closed result at 0 Critical/0 Important/0 Minor.

```text
ROOT_CAUSE_PRIMARY=UNRESOLVED
ENV_BATCH_RETRY_AUTHORIZED=NO
VERCEL_ENV_TOTAL=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
VERCEL_DEPLOYMENT_COUNT=0
VERCEL_PROJECT_GIT_LINK=ABSENT
PROJECT_SSO_FINAL=all_except_custom_domains
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
PRODUCTION=UNTOUCHED
CI4=NOT_STARTED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE
```

No retry/delete, deployment, SSO, public probe, patient discovery, Supabase or
database write occurred. Preserve the configured project, local link metadata,
all worktrees and primary/live quarantine. A new published authority must
first establish semantic diagnostic preservation and a provably single-request
transport; this operation must not execute that next gate.

## CI-3 bounded Vercel one-shot authority — dossier 1.6.13

The historical client cause is permanently classified
`UNRECOVERABLE_NON_DECISIVE`; remote state is still env `0/0/0`, deployments
`0`, Project link absent and SSO active. The mutation client is replaced, not
re-diagnosed by invention.

The remotely publishable authority fixes the root-only V1 identities:

```text
TRANSPORT_SOURCE_SHA256=b21520e29d260a01cecff1bad17d5f05fb50bffd976aa664afec53bed36d06df
TRANSPORT_TEST_SHA256=fb5a222849adb3e6902dcc5015acf3608cf194ec5dd0103200f84abb621b6198
PREFLIGHT_RECEIPT_SHA256=25bb55fe10141d275a7fea582d3aedbb47712e711a4137b74513e65c80c0c539
SELF_TESTS=30/30_PASS
SOURCE_TEST_MODE=0400
```

The transport uses fixed Vercel API origin/TLS, one mutable request, zero
retry/follow, bounded bodies/headers and closed sanitized claim/receipt
semantics. It accepts only the exact three Preview env objects and exact SSO
forward/rollback bodies. Attempt receipt publication precedes readback; every
ambiguous, partial or failed gate preserves evidence and exits non-zero.

The source receipt is intentionally absent before publication. This section
supersedes only that impossible timing: after the exact authority commit is
fast-forward pushed and confirmed remotely, exactly one atomic root-owned
`0600` receipt may bind that SHA to the two published frozen hashes. No mutable
mode may run earlier. The exact path is
`/root/.config/agentempp/control-plane/ci3-vercel-one-shot-v1.source.receipt.json`;
the JSON contains only `authority_sha`, `source_sha256`, `test_sha256`, and
`rollback_authorized=true`. Publication requires immediate absence,
same-directory `O_EXCL|O_NOFOLLOW` temp creation, complete write/file fsync,
atomic no-overwrite hard link, parent fsync, unlink of only the temporary link,
second parent fsync, and final root/0600/regular/non-symlink/link-count-one
descriptor verification.

After receipt and complete Phase E revalidation, one env batch may run. Exact
success is POST request 1/retry 0/HTTP 201/three exact created/zero failed,
followed by GET inventory `3/0/0`. Only that state unlocks one protected Preview
deployment at implementation SHA `e3e1e252b48e42554e75899b950692c05186f60d`,
then protected artifact review, one SSO forward and public probes. Probe failure
permits only one provenance-bound protective rollback; no reprobe.

```text
ONE_SHOT_TRANSPORT_DOCUMENTATION_COMMIT_ATTEMPTS=1
ONE_SHOT_TRANSPORT_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Those two Phase D budgets are active under the current operation authority.
Only confirmed remote publication activates the following operational
budgets:

```text
VERCEL_PREVIEW_ENV_ONE_SHOT_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_FORWARD_ONE_SHOT_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ONE_SHOT_ATTEMPTS=1
```

Settings PATCH, local link, project creation, CLI env and implementation
publication remain exhausted/closed. CI-3 remains unauthorized until
`PASS_COMPLETE`; Production, primary/live, Supabase/database writes, CI-4,
TestFlight and App Store remain prohibited for every outcome.
If this authority commit or push fails, stop `STOP_PRE_AUTHORITY` without
creating the source receipt, opening staging values or issuing POST.

## CI-3 Vercel one-shot Phase E review STOP — dossier 1.6.14

The V1 authority was published at
`af03a01be7103fa63254da4e95de8b19cc6d78d4`, and the immutable source receipt
successfully bound that authority to the frozen source/test hashes. Phase E
passed all manager, worktree, source, receipt, staging metadata/fingerprint and
primary-denylist checks. No mutable claim or attempt receipt existed.

The required final read-only review nevertheless produced one blocking
Important. `performMutableWithReadback` returns before Env GET after timeout,
socket error, non-201 or a partial POST response. It preserves zero-retry and
the attempt receipt but cannot establish whether the remote inventory is zero,
partial or complete. Because any Important blocks the authority, the env POST
was not executed. Deployment, SSO and probes were not started.

```text
FINAL_STATUS=STOP_DOCUMENTED
VERCEL_ENV_DIAGNOSTIC_EVIDENCE_STATUS=RECONCILED
VERCEL_ONE_SHOT_TRANSPORT_STATUS=AUTHORIZED_NOT_EXECUTED
VERCEL_PREVIEW_ENV_BATCH_STATUS=NOT_EXECUTED
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
ENV_ONE_SHOT_REQUESTS=0/1
PREVIEW_DEPLOYMENTS=0/1
SSO_FORWARD_ATTEMPTS=0/1
SSO_ROLLBACK_ATTEMPTS=0/1
DEDICATED_MOBILE_BFF_STATUS=IMPLEMENTED_NOT_DEPLOYED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
PRODUCTION=UNTOUCHED
CI4=NOT_STARTED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_ENV_ONE_SHOT_AMBIGUOUS_POST_READBACK
```

Do not modify or execute the frozen V1. The next gate requires a new versioned
helper and authority that persist the unique POST evidence and implement a
bounded read-only settlement/quiescence protocol after ambiguous/partial
outcomes. One immediate GET is not proof because the remote POST may complete
later. The authority must specify GET budgets, stability conditions and an
inconclusive terminal state, classify stable zero, partial or exact-three state,
cover late completion in tests, and never issue a second POST. The complete STOP
evidence is in
`docs/superpowers/evidence/2026-08-26-ci3-vercel-one-shot-env-or-mobile-bff-stop.md`.

## CI-3 Vercel single-object Preview upsert authority — dossier 1.6.15

The V1–V4 transport line remains frozen and unexecuted. The batch array is
rejected because Vercel CLI 50.35.0 does not serialize arrays through its JSON
body branch. A plain object is parsed from stdin, serialized with
`JSON.stringify` and sent as `application/json`; official OpenAPI accepts the
single object, `upsert=true`, `encrypted`/`sensitive` and Preview target. The
no-network synthetic proof and two independent reviews passed at 0 Critical,
0 Important and 0 Minor.

After remote publication of the 1.6.15 authority, CI-3 staging may resume only
as three sequential logical invocations, one immutable object per key and one
invocation per key. CLI internal retries reuse that same object and are
accepted only with `upsert=true`; no outer retry, second invocation, delete or
correction exists. A durable no-clobber claim is published before each call.

Metadata-only Env GET snapshots at +15, +30 and +60 must be identical before
the next key: URL encrypted gives total 1, anon encrypted gives total 2 and
service role sensitive gives total 3, always Preview-only with Production and
Development zero. Any zero, partial, duplicate, wrong, oscillating or
inconclusive state is STOP. A nonzero CLI result may pass only as
`COMMAND_AMBIGUOUS_REMOTE_VERIFIED` when stable remote metadata is exact.

Only stable `3/0/0` unlocks the already authorized one protected Preview
deployment. READY/source/surface review precede one SSO forward. Forward
Project GET at +10/+20/+40 must be stable; divergence is STOP without second
forward and without rollback. Only stable forward state unlocks probes. A
probe failure triggers the single frozen rollback, no reprobe and preserved
env/deployment. Patient discovery remains read-only.

Final outcomes use `SINGLE_OBJECT_AUTHORITY_SHA` as parent:

The contracts below wholly supersede every historical final-documentation
allowlist, dossier transition, subject and macro-prompt instruction, including
Task 15 from 2026-08-25. Historical outcome instructions are evidence only.

- PASS_COMPLETE: exact five-path allowlist
  (`docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-authority.md`,
  `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`,
  `docs/superpowers/specs/2026-08-27-ci3-today-staging-vertical-slice.md` and
  `docs/superpowers/plans/2026-08-27-ci3-today-staging-vertical-slice.md`),
  `1.6.15→1.7`,
  subject `docs(ios): authorize CI-3 after dedicated Mobile BFF verification`,
  one commit/push and integral Mac macro-prompt; authorize CI-3 on the Mac,
  CI-4 prohibited.
- PASS_PARTIAL: exact three-path allowlist
  (`docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`
  and `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`),
  `1.6.15→1.6.16`,
  subject `docs(staging): record verified dedicated Mobile BFF preview`, one
  commit/push and macro-prompt `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`
  without creating a user; CI-3 not authorized.
- STOP_DOCUMENTED: exact three-path allowlist
  (`docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-single-object-env-or-mobile-bff-stop.md`
  and `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`),
  `1.6.15→1.6.16`, subject
  `docs(staging): record single-object Preview env or Mobile BFF stop`, one
  commit/push and complete key/gate/count/exit/retry/readback/env/deploy/SSO/
  probe/preservation/Production/CI-3/next-gate record; CI-3 not authorized.

Every outcome also requires empty initial staging, exact allowlist,
`git diff --check`, full diff and sensitive-data scan, zero Production/CI-4,
two reviews at zero Critical/Important, selective staging without historical
paths, exact parent and one non-force commit/push with no tags, PR or merge.

Production/Development env, Production deploy, Supabase/database writes,
primary/live use, project creation, settings PATCH, local link, V1–V4, CI-4,
PR and merge remain prohibited. Detailed authority:
`docs/superpowers/evidence/2026-08-27-ci3-vercel-single-object-upsert-authority.md`.

## CI-3 single-object env PASS and unexpected Production deployment STOP — dossier 1.6.16

The three authorized single-object upserts passed with one logical invocation
per key, command exit 0 and stable metadata-only readbacks at +15/+30/+60.
The final environment inventory is exactly Preview/Production/Development
`3/0/0`; there was no external retry, second invocation, correction or env
delete. V1–V4 remained frozen and unexecuted, and the primary/live secret was
never opened.

The sole deployment command was executed without `--prod`, alias, domain,
promotion, redeploy or Git connection. It exited 0 and the artifact became
`READY` with the exact implementation source SHA, but two independent
read-only observations classified its remote target as `production` instead
of the required `preview`. Therefore the deployment target gate failed and
the operation ends as `STOP_DOCUMENTED`.

No deployment retry, promotion, alias, delete, SSO forward, rollback or probe
is authorized or was executed. The original SSO state, exact env inventory,
unexpected remote artifact and all bounded evidence remain preserved. This is
not “zero Production”: `PRODUCTION_UNTOUCHED=NO`, because Vercel classified the
artifact as Production even though the caller did not request a production
deployment. Supabase/database writes remain zero; CI-3 remains unauthorized
and CI-4 has not started.

This section supersedes only the continuation gates of the 1.6.15 operation.
No external mutation may resume until a new authority reconciles the target
classification and explicitly defines a bounded recovery. The exact next gate
is `RECONCILE_UNEXPECTED_VERCEL_PRODUCTION_TARGET_AND_AUTHORIZE_RECOVERY` on
the VPS. Full evidence:
`docs/superpowers/evidence/2026-08-27-ci3-single-object-env-or-mobile-bff-stop.md`.

## CI-3 first CLI Production bootstrap recovery authority — dossier 1.6.17

The unexpected target is classified
`FIRST_CLI_DEPLOYMENT_BOOTSTRAP_PRODUCTION`: the general Vercel CLI contract
says no `--prod` means Preview, while official historical and current Vercel
Labs references describe the first deployment of a new CLI-created/linked
project initializing Production and later deployments returning to Preview.
This explains the observation but does not make the original artifact valid
staging.

The remotely publishable authority preserves env `3/0/0`, the sole original
Production/READY/exact-source artifact, generated aliases, active SSO and all
root-only evidence. Only after its exact four-path commit is remotely confirmed
may one second deploy use explicit `--target=preview`. Remote target, READY,
source/root/Node/framework and absent Git Integration are mandatory; any
failure preserves all deployments, prohibits a third attempt and never unlocks
delete.

Only a distinct verified Preview permits one removal of the original raw
deployment ID from the incident receipt. URL, project name, wildcard, Preview,
project, env and domain removal are prohibited. Three readbacks must converge
on Production `0`, Preview `1`, total `1`, exact Preview preserved, original
aliases absent, custom domains zero, link absent, env `3/0/0` and SSO active.
There is no second delete.

SSO remains active through Review C. Immediately before the single forward,
fresh Project GET must prove the remote object structurally/canonically equal
to the frozen original; “active” alone is not enough. If forward/readback is
ambiguous, original exact means STOP without rollback, null consumes the one
shared rollback and requires stable restoration, and unresolved means STOP
without mutation plus escalation. That one rollback budget is shared with a
later public-probe failure and cannot be used twice.

Final outcomes use `PRODUCTION_RECOVERY_AUTHORITY_SHA` exclusively and
supersede every historical final allowlist:

- PASS_COMPLETE uses exactly the handoff, dedicated Mobile BFF authority
  evidence, this naming-neutral plan, Today vertical-slice spec and Today
  vertical-slice plan at the literal paths frozen in the recovery authority;
  `1.6.17→1.7`, subject
  `docs(ios): authorize CI-3 after dedicated Mobile BFF verification`.
- PASS_PARTIAL uses exactly the handoff,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`
  and this naming-neutral plan; `1.6.17→1.6.18`, subject
  `docs(staging): record verified dedicated Mobile BFF preview`, next gate
  `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`.
- STOP_DOCUMENTED uses exactly the handoff,
  `docs/superpowers/evidence/2026-08-27-ci3-production-target-recovery-stop.md`
  and this naming-neutral plan; `1.6.17→1.6.18`, subject
  `docs(staging): record Production target recovery stop`, with the material
  next gate and no broader cleanup. The historical single-object STOP evidence
  path is evidence-only and is not executable for this recovery outcome.

Every outcome keeps primary/live, Supabase/database writes, product production,
CI-4, TestFlight/App Store, settings/env changes, Git Integration, force, tags,
PR and merge prohibited. Detailed executable authority:
`docs/superpowers/evidence/2026-08-27-ci3-first-deployment-production-recovery-authority.md`.

## CI-3 dedicated Mobile BFF Preview verification — dossier 1.6.18

The remotely published recovery authority was executed within all bounded
budgets. One second deployment became the semantic Preview at the exact
implementation SHA. The original first-CLI bootstrap Production deployment
was removed once by exact ID and settled at +10/+20/+40 with Production `0`,
Preview `1`, total `1`, aliases `0`, env `3/0/0`, absent Project link and active
SSO. There was no third deployment or second delete.

Protected Review C passed at 0 Critical and 0 Important. The artifact contains
40 Mobile API routes and zero admin routes, authored pages, Server Actions or
middleware. The sole SSO forward stabilized as null at +10/+20/+40; shared
rollback remained unused. Public probing passed 30/30: three Mobile 401
contracts, eight base forbidden routes and all 19 frozen prior findings. The
root-only final deployment receipt is stable and holds the only raw origin.

Read-only staging discovery then found no Auth user, no eligible explicitly
synthetic patient and no approved runtime patient credential. It created no
user/profile/password/session and performed no database write. Therefore this
operation terminates `PASS_PARTIAL`, not `PASS_COMPLETE`:

```text
VERCEL_FIRST_DEPLOYMENT_CLASSIFICATION=FIRST_CLI_DEPLOYMENT_BOOTSTRAP_PRODUCTION
VERCEL_BOOTSTRAP_PRODUCTION_RECOVERY=VERIFIED
VERCEL_ORIGINAL_PRODUCTION_DEPLOYMENT=REMOVED
VERCEL_ACTIVE_PRODUCTION_DEPLOYMENT_COUNT=0
VERCEL_ACTIVE_PREVIEW_DEPLOYMENT_COUNT=1
VERCEL_RECOVERY_PREVIEW_TARGET=VERIFIED
VERCEL_PREVIEW_ENV_COUNT=3
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
PRIMARY_LIVE_PRODUCT_PRODUCTION_TOUCHED=NO
DEDICATED_MOBILE_BFF_STATUS=VERIFIED
STAGING_BFF_STATUS=VERIFIED
SYNTHETIC_PATIENT_PATH=MISSING
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING
```

The verified Preview must be preserved. The next gate is an authoring-only VPS
operation: it must design, independently review and publish the bounded
authority for a later execution to provision only a synthetic staging patient
and approved patient-token mechanism, then stop before any creation. The
future authority must prohibit a service-role bearer as the patient token,
changes to primary/live or product Production, CI-4, Preview removal/redeploy,
changes to the three Vercel envs and repeated SSO/delete operations.

Full outcome evidence:
`docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`.

## Synthetic staging patient provisioning authority — dossier 1.6.19

The authoring-only gate has frozen a later one-patient staging operation. It
does not execute that operation. The verified dedicated BFF remains one READY
semantic Preview at implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`, with Production `0`, env
Preview/Production/Development `3/0/0`, SSO `null` and the published public
probe set `30/30`. Project ref is exactly `xitugspwfxkcluxvrdeg`; primary/live
is outside the trust boundary.

The source and live staging schema establish three mandatory boundaries:

1. one confirmed Supabase Auth identity with the exact synthetic app-metadata
   marker;
2. one active domain patient created canonically by a patient-bearer
   `GET /api/mobile/v1/me` through `bootstrap_patient_profile()`;
3. one active `bodyflow_full` entitlement created by the trusted-backend
   `apply_entitlement_event` RPC.

`/me` and `/entitlements` are entitlement-exempt. `/today` is not and returns
402 without active access. No manual profile insert, direct entitlement table
write, patient self-grant or service-role patient bearer is authorized.

The frozen future grant is:

```text
ENTITLEMENT_KEY=bodyflow_full
ENTITLEMENT_SOURCE=manual
ENTITLEMENT_STATUS=active
ENTITLEMENT_PLAN=trial
ENTITLEMENT_ENVIRONMENT=sandbox
ENTITLEMENT_EVENT_TYPE=grant
ENTITLEMENT_REASON=ci3_synthetic_staging
ENTITLEMENT_START=GRANT_AT
ENTITLEMENT_ACCESS_EXPIRY=CREATED_AT_PLUS_14_DAYS
ENTITLEMENT_GRACE_EXPIRY=NULL
ENTITLEMENT_CANCEL_AT_PERIOD_END=false
ENTITLEMENT_ACTOR=one receipt-bound operation UUID
OPERATION_MARKER_PATTERN=ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>
ENTITLEMENT_SOURCE_REFERENCE=<OPERATION_MARKER>
ENTITLEMENT_PROVIDER_EVENT_ID=<OPERATION_MARKER>-grant
ENTITLEMENT_RPC_ACCEPTANCE=result=applied,exact event ID,exact entitlement ID
```

Identity is generated only in the future as
`ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>@example.invalid`, with a CSPRNG
password of at least 32 random bytes, no phone/invite/real identity and exact
metadata `synthetic=true`, `environment=staging`,
`purpose=ci3_authenticated_today`, `schema_version=1` and
`expires_at=CREATED_AT_PLUS_14_DAYS`. The current official Auth path validates
e-mail syntax rather than DNS; if the real staging create rejects `.invalid`,
the operation stops without a second user or fallback identity.

The future exclusive operation claim, credential, provisioning receipt and
recovery receipt are exact root-only paths under
`/root/.config/agentempp/secrets`, regular `0600`,
no-symlink, link-count-one and atomic/no-clobber. Tokens remain memory-only.
Execution uses Node 24.14.0, Corepack/pnpm 10.33.2 and repository-resolved
`@supabase/supabase-js` 2.105.1 with separate admin/patient clients and session
persistence, auto-refresh and URL detection disabled.

The exact order is preflight, in-memory identifiers plus exclusive claim,
credential material, one Auth create/readback (with at most one read-only
settlement), one sign-in, one `/me` bootstrap/readback, one entitlement RPC
accepted only as `result=applied` plus exact readback, one `/entitlements`, one
`/today` and one atomic provisioning receipt. Every create,
sign-in, grant, readback and endpoint probe has a one-attempt budget; manual
profile writes, storage deletes, second user, second entitlement, outer retry
and existing-user mutation are zero/forbidden.

An ambiguous Auth create has one read-only settlement but preserves claim and
credential even on zero because completion may arrive late. An ambiguous
entitlement RPC likewise has one read-only settlement and otherwise preserves
the entire fixture without rollback. In every rollback branch the claim stays
as the durable guard; a recovery receipt is published before any safe
credential removal. Claim removal belongs only to separately authorized final
cleanup.

Rollback is bounded by exact IDs, synthetic markers and cardinality assertions.
For an invalid/partial fixture, one no-retry official Supabase `execute_sql`
invocation of the literal versioned `ROLLBACK_SQL_V1` transaction deletes exact
event, exact entitlement and exact patient in that order, then one Auth Admin
call deletes the exact Auth user. It is bound to the canonical 43-row inbound-
FK digest, locks the patient parent before counting and allows only profile
`1`, progress `1`, all other children `0`.
Unexpected FK children or an ambiguous count stops without broader deletion.
A structurally valid Auth/patient/entitlement whose later bearer validation or
probe fails is `PRESERVED_FOR_DIAGNOSIS`; it is not
auto-deleted or recreated. After `TODAY_VERIFIED`, rollback is forbidden and a
separate cleanup authority must remove the fixture no later than
`CREATED_AT_PLUS_14_DAYS`, including exact credential and claim removal while
retaining only sanitized receipts under their documented lifecycle.

Today acceptance requires HTTP 200 JSON, no-store, Vary Authorization,
matching header/envelope request ID, API v1, a data object, local date,
calculation version, sources, completion status and source provenance in every
applicable targets/consumed/Block 7700 structure. The body, PII, credentials,
tokens, raw IDs and raw Preview origin are never printed or persisted as
evidence.

Canonical authority hashes:

```text
SOURCE_CONTRACT_STREAM_SHA256=0540cb5ed3bdc903dd5feda1499fed0eb5fe5b6197c0365f09c19596d6ac44bf
BOOTSTRAP_FUNCTION_SHA256=94a5de8bc0126fbbc03d1879efaa1a03f6333cb53acc6e9c97362275e679f0ab
PATIENT_SCHEMA_EXECUTION_GATE_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
ENTITLEMENT_SOURCE_FUNCTION_SHA256=797feb1288d91e195dd86f7c878c9b87a6f6577d14b19e9cace31b4e42ba68e3
ENTITLEMENT_RESOLUTION_SHA256=c25d2d1218c0952d26215f7cef57b0f57c3f713ff8c25d8aa33c3771398ececc
TODAY_RELATIONS_AUTHORING_EVIDENCE_SHA256=af34e74b68050e264930df866e9094372261c23e684e85d2507830477381c903
TODAY_FUNCTIONS_AUTHORING_EVIDENCE_SHA256=ee15dcc08e3b767c13f2acfe395c9566ebced1d33127d7471b06eb58f5adfc89
SCHEMA_GATE_V1_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
PUBLIC_USERS_INBOUND_FK_STREAM_SHA256=a5fffce98a0c33f0fc4271de3e6c13a5993c12855da945074fa3ef87157a138f
```

The complete contract, state machine, rollback and integral next-operation
handoff are in
`docs/superpowers/evidence/2026-08-27-ci3-synthetic-staging-patient-provisioning-authority.md`.
Publication of this three-path documentation commit authorizes only the future
operation `EXECUTE_SYNTHETIC_STAGING_PATIENT_PROVISIONING_AND_AUTHENTICATED_TODAY`.
It does not execute it, authorize CI-4, mutate Vercel, open primary/live or
touch product Production.

## Synthetic Auth identity readback resume authority — dossier 1.6.20

The one authorized 1.6.19 execution created exactly one synthetic staging Auth
identity and stopped before sign-in because its launcher required byte-exact
e-mail equality. The credential's generated local part contained uppercase
characters, while the official Supabase Auth implementation canonicalizes the
address with `strings.ToLower` before persistence. Lowercase comparative hashes
agree across credential, Admin GET, Admin LIST and `auth.users`.

Read-only settlement proved Auth `1`, synthetic match `1`, one e-mail identity
and zero patient/profile/progress/entitlement/event/storage. Confirmation,
typed required app metadata, provider, role/audience, phone absence and
ban/delete/anonymous/SSO predicates are valid. Provider/provider-list
augmentation, first-provider user metadata, LIST identity projection and
null/empty fields are documented server or representation semantics.

```text
ROOT_CAUSE=CLIENT_EXPECTED_RAW_EMAIL_WHILE_AUTH_CANONICALIZED_EMAIL_TO_LOWERCASE
ROOT_CAUSE_CLASSIFICATION=NORMALIZED_ALIAS_DOCUMENTED
OFFICIAL_AUTH_SEMANTICS_STREAM_SHA256=14e3a6be89402808e485a87108d7a597bd28616b21c72bc255d8a7d4816cb169
LOCAL_AUTH_JS_SOURCE_STREAM_SHA256=0252913cf3003ec3224243b9f344793a2730a446f861d5c03a00405596b1dd2c
DIAGNOSTIC_MATRIX_SHA256=9ddba9fa79f46f82591a8b031f0c36298fd88394fd9e3edfacd188d24f98e812
REVIEW_A=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
REVIEW_B=GO_0_CRITICAL_0_IMPORTANT_1_MINOR_SUPPLEMENTAL_TEST_SEQUENCE
```

After this exact three-path documentation commit is remotely published, one
later VPS operation may resume only from `AUTH_USER_CREATED`. It must reuse the
preserved claim, credential, recovery receipt and exact Auth user, compare the
credential e-mail through documented lowercase canonicalization, and execute
the remaining sequence once: sign-in, `/me` bootstrap/readback, entitlement
grant/readback, `/entitlements`, `/today`, then provisioning receipt only on
complete success.

Create remains consumed `1/1`; a second create is forbidden. Auth update and
delete are `0/0`. Credential rewrite, claim overwrite/removal, recovery receipt
removal, deadline change and retry of a consumed gate are forbidden. Remaining
budgets are sign-in `0/1`, `/me` `0/1`, entitlement `0/1`, entitlement readback
`0/1`, `/entitlements` `0/1` and `/today` `0/1`. Original ambiguity,
preservation and rollback rules continue to apply after the resume point.

The cleanup deadline remains `2026-09-11T11:44:11.182Z`; cleanup still needs a
separate authority. Vercel, SSO, deployment, env, primary/live, product
Production, CI-3 and CI-4 remain unchanged and outside this authority. The
complete evidence and next-operation contract are in
`docs/superpowers/evidence/2026-08-28-ci3-synthetic-auth-identity-readback-diagnostic.md`.

```text
RESUME_AUTHORITY_STATUS=PUBLISHED_PENDING_COMMIT_IDENTITY
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RESUME_EXISTING_SYNTHETIC_AUTH_IDENTITY_AND_COMPLETE_AUTHENTICATED_TODAY
```

## Authenticated staging completion and CI-3 Today authority — dossier 1.7

The single authorized resume completed with `PASS`: it reused the existing
synthetic Auth identity, consumed each remaining attempt exactly once and
published a root-only `TODAY_VERIFIED` provisioning receipt. No second user,
Auth update/delete, token persistence, real-user mutation or service-role
patient bearer occurred.

Read-only settlement recorded exactly one Auth user, identity, patient,
profile, progress, entitlement and entitlement event, exactly one active
`bodyflow_full` access and zero storage. `/me`, `/entitlements` and `/today`
each returned HTTP 200 JSON with no-store, `Vary: Authorization`, matching
request identity and API-v1 envelope. Today satisfied the structural source,
provenance, completion, local-date and calculation-version contract. No raw
body, token, identity, origin, health data or project/deployment identifier is
part of Git evidence.

The dedicated BFF remains one semantic Preview `READY` at implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`, with zero Production deployment,
three Preview-only env entries, no project Git link, custom alias/domain/
environment or SSO. This authoring operation made no Vercel or Supabase write
and did not issue a token or call an authenticated endpoint.

The preserved synthetic fixture and four root-only artifacts remain bounded
by separate cleanup authority and the immutable deadline
`2026-09-11T11:44:11.182Z`. CI-3 must not clean them implicitly.

Publication of the exact five-path documentation commit authorizes only this
future Mac operation:

```text
OPERATION=IMPLEMENT_CI3_TODAY_STAGING_VERTICAL_SLICE
BASE_SHA=277873755bf29771a10b5f362b522c2e6a6c21d6
BASE_PARENT=aba177d7cbb0d9cecb13c5f1099e6b99b6456c93
BASE_TREE=9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4
BASE_SUBJECT=feat(ios): add secure session lifecycle and user boundary
BRANCH=codex/ci3-today-staging-v1
WORKTREE=/Users/eduardohenrique/Developer/bodyflow-ci3-today-staging-v1
COMMIT_SUBJECT=feat(ios): connect Today to authenticated staging
PUSH=ONE_NON_FORCE_WITHOUT_UPSTREAM
PR=NO
MERGE=NO
DEPLOY=NO
CI4=NO
```

The slice connects only the owner-only staging configuration bridge,
Supabase Auth staging, the existing CI-1/CI-2 session lifecycle,
`MobileAPITransport`, authenticated `GET /api/mobile/v1/today`, strict
header/envelope/DTO validation and Today presentation states. The server
remains authoritative for targets, consumed, balances, completion, progress,
protocol, Block 7700 and source provenance. All other product domains,
backend/migrations/assets/rebranding, Production, TestFlight, App Store and
CI-4 remain out of scope.

The Mac bridge may copy only the staging Supabase URL, anon/publishable key,
approved BFF Preview origin and the synthetic credential through encrypted SSH
pipes into owner-only `0600` files outside Git. It must never copy
`service_role`. Values must not appear in argv, stdout, history, logs,
screenshots or `xcresult`; the Debug-only simulator credential copy is removed
after import. Tokens remain inside the existing CI-1/CI-2 session boundary and
Release/beta without complete local configuration remains fail-closed.

Implementation is bound to the exact allowlist and TDD/test/build/scan/review
gates in:

- `docs/superpowers/evidence/2026-08-28-ci3-authenticated-today-staging-completion.md`;
- `docs/superpowers/specs/2026-08-28-ci3-today-staging-vertical-slice.md`;
- `docs/superpowers/plans/2026-08-28-ci3-today-staging-vertical-slice.md`.

This VPS operation does not create the CI-3 worktree, edit iOS, run Xcode,
repeat sign-in or any endpoint, mutate the fixture, execute cleanup, open
primary/live, or start CI-3/CI-4. The next environment is `MAC_LOCAL`; the
next gate is `IMPLEMENT_CI3_TODAY_STAGING_VERTICAL_SLICE`.

## CI-3 versioned bridge authority — dossier 1.7.1

The initial Mac CI-3 Task-1 worktree remains on CI2 HEAD
`277873755bf29771a10b5f362b522c2e6a6c21d6`, with empty staging and the same
five working paths. Task 2 is still blocked behind a bridge PASS.

V1/V2 are frozen superseded. V3 is frozen rejected after five review rounds:
Review A `0C/5I/1M`, Review B `0C/6I/1M`. Its `174/174` synthetic PASS did not
overcome the 11 independent static Important findings. There is no sixth V3
round and no V1/V2/V3 execution.

The replacement gate is `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1`:

1. a Git-tracked Node-core generator on the VPS validates five fixed root-only
   sources and emits only an immutable version-addressed public config plus a
   sanitized receipt; it never copies credential or emits service role;
2. after VPS PASS, Mac B0 is strictly local/no-network, then validates the real
   simulator before remote Git/SSH and validates a concrete version-addressed
   trust descriptor supplied and hash-bound by VPS PASS;
3. three one-shot reads use durable claims/results and zero refetch; the local
   receipt is pre-terminal and published receipt-last with `link(2)`
   no-replace; a config-only final pathname may be physically visible after a
   crash but is explicitly `UNPUBLISHED`, and no consumer may read/use it until
   the marker exists and the entire contract validates;
4. install/scans produce a separate versioned terminal receipt, then a
   privileged controller fixes it in an external root-owned O_EXCL immutable
   anchor outside the bundle's mutable domain, but only after a separately
   controller-supplied/hash-bound privileged-writer authority; missing
   authority STOPs and normal execution cannot infer or mint it;
5. only anchored PASS releases original CI-3 Tasks 2–11; authority label 12 is
   final report/preservation only, with the original 23 paths/parent/subject.

Tooling TDD records original RED `90/1/89` and GREEN `90/90`, remediation RED
`123/91/32`, second RED `125/123/2`, then GREEN `125/125`, zero fail/skip/todo,
final RED `126/125/1`, controller-finding RED `130/126/4`, authority-builder
RED `1/0/1`, then GREEN `131/131`, syntax PASS and synthetic local self-test
with the complete receipt schema and zero network calls. `--create`,
SSH, streams, simulator, providers, production, cleanup and CI-4 were not run.

```text
CI3_BRIDGE_ARCHITECTURE=VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1
CI3_BRIDGE_V3_STATUS=FROZEN_REJECTED
CI3_BRIDGE_V3_EXECUTED=NO
CI3_BRIDGE_GENERATOR_TRACKED=YES
CI3_BRIDGE_GENERATOR_TESTS=131_PASS
CI3_WORKTREE_PRESERVED=YES
CI3_IMPLEMENTATION_STARTED_BEYOND_TASK1=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
```

VPS handoff summary, not executed:

```text
OPERATION=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
AUTHORITY_SHA=CONTROLLER_PASS.authority_sha
AUTHORITY_PARENT=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_SUBJECT=build(ops): authorize executable CI-3 bridge tooling
GENERATOR=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_EXECUTION=/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs --create
OUTPUT=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA
CREATION_BUDGET=1
OVERWRITE=NO
CREDENTIAL_COPY=NO
SERVICE_ROLE_OUTPUT=NO
```

Mac handoff summary after VPS PASS, not executed:

```text
OPERATION=FETCH_VERSIONED_CI3_BRIDGE_BUNDLE_AND_RESUME_CI3
SIMULATOR_GATE=BEFORE_SSH
TRUST_DESCRIPTOR=VPS_PASS.ssh.trust_descriptor_path+trust_descriptor_sha256
SSH_EFFECTIVE_CONFIG=/usr/bin/ssh -G -F VERIFIED_CONFIG VERIFIED_DESCRIPTOR_ALIAS
REMOTE_READS=3_TOTAL_1_EACH
RETRY=NO
NO_REFETCH_AFTER_CLAIM=YES
LOCAL_BUNDLE=$HOME/.config/agentempp/ci3/bundles/AUTHORITY_SHA
LOCAL_RECEIPT=PRE_TERMINAL_PUBLICATION_ONLY
INSTALL=/usr/bin/install -m 0600
TERMINAL_RECEIPT=SEPARATE_VERSIONED_AFTER_INSTALL_AND_SCANS
TERMINAL_ANCHOR=EXTERNAL_ROOT_OWNED_O_EXCL_UCHG
CI3_ORIGINAL_TASKS=2_THROUGH_11_AFTER_BRIDGE_PASS
CONTINUATION_LABEL_12=FINAL_REPORT_ONLY
V1_V2_V3_EXECUTION=NO
CI4=NO
```

The complete STOP evidence, sanitized manifest, remote/Mac contract and
executable two-phase plan are:

- `docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md`;
- `docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md`;
- `docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md`.

### CI-3 executable bridge authority 1.7.1 addendum

The active successor contract is
`VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1_WITH_EXECUTABLE_MAC_CONTROLLER`. The prior
generator-only STOP remains historical evidence; V1/V2/V3 remain frozen and
must not run.

Task 1 is now split into the authorized bridge phases only: Git-bound launcher,
local simulator B0, native `ssh -G` trust proof, three claimed reads, receipt-
last local publication, physical simulator install/removal proof, the exact
ordered scans `argv`, `history`, `terminal-log`, `attachment`, `xcresult`,
`runtime`, and the separately authorized privileged terminal writer. Missing
receipt means unpublished. Missing original claim means
`REJECT_UNCLAIMED_EXISTING_STATE`. Missing privileged writer authority means
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`.

The authority consists of exactly thirteen Git paths: the five documentation
paths, generator and generator test, controller and controller test, launcher
and launcher test, writer source and writer test. It binds commit/parent/tree,
the ordered manifest, four components, Node/ssh/Swift/Xcode identities and the
remote/controller/simulator/terminal generations. A future controller commit
must be the single commit for all thirteen paths; no intermediate commit is
authorized.

After terminal PASS, continuity is unchanged: original Task 2 transport, Task
3 Today adapter, Task 4 dependency wiring, Task 5 Today states, Task 6 staging
integration, Task 7 XCUI, Task 8 focused/full gates, Task 9 unsigned builds,
Task 10 scans/reviews and Task 11 selective commit/publication. Label 12 is only
the final-report wrapper. The five existing paths and the exact 23-path
allowlist remain the paths listed in the versioned bridge spec §10.

This addendum authorizes tooling implementation and synthetic verification
only. It did not execute generator `--create`, SSH connect/network, simulator,
install, streams, VPS bundle, privileged writer, terminal anchor, Task 2,
Supabase/Vercel/production, commit or push. Handoffs are embedded in the
versioned bridge plan and dossier and must not run before final independent
reviews plus the single controller commit.

#### Executable dispatch and privileged boundary closure

The public controller modes are reachable production dispatches, not
unconditional STOP stubs. Given a valid Git-bound launch attestation and an
immutable root-owned Mac operation-authority receipt, each mode advances the
same persisted state machine to its declared phase. Tests invoke those paths
only through synthetic adapters; no real operational mode ran here.

The normal authority's writer object contains only the fixed
`authority_path` and `manifest_path`. After the exact ordered scans `argv`,
`history`, `terminal-log`, `attachment`, `xcresult`, `runtime`, the normal
controller prepares and freezes the writer source, signed binary, scan/evidence
set, terminal preparation receipt and manifest. It cannot create the
privileged authority. A separately authorized external controller must bind
those already-existing hashes and the original privileged claim in a
root-owned `CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1` receipt at the
versioned authority path, mode 0444 with `UF_IMMUTABLE`. Missing privileged-
writer authority is an explicit STOP; neither the future VPS PASS nor ordinary
Mac access conveys it.

Historical Round 1 synthetic counts were generator 152, controller 383,
launcher 46 and writer 122 (703 total); they are superseded by the Round 3
section. Original Tasks 2 through 11, the five preserved paths and exact 23-path
allowlist remain unchanged and unexecuted.

The future authority commit must record Git mode `100755` for the official zsh
launcher and Node controller, and `100644` for the separately compiled Swift
writer source. The launcher rejects any committed mode drift. The present
pre-commit `COMPONENT_MISSING` is expected because HEAD lacks the new blobs; a
synthetic thirteen-path commit proves the exact self-test transition to PASS.

#### Round 1 executable remediation and continuity boundary

The single future authority subject is now
`build(ops): authorize executable CI-3 bridge tooling`; parent remains
`9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52`. The authority manifest is exactly
the five docs plus generator/test, controller/test, launcher/test and writer/
test listed in the bridge spec §13.1. Final OIDs/SHA-256 values are resolved
from that one commit with `git rev-parse "$AUTHORITY_SHA:$PATH"` and
`git cat-file blob "$AUTHORITY_SHA:$PATH" | shasum -a 256`, then persisted in
the controller PASS; they are not self-referential constants inside the blobs.

The future VPS entrypoint is the root-owned snapshot
`/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs`.
It is materialized from `git cat-file`, checked against blob OID/SHA-256 and
executed by the Node path/hash supplied in the controller PASS, first
`--self-test`, then `--create`. Its generation claim, staging, no-replace
links and receipt-last boundary make receipt absence `UNPUBLISHED`; recovery
does not rerender, reread inputs or allocate a new generation.

On Mac, the official executable entrypoint remains
`/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh <mode>`. Operational modes need a
root-owned immutable Node and `mac-operation-authority.v1.json` installed by an
external publisher. B0's seven physical simulator claims/results precede
remote Git/read; SSH begins with native `/usr/bin/ssh -G`; fetch is exactly
three claimed `exec /usr/bin/cat -- <receipt-path>` reads into same-fd captures;
publication is receipt-last; install persists physical readback; and all six
surface-specific scans are reopened at terminal time.

The privileged terminal publisher is a separate authority. It compiles with
`/usr/bin/xcrun swiftc -parse-as-library`, signs and installs the exact writer
under the version-addressed root authority tree as root:wheel `0555`,
single-link and `uchg`; then publishes the original claim and privileged
authority receipt `0444`/`uchg`. Normal execution cannot do so. Missing
publisher authority STOPs explicitly and no VPS/Mac handoff implies it.

Historical Round 1 gates were generator 152, controller 383, launcher 46 and
writer 122: 703 total; the Round 3 section is current. This is code evidence only. No real bridge mode,
publisher, privilege, SSH, simulator, install, anchor, commit/push or Task 2
ran. Original Tasks 2–11, five preserved paths and 23-path allowlist remain
unchanged behind terminal PASS.

### CI-3 Round 2 executable authority closure

The prior statement that root publishers were external/unimplemented is
superseded. The Git-bound launcher now exposes separately authorized
`publish-operation-authority` and `publish-privileged-writer-authority` modes.
The first consumes the VPS PASS plus an exact human authorization receipt and
publishes an immutable versioned Node/controller/operation authority and six
typed scan collectors. The second runs only after scan, consumes a distinct
manifest-bound human receipt, publishes the original root claim before the
writer, and creates the privileged authority receipt from the installed
writer's physical identity. Neither publisher ran during authoring.

Durable recovery now treats a claim without a physical receipt as consumed and
ambiguous: it STOPs and never repeats the effect. A present receipt is reopened
no-follow and its bytes plus full metadata are rehashed before result/event
recovery. Local publication is a single descriptor-bound
`renameatx_np(RENAME_EXCL)` of the complete staged directory; unclaimed bundle
or simulator destinations are rejected. The Swift writer receives and
semantically recomputes the literal authority manifest, all read roots, seven
simulator claim/receipt/result triples, seven controller triples, install and
the six surface-specific scan receipts.

The 48 Round 2 E2E cases, now superseded by Round 3, were eight durable phases by six distinct crash boundaries,
each using the same state-machine recovery rules and asserting no repeated
effect. Original Tasks 2–11, label 12, the five preserved paths and exact
23-path continuation allowlist are unchanged. Task 2 remains blocked until a
future real terminal PASS and independent `0C/0I` reviews.

### CI-3 Round 3 executable authority integration boundary

This section supersedes earlier 703-test, 48-E2E, 59-role and prepublished scan
surface statements. Publisher 1 now consumes a schema-exact VPS publisher
input manifest and VPS operation-authority PASS, both hash-bound to operation
authority, Node, generations, collector contracts and the transfer payload.
Its separate human receipt binds those two inputs. The publisher installs the
immutable runtime/authority/PASS/manifests; it does not install terminal scan
surfaces. Missing transfer-controller or privileged-publisher authority remains
an explicit STOP and is not inferred from future VPS/Mac access.

B0 revalidates absent config, credential and ACK before original simulator
claims. Typed phase observers re-open actual effect targets, and recovery runs
only observers, never effects or retroactive adoption. SSH provenance keeps the
public-key byte digest separate from the fingerprint-output digest. The six
literal scan surfaces are generated after the operation's final sources exist,
from fixed authenticated roles in the current generation, then scanned and
reobserved with independent tool/command/schema/output/counter receipts.

The pre-terminal manifest has 62 evidence roles and includes controller phase
triples through `RUN_SCANS`. Its physical result roots two subsequent contracts,
`INVOKE_WRITER` and `VERIFY_ANCHOR`, so the anchor never authorizes itself. The
privileged writer recomputes claims/results/commands/captures, authority and
source roots, remote/local/SSH/simulator/install relations, all phase chains,
six scanner relations and terminal settlement before emitting `TERMINAL_PASS`.

Fresh synthetic counts are generator 152, controller 408, launcher 108 and
writer 128: 796 total with zero fail/cancel/skip/todo. The operational matrix is
60 scenarios (ten durable phases by six crash boundaries); each invokes the
official Git-bound launcher and compiled synthetic writer. No operational mode,
VPS/Mac transfer, network, SSH, simulator, install, privilege, anchor, Task 2,
commit or push ran. The original Tasks 2–11/report 12, five preserved paths and
exact 23-path allowlist remain frozen behind a future independently reviewed
terminal PASS.

### CI-3 Round 4 executable authority integration boundary

This section supersedes the Round 3 statement that the pre-terminal writer
emits PASS and the 796-test count. The pre-anchor is now strictly
`PRE_ANCHOR_PENDING_SETTLEMENT/PENDING_VERIFICATION`. A distinct later
root-owned append-only/no-clobber settlement reopens the actual
`INVOKE_WRITER` and `VERIFY_ANCHOR` triples; only it may declare
`TERMINAL_PASS`.

The VPS PASS is no longer merely hash-bound user material. It is signed with an
externally provisioned Ed25519 issuer whose real public key must arrive in a
root-owned immutable, versioned authority receipt. The repository contains no
production key. Publisher 1 installs and then reopens the operation authority,
VPS PASS, issuer, human receipt, publisher manifest, SSH descriptor/public key
and Node/controller runtime. Human-receipt source swap is detected by the
privileged target hash and the post-prompt immutable readback.

The writer reconstructs the complete 13-line authority manifest, verifies the
external signature and root paths, recomputes the public-key bytes and actual
`ssh-keygen` fingerprint, compares local components/generations and reopens
each authority-fixed phase target. A settled controller event never suppresses
the current typed physical observer. `RUN_SCANS` binds actual fixed sources and
generation-bound surfaces for the six independent literal IDs; it never
renames a journal receipt as a source.

The 60 operational cases now enter through the executable Git-bound launcher,
inject a selected crash into the production state machine, resume or
fail-close without effect replay, and invoke the Swift test build as the real
`INVOKE_WRITER` effect. The final suite dimension is 152 generator + 434
controller + 108 launcher + 137 writer = 831; the implementation report
records the fresh final gate.

This remains an authority-only preparation. Missing real issuer or privileged
writer authority is `STOP_PRE_AUTHORITY`, not a future implied permission. No
real VPS/Mac transfer, SSH/network, simulator mutation, root install, admin
prompt, anchor, Task 2, commit or push ran. Original Tasks 2–11/report 12, five
preserved iOS paths and exact 23-path continuation allowlist remain unchanged.

## Round 5 executable authority correction — supersedes every earlier `--settle` description

The terminal lifecycle now has one privileged writer invocation only. The
controller invokes the root-owned, immutable, version-addressed writer once
with `--write`. That same process validates the frozen manifest and external
roots, publishes and reads back the pending pre-anchor, derives and publishes
the complete `INVOKE_WRITER` and `VERIFY_ANCHOR`
claim/physical-receipt/result chains, scans the final terminal bytes with all
six literal scanners, and publishes and reads back
`terminal-settlement.json`. `--settle` is not a public or private mode and
returns `MODE_INVALID`; there is no second elevation or second prompt.

`TERMINAL_PASS` is derived only inside that root transaction. It binds all
four generation IDs, the authority receipt hash, the pre-anchor hash, both
contract hashes, every claim/receipt/result edge, the ordered terminal phase
graph, physical target observations, and the terminal-final six-scan root.
The normal executor may reopen and recompute this graph but cannot supply a
terminal triple or settlement manifest.

Remote read bindings are derived again by the writer from the root-owned
operation authority. Each exact path is paired with exactly
`exec /usr/bin/cat -- <authority-path>`; the bootstrap claim, each read claim,
each read result, and the terminal input manifest must match those independent
derivations. The same operation authority contains the ordered per-phase
target contracts. Role, state, path hash, owner allowlist, mode allowlist and
immutability policy must match exactly; a fully rehashed alternate regular
file is rejected.

The six scans remain distinct and ordered: `argv`, `history`,
`terminal-log`, `attachment`, `xcresult`, `runtime`. The controller
collects complete argv, journal/history bytes, event/log bytes, attachment
bytes and only the closed sanitized runtime allowlist/process identity. The xcresult observation uses the
fixed generation-addressed operational result path, with an authenticated
absence receipt when it does not exist. The privileged transaction performs a
second terminal-final scan over current journal/output, the new pre-anchor,
phase objects, actual settlement and writer output, then publishes the bound
`complete-result.json` last.

Publisher 0 is a controller mode reachable only through the separately
installed root-owned immutable external bootstrap. The user-owned worktree
launcher rejects it. The bootstrap verifies the external issuer, fixed runtime
and full root directory chain before reading the fixed issuer/request/key
inputs, signs Ed25519, creates the PASS no-clobber, fsyncs, freezes and reopens
it. No real key is embedded; missing external provisioning is
`STOP_PRE_AUTHORITY`.

Synthetic crash coverage now invokes the actual Swift test writer as the
`INVOKE_WRITER` phase effect, and `VERIFY_ANCHOR` reopens the artifacts from
that same causal run. A crash after a durable claim but before any physical
effect is not healed by replay: it deterministically returns
`STOP_CLAIM_CONSUMED_NO_RESULT` and publishes no anchor. Other boundaries
recover with at-most-once effects and exact-existing readback.

All real authority inputs remain absent in this implementation operation.
Therefore `STOP_PRE_AUTHORITY` remains the only current operational status;
no VPS publisher, SSH/network, simulator, admin prompt, root publication,
anchor, Task 2, commit or push was executed.

Each matrix case now uses two distinct Git-bound controller processes: the first exits at the selected synthetic crash, and the second reconstructs maps, physical target bindings, effect counts and journal state exclusively from the durable scenario snapshot before recovery or STOP.

## Round 6 continuation gate

Tasks 2–12 remain frozen. Continuation requires the separately installed
root-owned Publisher 0 bootstrap, authenticated VPS PASS/transfer, root-owned
immutable Mac operation authority and SSH generation snapshot, semantic raw
terminal scans, and a single privileged writer transaction ending with a
read-back `complete-result.json`. The worktree launcher is never Publisher 0;
all `after-claim` cases fail closed without replay or retroactive adoption.
Until these real external authorities are supplied and verified, the only
authorized continuation result is `STOP_PRE_AUTHORITY`.

The 60 local crash/restart cases prohibit a terminal fixture created before the
protocol. The active Git-bound controller materializes synthetic writer inputs
only at `INVOKE_WRITER`, after reopening its own durable snapshot. That snapshot
is byte-stable across the helper, becomes the exact
`controller-durable-state-root` evidence role, and is bound by path/scenario/
content hashes checked again by the Swift test writer. `after-claim` never
adopts an effect or creates the role. This closes test provenance only; it does
not relax the real external authority STOP or authorize Task 2.

## Round 8 continuation mapping

The original Tasks 2–11 plus report Task 12 remain literal and unchanged. The
new executable authority work is a prerequisite gate, not a replacement task:

```text
external Publisher 0 issuer/bootstrap
  -> signed VPS PASS + authenticated eleven-role transfer
  -> external Publisher 1 bootstrap
  -> sixteen root-owned immutable Mac targets + five-file SSH snapshot
  -> B0 local/simulator gate
  -> existing CI-3 phase machine
  -> one privileged writer transaction and VERIFY_ANCHOR
  -> PRE_TERMINAL_UNPUBLISHED
  -> privileged marker-last terminal transaction
  -> retained-byte terminalizer validation/emission
  -> TERMINAL_PASS
  -> original Task 2 eligibility
```

The external and installed launchers must validate the ten-line authority and
use fixed Node/controller bytes under `env -i`; the worktree launcher cannot
run any publisher or operational mode. Publisher 0 uses Node-core retained
descriptors on Linux and the already authorized Swift `openat` helper on
Darwin; Python is not part of the toolchain. Publisher 1 installs the launcher
authority and exact SSH snapshot in the same no-clobber root. `status` remains
pre-terminal until the privileged root-owned marker exists and revalidates
every final surface.

This mapping authorizes no current VPS/Mac/root/network/simulator/anchor action.
The real issuer/bootstrap/operation/writer authorities are not present, so the
only present operational outcome remains `STOP_PRE_AUTHORITY`.

## Round 9 continuation gate

The prior normal-owned terminal tail receipt is removed from the authority
model. A normal journal can only reach `PRE_TERMINAL_UNPUBLISHED`. The single
privileged writer invocation owns anchor write/readback, settlement,
actual-journal/raw-output scans, complete/final-scan validation and the last
root-owned immutable `CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1`. The launcher
uses the fixed controller terminalizer to validate that marker and emit its
already retained bytes; no post-scan pathname open is permitted.

The Publisher 0 -> Publisher 1 prerequisite is executable once its external
roots exist: Publisher 0 signs the eleven-role transport; the Mac requires a
fixed root-owned immutable materializer authority, issuer receipt and Swift
binary; the normal side snapshots retained authenticated sources; and the
privileged materializer independently verifies external signature and
relationships before a durable claim. All source and ancestor walks are
descriptor-relative/no-follow. One complete staging directory is promoted
no-clobber, frozen, fsynced and read back. Recovery reobserves the claimed
effect without refetch or prompt replay and never adopts an unclaimed/partial
tree.

The original Tasks 2–11 and report Task 12 remain literal and frozen. Their
eligibility requires a real privileged marker after all four generations and
all phase/scan roots validate. Because no external issuer/materializer/
operation/writer authority exists in this local implementation run, the
current outcome remains `STOP_PRE_AUTHORITY`; no real continuation occurred.

## Round 10 frozen integration amendment

This amendment preserves the original Tasks 2–11 and report Task 12 but
changes the prerequisite terminal handoff. The normal controller owns only the
eight pre-terminal phases, their actual six-surface scans, the COMPLETE
commit-contract event and reversible journal frame. It then performs exactly
one privileged writer invocation and emits no later normal bytes. The writer
owns both privileged phase triples, final scans, COMPLETE/output frames and the
external append-only settlement; its no-clobber PASS marker is the last object.
No valid marker means `PRE_TERMINAL_UNPUBLISHED`, regardless of earlier files.

Publisher 1 additionally requires the external V2 materializer authority bound
to one fixed request path/hash/full physical identity and one exact receiver
descriptor identity. Production rejects stdin, suffix/path-free selection and
alternate roots. Controller recovery observes the fixed root claim/result/tree
first and never repeats the admin child for settled state. The root transaction
constructs and fsyncs staging, performs exclusive promotion, then freezes and
readbacks destination; any claim-only, partial, unclaimed or divergent state
STOPs with evidence preserved.

The local non-synthetic Darwin probe and synthetic 60-scenario launcher/writer
matrix verify these mechanics without installing external authority. They do
not authorize the original continuation. No real privilege, receiver, SSH,
network, simulator, terminal anchor or Task 2 was used, so the frozen plan
remains at `STOP_PRE_AUTHORITY`.

## Round 11 frozen integration amendment

The Publisher 1 prerequisite now includes a closed ordered physical manifest
for all sixteen receiver leaves. Role/path/content, owner, group, `0600`,
single-link status, size, mtime, device, inode and identity must agree across
external authority, request, retained descriptor read, original claim and
result. This is part of the frozen prerequisite for the five preserved iOS
paths and exact 23-path continuation allowlist; it does not alter or start the
original Tasks 2–11 or report Task 12.

The terminal prerequisite is likewise marker-only. A controller restart must
validate the complete privileged marker root or resume the exact authorized
writer prefix; no five-file or internal-state shortcut can confer PASS. Crash
recovery includes the frame/marker/freeze windows, and `resume` reports
`TERMINAL_PASS` only after privileged `terminalStatus` validation. The single
root writer invocation is a transient same-binary supervisor, so worker crash
does not cause a second `osascript`; controller restart only observes/waits.
Supervisor death without a marker and absence of any external issuer/
materializer/operation/writer authority both keep the frozen integration at
`STOP_PRE_AUTHORITY`. No real continuation action occurred in Round 11.

## Round 12 frozen integration amendment

The frozen continuation prerequisite now includes the immutable publication
edge itself. A post-fsync/pre-`UF_IMMUTABLE` terminal file may be finished only
by the same validated privileged claim and only after descriptor-stable exact
bytes, physical identity, parent entry, flag and readback succeed. An
unclaimed exact-looking file is not recoverable authority.

The prerequisite marker is an exact eighteen-root transitive proof, not the
former nine-file subset. It covers pre-anchor, writer output, terminal final
scan and both privileged phase triples in addition to the existing authority,
journal/output, settlement and COMPLETE roots. Directory sets and metadata,
file immutability, all four generations, fixed paths, phase graph and physical
observations are recomputed by the common reader. Any missing, extra or mutated
root leaves the original Tasks 2–11 and report Task 12 ineligible.

Round 12 changed no continuation path and executed no real continuation,
external authority, privilege, network, SSH, simulator or anchor. The frozen
integration therefore remains `STOP_PRE_AUTHORITY`.

## Round 13 frozen integration amendment

Eligibility for the original Tasks 2–11 and report Task 12 now requires the
single canonical terminal-corpus validator used by operational `status`,
`resume`, recovery and tail emission. Marker hash consistency alone is not
sufficient. The exact privileged authority receipt must validate against the
fixed manifest and retained writer identity, and the complete Swift pre-anchor
must recompute every authority/component/generation/path/provenance/claim,
ordered external-root/phase-target/scan/finding set, timestamp and policy
relationship before settlement and marker validation.

A self-consistently rehashed but semantically invalid inner root remains STOP.
Only the complete unmodified corpus may be revalidated as exact-existing.
Round 13 neither changes nor starts the frozen continuation and supplies no
missing real authority, so integration remains `STOP_PRE_AUTHORITY`.

## Round 14 frozen integration amendment

Eligibility for original Tasks 2–11 and report Task 12 now additionally
requires publication-equivalent semantic validation of every one of the 71
evidence roles and six scanners on each terminal marker read. The normal
controller invokes the fixed immutable writer's read-only validator; it may not
replace that validator with manifest pointer/order checks or trust a persisted
normal-user receipt.

The initial terminal predecessor is the independently reopened `RUN_SCANS`
result. Both terminal contracts come from the fixed transition table and each
claim binds the exact contract hash plus the prior validated result. A
self-consistently rehashed alternate contract/predecessor or any mutated role
class remains STOP. Round 14 neither changes the five preserved iOS paths nor
starts any continuation task; absent real external authority, integration
remains `STOP_PRE_AUTHORITY`.

## Round 15 frozen integration amendment

Eligibility for the original continuation now requires exact Node/Swift
physical-identity parity. Every identity-bearing read uses BigInt filesystem
stats and the fixed eight-field decimal hash preimage; `mtimeMs` rounding is
forbidden. Status, resume and terminal tail continue through the same common
marker reader, so a legitimate immutable writer with sub-millisecond mtime is
accepted while any one-nanosecond or other physical-field divergence STOPs.

This precision correction does not change the five preserved iOS paths, start
Tasks 2–12 or provide external authority. Integration remains
`STOP_PRE_AUTHORITY`.

## Round 16 frozen integration amendment

Continuation eligibility additionally requires an exact BigInt promotion
proof and exact simulator-container authority. The local bundle destination
must retain the staging directory's precise `dev`/`ino` after exclusive
promotion. The simulator authority must bind the resolved directory's full
eight-field physical identity; the former rounded three-field digest cannot
authorize any phase.

Adjacent physical values above `2^53` are a mandatory negative boundary and
must never compare or hash equal. This does not change the five preserved iOS
paths, start Tasks 2–12 or confer VPS/Mac/root authority; integration remains
`STOP_PRE_AUTHORITY`.

## Round 17 frozen integration amendment

Continuation eligibility now also requires exact generator owner-only
observations. Claim, exact-existing, staging and recovery must share the same
BigInt entry/descriptor/path comparison and the same eight-field physical hash
used across the controller/Swift boundary. A Number-projected physical field,
including an otherwise self-consistent adjacent-size collision, is not valid
authority.

This precision amendment changes neither the five preserved iOS paths nor the
frozen Tasks 2–12 and supplies no external authority. Integration remains
`STOP_PRE_AUTHORITY`.

## Runtime capsule prerequisite — dossier 1.7.2

The prior runtime STOP is preserved and reconciled by
`PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1`. `/usr/bin/node` remains
an unchanged bootstrap-only source; NVM is excluded. One child authority of
`ba847...` publishes a Git-bound builder, evidence and documentation across
exactly seven paths. After that authority is remotely confirmed, the builder
may consume one claim/probe/create budget to publish a root-owned immutable
private runtime and verify its dynamic closure.

Bridge authority remains `ba847...`. Its generator executes only from the Git
blob in a detached clean worktree and exclusively with the capsule. The bridge
budget remains one, credential remains external by path/hash, and the original
Tasks 2–12 stay frozen until the remote bridge bundle and later Mac terminal
gate pass. No primary/live, Supabase, Vercel, production, simulator or CI-4
action is introduced by this prerequisite.

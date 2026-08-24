# CI-2 — Session Lifecycle, User Boundary and Patient-Scoped Cancellation

## Objective and boundary

CI-2 adds app-owned refresh/rotation, local privacy-first logout, atomic user
switching, patient-scoped cancellation and stale-response suppression to CI-1.
It adds no real URL/key, UI, copy, adapter, backend, staging E2E, CI-3, signing
or production operation.

## Architecture

`AuthenticationSessionStore` remains the sole durable Keychain authority.
`SessionLifecycleCoordinator` is an actor that owns one in-flight refresh,
identity generation and `PatientWorkRegistry`; it never owns a password or
AuthClient. `SupabaseAuthRemoteClient` directly performs the two requests in
the authority evidence. It uses `SupabaseAuthFetch` and does not restore or
persist SDK state.

```swift
struct SessionLease: Sendable, Equatable { let userID: String; let generation: UInt64; let bearer: String }
enum RemoteRevocationOutcome: Sendable, Equatable { case confirmed, unconfirmed, localInvalidationFailed }
protocol SessionLifecycleProviding: SessionTokenProviding {
  func leaseForRequest() async throws -> SessionLease
  func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease
  func validate(_ lease: SessionLease) async throws
  func signOut() async -> RemoteRevocationOutcome
}
```

`RemoteRevocationOutcome` is an explicit, coordinator-level result: production
code and focused tests can distinguish `confirmed`, `unconfirmed`, and the
pre-local-invalidation failure. It deliberately does not alter the CI-1 public
`AuthenticationService.signOut() async throws` contract or fan out into UI
callers. The authentication adapter awaits the coordinator result: both
`confirmed` and `unconfirmed` return normally because local privacy state has
already been made unavailable; `localInvalidationFailed` maps to the existing
typed/throwing failure path. UI therefore never represents a remote logout as
confirmed when it is only unconfirmed, and no out-of-allowlist consumer change
is required.

The existing Keychain service gains a separate token-free invalidation-marker
key, written before any record replacement/removal. It contains only schema and
invalidated state. `bootstrapRecord()` reads marker before record and
distinguishes valid record, expired-but-structurally-valid record, marker,
corrupt data and blocked storage. A marker is signed out and cleanup failure
leaves it in place; corrupt/blocked storage never returns a record. If marker
write fails, no durable transition occurred: preserve the old authenticated
record, make no remote call and report `localInvalidationFailed`. This is an
honest failed logout, not local invalidation; a later relaunch may use the
unchanged record. The lifecycle coordinator alone may refresh an
expired bootstrap record before publishing any bearer. A valid record is
persisted before authenticated state is published.

## Refresh, transport and cancellation

`SessionRefreshPolicy` is injected with now/leeway; production leeway is 60
seconds and tests inject it. Before `now + leeway`, use existing bearer; at or
after it, join exactly one refresh for that identity/generation. Response must
match the same confirmed user, persist rotated access/refresh token, then
publish. Storage failure keeps old record. Invalid grant invalidates state;
network/timeout/429/5xx is typed transient and never loops.

`PatientWorkRegistry` registers cancellable patient work by UUID/user/generation
and removes it when complete. Logout/different-user switch increments generation
and cancels only old patient work. `MobileAPITransport` validates lease before
delivery and retry. It may recover one current 401 only: preserve request ID and
idempotency key, rebuild bearer, retry replayable request; second 401 ends.
403/409/422/429/5xx, cancellation, stale lease and non-replayable body never
refresh/retry. Stale completion throws typed `sessionSuperseded` without UI or
cache mutation.

## Logout and user boundary

Logout writes the independent token-free marker before local invalidation. If
that write fails, it preserves the old session and returns
`localInvalidationFailed`, without a remote call. If it succeeds, logout blocks
leases, advances generation, cancels patient work and clears owned sensitive
state; it then permits only local-scope remote revocation from captured access
token. Cleanup is a fail-closed ordered transaction: retain the marker, delete
the old record, then delete the marker only after record deletion succeeds. A
record-delete failure leaves both record and marker; a marker-delete failure
leaves the marker after the record is gone. Either failure leaves the next
bootstrap signed out and must remain so across a simulated process relaunch;
only success of both deletes leaves neither key. Remote result classification
is decided independently of this local cleanup and remains honest.

A different-user sign-in obtains/validates new remote record first. Persist new
record before publication; then invalidate old generation, cancel old work and
clear old owned state. Remote/persistence failure retains/restores old state.
Same-user reauthentication rotates credentials without patient cancellation.

Current sensitive state: Keychain record/tombstone, in-memory state, pending
patient tasks and explicitly ephemeral URLSession with URLCache, cookies and
credential storage disabled. `SensitiveStateClearing` is
a narrow no-op owner today; future domain adapters must register owned cache.
No broad cache deletion is permitted.

## Definition of Done

Tests cover expiry/leeway, N-way single-flight, rotation/persist ordering,
invalid/transient refresh, no SDK retention/listener, 401 one-retry rules,
generation/stale delivery, logout/tombstone outcomes, switching rollback,
relaunch, Keychain failure and Release wiring. CI-2/CI-1/CI-0 focused suites,
BodyFlowTests and unsigned Debug/Release builds pass; scans and two reviews have
zero Critical/Important; only the exact plan allowlist is committed/pushed once.

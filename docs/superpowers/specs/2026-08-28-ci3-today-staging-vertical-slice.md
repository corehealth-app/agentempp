# CI-3 — Authenticated Today staging vertical slice

## Objective

Connect the existing iOS Today experience to the verified dedicated staging
BFF using the CI-1/CI-2 authentication and session lifecycle. The only real
domain added by CI-3 is authenticated `GET /api/mobile/v1/today`.

The frozen base is CI-2 SHA
`277873755bf29771a10b5f362b522c2e6a6c21d6`, tree
`9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4`.

## Explicit non-goals

CI-3 does not integrate History, Plan, Progress, Registration, Meal/media,
Routine, Library/content, Profile mutation, push/APNs, StoreKit/RevenueCat,
paywall, native chat, backend rebranding, migrations, assets, production,
CI-4, TestFlight or App Store. It does not change target, scheme, module,
internal root `BodyFlow`, bundle ID `com.bodyflow.app`, package pins or signing.

## Architecture

```text
local owner-only staging config
              |
              v
SupabaseAuthenticationService -> AuthenticationSessionStore
                                      |
                                      v
                            SessionLifecycleCoordinator
                                      |
                                      v
MobileAPITodayProvider -> MobileAPITransport -> /api/mobile/v1/today
              |                                      |
              +-------- TodayResponse/DTO <----------+
                               |
                               v
                     TodayViewModel/TodayRootView
```

`AuthenticationSessionStore` is the only durable session authority.
`SessionLifecycleCoordinator` remains the only refresh/single-flight,
generation, logout/user-switch and patient-work authority. The Today provider
must not own a token, Auth client, refresh task, cache or second session state.

## Secure staging configuration and credential bridge

No real URL, key, credential or origin may enter Git, chat, command arguments,
result bundles or logs. The Mac executor must create two owner-only local files
outside Git:

- a configuration document containing only staging Supabase URL,
  anon/publishable key and approved BFF Preview origin;
- the existing synthetic credential document.

The source is the VPS root-only artifacts transferred through the already
authorized SSH key/host-key path. A fixed remote filter emits only the three
approved public-client values; it never opens or emits primary/live and never
copies `service_role`. The credential is transferred separately. Both streams
land through pre-opened owner-only files (`umask 077`, mode `0600`) with stdout
suppressed and no interactive shell history.

For simulator execution, the Mac launcher installs exact copies into the app
data container with mode `0600`, no symlink and no command-line values. The app
loads configuration fail-closed. A `#if DEBUG` staging-E2E bootstrap may read
the synthetic credential only when the non-secret CI-3 UI-test mode is active;
it removes the simulator credential copy after reading and passes values
directly to the existing auth service. The canonical Mac credential remains
owner-only until the separately authorized cleanup. Release/beta without an
installed configuration remains unavailable. Mocks remain Debug/preview/test
only.

## Transport and API contract

The request is exactly:

```text
METHOD=GET
PATH=/api/mobile/v1/today
ORIGIN=ONE_APPROVED_HTTPS_BFF_ORIGIN
AUTHORIZATION=CURRENT_PATIENT_BEARER_IN_MEMORY
```

The transport must:

- construct the URL only through `MobileAPIConfiguration`;
- obtain a current lease immediately before sending;
- register the request in `PatientWorkRegistry`;
- reject a redirect to any other origin before forwarding Authorization;
- enforce timeout, cancellation and the existing 64 KiB body limit;
- retry only one eligible 401 through the existing lifecycle coordinator;
- validate the lease before decode/delivery and discard stale generations;
- require HTTP 200, JSON content type, `Cache-Control` containing `no-store`,
  `Vary` containing `Authorization`, safe `X-Request-Id`, matching envelope
  `meta.request_id`, and `meta.api_version=v1`;
- expose sanitized request ID/typed failures only, never bearer/body/PII.

Error mapping must cover 401, 402, 403, 404, 409, 422, 429, 5xx, timeout,
network/offline, cancellation, oversized body, malformed JSON, incompatible
API version, invalid/mismatched request ID and invalid headers. No mutation or
second non-401 retry exists.

## Server-authoritative Today contract

The DTO is derived from `docs/mobile/api-v1.md` and the verified staging PASS,
not from a sample response. Required data includes:

- `local_date` as a valid calendar date;
- non-empty `calculation_version`;
- `targets` and its provenance;
- `consumed` and its provenance;
- remaining food, food excess, exercise and daily balance/status;
- protein status;
- meals, workouts and hydration;
- supplements and medications availability/items;
- pending actions/meal gaps;
- `completion_status`;
- `sources` for every official section;
- optional `block_7700` with provenance when present;
- optional protocol and timestamps with strict RFC3339 parsing.

Optional/null fields remain optional only where the server contract permits.
The mapper rejects missing required data, malformed dates/timestamps, empty or
malformed source/provenance, inconsistent optional structures and incompatible
API versions. An empty valid Today is determined only by the documented
completion status; it is not inferred from zero values.

The client must never calculate, repair or substitute nutrition, targets,
consumed, balances, completion, progress, protocol, Block 7700 or provenance.

## State, concurrency and UI

The Today flow must expose and test:

- loading;
- loaded;
- contract-valid empty;
- recoverable error;
- unauthenticated;
- entitlement/subscription error;
- offline with and without stale data;
- retry;
- cancellation;
- stale response suppression after a newer revision, logout or user switch.

Logout/user switch cancels patient-scoped work through CI-2. A late response
from an older generation cannot mutate view state or cache. The UI never turns
missing config/backend/auth/entitlement into demo success. Release uses
`MobileAPITodayProvider` only when complete real dependencies exist; otherwise
Today is unavailable. Existing Debug demos/previews remain isolated.

## Accessibility and localization

Preserve Dark Mode, Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast,
Differentiate Without Color, and the five independent tab/navigation stacks.
CI-3 may add only the minimum Today state strings and must add both pt-BR and en
catalog values. No new public raw literal or broad visual/naming rebrand is
allowed. Existing localization gaps remain recorded for later Tasks 7–8.

## Verification requirements

Implementation is TDD. Required coverage includes request construction,
current bearer, envelope/header identity, mapping/provenance/optional fields,
all typed status/error paths, timeout, cancellation, body limit, malformed
JSON/date/source, generation/logout/user-switch, fail-closed dependencies,
Debug mocks and Release real-provider boundary.

The real staging gate uses the synthetic fixture without printing or attaching
raw values. It proves one sign-in, current patient/session identity and one
Today read with structural assertions only. XCUI proves fail-closed missing
config, synthetic sign-in, real Today loaded, logout/relaunch, deterministic
offline/error/retry, accessibility labels and pt-BR/en. Credentials may not
enter `xcresult`, screenshots, hierarchies, argv or source.

Focused CI-3 plus CI-2/CI-1/CI-0/Auth/Storage/Networking/Today/
AppDependencies, full `BodyFlowTests` and selected XCUI must report zero fail,
skip or unapproved expected failure. Debug and Release unsigned generic-iOS
builds use only `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`.

Scans cover the exact allowlist, secrets, URLs, synthetic identity, keys,
tokens, PII, raw origin, mock Release, duplicate session state, direct Today
calculation, legacy public naming, backend/migration/assets/rebrand scope and
CI-4.

## Publication and lifecycle

```text
BRANCH=codex/ci3-today-staging-v1
WORKTREE=/Users/eduardohenrique/Developer/bodyflow-ci3-today-staging-v1
COMMIT_SUBJECT=feat(ios): connect Today to authenticated staging
PUSH=ONE_NON_FORCE_WITHOUT_UPSTREAM
PR=NO
MERGE=NO
DEPLOY=NO
CI4=NO
```

Two reviews must each report zero Critical and zero Important. CI-3 must finish
before `2026-09-11T11:44:11.182Z`, or publish a STOP and new decision before
expiry. Fixture cleanup requires a separate authority and is not part of this
spec.

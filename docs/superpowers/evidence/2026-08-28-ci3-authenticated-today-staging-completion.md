# CI-3 authenticated Today staging completion evidence

**Operation:** `AUTHORIZE_CI3_TODAY_STAGING_VERTICAL_SLICE`

**Mode:** `AUTHORING_ONLY`

**Dossier:** `1.7`

**Date:** 2026-08-28 UTC

**Outcome:** `CI3_AUTHORITY_PUBLISHABLE`

This evidence records the completed authenticated staging proof and authorizes
only a later Mac implementation of the CI-3 Today vertical slice. This
authoring operation did not call an authenticated endpoint, issue a token,
mutate Vercel or Supabase, edit iOS code, create a CI-3 worktree, run Xcode,
clean up the synthetic fixture, or start CI-3/CI-4.

## 1. Frozen documentation and implementation identities

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_BASE_SHA=5cecaa7af3f2c61f387e4e2d77a2b5e61f2d9a1c
DOCUMENTATION_BASE_PARENT=e4159e853e6a5938f4620afdce194eb8dab3232d
DOCUMENTATION_BASE_TREE=9bdd7558f4a2916e4846fdf8763fe50ec2d390b5
DOCUMENTATION_BASE_SUBJECT=docs(staging): authorize resume of synthetic Auth identity
CI2_BRANCH=codex/ci2-session-lifecycle-v1
CI2_SHA=277873755bf29771a10b5f362b522c2e6a6c21d6
CI2_PARENT=aba177d7cbb0d9cecb13c5f1099e6b99b6456c93
CI2_TREE=9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4
CI2_SUBJECT=feat(ios): add secure session lifecycle and user boundary
BFF_IMPLEMENTATION_SHA=e3e1e252b48e42554e75899b950692c05186f60d
BFF_IMPLEMENTATION_TREE=a167a6663cb1e476975742bcec51c7207dbcbc26
```

The manager baseline remained canonical `25/5/20`, staging was empty, and the
published porcelain, tracked/untracked status, tracked binary diff and staged
diff hashes matched. The CI-2 remote ref matched the exact SHA, parent, tree and
subject. The implementation, old deploy and dedicated deploy worktrees were
clean; the local `.vercel` link remained ignored and unstaged.

## 2. Dedicated BFF and Vercel readback

Strictly read-only Vercel API reads proved:

```text
SEMANTIC_PREVIEW_DEPLOYMENTS=1
READY_DEPLOYMENTS=1
IMPLEMENTATION_SHA_MATCH=YES
PRODUCTION_DEPLOYMENTS=0
PREVIEW_ENV_COUNT=3
PRODUCTION_ENV_COUNT=0
DEVELOPMENT_ENV_COUNT=0
PROJECT_LINK=ABSENT
GIT_INTEGRATION=ABSENT
ALIASES=0
CUSTOM_DOMAINS=0
CUSTOM_ENVIRONMENTS=0
SSO_PROTECTION=NULL
VERCEL_WRITE=NO
```

The raw Preview origin, project/deployment identifiers and environment values
were not printed or copied into Git. The approved origin remains bound only by
the root-only deployment receipt:

```text
DEPLOYMENT_RECEIPT_SHA256=f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6
```

The already-published public ingress proof remains valid and was not rerun in
this authoring operation:

```text
PUBLIC_PROBES=30/30_PASS
MOBILE_401_JSON_NO_STORE_VARY_REQUEST_ID=3/3
BASE_FORBIDDEN_404=8/8
PRIOR_FINDING_FORBIDDEN_404=19/19
CROSS_ORIGIN_REDIRECT=0
STACK_SECRET_PII=0
PUBLIC_PROBE_SUMMARY_SHA256=a46abe4638c3e1d3d2faf9658efc22c0f87fb5b0a90183d5647c9238dc454a27
PUBLIC_PROBES_REEXECUTED_THIS_OPERATION=NO
```

## 3. Authenticated synthetic staging proof

The prior bounded execution reused the one existing synthetic Auth identity,
canonicalized its e-mail only in memory, and consumed every remaining attempt
once. It reached `TODAY_VERIFIED` and published the final provisioning receipt.

```text
SYNTHETIC_PATIENT_RESUME_STATUS=PASS
AUTHENTICATED_TODAY_STATUS=PASS
SYNTHETIC_PATIENT_PATH=VERIFIED
AUTH_USER_TOTAL=1
AUTH_IDENTITY_TOTAL=1
PATIENT_TOTAL=1
PROFILE_TOTAL=1
PROGRESS_TOTAL=1
ENTITLEMENT_TOTAL=1
ENTITLEMENT_EVENT_TOTAL=1
ACTIVE_BODYFLOW_FULL_ENTITLEMENTS=1
STORAGE_MATCH_TOTAL=0
REAL_USER_MUTATION_TOTAL=0
AUTH_USER_CREATION_ATTEMPTS=1/1_CONSUMED_PREVIOUSLY
SECOND_AUTH_USER_CREATION=NO
PATIENT_SIGN_IN_ATTEMPTS=1/1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=1/1
PATIENT_BOOTSTRAP_READBACK_ATTEMPTS=1/1
ENTITLEMENT_CREATION_ATTEMPTS=1/1
ENTITLEMENT_READBACK_ATTEMPTS=1/1
ENTITLEMENT_RESOLUTION_ATTEMPTS=1/1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=1/1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=1/1
AUTH_USER_UPDATE=NO
AUTH_USER_DELETE=NO
SERVICE_ROLE_RUNTIME_BEARER=NO
TOKEN_PERSISTED=NO
```

`GET /me`, `GET /entitlements` and `GET /today` each returned HTTP 200 JSON,
`Cache-Control: no-store`, `Vary: Authorization`, a matching request ID and an
API-v1 envelope. Today contained a non-empty local date and calculation
version, sources, completion status and source provenance for every applicable
targets/consumed/Block 7700 section. Response bodies, tokens, identity values,
health data and raw origin were not persisted or reported.

## 4. Preserved root-only artifacts

Every artifact is root-owned, mode `0600`, regular, no-symlink, link-count-one
under a mode-`0700` parent. Their hashes remained exact during this authoring
operation.

```text
OPERATION_CLAIM_SHA256=f9b0a29a7f8b1da71ff7492a3f2ec4e746a25533570228da9acd41c475be179a
CREDENTIAL_FILE_SHA256=d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208
RECOVERY_RECEIPT_SHA256=f61700b584b36910ea532bbff429097f3608ec86e1cede22a72cefab7462b44b
PROVISIONING_RECEIPT_SHA256=5ed29995fa906d3774384d5a1aa9157516fa9f3e3dd0d320beff138b6aeedfcb
PROVISIONING_STATE=TODAY_VERIFIED
AUTH_REUSED=YES
EMAIL_NORMALIZATION_CLASS=NORMALIZED_ALIAS_DOCUMENTED
TOKEN_PERSISTED=NO
SERVICE_ROLE_PATIENT_BEARER=NO
VERCEL_WRITE=NO
PRIMARY_LIVE_OPEN=NO
CI3_STARTED=NO
CI4_STARTED=NO
CLEANUP_REQUIRED=YES
CLEANUP_DEADLINE=2026-09-11T11:44:11.182Z
```

Cleanup is not implicit in CI-3 and requires a separately published authority.
The fixture contains no real patient health data and must not outlive the
deadline.

## 5. CI-2 source findings that bind CI-3

The Mobile API contract, project/package state, application dependencies,
authentication/session actors, networking transport, Today models/provider,
Today view model/root view and corresponding tests were inspected from the
exact CI-2 Git object.

Material findings:

- `AuthenticationSessionStore` remains the only durable session source.
- `SessionLifecycleCoordinator` already owns refresh single-flight, generation,
  current-401 recovery, patient-work registration and logout/user-switch
  invalidation.
- `MobileAPITransport` already obtains a lease immediately before a request,
  cancels patient work, rejects cross-origin redirects, limits the body,
  times out, retries at most one eligible 401 and suppresses stale delivery.
- the transport currently returns only decoded payload and validates envelope
  metadata but not the response/header equality required by the staging PASS;
  CI-3 must add a metadata-preserving response path plus `Content-Type`,
  `Cache-Control`, `Vary` and header/envelope request-ID validation.
- `TodaySnapshot` already models the server Today fields and provenance; CI-3
  must validate semantic required/optional relationships without recalculating
  server-authoritative values.
- `TodayViewModel` already owns revision/sequence cancellation and stale
  suppression, but must expose unauthenticated and entitlement/subscription
  errors explicitly.
- `AppDependencies` wires authentication and transport in Release only when
  configuration is present, while `TodayProviding` remains unavailable. CI-3
  adds one real Today adapter and keeps every other domain unavailable/demo as
  it is.
- Xcode uses filesystem-synchronized source/test groups and Auth remains pinned
  at the existing package revision; no project or package file change is
  required or allowed.

## 6. CI-3 bounded scope and security authority

CI-3 may connect only:

```text
synthetic credential
-> Supabase Auth staging
-> AuthenticationSessionStore
-> SessionLifecycleCoordinator
-> MobileAPITransport
-> GET /api/mobile/v1/today
-> API V1 envelope and TodaySnapshot validation
-> existing Today presentation and real SwiftUI states
```

The iOS client must never recompute nutrition, targets, consumed, balance,
completion, progress, protocol, Block 7700 or provenance. It renders values and
sources from the backend or fails closed.

Real staging values remain outside Git. The authorized Mac bridge must use the
existing SSH host key/key, no interactive shell history, encrypted SSH pipes
and owner-only `0600` local files. It exports only staging Supabase URL,
anon/publishable key, approved BFF origin and the synthetic credential; it must
never copy `service_role`. Values are installed into the simulator app data
container without argv/stdout and the Debug-only credential import is removed
from that container after reading. Tokens remain in the CI-1/CI-2 session
boundary only. Release/beta without the local config remains unavailable.

## 7. Publication reviews

Review A covers backend contract, BFF/fixture identity, server authority,
config bridge, secrets, primary/live boundary and cleanup deadline. Review B
covers the exact CI-2 base, source architecture, allowlist, concurrency, UI
states, tests/builds/XCUI, accessibility/localization and scope.

```text
REVIEW_A_REQUIRED=0_CRITICAL_0_IMPORTANT
REVIEW_B_REQUIRED=0_CRITICAL_0_IMPORTANT
REVIEW_A=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
REVIEW_B=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
REVIEW_A_SHA256=c49f78131f9edf0b75d0967a8d84754d8c0eefc614f25b4bb5c25526995ab12a
REVIEW_B_SHA256=208352721dbbdd732ff3769a7987802449c7bca32242a1dbb2650759bcb827db
RAW_ARTIFACT_VALUE_SCAN=PASS
RAW_EMAIL_URL_JWT_BEARER_UUID_SCAN=PASS
```

## 8. External action ledger

```text
IOS_EDIT=NO
CI3_WORKTREE_CREATED=NO
XCODE_OR_SWIFT_TEST=NO
AUTHENTICATED_ENDPOINT_REEXECUTED=NO
TOKEN_ISSUANCE=NO
SUPABASE_WRITE=NO
VERCEL_WRITE=NO
PRIMARY_LIVE_OPEN=NO
PRODUCT_PRODUCTION_WRITE=NO
CLEANUP_EXECUTED=NO
CI3_STARTED=NO
CI4_STARTED=NO
PR=NO
MERGE=NO
DEPLOY=NO
TESTFLIGHT_OR_APP_STORE=NO
RAW_PII_OR_SECRET_REPORTED=NO
```

Publication authorizes only the later Mac operation defined by the CI-3 spec
and plan. It does not execute their handoff.

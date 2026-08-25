# CI-3 dedicated Mobile BFF STOP — RED 1 tests were not discovered

**Date:** 2026-08-25

**Operation:** `AUTHORIZE_IMPLEMENT_DEPLOY_DEDICATED_PUBLIC_MOBILE_BFF_AND_CONTINUE_CI3`

**Classification:** `STOP_DOCUMENTED`

**Candidate documentation subject:**
`docs(staging): record dedicated Mobile BFF stop`

## Authority and exact baseline

- Published authority SHA:
  `89f8bc1c41073d110fe17ee3c638da3998c31aad`.
- Authority parent:
  `9c0d9d608a966153285291c14da94bd2e958cb99`.
- Authority tree:
  `f143a287ffa0345dfe09594af4631afff0afcc15`.
- Authority subject:
  `docs(staging): authorize dedicated Mobile API BFF artifact`.
- Documentation branch/ref:
  `codex/better-ahead-rebranding-design` /
  `refs/heads/codex/better-ahead-rebranding-design`.
- Manager local HEAD and remote ref matched the authority before this draft.
- Manager staging was empty; its historical `-uall` stream remained 25 records
  with SHA-256
  `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`.
- Historical tracked-diff SHA-256 remained
  `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`.

The authority documentation used exactly four paths and was committed and
published once. This STOP draft uses exactly the three outcome paths defined
by that authority and remains unstaged.

## Implementation identity and last passed gate

- Implementation base/current HEAD:
  `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Branch: `codex/ci3-dedicated-mobile-bff-surface-v1`.
- Worktree: `/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`.
- Upstream: absent.
- Code commit/push attempts: `0/1` and `0/1`.
- Implementation commit/tree/subject: `N/A`; no implementation commit exists.

The last passed gate was Task 3 Step 1. After a VPS resource gate returned
`BUSY`, heavy work was serialized and this exact command completed with exit
0:

```text
corepack pnpm@10.33.2 install --frozen-lockfile
```

All 500 packages were reused. Git status remained empty before the RED test
mutation. The working lockfile remained identical to the CI-2 object:

```text
PNPM_LOCKFILE_SHA256=2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55
LOCKFILE_CHANGED=NO
```

pnpm emitted missing Supabase CLI bin-link warnings and listed ignored
dependency build scripts. Those warnings did not change tracked state and did
not cause the later RED blocker.

## Exact RED mutation and failed gate

Only these two RED 1 files were created; both remain untracked and unstaged:

```text
50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6  apps/mobile-bff/src/source-surface.test.ts
289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f  apps/mobile-bff/src/route-mirror.test.ts
```

No `package.json`, Next/Vitest/TypeScript config, verifier, wrapper, lockfile
importer or other GREEN path was created.

The failed gate was Task 3 Step 4, RED 1. After the resource gate reported
`PRESSURED` only from CPU PSI, the two-file test ran serially with the exact
published command:

```text
corepack pnpm@10.33.2 --dir apps/admin exec vitest run \
  --config vitest.config.ts \
  ../mobile-bff/src/source-surface.test.ts \
  ../mobile-bff/src/route-mirror.test.ts
```

Vitest 2.1.9 selected project root `apps/admin`, discovered zero test files,
executed zero tests and exited 1 with `No test files found`. Consequently, it
did not execute the source assertions and did not reach the required semantic
RED that reports wrapper count exactly zero.

The normalized failure transcript encodes the exact command, Vitest version,
project root, discovered-file count, executed-test count, exit code and result,
as ordered `key=value\n` records:

```text
RED1_NORMALIZED_LOG_SHA256=5faceda6a65a877d02f0eb1115c9227c98689ad8bc5cddb38929fabbac655a07
RED1_DISCOVERED_TEST_FILE_COUNT=0
RED1_EXECUTED_TEST_COUNT=0
RED1_EXIT_CODE=1
RED1_RESULT=NO_TEST_FILES_FOUND
```

No raw ANSI log was persisted or represented by that hash.

## Receipts reached and not reached

An independent read-only derivation from the immutable CI-2 object still
reproduced the source receipt:

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
SOURCE_ROUTE_INVALID_EXPORT_COUNT=0
```

This does not substitute for RED 1 execution. The following gates were not
executed and have no positive receipt:

```text
WRAPPER_ROUTE_EXPORT_COUNT=0
WRAPPER_ROUTE_EXPORT_STREAM_SHA256=NOT_EXECUTED
BUILD_ROUTE_PATH_COUNT=NOT_EXECUTED
BUILD_ROUTE_PATH_STREAM_SHA256=NOT_EXECUTED
IMPORT_CLOSURE=NOT_EXECUTED
SOURCE_SURFACE_DENIAL=NOT_EXECUTED
FOCUSED_SECURITY_TEST_FILE_COUNT=NOT_EXECUTED
FOCUSED_SECURITY_TEST_PATH_STREAM_SHA256=NOT_EXECUTED
DEDICATED_TESTS=NOT_EXECUTED
TYPECHECK=NOT_EXECUTED
BUILD=NOT_EXECUTED
LOOPBACK_SMOKE=NOT_EXECUTED
IMPLEMENTATION_REVIEWS=NOT_EXECUTED
```

The frozen expected build and focused-test hashes remain authority inputs, not
results of this stopped run. Historical 172/172 is not claimed as current.

## External state and zero-attempt preservation

No Vercel or Supabase tool/API/CLI call occurred during implementation. The
existing project `agentempp-mobile-bff-staging`, identified by project-ID
fingerprint
`26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f`,
therefore remains at the last confirmed authority baseline: root `apps/admin`,
Next.js, Node 22.x, external sources enabled, inherited project SSO
`all_except_custom_domains`, no Git Integration, no custom domain, zero
Preview env, zero Production env and zero deployment. This documentation task
does not perform a fresh service read or write.

```text
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=0/1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0/1
VERCEL_LOCAL_LINK_ATTEMPTS=0/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0/1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0/1
PROJECT_SSO_FINAL_LAST_CONFIRMED=all_except_custom_domains
TEAM_DEFAULT_CHANGED=NO
PREVIEW_ENV_COUNT_LAST_CONFIRMED=0
PRODUCTION_ENV_COUNT_LAST_CONFIRMED=0
PREVIEW_DEPLOYMENT_COUNT_LAST_CONFIRMED=0
PRODUCTION_DEPLOYMENT_COUNT_LAST_CONFIRMED=0
PUBLIC_MOBILE_401_PROBE_COUNT=0
PUBLIC_FORBIDDEN_404_PROBE_COUNT=0
PRIOR_FINDING_HTTP_PROBES=0/19
PRIOR_FINDING_ACTION_MANIFEST_PROOF=NOT_EXECUTED
SYNTHETIC_PATIENT_PATH=NOT_EVALUATED
AUTHENTICATED_TODAY=NOT_EXECUTED
DEPLOYMENT_RECEIPT=NOT_CREATED
```

No secret source was opened or used. No value, Authorization header, raw
origin or PII is present in this evidence.

## Preservation and complete action accounting

- Manager: authority HEAD, staging empty before this draft, canonical 25
  historical items/hash and tracked diff preserved.
- Old deploy worktree `/root/agentempp-ci3-staging-bff-v1`: detached and clean
  at the CI-2 SHA, staging empty and `.vercel` absent.
- Implementation worktree: CI-2 HEAD, no upstream, staging empty, exactly two
  untracked RED test files and no other status entry.
- Dedicated deploy worktree: not created.
- Frozen Mac evidence path: not accessed or modified.
- Primary/live source/key: not accessed, used or changed.
- Supabase/database writes, user creation and credential changes: zero.
- Production env/deployment, restart and production change: zero.
- PR, merge, tag, CI-3 authorization, CI-4, TestFlight and App Store: zero.
- GitHub Actions: `UNAVAILABLE — NOT USED`.

```text
AUTHORITY_DOCUMENTATION_COMMIT_ATTEMPTS=1/1
AUTHORITY_DOCUMENTATION_PUSH_ATTEMPTS=1/1
IMPLEMENTATION_WORKTREE_CREATION_ATTEMPTS=1/1
IMPLEMENTATION_COMMIT_ATTEMPTS=0/1
IMPLEMENTATION_PUSH_ATTEMPTS=0/1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=0/1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=0/1
PRODUCTION_DEPLOYMENT=NO
SUPABASE_WRITE=NO
DATABASE_WRITE=NO
PR=NO
MERGE=NO
CI3_AUTHORIZED=NO
CI4=NO
```

## Complete operational field groups

```text
OPERATION=AUTHORIZE_IMPLEMENT_DEPLOY_DEDICATED_PUBLIC_MOBILE_BFF_AND_CONTINUE_CI3
FINAL_STATUS=STOP_DOCUMENTED

AUTHORITY_DOCUMENTATION_INITIAL_SHA=9c0d9d608a966153285291c14da94bd2e958cb99
AUTHORITY_DOCUMENTATION_COMMIT=89f8bc1c41073d110fe17ee3c638da3998c31aad
AUTHORITY_DOCUMENTATION_PARENT=9c0d9d608a966153285291c14da94bd2e958cb99
AUTHORITY_DOCUMENTATION_TREE=f143a287ffa0345dfe09594af4631afff0afcc15
AUTHORITY_DOCUMENTATION_SUBJECT=docs(staging): authorize dedicated Mobile API BFF artifact
AUTHORITY_DOCUMENTATION_PATH_COUNT=4
AUTHORITY_DOCUMENTATION_PUSH=YES
AUTHORITY_DOCUMENTATION_REMOTE_SHA=89f8bc1c41073d110fe17ee3c638da3998c31aad

IMPLEMENTATION_BASE=277873755bf29771a10b5f362b522c2e6a6c21d6
IMPLEMENTATION_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
IMPLEMENTATION_WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1
IMPLEMENTATION_COMMIT=N/A
IMPLEMENTATION_PARENT=N/A
IMPLEMENTATION_TREE=N/A
IMPLEMENTATION_SUBJECT=N/A
IMPLEMENTATION_STATUS_PATH_COUNT=2
IMPLEMENTATION_WRAPPER_COUNT=0
IMPLEMENTATION_SOURCE_COUNT=40
IMPLEMENTATION_SOURCE_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
IMPLEMENTATION_WRAPPER_STREAM_SHA256=NOT_EXECUTED
IMPLEMENTATION_BUILD_ROUTE_STREAM_SHA256=NOT_EXECUTED
IMPLEMENTATION_IMPORT_CLOSURE=NOT_EXECUTED
IMPLEMENTATION_LOCKFILE=UNCHANGED
IMPLEMENTATION_TESTS=0_FILES_DISCOVERED_0_TESTS_EXECUTED_EXIT_1
IMPLEMENTATION_TYPECHECK=NOT_EXECUTED
IMPLEMENTATION_BUILD=NOT_EXECUTED
IMPLEMENTATION_LOCAL_SMOKE=NOT_EXECUTED
IMPLEMENTATION_REVIEWS=NOT_EXECUTED
IMPLEMENTATION_PUSH=NO
IMPLEMENTATION_REMOTE_SHA=N/A

VERCEL_PROJECT_NAME=agentempp-mobile-bff-staging
VERCEL_PROJECT_ID_SHA256=26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f
VERCEL_PROJECT_SETTINGS_ATTEMPTS=0
VERCEL_PROJECT_ROOT_LAST_CONFIRMED=apps/admin
VERCEL_PROJECT_NODE_LAST_CONFIRMED=22.x
VERCEL_PROJECT_FRAMEWORK_LAST_CONFIRMED=nextjs
VERCEL_PROJECT_BUILD_COMMAND=UNCHANGED_NOT_FRESHLY_READ
VERCEL_PROJECT_INSTALL_COMMAND=UNCHANGED_NOT_FRESHLY_READ
VERCEL_PROJECT_OUTSIDE_ROOT_LAST_CONFIRMED=YES
VERCEL_PROJECT_GIT_INTEGRATION_LAST_CONFIRMED=NO
VERCEL_PROJECT_CUSTOM_DOMAIN_COUNT_LAST_CONFIRMED=0
VERCEL_TEAM_DEFAULT_CHANGED=NO

VERCEL_ENV_BATCH_ATTEMPTS=0
VERCEL_ENV_NAMES=N/A
VERCEL_ENV_TYPES=N/A
VERCEL_ENV_TARGETS=N/A
VERCEL_PREVIEW_ENV_COUNT_LAST_CONFIRMED=0
VERCEL_PRODUCTION_ENV_COUNT_LAST_CONFIRMED=0
VERCEL_ENV_VALUES_PRINTED=NO
PRIMARY_SECRET_USED=NO

DEPLOYMENT_LINK_ATTEMPTS=0
DEPLOYMENT_ATTEMPTS=0
DEPLOYMENT_ID_SHA256=N/A
DEPLOYMENT_SOURCE_SHA=N/A
DEPLOYMENT_TARGET=N/A
DEPLOYMENT_READY_STATE=N/A
DEPLOYMENT_ROOT=N/A
DEPLOYMENT_NODE=N/A
DEPLOYMENT_ORIGIN_SHA256=N/A
DEPLOYMENT_RAW_ORIGIN_REPORTED=NO
DEPLOYMENT_PROTECTED_INSPECTION=NOT_EXECUTED

SSO_INITIAL_LAST_CONFIRMED=all_except_custom_domains
SSO_FORWARD_ATTEMPTS=0
SSO_FINAL_LAST_CONFIRMED=all_except_custom_domains
SSO_ROLLBACK_ATTEMPTS=0
SSO_TEAM_DEFAULT_CHANGED=NO

PUBLIC_PROBES_MOBILE_401_COUNT=0
PUBLIC_PROBES_FORBIDDEN_404_COUNT=0
PUBLIC_PROBES_PRIOR_FINDING_COUNT=0/19
PUBLIC_PROBES_ACTIONS_ABSENT=NOT_EXECUTED
PUBLIC_PROBES_NO_STORE=N/A
PUBLIC_PROBES_VARY=N/A
PUBLIC_PROBES_REQUEST_ID=N/A
PUBLIC_PROBES_REDIRECT=N/A
PUBLIC_PROBES_HTML=N/A
PUBLIC_PROBES_STACK=N/A
PUBLIC_PROBES_SECRET=N/A
PUBLIC_PROBES_PII=N/A

SYNTHETIC_PATIENT_STATUS=NOT_EVALUATED
SYNTHETIC_PATIENT_MECHANISM=N/A
SYNTHETIC_PATIENT_CREATED=NO
SYNTHETIC_PATIENT_PII_REPORTED=NO
AUTHENTICATED_TODAY=NOT_EXECUTED

DEPLOYMENT_RECEIPT_PATH=N/A
DEPLOYMENT_RECEIPT_MODE=N/A
DEPLOYMENT_RECEIPT_SHA256=N/A
DEPLOYMENT_RECEIPT_RAW_ORIGIN_ONLY_THERE=N/A
DEPLOYMENT_RECEIPT_SECRET_VALUES=NONE
```

Fields marked `LAST_CONFIRMED` come from the published authority baseline and
are not presented as a fresh service read. All service-attempt counters in this
outcome are zero.

## Final documentation state

```text
FINAL_DOCUMENTATION_OUTCOME=STOP_DOCUMENTED
DOSSIER_VERSION=1.6.7
FINAL_DOCUMENTATION_PARENT=89f8bc1c41073d110fe17ee3c638da3998c31aad
FINAL_DOCUMENTATION_TREE=N/A
FINAL_DOCUMENTATION_SUBJECT=docs(staging): record dedicated Mobile BFF stop
FINAL_DOCUMENTATION_COMMIT=N/A
FINAL_DOCUMENTATION_PUSH=NO
FINAL_DOCUMENTATION_REMOTE_SHA=N/A
```

This is an unstaged candidate. Independent reviews, selective staging, commit,
push and remote proof have not occurred and are not authorized by this draft.

## STOP markers and next material gate

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

Reconciliation must explicitly authorize a corrected RED 1 runner boundary
while preserving test-first order. It must decide whether to change the
command/root or authorize a RED bootstrap config before any GREEN artifact.
This record does not execute or authorize that gate, code continuation,
service access, deployment, production, CI-3 or CI-4.

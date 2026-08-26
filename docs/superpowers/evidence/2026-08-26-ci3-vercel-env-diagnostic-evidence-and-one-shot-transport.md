# CI-3 Vercel env diagnostic evidence and bounded one-shot transport

Date: 2026-08-26 UTC
Operation: `RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE_WITH_BOUNDED_ONE_SHOT_TRANSPORT_AND_RESUME_CI3`

## Decision

The historical Vercel CLI failure cannot be reconstructed from its deleted
executor, argv or raw error. That absence is non-decisive: it must not be
replaced by a guessed root cause. Immediate and current readbacks both prove
that the failed historical attempt created no remote environment variable.

```text
HISTORICAL_ROOT_CAUSE=UNRECOVERABLE_NON_DECISIVE
DIAGNOSTIC_EVIDENCE_STATUS=RECONCILED_BY_DURABLE_ONE_SHOT_RECEIPT
VERCEL_CLI_MUTATING_USE=SUPERSEDED_FOR_ENV_AND_SSO
CORRECTED_TRANSPORT=BOUNDED_NODE_HTTPS_ONE_SHOT_V1
ENV_BATCH_RETRY_AUTHORIZED=YES_ONE_SHOT_NEW_TRANSPORT
```

The installed Vercel CLI 50.35.0 cannot satisfy the governing proof contract:
its mutating API client has internal retries and does not provide the required
end-to-end request/response byte bounds. It remains prohibited for environment
or SSO mutation. The user's prohibition on CLI/SDK/fetch/axios/curl for env
creation is preserved. The later, separately budgeted Preview deployment may
use the exact `vercel deploy` command already fixed by the deployment plan; it
does not create environment variables.

## Credential and API contract evidence

The installed CLI source resolved one credential file. Metadata validation
proved regular, non-symlink, root-owned, mode `0600`, link count 1, bounded
size, safe parent ownership/modes and valid JSON with exactly one non-empty
`token` member. GNU file listings contained no ACL marker; ACL-capable helpers
were unavailable, so this external mode/no-marker evidence is retained as the
filesystem-level ruling. No credential value, length, prefix, suffix or
fingerprint was printed.

```text
VERCEL_AUTH_FILE_PATH_SHA256=4aac491198734fb9192ee9e0760f2d37764f6aff527abfb9e949e36cfc51646b
VERCEL_AUTH_FILE_MODE=0600
VERCEL_AUTH_FILE_OWNER=root
VERCEL_AUTH_FILE_SCHEMA=VALID
TOKEN_VALUE_REPORTED=NO
```

Official authenticated OpenAPI cache:

```text
OPENAPI_SHA256=843aa0c724aec9a36a761edfefe39ff36626800bdb75747f28afcd7353d6f6e0
OPENAPI_VERSION=3.0.3
ENV_CREATE=POST /v10/projects/{idOrName}/env?teamId={orgId}
ENV_LIST=GET /v10/projects/{idOrName}/env?teamId={orgId}
PROJECT_GET=GET /v9/projects/{idOrName}?teamId={orgId}
SSO_UPDATE=PATCH /v9/projects/{idOrName}?teamId={orgId}
ENV_CREATE_SUCCESS=HTTP_201
```

The env request is an array of exactly three objects, in this order:

1. `NEXT_PUBLIC_SUPABASE_URL`, `encrypted`, target `preview`;
2. `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `encrypted`, target `preview`;
3. `SUPABASE_SERVICE_ROLE_KEY`, `sensitive`, target `preview`.

Each object contains only `key`, in-memory `value`, `type`, and `target`.
There is no upsert, branch, comment, custom environment, Production,
Development, plain value, fourth item or fourth non-value shape field.

SSO forward is exactly `{ "ssoProtection": null }`; rollback is exactly
`{ "ssoProtection": { "deploymentType": "all_except_custom_domains" } }`.

## Root-only transport V1

Operational artifacts remain outside Git:

```text
TRANSPORT_SOURCE=/root/.config/agentempp/control-plane/ci3-vercel-one-shot-v1.mjs
TRANSPORT_SOURCE_SHA256=b21520e29d260a01cecff1bad17d5f05fb50bffd976aa664afec53bed36d06df
TRANSPORT_TEST=/root/.config/agentempp/control-plane/ci3-vercel-one-shot-v1.test.mjs
TRANSPORT_TEST_SHA256=fb5a222849adb3e6902dcc5015acf3608cf194ec5dd0103200f84abb621b6198
TRANSPORT_VERSION=v1
SOURCE_TEST_OWNER=root
SOURCE_TEST_MODE=0400
SOURCE_TEST_LINK_COUNT=1
```

The source uses only fixed `node:https`/core modules, fixed origin
`https://api.vercel.com`, fixed project scope, TLS verification and SNI, one
request per operation ID, zero client retry, no redirect follow, connection
close, identity encoding, 15-second total/socket timeouts, 16 KiB response
headers, 64 KiB request body and 128 KiB response body. There is exactly one
`https.request` callsite. Token, request values and response value-shaped
fields never enter stdout, stderr or receipts.

The primary/live secret path is a literal denylist entry applied to every
descriptor reader. The preflight never opened the staging source or the
primary/live source.

```text
SELF_TESTS=30/30_PASS
FAILED=0
SKIPPED=0
TODO=0
SYNTHETIC_NETWORK_CALLS=0
SOURCE_SCAN_RECEIPT_SHA256=8028ad56755f44f5173ec5f669ad1c285257cd695c1ee02dc088b2f0350ac877
```

Claims are created root-only with a budget of one and request count zero. The
claim is durably advanced to one immediately before the only mutable request.
After claim creation, crash or ambiguity forbids retry. Attempt receipts are
exclusive, crash-atomic, no-clobber, root-owned `0600` records containing only
the closed sanitized schema. They are published before any readback GET. A
failure or partial result preserves claim and receipt and exits non-zero.

POST success independently requires three exact created keys, exact types and
Preview-only targets before readback. The later GET independently requires the
same three-key inventory and Preview/Production/Development counts `3/0/0`.
SSO success requires explicit project state, exact env inventory, absent link,
and one READY Preview deployment bound to implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`.

Rollback authorization remains conservative: it requires the exact
provenance-bound HTTP-200 forward attempt receipt plus an external failed-probe
receipt bound to that receipt. The failed-probe receipt may be created only
after the forward command has returned its sanitized `readback_validated=true`
success summary. Rollback only restores `all_except_custom_domains`; it never
reprobes or weakens protection.

## Real read-only preflight

The approved frozen implementation executed exactly one Project GET and one
Env GET. Both returned HTTP 200 with request count 1, retry 0, no redirect,
valid bounded JSON and no network error.

```text
PREFLIGHT_RECEIPT_SHA256=25bb55fe10141d275a7fea582d3aedbb47712e711a4137b74513e65c80c0c539
PROJECT_ROOT=apps/mobile-bff
PROJECT_NODE=22.x
PROJECT_FRAMEWORK=nextjs
PROJECT_BUILD_COMMAND=MATCH
PROJECT_INSTALL_COMMAND=MATCH
PROJECT_OUTSIDE_ROOT=YES
PROJECT_LINK=ABSENT
PROJECT_SSO=all_except_custom_domains
VERCEL_DEPLOYMENT_COUNT=0
VERCEL_ENV_TOTAL=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
STAGING_SECRET_OPENED=NO
PRIMARY_SECRET_OPENED=NO
TOKEN_REPORTED=NO
ENV_VALUES_REPORTED=NO
```

Independent reviews after remediation:

```text
REVIEW_A_HTTP_VERCEL=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
REVIEW_B_SECRETS_EVIDENCE=GO_0_CRITICAL_0_IMPORTANT_2_MINOR
```

Review B's two non-blocking items are the explicit ACL ruling above and the
conservative rollback predicate documented above. The required publication
gate is zero Critical and zero Important.

## Source-receipt sequencing ruling

This authority supersedes only the original impossible source-receipt timing.
The authority commit must first publish the exact frozen source/test hashes.
Until its fast-forward push is confirmed, the source receipt remains absent:

```text
SOURCE_RECEIPT_STATUS=PENDING_POST_PUSH_BINDING
```

After the exact authority commit is confirmed remotely, this operation
authorizes exactly one atomic, no-clobber creation at:

```text
/root/.config/agentempp/control-plane/ci3-vercel-one-shot-v1.source.receipt.json
```

The destination must be absent immediately before creation. Its JSON object
has exactly four fields and no others:

```text
authority_sha=<CONFIRMED_REMOTE_AUTHORITY_SHA>
source_sha256=b21520e29d260a01cecff1bad17d5f05fb50bffd976aa664afec53bed36d06df
test_sha256=fb5a222849adb3e6902dcc5015acf3608cf194ec5dd0103200f84abb621b6198
rollback_authorized=true
```

The root controller must create a same-directory temporary file with
`O_CREAT|O_EXCL|O_NOFOLLOW`, mode `0600`; write the complete JSON and final
newline; fsync the file; publish to the absent final pathname with an atomic
no-overwrite hard link; fsync the parent; unlink only the temporary link; and
fsync the parent again. It must then prove root ownership, mode `0600`, regular
non-symlink type, final link count one and exact descriptor readback. Any
preexisting final path, temporary-write failure, publication ambiguity or
metadata mismatch is a STOP. The final receipt is never replaced, edited,
removed or passed to unlink.

The receipt binds only:

- the confirmed authority commit SHA;
- the published source hash;
- the published test hash;
- rollback authorization constrained by this document.

Mutable modes remain fail-closed until source/test are still `0400`, their
hashes still match this document, manager HEAD and remote both equal the
authority SHA, and the source receipt validates those values. The receipt may
not be replaced, edited or removed.

## Budgets and preservation

The attached operation authority activates only the Phase D publication
budgets now:

```text
ONE_SHOT_TRANSPORT_DOCUMENTATION_COMMIT_ATTEMPTS=1
ONE_SHOT_TRANSPORT_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Only remote confirmation of the resulting authority commit activates the
operational and later final-documentation budgets:

```text
VERCEL_PREVIEW_ENV_ONE_SHOT_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_FORWARD_ONE_SHOT_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ONE_SHOT_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Project creation, settings PATCH, local link, CLI env batch and implementation
commit/push budgets are not renewed. Production env/deployment, custom domain,
Git Integration, Supabase/database writes, primary/live use, PR, merge, CI-4,
TestFlight and App Store remain prohibited. CI-3 is not yet authorized; only a
later `PASS_COMPLETE` may authorize it.

Possible final outcomes remain exactly `PASS_COMPLETE`, `PASS_PARTIAL`, or
`STOP_DOCUMENTED`, with their allowlists and subjects already fixed by the
dedicated BFF plan. A commit/push failure in this authority phase is
`STOP_PRE_AUTHORITY`: no source receipt may be created, no staging value may be
opened and no POST may run.

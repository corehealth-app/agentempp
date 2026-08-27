# CI-3 dedicated Mobile BFF Preview verification — PASS_PARTIAL

## Outcome

```text
OPERATION=RECONCILE_UNEXPECTED_VERCEL_PRODUCTION_TARGET_AND_AUTHORIZE_RECOVERY
FINAL_STATUS=PASS_PARTIAL
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

The dedicated BFF and its public contract are verified. The outcome is partial
only because staging has no explicitly synthetic patient identity and no
approved runtime patient credential. This operation did not provision either.

## Authority and immutable source

| Field | Value |
| --- | --- |
| Recovery authority | `7b08e67c81e63b3302de6d8642b3855f5ec60ed9` |
| Authority parent | `047130f334950ec50de56ac11025cdf9a78b4b96` |
| Authority tree | `539363a3c96a3180553b396e2c2653d65fe02559` |
| Authority subject | `docs(staging): authorize recovery from bootstrap Production deployment` |
| Implementation SHA | `e3e1e252b48e42554e75899b950692c05186f60d` |
| Implementation tree | `a167a6663cb1e476975742bcec51c7207dbcbc26` |
| Root / Node / framework | `apps/mobile-bff` / `22.x` / `nextjs` |
| Recovery order | `CREATE_AND_VERIFY_PREVIEW_THEN_DELETE_BOOTSTRAP_PRODUCTION` |

The manager authority was remotely published before operational budgets became
active. GitHub Actions was `UNAVAILABLE — NOT USED`; no remote CI job is
reported as green.

## Preview target settlement

Exactly one second-deployment attempt was executed with literal
`--target=preview`, exact source metadata and recovery metadata. It used no
`--prod`, force/cache override, alias, custom domain, promotion, redeploy, Git
connection or env/token argument. It exited 0 and became READY.

Vercel CLI 50.35.0 reports the deployment as `preview`; the exact API object
stores `target=null`, never `production`. The installed CLI source explicitly
normalizes literal Preview to an omitted API target. Two independent
microreviews approved the contextual compound predicate at 0 Critical,
0 Important and 0 Minor. This record does not generalize API null as Preview
outside that frozen identity/version/state.

```text
RECOVERY_PREVIEW_DEPLOYMENT_ATTEMPTS=1/1
RECOVERY_DEPLOYMENT_TARGET=PREVIEW_SEMANTIC
RECOVERY_DEPLOYMENT_API_TARGET_REPRESENTATION=NULL
RECOVERY_DEPLOYMENT_PRODUCTION=NO
RECOVERY_DEPLOYMENT_READY=YES
RECOVERY_DEPLOYMENT_SOURCE_SHA=e3e1e252b48e42554e75899b950692c05186f60d
THIRD_DEPLOYMENT=NO
```

The root-only Preview receipt SHA-256 is
`2ff33fdfcd339b5f8a5770cf51e34cbcca2f7284b099f449304faffd1407fea1`.
Raw identity and URL are not present in Git or this report.

## Original bootstrap Production removal

Immediately before removal, fresh CLI/API readbacks proved the original and
Preview identities distinct, both READY at the exact source, original target
Production, new semantic target Preview, generated aliases only, custom
domains/environments zero, env `3/0/0`, absent Project link and canonical active
SSO. The exact original deployment ID from the incident receipt was the only
operand.

```text
ORIGINAL_DEPLOYMENT_DELETE_ATTEMPTS=1/1
DELETE_COMMAND_EXIT=0
DELETE_BY_EXACT_ID=YES
DELETE_BY_PROJECT_OR_WILDCARD=NO
PREVIEW_DELETE=NO
PROJECT_DELETE=NO
ENV_DELETE=NO
DOMAIN_DELETE=NO
SECOND_DELETE=NO
```

Readbacks +10/+20/+40 all converged:

```text
ORIGINAL_DEPLOYMENT=ABSENT
PRODUCTION_TARGET_DEPLOYMENT_COUNT=0
SEMANTIC_PREVIEW_DEPLOYMENT_COUNT=1
TOTAL_ACTIVE_DEPLOYMENT_COUNT=1
ORIGINAL_ALIAS_COUNT=0
CUSTOM_DOMAIN_COUNT=0
CUSTOM_ENVIRONMENT_COUNT=0
PROJECT_LINK=ABSENT
VERCEL_ENV_PREVIEW_PRODUCTION_DEVELOPMENT=3/0/0
PROJECT_SSO=ORIGINAL_ACTIVE
```

Settlement receipt hashes are `039ac90f230ad4d8baada5e53166d4543521b3dd71104018fc3904c47a27a4bb`,
`13d5385ddae2bde63633023079bd4c94210b7f88042a8f2fa74cdce9584c2413`
and `6f41c7940356fb5881b1313e57dfcdc689bd976342ccc592b093aa582d898414`.

## Artifact and protected verification

The protected checks targeted only the exact Preview. Today returned 401 JSON
with `Cache-Control: no-store`, `Vary: Authorization` and matching request IDs;
`/` and `/api/admin/send-message` returned 404 without redirect.

Review C returned GO with 0 Critical and 0 Important. Its one Minor was a label
for an auxiliary route stream and was dispositioned by deriving the canonical
hash from byte-identical manifests.

```text
MOBILE_API_ROUTE_COUNT=40
CANONICAL_ROUTE_PATH_STREAM_SHA256=abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a
ADMIN_ROUTE_COUNT=0
AUTHORED_PAGE_COUNT=0
SERVER_ACTION_COUNT=0
MIDDLEWARE_COUNT=0
EMBEDDED_STAGING_VALUE_MATCH_COUNT=0
BUILD_LOG_SECRET_OR_EMAIL_PATTERN=ABSENT
REVIEW_C_CRITICAL=0
REVIEW_C_IMPORTANT=0
```

The Review C report SHA-256 is
`5ad6adaf58cca6e5608175560c23d52aee49a8dccb52df2f454eafb327236af8`.

## SSO forward and public probes

A fresh Project GET proved structural and canonical equality with the frozen
original before the sole official PATCH. The forward returned HTTP 200. All
three +10/+20/+40 snapshots are stable at SSO null, Production 0, semantic
Preview 1 READY, env `3/0/0`, link absent and settings intact.

An intermediate controller observation occurred before the +40 receipt became
visible. A fail-closed rollback helper was invoked but detected the valid +40
receipt at its first precondition and aborted before claim or PATCH. Therefore
no rollback mutation occurred and the shared rollback budget remains unused.

```text
SSO_INITIAL=ALL_EXCEPT_CUSTOM_DOMAINS
SSO_FORWARD_ATTEMPTS=1/1
SSO_FORWARD_HTTP_STATUS=200
SSO_FINAL=NULL
SSO_ROLLBACK_ATTEMPTS=0/1
TEAM_DEFAULT_MUTATION_REQUESTS=0
TEAM_DEFAULT_LIVE_STATE=NOT_OBSERVED
```

Public probes then targeted only the exact Preview origin. Thirty out of thirty
passed:

```text
MOBILE_401_JSON_NO_STORE_VARY_REQUEST_ID=3/3
BASE_FORBIDDEN_404=8/8
PRIOR_FINDING_FORBIDDEN_404=19/19
PRIOR_FINDING_STREAM_SHA256=8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718
CROSS_ORIGIN_REDIRECT=0
STACK_SECRET_PII=0
PUBLIC_PROBE_SUMMARY_SHA256=a46abe4638c3e1d3d2faf9658efc22c0f87fb5b0a90183d5647c9238dc454a27
```

## Final deployment receipt

The final receipt is root:root 0600, regular, single-link and outside Git:

```text
PATH=/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json
SHA256=f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6
RAW_PREVIEW_ORIGIN_ONLY_THERE=YES
RAW_ORIGIN_REPORTED=NO
SECRET_VALUES=NONE
TOKEN=NONE
```

## Synthetic patient discovery

Read-only staging Auth discovery returned zero users. There was no explicitly
synthetic identity, eligible active/confirmed patient/non-admin record or
approved runtime patient credential. No authenticated Today request was
possible without inventing or provisioning credentials. The staging
service-role credential was used only as the control-plane authorization for
these read-only inventory GETs; it was never used as a patient runtime bearer,
and no primary/live credential was opened.

```text
AUTH_USER_TOTAL=0
EXPLICIT_SYNTHETIC_MARKER_COUNT=0
ELIGIBLE_SYNTHETIC_PATIENT_COUNT=0
APPROVED_RUNTIME_CREDENTIAL_ARTIFACT_COUNT=0
SYNTHETIC_PATIENT_PATH=MISSING
AUTHENTICATED_TODAY_PROBE=NOT_EXECUTED
PATIENT_OR_USER_CREATED=NO
PROFILE_CREATED=NO
PASSWORD_CHANGED=NO
EMAIL_CONFIRMED_BY_OPERATION=NO
STAGING_DISCOVERY_SERVICE_ROLE_READS=YES
SERVICE_ROLE_RUNTIME_BEARER=NO
SUPABASE_DATABASE_WRITE=NO
PII_REPORTED=NO
```

The root-only discovery receipt SHA-256 is
`b43d5b75930cf14029698993a06416eb3bcfed3077856abcce14671d708092c4`.

## Preservation

- manager historical entries: 25 preserved, including the five tracked dirty
  paths; staging remained empty before final selective documentation staging;
- implementation and deployment worktrees: exact and clean;
- Preview: preserved READY at the exact source;
- current Vercel Production deployment count: zero;
- Vercel envs: unchanged `3/0/0`;
- primary/live secret: not opened or used;
- product Production: untouched;
- Supabase/database writes: zero;
- no settings PATCH, env upsert, project/link mutation or extra deployment;
- no force, tag, PR or merge;
- CI-4, TestFlight and App Store: not started.

## Next macro-prompt

```text
OPERATION=AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING

Environment: VPS. Continue only from the remotely published PASS_PARTIAL
documentation commit on branch codex/better-ahead-rebranding-design whose
subject is "docs(staging): record verified dedicated Mobile BFF preview", whose
parent is 7b08e67c81e63b3302de6d8642b3855f5ec60ed9, and whose diff contains exactly
the three PASS_PARTIAL documentation paths. Fetch read-only and fail closed
unless that remote commit is unique and satisfies every identity condition.
Read this evidence, the current handoff, naming-neutral plan, dedicated BFF
spec/plan and root-only deployment receipt in full before any edit.

Mode: AUTHORING_ONLY. Design, independently review and publish one bounded
staging authority for a later execution to provision exactly one explicitly
synthetic Supabase Auth user and matching patient profile, establish an
approved patient credential mechanism and runtime access token, and validate
authenticated Today against only the verified dedicated Preview. Stop after
the authority commit is remotely confirmed. This operation does not provision
a user/profile/credential/token and does not run authenticated Today.

Required safety: first prove project ref is the authorized staging project;
never open/use primary/live; never report email, password, token, user/profile
ID or PII; never use service-role as the patient bearer; keep raw credentials
only in root:root 0600 receipts; use no real client identity; no existing-user
mutation; no broad cleanup; no Vercel project/env/SSO/deployment mutation;
preserve the verified Preview; production deployment count stays zero; CI-4,
TestFlight and App Store remain prohibited.

The authority must freeze exact user/profile schemas, explicitly synthetic
identity markers, Auth-to-profile order, no-clobber preconditions, rollback for
every partial state, credential lifetime/revocation, one-attempt budgets,
readbacks, authenticated Today acceptance, root-only recovery receipts and
terminal outcomes. Require two independent reviews at 0 Critical/Important
before its exact-path commit and one non-force push. Use exact allowlist:
docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md,
docs/superpowers/evidence/2026-08-27-ci3-synthetic-staging-patient-provisioning-authority.md,
docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md. Commit
subject: "docs(staging): authorize synthetic patient provisioning"; parent:
the validated PASS_PARTIAL commit. Do not stage historical dirty paths.

PATIENT_PROVISIONING_ATTEMPTS=0. AUTH_USER_CREATION_ATTEMPTS=0.
PROFILE_CREATION_ATTEMPTS=0. CREDENTIAL_ISSUANCE_ATTEMPTS=0.
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=0. If any baseline, authority, project,
Preview, env, production-count or secret-source gate diverges, STOP without
creating or altering any identity.

Expected terminal outcomes for this authoring operation: AUTHORITY_PUBLISHED,
STOP_DOCUMENTED or STOP_PRE_AUTHORITY. On AUTHORITY_PUBLISHED, print the exact
remote authority SHA and a separate execution handoff; do not execute it. Do
not begin CI-4.
```

This macro-prompt is authority input only. It does not itself authorize or
perform patient provisioning.

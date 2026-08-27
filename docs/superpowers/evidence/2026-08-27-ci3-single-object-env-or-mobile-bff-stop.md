# CI-3 — STOP after single-object Preview env settlement and unexpected Production deployment target

## Outcome

```text
OPERATION=RECONCILE_VERCEL_CLI_JSON_ARRAY_TRANSPORT_WITH_SINGLE_OBJECT_UPSERTS_AND_RESUME_CI3
OPERATION_STATUS=STOPPED
FINAL_STATUS=STOP_DOCUMENTED
FAILED_GATE=DEPLOYMENT_TARGET_MUST_BE_PREVIEW
STOP_CLASS=UNEXPECTED_PRODUCTION_DEPLOYMENT_TARGET
FAILED_KEY=NONE_AFTER_ENV_SETTLEMENT
CI3_AUTHORIZED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_UNEXPECTED_VERCEL_PRODUCTION_TARGET_AND_AUTHORIZE_RECOVERY
```

Authority parent:
`f27ad6eab60d1b41f0fd378d350b9b714d0d41de`.

## Single-object environment operations

The Vercel CLI 50.35.0 accepted three plain JSON objects, never an array. Each
object contained only `key`, `value`, `type` and `target:[preview]`. Each key
consumed exactly one logical invocation; internal CLI retries, if any, were
accepted only within that same idempotent `upsert=true` invocation. No outer
retry or second logical invocation occurred.

| Operation | Key | Type/target | Logical invocations | Exit | Stable readback |
| --- | --- | --- | ---: | ---: | --- |
| A | `NEXT_PUBLIC_SUPABASE_URL` | encrypted / Preview | 1 | 0 | `1/0/0`, +15/+30/+60 identical, inventory SHA-256 `887d167d4f481e0a6eefb9accc0fc9d12722d881b26df2f06b2d484cc3e795aa` |
| B | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | encrypted / Preview | 1 | 0 | `2/0/0`, +15/+30/+60 identical, inventory SHA-256 `4e1c60d7ea5436ea542b95ba5e801e3f0cfe758b34934e86ada434e0576d9e54` |
| C | `SUPABASE_SERVICE_ROLE_KEY` | sensitive / Preview | 1 | 0 | `3/0/0`, +15/+30/+60 identical, inventory SHA-256 `6f7a2bb4ccddce99bcc6a908e9d0a22c6313eaee6e112d1bc72c817627380f58` |

Final environment inventory is exactly Preview/Production/Development
`3/0/0`. Environment deletes, corrections, external retries and second
invocations are all zero. No decrypted or raw value was requested or reported.
The primary/live secret was not opened or reused for staging.

## Deployment gate and STOP

The pre-deploy review returned GO with 0 Critical, 0 Important and 0 Minor.
The dedicated detached deployment worktree was clean at implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`; the bounded surface was 40/40,
the import closure contained 121 records and the resource gate passed for one
sequential build.

Exactly one deployment attempt was executed. The command used `--yes` and the
exact source metadata, and did not contain `--prod`, alias, domain, promotion,
redeploy or Git connection. It exited 0. The artifact reached `READY` and its
source metadata matched the implementation SHA. However, protected
`vercel inspect` and an independent read-only official deployment API GET both
reported `target=production`, not the required `preview`.

```text
DEPLOYMENT_ATTEMPTS=1/1
DEPLOYMENT_EXIT=0
DEPLOYMENT_READY=YES
DEPLOYMENT_SOURCE_SHA_MATCH=YES
COMMAND_CONTAINED_PROD_FLAG=NO
EXPECTED_TARGET=preview
OBSERVED_TARGET=production
PRODUCTION_DEPLOYMENT_MUTATION_REQUESTED=NO
PRODUCTION_DEPLOYMENT_TARGET_UNEXPECTED=YES
PRODUCTION_UNTOUCHED=NO
PRODUCTION_RECOVERY_EXECUTED=NO
PRODUCTION_ARTIFACT_PRESERVED=YES
```

The deployment identifier and origin remain only in root-owned evidence and
are not reported here. Sanitized raw-output hashes are:

- stdout/origin evidence SHA-256:
  `d72a0d65bf154bba5191e2316b24bcee2520b8e53c182e6bbd1bf492b32aff9f`;
- stderr evidence SHA-256:
  `5735d1e1489b94d469778149d4f414ef636481ff5b940370cd9283e03c3bf7b3`.

No second deployment invocation, retry, promotion, alias, delete or recovery
was attempted. The Production-classified artifact is deliberately preserved:
the current authority contains no bounded recovery or deletion permission.

## SSO, probes and patient path

```text
SSO_ORIGINAL_ACTIVE=YES
SSO_FORWARD_INVOCATIONS=0
SSO_ROLLBACK_INVOCATIONS=0
TEAM_DEFAULT_MUTATION_REQUESTS=0
TEAM_DEFAULT_LIVE_STATE=NOT_OBSERVED
PUBLIC_PROBES=0
TODAY_PROBE=NOT_EXECUTED
SYNTHETIC_PATIENT=NOT_EVALUATED
PATIENT_OR_USER_CREATED=NO
PII_REPORTED=NO
```

The STOP happened before SSO forward. Consequently no public or authenticated
probe, patient discovery, rollback or reprobe was authorized or executed.

## Preserved and removed resources

Preserved:

- the root-only operation lock;
- three durable no-value claims, one per environment key;
- the 40/40 synthetic control test suite;
- the staging secret source and its receipt;
- the root-only deployment stdout/stderr evidence;
- the original SSO descriptors and state;
- the exact `3/0/0` environment inventory;
- the unexpected remote artifact;
- the clean implementation and deployment worktrees;
- all 25 historical manager worktree entries, including the five tracked
  historical modifications, with staging empty before documentation.

Removed only after stable env settlement, as authorized:

- the single-object emitter;
- the single-object runner;
- their empty owned temporary output directory.

Their frozen pre-removal hashes were emitter
`005e0b22bf8762c6026897d72767f36be054cb5a365c185e96214a432a4283ab`
and runner
`b8a7fe24707e6bf29733b119b850b6caf6ab444c6f602eb489cf6328866d2a43`.
They were removed by exact path and were not moved to trash; the hashes, tests
and independent review remain preserved evidence. They must not be recreated
under this operation.

Supabase/database writes, production recovery, primary key disable/rotation,
project creation, settings PATCH, Vercel link, V1–V4 execution, PR, merge and
CI-4 activity are all zero. GitHub Actions was unavailable and not used.

## Decision

The environment-variable portion passed, but the remote deployment target is
materially outside the authorized boundary. CI-3 is not authorized. No further
external mutation is permitted under this operation.

The next authority must reconcile why a non-`--prod` command created a
Production-classified deployment and explicitly authorize a bounded recovery
or preservation decision before any SSO change, probe or retry:

`RECONCILE_UNEXPECTED_VERCEL_PRODUCTION_TARGET_AND_AUTHORIZE_RECOVERY`.

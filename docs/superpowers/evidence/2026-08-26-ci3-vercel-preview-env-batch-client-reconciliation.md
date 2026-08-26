# CI-3 Vercel Preview env batch client reconciliation

**Date:** 2026-08-26

**Operation:**
`RECONCILE_VERCEL_PREVIEW_ENV_BATCH_CLIENT_FAILURE_WITH_ZERO_REMOTE_ENV_AND_RESUME_CI3`

**Outcome:** `STOP_DOCUMENTED`

**Next gate:** `RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE`

## Documentation baseline

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_SHA=79fa426b5293489666cc491225f1e9504c076a98
DOCUMENTATION_PARENT=fb1e0a3b76b831976f1e8b7f129758405b42e694
DOCUMENTATION_TREE=eea9155f6224ecf65ed3da31c1909464972f02d9
DOCUMENTATION_SUBJECT=docs(staging): record Vercel local-link or Mobile BFF stop
DOSSIER_BEFORE=1.6.11
MANAGER_BASELINE=25/5/20_PRESERVED
MANAGER_PORCELAIN_SHA256=455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0
MANAGER_TRACKED_DIFF_SHA256=7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb
INITIAL_STAGING=EMPTY
```

## Prior attempt evidence recovered without secrets

Only the frozen hashes/markers were searched in task reports, recovery ledger,
sanitized Codex reports, published documentation and safe remaining
temporaries. Shell history, credential stores, `.env`, both secret files,
browser profiles, process environments, databases and production were
excluded.

```text
EXECUTOR_PATH=/root/.codex/ops/state/ci3-preview-env-batch-executor.mjs
EXECUTOR_PATH_CURRENT=ABSENT
EXECUTOR_SOURCE=UNRECOVERED
ENV_EXECUTOR_SHA256=e41caa1bb0befe87471f224a7a04b55e3a11822ec4b6f31c7d73fa3ec645867e
ENV_FAILURE_DIAGNOSTIC_SHA256=e71d492d1abf97ecf9d984116c77e83470ef08214c21805a6f6085a6528e01cf
COMMAND_EXECUTABLE=node
COMMAND_ARGV=UNRECOVERED
COMMAND_CWD=UNRECOVERED
ENDPOINT_PATH_QUERY=UNRECOVERED
TEAM_SCOPE_EXPLICIT=UNRECOVERED
INPUT_MECHANISM=JSON_STDIN
INPUT_ARGUMENT=UNRECOVERED
CHILD_ENV=MINIMAL_NAMES_ONLY
CLIENT_EXIT=1
EXECUTOR_EXIT=78
RAW_STDOUT=NOT_PRESERVED
RAW_STDERR=NOT_PRESERVED
SANITIZED_ERROR_CLASSIFICATION=NOT_PRESERVED
```

Published evidence proves the old root-only executor, intended three exact
names/types/Preview targets, explicit Node invocation, minimal environment and
terminal exit codes. No permitted file matched the executor or diagnostic
hash. The missing source, argv and semantic error preimage were not invented.

## Installed Vercel CLI audit

```text
VERCEL_CLI_VERSION=50.35.0
NODE_VERSION=v24.14.0
RESOLVED_EXECUTABLE=/root/.nvm/versions/node/v24.14.0/bin/vercel
REAL_EXECUTABLE_SHA256=24a660d5013c2066a2637431519bda38a3c71c60a65566d86121362f27696576
PACKAGE_JSON_SHA256=80fd9f69d8f836660cf0cb4f8ddbbd1e73b69de899db6de6a7b9489958b8c933
COMMANDS_BULK_SHA256=96ea40cb30802a129bd565398412c4238d8d316c0d453ba9e17d3c56778f66ad
API_OPTIONS_CHUNK_SHA256=8e508b0e60527ce5958d3fbcf3f5bf854b062ecff53109a88d5758b58d05616a
CONFIG_CHUNK_SHA256=f0a4df081ceca97af4b354de9e19e9ea1741ce450977ae64453d5ee1fd8098db
INDEX_SHA256=6ed2c3e40b360db4abc8e1467f323c14e493968bc891dc57e265f72304fd4a6c
```

`vercel api --help`, `vercel api ls`, its `list` alias and `vercel whoami`
passed. Installed help/source directly prove that `--input -` calls
`readStdin()` and that another input is a cwd-resolved file. `-X/--method` is
supported, endpoint origin is restricted to the Vercel API, global auth is
discovered from HOME/XDG data or explicit global config, and team scope becomes
`teamId` in `Client._fetch()`.

A synthetic `--input - --generate=curl` execution exited 0 and reproduced the
synthetic body without network access. Therefore stdin unsupported/path
required are not valid classifications for this installed CLI.

The audit also found two incompatible properties for the preferred correction:

1. `Client.fetch()` has internal default `retries=3`, with no `vercel api`
   flag to force zero retry;
2. stdin/file request reads and response JSON/text parsing are unbounded inside
   the CLI. An outer pipe limit cannot bound bytes already buffered internally.

No installed package was changed or monkey-patched.

## Current official API contract

The authenticated OpenAPI cache was refreshed by the read-only endpoint-list
command and preserved root-owned mode `0600`:

```text
OPENAPI_FETCHED_AT=2026-08-26T13:23:43.039Z
OPENAPI_SHA256=843aa0c724aec9a36a761edfefe39ff36626800bdb75747f28afcd7353d6f6e0
OPENAPI_SIZE=3286882
OPENAPI_VERSION=3.0.3
ENDPOINT=POST /v10/projects/{idOrName}/env
SUCCESS_STATUS=201
BODY=ONE_OBJECT_OR_ARRAY
TYPES=system,encrypted,plain,sensitive
TARGETS=production,preview,development
```

The exact intended batch—two encrypted public variables and one sensitive
service-role variable, all target `preview`, no upsert/gitBranch/comment/custom
environment—satisfies the schema. A 201 response has `created`/`failed` shapes
and can contain value-shaped fields; it must never be printed raw.

## Minimal child-env and remote readback

The proposed child env was limited to
`HOME,USER,LOGNAME,PATH,LANG,LC_ALL,NO_COLOR,FORCE_COLOR,CI`; neither XDG nor a
manual token export was required. `whoami`, Project GET and Env GET passed. The
historical smaller set `HOME,PATH,NO_COLOR,CI` also passed those read-only
probes with explicit scope. Project GET also resolved under the authenticated
current-team context without explicit scope.

```text
PROJECT_NAME=agentempp-mobile-bff-staging
PROJECT_ID_FINGERPRINT=26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f
ROOT_DIRECTORY=apps/mobile-bff
NODE_VERSION=22.x
FRAMEWORK=nextjs
OUTSIDE_ROOT=YES
PROJECT_GIT_LINK=ABSENT
VERCEL_ENV_TOTAL=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
VERCEL_DEPLOYMENT_COUNT=0
PROJECT_SSO=all_except_custom_domains
```

## Root cause, reviews and ruling

```text
ROOT_CAUSE_PRIMARY=UNRESOLVED
ROOT_CAUSE_SECONDARY=CLIENT_RUNTIME_EXECUTION_ERROR
ROOT_CAUSE_SECONDARY_DETAIL=UNCLASSIFIED
REMOTE_ENV_ZERO=YES
ENV_BATCH_RETRY_AUTHORIZED=NO
CORRECTED_MECHANISM=NOT_AUTHORIZED
NEXT_GATE=RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE
```

Current direct evidence disproves the suspected stdin/path and auth-context
causes but cannot distinguish the historical API rejection, serialization,
parser, transport or runtime failure whose raw preimage no longer exists. The
hash alone is not a semantic error receipt. Separately, the CLI's internal
retries/unbounded buffering conflict with the current corrected-mechanism
contract. Retry authorization is therefore fail-closed.

Review A (Vercel client/API) and Review B (secrets/filesystem) each ended GO at
0 Critical / 0 Important / 0 Minor after correcting one invalid combined enum
into the authorized enum plus a separate descriptive detail. Reviewers were
read-only and executed no POST or secret access.

## Budgets and preservation

```text
SETTINGS_PATCH_HISTORICAL_ATTEMPTS=1/1_CLOSED
VERCEL_LOCAL_LINK_HISTORICAL_ATTEMPTS=1/1_CLOSED
VERCEL_PREVIEW_ENV_BATCH_HISTORICAL_ATTEMPTS=1/1_CLOSED
ENV_CLIENT_DOCUMENTATION_COMMIT_ATTEMPTS=1
ENV_CLIENT_DOCUMENTATION_PUSH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_RETRY_ATTEMPTS=0/0_NOT_ACTIVATED
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
STAGING_SECRET_OPENED=NO
PRIMARY_SECRET_OPENED=NO
SUPABASE_WRITE=NO
DATABASE_WRITE=NO
PRODUCTION_DEPLOYMENT=NO
PR=NO
MERGE=NO
CI4=NOT_STARTED
GITHUB_ACTIONS=UNAVAILABLE_NOT_USED
```

The manager's 25/5/20 historical state, implementation and old deploy
worktrees, detached dedicated deploy worktree and ignored mode-0600 local
project link metadata remain preserved. No env, deployment, SSO, user,
database, production or CI-4 mutation occurred. CI-3 remains unauthorized.

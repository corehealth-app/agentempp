# CI-3 RED 1 Vitest external discovery reconciliation

**Date:** 2026-08-26

**Operation:**
`RECONCILE_RED1_VITEST_EXTERNAL_TEST_DISCOVERY_AND_RESUME_DEDICATED_BFF`

**Classification:** documentation authority draft; no RED, implementation or
external-service action executed

**Candidate subject:** `docs(staging): reconcile dedicated BFF RED discovery`

## Documentation baseline and authority boundary

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_REMOTE_REF=refs/heads/codex/better-ahead-rebranding-design
DOCUMENTATION_BASE=6e03d5a67284204ab2781ff049ffe4df40b18961
DOCUMENTATION_BASE_PARENT=89f8bc1c41073d110fe17ee3c638da3998c31aad
DOCUMENTATION_BASE_TREE=f871f4bc2b19e84e641b202a2ecfa5ca8f3cd576
DOCUMENTATION_BASE_SUBJECT=docs(staging): record dedicated Mobile BFF stop
DOSSIER_TRANSITION=1.6.7_TO_1.6.8
RED_DISCOVERY_AUTHORITY_SHA=PENDING_COMMIT_AND_REMOTE_CONFIRMATION
```

Before this draft, local HEAD and the exact remote ref matched the baseline;
staging was empty. The manager retained 25 historical `-uall` records (five
tracked and 20 untracked), full status SHA-256
`455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`,
tracked-status SHA-256
`429841c416296c3f41cd3ea75ff4cbad7528a13d9e28bf21b3be9bc04f248c8a`,
untracked-status SHA-256
`913259345be829c189b40e68932ba1b726369edf8ca80ef4c0deb05574bd9d66`,
tracked-diff SHA-256
`7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`
and empty staged-diff SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

This five-path draft is the exclusive authority candidate for the RED 1
discovery boundary. It neither executes the RED nor authorizes implementation,
service access, production, CI-3 or CI-4. Only a successful commit with parent
`DOCUMENTATION_BASE`, followed by a single non-force fast-forward push and
remote proof, may establish `RED_DISCOVERY_AUTHORITY_SHA`.

## Historical failure preserved and root cause

The prior STOP was correct. Vitest 2.1.9 was invoked from the `@mpp/admin`
package with the prior relative command:

```text
corepack pnpm@10.33.2 --dir apps/admin exec vitest run \
  --config vitest.config.ts \
  ../mobile-bff/src/source-surface.test.ts \
  ../mobile-bff/src/route-mirror.test.ts
```

That command is now `SUPERSEDED` for every future run, but its evidence is not
erased. The runner retained the effective root/discovery boundary in
`apps/admin`; the test operands lived under the sibling `apps/mobile-bff`.
Vitest therefore discovered zero test files, executed zero tests and exited 1
with `No test files found`. The normalized historical transcript SHA-256 is
`5faceda6a65a877d02f0eb1115c9227c98689ad8bc5cddb38929fabbac655a07`.

```text
HISTORICAL_RED1_DISCOVERED_TEST_FILE_COUNT=0
HISTORICAL_RED1_EXECUTED_TEST_COUNT=0
HISTORICAL_RED1_EXIT_CODE=1
HISTORICAL_RED1_RESULT=NO_TEST_FILES_FOUND
ROOT_CAUSE=VITEST_ROOT_AND_DISCOVERY_REMAINED_APPS_ADMIN
TEST_FILES_INVALID=NO
SOURCE_MANIFEST_INVALID=NO
```

## Preserved source and test receipts

The source receipt remained valid independently of the failed discovery and
does not substitute for a semantic RED execution:

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_INVALID_EXPORT_COUNT=0
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
```

The two existing untracked and unstaged tests must remain byte-identical until
after the first reconciled RED is approved:

```text
SOURCE_SURFACE_TEST_PATH=apps/mobile-bff/src/source-surface.test.ts
SOURCE_SURFACE_TEST_SHA256=50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6
ROUTE_MIRROR_TEST_PATH=apps/mobile-bff/src/route-mirror.test.ts
ROUTE_MIRROR_TEST_SHA256=289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f
```

No `apps/mobile-bff/package.json`, dedicated Vitest/Next/TypeScript config,
wrapper, verifier or lockfile importer exists at this authority boundary. None
may be created before the semantic RED. `--passWithNoTests` is prohibited, as
is any test-byte edit or discovery/list run that would consume or bypass the
single RED attempt.

## Reconciled one-attempt command

Reuse the existing implementation identity exactly:

```text
IMPLEMENTATION_BASE=277873755bf29771a10b5f362b522c2e6a6c21d6
IMPLEMENTATION_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1
IMPLEMENTATION_UPSTREAM=ABSENT
```

Worktree or branch creation, recreation, repair, relinking and upstream
mutation are not reauthorized. The prior frozen install and both test writes
are historical/completed; do not repeat or rewrite them.

Only after the documentation remote confirms `RED_DISCOVERY_AUTHORITY_SHA`,
run the read-only Phase B preflight. Revalidate exact implementation branch,
HEAD/parent/tree/subject, absent upstream, empty staging, tracked-clean state,
exactly the two untracked tests and their hashes, lockfile SHA-256
`2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55`,
available Vitest 2.1.9, and admin config SHA-256
`8bb6705e6315f5a28bdf6cc15cae3ff7526007913c8f7c01acd7279ad0b91266`
with no conflicting custom `root`/`include`. Reproduce source
`40/0/7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`
read-only and require wrapper count zero plus zero package/config/GREEN
artifact. Modify nothing.

Run only:

```bash
corepack pnpm@10.33.2 --dir "$WORKTREE/apps/admin" exec vitest --help
```

Require the help to document `--root`, `--dir` and `--config`. Do not run
discovery/list or anything that consumes the RED attempt. Only if the binary is
absent may a resource gate precede one frozen install; tracked bytes and
lockfile must remain unchanged. Install failure or any preflight divergence is
`STOP_DOCUMENTED` without RED execution, test edit or GREEN artifact.

After the complete preflight passes, execute exactly once:

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

The command keeps the already installed Vitest 2.1.9 and existing admin config,
but makes root, discovery directory, config and both absolute test paths
explicit. It does not authorize a package/config/bootstrap mutation.

## Exact semantic RED contract

The single reconciled run passes the RED gate only when every field below is
true together:

```text
RED1_DISCOVERED_TEST_FILE_COUNT=2
RED1_EXECUTED_TEST_COUNT=>0
RED1_SOURCE_ROUTE_EXPORT_COUNT=40
RED1_SOURCE_INVALID_EXPORT_COUNT=0
RED1_SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
RED1_WRAPPER_ROUTE_EXPORT_COUNT=0
RED1_FAILURE_CLASSIFICATION=MIRROR_ABSENT_ONLY
RED1_NO_TEST_FILES_FOUND=NO
RED1_CONFIG_ERROR=NO
RED1_MODULE_ERROR=NO
RED1_SYNTAX_ERROR=NO
RED1_SOURCE_DRIFT=NO
RED1_SKIP_TODO_CANCEL=0
RED1_EXIT_CODE=1
```

Both test files must be executed. A discovery, config, module, syntax or source
failure is not semantic RED. Any other outcome stops without editing tests,
creating package/config, rerunning or starting Tasks 4–14. After a valid RED,
revalidate both physical test hashes before the first GREEN mutation.

## Normalized reconciled RED receipt

The one execution must produce an ordered `key=value\n` transcript normalized
without ANSI. The raw transcript is never a receipt. Its minimum complete
schema is:

```text
RED1_EXACT_COMMAND_FINGERPRINT_SHA256=<SHA_REAL>
RED1_VITEST_VERSION=2.1.9
RED1_ROOT=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1
RED1_DIR=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1/apps/mobile-bff/src
RED1_CONFIG=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1/apps/admin/vitest.config.ts
RED1_DISCOVERED_TEST_FILE_COUNT=2
RED1_EXECUTED_TEST_COUNT=<COUNT_REAL_GT_0>
RED1_PASSED_TEST_COUNT=<COUNT_REAL>
RED1_FAILED_TEST_COUNT=<COUNT_REAL>
RED1_SKIPPED_TEST_COUNT=0
RED1_EXIT_CODE=1
RED1_SOURCE_ROUTE_EXPORT_COUNT=40
RED1_SOURCE_INVALID_EXPORT_COUNT=0
RED1_SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
RED1_WRAPPER_ROUTE_EXPORT_COUNT=0
RED1_FAILURE_CLASSIFICATION=MIRROR_ABSENT_ONLY
RED1_NO_TEST_FILES_FOUND=NO
RED1_CONFIG_ERROR=NO
RED1_MODULE_ERROR=NO
RED1_SYNTAX_ERROR=NO
RED1_SOURCE_DRIFT=NO
RED1_SKIP_TODO_CANCEL=0
RED1_RECONCILED_NORMALIZED_LOG_SHA256=<SHA_REAL>
```

The command fingerprint covers the exact literal command, Vitest, root, dir,
config and both absolute test paths. Missing/divergent fields or receipt hash
select `STOP_DOCUMENTED` without rerun. Every final operational report must
include separate `DOCUMENTATION_BASELINE`, `RED_DISCOVERY_AUTHORITY`,
`IMPLEMENTATION_BASELINE` and `RED1_RECONCILED` groups; the last carries the
exact command/fingerprint, runner paths/version, all test counts, exit,
source/wrapper/classification receipts and normalized log SHA-256.

```text
RED1_RECONCILED: exact command, command fingerprint, Vitest version, root, dir,
  config, discovered files, executed/passed/failed/skipped tests, exit,
  source count/invalid/hash, wrapper count, failure classifications,
  RED1_RECONCILED_NORMALIZED_LOG_SHA256
```

## Independent budgets and continuation boundary

The documentation authority itself has exactly one commit and one push
attempt:

```text
RED_DISCOVERY_DOCUMENTATION_COMMIT_ATTEMPTS=1
RED_DISCOVERY_DOCUMENTATION_PUSH_ATTEMPTS=1
```

The earlier external budgets are historical and are not implicitly reused.
Only after remote confirmation of `RED_DISCOVERY_AUTHORITY_SHA` do these new,
independent budgets exist:

```text
RED1_RECONCILED_EXECUTION_ATTEMPTS=1
IMPLEMENTATION_COMMIT_ATTEMPTS=1
IMPLEMENTATION_PUSH_ATTEMPTS=1
VERCEL_DEDICATED_PROJECT_SETTINGS_PATCH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1
VERCEL_LOCAL_LINK_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

There is no new worktree-creation budget and no RED retry. Tasks 4–14 of
`docs/superpowers/plans/2026-08-25-dedicated-public-mobile-bff-surface.md`
continue literally only after the semantic RED is approved. This isolated
reconciliation performs zero production work and does not authorize CI-3 or
CI-4.

## Reconciled final-documentation authority

All final outcomes require the manager HEAD and remote ref to equal
`RED_DISCOVERY_AUTHORITY_SHA`; that SHA is the exact parent of the one permitted
final-documentation commit.

- `STOP_DOCUMENTED`: dossier `1.6.8 → 1.6.9`.
- `PASS_PARTIAL`: dossier `1.6.8 → 1.6.9`.
- `PASS_COMPLETE`: dossier `1.6.8 → 1.7`.

The outcome-specific allowlists, subjects, marker blocks and Tasks 4–14 remain
as specified in the reconciled spec/plan. `PASS_COMPLETE` alone may authorize
CI-3 after every required BFF/public/synthetic-patient gate; CI-4 remains
unauthorized in all outcomes.

Later deployment must reuse the clean implementation worktree. No dedicated
deployment worktree is created or expected. From the SSO forward PATCH, any success or
possible success makes every later failure or ambiguity—including the forward
response and complete readback—consume the single rollback attempt. Protection
must be read back active, probes must not start or repeat, and rollback failure
or ambiguity is an immediate material-risk STOP. Authorized STOP status values are only
`NOT_VERIFIED`, `IMPLEMENTED_NOT_DEPLOYED`, `DEPLOYED_PROTECTED` and
`PUBLIC_ROLLED_BACK`.

## Preservation and action accounting for this draft

```text
RED1_EXECUTION_ATTEMPTS=0
IMPLEMENTATION_FILE_EDITS=0
IMPLEMENTATION_COMMIT_ATTEMPTS=0
IMPLEMENTATION_PUSH_ATTEMPTS=0
VERCEL_READS=0
VERCEL_WRITES=0
SUPABASE_READS=0
SUPABASE_WRITES=0
DATABASE_WRITES=0
PRODUCTION_DEPLOYMENT=NO
CI3_AUTHORIZED=NO
CI4=NO
PR=NO
MERGE=NO
GITHUB_ACTIONS=UNAVAILABLE_NOT_USED
```

The manager historical set, old detached deploy worktree, implementation
worktree, primary/live material, staging project and production remain
preserved. No secret value, Authorization header, raw origin, email, user or
patient identifier, PII or health data is recorded here.

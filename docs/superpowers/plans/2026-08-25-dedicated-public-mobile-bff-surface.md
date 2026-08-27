# Dedicated Public Mobile BFF Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** build, publish and verify a dedicated Next.js Preview artifact whose
only public application surface is the existing Mobile API V1 route set, then
authorize CI-3 only if the synthetic-patient gate also passes.

**Architecture:** `apps/mobile-bff` is a minimal Next.js app made of static,
named re-export wrappers around the 40 authoritative route modules in
`apps/admin`. Source/import/build manifests prove that admin pages, routes,
Server Actions and middleware are absent before the existing staging Vercel
project is switched to the dedicated root and its project-only SSO is removed.

**Tech Stack:** Node >=22, Next.js 15 as already locked, TypeScript, Vitest,
Corepack pnpm 10.33.2, Vercel Preview, existing Supabase staging source.

**Spec:**
`docs/superpowers/specs/2026-08-25-dedicated-public-mobile-bff-surface.md`

**RED 1 discovery reconciliation:** dossier `1.6.8` supersedes only the old
runner command and obsolete final-documentation parent/version clauses.
Tasks 4–14 remain literal and may resume only after the reconciled semantic RED
passes.

**Vercel local-link reconciliation:** for every future execution, dossier
`1.6.10` and Replacement Task 9R–16R wholly supersede legacy Tasks 9–16. The
legacy text remains historical evidence only and must not control ordering,
gates, worktree choice or final-documentation authority. Execute the
replacement only after its remote authority is confirmed; do not repeat the
consumed settings PATCH.

## Global constraints

- Set `set +x` and `umask 077` before sensitive preflights or executors.
- Never print credential values, Authorization, a raw deployment origin, PAT,
  email, user ID, patient ID or health data.
- Do not open or use
  `/root/.config/agentempp/secrets/agentempp-primary-backend.env`.
- Do not change `apps/admin`, root package metadata, workspace config,
  packages, iOS, migrations, Supabase, assets, strings or production.
- Do not fix the 21 admin findings in this gate.
- Do not use the detached worktree
  `/root/agentempp-ci3-staging-bff-v1` for implementation and do not touch the
  frozen Mac worktree.
- Do not use reset, restore, clean, stash, pull, merge, rebase, cherry-pick,
  worktree prune/repair/remove, gc, repack or broad `git add` forms.
- Use only `corepack pnpm@10.33.2`; never use global pnpm, `corepack use/up`,
  global Corepack install/enable or `--dangerously-allow-all-builds`.
- Reuse `agentempp-mobile-bff-staging`; never delete/recreate it or create a
  second project, Git Integration, custom domain, alias or bypass.
- Environment and deployment target are Preview only. Production env,
  Production deployment, production, CI-4, PR, merge, TestFlight and App Store
  are prohibited.
- Any one-attempt external write that fails or leaves partial/ambiguous state is
  a STOP. Do not retry, delete or compensate except for the explicitly
  authorized SSO rollback.
- GitHub Actions for this repository are `UNAVAILABLE — NOT USED`; run the
  documented gates locally and do not claim remote CI passed.
- Before each materially heavy phase—initial/final install, focused/full tests,
  Next build, loopback server smoke and Vercel deployment/build trigger—run
  `/root/.codex/ops/bin/vps-resource-gate.sh`. Run it again after a
  resource-related failure or concrete degradation. `BUSY` means serialize
  heavy work; `PRESSURED` requires metric-based judgment and is not itself a
  hard block; `CRITICAL` blocks heavy work until its objective cause is fixed.
- Immediately after every mutation, append a recovery-ledger record containing
  exact target, evidence/precondition, result, and rollback/restore location.
  This includes file/lockfile edits, worktree/branch, staging/index, commit,
  push, Vercel settings/env/link/deployment/SSO and external receipt writes.
  Record names/counts/fingerprints only, never secret values, Authorization,
  raw origin or PII. A missing ledger entry blocks the next mutation.

## Frozen identities and budgets

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_REMOTE_REF=refs/heads/codex/better-ahead-rebranding-design
DOCUMENTATION_BASE=6e03d5a67284204ab2781ff049ffe4df40b18961
DOCUMENTATION_BASE_PARENT=89f8bc1c41073d110fe17ee3c638da3998c31aad
DOCUMENTATION_BASE_TREE=f871f4bc2b19e84e641b202a2ecfa5ca8f3cd576
DOCUMENTATION_BASE_SUBJECT=docs(staging): record dedicated Mobile BFF stop
RED_DISCOVERY_AUTHORITY_SUBJECT=docs(staging): reconcile dedicated BFF RED discovery

IMPLEMENTATION_BASE=277873755bf29771a10b5f362b522c2e6a6c21d6
IMPLEMENTATION_BASE_PARENT=aba177d7cbb0d9cecb13c5f1099e6b99b6456c93
IMPLEMENTATION_BASE_TREE=9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4
IMPLEMENTATION_BASE_SUBJECT=feat(ios): add secure session lifecycle and user boundary
IMPLEMENTATION_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
IMPLEMENTATION_WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1
IMPLEMENTATION_SUBJECT=feat(staging): add dedicated Mobile API BFF surface
MAC_FROZEN_EVIDENCE_PATH=/Users/eduardohenrique/Developer/bodyflow-production-secret-contract-v1

VERCEL_PROJECT_NAME=agentempp-mobile-bff-staging
VERCEL_PROJECT_ID_SHA256=26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f
STAGING_PROJECT_REF=xitugspwfxkcluxvrdeg
STAGING_SECRET_FILE=/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env
STAGING_RECEIPT_FILE=/root/.config/agentempp/secrets/ci3-staging-mobile-bff.receipt.json
STAGING_URL_SHA256=97010b2e836ff65ea00286dd549c7b53588c767be3b89d3b958e5db79901c992
STAGING_ANON_SHA256=75f6096cc1475fbc3268203fdf29eea2b839fd98e82ff5e7d6c4f18b6ce1a7c1
STAGING_SERVICE_ROLE_SHA256=76f90c745c5018fce36b9ba6d8b08a2d9bae70c07d40eebf48586bd552c83472
STAGING_SECRET_FILE_SHA256=6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d
STAGING_RECEIPT_SHA256=44d0da30244f2340827698caa1aae85410b6a34d5c50a312a8b9e5e9bbe08978
PRIMARY_PROJECT_REF=xuxehkhdvjivitduarvb
PRIMARY_KEY_NAME=manager_vps_20260825
PRIMARY_KEY_STATE=ACTIVE_QUARANTINED_UNUSED
PRIMARY_SECRET_FILE=/root/.config/agentempp/secrets/agentempp-primary-backend.env
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
WRAPPER_ROUTE_EXPORT_COUNT=40
WRAPPER_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
BUILD_ROUTE_PATH_COUNT=40
BUILD_ROUTE_PATH_STREAM_SHA256=abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a
FOCUSED_SECURITY_TEST_FILE_COUNT=39
FOCUSED_SECURITY_TEST_PATH_STREAM_SHA256=586a6653c80b06d77293f0d32f6a2166fb93f935c5d53080cbd0971e60b7a3b8
PRIOR_FINDING_HTTP_PROBE_COUNT=19
PRIOR_FINDING_HTTP_PROBE_STREAM_SHA256=8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718
PRIOR_FINDING_SERVER_ACTION_COUNT=2
PRIOR_FINDING_SERVER_ACTION_STREAM_SHA256=2cc8eac1a54c3f88673701d4b9ede202f1ec4440bf414ac7696dda341bd53a35

RED_DISCOVERY_DOCUMENTATION_COMMIT_ATTEMPTS=1
RED_DISCOVERY_DOCUMENTATION_PUSH_ATTEMPTS=1
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

---

### Task 1: Publish the reconciled RED discovery authority

**Files:**

- Modify:
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`
- Create:
  `docs/superpowers/evidence/2026-08-25-ci3-red1-vitest-external-discovery-reconciliation.md`
- Modify:
  `docs/superpowers/specs/2026-08-25-dedicated-public-mobile-bff-surface.md`
- Modify:
  `docs/superpowers/plans/2026-08-25-dedicated-public-mobile-bff-surface.md`
- Modify:
  `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`

**Interfaces:**

- Consumes: documentation baseline and canonical 25-entry manager state.
- Produces: `RED_DISCOVERY_AUTHORITY_SHA`, the only authority that permits the
  reconciled semantic RED and subsequent continuation.

- [ ] **Step 1: Validate the documentation baseline before any write**

  Confirm branch, HEAD, parent, tree, subject, exact
  `DOCUMENTATION_REMOTE_REF` and empty staging.
  Run `LC_ALL=C git status --porcelain=v1 -uall` and require 25 entries, five
  tracked, 20 untracked, full stream SHA-256
  `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`,
  tracked diff SHA-256
  `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`
  and empty staged-diff SHA-256.

- [ ] **Step 2: Preserve the historical STOP and receipts**

  Record that the prior `apps/admin` root/discovery found zero test files and
  ran zero tests, without invalidating either test or the source receipt.
  Preserve source `40`, invalid exports `0`, source hash
  `7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`
  and the two physical test hashes. Mark the old relative command
  `SUPERSEDED`; do not erase its historical evidence.

- [ ] **Step 3: Freeze the reconciled command and semantic gate**

  Require absolute `WORKTREE`, explicit absolute `--config`, `--root`, `--dir`
  and both absolute test paths exactly as Task 3 Step 4 states. Prohibit
  `--passWithNoTests`, test-byte edits and package/config/GREEN artifacts before
  the first run. Freeze one execution attempt and every exact semantic field:

  ```text
  discovered files 2; both files and >0 tests executed; source 40/0/frozen hash;
  wrapper 0; MIRROR_ABSENT_ONLY; exit 1; no no-files/config/module/syntax/source
  drift; zero skip/todo/cancel
  ```

- [ ] **Step 4: Validate the five-path authority diff**

  Run `git diff --check`, inspect the integral diff and require that the changed
  paths equal the five paths listed above. Scan added content for credential or
  PAT shapes, raw real origins, PII, production authorization and CI-4
  authorization. Require dossier transition `1.6.7 → 1.6.8`, the exact
  reconciliation title, new independent budgets, worktree reuse and final
  parent/version clauses.

- [ ] **Step 5: Obtain two independent read-only documentation reviews**

  Review A checks security/route/deployment sequencing. Review B checks plan
  completeness, one-attempt budgets, Git identities, final outcomes and
  preservation. Gate: 0 Critical and 0 Important for both.

- [ ] **Step 6: Stage only the five authority paths and commit once**

  Stage every exact path individually. Require none of the 25 historical
  entries staged, run `git diff --cached --check`, inspect cached name-status
  and commit once with:

  ```text
  docs(staging): reconcile dedicated BFF RED discovery
  ```

  The parent must be `DOCUMENTATION_BASE`.

- [ ] **Step 7: Push once and prove the remote commit**

  Push the existing documentation branch fast-forward without force. Read back
  its remote ref and record the exact commit as
  `RED_DISCOVERY_AUTHORITY_SHA`. No RED or implementation continuation may
  start until the remote ref equals that SHA.

- [ ] **Step 8: Use report-only STOP if commit or push fails**

  If the authority commit fails after the five exact authority paths were
  staged, leave those five paths staged; if it fails earlier, preserve the
  exact observed index/worktree state. Record the actual staged and unstaged
  path lists, exact failed gate and next safe action, and do not reset, restore,
  unstage, amend or retry. A failed authority push preserves the single local
  commit and exact observed index/worktree state, records the actual staged and
  unstaged path lists, and permits no amend/retry.
  In either case write only `STOP_PRE_AUTHORITY` to the task report and recovery
  ledger outside Git, do not spend the final-doc budgets, do not create Git STOP
  docs, and do not execute RED, edit code/worktrees or call Vercel/Supabase.

### Task 2: Validate and reuse the isolated implementation worktree

> **Reconciled state:** this task is historical and complete. Reuse the existing
> branch/worktree; worktree creation, branch creation and upstream mutation are
> not reauthorized.

**Files:**

- Preserve/reuse existing worktree:
  `/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`
- Preserve read-only:
  `/root/agentempp-ci3-staging-bff-v1`

**Interfaces:**

- Consumes: remotely confirmed `RED_DISCOVERY_AUTHORITY_SHA` and exact CI-2
  base.
- Produces: validated existing branch
  `codex/ci3-dedicated-mobile-bff-surface-v1` with no upstream and only the two
  preserved untracked RED tests.

- [ ] **Step 1: Prove the exact existing base**

  Require `IMPLEMENTATION_BASE` to be a commit with the frozen parent, tree and
  subject. Confirm the existing local branch and implementation worktree own
  the exact identity, upstream remains absent, staging is empty, tracked state
  is clean and the only status paths are the two preserved RED tests.

- [ ] **Step 2: Preserve the old deploy worktree**

  Require `/root/agentempp-ci3-staging-bff-v1` to remain detached at
  `IMPLEMENTATION_BASE`, tracked-clean, staging-empty and without `.vercel`.
  Do not repair, remove or reuse it.

- [ ] **Step 3: Reuse the branch/worktree without recreation**

  Require exact HEAD, exact branch, empty staging, no tracked change and no
  upstream. Do not recreate, repair, remove or relink the worktree, do not
  create another branch, and do not cherry-pick documentation.

### Task 3: RED 1 — freeze source surface and prove mirror absence

**Files:**

- Preserve/reuse existing untracked:
  `apps/mobile-bff/src/source-surface.test.ts`
- Preserve/reuse existing untracked:
  `apps/mobile-bff/src/route-mirror.test.ts`

No package/config/bootstrap file is created during RED 1. The dedicated
`package.json` and `vitest.config.ts` belong to GREEN 1.

**Interfaces:**

- Consumes: frozen 40-record source route/export stream from the spec.
- Produces: a failing proof whose only expected cause is zero wrappers.

- [x] **Step 1: Historical/completed — bootstrap the existing runner**

  The prior frozen install already completed with exit 0, no tracked change and
  lockfile hash
  `2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55`.
  Do not repeat it as the normal path of the reconciled preflight.

- [x] **Step 2: Historical/completed — source-manifest test written**

  The preserved test reads route modules from the CI-2 source tree, extracts
  only named Next
  Route Handler exports, sort path/export names and assert count 40, invalid
  export count zero and canonical SHA-256 `7154a9a…79b4`. Do not rewrite it.

- [x] **Step 3: Historical/completed — wrapper-parity test written**

  The preserved test enumerates
  `apps/mobile-bff/src/app/api/mobile/v1/**/route.ts`, requires
  one wrapper per source and parse each wrapper as a single named re-export.
  It rejects extra statements, `export *`, extra paths and export mismatch. Do
  not rewrite it.

- [ ] **Step 3R: Run the exact read-only Phase B preflight**

  After remote confirmation of `RED_DISCOVERY_AUTHORITY_SHA`, set
  `WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1` and revalidate
  without mutation:

  ```text
  branch=codex/ci3-dedicated-mobile-bff-surface-v1
  HEAD=277873755bf29771a10b5f362b522c2e6a6c21d6
  parent=aba177d7cbb0d9cecb13c5f1099e6b99b6456c93
  tree=9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4
  subject=feat(ios): add secure session lifecycle and user boundary
  upstream=ABSENT
  staging=EMPTY
  tracked=clean
  untracked=exactly the two preserved RED tests
  SOURCE_SURFACE_TEST_SHA256=50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6
  ROUTE_MIRROR_TEST_SHA256=289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f
  PNPM_LOCKFILE_SHA256=2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55
  VITEST_VERSION=2.1.9
  ADMIN_VITEST_CONFIG_SHA256=8bb6705e6315f5a28bdf6cc15cae3ff7526007913c8f7c01acd7279ad0b91266
  ADMIN_VITEST_CONFIG_CONFLICTING_ROOT_OR_INCLUDE=NO
  SOURCE_ROUTE_EXPORT_COUNT=40
  SOURCE_ROUTE_INVALID_EXPORT_COUNT=0
  SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
  WRAPPER_ROUTE_EXPORT_COUNT=0
  PACKAGE_OR_CONFIG_GREEN_ARTIFACT_COUNT=0
  ```

  Require the Vitest binary to be available and run only this capability check:

  ```bash
  corepack pnpm@10.33.2 --dir "$WORKTREE/apps/admin" exec vitest --help
  ```

  The help output must document `--root`, `--dir` and `--config`. Do not run
  discovery/list or any other command that could consume the single RED
  attempt. Only if the binary is absent, run the VPS resource gate and then one
  `corepack pnpm@10.33.2 install --frozen-lockfile`; require the lockfile hash
  and all tracked bytes unchanged. Install failure or any preflight divergence
  selects `STOP_DOCUMENTED` without RED execution, test edit or GREEN artifact.

- [ ] **Step 4: Run RED 1 with the exact existing-package command**

  The previously published relative command is `SUPERSEDED`. It retained
  `apps/admin` as the effective Vitest root/discovery boundary, discovered zero
  test files, executed zero tests and exited 1 with `No test files found`; this
  was runner discovery failure, not invalid test/source bytes.

  After the remote ref confirms `RED_DISCOVERY_AUTHORITY_SHA`, set
  `WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1` and run exactly
  once:

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

  Require both test files to execute and every exact field below to be true in
  the same run:

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

  Before this run, require physical test hashes
  `50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6`
  and `289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f`.
  Do not create a package/config/GREEN artifact, use `--passWithNoTests`, edit
  either test or rerun. Any non-semantic result is a STOP. Only a fully
  approved semantic RED permits literal continuation through Tasks 4–14.

  Capture an ordered `key=value\n` transcript normalized without ANSI. Never
  use the raw transcript as a receipt. The normalized receipt must include:

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

  The command fingerprint binds the literal reconciled command, Vitest, root,
  dir, config and both absolute test paths. Missing/divergent receipt data is
  `STOP_DOCUMENTED` without rerun. After RED approval, revalidate both test
  hashes byte for byte before the first GREEN mutation.

### Task 4: GREEN 1 — package, configuration and exact wrapper mirror

**Files:**

- Create: `apps/mobile-bff/package.json`
- Create: `apps/mobile-bff/tsconfig.json`
- Create: `apps/mobile-bff/vitest.config.ts`
- Create: `apps/mobile-bff/next.config.mjs`
- Create: `apps/mobile-bff/next-env.d.ts`
- Create: `apps/mobile-bff/scripts/verify-route-mirror.mjs`
- Create: `apps/mobile-bff/src/app/api/mobile/v1/**/route.ts` (exactly 40)
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: frozen source path/export records.
- Produces: `@mpp/mobile-bff` and an exact static wrapper manifest.

- [ ] **Step 1: Add the package contract**

  Name the package `@mpp/mobile-bff`; include only scripts `build`, `test`,
  `typecheck`, `verify:routes`, `verify:imports` and
  `verify:build-surface`. Use only dependency versions already resolved in the
  lockfile.

- [ ] **Step 2: Add the monorepo-safe Next configuration**

  Configure TypeScript `@/*` to point exclusively to `../admin/src/*`, add the
  equivalent webpack alias, set `outputFileTracingRoot` to the monorepo root,
  preserve required workspace `extensionAlias`, and list only transitively
  reached packages in `transpilePackages`.

- [ ] **Step 3: Generate exact named wrappers**

  Each wrapper has this form, with names and source path substituted from the
  frozen record:

  ```ts
  export { GET, runtime } from '@/app/api/mobile/v1/today/route'
  ```

  Do not add a root page, root layout, middleware, public directory, catch-all
  or executable wrapper code.

- [ ] **Step 4: Update only the new lockfile importer**

  Use Corepack pnpm 10.33.2 to produce the new importer/package snapshot.
  Inspect the lockfile diff structurally; no existing importer range or
  resolved package version may change. Any unexpected resolution is a STOP.

- [ ] **Step 5: Run GREEN 1**

  Run the route test and `verify:routes`. Require source 40, wrappers 40,
  exact path parity, exact named-export parity, zero extra/omitted wrapper,
  zero `export *`, source hash
  `SOURCE_ROUTE_EXPORT_STREAM_SHA256` and separately named wrapper hash
  `WRAPPER_ROUTE_EXPORT_STREAM_SHA256`. The two canonical streams use their
  respective relative roots and are required to be byte-identical.

### Task 5: RED/GREEN 2 — import closure and source-surface denial

**Files:**

- Create: `apps/mobile-bff/scripts/verify-import-closure.mjs`
- Create: `apps/mobile-bff/src/import-closure.test.ts`
- Extend: `apps/mobile-bff/src/source-surface.test.ts`

**Interfaces:**

- Consumes: wrapper entrypoints and TS/Next alias configuration.
- Produces: a resolved path/classification manifest with zero denylist hits.

- [ ] **Step 1: Write failing closure/surface tests**

  Require the verifier to resolve relative and `@` imports and reject admin
  pages, admin/Inngest/Stripe/admin-media APIs, middleware,
  `public-api-path.ts`, page/layout files, public files, webhooks, panel
  callbacks and `'use server'` outside Mobile API. Source-surface tests require
  zero page, layout, middleware, public file, Server Action and out-of-prefix
  `route.ts`.

- [ ] **Step 2: Run RED 2**

  Run the focused tests before the verifier is complete. Expected: failure for
  missing closure classification/surface proof, not source-manifest drift.

- [ ] **Step 3: Implement deterministic import resolution**

  Walk imports from the 40 source modules, resolve local file extensions and
  index files consistently, classify every reached local file, and print only
  path/classification records. Explicitly allow Mobile API routes,
  `lib/mobile-api/**`, `lib/supabase/server.ts` and other non-surface libs only
  when reached and not denied.

- [ ] **Step 4: Minimize package dependencies from the proven closure**

  Declare only reached workspace/external packages. Use `@mpp/admin` as
  `workspace:*` only if install correctness requires it and never import its
  package root at runtime. Recheck that no UI dependency is present without a
  transitive import record.

- [ ] **Step 5: Run GREEN 2**

  Run tests, `verify:routes` and `verify:imports`. Require denylist hits 0,
  pages 0, layouts 0, middleware 0, Server Actions 0, public files 0 and routes
  outside the Mobile prefix 0.

### Task 6: RED/GREEN 3 — structured build-surface manifest

**Files:**

- Create: `apps/mobile-bff/scripts/verify-build-surface.mjs`
- Extend: `apps/mobile-bff/src/source-surface.test.ts`
- Modify configuration only inside `apps/mobile-bff` if RED identifies a
  missing build-surface requirement.

**Interfaces:**

- Consumes: `.next` output from the dedicated app.
- Produces: application-route and bundle-surface manifest hashes.

- [ ] **Step 1: Write build-manifest assertions before the final build**

  Parse the actual Next 15 app paths, routes, middleware and server-reference
  manifests. Reject string-only grep as the proof mechanism. Permit only the
  40 `/api/mobile/v1/**` application routes and Next-generated internal
  `/_not-found` when present.

- [ ] **Step 2: Run RED 3**

  Run `verify:build-surface` without a final build. Expected: explicit failure
  because required structured manifests are absent or incomplete.

- [ ] **Step 3: Install frozen and build with synthetic values**

  Run the VPS resource gate immediately before the install/build, then run:

  ```text
  corepack pnpm@10.33.2 install --frozen-lockfile
  NEXT_PUBLIC_SUPABASE_URL=https://staging.example.test \
  NEXT_PUBLIC_SUPABASE_ANON_KEY=<synthetic-non-secret> \
  SUPABASE_SERVICE_ROLE_KEY=<synthetic-non-secret> \
  corepack pnpm@10.33.2 --filter @mpp/mobile-bff build
  ```

  The placeholders above mean locally generated non-secret test strings; never
  substitute a real staging or primary value for this local build.

- [ ] **Step 4: Run GREEN 3**

  Normalize every structured manifest application-route entry by removing the
  trailing Next `/route` marker, preserving `[id]`/`[token]`, and excluding
  only internal `/_not-found`; then sort and encode each public URL template as
  `<route-url>\n`. Run `verify:build-surface` and require
  `BUILD_ROUTE_PATH_COUNT=40`,
  `BUILD_ROUTE_PATH_STREAM_SHA256=abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a`,
  zero admin/Inngest/Stripe/admin-media route, zero page route, middleware
  object empty and Server Action references zero. Never compare this path-only
  stream with either export-inclusive source/wrapper stream.

### Task 7: Complete local verification and loopback smoke

**Files:** implementation allowlist only; no new product surface.

**Interfaces:**

- Consumes: dedicated build and all verifier scripts.
- Produces: local gate receipt and smoke result for reviews.

- [ ] **Step 1: Run the dedicated gate sequence once after GREEN**

  Run frozen install, package test, typecheck, `verify:routes`,
  `verify:imports`, synthetic build and `verify:build-surface` after a fresh
  resource-gate PASS. Then derive the deterministic current focused-security
  superset from the immutable CI-2 Git object and execute exactly that list:

  ```bash
  set -euo pipefail
  base=277873755bf29771a10b5f362b522c2e6a6c21d6
  test_manifest=$(mktemp)
  trap 'rm -f "$test_manifest"' EXIT
  git ls-tree -r --name-only "$base" -- apps/admin/src | LC_ALL=C sort | awk '
    /^apps\/admin\/src\/lib\/mobile-api\/.*\.test\.ts$/ ||
    /^apps\/admin\/src\/app\/api\/mobile\/v1\/.*\.test\.ts$/ ||
    $0=="apps/admin/src/app/api/webhooks/revenuecat/route.test.ts" ||
    $0=="apps/admin/src/lib/billing/revenuecat-webhook.test.ts" ||
    $0=="apps/admin/src/app/(admin)/content/actions.test.ts" ||
    $0=="apps/admin/src/app/(admin)/settings/coach-messages/actions.test.ts"
  ' > "$test_manifest"
  test "$(wc -l < "$test_manifest" | tr -d ' ')" = 39
  test "$(sha256sum "$test_manifest" | cut -d' ' -f1)" = \
    586a6653c80b06d77293f0d32f6a2166fb93f935c5d53080cbd0971e60b7a3b8
  mapfile -t test_files < "$test_manifest"
  test_args=()
  for path in "${test_files[@]}"; do test_args+=("${path#apps/admin/}"); done
  (
    cd apps/admin
    corepack pnpm@10.33.2 exec vitest run "${test_args[@]}"
  )
  ```

  The 39-file stream is the exact sorted list frozen in the spec. It is a safe
  deterministic superset, not a claim that the historical unnamed 11-file
  command was recovered. Report the actual current Vitest count and require
  zero failure/skip; do not substitute historical 172/172. Run admin typecheck
  only if the alias/closure requires it. Do not rerun the historical 619-test
  suite unless a finding or attributable failure makes it necessary.

- [ ] **Step 2: Start only the dedicated build on loopback**

  Run the VPS resource gate immediately before starting the server. Use
  synthetic values, `127.0.0.1` and an ephemeral port. Record the exact created
  PID without enumerating environment-bearing process output.

- [ ] **Step 3: Probe Mobile API authentication behavior**

  Probe `/today`, `/me` and the frozen content UUID path. Require 401 auth
  behavior, JSON, `no-store`, `Vary: Authorization`, request ID, sanitized
  envelope, no HTML, stack, secret or PII.

- [ ] **Step 4: Probe forbidden routes**

  Probe `/`, `/login`, `/api/inngest`, `/api/stripe/webhook`, the
  administrative media UUID path, and every path in the frozen 19-record
  prior-finding HTTP manifest below. Require 404, zero redirect/login
  render/sensitive handler execution and no stack, secret or PII. Separately
  prove both frozen action names and all page routes absent from structured
  manifests; never invoke either action.

  ```text
  /api/admin/send-message
  /audit
  /crescimento
  /dashboard
  /evaluations
  /formulas
  /messages
  /prompts
  /prompts/00000000-0000-4000-8000-000000000000
  /settings/admins
  /settings/agents
  /settings/api-keys
  /settings/calc
  /settings/crons
  /settings/foods
  /settings/global
  /settings/tools
  /users
  /users/00000000-0000-4000-8000-000000000000
  ```

  Before requests, canonicalize these sorted records as
  `GET\0<concrete-path>\n` and require count 19 and SHA-256
  `8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718`.
  Canonicalize the manifest-only names as `deleteFood\nupsertFood\n` and
  require count 2 and SHA-256
  `2cc8eac1a54c3f88673701d4b9ede202f1ec4440bf414ac7696dda341bd53a35`.

- [ ] **Step 5: Stop only the task-owned loopback process**

  Verify the recorded PID is the process started in Step 2, terminate it, and
  confirm the port is no longer listening. Do not kill unrelated services.

- [ ] **Step 6: Run diff and boundary scans**

  Run `git diff --check`, exact allowlist comparison, lockfile-importer review,
  existing-source byte comparison, and scans for secrets, PAT/access tokens,
  real Supabase/Vercel URLs, PII, `.env`, `.vercel`, admin/iOS/docs/migration
  edits, production, CI-4, Server Actions, middleware, pages, out-of-prefix
  routes, `export *`, catch-all and hard-coded fallback.

### Task 8: Independent implementation reviews and publication

**Files:** implementation allowlist only.

**Interfaces:**

- Consumes: complete implementation diff and local receipts.
- Produces: published `DEDICATED_BFF_IMPLEMENTATION_SHA`.

- [ ] **Step 1: Run Review A — route/runtime security**

  Review path/export parity, auth lifecycle, service-role server-only behavior,
  closure, manifests, 404 boundary, zero Server Actions/middleware/pages,
  log/PII safety and unchanged official-value calculations.

- [ ] **Step 2: Run Review B — build/deployment boundary**

  Review dependency closure, lockfile, Next config, output tracing, monorepo
  root, artifact isolation, source-SHA plan, SSO sequencing, rollback and zero
  production. Both reviews must have 0 Critical and 0 Important. Corrections
  remain in allowlist and require affected gates plus both reviews again.

- [ ] **Step 3: Inspect and selectively stage the implementation**

  Show name-status, stat, full diff, route/wrapper manifests and lockfile
  importer diff. Stage exact paths individually, run
  `git diff --cached --check`, and require no source-handler change.

- [ ] **Step 4: Commit once**

  Commit with subject:

  ```text
  feat(staging): add dedicated Mobile API BFF surface
  ```

  Require parent `IMPLEMENTATION_BASE`, one commit, exact allowlist paths,
  clean worktree, empty staging and no upstream.

- [ ] **Step 5: Push once without upstream or force**

  Reconfirm the remote implementation branch is absent, then publish
  `codex/ci3-dedicated-mobile-bff-surface-v1` once. Read back the remote ref and
  record it as `DEDICATED_BFF_IMPLEMENTATION_SHA`.

### Task 9: Reconfigure the existing Vercel project once

**Files:** no Git file changes.

**Interfaces:**

- Consumes: published implementation SHA and protected existing project.
- Produces: existing project rooted at `apps/mobile-bff`, SSO still active.

- [ ] **Step 1: Revalidate the remote and project preconditions**

  Require remote implementation branch at the exact SHA and exactly one
  project named `agentempp-mobile-bff-staging` with the expected ID fingerprint,
  root `apps/admin`, Node 22.x, Next.js, external sources enabled, SSO active,
  env 0/0, deployments 0, Git Integration 0 and custom domains 0.

- [ ] **Step 2: Execute one seven-field project PATCH**

  Send exactly:

  ```json
  {
    "nodeVersion": "22.x",
    "framework": "nextjs",
    "rootDirectory": "apps/mobile-bff",
    "buildCommand": "corepack pnpm@10.33.2 --filter @mpp/mobile-bff build",
    "installCommand": "corepack pnpm@10.33.2 install --frozen-lockfile",
    "skipGitConnectDuringLink": true,
    "sourceFilesOutsideRootDirectory": true
  }
  ```

  Do not include SSO, env, team or Git repository fields.

- [ ] **Step 3: Read back and require the complete state**

  Require dedicated root, Node/framework/commands exact, external sources true,
  no Git link, SSO still active, env 0/0 and deployments 0. A failed or partial
  PATCH is `STOP_DOCUMENTED`; do not repeat.

### Task 10: Create the Preview-only environment batch

**Files:**

- Read without printing:
  `/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env`
- Read metadata/receipt without exposing values:
  `/root/.config/agentempp/secrets/ci3-staging-mobile-bff.receipt.json`
- Create/remove: root-only temporary executor outside Git.

**Interfaces:**

- Consumes: exactly three verified staging values.
- Produces: Preview env count 3, Production env count 0.

- [ ] **Step 1: Revalidate source identity without printing values**

  Require regular root-owned `0600` files, expected integral hashes, receipt
  project `xitugspwfxkcluxvrdeg`, exact three names and expected value
  fingerprints. Never source or open the primary file.

- [ ] **Step 2: Create a descriptor-based root-only executor**

  It accepts only the three allowed names, clears inherited environment, opens
  the staging source by descriptor, never prints values, sends only to the
  exact project, and removes its temporaries.

- [ ] **Step 3: Send one no-upsert Preview batch**

  Create `NEXT_PUBLIC_SUPABASE_URL` and
  `NEXT_PUBLIC_SUPABASE_ANON_KEY` as `encrypted`, and
  `SUPABASE_SERVICE_ROLE_KEY` as `sensitive`, all with target `preview` and no
  gitBranch. If authenticated official schema proof says sensitive is
  unsupported, use `encrypted`, never `plain`.

- [ ] **Step 4: Verify metadata only**

  Require Preview count 3, Production count 0, exact names/types/targets and no
  Development entry. Partial state is a STOP without retry or delete.

### Task 11: Link and deploy one protected Preview

**Files:**

- Reuse the clean implementation worktree:
  `/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`
- Local-only `.vercel` inside that implementation worktree.

**Interfaces:**

- Consumes: exact implementation SHA and protected configured project.
- Produces: one READY protected Preview with exact source proof.

- [ ] **Step 1: Revalidate the clean implementation worktree for deployment**

  Require the existing implementation worktree at the exact published
  implementation SHA, on its existing branch, tracked-clean, staging-empty and
  without upstream. Reuse it; no new/detached deployment worktree may be
  created. Never remove or change the old CI-2 deploy worktree.

- [ ] **Step 2: Link once to the exact existing project**

  Allow `.vercel` only in the implementation worktree and never stage or commit
  it. Confirm
  the linked project by ID fingerprint without printing tokens.

- [ ] **Step 3: Deploy once while SSO remains active**

  Run the VPS resource gate immediately before this remotely build-triggering
  step and serialize it with any other heavy work. Then run one
  `vercel deploy --yes` attempt with no `--prod`, alias, domain,
  promotion, redeploy, env value in argv or token in argv. Capture deployment
  identity and raw origin only in memory.

- [ ] **Step 4: Require exact deployment metadata**

  Require READY, target Preview, production NO, exact implementation source
  SHA, Next.js, root `apps/mobile-bff` and Node 22.x. Missing source SHA is a
  STOP. Preserve the deployment on every STOP.

### Task 12: Inspect the protected artifact and remove project SSO

**Files:** no Git file changes.

**Interfaces:**

- Consumes: protected READY deployment.
- Produces: reviewed dedicated public Preview or a protected STOP.

- [ ] **Step 1: Inspect the deployment while still protected**

  Inspect metadata, sanitized build logs and available output files. Prove
  exact source SHA, build command, dedicated root, route inventory match, zero
  admin route, pages, middleware and Server Actions, zero custom domains,
  Production env and Git Integration. Reconstruct the normalized remote
  build-route stream, require count 40 and
  `BUILD_ROUTE_PATH_STREAM_SHA256`; compare source and wrapper receipts against
  their separately named export-inclusive hashes, never against the build-route
  path-only hash.

- [ ] **Step 2: Run Review C — deployed artifact ingress**

  Review source SHA, route inventory, absent admin surface, absent Server
  Actions/middleware/pages, protection still active and rollback readiness.
  Gate: 0 Critical and 0 Important.

- [ ] **Step 3: Execute one project-only SSO forward PATCH**

  Send exactly:

  ```json
  {"ssoProtection":null}
  ```

  Do not alter the team default or any other protection/settings field.

- [ ] **Step 4: Read back the complete public state**

  Require project SSO null, no password protection, trusted IPs, bypass or
  exception, unchanged team default, dedicated settings preserved, deployment
  READY, Preview env 3 and Production env 0. From the moment the forward PATCH
  succeeds or may have succeeded, any failure or ambiguity—including the
  forward response and this readback—must invoke the single rollback in Task 13
  Step 4. Do not probe while state is ambiguous.

### Task 13: Run public probes with fail-closed rollback

**Files:** no Git file changes; raw origin remains memory-only.

**Interfaces:**

- Consumes: public dedicated Preview.
- Produces: accepted public probe receipt or restored SSO plus STOP.

- [ ] **Step 1: Validate transport boundary**

  Require HTTPS, valid certificate, one exact origin and zero cross-origin
  redirect. Never echo the raw origin.

- [ ] **Step 2: Probe three Mobile API routes**

  Probe `/today`, `/me` and the content UUID route under `/api/mobile/v1`.
  Require their own 401 JSON contract, `no-store`, `Vary: Authorization`,
  request ID, sanitized envelope, and zero HTML, Vercel page, stack, secret or
  PII.

- [ ] **Step 3: Probe forbidden routes and the prior 21 findings**

  Require 404 without redirect for `/`, `/login`, `/api/inngest`,
  `/api/stripe/webhook`, the administrative media UUID route, and every one of
  the exact 19 paths listed in Task 7. Recompute and require
  `PRIOR_FINDING_HTTP_PROBE_COUNT=19` and
  `PRIOR_FINDING_HTTP_PROBE_STREAM_SHA256=8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718`
  before sending requests. Use no sensitive body or mutation. Require the two
  action names `deleteFood` and `upsertFood` absent from the structured server
  reference manifest, with manifest count/hash 2 and
  `2cc8eac1a54c3f88673701d4b9ede202f1ec4440bf414ac7696dda341bd53a35`;
  never invoke them. Also require every page route absent from structured
  application manifests.

- [ ] **Step 4: Roll back SSO once after any post-forward failure or ambiguity**

  From initiation of the forward PATCH, any response that proves neither
  definite failure-without-mutation nor a safely confirmed public state is
  treated as possible success. After success or possible success, **any**
  failure or ambiguity in the forward response, Task 12 Step 4 readback, or
  Task 13 Steps 1–3 triggers the single rollback PATCH. This includes
  HTTPS/certificate/origin,
  cross-origin redirect, any wrong status including wrong 4xx, non-JSON or
  invalid envelope, missing `no-store`, `Vary` or request ID, Vercel/HTML/stack,
  secret/PII, any forbidden/19-finding 404 failure, or either action/page
  manifest failure. Send exactly:

  ```json
  {"ssoProtection":{"deploymentType":"all_except_custom_domains"}}
  ```

  Confirm protection active by readback, do not start or repeat public probes,
  preserve env and deployment, and proceed only to STOP documentation. A
  rollback failure or ambiguous rollback/readback is an immediate material-risk
  STOP; never leave a post-forward STOP documented as protected without proof.

### Task 14: Write the deployment receipt and classify the patient gate

**Files:**

- Create outside Git only after public probes pass:
  `/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json`

**Interfaces:**

- Consumes: accepted public deployment metadata.
- Produces: `SYNTHETIC_PATIENT_PATH` and authenticated-Today disposition.

- [ ] **Step 1: Write the deployment receipt atomically and exclusively**

  Use mode `0600`, owner `root:root`. Record schema/purpose/environment,
  project/deployment fingerprints, source SHA, target, Node/root, route/wrapper
  evidence as three separately named fields
  (`SOURCE_ROUTE_EXPORT_STREAM_SHA256`,
  `WRAPPER_ROUTE_EXPORT_STREAM_SHA256`,
  `BUILD_ROUTE_PATH_STREAM_SHA256`), prior-finding HTTP/action counts/hashes,
  origin fingerprint, raw origin/base only in this root-only receipt, timestamp,
  SSO state, team-default preservation, env names/counts and probe summaries.
  Record no secret value, PAT or token.

- [ ] **Step 2: Search read-only for a safe synthetic patient mechanism**

  Inspect docs, runbooks, secret metadata, smoke scripts, sanitized inventory,
  Mac Keychain handoff and staging fixtures without printing identity or
  credential data. VERIFIED requires an explicitly synthetic staging patient,
  confirmed email, patient role, active/non-admin/non-blocked/non-deleted state,
  approved credential mechanism, runtime token and never service-role bearer.

- [ ] **Step 3: Classify without provisioning**

  Set `SYNTHETIC_PATIENT_PATH=VERIFIED` or `MISSING`. Do not create a user,
  reset/change password, confirm email or create profile. If runtime credentials
  exist on VPS, run authenticated Today entirely in memory. If an approved
  Mac-only mechanism is proven, set
  `AUTHENTICATED_TODAY_PROBE=DEFERRED_TO_MAC_BY_DESIGN`.

### Task 15: Publish final documentation for exactly one outcome

**Files:** outcome-specific allowlist below only.

**Interfaces:**

- Consumes: all local/external receipts and outcome classification.
- Produces: final documentation commit and exact next gate.

- [ ] **Step 0: Re-enter and validate the documentation manager**

  Require branch `DOCUMENTATION_BRANCH`, HEAD exactly the published
  `RED_DISCOVERY_AUTHORITY_SHA`, exact `DOCUMENTATION_REMOTE_REF` at that same
  SHA, empty staging, and the canonical 25 historical entries/count/hash and
  historical tracked diff preserved. Any mismatch is a STOP before final-doc
  edits; do not use the implementation worktree for documentation.

- [ ] **Step 1: Select `PASS_COMPLETE`, `PASS_PARTIAL` or `STOP_DOCUMENTED`**

  `PASS_COMPLETE` requires all BFF/public gates plus patient VERIFIED and
  authenticated Today PASS or deferred by design. `PASS_PARTIAL` requires all
  BFF/public gates but patient MISSING. Every other material divergence is
  `STOP_DOCUMENTED`.

- [ ] **Step 2A: Build PASS_COMPLETE documentation only when eligible**

  Use exactly this five-path allowlist:

  ```text
  docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
  docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-authority.md
  docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
  docs/superpowers/specs/2026-08-25-ci3-today-staging-vertical-slice.md
  docs/superpowers/plans/2026-08-25-ci3-today-staging-vertical-slice.md
  ```

  Update dossier `1.6.8` to `1.7`. Record authority/implementation SHAs,
  trees/paths, all three route stream counts/hashes, closure/lockfile/tests/
  typecheck/build/smoke/reviews, Vercel fingerprints, exact source/root/Node,
  Preview env 3/Production env 0, project SSO null, unchanged team default,
  401/headers, base forbidden and 19/19 finding 404s, 2/2 action manifest
  absence, patient/auth disposition, receipt and zero production. Authorize
  CI-3, keep CI-4 unauthorized, publish the complete PASS_COMPLETE marker block
  and generate the complete Mac `IMPLEMENT_CI3_TODAY_STAGING` prompt. Commit
  subject:

  ```text
  docs(ios): authorize CI-3 after dedicated Mobile BFF verification
  ```

- [ ] **Step 2B: Build PASS_PARTIAL documentation only when eligible**

  Use exactly this three-path allowlist:

  ```text
  docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
  docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-preview-verification.md
  docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
  ```

  Update dossier `1.6.8` to `1.6.9`, record verified BFF/public evidence, keep
  CI-3 unauthorized, publish the complete PASS_PARTIAL marker block and
  generate the complete
  `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING` prompt. Commit subject:

  ```text
  docs(staging): record verified dedicated Mobile BFF preview
  ```

- [ ] **Step 2C: Build STOP documentation for any STOP**

  Use exactly this three-path allowlist:

  ```text
  docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
  docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-stop.md
  docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
  ```

  Update dossier `1.6.8` to `1.6.9`; record the last passed gate, failed gate,
  code branch/SHA if any, project/env/deployment state, SSO forward/rollback,
  probes, preserved resources, no retries, production untouched, CI-3
  unauthorized, the complete STOP marker block and exact next gate. Commit
  subject:

  ```text
  docs(staging): record dedicated Mobile BFF stop
  ```

- [ ] **Step 3: Run final documentation gates**

  Require initial staging empty, exact outcome allowlist, `git diff --check`,
  integral diff, no credential/PAT/raw origin/PII, no production or CI-4
  authorization, and two independent reviews at 0 Critical/0 Important. Stage
  paths individually; no historical manager path may be staged. Recheck exact
  branch/HEAD/remote ref immediately before staging and immediately before
  push.

- [ ] **Step 4: Commit and push once**

  Parent must be exactly `RED_DISCOVERY_AUTHORITY_SHA`. Create one
  outcome-specific commit with the exact subject above and one non-force
  fast-forward push to `DOCUMENTATION_REMOTE_REF`, without tag, PR or merge.
  Read back and record exact local/remote SHA. Log every edit/index/commit/push
  mutation before proceeding to the next one.

### Task 16: Final preservation and report

**Files:** no new Git paths beyond the selected final documentation allowlist.

**Interfaces:**

- Consumes: final documented outcome.
- Produces: complete operational report and preservation proof.

- [ ] **Step 1: Revalidate every preserved Git/worktree state**

  Manager: final documented HEAD, empty staging, canonical 25 historical
  entries and historical tracked diff preserved. Existing deploy worktree:
  detached at exact CI-2 SHA, tracked-clean, staging empty and `.vercel`
  absent. Exact Mac evidence path remains untouched. Implementation worktree:
  published commit, tracked-clean, staging empty, no upstream, with local
  `.vercel` present only there if linked, untracked/unstaged and containing no
  Git-tracked secret. No dedicated deployment worktree exists or is expected.

- [ ] **Step 2: Revalidate external preservation**

  Primary key remains active/quarantined/unused with zero key mutation,
  database write, deploy or restart. Vercel retains one exact project, final
  dedicated root, Preview env 3, Production env 0, at most one Preview
  deployment, zero Production deployment/custom domain/Git Integration and SSO
  null only for accepted public outcomes or restored for a post-public STOP.

- [ ] **Step 3: Report exact attempts and boundaries**

  Populate every group and field below; use exact values, counts or explicit
  `NO`/`N/A`, never omit a group and never report a raw origin:

  ```text
  OPERATION, FINAL_STATUS
  DOCUMENTATION_BASELINE: initial SHA, parent, tree, subject, remote, dossier version
  RED_DISCOVERY_AUTHORITY: paths, reviews, commit, parent, tree, subject, push, remote
  IMPLEMENTATION_BASELINE: worktree, branch, HEAD, staging, status, test hashes,
    lockfile hash, Vitest version
  RED1_RECONCILED: exact command, command fingerprint, Vitest version, root, dir,
    config, discovered files, executed/passed/failed/skipped tests, exit,
    source count/invalid/hash, wrapper count, failure classifications,
    RED1_RECONCILED_NORMALIZED_LOG_SHA256
  IMPLEMENTATION: base, branch, worktree, commit, parent, tree, subject, path count,
    wrapper count, source/wrapper/build-route hashes, import closure, lockfile,
    tests, typecheck, build, local smoke, reviews, push, remote
  VERCEL_PROJECT: name, ID fingerprint, settings attempts, root, Node, framework,
    build/install, outside-root, Git Integration, custom domains, team default
  VERCEL_ENV: batch attempts, names, types, targets, Preview/Production counts,
    values printed NO, primary secret used NO
  DEPLOYMENT: link/deployment attempts, ID fingerprint, source SHA, target,
    ready state, root, Node, origin fingerprint, raw origin reported NO,
    protected inspection
  SSO: initial, forward attempts, final, rollback attempts, team default changed NO
  PUBLIC_PROBES: Mobile 401 count, forbidden 404 count, finding 19/19,
    actions 2/2 absent, no-store, Vary, request ID, redirect, HTML, stack,
    secret, PII
  SYNTHETIC_PATIENT: status, mechanism, created NO, PII reported NO
  AUTHENTICATED_TODAY: PASS|DEFERRED_TO_MAC_BY_DESIGN|NOT_EXECUTED|FAILED
  DEPLOYMENT_RECEIPT: path, mode, hash, raw origin only there YES, secret values NONE
  FINAL_DOCUMENTATION: outcome, dossier version, commit, parent, tree, subject, push, remote
  PRESERVATION: manager 25, existing old deploy staging/.vercel,
    implementation worktree and its local .vercel, no dedicated deployment
    worktree, primary/live, Vercel, production, CI-4
  EXTERNAL_ACTIONS: docs commits 1-2, code commit/push 0/1,
    settings/env/deployment/SSO forward/rollback 0/1 each,
    Production deployment NO, Supabase/database write NO, PR/merge/CI-4 NO
  ```

  Explicitly report GitHub Actions `UNAVAILABLE — NOT USED`.

## Outcome markers

For `PASS_COMPLETE`:

```text
DEDICATED_MOBILE_BFF_STATUS=VERIFIED
DEDICATED_MOBILE_BFF_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
DEDICATED_MOBILE_BFF_SHA=<exact implementation SHA>
STAGING_BFF_STATUS=VERIFIED
STAGING_BFF_PROJECT=agentempp-mobile-bff-staging
STAGING_BFF_TARGET=PREVIEW
STAGING_BFF_ROOT=apps/mobile-bff
STAGING_BFF_NODE_VERSION=22.x
STAGING_BFF_SOURCE_SHA=<exact implementation SHA>
STAGING_TODAY_UNAUTHENTICATED_PROBE=VERIFIED
STAGING_FORBIDDEN_SURFACE_PROBES=VERIFIED
SYNTHETIC_PATIENT_PATH=VERIFIED
CI3_STAGING_AUTHORITY_STATUS=VERIFIED
CI3_DOCUMENTATION_STATUS=PUBLISHED
CI3_DOCUMENTATION_REMOTE_SHA=<exact final docs SHA>
NEXT_ENVIRONMENT=MAC_LOCAL
NEXT_GATE=IMPLEMENT_CI3_TODAY_STAGING
```

For `PASS_PARTIAL`:

```text
DEDICATED_MOBILE_BFF_STATUS=VERIFIED
DEDICATED_MOBILE_BFF_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
DEDICATED_MOBILE_BFF_SHA=<exact implementation SHA>
STAGING_BFF_STATUS=VERIFIED
STAGING_BFF_PROJECT=agentempp-mobile-bff-staging
STAGING_BFF_TARGET=PREVIEW
STAGING_BFF_ROOT=apps/mobile-bff
STAGING_BFF_NODE_VERSION=22.x
STAGING_BFF_SOURCE_SHA=<exact implementation SHA>
STAGING_TODAY_UNAUTHENTICATED_PROBE=VERIFIED
STAGING_FORBIDDEN_SURFACE_PROBES=VERIFIED
SYNTHETIC_PATIENT_PATH=MISSING
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING
```

For `STOP_DOCUMENTED`:

```text
DEDICATED_MOBILE_BFF_STATUS=<NOT_VERIFIED|IMPLEMENTED_NOT_DEPLOYED|DEPLOYED_PROTECTED|PUBLIC_ROLLED_BACK>
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=<0_OR_1>
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=<0_OR_1>
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=<0_OR_1>
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=<0_OR_1>
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=<0_OR_1>
NEXT_ENVIRONMENT=VPS
NEXT_GATE=<exact material gate>
```

Do not execute the next gate in the final documentation task.

### Replacement Task 9R–16R: local-link control and CI-3 continuation

**Authority:** `LINK_SCHEMA_AUTHORITY_SHA`, published with subject
`docs(staging): reconcile Vercel local-link control` and dossier 1.6.10.

The historical seven-field Task 9 PATCH remains consumed. Its six persistent
settings passed; the deprecated optional `skipGitConnectDuringLink` field was
absent/null. Classification B makes Project `link` the sole material Git gate.
Never repeat the settings PATCH.

```text
PROJECT_GIT_LINK_BEFORE_LOCAL_LINK=ABSENT
LOCAL_LINK_COMMAND=VERCEL_LINK_PROJECT_EXPLICIT
LOCAL_LINK_REPO_FLAG=ABSENT
VERCEL_GIT_CONNECT_EXECUTED=NO
PROJECT_GIT_LINK_AFTER_LOCAL_LINK=ABSENT
LOCAL_PROJECT_JSON_MATCH=YES
```

- [ ] Revalidate manager 25/5/20, implementation local/remote exact and clean,
  old CI-2 deploy worktree clean, staging secret metadata/hashes, primary source
  unopened, exact Vercel settings, `link` absent, env 0/0/0, deployments 0,
  custom domains 0, SSO active and all other protection exceptions absent.
- [ ] Create exactly one detached worktree
  `/root/agentempp-ci3-dedicated-mobile-bff-deploy-v1` at
  `e3e1e252b48e42554e75899b950692c05186f60d`. Require exact tree, clean tracked
  state, empty staging, no branch/upstream, `.vercel` absent and ignored.
- [ ] Require `PROJECT_GIT_LINK_BEFORE_LOCAL_LINK=ABSENT`; run once, inside that
  worktree, `vercel link --yes --project agentempp-mobile-bff-staging --scope
  gestao-9664s-projects`. `--repo` and `vercel git connect/disconnect` are
  prohibited.
- [ ] Validate local `.vercel/project.json` as a regular non-symlink file with
  matching project-ID fingerprint and org/scope, no token/secret/env, ignored
  and unstaged. Require remote Project `link` still absent, Git Integration 0,
  settings preserved, env 0, deployment 0 and SSO active.
- [ ] Validate the root-only staging source/receipt without printing values;
  create exactly three Preview-only env variables in one no-upsert batch, with
  the two public variables encrypted and service role sensitive unless current
  official schema proves sensitive unsupported. Require Preview 3,
  Production/Development 0.
- [ ] Run pre-deploy review at 0 Critical/Important, resource gate, and one
  `vercel deploy --yes --meta
  githubCommitSha=e3e1e252b48e42554e75899b950692c05186f60d`. No prod, repo,
  alias, domain, token or env value in argv. Require READY Preview and exact
  metadata; combine declarative metadata with detached SHA/tree and receipts.
- [ ] While SSO is active, inspect sanitized metadata/logs/artifacts and obtain
  Review C at 0 Critical/Important. Require dedicated root, Node 22.x, exact
  40-route/build receipts, zero pages/middleware/Server Actions/admin surface,
  Git Integration 0 and Production env/deployment 0.
- [ ] Execute the original one-attempt SSO forward only after Review C. From
  possible success onward, any ambiguity or public-probe failure triggers the
  original single fail-closed rollback and forbids reprobe.
- [ ] After accepted public probes, write the root-only deployment receipt and
  classify the synthetic patient read-only as VERIFIED or MISSING; never create
  or mutate a user.
- [ ] Publish exactly one final outcome document with parent
  `LINK_SCHEMA_AUTHORITY_SHA`: PASS_COMPLETE `1.6.10→1.7`, PASS_PARTIAL
  `1.6.10→1.6.11`, or STOP_DOCUMENTED `1.6.10→1.6.11`, using the exact
  2026-08-26 allowlist and subject from the operation authority.

Fresh budgets:

```text
DEDICATED_DEPLOY_WORKTREE_CREATION_ATTEMPTS=1
VERCEL_LOCAL_LINK_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Final preservation requires manager history intact; implementation and old
deploy worktrees untouched; dedicated deploy worktree detached/clean with
only ignored local `.vercel`; primary/live unused; no Production, CI-4, PR,
merge, Git Integration or custom domain.

### Replacement diagnostic STOP after the Preview env client failure — dossier 1.6.12

The 1.6.11 env batch cannot resume. Read-only evidence proves CLI 50.35.0
supports `--input -`, the authenticated OpenAPI accepts the intended batch and
the preserved auth/scope context passes. The old source/argv/raw error is no
longer recoverable, so the primary cause is `UNRESOLVED`; do not substitute an
input-path or schema diagnosis.

The installed CLI's internal default retries and unbounded request/response
parsing also make the proposed root-only temp-input mechanism incompatible with
the current one-request/no-auto-retry/bounded contract. No corrected executor,
self-test, staging secret read, POST, env delete, deployment or SSO action is
authorized.

- [x] Recover only sanitized evidence and mark the missing executor/argv/error
  preimage `UNRECOVERED`.
- [x] Audit CLI help/source, refresh and parse current OpenAPI, and execute only
  read-only minimal-child-env probes.
- [x] Obtain independent client/API and secret/filesystem reviews at 0
  Critical/0 Important.
- [ ] Publish this five-path reconciliation from exact parent
  `79fa426b5293489666cc491225f1e9504c076a98` with subject
  `docs(staging): reconcile Vercel Preview env batch client`.
- [ ] Stop after remote confirmation; do not execute the next gate.

```text
ROOT_CAUSE_PRIMARY=UNRESOLVED
ROOT_CAUSE_SECONDARY=CLIENT_RUNTIME_EXECUTION_ERROR
ROOT_CAUSE_SECONDARY_DETAIL=UNCLASSIFIED
ENV_BATCH_RETRY_AUTHORIZED=NO
VERCEL_PREVIEW_ENV_BATCH_RETRY_ATTEMPTS=0/0_NOT_ACTIVATED
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE
```

The next authority must define how to preserve a semantic sanitized client/API
failure receipt and a transport with provable single-request and byte-bound
behavior. It must grant a new explicit budget before any POST. Do not execute
that next gate here.

### Replacement Task 17R–25R: bounded env transport and dedicated Preview continuation — dossier 1.6.13

Authority parent is the 1.6.12 documentation SHA
`8085a1d88d9fa0b0afe632a4395b5550b05d4b28`. The authority commit subject is
`docs(staging): authorize bounded Vercel env transport`. No mutating Vercel
request may occur before its fast-forward push is confirmed.

- [x] Preserve the historical failure as
  `UNRECOVERABLE_NON_DECISIVE`; prove remote env/deployment state remains zero.
- [x] Audit the installed credential store without reporting its value and
  cache the authenticated OpenAPI contract.
- [x] Build the root-only V1 transport outside Git with closed modes, fixed
  origin, one request per operation, zero retry/redirect, bounded bytes,
  timeout, claims and atomic sanitized receipts.
- [x] Complete exactly 30 synthetic tests with zero network/secrets and static
  scans with one `https.request` callsite.
- [x] Remediate independent Review A/B findings and obtain final gates:
  Review A `0C/0I/0M`, Review B `0C/0I/2M`.
- [x] Execute only the real Project GET and Env GET preflight. Require exact
  settings/link/SSO, deployments 0 and env 0/0/0; preserve receipt SHA-256
  `25bb55fe10141d275a7fea582d3aedbb47712e711a4137b74513e65c80c0c539`.
- [x] Freeze source/test at root-owned `0400` with hashes
  `b21520e29d260a01cecff1bad17d5f05fb50bffd976aa664afec53bed36d06df`
  and `fb5a222849adb3e6902dcc5015acf3608cf194ec5dd0103200f84abb621b6198`.
- [ ] Publish exactly the five-path authority allowlist from the exact parent,
  after two documentation reviews at 0 Critical/Important.
- [ ] After remote confirmation only, create one atomic root-owned `0600`
  source receipt at
  `/root/.config/agentempp/control-plane/ci3-vercel-one-shot-v1.source.receipt.json`.
  Require immediate absence,
  exact four-field schema (`authority_sha`, `source_sha256`, `test_sha256`,
  `rollback_authorized=true`), same-directory `O_EXCL|O_NOFOLLOW` temp,
  complete write/file fsync, atomic no-overwrite hard link, parent fsync,
  temporary-link-only unlink, second parent fsync and final
  root/0600/regular/non-symlink/link-count-one descriptor readback. Pre-push
  status is exactly `PENDING_POST_PUSH_BINDING`.
- [ ] Revalidate manager `25` historical entries, all three worktrees,
  project metadata, frozen source/test, source/preflight receipts, staging
  metadata/fingerprints, and absent env claim/receipt. The primary source must
  remain unopened.
- [ ] Execute `--execute-env-batch` exactly once. Require request 1, retry 0,
  HTTP 201, exact created metadata, failed 0 and exact GET inventory 3/0/0.
  Preserve claim/receipt on every outcome; never retry/delete/upsert.
- [ ] Only after verified env 3/0/0, run deployment preflight, VPS resource
  gate and exactly one non-production `vercel deploy --yes --meta
  githubCommitSha=e3e1e252b48e42554e75899b950692c05186f60d` in the dedicated detached
  worktree. Require READY Preview and exact source/root/Node/framework.
- [ ] With Project SSO still active, inspect artifacts/logs/routes and obtain
  Review C at 0 Critical/Important. Require 40 Mobile API routes and zero
  forbidden/admin/page/middleware/Server Action surface.
- [ ] Execute one SSO forward through the V1 transport. Require explicit null,
  exact env 3/0/0, absent link and the READY Preview deployment bound to the
  implementation SHA.
- [ ] Run public Mobile 401 and frozen forbidden 404 probes. Any failure creates
  the provenance-bound failed-probe receipt and permits exactly one protective
  SSO rollback; never reprobe.
- [ ] On public PASS, create the protected deployment receipt and perform only
  read-only synthetic-patient discovery. Publish exactly one final outcome:
  `PASS_COMPLETE`, `PASS_PARTIAL`, or `STOP_DOCUMENTED`.

Phase D publication budgets activated by the current operation authority:

```text
ONE_SHOT_TRANSPORT_DOCUMENTATION_COMMIT_ATTEMPTS=1
ONE_SHOT_TRANSPORT_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Operational and final-outcome budgets activated only by confirmed remote
publication:

```text
VERCEL_PREVIEW_ENV_ONE_SHOT_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_FORWARD_ONE_SHOT_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ONE_SHOT_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Do not renew project creation, settings PATCH, local link, CLI env batch or
implementation publication. Production, Supabase/database writes, primary/live
use, CI-4, PR, merge, tags, TestFlight and App Store remain prohibited.
Authority commit/push failure is `STOP_PRE_AUTHORITY`: do not create the source
receipt, open staging values or execute POST.

### Replacement Task 26R–34R: three single-object Preview upserts and CI-3 continuation — dossier 1.6.15

This replacement wholly supersedes the V1 env-batch execution and every later
V2/V3/V4 proposal for this continuation. V1–V4 remain immutable and may not be
executed. No V5 is created. The historical array transport is rejected; the
active operation is
`RECONCILE_VERCEL_CLI_JSON_ARRAY_TRANSPORT_WITH_SINGLE_OBJECT_UPSERTS_AND_RESUME_CI3`.

- [ ] Publish exactly the four-path documentary authority from parent
  `73f5a0b2ad633d7302f636168a01e297c5c00d18`, subject
  `docs(staging): authorize single-object Preview env upserts`, after two
  documentation reviews at 0 Critical/Important and one fast-forward push.
- [ ] Only after remote confirmation, create root-only emitter/runner and
  claim directory outside Git. Use TDD with at least 24 synthetic tests,
  `node --check`, static scans and one independent 0 Critical/Important review.
- [ ] Immediate preflight requires exact manager/worktrees, exact project
  settings/link/SSO, env `0/0/0`, deployments 0, three absent claims, frozen
  staging file/receipt hashes and fingerprints, and unopened primary/live.
- [ ] Operation A invokes CLI once for `NEXT_PUBLIC_SUPABASE_URL`, encrypted
  Preview object with `upsert=true`; require stable metadata-only readbacks at
  +15/+30/+60 and exact inventory 1.
- [ ] Only after A, Operation B invokes CLI once for
  `NEXT_PUBLIC_SUPABASE_ANON_KEY`, encrypted Preview object; require the same
  readbacks and exact inventory 2.
- [ ] Only after B, Operation C invokes CLI once for
  `SUPABASE_SERVICE_ROLE_KEY`, sensitive Preview object; require the same
  readbacks and exact inventory 3. Never downgrade the type.
- [ ] Each pre-invocation claim is exclusive and permanent, with logical
  budget/count one. Internal CLI retries are accepted only inside that
  invocation with identical content. There is no external retry, second
  logical invocation, delete or correction. Zero/partial/wrong/oscillating
  state is STOP. CLI nonzero is accepted only when exact stable state is
  independently verified.
- [ ] After env `3/0/0`, remove only emitter/runner and their owned temporaries,
  preserve claims, run pre-deploy review and VPS resource gate, then execute
  one Preview deploy with metadata binding implementation SHA
  `e3e1e252b48e42554e75899b950692c05186f60d`.
- [ ] Require READY Preview, exact source/root/Node/framework and protected
  Review C at 0 Critical/Important before one SSO forward. Stable SSO readbacks
  precede public probes.
- [ ] Project GET at +10/+20/+40 must prove the forward state. A divergence is
  STOP without second forward and without rollback. Only stable forward state
  unlocks public probes. A probe failure triggers one rollback using the frozen
  descriptor, stable protection readbacks, no reprobe and preserved
  env/deployment. Rollback ambiguity is a material-risk STOP.
- [ ] On public PASS, create the root-only deployment receipt, discover a
  synthetic patient read-only and publish exactly one outcome from parent
  `SINGLE_OBJECT_AUTHORITY_SHA` using the complete contracts below.

Final outcome contracts:

The contracts below wholly supersede Task 15 and every older final-documentation
allowlist, dossier transition, subject and macro-prompt instruction. Historical
outcome instructions are evidence only and are not executable in this operation.

- PASS_COMPLETE uses exactly
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-authority.md`,
  `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`,
  `docs/superpowers/specs/2026-08-27-ci3-today-staging-vertical-slice.md` and
  `docs/superpowers/plans/2026-08-27-ci3-today-staging-vertical-slice.md`; moves
  `1.6.15→1.7`; subject
  `docs(ios): authorize CI-3 after dedicated Mobile BFF verification`; one
  commit/push; generates the integral Mac macro-prompt.
- PASS_PARTIAL uses exactly
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`
  and `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`;
  moves `1.6.15→1.6.16`; subject
  `docs(staging): record verified dedicated Mobile BFF preview`; one
  commit/push; generates `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`
  without creating a user.
- STOP_DOCUMENTED uses exactly
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-single-object-env-or-mobile-bff-stop.md`
  and `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`;
  moves `1.6.15→1.6.16`; subject
  `docs(staging): record single-object Preview env or Mobile BFF stop`; one
  commit/push; records key/gate, logical count, command exit, retry model,
  readbacks, final env, deployment/SSO/probes, zero second invocation/delete,
  preserved resources, untouched Production, unauthorized CI-3 and exact next
  gate.
- Every final commit requires empty initial staging, exact allowlist,
  `git diff --check`, full diff and sensitive scan, zero Production/CI-4, two
  reviews at zero Critical/Important, selective staging without historical
  paths, exact parent and one non-force commit/push with no tags, PR or merge.

```text
VERCEL_JSON_ARRAY_TRANSPORT=REJECTED
VERCEL_SINGLE_PLAIN_OBJECT_TRANSPORT=SUPPORTED
VERCEL_INTERNAL_RETRIES=ACCEPTED_PER_LOGICAL_KEY_UPSERT
SINGLE_OBJECT_AUTHORITY_COMMIT_ATTEMPTS=1
SINGLE_OBJECT_AUTHORITY_PUSH_ATTEMPTS=1
VERCEL_ENV_LOGICAL_INVOCATIONS_MAX=3
VERCEL_ENV_LOGICAL_INVOCATIONS_PER_KEY_MAX=1
VERCEL_ENV_SECOND_LOGICAL_INVOCATION=FORBIDDEN
VERCEL_ENV_DELETE=FORBIDDEN
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_FORWARD_LOGICAL_INVOCATIONS=1
VERCEL_PROJECT_SSO_ROLLBACK_LOGICAL_INVOCATIONS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
PRODUCTION=UNTOUCHED
CI4=NOT_STARTED
```

Authority commit/push failure is `STOP_PRE_AUTHORITY`: no emitter/runner,
staging-value read, claim, POST, deploy or PATCH may occur. Every mutation must
be ledgered immediately; no mutation budget may be delegated.

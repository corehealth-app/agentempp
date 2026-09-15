# Performe AI — onboarding publication lifecycle local evidence

**Operation:** `IMPLEMENT_ONBOARDING_PUBLICATION_LIFECYCLE_V1`

**Date:** 2026-09-15

**Scope:** local migration, transactional SQL tests, focused application
regressions and documentary readiness update. No remote provider was accessed or
changed.

## Baseline

- Host: `MacBook-Air-de-Eduardo.local`, Darwin arm64, local user context.
- Classification: `LOCAL_DEVELOPMENT`.
- Worktree: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch: `codex/performe-ai-client-beta-flow-v1`.
- Starting HEAD: `fe75f66fbbd95f5075f427bf104e4536c47cabb1`.
- Parent: `61b674f8de8db16054f34429a3559eef31419121`.
- Starting tree: `6544aa7063c34d855e497e584bd6b15ed2ce24ca`.
- Starting worktree and index: clean.
- Frozen STOP evidence SHA-256:
  `84d0f7e39d9b3b577225fddeb4109d2d468aa2fe33ea01335a22159570f81dc4`;
  the file was verified and not changed.

## Revalidated cause

The original migration
`20260915150739_bodyflow_server_owned_onboarding.sql` constrained both
`onboarding_legal_documents.publication_status` and
`onboarding_legal_requirement_sets.publication_status` to `published`, required
non-null `published_at`, and attached
`private.reject_onboarding_legal_mutation()` to every UPDATE/DELETE. Both the
Admin repository and `complete_mobile_onboarding_atomic` select only effective
published requirement sets and documents. Consequently a selected synthetic QA
set had no legitimate closeout transition and remained current.

The requirement-set logical selection key is `locale`; no cohort or other scope
column exists. Requirement sets reference documents by immutable
`document_keys`, while acceptances retain the exact document UUID, version,
locale, hash, purpose and action.

## TDD RED

The new lifecycle test was created before the lifecycle migration. Against the
original schema:

1. Inserting an `inactive` document failed with
   `violates check constraint "onboarding_legal_documents_publication_check"`.
2. Updating a published document to archived failed with
   `Onboarding legal records are immutable`.
3. Updating a published requirement set to archived failed with the same
   immutable-record error.
4. A transactional closeout probe caught the rejected archive and confirmed
   `RED-4 confirmed: QA set remains selected after archive rejection`.

The first whole-file lifecycle run also failed on the absent expected function
`public.publish_onboarding_legal_document(uuid)`. These were semantic failures,
not syntax failures.

## Migration and lifecycle

Exactly one later migration was added:
`supabase/migrations/20260915193114_onboarding_publication_lifecycle.sql`.
The original migration was not modified.

Implemented states:

```text
inactive -> published -> archived
```

- New documents and requirement sets default to `inactive` and must have null
  lifecycle timestamps.
- Direct INSERT as `published` or `archived` is rejected by database triggers.
- Content, URL, hash, key, version, locale, action, purpose, required flag,
  effective time, composition, identity and creation time remain immutable.
- DELETE remains rejected.
- Publishing and archiving use server timestamps.
- Repeated publish of a published row and repeated archive of an archived row
  are stable, non-mutating outcomes.
- Archived rows cannot be republished or returned to inactive; published rows
  cannot return to inactive.

Trusted lifecycle functions:

- `public.publish_onboarding_legal_document(uuid)`
- `public.archive_onboarding_legal_document(uuid)`
- `public.publish_onboarding_legal_requirement_set(uuid)`
- `public.archive_onboarding_legal_requirement_set(uuid)`

All four are `SECURITY DEFINER`, use the pinned
`pg_catalog, public, private, extensions, pg_temp` search path, call
`private.assert_trusted_backend()`, revoke execution from PUBLIC/anon/
authenticated, and grant execution only to `service_role`. Direct table
INSERT/UPDATE/DELETE remains unavailable to `service_role`.

Every lifecycle transition writes a metadata-only `audit_log` event. No legal
body or credential is copied to the audit entry.

## Replacement, dependency and no-fallback rule

Publishing a requirement set takes a transaction-scoped advisory lock keyed by
locale, validates that every referenced current document is effective,
published and required, archives every currently published same-locale
predecessor, and publishes the target in the same transaction. Other locales
are untouched.

Archiving the current requirement set archives the target and any still-
published same-locale predecessor not newer than it. Therefore an archived V2
cannot expose an obsolete V1 through the unchanged GET query. A failed
replacement leaves the previous current set published and the invalid target
inactive.

A document archive is rejected while any currently eligible published
same-locale requirement set contains its key. The safe closeout order is set
first, documents second. Historical `user_onboarding_legal_actions` are never
updated or deleted.

## Local SQL evidence

The final local database was a task-owned PostgreSQL 17 container in the
task-owned Colima profile `performe-onboarding-lifecycle`. Migrations were
applied in lexical order through the original onboarding migration and the new
lifecycle migration. The minimal local Storage/Auth bootstrap existed only
inside the disposable database because the reduced CLI stack does not start
those services.

- `bodyflow_onboarding_publication_lifecycle.sql`: PASS, transaction rolled
  back.
- `bodyflow_server_owned_onboarding.sql`: PASS, transaction rolled back.
- Lifecycle RPC static `plpgsql_check`: zero findings for all four RPCs.
- Concurrent same-locale publish probe: both sessions exited 0; final state was
  exactly one published set, V1 archived and V2 published.
- Legacy compatibility database: a pre-migration published document and set
  remained published after migration; their exact
  `2026-09-02T00:00:00Z` publication timestamps were preserved and
  `archived_at` remained null.

The central closeout simulation proved:

```text
inactive documents/set
-> publish documents
-> publish set
-> completion records exact actions
-> publish V2 and atomically archive V1
-> archive V2 with no V1 fallback
-> completion fails closed
-> archive documents
-> historical actions remain present and immutable
```

## Application regressions

- Monorepo test gate with the repository-pinned `pnpm` 10.33.2: PASS — 7/7
  Turbo tasks.
- Admin focused onboarding: PASS — 3 files, 19 tests.
- Mobile BFF complete: PASS — 4 files, 26 tests.
- Admin typecheck: PASS.
- Mobile BFF typecheck: PASS.
- Admin production build: PASS.
- Mobile BFF production build: PASS, 41 Mobile API routes.
- Public onboarding JSON contract: unchanged.
- Admin query assertions explicitly prove that both requirement sets and
  documents remain filtered to `publication_status = 'published'` and effective
  time.

Next emitted pre-existing static-analysis warnings for typed-routes placement in
Admin and re-exported route runtime metadata in the dedicated BFF. No new build
failure was introduced.

Two initial monorepo test-launch attempts inherited the host fallback `pnpm`
11.19.0 instead of the repository-pinned 10.33.2 and stopped before tests while
trying to purge `node_modules` without a TTY. The passing run used a temporary
PATH-only symlink to the already cached Corepack 10.33.2 executable; it did not
install dependencies or modify the repository.

## iOS regressions

No iOS source, project setting, signing, entitlement, asset or public model was
changed.

- Debug focused onboarding/auth/session/config: PASS — 172 logical tests, 213
  executions, 0 failed, 0 skipped.
- Release focused onboarding/auth/session/config: PASS — 128 logical tests, 169
  executions, 0 failed, 0 skipped.

The initial broad Release test invocation compiled every test source and failed
before execution because unrelated test helpers are deliberately DEBUG-only.
The verified Release command used an ephemeral
`EXCLUDED_SOURCE_FILE_NAMES` list containing only non-selected suites; it made
no project-file change and then passed the exact selected Release-compatible
onboarding/auth/config suites. The app Release target compiled as part of this
gate. The iPhone 17 Pro simulator was returned to `Shutdown`.

## Reviews

### Review A — database and security

- Critical: 0.
- Important: 0.
- Verified state monotonicity, database-enforced inactive creation, immutable
  content/composition, no DELETE, pinned definer functions, trusted-backend
  assertion, least-privilege grants, RLS preservation, document dependency,
  advisory serialization, atomic replacement and rollback.

### Review B — product and integration

- Critical: 0.
- Important: 0.
- Verified unchanged GET/POST JSON contract, published-only selection,
  completion fail-closed behavior, no predecessor fallback, full synthetic
  closeout, preserved historical acceptance, BFF compatibility and iOS release
  boundary.

## Limits and operational state

- Lifecycle local: `VERIFIED`.
- Staging lifecycle: `NOT APPLIED`.
- Synthetic staging E2E: `NOT EXECUTED`.
- Legal activation: `BLOCKED`.
- Supabase staging/production: not accessed or changed.
- Vercel: not accessed or changed.
- OpenRouter: not accessed.
- CI-3: preserved.
- Remote resources created or changed: none.

The next gate requires separate authorization to revalidate staging, apply only
the authorized onboarding migrations, prove the remote lifecycle before any
provider key is created, and only then execute a bounded synthetic E2E.

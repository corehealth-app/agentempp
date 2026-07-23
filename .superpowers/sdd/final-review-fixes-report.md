# BodyFlow Final Review Fixes Report

## Status

`DONE_WITH_TASK_9_RUNTIME_LIMITATION`

Both Important final-review findings are fixed as one snapshot-owned temporal
model. No live or local mutable database, staging, production, deployment,
provider send, cron, Inngest invocation/sync, Xcode, or external integration was
accessed.

## Files

- `supabase/migrations/20260723131321_bodyflow_routine_occurrence_delivery.sql`
- `supabase/tests/bodyflow_routine_items.sql`
- `supabase/tests/bodyflow_push_routine.sql`
- `packages/core/src/routine.ts`
- `packages/core/src/routine.test.ts`
- `apps/admin/src/lib/mobile-api/routine-adherence-service.ts`
- `apps/admin/src/lib/mobile-api/routine-adherence-service.test.ts`
- `docs/mobile/api-v1.md`
- `.superpowers/sdd/final-review-fixes-report.md`

The earlier API migration
`supabase/migrations/20260722191125_bodyflow_routine_items_api.sql` remains
unchanged so it does not reference objects created by a later migration.

## Fixes

### Immutable occurrence targeting

- Added one shared exact snapshot resolver and one shared snapshot row lock.
- The resolver owns user, item, type, rule, occurrence key, original UTC instant,
  lifecycle interval, snapshot timezone, weekday, local time, and DST round-trip
  validation.
- The row is revalidated after `FOR UPDATE`, including its lifecycle bound, so a
  concurrent archive, deactivation, schedule edit, or timezone mutation cannot
  create a stale eligibility decision.
- Deliberately replaced `record_routine_occurrence_action_atomic` in the later
  occurrence-delivery migration, after the immutable snapshot relation exists.
  The final implementation no longer reads current user timezone, item active
  state, or current reminder-rule state to identify a historical occurrence.
- SQL rejects a scheduled target after effective `occurred_at`, pre-activation
  targets, expired correction targets, and actions outside the seven-day/five-
  minute bounds. Core rejects schedule-after-action bodies, and the BFF rejects
  targets after `min(occurred_at, server now)` with the existing opaque 404.
- Idempotency lookup remains before temporal revalidation so an exact committed
  replay returns the original result; conflicting payloads remain `23505`/409.

### Delayed finalizer convergence

- Action, reminder claim, and finalizer now lock snapshot first and the exact
  occurrence second.
- Added one shared singleton system-missed writer using the existing partial
  unique occurrence index and exact identity verification on conflict.
- A late unresolved action may only be `taken`. It atomically creates or reuses
  the system `missed`, then appends a patient correction linked through
  `supersedes_log_id`.
- Correction `created_at` is explicitly greater than the missed row, including
  when both rows are created in one transaction, satisfying the append-only
  correction trigger deterministically.
- Archive, rule deactivation, and timezone mutation after an eligible historical
  occurrence do not invalidate its correction. Future occurrences remain
  ineligible because they do not belong to the closed historical snapshot.
- Finalizer-first and action-first retries converge to one missed row and one
  linked correction without coupling the 08:00 and 20:00 occurrences.

## TDD Evidence

Application RED was observed before implementation:

- `pnpm --filter @mpp/core exec vitest run src/routine.test.ts` - RED: the new
  schedule-after-action contract case was the single expected failure.
- `pnpm --filter @mpp/admin exec vitest run src/lib/mobile-api/routine-adherence-service.test.ts`
  - RED: the future target reached the repository instead of returning opaque
  404; the new case was the single expected failure.

Focused GREEN after implementation:

- Core routine contract: 1 file, 15 tests passed.
- Admin routine adherence service: 1 file, 21 tests passed.

Executable SQL regression definitions were written before the SQL fix for:

- timezone mutation followed by ordinary action and historical correction;
- SQL pre-activation and future-target rejection;
- action-first missed plus linked correction and finalizer retry;
- finalizer-first missed plus correction and action replay;
- archive/deactivation before delayed correction;
- late non-`taken` rejection;
- idempotency replay and conflict;
- cross-user opacity; and
- independent 08:00 and 20:00 occurrences.

Per the explicit Task 9 boundary, these SQL definitions were not executed
against a database in this fix wave. Their pre-fix RED status is established by
the reviewed original function's current-timezone/current-rule lookup and lack
of target bounds, not claimed as a Postgres runtime result.

## Verification

All final commands below exited zero:

| Command | Result |
| --- | --- |
| `pnpm --filter @mpp/core test` | PASS - 16 files, 205 tests |
| `pnpm --filter @mpp/admin test` | PASS - 49 files, 547 tests |
| `pnpm --filter @mpp/inngest-functions test` | PASS - 35 files, 167 tests |
| `pnpm --filter @mpp/core --filter @mpp/admin --filter @mpp/inngest-functions typecheck` | PASS - all three workspaces |
| `pnpm exec biome check packages/core/src/routine.ts packages/core/src/routine.test.ts apps/admin/src/lib/mobile-api/routine-adherence-service.ts apps/admin/src/lib/mobile-api/routine-adherence-service.test.ts` | PASS - 4 files, no fixes |
| `uvx --from pglast pgpp` on the earlier API migration, later occurrence migration, and both changed SQL fixtures | PASS - 4 outer SQL files |
| Embedded `pglast.parser.parse_plpgsql_json` validator | PASS - 15 migration functions and 11 SQL test blocks |
| Static migration-order/immutable-source/temporal-bound/shared-lock/ACL validator | PASS |
| Added production-line privacy scan | PASS - no WhatsApp, PII, legal body, raw payload, or outbox/provider field match |
| `git diff --check` | PASS - no whitespace errors |

No provider-send behavior or event/outbox payload was added. Synthetic emails,
item text, and dose text occur only in transactional SQL test fixtures and do
not enter telemetry or delivery metadata.

## Migration Order And ACL Reasoning

- From-scratch order remains safe: the existing action RPC is first created by
  `20260722191125`; `20260723131321` creates snapshot persistence and helpers,
  then intentionally `CREATE OR REPLACE`s the same final signature.
- The earlier migration contains no reference to the later snapshot relation.
- New helpers use fixed `search_path`, are `SECURITY INVOKER`, and are revoked
  from `PUBLIC`, `anon`, `authenticated`, and `service_role`.
- The public action RPC retains a fixed path and trusted-backend assertion; its
  final privileges are explicitly revoked from all roles and granted only to
  `service_role`.
- Private snapshot tables retain RLS and no client grants. Added metadata is
  limited to technical IDs, timestamps, weekdays, local time, and timezone.

## Self Review

- Branch and base were confirmed as
  `codex/bodyflow-routine-medications-v1` at clean starting HEAD `5f054f9`.
- Scope is limited to the two Important findings, their executable regressions,
  deterministic BFF rejection, and the changed public API semantics.
- Cross-user failures stay opaque and idempotent replay/conflict behavior is
  preserved.
- The snapshot and occurrence lock order is identical in action and finalizer,
  removing the action/finalizer lost-missed race without a second identity
  implementation in the BFF or worker.
- No WhatsApp dependency/copy/event, clinical claim, coercion, gamification,
  patient PII, raw payload, or provider send was introduced.
- The known Minor medication 428 envelope assertion and generic PATCH reminder
  lookup cleanup were not naturally part of this fix and remain for the final
  reviewer.

## Task 9 Limitations

- No migration was applied and no SQL fixture ran in a Postgres runtime.
- Actual multi-session concurrency, database constraints/triggers, RLS, grants,
  DB lint/advisors, and a from-scratch migration apply remain to be proven in the
  controlled Task 9 database gate.
- Static outer and embedded PL/pgSQL parsing proves syntax coverage, not runtime
  catalog or transaction behavior.
- No claim is made that staging or production contains this fix wave.

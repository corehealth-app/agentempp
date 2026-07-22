# Task 4 Report: Authenticated Routine Item CRUD/List/History BFF

## Status

DONE. Implemented the authenticated mobile supplement and medication collection, item, and history BFF on `codex/bodyflow-routine-medications-v1` from base `826012453fec22fe5fc4752305c7ded80bc5c13c`.

## Plan Executed

1. Added focused service RED tests, then implemented DTO mapping and service error handling.
2. Added focused Supabase adapter RED tests, then bound the Task 4 CRUD/list/history RPCs.
3. Added RED tests for all supplement and medication routes, then implemented one shared handler layer and literal-type route closures.
4. Ran focused tests, typecheck, Biome, scope/parity scans, and `git diff --check`.

## Owned Files

Service and adapter:

- `apps/admin/src/lib/mobile-api/routine-item-service.ts`
- `apps/admin/src/lib/mobile-api/routine-item-service.test.ts`
- `apps/admin/src/lib/mobile-api/supabase-routine-items.ts`
- `apps/admin/src/lib/mobile-api/supabase-routine-items.test.ts`
- `apps/admin/src/lib/mobile-api/routine-route-handlers.ts`

Supplement routes:

- `apps/admin/src/app/api/mobile/v1/supplements/route.ts`
- `apps/admin/src/app/api/mobile/v1/supplements/route.test.ts`
- `apps/admin/src/app/api/mobile/v1/supplements/[id]/route.ts`
- `apps/admin/src/app/api/mobile/v1/supplements/[id]/route.test.ts`
- `apps/admin/src/app/api/mobile/v1/supplements/[id]/history/route.ts`
- `apps/admin/src/app/api/mobile/v1/supplements/[id]/history/route.test.ts`

Medication routes:

- `apps/admin/src/app/api/mobile/v1/medications/route.ts`
- `apps/admin/src/app/api/mobile/v1/medications/route.test.ts`
- `apps/admin/src/app/api/mobile/v1/medications/[id]/route.ts`
- `apps/admin/src/app/api/mobile/v1/medications/[id]/route.test.ts`
- `apps/admin/src/app/api/mobile/v1/medications/[id]/history/route.ts`
- `apps/admin/src/app/api/mobile/v1/medications/[id]/history/route.test.ts`

No migrations, generated database types, existing taken routes, or unrelated product files were edited.

## TDD Evidence

Service RED:

```text
pnpm --filter @mpp/admin test -- routine-item-service.test.ts
FAIL: Failed to load ./routine-item-service (module did not exist)
Existing result: 34 files passed, 403 tests passed
```

Service GREEN:

```text
pnpm --filter @mpp/admin test -- routine-item-service.test.ts
PASS: 35 files passed, 421 tests passed
```

Adapter RED:

```text
pnpm --filter @mpp/admin test -- supabase-routine-items.test.ts
FAIL: Failed to load ./supabase-routine-items (module did not exist)
Existing result: 35 files passed, 421 tests passed
```

Adapter GREEN:

```text
pnpm --filter @mpp/admin test -- supabase-routine-items.test.ts
PASS: 36 files passed, 452 tests passed
```

Routes RED:

```text
pnpm --filter @mpp/admin test -- supplements/route.test.ts
FAIL: all six new route suites could not load routine-route-handlers
Existing result: 36 files passed, 452 tests passed
```

Routes GREEN:

```text
pnpm --filter @mpp/admin test -- supplements/route.test.ts medications/route.test.ts
PASS: 42 files passed, 470 tests passed
```

Final focused verification:

```text
pnpm --filter @mpp/admin test -- routine-item-service.test.ts supabase-routine-items.test.ts supplements/route.test.ts
PASS: 42 files passed, 470 tests passed

pnpm --filter @mpp/admin typecheck
PASS

pnpm exec biome check <17 owned TypeScript files>
PASS: no fixes required after formatting
```

## Design Decisions

- One service, repository adapter, and handler implementation is parameterized by `RoutineItemType`; public route modules close over only `'supplement'` or `'medication'`.
- Task 4 binds the five Task 3 RPCs in this slice: `list_mobile_routine_items`, `create_mobile_routine_item`, `update_mobile_routine_item`, `archive_mobile_routine_item`, and `list_mobile_routine_history`. Task 5 owns the remaining occurrence/legal RPCs.
- List time is server-generated and passed as `p_now`; clients cannot send timezone or local date.
- Public DTOs are snake_case, preserve item/schedule ordering and occurrence state, add `frequency_summary.times_per_week`, and remove internal `occurrence_key` from list and history output.
- History cursors are decoded/encoded only with the Task 1 opaque cursor utilities.
- Create/update/archive return only the parsed canonical mutation RPC result. There is no post-mutation table read.
- Task 3 update/archive RPCs have no expected-type argument. Before those calls, the service performs an exact-type, authenticated, active-list preflight. This provides wrong-type/inactive non-disclosure without changing the migration or issuing an unconstrained read.
- Generic and database idempotency hashes include the literal type. Item mutations also include the route item ID; DELETE accepts only an empty strict JSON body and hashes the typed route identity.
- All handlers use the authenticated mobile wrappers, strict Task 1 schemas, JSON media validation, standard idempotency execution, and the standard mobile envelope.

## Error Mapping

- `404 routine_item_not_found`: item missing, inactive, wrong type, occurrence missing, or occurrence ambiguous.
- `409 routine_item_version_conflict`: stale item version.
- `409 routine_schedule_conflict`: conflicting schedule.
- `409 routine_transition_invalid`: invalid occurrence transition.
- `409 idempotency_key_conflict`: routine mutation idempotency conflict.
- `422 routine_schedule_invalid`: invalid schedule/payload aliases.
- `422 routine_snooze_invalid`: invalid snooze.
- `428 medication_disclaimer_required`: missing or stale medication disclaimer acceptance.
- Invalid opaque cursors become standard `422 validation_failed`; all unexpected storage/shape failures become opaque `500 internal_error`.

Known Task 3 SQL messages are normalized to the approved stable codes. Unexpected adapter logs contain only a validated `request_id`, a closed-set operation label, and a safe database code. SQL messages, user/item IDs, names, doses, request bodies, and operation internals are not logged or returned.

## Self-Review

- Confirmed supplement/medication route parity; diffs differ only by route literal and directory name.
- Confirmed auth wrapper executes before dependency/repository access.
- Confirmed strict unknown/duplicate query rejection, UUID validation, JSON media enforcement, required idempotency key, replay behavior, and 201/200 statuses.
- Confirmed stable schedule IDs/order, archived filtering, occurrence metadata, frequency summary, and opaque history pagination.
- Confirmed no internal occurrence keys, SQL messages, user IDs, technical legal rows, clinical claims, or WhatsApp dependency/copy/fixtures cross the DTO or route boundary.
- Confirmed only Task 4 files plus this required report changed.

## Concerns

None blocking. The typed update/archive preflight is required by the current Task 3 RPC signatures and is covered by wrong-type 404 tests; item type is immutable in the database domain, so the preflight remains valid through the mutation call.

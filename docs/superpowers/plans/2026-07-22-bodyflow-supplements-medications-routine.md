# BodyFlow Supplements, Medications And Routine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** deliver private, idempotent supplement and medication CRUD, exact-schedule adherence, same-day snooze, history, medication disclaimer acceptance, and app-first routine contracts without introducing clinical advice.

**Architecture:** extend the existing normalized `routine_items`, `reminder_rules`, and append-only `routine_adherence_logs` domain. PostgreSQL owns ownership, occurrence identity, state transitions, schedule replacement and finalization; `@mpp/core` owns portable request/state contracts; the Next.js BFF owns authenticated DTOs and idempotent commands; Inngest only discovers and claims technical occurrence IDs. No client or LLM computes routine state.

**Tech Stack:** TypeScript 5, Zod 3, Vitest 2, Next.js 15 App Router, Supabase/PostgreSQL 15+, Inngest 3, pnpm 10, Turbo 2.

## Global Constraints

- Work only in `/root/.codex/worktrees/agentempp-bodyflow-content-cms` on `codex/bodyflow-routine-medications-v1`.
- Preserve the stacked CMS base `eddf055b92ebac6f91c1541e72bda1e9ac1033cd` and approved specification commit `d20680d`.
- Production Supabase project `xuxehkhdvjivitduarvb` remains untouched.
- Database validation and application are allowed only on staging ref `xitugspwfxkcluxvrdeg` after revalidating the local link.
- Keep all 34 staging cron jobs inactive; do not sync or invoke new Inngest cron functions in a live environment.
- Do not deploy Vercel, configure APNs or another provider, start Xcode, execute visual prompts, copy production data, or read PII.
- Do not introduce any WhatsApp dependency, route, event, copy, compatibility fallback, or test fixture into the new BodyFlow flow.
- The app only organizes reminders and records; it never prescribes, recommends, interprets, increases, reduces or stops a dose.
- Supplement copy must not make medical, curative or guaranteed performance claims.
- Medication reminders remain neutral and are excluded from mascot rewards, streak pressure and persona-based persuasion.
- One item can have multiple schedules; every adherence action addresses exactly one `reminder_rule_id` plus original `scheduled_for`.
- `skipped` is patient-explicit; unresolved occurrences derive and later persist as `missed` after the local day ends.
- Snooze is limited to 15, 30 or 60 minutes, or a custom instant on the same patient-local day.
- Archive instead of delete; preserve item, rules, acceptances, occurrence actions and notification history.
- Use RED, GREEN, refactor for every production behavior and record the expected RED failure.
- Create migrations with `supabase migration new`; do not manually invent migration timestamps.
- Every new public table has RLS, explicit grants, and zero direct `PUBLIC`, `anon`, or `authenticated` writes.
- Trusted backend RPCs use a fixed search path, call `private.assert_trusted_backend()`, revoke default execution and grant only `service_role`.
- Never log item names, dose text, legal copy, raw request bodies, emails, tokens or patient-identifying data.
- New database columns are additive and nullable where required for legacy compatibility; do not backfill unknown dose, origin, schedule or occurrence identity.

---

### Task 1: Portable Routine Contracts And Occurrence State

**Files:**
- Create: `packages/core/src/routine.ts`
- Create: `packages/core/src/routine.test.ts`
- Modify: `packages/core/src/index.ts`

**Produces:**

```ts
export type RoutineItemType = 'supplement' | 'medication'
export type RoutineOrigin = 'user' | 'professional' | 'protocol' | 'other'
export type RoutineStoredStatus = 'taken' | 'snoozed' | 'skipped' | 'missed'
export type RoutinePublicStatus = 'pending' | RoutineStoredStatus
export type RoutinePreviewMode = 'private' | 'name' | 'name_and_dose'

export interface RoutineScheduleInput {
  local_time: string
  weekdays: number[]
}

export interface RoutineItemCreateInput {
  name: string
  dose_text: string
  origin: RoutineOrigin
  reminders_enabled: boolean
  schedules: RoutineScheduleInput[]
}

export interface RoutineItemPatchInput {
  expected_version: number
  name?: string
  dose_text?: string
  origin?: RoutineOrigin
  reminders_enabled?: boolean
  schedules?: RoutineScheduleInput[]
}

export interface RoutineActionInput {
  status: 'taken' | 'snoozed' | 'skipped'
  reminder_rule_id: string
  scheduled_for: string
  occurred_at: string
  snoozed_until?: string
}

export interface RoutineHistoryCursor {
  occurredAt: string
  logId: string
}

export interface RoutineItemListQuery {
  include_archived: boolean
}

export interface MedicationDisclaimerAcceptanceInput {
  accepted: true
  version: string
  body_hash: string
}

export const routinePreviewModeSchema: z.ZodType<RoutinePreviewMode>
export const routineItemCreateInputSchema: z.ZodType<RoutineItemCreateInput>
export const routineItemPatchInputSchema: z.ZodType<RoutineItemPatchInput>
export const routineActionInputSchema: z.ZodType<RoutineActionInput>
export const routineItemListQuerySchema: z.ZodType<RoutineItemListQuery>
export const medicationDisclaimerAcceptanceInputSchema: z.ZodType<MedicationDisclaimerAcceptanceInput>
export const routineHistoryQuerySchema: z.ZodType<{ limit: number; cursor?: string }>
export function encodeRoutineHistoryCursor(value: RoutineHistoryCursor): string
export function decodeRoutineHistoryCursor(value: string): RoutineHistoryCursor
export function deriveRoutineOccurrenceStatus(input: {
  actions: Array<{ status: RoutineStoredStatus; occurredAt: string; createdAt: string; id: string }>
  now: string
  localDayEndExclusive: string
}): RoutinePublicStatus
```

- [ ] **Step 1: Write RED enum and strict-input tests.**

Add cases proving exact item types/origins/statuses/preview modes, trimmed `name` and `dose_text`, name length 1-200, dose length 1-120, `HH:MM` time, unique weekdays 0-6, one to 16 schedules, canonical weekday sorting, positive `expected_version`, `include_archived=false` default/coercion, exact disclaimer acceptance, lowercase 64-character SHA-256 hash, controlled version length 1-64, unknown-key rejection, and snooze-field coupling.

```ts
expect(
  routineItemCreateInputSchema.parse({
    name: ' Creatina ',
    dose_text: ' 3 g ',
    origin: 'professional',
    reminders_enabled: true,
    schedules: [{ local_time: '08:00', weekdays: [6, 1, 1] }],
  }),
).toEqual({
  name: 'Creatina',
  dose_text: '3 g',
  origin: 'professional',
  reminders_enabled: true,
  schedules: [{ local_time: '08:00', weekdays: [1, 6] }],
})
```

- [ ] **Step 2: Run `pnpm --filter @mpp/core test -- routine.test.ts`.**

Expected: FAIL because `packages/core/src/routine.ts` does not exist.

- [ ] **Step 3: Implement the schemas with shared schedule normalization.**

Use strict Zod objects and reject duplicate logical schedules after canonicalizing weekdays:

```ts
const scheduleKey = (schedule: RoutineScheduleInput) =>
  `${schedule.local_time}:${schedule.weekdays.join(',')}`

const uniqueSchedules = (schedules: RoutineScheduleInput[], context: z.RefinementCtx) => {
  const keys = schedules.map(scheduleKey)
  if (new Set(keys).size !== keys.length) {
    context.addIssue({ code: 'custom', path: ['schedules'], message: 'Schedules must be unique' })
  }
}
```

- [ ] **Step 4: Write RED action-state tests.**

Cover no action before day end (`pending`), no action after day end (`missed`), latest snooze, snooze then taken, explicit skipped, deterministic tie-breaking by `occurredAt`, `createdAt`, then `id`, and automatic missed followed by corrective taken.

- [ ] **Step 5: Implement deterministic state reduction and opaque history cursor.**

Cursor payload is canonical base64url JSON, capped at 512 characters, and validated as ISO timestamp plus UUID. State selection sorts a defensive copy and never mutates caller input.

- [ ] **Step 6: Export the module and run focused verification.**

Run:

```bash
pnpm --filter @mpp/core test -- routine.test.ts
pnpm --filter @mpp/core typecheck
git diff --check
```

Expected: PASS.

- [ ] **Step 7: Commit `feat(core): add routine occurrence contracts`.**

### Task 2: Additive Routine, Legal And Privacy Persistence

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_routine_items_domain`
- Create with Supabase CLI: migration basename `bodyflow_routine_items_privileges`
- Create: `supabase/tests/bodyflow_routine_items.sql`

**Consumes:** exact enums and limits from Task 1.

**Produces:**

```sql
ALTER TABLE public.routine_items
  ADD COLUMN dose_text text,
  ADD COLUMN origin text,
  ADD COLUMN reminders_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN archived_at timestamptz,
  ADD COLUMN version integer NOT NULL DEFAULT 1;

ALTER TABLE public.reminder_rules
  ADD COLUMN deactivated_at timestamptz;

ALTER TABLE public.routine_adherence_logs
  ADD COLUMN reminder_rule_id uuid,
  ADD COLUMN occurrence_key text,
  ADD COLUMN source text,
  ADD COLUMN supersedes_log_id uuid;

ALTER TABLE public.reminder_events
  ADD COLUMN routine_occurrence_key text,
  ADD COLUMN routine_action_log_id uuid;

ALTER TABLE public.notification_deliveries
  ADD COLUMN routine_preview_mode text;

ALTER TABLE public.notification_preferences
  ADD COLUMN routine_preview_mode text NOT NULL DEFAULT 'private';

CREATE TABLE public.legal_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_key text NOT NULL,
  version text NOT NULL,
  locale text NOT NULL,
  body text NOT NULL,
  body_hash text GENERATED ALWAYS AS (
    encode(extensions.digest(body, 'sha256'), 'hex')
  ) STORED,
  required_from timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (document_key, locale, version),
  UNIQUE (document_key, locale, required_from),
  UNIQUE (id, document_key, version, locale, body_hash)
);

CREATE TABLE public.user_legal_acceptances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  legal_document_id uuid NOT NULL,
  document_key text NOT NULL,
  version text NOT NULL,
  locale text NOT NULL,
  body_hash text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (user_id, document_key, version),
  FOREIGN KEY (legal_document_id, document_key, version, locale, body_hash)
    REFERENCES public.legal_documents(id, document_key, version, locale, body_hash)
    ON DELETE RESTRICT
);

CREATE TABLE private.routine_mutation_receipts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  idempotency_key text NOT NULL,
  operation text NOT NULL,
  request_hash text NOT NULL,
  result_payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, idempotency_key)
);
```

- [ ] **Step 1: Write the transactional RED schema/security test.**

Require every additive column, legal table, database-assigned occurrence key, owner/type foreign keys, indexes, RLS and grants. Prove `anon` cannot read and `authenticated` cannot write any routine/legal relation. Prove the private receipt relation is absent from `public` and inaccessible to client roles. Persistent execution is deferred to the staging gate in Task 9; the recorded RED expectation is a missing `dose_text` column before any new migration is applied.

- [ ] **Step 2: Add RED constraint cases.**

Cover invalid origin/status/source/preview mode, blank or oversized name/dose, nonpositive version, archive/active mismatch, active/deactivated mismatch, cross-user and cross-type rule/log references, malformed database-assigned occurrence keys, snooze without future same-day validation deferred to RPC, and superseding another user's log.

- [ ] **Step 3: Add RED legal-document cases.**

Require immutable document key/version/locale/body hash, deterministic current-version selection by the greatest `required_from <= now()` per document/locale, exact locales `pt-BR` and `en-US`, unique patient/document/version acceptance, and acceptance referencing the exact document hash shown to the patient. A newer row supersedes an older requirement without mutating or deleting either the older document or its acceptances.

- [ ] **Step 4: Generate the two migrations using the CLI.**

Run:

```bash
supabase migration new bodyflow_routine_items_domain
supabase migration new bodyflow_routine_items_privileges
```

The privileges migration is later than the domain migration and owns all REVOKE/GRANT statements.

- [ ] **Step 5: Implement additive columns, checks, FKs and indexes.**

Required invariants include:

```sql
CHECK (origin IS NULL OR origin IN ('user', 'professional', 'protocol', 'other'))
CHECK (dose_text IS NULL OR char_length(btrim(dose_text)) BETWEEN 1 AND 120)
CHECK (version > 0)
CHECK (archived_at IS NULL OR (NOT active AND NOT reminders_enabled))
CHECK (deactivated_at IS NULL OR NOT active)
CHECK (source IS NULL OR source IN ('patient', 'system', 'offline_sync'))
CHECK (occurrence_key IS NULL OR occurrence_key ~ '^[0-9a-f]{64}$')
CHECK (occurrence_key IS NULL OR (reminder_rule_id IS NOT NULL AND scheduled_for IS NOT NULL AND source IS NOT NULL))
CHECK (supersedes_log_id IS NULL OR (status = 'taken' AND source IN ('patient', 'offline_sync')))
CHECK (source IS NULL OR status <> 'missed' OR source = 'system')
-- notification_preferences:
CHECK (routine_preview_mode IN ('private', 'name', 'name_and_dose'))
-- notification_deliveries:
CHECK (routine_preview_mode IS NULL OR routine_preview_mode IN ('private', 'name', 'name_and_dose'))
```

The adherence RPC assigns `occurrence_key` from the validated `reminder_rule_id` and original `scheduled_for`; no table grant, public RPC argument or trigger accepts a caller-provided key. Add an owner/type-safe FK from each occurrence log to its reminder rule, a descending partial index on `(user_id, occurrence_key, occurred_at DESC, created_at DESC, id DESC)` for exact-state reads, a partial unique index for one system `missed` action per occurrence, an owner-safe self-reference for `supersedes_log_id`, and a partial unique index on `reminder_events(routine_action_log_id)` so each snooze action can queue at most one follow-up event. `notification_deliveries.routine_preview_mode` is null for non-routine deliveries and one of the three controlled modes for routine deliveries; it stores no item name or dose.

Legal and receipt constraints are exact: document keys match `^[a-z][a-z0-9_]{0,99}$`, versions match `^[A-Za-z0-9._-]{1,64}$`, locale is `pt-BR` or `en-US`, body length is 1-4000 after trim, hashes are lowercase SHA-256, idempotency keys use the existing 8-128 character mobile format, receipt operations are `routine_item_create`, `routine_item_update`, `routine_item_archive` or `legal_acceptance`, request hashes are lowercase SHA-256 and `result_payload` must be a JSON object. The private receipt writer rejects result keys outside `routine_item_id`, `version`, `archived_at`, `document_key`, `accepted_version` and `accepted_at`.

Use `NOT VALID` only where unknown legacy rows could otherwise block the additive migration; new rows are still enforced. The one-way archive/deactivation checks accept legacy inactive rows whose historical timestamp is unknown while preventing active archived/deactivated rows. Do not rewrite or infer legacy values.

- [ ] **Step 6: Seed the versioned legal copy.**

Use document key `medication_reminder_disclaimer`, version `2026-07-22.1`, and SHA-256 hashes computed by PostgreSQL. Seed exactly:

```text
pt-BR: O BodyFlow apenas organiza lembretes e registros. Ele não prescreve, recomenda nem altera medicamentos ou doses. Siga a orientação do profissional de saúde responsável.
en-US: BodyFlow only organizes reminders and records. It does not prescribe, recommend or change medications or doses. Follow the guidance of the responsible healthcare professional.
```

Do not place the copy in telemetry or product events.

- [ ] **Step 7: Add RLS, explicit grants and immutable guards.**

Patients may select only their own routine items/rules/logs/acceptances through existing auth ownership. Legal-document text is read through the BFF. No direct client writes are granted. Add triggers that prevent editing/deleting legal acceptances and previous adherence actions.

- [ ] **Step 8: Run static verification.**

Run these exact static checks; persistent staging application remains reserved for Task 9:

```bash
git diff --check
rg -n "GRANT .* TO (PUBLIC|anon|authenticated)" supabase/migrations/*_bodyflow_routine_items_*.sql
rg -n "SECURITY DEFINER|SET search_path|REVOKE ALL ON FUNCTION|GRANT EXECUTE ON FUNCTION" supabase/migrations/*_bodyflow_routine_items_*.sql
```

The first `rg` may show read-only grants documented by the plan but must show no direct routine/legal DML grants. Every trusted function shown by the second command must have a fixed search path, default execution revoked and only `service_role` execution granted.

- [ ] **Step 9: Commit `feat(database): extend private routine domain`.**

### Task 3: Atomic CRUD, Legal, History And Adherence RPCs

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_routine_items_api`
- Create with Supabase CLI: migration basename `bodyflow_routine_items_api_privileges`
- Modify: `supabase/tests/bodyflow_routine_items.sql`

**Consumes:** Task 2 relations and Task 1 contract limits.

**Produces:**

```sql
public.create_mobile_routine_item(
  p_user_id uuid,
  p_item_type text,
  p_payload jsonb,
  p_idempotency_key text,
  p_request_hash text
) returns jsonb

public.update_mobile_routine_item(
  p_user_id uuid,
  p_item_id uuid,
  p_expected_version integer,
  p_patch jsonb,
  p_idempotency_key text,
  p_request_hash text
) returns jsonb

public.archive_mobile_routine_item(
  p_user_id uuid,
  p_item_id uuid,
  p_idempotency_key text,
  p_request_hash text
) returns jsonb

public.list_mobile_routine_items(
  p_user_id uuid,
  p_item_type text,
  p_include_archived boolean default false,
  p_now timestamptz default clock_timestamp()
) returns jsonb

public.list_mobile_routine_history(
  p_user_id uuid,
  p_item_id uuid,
  p_item_type text,
  p_limit integer,
  p_before_occurred_at timestamptz default null,
  p_before_log_id uuid default null
) returns jsonb

public.record_routine_occurrence_action_atomic(
  p_user_id uuid,
  p_item_id uuid,
  p_expected_item_type text,
  p_reminder_rule_id uuid,
  p_scheduled_for timestamptz,
  p_status text,
  p_occurred_at timestamptz,
  p_snoozed_until timestamptz,
  p_idempotency_key text
) returns jsonb

public.get_mobile_legal_document(
  p_user_id uuid,
  p_document_key text
) returns jsonb

public.accept_mobile_legal_document(
  p_user_id uuid,
  p_document_key text,
  p_version text,
  p_body_hash text,
  p_idempotency_key text
) returns jsonb
```

- [ ] **Step 1: Add RED transaction and idempotency cases for create/update/archive.**

Prove item, schedules and a technical `routine.item.created` domain event commit together; unchanged schedules retain IDs, changed schedules are deactivated and replaced, stale `expected_version` changes nothing, archive deactivates all rules, same key/hash replays the technical result, and same key/different hash raises a unique conflict. Receipt rows and event properties store IDs, item type, version and result only, never name or dose.

- [ ] **Step 2: Add RED exact-occurrence action cases.**

Create one item with 08:00 and 20:00 rules. Prove 08:00 taken leaves 20:00 pending, snooze keeps the original occurrence identity, snooze cannot cross the local day, client cannot submit `missed`, terminal actions reject ordinary rewrites, and a system `missed` can be corrected once to taken within seven days while preserving both rows.

- [ ] **Step 3: Add RED read/history/legal cases.**

Prove exact item type/ownership, archived exclusion by default, stable schedule order, database-derived patient-local date/current-day occurrence state, cursor tuple ordering `(occurred_at DESC, id DESC)`, no cross-user existence disclosure, locale selected from the stored patient profile, acceptance of the exact current body hash, and medication creation rejected before current acceptance. Neither list RPC nor its BFF accepts a client-supplied timezone or local date.

- [ ] **Step 4: Generate API and privilege migrations.**

Run:

```bash
supabase migration new bodyflow_routine_items_api
supabase migration new bodyflow_routine_items_api_privileges
```

- [ ] **Step 5: Implement shared private validation helpers.**

Helpers validate canonical schedules, compare local dates using the stored timezone, lock one item/occurrence, and read/write technical mutation receipts. A single private helper derives the 64-character occurrence hash from the canonical rule UUID plus the original instant represented as UTC epoch microseconds; adherence, reminder claim and finalizer all call that helper. They are private-schema functions with no client execution.

- [ ] **Step 6: Implement atomic CRUD and legal RPCs.**

Medication create calls the legal-acceptance assertion inside the same transaction. Schedule replacement uses `active=false, deactivated_at=clock_timestamp()` and inserts new rows; it never edits the historical `local_time` or `weekdays` of replaced rules.

- [ ] **Step 7: Implement exact adherence and read RPCs.**

The adherence RPC recomputes occurrence identity from the canonical rule and original instant, validates transition against the latest action ordered by `occurred_at DESC, created_at DESC, id DESC`, and inserts one append-only row. The supplied instant must round-trip to the rule's canonical local date, weekday and `HH:MM` in the stored patient timezone, including DST transition dates. Read RPCs return technical database shapes only; no signed token, email or raw legal audit row is returned.

- [ ] **Step 8: Revoke and grant functions explicitly.**

Every public mutation/read RPC calls `private.assert_trusted_backend()`, has a fixed search path, is revoked from `PUBLIC`, `anon`, `authenticated`, and is granted only to `service_role`.

- [ ] **Step 9: Run static checks and commit.**

Run `git diff --check`; persistent SQL execution remains Task 9. Commit `feat(database): add atomic routine operations`.

### Task 4: Authenticated Supplement And Medication CRUD BFF

**Files:**
- Create: `apps/admin/src/lib/mobile-api/routine-item-service.ts`
- Create: `apps/admin/src/lib/mobile-api/routine-item-service.test.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-routine-items.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-routine-items.test.ts`
- Create: `apps/admin/src/lib/mobile-api/routine-route-handlers.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/[id]/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/[id]/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/[id]/history/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/[id]/history/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/[id]/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/[id]/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/[id]/history/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/[id]/history/route.test.ts`

**Consumes:** Task 1 schemas and cursors; Task 3 CRUD/list/history RPCs; existing `createMobileRoute`, `createMobileRouteWithContext` and `executeSupabaseIdempotent`.

**Produces:**

```ts
export interface RoutineItemRepository {
  list(input: ListRoutineItemsCommand): Promise<RoutineItemPageRecord>
  create(input: CreateRoutineItemCommand): Promise<RoutineItemRecord>
  update(input: UpdateRoutineItemCommand): Promise<RoutineItemRecord>
  archive(input: ArchiveRoutineItemCommand): Promise<RoutineItemRecord>
  history(input: RoutineHistoryCommand): Promise<RoutineHistoryPageRecord>
}

export function listRoutineItems(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  query: RoutineItemListQuery,
  now?: Date,
): Promise<RoutineItemListDto>
```

- [ ] **Step 1: Write RED service tests.**

Cover canonical DTOs, exact item type forwarding, server `now` forwarding without a client timezone/date, archived filtering, frequency summary, stable schedules/occurrences, opaque history cursor, 404 non-disclosure, 409 version conflict, 409 idempotency conflict, 422 invalid schedule and 428 disclaimer-required mapping. Map every approved stable routine/disclaimer database code without exposing SQL messages or operation names:

```text
routine_item_not_found
routine_item_inactive
routine_item_type_mismatch
routine_item_version_conflict
routine_schedule_invalid
routine_schedule_conflict
routine_occurrence_not_found
routine_occurrence_ambiguous
routine_transition_invalid
routine_snooze_invalid
routine_idempotency_conflict
medication_disclaimer_required
medication_disclaimer_version_stale
```

Validation errors are 422, stale version/idempotency conflicts are 409, missing current legal acceptance is 428 and inaccessible resources are 404.

- [ ] **Step 2: Run `pnpm --filter @mpp/admin test -- routine-item-service.test.ts`.**

Expected: FAIL because the service module does not exist.

- [ ] **Step 3: Implement the service and repository error mapping.**

Use one shared implementation parameterized by the exact `RoutineItemType`; never derive type from request JSON. Return snake_case mobile DTOs and keep database operation names/messages out of responses.

- [ ] **Step 4: Write RED Supabase adapter tests.**

Assert exact RPC names/parameters, request hash forwarding, Zod parsing of every result, null/not-found behavior, malformed payload rejection, cursor encode/decode, and technical-only error logs containing `request_id`, operation and database code.

- [ ] **Step 5: Implement `supabase-routine-items.ts`.**

Bind RPC through the established typed/untyped adapter pattern. On successful create/update/archive, parse and return the canonical RPC result; do not issue a second unconstrained table query.

- [ ] **Step 6: Write RED route tests for both item types.**

Cover auth failure before repository access, strict query/body parsing, UUID validation, required JSON media type, required `Idempotency-Key`, replay, POST 201, PATCH 200, DELETE archive 200, history pagination, wrong-type 404 and no route duplication drift between supplements and medications.

- [ ] **Step 7: Implement shared handlers and thin route modules.**

Each public route closes over a literal item type:

```ts
export const GET = createRoutineCollectionGetRoute('supplement')
export const POST = createRoutineCollectionPostRoute('supplement')
```

Mutation payload hashing includes the route item ID and validated input. DELETE hashes `{ routine_item_id: id }`.

- [ ] **Step 8: Run focused verification.**

```bash
pnpm --filter @mpp/admin test -- routine-item-service.test.ts supabase-routine-items.test.ts supplements/route.test.ts
pnpm --filter @mpp/admin typecheck
git diff --check
```

Expected: PASS.

- [ ] **Step 9: Commit `feat(mobile-api): add routine item CRUD`.**

### Task 5: Medication Disclaimer, Adherence Log And Legacy Safety

**Files:**
- Create: `apps/admin/src/lib/mobile-api/routine-adherence-service.ts`
- Create: `apps/admin/src/lib/mobile-api/routine-adherence-service.test.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-routine-adherence.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-routine-adherence.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/legal/medication-reminder-disclaimer/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/legal/medication-reminder-disclaimer/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/legal/medication-reminder-disclaimer/accept/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/legal/medication-reminder-disclaimer/accept/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/[id]/log/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/supplements/[id]/log/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/[id]/log/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/medications/[id]/log/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/notification-preferences/route.test.ts`
- Modify: `apps/admin/src/app/api/mobile/v1/routine/supplements/[id]/taken/route.ts`
- Modify: `apps/admin/src/app/api/mobile/v1/routine/medications/[id]/taken/route.ts`
- Modify: `apps/admin/src/lib/mobile-api/contracts.ts`
- Modify: `apps/admin/src/lib/mobile-api/contracts.test.ts`
- Modify: `apps/admin/src/lib/mobile-api/routine-service.ts`
- Modify: `apps/admin/src/lib/mobile-api/routine-service.test.ts`
- Modify: `apps/admin/src/lib/mobile-api/supabase-routine.ts`

**Consumes:** Task 1 action schema; Task 3 adherence/legal RPCs; Task 4 route factory patterns.

**Produces:**

```ts
export interface RoutineAdherenceRepository {
  record(input: RecordRoutineActionCommand): Promise<RoutineActionResult>
  resolveLegacyOccurrence(input: LegacyTakenCommand): Promise<
    | { action: 'resolved'; reminderRuleId: string; scheduledFor: string }
    | { action: 'not_found' }
    | { action: 'ambiguous' }
  >
  getMedicationDisclaimer(userId: string): Promise<MedicationDisclaimerRecord>
  acceptMedicationDisclaimer(input: AcceptDisclaimerCommand): Promise<DisclaimerAcceptanceRecord>
}
```

- [ ] **Step 1: Write RED adherence service tests.**

Prove bounded seven-day offline timestamps, exact item type, no client `missed`, same-local-day snooze, 15/30/60 presets and valid custom time, archived-item conflict, transition conflict, retry replay, and response DTO without item name/dose.

- [ ] **Step 2: Write RED disclaimer tests.**

Prove GET returns locale-selected exact key/version/body/hash, POST requires `accepted=true` plus exact version/hash and idempotency, stale hash/version returns 409, and the acceptance response contains key/version/accepted_at only.

- [ ] **Step 3: Write RED legacy wrapper tests.**

With one eligible occurrence, legacy taken records that occurrence. With zero it returns 404. With 08:00 and 20:00 both eligible it returns `409 routine_occurrence_ambiguous`; it never picks nearest or first silently.

- [ ] **Step 4: Implement adherence/legal service and Supabase adapter.**

All logs use technical IDs. The server assigns `source='patient'`; request JSON cannot set source, occurrence key, `missed` or `supersedes_log_id`.

- [ ] **Step 5: Implement legal and log routes.**

GET legal is authenticated and non-idempotent at `/legal/medication-reminder-disclaimer`. POST acceptance is a separate `/legal/medication-reminder-disclaimer/accept` route; it and both log routes require `Idempotency-Key` and use the standard mobile envelope. The medication creation route from Task 4 surfaces 428 from the database without bypass.

- [ ] **Step 6: Convert legacy taken routes into exact-occurrence wrappers.**

Keep their external path and body shape. Resolve an exact occurrence server-side only when unique, then call the same adherence service used by `/:id/log`.

- [ ] **Step 7: Add routine notification preview preference.**

Extend `notificationPreferencesPatchSchema`, DTOs, the notification-preferences route and the Supabase preference adapter with exact modes `private`, `name`, `name_and_dose`; default responses return `private` before persistence. Route tests prove unknown modes/fields are rejected and no preference response exposes an item name or dose.

- [ ] **Step 8: Run focused tests and commit.**

```bash
pnpm --filter @mpp/admin test -- routine-adherence-service.test.ts supabase-routine-adherence.test.ts medication-reminder-disclaimer/route.test.ts medication-reminder-disclaimer/accept/route.test.ts routine-service.test.ts contracts.test.ts notification-preferences/route.test.ts
pnpm --filter @mpp/admin typecheck
git diff --check
```

Expected: PASS. Commit `feat(mobile-api): add routine adherence and legal acceptance`.

### Task 6: Exact-Occurrence Daily State

**Files:**
- Modify: `packages/core/src/daily-state.ts`
- Modify: `packages/core/src/daily-state.test.ts`
- Modify: `packages/agent/src/daily-state-service.ts`
- Modify: `packages/agent/src/daily-state-service.test.ts`
- Modify: `docs/CALCULO-MPP.md`

**Consumes:** Task 1 routine state types; Task 3 `list_mobile_routine_items` read model.

**Produces:**

```ts
export const DAILY_STATE_CALCULATION_VERSION = 'bodyflow.daily-state.v2' as const

export interface DailyStateRoutineOccurrenceInput {
  reminderRuleId: string
  scheduledFor: string
  status: RoutinePublicStatus
  lastActionAt: string | null
  snoozedUntil: string | null
}

export interface DailyStateRoutineItemInput {
  id: string
  itemType: RoutineItemType
  name: string
  doseText: string | null
  origin: RoutineOrigin | null
  remindersEnabled: boolean
  schedules: Array<{ id: string; localTime: string; weekdays: number[] }>
  occurrences: DailyStateRoutineOccurrenceInput[]
  updatedAt: string | null
}
```

- [ ] **Step 1: Write RED core daily-state tests.**

Require two occurrences for one item, independent 08:00 taken and 20:00 pending state, snoozed metadata, missed derivation, deterministic ordering, new metadata, no internal occurrence key, and calculation version v2.

- [ ] **Step 2: Run `pnpm --filter @mpp/core test -- daily-state.test.ts`.**

Expected: FAIL because the v1 item-level shape has no schedules/occurrences.

- [ ] **Step 3: Replace item-level routine reduction with exact occurrences.**

The public DTO shape is:

```ts
{
  id,
  name,
  dose_text,
  origin,
  reminders_enabled,
  schedules,
  occurrences,
}
```

Do not collapse occurrences into one status.

- [ ] **Step 4: Write RED official-loader tests.**

Mock the routine read RPC with multiple schedules, one action, delayed finalizer state and archived exclusion. Prove the loader uses the authenticated user's stored timezone/date and fails closed on malformed or failed routine payloads.

- [ ] **Step 5: Replace direct routine table reads with the canonical routine read RPC.**

Keep meals, workouts and hydration queries unchanged. Parse the RPC response before passing it to `buildDailyState`; no client-supplied timezone or item type enters the query.

- [ ] **Step 6: Update calculation documentation and verify.**

Document that v2 changes only the routine contract, not calorie, macro, hydration or bloco formulas.

```bash
pnpm --filter @mpp/core test
pnpm --filter @mpp/agent test -- daily-state-service.test.ts
pnpm --filter @mpp/core typecheck
pnpm --filter @mpp/agent typecheck
git diff --check
```

Expected: PASS.

- [ ] **Step 7: Commit `feat(daily-state): expose exact routine occurrences`.**

### Task 7: Exact Reminder Resolution, Snooze Follow-Up And Missed Finalizer

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_routine_occurrence_delivery`
- Modify: `supabase/tests/bodyflow_routine_items.sql`
- Modify: `supabase/tests/bodyflow_push_routine.sql`
- Create: `packages/inngest-functions/src/functions/routine-occurrence-scheduler.ts`
- Create: `packages/inngest-functions/src/functions/routine-occurrence-scheduler.test.ts`
- Modify: `packages/inngest-functions/src/functions/reminder-scheduler.test.ts`
- Modify: `packages/inngest-functions/src/client.ts`
- Modify: `packages/inngest-functions/src/index.ts`

**Consumes:** Task 2 occurrence columns; Task 3 state-transition helper/RPC.

**Produces:**

```sql
public.list_due_routine_snoozes(
  p_fired_at timestamptz,
  p_lookback_minutes integer,
  p_limit integer,
  p_after_snoozed_until timestamptz default null,
  p_after_log_id uuid default null
) returns table(adherence_log_id uuid, snoozed_until timestamptz)

public.claim_routine_snooze_event(
  p_adherence_log_id uuid,
  p_claimed_at timestamptz
) returns jsonb

public.finalize_due_routine_occurrences(
  p_now timestamptz,
  p_limit integer,
  p_after_scheduled_for timestamptz default null,
  p_after_user_id uuid default null,
  p_after_rule_id uuid default null
) returns jsonb
```

- [ ] **Step 1: Add RED SQL cases for exact regular reminder resolution.**

For one item with 08:00 and 20:00, a taken 08:00 action resolves only the 08:00 claim. The 20:00 claim remains eligible. A snoozed 08:00 suppresses only the regular 08:00 delivery until its follow-up; other item schedules remain independent.

- [ ] **Step 2: Add RED SQL cases for snooze/finalization.**

Prove one due snooze row per latest open occurrence, keyset pagination, stale/terminal snooze suppression, one follow-up notification event/delivery under retries, one missed row per unresolved ended local day, no missed for taken/skipped, derived/read state parity, deterministic spring-forward/fall-back handling, and no item name/dose in event/outbox metadata. Finalizer pagination orders and resumes by the complete tuple `(scheduled_for, user_id, rule_id)` so several occurrences for one user/rule or a multi-day backlog cannot be skipped.

- [ ] **Step 3: Generate and implement the delivery migration.**

Run `supabase migration new bodyflow_routine_occurrence_delivery`. Replace only the routine branch of the latest `claim_reminder_event` definition while preserving all existing meal/hydration/workout/content behavior byte-for-byte where practical. The routine branch requires an active item, active exact rule and `reminders_enabled=true`; it resolves only the matching occurrence key. It snapshots the controlled preview mode on the delivery, uses neutral routine template keys and `personality='default'` for medication, and never copies name/dose into events or deliveries. Add new service-only snooze/finalizer functions and explicit privileges.

- [ ] **Step 4: Write RED Inngest pure-function tests.**

Cover keyset progression, duplicate input collapse, one event per technical log ID, 15-minute discovery window, out-of-window rejection, page ceiling failure, finalizer cursor progression and event payloads that contain IDs/timestamps only.

- [ ] **Step 5: Implement the occurrence scheduler module.**

Add typed events:

```ts
'routine.snooze.due': {
  data: { adherenceLogId: string; snoozedUntil: string }
}
```

The cron discovers snoozes and finalizes missed occurrences through RPCs. The claim worker uses concurrency key `event.data.adherenceLogId`. Provider sending remains impossible; only the existing notification outbox can be queued.

- [ ] **Step 6: Register functions without live synchronization.**

Export and include the functions in `allFunctions` so local/build tests see them. Do not run an Inngest sync, invoke the cron, or configure a provider in staging.

- [ ] **Step 7: Run focused verification.**

```bash
pnpm --filter @mpp/inngest-functions test -- routine-occurrence-scheduler.test.ts reminder-scheduler.test.ts
pnpm --filter @mpp/inngest-functions typecheck
git diff --check
```

Expected: PASS.

- [ ] **Step 8: Commit `feat(inngest): schedule exact routine occurrences`.**

### Task 8: API Documentation, ADR And Full Local Review

**Files:**
- Modify: `docs/mobile/api-v1.md`
- Create: `docs/adr/016-bodyflow-routine-adherence.md`
- Modify: `docs/superpowers/plans/2026-07-22-bodyflow-supplements-medications-routine.md`

- [x] **Step 1: Document every public contract.**

Include CRUD, history cursor, log actions, disclaimer GET/accept, status semantics, snooze constraints, preview modes, idempotency, optimistic version, archive behavior, stable errors and complete JSON examples for supplement and medication.

- [x] **Step 2: Record the architecture decision.**

Document why shared normalized items/rules/logs beat separate tables and JSON, why pending is derived, why missed is persisted redundantly, why schedule occurrence identity is rule plus original instant, and why medication notifications default to private neutral copy.

- [x] **Step 3: Run complete local verification.**

```bash
pnpm --filter @mpp/core test
pnpm --filter @mpp/admin test
pnpm --filter @mpp/agent test
pnpm --filter @mpp/inngest-functions test
pnpm test
pnpm typecheck
pnpm --filter @mpp/admin build
git diff --check
```

Expected: every command exits zero.

- [x] **Step 4: Run changed-file quality and privacy scans.**

Run Biome on changed TypeScript/TSX. Scan only added production lines under `apps`, `packages` and `supabase` for token-like values, real emails/phones, medication names in telemetry calls, new WhatsApp dependencies/routes/copy, direct authenticated DML grants, unrestricted SECURITY DEFINER functions and raw payload logging; documentation is excluded because it records the prohibition itself. Use:

```bash
git diff --unified=0 eddf055b92ebac6f91c1541e72bda1e9ac1033cd -- apps packages supabase | rg "^\+.*(WhatsApp|whatsapp|Bearer [A-Za-z0-9._-]{16,}|@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\+?[0-9][0-9 ()-]{8,}|GRANT .* TO (anon|authenticated)|SECURITY DEFINER|request body|raw payload)"
```

Review every match in context; `SECURITY DEFINER` is acceptable only with the fixed-path/revocation/grant controls above. Test fixtures use `.invalid` email domains and synthetic UUIDs only.

- [x] **Step 5: Review the full branch diff against the specification.**

Check exact-occurrence resolution, DST/local-day behavior, schedule history, append-only logs, legal hash/version coupling, stale PATCH behavior, partial-failure retries, RLS/grants, cross-user 404 behavior, cursor stability, outbox privacy and no formula regressions.

- [x] **Step 6: Fix every Critical or Important finding and rerun its covering tests.**

Do not waive findings. Record remaining lower-risk limitations in the plan evidence without presenting them as fixed.

- [x] **Step 7: Commit `docs(bodyflow): document routine item contracts`.**

#### Task 8 local evidence — 2026-07-23

- `docs/mobile/api-v1.md` now records CRUD, exact actions, keyset history,
  disclaimer GET/accept, state transitions, snooze/local-day constraints,
  preview modes, two-layer idempotency, optimistic versioning, archive replay,
  stable errors and complete supplement/medication JSON examples.
- ADR 016 selects normalized shared items/rules/logs, derived `pending`,
  redundantly persisted `missed`, rule plus original UTC instant identity and
  neutral private-by-default medication notifications.
- The complete diff from `eddf055b92ebac6f91c1541e72bda1e9ac1033cd` was
  reviewed for exact occurrence/DST, immutable schedule history and logs, legal
  coupling, stale writes, retry receipts, RLS/grants, opaque cross-user 404s,
  cursor tuples, outbox privacy and formula regressions. Calorie, macro,
  hydration and bloco 7700 calculations are unchanged.
- Three Important findings were fixed and covered: PATCH with only
  `expected_version` now fails validation; medication create `428` now includes
  only the current legal key/version; generic `/reminders` writes can no longer
  bypass versioned supplement/medication schedule history. No Critical finding
  remained.
- Verification passed: core 204 tests; admin 546; agent 1,053; Inngest 167;
  monorepo 6/6 tasks; typecheck 8/8 tasks; admin production build; 49-file
  Biome; JSON/hash validation; and `git diff --check`.
- The required added-line scan produced only synthetic UUID/date/hash matches,
  `.invalid` e-mails, five authenticated `SELECT` grants protected by RLS and 16
  fixed-path `SECURITY DEFINER` functions with explicit backend-only controls.
  It found no new WhatsApp surface, bearer token, real contact, raw payload or
  unrestricted privileged function.
- Remaining limitation: migrations were not applied or executed, generated
  database types were not refreshed, and no staging canary ran. Those guarded
  SQL-runtime steps remain exclusively in Task 9; no production/staging,
  provider, cron, deploy, Inngest sync or Xcode action occurred in Task 8.

#### Task review fixes — 2026-07-23

- Removed the stale phase-limit statement that called supplements/medications
  read-only and put CRUD/dose out of scope. The limit now reflects the shipped
  versioned CRUD while keeping clinical guidance, recommended dosing and
  prescribing excluded.
- Clarified schedule errors without changing behavior: item request-schema
  duplicates are `422 validation_failed`; defensive domain/storage rejection of
  invalid or duplicate item schedules is `422 routine_schedule_invalid`;
  `409 routine_schedule_conflict` covers both blocked routine-category writes
  through generic `/reminders` and true concurrency/business schedule conflicts
  reported by the item CRUD repository/RPC after request validation.
- Remaining Minor: the medication collection regression asserts the
  service-level `MobileApiError` thrown by the handler, not the final route HTTP
  envelope. Existing route-wrapper tests cover generic envelope serialization,
  but this exact 428 envelope is not asserted end to end.
- Remaining Minor: generic reminder PATCH finds the owned target by listing
  reminders, and `findRoutineItem` remains unused after routine schedule writes
  were reserved to item CRUD. This is an internal efficiency/cleanup limitation,
  not a correctness defect; no repository refactor was included in this review
  fix.
- Review-fix verification passed: the API document's 31 JSON examples, legal
  SHA-256 and canonical history cursor; the focused stale-contract search;
  `pnpm --filter @mpp/core test -- routine.test.ts` (16 files/204 tests); and
  `pnpm --filter @mpp/admin test -- routine-item-service.test.ts
  supabase-routine-items.test.ts routine-service.test.ts
  medications/route.test.ts` (49 files/546 tests). No TypeScript or TSX changed
  after Task 8 commit `5f1e1d2`, so this review fix did not require scoped Biome.

### Task 9: Staging Migrations, Synthetic Canary, Generated Types And Draft PR

**Files:**
- Modify after verified staging schema: `packages/db/src/generated/database.ts`
- Modify: `docs/superpowers/plans/2026-07-22-bodyflow-supplements-medications-routine.md`

All persistent live SQL is reserved for this task and requires the staging safety gate below. Production is never a fallback.

- [ ] **Step 1: Revalidate worktree and Supabase link.**

Confirm the path and branch are exact, worktree is clean, `supabase/.temp/project-ref` equals `xitugspwfxkcluxvrdeg`, and it does not equal production `xuxehkhdvjivitduarvb`. Stop on missing ref, mismatch or ambiguity.

- [ ] **Step 2: Revalidate staging isolation.**

Query only safe cron metadata and aggregate counts. Confirm exactly 34 jobs and zero active jobs. Confirm no real patient data is used and no external integration secret is configured or read.

- [ ] **Step 3: Inspect migration scope before applying.**

Run migration list and dry-run. Review that only migrations created by Tasks 2, 3 and 7 are pending and all changes are additive. Stop if any unrelated migration appears.

- [ ] **Step 4: Execute and record the transactional RED database test.**

Run `supabase/tests/bodyflow_routine_items.sql` against staging before migration application. It must roll back and fail specifically because `public.routine_items.dose_text` is absent. Stop if it passes, changes a persistent row or fails for connectivity, permissions, stale base migrations or another unexpected reason.

- [ ] **Step 5: Apply only the reviewed routine migrations to staging.**

Do not deploy an application, activate a cron, configure APNs, sync Inngest or change production.

- [ ] **Step 6: Run SQL suites transactionally.**

Execute `supabase/tests/bodyflow_routine_items.sql` and `supabase/tests/bodyflow_push_routine.sql` in transactions that roll back synthetic users and rows. Run DB lint and advisors, separating new findings from pre-existing findings.

- [ ] **Step 7: Regenerate database types from staging.**

Generate `packages/db/src/generated/database.ts` using staging ref `xitugspwfxkcluxvrdeg`. Keep only expected routine/legal columns, tables and RPCs; discard unrelated generator drift. Run DB/admin/agent/Inngest typechecks.

- [ ] **Step 8: Execute the complete synthetic canary.**

With two synthetic patients and no external send:

1. Patient A accepts the exact medication disclaimer.
2. Patient A creates one supplement and one medication with 08:00 and 20:00 schedules.
3. Patient B cannot read, edit, archive, log or infer either item.
4. Patient A records 08:00 taken; 20:00 remains pending.
5. Patient A snoozes 20:00 and one technical follow-up is queued.
6. A same-key retry creates no second action/delivery.
7. A second item is archived; schedules deactivate and history remains.
8. A synthetic ended day finalizes one unresolved occurrence as missed.
9. A seven-day-bounded correction appends taken and preserves missed.
10. Notification preview defaults private and no technical event contains name/dose.

- [ ] **Step 9: Clean and prove postconditions.**

Delete synthetic Auth/domain rows through the approved cleanup path and assert aggregate zero retained synthetic items, rules, logs, acceptances, receipts, reminder events and deliveries. Confirm 34 cron jobs remain present and zero active.

- [ ] **Step 10: Run final application verification after generated types.**

Run full tests, full typecheck, admin build, changed-file Biome and `git diff --check`. Repeat the privacy/security scan.

- [ ] **Step 11: Record redacted evidence and commit.**

Write aggregate-only results in this plan. Commit generated types and evidence as `docs(bodyflow): complete routine staging validation`.

- [ ] **Step 12: Push and open a stacked draft PR.**

Push `codex/bodyflow-routine-medications-v1` and open a draft PR with base `codex/bodyflow-content-cms-v1`. Do not merge or deploy.

## Specification Traceability

| Approved specification area | Implemented and verified by |
| --- | --- |
| Controlled routine inputs and exact state reducer | Task 1 |
| Additive item, schedule, occurrence, legal and privacy persistence | Task 2 |
| Transaction boundaries, optimistic concurrency, idempotency and occurrence identity | Task 3 |
| Supplement/medication CRUD, list and history contracts | Task 4 |
| Legal acceptance, adherence actions, preview preference and legacy wrapper safety | Task 5 |
| Current-day exact occurrences and unchanged nutrition/hydration formulas | Task 6 |
| Exact reminder resolution, snooze follow-up, missed finalization and DST behavior | Task 7 |
| Clinical-copy boundary, architecture record, stable API documentation and privacy review | Task 8 |
| Staging-only SQL validation, synthetic isolation canary and generated types | Task 9 |
| No production, APNs, Xcode, visual prompt, real integration or real-patient action | Global constraints and Task 9 gate |

## Completion Gate

Do not mark Prompt 09 complete unless all conditions hold:

- every implementation slice has its own commit and the worktree is clean;
- supplement and medication CRUD are authenticated, patient-owned and strictly typed;
- medication creation requires the exact current disclaimer acceptance;
- one taken schedule never resolves another schedule from the same item/day;
- snooze remains on the original occurrence, stays within the local day and queues at most one follow-up;
- `skipped` is explicit, `missed` is derived/persisted, and late correction preserves audit history;
- schedule edits preserve historical rule identities and stale versions cannot overwrite newer edits;
- archive disables future reminders without deleting history;
- direct client writes, cross-user reads and client-executable trusted RPCs are denied;
- item names, doses, legal copy and PII do not enter logs, product events or Inngest payloads;
- daily state v2 exposes all exact occurrences without changing calorie, macro, hydration or bloco formulas;
- SQL, core, admin, agent, Inngest, monorepo, typecheck and admin build checks pass;
- staging canary cleans all synthetic rows and leaves all 34 cron jobs inactive;
- production, Vercel deploy, APNs, Xcode, visual prompts and external integrations remain untouched;
- a stacked draft PR is open with no merge or deployment.

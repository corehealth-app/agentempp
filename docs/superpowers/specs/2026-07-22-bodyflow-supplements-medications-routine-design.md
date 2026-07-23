# BodyFlow Supplements, Medications And Routine Design

**Status:** approved in conversation for specification on 2026-07-22. Product
implementation still requires an approved implementation plan.

## Objective

Extend the existing app-first routine foundation so a patient can privately
manage supplements and medications, receive reminders and record adherence.
BodyFlow remains an organizer and reminder. It does not prescribe, recommend,
interpret or change a medication or dose, and it does not make medical claims
about supplements.

## Confirmed product decisions

- The new flow has no WhatsApp dependency.
- One item can have multiple schedules, such as 08:00 and 20:00.
- Snooze asks for 15, 30 or 60 minutes, or a custom time on the same local day.
- No response is not a skip. `skipped` requires an explicit patient action;
  unresolved occurrences become `missed` after the local day ends.
- Delete archives the item, disables future reminders and preserves history.
- The first medication creation requires a versioned, one-time legal acceptance.
- Medication notification previews are private by default.
- The existing normalized routine domain will be extended instead of creating
  separate, duplicated supplement and medication subsystems.

## Current foundation and confirmed gap

The repository already contains:

- `routine_items` for private supplement and medication identities;
- `reminder_rules` for local time and weekdays;
- append-only `routine_adherence_logs`;
- a reminder event and notification outbox pipeline;
- BFF routes for hydration and the legacy `taken` action;
- daily-state sections for supplements and medications.

The current reminder claim resolves an item when any `taken` or `skipped` log
exists for that item on the same local date. With two schedules, taking the
08:00 occurrence can therefore resolve the 20:00 reminder. Prompt 09 must move
resolution from item/day scope to exact schedule-occurrence scope.

## Scope

### Included

- Full patient-owned CRUD for supplements and medications.
- Controlled free-text dose.
- Source: `user`, `professional`, `protocol` or `other`.
- Multiple local-time and weekday schedules.
- Per-item reminder preference.
- Per-occurrence `pending`, `taken`, `snoozed`, `skipped` and `missed` state.
- Append-only action history and cursor-paginated history APIs.
- Same-day snooze and follow-up reminder queueing.
- Versioned medication disclaimer and acceptance.
- Daily-state integration and exact-occurrence reminder resolution.
- Privacy-safe observability and deterministic/idempotent writes.

### Excluded

- Prescription, diagnosis or clinical decision support.
- Dose parsing, unit conversion, interaction checks or dose recommendations.
- Medication catalog lookup, pharmacy integration or prescription upload.
- Medical or physiological claims for supplements.
- APNs credentials or real push delivery.
- iOS UI implementation, StoreKit, Xcode or visual prompts.
- Production migration, data backfill or deploy.

## Domain model

### Routine items

`routine_items` remains the canonical identity table. Additive fields:

- `dose_text text`: nullable in storage for legacy compatibility, but required
  and non-blank for all new mobile API creates;
- `origin text`: constrained to `user`, `professional`, `protocol`, `other`;
- `reminders_enabled boolean`: controls push eligibility without deleting the
  schedule used by Today and adherence;
- `archived_at timestamptz`: null while active and set by DELETE;
- `version integer`: incremented on every accepted mutation for optimistic
  concurrency.

`dose_text` is trimmed and length-bounded. It is returned exactly as patient
data and is never parsed into a numeric dosage. The item type remains
`supplement` or `medication` and cannot be changed after creation.

`origin` is descriptive patient metadata, not proof that a professional issued
or reviewed the entry. This phase does not collect a professional identity.

The existing `active` flag remains compatible with reminder-rule constraints.
Archiving atomically sets `active=false`, `archived_at`, disables reminders and
deactivates active rules.

### Schedules

`reminder_rules` remains the normalized source for local time and weekdays. One
routine item can own multiple rules. The API exposes them as one `schedules`
array and computes frequency from that array instead of persisting a second
frequency representation that could drift.

For routine-item edits, time or weekday changes do not overwrite an old active
rule in place. The mutation deactivates the old rule and inserts a replacement.
This keeps historical rule IDs stable. Unchanged rules retain their IDs.

An active item must have at least one schedule. `reminders_enabled=false`
suppresses notification delivery but keeps schedules available for the daily
routine and manual adherence.

### Exact occurrence identity

A scheduled occurrence is identified by:

- patient ID;
- routine item ID and type;
- reminder rule ID;
- original `scheduled_for` instant.

The original instant does not change after a snooze. A stable occurrence key is
derived from the rule ID and original instant. It is used by adherence queries,
reminder claims, retries and finalization. The database derives this key after
validating the rule; the API never accepts a client-supplied occurrence key.

`routine_adherence_logs` receives additive occurrence fields:

- `reminder_rule_id`;
- `occurrence_key`;
- `source`, constrained to `patient`, `system` or `offline_sync`;
- optional `supersedes_log_id` for an audited late correction.

The effective-state query is indexed by patient, occurrence key and descending
action time. The source value is assigned by the backend and is not a writable
client field.

Existing rows remain valid with nullable occurrence fields. New mobile writes
must use exact occurrence identity. Every action is appended; prior actions are
never updated or deleted.

### Current state

The latest valid action for an occurrence determines its state:

```text
pending -> taken
pending -> skipped
pending -> snoozed -> taken
pending -> snoozed -> skipped
pending -> snoozed -> snoozed
pending -> missed -> taken (audited correction, up to seven days)
```

`taken` and `skipped` are terminal for ordinary client requests. A patient may
correct an automatically generated `missed` action to `taken` during the
existing seven-day offline window; the correction points to the previous log
and does not erase it. The client cannot submit `missed`.

`pending` is derived from an eligible schedule with no action and is not stored
as a fake adherence event. A backend finalizer appends one idempotent `missed`
event after the patient's local day ends for every unresolved occurrence. If
that worker is delayed, reads still derive `missed` from the local-day boundary;
the finalizer persists the same result later without changing the public state.

### Legal acceptance

Create a private, reusable legal-acceptance table keyed by patient, document key
and document version. For this phase the document key is
`medication_reminder_disclaimer`.

The backend serves the current localized text and version. Before the first
medication is created, the patient explicitly accepts that exact version. A
newer required version can require a new acceptance without changing old audit
rows. Acceptances cannot be edited or deleted by the patient API.

The approved meaning is:

> BodyFlow only organizes reminders and records. It does not prescribe,
> recommend or change medications or doses. Follow the guidance of the
> responsible healthcare professional.

Final localized copy can be reviewed before the iOS prompt without changing the
contract or acceptance semantics.

## API contracts

All paths use `/api/mobile/v1`, require authenticated patient context, and send
the standard request ID envelope. Every mutation requires `Idempotency-Key`.

### Collection and item routes

- `GET /supplements`
- `POST /supplements`
- `PATCH /supplements/:id`
- `DELETE /supplements/:id`
- `POST /supplements/:id/log`
- `GET /supplements/:id/history`
- `GET /medications`
- `POST /medications`
- `PATCH /medications/:id`
- `DELETE /medications/:id`
- `POST /medications/:id/log`
- `GET /medications/:id/history`

Creation accepts:

```json
{
  "name": "Creatina",
  "dose_text": "3 g",
  "origin": "professional",
  "reminders_enabled": true,
  "schedules": [
    {
      "local_time": "08:00",
      "weekdays": [0, 1, 2, 3, 4, 5, 6]
    }
  ]
}
```

The server sorts and deduplicates weekdays and rejects duplicate logical
schedules. Create, schedule creation and the first domain event commit in one
transaction. PATCH includes `expected_version`; stale edits return 409 and do
not partially change schedules. DELETE is an idempotent archive operation.

List responses return canonical item fields, stable schedule IDs, a structured
frequency summary and current-day occurrences. Archived items are excluded by
default and can be requested explicitly for history screens.

History uses an opaque cursor and bounded page size. It returns occurrences and
their action timeline without exposing rows owned by another patient.

### Adherence log

The log body identifies the exact schedule occurrence:

```json
{
  "status": "snoozed",
  "reminder_rule_id": "00000000-0000-0000-0000-000000000000",
  "scheduled_for": "2026-07-22T12:00:00.000Z",
  "occurred_at": "2026-07-22T12:01:00.000Z",
  "snoozed_until": "2026-07-22T12:31:00.000Z"
}
```

Allowed client statuses are `taken`, `snoozed` and `skipped`. Snooze requires a
future `snoozed_until` on the same patient-local date as the original
occurrence. Presets are 15, 30 and 60 minutes; custom time follows the same
server constraint. The server validates ownership, item type, active/archive
state, rule ownership and that the supplied instant represents that rule.

### Legal routes

- `GET /legal/medication-reminder-disclaimer`
- `POST /legal/medication-reminder-disclaimer/accept`

Medication POST returns `428 medication_disclaimer_required` when the current
required version has not been accepted. The error includes only the stable
document key and version needed to load the legal route.

### Legacy action compatibility

The existing `/routine/supplements/:id/taken` and
`/routine/medications/:id/taken` routes remain as compatibility wrappers. They
may resolve an occurrence only when exactly one eligible occurrence exists. If
zero or multiple candidates exist they return an explicit conflict instead of
guessing. New clients use `/:id/log`.

## Transaction boundaries

Backend-only RPCs perform the following atomically:

- create item plus schedules;
- update item plus versioned schedule replacement;
- archive item plus reminder deactivation;
- accept one legal-document version;
- validate and append one adherence action;
- finalize unresolved occurrences as `missed`;
- claim an exact regular or snoozed occurrence for notification delivery.

Each RPC takes an advisory transaction lock on the smallest stable resource:
item ID for CRUD, patient/document/version for acceptance, and occurrence key
for adherence. Reusing an idempotency key with a different payload is a 409;
reusing it with the same payload returns the original result.

## Reminder behavior

The reminder scheduler keeps local-time calculation in the backend. It claims
one exact occurrence, not all actions for an item on the same date.

For snooze, the original occurrence remains the identity and the next delivery
uses `snoozed_until`. Reminder events carry the non-sensitive occurrence key so
the follow-up can be correlated without adding medication name or dose to an
Inngest event.

Push preview modes are added to notification preferences:

- `private` (default): generic routine reminder;
- `name`: item name only;
- `name_and_dose`: item name and patient-entered dose.

The preference affects rendered push content only. APNs tokens, item name and
dose are not added to logs, product events or Inngest payloads. Real APNs
delivery remains outside this prompt.

## Daily state

The supplements and medications sections expose each item with its schedules
and today's exact occurrences. Each occurrence includes:

- reminder rule ID;
- original `scheduled_for`;
- current status;
- last action timestamp;
- `snoozed_until` when applicable.

The state is derived using the patient timezone and the latest valid action per
occurrence. One taken occurrence never changes another schedule. The response
continues to use the server calculation version; the iOS client does not
recompute routine status.

## Clinical and communication safeguards

- Names and doses are patient data, not instructions generated by BodyFlow.
- No API accepts a recommended dose, dose adjustment or treatment advice.
- The agent and content layers do not infer efficacy, interactions or safety.
- Medication reminders use neutral language regardless of selected persona.
- Mascot, streaks and gamification cannot reward medication adherence or shame a
  patient for `skipped` or `missed` states.
- Supplement copy cannot make medical, curative or guaranteed performance
  claims.
- A medication reminder can always be disabled without changing the historical
  record.

## Security and privacy

- All domain tables keep RLS enabled.
- Authenticated reads are limited to rows linked to `auth.uid()` through the
  domain user.
- No direct authenticated writes are granted.
- Mutations run through the BFF and trusted-backend RPCs.
- SECURITY DEFINER functions use a fixed search path, call
  `private.assert_trusted_backend()` and are revoked from PUBLIC, anon and
  authenticated.
- Medication name, dose, legal text and raw payloads are excluded from
  observability events.
- Metrics use technical IDs, item type, transition, result code and latency.
- Cross-patient lookups return 404 where appropriate and do not disclose
  existence.

## Stable errors

- `routine_item_not_found`
- `routine_item_inactive`
- `routine_item_type_mismatch`
- `routine_item_version_conflict`
- `routine_schedule_invalid`
- `routine_schedule_conflict`
- `routine_occurrence_not_found`
- `routine_occurrence_ambiguous`
- `routine_transition_invalid`
- `routine_snooze_invalid`
- `routine_idempotency_conflict`
- `medication_disclaimer_required`
- `medication_disclaimer_version_stale`

Validation errors are 422, stale version and idempotency conflicts are 409,
missing legal acceptance is 428, and inaccessible resources are 404.

## Verification strategy

### SQL and database tests

- RLS blocks cross-patient item, schedule, log and legal-acceptance reads.
- Authenticated and anon roles cannot write routine or acceptance data.
- Item type and owner FKs reject cross-type or cross-owner references.
- Duplicate schedules and invalid weekday/time combinations are rejected.
- CRUD RPCs are atomic and increment version exactly once.
- Archive disables all future item reminder claims without deleting history.
- One 08:00 `taken` action does not resolve the 20:00 occurrence.
- Snooze updates only the selected occurrence and queues at most one follow-up.
- Concurrent and retrying log requests append one effective action.
- Finalization writes one `missed` action per unresolved occurrence.
- Retroactive correction preserves both `missed` and corrective `taken` rows.
- DST transition dates produce deterministic occurrence identities.

### Application tests

- Zod contracts reject unknown fields, unsupported statuses and malformed dose,
  schedules or cursors.
- Medication creation is blocked before current legal acceptance.
- Supplement creation does not require medication acceptance.
- List, update, archive and history preserve ownership and stable DTOs.
- Legacy taken wrapper rejects ambiguous multiple schedules.
- Daily state represents all occurrences independently.
- Push rendering honors preview preference without leaking content to events.
- Client cannot submit `missed` or snooze into another local date.

### Regression commands

- `pnpm --filter @mpp/admin test`
- `pnpm --filter @mpp/core test`
- `pnpm --filter @mpp/agent test`
- `pnpm --filter @mpp/inngest-functions test`
- `pnpm test`
- `pnpm typecheck`
- `pnpm --filter @mpp/admin build`
- Supabase migration lint and transaction-scoped SQL tests against staging.

## Rollout boundary

Implementation is developed on the stacked
`codex/bodyflow-routine-medications-v1` branch. Database validation uses only the
approved Supabase staging branch and synthetic users. The 34 staging crons stay
disabled. Tests clean synthetic rows after execution.

No migration is applied to production, no deployment is created, no APNs or
other external integration is configured, and no production data is read or
changed without a separate explicit authorization.

## Alternatives rejected

### Separate supplement and medication tables

This duplicates schedules, logs, RLS, API services and daily-state behavior and
would leave two competing routine systems. The domain differences are enforced
by item type and clinical policies instead.

### JSON schedules and history inside the item

This is initially smaller but weakens relational ownership, uniqueness,
pagination, concurrency and exact-occurrence queries. Normalized rules and
append-only logs match the existing architecture and failure model.

# Command-owned meal Save and Undo

This additive SQL slice has five service-only RPCs. It adds no HTTP route,
public flag, provider call or nutrition calculation. Private reads return full
C11 state for the authenticated backend; it must never forward that state as a
public health payload. Audit history pagination and message binding remain
separate work.

| RPC | Arguments after `p_user_id uuid, p_command_id uuid` |
| --- | --- |
| `read_conversation_meal_edit_state` | none |
| `read_conversation_meal_edit_operation` | `p_operation_id uuid, p_input jsonb` |
| `commit_conversation_meal_item_edit` | `p_operation_id uuid, p_input jsonb, p_expected_state jsonb, p_calculated_items jsonb, p_nutrition_mode text, p_quantity_change jsonb, p_request_id text` |
| `undo_conversation_meal_item_edit` | `p_operation_id uuid, p_input jsonb, p_expected_state jsonb, p_request_id text` |
| `undo_conversation_meal_registration` | same as item Undo |

The backend binds the authenticated owner and original command. Every write
uses the existing owner/workout lane, current epoch and permanent command
tombstone before replay. New writes then take the day lane, snapshot and all
snapshot meal rows in C11 order. Existing NOWAIT/busy refusals are preserved.
Only READ COMMITTED is accepted.

`p_input` is a closed object with `schema: conversation.meal-edit.v1`,
`kind`, integer `expected_revision` and C11 `expected_version`.

- `save` additionally has `record_id` and `items`, using the existing confirmed
  meal item input fields. A new nutrition label is not accepted. The trusted
  backend supplies the existing C11 calculation/mode/proportional proof.
- `undo_save` additionally has `target_operation_id`. It accepts no clock,
  replacement nutrition or restored rows from the caller.
- `undo_registration` has no other fields.

Revision zero denotes the original registration. The full typed
`p_expected_state` is the SQL CAS, exactly as in C11; the `v1:` string alone is
only syntax-checked. The BFF must compare the client's version with its current
private C11 version before calculation. It must not silently replace stale
client state with a fresh server snapshot. Expected state and calculated items
are authenticated backend values, not request-body fields.

Save calls unchanged `mutate_mobile_confirmed_meal` PATCH for one selected
anchor, including one-to-many output. Its internal idempotency key includes
both command and operation UUIDs. The same transaction stores the actual
selected before-image, whole before/after groups, inserted rows, next revision
and mandatory receipt. The original conversation FX, confirmed proposal and
v1/v2 registration feedback remain immutable.

Registration Undo is allowed only at revision zero, while the entire current
physical group equals `FX.original_facts.logs`. Its deadline is the existing
server effect clock `FX.committed_at + 5 minutes`, not admission time, meal
creation time, a client clock or an invented PostgreSQL commit timestamp. It
removes exactly the original group and retains independent registrations.

Item Undo targets the latest uncompensated Save, with the exact recorded
after-group and its own `applied_at + 5 minutes` deadline. It replaces every
output ID with the stored prior item using the finite scoped writer. It
restores persisted values directly, including provenance and media headers;
inverse proportional calculation would lose rounding information. Restored
rows receive new physical IDs and creation clocks. Missing reference authority
fails atomically. Undo itself has no redo/recursive Undo contract.

External C11 edits, deletion or equal facts reinserted under new IDs make the
old Undo obsolete. A fresh Save can capture the actual current owned group
after a new full CAS. Current-day, open-day and deadline checks run after all
locks and again after mandatory audit publication. Expiry is inclusive
(`deadline <= server clock`). A late publication failure rolls back the entire
compensation. Day totals use C11's current sums/rounding; nullable targets,
exercise, unrelated rows, XP and block state are preserved.

Every successful write/replay and operation read also returns `command`, the
actual original database command binding (owner, command UUID, original input
hash, epoch, protocol, kind and admission clock). The BFF validates this binding
against its detached command on every success/recovery; it must not fabricate
an epoch or use the edit-intent hash as the original command hash.

Writes return `committed` or `replay` with an immutable
`conversation.meal-edit-effect.v1` receipt. Its `input_hash` identifies the edit
intent, not the original meal command input. It contains owner/command/operation,
kind (`saved`, `save_undone`, `registration_undone`), revision, server clocks,
optional Undo target, removed/new IDs, nullable next record ID and the existing
C11 snapshot allowlist. Business refusals are `absent`, `stale_epoch`,
`input_conflict`, `version_conflict`, `undo_expired`, `day_closed`, `in_progress`
or `event_conflict`; existing SQL exceptions remain exceptions. No retry is
performed inside these RPCs.

State reads return `available` with the original receipt, command binding,
current revision/state, lineage compatibility, last receipt, registration Undo
deadline and observation clock. Operation reads return `available` with the
stored receipt and actual command binding after checking the original edit input hash. Reads do not create
a head, initialize a day, calculate, seal feedback or invoke a domain writer.
After an unknown write response the caller explicitly reads; it does not
automatically repeat a calculation or compensation.

Private operation identities survive reset with the permanent command UUID.
Reset scrubs head, before/after images and receipts through the existing FX
cascade. The old epoch wins before replay. User deletion cascades all owned
state. The head's deferred foreign key retains final referential integrity while
allowing sibling account cascades to settle in the same transaction. RLS,
revoked direct grants and immutable audit/delete guards remain enforced.

Real local PG qualification covers original registration Undo, one-to-many
Save/Undo, full metadata restoration, NULL targets, independent appends, external
C11 drift/deletion, auth links, exact state CAS, first-winner replay, mandatory
receipt rollback, expiry across lock/audit waits, reset and account deletion.
Synthetic `auth.users` links exercise C11 database authority; they are not proof
of a GoTrue login or a public edit route. Evidence is retained privately under
`T3-DIRECT-EDIT-UNDO-PREPARATION`. No cloud deployment or public activation is
qualified by this SQL slice.

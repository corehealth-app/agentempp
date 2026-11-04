# Conversation journal public contract (not activated)

This is the implementation contract for the new Flow reader. The private SQL
page is already locally qualified. Public reader, native integration and
distribution remain separate gates; this document is not proof of activation.

`GET /api/mobile/v1/conversation/journal?limit=10&cursor=<opaque>` uses the same
default-off staging capability, actual Auth/entitlement checks and mandatory
original `X-Conversation-Owner` and `X-Conversation-Epoch` preconditions. No
per-command hash header is required for a page. Limit is 1–25. Unknown query
keys, repeated keys, malformed or foreign/old-epoch cursors are refused. The
standard mobile envelope is no-store and varies by Authorization.

The closed data packet is:

```ts
{
  schema: 'conversation.journal-page.v1',
  auth_user_id: UUID, // actual Auth subject, not inferred from patient
  owner_id: UUID,
  epoch: UUID,
  observed_at: Timestamp, // actual final server observation
  items: Array<CommandEntry | EditEntry>,
  has_more: boolean,
  next_cursor: string | null
}
```

`CommandEntry` has exactly `event_id`, `at`, `kind: 'command'`,
`original_command`, `result`, and `terminal_receipt`. `original_command` is
the original strict `conversation.command.v1`, including its UUID and exact
text or owned asset UUID/caption; never a source capture, transcript invented
from asset metadata, local URL or generated media URL. `result` is the existing
saved packet or `conversation.meal-command-state.v1` with pending/not_recorded;
absence is not a journal entry. The original report hash is rederived from the
canonical command and matched to the actual SQL binding. The event ID is
`command/<commandId>` and `at` equals original admission time.

For pending/saved entries `terminal_receipt` is null. For not_recorded entries
it is the following closed factual projection of the actual sealed SQL winner:

```ts
{
  schema: 'conversation.meal-decision-public.v1',
  status: 'not_recorded',
  owner_id: UUID,
  command_id: UUID,
  input_hash: SHA256, // original report hash
  epoch: UUID,
  reason: string, // [a-z_]{1,80}
  food_indexes: number[], // unique integers 0..29, at most 30
  decision_hash: SHA256, // opaque actual SQL token; do not reserialize
  sealed_at: Timestamp
}
```

The result reason/indexes and original identity match that terminal receipt.
`sealed_at` is not earlier than admission or later than final observation.
This proves delivery of a non-registration answer, never consumption or XP.
The native controller may close only the matching encrypted delivery entry
under its current revocable Auth/patient/epoch/generation lease, preserving
the no-resubmit state and deduplicating the remote transcript. It must not
evict unproven pending/unknown entries to make room, treat this as a saved-food
ACK, rewrite the original intent or grant any reward. A page read itself does
not acknowledge anything; explicit controller validation is required.

`EditEntry` has exactly `event_id`, `at`, `kind: 'edit'`, and `result`. Its result
is `conversation.meal-edit-result.v1`, with the actual original command
binding and the sanitized `conversation.meal-edit-effect-public.v1`. No private
snapshot, historical daily balance, before/after row groups or clinical context
is returned. Its ID is `edit/<commandId>/<operationId>` and `at` equals actual
application time. An operation UUID may legitimately repeat across commands.

Items retain SQL's descending time/event-ID C-collation order. A cursor encodes
only version 1, actual patient/epoch and the last included `{at,id}` anchor in
canonical base64url JSON. It is not write authority. SQL checks the owned
current-epoch anchor. No offset paging, device-clock sort or inferred chronology.

The public data packet is capped at 240,000 UTF-8 bytes, within the native
262,144-byte complete-envelope limit. Projection stops before an entry that
would exceed the cap and returns a cursor for the last included event; it must
never skip that next event. An unrepresentable first entry fails explicitly.
Fresh current-policy readers guard original saved feedback; no raw original
clinical feedback is sent. Profile observations before/after reading bind the
current server epoch. Optional feedback failure does not repeat any effect.

Reading, paging, refreshing and reopening do not invoke the provider, admit a
command, initialize a day, calculate nutrition, write consumption or issue XP.
Corrections and Undo remain immutable events linked to the original receipt;
the editable group supplies current facts separately. Old Flow messages remain
accessible through their existing reader and are not fabricated as new events.

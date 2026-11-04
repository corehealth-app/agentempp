# Linked meal reply transport

The existing conversation command capability also gates these dormant endpoints:

- `POST /api/mobile/v1/conversation/commands/[commandId]/replies`
- `GET /api/mobile/v1/conversation/commands/[commandId]/replies/[replyId]`

Both Admin and BFF wrappers use Node.js and a 120-second budget. The flag remains OFF by default. Both paths use the actual bearer subject, existing patient mapping and entitlement. Authentication never bootstraps a profile. It preserves the existing exclusion of any admin membership using a read-only membership lookup. `X-Conversation-Owner` must equal the actual patient, which can differ from the Auth subject. `X-Conversation-Epoch` is the immutable original backend epoch precondition; it is never proof of when an offline answer was created.

## Closed request and identity

POST accepts no query and exactly:

```json
{
  "schema": "conversation.meal-reply-submit.v1",
  "reply_id": "<original reply UUID>",
  "parent_input_hash": "<original parent hash>",
  "parent_decision_hash": "<opaque original decision hash>",
  "input": {
    "schema": "conversation.meal-clarification.v1",
    "expected_revision": 0,
    "question_key": "<actual question key>",
    "answer": { "kind": "quantity", "food_index": 0, "amount": 200, "unit": "mL" }
  }
}
```

The existing closed answer contract also accepts the six supported meal types. Quantity answers retain the exact allowed unit/reference semantics of the actual question. No calories, proposal, original text, model result or source proof can be supplied. The body is bounded to 16 KiB. `Idempotency-Key` must be exactly `cmreply1:<reply_id>`. The initial outbound body uses the qualified SQL-decimal operation canonical digest. Persisted historical JSONB hashes stay opaque; no body is reconstructed for resubmission from a GET.

GET accepts exactly one nonempty lowercase 64-hex `parent_input_hash` and `reply_input_hash`, plus the required original owner/epoch headers and path IDs. Unknown/duplicate keys, a missing hash or another identity fail closed.

## Result

The normal no-store mobile envelope contains exactly these `data` keys:

```
{
  schema: 'conversation.meal-reply-result.v1',
  auth_user_id, owner_id, epoch,
  parent_command_id, parent_input_hash, parent_decision_hash,
  reply_id, reply_input_hash,
  parent_binding, child_binding, observed_at,
  status, receipt, question, feedback, reason
}
```

`parent_binding` is the actual seven-field original report binding. `child_binding` is either the actual seven-field `conversation.clarification.v1` / `meal.clarify` binding or null. Admission and observation clocks are actual server observations, including microseconds; no transport clock is fabricated. The original negative parent stays immutable.

| status | Receipt, question and reason |
| --- | --- |
| `saved` | Actual requested child effect plus matching parent fulfillment; linked receipt present, question/reason null. |
| `needs_reply` | Actual admitted child and current unfulfilled head question; receipt/feedback/reason null. |
| `held` | No receipt/question/feedback; closed reason describes explicit resume or a refusal. |
| `reconciliation_required` | No receipt/question/feedback; closed reason, HTTP 202. |

Reasons are exactly `reply_conflict`, `parent_fulfilled`, `reply_superseded`, `awaiting_explicit_resume`, `ready_for_explicit_resume`, `question_changed`, `source_changed`, `day_closed`, `nutrition_unresolved`, `clarification_unavailable`, and `processing_uncertain`. A new admission quota refusal remains HTTP 429 and is never converted into a new UUID, an implicit retry or a misleading factual answer.

A requested reply that returns actual `reply_conflict` permits one bounded parent-only read under the same original owner/parent hash/epoch. This supplies the actual parent binding and observation only: `child_binding:null`, `status:reconciliation_required`, `reason:reply_conflict`. It does not prove absence, provide a current question or authorize admission. Stale, changed, ineligible or invalid original scope fails with HTTP 409.

The complete public result is bounded to 240,000 UTF-8 bytes. Optional presentation can be omitted atomically; mandatory facts are not truncated. The synthetic literal [packet](../../apps/admin/src/lib/mobile-api/__fixtures__/conversation-meal-reply-public.json) contains submit/saved/needs-reply/held/reconciliation examples and no real user, bearer, health or provider data.

## Effects and recovery

Constructors are inert. POST uses the real private continuation service, shared materializer/calculator/source and atomic writer. Its mandatory scope callback repeatedly verifies the original token, the same existing patient mapping and actual current backend epoch; observations are serialized and cannot reacquire after a failed check. Historical IDs never grant a capability. No interpreter/model is invoked by this new transport.

A submission is attempted once. An unknown response leads to one explicit actual complete same-identity read. No second submit, body replacement, admission or factual effect is scheduled. Public saved output requires the complete closed read, requested child receipt, actual parent fulfillment, original hash/epoch and exact source lineage. Private service outcome alone is insufficient.

After saved POST, only the qualified linked feedback adapter may ensure the optional original feedback, then read its historical presentation. Its binding uses the actual original parent, opaque decision hash, actual child and actual linked effect. Optional loss or unavailable frozen context does not invalidate saved food or repeat its registration. A lost optional seal is reconciled by the adapter's receipt-only read. GET uses only complete state, actual current-scope observations and read-only historical feedback. It never ensures/seals feedback, admits a reply, initializes a day, captures meal source, calculates, calls a model or advances rewards.

The shared public presentation guard preserves existing v1 output and accepts only common mandatory receipt fields for a qualified linked child. The linked original six-section renderer is the actual integrated adapter, with current clinical masking; malformed, oversized, stale, wrong-scope or unavailable optional output becomes null. A child is never relabelled as a v1 report or given invented provider/source facts. Journal v2 uses the same actual read-only linked historical seam; v1 remains unchanged.

Current editable child groups, Save/Undo transport, native reply dispatch, feature activation and published deployment remain separate gates. Focused controlled-SDK tests use the real Supabase library with explicit synthetic HTTP responses and an external-network deny stub; they are not real GoTrue/Postgres or public runtime QA. Root performs the coherent build/surface and actual local HTTP qualification after integration. No SQL, schema, generated database type, provider dependency or paid environment is changed here.

# Compact linked meal history, opt-in v2

The existing authenticated `GET /api/mobile/v1/conversation/journal` selects v2 only with `version=2`. An absent version or literal `version=1` retains the v1 reader and response. Other versions, duplicate query keys, unknown keys, empty cursor/version and noncanonical limits are rejected before service construction. Existing capability, entitlement, actual patient/epoch headers, no-store, and both 120-second route budgets remain in force.

Allowed query keys are `version`, `limit` (1–25, default 10), and `cursor`. The opaque canonical v2 cursor binds the authenticated patient, original epoch, actual server event timestamp and complete event ID. It cannot be used as a v1 cursor, a write permission, a terminal delivery proof, or a food ACK.

## Public response

The normal mobile envelope's `data` is exactly:

```
{
  schema: 'conversation.journal-page.v2',
  auth_user_id, owner_id, epoch, observed_at,
  threads: [Thread], items: [Event], has_more, next_cursor
}
```

`auth_user_id` is the actual authenticated subject; it can differ from the patient `owner_id`. `threads` contains each referenced original parent exactly once, sorted by UUID under C ordering. No unused descriptor is returned. A descriptor contains only `schema:'conversation.meal-thread.v1'`, `thread_id`, actual seven-field `parent_binding`, original strict v1 `original_command`, compact immutable `terminal_receipt|null`, and current read-only `continuation|null`. The latter exposes revision, actual question or null, and `fulfilled_by` child UUID or null. A historical question is never an assertion of current answerability.

Events retain their actual SQL identities, protocols, microsecond server clocks and opaque tokens:

| kind | Fields in addition to `event_id`, `at`, `kind`, `thread_id` |
| --- | --- |
| `report` | `status:pending\|registered\|not_recorded`, original mandatory `receipt|null`, `feedback|null` |
| `reply` | actual `child_binding`, immutable typed `body`, actual historical `question` |
| `reply_result` | actual `child_binding`, opaque `prepared_hash`, `status:needs_reply\|prepared`, historical `next_question|null` |
| `fulfillment` | actual `child_binding`, mandatory **conversation.meal-continuation-effect.v1** `receipt`, `feedback|null` |
| `edit` | actual parent-or-child `effect_binding`, sanitized 13-key **conversation.meal-edit-effect-public.v1** `receipt` |

The original parent remains `not_recorded` after child fulfillment. The child's receipt is never relabelled as v1, and no fabricated v1 command/body/provider proof is supplied to an old decoder. Edit receipt `input_hash` is the operation hash; the separate actual `effect_binding.input_hash` remains the original effect command hash. Persisted edit timestamps retain their original RFC3339 bytes; event, cursor, admission and observation timestamps use six fractional UTC digits. Reply/prepared/decision hashes are opaque SQL tokens; history cannot reconstruct a native immutable outbox wire from JSONB or recalculate its numeric lexical hash.

The exact synthetic cross-language packet, including all five event variants, is [conversation-thread-page-public.json](../../apps/admin/src/lib/mobile-api/__fixtures__/conversation-thread-page-public.json). It contains no real account, media, bearer, provider or health context.

## Read and privacy boundaries

The inert typed store calls the real `read_conversation_meal_journal_page_v2` RPC exactly once per explicit read. A transport failure never triggers an automatic second read or any write. Its complete closed graph is validated again at the service boundary, including actual owner/epoch, original parent hash, child protocol, question/reply shape, dependent receipts, clocks, descending timestamp + C event ID order, exact cursor, and no missing/duplicate/unused parent references. SQL remains the authority for persisted joins, original provenance and current epoch.

The service observes the real profile/current clinical policy before and after the page and optional feedback reads. It refuses a changed epoch, account mapping, stable clinical binding, policy, or contradictory clock. It never captures a meal source, initializes a day, interprets, calculates, seals feedback, registers food, advances XP/block progress or mutates a journal head.

For a genuine registered v1 report with an already sealed feedback reference, only the existing read-only historical presentation is used. The actual mandatory receipt and binding revalidate the result; the final policy and clock must match the surrounding fresh observations. Optional presentation failure leaves factual receipt success with `feedback:null`.

**Linked historical feedback remains explicitly null in this increment.** Root's separate linked feedback adapter must be qualified and integrated before it can provide the original six-block presentation under current policy. The reference alone does not complete those blocks. Current editable group, child Save/Undo authority, native v2 rendering and reply dispatch remain separate gates; a history page does not grant them.

No full private source/model/preparation, raw edit snapshot/before-image, clinical capture, tokens, credentials, signed URLs or wholesale original facts are public. Original owned text/caption/asset UUID remains only inside the strict parent command.

## Page budget and continuation

The complete public `data` packet is capped at 240,000 UTF-8 bytes. An event and a newly referenced descriptor are admitted atomically. On overflow, the whole event is left for the next page, unused descriptors are removed, and the cursor identifies the last included actual event. A first unrepresentable entry fails explicitly. There is no entry skip, byte truncation, reordering, fabricated clock, or reset retagging.

The v1 journal store/service and all SQL bodies remain byte-identical. This change adds one actual database RPC type and a thin version selector to the existing GET. It does not add a route, flag, environment or provider call. SQL local qualification belongs to the preceding migration evidence; this TypeScript increment adds unit/neighbor/type/lint evidence. Actual v2 HTTP/SDK, coherent BFF build/surface certification and native integration are root's subsequent gates.

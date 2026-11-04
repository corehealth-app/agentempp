# Linked continuation source ports

`createSupabaseConversationMealContinuationSourceFactory(db).fromRead(identity, rawRead)`
is synchronous and inert. Construction binds the actual SDK `rpc` method once;
`fromRead` revalidates the complete closed continuation read and requested identity
with the qualified reader decoder. It issues no read, capture, model, calculator,
admission, preparation, commit or reward operation. A real requested reply/source
is required, including when inspecting a historical reply.

The frozen result has exactly four fields:

- `command`: the original parent command and original input hash.
- `originalSource`: exact stored parent context, source hash and capture clock.
- `resolutionSource`: the real child source's `authority.context`,
  `authority.source_hash` and the child source's literal `captured_at`.
- `interpretation`: the unchanged original positive interpretation, including
  its original provider, source positions, references and hashes.

Both data contexts retain the parent's command identity and original evidence.
The adapter does not manufacture an interpretation/source belonging to the child,
replace an opaque hash, recapture the parent or reinterpret a reply as meal text.
`action: replay` on each capsule denotes reconstruction from already stored data;
it is not evidence that a capture RPC or another SQL operation was executed.
Clinical/context JSON remains private data, not current Auth/clinical authority.

The old source factory and the new adapter share the same nutrition-row, receipt
and audit implementation in `conversation-meal-source.ts`. The closed lookup
binding selects one of two actual RPCs:

| Capsule | RPC | Identifier argument |
| --- | --- | --- |
| Original | `read_conversation_meal_nutrition_source` | Original `p_command_id` |
| Fresh resolution | `read_conversation_meal_continuation_nutrition_source` | Actual child `p_reply_id` |

The reply identifier is independent of the parent command identity in the fresh
context. Owner, reply ID and exact cutoff are pinned before any lookup await.
The generated SDK does not yet name the separately versioned child RPC in this
checkout; a local exact-signature cast names only these two real RPCs. No
untyped general client, generated schema edit, live history or fallback is added.
The existing source module imports no continuation decoder or new runtime graph.

An explicit `sourceReader.read(kind, foodName)` may cause the SQL nutrition RPC to
persist its private durable lookup receipt; this is not a consumption registration
or reward. Construction itself does not call that RPC. Lookups retain the original
food-name string, exact literal `as_of`, nanosecond cutoff/30-day window, owner,
command/reply identity, closed nullable nutrition rows, 50/20 limits, ordering,
unique row IDs and verified-reference join constraints. NULL facts remain NULL.
Equivalent timestamp text does not replace the stored clock. The child-only
`event_conflict` refusal is added without broadening the old RPC's refusal list.

Receipt collectors start empty and separately collect every actual successful
lookup, including MISS and replay. Same-lookup ID/hash/rows must stay identical;
one receipt ID cannot represent two lookups. They do not load, fabricate or bless
prior preparation receipts. Audit sinks separately retain only detached,
owner-bound existing calculation-event intents in RAM, never `product_events`.
A lookup failure must stop the later calculation; callers must not continue with
only the already collected subset. SQL still checks the full receipt set and
current durable source before preparation/commit.

The later authenticated orchestrator must independently choose the eligible state,
recheck actual Auth/session/current SQL scope and use the original source for
semantic validation while supplying the **fresh resolution** reader/audit ports
to continuation calculation. The materializer already uses that fresh capture
clock for personal-correction/catalog resolution. Historical saved/superseded
bundles are still historical; successful reconstruction supplies no resubmission
or write permission. A sealed/conflicting/stale SQL lookup refuses without retry.

Local qualification uses mocked SDK callbacks and the existing byte-exact nine
SQL reader samples (SHA-256
`929a5e677fb9ef3c96a3f1714b6dd178fdc89c063ac2ad4b3341bdc9a53666c7`).
Seven actual snapshots with a requested child are reconstructed unchanged; two
without it are refused. Fixtures contain only previously qualified synthetic
private data. The legacy source suite is retained byte-for-byte. Actual SQL,
SDK/HTTP, provider/native QA, deployment and activation remain separate gates;
this leaf connects to none of them.

# Linked meal mutation bridge

`createSupabaseConversationMealContinuationWriter(db)` is a private service-only
adapter for the three real linked RPCs. It is dormant and exposes no HTTP route,
feature flag, current Auth observation, interpreter, calculator or public receipt.
The future authenticated orchestrator must establish the actual patient/session
scope before using it; supplied identifiers are preconditions, never authority.

Each structurally valid `admit`, `prepare` or `commit` that reaches the SDK issues
at most **one mutation RPC**, followed by exactly one
`read_conversation_meal_continuation` for the same detached owner,
parent, epoch, reply ID and reply input hash. Both SDK callbacks are pinned before
the first await. There is no retry loop, recapture, new UUID or fallback writer.
The separately exposed `read` is only that existing one-RPC read operation.

The mutation response's rich payload is intentionally discarded. A success label
does not prove a registration. `status: observed` requires the complete qualified
closed read decoder and the following operation-specific persisted fact:

| Operation | Required read witness |
| --- | --- |
| Admission | Actual requested reply, exact original typed body/hash and parent decision hash |
| Preparation | Actual immutable stored preparation equal to the entire submitted payload |
| Commit | Requested opaque prepared hash, actual saved child effect and the same parent's fulfillment by that child |

The read preserves the original negative parent decision, real child schema and
provider key, original/fresh sources, historical questions and server clocks.
No fake v1 child, reconstructed source hash or synthetic observation time is used.
Historical JSONB numeric-scale hashes remain opaque. Admission rebinds the actual
typed outbound intent with the existing qualified client canonicalizer; it does
not rebuild an encrypted retry from historical display JSON.

A lost, malformed or error mutation response still allows only the same read.
If the read proves the exact durable state, it can settle that operation. If it
fails, conflicts, remains merely admitted/prepared, or proves another result,
the result is `reconciliation_required`. This is uncertainty about the requested
effect, not a statement that the food was deleted or never saved. An explicit
later read can reconcile it. A current head or a ready preparation cannot prove
consumption. A closed SQL refusal is retained as a bounded diagnostic only when
the actual read does not prove the requested state; raw SDK errors never escape.

`parseConversationMealContinuationPreparationShape` reuses the existing closed
preparation schema and its 256 KiB compact-wire bound. It detaches/freeze-checks
JSON without executing getter or custom array prototype hooks. It validates
structure only. The actual SQL preparation/commit still validates the original
positive semantic source, question, answer chain, conversion witnesses, complete
nutrition lookup receipts, official current day/clinical authority and atomic
single fulfillment. SQL owns its JSONB serialization size bound as well.

Optional feedback or rendering never triggers another factual writer here.
There is no additional logging of bodies, health context or credentials. Returned
private state stays private and must pass the separately versioned public/current
policy presenter before any mobile response. History GET does not use this writer.

Unit tests use the existing byte-exact synthetic SQL read captures and controlled
SDK callbacks. They test uncertain responses, actual stored proof versus labels,
mutation-free reconciliation, owner/epoch/body/preparation mismatches, method and
argument mutation across awaits, unknown/protected data, standard JSON and caps.
The local SDK qualification subsequently exercised the real cached Supabase SDK,
PostgREST and PostgreSQL: quantity and meal-type clarification, actual original
and fresh nutrition-source lookups, persisted preparation and one factual commit.
Losing the commit response was reconciled with one read and no second commit.
The first attempt stopped on newly added SDK metadata before any SDK writes; the
separate reader compatibility fix was tested before the successful second run.

This qualification used synthetic records and controlled SQL preparation facts,
not the shared calculator/materializer orchestrator or a GoTrue patient session.
Its foreign-owner negative used a nonexistent patient, not another live QA
account. All test data and prior database state were verified restored. Public
HTTP, the native connected flow, source/calculator orchestration, public codecs,
deployment and installed TestFlight acceptance remain separate qualification
gates. This component alone does not complete the approved conversational app.

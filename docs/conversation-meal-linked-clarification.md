# Private linked meal clarification

This dormant SQL slice supports an original `missing_quantity` or
`meal_type_required` decision whose actual frozen interpreter result is a
positive reported meal. It introduces five service-only RPCs. It does not add
routes, public/native codecs, an interpreter invocation, label approval or a
new business target/default. The SQL is qualified on the exclusive owned local
retained PostgreSQL stack; public/SDK/native activation remains gated.

This first slice refuses a new reply outside the original report's civil date
or timezone. It never reassigns yesterday's meal to today, backdates a receipt
or initializes a fresh day before checking compatibility. Under the existing
owner lane, the original day/zone and exact owned processed media witness,
source evidence and source-unit list are checked before fresh authority
capture. Those original fences remain in force at preparation and commit;
media/owner locks prevent a new baseline from replacing the original facts.
Immutable completed replay still precedes freshness within the original epoch.

The reply body is closed:

```json
{
  "schema": "conversation.meal-clarification.v1",
  "expected_revision": 0,
  "question_key": "<opaque DB SHA256>",
  "answer": { "kind": "quantity", "food_index": 0, "amount": 100, "unit": "g" }
}
```

The alternate answer is `{ "kind": "meal_type", "meal_type": "almoco" }` with
the existing six-value meal enum. Owner, original parent command/hash/epoch,
opaque original decision hash and reply UUID are separate RPC context. The
body digest uses the qualified SQL JSONB decimal canonicalization, including
exponent expansion in callers; v1 command hashes are unchanged. Source,
question, preparation and historical decision hashes are opaque DB tokens.

`read_conversation_meal_continuation` returns the actual parent binding,
original capture/model/decision, current head and an optional explicitly bound
reply/preparation/effect. It is one STABLE read snapshot. It creates no head,
capture, daily authority, model attempt, progress row or receipt. The current
head is distinct from a previously accepted reply's immutable next question.

`admit_conversation_meal_reply` reuses the owner → epoch → command lane and
permanent UUID registry with the exact new pair
`conversation.clarification.v1` / `meal.clarify`. It checks the original parent
and server question, then captures fresh current resolution authority before
calculation. Admission shares the existing 10 fresh command IDs per current
epoch / rolling server 60 seconds quota. Existing child replay precedes
freshness/quota checks; invalidated UUIDs cannot be reused after reset.

The child capture explicitly separates immutable parent evidence references
from fresh clinical/day/catalog/correction/media authority. Its answer chain
contains actual accepted reply identities and the current typed answer. It
does not rewrite the parent source under its old hash or fabricate a child
provider attempt. Nutrition history hit/miss reads use the real captured
query helpers and child server cutoff; preparation and commit require the
complete receipt set and current rowset/source binding.

`prepare_conversation_meal_continuation` stores a new linked preparation
schema. Original materialization food positions must match the frozen model
exactly, all occurrences and calculation inputs must be covered, labels are
excluded, and every quantity answer has a conversion witness. Empty witness
input indexes are allowed only while the real materializer returned
`clarification_required`, which has no partial inputs. A materialized or ready
result requires real nonempty indexes and matching quantities. A pure local
projection reuses the existing resolved-meal numeric/catalog validator; that
v1 proof/projection is never persisted or used to call the old writer.

A `needs_reply` preparation atomically records the accepted answer and advances
one question. A `ready` preparation seals nutrition without advancing the head
until commit. Competing replies can be admitted/prepared; they cannot both
fulfill the same parent. Replay of a stored preparation returns its original
result with the separately read current head.

`commit_conversation_meal_continuation` reuses the qualified actual sequence:
confirmed pending proposal, `register_meal_atomic(..., false)`, exact whole
provider group/rounded facts/official targets verification, mandatory original
effect, unique parent fulfillment and head publication in one transaction.
The provider group is `conversation.clarification/<owner>/<parent>`. The new
receipt schema is `conversation.meal-continuation-effect.v1`; its command ID
and input hash belong to the child, and its explicit parent fields bind the
original immutable decision. It never writes an effect for the terminal parent.
Clock/day checks occur after locks and again after mandatory publication.

Original FX/feedback rules remain unchanged: optional original context capture
failure yields NULL enrichment and never another domain write; the generic
live-recapture feedback path sees the actual FX and remains fenced. New
versioned public feedback/edit adapters are activation gates. Existing v1
decoders must not be given a fake v1 receipt for a linked effect.

The old source/prepare/commit function bodies stay unchanged. An additive
pending trigger checks protocol equality only when a proposal explicitly
names a recognized conversation protocol and an actual owned registry ID.
Legacy pending rows without that linkage retain their behavior. The v1 journal
event helper filters the exact old protocol/kind in both command and edit
branches; linked replies have their own reader, not an incompatible v1 entry.

Reset cascades all personal source, answer, head, preparation, frozen health
and fulfillment content. Parent/child command tombstones and content-free
identity links survive reset; account deletion cascades them. New private
tables have RLS and no direct grants, including service_role. Only five public
trusted-backend wrappers are executable by service_role. A separate private
SECURITY DEFINER seam grants that role one boolean protocol-conflict lookup
for the INVOKER pending trigger; it does not expose raw registry data or grant
table access. Actual SET ROLE service_role DML/RPC tests cover that seam and
unlinked legacy metadata, alongside the old and new writers.

Reference conversion mirrors the existing exact-name quantity display policy,
including its actual Unicode normalization. The 17 golden reference cases
were generated by the actual TypeScript export, not by the new SQL function.
Twenty-six conversion goldens evaluate the approved JavaScript expression,
including explicit masses without extra rounding, fractional reference values
and subnormal/exponent cases. They passed actual PostgreSQL differential
execution, as did the independent typed TypeScript leaf's 44 literal cases.
Seven complete reply body hashes from the actual TypeScript binder also match
SQL canonicalization. The new grams helper pins `extra_float_digits=3`; caller
float serialization settings must not erase an explicit mass's binary64 result.
No fuzzy/brand/compound match, serving inference or arbitrary conversion is
added. Question names retain the literal original UTF16 slice, max160 units;
longer/unsupported targets are ineligible rather than truncated.

The SQL is a source/transaction/transport boundary, not an independent natural
language interpreter. The BFF must use the actual original frozen positive
model and materializer, apply a quantity overlay only at the actual missing
occurrence, preserve source groups, and choose a meal-type overlay only after
both explicit command type and the existing explicit-text detector are absent.
It must not infer old food facts again, suppress an actual label, invent
materialization slots or turn an unknown write response into another write.
Unknown outcomes require explicit reads of the same immutable identity.

Local qualification executed actual missing-RPC RED, five focused SQL files,
actual service-role DML/RPC and anon/authenticated denial, both stronger
isolation-level refusals, and 16 blocking/commit/rollback/reset races with
tracked actors reaped. Extra real-SQL cases cover complete nutrition hit/miss
receipts, an independent counter-only append, changed/deleted history,
mandatory effect/fulfillment/head failure rollback, optional NULL enrichment,
account deletion, and two missing quantities followed by a meal-type answer.
The partial materializer retained empty indexes until real input slots existed.

Eleven unchanged legacy neighbor SQL files passed, including v1/v2 receipts,
protected workout, journal, quota, writer and direct edit/undo. The exact empty
owned prototype was removed with RESTRICT and the original 209 table data,
709 function/ACL and 813 relation metadata fingerprints were asserted before
COMMIT. The final complete migration passed a fresh rollback rehearsal with
all original fingerprints restored, then a fresh installation and focused
SQL/race/differential checks. Earlier parse/name/precedence/float-format
failures and their causal repairs are preserved in external task evidence;
assertions were not weakened.

Final independent executed-evidence/diff review is required before commit.
The public continuation reader/result/native delivery protocol and actual
SDK path remain separate activation gates. This slice does not complete the
full conversational flow, does not prove GoTrue/HTTP/native behavior and has
not been deployed to production.

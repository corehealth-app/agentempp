# Private linked meal continuation service

This is an inert server composition, not an activated route or a distributed
Flow candidate. SQL owns the current owner/epoch/day, accepted answer chains,
source cutoffs, preparation and the parent's one fulfillment. No day
initialization, source recapture, interpreter, legacy executor or separate
XP/reward writer is added. Construction performs no I/O.

## Entry points and current scope

`createConversationMealContinuationService(db, dependencies)` exposes
`submit(auth, boundReply)` and read-only `reconcile(auth, identity)`.

`checkCurrentScope(scope)` is mandatory. The production caller must supply it
from the existing actual verified Auth/lease observation and revocation state.
Auth subject, patient, epoch, parent and reply IDs are preconditions; these IDs
never construct, renew or prove a lease. Auth subject may differ from patient.
The module does not authenticate a bearer or replace the existing Auth system.
The future route must preserve its actual Auth/entitlement/current-lease guards.

Auth, immutable reply data, dependencies, SDK methods and source ports are
captured before awaits. Checks run before and after asynchronous stages, before
writes and around each private nutrition lookup (which persists its receipt).
Cancellation or lost scope returns minimal reconciliation state, without a
saved receipt/question or another mutation. SQL current-state checks remain
mandatory; a callback or historical DTO alone does not create write authority.

## Durable state and recovery

Only a definite `absent` or `reply_conflict` read allows one admission. Failed
reads are never absence. The qualified writer uses one mutation RPC and one
closed reconciliation read; it never automatically repeats a POST. Uncertainty
stops without a new UUID, epoch, input hash, source or hidden rebase.

An already saved own child returns its immutable actual continuation effect.
An already ready child commits its stored opaque `prepared_hash` without
reinterpreting or recalculating. Full reads are qualified against the requested
identity, body and decision. Prepared state must equal the whole submitted
payload; saved state must retain the actual prepared hash and fulfillment proof.
SQL resolves concurrent winners. Mismatches stay reconcilable.

A `needs_reply` result uses only the **current head question**. Historical
`preparation.next_question` is not reused when the head advances. A different
child's fulfillment is held rather than returned as this child's receipt.
Read-only reconciliation cannot admit, calculate, prepare or commit; a
ready/admitted state requires an explicit subsequent resume.

## Stored answers and original evidence

The additive `materializeStoredConversationMealContinuation` accepts the actual
primitive SQL `answerChain`, with exact closed link/answer keys, lower-case
UUID/hash syntax, dense standard-prototype arrays, finite quantities, distinct
reply/question/food identities and at most one meal target. It does not create
historical questions, child-v1 commands or provider results.

Names and missing occurrences come from the original immutable model/source.
`convertConversationMealQuantity` reuses approved quantity factors. The shared
materializer still validates positive consumption, complete source coverage,
spans/media, whole names, confidence and original/fresh day/timezone before
queries. Explicit quantities cannot be overwritten. Ambiguous or expanded
compounds do not get fabricated one-to-one witnesses. Witnesses retain actual
answer values and map actual materialized indexes; empty indexes occur only
while another original quantity remains unresolved.

Both old materializer APIs and their 83 original tests are preserved. The
historical-question API still applies its exact question guard; both overlays
share the same qualification/candidate/witness core. The old production graph
does not import the large private continuation read decoder.

## Shared calculation

The admitted child reconstructs the original source/model and its separately
captured fresh resolution authority. Actual context/hash/capture timestamps and
the nutrition RPC's **real child ID** stay unchanged. Source data/ports are
compared to the complete read and pinned before another await. No parent capture
is relabeled fresh and no v1 child source is fabricated.

Meal selection uses the original explicit selection, then explicit original
text, then the actual typed meal answer. A conflict is held. Missing target
prepares the actual meal-type question before nutritional calculation. Missing
quantity prepares its actual next question. Other materialization reasons and
label-consent requirements remain held.

The default execution uses actual `calcMealMacros`, `consumed-meal-v1`,
`consumed.preparation.v1`, fresh nutrition/audit ports and the existing mobile
prepared-dish policy. Real input mapping, items, quantities, units, nutrients,
totals, annotations and every collected HIT/MISS receipt ID/hash populate the
new continuation preparation, without a fabricated v1 semantic proof.
Unknown/partial/unresolved nutrition stays held, with no zero-food or manual
calorie escape.

Historical SQL child/body/preparation hashes remain opaque when the SDK loses
numeric lexemes; normalized historical JSON is not rehashed. Initial typed
admission still binds its immutable client body via `bindConversationMealReply`.

## Feedback and evidence limits

Saved results explicitly contain `historicalFeedback: null` and
`feedbackGate: continuation_feedback_v2_unavailable`. The v1 feedback adapter
cannot be supplied invented child/effect identities. A separately qualified
continuation feedback-v2 adapter and public/current-policy presentation remain
required for the six-section candidate. Enrichment never repeats the writer.

Tests use the unchanged actual synthetic SQL fixture
`conversation-meal-continuation-read-sql.json`, SHA-256
`929a5e677fb9ef3c96a3f1714b6dd178fdc89c063ac2ad4b3341bdc9a53666c7`,
controlled SDK/read outcomes and actual materialization/calculation code.
The controlled default writer loses a commit response after simulated durable
state changes and proves one commit call plus its reconciliation read. Catalog,
HIT/MISS and saved outcomes in unit tests are controlled; they do not prove
actual Postgres, GoTrue, BFF HTTP, provider/model, native, staging, TestFlight or
production execution of this new orchestrator.

Connected shared-calculator orchestration, full feedback, actual route guards,
HTTP activation and native qualification remain separate gates. This slice
creates no infrastructure and performs no cloud or database operation.

# Complete private linked-continuation reader

`createSupabaseConversationMealContinuationReadStore(db).read(identity)` calls
only `read_conversation_meal_continuation`, exactly once per invocation. The
closed identity contains lowercase `ownerId`, `parentCommandId`,
`parentInputHash`, `epoch` and an optional paired `replyId`/`replyInputHash`.
Omit both optional fields or supply both nulls when no reply is requested.
The SDK callback and detached/frozen arguments are captured before awaiting.
There is no retry or response cache, including after a previous admitted read.

The exact SQL wire result is retained: `parent`, `head`, nullable `reply` and
`fulfillment`, and literal `observed_at`. Supported refusal actions are only
`absent`, `stale_epoch`, `input_conflict`, `ineligible`, `reply_conflict` and
`event_conflict`. Unknown or corrupt data is a redacted unavailable error.
Supabase envelope metadata is distinct from the closed private SQL JSON.

Parent decoding reuses the existing journal binding, stored-source, decision
receipt and interpretation validators. It verifies owner/command/input/epoch,
original source, semantic attempt/result links, positive complete interpretation
and the actual eligible `missing_quantity` or `meal_type_required` decision.
Original source wrappers, model/provider fields, references, source positions,
timestamp precision and opaque SQL source/result/decision tokens are preserved.
Stored-source validation projects only its existing declared helper fields;
the exact wire wrapper is checked first and returned unchanged.

Complete new versioned DTOs cover admitted, awaiting-reply, prepared, saved and
superseded replies; historical preparations/next questions; answer chains; and
fulfillment without a requested reply. Child/source/preparation/effect identities
are cross-bound to the original parent, actual reply, epoch and immutable answer
chain. Head revision, questions, accepted answers, winner and derived reply state
are checked together. If the requested reply targets the current head revision,
its body must match that exact current question (key, kind, target and unit).
Historical next questions remain historical when the head
has advanced; they are not rebased or returned as fresh permission.

Preparation decoding retains actual materialization/source positions, quantities,
witness coverage, complete real input mappings or empty mappings only for an
actual incomplete materialization. Each quantity witness is also checked against
`convertConversationMealQuantity(originalName, amount, unit)`, using the literal
original food occurrence and actual immutable answer. This reuses the approved
mass/reference conversion without reconstructing a historical question or key.
Explicit g/kg and reference rounding retain their existing operation order;
mismatched grams, factors and underflow are refused. The original typed-question
resolver keeps its exact question guards before reusing this pure conversion.
Resolved facts use the existing finite,
density, macro-mass, item coverage and decimal total consistency constraints;
no nutritional values are calculated or substituted. New effect receipts retain
`conversation.meal-continuation-effect.v1`, the real parent-based provider key,
day/timezone, registration/log identities and opaque version. No child is
relabeled as an original v1 source, provider result or effect. A historical
question that is not present in the read is not invented from natural language.

The new private whole-read JSON limit is 4 MiB UTF-8, with depth 64, exact keys,
finite numbers, valid Unicode and no getters, functions, sparse arrays or cycles.
Arrays must have exactly `Array.prototype`; custom, inherited-hook and null array
prototypes are refused before serialization without executing their hooks.
This separate bound accommodates repeated original/fresh contexts; it changes no
existing edit or public HTTP limit. The interpretation retains its existing helper bound; preparation has the
262,144-byte compact first bound, while the sealed SQL `jsonb::text` bound
remains authoritative. Over-budget reads fail without truncation or
silent field removal. Private payloads are not logged.

Historical child `input_hash` remains an opaque SQL token and is cross-bound to
the actual requested identity, source and answer chain; the reader does not
recompute it from a normalized SDK object. Root's read-only PostgreSQL probe
`T11-body-canonical-probe.log` observed that JSONB numbers `100` and `100.0` compare
equal but have distinct decimal canonical hashes, while both decode to JS `100`.
Original numeric lexemes are unavailable in this SDK result. This is a fidelity
limit, not cryptographic/body authentication by the reader. Fresh admission and
the authenticated orchestrator must bind the original typed body with the
qualified reply binder and expected header hash; SQL still validates its actual
stored body during preparation/commit. Source, preparation and other SQL opaque
tokens are likewise preserved rather than manufactured.

The byte-exact synthetic fixture
`__fixtures__/conversation-meal-continuation-read-sql.json` has SHA-256
`929a5e677fb9ef3c96a3f1714b6dd178fdc89c063ac2ad4b3341bdc9a53666c7`.
Its nine reads were captured from J-owned c3 synthetic fixtures through the real
SQL operations and rolled back. All media are null and no credentials, customer
data or URLs are included. The provenance artifact has SHA-256
`a803536c73f6fe006f0f9340b63c1bd6490faad1fae7db6d5235c54a1f1c2fca`;
driver/helper hashes and privacy guards were checked before copying. These are
SQL fixture origins, not HTTP, native or deployed-app qualification by this leaf.

A successful read is not Auth, current clinical/source authority, permission to
admit or resubmit, nutrition callbacks, a new preparation, a registration attempt
or reward. The actual authenticated orchestrator must independently supply and
recheck its revocable scope. This leaf creates no capture, model invocation,
calculation, writes, routes, migrations, deployment or feature activation.

# Private command meal writer adapter

`createSupabaseConversationMealWriter` is an inert BFF factory for the existing
service-only SQL protocol. It installs no route, flag or public writer and calls
no calculator, interpreter, clinical capture, daily initializer or direct table.

The four operations use the full `BoundConversationMealCommand`, revalidate its
original DTO/hash, detach inputs before the first await and retain the SDK method
captured by the constructor:

- `readPrepared(command)` reads the immutable source, resolved payload and factual
  receipt in the SQL function's single snapshot. An available result contains
  `binding`, nullable `source`, nullable `resolved`, and nullable `receipt`.
  Source-only and admitted-without-source are legitimate stages. A resolved
  payload requires source; a receipt requires both. Returned private data is
  detached and deeply frozen. The stored epoch must match the command binding.
- `readEffect(command)` reads only the mandatory original factual receipt.
- `prepare({command, source, resolved})` validates the closed resolved DTO and
  sends it unchanged to `prepare_conversation_meal`. Its `prepared`/`replay`
  result returns the opaque SQL `resolvedHash`.
- `commit({command, resolvedHash})` calls `commit_conversation_meal` once and
  decodes its `committed`/`replay` factual receipt. SQL returns the terminal
  winner before fresh context or submitted hash validation; the adapter preserves
  that behavior for an obsolete/malformed string hash on replay.

Read first in the caller: a factual receipt recovers the original outcome; an
already sealed resolved payload proceeds without another interpretation or
calculation. A lost prepare response is reconciled by explicit `readPrepared`;
a lost commit response by explicit `readEffect`/`readPrepared`. These operations
contain no automatic retries or fallback writes. Refusals retain their SQL action
codes. `event_conflict` and malformed/foreign responses fail closed; SQL busy and
serialization conflicts use redacted errors. No error includes raw SQL/provider
messages or connection details.

`ConversationMealStoredSource` is the bare stored source projection; the real
capture factory's result is a structural superset. Source hashes and resolved
hashes are opaque DB tokens, never hashes recomputed with JS numeric formatting.
The source parser retains the exact original command and private JSON, including
microsecond timestamp strings. Clinical JSON is a frozen source dependency,
never a current clinical authority or public presentation.

`parseConversationResolvedMeal(raw, {command, source})` mirrors the closed
`private.assert_conversation_resolved_meal` transport shape: explicit nullable
fields, whole source-unit coverage, complete generic input-index union, unique
canonical names, bounded quantities/nutrition, one-decimal totals and annotation
subsets. Cross-item index overlap is preserved because SQL permits it. Decimal
density/totals comparisons use exact finite JSON decimal values rather than IEEE
sum/product approximations. The payload byte bound accounts for JSONB separator
spaces and expanded exponents.

The decoder does **not** create a semantic proof. The trusted preparer must first
establish whole-source consumption and quantity/provenance coverage. Candidate
attachment/status is not resolved authority. SQL independently verifies current
epoch, full source/media/config/clinical/catalog bindings, actual food references
and the exact complete hit/miss nutrition receipt set before a new preparation
or commit. The adapter cannot validate those database facts locally.

`parseConversationMealEffectReceipt` is a scoped export of the existing feedback
store decoder. It binds owner, command, original input hash, exact provider key,
meal kind, civil date/timezone, unique log IDs and effect version without changing
the old feedback store behavior. The original receipt remains valid after C11
edits; its original log IDs do not describe the current editable generation.

Tests exercise the real codec and adapter across a controlled RPC boundary. No
PostgreSQL, model/provider request or route is started by this slice. Actual SDK
qualification belongs to the integrated caller's coordinated local batch; public
activation, full semantic preparation, current presentation and correction/Undo
are separate gates.

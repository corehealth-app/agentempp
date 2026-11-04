# Private conversation meal edit store

`conversation-meal-edit-contracts.ts` and `conversation-meal-edit-store.ts` provide the closed TypeScript boundary for the five service-only RPCs in `20261104060639_conversation_meal_direct_edit_undo.sql`. The reviewed SQL success contract includes its actual `command` binding on state reads, operation reads, committed writes and replays. The stored edit receipt remains `conversation.meal-edit-effect.v1`.

This increment has no route, service orchestration, native composition, provider call, calculation, generated database type change or activation. It does not migrate a database. Unit qualification uses synthetic rows and the real installed Supabase SDK with an intercepted fetch; that is not live PostgreSQL or public HTTP qualification.

## API and ownership

`createSupabaseConversationMealEditStore(db)` is inert. It captures the original RPC callback and exposes exactly:

| Method | RPC |
| --- | --- |
| `readState(binding)` | `read_conversation_meal_edit_state` |
| `readOperation({binding, operationId, input})` | `read_conversation_meal_edit_operation` |
| `save({...operation, expectedState, calculatedItems, nutritionMode, quantityChange, requestId})` | `commit_conversation_meal_item_edit` |
| `undoSave({...operation, expectedState, requestId})` | `undo_conversation_meal_item_edit` |
| `undoRegistration({...operation, expectedState, requestId})` | `undo_conversation_meal_registration` |

Each method calls one RPC once. The store never reads a table, retries a write, calculates food, initializes a day, admits a command or invokes the legacy writer. SQL itself composes the existing C11 mutation for Save. Unknown transport/decoding outcomes remain errors; future orchestration must reconcile through `readOperation`, never infer absence or automatically repeat a mutation.

`ConversationMealEditBinding` contains patient `ownerId`, original `commandId`, original `inputHash`, immutable `epoch`, and optionally the genuine `originalCommand`. Authentication belongs to the future service: an Auth subject is not a patient ID. Every success validates the actual SQL command binding against all four expected fields. No epoch, source text or Auth identity is synthesized. Refusal envelopes are closed and limited to the SQL-declared actions. SQL `55P03` and `40001` become redacted busy/conflict errors; other SQL/provider messages never escape.

`bindConversationMealEdit` validates and detaches the operation UUID and exact original intent, computes the SQL-compatible canonical SHA-256 input hash (including decimal expansion of JSON exponent numbers), and freezes the resulting value before any await. Food names are not silently normalized; the SQL name/control/UTF-16 and ASCII edge-space constraints apply. Quantities are in grams. Client macros, new nutrition-label approval, extra keys and unknown intent versions are refused. Calculation/provenance fields are separate private server arguments, not part of the original input identity.

## Current state and historical facts

State reads return `binding`, `originalReceipt`, `revision`, nullable `currentState`, `lineageCompatible`, nullable `lastOperation`, `registrationUndoExpiresAt` and `observedAt`. A null current state can represent a removed or incompatible live group; no original logs are recreated as current state.

The CAS includes the exact full PostgreSQL user context, snapshot and ordered log rows. Known persisted columns are required and typed. Additional SQL row columns remain in the detached private JSON and participate in CAS. Timestamp strings, including submillisecond precision and offsets, nullable targets, media metadata and reserved JSON keys are preserved. No `Date` object or reduced public DTO replaces a row. Non-JSON values, accessors, sparse/custom arrays, invalid Unicode and payloads exceeding 1 MiB are refused, rather than silently dropped or coerced. The parser supplies no nutritional or clinical authority.

When a genuine original bound command is available, the existing original FX receipt decoder is reused. Otherwise the original FX envelope is independently closed and checked for patient/command/input hash, exact provider key, distinct original log IDs and local date/timezone consistency. It never constructs an invented command source to call a decoder.

Edit receipts are distinct from original FX and legacy C11 receipts. They bind operation UUID/hash, intent kind, next revision, finite removed/new physical IDs, snapshot and server timestamps. Save has its exact five-minute interval; UndoSave restores one beforeimage under a different operation UUID and cannot be revision one. Fresh committed responses must match the submitted private snapshot and group; replay preserves the original winner even when ancillary fresh preparation is null or stale. Ancillary preparation is validated as detached transport JSON before the call, leaving SQL replay-first business guards intact.

Original FX and v1/v2 feedback remain immutable historical facts. The new edit receipt/current state belongs to a separate correction timeline. A future presentation service must use actual current clinical policy and the existing historical presentation guard; returning private CAS or raw original feedback publicly is not authorized by this store.

## Remaining integration gates

The future service must authenticate, enforce patient and epoch preconditions, read an existing operation before fresh preparation, reuse the actual C11 calculation helper for Save, and make a single bounded reconciliation read after an unknown write outcome. Undo must use the SQL-held beforeimage, never reverse rounded quantities. SQL still owns current revision, complete CAS, reset, open day and deadline authority. Live SDK/PostgreSQL qualification, service/HTTP/native integration and public activation remain separate gates.

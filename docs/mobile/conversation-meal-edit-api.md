# Conversation meal edit API (dormant)

Additive public adapters over the qualified private command edit store and C11 preparer. The original command/FX/feedback is immutable. No server flag, provider, SQL migration, app factory or distribution is activated here.

## Routes and scope

All three paths use the existing mobile Auth and entitlement wrapper before handler/service construction. They share `conversationMealCommandsEnabled`: explicit `MOBILE_CONVERSATION_COMMANDS_ENABLED=true` plus the established current-clinical staging target only; default off and no protected-legacy fallback.

| Method | Path | Meaning |
| --- | --- | --- |
| GET | `/api/mobile/v1/conversation/meal-commands/{commandId}/meal` | Current factual group and advisory edit/Undo availability |
| POST | `/api/mobile/v1/conversation/meal-commands/{commandId}/edits/{operationId}` | One direct Save, Undo Save or original registration Undo |
| POST | `/api/mobile/v1/conversation/meal-commands/{commandId}/edits/{operationId}/reconcile` | Read-only reconciliation with the exact original edit input |

Mandatory headers on all routes:

```text
X-Conversation-Owner: original canonical patient UUID
X-Conversation-Epoch: original command epoch UUID
X-Conversation-Input-Hash: original report SHA256
```

Both POSTs additionally require `Idempotency-Key: cmedit1:{operationId}` and the exact original closed `conversation.meal-edit.v1` JSON body, maximum 16,384 UTF-8 bytes. Command/operation UUIDs and hashes are lowercase. The original patient is a precondition, never identity authority; a valid different patient gets 409 before constructing the service. The Auth subject can differ from the patient ID. Body duplicate keys, authority fields, nonfinite numbers and malformed identities are rejected; malformed JSON remains 400, oversized body 413, invalid edit input 422.

Responses use the existing `{ data, meta: { api_version: "v1", request_id } }` envelope, `Cache-Control: no-store`, `Vary: Authorization`, and `X-Conversation-Protocol: meal-command-v1`. These are command-owned SQL operations; no second legacy idempotency writer wraps them. POST mutations must not receive an automatic 401 replay.

## Closed public schemas

Exact cross-language examples live in `apps/admin/src/lib/mobile-api/__fixtures__/conversation-meal-edit-public.json`. They include current/null groups, milk and whey references, saved and absent outcomes, all three mutation receipt kinds, and the PostgreSQL decimal-hash case. These are synthetic contract fixtures, not customer records or proof of device/provider execution.

The group has exactly these fourteen keys:

```text
schema: conversation.meal-group.v1
owner_id, command_id, input_hash (original), epoch
admitted_at, observed_at (actual SQL clock)
original_receipt: exact existing conversation.meal-effect.v1
revision: integer 0..2147483647
lineage_compatible: boolean
current: null or { expected_version, local_date, timezone, day_closed, items }
last_operation: null or PublicEffect below
registration_undo_expires_at
 actions: { save, undo_registration, undo_save }
```

`current.timezone` is nullable; `expected_version` is the opaque version of the ENTIRE private C11 state, not a hash of this projection. Current item rows have exactly `id`, `food_name`, `quantity_g`, `quantity_display`, `kcal`, `protein_g`, `carbs_g`, `fat_g`, `source`, `consumed_at`, `meal_type`. Quantities/nutrients/source may be null when the persisted fact is unavailable; unknown never becomes zero. All numbers must be finite; there are 1–30 unique current item IDs. `current:null` means no valid complete current group, which can mean empty OR changed/inconsistent state. It does not independently prove deletion or zero consumption.

Each action is exactly `{ allowed: true }` or `{ allowed: false, reason }`. Closed reasons: `current_group_unavailable`, `day_closed`, `not_current_day`, `invalid_timezone`, `revision_exhausted`, `version_changed`, `undo_expired`, `no_save_to_undo`.

The saved ACK has exactly:

```text
schema: conversation.meal-edit-result.v1
status: saved
owner_id, command_id, input_hash (ORIGINAL report), epoch
receipt: PublicEffect
```

`PublicEffect` has exactly thirteen keys:

```text
schema: conversation.meal-edit-effect-public.v1
owner_id, command_id, operation_id, input_hash (OPERATION hash)
kind: saved | save_undone | registration_undone
revision, applied_at, undo_expires_at, target_operation_id
removed_item_ids, new_item_ids, next_record_id
```

This whitelists the actual qualified immutable SQL operation receipt and omits its `snapshot` ENTIRELY. No full private rows, Auth linkage, URLs, before/after images, clinical target, day balance, percentage or block is returned. The two input hashes above have different purposes; never compare the operation receipt hash with the original report hash. Validate the actual binding and operation identity/intent before accepting the ACK.

A reconciled absence has exactly eight keys: `schema: conversation.meal-edit-state.v1`, `status: absent`, `owner_id`, `command_id`, `input_hash` (original), `epoch`, `operation_id`, `operation_input_hash`. No reason or effect receipt is attached.

## Current eligibility and quantities

Availability uses the actual SQL observation clock and CURRENT private context timezone, never device time or original report timezone. Current group, row/snapshot local dates, open day and a revision capable of advancing are required for fresh actions. SQL checks them again under locks at write/commit time.

Save allows a client-reviewed fresh version after an external generation, even if `lineage_compatible=false`. Undo requires exact lineage. Original registration Undo requires revision zero and the original five-minute deadline. Undo Save targets only the latest successful Save, using that receipt's deadline and current revision. Equality at the deadline is expired, including microsecond precision. Undo of Undo/redo is not introduced. Replay of an already saved operation precedes fresh date/expiry/revision checks, preserving its exact original result.

`quantity_display` is always present and is either null or the existing closed `{ unit: mL|unit|scoop, grams_per_unit, reference_id, estimated:true }`. `mobileQuantityFields` supplies exact-name allowlisted references. Canonical storage/request remains grams. Milk206g displays approximately200mL using1.03g/mL; 200g must not silently become200mL. Generic whey30g displays approximately1measure; it is an editable reference, not a guarantee about a brand dose. Unknown brands/mixtures retain grams. Existing Swift quantity helpers preserve the original unit of authorship and validate metadata against the food name. Same-item canonical quantities still require representable two-decimal grams; never silently round/rewrite an original intent or multiply a persisted quantity on read.

## Read-only recovery and presentation

An execute response projects the actual private result directly and needs no follow-up group, Today or educational read. A failed refresh cannot revoke the saved ACK or trigger another write. Current panel values come from refreshed existing readers, while original historical feedback remains separate and immutable.

Reconciliation has no HTTP or database idempotency-response cache: the same key/body must observe a later winner after an earlier absent result. Reconciliation calls `readOperation` once with original body/identity. A winner produces the same ACK with no group read, calculation, admission, provider or write. An absent operation needs one additional `readState` to prove the actual original command binding: absence itself carries no binding in the existing SQL union. Thus winner path=1RPC, absent path=2RPC, no retries. A reset/change between those reads cannot be retagged into a new absent command. Absence is a read observation, not permission for automatic resubmission with a new operation UUID/version/body. Unknown writes remain explicit reconciliation, and known SQL refusals remain non-success.

The existing `conversation.meal-edit.v1` OP hash uses PostgreSQL canonical JSON decimal scalars. For example `1e-7` hashes as decimal `0.0000001`, while the submitted numeric intent remains unchanged. The fixture provides an independently frozen expected hash. The hash input excludes newly calculated macros, current state, time and request ID.

There is deliberately no `current_policy` field or numeric guidance in these DTOs. Existing guarded Today/current-clinical readers and the scoped historical six-section wrapper supply those separately. Do not expose a raw private edit snapshot, reuse historical targets as current, or treat factual food correction as forbidden merely because guidance is paused. Exercise does not increase available food; edit/Undo never credits XP or a long-term block.

## Qualification boundaries

Focused tests cover closed projection/no leakage, null facts, exact-name mL/scoop references, current timezone/midnight/open day, microsecond deadlines/revision/lineage, Auth subject distinct from patient, immutable ACK despite failed refresh, one-read winner/two-read absent reconciliation, original input/hash binding, scope changes and route Auth/entitlement/default-off/byte bounds.

The parent integration retains the actual five-RPC connected QA and owns the coherent full Admin/BFF surface/build gates after edit and history routes are combined. No DB/cloud, real provider, device, TestFlight or release activation is performed by this source slice.

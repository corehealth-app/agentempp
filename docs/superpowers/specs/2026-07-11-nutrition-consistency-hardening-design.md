# Nutrition Consistency Hardening

**Date:** 2026-07-11  
**Status:** Approved  
**Scope:** Functional correctness for meal interpretation, editing, confirmation,
storage, messaging, and audited historical repair.

## Confirmed Incidents

Production evidence showed that an explicit calorie value from an older meal
could be attached to the first item of a newer meal. This produced the same
70 kcal override in unrelated foods for multiple active users. A quantity-only
edit then kept that override as an absolute total, so reducing grams did not
reduce calories.

Additional confirmed defects found during the functional sweep:

- `chocolate ao leite` is treated as liquid/dairy by keyword order and display
  unit rules.
- A confirmed pending is recalculated instead of persisting the exact proposal
  the patient approved.
- Weak history substring matches can outrank an exact canonical food entry.
- Exact duplicate items emitted by the LLM are summed instead of collapsed.
- Meal logs and daily snapshot totals are updated in separate operations.
- `proposal_msg_id` receives a provider text ID although the column references
  `messages.id` (UUID).
- General outbound messages lose per-message provider IDs after sending.
- The weekly food database gap worker uses an unsupported `.catch` call on a
  Supabase query builder.
- Prompt language normalization ignores active rules stored as `pt`.

## Design

### 1. Explicit Nutrition Evidence

An explicit calorie override is accepted only when it is proven by the current
patient turn, or by the immediately preceding turn when the current turn is a
short confirmation. The pending stores the value together with source message
provenance. No orphan value from arbitrary conversation history may attach to a
new food item.

### 2. Stable Pending Proposals

The pending proposal is the approval boundary. It stores resolved quantities,
macros, source, density, and optional explicit patient calories.

- A quantity-only edit scales kcal and macros from the previous approved
  density.
- A food identity or preparation edit resolves nutrition again.
- Confirmation writes the exact resolved values displayed in the pending.
- Explicit patient kcal remain absolute only while the quantity is unchanged;
  changing quantity scales the value unless the patient supplies a new total.

### 3. Deterministic Food Resolution

Resolution priority is:

1. current-turn explicit patient value;
2. exact canonical food database match;
3. exact compatible trusted user history;
4. guarded fuzzy canonical/history match;
5. deterministic category fallback.

Preparation and form modifiers such as powdered/liquid, skin/no skin,
fried/grilled, skim/whole, and fresh/derived must be compatible. Display unit
and macro category rules use whole food semantics, so chocolate containing the
word `leite` remains a solid sweet unless the name describes a drink.

### 4. Idempotency and Atomic Storage

Exact duplicate items within one tool call are collapsed. Different quantities
are summed only when current-turn evidence indicates multiple portions.

A transactional database function performs replacement, meal-log insertion,
and daily snapshot recomputation together. A retry cannot update the snapshot
without the corresponding rows.

### 5. Message Persistence

Interactive output is inserted into `messages` first; its UUID is then stored in
`pending_registrations.proposal_msg_id`. Every WhatsApp chunk is persisted with
its own provider ID and delivery result. Delivery failures remain retryable
without executing the nutrition write twice.

### 6. Monitoring and Historical Repair

The food-gap worker is repaired and compares recent logged foods with canonical
coverage using supported Supabase queries. New invariant events detect:

- explicit kcal without current-turn evidence;
- pending quantity changes that keep an unscaled total;
- displayed-versus-persisted nutrition drift;
- snapshot-versus-log drift;
- weak history matches blocked by modifier incompatibility.

Historical repair is dry-run first, covers all active users, masks PII, and only
updates rows with deterministic evidence. It recalculates affected daily
snapshots and progress in the same transaction. Ambiguous rows remain listed
for review and are not changed automatically.

## Delivery Sequence

1. Nutrition evidence, quantity edits, units, and deterministic resolution.
2. Frozen pending confirmation and exact duplicate handling.
3. Transactional meal persistence.
4. Interactive/outbound message identity and delivery persistence.
5. Food-gap worker, prompt language normalization, and invariant telemetry.
6. Full regression suite, historical dry-run, reviewed apply, and production
   deployment only after explicit authorization.

## Verification

Each phase is test-driven and committed independently. Required checks include
package tests, repository typecheck, lint/build where relevant, SQL pre/post
conditions, and a final production-safe dry-run. No deployment is part of this
implementation phase.

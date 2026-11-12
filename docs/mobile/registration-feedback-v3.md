# Dormant registration feedback v3

This is an additive backend receipt contract for the approved conversational meal/activity flow. It does not activate an HTTP route, capability, intake classifier, native screen, history presentation, activity correction or Undo. The workout core and these receipts must not be published alone to installed clients. A compatible negotiated Flow/history presentation and consumer remain activation gates. V1/v2 stored JSON, education, phrase steps and replay stay unchanged.

## Public facts

`@mpp/agent/registration-feedback-v3` exports the closed `registration.feedback.v3` parser, pure preparation and six-section renderer (`saved`, `items`, `summary`, `day`, `block`, `education`). The education text remains the reviewed `registration.education.v1` catalog; there is no model, calorie formula or registration/reward writer in this leaf.

The v2 registration facts remain structurally recognizable, including nullable individual workout estimates. A v3 day adds:

```ts
exercise_kcal: number | null
exercise_energy:
  | { status: 'available' }
  | { status: 'unavailable'; reason: 'unknown_workout_energy' | 'source_unavailable' }
```

Known zero is available and distinct from unknown. A saved false coverage witness or an actual NULL workout withholds the day exercise number. Missing original coverage is `source_unavailable`; it never inherits a new SQL default or later correction. Individual known energy can coexist with unavailable whole-day energy. An individual NULL activity cannot prove complete day exercise.

Food/protein facts remain independently available. Targets, percentages and food budget are independently nullable. Unknown exercise does not increase the food budget, invent a target, suppress proven intake, or change gain/maintenance/clinical policy. Incomplete assessment retains proven intake while withholding unsupported goals. A clinical pause keeps the registration and masks goals. Long-term block facts use only existing consolidated `user_progress`; neither registration nor feedback credits a block. There is no new daily-balance field or formula in this receipt.

`day: null` means the optional same-day factual enrichment could not be proved. Unknown exercise alone is not a reason to discard the entire day.

## Canonical identity and immutable versions

| Origin | Registration ID | Original source |
| --- | --- | --- |
| `pending_registration` | Actual confirmed pending UUID | Existing mobile capture, or exact frozen conversational meal context |
| `conversation_workout` | Actual workout command UUID | Existing own `conversation.workout.v1` effect, preparation and frozen feedback context |

The same UUID in these two real origins denotes distinct events. A conversational meal uses its real pending registration identity; it does not acquire a second origin just because it has a command. Direct and linked conversational meals share the existing meal effects and receipt authority. The private source codec never accepts an invented UI-v1 proof or treats client intent as performed evidence.

The canonical key is `(user_id, origin, registration_id)`. The first sealed version wins. A private unique claim records IDs and version only. Backfill copies existing unambiguous v1/v2 metadata without rewriting payloads, hashes, steps, timestamps or cursor state. Overlapping versions, foreign/orphan parent ownership, mismatched command linkage or ambiguous meal-effect registration bindings abort before creating new objects; there is no silent winner selection.

The claim is inserted in the same statement/transaction as each v1/v2/v3 metadata INSERT. Its unique index arbitrates even when an older RR/serializable snapshot cannot see a concurrent winner. There is no blanket new isolation restriction on v1: legitimate fresh v1 calls and exact replay remain supported in RR/serializable. A concurrent invisible winner can require a transaction retry (`40001`); competing physical inserts at READ COMMITTED reject the extra claim (`23505`). Normal callers read the canonical winner before attempting an insert. The existing fresh v2 READ COMMITTED restriction is unchanged; new v3 capture/commit also require it. Receipt-only read has no new isolation restriction.

The old v1/v2 read boundaries, including the frozen meal receipt helper, receive pinned additive v3 fences. A late old writer cannot create a second version or draw new phrases after a v3 winner. New v3 read/commit return an existing v1/v2 body exactly, before new capture, preparation or payload validation. V3 never upgrades or reseals an old receipt.

## Journal3 compatibility

`20261112025635_conversation_journal_feedback_v3.sql` gives journal3 a private
reference reader for genuine canonical3 meal receipts. It reads the existing
canonical winner, verifies the registration and meal-command identities, and
returns only its version/registration reference. Missing reciprocal claims,
changed bindings and unavailable winners refuse; they do not become an absent
legacy receipt. Canonical1/2 references retain the exact old reader.

Journal-only child/entry helpers reuse the qualified v2 factual and lineage
validators with only that reference port changed. The migration checks their
source hashes and changes only journal3's two call sites. Old receipt fences,
old journal1/2 paths, registration writers and stored receipt bodies stay
unchanged. The new helpers have no client or service-role execution grants;
the existing trusted journal RPC remains the entry point.

This allows a new meal, its later edit and its immutable original feedback to
coexist in the paginated history. A history read never generates feedback,
re-registers consumption or grants another reward. SQL qualification includes
mixed canonical1/2/3 pages, neutral intake lineage, linked fulfillment,
post-edit reads, pagination, identity refusal and unchanged legacy validators.
Native reload and distribution remain separate qualification gates.

## SQL and source proof

The three service-only RPCs are:

- `read_mobile_registration_feedback_v3(uuid, uuid, text)`
- `capture_mobile_registration_feedback_v3(uuid, uuid, text)`
- `commit_mobile_registration_feedback_v3(uuid, uuid, text, jsonb, jsonb)`

The third argument is the closed origin. Only the backend supplies owner/identity. New tables remain private with RLS and no direct service/client grants. The RPCs assert trusted backend access. They do not create registrations, run the daily closer, award XP, mutate progress or advance phrase cursors.

Ordinary pending capture uses the existing protected source producer plus the full owned snapshot workout set, actual coverage and clinical source. Commit acquires the config/owner/workouts lanes, recaptures and compares a stable complete source binding. Marker-only, source, clinical, snapshot, progress and full-workout changes invalidate a fresh preparation. Observation clocks are excluded only through the existing closed clinical binding; no mutable data is cached across requests.

Conversational meal and workout originals already store immutable feedback contexts. V3 uses those contexts, not edited live logs or a current snapshot substituted into history. Meal capture includes exact command ID, epoch, input hash and mandatory effect receipt; no generic live recapture can relabel it. Workout capture reuses the actual source/preparation/effect/strength decoders and its own provenance. Owner, date, original IDs, numbers and epoch remain bound. Missing pre-DDL coverage stays unavailable after NULL-to-zero repair or physical live-row removal. Current-day enrichment may prove unchanged food independently while withholding original exercise; changed optional clinical enrichment yields original facts without an invented day. Current clinical masking of a public historical presentation is a separate activation gate.

Fresh v3 feedback passes its own closed day/source validator. It does not construct a numeric v2 day with exercise zero to reuse the old decoder. Existing pure quantity, numeric, percentage, clinical-policy and reviewed education helpers remain version pinned.

The v3 payload follows its owned pending/effect parent cascades. Reset scrubs command health payloads; workout permanent command IDs and the corresponding claim remain as metadata tombstones to prevent resealing. Pending claims follow the already existing pending-parent deletion lifecycle. No queue, extra outbox, global cache or clinical ledger is added.

## Migration operational bounds

The migration prelocks parent tables, then old receipt tables, with `SHARE ROW EXCLUSIVE NOWAIT` and a five-second local lock timeout. It copies metadata before adding/validating parent FKs, avoiding per-row FK waits behind a legacy writer holding a user row and waiting on DDL. It aborts safely on an active conflicting table writer. The claim trigger takes only the already established owner row before the unique claim; it adds no reverse workouts lock to v1.

Backfill/validation cost is linear in existing receipt rows plus meal-effect ambiguity checks, with unique-key lookups for parents. The owned baseline has zero receipts; local qualification does not estimate production row counts, lock duration or index size. Actual target counts and writer activity must be checked in the guarded deployment manifest before any rollout. No remote or production qualification is claimed here.

## BFF leaf and failure behavior

`registration-feedback-v3-service.ts` is dormant. Its scope dependency is mandatory: each physical RPC and optional clinical await checks fresh actual Auth/admin/current patient/epoch scope before and after the await. Identity, method references and response values are detached before the next await. Optional clinical RPCs and lazy query dispatches share the same sticky scope latch; the scoped client exposes only the existing read RPC/table/filter paths and withholds table-write and unknown-RPC capabilities. Revocation is sticky: a swallowed SDK error cannot permit another RPC or return success after scope loss.

The ensure path reads canonical first, captures/prepares once, commits once, and acknowledges by an independent canonical read. A lost commit response permits one read reconciliation using the same immutable identity. It never repeats registration, preparation, source capture or commit. Optional metadata failure leaves the durable registration untouched. No default route, runtime factory or admission effect is installed.

## Qualification and limits

The retained local PostgreSQL suite installs the concrete workout and v3 source inside a single rollback wrapper. `fixtures/mobile_registration_feedback_v3_precoverage.sql` must run before the workout migration so real old writer bodies produce an original snapshot without the new marker; no fixture mutates an immutable original or fabricates a historical default. The suite covers real known/NULL workout receipts, legitimate equal identities, old-first v1/v2 and frozen command replay, repair zero, field availability, protected/incomplete policy, atomic rollback, ACL and reset/parent deletion. New actual SQL goldens are decoded by the TS source and wire parsers; old literal goldens remain unchanged.

`fixtures/mobile_registration_feedback_v3_claim_concurrency.py` proves the physical arbitration boundary with two connections, an exact trigger body, exact INSERT statements extracted from all three writers and a faithful unique index in a predeclared temporary synthetic arena. Only schema identifiers and bounded candidate adapters change. It includes an unguarded negative control, stale RR/serializable snapshots, both directions of version contention, same-version retry and distinct origins. It is not a complete RPC, HTTP, public/native or end-to-end concurrency proof. Complete real v1 writers are separately qualified in RR/serializable rollback transactions, including exact replay and the prior v2 isolation boundary. The arena is removed with exact object/dependency checks and global fingerprints.

The next public Flow/history wrapper must explicitly version its support for original v3 receipts and preserve current clinical presentation proof. `conversation.feedback-presentation.v1` is unchanged and must never be relabelled to carry v3. Activity intake, edit/Undo, combined journal/history, native/public integration and whole-flow latency acceptance remain open.

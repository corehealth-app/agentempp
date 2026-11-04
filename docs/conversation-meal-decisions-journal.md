# Durable non-registration and private journal pages

This additive SQL slice supplies three service-only RPCs. It adds no public
route, provider invocation, calculation, daily initialization or reward write.
The authenticated backend binds the patient owner; an Auth user UUID is not
assumed to equal that patient UUID. Only READ COMMITTED is accepted.

| RPC | Arguments |
| --- | --- |
| `seal_conversation_meal_decision` | `p_user_id uuid, p_command_id uuid, p_expected_epoch uuid, p_expected_input_hash text, p_expected_source_hash text, p_attempt_id uuid, p_expected_result_hash text, p_decision jsonb` |
| `read_conversation_meal_decision` | `p_user_id uuid, p_command_id uuid, p_expected_epoch uuid, p_expected_input_hash text` |
| `read_conversation_meal_journal_page` | `p_user_id uuid, p_expected_epoch uuid, p_limit integer DEFAULT 10, p_cursor jsonb DEFAULT NULL` |

The closed decision input has exactly `schema: conversation.meal-decision.v1`,
`status: not_recorded`, `reason` matching `[a-z_]{1,80}`, and `food_indexes`.
Indexes are unique integers from zero through 29, at most 30, and must exist
in the actual completed interpretation's foods. An empty set can describe a
whole-command refusal. The backend chooses this reason; SQL does not turn a
model hypothesis into semantic or nutrition authority. A completed positive
interpretation can still reach a later materialization, nutrition-label or
meal-type refusal in the existing registration service.

Sealing takes the existing owner/workout, epoch and command locks. The original
epoch/tombstone and command hash are checked before any replay. The source must
be the actual immutable capture, and the attempt and result hash must identify
the stored completed `conversation.meal-interpreter.v1` result. Started, unknown
or terminal-error attempts cannot manufacture a decision. No caller-supplied
source packet or model result is accepted. Live clinical/day/catalog state is
not recaptured to recover a completed interpretation's non-registration.

The first decision is immutable. Its exact JSONB input replays; changed input
returns `decision_conflict`. Existing resolved preparation or an effect returns
`resolved_conflict`. Additive insertion fences prevent a sealed decision from
being followed by resolved preparation or an effect, using the writers' existing
common owner lane. The qualified writer bodies remain unchanged. A commit with
no resolved meal still returns its existing `resolved_required` refusal before
any domain writer.

Sealing returns `sealed` or `replay`, and reading returns `available`, with the
actual original `command` binding and a flat immutable `decision` receipt. That
receipt contains the four input fields plus `owner_id`, `command_id`, `epoch`,
`input_hash`, `source_hash`, `attempt_id`, `semantic_result_hash`, `decision_hash`
and `sealed_at`. The decision hash is an opaque database canonical-JSON token;
clients must not substitute a JavaScript serialization hash. The remaining
seal actions are `absent`, `stale_epoch`, `input_conflict`, `source_required`,
`source_conflict`, `semantic_required`, `semantic_conflict`, `resolved_conflict`
and `event_conflict`. Reads can return `absent`, `stale_epoch`, `input_conflict`
or `event_conflict`. Invalid new decision shapes raise SQLSTATE 22023.

The page RPC is STABLE and side-effect free. It returns `available`, actual
`owner_id` and `epoch`, `items`, `has_more` and nullable `next_cursor`. Limits
are one through 25; explicit SQL NULL is invalid. The cursor is exactly
`{at, id}`, using UTC with six fractional digits and an actual owned event
anchor in the current epoch. Invalid, foreign or reset anchors return
`cursor_conflict`; an inactive/missing patient returns `absent`, and an absent
or mismatched epoch returns `stale_epoch` without creating authority.

Events sort by descending server event time and then event ID in C collation.
Command IDs are `command/<command UUID>` and keep the original `admitted_at`
even when pending becomes terminal. Edit IDs are
`edit/<command UUID>/<operation UUID>` and use actual `applied_at`: an operation
UUID can legitimately repeat across commands. A cursor identifies the last
returned event; an extra lookahead determines `has_more` under the same SQL
snapshot. Newer concurrent events belong to a subsequent first-page refresh.

Command events have exactly `event_id`, `at`, `kind: command`, `command`,
original `source_input`, `status`, nullable `receipt`, and nullable `decision`.
Status is `pending`, `registered` or `not_recorded`; pending never acknowledges
a registration. Edit events have exactly `event_id`, `at`, `kind: edit`,
`command` and the actual operation `receipt`. Receipt fields, including the
nested edit snapshot, have explicit factual whitelists. Original FX receipts
remain original after C11 edits or compensation. Current edit eligibility and
current visible clinical policy are separate projections.

The page does not expose source captures, clinical context, original FX facts,
feedback context, before/after audit groups, full C11 state, processing results,
backend credentials or generated media URLs. The original strict command may
contain patient-entered text/caption or an owned asset UUID. This is a private
backend contract: the public DTO, current-policy projection and response byte
cap are separate gates. Reading history never ACKs an outbox command.

Reset cascades through the actual source capture and semantic result, erasing
decision content and journal payloads while preserving invalidated permanent
command identities. Account deletion removes owned identities as before. RLS,
no direct table grants, immutable-content guards and service-only RPC ACLs apply.

Local qualification used the existing owned native PostgreSQL stack: decision,
pagination, prerequisites, ACL/RLS and both stronger-isolation refusals; twelve
real blocking cases cover first winners, rollback, opposing preparation/reset
directions and a page snapshot across a concurrently committed decision. Eleven
neighbor SQL files passed. A fresh migration rollback and exact reinstall
preserved existing rows/functions/triggers/relation metadata and restored all
eleven new function bodies, ACLs, columns, constraints, triggers and indexes.
All fixtures are synthetic and rolled back or explicitly cleaned. No provider,
cloud deployment or public-flow qualification is claimed by these SQL checks.

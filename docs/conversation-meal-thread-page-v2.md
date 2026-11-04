# Compact linked meal thread page v2 (locally qualified)

This additive migration introduces one private, service-only read RPC. It was
qualified on the exact retained synthetic native PostgreSQL stack after an
explicit exclusive ownership handover. This is local SQL evidence, without an
HTTP/native route, feature activation, model call or cloud resource. Public
projection, six-section feedback, native integration and distribution remain
separate gates.

## Wire and boundaries

`public.read_conversation_meal_journal_page_v2(p_user_id uuid,
p_expected_epoch uuid, p_limit integer DEFAULT 10, p_cursor jsonb DEFAULT NULL)`
returns `action:available`, `schema:conversation.journal-page-private.v2`, the
actual owner/epoch, canonical microsecond `observed_at`, `threads`, `items`,
`has_more` and nullable `next_cursor`. Refusals are exactly `absent`,
`stale_epoch`, `cursor_conflict` or `event_conflict`. Invalid arguments or stronger
isolation raise a static SQLSTATE 22023 error. The RPC accepts only READ COMMITTED.

The external implementation contract is
`PUBLIC-THREAD-V2-CONTRACT.json`, revision 2, SHA256
`5c1340006fd114ed9bba289838a17fa5131f7251ba82b0221147037959ced43a`.
Its revision 1 is preserved. Revision 2 only clarifies that existing edit receipt
timestamps retain their actual RFC3339 strings and microsecond precision;
event/cursor/binding/observation clocks use exactly six fractional digits in UTC.

A thread descriptor is returned exactly once per referenced original report,
sorted by parent UUID text with C collation. It contains only its thread ID,
actual original report binding, original strict command, sanitized immutable
terminal decision and nullable current continuation head. The head exposes
revision/question/fulfilled_by, without the answer chain or model/source body.
Its latest accepted answer is checked against the actual immutable preparation
and, when fulfilled, the actual child effect. Historical reply and next questions
are closed and compared in full to the qualified question function using the
actual immutable original parent and exact accepted answer-chain prefix. A
private parent-proof capsule is cached once per selected parent, but only its
compact descriptor is ever serialized into threads. A displayed head is historical
read evidence, never current-day/source permission to answer.

## Immutable event identities

| Kind | Event ID | Authoritative clock |
| --- | --- | --- |
| report | `command/<parent>` | Original report admission |
| reply | `reply/<parent>/<reply>` | Actual child admission |
| reply_result | `reply-result/<parent>/<reply>` | Immutable preparation time |
| fulfillment | `fulfillment/<parent>/<reply>` | Actual child FX commit |
| edit | `edit/<effect-command>/<operation>` | Actual edit application |

Report status comes from the actual original FX/decision. A parent negative
remains not_recorded after its child fulfills; the child is represented by its
own actual `conversation.meal-continuation-effect.v1` receipt, protocol and
parent-based provider key. Neither a v1 parent effect nor a child provider
attempt is fabricated. Edits expose exactly the existing sanitized thirteen
public effect fields, including actual operation hash/IDs, without snapshot.
Operation UUIDs may repeat across different effect commands.

A partial preparation has its own reply_result event so a question committed
after a previously paged admission is still discoverable. The result exposes
only child binding, opaque prepared hash, needs_reply/prepared status and its
stored historical next question. A later head/fulfillment does not rewrite that
preparation or make its historical question currently answerable. Ready is
presented as prepared, never as a saved-food ACK.

## Set selection, pagination and privacy

Limit is 1..25 with default ten. One bounded relation selects limit+1 event keys
ordered by `(at DESC, event_id COLLATE C DESC)`. The returned prefix determines
the distinct descriptors and child DTOs. Immutable evidence may be inspected
internally once per distinct parent/child; complete 2..4 MiB private reader
packets are not emitted per event or fetched through N extra RPCs.

The private cursor is exactly `{at,id}` with canonical UTC microseconds and the
actual owned current-epoch anchor. Continuation is a strict exclusive tuple.
When more events exist, the cursor is the last included event; otherwise it is
null. Every returned event has exactly one referenced descriptor; no unused
thread descriptors are included. Current head updates do not rekey events.
An independent snapshot is used for each request, rather than a promised
cross-request frozen database snapshot.

Feedback is only null or a two-field reference `{schema,registration_id}` to an
already sealed and validated first v1/v2 winner. The existing pure read helper
verifies original proposal/source linkage and reciprocal winner. There is no
raw feedback/clinical body, source recapture or receipt sealing on GET. A
reference is a temporary integration seam; it does not implement the six Flow
feedback sections or authorize unguarded current guidance.

No complete original/fresh source context, interpretation/provider metadata,
private preparation, original_facts, audit before/after group, private snapshot,
current editable group, raw Auth link or generated/signed URL is returned.
The strict original command can retain its owned asset UUID/caption. Feedback,
source, preparation and operation hashes remain their actual stored tokens;
historical numeric JSONB is never rehashed by a transport to reconstruct an
original child retry body.

The RPC checks trusted backend, active patient and current expected epoch under
one STABLE SQL snapshot. Its public wrapper must independently bind actual Auth
subject/patient/epoch and fresh current-policy observations. No new table/RLS
policy/grant is introduced; helpers have no service/anon/authenticated EXECUTE,
and only the public wrapper grants service_role EXECUTE. Two additive indexes
support preparation/effect event clocks. Five reused critical helper source
hashes are pinned in the migration preflight; no old function body is replaced.

## Preserved behavior and remaining gates

The existing v1 journal helper and decoder stay byte-identical, including both
exact v1/report filters. New replies do not enter its closed union. Original
FX/feedback, source/media/day fences, correction lineage, finite Undo clocks,
reset/account cascade and unrelated pending/workout/XP behavior are unchanged.
Current-group/Save/Undo support for a child remains a separate typed binding and
actual SDK gate. A timeline receipt cannot prove current physical rows or grant
an action; a compensation must remain an immutable separate event.

The public v2 projection must retain the 240000 UTF-8 data budget including
unique descriptors/cursor. It must add whole event+new descriptor together,
stop before the next oversized event and continue from the last included key,
without skipping. The private reader does not manufacture a public Auth
identity, promise that budget after a future projection, ACK an encrypted queue
entry or restore original request bytes from JSONB. Initial source tests do not
claim these future public/native gates have run.

## Executed local qualification

Tests were written before production source. The bounded lexical guard first
failed for a missing migration and passed after creation; Python AST and scoped
diff checks also passed. The migration filename came from the pinned cached
CLI's migration new command, without a dependency download or stack operation.
The lexical guard is not a PostgreSQL parser or runtime qualification substitute.

Real PostgreSQL then confirmed missing-RPC RED, whole-file ROLLBACK rehearsal
and exact restoration of the full baseline, followed by one fresh installation.
The production file remained byte-identical throughout qualification (SHA256
`56880416f445f001f616344920a16aa10f9fa9082b68cbf12ed3ee0df27662ab`).
The actual primary page test passed 37 assertions. The guard test passed 19
counted assertions plus actual SET ROLE service_role/anon/authenticated and
REPEATABLE READ/SERIALIZABLE checks. All ten INSERT-only historical-question and
next-question attacks passed, including extra private keys and changed name,
allowed units and reference after a different child fulfills.

The first guard execution stopped on a test-helper-only error: one generic
trigger expression accessed NEW.next_question while running under the reply
row type. The failed transaction rolled back. Independent source/data/catalog
and zero-row reads proved no fixture or test trigger remained. The test was
repaired only by branching on table name before accessing a record field;
assertions and production bytes were unchanged. After a targeted independent
review, execution resumed at the corrected guard file. Missing-RPC RED,
rehearsal, installation and the already passing primary test were not repeated.
The failure, source delta and executed reconciliation are retained externally.

Eleven unchanged SQL neighbors passed: v1 journal, linked core/writer/original
source/actual role, command journal, decisions, edit/Undo, frozen command
feedback, generic v2 receipt and protected-workout feedback. Eight real MVCC
cases covered partial preparation, fulfillment, reset and an original-command
C11 edit with both commit and rollback. Reads completed while the writer's
transaction remained open, exposing a coherent prior snapshot; later reads
observed the committed outcome or exact rollback state. The harness asserted
the first mutation actually succeeded and independently reaped every owned
actor while deleting only its explicit synthetic owner/Auth rows.

All 214 baseline table/data fingerprints, every old 735 function definition,
ACL/owner/config and all 824 existing relation/trigger/constraint fingerprints
remained exact. Only eight new function bodies and two new indexes were added;
all eight installed prosrc values matched the final whole-file source. The
final count was 743 functions and 826 relations. All 139 owner UUID columns,
users/Auth identities/sessions/tokens/audit, Storage/media, command IDs/sources,
FX and other postgres clients were zero. Backend TCP remained null, cron off
and pg_net batch size zero. No stack start/stop/bootstrap, old migration replay,
cloud/provider/HTTP/native call, reward or production deployment was performed
by this SQL increment.

The public 240000-byte projection, current-policy observations, child-aware
editable group and native transport remain separate implementation/activation
gates. A private page decode is not current action authority, a food ACK or full
Flow completion. Original v1/linked effects and immutable historical feedback
continue to use their existing contracts.

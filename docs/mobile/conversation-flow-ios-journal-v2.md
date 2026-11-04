# Native Flow linked history read/render

The existing real `FlowConversationSessionSource` selects journal v2 explicitly.
This does not select a new command protocol: original reports still use the
unchanged `conversation.command.v1` body and `cmsg1` identity. The existing
bundled candidate configuration remains default OFF, with no new Info.plist,
flag, launch argument, endpoint or permission value. The default
`FlowConversationModel.open` and `MobileConversationHistoryRepository.journal`
remain v1, including their old fixtures and decoder.

## Actual read path

`MobileConversationHistoryRepository.threadJournal` calls the existing GET with
explicit `version=2`, limit and an unchanged opaque cursor. The distinct typed
`.threadJournal` header policy permits only that version/query shape. It keeps
the original Auth lease, actual patient owner and server epoch preconditions.
The repository checks status 200, actual Auth subject (which can differ from
patient), patient, epoch and observation clock before returning its distinct
owned read capability. Current command Context and lease are checked before and
after transport and again inside the visible patient publication gate.

`ConversationThreadPageSnapshot` closes all nine page keys, descriptors and five
event variants. It validates six-fraction UTC clocks for events, admission and
observation; persisted edit clocks keep their original valid RFC3339 spelling.
All referenced parents must appear exactly once, sorted by C UUID order, with
no unused descriptor. Parent command/hash/decision and genuine child protocol,
binding, question/reply, fulfillment and sanitized edit relationships are
checked. Event order is descending timestamp then C event ID. The cursor's
closed public anchor must match the last event and original patient/epoch;
its exact opaque bytes are retained, never renewed or used as write permission.

The complete data is limited to 240,000 UTF-8 bytes before invalid optional
feedback can be discarded. The authenticated transport also enforces the
262,144-byte envelope/body limit and closed outer data/meta shape. Unknown
private facts, sources, snapshots and extra keys cannot enter factual DTOs.
Malformed optional feedback is withheld while an otherwise valid factual
receipt remains available.

## Model and timeline

The actual model loads, resets and paginates v2. It preserves server event IDs,
deduplicates local original reports by genuine parent ID/hash, rejects duplicate
or out-of-order append and fences superseded callbacks. Immutable event cache
pins reject changed reply bodies, prepared tokens or edits on a later reset;
an original pending report can become terminal once. These RAM consistency
digests are not SQL, command-input, source or preparation hashes. All actual
SQL reply/prepared/decision hashes remain opaque and unchanged. Pins survive a
same-identity scope refresh and are cleared on a different patient/epoch/Auth
identity or teardown. No historical JSONB is used to recreate original outbox
wire bytes or rehash a historical child input.

The transcript presents report, reply, preparation result, fulfillment and edit
as distinct events. The original `not_recorded` report remains negative after
its genuine linked child registers a meal. Historical questions and answers
are labelled as historical; an observed current head is read-only. One active
question uses the existing composer gate and explicit empty independent-report
action. Typing an answer cannot silently create a fresh unlinked copied meal.
The original raw report and encrypted identity stay preserved.

A genuine registered v1 parent can use the existing saved-meal/current-group
surface. A `conversation.meal-continuation-effect.v1` receipt remains a separate
type with its real child/parent/provider/epoch binding. It is never relabelled
as v1 or passed to the old group/editor with a substituted parent UUID. Current
child meal details and editing remain explicitly unavailable until that actual
protocol and SDK path qualify.

Optional six-section feedback is decoded using the existing closed historical
presentation and bound to the actual parent or child receipt under the current
model's real session generation/patient/epoch. The backend supplies current
clinical masking. Native code does not regenerate food numbers, targets,
education or clinical authority. Linked lineage/current-group qualification is
pending, so its immutable original feedback is explicitly historical and
collapsible rather than presented as current edited facts.

## Preservation and remaining gates

Reading v2 history never ACKs food or an edit, removes ciphertext, calculates,
captures a source, changes a journal head, registers a meal or advances rewards.
In particular it does not adapt v2 reads into the old v1 delivery or edit-ACK
capability. Terminal original intents can therefore remain encrypted after
remote deduplication. The existing outbox capacity is 50; a separate fully bound
v2 terminal-delivery capability is still needed for retention closeout. No
unknown intent is silently evicted to make room.

The exact synthetic public projector golden is copied without changes from
`conversation-thread-page-public.json`, SHA-256
`f45316e815835eeea27854ee1abbd8f847f7176a4de1c46c2ff6787ff01cb925`.
It contains data only; native HTTP unit tests add controlled normal metadata,
not an alleged real HTTP capture. Foundation URLProtocol/model tests are
controlled transport evidence. Focused simulator compilation/render probes
are separate from actual authenticated native/backend E2E.

The coherent synthetic SDK pieces in
`ConversationLinkedFeedbackSDKFixtures.json` have SHA-256
`831b9d10b1c20a60869d0d394df9c5e3a0d71c3648c2fd38245b04fad9cf87bc`.
Root independently qualified their actual GoTrue/shared-calculation/SQL and
feedback provenance. They are not a full journal page. Tests decode only their
actual parent/child bindings, linked receipt and masked presentation; no missing
event, parent source, Auth subject or page is fabricated. The genuine
`registration_id` is distinct from the child command UUID and remains distinct
through binding and six-section rendering. A closed receipt never requires
those different identities to be equal. This proof still does not establish an
authenticated native/server request or a public journal page with child feedback.

Reply dispatch, durable child outbox/ACK, actual child current-group/Save/Undo,
compatible backend deployment, native authenticated E2E and bundled activation
remain separate gates. No speculative reply request, cloud/provider call,
dependency, device upload or release activation is included here.

# Command-backed Flow candidate on iOS

This increment is source-only. `FlowConversationModel.open` uses the actual
session lifecycle, encrypted report outbox and authenticated command controller.
`AppShellView` accepts an explicitly supplied model/capture capability only at
its existing Debug conversational-preview root. No release factory, launch flag,
backend capability or route is activated. With no injection the previous root
is unchanged. The existing `.flowChat` destination and “Conversas anteriores”
secondary entry preserve the old conversation; the journal covers new commands.

## Source and composition

- Text is the original UTF-16 source, with optional explicit meal selection.
  The model freezes a prepared UUID/body before enqueue and keeps it across
  local persistence uncertainty. A newer unsent draft survives the older reply.
- Photo/camera/gallery/recording/audio import reuse `MealMediaStager`,
  `MealCameraCover` and `MealAudioRecorderView`. The picker-open patient/epoch
  identity stays fixed through preparation. No old meal-draft extractor runs.
- `ConversationMealMediaService` uses the actual media repository with the
  original patient header, original Auth lease and no mutation 401 replay.
  Upload tickets remain in RAM. The exact media command is encrypted BEFORE
  requesting processing, so a cold reopen resumes its original asset/UUID/body.
  Processing first reads the asset; already-processing work only polls. Unknown
  processing outcomes have no automatic POST retry. Explicit resume reuses its
  stable processing key. No media URL, transcript, calorie or success is invented.
- Logout revokes grants synchronously, cancels owned work and clears RAM/local
  staged handles. An uncertain or queued remote asset is never deleted on logout.

## Journal and terminal delivery

`MobileConversationHistoryRepository` applies the existing scoped HTTP transport
and closed protocol headers/envelope. Every read checks the original lease and
revocable Auth/patient/epoch observation before and after awaiting the network.
The journal uses opaque cursors, explicit pages, server descending order and
cross-page order/duplicate guards. The view reverses that order for a chronological
conversation. It does not create a local timestamp or offset cursor.

Remote/local command copies deduplicate only by actual command UUID and original
hash inside the same patient/epoch. A journal read alone never acknowledges a
report. A saved remote item with unresolved local delivery offers GET confirmation
synchronization, rather than blindly POSTing or fabricating another intent.

A durable `not_recorded` state is not a saved meal. Its original source/identity
remains unchanged. A linked answer is unavailable in this protocol: a short answer
such as “30g” cannot silently clone or rewrite the report. An explicit independent
report action opens an empty composer and retains the old decision in history.

The separate `closeTerminalDelivery` controller capability accepts only the actual
owned journal adapter's read and the same current observation grant. Its closed
negative receipt, original command, ticket, body/hash, patient/epoch and time
binding must match. Only dispatched non-reset work can close. Removal is atomic
under the lifecycle gate and file lock. No saved-food event or reward is emitted.
A synchronous in-session delivered-ID guard is recorded after successful rename,
before leaving that gate, to reject a late prepared enqueue. Storage failure
preserves the previous ciphertext and installs no guard. Unknown/unproven,
legacy, reset or foreign entries are preserved; there is no eviction policy.

## Current facts and historical presentation

A fresh owned `/meal` read supplies only current consumed food facts, quantity
references, revision and server actions. Null current data or nutrition remains
unavailable. Original six-section feedback stays separate in a historical
disclosure. The original receipt and numbers never change after an edit.
The actual QA fixture demonstrates original whey30g alongside current whey35g;
current calories/macros come from the group, not from recalculation or old feedback.

Only the factual saved event advances the model's saved-effect revision. The
candidate shell then invalidates/loads the official Today and History readers
under its existing owner gate. Their independent failure does not revoke the
ACK or repeat a write. The existing quantity draft helper preserves authored
mL/scoop conversions without rounding the original mass or inventing calories,
candidate attribution, operation UUIDs or eligibility.

## Qualification and remaining activation gates

Portable tests exercise actual controller/URLProtocol/disk paths, exact TypeScript
and actual local HTTP fixtures, cold restart, account/epoch changes, unknown
outcomes, owned media, terminal cleanup, paging and current-vs-historical facts.
The iOS renderer probe and focused native app compile are separate gates. Portable
macOS fixture setup uses private synthetic staging files because the host refuses
the iOS data-protection write option; iOS tests retain the real protected stager.
No production staging code is weakened.

This is not native-to-real-server, provider, physical-device or staging E2E proof.
Save/Undo controls remain uncomposed until the distinct durable edit outbox,
actual edit controller/reconciliation, server CAS and final native binding are
qualified. Linked clarification, workout commands and broader planned features
remain separate. No old writer fallback, dummy successful save, model-generated
nutrition, new paid environment or production deployment is introduced.

Two additional product gates from independent review remain before activation:

- A new, unchanged registration must show all six sections immediately in its
  primary response. The current dormant disclosure must be limited to edited or
  unavailable lineage after actual group/receipt/facts prove whether it changed;
  revision0 alone is insufficient.
- A prepared intent after persistence uncertainty must be visibly locked or
  separated from a new draft. Changes to only the meal selector or a media
  caption/type must not silently send the old frozen intent as the edited one.
  Type-only and caption/type failure-path RED tests are required in that slice.

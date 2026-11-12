# Negotiated intake media provenance

This is the server half of the conversational media bridge. It does not activate
photo/audio in the distributed iOS app. Ordinary-photo upload, processing,
retention qualification and the native codec/capture flow remain separate gates.

## Compatibility and authority

An optional `X-Conversation-Media-Provenance: 1` request header selects the new
response projection for POST `/api/mobile/v1/conversation/intakes` and GET
`/api/mobile/v1/conversation/intakes/:id`. Missing means legacy. Other values,
including duplicate combined values, are rejected with 422. The existing
`X-Conversation-Protocol: intake-v1`, immutable `conversation.intake.v1` body,
input hash and `cintake1:<uuid>` idempotency key are unchanged.

Negotiation is not permission. `MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED=true`
must be independently configured on the trusted server, together with the exact
staging guards and the existing intake, meal and workout capabilities. Default is
OFF. Legacy requests continue to hold media before typed dispatch even if the
trusted flag is enabled; negotiated requests also hold when the flag is off.

The durable SQL selection remains authoritative. After validating its genuine
`conversation.intake-selection.v2` and complete parent/asset/child bindings, the
driver calls the existing typed meal/workout service. The selected response is
`conversation.intake-result.v2`, adding only the validated `media_projection` to
its public selection. The private child input, media bytes, analysis result,
transcript, provider URLs and clinical captures are not projected. Text and
non-selected outcomes keep the existing v1 shapes.

The response echoes `X-Conversation-Media-Provenance: 1` for opted-in requests,
adds the header to `Vary`, and preserves the existing private/no-store transport.
A native client must explicitly support this codec and match the original media
ticket, owner, epoch, source hash, asset and child hash before accepting a factual
ACK. A selected or pending response alone is never a saved registration.

## Revocation and recovery

Once media capability has been used, its withdrawal closes the same request-owned
scope. Checks surround asynchronous observations and typed child RPCs, including
prepared-effect recovery. Re-enabling configuration cannot revive that request.
Existing fresh Auth, patient mapping, non-admin, clinical epoch and policy checks
are preserved. Refusal never falls back to the older media user actions.

GET only reads the existing selection/typed result. It does not classify,
capture, claim, seal or submit. Unknown POST outcomes use the existing read-only
reconciliation path rather than submitting again. The same original command is
preserved across retries; no new registration or reward is inferred from a read.

## Verification boundary

Tests use captured local PostgreSQL selections for meal photos, activity audio
and not-performed audio/equipment-photo cases. They verify legacy holds,
negotiation, default-off capability, fresh dispatch, revocation and real typed
facade RPC fencing. Controlled external Auth/database/provider ports are not a
connected upload/worker/native acceptance test. Keep this capability disabled
until those remaining gates pass; do not claim build 17 supports photo or audio.

## Native response bridge (capture still pending)

The new iOS codec selects provenance only for an original neutral `.media`
POST/reconciliation ticket. Text, session, journal, legacy meal and unrelated
requests emit no media negotiation. Every successful selected-media transport
requires the exact echo and `Cache-Control: no-store`, including held v1 outcomes.
An unsolicited response header cannot select the decoder.

The v2 selected envelope requires a closed projection: parent intake/input hash,
epoch, source/decision hashes, valid claim UUID, original media owner/asset,
compatible media kind, bounded processing clocks and processing-hash format, and
the actual child input hash. Ticket matching checks the original asset as well as
the existing owner/epoch/intake/hash binding. A v1 selected media envelope cannot
be upgraded to a saved ACK. A genuine typed saved receipt remains mandatory;
non-performed, question, held and pending outcomes do not become registrations.

This native protocol bridge does not add capture controls or enable generic
`conversation_photo`. Upload→worker→ordinary-photo lineage/retention, visible
capture/composer, connected multimodal registration, cold journal/edit/panel
agreement and release qualification remain required before shipping modalities.

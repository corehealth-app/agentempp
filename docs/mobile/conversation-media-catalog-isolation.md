# Conversational media catalog isolation

Status: **local catalog/upload/processing, factual capture and independent disposal qualified; not activated or deployed**. The full
conversational delivery and R105-REVIEW-1 remain open.

Old immutable ordinary-media handlers select `public.media_assets`. Existing
metadata and clinical paths must remain usable; a new guard only in a new BFF
does not constrain an old handler or an already-started Storage operation.

New assets can instead be created in `private.conversation_media_assets_v2`.
Their keys are `conversation-v2/<owner UUID>/<asset UUID>.<extension>` in the
existing private `meal-photos` and `audio-notes` buckets. The validated legacy
path constraint rejects this prefix, so no corresponding public catalog row
can expose the new path to an old lookup, expiry scan or account-purge scan.
The migration refuses an absent, unvalidated or changed legacy constraint.
No bucket, Storage policy or legacy row is changed by the foundation.

The pure `packages/core/src/conversation-media-namespace.ts` codec checks exact version,
owner, asset, kind, bucket, MIME, extension and size together. All twelve current
ordinary MIME types and existing size limits are retained. Valid shape is not
authentication, signing authority or a successful disposal.

## Catalog capabilities

`create_conversation_media_asset_v2(user, asset, kind, mime, bytes, context, hash)`
creates one source for an active owner, or returns the exact existing source
for an identical request. A retry nonce does not create another asset. Changed
source data or a conflicting opaque identity is refused. The database derives
the bucket, key and ordinary 30-day retention; callers cannot submit them.

`get_conversation_media_asset_v2(user, asset, request_hash)` accepts exactly one
lookup selector and returns only the owner's source. Both RPCs are backend-only
with fixed search paths. Neither client roles nor `service_role` can directly
read or mutate either private table. Source identity, caption, retention origin
and request hash are immutable.

An independent opaque-ID fence prevents catalog collisions. Its unique index
arbitrates real concurrent transactions, including an older repeatable-read
snapshot. Public catalog reservations disappear with their existing rows, so
clinical metadata receives no additional retention. Only the new ordinary
version-2 identity remains reserved after its private catalog disappears,
consistent with the approved minimal technical-marker policy. No old catalog
data is backfilled. Account deletion cannot erase a live private source through
a foreign-key cascade; the qualified disposal/purge integration must resolve it.

## Private upload and processing

`@mpp/core/conversation-media` exposes the pure namespace codecs and closed
RPC adapter. It creates no SDK client, credentials, provider or route. The API
constructor uses the existing server client and accepts only a trusted HTTPS
Storage origin. The installed SDK signs the exact disjoint key without upsert;
the issuer reuses the existing URL/expiry parser without changing its body.

Before signing, `prepare_conversation_media_upload_v2` persists an independent
obligation and ticket. `register_conversation_media_upload_v2` records the actual
provider expiry even after the catalog or owner has disappeared. An uncertain
signing response remains unresolved; neither elapsed time nor a missing catalog
is evidence of successful removal. Tickets contain no URL, token or payload.
`complete_conversation_media_upload_v2` checks registered preparation and exact
observed size/MIME/etag. Repetition preserves the first upload timestamp.

Processing uses an owner-bound request and a five-minute database claim token.
Only one live claim is admitted. A caller receiving `busy` must defer/retry after
`retry_at`; it must not acknowledge the job as completed. Expired claims obtain
new tokens. Completion/failure compare the current token and refuse late results
after discard or replacement. Uncertain completion is not followed by a failure
write or an automatic second model request.

The private processor checks the canonical key, downloaded byte count, signature
and readable audio duration (at most 180 seconds) before a model request. It
rechecks the current source after download. Photos retain only the existing
nonclinical image-result contract; audio retains the bounded transcription
fields, without raw provider diagnostics. Processing alone records no consumed
meal, workout or reward. No default provider factory or event is activated here.

## Explicit factual lineage

`admit_conversation_private_media_intake_v2` creates an immutable version-2
binding in the same transaction as a genuinely new intake. It retains the
existing owner/epoch lane, input protocol/hash, quota and reserved-child logic.
An existing admission without this binding remains version 1. It cannot be
upgraded, including after a legacy catalog row is removed and its opaque ID
is used by a new private source. No request probes one catalog and falls back
to the other. Reset/account input scrubbing cascades to this intake binding;
independent upload/disposal obligations retain their separate lifecycle.

Five fingerprinted source/projection/continuation readers receive narrowly
bound read substitutions. The common record is reconstructed only in memory
for the existing SQL readers; there is no public row or purpose retag. Private
reads refuse expired sources and closed independent obligations even if their
catalog status still says `processed`. The captured source and selection never
contain the private Storage key. Existing atomic domain writers and numerical
rules remain unchanged.

Only new private sources carry `catalog_version: 2` through neutral capture,
selection, typed source and interpretation. Legacy payloads omit the field
unchanged. Server codecs require matching source/projection versions and reject
missing/mismatched/unknown versions. They remain decoders, not permission gates.
The new private intake port is an explicit trusted composition option; it keeps
the existing per-call Auth/owner/epoch observer and never retries/falls back to
legacy admission. It is **not wired into the default runtime**. Activation must
select it only for a proved version-2 source; existing public-media drafts and
receipts keep their original admission path.

R168 qualifies 47 real SQL checks, including the original meal/workout atomic
writers and receipt replay. Meal resolution in that writer test uses the
existing synthetic resolved-result fixture; this is not automatic nutritional
resolution evidence. Five real concurrent admission schedules preserve the
first committed catalog version through commit/rollback and old/new callers.
Actual local SQL goldens exercise server codecs. The installed-SDK integration
continues from upload/processing through the scoped intake store, sealed typed
child and interpretation/writer source decoders, refusing a withdrawn epoch
before another physical RPC. Storage/model boundaries are synthetic; personal
Auth, connected Storage and native delivery remain separate gates.

Seven current SQL neighboring suites pass. Two older expiry/account-purge
fixtures still expect unenrolled legacy media to be deleted; both fail exactly
the same with the pre-R168 reader hashes restored. The approved retention-cutover
suite, which preserves those old rows, passes. Neither legacy fixture nor the
retention policy is weakened to make that mismatch green.

The source/build guards pin the whole new codec bodies and reverse only the
declared version additions. All five historical source hashes and four complete
compiled-body hashes are reconstructed exactly, with executable-tampering and
version-substitution refusal retained. Unknown SQL reader source is refused
before migration; its local rollback preserves the complete function fingerprint.

## Foundation qualification and remaining integration

R166 qualifies 34 namespace cases, 65 real SQL catalog/permission cases and six
real concurrent schedules. A repeatable-snapshot collision was first reproduced
with both catalogs claiming the same ID; the unique fence then refused the old
insertion. A separate regression first found extended legacy reservation
retention, then verified removal with the old catalog row. The changed-path
preflight was likewise tested before and after its guard.

The unchanged ordinary-media SQL qualifications (151 assertions) and actual
reevaluation-photo allocation suite (47 checks) pass with this foundation.
The older direct-insert `signup_body_photo_origin.sql` fixture is refused by the
existing `body_photos_unavailable` fence both before and after this change;
it is not a passing modern sign-up integration test and was not weakened.

R167 adds 58 real SQL lifecycle checks and four real concurrent schedules,
including both completion/disposal orders and late signing after concurrent
account removal. Installed-SDK tests exercise the private RPC/signing sequence.
A separate local integration runs the installed SDK, issuer, real private SQL and
processor together; only Storage and model boundaries are synthetic. It verifies
one interpretation on replay, no public catalog mirror and no domain write.
This is local integration evidence, not connected Storage or native QA.

## Independent byte disposition

R169 adds a separate version-2 disposal manifest bound to the existing independent
source obligation. Explicit discard closes issuance and scrubs the catalog's
processing result before returning an external cleanup task. Scheduled claims
also enroll expired unsigned sources, closed sources and missing-catalog
obligations. A missing catalog never erases an unresolved signer ticket. No
legacy catalog, clinical source or old cleanup debt is enrolled or retagged.

Claims have exclusive five-minute leases and capture the current issuance
revision. A late signer response remains durably recorded and invalidates an
earlier cleanup claim or sweep readiness. Inspections require the exact owner,
asset, token, disjoint key and current private/nonversioned Storage contract.
The installed-SDK adapter removes only the observed object version, then
installs an empty object without upsert. It never deletes an existing barrier,
falls back to plain removal or acknowledges an uncertain write. SQL checks the
current empty object again when acknowledging, including an acknowledgement
replay. The response explicitly does not claim issuance reconciliation.

Deleted-account preparation respects the existing status/cutoff, enrolls bounded
visits, and waits for matching sweep revisions plus current empty barriers.
Only then can it detach that owner's private catalog. The independent source,
opaque identity, tickets, disposal evidence and empty objects survive account
removal. The ordinary registration receipts and numerical writers are unchanged.

Local qualification covers 53 disposal SQL checks, 14 original-writer/history
checks, four real signing/disposal/worker schedules and 20 installed-SDK HTTP
boundary cases. An installed-SDK/local-SQL chain qualifies two sweeps with only
one conditional removal and one empty write; reopening preserves the original
typed source. Storage/model boundaries remain synthetic. The unchanged factual
capture suite retains all 47 checks; its shared fixture functions and assertions
are byte-identical after extraction. Actual Storage interleavings and account
orchestration in the running app remain activation gates.

## Request routing and upload API composition

R170 adds a backend-only catalog resolver that returns committed owner/asset/
purpose/version proof without a Storage key. A transient unique request index
covers live catalog rows in both versions. It carries no payload or result,
imports nothing into the private catalog, and is removed with its source row.
The existing permanent opaque-ID fence remains separate. Six actual concurrent
commit/rollback and repeatable-snapshot schedules prove that one technical
request cannot create an asset in each catalog. Existing source rows are not
rewritten, and valid old identity updates retain their existing behavior.

An atomic versioned intake admission dispatcher preserves the first admission's
provenance: absence of a private binding on an existing intake means legacy
forever. It does not infer a new version from a later reused asset ID. This
dispatcher is qualified locally but is not yet the default intake transport.

The existing upload POST now composes a default-OFF private creation branch.
It requires `MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED=true` plus the existing
qualified staging/protocol gates. A proved old request calls the unchanged old
handler; errors in the private branch never fall back to it. New uploads retain
the public DTO, limits and key hashing. Inputs are pinned across asynchronous
waits, and a withdrawn gate or invalid final clock cannot return a capability.
Clinical/document creation and the feature-OFF path keep their old handler.

Local tests qualify the response constructor and installed SDK with actual SQL,
including one source on replay, the subsequent existing capture chain, and byte
disposition with synthetic Storage/model boundaries. This does not qualify
hosted HTTP authentication. The compiled guard confines the new RPC graph to
the upload POST in R170. R171 adds only owned GET/complete entries and
reconstructs their exact old callback sources, pins their entire intentional
new bodies, and retains the full issuer/shared table certificates. No protected source or global dependency scan is exempted.

R171 composes owned GET and upload completion behind the same default-OFF
server policy. Both require a committed version/owner/asset proof and never
fall back after a private failure. The installed SDK reads the exact private
object's metadata; size/MIME mismatch or an observed 404 commits independent
source closure for the disposal worker. An uncertain Storage outage remains
retryable and does not close the source. No unversioned removal occurs here.

Downloads use only the proved private key/origin, at most 300 seconds and no
more than the observed retention remainder. A final owned-source read refuses
a disposed/substituted source or a withdrawn gate before returning its URL.
Pending/deleted sources return no download. Completion replay does not create
another upload or interpretation. Existing clinical/public callbacks and
complete-response redaction remain byte-identical after removing the two
reviewed wrappers. Entire current route/helper/shared compiler bodies are
sealed; old certificates and global graph/security scans are retained.

The remaining process/discard endpoints, versioned intake transport, account
orchestrator and private worker still need composition before this opt-in can
be enabled. Activation remains OFF. R171 SDK/route tests use synthetic HTTP
Storage/SQL boundaries, not hosted authentication or real Storage/model proof.

## Versioned intake transport and old-caller fence

R172 binds the actual request runtime's existing scoped store to the atomic
versioned admission dispatcher when the trusted private policy is on. Original
Auth/admin/patient/epoch observations still bracket each physical call; there
is no extra unobserved catalog probe. Policy withdrawal is sticky across the
admission, current-scope checks and read-only recovery. Text and the default-OFF
path retain the original transport. Explicit `media_unavailable` is decoded as
a temporary refusal, without inventing calories or a different intake.

A reproduced transition bug allowed an old caller to create a version1 intake
for a source that was already private/version2, permanently blocking the same
intake ID's later resumption. The new additive guard refuses that new legacy
admission before it creates any row. A current retry may then admit the same
ID with its actual private provenance. Already admitted public intakes remain
version1 through genuine later asset-ID reuse; already admitted private intakes
remain replayable. Their original receipts and domain writers are untouched.

The exact original admission body is copied into a closed private implementation;
the public function is updated in place, retaining its OID/signature. Actual
already-prepared service-role text requests continue working across the DDL,
while already-prepared old calls cannot reserve a new private source. Both
wrappers preserve the original owner lane, epoch, hashing and replay rules.
There is no direct service/client EXECUTE grant on the raw implementation.

The historical private-capture fixture now seeds a genuine public source before
its legacy admission and only then reuses the ID privately, matching its
original stated test scenario. All47 assertions remain. Five actual admission
races additionally prove refused old requests leave no stub and can resume;
this intentionally supersedes the pre-guard allowance for new v2 inputs on old
callers. Hosted activation and actual Storage/native qualification remain open.

All six migrations remain source only. No deployed route, registered worker, rollout flag,
provider, clinical function, native binary or TestFlight version has been
changed. Before activation, compose the qualified private byte disposal/account
ports into the running app/worker and select the request-specific private runtime. Preserve
explicit catalog-version provenance without a public mirror or fallback that
could rebind an old receipt to a new source. Qualify the complete connected graph,
actual Storage interleavings, native permissions and distribution afterward.
The source/build guard seals the new pure export and reconstructs the exact old
package manifest and URL-parser source; all old compiled certificates remain.

The existing public-catalog debts, markers and frozen receipts remain governed
by their existing obligations. This foundation does not assert that old upload
capabilities, provider operations or legacy remover invocations have drained.

Implementation sequence:
`docs/superpowers/plans/2026-11-17-conversation-media-catalog-isolation.md`.

# Conversational media catalog isolation

Status: **local catalog/upload/processing substrate qualified; not activated or deployed**. The full
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

## Qualified and remaining

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

Both migrations remain source only. No route, registered worker, rollout flag,
provider, clinical function, native binary or TestFlight version has been
changed. Before activation, integrate explicit versioned factual capture,
independent byte revocation, scheduled disposal and account purge. Preserve
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

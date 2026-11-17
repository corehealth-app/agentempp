# Conversational media catalog isolation

Status: **local foundation qualified; not activated or deployed**. The full
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

The migration remains source only. No route, worker, rollout flag, provider,
clinical function, native binary or TestFlight version has been changed. Before
activation, integrate private upload preparation and signing, upload completion,
processing, factual capture, independent disposal and account purge. Preserve
explicit catalog-version provenance without a public mirror or fallback that
could rebind an old receipt to a new source. Qualify the complete connected graph,
actual Storage interleavings, native permissions and distribution afterward.
The codec is not yet exported through the closed production package surface;
add its reviewed export together with its actual consumers during integration.

The existing public-catalog debts, markers and frozen receipts remain governed
by their existing obligations. This foundation does not assert that old upload
capabilities, provider operations or legacy remover invocations have drained.

Implementation sequence:
`docs/superpowers/plans/2026-11-17-conversation-media-catalog-isolation.md`.

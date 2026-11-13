# Ordinary Storage upload revocation characterization

Observed on 2026-11-13, staging `xitugspwfxkcluxvrdeg` only. This is a connected
Storage boundary test, not qualification of the complete conversational media
flow or an activated retention implementation.

## Target and isolation

- Existing BFF `dpl_GLwhjwFeAjtnTn4LMbTXH2E58RUt`, project
  `prj_NTrnUNFXfmddMuci3VWjalfAoejW`, team
  `team_UERmEwgxRUaDvbvd22K1Iqde`, `gru1`, source
  `71d1322e313356ed688775c36cf84f3fbb90cc5c`: verified from Vercel metadata
  immediately before the test. No deployment or alias change.
- Existing synthetic QA A, one new local Auth session and one sandbox manual
  trial grant limited to one hour. No Roberto records or new account.
- One ordinary audio asset and its exact owner/asset-bound private path. No
  processing/completion, model call, meal, workout, intake or XP operation.
- Both relevant buckets were private, with versioning `DISABLED`, and no
  `storage.objects` policies were present. This is an observation, not a
  guarantee about future bucket configuration.

## Observed sequence

1. The real BFF created a pending audio asset and returned a non-upsert upload
   capability. Its Storage origin, path, JWT path and `upsert:false` were bound
   to the exact new QA asset before use.
2. A zero-byte `audio/mp4` PUT succeeded with HTTP 200. A read of that exact
   Storage object confirmed size zero and `is_delete_marker:false`.
3. A different eight-byte synthetic payload sent through the same capability
   was refused with HTTP 400 and provider error `Duplicate`.
4. The object identity, version and metadata remained exactly unchanged, size
   zero. An object deleted through Storage's versioning semantics is different
   from this ordinary empty object; do not conflate them.
5. The existing BFF DELETE removed the owned fixture. The exact object was
   absent and its media catalogue row was `deleted` on readback.

The temporary grant was expired through its own new source reference; the new
Auth session was logged out with local scope and its token file removed. Old QA
meal/workout/intake/media, profile, entitlement/event and Auth session hashes
matched the baseline. The one deleted media row and expired grant/audit are
retained as synthetic evidence. Stored upload URLs were redacted after use.

No OpenRouter key was created, revealed, copied or configured. This test needed
no model credentials. No Storage catalogue rows were manually inserted or
deleted through SQL; all object writes/removal used supported HTTP APIs.

## Meaning and remaining gates

An ordinary empty object can block a later non-upsert PUT at the same path.
This gives a concrete candidate for payload revocation without an indefinite
delete/recreate resweep loop or a guessed two-hour drain deadline. It does not
by itself prove an already-authorized upload still in flight cannot win later.

Before using it in retention, verify concurrent provider completion, the
capabilities of every relevant issuer, bucket/configuration drift, uncertain
writes, retries that preserve an existing barrier, and account-deletion and
marker lifecycle. A marker is not absence of an object: any implementation must
distinguish original-payload removal from final metadata/capability disposal.
Do not silently introduce permanent marker retention or claim final deletion.
R105/R106 manifests remain unactivated and legacy issuance remains unqualified.

## R108 source continuation — not activated

The scoped conversation cleanup now inspects a bound, unexpired private claim
before touching Storage. Its additive RPC refuses public buckets, versioning,
direct object-policy drift, unsupported marker MIME types and unknown object
size/version metadata. It distinguishes absent, ordinary empty and payload
objects; a provider delete marker is never accepted as an empty barrier.

An existing ordinary empty object is preserved. An absent path receives a
zero-byte non-upsert object. A payload is removed **only by its inspected object
version**, then the path is sealed and read back before acknowledgment. A stale
cleanup must not erase a newer barrier: plain-path deletion is unsafe even when
the preceding inspection saw a payload. A lost write response leaves the claim
unacknowledged; the next claim inspects first and preserves a successful barrier.
The existing debt/`waiting_for_issuance_drain` state is retained. This does not
establish a new indefinite-retention policy or final disposal.

The installed Storage SDK serializes `prefixes` unchanged but its types accept
only strings. The narrow versioned-delete bridge is covered using the actual
SDK against a controlled fetch boundary. Its `{path, versionId}` body follows the
[upstream delete route](https://github.com/supabase/storage/blob/master/src/http/routes/object/deleteObjects.ts).
**At R108, hosted version-targeted deletion was NOT VERIFIED.**
R109 below supplies hosted audio-bucket evidence.
Do not substitute a plain-path fallback if a provider refuses it.

The attempted connected concurrency characterization was inconclusive. The
bounded exact-path transaction lock was released automatically before an
observer could establish both queued PUTs. The only actual upload was an empty
marker (HTTP 200); the second payload PUT was never started. Neither elapsed
time nor upstream code proves hosted concurrent completion. The fixture was
deleted, the own grant/session closed, and old QA hashes preserved. No model,
credential, schema or deployment changes occurred remotely.

Before activation, qualify version-targeted deletion and an already-authorized
upload in flight, issuer capabilities and complete marker/account-deletion
lifecycle. Local transaction tests and SDK tests are not that hosted proof.
R105/R106 and the R108 inspection migration remain unapplied to staging.

## R109 hosted concurrency and version-targeted deletion

On 2026-11-13, the existing private, non-versioned `audio-notes` bucket and
synthetic QA A were used for two distinct provider qualifications:

1. A single bounded SQL controller held only the exact new fixture path's
   advisory lock and observed its own wait queue. It recorded two ungranted
   exclusive waiters at 05:13:53.254 UTC, before releasing the lock. An already
   running local producer sent the zero-byte and eight-byte non-upsert PUTs;
   it did not depend on another tool call to start them. The zero-byte PUT
   succeeded (200), the concurrent payload PUT was refused (400/`Duplicate`),
   and readback showed an ordinary zero-byte object, not a delete marker.
   This is a real concurrent-request observation. Upstream source helps
   interpret the provider's completion lock; its exact deployed source revision
   and every possible interleaving were not independently attested.
2. A temporary, protected Node qualification deployment used the existing
   worker's staging configuration and the installed Supabase SDK 2.105.1.
   Its handler required the exact new QA Auth session and bound pending asset,
   a short deadline, staging origin/project and São Paulo. It could operate on
   only that one disposable path. An unauthenticated request was refused (401).
   The SDK created eight bytes, removed their observed version, and independent
   SQL readback proved the object absent. It then created a zero-byte barrier.
   Repeating deletion of the **old** version left the new object's identity,
   version, size zero and non-delete-marker state exactly unchanged.

The first SQL/HTTP orchestration did not overlap: the local request timestamps
were after lock release because tool calls were serialized. It is not counted
as concurrency proof. The corrected autonomous-producer round above recorded
both actual provider waiters; elapsed time alone was never an acceptance test.

The first diagnostic build failed on a pinned builder peer conflict. It was
removed and provider absence verified before one corrected build using builder
30.0.0, whose `build-utils` peer matched the hosted builder. No force or legacy
dependency-resolution bypass was used. Both temporary deployments were deleted
and confirmed absent (provider 404). The existing worker predecessor stayed
READY, project build/protection settings and the app's canonical alias unchanged.
The artifact was outside the product route tree and never served Inngest.

Three disposable media rows remain only as deleted audit evidence; all three
objects are absent. The own sandbox grant was expired, the new local Auth
session logged out, the short-lived development OIDC file removed and six stored
upload-URL fields redacted. Old QA domain/profile/access/session hashes matched
the baseline. No photo/audio processing, model request, OpenRouter-key operation,
new persistent paid resource, migration, scheduler sync or TestFlight change.

These observations qualify the two specified Storage boundaries under the
observed configuration. They do not qualify the full media-to-facts chat flow,
photo capture, other configurations, backend backup erasure, all legacy issuers,
account-purge interaction or final barrier retirement. Resolve those lifecycle
requirements before activating the retention schedule. Product runtimes remain
unchanged; R105/R106/R108 migrations are still source only.

The authoritative local evidence is the R107 checkpoint/report linked from the
active goal index; it includes the bound candidate, baseline/postflight hashes,
provider responses, exact object readbacks and closeout. These artifacts are
private and contain no retained authentication token or usable upload URL.

## Branch discovery

The staging ref is a Supabase preview branch. `get_project`/`list_projects` did
not expose it as a top-level project, while `execute_sql` directly against this
same ref succeeded with the existing connection. A top-level not-found response
is insufficient evidence that branch database access or authentication failed.
Do not switch accounts or reveal credentials solely on that response.

## Primary references

- [Signed upload URL contract](https://supabase.com/docs/reference/javascript/storage-from-createsigneduploadurl)
- [Standard uploads and conflicts](https://supabase.com/docs/guides/storage/uploads/standard-uploads)
- [Upstream signed upload route](https://github.com/supabase/storage/blob/master/src/http/routes/object/uploadSignedObject.ts)
- [Upstream uploader](https://github.com/supabase/storage/blob/master/src/storage/uploader.ts)

Upstream source helps identify race conditions; it is not proof that a hosted
instance runs those exact bytes. The observations above are the actual hosted
test's scope.

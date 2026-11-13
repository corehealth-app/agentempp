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

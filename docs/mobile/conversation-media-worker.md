# Conversational staging media worker

The approved photo/audio chat uses the existing processing worker and private
Storage. Local tests and a READY deployment do not establish connected delivery.
Distributed build 17 remains text-only until a qualified successor is installed.

## Explicit function sets

| Set | Served functions |
| --- | --- |
| unset / production | Existing `allFunctions`, unchanged |
| `media-staging` | Existing media processing only, unchanged |
| `media-clinical-staging` | Existing processing and recurring-photo disposition, unchanged |
| `media-conversation-staging` | Processing, recurring-photo disposition, scoped ordinary-media retention and guarded account purge |

The new set is guarded at registration and again in privileged client creation.
Both restricted sets require the exact `xitugspwfxkcluxvrdeg` Supabase origin,
including the existing explicit-empty URL refusal and URL precedence. A roster
cannot register under another set's environment. The new retention callback
independently requires `media-conversation-staging` before constructing a client,
including direct or stale invocations. No WhatsApp, reminder or closer job is
added by the new set. Ordinary-photo analysis retains its trusted opt-in and
nonclinical purpose guard under both restricted sets.

## Ordinary expiry

The R108 source continuation adds guarded, version-targeted payload removal and
a zero-byte non-upsert barrier; it preserves a barrier on retries. This remains
unactivated pending complete issuer/barrier lifecycle proof and connected account-deletion qualification. R109 has
now qualified concurrent non-upsert completion and exact-version/stale deletion
in the hosted private audio bucket; full photo/audio integration remains separate.
See [Storage revocation qualification](conversation-storage-revocation-qualification.md)
for the actual evidence and its limits; `swept` still does not mean final disposal.

The API already assigns conversation photos and audio notes a 30-day retention
date. This change does not alter those dates or recurring-photo 24-hour policy.
`conversation-media-retention-cleanup` runs hourly at minute 17 with a 100-row
batch, one concurrent invocation and one retry. An additive private manifest
admits only expired ordinary `conversation_photo`/`audio_note` rows, with no
recurring origin. SQL atomically closes the catalogue and commits an owner/path
cleanup obligation before giving the worker a leased Storage task. Missing
schema fails before bytes. Body, gym, legacy meal photos and plan documents do
not enter this schedule. The old generic factory keeps its original ordering.

A successful Storage removal acknowledges a sweep, **not final disposal**.
Already-issued uploads and old build-17/R95 signing requests may still recreate
bytes. Their durable manifests remain eligible after catalogue deletion; leases
and oldest-visit ordering yield to other assets, and uncertain/failed requests
retain retry obligations. The manifest survives catalogue deletion and holds no
caption or model output. Current API code also refuses new expired ordinary
upload tickets; that guard does not govern old immutable issuers.

**Issuance drain is not qualified.** This migration deliberately offers no RPC
that guesses a settled state from elapsed time. Before activation/closeout,
complete and verify tracked issuance plus the legacy-issuer drain protocol; a
successful sweep is insufficient. The job reports `swept` and
`issuanceDrain: not_qualified`, never a false final-deletion count. Continued
manifest visits carry bounded per-run runtime cost until drain is proven.
It does not alter food/workout facts, receipts, XP or domain totals. Local SQL
checks historical typed projections; connected QA must still verify real domain
history and numeric panels after actual Storage disposal.

The RPC claim/ack and Storage request shape were checked against the installed
SDK and official [filter](https://supabase.com/docs/reference/javascript/in)
and [removal](https://supabase.com/docs/reference/javascript/storage-from-remove)
references. Controlled SDK fetches are not live Storage deletion evidence.

## Tracked ordinary upload issuance (source only)

The BFF's existing `MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED` and intake flags,
clinical project ref and exact `NEXT_PUBLIC_SUPABASE_URL` jointly opt into the new
ordinary ticket issuer. The default/generic and clinical upload paths retain
their behavior. A request header cannot opt in. Deploy the additive ticket
migration before enabling this code; missing RPCs fail before Storage signing,
without an untracked fallback.

For each new photo/audio upload attempt the issuer commits a private ticket,
asks the installed SDK for a non-upsert signed URL, validates its exact
origin/path and reads the actual provider expiry, then persists that expiry
before checking current catalogue authority or returning the URL. Supabase
documents a [two-hour upload capability](https://supabase.com/docs/reference/javascript/storage-from-createsigneduploadurl);
the returned expiry is recorded rather than guessed from the local clock.
Anomalously long or expired capabilities are withheld after bookkeeping. No
URL, JWT, caption or model output enters the ticket ledger or error response.

The ticket manifest survives catalogue deletion. A first late registration
reopens the original cleanup debt and invalidates older sweep claims; replaying
the same registration does not invalidate a newer claim. Catalog, ticket and
debt locks use that common order. A pending attempt whose signing result is
unknown remains unresolved. None of this certifies that immutable older
issuers drained, so the existing `legacy_untracked` debt remains unsettled.
Local rollback/SDK tests qualify these contracts only; connected Storage and
multi-session timing, scheduler and account-deletion lifecycle remain gates.

The [connected Storage revocation characterization](conversation-storage-revocation-qualification.md)
records a real empty-object/non-upsert conflict test and its QA closeout. It is
a barrier candidate with R109 hosted concurrency and stale-version protection
evidence, not an activated cleanup strategy or proof of final disposal.

## Publication and acceptance

Reuse worker project `prj_0SRds3zTc57EB0sExjYPygKGEgBx` and BFF project
`prj_NTrnUNFXfmddMuci3VWjalfAoejW` under the established team. Bind exact
source and archive hashes, set São Paulo explicitly and inspect the actual
deployment region; the worker project's current default differs from its last
deployed region. Preserve the canonical alias and build 17 runtime dependency.

Before activation, prove the current Inngest `performe-staging` application and
the exact four registered functions/schedules (including guarded account purge). Qualify synthetic upload,
processing, factual chat feedback, replay, cold edit/Undo and cross-tab agreement.
Verify actual expired disposable QA object removal and catalog state while
preserving unrelated rows and historical numeric facts. Existing provider cap
and expiry remain binding. This source alone does not prove scheduler activity,
remote deletion, physical capture, release readiness or Roberto acceptance.

## Account deletion continuation (R110, source only)

The conversational staging roster now also includes the existing quarter-hour
`user-deletion-purger`. Previous rosters and the default production algorithm
are preserved. Its real callback selects a dedicated ordinary-media preflight
only under `media-conversation-staging`; the existing privileged-client target
guard still applies. This fourth function is an intentional lifecycle change,
not a permission to register the previous three-function candidate unchecked.

Before recurring or generic deletion, the new backend-only preflight locks an
eligible deleted owner at the existing cutoff, admits at most 100 ordinary
photo/audio assets to the independent cleanup manifest and closes their catalogue
status. The fair scoped expiry job performs version-targeted payload revocation.
The account visit defers until every own ordinary path has both sweep evidence
and a current ordinary zero-byte object in the private non-versioned bucket,
with no direct-client Storage policy. Missing schema, malformed readiness,
foreign debt identity, payloads, provider delete markers or unknown object
versions cannot authorize account purge. Further visits advance beyond the first
100 assets. No Storage bytes are mutated by SQL.

A ready account's generic removal list excludes ordinary photo/audio paths;
it retains legacy meal/document/clinical handling. The account and catalogue may
then be purged without erasing their upload barriers or independent cleanup debt.
This proves neither final issuance drain nor final technical-marker disposal.
It does not adopt indefinite retention: the new functions remain unactivated
until the separately qualified barrier settlement/lifecycle and connected QA.
The 31 local rollback assertions and real factory/callback tests qualify source
behavior; they are not evidence that a hosted account has been deleted this way.

### Issuer and remover census

Current source has three SDK upload-signing sites, all explicitly non-upsert:
`supabase-media.ts` (generic and signup), `supabase-ordinary-media-upload.ts`
(tracked ordinary intake), and `supabase-reevaluation-photo-upload.ts` (clinical).
The current BFF upload tickets specify `x-upsert: false`; the shared native
transport whitelists that header but does not independently enforce its value.
The signed provider capability and its non-upsert semantics remain the authority,
not a client header assertion. Clinical paths
have their separate disposition protocol and are not admitted to this ordinary
manifest. Legacy immutable deployments and requests already in flight remain
part of issuance-drain qualification; a source census does not retire them.

Generic expiry excludes already deleted catalogue rows; ordinary expiry closes
those rows before Storage work. Replaying an explicit media delete for such a
row returns without removing its barrier. Account purge now preserves barriers.
An already-running old unversioned remover, metadata-mismatch cleanup and final
marker settlement still need complete activation/drain qualification. No source
or local test result here supersedes that gate.

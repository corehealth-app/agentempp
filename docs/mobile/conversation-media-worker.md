# Conversational staging media worker

The approved photo/audio chat uses the existing processing worker and private
Storage. Local tests and a READY deployment do not establish connected delivery.
Distributed build 17 remains text-only until a qualified successor is installed.

## Cold canonical history compatibility — R114

Connected native QA found that a saved neutral-media child in a V1 canonical
page invalidated cold recovery of every current meal on that page. The server
correctly preserves the internal `report_actual_record` source and versioned
`intake_origin`; the iOS reader previously parsed every source as an outbound
public `ConversationMealCommand`, which correctly refuses that internal form.

The reader now has a separate closed, read-only media-child entry. It verifies
the canonical source hash, epoch, receipt, ordering and current-group binding.
It is never an outbound command, queue ticket or delivery ACK. Cold recovery
uses this historical identity to read current official facts; it does not replay
the record. Existing public command admission remains unchanged. Regression
coverage includes media and neighboring text origins, malformed sources,
closed-day actions, current edits, Auth/patient isolation and durable outboxes.

The temporary diagnostic decoded both actual QA pages (25 and 13 entries);
three internal media children reproduced the original failure. Its source and
RED/GREEN evidence are retained in the R114 local evidence directory. Permanent
synthetic tests have no dependency on those local QA files. Full-suite native
qualification is still partial: ten rendering failures reproduce in the frozen
pre-change package, and the broad run did not complete. Scoped passing tests
do not supersede the remaining release, retention and physical-device gates.

## Connected synthetic audio qualification — R112

On 2026-11-13 a five-second, locally synthesized Portuguese audio note completed
real upload, the existing Groq transcription worker, interpretation with the
BFF's existing OpenRouter configuration, and the official meal writer. No caption
or transcript was supplied with the upload. No provider key was created, revealed,
copied or changed. This proves that the inherited app configuration worked for
these calls; it does not establish worker/app OpenRouter secret equality or future
validity beyond the existing key's lifetime and allowance.

The source-bound BFF preview is `dpl_4rnKPG685sQYpT1os75v4SmJSauU`, commit
`aaf5ddae2c210713835944aa423bd281f5318cbd`, region `gru1`. Its nonsecret protocol
flags were explicitly sent in the deployment API's `env` object. Merely placing
those flags in the uploaded nested `vercel.json` did not activate the protocol in
the first attempt. Both superseded R112 previews were removed and returned 404;
the qualified candidate is retained for successor qualification, with a review
within 24 hours. Canonical routing, build 17 and the registered worker were not
changed. Photo processing was not enabled by this candidate.

The actual transcript, “No almoço eu tomei 200 mililitros de leite com uma medida
de whey”, exposed a guard that rejected a separately labeled first-person subject
after the meal adjunct. The correction accounts only for the optional `eu` in
that closed prefix; genuine consumption predicates and the existing checks for
negation, future intent, habits, attribution and complete source coverage remain.
Two failing cases became green alongside 26 adversarial/refusal cases. The root
suite passed 16,219 tests across 602 files and seven tasks; both Next builds,
admin/BFF type checks, changed-file lint and compiled-source certificates passed.

The connected result saved one lunch with two items: 200 mL of milk and one
estimated, editable 30 g measure of whey, totaling approximately 231.3 kcal and
29.9 g protein. All six feedback sections were present. Technical replay returned
the same receipt. Editing only the whey to 15 g recalculated that item; undoing
the edit restored it. Reopened journal and nutrition projections agreed with the
current facts, while the original receipt remained historical. The registration
undo window elapsed and was not exercised in this round; undo-save was exercised.
The successful intake took about 58 seconds, which is server-path evidence, not
native responsiveness qualification.

The owned audio payload was removed through the leased, version-targeted API.
The closed catalogue had no processing result; Storage held only an ordinary
zero-byte barrier, with one tracked upload ticket and an acknowledged sweep.
The empty barrier and durable debt are intentionally retained pending proven
legacy issuer/remover drain. They are not final deletion. Domain history and
numeric nutrition projections remained readable after payload removal. Prior QA
rows/profile were unchanged, and the one temporary entitlement and new Auth
session were explicitly closed without removing the preexisting session.

Evidence: `performe-r112-issuer-census-20261113/qa-spoken-subject/VERIFIED.json`
in the local Codex SDD cache. The metadata census covered 30 READY deployments,
23 source commits and four historical media-service variants; 32 executable
characterizations describe their behavior. This is not hosted-source byte
attestation or a complete drain proof. The authenticated Inngest observation
still showed two registered functions, not the planned four. No new worker
registration, retention schedule, iOS archive or TestFlight delivery is claimed.

## Database deployment status — R111

On 2026-11-13 the five additive migrations from `20261113023500` through
`20261113064121` were applied together to staging `xitugspwfxkcluxvrdeg`.
The guarded operation matched source commit
`5ae8696337f5300b4159b92ebcf637eb01c69c29`. Readback matched all eleven function
bodies, owners, security-definer settings and execution permissions against the
local rollback rehearsal. Both new private tables were empty with RLS and no
direct client/service-role table access; the two media buckets remained private
and non-versioned. The prior 262 migration-history entries were unchanged.

The official migration tool also appended its own audit wrapper,
`20261113075840_conversation_media_foundation_r111`, in addition to the five
canonical source versions. This is an application audit, not a sixth schema
change. Do not replay the wrapper or repair/reset migration history.

Only the database foundation is installed. No processing deployment, Inngest
registration, retention schedule, flag, app alias, provider key or TestFlight
release changed. References below to source-only/unapplied migrations describe
their earlier qualification stages; activation and complete issuance/barrier
retirement remain separate gates. The existing app key is preserved; this does
not prove that the worker uses the same secret. Audio currently uses the
worker's existing Groq configuration; image analysis uses OpenRouter.

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

Payload revocation acknowledges a sweep, **not final disposal**.
The verified non-upsert barrier blocks later uploads while it remains present.
Untracked old issuers and immutable unversioned removers remain part of the final
barrier lifecycle qualification. Their durable manifests remain eligible after catalogue deletion; leases
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
R111 now routes current explicit deletion and metadata-mismatch cleanup through
the shared version-aware primitive. Already-running old unversioned removers and
final marker settlement still need complete activation/drain qualification. No source
or local test result here supersedes that gate.

## Explicit deletion and upload mismatch (R111, source only)

The owned DELETE and upload-completion transports opt into an ordinary disposal
port under the unchanged exact staging protocol gate. They construct the real
adapter only in those two transports; the common Supabase factory only forwards
that optional port. Clinical and generic consumers do not gain an unconditional
new RPC dependency. Missing schema, a busy lease, a foreign claim or an uncertain
Storage result fails without falling back to plain-path removal.

The new backend-only `claim_conversation_media_disposal` RPC enrolls the original
owner/path in the same independent debt, closes the catalogue and then returns an
exclusive lease. It never steals a live worker claim. A new attempt can resume a
completed/expired lease, including after the catalogue disappears. Expiry,
account cleanup and explicit disposal use the same claim/ack semantics. No SQL
writes Storage objects or claims final issuance drain.

The neutral `@mpp/core/conversation-media-revocation` primitive contains the same
closed inspection and version-targeted revoke/seal algorithm previously used by
the expiry worker. It has no SDK, environment or job imports. Both the worker and
the API bind its ports to the real SDK. Already installed zero-byte barriers are
inspected and preserved; lost responses keep durable debt. The API acknowledges
only after the inspection succeeds, then rereads the authoritative closed row
before returning deletion success. A metadata mismatch uses the same mechanism
and still returns the original 422 mismatch result. Other media retain their
existing behavior. No food/workout fact, receipt or XP writer is changed.

Local qualification includes actual SDK serialization with synthetic responses,
seven behavioral RED-to-GREEN cases, the existing 22 expiry/SDK cases and 22 new
rollback assertions. The processing fixture was corrected to satisfy all
existing catalogue constraints; no constraint or production rule was relaxed.
Connected photo/audio processing, real deletion through these new API paths,
legacy issuer/remover retirement, final marker settlement and release remain
separate gates. Five additive migrations (R105/R106/R108/R110/R111) are not
activated merely by this source change.

### Build certificate continuation

The BFF certificate pins the complete two disposal handlers and their shared
3554-byte primitive/SDK adapter, with all three new RPC markers confined to those
two entries. The common factory differs by exactly one 66-byte optional-port
spread; removing it reconstructs its complete previously certified body. The
media service differs by exactly 385 inserted bytes for the two disposal
branches; removing those reconstructs its complete prior compiled body.
Thirteen other source functions, including upload creation, remain identical.

Webpack factors five reviewed modules into one new shared file for exactly three
media entries: three literal prior bodies, the changed/reversible media service,
and a 574-byte pure flag module from unchanged source. The upload source remains
identical; its framework entry is repinned after this extraction. Historical
counts project only that proven file and its three edges; raw global counts and
forbidden worker/admin/Stripe/action scans continue to inspect the entire build.
No whole namespace or changed body is exempted from verification.

## Connected simulator qualification (R113)

The same R112 candidate was exercised by an actual Debug 1.0(18) simulator
installation, without changing provider credentials, feature flags, the app's
canonical address or TestFlight. A synthetic M4A was selected through the native
Files picker, attached without a caption and sent once from the neutral Flow
composer. The authoritative writer created exactly one lunch with milk 200 mL
(206 g internally) and one estimated whey measure (30 g): 231.3 kcal and 29.93 g
protein. The native current-item controls displayed the mL/measure references.

The native undo-registration control was confirmed once and committed 291.79
seconds after registration. Both new consumption rows were removed; the original
receipt and audit operation remain. After stopping/relaunching the app,
Alimentação showed only the previous confirmed records. A hash comparison kept
the QA profile, all pre-existing meals, workouts, media, intakes, entitlements,
events and original Auth session unchanged. Both newly owned Auth sessions and
the temporary entitlement were closed; the simulator and copied Files fixture
were closed/removed. This is simulator evidence, not physical-device, VoiceOver,
camera, recording or TestFlight qualification.

Direct native quantity editing was **not qualified** in this run: the automation
reported keyboard actions but the field remained unchanged, and the editor was
closed without saving. The successful connected API editing/undo-save evidence
from R112 remains separate. Chat loading and registration responsiveness remain
open performance gates; successful persistence alone does not qualify latency.

Explicit disposal of this owned audio returned success, cleared the processing
result and left one ordinary zero-byte non-delete-marker object with a successful
sweep and no live claim. Its durable debt remains `legacy_untracked`; this does
not settle old issuance or authorize indefinite marker retention. The proposed
technical-marker policy is awaiting the owner's business decision. No release
gate is waived by this QA run.

The accompanying read-only census attested 24 unique uploaded source files for
31 existing deployment indexes. It found 282 exact Git member comparisons and
four differences: the same two worker configuration modules in two deployments,
both exactly matching the preserved R288 publication overlay. These are uploaded
source attestations, not hosted function-binary attestations or proof that all
previously issued upload capabilities and unversioned removers have drained.

### Owner decision after R113

The owner subsequently approved retention of empty technical markers while old
versions/capabilities remain. The accepted scope and limits are recorded in
[the marker policy](conversation-media-marker-policy.md). This changes the
retention decision, not the technical readiness verdict: payload disposal,
old-remover stability, bounded cleanup, connected photo/account-deletion QA and
release qualification remain required. R113's pending-decision text above is its
historical checkpoint, not the current business decision.

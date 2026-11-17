# Conversational media catalog isolation implementation plan

> **For agentic workers:** Continue inline with `superpowers:executing-plans`; this is the existing R105-REVIEW-1 author fix pass, not a new whole-increment review.

**Goal:** Finish the approved photo/audio lifecycle while immutable legacy handlers remain usable for existing patients and clinical flows.

**Architecture:** New conversational assets will use an independent private catalog and a disjoint Storage key namespace in the existing private buckets. Old immutable handlers select `public.media_assets` and cannot obtain the new keys through their catalog queries. Current upload preparation, processing, factual capture and disposal must bind to the private source explicitly; no public mirror of a new asset is allowed. Existing assets and receipts remain on their existing readers and manifests.

**Tech stack:** Existing Postgres, Supabase Storage/SDK, TypeScript/Zod, Vitest and iOS clients. No new service, bucket, dependency, provider key or recurring infrastructure.

**Spec:** `docs/superpowers/plans/2026-11-03-performe-conversational-app.md`, approved marker policy in `docs/mobile/conversation-media-marker-policy.md`, R105-REVIEW-1 in the existing execution ledger.

## Global constraints

- Preserve the full T1–T7/all20 goal, frozen T5 base and R105 single author-fix pass.
- Preserve canonical/legacy/distributed origins and clinical media, including unknown old media. Never copy or retag them into the new catalog.
- Zero-byte markers and independent cleanup obligations survive catalog/account deletion. No time-only legacy drain claim or deletion of old markers.
- AI interpretation and education do not authorize writes; existing factual writers and clinical policy remain authoritative.
- Default activation remains off until complete connected qualification. A local foundation is not a release.

## Evidence and alternatives

R166 read-only provider inventory found 21 BFF and eight worker deployments. Original build17 and protected canonical/build18/worker/currentQA remain READY. Active firewall configuration GET returns `404 Config not found` through both MCP and the existing SDK session; this is not proof of an authentication failure. No firewall was changed.

Ingress fencing alone does not cover a remover already in flight at Storage. A new check only in the current BFF does not govern immutable old functions. A private catalog plus disjoint keys removes new assets from the old source graph without disabling existing clinical/text behavior. This is an implementation decision under the already authorized retention fix, not a new user retention policy.

## Review focus

- Same owner/asset ID on an old URL must not expose, sign or delete a new private path.
- An old purge or cleanup query already running must not acquire a newly created private asset's path.
- A foreign owner, stale scope, malformed path, changed source identity or clinical kind must be refused.
- No duplicate asset on replay, no lost upload capability on uncertain signing and no dropped independent disposal debt.
- Frozen historical receipts and public-catalog rows must remain unchanged through integration, disposal and account purge.

## Tasks

### 1. Private namespace and catalog foundation

Files: new `packages/core/src/conversation-media-namespace.ts` and corresponding tests; a CLI-created additive migration; new `supabase/tests/conversation_media_private_catalog.sql`.

Interfaces: exact version-2 owner/asset/bucket/path identity; service-only creation/read RPCs; immutable source identity; no Storage requests or route activation.

- [x] Pin failing namespace and real SQL catalog/ACL/isolation regressions before implementation.
- [x] Implement canonical keys under `conversation-v2/<owner>/<asset>.<extension>` in the existing buckets and an independent RLS-denied private table. Public catalog constraints continue rejecting these keys; drift preflight refuses a changed constraint.
- [x] Verify idempotent creation, foreign-owner refusal, clinical rejection, immutable identity, private grants and old public-catalog query invisibility with real local Postgres transactions. Six actual concurrent schedules include both repeatable snapshots and actual lock waits; private identity survives catalog removal while public/clinical reservations are transient.
- [x] Run neighboring suites/types/lint and preserve the complete original local database on closeout. Core 1179/43, BFF 129/11, existing ordinary SQL 151 and reevaluation asset checks 47 passed; original 214 table fingerprints and complete schema remained identical. Own local copy/process/socket closed. Foundation remains inactive in staging.

### 2. Upload, process and factual capture integration

Files: existing `media-service.ts`, `supabase-media.ts`, ordinary upload adapters, media worker and the intake/meal/workout factual capture functions; introduce small dedicated private-catalog adapters rather than changing legacy defaults.

- [ ] Bind the private catalog version through prepare/sign/register/complete/process/read/dispose; preserve unresolved signing obligations and conditional state changes.
- [ ] Route explicitly qualified conversational sources to private readers. Preserve legacy readers and old receipts; never create a public mirror or infer clinical purpose from bytes.
- [ ] Add real SQL/SDK boundary tests, including no domain effect on processing failure and no duplicate logical registration on technical replay.

R167 local progress (not route activation): the private catalog RPC adapter,
prepared/observed upload issuer, installed-SDK constructor and observation-only
processor are implemented. Real SQL checks cover upload replay, exclusive claims,
failure/reclaim and refusal of stale completion. Four real concurrent schedules
and an installed-SDK → real SQL → processor integration pass without external
network or provider spend. Explicit versioned factual capture and the complete
disposal/account lifecycle remain required, so the task checkboxes stay open.

R168 local progress: explicit version-2 intake admission is immutable and atomic;
old admissions cannot be upgraded or rebound after an asset-ID reuse. Five
fingerprinted read/projection hooks carry the selected version into neutral,
typed and linked-clarification source captures without a public row. Original
atomic meal/workout writers and replay pass against those captures. The trusted
private intake port and server codecs are qualified with actual SQL goldens and
an installed-SDK/local-SQL chain; default runtime remains unchanged. Five real
admission races preserve first-commit provenance. Private byte disposition,
account purge, default composition/activation and connected/native release gates
remain required before Task2/Task3 are complete.

### 3. Independent disposal and account lifecycle

Files: existing neutral revocation/worker/purge adapters and additive private lifecycle SQL.

- [ ] Carry exact version-2 keys in a durable independent manifest; preserve version-targeted removal and the empty barrier, including expired tickets and missing catalog/account.
- [ ] Ensure old user deletion cannot cascade away a live private payload without retained disposal authority. New purge must reconcile its own catalog/manifest without touching old preserved media.
- [ ] Qualify both original immutable old queries and current scheduled worker against new synthetic paths, concurrent signing/deletion, actual late upload, saved factual history and account removal.

R169 local progress: independent private discard, fair scheduled claims,
revision-bound inspection/acknowledgement and deleted-account preparation are
implemented. A dedicated installed-SDK adapter uses version-targeted removal
and non-upsert empty barriers without modifying the legacy algorithm. Real SQL
covers missing catalogs, unresolved signers, expiry, account removal and 102
assets; original meal/workout receipts survive disposition. Four actual concurrent
schedules and the SDK/local-SQL chain pass. The ports are not wired into running
API/account/worker composition, and actual Storage/native qualification remains
pending. Task3 checkboxes therefore remain open; no global legacy drain claim.

R170 local progress: upload POST has a default-OFF private creation branch,
selected by committed catalog proof. Old technical requests delegate to the
unchanged public handler without private fallback. A transient live-request
unique index prevents parallel old/new callers creating two assets for one
technical key; it adds no source-row rewrite or extra retention after deletion.
Six real cross-catalog request races, 23 routing SQL checks, response/limit/gate
tests and the installed-SDK/local-SQL creation/replay chain pass. The immutable
intake-version dispatcher is also prepared. GET/complete/process/discard,
intake transport, account/worker composition and live Storage/native qualification
remain necessary before activation; Task2/Task3 stay open.

R171 local progress: owned GET and completion now select catalog version by
committed proof through the existing service client. Metadata mismatch/missing
closes independent disposal authority; a Storage outage stays retryable.
Download signing is bound to the private path/origin, retention and final owner
state. Both original callbacks reconstruct exactly; full compiled code and
current consumers are sealed. Real route/installed-SDK tests use synthetic
HTTP boundaries. Process/discard/intake/account/worker and actual hosted Storage,
authentication/native/TestFlight qualification remain open; default is OFF.

R172 local progress: the scoped intake runtime now calls the atomic versioned
media admission dispatcher under trusted policy, preserving real per-RPC scope
observations and sticky withdrawal. A reproduced old-caller transition is
fenced at the public admission RPC without changing its OID or original legacy
implementation body: a new private source cannot become an immutable legacy
stub, and the same intake ID can resume correctly. Original admitted receipts
stay frozen. The temporary `media_unavailable` refusal is explicitly decoded.
Process/discard/account/worker composition and actual hosted/native delivery
remain required; Task2/Task3 remain open and activation stays OFF.

### 4. Qualification and delivery

- [ ] Inspect the complete source/compiled/schema diff and run required regression gates before any staging application.
- [ ] Apply only the validated additive migration through the guarded staging manifest. Reuse the current task environment; do not create per-retry previews.
- [ ] Verify actual text/photo/audio, direct edit/Undo, cold cross-tab parity, physical camera/microphone permissions and privacy. Preserve all frozen evidence.
- [ ] Sign/archive/upload the qualified candidate, verify TestFlight processing/group availability and installed release, then obtain Roberto acceptance. Android and all other obligations remain in the parent plan.

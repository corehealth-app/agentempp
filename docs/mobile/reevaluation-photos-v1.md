# Recurring photo boundary (local candidate)

The HTTP factories, native repository and optional native capture model/UI are
implemented and tested locally. They are not mounted, enabled in default
dependencies, deployed or available to testers yet. Both Flow consumers and the
complete clinical composition must be qualified together before activation.
No signup authority or signup photo can satisfy a REGULAR cycle.

The base is `/api/mobile/v1/reevaluation/{cycleId}/photos`. Owner is derived from
authentication; cycle is the actual server occurrence. POST intentions use a UUID
`idempotency-key` header. Revisions are positive bigint strings, never JSON
numbers or a locally incremented value.

| Method/path | Public body | Result |
| --- | --- | --- |
| GET `consent` | none | Exact current legal text/identity, acceptance and revision |
| POST `consent` | `expectedRevision`, shown `document{id,documentKey,version,locale,bodyHash}` | Current acceptance |
| GET base | none | Three current pose/status slots and quota policy |
| POST base | `expectedRevision,acceptanceId,pose,mimeType,sizeBytes` | Bound asset and server revision |
| POST `{assetId}/upload` | `{}` | Narrow PUT capability, only MIME and no-upsert headers |
| POST `{assetId}/complete` | `{}` | Actual Storage metadata confirmation, server revisions |
| POST `{assetId}/process` | `{}` | `processed`, `skipped`, or safe failure reason |
| POST `discard` | `acceptanceId,expectedRevision` | SQL discard acknowledgement and physical cleanup state |

Accept always reaches SQL, including repeats of the same key. Current document,
locale, policy, expiry and occurrence are checked before replay. GET never
accepts the text or renews idle retention. The document body is preserved
literally and its UTF-8 SHA-256 is checked. This V1 exposes only the approved
86400-second policy.

Allocation replay keeps its key and exact bytes/MIME/pose intention. Processing
replay keeps its original request key, so an uncertain network result cannot
start a second provider attempt. Upload ticket issuance may be repeated for the
same asset; every actual capability expiry is registered independently before
the capability is released. These guarantees remain in the original authorities,
without an outer response cache or client clock.

Snapshots expose neither individual body-fat readings nor a mean. The FULL form
descriptor alone provides the opaque official candidate for explicit acceptance.
Snapshot status is not consent authority. Always reconcile consent before a new
capture and refresh the form after replacement or processing. The public quota
is a policy (6 new photos per rolling 24 hours), not a remaining-usage estimate.

Discard does not return a cycle revision. Re-read the server. `pending` and
`waiting` do not mean that all future bytes are gone: a still-valid upload
capability requires another sweep after its actual expiry. The existing drainer
performs remove, deadline guard, then exact SQL acknowledgement; the normal
cleanup worker reconciles later capabilities. No historical gallery is offered.

The native repository is scoped once to the original Auth lease and cycle. It
registers cancellable work before starting it, validates after the response and
again after finishing the work registry. An old A scope cannot renew for B or
for a new A session. Visible state publication uses the same retained lease.

The shell-owned FULL model retains one photo child per actual REGULAR cycle.
The parent's original session is checked before and after binding that child.
Replacement revokes the old draft acceptance and blocks clinical editing until
the official form is successfully refreshed. A refresh begun before a new
replacement cannot clear that barrier. Closing/reopening the photo route keeps
the same in-memory intent, file, asset and keys; no signed ticket is persisted.
App termination does not persist these local intentions. Server-side abandoned
assets remain subject to the independent cleanup authority.

The camera and system library picker have per-presentation nonces. A cancelled
or late callback cannot consume or dismiss a newer producer. The library read
is registered as cancellable original-session work; its SDK progress and sole
continuation are cancelled together. Before staging, images are normalized to
metadata-free JPEG, at most 2048px, in the existing protected temporary area.
The shared `body_checkin_photo` media kind conveys no signup authorization.

An uncertain allocation is replayed with the same request; an uncertain PUT is
first reconciled through completion of the exact asset. Missing bytes can use
fresh upload authority for that same asset, without a new allocation. A pending
or uncertain analysis keeps its processing key. No automatic second analysis
or photo is created. Explicit discard keeps its original acceptance/revision
intention and reports waiting cleanup honestly.

A specific SQL-authoritative quota refusal creates no new asset. The local
file/intent is cleared, selected photos are preserved, and the FULL descriptor
is refreshed instead of trapping an otherwise valid reassessment. New capture
waits for explicit refresh. An unrelated HTTP429 is an uncertain failure and
must never be interpreted as that allocation refusal.

Local evidence includes real factories/adapters against the owned PostgreSQL
runtime with rollback, explicit synthetic Storage/AI ports, and native contract
and session tests. It does not prove PostgREST, provider deletion, real AI,
real camera/system-picker execution, full navigation, fresh install, deployed
cron or TestFlight delivery. Hosted native content nodes are tested separately
from the still-required real-device end-to-end flow.

# Dormant authenticated native meal command controller

This increment composes the real `MobileAPITransport`, actual session lifecycle,
encrypted outbox and typed terminal receipt. It does not connect a view/model,
change a feature flag, enable a route or call the legacy Flow writer. Backend
contracts are the local root public service at `99a17ba4`, qualified separately;
URLProtocol tests below are mocked HTTP, not authenticated backend/native E2E.

## Public wire boundary

- GET `/api/mobile/v1/conversation/session`: exact six fields `schema`
  (`conversation.session.v1`), `auth_user_id`, `owner_id`, `epoch`, `observed_at`,
  `meal_command_protocol` (`conversation.command.v1`). No command is created.
- POST `/api/mobile/v1/conversation/meal-commands`: byte-exact original command,
  original `Idempotency-Key`, `X-Conversation-Epoch` and `X-Conversation-Owner`.
- GET `/api/mobile/v1/conversation/meal-commands/{lowercase command UUID}`:
  original epoch/patient headers and `X-Conversation-Input-Hash`, with no body/key.
- All three send `X-Conversation-Protocol: meal-command-v1`. Owner/epoch headers
  are preconditions only; the backend authenticates the actual patient before
  service/RPC work. They grant no owner, clinical or nutrition write authority.

The existing HTTPS origin/path policy, disabled cookies/cache/credential storage,
bounded response reader, cancellation, Auth lease and patient-work registry are
reused. Header fields are a closed enum restricted to the exact method/path,
canonical body and explicit matching cmsg1 key; callers cannot override Auth/Host
or add a patient query. Every conversation redirect is refused. Legacy requests
retain their prior GET redirect and bounded 401 refresh/replay behavior.

Command POST explicitly disables 401 refresh/replay. Network loss, timeout,
5xx, 409 and 429 produce no automatic POST retry. The existing Flow turn ceiling
(180s client, with separate shorter backend provider/route budgets) is reused;
response limit 262144 applies only to this protocol. No dependency/provider/model
or cost rule is added.

New responses require exactly `data` and `meta`, with meta exactly
`api_version=v1` and a valid `request_id`. The transport preserves status. Saved
packets require 200, pending state requires 202, absent/not_recorded require 200.
State has exactly schema/status/owner_id/command_id/input_hash/epoch; only
not_recorded additionally requires reason `[a-z_]{1,80}` and unique food_indexes
0...29 (max30). None of these state responses is a saved acknowledgement.

## Identity, intake and current authority

`ConversationMealCommandController.open(transport:lifecycle:store:keyVault:)`
reserves the original real Auth lease, refuses token-only or differently scoped
transports before requests, opens the same account ciphertext and explicitly
reads the session capability. Constructors perform no HTTP/domain work.

Auth subject and patient ID may differ. Crypto file/key namespace remains Auth;
v3 entries/tickets preserve the separately verified original patient and epoch.
V1/v2 without patient proof remain held and redacted, never automatically tagged.
The actual session response's auth_user_id must match the captured lease.

The controller's shared current authority is revoked when a refresh begins.
Only the latest local request identity can accept a response; backend UUIDs are
never ordered. Both data publication and the initial scope-suspension event are
bound to that refresh token, so a late suspension cannot hide a newer snapshot.
Authority locks span synchronous disk and visible operations inside the real
lifecycle gate, never an await. A known new patient/epoch cannot race an old
local ACK, resend or raw-body publication.

A second, enqueue-only binding retains the last actually verified patient/epoch
during an active Auth session if a later refresh is offline/pending. It can only
persist a new encrypted intent and publish a queued UUID, without old raw data,
meal success or targets. It cannot dispatch, replay, ACK or publish a raw snapshot.
A successfully verified new mapping revokes/replaces it in the same patient-state
gate; logout/close revokes both. Cold open without a verified session never
invents this binding. No old command is retagged. A fresh session read is still
required before any send or reconciliation.

## Explicit operations and recovery

`enqueue` creates a fresh UUID per genuine new intent, including identical text.
`send` refreshes the session, checks original patient/epoch and persists unknown
before one physical POST. `reconcile` performs session GET plus command GET only.
Saved results go through the same closed factual packet/FX decoder and atomic
exact-command ACK; optional null/malformed historical feedback remains optional.
All saved/UI facts publish only through the visible session gate.

Only a fully bound authoritative GET returning pending/absent can create a
one-use `resubmit` permission. Resubmit checks current authority, exact stored
body/hash/ID/patient/epoch/key and no permanent hold, then sends those same bytes.
It never generates a new ID or automatically resubmits from an unknown outcome.
Starting another refresh revokes older permissions. A late old POST callback
cannot consume a newer GET permission. Not-recorded remains a durable held
clarification tombstone, never ACKed or silently rewritten as new intent.

The backend's known `conversation_command_changed`/`conversation_patient_changed`
409 codes create a permanent exact-entry serverChanged hold; unrelated conflicts
remain unresolved without being mislabeled as a known epoch reset. 429 stays
pending with no timed/model retry. Explicit local reset and stale/reset holds
remain permanent. Missing/corrupt/lost storage never becomes a fake empty success.

Cancellation/account change synchronously revokes both authorities and schedules
the retained controller's close to release RAM lease/replay handles and owned
work, matching the outbox's existing cancellation lifecycle. It suppresses late callbacks while
keeping ciphertext. A verified A deletion before a later account change remains
A's factual ACK; B receives no publication. In-flight close/cancel/network loss
keeps unknown work for read reconciliation. The controller has no automatic
background queue drain, model/extractor call, UUID renewal or legacy fallback.

## Verification and activation gates

Portable tests run the actual Foundation store/parser/transport/controller with
synthetic URLProtocol responses and in-memory test credentials. They cover
physical headers/body/key, default legacy vs new 401 behavior, 200/202 mismatch,
response bounds/redirects, Auth!=patient, v1/v2 preservation, caller cancellation,
restart/lost response, account/mapping change, late session/POST/visible ordering,
permanent holds and explicit pending/absent replay. Regression REDs were observed
for both ordering races and offline intake preservation before their fixes.
Native QA additionally uses the actual SessionLifecycleCoordinator and existing
unique synthetic Keychain roundtrip/verified deletion, plus receipt/view neighbors.

Remaining activation gates: actual authenticated SDK-to-native flow, lifecycle/
foreground/UI composition and refresh, user-facing retry/clarification behavior,
provider latency/cost qualification where required, and explicit release flags.
A schema decoder or URLProtocol PASS is not database/provider/user-flow proof.
No physical phone, cloud environment, provider request or server deployment is
performed by this native increment.

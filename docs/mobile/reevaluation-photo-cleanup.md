# Recurring photo cleanup (local qualification, dormant)

The normal recurring-photo worker uses the existing disposition authority and
Storage drainer. It does not analyze photos, sign uploads, publish consent,
change clinical results or delete patient history. A sealed SQL disposition is
not proof that its Storage bytes have disappeared.

`claim_mobile_reevaluation_photo_cleanup_scopes(limit)` is a backend-only,
server-clock discovery function. It finds bounded candidates in non-deleted
accounts, including old generations and completed/invalidated cycles. Candidates
include the acceptance's actual idle deadline, revoked/changed authority and
sealed scopes ready for a first removal or a due resweep. Future waits and settled
scopes are excluded. A late ticket registration reopens its existing disposition
and makes it discoverable again. Deleted accounts retain their existing purger.

The queue's stale-authority checks are discovery hints. The original prepare RPC
locks and checks current authority before removal; a renewed valid scope returns
`live`. The worker never substitutes its own calendar or consent decision.

The claim locks acceptance rows with SKIP LOCKED and records a technical visit
before returning. It does not acquire an owner lock after that acceptance lock.
Its checkpoint table references the acceptance only, so an extra user FK does
not invert the clinical owner-to-acceptance lock order. Clinical/profile/media
rows are not changed by claiming. The visit rotates a failed scope behind other
eligible work; the SQL row remains available for subsequent runs.

`cleanupReevaluationPhotos()` claims one scope at a time, with an eight-second
default total deadline and up to twenty distinct scopes. Each existing drainer
gets at most three seconds/five pages and the shared abort signal. A scope failure
does not stop other owners. A repeated valid scope is deferred to the next run;
a changed identity, malformed packet or late claim cannot start another removal.
Results contain only bounded counts and safe stop reasons. `batch_end` means the
current scan ended, not that every physical file or future PUT has been cleared.

The adapter delegates the original sequence:

1. Prepare/reconcile the exact owner, cycle and acceptance.
2. Read the original manifest page and its sweep/capability identity.
3. Remove only those `body-checkin-photos` paths.
4. Guard the deadline, then ACK the exact page in SQL.

An uncertain/failed removal has no new ACK. A later run reuses the durable
disposition and handles unknown or late upload expiry through the existing
waiting/reopen/resweep rules. Numeric confirmed results remain preserved.

`reevaluation-photo-disposition-cleanup` is defined with concurrency one, one
retry and a once-per-minute cron. It is served **only** by the new explicit
`media-clinical-staging` function set, together with existing media processing.
`media-staging` and the default/legacy `allFunctions` array are unchanged. No
environment or endpoint is switched by adding this source. Selecting the set,
checking provider registration and verifying actual Storage removal remain part
of the complete M3B release. Cron scheduling adds delay after the SQL deadline;
backlog/time-limit outcomes are aggregate warnings, not a guarantee of exact-time
physical deletion.

Local evidence includes SQL invariants for the 24-hour boundary/discovery,
fairness, reset, discard, due waiting, late expiry, permissions and preservation;
neighboring drainer/purge/media tests; and the actual worker/adapter/SQL bridge.
The bridge deliberately uses a synthetic Storage port: the first removal fails,
the second succeeds, and SQL proves no ACK for the failed owner while fresh and
ordinary media/profile state remain unchanged. It uses one ROLLBACK connection,
not PostgREST, Inngest execution or real Storage. Real provider/Storage, quota,
retention, connected native UI and final release qualification are still required.

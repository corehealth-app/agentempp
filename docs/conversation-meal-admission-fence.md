# Meal command admission with the original epoch

`admit_conversation_meal_command_fenced(p_user_id uuid, p_input jsonb,
p_expected_epoch uuid)` is a service-only additive admission entrypoint. It
returns the existing `admitted`/`replay` command binding or
`input_conflict`/`stale_epoch`. SQL exceptions retain the existing strict input,
trusted backend, active owner and READ COMMITTED requirements.

The caller must retain the backend epoch originally associated with the intent.
After a reset, it must not replace a queued intent's epoch with the new one.
A current epoch supplied by a client does not prove when an unseen intent was
created. The BFF must bind the authenticated owner and use the immutable queued
epoch; this RPC does not establish client provenance.

The function takes the existing workout/owner lane, then locks the existing
authority epoch and command identity. An invalidated or old-epoch command UUID
returns `stale_epoch` before input hash comparison. A missing, NULL or mismatched
expected epoch also returns `stale_epoch`, including for an existing current
command. Refusals create no authority, identity or source. A matching existing
epoch delegates to the unchanged legacy admission while retaining those locks.

The old admission RPC remains available for qualified private legacy callers.
New routes must use this fenced entrypoint. This migration creates no route,
queue policy, domain effect, provider call, message, workout lifecycle or reward.

Real local PostgreSQL qualification covers admission/replay, changed input,
owner isolation, missing authority, reset tombstones, an unadmitted offline
intent, 48-hour replay, ACL and both unsupported isolation levels. Six actual
blocking races cover two admissions and reset in both orders, with commit and
rollback. Journal, semantic, source, writer and feedback neighbors pass. A fresh
migration rollback/reinstall preserves row and existing schema fingerprints;
the synthetic owners and actors are removed. Evidence is retained outside Git
under the task's `T3-ADMISSION-FENCE` directory. No cloud or public activation is
qualified by these local checks.

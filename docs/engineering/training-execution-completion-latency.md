# Bounded training completion

The original connected completion path committed a workout but exceeded the
client response deadline. Nested runtime, completion and workout guards caused
repeated Auth, mapping, entitlement and clinical HTTP observations. Increasing
the client timeout does not fix that amplification.

## Transaction boundary

`submit_training_execution_completion_authenticated` runs the existing guarded
begin, source capture, version-2 report resolver, preparation, protected commit,
effect read and completion read in one owner/Auth-session transaction. It calls
the public begin wrapper, so an existing withdrawal marker still rejects a late
finish. It does not replace the workout, clinical, energy or strength writer.

The transaction retains the original owner and Auth-session locks throughout.
The normal entry points still check the active patient, epoch, open local day
and clinical permissions. Original-session expiry is checked again before the
transaction returns. Expiry during the writer rolls back its reservation and
effect. A concurrent withdrawal either wins before admission or observes the
already completed receipt; it cannot release a completed workout for replay.

Only `service_role` may call the new RPC. The migration checks the executable
bodies of its existing primitives and adds no tables or direct client grants.
Deploy the additive migration before a server that selects this RPC. Preserve
it on server rollback; it does not activate any client capability by itself.

## Independent proof and response recovery

The server independently decodes the captured source, recomputes the report
decision, validates preparation and actual effect, and verifies the linked
training receipt. A status string or mutation response is insufficient. The
before/after current-scope callback surrounds this one transaction without a
second identical outer pair.

A lost or malformed transaction response never causes an automatic write
retry. The runtime may observe only the same immutable operation and return its
proved terminal receipt. A missing/reserved/unproved outcome is not an ACK.
Existing read/cancel/progress/finish-resolution protocols remain unchanged.

The proved source/preparation/effect feed the existing canonical feedback
writer and current-safe historical renderer directly. This avoids reconciling
the whole workout again just to render education. The final clinical policy
and observation time must still match before publishing feedback. Optional
education failure neither repeats nor invalidates the physical registration.
All six feedback sections retain their existing official-number rendering.

## Qualification

Require real SQL tests for replay, cancellation/withdrawal, non-performed and
incomplete reports, identity/revision rejection, expiry during the writer and
both concurrent submit/withdraw lock orders. Verify the actual route/service/
SQL path and lost-response read recovery. Measure connected response latency
against the unchanged native deadline before enabling the new native path or
claiming that the TestFlight candidate is ready. Local timing is not hosted QA.

## Nonretryable HTTP conflicts

The connected withdrawn-command test exposed a second cause: a custom
`40001` conflict can make PostgREST repeat the transaction. Supabase documents
this behavior and recommends an HTTP-mapped error such as `PT409` in its
[RPC retry guidance](https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).

The new server selects thirteen closed, service-only `_authenticated_http`
adapters. Each invokes its byte-pinned original function and translates only
`serialization_failure` into `PT409`. The originals, including their errors,
stay intact for older servers. There is no new domain writer or table grant.
Cursor defaults and argument order are preserved. Apply the additive adapters
before selecting them in the server; older servers remain compatible on rollback.

The runtime maps `PT409` to the existing conflict response and returns definite
Auth or conflict refusals without extra recovery SQL. Unknown transport outcomes
still use the exact read-only recovery path. A conflict is not a workout ACK and
does not authorize clearing an uncertain native pending command.

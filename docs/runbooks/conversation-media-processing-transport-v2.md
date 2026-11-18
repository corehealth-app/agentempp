# Private conversation media processing without orchestration quota

This additive transport runs only in the existing Performe staging project
`xitugspwfxkcluxvrdeg` and worker `prj_0SRds3zTc57EB0sExjYPygKGEgBx`.
It reuses private catalog v2, the existing processing algorithm, configured vision
model/prompts and Groq transcription. It performs no meal, workout, XP, clinical
or feedback write. Media observations still enter the existing intake protocol.
Legacy/default worker sets and the default BFF transport remain unchanged.

## Activation gates

The migration `20261118031352_conversation_private_media_processing_transport.sql`
installs two private RLS tables and backend-only RPCs. It starts OFF and creates
no active cron. Read migration history before applying; do not infer provider
history version from the source filename or reapply an ambiguous attempt.

The worker's opt-in requires all of:

- `MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED=true`;
- `INNGEST_FUNCTION_SET=media-conversation-staging`;
- exact staging `SUPABASE_URL`;
- `MOBILE_CONVERSATION_PROCESSING_WORKER_PROJECT_ID` equal to the worker above;
- `MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA` equal to the candidate commit;
- its actual `VERCEL_URL` matching the fixed staging worker namespace.

The existing private catalog/photo flags retain their independent live checks.
The new HTTP POST is `/api/internal/conversation-media/process-v2`. It uses a
one-use 256-bit capability, not an administrative cookie or an Inngest execution.
All public bodies are strictly bounded to 256 bytes and contain only a dispatch
ID, or `{ "setup": true }` for the separate one-use setup operation. Caller-supplied
owner, path, source, model, credential or callback URL is rejected.

After candidate metadata/source/build/health qualification, prepare setup through
`prepare_conversation_media_processing_transport_v2` using the exact deployment
URL, SHA and a random capability's SHA-256. Keep the raw capability only in memory.
A protected setup POST lets that worker register its own existing
`VERCEL_AUTOMATION_BYPASS_SECRET` into Supabase Vault. No provider key is fetched,
copied, rotated or put into SQL text, logs or an artifact. Runtime availability
must be proved by this operation; documentation alone is insufficient. The setup
expires in ten minutes and cannot replay. Reconfiguration reuses its Vault slot.

Only after connected private-source qualification may
`configure_conversation_media_processing_transport_v2(true, 'xitugspwfxkcluxvrdeg')`
enable the single owned minute cron. It sends HTTP only when work is due and
bounds global in-flight requests to two. Preserve the independent retention cron.
Enable the new BFF flag on the qualified app candidate only after the worker is
ready. No Inngest workspace, plan or execution is required for this transport.

## Durable behavior

The BFF first commits `enqueue_conversation_media_processing_job_v2`, validating
the returned owner/asset/job receipt. It then awaits a separate bounded dispatcher
RPC as an immediate wakeup. A lost wakeup does not invalidate durable acceptance;
the owned cron recovers it. An unaccepted/foreign/failed receipt never falls back
to Inngest and is not reported as accepted. Keeping enqueue and wakeup in separate
transactions avoids reversing the source/config lock order.

Concurrent requests for one active source reuse one job. Different assets remain
different jobs even when their request IDs or contents match. Core SQL source and
processing leases remain authoritative; transport leases are additional fences.
A busy core lease or feature OFF is deferred without consuming a transport retry.
Queued callbacks expire after two minutes; running leases expire after five.
Transport errors are bounded to four failures and become a source-scoped failure
through the existing core claim/failure protocol, without invoking a model.

A claimed callback cannot replay. Completion is idempotent for an uncertain ACK;
it cannot downgrade a terminal result or report an unprocessed source as complete.
Removed/expired/inactive sources are cancelled. Rebinding refuses a live lease,
invalidates old queued capabilities and preserves all source/history records.
Lock timeouts fail the transaction rather than bypassing row/source fences.

The worker shares a 240-second deadline with its SQL and Storage HTTP calls and
with explicitly injected provider fetch. The SDK's default Node fetch otherwise
bypasses a caller's signal. Before starting providers it reserves their bounded
runtime budget. Existing model/purpose checks, timeouts and retry policy remain.
Only the existing OpenRouter chat and Groq transcription endpoints are allowed;
redirects and other egress are refused. Authenticated Storage downloads use the
installed SDK's `/storage/v1/object/<bucket>/conversation-v2/...` path. The worker
reads only the existing vision configuration/rules and listed backend RPCs.

## Rollback and closeout

Disable the SQL controller to stop dispatch and revoke live IO fences. This
unschedules only the exact owned cron and preserves pending jobs, catalog rows,
results and retention obligations. Keep the BFF bridge flag enabled while its
controller is disabled so new attempts receive an explicit unavailable response;
do not silently send them into an exhausted orchestration service. Re-enable or
replace only after qualification. A planned handover waits for active leases.

No new fixed paid service is needed. Candidate previews still consume existing
plan resources and require source/deployment identity, owner, purpose and a
closeout condition. Close superseded task-owned candidates only after checking
actual native, alias, registration, pending-source and cleanup dependencies.
Never delete required zero-byte late-upload barriers to close a deployment task.

Local qualification is not hosted provider or native/TestFlight proof. Required
release checks remain actual photo and spoken audio, persisted neutral results,
chat intake/receipt, edit/Undo, cold reopen and cross-tab consistency, followed by
native/TestFlight and the installed Roberto build. All other full-plan obligations
remain active.

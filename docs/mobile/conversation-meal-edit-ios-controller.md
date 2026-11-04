# Dormant native meal-edit controller

`ConversationMealEditController` composes the existing encrypted edit session,
closed operation/result readers, owned group reader and authenticated mobile
transport. No app factory, screen, route or feature flag activates it here.

## Original intent and current scope

`open(transport:lifecycle:store:keyVault:)` captures the real Auth lease and owns
cancellable lifecycle work. It performs no remote edit or background dispatch.
Every operation requires the command controller’s actual revocable
`ConversationCommandContext`; Auth subject and patient ID remain distinct.
The controller never creates a backend observation or changes the crypto owner.

`prepare(commandID:originalInputHash:expectedRevision:expectedVersion:action:
context:operationID:)` performs a real owned group GET. It requires the exact
captured revision/version and the server action capability. Save must target a
current item; UndoSave must target that group’s last actual saved operation.
No eligibility is inferred from device time, local macros or decoded shape.
The opaque preparation retains the original context and one immutable operation.
It exposes no current group or clinical authority. After the local state
operation returns, the actual lease, lifetime and context grant are checked
again before any prepared payload can reach the caller.

`enqueue(preparation:context:publish:)` persists that operation before dispatch.
A refreshed grant for the identical Auth/patient/session-generation/epoch may
preserve the original intent in storage; its CAS, UUID, body and hashes stay
unchanged. A changed identity or another controller’s preparation is refused.
A failed enqueue leaves the preparation usable for the same explicit retry.
The future editor must keep this prepared intent visibly locked, as the report
composer does, and must not prepare a replacement UUID after uncertainty.

## Transport and recovery

- `send(id:context:publish:)` persists unknown before exactly one edit POST.
- `reconcile(id:context:publish:)` uses the read-only POST endpoint with the same
  original body, operation UUID, `cmedit1` key and original owner/epoch/hash headers.
  It never calls the edit writer as a fallback.
- Only an exact closed `absent` response can grant one explicit, one-use
  `resubmit`; no response, timeout, 401, 429 or absence automatically sends again.
- Physical work is serialized per composite command ID + operation ID. A second
  call for the same intent fails `busy` while the first request is in flight.
  Independent operations retain separate identities.
- Both POSTs opt out of unauthorized replay. Other mobile request modes retain
  their existing behavior. Redirect and envelope checks reuse the existing
  conversation transport; only this protocol uses its bounded 262144-byte limit.

A saved response closes only the exact dispatched operation after its mandatory
receipt matches the original owner, command/hash/epoch, operation hash, revision,
action and target. HTTP200 alone is insufficient. Closure and the local
closed-intent guard occur after atomic ciphertext replacement; visible
publication is separately gated. A patient change after rename suppresses the
old publication and cannot recreate that operation. No group refresh is needed
to acknowledge a factual winner.

Known stale-epoch, changed-input/event/version, closed-day, expired-Undo or
changed-patient refusals retain a permanent hold. Busy/unavailable/network
outcomes remain unresolved. No hold is lowered and no CAS/UUID is renewed.
Unknown operations cannot be discarded. Explicit queued-only discard and local
reset, plus waiting transitions, now accept a current-server guard inside their
actual patient transaction; existing core callers retain their prior API.
The new controller always supplies the guard. No queue-wide epoch sweep occurs.

Logout synchronously closes the controller lifetime, then cancels its owned
network work and clears lease/permission/key handles. Ciphertext remains bound
to the original Auth namespace and immutable patient/epoch. Snapshot bodies are
published only under the actual current patient/epoch grant; foreign entries
remain metadata-only.

## Evidence and integration gates

The unchanged public codec fixture is pinned at SHA256
`da84f8538ded15873383dd38e3611db493e9f079d14742ec8f1c623354618f63`.
Its standalone input/saved golden uses a placeholder CAS different from its
projected current group. That placeholder is explicitly refused by preparation.
Positive Save controller unit responses are clearly controlled echoes bound to
the operation built from the actual group CAS; they are not new SQL/SDK evidence.

The unchanged actual HTTP lifecycle fixture at SHA256
`f0037fb5da38db2ab3806d97f5d341f5ce82a5304f69c1e3618f2320dba6cc1b`
provides a coherent UndoSave path: revision7/current CAS/last-operation target
reconstruct native operation hash
`c108db45f4b005d83e4c42a363ca55e8cb969f48a09be5b1990f8f44ceade519`,
which matches its original revision8 ACK without changing IDs or hashes.
URLProtocol tests establish native fixture/transport compatibility, not a new
connected native, staging, provider or production run.

Save/Undo UI and factory composition remain separate gates. A future consumer
must record the acknowledged edit revision before refreshing current group facts,
keep the immutable original six sections clearly historical after an edit, and
refresh Food/Today using official readers. Read failures cannot revoke an ACK or
substitute old original macros as current. Linked clarification, authenticated
native/server end-to-end QA and release activation remain unimplemented here.
No nutrition, daily, registration, reward, analytics or stored feedback is
recalculated or rewritten by this client controller.

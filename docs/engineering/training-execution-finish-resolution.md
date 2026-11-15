# Exact recovery of a pending training finish

This is an additive protocol behind the existing training-completion gate. It does not enable that gate, migrate staging, activate native v2, or establish TestFlight/device acceptance.

## Request and authority

`POST /api/mobile/v1/training/execution-v2/:sessionId` accepts a separate closed envelope:

```typescript
{
  schema: 'training.execution.finish-resolution.v1',
  mode: 'observe',
  command: originalImmutableFinishCommand,
}
```

`mode` is `observe` or explicit `withdraw`. The nested command is the unchanged `training.execution.finish.v1` object. The path, original epoch header, owner header and `tresolve1:<mode>:<operation_id>` key must bind that exact command. This capability cannot be used on the actual finish writer or as a progress command. Existing progress, completion and cancellation readers remain strict.

The original live login, non-admin owner and entitlement are checked around the operation. The runtime discovers the current clinical epoch independently; it does not adopt the old command epoch as current write authority. SQL serializes original operation, current state and withdrawal under the existing owner/Auth lane. An expired or replaced login never grants recovery authority.

## Response meaning

The closed `training.execution-finish-resolution.v1` response contains the request mode, operation/session/hash/original epoch/revision, observed current scope, independent current execution, and either its own completion proof or its withdrawal marker.

| Status | Meaning and native action |
| --- | --- |
| `available` | The exact original completion exists. A terminal receipt can retire only its matching pending operation. Its own reservation can permit one explicit identical finish retry. A different current completion remains independent. |
| `ready` | No original completion is acknowledged; the unchanged command can be explicitly retried once against the observed current state. |
| `pending` | Another cancellable reservation, temporary clinical unavailability, missing session or unproved revision. Keep the exact pending slot and do not submit another workout. |
| `fenced` | No original receipt, but terminal state, an advanced revision, passed date or changed epoch permanently prevents future application of that exact command. Retire only that operation without inventing a workout receipt. |
| `withdrawn` | Explicit withdrawal has a durable exact future-denial marker. Retire only that operation; keep independently saved history. |

A changed epoch proves only that the old command cannot be applied in the future. It does not prove that no historical effect existed before a reset. Old executions are never relabelled under the new epoch. A generic 404, timeout, malformed response or someone else's receipt cannot retire the slot.

## SQL preservation and concurrency

Migration `20261115034000_training_execution_finish_resolution.sql` checks the original begin body hash before moving it unchanged behind a revoked private function and a public marker guard. It does not replace workout, clinical, energy or strength writers.

If an exact original reserved completion exists, withdrawal uses the existing cancellation receipt. If it is already completed, completion wins and the saved workout remains. If no completion/admission exists, withdrawal persists only owner/Auth/session/operation/epoch/revision/hash/time metadata in a private RLS table. It stores no report, media or clinical snapshot. Owner deletion cascades to its markers. Markers survive execution resets to deny delayed original submissions. Other-domain or unlinked admitted commands are refused rather than normalized into a cancellation.

The service role can execute only the two public original-login RPCs and the guarded existing begin function; it cannot read the marker table or call the moved private writer. Both lock orders are required QA: reservation before withdrawal yields its real cancellation; withdrawal before reservation denies the late begin. Neither path may create a workout.

## Native and feedback behavior

There is one existing Keychain actor/slot, with exact compare-before-delete. The new retirement method accepts only a validated permanent fence or withdrawal. Actual completion receipts retain their separate acknowledgement method. Recovery is explicit, uses no authorization refresh, and never performs a second automatic write after a failed POST.

The model refreshes the original account's home before publishing a terminal recovery, clears old-epoch presentation when scope has changed, and preserves another device's actual current completion. Its notice distinguishes cancelling a future resend from a historical workout result. Current completed education may be read through the existing optional reader; recovery never invokes the education writer or repeats a registration/reward.

## Qualification boundary

Local qualification includes original SQL, real route/service/SQL with synthetic external Auth/entitlement, both concurrent lock orders, preserved original database state, and native transport/model/Keychain using captured real SQL/public packets. These proofs do not substitute for guarded staging migration, current installed build verification, connected UI/device QA, TestFlight distribution or Roberto's acceptance. The overall T1–T7/all20 plan remains active until its complete contract is met.

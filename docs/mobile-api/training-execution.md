# Training execution — T5 implementation in progress

The approved conversational plan remains the delivery contract. The current source-only increment adds a pure preparation kernel. It is **not** installed as an endpoint or storage writer, and does not yet deliver persisted per-exercise execution to clients.

`training-execution-kernel.ts` projects the server-owned current training plan and prepares start/update transitions. The selected plan UUID/version/content hash and exercise ordinals are pinned in the session. Two exercises with the same name retain different identities. Recommendations remain separate from actual set UUIDs, repetitions, kilograms, duration and completion; missing actual values remain null, and zero stays zero.

Closed commands support starting, saving/removing a set, marking an exercise and abandoning the session. They reject client owner, clinical, calorie or XP overrides. Marking an exercise does not seed prescribed sets, write a workout, credit a block or change the food budget. A completed registration remains a separate future integration with the existing protected workout service, exactly once per execution session.

Updates require original owner/Auth, epoch, timezone, open session day and revision. The session day is checked against the actual start instant in the pinned timezone; progress may cross midnight while that original day stays open. A receipt must belong to this session and its chronology. Replaying an accepted operation returns its immutable receipt alongside current state, including after abandonment/day closure; it never restores an old state.

The persistence adapter must lock the original owner/epoch, recapture authoritative scope and atomically compare revision, store the new state and insert a unique operation receipt with its minimal audit delta. An in-memory kernel result is not durability. The private SQL store, concurrency/role/reset/account-deletion gates, original-Auth client transport, reopen recovery, single protected completion, user-initiated sharing and connected iOS/TestFlight qualification remain to be implemented/verified before activation. No new public capability or migration was deployed in this source increment.

Evidence: 33 behavioral tests including the two start-date/receipt chronology regressions, plus the existing full admin regression suite. Runtime, native per-exercise persistence and Roberto acceptance remain unverified.

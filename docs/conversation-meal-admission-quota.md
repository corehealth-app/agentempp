# New meal command admission budget

The additive quota migration extends
`admit_conversation_meal_command_fenced(uuid,jsonb,uuid)` with the action
`rate_limited`. The caller must map it to HTTP 429 and must not automatically retry
or create a different command UUID to bypass the refusal.

At most ten fresh command identities per authenticated owner and current epoch
are admitted inside the inclusive rolling 60-second window. The clock is
`clock_timestamp()` after the owner, existing epoch and command locks. The
existing owner lane serializes concurrent final-slot admissions. A rolled-back
transaction does not consume a slot. A refused command creates no tombstone,
personal source, interpretation attempt or domain effect.

Tombstone and expected-epoch checks run first. An existing current UUID then
resolves replay or changed-input conflict before reading the quota clock or
counting slots. Replay does not consume another slot or invoke a provider.
Negative or uncertain meal intents still count when first admitted; admission
precedes semantic preparation.

This reuses the threshold ten and inclusive rolling-minute boundary of
`flow-chat-service.ts`. Its unit is fresh command admissions in the current
epoch. Legacy Flow counts executions and retries; this is not an aggregate
limit across legacy endpoints or resets. Existing authority and UUID reset
fences remain mandatory. The old unfenced admission RPC is unchanged. No
existing migration is edited, and no route or public flag is activated here.

Real local PostgreSQL qualification includes 34 assertions, three blocking
races (final slot commit/rollback and reset), the previous fenced admission and
journal/semantic/writer/feedback neighbors, and predecessor restoration followed
by migration rollback/reinstallation. Existing rows and other schema definitions
are preserved; reinstallation restores the qualified function definition/ACL
exactly. All synthetic rows and tracked
actors are removed. Private evidence is retained under the task's
`T3-ADMISSION-QUOTA` directory. The same local stack is handed back running for
root's connected QA; no cloud resource or provider request is created.

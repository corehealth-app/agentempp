# Ordinary photos in Flow — private preparation

`conversation_photo` is an additive, nonclinical media purpose. It does not
establish consumption, performed activity, a body assessment or a reward.
The normal authenticated media routes still own upload/completion/read/delete.
Creation additionally requires a matching `X-Conversation-Owner` patient UUID.

Creation is off unless all mobile predicates are true:

- `MOBILE_CONVERSATION_PHOTOS_ENABLED=true`
- `MOBILE_CONVERSATION_INTAKES_ENABLED=true`
- `MOBILE_CURRENT_CLINICAL_PROJECT_REF=xitugspwfxkcluxvrdeg`
- the exact staging Supabase origin (a trailing slash is also accepted).

The worker independently requires the photos flag, the exact staging origin,
and an explicit `media-clinical-staging` or `media-conversation-staging` function
set. Missing/changed configuration
does not fall back to the legacy image purpose. The live purpose is checked
after configuration/download waits and before each new paid model request.
An in-flight request cannot be undone; later requests and result publication
are refused after revocation is observed.

The analyzer classifies first. Only meal, equipment and nutrition-label
analysis is allowed. Body, scale, other or unrecognized classifications become
a closed `conversation.image-result.v1` unsupported result. The generic,
body and scale analyzers are never fallback paths for this purpose. Ready
results are observations only, with unknown label nutrients kept null. Raw
answers, token usage and provider error text do not enter the public result.

The SDK chain uses at most three requests per worker attempt, each with a
12-second timeout and no SDK retries, sharing a 40-second abort signal.
Existing worker retries remain; this is not a claim that one event costs only
one inference attempt. Existing image-purpose behavior remains separate.

The existing private `meal-photos` infrastructure and ordinary-photo 30-day
`retention_until` policy are reused. No bucket or paid environment is created.
The new kind and immutable source metadata cannot be adopted by retagging an
older row. Existing body/signup/reevaluation retention rules are unchanged.

Deployment must apply `20261106021433_conversation_photo_purpose.sql` before
shipping callers that use the new kind. Its four constraint expansions preserve
the installed predicates and reject unknown catalog drift. This is not a
general migration-repair or database-push procedure.

Public activation remains pending: qualify upload→worker→typed lineage,
negotiate public media provenance and native ACK, and verify the deployed
ordinary-photo retention scheduler. The restricted staging function set does
not itself prove that the ordinary 30-day cleanup runs. Do not promise automatic
disposal from a retention date alone. The old public intake protocol continues
to hold media, including already persisted selection/recovery paths.

The new conversational staging set additionally prepares a scoped ordinary-photo
and audio expiry handler. See [worker qualification](conversation-media-worker.md).
Existing function sets and production membership remain unchanged; live scheduler
and Storage disposal still need their own qualification.

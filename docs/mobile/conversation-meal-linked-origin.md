# Cold linked meal origin

Additive read-only protocol for the Flow restart path. It does not change the v1/v2 journal, feedback winner fences, admission, calculation, writes, or rewards.

`GET /api/mobile/v1/conversation/meal-commands/{child-command-id}/origin`

Uses existing-account patient authentication and entitlement, the existing conversation flag, and the current clinical scope. Required headers are `Authorization`, `X-Conversation-Owner` and `X-Conversation-Epoch`. No query parameters, input hash hint, body, or idempotency key are accepted. The server discovers the original hash from the owned service-only state; it never derives that hash from a public journal event.

A successful response is the normal closed mobile `data`/`meta` envelope, HTTP 200, `Cache-Control: no-store`, `Vary: Authorization`, `X-Conversation-Protocol: meal-linked-origin-v1`. Its data contains exactly:

- `schema: conversation.meal-linked-origin.v1`
- `auth_user_id`, `owner_id`, `epoch`, `observed_at`
- `parent_binding`, `child_binding`, `parent_decision_hash`
- the immutable original `receipt` of `conversation.meal-continuation-effect.v1`

Bindings keep the real protocols (`conversation.command.v1` / `meal.report` and `conversation.clarification.v1` / `meal.clarify`), original hashes and admission timestamps. They are qualified through existing `read_conversation_meal_edit_state` and `read_conversation_meal_continuation` calls and their complete private parsers. Auth, owner mapping, epoch and observation clocks are rechecked around the reads. A final route check retains the original bearer and authenticated mapping. Missing, stale or conflicting data is refused; no new admission, retry, source capture, provider call, feedback generation or mutation occurs.

The iOS client treats a registered fulfillment in journal v3 as a locator only. It validates the owned origin against the original public meal facts, then loads the existing current meal group using the genuine child hash. The group's complete original receipt must equal the independently recovered identity. Current group/CAS/day/Undo policy alone controls editing. Existing Save and Undo controllers remain responsible for durable operations. Reopening or reading creates no ACK, record or reward.

Qualification is recorded in the active completion checkpoint. Unit fixtures demonstrate contract and controller behavior; they are not proof of connected staging, TestFlight distribution or Roberto acceptance.

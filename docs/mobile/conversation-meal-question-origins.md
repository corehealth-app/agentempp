# Recovering a meal question after reopening Flow

`GET /api/mobile/v1/conversation/intakes` discovers original meal-question lookups. The existing POST at that path remains the neutral reporting operation. GET requires the authenticated patient, entitlement, existing intake capability and matching `X-Conversation-Owner` / `X-Conversation-Epoch` headers.

The response uses `X-Conversation-Protocol: intake-question-origins-v1`, `Cache-Control: no-store` and the closed `conversation.meal-question-origins.v1` / `lookup_only` data contract. It contains genuine intake bindings, selected typed-meal lookup metadata, read-only source labels and pagination. The selection decision hash belongs to routing; it is not the typed meal decision hash used by an answer.

Discovery reuses the complete private journal3 parser and its existing STABLE database reader. Only primary intake events with an eligible meal terminal decision and a real unfulfilled question produce candidates. Reply and fulfillment descendants do not create another candidate. There is no new table, migration, provider call, capture, registration, feedback generation or reward.

The limit is 1–25, default 10. An optional cursor uses the existing canonical owner/epoch-bound journal cursor. Pagination counts all history events, so an empty candidate page can still have `has_more: true`. Clients must retain the cursor and offer explicit pagination rather than claiming that the first page is an exhaustive pending inbox.

An origin is a selector, not an answer lease or a saved acknowledgment. On user selection, the native client reads the current parent through the existing focused question GET before opening the existing quantity or meal-type form. The original patient lease, current grant, epoch and selected child must still match after the read. The existing answer POST retains the final source, day and revision checks. A question observation does not guarantee that the day will remain open until submission.

Previously queued answers retain their original encrypted body, reply ID and reconciliation path. Discovery does not replace them, reconstruct an original report, repeat an intake or produce a new factual effect. Public historical journal3 responses and their immutable receipts remain unchanged.

This interface supports recovery of persisted typed meal questions. Generic routing and workout answer lifecycles require their own supported continuation paths.

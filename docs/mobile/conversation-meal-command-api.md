# Conversation meal command API (dormant)

This additive transport composes the existing meal command journal, durable
semantic attempt, shared nutrition calculator, atomic writer and frozen original
feedback. It does not enable the Flow UI or replace existing registration routes.

`MOBILE_CONVERSATION_COMMANDS_ENABLED=true` enables these routes only when the
existing current-clinical runtime selects staging `xitugspwfxkcluxvrdeg` and its
exact HTTPS Supabase origin. The default is off. Invalid configuration never
falls back to the protected legacy environment. Authentication and the existing
entitlement check apply to all three routes, including capability discovery.

## Session and identity

`GET /api/mobile/v1/conversation/session` returns the normal mobile
`{ data, meta: { api_version, request_id } }` envelope. Its data has exactly:

```text
schema: conversation.session.v1
auth_user_id: authenticated Supabase Auth subject
owner_id: canonical patient ID
epoch: current server authority epoch
observed_at: server observation time
meal_command_protocol: conversation.command.v1
```

Auth subject and patient ID may differ. The native lifecycle and encrypted
storage namespace remain keyed by Auth subject; each queued intent must also
retain its original authenticated patient ID and server epoch. Never infer the
patient from the Auth subject, migrate an unbound intent by guessing, or retag an
old command with a new epoch. Session discovery is an observation, not write
authority; SQL admission enforces the epoch under the owner/reset locks.

## Submit and reconcile

`POST /api/mobile/v1/conversation/meal-commands` accepts the closed existing
`conversation.command.v1` meal report, at most 16,384 UTF-8 bytes. Duplicate JSON
keys and extra authority fields are rejected. Headers:

```text
Idempotency-Key: cmsg1:<original command UUID>
X-Conversation-Epoch: <original server epoch>
X-Conversation-Owner: <original canonical patient ID>
```

The original body, UUID and hash survive technical retries. A separate genuine
consumption receives a new UUID, even if its text matches an earlier meal. The
public driver fences *every* internal authority/recovery read against the
original epoch before calculation or effects; checking only the first read or
the final response is insufficient across reset/concurrent admission.

`GET /api/mobile/v1/conversation/meal-commands/<commandId>` reconciles only, with
`X-Conversation-Epoch`, `X-Conversation-Owner` and `X-Conversation-Input-Hash`. It does not admit, invoke
the model, calculate, initialize a day, write food, enrich a receipt or reward.

The owner header is a precondition, never identity/write authority: a valid
but different patient is refused with `conversation_patient_changed` before
constructing the service, even if two patients happened to share an epoch.
Missing or invalid owner/epoch/hash headers are rejected as validation errors.

Both return `Cache-Control: no-store`, `Vary: Authorization` and
`X-Conversation-Protocol: meal-command-v1` inside the established mobile envelope.
The server-owned admission limit is ten **new command IDs** per patient/current
epoch in a rolling 60 seconds. Replay/conflict and reset checks precede quota;
repetition does not consume another slot. A known refusal returns HTTP 429 with
`conversation_admission_rate_limited`, with no model claim or fresh command row.
This new admission counter is separate from the older Flow execution limit.

## Factual success and optional historical presentation

HTTP 200 alone never acknowledges an outbox intent. A saved packet has schema
`conversation.meal-command-result.v1`, status `saved`, original patient, command,
input hash, epoch and admission time, the actual mandatory
`conversation.meal-effect.v1` receipt, and nullable guarded feedback. The client
must bind this exact packet to its original ticket and currently authorized
session/patient/epoch before atomically removing that one encrypted entry.

The optional `conversation.feedback-presentation.v1` wrapper projects the
immutable original v1/v2 receipt through a fresh current clinical guard. It never
exposes raw private command/source/clinical capture. All six policy hide flags,
including food budget, are preserved. A new read can change the guard's two
observation timestamps or mask guidance after a health change; the original
factual receipt remains unchanged. Optional presentation failure means null
feedback, never another model call or food write. A lost commit response is
reconciled through one authoritative read containing binding and receipt in the
same snapshot, without repeating the commit.

Other replies have schema `conversation.meal-command-state.v1` and the original
patient/command/hash/epoch. `pending` is HTTP 202; `absent` and `not_recorded` are
HTTP 200. Only `not_recorded` includes `reason` (1–80 lowercase letters or `_`)
and unique `food_indexes` (0–29, at most 30). None is proof of a food effect or a
saved-result ACK. A 401 on a command POST must not trigger transparent replay;
unknown outcomes require explicit reconciliation with the same identity/body.

## Remaining activation gates

- GET currently recovers saved effects, not durable terminal negative or
  clarification decisions; a command without an effect remains pending on GET.
  Persist those decisions and continuation links before the complete chat UX.
- Real native transport/controller, paginated conversation, direct item save,
  five-minute versioned undo and clinical-policy refresh on display remain
  separate integrations. Do not activate the prototype four-tab UI as a finished
  Flow, infer a meal slot from fabricated personal windows, or silently approve
  nutrition-label metadata.
- Multimodal provider/device paths, full app reopen/panel consistency, staged
  migrations/deployment, TestFlight and installed-version acceptance still need
  qualification before delivery. Existing v1/v2 receipt and registration readers
  remain compatible.

## Qualification to date

The local connected QA used actual Node HTTP requests through the production
handler/auth/entitlement/service functions, local GoTrue, PostgREST and Postgres;
only the external model response leaf was controlled. Two confirmed Auth users
had IDs different from their patient IDs. It exercised 401/402, six-section saved
feedback, read reconciliation after a lost response, replay without duplication,
equal legitimate consumptions, A/B isolation, milk/whey, quota refusal and old
epoch refusal after reset. All task-owned Auth sessions/tokens/audit and domain
fixtures were removed; original global fingerprints were restored. This is not
deployed Next, native device, real-provider or customer acceptance evidence.

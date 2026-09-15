# Performe AI Client Beta with Flow — Design Specification

**Date:** 2026-09-14
**Status:** approved by the human mandate `START_PERFORME_AI_CLIENT_BETA_WITH_FLOW_V1`
**Product:** Performe AI
**Agent:** Flow

## 1. Scope

This checkpoint delivers a local, authenticated text-chat vertical slice while preserving the existing five-tab iOS product. It includes secure runtime configuration, the existing Supabase email/password authentication and session lifecycle, an authenticated `/api/mobile/v1/flow/chat` BFF surface, per-patient persistent history, the real existing Flow agent pipeline, a native SwiftUI conversation, recoverable failures, cancellation, offline behavior, tests, and local builds.

This checkpoint does not deploy, call staging or paid providers, migrate a remote database, use production data, link WhatsApp to iOS, enable voice/media/streaming/push/billing, change signing, or distribute a build.

## 2. Authority and base

The documentary authority is the committed dossier at `b4c09e80190fd6ce5c5f59b5193f8a6621554854:docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`, plus the committed rebrand spec/plan and the binding decisions in the current mandate. The product code base is `277873755bf29771a10b5f362b522c2e6a6c21d6`, the dossier's exact integrated CI-2 auth/session checkpoint. The frozen CI-3 tree is evidence/support work and is not a product implementation base.

The new worktree is `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1` on `codex/performe-ai-client-beta-flow-v1`, created directly from that SHA. The CI-3 worktree remains frozen and read-only.

## 3. Existing architecture reused

- iOS keeps target, scheme, module, bundle identifier, namespaces, persisted keys, accessibility/telemetry identifiers, signing, assets, and the five tabs under internal name `BodyFlow`.
- `SupabaseAuthenticationService`, `AuthenticationSessionStore`, `SessionLifecycleCoordinator`, `PatientWorkRegistry`, `KeychainSecureStore`, and `MobileAPITransport` remain the single auth/session/transport stack.
- The BFF keeps `createMobileRoute`, verified Supabase bearer identity, patient bootstrap, entitlement checks, service-role use only on the server, typed envelopes, request IDs, `no-store`, `Vary: Authorization`, strict same-origin HTTPS, and the existing idempotency store.
- `@mpp/agent` remains the only Flow agent pipeline. The mobile adapter supplies an already authenticated domain `userId`; it must not fake a WhatsApp number or create/link a second identity.
- The existing `messages` table is the canonical conversation store. Mobile rows use `provider = 'mobile_flow'`; history and prompt context are provider-scoped to prevent channel leakage. The logical first-beta conversation identifier is the stable server-owned value `flow`; no caller-supplied owner is accepted.

## 4. Runtime configuration and authentication

Release reads only these injected Info.plist classes: `PERFORME_SUPABASE_URL`, `PERFORME_SUPABASE_PUBLISHABLE_KEY`, and `PERFORME_MOBILE_API_ORIGIN`. Values are not committed. Supabase and BFF origins must be absolute HTTPS origins without path, user info, query, or fragment; service-role material is never accepted by the client.

Debug UI-test/demo arguments retain explicit doubles. Release never falls back to demo auth or a hard-coded endpoint. Missing or invalid values fail closed through unavailable capabilities.

The existing session lifecycle remains authoritative for Keychain storage, refresh single-flight, session restoration, request leases, stale-response suppression, logout cancellation, invalid-grant handling, and user-switch cache boundaries. The app root must wire the validated Release configuration into that existing graph.

## 5. BFF conversation contract

`GET /api/mobile/v1/flow/chat?limit=N` returns `{ conversation_id: "flow", messages: FlowMessage[] }` for the authenticated patient only.

`POST /api/mobile/v1/flow/chat` requires an `Idempotency-Key` and body `{ text: string }`, where trimmed UTF-8 text is 1–4000 characters and the body is bounded to 16 KiB. It returns the persisted assistant message and the stable conversation identifier.

`FlowMessage` contains `id`, `conversation_id`, `role` (`user` or `assistant`), `content`, `state` (`processing`, `completed`, or `failed`), `request_id`, and `created_at`. Provider metadata is not exposed. The idempotency key is stored only through the existing idempotency subsystem and stable provider message IDs; it is not returned.

The service sequence is: validate auth/entitlement and rate limit → claim idempotency → persist inbound `processing` → call authenticated Flow pipeline → persist assistant `completed` → mark inbound `completed` → return. Provider failure marks the inbound row `failed` and returns a typed 502 without fabricated assistant content. A completed replay returns the original stored response. History is ordered oldest-first after a bounded newest-first query.

The first checkpoint uses a database-backed ten-inbound-messages-per-rolling-minute patient limit and returns 429. This is deliberately local to the existing database and creates no new infrastructure.

## 6. Agent and server-authoritative context

`processAuthenticatedMessage` adapts the existing pipeline with a trusted `userId`, `provider = 'mobile_flow'`, and provider-scoped recent messages. It reuses official profile, progress, targets, protocols, Block 7,700 kcal, and deterministic tools. It adds an immutable Performe AI/Flow channel policy to the system prompt.

For this first mobile checkpoint, the tool allowlist is read-only: progress, metrics, period summary, and protocol reevaluation queries. Mutating tools are absent from the LLM tool schema. Flow must say that recording/changing health data requires an explicit structured confirmation flow; sending a chat message is never that confirmation. This is deny-by-default and preserves existing WhatsApp behavior.

The model interprets and explains; official numbers remain server-produced. No chain-of-thought, raw provider payload, bearer, health content, or PII is logged.

## 7. iOS repository and UX

The new `FlowChatProviding` capability owns history/send contracts. `MobileFlowChatRepository` encodes/decodes the BFF contract through `MobileAPITransport`; `UnavailableFlowChatRepository` fails closed; debug UI-test fixtures are explicit doubles only.

`FlowChatModel` is root-owned for the authenticated shell and scoped to its `userID`. It exposes loading, empty, loaded, sending, recoverable error, offline, retry, and cancellation states. It discards results whose session/user generation no longer matches and clears its messages synchronously when the authenticated shell disappears.

`FlowChatView` is reached from a prominent card on the existing “Hoje” route. It uses a `ScrollViewReader`/lazy stack, textual bubbles, a multiline composer, send and cancel controls, processing indication, retry, VoiceOver labels/identifiers, Dynamic Type-friendly layout, and Portuguese-first copy with English catalog structure. It does not add a tab.

Messages appear as persisted only after BFF confirmation. The composer may show a transient local sending state, but it must not fabricate a saved or answered row.

## 8. Public naming

Public text reached by the checkpoint uses “Performe AI” for the product and “Flow” for the agent. `CFBundleDisplayName`, `CFBundleName`, auth/onboarding identity, chat presentation, and pertinent errors are updated textually. Historical/internal `BodyFlow` identifiers and preserved assets remain unchanged. Because no new logo/assets are authorized, rebrand status cannot exceed partial while inherited visual assets remain.

## 9. Security and privacy acceptance

- Every route validates bearer, confirmed email, active patient identity, entitlement, and server-derived ownership.
- History/send never accept `user_id`, auth identity, provider, conversation owner, model, tool, or request ID from the JSON body.
- Cross-user rows are excluded by mandatory `user_id` and `provider` predicates; tests prove this contract.
- Service role remains server-only. Database tables retain RLS and explicit grants; this checkpoint adds no remote migration.
- HTTPS origin validation, redirect rejection, request cancellation, session lease validation, one safe 401 refresh, and no unsafe automatic retry remain intact.
- 401/403/429/5xx, timeout, offline, cancellation, invalid response, and superseded session map to explicit non-success UI states.
- Logs include only a request ID and safe error class/code, never secrets or message content.

## 10. Acceptance criteria

Local validation requires: clean authorized worktree; two documentary reviews with Critical 0/Important 0; Release configuration wired without a demo fallback; existing auth/session regression tests green; authenticated BFF history/send tests; cross-user, idempotency, rate-limit, provider-failure, context-scope, and read-only-tool tests; iOS repository/model/view tests; Debug simulator and unsigned Release builds; functional simulator evidence using explicit local doubles; final Security/Auth and Product/Chat reviews at Critical 0/Important 0; and CI-3 preservation rechecked.

Provider doubles prove local contracts only. Without authorized Supabase/BFF/OpenRouter credentials and an applied staging schema, report `AUTH_RUNTIME_INTEGRATION_NOT_VERIFIED` and do not call the external integration verified.

## 11. Alternatives considered

1. **Reuse `messages` and adapt the existing pipeline (selected):** preserves one agent, one official context model, and existing operational controls with a small channel adapter.
2. **Build a second mobile agent:** rejected because it duplicates prompts/tools, risks divergent health calculations, and violates the mandate.
3. **Bridge through the WhatsApp/Inngest worker:** rejected for the first synchronous text slice because it would fake a WhatsApp identity, mix histories, and introduce an unnecessary queue dependency. A later async transport can be evaluated without changing the public contract.

## 12. External gates

Staging E2E and private-device distribution are explicitly deferred. The next gate is the smallest existing-environment test of real login → Flow send → provider response → persisted history → logout/user switch, with named secrets supplied only to the environment, migration review if required, rollback/closeout, and no new paid resource by default.

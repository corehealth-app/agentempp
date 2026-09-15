# Performe AI Client Beta with Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and locally verify secure Release auth/session wiring plus an authenticated native Flow text-chat vertical slice for Performe AI.

**Architecture:** Keep the existing Supabase auth/session/Mobile API stack and the existing `@mpp/agent` pipeline. Add a provider-scoped BFF adapter over `messages`, then a session-scoped SwiftUI repository/model/view reached from the existing Today navigation.

**Tech Stack:** Swift 6.3, SwiftUI/iOS 26, Xcode 26.6, TypeScript 5.7, Next.js 15 Route Handlers, Supabase/Postgres, Vitest 2, pnpm 10.33.2.

**Spec:** `docs/superpowers/specs/2026-09-14-performe-ai-client-beta-flow-v1.md`

## Global Constraints

- Public product name is exactly `Performe AI`; agent name is exactly `Flow`.
- Preserve target/scheme/module `BodyFlow`, bundle `com.bodyflow.app`, internal identifiers, assets, five tabs, and existing journeys.
- No remote calls, provider calls, dependency downloads, migrations, push, PR, merge, deploy, signing changes, paid infrastructure, WhatsApp linking, billing, Android, or CI-3 mutation.
- All production behavior follows RED → observed expected failure → minimum GREEN → focused regression.
- Release fails closed; doubles stay in Debug/tests/previews and are never external-integration evidence.

---

### Task 0: Authority, base, preservation, and baseline

**Files:**
- Create: `docs/superpowers/evidence/2026-09-14-performe-ai-client-beta-flow-v1-baseline.md`
- Create: `docs/handoffs/2026-09-14-performe-ai-client-beta-flow-v1-addendum.md`

**Interfaces:**
- Consumes: immutable Git objects and frozen CI-3 ledger.
- Produces: exact base/worktree/tool/test evidence and the allowed scope for Tasks 1–10.

- [x] Verify host, Git state, documentary authority, exact CI-3 metadata/hashes/staging/processes, and create the single worktree directly from `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- [x] Use cached pnpm 10.33.2 offline; run mobile BFF, agent, and iOS auth/session focused baselines serially.
- [x] Record component classifications and pre-existing warnings without treating doubles as integration.
- [ ] Recheck CI-3 and the new worktree after every implementation commit.

### Task 1: Release environment and BFF configuration

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/App/PerformeRuntimeConfiguration.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Resources/Info.plist`
- Test: `apps/ios/BodyFlow/BodyFlowTests/PerformeRuntimeConfigurationTests.swift`

**Interfaces:**
- Produces: `PerformeRuntimeConfiguration.load(from:) -> PerformeRuntimeConfiguration?`, containing validated `SupabaseAuthConfiguration` and `MobileAPIConfiguration`.

- [ ] Write tests proving complete valid dictionaries load, missing/invalid values fail closed, and service-role-looking keys are rejected; run the suite and observe missing-type failures.
- [ ] Implement the small loader over the three `PERFORME_*` Info.plist keys; rerun to GREEN.
- [ ] Wire `BodyFlowApp` to pass both validated configurations into `AppDependencies.make`; prove Release has no hard-coded fallback.

### Task 2: Authentication/session checkpoint and public identity

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/DesignSystem/BrandIdentity.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Resources/Info.plist`
- Modify: `apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings`
- Modify: `apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings`
- Test: `apps/ios/BodyFlow/BodyFlowTests/BrandIdentityTests.swift`
- Test: existing auth/session suites.

**Interfaces:**
- Consumes: Task 1 validated config and the existing session coordinator.
- Produces: real Release auth graph branded Performe AI, with Flow remaining the agent.

- [ ] Add failing naming assertions for `BrandIdentity.productName`, agent name, and Info.plist display name; observe RED.
- [ ] Apply textual rebrand only and rerun GREEN.
- [ ] Run valid/expired/revoked, concurrent refresh, logout, switch A→B, stale-response, Keychain, redirect, and Release-no-mock regression tests.
- [ ] Review only auth/config/rebrand paths, then create local commit `feat(beta): add real iOS authentication and session`.

### Task 3: Authenticated agent and conversation contracts

**Files:**
- Modify: `packages/agent/src/types.ts`
- Modify: `packages/agent/src/pipeline.ts`
- Test: `packages/agent/src/mobile-authenticated-pipeline.test.ts`
- Modify: `apps/admin/src/lib/mobile-api/contracts.ts`
- Create: `apps/admin/src/lib/mobile-api/flow-chat-contracts.test.ts`

**Interfaces:**
- Produces: `processAuthenticatedMessage(deps, { userId, providerMessageId, text, timestamp })`; `flowChatInputSchema`; `FlowMessage` DTOs.

- [ ] Write failing tests proving trusted user ID bypasses `ensure_user_initialized`, recent context filters `provider=mobile_flow`, the Performe AI/Flow policy is injected, and mutating tools are absent; observe RED.
- [ ] Extract one internal pipeline entry path while preserving `processMessage` behavior; implement the authenticated adapter and provider filter; rerun focused agent tests to GREEN.
- [ ] Add RED/GREEN contract tests for strict `{text}`, trim, 1–4000 characters, and rejection of ownership/tool/provider fields.

### Task 4: Flow persistence, ownership, idempotency, and rate limit

**Files:**
- Create: `apps/admin/src/lib/mobile-api/flow-chat-service.ts`
- Create: `apps/admin/src/lib/mobile-api/flow-chat-service.test.ts`

**Interfaces:**
- Produces: `loadFlowHistory(deps, userId, limit)` and `sendFlowMessage(deps, input)` over `messages(provider='mobile_flow')`.

- [ ] Write failing repository tests for oldest-first history, mandatory user/provider predicates, cross-user exclusion, inbound processing→completed, provider error→failed without assistant fabrication, stable IDs, and ten-per-minute 429; observe RED.
- [ ] Implement the minimum typed repository/agent dependency interface and safe error mapping; rerun GREEN.
- [ ] Add idempotent replay/duplicate tests using the existing mobile idempotency boundary; prove duplicate sends do not call Flow twice.

### Task 5: Authenticated BFF endpoint and real Flow runtime

**Files:**
- Create: `apps/admin/src/app/api/mobile/v1/flow/chat/handler.ts`
- Create: `apps/admin/src/app/api/mobile/v1/flow/chat/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/flow/chat/route.test.ts`

**Interfaces:**
- Consumes: Tasks 3–4 and `createMobileRoute`.
- Produces: GET/POST `/api/mobile/v1/flow/chat` with bearer, entitlement, request ID, no-store/Vary, bounded JSON, and Idempotency-Key.

- [ ] Add failing route tests for GET, POST, 401/403 delegation, 429, 5xx, 16 KiB bound, typed envelopes, and no content/token logging; observe RED.
- [ ] Implement injectable handlers plus a lazy server-only OpenRouter runner; missing provider configuration returns typed failure, never a fake response; rerun GREEN.
- [ ] Run all mobile API and focused agent regression suites.

### Task 6: Native iOS chat repository

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/FlowChat/FlowChatModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/FlowChat/FlowChatProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/FlowChat/MobileFlowChatRepository.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Test: `apps/ios/BodyFlow/BodyFlowTests/MobileFlowChatRepositoryTests.swift`

**Interfaces:**
- Produces: `history(limit:)`, `send(text:idempotencyKey:)`, and fail-closed Release/debug fixture capability.

- [ ] Add failing decode/request tests for history/send, exact `/api/mobile/v1/flow/chat`, idempotency, 401/403/429/5xx, invalid envelope, timeout, cancellation, offline, and no Release mock; observe RED.
- [ ] Implement models and repository using `MobileAPITransport`; inject it through `AppDependencies`; rerun GREEN.

### Task 7: Session-scoped chat state and recovery

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/FlowChat/FlowChatModel.swift`
- Test: `apps/ios/BodyFlow/BodyFlowTests/FlowChatModelTests.swift`

**Interfaces:**
- Produces: observable history/composer/send/error state scoped to one immutable `userID` and generation.

- [ ] Add failing tests for loading/empty/success, pending send, retry with the same idempotency key, cancel, offline, and error mapping; observe RED.
- [ ] Add failing A→B and late-A-response tests proving synchronous clear and stale-result suppression; observe RED.
- [ ] Implement the minimum actor-safe model and rerun GREEN.

### Task 8: Native SwiftUI conversation and existing navigation

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/FlowChat/FlowChatView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings`
- Test: `apps/ios/BodyFlow/BodyFlowTests/FlowChatPresentationTests.swift`
- Test: `apps/ios/BodyFlow/BodyFlowUITests/FlowChatUITests.swift`

**Interfaces:**
- Consumes: Tasks 6–7.
- Produces: `.flowChat` Today route and accessible native UI without a new tab.

- [ ] Add failing route/presentation assertions for the Today-owned route, Performe AI/Flow copy, five tabs, and accessibility identifiers; observe RED.
- [ ] Implement card, list, bubbles, multiline composer, send/cancel, progress, empty/error/offline/retry, scroll-to-latest, VoiceOver labels, and Dynamic Type-safe layout; rerun GREEN.
- [ ] Run focused UI tests in explicit debug fixture mode and visually inspect the simulator; label all fixture/provider evidence as simulated.

### Task 9: Security and official-context regression

**Files:**
- Test: Task 3–8 tests and existing auth/API/agent security tests.

**Interfaces:**
- Produces: evidence for Security/Auth review.

- [ ] Prove deny-by-default mobile tools, server-owned identity, provider-scoped context, no cross-user history, idempotency/replay, rate limit, body bound, and provider error without fabricated response.
- [ ] Scan changed source for tokens, service-role values, PII/content logs, hard-coded origins, ATS exceptions, broad ignores, disabled tests, and CI-3 paths.
- [ ] Run `git diff --check`, TypeScript typecheck/lint, and focused regressions.

### Task 10: Local integration, reviews, and checkpoint

**Files:**
- Modify: `docs/superpowers/evidence/2026-09-14-performe-ai-client-beta-flow-v1-baseline.md`

**Interfaces:**
- Produces: final local checkpoint evidence and commit 3.

- [ ] Build Debug for iPhone 17 Pro simulator and run auth/chat unit/UI tests; inspect loading, empty, send, response, error, retry, cancel, offline, logout/switch fixture states.
- [ ] Build unsigned Release for generic iOS and prove no demo success path.
- [ ] Run Review A (Security/Auth) and Review B (Product/Chat); fix and repeat until Critical 0/Important 0 or report partial.
- [ ] Review the complete diff and create local commit `feat(beta): add authenticated Flow text chat vertical slice` only if its claimed checkpoint is true.
- [ ] Recheck commit chain, clean/staging state, CI-3 hashes, and record real providers versus doubles.

### Task 11: Staging E2E — not authorized in this session

**Files:** none.

**Interfaces:** consumes the local checkpoint; produces external integration evidence in a separately authorized task.

- [ ] Do not execute. Propose use of an existing staging environment, named secret classes, reviewed schema application if needed, safe synthetic patient, provider cost/owner/duration, rollback, and closeout.
- [ ] Validate real login → Flow send → real response → persisted history → logout/user switch without production data.

### Task 12: Device/private distribution — not authorized in this session

**Files:** none.

**Interfaces:** consumes successful staging E2E; produces a separately authorized signed private build.

- [ ] Do not execute. Inventory Apple access, signing/provisioning, device/TestFlight choice, privacy/support metadata, owner, expiry, and rollback only after Task 11 passes.

## Exact local execution commands

All Node commands use the already cached package manager and prohibit network resolution:

```bash
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent exec vitest run src/mobile-authenticated-pipeline.test.ts src/pipeline-context.test.ts src/pipeline-core-reads.test.ts
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/admin exec vitest run src/lib/mobile-api/flow-chat-contracts.test.ts src/lib/mobile-api/flow-chat-service.test.ts src/app/api/mobile/v1/flow/chat/route.test.ts
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent typecheck
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/admin typecheck
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent lint
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/admin lint
```

iOS RED/GREEN commands target only the named new suites until integration:

```bash
xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' -only-testing:BodyFlowTests/PerformeRuntimeConfigurationTests -only-testing:BodyFlowTests/BrandIdentityTests
xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' -only-testing:BodyFlowTests/MobileFlowChatRepositoryTests -only-testing:BodyFlowTests/FlowChatModelTests -only-testing:BodyFlowTests/FlowChatPresentationTests
xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' -only-testing:BodyFlowUITests/FlowChatUITests
xcodebuild build -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Debug -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9'
xcodebuild build -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Each first command is expected to fail because the named production symbol/file/behavior is absent. After the corresponding minimum implementation, the identical command must pass. Integration then reruns the baseline mobile/API/agent/auth/session suites recorded in the evidence document, followed by `git diff --check` and secret/mock/CI-3 scans.

## Documentary review gates

- Review 1 — architecture/security: Critical 0, Important 0 after clarifying trusted mobile identity, provider-scoped history, read-only mobile tools, Release fail-closed configuration, and no remote migration.
- Review 2 — plan/acceptance: Critical 0, Important 0 after mapping every mandate requirement to Tasks 0–12, adding exact RED/GREEN commands to execution notes, and retaining explicit external gates.

The mandate already selects inline execution after these two clean reviews. No additional product approval is required unless a new material decision, unauthorized risk, or true authority conflict appears.

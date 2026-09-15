# Performe AI Server-Owned Onboarding Implementation Plan

> **Execution constraint:** implement locally with strict red-green-refactor cycles. Do not push, deploy, publish legal documents, access remote Supabase/Vercel, run staging E2E, invoke an LLM, or touch CI-3.

**Goal:** Replace Release's synthetic/unavailable onboarding consent with a fail-closed, server-owned onboarding contract whose documents, explicit user actions, persistence, and completion are authoritative in the trusted mobile BFF and database.

**Architecture:** Add a dedicated immutable onboarding-document and acceptance domain plus a single trusted-backend PostgreSQL RPC that atomically validates current published requirements and persists profile, objective, persona, exact document actions, and completion. Extend the existing `/api/mobile/v1/onboarding` route with GET state/requirements and an idempotent full POST completion contract, while retaining the pre-existing safe partial-profile POST contract for callers that do not send `document_actions`. Add a production iOS repository over `MobileAPITransport`; Debug keeps its demo repository while Release restores and completes exclusively from server responses.

**Stack:** PostgreSQL/Supabase migrations and pgTAP-style SQL tests; Next.js route handlers, TypeScript, Zod, Vitest; Swift 6, SwiftUI, Swift Testing, Xcode Release test action.

## Safety and contract decisions

- The bearer/session boundary derives the domain user. Neither API payload nor iOS models expose a writable `user_id`, `onboarding_completed`, publication state, approval state, or official timestamp.
- New onboarding legal tables are separate from medication/routine legal tables and receipts.
- Document identity is immutable across key, version, locale, content hash, purpose, action type, effective time, and publication state. A changed document requires a new version/row.
- Embedded body and controlled HTTPS URL are mutually exclusive. URL documents carry the hash of the presented content, not a hash of the URL string. Operational URL origins come from an explicit server allowlist; no origin is invented or enabled by this change.
- No operational Terms/Privacy rows are seeded. SQL and application tests create synthetic non-`dev.*` fixtures inside rollback-only test transactions or in-memory doubles.
- Missing or stale published requirements keep Release incomplete and make the app reload requirements. Explicit actions start unchecked.
- One database transaction writes all onboarding facts, persona preference, legal actions, and server completion timestamp. The existing API idempotency ledger protects request replay/conflict; immutable unique acceptances make a retry safe even if response-ledger finalization fails after the transaction.
- The new function is callable only by `service_role`, invokes the existing trusted-backend assertion, pins `search_path`, and grants no direct client write path.
- Existing endpoints remain compatible. The legacy partial onboarding POST is selected only when `document_actions` is absent, rejects caller-owned completion (`onboarding_completed: true`), and keeps its prior response shape. The full server-owned completion contract is selected when `document_actions` is present and cannot fall through to the legacy write path.

## Concrete edit allowlist

No file outside this list may be changed without first updating this plan and explaining why in the task log.

- `docs/superpowers/plans/2026-09-15-performe-ai-server-owned-onboarding.md`
- `docs/mobile/api-v1.md`
- `docs/runbook/performe-ai-onboarding-legal-activation.md` (new)
- `supabase/migrations/20260915150739_bodyflow_server_owned_onboarding.sql` (new; the one CLI-generated migration for this task)
- `supabase/tests/bodyflow_server_owned_onboarding.sql` (new)
- `apps/admin/src/lib/mobile-api/contracts.ts`
- `apps/admin/src/lib/mobile-api/contracts.test.ts`
- `apps/admin/src/lib/mobile-api/onboarding-service.ts` (new)
- `apps/admin/src/lib/mobile-api/onboarding-service.test.ts` (new)
- `apps/admin/src/lib/mobile-api/supabase-onboarding.ts` (new)
- `apps/admin/src/lib/mobile-api/supabase-onboarding.test.ts` (new)
- `apps/admin/src/app/api/mobile/v1/onboarding/handler.ts` (new)
- `apps/admin/src/app/api/mobile/v1/onboarding/route.ts`
- `apps/admin/src/app/api/mobile/v1/onboarding/route.test.ts` (new)
- `apps/mobile-bff/src/app/api/mobile/v1/onboarding/route.ts`
- `apps/mobile-bff/src/app/api/mobile/v1/onboarding/route.test.ts` (only if route-mirror behavior needs a direct regression test)
- `apps/mobile-bff/scripts/verify-route-mirror.mjs` (frozen export hash changes only because onboarding adds GET)
- `apps/mobile-bff/src/route-mirror.test.ts` (same frozen export hash assertion)
- `apps/mobile-bff/src/source-surface.test.ts` (same frozen source-manifest hash assertion)
- `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingModels.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingRepository.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/MobileOnboardingRepository.swift` (new)
- `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/DemoOnboardingRepository.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingFlowModel.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/BodyDataStepView.swift` (review follow-up: render and select the civil birth date in the draft's declared timezone)
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingCompletionView.swift` (review follow-up: present official document actions instead of the Debug-only consent field)
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/WelcomeStepView.swift` (review follow-up: describe the locale as server-owned instead of device-owned)
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ConsentStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingContainerView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingViewSupport.swift`
- `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- `apps/ios/BodyFlow/BodyFlow/App/AppFlowModel.swift`
- `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj`
- `apps/ios/BodyFlow/BodyFlowTests/OnboardingModelsTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/OnboardingFlowModelTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/OnboardingCompletionTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/OnboardingPresentationTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/AppFlowModelTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/MobileOnboardingRepositoryTests.swift` (new)
- `apps/ios/BodyFlow/BodyFlowTests/TelemetryTests.swift` (server-owned completion ordering and authoritative restore expectations)
- `docs/performe-ai-onboarding-activation.md` (new; activation metadata only, no legal draft)

## Task 1: Establish local baseline and reproduce Release failure

1. Revalidate branch, HEAD, tree, empty index/worktree, applicable instructions, runtime versions, local database tooling, disk/memory, and absence of competing writes.
2. Run focused existing TypeScript onboarding/contract tests.
3. Run the focused iOS Debug onboarding tests and record pass/fail.
4. Run the same focused tests with the Release configuration and capture the module-resolution error.
5. Inspect derived build settings and module artifacts to establish the root cause before editing `project.pbxproj`.

## Task 2: Specify the public API contract test-first

1. Add failing Zod contract tests for GET output shapes and strict POST input: profile fields, objective, persona, document identity/action, no client-owned completion/user/time/publication fields, bounded payloads, and rejection of `dev.*` identifiers.
2. Run the focused tests and verify RED for missing contract.
3. Implement the minimal schemas/types and rerun to GREEN.

## Task 3: Build the additive database domain test-first

1. Create `supabase/tests/bodyflow_server_owned_onboarding.sql` first with rollback-contained synthetic fixtures covering immutable document versions, body/URL identity, required document absence, explicit action mismatch, stale version/hash, publication/effective time, atomic rollback, retry, exact acceptance history, cross-user isolation, RLS/grants, and trusted-backend-only function execution.
2. Run the new SQL test against the unchanged local database and verify RED because the domain/RPC is absent.
3. Create the migration through the installed project Supabase CLI's `migration new` command.
4. Implement tables, constraints, indexes, immutable triggers, RLS, explicit revokes/grants, and `complete_mobile_onboarding_atomic`.
5. Reset only the task's known local Supabase development stack if its identity and volumes are verified; otherwise use the project's isolated test mechanism without destroying state.
6. Run the new SQL test and neighboring database suites to GREEN. Run available local database lint/advisors without linking or remote access.

## Task 4: Implement server application boundary test-first

1. Add failing service/repository tests for server snapshot loading, document allowlist enforcement, current requirements, RPC payload translation, sanitized database errors, and server-owned result mapping.
2. Add failing route tests for authenticated GET and idempotent POST, replay, stale-document conflict/reload signal, payload rejection, no-store/Vary/request ID, and absence of sensitive logs.
3. Run focused tests and verify RED.
4. Implement `onboarding-service`, `supabase-onboarding`, and the GET/POST handler. Keep the existing agent-backed partial-profile command only behind the discriminated legacy contract, without changing `packages/agent`; all completion authority belongs to the new service/RPC path.
5. Export GET and POST through the dedicated BFF mirror and rerun route/import/build-surface verification.
6. Run the full Admin and mobile-BFF test/typecheck/lint/build gates as resources permit.

## Task 5: Implement the Release iOS repository test-first

1. Add failing model/repository tests for decoding server requirements, exact document identities/actions, strict submission encoding, official completion acknowledgement, transport error mapping, retry key reuse, and no `dev.*` operational identity.
2. Add failing flow/app tests for initial unchecked actions, missing-document blocking, stale-response discard, logout/user-switch isolation, server restore after relaunch, and no authenticated transition before server acknowledgement.
3. Run focused Debug tests and verify RED.
4. Implement production onboarding models and `MobileOnboardingRepository`; keep demo-only models/fixtures behind Debug boundaries.
5. Inject the mobile repository into Release, load official requirements before presenting consent, submit persona with the atomic onboarding request, and use server completion as the only transition authority.
6. Update SwiftUI consent presentation to render the server-provided document/action semantics without invented legal copy or preselection.
7. Rerun focused Debug tests to GREEN.

## Task 6: Repair and execute the actual Release tests

1. Add or refine the smallest Release regression test that proves the app module must be importable by `BodyFlowTests`.
2. Apply the root-cause build-setting correction (`ENABLE_TESTABILITY` on the app's Release build) only if the reproduced build settings confirm that hypothesis.
3. Execute the same onboarding/app/repository suites under `configuration=Release`; do not substitute Debug or a build-only check.
4. Verify no bundle ID, signing, entitlement, or runtime-mode changes occurred.

## Task 7: Documentation, regression, independent reviews, and commit

1. Document the GET/POST contract and the single fail-closed activation checklist for approved legal keys, versions, locales, purpose, action types, body or controlled URL, content hashes, effective dates, publication approval, and configured URL origins.
2. Run format/lint/typecheck/tests/build plus SQL and focused iOS Debug/Release verification. Inspect the complete output and separate pre-existing warnings from new failures.
3. Review the full diff for scope, secrets, disabled tests, widened grants, synthetic operational data, client-owned completion, and accidental project/signing changes.
4. Obtain two independent reviews: security/consent/persistence/no-bypass, then API/iOS/end-to-end-local/Release-tests. Resolve every Critical or Important item and rerun affected gates.
5. Revalidate exact parent HEAD, stage only allowlisted files, review staged diff, and create exactly one local commit with subject `feat(onboarding): add server-owned consent and completion`.
6. Verify final commit parent/tree/status without push, merge, deploy, remote migration, document publication, or E2E.

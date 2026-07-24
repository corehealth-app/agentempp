# BodyFlow Central Entitlements Implementation Plan

> **Execution:** use RED, GREEN and refactor for every behavior. Work only on
> `codex/bodyflow-entitlements-v1` in the isolated BodyFlow worktree.

**Goal:** add one secure entitlement decision for app-first access, preserve
legacy Stripe compatibility, and prepare disabled-by-default RevenueCat
ingestion without charging, configuring providers or touching production.

## Global Constraints

- Production Supabase ref `xuxehkhdvjivitduarvb` remains untouched.
- Database application and SQL validation are staging-only on
  `xitugspwfxkcluxvrdeg`, after validating the local link every time.
- Keep all 34 staging cron jobs inactive.
- Do not deploy Vercel or Edge Functions, configure secrets/providers, charge
  users, activate paywalls, create StoreKit products, start Xcode or run visual
  prompts.
- Do not read PII, raw messages, provider payloads or secret values.
- Do not modify the frozen legacy messaging subscription gate.
- Do not migrate or grandfather real users.
- Use migrations created by the pinned Supabase CLI.

## Task 1: Portable Entitlement Contracts

**Files:**

- Create `packages/core/src/entitlements.ts`
- Create `packages/core/src/entitlements.test.ts`
- Modify `packages/core/src/index.ts`

- [x] Add RED tests for exact statuses, sources, provider environments,
  patient-safe decision parsing, RevenueCat event parsing and event ordering.
- [x] Implement strict Zod contracts and deterministic helpers.
- [x] Verify focused core tests and typecheck.
- [x] Commit `feat(core): add entitlement contracts`.

## Task 2: Central Entitlement Persistence And Resolver

**Files:**

- Create migrations `bodyflow_entitlements_domain` and
  `bodyflow_entitlements_privileges` with the Supabase CLI.
- Create `supabase/tests/bodyflow_entitlements.sql`.

- [x] Write RED SQL tests for schema, constraints, RLS, grants and function
  signatures.
- [x] Add `user_entitlements` and sanitized `entitlement_events`.
- [x] Add trusted idempotent/out-of-order-safe apply and Stripe sync RPCs.
- [x] Add the patient-safe resolver with explicit block precedence, expiration
  semantics and narrow Stripe read-through.
- [x] Revoke default privileges and grant only the documented roles.
- [x] Prove no direct authenticated write or provider-reference read.
- [x] Commit `feat(database): add central entitlement service`.

## Task 3: Mobile Entitlement Service And Endpoint

**Files:**

- Create `apps/admin/src/lib/mobile-api/entitlement-service.ts`
- Create `apps/admin/src/lib/mobile-api/entitlement-service.test.ts`
- Modify `apps/admin/src/app/api/mobile/v1/entitlements/route.ts`
- Modify route/read-model tests as needed.

- [x] Write RED tests proving sanitized DTOs, no raw subscription rows, fail
  closed behavior and a stable disabled billing capability.
- [x] Replace direct subscription reads with `resolve_user_entitlement`.
- [x] Enforce the resolver in the shared BFF wrapper for every protected mobile
  route, after authentication and before its handler.
- [x] Map database failures to the standard mobile error envelope.
- [x] Verify focused admin tests and typecheck.
- [x] Commit `feat(admin): expose central mobile entitlement` and
  `feat(admin): enforce mobile entitlement gate`.

## Task 4: Stripe Projection Compatibility

**Files:**

- Modify `supabase/functions/webhook-stripe/index.ts`
- Add or extend isolated webhook logic tests without real Stripe calls.

- [x] Write RED tests for active, trial, past-due, cancellation and expiry
  normalization.
- [x] Call the central Stripe sync RPC after each successful subscription
  mutation and before finalizing its provider event.
- [x] Keep raw provider data private and preserve existing event idempotency.
- [x] Verify no legacy agent gate changes.
- [x] Commit `feat(billing): project stripe subscriptions to entitlements`.

## Task 5: Disabled-By-Default RevenueCat Ingestion

**Files:**

- Create a pure RevenueCat signature/event normalizer and tests.
- Create the internal webhook route using the pure normalizer.
- Document required future sandbox environment variable names only.

- [x] Write RED tests for valid HMAC, tampering, stale timestamp, wrong
  environment, unknown entitlement, invalid user UUID and event mapping.
- [x] Require raw-body HMAC and constant-time comparison.
- [x] Apply only safe known events through the central RPC.
- [x] Return 503 when sandbox configuration is absent; do not create secrets.
- [x] Acknowledge state-neutral events with `200` so the provider does not retry
  accepted no-op events.
- [x] Distinguish paid-through cancellation, immediate refund, billing-error
  cancellation and refund reversal.
- [x] Reject transfer/reconciliation events instead of guessing ownership.
- [x] Commit `feat(billing): prepare revenuecat entitlement ingestion` and the
  subsequent provider-semantics fixes.

## Task 6: Generated Types, Full Verification And Staging

- [x] Regenerate or update Supabase types from the staging schema after applying
  only the new migrations there.
- [x] Run core/admin/agent/Inngest tests, monorepo test, typecheck, lint if
  configured, admin build and all SQL suites.
- [x] Revalidate zero active staging crons and zero provider secrets.
- [x] Run synthetic entitlement cases inside the rollback-only SQL suite.
- [x] Confirm production ref was never linked or queried.
- [x] Record exact commands/results in the implementation report.

## Task 7: Review And Checkpoint

- [x] Run `git diff --check` and a focused security review of RLS, RPCs,
  webhook verification, logs and error responses.
- [x] Update the design with evidence-backed deviations and the bounded content
  plan-targeting follow-up.
- [x] Create final documentation/checkpoint commits.
- [ ] Push the branch and open a draft stacked PR only if remote access works.
- [x] Do not deploy or merge.

### Staging And Verification Evidence — 2026-07-24

- The linked Supabase ref was revalidated as staging
  `xitugspwfxkcluxvrdeg` before live commands and differed from production.
  Production was never linked, queried, migrated or deployed.
- The three additive entitlement migrations are present in staging. The final
  migration adds the partial ownership index required by the foreign-key
  advisor for `entitlement_events.entitlement_id`.
- The rollback-only SQL suite passed after the final schema. It proves source
  isolation, deterministic precedence, block override, expiration semantics,
  duplicate/stale event handling, narrow Stripe read-through, constraints,
  RLS, explicit grants and service-role-only RPC execution.
- Supabase CLI 2.109.1 now executes linked tests through a restricted temporary
  login. That login correctly cannot insert fixtures into private `users`, and
  privilege-filtered `information_schema` initially hid the columns from it.
  Structural assertions now use `pg_catalog`; the unchanged `BEGIN`/`ROLLBACK`
  suite passed through the staging administrative SQL channel and retained zero
  fixture rows. This transport limitation is not reported as an application or
  schema failure.
- Both entitlement tables have RLS enabled. Only `service_role` has direct
  `SELECT`; `anon` and `authenticated` have no table privileges. All three
  trusted functions are `SECURITY DEFINER`, use a fixed search path and deny
  execution to `PUBLIC`, `anon` and `authenticated`.
- The mobile BFF tests prove authentication precedes authorization, protected
  handlers do not run after denial, all approved account/configuration paths
  remain reachable and similarly prefixed paths cannot bypass the gate.
- RevenueCat tests prove raw-body HMAC, constant-time verification, replay
  rejection, environment and product allowlists, UUID ownership, size bounds,
  disabled-by-default configuration, retryable reconciliation and explicit
  cancellation/refund semantics. No provider account, key, secret or product
  was created.
- The staging postcondition is 34 cron jobs, zero active jobs, zero entitlement
  rows, zero entitlement-event rows and zero Vault secrets.
- Final verification passed: 2,022 tests across Core 213, Providers 18, Agent
  1,053, Inngest 167 and Admin 571; monorepo typecheck 8/8; admin production
  build with 32 static pages; Deno Stripe projection tests 4/4; Stripe Edge
  Function `deno check`; database lint with zero errors; changed-file Biome on
  22 files; and `git diff --check`.
- The repository-wide `pnpm lint` remains red on pre-existing formatting,
  import-order and non-null-assertion debt in files outside this branch,
  including `packages/core/src/engine/targets.ts` and legacy provider files.
  No baseline file was reformatted as part of this entitlement slice.
- Security advisors report only the intentional informational deny-all pattern
  (`RLS enabled, no policy`) for the two entitlement tables. Performance
  advisors no longer report an unindexed entitlement foreign key; the two new
  indexes are merely unused while staging contains zero entitlement rows.

### Deliberately Deferred

- Content delivery still reads legacy `subscriptions.plan` only for optional
  editorial targeting. It cannot bypass the central BFF access gate, but it
  must move to the central resolver before plan-specific content is enabled.
- Provider dashboard configuration, StoreKit products, prices, paywalls,
  charging, production migration, real-user reconciliation, deployment, merge,
  push and draft PR remain outside this local checkpoint.

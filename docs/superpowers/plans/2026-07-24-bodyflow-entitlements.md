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
- Do not modify the legacy agent/WhatsApp subscription gate.
- Do not migrate or grandfather real users.
- Use migrations created by the pinned Supabase CLI.

## Task 1: Portable Entitlement Contracts

**Files:**

- Create `packages/core/src/entitlements.ts`
- Create `packages/core/src/entitlements.test.ts`
- Modify `packages/core/src/index.ts`

- [ ] Add RED tests for exact statuses, sources, provider environments,
  patient-safe decision parsing, RevenueCat event parsing and event ordering.
- [ ] Implement strict Zod contracts and deterministic helpers.
- [ ] Verify focused core tests and typecheck.
- [ ] Commit `feat(core): add entitlement contracts`.

## Task 2: Central Entitlement Persistence And Resolver

**Files:**

- Create migrations `bodyflow_entitlements_domain` and
  `bodyflow_entitlements_privileges` with the Supabase CLI.
- Create `supabase/tests/bodyflow_entitlements.sql`.

- [ ] Write RED SQL tests for schema, constraints, RLS, grants and function
  signatures.
- [ ] Add `user_entitlements` and sanitized `entitlement_events`.
- [ ] Add trusted idempotent/out-of-order-safe apply and Stripe sync RPCs.
- [ ] Add the patient-safe resolver with explicit block precedence, expiration
  semantics and narrow Stripe read-through.
- [ ] Revoke default privileges and grant only the documented roles.
- [ ] Prove no direct authenticated write or provider-reference read.
- [ ] Commit `feat(database): add central entitlement service`.

## Task 3: Mobile Entitlement Service And Endpoint

**Files:**

- Create `apps/admin/src/lib/mobile-api/entitlement-service.ts`
- Create `apps/admin/src/lib/mobile-api/entitlement-service.test.ts`
- Modify `apps/admin/src/app/api/mobile/v1/entitlements/route.ts`
- Modify route/read-model tests as needed.

- [ ] Write RED tests proving sanitized DTOs, no raw subscription rows, fail
  closed behavior and a stable disabled billing capability.
- [ ] Replace direct subscription reads with `resolve_user_entitlement`.
- [ ] Map database failures to the standard mobile error envelope.
- [ ] Verify focused admin tests and typecheck.
- [ ] Commit `feat(admin): expose central mobile entitlement`.

## Task 4: Stripe Projection Compatibility

**Files:**

- Modify `supabase/functions/webhook-stripe/index.ts`
- Add or extend isolated webhook logic tests without real Stripe calls.

- [ ] Write RED tests for active, trial, past-due, cancellation and expiry
  normalization.
- [ ] Call the central Stripe sync RPC after each successful subscription
  mutation and before finalizing its provider event.
- [ ] Keep raw provider data private and preserve existing event idempotency.
- [ ] Verify no legacy agent gate changes.
- [ ] Commit `feat(billing): project stripe subscriptions to entitlements`.

## Task 5: Disabled-By-Default RevenueCat Ingestion

**Files:**

- Create a pure RevenueCat signature/event normalizer and tests.
- Create the internal webhook route using the pure normalizer.
- Document required future sandbox environment variable names only.

- [ ] Write RED tests for valid HMAC, tampering, stale timestamp, wrong
  environment, unknown entitlement, invalid user UUID and event mapping.
- [ ] Require raw-body HMAC and constant-time comparison.
- [ ] Apply only safe known events through the central RPC.
- [ ] Return 503 when sandbox configuration is absent; do not create secrets.
- [ ] Reject transfer/reconciliation events instead of guessing ownership.
- [ ] Commit `feat(billing): prepare revenuecat entitlement ingestion`.

## Task 6: Generated Types, Full Verification And Staging

- [ ] Regenerate or update Supabase types from the staging schema after applying
  only the new migrations there.
- [ ] Run core/admin/agent/Inngest tests, monorepo test, typecheck, lint if
  configured, admin build and all SQL suites.
- [ ] Revalidate zero active staging crons and zero provider secrets.
- [ ] Run synthetic entitlement cases in a transaction and clean every row.
- [ ] Confirm production ref was never linked or queried.
- [ ] Record exact commands/results in the implementation report.

## Task 7: Review And Checkpoint

- [ ] Run `git diff --check` and a focused security review of RLS, RPCs,
  webhook verification, logs and error responses.
- [ ] Update the design with any evidence-backed deviation.
- [ ] Create final documentation/checkpoint commits.
- [ ] Push the branch and open a draft stacked PR only if remote access works.
- [ ] Do not deploy or merge.

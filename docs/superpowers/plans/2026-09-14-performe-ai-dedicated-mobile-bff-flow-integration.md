# Performe AI Dedicated Mobile BFF Flow Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the proven dedicated Mobile BFF artifact on top of the Performe AI beta checkpoint and publish the already-implemented authenticated Flow route through that artifact without exposing Admin surfaces.

**Architecture:** Reuse the exact `apps/mobile-bff` package from historical commit `e3e1e252b48e42554e75899b950692c05186f60d`, whose parent is the beta base `277873755bf29771a10b5f362b522c2e6a6c21d6`. Keep `apps/admin/src/app/api/mobile/v1/**` as the authoritative implementation and add one named-handler wrapper for `flow/chat/route.ts`; declare that route's static Next runtime metadata locally because Next does not statically analyze re-exported `maxDuration`, then update the source, mirror, import-closure, and built-surface receipts from 40 to 41 routes.

**Tech Stack:** Node.js 22, pnpm 10.33.2, Next.js 15, TypeScript 5.9, Vitest 2.1, existing `@mpp/*` workspace packages.

**Spec:** `docs/superpowers/specs/2026-09-14-performe-ai-client-beta-flow-v1.md`

## Global Constraints

- Starting HEAD is exactly `dcbd6eb70c7845c156fddbffb3cce5d7bdd4de32`; exactly one final local commit is allowed.
- Do not modify the existing Admin Flow implementation, Agent pipeline, iOS client, schema, CI-3, remote staging, Vercel, Supabase, users, provider configuration, signing, or secrets.
- Dedicated route wrappers contain only exact named handler re-exports plus static Next route metadata when required by the build analyzer; no `export *`, copied business logic, page, layout, middleware, Server Action, public asset, Admin route, webhook, or worker graph.
- Tests use local doubles/build artifacts only and make no real Supabase or provider request.
- External E2E remains `NOT VERIFIED`; deployment and all remote mutations remain `NOT EXECUTED`.
- The user instruction requiring one final commit overrides the plan skill's default preference for frequent commits.

## Reviewed allowlist

- Create from the exact historical commit: `apps/mobile-bff/**`.
- Add for the new authoritative route: `apps/mobile-bff/src/app/api/mobile/v1/flow/chat/route.ts`.
- Modify only for workspace dependency registration: `pnpm-lock.yaml`.
- Add plan/evidence: `docs/superpowers/plans/2026-09-14-performe-ai-dedicated-mobile-bff-flow-integration.md` and `docs/superpowers/evidence/2026-09-14-performe-ai-dedicated-mobile-bff-flow-integration.md`.

No other path is authorized by this plan. If a test demonstrates that another production path must change, stop and re-evaluate the allowlist before editing it.

---

### Task 1: Restore the proven dedicated package and establish RED

**Files:**
- Create: exact `apps/mobile-bff/**` tree from `e3e1e252b48e42554e75899b950692c05186f60d`.
- Modify: `pnpm-lock.yaml` with the historical `apps/mobile-bff` importer plus direct `@mpp/providers` workspace dependency required by the Flow route.
- Test: `apps/mobile-bff/src/source-surface.test.ts`.
- Test: `apps/mobile-bff/src/route-mirror.test.ts`.

**Interfaces:**
- Consumes: authoritative handlers under `apps/admin/src/app/api/mobile/v1/**`.
- Produces: standalone Next app whose route files are named re-export wrappers.

- [ ] Restore every historical package file byte-for-byte and verify it against the `e3e1e252…` tree before making Flow-specific edits.
- [ ] Run the historical source/mirror tests with the current beta source and observe semantic RED: source count/hash changed to 41 while the wrapper count remains 40.
- [ ] Confirm the failure is caused only by the missing Flow wrapper and frozen 40-route receipts, not by test discovery, syntax, module resolution, or unrelated source drift.

### Task 2: Add the minimum Flow wrapper and update deterministic receipts

**Files:**
- Create: `apps/mobile-bff/src/app/api/mobile/v1/flow/chat/route.ts`.
- Modify: `apps/mobile-bff/scripts/verify-route-mirror.mjs`.
- Modify: `apps/mobile-bff/scripts/verify-build-surface.mjs`.
- Modify: `apps/mobile-bff/src/route-mirror.test.ts`.
- Modify: `apps/mobile-bff/src/source-surface.test.ts`.
- Modify: `apps/mobile-bff/src/import-closure.test.ts` only if needed to assert the Flow route/service in the allowlisted closure.
- Modify: `apps/mobile-bff/package.json` to declare direct `@mpp/providers` use.

**Interfaces:**
- Consumes: `GET` and `POST` from `@/app/api/mobile/v1/flow/chat/route`; preserves the authoritative route's literal `runtime = 'nodejs'` and `maxDuration = 300` as static wrapper metadata recognized by Next.
- Produces: `/api/mobile/v1/flow/chat` with the exact existing handler/auth/service behavior.

- [ ] Add the single wrapper:

```ts
export const runtime = 'nodejs'
export const maxDuration = 300

export { GET, POST } from '@/app/api/mobile/v1/flow/chat/route'
```

  This replaces the initially planned four-name re-export after the production build emitted a warning that re-exported `maxDuration` was not recognized and would fall back to the platform default.

- [ ] Update the literal source/mirror receipt to count `41` and SHA-256 `b8ed43a4af34bf6ebfd2402f81d1510b5fe2dfb625444dc58700b467c9f280b2`.
- [ ] Update the literal built route-path receipt to count `41` and SHA-256 `de49930a0b49313c30017e3320a7584b9a3012c80ef48660210ba0a624003a5b`.
- [ ] Assert the import closure contains the Flow wrapper, authoritative Flow route, handler, and `flow-chat-service.ts`, with zero denied records.
- [ ] Run the dedicated source/mirror/import tests and require GREEN.

### Task 3: Build and verify the real dedicated artifact

**Files:**
- Build output only: `apps/mobile-bff/.next/**` (ignored and excluded from the commit).
- Evidence: `docs/superpowers/evidence/2026-09-14-performe-ai-dedicated-mobile-bff-flow-integration.md`.

**Interfaces:**
- Consumes: the 41-wrapper dedicated source tree.
- Produces: a locally publishable Next build with only `/api/mobile/v1/**` routes.

- [ ] Run focused dedicated tests, Admin Mobile API regressions, Agent regressions, and typechecks.
- [ ] Build `@mpp/mobile-bff` with no runtime secrets and no network calls to Supabase/OpenRouter.
- [ ] Inspect the actual `.next` manifests and NFT closure. Require `/api/mobile/v1/flow/chat`, all 40 historical Mobile routes, zero pages/middleware/Server Actions, and zero forbidden Admin/Inngest/Stripe/media/webhook/worker references.
- [ ] Review any NFT count/hash drift path-by-path before freezing the new local receipt; never accept a blind snapshot update.
- [ ] Run scoped Biome checks, secret/PII/log scans, `git diff --check`, and review the complete allowlisted diff.

### Task 4: Independent reviews and one final commit

**Files:**
- Modify: `docs/superpowers/evidence/2026-09-14-performe-ai-dedicated-mobile-bff-flow-integration.md` with sanitized commands/results/reviews.

**Interfaces:**
- Consumes: complete unstaged integration diff and fresh verification outputs.
- Produces: exactly one reviewed commit on the existing beta branch.

- [ ] Dispatch independent read-only Review A for published security surface: auth, ownership, secrets, headers, logs, routes, Admin isolation.
- [ ] Dispatch independent read-only Review B for integration: wrapper, Flow services, persistence, build, iOS contract compatibility.
- [ ] Resolve every Critical and Important issue through a new RED/GREEN cycle, then repeat the affected review.
- [ ] Require Critical 0 and Important 0 from both reviews.
- [ ] Stage only allowlisted paths and verify staged secrets, diff, parent, and path list.
- [ ] Create exactly one commit with subject `feat(staging): integrate Flow into dedicated mobile BFF` and parent `dcbd6eb70c7845c156fddbffb3cce5d7bdd4de32`.
- [ ] Re-run commit-level tests/manifest/scans and verify final HEAD, parent, tree, clean worktree, CI-3 preservation, and zero remote mutation.

# BodyFlow Personalities, Messages, And Mascot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** deliver the app-first personality preference, bilingual deterministic message catalog, monthly editorial rotation, admin governance, and non-visual mascot state defined by BodyFlow Prompt 07.

**Architecture:** pure rendering and validation live in `@mpp/core`; PostgreSQL owns catalog versioning, frequency, selection, idempotency, RLS, and pack activation; the authenticated Next.js BFF owns patient and admin APIs. Recurring runtime paths select immutable catalog versions and never call an LLM, while a bounded admin-only adapter may suggest draft rewrites for human approval.

**Tech Stack:** TypeScript, Zod, Vitest, Next.js 15 App Router, Supabase/PostgreSQL, Inngest 3, OpenRouter through `@mpp/providers`, pnpm 10.

## Global Constraints

- Work only in `/root/.codex/worktrees/agentempp-bodyflow-personalities` on `codex/bodyflow-personalities-mascot-v1`.
- Preserve the layered base `b8c4999cf4492fbb3aa713aee8fc08bb39ed8bdb` and do not modify the Prompt 06 worktree.
- Production Supabase project `xuxehkhdvjivitduarvb` remains untouched.
- Database validation and application are allowed only on staging ref `xitugspwfxkcluxvrdeg` after revalidating the link.
- Do not deploy, sync Inngest, configure providers, reactivate cron jobs, or send external messages.
- New-domain channels are exactly `in_app`, `push`, and `email`.
- Locales are exactly `pt-BR` and `en-US`.
- Selectable personalities are exactly `focus`, `impulse`, and `zen`; `balanced` is internal fallback only.
- The baseline catalog contains exactly 1,080 renditions: 4 tones x 15 contexts x 3 channels x 2 locales x 3 variants.
- Email catalog entries exist, but email delivery remains disabled.
- Do not invent mascot visual assets, SwiftUI, animation, or engagement thresholds.
- Use RED, GREEN, refactor for every production behavior.
- Create migrations with `supabase migration new`; do not invent timestamp prefixes manually.
- Every new public table has RLS, explicit grants, and no default client writes.
- Never log or persist rendered patient content, credentials, raw event keys, or PII in message-usage telemetry.

---

### Task 1: Pure Coach Message Contracts, Rendering, And Safety Lint

**Files:**
- Create: `packages/core/src/coach-messages.ts`
- Create: `packages/core/src/coach-messages.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Produces:

```ts
export const coachPersonalitySchema: z.ZodEnum<['balanced', 'focus', 'impulse', 'zen']>
export const selectableCoachPersonalitySchema: z.ZodEnum<['focus', 'impulse', 'zen']>
export const coachMessageContextSchema: z.ZodEnum<[
  'onboarding',
  'meal_pending',
  'registration_confirmed',
  'error_corrected',
  'hydration',
  'supplement',
  'medication',
  'workout',
  'progress',
  'day_incomplete',
  'reevaluation',
  'reengagement',
  'trial',
  'paywall',
  'return_after_abandonment',
]>
export const coachMessageChannelSchema: z.ZodEnum<['in_app', 'push', 'email']>
export const coachMessageLocaleSchema: z.ZodEnum<['pt-BR', 'en-US']>

export type CoachPersonality = z.infer<typeof coachPersonalitySchema>
export type SelectableCoachPersonality = z.infer<typeof selectableCoachPersonalitySchema>
export type CoachMessageContext = z.infer<typeof coachMessageContextSchema>
export type CoachMessageChannel = z.infer<typeof coachMessageChannelSchema>
export type CoachMessageLocale = z.infer<typeof coachMessageLocaleSchema>

export interface CoachTemplateLintInput {
  context: CoachMessageContext
  channel: CoachMessageChannel
  locale: CoachMessageLocale
  title: string | null
  subject: string | null
  body: string
  allowedVariables: readonly string[]
  requiredVariables: readonly string[]
}

export interface CoachTemplateLintIssue {
  code: 'invalid_placeholder' | 'unknown_variable' | 'missing_required_variable'
    | 'channel_length' | 'unsafe_language' | 'control_character'
  field: 'title' | 'subject' | 'body' | 'variables'
  message: string
}

export function extractCoachPlaceholders(value: string): string[]
export function lintCoachTemplate(input: CoachTemplateLintInput): CoachTemplateLintIssue[]
export function renderCoachTemplate(input: CoachTemplateLintInput, variables: Record<string, string | number>): {
  title: string | null
  subject: string | null
  body: string
}
export function chooseLeastRecentlyUsedVariant<T extends {
  id: string
  variant: 1 | 2 | 3
  lastUsedAt: string | null
}>(candidates: readonly T[], lastSelectedId: string | null): T
```

- [ ] **Step 1: Write RED tests for schemas and exact supported values.**

```ts
expect(selectableCoachPersonalitySchema.safeParse('balanced').success).toBe(false)
expect(coachMessageChannelSchema.options).toEqual(['in_app', 'push', 'email'])
expect(coachMessageContextSchema.options).toHaveLength(15)
```

- [ ] **Step 2: Run `pnpm --filter @mpp/core test -- coach-messages.test.ts`.**

Expected: FAIL because `coach-messages.ts` does not exist.

- [ ] **Step 3: Implement the schemas and exported TypeScript types.**
- [ ] **Step 4: Add RED tests for placeholder extraction, unknown variables, unresolved required variables, control characters, locale-specific unsafe phrases, and channel limits.**
- [ ] **Step 5: Implement fail-closed linting and plain-text rendering.**

Rendering must normalize CRLF, remove forbidden control characters from variable values, limit substituted strings to 200 characters, format only already-formatted numeric/date inputs, and throw when any placeholder remains unresolved.

- [ ] **Step 6: Add RED tests proving variants 1, 2, and 3 are selected before reuse and immediate repeat is avoided after exhaustion.**
- [ ] **Step 7: Implement the pure LRU tie-breaker with stable `id` ordering.**
- [ ] **Step 8: Run `pnpm --filter @mpp/core test` and `pnpm --filter @mpp/core typecheck`.**
- [ ] **Step 9: Commit `feat(core): add coach message contracts and renderer`.**

### Task 2: Catalog, Preference, Usage, Pack, And Mascot Database Domain

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_coach_message_domain`
- Create: `supabase/tests/bodyflow_coach_messages.sql`
- Modify after verified schema: `packages/db/src/generated/database.ts`

**Consumes:** the exact constrained values from Task 1.

**Produces:**

```sql
public.coach_personalities
public.user_coach_preferences
public.coach_message_context_policies
public.coach_content_packs
public.coach_message_templates
public.coach_message_template_versions
public.coach_content_pack_entries
public.coach_message_usage
public.user_mascot_state
public.user_mascot_state_events

public.set_user_coach_personality(p_user_id uuid, p_personality text) returns jsonb
public.claim_coach_message(
  p_user_id uuid,
  p_context text,
  p_channel text,
  p_locale text,
  p_event_key text,
  p_available_variables text[],
  p_now timestamptz default clock_timestamp()
) returns jsonb
public.activate_coach_content_pack(p_pack_id uuid, p_activated_by uuid, p_now timestamptz) returns jsonb
public.activate_due_coach_content_pack(p_now timestamptz) returns jsonb
public.transition_user_mascot_state(
  p_user_id uuid,
  p_next_state text,
  p_reason text,
  p_event_key text
) returns jsonb
```

- [ ] **Step 1: Write a SQL test that fails because the ten relations and four RPCs do not exist.**

The test must assert RLS, forbidden `anon`/`authenticated` writes, service-only execution for all five internal RPCs, uniqueness, immutable copy fields, one active pack, valid personality selection, valid mascot transitions, and no rendered-body column in usage telemetry.

- [ ] **Step 2: Run the SQL test against an isolated database and confirm the expected missing-relation failure.**
- [ ] **Step 3: Run `supabase migration new bodyflow_coach_message_domain`.**
- [ ] **Step 4: Implement tables, checks, indexes, RLS, grants, and ownership policies.**

Template title, subject, body, variables, provenance, and content hash are
immutable after insert. Lifecycle status and activation/archive audit columns
may change only through the pack RPCs.

Required invariants include:

```sql
UNIQUE (personality_code, context, channel, locale, variant)
CHECK (variant BETWEEN 1 AND 3)
CHECK (channel IN ('in_app', 'push', 'email'))
CHECK (locale IN ('pt-BR', 'en-US'))
CHECK (status IN ('draft', 'scheduled', 'active', 'archived'))
```

Use a partial unique index for the one active pack and reject `balanced` in `set_user_coach_personality`.

- [ ] **Step 5: Implement `claim_coach_message` with an advisory transaction lock keyed by user/context/channel, same-locale exact-personality selection, balanced fallback, three-variant LRU, event-key hashing, local-day limits, cooldown, and append-only telemetry.**
- [ ] **Step 6: Implement pack activation and rollback-safe status changes atomically.**
- [ ] **Step 7: Implement explicit mascot transition validation without automatic time-based transitions.**
- [ ] **Step 8: Run SQL tests through rollback and confirm zero synthetic rows remain.**
- [ ] **Step 9: Regenerate database types from the isolated/staging schema only after migration verification.**
- [ ] **Step 10: Run `pnpm --filter @mpp/db typecheck` and `git diff --check`.**
- [ ] **Step 11: Commit `feat(database): add coach message and mascot domain`.**

### Task 3: Complete Bilingual Baseline Catalog And Deterministic Seed

**Files:**
- Create: `content/coach-messages/bodyflow-baseline-v1.json`
- Create: `apps/admin/scripts/generate-coach-message-seed.mjs`
- Create: `apps/admin/src/lib/coach-messages/catalog-source.ts`
- Create: `apps/admin/src/lib/coach-messages/catalog-source.test.ts`
- Create with Supabase CLI: migration basename `bodyflow_coach_catalog_baseline_v1`

**Consumes:** `lintCoachTemplate` from Task 1 and catalog tables from Task 2.

**Produces:** a deterministic, reviewable source containing 360 semantic variants and three channel renditions per variant, expanded to exactly 1,080 database versions and pack entries.

```ts
export interface CoachCatalogRendition {
  title?: string
  subject?: string
  body: string
}

export interface CoachCatalogVariant {
  variant: 1 | 2 | 3
  requiredVariables: readonly string[]
  renditions: {
    in_app: CoachCatalogRendition
    push: CoachCatalogRendition & { title: string }
    email: CoachCatalogRendition & { subject: string }
  }
}
```

The JSON root contract is:

```ts
interface BaselineCatalog {
  schema_version: 'bodyflow.coach-catalog.v1'
  pack: { slug: 'bodyflow-baseline-v1'; label: string }
  groups: Array<{
    personality: 'balanced' | 'focus' | 'impulse' | 'zen'
    context: CoachMessageContext
    locale: 'pt-BR' | 'en-US'
    variants: Array<{
      variant: 1 | 2 | 3
      required_variables: string[]
      renditions: {
        in_app: { body: string }
        push: { title: string; body: string }
        email: { subject: string; body: string }
      }
    }>
  }>
}
```

- [ ] **Step 1: Write RED tests requiring 120 unique groups, three variants per group, 1,080 renditions, complete matrix coverage, and no normalized duplicate within a tuple.**
- [ ] **Step 2: Run `pnpm --filter @mpp/admin test -- catalog-source.test.ts` and confirm the missing-source failure.**
- [ ] **Step 3: Author the baseline JSON with locale-native copy and no mechanical word-for-word translation.**

Every string must satisfy the approved tone rules. Push copy must fit its channel limits. Email content remains plain text and must not imply that delivery is enabled.

- [ ] **Step 4: Implement the parser and run every rendition through the Task 1 linter.**
- [ ] **Step 5: Implement the deterministic generator.**

The generator must sort by personality, context, locale, variant, and channel; produce fixed UUIDs from stable keys; escape SQL values safely; include a source SHA-256; and fail if coverage is not exactly 1,080.

- [ ] **Step 6: Run `supabase migration new bodyflow_coach_catalog_baseline_v1`, generate its SQL body, and run the generator twice to prove byte-identical output.**
- [ ] **Step 7: Apply schema plus seed to an isolated database, assert 1,080 active versions and entries, and roll back test data.**
- [ ] **Step 8: Run focused core/admin tests and changed-file Biome.**
- [ ] **Step 9: Commit `feat(content): seed complete BodyFlow coach catalog`.**

### Task 4: Patient Personality API And Server-Side Selection Adapter

**Files:**
- Modify: `apps/admin/src/lib/mobile-api/contracts.ts`
- Create: `apps/admin/src/lib/mobile-api/coach-service.ts`
- Create: `apps/admin/src/lib/mobile-api/coach-service.test.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-coach.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-coach.test.ts`
- Modify: `apps/admin/src/app/api/mobile/v1/coach/persona/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/coach/persona/route.test.ts`

**Consumes:** Task 1 renderer and Task 2 RPCs.

**Produces:**

```ts
export interface CoachPersonaState {
  selected: 'focus' | 'impulse' | 'zen' | null
  effective: 'balanced' | 'focus' | 'impulse' | 'zen'
  options: Array<{
    code: 'focus' | 'impulse' | 'zen'
    name: string
    description: string
  }>
  mascot: {
    state: 'inactive' | 'reactivating' | 'active' | 'evolving' | 'neglected'
    changed_at: string | null
  }
  contract_version: 'bodyflow.coach-persona.v1'
}

export interface ClaimedCoachMessage {
  usageId: string
  templateVersionId: string
  packId: string
  requestedPersonality: CoachPersonality
  effectivePersonality: CoachPersonality
  reason: 'exact' | 'balanced_fallback'
  rendered: { title: string | null; subject: string | null; body: string }
}

export interface ClaimCoachMessageInput {
  userId: string
  context: CoachMessageContext
  channel: CoachMessageChannel
  locale: CoachMessageLocale
  eventKey: string
  variables: Record<string, string | number>
  now?: string
}

export interface ClaimedCoachMessageRecord {
  usageId: string
  templateVersionId: string
  packId: string
  requestedPersonality: CoachPersonality
  effectivePersonality: CoachPersonality
  reason: 'exact' | 'balanced_fallback'
  title: string | null
  subject: string | null
  body: string
  allowedVariables: string[]
  requiredVariables: string[]
}

export interface CoachDependencies {
  repository: {
    getPersonaState(userId: string, locale: CoachMessageLocale): Promise<CoachPersonaState>
    setPersona(userId: string, persona: SelectableCoachPersonality): Promise<void>
    claimMessage(input: {
      userId: string
      context: CoachMessageContext
      channel: CoachMessageChannel
      locale: CoachMessageLocale
      eventKey: string
      availableVariables: string[]
      now?: string
    }): Promise<ClaimedCoachMessageRecord | null>
    markUsageFailed(usageId: string, reason: 'render_failed'): Promise<void>
  }
}

export function getCoachPersonaState(deps: CoachDependencies, userId: string, locale: CoachMessageLocale): Promise<CoachPersonaState>
export function setCoachPersona(deps: CoachDependencies, userId: string, persona: SelectableCoachPersonality): Promise<CoachPersonaState>
export function claimAndRenderCoachMessage(deps: CoachDependencies, input: ClaimCoachMessageInput): Promise<ClaimedCoachMessage | null>
```

- [ ] **Step 1: Replace the reserved-route expectations with RED tests for balanced fallback, localized options, and mascot state.**
- [ ] **Step 2: Add RED PATCH tests for strict personality input, ownership from auth context, idempotent replay, and rejection of `balanced`.**
- [ ] **Step 3: Implement repository interfaces and pure service orchestration.**
- [ ] **Step 4: Implement Supabase adapters without exposing catalog tables to the patient client.**
- [ ] **Step 5: Implement claim-and-render with fail-closed rendering and a non-PII failure update.**
- [ ] **Step 6: Replace `501 persona_module_not_configured` with functional GET/PATCH routes using `executeSupabaseIdempotent`.**
- [ ] **Step 7: Run `pnpm --filter @mpp/admin test` and `pnpm --filter @mpp/admin typecheck`.**
- [ ] **Step 8: Commit `feat(mobile-api): enable BodyFlow coach personalities`.**

### Task 5: Reminder Selection And Scheduled Pack Activation

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_coach_delivery_integration`
- Modify: `supabase/tests/bodyflow_push_routine.sql`
- Modify: `supabase/tests/bodyflow_coach_messages.sql`
- Create: `packages/inngest-functions/src/functions/coach-content-pack-activation.ts`
- Create: `packages/inngest-functions/src/functions/coach-content-pack-activation.test.ts`
- Modify: `packages/inngest-functions/src/index.ts`
- Modify: `packages/inngest-functions/src/client.ts` only if the event map requires a new typed event

**Consumes:** the selector RPC and the existing reminder outbox.

**Produces:** queued reminder deliveries reference an immutable catalog version and effective personality; due approved packs activate without any external provider call.

- [ ] **Step 1: Add RED SQL tests proving queued reminders no longer persist the legacy `default` personality and reference one push template usage shared across all devices for the reminder event.**
- [ ] **Step 2: Create the additive integration migration.**

Add nullable foreign keys from `notification_deliveries` to the selected template version and usage row, plus a constrained locale. Update `claim_reminder_event` so supported reminder categories select a generic no-variable push rendition once per event before creating per-device delivery rows.

- [ ] **Step 3: Add RED tests for no eligible template, balanced fallback, retry reuse, no active device, and a reminder with multiple devices.**
- [ ] **Step 4: Implement SQL integration and keep provider delivery disabled.**
- [ ] **Step 5: Write RED worker tests for no due pack, one due pack, retry, incomplete pack rejection, and no PII in logs/results.**
- [ ] **Step 6: Implement a low-concurrency Inngest scheduler that calls only `activate_due_coach_content_pack`; do not sync or deploy it.**
- [ ] **Step 7: Register the worker and run `pnpm --filter @mpp/inngest-functions test` plus typecheck.**
- [ ] **Step 8: Commit `feat(workers): rotate approved coach content packs`.**

### Task 6: Admin Governance And Bounded Assisted Drafts

**Files:**
- Create: `apps/admin/src/lib/coach-messages/admin-service.ts`
- Create: `apps/admin/src/lib/coach-messages/admin-service.test.ts`
- Create: `apps/admin/src/lib/coach-messages/assisted-rewrite.ts`
- Create: `apps/admin/src/lib/coach-messages/assisted-rewrite.test.ts`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/actions.ts`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/actions.test.ts`

**Consumes:** catalog linter, immutable versions, pack RPCs, existing `OpenRouterLLM`, and existing admin RBAC helpers.

**Produces:** server-only operations for list/filter, immutable revision, synthetic preview, pack clone, bounded suggestion, validation, schedule, activate, archive, and rollback.

```ts
export interface AssistedRewriteRequest {
  packId: string
  personality: CoachPersonality
  context: CoachMessageContext
  locale: CoachMessageLocale
  sourceVersions: readonly [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant]
}

export interface AssistedRewriteResult {
  variants: readonly [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant]
  model: string
  promptTokens: number
  completionTokens: number
  costUsd: number | null
  latencyMs: number
}
```

- [ ] **Step 1: Write RED service tests for immutable draft revision and synthetic-only preview.**
- [ ] **Step 2: Implement repository-driven admin service methods.**
- [ ] **Step 3: Write RED authorization tests proving content editors cannot schedule, activate, archive, or roll back and other roles cannot mutate drafts.**
- [ ] **Step 4: Implement server actions that reauthenticate, load the admin role, and only then create a service client.**
- [ ] **Step 5: Write RED assisted-rewrite tests for exactly one personality/context/locale group, JSON-only output, preserved placeholders, three distinct variants, safety lint, provider failure, and no patient data.**
- [ ] **Step 6: Implement the OpenRouter adapter with model `anthropic/claude-haiku-4.5`, temperature at most `0.4`, JSON mode, and a hard output limit.**

The action reads the provider credential server-side using the existing credential pattern, never logs it, never runs in bulk, and stores output only as immutable `assisted_draft` versions after lint succeeds.

- [ ] **Step 7: Record model, tokens, cost, latency, group key, and result status in audit telemetry without storing prompts or generated body text.**
- [ ] **Step 8: Run focused admin tests, typecheck, and changed-file Biome.**
- [ ] **Step 9: Commit `feat(admin): govern coach content packs`.**

### Task 7: Operational Admin UI

**Files:**
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/page.tsx`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/loading.tsx`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/catalog-table.tsx`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/template-editor.tsx`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/pack-controls.tsx`
- Create: `apps/admin/src/app/(admin)/settings/coach-messages/usage-summary.tsx`
- Modify: `apps/admin/src/components/sidebar.tsx`

**Consumes:** Task 6 actions and existing UI primitives.

**Produces:** a compact operational surface at `/settings/coach-messages`.

- [ ] **Step 1: Add component tests or extracted presenter tests for filter serialization, grouped three-variant display, permission-disabled controls, preview states, and validation errors.**
- [ ] **Step 2: Build a server-rendered page with filters for pack, status, personality, context, channel, and locale.**
- [ ] **Step 3: Build stable desktop/mobile table layouts that show three variants together without nested cards or marketing copy.**
- [ ] **Step 4: Add an editor with explicit channel fields, variable chips, synthetic preview, version comparison, and assisted-draft action.**
- [ ] **Step 5: Add pack controls for clone, validate, schedule, activate, archive, and rollback, hiding or disabling commands according to role.**
- [ ] **Step 6: Add basic selection, suppression, fallback, and failure counts without exposing user identities or message bodies.**
- [ ] **Step 7: Add the sidebar entry using a Lucide icon and verify text containment at mobile and desktop widths.**
- [ ] **Step 8: Run admin tests, typecheck, production build, and visual browser verification against synthetic/local data when the authenticated local shell is available.**
- [ ] **Step 9: Commit `feat(admin-ui): add coach message catalog console`.**

### Task 8: Documentation, Full Verification, Staging, And Draft PR

**Files:**
- Modify: `docs/mobile/api-v1.md`
- Create: `docs/adr/014-bodyflow-coach-message-catalog.md`
- Modify: `docs/superpowers/plans/2026-07-20-bodyflow-personalities-messages-mascot.md`
- Modify if migrations add functions/tables: `packages/db/src/generated/database.ts`

**Produces:** verified staging-only delivery and an auditable layered PR.

- [ ] **Step 1: Document GET/PATCH persona contracts, effective balanced fallback, message-selection failure behavior, catalog governance, and mascot limitations.**
- [ ] **Step 2: Record the architecture decision that recurring messages are deterministic, catalog versions are immutable, monthly refresh is human-approved, and email delivery is disabled.**
- [ ] **Step 3: Run focused suites for core, admin, and Inngest.**
- [ ] **Step 4: Run `pnpm test`, `pnpm typecheck`, `pnpm --filter @mpp/admin build`, changed-file Biome, and `git diff --check`.**
- [ ] **Step 5: Revalidate the linked Supabase ref is exactly `xitugspwfxkcluxvrdeg` and not production. Stop on ambiguity.**
- [ ] **Step 6: Run migration dry-run, apply only the new additive migrations to staging, and never reactivate its 34 cron jobs.**
- [ ] **Step 7: Execute SQL tests transactionally, Supabase DB lint, and advisors; redact IDs and never select copy bodies or user data in reports.**
- [ ] **Step 8: Confirm staging catalog counts only: 1 active pack, 120 groups, 360 logical variants, 1,080 renditions, 0 usage rows, 0 preference rows, 0 mascot rows, and email delivery disabled.**
- [ ] **Step 9: Confirm production was not linked, queried, or modified and no deploy/provider call occurred.**
- [ ] **Step 10: Review the full diff for scope, generated catalog integrity, secrets, PII, RLS, and client-bundle service-role leakage.**
- [ ] **Step 11: Commit final documentation and validation evidence as `docs(bodyflow): complete coach catalog validation`.**
- [ ] **Step 12: Push `codex/bodyflow-personalities-mascot-v1` and open a draft PR with base `codex/bodyflow-push-routine-v1`.**

## Completion Gate

Do not mark Prompt 07 complete unless all conditions hold:

- the worktree is clean;
- every task has its own commit;
- the baseline source and database both prove exactly 1,080 renditions;
- three variants rotate before reuse and balanced fallback never crosses locale;
- no recurring runtime selection calls an LLM;
- every admin mutation is role-checked server-side;
- RLS, grants, internal RPC privileges, and immutable-version invariants pass SQL tests;
- mobile persona GET/PATCH are functional and idempotent;
- mascot state is persisted without visual or guessed behavioral automation;
- staging-only migration validation passes;
- production and external delivery remain untouched;
- the layered draft PR is open with passing available checks.

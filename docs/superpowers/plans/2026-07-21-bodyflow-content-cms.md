# BodyFlow Educational Content CMS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** deliver the bilingual, role-reviewed educational publication CMS and the authenticated mobile v1 content contracts defined by BodyFlow Prompt 08.

**Architecture:** `@mpp/core` owns the portable Markdown and request contracts; PostgreSQL owns immutable reviewed versions, targeting, lifecycle, visibility, user state, metrics, and audit invariants; the Next.js BFF owns authenticated patient DTOs and signed cover capabilities; the existing admin owns the separated editorial workflow. Scheduled visibility is derived from database time and requires no cron.

**Tech Stack:** TypeScript 5, Zod 3, mdast, Vitest 2, Next.js 15 App Router, React 19, Supabase/PostgreSQL, Supabase Storage, pnpm 10.

## Global Constraints

- Work only in `/root/.codex/worktrees/agentempp-bodyflow-content-cms` on `codex/bodyflow-content-cms-v1`.
- Preserve the layered base `3528d27729c55e0f93cced0f466a3e0c45ef1ab7` and do not modify the Prompt 07 worktree.
- Production Supabase project `xuxehkhdvjivitduarvb` remains untouched.
- Database validation and application are allowed only on staging ref `xitugspwfxkcluxvrdeg` after revalidating the link.
- Do not deploy Vercel, configure providers, reactivate cron jobs, send external messages, start Xcode, or execute visual workpack prompts.
- Do not introduce any WhatsApp dependency, route, event, copy, or fallback.
- Locales are exactly `pt-BR` and `en-US`; there is no cross-locale fallback.
- Canonical content is sanitized Markdown. Raw HTML, H1, inline images, embeds, and non-HTTPS links are rejected.
- Editorial roles are exact: `content_editor` authors/submits, `nutrition_admin` reviews, and `master_admin` publishes/schedules/archives.
- Targeting is version-scoped and optional. Configured protocol, plan, and personality dimensions combine with AND; no rows in one dimension mean wildcard.
- Scheduling uses database time and visibility queries; do not add a cron just to flip status.
- Use RED, GREEN, refactor for every production behavior and record the expected RED failure.
- Create migrations with `supabase migration new`; do not invent timestamp prefixes manually.
- Every new public table has RLS, explicit grants, and no direct `PUBLIC`, `anon`, or `authenticated` CMS access.
- Internal functions use a fixed search path, are `SECURITY INVOKER`, are executable only by `service_role`, and revoke default execution.
- Never log or copy article bodies, signed URLs, credentials, access tokens, emails, or patient-identifying data into audit or telemetry.
- New dependencies are exact-pinned and the lockfile is committed.

---

### Task 1: Portable Content Contracts And Markdown Policy

**Files:**
- Create: `packages/core/src/content.ts`
- Create: `packages/core/src/content.test.ts`
- Modify: `packages/core/src/index.ts`
- Modify: `packages/core/package.json`
- Modify: `pnpm-lock.yaml`

**Produces:**

```ts
export const contentLocaleSchema: z.ZodEnum<['pt-BR', 'en-US']>
export const contentCategorySchema: z.ZodEnum<[
  'weight_loss',
  'hypertrophy',
  'nutrition',
  'training',
  'neuroscience',
  'habit_formation',
  'cardiovascular_health',
  'hydration',
  'supplementation',
  'sleep',
  'using_bodyflow',
]>
export const contentSurfaceSchema: z.ZodEnum<['today', 'library', 'saved']>
export const contentOriginSchema: z.ZodEnum<['today', 'library', 'push']>
export const contentReadEventSchema: z.ZodEnum<['impression', 'opened', 'completed']>
export const contentDraftInputSchema: z.ZodType<ContentDraftInput>
export const contentListQuerySchema: z.ZodType<ContentListQuery>
export const contentReadInputSchema: z.ZodType<ContentReadInput>
export const contentSaveInputSchema: z.ZodType<ContentSaveInput>
export const contentCoverInputSchema: z.ZodType<ContentCoverInput>

export type ContentMarkdownInline =
  | { type: 'text'; value: string }
  | { type: 'strong' | 'emphasis'; children: ContentMarkdownInline[] }
  | { type: 'link'; url: string; children: ContentMarkdownInline[] }

export type ContentMarkdownBlock =
  | { type: 'paragraph'; children: ContentMarkdownInline[] }
  | { type: 'heading'; level: 2 | 3; children: ContentMarkdownInline[] }
  | { type: 'blockquote'; children: ContentMarkdownBlock[] }
  | { type: 'list'; ordered: boolean; items: ContentMarkdownBlock[][] }

export interface ValidatedContentMarkdown {
  normalized: string
  blocks: ContentMarkdownBlock[]
  wordCount: number
  readingTimeMinutes: number
}

export function validateContentMarkdown(value: string): ValidatedContentMarkdown
export function encodeContentCursor(input: { publishAt: string; publicationId: string }): string
export function decodeContentCursor(value: string): { publishAt: string; publicationId: string }
```

- [x] **Step 1: Add exact parser dependencies.**

Run:

```bash
pnpm add --save-exact --filter @mpp/core \
  mdast-util-from-markdown@2.0.3 \
  mdast-util-to-markdown@2.1.2
pnpm add --save-exact --save-dev --filter @mpp/core @types/mdast@4.0.4
```

- [x] **Step 2: Write RED tests for exact enums, strict draft limits, normalized tags, content-cover MIME/size limits, query defaults, and strict unknown-key rejection.**
- [x] **Step 3: Write RED Markdown tests for the accepted AST subset and rejection of HTML, H1, code, thematic breaks, inline images, nested embeds, non-HTTPS URLs, malformed nodes, depth over eight, body under 100 characters, and body over 50,000 characters.**
- [x] **Step 4: Run `pnpm --filter @mpp/core test -- content.test.ts`.**

Expected: FAIL because `content.ts` does not exist.

- [x] **Step 5: Implement schemas and the mdast-to-portable-block conversion without rendering HTML.**

The parser must normalize CRLF, round reading time at 200 words/minute with a minimum of one, and reject unsupported nodes rather than dropping them.

- [x] **Step 6: Add RED tests for opaque cursor round-trip and malformed, oversized, non-UUID, and non-ISO cursor rejection.**
- [x] **Step 7: Implement base64url cursor encoding/decoding with a 512-character input cap and strict Zod validation.**
- [x] **Step 8: Export the contracts, run `pnpm --filter @mpp/core test` and `pnpm --filter @mpp/core typecheck`, then run `git diff --check`.**
- [x] **Step 9: Commit `feat(core): add educational content contracts`.**

### Task 2: CMS Persistence, Covers, Editorial Lifecycle, And RBAC

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_content_cms_domain`
- Create: `supabase/tests/bodyflow_content_cms.sql`

**Consumes:** strict values and normalized payloads from Task 1.

**Produces:**

```sql
public.content_publications
public.content_assets
public.content_versions
public.content_version_target_protocols
public.content_version_target_plans
public.content_version_target_personalities
public.content_user_state
public.content_events

public.create_content_publication(p_actor_id uuid, p_slug text) returns jsonb
public.create_content_draft(
  p_actor_id uuid,
  p_publication_id uuid,
  p_locale text,
  p_source_version_id uuid default null
) returns jsonb
public.save_content_draft(
  p_actor_id uuid,
  p_version_id uuid,
  p_expected_updated_at timestamptz,
  p_draft jsonb
) returns jsonb
public.submit_content_version(
  p_actor_id uuid,
  p_version_id uuid,
  p_expected_updated_at timestamptz
) returns jsonb
public.review_content_version(
  p_actor_id uuid,
  p_version_id uuid,
  p_decision text,
  p_rejection_reason text default null
) returns jsonb
public.publish_content_version(
  p_actor_id uuid,
  p_version_id uuid,
  p_publish_at timestamptz default null
) returns jsonb
public.archive_content_publication(
  p_actor_id uuid,
  p_publication_id uuid
) returns jsonb
public.create_content_asset(
  p_actor_id uuid,
  p_asset_id uuid,
  p_mime_type text,
  p_declared_size_bytes bigint,
  p_object_path text
) returns jsonb
public.complete_content_asset(
  p_actor_id uuid,
  p_asset_id uuid,
  p_actual_size_bytes bigint,
  p_etag text
) returns jsonb
public.delete_content_asset(p_actor_id uuid, p_asset_id uuid) returns jsonb
```

- [ ] **Step 1: Write a transactional RED SQL test requiring all eight relations, RLS, indexes, constraints, trigger guards, no client privileges, and service-only `SECURITY INVOKER` functions.**

The test must use synthetic admin accounts for all three editorial roles and prove that each role is denied the other two responsibilities.

- [ ] **Step 2: Add RED lifecycle cases for immutable slug, monotonic versions, one draft per publication/locale, stale `updated_at` conflict, submitted-version immutability, author/reviewer separation, required rejection reason, review-before-publish, minimum five-minute scheduling, and global archive.**
- [ ] **Step 3: Run the SQL test transactionally against staging before migration and confirm the expected missing-relation failure.**
- [x] **Step 4: Run `supabase migration new bodyflow_content_cms_domain`.**
- [x] **Step 5: Implement the eight tables, foreign keys, checks, indexes, updated-at/immutability triggers, RLS, and explicit grants.**

Required database invariants include:

```sql
UNIQUE (publication_id, version)
CREATE UNIQUE INDEX content_versions_one_draft_per_locale_idx
  ON public.content_versions (publication_id, locale)
  WHERE state = 'draft'
CHECK (locale IN ('pt-BR', 'en-US'))
CHECK (state IN ('draft', 'in_review', 'approved', 'rejected'))
CHECK (char_length(title) BETWEEN 3 AND 120)
CHECK (char_length(excerpt) BETWEEN 20 AND 280)
CHECK (char_length(body_markdown) BETWEEN 100 AND 50000)
CHECK (body_hash ~ '^[0-9a-f]{64}$')
CHECK (reading_time_minutes BETWEEN 1 AND 500)
```

The database recomputes `body_hash` with `pgcrypto`; it does not trust a hash from the client.

- [x] **Step 6: Implement the authoring, review, publishing, archive, and asset RPCs with actor-role validation and `audit_log` rows containing IDs, state, schedule, and hash only.**
- [x] **Step 7: Implement target replacement inside `save_content_draft`; target tables are keyed by version and accept only existing enum/reference values.**
- [x] **Step 8: Prove cover paths are server-shaped as `content/<asset-id>.<ext>`, objects must be uploaded before attachment, and referenced assets cannot be deleted.**
- [ ] **Step 9: Execute the migration SQL plus the SQL suite inside one transaction that always rolls back, confirm no schema or synthetic rows remain, then run migration SQL lint/static checks and `git diff --check`.**
- [x] **Step 10: Commit `feat(database): add educational content CMS domain`.**

### Task 3: Deterministic Visibility, Targeting, State, And Metrics

**Files:**
- Create with Supabase CLI: migration basename `bodyflow_content_delivery`
- Create: `supabase/tests/bodyflow_content_delivery.sql`

**Consumes:** Task 2 versioned CMS tables.

**Produces:**

```sql
public.list_mobile_content(
  p_user_id uuid,
  p_surface text default 'library',
  p_category text default null,
  p_limit integer default 20,
  p_cursor_publish_at timestamptz default null,
  p_cursor_publication_id uuid default null,
  p_now timestamptz default clock_timestamp()
) returns jsonb

public.get_mobile_content(
  p_user_id uuid,
  p_publication_id uuid,
  p_now timestamptz default clock_timestamp()
) returns jsonb

public.record_mobile_content_event(
  p_user_id uuid,
  p_publication_id uuid,
  p_version integer,
  p_event_type text,
  p_origin text,
  p_event_key text,
  p_now timestamptz default clock_timestamp()
) returns jsonb

public.set_mobile_content_saved(
  p_user_id uuid,
  p_publication_id uuid,
  p_version integer,
  p_saved boolean,
  p_origin text,
  p_event_key text,
  p_now timestamptz default clock_timestamp()
) returns jsonb
```

- [ ] **Step 1: Write RED SQL cases for exact patient locale, no translation fallback, newest due approved version, future schedule exclusion, replacement without downtime, global archive, today feature filtering, saved filtering, stable cursor ordering, and category filtering.**
- [ ] **Step 2: Add RED targeting cases for wildcard dimensions, protocol-only, plan-only, personality-only, all-three AND matching, missing patient attributes, expired subscriptions, and non-selectable `balanced`.**
- [ ] **Step 3: Add RED state/metric cases for impression, opened/click, completed version, saved persistence across revisions, completion reset on a new visible version, stale version conflict, event-key hashing, event retry, and save no-op without a duplicate event.**
- [ ] **Step 4: Run the SQL test and confirm missing-function failures.**
- [x] **Step 5: Run `supabase migration new bodyflow_content_delivery`.**
- [x] **Step 6: Implement one canonical eligible-version SQL relation inside each read RPC, using the user's stored locale, profile protocol, active/trial non-expired subscription, and selected coach personality.**

The query chooses the latest row by `publish_at DESC, version DESC`, then pages publications by `publish_at DESC, publication_id DESC`. It never accepts locale or targeting attributes from the client.

- [x] **Step 7: Implement event/state RPCs with row locks, a SHA-256 event key, a unique patient/event-key constraint, version visibility recheck, and successful replay semantics.**
- [x] **Step 8: Ensure RPC results include internal cover bucket/path only for the trusted BFF and contain no signed URL or patient PII.**
- [ ] **Step 9: Execute both migration files plus both CMS SQL suites inside one transaction that always rolls back, and confirm no schema or synthetic rows remain before the final staging rollout.**
- [x] **Step 10: Commit `feat(database): add deterministic content delivery`.**

### Task 4: Authenticated Mobile Content BFF

**Files:**
- Create: `apps/admin/src/lib/mobile-api/content-service.ts`
- Create: `apps/admin/src/lib/mobile-api/content-service.test.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-content.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-content.test.ts`
- Modify: `apps/admin/src/lib/mobile-api/contracts.test.ts`
- Modify: `apps/admin/src/app/api/mobile/v1/content/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/content/route.test.ts`
- Create: `apps/admin/src/app/api/mobile/v1/content/[id]/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/content/[id]/read/route.ts`
- Create: `apps/admin/src/app/api/mobile/v1/content/[id]/save/route.ts`

**Consumes:** Task 1 schemas and Task 3 RPCs.

**Produces:**

```ts
export interface ContentRepository {
  list(userId: string, query: ContentListQuery): Promise<ContentFeedPage>
  get(userId: string, publicationId: string): Promise<ContentRecord | null>
  recordRead(input: ContentReadCommand): Promise<ContentUserState>
  setSaved(input: ContentSaveCommand): Promise<ContentUserState>
}

export interface ContentCoverGateway {
  issue(input: {
    userId: string
    publicationId: string
    version: number
  }): Promise<{ token: string; expiresAt: string }>
}

export interface ContentServiceDependencies {
  repository: ContentRepository
  covers: ContentCoverGateway
}

export function listContent(
  dependencies: ContentServiceDependencies,
  auth: MobileAuthContext,
  query: ContentListQuery,
): Promise<ContentFeedDto>

export function getContent(
  dependencies: ContentServiceDependencies,
  auth: MobileAuthContext,
  publicationId: string,
): Promise<ContentDetailDto>
```

- [x] **Step 1: Write RED service tests for list/detail DTOs, cursor construction, cover expiry, no internal path leakage, no-content `404`, capability failure, read/save commands, and stale-version mapping.**
- [x] **Step 2: Run `pnpm --filter @mpp/admin test -- content-service.test.ts` and confirm the missing-module failure.**
- [x] **Step 3: Implement the service with a 300-second cover capability and no cross-locale fallback.**
- [x] **Step 4: Write RED Supabase adapter tests for RPC names/parameters, malformed RPC payloads, null detail, opaque database errors, and opaque capability issuance for `content-covers`.**
- [x] **Step 5: Implement the Supabase repository/gateway with Zod parsing and technical-ID-only error logs.**
- [x] **Step 6: Write RED route tests for authenticated list/detail, strict query validation, UUID validation, `404` non-disclosure, required JSON content type, required `Idempotency-Key`, idempotent replay, and `409 content_version_changed`.**
- [x] **Step 7: Replace the unavailable placeholder route and add detail/read/save routes using `createMobileRoute`, `createMobileRouteWithContext`, `executeSupabaseIdempotent`, and existing response envelopes.**
- [x] **Step 8: Store no cover capability in generic idempotency responses; read/save responses contain only consolidated state.**
- [x] **Step 9: Run focused admin tests, admin typecheck, and `git diff --check`.**
- [x] **Step 10: Commit `feat(mobile-api): expose eligible educational content`.**

### Task 5: Admin Domain Services, Cover Capabilities, And Server Actions

**Files:**
- Create: `apps/admin/src/lib/content/admin-service.ts`
- Create: `apps/admin/src/lib/content/admin-service.test.ts`
- Create: `apps/admin/src/lib/content/supabase-repository.ts`
- Create: `apps/admin/src/app/(admin)/content/actions-core.ts`
- Create: `apps/admin/src/app/(admin)/content/actions.test.ts`
- Create: `apps/admin/src/app/(admin)/content/actions.ts`
- Modify: `apps/admin/src/lib/admin-rbac.ts`

**Consumes:** Task 1 validation and Task 2 lifecycle/asset RPCs.

**Produces:**

```ts
export const CONTENT_AUTHOR_ROLES = ['content_editor'] as const
export const CONTENT_REVIEW_ROLES = ['nutrition_admin'] as const
export const CONTENT_PUBLISH_ROLES = ['master_admin'] as const

export type ContentAdminAction =
  | { type: 'list'; input: ContentAdminFilters }
  | { type: 'get'; input: { publicationId: string } }
  | { type: 'createPublication'; input: { slug: string } }
  | { type: 'createDraft'; input: CreateContentDraftInput }
  | { type: 'saveDraft'; input: SaveContentDraftInput }
  | { type: 'submit'; input: ContentVersionPrecondition }
  | { type: 'review'; input: ReviewContentVersionInput }
  | { type: 'publish'; input: PublishContentVersionInput }
  | { type: 'archive'; input: { publicationId: string } }
  | { type: 'createCover'; input: ContentCoverInput }
  | { type: 'completeCover'; input: { assetId: string } }
  | { type: 'deleteCover'; input: { assetId: string } }

export function executeContentAdminAction(
  action: ContentAdminAction,
  dependencies: ContentAdminActionDependencies,
): Promise<unknown>
```

- [x] **Step 1: Add RED role tests proving support/operations roles cannot access the module, content editors cannot review/publish, nutrition admins cannot author/publish, and master admins cannot author/review.**
- [x] **Step 2: Add RED service tests for publication listing, draft validation, Markdown normalization, stale preconditions, copy-from-version, audit-safe repository payloads, and lifecycle error mapping.**
- [x] **Step 3: Implement the repository/service and preserve the existing broader `CONTENT_ADMIN_ROLES` behavior used by coach-message governance.**
- [x] **Step 4: Add RED cover tests for exact MIME/size, server UUID/path generation, signed upload with `upsert: false`, object info verification, mismatch cleanup, attach-only-after-upload, signed URL redaction, and referenced-cover deletion denial.**
- [x] **Step 5: Implement cover creation/completion/deletion with the server-only storage client and Task 2 asset RPCs.**
- [x] **Step 6: Add RED action tests for fresh authenticated role lookup on every action and for all action-to-role mappings.**
- [x] **Step 7: Implement server actions, revalidate `/content` and `/content/[id]` after successful mutations, and return bounded Portuguese admin errors without provider/database details.**
- [x] **Step 8: Run `pnpm --filter @mpp/admin test -- admin-service.test.ts actions.test.ts` and admin typecheck.**
- [x] **Step 9: Commit `feat(admin): govern educational publications`.**

### Task 6: Operational Editorial UI

**Files:**
- Create: `apps/admin/src/app/(admin)/content/page.tsx`
- Create: `apps/admin/src/app/(admin)/content/loading.tsx`
- Create: `apps/admin/src/app/(admin)/content/publication-table.tsx`
- Create: `apps/admin/src/app/(admin)/content/new/page.tsx`
- Create: `apps/admin/src/app/(admin)/content/[id]/page.tsx`
- Create: `apps/admin/src/app/(admin)/content/[id]/editor.tsx`
- Create: `apps/admin/src/app/(admin)/content/[id]/markdown-preview.tsx`
- Create: `apps/admin/src/app/(admin)/content/[id]/cover-uploader.tsx`
- Create: `apps/admin/src/app/(admin)/content/[id]/workflow-controls.tsx`
- Create: `apps/admin/src/app/(admin)/content/presenter.ts`
- Create: `apps/admin/src/app/(admin)/content/presenter.test.ts`
- Modify: `apps/admin/src/components/sidebar.tsx`
- Modify: `apps/admin/src/components/command-palette.tsx`

**Consumes:** Task 1 portable Markdown blocks and Task 5 server actions.

- [x] **Step 1: Write RED presenter tests for effective status, locale completeness, role-visible commands, schedule labels, active-version selection, and no body/signed-path exposure in list rows.**
- [x] **Step 2: Implement pure presentation helpers and run the focused test.**
- [x] **Step 3: Build `/content` as a dense table with status, locale, category, author/reviewer, schedule, featured, and text filters plus a clear create command.**
- [x] **Step 4: Build `/content/new` with slug creation and explicit locale-draft creation.**
- [x] **Step 5: Build the publication editor with separate `pt-BR` and `en-US` tabs, title, excerpt, category, normalized tag input, feature toggle, protocol/plan/personality multiselects, cover upload, stable textarea dimensions, and portable-block preview.**
- [x] **Step 6: Render Markdown blocks as React elements without `dangerouslySetInnerHTML`; external HTTPS links use `rel="noopener noreferrer"`.**
- [x] **Step 7: Build read-only review controls, required rejection reason, publication/schedule confirmation dialogs, stale-conflict feedback, and global archive confirmation.**
- [x] **Step 8: Gate the page and every visible command by the exact role while retaining server-side enforcement.**
- [x] **Step 9: Add `Publicacoes` with a `Newspaper` Lucide icon to sidebar and command palette.**
- [ ] **Step 10: Run admin tests, admin typecheck, admin build, changed-file Biome, and `git diff --check`.**
- [x] **Step 11: Commit `feat(admin-ui): add educational publication workspace`.**

### Task 7: Contracts, ADR, And Full Local Verification

**Files:**
- Modify: `docs/mobile/api-v1.md`
- Create: `docs/adr/015-bodyflow-educational-content-cms.md`
- Modify: `docs/superpowers/plans/2026-07-21-bodyflow-content-cms.md`

- [x] **Step 1: Replace the reserved content documentation with exact list/detail/read/save contracts, query/body examples, errors, idempotency, locale isolation, segment matching, cover expiry, and caching behavior.**
- [x] **Step 2: Record the architecture decision for immutable localized versions, version-scoped targets, private covers, derived scheduling, separated review, and BFF-only patient access.**
- [ ] **Step 3: Run `pnpm --filter @mpp/core test`, `pnpm --filter @mpp/admin test`, and every CMS SQL suite transactionally.**
- [ ] **Step 4: Run `pnpm test`, `pnpm typecheck`, `pnpm --filter @mpp/admin build`, changed-file Biome, secret/PII scans, and `git diff --check`.**
- [ ] **Step 5: Review the full branch diff for spec coverage, SQL injection, RLS/grants, service-role client leakage, unsafe Markdown, stale-write loss, visibility leaks, pagination gaps, idempotency gaps, and object-path exposure.**
- [ ] **Step 6: Fix every Critical/Important review finding and repeat its covering tests.**
- [ ] **Step 7: Commit `docs(bodyflow): document educational content contracts`.**

### Task 8: Staging Migration, Canary, Generated Types, And Draft PR

**Files:**
- Modify after verified staging schema: `packages/db/src/generated/database.ts`
- Modify: `docs/superpowers/plans/2026-07-21-bodyflow-content-cms.md`

Toda execução SQL live, incluindo as suites CMS, permanece reservada para esta
Task 8. Evidência estática ou local anterior não substitui essa validação.

- [ ] **Step 1: Confirm the worktree path/branch and verify `supabase/.temp/project-ref` is exactly `xitugspwfxkcluxvrdeg` and is not `xuxehkhdvjivitduarvb`; stop on ambiguity.**
- [ ] **Step 2: Confirm staging still has 34 cron jobs and zero active jobs without selecting job commands.**
- [ ] **Step 3: Run `supabase migration list --linked`, migration dry-run, and review that only the new additive CMS migrations are pending.**
- [ ] **Step 4: Apply only those migrations to staging. Do not deploy an application or configure any secret/integration.**
- [ ] **Step 5: Run both SQL suites transactionally, Supabase DB lint, and advisors. Distinguish new findings from pre-existing findings.**
- [ ] **Step 6: Regenerate `packages/db/src/generated/database.ts` from staging using ref `xitugspwfxkcluxvrdeg`, review the generated diff for unrelated drift, and rerun DB/admin typecheck.**
- [ ] **Step 7: Execute synthetic rollback-safe canaries for the complete workflow:** author draft, both locales, Markdown rejection, technical approval, immediate publication, future schedule, universal and three-dimension targeting, exact-locale feed/detail, read/save retry, short-lived cover capability, replacement without downtime, archive, e um canário concorrente de duas sessões para o `one-open-workflow`, cobrindo `create/submit/review` concorrendo com outro `create` da mesma publicação e locale.
- [ ] **Step 8: Confirm aggregate-only staging postconditions: zero retained synthetic publications/assets/events/states, zero active cron jobs, no public/authenticated CMS grants, and no client-executable internal CMS functions.**
- [ ] **Step 9: Confirm production was not linked, queried, modified, or deployed and no external provider was called.**
- [ ] **Step 10: Run final `pnpm test`, `pnpm typecheck`, admin build, Biome, and `git diff --check` after generated types.**
- [ ] **Step 11: Record redacted verification evidence and commit `docs(bodyflow): complete educational CMS validation`.**
- [ ] **Step 12: Push `codex/bodyflow-content-cms-v1` and open a draft PR with base `codex/bodyflow-personalities-mascot-v1`.**

## Completion Gate

Do not mark Prompt 08 complete unless all conditions hold:

- the worktree is clean and every implementation slice has its own commit;
- Markdown validation rejects every unsupported or unsafe construct and never renders HTML;
- live content remains visible while a replacement is drafted/reviewed/scheduled;
- each locale publishes independently with no fallback;
- content-editor, nutrition-reviewer, and master-publisher responsibilities are separately enforced in app and database;
- targeting is version-scoped and all configured dimensions match;
- draft, review, publication, schedule, archive, cover, and audit invariants pass SQL tests;
- mobile list/detail/read/save are authenticated, idempotent where mutable, and disclose no ineligible content or storage path;
- events count impression, open/click, completion, save, and unsave without duplicate retries;
- staging-only migration and synthetic canary validation pass with all 34 crons inactive;
- production, Vercel deployment, Xcode, visual prompts, external integrations, and external delivery remain untouched;
- the layered draft PR is open with all available checks passing.

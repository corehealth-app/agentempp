# Dedicated Public Mobile BFF Surface Specification

**Date:** 2026-08-25

**Status:** authorized design for implementation and Preview verification;
production and CI-4 are not authorized

**Architecture:** `DEDICATED_NEXTJS_MOBILE_BFF_ARTIFACT`

**RED 1 discovery authority:** reconciled at dossier `1.6.8`; this authority
supersedes only the prior RED 1 runner command and the obsolete final-outcome
parent/version clauses. Historical evidence remains authoritative for what was
attempted and observed.

**Vercel local-link reconciliation:** for every future execution, dossier
`1.6.10` and Section 15 wholly supersede legacy Tasks/Sections 9–16. The old
text is retained only as historical evidence and must not control ordering,
gates, worktree choice or final-documentation authority.

## 1. Decision and motivation

The existing staging Vercel project was configured with root `apps/admin` and
inherits Vercel Authentication. Removing that protection from the shared
artifact is unsafe: the complete application-layer audit found 21 blocking
admin surfaces in three families—one middleware-exempt route that accepts the
service-role credential as a public bearer, two food-management Server Actions
without their own admin authorization, and 18 privileged admin pages without
authorization colocated with their data access.

This gate does not repair or expose those 21 surfaces. It isolates public
Mobile API ingress in a separate Next.js application:

```text
apps/mobile-bff
package: @mpp/mobile-bff
public route prefix: /api/mobile/v1/**
```

The dedicated artifact must contain no admin pages, authenticated dashboard
pages, root page, login, Server Actions, admin middleware, `/api/admin/**`,
`/api/inngest/**`, `/api/stripe/**`, administrative `/api/media/**`, webhooks,
panel callbacks, panel static assets or any application route outside
`/api/mobile/v1/**`.

## 2. Source-of-truth and mirror contract

Official Mobile API handler logic remains in exactly one place:

```text
apps/admin/src/app/api/mobile/v1/**/route.ts
```

The dedicated app creates one static wrapper for each frozen source route at
the corresponding relative path beneath:

```text
apps/mobile-bff/src/app/api/mobile/v1/
```

Each wrapper may contain a stable generated comment and exactly one named
re-export statement. It must contain no executable logic, alternate handler,
fallback, catch-all, auth logic, URL or token. `export *` is prohibited. The
wrapper must re-export exactly the names exported by its source module; it may
not add or omit a name.

The `@/*` alias in the dedicated app maps exclusively to
`../admin/src/*`. The webpack alias must be equivalent. The monorepo root is
the `outputFileTracingRoot`. Existing workspace package extension aliases are
preserved, and only transitively reached workspace packages are listed in
`transpilePackages`.

No existing route module may be changed. Handler logic may not be copied or
duplicated.

## 3. Frozen source route manifest

Every path below is relative to:

```text
apps/admin/src/app/api/mobile/v1/
```

Canonicalization sorts relative paths lexicographically, sorts export names
for each route lexicographically, and encodes each record as:

```text
<relative-path>\0<comma-separated-export-names>\n
```

This is the **source route/export stream**. Frozen values:

- route modules: `40`;
- `SOURCE_ROUTE_EXPORT_STREAM_SHA256`:
  `7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`;
- invalid exports: `0`.

```text
coach/persona/route.ts\tGET,PATCH,runtime
content/[id]/read/route.ts\tPOST,runtime
content/[id]/route.ts\tGET,runtime
content/[id]/save/route.ts\tPOST,runtime
content/covers/[token]/route.ts\tGET,runtime
content/route.ts\tGET,runtime
devices/[id]/route.ts\tDELETE,runtime
devices/route.ts\tGET,POST,runtime
entitlements/route.ts\tGET,runtime
history/route.ts\tGET,runtime
legal/medication-reminder-disclaimer/accept/route.ts\tPOST,runtime
legal/medication-reminder-disclaimer/route.ts\tGET,runtime
me/route.ts\tGET,PATCH,runtime
media/[id]/complete/route.ts\tPOST,runtime
media/[id]/process/route.ts\tPOST,runtime
media/[id]/route.ts\tDELETE,GET,runtime
media/route.ts\tPOST,runtime
medications/[id]/history/route.ts\tGET,runtime
medications/[id]/log/route.ts\tPOST,runtime
medications/[id]/route.ts\tDELETE,PATCH,runtime
medications/route.ts\tGET,POST,runtime
notification-preferences/route.ts\tGET,PATCH,runtime
onboarding/route.ts\tPOST,runtime
pending/route.ts\tGET,runtime
plan/route.ts\tGET,runtime
profile/route.ts\tGET,runtime
progress/route.ts\tGET,runtime
registrations/[id]/confirm/route.ts\tPOST,runtime
registrations/[id]/route.ts\tDELETE,PATCH,runtime
registrations/propose/route.ts\tPOST,runtime
reminders/[id]/route.ts\tPATCH,runtime
reminders/route.ts\tGET,POST,runtime
routine/hydration/route.ts\tPOST,runtime
routine/medications/[id]/taken/route.ts\tPOST,runtime
routine/supplements/[id]/taken/route.ts\tPOST,runtime
supplements/[id]/history/route.ts\tGET,runtime
supplements/[id]/log/route.ts\tPOST,runtime
supplements/[id]/route.ts\tDELETE,PATCH,runtime
supplements/route.ts\tGET,POST,runtime
today/route.ts\tGET,runtime
```

The only valid Next Route Handler exports for this mirror are:

```text
GET POST PUT PATCH DELETE HEAD OPTIONS runtime dynamic revalidate fetchCache
preferredRegion maxDuration dynamicParams
```

Any source export outside this allowlist, any route-count or path drift, or any
canonical hash mismatch is a material STOP before wrapper generation.

### 3.1 Separate wrapper and build-route streams

Three different receipts are normative and must never be conflated:

1. `SOURCE_ROUTE_EXPORT_STREAM`: paths relative to
   `apps/admin/src/app/api/mobile/v1/`, encoded exactly as defined above.
2. `WRAPPER_ROUTE_EXPORT_STREAM`: paths relative to
   `apps/mobile-bff/src/app/api/mobile/v1/`, sorted lexicographically; export
   names for each wrapper sorted lexicographically; each record encoded as
   `<relative-path>\0<comma-separated-export-names>\n`.
3. `BUILD_ROUTE_PATH_STREAM`: map each frozen source
   `<segments>/route.ts` to `/api/mobile/v1/<segments>`, preserving dynamic
   segment spelling such as `[id]` and `[token]`; sort the URL templates
   lexicographically and encode each as `<route-url>\n`. The Next-generated
   internal `/_not-found` is permitted only as an observed internal route and
   is excluded from this canonical stream.

Because wrapper path/export parity is exact by contract, the source and wrapper
streams have equal bytes but retain distinct names and receipt fields:

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
WRAPPER_ROUTE_EXPORT_COUNT=40
WRAPPER_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
BUILD_ROUTE_PATH_COUNT=40
BUILD_ROUTE_PATH_STREAM_SHA256=abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a
```

The exact build-route stream is:

```text
/api/mobile/v1/coach/persona
/api/mobile/v1/content
/api/mobile/v1/content/[id]
/api/mobile/v1/content/[id]/read
/api/mobile/v1/content/[id]/save
/api/mobile/v1/content/covers/[token]
/api/mobile/v1/devices
/api/mobile/v1/devices/[id]
/api/mobile/v1/entitlements
/api/mobile/v1/history
/api/mobile/v1/legal/medication-reminder-disclaimer
/api/mobile/v1/legal/medication-reminder-disclaimer/accept
/api/mobile/v1/me
/api/mobile/v1/media
/api/mobile/v1/media/[id]
/api/mobile/v1/media/[id]/complete
/api/mobile/v1/media/[id]/process
/api/mobile/v1/medications
/api/mobile/v1/medications/[id]
/api/mobile/v1/medications/[id]/history
/api/mobile/v1/medications/[id]/log
/api/mobile/v1/notification-preferences
/api/mobile/v1/onboarding
/api/mobile/v1/pending
/api/mobile/v1/plan
/api/mobile/v1/profile
/api/mobile/v1/progress
/api/mobile/v1/registrations/[id]
/api/mobile/v1/registrations/[id]/confirm
/api/mobile/v1/registrations/propose
/api/mobile/v1/reminders
/api/mobile/v1/reminders/[id]
/api/mobile/v1/routine/hydration
/api/mobile/v1/routine/medications/[id]/taken
/api/mobile/v1/routine/supplements/[id]/taken
/api/mobile/v1/supplements
/api/mobile/v1/supplements/[id]
/api/mobile/v1/supplements/[id]/history
/api/mobile/v1/supplements/[id]/log
/api/mobile/v1/today
```

## 4. Exact implementation boundary

The implementation may create or modify only:

```text
apps/mobile-bff/package.json
apps/mobile-bff/tsconfig.json
apps/mobile-bff/next.config.mjs
apps/mobile-bff/vitest.config.ts
apps/mobile-bff/next-env.d.ts
apps/mobile-bff/scripts/verify-route-mirror.mjs
apps/mobile-bff/scripts/verify-import-closure.mjs
apps/mobile-bff/scripts/verify-build-surface.mjs
apps/mobile-bff/src/route-mirror.test.ts
apps/mobile-bff/src/import-closure.test.ts
apps/mobile-bff/src/source-surface.test.ts
apps/mobile-bff/src/app/api/mobile/v1/**/route.ts
pnpm-lock.yaml
```

It must not change root `package.json`, `pnpm-workspace.yaml`, `apps/admin`,
packages, docs, migrations, Supabase files, iOS, assets or strings. The
workspace already includes `apps/*`.

The new package scripts are exactly the functional gates needed here:
`build`, `test`, `typecheck`, `verify:routes`, `verify:imports` and
`verify:build-surface`. Lint is not added as a gate without a dedicated config.

## 5. Dependency and import-closure boundary

The app may import only:

1. the 40 frozen source route modules;
2. their strictly necessary transitive closure;
3. workspace packages and external dependencies required by that closure.

Workspace and external dependencies are derived, not guessed. Next, React and
ReactDOM use the versions already resolved by the lockfile. No existing range
or package version may change. `@mpp/admin` may be declared as `workspace:*`
only if needed to install dependencies of imported source files and never as a
runtime package-root import. The lockfile may change only by adding the new
importer/package; any unexpected resolution is a STOP.

The closure verifier resolves relative imports and `@` imports and rejects:

```text
apps/admin/src/app/(admin)/**
apps/admin/src/app/api/admin/**
apps/admin/src/app/api/inngest/**
apps/admin/src/app/api/stripe/**
apps/admin/src/app/api/media/**
apps/admin/src/middleware.ts
apps/admin/src/lib/public-api-path.ts
any page.tsx
any layout.tsx
any file under public/
any webhook
any panel callback
any file with 'use server' outside the Mobile API
```

Explicitly permitted roots are the Mobile API routes,
`apps/admin/src/lib/mobile-api/**`,
`apps/admin/src/lib/supabase/server.ts`, and other local libraries only when
the resolved closure proves necessity and the file is not an HTTP surface,
Server Action or admin UI. The verifier prints paths and classifications only,
never secret values.

## 6. Source, build and runtime proofs

The source-surface proof must report:

- source routes `40` and the frozen path/export hash;
- wrapper routes `40` with exact path and named-export parity;
- zero extra or omitted wrappers;
- zero `export *`, catch-all, root page, layout, middleware, public file,
  Server Action or route outside `/api/mobile/v1/**`.

After build, structured parsers—not grep alone—must inspect the actual Next 15
manifests, including the equivalents of:

```text
.next/server/app-paths-manifest.json
.next/routes-manifest.json
.next/server/middleware-manifest.json
.next/server/server-reference-manifest.json
```

They must prove that every application route is inside `/api/mobile/v1/**`,
apart from an internal `/_not-found` generated by Next; the Mobile route count
and path-stream hash match the frozen manifest; middleware is empty; Server
Action references are zero; and admin, Inngest, Stripe, administrative media
and page routes are absent.

The loopback smoke starts only the dedicated build with synthetic values on an
ephemeral local port. Required results are:

| Request | Required result |
| --- | --- |
| `GET /api/mobile/v1/today` | Mobile API `401` JSON |
| `GET /api/mobile/v1/me` | Mobile API `401` JSON |
| `GET /api/mobile/v1/content/00000000-0000-4000-8000-000000000000` | auth-first Mobile API `401` or compatible auth envelope |
| `GET /` | `404` |
| `GET /login` | `404` |
| `GET /dashboard` | `404` |
| `GET /api/admin/send-message` | `404` |
| `GET /api/inngest` | `404` |
| `GET /api/stripe/webhook` | `404` |
| `GET /api/media/00000000-0000-4000-8000-000000000000` | `404` |

Every 401 must be JSON, sanitized and non-HTML, with `Cache-Control` containing
`no-store`, `Vary` containing `Authorization`, and a request ID. Every 404 must
avoid redirects, login rendering, sensitive handler execution, stack traces,
secrets and PII.

### 6.1 Frozen 21-finding acceptance inventory

The prior 21 blockers split into 19 HTTP-reachable records and two Server
Actions that are manifest-only. The HTTP stream sorts paths lexicographically
and encodes every record as `<METHOD>\0<concrete-path>\n`. Dynamic page routes
use the non-sensitive UUID `00000000-0000-4000-8000-000000000000`.

```text
GET\0/api/admin/send-message
GET\0/audit
GET\0/crescimento
GET\0/dashboard
GET\0/evaluations
GET\0/formulas
GET\0/messages
GET\0/prompts
GET\0/prompts/00000000-0000-4000-8000-000000000000
GET\0/settings/admins
GET\0/settings/agents
GET\0/settings/api-keys
GET\0/settings/calc
GET\0/settings/crons
GET\0/settings/foods
GET\0/settings/global
GET\0/settings/tools
GET\0/users
GET\0/users/00000000-0000-4000-8000-000000000000
```

```text
PRIOR_FINDING_HTTP_PROBE_COUNT=19
PRIOR_FINDING_HTTP_PROBE_STREAM_SHA256=8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718
```

Every one of the 19 HTTP paths must return 404 with zero redirect, login render,
sensitive handler execution, stack, secret or PII, locally and after SSO is
removed. The two food actions are never invoked. Their manifest-only stream
sorts export names lexicographically and encodes each as `<export-name>\n`:

```text
deleteFood
upsertFood
```

```text
PRIOR_FINDING_SERVER_ACTION_COUNT=2
PRIOR_FINDING_SERVER_ACTION_STREAM_SHA256=2cc8eac1a54c3f88673701d4b9ede202f1ec4440bf414ac7696dda341bd53a35
```

Source inspection must still locate both names in
`apps/admin/src/app/(admin)/settings/foods/actions.ts`; source and structured
server-reference manifests for the dedicated app must contain zero references
to either action and zero Server Action references in total. Page routes must
also be absent from structured manifests; HTTP 404 probes do not replace that
proof.

## 7. TDD and local gates

Implementation proceeds in the following proof sequence:

1. RED source surface: frozen source is 40, wrappers are zero, failure is for
   the absent mirror.
2. GREEN mirror: package/config and all 40 exact wrappers produce 40/40 parity.
3. RED closure/surface: tests fail while verifier/configuration proofs are
   absent.
4. GREEN closure/surface: denylist, pages, layouts, middleware, Server Actions,
   public files and out-of-prefix routes are all zero.
5. RED build manifest: structured build-surface verification fails before the
   final config/build exists.
6. GREEN build manifest: actual Next manifests satisfy every route and bundle
   invariant.

RED 1 has no unnamed bootstrap artifact. The historical install and creation
of the two tests are complete; the reconciled flow must preserve, not rewrite,
`apps/mobile-bff/src/source-surface.test.ts` and
`apps/mobile-bff/src/route-mirror.test.ts`; both use Node built-ins. Execute
them through the already frozen admin Vitest binary. The previously published
relative command is `SUPERSEDED`: because the effective Vitest root/discovery
remained `apps/admin`, it discovered zero test files and executed zero tests
under the sibling `apps/mobile-bff`. That outcome did not invalidate either
test or the source manifest.

After remote confirmation of `RED_DISCOVERY_AUTHORITY_SHA`, set
`WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1` and first run the
read-only Phase B preflight. Require exact implementation identity, only the
two untracked tests with their frozen hashes, empty staging, tracked-clean
state, no upstream, lockfile SHA-256
`2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55`,
available Vitest 2.1.9, and CI-2 admin config SHA-256
`8bb6705e6315f5a28bdf6cc15cae3ff7526007913c8f7c01acd7279ad0b91266`
with no custom `root`/`include` that conflicts with the command. Reproduce the
source receipt read-only as 40 routes, zero invalid exports and the frozen
source hash; require wrapper count zero and zero package/config/GREEN artifact.
Modify nothing.

Run only this capability check and require documented support for `--root`,
`--dir` and `--config`:

```bash
corepack pnpm@10.33.2 --dir "$WORKTREE/apps/admin" exec vitest --help
```

Do not run discovery/list or anything else that could consume the RED attempt.
Only when the binary is absent may the resource gate precede one
`corepack pnpm@10.33.2 install --frozen-lockfile`; all tracked bytes and the
lockfile hash must remain unchanged. Install failure or any preflight
divergence is `STOP_DOCUMENTED` without RED, test edit or GREEN artifact.

After the complete preflight passes, execute only:

```bash
WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1
corepack pnpm@10.33.2 \
  --dir "$WORKTREE/apps/admin" \
  exec vitest run \
  --config "$WORKTREE/apps/admin/vitest.config.ts" \
  --root "$WORKTREE" \
  --dir "$WORKTREE/apps/mobile-bff/src" \
  "$WORKTREE/apps/mobile-bff/src/source-surface.test.ts" \
  "$WORKTREE/apps/mobile-bff/src/route-mirror.test.ts"
```

The one permitted execution is a valid semantic RED only if both files are
executed and every exact field below is true together:

```text
RED1_DISCOVERED_TEST_FILE_COUNT=2
RED1_EXECUTED_TEST_COUNT=>0
RED1_SOURCE_ROUTE_EXPORT_COUNT=40
RED1_SOURCE_INVALID_EXPORT_COUNT=0
RED1_SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
RED1_WRAPPER_ROUTE_EXPORT_COUNT=0
RED1_FAILURE_CLASSIFICATION=MIRROR_ABSENT_ONLY
RED1_NO_TEST_FILES_FOUND=NO
RED1_CONFIG_ERROR=NO
RED1_MODULE_ERROR=NO
RED1_SYNTAX_ERROR=NO
RED1_SOURCE_DRIFT=NO
RED1_SKIP_TODO_CANCEL=0
RED1_EXIT_CODE=1
```

Before that execution, do
not create any dedicated `package.json`, Vitest config or other GREEN artifact,
do not use `--passWithNoTests`, and do not change either test byte. Required
physical test hashes are:

```text
SOURCE_SURFACE_TEST_SHA256=50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6
ROUTE_MIRROR_TEST_SHA256=289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f
```

Only after every semantic criterion passes do Tasks 4–14 continue literally.
The existing branch/worktree are reused; worktree creation, branch creation,
upstream mutation and a second RED execution are not authorized.

Capture an ordered `key=value\n` transcript normalized without ANSI. Never use
the raw transcript as a receipt. Its complete required schema includes:

```text
RED1_EXACT_COMMAND_FINGERPRINT_SHA256=<SHA_REAL>
RED1_VITEST_VERSION=2.1.9
RED1_ROOT=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1
RED1_DIR=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1/apps/mobile-bff/src
RED1_CONFIG=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1/apps/admin/vitest.config.ts
RED1_DISCOVERED_TEST_FILE_COUNT=2
RED1_EXECUTED_TEST_COUNT=<COUNT_REAL_GT_0>
RED1_PASSED_TEST_COUNT=<COUNT_REAL>
RED1_FAILED_TEST_COUNT=<COUNT_REAL>
RED1_SKIPPED_TEST_COUNT=0
RED1_EXIT_CODE=1
RED1_SOURCE_ROUTE_EXPORT_COUNT=40
RED1_SOURCE_INVALID_EXPORT_COUNT=0
RED1_SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
RED1_WRAPPER_ROUTE_EXPORT_COUNT=0
RED1_FAILURE_CLASSIFICATION=MIRROR_ABSENT_ONLY
RED1_NO_TEST_FILES_FOUND=NO
RED1_CONFIG_ERROR=NO
RED1_MODULE_ERROR=NO
RED1_SYNTAX_ERROR=NO
RED1_SOURCE_DRIFT=NO
RED1_SKIP_TODO_CANCEL=0
RED1_RECONCILED_NORMALIZED_LOG_SHA256=<SHA_REAL>
```

Missing or divergent receipt data is `STOP_DOCUMENTED` without rerun. After a
valid RED, revalidate both physical test hashes before the first GREEN mutation.

Toolchain is Node `>=22` and exclusively `corepack pnpm@10.33.2`. Global pnpm,
`corepack use`, `corepack up`, `corepack install -g`, `corepack enable` and
`--dangerously-allow-all-builds` are prohibited. A frozen install, package
tests, typecheck, route/import/build verification, dedicated build using only
synthetic values, existing Mobile API security tests, and loopback smoke are
required. The historical unnamed 11-file result of 172/172 is context and is
not reconstructible as an exact command from published evidence; it must not be
claimed as the current inventory. Instead, the current gate uses a deterministic
CI-2 Git-object-derived superset: all
`apps/admin/src/lib/mobile-api/**/*.test.ts`, all
`apps/admin/src/app/api/mobile/v1/**/*.test.ts`, plus the RevenueCat route and
library tests and the two previously tested admin-action files. Sort unique
repository-relative paths and encode each as `<repo-relative-path>\n`.

```text
FOCUSED_SECURITY_TEST_FILE_COUNT=39
FOCUSED_SECURITY_TEST_PATH_STREAM_SHA256=586a6653c80b06d77293f0d32f6a2166fb93f935c5d53080cbd0971e60b7a3b8
```

The frozen 39 paths are:

```text
apps/admin/src/app/(admin)/content/actions.test.ts
apps/admin/src/app/(admin)/settings/coach-messages/actions.test.ts
apps/admin/src/app/api/mobile/v1/coach/persona/route.test.ts
apps/admin/src/app/api/mobile/v1/content/covers/[token]/route.test.ts
apps/admin/src/app/api/mobile/v1/content/route.test.ts
apps/admin/src/app/api/mobile/v1/legal/medication-reminder-disclaimer/accept/route.test.ts
apps/admin/src/app/api/mobile/v1/legal/medication-reminder-disclaimer/route.test.ts
apps/admin/src/app/api/mobile/v1/medications/[id]/history/route.test.ts
apps/admin/src/app/api/mobile/v1/medications/[id]/log/route.test.ts
apps/admin/src/app/api/mobile/v1/medications/[id]/route.test.ts
apps/admin/src/app/api/mobile/v1/medications/route.test.ts
apps/admin/src/app/api/mobile/v1/notification-preferences/route.test.ts
apps/admin/src/app/api/mobile/v1/supplements/[id]/history/route.test.ts
apps/admin/src/app/api/mobile/v1/supplements/[id]/log/route.test.ts
apps/admin/src/app/api/mobile/v1/supplements/[id]/route.test.ts
apps/admin/src/app/api/mobile/v1/supplements/route.test.ts
apps/admin/src/app/api/webhooks/revenuecat/route.test.ts
apps/admin/src/lib/billing/revenuecat-webhook.test.ts
apps/admin/src/lib/mobile-api/auth.test.ts
apps/admin/src/lib/mobile-api/coach-service.test.ts
apps/admin/src/lib/mobile-api/commands.test.ts
apps/admin/src/lib/mobile-api/content-cover-capability.test.ts
apps/admin/src/lib/mobile-api/content-service.test.ts
apps/admin/src/lib/mobile-api/contracts.test.ts
apps/admin/src/lib/mobile-api/entitlement-service.test.ts
apps/admin/src/lib/mobile-api/http.test.ts
apps/admin/src/lib/mobile-api/idempotency.test.ts
apps/admin/src/lib/mobile-api/media-service.test.ts
apps/admin/src/lib/mobile-api/read-model.test.ts
apps/admin/src/lib/mobile-api/registration-service.test.ts
apps/admin/src/lib/mobile-api/route.test.ts
apps/admin/src/lib/mobile-api/routine-adherence-service.test.ts
apps/admin/src/lib/mobile-api/routine-item-service.test.ts
apps/admin/src/lib/mobile-api/routine-service.test.ts
apps/admin/src/lib/mobile-api/supabase-coach.test.ts
apps/admin/src/lib/mobile-api/supabase-content.test.ts
apps/admin/src/lib/mobile-api/supabase-routine-adherence.test.ts
apps/admin/src/lib/mobile-api/supabase-routine-items.test.ts
apps/admin/src/lib/mobile-api/supabase-routine.test.ts
```

The exact derivation and execution command is frozen in the implementation
plan. It must reproduce count/hash before execution and then report the actual
current Vitest test count with zero failure/skip; it must not substitute the
historical number 172. The full historical 619-test admin suite is not rerun
unless a finding, review or attributable failure requires it.

## 8. Git identity, reviews and publication

Authority documentation baseline:

```text
branch: codex/better-ahead-rebranding-design
remote ref: refs/heads/codex/better-ahead-rebranding-design
HEAD: 6e03d5a67284204ab2781ff049ffe4df40b18961
parent: 89f8bc1c41073d110fe17ee3c638da3998c31aad
tree: f871f4bc2b19e84e641b202a2ecfa5ca8f3cd576
subject: docs(staging): record dedicated Mobile BFF stop
RED discovery authority subject: docs(staging): reconcile dedicated BFF RED discovery
```

Implementation identity:

```text
base: 277873755bf29771a10b5f362b522c2e6a6c21d6
branch: codex/ci3-dedicated-mobile-bff-surface-v1
worktree: /root/agentempp-ci3-dedicated-mobile-bff-surface-v1
subject: feat(staging): add dedicated Mobile API BFF surface
```

The implementation resumes only after the RED discovery authority commit is
remotely confirmed as `RED_DISCOVERY_AUTHORITY_SHA`. The existing branch and
worktree are reused at the exact CI-2 base without cherry-picking
documentation; creation is not reauthorized. The old detached deploy worktree
`/root/agentempp-ci3-staging-bff-v1` and the frozen Mac worktree remain
untouched.

The exact Mac evidence path is
`/Users/eduardohenrique/Developer/bodyflow-production-secret-contract-v1`.
It is evidence-only, has no authority on this VPS and may not be used as an
implementation source, repaired or modified.

Two independent read-only implementation reviews are mandatory:

- Review A: route/runtime security, exact exports, auth lifecycle,
  service-role server-only behavior, closure, manifests, 404 boundary,
  logs/PII and unchanged official calculations.
- Review B: package dependencies, lockfile, Next config, output tracing,
  monorepo root, Vercel artifact isolation, source SHA, protection sequencing,
  rollback and no production.

The gate is 0 Critical and 0 Important. Corrections stay inside the
implementation allowlist and trigger affected gates plus both reviews again.
The implementation uses selective staging, one commit and one non-force push;
there is no upstream setup, PR or merge.

## 9. Existing Vercel project and Preview boundary

Reuse exactly the existing project `agentempp-mobile-bff-staging`, whose ID is
recorded only by SHA-256
`26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f`.
Do not delete, recreate or create another project. Initial expectations are
root `apps/admin`, Next.js, Node 22.x, external sources enabled, no Git
Integration, no custom domain, zero Preview env, zero Production env, zero
deployment, and
`ssoProtection.deploymentType=all_except_custom_domains` with no other
protection mechanism or exception.

The staging input is the root-only pair
`/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env` and
`/root/.config/agentempp/secrets/ci3-staging-mobile-bff.receipt.json`, with
integral SHA-256 values
`6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d`
and
`44d0da30244f2340827698caa1aae85410b6a34d5c50a312a8b9e5e9bbe08978`.
The three value fingerprints are respectively
`97010b2e836ff65ea00286dd549c7b53588c767be3b89d3b958e5db79901c992`,
`75f6096cc1475fbc3268203fdf29eea2b839fd98e82ff5e7d6c4f18b6ce1a7c1`
and
`76f90c745c5018fce36b9ba6d8b08a2d9bae70c07d40eebf48586bd552c83472`.
Values are revalidated without printing. Primary/live project
`xuxehkhdvjivitduarvb`, key `manager_vps_20260825` in state
`ACTIVE_QUARANTINED_UNUSED`, and
`/root/.config/agentempp/secrets/agentempp-primary-backend.env` are prohibited
from this operation and remain untouched.

After the code is published, exactly one seven-field settings PATCH changes
the root to `apps/mobile-bff` and sets the exact install/build commands while
leaving SSO and team defaults unchanged. Exactly three staging variables are
then created in one batch, Preview-only: the two public Supabase variables are
encrypted and the service-role variable is sensitive, or encrypted only if
official schema proof shows sensitive unsupported. No raw value is printed;
the primary/live secret file is never opened or used.

A single Preview deployment must be READY, target Preview, and prove its source
SHA equals the implementation commit. The raw origin remains in memory and is
never written to Git, docs, chat or reports. While SSO is still active,
metadata, sanitized build logs and available deployment outputs must prove the
dedicated root, exact source, no admin surface, zero pages, zero middleware,
zero Server Actions, no custom domains, no Production env and no Git
Integration. Review C must return 0 Critical and 0 Important.

Only then may one project-only PATCH set `ssoProtection` to null. The team
default is immutable. From initiation of that forward PATCH, an outcome that
does not prove definite failure-without-mutation is possible success. After
success or possible success, failure or ambiguity of the forward response, its
complete readback, or **any** later requirement—HTTPS/certificate/exact-origin,
redirect,
Mobile status/JSON/envelope/header/request-ID, Vercel-page/HTML/stack/secret/PII,
any forbidden-route assertion, any one of the 19 prior-finding HTTP probes, or
either manifest-only Server Action/page assertion—triggers exactly one rollback
PATCH that restores:

```json
{"ssoProtection":{"deploymentType":"all_except_custom_domains"}}
```

There is no retry of forward or rollback. Do not start or repeat public probes
while state is ambiguous or after rollback. Protection must be read back as
active, env/deployment are preserved, and the operation continues only to STOP
documentation. Rollback failure or ambiguous rollback/readback is an immediate
material-risk STOP; a post-forward STOP may never claim protection without
proof.

## 10. Public acceptance and outcome classification

After SSO removal, the three Mobile API probes must return their own sanitized
401 contract, and `/`, `/login`, `/dashboard`, `/crescimento`, admin, Inngest,
Stripe and administrative media routes must return 404 without redirect. Every
materially reachable HTTP path among the 21 prior findings is probed read-only;
pages and Server Actions are additionally disproved by manifests.

After public probes pass, write the root-only deployment receipt outside Git
with mode `0600`. It may hold the raw origin solely for Mac handoff and must
contain no secret value, token or PII. Then search read-only for an explicitly
synthetic, active, confirmed, patient-role staging identity and an approved
runtime credential mechanism. Do not create a user, change a password, confirm
an email or create a profile.

### 10.1 Pre-authority report-only STOP

If the one RED discovery documentation commit attempt fails, or its one push
attempt fails, there is no published `RED_DISCOVERY_AUTHORITY_SHA` that can
serve as the required parent. Stop before RED execution, implementation edit or
any external service access/write. Do not spend the final-documentation budget
and do not create a Git STOP document. Record a report-only
`STOP_PRE_AUTHORITY` in the task report and recovery ledger outside the
five-path candidate, preserving target, exact failed gate, evidence, result,
actual staged/unstaged paths and rollback/restore information. If the local
commit fails after the five exact authority paths have been staged, leave those
five paths staged. If it fails earlier, preserve the exact observed
index/worktree state. A failed push preserves the one local authority commit
and exact observed index/worktree state. Do not reset, restore, unstage, amend,
retry, execute RED or touch the implementation worktree or services.

### 10.2 Common final-documentation preflight and gates

Final documentation exists only after the RED discovery authority was
published.
Before editing it, re-enter the manager and require branch
`codex/better-ahead-rebranding-design`, HEAD equal to the published
`RED_DISCOVERY_AUTHORITY_SHA`, remote ref
`refs/heads/codex/better-ahead-rebranding-design` equal to the same SHA, empty
staging, and the canonical 25 historical entries/hash unchanged. The common
gates are exact outcome allowlist, integral diff, `git diff --check`, zero
credential/PAT/raw-origin/PII, zero production or CI-4 authorization, two
independent reviews with 0 Critical/0 Important, selective per-path staging,
none of the 25 historical entries staged, parent exactly
`RED_DISCOVERY_AUTHORITY_SHA`, one commit, one non-force fast-forward push, no
tag/PR/merge, and remote-ref proof.

### 10.3 `PASS_COMPLETE` final-documentation contract

Eligibility requires all BFF/public gates, `SYNTHETIC_PATIENT_PATH=VERIFIED`,
and authenticated Today `PASS` or `DEFERRED_TO_MAC_BY_DESIGN`. Exact allowlist:

```text
docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-authority.md
docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
docs/superpowers/specs/2026-08-25-ci3-today-staging-vertical-slice.md
docs/superpowers/plans/2026-08-25-ci3-today-staging-vertical-slice.md
```

Dossier transition: `1.6.8` to `1.7`. Subject:
`docs(ios): authorize CI-3 after dedicated Mobile BFF verification`. Record
authority/implementation SHAs and trees, exact code paths, all three route
stream counts/hashes, closure/lockfile/tests/typecheck/build/smoke/reviews,
Vercel project/deployment fingerprints, exact source/root/Node, Preview env 3,
Production env 0, project SSO null, unchanged team default, Mobile 401 headers,
all forbidden/19-finding 404s, action/page manifest absence, patient/auth probe,
root-only receipt and zero production. Publish the complete Mac macro-prompt
for `IMPLEMENT_CI3_TODAY_STAGING` and the `PASS_COMPLETE` markers; CI-4 remains
unauthorized.

```text
DEDICATED_MOBILE_BFF_STATUS=VERIFIED
DEDICATED_MOBILE_BFF_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
DEDICATED_MOBILE_BFF_SHA=<exact implementation SHA>
STAGING_BFF_STATUS=VERIFIED
STAGING_BFF_PROJECT=agentempp-mobile-bff-staging
STAGING_BFF_TARGET=PREVIEW
STAGING_BFF_ROOT=apps/mobile-bff
STAGING_BFF_NODE_VERSION=22.x
STAGING_BFF_SOURCE_SHA=<exact implementation SHA>
STAGING_TODAY_UNAUTHENTICATED_PROBE=VERIFIED
STAGING_FORBIDDEN_SURFACE_PROBES=VERIFIED
SYNTHETIC_PATIENT_PATH=VERIFIED
CI3_STAGING_AUTHORITY_STATUS=VERIFIED
CI3_DOCUMENTATION_STATUS=PUBLISHED
CI3_DOCUMENTATION_REMOTE_SHA=<exact final docs SHA>
NEXT_ENVIRONMENT=MAC_LOCAL
NEXT_GATE=IMPLEMENT_CI3_TODAY_STAGING
```

### 10.4 `PASS_PARTIAL` final-documentation contract

Eligibility requires all BFF/public gates and
`SYNTHETIC_PATIENT_PATH=MISSING`. Exact allowlist:

```text
docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-preview-verification.md
docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
```

Dossier transition: `1.6.8` to `1.6.9`. Subject:
`docs(staging): record verified dedicated Mobile BFF preview`. Record the full
BFF/public evidence and preservation state, keep CI-3 unauthorized, publish the
`PASS_PARTIAL` markers and complete macro-prompt for
`AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`. No user is created.

```text
DEDICATED_MOBILE_BFF_STATUS=VERIFIED
DEDICATED_MOBILE_BFF_BRANCH=codex/ci3-dedicated-mobile-bff-surface-v1
DEDICATED_MOBILE_BFF_SHA=<exact implementation SHA>
STAGING_BFF_STATUS=VERIFIED
STAGING_BFF_PROJECT=agentempp-mobile-bff-staging
STAGING_BFF_TARGET=PREVIEW
STAGING_BFF_ROOT=apps/mobile-bff
STAGING_BFF_NODE_VERSION=22.x
STAGING_BFF_SOURCE_SHA=<exact implementation SHA>
STAGING_TODAY_UNAUTHENTICATED_PROBE=VERIFIED
STAGING_FORBIDDEN_SURFACE_PROBES=VERIFIED
SYNTHETIC_PATIENT_PATH=MISSING
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING
```

### 10.5 `STOP_DOCUMENTED` final-documentation contract

Any material divergence after the Phase A authority is published selects this
outcome. Exact allowlist:

```text
docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-stop.md
docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
```

Dossier transition: `1.6.8` to `1.6.9`. Subject:
`docs(staging): record dedicated Mobile BFF stop`. Record the last passed gate,
failed gate, code branch/SHA if created, settings/env/deployment, SSO
forward/rollback and probes, preserved resources, consumed attempts, zero
repetition, production untouched, CI-3 unauthorized, `STOP_DOCUMENTED` markers
and the exact next material gate. Preserve project, env and deployment.

```text
DEDICATED_MOBILE_BFF_STATUS=<NOT_VERIFIED|IMPLEMENTED_NOT_DEPLOYED|DEPLOYED_PROTECTED|PUBLIC_ROLLED_BACK>
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=<0_OR_1>
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=<0_OR_1>
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=<0_OR_1>
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=<0_OR_1>
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=<0_OR_1>
NEXT_ENVIRONMENT=VPS
NEXT_GATE=<exact material gate>
```

CI-4, production, production env/deployment, Supabase/database writes, new
users, PRs, merges, TestFlight and App Store remain prohibited in every
outcome.

## 11. Independent one-attempt budgets after RED discovery authority

The historical external budgets are not implicitly reusable. Draft and
publication of this reconciliation have their own one-attempt budgets:

```text
RED_DISCOVERY_DOCUMENTATION_COMMIT_ATTEMPTS=1
RED_DISCOVERY_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Only after the remote ref confirms `RED_DISCOVERY_AUTHORITY_SHA`, these new,
separate budgets become valid:

```text
RED1_RECONCILED_EXECUTION_ATTEMPTS=1
IMPLEMENTATION_COMMIT_ATTEMPTS=1
IMPLEMENTATION_PUSH_ATTEMPTS=1
VERCEL_DEDICATED_PROJECT_SETTINGS_PATCH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1
VERCEL_LOCAL_LINK_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

There is no new worktree-creation budget. Partial external state is a STOP,
not authorization to retry, delete or recreate resources.

## 12. VPS resource and mutation-record controls

Run `/root/.codex/ops/bin/vps-resource-gate.sh` immediately before every
materially heavy phase: the initial frozen install used to bootstrap RED 1,
dependency/lockfile installation, focused/full test phase, Next build, local
server smoke, and Vercel deployment/build trigger. Run it again after any
resource-related failure or concrete degradation evidence. `BUSY` means heavy
work runs sequentially; `PRESSURED` is evaluated from the concrete combined
metrics and does not automatically block; `CRITICAL` blocks heavy work until
its objective cause is resolved. Lightweight Git/status/diff and read-only
documentation checks do not require this gate.

Every mutation must be appended immediately to the task recovery ledger with
exact target, precondition/evidence, result, and rollback or restore location.
This includes repository edits, generated lockfile/importer, worktree/branch,
index/staging, commits, pushes, Vercel settings/env/link/deployment/SSO writes,
the external deployment receipt and final docs. Ledger entries contain only
names, counts and fingerprints—never secret values, Authorization, raw origin
or PII. A mutation without a successful ledger entry blocks the next mutation.

## 13. Preservation invariants

- The manager retains its canonical 25 historical `-uall` entries, five
  tracked modifications, 20 untracked entries, empty staging and historical
  tracked diff.
- The existing detached CI-2 deploy worktree remains at the exact CI-2 SHA,
  tracked-clean, staging-empty and without `.vercel`.
- The Mac evidence path
  `/Users/eduardohenrique/Developer/bodyflow-production-secret-contract-v1`
  remains evidence only and is never imported or modified.
- The implementation worktree ends at the published implementation commit,
  tracked-clean, staging-empty and with no upstream; its local `.vercel` may
  exist only there, remains untracked/unstaged and contains no Git-tracked
  secret. No dedicated deployment worktree is created or expected.
- The quarantined primary/live key remains active, isolated, unused and
  prohibited from this flow.
- Supabase and database writes are zero.
- The existing Vercel project is preserved; at most one Preview deployment,
  zero Production deployments, zero custom domains and zero Git Integration.
- CI-3 is authorized only by `PASS_COMPLETE`; CI-4 is never started here.

## 14. Final report contract

The final operational report must populate every field group below with exact
values, counts or explicit `NO`/`N/A`; it must not omit a group or report a raw
origin:

```text
OPERATION, FINAL_STATUS
DOCUMENTATION_BASELINE: initial SHA, parent, tree, subject, remote, dossier version
RED_DISCOVERY_AUTHORITY: paths, reviews, commit, parent, tree, subject, push, remote
IMPLEMENTATION_BASELINE: worktree, branch, HEAD, staging, status, test hashes,
  lockfile hash, Vitest version
RED1_RECONCILED: exact command, command fingerprint, Vitest version, root, dir,
  config, discovered files, executed/passed/failed/skipped tests, exit,
  source count/invalid/hash, wrapper count, failure classifications,
  RED1_RECONCILED_NORMALIZED_LOG_SHA256
IMPLEMENTATION: base, branch, worktree, commit, parent, tree, subject, path count,
  wrapper count, source/wrapper/build-route stream hashes, import closure,
  lockfile, tests, typecheck, build, local smoke, reviews, push, remote
VERCEL_PROJECT: name, ID fingerprint, settings attempts, root, Node, framework,
  build/install commands, outside-root, Git Integration, custom domains, team default
VERCEL_ENV: batch attempts, names, types, targets, Preview count, Production count,
  values printed NO, primary secret used NO
DEPLOYMENT: link attempts, deployment attempts, ID fingerprint, source SHA, target,
  ready state, root, Node, origin fingerprint, raw origin reported NO,
  protected inspection
SSO: initial, forward attempts, final, rollback attempts, team default changed NO
PUBLIC_PROBES: Mobile 401 count, forbidden 404 count, prior-finding 19/19,
  action manifest 2/2 absent, no-store, Vary, request ID, redirect, HTML,
  stack, secret, PII
SYNTHETIC_PATIENT: status, mechanism, created NO, PII reported NO
AUTHENTICATED_TODAY: PASS, DEFERRED_TO_MAC_BY_DESIGN, NOT_EXECUTED or FAILED
DEPLOYMENT_RECEIPT: path, mode, hash, raw origin only there YES, secret values NONE
FINAL_DOCUMENTATION: outcome, dossier version, commit, parent, tree, subject, push, remote
PRESERVATION: 25 historical items, existing old deploy worktree staging/.vercel,
  implementation worktree and its local .vercel, no dedicated deployment
  worktree, primary/live, Vercel, production, CI-4
EXTERNAL_ACTIONS: docs commits 1-2, code commit 0/1, code push 0/1,
  settings PATCH 0/1, Preview env batch 0/1, Preview deployment 0/1,
  SSO forward 0/1, SSO rollback 0/1, production deployment NO,
  Supabase write NO, database write NO, PR NO, merge NO, CI-4 NO
```

## 15. Vercel local-link control reconciliation — dossier 1.6.10

The single seven-field Task 9 PATCH is historical and consumed. Six persistent
settings are approved; `skipGitConnectDuringLink` is absent/null. Current
authenticated OpenAPI classifies that optional boolean as deprecated and does
not require it in PATCH response or Project GET. Installed CLI 50.35.0 does not
consume it for an existing project. Classification is:

```text
LINK_CONTROL_CLASSIFICATION=FIELD_REMOVED_OR_IGNORED_WITH_MATERIAL_GIT_LINK_ABSENT
SETTINGS_PATCH_RETRY_AUTHORIZED=NO
```

Project `link`, not the deprecated field, is the material Git-integration
state. Replace every Task 9+ gate requiring the deprecated field's readback
with:

```text
PROJECT_GIT_LINK_BEFORE_LOCAL_LINK=ABSENT
LOCAL_LINK_COMMAND=VERCEL_LINK_PROJECT_EXPLICIT
LOCAL_LINK_REPO_FLAG=ABSENT
VERCEL_GIT_CONNECT_EXECUTED=NO
PROJECT_GIT_LINK_AFTER_LOCAL_LINK=ABSENT
LOCAL_PROJECT_JSON_MATCH=YES
```

Only after remote publication of `LINK_SCHEMA_AUTHORITY_SHA` may one detached
deploy worktree be created at
`/root/agentempp-ci3-dedicated-mobile-bff-deploy-v1`, exact implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`. The implementation worktree and
old CI-2 worktree remain untouched. Run exactly one local link there with
`vercel link --yes --project agentempp-mobile-bff-staging --scope
gestao-9664s-projects`; `--repo` and every `vercel git connect/disconnect` are
prohibited. `.vercel/project.json` must be regular, local-only, ignored,
project/scope matching and contain no token, secret or env. Project GET must
still expose no `link` afterward.

After this postcondition, one Preview-only env batch and one protected Preview
deployment may proceed. Deploy with metadata
`githubCommitSha=e3e1e252b48e42554e75899b950692c05186f60d`; combine that
declarative metadata with detached clean SHA/tree and existing build receipts.
Do not treat it as a cryptographic binding by itself. All original protected
inspection, Review C, SSO forward/rollback and public-probe gates remain
mandatory.

Fresh budgets activated only by the remote authority:

```text
DEDICATED_DEPLOY_WORKTREE_CREATION_ATTEMPTS=1
VERCEL_LOCAL_LINK_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

The final documentation parent is `LINK_SCHEMA_AUTHORITY_SHA`.
`PASS_COMPLETE` transitions dossier `1.6.10→1.7` and uses the 2026-08-26
authority/Today paths. `PASS_PARTIAL` and post-authority `STOP_DOCUMENTED`
transition `1.6.10→1.6.11` and use the 2026-08-26 outcome paths defined by the
operation. Production, CI-4, Git Integration, custom domain and Production env
or deployment remain prohibited.

## 16. Vercel Preview env client reconciliation — dossier 1.6.12

The dossier 1.6.11 client STOP is now diagnosed as far as preserved evidence
allows. The removed executor remains bound only by SHA-256
`e41caa1bb0befe87471f224a7a04b55e3a11822ec4b6f31c7d73fa3ec645867e`;
its client failure remains bound only by SHA-256
`e71d492d1abf97ecf9d984116c77e83470ef08214c21805a6f6085a6528e01cf`.
Exact source, argv and semantic error preimage are unrecovered.

Installed Vercel CLI 50.35.0 proves `--input -` is supported, while the current
authenticated OpenAPI accepts the intended exact three-object Preview batch
and returns HTTP 201. Minimal HOME/auth/scope probes pass. Those facts disprove
the suspected stdin/path and current auth-context classifications but do not
identify the historical failure. `ROOT_CAUSE_PRIMARY=UNRESOLVED` is therefore
mandatory.

The CLI also performs internal default retries and unbounded request/response
parsing without an `api` retry-disable flag. A temp-body wrapper cannot prove
one HTTP request or an end-to-end byte bound. `CLI_API_ROOT_ONLY_TEMP_INPUT` is
not authorized under this contract.

```text
ENV_BATCH_RETRY_AUTHORIZED=NO
VERCEL_PREVIEW_ENV_BATCH_RETRY_ATTEMPTS=0/0_NOT_ACTIVATED
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE
```

This section supersedes only any 1.6.10/1.6.11 continuation that would create
Preview env or deploy after the historical failure. Settings PATCH and local
link remain completed/closed. Project env stays 0/0/0, deployments 0, material
Git link absent and SSO active. Production, Supabase/database writes, CI-3,
CI-4, PR and merge remain prohibited.

## 17. Bounded Vercel one-shot transport — dossier 1.6.13

The historical client failure is `UNRECOVERABLE_NON_DECISIVE`: its removed
preimage cannot justify a guessed cause, while repeated read-only evidence
continues to prove remote env `0/0/0` and deployments `0`. Vercel CLI mutation
is superseded for env and SSO because its retry and response behavior cannot
satisfy the bounded one-request contract.

The approved V1 transport is root-only and outside Git. Its frozen identities
are:

```text
TRANSPORT_SOURCE_SHA256=b21520e29d260a01cecff1bad17d5f05fb50bffd976aa664afec53bed36d06df
TRANSPORT_TEST_SHA256=fb5a222849adb3e6902dcc5015acf3608cf194ec5dd0103200f84abb621b6198
TRANSPORT_SOURCE_TEST_MODE=0400
SELF_TESTS=30/30_PASS
PREFLIGHT_RECEIPT_SHA256=25bb55fe10141d275a7fea582d3aedbb47712e711a4137b74513e65c80c0c539
```

It fixes `https://api.vercel.com`, TLS/SNI, closed endpoint IDs, one mutable
request, zero retry/follow, connection close, 15-second timeouts and bounded
headers/request/response. Claims are single-use. Attempt receipts use the
closed sanitized schema and are durably published before readback. Any crash,
partial response, invalid POST metadata or readback mismatch preserves the
claim/receipt and forbids retry.

The exact env body remains the ordered three-key Preview batch:
`NEXT_PUBLIC_SUPABASE_URL` encrypted, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
encrypted, and `SUPABASE_SERVICE_ROLE_KEY` sensitive. Exact POST-created
metadata and exact GET inventory are separate success gates.

The real preflight proved the expected root, Node, framework, build/install,
outside-root, absent Project link, active SSO, zero deployments and env 0/0/0.
It opened neither staging nor primary/live. Independent HTTP and secret reviews
both have zero Critical/Important.

Source-receipt timing is explicitly narrowed: this authority publishes the
source/test hashes first. `SOURCE_RECEIPT_STATUS=PENDING_POST_PUSH_BINDING` is
the only truthful pre-push state. After remote confirmation, exactly one atomic
root-owned `0600` receipt at
`/root/.config/agentempp/control-plane/ci3-vercel-one-shot-v1.source.receipt.json`
may bind the authority SHA to those hashes. Its exact no-extra-field schema is
`authority_sha`, `source_sha256`, `test_sha256`, and
`rollback_authorized=true`. Same-directory `O_EXCL|O_NOFOLLOW` temp write,
file fsync, atomic no-overwrite hard-link publication, parent fsync, temporary
link removal, second parent fsync and final root/0600/regular/link-count-one
readback are mandatory. Mutable modes remain blocked until receipt,
local/remote SHA, frozen modes and hashes all validate.

The current operation authority activates only the Phase D publication
budgets:

```text
ONE_SHOT_TRANSPORT_DOCUMENTATION_COMMIT_ATTEMPTS=1
ONE_SHOT_TRANSPORT_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Only confirmed remote publication activates these operational budgets:

```text
VERCEL_PREVIEW_ENV_ONE_SHOT_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_FORWARD_ONE_SHOT_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ONE_SHOT_ATTEMPTS=1
```

The rollback predicate is deliberately protective: exact forward attempt
provenance plus a failed public-probe receipt created only after the forward
command's successful readback may authorize one restoration of
`all_except_custom_domains`. It never authorizes a reprobe.

Project creation, settings PATCH, local link, CLI env, implementation commit,
Production, custom domain, Git Integration, Supabase/database write, CI-3 and
CI-4 remain closed. CI-3 is authorized only by a later `PASS_COMPLETE`.
Failure of this authority commit or push is `STOP_PRE_AUTHORITY`, with no
source receipt creation, staging-value read or POST.

# CI-3 Preview protection policy STOP — shared admin surface is not public-ingress safe

**Date:** 2026-08-25

**Operation:**
`RECONCILE_STAGING_BFF_PREVIEW_PROTECTION_POLICY_AND_CONTINUE`

**Classification:** `STOP_DOCUMENTED`

## Authority and immutable inputs

- Documentation authority:
  `ff8a4ec2f98764b0ff6b34f617288c652ece2f66`.
- CI-2 source:
  `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Deploy worktree:
  `/root/agentempp-ci3-staging-bff-v1`, detached and tracked-clean.
- Target project: `agentempp-mobile-bff-staging`.
- Project-ID SHA-256:
  `26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f`.
- Intended target: Preview only.

The manager reproduced its canonical 25-entry `-uall` baseline, empty staging,
porcelain SHA-256
`455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`
and tracked-diff SHA-256
`7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`.
The remote documentation ref matched the authority exactly.

## Read-only Vercel and staging-source preflight

The current project GET confirmed:

- Next.js, root `apps/admin`, Node 22.x;
- exact frozen Corepack/pnpm install and build commands;
- external workspace sources enabled;
- Git Integration absent;
- effective `ssoProtection.deploymentType=all_except_custom_domains`;
- password protection, Trusted IPs, Protection Bypass, Deployment Protection
  Exceptions and OPTIONS allowlist absent;
- zero Preview env and zero Production env;
- zero deployments;
- one Vercel-managed `.vercel.app` domain and zero custom domains.

No project setting was changed. The prior authority identifies the effective
SSO setting as inherited. This operation did not modify the team default or
create a project override.

The root-only staging source and receipt remained regular `root:root` files,
mode `0600`, link count one, under a `0700` parent. Their integral hashes and
the three value fingerprints matched the frozen authority. Exactly these names
were present:

- `NEXT_PUBLIC_SUPABASE_URL`;
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`;
- `SUPABASE_SERVICE_ROLE_KEY`.

The receipt contained no raw value. The primary/live secret source was not
opened or used.

## Complete `apps/admin` ingress inventory

The read-only source audit classified 132 entry-point units with zero
unclassified surfaces:

| Unit | Count | Classification summary |
| --- | ---: | --- |
| `page.tsx` | 27 | 2 public non-sensitive, 7 admin-session protected, 18 blocking |
| `route.ts` | 48 | 40 Mobile bearer, 3 admin session, 2 signed webhooks, 2 auth callbacks, 1 blocking |
| exported Server Actions | 54 | 52 with their own admin authorization path, 2 blocking |
| layouts | 2 | 1 static root shell, 1 admin-session layout |
| middleware | 1 | session routing plus explicit self-authenticated API exemptions |
| source `public/` static files | 0 | N/A |

The 40 `/api/mobile/v1/**` route files resolve through the common mobile-route
lifecycle, directly or through bounded handler factories. That lifecycle
creates a server-only service client, validates a Supabase bearer, requires a
confirmed patient identity, rejects non-active identities, authorizes the
entitlement, attaches request ID, emits `no-store` and `Vary: Authorization`,
and sanitizes unexpected errors. Mutation handlers use the shared idempotency
path. The historical unchanged-source client-bundle gate remains 141 files
with zero raw service-role occurrence.

The RevenueCat webhook performs a bounded raw-body read and verifies its HMAC
signature and timestamp freshness before creating a privileged client.
Duplicate provider event IDs are handled later by the idempotent RPC, not by a
pre-client replay rejection. The Inngest route delegates signing-key
verification to the Inngest handler. `/api/media/[id]` and both Stripe routes
authenticate and authorize an admin before privileged work. Login, auth
callback, signout and the root redirect expose no patient data by themselves.

## Blocking application-layer findings

The project cannot safely become public as one shared `apps/admin` deployment.
There are 21 `BLOCKING_UNPROTECTED_SENSITIVE_SURFACE` units in three root-cause
families.

### 1. Public route reuses `service_role` as bearer

`apps/admin/src/lib/public-api-path.ts:4` exempts
`/api/admin/send-message` from cookie-session middleware. The route then reads
`SUPABASE_SERVICE_ROLE_KEY` and compares the public Authorization header with
that same credential at
`apps/admin/src/app/api/admin/send-message/route.ts:18-26`. After this check it
uses the service client to read patient communication data and send/persist a
message (`route.ts:36-98`). This directly violates the ingress contract that no
public endpoint may accept `service_role` as bearer.

### 2. Two Server Actions lack their own auth/admin authorization

`upsertFood` and `deleteFood` are exported from a `'use server'` module and
open the service client immediately at
`apps/admin/src/app/(admin)/settings/foods/actions.ts:34-36` and
`:71-72`. Neither action revalidates the current user or an admin role before
reading or mutating `food_db`. A layout or hidden button is not an
authorization boundary for an exported Server Action.

### 3. Eighteen page routes query with `service_role` before page-local admin authorization

The following page components open a privileged service client without first
proving an admin role in the page or in a data-access function called before
the query:

- `apps/admin/src/app/(admin)/audit/page.tsx:20`;
- `apps/admin/src/app/(admin)/dashboard/page.tsx:81`;
- `apps/admin/src/app/(admin)/evaluations/page.tsx:12`;
- `apps/admin/src/app/(admin)/formulas/page.tsx:127`;
- `apps/admin/src/app/(admin)/messages/page.tsx:59`;
- `apps/admin/src/app/(admin)/prompts/[id]/page.tsx:18`;
- `apps/admin/src/app/(admin)/prompts/page.tsx:29`;
- `apps/admin/src/app/(admin)/settings/admins/page.tsx:14`;
- `apps/admin/src/app/(admin)/settings/agents/page.tsx:46`;
- `apps/admin/src/app/(admin)/settings/api-keys/page.tsx:110`;
- `apps/admin/src/app/(admin)/settings/calc/page.tsx:14`;
- `apps/admin/src/app/(admin)/settings/crons/page.tsx:10`;
- `apps/admin/src/app/(admin)/settings/foods/page.tsx:16`;
- `apps/admin/src/app/(admin)/settings/global/page.tsx:8`;
- `apps/admin/src/app/(admin)/settings/tools/page.tsx:17`;
- `apps/admin/src/app/(admin)/users/[id]/page.tsx:19`;
- `apps/admin/src/app/(admin)/users/page.tsx:15`.

The eighteenth route is `/crescimento`: its page selects one of three
transitive views at `apps/admin/src/app/(admin)/crescimento/page.tsx:59-63`,
and every view opens a privileged client without a local admin check:
`views/receita-view.tsx:36`, `views/conquistas-view.tsx:28` and
`views/funil-view.tsx:31`.

The middleware proves only that a Supabase user exists. The parent admin layout
does an admin-role lookup, but that shared layout is not a safe data-access
authorization boundary for nested routes. Current Next.js guidance requires
authorization close to the data source and warns against relying on a layout
for nested pages or Server Actions.

## Focused tests and review gate

Only existing security-focused tests were executed, through Corepack/pnpm
10.33.2. Eleven test files produced 172/172 passing tests, covering Mobile API
auth, headers, route wrapper, idempotency, content capability, RevenueCat
signature handling and the two hardened admin-action families that already
have tests. No full suite, dependency install, typecheck or build was rerun.

There is no existing focused authorization test for the public send-message
route or the two food actions. This missing coverage does not authorize code
creation in this operation.

Independent review results are recorded below after completion of the two
required read-only reviews:

- Review A — application security: `NO-GO`, 0 Critical, 3 Important,
  1 Minor.
- Review B — ingress architecture: `NO-GO`, 0 Critical, 3 Important,
  1 Minor.

Both reviews independently confirmed the three blocking root causes. Their
Minor finding is that `isSelfAuthenticatedApiPath()` uses unbounded prefix
matching for `/api/admin/send-message` and `/api/inngest`, so a future sibling
path could inherit the public exemption unintentionally.

The blocking findings prevent the required 0 Critical / 0 Important gate and
therefore prevent the Vercel protection PATCH.

## STOP and frozen budgets

The STOP occurred before every authorized external write in this operation:

```text
INGRESS_ARCHITECTURE=REQUIRES_DEDICATED_BFF_ONLY_ARTIFACT
VERCEL_PROJECT_PROTECTION_PATCH_ATTEMPTS=0/1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0/1
VERCEL_LOCAL_LINK_ATTEMPTS=0/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
PROJECT_SSO_PROTECTION=all_except_custom_domains
PROJECT_OVERRIDE_CREATED=NO
TEAM_DEFAULT_CHANGED=NO
PREVIEW_ENV_COUNT=0
PRODUCTION_ENV_COUNT=0
DEPLOYMENT_COUNT=0
TODAY_UNAUTHENTICATED_PROBE=NOT_EXECUTED
SYNTHETIC_PATIENT_PATH=NOT_EVALUATED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=AUTHORIZE_DEDICATED_PUBLIC_MOBILE_BFF_SURFACE
```

No protection, env variable, link, deployment, bypass, share token, domain,
alias, Git integration or production setting was created or changed. No
Supabase key, user or database was changed. The project and its inherited
protection remain intact.

## Required next architecture

The safe next gate is a separately authorized deployment artifact that exposes
only the Mobile API surface. It must not share public ingress with the admin
pages, admin Server Actions, Stripe administration, media administration or
the service-role bearer endpoint. That future gate must define its source
allowlist, build/root strategy, route inventory, independent secrets boundary,
one-attempt budgets, tests and rollback before any code or external mutation.

This record does not authorize that implementation, another protection PATCH,
environment creation, deployment, production, CI-3, CI-4, TestFlight or App
Store work.

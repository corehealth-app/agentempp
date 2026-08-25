# CI-3 staging BFF reconciliation STOP — inherited Preview protection

**Date:** 2026-08-25

**Operation:**
`RECONCILE_VERCEL_CREATE_SCHEMA_PROVISION_PREVIEW_AND_AUTHOR_CI3`

**Classification:** `STOP_DOCUMENTED`

## Authority and frozen inputs

- Documentation authority before this record:
  `eed2a4dd8155c2043b732ca3196b69a5cd80f8e2`.
- CI-2 source:
  `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Vercel CLI: 50.35.0, already installed and authenticated.
- Target project: `agentempp-mobile-bff-staging`.
- Target environment: Preview only.
- Intended framework/root/runtime: Next.js, `apps/admin`, Node 22.x.
- Package manager: Corepack invoking exactly pnpm 10.33.2.

The Git manager passed its canonical 25-entry `-uall` baseline, empty staging
and historical tracked-diff gate before external mutation. The detached CI-2
worktree was clean at the exact source SHA. The staging source and receipt were
regular root-only files with their expected SHA-256 fingerprints and exactly
the three authorized variable names. Raw secret values were not reported, and
the primary/live secret was not loaded for this operation.

The previously frozen backend evidence remained applicable because neither
source nor lockfile changed and no deployment revealed a source build issue:
48/48 focused Mobile API tests, 10/10 daily-state tests, 619/619 admin tests,
typecheck, Next.js build, client-bundle scan and two pre-Vercel reviews had
passed. These gates were not rerun.

## Schema reconciliation and preflight

The authenticated OpenAPI schema used by Vercel CLI 50.35.0 confirmed:

- `POST /v11/projects` requires `name`, rejects additional properties and
  accepts the four authorized create keys;
- `nodeVersion` is not a create-project property;
- `PATCH /v9/projects/{idOrName}` accepts `nodeVersion: 22.x` and the other
  six authorized settings;
- `POST /v10/projects/{idOrName}/env` accepts a batch and the `sensitive` type.

The read-only remote preflight found zero project with the exact name, zero
matching deployment and no local `.vercel` link. Static manifest inspection
confirmed that `@mpp/admin` depends on workspace packages outside
`apps/admin`, requiring `sourceFilesOutsideRootDirectory=true`.

## Authorized Vercel writes

### Corrected project creation

The historical project-creation attempt remained consumed at 1/1. A new,
separately authorized reconciliation attempt was executed exactly once with
only:

- `name`;
- `framework`;
- `rootDirectory`;
- `skipGitConnectDuringLink`.

Result: the project was created with Next.js, root `apps/admin` and no Git
link. Canonical project-ID SHA-256, calculated over the raw ID bytes without a
line ending:
`26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f`.

### Project settings update

Exactly one PATCH was executed with the seven-key allowlist:

- `nodeVersion`;
- `framework`;
- `rootDirectory`;
- `buildCommand`;
- `installCommand`;
- `skipGitConnectDuringLink`;
- `sourceFilesOutsideRootDirectory`.

The authoritative GET confirmed Node 22.x, Next.js, `apps/admin`, both exact
Corepack/pnpm commands, external workspace sources enabled, no Git link and
zero custom domains. The deprecated `skipGitConnectDuringLink` response field
was null/not echoed; its material postcondition, absence of a Git link, passed.
No retry or eighth field was used.

## Material blocker

The GET also exposed inherited Vercel Authentication in the exact field:

```text
ssoProtection.deploymentType=all_except_custom_domains
```

The required Preview origin has no custom domain. Therefore this policy would
intercept the unauthenticated `/api/mobile/v1/today` request before the Mobile
API could return its required 401 JSON envelope. Proceeding to secrets and a
deployment would knowingly consume remaining one-attempt budgets without a
valid public probe path.

Sanitized error classification:

```text
INHERITED_VERCEL_AUTHENTICATION_ALL_EXCEPT_CUSTOM_DOMAINS_BLOCKS_PUBLIC_PREVIEW_MOBILE_API_PROBE
```

The protection was not disabled or modified. No bypass, password, share token,
custom domain or alias was created.

## Frozen external state

```text
VERCEL_PROJECT_CREATED=YES
VERCEL_PROJECT_CREATION_HISTORICAL_ATTEMPTS=1/1
VERCEL_PROJECT_CREATION_RECONCILIATION_ATTEMPTS=1/1
VERCEL_PROJECT_CREATION_TOTAL_HISTORICAL_REQUESTS=2
VERCEL_PROJECT_SETTINGS_APPLIED=YES
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=1/1
VERCEL_PREVIEW_ENV_VARIABLES_CREATED=0
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0/1
VERCEL_PRODUCTION_ENV_VARIABLES_CREATED=0
VERCEL_LOCAL_LINK_ATTEMPTS=0/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
VERCEL_DEPLOYMENT_ID=N/A
VERCEL_ORIGIN=N/A
VERCEL_GIT_INTEGRATION=NO
VERCEL_CUSTOM_DOMAIN_COUNT=0
STAGING_BFF_SOURCE_INTENDED=277873755bf29771a10b5f362b522c2e6a6c21d6
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
PRODUCTION_TOUCHED=NO
```

No Supabase project, key, user or database was mutated. The quarantined
primary/live key remains active, isolated and unused; it was not copied to
staging or Vercel. No code edit, dependency install, test, build, local link,
deployment, origin probe, PR, merge, production deploy, CI-3 or CI-4 was
executed.

## Preservation and next gate

The created Vercel project and its applied settings must be preserved. This
operation does not authorize deleting or recreating the project, changing
Vercel Authentication, disabling protection, creating a bypass/share token,
adding env vars or attempting deployment.

Every `0/1` count in this record is closed historical state from this operation,
not reusable authorization.

```text
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_STAGING_BFF_PREVIEW_PROTECTION_POLICY
```

The next authority must decide a safe Preview ingress architecture that lets
the Mobile API return its own 401 contract without unintentionally exposing
the remaining `apps/admin` surface. It must issue fresh, explicit budgets for
any still-required external mutation. This evidence does not execute or
authorize that next gate.

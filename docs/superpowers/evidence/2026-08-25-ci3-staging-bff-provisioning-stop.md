# CI-3 staging BFF provisioning STOP

**Date:** 2026-08-25

**Classification:** material, fail-closed provisioning STOP

## Authorized target

- Project name: `agentempp-mobile-bff-staging`.
- Target: Preview only.
- Intended source SHA:
  `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Intended root directory: `apps/admin`.
- Intended framework: Next.js.
- Intended runtime: Node 22 compatible.
- Intended package manager: Corepack pnpm 10.33.2.

## Preflight

Vercel CLI 50.35.0 was already installed and authenticated. Identity and scope
were recorded only as SHA-256 fingerprints. The read-only inventory found 20
visible projects, zero exact-name project and zero deployment corresponding to
the requested name. Required CLI help surfaces were inspected. No Git
integration, custom domain, alias, webhook or local `.vercel` link existed.

The CI-2 source was detached and clean. Frozen install, focused and full tests,
typecheck and build were green. The staging source and receipt were root-only,
matched their expected hashes and contained exactly:

- `NEXT_PUBLIC_SUPABASE_URL`;
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`;
- `SUPABASE_SERVICE_ROLE_KEY`.

The primary/live secret source was not opened by the executor or used for this
attempt. Two independent security reviews were GO, each with 0 Critical,
0 Important and 0 Minor.

## Single attempt and failure

Exactly one project-creation request was made. It returned HTTP 400 before a
project was created because Vercel API v11 rejected `nodeVersion` as an
additional request property. The sanitized error classification is:

```text
INVALID_CREATE_PROJECT_REQUEST_ADDITIONAL_PROPERTY_NODE_VERSION
```

The request contained no environment values. No retry, fallback request,
project reuse or field weakening was attempted. A read-only inventory after
the failure again found zero exact-name project.

## Frozen result

```text
VERCEL_PROJECT_CREATED=NO
VERCEL_PROJECT_CREATION_ATTEMPTS=1/1
VERCEL_PREVIEW_ENV_VARIABLES_CREATED=0
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
VERCEL_DEPLOYMENT_ID=N/A
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
PRODUCTION_TOUCHED=NO
SECOND_ATTEMPT_AUTHORIZED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_STAGING_BFF_PROVISIONING_STOP
```

No project, environment variable, deployment, custom domain, alias, Production
Branch, Git integration, analytics capability or production resource was
created or changed. Supabase primary/live, Supabase staging, databases, users,
keys and runtimes were not mutated.

## Required reconciliation

A new authority must define an API-compatible create-project request that
preserves the required Node 22 behavior without sending the rejected property,
or a separately verified post-create configuration sequence. It must repeat
the exact-name absence gate and issue a new explicit single-attempt
authorization. This operation's exhausted attempt cannot be reused.

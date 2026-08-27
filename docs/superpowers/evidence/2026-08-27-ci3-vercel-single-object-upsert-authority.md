# CI-3 Vercel single-object Preview upsert authority

**Date:** 2026-08-27

**Operation:**
`RECONCILE_VERCEL_CLI_JSON_ARRAY_TRANSPORT_WITH_SINGLE_OBJECT_UPSERTS_AND_RESUME_CI3`

**Status:** documentary authority; no environment mutation has run under this
authority

## Baseline and supersession

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_BASE=73f5a0b2ad633d7302f636168a01e297c5c00d18
DOCUMENTATION_BASE_PARENT=af03a01be7103fa63254da4e95de8b19cc6d78d4
DOCUMENTATION_BASE_TREE=5375cb7a7d32e423cc9ba98c6e9f87ff7050e885
DOCUMENTATION_BASE_SUBJECT=docs(staging): record Vercel one-shot env or Mobile BFF stop
DOSSIER_BEFORE=1.6.14
DOSSIER_AFTER=1.6.15
MANAGER_BASELINE=25/5/20_PRESERVED
MANAGER_PORCELAIN_SHA256=455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0
MANAGER_TRACKED_DIFF_SHA256=7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb
INITIAL_STAGING=EMPTY
```

The historical batch-array `NEXT_GATE=RECONCILE_VERCEL_CLI_JSON_ARRAY_TRANSPORT`
is `SUPERSEDED`. It produced zero real POST, zero remote environment entry and
zero deployment. V1–V4 remain immutable and unexecuted by this operation. No
V5 is created.

## Read-only transport proof

Installed Vercel CLI 50.35.0 and Node v24.14.0 were inspected without editing
the installation. Relevant SHA-256 identities:

```text
CLI_PACKAGE_SHA256=80fd9f69d8f836660cf0cb4f8ddbbd1e73b69de899db6de6a7b9489958b8c933
CLI_COMMANDS_BULK_SHA256=96ea40cb30802a129bd565398412c4238d8d316c0d453ba9e17d3c56778f66ad
CLI_CLIENT_CHUNK_SHA256=aa2e8d1b59a0b854cdb10ec625db38f3d87b8be720d7dd3b2898d68685447d4f
CLI_NODE_FETCH_SHA256=5010821fbd9a88136517267b28c6346aa66994cded5fc66b17d7357304c05d68
OFFICIAL_OPENAPI_SHA256=843aa0c724aec9a36a761edfefe39ff36626800bdb75747f28afcd7353d6f6e0
```

Direct source proof:

1. `--input -` reads stdin and applies `JSON.parse`.
2. `executeSingleRequest` passes `config.body` unchanged to `Client.fetch`.
3. Arrays fail `isJSONObject` and do not follow the JSON-body path.
4. Plain objects pass `isJSONObject`, are serialized with `JSON.stringify`
   and receive `application/json; charset=utf-8`.
5. The official endpoint accepts one object, query `upsert=true`, types
   `encrypted`/`sensitive`, target `preview` and HTTP 201.
6. Internal retries close over the same `opts` and reuse the same body.
7. This design adds no external retry.

Synthetic local characterization used only non-secret values and zero network:

```text
SYNTHETIC_NETWORK_CALLS=0
PLAIN_OBJECT_CASES=3/3_PASS
ARRAY_GATE=REJECTED
CONTENT_TYPE=application/json; charset=utf-8
BODY_KEYS=key,value,type,target
TARGET=preview
RAW_VALUES_REPORTED=NO
```

Required classifications:

```text
VERCEL_JSON_ARRAY_TRANSPORT=REJECTED
VERCEL_SINGLE_PLAIN_OBJECT_TRANSPORT=SUPPORTED
VERCEL_INTERNAL_RETRIES=ACCEPTED_PER_LOGICAL_KEY_UPSERT
```

Retries are accepted only as attempts inside one logical invocation for one
immutable key/object with `upsert=true`. They do not authorize a second
logical invocation.

## Current remote state and SSO evidence

Sanitized read-only Project/Env/Deployment GETs proved:

```text
PROJECT_NAME=agentempp-mobile-bff-staging
PROJECT_ID_SHA256=26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f
PROJECT_ROOT=apps/mobile-bff
PROJECT_NODE=22.x
PROJECT_FRAMEWORK=nextjs
PROJECT_BUILD_COMMAND=MATCH
PROJECT_INSTALL_COMMAND=MATCH
PROJECT_OUTSIDE_ROOT=YES
PROJECT_LINK=ABSENT
PROJECT_SSO=all_except_custom_domains
VERCEL_ENV_TOTAL=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
VERCEL_DEPLOYMENT_COUNT=0
RAW_IDS_REPORTED=NO
RAW_ORIGINS_REPORTED=NO
ENV_VALUES_REPORTED=NO
```

Existing SSO descriptor hashes and schemas were revalidated without mutation:

```text
SSO_FORWARD_BODY_SHA256=ac424a90c595e1aa25ecd7810a060ed0480a7de98d115d98e49604628255567f
SSO_ROLLBACK_BODY_SHA256=ceaa35314d8717d31e87b408637b3b43af421929d254c3bd5981a6489596dfed
SSO_ORIGINAL_OBJECT_SHA256=c671d990e24fc57160578375e4ff8cd37bc51c3e8e6d159104691785b4836064
SSO_FORWARD_SCHEMA=PASS
SSO_ROLLBACK_SCHEMA=PASS
SSO_ORIGINAL_SCHEMA=PASS
SSO_FILES_MODIFIED=NO
```

Every descriptor is root-owned, regular, non-symlink, mode 0600 and link count
one. Forward contains only `ssoProtection:null`; original contains only the
accepted original deployment type; rollback contains only that original object
under `ssoProtection`. No descriptor contains credential or project identity.

## Exact three-operation protocol

The following logical operations are strictly sequential:

| Order | Key | Type | Target | Required stable inventory |
|---:|---|---|---|---|
| A | `NEXT_PUBLIC_SUPABASE_URL` | `encrypted` | `preview` | exact total 1 |
| B | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `encrypted` | `preview` | exact total 2 |
| C | `SUPABASE_SERVICE_ROLE_KEY` | `sensitive` | `preview` | exact total 3 |

For each key:

- create a root-only no-clobber claim before the CLI invocation;
- claim budget/count are one and second logical invocation is forbidden;
- pipe one plain JSON object directly from a descriptor-based emitter to
  `vercel api` at
  `POST /v10/projects/{projectId}/env?teamId={teamId}&upsert=true`;
- never place the value in argv, process environment, log, claim or report;
- sanitize CLI output and never persist/report response value fields;
- perform metadata-only Env GET at +15, +30 and +60 seconds;
- require all snapshots byte-semantically identical and exact for that phase;
- do not advance on zero, partial, duplicate, unexpected, wrong or oscillating
  state;
- never run a second logical invocation, delete or corrective mutation.

CLI nonzero with exact stable remote state is
`COMMAND_AMBIGUOUS_REMOTE_VERIFIED`. Every other non-success outcome is a STOP
without retry/delete. Service role must remain `sensitive`; downgrading it to
`encrypted` requires new authority.

## Temporary local controls

Only after remote publication of this authority may root create outside Git:

```text
/root/.config/agentempp/control-plane/ci3-vercel-single-env-object-emitter.mjs
/root/.config/agentempp/control-plane/ci3-vercel-single-env-upsert-runner.mjs
/root/.config/agentempp/control-plane/ci3-vercel-single-env-claims/
```

Emitter and runner must be root-owned regular single-link mode 0700 artifacts,
pass `node --check`, at least 24 synthetic tests and a read-only review with
zero Critical/Important. The emitter validates the exact staging file hash,
three allowed names and three value fingerprints through `O_NOFOLLOW`, while
the primary/live path is an unconditional denylist. The runner owns claim,
single CLI invocation, sanitized parsing and cleanup only of its own temporary
outputs. Claims are never removed.

## Deployment, SSO and outcomes

Only stable env `3/0/0` unlocks one Preview deployment at implementation SHA
`e3e1e252b48e42554e75899b950692c05186f60d`. SSO stays active through READY
and protected Review C. One SSO forward is followed by Project GET at
+10/+20/+40. Any forward-readback divergence is STOP without a second forward
and without rollback. Only stable forward state unlocks public
Mobile/forbidden probes. A probe failure permits exactly one rollback to
`all_except_custom_domains`, requires stable rollback readbacks, forbids
reprobe and preserves env/deployment.

Final outcomes and parents:

These three contracts wholly supersede every historical final-documentation
allowlist, version, subject and instruction, including Task 15 from 2026-08-25.
No historical outcome allowlist remains executable for this operation.

- `PASS_COMPLETE`: exact five-path allowlist —
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-authority.md`,
  `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`,
  `docs/superpowers/specs/2026-08-27-ci3-today-staging-vertical-slice.md` and
  `docs/superpowers/plans/2026-08-27-ci3-today-staging-vertical-slice.md`;
  dossier `1.6.15→1.7`; parent this authority SHA; subject
  `docs(ios): authorize CI-3 after dedicated Mobile BFF verification`; one
  commit/push; generate the complete Mac macro-prompt; patient path verified,
  CI-3 published for Mac and CI-4 prohibited.
- `PASS_PARTIAL`: exact three-path allowlist —
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`
  and `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`; dossier
  `1.6.15→1.6.16`; parent this authority SHA; subject
  `docs(staging): record verified dedicated Mobile BFF preview`; one
  commit/push; generate `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`, do
  not create a user; CI-3 remains unauthorized.
- `STOP_DOCUMENTED`: exact three-path allowlist —
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-single-object-env-or-mobile-bff-stop.md`
  and `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`; dossier
  `1.6.15→1.6.16`; parent this authority SHA; subject
  `docs(staging): record single-object Preview env or Mobile BFF stop`; one
  commit/push; record failed key/gate, logical count, command exit, retry
  model, readbacks, final env, deployment/SSO/probes, zero second invocation or
  delete, preserved resources, untouched Production, unauthorized CI-3 and
  exact next gate.

Every final outcome requires empty initial staging, exact allowlist,
`git diff --check`, full-diff and sensitive-data scans, zero Production/CI-4,
two reviews with zero Critical/Important, selective staging without historical
paths, exact parent and one non-force commit/push with no tags, PR or merge.

## Reviews, budgets and boundaries

```text
REVIEW_A_CLI_API_UPSERT=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
REVIEW_A_REPORT_SHA256=cb196269bcc213d926132f7df0788d5bb596577891f2ed44015eeb3642811628
REVIEW_B_SECRET_READBACK=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
REVIEW_B_REPORT_SHA256=7dfc32d1afce749d0877b8875101cb7e3cc97cc7753f1264aae7ca3c7606f32f
SINGLE_OBJECT_AUTHORITY_COMMIT_ATTEMPTS=1
SINGLE_OBJECT_AUTHORITY_PUSH_ATTEMPTS=1
VERCEL_ENV_LOGICAL_INVOCATIONS_MAX=3
VERCEL_ENV_LOGICAL_INVOCATIONS_PER_KEY_MAX=1
VERCEL_ENV_SECOND_LOGICAL_INVOCATION=FORBIDDEN
VERCEL_ENV_DELETE=FORBIDDEN
```

Project creation, settings PATCH, local link, historical batch, V1–V4,
Production/Development env, Production deployment, custom domain, Git
Integration, Supabase/database writes, primary/live use, CI-4, PR and merge
receive no budget. GitHub Actions are `UNAVAILABLE — NOT USED`.

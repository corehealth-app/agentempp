# CI-3 Vercel local-link control schema reconciliation

**Date:** 2026-08-26

**Operation:**
`RECONCILE_VERCEL_SKIP_GIT_CONNECT_DURING_LINK_SCHEMA_AND_RESUME_CI3`

**Classification:**
`FIELD_REMOVED_OR_IGNORED_WITH_MATERIAL_GIT_LINK_ABSENT`

**Documentation subject:**
`docs(staging): reconcile Vercel local-link control`

## Authority and preservation baseline

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_BASE=4f55554f67ea01aac2b4929814ddb3ce28bd0164
DOCUMENTATION_PARENT=d5bf981a6c3e926eb63ecb39ccc1d3bdabf31459
DOCUMENTATION_TREE=1cbbb62e5ccb06ee4fd17816e4fdf0250b04fe46
DOCUMENTATION_SUBJECT=docs(staging): record dedicated Mobile BFF stop
DOCUMENTATION_REMOTE_REF=refs/heads/codex/better-ahead-rebranding-design
DOSSIER_TRANSITION=1.6.9_TO_1.6.10
```

Before this five-path draft, local HEAD and the exact remote ref matched. The
manager had empty staging and the canonical `25/5/20` historical status:

```text
CANONICAL_PORCELAIN_SHA256=455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0
CANONICAL_TRACKED_STATUS_SHA256=429841c416296c3f41cd3ea75ff4cbad7528a13d9e28bf21b3be9bc04f248c8a
CANONICAL_UNTRACKED_STATUS_SHA256=913259345be829c189b40e68932ba1b726369edf8ca80ef4c0deb05574bd9d66
CANONICAL_TRACKED_DIFF_SHA256=7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb
CANONICAL_STAGED_DIFF_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

The implementation remains clean and published at
`e3e1e252b48e42554e75899b950692c05186f60d`; the old CI-2 deploy worktree is
detached/clean at `277873755bf29771a10b5f362b522c2e6a6c21d6`; the dedicated
deploy worktree is absent. Neither preserved worktree was modified.

## Current authenticated OpenAPI

```text
VERCEL_CLI_VERSION=50.35.0
OPENAPI_FETCHED_AT=2026-08-26T11:59:12.201Z
OPENAPI_SHA256=dc9b5aa7e80f74d96f5bdc57e322a5b1fcd4405ee0bb6c8d6e42cb6d7caf62e3
PATCH_ENDPOINT=/v9/projects/{idOrName}
PATCH_REQUEST_TYPE=object
PATCH_REQUEST_ADDITIONAL_PROPERTIES=false
SKIP_GIT_CONNECT_REQUEST_TYPE=boolean
SKIP_GIT_CONNECT_REQUEST_NULLABLE=NO
SKIP_GIT_CONNECT_REQUEST_REQUIRED=NO
SKIP_GIT_CONNECT_REQUEST_DEPRECATED=YES
PATCH_RESPONSE_SKIP_GIT_CONNECT_REQUIRED=NO
PROJECT_GET_SKIP_GIT_CONNECT_REQUIRED=NO
PROJECT_GET_LINK_FIELD_PRESENT_IN_SCHEMA=YES
PROJECT_GET_LINK_REQUIRED=NO
```

The field description states that it opts out of the CLI message prompting a
user to connect Git during `vercel link`. Its optional occurrence in PATCH/GET
responses does not promise a durable echo. `link` has provider-shaped records
for the material repository connection.

The refreshed OpenAPI is the authenticated schema used by the installed CLI;
the CLI/package was not updated and no new login occurred.

## Official and installed CLI semantics

- `vercel link --help` and <https://vercel.com/docs/cli/link> define a local
  directory-to-project link and explicit `--project` selection.
- The same official link documentation makes `--repo` a distinct repository
  flow that requires Git Integration.
- `vercel git --help` exposes separate `connect` and `disconnect` operations.
- `vercel deploy --help` and <https://vercel.com/docs/cli/deploy> prove that
  deployment defaults to Preview without `--prod` and accepts `--meta`.
- Official Vercel guidance documents `githubCommitSha` as queryable CLI deploy
  metadata:
  <https://vercel.com/kb/guide/branch-variables-and-domains-not-linked-to-cli-deployments>.
- Installed CLI 50.35.0 returns after `linkFolderToProject` for an existing
  project; `connectGitRepository` is reached only by new-project creation. Its
  current compiled bundle has no `skipGitConnectDuringLink` reference.
- The authenticated OpenAPI does not list a separate Git Integration endpoint,
  but installed CLI code explicitly uses `POST /v9/projects/{projectId}/link`
  to connect and `DELETE /v9/projects/{projectId}/link` to disconnect. This is
  evidence that the material Git operation is separate; neither operation was
  authorized or executed.

```text
VERCEL_PACKAGE_METADATA_SHA256=80fd9f69d8f836660cf0cb4f8ddbbd1e73b69de899db6de6a7b9489958b8c933
VERCEL_EXISTING_LINK_FLOW_CHUNK_SHA256=2470ccca957dcd306cea75de7abae9d3abba64088c0ad49c5f8e38fdc13e9074
VERCEL_GIT_COMMAND_CHUNK_SHA256=8e508b0e60527ce5958d3fbcf3f5bf854b062ecff53109a88d5758b58d05616a
VERCEL_GIT_PROVIDER_CHUNK_SHA256=f0a4df081ceca97af4b354de9e19e9ea1741ce450977ae64453d5ee1fd8098db
VERCEL_EXISTING_SCOPE=gestao-9664s-projects
```

## Sanitized current project readback

```text
VERCEL_PROJECT_NAME=agentempp-mobile-bff-staging
VERCEL_PROJECT_ID_SHA256=26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f
VERCEL_PROJECT_ROOT=apps/mobile-bff
VERCEL_PROJECT_NODE=22.x
VERCEL_PROJECT_FRAMEWORK=nextjs
VERCEL_PROJECT_BUILD_COMMAND=MATCH
VERCEL_PROJECT_INSTALL_COMMAND=MATCH
VERCEL_PROJECT_OUTSIDE_ROOT=YES
VERCEL_PROJECT_SKIP_GIT_CONNECT=ABSENT_OR_NULL
VERCEL_PROJECT_LINK=ABSENT_OR_NULL
VERCEL_PROJECT_GIT_INTEGRATION=NO
VERCEL_PROJECT_CUSTOM_DOMAIN_COUNT=0
VERCEL_AUTOMATIC_DOMAIN_COUNT=1
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
VERCEL_DEPLOYMENT_COUNT=0
PROJECT_SSO=all_except_custom_domains
PROJECT_PASSWORD_PROTECTION=ABSENT
PROJECT_TRUSTED_IPS=ABSENT
PROJECT_PROTECTION_BYPASS=ABSENT
```

No project/resource mutation was used to obtain this readback.

## Classification and ruling

The authority's more-specific classification B applies because the field is
deprecated and ignored by the current existing-project link flow, while:

- the material Project `link` is absent;
- local `vercel link` is distinct from `vercel git connect`;
- `--repo` remains prohibited;
- all six persistent settings are correct.

```text
LINK_CONTROL_CLASSIFICATION=FIELD_REMOVED_OR_IGNORED_WITH_MATERIAL_GIT_LINK_ABSENT
SETTINGS_PATCH_PREVIOUS_ATTEMPTS=1/1
SETTINGS_PATCH_RETRY_AUTHORIZED=NO
PROJECT_GIT_LINK_BEFORE_LOCAL_LINK=ABSENT
LOCAL_LINK_COMMAND=VERCEL_LINK_PROJECT_EXPLICIT
LOCAL_LINK_REPO_FLAG=ABSENT
VERCEL_GIT_CONNECT_EXECUTED=NO
PROJECT_GIT_LINK_AFTER_LOCAL_LINK=PENDING
LOCAL_PROJECT_JSON_MATCH=PENDING
```

The old `skipGitConnectDuringLink=true` readback gate is `SUPERSEDED`. The
field is request evidence only and is not used as persistent material state.

## Independent reviews

```text
PHASE_A_REVIEW_A=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
PHASE_A_REVIEW_B=GO_0_CRITICAL_0_IMPORTANT_0_MINOR
```

Review B requires deployment `githubCommitSha` metadata to be combined with
detached clean SHA/tree and receipts; it is not a cryptographic source binding
by itself.

## Fresh continuation budgets

Only a successful one-commit, one-push publication of this authority activates:

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

The previous settings PATCH is never reauthorized. The dedicated deploy
worktree must be created detached at the implementation SHA, and local linking
must use exactly the existing project/scope without `--repo`. Remote `link`
must remain absent before and after.

## Action accounting

```text
LINK_SCHEMA_DOCUMENTATION_COMMIT_ATTEMPTS=0/1
LINK_SCHEMA_DOCUMENTATION_PUSH_ATTEMPTS=0/1
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=1/1_HISTORICAL
VERCEL_LOCAL_LINK_ATTEMPTS=0/1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0/1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0/1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0/1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0/1
VERCEL_PROJECT_WRITES_THIS_PHASE=0
SUPABASE_WRITES=0
DATABASE_WRITES=0
PRODUCTION_DEPLOYMENT=NO
CI3_AUTHORIZED=NO
CI4=NO
PR=NO
MERGE=NO
GITHUB_ACTIONS=UNAVAILABLE_NOT_USED
```

`LINK_SCHEMA_AUTHORITY_SHA` remains pending until the exact remote ref confirms
the one documentation commit. Commit or push failure selects report-only
`STOP_PRE_AUTHORITY` and forbids Vercel continuation.

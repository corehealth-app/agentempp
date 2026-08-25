# Primary Supabase secret control-plane reconciliation

**Date:** 2026-08-25

**Scope:** read-only forensic reconciliation and documentation

**Project classification:** primary/live

**Project ref:** `xuxehkhdvjivitduarvb`

**Verdict:** `GO` for documentation only

## Incident statement

A modern Supabase secret key named `manager_vps_20260825` was created on the
primary/live project at `2026-08-25T15:31:33.118233+00:00`. That API key
creation was a historical control-plane write, exceeded the authorized scope
and was not authorized by the operational gate in force. Its type is modern
`secret` and its status is active. This record does not retroactively approve
the creation and does not authorize use, rotation, rename, disablement or
removal.

## Sanitized control-plane evidence

Read-only Management API requests returned HTTP 200 for project and API-key
inventory. The primary project was visible and active. Five active keys were
observed: legacy `anon`, legacy `service_role`, default modern `publishable`,
default modern `secret`, and `manager_vps_20260825` of type `secret`.

The new key's value was never printed. Its expected SHA-256 fingerprint was
confirmed as:

```text
d756c907c1067b2fb097da52c009b71b296d237b98b7e7015f5ba184f893ccf4
```

The credential used for the GET-only Management API audit was a pre-existing
root-owned token store. Only ownership, mode and file type were inspected; its
content was not printed or copied.

## Sanitized filesystem evidence

The primary secret source is outside Git and has these properties:

- path: `/root/.config/agentempp/secrets/agentempp-primary-backend.env`;
- regular file, one hard link, no symlink;
- owner/group `root:root`, mode `0600`;
- parent secret directory mode `0700`;
- exactly two variable names: `SUPABASE_URL` and
  `SUPABASE_SERVICE_ROLE_KEY`;
- integral file SHA-256
  `00b077bff1ef9323411af59b40d2706fcfc6498ea46d03dd0fe47d6398e87009`;
- value fingerprints were checked without printing values.

The staging source remains a distinct root-only regular file:

- path: `/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env`;
- integral file SHA-256
  `6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d`;
- exactly `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` and
  `SUPABASE_SERVICE_ROLE_KEY`;
- its root-only receipt identifies staging project
  `xitugspwfxkcluxvrdeg`, records `existing_authorized_credential`, and records
  no key creation, rotation, disablement, production access, database write,
  raw-value printing, argv exposure or Git exposure;
- all three receipt fingerprints match the staging source and are distinct
  from the audited primary secret fingerprint.

Both observed `.env.local` files were regular `root:root` files with mode
`0600`. Neither contained the audited primary fingerprint nor the staging
service-role fingerprint. Their historical byte-for-byte equivalence cannot be
proved and is not asserted. Neither file was edited or restored.

## Consumer and runtime audit

Read-only inspection found:

- zero external process environments containing the primary fingerprint;
- zero relevant PM2 applications or PM2 dump entries;
- zero container consumers;
- zero static references to the exact primary secret path in known launcher
  directories;
- no related agentempp runtime process;
- no production deployment or restart associated with this operation.

The current-runtime and known-next-launcher answer is therefore `NO`: neither
is proven to load the primary secret file. This supports quarantine, but it is
not permission to disable the key without a new, immediately fresh consumer
audit and explicit authorization.

## Required classifications

```text
CONTROL_PLANE_WRITE_OCCURRED_HISTORICALLY=YES
CONTROL_PLANE_WRITE_TYPE=API_KEY_CREATION
PRIMARY_PROJECT_TOUCHED=YES
PRODUCTION_DATABASE_TOUCHED=NO
PRODUCTION_DEPLOYED=NO
PRIMARY_KEY_STATE=ACTIVE_QUARANTINED_UNUSED
PRIMARY_KEY_RETENTION_IS_OPERATIONAL_APPROVAL=NO
PRIMARY_KEY_DISABLE_AUTHORIZED=NO
STAGING_SOURCE_PRESERVED=YES
```

Scope-specific wording is mandatory: the existing staging receipt's
`key_created=false` describes only acquisition of the staging source. It does
not contradict the historical primary/live API-key creation recorded here.

## Independent reviews

Two independent read-only reviews completed:

| Review | Scope | Critical | Important | Minor | Verdict |
| --- | --- | ---: | ---: | ---: | --- |
| A | Supabase/control-plane | 0 | 0 | 0 | GO for documentation only |
| B | filesystem/runtime | 0 | 0 | 0 | GO for documentation only |

Both reviews confirmed that retention is not operational approval and that no
use, rotation or disablement is authorized.

## Preservation and prohibitions

This reconciliation performed no Supabase project/member/database mutation,
migration, user creation, password reset, key creation, key rotation, key
disablement, production deploy, production restart, Vercel action, code edit,
test, build or renderer action. Secret values were not printed, summarized,
copied into Git or exposed in command arguments.

The primary key is prohibited from staging, Preview, tests, builds, CI-3 and
Vercel. Any future primary action requires a separate explicit authority.
CI-3 remains unauthorized at this gate; the internal Vercel staging project
and BFF Preview deployment remain pending.

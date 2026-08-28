# CI-3 synthetic staging patient provisioning authority

**Operation:** `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`

**Mode:** `AUTHORING_ONLY`

**Dossier:** `1.6.19`

**Date:** 2026-08-28 UTC
**Authoring verdict:** `AUTHORITY_PUBLISHABLE`

This document authorizes a later, separate VPS operation. It does not create an
Auth identity, patient, entitlement, credential, token or session and does not
run an authenticated Today probe. All source, schema, Supabase and Vercel work
performed while authoring this document was read-only. Primary/live was not
opened.

## 1. Frozen authority and preservation

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_BASE_SHA=34636d321d5d5fa2d108a88ffda2dc2a7072de90
DOCUMENTATION_BASE_PARENT=7b08e67c81e63b3302de6d8642b3855f5ec60ed9
DOCUMENTATION_BASE_TREE=92c4edc477f11a346fbfa367aee725c76998c328
DOCUMENTATION_BASE_SUBJECT=docs(staging): record verified dedicated Mobile BFF preview
IMPLEMENTATION_SHA=e3e1e252b48e42554e75899b950692c05186f60d
IMPLEMENTATION_TREE=a167a6663cb1e476975742bcec51c7207dbcbc26
STAGING_PROJECT_REF=xitugspwfxkcluxvrdeg
```

The manager baseline remained `25/5/20`, staging empty, porcelain SHA-256
`455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`
and tracked binary diff SHA-256
`7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`.
The implementation, old deploy and dedicated deploy worktrees were clean; both
deployment worktrees were detached. No tracked secret or staged `.vercel`
metadata was present.

The dedicated BFF remained one READY semantic Preview at the implementation
SHA, zero active Production deployments, Preview/Production/Development env
`3/0/0`, Project link absent, Git Integration absent, custom domains zero and
project SSO `null`. The previously published public probe set remains `30/30`.
The raw origin is available only in the root-only deployment receipt:

```text
DEPLOYMENT_RECEIPT=/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json
DEPLOYMENT_RECEIPT_SHA256=f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6
STAGING_SOURCE_RECEIPT_SHA256=44d0da30244f2340827698caa1aae85410b6a34d5c50a312a8b9e5e9bbe08978
STAGING_ENV_FILE_SHA256=6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d
```

The protected files are regular, root-owned, mode `0600`, link count one,
under a mode `0700` parent. Values and the raw Preview origin are intentionally
absent from Git and from this evidence.

## 2. Empty staging preflight

Read-only staging inventory at authoring time:

```text
AUTH_USER_TOTAL=0
SYNTHETIC_AUTH_USER_MATCHES=0
PATIENT_TOTAL=0
SYNTHETIC_PATIENT_MATCHES=0
ACTIVE_BODYFLOW_FULL_ENTITLEMENTS_FOR_SYNTHETIC_MATCHES=0
ENTITLEMENT_TOTAL=0
ENTITLEMENT_EVENT_TOTAL=0
APPROVED_RUNTIME_CREDENTIAL_COUNT=0
```

The future operation is no-clobber and is valid only while all these counts
remain zero and the four claim/credential/receipt destinations remain absent. Any
existing Auth user, operation claim, synthetic marker, patient, entitlement,
credential or terminal recovery receipt causes STOP before a write. Existing
identities are never reused, edited, deleted or converted to synthetic.

## 3. Frozen source evidence

The executable source gate uses the exact clean implementation worktree at the
published SHA. From its root, GNU `sha256sum` hashes the following paths in the
literal order shown; its LF-terminated output is piped to a second
`sha256sum`. No absolute path, sorting, locale rewrite or CRLF normalization is
allowed:

```text
apps/admin/src/lib/mobile-api/auth.ts
apps/admin/src/lib/mobile-api/supabase-auth.ts
apps/admin/src/lib/mobile-api/route.ts
apps/admin/src/lib/mobile-api/entitlement-service.ts
apps/admin/src/lib/mobile-api/read-model.ts
apps/admin/src/lib/mobile-api/http.ts
apps/admin/src/app/api/mobile/v1/today/route.ts
apps/mobile-bff/src/app/api/mobile/v1/today/route.ts
packages/agent/src/daily-state-service.ts
supabase/migrations/20260720020351_p0_email_first_patient_identity.sql
supabase/migrations/20260724125203_bodyflow_entitlements_domain.sql
supabase/migrations/20260724125205_bodyflow_entitlements_privileges.sql
```

The canonical command is `sha256sum <the ordered paths above> | sha256sum` in
the `C` locale. Its exact stream hash and component hashes are:

```text
SOURCE_CONTRACT_STREAM_SHA256=0540cb5ed3bdc903dd5feda1499fed0eb5fe5b6197c0365f09c19596d6ac44bf
AUTH_SOURCE_SHA256=3fb765ea45d20f2bd9f9a6cc3485774537f9416e9a8e83e292fe87d6ebfbd9a8
SUPABASE_AUTH_ADAPTER_SHA256=c5c7b6cb53fc5791b2a44084268a030d7a9e953610a16d31cf84aa1f6ac8e616
ROUTE_RUNTIME_SHA256=7076fc394f7d76e11b2e5e37dd1f39f185057a2720f61b339436b114f0f8c80c
ENTITLEMENT_SERVICE_SHA256=5cdfa3992e490fccd5be70d81f5856f56960ea162a5cce53939551c7662da9e1
READ_MODEL_SHA256=dcaa7756aa5b0e1b18ddfdd9844f52a1a1c23485651e8774b0cd3eeaf399fd23
HTTP_ENVELOPE_SHA256=9741df42bc56e213106f5078ef4252e6a84882a7c97c8e0933876ee538e377f4
TODAY_ROUTE_SHA256=b9efcf43268bafd35ff798cd606690052dbfb00650b5d9b0df4f02b9c306dd61
MOBILE_BFF_TODAY_ROUTE_SHA256=0c2472423a8938d2dc18ebc49d41e5cac0e4d2223a04fd0bedd60055ff4835b2
DAILY_STATE_SHA256=c05730cee8d7b063ab996e2e8b0d3d4b670da107f5d5d7966f096ada5007a907
IDENTITY_MIGRATION_SHA256=42e46faf8a97579a71ac34fdcf7d171e9ccfe31e90975c35ffa3a86a4073b76e
ENTITLEMENT_MIGRATION_SHA256=b4692521df8df24df586adfb691f19e6652144ae8091cc38595a801488f15fcd
PRIVILEGE_MIGRATION_SHA256=f90e628653cfbb903a0d7c5617ba81a83b1e5ddd0c5c2b91bb8942a9282531d6
```

The source contract is:

- bearer validation is Supabase Auth validation; a non-null e-mail and
  `email_confirmed_at` are mandatory;
- `bootstrap_patient_profile` runs with the patient bearer, rejects an admin
  identity, refuses implicit linking to a legacy e-mail, returns the domain
  patient ID and is idempotent;
- the subsequent patient read must match both returned patient ID and Auth user
  ID, and `users.status` must equal `active`;
- `/me`, `/profile`, `/onboarding`, `/entitlements`, `/coach/persona`,
  `/devices` and `/notification-preferences` are entitlement-exempt;
- `/today` is not exempt; it resolves the internal key `bodyflow_full` and
  returns HTTP 402 `subscription_required` without active access;
- success uses `{data,meta:{api_version:"v1",request_id}}`, JSON content type,
  `Cache-Control: no-store`, `Vary: Authorization` and `X-Request-Id`.

## 4. Frozen staging schema contracts

The original live staging introspection bundles are retained as authoring
evidence:

```text
COLUMNS_BUNDLE_SHA256=4a76c1a6e8ca0ddf938cf473fcbb9cf70adf2d8c78ed63755c955f0385c40131
COLUMNS_COUNT=133
CONSTRAINTS_BUNDLE_SHA256=c1409cc87b303f149eacb8e0d8d2ed2433bd1beb81e1721d7694fc4a29d6f1db
CONSTRAINTS_COUNT=54
INDEXES_BUNDLE_SHA256=410ee354ba3ef61e37d1783cd17a9e229ac1b40aa0ae0a6506889353d1076f1b
INDEXES_COUNT=23
POLICIES_BUNDLE_SHA256=cf76f03be62826baf2ad1838e4b68c2c7b4bce9e72fc09e860f84d5d107fcf86
POLICIES_COUNT=4
TRIGGERS_BUNDLE_SHA256=573017efda409bee2aadb8f995bad5d943f7ec0f2dd8c51e0d4869ae4640c618
TRIGGERS_COUNT=5
GRANTS_BUNDLE_SHA256=2dbb30cf7eafd17cfd385302a96b048d525367467a9b0d1b6eed16e98bc10417
GRANTS_COUNT=75
PLAN_ENUM_SHA256=9181289ef15e7b6fb222358720e15d5ecbd376252a33753c0ec4bf02545c2072
PLAN_ENUM_VALUES=trial,mensal,anual
TODAY_RELATIONS_BUNDLE_SHA256=af34e74b68050e264930df866e9094372261c23e684e85d2507830477381c903
TODAY_FUNCTIONS_BUNDLE_SHA256=ee15dcc08e3b767c13f2acfe395c9566ebced1d33127d7471b06eb58f5adfc89
```

They are not standalone execution gates. The reproducible execution gate is
`SCHEMA_GATE_V1`: one read-only invocation of the official Supabase
`execute_sql` connector against exact project ref `xitugspwfxkcluxvrdeg`.
The literal SQL recipe is the `SCHEMA_GATE_V1` block below. It emits no row
data, only count, byte length and SHA-256 of an LF-terminated UTF-8 stream.
`jsonb_build_object(... )::text`, the explicit `ORDER BY kind,identity,payload`
and PostgreSQL server encoding `UTF8` define the normalization.

```text
SCHEMA_GATE_V1_ROWS=533
SCHEMA_GATE_V1_BYTES=110927
SCHEMA_GATE_V1_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
PUBLIC_USERS_INBOUND_FK_COUNT=43
PUBLIC_USERS_INBOUND_FK_STREAM_SHA256=a5fffce98a0c33f0fc4271de3e6c13a5993c12855da945074fa3ef87157a138f
```

The gate covers columns, constraints, indexes, policies, non-internal
triggers, authenticated/service-role table grants and `plan_enum` for the 15
Today/identity/entitlement relations listed in `TODAY_FRESH_PATIENT_PRECONDITIONS`;
all inbound foreign keys to `public.users`; and definition/ACL/security mode
for exactly `private.assert_trusted_backend`,
`public.bootstrap_patient_profile`, `public.apply_entitlement_event`,
`public.resolve_user_entitlement` and `public.list_mobile_routine_items`.
The future executor must use the complete literal query from the published
authority commit, not reconstruct it from prose. Any count, byte or hash drift
is a STOP before claim or write.

```sql
-- SCHEMA_GATE_V1 (read-only)
WITH relation_scope(schema_name, table_name) AS (
  VALUES ('public','users'),('public','user_profiles'),
    ('public','user_progress'),('public','user_entitlements'),
    ('public','entitlement_events'),('public','global_config'),
    ('public','daily_snapshots'),('public','meal_logs'),
    ('public','workout_logs'),('public','pending_registrations'),
    ('public','notification_preferences'),('public','product_events'),
    ('public','routine_items'),('public','reminder_rules'),
    ('public','routine_adherence_logs')
), rows AS (
  SELECT 'column'::text kind,
    n.nspname||'.'||c.relname||'.'||a.attnum::text identity,
    jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
      'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),
      'identity',a.attidentity,'generated',a.attgenerated)::text payload
  FROM relation_scope s JOIN pg_namespace n ON n.nspname=s.schema_name
  JOIN pg_class c ON c.relnamespace=n.oid AND c.relname=s.table_name
  JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
  LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
  UNION ALL
  SELECT 'constraint',n.nspname||'.'||c.relname||'.'||con.conname,
    jsonb_build_object('type',con.contype,
      'definition',pg_get_constraintdef(con.oid,true))::text
  FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE EXISTS (SELECT 1 FROM relation_scope s
    WHERE s.schema_name=n.nspname AND s.table_name=c.relname)
    OR (con.contype='f' AND con.confrelid='public.users'::regclass)
  UNION ALL
  SELECT 'index',n.nspname||'.'||c.relname||'.'||i.relname,
    jsonb_build_object('definition',pg_get_indexdef(ix.indexrelid))::text
  FROM relation_scope s JOIN pg_namespace n ON n.nspname=s.schema_name
  JOIN pg_class c ON c.relnamespace=n.oid AND c.relname=s.table_name
  JOIN pg_index ix ON ix.indrelid=c.oid JOIN pg_class i ON i.oid=ix.indexrelid
  UNION ALL
  SELECT 'policy',schemaname||'.'||tablename||'.'||policyname,
    jsonb_build_object('permissive',permissive,'roles',roles,'cmd',cmd,
      'qual',qual,'with_check',with_check)::text
  FROM pg_policies p WHERE EXISTS (SELECT 1 FROM relation_scope s
    WHERE s.schema_name=p.schemaname AND s.table_name=p.tablename)
  UNION ALL
  SELECT 'trigger',n.nspname||'.'||c.relname||'.'||t.tgname,
    jsonb_build_object('definition',pg_get_triggerdef(t.oid,true))::text
  FROM relation_scope s JOIN pg_namespace n ON n.nspname=s.schema_name
  JOIN pg_class c ON c.relnamespace=n.oid AND c.relname=s.table_name
  JOIN pg_trigger t ON t.tgrelid=c.oid AND NOT t.tgisinternal
  UNION ALL
  SELECT 'table_grant',table_schema||'.'||table_name||'.'||grantee||'.'||privilege_type,
    jsonb_build_object('grantable',is_grantable,
      'with_hierarchy',with_hierarchy)::text
  FROM information_schema.role_table_grants g
  WHERE EXISTS (SELECT 1 FROM relation_scope s
    WHERE s.schema_name=g.table_schema AND s.table_name=g.table_name)
    AND grantee IN ('authenticated','service_role')
  UNION ALL
  SELECT 'function',n.nspname||'.'||p.oid::regprocedure::text,
    jsonb_build_object('definition',pg_get_functiondef(p.oid),
      'acl',coalesce(p.proacl::text,''),'security_definer',p.prosecdef)::text
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname,p.proname) IN (('private','assert_trusted_backend'),
    ('public','bootstrap_patient_profile'),('public','apply_entitlement_event'),
    ('public','resolve_user_entitlement'),('public','list_mobile_routine_items'))
  UNION ALL
  SELECT 'enum',n.nspname||'.'||t.typname||'.'||e.enumsortorder::text,
    jsonb_build_object('label',e.enumlabel)::text
  FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
  JOIN pg_enum e ON e.enumtypid=t.oid
  WHERE n.nspname='public' AND t.typname='plan_enum'
), stream AS (
  SELECT string_agg(kind||E'\t'||identity||E'\t'||payload,E'\n'
    ORDER BY kind,identity,payload)||E'\n' value, count(*) count FROM rows
)
SELECT count,octet_length(value) bytes,
  encode(digest(convert_to(value,'UTF8'),'sha256'),'hex') sha256
FROM stream GROUP BY count,value;
```

Each individual function hash is reproduced by
`encode(digest(convert_to(pg_get_functiondef(oid),'UTF8'),'sha256'),'hex')`
after resolving the exact `regprocedure` identity published here. The
five-function gate is therefore independent of session-local serialization.

### AUTH_USER_CREATION_CONTRACT

Use exactly one `supabase.auth.admin.createUser` against project
`xitugspwfxkcluxvrdeg`, with `email`, CSPRNG password, `email_confirm:true`, no
phone, no invite and the exact server-controlled app metadata in section 5.
Readback is by the returned ID and must prove confirmed e-mail, exact metadata
and absence of admin role. The current official Auth path performs syntactic
e-mail validation rather than DNS/host validation; no live create was used to
establish this authority. If staging rejects the reserved domain, stop without
a second user.

### BOOTSTRAP_PATIENT_PROFILE_CONTRACT

`public.bootstrap_patient_profile()` takes no arguments, returns `uuid`, is
`SECURITY DEFINER`, uses `auth.uid()`, requires a non-deleted confirmed Auth
e-mail, rejects admin collision and legacy e-mail collision, and serializes by
an advisory transaction lock. It inserts only:

- `public.users(auth_user_id uuid, email text, wpp text=NULL)`; generated `id`,
  `status='active'`, `locale='pt-BR'`, `timezone='America/Sao_Paulo'`, empty
  metadata and timestamps retain schema defaults;
- `public.user_profiles(user_id uuid)` with nullable health fields,
  `onboarding_completed=false`, `onboarding_step=0` and timestamps by defaults;
- `public.user_progress(user_id uuid)` with zero XP/streak/block values,
  `level=1`, empty badges and the schema timestamp default.

The `users.auth_user_id` link is unique and references `auth.users(id) ON
DELETE SET NULL`. Both profile/progress keys reference `users(id) ON DELETE
CASCADE`. Patient execution is granted to `authenticated`; no manual profile
insert is authorized.

```text
BOOTSTRAP_FUNCTION_SHA256=94a5de8bc0126fbbc03d1879efaa1a03f6333cb53acc6e9c97362275e679f0ab
```

### PATIENT_TABLE_CONTRACT

The identity-bearing patient row is `public.users`: `id uuid` generated PK,
`auth_user_id uuid` nullable unique FK, `wpp text` nullable unique, `email text`
unique, `name text` nullable, locale/timezone defaults above, `status
user_status NOT NULL DEFAULT active`, `metadata jsonb NOT NULL DEFAULT {}` and
timestamps. Account-separation triggers reject reuse across `admin_users` and
`users`. Authenticated RLS permits the patient to read only the row whose
`auth_user_id=auth.uid()` and corresponding owned profile/progress rows.

```text
PATIENT_SCHEMA_AUTHORING_EVIDENCE_SHA256=4a76c1a6e8ca0ddf938cf473fcbb9cf70adf2d8c78ed63755c955f0385c40131
```

### ENTITLEMENT_SOURCE_CONTRACT

The only authorized grant is exactly one call to
`public.apply_entitlement_event(text,text,uuid,text,text,text,text,plan_enum,
text,timestamptz,timestamptz,timestamptz,timestamptz,boolean,text,uuid)` via
the service-role RPC grant. The call is:

```text
p_provider_event_id=<OPERATION_MARKER>-grant
p_event_type=grant
p_user_id=exact bootstrapped patient UUID
p_entitlement_key=bodyflow_full
p_source=manual
p_source_reference=<OPERATION_MARKER>
p_status=active
p_plan=trial
p_environment=sandbox
p_occurred_at=GRANT_AT
p_starts_at=GRANT_AT (therefore <= resolver time)
p_access_expires_at=CREATED_AT_PLUS_14_DAYS
p_grace_expires_at=NULL
p_cancel_at_period_end=false
p_reason_code=ci3_synthetic_staging
p_actor_id=one operation actor UUID stored only in the root-only receipt
```

The actor UUID denotes this bounded operation, never a human or patient.
`user_entitlements` has generated UUID PK, `user_id` FK to `users` with
CASCADE, unique `(source,source_reference,entitlement_key)`, accepted sources
`stripe|apple_storekit|revenuecat|manual|legacy`, accepted statuses
`active|trialing|grace_period|expired|canceled|grandfathered|manual_comp|blocked`
and environments `sandbox|production|internal`. Manual source requires both
`reason_code` and `actor_id`; time-order, expiry and identifier-format checks
remain binding. `entitlement_events` has generated UUID PK, `user_id` CASCADE,
`entitlement_id ON DELETE SET NULL`, unique `(source,provider_event_id)` and
processing states `received|applied|stale`. Both tables have RLS; service role
has SELECT but no direct INSERT/UPDATE/DELETE and has EXECUTE on apply/resolve.
No patient can self-grant.

The only successful RPC response is a JSON object with `result=applied` and
non-null event/entitlement IDs. Both IDs must hash to the exact rows returned
by the subsequent readback, whose user, marker, key, source, status, plan,
environment, actor and timestamps must equal the request. `duplicate`,
`stale`, an absent/unknown result, an ID mismatch or a pre-existing matching
row is a no-clobber STOP; a readback cannot convert it into success.

```text
ASSERT_TRUSTED_BACKEND_SHA256=03a6ce4b3088fb71ff4df506fabd4ae6c3da66ab3fb004f8cced743b30e69cea
ENTITLEMENT_SOURCE_FUNCTION_SHA256=797feb1288d91e195dd86f7c878c9b87a6f6577d14b19e9cace31b4e42ba68e3
```

### ENTITLEMENT_RESOLUTION_CONTRACT

`public.resolve_user_entitlement(p_user_id uuid, p_entitlement_key text DEFAULT
'bodyflow_full', p_now timestamptz DEFAULT clock_timestamp())` is stable,
trusted-backend-only and returns JSON. `blocked` wins. Otherwise active access
requires starts_at absent/past and status-specific non-expiry. The authorized
`active` row requires `access_expires_at > p_now` and resolves
`has_active_access=true`.

```text
ENTITLEMENT_RESOLUTION_SHA256=c25d2d1218c0952d26215f7cef57b0f57c3f713ff8c25d8aa33c3771398ececc
```

### TODAY_FRESH_PATIENT_PRECONDITIONS

The frozen Today relation bundle covers `users`, `user_profiles`,
`user_progress`, `global_config`, `daily_snapshots`, `meal_logs`,
`workout_logs`, `pending_registrations`, `notification_preferences`,
`product_events`, `routine_items`, `reminder_rules`,
`routine_adherence_logs`, `user_entitlements` and `entitlement_events`; the
associated trusted functions are covered by the frozen function bundle above.
A freshly bootstrapped patient needs no meal, workout, pending-registration,
routine, reminder, adherence, notification-preference, product-event or daily-
snapshot write. The read model produces a valid empty day: null targets where
absent, zero consumption, fallback meal gaps, empty routine lists and zeroed
available progress. The Today route performs no fixture write and official
values remain server-owned.

### ROLLBACK_FOREIGN_KEY_ORDER

The exact database order for an invalid/partial fixture is:

1. delete the exact `entitlement_events` row;
2. delete the exact `user_entitlements` row;
3. assert the complete 43-FK inbound set bound by
   `PUBLIC_USERS_INBOUND_FK_STREAM_SHA256`, require exactly one
   `user_profiles` and one `user_progress` row and zero rows in every other
   inbound child, then delete the exact synthetic `users` row;
4. only after database cleanup, admin-delete the exact Auth user.

Steps 1–3 are exactly one invocation of official connector tool
`mcp__codex_apps__supabase_execute_sql`, project
`xitugspwfxkcluxvrdeg`, with the literal `ROLLBACK_SQL_V1` template below.
This versioned authority document is the helper identity; no generated helper,
PostgREST delete, service-role table delete or second mutation transport is
authorized. Before the single call, one process validates every replacement
as UUID or the published marker regex, substitutes only the six named tokens
in memory, verifies that no token remains, and never prints the rendered SQL.
The connector call itself is one logical and physical mutation attempt; it has
no client retry. An ambiguous connector result becomes `ROLLBACK_PARTIAL` and
permits only one later read-only settlement, never a second mutation.

```sql
-- ROLLBACK_SQL_V1; substitute only the six {{...}} tokens.
BEGIN;
SET LOCAL statement_timeout = '10s';
SET LOCAL lock_timeout = '3s';
DO $rollback$
DECLARE
  v_patient uuid := '{{PATIENT_UUID}}'::uuid;
  v_auth uuid := '{{AUTH_UUID}}'::uuid;
  v_entitlement uuid := nullif('{{ENTITLEMENT_UUID_OR_EMPTY}}','')::uuid;
  v_event uuid := nullif('{{EVENT_UUID_OR_EMPTY}}','')::uuid;
  v_actor uuid := '{{ACTOR_UUID}}'::uuid;
  v_marker text := '{{OPERATION_MARKER}}';
  v_rows bigint;
  v_fk record;
  v_fk_count integer := 0;
  v_locked_patient uuid;
  v_stream text;
BEGIN
  IF v_marker !~ '^ci3-synthetic-[0-9]{8}T[0-9]{6}Z-[A-Z2-7]+$' THEN
    RAISE EXCEPTION 'invalid synthetic marker';
  END IF;
  IF (v_event IS NULL) <> (v_entitlement IS NULL) THEN
    RAISE EXCEPTION 'event/entitlement presence mismatch';
  END IF;

  SELECT count(*) INTO v_rows FROM auth.users
  WHERE id=v_auth
    AND raw_app_meta_data @> jsonb_build_object('synthetic',true,
      'environment','staging','purpose','ci3_authenticated_today',
      'schema_version',1);
  IF v_rows <> 1 THEN RAISE EXCEPTION 'auth marker cardinality mismatch'; END IF;

  SELECT u.id INTO v_locked_patient FROM public.users u
  WHERE u.id=v_patient AND u.auth_user_id=v_auth AND u.status='active'
    AND lower(u.email)=lower((SELECT au.email FROM auth.users au WHERE au.id=v_auth))
  FOR UPDATE;
  IF v_locked_patient IS DISTINCT FROM v_patient THEN
    RAISE EXCEPTION 'patient lock/predicate mismatch';
  END IF;

  IF v_event IS NULL THEN
    SELECT count(*) INTO v_rows FROM public.entitlement_events
    WHERE user_id=v_patient AND source='manual'
      AND source_reference=v_marker AND provider_event_id=v_marker||'-grant';
    IF v_rows <> 0 THEN RAISE EXCEPTION 'unexpected entitlement event'; END IF;
    SELECT count(*) INTO v_rows FROM public.user_entitlements
    WHERE user_id=v_patient AND source='manual'
      AND source_reference=v_marker AND entitlement_key='bodyflow_full';
    IF v_rows <> 0 THEN RAISE EXCEPTION 'unexpected entitlement'; END IF;
  ELSE
    DELETE FROM public.entitlement_events
    WHERE id=v_event AND entitlement_id=v_entitlement AND user_id=v_patient
      AND entitlement_key='bodyflow_full' AND source='manual'
      AND source_reference=v_marker AND provider_event_id=v_marker||'-grant'
      AND event_type='grant' AND environment='sandbox'
      AND processing_result='applied';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN RAISE EXCEPTION 'event delete cardinality mismatch'; END IF;

    DELETE FROM public.user_entitlements
    WHERE id=v_entitlement AND user_id=v_patient
      AND entitlement_key='bodyflow_full' AND source='manual'
      AND source_reference=v_marker AND status='active' AND plan='trial'
      AND environment='sandbox' AND last_provider_event_id=v_marker||'-grant'
      AND reason_code='ci3_synthetic_staging' AND actor_id=v_actor;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN RAISE EXCEPTION 'entitlement delete cardinality mismatch'; END IF;
  END IF;

  SELECT string_agg(cn.nspname||'.'||cc.relname||E'\t'||con.conname||E'\t'||
    pg_get_constraintdef(con.oid,true),E'\n'
    ORDER BY cn.nspname,cc.relname,con.conname)||E'\n'
  INTO v_stream
  FROM pg_constraint con JOIN pg_class pc ON pc.oid=con.confrelid
  JOIN pg_namespace pn ON pn.oid=pc.relnamespace
  JOIN pg_class cc ON cc.oid=con.conrelid
  JOIN pg_namespace cn ON cn.oid=cc.relnamespace
  WHERE con.contype='f' AND pn.nspname='public' AND pc.relname='users';
  IF encode(digest(convert_to(v_stream,'UTF8'),'sha256'),'hex') <>
    'a5fffce98a0c33f0fc4271de3e6c13a5993c12855da945074fa3ef87157a138f'
  THEN RAISE EXCEPTION 'inbound FK stream drift'; END IF;

  FOR v_fk IN
    SELECT cn.nspname child_schema,cc.relname child_table,a.attname child_column,
      con.conkey
    FROM pg_constraint con JOIN pg_class pc ON pc.oid=con.confrelid
    JOIN pg_namespace pn ON pn.oid=pc.relnamespace
    JOIN pg_class cc ON cc.oid=con.conrelid
    JOIN pg_namespace cn ON cn.oid=cc.relnamespace
    JOIN pg_attribute a ON a.attrelid=cc.oid AND a.attnum=con.conkey[1]
    WHERE con.contype='f' AND pn.nspname='public' AND pc.relname='users'
    ORDER BY cn.nspname,cc.relname,con.conname
  LOOP
    IF array_length(v_fk.conkey,1) <> 1 THEN
      RAISE EXCEPTION 'composite inbound FK is forbidden';
    END IF;
    v_fk_count := v_fk_count + 1;
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I=$1',
      v_fk.child_schema,v_fk.child_table,v_fk.child_column)
      INTO v_rows USING v_patient;
    IF v_fk.child_schema='public'
       AND v_fk.child_table IN ('user_profiles','user_progress') THEN
      IF v_rows <> 1 THEN RAISE EXCEPTION 'bootstrap child cardinality mismatch'; END IF;
    ELSIF v_rows <> 0 THEN
      RAISE EXCEPTION 'unexpected inbound child row';
    END IF;
  END LOOP;
  IF v_fk_count <> 43 THEN RAISE EXCEPTION 'inbound FK count mismatch'; END IF;

  DELETE FROM public.users u
  WHERE u.id=v_patient AND u.auth_user_id=v_auth AND u.status='active'
    AND lower(u.email)=lower((SELECT au.email FROM auth.users au WHERE au.id=v_auth));
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN RAISE EXCEPTION 'patient delete cardinality mismatch'; END IF;
END
$rollback$;
SELECT true AS rollback_applied;
COMMIT;
```

The parent patient row is locked `FOR UPDATE` before event deletion or child
counting, preventing a concurrent FK insert from entering between assertion
and delete. The loop is closed, not open-ended: the frozen FK digest must match
first, every one of the 43 FKs must be processed and any composite FK aborts;
the only allowed nonzero children after event/entitlement deletion are exactly one
profile and one progress row. `media_assets` and every other CASCADE,
SET-NULL or RESTRICT child must be zero. Any schema drift, unexpected child,
row-count mismatch or timeout aborts the transaction. The single optional
read-only settlement checks exact IDs/marker and publishes only booleans and
counts; it never changes data or authorizes another delete.

## 5. Synthetic identity and credentials

```text
EMAIL_PATTERN=ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>@example.invalid
OPERATION_MARKER_PATTERN=ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>
PROVIDER_EVENT_ID_PATTERN=<OPERATION_MARKER>-grant
SOURCE_REFERENCE_PATTERN=<OPERATION_MARKER>
PHONE=ABSENT
PASSWORD_MINIMUM_RANDOM_BYTES=32
CREDENTIAL_LIFETIME=CREATED_AT_PLUS_14_DAYS
```

There is no fallback domain. The exact e-mail is generated only in the future
execution, uses the RFC-reserved `.invalid` domain, and is stored only in the
credential file. No real name, e-mail, phone, image, audio or health data is
used. Invitation, confirmation-mail delivery, social identity, MFA, storage
objects and role/admin grants are prohibited.

Exact app metadata:

```text
synthetic=true
environment=staging
purpose=ci3_authenticated_today
schema_version=1
expires_at=<CREATED_AT_PLUS_14_DAYS>
```

Future files:

```text
CREDENTIAL_ROOT=/root/.config/agentempp/secrets
SYNTHETIC_OPERATION_CLAIM=/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.claim
SYNTHETIC_CREDENTIAL_FILE=/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json
SYNTHETIC_PROVISIONING_RECEIPT=/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.receipt.json
SYNTHETIC_RECOVERY_RECEIPT=/root/.config/agentempp/secrets/ci3-synthetic-patient.recovery.receipt.json
```

All are root-owned `0600`, regular, no symlink, link count one, under a `0700`
parent, created atomically/no-clobber with file and parent fsync. After the
read-only preflight, the process generates the operation UUID, actor UUID,
marker and timestamps in memory and only then acquires the operation claim
once with exclusive create. The claim binds those already-generated values;
an existing claim is a STOP, never an invitation to resume or overwrite. The credential
file contains only schema version, environment, project ref, synthetic marker,
raw synthetic e-mail/password, created/expiry times and
`cleanup_required=true`. It never contains Supabase keys, bearer tokens,
patient data or Preview origin. Receipts may contain raw IDs only because they
are root-only; neither password nor token may enter a receipt.

Access and refresh tokens are memory-only: never file, argv, env, receipt, log,
chat or diagnostic. They are discarded immediately after the bounded probes.

## 6. Frozen execution mechanism, order and budgets

Use the repository-resolved `@supabase/supabase-js` `2.105.1` from the exact
implementation SHA, Node `24.14.0`, invoked through Corepack/pnpm `10.33.2`.
Use one process, no shell tracing, one service/admin client and one patient client.
Both clients must set `persistSession=false`, `autoRefreshToken=false` and
`detectSessionInUrl=false`. The service/admin client is limited to Auth
preflight, `createUser`, Auth readback/rollback, the one exact
`apply_entitlement_event` RPC, `resolve_user_entitlement` and the specified
server-side readbacks; it may not mutate tables directly. The patient client
is used only for `signInWithPassword`. BFF requests use the in-memory patient bearer;
service role is never a patient bearer. No package or dependency update is
authorized.

Execution order:

1. fresh Git/worktree/Vercel/project-ref/schema/hash/inventory/no-clobber
   preflight;
2. generate identity/password/operation UUIDs and timestamps in memory, then
   acquire exactly one exclusive operation claim and atomically publish the
   credential file;
3. exactly one Auth Admin create plus exact readback;
4. exactly one patient sign-in;
5. exactly one authenticated `GET /api/mobile/v1/me`, then exact server-side
   patient/profile/progress readback;
6. exactly one `apply_entitlement_event` RPC and one exact DB/resolver readback;
7. exactly one authenticated `GET /api/mobile/v1/entitlements`;
8. exactly one authenticated `GET /api/mobile/v1/today`;
9. atomically publish the provisioning receipt, discard tokens and retain the
   fixture until the cleanup gate.

Budgets:

```text
AUTH_USER_CREATION_ATTEMPTS=1
PATIENT_SIGN_IN_ATTEMPTS=1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=1
PATIENT_PROFILE_MANUAL_CREATE_ATTEMPTS=0
ENTITLEMENT_CREATION_ATTEMPTS=1
ENTITLEMENT_READBACK_ATTEMPTS=1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=1
ROLLBACK_DATABASE_TRANSACTION_ATTEMPTS=1
AUTH_USER_DELETE_ROLLBACK_ATTEMPTS=1
PATIENT_DELETE_ROLLBACK_ATTEMPTS=1_IF_SCHEMA_PREDICATES_PASS
ENTITLEMENT_DELETE_ROLLBACK_ATTEMPTS=1_WITHIN_DATABASE_TRANSACTION
AUTH_CREATE_SETTLEMENT_READ_ATTEMPTS=1
ENTITLEMENT_CREATE_SETTLEMENT_READ_ATTEMPTS=1
ROLLBACK_SETTLEMENT_READ_ATTEMPTS=1
STORAGE_OBJECT_DELETE_ATTEMPTS=0
SECOND_AUTH_USER_CREATION=NO
SECOND_ENTITLEMENT_CREATION=NO
EXISTING_USER_MUTATION=NO
```

No second create, grant, sign-in, endpoint probe or mutation is authorized.

## 7. State machine, failure and recovery

```text
PRECONDITIONS_VERIFIED
CREDENTIAL_WRITTEN
AUTH_USER_CREATED
PATIENT_SESSION_ISSUED
PATIENT_BOOTSTRAPPED
ENTITLEMENT_CREATED
ENTITLEMENT_VERIFIED
TODAY_VERIFIED
ROLLBACK_REQUIRED
ROLLBACK_PARTIAL
PRESERVED_FOR_DIAGNOSIS
```

- From `CREDENTIAL_WRITTEN`, a definitive pre-create local failure first
  atomically publishes a sanitized recovery receipt, then removes only this
  operation's credential and fsyncs the parent. The claim remains as a durable
  no-clobber guard until separately authorized recovery. A `createUser`
  transport/timeout ambiguity permits exactly one read-only
  `auth.admin.listUsers({page:1,perPage:1000})` settlement after the initially
  empty inventory, matching exact generated e-mail plus metadata marker.
  Exactly one matching row and total Auth cardinality one advances to
  `AUTH_USER_CREATED`; zero, multiple, unavailable or ambiguous results preserve
  claim and credential, record `PRESERVED_FOR_DIAGNOSIS` and stop because the
  create could complete late. A definitive server rejection plus a zero-row
  settlement publishes recovery first, then removes only credential; claim is
  retained. There is never a second create.
- Before `PATIENT_BOOTSTRAPPED`, a settled failure after Auth creation requires
  proof of zero storage/profile/entitlement, one exact Auth delete, removal only
  of this operation's credential only after durable publication of a sanitized
  recovery receipt. The claim is retained for separate recovery.
- After bootstrap and before entitlement, rollback is allowed only when the
  frozen FK/cardinality predicates pass: one exact DB transaction, then one
  exact Auth delete, then durable recovery receipt and exact credential
  removal. The claim is retained for separate recovery.
- After entitlement creation, if Auth, patient and entitlement are
  structurally valid and only later bearer validation or a probe fails, use
  `PRESERVED_FOR_DIAGNOSIS`; do not auto-delete or recreate the fixture.
- A timeout/transport ambiguity from `apply_entitlement_event` permits exactly
  one read-only settlement for the exact marker/event/entitlement plus resolver.
  An exact `applied` pair may advance; zero, `duplicate`, `stale`, mismatched or
  unavailable settlement is `PRESERVED_FOR_DIAGNOSIS`. It may complete late,
  so no database/Auth rollback, credential removal, claim release or second
  grant is permitted in that branch.
- A partial or invalid entitlement may use the exact bounded DB rollback, then
  patient/Auth rollback only when safe, followed by durable recovery receipt
  and exact credential removal. The claim remains. One attempt per object; no
  mass delete.
- Any rollback failure becomes `ROLLBACK_PARTIAL`; preserve hashed IDs and
  state only in the root-only recovery receipt and stop without another try.
- After `TODAY_VERIFIED`, do not roll back. Preserve the fixture for CI-3 and
  reserve cleanup to a later explicitly authorized operation.

The cleanup deadline is exactly `CREATED_AT_PLUS_14_DAYS`. A later, separately
authorized cleanup must revoke/delete the exact entitlement event and
entitlement, delete the exact synthetic patient and then the exact Auth user in
the frozen order; after verified deletion it removes the exact credential and
claim with no-follow/cardinality checks and parent fsync. The password-bearing
credential may never survive the deadline. The provisioning receipt is retained
root-only as sanitized audit evidence; any recovery receipt is retained until
its separately authorized diagnosis/resolution, then superseded by a sanitized
cleanup receipt. This authority documents but does not execute or pre-authorize
that cleanup.

## 8. Probe acceptance

`GET /me` must return HTTP 200, no-store, Vary Authorization, request ID,
API-v1 envelope, consistent active patient/Auth identity and no PII in output.

`GET /entitlements` must return HTTP 200, an active decision for
`bodyflow_full`, no-store, Vary Authorization and request ID. Billing provider
may remain unavailable as defined by the source contract.

`GET /today` runs once and passes only with:

- HTTP 200 and JSON;
- `Cache-Control` including `no-store`;
- `Vary` including `Authorization`;
- `X-Request-Id` present and equal to envelope `meta.request_id`;
- envelope `meta.api_version=v1`, a `data` object and no error;
- non-empty `data.local_date` and `data.calculation_version`;
- `data.sources` and `data.completion_status` present;
- `data.targets.source`, `data.consumed.source` and `block_7700.source` when
  their corresponding structures apply;
- no provider ID, token or PII reflected, and all official values from backend.

The response body is never printed or persisted. Record only assertions and a
canonical structural SHA-256.

## 9. Security, logs and hard prohibitions

Allowed output is limited to operation/status, HTTP status, request ID, counts,
booleans, sanitized error code, definition/receipt hashes and hashes of IDs.
Raw e-mail, password, access/refresh token, Authorization, anon/service-role
value, user/patient/entitlement ID, Preview origin, response body and health
data are prohibited. Do not use shell tracing, `env`, `printenv`, `set`,
`declare -p`, `ps e` or verbose HTTP output.

The future operation may not change Vercel, deployments, SSO, envs, project
settings, domains or aliases; may not open primary/live; may not touch product
Production; may not start CI-4; and may not use a service-role bearer as the
patient token. CI-3 is not started until the future operation completes and a
separate CI-3 authorization is published.

## 10. Independent review gates

Publication requires two independent reviews:

- Review A: project identity, Auth create/read/delete, confirmation,
  bootstrap, account separation, patient status, exact entitlement RPC/key,
  RLS/grants, fresh-Today prerequisites and FK rollback;
- Review B: synthetic identity, credential physics, memory-only bearer,
  admin/patient separation, no-clobber, budgets, recovery receipts, headers,
  envelope, 14-day cleanup and zero Vercel/primary/live/CI-4 mutation.

Both must report zero Critical and zero Important. A finding affecting
identity, entitlement, rollback, security or acceptance blocks publication.

## 11. Integral next-operation handoff

```text
OPERATION=EXECUTE_SYNTHETIC_STAGING_PATIENT_PROVISIONING_AND_AUTHENTICATED_TODAY
NEXT_ENVIRONMENT=VPS

AUTHORING_ONLY_IS_COMPLETE=YES
DO_NOT_REAUTHOR_OR_REUSE_OLD_PROMPTS=YES

AUTHORITY_BRANCH=codex/better-ahead-rebranding-design
AUTHORITY_SHA=<PUBLISHED_AUTHORITY_SHA>
AUTHORITY_PARENT=34636d321d5d5fa2d108a88ffda2dc2a7072de90
AUTHORITY_TREE=<PUBLISHED_AUTHORITY_TREE>
AUTHORITY_SUBJECT=docs(staging): authorize synthetic patient provisioning
AUTHORITY_DOCUMENT_1=docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
AUTHORITY_DOCUMENT_2=docs/superpowers/evidence/2026-08-27-ci3-synthetic-staging-patient-provisioning-authority.md
AUTHORITY_DOCUMENT_3=docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
AUTHORITY_DOCUMENT_HASHES=<READ_FROM_PUBLISHED_COMMIT>

IMPLEMENTATION_SHA=e3e1e252b48e42554e75899b950692c05186f60d
IMPLEMENTATION_TREE=a167a6663cb1e476975742bcec51c7207dbcbc26
STAGING_PROJECT_REF=xitugspwfxkcluxvrdeg
DEPLOYMENT_RECEIPT=/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json
DEPLOYMENT_RECEIPT_SHA256=f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6

SOURCE_CONTRACT_STREAM_SHA256=0540cb5ed3bdc903dd5feda1499fed0eb5fe5b6197c0365f09c19596d6ac44bf
BOOTSTRAP_FUNCTION_SHA256=94a5de8bc0126fbbc03d1879efaa1a03f6333cb53acc6e9c97362275e679f0ab
PATIENT_SCHEMA_EXECUTION_GATE_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
ENTITLEMENT_SOURCE_FUNCTION_SHA256=797feb1288d91e195dd86f7c878c9b87a6f6577d14b19e9cace31b4e42ba68e3
ENTITLEMENT_RESOLUTION_SHA256=c25d2d1218c0952d26215f7cef57b0f57c3f713ff8c25d8aa33c3771398ececc
TODAY_RELATIONS_AUTHORING_EVIDENCE_SHA256=af34e74b68050e264930df866e9094372261c23e684e85d2507830477381c903
TODAY_FUNCTIONS_AUTHORING_EVIDENCE_SHA256=ee15dcc08e3b767c13f2acfe395c9566ebced1d33127d7471b06eb58f5adfc89
SCHEMA_GATE_V1_ROWS=533
SCHEMA_GATE_V1_BYTES=110927
SCHEMA_GATE_V1_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
PUBLIC_USERS_INBOUND_FK_COUNT=43
PUBLIC_USERS_INBOUND_FK_STREAM_SHA256=a5fffce98a0c33f0fc4271de3e6c13a5993c12855da945074fa3ef87157a138f
HASH_RECIPES=AUTHORITY_DOCUMENT_2_SECTIONS_3_AND_4

CREDENTIAL_FILE=/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json
OPERATION_CLAIM=/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.claim
PROVISIONING_RECEIPT=/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.receipt.json
RECOVERY_RECEIPT=/root/.config/agentempp/secrets/ci3-synthetic-patient.recovery.receipt.json
TOOLCHAIN=node@24.14.0,corepack-pnpm@10.33.2,@supabase/supabase-js@2.105.1

EXECUTION_ORDER=PREFLIGHT,IDENTIFIERS_AND_CLAIM,CREDENTIAL,AUTH_CREATE_AND_SETTLEMENT,SIGN_IN,ME_BOOTSTRAP,ENTITLEMENT_GRANT_APPLIED_ONLY,ENTITLEMENT_READBACK,ENTITLEMENTS_PROBE,TODAY_PROBE,RECEIPT
AUTH_USER_CREATION_ATTEMPTS=1
PATIENT_SIGN_IN_ATTEMPTS=1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=1
PATIENT_PROFILE_MANUAL_CREATE_ATTEMPTS=0
ENTITLEMENT_CREATION_ATTEMPTS=1
ENTITLEMENT_READBACK_ATTEMPTS=1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=1
ROLLBACK_DATABASE_TRANSACTION_ATTEMPTS=1
AUTH_USER_DELETE_ROLLBACK_ATTEMPTS=1
PATIENT_DELETE_ROLLBACK_ATTEMPTS=1_IF_SCHEMA_PREDICATES_PASS
ENTITLEMENT_DELETE_ROLLBACK_ATTEMPTS=1_WITHIN_DATABASE_TRANSACTION
AUTH_CREATE_SETTLEMENT_READ_ATTEMPTS=1
ENTITLEMENT_CREATE_SETTLEMENT_READ_ATTEMPTS=1
ROLLBACK_SETTLEMENT_READ_ATTEMPTS=1
STORAGE_OBJECT_DELETE_ATTEMPTS=0
SECOND_AUTH_USER_CREATION=NO
SECOND_ENTITLEMENT_CREATION=NO
SECOND_SIGN_IN=NO
SECOND_ENDPOINT_PROBE=NO
EXISTING_USER_MUTATION=NO

EMAIL_PATTERN=ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>@example.invalid
OPERATION_MARKER_PATTERN=ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>
PROVIDER_EVENT_ID_PATTERN=<OPERATION_MARKER>-grant
SOURCE_REFERENCE_PATTERN=<OPERATION_MARKER>
ENTITLEMENT_KEY=bodyflow_full
ENTITLEMENT_STATUS=active
ENTITLEMENT_SOURCE=manual
ENTITLEMENT_PLAN=trial
ENTITLEMENT_ENVIRONMENT=sandbox
ENTITLEMENT_EVENT_TYPE=grant
ENTITLEMENT_REASON=ci3_synthetic_staging
ENTITLEMENT_ACTOR=one receipt-bound operation UUID
ENTITLEMENT_OCCURRED_AT=GRANT_AT
ENTITLEMENT_STARTS_AT=GRANT_AT
ENTITLEMENT_ACCESS_EXPIRES_AT=CREATED_AT_PLUS_14_DAYS
ENTITLEMENT_GRACE_EXPIRES_AT=NULL
ENTITLEMENT_CANCEL_AT_PERIOD_END=false
ENTITLEMENT_RPC_ACCEPTANCE=result=applied,exact event ID,exact entitlement ID
CLEANUP_DEADLINE=CREATED_AT_PLUS_14_DAYS

STATE_MACHINE=PRECONDITIONS_VERIFIED,CREDENTIAL_WRITTEN,AUTH_USER_CREATED,PATIENT_SESSION_ISSUED,PATIENT_BOOTSTRAPPED,ENTITLEMENT_CREATED,ENTITLEMENT_VERIFIED,TODAY_VERIFIED,ROLLBACK_REQUIRED,ROLLBACK_PARTIAL,PRESERVED_FOR_DIAGNOSIS
ROLLBACK_ORDER=EXACT_EVENT,EXACT_ENTITLEMENT,EXACT_PATIENT,EXACT_AUTH_USER
ROLLBACK_TRANSPORT=mcp__codex_apps__supabase_execute_sql
ROLLBACK_PROJECT=xitugspwfxkcluxvrdeg
ROLLBACK_TEMPLATE=AUTHORITY_DOCUMENT_2_ROLLBACK_SQL_V1
ROLLBACK_HELPER_VERSION=ROLLBACK_SQL_V1@AUTHORITY_SHA
ROLLBACK_MUTATION_ATTEMPTS=1_NO_CLIENT_RETRY
ROLLBACK_FK_GATE=43_ROWS,a5fffce98a0c33f0fc4271de3e6c13a5993c12855da945074fa3ef87157a138f
ROLLBACK_ALLOWED_CHILDREN=user_profiles:1,user_progress:1,all_others:0
VALID_FIXTURE_PROBE_FAILURE=PRESERVED_FOR_DIAGNOSIS
AMBIGUOUS_AUTH_CREATE=PRESERVE_CLAIM_AND_CREDENTIAL_NO_DELETE
AMBIGUOUS_ENTITLEMENT_GRANT=PRESERVE_FIXTURE_CLAIM_AND_CREDENTIAL_NO_ROLLBACK
FAILED_ROLLBACK_ARTIFACT_ORDER=KEEP_CLAIM,PUBLISH_RECOVERY_RECEIPT,REMOVE_CREDENTIAL_IF_SAFE
TODAY_VERIFIED_ROLLBACK=FORBIDDEN
CLEANUP_REQUIRES_SEPARATE_AUTHORITY=YES
CLEANUP_ORDER=EXACT_EVENT,EXACT_ENTITLEMENT,EXACT_PATIENT,EXACT_AUTH_USER,CREDENTIAL,CLAIM
CREDENTIAL_MUST_BE_REMOVED_BY=CREATED_AT_PLUS_14_DAYS
PROVISIONING_RECEIPT_RETENTION=ROOT_ONLY_SANITIZED_AUDIT
RECOVERY_RECEIPT_RETENTION=UNTIL_SEPARATELY_AUTHORIZED_RESOLUTION

TODAY_ACCEPTANCE=HTTP_200,JSON,NO_STORE,VARY_AUTHORIZATION,REQUEST_ID_MATCH,API_V1,DATA_OBJECT,LOCAL_DATE,CALCULATION_VERSION,SOURCES,COMPLETION_STATUS,SOURCE_PROVENANCE,NO_RAW_BODY
VERCEL_WRITE=NO
PRIMARY_LIVE_OPEN=NO
PRODUCT_PRODUCTION_WRITE=NO
CI4_STARTED=NO
RAW_PII_OR_SECRET_OUTPUT=NO

Run the published authority exactly once. Before writing, validate the
reproducible source stream, individual function hashes, `SCHEMA_GATE_V1`, the
inbound-FK stream and every empty-state precondition; the three explicitly
named authoring-evidence bundle hashes are historical evidence, not execution
inputs. If the reserved domain is rejected, if any executable
schema/function hash drifts, or if any marker/file/identity exists, stop without
a second create. Do not execute CI-4. Do not mutate Vercel or primary/live.

On success print only sanitized markers including:
SYNTHETIC_PATIENT_PROVISIONING_STATUS=PASS
AUTHENTICATED_TODAY_STATUS=PASS
SYNTHETIC_PATIENT_PATH=VERIFIED
CLEANUP_REQUIRED=YES
CLEANUP_DEADLINE_CLASS=CREATED_AT_PLUS_14_DAYS
RAW_PII_REPORTED=NO
RAW_SECRET_REPORTED=NO
NEXT_GATE=AUTHORIZE_CI3_TODAY_STAGING_VERTICAL_SLICE

On failure print a sanitized terminal state, attempts actually consumed,
recovery classification and the exact next gate. Never print raw IDs, identity,
credential, token, origin or response body.
```

This handoff is part of the published authority. It must not be executed during
the authoring operation.

## 12. Authoring-only external action ledger

```text
AUTH_USER_CREATED=NO
PROFILE_CREATED=NO
ENTITLEMENT_CREATED=NO
CREDENTIAL_ISSUED=NO
TOKEN_ISSUED=NO
AUTHENTICATED_TODAY_PROBE=NO
VERCEL_WRITE=NO
SUPABASE_WRITE=NO
DATABASE_WRITE=NO
PRODUCTION=NO
CI3_STARTED=NO
CI4_STARTED=NO
PRIMARY_LIVE_OPENED=NO
```

-- Keep the INVOKER pending guard usable by a fresh service backend without
-- granting schema-private access. Preserve the boolean capability's OID/ACL.
BEGIN;
SET LOCAL search_path=pg_catalog;

DO $visibility$
DECLARE
  helper oid:=to_regprocedure('private.mobile_workout_registration_pending_is_protected(uuid,uuid)');
  guard oid:=to_regprocedure('private.guard_mobile_workout_registration()');
  old_namespace oid:=to_regnamespace('private');
  new_namespace oid:=to_regnamespace('public');
  helper_before jsonb;
  guard_before jsonb;
  namespaces_before jsonb;
  dependencies_before jsonb;
  dependencies_expected jsonb;
  dependencies_after jsonb;
  old_token text:='private.mobile_workout_registration_pending_is_protected(';
  new_token text:='public.mobile_workout_registration_pending_is_protected(';
  new_source text;
BEGIN
  IF CURRENT_USER<>'postgres' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF helper IS NULL OR guard IS NULL OR old_namespace IS NULL OR new_namespace IS NULL
    OR EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace=new_namespace
      AND proname='mobile_workout_registration_pending_is_protected') THEN
    RAISE EXCEPTION 'mobile_workout_registration_visibility_identity_drift' USING ERRCODE='55000';
  END IF;
  SELECT to_jsonb(p) INTO STRICT helper_before FROM pg_proc p WHERE oid=helper;
  SELECT to_jsonb(p) INTO STRICT guard_before FROM pg_proc p WHERE oid=guard;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE oid=helper AND proowner='postgres'::regrole
      AND prolang=(SELECT oid FROM pg_language WHERE lanname='sql')
      AND prokind='f' AND prosecdef AND provolatile='s' AND prorettype='boolean'::regtype
      AND pronargs=2 AND proargtypes[0]='uuid'::regtype AND proargtypes[1]='uuid'::regtype
      AND proargdefaults IS NULL
      AND proconfig=ARRAY['search_path=pg_catalog']
      AND md5(prosrc)='f15ab7a6b57938e38ab369d93b732300')
    OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE oid=guard AND proowner='postgres'::regrole
      AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql')
      AND prokind='f' AND NOT prosecdef AND provolatile='v' AND prorettype='trigger'::regtype
      AND pronargs=0 AND proargdefaults IS NULL AND proconfig=ARRAY['search_path=pg_catalog']
      AND md5(prosrc)='31c368e9abd3a85b393d68229073123b') THEN
    RAISE EXCEPTION 'mobile_workout_registration_visibility_source_drift' USING ERRCODE='55000';
  END IF;
  -- Preserve the exact existing ACL capability, including denial to client roles.
  IF EXISTS (
    WITH actual AS (
      SELECT p.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM pg_proc p CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
      WHERE p.oid IN(helper,guard)
    ), expected AS (
      SELECT p.oid,'postgres'::regrole::oid AS grantor,'postgres'::regrole::oid AS grantee,
        'EXECUTE'::text AS privilege_type,false AS is_grantable FROM pg_proc p WHERE p.oid IN(helper,guard)
      UNION ALL SELECT helper,'postgres'::regrole::oid,'service_role'::regrole::oid,'EXECUTE',false
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    ) SELECT 1 FROM differences
  ) OR NOT has_schema_privilege('service_role',new_namespace,'USAGE')
    OR NOT has_function_privilege('service_role',helper,'EXECUTE')
    OR has_function_privilege('anon',helper,'EXECUTE')
    OR has_function_privilege('authenticated',helper,'EXECUTE') THEN
    RAISE EXCEPTION 'mobile_workout_registration_visibility_acl_drift' USING ERRCODE='42501';
  END IF;
  IF (length(guard_before->>'prosrc')-length(replace(guard_before->>'prosrc',old_token,'')))
      <>3*length(old_token) THEN
    RAISE EXCEPTION 'mobile_workout_registration_visibility_call_count' USING ERRCODE='55000';
  END IF;
  new_source:=replace(guard_before->>'prosrc',old_token,new_token);
  SELECT jsonb_agg(to_jsonb(n) ORDER BY n.oid) INTO namespaces_before
    FROM pg_namespace n WHERE oid IN(old_namespace,new_namespace);
  SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY to_jsonb(d)::text),'[]'::jsonb)
    INTO dependencies_before FROM pg_depend d WHERE classid='pg_proc'::regclass AND objid IN(helper,guard);
  IF (SELECT count(*) FROM pg_depend WHERE classid='pg_proc'::regclass AND objid=helper
      AND objsubid=0 AND refclassid='pg_namespace'::regclass AND refobjid=old_namespace
      AND refobjsubid=0 AND deptype='n')<>1 THEN
    RAISE EXCEPTION 'mobile_workout_registration_visibility_dependency_drift' USING ERRCODE='55000';
  END IF;
  SELECT jsonb_agg(v ORDER BY v::text) INTO dependencies_expected FROM (
    SELECT CASE WHEN (d->>'classid')::oid='pg_proc'::regclass AND (d->>'objid')::oid=helper
      AND (d->>'objsubid')::integer=0 AND (d->>'refclassid')::oid='pg_namespace'::regclass
      AND (d->>'refobjid')::oid=old_namespace AND (d->>'refobjsubid')::integer=0 AND d->>'deptype'='n'
      THEN jsonb_set(d,'{refobjid}',to_jsonb(new_namespace)) ELSE d END AS v
    FROM jsonb_array_elements(dependencies_before) d
  ) expected_dependencies;

  ALTER FUNCTION private.mobile_workout_registration_pending_is_protected(uuid,uuid) SET SCHEMA public;
  EXECUTE format('CREATE OR REPLACE FUNCTION private.guard_mobile_workout_registration() RETURNS trigger '
    'LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS %L',new_source);

  SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY to_jsonb(d)::text),'[]'::jsonb)
    INTO dependencies_after FROM pg_depend d WHERE classid='pg_proc'::regclass AND objid IN(helper,guard);
  IF to_regprocedure('private.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NOT NULL
    OR to_regprocedure('public.mobile_workout_registration_pending_is_protected(uuid,uuid)')::oid IS DISTINCT FROM helper
    OR (SELECT to_jsonb(p) FROM pg_proc p WHERE oid=helper) IS DISTINCT FROM
      jsonb_set(helper_before,'{pronamespace}',to_jsonb(new_namespace))
    OR (SELECT to_jsonb(p) FROM pg_proc p WHERE oid=guard) IS DISTINCT FROM
      jsonb_set(guard_before,'{prosrc}',to_jsonb(new_source))
    OR (SELECT jsonb_agg(to_jsonb(n) ORDER BY n.oid) FROM pg_namespace n WHERE oid IN(old_namespace,new_namespace))
      IS DISTINCT FROM namespaces_before
    OR dependencies_after IS DISTINCT FROM dependencies_expected
    OR NOT has_schema_privilege('service_role',new_namespace,'USAGE') THEN
    RAISE EXCEPTION 'mobile_workout_registration_visibility_unexpected_delta' USING ERRCODE='55000';
  END IF;
END $visibility$;
COMMIT;

-- Reset isolation regression: real RPCs, error priorities and explicit RC fence.
-- Three native isolation transactions, all ROLLBACK; no fixture/product DDL/auth mocks.
-- Run only in an authorized isolated local test DB after the candidate migration.
-- RC preserve/keep/remove/inactive/atomicity remain in strength_week_reset_closure.sql (32).
-- Native contention/non-wait proof is separate in the reviewed eight-lock Actor driver.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';
SET LOCAL standard_conforming_strings=on;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $fence_test$
DECLARE u uuid:='c59f2600-0000-0000-0000-000000000701'::uuid;c record;s text;m text;r jsonb;
BEGIN
  IF current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_WRONG_ISOLATION:RC'; END IF;
  IF NOT has_function_privilege(current_user,'public.reset_user_conversation_atomic(uuid,boolean)','EXECUTE')
    OR NOT has_function_privilege(current_user,'public.reset_user_conversation_atomic(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_RPC_EXECUTE_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_SYNTHETIC_UUID_COLLISION'; END IF;
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_SERVICE_CLAIMS_REQUIRED'; END IF;

  FOR c IN SELECT * FROM (VALUES
      ('NULL-owner','SELECT public.reset_user_conversation_atomic(NULL::uuid,true)'),
      ('NULL-keep','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,NULL::boolean)'),
      ('NULL-both','SELECT public.reset_user_conversation_atomic(NULL::uuid,NULL::boolean)'),
      ('NULL-owner-wrapper','SELECT public.reset_user_conversation_atomic(NULL::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '22023' OR m IS DISTINCT FROM 'invalid reset request' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:RC/trusted/% expected NULL22023, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:RC/trusted/%',c.label;
  END LOOP;

  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  IF auth.jwt()->>'role' IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_UNTRUSTED_CLAIMS_REQUIRED'; END IF;
  FOR c IN SELECT * FROM (VALUES
      ('valid-direct','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,true)'),
      ('NULL-owner','SELECT public.reset_user_conversation_atomic(NULL::uuid,true)'),
      ('NULL-keep','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,NULL::boolean)'),
      ('NULL-both','SELECT public.reset_user_conversation_atomic(NULL::uuid,NULL::boolean)'),
      ('valid-wrapper','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid)'),
      ('NULL-owner-wrapper','SELECT public.reset_user_conversation_atomic(NULL::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '42501' OR m IS DISTINCT FROM 'trusted backend role required' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:RC/untrusted/% expected trust42501, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:RC/untrusted/%',c.label;
  END LOOP;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_SERVICE_CLAIMS_NOT_RESTORED'; END IF;
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_SYNTHETIC_UUID_CREATED'; END IF;
END $fence_test$;
ROLLBACK;
\echo RC_FENCE_RC_ROLLBACK_RETURNED

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';
SET LOCAL standard_conforming_strings=on;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $fence_test$
DECLARE u uuid:='c59f2600-0000-0000-0000-000000000701'::uuid;c record;s text;m text;r jsonb;
BEGIN
  IF current_setting('transaction_isolation')<>'repeatable read' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_WRONG_ISOLATION:RR'; END IF;
  IF NOT has_function_privilege(current_user,'public.reset_user_conversation_atomic(uuid,boolean)','EXECUTE')
    OR NOT has_function_privilege(current_user,'public.reset_user_conversation_atomic(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_RPC_EXECUTE_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_SYNTHETIC_UUID_COLLISION'; END IF;
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_SERVICE_CLAIMS_REQUIRED'; END IF;

  FOR c IN SELECT * FROM (VALUES
      ('NULL-owner','SELECT public.reset_user_conversation_atomic(NULL::uuid,true)'),
      ('NULL-keep','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,NULL::boolean)'),
      ('NULL-both','SELECT public.reset_user_conversation_atomic(NULL::uuid,NULL::boolean)'),
      ('NULL-owner-wrapper','SELECT public.reset_user_conversation_atomic(NULL::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '22023' OR m IS DISTINCT FROM 'invalid reset request' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:RR/trusted/% expected NULL22023, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:RR/trusted/%',c.label;
  END LOOP;

  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  IF auth.jwt()->>'role' IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_UNTRUSTED_CLAIMS_REQUIRED'; END IF;
  FOR c IN SELECT * FROM (VALUES
      ('valid-direct','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,true)'),
      ('NULL-owner','SELECT public.reset_user_conversation_atomic(NULL::uuid,true)'),
      ('NULL-keep','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,NULL::boolean)'),
      ('NULL-both','SELECT public.reset_user_conversation_atomic(NULL::uuid,NULL::boolean)'),
      ('valid-wrapper','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid)'),
      ('NULL-owner-wrapper','SELECT public.reset_user_conversation_atomic(NULL::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '42501' OR m IS DISTINCT FROM 'trusted backend role required' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:RR/untrusted/% expected trust42501, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:RR/untrusted/%',c.label;
  END LOOP;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_SERVICE_CLAIMS_NOT_RESTORED'; END IF;

  -- The UUID does not exist: the exact fence must precede the owner lookup.
  FOR c IN SELECT * FROM (VALUES
      ('valid-direct','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,true)'),
      ('valid-wrapper','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '22023' OR m IS DISTINCT FROM 'reset_user_conversation_requires_read_committed' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:RR/fence/% expected explicit fence22023, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:RR/fence/%',c.label;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_SYNTHETIC_UUID_CREATED'; END IF;
END $fence_test$;
ROLLBACK;
\echo RC_FENCE_RR_ROLLBACK_RETURNED

BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';
SET LOCAL standard_conforming_strings=on;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $fence_test$
DECLARE u uuid:='c59f2600-0000-0000-0000-000000000701'::uuid;c record;s text;m text;r jsonb;
BEGIN
  IF current_setting('transaction_isolation')<>'serializable' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_WRONG_ISOLATION:SERIALIZABLE'; END IF;
  IF NOT has_function_privilege(current_user,'public.reset_user_conversation_atomic(uuid,boolean)','EXECUTE')
    OR NOT has_function_privilege(current_user,'public.reset_user_conversation_atomic(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_RPC_EXECUTE_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_SYNTHETIC_UUID_COLLISION'; END IF;
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_SERVICE_CLAIMS_REQUIRED'; END IF;

  FOR c IN SELECT * FROM (VALUES
      ('NULL-owner','SELECT public.reset_user_conversation_atomic(NULL::uuid,true)'),
      ('NULL-keep','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,NULL::boolean)'),
      ('NULL-both','SELECT public.reset_user_conversation_atomic(NULL::uuid,NULL::boolean)'),
      ('NULL-owner-wrapper','SELECT public.reset_user_conversation_atomic(NULL::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '22023' OR m IS DISTINCT FROM 'invalid reset request' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:SERIALIZABLE/trusted/% expected NULL22023, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:SERIALIZABLE/trusted/%',c.label;
  END LOOP;

  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  IF auth.jwt()->>'role' IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_UNTRUSTED_CLAIMS_REQUIRED'; END IF;
  FOR c IN SELECT * FROM (VALUES
      ('valid-direct','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,true)'),
      ('NULL-owner','SELECT public.reset_user_conversation_atomic(NULL::uuid,true)'),
      ('NULL-keep','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,NULL::boolean)'),
      ('NULL-both','SELECT public.reset_user_conversation_atomic(NULL::uuid,NULL::boolean)'),
      ('valid-wrapper','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid)'),
      ('NULL-owner-wrapper','SELECT public.reset_user_conversation_atomic(NULL::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '42501' OR m IS DISTINCT FROM 'trusted backend role required' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:SERIALIZABLE/untrusted/% expected trust42501, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:SERIALIZABLE/untrusted/%',c.label;
  END LOOP;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_REAL_SERVICE_CLAIMS_NOT_RESTORED'; END IF;

  -- The UUID does not exist: the exact fence must precede the owner lookup.
  FOR c IN SELECT * FROM (VALUES
      ('valid-direct','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid,true)'),
      ('valid-wrapper','SELECT public.reset_user_conversation_atomic(''c59f2600-0000-0000-0000-000000000701''::uuid)')
    ) x(label,statement) LOOP
    s:=NULL;m:=NULL;
    BEGIN EXECUTE c.statement INTO r;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    END;
    IF s IS DISTINCT FROM '22023' OR m IS DISTINCT FROM 'reset_user_conversation_requires_read_committed' THEN
      RAISE EXCEPTION 'RC_FENCE_TEST:SERIALIZABLE/fence/% expected explicit fence22023, got % %',c.label,s,m; END IF;
    RAISE NOTICE 'RC_FENCE_PASS:SERIALIZABLE/fence/%',c.label;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN
    RAISE EXCEPTION 'RC_FENCE_TEST_SYNTHETIC_UUID_CREATED'; END IF;
END $fence_test$;
ROLLBACK;
\echo RC_FENCE_SERIALIZABLE_ROLLBACK_RETURNED

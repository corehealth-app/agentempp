\set ON_ERROR_STOP on
-- Owned native schema204/205 only. No account creation, COMMIT, sequence allocation,
-- canonical completion or HTTP claim. The runner supplies existing synthetic owners.
\if :{?p12e_data_directory}
\else
  \quit 3
\endif
\if :{?p12e_owner_a}
\else
  \quit 3
\endif
\if :{?p12e_owner_b}
\else
  \quit 3
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout = '40s';
SET LOCAL lock_timeout = '5s';
SELECT set_config('p12e.data_directory', :'p12e_data_directory', true),
  set_config('p12e.owner_a', :'p12e_owner_a', true),
  set_config('p12e.owner_b', :'p12e_owner_b', true);
DO $target$
BEGIN
  IF current_user <> 'postgres' OR session_user <> 'postgres'
    OR current_database() <> 'postgres' OR current_setting('server_version_num') <> '170011'
    OR inet_server_addr() IS NOT NULL OR current_setting('listen_addresses') <> ''
    OR current_setting('data_directory') <> current_setting('p12e.data_directory')
    OR current_setting('data_directory') NOT LIKE
      '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/M3-protocols-resume-20261019/C59c-sql-next-preflight-r1/ACCEPTED-PLAN-PREPARATION-R1/P11-BFF-INVENTORY-R1/P12-LOCAL-INTEGRATION-R1/runtime-home/stacks/6d5dda98c7e6e074034eac19203bc8143acd8072806bc2218275f6eb07f345d4/data/%/data'
    OR current_setting('cron.launch_active_jobs') <> 'off'
    OR current_setting('pg_net.batch_size') <> '0'
    OR (SELECT count(*) FROM auth.users) <> 2
    OR (SELECT count(*) FROM public.users) <> 2
    OR current_setting('p12e.owner_a') = current_setting('p12e.owner_b')
    OR (SELECT count(*) FROM public.users WHERE id IN (
      current_setting('p12e.owner_a')::uuid, current_setting('p12e.owner_b')::uuid)
      AND status = 'active') <> 2 THEN
    RAISE EXCEPTION 'P12E_SETUP_WRONG_OWNED_LOCAL_TARGET';
  END IF;
  IF to_regprocedure('public.begin_mobile_signup_completion_intent(uuid,uuid)') IS NULL
    OR to_regprocedure('public.resolve_mobile_signup_completion_intent(uuid,uuid)') IS NULL
    OR to_regprocedure('public.verify_mobile_signup_completion_intent(uuid,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'P12E_SETUP_NEW_RPC_ABSENT';
  END IF;
END $target$;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';

CREATE FUNCTION pg_temp.p12e_ok(value boolean, label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'P12E_ASSERT:%', label; END IF;
  RAISE NOTICE 'P12E_PASS:%', label;
END $$;
CREATE FUNCTION pg_temp.p12e_state() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE relation record; rows jsonb; result jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT n.nspname, c.relname FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM ONLY %I.%I r',
      relation.nspname,relation.relname) INTO rows;
    result := result || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
  END LOOP;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION pg_temp.p12e_ok(boolean,text), pg_temp.p12e_state()
  FROM PUBLIC,anon,authenticated,service_role;

DO $schema$
DECLARE valid boolean;
BEGIN
  SELECT c.relowner='postgres'::regrole AND c.relrowsecurity AND NOT c.relforcerowsecurity
    AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid=c.oid)
    AND NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE a.grantee<>c.relowner)
    INTO valid FROM pg_class c WHERE c.oid='private.mobile_signup_completion_intents'::regclass;
  PERFORM pg_temp.p12e_ok(valid,'owner_only_private_RLS_no_policy');
  SELECT count(*)=3 AND bool_and(p.proowner='postgres'::regrole AND p.prosecdef
    AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.pronargdefaults=0
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
    AND NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE a.grantee NOT IN (p.proowner,'service_role'::regrole))) INTO valid
    FROM pg_proc p WHERE p.oid IN (
      'public.begin_mobile_signup_completion_intent(uuid,uuid)'::regprocedure,
      'public.resolve_mobile_signup_completion_intent(uuid,uuid)'::regprocedure,
      'public.verify_mobile_signup_completion_intent(uuid,uuid,text)'::regprocedure);
  PERFORM pg_temp.p12e_ok(valid,'three_service_only_fixed_path_RPCs');
END $schema$;

DO $contract$
DECLARE
  a uuid := current_setting('p12e.owner_a')::uuid;
  b uuid := current_setting('p12e.owner_b')::uuid;
  q constant uuid := 'e1000000-0000-4000-8000-000000000001';
  q2 constant uuid := 'e1000000-0000-4000-8000-000000000002';
  issued jsonb; receipt jsonb; result jsonb; before_state jsonb; stamp timestamptz;
  epoch0 uuid; epoch1 uuid; failed_state text; failed_message text; statement text;
BEGIN
  PERFORM pg_temp.p12e_ok(NOT EXISTS (SELECT 1 FROM private.mobile_signup_completion_intents),
    'new_intent_table_starts_empty');
  before_state:=pg_temp.p12e_state();
  result:=public.resolve_mobile_signup_completion_intent(b,q);
  PERFORM pg_temp.p12e_ok(result='{"status":"absent"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'resolve_absent_creates_nothing_including_epoch');
  stamp:=clock_timestamp();
  issued:=public.begin_mobile_signup_completion_intent(a,q);
  receipt:=issued->'intent'; epoch0:=(receipt->>'epoch')::uuid;
  PERFORM pg_temp.p12e_ok(issued->>'status'='issued'
    AND receipt->>'ownerID'=a::text AND receipt->>'preparationID'=q::text
    AND receipt->>'requestKey' ~ '^osc1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND receipt->>'issuedAt' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$'
    AND (receipt->>'issuedAt')::timestamptz BETWEEN stamp AND clock_timestamp()
    AND (receipt->>'intentID')::uuid IS NOT NULL,
    'begin_issues_positive_owned_server_key_epoch_UTC6_once');
  PERFORM pg_temp.p12e_ok(
    (pg_temp.p12e_state()-'private.mobile_signup_completion_intents'-'private.workout_strength_authority_epochs')
      =(before_state-'private.mobile_signup_completion_intents'-'private.workout_strength_authority_epochs'),
    'begin_does_not_admit_hash_claim_complete_grant_or_open_lifecycle');
  before_state:=pg_temp.p12e_state();
  result:=public.begin_mobile_signup_completion_intent(a,q);
  PERFORM pg_temp.p12e_ok(result=jsonb_build_object('status','reused','intent',receipt)
    AND pg_temp.p12e_state()=before_state,'duplicate_Q_keeps_literal_identity_epoch_and_clock');
  result:=public.resolve_mobile_signup_completion_intent(a,q);
  PERFORM pg_temp.p12e_ok(result=jsonb_build_object('status','resolved','intent',receipt)
    AND pg_temp.p12e_state()=before_state,'resolve_issued_is_read_only_exact');
  result:=public.verify_mobile_signup_completion_intent(a,(receipt->>'intentID')::uuid,receipt->>'requestKey');
  PERFORM pg_temp.p12e_ok(result=jsonb_build_object('status','verified','intent',receipt)
    AND pg_temp.p12e_state()=before_state,'verify_is_read_only_and_preserves_original_epoch');
  result:=public.verify_mobile_signup_completion_intent(b,(receipt->>'intentID')::uuid,receipt->>'requestKey');
  PERFORM pg_temp.p12e_ok(result='{"status":"forbidden","reason":"invalid_intent"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'foreign_owner_receipt_is_generic_and_creates_nothing');
  result:=public.verify_mobile_signup_completion_intent(a,(receipt->>'intentID')::uuid,
    'osc1:e1000000-0000-4000-8000-000000000099');
  PERFORM pg_temp.p12e_ok(result='{"status":"forbidden","reason":"invalid_intent"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'mixed_receipt_key_refused_without_writes');
  result:=public.begin_mobile_signup_completion_intent(b,q);
  PERFORM pg_temp.p12e_ok(result->>'status'='issued'
    AND result#>>'{intent,ownerID}'=b::text
    AND result#>>'{intent,intentID}'<>receipt->>'intentID'
    AND result#>>'{intent,requestKey}'<>receipt->>'requestKey',
    'same_Q_other_owner_is_independent');

  -- No admission exists for K. A real reset must not let its first bind acquire E1.
  PERFORM public.reset_user_conversation_atomic(a,true);
  SELECT epoch INTO epoch1 FROM private.workout_strength_authority_epochs WHERE user_id=a;
  before_state:=pg_temp.p12e_state();
  PERFORM pg_temp.p12e_ok(epoch1<>epoch0 AND EXISTS (
    SELECT 1 FROM private.mobile_signup_completion_intents
    WHERE user_id=a AND preparation_id=q AND epoch=epoch0
      AND intent_id=(receipt->>'intentID')::uuid AND request_key=receipt->>'requestKey'),
    'reset_rotates_current_epoch_but_retains_never_admitted_positive_receipt');
  result:=public.begin_mobile_signup_completion_intent(a,q);
  PERFORM pg_temp.p12e_ok(result='{"status":"forbidden","reason":"stale_epoch"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'old_Q_after_reset_never_issues_new_key_or_epoch');
  result:=public.resolve_mobile_signup_completion_intent(a,q);
  PERFORM pg_temp.p12e_ok(result='{"status":"forbidden","reason":"stale_epoch"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'old_Q_resolution_is_stale_not_absent');
  result:=public.verify_mobile_signup_completion_intent(a,(receipt->>'intentID')::uuid,receipt->>'requestKey');
  PERFORM pg_temp.p12e_ok(result='{"status":"forbidden","reason":"stale_epoch"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'old_receipt_verify_never_refreshes_epoch');
  result:=public.admit_mobile_signup_strength_request(a,receipt->>'requestKey',repeat('e',64),epoch0);
  PERFORM pg_temp.p12e_ok(result='{"status":"forbidden","reason":"stale_epoch"}'::jsonb
    AND pg_temp.p12e_state()=before_state,'first_bind_after_reset_rejects_original_E0_without_admission');
  result:=public.begin_mobile_signup_completion_intent(a,q2);
  PERFORM pg_temp.p12e_ok(result->>'status'='issued'
    AND result#>>'{intent,epoch}'=epoch1::text
    AND result#>>'{intent,requestKey}'<>receipt->>'requestKey'
    AND result#>>'{intent,intentID}'<>receipt->>'intentID',
    'explicit_new_Q_gets_distinct_positive_identity_in_current_epoch');

  FOR statement IN SELECT unnest(ARRAY[
    format('SELECT public.begin_mobile_signup_completion_intent(%L,NULL)',a),
    format('SELECT public.resolve_mobile_signup_completion_intent(NULL,%L)',q),
    format('SELECT public.verify_mobile_signup_completion_intent(%L,%L,%L)',a,receipt->>'intentID','legacy-key-1')
  ]) LOOP
    failed_state:=NULL; failed_message:=NULL;
    BEGIN EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS failed_state=RETURNED_SQLSTATE,failed_message=MESSAGE_TEXT;
    END;
    PERFORM pg_temp.p12e_ok(failed_state='22023' AND failed_message='invalid_mobile_signup_completion_intent_input',
      'invalid_input_refused');
  END LOOP;
  PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
  failed_state:=NULL;
  BEGIN PERFORM public.begin_mobile_signup_completion_intent(a,q2);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS failed_state=RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.p12e_ok(failed_state='42501','trusted_backend_guard_rejects_end_user_claim');
END $contract$;
ROLLBACK;

-- No lookup/writes are allowed from a stale transaction snapshot.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
DO $isolation$
DECLARE statement text; failed_state text; failed_message text;
BEGIN
  FOR statement IN SELECT unnest(ARRAY[
    'SELECT public.begin_mobile_signup_completion_intent(''e1000000-0000-4000-8000-000000000091'',''e1000000-0000-4000-8000-000000000092'')',
    'SELECT public.resolve_mobile_signup_completion_intent(''e1000000-0000-4000-8000-000000000091'',''e1000000-0000-4000-8000-000000000092'')',
    'SELECT public.verify_mobile_signup_completion_intent(''e1000000-0000-4000-8000-000000000091'',''e1000000-0000-4000-8000-000000000092'',''osc1:e1000000-0000-4000-8000-000000000093'')'
  ]) LOOP
    failed_state:=NULL; failed_message:=NULL;
    BEGIN EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS failed_state=RETURNED_SQLSTATE,failed_message=MESSAGE_TEXT;
    END;
    IF failed_state IS DISTINCT FROM '22023'
      OR failed_message IS DISTINCT FROM 'mobile_signup_completion_intent_requires_read_committed' THEN
      RAISE EXCEPTION 'P12E_ASSERT:RR_must_refuse_before_owner_lookup';
    END IF;
    RAISE NOTICE 'P12E_PASS:RR_refuses_before_owner_lookup';
  END LOOP;
END $isolation$;
ROLLBACK;

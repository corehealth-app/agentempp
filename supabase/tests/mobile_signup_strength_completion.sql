\set ON_ERROR_STOP on
-- Contract written before the new keyed writer. W1's real legacy RED is retained
-- separately; a missing RPC/substrate is SETUP, never a causal product RED.
-- Atomic branch only here. Photo-chain, durable replay and races are separate gates.
-- Three real source INSERTs are expected (including the rolled-back W3 INSERT).
-- Their IDENTITY allocations survive ROLLBACK: the executor must verify that exact
-- monotonic delta plus complete catalog/row/other-sequence preservation.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout = '40s';
SET LOCAL lock_timeout = '5s';
DO $target$
BEGIN
  IF session_user <> 'c5_local_admin' OR current_user <> 'c5_local_admin'
    OR current_database() <> 'c5_reset_default_20261009'
    OR current_setting('port') <> '55489'
    OR current_setting('server_version_num') <> '170011'
    OR current_setting('data_directory') <>
      '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
    OR current_setting('unix_socket_directories') <> '/private/tmp/performe-c5-osecmg7_'
    OR current_setting('listen_addresses') <> '' OR inet_server_addr() IS NOT NULL THEN
    RAISE EXCEPTION 'C59SC_SETUP_WRONG_LOCAL_TARGET';
  END IF;
  IF to_regnamespace('c59signup_completion_fixture') IS NOT NULL
    OR EXISTS (SELECT 1 FROM public.users WHERE id::text LIKE 'c59c2700-%') THEN
    RAISE EXCEPTION 'C59SC_SETUP_FIXTURE_COLLISION';
  END IF;
  IF to_regprocedure('public.complete_mobile_onboarding_keyed(uuid,jsonb,text,text,text,uuid,uuid,jsonb,boolean,timestamptz,bigint)') IS NULL
    OR to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL
    OR to_regprocedure('public.complete_mobile_onboarding_atomic(uuid,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'C59SC_SETUP_ENTRYPOINT_OR_SUBSTRATE_ABSENT';
  END IF;
END $target$;
CREATE SCHEMA c59signup_completion_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
REVOKE ALL ON SCHEMA c59signup_completion_fixture FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION c59signup_completion_fixture.ok(value boolean, label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59SC_ASSERT:%', label; END IF;
  RAISE NOTICE 'C59SC_PASS:%', label;
END $$;

CREATE FUNCTION c59signup_completion_fixture.attempt(statement text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE result jsonb; state text; message text;
BEGIN
  EXECUTE statement INTO result;
  RETURN jsonb_build_object('ok', true, 'result', result);
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'sqlstate', state, 'message', message);
END $$;

CREATE FUNCTION c59signup_completion_fixture.state(owner_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = pg_catalog
SET DateStyle = 'ISO, YMD' SET TimeZone = 'UTC' AS $$
DECLARE relation record; rows jsonb; result jsonb := jsonb_build_object('public.users',
  (SELECT to_jsonb(u) FROM ONLY public.users u WHERE id = owner_id));
BEGIN
  FOR relation IN SELECT n.nspname, c.relname FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'private') AND c.relkind IN ('r', 'p')
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid
        AND a.attname = 'user_id' AND a.attnum > 0 AND NOT a.attisdropped)
    ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM ONLY %I.%I r WHERE user_id=$1',
      relation.nspname, relation.relname) INTO rows USING owner_id;
    result := result || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN result;
END $$;

CREATE FUNCTION c59signup_completion_fixture.submission(frequency smallint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = pg_catalog AS $$
  SELECT jsonb_build_object(
    'name', 'C59 synthetic QA', 'locale', 'pt-BR', 'country', 'BR',
    'timezone', 'America/Sao_Paulo', 'sex', 'masculino', 'birth_date', '1990-01-01',
    'height_cm', 180, 'weight_kg', 80, 'body_fat_percent', 24,
    'objective', 'recomposicao', 'activity_level', 'moderado', 'training_frequency', frequency,
    'water_intake', 'moderado', 'hunger_level', 'moderada', 'wake_time', '07:00',
    'bedtime', '23:00', 'food_organization', 'sim', 'persona', 'focus',
    'document_actions', jsonb_build_array(jsonb_build_object(
      'document_key', d.document_key, 'version', d.version, 'locale', d.locale,
      'content_hash', d.content_hash, 'action', d.action_type)))
  FROM public.onboarding_legal_documents d
  WHERE d.id = 'c59c2700-0000-4000-8000-000000000201'
$$;

CREATE FUNCTION c59signup_completion_fixture.bind(owner_id uuid, request_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE observation jsonb; bound jsonb;
BEGIN
  observation := public.observe_mobile_signup_strength_epoch(owner_id);
  bound := public.admit_mobile_signup_strength_request(owner_id, request_key, repeat('a',64),
    (observation #>> '{observation,epoch}')::uuid);
  IF bound->>'status' NOT IN ('admitted','reused') THEN
    RAISE EXCEPTION 'C59SC_SETUP_BIND_FAILED';
  END IF;
  RETURN bound->'admission';
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59signup_completion_fixture
  FROM PUBLIC, anon, authenticated, service_role;

DO $fixtures$
DECLARE body constant text := 'C59 keyed completion synthetic requirement. Local test only.';
BEGIN
  IF EXISTS (SELECT 1 FROM public.onboarding_legal_documents
      WHERE id = 'c59c2700-0000-4000-8000-000000000201' OR version = 'c59-20261019-keyed')
    OR EXISTS (SELECT 1 FROM public.onboarding_legal_requirement_sets
      WHERE id = 'c59c2700-0000-4000-8000-000000000301' OR version = 'c59-20261019-keyed')
    OR NOT EXISTS (SELECT 1 FROM public.coach_personalities WHERE code='focus' AND active AND selectable) THEN
    RAISE EXCEPTION 'C59SC_SETUP_LEGAL_COLLISION_OR_PERSONA_ABSENT';
  END IF;
  INSERT INTO public.onboarding_legal_documents
    (id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
    VALUES ('c59c2700-0000-4000-8000-000000000201','c59_signup_keyed_test',
      'c59-20261019-keyed','pt-BR',body,encode(extensions.digest(body,'sha256'),'hex'),
      'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_document('c59c2700-0000-4000-8000-000000000201');
  INSERT INTO public.onboarding_legal_requirement_sets (id,version,locale,document_keys,effective_at)
    VALUES ('c59c2700-0000-4000-8000-000000000301','c59-20261019-keyed','pt-BR',
      ARRAY['c59_signup_keyed_test'],clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_requirement_set('c59c2700-0000-4000-8000-000000000301');
  INSERT INTO public.users(id,email,name,locale,timezone,country,status)
    SELECT ('c59c2700-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
      'c59-keyed-'||n::text||'@example.invalid','C59 synthetic QA','pt-BR',
      'America/Sao_Paulo','BR','active' FROM generate_series(501,510) n;
  INSERT INTO public.user_profiles(user_id,onboarding_completed)
    SELECT id,false FROM public.users WHERE id::text LIKE 'c59c2700-%';
END $fixtures$;

DO $catalog$
DECLARE valid boolean;
BEGIN
  SELECT c.relowner='postgres'::regrole AND c.relrowsecurity AND NOT c.relforcerowsecurity
    AND NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid=c.oid)
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE a.grantee<>c.relowner) INTO valid FROM pg_class c
    WHERE c.oid='private.mobile_signup_strength_completion_receipts'::regclass;
  PERFORM c59signup_completion_fixture.ok(valid,'receipt_owner_only_RLS_no_policies');
  SELECT p.proowner='postgres'::regrole AND p.prosecdef AND p.pronargdefaults=0
    AND p.proconfig=ARRAY['search_path=pg_catalog']
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE a.grantee NOT IN(p.proowner,'service_role'::regrole)) INTO valid FROM pg_proc p
    WHERE p.oid='public.complete_mobile_onboarding_keyed(uuid,jsonb,text,text,text,uuid,uuid,jsonb,boolean,timestamptz,bigint)'::regprocedure;
  PERFORM c59signup_completion_fixture.ok(valid,'keyed_RPC_fixed_path_no_defaults_service_only');
END $catalog$;

DO $input_guards$
DECLARE query text; result jsonb; n integer:=0;
BEGIN
  -- Validly formatted but absent identities prove validation precedes lookup.
  FOR query IN SELECT format(
    'SELECT public.complete_mobile_onboarding_keyed(%s,%s,%s,%s,%s,%s,%s,NULL,NULL,NULL,NULL)',
    owner_arg,submission_arg,path_arg,key_arg,hash_arg,epoch_arg,admission_arg)
    FROM (VALUES
      ('NULL::uuid','''{}''::jsonb','''atomic''','''c59-valid-input''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','NULL::jsonb','''atomic''','''c59-valid-input''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''[]''::jsonb','''atomic''','''c59-valid-input''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''{}''::jsonb','NULL::text','''c59-valid-input''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''{}''::jsonb','''arbitrary_rpc''','''c59-valid-input''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''{}''::jsonb','''atomic''','''bad key''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''{}''::jsonb','''atomic''','''c59-valid-input''','''INVALID_HASH''','''c59c2700-0000-4000-8000-000000000901''::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''{}''::jsonb','''atomic''','''c59-valid-input''',quote_literal(repeat('a',64)),'NULL::uuid','''c59c2700-0000-4000-8000-000000000902''::uuid'),
      ('''c59c2700-0000-4000-8000-000000000900''::uuid','''{}''::jsonb','''atomic''','''c59-valid-input''',quote_literal(repeat('a',64)),'''c59c2700-0000-4000-8000-000000000901''::uuid','NULL::uuid')
    ) q(owner_arg,submission_arg,path_arg,key_arg,hash_arg,epoch_arg,admission_arg)
  LOOP
    n:=n+1;result:=c59signup_completion_fixture.attempt(query);
    PERFORM c59signup_completion_fixture.ok(result=
      '{"ok":false,"sqlstate":"22023","message":"invalid_mobile_signup_strength_input"}'::jsonb,
      'invalid_input_'||n::text||'_before_absent_owner_lookup');
  END LOOP;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  result:=c59signup_completion_fixture.attempt(
    'SELECT public.complete_mobile_onboarding_keyed(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)');
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  PERFORM c59signup_completion_fixture.ok(result=
    '{"ok":false,"sqlstate":"42501","message":"trusted backend role required"}'::jsonb,
    'real_trusted_guard_precedes_invalid_input');
END $input_guards$;

DO $fresh_and_replay$
DECLARE owner_id uuid; frequency smallint; admission jsonb; result jsonb; replay jsonb;
  before_state jsonb; after_state jsonb; receipt jsonb; source jsonb; sequence_before jsonb;
  sequence_after jsonb; lower_at timestamptz; key text; other_before jsonb;
BEGIN
  admission:=c59signup_completion_fixture.bind('c59c2700-0000-4000-8000-000000000501','c59-keyed-fresh-4');
  PERFORM private.open_strength_week_scope('c59c2700-0000-4000-8000-000000000508',
    'mobile_signup_completion_v1',admission->>'admissionID');
  other_before:=c59signup_completion_fixture.state('c59c2700-0000-4000-8000-000000000508');
  FOR frequency IN SELECT n::smallint FROM unnest(ARRAY[4,0]) n LOOP
    owner_id:=CASE frequency WHEN 4 THEN 'c59c2700-0000-4000-8000-000000000501'::uuid
      ELSE 'c59c2700-0000-4000-8000-000000000502'::uuid END;
    key:='c59-keyed-fresh-'||frequency::text;
    admission:=c59signup_completion_fixture.bind(owner_id,key);
    lower_at:=clock_timestamp();
    result:=public.complete_mobile_onboarding_keyed(owner_id,
      c59signup_completion_fixture.submission(frequency),'atomic',key,repeat('a',64),
      (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
    SELECT to_jsonb(r) INTO receipt FROM private.mobile_signup_strength_completion_receipts r
      WHERE user_id=owner_id AND admission_id=(admission->>'admissionID')::uuid;
    SELECT to_jsonb(v) INTO source FROM private.strength_week_source_versions v
      WHERE v.user_id=owner_id AND v.source_version_id=(receipt->>'frequency_source_version_id')::uuid;
    PERFORM c59signup_completion_fixture.ok(result->>'user_id'=owner_id::text
      AND result->>'onboarding_completed'='true' AND result->>'completed_at' IS NOT NULL
      AND receipt->>'outcome'='first_fresh' AND receipt->>'completion_path'='atomic'
      AND receipt->>'epoch'=admission->>'epoch' AND receipt->'completion_result'=result
      AND (receipt->>'completed_at')::timestamptz=(result->>'completed_at')::timestamptz
      AND source->>'source_kind'='informed_frequency' AND source->>'fact'='value'
      AND (source->>'planned_days')::smallint=frequency
      AND source->>'operation_namespace'='mobile_signup_completion_v1'
      AND source->>'operation_key'=admission->>'admissionID'
      AND source->>'generation'=receipt->>'generation'
      AND source->>'source_entity_id' IS NULL AND source->>'source_valid_until' IS NULL
      AND source->>'observed_timezone'='America/Sao_Paulo'
      AND (source->>'observed_at')::timestamptz>=lower_at
      AND (source->>'observed_at')::timestamptz<=(receipt->>'recorded_at')::timestamptz
      AND (source->>'effective_week_start')::date=
        date_trunc('week',(source->>'observed_at')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date+7
      AND EXISTS(SELECT 1 FROM private.strength_week_scopes s WHERE s.user_id=owner_id
        AND s.generation=(receipt->>'generation')::uuid AND s.closed_at IS NULL
        AND s.predecessor_generation IS NULL AND s.open_operation_namespace='mobile_signup_completion_v1'
        AND s.open_operation_key=admission->>'admissionID'
        AND s.opened_at<=(source->>'observed_at')::timestamptz)
      AND (SELECT count(*) FROM private.strength_week_scopes WHERE user_id=owner_id)=1
      AND (SELECT count(*) FROM private.strength_week_source_versions WHERE user_id=owner_id)=1
      AND NOT EXISTS(SELECT 1 FROM private.strength_week_targets WHERE user_id=owner_id)
      AND (SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id=owner_id)=1,
      'real_fresh_value'||frequency::text||'_owned_scope_source_receipt_next_Monday_no_target');
    RAISE NOTICE 'C59SC_ALLOCATED:%',source->>'source_order';
    UPDATE public.user_profiles SET training_frequency=7 WHERE user_id=owner_id;
    UPDATE public.users SET timezone='Pacific/Auckland' WHERE id=owner_id;
    before_state:=c59signup_completion_fixture.state(owner_id);
    SELECT jsonb_build_object('last_value',s.last_value::text,'log_cnt',s.log_cnt::text,'is_called',s.is_called)
      INTO sequence_before FROM private.strength_week_source_versions_source_order_seq s;
    -- A changed internal selector/CAS does not re-delegate a completed admission.
    replay:=public.complete_mobile_onboarding_keyed(owner_id,
      c59signup_completion_fixture.submission(frequency),'cleanup_scope',key,repeat('a',64),
      (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,true,clock_timestamp(),77);
    after_state:=c59signup_completion_fixture.state(owner_id);
    SELECT jsonb_build_object('last_value',s.last_value::text,'log_cnt',s.log_cnt::text,'is_called',s.is_called)
      INTO sequence_after FROM private.strength_week_source_versions_source_order_seq s;
    PERFORM c59signup_completion_fixture.ok(replay=result AND after_state=before_state
      AND sequence_after=sequence_before,'replay_value'||frequency::text||'_returns_original_without_clock_source_or_core');
    UPDATE public.user_profiles SET training_frequency=frequency WHERE user_id=owner_id;
    UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=owner_id;
    admission:=c59signup_completion_fixture.bind(owner_id,key||'-later');
    replay:=public.complete_mobile_onboarding_keyed(owner_id,
      c59signup_completion_fixture.submission(frequency),'atomic',key||'-later',repeat('a',64),
      (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
    PERFORM c59signup_completion_fixture.ok(replay=result
      AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r
        WHERE user_id=owner_id AND admission_id=(admission->>'admissionID')::uuid
          AND outcome='not_first_fresh' AND generation IS NULL AND frequency_source_version_id IS NULL)
      AND (SELECT count(*) FROM private.strength_week_source_versions WHERE user_id=owner_id)=1,
      'later_key_value'||frequency::text||'_historical_reaccept_never_reopens_source');
  END LOOP;
  PERFORM c59signup_completion_fixture.ok(
    c59signup_completion_fixture.state('c59c2700-0000-4000-8000-000000000508')=other_before,
    'other_owner_unchanged');
END $fresh_and_replay$;

DO $historical_and_orphans$
DECLARE owner_id uuid; admission jsonb; result jsonb; before_state jsonb; after_state jsonb;
  source_count bigint; ignored jsonb; key text; n integer;
BEGIN
  owner_id:='c59c2700-0000-4000-8000-000000000503';key:='c59-keyed-true-null';
  UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=owner_id;
  admission:=c59signup_completion_fixture.bind(owner_id,key);
  result:=public.complete_mobile_onboarding_keyed(owner_id,c59signup_completion_fixture.submission(4::smallint),
    'atomic',key,repeat('a',64),(admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
  PERFORM c59signup_completion_fixture.ok(result->>'onboarding_completed'='true'
    AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=owner_id
      AND outcome='not_first_fresh' AND generation IS NULL AND frequency_source_version_id IS NULL)
    AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=owner_id),
    'true_null_may_complete_but_never_becomes_first_fresh');

  owner_id:='c59c2700-0000-4000-8000-000000000504';key:='c59-keyed-false-timestamp';
  ignored:=public.complete_mobile_onboarding_atomic(owner_id,c59signup_completion_fixture.submission(4::smallint));
  UPDATE public.user_profiles SET onboarding_completed=false WHERE user_id=owner_id;
  admission:=c59signup_completion_fixture.bind(owner_id,key);
  before_state:=c59signup_completion_fixture.state(owner_id);
  result:=c59signup_completion_fixture.attempt(format(
    'SELECT public.complete_mobile_onboarding_keyed(%L::uuid,%L::jsonb,%L,%L,%L,%L::uuid,%L::uuid,NULL,NULL,NULL,NULL)',
    owner_id,c59signup_completion_fixture.submission(4::smallint),'atomic',key,repeat('a',64),
    admission->>'epoch',admission->>'admissionID'));
  after_state:=c59signup_completion_fixture.state(owner_id);
  PERFORM c59signup_completion_fixture.ok(result='{"ok":false,"sqlstate":"23514","message":"onboarding_already_completed"}'::jsonb
    AND after_state=before_state,'false_timestamp_preserves_real_core_23514_without_normalization');

  FOR n IN SELECT unnest(ARRAY[505,506,509]) LOOP
    owner_id:=('c59c2700-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
    key:='c59-keyed-orphan-'||n::text;admission:=c59signup_completion_fixture.bind(owner_id,key);
    IF n=505 THEN
      ignored:=private.open_strength_week_scope(owner_id,'c59_other_test_scope','c59-other-orphan-key');
    ELSE
      ignored:=private.open_strength_week_scope(owner_id,'mobile_signup_completion_v1',admission->>'admissionID');
      IF n=506 THEN
        UPDATE private.strength_week_scopes SET closed_at=clock_timestamp() WHERE user_id=owner_id AND closed_at IS NULL;
      END IF;
    END IF;
    before_state:=c59signup_completion_fixture.state(owner_id);
    result:=c59signup_completion_fixture.attempt(format(
      'SELECT public.complete_mobile_onboarding_keyed(%L::uuid,%L::jsonb,%L,%L,%L,%L::uuid,%L::uuid,NULL,NULL,NULL,NULL)',
      owner_id,c59signup_completion_fixture.submission(4::smallint),'atomic',key,repeat('a',64),
      admission->>'epoch',admission->>'admissionID'));
    after_state:=c59signup_completion_fixture.state(owner_id);
    PERFORM c59signup_completion_fixture.ok(result='{"ok":false,"sqlstate":"40001","message":"mobile_signup_strength_existing_scope"}'::jsonb
      AND after_state=before_state,'orphan_'||n::text||'_rejected_before_core_without_adoption');
  END LOOP;
END $historical_and_orphans$;

DO $authority_and_receipt$
DECLARE owner_id constant uuid:='c59c2700-0000-4000-8000-000000000501';
  admission jsonb; other_admission jsonb; result jsonb; before_state jsonb; after_state jsonb; other_state jsonb;
  key text; hash text; fake_id uuid; n integer;
BEGIN
  SELECT jsonb_build_object('epoch',a.epoch,'admissionID',a.admission_id) INTO admission
    FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id=owner_id AND a.request_key='c59-keyed-fresh-4';
  other_admission:=c59signup_completion_fixture.bind('c59c2700-0000-4000-8000-000000000508','c59-keyed-other-owner');
  other_state:=c59signup_completion_fixture.state('c59c2700-0000-4000-8000-000000000508');
  before_state:=c59signup_completion_fixture.state(owner_id);
  result:=c59signup_completion_fixture.attempt(format(
    'UPDATE private.mobile_signup_strength_completion_receipts SET completion_path=%L WHERE user_id=%L::uuid',
    'cleanup_scope',owner_id));
  after_state:=c59signup_completion_fixture.state(owner_id);
  PERFORM c59signup_completion_fixture.ok(result=
    '{"ok":false,"sqlstate":"22023","message":"mobile_signup_strength_completion_receipt_immutable"}'::jsonb
    AND after_state=before_state,'receipt_decision_cannot_be_updated');
  -- Technical owned epoch rotation only; actual reset/race coverage is separate.
  UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid(),changed_at=clock_timestamp()
    WHERE user_id=owner_id;
  before_state:=c59signup_completion_fixture.state(owner_id);
  FOR n IN SELECT generate_series(1,4) LOOP
    key:=CASE n WHEN 1 THEN 'c59-keyed-wrong-key' ELSE 'c59-keyed-fresh-4' END;
    hash:=CASE n WHEN 2 THEN repeat('b',64) ELSE repeat('a',64) END;
    fake_id:=CASE n WHEN 3 THEN (other_admission->>'admissionID')::uuid
      ELSE (admission->>'admissionID')::uuid END;
    result:=c59signup_completion_fixture.attempt(format(
      'SELECT public.complete_mobile_onboarding_keyed(%L::uuid,%L::jsonb,%L,%L,%L,%L::uuid,%L::uuid,NULL,NULL,NULL,NULL)',
      owner_id,c59signup_completion_fixture.submission(4::smallint),'atomic',key,hash,
      admission->>'epoch',fake_id));
    after_state:=c59signup_completion_fixture.state(owner_id);
    PERFORM c59signup_completion_fixture.ok(result=jsonb_build_object('ok',false,'sqlstate','40001',
      'message',CASE n WHEN 4 THEN 'mobile_signup_strength_stale_epoch'
        ELSE 'mobile_signup_strength_invalid_admission' END)
      AND after_state=before_state,'authority_case_'||n::text||'_validated_before_receipt_replay');
  END LOOP;
  PERFORM c59signup_completion_fixture.ok(
    c59signup_completion_fixture.state('c59c2700-0000-4000-8000-000000000508')=other_state,
    'mixed_other_owner_admission_does_not_change_other_owner');
END $authority_and_receipt$;

DO $core_failure$
DECLARE owner_id constant uuid:='c59c2700-0000-4000-8000-000000000510';
  key constant text:='c59-keyed-core-failure';admission jsonb;before_state jsonb;after_state jsonb;result jsonb;
BEGIN
  admission:=c59signup_completion_fixture.bind(owner_id,key);
  before_state:=c59signup_completion_fixture.state(owner_id);
  result:=c59signup_completion_fixture.attempt(format(
    'SELECT public.complete_mobile_onboarding_keyed(%L::uuid,%L::jsonb,%L,%L,%L,%L::uuid,%L::uuid,NULL,NULL,NULL,NULL)',
    owner_id,jsonb_set(c59signup_completion_fixture.submission(4::smallint),'{document_actions}','[]'::jsonb),
    'atomic',key,repeat('a',64),admission->>'epoch',admission->>'admissionID'));
  after_state:=c59signup_completion_fixture.state(owner_id);
  PERFORM c59signup_completion_fixture.ok(result=
    '{"ok":false,"sqlstate":"22023","message":"invalid_onboarding_document_actions"}'::jsonb
    AND after_state=before_state,'real_core_error_propagates_and_preserves_post_bind_state');
END $core_failure$;

-- Owned fault only on the NEW receipt table. Never replace an auth/core/Y helper.
CREATE FUNCTION c59signup_completion_fixture.fail_after_real_source() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE source_order_text text;
BEGIN
  IF NEW.user_id='c59c2700-0000-4000-8000-000000000507'::uuid THEN
    SELECT v.source_order::text INTO source_order_text
      FROM private.strength_week_source_versions v
      JOIN public.user_profiles p ON p.user_id=v.user_id
      JOIN private.mobile_signup_strength_request_admissions a
        ON a.user_id=v.user_id AND a.admission_id=NEW.admission_id
      JOIN private.strength_week_scopes s ON s.user_id=v.user_id AND s.generation=v.generation
      WHERE v.user_id=NEW.user_id AND v.generation=NEW.generation
        AND v.source_version_id=NEW.frequency_source_version_id
        AND NEW.outcome='first_fresh' AND NEW.completion_path='atomic' AND a.epoch=NEW.epoch
        AND a.request_key='c59-keyed-rollback-after-source' AND a.request_hash=repeat('a',64)
        AND v.source_kind='informed_frequency' AND v.fact='value' AND v.planned_days=4
        AND v.operation_namespace='mobile_signup_completion_v1' AND v.operation_key=NEW.admission_id::text
        AND s.open_operation_namespace='mobile_signup_completion_v1' AND s.open_operation_key=NEW.admission_id::text
        AND s.closed_at IS NULL AND p.onboarding_completed IS TRUE AND p.onboarding_completed_at=NEW.completed_at
        AND EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions legal
          WHERE legal.user_id=NEW.user_id AND legal.legal_document_id='c59c2700-0000-4000-8000-000000000201');
    IF source_order_text IS NULL THEN RAISE EXCEPTION 'C59SC_SETUP_FAULT_BEFORE_REAL_EFFECT'; END IF;
    RAISE NOTICE 'C59SC_ALLOCATED:%',source_order_text;
    RAISE EXCEPTION 'C59SC_OWNED_RECEIPT_FAILURE_AFTER_REAL_SOURCE' USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION c59signup_completion_fixture.fail_after_real_source()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER c59_owned_fail_after_real_source BEFORE INSERT
  ON private.mobile_signup_strength_completion_receipts FOR EACH ROW
  EXECUTE FUNCTION c59signup_completion_fixture.fail_after_real_source();

DO $atomic_rollback$
DECLARE owner_id constant uuid:='c59c2700-0000-4000-8000-000000000507';
  key constant text:='c59-keyed-rollback-after-source';admission jsonb;before_state jsonb;after_state jsonb;result jsonb;
BEGIN
  admission:=c59signup_completion_fixture.bind(owner_id,key);
  before_state:=c59signup_completion_fixture.state(owner_id);
  result:=c59signup_completion_fixture.attempt(format(
    'SELECT public.complete_mobile_onboarding_keyed(%L::uuid,%L::jsonb,%L,%L,%L,%L::uuid,%L::uuid,NULL,NULL,NULL,NULL)',
    owner_id,c59signup_completion_fixture.submission(4::smallint),'atomic',key,repeat('a',64),
    admission->>'epoch',admission->>'admissionID'));
  after_state:=c59signup_completion_fixture.state(owner_id);
  PERFORM c59signup_completion_fixture.ok(result=
    '{"ok":false,"sqlstate":"P0001","message":"C59SC_OWNED_RECEIPT_FAILURE_AFTER_REAL_SOURCE"}'::jsonb
    AND after_state=before_state
    AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_request_admissions WHERE user_id=owner_id
      AND admission_id=(admission->>'admissionID')::uuid),
    'failure_after_real_source_rolls_back_core_legal_Y_receipt_and_preserves_prior_admission');
END $atomic_rollback$;

-- Test the new FK cascade directly. Full account deletion also has pre-existing
-- legal-retention guards and is not claimed as validated by this test.
DO $admission_delete_cascade$
DECLARE owner_id constant uuid:='c59c2700-0000-4000-8000-000000000502';
BEGIN
  DELETE FROM private.mobile_signup_strength_request_admissions WHERE user_id=owner_id;
  PERFORM c59signup_completion_fixture.ok(
    NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=owner_id)
    AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_request_admissions WHERE user_id=owner_id)
    AND (SELECT count(*) FROM private.strength_week_scopes WHERE user_id=owner_id)=1
    AND (SELECT count(*) FROM private.strength_week_source_versions WHERE user_id=owner_id)=1,
    'admission_FK_cascades_receipts_without_delete_trigger_and_preserves_Y');
END $admission_delete_cascade$;
ROLLBACK;

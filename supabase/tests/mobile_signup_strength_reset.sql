\set ON_ERROR_STOP on
-- Regression for W5: first_fresh keyed completion -> real reset -> new admission.
-- Causal RED was reproduced on the unchanged reset/core before the candidate.
-- This test requires the owned-normalizer candidate and the ordinary writer substrate.
-- Five natural source allocations survive ROLLBACK. The local executor must compare
-- the complete four-database model; no sequence rewind or durable-reset claim.
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
    RAISE EXCEPTION 'C59SR_SETUP_WRONG_LOCAL_TARGET';
  END IF;
  IF to_regnamespace('c59signup_reset_fixture') IS NOT NULL
    OR EXISTS (SELECT 1 FROM public.users WHERE id::text LIKE 'c59f2900-%') THEN
    RAISE EXCEPTION 'C59SR_SETUP_FIXTURE_COLLISION';
  END IF;
  IF to_regprocedure('public.complete_mobile_onboarding_keyed(uuid,jsonb,text,text,text,uuid,uuid,jsonb,boolean,timestamptz,bigint)') IS NULL
    OR to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL
    OR to_regprocedure('public.complete_mobile_onboarding_atomic(uuid,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'C59SR_SETUP_ENTRYPOINT_OR_SUBSTRATE_ABSENT';
  END IF;
END $target$;
CREATE SCHEMA c59signup_reset_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
REVOKE ALL ON SCHEMA c59signup_reset_fixture FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION c59signup_reset_fixture.ok(value boolean, label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59SR_ASSERT:%', label; END IF;
  RAISE NOTICE 'C59SR_PASS:%', label;
END $$;

CREATE FUNCTION c59signup_reset_fixture.attempt(statement text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE result jsonb; state text; message text;
BEGIN
  EXECUTE statement INTO result;
  RETURN jsonb_build_object('ok', true, 'result', result);
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'sqlstate', state, 'message', message);
END $$;

CREATE FUNCTION c59signup_reset_fixture.state(owner_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog
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

CREATE FUNCTION c59signup_reset_fixture.submission(frequency smallint) RETURNS jsonb
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
  WHERE d.id = 'c59f2900-0000-4000-8000-000000000201'
$$;

CREATE FUNCTION c59signup_reset_fixture.bind(owner_id uuid, request_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE observation jsonb; bound jsonb;
BEGIN
  observation := public.observe_mobile_signup_strength_epoch(owner_id);
  bound := public.admit_mobile_signup_strength_request(owner_id, request_key, repeat('a',64),
    (observation #>> '{observation,epoch}')::uuid);
  IF bound->>'status' NOT IN ('admitted','reused') THEN
    RAISE EXCEPTION 'C59SR_SETUP_BIND_FAILED';
  END IF;
  RETURN bound->'admission';
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59signup_reset_fixture
  FROM PUBLIC, anon, authenticated, service_role;

DO $fixtures$
DECLARE body constant text := 'C59 keyed reset synthetic requirement. Local test only.';
BEGIN
  IF EXISTS (SELECT 1 FROM public.onboarding_legal_documents
      WHERE id = 'c59f2900-0000-4000-8000-000000000201' OR version = 'c59-20261020-keyed-reset')
    OR EXISTS (SELECT 1 FROM public.onboarding_legal_requirement_sets
      WHERE id = 'c59f2900-0000-4000-8000-000000000301' OR version = 'c59-20261020-keyed-reset')
    OR NOT EXISTS (SELECT 1 FROM public.coach_personalities WHERE code='focus' AND active AND selectable) THEN
    RAISE EXCEPTION 'C59SR_SETUP_LEGAL_COLLISION_OR_PERSONA_ABSENT';
  END IF;
  INSERT INTO public.onboarding_legal_documents
    (id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
    VALUES ('c59f2900-0000-4000-8000-000000000201','c59_signup_reset_test',
      'c59-20261020-keyed-reset','pt-BR',body,encode(extensions.digest(body,'sha256'),'hex'),
      'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_document('c59f2900-0000-4000-8000-000000000201');
  INSERT INTO public.onboarding_legal_requirement_sets (id,version,locale,document_keys,effective_at)
    VALUES ('c59f2900-0000-4000-8000-000000000301','c59-20261020-keyed-reset','pt-BR',
      ARRAY['c59_signup_reset_test'],clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_requirement_set('c59f2900-0000-4000-8000-000000000301');
  INSERT INTO public.users(id,email,name,locale,timezone,country,status)
    SELECT ('c59f2900-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
      'c59-keyed-reset-'||n::text||'@example.invalid','C59 synthetic QA','pt-BR',
      'America/Sao_Paulo','BR','active' FROM generate_series(501,510) n;
  INSERT INTO public.user_profiles(user_id,onboarding_completed)
    SELECT id,false FROM public.users WHERE id::text LIKE 'c59f2900-%';
END $fixtures$;

CREATE TABLE c59signup_reset_fixture.registry(key text PRIMARY KEY,value jsonb NOT NULL);
REVOKE ALL ON TABLE c59signup_reset_fixture.registry FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59signup_reset_fixture.keyed(owner_id uuid,request_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE admission jsonb; result jsonb;
BEGIN
  admission:=c59signup_reset_fixture.bind(owner_id,request_key);
  result:=public.complete_mobile_onboarding_keyed(owner_id,c59signup_reset_fixture.submission(4::smallint),
    'atomic',request_key,repeat('a',64),(admission->>'epoch')::uuid,
    (admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
  RETURN jsonb_build_object('admission',admission,'result',result);
END $$;
REVOKE ALL ON FUNCTION c59signup_reset_fixture.keyed(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

DO $candidate_catalog$
DECLARE p record; t record;
BEGIN
  SELECT * INTO p FROM pg_proc
    WHERE oid=to_regprocedure('private.normalize_mobile_signup_strength_receipted_reset()');
  SELECT * INTO t FROM pg_trigger WHERE tgrelid='public.user_profiles'::regclass
    AND tgname='normalize_mobile_signup_strength_receipted_reset';
  PERFORM c59signup_reset_fixture.ok(p.oid IS NOT NULL AND p.proowner='postgres'::regrole
    AND p.prosecdef AND p.provolatile='v' AND p.pronargdefaults=0
    AND p.proconfig=ARRAY['search_path=pg_catalog']
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE a.grantee<>p.proowner)
    AND t.tgfoid=p.oid AND t.tgtype=19 AND t.tgenabled='O' AND NOT t.tgisinternal,
    'candidate_owner_only_fixed_path_update_trigger');
  INSERT INTO c59signup_reset_fixture.registry
    SELECT 'initial_source_order',to_jsonb(last_value)
    FROM private.strength_week_source_versions_source_order_seq;
END $candidate_catalog$;

DO $owned_completion_and_reset$
DECLARE owner_id constant uuid:='c59f2900-0000-4000-8000-000000000501';
  original jsonb; receipt jsonb; admission jsonb; source jsonb; scope jsonb; reset_result jsonb;
BEGIN
  original:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-original-501');
  SELECT to_jsonb(r) INTO receipt FROM private.mobile_signup_strength_completion_receipts r
    WHERE r.user_id=owner_id;
  SELECT to_jsonb(a) INTO admission FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id=owner_id;
  SELECT to_jsonb(v) INTO source FROM private.strength_week_source_versions v WHERE v.user_id=owner_id;
  SELECT to_jsonb(s) INTO scope FROM private.strength_week_scopes s WHERE s.user_id=owner_id;
  PERFORM c59signup_reset_fixture.ok(receipt->>'outcome'='first_fresh'
    AND source->>'generation'=receipt->>'generation' AND scope->>'generation'=receipt->>'generation',
    'original_first_fresh_has_real_receipt_scope_and_frequency_source');
  UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=owner_id;
  PERFORM c59signup_reset_fixture.ok(EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
    AND p.onboarding_completed IS TRUE AND p.onboarding_completed_at=(receipt->>'completed_at')::timestamptz),
    'ordinary_true_to_true_update_preserves_owned_timestamp');
  reset_result:=public.reset_user_conversation_atomic(owner_id,true);
  PERFORM c59signup_reset_fixture.ok(reset_result->'reset'='true'::jsonb
    AND EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
      AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.user_progress p WHERE p.user_id=owner_id),
    'real_reset_clears_exact_owned_timestamp_without_forged_NULL');
  PERFORM c59signup_reset_fixture.ok(receipt=(SELECT to_jsonb(r)
      FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=owner_id)
    AND admission=(SELECT to_jsonb(a) FROM private.mobile_signup_strength_request_admissions a WHERE a.user_id=owner_id)
    AND source=(SELECT to_jsonb(v) FROM private.strength_week_source_versions v WHERE v.user_id=owner_id)
    AND EXISTS(SELECT 1 FROM private.strength_week_scopes s WHERE s.user_id=owner_id
      AND s.closed_at IS NOT NULL AND to_jsonb(s)-'closed_at'=scope-'closed_at'),
    'reset_preserves_complete_original_admission_receipt_source_and_closes_only_G0');
  INSERT INTO c59signup_reset_fixture.registry VALUES('original',original),('receipt0',receipt),
    ('source0',source),('scope0',scope),('post_reset',c59signup_reset_fixture.state(owner_id));
END $owned_completion_and_reset$;

DO $old_authority$
DECLARE owner_id constant uuid:='c59f2900-0000-4000-8000-000000000501';
  original jsonb; a jsonb; result jsonb; observation jsonb;
BEGIN
  SELECT value INTO original FROM c59signup_reset_fixture.registry WHERE key='original';
  a:=original->'admission';
  result:=c59signup_reset_fixture.attempt(format(
    'SELECT public.complete_mobile_onboarding_keyed(%L::uuid,%L::jsonb,''atomic'',%L,%L,%L::uuid,%L::uuid,NULL,NULL,NULL,NULL)',
    owner_id,c59signup_reset_fixture.submission(4::smallint),'c59-w5-original-501',repeat('a',64),a->>'epoch',a->>'admissionID'));
  PERFORM c59signup_reset_fixture.ok(result->'ok'='false'::jsonb AND result->>'sqlstate'='40001'
    AND result->>'message'='mobile_signup_strength_stale_epoch','old_tuple_rejected_after_real_reset');
  observation:=public.observe_mobile_signup_strength_epoch(owner_id);
  result:=public.admit_mobile_signup_strength_request(owner_id,'c59-w5-original-501',repeat('a',64),
    (observation#>>'{observation,epoch}')::uuid);
  PERFORM c59signup_reset_fixture.ok(result='{"status":"forbidden","reason":"stale_epoch"}'::jsonb,
    'old_key_not_rebound_after_reobservation');
  result:=public.admit_mobile_signup_strength_request(owner_id,'c59-w5-original-501',repeat('b',64),
    (observation#>>'{observation,epoch}')::uuid);
  PERFORM c59signup_reset_fixture.ok(result='{"status":"forbidden","reason":"stale_epoch"}'::jsonb,
    'changed_hash_cannot_repair_stale_key');
END $old_authority$;

DO $new_owned_completion$
DECLARE owner_id constant uuid:='c59f2900-0000-4000-8000-000000000501';
  original jsonb; next_result jsonb; receipt0 jsonb; receipt1 jsonb;
BEGIN
  PERFORM c59signup_reset_fixture.ok(c59signup_reset_fixture.state(owner_id)=
    (SELECT value FROM c59signup_reset_fixture.registry WHERE key='post_reset'),
    'stale_attempts_change_no_owned_rows_in_later_statement');
  SELECT value INTO original FROM c59signup_reset_fixture.registry WHERE key='original';
  SELECT value INTO receipt0 FROM c59signup_reset_fixture.registry WHERE key='receipt0';
  next_result:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-new-501');
  SELECT to_jsonb(r) INTO receipt1 FROM private.mobile_signup_strength_completion_receipts r
    WHERE r.user_id=owner_id AND r.admission_id=(next_result#>>'{admission,admissionID}')::uuid;
  PERFORM c59signup_reset_fixture.ok(receipt1->>'outcome'='first_fresh'
    AND next_result#>>'{admission,epoch}'<>original#>>'{admission,epoch}'
    AND receipt1->>'generation'<>receipt0->>'generation'
    AND (receipt1->>'completed_at')::timestamptz>(receipt0->>'completed_at')::timestamptz
    AND EXISTS(SELECT 1 FROM private.strength_week_scopes s WHERE s.user_id=owner_id
      AND s.generation=(receipt1->>'generation')::uuid AND s.closed_at IS NULL
      AND s.predecessor_generation IS NULL)
    AND EXISTS(SELECT 1 FROM private.strength_week_source_versions v WHERE v.user_id=owner_id
      AND v.source_version_id=(receipt1->>'frequency_source_version_id')::uuid
      AND v.planned_days=4 AND v.effective_week_start=
        date_trunc('week',v.observed_at AT TIME ZONE v.observed_timezone)::date+7)
    AND receipt0=(SELECT to_jsonb(r) FROM private.mobile_signup_strength_completion_receipts r
      WHERE r.user_id=owner_id AND r.admission_id=(original#>>'{admission,admissionID}')::uuid),
    'K1_E1_recovers_with_new_T1_G1_and_next_Monday_preserving_receipt0');
END $new_owned_completion$;

DO $legacy_and_historical_negatives$
DECLARE owner_id uuid; original jsonb; rec jsonb; completed_at timestamptz; result jsonb;
BEGIN
  -- Real legacy completion followed by a keyed reaccept is not first_fresh ownership.
  owner_id:='c59f2900-0000-4000-8000-000000000502';
  original:=public.complete_mobile_onboarding_atomic(owner_id,c59signup_reset_fixture.submission(4::smallint));
  rec:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-reaccept-only-502');
  PERFORM public.reset_user_conversation_atomic(owner_id,false);
  PERFORM c59signup_reset_fixture.ok(EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
      AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at=(original->>'completed_at')::timestamptz)
    AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=owner_id
      AND r.outcome='not_first_fresh' AND r.generation IS NULL),
    'not_first_fresh_alone_preserves_legacy_reset_timestamp');

  owner_id:='c59f2900-0000-4000-8000-000000000503';
  original:=public.complete_mobile_onboarding_atomic(owner_id,c59signup_reset_fixture.submission(4::smallint));
  PERFORM public.reset_user_conversation_atomic(owner_id,true);
  PERFORM c59signup_reset_fixture.ok(EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
      AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at=(original->>'completed_at')::timestamptz)
    AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=owner_id),
    'legacy_without_owned_receipt_preserves_timestamp');

  -- An old owned receipt never attests a different, genuinely completed legacy T1.
  owner_id:='c59f2900-0000-4000-8000-000000000504';
  rec:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-old-owned-504');
  PERFORM public.reset_user_conversation_atomic(owner_id,true);
  original:=public.complete_mobile_onboarding_atomic(owner_id,c59signup_reset_fixture.submission(4::smallint));
  PERFORM c59signup_reset_fixture.ok((original->>'completed_at')::timestamptz>
    (rec#>>'{result,completed_at}')::timestamptz,'legacy_T1_is_real_and_newer_than_owned_T0');
  PERFORM public.reset_user_conversation_atomic(owner_id,true);
  PERFORM c59signup_reset_fixture.ok(EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
    AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at=(original->>'completed_at')::timestamptz),
    'old_first_fresh_receipt_cannot_normalize_new_unowned_T1');

  owner_id:='c59f2900-0000-4000-8000-000000000505';
  rec:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-first-505');
  result:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-reaccept-505');
  PERFORM public.reset_user_conversation_atomic(owner_id,true);
  PERFORM c59signup_reset_fixture.ok(result#>'{result,completed_at}'=rec#>'{result,completed_at}'
    AND EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
      AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at IS NULL)
    AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=owner_id
      AND r.outcome='first_fresh') AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r
      WHERE r.user_id=owner_id AND r.outcome='not_first_fresh'),
    'exact_first_fresh_still_owns_completion_after_later_reaccept');

  -- Explicit timestamp replacement is a negative guard test, not a recovery fixture.
  owner_id:='c59f2900-0000-4000-8000-000000000506';
  rec:=c59signup_reset_fixture.keyed(owner_id,'c59-w5-explicit-506');
  completed_at:=(rec#>>'{result,completed_at}')::timestamptz+interval '1 second';
  UPDATE public.user_profiles SET onboarding_completed=false,onboarding_completed_at=completed_at
    WHERE user_id=owner_id;
  PERFORM c59signup_reset_fixture.ok(EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
    AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at=completed_at),
    'explicit_new_timestamp_is_not_overwritten');

  -- Deliberately collide timestamps across two synthetic owners, without forging
  -- any receipt. Another owner's real first_fresh T cannot attest this profile.
  owner_id:='c59f2900-0000-4000-8000-000000000508';
  original:=public.complete_mobile_onboarding_atomic(owner_id,c59signup_reset_fixture.submission(4::smallint));
  SELECT (value->>'completed_at')::timestamptz INTO completed_at
    FROM c59signup_reset_fixture.registry WHERE key='receipt0';
  UPDATE public.user_profiles SET onboarding_completed_at=completed_at WHERE user_id=owner_id;
  PERFORM public.reset_user_conversation_atomic(owner_id,true);
  PERFORM c59signup_reset_fixture.ok(EXISTS(SELECT 1 FROM public.user_profiles p WHERE p.user_id=owner_id
    AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at=completed_at)
    AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=owner_id),
    'other_owner_receipt_with_same_timestamp_cannot_attest_profile');

  PERFORM c59signup_reset_fixture.ok((SELECT last_value FROM private.strength_week_source_versions_source_order_seq)=
    (SELECT value::bigint+5 FROM c59signup_reset_fixture.registry WHERE key='initial_source_order'),
    'five_exact_natural_source_allocations');
END $legacy_and_historical_negatives$;

RESET ROLE;
ROLLBACK;
\echo C59W5_GREEN_ATOMIC_ROLLBACK

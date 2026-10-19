\set ON_ERROR_STOP on
-- New S1–S3 contract tests. Missing new RPCs is SETUP, never a causal product RED.
-- Local retained C5 only; no fixture COMMIT or product/auth replacement.
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
    RAISE EXCEPTION 'C59SA_SETUP_WRONG_LOCAL_TARGET';
  END IF;
  IF to_regnamespace('c59signup_fixture') IS NOT NULL
    OR EXISTS (SELECT 1 FROM public.users WHERE id::text LIKE 'c59c2600-%') THEN
    RAISE EXCEPTION 'C59SA_SETUP_FIXTURE_COLLISION';
  END IF;
  IF to_regprocedure('public.observe_mobile_signup_strength_epoch(uuid)') IS NULL
    OR to_regprocedure('public.admit_mobile_signup_strength_request(uuid,text,text,uuid)') IS NULL
    OR to_regprocedure('public.verify_mobile_signup_strength_request(uuid,uuid,text,text,uuid)') IS NULL
    OR to_regclass('private.mobile_signup_strength_request_admissions') IS NULL THEN
    RAISE EXCEPTION 'C59SA_SETUP_NEW_ENTRYPOINT_ABSENT';
  END IF;
END $target$;
CREATE SCHEMA c59signup_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
REVOKE ALL ON SCHEMA c59signup_fixture FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION c59signup_fixture.ok(value boolean, label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  IF value IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'C59SA_ASSERT:%', label;
  END IF;
  RAISE NOTICE 'C59SA_PASS:%', label;
END $$;

CREATE FUNCTION c59signup_fixture.attempt(statement text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE result jsonb; state text; message text;
BEGIN
  EXECUTE statement INTO result;
  RETURN jsonb_build_object('ok', true, 'result', result);
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'sqlstate', state, 'message', message);
END $$;

CREATE FUNCTION c59signup_fixture.state(owner_id uuid) RETURNS jsonb
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
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59signup_fixture FROM PUBLIC, anon, authenticated, service_role;

DO $schema$
DECLARE valid boolean;
BEGIN
  SELECT c.relowner = 'postgres'::regrole AND c.relrowsecurity AND NOT c.relforcerowsecurity
    AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid)
    AND NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE a.grantee <> c.relowner)
    INTO valid FROM pg_class c WHERE c.oid = 'private.mobile_signup_strength_request_admissions'::regclass;
  PERFORM c59signup_fixture.ok(valid, 'dedicated_table_owner_only_RLS_no_policies');
  SELECT count(*) = 3 AND bool_and(p.proowner = 'postgres'::regrole AND p.prosecdef
    AND p.proconfig = ARRAY['search_path=pg_catalog'] AND p.pronargdefaults = 0
    AND has_function_privilege('service_role', p.oid, 'EXECUTE')
    AND NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE a.grantee NOT IN (p.proowner, 'service_role'::regrole))) INTO valid
    FROM pg_proc p WHERE p.oid IN (
      'public.observe_mobile_signup_strength_epoch(uuid)'::regprocedure,
      'public.admit_mobile_signup_strength_request(uuid,text,text,uuid)'::regprocedure,
      'public.verify_mobile_signup_strength_request(uuid,uuid,text,text,uuid)'::regprocedure);
  PERFORM c59signup_fixture.ok(valid, 'three_RPCs_fixed_path_owner_service_only');
END $schema$;

DO $contract$
DECLARE
  owner_a constant uuid := 'c59c2600-0000-4000-8000-000000000401';
  owner_b constant uuid := 'c59c2600-0000-4000-8000-000000000402';
  owner_blocked constant uuid := 'c59c2600-0000-4000-8000-000000000403';
  original_key constant text := 'c59-signup-original-1';
  original_hash constant text := repeat('a', 64);
  observed jsonb; admission jsonb; replay jsonb; result jsonb; before_state jsonb; after_state jsonb;
  mixed_results jsonb[]; stale_result jsonb;
  control_state jsonb; epoch_a uuid; epoch_b uuid; created_after timestamptz;
  id_a uuid; invalid jsonb; query text;
BEGIN
  INSERT INTO public.users (id, wpp, email, status) VALUES
    (owner_a, '1555190000401', 'c59-signup-authority-a@example.invalid', 'active'),
    (owner_b, '1555190000402', 'c59-signup-authority-b@example.invalid', 'active'),
    (owner_blocked, '1555190000403', 'c59-signup-authority-blocked@example.invalid', 'blocked');
  control_state := c59signup_fixture.state(owner_b);
  before_state := c59signup_fixture.state(owner_a);
  created_after := clock_timestamp();
  observed := public.observe_mobile_signup_strength_epoch(owner_a);
  after_state := c59signup_fixture.state(owner_a);
  epoch_a := (observed #>> '{observation,epoch}')::uuid;
  PERFORM c59signup_fixture.ok(observed->>'status' = 'observed'
    AND observed #>> '{observation,ownerID}' = owner_a::text
    AND observed #>> '{observation,changedAt}' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$'
    AND EXISTS (SELECT 1 FROM private.workout_strength_authority_epochs
      WHERE user_id = owner_a AND epoch = epoch_a AND changed_at >= created_after
        AND changed_at <= clock_timestamp() AND current_lifecycle_key IS NULL),
    'observe_creates_concrete_owned_epoch_with_post_lock_UTC6_clock');
  PERFORM c59signup_fixture.ok(
    NOT EXISTS (SELECT 1 FROM private.mobile_signup_strength_request_admissions WHERE user_id = owner_a)
    AND NOT EXISTS (SELECT 1 FROM private.workout_strength_request_admissions WHERE user_id = owner_a)
    AND NOT EXISTS (SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id = owner_a)
    AND NOT EXISTS (SELECT 1 FROM private.strength_week_scopes WHERE user_id = owner_a)
    AND NOT EXISTS (SELECT 1 FROM private.strength_week_source_versions WHERE user_id = owner_a)
    AND NOT EXISTS (SELECT 1 FROM private.strength_week_targets WHERE user_id = owner_a)
    AND NOT EXISTS (SELECT 1 FROM public.messages WHERE user_id = owner_a)
    AND (after_state - 'private.workout_strength_authority_epochs')
      = (before_state - 'private.workout_strength_authority_epochs')
    AND c59signup_fixture.state(owner_b) = control_state,
    'observation_binds_no_key_hash_life_IN_Y_and_preserves_other_owner');

  UPDATE private.workout_strength_authority_epochs
    SET current_lifecycle_key = 'c59c2600-0000-4000-8000-000000000999' WHERE user_id = owner_a;
  before_state := c59signup_fixture.state(owner_a);
  result := public.observe_mobile_signup_strength_epoch(owner_a);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(result = observed AND after_state = before_state,
    'reobserve_conserves_epoch_clock_and_existing_lifecycle_pointer_without_adoption');

  before_state := c59signup_fixture.state(owner_a);
  created_after := clock_timestamp();
  result := public.admit_mobile_signup_strength_request(owner_a, original_key, original_hash, epoch_a);
  after_state := c59signup_fixture.state(owner_a);
  admission := result->'admission'; id_a := (admission->>'admissionID')::uuid;
  PERFORM c59signup_fixture.ok(result->>'status' = 'admitted'
    AND admission->>'ownerID' = owner_a::text AND admission->>'epoch' = epoch_a::text
    AND admission->>'requestKey' = original_key AND admission->>'requestHash' = original_hash
    AND admission->>'admittedAt' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$'
    AND EXISTS (SELECT 1 FROM private.mobile_signup_strength_request_admissions
      WHERE user_id = owner_a AND admission_id = id_a AND admitted_at >= created_after
        AND admitted_at <= clock_timestamp())
    AND (after_state - 'private.mobile_signup_strength_request_admissions')
      = (before_state - 'private.mobile_signup_strength_request_admissions'),
    'bind_original_identity_once_post_lock_clock');
  before_state := c59signup_fixture.state(owner_a);
  replay := public.admit_mobile_signup_strength_request(owner_a, original_key, original_hash, epoch_a);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(replay = jsonb_build_object('status', 'reused', 'admission', admission)
    AND after_state = before_state, 'same_key_payload_reuses_exact_admission_without_writes');
  result := public.admit_mobile_signup_strength_request(owner_a, original_key, repeat('b',64), epoch_a);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(result = '{"status":"conflict","reason":"request_content_conflict"}'::jsonb
    AND after_state = before_state, 'changed_payload_conflicts_without_overwriting');
  result := public.admit_mobile_signup_strength_request(owner_a, upper(original_key), original_hash, epoch_a);
  PERFORM c59signup_fixture.ok(result->>'status' = 'admitted'
    AND result #>> '{admission,requestKey}' = upper(original_key)
    AND result #>> '{admission,admissionID}' <> id_a::text, 'request_key_is_literal_case_sensitive');

  before_state := c59signup_fixture.state(owner_a);
  result := public.admit_mobile_signup_strength_request(owner_b, original_key, original_hash, epoch_a);
  after_state := c59signup_fixture.state(owner_b);
  PERFORM c59signup_fixture.ok(
    result = '{"status":"forbidden","reason":"invalid_observation"}'::jsonb
    AND after_state = control_state,
    'bind_without_observation_does_not_create_epoch_or_admission');
  epoch_b := (public.observe_mobile_signup_strength_epoch(owner_b) #>> '{observation,epoch}')::uuid;
  result := public.admit_mobile_signup_strength_request(owner_b, original_key, original_hash, epoch_b);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(result->>'status' = 'admitted'
    AND result #>> '{admission,ownerID}' = owner_b::text
    AND result #>> '{admission,admissionID}' <> id_a::text
    AND after_state = before_state, 'same_key_other_owner_is_independent');
  result := public.verify_mobile_signup_strength_request(owner_a, id_a, original_key, original_hash, epoch_a);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(result = jsonb_build_object('status', 'verified', 'admission', admission)
    AND after_state = before_state, 'verify_same_admission_is_read_only');
  invalid := '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  mixed_results := ARRAY[
    public.verify_mobile_signup_strength_request(owner_b, id_a, original_key, original_hash, epoch_b),
    public.verify_mobile_signup_strength_request(owner_a, id_a, 'c59-wrong-key-1', original_hash, epoch_a),
    public.verify_mobile_signup_strength_request(owner_a, id_a, original_key, repeat('b',64), epoch_a),
    public.verify_mobile_signup_strength_request(owner_a, owner_b, original_key, original_hash, epoch_a)];
  stale_result := public.verify_mobile_signup_strength_request(owner_a, id_a, original_key, original_hash, owner_b);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(
    (SELECT bool_and(value = invalid) FROM unnest(mixed_results) value)
    AND stale_result = '{"status":"forbidden","reason":"stale_epoch"}'::jsonb
    AND after_state = before_state, 'mixed_owner_ID_key_hash_refused_without_mutation');

  FOR query IN SELECT unnest(ARRAY[
    'SELECT public.observe_mobile_signup_strength_epoch(NULL)',
    format('SELECT public.admit_mobile_signup_strength_request(%L,NULL,%L,%L)', owner_a, original_hash, epoch_a),
    format('SELECT public.admit_mobile_signup_strength_request(%L,%L,NULL,%L)', owner_a, original_key, epoch_a),
    format('SELECT public.admit_mobile_signup_strength_request(%L,%L,%L,NULL)', owner_a, original_key, original_hash),
    format('SELECT public.admit_mobile_signup_strength_request(%L,%L,%L,%L)', owner_a, 'short', original_hash, epoch_a),
    format('SELECT public.admit_mobile_signup_strength_request(%L,%L,%L,%L)', owner_a, ' c59-space-key-1', original_hash, epoch_a),
    format('SELECT public.admit_mobile_signup_strength_request(%L,%L,%L,%L)', owner_a, original_key, upper(original_hash), epoch_a),
    format('SELECT public.verify_mobile_signup_strength_request(%L,NULL,%L,%L,%L)', owner_a, original_key, original_hash, epoch_a)
  ]) LOOP
    result := c59signup_fixture.attempt(query);
    PERFORM c59signup_fixture.ok(result = '{"ok":false,"sqlstate":"22023","message":"invalid_mobile_signup_strength_input"}'::jsonb,
      'invalid_NULL_or_literal_format_refused_before_bind');
  END LOOP;
  result := c59signup_fixture.attempt(format('SELECT public.observe_mobile_signup_strength_epoch(%L)', owner_blocked));
  PERFORM c59signup_fixture.ok(result = '{"ok":false,"sqlstate":"P0002","message":"mobile_signup_strength_patient_not_found"}'::jsonb
    AND NOT EXISTS (SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id = owner_blocked),
    'blocked_owner_has_no_fence');
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  result := c59signup_fixture.attempt(format('SELECT public.observe_mobile_signup_strength_epoch(%L)', owner_a));
  PERFORM c59signup_fixture.ok(result = '{"ok":false,"sqlstate":"42501","message":"trusted backend role required"}'::jsonb,
    'real_trusted_guard_rejects_end_user_claim_even_as_function_owner');
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- Real reset rotates the shared epoch; no old key can be rebound to the new one.
  PERFORM public.reset_user_conversation_atomic(owner_a, true);
  epoch_b := (public.observe_mobile_signup_strength_epoch(owner_a) #>> '{observation,epoch}')::uuid;
  invalid := '{"status":"forbidden","reason":"stale_epoch"}'::jsonb;
  before_state := c59signup_fixture.state(owner_a);
  mixed_results := ARRAY[
    public.admit_mobile_signup_strength_request(owner_a, original_key, original_hash, epoch_a),
    public.admit_mobile_signup_strength_request(owner_a, original_key, original_hash, epoch_b),
    public.admit_mobile_signup_strength_request(owner_a, original_key, repeat('b',64), epoch_b),
    public.verify_mobile_signup_strength_request(owner_a, id_a, original_key, original_hash, epoch_a)];
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(epoch_b <> epoch_a
    AND (SELECT bool_and(value = invalid) FROM unnest(mixed_results) value)
    AND after_state = before_state,
    'reset_retains_tombstone_and_old_key_never_acquires_new_epoch');
  result := public.admit_mobile_signup_strength_request(owner_a, 'c59-never-bound-key-1', original_hash, epoch_a);
  after_state := c59signup_fixture.state(owner_a);
  PERFORM c59signup_fixture.ok(result = invalid AND after_state = before_state,
    'observe_before_reset_then_first_bind_cannot_renew_epoch');
  result := public.admit_mobile_signup_strength_request(owner_a, 'c59-new-after-reset-1', original_hash, epoch_b);
  PERFORM c59signup_fixture.ok(result->>'status' = 'admitted'
    AND result #>> '{admission,epoch}' = epoch_b::text
    AND result #>> '{admission,admissionID}' <> id_a::text,
    'new_observation_new_key_admits_without_reusing_old_identity');
END $contract$;
ROLLBACK;

-- The missing owner would fail P0002 after locks; both modes must instead refuse RC.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
DO $isolation$
DECLARE query text; state text; message text;
BEGIN
  FOR query IN SELECT unnest(ARRAY[
    'SELECT public.observe_mobile_signup_strength_epoch(''c59c2600-0000-4000-8000-000000000701'')',
    'SELECT public.admit_mobile_signup_strength_request(''c59c2600-0000-4000-8000-000000000701'',''c59-rr-valid-key-1'',repeat(''a'',64),''c59c2600-0000-4000-8000-000000000702'')',
    'SELECT public.verify_mobile_signup_strength_request(''c59c2600-0000-4000-8000-000000000701'',''c59c2600-0000-4000-8000-000000000703'',''c59-rr-valid-key-1'',repeat(''a'',64),''c59c2600-0000-4000-8000-000000000702'')'
  ]) LOOP
    state := NULL; message := NULL;
    BEGIN EXECUTE query;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
    END;
    IF state IS DISTINCT FROM '22023' OR message IS DISTINCT FROM 'mobile_signup_strength_requires_read_committed' THEN
      RAISE EXCEPTION 'C59SA_ASSERT:RR_must_refuse_before_owner_lookup';
    END IF;
    RAISE NOTICE 'C59SA_PASS:RR_refuses_before_owner_lookup';
  END LOOP;
END $isolation$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
DO $isolation$
DECLARE query text; state text; message text;
BEGIN
  FOR query IN SELECT unnest(ARRAY[
    'SELECT public.observe_mobile_signup_strength_epoch(''c59c2600-0000-4000-8000-000000000701'')',
    'SELECT public.admit_mobile_signup_strength_request(''c59c2600-0000-4000-8000-000000000701'',''c59-serial-valid-key-1'',repeat(''a'',64),''c59c2600-0000-4000-8000-000000000702'')',
    'SELECT public.verify_mobile_signup_strength_request(''c59c2600-0000-4000-8000-000000000701'',''c59c2600-0000-4000-8000-000000000703'',''c59-serial-valid-key-1'',repeat(''a'',64),''c59c2600-0000-4000-8000-000000000702'')'
  ]) LOOP
    state := NULL; message := NULL;
    BEGIN EXECUTE query;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
    END;
    IF state IS DISTINCT FROM '22023' OR message IS DISTINCT FROM 'mobile_signup_strength_requires_read_committed' THEN
      RAISE EXCEPTION 'C59SA_ASSERT:Serializable_must_refuse_before_owner_lookup';
    END IF;
    RAISE NOTICE 'C59SA_PASS:Serializable_refuses_before_owner_lookup';
  END LOOP;
END $isolation$;
ROLLBACK;

-- TEST SCAFFOLD ONLY. No C59a2 product function/table is defined here.
-- Install as fixture owner in Root's NEW, exclusive, synthetic local cluster.
-- All helpers are invokers, owner-only; they do not grant business authority.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA c59a2_fixture;
REVOKE ALL ON SCHEMA c59a2_fixture FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION c59a2_fixture.ok(p_ok boolean,p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'C59A2_ASSERT:%',p_label USING ERRCODE='P0001';
  END IF;
  RAISE NOTICE 'C59A2_PASS:%',p_label;
END $$;
CREATE FUNCTION c59a2_fixture.throws(p_sql text,p_state text,p_message text,p_label text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE s text;m text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    PERFORM c59a2_fixture.ok(s=p_state AND (p_message IS NULL OR m=p_message),p_label);
    RETURN;
  END;
  RAISE EXCEPTION 'C59A2_EXPECTED_ERROR:%',p_label;
END $$;
CREATE FUNCTION c59a2_fixture.new_owner(p_label text,p_zone text DEFAULT 'America/Sao_Paulo',
  p_history boolean DEFAULT true,p_completed boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE u uuid:=pg_catalog.gen_random_uuid();g uuid:=pg_catalog.gen_random_uuid();
BEGIN
  INSERT INTO public.users(id,wpp,name,timezone,metadata)
  VALUES(u,'c59a2-synthetic-'||u::text,p_label,p_zone,'{"c59a2_synthetic":true}'::jsonb);
  INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at)
  VALUES(u,p_completed,NULL);
  IF p_history THEN
    -- Explicit historical fixture, not open() or automatic bootstrap evidence.
    INSERT INTO private.strength_week_scopes(user_id,generation,predecessor_generation,
      open_operation_namespace,open_operation_key,opened_at,closed_at)
    VALUES(u,g,NULL,'c59a2.fixture',p_label||'-history',timestamptz '2026-01-01T00:00:00.000000Z',NULL);
  ELSE g:=NULL; END IF;
  RETURN jsonb_build_object('user_id',u,'generation',g);
END $$;
CREATE FUNCTION c59a2_fixture.frequency(p_owner jsonb,p_days smallint,p_key text,
  p_at timestamptz DEFAULT timestamptz '2026-10-08T12:00:00.123456Z') RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  UPDATE public.user_profiles SET training_frequency=p_days
    WHERE user_id=(p_owner->>'user_id')::uuid;
  RETURN private.capture_strength_week_source_at((p_owner->>'user_id')::uuid,
    (p_owner->>'generation')::uuid,'informed_frequency',
    CASE WHEN p_days IS NULL THEN 'absent' ELSE 'value' END,p_days,NULL,NULL,
    'c59a2.fixture',p_key,p_at);
END $$;
CREATE FUNCTION c59a2_fixture.plan(p_owner jsonb,p_days smallint,p_key text,
  p_at timestamptz DEFAULT timestamptz '2026-10-08T12:00:00.123456Z',
  p_until timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE p uuid;
BEGIN
  UPDATE public.training_plans SET active=false WHERE user_id=(p_owner->>'user_id')::uuid;
  IF p_days IS NOT NULL THEN
    INSERT INTO public.training_plans(user_id,plan_type,days_per_week,weekly_schedule,
      generated_at,valid_until,active)
    VALUES((p_owner->>'user_id')::uuid,'custom',p_days,'[]'::jsonb,p_at,p_until,true)
    RETURNING id INTO p;
  END IF;
  RETURN private.capture_strength_week_source_at((p_owner->>'user_id')::uuid,
    (p_owner->>'generation')::uuid,'accepted_plan',
    CASE WHEN p_days IS NULL THEN 'absent' ELSE 'value' END,p_days,p,p_until,
    'c59a2.fixture',p_key,p_at);
END $$;
CREATE FUNCTION c59a2_fixture.proposal(p_source text,p_days smallint,p_key text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$
SELECT jsonb_build_object('source',p_source,'planned_days',p_days,'source_key',p_key)
$$;
CREATE FUNCTION c59a2_fixture.read_at(p_owner jsonb,
  p_at timestamptz DEFAULT timestamptz '2026-10-12T12:00:00.000000Z') RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$
SELECT private.get_mobile_strength_week_context_at((p_owner->>'user_id')::uuid,p_at)
$$;
CREATE FUNCTION c59a2_fixture.freeze_at(p_owner jsonb,p_read jsonb,p_proposal jsonb,
  p_at timestamptz DEFAULT timestamptz '2026-10-12T12:00:00.000000Z') RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$
SELECT private.freeze_mobile_strength_week_target_at((p_owner->>'user_id')::uuid,
  (p_owner->>'generation')::uuid,p_read#>>'{context,timezone}',
  (p_read#>>'{context,week_start}')::date,p_read#>'{context,source_proof}',p_proposal,p_at)
$$;
CREATE FUNCTION c59a2_fixture.ready_case(p_label text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE o jsonb;p jsonb;f jsonb;r jsonb;
BEGIN
  o:=c59a2_fixture.new_owner(p_label);
  p:=c59a2_fixture.plan(o,3::smallint,p_label||'-plan');
  f:=c59a2_fixture.frequency(o,4::smallint,p_label||'-freq');
  r:=c59a2_fixture.read_at(o);
  PERFORM c59a2_fixture.ok(r->>'status'='ready' AND r#>>'{context,kind}'='source_facts',
    p_label||':fixture_ready');
  RETURN o||jsonb_build_object('read',r,'plan',p,'frequency',f,
    'proposal',c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'));
END $$;
-- Future installed-private patch invokes ONLY this observation helper at the
-- verified product callsite BEFORE users FOR UPDATE or any preceding owner lock.
-- No flags, facts, identity, result, clock or permission are injected into product.
CREATE FUNCTION c59a2_fixture.observe_pre_owner_lock() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE own_key bigint;peer_key bigint;turn_key bigint;loser boolean;
BEGIN
  IF current_setting('c59a2_test.enabled',true) IS DISTINCT FROM 'on' THEN RETURN;END IF;
  own_key:=current_setting('c59a2_test.own')::bigint;
  peer_key:=current_setting('c59a2_test.peer')::bigint;
  turn_key:=current_setting('c59a2_test.turn')::bigint;
  loser:=current_setting('c59a2_test.loser')::boolean;
  RAISE NOTICE 'C59A2_PRE_OWNER_ARRIVAL';
  IF NOT pg_advisory_unlock(own_key) THEN RAISE EXCEPTION 'C59A2_SETUP_OWN_GATE_MISSING';END IF;
  PERFORM pg_advisory_lock(peer_key);
  PERFORM pg_advisory_unlock(peer_key);
  IF loser THEN
    PERFORM pg_advisory_lock(turn_key);
    PERFORM pg_advisory_unlock(turn_key);
  END IF;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59a2_fixture FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

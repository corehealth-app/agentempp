-- Synthetic fixture for the reviewed retained local C5 reset regression only.
-- Included after BEGIN; the target and fixture roles are established below.
-- Target/schema check happens before SET LOCAL ROLE postgres; all QA DDL rolls back.
-- No product function, guard, auth shim or migration is copied/replaced here.
-- All weekly receipts are explicit historical fixtures, not writer admission proof.
\set ON_ERROR_STOP on
DO $target$
BEGIN
  IF session_user <> 'c5_local_admin' OR current_user <> 'c5_local_admin' THEN
    RAISE EXCEPTION 'C59RY_SETUP_TARGET_INSPECTION_REQUIRES_SESSION_ROLE';
  END IF;
  IF current_database() <> 'c5_reset_default_20261009'
    OR current_setting('port') <> '55489'
    OR current_setting('server_version_num') <> '170011'
    OR current_setting('data_directory') <>
      '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
    OR current_setting('unix_socket_directories') <> '/private/tmp/performe-c5-osecmg7_'
    OR inet_server_addr() IS NOT NULL
    OR current_setting('transaction_isolation') <> 'read committed'
  THEN RAISE EXCEPTION 'C59RY_SETUP_WRONG_LOCAL_TARGET'; END IF;
  IF to_regnamespace('c59ry_fixture') IS NOT NULL
    OR to_regclass('private.strength_week_scopes') IS NULL
    OR to_regclass('private.strength_week_source_versions') IS NULL
    OR to_regclass('private.strength_week_targets') IS NULL
    OR to_regprocedure('public.reset_user_conversation_atomic(uuid,boolean)') IS NULL
    OR to_regprocedure('public.reset_user_conversation_atomic(uuid)') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  THEN RAISE EXCEPTION 'C59RY_SETUP_MISSING_OR_COLLIDING_SUBSTRATE'; END IF;
  IF EXISTS (SELECT 1 FROM public.users
    WHERE id::text LIKE 'c59f2600-0000-0000-0000-%')
    OR EXISTS (SELECT 1 FROM private.strength_week_source_versions
      WHERE source_order BETWEEN 88000000000000000 AND 88000000000010000)
  THEN RAISE EXCEPTION 'C59RY_SETUP_SYNTHETIC_NAMESPACE_COLLISION'; END IF;
  IF NOT has_database_privilege(current_user,current_database(),'CREATE') THEN
    RAISE EXCEPTION 'C59RY_SETUP_SESSION_ROLE_CANNOT_CREATE_QA_SCHEMA';
  END IF;
  RAISE NOTICE 'C59RY_GUARD:target_session_verified_before_role';
END $target$;

-- Session administrator creates only the owned QA schema; postgres is not
-- assumed to own this database or have CREATE privilege on it.
CREATE SCHEMA c59ry_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
DO $fixture_role$
BEGIN
  IF session_user<>'c5_local_admin' OR current_user<>'postgres'
    OR (SELECT nspowner FROM pg_namespace WHERE nspname='c59ry_fixture')
      IS DISTINCT FROM 'postgres'::regrole::oid THEN
    RAISE EXCEPTION 'C59RY_SETUP_FIXTURE_ROLE_OR_SCHEMA_OWNER_WRONG';
  END IF;
  RAISE NOTICE 'C59RY_GUARD:fixture_role_postgres_verified';
END $fixture_role$;
REVOKE ALL ON SCHEMA c59ry_fixture FROM PUBLIC,anon,authenticated,service_role;

-- Empty for sequential/RED transactions. Only the reviewed Root controller may
-- populate/COMMIT these two registries for the concurrency phase.
CREATE TABLE c59ry_fixture.ownership (
  tag text PRIMARY KEY CHECK(tag='c59ry_reset_close_v1'),
  controller_token uuid NOT NULL,
  fixture_sha256 text NOT NULL CHECK(fixture_sha256 ~ '^[0-9a-f]{64}$'),
  product_baseline_four_sha256 text NOT NULL CHECK(product_baseline_four_sha256 ~ '^[0-9a-f]{64}$'),
  expected_sequences jsonb NOT NULL,
  sentinel_state jsonb NOT NULL
);
CREATE TABLE c59ry_fixture.cases (
  case_id text PRIMARY KEY,
  owner_id uuid UNIQUE NOT NULL,
  payload jsonb NOT NULL
);
REVOKE ALL ON TABLE c59ry_fixture.ownership,c59ry_fixture.cases
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION c59ry_fixture.ok(v boolean,label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $ok$
BEGIN
  IF v IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'C59RY_ASSERT:%',label USING ERRCODE='P0001';
  END IF;
  RAISE NOTICE 'C59RY_PASS:%',label;
END $ok$;

CREATE FUNCTION c59ry_fixture.uid(i integer) RETURNS uuid
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $uid$
SELECT ('c59f2600-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid
$uid$;

CREATE FUNCTION c59ry_fixture.attempt(sql text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $attempt$
DECLARE r jsonb;s text;m text;
BEGIN
  BEGIN
    EXECUTE sql INTO r;
    RETURN jsonb_build_object('ok',true,'result',r);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m);
  END;
END $attempt$;

-- Includes every actual public/private owner table, without dumping other owners.
CREATE FUNCTION c59ry_fixture.state(u uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog
SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $state$
DECLARE t record;rows jsonb;r jsonb:=jsonb_build_object('public.users',
  (SELECT to_jsonb(x) FROM ONLY public.users x WHERE id=u));
BEGIN
  FOR t IN SELECT n.nspname,c.relname FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid
        AND a.attname='user_id' AND a.attnum>0 AND NOT a.attisdropped)
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)
      INTO rows USING u;
    r:=r||jsonb_build_object(t.nspname||'.'||t.relname,rows);
  END LOOP;
  RETURN r;
END $state$;

CREATE FUNCTION c59ry_fixture.sequences() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $sequences$
SELECT coalesce(jsonb_object_agg(n.nspname||'.'||c.relname,
  jsonb_build_object('oid',c.oid::text,'owner',c.relowner::text,'acl',c.relacl::text,
    'parameters',to_jsonb(s),'last_value',v.last_value)),'{}'::jsonb)
FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_sequences v ON v.schemaname=n.nspname AND v.sequencename=c.relname
WHERE n.nspname IN ('public','private')
$sequences$;

-- Exact legacy DELETE targets from the retained S15 reset. Closure UPDATEs do not
-- enter this count. The expected list is frozen before the new product delta.
CREATE FUNCTION c59ry_fixture.deleted_count(u uuid,keep_plans boolean) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $deleted$
DECLARE t text;n bigint;r bigint:=0;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'pending_registrations','message_dispatch_outbox','message_buffer','tools_audit',
    'llm_evaluations','daily_gap_reminder_attempts','engagement_delivery_attempts',
    'attention_dismissals','user_phrase_cooldown','user_food_corrections',
    'reevaluations','meal_logs','workout_logs','daily_snapshots','messages','product_events'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM ONLY public.%I WHERE user_id=$1',t) INTO n USING u;
    r:=r+n;
  END LOOP;
  IF NOT keep_plans THEN
    FOREACH t IN ARRAY ARRAY['plan_drafts','prescriptions','training_plans'] LOOP
      EXECUTE format('SELECT count(*) FROM ONLY public.%I WHERE user_id=$1',t) INTO n USING u;
      r:=r+n;
    END LOOP;
  END IF;
  RETURN r;
END $deleted$;

CREATE FUNCTION c59ry_fixture.seed(i integer,with_y boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $seed$
DECLARE
  u uuid:=c59ry_fixture.uid(i);g uuid:=c59ry_fixture.uid(i+1000);
  prior uuid:=c59ry_fixture.uid(i+2000);pv uuid:=c59ry_fixture.uid(i+3000);
  fv uuid:=c59ry_fixture.uid(i+4000);target uuid:=c59ry_fixture.uid(i+5000);
  plan uuid:=c59ry_fixture.uid(i+6000);msg uuid:=c59ry_fixture.uid(i+7000);
  workout uuid:=c59ry_fixture.uid(i+8000);life uuid:=c59ry_fixture.uid(i+9000);
  epoch uuid:=c59ry_fixture.uid(i+10000);admission uuid:=c59ry_fixture.uid(i+11000);
  porder bigint:=88000000000000000::bigint+i*2;forder bigint:=porder+1;
BEGIN
  INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,
    metadata,flow_phrase_cursor_revision)
  VALUES(u,'c59ry-synthetic-'||i,'c59ry-'||i||'@example.invalid','C59RY synthetic',
    'UTC','US',true,'{"c59ry_synthetic":true,"training_reminders":true,"training_delivery_hour":7}',23);
  INSERT INTO public.user_profiles(user_id,weight_kg,training_frequency,
    onboarding_completed,onboarding_step)
  VALUES(u,80,4,true,9)
  ON CONFLICT(user_id) DO UPDATE SET weight_kg=80,training_frequency=4,
    onboarding_completed=true,onboarding_step=9;
  INSERT INTO public.training_plans(id,user_id,plan_type,days_per_week,
    weekly_schedule,generated_at,active)
  VALUES(plan,u,'custom',3,'[]','2026-10-08T12:00:00.123456Z',true);
  INSERT INTO public.messages(id,user_id,direction,role,content_type,content,provider)
  VALUES(msg,u,'in','user','text','C59RY synthetic text','mobile_flow');
  INSERT INTO public.pending_registrations(user_id,proposal,proposal_msg_id,expires_at)
  VALUES(u,'{"kind":"meal","mealType":"jantar"}',msg,clock_timestamp()+interval '1 hour');
  INSERT INTO public.workout_logs(id,user_id,workout_type,duration_min,estimated_kcal,performed_at)
  VALUES(workout,u,'C59RY synthetic legacy',30,100,'2026-10-12T12:00:00Z');
  INSERT INTO private.workout_strength_lifecycles(user_id,lifecycle_key,opened_at)
  VALUES(u,life,'2026-10-01T00:00:00Z');
  INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,current_lifecycle_key,changed_at)
  VALUES(u,epoch,life,'2026-10-01T00:00:00Z');
  INSERT INTO private.workout_strength_request_admissions(user_id,admission_id,
    request_namespace,request_key,request_hash,epoch,admitted_at)
  VALUES(u,admission,'mobile_flow_turn','c59ry-admission-'||i,repeat('a',64),epoch,
    '2026-10-01T00:00:00Z');
  IF with_y THEN
    INSERT INTO private.strength_week_scopes(user_id,generation,predecessor_generation,
      open_operation_namespace,open_operation_key,opened_at,closed_at)
    VALUES(u,prior,NULL,'c59ry.fixture','reset-y-prior-'||i,
      '2026-01-01T00:00:00Z','2026-01-02T00:00:00Z'),
      (u,g,prior,'c59ry.fixture','reset-y-current-'||i,'2026-10-01T00:00:00Z',NULL);
    INSERT INTO private.strength_week_source_versions(source_version_id,user_id,generation,
      source_kind,fact,planned_days,source_entity_id,source_valid_until,
      operation_namespace,operation_key,observed_at,observed_timezone,
      effective_week_start,source_order) OVERRIDING SYSTEM VALUE
    VALUES(pv,u,g,'accepted_plan','value',3,plan,NULL,'c59ry.fixture',
      'reset-y-plan-'||i,'2026-10-08T12:00:00.123456Z','UTC','2026-10-12',porder),
      (fv,u,g,'informed_frequency','value',4,NULL,NULL,'c59ry.fixture',
      'reset-y-frequency-'||i,'2026-10-08T12:00:00.654321Z','UTC','2026-10-12',forder);
    INSERT INTO private.strength_week_targets(target_id,user_id,generation,
      week_start,timezone_at_freeze,planned_days,source,plan_source_version_id,
      frequency_source_version_id,frozen_at)
    VALUES(target,u,g,'2026-10-12','UTC',3,'accepted_plan',pv,fv,
      '2026-10-12T12:00:00.123456Z');
  END IF;
  RETURN jsonb_build_object('owner',u,'generation',g,'prior',prior,'target',target,
    'plan',plan,'plan_version',pv,'frequency_version',fv,'life',life,'epoch',epoch,
    'index',i,'proof',jsonb_build_object(
      'plan',jsonb_build_object('coverage','covered','source_version_id',pv,'source_order',porder::text),
      'frequency',jsonb_build_object('coverage','covered','source_version_id',fv,'source_order',forder::text)),
    'proposal',jsonb_build_object('source','accepted_plan','planned_days',3,'source_key',pv));
END $seed$;

CREATE FUNCTION c59ry_fixture.fail_after_y_close() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fault$
BEGIN
  IF OLD.user_id=c59ry_fixture.uid(302) THEN
    IF EXISTS(SELECT 1 FROM private.strength_week_scopes
        WHERE user_id=OLD.user_id AND closed_at IS NULL)
      OR NOT EXISTS(SELECT 1 FROM private.strength_week_scopes
        WHERE user_id=OLD.user_id AND generation=c59ry_fixture.uid(1302) AND closed_at IS NOT NULL)
      OR NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles
        WHERE user_id=OLD.user_id AND lifecycle_key=c59ry_fixture.uid(9302) AND closed_at IS NOT NULL)
      OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs
        WHERE user_id=OLD.user_id AND epoch<>c59ry_fixture.uid(10302) AND current_lifecycle_key IS NULL)
      OR EXISTS(SELECT 1 FROM public.pending_registrations WHERE user_id=OLD.user_id)
    THEN RAISE EXCEPTION 'C59RY_FAULT_ORDER_NOT_PROVED' USING ERRCODE='P0002'; END IF;
    RAISE EXCEPTION 'C59RY_INJECTED_AFTER_Y_EPOCH_LIFE_AND_EARLY_DELETE' USING ERRCODE='P0001';
  END IF;
  RETURN OLD;
END $fault$;

DO $acl$
DECLARE p record;
BEGIN
  FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='c59ry_fixture'::regnamespace LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.oid::regprocedure);
  END LOOP;
END $acl$;

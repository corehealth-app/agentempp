-- TEST-ONLY substrate fragment. Included INSIDE the X26 runner transaction.
-- Requires the pinned C59a2 minimum bootstrap users/protocol_enum/roles.
-- No fake product function, new enum, DROP, clone, remote access or COMMIT.
-- Exact selected schema/index statements copied from real repository migrations.

CREATE TABLE daily_snapshots (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                  date NOT NULL,
  calories_consumed     integer NOT NULL DEFAULT 0,
  calories_target       integer,
  protein_g             numeric(6,2) NOT NULL DEFAULT 0,
  protein_target        numeric(6,2),
  carbs_g               numeric(6,2) NOT NULL DEFAULT 0,
  fat_g                 numeric(6,2) NOT NULL DEFAULT 0,
  exercise_calories     integer NOT NULL DEFAULT 0,
  steps                 integer,
  training_done         boolean NOT NULL DEFAULT false,
  sleep_hours           numeric(3,1),
  water_consumed_ml     integer NOT NULL DEFAULT 0,
  xp_earned             integer NOT NULL DEFAULT 0,
  deficit_accumulated   integer NOT NULL DEFAULT 0,
  daily_balance         integer GENERATED ALWAYS AS (
    calories_consumed - COALESCE(calories_target, 0) - COALESCE(exercise_calories, 0)
  ) STORED,
  current_protocol      protocol_enum,
  day_closed            boolean NOT NULL DEFAULT false,
  closed_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, date)
);

CREATE INDEX idx_daily_user_date ON daily_snapshots(user_id, date DESC);
CREATE INDEX idx_daily_unclosed ON daily_snapshots(date, day_closed) WHERE day_closed = false;

COMMENT ON TABLE daily_snapshots IS 'Resumo agregado por usuário/dia. Atualizado por cada refeição/treino.';
COMMENT ON COLUMN daily_snapshots.daily_balance IS 'Positivo = surplus, negativo = déficit.';

CREATE TABLE workout_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_id     uuid REFERENCES daily_snapshots(id) ON DELETE CASCADE,
  workout_type    text,
  duration_min    integer CHECK (duration_min IS NULL OR duration_min > 0),
  estimated_kcal  integer CHECK (estimated_kcal IS NULL OR estimated_kcal >= 0),
  intensity       text,
  notes           text,
  performed_at    timestamptz NOT NULL DEFAULT now(),
  raw_message_id  uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_workouts_user_performed ON workout_logs(user_id, performed_at DESC);

ALTER TABLE workout_logs
  ADD COLUMN IF NOT EXISTS raw_provider_message_id text;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_workout_logs_provider_msg
  ON workout_logs (user_id, raw_provider_message_id, workout_type)
  WHERE raw_provider_message_id IS NOT NULL;

ALTER TABLE daily_snapshots
  ADD COLUMN day_status text NOT NULL DEFAULT 'complete'
    CHECK (day_status IN ('complete', 'user_skipped', 'incomplete_no_response', 'pending_close'));

ALTER TABLE daily_snapshots
  ADD COLUMN gap_reminder_sent_at timestamp with time zone;

-- Índice pra cron de re-check: encontra rapidamente os pending_close vencidos.
CREATE INDEX idx_daily_snapshots_pending_close
  ON daily_snapshots (gap_reminder_sent_at)
  WHERE day_status = 'pending_close';

ALTER TABLE daily_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_logs ENABLE ROW LEVEL SECURITY;

-- Exact original catalogue DDL/comment/GRANT from S3 fixture.
CREATE TABLE IF NOT EXISTS workout_types (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            text NOT NULL UNIQUE,
  display_name    text NOT NULL,
  category        text NOT NULL CHECK (category IN ('musculacao', 'cardio', 'esporte', 'mobilidade')),
  kcal_per_min    numeric(5,2) NOT NULL,  -- pra paciente médio (70kg, intensidade moderada)
  description     text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE workout_types IS
  'Tipos de treino com kcal/min de referência. Replicação do ADR-007: cálculo determinístico em vez de LLM estimar.';

-- Exact original line63: real legacy SELECT authority present before migration.
GRANT SELECT ON workout_types TO authenticated, service_role;

\i :legacy_api_path
\i :legacy_permissions_path
\i :bindings_path
\i :catalogue_path
\i :facts_path
\i :commands_path

-- Test-only own namespace. Helpers forward real SQL; no product fake/matcher.
CREATE SCHEMA c59s8_fixture;
REVOKE ALL ON SCHEMA c59s8_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s8_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,object_oids jsonb NOT NULL,object_fingerprint jsonb NOT NULL);
REVOKE ALL ON TABLE c59s8_fixture.ownership FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s8_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $ok$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S8_ASSERT:%',label;END IF;RAISE NOTICE 'C59S8_PASS:%',label;END $ok$;
CREATE FUNCTION c59s8_fixture.throws(sql text,state text,label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $throws$
DECLARE actual text;BEGIN BEGIN EXECUTE sql;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE;
 PERFORM c59s8_fixture.ok(actual=state,label);RETURN;END;RAISE EXCEPTION 'C59S8_EXPECTED_ERROR:%',label;END $throws$;
CREATE FUNCTION c59s8_fixture.arguments(owner_id uuid,raw text,provider text) RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $args$
 SELECT jsonb_build_object('p_user_id',owner_id::text,'p_date','2026-10-12','p_workout_type',raw,'p_duration_min',60,'p_estimated_kcal',300,
 'p_intensity','moderada','p_notes','S8 preserved notes','p_performed_at','2026-10-12T15:00:00.123456Z','p_provider_message_id',provider,
 'p_calories_target',2000,'p_protein_target',150,'p_replace_recent',false,'p_replace_since',NULL)
$args$;
CREATE FUNCTION c59s8_fixture.admit(owner_id uuid,life uuid,key text,raw text,patch jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
 LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $admit$
 SELECT public.read_or_admit_workout_strength_command(owner_id,life,key,raw,c59s8_fixture.arguments(owner_id,raw,key)||patch)
$admit$;
CREATE FUNCTION c59s8_fixture.decision(obs jsonb,raw text) RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $decision$
 SELECT jsonb_build_object('status','matched','observationKey',obs->'observationKey','matcherVersion',obs->'matcherVersion',
 'originalOperationType',raw,'method','active_slug','selectedRowID','c59a9000-0000-0000-0000-000000009001')
$decision$;
CREATE FUNCTION c59s8_fixture.capture(owner_id uuid,life uuid,key text,raw text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $capture$
DECLARE obs jsonb:=public.get_workout_strength_catalogue_context();BEGIN
 RETURN public.register_workout_strength_atomic(owner_id,life,key,raw,obs,c59s8_fixture.decision(obs,raw));END $capture$;
CREATE FUNCTION c59s8_fixture.legacy(args jsonb) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $legacy$
 SELECT public.register_workout_atomic((args->>'p_user_id')::uuid,(args->>'p_date')::date,args->>'p_workout_type',
 (args->>'p_duration_min')::numeric::integer,(args->>'p_estimated_kcal')::numeric::integer,args->>'p_intensity',args->>'p_notes',
 (args->>'p_performed_at')::timestamptz,args->>'p_provider_message_id',(args->>'p_calories_target')::numeric::integer,
 (args->>'p_protein_target')::numeric,(args->>'p_replace_recent')::boolean,(args->>'p_replace_since')::timestamptz)
$legacy$;
CREATE FUNCTION c59s8_fixture.state(owner_id uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $state$
 SELECT jsonb_build_object('workouts',(SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY id),'[]') FROM public.workout_logs w WHERE user_id=owner_id),
 'snapshots',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM public.daily_snapshots s WHERE user_id=owner_id),
 'facts',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY workout_log_id),'[]') FROM private.workout_strength_facts f WHERE user_id=owner_id),
 'operations',(SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY operation_kind,operation_key,original_operation_type),'[]') FROM private.workout_strength_operations o WHERE user_id=owner_id),
 'commands',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY operation_key,original_operation_type),'[]') FROM private.workout_strength_commands c WHERE user_id=owner_id))
$state$;
CREATE FUNCTION c59s8_fixture.object_oids() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $oids$
 SELECT jsonb_build_object('schema',to_regnamespace('c59s8_fixture')::oid::text,
 'relations',(SELECT jsonb_object_agg(n.nspname||'.'||c.relname,c.oid::text) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND
 ((n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')) OR n.nspname='c59s8_fixture')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,p.oid::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='c59s8_fixture' OR(n.nspname='private' AND p.proname='workout_strength_fact_snapshot') OR(n.nspname='public' AND p.proname IN
 ('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic'))))
$oids$;
CREATE FUNCTION c59s8_fixture.object_fingerprint() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $fingerprint$
 WITH rels AS (SELECT c.* FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND
 ((n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')) OR n.nspname='c59s8_fixture')),
 funcs AS (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='c59s8_fixture'
 OR(n.nspname='private' AND p.proname='workout_strength_fact_snapshot') OR(n.nspname='public' AND p.proname IN
 ('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic')))
 SELECT jsonb_build_object('schema',(SELECT jsonb_build_object('oid',oid::text,'owner',nspowner::text,'acl',nspacl::text) FROM pg_namespace WHERE nspname='c59s8_fixture'),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'definition',pg_get_functiondef(p.oid),'comment',obj_description(p.oid,'pg_proc'))) FROM funcs p),
 'relations',(SELECT jsonb_object_agg(r.oid::regclass::text,jsonb_build_object('oid',r.oid::text,'owner',r.relowner::text,'acl',r.relacl::text,'rls',r.relrowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attcollation::text,pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.conname,pg_get_constraintdef(c.oid,true)) ORDER BY c.conname),'[]') FROM pg_constraint c WHERE c.conrelid=r.oid),
 'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,pg_get_indexdef(i.indexrelid)) ORDER BY i.indexrelid),'[]') FROM pg_index i WHERE i.indrelid=r.oid),
 'policies',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.polname),'[]') FROM pg_policy p WHERE p.polrelid=r.oid))) FROM rels r))
$fingerprint$;
DO $revoke$ DECLARE p record;BEGIN FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='c59s8_fixture'::regnamespace LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.oid::regprocedure);END LOOP;END $revoke$;
INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min,updated_at) VALUES
 ('c59a9000-0000-0000-0000-000000009001','musculacao','Musculação','musculacao',5,'2026-10-10T00:00:00.000001Z'),
 ('c59a9000-0000-0000-0000-000000009002','natacao','Natação','cardio',5,'2026-10-10T00:00:00.000002Z'),
 ('c59a9000-0000-0000-0000-000000009003','outro','Outro','cardio',5,'2026-10-10T00:00:00.000003Z');

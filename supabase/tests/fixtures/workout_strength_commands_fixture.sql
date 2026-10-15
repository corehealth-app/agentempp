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

-- S7 test-only helpers and durable setup identity; no product implementation.
CREATE SCHEMA c59s7_fixture;
REVOKE ALL ON SCHEMA c59s7_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s7_fixture.ownership(
  tag text PRIMARY KEY, owner_name text NOT NULL, object_oids jsonb NOT NULL, object_fingerprint jsonb NOT NULL
);
REVOKE ALL ON TABLE c59s7_fixture.ownership FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s7_fixture.ok(p_ok boolean,p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S7_ASSERT:%',p_label; END IF;
  RAISE NOTICE 'C59S7_PASS:%',p_label;
END $$;
CREATE FUNCTION c59s7_fixture.throws(p_sql text,p_state text,p_message text,p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE s text;m text;
BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    PERFORM c59s7_fixture.ok(s=p_state AND(p_message IS NULL OR m=p_message),p_label);RETURN;
  END;
  RAISE EXCEPTION 'C59S7_EXPECTED_ERROR:%',p_label;
END $$;
CREATE FUNCTION c59s7_fixture.arguments(p_owner uuid,p_raw text) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT jsonb_build_object('p_user_id',p_owner::text,'p_date','2026-10-12','p_workout_type',p_raw,
    'p_duration_min',60,'p_estimated_kcal',300,'p_intensity',NULL,'p_notes',NULL,
    'p_performed_at',NULL,'p_provider_message_id',NULL,'p_calories_target',NULL,
    'p_protein_target',NULL,'p_replace_recent',NULL,'p_replace_since',NULL)
$$;
CREATE FUNCTION c59s7_fixture.object_oids() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object(
   'fixture_schema',to_regnamespace('c59s7_fixture')::oid::text,
   'ownership',to_regclass('c59s7_fixture.ownership')::oid::text,
   'ok',to_regprocedure('c59s7_fixture.ok(boolean,text)')::oid::text,
   'throws',to_regprocedure('c59s7_fixture.throws(text,text,text,text)')::oid::text,
   'arguments',to_regprocedure('c59s7_fixture.arguments(uuid,text)')::oid::text,
   'object_oids',to_regprocedure('c59s7_fixture.object_oids()')::oid::text,
   'object_fingerprint',to_regprocedure('c59s7_fixture.object_fingerprint()')::oid::text,
   'snapshots',to_regclass('public.daily_snapshots')::oid::text,
   'workouts',to_regclass('public.workout_logs')::oid::text,
   'owned_workout_index',to_regclass('public.workout_logs_user_id_id_key')::oid::text,
   'lifecycles',to_regclass('private.workout_strength_lifecycles')::oid::text,
   'operations',to_regclass('private.workout_strength_operations')::oid::text,
   'commands',to_regclass('private.workout_strength_commands')::oid::text,
   'admission',to_regprocedure('public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)')::oid::text)
$$;
CREATE FUNCTION c59s7_fixture.object_fingerprint() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $fingerprint$
 WITH rels AS (
  SELECT c.oid,c.relname,c.relowner,c.relacl,c.relrowsecurity FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs'))
   OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_commands'))
   OR(n.nspname='c59s7_fixture' AND c.relname='ownership')
 ), funcs AS (
  SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='c59s7_fixture' OR(n.nspname='public' AND p.proname='read_or_admit_workout_strength_command')
 )
 SELECT jsonb_build_object(
 'schema',(SELECT jsonb_build_object('oid',oid::text,'owner',nspowner::text,'acl',nspacl::text)
  FROM pg_namespace WHERE nspname='c59s7_fixture'),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'owner',p.proowner::text,
  'acl',p.proacl::text,'definition',pg_get_functiondef(p.oid),'config',p.proconfig,'comment',obj_description(p.oid,'pg_proc'))) FROM funcs p),
 'relations',(SELECT jsonb_object_agg(r.oid::regclass::text,jsonb_build_object('oid',r.oid::text,'owner',r.relowner::text,
  'acl',r.relacl::text,'rls',r.relrowsecurity,'comment',obj_description(r.oid,'pg_class'),
  'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,a.attcollation::text,
    pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
  'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.conname,pg_get_constraintdef(c.oid,true)) ORDER BY c.conname),'[]'::jsonb) FROM pg_constraint c WHERE c.conrelid=r.oid),
  'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,pg_get_indexdef(i.indexrelid)) ORDER BY i.indexrelid),'[]'::jsonb) FROM pg_index i WHERE i.indrelid=r.oid),
  'policies',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.polname),'[]'::jsonb) FROM pg_policy p WHERE p.polrelid=r.oid))) FROM rels r))
$fingerprint$;
REVOKE ALL ON FUNCTION c59s7_fixture.ok(boolean,text),c59s7_fixture.throws(text,text,text,text),
  c59s7_fixture.arguments(uuid,text),c59s7_fixture.object_oids(),c59s7_fixture.object_fingerprint() FROM PUBLIC,anon,authenticated,service_role;

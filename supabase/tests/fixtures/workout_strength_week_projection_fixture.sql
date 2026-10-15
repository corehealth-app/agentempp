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

-- Real closed migrations only; guard/auth shim/users/roles stay in retained baseline.
\i :bindings_path
\i :facts_path
\i :answers_path
\i :calendar_path
CREATE SCHEMA c59s12_fixture;
REVOKE ALL ON SCHEMA c59s12_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s12_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,object_oids jsonb NOT NULL,object_fingerprint jsonb NOT NULL);
REVOKE ALL ON TABLE c59s12_fixture.ownership FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s12_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $ok$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S12_ASSERT:%',label;END IF;RAISE NOTICE 'C59S12_PASS:%',label;END $ok$;
CREATE FUNCTION c59s12_fixture.throws(sql text,state text,label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $throws$
DECLARE actual text;BEGIN BEGIN EXECUTE sql;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE;
 PERFORM c59s12_fixture.ok(actual=state,label);RETURN;END;RAISE EXCEPTION 'C59S12_EXPECTED_ERROR:%',label;END $throws$;
CREATE FUNCTION c59s12_fixture.state(owner_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $state$
 BEGIN RETURN (SELECT jsonb_build_object('user',(SELECT to_jsonb(u) FROM public.users u WHERE id=owner_id),
 'lifecycles',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY lifecycle_key),'[]') FROM private.workout_strength_lifecycles l WHERE user_id=owner_id),
 'facts',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY workout_log_id),'[]') FROM private.workout_strength_facts f WHERE user_id=owner_id),
 'scopes',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY scope_key),'[]') FROM private.workout_strength_calendar_scopes s WHERE user_id=owner_id),
 'operations',(SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY operation_kind,operation_key),'[]') FROM private.workout_strength_operations o WHERE user_id=owner_id),
 'workouts',(SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY id),'[]') FROM public.workout_logs w WHERE user_id=owner_id),
 'snapshots',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY id),'[]') FROM public.daily_snapshots d WHERE user_id=owner_id)));END
$state$;
-- All public/private metadata, not just S11. Retained external full snapshot also covers rows/physical state.
CREATE FUNCTION c59s12_fixture.object_oids() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $oids$
 SELECT jsonb_build_object('schema','c59s12_fixture'::regnamespace::oid::text,
 'relations',(SELECT jsonb_object_agg(n.nspname||'.'||c.relname,c.oid::text) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s12_fixture') AND c.relkind IN('r','p','v','m','S','i','I')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,p.oid::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s12_fixture') AND p.prokind IN('f','p')))
$oids$;
CREATE FUNCTION c59s12_fixture.object_fingerprint() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $fingerprint$
 WITH rels AS (SELECT c.* FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s12_fixture') AND c.relkind IN('r','p','v','m','S')),
 funcs AS (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s12_fixture') AND p.prokind IN('f','p'))
 SELECT jsonb_build_object('schemas',(SELECT jsonb_object_agg(nspname,jsonb_build_object('oid',oid::text,'owner',nspowner::text,'acl',nspacl::text)) FROM pg_namespace WHERE nspname IN('public','private','c59s12_fixture')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'definition',pg_get_functiondef(p.oid),'comment',obj_description(p.oid,'pg_proc'))) FROM funcs p),
 'relations',(SELECT jsonb_object_agg(r.oid::regclass::text,jsonb_build_object('oid',r.oid::text,'owner',r.relowner::text,'acl',r.relacl::text,'kind',r.relkind,'rls',r.relrowsecurity,'forceRls',r.relforcerowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attcollation::text,pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.oid::text,c.conname,pg_get_constraintdef(c.oid,true)) ORDER BY c.conname),'[]') FROM pg_constraint c WHERE c.conrelid=r.oid),
 'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,pg_get_indexdef(i.indexrelid)) ORDER BY i.indexrelid),'[]') FROM pg_index i WHERE i.indrelid=r.oid),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_array(t.oid::text,t.tgname,t.tgenabled,t.tgisinternal,pg_get_triggerdef(t.oid,true)) ORDER BY t.tgname),'[]') FROM pg_trigger t WHERE t.tgrelid=r.oid),
 'policies',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.polname),'[]') FROM pg_policy p WHERE p.polrelid=r.oid))) FROM rels r),
 'sequences',(SELECT coalesce(jsonb_object_agg(c.oid::regclass::text,jsonb_build_object('oid',c.oid::text,'owner',c.relowner::text,'acl',c.relacl::text,'parameters',to_jsonb(s),'lastValue',v.last_value)),'{}') FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_sequences v ON v.schemaname=n.nspname AND v.sequencename=c.relname WHERE n.nspname IN('public','private','c59s12_fixture')))
$fingerprint$;
-- Test-only canonical stored data, not a replacement for any product RPC.
-- Answer races call REAL S9. Projection source does not call this helper.
CREATE FUNCTION c59s12_fixture.seed_fact(owner_id uuid,life uuid,workout_id uuid,day date,classification text,category text DEFAULT NULL,calendar text DEFAULT 'proven',zone text DEFAULT 'UTC') RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $seed$
DECLARE snapshot uuid;raw text:=CASE WHEN classification='matched' THEN 'c59s12_'||category ELSE 'c59s12_'||workout_id::text END;at timestamptz:=(day+TIME '12:00') AT TIME ZONE 'UTC';BEGIN
 INSERT INTO public.daily_snapshots(user_id,date) VALUES(owner_id,day) ON CONFLICT(user_id,date) DO NOTHING;
 SELECT id INTO STRICT snapshot FROM public.daily_snapshots WHERE user_id=owner_id AND date=day;
 INSERT INTO public.workout_logs(id,user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at,created_at) VALUES(workout_id,owner_id,snapshot,raw,60,300,at,clock_timestamp());
 INSERT INTO private.workout_strength_facts(user_id,workout_log_id,lifecycle_key,snapshot_id,stored_workout_type,performed_at,snapshot_date,
 classification_status,classification_reason,observation_key,observed_at,matcher_version,active_row_count,match_method,catalogue_id,catalogue_slug,catalogue_display_name,catalogue_category,catalogue_updated_at,
 calendar_status,calendar_reason,local_date,time_zone,zone_source,zone_observed_at,question_key,answer,answer_operation_key,answer_accepted_at,revision)
 VALUES(owner_id,workout_id,life,snapshot,raw,at,day,classification,
 CASE classification WHEN 'unrecognized' THEN 'no_active_match' WHEN 'unavailable' THEN 'catalogue_read_error' ELSE NULL END,
 CASE WHEN classification<>'unavailable' THEN workout_id ELSE NULL END,CASE WHEN classification<>'unavailable' THEN clock_timestamp() ELSE NULL END,
 CASE WHEN classification<>'unavailable' THEN 'active_slug_then_unique_canonical_display_v1' ELSE NULL END,
 CASE classification WHEN 'matched' THEN 1 WHEN 'unrecognized' THEN 0 ELSE NULL END,
 CASE WHEN classification='matched' THEN 'active_slug' ELSE NULL END,CASE WHEN classification='matched' THEN workout_id ELSE NULL END,
 CASE WHEN classification='matched' THEN 'c59s12_'||category ELSE NULL END,CASE WHEN classification='matched' THEN 'C59S12 stored category' ELSE NULL END,
 CASE WHEN classification='matched' THEN category ELSE NULL END,CASE WHEN classification='matched' THEN at ELSE NULL END,
 calendar,CASE WHEN calendar='unavailable' THEN 'legacy_calendar_gap' ELSE NULL END,CASE WHEN calendar='proven' THEN day ELSE NULL END,
 CASE WHEN calendar='proven' THEN zone ELSE NULL END,CASE WHEN calendar='proven' THEN 'official_owner_zone_at_recording' ELSE NULL END,
 CASE WHEN calendar='proven' THEN clock_timestamp() ELSE NULL END,CASE WHEN classification='unrecognized' THEN workout_id ELSE NULL END,NULL,NULL,NULL,0);
END $seed$;
DO $revoke$DECLARE p record;BEGIN FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='c59s12_fixture'::regnamespace LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.oid::regprocedure);END LOOP;END $revoke$;

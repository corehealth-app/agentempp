-- Backend-only transport, no HTTP or remote access. All synthetic effects roll back.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_no_plan_fixture.sql
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2920,NULL);before_rows jsonb;r jsonb;start_at timestamptz;token jsonb;
 body jsonb:='{"locale":"pt-BR","timezone":"America/Sao_Paulo","sex":"masculino","birth_date":"1990-01-01","height_cm":180,"weight_kg":80,"body_fat_percent":24,"training_frequency":4}';
BEGIN
 before_rows:=m3b_cycle_test.original_state(a);start_at:=clock_timestamp();
 r:=public.get_mobile_current_clinical_state(a,'signup',body,NULL);
 PERFORM m3b_cycle_test.ok(r->>'user_id'=a::text AND r->'body'=body,
  'backend wrapper retains exact owner and typed signup body');
 PERFORM m3b_cycle_test.ok((r->>'observed_at')::timestamptz>=start_at
  AND (r->>'observed_at')::timestamptz<=clock_timestamp(),'wrapper uses only actual server clock');
 PERFORM m3b_cycle_test.ok(r#>>'{phase_origin,kind}'='not_completed'
  AND r->'epoch'='null'::jsonb AND r->'signup_generation'='null'::jsonb,'read does not mint any authority');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
  AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=a),
  'public capture makes no profile epoch receipt or admission writes');
 token:=r->'generation_token';
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_current_clinical_state(%L,''signup'',%L,%L)',a,body,
  jsonb_build_object('generation_token',token||'{"receipt_count":1}')),'40001','public transport retains optimistic generation binding');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_current_clinical_state(%L,''signup'',%L,%L)',a,body,
  jsonb_build_object('epoch',gen_random_uuid())),'40001','public transport retains expected epoch binding');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_current_clinical_state(%L,''profile'',%L,NULL)',a,body),
  '22023','profile transport cannot substitute client body');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_current_clinical_state(%L,''signup'',%L,NULL)',a,body||'{"no_plan":true}'),
  '22023','wrapper never accepts client clinical conclusion');
 PERFORM set_config('request.jwt.claim','{"role":"authenticated"}',true);
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_current_clinical_state(%L,''profile'',NULL,NULL)',a),
  '42501','security definer still refuses untrusted JWT role');
 PERFORM set_config('request.jwt.claim','{"role":"service_role"}',true);
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.uid(2920);caller text;refused boolean;r jsonb;
BEGIN
 FOR caller IN SELECT unnest(ARRAY['anon','authenticated']) LOOP
  refused:=false;
  EXECUTE format('SET LOCAL ROLE %I',caller);
  BEGIN
   PERFORM public.get_mobile_current_clinical_state(a,'profile',NULL,NULL);
  EXCEPTION WHEN insufficient_privilege THEN refused:=true;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM m3b_cycle_test.ok(refused,'actual SQL role '||caller||' cannot call the backend wrapper');
 END LOOP;
 EXECUTE 'SET LOCAL ROLE service_role';
 r:=public.get_mobile_current_clinical_state(a,'profile',NULL,NULL);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(r->>'user_id'=a::text AND r->>'mode'='profile',
  'actual backend service role can call wrapper without private grants');
END $$;
SELECT m3b_cycle_test.ok(has_function_privilege('service_role',
 'public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb)','EXECUTE'),
 'only backend service has wrapper execution');
SELECT m3b_cycle_test.ok(NOT has_function_privilege('anon',
 'public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb)','EXECUTE'),
 'anon and authenticated cannot execute wrapper');
SELECT m3b_cycle_test.ok(NOT has_function_privilege('service_role',
 'private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)','EXECUTE'),
 'private clock helper remains revoked from service');
SELECT m3b_cycle_test.ok((SELECT prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] FROM pg_proc
 WHERE oid='public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb)'::regprocedure),
 'backend wrapper has fixed secure search path');
SELECT m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(pronargs=4) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='get_mobile_current_clinical_state'),
 'no public overload can accept a client clock');
ROLLBACK;

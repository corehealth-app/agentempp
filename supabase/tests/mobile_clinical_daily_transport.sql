-- Actual backend role/transport proof. Synthetic calculation here; the BFF bridge
-- separately uses the real core calculator. Every fixture effect rolls back.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF to_regprocedure('public.get_mobile_clinical_daily_receipt(uuid,uuid)') IS NULL
  OR to_regprocedure('public.get_mobile_clinical_daily_context(uuid)') IS NULL
  OR to_regprocedure('public.apply_mobile_clinical_daily(uuid,uuid,text,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'clinical_daily_backend_transport_missing';
 END IF;
END $$;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_daily_fixture.sql
DO $$
DECLARE a uuid;c jsonb;r jsonb;original jsonb;key uuid:=gen_random_uuid();start_at timestamptz;
 calc jsonb:='{"version":1,"formulaKcal":2400,"maintenanceKcal":2400,"sedentaryKcal":1900,"proteinTarget":144,"maintenanceProteinTarget":144}';
BEGIN
 a:=(m3b_cycle_test.scheduled(2990,'recomp_to_maintenance',clock_timestamp()-interval '6 days')->>'user')::uuid;
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_daily_receipt(a,key) IS NULL,'absent receipt is SQL null, not a failed lookup');
 start_at:=clock_timestamp();c:=public.get_mobile_clinical_daily_context(a);
 PERFORM m3b_cycle_test.ok(c->>'user_id'=a::text AND c->>'review_kind'='APPLICATION' AND c->'cycle_id'='null'::jsonb,'capture is the full APPLICATION context for exact owner');
 PERFORM m3b_cycle_test.ok((c->>'observed_at')::timestamptz>=start_at AND (c->>'observed_at')::timestamptz<=clock_timestamp(),'capture uses actual SQL time without public clock');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_daily_keys WHERE user_id=a),'capture is not a daily acknowledgement');
 EXECUTE 'SET LOCAL ROLE service_role';
 r:=public.apply_mobile_clinical_daily(a,key,c->>'context_hash',calc);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(r->>'user_id'=a::text AND r->>'operation_key'=key::text AND r#>>'{result,availability}'='applied','actual service role applies through the public backend wrapper');
 PERFORM m3b_cycle_test.ok(jsonb_typeof(r#>'{result,application_no}')='string','bigint application sequence remains text');
 original:=public.get_mobile_clinical_daily_receipt(a,key);
 PERFORM m3b_cycle_test.ok(original=r,'receipt wrapper returns the exact stored original envelope');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_daily_receipt(a,key)=original,'original receipt remains readable after actual signup reset');
 PERFORM m3b_cycle_test.ok(public.apply_mobile_clinical_daily(a,key,c->>'context_hash',calc)=original,'same direct apply replay precedes recapture after reset');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_daily_applications WHERE user_id=a),'replay adds no daily application');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_daily_receipt(NULL,%L)',key),'22023','null owner cannot masquerade as missing receipt');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_daily_receipt(%L,NULL)',a),'22023','null operation key is refused');
 PERFORM set_config('request.jwt.claim','{"role":"authenticated"}',true);
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_daily_receipt(%L,%L)',a,key),'42501','definer lookup still validates backend JWT');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_daily_context(%L)',a),'42501','definer capture still validates backend JWT');
 PERFORM m3b_cycle_test.throws(format('SELECT public.apply_mobile_clinical_daily(%L,%L,%L,%L)',a,key,c->>'context_hash',calc),'42501','definer apply still validates backend JWT');
 PERFORM set_config('request.jwt.claim','{"role":"service_role"}',true);
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.uid(2990);caller text;statement text;refused boolean;
BEGIN
 FOR caller IN SELECT unnest(ARRAY['anon','authenticated']) LOOP
  FOREACH statement IN ARRAY ARRAY[
   format('SELECT public.get_mobile_clinical_daily_receipt(%L,%L)',a,gen_random_uuid()),
   format('SELECT public.get_mobile_clinical_daily_context(%L)',a),
   format('SELECT public.apply_mobile_clinical_daily(%L,%L,%L,%L)',a,gen_random_uuid(),repeat('a',64),'{}'::jsonb)
  ] LOOP
   refused:=false;EXECUTE format('SET LOCAL ROLE %I',caller);
   BEGIN EXECUTE statement;EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
   EXECUTE 'RESET ROLE';
   PERFORM m3b_cycle_test.ok(refused,'actual SQL role '||caller||' is denied daily backend RPC');
  END LOOP;
 END LOOP;
 EXECUTE 'SET LOCAL ROLE service_role';
 PERFORM public.get_mobile_clinical_daily_receipt(a,gen_random_uuid());
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(true,'actual service role reads receipt without private-table grant');
END $$;
SELECT m3b_cycle_test.ok((SELECT count(*)=3 AND bool_and(prosecdef AND proconfig=ARRAY['search_path=pg_catalog']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('get_mobile_clinical_daily_receipt','get_mobile_clinical_daily_context','apply_mobile_clinical_daily')),'exactly three secure backend wrappers, no clock overload');
SELECT m3b_cycle_test.ok(NOT has_function_privilege('service_role','private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)','EXECUTE') AND NOT has_function_privilege('service_role','private.apply_mobile_clinical_daily_at(uuid,uuid,text,jsonb,timestamptz)','EXECUTE'),'private context/application clock helpers remain revoked');
SELECT m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_clinical_daily_keys','SELECT'),'service cannot bypass receipt wrapper using private table');
ROLLBACK;

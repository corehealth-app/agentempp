BEGIN;
DO $$ BEGIN IF to_regprocedure('public.admit_mobile_signup_health(uuid,jsonb)') IS NULL THEN RAISE EXCEPTION 'signup_health_transport_missing'; END IF; END $$;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_signup_health_fixture.sql
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(5800,NULL);c jsonb;r jsonb;again jsonb;before_state jsonb;
BEGIN
 c:=m3b_cycle_test.signup_health_command(a,m3b_cycle_test.uid(5801),m3b_cycle_test.uid(5802));
 EXECUTE 'SET LOCAL ROLE service_role';
 r:=public.admit_mobile_signup_health(a,c);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(r#>>'{receipt,intent_id}'=c->>'intent_id' AND r#>>'{declaration,state,hold_active}'='true','backend transport admits exact consent/risk/intent atomically');
 before_state:=m3b_cycle_test.original_state(a);
 again:=public.admit_mobile_signup_health(a,c);
 PERFORM m3b_cycle_test.ok(again=r AND m3b_cycle_test.original_state(a)=before_state,'same-key public replay adds no health/legal act');
 PERFORM m3b_cycle_test.throws(format('SELECT public.admit_mobile_signup_health(%L,%L)',a,c||jsonb_build_object('weight_kg',80)),'22023','transport cannot save ordinary signup answers');
 PERFORM public.reset_user_conversation_atomic(a,true);
 before_state:=m3b_cycle_test.original_state(a);
 again:=public.admit_mobile_signup_health(a,c);
 PERFORM m3b_cycle_test.ok(again->'receipt'=r->'receipt' AND m3b_cycle_test.original_state(a)=before_state,'old epoch returns original receipt without rearming health or restoring profile');
 PERFORM m3b_cycle_test.throws(format('SELECT public.admit_mobile_signup_health(%L,%L)',a,c||jsonb_build_object('operation_key',gen_random_uuid())),'40001','new operation cannot use an old signup epoch');
 PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.admit_mobile_signup_health(uuid,jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.admit_mobile_signup_health(uuid,jsonb)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.admit_mobile_signup_health(uuid,jsonb)','EXECUTE')
  AND NOT has_function_privilege('service_role','private.admit_mobile_signup_health(uuid,jsonb)','EXECUTE')
  AND NOT has_table_privilege('service_role','private.mobile_signup_health_receipts','SELECT,INSERT,UPDATE,DELETE'),'one narrow backend transport leaves private authority/table grants closed');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(prosecdef AND 'search_path=pg_catalog'=ANY(proconfig) AND 'lock_timeout=2s'=ANY(proconfig))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admit_mobile_signup_health'),'no public clock or alternate health transport overload');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 PERFORM m3b_cycle_test.throws(format('SELECT public.admit_mobile_signup_health(%L,%L)',a,c),'42501','untrusted JWT cannot invoke definer even from the owner SQL harness');
END $$;
ROLLBACK;

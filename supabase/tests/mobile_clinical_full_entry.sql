BEGIN;
DO $$ BEGIN
 IF to_regprocedure('public.start_mobile_clinical_full(uuid,uuid,text)') IS NULL THEN RAISE EXCEPTION 'full_entry_missing'; END IF;
END $$;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_full_fixture.sql
DO $$
DECLARE a uuid;before_state jsonb;state jsonb;again jsonb;early_key uuid:=gen_random_uuid();resume_key uuid:=gen_random_uuid();cycle text;refused boolean;
BEGIN
 a:=m3b_cycle_test.seed(4800,clock_timestamp()-interval '6 days');
 before_state:=public.get_mobile_reevaluation_cycle(a);
 state:=public.start_mobile_clinical_full(a,gen_random_uuid(),NULL);
 PERFORM m3b_cycle_test.ok(state->>'unavailable_reason'='not_due' AND state->'cycle'='null'::jsonb,'null reason uses server clock and does not open early');
 state:=public.start_mobile_clinical_full(a,early_key,'not_well_with_plan');cycle:=state#>>'{cycle,id}';
 PERFORM m3b_cycle_test.ok(state->>'availability'='available' AND state#>>'{cycle,kind}'='EARLY_FULL' AND cycle IS NOT NULL,'explicit early reason opens actual early occurrence');
 again:=public.start_mobile_clinical_full(a,early_key,'not_well_with_plan');
 PERFORM m3b_cycle_test.ok(again=state,'same early key and reason reuse actual occurrence');
 state:=public.start_mobile_clinical_full(a,resume_key,NULL);
 PERFORM m3b_cycle_test.ok(state#>>'{cycle,id}'=cycle AND state#>>'{cycle,kind}'='EARLY_FULL','fresh resume key without a client kind reuses unexpired early');
 PERFORM m3b_cycle_test.throws(format('SELECT public.start_mobile_clinical_full(%L,%L,NULL)',a,early_key),'40001','changing an original early reason into resume cannot reuse its old key');
 PERFORM m3b_cycle_test.throws(format('SELECT public.start_mobile_clinical_full(%L,%L,''client_date_or_kind'')',a,gen_random_uuid()),'22023','unknown early reason rejected');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.throws(format('SELECT public.start_mobile_clinical_full(%L,%L,NULL)',a,resume_key),'40001','reset does not resurrect old cycle scope');

 a:=m3b_cycle_test.seed(4801,clock_timestamp()-interval '15 days');
 state:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',clock_timestamp()-interval '9 days');
 cycle:=state#>>'{cycle,id}';
 state:=public.start_mobile_clinical_full(a,gen_random_uuid(),NULL);
 PERFORM m3b_cycle_test.ok(state#>>'{cycle,id}'=cycle AND state#>>'{cycle,kind}'='REGULAR' AND (state#>>'{cycle,revision}')::bigint=2,'public server-clock resume promotes overdue early to regular with same id');
 PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.start_mobile_clinical_full(uuid,uuid,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.start_mobile_clinical_full(uuid,uuid,text)','EXECUTE'),'full entry is trusted backend only');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(prosecdef AND 'search_path=pg_catalog'=ANY(proconfig) AND 'lock_timeout=2s'=ANY(proconfig))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='start_mobile_clinical_full'),'one narrow definer without public clock overload');
END $$;
ROLLBACK;

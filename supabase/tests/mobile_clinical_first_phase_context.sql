BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_no_plan_fixture.sql
DO $$
DECLARE signup jsonb:=m3b_cycle_test.no_plan_signup(2850);a uuid:=(signup->>'user')::uuid;
 c jsonb;old jsonb;cycle uuid;q jsonb;k uuid;first_hash text;
BEGIN
 old:=m3b_cycle_test.original_state(a);c:=public.get_mobile_clinical_first_phase_context(a);
 PERFORM m3b_cycle_test.ok(c->>'review_kind'='FIRST_PHASE' AND c->>'cycle_id' IS NULL
  AND c#>>'{facts,protocol_authority,phase_origin,kind}'='confirmed_no_plan'
  AND c#>>'{facts,safety,hold_active}'='true','dedicated current no-plan capture retains the actual health block');
 PERFORM m3b_cycle_test.ok(old=m3b_cycle_test.original_state(a),'capture is effect-free for profile targets calendar XP and receipts');
 first_hash:=c->>'context_hash';
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);PERFORM m3b_cycle_test.no_plan_confirm(a,q);
 old:=m3b_cycle_test.original_state(a);c:=public.get_mobile_clinical_first_phase_context(a);
 PERFORM m3b_cycle_test.ok(c#>>'{facts,safety,hold_active}'='false' AND c->>'context_hash'<>first_hash
  AND c#>>'{facts,profile,current_protocol}' IS NULL AND c#>'{facts,protocol_authority,episode}'='null'::jsonb,
  'actual health FULL changes the context without selecting a first phase');
 PERFORM m3b_cycle_test.ok(old=m3b_cycle_test.original_state(a),'cleared first-phase capture adds no occurrence target or episode');
 PERFORM m3b_cycle_test.ok((c#>>'{facts,first_phase,effective_date}')::date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
  AND (c->>'valid_until')::timestamptz<=(c->>'observed_at')::timestamptz+interval '15minutes',
  'first preview applies today and expires before the actual civil or fifteen-minute boundary');
 first_hash:=c->>'context_hash';
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,day_closed,closed_at)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1900,120,true,clock_timestamp());
 old:=m3b_cycle_test.original_state(a);c:=public.get_mobile_clinical_first_phase_context(a);
 PERFORM m3b_cycle_test.ok((c#>>'{facts,first_phase,effective_date}')::date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date+1
  AND c#>>'{facts,day,calories_target}'='1900' AND c->>'context_hash'<>first_hash AND old=m3b_cycle_test.original_state(a),
  'closed day remains byte-exact and the candidate starts on the next civil day');
 first_hash:=c->>'context_hash';
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 c:=public.get_mobile_clinical_first_phase_context(a);
 PERFORM m3b_cycle_test.ok(c->>'context_hash'<>first_hash AND c#>>'{facts,safety,hold_active}'='true',
  'new risk changes the first-phase authority fingerprint');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_first_phase_context(%L)',a),
  '40001','reset cannot reuse the earlier no-plan completion as first-phase authority');
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2851,clock_timestamp());
BEGIN
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_first_phase_context(%L)',a),
  '40001','legacy unassigned NULL is not a genuine first-phase origin');
END $$;
DO $$
DECLARE role_name text;denied boolean;a uuid:=m3b_cycle_test.uid(2850);
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege(role_name,'public.get_mobile_clinical_first_phase_context(uuid)','EXECUTE'),
   'untrusted clients cannot read the private first-phase capture');
  EXECUTE format('SET LOCAL ROLE %I',role_name);denied:=false;
  BEGIN PERFORM public.get_mobile_clinical_first_phase_context(a);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(denied,'actual client role cannot call first-phase RPC');
 END LOOP;
 PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role','private.capture_mobile_clinical_first_phase_at(uuid,timestamptz)','EXECUTE'),
  'backend cannot supply a private first-phase clock');
 EXECUTE 'SET LOCAL ROLE service_role';denied:=false;
 BEGIN PERFORM private.capture_mobile_clinical_first_phase_at(a,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(denied,'actual backend role cannot call first-phase clock helper');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

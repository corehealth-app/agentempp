BEGIN;
SET LOCAL request.jwt.claim='{"role":"service_role"}';
DO $$ BEGIN IF to_regclass('private.mobile_clinical_signup_applications') IS NULL THEN
 RAISE EXCEPTION 'signup_target_authority_missing'; END IF; END $$;
\ir fixtures/mobile_clinical_signup_targets_fixture.sql
DO $$
DECLARE c jsonb;a uuid;context jsonb;calculation jsonb;ack jsonb;origin jsonb;phase text;n integer:=6300;before_rows jsonb;key uuid;
BEGIN
 FOREACH phase IN ARRAY ARRAY['recomposicao','manutencao','ganho_massa'] LOOP
  c:=m3b_cycle_test.signup_target_context(n,phase);n:=n+1;a:=(c->>'user')::uuid;
  PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a),'genuine signup has no fabricated FULL or event');
  context:=public.get_mobile_clinical_daily_context(a);
  calculation:='{"version":1,"formulaKcal":2000,"maintenanceKcal":2500,"sedentaryKcal":1900,"proteinTarget":144,"maintenanceProteinTarget":144}';
  key:=gen_random_uuid();ack:=public.apply_mobile_clinical_daily(a,key,context->>'context_hash',calculation);
  PERFORM m3b_cycle_test.ok(ack#>>'{result,availability}'='applied' AND ack#>>'{result,source_kind}'='signup'
   AND ack#>'{result,source_review_id}'='null'::jsonb AND ack#>>'{result,source_signup_id}'=c->>'generation',phase||' source is actual signup rather than a fake review');
  PERFORM m3b_cycle_test.ok((SELECT calories_target=2000 AND protein_target=144 AND current_protocol::text=phase
   FROM public.daily_snapshots WHERE user_id=a),phase||' first target actually materialized');
  origin:=private.mobile_clinical_target_origin(a,(c->>'generation')::uuid,(c->>'epoch')::uuid,(context#>>'{facts,calculation_date}')::date,clock_timestamp());
  PERFORM m3b_cycle_test.ok(origin->>'source'='clinical_signup_v1' AND origin->>'signup_application_id'=ack#>>'{result,application_id}'
   AND origin->>'review_id' IS NULL AND origin->>'application_id' IS NULL,phase||' actual target origin has exactly one signup application source');
  before_rows:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_daily_receipt(a,key)=ack,phase||' shared transport finds initial original ACK');
  PERFORM m3b_cycle_test.ok(public.apply_mobile_clinical_daily(a,key,context->>'context_hash',calculation)=ack
   AND m3b_cycle_test.original_state(a)=before_rows,phase||' replay cannot duplicate first target/origin/receipt');
  context:=public.get_mobile_clinical_daily_context(a);
  PERFORM public.apply_mobile_clinical_daily(a,gen_random_uuid(),context->>'context_hash',calculation);
  PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_signup_applications WHERE user_id=a)
   AND (SELECT count(*)=1 FROM private.mobile_clinical_target_origins WHERE user_id=a),phase||' another operation key acknowledges the same unchanged target application');
 END LOOP;
END $$;
DO $$
DECLARE c jsonb;a uuid;context jsonb;ack jsonb;before_rows jsonb;caller text;refused boolean;
 calculation jsonb:='{"version":1,"formulaKcal":2000,"maintenanceKcal":2500,"sedentaryKcal":1900,"proteinTarget":144,"maintenanceProteinTarget":144}';
BEGIN
 c:=m3b_cycle_test.signup_target_context(6320,'manutencao');a:=(c->>'user')::uuid;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 context:=public.get_mobile_clinical_daily_context(a);
 ack:=public.apply_mobile_clinical_daily(a,gen_random_uuid(),context->>'context_hash',jsonb_build_object('version',1,
  'formulaKcal',NULL,'maintenanceKcal',NULL,'sedentaryKcal',NULL,'proteinTarget',NULL,'maintenanceProteinTarget',NULL));
 PERFORM m3b_cycle_test.ok(ack#>>'{result,reason}'='safety' AND ack#>'{result,targets,calories_target}'='null'::jsonb
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a),'assigned HOLD before first target never fabricates a calorie target or calculation origin');
 c:=m3b_cycle_test.signup_target_context(6321,NULL);a:=(c->>'user')::uuid;
 context:=public.get_mobile_clinical_daily_context(a);
 ack:=public.apply_mobile_clinical_daily(a,gen_random_uuid(),context->>'context_hash',calculation);
 PERFORM m3b_cycle_test.ok(ack#>>'{result,availability}'='unavailable' AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_applications WHERE user_id=a),'confirmed no-plan signup cannot create a target application');
 c:=m3b_cycle_test.signup_target_context(6322,'recomposicao');a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories,xp_earned)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,NULL,NULL,'recomposicao',550,100,15);
 context:=public.get_mobile_clinical_daily_context(a);ack:=public.apply_mobile_clinical_daily(a,gen_random_uuid(),context->>'context_hash',calculation);
 PERFORM m3b_cycle_test.ok((SELECT calories_target=2000 AND protein_target=144 AND calories_consumed=550 AND exercise_calories=100 AND xp_earned=15
  FROM public.daily_snapshots WHERE user_id=a),'NULL first targets materialize without changing intake/workouts/XP');
 c:=m3b_cycle_test.signup_target_context(6323,'recomposicao');a:=(c->>'user')::uuid;
 context:=public.get_mobile_clinical_daily_context(a);UPDATE public.user_profiles SET weight_kg=81 WHERE user_id=a;
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.apply_mobile_clinical_daily(%L,%L,%L,%L)',a,gen_random_uuid(),context->>'context_hash',calculation),'40001','profile change after capture rejects initial application');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)=before_rows,'stale initial command has zero partial target/origin/application effects');
 FOREACH caller IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(caller,'private.mobile_clinical_signup_applications','SELECT,INSERT,UPDATE,DELETE')
   AND NOT has_table_privilege(caller,'private.mobile_clinical_signup_application_keys','SELECT,INSERT,UPDATE,DELETE'),'initial authority has no direct client/backend table privileges');
  refused:=false;EXECUTE format('SET LOCAL ROLE %I',caller);
  BEGIN PERFORM private.apply_mobile_clinical_signup_targets(a,gen_random_uuid(),context,calculation);
   EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
  EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(refused,'actual restricted role cannot call private signup writer');
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN('private.mobile_clinical_signup_applications'::regclass,
  'private.mobile_clinical_signup_application_keys'::regclass)),'both initial authority tables enable RLS');
END $$;
CREATE FUNCTION m3b_cycle_test.fail_after_signup_target_origin() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN
 IF NEW.signup_application_id IS NOT NULL AND NEW.user_id=m3b_cycle_test.uid(6340) THEN RAISE EXCEPTION 'synthetic_after_initial_origin';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER zzz_initial_target_test_failure AFTER INSERT ON private.mobile_clinical_target_origins
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_after_signup_target_origin();
DO $$
DECLARE c jsonb;a uuid;context jsonb;before_rows jsonb;key uuid:=gen_random_uuid();
 calculation jsonb:='{"version":1,"formulaKcal":2000,"maintenanceKcal":2500,"sedentaryKcal":1900,"proteinTarget":144,"maintenanceProteinTarget":144}';
BEGIN
 c:=m3b_cycle_test.signup_target_context(6340,'recomposicao');a:=(c->>'user')::uuid;context:=public.get_mobile_clinical_daily_context(a);
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.apply_mobile_clinical_daily(%L,%L,%L,%L)',a,key,context->>'context_hash',calculation),'P0001','later failure occurs after initial target/application/origin inserts');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)=before_rows,'later failure rolls back the whole first-target write');
 EXECUTE 'DROP TRIGGER zzz_initial_target_test_failure ON private.mobile_clinical_target_origins';
 PERFORM public.apply_mobile_clinical_daily(a,key,context->>'context_hash',calculation);
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_signup_applications WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_clinical_target_origins WHERE user_id=a),'same failed initial key can complete once after rollback');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_signup_applications SET reason=reason WHERE user_id=%L',a),'55000','initial application immutable even for equal update');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_signup_application_keys WHERE user_id=%L',a),'55000','initial operation keys cannot be independently erased');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

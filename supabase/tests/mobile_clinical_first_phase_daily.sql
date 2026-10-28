-- Explicit synthetic server numbers / private clocks; not core or device QA.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='private'
  AND table_name='mobile_clinical_daily_applications' AND column_name='source_first_phase_id') THEN
  RAISE EXCEPTION 'M3B_ASSERT:first_phase_daily_source_missing';END IF;
END $$;
\ir fixtures/mobile_clinical_first_phase_fixture.sql
CREATE FUNCTION m3b_cycle_test.first_daily(a uuid,at_time timestamptz,k uuid DEFAULT gen_random_uuid()) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c jsonb:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,at_time);
BEGIN
 RETURN private.apply_mobile_clinical_daily_at(a,k,c->>'context_hash',
  '{"version":1,"formulaKcal":1500,"maintenanceKcal":2600,"sedentaryKcal":1800,"proteinTarget":130,"maintenanceProteinTarget":145.8}',at_time);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2870);a uuid:=(q->>'user')::uuid;r jsonb;d jsonb;old_day jsonb;
 at_time timestamptz:=clock_timestamp()+interval '1 day';g uuid;e uuid;o jsonb;before_rows jsonb;
BEGIN
 r:=m3b_cycle_test.first_phase_confirm(q);
 SELECT to_jsonb(s) INTO old_day FROM public.daily_snapshots s WHERE user_id=a;
 d:=m3b_cycle_test.first_daily(a,at_time);
 PERFORM m3b_cycle_test.ok(d->>'source_kind'='first_phase' AND d->>'source_review_id' IS NULL
  AND d->>'source_first_phase_id'=r#>>'{result,first_phase_id}' AND d->>'reason'='episode_formula'
  AND d#>>'{targets,calories_target}'='1500','next civil day uses actual first-phase source without a FULL');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(source_review_id IS NULL AND source_first_phase_id IS NOT NULL)
  FROM private.mobile_clinical_daily_applications WHERE user_id=a) AND (SELECT count(*)=1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a),'daily first source preserves real FULL count and day events');
 PERFORM m3b_cycle_test.ok(old_day=(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id=a AND date=(old_day->>'date')::date),
  'new day leaves original applied snapshot exact');
 SELECT signup_generation,signup_epoch INTO g,e FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=a;
 o:=private.mobile_clinical_target_origin(a,g,e,(d->>'date')::date,at_time);
 PERFORM m3b_cycle_test.ok(o->>'source'='clinical_daily_v1' AND o->>'application_id'=d->>'application_id'
  AND o->>'deficit_level'='500','new daily origin preserves proven entry deficit for historical close');
 before_rows:=m3b_cycle_test.original_state(a);d:=m3b_cycle_test.first_daily(a,at_time);
 PERFORM m3b_cycle_test.ok((before_rows-'private.mobile_clinical_daily_keys')=(m3b_cycle_test.original_state(a)-'private.mobile_clinical_daily_keys'),
  'same-day alias adds only daily acknowledgement key');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2871,'manutencao',true);a uuid:=(q->>'user')::uuid;r jsonb;d jsonb;old_day jsonb;
 at_time timestamptz:=clock_timestamp()+interval '1 day';g uuid;e uuid;o jsonb;
BEGIN
 SELECT to_jsonb(s) INTO old_day FROM public.daily_snapshots s WHERE user_id=a;
 r:=m3b_cycle_test.first_phase_confirm(q);d:=m3b_cycle_test.first_daily(a,at_time);
 PERFORM m3b_cycle_test.ok(d->>'reason'='confirmed_target' AND d#>>'{targets,calories_target}'='2471'
  AND d#>>'{targets,formula_target}'='2471' AND d#>>'{episode,maintenance_since}'=d->>'date',
  'closed initial maintenance applies original approved target and establishes R only on actual future application');
 SELECT signup_generation,signup_epoch INTO g,e FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=a;
 o:=private.mobile_clinical_target_origin(a,g,e,(d->>'date')::date,at_time);
 PERFORM m3b_cycle_test.ok(o->>'source'='clinical_daily_v1' AND o->>'origin_kind'='confirmed'
  AND o->>'decision_review_id' IS NULL AND o->>'decision_first_phase_id'=r#>>'{result,first_phase_id}',
  'confirmed daily target retains genuine first decision without a fabricated FULL decision');
 PERFORM m3b_cycle_test.ok(old_day=(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id=a AND date=(old_day->>'date')::date),
  'future maintenance application never edits closed day');
 d:=m3b_cycle_test.first_daily(a,at_time+interval '1 day');
 PERFORM m3b_cycle_test.ok(d->>'reason'='episode_formula' AND d#>>'{targets,calories_target}'='1800'
  AND (d#>>'{episode,maintenance_since}')::date=(d->>'date')::date-1,
  'subsequent maintenance daily formula preserves previously established R');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2872,'manutencao',true);a uuid:=(q->>'user')::uuid;d jsonb;
 at_time timestamptz:=clock_timestamp()+interval '1 day';
BEGIN
 PERFORM m3b_cycle_test.first_phase_confirm(q);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 d:=m3b_cycle_test.first_daily(a,at_time);
 PERFORM m3b_cycle_test.ok(d->>'reason'='safety' AND d#>'{targets,calories_target}'='1900'::jsonb
  AND d#>'{episode,maintenance_since}'='null'::jsonb,'new HOLD preserves baseline and cannot establish maintenance R');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a AND application_id IS NOT NULL),
  'unproven preserved baseline receives no invented formula origin');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

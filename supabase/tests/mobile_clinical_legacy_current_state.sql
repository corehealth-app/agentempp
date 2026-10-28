\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
DO $legacy$
DECLARE n integer;a uuid;known_marker boolean;assigned boolean;marker timestamptz;
 before_rows jsonb;r jsonb;admission jsonb;
BEGIN
 FOR n IN 2990..2993 LOOP
  known_marker:=n%2=0;assigned:=n<2992;
  marker:=CASE WHEN known_marker THEN '2026-10-01T23:00:00Z'::timestamptz END;
  a:=m3b_cycle_test.seed(n,marker,'America/Sao_Paulo',false);
  UPDATE public.user_profiles SET onboarding_completed=true,sex='masculino',birth_date='1990-01-01',
   height_cm=180,weight_kg=80,body_fat_percent=24,activity_level='moderado',training_frequency=4,
   hunger_level='moderada',current_protocol=CASE WHEN assigned THEN 'recomposicao'::public.protocol_enum END,
   deficit_level=CASE WHEN assigned THEN 500 END WHERE user_id=a;
  before_rows:=m3b_cycle_test.original_state(a);
  r:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
  PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
   AND NOT(r ? 'generation_authority') AND r->'epoch'='null'::jsonb,
   'unadmitted_legacy_capture_is_observational_'||n);
  admission:=private.admit_mobile_clinical_legacy_generation_at(a,NULL);
  before_rows:=m3b_cycle_test.original_state(a);
  r:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
  PERFORM m3b_cycle_test.ok(r#>>'{generation_authority,kind}'='legacy_transition'
   AND r->'signup_generation'=admission#>'{authority,generation}'
   AND r->'epoch'=admission#>'{authority,epoch}' AND r->'first_completion'='false'::jsonb
   AND r#>>'{generation_token,onboarding_completed}'='true'
   AND (r#>>'{generation_token,onboarding_completed_at}')::timestamptz IS NOT DISTINCT FROM marker,
   'current_reader_consumes_actual_admission_without_inventing_old_marker_'||n);
  PERFORM m3b_cycle_test.ok(r#>>'{phase_origin,kind}'=(CASE WHEN assigned THEN 'assigned' ELSE 'legacy_unassigned' END)
   AND before_rows=m3b_cycle_test.original_state(a)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),
   'current_reader_creates_no_signup_frequency_targets_or_profile_changes_'||n);
  PERFORM public.reset_user_conversation_atomic(a,true);
  r:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
  -- The existing reset clears the old completion stamp only for a genuine
  -- signup receipt. Legacy known stamps are preserved, never normalized here.
  PERFORM m3b_cycle_test.ok(r#>>'{phase_origin,kind}'='not_completed'
   AND r->'first_completion'=to_jsonb(marker IS NULL)
   AND r#>>'{generation_token,onboarding_completed}'='false'
   AND (r#>>'{generation_token,onboarding_completed_at}')::timestamptz IS NOT DISTINCT FROM marker
   AND NOT(r ? 'generation_authority') AND r->'signup_generation'='null'::jsonb,
   'reset_invalidates_current_legacy_authority_without_fabricated_completion_'||n);
 END LOOP;
END $legacy$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

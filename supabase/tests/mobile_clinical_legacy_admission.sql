\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

-- An admission is a present boundary, never a reconstructed first signup.
DO $legacy$
DECLARE a uuid; b uuid; d jsonb; again jsonb; before_state jsonb; neighbor_state jsonb;
 observed timestamptz:=clock_timestamp();
BEGIN
 a:=m3b_cycle_test.seed(2951,'2026-10-01T23:00:00Z','America/Sao_Paulo',false);
 b:=m3b_cycle_test.seed(2952,'2026-10-02T23:00:00Z','America/Sao_Paulo',false);
 before_state:=m3b_cycle_test.original_state(a);
 neighbor_state:=m3b_cycle_test.original_state(b);
 d:=private.admit_mobile_clinical_legacy_generation_at(a,observed);
 PERFORM m3b_cycle_test.ok(d->>'availability'='admitted'
  AND d#>>'{authority,kind}'='legacy_transition'
  AND d#>>'{authority,user_id}'=a::text,'legacy_present_admission_has_honest_origin');
 PERFORM m3b_cycle_test.ok((d#>>'{authority,admitted_at}')::timestamptz=observed
  AND d#>>'{authority,admitted_date}'=(observed AT TIME ZONE 'America/Sao_Paulo')::date::text
  AND d#>>'{authority,timezone_at_admission}'='America/Sao_Paulo',
  'legacy_admission_records_current_civil_boundary_not_old_signup');
 PERFORM m3b_cycle_test.ok(
  m3b_cycle_test.original_state(a)-'private.workout_strength_authority_epochs'-'private.mobile_clinical_legacy_admissions'-'private.mobile_clinical_generation_sources'
  =before_state-'private.workout_strength_authority_epochs'-'private.mobile_clinical_legacy_admissions'-'private.mobile_clinical_generation_sources',
  'legacy_admission_preserves_all_existing_user_rows');
 PERFORM m3b_cycle_test.ok(
  NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_request_admissions WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a),
  'legacy_admission_does_not_forge_signup_frequency_or_full');
 again:=private.admit_mobile_clinical_legacy_generation_at(a,observed+interval '1 day');
 PERFORM m3b_cycle_test.ok(d=again AND
  (SELECT count(*)=1 FROM private.mobile_clinical_legacy_admissions WHERE user_id=a),
  'same_epoch_reuses_exact_original_admission');
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,observed)=d->'authority'
  AND private.read_mobile_clinical_legacy_generation_at(b,observed) IS NULL,
  'legacy_observation_is_owner_bound_and_does_not_initialize_neighbor');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(b)=neighbor_state
  AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=b),
  'legacy_neighbor_stays_without_epoch');
 UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=a;
 PERFORM m3b_cycle_test.ok(private.admit_mobile_clinical_legacy_generation_at(a,observed+interval '1 day')=d,
  'admission_timezone_does_not_drift_with_mutable_profile');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_legacy_admissions SET timezone_at_admission=''UTC'' WHERE user_id=%L',a),
  '55000','legacy_admission_is_immutable');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_legacy_admissions WHERE user_id=%L',a),
  '55000','legacy_admission_not_deleted_while_owner_exists');
 UPDATE public.user_profiles SET onboarding_completed=false WHERE user_id=a;
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,observed) IS NULL,
  'reset_completed_flag_invalidates_observed_admission');
 PERFORM m3b_cycle_test.ok(private.admit_mobile_clinical_legacy_generation_at(a,observed)->>'reason'='onboarding_incomplete',
  'reset_does_not_re_admit_incomplete_profile');
 UPDATE public.user_profiles SET onboarding_completed=true,onboarding_completed_at='2026-10-03T23:00:00Z' WHERE user_id=a;
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,observed) IS NULL,
  'changed_completion_marker_invalidates_admission_without_historical_claim');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_clinical_legacy_generation_at(%L,%L)',a,observed),
  '40001','same_epoch_changed_completion_marker_refuses_rebinding');
 UPDATE private.workout_strength_authority_epochs e SET epoch=gen_random_uuid(),changed_at=observed WHERE e.user_id=a;
 again:=private.admit_mobile_clinical_legacy_generation_at(a,observed);
 PERFORM m3b_cycle_test.ok(again#>>'{authority,generation}'<>d#>>'{authority,generation}'
  AND again#>>'{authority,epoch}'<>d#>>'{authority,epoch}'
  AND (SELECT count(*)=2 FROM private.mobile_clinical_legacy_admissions WHERE user_id=a),
  'new_epoch_gets_new_present_generation_preserving_old_evidence');
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,observed)=again->'authority',
  'only_current_epoch_is_observable');
END $legacy$;

DO $proven$
DECLARE a uuid; before_state jsonb; d jsonb;
BEGIN
 a:=m3b_cycle_test.seed(2953,'2026-10-01T23:00:00Z');
 before_state:=m3b_cycle_test.original_state(a);
 d:=private.admit_mobile_clinical_legacy_generation_at(a,clock_timestamp());
 PERFORM m3b_cycle_test.ok(d->>'availability'='signup_proven'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_legacy_admissions WHERE user_id=a)
  AND m3b_cycle_test.original_state(a)=before_state,
  'genuine_signup_keeps_original_authority_and_creates_no_legacy_admission');
 UPDATE public.user_profiles SET onboarding_completed_at='2026-10-02T23:00:00Z' WHERE user_id=a;
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_clinical_legacy_generation_at(%L,NULL)',a),
  'XX001','corrupt_current_signup_receipt_is_not_rescued_as_legacy');
 a:=m3b_cycle_test.seed(2954,NULL);
 before_state:=m3b_cycle_test.original_state(a);
 d:=private.admit_mobile_clinical_legacy_generation_at(a,NULL);
 PERFORM m3b_cycle_test.ok(d->>'reason'='onboarding_incomplete'
  AND m3b_cycle_test.original_state(a)=before_state,
  'fresh_incomplete_signup_is_never_legacy_initialized');
 a:=m3b_cycle_test.seed(2956,NULL);
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 before_state:=m3b_cycle_test.original_state(a);
 d:=private.admit_mobile_clinical_legacy_generation_at(a,NULL);
 PERFORM m3b_cycle_test.ok(d->>'availability'='admitted'
  AND d#>'{authority,profile_completed_marker}'='null'::jsonb,
  'completed_legacy_without_old_timestamp_gets_honest_present_admission');
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,NULL)=d->'authority'
  AND m3b_cycle_test.original_state(a)-'private.workout_strength_authority_epochs'-'private.mobile_clinical_legacy_admissions'-'private.mobile_clinical_generation_sources'
  =before_state-'private.workout_strength_authority_epochs'-'private.mobile_clinical_legacy_admissions'-'private.mobile_clinical_generation_sources',
  'unknown_legacy_date_and_null_phase_remain_unknown_after_admission');
 a:=m3b_cycle_test.seed(2955,'2026-10-01T23:00:00Z','America/Sao_Paulo',false);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
  VALUES(a,gen_random_uuid(),'2026-10-02T23:00:00Z');
 before_state:=m3b_cycle_test.original_state(a)->'private.workout_strength_authority_epochs';
 d:=private.admit_mobile_clinical_legacy_generation_at(a,NULL);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)->'private.workout_strength_authority_epochs'=before_state,
  'existing_shared_epoch_is_preserved');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_clinical_legacy_generation_at(%L,''2026-10-02T22:00:00Z'')',a),
  '40001','admission_replay_rejects_reversed_clock');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_clinical_legacy_generation_at(%L,''infinity'')',a),
  '22023','nonfinite_clock_rejected');
 PERFORM m3b_cycle_test.throws('SELECT private.admit_mobile_clinical_legacy_generation_at(NULL,NULL)',
  '22023','null_legacy_owner_rejected');
 UPDATE public.users SET status='blocked' WHERE id=a;
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,NULL) IS NULL,
  'inactive_owner_cannot_observe_admission');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_clinical_legacy_generation_at(%L,NULL)',a),
  'P0002','inactive_owner_cannot_admit');
END $proven$;

DO $security$
DECLARE role_name text; fn text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(role_name,'private.mobile_clinical_legacy_admissions','SELECT,INSERT,UPDATE,DELETE'),
   'legacy_private_table_acl_'||role_name);
  FOREACH fn IN ARRAY ARRAY[
   'private.admit_mobile_clinical_legacy_generation_at(uuid,timestamptz)',
   'private.read_mobile_clinical_legacy_generation_at(uuid,timestamptz)'] LOOP
   PERFORM m3b_cycle_test.ok(NOT has_function_privilege(role_name,fn,'EXECUTE'),
    'legacy_private_function_acl_'||role_name||'_'||fn);
  END LOOP;
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.mobile_clinical_legacy_admissions'::regclass),
  'legacy_admission_rls_enabled');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_clinical_legacy_generation_at(%L,NULL)',m3b_cycle_test.uid(2951)),
  '42501','legacy_trusted_backend_required_even_for_direct_call');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
END $security$;
ROLLBACK;

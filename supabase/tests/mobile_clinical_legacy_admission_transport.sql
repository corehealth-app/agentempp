\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('public.admit_mobile_clinical_legacy_generation(uuid)') IS NOT NULL,
 'explicit_service_only_legacy_admission_transport_exists');
DO $admit$
DECLARE n integer;a uuid;r jsonb;before_rows jsonb;stamp timestamptz;before_clock timestamptz;
 allowed text[]:=ARRAY['private.workout_strength_authority_epochs','private.mobile_clinical_generation_sources','private.mobile_clinical_legacy_admissions'];
BEGIN
 FOR n IN 3000..3003 LOOP
  stamp:=CASE WHEN n%2=0 THEN '2026-10-01T23:00:00Z'::timestamptz END;
  a:=m3b_cycle_test.seed(n,stamp,'America/Sao_Paulo',false);
  UPDATE public.user_profiles SET onboarding_completed=true,current_protocol=CASE WHEN n<3002 THEN 'recomposicao'::public.protocol_enum END
   WHERE user_id=a;
  before_rows:=m3b_cycle_test.original_state(a);before_clock:=clock_timestamp();
  SET LOCAL ROLE service_role;
  r:=public.admit_mobile_clinical_legacy_generation(a);
  RESET ROLE;
  PERFORM m3b_cycle_test.ok(r->>'availability'='admitted' AND r#>>'{authority,user_id}'=a::text
   AND (r#>>'{authority,admitted_at}')::timestamptz BETWEEN before_clock AND clock_timestamp()
   AND (r#>>'{authority,profile_completed_marker}')::timestamptz IS NOT DISTINCT FROM stamp,
   'service_transport_uses_actual_owner_server_clock_and_original_marker_'||n);
  PERFORM m3b_cycle_test.ok(before_rows-allowed=m3b_cycle_test.original_state(a)-allowed
   AND (SELECT count(*)=1 FROM private.mobile_clinical_generation_sources WHERE user_id=a AND kind='legacy_transition')
   AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),
   'admission_changes_only_its_three_authority_tables_not_signup_profile_or_targets_'||n);
  before_rows:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.ok(public.admit_mobile_clinical_legacy_generation(a)=r
   AND before_rows=m3b_cycle_test.original_state(a),'admission_retry_reuses_its_exact_existing_source_'||n);
 END LOOP;
 a:=m3b_cycle_test.seed(3004,'2026-10-01T23:00:00Z');before_rows:=m3b_cycle_test.original_state(a);
 r:=public.admit_mobile_clinical_legacy_generation(a);
 PERFORM m3b_cycle_test.ok(r->>'availability'='signup_proven' AND before_rows=m3b_cycle_test.original_state(a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_legacy_admissions WHERE user_id=a),
  'actual_genuine_signup_is_not_readmitted_as_legacy');
 a:=m3b_cycle_test.seed(3005,NULL);before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(public.admit_mobile_clinical_legacy_generation(a)->>'reason'='onboarding_incomplete'
  AND before_rows=m3b_cycle_test.original_state(a),'incomplete_account_gets_no_admission_or_epoch');
END $admit$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege('anon','public.admit_mobile_clinical_legacy_generation(uuid)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.admit_mobile_clinical_legacy_generation(uuid)','EXECUTE')
 AND has_function_privilege('service_role','public.admit_mobile_clinical_legacy_generation(uuid)','EXECUTE'),
 'new_public_RPC_is_not_available_to_app_JWT_roles');
DO $jwt$
DECLARE code text;
BEGIN
 SET LOCAL request.jwt.claims='{"role":"authenticated"}';
 BEGIN PERFORM public.admit_mobile_clinical_legacy_generation(m3b_cycle_test.uid(3000));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 SET LOCAL request.jwt.claims='{"role":"service_role"}';
 PERFORM m3b_cycle_test.ok(code='42501','wrapper_requires_trusted_backend_even_for_privileged_SQL_caller');
END $jwt$;
DO $transport$
DECLARE a uuid:=m3b_cycle_test.seed(3006,clock_timestamp()+interval '1 hour','America/Sao_Paulo',false);
 code text;msg text;detail text;
BEGIN
 PERFORM m3b_cycle_test.throws(format('SELECT public.admit_mobile_clinical_legacy_generation(%L)',a),
  '40001','direct_SQL_preserves_original_admission_conflict');
 SET LOCAL request.path='/rpc/admit_mobile_clinical_legacy_generation';SET LOCAL request.method='POST';
 BEGIN PERFORM public.admit_mobile_clinical_legacy_generation(a);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,msg=MESSAGE_TEXT,detail=PG_EXCEPTION_DETAIL; END;
 PERFORM m3b_cycle_test.ok(code='PGRST' AND msg::jsonb->>'code'='40001' AND detail::jsonb->>'status'='409',
  'official_RPC_conflict_uses_existing_HTTP409_transport_rule');
END $transport$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

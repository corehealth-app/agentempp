\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

DO $transition$
DECLARE a uuid; d jsonb; admission jsonb; started jsonb; again jsonb; selected_cycle uuid;
 key_a uuid:=gen_random_uuid(); key_b uuid:=gen_random_uuid(); observed timestamptz:=clock_timestamp();
 base date:=(observed AT TIME ZONE 'America/Sao_Paulo')::date; before_profile jsonb;
BEGIN
 a:=m3b_cycle_test.seed(2971,'2026-10-01T23:00:00Z','America/Sao_Paulo',false);
 PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->>'unavailable_reason'='anchor_unproven',
  'clock_observation_never_admits_a_legacy_account_implicitly');
 admission:=private.admit_mobile_clinical_legacy_generation_at(a,observed)->'authority';
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 d:=private.mobile_reevaluation_clock_at(a,observed);
 PERFORM m3b_cycle_test.ok(d->>'availability'='available' AND d#>>'{clock,base_date}'=base::text
  AND d#>>'{clock,due_date}'=base::text AND d->'cycle'='null'::jsonb,
  'admitted_legacy_is_available_now_without_fabricating_a_previous_fortnight');
 PERFORM m3b_cycle_test.ok(d#>>'{transition,kind}'='legacy_transition'
  AND d#>>'{transition,generation}'=admission->>'generation'
  AND d#>>'{transition,epoch}'=admission->>'epoch'
  AND d#>>'{transition,admitted_at}'=admission->>'admitted_at',
  'immediate_calendar_has_explicit_original_transition_identity');
 started:=private.start_mobile_reevaluation_cycle_at(a,key_a,observed);
 selected_cycle:=(started#>>'{cycle,id}')::uuid;
 PERFORM m3b_cycle_test.ok(started#>>'{cycle,kind}'='TRANSITION_FULL'
  AND started#>>'{cycle,due_date}'=base::text,
  'server_selects_transition_kind_for_first_legacy_cycle');
 again:=private.start_mobile_reevaluation_cycle_at(a,key_a,observed+interval '1 hour');
 PERFORM m3b_cycle_test.ok(again=started,'same_start_key_reuses_transition_without_a_second_occurrence');
 again:=private.start_mobile_clinical_full_at(a,key_b,'REGULAR',NULL,observed+interval '1 hour');
 PERFORM m3b_cycle_test.ok(again#>>'{cycle,id}'=selected_cycle::text
  AND again#>>'{cycle,kind}'='TRANSITION_FULL',
  'ordinary_start_intent_cannot_relabel_transition_as_a_fortnight');
 again:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'TRANSITION_FULL',NULL,observed+interval '1 hour');
 PERFORM m3b_cycle_test.ok(again#>>'{cycle,id}'=selected_cycle::text,'explicit_transition_intent_uses_same_server_owned_cycle');
 again:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',observed+interval '1 hour');
 PERFORM m3b_cycle_test.ok(again#>>'{cycle,kind}'='TRANSITION_FULL',
  'early_intent_cannot_bypass_first_transition_kind_or_photo_requirement');
 UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=a;
 d:=private.mobile_reevaluation_clock_at(a,observed+interval '1 hour');
 PERFORM m3b_cycle_test.ok(d#>>'{clock,timezone}'='America/Sao_Paulo'
  AND d#>>'{clock,due_date}'=base::text,'open_transition_keeps_its_admission_timezone');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=before_profile FROM public.user_profiles p WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),
  'transition_start_preserves_profile_targets_and_no_fabricated_full_or_signup');
 UPDATE private.mobile_reevaluation_cycles c SET kind='REGULAR',due_date=base+14 WHERE c.user_id=a AND c.cycle_id=selected_cycle;
 PERFORM m3b_cycle_test.throws(format('SELECT private.mobile_reevaluation_clock_at(%L,%L)',a,observed+interval '1 hour'),
  'XX001','a_mislabeled_first_legacy_cycle_is_not_accepted_as_regular');
 UPDATE private.mobile_reevaluation_cycles c SET kind='TRANSITION_FULL',due_date=base WHERE c.user_id=a AND c.cycle_id=selected_cycle;
 PERFORM public.reset_user_conversation_atomic(a,true);
 d:=public.get_mobile_reevaluation_cycle(a);
 PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='onboarding_incomplete' AND NOT(d ? 'transition'),
  'reset_revokes_transition_identity_without_reopening_signup');
 PERFORM m3b_cycle_test.throws(format('SELECT private.start_mobile_reevaluation_cycle_at(%L,%L,NULL)',a,key_a),
  '40001','old_transition_key_cannot_acquire_a_new_generation_after_reset');
END $transition$;

DO $origins$
DECLARE a uuid; d jsonb; admission jsonb; observed timestamptz:=clock_timestamp();
BEGIN
 a:=m3b_cycle_test.seed(2972,NULL);
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 admission:=private.admit_mobile_clinical_legacy_generation_at(a,observed)->'authority';
 d:=private.mobile_reevaluation_clock_at(a,observed);
 PERFORM m3b_cycle_test.ok(d->>'availability'='available' AND d ? 'transition'
  AND (SELECT onboarding_completed_at IS NULL AND current_protocol IS NULL FROM public.user_profiles WHERE user_id=a),
  'legacy_without_old_timestamp_or_phase_gets_transition_without_invented_history');
 a:=m3b_cycle_test.seed(2973,'2026-10-01T23:00:00Z');
 d:=private.mobile_reevaluation_clock_at(a,observed);
 PERFORM m3b_cycle_test.ok(d#>>'{clock,base_date}'='2026-10-01'
  AND d#>>'{clock,due_date}'='2026-10-15' AND NOT(d ? 'transition'),
  'genuine_signup_calendar_and_wire_remain_original');
 PERFORM m3b_cycle_test.throws(format('SELECT private.start_mobile_clinical_full_at(%L,%L,''TRANSITION_FULL'',NULL,%L)',a,gen_random_uuid(),observed),
  '40001','genuine_signup_cannot_request_a_transition_to_evade_its_calendar');
END $origins$;
ROLLBACK;

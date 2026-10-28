\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_clinical_legacy_transition_fixture.sql
DO $keep$
DECLARE c jsonb;a uuid;request jsonb;result jsonb;before_day jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(2983,false,false));
 a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories)
 VALUES(a,day,1700,120,NULL,333,44);
 SELECT to_jsonb(d) INTO before_day FROM public.daily_snapshots d WHERE user_id=a AND date=day;
 request:=m3b_cycle_test.legacy_clinical_request(c);
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'status'='confirmed'
  AND (SELECT current_protocol IS NULL AND onboarding_completed_at IS NULL FROM public.user_profiles WHERE user_id=a),
  'legacy_keep_never_assigns_a_phase_or_invents_an_old_marker');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(d)=before_day FROM public.daily_snapshots d WHERE user_id=a AND date=day)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'legacy_keep_preserves_an_existing_unknown_phase_target_byte_for_byte_without_a_fake_event');
END $keep$;
CREATE FUNCTION m3b_cycle_test.reject_initial(q jsonb,expected text,label text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid:=(q#>>'{context,user_id}')::uuid;cycle uuid:=(q#>>'{context,cycle_id}')::uuid;
 context jsonb;preview jsonb;
BEGIN
 context:=public.get_mobile_clinical_full_context(a,'TRANSITION_FULL',cycle);
 preview:=private.prepare_mobile_clinical_preview_at(a,'TRANSITION_FULL',cycle,gen_random_uuid(),
  context->>'context_hash',q->'form',q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  preview->>'preview_id',gen_random_uuid(),q->'form',q->'intent',q->'proposal'),expected,label);
END $$;
DO $guards$
DECLARE c jsonb;a uuid;q jsonb;before_profile jsonb;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(2984,false,false));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_initial_phase_request(c);
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 PERFORM private.assert_mobile_clinical_legacy_phase_entry(q->'context',q->'form',q->'intent',q->'proposal',24);
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=before_profile FROM public.user_profiles p WHERE user_id=a),
  'eligibility_validation_alone_never_assigns_a_legacy_phase');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{form,legacyOrigin,generation}',to_jsonb(gen_random_uuid())),
  '40001','initial_phase_requires_the_exact_legacy_generation');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{intent,principalConfirmed}','false'),
  '22023','initial_phase_requires_explicit_principal_acceptance');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{intent,bodyFat,confirmed}','false'),
  '40001','initial_phase_requires_the_three_photo_mean_acceptance');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{proposal,profile,deficit_level}','600'),
  '22023','initial_phase_deficit_is_bound_to_the_actual_hunger_input');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{proposal,profile,activity_level}','"alto"'),
  '22023','initial_phase_cannot_change_activity_without_an_explicit_answer');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{proposal,targets,formulaAfterKcal}','1600'),
  '22023','initial_phase_has_no_unproven_adjustment_above_its_formula');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{proposal,episode,difficultyCount}','null'),
  '22023','recomposition_initializes_its_actual_new_counter_at_zero');
 PERFORM m3b_cycle_test.reject_initial(jsonb_set(q,'{proposal,episode,ledgerSteps}','[]'),
  '22023','recomposition_does_not_fabricate_an_initial_calorie_step_ledger');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 PERFORM m3b_cycle_test.reject_initial(q,'40001','an_active_health_hold_blocks_the_initial_phase');
 PERFORM m3b_cycle_test.ok((SELECT current_protocol IS NULL FROM public.user_profiles WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'all_refused_initial_variants_leave_no_phase_full_or_episode');
END $guards$;
DO $closed$
DECLARE c jsonb;a uuid;q jsonb;r jsonb;before_day jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(2985,false,false));a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,
  calories_consumed,exercise_calories,day_closed,closed_at)
 VALUES(a,day,1700,120,NULL,777,333,true,clock_timestamp());
 SELECT to_jsonb(d) INTO before_day FROM public.daily_snapshots d WHERE user_id=a AND date=day;
 q:=m3b_cycle_test.legacy_initial_phase_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  q->'form',q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed' AND (SELECT current_protocol='recomposicao'
  AND onboarding_completed_at IS NULL FROM public.user_profiles WHERE user_id=a),
  'explicit_initial_phase_creates_a_new_decision_without_fabricating_signup');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(d)=before_day FROM public.daily_snapshots d WHERE user_id=a AND date=day)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a),
  'initial_phase_never_reopens_or_rewrites_a_closed_day');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(review_id=(r->>'review_id')::uuid
  AND first_phase_id IS NULL AND entry_origin='confirmed_phase_change' AND difficulty_count=0
  AND ledger_steps IS NULL) FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'initial_episode_is_sourced_by_its_actual_FULL_not_a_signup_first_phase_receipt');
END $closed$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

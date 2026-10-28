\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_clinical_legacy_transition_fixture.sql
DO $full$
DECLARE c jsonb;a uuid;cycle uuid;request jsonb;result jsonb;before_profile jsonb;before_day jsonb;
 operation uuid:=gen_random_uuid();snapshot jsonb;day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.legacy_photo_context(2980);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 PERFORM m3b_cycle_test.ok((SELECT kind='TRANSITION_FULL' AND base_date=due_date
  FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),'legacy_photo_consent_uses_actual_immediate_transition');
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories)
 VALUES(a,day,1700,120,'recomposicao',200,50);
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 SELECT to_jsonb(d) INTO before_day FROM public.daily_snapshots d WHERE user_id=a AND date=day;
 PERFORM m3b_cycle_test.ok(jsonb_array_length(public.claim_mobile_reevaluation_photo_cleanup_scopes(100)->'items')=0,
  'active_transition_consent_is_not_misclassified_as_orphaned_signup');
 c:=m3b_cycle_test.process_clinical_photos(c);
 request:=m3b_cycle_test.legacy_clinical_request(c);
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=before_profile FROM public.user_profiles p WHERE user_id=a)
  AND (SELECT to_jsonb(d)=before_day FROM public.daily_snapshots d WHERE user_id=a AND date=day),
  'three_new_photos_and_preview_preserve_profile_and_targets_before_confirmation');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),'transition_does_not_manufacture_signup_or_frequency');
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'kind'='TRANSITION_FULL' AND result->>'status'='confirmed'
  AND result->>'body_fat_percent'='24.00','transition_confirms_real_three_photo_mean_without_a_historical_fortnight');
 PERFORM m3b_cycle_test.ok((SELECT current_protocol='recomposicao' AND body_fat_percent=24
  AND onboarding_completed_at='2026-10-01T23:00:00Z' FROM public.user_profiles WHERE user_id=a),
  'original_onboarding_marker_is_preserved_after_transition');
 PERFORM m3b_cycle_test.ok((SELECT calories_target=1599 AND protein_target=126 AND calories_consumed=200
  AND exercise_calories=50 AND NOT day_closed FROM public.daily_snapshots WHERE user_id=a AND date=day),
  'transition_changes_only_confirmed_targets_preserving_day_consumption');
 PERFORM m3b_cycle_test.ok((SELECT difficulty_count IS NULL AND ledger_steps IS NULL AND entry_origin='legacy_unknown'
  AND entry_date IS NULL FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'transition_never_counts_as_regular_difficulty_or_fabricates_phase_baseline');
 PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)#>>'{clock,base_date}'=day::text
  AND public.get_mobile_reevaluation_cycle(a)#>>'{clock,due_date}'=(day+14)::text
  AND NOT(public.get_mobile_reevaluation_cycle(a) ? 'transition'),
  'next_calendar_starts_fourteen_civil_days_after_actual_confirmation');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(manifest_count=3)
  FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_clinical_body_fat_receipts WHERE user_id=a),
  'transition_seals_three_photo_cleanup_and_retains_one_numeric_receipt');
 snapshot:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL)=result AND snapshot=m3b_cycle_test.original_state(a),
  'transition_confirmation_replay_is_exact_without_second_calendar_or_target_write');
 PERFORM public.reset_user_conversation_atomic(a,true);
 snapshot:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL)=result AND snapshot=m3b_cycle_test.original_state(a)
  AND (SELECT body_fat_percent IS NULL FROM public.user_profiles WHERE user_id=a),
  'old_transition_ack_after_reset_does_not_restore_clinical_state');
END $full$;

DO $unassigned$
DECLARE c jsonb;a uuid;request jsonb;result jsonb;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(2981,false));a:=(c->>'user')::uuid;
 request:=m3b_cycle_test.legacy_clinical_request(c);
 PERFORM m3b_cycle_test.ok(request#>>'{context,facts,protocol_authority,phase_origin,kind}'='legacy_transition_unassigned',
  'null_phase_transition_has_own_truthful_origin_not_confirmed_no_plan');
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'status'='confirmed' AND result->>'body_fat_percent'='24.00'
  AND (SELECT current_protocol IS NULL AND onboarding_completed_at IS NULL AND body_fat_percent=24
   FROM public.user_profiles WHERE user_id=a),'null_phase_and_unknown_old_marker_remain_null_after_photo_confirmation');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),
  'unassigned_transition_does_not_automatically_assign_a_phase_target_or_fake_signup');
END $unassigned$;

DO $incomplete$
DECLARE c jsonb;a uuid;cycle uuid;asset uuid;ticket uuid;request_key uuid;pose text;candidate jsonb;
 request jsonb;profile_before jsonb;current_snapshot jsonb;
BEGIN
 c:=m3b_cycle_test.legacy_photo_context(2982);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 SELECT to_jsonb(p) INTO profile_before FROM public.user_profiles p WHERE user_id=a;
 FOREACH pose IN ARRAY ARRAY['front','side'] LOOP
  c:=c||jsonb_build_object('revision',(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle));
  asset:=(m3b_cycle_test.allocate(c,gen_random_uuid(),pose)#>>'{asset,id}')::uuid;
  ticket:=gen_random_uuid();request_key:=gen_random_uuid();
  PERFORM public.prepare_mobile_reevaluation_photo_upload(a,cycle,asset,ticket);
  PERFORM public.register_mobile_reevaluation_photo_upload_ticket(a,cycle,asset,ticket,clock_timestamp()+interval '2 hours');
  PERFORM public.complete_mobile_reevaluation_photo_upload(a,cycle,asset,
   (SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id=a AND cycle_id=cycle AND requested_asset_id=asset),1200,'image/jpeg',NULL);
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,cycle,asset,request_key);
  PERFORM public.authorize_mobile_reevaluation_photo_provider(a,cycle,asset,request_key);
  PERFORM public.complete_mobile_reevaluation_photo_processing(a,cycle,asset,request_key,
   jsonb_build_object('type','body','view',pose,'bf_percent_estimate',24));
 END LOOP;
 candidate:=private.mobile_clinical_body_fat_candidate_at(a,cycle,NULL);
 PERFORM m3b_cycle_test.ok(candidate->>'availability'='unavailable'
  AND candidate->>'unavailable_reason'='three_processed_photos_required',
  'two_processed_new_poses_do_not_satisfy_transition');
 request:=m3b_cycle_test.legacy_clinical_request(c);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal'),
  '40001','transition_cannot_confirm_without_all_three_processed_photos');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=profile_before FROM public.user_profiles p WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a),
  'incomplete_photo_refusal_preserves_legacy_profile_and_has_no_full');
 c:=m3b_cycle_test.process_clinical_photos(c);
 request:=m3b_cycle_test.legacy_clinical_request(c);
 c:=c||jsonb_build_object('revision',(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle));
 PERFORM m3b_cycle_test.allocate(c,gen_random_uuid(),'front');
 current_snapshot:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal'),
  '40001','replacing_a_photo_invalidates_the_original_transition_preview');
 PERFORM m3b_cycle_test.ok(current_snapshot=m3b_cycle_test.original_state(a),
  'stale_transition_confirmation_changes_no_clinical_photo_or_target_rows');
END $incomplete$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT m3b_cycle_test.ok(true,'all_transition_rows_satisfy_actual_deferred_constraints');
ROLLBACK;

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_fixture.sql

DO $normal$
DECLARE ctx jsonb; a uuid; c uuid; aid uuid; rid uuid:=gen_random_uuid(); w jsonb; auth jsonb; done jsonb;
  activity timestamptz; retention timestamptz; profile jsonb; rev bigint; snap jsonb;
  reading jsonb:='{"type":"body","view":"front","bf_percent_estimate":22.35}';
BEGIN
  ctx:=m3b_cycle_test.ready_photo(801);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(ctx->>'asset')::uuid;
  SELECT last_activity_at INTO activity FROM private.mobile_reevaluation_photo_consents WHERE user_id=a;
  SELECT retention_until INTO retention FROM public.media_assets WHERE id=aid;
  SELECT to_jsonb(p) INTO profile FROM public.user_profiles p WHERE user_id=a;
  SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
  w:=public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid);
  PERFORM m3b_cycle_test.ok(w#>>'{attempt,id}'=rid::text AND w#>>'{attempt,status}'='claimed'
    AND w->>'source_revision'='2' AND w#>>'{asset,status}'='processing','claim_binds_latest_selected_source');
  PERFORM m3b_cycle_test.ok((w#>>'{attempt,lease_until}')::timestamptz<=retention
    AND (w#>>'{attempt,lease_until}')::timestamptz<=(w#>>'{attempt,claimed_at}')::timestamptz+interval '300seconds','lease_clamps_to_live_consent_and_storage');
  PERFORM m3b_cycle_test.ok(public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid) IS NULL,'same_claim_never_grants_second_download_or_provider');
  PERFORM m3b_cycle_test.ok(public.claim_mobile_reevaluation_photo_processing(a,c,aid,gen_random_uuid()) IS NULL,'competing_claim_is_busy');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_processing(%L,%L,%L,%L,%L)',a,c,aid,rid,reading),'40001','result_requires_provider_authorization');
  auth:=public.authorize_mobile_reevaluation_photo_provider(a,c,aid,rid);
  PERFORM m3b_cycle_test.ok(auth#>>'{attempt,status}'='authorized' AND auth#>>'{attempt,provider_started_at}' IS NOT NULL,'one_provider_authorization');
  PERFORM m3b_cycle_test.ok(public.authorize_mobile_reevaluation_photo_provider(a,c,aid,rid) IS NULL,'authorization_cannot_repeat_paid_call');
  done:=public.complete_mobile_reevaluation_photo_processing(a,c,aid,rid,reading);
  PERFORM m3b_cycle_test.ok(done#>>'{attempt,status}'='succeeded' AND done#>'{attempt,result}'=reading
    AND done#>>'{asset,status}'='processed','minimal_private_reading_committed');
  PERFORM m3b_cycle_test.ok(public.complete_mobile_reevaluation_photo_processing(a,c,aid,rid,reading)=done,'identical_result_replay_stable');
  PERFORM m3b_cycle_test.ok(public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid)=done,'terminal_claim_replay_avoids_provider');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_processing(%L,%L,%L,%L,%L)',a,c,aid,rid,jsonb_set(reading,'{bf_percent_estimate}','23')),'40001','different_result_cannot_overwrite_receipt');
  PERFORM m3b_cycle_test.ok(NOT public.fail_mobile_reevaluation_photo_processing(a,c,aid,rid,'provider_unavailable'),'late_failure_cannot_erase_success');
  PERFORM m3b_cycle_test.ok((SELECT processing_result IS NULL FROM public.media_assets WHERE id=aid),'generic_media_result_is_not_authority');
  PERFORM m3b_cycle_test.ok((SELECT last_activity_at=activity FROM private.mobile_reevaluation_photo_consents WHERE user_id=a)
    AND (SELECT retention_until=retention FROM public.media_assets WHERE id=aid),'background_work_never_renews_retention');
  PERFORM m3b_cycle_test.ok((SELECT revision=rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c)
    AND (SELECT to_jsonb(p)=profile FROM public.user_profiles p WHERE user_id=a),'background_work_preserves_revision_profile_targets');
  snap:=public.get_mobile_reevaluation_photo_snapshot(a,c);
  PERFORM m3b_cycle_test.ok(jsonb_array_length(snap->'photos')=3 AND snap#>>'{photos,0,pose}'='front'
    AND snap#>'{photos,0,photo,analysis}'=reading AND snap#>'{photos,1,photo}'='null'::jsonb,'snapshot_exact_slots_and_private_reading');
  PERFORM m3b_cycle_test.ok(NOT (snap::text LIKE '%object_path%' OR snap::text LIKE '%bucket_id%' OR snap::text LIKE '%raw_response%'),'snapshot_excludes_paths_and_provider_text');
  PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid());
  snap:=public.get_mobile_reevaluation_photo_snapshot(a,c);
  PERFORM m3b_cycle_test.ok(snap#>'{photos,0,photo}'='null'::jsonb,'pending_replacement_blocks_old_numeric_candidate');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_processing(%L,%L,%L,%L,%L)',a,c,aid,rid,reading),'40001','replacement_blocks_old_success_receipt');
END $normal$;

DO $invalid_readings$
DECLARE ctx jsonb; a uuid; c uuid; aid uuid; rid uuid:=gen_random_uuid(); reading jsonb;
BEGIN
  ctx:=m3b_cycle_test.ready_photo(802,'side');a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(ctx->>'asset')::uuid;
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid);PERFORM public.authorize_mobile_reevaluation_photo_provider(a,c,aid,rid);
  FOREACH reading IN ARRAY ARRAY[
    '{"type":"body","view":"unknown","bf_percent_estimate":20}'::jsonb,
    '{"type":"body","view":"front","bf_percent_estimate":20}'::jsonb,
    '{"type":"body","view":"side","bf_percent_estimate":null}'::jsonb,
    '{"type":"body","view":"side","bf_percent_estimate":2.99}'::jsonb,
    '{"type":"body","view":"side","bf_percent_estimate":60.01}'::jsonb,
    '{"type":"body","view":"side","bf_percent_estimate":"NaN"}'::jsonb,
    '{"type":"body","view":"side","bf_percent_estimate":20,"notes":"private"}'::jsonb] LOOP
    PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_processing(%L,%L,%L,%L,%L)',a,c,aid,rid,reading),'22023','invalid_or_unapproved_provider_reading_'||reading::text);
  END LOOP;
  PERFORM m3b_cycle_test.ok(public.fail_mobile_reevaluation_photo_processing(a,c,aid,rid,'invalid_analysis'),'deterministic_failure_saved_privately');
  PERFORM m3b_cycle_test.ok(public.fail_mobile_reevaluation_photo_processing(a,c,aid,rid,'invalid_analysis'),'failure_replay_stable');
  PERFORM m3b_cycle_test.ok((SELECT status='processing' AND processing_result IS NULL FROM public.media_assets WHERE id=aid),'private_failure_preserves_upload_completion_replay_status');
  PERFORM m3b_cycle_test.ok(public.complete_mobile_reevaluation_photo_upload(a,c,aid,2,1200,'image/jpeg',NULL) IS NOT NULL,'uploaded_bytes_replay_survives_provider_failure');
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_snapshot(a,c)#>>'{photos,1,photo,status}'='failed','snapshot_projects_private_failure');
  PERFORM m3b_cycle_test.ok(public.claim_mobile_reevaluation_photo_processing(a,c,aid,gen_random_uuid())#>>'{attempt,status}'='claimed','fresh_request_can_retry_private_failure');
END $invalid_readings$;

DO $closure$
DECLARE ctx jsonb; a uuid; c uuid; aid uuid; rid uuid; mode text; n integer:=810; expired_at timestamptz;
BEGIN
  FOREACH mode IN ARRAY ARRAY['reset','locale','deleted','expired','replacement'] LOOP
    ctx:=m3b_cycle_test.ready_photo(n);n:=n+1;a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(ctx->>'asset')::uuid;rid:=gen_random_uuid();
    PERFORM public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid);PERFORM public.authorize_mobile_reevaluation_photo_provider(a,c,aid,rid);
    SELECT retention_until INTO expired_at FROM public.media_assets WHERE id=aid;
    IF mode='reset' THEN PERFORM public.reset_user_conversation_atomic(a,true);
    ELSIF mode='locale' THEN UPDATE public.users SET locale='en-US' WHERE id=a;
    ELSIF mode='deleted' THEN UPDATE public.users SET status='deleted' WHERE id=a;
    ELSIF mode='replacement' THEN PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid());END IF;
    PERFORM m3b_cycle_test.throws(format('SELECT private.complete_mobile_reevaluation_photo_processing_at(%L,%L,%L,%L,''{"type":"body","view":"front","bf_percent_estimate":20}''::jsonb,%s)',a,c,aid,rid,
      CASE WHEN mode='expired' THEN quote_literal(expired_at)||'::timestamptz' ELSE 'NULL::timestamptz' END),CASE WHEN mode='deleted' THEN 'P0002' ELSE '40001' END,'late_result_refused_after_'||mode);
    PERFORM m3b_cycle_test.ok(public.fail_mobile_reevaluation_photo_processing(a,c,aid,rid,'provider_unavailable'),'late_failure_only_closes_private_attempt_'||mode);
    PERFORM m3b_cycle_test.ok((SELECT result IS NULL FROM private.mobile_reevaluation_photo_processing_attempts WHERE request_id=rid),'no_result_after_'||mode);
  END LOOP;
END $closure$;

DO $isolation$
DECLARE ctx jsonb; other_ctx jsonb; a uuid; c uuid; aid uuid; rid uuid:=gen_random_uuid();
BEGIN
  ctx:=m3b_cycle_test.ready_photo(820);other_ctx:=m3b_cycle_test.ready_photo(821);
  a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(ctx->>'asset')::uuid;
  PERFORM m3b_cycle_test.ok(public.claim_mobile_reevaluation_photo_processing((other_ctx->>'user')::uuid,(other_ctx->>'cycle')::uuid,aid,rid) IS NULL,'other_owner_cannot_claim');
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid);
  PERFORM m3b_cycle_test.ok(NOT public.fail_mobile_reevaluation_photo_processing((other_ctx->>'user')::uuid,(other_ctx->>'cycle')::uuid,aid,rid,'invalid_bytes'),'other_owner_cannot_close_attempt');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_processing_attempts SET source_revision=source_revision+1 WHERE request_id=%L',rid),'55000','attempt_identity_immutable');
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_processing_attempts','SELECT'),'private_attempt_not_directly_readable');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('authenticated','public.complete_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),'client_cannot_supply_provider_result');
  PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.claim_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid)','EXECUTE'),'trusted_backend_may_claim');
END $isolation$;

DO $lease_retry$
DECLARE ctx jsonb; a uuid; c uuid; aid uuid; old_id uuid:=gen_random_uuid();new_id uuid:=gen_random_uuid();
  base_time timestamptz; w jsonb;
BEGIN
  ctx:=m3b_cycle_test.ready_photo(830);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(ctx->>'asset')::uuid;
  SELECT uploaded_at INTO base_time FROM public.media_assets WHERE id=aid;
  PERFORM private.claim_mobile_reevaluation_photo_processing_at(a,c,aid,old_id,base_time);
  PERFORM private.authorize_mobile_reevaluation_photo_provider_at(a,c,aid,old_id,base_time+interval '1second');
  -- Genuine user allocation of a different pose renews the consent, not the
  -- old attempt's frozen lease. Explicit test clocks never reach publicRPCs.
  PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid(),'side',1200,base_time+interval '59seconds');
  w:=private.claim_mobile_reevaluation_photo_processing_at(a,c,aid,new_id,base_time+interval '61seconds');
  PERFORM m3b_cycle_test.ok(w#>>'{attempt,id}'=new_id::text AND w#>>'{attempt,status}'='claimed','fresh_request_after_expired_lease');
  PERFORM m3b_cycle_test.ok((SELECT status='expired' AND result IS NULL FROM private.mobile_reevaluation_photo_processing_attempts WHERE request_id=old_id),'old_attempt_terminalized_without_result');
  PERFORM m3b_cycle_test.ok(private.claim_mobile_reevaluation_photo_processing_at(a,c,aid,old_id,base_time+interval '61seconds') IS NULL,'old_request_never_reclaims_lease');
  PERFORM m3b_cycle_test.throws(format('SELECT private.complete_mobile_reevaluation_photo_processing_at(%L,%L,%L,%L,''{"type":"body","view":"front","bf_percent_estimate":20}''::jsonb,%L)',a,c,aid,old_id,base_time+interval '62seconds'),'40001','old_provider_cannot_overwrite_new_attempt');
  PERFORM private.authorize_mobile_reevaluation_photo_provider_at(a,c,aid,new_id,base_time+interval '62seconds');
  w:=private.complete_mobile_reevaluation_photo_processing_at(a,c,aid,new_id,'{"type":"body","view":"front","bf_percent_estimate":20}',base_time+interval '63seconds');
  PERFORM m3b_cycle_test.ok(w#>>'{attempt,status}'='succeeded' AND w->>'source_revision'='2','unrelated_pose_activity_does_not_reject_current_source');
END $lease_retry$;

DO $forged_generic_result$
DECLARE ctx jsonb; a uuid; c uuid; aid uuid;rid uuid:=gen_random_uuid();
BEGIN
  ctx:=m3b_cycle_test.ready_photo(831);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(ctx->>'asset')::uuid;
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid);
  -- Characterize the existing trusted direct-DML surface: status/result alone
  -- can never synthesize a successful private attempt or numeric candidate.
  UPDATE public.media_assets SET status='processed',processed_at=clock_timestamp(),
    processing_result='{"type":"body","view":"front","bf_percent_estimate":20}' WHERE id=aid;
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_snapshot(a,c)#>'{photos,0,photo,analysis}'='null'::jsonb
    AND public.get_mobile_reevaluation_photo_snapshot(a,c)#>>'{photos,0,photo,status}'='processing','generic_direct_result_not_accepted_as_recurring_reading');
END $forged_generic_result$;

ROLLBACK;

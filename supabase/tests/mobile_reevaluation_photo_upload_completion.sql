\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_fixture.sql
CREATE FUNCTION m3b_cycle_test.ticket(ctx jsonb,aid uuid) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=gen_random_uuid();
BEGIN
  PERFORM public.prepare_mobile_reevaluation_photo_upload((ctx->>'user')::uuid,(ctx->>'cycle')::uuid,aid,t);
  PERFORM public.register_mobile_reevaluation_photo_upload_ticket((ctx->>'user')::uuid,(ctx->>'cycle')::uuid,aid,t,clock_timestamp()+interval '2hours');
END $$;

DO $normal$
DECLARE ctx jsonb; a uuid; c uuid; first_id uuid; next_id uuid; obsolete uuid; k uuid:=gen_random_uuid();
  w jsonb; done jsonb; activity timestamptz; expiry timestamptz; profile jsonb;
BEGIN
  ctx:=m3b_cycle_test.photo_context(601);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
  SELECT to_jsonb(p) INTO profile FROM public.user_profiles p WHERE user_id=a;
  first_id:=(m3b_cycle_test.allocate(ctx,k)#>>'{asset,id}')::uuid;
  PERFORM m3b_cycle_test.ticket(ctx,first_id);
  w:=public.get_mobile_reevaluation_photo_upload_completion(a,c,first_id);
  PERFORM m3b_cycle_test.ok(w->>'source_revision'='1' AND w->>'selection_state'='pending','new_request_has_private_source_revision');
  done:=public.complete_mobile_reevaluation_photo_upload(a,c,first_id,1,1200,'image/jpeg','etag-1');
  PERFORM m3b_cycle_test.ok(done->>'source_revision'='2' AND done->>'cycle_revision'='3'
    AND done->>'selection_state'='selected' AND done#>>'{asset,status}'='uploaded','completion_selects_uploaded_source_once');
  PERFORM m3b_cycle_test.ok((SELECT selected_asset_id=first_id AND requested_asset_id=first_id
    FROM private.mobile_reevaluation_photo_sources WHERE user_id=a),'selected_source_matches_requested_tuple');
  SELECT last_activity_at INTO activity FROM private.mobile_reevaluation_photo_consents WHERE user_id=a;
  SELECT retention_until INTO expiry FROM public.media_assets WHERE id=first_id;
  PERFORM m3b_cycle_test.ok(public.complete_mobile_reevaluation_photo_upload(a,c,first_id,2,1200,'image/jpeg','etag-1')=done,'identical_completion_replay_is_stable');
  PERFORM m3b_cycle_test.ok((SELECT last_activity_at=activity FROM private.mobile_reevaluation_photo_consents WHERE user_id=a)
    AND (SELECT retention_until=expiry FROM public.media_assets WHERE id=first_id),'replay_does_not_renew_activity_or_retention');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_upload(%L,%L,%L,2,1200,''image/jpeg'',''changed'')',a,c,first_id),'40001','replay_changed_etag_refused');
  ctx:=jsonb_set(ctx,'{revision}','"3"');
  obsolete:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;
  PERFORM m3b_cycle_test.ticket(ctx,obsolete);
  next_id:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;
  PERFORM m3b_cycle_test.ok((SELECT selected_asset_id=first_id AND requested_asset_id=next_id AND source_revision=4
    FROM private.mobile_reevaluation_photo_sources WHERE user_id=a),'latest_request_preserves_previous_selection');
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_asset(a,c,first_id) IS NOT NULL
    AND public.get_mobile_reevaluation_photo_asset(a,c,obsolete) IS NULL,'only_selected_or_latest_requested_visible');
  PERFORM m3b_cycle_test.ok(m3b_cycle_test.allocate(jsonb_set(ctx,'{revision}','"2"'),k) IS NOT NULL
    AND (SELECT requested_asset_id=next_id FROM private.mobile_reevaluation_photo_sources WHERE user_id=a),'allocation_replay_never_retakes_requested_identity');
  PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_reevaluation_photo_upload(%L,%L,%L,%L)',a,c,obsolete,gen_random_uuid()),'P0002','obsolete_pending_cannot_sign_again');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_upload(%L,%L,%L,3,1200,''image/jpeg'',NULL)',a,c,obsolete),'40001','slow_obsolete_upload_cannot_select');
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_upload_completion(%L,%L,%L)',a,c,first_id),'40001','old_selected_cannot_complete_while_replacement_pending');
  PERFORM m3b_cycle_test.ticket(ctx,next_id);
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_upload(%L,%L,%L,4,1199,''image/jpeg'',NULL)',a,c,next_id),'22023','wrong_storage_size_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_upload(%L,%L,%L,4,1200,''image/png'',NULL)',a,c,next_id),'22023','wrong_storage_mime_refused');
  PERFORM m3b_cycle_test.ok((SELECT selected_asset_id=first_id FROM private.mobile_reevaluation_photo_sources WHERE user_id=a)
    AND (SELECT invalidated_at IS NULL FROM private.mobile_reevaluation_photo_assets WHERE asset_id=first_id),'invalid_metadata_keeps_previous_source');
  done:=public.complete_mobile_reevaluation_photo_upload(a,c,next_id,4,1200,'image/jpeg',NULL);
  PERFORM m3b_cycle_test.ok(done->>'source_revision'='5' AND done->>'cycle_revision'='4','replacement_advances_both_revisions_once');
  PERFORM m3b_cycle_test.ok((SELECT selected_asset_id=next_id FROM private.mobile_reevaluation_photo_sources WHERE user_id=a)
    AND (SELECT invalidated_reason='replaced' FROM private.mobile_reevaluation_photo_assets WHERE asset_id=first_id),'successful_replacement_invalidates_previous_selection');
  PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=profile FROM public.user_profiles p WHERE user_id=a),'completion_preserves_profile_and_targets');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_upload(%L,%L,%L,4,1200,''image/jpeg'',NULL)',a,c,next_id),'40001','stale_source_revision_cannot_replay');
END $normal$;

DO $authority$
DECLARE ctx jsonb; other_ctx jsonb; a uuid; c uuid; aid uuid; w jsonb; mode text; n integer:=610;
BEGIN
  FOREACH mode IN ARRAY ARRAY['ticket','reset','deleted','locale','expired','discarded'] LOOP
    ctx:=m3b_cycle_test.photo_context(n);n:=n+1;a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
    aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid(),'side')#>>'{asset,id}')::uuid;
    IF mode<>'ticket' THEN PERFORM m3b_cycle_test.ticket(ctx,aid);END IF;
    IF mode='reset' THEN PERFORM public.reset_user_conversation_atomic(a,true);
    ELSIF mode='deleted' THEN UPDATE public.users SET status='deleted' WHERE id=a;
    ELSIF mode='locale' THEN UPDATE public.users SET locale='en-US' WHERE id=a;
    ELSIF mode='discarded' THEN UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=clock_timestamp(),invalidated_reason='discarded' WHERE asset_id=aid;
    END IF;
    PERFORM m3b_cycle_test.throws(format('SELECT private.complete_mobile_reevaluation_photo_upload_at(%L,%L,%L,1,1200,''image/jpeg'',NULL,%s)',a,c,aid,
      CASE WHEN mode='expired' THEN quote_literal((SELECT retention_until FROM public.media_assets WHERE id=aid))||'::timestamptz' ELSE 'NULL::timestamptz' END),
      CASE WHEN mode='deleted' THEN 'P0002' ELSE '40001' END,'completion_refused_after_'||mode);
    PERFORM m3b_cycle_test.ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=aid),'refusal_preserves_pending_'||mode);
  END LOOP;
  ctx:=m3b_cycle_test.photo_context(620);other_ctx:=m3b_cycle_test.photo_context(621);
  a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;
  PERFORM m3b_cycle_test.ticket(ctx,aid);
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_upload_completion(%L,%L,%L)',other_ctx->>'user',other_ctx->>'cycle',aid),'40001','cross_owner_completion_context_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_upload(%L,%L,%L,1,1200,''image/jpeg'',%L)',a,c,aid,repeat('x',257)),'22023','oversized_etag_refused');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_sources SET pose=''back'' WHERE user_id=%L',a),'55000','source_identity_immutable');
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_sources','SELECT'),'source_authority_private');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('authenticated','public.complete_mobile_reevaluation_photo_upload(uuid,uuid,uuid,bigint,bigint,text,text)','EXECUTE'),'client_cannot_supply_storage_metadata');
  PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.complete_mobile_reevaluation_photo_upload(uuid,uuid,uuid,bigint,bigint,text,text)','EXECUTE'),'trusted_backend_can_complete');
END $authority$;
ROLLBACK;

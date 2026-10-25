\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/mobile_reevaluation_photo_fixture.sql

DO $allocation$
DECLARE ctx jsonb; other_ctx jsonb; d jsonb; r jsonb; k uuid:=gen_random_uuid();
  a uuid; c uuid; created_id uuid; original_profile jsonb; expiry timestamptz;
BEGIN
  ctx:=m3b_cycle_test.photo_context(201);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
  SELECT to_jsonb(p) INTO original_profile FROM public.user_profiles p WHERE user_id=a;
  d:=m3b_cycle_test.allocate(ctx,k);created_id:=(d#>>'{asset,id}')::uuid;
  PERFORM m3b_cycle_test.ok(d->>'version'='1' AND d->>'cycle_revision'='2'
    AND d#>>'{asset,origin}'='reevaluation_cycle_v1' AND d#>>'{asset,status}'='pending_upload'
    AND d#>>'{asset,pose}'='front' AND d#>>'{asset,consent_acceptance_id}'=ctx->>'acceptance',
    'new_pending_asset_binds_current_receipt_cycle_and_pose');
  PERFORM m3b_cycle_test.ok(d#>>'{asset,bucket_id}'='body-checkin-photos'
    AND d#>>'{asset,object_path}'=a::text||'/'||created_id::text||'.jpg'
    AND d#>>'{asset,size_bytes}'='1200','server_generates_identity_path_and_mime_extension');
  PERFORM m3b_cycle_test.ok((SELECT m.reevaluation_origin_version=1 AND m.signup_origin=false
    AND m.signup_disposition_version IS NULL AND l.asset_id=m.id
    AND l.user_id=m.user_id AND l.cycle_id=c AND l.consent_acceptance_id=(ctx->>'acceptance')::uuid
    FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=m.id
    WHERE m.id=created_id),'asset_and_private_membership_exist_atomically');
  expiry:=(d#>>'{asset,retention_until}')::timestamptz;
  r:=m3b_cycle_test.allocate(ctx,k);
  PERFORM m3b_cycle_test.ok(r=d AND (SELECT count(*)=1 FROM public.media_assets WHERE user_id=a),
    'same_key_one_asset_and_no_activity_renewal');
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_asset(a,c,created_id)=d,
    'owned_asset_lookup_uses_live_cycle_and_consent');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''side'')',ctx,k),
    '40001','same_key_different_pose_rejected');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''front'',1300)',ctx,k),
    '40001','same_key_different_size_rejected');
  r:=m3b_cycle_test.allocate(ctx,gen_random_uuid(),'front',1200,
    (d#>>'{asset,created_at}')::timestamptz+interval '1second');
  PERFORM m3b_cycle_test.ok(r#>>'{asset,id}'<>created_id::text AND r->>'cycle_revision'='2'
    AND (SELECT count(*)=2 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
    AND (SELECT status='pending_upload' FROM public.media_assets WHERE id=created_id),
    'pending_replacement_keeps_previous_asset_and_revision');
  PERFORM m3b_cycle_test.ok((SELECT count(DISTINCT retention_until)=1
    AND min(retention_until)>expiry FROM public.media_assets WHERE user_id=a),
    'legitimate_activity_updates_session_deadline_for_all_its_assets');
  PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=original_profile FROM public.user_profiles p WHERE user_id=a),
    'allocation_never_changes_clinical_profile_or_targets');
  other_ctx:=m3b_cycle_test.photo_context(202);
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_asset((other_ctx->>'user')::uuid,
    (other_ctx->>'cycle')::uuid,created_id) IS NULL,'other_owner_cannot_read_asset');
END $allocation$;

DO $validation_and_context$
DECLARE ctx jsonb; bad jsonb; d jsonb; a uuid; c uuid; k uuid; ordinary uuid;
BEGIN
  ctx:=m3b_cycle_test.photo_context(203);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''unknown'')',ctx,gen_random_uuid()),
    '22023','invalid_pose_cannot_allocate');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''front'',0)',ctx,gen_random_uuid()),
    '22023','zero_bytes_cannot_allocate');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''front'',15728641)',ctx,gen_random_uuid()),
    '22023','oversized_photo_cannot_allocate');
  bad:=jsonb_set(ctx,'{revision}','"1"');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',bad,gen_random_uuid()),
    '40001','stale_revision_cannot_allocate');
  bad:=jsonb_set(ctx,'{acceptance}',to_jsonb(gen_random_uuid()::text));
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',bad,gen_random_uuid()),
    '40001','another_acceptance_cannot_allocate');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,NULL)',ctx),
    '22023','null_request_key_cannot_allocate');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''front'',1200,%L)',
    ctx,gen_random_uuid(),(ctx->>'accepted_at')::timestamptz+interval '60seconds'),
    '40001','expired_consent_cannot_allocate');
  k:=gen_random_uuid();ordinary:=m3b_cycle_test.ordinary_asset(a);
  UPDATE public.media_assets SET source_request_hash=encode(extensions.digest(
    'reevaluation_photo_v1:'||k::text,'sha256'),'hex') WHERE id=ordinary;
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,k),
    '40001','hash_collision_never_adopts_generic_or_signup_asset');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=0 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),
    'failed_allocation_leaves_no_orphan_membership');
  k:=gen_random_uuid();d:=m3b_cycle_test.allocate(ctx,k);
  UPDATE public.users SET locale='en-US' WHERE id=a;
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,k),
    '40001','locale_change_checked_before_allocation_replay');
  UPDATE public.users SET locale='pt-BR' WHERE id=a;
  PERFORM public.reset_user_conversation_atomic(a,true);
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,k),
    '40001','reset_cannot_replay_old_cycle_asset');
END $validation_and_context$;

DO $immutability_and_generic_worker$
DECLARE ctx jsonb; d jsonb; created_id uuid; ordinary uuid; a uuid; c uuid; snapshot jsonb;
BEGIN
  ctx:=m3b_cycle_test.photo_context(204);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
  d:=m3b_cycle_test.allocate(ctx,gen_random_uuid());created_id:=(d#>>'{asset,id}')::uuid;
  PERFORM m3b_cycle_test.throws(format('UPDATE public.media_assets SET reevaluation_origin_version=NULL WHERE id=%L',created_id),
    '22023','recurring_marker_cannot_be_removed');
  PERFORM m3b_cycle_test.throws(format('UPDATE public.media_assets SET context_text=''Foto de costas.'' WHERE id=%L',created_id),
    '22023','recurring_asset_identity_cannot_be_rewritten');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_assets SET pose=''side'' WHERE asset_id=%L',created_id),
    '55000','private_source_pose_cannot_be_relabelled');
  ordinary:=m3b_cycle_test.ordinary_asset(a);
  PERFORM m3b_cycle_test.throws(format('UPDATE public.media_assets SET reevaluation_origin_version=1 WHERE id=%L',ordinary),
    '22023','historical_asset_cannot_be_retagged');
  PERFORM m3b_cycle_test.throws(format('INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until,signup_origin,reevaluation_origin_version) SELECT id2,%L,''body_checkin_photo'',''body-checkin-photos'',%L||''/''||id2::text||''.jpg'',''image/jpeg'',1200,''pending_upload'',repeat(''d'',64),clock_timestamp()+interval ''1hour'',false,1 FROM (SELECT gen_random_uuid() id2) q',a,a),
    '23503','marker_insert_without_membership_is_rejected');
  PERFORM m3b_cycle_test.ok(public.claim_media_asset_processing(created_id,a,repeat('a',64)) IS NULL,
    'generic_worker_does_not_claim_recurring_pending_photo');
  UPDATE public.media_assets SET status='uploaded',actual_size_bytes=1200,uploaded_at=clock_timestamp() WHERE id=created_id;
  PERFORM m3b_cycle_test.ok(public.claim_media_asset_processing(created_id,a,repeat('a',64)) IS NULL,
    'generic_worker_does_not_claim_recurring_uploaded_photo');
  UPDATE public.media_assets SET status='processing',processing_request_id=repeat('a',64) WHERE id=created_id;
  SELECT to_jsonb(m) INTO snapshot FROM public.media_assets m WHERE id=created_id;
  PERFORM m3b_cycle_test.ok(public.complete_media_asset_processing(created_id,a,repeat('a',64),'{}'::jsonb)=false,
    'generic_worker_cannot_commit_recurring_result');
  PERFORM m3b_cycle_test.ok(public.fail_media_asset_processing(created_id,a,repeat('a',64),'synthetic')=false
    AND (SELECT to_jsonb(m)=snapshot FROM public.media_assets m WHERE id=created_id),
    'generic_worker_cannot_fail_or_mutate_recurring_asset');
  PERFORM m3b_cycle_test.ok(public.claim_media_asset_processing(ordinary,a,repeat('b',64)) IS NOT NULL
    AND public.complete_media_asset_processing(ordinary,a,repeat('b',64),'{}'::jsonb),
    'ordinary_body_photo_processing_is_preserved');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM public.media_assets
    WHERE user_id=a AND reevaluation_origin_version IS NULL),
    'generic_SQL_filter_preserves_only_non_recurring_media');
END $immutability_and_generic_worker$;

DO $closed_sources_and_mime$
DECLARE ctx jsonb; d jsonb; r jsonb; a uuid; c uuid; first_id uuid; key_id uuid:=gen_random_uuid();
  first_time timestamptz; first_expiry timestamptz; entry jsonb; ordinary uuid;
BEGIN
  ctx:=m3b_cycle_test.photo_context(205);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
  d:=m3b_cycle_test.allocate(ctx,key_id);first_id:=(d#>>'{asset,id}')::uuid;
  first_time:=(d#>>'{asset,created_at}')::timestamptz;
  first_expiry:=(d#>>'{asset,retention_until}')::timestamptz;
  UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=first_time,invalidated_reason='discarded'
    WHERE asset_id=first_id;
  r:=m3b_cycle_test.allocate(ctx,gen_random_uuid(),'side',1200,first_time+interval '1second');
  PERFORM m3b_cycle_test.ok((SELECT retention_until=first_expiry FROM public.media_assets WHERE id=first_id),
    'new_activity_never_renews_closed_source_retention');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''front'',1200,%L)',
    ctx,key_id,first_time+interval '1second'),'40001','closed_source_replay_cannot_reauthorize_it');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=NULL,invalidated_reason=NULL WHERE asset_id=%L',first_id),
    '55000','closed_source_cannot_be_reopened');
  ctx:=m3b_cycle_test.photo_context(206);a:=(ctx->>'user')::uuid;
  FOR entry IN SELECT value FROM jsonb_array_elements('[ ["image/jpeg","jpg"], ["image/png","png"], ["image/webp","webp"], ["image/heic","heic"], ["image/heif","heif"] ]'::jsonb)
  LOOP
    d:=public.create_mobile_reevaluation_photo_asset(a,(ctx->>'cycle')::uuid,2,
      (ctx->>'acceptance')::uuid,'back',entry->>0,15728640,gen_random_uuid());
    PERFORM m3b_cycle_test.ok(d#>>'{asset,mime_type}'=entry->>0
      AND d#>>'{asset,object_path}'=a::text||'/'||(d#>>'{asset,id}')||'.'||(entry->>1),
      'permitted_mime_and_max_size_'||(entry->>0));
  END LOOP;
  PERFORM m3b_cycle_test.throws(format('SELECT public.create_mobile_reevaluation_photo_asset(%L,%L,2,%L,''front'',''application/pdf'',1200,%L)',
    a,ctx->>'cycle',ctx->>'acceptance',gen_random_uuid()),'22023','non_image_mime_rejected');
  ordinary:=m3b_cycle_test.ordinary_asset(a);
  PERFORM m3b_cycle_test.throws(format('SET CONSTRAINTS ALL IMMEDIATE; INSERT INTO private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose,request_key,request_revision,created_at) SELECT %L,%L,signup_generation,cycle_id,%L,''front'',%L,2,clock_timestamp() FROM private.mobile_reevaluation_cycles WHERE cycle_id=%L',
    ordinary,a,ctx->>'acceptance',gen_random_uuid(),ctx->>'cycle'),
    '23503','ledger_cannot_adopt_an_existing_unmarked_media_row');
  PERFORM m3b_cycle_test.throws(format('INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until,signup_origin,reevaluation_origin_version) SELECT id2,%L,''body_checkin_photo'',''body-checkin-photos'',%L||''/''||id2::text||''.jpg'',''image/jpeg'',1200,''pending_upload'',repeat(''e'',64),clock_timestamp()+interval ''1hour'',NULL,1 FROM (SELECT gen_random_uuid() id2) q',a,a),
    '23514','recurring_marker_requires_explicit_false_signup_origin');
END $closed_sources_and_mime$;

DO $security$
DECLARE valid boolean;
BEGIN
  SELECT c.relrowsecurity AND NOT has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')
  INTO valid FROM pg_class c WHERE c.oid='private.mobile_reevaluation_photo_assets'::regclass;
  PERFORM m3b_cycle_test.ok(valid,'private_asset_ledger_RLS_and_no_direct_backend_grants');
  SELECT bool_and(p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog']
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) INTO valid FROM pg_proc p
    WHERE p.oid IN('public.create_mobile_reevaluation_photo_asset(uuid,uuid,bigint,uuid,text,text,bigint,uuid)'::regprocedure,
      'public.get_mobile_reevaluation_photo_asset(uuid,uuid,uuid)'::regprocedure);
  PERFORM m3b_cycle_test.ok(valid,'asset_RPCs_backend_only_fixed_path');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role',
    'private.create_mobile_reevaluation_photo_asset_at(uuid,uuid,bigint,uuid,text,text,bigint,uuid,timestamptz)','EXECUTE'),
    'asset_clock_not_exposed');
END $security$;
ROLLBACK;

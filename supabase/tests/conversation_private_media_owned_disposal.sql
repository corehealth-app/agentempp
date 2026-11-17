-- Owned isolated rollback fixture only. Synthetic Storage metadata is not a
-- live provider deletion proof; the API/SDK path is qualified separately.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE private_owned_disposal_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.owned_disposal_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'OWNED_PRIVATE_DISPOSAL_FAIL:%',label;END IF;
INSERT INTO private_owned_disposal_checks VALUES(label);END $$;
SELECT pg_temp.owned_disposal_ok(to_regprocedure('public.claim_conversation_media_owned_disposal_v2(uuid,uuid)') IS NOT NULL,'single owned claim exists');
DO $cases$
DECLARE u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();
 foreign_a uuid:=gen_random_uuid();old_a uuid:=gen_random_uuid();expired_a uuid:=gen_random_uuid();q jsonb;busy jsonb;
 token uuid;new_token uuid;closed timestamptz;denied boolean;path text;old_at timestamptz:=clock_timestamp()-interval '31days';
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES
 (u,'owned-disposal-'||u||'@example.invalid','active','UTC','BR',true),
 (v,'owned-disposal-'||v||'@example.invalid','active','UTC','BR',true);
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('a',64));
 PERFORM public.create_conversation_media_asset_v2(u,b,'audio_note','audio/mp4',8,NULL,repeat('b',64));
 PERFORM public.create_conversation_media_asset_v2(v,foreign_a,'conversation_photo','image/jpeg',8,NULL,repeat('a',64));
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(old_a,u,'audio_note','audio-notes',u||'/'||old_a||'.m4a','audio/mp4',8,'pending_upload',repeat('c',64),clock_timestamp()+interval '30days');
 PERFORM pg_temp.owned_disposal_ok(public.claim_conversation_media_owned_disposal_v2(v,a) IS NULL,'foreign owner gets no claim');
 PERFORM pg_temp.owned_disposal_ok((SELECT status='pending_upload' FROM private.conversation_media_assets_v2 WHERE id=a),'foreign attempt does not close source');
 PERFORM pg_temp.owned_disposal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2),'foreign attempt enrolls no debt');
 PERFORM pg_temp.owned_disposal_ok(public.claim_conversation_media_owned_disposal_v2(u,old_a) IS NULL,'legacy source is never enrolled privately');
 PERFORM pg_temp.owned_disposal_ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=old_a),'old public source is preserved');
 q:=public.claim_conversation_media_owned_disposal_v2(u,a);token:=(q#>>'{claim,claim_token}')::uuid;
 PERFORM pg_temp.owned_disposal_ok(q->>'schema'='conversation.media-owned-disposal.v2' AND q->>'catalog_version'='2','versioned owned response');
 PERFORM pg_temp.owned_disposal_ok(q->>'user_id'=u::text AND q->>'asset_id'=a::text AND token IS NOT NULL,'exact chosen owner and source');
 path:='conversation-v2/'||u||'/'||a||'.m4a';
 PERFORM pg_temp.owned_disposal_ok(q#>>'{claim,object_path}'=path AND q#>>'{claim,bucket_id}'='audio-notes','claim carries only canonical private identity');
 PERFORM pg_temp.owned_disposal_ok((SELECT status='deleted' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=a),'closure commits before external IO');
 PERFORM pg_temp.owned_disposal_ok((SELECT count(*)=1 FROM private.conversation_media_disposals_v2),'only chosen asset enrolled');
 PERFORM pg_temp.owned_disposal_ok((SELECT count(*)=2 FROM private.conversation_media_assets_v2 WHERE id IN(b,foreign_a) AND status='pending_upload'),'other own and foreign sources untouched');
 SELECT closed_at INTO closed FROM private.conversation_media_obligations_v2 WHERE asset_id=a;
 busy:=public.claim_conversation_media_owned_disposal_v2(u,a);
 PERFORM pg_temp.owned_disposal_ok(busy->'claim'='null'::jsonb,'active lease is not stolen');
 PERFORM pg_temp.owned_disposal_ok((SELECT claim_token=token AND claim_revision=0 AND lease_until>clock_timestamp() FROM private.conversation_media_disposals_v2 WHERE asset_id=a),'lease token and revision unchanged on busy retry');
 PERFORM pg_temp.owned_disposal_ok(public.claim_conversation_media_disposal_batch_v2(100)->'items'='[]'::jsonb,'batch respects the single-source lease');
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',path,gen_random_uuid()::text,'{"size":0}');
 PERFORM pg_temp.owned_disposal_ok(public.inspect_conversation_media_disposal_v2(a,u,token)->>'state'='empty','single claim uses existing inspection authority');
 PERFORM pg_temp.owned_disposal_ok(public.acknowledge_conversation_media_disposal_v2(a,u,token)->>'state'='barrier_retained','existing acknowledgement retains barrier');
 q:=public.claim_conversation_media_owned_disposal_v2(u,a);new_token:=(q#>>'{claim,claim_token}')::uuid;
 PERFORM pg_temp.owned_disposal_ok(new_token IS NOT NULL AND new_token<>token,'completed retry acquires a fresh verifiable lease');
 PERFORM pg_temp.owned_disposal_ok((SELECT closed_at=closed FROM private.conversation_media_obligations_v2 WHERE asset_id=a),'retry preserves original closure');
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,token);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.owned_disposal_ok(denied,'prior token cannot inspect the new lease');
 PERFORM public.acknowledge_conversation_media_disposal_v2(a,u,new_token);
 PERFORM pg_temp.owned_disposal_ok((SELECT count(*)=1 FROM storage.objects WHERE bucket_id='audio-notes' AND name=path AND metadata->>'size'='0'),'marker never deleted by SQL claim or ack');
 INSERT INTO private.conversation_media_assets_v2(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,source_request_hash,created_at,updated_at,retention_until)
 VALUES(expired_a,u,'conversation_photo','meal-photos','conversation-v2/'||u||'/'||expired_a||'.jpg','image/jpeg',8,repeat('d',64),old_at,old_at,old_at+interval '720hours');
 PERFORM pg_temp.owned_disposal_ok(public.claim_conversation_media_owned_disposal_v2(u,expired_a)#>>'{claim,asset_id}'=expired_a::text,'expired own source can still be discarded');
 UPDATE public.users SET status='deleted',updated_at=clock_timestamp() WHERE id=u;
 PERFORM pg_temp.owned_disposal_ok(public.claim_conversation_media_owned_disposal_v2(u,b) IS NULL,'inactive account receives no interactive claim');
 PERFORM pg_temp.owned_disposal_ok((SELECT status='pending_upload' FROM private.conversation_media_assets_v2 WHERE id=b),'inactive interactive request does not become global purge');
 denied:=false;BEGIN PERFORM public.claim_conversation_media_owned_disposal_v2(NULL,a);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.owned_disposal_ok(denied,'invalid scope refused');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.claim_conversation_media_owned_disposal_v2(v,foreign_a);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.owned_disposal_ok(denied,'untrusted request context refused');
 PERFORM pg_temp.owned_disposal_ok(NOT has_function_privilege('authenticated','public.claim_conversation_media_owned_disposal_v2(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.claim_conversation_media_owned_disposal_v2(uuid,uuid)','EXECUTE'),'client execution closed');
 PERFORM pg_temp.owned_disposal_ok(has_function_privilege('service_role','public.claim_conversation_media_owned_disposal_v2(uuid,uuid)','EXECUTE'),'backend execution available');
 PERFORM pg_temp.owned_disposal_ok(NOT has_table_privilege('service_role','private.conversation_media_disposals_v2','SELECT'),'no new direct table access');
END $cases$;
SELECT jsonb_build_object('schema','conversation.private-owned-disposal-qa.v2','checks',(SELECT count(*) FROM private_owned_disposal_checks));
ROLLBACK;

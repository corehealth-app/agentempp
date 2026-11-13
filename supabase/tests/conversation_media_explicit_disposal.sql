-- Synthetic records and Storage metadata in the local rollback arena only.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE explicit_disposal_assertions(label text);
CREATE FUNCTION pg_temp.disposal_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'DISPOSAL_FAIL:%',label;END IF;
 INSERT INTO explicit_disposal_assertions VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();body uuid:=gen_random_uuid();
 q jsonb;r jsonb;c uuid;old_c uuid;before_debt jsonb;denied boolean;p text;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'explicit-'||u||'@example.invalid','active'),(other_u,'other-explicit-'||other_u||'@example.invalid','active');
 p:=u||'/'||a||'.m4a';
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until,processing_result,processing_request_id,actual_size_bytes,uploaded_at)
 VALUES(a,u,'audio_note','audio-notes',p,'audio/mp4',8,'processing',repeat('a',64),clock_timestamp()+interval '30days','{"private":"result"}',repeat('c',64),8,clock_timestamp()),
 (body,u,'body_checkin_photo','body-checkin-photos',u||'/'||body||'.jpg','image/jpeg',8,'pending_upload',repeat('b',64),clock_timestamp()+interval '30days',NULL,NULL,NULL,NULL);
 denied:=false;BEGIN PERFORM public.claim_conversation_media_disposal(a,other_u);EXCEPTION WHEN no_data_found THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'foreign owner refused before debt or catalogue mutation');
 PERFORM pg_temp.disposal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE asset_id=a),'foreign attempt leaves no manifest');
 denied:=false;BEGIN PERFORM public.claim_conversation_media_disposal(body,u);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied AND (SELECT status='pending_upload' FROM public.media_assets WHERE id=body),'clinical media excluded and preserved');
 q:=public.claim_conversation_media_disposal(a,u);c:=(q#>>'{claim,claim_token}')::uuid;
 PERFORM pg_temp.disposal_ok(q->>'schema'='conversation.media-disposal.v1' AND c IS NOT NULL,'ordinary direct disposal receives committed lease');
 PERFORM pg_temp.disposal_ok(q#>>'{claim,user_id}'=u::text AND q#>>'{claim,asset_id}'=a::text AND q#>>'{claim,object_path}'=p,'lease bound to immutable original owner and path');
 PERFORM pg_temp.disposal_ok((SELECT status='deleted' AND processing_result IS NULL FROM public.media_assets WHERE id=a),'closure precedes caller Storage operations');
 PERFORM pg_temp.disposal_ok((SELECT retention_until>clock_timestamp() FROM public.media_assets WHERE id=a),'explicit disposal does not wait for or rewrite normal retention');
 SELECT to_jsonb(d) INTO before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=a;
 r:=public.claim_conversation_media_disposal(a,u);
 PERFORM pg_temp.disposal_ok(r->'claim'='null'::jsonb,'repeat while live lease is busy not successful');
 PERFORM pg_temp.disposal_ok((SELECT to_jsonb(d)=before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=a),'busy attempt cannot steal claim or churn debt');
 old_c:=c;
 UPDATE private.conversation_media_expiry_debts SET lease_until=clock_timestamp()-interval '1microsecond' WHERE asset_id=a;
 q:=public.claim_conversation_media_disposal(a,u);c:=(q#>>'{claim,claim_token}')::uuid;
 PERFORM pg_temp.disposal_ok(c IS NOT NULL AND c<>old_c,'expired uncertain request lease can be reclaimed');
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,old_c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'unknown-result retry invalidates former lease');
 r:=public.inspect_conversation_media_payload_revocation(a,u,c);
 PERFORM pg_temp.disposal_ok(r->>'state'='absent','same existing revocation inspection accepts direct lease');
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',p,'11110000-0000-4000-8000-000000000111','{"size":0,"mimetype":"audio/mp4"}');
 r:=public.inspect_conversation_media_payload_revocation(a,u,c);
 PERFORM pg_temp.disposal_ok(r->>'state'='empty','same barrier protocol applies after explicit closure');
 r:=public.acknowledge_conversation_media_expiry_sweep(a,u,c);
 PERFORM pg_temp.disposal_ok(r->>'state'='waiting_for_issuance_drain','acknowledgment never claims final disposal');
 old_c:=c;q:=public.claim_conversation_media_disposal(a,u);c:=(q#>>'{claim,claim_token}')::uuid;
 PERFORM pg_temp.disposal_ok(c IS NOT NULL AND c<>old_c,'retry after completed sweep uses fresh lease');
 PERFORM pg_temp.disposal_ok((SELECT count(*)=1 FROM private.conversation_media_expiry_debts WHERE asset_id=a),'retries retain one independent debt');
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,old_c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'old caller cannot mutate with stale lease');
 DELETE FROM public.media_assets WHERE id=a;
 PERFORM public.acknowledge_conversation_media_expiry_sweep(a,u,c);
 q:=public.claim_conversation_media_disposal(a,u);c:=(q#>>'{claim,claim_token}')::uuid;
 PERFORM pg_temp.disposal_ok(c IS NOT NULL,'debt can be resumed if catalogue was purged after the owned lookup');
 DELETE FROM public.media_assets WHERE id=body AND user_id=u; -- synthetic clinical fixture has no Storage object
 DELETE FROM public.users WHERE id=u;
 PERFORM pg_temp.disposal_ok((public.inspect_conversation_media_payload_revocation(a,u,c)->>'state')='empty','account removal does not lose barrier or claim');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.claim_conversation_media_disposal(a,u);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.disposal_ok(denied,'untrusted role cannot invoke privileged preflight');
 PERFORM pg_temp.disposal_ok(NOT has_function_privilege('authenticated','public.claim_conversation_media_disposal(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.claim_conversation_media_disposal(uuid,uuid)','EXECUTE'),'client RPC permission closed');
 PERFORM pg_temp.disposal_ok(has_function_privilege('service_role','public.claim_conversation_media_disposal(uuid,uuid)','EXECUTE'),'backend disposal permission explicit');
END $cases$;
SELECT jsonb_build_object('schema','conversation.explicit-disposal-local-qa.v1','assertions',(SELECT count(*) FROM explicit_disposal_assertions));
ROLLBACK;

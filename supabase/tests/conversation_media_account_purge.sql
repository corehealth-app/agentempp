-- Synthetic Storage metadata belongs only to the local rollback arena.
-- Real object creation/removal must use the Storage API.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE conversation_purge_assertions(label text);
CREATE FUNCTION pg_temp.account_media_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'ACCOUNT_PURGE_FAIL:%',label;END IF;
INSERT INTO conversation_purge_assertions VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();legacy_a uuid:=gen_random_uuid();
 c uuid;cutoff timestamptz;q jsonb;p text;denied boolean;before_debt jsonb;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'account-media-'||u||'@example.invalid','active'),(other_u,'other-media-'||other_u||'@example.invalid','active');
 p:=u||'/'||a||'.m4a';cutoff:=clock_timestamp();
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(a,u,'audio_note','audio-notes',p,'audio/mp4',8,'pending_upload',repeat('1',64),clock_timestamp()+interval '30days'),
 (legacy_a,u,'meal_photo','meal-photos',u||'/'||legacy_a||'.jpg','image/jpeg',8,'pending_upload',repeat('2',64),clock_timestamp()+interval '30days');
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'active account cannot authorize disposal');
 PERFORM pg_temp.account_media_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE user_id=u),'ineligible preflight creates no debt');
 UPDATE public.users SET status='deleted' WHERE id=u;cutoff:=clock_timestamp();
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff-interval '1hour'),'changed cutoff refuses enrollment');
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'pending capability blocks account purge before Storage');
 PERFORM pg_temp.account_media_ok((SELECT status='deleted' AND processing_result IS NULL FROM public.media_assets WHERE id=a),'ordinary issuance closed before cleanup');
 PERFORM pg_temp.account_media_ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=legacy_a),'legacy meal media preserved for old cleanup');
 PERFORM pg_temp.account_media_ok((SELECT count(*)=1 FROM private.conversation_media_expiry_debts WHERE user_id=u AND asset_id=a),'bounded independent debt enrolled even before normal expiry');
 UPDATE private.conversation_media_expiry_debts SET user_id=other_u,object_path=other_u||'/'||a||'.m4a' WHERE asset_id=a;
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_account_purge(u,cutoff);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.account_media_ok(denied,'foreign identity in an existing debt cannot satisfy readiness');
 UPDATE private.conversation_media_expiry_debts SET user_id=u,object_path=p WHERE asset_id=a;
 PERFORM pg_temp.account_media_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE user_id=other_u),'foreign account unaffected');
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',p,'11110000-0000-4000-8000-000000000110','{"size":8,"mimetype":"audio/mp4"}');
 UPDATE storage.objects SET metadata='{"size":0}' WHERE bucket_id='audio-notes' AND name=p;
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'empty object without successful sweep cannot authorize purge');
 UPDATE storage.objects SET metadata='{"size":8}' WHERE bucket_id='audio-notes' AND name=p;
 UPDATE private.conversation_media_expiry_debts SET last_successful_sweep_at=clock_timestamp() WHERE asset_id=a;
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'ack without empty payload is insufficient');
 UPDATE storage.objects SET metadata='{"size":0,"mimetype":"audio/mp4"}' WHERE bucket_id='audio-notes' AND name=p;
 PERFORM pg_temp.account_media_ok(public.prepare_conversation_media_account_purge(u,cutoff),'verified empty barrier permits account purge');
 UPDATE storage.objects SET is_delete_marker=true WHERE bucket_id='audio-notes' AND name=p;
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'provider delete marker cannot authorize purge');
 UPDATE storage.objects SET is_delete_marker=false,archived_at=clock_timestamp() WHERE bucket_id='audio-notes' AND name=p;
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'archived object is not a current barrier');
 UPDATE storage.objects SET archived_at=NULL,version=NULL WHERE bucket_id='audio-notes' AND name=p;
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'unknown version refuses purge');
 UPDATE storage.objects SET version='11110000-0000-4000-8000-000000000110' WHERE bucket_id='audio-notes' AND name=p;
 UPDATE storage.buckets SET public=true WHERE id='audio-notes';
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'public bucket drift refuses purge');
 UPDATE storage.buckets SET public=false WHERE id='audio-notes';
 CREATE POLICY account_media_policy_drift ON storage.objects FOR INSERT TO authenticated WITH CHECK(true);
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'direct-client write policy drift refuses purge');
 DROP POLICY account_media_policy_drift ON storage.objects;
 SELECT to_jsonb(d) INTO before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=a;
 PERFORM pg_temp.account_media_ok(public.prepare_conversation_media_account_purge(u,cutoff),'ready replay remains ready');
 PERFORM pg_temp.account_media_ok((SELECT to_jsonb(d)=before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=a),'ready replay does not churn claims or settle debt');
 DELETE FROM public.media_assets WHERE user_id=u;
 PERFORM pg_temp.account_media_ok(public.prepare_conversation_media_account_purge(u,cutoff),'independent debt still checked after catalogue deletion');
 UPDATE storage.objects SET metadata='{"size":8}' WHERE bucket_id='audio-notes' AND name=p;
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'late payload cannot hide behind missing catalogue');
 UPDATE storage.objects SET metadata='{"size":0}' WHERE bucket_id='audio-notes' AND name=p;
 DELETE FROM public.users WHERE id=u;
 PERFORM pg_temp.account_media_ok((SELECT to_jsonb(d)=before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=a),'account removal preserves cleanup evidence and pending drain');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_account_purge(other_u,cutoff);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.account_media_ok(denied,'client role refused through privileged SQL session');
 PERFORM pg_temp.account_media_ok(NOT has_function_privilege('authenticated','public.prepare_conversation_media_account_purge(uuid,timestamptz)','EXECUTE') AND NOT has_function_privilege('anon','public.prepare_conversation_media_account_purge(uuid,timestamptz)','EXECUTE'),'client execute permissions closed');
 PERFORM pg_temp.account_media_ok(has_function_privilege('service_role','public.prepare_conversation_media_account_purge(uuid,timestamptz)','EXECUTE'),'trusted backend can prepare');
END $cases$;
DO $bounded$
DECLARE u uuid:=gen_random_uuid();cutoff timestamptz;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'bounded-media-'||u||'@example.invalid','deleted');
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 SELECT aid,u,'audio_note','audio-notes',u||'/'||aid||'.m4a','audio/mp4',8,'pending_upload',lpad(g::text,64,'0'),clock_timestamp()+interval '30days'
 FROM (SELECT gen_random_uuid() aid,g FROM generate_series(1,102) g) f;
 cutoff:=clock_timestamp();
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'over-limit owner defers safely');
 PERFORM pg_temp.account_media_ok((SELECT count(*)=100 FROM private.conversation_media_expiry_debts WHERE user_id=u),'one visit enrolls at most 100 ordinary paths');
 PERFORM pg_temp.account_media_ok((SELECT count(*)=2 FROM public.media_assets WHERE user_id=u AND status='pending_upload'),'bounded visit preserves remainder');
 PERFORM pg_temp.account_media_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'second visit still waits for payload revocation');
 PERFORM pg_temp.account_media_ok((SELECT count(*)=102 FROM private.conversation_media_expiry_debts WHERE user_id=u),'later visit advances beyond original first100');
 PERFORM pg_temp.account_media_ok((SELECT bool_and(status='deleted') FROM public.media_assets WHERE user_id=u),'all ordinary issuance closed after bounded visits');
END $bounded$;
SELECT jsonb_build_object('schema','conversation.media-account-purge-local-qa.v1','assertions',(SELECT count(*) FROM conversation_purge_assertions));
ROLLBACK;

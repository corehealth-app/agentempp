-- Local rollback arena only. Storage metadata below is synthetic test setup;
-- production object mutations must use the Storage API, never SQL.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE revocation_assertions(label text);
CREATE FUNCTION pg_temp.revocation_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'REVOCATION_FAIL:%',label;END IF;INSERT INTO revocation_assertions VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();c uuid:=gen_random_uuid();q jsonb;denied boolean;p text;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'revocation-'||u||'@example.invalid','active');
 p:=u||'/'||a||'.m4a';
 INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path,disposed_at,last_attempt_at,claim_token,lease_until)
 VALUES(a,u,'audio_note','audio-notes',p,clock_timestamp()-interval '1hour',clock_timestamp(),c,clock_timestamp()+interval '5minutes');
 q:=public.inspect_conversation_media_payload_revocation(a,u,c);
 PERFORM pg_temp.revocation_ok(q->>'state'='absent' AND q->'size_bytes'='null'::jsonb,'absence distinguished from empty object');
 PERFORM pg_temp.revocation_ok(q->>'asset_id'=a::text AND q->>'user_id'=u::text AND q->>'claim_token'=c::text AND q->>'object_path'=p,'inspection bound to immutable claim and path');
 PERFORM pg_temp.revocation_ok(q->>'bucket_private'='true' AND q->>'versioning'='DISABLED' AND q->>'mime_type'='audio/mp4','private non-versioned supported marker type explicit');
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',p,'11110000-0000-4000-8000-000000000004','{"size":8,"mimetype":"audio/mp4"}');
 q:=public.inspect_conversation_media_payload_revocation(a,u,c);
 PERFORM pg_temp.revocation_ok(q->>'state'='payload' AND (q->>'size_bytes')::integer=8,'positive payload never treated as barrier');
 PERFORM pg_temp.revocation_ok(q->>'object_version'='11110000-0000-4000-8000-000000000004','exact observed version available for conditional removal');
 UPDATE storage.objects SET metadata='{"size":0,"mimetype":"audio/mp4"}' WHERE bucket_id='audio-notes' AND name=p;
 q:=public.inspect_conversation_media_payload_revocation(a,u,c);
 PERFORM pg_temp.revocation_ok(q->>'state'='empty' AND (q->>'size_bytes')::integer=0,'ordinary zero bytes recognized');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.revocation_ok(denied,'untrusted JWT role refused even through privileged session');
 CREATE POLICY revocation_qa_drift ON storage.objects FOR INSERT TO authenticated WITH CHECK(true);
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 DROP POLICY revocation_qa_drift ON storage.objects;
 PERFORM pg_temp.revocation_ok(denied,'new direct client object policy drift refuses cleanup');
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,gen_random_uuid(),c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'foreign owner refused');
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'stale claim refused');
 UPDATE storage.buckets SET public=true WHERE id='audio-notes';
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'public bucket drift stops disposal before Storage');
 UPDATE storage.buckets SET public=false,allowed_mime_types=ARRAY['audio/ogg'] WHERE id='audio-notes';
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'unsupported marker MIME drift refused');
 UPDATE storage.buckets SET allowed_mime_types=ARRAY['audio/mp4'] WHERE id='audio-notes';
 UPDATE storage.objects SET metadata='{"size":"unknown"}' WHERE bucket_id='audio-notes' AND name=p;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'malformed object size never assumed empty');
 UPDATE storage.objects SET metadata='{"size":0}',is_delete_marker=true WHERE bucket_id='audio-notes' AND name=p;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'provider delete marker never mistaken for ordinary barrier');
 UPDATE storage.objects SET is_delete_marker=false WHERE bucket_id='audio-notes' AND name=p;
 UPDATE storage.objects SET version=NULL WHERE bucket_id='audio-notes' AND name=p;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'unknown version cannot permit plain-path deletion');
 UPDATE storage.objects SET version='11110000-0000-4000-8000-000000000004' WHERE bucket_id='audio-notes' AND name=p;
 -- Manifest is deliberately independent of the catalogue/user. Inspection must
 -- still permit only this claimed empty path after a user is erased.
 DELETE FROM public.users WHERE id=u;
 q:=public.inspect_conversation_media_payload_revocation(a,u,c);
 PERFORM pg_temp.revocation_ok(q->>'state'='empty','claim still protects original path after account removal');
 UPDATE private.conversation_media_expiry_debts SET lease_until=clock_timestamp()-interval '1microsecond' WHERE asset_id=a;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_payload_revocation(a,u,c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.revocation_ok(denied,'expired lease cannot authorize Storage mutation');
 PERFORM pg_temp.revocation_ok(NOT has_function_privilege('authenticated','public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid)','EXECUTE'),'client inspection access closed');
 PERFORM pg_temp.revocation_ok(has_function_privilege('service_role','public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid)','EXECUTE'),'trusted backend can inspect own claimed cleanup');
END $cases$;
SELECT jsonb_build_object('schema','conversation.media-revocation-local-qa.v1','assertions',(SELECT count(*) FROM revocation_assertions));
ROLLBACK;

-- Owned local rollback arena only. Synthetic Storage metadata is not an API
-- deletion test; live object writes/removals must use the Storage API.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE private_disposal_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.disposal_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_DISPOSAL_FAIL:%',label;END IF;
INSERT INTO private_disposal_checks VALUES(label);END $$;
SELECT pg_temp.disposal_ok(to_regprocedure('public.close_conversation_media_v2(uuid,uuid)') IS NOT NULL,'private explicit disposal available');
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();
 t uuid:=gen_random_uuid();late_t uuid:=gen_random_uuid();c uuid;q jsonb;replay jsonb;state jsonb;
 path text;denied boolean;closed timestamptz;cutoff timestamptz;expiry timestamptz:=clock_timestamp()+interval '2hours';
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES
 (u,'private-disposal-'||u||'@example.invalid','active','UTC','BR',true),
 (other_u,'private-disposal-'||other_u||'@example.invalid','active','UTC','BR',true);
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,'Consumido leite com whey',repeat('8',64));
 path:='conversation-v2/'||u||'/'||a||'.m4a';
 PERFORM public.prepare_conversation_media_upload_v2(u,a,t);
 PERFORM public.prepare_conversation_media_upload_v2(u,a,late_t);
 PERFORM public.register_conversation_media_upload_v2(u,a,t,expiry);
 PERFORM public.complete_conversation_media_upload_v2(u,a,8,'audio/mp4',NULL);
 q:=public.claim_conversation_media_processing_v2(u,a,repeat('7',64));
 PERFORM public.complete_conversation_media_processing_v2(u,a,repeat('7',64),(q#>>'{claim,token}')::uuid,'{"text":"Leite com whey"}');
 PERFORM pg_temp.disposal_ok(NOT public.close_conversation_media_v2(other_u,a),'foreign owner cannot close source');
 PERFORM pg_temp.disposal_ok(NOT public.prepare_conversation_media_account_purge_v2(u,clock_timestamp()),'active account cannot enroll purge');
 PERFORM pg_temp.disposal_ok(public.close_conversation_media_v2(u,a),'own explicit disposal closes source');
 SELECT closed_at INTO closed FROM private.conversation_media_obligations_v2 WHERE asset_id=a;
 PERFORM pg_temp.disposal_ok(public.close_conversation_media_v2(u,a) AND(SELECT closed_at=closed FROM private.conversation_media_obligations_v2 WHERE asset_id=a),'disposal replay preserves original closure');
 PERFORM pg_temp.disposal_ok((SELECT status='deleted' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=a),'source closed and interpretation scrubbed');
 PERFORM pg_temp.disposal_ok(public.get_conversation_media_upload_state_v2(u,a) IS NULL,'closed source cannot sign again');
 PERFORM pg_temp.disposal_ok((SELECT count(*)=1 FROM private.conversation_media_disposals_v2 WHERE asset_id=a AND user_id=u),'exact independent disposal debt enrolled');
 PERFORM pg_temp.disposal_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=a) AND NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE asset_id=a),'legacy catalog and remover never obtain private path');
 q:=public.claim_conversation_media_disposal_batch_v2(100);
 SELECT (x->>'claim_token')::uuid INTO c FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=a::text;
 PERFORM pg_temp.disposal_ok(c IS NOT NULL AND q->>'schema'='conversation.media-disposal-page.v2','scheduled claim includes explicit version2 source');
 PERFORM pg_temp.disposal_ok((SELECT x->>'object_path'=path AND x->>'catalog_version'='2' FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=a::text),'claim binds canonical disjoint path');
 state:=public.inspect_conversation_media_disposal_v2(a,u,c);
 PERFORM pg_temp.disposal_ok(state->>'state'='absent' AND state->'object_version'='null'::jsonb,'absence is not an empty barrier');
 denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'ack refuses absent marker');
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',path,'11110000-0000-4000-8000-000000000169','{"size":8,"mimetype":"audio/mp4"}');
 state:=public.inspect_conversation_media_disposal_v2(a,u,c);
 PERFORM pg_temp.disposal_ok(state->>'state'='payload' AND state->>'object_version'='11110000-0000-4000-8000-000000000169','payload inspection binds exact version');
 denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'ack refuses live payload');
 -- Actual provider response arrives after closure, invalidating the claim revision.
 PERFORM public.register_conversation_media_upload_v2(u,a,late_t,expiry);
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'late signing invalidates prior cleanup authority');
 UPDATE private.conversation_media_disposals_v2 SET lease_until=clock_timestamp()-interval '1microsecond' WHERE asset_id=a;
 q:=public.claim_conversation_media_disposal_batch_v2(100);
 SELECT (x->>'claim_token')::uuid INTO c FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=a::text;
 UPDATE storage.objects SET metadata='{"size":0,"mimetype":"audio/mp4"}' WHERE bucket_id='audio-notes' AND name=path;
 state:=public.inspect_conversation_media_disposal_v2(a,u,c);
 PERFORM pg_temp.disposal_ok(state->>'state'='empty' AND state->>'catalog_version'='2','current exact empty barrier observed');
 replay:=public.acknowledge_conversation_media_disposal_v2(a,u,c);
 PERFORM pg_temp.disposal_ok(replay->>'state'='barrier_retained' AND replay->>'issuance_reconciled'='false','ack never asserts capability drain');
 PERFORM pg_temp.disposal_ok(public.acknowledge_conversation_media_disposal_v2(a,u,c)=replay,'same ack is stable while barrier current');
 UPDATE storage.objects SET metadata='{"size":8}' WHERE bucket_id='audio-notes' AND name=path;
 denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'ack replay rechecks current barrier');
 UPDATE storage.objects SET metadata='{"size":0}' WHERE bucket_id='audio-notes' AND name=path;
 UPDATE public.users SET status='deleted' WHERE id=u;cutoff:=clock_timestamp();
 PERFORM pg_temp.disposal_ok(NOT public.prepare_conversation_media_account_purge_v2(u,cutoff-interval '1hour'),'stale account cutoff refused');
 PERFORM pg_temp.disposal_ok(public.prepare_conversation_media_account_purge_v2(u,cutoff),'verified barrier releases own catalog for account purge');
 PERFORM pg_temp.disposal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE user_id=u),'account purge detaches only qualified private sources');
 PERFORM pg_temp.disposal_ok(public.prepare_conversation_media_account_purge_v2(u,cutoff),'account purge replay checks retained independent obligation');
 UPDATE storage.objects SET is_delete_marker=true WHERE bucket_id='audio-notes' AND name=path;
 PERFORM pg_temp.disposal_ok(NOT public.prepare_conversation_media_account_purge_v2(u,cutoff),'provider delete marker cannot satisfy account readiness');
 UPDATE storage.objects SET is_delete_marker=false WHERE bucket_id='audio-notes' AND name=path;
 DELETE FROM public.users WHERE id=u;
 PERFORM pg_temp.disposal_ok(EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 WHERE asset_id=a) AND EXISTS(SELECT 1 FROM private.conversation_media_upload_tickets_v2 WHERE ticket_id=late_t),'account removal retains technical source and tickets');
 q:=public.claim_conversation_media_disposal_batch_v2(100);
 SELECT (x->>'claim_token')::uuid INTO c FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=a::text;
 PERFORM pg_temp.disposal_ok(public.inspect_conversation_media_disposal_v2(a,u,c)->>'state'='empty','scheduled protection survives missing owner and catalog');
 PERFORM pg_temp.disposal_ok(public.acknowledge_conversation_media_disposal_v2(a,u,c)->>'state'='barrier_retained','missing owner does not remove barrier or debt');
 PERFORM pg_temp.disposal_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=other_u) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=other_u),'disposal has no unrelated domain effects');
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,other_u,c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'foreign inspection refused');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.claim_conversation_media_disposal_batch_v2(1);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.disposal_ok(denied,'untrusted claim role refused');
 PERFORM pg_temp.disposal_ok(NOT has_table_privilege('service_role','private.conversation_media_disposals_v2','SELECT') AND NOT has_table_privilege('authenticated','private.conversation_media_disposals_v2','SELECT'),'private debt has no direct backend or client access');
 PERFORM pg_temp.disposal_ok(NOT has_function_privilege('authenticated','public.close_conversation_media_v2(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.claim_conversation_media_disposal_batch_v2(integer)','EXECUTE'),'client RPC execution closed');
END $cases$;
DO $expiry_and_drift$
DECLARE u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();fresh uuid:=gen_random_uuid();q jsonb;c uuid;denied boolean;
 p text;old_at timestamptz:=clock_timestamp()-interval '31days';
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'expiry-v2-'||u||'@example.invalid','active');
 p:='conversation-v2/'||u||'/'||a||'.jpg';
 INSERT INTO private.conversation_media_assets_v2(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,source_request_hash,created_at,updated_at,retention_until)
 VALUES(a,u,'conversation_photo','meal-photos',p,'image/jpeg',8,repeat('9',64),old_at,old_at,old_at+interval '720hours');
 PERFORM public.create_conversation_media_asset_v2(u,fresh,'conversation_photo','image/jpeg',8,NULL,repeat('6',64));
 q:=public.claim_conversation_media_disposal_batch_v2(100);
 SELECT(x->>'claim_token')::uuid INTO c FROM jsonb_array_elements(q->'items')x WHERE x->>'asset_id'=a::text;
 PERFORM pg_temp.disposal_ok(c IS NOT NULL AND(SELECT status='deleted' FROM private.conversation_media_assets_v2 WHERE id=a),'expiry closes never-signed private catalog source');
 PERFORM pg_temp.disposal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 WHERE asset_id=fresh),'fresh active source not enrolled by scheduled expiry');
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('meal-photos',p,gen_random_uuid()::text,'{"size":0}');
 CREATE POLICY private_v2_disposal_drift ON storage.objects FOR INSERT TO authenticated WITH CHECK(true);
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 DROP POLICY private_v2_disposal_drift ON storage.objects;
 PERFORM pg_temp.disposal_ok(denied,'direct client policy drift refuses private cleanup');
 UPDATE storage.buckets SET public=true WHERE id='meal-photos';
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 UPDATE storage.buckets SET public=false WHERE id='meal-photos';
 PERFORM pg_temp.disposal_ok(denied,'public bucket drift refuses private cleanup');
 UPDATE storage.objects SET version=NULL WHERE bucket_id='meal-photos' AND name=p;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'unknown object version never permits fallback deletion');
 UPDATE storage.objects SET version=gen_random_uuid()::text,metadata='{"size":"0"}' WHERE bucket_id='meal-photos' AND name=p;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'string size cannot masquerade as empty bytes');
 UPDATE storage.objects SET metadata='{"size":0}' WHERE bucket_id='meal-photos' AND name=p;
 UPDATE private.conversation_media_disposals_v2 SET lease_until=clock_timestamp()-interval '1microsecond' WHERE asset_id=a;
 denied:=false;BEGIN PERFORM public.inspect_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'expired cleanup token cannot authorize Storage IO');
 q:=public.claim_conversation_media_disposal_batch_v2(100);
 PERFORM pg_temp.disposal_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(q->'items')x WHERE x->>'asset_id'=a::text AND x->>'claim_token'<>c::text),'reclaim gets new token after lease expiry');
 denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_disposal_v2(a,u,c);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'superseded cleanup token cannot acknowledge');
 denied:=false;BEGIN PERFORM public.claim_conversation_media_disposal_batch_v2(101);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.disposal_ok(denied,'batch remains bounded at100');
END $expiry_and_drift$;
DO $orphaned_source$
DECLARE u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();t uuid:=gen_random_uuid();q jsonb;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'orphan-v2-'||u||'@example.invalid','active');
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('5',64));
 PERFORM public.prepare_conversation_media_upload_v2(u,a,t);
 -- Controlled missing-catalog condition after an external signer may have begun.
 DELETE FROM private.conversation_media_assets_v2 WHERE id=a;
 q:=public.claim_conversation_media_disposal_batch_v2(100);
 PERFORM pg_temp.disposal_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(q->'items')x WHERE x->>'asset_id'=a::text),'missing catalog retains independent cleanup authority');
 PERFORM pg_temp.disposal_ok((SELECT closed_at IS NOT NULL FROM private.conversation_media_obligations_v2 WHERE asset_id=a),'orphaned capability source is closed before sweep');
 PERFORM pg_temp.disposal_ok((SELECT provider_expires_at IS NULL FROM private.conversation_media_upload_tickets_v2 WHERE ticket_id=t),'unresolved signer is never assumed expired');
END $orphaned_source$;
DO $bounded_account$
DECLARE u uuid:=gen_random_uuid();a uuid;q jsonb;x jsonb;cutoff timestamptz;visits integer:=0;ready boolean;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'bounded-v2-'||u||'@example.invalid','active');
 FOR n IN 1..102 LOOP
  a:=gen_random_uuid();PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,encode(sha256(convert_to(a::text,'UTF8')),'hex'));
 END LOOP;
 UPDATE public.users SET status='deleted' WHERE id=u;cutoff:=clock_timestamp();
 PERFORM pg_temp.disposal_ok(NOT public.prepare_conversation_media_account_purge_v2(u,cutoff),'account waits for private byte revocation');
 PERFORM pg_temp.disposal_ok((SELECT count(*)=100 FROM private.conversation_media_disposals_v2 WHERE user_id=u),'one account visit enrolls only100 sources');
 PERFORM pg_temp.disposal_ok((SELECT count(*)=2 FROM private.conversation_media_assets_v2 WHERE user_id=u AND status='pending_upload'),'first bounded visit preserves remaining sources');
 ready:=public.prepare_conversation_media_account_purge_v2(u,cutoff);
 PERFORM pg_temp.disposal_ok(NOT ready AND(SELECT count(*)=102 FROM private.conversation_media_disposals_v2 WHERE user_id=u),'second bounded visit advances enrollment');
 INSERT INTO storage.objects(bucket_id,name,version,metadata)
 SELECT bucket_id,object_path,gen_random_uuid()::text,'{"size":0}'::jsonb FROM private.conversation_media_obligations_v2 WHERE user_id=u;
 FOR visits IN 1..3 LOOP
  q:=public.claim_conversation_media_disposal_batch_v2(100);
  FOR x IN SELECT value FROM jsonb_array_elements(q->'items') WHERE value->>'user_id'=u::text LOOP
   PERFORM public.acknowledge_conversation_media_disposal_v2((x->>'asset_id')::uuid,u,(x->>'claim_token')::uuid);
  END LOOP;
  EXIT WHEN public.prepare_conversation_media_account_purge_v2(u,cutoff);
 END LOOP;
 PERFORM pg_temp.disposal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE user_id=u),'fair sweeps release all102 qualified catalog sources');
 PERFORM pg_temp.disposal_ok((SELECT count(*)=102 FROM private.conversation_media_disposals_v2 WHERE user_id=u),'account purge retains every independent barrier obligation');
 DELETE FROM public.users WHERE id=u;
 PERFORM pg_temp.disposal_ok((SELECT count(*)=102 FROM private.conversation_media_obligations_v2 WHERE user_id=u),'owner removal cannot cascade disposal authority');
END $bounded_account$;
SELECT jsonb_build_object('schema','conversation.private-disposal-local-qa.v2','checks',(SELECT count(*) FROM private_disposal_checks));
ROLLBACK;

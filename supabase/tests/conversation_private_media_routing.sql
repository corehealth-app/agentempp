-- Actual local SQL, rollback only. No Storage or model operations.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE private_routing_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.routing_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_ROUTING_FAIL:%',label;END IF;
INSERT INTO private_routing_checks VALUES(label);END $$;
SELECT pg_temp.routing_ok(to_regprocedure('public.resolve_conversation_media_catalog_v2(uuid,uuid,text)') IS NOT NULL,'trusted catalog routing available');
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();
 old_id uuid:=gen_random_uuid();replacement_id uuid:=gen_random_uuid();e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();fresh_i uuid:=gen_random_uuid();
 q jsonb;raw jsonb;denied boolean;h text:=repeat('a',64);
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES
 (u,'private-routing-'||u||'@example.invalid','active','UTC','BR',true),
 (other_u,'private-routing-'||other_u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(old_id,u,'audio_note','audio-notes',u||'/'||old_id||'.m4a','audio/mp4',8,'pending_upload',h,clock_timestamp()+interval '30days');
 q:=public.resolve_conversation_media_catalog_v2(u,NULL,h);
 PERFORM pg_temp.routing_ok(q->>'schema'='conversation.media-catalog.v2' AND q->>'catalog_version'='1' AND q->>'asset_id'=old_id::text,'old technical retry retains its public source');
 PERFORM pg_temp.routing_ok(public.resolve_conversation_media_catalog_v2(other_u,old_id,NULL) IS NULL,'foreign catalog identity not exposed');
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('b',64));
 q:=public.resolve_conversation_media_catalog_v2(u,a,NULL);
 PERFORM pg_temp.routing_ok(q->>'catalog_version'='2' AND q->>'asset_id'=a::text AND q->>'user_id'=u::text AND q->>'kind'='audio_note','private routing derives owner purpose and version from committed source');
 PERFORM pg_temp.routing_ok(NOT(q ? 'object_path') AND NOT(q ? 'source_request_hash'),'route proof contains no key or request hash');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,b,'audio_note','audio/mp4',8,NULL,h);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.routing_ok(denied,'private create cannot duplicate an existing public technical request');
 denied:=false;BEGIN
  INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
  VALUES(b,u,'audio_note','audio-notes',u||'/'||b||'.m4a','audio/mp4',8,'pending_upload',repeat('b',64),clock_timestamp()+interval '30days');
 EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.routing_ok(denied,'old caller cannot duplicate a committed private technical request');
 PERFORM pg_temp.routing_ok(public.create_conversation_media_asset_v2(u,b,'audio_note','audio/mp4',8,NULL,repeat('b',64))#>>'{asset,id}'=a::text,'private technical replay retains first asset ID');
 PERFORM public.create_conversation_media_asset_v2(other_u,b,'audio_note','audio/mp4',8,NULL,h);
 PERFORM pg_temp.routing_ok(public.resolve_conversation_media_catalog_v2(other_u,NULL,h)->>'asset_id'=b::text,'same hash on another owner remains independent');

 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_build_object('channel','media','media_asset_id',old_id,'user_action','report_actual_record'));
 q:=public.admit_conversation_versioned_media_intake_v2(u,e,raw);
 PERFORM pg_temp.routing_ok(q->>'action'='admitted' AND NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=i),'versioned admission preserves old pending intake provenance');
 DELETE FROM public.media_assets WHERE id=old_id;
 PERFORM public.create_conversation_media_asset_v2(u,old_id,'audio_note','audio/mp4',8,NULL,h);
 PERFORM pg_temp.routing_ok(public.admit_conversation_versioned_media_intake_v2(u,e,raw)->>'action'='replay','old admitted intake remains legacy after genuine opaque-ID reuse');
 PERFORM pg_temp.routing_ok(NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=i),'dispatch never upgrades a legacy admission');
 raw:=jsonb_set(raw,'{intake_id}',to_jsonb(fresh_i::text));
 q:=public.admit_conversation_versioned_media_intake_v2(u,e,raw);
 PERFORM pg_temp.routing_ok(q->>'action'='admitted' AND EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=fresh_i AND asset_id=old_id),'genuinely new intake binds actual private source');
 PERFORM pg_temp.routing_ok(public.admit_conversation_versioned_media_intake_v2(u,e,raw)->>'action'='replay','private intake retry retains immutable binding');
 PERFORM pg_temp.routing_ok(public.admit_conversation_versioned_media_intake_v2(u,gen_random_uuid(),raw)->>'action'='stale_epoch','dispatch retains current epoch fence');
 PERFORM public.close_conversation_media_v2(u,old_id);
 PERFORM pg_temp.routing_ok(public.admit_conversation_versioned_media_intake_v2(u,e,raw)->>'action'='replay','historical private admission remains replayable after discard');
 DELETE FROM private.conversation_media_assets_v2 WHERE id=old_id;
 PERFORM pg_temp.routing_ok(public.resolve_conversation_media_catalog_v2(u,old_id,NULL) IS NULL,'catalog absence does not fabricate a live source');
 PERFORM pg_temp.routing_ok(public.admit_conversation_versioned_media_intake_v2(u,e,raw)->>'action'='replay','private intake provenance survives catalog absence');
 PERFORM pg_temp.routing_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_requests_v2 WHERE user_id=u AND source_request_hash=h),'transient request reservation adds no retention after catalog removal');
 PERFORM pg_temp.routing_ok(EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=old_id AND catalog_version=2),'opaque upload barrier identity remains independently reserved');
 denied:=false;BEGIN PERFORM public.resolve_conversation_media_catalog_v2(u,a,repeat('b',64));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.routing_ok(denied,'exactly one trusted lookup selector required');
 PERFORM pg_temp.routing_ok(NOT has_table_privilege('service_role','private.conversation_media_requests_v2','SELECT') AND NOT has_function_privilege('authenticated','public.resolve_conversation_media_catalog_v2(uuid,uuid,text)','EXECUTE'),'routing table and client RPC permissions closed');
 old_id:=gen_random_uuid();
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(old_id,u,'meal_photo','meal-photos',u||'/'||old_id||'.jpg','image/jpeg',8,'pending_upload',repeat('c',64),clock_timestamp()+interval '30days');
 UPDATE public.media_assets SET id=replacement_id,object_path=u||'/'||replacement_id||'.jpg' WHERE id=old_id;
 PERFORM pg_temp.routing_ok(public.resolve_conversation_media_catalog_v2(u,NULL,repeat('c',64))->>'asset_id'=replacement_id::text,'valid old catalog identity update retains technical reservation');
END $cases$;
SELECT jsonb_build_object('schema','conversation.private-routing-local-qa.v2','checks',(SELECT count(*) FROM private_routing_checks));
ROLLBACK;

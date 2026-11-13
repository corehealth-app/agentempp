-- Owned local transaction only; no Storage/provider calls.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE expiry_assertions(label text);
CREATE FUNCTION pg_temp.expiry_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'MEDIA_EXPIRY_FAIL:%',label;END IF;INSERT INTO expiry_assertions VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_user uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();f uuid:=gen_random_uuid();legacy uuid:=gen_random_uuid();p jsonb;q jsonb;x jsonb;y jsonb;denied boolean;h uuid:=gen_random_uuid();epoch uuid:=gen_random_uuid();intake_id uuid:=gen_random_uuid();source jsonb;routing jsonb;raw jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'expiry-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(a,u,'audio_note','audio-notes',u||'/'||a||'.m4a','audio/mp4',100,'pending_upload',repeat('1',64),clock_timestamp()-interval '1day'),
 (b,u,'conversation_photo','meal-photos',u||'/'||b||'.jpg','image/jpeg',100,'pending_upload',repeat('2',64),clock_timestamp()-interval '1day'),
 (f,u,'audio_note','audio-notes',u||'/'||f||'.m4a','audio/mp4',100,'pending_upload',repeat('3',64),clock_timestamp()+interval '1day'),
 (legacy,u,'meal_photo','meal-photos',u||'/'||legacy||'.jpg','image/jpeg',100,'pending_upload',repeat('4',64),clock_timestamp()-interval '1day');
 p:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.expiry_ok(jsonb_array_length(p->'items')=2,'only expired ordinary photo/audio enrolled');
 PERFORM pg_temp.expiry_ok((SELECT count(*)=2 FROM public.media_assets WHERE user_id=u AND status='deleted'),'expired rows closed before Storage work');
 PERFORM pg_temp.expiry_ok((SELECT bool_and(status='pending_upload') FROM public.media_assets WHERE id IN(f,legacy)),'future and legacy rows untouched');
 PERFORM pg_temp.expiry_ok((SELECT count(*)=2 FROM private.conversation_media_expiry_debts WHERE user_id=u),'durable independent manifest persisted');
 PERFORM pg_temp.expiry_ok(jsonb_array_length(public.claim_conversation_media_expiry_batch(100)->'items')=0,'live claims not concurrently issued twice');
 FOR x IN SELECT value FROM jsonb_array_elements(p->'items') LOOP
  denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_expiry_sweep((x->>'asset_id')::uuid,other_user,(x->>'claim_token')::uuid);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
  PERFORM pg_temp.expiry_ok(denied,'foreign owner acknowledgment refused');
  denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_expiry_sweep((x->>'asset_id')::uuid,u,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
  PERFORM pg_temp.expiry_ok(denied,'stale claim acknowledgment refused');
  q:=public.acknowledge_conversation_media_expiry_sweep((x->>'asset_id')::uuid,u,(x->>'claim_token')::uuid);
  PERFORM pg_temp.expiry_ok(q->>'state'='waiting_for_issuance_drain','success does not pretend untracked issuer drained');
  PERFORM pg_temp.expiry_ok(public.acknowledge_conversation_media_expiry_sweep((x->>'asset_id')::uuid,u,(x->>'claim_token')::uuid)=q,'acknowledgment replay stable');
 END LOOP;
 p:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.expiry_ok(jsonb_array_length(p->'items')=2,'deleted rows retain a second physical sweep after late uploads');
 FOR x IN SELECT value FROM jsonb_array_elements(p->'items') LOOP PERFORM public.acknowledge_conversation_media_expiry_sweep((x->>'asset_id')::uuid,u,(x->>'claim_token')::uuid);END LOOP;
 DELETE FROM public.media_assets WHERE id=a;
 p:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.expiry_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'items') v WHERE v->>'asset_id'=a::text),'catalog removal cannot orphan outstanding Storage cleanup');
 denied:=false;BEGIN PERFORM public.claim_conversation_media_expiry_batch(101);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.expiry_ok(denied,'bounded batch enforced in SQL');
 PERFORM pg_temp.expiry_ok(NOT has_table_privilege('service_role','private.conversation_media_expiry_debts','SELECT'),'private manifest not directly readable by service role');
 PERFORM pg_temp.expiry_ok(NOT has_function_privilege('authenticated','public.claim_conversation_media_expiry_batch(integer)','EXECUTE') AND NOT has_function_privilege('anon','public.acknowledge_conversation_media_expiry_sweep(uuid,uuid,uuid)','EXECUTE'),'client RPC access closed');
 PERFORM pg_temp.expiry_ok(has_function_privilege('service_role','public.claim_conversation_media_expiry_batch(integer)','EXECUTE'),'trusted worker RPC access available');
 -- A real immutable historical projection remains readable after catalog data
 -- and processing output are disposed. This is not live domain/XP E2E proof.
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,epoch,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(h,u,'conversation_photo','meal-photos',u||'/'||h||'.jpg','image/jpeg',100,100,'processed',repeat('5',64),repeat('6',64),clock_timestamp()+interval '1day',clock_timestamp(),clock_timestamp(),'{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[{"name":"arroz","confidence":0.95,"quantity_g_estimate":100}]}}');
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',intake_id,'source',jsonb_build_object('channel','media','media_asset_id',h,'user_action','report_actual_record','caption','Comi arroz 100 g'));
 p:=public.admit_conversation_intake(u,epoch,raw);
 source:=public.capture_conversation_intake_source(u,intake_id,p#>>'{intake,input_hash}',epoch);
 routing:=public.claim_conversation_intake_routing(u,intake_id,p#>>'{intake,input_hash}',epoch,source->>'source_hash');
 x:=public.seal_conversation_intake_routing(u,intake_id,p#>>'{intake,input_hash}',epoch,source->>'source_hash',(routing->>'claim_id')::uuid,'{"schema":"conversation.intake-routing.v1","kind":"meal.report","reason":"processed_media_report"}')->'selection';
 PERFORM pg_temp.expiry_ok(x->>'schema'='conversation.intake-selection.v2','genuine original processed-media selection exists before expiry');
 y:=x#>'{command,input}';
 UPDATE public.media_assets SET retention_until=clock_timestamp()-interval '1day' WHERE id=h;
 p:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.expiry_ok(private.conversation_intake_media_projection(u,y,true,false)=x->'media_projection','historical typed source survives physical-disposal manifest enrollment');
 PERFORM pg_temp.expiry_ok((SELECT processing_result IS NULL AND status='deleted' FROM public.media_assets WHERE id=h),'active media payload erased while historical source stays intact');
 UPDATE private.conversation_media_expiry_debts SET lease_until=clock_timestamp()-interval '1microsecond' WHERE claim_token IS NOT NULL;
 p:=public.claim_conversation_media_expiry_batch(1);q:=public.claim_conversation_media_expiry_batch(1);
 PERFORM pg_temp.expiry_ok(jsonb_array_length(p->'items')=1 AND jsonb_array_length(q->'items')=1 AND p#>>'{items,0,asset_id}'<>q#>>'{items,0,asset_id}','unacknowledged claim yields fairly to another expired asset');

END $cases$;
SELECT jsonb_build_object('schema','conversation.media-expiry-local-qa.v1','assertions',(SELECT count(*) FROM expiry_assertions));
ROLLBACK;

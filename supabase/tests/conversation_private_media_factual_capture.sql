-- Owned local rollback only: actual admission/capture/selection functions.
-- No Storage/provider/remote calls or direct domain-fact inserts.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
CREATE TEMP TABLE private_capture_checks(label text PRIMARY KEY);
CREATE TEMP TABLE private_capture_goldens(kind text,neutral jsonb,selection jsonb,typed jsonb);
CREATE FUNCTION pg_temp.capture_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_CAPTURE_FAIL:%',label;END IF;
INSERT INTO private_capture_checks VALUES(label);END $$;
SELECT pg_temp.capture_ok(to_regprocedure('public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb)') IS NOT NULL,'private versioned admission installed');
\ir fixtures/conversation_private_media_capture_fixture.sql
-- Reuse the existing synthetic resolved-result fixture only for atomic writer
-- qualification; automatic nutritional resolution is a separate app QA gate.
\ir fixtures/conversation_meal_atomic_writer_fixture.sql
DO $cases$
DECLARE s jsonb;q jsonb;r jsonb;a jsonb;u uuid;e uuid;i uuid;child uuid;kind text;domain text;result jsonb;denied boolean;old uuid;raw jsonb;
BEGIN
 FOREACH kind IN ARRAY ARRAY['conversation_photo','audio_note'] LOOP
  result:=CASE kind WHEN 'conversation_photo' THEN '{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[{"name":"arroz","quantity_g_estimate":100,"confidence":0.9}]}}'::jsonb ELSE '{"text":"Comi arroz 100 g"}'::jsonb END;
  s:=pg_temp.private_seed(kind,'Comi arroz 100 g',result);u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;i:=(s->>'intake')::uuid;
  q:=pg_temp.private_select(s,'meal.report');child:=(q#>>'{sealed,selection,command,command_id}')::uuid;
  PERFORM pg_temp.capture_ok(q#>>'{admission,action}'='admitted','actual private intake admission '||kind);
  PERFORM pg_temp.capture_ok(q#>>'{source,context,media,catalog_version}'='2' AND q#>>'{source,context,media,kind}'=kind,'neutral capture retains exact private purpose and version '||kind);
  PERFORM pg_temp.capture_ok(q#>>'{sealed,action}'='sealed' AND q#>>'{sealed,selection,media_projection,media,catalog_version}'='2','selection binds private version '||kind);
  PERFORM pg_temp.capture_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=(s->>'asset')::uuid),'no public media mirror '||kind);
  r:=public.capture_conversation_meal_source(u,child);
  PERFORM pg_temp.capture_ok(r#>'{context,media,processing_result}'=result AND r#>>'{context,media,catalog_version}'='2','typed meal capture uses original private processing result '||kind);
  PERFORM pg_temp.capture_ok(r#>>'{context,intake_projection,media,catalog_version}'='2','typed meal projection retains private provenance '||kind);
  INSERT INTO private_capture_goldens VALUES(kind,q->'source',q#>'{sealed,selection}',r);
  PERFORM pg_temp.capture_ok(private.conversation_continuation_original_current(u,jsonb_build_object('source',r)),'linked clarification sees the current private source '||kind);
  PERFORM pg_temp.capture_ok(public.admit_conversation_private_media_intake_v2(u,e,s->'input')->>'action'='replay','private intake retry reuses admission '||kind);
  a:=public.capture_conversation_meal_source(u,child);
  PERFORM pg_temp.capture_ok(a->>'action'='replay' AND a-'action'=r-'action','typed capture retry returns frozen context '||kind);
  PERFORM pg_temp.capture_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'interpretation alone does not create domain facts '||kind);
  UPDATE private.conversation_media_assets_v2 SET status='deleted',deleted_at=clock_timestamp(),updated_at=clock_timestamp(),processing_result=NULL,processed_at=NULL WHERE id=(s->>'asset')::uuid;
  denied:=false;BEGIN PERFORM private.conversation_continuation_original_current(u,jsonb_build_object('source',r));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
  PERFORM pg_temp.capture_ok(denied,'disposed private source cannot support a new clarification '||kind);
 END LOOP;

 s:=pg_temp.private_seed('audio_note',NULL,'{"text":"Caminhei por 12 minutos"}');u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;
 q:=pg_temp.private_select(s,'workout.report');child:=(q#>>'{sealed,selection,command,command_id}')::uuid;
 r:=public.capture_conversation_workout_source(u,child,q#>>'{sealed,selection,command,input_hash}',e);
 PERFORM pg_temp.capture_ok(q#>>'{sealed,action}'='sealed' AND r#>>'{context,media,catalog_version}'='2','typed workout capture retains private source version');
 PERFORM pg_temp.capture_ok(r#>>'{context,media,processing_result,text}'='Caminhei por 12 minutos','workout source uses the original private transcript');
 INSERT INTO private_capture_goldens VALUES('audio_workout',q->'source',q#>'{sealed,selection}',r);

 DECLARE prepared jsonb;effect jsonb;BEGIN
  s:=pg_temp.private_seed('audio_note','Fiz 30 minutos de caminhada leve','{"text":"Fiz 30 minutos de caminhada leve"}');u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;
  q:=pg_temp.private_select(s,'workout.report');child:=(q#>>'{sealed,selection,command,command_id}')::uuid;
  r:=public.capture_conversation_workout_source(u,child,q#>>'{sealed,selection,command,input_hash}',e);
  prepared:=public.prepare_conversation_workout(u,child,q#>>'{sealed,selection,command,input_hash}',r->>'source_hash',e,private.conversation_workout_report(r->'context',r->>'source_hash'));
  PERFORM pg_temp.capture_ok(prepared#>>'{prepared,status}'='ready','private transcript reaches the unchanged performed-authority resolver');
  effect:=public.commit_conversation_workout(u,child,q#>>'{sealed,selection,command,input_hash}',r->>'source_hash',e,prepared->>'prepared_hash',prepared->'prepared');
  PERFORM pg_temp.capture_ok(effect->>'action'='committed' AND(SELECT count(*)=1 FROM public.workout_logs WHERE user_id=u),'private transcript reaches the original atomic workout writer');
  PERFORM pg_temp.capture_ok(public.commit_conversation_workout(u,child,q#>>'{sealed,selection,command,input_hash}',r->>'source_hash',e,prepared->>'prepared_hash',prepared->'prepared')=jsonb_set(effect,'{action}','"replay"'),'private workout technical replay preserves one fact and original receipt');

  s:=pg_temp.private_seed('audio_note','Comi arroz 100 g','{"text":"Comi arroz 100 g"}');u:=(s->>'owner')::uuid;
  q:=pg_temp.private_select(s,'meal.report');child:=(q#>>'{sealed,selection,command,command_id}')::uuid;r:=public.capture_conversation_meal_source(u,child);
  prepared:=public.prepare_conversation_meal(u,child,pg_temp.writer_resolved(r));effect:=public.commit_conversation_meal(u,child,prepared->>'resolved_hash');
  PERFORM pg_temp.capture_ok(effect->>'action'='committed' AND(SELECT count(*)=1 FROM public.meal_logs WHERE user_id=u),'private source reaches original meal writer with synthetic resolution only');
  PERFORM pg_temp.capture_ok(public.commit_conversation_meal(u,child,NULL)=jsonb_set(effect,'{action}','"replay"'),'private meal technical replay preserves one fact and original receipt');
 END;

 s:=pg_temp.private_seed('audio_note',NULL,'{"text":"Comi arroz 100 g"}');u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;i:=(s->>'intake')::uuid;
 a:=public.admit_conversation_private_media_intake_v2(u,e,s->'input');
 q:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
 UPDATE private.conversation_media_obligations_v2 SET closed_at=clock_timestamp() WHERE asset_id=(s->>'asset')::uuid;
 PERFORM pg_temp.capture_ok((SELECT status='processed' FROM private.conversation_media_assets_v2 WHERE id=(s->>'asset')::uuid),'discard intent test retains preexisting processed metadata');
 raw:=jsonb_set(s->'input','{intake_id}',to_jsonb(gen_random_uuid()::text));
 PERFORM pg_temp.capture_ok(public.admit_conversation_private_media_intake_v2(u,e,raw)->>'action'='media_unavailable','closed independent obligation blocks a new intake before catalog cleanup');
 PERFORM pg_temp.capture_ok(public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e)->>'action'='media_unavailable','closed obligation cannot be recaptured from processed metadata');

 -- Exercise actual legacy-ID removal and private-ID reuse, retaining the
 -- genuine original selection and typed source hash throughout.
 DECLARE legacy_asset uuid:=gen_random_uuid();legacy_intake uuid:=gen_random_uuid();legacy_ticket uuid:=gen_random_uuid();c jsonb;claim jsonb;sealed jsonb;before_source jsonb;token uuid;BEGIN
  s:=pg_temp.private_seed('audio_note',NULL,'{"text":"another independent private source"}');u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;
  INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
  VALUES(legacy_asset,u,'audio_note','audio-notes',u||'/'||legacy_asset||'.m4a','audio/mp4',8,8,'processed',encode(sha256(convert_to(legacy_asset::text,'UTF8')),'hex'),repeat('b',64),clock_timestamp()+interval '1day',clock_timestamp(),clock_timestamp(),'{"text":"Comi pão 50 g"}');
  raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',legacy_intake,'source',jsonb_build_object('channel','media','media_asset_id',legacy_asset,'user_action','report_actual_record'));
  a:=public.admit_conversation_intake(u,e,raw);c:=public.capture_conversation_intake_source(u,legacy_intake,a#>>'{intake,input_hash}',e);
  claim:=public.claim_conversation_intake_routing(u,legacy_intake,a#>>'{intake,input_hash}',e,c->>'source_hash');
  sealed:=public.seal_conversation_intake_routing(u,legacy_intake,a#>>'{intake,input_hash}',e,c->>'source_hash',(claim->>'claim_id')::uuid,'{"schema":"conversation.intake-routing.v1","kind":"meal.report","reason":"processed_media_report"}');
  child:=(sealed#>>'{selection,command,command_id}')::uuid;before_source:=public.capture_conversation_meal_source(u,child);
  PERFORM pg_temp.capture_ok(NOT(before_source#>'{context,media}' ? 'catalog_version'),'legacy typed source remains literal without a new version field');
  DELETE FROM public.media_assets WHERE id=legacy_asset;
  PERFORM public.create_conversation_media_asset_v2(u,legacy_asset,'audio_note','audio/mp4',8,NULL,encode(sha256(convert_to('new-'||legacy_asset::text,'UTF8')),'hex'));
  PERFORM public.prepare_conversation_media_upload_v2(u,legacy_asset,legacy_ticket);
  PERFORM public.register_conversation_media_upload_v2(u,legacy_asset,legacy_ticket,date_trunc('second',clock_timestamp())+interval '2hours');
  PERFORM public.complete_conversation_media_upload_v2(u,legacy_asset,8,'audio/mp4',NULL);
  claim:=public.claim_conversation_media_processing_v2(u,legacy_asset,repeat('c',64));token:=(claim#>>'{claim,token}')::uuid;
  PERFORM public.complete_conversation_media_processing_v2(u,legacy_asset,repeat('c',64),token,'{"text":"Comi arroz 200 g"}');
  PERFORM pg_temp.capture_ok(EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE id=legacy_asset) AND NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=legacy_asset),'legacy opaque ID is genuinely reused only in the private catalog');
  PERFORM pg_temp.capture_ok(public.admit_conversation_private_media_intake_v2(u,e,raw)->>'action'='input_conflict','genuine reused asset ID cannot upgrade its old intake');
  PERFORM pg_temp.capture_ok(public.capture_conversation_intake_source(u,legacy_intake,a#>>'{intake,input_hash}',e)->>'action'='media_unavailable','old neutral capture refuses a later private source with the same ID');
  r:=public.capture_conversation_meal_source(u,child);
  PERFORM pg_temp.capture_ok(r->>'action'='replay' AND r-'action'=before_source-'action' AND r#>>'{context,media,processing_result,text}'='Comi pão 50 g','historical typed receipt keeps the original legacy transcript and hash');
  raw:=jsonb_set(raw,'{intake_id}',to_jsonb(gen_random_uuid()::text));a:=public.admit_conversation_private_media_intake_v2(u,e,raw);
  c:=public.capture_conversation_intake_source(u,(raw->>'intake_id')::uuid,a#>>'{intake,input_hash}',e);
  PERFORM pg_temp.capture_ok(c#>>'{context,media,catalog_version}'='2' AND c#>>'{context,media,processing_result,text}'='Comi arroz 200 g','a genuinely new intake may explicitly bind the new private source');
 END;

 -- A legacy admission is permanently version1 even if its opaque asset ID is
 -- later used by a new private source after the legacy row is gone.
 s:=pg_temp.private_seed('audio_note',NULL,'{"text":"Comi arroz"}');u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;i:=(s->>'intake')::uuid;
 -- This legacy admission must precede private creation. The previous seed
 -- already created v2 first, contrary to this case's ID-reuse comment.
 DECLARE prior_a uuid:=gen_random_uuid();BEGIN
  INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
  VALUES(prior_a,u,'audio_note','audio-notes',u||'/'||prior_a||'.m4a','audio/mp4',8,'pending_upload',repeat('f',64),clock_timestamp()+interval '30days');
  s:=jsonb_set(s,'{input,source,media_asset_id}',to_jsonb(prior_a::text));
  a:=public.admit_conversation_intake(u,e,s->'input');
  DELETE FROM public.media_assets WHERE id=prior_a;
  PERFORM public.create_conversation_media_asset_v2(u,prior_a,'audio_note','audio/mp4',8,NULL,repeat('f',64));
 END;
 PERFORM pg_temp.capture_ok(a->>'action'='admitted','legacy admission accepts its unchanged input protocol');
 PERFORM pg_temp.capture_ok(public.admit_conversation_private_media_intake_v2(u,e,s->'input')->>'action'='input_conflict','existing legacy intake cannot be upgraded to private');
 PERFORM pg_temp.capture_ok(public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e)->>'action'='media_unavailable','legacy capture never probes the private catalog');
 PERFORM pg_temp.capture_ok(NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=i),'failed upgrade creates no private binding');
 denied:=false;BEGIN UPDATE private.conversation_private_media_intakes_v2 SET asset_id=gen_random_uuid();EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.capture_ok(denied,'existing private binding cannot change asset');
 PERFORM pg_temp.capture_ok(NOT has_table_privilege('service_role','private.conversation_private_media_intakes_v2','SELECT,INSERT,UPDATE,DELETE'),'private binding is inaccessible to direct backend table operations');
 PERFORM pg_temp.capture_ok(NOT has_function_privilege('authenticated','public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb)','EXECUTE'),'untrusted role cannot bind a private intake');
END $cases$;
SELECT pg_temp.capture_ok(NOT EXISTS(SELECT 1 FROM private_capture_goldens WHERE to_jsonb(private_capture_goldens)::text LIKE '%conversation-v2/%'),'captured source and selection never expose the private Storage key');
SELECT jsonb_build_object('passed',count(*),'labels',jsonb_agg(label ORDER BY label)) FROM private_capture_checks;
SELECT jsonb_build_object('schema','conversation.private-capture-local-goldens.v2','rows',jsonb_agg(to_jsonb(g) ORDER BY kind)) FROM private_capture_goldens g;
ROLLBACK;

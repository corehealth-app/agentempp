-- Genuine T39/T41 processed-media child lineage; owned local rollback only.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
CREATE TEMP TABLE t44_assertions(label text);
CREATE TEMP TABLE t44_goldens(kind text,selection jsonb,source jsonb,prepared jsonb,effect jsonb);
CREATE FUNCTION pg_temp.t44_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'T44_FAIL:%',label;END IF;INSERT INTO t44_assertions VALUES(label);END $$;
CREATE FUNCTION pg_temp.t44_seed(k text,caption text,context text,processed jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();m uuid:=gen_random_uuid();a jsonb;s jsonb;c jsonb;raw jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'t44-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,context_text,processing_result)
 VALUES(m,u,k,CASE WHEN k='audio_note' THEN 'audio-notes' WHEN k='gym_photo' THEN 'gym-photos' ELSE 'meal-photos' END,u||'/'||m||'.bin',CASE WHEN k='audio_note' THEN 'audio/mpeg' ELSE 'image/jpeg' END,1200,1200,'processed',repeat('a',64),repeat('b',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),context,processed);
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_strip_nulls(jsonb_build_object('channel','media','media_asset_id',m,'user_action','report_actual_record','caption',caption)));
 a:=public.admit_conversation_intake(u,e,raw);s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');
 RETURN jsonb_build_object('intake',a->'intake','source',s,'claim',c,'raw',raw);
END $$;
CREATE FUNCTION pg_temp.t44_seal(s jsonb,k text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.seal_conversation_intake_routing((s#>>'{intake,owner_id}')::uuid,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid,s#>>'{source,source_hash}',(s#>>'{claim,claim_id}')::uuid,jsonb_build_object('schema','conversation.intake-routing.v1','kind',k,'reason','processed_media_report'));
$$;

DO $ordinary_meal$
DECLARE s jsonb;x jsonb;r jsonb;u uuid;child uuid;raw jsonb;result jsonb;
BEGIN
 result:='{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[{"name":"arroz","quantity_g_estimate":100,"confidence":0.95}]}}';
 s:=pg_temp.t44_seed('conversation_photo','Comi arroz 100 g',NULL,result);
 PERFORM pg_temp.t44_ok(s#>>'{source,action}'='captured','ordinary photo retains genuine neutral capture');
 x:=pg_temp.t44_seal(s,'meal.report');PERFORM pg_temp.t44_ok(x->>'action'='sealed','classified ordinary meal seals a real reserved meal child');
 u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;raw:=x#>'{selection,command,input}';
 PERFORM pg_temp.t44_ok(x#>>'{selection,media_projection,media,kind}'='conversation_photo','ordinary purpose is never retagged meal_photo');
 r:=public.capture_conversation_meal_source(u,child);
 PERFORM pg_temp.t44_ok(r#>'{context,media,processing_result}'=result AND r#>>'{context,media,kind}'='conversation_photo','typed source hashes the original classified envelope unchanged');
 PERFORM pg_temp.t44_ok(r#>'{context,source_units}'='["media_caption","vision_items"]','classified meal contributes observations beside the literal caption');
 PERFORM pg_temp.t44_ok(private.conversation_continuation_original_current(u,jsonb_build_object('source',r)),'ordinary meal remains a genuine current linked clarification source');
 PERFORM pg_temp.t44_ok(public.admit_conversation_meal_command_fenced(u,raw,(s#>>'{intake,epoch}')::uuid)->>'action'='replay','ordinary typed retry preserves original selection');
 INSERT INTO t44_goldens VALUES('ordinary_meal',x,r,NULL,NULL);
 -- Exercise the actual durable semantic validator against the same captured
 -- envelope; only provider metadata is synthetic and no writer is invoked.
 DECLARE attempt jsonb;semantic jsonb;committed jsonb;
 BEGIN
  attempt:=public.start_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1',r->>'source_hash');
  semantic:=jsonb_build_object('schema','conversation.meal-interpretation.v1','interpreter_version','conversation.meal-interpreter.v1','owner_id',u,'command_id',child,'attempt_id',attempt->'attempt_id','input_hash',r#>'{context,input_hash}','source_hash',r->'source_hash','source_units',r#>'{context,source_units}','decision','reported_meal','reason','explicit_media_action',
   'sources','[{"unit":"media_caption","classification":"reported","visual_indexes":[],"spans":[{"start":0,"end":4,"kind":"report","food_index":null},{"start":4,"end":5,"kind":"separator","food_index":null},{"start":5,"end":10,"kind":"food","food_index":0},{"start":10,"end":11,"kind":"separator","food_index":null},{"start":11,"end":14,"kind":"quantity","food_index":0},{"start":14,"end":15,"kind":"separator","food_index":null},{"start":15,"end":16,"kind":"unit","food_index":0}]},{"unit":"vision_items","classification":"visual","visual_indexes":[0],"spans":[]}]'::jsonb,
   'foods','[{"index":0,"name":{"unit":"media_caption","start":5,"end":10},"quantity":{"unit":"media_caption","start":11,"end":14},"unit":{"unit":"media_caption","start":15,"end":16},"visual_index":0}]'::jsonb,
   'provider_metadata','{"model":"synthetic/no-provider","prompt_tokens":0,"completion_tokens":0,"cost_usd":0,"latency_ms":0}'::jsonb);
  committed:=public.commit_conversation_meal_semantic_result(u,child,'conversation.meal-interpreter.v1',(attempt->>'attempt_id')::uuid,semantic);
  PERFORM pg_temp.t44_ok(committed->>'status'='completed' AND committed->'result'=semantic,'real semantic receipt uses extracted observations while retaining original processing hash');
  PERFORM pg_temp.t44_ok(public.read_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1')->'result'=semantic AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'semantic replay does not invent consumption facts or rewards');
 END;
END $ordinary_meal$;
DO $ordinary_label$
DECLARE s jsonb;x jsonb;r jsonb;a jsonb;u uuid;child uuid;raw jsonb;
BEGIN
 raw:='{"schema":"conversation.image-result.v1","status":"ready","classification":"nutrition_label","analysis":{"type":"nutrition_label","product_name":"whey","serving_size_g":30,"per_serving":{"kcal":120,"protein_g":24,"carbs_g":3,"fat_g":1},"per_100g":{"kcal":400,"protein_g":80,"carbs_g":10,"fat_g":3.3},"confidence":0.95}}';
 s:=pg_temp.t44_seed('conversation_photo',NULL,NULL,raw);x:=pg_temp.t44_seal(s,'meal.report');
 PERFORM pg_temp.t44_ok(x->>'action'='sealed','printed label has genuine meal clarification lineage');
 u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;r:=public.capture_conversation_meal_source(u,child);
 a:=private.conversation_meal_media_analysis('conversation_photo',raw);
 PERFORM pg_temp.t44_ok(a#>>'{items,0,quantity_g_estimate}'='0' AND a#>>'{nutrition_label,serving_size_g}'='30','printed serving remains label metadata rather than consumed quantity');
 PERFORM pg_temp.t44_ok(r#>'{context,media,processing_result}'=raw AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'label extraction leaves original bytes and facts untouched');
 INSERT INTO t44_goldens VALUES('ordinary_label_missing_portion',x,r,NULL,NULL);
END $ordinary_label$;
DO $ordinary_equipment$
DECLARE s jsonb;x jsonb;r jsonb;p jsonb;u uuid;child uuid;h text;e uuid;
BEGIN
 s:=pg_temp.t44_seed('conversation_photo',NULL,NULL,'{"schema":"conversation.image-result.v1","status":"ready","classification":"equipment","analysis":{"type":"equipment","equipment":["esteira"],"location":"academia_completa","confidence":0.9}}');
 x:=pg_temp.t44_seal(s,'workout.report');PERFORM pg_temp.t44_ok(x->>'action'='sealed','classified equipment can use genuine workout clarification lineage');
 u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;h:=x#>>'{selection,command,input_hash}';e:=(s#>>'{intake,epoch}')::uuid;
 r:=public.capture_conversation_workout_source(u,child,h,e);p:=private.conversation_workout_report(r->'context',r->>'source_hash');
 PERFORM pg_temp.t44_ok(p->>'status'='needs_reply' AND p#>>'{question,field}'='activity' AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'equipment pixels do not become a performed workout or calorie estimate');
 INSERT INTO t44_goldens VALUES('ordinary_equipment_not_performed',x,r,p,NULL);
END $ordinary_equipment$;
DO $unsupported_and_mismatched$
DECLARE class text;s jsonb;x jsonb;u uuid;
BEGIN
 FOREACH class IN ARRAY ARRAY['body','scale','other','unknown'] LOOP
  s:=pg_temp.t44_seed('conversation_photo',NULL,NULL,jsonb_build_object('schema','conversation.image-result.v1','status','unsupported','classification',class,'reason','image_not_supported_for_conversation'));
  PERFORM pg_temp.t44_ok(s#>>'{source,action}'='captured','unsupported image can complete neutral non-recording observation');
  x:=pg_temp.t44_seal(s,'meal.report');u:=(s#>>'{intake,owner_id}')::uuid;
  PERFORM pg_temp.t44_ok(x='{"action":"media_projection_required"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'unsupported class cannot mint a meal child');
 END LOOP;
 s:=pg_temp.t44_seed('conversation_photo',NULL,NULL,'{"schema":"conversation.image-result.v1","status":"ready","classification":"equipment","analysis":{"type":"equipment","equipment":[],"location":null,"confidence":0.9}}');
 x:=pg_temp.t44_seal(s,'meal.report');PERFORM pg_temp.t44_ok(x='{"action":"media_projection_required"}','equipment cannot become a meal through a routing hint');
 s:=pg_temp.t44_seed('conversation_photo',NULL,NULL,'{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[{"name":"arroz","quantity_g_estimate":100,"confidence":0.95}]}}');
 x:=pg_temp.t44_seal(s,'workout.report');PERFORM pg_temp.t44_ok(x='{"action":"media_projection_required"}','meal cannot become a workout through a routing hint');
END $unsupported_and_mismatched$;
DO $review_label_identity$
DECLARE name jsonb;raw jsonb;s jsonb;x jsonb;u uuid;
BEGIN
 FOREACH name IN ARRAY ARRAY['null'::jsonb,'""'::jsonb,'" "'::jsonb,to_jsonb(repeat('x',241))] LOOP
  raw:=jsonb_build_object('schema','conversation.image-result.v1','status','ready','classification','nutrition_label','analysis',jsonb_build_object('type','nutrition_label','product_name',name,'serving_size_g',30,'per_serving',jsonb_build_object('kcal',120,'protein_g',24,'carbs_g',3,'fat_g',1),'per_100g',jsonb_build_object('kcal',400,'protein_g',80,'carbs_g',10,'fat_g',3.3),'confidence',0.95));
  s:=pg_temp.t44_seed('conversation_photo',NULL,NULL,raw);x:=pg_temp.t44_seal(s,'meal.report');u:=(s#>>'{intake,owner_id}')::uuid;
  PERFORM pg_temp.t44_ok(x='{"action":"media_projection_required"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'unusable label identity cannot create a stranded meal child');
 END LOOP;
END $review_label_identity$;
DO $review_caption_only$
DECLARE s jsonb;x jsonb;r jsonb;u uuid;child uuid;raw jsonb;result jsonb;
BEGIN
 result:='{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[]}}';
 s:=pg_temp.t44_seed('conversation_photo','Comi arroz 100 g',NULL,result);
 PERFORM pg_temp.t44_ok(s#>>'{source,action}'='captured','ordinary photo retains genuine neutral capture');
 x:=pg_temp.t44_seal(s,'meal.report');PERFORM pg_temp.t44_ok(x->>'action'='sealed','empty ordinary meal with caption seals real typed child');
 u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;raw:=x#>'{selection,command,input}';
 PERFORM pg_temp.t44_ok(x#>>'{selection,media_projection,media,kind}'='conversation_photo','ordinary purpose is never retagged meal_photo');
 r:=public.capture_conversation_meal_source(u,child);
 PERFORM pg_temp.t44_ok(r#>'{context,media,processing_result}'=result AND r#>>'{context,media,kind}'='conversation_photo','typed source hashes the original classified envelope unchanged');
 PERFORM pg_temp.t44_ok(r#>'{context,source_units}'='["media_caption"]','empty image preserves the complete literal caption without a fictional visual unit');
 PERFORM pg_temp.t44_ok(private.conversation_continuation_original_current(u,jsonb_build_object('source',r)),'ordinary meal remains a genuine current linked clarification source');
 PERFORM pg_temp.t44_ok(public.admit_conversation_meal_command_fenced(u,raw,(s#>>'{intake,epoch}')::uuid)->>'action'='replay','ordinary typed retry preserves original selection');
 INSERT INTO t44_goldens VALUES('ordinary_meal_caption_only',x,r,NULL,NULL);
 -- Exercise the actual durable semantic validator against the same captured
 -- envelope; only provider metadata is synthetic and no writer is invoked.
 DECLARE attempt jsonb;semantic jsonb;committed jsonb;
 BEGIN
  attempt:=public.start_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1',r->>'source_hash');
  semantic:=jsonb_build_object('schema','conversation.meal-interpretation.v1','interpreter_version','conversation.meal-interpreter.v1','owner_id',u,'command_id',child,'attempt_id',attempt->'attempt_id','input_hash',r#>'{context,input_hash}','source_hash',r->'source_hash','source_units',r#>'{context,source_units}','decision','reported_meal','reason','explicit_media_action',
   'sources','[{"unit":"media_caption","classification":"reported","visual_indexes":[],"spans":[{"start":0,"end":4,"kind":"report","food_index":null},{"start":4,"end":5,"kind":"separator","food_index":null},{"start":5,"end":10,"kind":"food","food_index":0},{"start":10,"end":11,"kind":"separator","food_index":null},{"start":11,"end":14,"kind":"quantity","food_index":0},{"start":14,"end":15,"kind":"separator","food_index":null},{"start":15,"end":16,"kind":"unit","food_index":0}]}]'::jsonb,
   'foods','[{"index":0,"name":{"unit":"media_caption","start":5,"end":10},"quantity":{"unit":"media_caption","start":11,"end":14},"unit":{"unit":"media_caption","start":15,"end":16},"visual_index":null}]'::jsonb,
   'provider_metadata','{"model":"synthetic/no-provider","prompt_tokens":0,"completion_tokens":0,"cost_usd":0,"latency_ms":0}'::jsonb);
  committed:=public.commit_conversation_meal_semantic_result(u,child,'conversation.meal-interpreter.v1',(attempt->>'attempt_id')::uuid,semantic);
  PERFORM pg_temp.t44_ok(committed->>'status'='completed' AND committed->'result'=semantic,'real semantic receipt uses extracted observations while retaining original processing hash');
  PERFORM pg_temp.t44_ok(public.read_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1')->'result'=semantic AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'semantic replay does not invent consumption facts or rewards');
 END;
END $review_caption_only$;
DO $review_context_only$
DECLARE s jsonb;x jsonb;r jsonb;u uuid;child uuid;raw jsonb;result jsonb;
BEGIN
 result:='{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[]}}';
 s:=pg_temp.t44_seed('conversation_photo',NULL,'Comi arroz 100 g',result);
 PERFORM pg_temp.t44_ok(s#>>'{source,action}'='captured','ordinary photo retains genuine neutral capture');
 x:=pg_temp.t44_seal(s,'meal.report');PERFORM pg_temp.t44_ok(x->>'action'='sealed','empty ordinary meal with caption seals real typed child');
 u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;raw:=x#>'{selection,command,input}';
 PERFORM pg_temp.t44_ok(x#>>'{selection,media_projection,media,kind}'='conversation_photo','ordinary purpose is never retagged meal_photo');
 r:=public.capture_conversation_meal_source(u,child);
 PERFORM pg_temp.t44_ok(r#>'{context,media,processing_result}'=result AND r#>>'{context,media,kind}'='conversation_photo','typed source hashes the original classified envelope unchanged');
 PERFORM pg_temp.t44_ok(r#>'{context,source_units}'='["media_context"]','empty image preserves the complete literal caption without a fictional visual unit');
 PERFORM pg_temp.t44_ok(private.conversation_continuation_original_current(u,jsonb_build_object('source',r)),'ordinary meal remains a genuine current linked clarification source');
 PERFORM pg_temp.t44_ok(public.admit_conversation_meal_command_fenced(u,raw,(s#>>'{intake,epoch}')::uuid)->>'action'='replay','ordinary typed retry preserves original selection');
 INSERT INTO t44_goldens VALUES('ordinary_meal_context_only',x,r,NULL,NULL);
 -- Exercise the actual durable semantic validator against the same captured
 -- envelope; only provider metadata is synthetic and no writer is invoked.
 DECLARE attempt jsonb;semantic jsonb;committed jsonb;
 BEGIN
  attempt:=public.start_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1',r->>'source_hash');
  semantic:=jsonb_build_object('schema','conversation.meal-interpretation.v1','interpreter_version','conversation.meal-interpreter.v1','owner_id',u,'command_id',child,'attempt_id',attempt->'attempt_id','input_hash',r#>'{context,input_hash}','source_hash',r->'source_hash','source_units',r#>'{context,source_units}','decision','reported_meal','reason','explicit_media_action',
   'sources','[{"unit":"media_context","classification":"reported","visual_indexes":[],"spans":[{"start":0,"end":4,"kind":"report","food_index":null},{"start":4,"end":5,"kind":"separator","food_index":null},{"start":5,"end":10,"kind":"food","food_index":0},{"start":10,"end":11,"kind":"separator","food_index":null},{"start":11,"end":14,"kind":"quantity","food_index":0},{"start":14,"end":15,"kind":"separator","food_index":null},{"start":15,"end":16,"kind":"unit","food_index":0}]}]'::jsonb,
   'foods','[{"index":0,"name":{"unit":"media_context","start":5,"end":10},"quantity":{"unit":"media_context","start":11,"end":14},"unit":{"unit":"media_context","start":15,"end":16},"visual_index":null}]'::jsonb,
   'provider_metadata','{"model":"synthetic/no-provider","prompt_tokens":0,"completion_tokens":0,"cost_usd":0,"latency_ms":0}'::jsonb);
  committed:=public.commit_conversation_meal_semantic_result(u,child,'conversation.meal-interpreter.v1',(attempt->>'attempt_id')::uuid,semantic);
  PERFORM pg_temp.t44_ok(committed->>'status'='completed' AND committed->'result'=semantic,'real semantic receipt uses extracted observations while retaining original processing hash');
  PERFORM pg_temp.t44_ok(public.read_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1')->'result'=semantic AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'semantic replay does not invent consumption facts or rewards');
 END;
END $review_context_only$;
DO $empty_legacy_and_missing_literal$
DECLARE k text;s jsonb;x jsonb;u uuid;child uuid;refused boolean;
BEGIN
 FOREACH k IN ARRAY ARRAY['meal_photo','conversation_photo'] LOOP
  s:=pg_temp.t44_seed(k,CASE WHEN k='meal_photo' THEN 'Comi arroz 100 g' ELSE NULL END,NULL,CASE WHEN k='meal_photo' THEN '{"type":"meal","items":[]}'::jsonb ELSE '{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[]}}'::jsonb END);
  x:=pg_temp.t44_seal(s,'meal.report');u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;refused:=false;
  BEGIN PERFORM public.capture_conversation_meal_source(u,child);
  EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'conversation_meal_vision_missing' THEN RAISE;END IF;refused:=true;END;
  PERFORM pg_temp.t44_ok(refused AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'legacy empty visuals remain refused; ordinary empty visuals need a literal source '||k);
 END LOOP;
END $empty_legacy_and_missing_literal$;
DO $helper_privileges$
DECLARE role_name text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.t44_ok(NOT has_function_privilege(role_name,'private.conversation_photo_domain_allowed(text,jsonb,text)','EXECUTE') AND NOT has_function_privilege(role_name,'private.conversation_meal_media_analysis(text,jsonb)','EXECUTE'),'ordinary analysis helpers remain private to trusted SQL owners '||role_name);
 END LOOP;
END $helper_privileges$;
SELECT jsonb_build_object('schema','r102.ordinary-photo-lineage.v1','assertions',(SELECT count(*) FROM t44_assertions),'cases',(SELECT jsonb_agg(to_jsonb(x)) FROM t44_goldens x));
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

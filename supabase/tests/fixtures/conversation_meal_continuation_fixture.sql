-- Synthetic, transaction-owned helpers. No model/provider is contacted.
\ir conversation_meal_decision_fixture.sql
CREATE FUNCTION pg_temp.continuation_seed(u uuid,a uuid,c uuid,missing boolean DEFAULT true,new_owner boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE raw jsonb;source jsonb;claim jsonb;model jsonb;terminal jsonb;decision jsonb;
BEGIN
 IF new_owner THEN
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=a) THEN RAISE EXCEPTION 'continuation_fixture_collision';END IF;
  INSERT INTO auth.users(id) VALUES(a);
  INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed)
   VALUES(u,a,'continuation-'||u::text||'@example.invalid','active','UTC','BR',true);
 END IF;
 raw:=pg_temp.writer_input(c)-'meal_type';
 IF missing THEN raw:=jsonb_set(raw,'{source,text}','"Comi arroz"');END IF;
 PERFORM public.admit_conversation_meal_command(u,raw);source:=public.capture_conversation_meal_source(u,c);
 claim:=public.start_conversation_meal_semantic_attempt(u,c,'conversation.meal-interpreter.v1',source->>'source_hash');
 model:=pg_temp.semantic_result(claim);
 IF missing THEN
  model:=jsonb_set(model,'{foods}', '[{"index":0,"name":{"unit":"command_text","start":5,"end":10},"quantity":null,"unit":null,"visual_index":null}]');
  model:=jsonb_set(model,'{sources,0,spans}', '[{"start":0,"end":4,"kind":"report","food_index":null},{"start":4,"end":5,"kind":"separator","food_index":null},{"start":5,"end":10,"kind":"food","food_index":0}]');
 END IF;
 terminal:=public.commit_conversation_meal_semantic_result(u,c,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,model);
 IF terminal->>'status'<>'completed' THEN RAISE EXCEPTION 'continuation_fixture_not_completed';END IF;
 decision:=public.seal_conversation_meal_decision(u,c,(terminal->>'epoch')::uuid,terminal->>'input_hash',source->>'source_hash',
  (terminal->>'attempt_id')::uuid,terminal->>'result_hash',pg_temp.decision_payload(CASE WHEN missing THEN 'missing_quantity' ELSE 'meal_type_required' END,CASE WHEN missing THEN '[0]'::jsonb ELSE '[]'::jsonb END));
 IF decision->>'action'<>'sealed' THEN RAISE EXCEPTION 'continuation_fixture_not_sealed';END IF;
 RETURN jsonb_build_object('source',source,'terminal',terminal,'decision',decision->'decision','command',decision->'command');
END $$;
-- Historical synthetic server-clock fixture: no immutable rows are rewritten.
-- Uses the actual source_at clock seam and actual semantic shape/hash validator;
-- direct inserts model a previously committed attempt without waiting one day.
CREATE FUNCTION pg_temp.continuation_historical_seed(u uuid,a uuid,c uuid,observed timestamptz) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE raw jsonb:=pg_temp.writer_input(c)-'meal_type';epoch uuid:=gen_random_uuid();h text;context jsonb;source jsonb;claim jsonb;model jsonb;terminal jsonb;decision jsonb;
 attempt private.conversation_meal_semantic_attempts%ROWTYPE;result private.conversation_meal_semantic_results%ROWTYPE;
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=a) THEN RAISE EXCEPTION 'continuation_historical_collision';END IF;
 INSERT INTO auth.users(id) VALUES(a);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed) VALUES(u,a,'continuation-history-'||u::text||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,epoch,observed);
 PERFORM private.assert_conversation_meal_input(raw);h:=encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at) VALUES(u,c,h,'conversation.command.v1','meal.report',epoch,observed);
 INSERT INTO private.conversation_meal_command_sources VALUES(u,c,raw);
 context:=private.conversation_meal_source_at(u,c,observed);
 INSERT INTO private.conversation_meal_source_captures VALUES(u,c,encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex'),context,observed);
 SELECT jsonb_build_object('source_hash',s.source_hash,'captured_at',s.captured_at,'context',s.context) INTO source FROM private.conversation_meal_source_captures s WHERE user_id=u AND command_id=c;
 INSERT INTO private.conversation_meal_semantic_attempts VALUES(u,c,'conversation.meal-interpreter.v1',epoch,h,source->>'source_hash',gen_random_uuid(),observed) RETURNING * INTO attempt;
 claim:=private.conversation_semantic_state(attempt,NULL,'claimed');model:=pg_temp.semantic_result(claim);
 PERFORM private.assert_conversation_semantic_result(model,attempt,context);
 INSERT INTO private.conversation_meal_semantic_results VALUES(u,c,attempt.attempt_id,'completed',model,encode(sha256(convert_to(private.conversation_command_canonical(model),'UTF8')),'hex'),NULL,observed) RETURNING * INTO result;
 terminal:=private.conversation_semantic_state(attempt,result,'available');
 decision:=public.seal_conversation_meal_decision(u,c,epoch,h,source->>'source_hash',attempt.attempt_id,result.result_hash,pg_temp.decision_payload());
 IF decision->>'action'<>'sealed' THEN RAISE EXCEPTION 'continuation_historical_not_sealed';END IF;
 RETURN jsonb_build_object('source',source,'terminal',terminal,'decision',decision->'decision','command',decision->'command');
END $$;
CREATE FUNCTION pg_temp.continuation_media_seed(u uuid,a uuid,c uuid,asset uuid,kind text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE raw jsonb;source jsonb;claim jsonb;model jsonb;terminal jsonb;decision jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=a) OR EXISTS(SELECT 1 FROM public.media_assets WHERE id=asset) THEN RAISE EXCEPTION 'continuation_media_collision';END IF;
 IF kind NOT IN('audio_note','meal_photo') THEN RAISE EXCEPTION 'synthetic_media_kind';END IF;
 INSERT INTO auth.users(id) VALUES(a);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed) VALUES(u,a,'continuation-media-'||u::text||'@example.invalid','active','UTC','BR',true);
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,context_text,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(asset,u,kind,CASE kind WHEN 'audio_note' THEN 'audio-notes' ELSE 'meal-photos' END,u::text||'/'||asset::text||CASE kind WHEN 'audio_note' THEN '.m4a' ELSE '.jpg' END,
  CASE kind WHEN 'audio_note' THEN 'audio/mp4' ELSE 'image/jpeg' END,1200,1200,'processed',NULL,repeat('f',64),repeat('e',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),
  CASE kind WHEN 'audio_note' THEN '{"text":"Comi arroz"}'::jsonb ELSE '{"items":[{"name":"arroz","quantity_g_estimate":100,"confidence":1}]}'::jsonb END);
 raw:=jsonb_set(pg_temp.writer_input(c)-'meal_type','{source}',jsonb_build_object('channel','media','media_asset_id',asset,'user_action','register_consumed_meal'));
 PERFORM public.admit_conversation_meal_command(u,raw);source:=public.capture_conversation_meal_source(u,c);
 claim:=public.start_conversation_meal_semantic_attempt(u,c,'conversation.meal-interpreter.v1',source->>'source_hash');model:=pg_temp.semantic_result(claim);
 IF kind='audio_note' THEN
  model:=jsonb_set(model,'{source_units}','["media_transcript"]');
  model:=jsonb_set(model,'{sources}','[{"unit":"media_transcript","classification":"reported","visual_indexes":[],"spans":[{"start":0,"end":4,"kind":"report","food_index":null},{"start":4,"end":5,"kind":"separator","food_index":null},{"start":5,"end":10,"kind":"food","food_index":0}]}]');
  model:=jsonb_set(model,'{foods}','[{"index":0,"name":{"unit":"media_transcript","start":5,"end":10},"quantity":null,"unit":null,"visual_index":null}]');
 ELSE
  model:=model||'{"source_units":["vision_items"],"reason":"explicit_media_action","sources":[{"unit":"vision_items","classification":"visual","visual_indexes":[0],"spans":[]}],"foods":[{"index":0,"name":null,"quantity":null,"unit":null,"visual_index":0}]}'::jsonb;
 END IF;
 terminal:=public.commit_conversation_meal_semantic_result(u,c,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,model);
 decision:=public.seal_conversation_meal_decision(u,c,(terminal->>'epoch')::uuid,terminal->>'input_hash',source->>'source_hash',(terminal->>'attempt_id')::uuid,terminal->>'result_hash',
  pg_temp.decision_payload(CASE kind WHEN 'audio_note' THEN 'missing_quantity' ELSE 'meal_type_required' END,CASE kind WHEN 'audio_note' THEN '[0]'::jsonb ELSE '[]'::jsonb END));
 IF terminal->>'status'<>'completed' OR decision->>'action'<>'sealed' THEN RAISE EXCEPTION 'continuation_media_not_sealed';END IF;
 RETURN jsonb_build_object('source',source,'terminal',terminal,'decision',decision->'decision','command',decision->'command');
END $$;
CREATE FUNCTION pg_temp.continuation_read(u uuid,c uuid,seed jsonb,r uuid DEFAULT NULL,h text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.read_conversation_meal_continuation(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',r,h);
$$;
CREATE FUNCTION pg_temp.continuation_body(state jsonb,answer jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','conversation.meal-clarification.v1','expected_revision',state#>'{head,revision}','question_key',state#>'{head,question,question_key}','answer',answer);
$$;
CREATE FUNCTION pg_temp.continuation_admit(u uuid,c uuid,seed jsonb,r uuid,body jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.admit_conversation_meal_reply(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',seed#>>'{decision,decision_hash}',r,body);
$$;
CREATE FUNCTION pg_temp.continuation_prepare(u uuid,c uuid,seed jsonb,r uuid,h text,p jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.prepare_conversation_meal_continuation(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',r,h,p);
$$;
CREATE FUNCTION pg_temp.continuation_commit(u uuid,c uuid,seed jsonb,r uuid,h text,p text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.commit_conversation_meal_continuation(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',r,h,p);
$$;
CREATE FUNCTION pg_temp.continuation_materialized(parent jsonb,grams numeric DEFAULT 100) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE food jsonb:=parent#>'{semantic,result,foods,0}';name text;visual boolean:=parent#>'{semantic,result,foods,0,visual_index}'<>'null'::jsonb;
BEGIN
 name:=CASE WHEN parent#>>'{source,context,source_input,source,text}'='Comi arroz' THEN 'arroz' ELSE 'arroz sintetico' END;
 IF visual THEN name:=parent#>>'{source,context,media,processing_result,items,0,name}';END IF;
 RETURN jsonb_build_object('schema','conversation.meal-materialization.v1','status','materialized',
  'input_hash',parent#>'{binding,input_hash}','source_hash',parent#>'{source,source_hash}','attempt_id',parent#>'{semantic,attempt_id}',
  'inputs',jsonb_build_array(jsonb_build_object('input_index',0,'calculation_input',jsonb_build_object('food_name',name,'quantity_g',grams),
   'source_group_index',0,'candidate',jsonb_build_object('candidate_id','synthetic-candidate-0','name',name,'quantity_g',grams,'quantity_basis',CASE WHEN visual THEN 'visual_estimate' ELSE 'stated' END,
    'count',NULL,'unit_label',NULL,'confidence',CASE WHEN visual THEN 1 ELSE NULL END,'needs_review',visual,'review_reason',CASE WHEN visual THEN 'estimated_quantity' ELSE NULL END))),
  'source_groups',jsonb_build_array(jsonb_build_object('group_index',0,'interpretation_food_indexes','[0]'::jsonb,'input_indexes','[0]'::jsonb,'rule',CASE WHEN visual THEN 'visual' ELSE 'literal' END,
   'source_positions',jsonb_build_array(jsonb_build_object('food_index',0,'unit',CASE WHEN visual THEN 'vision_items' ELSE food#>>'{name,unit}' END,'name',food->'name','quantity',food->'quantity','unit_ref',food->'unit','visual_index',food->'visual_index')))),
  'nutrition_label',NULL);
END $$;
CREATE FUNCTION pg_temp.continuation_preparation(state jsonb,ready boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE reply jsonb:=state->'reply';parent jsonb:=state->'parent';source jsonb:=state#>'{reply,source,context}';m jsonb;w jsonb:='[]';link jsonb;v jsonb;meal jsonb;
BEGIN
 m:=pg_temp.continuation_materialized(parent);
 FOR link IN SELECT value FROM jsonb_array_elements(source->'answer_chain') WHERE value#>>'{answer,kind}'='quantity' LOOP
  w:=w||jsonb_build_array(jsonb_build_object('reply_id',link->'reply_id','food_index',link#>'{answer,food_index}','amount',link#>'{answer,amount}',
   'unit',link#>'{answer,unit}','quantity_g',100,'quantity_basis','stated','quantity_display',NULL,'input_indexes','[0]'::jsonb));
 END LOOP;
 v:=jsonb_build_object('schema','conversation.meal-continuation-preparation.v1','status',CASE WHEN ready THEN 'ready' ELSE 'needs_reply' END,
  'input_hash',reply#>'{binding,input_hash}','source_hash',reply#>'{source,source_hash}','parent_ref',source->'parent',
  'answer_chain_hash',source->'answer_chain_hash','quantity_witnesses',w,'materialization',m);
 IF NOT ready THEN RETURN v||jsonb_build_object('next_need',jsonb_build_object('kind','meal_type','food_index',NULL));END IF;
 meal:=pg_temp.writer_resolved(parent->'source')-ARRAY['schema','input_hash','source_hash','semantic_proof'];
 meal:=jsonb_set(meal,'{items,0,name}',m#>'{inputs,0,calculation_input,food_name}');
 meal:=jsonb_set(meal,'{items,0,quantity_basis}',m#>'{inputs,0,candidate,quantity_basis}');
 RETURN v||jsonb_build_object('meal',meal);
END $$;

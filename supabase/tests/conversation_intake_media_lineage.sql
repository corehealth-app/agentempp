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
DO $core$
DECLARE s jsonb;x jsonb;r jsonb;p jsonb;q jsonb;u uuid;e uuid;child uuid;raw jsonb;denied boolean;k text;
BEGIN
 s:=pg_temp.t44_seed('audio_note','Fiz 30 minutos de caminhada leve','Fiz 30 minutos de caminhada leve','{"text":"Fiz 30 minutos de caminhada leve"}');
 x:=pg_temp.t44_seal(s,'workout.report');
 PERFORM pg_temp.t44_ok(x->>'action'='sealed' AND x#>>'{selection,schema}'='conversation.intake-selection.v2','processed media seals genuine versioned typed child');
 u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;raw:=x#>'{selection,command,input}';
 PERFORM pg_temp.t44_ok(raw->'source'=s#>'{raw,source}' AND raw#>>'{source,user_action}'='report_actual_record','original caption and neutral user action remain literal');
 PERFORM pg_temp.t44_ok(raw#>>'{intake_origin,intake_id}'=s#>>'{intake,intake_id}' AND raw#>>'{intake_origin,claim_id}'=s#>>'{claim,claim_id}' AND raw#>>'{intake_origin,source_hash}'=s#>>'{source,source_hash}' AND (SELECT source_input=raw FROM private.conversation_workout_inputs WHERE user_id=u AND command_id=child),'real reserved child stores exact parent source claim and result origin');
 PERFORM pg_temp.t44_ok(pg_temp.t44_seal(s,'workout.report')=jsonb_set(x,'{action}','"replay"'),'same parent replays identical selected child');
 PERFORM pg_temp.t44_ok(public.admit_conversation_workout_command(u,e,raw)=jsonb_build_object('action','replay','command',(x#>'{selection,command}')-ARRAY['kind','input']),'typed resume replays only actually selected internal child');
 denied:=false;BEGIN PERFORM public.admit_conversation_workout_command(u,e,jsonb_set(raw,'{command_id}',to_jsonb(gen_random_uuid())));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.t44_ok(denied,'public legacy admission cannot mint an unselected neutral child');
 r:=public.capture_conversation_workout_source(u,child,x#>>'{selection,command,input_hash}',e);
 PERFORM pg_temp.t44_ok(r#>>'{context,schema}'='conversation.workout-source.v2' AND r#>'{context,intake_projection}'=x#>'{selection,media_projection}','typed source persists original genuine projection');
 p:=public.prepare_conversation_workout(u,child,x#>>'{selection,command,input_hash}',r->>'source_hash',e,private.conversation_workout_report(r->'context',r->>'source_hash'));
 PERFORM pg_temp.t44_ok(p#>>'{prepared,status}'='ready' AND p#>'{prepared,evidence}' @> '[{"unit":"media_context"}]','SQL performed authority independently sees separate caption context and transcript');
 q:=public.commit_conversation_workout(u,child,x#>>'{selection,command,input_hash}',r->>'source_hash',e,p->>'prepared_hash',p->'prepared');
 PERFORM pg_temp.t44_ok(q->>'action'='committed' AND (SELECT count(*)=1 FROM public.workout_logs WHERE user_id=u),'genuine neutral media source reaches existing atomic writer');
 PERFORM pg_temp.t44_ok(public.commit_conversation_workout(u,child,x#>>'{selection,command,input_hash}',r->>'source_hash',e,p->>'prepared_hash',p->'prepared')=jsonb_set(q,'{action}','"replay"'),'commit resume cannot duplicate existing workout or receipt');
 INSERT INTO t44_goldens VALUES('audio_workout',x,r,p,q);
END $core$;
-- Existing writer's synthetic resolved fixture is exercised against the genuine
-- newly captured source; no external model/provider is called by this SQL suite.
\ir fixtures/conversation_meal_atomic_writer_fixture.sql
DO $meal$
DECLARE s jsonb;x jsonb;r jsonb;p jsonb;q jsonb;u uuid;e uuid;child uuid;raw jsonb;changed boolean;
BEGIN
 s:=pg_temp.t44_seed('meal_photo','Comi arroz','Contexto original separado','{"items":[{"name":"arroz","quantity_g":100}]}');x:=pg_temp.t44_seal(s,'meal.report');
 PERFORM pg_temp.t44_ok(x->>'action'='sealed' AND x#>>'{selection,schema}'='conversation.intake-selection.v2','processed meal photo seals only real meal child');
 u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;raw:=x#>'{selection,command,input}';
 r:=public.capture_conversation_meal_source(u,child);
 PERFORM pg_temp.t44_ok(r#>>'{context,schema}'='conversation.meal-source.v2' AND r#>'{context,intake_projection}'=x#>'{selection,media_projection}' AND r#>>'{context,source_evidence,caption}'='Comi arroz' AND r#>>'{context,source_evidence,context_text}'='Contexto original separado' AND r#>'{context,source_evidence,transcript}'='null' AND r#>'{context,source_units}'='["media_caption","media_context","vision_items"]','meal source separates caption context and vision without replacement');
 PERFORM pg_temp.t44_ok(public.admit_conversation_meal_command_fenced(u,raw,e)=jsonb_build_object('action','replay','command',(x#>'{selection,command}')-ARRAY['kind','input']),'meal typed resume replays exact selected neutral input');
 PERFORM pg_temp.t44_ok(private.conversation_continuation_original_current(u,jsonb_build_object('source',r)),'linked clarification accepts actual v2 original source without coalescing');
 p:=public.prepare_conversation_meal(u,child,pg_temp.writer_resolved(r));q:=public.commit_conversation_meal(u,child,p->>'resolved_hash');
 PERFORM pg_temp.t44_ok(p->>'action'='prepared' AND q->>'action'='committed' AND (SELECT count(*)=1 FROM public.meal_logs WHERE user_id=u),'neutral media reaches existing meal atomic preparation and writer');
 PERFORM pg_temp.t44_ok(public.commit_conversation_meal(u,child,NULL)=jsonb_set(q,'{action}','"replay"'),'cold meal receipt replay does not reinterpret or duplicate');
 INSERT INTO t44_goldens VALUES('meal_photo',x,r,p,q);
 UPDATE public.media_assets SET processing_result=processing_result||'{"drift":true}' WHERE id=(raw#>>'{source,media_asset_id}')::uuid;
 changed:=false;BEGIN PERFORM private.conversation_meal_source_at(u,child,NULL);EXCEPTION WHEN serialization_failure THEN changed:=true;END;
 PERFORM pg_temp.t44_ok(changed AND public.commit_conversation_meal(u,child,NULL)=jsonb_set(q,'{action}','"replay"'),'changed processing cannot be new authority while old receipt remains exact');
END $meal$;
DO $independent_sources$
DECLARE s jsonb;x jsonb;r jsonb;p jsonb;u uuid;e uuid;child uuid;kind text;
BEGIN
 FOREACH kind IN ARRAY ARRAY['audio_note','gym_photo'] LOOP
  s:=pg_temp.t44_seed(kind,CASE WHEN kind='audio_note' THEN 'Fiz 30 minutos de caminhada leve' END,CASE WHEN kind='audio_note' THEN 'Não fiz caminhada' END,CASE WHEN kind='audio_note' THEN '{"text":"Fiz 30 minutos de caminhada leve"}'::jsonb ELSE '{"equipment":[{"name":"esteira"}]}'::jsonb END);
  x:=pg_temp.t44_seal(s,'workout.report');u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;
  r:=public.capture_conversation_workout_source(u,child,x#>>'{selection,command,input_hash}',e);p:=private.conversation_workout_report(r->'context',r->>'source_hash');
  PERFORM pg_temp.t44_ok(p->>'status'=CASE WHEN kind='audio_note' THEN 'not_reported' ELSE 'needs_reply' END,'conflicting original context or equipment pixels never prove performed exercise '||kind);
  PERFORM pg_temp.t44_ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'no performed effect from conflicting or pixel-only evidence '||kind);
  INSERT INTO t44_goldens VALUES(kind||'_not_performed',x,r,p,NULL);
 END LOOP;
END $independent_sources$;
DO $semantic_context$
DECLARE s jsonb;x jsonb;r jsonb;a jsonb;v jsonb;q jsonb;u uuid;e uuid;child uuid;units jsonb:='[]';unit text;
BEGIN
 s:=pg_temp.t44_seed('audio_note',NULL,'arroz 100 g','{"text":"arroz 100 g"}');x:=pg_temp.t44_seal(s,'meal.report');
 u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;r:=public.capture_conversation_meal_source(u,child);
 a:=public.start_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1',r->>'source_hash');
 FOREACH unit IN ARRAY ARRAY['media_context','media_transcript'] LOOP
  units:=units||jsonb_build_array(jsonb_build_object('unit',unit,'classification','nominal_list','visual_indexes','[]'::jsonb,'spans','[{"start":0,"end":5,"kind":"food","food_index":0},{"start":5,"end":6,"kind":"separator","food_index":null},{"start":6,"end":9,"kind":"quantity","food_index":0},{"start":9,"end":10,"kind":"separator","food_index":null},{"start":10,"end":11,"kind":"unit","food_index":0}]'::jsonb));
 END LOOP;
 v:=jsonb_build_object('schema','conversation.meal-interpretation.v1','interpreter_version','conversation.meal-interpreter.v1','owner_id',u,'command_id',child,'attempt_id',a->'attempt_id','input_hash',r#>'{context,input_hash}','source_hash',r->'source_hash','source_units',r#>'{context,source_units}','decision','reported_meal','reason','nominal_food_list','sources',units,
 'foods','[{"index":0,"name":{"unit":"media_context","start":0,"end":5},"quantity":{"unit":"media_context","start":6,"end":9},"unit":{"unit":"media_context","start":10,"end":11},"visual_index":null}]'::jsonb,'provider_metadata','{"model":"synthetic/no-provider","prompt_tokens":0,"completion_tokens":0,"cost_usd":0,"latency_ms":0}'::jsonb);
 q:=public.commit_conversation_meal_semantic_result(u,child,'conversation.meal-interpreter.v1',(a->>'attempt_id')::uuid,v);
 PERFORM pg_temp.t44_ok(q->>'status'='completed' AND q->'result'=v,'actual semantic receipt preserves complete context and transcript units with real food references');
 PERFORM pg_temp.t44_ok(public.read_conversation_meal_semantic_attempt(u,child,'conversation.meal-interpreter.v1')->'result'=v AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'cold semantic read does not interpret again or record a meal');
END $semantic_context$;
DO $fences$
DECLARE s jsonb;x jsonb;u uuid;e uuid;raw jsonb;child uuid;kind text;denied boolean;j integer;t jsonb;
BEGIN
 s:=pg_temp.t44_seed('meal_photo',NULL,NULL,'{"items":[{"name":"arroz"}]}');u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;
 x:=pg_temp.t44_seal(s,'workout.report');
 PERFORM pg_temp.t44_ok(x='{"action":"media_projection_required"}' AND (SELECT count(*)=1 FROM private.conversation_intake_routing_results WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u),'routing cannot reinterpret meal photo as performed workout');
 -- Independent seeds keep previous immutable decisions intact.
 s:=pg_temp.t44_seed('audio_note',NULL,NULL,'{"text":"Comi arroz"}');u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;
 FOR j IN 1..10 LOOP t:=public.admit_conversation_meal_command_fenced(u,jsonb_build_object('command_protocol','conversation.command.v1','command_id',gen_random_uuid(),'kind','meal.report','source',jsonb_build_object('channel','text','text','Registro sintético')),e);END LOOP;
 PERFORM pg_temp.t44_ok(pg_temp.t44_seal(s,'meal.report')='{"action":"rate_limited"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u) AND (SELECT count(*)=10 FROM private.conversation_meal_command_ids WHERE user_id=u),'media uses original shared typed quota and rolls child selection back together');
 PERFORM pg_temp.t44_ok((SELECT count(*)=1 FROM private.conversation_intake_routing_results WHERE user_id=u),'quota refusal retains original T41 routing result');
 s:=pg_temp.t44_seed('audio_note',NULL,NULL,'{"text":"Comi arroz"}');u:=(s#>>'{intake,owner_id}')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
 PERFORM pg_temp.t44_ok(pg_temp.t44_seal(s,'meal.report')='{"action":"day_closed"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'closed day refuses media child before any identity');
 s:=pg_temp.t44_seed('audio_note',NULL,NULL,'{"text":"Comi arroz"}');u:=(s#>>'{intake,owner_id}')::uuid;
 UPDATE public.media_assets SET context_text='Comi outro alimento' WHERE id=(s#>>'{raw,source,media_asset_id}')::uuid;
 PERFORM pg_temp.t44_ok(pg_temp.t44_seal(s,'meal.report')='{"action":"source_conflict"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'media context mutation cannot be silently adopted before seal');
 s:=pg_temp.t44_seed('audio_note',NULL,NULL,'{"text":"Comi arroz"}');u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;x:=pg_temp.t44_seal(s,'meal.report');raw:=x#>'{selection,command,input}';
 FOREACH kind IN ARRAY ARRAY['input_hash','source_hash','claim_id','decision_hash','epoch','intake_id'] LOOP
  denied:=false;BEGIN PERFORM public.admit_conversation_meal_command_fenced(u,jsonb_set(raw,ARRAY['intake_origin',kind],to_jsonb(CASE WHEN kind LIKE '%hash' THEN repeat('0',64) ELSE gen_random_uuid()::text END)),e);EXCEPTION WHEN invalid_parameter_value OR no_data_found THEN denied:=true;END;
  PERFORM pg_temp.t44_ok(denied,'cannot forge real lineage reference '||kind);
 END LOOP;
 FOREACH kind IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.t44_ok(NOT has_function_privilege(kind,'private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)','EXECUTE') AND NOT has_function_privilege(kind,'private.admit_conversation_intake_media_child(uuid,uuid,jsonb)','EXECUTE'),'projection and initial child mint remain private '||kind);
 END LOOP;
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.t44_ok(public.admit_conversation_meal_command_fenced(u,raw,e)='{"action":"stale_epoch"}','typed media retry after reset cannot reconstitute deleted lineage');
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 PERFORM pg_temp.t44_ok(public.admit_conversation_meal_command_fenced(u,raw,e)='{"action":"stale_epoch"}','new epoch cannot revive old media child tombstone');
 PERFORM pg_temp.t44_ok(public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid)='{"action":"stale_epoch"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_sources WHERE user_id=u),'epoch reset removes raw lineage and media child payload but preserves tombstones');
END $fences$;
SELECT jsonb_build_object('schema','t44.actual-media-lineage.v1','assertions',(SELECT count(*) FROM t44_assertions),'cases',(SELECT jsonb_agg(to_jsonb(x)) FROM t44_goldens x))::text;
ROLLBACK;

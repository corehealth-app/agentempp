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


DO $journal_ordinary$
DECLARE k text;s jsonb;x jsonb;r jsonb;p jsonb;input jsonb;u uuid;e uuid;child uuid;asset uuid;hash_before text;
BEGIN
 FOREACH k IN ARRAY ARRAY['meal.report','workout.report'] LOOP
  s:=pg_temp.t44_seed('conversation_photo',NULL,CASE WHEN k='meal.report' THEN 'Acabei de almoçar esse prato.' ELSE 'Fiz atividade nesta academia' END,
   CASE WHEN k='meal.report' THEN '{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[{"name":"feijão preto cozido","quantity_g_estimate":150,"confidence":0.9},{"name":"farofa","quantity_g_estimate":80,"confidence":0.85}]}}'::jsonb
   ELSE '{"schema":"conversation.image-result.v1","status":"ready","classification":"equipment","analysis":{"type":"equipment","equipment":["esteira"],"location":"academia_completa","confidence":0.9}}'::jsonb END);
  x:=pg_temp.t44_seal(s,k);PERFORM pg_temp.t44_ok(x->>'action'='sealed','actual ordinary source seals genuine child '||k);
  u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;input:=x#>'{selection,command,input}';asset:=(input#>>'{source,media_asset_id}')::uuid;
  PERFORM pg_temp.t44_ok(private.conversation_journal_media_input_v3(u,input),'original ordinary photo passes read-only projection '||k);
  p:=public.read_conversation_journal_page_v3(u,e,25,NULL);
  PERFORM pg_temp.t44_ok(p->>'action'='available' AND jsonb_array_length(p->'items')=1,'whole journal page remains available '||k);
  PERFORM pg_temp.t44_ok(p#>'{intakes,0,source_input}'=s->'raw','literal original source preserved '||k);
  PERFORM pg_temp.t44_ok(NOT private.conversation_journal_media_input_v3(gen_random_uuid(),input),'foreign owner cannot read ordinary projection '||k);
  PERFORM pg_temp.t44_ok(NOT private.conversation_journal_media_input_v3(u,jsonb_set(input,'{source,media_asset_id}',to_jsonb(gen_random_uuid()))),'changed asset cannot read ordinary projection '||k);
  SELECT encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') INTO hash_before FROM private.conversation_intake_selections t WHERE user_id=u;
  UPDATE public.media_assets SET status='deleted',deleted_at=clock_timestamp(),processing_result=NULL WHERE id=asset;
  p:=public.read_conversation_journal_page_v3(u,e,25,NULL);
  PERFORM pg_temp.t44_ok(p->>'action'='available' AND p#>'{intakes,0,source_input}'=s->'raw','payload disposal cannot invalidate immutable original '||k);
  PERFORM pg_temp.t44_ok((SELECT hash_before=encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') FROM private.conversation_intake_selections t WHERE user_id=u),'observational replay does not rewrite selection '||k);
  PERFORM pg_temp.t44_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'reading pixels never creates consumption activity or reward '||k);
 END LOOP;
END $journal_ordinary$;
SELECT jsonb_build_object('pass',count(*),'labels',jsonb_agg(label)) FROM t44_assertions;
ROLLBACK;

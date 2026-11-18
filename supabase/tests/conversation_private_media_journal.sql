-- Local, synthetic, transactional qualification. No provider or Storage calls.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
CREATE TEMP TABLE journal_private_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.journal_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_JOURNAL_FAIL:%',label;END IF;
 INSERT INTO journal_private_checks VALUES(label);
END $$;
\ir fixtures/conversation_private_media_capture_fixture.sql
-- The fallback exposes the actual pre-migration regression, rather than failing
-- merely because the additive helper has not been installed yet.
CREATE FUNCTION pg_temp.journal_valid(u uuid,input jsonb) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE valid boolean;
BEGIN
 IF to_regprocedure('private.conversation_journal_versioned_media_input_v3(uuid,jsonb)') IS NULL THEN
  RETURN private.conversation_journal_media_input_v3(u,input);
 END IF;
 EXECUTE 'SELECT private.conversation_journal_versioned_media_input_v3($1,$2)' INTO valid USING u,input;
 RETURN valid;
END $$;
-- Corruption is confined to a rolled-back nested transaction on an owned local
-- copy. Production immutability triggers remain enabled and unchanged.
CREATE FUNCTION pg_temp.journal_corrupt(sql text,u uuid,input jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE refused boolean;
BEGIN
 BEGIN
  ALTER TABLE private.conversation_intake_sources DISABLE TRIGGER USER;
  ALTER TABLE private.conversation_intake_selections DISABLE TRIGGER USER;
  ALTER TABLE private.conversation_private_media_intakes_v2 DISABLE TRIGGER USER;
  EXECUTE sql;
  refused:=NOT pg_temp.journal_valid(u,input);
  RAISE EXCEPTION 'rollback local corruption' USING ERRCODE='P0185';
 EXCEPTION WHEN SQLSTATE 'P0185' THEN NULL;
 END;
 PERFORM pg_temp.journal_ok(refused,label);
END $$;
DO $private_cases$
DECLARE s jsonb;q jsonb;input jsonb;u uuid;e uuid;i uuid;a uuid;kind text;domain text;result jsonb;p jsonb;original jsonb;mutation text;
BEGIN
 FOREACH kind IN ARRAY ARRAY['conversation_photo','audio_note'] LOOP
  FOREACH domain IN ARRAY ARRAY['meal.report','workout.report'] LOOP
   result:=CASE WHEN kind='audio_note' THEN '{"text":"Comi arroz 100 g e caminhei por 12 minutos"}'::jsonb
    WHEN domain='meal.report' THEN '{"schema":"conversation.image-result.v1","status":"ready","classification":"meal","analysis":{"type":"meal","items":[{"name":"arroz","quantity_g_estimate":100,"confidence":0.9}]}}'::jsonb
    ELSE '{"schema":"conversation.image-result.v1","status":"ready","classification":"equipment","analysis":{"type":"equipment","equipment":["esteira"],"location":"academia_completa","confidence":0.9}}'::jsonb END;
   s:=pg_temp.private_seed(kind,NULL,result);u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;i:=(s->>'intake')::uuid;a:=(s->>'asset')::uuid;
   q:=pg_temp.private_select(s,domain);input:=q#>'{sealed,selection,command,input}';original:=q#>'{sealed,selection}';
   PERFORM pg_temp.journal_ok(q#>>'{sealed,action}'='sealed','genuine private selection '||kind||domain);
   PERFORM pg_temp.journal_ok(pg_temp.journal_valid(u,input),'versioned historical input '||kind||domain);
   PERFORM pg_temp.journal_ok(NOT private.conversation_journal_media_input_v3(u,input),'legacy observer remains strict '||kind||domain);
   p:=public.read_conversation_journal_page_v3(u,e,10,NULL);
   PERFORM pg_temp.journal_ok(p->>'action'='available' AND jsonb_array_length(p->'items')=1,'default journal includes private intake '||kind||domain);
   PERFORM pg_temp.journal_ok(NOT pg_temp.journal_valid(gen_random_uuid(),input),'foreign owner refused '||kind||domain);
   PERFORM pg_temp.journal_ok(NOT pg_temp.journal_valid(u,jsonb_set(input,'{source,media_asset_id}',to_jsonb(gen_random_uuid()))),'changed asset refused '||kind||domain);
   PERFORM pg_temp.journal_ok(NOT pg_temp.journal_valid(u,input||'{"unexpected":true}'),'extra child field refused '||kind||domain);
   UPDATE private.conversation_media_assets_v2 SET status='deleted',deleted_at=clock_timestamp(),updated_at=clock_timestamp(),processing_result=NULL,processed_at=NULL WHERE id=a;
   UPDATE private.conversation_media_obligations_v2 SET closed_at=clock_timestamp() WHERE asset_id=a;
   PERFORM pg_temp.journal_ok(pg_temp.journal_valid(u,input),'disposed content preserves historical evidence '||kind||domain);
   PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,e,10,NULL)->>'action'='available','disposed content preserves complete page '||kind||domain);
   PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,gen_random_uuid(),10,NULL)->>'action'='stale_epoch','stale epoch refused '||kind||domain);
   PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,e,10,'{"at":"bad","id":"bad"}')->>'action'='cursor_conflict','invalid cursor refused '||kind||domain);
   PERFORM pg_temp.journal_ok((SELECT selection=original FROM private.conversation_intake_selections WHERE user_id=u AND intake_id=i),'historical reads preserve original receipt '||kind||domain);
   PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'history creates no facts '||kind||domain);

   PERFORM pg_temp.journal_corrupt(format('DELETE FROM private.conversation_private_media_intakes_v2 WHERE user_id=%L AND intake_id=%L',u,i),u,input,'missing private namespace binding '||kind||domain);
   PERFORM pg_temp.journal_corrupt(format('UPDATE private.conversation_private_media_intakes_v2 SET asset_id=%L WHERE user_id=%L AND intake_id=%L',gen_random_uuid(),u,i),u,input,'changed private namespace binding '||kind||domain);
   FOREACH mutation IN ARRAY ARRAY[
    'context #- ''{media,catalog_version}''',
    'jsonb_set(context,''{media,catalog_version}'',''3'')',
    'jsonb_set(context,''{media,catalog_version}'',''"2"'')',
    'jsonb_set(context,''{media,owner_id}'',to_jsonb(gen_random_uuid()))',
    'jsonb_set(context,''{media,asset_id}'',to_jsonb(gen_random_uuid()))',
    'jsonb_set(context,''{media,processing_result}'',''{"text":"forged"}'')'
   ] LOOP
    PERFORM pg_temp.journal_corrupt(format('UPDATE private.conversation_intake_sources SET context=%s,source_hash=encode(sha256(convert_to(private.conversation_command_canonical(%s),''UTF8'')),''hex'') WHERE user_id=%L AND intake_id=%L',mutation,mutation,u,i),u,input,'captured source refuses '||mutation||kind||domain);
   END LOOP;
   FOREACH mutation IN ARRAY ARRAY[
    'selection #- ''{media_projection,media,catalog_version}''',
    'jsonb_set(selection,''{media_projection,media,catalog_version}'',''1'')',
    'jsonb_set(selection,''{media_projection,media,processing_hash}'',to_jsonb(repeat(''0'',64)))',
    'jsonb_set(selection,''{command,input_hash}'',to_jsonb(repeat(''0'',64)))'
   ] LOOP
    PERFORM pg_temp.journal_corrupt(format('UPDATE private.conversation_intake_selections SET selection=%s WHERE user_id=%L AND intake_id=%L',mutation,u,i),u,input,'selected evidence refuses '||mutation||kind||domain);
   END LOOP;
  END LOOP;
 END LOOP;
END $private_cases$;
-- Catalog1 stays literal. A colliding private asset must never retag its intake.
DO $legacy_cases$
DECLARE s jsonb;raw jsonb;admitted jsonb;captured jsonb;claim jsonb;sealed jsonb;input jsonb;u uuid;e uuid;a uuid:=gen_random_uuid();i uuid:=gen_random_uuid();
BEGIN
 s:=pg_temp.private_seed('audio_note',NULL,'{"text":"independent private source"}');u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(a,u,'audio_note','audio-notes',u||'/'||a||'.m4a','audio/mp4',8,8,'processed',repeat('a',64),repeat('b',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),'{"text":"Comi pão 50 g"}');
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_build_object('channel','media','media_asset_id',a,'user_action','report_actual_record'));
 admitted:=public.admit_conversation_intake(u,e,raw);captured:=public.capture_conversation_intake_source(u,i,admitted#>>'{intake,input_hash}',e);
 claim:=public.claim_conversation_intake_routing(u,i,admitted#>>'{intake,input_hash}',e,captured->>'source_hash');
 sealed:=public.seal_conversation_intake_routing(u,i,admitted#>>'{intake,input_hash}',e,captured->>'source_hash',(claim->>'claim_id')::uuid,'{"schema":"conversation.intake-routing.v1","kind":"meal.report","reason":"processed_media_report"}');input:=sealed#>'{selection,command,input}';
 PERFORM pg_temp.journal_ok(private.conversation_journal_media_input_v3(u,input) AND pg_temp.journal_valid(u,input),'genuine legacy read remains exact');
 DELETE FROM public.media_assets WHERE id=a;
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('c',64));
 PERFORM pg_temp.journal_ok(pg_temp.journal_valid(u,input),'private UUID reuse cannot retag legacy history');
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,e,10,NULL)->>'action'='available','legacy disposed history remains available');
 PERFORM pg_temp.journal_corrupt(format('INSERT INTO private.conversation_private_media_intakes_v2(user_id,intake_id,asset_id) VALUES(%L,%L,%L)',u,i,a),u,input,'forged private admission cannot promote legacy evidence');
END $legacy_cases$;
DO $authority$
DECLARE sig text;body text;role text;
BEGIN
 PERFORM pg_temp.journal_ok((SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex')='a7a401e2b6d12269ada36a6c5c8531b67a9227217cde6a143b6f85a305a215f0' FROM pg_proc WHERE oid='private.conversation_journal_media_input_v3(uuid,jsonb)'::regprocedure),'legacy observer byte preservation');
 FOREACH sig IN ARRAY ARRAY['private.conversation_journal_private_media_input_v2(uuid,jsonb)','private.conversation_journal_versioned_media_input_v3(uuid,jsonb)'] LOOP
  SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid=to_regprocedure(sig);
  PERFORM pg_temp.journal_ok((SELECT provolatile='s' AND NOT prosecdef AND 'search_path=pg_catalog'=ANY(proconfig) FROM pg_proc WHERE oid=to_regprocedure(sig)),'stable invoker qualified helper '||sig);
  FOREACH role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.journal_ok(NOT has_function_privilege(role,sig,'EXECUTE'),'private helper unavailable to '||role||sig);
  END LOOP;
  PERFORM pg_temp.journal_ok(body !~* '(public[.]media_assets|private[.]conversation_media_assets_v2|read_conversation_media_record_v2|intake_media_projection[(]|FOR (UPDATE|SHARE)|INSERT |UPDATE |DELETE |net[.]|vault[.])','history has no content catalog or side effects '||sig);
 END LOOP;
 PERFORM pg_temp.journal_ok((SELECT encode(sha256(convert_to(replace(prosrc,'private.conversation_journal_versioned_media_input_v3(','private.conversation_journal_media_input_v3('),'UTF8')),'hex')='db6f6fe158a53ff3eee8afd65342e0e4bebbd7eac371066d6c3c747b0e3d2850' FROM pg_proc WHERE oid='private.conversation_journal_parent_v3(uuid,uuid,uuid)'::regprocedure),'parent exact single observational substitution');
 PERFORM pg_temp.journal_ok((SELECT encode(sha256(convert_to(replace(prosrc,'private.conversation_journal_versioned_media_input_v3(','private.conversation_journal_media_input_v3('),'UTF8')),'hex')='ed651eb30c65f668425ad01e463aabe50809962851874989b52ae359fe523392' FROM pg_proc WHERE oid='public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)'::regprocedure),'page exact single observational substitution');
END $authority$;
SELECT jsonb_build_object('passed',count(*),'labels',jsonb_agg(label ORDER BY label)) FROM journal_private_checks;
ROLLBACK;

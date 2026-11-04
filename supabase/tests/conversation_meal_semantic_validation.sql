BEGIN;
\ir fixtures/conversation_meal_semantic_fixture.sql
DO $media_order$
DECLARE a uuid:='c3a30000-0000-4000-8000-000000000001';cmd uuid:='c3a30000-0000-4000-8000-000000000002';asset uuid:='c3a30000-0000-4000-8000-000000000003';input jsonb;src jsonb;claim jsonb;v jsonb;x jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-media-order@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,context_text,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(asset,a,'meal_photo','meal-photos',a::text||'/'||asset::text||'.jpg','image/jpeg',1200,1200,'processed','Meu almoco',repeat('f',64),repeat('e',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),'{"items":[{"name":"arroz"},{"name":"feijao"}]}');
 input:=jsonb_set(pg_temp.writer_input(cmd),'{source}',jsonb_build_object('channel','media','media_asset_id',asset,'user_action','register_consumed_meal'));
 PERFORM public.admit_conversation_meal_command(a,input);src:=public.capture_conversation_meal_source(a,cmd);
 claim:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',src->>'source_hash');
 v:=pg_temp.semantic_result(claim);v:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(v,'{source_units}','["media_caption","vision_items"]'),'{foods}','[]'),'{decision}','"clarification_required"'),'{reason}','"ambiguous"'),'{sources}',
 '[{"unit":"media_caption","classification":"media_pointer","spans":[{"start":0,"end":10,"kind":"other","food_index":null}],"visual_indexes":[]},{"unit":"vision_items","classification":"visual","spans":[],"visual_indexes":[0,1]}]');
 PERFORM pg_temp.semantic_reject(a,cmd,claim,jsonb_set(v,'{sources}',jsonb_build_array(v#>'{sources,1}',v#>'{sources,0}')),'reject reordered multimodal sources before durable terminal');
 PERFORM pg_temp.semantic_reject(a,cmd,claim,jsonb_set(v,'{sources,1,visual_indexes}','[1,0]'),'reject reordered visual source indexes');
 PERFORM pg_temp.semantic_reject(a,cmd,claim,jsonb_set(v,'{sources,1,classification}','"reported"'),'visual source has its actual structural role');
 x:=public.commit_conversation_meal_semantic_result(a,cmd,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,v);
 PERFORM pg_temp.writer_ok(x->>'action'='committed' AND x->'result'=v,'ordered complete multimodal result can be read and replayed');
END $media_order$;
DO $invalid$
DECLARE a uuid:='c3a30000-0000-4000-8000-000000000010';cmd uuid:='c3a30000-0000-4000-8000-000000000011';src jsonb;claim jsonb;v jsonb;bad jsonb;label text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-invalid@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);src:=pg_temp.writer_seed(a,cmd);claim:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',src->>'source_hash');v:=pg_temp.semantic_result(claim);
 FOR bad,label IN SELECT * FROM (VALUES
 ('null'::jsonb,'reject null envelope'),('[]'::jsonb,'reject array envelope'),(v||'{"nutrition":{"kcal":130}}','no invented nutrition authority'),
 (jsonb_set(v,'{owner_id}',to_jsonb(cmd)),'wrong result owner'),(jsonb_set(v,'{command_id}',to_jsonb(a)),'wrong result command'),(jsonb_set(v,'{attempt_id}',to_jsonb(a)),'wrong result minted attempt'),
 (jsonb_set(v,'{input_hash}',to_jsonb(repeat('a',64))),'wrong input hash'),(jsonb_set(v,'{source_hash}',to_jsonb(repeat('a',64))),'wrong captured source hash'),
 (jsonb_set(v,'{interpreter_version}','"caller-picked-version"'),'wrong pinned interpreter'),(jsonb_set(v,'{source_units}','["command_text","command_text"]'),'duplicate source units'),
 (jsonb_set(v,'{sources,0,spans,0,end}','3'),'source partition gap'),(jsonb_set(v,'{sources,0,spans,1,start}','3'),'source partition overlap'),
 (jsonb_set(v,'{sources,0,spans,5,end}','27'),'source suffix omitted'),(jsonb_set(v,'{foods,0,name,end}','27'),'food reference exact occurrence required'),
 (jsonb_set(v,'{foods,0,quantity,start}','8'),'quantity reference exact role required'),(jsonb_set(v,'{foods,0,index}','1'),'dense food index required'),
 (jsonb_set(v,'{foods,0,visual_index}','0'),'no visual index without captured vision'),(jsonb_set(v,'{provider_metadata,cost_usd}','-0.1'),'nonnegative provider cost'),
 (jsonb_set(v,'{provider_metadata,prompt_tokens}','9007199254740992'),'safe metadata integer'),(jsonb_set(v,'{provider_metadata,latency_ms}','1.5'),'integer metadata only'),
 (jsonb_set(v,'{provider_metadata,model}',to_jsonb(repeat('😀',65))),'metadata model UTF16 bound'),(jsonb_set(v,'{provider_metadata,model}',to_jsonb(repeat('x',200000))),'canonical envelope byte cap'),
 (jsonb_set(v,'{provider_metadata}',(v->'provider_metadata')||'{"raw_prompt":"private"}'),'closed provider metadata'),
 (jsonb_set(v,'{foods,0}',(v#>'{foods,0}')||'{"kcal":130}'),'closed food refs, no macros')
 ) cases(value,label) LOOP PERFORM pg_temp.semantic_reject(a,cmd,claim,bad,label);END LOOP;
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1')->>'status'='started','all rejected attempts leave single original invocation started');
END $invalid$;
DO $unicode$
DECLARE a uuid:='c3a30000-0000-4000-8000-000000000020';cmd uuid:='c3a30000-0000-4000-8000-000000000021';input jsonb;src jsonb;claim jsonb;v jsonb;x jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-unicode@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 input:=jsonb_set(pg_temp.writer_input(cmd),'{source,text}','"A😀B"');PERFORM public.admit_conversation_meal_command(a,input);src:=public.capture_conversation_meal_source(a,cmd);
 claim:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',src->>'source_hash');v:=pg_temp.semantic_result(claim);
 v:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(v,'{foods}','[]'),'{decision}','"clarification_required"'),'{reason}','"ambiguous"'),'{sources}','[{"unit":"command_text","classification":"ambiguous","spans":[{"start":0,"end":1,"kind":"other","food_index":null},{"start":1,"end":3,"kind":"other","food_index":null},{"start":3,"end":4,"kind":"other","food_index":null}],"visual_indexes":[]}]');
 PERFORM pg_temp.semantic_reject(a,cmd,claim,jsonb_set(v,'{sources,0,spans}','[{"start":0,"end":2,"kind":"other","food_index":null},{"start":2,"end":4,"kind":"other","food_index":null}]'),'UTF16 spans never cut a surrogate pair');
 x:=public.commit_conversation_meal_semantic_result(a,cmd,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,v);
 PERFORM pg_temp.writer_ok(x->>'status'='completed' AND x->'result'=v,'exact UTF16 partition survives durable replay');
END $unicode$;
SELECT count(*) AS semantic_validation_assertions FROM meal_writer_assertions;
ROLLBACK;

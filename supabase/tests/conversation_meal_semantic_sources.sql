BEGIN;
\ir fixtures/conversation_meal_semantic_fixture.sql
DO $first_claim$
DECLARE a uuid:='c3a40000-0000-4000-8000-000000000001';cmd uuid;src jsonb;x jsonb;mode text;n integer:=10;ok boolean;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-current-source@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH mode IN ARRAY ARRAY['closed','timezone','profile','config','catalog'] LOOP
  n:=n+1;cmd:=('c3a40000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;src:=pg_temp.writer_seed(a,cmd);ok:=false;
  BEGIN
   IF mode='closed' THEN INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(a,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
   ELSIF mode='timezone' THEN UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=a;
   ELSIF mode='profile' THEN INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_step) VALUES(a,false,0);
   ELSIF mode='config' THEN INSERT INTO public.global_config(key,value) VALUES('calc.synthetic_conversation_semantic_v1','1'::jsonb);
   ELSE INSERT INTO public.food_db(id,name_pt,source) VALUES(2140000020,'synthetic semantic source fence','test');DELETE FROM public.food_db WHERE id=2140000020;END IF;
   x:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',src->>'source_hash');
   ok:=x=jsonb_build_object('action',CASE WHEN mode='closed' THEN 'day_closed' ELSE 'source_conflict' END) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_semantic_attempts WHERE user_id=a AND command_id=cmd);
   RAISE EXCEPTION 'rollback source drift fixture' USING ERRCODE='P5512';
  EXCEPTION WHEN SQLSTATE 'P5512' THEN NULL;END;
  PERFORM pg_temp.writer_ok(ok,'fresh current source before first claim '||mode);
 END LOOP;
END $first_claim$;
DO $media$
DECLARE a uuid:='c3a40000-0000-4000-8000-000000000030';cmd uuid:='c3a40000-0000-4000-8000-000000000031';asset uuid:='c3a40000-0000-4000-8000-000000000032';src jsonb;claim jsonb;v jsonb;x jsonb;code text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-media-drift@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);src:=pg_temp.semantic_media_seed(a,cmd,asset);
 BEGIN
  UPDATE public.media_assets SET processing_result='{"items":[{"name":"feijao"}]}' WHERE id=asset;
  x:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',src->>'source_hash');
  PERFORM pg_temp.writer_ok(x='{"action":"source_conflict"}'::jsonb AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_semantic_attempts WHERE user_id=a),'changed processing source never claims provider');
  RAISE EXCEPTION 'rollback media drift fixture' USING ERRCODE='P5512';
 EXCEPTION WHEN SQLSTATE 'P5512' THEN NULL;END;
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_semantic_attempts WHERE user_id=a),'media drift attempt remains absent');
 claim:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',src->>'source_hash');
 v:=pg_temp.semantic_result(claim);v:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(v,'{source_units}','["vision_items"]'),'{foods}','[]'),'{decision}','"clarification_required"'),'{reason}','"ambiguous"'),'{sources}','[{"unit":"vision_items","classification":"visual","spans":[],"visual_indexes":[0]}]');
 UPDATE public.media_assets SET deleted_at=clock_timestamp() WHERE id=asset;
 x:=public.commit_conversation_meal_semantic_result(a,cmd,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,v);
 PERFORM pg_temp.writer_ok(x->>'status'='completed' AND public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',NULL)=jsonb_set(x,'{action}','"replay"'),'late response survives current media deletion without fresh lookup/reclaim');
 BEGIN PERFORM public.prepare_conversation_meal(a,cmd,pg_temp.writer_resolved(src));EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 PERFORM pg_temp.writer_ok(code='40001' AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=a),'semantic result does not authorize domain with stale media');
END $media$;
DO $aged_unknown$
DECLARE a uuid:='c3a40000-0000-4000-8000-000000000040';cmd uuid:='c3a40000-0000-4000-8000-000000000041';epoch uuid:=gen_random_uuid();old_time timestamptz:=clock_timestamp()-interval '25 hours';input jsonb;ih text;context jsonb;sh text;x jsonb;y jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-aged@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);input:=pg_temp.writer_input(cmd);ih:=encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(a,epoch,old_time-interval '1 second');
 INSERT INTO private.conversation_meal_command_ids VALUES(a,cmd,ih,'conversation.command.v1','meal.report',epoch,old_time-interval '1 second',NULL);
 INSERT INTO private.conversation_meal_command_sources VALUES(a,cmd,input);
 PERFORM private.lock_conversation_meal(a,cmd);context:=private.conversation_meal_source_at(a,cmd,old_time);sh:=encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_source_captures VALUES(a,cmd,sh,context,old_time);
 INSERT INTO private.conversation_meal_semantic_attempts VALUES(a,cmd,'conversation.meal-interpreter.v1',epoch,ih,sh,gen_random_uuid(),old_time);
 x:=public.read_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1');y:=public.start_conversation_meal_semantic_attempt(a,cmd,'conversation.meal-interpreter.v1',NULL);
 PERFORM pg_temp.writer_ok(x=y AND x->>'action'='reconciliation_required' AND (x->>'started_at')::timestamptz<clock_timestamp()-interval '24 hours' AND (SELECT count(*)=1 FROM private.conversation_meal_semantic_attempts WHERE user_id=a),'started attempt older than24h never expires into new permission');
END $aged_unknown$;
DO $prepared_c11$
DECLARE a uuid:='c3a40000-0000-4000-8000-000000000050';auth_id uuid:='c3a40000-0000-4000-8000-000000000051';cmd uuid:='c3a40000-0000-4000-8000-000000000052';src jsonb;p jsonb;e jsonb;frozen jsonb;state jsonb;x jsonb;before_all jsonb;mid uuid;sid uuid;
BEGIN
 INSERT INTO auth.users(id) VALUES(auth_id);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed) VALUES(a,auth_id,'semantic-read-c11@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);src:=pg_temp.writer_seed(a,cmd);p:=public.prepare_conversation_meal(a,cmd,pg_temp.writer_resolved(src));e:=public.commit_conversation_meal(a,cmd,p->>'resolved_hash');
 frozen:=public.read_conversation_meal_prepared(a,cmd);mid:=(e#>>'{receipt,log_ids,0}')::uuid;SELECT snapshot_id INTO sid FROM public.meal_logs WHERE id=mid;state:=pg_temp.semantic_c11_state(a,sid,mid);
 x:=public.mutate_mobile_confirmed_meal(a,'synthetic-semantic-read-c11','PATCH','/api/mobile/v1/meal-records/'||mid::text,repeat('c',64),mid,'v1:'||repeat('a',64),ARRAY[mid],state,
 '[{"food_name":"arroz sintetico","food_db_id":null,"source":"user_kcal","quantity_g":100,"kcal":140,"protein_g":2.31,"carbs_g":28.21,"fat_g":0.21,"confidence":null}]','recalculated',NULL,'synthetic-semantic-read-c11');
 before_all:=pg_temp.semantic_owner_state(a);
 PERFORM pg_temp.writer_ok(x->>'action'='completed' AND public.read_conversation_meal_prepared(a,cmd)=frozen AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE id=mid) AND pg_temp.semantic_owner_state(a)=before_all,'prepared/effect recovery stays original and read-only after actual C11');
END $prepared_c11$;
DO $acl$
DECLARE sig text;t text;role_name text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['public.start_conversation_meal_semantic_attempt(uuid,uuid,text,text)','public.read_conversation_meal_semantic_attempt(uuid,uuid,text)','public.commit_conversation_meal_semantic_result(uuid,uuid,text,uuid,jsonb)','public.mark_conversation_meal_semantic_unknown(uuid,uuid,text,uuid,text)','public.read_conversation_meal_prepared(uuid,uuid)'] LOOP
  PERFORM pg_temp.writer_ok(has_function_privilege('service_role',sig,'EXECUTE') AND NOT has_function_privilege('anon',sig,'EXECUTE') AND NOT has_function_privilege('authenticated',sig,'EXECUTE'),'semantic service-only RPC '||sig);END LOOP;
 FOREACH t IN ARRAY ARRAY['private.conversation_meal_semantic_attempts','private.conversation_meal_semantic_results'] LOOP
  PERFORM pg_temp.writer_ok((SELECT relrowsecurity FROM pg_class WHERE oid=t::regclass),'semantic RLS '||t);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP PERFORM pg_temp.writer_ok(NOT has_table_privilege(role_name,t,'SELECT,INSERT,UPDATE,DELETE'),'semantic no direct grants '||t||' '||role_name);END LOOP;
 END LOOP;
END $acl$;
SELECT count(*) AS semantic_source_assertions FROM meal_writer_assertions;
ROLLBACK;

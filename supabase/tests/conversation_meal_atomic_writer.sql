-- Exact owned local PostgreSQL only; every synthetic business row rolls back.
BEGIN;
\ir fixtures/conversation_meal_atomic_writer_fixture.sql
DO $test$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000001';c uuid:='c3c00000-0000-4000-8000-000000000002';d uuid:='c3c00000-0000-4000-8000-000000000003';
 source jsonb;second_source jsonb;resolved jsonb;prepared jsonb;x jsonb;y jsonb;h text;original jsonb;
BEGIN
 PERFORM pg_temp.writer_ok(to_regprocedure('public.commit_conversation_meal(uuid,uuid,text)') IS NOT NULL,'atomic writer exists');
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-meal-a@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 source:=pg_temp.writer_seed(a,c);second_source:=pg_temp.writer_seed(a,d);
 PERFORM pg_temp.writer_ok(source->>'action'='captured' AND source#>'{context,day,calories_target}'='null'::jsonb,'server capture before calculator preserves missing official target');
 resolved:=pg_temp.writer_resolved(source);prepared:=public.prepare_conversation_meal(a,c,resolved);h:=prepared->>'resolved_hash';
 PERFORM pg_temp.writer_ok(prepared->>'action'='prepared','separate full authoritative preparation');
 x:=public.commit_conversation_meal(a,c,h);
 PERFORM pg_temp.writer_ok(x->>'action'='committed','atomic meal commits');
 PERFORM pg_temp.writer_ok((SELECT count(*)=1 AND min(quantity_g)=100 AND min(kcal)=130.04 AND min(meal_type::text)='almoco' FROM public.meal_logs WHERE user_id=a),'one exact rounded persisted effect, selected meal preserved');
 PERFORM pg_temp.writer_ok((SELECT count(*)=1 AND bool_and(calories_target IS NULL AND protein_target IS NULL) FROM public.daily_snapshots WHERE user_id=a),'first snapshot never invents target');
 PERFORM pg_temp.writer_ok((SELECT count(*)=1 AND bool_and(status='confirmed') FROM public.pending_registrations WHERE user_id=a),'confirmed pending same transaction');
 PERFORM pg_temp.writer_ok((x->'receipt')-ARRAY['schema','owner_id','command_id','input_hash','registration_id','provider_key','meal_type','local_date','timezone','consumed_at','log_ids','effect_version']='{}'::jsonb,'minimal public effect receipt has no numeric health facts');
 y:=public.commit_conversation_meal(a,c,NULL);
 PERFORM pg_temp.writer_ok(y=jsonb_set(x,'{action}','"replay"'),'lost response replays before fresh arguments');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_effect(a,c)=jsonb_build_object('action','available','receipt',x->'receipt'),'read receipt has no effects');
 -- The second source was captured while the day did not exist. First append
 -- must not invalidate it through snapshot ID, updated_at or intake counters.
 prepared:=public.prepare_conversation_meal(a,d,pg_temp.writer_resolved(second_source));
 PERFORM pg_temp.writer_ok(prepared->>'action'='prepared','absent NULL day to created NULL day preserves append source');
 y:=public.commit_conversation_meal(a,d,prepared->>'resolved_hash');
 PERFORM pg_temp.writer_ok(y->>'action'='committed' AND (SELECT count(*)=2 AND count(DISTINCT raw_provider_message_id)=2 FROM public.meal_logs WHERE user_id=a),'different UUID identical meal has two additive groups');
 SELECT original_facts INTO original FROM private.conversation_meal_effects WHERE user_id=a AND command_id=c;
 UPDATE public.meal_logs SET kcal=140 WHERE user_id=a AND raw_provider_message_id=x#>>'{receipt,provider_key}';
 PERFORM pg_temp.writer_ok((SELECT original_facts=original AND feedback_context->'logs'=original->'logs' FROM private.conversation_meal_effects WHERE user_id=a AND command_id=c),'later C11-equivalent fact edit leaves original frozen context');
 UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=a;
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,NULL)=jsonb_set(x,'{action}','"replay"'),'closed day retry never repeats effect');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,NULL)='{"action":"stale_epoch"}'::jsonb AND public.read_conversation_meal_effect(a,c)='{"action":"stale_epoch"}'::jsonb,'completed UUID fenced after reset');
 PERFORM pg_temp.writer_ok((SELECT count(*)=2 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_meal_command_ids WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_source_captures WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=a),'reset retains identity and scrubs every new personal payload');
END $test$;
CREATE FUNCTION pg_temp.writer_bad(u uuid,c uuid,v jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE code text;message text; BEGIN BEGIN PERFORM public.prepare_conversation_meal(u,c,v); EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT; END;
 IF code IS DISTINCT FROM '22023' THEN RAISE NOTICE 'invalid-case % returned %: %',label,code,message; END IF;
 PERFORM pg_temp.writer_ok(code='22023',label); END $$;
DO $invalid$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000010';c uuid:='c3c00000-0000-4000-8000-000000000011';source jsonb;v jsonb;k text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-invalid@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 source:=pg_temp.writer_seed(a,c);v:=pg_temp.writer_resolved(source);
 FOREACH k IN ARRAY ARRAY['schema','input_hash','source_hash','meal_type','semantic_proof','items','totals','preparation_annotations'] LOOP
  PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,ARRAY[k],'null'),'reject resolved null '||k);
 END LOOP;
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{semantic_proof,complete_source}','false'),'opaque incomplete semantics never authorize');
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{semantic_proof,source_units}','[]'),'whole evidence source units required');
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{semantic_proof,input_count}','2'),'all calculation input indexes covered');
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{items}',(v->'items')||(v->'items')),'duplicate canonical names refused before base dedup');
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{items,0,nutrition_source}','"no_match"'),'unresolved nutrition refused');
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{meal_type}','"jantar"'),'selected meal kind cannot be overridden');
 PERFORM pg_temp.writer_bad(a,c,jsonb_set(v,'{preparation_annotations}',jsonb_build_array(jsonb_build_object('schema','consumed.preparation.v1','kind','default_cooked','input_indexes',jsonb_build_array(0,0),'food_name','arroz sintetico','policy','synthetic-policy.v1','reference_id','synthetic-ref'))),'duplicate annotation input indexes refused');
END $invalid$;
DO $drift$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000020';c uuid;src jsonb;prep jsonb;x jsonb;mode text;catalog_epoch uuid;food_count bigint;code text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-drift@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target) VALUES(a,(clock_timestamp() AT TIME ZONE 'UTC')::date,1900,120);
 FOREACH mode IN ARRAY ARRAY['timezone','profile','config','catalog','targets','closed','midnight'] LOOP
  c:=gen_random_uuid();src:=pg_temp.writer_seed(a,c);prep:=public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src));
  BEGIN
   IF mode='timezone' THEN UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=a;
   ELSIF mode='profile' THEN INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_step) VALUES(a,false,0);
   ELSIF mode='config' THEN INSERT INTO public.global_config(key,value) VALUES('calc.synthetic_conversation_writer','1'::jsonb);
   ELSIF mode='catalog' THEN INSERT INTO public.food_db(id,name_pt,source) VALUES(2140000001,'synthetic conversation source fence','test');DELETE FROM public.food_db WHERE id=2140000001;
   ELSIF mode='targets' THEN UPDATE public.daily_snapshots SET calories_target=2000 WHERE user_id=a;UPDATE public.daily_snapshots SET calories_target=1900 WHERE user_id=a;
   ELSIF mode='closed' THEN UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=a;
   END IF;
   x:=CASE WHEN mode='midnight' THEN private.commit_conversation_meal_at(a,c,prep->>'resolved_hash',clock_timestamp()+interval '1 day') ELSE public.commit_conversation_meal(a,c,prep->>'resolved_hash') END;
   PERFORM pg_temp.writer_ok(x='{"action":"source_conflict"}'::jsonb,'commit source drift fenced '||mode);
   IF EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=a) THEN RAISE EXCEPTION 'drift wrote domain'; END IF;
   RAISE EXCEPTION 'rollback synthetic drift' USING ERRCODE='P5507';
  EXCEPTION WHEN SQLSTATE 'P5507' THEN NULL; END;
  -- Assertion rows inside the rollback disappear; record successful test after.
  PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=a),'no effect after drift '||mode);
 END LOOP;
 c:=gen_random_uuid();src:=pg_temp.writer_seed(a,c);
 SELECT r.epoch INTO catalog_epoch FROM private.conversation_food_catalog_revision r WHERE singleton;
 UPDATE public.food_db SET source=source WHERE false;
 PERFORM pg_temp.writer_ok((SELECT r.epoch=catalog_epoch FROM private.conversation_food_catalog_revision r WHERE singleton),'zero-row catalog statement does not advance epoch');
 SELECT count(*) INTO food_count FROM public.food_db;
 BEGIN
  TRUNCATE public.food_db CASCADE;
  PERFORM pg_temp.writer_ok((SELECT r.epoch<>catalog_epoch FROM private.conversation_food_catalog_revision r WHERE singleton),'truncate fences catalog source');
  RAISE EXCEPTION 'rollback truncate test' USING ERRCODE='P5507';
 EXCEPTION WHEN SQLSTATE 'P5507' THEN NULL; END;
 PERFORM pg_temp.writer_ok((SELECT count(*)=food_count FROM public.food_db) AND (SELECT r.epoch=catalog_epoch FROM private.conversation_food_catalog_revision r WHERE singleton),'catalog truncate rollback preserves data and epoch');
 -- Candidate-only prepared never reaches the domain writer.
 PERFORM public.attach_conversation_meal_candidate(a,c,src#>>'{context,input_hash}',jsonb_build_object('schema','conversation.meal-candidate.v1','input_hash',src#>'{context,input_hash}','status','prepared','candidate','{}'::jsonb));
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,repeat('a',64))='{"action":"resolved_required"}'::jsonb,'opaque candidate never authorizes writer');
END $drift$;
CREATE FUNCTION pg_temp.writer_forced_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic atomic failure' USING ERRCODE='P5508'; END $$;
DO $atomic_failure$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000040';c uuid;src jsonb;prep jsonb;x jsonb;code text;target text;definition text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-failure@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH target IN ARRAY ARRAY['public.meal_logs','private.conversation_meal_effects'] LOOP
  c:=gen_random_uuid();src:=pg_temp.writer_seed(a,c);prep:=public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src));code:=NULL;
  EXECUTE format('CREATE TRIGGER qa_atomic_failure AFTER INSERT ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.writer_forced_failure()',target);
  BEGIN PERFORM public.commit_conversation_meal(a,c,prep->>'resolved_hash'); EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  EXECUTE format('DROP TRIGGER qa_atomic_failure ON %s',target);
  PERFORM pg_temp.writer_ok(code='P5508' AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=a),'domain snapshot pending receipt roll back '||target);
 END LOOP;
 -- Optional enrichment is deliberately unavailable, while mandatory identity /
 -- exact original domain facts still commit once and replays do not try again.
 c:=gen_random_uuid();src:=pg_temp.writer_seed(a,c);prep:=public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src));
 SELECT pg_get_functiondef('private.capture_mobile_registration_feedback_v2(uuid,uuid)'::regprocedure) INTO definition;
 EXECUTE $replace$CREATE OR REPLACE FUNCTION private.capture_mobile_registration_feedback_v2(p_owner uuid,p_registration uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $body$BEGIN RAISE EXCEPTION 'synthetic optional enrichment failure' USING ERRCODE='P5509'; END $body$$replace$;
 x:=public.commit_conversation_meal(a,c,prep->>'resolved_hash');
 EXECUTE definition;
 PERFORM pg_temp.writer_ok(x->>'action'='committed' AND (SELECT feedback_context IS NULL AND jsonb_array_length(original_facts->'logs')=1 FROM private.conversation_meal_effects WHERE user_id=a AND command_id=c),'optional capture failure preserves mandatory factual commit');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,NULL)=jsonb_set(x,'{action}','"replay"') AND (SELECT count(*)=1 FROM public.meal_logs WHERE user_id=a),'optional capture failure retry has no second domain effect');
END $atomic_failure$;
DO $media$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000050';c uuid:='c3c00000-0000-4000-8000-000000000051';asset uuid:='c3c00000-0000-4000-8000-000000000052';src jsonb;prep jsonb;input jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-media@example.invalid','active','Pacific/Kiritimati','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,context_text,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(asset,a,'audio_note','audio-notes',a::text||'/'||asset::text||'.mp3','audio/mpeg',1200,1200,'processed','Meu almoco',repeat('f',64),repeat('e',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),'{"text":"Comi 100g de arroz sintetico"}');
 input:=jsonb_set(pg_temp.writer_input(c),'{source}',jsonb_build_object('channel','media','media_asset_id',asset,'user_action','register_consumed_meal'));
 PERFORM public.admit_conversation_meal_command(a,input);src:=public.capture_conversation_meal_source(a,c);
 PERFORM pg_temp.writer_ok(src#>'{context,source_units}'='["media_caption","media_transcript"]'::jsonb AND src#>>'{context,day,date}'=(clock_timestamp() AT TIME ZONE 'Pacific/Kiritimati')::date::text,'actual owned audio units and server timezone captured');
 prep:=public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src));
 UPDATE public.media_assets SET processing_result='{"text":"Comi 200g de arroz sintetico"}' WHERE id=asset;
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,prep->>'resolved_hash')='{"action":"source_conflict"}'::jsonb AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=a),'media processing drift fenced before effect');
END $media$;
CREATE FUNCTION pg_temp.writer_c11_state(owner_id uuid,snapshot_id uuid,anchor_id uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('context',jsonb_build_object('id',u.id,'auth_user_id',u.auth_user_id,'country',u.country,'country_confirmed',u.country_confirmed,'timezone',u.timezone,'status',u.status,'wpp',u.wpp,'updated_at',u.updated_at),'snapshot',to_jsonb(s),
 'items',(SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.meal_logs m WHERE m.user_id=u.id AND m.snapshot_id=s.id AND m.raw_provider_message_id=a.raw_provider_message_id))
 FROM public.users u JOIN public.daily_snapshots s ON s.user_id=u.id JOIN public.meal_logs a ON a.user_id=u.id AND a.snapshot_id=s.id WHERE u.id=$1 AND s.id=$2 AND a.id=$3 $$;
DO $actual_c11$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000060';auth_id uuid:='c3c00000-0000-4000-8000-000000000061';c uuid:='c3c00000-0000-4000-8000-000000000062';src jsonb;prep jsonb;committed jsonb;frozen jsonb;state jsonb;mid uuid;sid uuid;x jsonb;
BEGIN
 INSERT INTO auth.users(id) VALUES(auth_id);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed) VALUES(a,auth_id,'atomic-c11@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 src:=pg_temp.writer_seed(a,c);prep:=public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src));committed:=public.commit_conversation_meal(a,c,prep->>'resolved_hash');
 SELECT to_jsonb(e) INTO frozen FROM private.conversation_meal_effects e WHERE user_id=a AND command_id=c;
 mid:=(committed#>>'{receipt,log_ids,0}')::uuid;SELECT snapshot_id INTO sid FROM public.meal_logs WHERE id=mid;
 state:=pg_temp.writer_c11_state(a,sid,mid);
 x:=public.mutate_mobile_confirmed_meal(a,'synthetic-command-c11-edit','PATCH','/api/mobile/v1/meal-records/'||mid::text,repeat('e',64),mid,'v1:'||repeat('a',64),ARRAY[mid],state,
 '[{"food_name":"arroz sintetico","food_db_id":null,"source":"user_kcal","quantity_g":100,"kcal":140,"protein_g":2.31,"carbs_g":28.21,"fat_g":0.21,"confidence":null}]','recalculated',NULL,'synthetic-command-c11');
 PERFORM pg_temp.writer_ok(x->>'action'='completed' AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE id=mid),'actual C11 edit replaces original effect log');
 PERFORM pg_temp.writer_ok((SELECT to_jsonb(e)=frozen FROM private.conversation_meal_effects e WHERE user_id=a AND command_id=c),'actual C11 cannot rewrite frozen original facts or optional v2 source');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,NULL)=jsonb_set(committed,'{action}','"replay"'),'C11 edit before future sealing never repeats command effect');
END $actual_c11$;
DO $official_and_service$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000070';c uuid:='c3c00000-0000-4000-8000-000000000071';pending uuid:='c3c00000-0000-4000-8000-000000000072';src jsonb;prep jsonb;x jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-official@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target) VALUES(a,(clock_timestamp() AT TIME ZONE 'UTC')::date,1900,120);
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(pending,a,'pending','{"kind":"workout","synthetic":"keep"}',clock_timestamp()+interval '1 hour');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 src:=pg_temp.writer_seed(a,c);prep:=public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src));
 SET LOCAL ROLE service_role;x:=public.commit_conversation_meal(a,c,prep->>'resolved_hash');SET LOCAL ROLE NONE;
 PERFORM pg_temp.writer_ok(x->>'action'='committed' AND (SELECT calories_target=1900 AND protein_target=120 AND xp_earned=0 FROM public.daily_snapshots WHERE user_id=a),'actual service role preserves official targets and XP');
 PERFORM pg_temp.writer_ok((SELECT status='pending' AND proposal='{"kind":"workout","synthetic":"keep"}'::jsonb FROM public.pending_registrations WHERE id=pending) AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=a),'unrelated pending and progress remain untouched');
END $official_and_service$;
DO $old_replay$
DECLARE a uuid:='c3c00000-0000-4000-8000-000000000080';c uuid:='c3c00000-0000-4000-8000-000000000081';epoch uuid:=gen_random_uuid();old_time timestamptz:=clock_timestamp()-interval '25 hours';input jsonb;ih text;context jsonb;sh text;resolved jsonb;rh text;x jsonb;
BEGIN
 -- Qualified private clock seam constructs a coherent historical synthetic
 -- effect. Public transport has no caller-controlled clock or source context.
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-old@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 input:=pg_temp.writer_input(c);ih:=encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(a,epoch,old_time-interval '1 second');
 INSERT INTO private.conversation_meal_command_ids VALUES(a,c,ih,'conversation.command.v1','meal.report',epoch,old_time-interval '1 second',NULL);
 INSERT INTO private.conversation_meal_command_sources VALUES(a,c,input);
 PERFORM private.lock_conversation_meal(a,c);context:=private.conversation_meal_source_at(a,c,old_time);sh:=encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_source_captures VALUES(a,c,sh,context,old_time);
 resolved:=pg_temp.writer_resolved(jsonb_build_object('context',context,'source_hash',sh));PERFORM private.assert_conversation_resolved_meal(resolved,context,sh);
 rh:=encode(sha256(convert_to(private.conversation_command_canonical(resolved),'UTF8')),'hex');INSERT INTO private.conversation_meal_resolved VALUES(a,c,rh,resolved,old_time);
 x:=private.commit_conversation_meal_at(a,c,rh,old_time);
 PERFORM pg_temp.writer_ok(x->>'action'='committed' AND (SELECT committed_at<clock_timestamp()-interval '24 hours' FROM private.conversation_meal_effects WHERE user_id=a AND command_id=c),'historical synthetic command effect older than 24h');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,c,NULL)=jsonb_set(x,'{action}','"replay"') AND (SELECT count(*)=1 FROM public.meal_logs WHERE user_id=a),'durable lost-response replay beyond 24h has one effect');
END $old_replay$;
DO $acl$
DECLARE f text;t text;role text;
BEGIN
 FOREACH f IN ARRAY ARRAY['public.capture_conversation_meal_source(uuid,uuid)','public.prepare_conversation_meal(uuid,uuid,jsonb)','public.commit_conversation_meal(uuid,uuid,text)','public.read_conversation_meal_effect(uuid,uuid)','public.read_conversation_meal_nutrition_source(uuid,uuid,text,text)'] LOOP
  PERFORM pg_temp.writer_ok(has_function_privilege('service_role',f,'EXECUTE') AND NOT has_function_privilege('anon',f,'EXECUTE') AND NOT has_function_privilege('authenticated',f,'EXECUTE'),'trusted-only writer RPC '||f);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['private.conversation_food_catalog_revision','private.conversation_meal_source_captures','private.conversation_meal_resolved','private.conversation_meal_effects','private.conversation_meal_nutrition_sources'] LOOP
  PERFORM pg_temp.writer_ok((SELECT relrowsecurity FROM pg_class WHERE oid=t::regclass),'writer RLS '||t);
  FOREACH role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.writer_ok(NOT has_table_privilege(role,t,'SELECT,INSERT,UPDATE,DELETE'),'writer no direct table grants '||role||' '||t);
  END LOOP;
 END LOOP;
END $acl$;
SELECT count(*) FROM meal_writer_assertions;
ROLLBACK;

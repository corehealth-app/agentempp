-- Owned synthetic PostgreSQL only. Every row and DDL is rolled back.
BEGIN;
CREATE TEMP TABLE workout_assertions(label text);
CREATE TEMP TABLE workout_actual_golden(kind text,source jsonb,preparation jsonb,effect jsonb);
CREATE FUNCTION pg_temp.workout_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'WORKOUT_ASSERT: %',label;END IF;INSERT INTO workout_assertions VALUES(label);END $$;
CREATE FUNCTION pg_temp.workout_seed(u uuid,c uuid,t text DEFAULT 'Fiz 30 minutos de caminhada.') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid;x jsonb;h text;BEGIN
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 x:=public.admit_conversation_workout_command(u,e,jsonb_build_object('command_protocol','conversation.command.v1','command_id',c,'kind','workout.report','source',jsonb_build_object('channel','text','text',t)));
 PERFORM pg_temp.workout_ok(x->>'action'='admitted','admitted source');h:=x#>>'{command,input_hash}';
 RETURN public.capture_conversation_workout_source(u,c,h,e);
END $$;
CREATE FUNCTION pg_temp.workout_prepare(s jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.prepare_conversation_workout((s#>>'{context,owner_id}')::uuid,(s#>>'{context,command_id}')::uuid,s#>>'{context,input_hash}',s->>'source_hash',(s#>>'{context,epoch}')::uuid,private.conversation_workout_report(s->'context',s->>'source_hash'));
$$;
CREATE FUNCTION pg_temp.workout_commit(s jsonb,p jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.commit_conversation_workout((s#>>'{context,owner_id}')::uuid,(s#>>'{context,command_id}')::uuid,s#>>'{context,input_hash}',s->>'source_hash',(s#>>'{context,epoch}')::uuid,p->>'prepared_hash',p->'prepared');
$$;
DO $core$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000001';a uuid:='139c0000-0000-4000-8000-000000000002';b uuid:='139c0000-0000-4000-8000-000000000003';e uuid:=gen_random_uuid();s jsonb;t jsonb;p jsonb;q jsonb;x jsonb;y jsonb;f jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-atomic-core@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 s:=pg_temp.workout_seed(u,a);t:=pg_temp.workout_seed(u,b);
 p:=pg_temp.workout_prepare(s);PERFORM pg_temp.workout_ok(p->>'action'='prepared' AND p#>>'{prepared,status}'='ready','literal performed report prepared');
 PERFORM pg_temp.workout_ok(p#>'{prepared,activity,estimated_kcal}'='null'::jsonb AND p#>>'{prepared,energy,status}'='unavailable','unknown weight and intensity have nullable energy, no fallback');
 x:=pg_temp.workout_commit(s,p);PERFORM pg_temp.workout_ok(x->>'action'='committed','actual atomic commit');
 PERFORM pg_temp.workout_ok((SELECT count(*)=1 AND bool_and(estimated_kcal IS NULL) FROM public.workout_logs WHERE user_id=u),'one real workout NULL kcal');
 PERFORM pg_temp.workout_ok((SELECT count(*)=1 AND bool_and(NOT exercise_energy_complete AND exercise_calories=0 AND calories_target IS NULL AND protein_target IS NULL) FROM public.daily_snapshots WHERE user_id=u),'known partial sum remains private and coverage false, targets not minted');
 PERFORM pg_temp.workout_ok((SELECT count(*)=1 FROM private.workout_strength_facts WHERE user_id=u) AND (SELECT count(*)=1 FROM private.workout_strength_operations WHERE user_id=u) AND (SELECT count(*)=1 FROM private.conversation_workout_events WHERE user_id=u AND kind='registered'),'strength receipt and event atomic');
 PERFORM pg_temp.workout_ok(NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u),'registration never grants XP or block credit');
 y:=public.read_conversation_workout_effect(u,a,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash');
 PERFORM pg_temp.workout_ok(y->>'action'='available' AND y->'receipt'=x->'receipt','independent durable receipt read');f:=y->'original_facts';
 INSERT INTO workout_actual_golden VALUES('unknown',s,p,y);
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)=jsonb_set(x,'{action}','"replay"'),'same command replays exactly');
 q:=pg_temp.workout_prepare(t);y:=pg_temp.workout_commit(t,q);
 PERFORM pg_temp.workout_ok(y->>'action'='committed' AND (SELECT count(*)=2 AND count(DISTINCT raw_provider_message_id)=2 FROM public.workout_logs WHERE user_id=u),'two identical legitimate activities remain distinct despite same window');
 UPDATE public.workout_logs SET estimated_kcal=110 WHERE user_id=u;
 PERFORM pg_temp.workout_ok((SELECT exercise_energy_complete AND exercise_calories=220 FROM public.daily_snapshots WHERE user_id=u),'unknown to known correction repairs coverage');
 UPDATE public.workout_logs SET estimated_kcal=NULL WHERE user_id=u AND id=(x#>>'{receipt,workout_id}')::uuid;
 PERFORM pg_temp.workout_ok((SELECT NOT exercise_energy_complete AND exercise_calories=110 FROM public.daily_snapshots WHERE user_id=u),'Undo energy correction restores unknown coverage');
 DELETE FROM public.workout_logs WHERE user_id=u AND id=(x#>>'{receipt,workout_id}')::uuid;
 PERFORM pg_temp.workout_ok((SELECT exercise_energy_complete AND exercise_calories=110 FROM public.daily_snapshots WHERE user_id=u),'Undo registration removes unknown row without permanent block');
 PERFORM pg_temp.workout_ok((SELECT original_facts=f AND live_workout_id IS NULL FROM private.conversation_workout_effects WHERE user_id=u AND command_id=a),'original facts survive Undo');
 UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=u;
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)=jsonb_set(x,'{action}','"replay"'),'closed day replays historical receipt');
END $core$;

DO $guards$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000010';other_id uuid:='139c0000-0000-4000-8000-000000000011';e uuid:=gen_random_uuid();c uuid;s jsonb;p jsonb;x jsonb;kind text;input jsonb;code text;n integer;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-guards@example.invalid','active','UTC','BR',true),(other_id,'workout-foreign@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 FOREACH kind IN ARRAY ARRAY['Farei 30 minutos de caminhada.','Vou fazer caminhada.','Eu não fiz caminhada.','Sempre faço caminhada.','Ele fez 30 minutos de caminhada.','Fiz 30 minutos de caminhada?','Comi arroz e fiz 30 minutos de caminhada.','Fiz caminhada.','Fiz 30 minutos de outro.'] LOOP
  c:=gen_random_uuid();s:=pg_temp.workout_seed(u,c,kind);p:=pg_temp.workout_prepare(s);x:=pg_temp.workout_commit(s,p);
  PERFORM pg_temp.workout_ok(x->>'action'='not_ready' AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'question/future/habit/negation/thirdparty/mixed/unsupported never writes');
  PERFORM pg_temp.workout_ok(pg_temp.workout_prepare(s)=jsonb_set(p,'{action}','"replay"'),'preserved one question replays');
 END LOOP;
 c:=gen_random_uuid();s:=pg_temp.workout_seed(u,c);p:=pg_temp.workout_prepare(s);
 PERFORM pg_temp.workout_ok(public.prepare_conversation_workout(u,c,s#>>'{context,input_hash}',s->>'source_hash',e,'{"status":"ready"}')='{"action":"semantic_conflict"}'::jsonb,'client performed flag is not proof');
 PERFORM pg_temp.workout_ok(public.commit_conversation_workout(u,c,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',jsonb_set(p->'prepared','{activity,estimated_kcal}','900'))='{"action":"prepared_conflict"}'::jsonb,'caller cannot forge energy');
 PERFORM pg_temp.workout_ok(public.read_conversation_workout_effect(other_id,c,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash')='{"action":"absent"}'::jsonb,'foreign owner cannot read source/effect');
 UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=u;
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)->>'action'='source_conflict','owner timezone changed after preparation refuses effect');
 UPDATE public.users SET timezone='UTC' WHERE id=u;
 UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=u;
 -- No day existed yet; creating a closed day is a real durable boundary.
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)->>'action'='day_closed','closed source refuses fresh write');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.workout_ok(public.read_conversation_workout_preparation(u,c,s#>>'{context,input_hash}',e)='{"action":"stale_epoch"}'::jsonb AND pg_temp.workout_commit(s,p)->>'action'='stale_epoch','reset invalidates current and lost-success replay');
 PERFORM pg_temp.workout_ok((SELECT count(*)=10 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_workout_command_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_inputs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_sources WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_preparations WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_events WHERE user_id=u),'reset retains tombstones and scrubs all source/preparation/events');
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 input:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',c,'kind','workout.report','source',jsonb_build_object('channel','text','text','Fiz 30 minutos de caminhada.'));
 PERFORM pg_temp.workout_ok(public.admit_conversation_workout_command(u,e,input)->>'action'='stale_epoch','old UUID cannot re-admit in new epoch');
END $guards$;
DO $known$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000020';e uuid:=gen_random_uuid();c uuid:=gen_random_uuid();s jsonb;p jsonb;x jsonb;k integer;original jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-known@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(u,80);
 s:=pg_temp.workout_seed(u,c,'Fiz 30 minutos de caminhada moderada.');p:=pg_temp.workout_prepare(s);k:=public.calc_workout_kcal('caminhada',30,'moderada',80);
 PERFORM pg_temp.workout_ok(p#>>'{prepared,energy,status}'='available' AND (p#>>'{prepared,activity,estimated_kcal}')::integer=k,'existing exact current-weight formula retained');
 x:=pg_temp.workout_commit(s,p);PERFORM pg_temp.workout_ok(x->>'action'='committed' AND (SELECT exercise_energy_complete AND exercise_calories=k FROM public.daily_snapshots WHERE user_id=u),'known energy complete');
 INSERT INTO workout_actual_golden VALUES('known',s,p,public.read_conversation_workout_effect(u,c,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash'));
 original:=public.reconcile_conversation_workout(u,c,s#>>'{context,input_hash}',e);
 PERFORM pg_temp.workout_ok(original#>>'{current,status}'='present' AND original#>'{effect,receipt}'=x->'receipt','read-only reconciliation binds original/current');
 UPDATE public.user_profiles SET weight_kg=90 WHERE user_id=u;
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)=jsonb_set(x,'{action}','"replay"'),'lost success never regenerates estimate from new body');
END $known$;
DO $quota$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000030';e uuid:=gen_random_uuid();i integer;x jsonb;id uuid;body jsonb;first_body jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-quota@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 FOR i IN 1..10 LOOP
  id:=gen_random_uuid();body:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',id,'kind',CASE WHEN i%2=0 THEN 'meal.report' ELSE 'workout.report' END,'source',jsonb_build_object('channel','text','text',CASE WHEN i%2=0 THEN 'Comi arroz' ELSE 'Fiz caminhada' END));
  IF i=1 THEN first_body:=body;END IF;
  IF i%2=0 THEN x:=public.admit_conversation_meal_command_fenced(u,body,e);ELSE x:=public.admit_conversation_workout_command(u,e,body);END IF;
  PERFORM pg_temp.workout_ok(x->>'action'='admitted','mixed admissions share threshold');
 END LOOP;
 PERFORM pg_temp.workout_ok(public.admit_conversation_workout_command(u,e,first_body)->>'action'='replay','replay is free at cap');
 body:=jsonb_set(first_body,'{command_id}',to_jsonb(gen_random_uuid()));
 PERFORM pg_temp.workout_ok(public.admit_conversation_workout_command(u,e,body)->>'action'='rate_limited','workout cap includes meals');
 body:=jsonb_set(body,'{kind}','"meal.report"');
 PERFORM pg_temp.workout_ok(public.admit_conversation_meal_command_fenced(u,body,e)->>'action'='rate_limited','meal cap includes workouts');
 body:=jsonb_set(first_body,'{kind}','"meal.report"');
 PERFORM pg_temp.workout_ok(public.admit_conversation_meal_command_fenced(u,body,e)->>'action'='input_conflict','generic command bytes cannot be retyped to meal');
END $quota$;
DO $close$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000040';e uuid:=gen_random_uuid();c uuid:=gen_random_uuid();s jsonb;p jsonb;x jsonb;snap uuid;day date;code text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-close@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 s:=pg_temp.workout_seed(u,c);p:=pg_temp.workout_prepare(s);x:=pg_temp.workout_commit(s,p);snap:=(x#>>'{receipt,snapshot_id}')::uuid;day:=(s#>>'{context,clinical,date}')::date;
 BEGIN PERFORM public.finalize_daily_close_atomic(u,snap,'complete',50,1,1,1,0,120,ARRAY[]::text[],day);EXCEPTION WHEN SQLSTATE '40001' THEN code:=SQLSTATE;END;
 PERFORM pg_temp.workout_ok(code='40001' AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u) AND NOT(SELECT day_closed FROM public.daily_snapshots WHERE id=snap),'unknown day cannot grant energy credit');
 UPDATE public.daily_snapshots SET exercise_energy_complete=true WHERE id=snap;code:=NULL;
 BEGIN PERFORM public.finalize_daily_close_atomic(u,snap,'complete',50,1,1,1,0,120,ARRAY[]::text[],day);EXCEPTION WHEN SQLSTATE '40001' THEN code:=SQLSTATE;END;
 PERFORM pg_temp.workout_ok(code='40001' AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u),'actual NULL row independently refuses a forged complete marker');
 UPDATE public.daily_snapshots SET exercise_energy_complete=false WHERE id=snap;

 x:=public.finalize_daily_close_atomic(u,snap,'complete',50,1,1,1,0,0,ARRAY[]::text[],day);
 PERFORM pg_temp.workout_ok(x->>'applied'='true' AND (SELECT xp_total=50 AND deficit_block=0 FROM public.user_progress WHERE user_id=u),'existing XP/status allowed while energy credit held');
 x:=public.finalize_daily_close_atomic(u,snap,'complete',100,1,2,2,1,400,ARRAY[]::text[],day);
 PERFORM pg_temp.workout_ok(x->>'already_closed'='true' AND (SELECT xp_total=50 AND deficit_block=0 FROM public.user_progress WHERE user_id=u),'closed retry never doubles XP or changes old ledger');
 UPDATE public.workout_logs SET estimated_kcal=90 WHERE user_id=u;
 PERFORM pg_temp.workout_ok((SELECT exercise_energy_complete FROM public.daily_snapshots WHERE id=snap) AND (SELECT xp_total=50 AND deficit_block=0 FROM public.user_progress WHERE user_id=u),'late coverage repair never recalculates consolidated closed ledger');
END $close$;
DO $acl$
DECLARE name text;r text;
BEGIN
 FOREACH name IN ARRAY ARRAY['admit_conversation_workout_command(uuid,uuid,jsonb)','capture_conversation_workout_source(uuid,uuid,text,uuid)','prepare_conversation_workout(uuid,uuid,text,text,uuid,jsonb)','commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb)','read_conversation_workout_effect(uuid,uuid,text,text,uuid,text)','reconcile_conversation_workout(uuid,uuid,text,uuid)'] LOOP
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP PERFORM pg_temp.workout_ok(NOT has_function_privilege(r,'public.'||name,'EXECUTE'),'untrusted RPC ACL');END LOOP;
  PERFORM pg_temp.workout_ok(has_function_privilege('service_role','public.'||name,'EXECUTE'),'trusted RPC ACL');
 END LOOP;
 PERFORM pg_temp.workout_ok(NOT has_table_privilege('service_role','private.conversation_workout_effects','SELECT'),'service cannot bypass immutable effect RPC');
END $acl$;

CREATE FUNCTION pg_temp.workout_fingerprint(u uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('workouts',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workout_logs x WHERE user_id=u),
 'snapshots',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.daily_snapshots x WHERE user_id=u),
 'facts',(SELECT jsonb_agg(to_jsonb(x) ORDER BY workout_log_id) FROM private.workout_strength_facts x WHERE user_id=u),
 'operations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_key) FROM private.workout_strength_operations x WHERE user_id=u),
 'lifecycle',(SELECT jsonb_agg(to_jsonb(x) ORDER BY lifecycle_key) FROM private.workout_strength_lifecycles x WHERE user_id=u),
 'authority',(SELECT jsonb_agg(to_jsonb(x)) FROM private.workout_strength_authority_epochs x WHERE user_id=u),
 'effects',(SELECT jsonb_agg(to_jsonb(x) ORDER BY command_id) FROM private.conversation_workout_effects x WHERE user_id=u),
 'events',(SELECT jsonb_agg(to_jsonb(x) ORDER BY event_id) FROM private.conversation_workout_events x WHERE user_id=u));
$$;
CREATE FUNCTION pg_temp.fail_workout_write() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic mandatory workout evidence failure' USING ERRCODE='P1391';END $$;
DO $rollback$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000050';e uuid:=gen_random_uuid();c uuid:=gen_random_uuid();s jsonb;p jsonb;x jsonb;before_state jsonb;table_name text;code text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-rollback@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());s:=pg_temp.workout_seed(u,c);p:=pg_temp.workout_prepare(s);
 FOREACH table_name IN ARRAY ARRAY['workout_strength_facts','workout_strength_operations','conversation_workout_effects','conversation_workout_events'] LOOP
  before_state:=pg_temp.workout_fingerprint(u);code:=NULL;
  EXECUTE format('CREATE TRIGGER synthetic_mandatory_failure BEFORE INSERT ON private.%I FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_workout_write()',table_name);
  BEGIN PERFORM pg_temp.workout_commit(s,p);EXCEPTION WHEN SQLSTATE 'P1391' THEN code:=SQLSTATE;END;
  EXECUTE format('DROP TRIGGER synthetic_mandatory_failure ON private.%I',table_name);
  PERFORM pg_temp.workout_ok(code='P1391' AND pg_temp.workout_fingerprint(u)=before_state,'mandatory failure rolls back every workout/snapshot/lifecycle/strength/effect/event: '||table_name);
  PERFORM pg_temp.workout_ok(public.read_conversation_workout_effect(u,c,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash')='{"action":"absent"}'::jsonb,'failed transaction cannot acknowledge effect');
 END LOOP;
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)->>'action'='committed','one same-identity retry after rollback commits once');
 before_state:=pg_temp.workout_fingerprint(u);x:=public.reconcile_conversation_workout(u,c,s#>>'{context,input_hash}',e);
 PERFORM pg_temp.workout_ok(x#>>'{current,status}'='present' AND pg_temp.workout_fingerprint(u)=before_state,'reconciliation has no physical writes');
END $rollback$;
DO $media$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000060';foreign_u uuid:='139c0000-0000-4000-8000-000000000061';e uuid:=gen_random_uuid();c uuid;asset uuid:=gen_random_uuid();s jsonb;p jsonb;x jsonb;input jsonb;code text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-media@example.invalid','active','UTC','BR',true),(foreign_u,'workout-media-foreign@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(asset,u,'audio_note','audio-notes',u::text||'/'||asset||'.mp3','audio/mpeg',1200,1200,'processed',repeat('f',64),repeat('e',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),'{"text":"Fiz 30 minutos de caminhada."}');
 c:=gen_random_uuid();input:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',c,'kind','workout.report','source',jsonb_build_object('channel','media','media_asset_id',asset,'user_action','register_performed_workout'));
 x:=public.admit_conversation_workout_command(u,e,input);s:=public.capture_conversation_workout_source(u,c,x#>>'{command,input_hash}',e);p:=pg_temp.workout_prepare(s);
 PERFORM pg_temp.workout_ok(p#>>'{prepared,status}'='ready' AND p#>>'{prepared,evidence,0,unit}'='media_transcript','actual owned processed audio transcript is performed proof');
 UPDATE public.media_assets SET processing_result='{"text":"Vou caminhar amanha."}' WHERE id=asset;
 PERFORM pg_temp.workout_ok(pg_temp.workout_commit(s,p)->>'action'='source_conflict' AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'processed media drift fenced before effect');
 UPDATE public.media_assets SET user_id=foreign_u,object_path=foreign_u::text||'/'||asset||'.mp3' WHERE id=asset;
 BEGIN PERFORM pg_temp.workout_commit(s,p);EXCEPTION WHEN SQLSTATE '40001' THEN code:=SQLSTATE;END;
 PERFORM pg_temp.workout_ok(code='40001','foreign media revocation refuses write');
 UPDATE public.media_assets SET user_id=u,object_path=u::text||'/'||asset||'.jpg',kind='gym_photo',bucket_id='gym-photos',mime_type='image/jpeg',processing_result='{"equipment":["esteira"]}' WHERE id=asset;
 c:=gen_random_uuid();input:=jsonb_set(input,'{command_id}',to_jsonb(c));x:=public.admit_conversation_workout_command(u,e,input);s:=public.capture_conversation_workout_source(u,c,x#>>'{command,input_hash}',e);p:=pg_temp.workout_prepare(s);
 PERFORM pg_temp.workout_ok(p#>>'{prepared,status}'='needs_reply' AND pg_temp.workout_commit(s,p)->>'action'='not_ready','equipment photograph and client intent alone never performed proof');
END $media$;
DO $source_drift$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000080';e uuid:=gen_random_uuid();c uuid:=gen_random_uuid();s jsonb;p jsonb;x jsonb;mode text;denied boolean;code text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'workout-source-drift@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());s:=pg_temp.workout_seed(u,c);p:=pg_temp.workout_prepare(s);
 FOREACH mode IN ARRAY ARRAY['profile','config','catalogue','catalogue_future'] LOOP
  denied:=false;code:=NULL;
  BEGIN
   IF mode='profile' THEN INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(u,80);
   ELSIF mode='config' THEN UPDATE public.global_config SET value='7701' WHERE key='calc.kcal_block';
   ELSIF mode='catalogue' THEN UPDATE public.workout_types SET display_name=display_name||' synthetic change',updated_at=clock_timestamp() WHERE slug='caminhada';
   ELSE UPDATE public.workout_types SET updated_at=clock_timestamp()+interval '1 hour' WHERE slug='caminhada';END IF;
   BEGIN x:=pg_temp.workout_commit(s,p);EXCEPTION WHEN SQLSTATE '55000' THEN code:=SQLSTATE;END;
   denied:=x->>'action'='source_conflict' OR code='55000';
   RAISE EXCEPTION 'rollback source drift fixture' USING ERRCODE='P1392';
  EXCEPTION WHEN SQLSTATE 'P1392' THEN NULL;END;
  PERFORM pg_temp.workout_ok(denied AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'fresh before-write source refuses '||mode);
 END LOOP;
END $source_drift$;
-- The reader's scalar latch must also change when membership/detail changes
-- but known partial sum, coverage and training_done remain exactly identical.
DO $freshness$
DECLARE n integer;u uuid;snap uuid;first_id uuid;before_stamp timestamptz;after_stamp timestamptz;k integer;
BEGIN
 FOR n IN 0..1 LOOP
  u:=('139c0000-0000-4000-8000-'||lpad((90+n)::text,12,'0'))::uuid;k:=CASE WHEN n=0 THEN NULL ELSE 0 END;
  INSERT INTO public.users(id,email,status,timezone) VALUES(u,'workout-freshness-'||n||'@example.invalid','active','UTC');
  INSERT INTO public.daily_snapshots(user_id,date) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date) RETURNING id INTO snap;
  INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) VALUES(u,snap,'caminhada',30,k,clock_timestamp()) RETURNING id INTO first_id;
  SELECT updated_at INTO before_stamp FROM public.daily_snapshots WHERE id=snap;
  INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) VALUES(u,snap,'caminhada',30,k,clock_timestamp());
  SELECT updated_at INTO after_stamp FROM public.daily_snapshots WHERE id=snap;
  PERFORM pg_temp.workout_ok(after_stamp>before_stamp AND (SELECT exercise_calories=0 AND exercise_energy_complete=(n=1) AND training_done FROM public.daily_snapshots WHERE id=snap),'second equal-energy row advances snapshot latch for NULL/zero mode '||n);
  before_stamp:=after_stamp;UPDATE public.workout_logs SET duration_min=31 WHERE id=first_id;
  SELECT updated_at INTO after_stamp FROM public.daily_snapshots WHERE id=snap;
  PERFORM pg_temp.workout_ok(after_stamp>before_stamp,'duration-only update advances scalar version without energy change mode '||n);
  before_stamp:=after_stamp;DELETE FROM public.workout_logs WHERE id=first_id;
  PERFORM pg_temp.workout_ok((SELECT updated_at>before_stamp AND exercise_calories=0 AND training_done FROM public.daily_snapshots WHERE id=snap),'row removal advances version while same aggregate remains mode '||n);
  PERFORM pg_temp.workout_ok(NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.product_events WHERE user_id=u),'freshness stamps grant no XP/block/event mode '||n);
 END LOOP;
END $freshness$;
DO $v2_guard$
DECLARE message text;
BEGIN
 BEGIN PERFORM private.assert_registration_feedback_v2_sources('{"day":{}}','{"snapshot":{"exercise_energy_complete":false}}');EXCEPTION WHEN SQLSTATE '22023' THEN GET STACKED DIAGNOSTICS message=MESSAGE_TEXT;END;
 PERFORM pg_temp.workout_ok(message='feedback_v2_day_energy_unavailable','new numeric v2 day seal refuses unknown coverage before any publication');
END $v2_guard$;
SET LOCAL ROLE anon;
DO $$ DECLARE denied boolean:=false;BEGIN
 BEGIN PERFORM public.read_conversation_workout_preparation(gen_random_uuid(),gen_random_uuid(),repeat('a',64),gen_random_uuid());EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'anonymous_workout_rpc_was_allowed';END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ DECLARE denied boolean:=false;BEGIN
 BEGIN PERFORM public.admit_conversation_workout_command(gen_random_uuid(),gen_random_uuid(),'{}');EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'authenticated_workout_rpc_was_allowed';END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 IF public.read_conversation_workout_preparation(gen_random_uuid(),gen_random_uuid(),repeat('a',64),gen_random_uuid()) IS DISTINCT FROM '{"action":"absent"}'::jsonb THEN RAISE EXCEPTION 'trusted_workout_read_unavailable';END IF;
END $$;
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS workout_atomic_assertions FROM workout_assertions;
SELECT jsonb_build_object('provenance','Actual owned synthetic PostgreSQL atomic core under rollback; no HTTP/native/provider', 'workout_actual_golden',jsonb_agg(jsonb_build_object('kind',kind,'source',source,'preparation',preparation,'effect',effect) ORDER BY kind)) FROM workout_actual_golden;
ROLLBACK;

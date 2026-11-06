-- Run in the owned rollback transaction AFTER T44 and BEFORE T49.
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE workout_parity_legacy(kind text PRIMARY KEY,source jsonb,report jsonb,preparation jsonb,receipt jsonb,row_before jsonb,read_before jsonb);
CREATE TEMP TABLE workout_parity_before_bodies AS
 SELECT oid::regprocedure::text AS signature,prosrc,proacl FROM pg_proc WHERE oid IN(
 'private.conversation_workout_report(jsonb,text)'::regprocedure,
 'public.prepare_conversation_workout(uuid,uuid,text,text,uuid,jsonb)'::regprocedure,
 'public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure);
CREATE FUNCTION pg_temp.parity_seed(t text,weight numeric DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();id uuid:=gen_random_uuid();a jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'t49-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 IF weight IS NOT NULL THEN INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(u,weight);END IF;
 a:=public.admit_conversation_workout_command(u,e,jsonb_build_object('command_protocol','conversation.command.v1','command_id',id,'kind','workout.report','source',jsonb_build_object('channel','text','text',t)));
 IF a->>'action'<>'admitted' THEN RAISE EXCEPTION 'parity_fixture_admission';END IF;
 RETURN public.capture_conversation_workout_source(u,id,a#>>'{command,input_hash}',e);
END $$;
DO $before$
DECLARE kind text;t text;s jsonb;r jsonb;p jsonb;q jsonb;u uuid;id uuid;e uuid;
BEGIN
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.conversation_workout_preparations'::regclass AND attname='report_version' AND NOT attisdropped) THEN RAISE EXCEPTION 'parity_fixture_requires_pre_upgrade';END IF;
 FOR kind,t IN SELECT * FROM (VALUES('ready','Fiz 30 minutos de caminhada.'),('duration','Fiz caminhada'),('natural','Caminhei30min'),('saved','Fiz 30 minutos de caminhada moderada.')) x(k,t) LOOP
  s:=pg_temp.parity_seed(t,CASE WHEN kind='saved' THEN 80 ELSE NULL END);
  u:=(s#>>'{context,owner_id}')::uuid;id:=(s#>>'{context,command_id}')::uuid;e:=(s#>>'{context,epoch}')::uuid;
  r:=private.conversation_workout_report(s->'context',s->>'source_hash');
  p:=public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r);
  IF p->>'action'<>'prepared' THEN RAISE EXCEPTION 'parity_fixture_preparation';END IF;
  q:=NULL;
  IF kind='saved' THEN q:=public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared');IF q->>'action'<>'committed' THEN RAISE EXCEPTION 'parity_fixture_commit';END IF;END IF;
  INSERT INTO workout_parity_legacy SELECT kind,s,r,p,q,to_jsonb(x),public.read_conversation_workout_preparation(u,id,s#>>'{context,input_hash}',e)
   FROM private.conversation_workout_preparations x WHERE x.user_id=u AND x.command_id=id;
 END LOOP;
END $before$;

-- Same actual T39/T41/T44 admission/capture/selection path as the qualified media suite.
CREATE FUNCTION pg_temp.parity_media(caption text,context text,transcript text,k text DEFAULT 'audio_note') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();m uuid:=gen_random_uuid();raw jsonb;a jsonb;s jsonb;claim jsonb;selected jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'t49-media-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,context_text,processing_result)
 VALUES(m,u,k,CASE WHEN k='audio_note' THEN 'audio-notes' ELSE 'gym-photos' END,u||'/'||m||'.bin',CASE WHEN k='audio_note' THEN 'audio/mpeg' ELSE 'image/jpeg' END,1200,1200,'processed',repeat('a',64),repeat('b',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),context,
 CASE WHEN k='audio_note' THEN jsonb_build_object('text',transcript) ELSE '{"equipment":[{"name":"esteira"}]}'::jsonb END);
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_strip_nulls(jsonb_build_object('channel','media','media_asset_id',m,'user_action','report_actual_record','caption',caption)));
 a:=public.admit_conversation_intake(u,e,raw);s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
 claim:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');
 selected:=public.seal_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash',(claim->>'claim_id')::uuid,'{"schema":"conversation.intake-routing.v1","kind":"workout.report","reason":"processed_media_report"}');
 IF selected->>'action'<>'sealed' THEN RAISE EXCEPTION 'parity_fixture_media_selection';END IF;
 RETURN public.capture_conversation_workout_source(u,(selected#>>'{selection,command,command_id}')::uuid,selected#>>'{selection,command,input_hash}',e);
END $$;

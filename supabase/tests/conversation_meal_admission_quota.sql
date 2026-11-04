-- Real local PG: new-admission cost fence before source/provider preparation.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
CREATE FUNCTION pg_temp.quota_input(id uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('command_protocol','conversation.command.v1','command_id',id,'kind','meal.report',
 'source',jsonb_build_object('channel','text','text','Sonhei com arroz sintetico'));
$$;
CREATE FUNCTION pg_temp.quota_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'QUOTA_FAIL:%',label;END IF;RAISE NOTICE 'QUOTA_PASS:%',label;END $$;
DO $quota$
DECLARE u uuid:='c3fa0000-0000-4000-8000-000000000001';other_id uuid:='c3fa0000-0000-4000-8000-000000000002';
 epoch uuid:='c3fa0000-0000-4000-8000-000000000003';other_epoch uuid:='c3fa0000-0000-4000-8000-000000000004';
 first_id uuid:='c3fa0000-0000-4000-8000-000000000101';rejected uuid:='c3fa0000-0000-4000-8000-000000000111';
 new_id uuid;v jsonb;first_winner jsonb;before_replay jsonb;next_epoch uuid;
BEGIN
 PERFORM pg_temp.quota_ok(NOT EXISTS(SELECT 1 FROM public.users WHERE id IN(u,other_id)),'synthetic namespace empty');
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'quota-a@example.invalid','active','UTC'),(other_id,'quota-b@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,epoch,clock_timestamp()),(other_id,other_epoch,clock_timestamp());
 FOR i IN 101..110 LOOP
  new_id:=('c3fa0000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid;
  v:=public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(new_id),epoch);
  PERFORM pg_temp.quota_ok(v->>'action'='admitted','fresh slot '||(i-100)::text);
  IF i=101 THEN first_winner:=v; END IF;
 END LOOP;
 v:=public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(rejected),epoch);
 -- This is the RED assertion against the pre-quota fenced admission.
 PERFORM pg_temp.quota_ok(v='{"action":"rate_limited"}'::jsonb,'eleventh fresh command is rate limited');
 PERFORM pg_temp.quota_ok((SELECT count(*)=10 FROM private.conversation_meal_command_ids WHERE user_id=u)
  AND (SELECT count(*)=10 FROM private.conversation_meal_command_sources WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=rejected),'refused command has no identity or personal source');
 SELECT jsonb_agg(to_jsonb(c) ORDER BY command_id) INTO before_replay FROM private.conversation_meal_command_ids c WHERE user_id=u;
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(first_id),epoch)=jsonb_set(first_winner,'{action}','"replay"')
  AND (SELECT jsonb_agg(to_jsonb(c) ORDER BY command_id)=before_replay FROM private.conversation_meal_command_ids c WHERE user_id=u),'same UUID at cap replays original without mutation');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(first_id)||'{"meal_type":"jantar"}',epoch)='{"action":"input_conflict"}'::jsonb,'changed input conflicts before quota');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(rejected),other_epoch)='{"action":"stale_epoch"}'::jsonb,'expected epoch fence before quota');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(other_id,pg_temp.quota_input(rejected),other_epoch)->>'action'='admitted','owner quota isolated');
 PERFORM pg_temp.quota_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_semantic_attempts WHERE user_id IN(u,other_id))
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_source_captures WHERE user_id IN(u,other_id))
  AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id IN(u,other_id))
  AND NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE user_id IN(u,other_id))
  AND NOT EXISTS(SELECT 1 FROM public.messages WHERE user_id IN(u,other_id))
  AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id IN(u,other_id)),'including negative intents consumes admission quota before any provider domain or progress');
 PERFORM public.reset_user_conversation_atomic(u,true);
 SELECT a.epoch INTO next_epoch FROM private.workout_strength_authority_epochs a WHERE user_id=u;
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(first_id),next_epoch)='{"action":"stale_epoch"}'::jsonb,'old tombstone before empty new epoch quota');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(rejected),epoch)='{"action":"stale_epoch"}'::jsonb,'unadmitted offline intent still cannot retag');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(rejected),next_epoch)->>'action'='admitted','new epoch counts only its own admitted identities');
END $quota$;

DO $window$
DECLARE u uuid:='c3fa0000-0000-4000-8000-000000000021';epoch uuid:='c3fa0000-0000-4000-8000-000000000022';
 old_id uuid:='c3fa0000-0000-4000-8000-000000000023';new_id uuid;raw jsonb;v jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'quota-window@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,epoch,clock_timestamp());
 raw:=pg_temp.quota_input(old_id);
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
 VALUES(u,old_id,encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex'),'conversation.command.v1','meal.report',epoch,clock_timestamp()-interval '61 seconds');
 INSERT INTO private.conversation_meal_command_sources VALUES(u,old_id,raw);
 FOR i IN 201..210 LOOP
  new_id:=('c3fa0000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid;
  v:=public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input(new_id),epoch);
  PERFORM pg_temp.quota_ok(v->>'action'='admitted','rolling window fresh slot '||(i-200)::text);
 END LOOP;
 PERFORM pg_temp.quota_ok((SELECT count(*)=11 FROM private.conversation_meal_command_ids WHERE user_id=u),'aged identity outside window does not consume slot');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,pg_temp.quota_input('c3fa0000-0000-4000-8000-000000000211'),epoch)='{"action":"rate_limited"}'::jsonb,'rolling window caps recent ten');
 PERFORM pg_temp.quota_ok(public.admit_conversation_meal_command_fenced(u,raw,epoch)->>'action'='replay','aged UUID also replays at full quota');
END $window$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

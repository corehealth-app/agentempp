-- Real local PostgreSQL only. All synthetic rows roll back; no lifecycle init.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN
 IF to_regprocedure('public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)') IS NULL THEN
  RAISE EXCEPTION 'FENCE_RED:missing_fenced_admission'; END IF;
END $$;
CREATE FUNCTION pg_temp.fence_ok(value boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'FENCE_FAIL:%',label;END IF;
 RAISE NOTICE 'FENCE_PASS:%',label;END $$;
DO $cases$
DECLARE
 a uuid:='c3fe0000-0000-4000-8000-000000000001';b uuid:='c3fe0000-0000-4000-8000-000000000002';
 missing uuid:='c3fe0000-0000-4000-8000-000000000003';
 epoch_a uuid:='c3fe0000-0000-4000-8000-000000000004';epoch_b uuid:='c3fe0000-0000-4000-8000-000000000005';
 cid uuid:='c3fe0000-0000-4000-8000-000000000006';offline uuid:='c3fe0000-0000-4000-8000-000000000007';
 fresh uuid:='c3fe0000-0000-4000-8000-000000000008';aged uuid:='c3fe0000-0000-4000-8000-000000000009';
 new_epoch uuid;raw jsonb;old_raw jsonb;v jsonb;before_state jsonb;refused boolean;
BEGIN
 PERFORM pg_temp.fence_ok(NOT EXISTS(SELECT 1 FROM public.users WHERE id IN(a,b,missing)),'synthetic namespace empty');
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES
  (a,'admission-fence-a@example.invalid','active','UTC','BR',true),
  (b,'admission-fence-b@example.invalid','active','UTC','BR',true),
  (missing,'admission-fence-no-epoch@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(a,epoch_a,clock_timestamp()),(b,epoch_b,clock_timestamp());
 raw:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',cid,'kind','meal.report','source',jsonb_build_object('channel','text','text','Comi arroz 100g sintetico'));
 PERFORM pg_temp.fence_ok(NOT has_function_privilege('anon','public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)','EXECUTE')
  AND has_function_privilege('service_role','public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)','EXECUTE'),'service-only ACL');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);refused:=false;
 BEGIN PERFORM public.admit_conversation_meal_command_fenced(a,raw,epoch_a);EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
 PERFORM pg_temp.fence_ok(refused,'untrusted JWT denied even postgres transport');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw,NULL)='{"action":"stale_epoch"}'::jsonb,'missing original epoch refuses');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw,epoch_b)='{"action":"stale_epoch"}'::jsonb,'foreign epoch refuses');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(missing,raw,epoch_a)='{"action":"stale_epoch"}'::jsonb,'no epoch refuses without initializing');
 PERFORM pg_temp.fence_ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=missing)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id IN(a,missing)),'refusals create no epoch or command');
 v:=public.admit_conversation_meal_command_fenced(a,raw,epoch_a);
 PERFORM pg_temp.fence_ok(v->>'action'='admitted' AND v#>>'{command,epoch}'=epoch_a::text,'matching original epoch admits');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw,epoch_a)->>'action'='replay','matching epoch replay');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw||'{"meal_type":"jantar"}',epoch_a)='{"action":"input_conflict"}'::jsonb,'same UUID changed input conflicts');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw,epoch_b)='{"action":"stale_epoch"}'::jsonb,'existing current command never bypasses requested fence');
 -- Insert a past synthetic identity without mutating the immutable live identity.
 old_raw:=raw||jsonb_build_object('command_id',aged);
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
 VALUES(a,aged,encode(sha256(convert_to(private.conversation_command_canonical(old_raw),'UTF8')),'hex'),'conversation.command.v1','meal.report',epoch_a,clock_timestamp()-interval '48 hours');
 INSERT INTO private.conversation_meal_command_sources(user_id,command_id,source_input) VALUES(a,aged,old_raw);
 before_state:=(SELECT to_jsonb(c) FROM private.conversation_meal_command_ids c WHERE user_id=a AND command_id=aged);
 v:=public.admit_conversation_meal_command_fenced(a,old_raw,epoch_a);
 PERFORM pg_temp.fence_ok(v->>'action'='replay' AND (v#>>'{command,admitted_at}')::timestamptz<clock_timestamp()-interval '24 hours'
  AND (SELECT to_jsonb(c)=before_state FROM private.conversation_meal_command_ids c WHERE user_id=a AND command_id=aged),'48h replay keeps permanent identity');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(b,raw,epoch_b)->>'action'='admitted','same UUID other owner isolated');
 PERFORM pg_temp.fence_ok((SELECT count(*)=0 FROM public.pending_registrations WHERE user_id IN(a,b,missing))
  AND (SELECT count(*)=0 FROM public.meal_logs WHERE user_id IN(a,b,missing))
  AND (SELECT count(*)=0 FROM public.messages WHERE user_id IN(a,b,missing))
  AND (SELECT count(*)=0 FROM public.user_progress WHERE user_id IN(a,b,missing)),'admit/replay initializes no domain or progress');
 PERFORM public.reset_user_conversation_atomic(a,true);
 SELECT epoch INTO new_epoch FROM private.workout_strength_authority_epochs WHERE user_id=a;
 PERFORM pg_temp.fence_ok(new_epoch IS DISTINCT FROM epoch_a,'actual reset rotates epoch');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw,new_epoch)='{"action":"stale_epoch"}'::jsonb,'old command tombstone wins even current requested epoch');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw||'{"meal_type":"jantar"}',new_epoch)='{"action":"stale_epoch"}'::jsonb,'old tombstone before changed valid input');
 PERFORM pg_temp.fence_ok((SELECT invalidated_at IS NOT NULL AND epoch=epoch_a FROM private.conversation_meal_command_ids WHERE user_id=a AND command_id=cid)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_sources WHERE user_id=a AND command_id=cid),'reset identity preserved and personal source scrubbed');
 v:=public.admit_conversation_meal_command_fenced(a,raw||jsonb_build_object('command_id',offline),epoch_a);
 PERFORM pg_temp.fence_ok(v='{"action":"stale_epoch"}'::jsonb AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=a AND command_id=offline),'never-admitted offline intent cannot be retagged automatically after reset');
 PERFORM pg_temp.fence_ok(public.admit_conversation_meal_command_fenced(a,raw||jsonb_build_object('command_id',fresh),new_epoch)->>'action'='admitted','separate fresh current-epoch intent admits');
 refused:=false;BEGIN PERFORM public.admit_conversation_meal_command_fenced(a,raw||'{"unexpected":true}',new_epoch);EXCEPTION WHEN invalid_parameter_value THEN refused:=true;END;
 PERFORM pg_temp.fence_ok(refused,'strict DTO unknown keys reject');
 PERFORM pg_temp.fence_ok((SELECT count(*)=3 FROM private.conversation_meal_command_ids WHERE user_id=a),'no extra rejected command identity');
END $cases$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE refused boolean:=false;BEGIN
 BEGIN PERFORM public.admit_conversation_meal_command_fenced('c3fe0000-0000-4000-8000-000000000001','{"command_protocol":"conversation.command.v1","command_id":"c3fe0000-0000-4000-8000-000000000006","kind":"meal.report","source":{"channel":"text","text":"Sintetico"}}','c3fe0000-0000-4000-8000-000000000004');
 EXCEPTION WHEN invalid_parameter_value THEN refused:=true;END;
 IF NOT refused THEN RAISE EXCEPTION 'FENCE_FAIL:repeatable read accepted';END IF;RAISE NOTICE 'FENCE_PASS:repeatable read refused';END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE refused boolean:=false;BEGIN
 BEGIN PERFORM public.admit_conversation_meal_command_fenced('c3fe0000-0000-4000-8000-000000000001','{"command_protocol":"conversation.command.v1","command_id":"c3fe0000-0000-4000-8000-000000000006","kind":"meal.report","source":{"channel":"text","text":"Sintetico"}}','c3fe0000-0000-4000-8000-000000000004');
 EXCEPTION WHEN invalid_parameter_value THEN refused:=true;END;
 IF NOT refused THEN RAISE EXCEPTION 'FENCE_FAIL:serializable accepted';END IF;RAISE NOTICE 'FENCE_PASS:serializable refused';END $$;
ROLLBACK;

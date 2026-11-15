-- Current v2 state and Flow discovery are observational; fixture and effects roll back.
BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;a jsonb;x jsonb;c jsonb;h jsonb;original_epoch_count bigint;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 SELECT count(*) INTO original_epoch_count FROM private.workout_strength_authority_epochs;
 a:=public.read_training_execution_state_v2_authenticated(f.owner_id,f.auth_id,f.login_id,f.session_id);
 ASSERT a->>'action'='progress' AND a#>>'{session,schema}'='training.execution.v1';
 ASSERT a#>>'{session,phase}'='in_progress';
 h:=public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,NULL);
 ASSERT jsonb_array_length(h->'sessions')=1 AND h#>>'{sessions,0,phase}'='in_progress';
 ASSERT h#>'{sessions,0,completion}'='null'::jsonb;
 ASSERT NOT EXISTS(SELECT 1 FROM private.training_execution_completions WHERE user_id=f.owner_id);
 x:=pg_temp.prepare_training_finish();
 a:=public.read_training_execution_state_v2_authenticated(f.owner_id,f.auth_id,f.login_id,f.session_id);
 ASSERT a->>'action'='completion' AND a#>>'{context,completion,status}'='reserved','a second device sees the exact reservation';
 ASSERT NOT EXISTS(SELECT 1 FROM private.conversation_journal_events_v3(f.owner_id,f.epoch) WHERE command_id=f.completion_id),
  'a training reservation is not yet a performed activity in Flow';
 c:=pg_temp.commit_training_finish(x);ASSERT c->>'action'='committed';
 a:=public.read_training_execution_state_v2_authenticated(f.owner_id,f.auth_id,f.login_id,f.session_id);
 ASSERT a->>'action'='completion' AND a#>>'{context,completion,status}'='completed';
 ASSERT a#>>'{context,session,schema}'='training.execution.v2' AND a#>>'{context,session,phase}'='completed';
 ASSERT a#>'{context,completion,receipt,workout}'=c->'receipt';
 h:=public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,NULL);
 ASSERT h#>>'{sessions,0,phase}'='completed' AND h#>>'{sessions,0,completion,status}'='completed';
 ASSERT h#>>'{sessions,0,completion,id}'=f.completion_id::text;
 ASSERT jsonb_array_length(public.read_training_execution_home_authenticated(f.owner_id,f.auth_id,f.login_id,NULL)->'sessions')=0,
  'old v1 resumption remains literal and does not silently decode completed v2';
 ASSERT (SELECT count(*) FROM private.conversation_journal_events_v3(f.owner_id,f.epoch) WHERE command_id=f.completion_id)=1,
  'the actual completed workout is discoverable exactly once in Flow';
 UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=f.owner_id;
 a:=public.read_training_execution_state_v2_authenticated(f.owner_id,f.auth_id,f.login_id,f.session_id);
 ASSERT a#>>'{context,completion,status}'='completed','closed day history remains an observation';
 h:=public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,NULL);
 ASSERT h#>'{sessions,0,day_closed}'='true'::jsonb AND h#>>'{sessions,0,phase}'='completed','closed history stays visible';
 ASSERT (SELECT count(*) FROM private.workout_strength_authority_epochs)=original_epoch_count,'reads mint no lifecycle';
 ASSERT NOT has_function_privilege('authenticated','public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid)','EXECUTE');
 RAISE NOTICE 'R140_CURRENT_STATE_AND_FLOW_COMPLETED_DISCOVERY_PASS';
END $test$;
ROLLBACK;

-- Cancellation is observational to Flow and releases the original execution.
BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;x jsonb;a jsonb;h jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 x:=pg_temp.prepare_training_finish();
 a:=public.cancel_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,x#>>'{begin,completion,input_hash}');
 ASSERT a->>'action'='cancelled' AND a#>>'{receipt,schema}'='training.execution-finish-cancelled.v1';
 ASSERT NOT EXISTS(SELECT 1 FROM private.conversation_journal_events_v3(f.owner_id,f.epoch) WHERE command_id=f.completion_id),
  'cancelled reservations must never be presented as performed activities';
 h:=public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,NULL);
 ASSERT h#>>'{sessions,0,phase}'='in_progress' AND h#>'{sessions,0,completion}'='null'::jsonb;
 a:=public.read_training_execution_state_v2_authenticated(f.owner_id,f.auth_id,f.login_id,f.session_id);
 ASSERT a->>'action'='progress' AND a#>>'{session,revision}'='0';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id);
 RAISE NOTICE 'R140_CANCELLED_RESERVATION_NO_FLOW_EFFECT_PASS';
END $test$;
ROLLBACK;

-- Stable keyset pages include terminal history, bind owner/epoch/zone and do
-- not initialize a lifecycle or leak a second account's execution.
BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;h jsonb;h2 jsonb;s jsonb;sid uuid;i integer;bad jsonb;seen integer;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 SELECT state INTO s FROM private.training_execution_sessions WHERE user_id=f.owner_id AND session_id=f.session_id;
 FOR i IN 1..22 LOOP
  sid:=('140e0000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid;
  INSERT INTO private.training_execution_sessions(user_id,session_id,epoch,revision,state)
   VALUES(f.owner_id,sid,f.epoch,0,s||jsonb_build_object('id',sid,'phase',CASE WHEN i%2=0 THEN 'abandoned' ELSE 'in_progress' END));
 END LOOP;
 h:=public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,NULL);
 ASSERT jsonb_array_length(h->'sessions')=20 AND h->'next_cursor'<>'null'::jsonb;
 h2:=public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,h->'next_cursor');
 ASSERT jsonb_array_length(h2->'sessions')=3 AND h2->'next_cursor'='null'::jsonb;
 SELECT count(DISTINCT e->>'id') INTO seen FROM jsonb_array_elements((h->'sessions')||(h2->'sessions')) e;
 ASSERT seen=23,'stable equal-clock pages must neither omit nor duplicate an execution';
 ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(h->'sessions') e WHERE e->>'phase'='abandoned');
 FOREACH bad IN ARRAY ARRAY[
  (h->'next_cursor')||'{"owner_id":"140e0000-0000-4000-8000-000000000099"}',
  (h->'next_cursor')||'{"epoch":"140e0000-0000-4000-8000-000000000099"}',
  (h->'next_cursor')||'{"time_zone":"UTC"}',
  (h->'next_cursor')||'{"extra":true}',
  (h->'next_cursor')- 'session_id'
 ] LOOP
  BEGIN
   PERFORM public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,f.login_id,bad);
   RAISE EXCEPTION 'R140 altered cursor accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;END;
 END LOOP;
 BEGIN
  PERFORM public.read_training_execution_state_v2_authenticated(f.owner_id,'140e0000-0000-4000-8000-000000000099',f.login_id,f.session_id);
  RAISE EXCEPTION 'R140 changed Auth accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM public.read_training_execution_home_v2_authenticated(f.owner_id,f.auth_id,'140e0000-0000-4000-8000-000000000099',NULL);
  RAISE EXCEPTION 'R140 changed login accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT NOT has_function_privilege('authenticated','public.read_training_execution_home_v2_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('anon','public.read_training_execution_home_v2_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 RAISE NOTICE 'R140_HISTORY_PAGINATION_SCOPE_AND_ACL_PASS';
END $test$;
ROLLBACK;

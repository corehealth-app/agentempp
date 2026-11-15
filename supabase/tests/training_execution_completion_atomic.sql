-- Real protected primitives; every group rolls back its synthetic account.
BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;v jsonb;again jsonb;cancelled jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 v:=public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'status'='saved' AND v#>>'{completion,completion,status}'='completed';
 ASSERT v#>'{effect,receipt}'=v#>'{completion,completion,receipt,workout}';
 ASSERT v#>>'{effect,receipt,activity,duration_min}'='30';
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=1;
 ASSERT (SELECT count(*) FROM private.training_execution_completion_events WHERE user_id=f.owner_id AND kind='completed')=1;
 again:=public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT again->'effect'=v->'effect','replay must return original physical effect';
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=1;
 cancelled:=public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT cancelled#>>'{completion,completion,status}'='completed','completed effect wins late withdrawal';
 ASSERT NOT has_function_privilege('anon','public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 RAISE NOTICE 'ATOMIC_SAVED_REPLAY_LATE_CANCEL_ACL_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
CREATE FUNCTION pg_temp.expire_atomic_finish_login() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second'
 WHERE id='139d0000-0000-4000-8000-000000000005';
 RETURN NEW;
END $$;
CREATE TRIGGER qa_atomic_expiry BEFORE INSERT ON public.workout_logs
 FOR EACH ROW EXECUTE FUNCTION pg_temp.expire_atomic_finish_login();
DO $test$
DECLARE f record;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'expiry inside original writer was accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 ASSERT (SELECT count(*) FROM private.training_execution_completions WHERE user_id=f.owner_id)=0;
 ASSERT (SELECT count(*) FROM private.conversation_workout_command_ids WHERE user_id=f.owner_id)=0;
 RAISE NOTICE 'ATOMIC_EXPIRY_DURING_WRITER_ROLLS_BACK_RESERVATION_AND_EFFECT_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;c jsonb;v jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 c:=public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 PERFORM public.cancel_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,c#>>'{completion,input_hash}');
 v:=public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'status'='cancelled' AND v#>>'{completion,completion,status}'='cancelled';
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 RAISE NOTICE 'ATOMIC_EXISTING_CANCELLED_RECEIPT_NO_EFFECT_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;v jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 PERFORM public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'withdrawn operation was written';
 EXCEPTION WHEN serialization_failure THEN ASSERT SQLERRM='training_completion_withdrawn';END;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 ASSERT (SELECT count(*) FROM private.training_execution_completions WHERE user_id=f.owner_id)=0;
 RAISE NOTICE 'ATOMIC_WITHDRAWAL_FENCE_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;v jsonb;c jsonb;text_value text;op uuid;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 FOREACH text_value IN ARRAY ARRAY['Fiz full body.','Amanhã farei full body por 30 min.'] LOOP
  op:=gen_random_uuid();c:=jsonb_set(jsonb_set(f.command,'{operation_id}',to_jsonb(op::text)),'{source,text}',to_jsonb(text_value));
  v:=public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,c);
  ASSERT v->>'status'='decision' AND v#>>'{completion,completion,status}'='reserved';
  ASSERT v#>>'{preparation,prepared,status}'=CASE WHEN text_value='Fiz full body.' THEN 'needs_reply' ELSE 'not_reported' END;
  PERFORM public.cancel_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,op,v#>>'{completion,completion,input_hash}');
 END LOOP;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 RAISE NOTICE 'ATOMIC_MISSING_DURATION_FUTURE_NO_WORKOUT_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated(f.owner_id,'14500000-0000-4000-8000-000000000088',f.login_id,f.command);
  RAISE EXCEPTION 'foreign identity accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,jsonb_set(f.command,'{expected_revision}','1'));
  RAISE EXCEPTION 'stale revision accepted';
 EXCEPTION WHEN serialization_failure THEN NULL;END;
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id=f.login_id;
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'expired original session accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 ASSERT (SELECT count(*) FROM private.training_execution_completions WHERE user_id=f.owner_id)=0;
 RAISE NOTICE 'ATOMIC_IDENTITY_REVISION_EXPIRED_SESSION_PASS';
END $test$;
ROLLBACK;

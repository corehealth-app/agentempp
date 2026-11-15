-- The HTTP transport translates conflicts; original functions remain literal.
BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;v jsonb;original jsonb;r record;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 v:=public.read_training_execution_home_authenticated_http(f.owner_id,f.auth_id,f.login_id);
 ASSERT v#>>'{scope,owner_id}'=f.owner_id::text,'v1 default cursor preserved';
 v:=public.submit_training_execution_completion_authenticated_http(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'status'='saved' AND v#>>'{completion,completion,status}'='completed';
 original:=public.read_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id);
 ASSERT original#>'{completion,receipt}'=v#>'{completion,completion,receipt}';
 v:=public.submit_training_execution_completion_authenticated_http(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'status'='saved' AND (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=1;
 v:=public.cancel_training_execution_completion_authenticated_http(f.owner_id,f.auth_id,f.login_id,f.completion_id,v#>>'{completion,completion,input_hash}');
 ASSERT v->>'action'='completed','late cancellation retains the official workout';
 FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname LIKE '%training_execution%_authenticated_http' LOOP
  ASSERT has_function_privilege('service_role',r.oid,'EXECUTE');
  ASSERT NOT has_function_privilege('anon',r.oid,'EXECUTE');
  ASSERT NOT has_function_privilege('authenticated',r.oid,'EXECUTE');
 END LOOP;
 ASSERT (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname LIKE '%training_execution%_authenticated_http')=13;
 RAISE NOTICE 'HTTP_TRANSPORT_DEFAULTS_ACTUAL_EFFECT_REPLAY_CANCEL_ACL_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;v jsonb;changed jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 PERFORM public.withdraw_training_execution_finish_authenticated_http(f.owner_id,f.auth_id,f.login_id,f.command);
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated_http(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'withdrawn HTTP command accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN ASSERT SQLERRM='training_execution_conflict';END;
 -- The guarded original is preserved, including its original error contract.
 BEGIN
  PERFORM public.submit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'withdrawn original command accepted';
 EXCEPTION WHEN serialization_failure THEN ASSERT SQLERRM='training_completion_withdrawn';END;
 changed:=jsonb_set(f.command,'{source,text}','"Fiz full body por 40 min."');
 BEGIN
  PERFORM public.observe_training_execution_finish_authenticated_http(f.owner_id,f.auth_id,f.login_id,changed);
  RAISE EXCEPTION 'changed marker input accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL;END;
 BEGIN
  PERFORM public.read_training_execution_home_authenticated_http(f.owner_id,'14600000-0000-4000-8000-000000000088',f.login_id);
  RAISE EXCEPTION 'foreign identity accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id=f.login_id;
 BEGIN
  PERFORM public.read_training_execution_home_v2_authenticated_http(f.owner_id,f.auth_id,f.login_id);
  RAISE EXCEPTION 'expired original login accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 ASSERT (SELECT count(*) FROM private.training_execution_completions WHERE user_id=f.owner_id)=0;
 RAISE NOTICE 'HTTP_TRANSPORT_NONRETRYABLE_REJECTION_ORIGINAL_AUTH_PRESERVED_PASS';
END $test$;
ROLLBACK;

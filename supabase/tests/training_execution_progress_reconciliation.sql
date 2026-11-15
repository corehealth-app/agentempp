BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;s jsonb;command jsonb;a jsonb;b jsonb;x jsonb;n bigint;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 SELECT state INTO s FROM private.training_execution_sessions WHERE user_id=f.owner_id AND session_id=f.session_id;
 command:=jsonb_build_object('schema','training.execution.start.v1','session_id',f.session_id,'operation_id',f.session_id,
  'expected_epoch',f.epoch,'expected_local_date',s->'local_date','plan_id',s#>'{definition,plan_id}',
  'plan_hash',s#>'{definition,plan_hash}','day_index',s#>'{definition,day_index}');
 SELECT count(*) INTO n FROM private.training_execution_operations;
 a:=public.reconcile_training_execution_progress_authenticated(f.owner_id,f.auth_id,f.login_id,command);
 ASSERT a->>'action'='absent' AND a#>>'{state,action}'='progress';
 ASSERT (SELECT count(*) FROM private.training_execution_operations)=n,'an observation creates no receipt';
 BEGIN
  PERFORM public.reconcile_training_execution_progress_authenticated(f.owner_id,f.auth_id,f.login_id,command||'{"expected_epoch":"14100000-0000-4000-8000-000000000099"}');
  RAISE EXCEPTION 'changed epoch accepted';
 EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN
  PERFORM public.reconcile_training_execution_progress_authenticated(f.owner_id,f.auth_id,f.login_id,command||'{"schema":null}');
  RAISE EXCEPTION 'null schema accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN
  PERFORM public.reconcile_training_execution_progress_authenticated(f.owner_id,f.auth_id,f.login_id,command||'{"calories":900}');
  RAISE EXCEPTION 'extra request authority accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 x:=pg_temp.prepare_training_finish();PERFORM pg_temp.commit_training_finish(x);
 a:=public.reconcile_training_execution_progress_authenticated(f.owner_id,f.auth_id,f.login_id,command);
 ASSERT a->>'action'='absent' AND a#>>'{state,action}'='completion' AND a#>>'{state,context,completion,status}'='completed';
 ASSERT NOT(a?'receipt'),'a completion never becomes a missing progress receipt';
 ASSERT (SELECT count(*) FROM private.training_execution_operations)=n;
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id=f.login_id;
 BEGIN
  PERFORM public.reconcile_training_execution_progress_authenticated(f.owner_id,f.auth_id,f.login_id,command);
  RAISE EXCEPTION 'expired original login accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT NOT has_function_privilege('authenticated','public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('anon','public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 RAISE NOTICE 'R141_READONLY_PROGRESS_RECONCILIATION_SCOPE_AND_ACL_PASS';
END $test$;
ROLLBACK;

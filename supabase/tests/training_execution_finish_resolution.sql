BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;v jsonb;w jsonb;n bigint;changed jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 SELECT count(*) INTO n FROM private.training_execution_completions;
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'action'='absent' AND v#>>'{state,action}'='progress';
 ASSERT v#>>'{request,operation_id}'=f.completion_id::text AND (SELECT count(*) FROM private.training_execution_completions)=n;
 ASSERT (SELECT count(*) FROM private.training_execution_finish_withdrawals)=0,'observe creates no marker';
 w:=public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT w->>'action'='withdrawn' AND w#>>'{withdrawal,input_hash}'=v#>>'{request,input_hash}';
 ASSERT NOT(w->'withdrawal' ? 'source'),'marker stores no accepted report';
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0;
 ASSERT public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command)->'withdrawal'=w->'withdrawal';
 BEGIN
  PERFORM public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'late withdrawn finish accepted';
 EXCEPTION WHEN serialization_failure THEN ASSERT SQLERRM='training_completion_withdrawn';END;
 changed:=jsonb_set(f.command,'{source,text}','"Fiz caminhada por 40 min."');
 BEGIN
  PERFORM public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,changed);
  RAISE EXCEPTION 'changed input reused marker';
 EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN
  PERFORM public.withdraw_training_execution_finish_authenticated(f.owner_id,'14300000-0000-4000-8000-000000000088',f.login_id,f.command);
  RAISE EXCEPTION 'foreign auth accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id=f.login_id;
 BEGIN
  PERFORM public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
  RAISE EXCEPTION 'expired original login accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT NOT has_function_privilege('authenticated','public.observe_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('anon','public.withdraw_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('service_role','private.begin_training_execution_completion_unwithdrawn(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_table_privilege('service_role','private.training_execution_finish_withdrawals','SELECT');
 RAISE NOTICE 'R143_ABSENT_WITHDRAWAL_LATE_BEGIN_INPUT_AUTH_ACL_PASS';
END $test$;
ROLLBACK;

BEGIN;
\ir fixtures/training_execution_completion_seed.sql
DO $test$
DECLARE f record;x jsonb;v jsonb;other jsonb;unknown jsonb;w jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 x:=pg_temp.prepare_training_finish();
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'action'='available' AND v#>>'{completion,completion,status}'='reserved';
 other:=jsonb_set(f.command,'{operation_id}','"14300000-0000-4000-8000-000000000099"');
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,other);
 ASSERT v->>'action'='absent' AND v#>>'{state,context,completion,status}'='reserved';
 v:=public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v->>'action'='available' AND v#>>'{completion,completion,status}'='cancelled';
 BEGIN
  PERFORM pg_temp.commit_training_finish(x);
  RAISE EXCEPTION 'cancelled callback accepted';
 EXCEPTION WHEN serialization_failure THEN ASSERT SQLERRM='training_completion_cancelled';END;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=0,'cancelled callback creates no workout';
 UPDATE finish_fixture SET completion_id=(other->>'operation_id')::uuid,command=other;
 x:=pg_temp.prepare_training_finish();PERFORM pg_temp.commit_training_finish(x);
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT v#>>'{completion,completion,status}'='cancelled' AND v#>>'{state,context,completion,status}'='completed';
 v:=public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,other);
 ASSERT v->>'action'='available' AND v#>>'{completion,completion,status}'='completed','completion wins late cancellation';
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=1;
 unknown:=jsonb_set(other,'{operation_id}','"14300000-0000-4000-8000-000000000098"');
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,unknown);
 ASSERT v->>'action'='absent' AND v#>>'{state,context,completion,status}'='completed';
 ASSERT (SELECT count(*) FROM private.training_execution_finish_withdrawals)=0,'terminal observation invents no cancellation';
 w:=public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,unknown);
 ASSERT w->>'action'='withdrawn' AND w#>>'{state,context,completion,status}'='completed';
 UPDATE private.workout_strength_authority_epochs SET epoch='14300000-0000-4000-8000-000000000080' WHERE user_id=f.owner_id;
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,unknown);
 ASSERT v->>'action'='withdrawn' AND v#>>'{scope,epoch}'='14300000-0000-4000-8000-000000000080' AND v#>>'{state,action}'='absent';
 unknown:=jsonb_set(other,'{operation_id}','"14300000-0000-4000-8000-000000000097"');
 v:=public.observe_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,unknown);
 ASSERT v->>'action'='absent' AND v#>>'{state,action}'='absent','old epoch never relabels old data as new';
 v:=public.withdraw_training_execution_finish_authenticated(f.owner_id,f.auth_id,f.login_id,unknown);
 ASSERT v->>'action'='withdrawn';
 DELETE FROM public.users WHERE id=f.owner_id AND auth_user_id=f.auth_id;
 ASSERT (SELECT count(*) FROM private.training_execution_finish_withdrawals WHERE user_id=f.owner_id)=0,'owner deletion removes markers';
 RAISE NOTICE 'R143_RESERVATION_CANCEL_COMMIT_OTHER_TERMINAL_EPOCH_DELETE_PASS';
END $test$;
ROLLBACK;

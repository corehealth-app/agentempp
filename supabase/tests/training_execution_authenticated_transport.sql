BEGIN;
INSERT INTO auth.users(id,email) VALUES('13600000-0000-4000-8000-000000000001','training-r136@example.invalid');
INSERT INTO public.users(id,auth_user_id,name,timezone) VALUES
 ('13600000-0000-4000-8000-000000000002','13600000-0000-4000-8000-000000000001','Synthetic API execution','America/Sao_Paulo');
DO $test$
BEGIN
 BEGIN
  PERFORM public.capture_training_execution_context('13600000-0000-4000-8000-000000000002','13600000-0000-4000-8000-000000000001',
   '13600000-0000-4000-8000-000000000003','13600000-0000-4000-8000-000000000003');
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 ASSERT NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id='13600000-0000-4000-8000-000000000002'),
  'Reading training must not mint an epoch';
END $test$;
INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
 VALUES('13600000-0000-4000-8000-000000000002','13600000-0000-4000-8000-000000000010',clock_timestamp());
INSERT INTO auth.users(id,email) VALUES('13600000-0000-4000-8000-000000000009','other-training-r136@example.invalid');
INSERT INTO auth.sessions(id,user_id,created_at,not_after) VALUES
 ('13600000-0000-4000-8000-000000000003','13600000-0000-4000-8000-000000000001',clock_timestamp(),NULL),
 ('13600000-0000-4000-8000-000000000004','13600000-0000-4000-8000-000000000001',clock_timestamp()-interval '1 day',clock_timestamp()-interval '1 hour'),
 ('13600000-0000-4000-8000-000000000005','13600000-0000-4000-8000-000000000009',clock_timestamp(),NULL);
DO $test$
DECLARE c jsonb; bad uuid;
BEGIN
 c:=public.read_training_execution_home_authenticated('13600000-0000-4000-8000-000000000002','13600000-0000-4000-8000-000000000001','13600000-0000-4000-8000-000000000003',NULL);
 ASSERT c->'sessions'='[]' AND c->'plan'='null' AND c->'next_cursor'='null';
 ASSERT (SELECT count(*) FROM private.workout_strength_authority_epochs WHERE user_id='13600000-0000-4000-8000-000000000002')=1;
 ASSERT NOT EXISTS(SELECT 1 FROM private.training_execution_sessions WHERE user_id='13600000-0000-4000-8000-000000000002');
 FOREACH bad IN ARRAY ARRAY['13600000-0000-4000-8000-000000000004'::uuid,'13600000-0000-4000-8000-000000000005'::uuid,'13600000-0000-4000-8000-000000000099'::uuid] LOOP
  BEGIN
   PERFORM public.read_training_execution_home_authenticated('13600000-0000-4000-8000-000000000002','13600000-0000-4000-8000-000000000001',bad,NULL);
   RAISE EXCEPTION 'missing/expired/other login accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 DELETE FROM auth.sessions WHERE id='13600000-0000-4000-8000-000000000003';
 BEGIN
  PERFORM public.read_training_execution_home_authenticated('13600000-0000-4000-8000-000000000002','13600000-0000-4000-8000-000000000001','13600000-0000-4000-8000-000000000003',NULL);
  RAISE EXCEPTION 'logged out session accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 ASSERT NOT has_function_privilege('authenticated','public.read_training_execution_home_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('anon','public.commit_training_execution_mutation_authenticated(uuid,uuid,uuid,jsonb,text,timestamptz,jsonb)','EXECUTE');
END $test$;
ROLLBACK;

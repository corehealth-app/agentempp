-- Run against the owned local arena; every fixture and assertion rolls back.
BEGIN;
INSERT INTO auth.users(id,email) VALUES('13500000-0000-4000-8000-000000000001','training-r135@example.invalid');
INSERT INTO public.users(id,auth_user_id,name,timezone) VALUES
 ('13500000-0000-4000-8000-000000000002','13500000-0000-4000-8000-000000000001','Synthetic training execution','America/Sao_Paulo');
DO $test$
DECLARE c jsonb;
BEGIN
 c:=public.capture_training_execution_context(
  '13500000-0000-4000-8000-000000000002','13500000-0000-4000-8000-000000000001',
  '13500000-0000-4000-8000-000000000003','13500000-0000-4000-8000-000000000003');
 ASSERT c#>>'{context,scope,owner_id}'='13500000-0000-4000-8000-000000000002','original owner must be captured';
 ASSERT c#>>'{context,scope,auth_user_id}'='13500000-0000-4000-8000-000000000001','original Auth must be captured';
 ASSERT c#>'{context,session}'='null'::jsonb,'new session must not already exist';
 ASSERT c#>'{context,plan}'='null'::jsonb,'absent plan is not invented';
 ASSERT c#>>'{context,scope,current_local_date}'=c#>>'{context,scope,open_local_date}','open day is captured';
 ASSERT c->>'context_hash' ~ '^[0-9a-f]{64}$','context needs a CAS binding';
 BEGIN
  PERFORM public.capture_training_execution_context(
   '13500000-0000-4000-8000-000000000002','13500000-0000-4000-8000-000000000099',
   '13500000-0000-4000-8000-000000000003','13500000-0000-4000-8000-000000000003');
  RAISE EXCEPTION 'wrong Auth accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 ASSERT NOT has_function_privilege('anon','public.capture_training_execution_context(uuid,uuid,uuid,uuid)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.capture_training_execution_context(uuid,uuid,uuid,uuid)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.capture_training_execution_context(uuid,uuid,uuid,uuid)','EXECUTE');
 ASSERT NOT has_table_privilege('service_role','private.training_execution_sessions','SELECT');
END $test$;
ROLLBACK;

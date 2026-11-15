-- Read-only v2 reconciliation. Never treats completion as a progress receipt.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$ BEGIN
 IF current_user<>'postgres'
 OR to_regprocedure('public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid)') IS NULL
 OR to_regclass('private.training_execution_operations') IS NULL
 OR to_regprocedure('public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'training_progress_reconciliation_unknown_substrate';END IF;
END $preflight$;
CREATE FUNCTION public.reconcile_training_execution_progress_authenticated(
 p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE sid uuid;op uuid;c jsonb;state jsonb;scope jsonb;old private.training_execution_operations%ROWTYPE;found_original boolean;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR octet_length(p_command::text)>16384
 OR p_command->>'schema' IS NULL OR p_command->>'schema' NOT IN('training.execution.start.v1','training.execution.update.v1')
 OR NOT(p_command ?& ARRAY['schema','session_id','operation_id','expected_epoch'])
 OR (p_command->>'schema'='training.execution.start.v1' AND
  (NOT(p_command ?& ARRAY['expected_local_date','plan_id','plan_hash','day_index']) OR
   p_command-ARRAY['schema','session_id','operation_id','expected_epoch','expected_local_date','plan_id','plan_hash','day_index']<>'{}'))
 OR (p_command->>'schema'='training.execution.update.v1' AND
  (NOT(p_command ?& ARRAY['expected_revision','action']) OR
   p_command-ARRAY['schema','session_id','operation_id','expected_epoch','expected_revision','action']<>'{}'))
 THEN RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023';END IF;
 sid:=(p_command->>'session_id')::uuid;op:=(p_command->>'operation_id')::uuid;
 IF sid IS NULL OR op IS NULL OR (p_command->>'expected_epoch') IS NULL THEN
  RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023';END IF;
 -- This existing context uses the same owner/epoch lane as every progress,
 -- completion and reset writer. It creates no epoch or execution on reads.
 c:=private.training_execution_context_at(p_user_id,p_auth_user_id,sid,op,NULL)->'context';
 IF (p_command->>'expected_epoch') IS DISTINCT FROM c#>>'{scope,epoch}' THEN
  RAISE EXCEPTION 'training_execution_epoch_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO old FROM private.training_execution_operations WHERE user_id=p_user_id AND operation_id=op;
 found_original:=FOUND;
 IF found_original AND (old.session_id<>sid OR old.input IS DISTINCT FROM p_command) THEN
  RAISE EXCEPTION 'training_execution_operation_conflict' USING ERRCODE='40001';END IF;
 state:=public.read_training_execution_state_v2_authenticated(p_user_id,p_auth_user_id,p_auth_session_id,sid);
 IF state->>'action'='absent' THEN
  IF found_original THEN RAISE EXCEPTION 'training_execution_original_without_state' USING ERRCODE='40001';END IF;
  scope:=c->'scope';state:=state||jsonb_build_object('scope',scope);
 ELSIF state->>'action'='progress' THEN scope:=state->'scope';
 ELSIF state->>'action'='completion' THEN scope:=state#>'{context,scope}';
 ELSE RAISE EXCEPTION 'training_execution_current_unavailable' USING ERRCODE='40001';END IF;
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 IF NOT found_original THEN RETURN jsonb_build_object('action','absent','scope',scope,'state',state);END IF;
 RETURN jsonb_build_object('action','available','scope',scope,'command',old.input,'receipt',old.receipt,'state',state);
END $$;
REVOKE ALL ON FUNCTION public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb) TO service_role;
COMMIT;

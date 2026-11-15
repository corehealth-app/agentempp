-- Exact future-denial proof for an uncertain finish. No source/report retained
-- in a withdrawal marker, and no workout/clinical/energy writer is replaced.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.training_execution_finish_withdrawals') IS NOT NULL
 OR to_regprocedure('public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid)') IS NULL
 OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=
  to_regprocedure('public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)')) IS DISTINCT FROM
  '012ae850aaa5db318ace7359380fbeb4a6c6db6cfd73addb89d2e4d7c3c87963' THEN
  RAISE EXCEPTION 'training_finish_resolution_unknown_substrate';END IF;
END $preflight$;

CREATE TABLE private.training_execution_finish_withdrawals(
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_id uuid NOT NULL,session_id uuid NOT NULL,auth_user_id uuid NOT NULL,
 epoch uuid NOT NULL,before_revision integer NOT NULL CHECK(before_revision>=0 AND before_revision<2147483647),
 input_hash text COLLATE "C" NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 withdrawn_at timestamptz NOT NULL CHECK(isfinite(withdrawn_at)),
 PRIMARY KEY(user_id,operation_id)
);
ALTER TABLE private.training_execution_finish_withdrawals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.training_execution_finish_withdrawals FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.training_execution_finish_request(p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE sid uuid;op uuid;e uuid;w jsonb;
BEGIN
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR octet_length(p_command::text)>16384
 OR NOT(p_command ?& ARRAY['schema','session_id','operation_id','expected_epoch','expected_revision','source'])
 OR p_command-ARRAY['schema','session_id','operation_id','expected_epoch','expected_revision','source']<>'{}'
 OR p_command->>'schema' IS DISTINCT FROM 'training.execution.finish.v1'
 OR jsonb_typeof(p_command->'expected_revision') IS DISTINCT FROM 'number'
 OR NOT coalesce(p_command->>'expected_revision' ~ '^(0|[1-9][0-9]{0,9})$',false)
 OR (p_command->>'expected_revision')::numeric>=2147483647 THEN
  RAISE EXCEPTION 'training_completion_invalid_input' USING ERRCODE='22023';END IF;
 sid:=(p_command->>'session_id')::uuid;op:=(p_command->>'operation_id')::uuid;e:=(p_command->>'expected_epoch')::uuid;
 IF sid IS NULL OR op IS NULL OR e IS NULL THEN
  RAISE EXCEPTION 'training_completion_invalid_input' USING ERRCODE='22023';END IF;
 w:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',op,'kind','workout.report','source',p_command->'source');
 PERFORM private.assert_conversation_workout_input(w);
 RETURN jsonb_build_object('session_id',sid,'operation_id',op,'epoch',e,'before_revision',p_command->'expected_revision',
  'input_hash',encode(sha256(convert_to(private.conversation_command_canonical(p_command),'UTF8')),'hex'));
END $$;
REVOKE ALL ON FUNCTION private.training_execution_finish_request(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- The original begin body is kept byte-exact behind a narrowly guarded wrapper.
ALTER FUNCTION public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)
 RENAME TO begin_training_execution_completion_unwithdrawn;
ALTER FUNCTION public.begin_training_execution_completion_unwithdrawn(uuid,uuid,uuid,jsonb) SET SCHEMA private;
REVOKE ALL ON FUNCTION private.begin_training_execution_completion_unwithdrawn(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.begin_training_execution_completion_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE request jsonb;r private.training_execution_finish_withdrawals%ROWTYPE;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 request:=private.training_execution_finish_request(p_command);
 SELECT * INTO r FROM private.training_execution_finish_withdrawals
 WHERE user_id=p_user_id AND operation_id=(request->>'operation_id')::uuid;
 IF FOUND THEN
  IF r.auth_user_id IS DISTINCT FROM p_auth_user_id OR r.session_id::text IS DISTINCT FROM request->>'session_id'
  OR r.epoch::text IS DISTINCT FROM request->>'epoch' OR r.before_revision::text IS DISTINCT FROM request->>'before_revision'
  OR r.input_hash IS DISTINCT FROM request->>'input_hash' THEN
   RAISE EXCEPTION 'training_completion_operation_conflict' USING ERRCODE='40001';END IF;
  RAISE EXCEPTION 'training_completion_withdrawn' USING ERRCODE='40001';
 END IF;
 RETURN private.begin_training_execution_completion_unwithdrawn(p_user_id,p_auth_user_id,p_auth_session_id,p_command);
END $$;
REVOKE ALL ON FUNCTION public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb) TO service_role;

CREATE FUNCTION private.training_execution_finish_resolution_at(p_user uuid,p_auth uuid,p_login uuid,p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE c jsonb;scope jsonb;state jsonb;own jsonb;r private.training_execution_completions%ROWTYPE;
 w private.training_execution_finish_withdrawals%ROWTYPE;has_completion boolean;has_marker boolean;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user,p_auth,p_login);
 c:=private.training_execution_context_at(p_user,p_auth,NULL,NULL,NULL)->'context';scope:=c->'scope';
 SELECT * INTO r FROM private.training_execution_completions
 WHERE user_id=p_user AND completion_id=(p_request->>'operation_id')::uuid FOR UPDATE;has_completion:=FOUND;
 SELECT * INTO w FROM private.training_execution_finish_withdrawals
 WHERE user_id=p_user AND operation_id=(p_request->>'operation_id')::uuid FOR UPDATE;has_marker:=FOUND;
 IF has_completion AND has_marker THEN RAISE EXCEPTION 'training_finish_resolution_conflicting_history' USING ERRCODE='40001';END IF;
 IF has_completion THEN
  IF r.auth_user_id IS DISTINCT FROM p_auth OR r.session_id::text IS DISTINCT FROM p_request->>'session_id'
  OR r.epoch::text IS DISTINCT FROM p_request->>'epoch' OR r.original_revision::text IS DISTINCT FROM p_request->>'before_revision'
  OR r.input_hash IS DISTINCT FROM p_request->>'input_hash' THEN
   RAISE EXCEPTION 'training_completion_operation_conflict' USING ERRCODE='40001';END IF;
  own:=private.training_execution_completion_context(p_user,p_auth,p_login,r.completion_id);
 END IF;
 IF has_marker AND (w.auth_user_id IS DISTINCT FROM p_auth OR w.session_id::text IS DISTINCT FROM p_request->>'session_id'
 OR w.epoch::text IS DISTINCT FROM p_request->>'epoch' OR w.before_revision::text IS DISTINCT FROM p_request->>'before_revision'
 OR w.input_hash IS DISTINCT FROM p_request->>'input_hash') THEN
  RAISE EXCEPTION 'training_completion_operation_conflict' USING ERRCODE='40001';END IF;
 IF p_request->>'epoch' IS DISTINCT FROM scope->>'epoch' THEN
  state:=jsonb_build_object('action','absent','scope',scope);
 ELSE
  state:=public.read_training_execution_state_v2_authenticated(p_user,p_auth,p_login,(p_request->>'session_id')::uuid);
  IF state->>'action'='completion' THEN scope:=state#>'{context,scope}';
  ELSIF state->>'action'='progress' THEN scope:=state->'scope';
  ELSIF state->>'action'='absent' THEN state:=state||jsonb_build_object('scope',scope);
  ELSE RAISE EXCEPTION 'training_finish_resolution_current_unavailable' USING ERRCODE='40001';END IF;
 END IF;
 PERFORM private.lock_training_execution_auth_session(p_user,p_auth,p_login);
 IF has_completion THEN
  RETURN jsonb_build_object('action','available','request',p_request,'scope',scope,'state',state,'completion',own);
 ELSIF has_marker THEN
  RETURN jsonb_build_object('action','withdrawn','request',p_request,'scope',scope,'state',state,'withdrawal',
   p_request||jsonb_build_object('schema','training.execution-finish-withdrawal.v1','owner_id',p_user,'auth_user_id',p_auth,
    'at',private.conversation_workout_clock(w.withdrawn_at)));
 END IF;
 RETURN jsonb_build_object('action','absent','request',p_request,'scope',scope,'state',state);
END $$;
REVOKE ALL ON FUNCTION private.training_execution_finish_resolution_at(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.observe_training_execution_finish_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN private.training_execution_finish_resolution_at(p_user_id,p_auth_user_id,p_auth_session_id,private.training_execution_finish_request(p_command));
END $$;
CREATE FUNCTION public.withdraw_training_execution_finish_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE request jsonb;v jsonb;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 request:=private.training_execution_finish_request(p_command);
 v:=private.training_execution_finish_resolution_at(p_user_id,p_auth_user_id,p_auth_session_id,request);
 IF v->>'action'='available' THEN
  IF v#>>'{completion,completion,status}'='reserved' THEN
   PERFORM public.cancel_training_execution_completion_authenticated(p_user_id,p_auth_user_id,p_auth_session_id,
    (request->>'operation_id')::uuid,request->>'input_hash');
   RETURN private.training_execution_finish_resolution_at(p_user_id,p_auth_user_id,p_auth_session_id,request);
  END IF;
  RETURN v;
 ELSIF v->>'action'='withdrawn' THEN RETURN v;END IF;
 -- Never use a missing training row to deny an unlinked or different-domain effect.
 IF EXISTS(SELECT 1 FROM private.training_execution_operations WHERE user_id=p_user_id AND operation_id=(request->>'operation_id')::uuid)
 OR EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=(request->>'operation_id')::uuid)
 OR EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=(request->>'operation_id')::uuid) THEN
  RAISE EXCEPTION 'training_completion_unlinked_command' USING ERRCODE='40001';END IF;
 INSERT INTO private.training_execution_finish_withdrawals(user_id,operation_id,session_id,auth_user_id,epoch,before_revision,input_hash,withdrawn_at)
 VALUES(p_user_id,(request->>'operation_id')::uuid,(request->>'session_id')::uuid,p_auth_user_id,(request->>'epoch')::uuid,
  (request->>'before_revision')::integer,request->>'input_hash',clock_timestamp());
 RETURN private.training_execution_finish_resolution_at(p_user_id,p_auth_user_id,p_auth_session_id,request);
END $$;
REVOKE ALL ON FUNCTION public.observe_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb),
 public.withdraw_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.observe_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb),
 public.withdraw_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb) TO service_role;
COMMIT;

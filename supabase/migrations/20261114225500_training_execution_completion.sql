-- Protected T5 completion. No route/capability/client cutover here.
-- The existing workout primitive still owns clinical, energy and strength facts.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
DECLARE sig text;pin text;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.training_execution_completions') IS NOT NULL
 OR to_regprocedure('private.lock_training_execution_auth_session(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'training_completion_unknown_substrate'; END IF;
 FOR sig,pin IN SELECT * FROM (VALUES
  ('public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb)','c8ff48378e08db4260d7aba63a2b3a20e065dd2a199d846fb0b55587a2dd2743'),
  ('public.commit_training_execution_mutation(uuid,uuid,jsonb,text,timestamptz,jsonb)','7075a91b3b5e7b282e51500f0ce701e19aadabc964956a89acb2eaa74952e7d7')
 ) expected(signature,hash) LOOP
  IF to_regprocedure(sig) IS NULL OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM pin THEN
   RAISE EXCEPTION 'training_completion_unknown_body:%',sig; END IF;
 END LOOP;
END $preflight$;

CREATE TABLE private.training_execution_completions (
 user_id uuid NOT NULL,completion_id uuid NOT NULL,session_id uuid NOT NULL,
 auth_user_id uuid NOT NULL,epoch uuid NOT NULL,time_zone text NOT NULL,
 original_revision integer NOT NULL CHECK(original_revision>=0 AND original_revision<2147483647),
 command jsonb NOT NULL,input_hash text COLLATE "C" NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 workout_input jsonb NOT NULL,workout_hash text COLLATE "C" NOT NULL CHECK(workout_hash ~ '^[0-9a-f]{64}$'),
 frozen_state jsonb NOT NULL,frozen_hash text COLLATE "C" NOT NULL CHECK(frozen_hash ~ '^[0-9a-f]{64}$'),
 status text NOT NULL CHECK(status IN('reserved','completed','cancelled')),
 reserved_at timestamptz NOT NULL CHECK(isfinite(reserved_at)),
 completed_at timestamptz CHECK(isfinite(completed_at)),cancelled_at timestamptz CHECK(isfinite(cancelled_at)),
 receipt jsonb,cancel_receipt jsonb,
 PRIMARY KEY(user_id,completion_id),
 FOREIGN KEY(user_id,session_id) REFERENCES private.training_execution_sessions(user_id,session_id) ON DELETE CASCADE,
 CHECK(jsonb_typeof(command)='object' AND octet_length(command::text)<=16384
  AND (command->>'operation_id')::uuid=completion_id AND (command->>'session_id')::uuid=session_id
  AND (command->>'expected_epoch')::uuid=epoch AND (command->>'expected_revision')::integer=original_revision),
 CHECK(jsonb_typeof(frozen_state)='object' AND octet_length(frozen_state::text)<=524288
  AND (frozen_state->>'id')::uuid=session_id AND (frozen_state->>'owner_id')::uuid=user_id
  AND (frozen_state->>'auth_user_id')::uuid=auth_user_id AND (frozen_state->>'epoch')::uuid=epoch
  AND (frozen_state->>'revision')::integer=original_revision),
 CHECK((status='completed')=(receipt IS NOT NULL) AND (status='completed')=(completed_at IS NOT NULL)),
 CHECK((status='cancelled')=(cancel_receipt IS NOT NULL) AND (status='cancelled')=(cancelled_at IS NOT NULL))
);
CREATE UNIQUE INDEX training_execution_one_completion ON private.training_execution_completions(user_id,session_id)
 WHERE status IN('reserved','completed');
CREATE TABLE private.training_execution_completion_events (
 user_id uuid NOT NULL,completion_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN('reserved','completed','cancelled')),
 at timestamptz NOT NULL CHECK(isfinite(at)),body jsonb NOT NULL CHECK(jsonb_typeof(body)='object' AND octet_length(body::text)<=16384),
 PRIMARY KEY(user_id,completion_id,kind),
 FOREIGN KEY(user_id,completion_id) REFERENCES private.training_execution_completions(user_id,completion_id) ON DELETE CASCADE
);
ALTER TABLE private.training_execution_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.training_execution_completion_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.training_execution_completions,private.training_execution_completion_events FROM PUBLIC,anon,authenticated,service_role;

-- Keep the original executable bodies intact. Public callers cannot bypass a
-- reserved/cancelled training command; only the guarded completion calls it.
ALTER FUNCTION public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb) RENAME TO commit_conversation_workout_unreserved;
ALTER FUNCTION public.commit_conversation_workout_unreserved(uuid,uuid,text,text,uuid,text,jsonb) SET SCHEMA private;
ALTER FUNCTION public.commit_training_execution_mutation(uuid,uuid,jsonb,text,timestamptz,jsonb) RENAME TO commit_training_execution_mutation_unreserved;
ALTER FUNCTION public.commit_training_execution_mutation_unreserved(uuid,uuid,jsonb,text,timestamptz,jsonb) SET SCHEMA private;
REVOKE ALL ON FUNCTION private.commit_conversation_workout_unreserved(uuid,uuid,text,text,uuid,text,jsonb),
 private.commit_training_execution_mutation_unreserved(uuid,uuid,jsonb,text,timestamptz,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.commit_conversation_workout(p_user_id uuid,p_command_id uuid,p_input_hash text,p_source_hash text,p_expected_epoch uuid,p_prepared_hash text,p_prepared jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.lock_conversation_command_owner(p_user_id);
 IF EXISTS(SELECT 1 FROM private.training_execution_completions WHERE user_id=p_user_id AND completion_id=p_command_id) THEN
  RETURN '{"action":"training_completion_required"}'; END IF;
 RETURN private.commit_conversation_workout_unreserved(p_user_id,p_command_id,p_input_hash,p_source_hash,p_expected_epoch,p_prepared_hash,p_prepared);
END $$;

CREATE FUNCTION public.commit_training_execution_mutation(p_user_id uuid,p_auth_user_id uuid,p_command jsonb,p_context_hash text,p_observed_at timestamptz,p_prepared jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.lock_conversation_command_owner(p_user_id);
 IF EXISTS(SELECT 1 FROM private.training_execution_completions WHERE user_id=p_user_id AND session_id=(p_command->>'session_id')::uuid AND status IN('reserved','completed'))
 AND NOT EXISTS(SELECT 1 FROM private.training_execution_operations WHERE user_id=p_user_id AND operation_id=(p_command->>'operation_id')::uuid) THEN
  RAISE EXCEPTION 'training_execution_completion_locked' USING ERRCODE='40001'; END IF;
 RETURN private.commit_training_execution_mutation_unreserved(p_user_id,p_auth_user_id,p_command,p_context_hash,p_observed_at,p_prepared);
END $$;

-- All entry points retain the live original login. Reads lock no additional
-- lifecycle into existence and may observe a recorded/cancelled outcome later.
CREATE FUNCTION private.training_execution_completion_context(p_user uuid,p_auth uuid,p_login uuid,p_completion uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE r private.training_execution_completions%ROWTYPE;c jsonb;s jsonb;e private.conversation_workout_effects%ROWTYPE;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user,p_auth,p_login);
 SELECT * INTO r FROM private.training_execution_completions WHERE user_id=p_user AND completion_id=p_completion;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'; END IF;
 c:=private.training_execution_context_at(p_user,p_auth,r.session_id,r.completion_id,NULL)->'context';s:=c->'session';
 SELECT * INTO STRICT r FROM private.training_execution_completions WHERE user_id=p_user AND completion_id=p_completion FOR UPDATE;
 IF r.auth_user_id IS DISTINCT FROM p_auth OR r.epoch::text IS DISTINCT FROM c#>>'{scope,epoch}'
 OR r.time_zone IS DISTINCT FROM c#>>'{scope,time_zone}' OR s='null'::jsonb
 OR s->>'auth_user_id' IS DISTINCT FROM p_auth::text OR s->>'epoch' IS DISTINCT FROM r.epoch::text THEN
  RAISE EXCEPTION 'training_completion_scope_changed' USING ERRCODE='40001'; END IF;
 IF r.status='reserved' AND (s IS DISTINCT FROM r.frozen_state OR encode(sha256(convert_to(s::text,'UTF8')),'hex') IS DISTINCT FROM r.frozen_hash) THEN
  RAISE EXCEPTION 'training_completion_frozen_state_changed' USING ERRCODE='40001'; END IF;
 IF r.status='completed' THEN
  SELECT * INTO e FROM private.conversation_workout_effects WHERE user_id=p_user AND command_id=p_completion;
  IF NOT FOUND OR r.receipt->'workout' IS DISTINCT FROM e.receipt OR s->>'schema'<>'training.execution.v2'
  OR s->>'phase'<>'completed' OR (s->>'revision')::integer<>r.original_revision+1
  OR s->'exercises' IS DISTINCT FROM r.frozen_state->'exercises' OR s->'definition' IS DISTINCT FROM r.frozen_state->'definition' THEN
   RAISE EXCEPTION 'training_completion_receipt_unproved' USING ERRCODE='40001'; END IF;
 END IF;
 RETURN jsonb_build_object('action','available','scope',c->'scope','session',s,'completion',to_jsonb(r),
  'workout_is_live',CASE WHEN r.status='completed' THEN EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=p_user AND id=e.live_workout_id) ELSE NULL END);
END $$;

CREATE FUNCTION public.begin_training_execution_completion_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE r private.training_execution_completions%ROWTYPE;c jsonb;s jsonb;scope jsonb;workout jsonb;admission jsonb;
 sid uuid;op uuid;e uuid;h text;wh text;at timestamptz;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR octet_length(p_command::text)>16384
 OR NOT(p_command ?& ARRAY['schema','session_id','operation_id','expected_epoch','expected_revision','source'])
 OR p_command-ARRAY['schema','session_id','operation_id','expected_epoch','expected_revision','source']<>'{}'
 OR p_command->>'schema' IS DISTINCT FROM 'training.execution.finish.v1'
 OR jsonb_typeof(p_command->'source') IS DISTINCT FROM 'object' OR p_command#>>'{source,channel}' IS DISTINCT FROM 'text'
 OR jsonb_typeof(p_command->'expected_revision') IS DISTINCT FROM 'number'
 OR NOT coalesce(p_command->>'expected_revision' ~ '^(0|[1-9][0-9]{0,9})$',false)
 OR (p_command->>'expected_revision')::numeric>=2147483647 THEN
  RAISE EXCEPTION 'training_completion_invalid_input' USING ERRCODE='22023'; END IF;
 sid:=(p_command->>'session_id')::uuid;op:=(p_command->>'operation_id')::uuid;e:=(p_command->>'expected_epoch')::uuid;
 IF sid IS NULL OR op IS NULL OR e IS NULL OR p_command->>'session_id'<>sid::text OR p_command->>'operation_id'<>op::text OR p_command->>'expected_epoch'<>e::text THEN
  RAISE EXCEPTION 'training_completion_invalid_input' USING ERRCODE='22023'; END IF;
 workout:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',op,'kind','workout.report','source',p_command->'source');
 PERFORM private.assert_conversation_workout_input(workout);
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_command),'UTF8')),'hex');
 wh:=encode(sha256(convert_to(private.conversation_command_canonical(workout),'UTF8')),'hex');
 c:=private.training_execution_context_at(p_user_id,p_auth_user_id,sid,op,NULL)->'context';s:=c->'session';scope:=c->'scope';
 IF e::text IS DISTINCT FROM scope->>'epoch' THEN RAISE EXCEPTION 'training_completion_epoch_changed' USING ERRCODE='40001'; END IF;
 SELECT * INTO r FROM private.training_execution_completions WHERE user_id=p_user_id AND completion_id=op FOR UPDATE;
 IF FOUND THEN
  IF r.session_id<>sid OR r.command IS DISTINCT FROM p_command OR r.input_hash<>h THEN
   RAISE EXCEPTION 'training_completion_operation_conflict' USING ERRCODE='40001'; END IF;
  c:=private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,op);
  RETURN c||'{"action":"replay"}';
 END IF;
 IF s='null'::jsonb OR s->>'schema' IS DISTINCT FROM 'training.execution.v1' OR s->>'phase' IS DISTINCT FROM 'in_progress'
 OR s->>'owner_id' IS DISTINCT FROM p_user_id::text OR s->>'auth_user_id' IS DISTINCT FROM p_auth_user_id::text
 OR s->>'epoch' IS DISTINCT FROM e::text OR s->>'time_zone' IS DISTINCT FROM scope->>'time_zone'
 OR s->>'revision' IS DISTINCT FROM p_command->>'expected_revision'
 OR scope->'recording_allowed' IS DISTINCT FROM 'true'::jsonb
 OR s->>'local_date' IS DISTINCT FROM scope->>'open_local_date' OR s->>'local_date' IS DISTINCT FROM scope->>'current_local_date' THEN
  RAISE EXCEPTION 'training_completion_state_changed' USING ERRCODE='40001'; END IF;
 IF EXISTS(SELECT 1 FROM private.training_execution_completions WHERE user_id=p_user_id AND session_id=sid AND status IN('reserved','completed'))
 OR EXISTS(SELECT 1 FROM private.training_execution_operations WHERE user_id=p_user_id AND operation_id=op)
 OR EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=op)
 OR EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=op) THEN
  RAISE EXCEPTION 'training_completion_in_progress_or_operation_used' USING ERRCODE='40001'; END IF;
 at:=clock_timestamp();
 INSERT INTO private.training_execution_completions(user_id,completion_id,session_id,auth_user_id,epoch,time_zone,original_revision,
 command,input_hash,workout_input,workout_hash,frozen_state,frozen_hash,status,reserved_at)
 VALUES(p_user_id,op,sid,p_auth_user_id,e,scope->>'time_zone',(s->>'revision')::integer,
 p_command,h,workout,wh,s,encode(sha256(convert_to(s::text,'UTF8')),'hex'),'reserved',at);
 admission:=public.admit_conversation_workout_command(p_user_id,e,workout);
 IF admission->>'action' IS DISTINCT FROM 'admitted' THEN
  RAISE EXCEPTION 'training_completion_admission_refused:%',admission->>'action' USING ERRCODE='40001'; END IF;
 INSERT INTO private.training_execution_completion_events VALUES(p_user_id,op,'reserved',at,
  jsonb_build_object('input_hash',h,'session_id',sid,'revision',s->'revision','workout_hash',wh));
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 c:=private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,op);
 RETURN c||'{"action":"reserved"}';
END $$;

CREATE FUNCTION public.read_training_execution_completion_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_completion_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,p_completion_id);
$$;

CREATE FUNCTION public.cancel_training_execution_completion_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_completion_id uuid,p_input_hash text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;r private.training_execution_completions%ROWTYPE;at timestamptz;cancelled_receipt jsonb;
BEGIN
 c:=private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,p_completion_id);
 IF c->>'action'<>'available' THEN RETURN c; END IF;
 SELECT * INTO STRICT r FROM private.training_execution_completions WHERE user_id=p_user_id AND completion_id=p_completion_id;
 IF p_input_hash IS DISTINCT FROM r.input_hash THEN RAISE EXCEPTION 'training_completion_input_changed' USING ERRCODE='40001'; END IF;
 IF r.status='completed' THEN RETURN jsonb_build_object('action','completed','receipt',r.receipt); END IF;
 IF r.status='cancelled' THEN RETURN jsonb_build_object('action','replay','receipt',r.cancel_receipt); END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_completion_id) THEN
  RAISE EXCEPTION 'training_completion_unlinked_effect' USING ERRCODE='40001'; END IF;
 at:=clock_timestamp();cancelled_receipt:=jsonb_build_object('schema','training.execution-finish-cancelled.v1','owner_id',p_user_id,
  'auth_user_id',p_auth_user_id,'epoch',r.epoch,'session_id',r.session_id,'completion_id',p_completion_id,'input_hash',r.input_hash,
  'at',private.conversation_workout_clock(at));
 UPDATE private.training_execution_completions SET status='cancelled',cancelled_at=at,cancel_receipt=cancelled_receipt WHERE user_id=p_user_id AND completion_id=p_completion_id;
 INSERT INTO private.training_execution_completion_events VALUES(p_user_id,p_completion_id,'cancelled',at,cancelled_receipt);
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN jsonb_build_object('action','cancelled','receipt',cancelled_receipt);
END $$;

CREATE FUNCTION public.commit_training_execution_completion_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_completion_id uuid,
 p_input_hash text,p_source_hash text,p_prepared_hash text,p_prepared jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c jsonb;r private.training_execution_completions%ROWTYPE;src private.conversation_workout_sources%ROWTYPE;
 prep private.conversation_workout_preparations%ROWTYPE;effect private.conversation_workout_effects%ROWTYPE;
 result jsonb;next_state jsonb;completed_receipt jsonb;at timestamptz;
BEGIN
 c:=private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,p_completion_id);
 IF c->>'action'<>'available' THEN RETURN c; END IF;
 SELECT * INTO STRICT r FROM private.training_execution_completions WHERE user_id=p_user_id AND completion_id=p_completion_id;
 IF p_input_hash IS DISTINCT FROM r.input_hash THEN RAISE EXCEPTION 'training_completion_input_changed' USING ERRCODE='40001'; END IF;
 IF r.status='cancelled' THEN RAISE EXCEPTION 'training_completion_cancelled' USING ERRCODE='40001'; END IF;
 SELECT * INTO src FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_completion_id;
 IF NOT FOUND OR src.source_hash IS DISTINCT FROM p_source_hash OR src.context->'source_input' IS DISTINCT FROM r.workout_input THEN
  RAISE EXCEPTION 'training_completion_source_unproved' USING ERRCODE='40001'; END IF;
 SELECT * INTO prep FROM private.conversation_workout_preparations WHERE user_id=p_user_id AND command_id=p_completion_id;
 IF NOT FOUND OR prep.prepared_hash IS DISTINCT FROM p_prepared_hash OR prep.prepared IS DISTINCT FROM p_prepared THEN
  RAISE EXCEPTION 'training_completion_preparation_unproved' USING ERRCODE='40001'; END IF;
 IF r.status='completed' THEN RETURN jsonb_build_object('action','replay','receipt',r.receipt->'workout'); END IF;
 IF c#>'{scope,recording_allowed}' IS DISTINCT FROM 'true'::jsonb
 OR r.frozen_state->>'local_date' IS DISTINCT FROM c#>>'{scope,open_local_date}'
 OR r.frozen_state->>'local_date' IS DISTINCT FROM c#>>'{scope,current_local_date}' THEN
  RAISE EXCEPTION 'training_completion_day_closed' USING ERRCODE='40001'; END IF;
 result:=private.commit_conversation_workout_unreserved(p_user_id,p_completion_id,r.workout_hash,p_source_hash,r.epoch,p_prepared_hash,p_prepared);
 IF result->>'action' NOT IN('committed','replay') THEN RETURN result; END IF;
 SELECT * INTO effect FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_completion_id;
 IF NOT FOUND OR effect.receipt IS DISTINCT FROM result->'receipt' OR effect.receipt->>'input_hash' IS DISTINCT FROM r.workout_hash
 OR effect.receipt->>'epoch' IS DISTINCT FROM r.epoch::text OR effect.receipt->>'command_id' IS DISTINCT FROM p_completion_id::text
 OR effect.original_workout_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE id=effect.original_workout_id AND user_id=p_user_id) THEN
  RAISE EXCEPTION 'training_completion_effect_unproved' USING ERRCODE='40001'; END IF;
 at:=(effect.receipt->>'committed_at')::timestamptz;
 next_state:=r.frozen_state||jsonb_build_object('schema','training.execution.v2','phase','completed','revision',r.original_revision+1,'updated_at',effect.receipt->'committed_at');
 UPDATE private.training_execution_sessions SET state=next_state,revision=r.original_revision+1
 WHERE user_id=p_user_id AND session_id=r.session_id AND revision=r.original_revision AND training_execution_sessions.state=r.frozen_state;
 IF NOT FOUND THEN RAISE EXCEPTION 'training_completion_frozen_state_changed' USING ERRCODE='40001'; END IF;
 completed_receipt:=jsonb_build_object('schema','training.execution-completed.v1','owner_id',p_user_id,'auth_user_id',p_auth_user_id,
  'epoch',r.epoch,'session_id',r.session_id,'completion_id',p_completion_id,'input_hash',r.input_hash,
  'before_revision',r.original_revision,'after_revision',r.original_revision+1,'at',effect.receipt->'committed_at','workout',effect.receipt);
 UPDATE private.training_execution_completions SET status='completed',completed_at=at,receipt=completed_receipt WHERE user_id=p_user_id AND completion_id=p_completion_id;
 INSERT INTO private.training_execution_completion_events VALUES(p_user_id,p_completion_id,'completed',at,completed_receipt);
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN result;
END $$;

REVOKE ALL ON FUNCTION private.training_execution_completion_context(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb),
 public.commit_training_execution_mutation(uuid,uuid,jsonb,text,timestamptz,jsonb),
 public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb),
 public.read_training_execution_completion_authenticated(uuid,uuid,uuid,uuid),
 public.cancel_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text),
 public.commit_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb),
 public.commit_training_execution_mutation(uuid,uuid,jsonb,text,timestamptz,jsonb),
 public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb),
 public.read_training_execution_completion_authenticated(uuid,uuid,uuid,uuid),
 public.cancel_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text),
 public.commit_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text,text,text,jsonb) TO service_role;
COMMIT;

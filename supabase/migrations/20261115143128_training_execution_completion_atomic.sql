-- Bound the completion's network round trips without replacing any workout,
-- clinical, energy, strength, cancellation or withdrawal primitive.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
DECLARE sig text;pin text;
BEGIN
 IF current_user<>'postgres' OR to_regprocedure('public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'training_completion_atomic_unknown_substrate';END IF;
 FOR sig,pin IN SELECT * FROM (VALUES
  ('public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','3ad19d334f39f6c3c5447ade716eb5a50ce53878fcd6676f2b6916c2a650b100'),
  ('public.commit_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text,text,text,jsonb)','2e0513e90dbea0d9502ab07c83b561bd9172a66c8c1bb6f9e7e15b0578497591'),
  ('private.conversation_workout_report_v2(jsonb,text)','4b28e9cb31d23b87c16903645ba2e7c740fa3c4ae0d81387391eb39684f9c255'),
  ('public.capture_conversation_workout_source(uuid,uuid,text,uuid)','1269a0bab0fd4c7e60cdfa9eff1388981f8d52dc073beec6c5a58e3351f5307a'),
  ('public.prepare_conversation_workout(uuid,uuid,text,text,uuid,jsonb)','020ae2d686ef2b741b1dedbbb37c8b772aa30310dc69115f2fa0cc84979eb463'),
  ('public.read_conversation_workout_effect(uuid,uuid,text,text,uuid,text)','6552230698ec02cce5dba2edb374792a8d069e6ba0753187d6df7d9933d6cbc0'),
  ('public.read_conversation_workout_preparation(uuid,uuid,text,uuid)','64c82f1cadce206f10ac80ed606066188ff89168ef94aa0774487cdcc40aad62')
 ) expected(signature,hash) LOOP
  IF to_regprocedure(sig) IS NULL OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM pin THEN
   RAISE EXCEPTION 'training_completion_atomic_unknown_body:%',sig;END IF;
 END LOOP;
END $preflight$;

CREATE FUNCTION public.submit_training_execution_completion_authenticated(
 p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c jsonb;stored jsonb;s jsonb;p jsonb;report jsonb;effect jsonb;written jsonb;
 op uuid;e uuid;workout_hash text;input_hash text;
BEGIN
 -- This owner/Auth-session lock is retained across all original primitives.
 -- Logout/reset/withdrawal cannot pass between reservation and its writer.
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 c:=public.begin_training_execution_completion_authenticated(p_user_id,p_auth_user_id,p_auth_session_id,p_command);
 IF c#>>'{completion,status}'='cancelled' THEN
  PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
  RETURN jsonb_build_object('status','cancelled','completion',c);
 END IF;
 op:=(c#>>'{completion,completion_id}')::uuid;e:=(c#>>'{completion,epoch}')::uuid;
 workout_hash:=c#>>'{completion,workout_hash}';input_hash:=c#>>'{completion,input_hash}';
 stored:=public.read_conversation_workout_preparation(p_user_id,op,workout_hash,e);
 IF stored->>'action' IS DISTINCT FROM 'available' THEN
  RAISE EXCEPTION 'training_completion_atomic_preparation_unavailable' USING ERRCODE='40001';END IF;
 s:=stored->'source';p:=stored->'preparation';
 IF s IS NULL OR s='null'::jsonb THEN s:=public.capture_conversation_workout_source(p_user_id,op,workout_hash,e);END IF;
 IF p IS NULL OR p='null'::jsonb THEN
  report:=private.conversation_workout_report_v2(s->'context',s->>'source_hash');
  p:=public.prepare_conversation_workout(p_user_id,op,workout_hash,s->>'source_hash',e,report);
 END IF;
 IF p#>>'{prepared,status}' IN('needs_reply','not_reported') THEN
  c:=public.read_training_execution_completion_authenticated(p_user_id,p_auth_user_id,p_auth_session_id,op);
  PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
  RETURN jsonb_build_object('status','decision','source',s,'preparation',p,'completion',c);
 END IF;
 IF p#>>'{prepared,status}' IS DISTINCT FROM 'ready' THEN
  RAISE EXCEPTION 'training_completion_atomic_preparation_unproved' USING ERRCODE='40001';END IF;
 effect:=public.read_conversation_workout_effect(p_user_id,op,workout_hash,s->>'source_hash',e,p->>'prepared_hash');
 IF effect->>'action'='absent' THEN
  written:=public.commit_training_execution_completion_authenticated(p_user_id,p_auth_user_id,p_auth_session_id,op,
   input_hash,s->>'source_hash',p->>'prepared_hash',p->'prepared');
  IF written->>'action' NOT IN('committed','replay') OR written->>'action' IS NULL THEN
   RAISE EXCEPTION 'training_completion_atomic_commit_unproved' USING ERRCODE='40001';END IF;
  -- A writer reply alone is not an ACK: independently read its actual effect.
  effect:=public.read_conversation_workout_effect(p_user_id,op,workout_hash,s->>'source_hash',e,p->>'prepared_hash');
 END IF;
 c:=public.read_training_execution_completion_authenticated(p_user_id,p_auth_user_id,p_auth_session_id,op);
 IF effect->>'action' IS DISTINCT FROM 'available' OR c#>>'{completion,status}' IS DISTINCT FROM 'completed'
 OR effect->'receipt' IS DISTINCT FROM c#>'{completion,receipt,workout}' THEN
  RAISE EXCEPTION 'training_completion_atomic_link_unproved' USING ERRCODE='40001';END IF;
 -- Natural Auth expiry during calculation also aborts the whole transaction.
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN jsonb_build_object('status','saved','source',s,'preparation',p,'effect',effect,'completion',c);
END $$;
REVOKE ALL ON FUNCTION public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb) TO service_role;
COMMIT;

-- Dormant command-only receipt sealing from the original committed source.
-- No live recapture, business writer, clinical initialization or public caller.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_meal_effects') IS NULL
  OR to_regprocedure('private.assert_registration_feedback_v2_sources(jsonb,jsonb)') IS NULL
  OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure('public.commit_mobile_registration_feedback_v2(uuid,uuid,jsonb,jsonb)')) IS DISTINCT FROM 'e875b795e303e43c468549aab19d2b972d59aa668c188167d31babd578c85cf3'
  OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure('public.commit_mobile_registration_feedback(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb)')) IS DISTINCT FROM '440f02f0c8f8f232f9e59b3e82832156ba8d53dcc5180d505033d5522454b52b'
  OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure('private.guard_mobile_registration_feedback_v2()')) IS DISTINCT FROM 'a8e00d742f755da596faefacf7c0dd1aeb64a47ca9729ee0a859b7598654df4f' THEN
  RAISE EXCEPTION 'conversation_feedback_requires_pinned_substrate' USING ERRCODE='42501';
 END IF;
END $preflight$;

-- Nullable bridge preserves every old receipt and explicit-column T2C insert.
-- Command health payloads also follow the existing epoch -> source cascade.
ALTER TABLE private.mobile_registration_feedback_v2 ADD COLUMN command_id uuid,
 ADD CONSTRAINT mobile_feedback_v2_command_unique UNIQUE(user_id,command_id),
 ADD CONSTRAINT mobile_feedback_v2_command_effect FOREIGN KEY(user_id,command_id)
 REFERENCES private.conversation_meal_effects(user_id,command_id) ON DELETE CASCADE;
CREATE OR REPLACE FUNCTION private.guard_mobile_registration_feedback_v2() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=OLD.registration_id)
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)
  OR (OLD.command_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=OLD.user_id AND command_id=OLD.command_id))) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'immutable_registration_feedback_v2' USING ERRCODE='22023';
END $$;

CREATE FUNCTION private.conversation_meal_frozen_feedback_source(e private.conversation_meal_effects) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT CASE WHEN (e).feedback_context IS NULL OR jsonb_typeof((e).feedback_context) IS DISTINCT FROM 'object'
  OR (e).feedback_context->'confirmed' IS DISTINCT FROM (e).original_facts->'confirmed'
  OR (e).feedback_context->'logs' IS DISTINCT FROM (e).original_facts->'logs'
  OR (e).feedback_context->'snapshot' IS DISTINCT FROM (e).original_facts->'snapshot'
 THEN jsonb_build_object('action','unavailable','reason','original_context_unavailable','receipt',(e).receipt)
 ELSE jsonb_build_object('action','available','receipt',(e).receipt,'context',(e).feedback_context) END;
$$;
CREATE FUNCTION private.conversation_meal_feedback_receipt(e private.conversation_meal_effects) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE r private.mobile_registration_feedback_v2%ROWTYPE;old private.mobile_registration_feedback%ROWTYPE;h text;source_hash text;registration uuid;
BEGIN
 registration:=(e.receipt->>'registration_id')::uuid;
 SELECT * INTO r FROM private.mobile_registration_feedback_v2 WHERE registration_id=registration AND user_id=e.user_id;
 SELECT * INTO old FROM private.mobile_registration_feedback WHERE registration_id=registration AND user_id=e.user_id;
 IF r.registration_id IS NOT NULL AND old.registration_id IS NOT NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 h:=encode(extensions.digest(convert_to((e.original_facts#>'{confirmed,proposal}')::text,'UTF8'),'sha256'),'hex');
 IF r.registration_id IS NOT NULL THEN
  -- An old unlinked live-CAS receipt is never relabelled as original authority.
  IF r.command_id IS DISTINCT FROM e.command_id OR r.proposal_hash IS DISTINCT FROM h
   OR private.conversation_meal_frozen_feedback_source(e)->>'action'<>'available' THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
  source_hash:=encode(extensions.digest(convert_to(private.mobile_registration_feedback_v2_source_binding(e.feedback_context)::text,'UTF8'),'sha256'),'hex');
  IF r.source_hash IS DISTINCT FROM source_hash THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('action','available','feedback',r.feedback);
 END IF;
 IF old.registration_id IS NOT NULL THEN
  IF old.proposal_hash IS DISTINCT FROM h THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('action','legacy','feedback',old.feedback);
 END IF;
 RETURN '{"action":"absent"}'::jsonb;
END $$;

CREATE FUNCTION public.read_conversation_meal_feedback_source(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_meal_feedback_read' USING ERRCODE='22023'; END IF;
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM a.epoch THEN '{"action":"stale_epoch"}'::jsonb
  WHEN e.command_id IS NULL THEN '{"action":"absent"}'::jsonb ELSE private.conversation_meal_frozen_feedback_source(e) END INTO result
 FROM private.conversation_meal_command_ids c JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs a ON a.user_id=c.user_id
 LEFT JOIN private.conversation_meal_effects e ON e.user_id=c.user_id AND e.command_id=c.command_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;
CREATE FUNCTION public.read_conversation_meal_feedback_v2(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_meal_feedback_read' USING ERRCODE='22023'; END IF;
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM a.epoch THEN '{"action":"stale_epoch"}'::jsonb
  WHEN e.command_id IS NULL THEN '{"action":"absent"}'::jsonb ELSE private.conversation_meal_feedback_receipt(e) END INTO result
 FROM private.conversation_meal_command_ids c JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs a ON a.user_id=c.user_id
 LEFT JOIN private.conversation_meal_effects e ON e.user_id=c.user_id AND e.command_id=c.command_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;
CREATE FUNCTION public.commit_conversation_meal_feedback_v2(p_user_id uuid,p_command_id uuid,p_expected_effect_version text,p_feedback jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;e private.conversation_meal_effects%ROWTYPE;existing jsonb;source jsonb;registration uuid;binding jsonb;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_command_id);
 IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 SELECT * INTO e FROM private.conversation_meal_effects WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'::jsonb; END IF;
 existing:=private.conversation_meal_feedback_receipt(e);
 IF existing->>'action'='available' THEN RETURN jsonb_build_object('action','replay','feedback',existing->'feedback'); END IF;
 IF existing->>'action' IN('legacy','event_conflict') THEN RETURN existing; END IF;
 IF p_expected_effect_version IS DISTINCT FROM e.receipt->>'effect_version' THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 source:=private.conversation_meal_frozen_feedback_source(e);
 IF source->>'action'<>'available' THEN RETURN source; END IF;
 registration:=(e.receipt->>'registration_id')::uuid;
 -- Parent existence only: later live proposal/log edits do not rewrite history.
 PERFORM 1 FROM public.pending_registrations WHERE id=registration AND user_id=p_user_id AND status='confirmed' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 BEGIN PERFORM private.assert_registration_feedback_v2_sources(p_feedback,e.feedback_context);
 EXCEPTION WHEN data_exception THEN RAISE EXCEPTION 'invalid_conversation_meal_feedback' USING ERRCODE='22023'; END;
 binding:=private.mobile_registration_feedback_v2_source_binding(e.feedback_context);
 INSERT INTO private.mobile_registration_feedback_v2(registration_id,user_id,proposal_hash,source_hash,feedback,command_id)
 VALUES(registration,p_user_id,encode(extensions.digest(convert_to((e.original_facts#>'{confirmed,proposal}')::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(binding::text,'UTF8'),'sha256'),'hex'),p_feedback,p_command_id);
 RETURN jsonb_build_object('action','committed','feedback',p_feedback);
END $$;

-- Preserve the old T2C body for ordinary events, but do not let its live
-- recapture path claim an original command receipt after a C11 edit.
CREATE OR REPLACE FUNCTION public.commit_mobile_registration_feedback_v2(p_user_id uuid,p_registration_id uuid,p_expected_context jsonb,p_feedback jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;existing jsonb;binding jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'feedback_v2_requires_read_committed' USING ERRCODE='22023'; END IF;
 IF p_user_id IS NULL OR p_registration_id IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 -- Same order as capture and protected workout writers. Never hold an owner
 -- SHARE lock from a receipt read before waiting for the workouts lane.
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=p_user_id AND receipt->>'registration_id'=p_registration_id::text)
  OR EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=p_registration_id AND user_id=p_user_id AND proposal->>'command_protocol'='conversation.command.v1')
 THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 existing:=public.read_mobile_registration_feedback_v2(p_user_id,p_registration_id);
 IF existing->>'action'='available' THEN RETURN jsonb_build_object('action','replay','feedback',existing->'feedback'); END IF;
 IF existing->>'action' IN('legacy','event_conflict') THEN RETURN existing; END IF;
 -- Replays above need no current observation, prepared payload or source read.
 c:=private.capture_mobile_registration_feedback_v2(p_user_id,p_registration_id);
 IF c IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 binding:=private.mobile_registration_feedback_v2_source_binding(c);
 IF binding IS DISTINCT FROM private.mobile_registration_feedback_v2_source_binding(p_expected_context) THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 PERFORM private.assert_registration_feedback_v2_sources(p_feedback,c);
 INSERT INTO private.mobile_registration_feedback_v2(registration_id,user_id,proposal_hash,source_hash,feedback)
 VALUES(p_registration_id,p_user_id,encode(extensions.digest(convert_to((c#>'{confirmed,proposal}')::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(binding::text,'UTF8'),'sha256'),'hex'),p_feedback);
 RETURN jsonb_build_object('action','committed','feedback',p_feedback);
END $$;
REVOKE ALL ON FUNCTION private.conversation_meal_frozen_feedback_source(private.conversation_meal_effects),private.conversation_meal_feedback_receipt(private.conversation_meal_effects),
 public.read_conversation_meal_feedback_source(uuid,uuid),public.read_conversation_meal_feedback_v2(uuid,uuid),public.commit_conversation_meal_feedback_v2(uuid,uuid,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_feedback_source(uuid,uuid),public.read_conversation_meal_feedback_v2(uuid,uuid),public.commit_conversation_meal_feedback_v2(uuid,uuid,text,jsonb) TO service_role;
COMMIT;

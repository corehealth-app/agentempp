-- New command admission requires the backend epoch originally bound to the
-- queued intent. The qualified private legacy entrypoint remains unchanged.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'conversation_admission_requires_postgres' USING ERRCODE='42501'; END IF;
 IF to_regprocedure('public.admit_conversation_meal_command(uuid,jsonb)') IS NULL OR
  to_regprocedure('private.lock_conversation_command_owner(uuid)') IS NULL THEN
  RAISE EXCEPTION 'conversation_admission_requires_journal' USING ERRCODE='42883'; END IF;
END $preflight$;

CREATE FUNCTION public.admit_conversation_meal_command_fenced(p_user_id uuid,p_input jsonb,p_expected_epoch uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE e private.workout_strength_authority_epochs%ROWTYPE;c private.conversation_meal_command_ids%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.assert_conversation_meal_input(p_input);
 -- Same owner -> epoch -> command order as reset and the existing writer.
 PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT * INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 SELECT * INTO c FROM private.conversation_meal_command_ids
  WHERE user_id=p_user_id AND command_id=(p_input->>'command_id')::uuid FOR UPDATE;
 -- A reset tombstone wins even when the caller supplies the new epoch or a
 -- changed, otherwise valid input. An old UUID can never become a new intent.
 IF c.command_id IS NOT NULL AND (c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e.epoch) THEN
  RETURN '{"action":"stale_epoch"}'::jsonb;
 END IF;
 -- Do not initialize authority or a command when the original epoch is absent
 -- or unknown. In particular, never retag a never-admitted offline intent.
 IF p_expected_epoch IS NULL OR e.user_id IS NULL OR e.epoch IS DISTINCT FROM p_expected_epoch THEN
  RETURN '{"action":"stale_epoch"}'::jsonb;
 END IF;
 -- All locks are reentrant. The legacy initializer is unreachable because an
 -- existing, matching authority row remains locked until this transaction ends.
 RETURN public.admit_conversation_meal_command(p_user_id,p_input);
END $$;
REVOKE ALL ON FUNCTION public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid) TO service_role;
COMMIT;

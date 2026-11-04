-- Bounded new-command admission budget. Legacy admission remains unchanged.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'conversation_admission_requires_postgres' USING ERRCODE='42501'; END IF;
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)')),'UTF8')),'hex')
  IS DISTINCT FROM 'f02efc866c9164d97ef410019d67aaec6ffae72db21dccd7b056003c7f81268d' THEN
  RAISE EXCEPTION 'conversation_admission_unknown_fenced_source' USING ERRCODE='55000'; END IF;
END $preflight$;

CREATE OR REPLACE FUNCTION public.admit_conversation_meal_command_fenced(p_user_id uuid,p_input jsonb,p_expected_epoch uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE e private.workout_strength_authority_epochs%ROWTYPE;c private.conversation_meal_command_ids%ROWTYPE;admission_clock timestamptz;
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
 -- Existing identities resolve before quota: a stored command never spends a
 -- new admission slot, and changed input remains an input conflict at the cap.
 IF c.command_id IS NOT NULL THEN RETURN public.admit_conversation_meal_command(p_user_id,p_input); END IF;
 -- Reuse Flow's ten/rolling-minute threshold and inclusive lower boundary.
 -- This unit is a fresh command identity in the current epoch, including
 -- negative intents, before any source preparation or physical provider call.
 admission_clock:=clock_timestamp();
 IF (SELECT count(*) FROM private.conversation_meal_command_ids ids
  WHERE ids.user_id=p_user_id AND ids.epoch=e.epoch
   AND ids.admitted_at>=admission_clock-interval '60 seconds')>=10 THEN
  RETURN '{"action":"rate_limited"}'::jsonb;
 END IF;
 -- All locks are reentrant. The legacy initializer is unreachable because an
 -- existing, matching authority row remains locked until this transaction ends.
 RETURN public.admit_conversation_meal_command(p_user_id,p_input);
END $$;
REVOKE ALL ON FUNCTION public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid) TO service_role;
COMMIT;

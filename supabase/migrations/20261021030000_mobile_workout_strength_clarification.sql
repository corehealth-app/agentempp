-- Dormant mobile reader and answer wrapper over confirmed, owned strength facts.
-- No new capture, admission, lifecycle, classification or calorie calculation.
DO $preflight$
BEGIN
 IF CURRENT_USER<>'postgres' THEN
  RAISE EXCEPTION 'mobile_strength_clarification_requires_postgres_owner' USING ERRCODE='42501';
 END IF;
 IF pg_catalog.to_regclass('public.users') IS NULL
  OR pg_catalog.to_regclass('public.workout_logs') IS NULL
  OR pg_catalog.to_regclass('public.daily_snapshots') IS NULL
  OR pg_catalog.to_regclass('private.workout_strength_authority_epochs') IS NULL
  OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
  OR pg_catalog.to_regclass('private.workout_strength_facts') IS NULL
  OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
  OR pg_catalog.to_regprocedure('private.workout_strength_fact_snapshot(uuid,uuid,uuid)') IS NULL
  OR pg_catalog.to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL
 THEN
  RAISE EXCEPTION 'mobile_strength_clarification_requires_existing_substrate' USING ERRCODE='42P01';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN
   ('get_mobile_workout_strength_clarification','answer_mobile_workout_strength_clarification')) THEN
  RAISE EXCEPTION 'mobile_strength_clarification_unknown_existing_object' USING ERRCODE='42P07';
 END IF;
END $preflight$;

CREATE FUNCTION public.get_mobile_workout_strength_clarification(p_user_id uuid,p_workout_log_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $read$
DECLARE
 authority private.workout_strength_authority_epochs%ROWTYPE;
 lifecycle private.workout_strength_lifecycles%ROWTYPE;
 current_workout record;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_workout_log_id IS NULL THEN
  RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
 END IF;
 IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
 END IF;
 -- Each statement takes a fresh RC snapshot after its preceding lock wait.
 SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
  WHERE e.user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS NULL THEN
  RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb;
 END IF;
 SELECT l.* INTO lifecycle FROM private.workout_strength_lifecycles l
  WHERE l.user_id=p_user_id AND l.lifecycle_key=authority.current_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR lifecycle.closed_at IS NOT NULL THEN
  RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb;
 END IF;

 -- One post-lock statement proves live ownership, stored anchor and fact.
 -- Do not filter the fact join by lifecycle: an old fact is stale, not legacy.
 SELECT w.id AS workout_id,s.id AS snapshot_id,f.workout_log_id AS fact_id,
  f.lifecycle_key AS fact_lifecycle,
  private.workout_strength_fact_snapshot(p_user_id,authority.current_lifecycle_key,p_workout_log_id) AS wire
 INTO current_workout
 FROM public.workout_logs w
 LEFT JOIN public.daily_snapshots s ON s.user_id=w.user_id AND s.id=w.snapshot_id
 LEFT JOIN private.workout_strength_facts f ON f.user_id=w.user_id AND f.workout_log_id=w.id
 WHERE w.user_id=p_user_id AND w.id=p_workout_log_id;
 IF NOT FOUND OR current_workout.snapshot_id IS NULL THEN
  RETURN '{"status":"forbidden","reason":"stale_workout"}'::jsonb;
 END IF;
 IF current_workout.fact_id IS NULL THEN
  RETURN '{"status":"unavailable","reason":"provenance_gap"}'::jsonb;
 END IF;
 IF current_workout.fact_lifecycle IS DISTINCT FROM authority.current_lifecycle_key
  OR current_workout.wire IS NULL THEN
  RETURN '{"status":"forbidden","reason":"stale_workout"}'::jsonb;
 END IF;
 RETURN pg_catalog.jsonb_build_object('status','available','workoutLogID',current_workout.workout_id,
  'lifecycleKey',authority.current_lifecycle_key,'factRevision',current_workout.wire->'revision',
  'clarification',current_workout.wire->'clarification');
END $read$;

CREATE FUNCTION public.answer_mobile_workout_strength_clarification(
 p_user_id uuid,p_expected_lifecycle_key uuid,p_workout_log_id uuid,
 p_expected_fact_revision integer,p_question_key uuid,p_answer text,p_operation_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $answer$
DECLARE
 authority private.workout_strength_authority_epochs%ROWTYPE;
 lifecycle private.workout_strength_lifecycles%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_expected_lifecycle_key IS NULL OR p_workout_log_id IS NULL
  OR p_expected_fact_revision IS NULL OR p_expected_fact_revision<0 OR p_question_key IS NULL
  OR p_answer IS NULL OR (p_answer COLLATE "C") NOT IN ('yes','no')
  OR p_operation_key IS NULL OR p_operation_key='' THEN
  RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
 END IF;
 IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
 END IF;
 SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
  WHERE e.user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS DISTINCT FROM p_expected_lifecycle_key THEN
  RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb;
 END IF;
 SELECT l.* INTO lifecycle FROM private.workout_strength_lifecycles l
  WHERE l.user_id=p_user_id AND l.lifecycle_key=authority.current_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR lifecycle.closed_at IS NOT NULL THEN
  RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb;
 END IF;
 -- S9 resolves the immutable original operation before mutable revision CAS.
 -- Never replace the submitted revision with the reader's current revision.
 RETURN public.answer_confirmed_workout_strength(p_user_id,p_expected_lifecycle_key,p_workout_log_id,
  p_expected_fact_revision,p_question_key,p_answer,p_operation_key);
END $answer$;

REVOKE ALL ON FUNCTION public.get_mobile_workout_strength_clarification(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.answer_mobile_workout_strength_clarification(uuid,uuid,uuid,integer,uuid,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_workout_strength_clarification(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.answer_mobile_workout_strength_clarification(uuid,uuid,uuid,integer,uuid,text,text) TO service_role;
COMMENT ON FUNCTION public.get_mobile_workout_strength_clarification(uuid,uuid) IS
 'Backend-only current owned workout clarification; no capture selection, authority adoption or classification refresh.';
COMMENT ON FUNCTION public.answer_mobile_workout_strength_clarification(uuid,uuid,uuid,integer,uuid,text,text) IS
 'Backend-only CURRENT authority guard before unchanged atomic strength answer/replay; preserves original attempt revision.';

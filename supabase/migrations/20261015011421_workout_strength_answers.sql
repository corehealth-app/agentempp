-- Dormant F2 writer. First answer and original operation receipt commit together.
-- Existing capture, legacy writer, consumers and grants remain unchanged.
DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_operations') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_facts') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR pg_catalog.to_regprocedure('private.workout_strength_fact_snapshot(uuid,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_answers_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='answer_confirmed_workout_strength') THEN
    RAISE EXCEPTION 'workout_strength_answers_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE FUNCTION public.answer_confirmed_workout_strength(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_workout_log_id uuid,
  p_expected_fact_revision integer,p_question_key uuid,p_answer text,p_operation_key text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $answer$
DECLARE
  current_fact private.workout_strength_facts%ROWTYPE;
  answer_operation private.workout_strength_operations%ROWTYPE;
  current_wire jsonb;
  original_wire jsonb;
  receipt jsonb;
  recorded_at timestamptz;
  first_answer boolean;
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
  PERFORM 1 FROM private.workout_strength_lifecycles l
    WHERE l.user_id=p_user_id AND l.lifecycle_key=p_expected_lifecycle_key AND l.closed_at IS NULL;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle');
  END IF;

  SELECT f.* INTO current_fact FROM private.workout_strength_facts f
    WHERE f.user_id=p_user_id AND f.lifecycle_key=p_expected_lifecycle_key
      AND f.workout_log_id=p_workout_log_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_workout');
  END IF;
  current_wire:=private.workout_strength_fact_snapshot(p_user_id,p_expected_lifecycle_key,p_workout_log_id);
  IF current_wire IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_workout');
  END IF;
  IF current_fact.classification_status<>'unrecognized' THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','not_unrecognized');
  END IF;
  IF current_fact.question_key IS DISTINCT FROM p_question_key THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_fact');
  END IF;

  SELECT o.* INTO answer_operation FROM private.workout_strength_operations o
    WHERE o.user_id=p_user_id AND o.lifecycle_key=p_expected_lifecycle_key
      AND o.operation_kind='answer' AND o.operation_key=(p_operation_key COLLATE "C");
  IF FOUND THEN
    IF answer_operation.live_workout_log_id IS DISTINCT FROM answer_operation.original_workout_log_id THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_workout');
    END IF;
    -- Check the binding's ORIGINAL fact, even when the request names another live target.
    original_wire:=private.workout_strength_fact_snapshot(
      p_user_id,p_expected_lifecycle_key,answer_operation.original_workout_log_id);
    IF original_wire IS NULL
      OR original_wire#>>'{clarification,status}' IS DISTINCT FROM 'answered'
      OR answer_operation.answer_receipt IS DISTINCT FROM original_wire#>'{clarification,receipt}' THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_workout');
    END IF;
    IF answer_operation.original_workout_log_id IS DISTINCT FROM p_workout_log_id
      OR answer_operation.answer_expected_revision IS DISTINCT FROM p_expected_fact_revision
      OR answer_operation.answer_question_key IS DISTINCT FROM p_question_key
      OR answer_operation.answer_value IS DISTINCT FROM (p_answer COLLATE "C") THEN
      RETURN pg_catalog.jsonb_build_object('status','conflict','reason','operation_content_conflict');
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','reuse_existing','receipt',answer_operation.answer_receipt);
  END IF;

  -- The mutable CAS applies only after original-operation replay has been resolved.
  IF current_fact.revision<>p_expected_fact_revision THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','stale_fact');
  END IF;
  first_answer:=current_fact.revision=0;
  IF NOT first_answer AND current_fact.answer IS DISTINCT FROM (p_answer COLLATE "C") THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','answer_already_differs');
  END IF;
  recorded_at:=pg_catalog.clock_timestamp();
  IF first_answer THEN
    UPDATE private.workout_strength_facts f
      SET answer=p_answer,answer_operation_key=p_operation_key,answer_accepted_at=recorded_at,revision=1
      WHERE f.user_id=p_user_id AND f.lifecycle_key=p_expected_lifecycle_key
        AND f.workout_log_id=p_workout_log_id AND f.revision=0;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'workout_strength_answer_fact_changed' USING ERRCODE='P0002';
    END IF;
    current_wire:=private.workout_strength_fact_snapshot(p_user_id,p_expected_lifecycle_key,p_workout_log_id);
  END IF;
  receipt:=current_wire#>'{clarification,receipt}';
  IF current_wire#>>'{clarification,status}' IS DISTINCT FROM 'answered' OR receipt IS NULL THEN
    RAISE EXCEPTION 'workout_strength_answer_receipt_unproved' USING ERRCODE='P0002';
  END IF;
  -- B retains its original CAS/content while its receipt may name winning operation A.
  -- Any insertion error propagates and rolls back the preceding fact update too.
  INSERT INTO private.workout_strength_operations(
    user_id,lifecycle_key,operation_kind,operation_key,original_workout_log_id,live_workout_log_id,
    created_at,answer_expected_revision,answer_question_key,answer_value,answer_receipt
  ) VALUES (
    p_user_id,p_expected_lifecycle_key,'answer',p_operation_key,p_workout_log_id,p_workout_log_id,
    recorded_at,p_expected_fact_revision,p_question_key,p_answer,receipt
  );
  RETURN pg_catalog.jsonb_build_object('status',CASE WHEN first_answer THEN 'accepted' ELSE 'reuse_existing' END,
    'receipt',receipt);
END;
$answer$;
REVOKE ALL ON FUNCTION public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)
  TO service_role;
COMMENT ON FUNCTION public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text) IS
  'Backend-only first strength answer with live owned authority, original canonical replay and atomic immutable receipt.';

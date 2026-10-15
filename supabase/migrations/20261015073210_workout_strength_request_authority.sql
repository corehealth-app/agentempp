-- Dormant durable authority for enabled Flow requests; no caller or cutover.
-- Install as postgres. The reset replacement below preserves the S14 body.
BEGIN;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'workout_strength_authority_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('public.messages') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR pg_catalog.to_regprocedure('public.reset_user_conversation_atomic(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_authority_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF pg_catalog.to_regclass('private.workout_strength_authority_epochs') IS NOT NULL
    OR pg_catalog.to_regclass('private.workout_strength_request_admissions') IS NOT NULL
    OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN
        ('admit_workout_strength_request','initialize_workout_strength_lifecycle')
    ) THEN
    RAISE EXCEPTION 'workout_strength_authority_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE TABLE private.workout_strength_authority_epochs (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  epoch uuid NOT NULL,
  current_lifecycle_key uuid,
  changed_at timestamptz NOT NULL,
  CONSTRAINT workout_strength_authority_epochs_clock_check
    CHECK (pg_catalog.isfinite(changed_at))
);
CREATE TABLE private.workout_strength_request_admissions (
  user_id uuid NOT NULL,
  admission_id uuid NOT NULL,
  request_namespace text COLLATE "C" NOT NULL,
  request_key text COLLATE "C" NOT NULL,
  request_hash text NOT NULL,
  epoch uuid NOT NULL,
  admitted_at timestamptz NOT NULL,
  original_inbound_id uuid,
  lifecycle_key uuid,
  PRIMARY KEY(user_id,request_namespace,request_key),
  UNIQUE(user_id,admission_id),
  CONSTRAINT workout_strength_request_admissions_owner_fk FOREIGN KEY(user_id)
    REFERENCES private.workout_strength_authority_epochs(user_id) ON DELETE CASCADE,
  CONSTRAINT workout_strength_request_admissions_shape_check CHECK ((
    request_namespace='mobile_flow_turn'
    AND (request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$'
    AND (request_hash COLLATE "C") ~ '^[0-9a-f]{64}$'
    AND pg_catalog.isfinite(admitted_at)
    AND ((original_inbound_id IS NULL)=(lifecycle_key IS NULL))
  ) IS TRUE)
);
ALTER TABLE private.workout_strength_authority_epochs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.workout_strength_request_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.workout_strength_authority_epochs,
  private.workout_strength_request_admissions FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.admit_workout_strength_request(
  p_user_id uuid,p_request_key text,p_request_hash text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $admit$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.workout_strength_request_admissions%ROWTYPE;
  admission_status text:='reused';
  admitted_clock timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_request_key IS NULL OR p_request_hash IS NULL
    OR NOT ((p_request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$')
    OR NOT ((p_request_hash COLLATE "C") ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u
    WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
  END IF;

  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
    WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    admitted_clock:=pg_catalog.clock_timestamp();
    INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
      VALUES(p_user_id,pg_catalog.gen_random_uuid(),admitted_clock)
      RETURNING * INTO authority;
  END IF;
  SELECT a.* INTO admission FROM private.workout_strength_request_admissions a
    WHERE a.user_id=p_user_id AND a.request_namespace='mobile_flow_turn'
      AND a.request_key=(p_request_key COLLATE "C") FOR UPDATE;
  IF FOUND THEN
    -- An old key never acquires a new epoch, even with a changed payload.
    IF admission.epoch IS DISTINCT FROM authority.epoch THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_epoch');
    END IF;
    IF admission.request_hash IS DISTINCT FROM p_request_hash THEN
      RETURN pg_catalog.jsonb_build_object('status','conflict','reason','request_content_conflict');
    END IF;
  ELSE
    admitted_clock:=pg_catalog.clock_timestamp();
    INSERT INTO private.workout_strength_request_admissions(
      user_id,admission_id,request_namespace,request_key,request_hash,epoch,admitted_at
    ) VALUES(p_user_id,pg_catalog.gen_random_uuid(),'mobile_flow_turn',p_request_key,
      p_request_hash,authority.epoch,admitted_clock) RETURNING * INTO admission;
    admission_status:='admitted';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',admission_status,'admission',
    pg_catalog.jsonb_build_object('ownerID',admission.user_id::text,
      'admissionID',admission.admission_id::text,'epoch',admission.epoch::text,
      'requestNamespace',admission.request_namespace,'requestKey',admission.request_key,
      'requestHash',admission.request_hash,'admittedAt',
      pg_catalog.to_char(admission.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END;
$admit$;
REVOKE ALL ON FUNCTION public.admit_workout_strength_request(uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_workout_strength_request(uuid,text,text) TO service_role;

CREATE FUNCTION public.initialize_workout_strength_lifecycle(
  p_user_id uuid,p_admission_id uuid,p_original_inbound_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $initialize$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.workout_strength_request_admissions%ROWTYPE;
  life private.workout_strength_lifecycles%ROWTYPE;
  bound_admission boolean;
  expected_life_key uuid;
  lifecycle_status text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_admission_id IS NULL OR p_original_inbound_id IS NULL THEN
    RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u
    WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
  END IF;

  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
    WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','invalid_admission');
  END IF;
  SELECT a.* INTO admission FROM private.workout_strength_request_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=p_admission_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','invalid_admission');
  END IF;
  IF admission.epoch IS DISTINCT FROM authority.epoch THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_epoch');
  END IF;
  bound_admission:=admission.original_inbound_id IS NOT NULL;
  IF bound_admission AND admission.original_inbound_id IS DISTINCT FROM p_original_inbound_id THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','inbound_mismatch');
  END IF;

  -- Validate the real owned inbound, not just a caller-supplied UUID/hash.
  -- SHARE keeps its checked content/identity stable through this transaction.
  PERFORM m.id FROM public.messages m
    WHERE m.id=p_original_inbound_id AND m.user_id=p_user_id
      AND m.direction='in' AND m.role='user' AND m.content_type='text'
      AND (m.provider COLLATE "C")='mobile_flow'
      AND (m.provider_message_id COLLATE "C")=
        (('mobile_flow/'||p_user_id::text||'/'||admission.request_key) COLLATE "C")
      AND m.content IS NOT NULL
      AND (pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(m.content,'UTF8')),'hex') COLLATE "C")=
        (admission.request_hash COLLATE "C")
    FOR SHARE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','inbound_mismatch');
  END IF;

  expected_life_key:=CASE WHEN bound_admission THEN admission.lifecycle_key
    ELSE authority.current_lifecycle_key END;
  IF expected_life_key IS NOT NULL THEN
    SELECT l.* INTO life FROM private.workout_strength_lifecycles l
      WHERE l.user_id=p_user_id AND l.lifecycle_key=expected_life_key FOR UPDATE;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','unproved_lifecycle');
    END IF;
    IF life.closed_at IS NOT NULL THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle');
    END IF;
    IF bound_admission AND authority.current_lifecycle_key IS DISTINCT FROM life.lifecycle_key THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle');
    END IF;
  ELSE
    -- A life with no persisted current-epoch pointer is never adopted.
    PERFORM l.lifecycle_key FROM private.workout_strength_lifecycles l
      WHERE l.user_id=p_user_id AND l.closed_at IS NULL;
    IF FOUND THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','unproved_lifecycle');
    END IF;
    INSERT INTO private.workout_strength_lifecycles(user_id,lifecycle_key,opened_at)
      VALUES(p_user_id,pg_catalog.gen_random_uuid(),pg_catalog.clock_timestamp())
      RETURNING * INTO life;
    UPDATE private.workout_strength_authority_epochs
      SET current_lifecycle_key=life.lifecycle_key
      WHERE user_id=p_user_id RETURNING * INTO STRICT authority;
  END IF;

  IF bound_admission THEN
    lifecycle_status:='reused';
  ELSE
    UPDATE private.workout_strength_request_admissions
      SET original_inbound_id=p_original_inbound_id,lifecycle_key=life.lifecycle_key
      WHERE user_id=p_user_id AND admission_id=p_admission_id
        AND original_inbound_id IS NULL AND lifecycle_key IS NULL
      RETURNING * INTO STRICT admission;
    lifecycle_status:='initialized';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',lifecycle_status,'lifecycle',
    pg_catalog.jsonb_build_object('ownerID',life.user_id::text,
      'lifecycleKey',life.lifecycle_key::text,'openedAt',
      pg_catalog.to_char(life.opened_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END;
$initialize$;
REVOKE ALL ON FUNCTION public.initialize_workout_strength_lifecycle(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.initialize_workout_strength_lifecycle(uuid,uuid,uuid) TO service_role;

-- Same S14 reset definition, with one owner-scoped epoch update.
CREATE OR REPLACE FUNCTION public.reset_user_conversation_atomic(
  p_user_id uuid,
  p_keep_plans boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_deleted integer;
  v_deleted_total integer := 0;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR p_keep_plans IS NULL THEN
    RAISE EXCEPTION 'invalid reset request' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text || ':workouts', 0)
  );

  PERFORM 1
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user % not found', p_user_id;
  END IF;

  -- Retain old admissions and invalidate their authority even without a life.
  UPDATE private.workout_strength_authority_epochs
  SET epoch = pg_catalog.gen_random_uuid(),
      current_lifecycle_key = NULL,
      changed_at = pg_catalog.clock_timestamp()
  WHERE user_id = p_user_id;

  UPDATE private.workout_strength_lifecycles
  SET closed_at = pg_catalog.clock_timestamp(),
      close_operation_key = 'reset_user_conversation:' || pg_catalog.gen_random_uuid()::text
  WHERE user_id = p_user_id
    AND closed_at IS NULL;

  DELETE FROM public.pending_registrations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_dispatch_outbox WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_buffer WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.tools_audit WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.llm_evaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_gap_reminder_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.engagement_delivery_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.attention_dismissals WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_phrase_cooldown WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_food_corrections WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  IF NOT p_keep_plans THEN
    -- Everything of the plans goes, drafts included (their documents stay:
    -- the patient removes them).
    DELETE FROM public.plan_drafts WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_deleted_total := v_deleted_total + v_deleted;

    DELETE FROM public.prescriptions WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_deleted_total := v_deleted_total + v_deleted;

    DELETE FROM public.training_plans WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_deleted_total := v_deleted_total + v_deleted;
  END IF;

  DELETE FROM public.reevaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.meal_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.workout_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_snapshots WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.messages WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.product_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  INSERT INTO public.user_profiles (
    user_id,
    onboarding_completed,
    onboarding_step
  ) VALUES (
    p_user_id,
    false,
    0
  )
  ON CONFLICT (user_id) DO UPDATE
  SET sex = null,
      birth_date = null,
      height_cm = null,
      weight_kg = null,
      body_fat_percent = null,
      body_fat_measured_at = null,
      activity_level = null,
      training_frequency = null,
      water_intake = null,
      hunger_level = null,
      wake_time = null,
      bedtime = null,
      current_protocol = null,
      goal_type = null,
      goal_value = null,
      deficit_level = null,
      food_organization = null,
      bf_percent_estimated = null,
      bf_source = null,
      bf_estimated_at = null,
      cycle_start_weight_kg = null,
      cycle_start_bf_percent = null,
      cycle_start_training_freq = null,
      cycle_start_at = null,
      onboarding_completed = false,
      onboarding_step = 0,
      updated_at = now();

  INSERT INTO public.user_progress (
    user_id,
    xp_total,
    level,
    current_streak,
    longest_streak,
    blocks_completed,
    deficit_block,
    badges_earned
  ) VALUES (
    p_user_id,
    0,
    1,
    0,
    0,
    0,
    0,
    '{}'::text[]
  )
  ON CONFLICT (user_id) DO UPDATE
  SET xp_total = 0,
      level = 1,
      current_streak = 0,
      longest_streak = 0,
      blocks_completed = 0,
      deficit_block = 0,
      current_weight = null,
      current_bf_percent = null,
      badges_earned = '{}'::text[],
      last_active_date = null,
      next_reevaluation = null,
      updated_at = now();

  UPDATE public.users
  SET name = null,
      flow_phrase_cursor_revision = 0,
      summary = null,
      summary_updated_at = null,
      tags = '{}'::text[],
      admin_notes = null,
      country_confirmed = false,
      last_active_at = null,
      -- The daily delivery of a kept training plan keeps its settings.
      metadata = CASE
        WHEN p_keep_plans THEN jsonb_strip_nulls(jsonb_build_object(
          'training_reminders', metadata -> 'training_reminders',
          'training_delivery_hour', metadata -> 'training_delivery_hour'
        ))
        ELSE '{}'::jsonb
      END,
      updated_at = now()
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'reset', true,
    'user_id', p_user_id,
    'deleted_rows', v_deleted_total,
    'kept_plans', p_keep_plans
  );
END;
$$;

-- Reject inherited privileges outside the exact new backend surface.
-- Do not silently revoke unknown grantees or alter default/global privileges.
DO $privileges$
DECLARE
  postgres_owner oid:='postgres'::regrole::oid;
  service_grantee oid:='service_role'::regrole::oid;
BEGIN
  IF EXISTS (
    WITH objects AS (
      SELECT 'r'::pg_catalog."char" AS kind,c.oid,c.relowner AS owner_id,c.relacl AS acl
      FROM pg_catalog.pg_class c WHERE c.oid IN (
        'private.workout_strength_authority_epochs'::regclass,
        'private.workout_strength_request_admissions'::regclass)
      UNION ALL
      SELECT 'f'::pg_catalog."char",p.oid,p.proowner,p.proacl
      FROM pg_catalog.pg_proc p WHERE p.oid IN (
        'public.admit_workout_strength_request(uuid,text,text)'::regprocedure,
        'public.initialize_workout_strength_lifecycle(uuid,uuid,uuid)'::regprocedure)
    ), actual AS (
      SELECT o.kind,o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL
        pg_catalog.aclexplode(COALESCE(o.acl,pg_catalog.acldefault(o.kind,o.owner_id))) a
    ), expected AS (
      SELECT o.kind,o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL
        pg_catalog.aclexplode(pg_catalog.acldefault(o.kind,postgres_owner)) a
      WHERE a.grantee=postgres_owner
      UNION ALL
      SELECT o.kind,o.oid,postgres_owner,service_grantee,'EXECUTE'::text,false
      FROM objects o WHERE o.kind='f'::pg_catalog."char"
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL
      (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    )
    SELECT 1 FROM objects WHERE owner_id<>postgres_owner
    UNION ALL
    SELECT 1 FROM differences
  ) THEN
    RAISE EXCEPTION 'C59S15_UNEXPECTED_OBJECT_ACL' USING ERRCODE='42501';
  END IF;
END $privileges$;

COMMIT;

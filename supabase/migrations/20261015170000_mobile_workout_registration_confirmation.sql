-- Dormant UI confirmation: owned revision, S7 preparation and the real S8 writer
-- commit together. No caller, formula change or modification of the closed cores.
BEGIN;

DO $preflight$
BEGIN
  IF CURRENT_USER<>'postgres' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('private.mobile_workout_proposal_admissions') IS NULL
    OR pg_catalog.to_regclass('private.mobile_workout_registration_edit_receipts') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_commands') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_operations') IS NULL
    OR pg_catalog.to_regclass('public.pending_registrations') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR pg_catalog.to_regprocedure('public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)') IS NULL
    OR pg_catalog.to_regprocedure('private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb)') IS NULL
    OR pg_catalog.to_regprocedure('public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='confirm_mobile_workout_registration') THEN
    RAISE EXCEPTION 'mobile_workout_registration_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE FUNCTION public.confirm_mobile_workout_registration(
  p_user_id uuid,p_registration_id uuid,p_expected_revision integer,
  p_legacy_arguments jsonb,p_catalogue_observation jsonb,p_catalogue_decision jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $confirm$
DECLARE
  v_authority private.workout_strength_authority_epochs%ROWTYPE;
  v_admission private.mobile_workout_proposal_admissions%ROWTYPE;
  v_match private.mobile_workout_proposal_admissions%ROWTYPE;
  v_pending public.pending_registrations%ROWTYPE;
  v_lifecycle private.workout_strength_lifecycles%ROWTYPE;
  v_command private.workout_strength_commands%ROWTYPE;
  v_operation private.workout_strength_operations%ROWTYPE;
  v_admission_count integer:=0;
  v_lifecycle_key uuid;
  v_operation_key text;
  v_raw_type text;
  v_provider text;
  v_now timestamptz;
  v_source_instant timestamptz;
  v_performed_instant timestamptz;
  v_registration jsonb;
  v_arguments jsonb;
  v_capture jsonb;
  v_strength jsonb;
  v_resolved jsonb;
  v_gap jsonb;
  v_legacy_result jsonb;
  v_own_negative boolean:=false;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_registration_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0 THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_read_committed' USING ERRCODE='22023';
  END IF;
  -- S8 takes this lock first, even on replay. Never invert its global order.
  LOCK TABLE public.workout_types IN SHARE MODE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_workout_proposal_patient_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.* INTO v_authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
  FOR v_match IN SELECT a.* FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.pending_id=p_registration_id ORDER BY a.admission_id FOR UPDATE LOOP
    v_admission:=v_match;
    v_admission_count:=v_admission_count+1;
  END LOOP;
  IF v_admission_count<>1 OR v_admission.content_revision IS NULL OR v_authority.user_id IS NULL THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  IF v_admission.epoch IS DISTINCT FROM v_authority.epoch THEN
    RETURN '{"status":"forbidden","reason":"stale_epoch"}'::jsonb;
  END IF;
  -- Observe terminal updates or deletion committed during this row wait.
  SELECT p.* INTO v_pending FROM public.pending_registrations p
    WHERE p.user_id=p_user_id AND p.id=p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"pending_missing"}'::jsonb; END IF;
  IF v_pending.workout_ui_admission_id IS DISTINCT FROM v_admission.admission_id
    OR v_admission.pending_id IS DISTINCT FROM v_pending.id
    OR (v_admission.confirmed_lifecycle_key IS NOT NULL AND v_pending.status<>'confirmed') THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  v_provider:=v_pending.proposal->>'source_provider_message_id';
  IF (v_admission.content_revision=0 AND
      (v_provider COLLATE "C") IS DISTINCT FROM (v_admission.request_key COLLATE "C"))
    OR (v_admission.content_revision>0 AND NOT EXISTS (
      SELECT 1 FROM private.mobile_workout_registration_edit_receipts r
      WHERE r.user_id=p_user_id AND r.admission_id=v_admission.admission_id
        AND r.request_key=(v_provider COLLATE "C") AND r.result_revision=v_admission.content_revision)) THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  v_registration:=pg_catalog.jsonb_build_object('id',v_pending.id,'status',v_pending.status,
    'created_at',v_pending.created_at,'expires_at',v_pending.expires_at,'resolved_at',v_pending.resolved_at,
    'proposal',v_pending.proposal,'workout_protocol','ui-v1','content_revision',v_admission.content_revision);
  v_operation_key:='ui:'||v_admission.admission_id::text||':r:'||v_admission.content_revision::text;
  v_raw_type:=v_pending.proposal->>'workoutType';

  IF v_pending.status='confirmed' THEN
    IF v_admission.content_revision<>p_expected_revision THEN
      RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_conflict','registration',v_registration);
    END IF;
    v_lifecycle_key:=v_admission.confirmed_lifecycle_key;
    IF v_lifecycle_key IS NULL THEN RETURN '{"status":"forbidden","reason":"invalid_confirmation"}'::jsonb; END IF;
    SELECT l.* INTO v_lifecycle FROM private.workout_strength_lifecycles l
      WHERE l.user_id=p_user_id AND l.lifecycle_key=v_lifecycle_key FOR UPDATE;
    IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb; END IF;
    IF v_lifecycle.closed_at IS NOT NULL OR v_authority.current_lifecycle_key IS DISTINCT FROM v_lifecycle_key THEN
      RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb;
    END IF;
    -- A missing binding is never permission to re-enter a writer on replay.
    SELECT o.* INTO v_operation FROM private.workout_strength_operations o
      WHERE o.user_id=p_user_id AND o.lifecycle_key=v_lifecycle_key AND o.operation_kind='capture'
        AND o.operation_key=(v_operation_key COLLATE "C") AND o.original_operation_type=(v_raw_type COLLATE "C");
    IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"invalid_confirmation"}'::jsonb; END IF;
    v_resolved:=public.resolve_confirmed_workout_strength_capture(p_user_id,v_lifecycle_key,v_operation_key,v_raw_type);
    IF v_resolved->>'status'='forbidden' THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason',v_resolved->>'reason');
    END IF;
    v_gap:=pg_catalog.jsonb_build_object('status','unavailable','reason','legacy_provenance_gap',
      'confirmedWorkoutLogID',v_operation.live_workout_log_id::text);
    IF (v_operation.capture_outcome='fact' AND v_resolved->>'status' IS DISTINCT FROM 'reuse_existing')
      OR (v_operation.capture_outcome='legacy_provenance_gap' AND v_resolved IS DISTINCT FROM v_gap) THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','reused','registration',v_registration,'capture',
      pg_catalog.jsonb_build_object('legacy_result',v_operation.legacy_result,'strength',v_resolved));
  END IF;
  IF v_pending.status<>'pending' THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','not_pending','registration',v_registration);
  END IF;
  IF v_admission.content_revision<>p_expected_revision THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_conflict','registration',v_registration);
  END IF;

  v_lifecycle_key:=v_authority.current_lifecycle_key;
  IF v_lifecycle_key IS NOT NULL THEN
    SELECT l.* INTO v_lifecycle FROM private.workout_strength_lifecycles l
      WHERE l.user_id=p_user_id AND l.lifecycle_key=v_lifecycle_key FOR UPDATE;
    IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb; END IF;
    IF v_lifecycle.closed_at IS NOT NULL THEN RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb; END IF;
  ELSE
    PERFORM 1 FROM private.workout_strength_lifecycles l WHERE l.user_id=p_user_id AND l.closed_at IS NULL FOR UPDATE;
    IF FOUND THEN RETURN '{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb; END IF;
  END IF;
  -- TTL is a wall clock after all authority/lifecycle row waits, not transaction now().
  v_now:=pg_catalog.clock_timestamp();
  IF v_pending.expires_at<=v_now THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','expired','registration',v_registration);
  END IF;
  IF v_lifecycle_key IS NOT NULL THEN
    SELECT c.* INTO v_command FROM private.workout_strength_commands c
      WHERE c.user_id=p_user_id AND c.lifecycle_key=v_lifecycle_key
        AND c.operation_key=(v_operation_key COLLATE "C") AND c.original_operation_type=(v_raw_type COLLATE "C");
  END IF;
  IF v_command.user_id IS NULL AND p_legacy_arguments IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','preparation_required','registration',v_registration);
  END IF;

  -- Only this block may mutate. A legitimate negative from S8 must undo even
  -- the life and S7 preparation before its JSON result can leave the function.
  BEGIN
    IF v_lifecycle_key IS NULL THEN
      v_lifecycle_key:=pg_catalog.gen_random_uuid();
      INSERT INTO private.workout_strength_lifecycles(user_id,lifecycle_key,opened_at)
        VALUES(p_user_id,v_lifecycle_key,pg_catalog.clock_timestamp());
      UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=v_lifecycle_key
        WHERE user_id=p_user_id AND epoch=v_admission.epoch RETURNING * INTO STRICT v_authority;
    END IF;
    PERFORM public.read_or_admit_workout_strength_command(
      p_user_id,v_lifecycle_key,v_operation_key,v_raw_type,p_legacy_arguments);
    SELECT c.* INTO STRICT v_command FROM private.workout_strength_commands c
      WHERE c.user_id=p_user_id AND c.lifecycle_key=v_lifecycle_key
        AND c.operation_key=(v_operation_key COLLATE "C") AND c.original_operation_type=(v_raw_type COLLATE "C");
    v_arguments:=v_command.legacy_arguments;
    -- Cast only the chosen S7 value; do not reconstruct or normalize its JSONB.
    -- This narrow decoder never catches errors from S7, locks or the real writer.
    BEGIN
      v_source_instant:=(v_pending.proposal->>'source_timestamp')::timestamptz;
      v_performed_instant:=(v_arguments->>'p_performed_at')::timestamptz;
      IF (v_arguments->>'p_user_id')::uuid IS DISTINCT FROM p_user_id
        OR ((v_arguments->>'p_workout_type') COLLATE "C") IS DISTINCT FROM (v_raw_type COLLATE "C")
        OR (v_arguments->>'p_duration_min')::numeric IS DISTINCT FROM (v_pending.proposal->>'durationMin')::numeric
        OR v_arguments->'p_intensity' IS DISTINCT FROM v_pending.proposal->'intensity'
        OR ((v_arguments->>'p_provider_message_id') COLLATE "C") IS DISTINCT FROM (v_provider COLLATE "C")
        OR v_source_instant IS NULL OR NOT pg_catalog.isfinite(v_source_instant)
        OR v_performed_instant IS NULL OR NOT pg_catalog.isfinite(v_performed_instant)
        OR v_performed_instant IS DISTINCT FROM v_source_instant
        OR v_arguments->'p_replace_recent' IS DISTINCT FROM 'false'::jsonb
        OR v_arguments->'p_replace_since' IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'invalid_mobile_workout_registration_preparation' USING ERRCODE='22023';
      END IF;
    EXCEPTION WHEN data_exception THEN
      RAISE EXCEPTION 'invalid_mobile_workout_registration_preparation' USING ERRCODE='22023';
    END;
    -- kcal, targets, notes and date remain the first official preparation.
    -- The current producer recalculates them; preview equality is not required.
    v_capture:=private.register_workout_strength_core(
      p_user_id,v_lifecycle_key,v_operation_key,v_raw_type,p_catalogue_observation,p_catalogue_decision);
    IF pg_catalog.jsonb_typeof(v_capture) IS DISTINCT FROM 'object'
      OR NOT (v_capture ?& ARRAY['legacy_result','strength'])
      OR v_capture-ARRAY['legacy_result','strength']<>'{}'::jsonb
      OR pg_catalog.jsonb_typeof(v_capture->'strength') IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    v_strength:=v_capture->'strength';
    IF NOT (COALESCE(v_strength->>'status' IN ('committed','reuse_existing'),false)
      OR (v_strength->>'status'='unavailable' AND v_strength->>'reason'='legacy_provenance_gap')) THEN
      IF v_strength->>'status' IN ('forbidden','conflict','unavailable') THEN
        v_own_negative:=true;
        RAISE EXCEPTION 'mobile_workout_registration_capture_not_accepted' USING ERRCODE='P17D0';
      END IF;
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    SELECT o.* INTO v_operation FROM private.workout_strength_operations o
      WHERE o.user_id=p_user_id AND o.lifecycle_key=v_lifecycle_key AND o.operation_kind='capture'
        AND o.operation_key=(v_operation_key COLLATE "C") AND o.original_operation_type=(v_raw_type COLLATE "C");
    IF NOT FOUND THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    v_resolved:=public.resolve_confirmed_workout_strength_capture(p_user_id,v_lifecycle_key,v_operation_key,v_raw_type);
    v_legacy_result:=COALESCE(v_operation.legacy_result,'null'::jsonb);
    v_gap:=pg_catalog.jsonb_build_object('status','unavailable','reason','legacy_provenance_gap',
      'confirmedWorkoutLogID',v_operation.live_workout_log_id::text);
    IF (v_capture->'legacy_result')::text IS DISTINCT FROM v_legacy_result::text
      OR (v_operation.capture_outcome='fact' AND (
        NOT COALESCE(v_strength->>'status' IN ('committed','reuse_existing'),false)
        OR v_resolved->>'status' IS DISTINCT FROM 'reuse_existing'
        OR (v_strength||'{"status":"reuse_existing"}'::jsonb) IS DISTINCT FROM v_resolved))
      OR (v_operation.capture_outcome='legacy_provenance_gap' AND
        (v_strength IS DISTINCT FROM v_gap OR v_resolved IS DISTINCT FROM v_gap)) THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=v_lifecycle_key
      WHERE user_id=p_user_id AND admission_id=v_admission.admission_id AND content_revision=p_expected_revision
      RETURNING * INTO STRICT v_admission;
    UPDATE public.pending_registrations SET status='confirmed',resolved_at=pg_catalog.clock_timestamp()
      WHERE user_id=p_user_id AND id=p_registration_id AND status='pending' RETURNING * INTO STRICT v_pending;
  EXCEPTION WHEN SQLSTATE 'P17D0' THEN
    -- A native P17D0 from a writer/trigger is not our control signal.
    IF NOT v_own_negative THEN RAISE; END IF;
  END;
  IF v_own_negative THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','capture_not_accepted',
      'registration',v_registration,'capture',v_capture);
  END IF;
  v_registration:=pg_catalog.jsonb_build_object('id',v_pending.id,'status',v_pending.status,
    'created_at',v_pending.created_at,'expires_at',v_pending.expires_at,'resolved_at',v_pending.resolved_at,
    'proposal',v_pending.proposal,'workout_protocol','ui-v1','content_revision',v_admission.content_revision);
  RETURN pg_catalog.jsonb_build_object('status','confirmed','registration',v_registration,'capture',v_capture);
END $confirm$;
REVOKE ALL ON FUNCTION public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb) TO service_role;

DO $privileges$
BEGIN
  IF EXISTS (
    WITH objects AS (
      SELECT p.oid,p.proowner AS owner_id,p.proacl AS acl FROM pg_catalog.pg_proc p
      WHERE p.oid='public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)'::regprocedure
    ), actual AS (
      SELECT o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(o.acl,pg_catalog.acldefault('f',o.owner_id))) a
    ), expected AS (
      SELECT o.oid,'postgres'::regrole::oid AS grantor,'postgres'::regrole::oid AS grantee,
        'EXECUTE'::text AS privilege_type,false AS is_grantable FROM objects o
      UNION ALL SELECT o.oid,'postgres'::regrole::oid,'service_role'::regrole::oid,'EXECUTE',false FROM objects o
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    ) SELECT 1 FROM objects WHERE owner_id<>'postgres'::regrole UNION ALL SELECT 1 FROM differences
  ) OR pg_catalog.has_function_privilege('anon','public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)','EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated','public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'mobile_workout_registration_unexpected_confirmation_acl' USING ERRCODE='42501';
  END IF;
END $privileges$;
COMMIT;

-- Dormant UI workout EDIT/CANCEL. BFF/Swift integration and confirmation remain separate.
-- Reuse the S17B journal and receipts; never invoke a workout writer or recalculate kcal.
BEGIN;

DO $preflight$
BEGIN
  IF CURRENT_USER<>'postgres' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('private.mobile_workout_proposal_admissions') IS NULL
    OR pg_catalog.to_regclass('private.mobile_workout_registration_edit_receipts') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR pg_catalog.to_regclass('public.pending_registrations') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR pg_catalog.to_regprocedure('private.mobile_workout_proposal_input_hash(jsonb)') IS NULL
    OR pg_catalog.to_regprocedure('public.get_mobile_workout_registration(uuid,uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('edit_mobile_workout_registration','cancel_mobile_workout_registration')) THEN
    RAISE EXCEPTION 'mobile_workout_registration_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE FUNCTION public.edit_mobile_workout_registration(
  p_user_id uuid,p_registration_id uuid,p_expected_revision integer,
  p_request_key text,p_input jsonb,p_proposal jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $edit$
DECLARE
  v_authority private.workout_strength_authority_epochs%ROWTYPE;
  v_admission private.mobile_workout_proposal_admissions%ROWTYPE;
  v_match private.mobile_workout_proposal_admissions%ROWTYPE;
  v_pending public.pending_registrations%ROWTYPE;
  v_receipt private.mobile_workout_registration_edit_receipts%ROWTYPE;
  v_admission_count integer:=0;
  v_input_hash text;
  v_now timestamptz;
  v_registration jsonb;
  v_kcal numeric;
  v_source_instant timestamptz;
  v_source_date date;
  v_normalized_performed text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_registration_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0
    OR p_request_key IS NULL OR NOT ((p_request_key COLLATE "C") ~
      '^wue1:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  v_input_hash:=private.mobile_workout_proposal_input_hash(p_input);
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_workout_proposal_patient_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.* INTO v_authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
  -- Historical owner/pending locates the original even after DELETE or marker corruption.
  -- Lock every match rather than choosing an arbitrary admission in a corrupt journal.
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
  -- No status predicate: observe terminal updates/deletion committed during the row wait.
  SELECT p.* INTO v_pending FROM public.pending_registrations p
    WHERE p.user_id=p_user_id AND p.id=p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"pending_missing"}'::jsonb; END IF;
  IF v_pending.workout_ui_admission_id IS DISTINCT FROM v_admission.admission_id
    OR v_admission.pending_id IS DISTINCT FROM v_pending.id
    OR (v_admission.confirmed_lifecycle_key IS NOT NULL AND v_pending.status<>'confirmed') THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  v_now:=pg_catalog.clock_timestamp();
  v_registration:=pg_catalog.jsonb_build_object('id',v_pending.id,'status',v_pending.status,
    'created_at',v_pending.created_at,'expires_at',v_pending.expires_at,'resolved_at',v_pending.resolved_at,
    'proposal',v_pending.proposal,'workout_protocol','ui-v1','content_revision',v_admission.content_revision);
  SELECT r.* INTO v_receipt FROM private.mobile_workout_registration_edit_receipts r
    WHERE r.user_id=p_user_id AND r.admission_id=v_admission.admission_id AND r.request_key=(p_request_key COLLATE "C");
  IF FOUND THEN
    IF v_receipt.input_hash IS DISTINCT FROM v_input_hash OR v_receipt.expected_revision IS DISTINCT FROM p_expected_revision THEN
      RETURN pg_catalog.jsonb_build_object('status','conflict','reason','request_content_conflict','registration',v_registration);
    END IF;
    -- Original receipt with CURRENT content; no candidate validation, renewal or reversion.
    RETURN pg_catalog.jsonb_build_object('status','reused','registration',v_registration,'receipt',
      pg_catalog.jsonb_build_object('requestKey',v_receipt.request_key,'expectedRevision',v_receipt.expected_revision,
        'resultRevision',v_receipt.result_revision));
  END IF;
  IF v_pending.status='confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','already_confirmed','registration',v_registration);
  END IF;
  IF v_pending.status<>'pending' THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','not_pending','registration',v_registration);
  END IF;
  IF v_admission.content_revision<>p_expected_revision THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_conflict','registration',v_registration);
  END IF;
  IF v_pending.expires_at<=v_now THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','expired','registration',v_registration);
  END IF;
  -- Keep keys owner-wide, including unbound admissions and receipts from old epochs.
  IF EXISTS (SELECT 1 FROM private.mobile_workout_proposal_admissions a
      WHERE a.user_id=p_user_id AND a.admission_id<>v_admission.admission_id AND a.request_key=(p_request_key COLLATE "C"))
    OR EXISTS (SELECT 1 FROM private.mobile_workout_registration_edit_receipts r
      WHERE r.user_id=p_user_id AND r.admission_id<>v_admission.admission_id AND r.request_key=(p_request_key COLLATE "C")) THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','request_key_conflict','registration',v_registration);
  END IF;

  -- Literal S16 candidate contract, except provider belongs to this EDIT key.
  -- The original S16 materializer/hash remains unchanged and is not an EDIT writer.
  IF pg_catalog.jsonb_typeof(p_proposal) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
  END IF;
  IF NOT (p_proposal ?& ARRAY['kind','workoutType','durationMin','kcalEst','intensity',
      'sourceContentType','source_provider_message_id','source_timestamp',
      'source_timezone','source_local_date','raw_args','express_eligible'])
    OR p_proposal-ARRAY['kind','workoutType','durationMin','kcalEst','intensity',
      'sourceContentType','source_provider_message_id','source_timestamp',
      'source_timezone','source_local_date','raw_args','express_eligible'] <> '{}'::jsonb
    OR p_proposal->'kind' IS DISTINCT FROM '"workout"'::jsonb
    OR p_proposal->'workoutType' IS DISTINCT FROM p_input->'workout_type'
    OR p_proposal->'durationMin' IS DISTINCT FROM p_input->'duration_min'
    OR p_proposal->'intensity' IS DISTINCT FROM p_input->'intensity'
    OR p_proposal->'sourceContentType' IS DISTINCT FROM '"mobile"'::jsonb
    OR p_proposal->'source_provider_message_id' IS DISTINCT FROM pg_catalog.to_jsonb(p_request_key)
    OR p_proposal->'raw_args' IS DISTINCT FROM pg_catalog.jsonb_build_object(
      'workout_type',p_input->'workout_type','duration_min',p_input->'duration_min','intensity',p_input->'intensity')
    OR p_proposal->'express_eligible' IS DISTINCT FROM 'false'::jsonb
    OR pg_catalog.jsonb_typeof(p_proposal->'kcalEst') IS DISTINCT FROM 'number'
    OR pg_catalog.jsonb_typeof(p_proposal->'source_timestamp') IS DISTINCT FROM 'string'
    OR NOT ((p_proposal->>'source_timestamp') COLLATE "C" ~
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$')
    OR pg_catalog.jsonb_typeof(p_proposal->'source_timezone') IS DISTINCT FROM 'string'
    OR pg_catalog.char_length(p_proposal->>'source_timezone')<1
    OR pg_catalog.jsonb_typeof(p_proposal->'source_local_date') IS DISTINCT FROM 'string'
    OR NOT ((p_proposal->>'source_local_date') COLLATE "C" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
  END IF;
  v_kcal:=(p_proposal->>'kcalEst')::numeric;
  IF v_kcal<0 OR v_kcal<>pg_catalog.trunc(v_kcal) THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
  END IF;
  BEGIN
    v_source_instant:=(p_proposal->>'source_timestamp')::timestamptz;
    v_source_date:=(p_proposal->>'source_local_date')::date;
    IF NOT pg_catalog.isfinite(v_source_instant) OR NOT pg_catalog.isfinite(v_source_date) THEN
      RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
    END IF;
    IF p_input ? 'performed_at' THEN
      -- Existing JS Date discards submilliseconds; truncate text before a SQL cast can round it.
      v_normalized_performed:=pg_catalog.regexp_replace(p_input->>'performed_at','([.][0-9]{3})[0-9]+',E'\\1');
      IF v_source_instant IS DISTINCT FROM v_normalized_performed::timestamptz THEN
        RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
      END IF;
    END IF;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
  END;
  IF v_admission.content_revision=2147483647 THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_exhausted','registration',v_registration);
  END IF;

  UPDATE public.pending_registrations SET proposal=p_proposal,expires_at=v_now+interval '24 hours'
    WHERE user_id=p_user_id AND id=p_registration_id RETURNING * INTO STRICT v_pending;
  UPDATE private.mobile_workout_proposal_admissions SET content_revision=content_revision+1
    WHERE user_id=p_user_id AND admission_id=v_admission.admission_id AND content_revision=p_expected_revision
    RETURNING * INTO STRICT v_admission;
  INSERT INTO private.mobile_workout_registration_edit_receipts(
    user_id,admission_id,request_key,input_hash,expected_revision,result_revision
  ) VALUES(p_user_id,v_admission.admission_id,p_request_key,v_input_hash,p_expected_revision,v_admission.content_revision)
    RETURNING * INTO STRICT v_receipt;
  v_registration:=v_registration||pg_catalog.jsonb_build_object('proposal',v_pending.proposal,
    'expires_at',v_pending.expires_at,'content_revision',v_admission.content_revision);
  RETURN pg_catalog.jsonb_build_object('status','edited','registration',v_registration,'receipt',
    pg_catalog.jsonb_build_object('requestKey',v_receipt.request_key,'expectedRevision',v_receipt.expected_revision,
      'resultRevision',v_receipt.result_revision));
END $edit$;
REVOKE ALL ON FUNCTION public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb) TO service_role;

CREATE FUNCTION public.cancel_mobile_workout_registration(
  p_user_id uuid,p_registration_id uuid,p_expected_revision integer
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $cancel$
DECLARE
  v_authority private.workout_strength_authority_epochs%ROWTYPE;
  v_admission private.mobile_workout_proposal_admissions%ROWTYPE;
  v_match private.mobile_workout_proposal_admissions%ROWTYPE;
  v_pending public.pending_registrations%ROWTYPE;
  v_admission_count integer:=0;
  v_now timestamptz;
  v_registration jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_registration_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0 THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_read_committed' USING ERRCODE='22023';
  END IF;
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
  SELECT p.* INTO v_pending FROM public.pending_registrations p
    WHERE p.user_id=p_user_id AND p.id=p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"pending_missing"}'::jsonb; END IF;
  IF v_pending.workout_ui_admission_id IS DISTINCT FROM v_admission.admission_id
    OR v_admission.pending_id IS DISTINCT FROM v_pending.id
    OR (v_admission.confirmed_lifecycle_key IS NOT NULL AND v_pending.status<>'confirmed') THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  v_now:=pg_catalog.clock_timestamp();
  v_registration:=pg_catalog.jsonb_build_object('id',v_pending.id,'status',v_pending.status,
    'created_at',v_pending.created_at,'expires_at',v_pending.expires_at,'resolved_at',v_pending.resolved_at,
    'proposal',v_pending.proposal,'workout_protocol','ui-v1','content_revision',v_admission.content_revision);
  IF v_pending.status='confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','already_confirmed','registration',v_registration);
  END IF;
  IF v_admission.content_revision<>p_expected_revision THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_conflict','registration',v_registration);
  END IF;
  IF v_pending.status='cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('status','reused','registration',v_registration);
  END IF;
  IF v_pending.status<>'pending' THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','not_pending','registration',v_registration);
  END IF;
  -- Timestamp expiry alone does not veto cancellation of a still-pending proposal.
  UPDATE public.pending_registrations SET status='cancelled',resolved_at=v_now
    WHERE user_id=p_user_id AND id=p_registration_id RETURNING * INTO STRICT v_pending;
  v_registration:=v_registration||pg_catalog.jsonb_build_object('status',v_pending.status,'resolved_at',v_pending.resolved_at);
  RETURN pg_catalog.jsonb_build_object('status','cancelled','registration',v_registration);
END $cancel$;
REVOKE ALL ON FUNCTION public.cancel_mobile_workout_registration(uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.cancel_mobile_workout_registration(uuid,uuid,integer) TO service_role;

-- Unexpected default grants abort the transaction rather than leaving broad RPCs installed.
DO $privileges$
BEGIN
  IF EXISTS (
    WITH objects AS (
      SELECT p.oid,p.proowner AS owner_id,p.proacl AS acl FROM pg_catalog.pg_proc p
      WHERE p.oid IN ('public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb)'::regprocedure,
        'public.cancel_mobile_workout_registration(uuid,uuid,integer)'::regprocedure)
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
  ) OR pg_catalog.has_function_privilege('anon','public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb)','EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated','public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb)','EXECUTE')
    OR pg_catalog.has_function_privilege('anon','public.cancel_mobile_workout_registration(uuid,uuid,integer)','EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated','public.cancel_mobile_workout_registration(uuid,uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'mobile_workout_registration_unexpected_mutator_acl' USING ERRCODE='42501';
  END IF;
END $privileges$;
COMMIT;

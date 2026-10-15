-- Dormant authority for the real mobile workout proposal producer.
-- No caller, lifecycle, workout, snapshot, Flow inbound or cutover is enabled.
BEGIN;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('public.pending_registrations') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR pg_catalog.to_regprocedure('public.replace_pending_registration_atomic(uuid,jsonb,timestamptz,text)') IS NULL THEN
    RAISE EXCEPTION 'mobile_workout_proposal_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF pg_catalog.to_regclass('private.mobile_workout_proposal_admissions') IS NOT NULL
    OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE (n.nspname='public' AND p.proname IN
        ('admit_mobile_workout_proposal','materialize_mobile_workout_proposal'))
        OR (n.nspname='private' AND p.proname='mobile_workout_proposal_input_hash')
    ) THEN
    RAISE EXCEPTION 'mobile_workout_proposal_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE TABLE private.mobile_workout_proposal_admissions (
  user_id uuid NOT NULL,
  admission_id uuid NOT NULL,
  epoch uuid NOT NULL,
  request_key text COLLATE "C" NOT NULL,
  request_hash text NOT NULL,
  admitted_at timestamptz NOT NULL,
  pending_id uuid,
  first_proposal_hash text,
  bound_at timestamptz,
  rejection_reason text,
  PRIMARY KEY(user_id,request_key),
  UNIQUE(user_id,admission_id),
  CONSTRAINT mobile_workout_proposal_admissions_owner_fk FOREIGN KEY(user_id)
    REFERENCES private.workout_strength_authority_epochs(user_id) ON DELETE CASCADE,
  CONSTRAINT mobile_workout_proposal_admissions_shape_check CHECK ((
    (request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$'
    AND (request_hash COLLATE "C") ~ '^[0-9a-f]{64}$'
    AND pg_catalog.isfinite(admitted_at)
    AND (
      (pending_id IS NULL AND first_proposal_hash IS NULL AND bound_at IS NULL
        AND (rejection_reason IS NULL OR rejection_reason='unproved_pending'))
      OR (pending_id IS NOT NULL AND first_proposal_hash IS NOT NULL AND bound_at IS NOT NULL
        AND rejection_reason IS NULL
        AND (first_proposal_hash COLLATE "C") ~ '^[0-9a-f]{64}$'
        AND pg_catalog.isfinite(bound_at))
    )
  ) IS TRUE)
);
ALTER TABLE private.mobile_workout_proposal_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_workout_proposal_admissions FROM PUBLIC,anon,authenticated,service_role;

-- A new SQL hash namespace, not HTTP canonical JSON or the Flow text hash.
-- The BFF supplies the already validated input, never a client-supplied hash.
CREATE FUNCTION private.mobile_workout_proposal_input_hash(p_input jsonb) RETURNS text
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $hash$
DECLARE
  duration numeric;
  performed timestamptz;
BEGIN
  IF pg_catalog.jsonb_typeof(p_input) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  IF NOT (p_input ?& ARRAY['kind','workout_type','duration_min','intensity'])
    OR p_input-ARRAY['kind','workout_type','duration_min','intensity','performed_at'] <> '{}'::jsonb
    OR p_input->'kind' IS DISTINCT FROM '"workout"'::jsonb
    OR pg_catalog.jsonb_typeof(p_input->'workout_type') IS DISTINCT FROM 'string'
    OR pg_catalog.char_length(p_input->>'workout_type') NOT BETWEEN 1 AND 80
    OR pg_catalog.btrim(p_input->>'workout_type') IS DISTINCT FROM p_input->>'workout_type'
    OR pg_catalog.jsonb_typeof(p_input->'duration_min') IS DISTINCT FROM 'number'
    OR p_input->'intensity' NOT IN ('"leve"'::jsonb,'"moderada"'::jsonb,'"alta"'::jsonb) THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  duration:=(p_input->>'duration_min')::numeric;
  IF duration NOT BETWEEN 1 AND 1440 OR duration<>pg_catalog.trunc(duration) THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  IF p_input ? 'performed_at' THEN
    IF pg_catalog.jsonb_typeof(p_input->'performed_at') IS DISTINCT FROM 'string'
      OR NOT ((p_input->>'performed_at') COLLATE "C" ~
        '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$') THEN
      RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
    END IF;
    BEGIN
      performed:=(p_input->>'performed_at')::timestamptz;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
    END;
    IF NOT pg_catalog.isfinite(performed) THEN
      RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
    END IF;
  END IF;
  RETURN pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
    (p_input||pg_catalog.jsonb_build_object('duration_min',duration::integer))::text,'UTF8')),'hex');
END $hash$;
REVOKE ALL ON FUNCTION private.mobile_workout_proposal_input_hash(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.admit_mobile_workout_proposal(
  p_user_id uuid,p_request_key text,p_input jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $admit$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.mobile_workout_proposal_admissions%ROWTYPE;
  input_hash text;
  outcome text:='reused';
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_request_key IS NULL
    OR NOT ((p_request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$') THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  input_hash:=private.mobile_workout_proposal_input_hash(p_input);
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_workout_proposal_patient_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
      VALUES(p_user_id,pg_catalog.gen_random_uuid(),pg_catalog.clock_timestamp()) RETURNING * INTO authority;
  END IF;
  SELECT a.* INTO admission FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.request_key=(p_request_key COLLATE "C") FOR UPDATE;
  IF FOUND THEN
    IF admission.epoch IS DISTINCT FROM authority.epoch THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_epoch');
    END IF;
    IF admission.request_hash IS DISTINCT FROM input_hash THEN
      RETURN pg_catalog.jsonb_build_object('status','conflict','reason','request_content_conflict');
    END IF;
  ELSE
    INSERT INTO private.mobile_workout_proposal_admissions(
      user_id,admission_id,epoch,request_key,request_hash,admitted_at
    ) VALUES(p_user_id,pg_catalog.gen_random_uuid(),authority.epoch,p_request_key,input_hash,pg_catalog.clock_timestamp())
      RETURNING * INTO admission;
    outcome:='admitted';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',outcome,'admission',
    pg_catalog.jsonb_build_object('ownerID',admission.user_id::text,
      'admissionID',admission.admission_id::text,'epoch',admission.epoch::text,
      'requestNamespace','mobile_workout_proposal_v1','requestKey',admission.request_key,
      'requestHash',admission.request_hash,'admittedAt',
      pg_catalog.to_char(admission.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $admit$;
REVOKE ALL ON FUNCTION public.admit_mobile_workout_proposal(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_mobile_workout_proposal(uuid,text,jsonb) TO service_role;

CREATE FUNCTION public.materialize_mobile_workout_proposal(
  p_user_id uuid,p_admission_id uuid,p_input jsonb,p_proposal jsonb,p_expires_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $materialize$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.mobile_workout_proposal_admissions%ROWTYPE;
  pending public.pending_registrations%ROWTYPE;
  input_hash text;
  kcal numeric;
  source_instant timestamptz;
  source_date date;
  normalized_performed text;
  result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_admission_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  input_hash:=private.mobile_workout_proposal_input_hash(p_input);
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_workout_proposal_patient_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','invalid_admission');
  END IF;
  SELECT a.* INTO admission FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=p_admission_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','invalid_admission');
  END IF;
  IF admission.epoch IS DISTINCT FROM authority.epoch THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_epoch');
  END IF;
  IF admission.request_hash IS DISTINCT FROM input_hash THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','request_content_conflict');
  END IF;
  IF admission.rejection_reason IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','unproved_pending');
  END IF;
  IF admission.pending_id IS NOT NULL THEN
    SELECT p.* INTO pending FROM public.pending_registrations p
      WHERE p.user_id=p_user_id AND p.id=admission.pending_id FOR SHARE;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','pending_missing');
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','reused','pendingID',pending.id::text,
      'pendingStatus',pending.status::text,'cancelledCount',0);
  END IF;

  -- Only the first bind uses the calculated candidate. Replay above ignores it.
  IF pg_catalog.jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
    OR p_expires_at IS NULL OR NOT pg_catalog.isfinite(p_expires_at) THEN
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
    OR p_proposal->'source_provider_message_id' IS DISTINCT FROM pg_catalog.to_jsonb(admission.request_key)
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
  kcal:=(p_proposal->>'kcalEst')::numeric;
  IF kcal<0 OR kcal<>pg_catalog.trunc(kcal) THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
  END IF;
  BEGIN
    source_instant:=(p_proposal->>'source_timestamp')::timestamptz;
    source_date:=(p_proposal->>'source_local_date')::date;
    IF NOT pg_catalog.isfinite(source_instant) OR NOT pg_catalog.isfinite(source_date) THEN
      RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
    END IF;
    IF p_input ? 'performed_at' THEN
      -- The existing JS Date builder discards submilliseconds before ISO output.
      -- Truncate the text BEFORE casting; a SQL cast could round .123999999.
      normalized_performed:=pg_catalog.regexp_replace(p_input->>'performed_at',
        '([.][0-9]{3})[0-9]+',E'\\1');
      IF source_instant IS DISTINCT FROM normalized_performed::timestamptz THEN
        RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
      END IF;
    END IF;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_candidate' USING ERRCODE='22023';
  END;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':pending-registration',0));
  result:=public.replace_pending_registration_atomic(p_user_id,p_proposal,p_expires_at,admission.request_key);
  IF pg_catalog.jsonb_typeof(result) IS DISTINCT FROM 'object'
    OR NOT (result ?& ARRAY['pending_id','created','status','cancelled_count'])
    OR result-ARRAY['pending_id','created','status','cancelled_count'] <> '{}'::jsonb
    OR pg_catalog.jsonb_typeof(result->'created') IS DISTINCT FROM 'boolean'
    OR pg_catalog.jsonb_typeof(result->'pending_id') IS DISTINCT FROM 'string'
    OR pg_catalog.jsonb_typeof(result->'cancelled_count') IS DISTINCT FROM 'number'
    OR pg_catalog.jsonb_typeof(result->'status') IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_unexpected_legacy_result';
  END IF;
  SELECT p.* INTO pending FROM public.pending_registrations p
    WHERE p.user_id=p_user_id AND p.id=(result->>'pending_id')::uuid FOR SHARE;
  IF NOT FOUND OR pending.proposal->>'source_provider_message_id' IS DISTINCT FROM admission.request_key
    OR pending.status::text IS DISTINCT FROM result->>'status' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_unexpected_legacy_result';
  END IF;
  IF result->'created'='false'::jsonb THEN
    IF result->'cancelled_count' IS DISTINCT FROM '0'::jsonb THEN
      RAISE EXCEPTION 'mobile_workout_proposal_unexpected_legacy_result';
    END IF;
    UPDATE private.mobile_workout_proposal_admissions SET rejection_reason='unproved_pending'
      WHERE user_id=p_user_id AND admission_id=p_admission_id;
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','unproved_pending');
  END IF;
  IF pending.proposal IS DISTINCT FROM p_proposal OR pending.expires_at IS DISTINCT FROM p_expires_at
    OR pending.status::text<>'pending' OR (result->>'cancelled_count')::numeric<0
    OR (result->>'cancelled_count')::numeric<>pg_catalog.trunc((result->>'cancelled_count')::numeric) THEN
    RAISE EXCEPTION 'mobile_workout_proposal_unexpected_legacy_result';
  END IF;
  UPDATE private.mobile_workout_proposal_admissions
    SET pending_id=pending.id,
      first_proposal_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pending.proposal::text,'UTF8')),'hex'),
      bound_at=pg_catalog.clock_timestamp()
    WHERE user_id=p_user_id AND admission_id=p_admission_id
      AND pending_id IS NULL AND rejection_reason IS NULL
    RETURNING * INTO STRICT admission;
  RETURN pg_catalog.jsonb_build_object('status','materialized','pendingID',pending.id::text,
    'pendingStatus',pending.status::text,'cancelledCount',(result->>'cancelled_count')::integer);
END $materialize$;
REVOKE ALL ON FUNCTION public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamptz) TO service_role;

-- Keep inherited unexpected grants visible: abort instead of repairing defaults.
DO $privileges$
DECLARE
  postgres_owner oid:='postgres'::regrole::oid;
  service_grantee oid:='service_role'::regrole::oid;
BEGIN
  IF EXISTS (
    WITH objects AS (
      SELECT 'r'::pg_catalog."char" AS kind,c.oid,c.relowner AS owner_id,c.relacl AS acl,false AS backend_rpc
      FROM pg_catalog.pg_class c WHERE c.oid='private.mobile_workout_proposal_admissions'::regclass
      UNION ALL
      SELECT 'f'::pg_catalog."char",p.oid,p.proowner,p.proacl,
        p.oid<>'private.mobile_workout_proposal_input_hash(jsonb)'::regprocedure
      FROM pg_catalog.pg_proc p WHERE p.oid IN (
        'private.mobile_workout_proposal_input_hash(jsonb)'::regprocedure,
        'public.admit_mobile_workout_proposal(uuid,text,jsonb)'::regprocedure,
        'public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamptz)'::regprocedure)
    ), actual AS (
      SELECT o.kind,o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(o.acl,pg_catalog.acldefault(o.kind,o.owner_id))) a
    ), expected AS (
      SELECT o.kind,o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL pg_catalog.aclexplode(pg_catalog.acldefault(o.kind,postgres_owner)) a
      WHERE a.grantee=postgres_owner
      UNION ALL
      SELECT o.kind,o.oid,postgres_owner,service_grantee,'EXECUTE'::text,false FROM objects o WHERE o.backend_rpc
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    )
    SELECT 1 FROM objects WHERE owner_id<>postgres_owner
    UNION ALL SELECT 1 FROM differences
  ) THEN
    RAISE EXCEPTION 'C59S16_UNEXPECTED_OBJECT_ACL' USING ERRCODE='42501';
  END IF;
END $privileges$;

COMMIT;

-- Dormant signup request authority. No completion writer, Flow IN, lifecycle or Y creation.
-- Epoch storage is shared with S15/reset; existing RPCs and their namespaces stay intact.
BEGIN;
SET LOCAL search_path = pg_catalog;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_postgres_owner' USING ERRCODE = '42501';
  END IF;
  IF to_regclass('public.users') IS NULL
    OR to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_existing_substrate' USING ERRCODE = '42P01';
  END IF;
  IF to_regclass('private.mobile_signup_strength_request_admissions') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (
        'observe_mobile_signup_strength_epoch', 'admit_mobile_signup_strength_request',
        'verify_mobile_signup_strength_request')) THEN
    RAISE EXCEPTION 'mobile_signup_strength_unknown_existing_object' USING ERRCODE = '42P07';
  END IF;
END $preflight$;

-- Dedicated event domain: the Flow-only S15 admission table is not widened/reused.
CREATE TABLE private.mobile_signup_strength_request_admissions (
  user_id uuid NOT NULL REFERENCES private.workout_strength_authority_epochs(user_id) ON DELETE CASCADE,
  request_key text COLLATE "C" NOT NULL,
  request_hash text COLLATE "C" NOT NULL,
  epoch uuid NOT NULL,
  admission_id uuid NOT NULL,
  admitted_at timestamptz NOT NULL,
  PRIMARY KEY (user_id, request_key),
  UNIQUE (user_id, admission_id),
  CHECK (((request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$'
    AND (request_hash COLLATE "C") ~ '^[0-9a-f]{64}$'
    AND pg_catalog.isfinite(admitted_at)) IS TRUE)
);
ALTER TABLE private.mobile_signup_strength_request_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_signup_strength_request_admissions
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.observe_mobile_signup_strength_epoch(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $observe$
DECLARE authority private.workout_strength_authority_epochs%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_signup_strength_input' USING ERRCODE = '22023';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_read_committed' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':workouts', 0));
  PERFORM u.id FROM public.users u
    WHERE u.id = p_user_id AND u.status = 'active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_signup_strength_patient_not_found' USING ERRCODE = 'P0002';
  END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
    WHERE e.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO private.workout_strength_authority_epochs (user_id, epoch, changed_at)
      VALUES (p_user_id, gen_random_uuid(), clock_timestamp()) RETURNING * INTO authority;
  END IF;
  RETURN jsonb_build_object('status', 'observed', 'observation', jsonb_build_object(
    'ownerID', authority.user_id::text, 'epoch', authority.epoch::text,
    'changedAt', to_char(authority.changed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $observe$;
REVOKE ALL ON FUNCTION public.observe_mobile_signup_strength_epoch(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.observe_mobile_signup_strength_epoch(uuid) TO service_role;

-- The hash is the ORIGINAL validated payload hash supplied by the trusted backend,
-- not a hash reconstructed from effective BF, current profile or SQL jsonb rendering.
CREATE FUNCTION public.admit_mobile_signup_strength_request(
  p_user_id uuid, p_request_key text, p_request_hash text, p_expected_epoch uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $admit$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.mobile_signup_strength_request_admissions%ROWTYPE;
  outcome text := 'reused';
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_request_key IS NULL OR p_request_hash IS NULL OR p_expected_epoch IS NULL
    OR NOT ((p_request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$')
    OR NOT ((p_request_hash COLLATE "C") ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'invalid_mobile_signup_strength_input' USING ERRCODE = '22023';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_read_committed' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':workouts', 0));
  PERFORM u.id FROM public.users u
    WHERE u.id = p_user_id AND u.status = 'active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_signup_strength_patient_not_found' USING ERRCODE = 'P0002';
  END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
    WHERE e.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'forbidden', 'reason', 'invalid_observation');
  END IF;
  SELECT a.* INTO admission FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id = p_user_id AND a.request_key = (p_request_key COLLATE "C") FOR UPDATE;
  IF FOUND THEN
    -- Old keys remain tombstones after reset, even with a new observation or payload.
    IF admission.epoch IS DISTINCT FROM authority.epoch THEN
      RETURN jsonb_build_object('status', 'forbidden', 'reason', 'stale_epoch');
    END IF;
    IF p_expected_epoch IS DISTINCT FROM authority.epoch THEN
      RETURN jsonb_build_object('status', 'forbidden', 'reason', 'stale_epoch');
    END IF;
    IF admission.request_hash IS DISTINCT FROM p_request_hash THEN
      RETURN jsonb_build_object('status', 'conflict', 'reason', 'request_content_conflict');
    END IF;
  ELSE
    IF p_expected_epoch IS DISTINCT FROM authority.epoch THEN
      RETURN jsonb_build_object('status', 'forbidden', 'reason', 'stale_epoch');
    END IF;
    INSERT INTO private.mobile_signup_strength_request_admissions (
      user_id, request_key, request_hash, epoch, admission_id, admitted_at
    ) VALUES (p_user_id, p_request_key, p_request_hash, authority.epoch,
      gen_random_uuid(), clock_timestamp()) RETURNING * INTO admission;
    outcome := 'admitted';
  END IF;
  RETURN jsonb_build_object('status', outcome, 'admission', jsonb_build_object(
    'ownerID', admission.user_id::text, 'admissionID', admission.admission_id::text,
    'epoch', admission.epoch::text, 'requestKey', admission.request_key, 'requestHash', admission.request_hash,
    'admittedAt', to_char(admission.admitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $admit$;
REVOKE ALL ON FUNCTION public.admit_mobile_signup_strength_request(uuid, text, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admit_mobile_signup_strength_request(uuid, text, text, uuid) TO service_role;

-- Point-in-time replay gate only. The future writer must revalidate inside its
-- mobile-onboarding -> users/profile transaction, without taking workouts late.
CREATE FUNCTION public.verify_mobile_signup_strength_request(
  p_user_id uuid, p_admission_id uuid, p_request_key text, p_request_hash text, p_expected_epoch uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $verify$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.mobile_signup_strength_request_admissions%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_admission_id IS NULL OR p_request_key IS NULL
    OR p_request_hash IS NULL OR p_expected_epoch IS NULL
    OR NOT ((p_request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$')
    OR NOT ((p_request_hash COLLATE "C") ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'invalid_mobile_signup_strength_input' USING ERRCODE = '22023';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_read_committed' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':workouts', 0));
  PERFORM u.id FROM public.users u
    WHERE u.id = p_user_id AND u.status = 'active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_signup_strength_patient_not_found' USING ERRCODE = 'P0002';
  END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
    WHERE e.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'forbidden', 'reason', 'invalid_admission');
  END IF;
  SELECT a.* INTO admission FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id = p_user_id AND a.admission_id = p_admission_id FOR UPDATE;
  IF NOT FOUND OR admission.request_key IS DISTINCT FROM p_request_key
    OR admission.request_hash IS DISTINCT FROM p_request_hash THEN
    RETURN jsonb_build_object('status', 'forbidden', 'reason', 'invalid_admission');
  END IF;
  IF admission.epoch IS DISTINCT FROM authority.epoch
    OR admission.epoch IS DISTINCT FROM p_expected_epoch THEN
    RETURN jsonb_build_object('status', 'forbidden', 'reason', 'stale_epoch');
  END IF;
  RETURN jsonb_build_object('status', 'verified', 'admission', jsonb_build_object(
    'ownerID', admission.user_id::text, 'admissionID', admission.admission_id::text,
    'epoch', admission.epoch::text, 'requestKey', admission.request_key, 'requestHash', admission.request_hash,
    'admittedAt', to_char(admission.admitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $verify$;
REVOKE ALL ON FUNCTION public.verify_mobile_signup_strength_request(uuid, uuid, text, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_mobile_signup_strength_request(uuid, uuid, text, text, uuid) TO service_role;

-- Reject unexpected inherited grants atomically; never change global default ACLs.
DO $acl$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c,
    LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
    WHERE c.oid = 'private.mobile_signup_strength_request_admissions'::regclass
      AND a.grantee <> c.relowner)
    OR EXISTS (SELECT 1 FROM pg_proc p,
      LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE p.oid IN ('public.observe_mobile_signup_strength_epoch(uuid)'::regprocedure,
        'public.admit_mobile_signup_strength_request(uuid,text,text,uuid)'::regprocedure,
        'public.verify_mobile_signup_strength_request(uuid,uuid,text,text,uuid)'::regprocedure)
        AND a.grantee NOT IN (p.proowner, 'service_role'::regrole)) THEN
    RAISE EXCEPTION 'mobile_signup_strength_unexpected_inherited_grant' USING ERRCODE = '42501';
  END IF;
END $acl$;
COMMIT;

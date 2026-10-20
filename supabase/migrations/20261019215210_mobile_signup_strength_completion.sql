-- Dormant, backend-only completion event. Legacy completion RPCs remain unchanged.
-- The public composition stays OFF until the integration and activation gates pass.
BEGIN;
SET LOCAL search_path = pg_catalog;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regclass('private.mobile_signup_strength_request_admissions') IS NULL
    OR to_regclass('private.strength_week_scopes') IS NULL
    OR to_regclass('private.strength_week_source_versions') IS NULL
    OR to_regprocedure('public.complete_mobile_onboarding_atomic(uuid,jsonb)') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR to_regprocedure('private.open_strength_week_scope(uuid,text,text)') IS NULL
    OR to_regprocedure('private.capture_strength_week_source(uuid,uuid,text,text,smallint,uuid,timestamptz,text,text)') IS NULL THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF to_regclass('private.mobile_signup_strength_completion_receipts') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE (n.nspname='public' AND p.proname='complete_mobile_onboarding_keyed')
        OR (n.nspname='private' AND p.proname='preserve_mobile_signup_strength_completion_receipt')) THEN
    RAISE EXCEPTION 'mobile_signup_strength_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE TABLE private.mobile_signup_strength_completion_receipts (
  user_id uuid NOT NULL,
  admission_id uuid NOT NULL,
  epoch uuid NOT NULL,
  outcome text NOT NULL CHECK(outcome IN('first_fresh','not_first_fresh')),
  completion_path text NOT NULL CHECK(completion_path IN('atomic','body_photo_confirmation','cleanup_scope')),
  completed_at timestamptz NOT NULL CHECK(isfinite(completed_at)),
  generation uuid,
  frequency_source_version_id uuid,
  completion_result jsonb NOT NULL,
  recorded_at timestamptz NOT NULL CHECK(isfinite(recorded_at)),
  PRIMARY KEY(user_id,admission_id),
  FOREIGN KEY(user_id,admission_id)
    REFERENCES private.mobile_signup_strength_request_admissions(user_id,admission_id) ON DELETE CASCADE,
  FOREIGN KEY(user_id,generation,frequency_source_version_id)
    REFERENCES private.strength_week_source_versions(user_id,generation,source_version_id) ON DELETE NO ACTION,
  UNIQUE(user_id,generation),
  CHECK(((outcome='first_fresh' AND generation IS NOT NULL AND frequency_source_version_id IS NOT NULL)
    OR (outcome='not_first_fresh' AND generation IS NULL AND frequency_source_version_id IS NULL)) IS TRUE),
  CHECK((jsonb_typeof(completion_result)='object'
    AND completion_result->>'user_id'=user_id::text
    AND completion_result->'onboarding_completed'='true'::jsonb
    AND jsonb_typeof(completion_result->'completed_at')='string') IS TRUE)
);
CREATE UNIQUE INDEX mobile_signup_strength_one_first_fresh_per_epoch
  ON private.mobile_signup_strength_completion_receipts(user_id,epoch) WHERE outcome='first_fresh';
ALTER TABLE private.mobile_signup_strength_completion_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_signup_strength_completion_receipts
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.preserve_mobile_signup_strength_completion_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $immutable$
BEGIN
  IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
    RAISE EXCEPTION 'mobile_signup_strength_completion_receipt_immutable' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END $immutable$;
CREATE TRIGGER preserve_mobile_signup_strength_completion_receipt BEFORE UPDATE
  ON private.mobile_signup_strength_completion_receipts FOR EACH ROW
  EXECUTE FUNCTION private.preserve_mobile_signup_strength_completion_receipt();
REVOKE ALL ON FUNCTION private.preserve_mobile_signup_strength_completion_receipt()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.complete_mobile_onboarding_keyed(
  p_user_id uuid,p_submission jsonb,p_completion_path text,
  p_request_key text,p_request_hash text,p_expected_epoch uuid,p_admission_id uuid,
  p_confirmation jsonb,p_expected_completed boolean,p_expected_completed_at timestamptz,
  p_expected_receipt_count bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $complete$
DECLARE
  completed boolean; completed_at timestamptz; first_fresh boolean;
  current_epoch uuid; admission private.mobile_signup_strength_request_admissions%ROWTYPE;
  receipt private.mobile_signup_strength_completion_receipts%ROWTYPE;
  scope private.strength_week_scopes%ROWTYPE; source private.strength_week_source_versions%ROWTYPE;
  result jsonb; scope_wire jsonb; source_wire jsonb; frequency smallint;
  result_completed_at timestamptz; recorded_at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR jsonb_typeof(p_submission) IS DISTINCT FROM 'object'
    OR p_completion_path IS NULL OR p_completion_path NOT IN('atomic','body_photo_confirmation','cleanup_scope')
    OR p_request_key IS NULL OR p_request_hash IS NULL OR p_expected_epoch IS NULL OR p_admission_id IS NULL
    OR NOT ((p_request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$')
    OR NOT ((p_request_hash COLLATE "C") ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'invalid_mobile_signup_strength_input' USING ERRCODE='22023';
  END IF;
  IF current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;

  -- Match the existing core's order. Do not take workouts after users/profile.
  PERFORM pg_advisory_xact_lock(hashtextextended('mobile-onboarding:'||p_user_id::text,0));
  SELECT p.onboarding_completed,p.onboarding_completed_at INTO completed,completed_at
    FROM public.users u JOIN public.user_profiles p ON p.user_id=u.id
    WHERE u.id=p_user_id AND u.status='active' FOR UPDATE OF u,p;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e
    WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_signup_strength_invalid_admission' USING ERRCODE='40001';
  END IF;
  SELECT a.* INTO admission FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=p_admission_id FOR UPDATE;
  IF NOT FOUND OR admission.request_key IS DISTINCT FROM p_request_key
    OR admission.request_hash IS DISTINCT FROM p_request_hash THEN
    RAISE EXCEPTION 'mobile_signup_strength_invalid_admission' USING ERRCODE='40001';
  END IF;
  IF admission.epoch IS DISTINCT FROM current_epoch OR admission.epoch IS DISTINCT FROM p_expected_epoch THEN
    RAISE EXCEPTION 'mobile_signup_strength_stale_epoch' USING ERRCODE='40001';
  END IF;

  -- Authority is checked before replay. The original event is not reconstructed
  -- from today's profile, clock, selector or CAS, and a closed Y is not reopened.
  SELECT r.* INTO receipt FROM private.mobile_signup_strength_completion_receipts r
    WHERE r.user_id=p_user_id AND r.admission_id=p_admission_id FOR UPDATE;
  IF FOUND THEN
    IF receipt.epoch IS DISTINCT FROM admission.epoch
      OR (receipt.completion_result->>'completed_at')::timestamptz IS DISTINCT FROM receipt.completed_at
      OR (receipt.outcome='first_fresh' AND NOT EXISTS(
        SELECT 1 FROM private.strength_week_source_versions v
        JOIN private.strength_week_scopes s ON s.user_id=v.user_id AND s.generation=v.generation
        WHERE v.user_id=p_user_id AND v.generation=receipt.generation
          AND v.source_version_id=receipt.frequency_source_version_id
          AND v.source_kind='informed_frequency' AND v.fact='value' AND v.planned_days BETWEEN 0 AND 7
          AND v.operation_namespace='mobile_signup_completion_v1' AND v.operation_key=p_admission_id::text
          AND v.source_entity_id IS NULL AND v.source_valid_until IS NULL
          AND s.predecessor_generation IS NULL AND s.open_operation_namespace='mobile_signup_completion_v1'
          AND s.open_operation_key=p_admission_id::text AND s.opened_at<=v.observed_at
          AND v.observed_at<=receipt.recorded_at)) THEN
      RAISE EXCEPTION 'mobile_signup_strength_receipt_invalid' USING ERRCODE='XX001';
    END IF;
    RETURN receipt.completion_result;
  END IF;

  first_fresh:=completed IS FALSE AND completed_at IS NULL;
  IF first_fresh THEN
    PERFORM 1 FROM private.strength_week_scopes s WHERE s.user_id=p_user_id
      AND (s.closed_at IS NULL OR (s.open_operation_namespace='mobile_signup_completion_v1'
        AND s.open_operation_key=p_admission_id::text)) FOR UPDATE;
    IF FOUND THEN
      RAISE EXCEPTION 'mobile_signup_strength_existing_scope' USING ERRCODE='40001';
    END IF;
  END IF;

  -- These are the three literal historical delegations. There is no fallback.
  -- Execution-specific CAS validation follows receipt replay intentionally.
  CASE p_completion_path
    WHEN 'atomic' THEN
      IF p_confirmation IS NOT NULL OR p_expected_completed IS NOT NULL
        OR p_expected_completed_at IS NOT NULL OR p_expected_receipt_count IS NOT NULL THEN
        RAISE EXCEPTION 'invalid_mobile_signup_strength_input' USING ERRCODE='22023';
      END IF;
      result:=public.complete_mobile_onboarding_atomic(p_user_id,p_submission);
    WHEN 'body_photo_confirmation' THEN
      result:=public.complete_mobile_onboarding_with_body_photo_confirmation(
        p_user_id,p_submission,p_confirmation,p_expected_completed,p_expected_completed_at,p_expected_receipt_count);
    WHEN 'cleanup_scope' THEN
      result:=public.complete_mobile_onboarding_with_cleanup_scope(
        p_user_id,p_submission,p_confirmation,p_expected_completed,p_expected_completed_at,p_expected_receipt_count);
  END CASE;
  IF jsonb_typeof(result) IS DISTINCT FROM 'object'
    OR result->>'user_id' IS DISTINCT FROM p_user_id::text
    OR result->'onboarding_completed' IS DISTINCT FROM 'true'::jsonb
    OR jsonb_typeof(result->'completed_at') IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'mobile_signup_strength_completion_invalid' USING ERRCODE='XX001';
  END IF;
  result_completed_at:=(result->>'completed_at')::timestamptz;
  IF NOT isfinite(result_completed_at) THEN
    RAISE EXCEPTION 'mobile_signup_strength_completion_invalid' USING ERRCODE='XX001';
  END IF;

  IF first_fresh THEN
    SELECT p.training_frequency INTO frequency FROM public.user_profiles p
      WHERE p.user_id=p_user_id AND p.onboarding_completed IS TRUE
        AND p.onboarding_completed_at=result_completed_at;
    IF NOT FOUND OR frequency IS NULL OR frequency NOT BETWEEN 0 AND 7
      OR frequency IS DISTINCT FROM (p_submission->>'training_frequency')::smallint THEN
      RAISE EXCEPTION 'mobile_signup_strength_completion_invalid' USING ERRCODE='XX001';
    END IF;
    scope_wire:=private.open_strength_week_scope(p_user_id,'mobile_signup_completion_v1',p_admission_id::text);
    SELECT s.* INTO scope FROM private.strength_week_scopes s
      WHERE s.user_id=p_user_id AND s.generation=(scope_wire->>'generation')::uuid
        AND s.predecessor_generation IS NULL AND s.closed_at IS NULL
        AND s.open_operation_namespace='mobile_signup_completion_v1' AND s.open_operation_key=p_admission_id::text;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'mobile_signup_strength_completion_invalid' USING ERRCODE='XX001';
    END IF;
    source_wire:=private.capture_strength_week_source(p_user_id,scope.generation,'informed_frequency','value',
      frequency,NULL::uuid,NULL::timestamptz,'mobile_signup_completion_v1',p_admission_id::text);
    SELECT v.* INTO source FROM private.strength_week_source_versions v
      WHERE v.user_id=p_user_id AND v.generation=scope.generation
        AND v.source_version_id=(source_wire->>'source_version_id')::uuid
        AND v.source_kind='informed_frequency' AND v.fact='value' AND v.planned_days=frequency
        AND v.operation_namespace='mobile_signup_completion_v1' AND v.operation_key=p_admission_id::text
        AND v.source_entity_id IS NULL AND v.source_valid_until IS NULL AND v.observed_at>=scope.opened_at;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'mobile_signup_strength_completion_invalid' USING ERRCODE='XX001';
    END IF;
  END IF;

  -- This is the database observation after the effects, not a COMMIT timestamp.
  recorded_at:=clock_timestamp();
  IF first_fresh AND (source.observed_at>recorded_at OR source.effective_week_start IS DISTINCT FROM
    (date_trunc('week',source.observed_at AT TIME ZONE source.observed_timezone)::date+7)) THEN
    RAISE EXCEPTION 'mobile_signup_strength_completion_invalid' USING ERRCODE='XX001';
  END IF;
  INSERT INTO private.mobile_signup_strength_completion_receipts(
    user_id,admission_id,epoch,outcome,completion_path,completed_at,
    generation,frequency_source_version_id,completion_result,recorded_at)
    VALUES(p_user_id,p_admission_id,admission.epoch,
      CASE WHEN first_fresh THEN 'first_fresh' ELSE 'not_first_fresh' END,
      p_completion_path,result_completed_at,scope.generation,source.source_version_id,result,recorded_at)
    RETURNING * INTO receipt;
  RETURN receipt.completion_result;
END $complete$;
REVOKE ALL ON FUNCTION public.complete_mobile_onboarding_keyed(
  uuid,jsonb,text,text,text,uuid,uuid,jsonb,boolean,timestamptz,bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_mobile_onboarding_keyed(
  uuid,jsonb,text,text,text,uuid,uuid,jsonb,boolean,timestamptz,bigint) TO service_role;

DO $acl$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_class c,
    LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
    WHERE c.oid='private.mobile_signup_strength_completion_receipts'::regclass AND a.grantee<>c.relowner)
    OR EXISTS(SELECT 1 FROM pg_proc p,
      LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE p.oid='private.preserve_mobile_signup_strength_completion_receipt()'::regprocedure
        AND a.grantee<>p.proowner)
    OR EXISTS(SELECT 1 FROM pg_proc p,
      LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE p.oid='public.complete_mobile_onboarding_keyed(uuid,jsonb,text,text,text,uuid,uuid,jsonb,boolean,timestamptz,bigint)'::regprocedure
        AND a.grantee NOT IN(p.proowner,'service_role'::regrole)) THEN
    RAISE EXCEPTION 'mobile_signup_strength_unexpected_inherited_grant' USING ERRCODE='42501';
  END IF;
END $acl$;
COMMIT;

-- Dormant processing: fence delivery/provider budget at known consent changes.
-- This does not promise instantaneous distributed revocation after authorization.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_processing_attempts) THEN
    RAISE EXCEPTION 'mobile_reevaluation_provider_deadline_requires_dormant_attempts' USING ERRCODE='55000'; END IF;
END $preflight$;
ALTER TABLE private.mobile_reevaluation_photo_processing_attempts ADD COLUMN provider_authorized_until timestamptz;
ALTER TABLE private.mobile_reevaluation_photo_processing_attempts ADD CONSTRAINT mobile_reevaluation_provider_deadline_valid CHECK(
  (provider_started_at IS NULL AND provider_authorized_until IS NULL)
  OR(provider_started_at IS NOT NULL AND provider_authorized_until IS NOT NULL
    AND isfinite(provider_authorized_until) AND provider_authorized_until>provider_started_at
    AND provider_authorized_until<=lease_until
    AND(status<>'succeeded' OR finished_at<provider_authorized_until)));
CREATE OR REPLACE FUNCTION private.preserve_mobile_reevaluation_photo_processing_attempt() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF (to_jsonb(NEW)-ARRAY['provider_started_at','provider_authorized_until','status','finished_at','result','failure_code'])
      IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['provider_started_at','provider_authorized_until','status','finished_at','result','failure_code'])
    OR(OLD.status IN('succeeded','failed','expired') AND NEW IS DISTINCT FROM OLD)
    OR NOT((OLD.status='claimed' AND NEW.status IN('authorized','failed','expired'))
      OR(OLD.status='authorized' AND NEW.status IN('succeeded','failed','expired')))
    OR(OLD.provider_started_at IS NOT NULL AND NEW.provider_started_at IS DISTINCT FROM OLD.provider_started_at) OR(OLD.provider_authorized_until IS NOT NULL AND NEW.provider_authorized_until IS DISTINCT FROM OLD.provider_authorized_until) THEN
    RAISE EXCEPTION 'mobile_reevaluation_processing_attempt_immutable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private.mobile_reevaluation_photo_processing_wire(p_context jsonb,
  t private.mobile_reevaluation_photo_processing_attempts) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT private.mobile_reevaluation_photo_asset_wire(p_context,(t).asset_id)||jsonb_build_object(
    'source_revision',(t).source_revision::text,'attempt',jsonb_build_object(
      'id',(t).request_id,'asset_id',(t).asset_id,'user_id',(t).user_id,'signup_generation',(t).signup_generation,
      'cycle_id',(t).cycle_id,'consent_acceptance_id',(t).consent_acceptance_id,'pose',(t).pose,
      'source_revision',(t).source_revision::text,'processing_request_id',(t).processing_request_id,
      'claimed_at',to_char((t).claimed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'lease_until',to_char((t).lease_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'provider_started_at',CASE WHEN(t).provider_started_at IS NULL THEN NULL ELSE to_char((t).provider_started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
      'provider_authorized_until',CASE WHEN(t).provider_authorized_until IS NULL THEN NULL ELSE to_char((t).provider_authorized_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
      'status',(t).status,'finished_at',CASE WHEN(t).finished_at IS NULL THEN NULL ELSE to_char((t).finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
      'result',(t).result,'failure_code',(t).failure_code))
$$;

CREATE OR REPLACE FUNCTION private.authorize_mobile_reevaluation_photo_provider_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; t private.mobile_reevaluation_photo_processing_attempts%ROWTYPE; at_time timestamptz; authorization_deadline timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  IF context IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_photo_source_changed' USING ERRCODE='40001'; END IF;
  SELECT a.* INTO t FROM private.mobile_reevaluation_photo_processing_attempts a
    WHERE a.request_id=p_request_id AND a.user_id=p_user_id AND a.cycle_id=p_cycle_id AND a.asset_id=p_asset_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  at_time:=(context->>'observed_at')::timestamptz;
  IF context IS NULL OR t.source_revision IS DISTINCT FROM(context->>'source_revision')::bigint
    OR NOT EXISTS(SELECT 1 FROM public.media_assets m WHERE m.id=p_asset_id AND m.status='processing' AND m.processing_request_id=t.processing_request_id)
    OR at_time>=t.lease_until THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  IF t.status<>'claimed' THEN RETURN NULL; END IF;
  -- photo_processing_context holds legal/policy SHARE locks. Recompute here:
  -- a new future document may have been published after claim. No policy is
  -- required for that boundary: an unenabled effective document also closes it.
  SELECT least(t.lease_until,min(d.required_from)) INTO authorization_deadline
    FROM public.legal_documents d
    WHERE d.document_key=context#>>'{document,document_key}'
      AND d.locale=context#>>'{document,locale}' AND d.required_from>at_time;
  IF authorization_deadline<=at_time THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  UPDATE private.mobile_reevaluation_photo_processing_attempts SET status='authorized',provider_started_at=at_time,
    provider_authorized_until=authorization_deadline WHERE request_id=p_request_id RETURNING * INTO t;
  RETURN private.mobile_reevaluation_photo_processing_wire(context,t);
END $$;

CREATE OR REPLACE FUNCTION private.complete_mobile_reevaluation_photo_processing_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_result jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; t private.mobile_reevaluation_photo_processing_attempts%ROWTYPE; at_time timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  IF context IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_photo_source_changed' USING ERRCODE='40001'; END IF;
  SELECT a.* INTO t FROM private.mobile_reevaluation_photo_processing_attempts a
    WHERE a.request_id=p_request_id AND a.user_id=p_user_id AND a.cycle_id=p_cycle_id AND a.asset_id=p_asset_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  at_time:=(context->>'observed_at')::timestamptz;
  IF context IS NULL OR t.source_revision IS DISTINCT FROM(context->>'source_revision')::bigint
    OR NOT EXISTS(SELECT 1 FROM public.media_assets m WHERE m.id=p_asset_id AND m.processing_request_id=t.processing_request_id) THEN
    RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  IF jsonb_typeof(p_result) IS DISTINCT FROM 'object' OR p_result-ARRAY['type','view','bf_percent_estimate']<>'{}'::jsonb
    OR p_result->>'type' IS DISTINCT FROM 'body' OR p_result->>'view' IS DISTINCT FROM t.pose
    OR jsonb_typeof(p_result->'bf_percent_estimate') IS DISTINCT FROM 'number' THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_analysis' USING ERRCODE='22023'; END IF;
  IF (p_result->>'bf_percent_estimate')::numeric NOT BETWEEN 3 AND 60 THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_analysis' USING ERRCODE='22023'; END IF;
  IF t.status='succeeded' THEN
    IF t.result IS DISTINCT FROM p_result THEN RAISE EXCEPTION 'mobile_reevaluation_processing_result_changed' USING ERRCODE='40001'; END IF;
    RETURN private.mobile_reevaluation_photo_processing_wire(context,t);
  END IF;
  IF t.status<>'authorized' OR t.provider_authorized_until IS NULL OR at_time>=t.provider_authorized_until THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  UPDATE public.media_assets SET status='processed',processed_at=at_time,processing_result=NULL WHERE id=p_asset_id;
  UPDATE private.mobile_reevaluation_photo_processing_attempts SET status='succeeded',finished_at=at_time,result=p_result WHERE request_id=p_request_id RETURNING * INTO t;
  RETURN private.mobile_reevaluation_photo_processing_wire(context,t);
END $$;
COMMIT;

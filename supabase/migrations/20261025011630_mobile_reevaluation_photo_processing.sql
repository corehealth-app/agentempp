-- Dormant recurring photo processing. Private readings; no job or policy activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501'; END IF;
  IF to_regclass('private.mobile_reevaluation_photo_sources') IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_requires_source_authority' USING ERRCODE='42P01'; END IF;
END $preflight$;
CREATE TABLE private.mobile_reevaluation_photo_processing_attempts(
  request_id uuid PRIMARY KEY,asset_id uuid NOT NULL,user_id uuid NOT NULL,signup_generation uuid NOT NULL,
  cycle_id uuid NOT NULL,consent_acceptance_id uuid NOT NULL,pose text NOT NULL,
  source_revision bigint NOT NULL CHECK(source_revision>0),processing_request_id text NOT NULL UNIQUE CHECK(processing_request_id~'^[0-9a-f]{64}$'),
  claimed_at timestamptz NOT NULL CHECK(isfinite(claimed_at)),lease_until timestamptz NOT NULL,
  provider_started_at timestamptz,status text NOT NULL CHECK(status IN('claimed','authorized','succeeded','failed','expired')),
  finished_at timestamptz,result jsonb,failure_code text,
  FOREIGN KEY(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose)
    REFERENCES private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose),
  CHECK(isfinite(lease_until) AND lease_until>claimed_at AND lease_until<=claimed_at+interval '300seconds'),
  CHECK(provider_started_at IS NULL OR(isfinite(provider_started_at) AND provider_started_at>=claimed_at AND provider_started_at<lease_until)),
  CHECK(finished_at IS NULL OR(isfinite(finished_at) AND finished_at>=claimed_at)),
  CHECK(failure_code IS NULL OR failure_code IN('storage_unavailable','invalid_bytes','provider_unavailable','invalid_analysis')),
  CHECK((status='claimed' AND provider_started_at IS NULL AND finished_at IS NULL AND result IS NULL AND failure_code IS NULL)
    OR(status='authorized' AND provider_started_at IS NOT NULL AND finished_at IS NULL AND result IS NULL AND failure_code IS NULL)
    OR(status='succeeded' AND provider_started_at IS NOT NULL AND finished_at IS NOT NULL AND result IS NOT NULL AND failure_code IS NULL)
    OR(status='failed' AND finished_at IS NOT NULL AND result IS NULL AND failure_code IS NOT NULL)
    OR(status='expired' AND finished_at IS NOT NULL AND result IS NULL AND failure_code IS NULL))
);
CREATE INDEX mobile_reevaluation_processing_asset ON private.mobile_reevaluation_photo_processing_attempts(user_id,cycle_id,asset_id);
ALTER TABLE private.mobile_reevaluation_photo_processing_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_processing_attempts FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.preserve_mobile_reevaluation_photo_processing_attempt() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF (to_jsonb(NEW)-ARRAY['provider_started_at','status','finished_at','result','failure_code'])
      IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['provider_started_at','status','finished_at','result','failure_code'])
    OR(OLD.status IN('succeeded','failed','expired') AND NEW IS DISTINCT FROM OLD)
    OR NOT((OLD.status='claimed' AND NEW.status IN('authorized','failed','expired'))
      OR(OLD.status='authorized' AND NEW.status IN('succeeded','failed','expired')))
    OR(OLD.provider_started_at IS NOT NULL AND NEW.provider_started_at IS DISTINCT FROM OLD.provider_started_at) THEN
    RAISE EXCEPTION 'mobile_reevaluation_processing_attempt_immutable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_photo_processing_attempt BEFORE UPDATE ON private.mobile_reevaluation_photo_processing_attempts
  FOR EACH ROW EXECUTE FUNCTION private.preserve_mobile_reevaluation_photo_processing_attempt();

CREATE FUNCTION private.mobile_reevaluation_photo_processing_context(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; source private.mobile_reevaluation_photo_sources%ROWTYPE; asset_wire jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_asset_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_processing' USING ERRCODE='22023'; END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001'; END IF;
  SELECT s.* INTO source FROM private.mobile_reevaluation_photo_sources s
    WHERE s.user_id=p_user_id AND s.cycle_id=p_cycle_id
      AND s.signup_generation=(context->>'signup_generation')::uuid
      AND s.consent_acceptance_id=(context#>>'{current_acceptance,acceptance_id}')::uuid
      AND s.requested_asset_id=p_asset_id AND s.selected_asset_id=p_asset_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  PERFORM m.id FROM public.media_assets m WHERE m.id=p_asset_id AND m.user_id=p_user_id AND m.reevaluation_origin_version=1 FOR UPDATE;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001'; END IF;
  asset_wire:=private.mobile_reevaluation_photo_asset_wire(context,p_asset_id);
  IF asset_wire IS NULL THEN RETURN NULL; END IF;
  RETURN context||jsonb_build_object('source_revision',source.source_revision::text);
END $$;

CREATE FUNCTION private.mobile_reevaluation_photo_processing_wire(p_context jsonb,
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
      'status',(t).status,'finished_at',CASE WHEN(t).finished_at IS NULL THEN NULL ELSE to_char((t).finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
      'result',(t).result,'failure_code',(t).failure_code))
$$;

CREATE FUNCTION private.claim_mobile_reevaluation_photo_processing_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; t private.mobile_reevaluation_photo_processing_attempts%ROWTYPE;
  old_attempt private.mobile_reevaluation_photo_processing_attempts%ROWTYPE;
  asset public.media_assets%ROWTYPE; at_time timestamptz; source_revision bigint; request_hash text; pose text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_processing' USING ERRCODE='22023'; END IF;
  context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  IF context IS NULL THEN RETURN NULL; END IF;
  source_revision:=(context->>'source_revision')::bigint;
  SELECT m.* INTO asset FROM public.media_assets m WHERE m.id=p_asset_id;
  SELECT a.* INTO t FROM private.mobile_reevaluation_photo_processing_attempts a WHERE a.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF ROW(t.user_id,t.cycle_id,t.asset_id,t.signup_generation,t.consent_acceptance_id)
      IS DISTINCT FROM ROW(p_user_id,p_cycle_id,p_asset_id,(context->>'signup_generation')::uuid,(context#>>'{current_acceptance,acceptance_id}')::uuid) THEN
      RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
    context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
    IF context IS NULL OR t.source_revision IS DISTINCT FROM(context->>'source_revision')::bigint OR asset.processing_request_id IS DISTINCT FROM t.processing_request_id THEN RETURN NULL; END IF;
    IF t.status IN('succeeded','failed') THEN RETURN private.mobile_reevaluation_photo_processing_wire(context,t); END IF;
    RETURN NULL;
  END IF;
  IF asset.status NOT IN('uploaded','processing') THEN RETURN NULL; END IF;
  IF asset.status='processing' THEN
    SELECT a.* INTO old_attempt FROM private.mobile_reevaluation_photo_processing_attempts a
      WHERE a.processing_request_id=asset.processing_request_id AND a.asset_id=p_asset_id AND a.user_id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_processing_attempt_missing' USING ERRCODE='XX001'; END IF;
  END IF;
  context:=private.mobile_reevaluation_photo_processing_context(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  IF context IS NULL THEN RETURN NULL; END IF;
  at_time:=(context->>'observed_at')::timestamptz;
  IF old_attempt.request_id IS NOT NULL AND old_attempt.status IN('claimed','authorized') THEN
    IF at_time<old_attempt.lease_until THEN RETURN NULL; END IF;
    UPDATE private.mobile_reevaluation_photo_processing_attempts SET status='expired',finished_at=at_time WHERE request_id=old_attempt.request_id;
  ELSIF old_attempt.request_id IS NOT NULL AND old_attempt.status NOT IN('failed','expired') THEN RETURN NULL;
  END IF;
  SELECT l.pose INTO pose FROM private.mobile_reevaluation_photo_assets l WHERE l.asset_id=p_asset_id;
  request_hash:=encode(extensions.digest('reevaluation_processing_v1:'||p_request_id::text||':'||p_asset_id::text||':'||source_revision::text,'sha256'),'hex');
  INSERT INTO private.mobile_reevaluation_photo_processing_attempts(request_id,asset_id,user_id,signup_generation,cycle_id,
    consent_acceptance_id,pose,source_revision,processing_request_id,claimed_at,lease_until,status)
    VALUES(p_request_id,p_asset_id,p_user_id,(context->>'signup_generation')::uuid,p_cycle_id,
      (context#>>'{current_acceptance,acceptance_id}')::uuid,pose,source_revision,request_hash,at_time,
      least(at_time+interval '300seconds',
        (context#>>'{current_acceptance,last_activity_at}')::timestamptz+make_interval(secs=>(context#>>'{document,idle_timeout_seconds}')::integer),asset.retention_until),'claimed') RETURNING * INTO t;
  UPDATE public.media_assets SET status='processing',processing_request_id=request_hash,processing_result=NULL,processed_at=NULL WHERE id=p_asset_id;
  RETURN private.mobile_reevaluation_photo_processing_wire(context,t);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001';
END $$;

CREATE FUNCTION private.authorize_mobile_reevaluation_photo_provider_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_observed_at timestamptz) RETURNS jsonb
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
    OR NOT EXISTS(SELECT 1 FROM public.media_assets m WHERE m.id=p_asset_id AND m.status='processing' AND m.processing_request_id=t.processing_request_id)
    OR at_time>=t.lease_until THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  IF t.status<>'claimed' THEN RETURN NULL; END IF;
  UPDATE private.mobile_reevaluation_photo_processing_attempts SET status='authorized',provider_started_at=at_time WHERE request_id=p_request_id RETURNING * INTO t;
  RETURN private.mobile_reevaluation_photo_processing_wire(context,t);
END $$;

CREATE FUNCTION private.complete_mobile_reevaluation_photo_processing_at(
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
  IF t.status<>'authorized' OR at_time>=t.lease_until THEN RAISE EXCEPTION 'mobile_reevaluation_processing_request_changed' USING ERRCODE='40001'; END IF;
  UPDATE public.media_assets SET status='processed',processed_at=at_time,processing_result=NULL WHERE id=p_asset_id;
  UPDATE private.mobile_reevaluation_photo_processing_attempts SET status='succeeded',finished_at=at_time,result=p_result WHERE request_id=p_request_id RETURNING * INTO t;
  RETURN private.mobile_reevaluation_photo_processing_wire(context,t);
END $$;

CREATE FUNCTION private.fail_mobile_reevaluation_photo_processing_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_failure_code text,p_observed_at timestamptz) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t private.mobile_reevaluation_photo_processing_attempts%ROWTYPE; at_time timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_failure_code IS NULL OR p_failure_code NOT IN('storage_unavailable','invalid_bytes','provider_unavailable','invalid_analysis') THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_processing_failure' USING ERRCODE='22023'; END IF;
  -- Only private attempt bookkeeping, like late signed-ticket registration.
  -- No source/result/media/activity write; owner may already be soft-deleted.
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT a.* INTO t FROM private.mobile_reevaluation_photo_processing_attempts a
    WHERE a.request_id=p_request_id AND a.user_id=p_user_id AND a.cycle_id=p_cycle_id AND a.asset_id=p_asset_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF t.status='failed' THEN RETURN t.failure_code=p_failure_code; END IF;
  IF t.status NOT IN('claimed','authorized') THEN RETURN false; END IF;
  at_time:=coalesce(p_observed_at,clock_timestamp());
  IF NOT isfinite(at_time) OR at_time<t.claimed_at THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_processing_clock' USING ERRCODE='22023'; END IF;
  UPDATE private.mobile_reevaluation_photo_processing_attempts SET status='failed',finished_at=at_time,failure_code=p_failure_code WHERE request_id=p_request_id;
  RETURN true;
END $$;

CREATE FUNCTION private.get_mobile_reevaluation_photo_snapshot_at(p_user_id uuid,p_cycle_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; slots jsonb; opened_at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  PERFORM m.id FROM public.media_assets m JOIN private.mobile_reevaluation_photo_sources s ON s.selected_asset_id=m.id
    WHERE s.user_id=p_user_id AND s.cycle_id=p_cycle_id ORDER BY m.id FOR SHARE OF m;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001'; END IF;
  SELECT c.opened_at INTO opened_at FROM private.mobile_reevaluation_cycles c WHERE c.cycle_id=p_cycle_id;
  SELECT jsonb_agg(jsonb_build_object('pose',p.pose,'photo',CASE WHEN m.id IS NULL THEN NULL ELSE
    jsonb_build_object('asset_id',m.id,'user_id',m.user_id,'signup_generation',l.signup_generation,'cycle_id',l.cycle_id,
      'consent_acceptance_id',l.consent_acceptance_id,'origin','reevaluation_cycle_v1',
      'status',CASE WHEN t.status='failed' THEN 'failed' WHEN m.status='processed' AND t.status IS DISTINCT FROM 'succeeded' THEN 'processing' ELSE m.status::text END,
      'created_at',to_char(m.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'uploaded_at',to_char(m.uploaded_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'processed_at',CASE WHEN t.status='succeeded' AND m.status='processed' THEN to_char(t.finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') ELSE NULL END,
      'analysis',CASE WHEN t.status='succeeded' AND m.status='processed' THEN t.result ELSE NULL END) END) ORDER BY p.ordinality)
    INTO slots FROM unnest(ARRAY['front','side','back']) WITH ORDINALITY p(pose,ordinality)
    LEFT JOIN private.mobile_reevaluation_photo_sources s ON s.user_id=p_user_id AND s.cycle_id=p_cycle_id AND s.pose=p.pose
      AND s.signup_generation=(context->>'signup_generation')::uuid
      AND s.consent_acceptance_id=(context#>>'{current_acceptance,acceptance_id}')::uuid AND s.requested_asset_id=s.selected_asset_id
    LEFT JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=s.selected_asset_id AND l.invalidated_at IS NULL
    LEFT JOIN public.media_assets m ON m.id=l.asset_id AND m.user_id=l.user_id AND m.reevaluation_origin_version=1 AND m.status<>'deleted'
    LEFT JOIN private.mobile_reevaluation_photo_processing_attempts t ON t.asset_id=m.id AND t.user_id=m.user_id
      AND t.signup_generation=l.signup_generation AND t.cycle_id=l.cycle_id AND t.consent_acceptance_id=l.consent_acceptance_id
      AND t.pose=l.pose AND t.source_revision=s.source_revision AND t.processing_request_id=m.processing_request_id;
  RETURN jsonb_build_object('version',1,'user_id',p_user_id,'signup_generation',context->'signup_generation',
    'cycle_id',p_cycle_id,'cycle_revision',context->'cycle_revision','opened_at',to_char(opened_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'observed_at',to_char((context->>'observed_at')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'consent',jsonb_build_object('acceptance_id',context#>'{current_acceptance,acceptance_id}',
      'document_id',context#>'{current_acceptance,document_id}','document_key',context#>'{current_acceptance,document_key}',
      'version',context#>'{current_acceptance,version}','locale',context#>'{current_acceptance,locale}','body_hash',context#>'{current_acceptance,body_hash}',
      'accepted_at',to_char((context#>>'{current_acceptance,accepted_at}')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),'photos',slots);
END $$;

CREATE FUNCTION public.claim_mobile_reevaluation_photo_processing(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.claim_mobile_reevaluation_photo_processing_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,NULL::timestamptz)
$$;

CREATE FUNCTION public.authorize_mobile_reevaluation_photo_provider(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.authorize_mobile_reevaluation_photo_provider_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,NULL::timestamptz)
$$;

CREATE FUNCTION public.complete_mobile_reevaluation_photo_processing(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_result jsonb) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.complete_mobile_reevaluation_photo_processing_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,p_result,NULL::timestamptz)
$$;

CREATE FUNCTION public.fail_mobile_reevaluation_photo_processing(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_request_id uuid,p_failure_code text) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.fail_mobile_reevaluation_photo_processing_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,p_failure_code,NULL::timestamptz)
$$;

CREATE FUNCTION public.get_mobile_reevaluation_photo_snapshot(p_user_id uuid,p_cycle_id uuid) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.get_mobile_reevaluation_photo_snapshot_at(p_user_id,p_cycle_id,NULL::timestamptz)
$$;

REVOKE ALL ON FUNCTION private.preserve_mobile_reevaluation_photo_processing_attempt(),
  private.mobile_reevaluation_photo_processing_context(uuid,uuid,uuid,timestamptz),
  private.mobile_reevaluation_photo_processing_wire(jsonb,private.mobile_reevaluation_photo_processing_attempts),
  private.claim_mobile_reevaluation_photo_processing_at(uuid,uuid,uuid,uuid,timestamptz),
  public.claim_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid),
  private.authorize_mobile_reevaluation_photo_provider_at(uuid,uuid,uuid,uuid,timestamptz),
  public.authorize_mobile_reevaluation_photo_provider(uuid,uuid,uuid,uuid),
  private.complete_mobile_reevaluation_photo_processing_at(uuid,uuid,uuid,uuid,jsonb,timestamptz),
  public.complete_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid,jsonb),
  private.fail_mobile_reevaluation_photo_processing_at(uuid,uuid,uuid,uuid,text,timestamptz),
  public.fail_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid,text),
  private.get_mobile_reevaluation_photo_snapshot_at(uuid,uuid,timestamptz),
  public.get_mobile_reevaluation_photo_snapshot(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid),
  public.authorize_mobile_reevaluation_photo_provider(uuid,uuid,uuid,uuid),
  public.complete_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid,jsonb),
  public.fail_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid,text),
  public.get_mobile_reevaluation_photo_snapshot(uuid,uuid) TO service_role;
COMMIT;

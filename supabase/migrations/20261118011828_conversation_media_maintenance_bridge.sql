-- Default-OFF cleanup-only transport in the existing staging project.
-- No Storage deletion, legacy enrollment, Inngest change or active cron here.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$BEGIN
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.claim_conversation_media_expiry_batch(integer)'::regprocedure) IS DISTINCT FROM '6b5f033529bc601813192c2f7fcc6f9ef71dd81ec205617af00516b485f542f8' THEN RAISE EXCEPTION 'media_maintenance_source_drift';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.claim_conversation_media_disposal_batch_v2(integer)'::regprocedure) IS DISTINCT FROM '81d0c73c6a703c1dfe3c79173d95aea7c934b7594bf7f80abf37ed3b2ec5060e' THEN RAISE EXCEPTION 'media_maintenance_source_drift';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.claim_mobile_reevaluation_photo_cleanup_scopes(integer)'::regprocedure) IS DISTINCT FROM '5a6c66f288332ace1ec96b68c10d174cc498ba7245dbd6f36b75b12fa769f04e' THEN RAISE EXCEPTION 'media_maintenance_source_drift';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='private.conversation_media_retention_eligible(uuid,uuid,text,text,text)'::regprocedure) IS DISTINCT FROM '1b52223b5958561d626ec1728f4096ecf6d0e10a619ad86e5334650938a03a48' THEN RAISE EXCEPTION 'media_maintenance_source_drift';END IF;
END$$;
CREATE TABLE private.conversation_media_maintenance_config(
 singleton boolean PRIMARY KEY CHECK(singleton),enabled boolean NOT NULL DEFAULT false
);
INSERT INTO private.conversation_media_maintenance_config(singleton) VALUES(true);
CREATE TABLE private.conversation_media_maintenance_lanes(
 lane text PRIMARY KEY CHECK(lane IN('private','ordinary','recurring','accounts')),
 dispatch_id uuid UNIQUE,token_sha256 text CHECK(token_sha256 ~ '^[0-9a-f]{64}$'),
 state text NOT NULL DEFAULT 'idle' CHECK(state IN('idle','queued','running','completed','retry')),
 queued_at timestamptz CHECK(isfinite(queued_at)),lease_id uuid,lease_until timestamptz CHECK(isfinite(lease_until)),
 next_attempt_at timestamptz NOT NULL DEFAULT '-infinity',last_completed_at timestamptz,
 CHECK((dispatch_id IS NULL)=(token_sha256 IS NULL)),
 CHECK(state<>'queued' OR(dispatch_id IS NOT NULL AND queued_at IS NOT NULL)),
 CHECK(state<>'running' OR(lease_id IS NOT NULL AND lease_until IS NOT NULL))
);
INSERT INTO private.conversation_media_maintenance_lanes(lane) VALUES('private'),('ordinary'),('recurring'),('accounts');
ALTER TABLE private.conversation_media_maintenance_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_media_maintenance_lanes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_maintenance_config,private.conversation_media_maintenance_lanes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.conversation_media_maintenance_due(p_lane text) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz:=statement_timestamp();BEGIN
 IF p_lane='private' THEN RETURN
 EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 d WHERE d.lease_until IS NULL OR d.lease_until<=at_time)
 OR EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 x WHERE(x.retention_until<=at_time OR x.status='deleted'
  OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 o WHERE o.asset_id=x.id AND o.closed_at IS NOT NULL)
  OR NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=x.user_id AND u.status='active'))
  AND NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 d WHERE d.asset_id=x.id))
 OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 o WHERE(o.closed_at IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 m WHERE m.id=o.asset_id))
  AND NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 d WHERE d.asset_id=o.asset_id));
 ELSIF p_lane='ordinary' THEN RETURN
 EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE(x.lease_until IS NULL OR x.lease_until<=at_time)
  AND private.conversation_media_retention_eligible(x.asset_id,x.user_id,x.kind,x.bucket_id,x.object_path))
 OR EXISTS(SELECT 1 FROM public.media_assets a WHERE a.kind IN('conversation_photo','audio_note') AND a.retention_until<=at_time
  AND a.reevaluation_origin_version IS NULL AND private.conversation_media_retention_eligible(a.id,a.user_id,a.kind,a.bucket_id,a.object_path)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.asset_id=a.id));
 ELSIF p_lane='accounts' THEN RETURN EXISTS(SELECT 1 FROM public.users WHERE status='deleted' AND updated_at<=at_time-interval '1 hour');
 ELSIF p_lane='recurring' THEN RETURN EXISTS(
 SELECT 1 FROM private.mobile_reevaluation_photo_consents a
   JOIN public.users u ON u.id=a.user_id
   JOIN private.mobile_reevaluation_cycles c ON c.cycle_id=a.cycle_id AND c.user_id=a.user_id
   LEFT JOIN public.user_profiles p ON p.user_id=a.user_id
   LEFT JOIN private.workout_strength_authority_epochs e ON e.user_id=a.user_id
   LEFT JOIN private.mobile_clinical_generation_sources source ON source.user_id=a.user_id AND source.generation=a.signup_generation
   LEFT JOIN private.mobile_signup_strength_completion_receipts r ON r.user_id=a.user_id AND r.admission_id=a.signup_generation
   LEFT JOIN private.mobile_clinical_legacy_admissions legacy ON legacy.user_id=a.user_id AND legacy.generation=a.signup_generation
   LEFT JOIN private.mobile_reevaluation_photo_dispositions h ON h.acceptance_id=a.acceptance_id
   LEFT JOIN private.mobile_reevaluation_photo_cleanup_visits v ON v.acceptance_id=a.acceptance_id
   LEFT JOIN LATERAL(
    SELECT d.id FROM public.legal_documents d WHERE d.document_key='body_photo_reevaluation_consent'
     AND d.locale=u.locale AND d.required_from<=at_time ORDER BY d.required_from DESC,d.created_at DESC,d.id DESC LIMIT 1
   ) doc ON true
   LEFT JOIN private.mobile_reevaluation_photo_policies policy ON policy.document_id=doc.id
  WHERE u.status<>'deleted' AND (
   (h.disposition_id IS NULL AND (
    a.revoked_at IS NOT NULL OR a.last_activity_at+make_interval(secs=>a.idle_timeout_seconds)<=at_time
    OR c.status NOT IN('open','collecting','review_ready')
    OR p.onboarding_completed IS DISTINCT FROM true OR c.signup_epoch IS DISTINCT FROM e.epoch
    OR (source.epoch=c.signup_epoch AND (
     (source.kind='signup_receipt' AND r.epoch=c.signup_epoch AND r.outcome='first_fresh'
      AND r.completed_at IS NOT DISTINCT FROM p.onboarding_completed_at AND r.completed_at<=at_time)
     OR (source.kind='legacy_transition' AND legacy.epoch=c.signup_epoch
      AND legacy.profile_completed_marker IS NOT DISTINCT FROM p.onboarding_completed_at AND legacy.admitted_at<=at_time)
    )) IS DISTINCT FROM true
    OR a.document_id IS DISTINCT FROM doc.id OR a.locale IS DISTINCT FROM u.locale OR policy.enabled IS DISTINCT FROM true
   )) OR (h.disposition_id IS NOT NULL AND (h.sweep_state IN('idle','pending')
    OR(h.sweep_state='waiting' AND h.next_sweep_at<=at_time)))
  )
  );
 ELSE RAISE EXCEPTION 'invalid_media_maintenance_lane' USING ERRCODE='22023';END IF;
END$$;
REVOKE ALL ON FUNCTION private.conversation_media_maintenance_due(text) FROM PUBLIC,anon,authenticated,service_role;

-- Only the trusted scheduler may enqueue. It sends a different 256-bit token
-- for each job; the database keeps only its hash. pg_net's internal request
-- queue contains the transient header, never a provider/service-role key.
CREATE FUNCTION public.dispatch_due_conversation_media_maintenance() RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE l private.conversation_media_maintenance_lanes%ROWTYPE;at_time timestamptz:=clock_timestamp();
 raw_token text;job uuid;sent integer:=0;request_id bigint;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_media_maintenance_transaction';END IF;
 PERFORM 1 FROM private.conversation_media_maintenance_config WHERE singleton AND enabled FOR SHARE;
 IF NOT FOUND THEN RETURN 0;END IF;
 FOR l IN SELECT * FROM private.conversation_media_maintenance_lanes
  WHERE next_attempt_at<=at_time AND
   (state NOT IN('queued','running') OR(state='queued' AND queued_at<=at_time-interval '2 minutes')
    OR(state='running' AND lease_until<=at_time))
  ORDER BY next_attempt_at,lane FOR UPDATE SKIP LOCKED LOOP
  IF NOT private.conversation_media_maintenance_due(l.lane) THEN CONTINUE;END IF;
  raw_token:=encode(extensions.gen_random_bytes(32),'hex');job:=gen_random_uuid();
  UPDATE private.conversation_media_maintenance_lanes SET dispatch_id=job,
   token_sha256=encode(extensions.digest(raw_token,'sha256'),'hex'),state='queued',queued_at=clock_timestamp(),
   lease_id=NULL,lease_until=NULL,next_attempt_at=clock_timestamp()+interval '1 minute' WHERE lane=l.lane;
  SELECT net.http_post(
   url:='https://xitugspwfxkcluxvrdeg.supabase.co/functions/v1/conversation-media-maintenance',
   headers:=jsonb_build_object('Content-Type','application/json','x-performe-maintenance-token',raw_token),
   body:=jsonb_build_object('dispatch_id',job),timeout_milliseconds:=60000) INTO request_id;
  IF request_id IS NULL THEN RAISE EXCEPTION 'media_maintenance_dispatch_unavailable';END IF;
  sent:=sent+1;
 END LOOP;
 RETURN sent;
END$$;

CREATE FUNCTION public.claim_conversation_media_maintenance(p_dispatch_id uuid,p_token_sha256 text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE l private.conversation_media_maintenance_lanes%ROWTYPE;at_time timestamptz:=clock_timestamp();BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_dispatch_id IS NULL OR p_token_sha256 IS NULL OR p_token_sha256!~'^[0-9a-f]{64}$' THEN RETURN NULL;END IF;
 PERFORM 1 FROM private.conversation_media_maintenance_config WHERE singleton AND enabled FOR SHARE;
 IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO l FROM private.conversation_media_maintenance_lanes WHERE dispatch_id=p_dispatch_id FOR UPDATE;
 IF NOT FOUND OR l.state<>'queued' OR l.token_sha256<>p_token_sha256 OR l.queued_at<=at_time-interval '2 minutes'
  OR l.queued_at>at_time THEN RETURN NULL;END IF;
 UPDATE private.conversation_media_maintenance_lanes SET state='running',lease_id=gen_random_uuid(),
  lease_until=clock_timestamp()+interval '65 seconds' WHERE lane=l.lane RETURNING * INTO l;
 RETURN jsonb_build_object('schema','conversation.media-maintenance-lease.v1','dispatch_id',l.dispatch_id,
  'lease_id',l.lease_id,'lane',l.lane,'expires_at',l.lease_until);
END$$;

CREATE FUNCTION public.complete_conversation_media_maintenance(p_dispatch_id uuid,p_lease_id uuid,p_outcome text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE l private.conversation_media_maintenance_lanes%ROWTYPE;at_time timestamptz:=clock_timestamp();BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_dispatch_id IS NULL OR p_lease_id IS NULL OR p_outcome IS NULL OR p_outcome NOT IN('completed','retry') THEN RETURN false;END IF;
 PERFORM 1 FROM private.conversation_media_maintenance_config WHERE singleton AND enabled FOR SHARE;
 IF NOT FOUND THEN RETURN false;END IF;
 SELECT * INTO l FROM private.conversation_media_maintenance_lanes WHERE dispatch_id=p_dispatch_id FOR UPDATE;
 IF NOT FOUND OR l.lease_id IS DISTINCT FROM p_lease_id THEN RETURN false;END IF;
 IF l.state=p_outcome THEN RETURN true;END IF;
 IF l.state<>'running' OR l.lease_until<=at_time THEN RETURN false;END IF;
 UPDATE private.conversation_media_maintenance_lanes SET state=p_outcome,
  next_attempt_at=CASE WHEN p_outcome='retry' THEN at_time+interval '30 seconds'
   WHEN l.lane IN('private','accounts') THEN at_time+interval '15 minutes'
   WHEN l.lane='ordinary' THEN at_time+interval '1 hour'
   ELSE date_trunc('minute',at_time)+interval '1 minute' END,
  last_completed_at=CASE WHEN p_outcome='completed' THEN at_time ELSE last_completed_at END
  WHERE lane=l.lane;
 RETURN true;
END$$;

-- Operator-controlled handover only after hosted Edge/cleanup qualification.
-- No unrelated database cron is enabled or disabled by this function.
CREATE FUNCTION public.configure_conversation_media_maintenance(p_enabled boolean,p_project_ref text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE j record;BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_enabled IS NULL OR p_project_ref IS DISTINCT FROM 'xitugspwfxkcluxvrdeg' THEN RAISE EXCEPTION 'invalid_media_maintenance_target';END IF;
 UPDATE private.conversation_media_maintenance_config SET enabled=p_enabled WHERE singleton;
 IF p_enabled THEN
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='performe-conversation-media-maintenance' AND
   (schedule<>'* * * * *' OR command<>'SELECT public.dispatch_due_conversation_media_maintenance();' OR database<>current_database() OR username<>current_user)) THEN
   RAISE EXCEPTION 'media_maintenance_cron_conflict';END IF;
  PERFORM cron.schedule('performe-conversation-media-maintenance','* * * * *','SELECT public.dispatch_due_conversation_media_maintenance();');
 ELSE
  FOR j IN SELECT jobid FROM cron.job WHERE jobname='performe-conversation-media-maintenance'
   AND database=current_database() AND username=current_user LOOP PERFORM cron.unschedule(j.jobid);END LOOP;
 END IF;
 RETURN true;
END$$;

REVOKE ALL ON FUNCTION public.dispatch_due_conversation_media_maintenance(),public.claim_conversation_media_maintenance(uuid,text),
 public.complete_conversation_media_maintenance(uuid,uuid,text),public.configure_conversation_media_maintenance(boolean,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_due_conversation_media_maintenance(),public.claim_conversation_media_maintenance(uuid,text),
 public.complete_conversation_media_maintenance(uuid,uuid,text),public.configure_conversation_media_maintenance(boolean,text) TO service_role;
COMMIT;

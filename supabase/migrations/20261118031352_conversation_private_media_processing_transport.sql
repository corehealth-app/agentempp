-- Default-OFF durable transport in the existing staging database/worker.
-- No new provider, key retrieval, legacy catalog change or active cron at install.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_assets_v2') IS NULL
  OR to_regprocedure('public.claim_conversation_media_processing_v2(uuid,uuid,text)') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='supabase_vault')
  OR NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net') THEN
  RAISE EXCEPTION 'private_processing_transport_substrate_required';END IF;
END$$;
CREATE TABLE private.conversation_media_processing_transport_v2(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),enabled boolean NOT NULL DEFAULT false,
 target_url text,source_sha text,secret_id uuid,setup_token_sha256 text,setup_expires_at timestamptz,
 CHECK(target_url IS NULL OR target_url~'^https://agentempp-media-worker-staging-[a-z0-9]+-gestao-9664s-projects\.vercel\.app$'),
 CHECK(source_sha IS NULL OR source_sha~'^[0-9a-f]{40}$'),
 CHECK(setup_token_sha256 IS NULL OR setup_token_sha256~'^[0-9a-f]{64}$'),
 CHECK(NOT enabled OR(target_url IS NOT NULL AND source_sha IS NOT NULL AND secret_id IS NOT NULL AND setup_token_sha256 IS NULL))
);
ALTER TABLE private.conversation_media_processing_transport_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_processing_transport_v2 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.conversation_media_processing_transport_v2(singleton) VALUES(true);
CREATE TABLE private.conversation_media_processing_jobs_v2(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),asset_id uuid NOT NULL REFERENCES private.conversation_media_assets_v2(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,request_id text NOT NULL CHECK(request_id~'^[0-9a-f]{64}$'),
 state text NOT NULL DEFAULT 'waiting' CHECK(state IN('waiting','queued','running','completed','cancelled','failed')),
 next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),failure_count integer NOT NULL DEFAULT 0 CHECK(failure_count BETWEEN 0 AND 4),
 dispatch_id uuid UNIQUE,token_sha256 text CHECK(token_sha256 IS NULL OR token_sha256~'^[0-9a-f]{64}$'),
 dispatched_source_sha text,queued_at timestamptz,lease_id uuid,lease_until timestamptz,last_outcome text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(asset_id,request_id),
 CHECK(state<>'queued' OR(dispatch_id IS NOT NULL AND token_sha256 IS NOT NULL AND queued_at IS NOT NULL)),
 CHECK(state<>'running' OR(lease_id IS NOT NULL AND lease_until IS NOT NULL))
);
ALTER TABLE private.conversation_media_processing_jobs_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_processing_jobs_v2 FROM PUBLIC,anon,authenticated,service_role;
CREATE UNIQUE INDEX conversation_media_processing_one_active_v2 ON private.conversation_media_processing_jobs_v2(asset_id) WHERE state IN('waiting','queued','running');
CREATE INDEX conversation_media_processing_owner_v2 ON private.conversation_media_processing_jobs_v2(user_id);
CREATE INDEX conversation_media_processing_due_v2 ON private.conversation_media_processing_jobs_v2(next_attempt_at) WHERE state IN('waiting','queued','running');

CREATE FUNCTION public.prepare_conversation_media_processing_transport_v2(p_project_ref text,p_target_url text,p_source_sha text,p_setup_token_sha256 text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_project_ref IS DISTINCT FROM 'xitugspwfxkcluxvrdeg' OR p_target_url IS NULL
  OR p_target_url!~'^https://agentempp-media-worker-staging-[a-z0-9]+-gestao-9664s-projects\.vercel\.app$'
  OR p_source_sha IS NULL OR p_source_sha!~'^[0-9a-f]{40}$' OR p_setup_token_sha256 IS NULL OR p_setup_token_sha256!~'^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'invalid_private_processing_target' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM private.conversation_media_processing_transport_v2 WHERE singleton FOR UPDATE;
 IF EXISTS(SELECT 1 FROM private.conversation_media_processing_transport_v2 WHERE enabled)
  OR EXISTS(SELECT 1 FROM private.conversation_media_processing_jobs_v2 WHERE state='running' AND lease_until>clock_timestamp()) THEN
  RAISE EXCEPTION 'private_processing_handover_busy' USING ERRCODE='40001';END IF;
 UPDATE private.conversation_media_processing_transport_v2 SET target_url=p_target_url,source_sha=p_source_sha,
  setup_token_sha256=p_setup_token_sha256,setup_expires_at=clock_timestamp()+interval '10minutes' WHERE singleton;
 -- Invalidate queued callbacks to the old deployment; no media/source is changed.
 UPDATE private.conversation_media_processing_jobs_v2 SET state='waiting',next_attempt_at=clock_timestamp(),dispatch_id=NULL,token_sha256=NULL,queued_at=NULL,lease_id=NULL,lease_until=NULL WHERE state IN('queued','running');
 RETURN true;
END$$;
CREATE FUNCTION public.register_conversation_media_processing_transport_v2(p_target_url text,p_source_sha text,p_setup_token_sha256 text,p_bypass_secret text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.conversation_media_processing_transport_v2%ROWTYPE;secret uuid;BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO c FROM private.conversation_media_processing_transport_v2 WHERE singleton FOR UPDATE;
 IF c.enabled OR c.target_url IS DISTINCT FROM p_target_url OR c.source_sha IS DISTINCT FROM p_source_sha
  OR c.setup_token_sha256 IS NULL OR c.setup_token_sha256 IS DISTINCT FROM p_setup_token_sha256
  OR c.setup_expires_at<=clock_timestamp() OR p_bypass_secret IS NULL OR length(p_bypass_secret) NOT BETWEEN 8 AND 1024
  OR p_bypass_secret~'[[:cntrl:]]' THEN RETURN false;END IF;
 secret:=c.secret_id;
 IF secret IS NULL THEN SELECT vault.create_secret(p_bypass_secret,'performe-private-media-worker-bypass-v2','Existing Vercel worker automation credential; task transport only') INTO secret;
 ELSE PERFORM vault.update_secret(secret,p_bypass_secret);END IF;
 UPDATE private.conversation_media_processing_transport_v2 SET secret_id=secret,setup_token_sha256=NULL,setup_expires_at=NULL WHERE singleton;
 RETURN true;
END$$;

-- A terminal transport error becomes visible through the existing guarded
-- media failure protocol. No model is invoked and a live core lease is deferred.
CREATE FUNCTION private.fail_conversation_media_processing_transport_v2(p_job_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$DECLARE j private.conversation_media_processing_jobs_v2%ROWTYPE;q jsonb;BEGIN
 SELECT * INTO j FROM private.conversation_media_processing_jobs_v2 WHERE id=p_job_id;
 q:=public.claim_conversation_media_processing_v2(j.user_id,j.asset_id,j.request_id);
 IF q->>'action'='busy' THEN
  UPDATE private.conversation_media_processing_jobs_v2 SET state='waiting',next_attempt_at=(q->>'retry_at')::timestamptz+interval '1second' WHERE id=j.id;RETURN;
 END IF;
 IF q->>'action'='claimed' THEN
  IF NOT public.fail_conversation_media_processing_v2(j.user_id,j.asset_id,j.request_id,(q#>>'{claim,token}')::uuid,'worker_transport_unavailable') THEN
   RAISE EXCEPTION 'private_processing_failure_uncertain';END IF;
 END IF;
 UPDATE private.conversation_media_processing_jobs_v2 SET state='failed',last_outcome='failed' WHERE id=j.id;
END$$;
REVOKE ALL ON FUNCTION private.fail_conversation_media_processing_transport_v2(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.dispatch_due_conversation_media_processing_v2() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE c private.conversation_media_processing_transport_v2%ROWTYPE;j private.conversation_media_processing_jobs_v2%ROWTYPE;
 at_time timestamptz:=clock_timestamp();raw_token text;bypass text;sent integer:=0;slots integer;request_id bigint;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_private_processing_isolation';END IF;
 -- Exclusive config lock serializes dispatchers and bounds global in-flight IO.
 SELECT * INTO c FROM private.conversation_media_processing_transport_v2 WHERE singleton FOR UPDATE;
 IF NOT c.enabled THEN RETURN 0;END IF;
 SELECT decrypted_secret INTO bypass FROM vault.decrypted_secrets WHERE id=c.secret_id;
 IF bypass IS NULL THEN RAISE EXCEPTION 'private_processing_target_unavailable';END IF;
 SELECT greatest(0,2-count(*))::integer INTO slots FROM private.conversation_media_processing_jobs_v2
  WHERE(state='queued' AND queued_at>at_time-interval '2minutes') OR(state='running' AND lease_until>at_time);
 FOR j IN SELECT * FROM private.conversation_media_processing_jobs_v2
  WHERE(state='waiting' AND next_attempt_at<=at_time) OR(state='queued' AND queued_at<=at_time-interval '2minutes') OR(state='running' AND lease_until<=at_time)
  ORDER BY next_attempt_at,id LIMIT 20 FOR UPDATE SKIP LOCKED LOOP
  IF NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 a JOIN public.users u ON u.id=a.user_id
   JOIN private.conversation_media_obligations_v2 o ON o.asset_id=a.id AND o.user_id=a.user_id
   WHERE a.id=j.asset_id AND a.user_id=j.user_id AND a.status NOT IN('deleted','pending_upload') AND a.retention_until>at_time AND u.status='active' AND o.closed_at IS NULL) THEN
   UPDATE private.conversation_media_processing_jobs_v2 SET state='cancelled',last_outcome='cancelled' WHERE id=j.id;CONTINUE;END IF;
  IF EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE id=j.asset_id AND(status='processed' OR(status='failed' AND failure_stage='processing' AND processing_request_id=j.request_id))) THEN
   UPDATE private.conversation_media_processing_jobs_v2 SET state='completed',last_outcome='completed' WHERE id=j.id;CONTINUE;END IF;
  IF j.failure_count>=4 THEN PERFORM private.fail_conversation_media_processing_transport_v2(j.id);CONTINUE;END IF;
  IF j.state IN('queued','running') THEN
   UPDATE private.conversation_media_processing_jobs_v2 SET state='waiting',failure_count=failure_count+1,next_attempt_at=at_time+interval '30seconds',last_outcome='retry' WHERE id=j.id;
   CONTINUE;END IF;
  IF slots<=0 THEN CONTINUE;END IF;
  raw_token:=encode(extensions.gen_random_bytes(32),'hex');
  UPDATE private.conversation_media_processing_jobs_v2 SET state='queued',dispatch_id=gen_random_uuid(),token_sha256=encode(extensions.digest(raw_token,'sha256'),'hex'),
   dispatched_source_sha=c.source_sha,queued_at=clock_timestamp(),lease_id=NULL,lease_until=NULL,last_outcome=NULL WHERE id=j.id RETURNING * INTO j;
  SELECT net.http_post(url:=c.target_url||'/api/internal/conversation-media/process-v2',
   headers:=jsonb_build_object('Content-Type','application/json','x-vercel-protection-bypass',bypass,'x-performe-processing-token',raw_token),
   body:=jsonb_build_object('dispatch_id',j.dispatch_id),timeout_milliseconds:=260000) INTO request_id;
  IF request_id IS NULL THEN RAISE EXCEPTION 'private_processing_dispatch_unavailable';END IF;
  slots:=slots-1;sent:=sent+1;
 END LOOP;
 RETURN sent;
END$$;

CREATE FUNCTION public.enqueue_conversation_media_processing_job_v2(p_user_id uuid,p_asset_id uuid,p_request_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;j private.conversation_media_processing_jobs_v2%ROWTYPE;BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_request_id IS NULL OR p_request_id!~'^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'invalid_private_processing_request' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM private.conversation_media_processing_transport_v2 WHERE singleton AND enabled FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_processing_transport_disabled';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR m.status IN('pending_upload','deleted') OR m.retention_until<=clock_timestamp() OR(m.status='failed' AND m.failure_stage<>'processing') THEN RETURN NULL;END IF;
 PERFORM 1 FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id AND user_id=m.user_id AND closed_at IS NULL FOR SHARE;IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO j FROM private.conversation_media_processing_jobs_v2 WHERE asset_id=m.id AND request_id=p_request_id;
 IF NOT FOUND THEN SELECT * INTO j FROM private.conversation_media_processing_jobs_v2 WHERE asset_id=m.id AND state IN('waiting','queued','running');END IF;
 IF j.id IS NULL THEN
  INSERT INTO private.conversation_media_processing_jobs_v2(asset_id,user_id,request_id,state)
   VALUES(m.id,m.user_id,p_request_id,CASE WHEN m.status='processed' THEN 'completed' ELSE 'waiting' END) RETURNING * INTO j;
 END IF;
 -- Commit acceptance before the BFF invokes the due dispatcher separately.
 -- Cron recovers a lost/failed wakeup; acceptance never depends on that ACK.
 RETURN jsonb_build_object('schema','conversation.media-processing-job.v2','job_id',j.id,'user_id',j.user_id,'asset_id',j.asset_id,'state',j.state);
END$$;

CREATE FUNCTION public.claim_conversation_media_processing_job_v2(p_dispatch_id uuid,p_token_sha256 text,p_source_sha text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE c private.conversation_media_processing_transport_v2%ROWTYPE;j private.conversation_media_processing_jobs_v2%ROWTYPE;at_time timestamptz:=clock_timestamp();m private.conversation_media_assets_v2%ROWTYPE;BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO c FROM private.conversation_media_processing_transport_v2 WHERE singleton FOR SHARE;
 IF NOT c.enabled OR c.source_sha IS DISTINCT FROM p_source_sha THEN RETURN NULL;END IF;
 SELECT * INTO j FROM private.conversation_media_processing_jobs_v2 WHERE dispatch_id=p_dispatch_id FOR UPDATE;
 IF NOT FOUND OR j.state<>'queued' OR j.token_sha256 IS DISTINCT FROM p_token_sha256 OR j.queued_at<=at_time-interval '2minutes' OR j.dispatched_source_sha IS DISTINCT FROM p_source_sha THEN RETURN NULL;END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=j.asset_id AND user_id=j.user_id;
 IF NOT FOUND OR m.status IN('deleted','pending_upload') OR m.retention_until<=at_time
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=j.user_id AND status='active')
  OR NOT EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 WHERE asset_id=j.asset_id AND closed_at IS NULL) THEN
  UPDATE private.conversation_media_processing_jobs_v2 SET state='cancelled',last_outcome='cancelled' WHERE id=j.id;RETURN NULL;END IF;
 IF m.status='processed' OR(m.status='failed' AND m.failure_stage='processing' AND m.processing_request_id=j.request_id) THEN
  UPDATE private.conversation_media_processing_jobs_v2 SET state='completed',last_outcome='completed' WHERE id=j.id;RETURN NULL;END IF;
 UPDATE private.conversation_media_processing_jobs_v2 SET state='running',lease_id=gen_random_uuid(),lease_until=at_time+interval '5minutes' WHERE id=j.id RETURNING * INTO j;
 RETURN jsonb_build_object('schema','conversation.media-processing-dispatch.v2','dispatch_id',j.dispatch_id,'job_id',j.id,'lease_id',j.lease_id,
  'expires_at',to_char(j.lease_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'source_sha',p_source_sha,'user_id',j.user_id,'asset_id',j.asset_id,'request_id',j.request_id,'kind',m.kind);
END$$;
CREATE FUNCTION public.validate_conversation_media_processing_job_v2(p_dispatch_id uuid,p_lease_id uuid,p_source_sha text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN EXISTS(SELECT 1 FROM private.conversation_media_processing_jobs_v2 j CROSS JOIN private.conversation_media_processing_transport_v2 c
  WHERE c.singleton AND c.enabled AND c.source_sha=p_source_sha AND j.dispatched_source_sha=p_source_sha AND j.dispatch_id=p_dispatch_id AND j.lease_id=p_lease_id AND j.state='running' AND j.lease_until>clock_timestamp());
END$$;
CREATE FUNCTION public.complete_conversation_media_processing_job_v2(p_dispatch_id uuid,p_lease_id uuid,p_outcome text,p_retry_at timestamptz DEFAULT NULL) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE j private.conversation_media_processing_jobs_v2%ROWTYPE;at_time timestamptz:=clock_timestamp();BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_outcome IS NULL OR p_outcome NOT IN('completed','retry','defer') THEN RETURN false;END IF;
 PERFORM 1 FROM private.conversation_media_processing_transport_v2 WHERE singleton AND enabled FOR SHARE;IF NOT FOUND THEN RETURN false;END IF;
 SELECT * INTO j FROM private.conversation_media_processing_jobs_v2 WHERE dispatch_id=p_dispatch_id FOR UPDATE;
 IF NOT FOUND OR j.lease_id IS DISTINCT FROM p_lease_id OR p_lease_id IS NULL THEN RETURN false;END IF;
 IF j.state IN('completed','cancelled') AND j.last_outcome='completed' THEN RETURN p_outcome='completed';END IF;
 IF j.state='waiting' AND j.last_outcome=p_outcome THEN RETURN true;END IF;
 IF j.state<>'running' OR j.lease_until<=at_time THEN RETURN false;END IF;
 IF p_outcome='completed' THEN
  IF NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE id=j.asset_id AND(status='deleted' OR status='processed' OR(status='failed' AND failure_stage='processing' AND processing_request_id=j.request_id)))
   AND EXISTS(SELECT 1 FROM public.users WHERE id=j.user_id AND status='active') THEN RETURN false;END IF;
  UPDATE private.conversation_media_processing_jobs_v2 SET state='completed',last_outcome='completed' WHERE id=j.id;
 ELSE
  IF p_outcome='defer' AND(p_retry_at IS NULL OR NOT isfinite(p_retry_at)) THEN RETURN false;END IF;
  UPDATE private.conversation_media_processing_jobs_v2 SET state='waiting',last_outcome=p_outcome,
   failure_count=least(4,failure_count+CASE WHEN p_outcome='retry' THEN 1 ELSE 0 END),
   next_attempt_at=CASE WHEN p_outcome='defer' THEN greatest(at_time+interval '1second',least(p_retry_at,at_time+interval '10minutes')) ELSE at_time+interval '30seconds' END WHERE id=j.id;
 END IF;RETURN true;
END$$;
CREATE FUNCTION public.configure_conversation_media_processing_transport_v2(p_enabled boolean,p_project_ref text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$DECLARE existing record;BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_enabled IS NULL OR p_project_ref IS DISTINCT FROM 'xitugspwfxkcluxvrdeg' THEN RAISE EXCEPTION 'invalid_private_processing_target';END IF;
 PERFORM 1 FROM private.conversation_media_processing_transport_v2 WHERE singleton FOR UPDATE;
 IF p_enabled AND NOT EXISTS(SELECT 1 FROM private.conversation_media_processing_transport_v2 WHERE singleton AND target_url IS NOT NULL AND source_sha IS NOT NULL AND secret_id IS NOT NULL AND setup_token_sha256 IS NULL) THEN RAISE EXCEPTION 'private_processing_not_configured';END IF;
 SELECT * INTO existing FROM cron.job WHERE jobname='performe-conversation-media-processing-v2';
 IF FOUND AND(existing.command<>'SELECT public.dispatch_due_conversation_media_processing_v2();' OR existing.database<>current_database() OR existing.username<>current_user) THEN RAISE EXCEPTION 'private_processing_cron_conflict';END IF;
 IF p_enabled THEN PERFORM cron.schedule_in_database('performe-conversation-media-processing-v2','* * * * *','SELECT public.dispatch_due_conversation_media_processing_v2();',current_database(),NULL,true);
 ELSIF existing.jobid IS NOT NULL THEN PERFORM cron.unschedule(existing.jobid);END IF;
 UPDATE private.conversation_media_processing_transport_v2 SET enabled=p_enabled WHERE singleton;
 RETURN true;
END$$;
REVOKE ALL ON FUNCTION public.prepare_conversation_media_processing_transport_v2(text,text,text,text),public.register_conversation_media_processing_transport_v2(text,text,text,text),public.dispatch_due_conversation_media_processing_v2(),public.enqueue_conversation_media_processing_job_v2(uuid,uuid,text),public.claim_conversation_media_processing_job_v2(uuid,text,text),public.validate_conversation_media_processing_job_v2(uuid,uuid,text),public.complete_conversation_media_processing_job_v2(uuid,uuid,text,timestamptz),public.configure_conversation_media_processing_transport_v2(boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_conversation_media_processing_transport_v2(text,text,text,text),public.register_conversation_media_processing_transport_v2(text,text,text,text),public.dispatch_due_conversation_media_processing_v2(),public.enqueue_conversation_media_processing_job_v2(uuid,uuid,text),public.claim_conversation_media_processing_job_v2(uuid,text,text),public.validate_conversation_media_processing_job_v2(uuid,uuid,text),public.complete_conversation_media_processing_job_v2(uuid,uuid,text,timestamptz),public.configure_conversation_media_processing_transport_v2(boolean,text) TO service_role;
COMMIT;

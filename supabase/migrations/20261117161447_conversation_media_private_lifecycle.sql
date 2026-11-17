-- Private v2 lifecycle substrate only. No route, event or schedule activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_assets_v2') IS NULL
  OR to_regclass('private.conversation_media_identity_v2') IS NULL THEN
  RAISE EXCEPTION 'private_media_catalog_required' USING ERRCODE='42501';END IF;
END $guard$;

-- Independent source identity, never a caption, transcript or provider result.
-- It must outlive both catalog and owner while upload capabilities may exist.
CREATE TABLE private.conversation_media_obligations_v2 (
 asset_id uuid PRIMARY KEY,user_id uuid NOT NULL,kind text NOT NULL,
 bucket_id text NOT NULL,object_path text NOT NULL,mime_type text NOT NULL,
 declared_size_bytes bigint NOT NULL,source_created_at timestamptz NOT NULL,retention_until timestamptz NOT NULL,
 closed_at timestamptz,issuance_revision bigint NOT NULL DEFAULT 0 CHECK(issuance_revision>=0),
 last_provider_observed_at timestamptz,
 CHECK(kind IN('conversation_photo','audio_note')),
 CHECK(bucket_id=CASE kind WHEN 'conversation_photo' THEN 'meal-photos' ELSE 'audio-notes' END),
 CHECK(private.conversation_media_extension_v2(kind,mime_type) IS NOT NULL),
 CHECK(object_path='conversation-v2/'||user_id::text||'/'||asset_id::text||'.'||private.conversation_media_extension_v2(kind,mime_type)),
 CHECK(declared_size_bytes>0 AND declared_size_bytes<=(CASE kind WHEN 'conversation_photo' THEN 15728640 ELSE 26214400 END)),
 CHECK(isfinite(source_created_at) AND isfinite(retention_until) AND retention_until=source_created_at+interval '720hours'),
 CHECK(closed_at IS NULL OR(isfinite(closed_at) AND closed_at>=source_created_at)),
 CHECK(last_provider_observed_at IS NULL OR(isfinite(last_provider_observed_at) AND last_provider_observed_at>=source_created_at))
);
CREATE TABLE private.conversation_media_upload_tickets_v2 (
 ticket_id uuid PRIMARY KEY,asset_id uuid NOT NULL REFERENCES private.conversation_media_obligations_v2(asset_id),
 user_id uuid NOT NULL,prepared_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(prepared_at)),
 provider_expires_at timestamptz CHECK(provider_expires_at IS NULL OR(isfinite(provider_expires_at)
  AND provider_expires_at>='1970-01-01Z'::timestamptz AND provider_expires_at<'10000-01-01Z'::timestamptz)),
 registered_at timestamptz CHECK(registered_at IS NULL OR(isfinite(registered_at) AND registered_at>=prepared_at)),
 CHECK((provider_expires_at IS NULL)=(registered_at IS NULL))
);
CREATE INDEX conversation_private_upload_tickets_asset ON private.conversation_media_upload_tickets_v2(asset_id,user_id);
CREATE TABLE private.conversation_media_processing_claims_v2 (
 asset_id uuid PRIMARY KEY REFERENCES private.conversation_media_assets_v2(id) ON DELETE CASCADE,
 user_id uuid NOT NULL,request_id text NOT NULL CHECK(request_id~'^[0-9a-f]{64}$'),
 claim_token uuid NOT NULL UNIQUE,started_at timestamptz NOT NULL,lease_until timestamptz NOT NULL,
 phase text NOT NULL CHECK(phase IN('open','processed','failed')),finished_at timestamptz,
 CHECK(isfinite(started_at) AND isfinite(lease_until) AND lease_until=started_at+interval '5minutes'),
 CHECK((phase='open')=(finished_at IS NULL)),
 CHECK(finished_at IS NULL OR(isfinite(finished_at) AND finished_at>=started_at))
);
ALTER TABLE private.conversation_media_obligations_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_media_upload_tickets_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_media_processing_claims_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_obligations_v2,private.conversation_media_upload_tickets_v2,
 private.conversation_media_processing_claims_v2 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.freeze_conversation_media_lifecycle_v2() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_TABLE_NAME='conversation_media_upload_tickets_v2' THEN
  IF(to_jsonb(NEW)-'provider_expires_at'-'registered_at') IS DISTINCT FROM(to_jsonb(OLD)-'provider_expires_at'-'registered_at')
   OR(OLD.provider_expires_at IS NOT NULL AND ROW(NEW.provider_expires_at,NEW.registered_at) IS DISTINCT FROM ROW(OLD.provider_expires_at,OLD.registered_at)) THEN
   RAISE EXCEPTION 'private_media_ticket_changed' USING ERRCODE='23514';END IF;
 ELSE
  IF(to_jsonb(NEW)-'closed_at'-'issuance_revision'-'last_provider_observed_at') IS DISTINCT FROM
   (to_jsonb(OLD)-'closed_at'-'issuance_revision'-'last_provider_observed_at')
   OR(OLD.closed_at IS NOT NULL AND NEW.closed_at IS DISTINCT FROM OLD.closed_at)
   OR NEW.issuance_revision<OLD.issuance_revision THEN
   RAISE EXCEPTION 'private_media_obligation_changed' USING ERRCODE='23514';END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.freeze_conversation_media_lifecycle_v2() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER freeze_conversation_private_ticket BEFORE UPDATE ON private.conversation_media_upload_tickets_v2
 FOR EACH ROW EXECUTE FUNCTION private.freeze_conversation_media_lifecycle_v2();
CREATE TRIGGER freeze_conversation_private_obligation BEFORE UPDATE ON private.conversation_media_obligations_v2
 FOR EACH ROW EXECUTE FUNCTION private.freeze_conversation_media_lifecycle_v2();

CREATE FUNCTION private.conversation_media_identity_wire_v2(m private.conversation_media_assets_v2) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('catalog_version',2,'asset_id',m.id,'user_id',m.user_id,'kind',m.kind,
  'bucket_id',m.bucket_id,'object_path',m.object_path,'mime_type',m.mime_type,'declared_size_bytes',m.declared_size_bytes)
$$;
CREATE FUNCTION private.conversation_media_state_wire_v2(m private.conversation_media_assets_v2) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('identity',private.conversation_media_identity_wire_v2(m),
  'state',jsonb_build_object('status',m.status,'retention_until',to_char(m.retention_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'created_at',to_char(m.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')))
$$;
CREATE FUNCTION private.conversation_media_ticket_wire_v2(t private.conversation_media_upload_tickets_v2) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',t.ticket_id,'asset_id',t.asset_id,'user_id',t.user_id,
  'prepared_at',to_char(t.prepared_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'provider_expires_at',to_char(t.provider_expires_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'registered_at',to_char(t.registered_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
$$;
REVOKE ALL ON FUNCTION private.conversation_media_identity_wire_v2(private.conversation_media_assets_v2),
 private.conversation_media_state_wire_v2(private.conversation_media_assets_v2),
 private.conversation_media_ticket_wire_v2(private.conversation_media_upload_tickets_v2) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.prepare_conversation_media_upload_v2(p_user_id uuid,p_asset_id uuid,p_ticket_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 t private.conversation_media_upload_tickets_v2%ROWTYPE;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_ticket_id IS NULL THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 -- Shared order: owner -> catalog -> independent obligation -> ticket/claim.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 at_time:=clock_timestamp();
 IF NOT FOUND OR m.status<>'pending_upload' OR m.retention_until<=at_time OR m.created_at>at_time THEN
  RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 INSERT INTO private.conversation_media_obligations_v2(asset_id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,source_created_at,retention_until)
 VALUES(m.id,m.user_id,m.kind,m.bucket_id,m.object_path,m.mime_type,m.declared_size_bytes,m.created_at,m.retention_until)
 ON CONFLICT(asset_id) DO NOTHING;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id FOR UPDATE;
 IF ROW(o.user_id,o.kind,o.bucket_id,o.object_path,o.mime_type,o.declared_size_bytes,o.source_created_at,o.retention_until)
 IS DISTINCT FROM ROW(m.user_id,m.kind,m.bucket_id,m.object_path,m.mime_type,m.declared_size_bytes,m.created_at,m.retention_until)
 OR o.closed_at IS NOT NULL THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 INSERT INTO private.conversation_media_upload_tickets_v2(ticket_id,asset_id,user_id,prepared_at)
 VALUES(p_ticket_id,m.id,m.user_id,at_time) ON CONFLICT(ticket_id) DO NOTHING;
 SELECT * INTO t FROM private.conversation_media_upload_tickets_v2 WHERE ticket_id=p_ticket_id FOR UPDATE;
 IF t.asset_id<>m.id OR t.user_id<>m.user_id OR t.provider_expires_at IS NOT NULL THEN
  RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('schema','conversation.upload-prepared.v2','asset',private.conversation_media_state_wire_v2(m),'ticket',private.conversation_media_ticket_wire_v2(t));
END $$;

CREATE FUNCTION public.register_conversation_media_upload_v2(p_user_id uuid,p_asset_id uuid,p_ticket_id uuid,p_provider_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 t private.conversation_media_upload_tickets_v2%ROWTYPE;has_catalog boolean;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_ticket_id IS NULL OR p_provider_expires_at IS NULL
  OR NOT isfinite(p_provider_expires_at) OR p_provider_expires_at<'1970-01-01Z'::timestamptz OR p_provider_expires_at>='10000-01-01Z'::timestamptz THEN
  RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 -- Do not require an owner/catalog that may have gone away after signing began.
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id FOR UPDATE;has_catalog:=FOUND;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO t FROM private.conversation_media_upload_tickets_v2 WHERE ticket_id=p_ticket_id FOR UPDATE;
 IF NOT FOUND OR t.asset_id<>p_asset_id OR t.user_id<>p_user_id THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 IF has_catalog AND ROW(m.user_id,m.kind,m.bucket_id,m.object_path,m.mime_type,m.declared_size_bytes,m.created_at,m.retention_until)
 IS DISTINCT FROM ROW(o.user_id,o.kind,o.bucket_id,o.object_path,o.mime_type,o.declared_size_bytes,o.source_created_at,o.retention_until) THEN
  RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 IF t.provider_expires_at IS NOT NULL THEN
  IF t.provider_expires_at IS DISTINCT FROM p_provider_expires_at THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
  RETURN jsonb_build_object('schema','conversation.upload-registered.v2','ticket',private.conversation_media_ticket_wire_v2(t));
 END IF;
 at_time:=clock_timestamp();
 UPDATE private.conversation_media_upload_tickets_v2 SET provider_expires_at=p_provider_expires_at,registered_at=at_time
  WHERE ticket_id=t.ticket_id RETURNING * INTO t;
 UPDATE private.conversation_media_obligations_v2 SET issuance_revision=issuance_revision+1,last_provider_observed_at=at_time
  WHERE asset_id=o.asset_id;
 IF NOT has_catalog OR m.status='deleted' OR m.retention_until<=at_time OR o.closed_at IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN
  UPDATE private.conversation_media_obligations_v2 SET closed_at=coalesce(closed_at,at_time) WHERE asset_id=o.asset_id;
  IF has_catalog AND m.status<>'deleted' THEN
   UPDATE private.conversation_media_assets_v2 SET status='deleted',deleted_at=at_time,updated_at=at_time,
    failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=m.id;
  END IF;
 END IF;
 RETURN jsonb_build_object('schema','conversation.upload-registered.v2','ticket',private.conversation_media_ticket_wire_v2(t));
END $$;

CREATE FUNCTION public.get_conversation_media_upload_state_v2(p_user_id uuid,p_asset_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN NULL;END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR SHARE;
 IF NOT FOUND OR m.status<>'pending_upload' OR m.retention_until<=clock_timestamp()
  OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id AND closed_at IS NOT NULL) THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('schema','conversation.upload-state.v2','asset',private.conversation_media_state_wire_v2(m));
END $$;

CREATE FUNCTION public.complete_conversation_media_upload_v2(p_user_id uuid,p_asset_id uuid,p_actual_size_bytes bigint,p_mime_type text,p_etag text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id AND user_id=m.user_id FOR UPDATE;
 at_time:=clock_timestamp();
 IF NOT FOUND OR o.closed_at IS NOT NULL OR m.retention_until<=at_time OR m.created_at>at_time
  OR m.declared_size_bytes IS DISTINCT FROM p_actual_size_bytes OR m.mime_type IS DISTINCT FROM p_mime_type
  OR(p_etag IS NOT NULL AND char_length(p_etag)>512)
  OR NOT EXISTS(SELECT 1 FROM private.conversation_media_upload_tickets_v2 WHERE asset_id=m.id AND user_id=m.user_id AND provider_expires_at IS NOT NULL) THEN
  RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 IF m.status IN('uploaded','processing','processed') THEN
  IF m.actual_size_bytes IS DISTINCT FROM p_actual_size_bytes OR m.etag IS DISTINCT FROM p_etag THEN
   RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
 ELSE
  IF m.status<>'pending_upload' THEN RAISE EXCEPTION 'private_upload_changed' USING ERRCODE='40001';END IF;
  UPDATE private.conversation_media_assets_v2 SET status='uploaded',actual_size_bytes=p_actual_size_bytes,etag=p_etag,
   uploaded_at=at_time,updated_at=at_time WHERE id=m.id RETURNING * INTO m;
 END IF;
 RETURN jsonb_build_object('schema','conversation.media-asset.v2','catalog_version',2,'asset',to_jsonb(m));
END $$;

CREATE FUNCTION public.claim_conversation_media_processing_v2(p_user_id uuid,p_asset_id uuid,p_request_id text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 c private.conversation_media_processing_claims_v2%ROWTYPE;at_time timestamptz;
 unavailable jsonb:='{"schema":"conversation.media-processing-claim.v2","action":"unavailable"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_request_id IS NULL OR p_request_id!~'^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'invalid_private_media_processing' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RETURN unavailable;END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 at_time:=clock_timestamp();
 IF NOT FOUND OR m.status IN('pending_upload','processed','deleted') OR m.retention_until<=at_time OR m.created_at>at_time
  OR(m.status='failed' AND m.failure_stage<>'processing') THEN RETURN unavailable;END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id AND user_id=m.user_id FOR UPDATE;
 IF NOT FOUND OR o.closed_at IS NOT NULL THEN RETURN unavailable;END IF;
 SELECT * INTO c FROM private.conversation_media_processing_claims_v2 WHERE asset_id=m.id FOR UPDATE;
 IF FOUND AND c.phase='open' AND c.lease_until>at_time THEN
  RETURN jsonb_build_object('schema','conversation.media-processing-claim.v2','action','busy',
   'retry_at',to_char(c.lease_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
 END IF;
 INSERT INTO private.conversation_media_processing_claims_v2(asset_id,user_id,request_id,claim_token,started_at,lease_until,phase,finished_at)
 VALUES(m.id,m.user_id,p_request_id,gen_random_uuid(),at_time,at_time+interval '5minutes','open',NULL)
 ON CONFLICT(asset_id) DO UPDATE SET user_id=EXCLUDED.user_id,request_id=EXCLUDED.request_id,claim_token=EXCLUDED.claim_token,
  started_at=EXCLUDED.started_at,lease_until=EXCLUDED.lease_until,phase='open',finished_at=NULL RETURNING * INTO c;
 UPDATE private.conversation_media_assets_v2 SET status='processing',processing_request_id=p_request_id,
  failure_stage=NULL,failure_code=NULL,processing_result=NULL,processed_at=NULL,updated_at=at_time WHERE id=m.id RETURNING * INTO m;
 RETURN jsonb_build_object('schema','conversation.media-processing-claim.v2','action','claimed',
  'asset',private.conversation_media_state_wire_v2(m)||jsonb_build_object('context_text',m.context_text,'processing_request_id',m.processing_request_id),
  'claim',jsonb_build_object('token',c.claim_token,'lease_until',to_char(c.lease_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
END $$;

CREATE FUNCTION public.complete_conversation_media_processing_v2(p_user_id uuid,p_asset_id uuid,p_request_id text,p_claim_token uuid,p_result jsonb) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 c private.conversation_media_processing_claims_v2%ROWTYPE;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_result IS NULL OR jsonb_typeof(p_result)<>'object' OR octet_length(p_result::text)>1048576 THEN
  RAISE EXCEPTION 'invalid_private_media_result' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RETURN false;END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id AND user_id=m.user_id FOR UPDATE;
 at_time:=clock_timestamp();
 IF NOT FOUND OR o.closed_at IS NOT NULL OR m.retention_until<=at_time OR m.processing_request_id IS DISTINCT FROM p_request_id THEN RETURN false;END IF;
 SELECT * INTO c FROM private.conversation_media_processing_claims_v2 WHERE asset_id=m.id AND user_id=m.user_id FOR UPDATE;
 IF NOT FOUND OR c.claim_token IS DISTINCT FROM p_claim_token OR c.request_id IS DISTINCT FROM p_request_id THEN RETURN false;END IF;
 IF m.status='processed' AND c.phase='processed' THEN RETURN m.processing_result IS NOT DISTINCT FROM p_result;END IF;
 IF m.status<>'processing' OR c.phase<>'open' OR c.lease_until<=at_time THEN RETURN false;END IF;
 UPDATE private.conversation_media_assets_v2 SET status='processed',processing_result=p_result,processed_at=at_time,updated_at=at_time WHERE id=m.id;
 UPDATE private.conversation_media_processing_claims_v2 SET phase='processed',finished_at=at_time WHERE asset_id=m.id;
 RETURN true;
END $$;

CREATE FUNCTION public.fail_conversation_media_processing_v2(p_user_id uuid,p_asset_id uuid,p_request_id text,p_claim_token uuid,p_failure_code text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 c private.conversation_media_processing_claims_v2%ROWTYPE;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_failure_code IS NULL OR p_failure_code!~'^[a-z][a-z0-9_]{0,79}$' THEN
  RAISE EXCEPTION 'invalid_private_media_failure' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RETURN false;END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=m.id AND user_id=m.user_id FOR UPDATE;
 at_time:=clock_timestamp();
 IF NOT FOUND OR o.closed_at IS NOT NULL OR m.retention_until<=at_time OR m.processing_request_id IS DISTINCT FROM p_request_id THEN RETURN false;END IF;
 SELECT * INTO c FROM private.conversation_media_processing_claims_v2 WHERE asset_id=m.id AND user_id=m.user_id FOR UPDATE;
 IF NOT FOUND OR c.claim_token IS DISTINCT FROM p_claim_token OR c.request_id IS DISTINCT FROM p_request_id THEN RETURN false;END IF;
 IF m.status='failed' AND c.phase='failed' THEN RETURN m.failure_code IS NOT DISTINCT FROM p_failure_code;END IF;
 IF m.status<>'processing' OR c.phase<>'open' OR c.lease_until<=at_time THEN RETURN false;END IF;
 UPDATE private.conversation_media_assets_v2 SET status='failed',failure_stage='processing',failure_code=p_failure_code,
  processing_result=NULL,processed_at=NULL,updated_at=at_time WHERE id=m.id;
 UPDATE private.conversation_media_processing_claims_v2 SET phase='failed',finished_at=at_time WHERE asset_id=m.id;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.prepare_conversation_media_upload_v2(uuid,uuid,uuid),
 public.register_conversation_media_upload_v2(uuid,uuid,uuid,timestamptz),public.get_conversation_media_upload_state_v2(uuid,uuid),
 public.complete_conversation_media_upload_v2(uuid,uuid,bigint,text,text),public.claim_conversation_media_processing_v2(uuid,uuid,text),
 public.complete_conversation_media_processing_v2(uuid,uuid,text,uuid,jsonb),public.fail_conversation_media_processing_v2(uuid,uuid,text,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_conversation_media_upload_v2(uuid,uuid,uuid),
 public.register_conversation_media_upload_v2(uuid,uuid,uuid,timestamptz),public.get_conversation_media_upload_state_v2(uuid,uuid),
 public.complete_conversation_media_upload_v2(uuid,uuid,bigint,text,text),public.claim_conversation_media_processing_v2(uuid,uuid,text),
 public.complete_conversation_media_processing_v2(uuid,uuid,text,uuid,jsonb),public.fail_conversation_media_processing_v2(uuid,uuid,text,uuid,text)
 TO service_role;
COMMENT ON TABLE private.conversation_media_obligations_v2 IS
 'Independent v2 byte-revocation authority before external signing, survives catalog/owner deletion. No caption/result/URL/token. Unknown provider outcome is not a drain certificate. Disposal/sweep adapters must be qualified before activation.';
COMMIT;

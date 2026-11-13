-- Source-only rollout substrate. No schedule, flag, Storage request or legacy
-- issuance-drain certificate is activated by this additive migration.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_expiry_debts') IS NULL THEN
  RAISE EXCEPTION 'ordinary_upload_expiry_substrate_required' USING ERRCODE='42501';
 END IF;
END $guard$;
CREATE TABLE private.conversation_media_upload_tickets (
 ticket_id uuid PRIMARY KEY, asset_id uuid NOT NULL, user_id uuid NOT NULL,
 kind text NOT NULL, bucket_id text NOT NULL, object_path text NOT NULL,
 asset_wire jsonb NOT NULL,
 prepared_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(prepared_at)),
 provider_expires_at timestamptz CHECK(provider_expires_at IS NULL OR(isfinite(provider_expires_at) AND provider_expires_at>='1970-01-01Z'::timestamptz AND provider_expires_at<'10000-01-01Z'::timestamptz)),
 registered_at timestamptz CHECK(registered_at IS NULL OR(isfinite(registered_at) AND registered_at>=prepared_at)),
 CHECK((provider_expires_at IS NULL)=(registered_at IS NULL)),
 CHECK((kind='conversation_photo' AND bucket_id='meal-photos') OR(kind='audio_note' AND bucket_id='audio-notes')),
 CHECK(object_path ~ ('^'||user_id::text||'/'||asset_id::text||'[.][a-z0-9]+$'))
);
-- No catalog/auth FK: an in-flight signing response must still be bookkept
-- after account/catalog deletion. Only the original private owner/path survives.
ALTER TABLE private.conversation_media_upload_tickets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_upload_tickets FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX conversation_media_upload_tickets_asset ON private.conversation_media_upload_tickets(asset_id,user_id);
CREATE FUNCTION private.freeze_conversation_media_upload_ticket() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF (to_jsonb(NEW)-'provider_expires_at'-'registered_at') IS DISTINCT FROM
    (to_jsonb(OLD)-'provider_expires_at'-'registered_at') OR
   (OLD.provider_expires_at IS NOT NULL AND (NEW.provider_expires_at IS DISTINCT FROM OLD.provider_expires_at OR NEW.registered_at IS DISTINCT FROM OLD.registered_at)) THEN
  RAISE EXCEPTION 'ordinary_upload_ticket_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.freeze_conversation_media_upload_ticket() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER conversation_media_upload_ticket_frozen BEFORE UPDATE ON private.conversation_media_upload_tickets
 FOR EACH ROW EXECUTE FUNCTION private.freeze_conversation_media_upload_ticket();
CREATE FUNCTION private.conversation_upload_asset_wire(m public.media_assets) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',m.id,'user_id',m.user_id,'kind',m.kind,'bucket_id',m.bucket_id,'object_path',m.object_path,
 'mime_type',m.mime_type,'size_bytes',m.declared_size_bytes,'status',m.status,
 'retention_until',to_char(m.retention_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
$$;
CREATE FUNCTION private.conversation_upload_ticket_wire(t private.conversation_media_upload_tickets) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',t.ticket_id,'asset_id',t.asset_id,'user_id',t.user_id,
 'prepared_at',to_char(t.prepared_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'provider_expires_at',to_char(t.provider_expires_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'registered_at',to_char(t.registered_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
$$;
REVOKE ALL ON FUNCTION private.conversation_upload_asset_wire(public.media_assets),
 private.conversation_upload_ticket_wire(private.conversation_media_upload_tickets) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.prepare_conversation_media_upload(p_user_id uuid,p_asset_id uuid,p_ticket_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m public.media_assets%ROWTYPE;t private.conversation_media_upload_tickets%ROWTYPE;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_ticket_id IS NULL THEN RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
 -- Common lock order is catalog -> ticket -> cleanup debt. Never reverse it.
 SELECT * INTO m FROM public.media_assets WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 at_time:=clock_timestamp();
 IF NOT FOUND OR m.kind NOT IN('conversation_photo','audio_note') OR m.reevaluation_origin_version IS NOT NULL OR
 m.status<>'pending_upload' OR m.retention_until IS NULL OR m.retention_until<=at_time THEN
  RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
 INSERT INTO private.conversation_media_upload_tickets(ticket_id,asset_id,user_id,kind,bucket_id,object_path,asset_wire,prepared_at)
 VALUES(p_ticket_id,m.id,m.user_id,m.kind,m.bucket_id,m.object_path,private.conversation_upload_asset_wire(m),at_time) ON CONFLICT(ticket_id) DO NOTHING;
 SELECT * INTO t FROM private.conversation_media_upload_tickets WHERE ticket_id=p_ticket_id FOR UPDATE;
 IF t.asset_id<>m.id OR t.user_id<>m.user_id OR t.kind<>m.kind OR t.bucket_id<>m.bucket_id OR t.object_path<>m.object_path OR
 t.asset_wire IS DISTINCT FROM private.conversation_upload_asset_wire(m) OR t.provider_expires_at IS NOT NULL THEN
  RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('schema','conversation.upload-prepared.v1','asset',t.asset_wire,'ticket',private.conversation_upload_ticket_wire(t));
END $$;
CREATE FUNCTION public.register_conversation_media_upload(p_user_id uuid,p_asset_id uuid,p_ticket_id uuid,p_provider_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m public.media_assets%ROWTYPE;t private.conversation_media_upload_tickets%ROWTYPE;d private.conversation_media_expiry_debts%ROWTYPE;
 has_catalog boolean;at_time timestamptz;needs_cleanup boolean;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_ticket_id IS NULL OR p_provider_expires_at IS NULL OR NOT isfinite(p_provider_expires_at) OR
 p_provider_expires_at<'1970-01-01Z'::timestamptz OR p_provider_expires_at>='10000-01-01Z'::timestamptz THEN
  RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO m FROM public.media_assets WHERE id=p_asset_id FOR UPDATE;has_catalog:=FOUND;
 SELECT * INTO t FROM private.conversation_media_upload_tickets WHERE ticket_id=p_ticket_id FOR UPDATE;
 IF NOT FOUND OR t.asset_id<>p_asset_id OR t.user_id<>p_user_id THEN RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
 IF has_catalog AND (m.user_id<>t.user_id OR m.kind<>t.kind OR m.bucket_id<>t.bucket_id OR m.object_path<>t.object_path OR m.reevaluation_origin_version IS NOT NULL) THEN
  RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
 IF t.provider_expires_at IS NOT NULL THEN
  IF t.provider_expires_at IS DISTINCT FROM p_provider_expires_at THEN RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
  -- Replaying bookkeeping never invalidates a subsequent cleanup claim.
  RETURN jsonb_build_object('schema','conversation.upload-registered.v1','ticket',private.conversation_upload_ticket_wire(t));
 END IF;
 at_time:=clock_timestamp();
 UPDATE private.conversation_media_upload_tickets SET provider_expires_at=p_provider_expires_at,registered_at=at_time
 WHERE ticket_id=t.ticket_id RETURNING * INTO t;
 SELECT * INTO d FROM private.conversation_media_expiry_debts WHERE asset_id=t.asset_id FOR UPDATE;
 needs_cleanup:=FOUND OR NOT has_catalog OR m.status='deleted' OR m.retention_until<=at_time;
 IF needs_cleanup THEN
  IF d.asset_id IS NOT NULL AND (d.user_id<>t.user_id OR d.kind<>t.kind OR d.bucket_id<>t.bucket_id OR d.object_path<>t.object_path) THEN
   RAISE EXCEPTION 'ordinary_upload_changed' USING ERRCODE='40001';END IF;
  IF has_catalog AND m.status<>'deleted' THEN
   UPDATE public.media_assets SET status='deleted',deleted_at=at_time,failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=t.asset_id AND user_id=t.user_id;
  END IF;
  INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path,disposed_at)
  VALUES(t.asset_id,t.user_id,t.kind,t.bucket_id,t.object_path,at_time) ON CONFLICT(asset_id) DO UPDATE SET
   claim_token=NULL,lease_until=NULL,last_completed_claim=NULL,last_attempt_at=NULL,last_successful_sweep_at=NULL;
 END IF;
 RETURN jsonb_build_object('schema','conversation.upload-registered.v1','ticket',private.conversation_upload_ticket_wire(t));
END $$;
CREATE FUNCTION public.get_conversation_media_upload_state(p_user_id uuid,p_asset_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m public.media_assets%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO m FROM public.media_assets WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR m.kind NOT IN('conversation_photo','audio_note') OR m.reevaluation_origin_version IS NOT NULL OR
 m.status<>'pending_upload' OR m.retention_until IS NULL OR m.retention_until<=clock_timestamp() THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('schema','conversation.upload-state.v1','asset',private.conversation_upload_asset_wire(m));
END $$;
REVOKE ALL ON FUNCTION public.prepare_conversation_media_upload(uuid,uuid,uuid),
 public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz),public.get_conversation_media_upload_state(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_conversation_media_upload(uuid,uuid,uuid),
 public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz),public.get_conversation_media_upload_state(uuid,uuid) TO service_role;
COMMENT ON TABLE private.conversation_media_upload_tickets IS
 'Private ordinary Storage issuance attempts; no URL/token/caption. Actual provider expiry survives late response/catalog deletion. Unresolved attempts and legacy_untracked cleanup debt are never implicitly settled.';
COMMIT;

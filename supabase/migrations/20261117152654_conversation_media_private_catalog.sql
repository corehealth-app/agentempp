-- Additive foundation only. No route/worker/flag activation or data migration.
-- Immutable old functions must never acquire a new conversational Storage key.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('public.media_assets') IS NULL
  OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
  RAISE EXCEPTION 'conversation_private_catalog_substrate_required' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.media_assets'::regclass
  AND c.conname='media_assets_path_check' AND c.contype='c' AND c.convalidated
  AND encode(sha256(convert_to(pg_get_constraintdef(c.oid),'UTF8')),'hex')='d6f039ab792b206e707566534833eb6c183934d72041210647ecda14840022cf') THEN
  RAISE EXCEPTION 'conversation_private_catalog_legacy_path_changed' USING ERRCODE='23514';
 END IF;
END $guard$;

CREATE FUNCTION private.conversation_media_extension_v2(p_kind text,p_mime text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE
 WHEN p_kind='conversation_photo' THEN CASE p_mime
  WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png' WHEN 'image/webp' THEN 'webp'
  WHEN 'image/heic' THEN 'heic' WHEN 'image/heif' THEN 'heif' END
 WHEN p_kind='audio_note' THEN CASE p_mime
  WHEN 'audio/mpeg' THEN 'mp3' WHEN 'audio/mp4' THEN 'm4a' WHEN 'audio/x-m4a' THEN 'm4a'
  WHEN 'audio/aac' THEN 'aac' WHEN 'audio/wav' THEN 'wav' WHEN 'audio/x-wav' THEN 'wav'
  WHEN 'audio/ogg' THEN 'ogg' END END
$$;
REVOKE ALL ON FUNCTION private.conversation_media_extension_v2(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE private.conversation_media_assets_v2 (
 id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
 kind text NOT NULL CHECK(kind IN('conversation_photo','audio_note')),
 bucket_id text NOT NULL REFERENCES storage.buckets(id),
 object_path text NOT NULL,
 mime_type text NOT NULL,
 declared_size_bytes bigint NOT NULL,
 actual_size_bytes bigint,
 etag text,
 status text NOT NULL DEFAULT 'pending_upload' CHECK(status IN('pending_upload','uploaded','processing','processed','failed','deleted')),
 failure_stage text CHECK(failure_stage IN('upload','processing')),
 failure_code text,
 context_text text CHECK(context_text IS NULL OR char_length(context_text) BETWEEN 1 AND 1000),
 processing_request_id text CHECK(processing_request_id IS NULL OR processing_request_id~'^[0-9a-f]{64}$'),
 processing_result jsonb,
 source_request_hash text NOT NULL CHECK(source_request_hash~'^[0-9a-f]{64}$'),
 retention_until timestamptz NOT NULL,
 uploaded_at timestamptz,
 processed_at timestamptz,
 deleted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(user_id,source_request_hash),UNIQUE(bucket_id,object_path),
 CHECK(bucket_id=CASE kind WHEN 'conversation_photo' THEN 'meal-photos' ELSE 'audio-notes' END),
 CHECK(private.conversation_media_extension_v2(kind,mime_type) IS NOT NULL),
 CHECK(object_path='conversation-v2/'||user_id::text||'/'||id::text||'.'||private.conversation_media_extension_v2(kind,mime_type)),
 CHECK(declared_size_bytes>0 AND declared_size_bytes<=CASE kind WHEN 'conversation_photo' THEN 15728640 ELSE 26214400 END
  AND(actual_size_bytes IS NULL OR actual_size_bytes=declared_size_bytes)),
 CHECK((status='failed' AND failure_stage IS NOT NULL AND failure_code IS NOT NULL)
  OR(status<>'failed' AND failure_stage IS NULL AND failure_code IS NULL)),
 CHECK(status IN('pending_upload','failed','deleted') OR(actual_size_bytes IS NOT NULL AND uploaded_at IS NOT NULL)),
 CHECK(status<>'processed' OR processed_at IS NOT NULL),
 CHECK(status NOT IN('processing','processed') OR processing_request_id IS NOT NULL),
 CHECK(status<>'deleted' OR(deleted_at IS NOT NULL AND processing_result IS NULL)),
 CHECK(isfinite(created_at) AND isfinite(updated_at) AND isfinite(retention_until)
  AND retention_until=created_at+interval '720hours' AND updated_at>=created_at),
 CHECK(uploaded_at IS NULL OR(isfinite(uploaded_at) AND uploaded_at>=created_at)),
 CHECK(processed_at IS NULL OR(isfinite(processed_at) AND processed_at>=created_at)),
 CHECK(deleted_at IS NULL OR(isfinite(deleted_at) AND deleted_at>=created_at))
);
ALTER TABLE private.conversation_media_assets_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_assets_v2 FROM PUBLIC,anon,authenticated,service_role;

-- Minimal independent identity fence, not a payload or catalog mirror. A
-- unique index also arbitrates transactions using an older repeatable snapshot.
CREATE TABLE private.conversation_media_identity_v2 (
 asset_id uuid PRIMARY KEY,
 catalog_version smallint NOT NULL CHECK(catalog_version IN(1,2))
);
ALTER TABLE private.conversation_media_identity_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_identity_v2 FROM PUBLIC,anon,authenticated,service_role;

-- Old queries still read only public.media_assets; no new path is mirrored there.
-- AFTER INSERT runs only for an actually inserted row, not an idempotent no-op.
CREATE FUNCTION private.conversation_media_catalog_namespace_v2() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_TABLE_SCHEMA='public' THEN
  INSERT INTO private.conversation_media_identity_v2(asset_id,catalog_version) VALUES(NEW.id,1)
   ON CONFLICT(asset_id) DO UPDATE SET catalog_version=1
   WHERE conversation_media_identity_v2.catalog_version=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_asset_namespace_conflict' USING ERRCODE='40001';END IF;
  IF TG_OP='UPDATE' AND OLD.id IS DISTINCT FROM NEW.id THEN
   DELETE FROM private.conversation_media_identity_v2 WHERE asset_id=OLD.id AND catalog_version=1;
  END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM public.media_assets WHERE id=NEW.id) THEN
   RAISE EXCEPTION 'media_asset_namespace_conflict' USING ERRCODE='40001';END IF;
  INSERT INTO private.conversation_media_identity_v2(asset_id,catalog_version) VALUES(NEW.id,2)
   ON CONFLICT(asset_id) DO NOTHING;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_asset_namespace_conflict' USING ERRCODE='40001';END IF;
 END IF;
 RETURN NEW;
EXCEPTION WHEN serialization_failure THEN
 RAISE EXCEPTION 'media_asset_namespace_conflict' USING ERRCODE='40001';
END $$;
REVOKE ALL ON FUNCTION private.conversation_media_catalog_namespace_v2() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER conversation_media_catalog_namespace_v2 AFTER INSERT OR UPDATE OF id ON public.media_assets
 FOR EACH ROW EXECUTE FUNCTION private.conversation_media_catalog_namespace_v2();
CREATE TRIGGER conversation_media_private_namespace_v2 AFTER INSERT ON private.conversation_media_assets_v2
 FOR EACH ROW EXECUTE FUNCTION private.conversation_media_catalog_namespace_v2();

-- Public/clinical rows gain no extra retention: their transient reservation is
-- removed with the existing catalog row. Only ordinary version2 IDs survive.
CREATE FUNCTION private.release_legacy_media_identity_v2() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 DELETE FROM private.conversation_media_identity_v2 WHERE asset_id=OLD.id AND catalog_version=1;
 RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION private.release_legacy_media_identity_v2() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER release_legacy_media_identity_v2 AFTER DELETE ON public.media_assets
 FOR EACH ROW EXECUTE FUNCTION private.release_legacy_media_identity_v2();

CREATE FUNCTION private.conversation_media_source_immutable_v2() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF ROW(NEW.id,NEW.user_id,NEW.kind,NEW.bucket_id,NEW.object_path,NEW.mime_type,NEW.declared_size_bytes,
  NEW.context_text,NEW.source_request_hash,NEW.retention_until,NEW.created_at)
 IS DISTINCT FROM ROW(OLD.id,OLD.user_id,OLD.kind,OLD.bucket_id,OLD.object_path,OLD.mime_type,OLD.declared_size_bytes,
  OLD.context_text,OLD.source_request_hash,OLD.retention_until,OLD.created_at) THEN
  RAISE EXCEPTION 'conversation_media_source_changed' USING ERRCODE='23514';END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.conversation_media_source_immutable_v2() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER conversation_media_source_immutable_v2 BEFORE UPDATE ON private.conversation_media_assets_v2
 FOR EACH ROW EXECUTE FUNCTION private.conversation_media_source_immutable_v2();

CREATE FUNCTION public.create_conversation_media_asset_v2(p_user_id uuid,p_asset_id uuid,p_kind text,
 p_mime_type text,p_declared_size_bytes bigint,p_context_text text,p_source_request_hash text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;extension text;at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 extension:=private.conversation_media_extension_v2(p_kind,p_mime_type);
 IF p_user_id IS NULL OR p_asset_id IS NULL OR extension IS NULL OR p_declared_size_bytes IS NULL
  OR p_declared_size_bytes<1 OR p_declared_size_bytes>(CASE p_kind WHEN 'conversation_photo' THEN 15728640 ELSE 26214400 END)
  OR p_source_request_hash IS NULL OR p_source_request_hash!~'^[0-9a-f]{64}$'
  OR(p_context_text IS NOT NULL AND char_length(p_context_text) NOT BETWEEN 1 AND 1000) THEN
  RAISE EXCEPTION 'invalid_conversation_media_asset' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'conversation_media_owner_changed' USING ERRCODE='40001';END IF;
 at_time:=clock_timestamp();
 BEGIN
  INSERT INTO private.conversation_media_assets_v2(id,user_id,kind,bucket_id,object_path,mime_type,
   declared_size_bytes,context_text,source_request_hash,created_at,updated_at,retention_until)
  VALUES(p_asset_id,p_user_id,p_kind,CASE p_kind WHEN 'conversation_photo' THEN 'meal-photos' ELSE 'audio-notes' END,
   'conversation-v2/'||p_user_id::text||'/'||p_asset_id::text||'.'||extension,p_mime_type,
   p_declared_size_bytes,p_context_text,p_source_request_hash,at_time,at_time,at_time+interval '720hours')
  ON CONFLICT(user_id,source_request_hash) DO NOTHING RETURNING * INTO m;
 EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'conversation_media_identity_changed' USING ERRCODE='40001';
 END;
 IF NOT FOUND THEN
  SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE user_id=p_user_id AND source_request_hash=p_source_request_hash FOR SHARE;
 END IF;
 IF m.id IS NULL OR m.kind IS DISTINCT FROM p_kind OR m.mime_type IS DISTINCT FROM p_mime_type
  OR m.declared_size_bytes IS DISTINCT FROM p_declared_size_bytes OR m.context_text IS DISTINCT FROM p_context_text THEN
  RAISE EXCEPTION 'conversation_media_request_changed' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('schema','conversation.media-asset.v2','catalog_version',2,'asset',to_jsonb(m));
END $$;

CREATE FUNCTION public.get_conversation_media_asset_v2(p_user_id uuid,p_asset_id uuid,p_source_request_hash text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR(p_asset_id IS NULL)=(p_source_request_hash IS NULL)
  OR(p_source_request_hash IS NOT NULL AND p_source_request_hash!~'^[0-9a-f]{64}$') THEN
  RAISE EXCEPTION 'invalid_conversation_media_lookup' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN
  RAISE EXCEPTION 'conversation_media_owner_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE user_id=p_user_id
  AND((p_asset_id IS NOT NULL AND id=p_asset_id) OR(p_source_request_hash IS NOT NULL AND source_request_hash=p_source_request_hash));
 IF NOT FOUND THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('schema','conversation.media-asset.v2','catalog_version',2,'asset',to_jsonb(m));
END $$;
REVOKE ALL ON FUNCTION public.create_conversation_media_asset_v2(uuid,uuid,text,text,bigint,text,text),
 public.get_conversation_media_asset_v2(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_conversation_media_asset_v2(uuid,uuid,text,text,bigint,text,text),
 public.get_conversation_media_asset_v2(uuid,uuid,text) TO service_role;
COMMENT ON TABLE private.conversation_media_assets_v2 IS
 'New ordinary conversational media only. Disjoint private source and keys; no public mirror, client table privileges, historical import or clinical media. Foundation not activated by this migration.';
COMMENT ON TABLE private.conversation_media_identity_v2 IS
 'Opaque-ID collision barrier only, no owner/caption/path/result. Ordinary version2 identity is not recycled while legacy capabilities exist. Version1 reservation lasts only as long as its public row, without extra clinical retention. No legacy backfill.';
COMMIT;

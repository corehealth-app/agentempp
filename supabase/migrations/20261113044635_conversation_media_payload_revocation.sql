-- Ordinary payload revocation metadata guard; no schedule/flag activation.
-- Empty ordinary objects are barriers, not final deletion or drained tickets.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_expiry_debts') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='storage.buckets'::regclass AND attname='versioning_status' AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='storage.objects'::regclass AND attname='is_delete_marker' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'conversation_media_revocation_substrate_required' USING ERRCODE='42501';
 END IF;
END $guard$;
CREATE FUNCTION public.inspect_conversation_media_payload_revocation(p_asset_id uuid,p_user_id uuid,p_claim_token uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d private.conversation_media_expiry_debts%ROWTYPE;b storage.buckets%ROWTYPE;o storage.objects%ROWTYPE;
 at_time timestamptz:=clock_timestamp();mime text;size bigint;state text;object_count bigint;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_asset_id IS NULL OR p_user_id IS NULL OR p_claim_token IS NULL THEN RAISE EXCEPTION 'invalid_media_revocation_claim' USING ERRCODE='22023';END IF;
 SELECT * INTO d FROM private.conversation_media_expiry_debts WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR d.claim_token IS DISTINCT FROM p_claim_token OR d.lease_until IS NULL OR d.lease_until<=at_time THEN
  RAISE EXCEPTION 'media_revocation_claim_changed' USING ERRCODE='40001';END IF;
 mime:=CASE WHEN d.kind='conversation_photo' THEN 'image/jpeg' WHEN d.kind='audio_note' THEN 'audio/mp4' END;
 SELECT * INTO b FROM storage.buckets WHERE id=d.bucket_id;
 IF NOT FOUND OR b.public IS DISTINCT FROM false OR b.versioning_status::text IS DISTINCT FROM 'DISABLED'
  OR mime IS NULL OR b.allowed_mime_types IS NULL OR NOT (mime=ANY(b.allowed_mime_types))
  OR b.file_size_limit IS NULL OR b.file_size_limit<=0
  OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='storage.objects'::regclass) THEN
  RAISE EXCEPTION 'media_revocation_bucket_changed' USING ERRCODE='23514';END IF;
 SELECT count(*) INTO object_count FROM storage.objects WHERE bucket_id=d.bucket_id AND name=d.object_path;
 IF object_count=0 THEN state:='absent';size:=NULL;
 ELSIF object_count=1 THEN
  SELECT * INTO o FROM storage.objects WHERE bucket_id=d.bucket_id AND name=d.object_path;
  IF o.is_delete_marker IS DISTINCT FROM false OR o.archived_at IS NOT NULL OR o.version IS NULL OR o.version !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   OR jsonb_typeof(o.metadata->'size') IS DISTINCT FROM 'number'
   OR (o.metadata->>'size') !~ '^[0-9]{1,8}$' THEN
   RAISE EXCEPTION 'media_revocation_object_unknown' USING ERRCODE='23514';END IF;
  size:=(o.metadata->>'size')::bigint;
  IF size>b.file_size_limit OR size>26214400 THEN RAISE EXCEPTION 'media_revocation_object_unknown' USING ERRCODE='23514';END IF;
  state:=CASE WHEN size=0 THEN 'empty' ELSE 'payload' END;
 ELSE RAISE EXCEPTION 'media_revocation_object_unknown' USING ERRCODE='23514';END IF;
 RETURN jsonb_build_object('schema','conversation.media-revocation-state.v1','asset_id',d.asset_id,
  'user_id',d.user_id,'claim_token',p_claim_token,'bucket_id',d.bucket_id,'object_path',d.object_path,
  'bucket_private',true,'versioning','DISABLED','mime_type',mime,'state',state,'size_bytes',size,'object_version',CASE WHEN state='absent' THEN NULL ELSE o.version END);
END $$;
REVOKE ALL ON FUNCTION public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid) TO service_role;
COMMENT ON FUNCTION public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid) IS
 'Trusted cleanup-claim inspection only. Private non-versioned bucket and ordinary object metadata required. No Storage mutation or final ticket-drain assertion.';
COMMIT;

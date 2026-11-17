-- One owner/asset-specific disposal authorization for the private media API.
-- No global scan, old function replacement, Storage write, job or activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF current_user<>'postgres'
  OR to_regclass('private.conversation_media_disposals_v2') IS NULL
  OR to_regprocedure('private.close_conversation_media_source_v2(uuid,uuid)') IS NULL
  OR to_regprocedure('public.inspect_conversation_media_disposal_v2(uuid,uuid,uuid)') IS NULL
  OR to_regprocedure('public.acknowledge_conversation_media_disposal_v2(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'private_owned_disposal_substrate_required' USING ERRCODE='42501';
 END IF;
END $guard$;

CREATE FUNCTION public.claim_conversation_media_owned_disposal_v2(p_user_id uuid,p_asset_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE o private.conversation_media_obligations_v2%ROWTYPE;
 d private.conversation_media_disposals_v2%ROWTYPE;at_time timestamptz;result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL THEN
  RAISE EXCEPTION 'invalid_private_owned_disposal' USING ERRCODE='22023';END IF;
 -- Serialize account deactivation with this interactive authorization. Account
 -- cleanup has its own cutoff-scoped worker protocol and never uses this API.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RETURN NULL;END IF;
 -- This shared primitive locks catalog -> obligation -> disposal. It commits
 -- closure and independent debt before any external byte-removal operation.
 IF NOT private.close_conversation_media_source_v2(p_user_id,p_asset_id) THEN RETURN NULL;END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2
  WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR o.closed_at IS NULL THEN
  RAISE EXCEPTION 'private_owned_disposal_source_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO d FROM private.conversation_media_disposals_v2
  WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR d.disposed_at IS DISTINCT FROM o.closed_at THEN
  RAISE EXCEPTION 'private_owned_disposal_source_changed' USING ERRCODE='40001';END IF;
 result:=jsonb_build_object('schema','conversation.media-owned-disposal.v2','catalog_version',2,
  'user_id',p_user_id,'asset_id',p_asset_id,'claim',NULL);
 at_time:=clock_timestamp();
 IF d.lease_until IS NOT NULL AND d.lease_until>at_time THEN RETURN result;END IF;
 UPDATE private.conversation_media_disposals_v2 SET claim_token=gen_random_uuid(),
  lease_until=at_time+interval '5minutes',claim_revision=o.issuance_revision,last_attempt_at=at_time
  WHERE asset_id=p_asset_id AND user_id=p_user_id RETURNING * INTO d;
 RETURN result||jsonb_build_object('claim',jsonb_build_object('catalog_version',2,
  'asset_id',o.asset_id,'user_id',o.user_id,'kind',o.kind,'bucket_id',o.bucket_id,
  'object_path',o.object_path,'mime_type',o.mime_type,'declared_size_bytes',o.declared_size_bytes,
  'claim_token',d.claim_token));
END $$;
REVOKE ALL ON FUNCTION public.claim_conversation_media_owned_disposal_v2(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_conversation_media_owned_disposal_v2(uuid,uuid) TO service_role;
COMMENT ON FUNCTION public.claim_conversation_media_owned_disposal_v2(uuid,uuid) IS
 'Interactive private owner/asset closure and existing revision-fenced lease only. Never scans or claims another source. Empty markers and unresolved issuance are retained by existing inspect/ack protocol.';
COMMIT;

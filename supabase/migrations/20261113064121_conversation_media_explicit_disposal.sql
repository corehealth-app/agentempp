-- Owned ordinary disposal: commit debt/closure before leased byte revocation.
-- No Storage SQL writes, new activation, or final issuance-drain assertion.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid)') IS NULL
  OR to_regclass('private.conversation_media_upload_tickets') IS NULL THEN
  RAISE EXCEPTION 'conversation_media_disposal_substrate_required' USING ERRCODE='42501';END IF;
END $guard$;
CREATE FUNCTION public.claim_conversation_media_disposal(p_asset_id uuid,p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m public.media_assets%ROWTYPE;d private.conversation_media_expiry_debts%ROWTYPE;
 at_time timestamptz:=clock_timestamp();has_catalog boolean;claim jsonb:=NULL;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_asset_id IS NULL OR p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_conversation_media_disposal' USING ERRCODE='22023';END IF;
 SELECT * INTO m FROM public.media_assets WHERE id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 has_catalog:=FOUND;
 IF has_catalog THEN
  IF m.kind NOT IN('conversation_photo','audio_note') OR m.reevaluation_origin_version IS NOT NULL THEN
   RAISE EXCEPTION 'invalid_conversation_media_disposal_scope' USING ERRCODE='22023';END IF;
  INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path,disposed_at)
   VALUES(m.id,m.user_id,m.kind,m.bucket_id,m.object_path,at_time) ON CONFLICT(asset_id) DO NOTHING;
 END IF;
 SELECT * INTO d FROM private.conversation_media_expiry_debts WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'conversation_media_disposal_not_found' USING ERRCODE='P0002';END IF;
 IF has_catalog AND (d.kind IS DISTINCT FROM m.kind OR d.bucket_id IS DISTINCT FROM m.bucket_id OR d.object_path IS DISTINCT FROM m.object_path) THEN
  RAISE EXCEPTION 'conversation_media_disposal_scope_changed' USING ERRCODE='23514';END IF;
 IF has_catalog AND m.status<>'deleted' THEN
  UPDATE public.media_assets SET status='deleted',deleted_at=at_time,failure_stage=NULL,failure_code=NULL,processing_result=NULL
   WHERE id=p_asset_id AND user_id=p_user_id;
 END IF;
 -- Never steal another worker's live lease. A null claim is a deferred disposal,
 -- not a success, and does not permit any Storage operation or acknowledgment.
 IF d.claim_token IS NULL OR d.lease_until<=at_time THEN
  UPDATE private.conversation_media_expiry_debts SET claim_token=gen_random_uuid(),
   lease_until=at_time+interval '5minutes',last_attempt_at=at_time WHERE asset_id=d.asset_id RETURNING * INTO d;
  claim:=jsonb_build_object('asset_id',d.asset_id,'user_id',d.user_id,'kind',d.kind,
   'bucket_id',d.bucket_id,'object_path',d.object_path,'claim_token',d.claim_token);
 END IF;
 RETURN jsonb_build_object('schema','conversation.media-disposal.v1','asset_id',p_asset_id,'user_id',p_user_id,'claim',claim);
END $$;
REVOKE ALL ON FUNCTION public.claim_conversation_media_disposal(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_conversation_media_disposal(uuid,uuid) TO service_role;
COMMENT ON FUNCTION public.claim_conversation_media_disposal(uuid,uuid) IS
 'Trusted owned ordinary-media delete/mismatch preflight; same durable debt and exclusive lease as expiry. Closes catalogue first, no Storage mutation or final ticket-drain claim.';
COMMIT;

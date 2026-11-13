-- Conversation staging account cleanup: retain empty upload barriers and debt.
-- No Storage SQL writes, scheduler activation, or final issuance-drain claim.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_expiry_debts') IS NULL
  OR to_regprocedure('public.inspect_conversation_media_payload_revocation(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'conversation_media_account_purge_substrate_required' USING ERRCODE='42501';
 END IF;
END $guard$;
CREATE INDEX conversation_media_expiry_debts_owner ON private.conversation_media_expiry_debts(user_id,asset_id);
CREATE FUNCTION public.prepare_conversation_media_account_purge(p_user_id uuid,p_cutoff timestamptz) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz:=clock_timestamp();m public.media_assets%ROWTYPE;d private.conversation_media_expiry_debts%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time THEN
  RAISE EXCEPTION 'invalid_conversation_media_account_purge' USING ERRCODE='22023';END IF;
 -- Preserve the existing deleted-account cutoff; never touch an active owner.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='deleted' AND updated_at<=p_cutoff FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 -- Bound each enrollment visit. Later visits and the existing fair expiry worker
 -- continue an owner with >100 assets. No generic/clinical media is enrolled.
 FOR m IN SELECT a.* FROM public.media_assets a WHERE a.user_id=p_user_id
  AND a.kind IN('conversation_photo','audio_note') AND a.reevaluation_origin_version IS NULL
  AND (a.status<>'deleted' OR NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.asset_id=a.id AND x.user_id=a.user_id AND x.kind=a.kind AND x.bucket_id=a.bucket_id AND x.object_path=a.object_path))
  ORDER BY a.id LIMIT 100 FOR UPDATE OF a LOOP
  INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path,disposed_at)
   VALUES(m.id,m.user_id,m.kind,m.bucket_id,m.object_path,at_time) ON CONFLICT(asset_id) DO NOTHING;
  SELECT * INTO d FROM private.conversation_media_expiry_debts WHERE asset_id=m.id FOR UPDATE;
  IF d.user_id IS DISTINCT FROM m.user_id OR d.kind IS DISTINCT FROM m.kind
   OR d.bucket_id IS DISTINCT FROM m.bucket_id OR d.object_path IS DISTINCT FROM m.object_path THEN
   RAISE EXCEPTION 'conversation_media_account_debt_changed' USING ERRCODE='23514';END IF;
  IF m.status<>'deleted' THEN UPDATE public.media_assets SET status='deleted',deleted_at=at_time,
   failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=m.id AND user_id=p_user_id;END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.media_assets a WHERE a.user_id=p_user_id
  AND a.kind IN('conversation_photo','audio_note') AND a.reevaluation_origin_version IS NULL
  AND (a.status<>'deleted' OR NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.asset_id=a.id AND x.user_id=a.user_id AND x.kind=a.kind AND x.bucket_id=a.bucket_id AND x.object_path=a.object_path))) THEN
  RETURN false;END IF;
 -- An acknowledged sweep alone is insufficient. Require the current ordinary
 -- zero-byte barrier under the same private/no-direct-write bucket contract.
 -- This is account payload removal readiness, NOT ticket drain or final disposal.
 IF EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.user_id=p_user_id AND (
  x.last_successful_sweep_at IS NULL
  OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='storage.objects'::regclass)
  OR NOT EXISTS(SELECT 1 FROM storage.buckets b WHERE b.id=x.bucket_id AND b.public=false
    AND b.versioning_status::text='DISABLED' AND b.file_size_limit>0
    AND (CASE WHEN x.kind='conversation_photo' THEN 'image/jpeg' ELSE 'audio/mp4' END)=ANY(b.allowed_mime_types))
  OR (SELECT count(*) FROM storage.objects o WHERE o.bucket_id=x.bucket_id AND o.name=x.object_path)<>1
  OR NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id=x.bucket_id AND o.name=x.object_path
    AND o.is_delete_marker=false AND o.archived_at IS NULL
    AND o.version ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND jsonb_typeof(o.metadata->'size')='number' AND o.metadata->'size'='0'::jsonb)
 )) THEN RETURN false;END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.prepare_conversation_media_account_purge(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_conversation_media_account_purge(uuid,timestamptz) TO service_role;
COMMENT ON FUNCTION public.prepare_conversation_media_account_purge(uuid,timestamptz) IS
 'Conversation staging account preflight. Enroll <=100 ordinary cleanup debts; wait for current verified empty barriers. Account deletion must skip ordinary Storage removal and retain independent debt. Does not settle issuance drain.';
COMMIT;

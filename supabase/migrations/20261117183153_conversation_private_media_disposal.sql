-- Independent v2 byte disposition. No Storage SQL writes, old handler changes,
-- schedule/route activation, or assertion that outstanding capabilities drained.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_obligations_v2') IS NULL
  OR to_regclass('private.conversation_private_media_intakes_v2') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='storage.buckets'::regclass AND attname='versioning_status' AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='storage.objects'::regclass AND attname='is_delete_marker' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'private_media_disposal_substrate_required' USING ERRCODE='42501';END IF;
END $guard$;

CREATE TABLE private.conversation_media_disposals_v2 (
 asset_id uuid PRIMARY KEY REFERENCES private.conversation_media_obligations_v2(asset_id),
 user_id uuid NOT NULL,disposed_at timestamptz NOT NULL CHECK(isfinite(disposed_at)),
 last_attempt_at timestamptz,last_successful_sweep_at timestamptz,
 claim_token uuid,lease_until timestamptz,claim_revision bigint,
 last_completed_claim uuid,last_completed_revision bigint,
 CHECK((claim_token IS NULL)=(lease_until IS NULL) AND(claim_token IS NULL)=(claim_revision IS NULL)),
 CHECK((last_completed_claim IS NULL)=(last_completed_revision IS NULL)),
 CHECK(claim_revision IS NULL OR claim_revision>=0),
 CHECK(last_completed_revision IS NULL OR last_completed_revision>=0),
 CHECK(last_attempt_at IS NULL OR(isfinite(last_attempt_at) AND last_attempt_at>=disposed_at)),
 CHECK(last_successful_sweep_at IS NULL OR(isfinite(last_successful_sweep_at) AND last_successful_sweep_at>=disposed_at)),
 CHECK(lease_until IS NULL OR(isfinite(lease_until) AND lease_until>last_attempt_at))
);
ALTER TABLE private.conversation_media_disposals_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_disposals_v2 FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX conversation_private_disposals_fair ON private.conversation_media_disposals_v2(last_attempt_at NULLS FIRST,asset_id);
CREATE INDEX conversation_private_obligations_owner ON private.conversation_media_obligations_v2(user_id,asset_id);

-- Shared order catalog -> independent obligation -> disposal. Caller commits
-- this authority before any external removal; never infer a path from bytes.
CREATE FUNCTION private.close_conversation_media_source_v2(u uuid,a uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 d private.conversation_media_disposals_v2%ROWTYPE;has_catalog boolean;at_time timestamptz:=clock_timestamp();
BEGIN
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE id=a AND user_id=u FOR UPDATE;has_catalog:=FOUND;
 IF has_catalog THEN
  INSERT INTO private.conversation_media_obligations_v2(asset_id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,source_created_at,retention_until)
  VALUES(m.id,m.user_id,m.kind,m.bucket_id,m.object_path,m.mime_type,m.declared_size_bytes,m.created_at,m.retention_until)
  ON CONFLICT(asset_id) DO NOTHING;
 END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=a AND user_id=u FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 IF has_catalog AND ROW(m.user_id,m.kind,m.bucket_id,m.object_path,m.mime_type,m.declared_size_bytes,m.created_at,m.retention_until)
 IS DISTINCT FROM ROW(o.user_id,o.kind,o.bucket_id,o.object_path,o.mime_type,o.declared_size_bytes,o.source_created_at,o.retention_until) THEN
  RAISE EXCEPTION 'private_media_disposal_source_changed' USING ERRCODE='23514';END IF;
 UPDATE private.conversation_media_obligations_v2 SET closed_at=coalesce(closed_at,at_time) WHERE asset_id=a RETURNING * INTO o;
 IF has_catalog AND m.status<>'deleted' THEN
  UPDATE private.conversation_media_assets_v2 SET status='deleted',deleted_at=at_time,updated_at=at_time,
   failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=a AND user_id=u;
 END IF;
 INSERT INTO private.conversation_media_disposals_v2(asset_id,user_id,disposed_at)
 VALUES(a,u,o.closed_at) ON CONFLICT(asset_id) DO NOTHING;
 SELECT * INTO d FROM private.conversation_media_disposals_v2 WHERE asset_id=a;
 IF d.user_id IS DISTINCT FROM u OR d.disposed_at IS DISTINCT FROM o.closed_at THEN
  RAISE EXCEPTION 'private_media_disposal_source_changed' USING ERRCODE='23514';END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION private.close_conversation_media_source_v2(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.close_conversation_media_v2(p_user_id uuid,p_asset_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL THEN RAISE EXCEPTION 'invalid_private_disposal' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RETURN false;END IF;
 RETURN private.close_conversation_media_source_v2(p_user_id,p_asset_id);
END $$;

CREATE FUNCTION public.claim_conversation_media_disposal_batch_v2(p_limit integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 d private.conversation_media_disposals_v2%ROWTYPE;items jsonb:='[]';at_time timestamptz:=clock_timestamp();more boolean;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_private_disposal_limit' USING ERRCODE='22023';END IF;
 FOR m IN SELECT x.* FROM private.conversation_media_assets_v2 x
  WHERE (x.retention_until<=at_time OR x.status='deleted'
   OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 ox WHERE ox.asset_id=x.id AND ox.closed_at IS NOT NULL)
   OR NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=x.user_id AND u.status='active'))
  AND NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=x.id)
  ORDER BY x.retention_until,x.id LIMIT p_limit FOR UPDATE OF x SKIP LOCKED LOOP
  PERFORM private.close_conversation_media_source_v2(m.user_id,m.id);
 END LOOP;
 -- Late signing can close an independent obligation after catalog removal.
 -- Enroll it without requiring the owner, catalog or any historical payload.
 FOR o IN SELECT x.* FROM private.conversation_media_obligations_v2 x WHERE(x.closed_at IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 m2 WHERE m2.id=x.asset_id))
  AND NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=x.asset_id)
  ORDER BY x.closed_at,x.asset_id LIMIT p_limit FOR UPDATE OF x SKIP LOCKED LOOP
  UPDATE private.conversation_media_obligations_v2 SET closed_at=coalesce(closed_at,clock_timestamp()) WHERE asset_id=o.asset_id RETURNING * INTO o;
  INSERT INTO private.conversation_media_disposals_v2(asset_id,user_id,disposed_at)
  VALUES(o.asset_id,o.user_id,o.closed_at) ON CONFLICT(asset_id) DO NOTHING;
 END LOOP;
 -- Claim obligations first, in the same order as signer registration. A skip
 -- avoids a global worker waiting for an active signing/account transaction.
 FOR o IN SELECT x.* FROM private.conversation_media_obligations_v2 x
  JOIN private.conversation_media_disposals_v2 dx ON dx.asset_id=x.asset_id
  WHERE dx.lease_until IS NULL OR dx.lease_until<=at_time
  ORDER BY dx.last_attempt_at NULLS FIRST,x.asset_id LIMIT p_limit FOR UPDATE OF x SKIP LOCKED LOOP
  SELECT * INTO d FROM private.conversation_media_disposals_v2 WHERE asset_id=o.asset_id FOR UPDATE;
  IF d.user_id IS DISTINCT FROM o.user_id OR o.closed_at IS NULL THEN
   RAISE EXCEPTION 'private_media_disposal_source_changed' USING ERRCODE='23514';END IF;
  at_time:=clock_timestamp();
  UPDATE private.conversation_media_disposals_v2 SET claim_token=gen_random_uuid(),lease_until=at_time+interval '5minutes',
   claim_revision=o.issuance_revision,last_attempt_at=at_time WHERE asset_id=o.asset_id RETURNING * INTO d;
  items:=items||jsonb_build_array(jsonb_build_object('catalog_version',2,'asset_id',o.asset_id,'user_id',o.user_id,
   'kind',o.kind,'bucket_id',o.bucket_id,'object_path',o.object_path,'mime_type',o.mime_type,
   'declared_size_bytes',o.declared_size_bytes,'claim_token',d.claim_token));
 END LOOP;
 SELECT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.lease_until IS NULL OR dx.lease_until<=at_time)
  OR EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 x WHERE(x.retention_until<=at_time OR x.status='deleted'
   OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 ox WHERE ox.asset_id=x.id AND ox.closed_at IS NOT NULL)
   OR NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=x.user_id AND u.status='active'))
   AND NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=x.id))
  OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 ox WHERE(ox.closed_at IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 m2 WHERE m2.id=ox.asset_id))
   AND NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=ox.asset_id)) INTO more;
 RETURN jsonb_build_object('schema','conversation.media-disposal-page.v2','items',items,'has_more',more);
END $$;

CREATE FUNCTION private.conversation_media_object_state_v2(o private.conversation_media_obligations_v2) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE b storage.buckets%ROWTYPE;s storage.objects%ROWTYPE;mime text;size bigint;state text;n bigint;
BEGIN
 mime:=CASE o.kind WHEN 'conversation_photo' THEN 'image/jpeg' WHEN 'audio_note' THEN 'audio/mp4' END;
 SELECT * INTO b FROM storage.buckets WHERE id=o.bucket_id;
 IF NOT FOUND OR b.public IS DISTINCT FROM false OR b.versioning_status::text IS DISTINCT FROM 'DISABLED'
  OR mime IS NULL OR b.allowed_mime_types IS NULL OR NOT(mime=ANY(b.allowed_mime_types))
  OR b.file_size_limit IS NULL OR b.file_size_limit<=0 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='storage.objects'::regclass) THEN
  RAISE EXCEPTION 'private_media_disposal_bucket_changed' USING ERRCODE='23514';END IF;
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id=o.bucket_id AND name=o.object_path;
 IF n=0 THEN state:='absent';size:=NULL;
 ELSIF n=1 THEN
  SELECT * INTO s FROM storage.objects WHERE bucket_id=o.bucket_id AND name=o.object_path;
  IF s.is_delete_marker IS DISTINCT FROM false OR s.archived_at IS NOT NULL OR s.version IS NULL
   OR s.version!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   OR jsonb_typeof(s.metadata->'size') IS DISTINCT FROM 'number' OR(s.metadata->>'size')!~'^[0-9]{1,8}$' THEN
   RAISE EXCEPTION 'private_media_disposal_object_unknown' USING ERRCODE='23514';END IF;
  size:=(s.metadata->>'size')::bigint;
  IF size>b.file_size_limit OR size>26214400 THEN RAISE EXCEPTION 'private_media_disposal_object_unknown' USING ERRCODE='23514';END IF;
  state:=CASE WHEN size=0 THEN 'empty' ELSE 'payload' END;
 ELSE RAISE EXCEPTION 'private_media_disposal_object_unknown' USING ERRCODE='23514';END IF;
 RETURN jsonb_build_object('bucket_private',true,'versioning','DISABLED','mime_type',mime,'state',state,
  'size_bytes',size,'object_version',CASE WHEN state='absent' THEN NULL ELSE s.version END);
END $$;
REVOKE ALL ON FUNCTION private.conversation_media_object_state_v2(private.conversation_media_obligations_v2) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.inspect_conversation_media_disposal_v2(p_asset_id uuid,p_user_id uuid,p_claim_token uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE o private.conversation_media_obligations_v2%ROWTYPE;d private.conversation_media_disposals_v2%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_asset_id IS NULL OR p_user_id IS NULL OR p_claim_token IS NULL THEN RAISE EXCEPTION 'invalid_private_disposal_claim' USING ERRCODE='22023';END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR o.closed_at IS NULL THEN RAISE EXCEPTION 'private_media_disposal_claim_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO d FROM private.conversation_media_disposals_v2 WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR d.claim_token IS DISTINCT FROM p_claim_token OR d.lease_until IS NULL OR d.lease_until<=clock_timestamp()
  OR d.claim_revision IS DISTINCT FROM o.issuance_revision THEN
  RAISE EXCEPTION 'private_media_disposal_claim_changed' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('schema','conversation.media-disposal-state.v2','catalog_version',2,
  'asset_id',o.asset_id,'user_id',o.user_id,'claim_token',p_claim_token,'bucket_id',o.bucket_id,'object_path',o.object_path)
  ||private.conversation_media_object_state_v2(o);
END $$;

CREATE FUNCTION public.acknowledge_conversation_media_disposal_v2(p_asset_id uuid,p_user_id uuid,p_claim_token uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE o private.conversation_media_obligations_v2%ROWTYPE;d private.conversation_media_disposals_v2%ROWTYPE;
 at_time timestamptz:=clock_timestamp();
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_asset_id IS NULL OR p_user_id IS NULL OR p_claim_token IS NULL THEN RAISE EXCEPTION 'invalid_private_disposal_ack' USING ERRCODE='22023';END IF;
 SELECT * INTO o FROM private.conversation_media_obligations_v2 WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR o.closed_at IS NULL THEN RAISE EXCEPTION 'private_media_disposal_claim_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO d FROM private.conversation_media_disposals_v2 WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_media_disposal_claim_changed' USING ERRCODE='40001';END IF;
 IF d.last_completed_claim IS NOT DISTINCT FROM p_claim_token THEN
  IF d.last_completed_revision IS DISTINCT FROM o.issuance_revision THEN
   RAISE EXCEPTION 'private_media_disposal_claim_changed' USING ERRCODE='40001';END IF;
 ELSE
  IF d.claim_token IS DISTINCT FROM p_claim_token OR d.lease_until IS NULL OR d.lease_until<=at_time
   OR d.claim_revision IS DISTINCT FROM o.issuance_revision THEN
   RAISE EXCEPTION 'private_media_disposal_claim_changed' USING ERRCODE='40001';END IF;
 END IF;
 IF private.conversation_media_object_state_v2(o)->>'state' IS DISTINCT FROM 'empty' THEN
  RAISE EXCEPTION 'private_media_barrier_not_observed' USING ERRCODE='23514';END IF;
 IF d.last_completed_claim IS DISTINCT FROM p_claim_token THEN
  UPDATE private.conversation_media_disposals_v2 SET last_successful_sweep_at=at_time,
   last_completed_claim=p_claim_token,last_completed_revision=o.issuance_revision,
   claim_token=NULL,claim_revision=NULL,lease_until=NULL WHERE asset_id=o.asset_id;
 END IF;
 RETURN jsonb_build_object('schema','conversation.media-disposal-ack.v2','catalog_version',2,'asset_id',p_asset_id,
  'user_id',p_user_id,'claim_token',p_claim_token,'state','barrier_retained','issuance_reconciled',false);
END $$;

CREATE FUNCTION public.prepare_conversation_media_account_purge_v2(p_user_id uuid,p_cutoff timestamptz) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;o private.conversation_media_obligations_v2%ROWTYPE;
 d private.conversation_media_disposals_v2%ROWTYPE;at_time timestamptz:=clock_timestamp();
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time THEN
  RAISE EXCEPTION 'invalid_private_media_account_purge' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='deleted' AND updated_at<=p_cutoff FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 FOR m IN SELECT x.* FROM private.conversation_media_assets_v2 x WHERE x.user_id=p_user_id
  AND(x.status<>'deleted' OR NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=x.id))
  ORDER BY x.id LIMIT 100 FOR UPDATE OF x LOOP
  PERFORM private.close_conversation_media_source_v2(p_user_id,m.id);
 END LOOP;
 FOR o IN SELECT x.* FROM private.conversation_media_obligations_v2 x WHERE x.user_id=p_user_id
  AND NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 m2 WHERE m2.id=x.asset_id)
  AND(x.closed_at IS NULL OR NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=x.asset_id))
  ORDER BY x.asset_id LIMIT 100 FOR UPDATE OF x LOOP
  PERFORM private.close_conversation_media_source_v2(p_user_id,o.asset_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 x WHERE x.user_id=p_user_id
  AND(x.status<>'deleted' OR NOT EXISTS(SELECT 1 FROM private.conversation_media_disposals_v2 dx WHERE dx.asset_id=x.id))) THEN RETURN false;END IF;
 FOR o IN SELECT x.* FROM private.conversation_media_obligations_v2 x WHERE x.user_id=p_user_id ORDER BY x.asset_id FOR UPDATE OF x LOOP
  SELECT * INTO d FROM private.conversation_media_disposals_v2 WHERE asset_id=o.asset_id AND user_id=o.user_id FOR UPDATE;
  IF NOT FOUND OR o.closed_at IS NULL OR d.last_successful_sweep_at IS NULL OR d.last_completed_revision IS DISTINCT FROM o.issuance_revision THEN RETURN false;END IF;
  BEGIN
   IF private.conversation_media_object_state_v2(o)->>'state' IS DISTINCT FROM 'empty' THEN RETURN false;END IF;
  EXCEPTION WHEN check_violation THEN RETURN false;END;
 END LOOP;
 -- Only the current v2 catalog is detached. Ordinary historical receipts,
 -- opaque identity, independent obligation/tickets and empty objects remain.
 DELETE FROM private.conversation_media_assets_v2 WHERE user_id=p_user_id;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.close_conversation_media_v2(uuid,uuid),
 public.claim_conversation_media_disposal_batch_v2(integer),public.inspect_conversation_media_disposal_v2(uuid,uuid,uuid),
 public.acknowledge_conversation_media_disposal_v2(uuid,uuid,uuid),public.prepare_conversation_media_account_purge_v2(uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.close_conversation_media_v2(uuid,uuid),
 public.claim_conversation_media_disposal_batch_v2(integer),public.inspect_conversation_media_disposal_v2(uuid,uuid,uuid),
 public.acknowledge_conversation_media_disposal_v2(uuid,uuid,uuid),public.prepare_conversation_media_account_purge_v2(uuid,timestamptz)
 TO service_role;
COMMENT ON TABLE private.conversation_media_disposals_v2 IS
 'Independent v2 cleanup lease and sweep evidence; survives owner/catalog deletion. No caption/result/URL/token. Empty barriers and unresolved tickets remain; no legacy drain claim.';
COMMIT;

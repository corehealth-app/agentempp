-- Durable ordinary-media cleanup debt. No schedule/flag activation.
-- Legacy signing requests are untracked: no elapsed-time guess can settle debt.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('public.media_assets') IS NULL THEN
  RAISE EXCEPTION 'conversation_media_expiry_substrate_required' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.media_assets'::regclass
  AND attname='reevaluation_origin_version' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'conversation_media_expiry_origin_required' USING ERRCODE='42703';
 END IF;
END $guard$;
CREATE TABLE private.conversation_media_expiry_debts (
 asset_id uuid PRIMARY KEY, user_id uuid NOT NULL, kind text NOT NULL,
 bucket_id text NOT NULL, object_path text NOT NULL,
 disposed_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(disposed_at)),
 last_attempt_at timestamptz, last_successful_sweep_at timestamptz,
 claim_token uuid, lease_until timestamptz, last_completed_claim uuid,
 issuance_state text NOT NULL DEFAULT 'legacy_untracked' CHECK(issuance_state='legacy_untracked'),
 CHECK((kind='conversation_photo' AND bucket_id='meal-photos') OR(kind='audio_note' AND bucket_id='audio-notes')),
 CHECK(object_path ~ ('^'||user_id::text||'/'||asset_id::text||'[.][a-z0-9]+$')),
 CHECK((claim_token IS NULL)=(lease_until IS NULL)),
 CHECK(last_attempt_at IS NULL OR(isfinite(last_attempt_at) AND last_attempt_at>=disposed_at)),
 CHECK(last_successful_sweep_at IS NULL OR(isfinite(last_successful_sweep_at) AND last_successful_sweep_at>=disposed_at)),
 CHECK(lease_until IS NULL OR(isfinite(lease_until) AND lease_until>last_attempt_at))
);
-- Independent manifest deliberately survives catalog/user deletion until bytes
-- and outstanding issuance have been reconciled. It carries no caption/result.
ALTER TABLE private.conversation_media_expiry_debts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_expiry_debts FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX conversation_media_expiry_debts_fair_visit ON private.conversation_media_expiry_debts(last_attempt_at NULLS FIRST,asset_id);
CREATE FUNCTION public.claim_conversation_media_expiry_batch(p_limit integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz:=clock_timestamp();m public.media_assets%ROWTYPE;
 d private.conversation_media_expiry_debts%ROWTYPE;items jsonb:='[]';more boolean;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_media_expiry_limit' USING ERRCODE='22023';END IF;
 -- Canonical row lock orders expiry against upload completion/processing. Only
 -- ordinary, expired, non-recurring rows enter this independent manifest.
 FOR m IN SELECT a.* FROM public.media_assets a
  WHERE a.kind IN('conversation_photo','audio_note') AND a.retention_until<=at_time
   AND a.reevaluation_origin_version IS NULL
   AND NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.asset_id=a.id)
  ORDER BY a.retention_until,a.id LIMIT p_limit FOR UPDATE OF a SKIP LOCKED LOOP
  INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path,disposed_at)
   VALUES(m.id,m.user_id,m.kind,m.bucket_id,m.object_path,at_time) ON CONFLICT(asset_id) DO NOTHING;
  -- Close future issuance by old pending-replay callers before returning a
  -- Storage task. Already-started/issued capabilities remain explicitly unknown.
  IF m.status<>'deleted' THEN UPDATE public.media_assets SET status='deleted',deleted_at=at_time,
   failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=m.id AND user_id=m.user_id;END IF;
 END LOOP;
 FOR d IN SELECT x.* FROM private.conversation_media_expiry_debts x
  WHERE x.lease_until IS NULL OR x.lease_until<=at_time
  ORDER BY x.last_attempt_at NULLS FIRST,x.asset_id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
  UPDATE private.conversation_media_expiry_debts SET claim_token=gen_random_uuid(),
   lease_until=at_time+interval '5 minutes',last_attempt_at=at_time WHERE asset_id=d.asset_id RETURNING * INTO d;
  items:=items||jsonb_build_array(jsonb_build_object('asset_id',d.asset_id,'user_id',d.user_id,
   'kind',d.kind,'bucket_id',d.bucket_id,'object_path',d.object_path,'claim_token',d.claim_token));
 END LOOP;
 SELECT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x
  WHERE x.lease_until IS NULL OR x.lease_until<=at_time) OR EXISTS(SELECT 1 FROM public.media_assets a
  WHERE a.kind IN('conversation_photo','audio_note') AND a.retention_until<=at_time AND a.reevaluation_origin_version IS NULL
   AND NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.asset_id=a.id)) INTO more;
 RETURN jsonb_build_object('schema','conversation.media-expiry-page.v1','items',items,'has_more',more);
END $$;
CREATE FUNCTION public.acknowledge_conversation_media_expiry_sweep(p_asset_id uuid,p_user_id uuid,p_claim_token uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d private.conversation_media_expiry_debts%ROWTYPE;at_time timestamptz:=clock_timestamp();
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_asset_id IS NULL OR p_user_id IS NULL OR p_claim_token IS NULL THEN RAISE EXCEPTION 'invalid_media_expiry_ack' USING ERRCODE='22023';END IF;
 SELECT * INTO d FROM private.conversation_media_expiry_debts WHERE asset_id=p_asset_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'media_expiry_claim_changed' USING ERRCODE='40001';END IF;
 IF d.last_completed_claim IS DISTINCT FROM p_claim_token THEN
  IF d.claim_token IS DISTINCT FROM p_claim_token OR d.lease_until<=at_time THEN
   RAISE EXCEPTION 'media_expiry_claim_changed' USING ERRCODE='40001';END IF;
  UPDATE private.conversation_media_expiry_debts SET last_successful_sweep_at=at_time,
   last_completed_claim=p_claim_token,claim_token=NULL,lease_until=NULL WHERE asset_id=d.asset_id;
 END IF;
 -- Successful removal is NOT proof that legacy/in-flight signing drained.
 -- Retain fair retry debt even for deleted catalog rows; never silently settle.
 RETURN jsonb_build_object('schema','conversation.media-expiry-ack.v1','asset_id',p_asset_id,
  'user_id',p_user_id,'claim_token',p_claim_token,'state','waiting_for_issuance_drain');
END $$;
REVOKE ALL ON FUNCTION public.claim_conversation_media_expiry_batch(integer),
 public.acknowledge_conversation_media_expiry_sweep(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_conversation_media_expiry_batch(integer),
 public.acknowledge_conversation_media_expiry_sweep(uuid,uuid,uuid) TO service_role;
COMMENT ON TABLE private.conversation_media_expiry_debts IS
 'Private immutable owner/path cleanup manifest. Untracked legacy upload issuance prevents final settlement; repeated Storage sweeps remain required until separately qualified drain.';
COMMIT;

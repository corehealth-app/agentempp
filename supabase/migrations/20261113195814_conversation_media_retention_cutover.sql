-- Approved staging cutover: preserve existing ordinary media; only new
-- qualified upload lineage enters automatic expiry/account cleanup.
-- Does not activate a scheduler, alter Storage objects or settle old issuance.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_upload_tickets') IS NULL
  OR to_regprocedure('public.prepare_conversation_media_account_purge(uuid,timestamptz)') IS NULL
  OR to_regprocedure('public.claim_conversation_media_expiry_batch(integer)') IS NULL THEN
  RAISE EXCEPTION 'conversation_retention_cutover_substrate_required' USING ERRCODE='42501';END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid IN(
  'public.claim_conversation_media_expiry_batch(integer)'::regprocedure,
  'public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz)'::regprocedure,
  'public.prepare_conversation_media_account_purge(uuid,timestamptz)'::regprocedure)
  AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
  AND pg_get_userbyid(p.proowner)='postgres'
  AND p.proacl::text='{postgres=X/postgres,service_role=X/postgres}')<>3 THEN
  RAISE EXCEPTION 'conversation_retention_acl_drift' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.claim_conversation_media_expiry_batch(integer)'::regprocedure) IS DISTINCT FROM 'b8db85b7653d6b00d9a3aa3559748950e9c4da90484455c2fba4546f8c8717b2' THEN RAISE EXCEPTION 'conversation_retention_source_drift:claim_conversation_media_expiry_batch' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.register_conversation_media_upload(uuid,uuid,uuid,timestamp with time zone)'::regprocedure) IS DISTINCT FROM 'c01d87392d19de3aaecd345ca692366f25891b190f55864cfeb14602882bff84' THEN RAISE EXCEPTION 'conversation_retention_source_drift:register_conversation_media_upload' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.prepare_conversation_media_account_purge(uuid,timestamp with time zone)'::regprocedure) IS DISTINCT FROM 'b6ce83aa46c7b9f62fdea8b3f597e15f168e6467cf50f5e3454c9152cab450e1' THEN RAISE EXCEPTION 'conversation_retention_source_drift:prepare_conversation_media_account_purge' USING ERRCODE='55000';END IF;
END $guard$;
CREATE TABLE private.conversation_media_retention_cutover (
 singleton boolean PRIMARY KEY CHECK(singleton),
 starts_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(starts_at))
);
INSERT INTO private.conversation_media_retention_cutover(singleton) VALUES(true);
CREATE TABLE private.conversation_media_retention_cohort (
 asset_id uuid PRIMARY KEY,user_id uuid NOT NULL,kind text NOT NULL,
 bucket_id text NOT NULL,object_path text NOT NULL,ticket_id uuid NOT NULL,
 asset_created_at timestamptz NOT NULL,prepared_at timestamptz NOT NULL,cutover_at timestamptz NOT NULL,
 CHECK(isfinite(asset_created_at) AND isfinite(prepared_at) AND isfinite(cutover_at)),
 CHECK(asset_created_at>=cutover_at AND prepared_at>=asset_created_at),
 CHECK((kind='conversation_photo' AND bucket_id='meal-photos') OR(kind='audio_note' AND bucket_id='audio-notes')),
 CHECK(object_path ~ ('^'||user_id::text||'/'||asset_id::text||'[.][a-z0-9]+$'))
);
-- Independent technical provenance must survive catalog/account deletion.
ALTER TABLE private.conversation_media_retention_cutover ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_media_retention_cohort ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_retention_cutover,private.conversation_media_retention_cohort FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX conversation_media_retention_cohort_owner ON private.conversation_media_retention_cohort(user_id,asset_id);
CREATE FUNCTION private.freeze_conversation_media_retention_provenance() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN
 RAISE EXCEPTION 'conversation_media_retention_provenance_immutable' USING ERRCODE='23514';
END $$;
CREATE TRIGGER conversation_media_retention_cutover_frozen BEFORE UPDATE OR DELETE ON private.conversation_media_retention_cutover
 FOR EACH ROW EXECUTE FUNCTION private.freeze_conversation_media_retention_provenance();
CREATE TRIGGER conversation_media_retention_cohort_frozen BEFORE UPDATE OR DELETE ON private.conversation_media_retention_cohort
 FOR EACH ROW EXECUTE FUNCTION private.freeze_conversation_media_retention_provenance();
CREATE FUNCTION private.enroll_conversation_media_retention_cohort() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE at_cutover timestamptz;m public.media_assets%ROWTYPE;c private.conversation_media_retention_cohort%ROWTYPE;
BEGIN
 SELECT starts_at INTO at_cutover FROM private.conversation_media_retention_cutover WHERE singleton;
 IF at_cutover IS NULL OR NEW.prepared_at<at_cutover THEN RETURN NEW;END IF;
 SELECT * INTO m FROM public.media_assets WHERE id=NEW.asset_id AND user_id=NEW.user_id;
 IF NOT FOUND OR m.created_at<at_cutover OR m.reevaluation_origin_version IS NOT NULL
  OR m.kind NOT IN('conversation_photo','audio_note') THEN RETURN NEW;END IF;
 IF m.kind IS DISTINCT FROM NEW.kind OR m.bucket_id IS DISTINCT FROM NEW.bucket_id
  OR m.object_path IS DISTINCT FROM NEW.object_path
  OR NEW.asset_wire IS DISTINCT FROM private.conversation_upload_asset_wire(m) THEN
  RAISE EXCEPTION 'conversation_media_retention_source_changed' USING ERRCODE='23514';END IF;
 INSERT INTO private.conversation_media_retention_cohort(asset_id,user_id,kind,bucket_id,object_path,ticket_id,asset_created_at,prepared_at,cutover_at)
 VALUES(m.id,m.user_id,m.kind,m.bucket_id,m.object_path,NEW.ticket_id,m.created_at,NEW.prepared_at,at_cutover)
 ON CONFLICT(asset_id) DO NOTHING;
 SELECT * INTO c FROM private.conversation_media_retention_cohort WHERE asset_id=m.id;
 IF c.user_id IS DISTINCT FROM m.user_id OR c.kind IS DISTINCT FROM m.kind OR c.bucket_id IS DISTINCT FROM m.bucket_id
  OR c.object_path IS DISTINCT FROM m.object_path OR c.asset_created_at IS DISTINCT FROM m.created_at OR c.cutover_at IS DISTINCT FROM at_cutover THEN
  RAISE EXCEPTION 'conversation_media_retention_source_changed' USING ERRCODE='23514';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_media_retention_cohort_enrolled AFTER INSERT ON private.conversation_media_upload_tickets
 FOR EACH ROW EXECUTE FUNCTION private.enroll_conversation_media_retention_cohort();
CREATE FUNCTION private.conversation_media_retention_eligible(a uuid,u uuid,k text,b text,p text) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM private.conversation_media_retention_cohort c
 JOIN private.conversation_media_retention_cutover r ON r.singleton AND r.starts_at=c.cutover_at
 WHERE c.asset_id=a AND c.user_id=u AND c.kind=k AND c.bucket_id=b AND c.object_path=p);
$$;
REVOKE ALL ON FUNCTION private.freeze_conversation_media_retention_provenance(),private.enroll_conversation_media_retention_cohort(),
 private.conversation_media_retention_eligible(uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.register_conversation_media_upload(p_user_id uuid,p_asset_id uuid,p_ticket_id uuid,p_provider_expires_at timestamptz) RETURNS jsonb
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
 -- Preserve old assets/debts even when an old signing response arrives late.
 -- The actual capability expiry is still durably recorded above.
 IF NOT private.conversation_media_retention_eligible(t.asset_id,t.user_id,t.kind,t.bucket_id,t.object_path) THEN
  RETURN jsonb_build_object('schema','conversation.upload-registered.v1','ticket',private.conversation_upload_ticket_wire(t));END IF;
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

CREATE OR REPLACE FUNCTION public.claim_conversation_media_expiry_batch(p_limit integer) RETURNS jsonb
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
   AND a.reevaluation_origin_version IS NULL AND private.conversation_media_retention_eligible(a.id,a.user_id,a.kind,a.bucket_id,a.object_path)
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
  WHERE (x.lease_until IS NULL OR x.lease_until<=at_time) AND private.conversation_media_retention_eligible(x.asset_id,x.user_id,x.kind,x.bucket_id,x.object_path)
  ORDER BY x.last_attempt_at NULLS FIRST,x.asset_id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
  UPDATE private.conversation_media_expiry_debts SET claim_token=gen_random_uuid(),
   lease_until=at_time+interval '5 minutes',last_attempt_at=at_time WHERE asset_id=d.asset_id RETURNING * INTO d;
  items:=items||jsonb_build_array(jsonb_build_object('asset_id',d.asset_id,'user_id',d.user_id,
   'kind',d.kind,'bucket_id',d.bucket_id,'object_path',d.object_path,'claim_token',d.claim_token));
 END LOOP;
 SELECT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x
  WHERE (x.lease_until IS NULL OR x.lease_until<=at_time) AND private.conversation_media_retention_eligible(x.asset_id,x.user_id,x.kind,x.bucket_id,x.object_path)) OR EXISTS(SELECT 1 FROM public.media_assets a
  WHERE a.kind IN('conversation_photo','audio_note') AND a.retention_until<=at_time AND a.reevaluation_origin_version IS NULL AND private.conversation_media_retention_eligible(a.id,a.user_id,a.kind,a.bucket_id,a.object_path)
   AND NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.asset_id=a.id)) INTO more;
 RETURN jsonb_build_object('schema','conversation.media-expiry-page.v1','items',items,'has_more',more);
END $$;
CREATE OR REPLACE FUNCTION public.prepare_conversation_media_account_purge(p_user_id uuid,p_cutoff timestamptz) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz:=clock_timestamp();m public.media_assets%ROWTYPE;d private.conversation_media_expiry_debts%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time THEN
  RAISE EXCEPTION 'invalid_conversation_media_account_purge' USING ERRCODE='22023';END IF;
 -- Preserve the existing deleted-account cutoff; never touch an active owner.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='deleted' AND updated_at<=p_cutoff FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 -- Preserve old catalog AND independent old debts before touching any asset.
 -- A missing catalog row or new ticket on an old asset cannot waive the hold.
 IF EXISTS(SELECT 1 FROM public.media_assets a WHERE a.user_id=p_user_id
  AND a.kind IN('conversation_photo','audio_note') AND a.reevaluation_origin_version IS NULL
  AND NOT private.conversation_media_retention_eligible(a.id,a.user_id,a.kind,a.bucket_id,a.object_path))
 OR EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts x WHERE x.user_id=p_user_id
  AND NOT private.conversation_media_retention_eligible(x.asset_id,x.user_id,x.kind,x.bucket_id,x.object_path)) THEN
  RETURN false;END IF;

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
REVOKE ALL ON FUNCTION public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz),public.claim_conversation_media_expiry_batch(integer),public.prepare_conversation_media_account_purge(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz),public.claim_conversation_media_expiry_batch(integer),public.prepare_conversation_media_account_purge(uuid,timestamptz) TO service_role;
COMMENT ON TABLE private.conversation_media_retention_cohort IS 'New qualified ordinary upload lineage after immutable approved staging cutover. No content, signed URL or token. Independent technical identity survives deletion. Not issuance-drain evidence.';
COMMIT;

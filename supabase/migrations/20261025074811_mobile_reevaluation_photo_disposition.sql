-- Dormant recurring disposal. No policy publication, cron, event or Storage call.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501'; END IF;
 IF to_regclass('private.mobile_reevaluation_photo_processing_attempts') IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_requires_processing' USING ERRCODE='42P01'; END IF;
END $preflight$;
CREATE TABLE private.mobile_reevaluation_photo_dispositions(
 disposition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL,signup_generation uuid NOT NULL,
 cycle_id uuid NOT NULL,acceptance_id uuid NOT NULL UNIQUE,reason text NOT NULL CHECK(reason IN('discarded','expired','consent_changed','cycle_changed','completed','account_deleted')),
 request_revision bigint NOT NULL CHECK(request_revision>0),sealed_at timestamptz NOT NULL CHECK(isfinite(sealed_at)),
 manifest_count bigint NOT NULL CHECK(manifest_count>=0),capability_revision bigint NOT NULL DEFAULT 1 CHECK(capability_revision>0),
 sweep_no bigint NOT NULL DEFAULT 0 CHECK(sweep_no>=0),sweep_capability_revision bigint,
 sweep_started_at timestamptz,sweep_state text NOT NULL DEFAULT 'idle' CHECK(sweep_state IN('idle','pending','waiting','settled')),
 cursor uuid,next_sweep_at timestamptz,last_ack_at timestamptz,
 UNIQUE(disposition_id,user_id,signup_generation,cycle_id,acceptance_id),
 FOREIGN KEY(user_id,signup_generation,cycle_id,acceptance_id) REFERENCES private.mobile_reevaluation_photo_consents(user_id,signup_generation,cycle_id,acceptance_id),
 CHECK(sweep_capability_revision IS NULL OR sweep_capability_revision BETWEEN 1 AND capability_revision),
 CHECK(sweep_started_at IS NULL OR(isfinite(sweep_started_at) AND sweep_started_at>=sealed_at)),
 CHECK(last_ack_at IS NULL OR(isfinite(last_ack_at) AND last_ack_at>=sweep_started_at)),
 CHECK(next_sweep_at IS NULL OR isfinite(next_sweep_at)),
 CHECK((sweep_state='idle' AND cursor IS NULL AND sweep_started_at IS NULL AND sweep_capability_revision IS NULL AND next_sweep_at IS NULL)
  OR(sweep_state<>'idle' AND sweep_no>0 AND sweep_started_at IS NOT NULL AND sweep_capability_revision IS NOT NULL
   AND(sweep_state<>'waiting' OR next_sweep_at IS NOT NULL)
   AND(sweep_state NOT IN('waiting','settled') OR last_ack_at IS NOT NULL)))
);
CREATE TABLE private.mobile_reevaluation_photo_disposition_assets(
 disposition_id uuid NOT NULL,user_id uuid NOT NULL,signup_generation uuid NOT NULL,cycle_id uuid NOT NULL,acceptance_id uuid NOT NULL,
 asset_id uuid NOT NULL UNIQUE,pose text NOT NULL,mime_type text NOT NULL,bucket_id text NOT NULL CHECK(bucket_id='body-checkin-photos'),object_path text NOT NULL,
 last_sweep_no bigint NOT NULL DEFAULT 0 CHECK(last_sweep_no>=0),last_ack_at timestamptz,
 PRIMARY KEY(disposition_id,asset_id),
 FOREIGN KEY(disposition_id,user_id,signup_generation,cycle_id,acceptance_id) REFERENCES private.mobile_reevaluation_photo_dispositions(disposition_id,user_id,signup_generation,cycle_id,acceptance_id),
 FOREIGN KEY(asset_id,user_id,signup_generation,cycle_id,acceptance_id,pose) REFERENCES private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose),
 CHECK(mime_type IN('image/jpeg','image/png','image/webp','image/heic','image/heif')),
 CHECK(object_path=user_id::text||'/'||asset_id::text||'.'||CASE mime_type WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png' WHEN 'image/webp' THEN 'webp' WHEN 'image/heic' THEN 'heic' ELSE 'heif' END),
 CHECK((last_sweep_no=0 AND last_ack_at IS NULL) OR(last_sweep_no>0 AND last_ack_at IS NOT NULL AND isfinite(last_ack_at)))
);
ALTER TABLE private.mobile_reevaluation_photo_dispositions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_reevaluation_photo_disposition_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_dispositions,private.mobile_reevaluation_photo_disposition_assets FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX mobile_reevaluation_photo_disposition_owner ON private.mobile_reevaluation_photo_dispositions(user_id,acceptance_id);
CREATE FUNCTION private.preserve_mobile_reevaluation_photo_disposition() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE mutable text[]:=ARRAY['capability_revision','sweep_no','sweep_capability_revision','sweep_started_at','sweep_state','cursor','next_sweep_at','last_ack_at'];
BEGIN
 IF(to_jsonb(NEW)-mutable) IS DISTINCT FROM(to_jsonb(OLD)-mutable)
  OR NEW.capability_revision NOT BETWEEN OLD.capability_revision AND OLD.capability_revision+1
  OR NEW.sweep_no NOT BETWEEN OLD.sweep_no AND OLD.sweep_no+1 THEN
  RAISE EXCEPTION 'mobile_reevaluation_photo_disposition_immutable' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_photo_disposition BEFORE UPDATE ON private.mobile_reevaluation_photo_dispositions FOR EACH ROW EXECUTE FUNCTION private.preserve_mobile_reevaluation_photo_disposition();
CREATE FUNCTION private.preserve_mobile_reevaluation_photo_disposition_asset() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF(to_jsonb(NEW)-ARRAY['last_sweep_no','last_ack_at']) IS DISTINCT FROM(to_jsonb(OLD)-ARRAY['last_sweep_no','last_ack_at']) OR NEW.last_sweep_no<OLD.last_sweep_no THEN
  RAISE EXCEPTION 'mobile_reevaluation_photo_disposition_immutable' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_photo_disposition_asset BEFORE UPDATE ON private.mobile_reevaluation_photo_disposition_assets FOR EACH ROW EXECUTE FUNCTION private.preserve_mobile_reevaluation_photo_disposition_asset();
CREATE FUNCTION private.mobile_reevaluation_photo_cleanup_owner(p_user_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup' USING ERRCODE='22023'; END IF;
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_owner_missing' USING ERRCODE='P0002'; END IF;
END $$;
CREATE FUNCTION private.mobile_reevaluation_photo_disposition_wire(h private.mobile_reevaluation_photo_dispositions) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',(h).disposition_id,'user_id',(h).user_id,'signup_generation',(h).signup_generation,'cycle_id',(h).cycle_id,'acceptance_id',(h).acceptance_id,
  'reason',(h).reason,'request_revision',(h).request_revision::text,'sealed_at',to_char((h).sealed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'manifest_count',(h).manifest_count::text,'capability_revision',(h).capability_revision::text,'sweep_no',(h).sweep_no::text,'sweep_capability_revision',(h).sweep_capability_revision::text,
  'sweep_started_at',to_char((h).sweep_started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'sweep_state',(h).sweep_state,'cursor',(h).cursor,
  'next_sweep_at',to_char((h).next_sweep_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'last_ack_at',to_char((h).last_ack_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

-- Internal completion hook is for a future typed clinical transaction only.
-- Public entrypoints below can only request discard or derive stale authority.
CREATE FUNCTION private.seal_mobile_reevaluation_photo_disposition_at(p_user_id uuid,p_cycle_id uuid,p_acceptance_id uuid,p_reason text,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE a private.mobile_reevaluation_photo_consents%ROWTYPE;h private.mobile_reevaluation_photo_dispositions%ROWTYPE;at_time timestamptz;rev bigint;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 IF p_reason IS NULL OR p_reason NOT IN('discarded','expired','consent_changed','cycle_changed','completed','account_deleted') THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup' USING ERRCODE='22023'; END IF;
 LOCK TABLE public.legal_documents IN SHARE MODE;LOCK TABLE private.mobile_reevaluation_photo_policies IN SHARE MODE;
 SELECT x.* INTO a FROM private.mobile_reevaluation_photo_consents x WHERE x.user_id=p_user_id AND x.cycle_id=p_cycle_id AND x.acceptance_id=p_acceptance_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_scope_missing' USING ERRCODE='P0002'; END IF;
 SELECT x.* INTO h FROM private.mobile_reevaluation_photo_dispositions x WHERE x.acceptance_id=p_acceptance_id;
 IF FOUND THEN RETURN private.mobile_reevaluation_photo_disposition_wire(h); END IF;
 SELECT c.revision INTO rev FROM private.mobile_reevaluation_cycles c WHERE c.user_id=p_user_id AND c.cycle_id=p_cycle_id FOR UPDATE;
 PERFORM m.id FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=m.id WHERE l.user_id=p_user_id AND l.consent_acceptance_id=p_acceptance_id ORDER BY m.id FOR UPDATE OF m;
 at_time:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(at_time) OR at_time<a.last_activity_at THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup_clock' USING ERRCODE='22023'; END IF;
 INSERT INTO private.mobile_reevaluation_photo_dispositions(user_id,signup_generation,cycle_id,acceptance_id,reason,request_revision,sealed_at,manifest_count)
  SELECT p_user_id,a.signup_generation,p_cycle_id,p_acceptance_id,p_reason,rev,at_time,count(*) FROM private.mobile_reevaluation_photo_assets l
   WHERE l.user_id=p_user_id AND l.signup_generation=a.signup_generation AND l.cycle_id=p_cycle_id AND l.consent_acceptance_id=p_acceptance_id RETURNING * INTO h;
 INSERT INTO private.mobile_reevaluation_photo_disposition_assets(disposition_id,user_id,signup_generation,cycle_id,acceptance_id,asset_id,pose,mime_type,bucket_id,object_path)
  SELECT h.disposition_id,l.user_id,l.signup_generation,l.cycle_id,l.consent_acceptance_id,l.asset_id,l.pose,m.mime_type,m.bucket_id,m.object_path
   FROM private.mobile_reevaluation_photo_assets l JOIN public.media_assets m ON m.id=l.asset_id AND m.user_id=l.user_id AND m.reevaluation_origin_version=1
   WHERE l.user_id=p_user_id AND l.consent_acceptance_id=p_acceptance_id;
 IF(SELECT count(*) FROM private.mobile_reevaluation_photo_disposition_assets WHERE disposition_id=h.disposition_id)<>h.manifest_count THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_manifest_incomplete' USING ERRCODE='XX001'; END IF;
 UPDATE private.mobile_reevaluation_photo_consents SET revoked_at=at_time,revoked_reason=CASE p_reason WHEN 'cycle_changed' THEN 'generation_changed' WHEN 'account_deleted' THEN 'generation_changed' ELSE p_reason END WHERE acceptance_id=p_acceptance_id AND revoked_at IS NULL;
 UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=at_time,invalidated_reason=CASE WHEN p_reason='account_deleted' THEN 'cycle_changed' ELSE p_reason END
  WHERE user_id=p_user_id AND consent_acceptance_id=p_acceptance_id AND invalidated_at IS NULL;
 UPDATE private.mobile_reevaluation_cycles SET revision=revision+1 WHERE user_id=p_user_id AND cycle_id=p_cycle_id;
 RETURN private.mobile_reevaluation_photo_disposition_wire(h);
END $$;
CREATE FUNCTION public.discard_mobile_reevaluation_photos(p_user_id uuid,p_cycle_id uuid,p_acceptance_id uuid,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;ctx jsonb;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 IF p_expected_revision IS NULL OR p_expected_revision<1 THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup' USING ERRCODE='22023'; END IF;
 SELECT x.* INTO h FROM private.mobile_reevaluation_photo_dispositions x WHERE x.user_id=p_user_id AND x.cycle_id=p_cycle_id AND x.acceptance_id=p_acceptance_id;
 IF FOUND THEN
  IF h.reason<>'discarded' OR h.request_revision<>p_expected_revision THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_changed' USING ERRCODE='40001'; END IF;
  RETURN private.mobile_reevaluation_photo_disposition_wire(h);
 END IF;
 ctx:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,NULL);
 IF ctx->>'cycle_revision' IS DISTINCT FROM p_expected_revision::text OR ctx#>>'{current_acceptance,acceptance_id}' IS DISTINCT FROM p_acceptance_id::text
  OR private.mobile_reevaluation_photo_consent_wire(ctx)->>'availability' IS DISTINCT FROM 'available' THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_changed' USING ERRCODE='40001'; END IF;
 RETURN private.seal_mobile_reevaluation_photo_disposition_at(p_user_id,p_cycle_id,p_acceptance_id,'discarded',NULL);
END $$;

CREATE FUNCTION private.reopen_mobile_reevaluation_photo_disposition_ticket() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.provider_expires_at IS DISTINCT FROM OLD.provider_expires_at THEN
  UPDATE private.mobile_reevaluation_photo_dispositions SET capability_revision=capability_revision+1,
   sweep_state='idle',cursor=NULL,sweep_capability_revision=NULL,sweep_started_at=NULL,next_sweep_at=NULL,last_ack_at=NULL
   WHERE user_id=NEW.user_id AND cycle_id=NEW.cycle_id AND acceptance_id=NEW.consent_acceptance_id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER reopen_mobile_reevaluation_photo_disposition_ticket AFTER UPDATE ON private.mobile_reevaluation_photo_upload_tickets FOR EACH ROW EXECUTE FUNCTION private.reopen_mobile_reevaluation_photo_disposition_ticket();

CREATE FUNCTION private.prepare_mobile_reevaluation_photo_disposition_at(p_user_id uuid,p_cycle_id uuid,p_acceptance_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;a private.mobile_reevaluation_photo_consents%ROWTYPE;ctx jsonb;wire jsonb;at_time timestamptz;reason text;kind text;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 LOCK TABLE public.legal_documents IN SHARE MODE;LOCK TABLE private.mobile_reevaluation_photo_policies IN SHARE MODE;
 SELECT x.* INTO a FROM private.mobile_reevaluation_photo_consents x WHERE x.user_id=p_user_id AND x.cycle_id=p_cycle_id AND x.acceptance_id=p_acceptance_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_scope_missing' USING ERRCODE='P0002'; END IF;
 SELECT x.* INTO h FROM private.mobile_reevaluation_photo_dispositions x WHERE x.acceptance_id=p_acceptance_id FOR UPDATE;
 IF NOT FOUND THEN
  LOCK TABLE public.legal_documents IN SHARE MODE;LOCK TABLE private.mobile_reevaluation_photo_policies IN SHARE MODE;
  at_time:=coalesce(p_observed_at,clock_timestamp());
  IF(SELECT status FROM public.users WHERE id=p_user_id)='deleted' THEN reason:='account_deleted';
  ELSIF a.revoked_at IS NOT NULL THEN reason:=CASE a.revoked_reason WHEN 'generation_changed' THEN 'cycle_changed' ELSE a.revoked_reason END;
  ELSE
   BEGIN
    ctx:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);wire:=private.mobile_reevaluation_photo_consent_wire(ctx);
    IF ctx#>>'{current_acceptance,acceptance_id}' IS DISTINCT FROM p_acceptance_id::text THEN reason:='consent_changed';
    ELSIF wire->>'availability'='available' THEN
     RETURN jsonb_build_object('version',1,'user_id',p_user_id,'cycle_id',p_cycle_id,'acceptance_id',p_acceptance_id,'kind','live','disposition',NULL);
    ELSE reason:=CASE WHEN wire->>'unavailable_reason'='consent_expired' THEN 'expired' ELSE 'consent_changed' END;END IF;
   EXCEPTION WHEN SQLSTATE '40001' OR SQLSTATE 'P0002' THEN reason:='cycle_changed';END;
  END IF;
  PERFORM private.seal_mobile_reevaluation_photo_disposition_at(p_user_id,p_cycle_id,p_acceptance_id,reason,p_observed_at);
  SELECT x.* INTO h FROM private.mobile_reevaluation_photo_dispositions x WHERE x.acceptance_id=p_acceptance_id FOR UPDATE;
 END IF;
 at_time:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(at_time) OR at_time<h.sealed_at THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup_clock' USING ERRCODE='22023'; END IF;
 IF h.sweep_state='settled' THEN kind:='settled';
 ELSIF h.sweep_state='waiting' AND at_time<h.next_sweep_at THEN kind:='waiting';
 ELSE
  IF h.sweep_state<>'pending' THEN
   UPDATE private.mobile_reevaluation_photo_dispositions SET sweep_no=sweep_no+1,sweep_capability_revision=capability_revision,
    sweep_started_at=at_time,cursor=NULL,next_sweep_at=NULL,sweep_state=CASE WHEN manifest_count=0 THEN 'settled' ELSE 'pending' END,
    last_ack_at=CASE WHEN manifest_count=0 THEN at_time ELSE NULL END WHERE disposition_id=h.disposition_id RETURNING * INTO h;
  END IF;
  kind:=CASE WHEN h.sweep_state='settled' THEN 'settled' ELSE 'ready' END;
 END IF;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'cycle_id',p_cycle_id,'acceptance_id',p_acceptance_id,'kind',kind,'disposition',private.mobile_reevaluation_photo_disposition_wire(h));
END $$;
CREATE FUNCTION public.prepare_mobile_reevaluation_photo_disposition(p_user_id uuid,p_cycle_id uuid,p_acceptance_id uuid) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT private.prepare_mobile_reevaluation_photo_disposition_at(p_user_id,p_cycle_id,p_acceptance_id,NULL::timestamptz) $$;
CREATE FUNCTION public.list_mobile_reevaluation_photo_disposition_scopes(p_user_id uuid,p_after_acceptance uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;cursor uuid;more boolean;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('cycle_id',q.cycle_id,'acceptance_id',q.acceptance_id) ORDER BY q.acceptance_id),'[]'),max(q.acceptance_id::text)::uuid INTO result,cursor
  FROM(SELECT a.cycle_id,a.acceptance_id FROM private.mobile_reevaluation_photo_consents a WHERE a.user_id=p_user_id AND(p_after_acceptance IS NULL OR a.acceptance_id>p_after_acceptance) ORDER BY a.acceptance_id LIMIT p_limit) q;
 SELECT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_consents a WHERE a.user_id=p_user_id AND a.acceptance_id>cursor) INTO more;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'items',result,'has_more',more,'cursor',cursor);
END $$;

CREATE FUNCTION private.mobile_reevaluation_photo_disposition_page_header(p_user_id uuid,p_disposition_id uuid,p_sweep bigint,p_capability bigint,p_after uuid) RETURNS private.mobile_reevaluation_photo_dispositions
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 SELECT x.* INTO h FROM private.mobile_reevaluation_photo_dispositions x WHERE x.user_id=p_user_id AND x.disposition_id=p_disposition_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_scope_missing' USING ERRCODE='P0002'; END IF;
 IF p_sweep IS NULL OR p_capability IS NULL OR h.sweep_state<>'pending' OR h.sweep_no<>p_sweep
  OR h.sweep_capability_revision<>p_capability OR h.capability_revision<>p_capability OR h.cursor IS DISTINCT FROM p_after THEN
  RAISE EXCEPTION 'mobile_reevaluation_cleanup_changed' USING ERRCODE='40001'; END IF;
 RETURN h;
END $$;
CREATE FUNCTION public.get_mobile_reevaluation_photo_disposition_page(p_user_id uuid,p_disposition_id uuid,p_expected_sweep bigint,p_expected_capability_revision bigint,p_expected_after uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;items jsonb;last_id uuid;more boolean;
BEGIN
 h:=private.mobile_reevaluation_photo_disposition_page_header(p_user_id,p_disposition_id,p_expected_sweep,p_expected_capability_revision,p_expected_after);
 SELECT jsonb_agg(jsonb_build_object('asset_id',q.asset_id,'bucket_id',q.bucket_id,'object_path',q.object_path) ORDER BY q.asset_id),max(q.asset_id::text)::uuid INTO items,last_id
  FROM(SELECT a.* FROM private.mobile_reevaluation_photo_disposition_assets a WHERE a.disposition_id=p_disposition_id AND(p_expected_after IS NULL OR a.asset_id>p_expected_after) ORDER BY a.asset_id LIMIT 200) q;
 IF items IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_page_missing' USING ERRCODE='40001'; END IF;
 SELECT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_disposition_assets WHERE disposition_id=p_disposition_id AND asset_id>last_id) INTO more;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'signup_generation',h.signup_generation,'cycle_id',h.cycle_id,'acceptance_id',h.acceptance_id,'disposition_id',p_disposition_id,
  'sweep_no',p_expected_sweep::text,'capability_revision',p_expected_capability_revision::text,'cursor',p_expected_after,'items',items,'has_more',more);
END $$;
CREATE FUNCTION private.commit_mobile_reevaluation_photo_disposition_page_at(p_user_id uuid,p_disposition_id uuid,p_expected_sweep bigint,p_expected_capability_revision bigint,p_expected_after uuid,p_asset_ids uuid[],p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;expected uuid[];aid uuid;at_time timestamptz;complete boolean;unknown boolean;boundary timestamptz;state text;assets jsonb:='[]';m public.media_assets%ROWTYPE;newly boolean;cat_state text;next_cursor uuid;
BEGIN
 h:=private.mobile_reevaluation_photo_disposition_page_header(p_user_id,p_disposition_id,p_expected_sweep,p_expected_capability_revision,p_expected_after);
 IF p_asset_ids IS NULL OR cardinality(p_asset_ids) NOT BETWEEN 1 AND 200 OR array_ndims(p_asset_ids) IS DISTINCT FROM 1 OR array_lower(p_asset_ids,1) IS DISTINCT FROM 1 OR array_position(p_asset_ids,NULL::uuid) IS NOT NULL THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup_page' USING ERRCODE='22023'; END IF;
 SELECT array_agg(q.asset_id ORDER BY q.asset_id) INTO expected FROM(SELECT a.asset_id FROM private.mobile_reevaluation_photo_disposition_assets a WHERE a.disposition_id=p_disposition_id AND(p_expected_after IS NULL OR a.asset_id>p_expected_after) ORDER BY a.asset_id LIMIT 200) q;
 IF expected IS NULL OR p_asset_ids IS DISTINCT FROM expected THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_page_changed' USING ERRCODE='40001'; END IF;
 PERFORM x.id FROM public.media_assets x WHERE x.id=ANY(expected) ORDER BY x.id FOR UPDATE;
 at_time:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(at_time) OR at_time<h.sweep_started_at THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup_clock' USING ERRCODE='22023'; END IF;
 FOREACH aid IN ARRAY expected LOOP
  SELECT x.* INTO m FROM public.media_assets x JOIN private.mobile_reevaluation_photo_disposition_assets a ON a.asset_id=x.id
   WHERE a.disposition_id=p_disposition_id AND x.id=aid AND x.user_id=p_user_id AND x.reevaluation_origin_version=1 AND x.bucket_id=a.bucket_id AND x.object_path=a.object_path AND x.mime_type=a.mime_type FOR UPDATE OF x;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_asset_changed' USING ERRCODE='XX001'; END IF;
  newly:=m.status<>'deleted';cat_state:='deleted';
  IF m.status='failed' AND m.failure_stage='upload' THEN
   newly:=false;cat_state:='failed_upload_preserved';UPDATE public.media_assets SET processing_result=NULL WHERE id=aid;
  ELSE
   UPDATE public.media_assets SET status='deleted',deleted_at=coalesce(deleted_at,at_time),failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=aid;
  END IF;
  UPDATE private.mobile_reevaluation_photo_disposition_assets SET last_sweep_no=p_expected_sweep,last_ack_at=at_time WHERE disposition_id=p_disposition_id AND asset_id=aid;
  assets:=assets||jsonb_build_array(jsonb_build_object('asset_id',aid,'newly_deleted',newly,'catalogue_state',cat_state));
 END LOOP;
 next_cursor:=expected[cardinality(expected)];
 SELECT NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_disposition_assets WHERE disposition_id=p_disposition_id AND asset_id>next_cursor) INTO complete;
 state:='pending';
 IF complete THEN
  SELECT coalesce(bool_or(t.provider_expires_at IS NULL),false),max(t.provider_expires_at) INTO unknown,boundary FROM private.mobile_reevaluation_photo_upload_tickets t WHERE t.user_id=p_user_id AND t.consent_acceptance_id=h.acceptance_id;
  state:=CASE WHEN NOT unknown AND(boundary IS NULL OR h.sweep_started_at>boundary) THEN 'settled' ELSE 'waiting' END;
 END IF;
 UPDATE private.mobile_reevaluation_photo_dispositions SET cursor=next_cursor,sweep_state=state,last_ack_at=at_time,
  next_sweep_at=CASE WHEN state<>'waiting' THEN NULL WHEN unknown THEN at_time+interval '900seconds' ELSE greatest(at_time+interval '1microsecond',boundary+interval '1microsecond') END
  WHERE disposition_id=p_disposition_id;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'signup_generation',h.signup_generation,'cycle_id',h.cycle_id,'acceptance_id',h.acceptance_id,'disposition_id',p_disposition_id,
  'sweep_no',p_expected_sweep::text,'capability_revision',p_expected_capability_revision::text,'previous_cursor',p_expected_after,'cursor',next_cursor,'sweep_complete',complete,'state',state,'assets',assets);
END $$;
CREATE FUNCTION public.commit_mobile_reevaluation_photo_disposition_page(p_user_id uuid,p_disposition_id uuid,p_expected_sweep bigint,p_expected_capability_revision bigint,p_expected_after uuid,p_asset_ids uuid[]) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT private.commit_mobile_reevaluation_photo_disposition_page_at(p_user_id,p_disposition_id,p_expected_sweep,p_expected_capability_revision,p_expected_after,p_asset_ids,NULL::timestamptz) $$;

-- Every new public wrapper and every private helper is explicitly closed first.
DO $permissions$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature,n.nspname AS schema_name FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private') AND p.proname IN(
 'preserve_mobile_reevaluation_photo_disposition','preserve_mobile_reevaluation_photo_disposition_asset','mobile_reevaluation_photo_cleanup_owner','mobile_reevaluation_photo_disposition_wire','seal_mobile_reevaluation_photo_disposition_at','discard_mobile_reevaluation_photos','reopen_mobile_reevaluation_photo_disposition_ticket','prepare_mobile_reevaluation_photo_disposition_at','prepare_mobile_reevaluation_photo_disposition','list_mobile_reevaluation_photo_disposition_scopes','mobile_reevaluation_photo_disposition_page_header','get_mobile_reevaluation_photo_disposition_page','commit_mobile_reevaluation_photo_disposition_page_at','commit_mobile_reevaluation_photo_disposition_page') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
  IF f.schema_name='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',f.signature); END IF;
 END LOOP;
END $permissions$;
COMMIT;

-- Technical request uniqueness/routing only. No media import/retag, source-row
-- mutation, provider operation, route/worker activation or clinical change.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_disposals_v2') IS NULL
  OR to_regprocedure('public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'private_media_routing_substrate_required' USING ERRCODE='42501';END IF;
END $guard$;
-- Hold writes while establishing live request reservations and their triggers.
-- Old payloads/results never enter the reservation table. Catalog deletion
-- removes its transient reservation, including clinical/public reservations.
LOCK TABLE public.media_assets,private.conversation_media_assets_v2 IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE private.conversation_media_requests_v2(
 user_id uuid NOT NULL,source_request_hash text COLLATE "C" NOT NULL CHECK(source_request_hash~'^[0-9a-f]{64}$'),
 asset_id uuid NOT NULL,catalog_version smallint NOT NULL CHECK(catalog_version IN(1,2)),
 PRIMARY KEY(user_id,source_request_hash),UNIQUE(asset_id,catalog_version)
);
ALTER TABLE private.conversation_media_requests_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_media_requests_v2 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.conversation_media_requests_v2(user_id,source_request_hash,asset_id,catalog_version)
 SELECT user_id,source_request_hash,id,1 FROM public.media_assets WHERE source_request_hash~'^[0-9a-f]{64}$'
 UNION ALL SELECT user_id,source_request_hash,id,2 FROM private.conversation_media_assets_v2;

CREATE FUNCTION private.conversation_media_request_reservation_v2() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v smallint:=CASE TG_TABLE_SCHEMA WHEN 'public' THEN 1 ELSE 2 END;
BEGIN
 IF TG_OP='DELETE' THEN
  DELETE FROM private.conversation_media_requests_v2 WHERE user_id=OLD.user_id
   AND source_request_hash=OLD.source_request_hash AND asset_id=OLD.id AND catalog_version=v;
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND ROW(OLD.id,OLD.user_id,OLD.source_request_hash) IS DISTINCT FROM ROW(NEW.id,NEW.user_id,NEW.source_request_hash) THEN
  DELETE FROM private.conversation_media_requests_v2 WHERE user_id=OLD.user_id
   AND source_request_hash=OLD.source_request_hash AND asset_id=OLD.id AND catalog_version=v;
 END IF;
 -- Preserve old sources that have no usable technical hash. A new private
 -- source always has a valid hash, so these cannot conflict with its request.
 IF NEW.source_request_hash~'^[0-9a-f]{64}$' THEN
  IF(v=1 AND EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 x WHERE x.user_id=NEW.user_id AND x.source_request_hash=NEW.source_request_hash))
   OR(v=2 AND EXISTS(SELECT 1 FROM public.media_assets x WHERE x.user_id=NEW.user_id AND x.source_request_hash=NEW.source_request_hash)) THEN
   RAISE EXCEPTION 'media_request_catalog_conflict' USING ERRCODE='40001';END IF;
  INSERT INTO private.conversation_media_requests_v2 AS r(user_id,source_request_hash,asset_id,catalog_version)
  VALUES(NEW.user_id,NEW.source_request_hash,NEW.id,v)
  ON CONFLICT(user_id,source_request_hash) DO UPDATE SET asset_id=EXCLUDED.asset_id
   WHERE r.asset_id=EXCLUDED.asset_id AND r.catalog_version=EXCLUDED.catalog_version;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_request_catalog_conflict' USING ERRCODE='40001';END IF;
 END IF;
 RETURN NEW;
EXCEPTION WHEN serialization_failure OR unique_violation THEN
 RAISE EXCEPTION 'media_request_catalog_conflict' USING ERRCODE='40001';
END $$;
REVOKE ALL ON FUNCTION private.conversation_media_request_reservation_v2() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER conversation_media_request_public_v2 AFTER INSERT OR UPDATE OF id,user_id,source_request_hash OR DELETE ON public.media_assets
 FOR EACH ROW EXECUTE FUNCTION private.conversation_media_request_reservation_v2();
CREATE TRIGGER conversation_media_request_private_v2 AFTER INSERT OR UPDATE OF id,user_id,source_request_hash OR DELETE ON private.conversation_media_assets_v2
 FOR EACH ROW EXECUTE FUNCTION private.conversation_media_request_reservation_v2();

CREATE FUNCTION public.resolve_conversation_media_catalog_v2(p_user_id uuid,p_asset_id uuid,p_source_request_hash text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE a uuid;v smallint;k text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR(p_asset_id IS NULL)=(p_source_request_hash IS NULL)
  OR(p_source_request_hash IS NOT NULL AND p_source_request_hash!~'^[0-9a-f]{64}$') THEN
  RAISE EXCEPTION 'invalid_media_catalog_lookup' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN
  RAISE EXCEPTION 'media_catalog_owner_changed' USING ERRCODE='40001';END IF;
 BEGIN
 SELECT id,version,kind INTO STRICT a,v,k FROM(
  SELECT x.id,1::smallint AS version,x.kind FROM public.media_assets x WHERE x.user_id=p_user_id
   AND((p_asset_id IS NOT NULL AND x.id=p_asset_id) OR(p_source_request_hash IS NOT NULL AND x.source_request_hash=p_source_request_hash))
  UNION ALL SELECT x.id,2::smallint,x.kind FROM private.conversation_media_assets_v2 x WHERE x.user_id=p_user_id
   AND((p_asset_id IS NOT NULL AND x.id=p_asset_id) OR(p_source_request_hash IS NOT NULL AND x.source_request_hash=p_source_request_hash))
 ) sources;
 EXCEPTION WHEN no_data_found THEN RETURN NULL;WHEN too_many_rows THEN RAISE EXCEPTION 'media_catalog_ambiguous' USING ERRCODE='40001';END;
 -- No catch-and-fallback catalog probe. The live cross-catalog unique fence
 -- makes exactly one committed source authoritative for a technical request.
 RETURN jsonb_build_object('schema','conversation.media-catalog.v2','catalog_version',v,'asset_id',a,'user_id',p_user_id,'kind',k);
END $$;

CREATE FUNCTION public.admit_conversation_versioned_media_intake_v2(p_user_id uuid,p_expected_epoch uuid,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE actual uuid;i uuid;a uuid;v smallint;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_intake_input(p_input);
 IF p_input#>>'{source,channel}' IS DISTINCT FROM 'media' THEN RETURN public.admit_conversation_intake(p_user_id,p_expected_epoch,p_input);END IF;
 PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO actual FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF actual IS NULL OR actual IS DISTINCT FROM p_expected_epoch THEN RETURN '{"action":"stale_epoch"}';END IF;
 i:=(p_input->>'intake_id')::uuid;a:=(p_input#>>'{source,media_asset_id}')::uuid;
 PERFORM 1 FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=i FOR UPDATE;
 IF FOUND THEN
  -- Absence of a private binding on an existing admission means legacy forever,
  -- even after its old asset ID is reused or the private catalog disappears.
  IF EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=p_user_id AND intake_id=i) THEN
   RETURN public.admit_conversation_private_media_intake_v2(p_user_id,p_expected_epoch,p_input);
  END IF;
  RETURN public.admit_conversation_intake(p_user_id,p_expected_epoch,p_input);
 END IF;
 SELECT catalog_version INTO v FROM private.conversation_media_identity_v2 WHERE asset_id=a;
 IF v=2 THEN RETURN public.admit_conversation_private_media_intake_v2(p_user_id,p_expected_epoch,p_input);END IF;
 RETURN public.admit_conversation_intake(p_user_id,p_expected_epoch,p_input);
END $$;
REVOKE ALL ON FUNCTION public.resolve_conversation_media_catalog_v2(uuid,uuid,text),
 public.admit_conversation_versioned_media_intake_v2(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_conversation_media_catalog_v2(uuid,uuid,text),
 public.admit_conversation_versioned_media_intake_v2(uuid,uuid,jsonb) TO service_role;
COMMENT ON TABLE private.conversation_media_requests_v2 IS
 'Transient request identity for live v1/v2 catalog rows only; no caption/path/result or extra retention after catalog deletion. Shared unique index prevents a technical retry creating one asset in each catalog. Not a new media catalog or disposal authority.';
COMMIT;

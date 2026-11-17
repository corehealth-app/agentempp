-- Explicit private-media admission provenance. No public catalog mirror,
-- provider invocation, route activation or change to domain math/writers.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL search_path=pg_catalog;
DO $preflight$
DECLARE sig text;expected text;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_assets_v2') IS NULL THEN
  RAISE EXCEPTION 'private_media_capture_substrate_required' USING ERRCODE='42501';END IF;
 FOR sig,expected IN SELECT * FROM(VALUES
 ('private.conversation_intake_context(uuid,uuid)','ecdcbe51c424a777996154f2e7ae77632fe16672d1b5b41f54e444758f373ab3'),
 ('private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)','5ba0cf8752337007d4b3ea48df0d927e1db5f5962cb5387e7e235059690e7c1a'),
 ('private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)','6218b1bbdee113232cd16d606af8031ebf5b03379264f92c316b09b30871f153'),
 ('private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)','40ff5d2bb3f508c773783c9d79992ea596653abc71ca6a07cb700db87a151d8f'),
 ('private.conversation_workout_source_at(uuid,uuid,timestamp with time zone)','4d56528081eb8300e0486179c73473cb7e7cd3733f720969cd203f52dadeb22f'),
 ('public.admit_conversation_intake(uuid,uuid,jsonb)','1317813e9f7f7fa86b272820cb5c0bd4fdd889543018dfefb9bdada7df30af34')
 ) pins(signature,sha) LOOP
  IF to_regprocedure(sig) IS NULL OR(SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM expected THEN
   RAISE EXCEPTION 'private_media_capture_source_drift:%',sig USING ERRCODE='55000';END IF;
 END LOOP;
END $preflight$;

-- Absence means the historical version1 admission. Only the wrapper below may
-- create version2 at the same transaction boundary as a brand-new intake.
CREATE TABLE private.conversation_private_media_intakes_v2(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,asset_id uuid NOT NULL,
 catalog_version smallint NOT NULL DEFAULT 2 CHECK(catalog_version=2),
 PRIMARY KEY(user_id,intake_id),
 FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_inputs(user_id,intake_id) ON DELETE CASCADE
);
ALTER TABLE private.conversation_private_media_intakes_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_private_media_intakes_v2 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER conversation_private_media_intake_immutable BEFORE UPDATE ON private.conversation_private_media_intakes_v2
 FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();

CREATE FUNCTION private.conversation_private_media_catalog_version_v2(u uuid,i uuid,a uuid) RETURNS integer
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE b private.conversation_private_media_intakes_v2%ROWTYPE;
BEGIN
 SELECT * INTO b FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=i;
 IF NOT FOUND THEN RETURN 1;END IF;
 IF b.asset_id IS DISTINCT FROM a THEN RAISE EXCEPTION 'private_media_capture_binding_changed' USING ERRCODE='40001';END IF;
 RETURN 2;
END $$;

-- Common in-memory record shape for the existing readers only. No INSERT,
-- retagging, public row, source fallback or Storage capability is created.
CREATE FUNCTION private.read_conversation_media_record_v2(u uuid,a uuid,v integer) RETURNS SETOF public.media_assets
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE m private.conversation_media_assets_v2%ROWTYPE;
BEGIN
 IF v=1 THEN
  RETURN QUERY SELECT * FROM public.media_assets WHERE user_id=u AND id=a FOR SHARE NOWAIT;
 ELSIF v=2 THEN
  SELECT * INTO m FROM private.conversation_media_assets_v2 x WHERE x.user_id=u AND x.id=a
   AND x.created_at<=clock_timestamp() AND x.retention_until>clock_timestamp() AND x.deleted_at IS NULL
   AND NOT EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 o WHERE o.asset_id=x.id AND o.closed_at IS NOT NULL)
   FOR SHARE NOWAIT;
  IF FOUND THEN RETURN NEXT jsonb_populate_record(NULL::public.media_assets,to_jsonb(m));END IF;
 ELSE RAISE EXCEPTION 'private_media_capture_version_invalid' USING ERRCODE='22023';END IF;
END $$;
REVOKE ALL ON FUNCTION private.conversation_private_media_catalog_version_v2(uuid,uuid,uuid),
 private.read_conversation_media_record_v2(uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.admit_conversation_private_media_intake_v2(p_user_id uuid,p_expected_epoch uuid,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;m private.conversation_media_assets_v2%ROWTYPE;
 actual uuid;i uuid;a uuid;r jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_intake_input(p_input);
 IF p_input#>>'{source,channel}' IS DISTINCT FROM 'media' THEN RAISE EXCEPTION 'private_media_intake_required' USING ERRCODE='22023';END IF;
 PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO actual FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF actual IS NULL OR actual IS DISTINCT FROM p_expected_epoch THEN RETURN '{"action":"stale_epoch"}';END IF;
 i:=(p_input->>'intake_id')::uuid;a:=(p_input#>>'{source,media_asset_id}')::uuid;
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=i FOR UPDATE;
 IF FOUND THEN
  r:=public.admit_conversation_intake(p_user_id,p_expected_epoch,p_input);
  IF r->>'action'<>'replay' THEN RETURN r;END IF;
  IF NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=p_user_id AND intake_id=i AND asset_id=a) THEN RETURN '{"action":"input_conflict"}';END IF;
  RETURN r;
 END IF;
 SELECT * INTO m FROM private.conversation_media_assets_v2 WHERE user_id=p_user_id AND id=a FOR SHARE NOWAIT;
 IF NOT FOUND OR m.status='deleted' OR m.deleted_at IS NOT NULL OR m.retention_until<=clock_timestamp() OR m.created_at>clock_timestamp()
  OR EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 o WHERE o.asset_id=m.id AND o.closed_at IS NOT NULL) THEN RETURN '{"action":"media_unavailable"}';END IF;
 r:=public.admit_conversation_intake(p_user_id,p_expected_epoch,p_input);
 IF r->>'action'='admitted' THEN
  INSERT INTO private.conversation_private_media_intakes_v2(user_id,intake_id,asset_id) VALUES(p_user_id,i,a);
 END IF;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb) TO service_role;

-- Closed, fingerprinted read substitutions. All original owner, epoch, time,
-- classification, clinical, catalog, replay and domain-write fences remain.
DO $patch$
DECLARE body text;old text;new text;
BEGIN
 body:=pg_get_functiondef('private.conversation_intake_context(uuid,uuid)'::regprocedure);
 old:=$old$SELECT * INTO m FROM public.media_assets WHERE user_id=u AND id=(r.source_input#>>'{source,media_asset_id}')::uuid FOR SHARE NOWAIT;$old$;
 new:=$new$SELECT * INTO m FROM private.read_conversation_media_record_v2(u,(r.source_input#>>'{source,media_asset_id}')::uuid,
   private.conversation_private_media_catalog_version_v2(u,i,(r.source_input#>>'{source,media_asset_id}')::uuid));$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_intake_hook';END IF;body:=replace(body,old,new);
 old:=$old$ END IF;
 context:=jsonb_build_object('schema','conversation.intake-source.v1'$old$;
 new:=$new$  IF private.conversation_private_media_catalog_version_v2(u,i,m.id)=2 THEN media:=media||jsonb_build_object('catalog_version',2);END IF;
 END IF;
 context:=jsonb_build_object('schema','conversation.intake-source.v1'$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_intake_version_hook';END IF;
 EXECUTE replace(body,old,new);

 body:=pg_get_functiondef('private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)'::regprocedure);
 old:=$old$ IF require_selection THEN$old$;
 new:=$new$ IF private.conversation_private_media_catalog_version_v2(u,c.intake_id,(media->>'asset_id')::uuid)=2 THEN
  IF media->'catalog_version' IS DISTINCT FROM '2'::jsonb THEN RAISE EXCEPTION 'private_media_projection_version_changed' USING ERRCODE='40001';END IF;
  projection:=jsonb_set(projection,'{media,catalog_version}','2'::jsonb);
 ELSIF media ? 'catalog_version' THEN RAISE EXCEPTION 'legacy_media_projection_version_changed' USING ERRCODE='40001';END IF;
 IF require_selection THEN$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_projection_hook';END IF;
 EXECUTE replace(body,old,new);

 body:=pg_get_functiondef('private.conversation_meal_source_at(uuid,uuid,timestamptz)'::regprocedure);
 old:=$old$SELECT * INTO m FROM public.media_assets WHERE id=(input#>>'{source,media_asset_id}')::uuid AND user_id=p_user FOR SHARE NOWAIT;$old$;
 new:=$new$SELECT * INTO m FROM private.read_conversation_media_record_v2(p_user,(input#>>'{source,media_asset_id}')::uuid,coalesce((projection#>>'{media,catalog_version}')::integer,1));$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_meal_hook';END IF;body:=replace(body,old,new);
 old:=$old$IF projection IS NOT NULL THEN media:=media||jsonb_build_object('owner_id',m.user_id);evidence:=evidence||jsonb_build_object('context_text',m.context_text);END IF;$old$;
 new:=old||$new$
  IF projection#>>'{media,catalog_version}'='2' THEN media:=media||jsonb_build_object('catalog_version',2);END IF;$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_meal_version_hook';END IF;
 EXECUTE replace(body,old,new);

 body:=pg_get_functiondef('private.conversation_workout_source_at(uuid,uuid,timestamptz)'::regprocedure);
 old:=$old$SELECT * INTO m FROM public.media_assets WHERE user_id=p_user AND id=(input#>>'{source,media_asset_id}')::uuid FOR SHARE NOWAIT;$old$;
 new:=$new$SELECT * INTO m FROM private.read_conversation_media_record_v2(p_user,(input#>>'{source,media_asset_id}')::uuid,coalesce((projection#>>'{media,catalog_version}')::integer,1));$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_workout_hook';END IF;body:=replace(body,old,new);
 old:=$old$'context_text',m.context_text,'processing_result',m.processing_result);$old$;
 new:=old||$new$
  IF projection#>>'{media,catalog_version}'='2' THEN media:=media||jsonb_build_object('catalog_version',2);END IF;$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_workout_version_hook';END IF;
 EXECUTE replace(body,old,new);

 body:=pg_get_functiondef('private.conversation_continuation_original_current_at(uuid,jsonb,timestamptz)'::regprocedure);
 old:=$old$SELECT * INTO m FROM public.media_assets WHERE id=(raw#>>'{source,media_asset_id}')::uuid AND user_id=p_user FOR SHARE NOWAIT;$old$;
 new:=$new$SELECT * INTO m FROM private.read_conversation_media_record_v2(p_user,(raw#>>'{source,media_asset_id}')::uuid,coalesce((original#>>'{intake_projection,media,catalog_version}')::integer,1));$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_continuation_hook';END IF;body:=replace(body,old,new);
 old:=$old$ RETURN original->'media' IS NOT DISTINCT FROM media$old$;
 new:=$new$ IF original#>>'{intake_projection,media,catalog_version}'='2' THEN media:=media||jsonb_build_object('catalog_version',2);END IF;
 RETURN original->'media' IS NOT DISTINCT FROM media$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_capture_continuation_version_hook';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
COMMENT ON TABLE private.conversation_private_media_intakes_v2 IS
 'Immutable explicit version2 source binding created with a new intake only. Missing binding remains legacy1; never probe/fallback between catalogs. Scrubs with the original intake input.';
COMMIT;

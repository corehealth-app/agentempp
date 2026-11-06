-- An ordinary conversational photo is not a meal registration or a body
-- assessment. Reuse the existing private ordinary-photo infrastructure, with
-- a distinct immutable purpose. No bucket, policy, row, RPC or flag is changed.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
DECLARE r record; expression text;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'conversation_photo_requires_postgres' USING ERRCODE='42501'; END IF;
 -- Preserve each installed old predicate verbatim; refuse unknown drift before
 -- taking it as DDL. These fingerprints were read from the staging catalog.
 FOR r IN SELECT * FROM (VALUES
  ('media_assets_kind_check','7174da6deb7fc27b24ec719a73c547e0b9e55e623a3f49b11cca8e2f1effe283', $$kind='conversation_photo'$$),
  ('media_assets_bucket_kind_check','690e5f8253baf5fb03a183613c6b05451119c45058c1dda04c8ee9de5d49f073', $$kind='conversation_photo' AND bucket_id='meal-photos'$$),
  ('media_assets_mime_kind_check','848c45b7563e5711894a3a2fbd54290562c3c745807377c1afd72674f99b8cb5', $$kind='conversation_photo' AND mime_type IN ('image/jpeg','image/png','image/webp','image/heic','image/heif')$$),
  ('media_assets_size_check','39df56f08463d0f970caac9bf8d9a1e530b331eba9a47a61cb963906a4f66094', $$kind='conversation_photo' AND declared_size_bytes>0 AND declared_size_bytes<=15728640 AND (actual_size_bytes IS NULL OR actual_size_bytes=declared_size_bytes)$$)
 ) t(name,sha,addition) LOOP
  SELECT pg_get_expr(c.conbin,c.conrelid) INTO expression FROM pg_constraint c
   WHERE c.conrelid='public.media_assets'::regclass AND c.conname=r.name AND c.contype='c' AND c.convalidated;
  IF expression IS NULL OR encode(sha256(convert_to(expression,'UTF8')),'hex')<>r.sha THEN
   RAISE EXCEPTION 'conversation_photo_constraint_drift: %',r.name USING ERRCODE='55000';
  END IF;
 END LOOP;
 IF to_regprocedure('private.preserve_conversation_photo_source()') IS NOT NULL THEN
  RAISE EXCEPTION 'conversation_photo_unknown_existing_object' USING ERRCODE='42P07'; END IF;
END $preflight$;
-- Serialize the check and replacement; another transaction cannot change the
-- catalog between them. A timeout aborts the entire transaction.
LOCK TABLE public.media_assets IN ACCESS EXCLUSIVE MODE;
DO $expand$
DECLARE r record; expression text;
BEGIN
 FOR r IN SELECT * FROM (VALUES
  ('media_assets_kind_check','7174da6deb7fc27b24ec719a73c547e0b9e55e623a3f49b11cca8e2f1effe283', $$kind='conversation_photo'$$),
  ('media_assets_bucket_kind_check','690e5f8253baf5fb03a183613c6b05451119c45058c1dda04c8ee9de5d49f073', $$kind='conversation_photo' AND bucket_id='meal-photos'$$),
  ('media_assets_mime_kind_check','848c45b7563e5711894a3a2fbd54290562c3c745807377c1afd72674f99b8cb5', $$kind='conversation_photo' AND mime_type IN ('image/jpeg','image/png','image/webp','image/heic','image/heif')$$),
  ('media_assets_size_check','39df56f08463d0f970caac9bf8d9a1e530b331eba9a47a61cb963906a4f66094', $$kind='conversation_photo' AND declared_size_bytes>0 AND declared_size_bytes<=15728640 AND (actual_size_bytes IS NULL OR actual_size_bytes=declared_size_bytes)$$)
 ) t(name,sha,addition) LOOP
  SELECT pg_get_expr(c.conbin,c.conrelid) INTO expression FROM pg_constraint c
   WHERE c.conrelid='public.media_assets'::regclass AND c.conname=r.name AND c.contype='c' AND c.convalidated;
  IF expression IS NULL OR encode(sha256(convert_to(expression,'UTF8')),'hex')<>r.sha THEN
   RAISE EXCEPTION 'conversation_photo_constraint_drift: %',r.name USING ERRCODE='55000'; END IF;
  EXECUTE format('ALTER TABLE public.media_assets DROP CONSTRAINT %I',r.name);
  EXECUTE format('ALTER TABLE public.media_assets ADD CONSTRAINT %I CHECK ((%s) OR (%s))',r.name,expression,r.addition);
 END LOOP;
END $expand$;
CREATE FUNCTION private.preserve_conversation_photo_source() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF (NEW.kind='conversation_photo' OR OLD.kind='conversation_photo') AND
  ROW(NEW.id,NEW.user_id,NEW.kind,NEW.bucket_id,NEW.object_path,NEW.mime_type,
      NEW.declared_size_bytes,NEW.context_text,NEW.source_request_hash,NEW.created_at,
      NEW.signup_origin,NEW.signup_disposition_version,NEW.reevaluation_origin_version)
  IS DISTINCT FROM
  ROW(OLD.id,OLD.user_id,OLD.kind,OLD.bucket_id,OLD.object_path,OLD.mime_type,
      OLD.declared_size_bytes,OLD.context_text,OLD.source_request_hash,OLD.created_at,
      OLD.signup_origin,OLD.signup_disposition_version,OLD.reevaluation_origin_version) THEN
  RAISE EXCEPTION 'conversation_photo_source_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.preserve_conversation_photo_source() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER preserve_conversation_photo_source BEFORE UPDATE ON public.media_assets
 FOR EACH ROW EXECUTE FUNCTION private.preserve_conversation_photo_source();
COMMIT;

-- Version-aware historical observation of immutable private-media provenance.
-- No live catalog lookup, content retention, replay, fact, reward or schedule.
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='20s';
SET LOCAL search_path=pg_catalog;
DO $preflight$
DECLARE sig text;expected text;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_private_media_intakes_v2') IS NULL
 OR to_regprocedure('private.conversation_journal_private_media_input_v2(uuid,jsonb)') IS NOT NULL
 OR to_regprocedure('private.conversation_journal_versioned_media_input_v3(uuid,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'private_journal_substrate_conflict' USING ERRCODE='55000';END IF;
 FOR sig,expected IN SELECT * FROM(VALUES
  ('private.conversation_journal_media_input_v3(uuid,jsonb)','a7a401e2b6d12269ada36a6c5c8531b67a9227217cde6a143b6f85a305a215f0'),
  ('private.conversation_journal_parent_v3(uuid,uuid,uuid)','db6f6fe158a53ff3eee8afd65342e0e4bebbd7eac371066d6c3c747b0e3d2850'),
  ('public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','ed651eb30c65f668425ad01e463aabe50809962851874989b52ae359fe523392')
 ) pins(signature,sha) LOOP
  IF to_regprocedure(sig) IS NULL OR(SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM expected THEN
   RAISE EXCEPTION 'private_journal_unknown_predecessor:%',sig USING ERRCODE='55000';END IF;
 END LOOP;
END $preflight$;

-- Preserve the literal legacy observer and derive a separate strict version2
-- observer from its fingerprinted body. Every original hash/identity/selection
-- check survives. Only the explicit immutable namespace and projected marker
-- differ; disposal of actual content does not invalidate captured history.
DO $private_observer$
DECLARE body text;old text;replacement text;
BEGIN
 body:=pg_get_functiondef('private.conversation_journal_media_input_v3(uuid,jsonb)'::regprocedure);
 old:='private.conversation_journal_media_input_v3(';
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_journal_identity_hook';END IF;
 body:=replace(body,old,'private.conversation_journal_private_media_input_v2(');
 body:=replace(body,'CREATE OR REPLACE FUNCTION','CREATE FUNCTION');
 old:=$old$ media:=s.context->'media';$old$;
 replacement:=old||$new$
 IF media->'catalog_version' IS DISTINCT FROM '2'::jsonb
 OR NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 b
  WHERE b.user_id=u AND b.intake_id=c.intake_id AND b.asset_id=(raw#>>'{source,media_asset_id}')::uuid AND b.catalog_version=2)
 THEN RETURN false;END IF;$new$;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_journal_namespace_hook';END IF;
 body:=replace(body,old,replacement);
 old:=$old$ PERFORM private.conversation_meal_keys(selected,ARRAY['schema','intake','source_hash','decision_hash','decision','selected_at','command','media_projection']);$old$;
 replacement:=$new$ projection:=jsonb_set(projection,'{media,catalog_version}','2'::jsonb);
$new$||old;
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_journal_projection_hook';END IF;
 EXECUTE replace(body,old,replacement);
END $private_observer$;

CREATE FUNCTION private.conversation_journal_versioned_media_input_v3(u uuid,input jsonb) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE i uuid;media jsonb;selected_media jsonb;binding private.conversation_private_media_intakes_v2%ROWTYPE;
BEGIN
 i:=(input#>>'{intake_origin,intake_id}')::uuid;
 SELECT context->'media' INTO media FROM private.conversation_intake_sources WHERE user_id=u AND intake_id=i;
 SELECT selection#>'{media_projection,media}' INTO selected_media FROM private.conversation_intake_selections WHERE user_id=u AND intake_id=i;
 IF media IS NULL OR selected_media IS NULL THEN RETURN false;END IF;
 SELECT * INTO binding FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=i;
 IF FOUND THEN
  IF binding.catalog_version IS DISTINCT FROM 2 OR binding.asset_id::text IS DISTINCT FROM input#>>'{source,media_asset_id}'
  OR media->'catalog_version' IS DISTINCT FROM '2'::jsonb OR selected_media->'catalog_version' IS DISTINCT FROM '2'::jsonb THEN RETURN false;END IF;
  RETURN private.conversation_journal_private_media_input_v2(u,input);
 END IF;
 -- Absence is legacy only when both immutable captures are marker-free.
 -- A forged/unknown version never falls back to the public or private catalog.
 IF media ? 'catalog_version' OR selected_media ? 'catalog_version' THEN RETURN false;END IF;
 RETURN private.conversation_journal_media_input_v3(u,input);
EXCEPTION WHEN data_exception THEN RETURN false;
END $$;

-- Change exactly the two observational consumers. No global/live writer or
-- admission validator is redirected, and the old observer remains untouched.
DO $journal_consumers$
DECLARE sig text;body text;old text:='private.conversation_journal_media_input_v3(';
BEGIN
 FOREACH sig IN ARRAY ARRAY['private.conversation_journal_parent_v3(uuid,uuid,uuid)',
  'public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)'] LOOP
  body:=pg_get_functiondef(to_regprocedure(sig));
  IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_journal_consumer_hook:%',sig;END IF;
  EXECUTE replace(body,old,'private.conversation_journal_versioned_media_input_v3(');
 END LOOP;
END $journal_consumers$;
REVOKE ALL ON FUNCTION private.conversation_journal_private_media_input_v2(uuid,jsonb),
 private.conversation_journal_versioned_media_input_v3(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION private.conversation_journal_versioned_media_input_v3(uuid,jsonb) IS
 'Read-only immutable history validator. Explicit intake namespace chooses legacy1 or private2; no catalog access, disposal dependency or side effects.';
COMMIT;

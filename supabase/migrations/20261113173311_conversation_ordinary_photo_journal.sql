-- Extend only the observational original-media validator to the same classified
-- ordinary-photo domain policy already enforced by intake admission. No writes,
-- new authority, retained content, grants, schedules or historical rewrites.
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='20s';
DO $journal_ordinary$
DECLARE fn regprocedure := 'private.conversation_journal_media_input_v3(uuid,jsonb)'::regprocedure;
 body text; old text := $old$OR (r.decision->>'kind'='meal.report' AND media->>'kind' NOT IN('meal_photo','audio_note'))
 OR (r.decision->>'kind'='workout.report' AND media->>'kind' NOT IN('gym_photo','audio_note'))$old$; replacement text := $new$OR NOT private.conversation_photo_domain_allowed(media->>'kind',media->'processing_result',r.decision->>'kind')$new$;
BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.conversation_photo_domain_allowed(text,jsonb,text)') IS NULL THEN
  RAISE EXCEPTION 'ordinary_journal_missing_domain_policy' USING ERRCODE='55000'; END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=fn) IS DISTINCT FROM '79257c7dea68a811f78229370ceadc9c6e3ba096a5d1588476d53fe0fb0e1f17' THEN
  RAISE EXCEPTION 'ordinary_journal_unknown_predecessor' USING ERRCODE='55000'; END IF;
 body := pg_get_functiondef(fn);
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN
  RAISE EXCEPTION 'ordinary_journal_domain_hook_count' USING ERRCODE='55000'; END IF;
 EXECUTE replace(body,old,replacement);
END $journal_ordinary$;
COMMIT;

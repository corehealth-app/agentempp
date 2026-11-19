-- Keep the old unified journal readable by servers without name-answer DTOs.
-- New servers select v4; the public page schema remains v3. Both retain the
-- exact qualified private-media validators. Filter unsupported threads before
-- pagination; immutable observations, effects and original receipts are intact.
BEGIN;
SET LOCAL lock_timeout='3s';
DO $compat$
DECLARE body text;old text;new text;
BEGIN
 IF to_regprocedure('public.read_conversation_journal_page_v4(uuid,uuid,integer,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'unified_name_reader_already_exists'; END IF;
 body:=pg_get_functiondef('public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)'::regprocedure);
 IF encode(sha256(convert_to(body,'UTF8')),'hex')<>'e487ab89668f3caa9e3023be165bb5b2feae0c1f9a9edcc0f0b3835dd0c4fa17' THEN
  RAISE EXCEPTION 'unified_name_reader_source_changed'; END IF;
 old:='public.read_conversation_journal_page_v3(';
 IF cardinality(string_to_array(body,old))<>2 THEN RAISE EXCEPTION 'unified_name_reader_identity'; END IF;
 EXECUTE replace(body,old,'public.read_conversation_journal_page_v4(');
 old:=$old$WHERE cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C"))$old$;
 new:=$new$WHERE NOT EXISTS (
  SELECT 1 FROM private.conversation_meal_continuation_heads h
  WHERE h.user_id=p_user_id AND h.parent_command_id=coalesce(x.thread_id,
    (SELECT i.reserved_child_id FROM private.conversation_intake_ids i
     WHERE i.user_id=p_user_id AND i.intake_id=x.intake_id))
   AND (h.question->>'kind'='food_name' OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(h.answers) a WHERE a#>>'{answer,kind}'='food_name')))
 AND (cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C")))$new$;
 IF cardinality(string_to_array(body,old))<>2 THEN RAISE EXCEPTION 'unified_name_reader_filter'; END IF;
 EXECUTE replace(body,old,new);
END $compat$;
REVOKE ALL ON FUNCTION public.read_conversation_journal_page_v4(uuid,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_journal_page_v4(uuid,uuid,integer,jsonb) TO service_role;
COMMIT;

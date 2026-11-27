-- Keep a linked answer's real arrival clock distinct from its original meal
-- date. The owned parent source still supplies the meal date and targets.
BEGIN;
SET LOCAL lock_timeout='5s';

DO $migration$
DECLARE
  original_def text:=pg_get_functiondef(
    'private.conversation_continuation_original_current_at(uuid,jsonb,timestamptz)'::regprocedure);
  admit_def text:=pg_get_functiondef(
    'public.admit_conversation_meal_reply(uuid,uuid,uuid,text,text,uuid,jsonb)'::regprocedure);
  original_day constant text:=$old$(original#>>'{day,date}')::date$old$;
  original_clock constant text:=$new$coalesce(original#>>'{clinical,date}',original#>>'{day,date}')::date$new$;
  admit_day constant text:=$old$(authority#>>'{day,date}')::date$old$;
  admit_clock constant text:=$new$coalesce(authority#>>'{clinical,date}',authority#>>'{day,date}')::date$new$;
BEGIN
  IF length(original_def)-length(replace(original_def,original_day,''))<>length(original_day)
    OR length(admit_def)-length(replace(admit_def,admit_day,''))<>length(admit_day) THEN
    RAISE EXCEPTION 'unexpected_earlier_meal_reply_clock_definition';
  END IF;
  EXECUTE replace(original_def,original_day,original_clock);
  EXECUTE replace(admit_def,admit_day,admit_clock);
END $migration$;

COMMIT;

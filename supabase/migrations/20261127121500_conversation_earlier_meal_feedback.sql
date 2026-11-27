-- Bind feedback to the original historical registration. The current clinical
-- view remains current and cannot supply historical targets or percentages.
BEGIN;
SET LOCAL lock_timeout='5s';

DO $migration$
DECLARE
  body text:=pg_get_functiondef(
    'private.registration_feedback_v3_meal_command(private.conversation_meal_effects)'::regprocedure);
  original constant text:=$old$ IF e.receipt->>'schema'='conversation.meal-effect.v1' THEN
  IF c.command_protocol<>'conversation.command.v1' OR c.kind<>'meal.report' THEN RETURN NULL;END IF;$old$;
  replacement constant text:=$new$ IF e.receipt->>'schema' IN('conversation.meal-effect.v1','conversation.meal-effect.v2') THEN
  IF c.command_protocol<>'conversation.command.v1' OR c.kind<>'meal.report' THEN RETURN NULL;END IF;
  IF e.receipt->>'schema'='conversation.meal-effect.v2'
    AND private.conversation_thread_effect_v2(e,c,NULL) IS DISTINCT FROM e.receipt THEN RETURN NULL;END IF;$new$;
BEGIN
  IF length(body)-length(replace(body,original,''))<>length(original) THEN
    RAISE EXCEPTION 'unexpected_historical_meal_feedback_definition';
  END IF;
  EXECUTE replace(body,original,replacement);
END $migration$;

COMMIT;

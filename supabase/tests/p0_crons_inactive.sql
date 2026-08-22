BEGIN;

DO $test$
DECLARE
  v_active_count integer;
BEGIN
  SELECT count(*)::integer
  INTO v_active_count
  FROM cron.job
  WHERE active;

  IF v_active_count <> 0 THEN
    RAISE EXCEPTION 'staging has % active cron jobs', v_active_count;
  END IF;
END;
$test$;

ROLLBACK;

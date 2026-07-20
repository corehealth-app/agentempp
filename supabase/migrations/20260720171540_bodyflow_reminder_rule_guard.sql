CREATE OR REPLACE FUNCTION private.normalize_and_validate_reminder_rule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  SELECT array_agg(day ORDER BY day)::smallint[]
  INTO NEW.weekdays
  FROM (
    SELECT DISTINCT unnest(NEW.weekdays) AS day
  ) AS canonical_days;

  IF NEW.active AND NEW.category IN ('supplement', 'medication') THEN
    PERFORM 1
    FROM public.routine_items
    WHERE id = NEW.routine_item_id
      AND user_id = NEW.user_id
      AND item_type = NEW.category
      AND active
    FOR KEY SHARE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'active reminder requires an active matching routine item'
        USING ERRCODE = '23514',
              CONSTRAINT = 'reminder_rules_active_item_check';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

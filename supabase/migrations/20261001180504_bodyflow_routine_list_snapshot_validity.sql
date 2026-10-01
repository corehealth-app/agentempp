-- Mobile read model must honor the same immutable occurrence interval as the
-- writer. Keep configured schedules visible; pre-creation/invalid occurrences
-- are null. No data rewrite, clock override, privilege or write guard change.
CREATE OR REPLACE FUNCTION public.list_mobile_routine_items(
  p_user_id uuid,
  p_item_type text,
  p_include_archived boolean DEFAULT false,
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_timezone text;
  v_local_date date;
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_item_type IS NULL
    OR p_item_type NOT IN ('supplement', 'medication')
    OR p_include_archived IS NULL
    OR p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_routine_list_request' USING ERRCODE = '22023';
  END IF;

  v_timezone := private.routine_user_timezone(p_user_id);
  v_local_date := timezone(v_timezone, p_now)::date;

  WITH item_rows AS (
    SELECT item.*
    FROM public.routine_items item
    WHERE item.user_id = p_user_id
      AND item.item_type = p_item_type
      AND (
        p_include_archived
        OR (item.active AND item.archived_at IS NULL)
      )
  ),
  rule_rows AS (
    SELECT
      rule.id,
      rule.routine_item_id,
      rule.local_time,
      rule.weekdays,
      CASE
        WHEN extract(dow FROM v_local_date)::smallint = ANY(rule.weekdays)
          THEN v_local_date + rule.local_time
        ELSE NULL
      END AS local_scheduled_at
    FROM public.reminder_rules rule
    JOIN item_rows item ON item.id = rule.routine_item_id
    WHERE rule.user_id = p_user_id
      AND rule.category = p_item_type
      AND rule.active
  ),
  occurrence_rows AS (
    SELECT
      rule.*,
      CASE
        WHEN rule.local_scheduled_at IS NOT NULL
          THEN rule.local_scheduled_at AT TIME ZONE v_timezone
        ELSE NULL
      END AS candidate_scheduled_for
    FROM rule_rows rule
  ),
  canonical_occurrences AS (
    SELECT
      occurrence.*,
      CASE
        WHEN occurrence.candidate_scheduled_for IS NOT NULL
          AND timezone(v_timezone, occurrence.candidate_scheduled_for)
            = occurrence.local_scheduled_at
          THEN CASE WHEN private.resolve_routine_occurrence_snapshot_id(
            p_user_id,
            occurrence.routine_item_id,
            p_item_type,
            occurrence.id,
            private.derive_routine_occurrence_key(
              occurrence.id,
              occurrence.candidate_scheduled_for
            ),
            occurrence.candidate_scheduled_for,
            NULL
          ) IS NOT NULL
            THEN occurrence.candidate_scheduled_for
            ELSE NULL
          END
        ELSE NULL
      END AS scheduled_for
    FROM occurrence_rows occurrence
  ),
  schedule_rows AS (
    SELECT
      occurrence.id,
      occurrence.routine_item_id,
      occurrence.local_time,
      occurrence.weekdays,
      occurrence.scheduled_for,
      private.derive_routine_occurrence_key(
        occurrence.id,
        occurrence.scheduled_for
      ) AS occurrence_key
    FROM canonical_occurrences occurrence
  ),
  schedule_states AS (
    SELECT
      schedule.*,
      CASE
        WHEN schedule.occurrence_key IS NULL THEN NULL
        ELSE private.derive_routine_occurrence_state(
          p_user_id,
          schedule.routine_item_id,
          p_item_type,
          schedule.occurrence_key,
          schedule.scheduled_for,
          p_now
        )
      END AS occurrence_state
    FROM schedule_rows schedule
  )
  SELECT jsonb_build_object(
    'local_date', v_local_date,
    'items', COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', item.id,
          'item_type', item.item_type,
          'name', item.name,
          'dose_text', item.dose_text,
          'origin', item.origin,
          'reminders_enabled', item.reminders_enabled,
          'active', item.active,
          'archived_at', item.archived_at,
          'version', item.version,
          'created_at', item.created_at,
          'updated_at', item.updated_at,
          'schedules', COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'id', schedule.id,
                  'local_time', to_char(schedule.local_time, 'HH24:MI'),
                  'weekdays', to_jsonb(schedule.weekdays),
                  'occurrence', CASE
                    WHEN schedule.occurrence_key IS NULL THEN NULL
                    ELSE jsonb_build_object(
                      'occurrence_key', schedule.occurrence_key,
                      'scheduled_for', schedule.scheduled_for
                    ) || schedule.occurrence_state
                  END
                )
                ORDER BY schedule.local_time, schedule.weekdays, schedule.id
              )
              FROM schedule_states schedule
              WHERE schedule.routine_item_id = item.id
            ),
            '[]'::jsonb
          )
        )
        ORDER BY item.updated_at DESC, item.id DESC
      ),
      '[]'::jsonb
    )
  )
  INTO v_result
  FROM item_rows item;

  RETURN v_result;
END;
$$;

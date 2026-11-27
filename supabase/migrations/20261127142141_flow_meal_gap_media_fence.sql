BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.flow_meal_gap_blocked(
  p_user_id uuid, p_date date, p_timezone text, p_now timestamptz
)
RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.daily_snapshots s
    WHERE s.user_id = p_user_id AND s.date = p_date AND s.day_closed
  ) OR EXISTS (
    SELECT 1 FROM private.conversation_intake_ids i
    JOIN private.conversation_intake_inputs x USING (user_id, intake_id)
    LEFT JOIN private.conversation_intake_routing_results r USING (user_id, intake_id)
    WHERE i.user_id = p_user_id AND i.invalidated_at IS NULL
      AND i.admitted_at >= p_now - interval '30 minutes'
      AND i.admitted_at <= p_now
      AND coalesce(x.admitted_local_date, (i.admitted_at AT TIME ZONE p_timezone)::date) = p_date
      AND (
        r.decision IS NULL OR (
          r.decision->>'kind' = 'meal.report'
          AND NOT EXISTS (
            SELECT 1 FROM private.conversation_meal_effects e
            WHERE e.user_id = i.user_id AND e.command_id = i.reserved_child_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM private.conversation_meal_decisions d
            WHERE d.user_id = i.user_id AND d.command_id = i.reserved_child_id
          )
        )
      )
  ) OR EXISTS (
    SELECT 1 FROM private.conversation_media_assets_v2 a
    WHERE a.user_id = p_user_id
      AND a.deleted_at IS NULL
      AND a.retention_until > p_now
      AND (a.uploaded_at AT TIME ZONE p_timezone)::date = p_date
      AND a.uploaded_at <= p_now
      AND (
        (a.status = 'processing' AND a.updated_at BETWEEN p_now - interval '30 minutes' AND p_now)
        OR (
          a.status = 'uploaded'
          AND EXISTS (
            SELECT 1 FROM private.conversation_media_processing_jobs_v2 j
            WHERE j.asset_id = a.id AND j.user_id = a.user_id
              AND j.state IN ('waiting','queued','running')
              AND j.created_at BETWEEN p_now - interval '30 minutes' AND p_now
          )
        )
        OR (
          -- The app submits its intake just after receiving the media result.
          a.status = 'processed'
          AND a.processed_at BETWEEN p_now - interval '2 minutes' AND p_now
          AND NOT EXISTS (
            SELECT 1 FROM private.conversation_private_media_intakes_v2 x
            WHERE x.asset_id = a.id AND x.user_id = a.user_id
          )
        )
      )
  );
$$;

COMMIT;

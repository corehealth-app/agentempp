CREATE OR REPLACE FUNCTION public.update_notification_preferences_atomic(
  p_user_id uuid,
  p_patch jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_preferences record;
  v_quiet_start time;
  v_quiet_end time;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_patch IS NULL
    OR jsonb_typeof(p_patch) <> 'object'
    OR p_patch = '{}'::jsonb
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_patch) AS field(key)
      WHERE field.key NOT IN (
        'push_enabled',
        'quiet_hours',
        'daily_push_limit',
        'hydration_target_ml'
      )
    ) THEN
    RAISE EXCEPTION 'invalid notification preferences patch' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = p_user_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'active notification preferences user is required' USING ERRCODE = '22023';
  END IF;

  IF p_patch ? 'push_enabled'
    AND jsonb_typeof(p_patch -> 'push_enabled') <> 'boolean' THEN
    RAISE EXCEPTION 'push_enabled must be boolean' USING ERRCODE = '22023';
  END IF;

  IF p_patch ? 'daily_push_limit'
    AND jsonb_typeof(p_patch -> 'daily_push_limit') <> 'number' THEN
    RAISE EXCEPTION 'daily_push_limit must be an integer' USING ERRCODE = '22023';
  END IF;

  IF p_patch ? 'hydration_target_ml'
    AND jsonb_typeof(p_patch -> 'hydration_target_ml') NOT IN ('number', 'null') THEN
    RAISE EXCEPTION 'hydration_target_ml must be an integer or null' USING ERRCODE = '22023';
  END IF;

  IF p_patch ? 'quiet_hours' THEN
    IF jsonb_typeof(p_patch -> 'quiet_hours') = 'null' THEN
      v_quiet_start := NULL;
      v_quiet_end := NULL;
    ELSIF jsonb_typeof(p_patch -> 'quiet_hours') = 'object'
      AND (p_patch -> 'quiet_hours') ?& ARRAY['start', 'end']
      AND (
        SELECT count(*)
        FROM jsonb_object_keys(p_patch -> 'quiet_hours') AS quiet_field(key)
      ) = 2 THEN
      v_quiet_start := (p_patch #>> '{quiet_hours,start}')::time;
      v_quiet_end := (p_patch #>> '{quiet_hours,end}')::time;
    ELSE
      RAISE EXCEPTION 'quiet_hours must contain only start and end or be null'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.notification_preferences (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT *
  INTO v_preferences
  FROM public.notification_preferences
  WHERE user_id = p_user_id
  FOR UPDATE;

  UPDATE public.notification_preferences
  SET push_enabled = CASE
        WHEN p_patch ? 'push_enabled' THEN (p_patch ->> 'push_enabled')::boolean
        ELSE v_preferences.push_enabled
      END,
      quiet_hours_start = CASE
        WHEN p_patch ? 'quiet_hours' THEN v_quiet_start
        ELSE v_preferences.quiet_hours_start
      END,
      quiet_hours_end = CASE
        WHEN p_patch ? 'quiet_hours' THEN v_quiet_end
        ELSE v_preferences.quiet_hours_end
      END,
      daily_push_limit = CASE
        WHEN p_patch ? 'daily_push_limit' THEN (p_patch ->> 'daily_push_limit')::integer
        ELSE v_preferences.daily_push_limit
      END,
      hydration_target_ml = CASE
        WHEN p_patch ? 'hydration_target_ml'
          AND jsonb_typeof(p_patch -> 'hydration_target_ml') = 'null' THEN NULL
        WHEN p_patch ? 'hydration_target_ml' THEN (p_patch ->> 'hydration_target_ml')::integer
        ELSE v_preferences.hydration_target_ml
      END,
      updated_at = clock_timestamp()
  WHERE user_id = p_user_id
  RETURNING * INTO v_preferences;

  RETURN jsonb_build_object(
    'user_id', v_preferences.user_id,
    'push_enabled', v_preferences.push_enabled,
    'quiet_hours_start', v_preferences.quiet_hours_start,
    'quiet_hours_end', v_preferences.quiet_hours_end,
    'daily_push_limit', v_preferences.daily_push_limit,
    'hydration_target_ml', v_preferences.hydration_target_ml,
    'created_at', v_preferences.created_at,
    'updated_at', v_preferences.updated_at
  );
END;
$$;

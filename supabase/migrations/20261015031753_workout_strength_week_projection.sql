-- Dormant read model. Complete owned history must prove its calendar first.
DO $preflight$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='get_confirmed_workouts_for_strength_week') THEN
    RAISE EXCEPTION 'workout_strength_week_projection_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
  IF pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('public.workout_logs') IS NULL
    OR pg_catalog.to_regclass('public.daily_snapshots') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_facts') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_calendar_scopes') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_week_projection_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
END $preflight$;

CREATE FUNCTION public.get_confirmed_workouts_for_strength_week(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_scope_key uuid,
  p_time_zone text,p_week_start_date date,p_as_of_local_date date
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $project$
DECLARE projection jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_expected_lifecycle_key IS NULL OR p_scope_key IS NULL
    OR p_time_zone IS NULL OR p_week_start_date IS NULL OR p_as_of_local_date IS NULL THEN
    RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
  END IF;

  -- This entire statement gets one fresh snapshot after the common fence.
  WITH authenticated_scope AS MATERIALIZED (
    SELECT 1 FROM private.workout_strength_calendar_scopes c
    JOIN private.workout_strength_lifecycles l
      ON l.user_id=c.user_id AND l.lifecycle_key=c.lifecycle_key AND l.closed_at IS NULL
    WHERE c.user_id=p_user_id AND c.lifecycle_key=p_expected_lifecycle_key AND c.scope_key=p_scope_key
      AND c.time_zone=(p_time_zone COLLATE "C")
      AND c.week_start_date=p_week_start_date AND c.as_of_local_date=p_as_of_local_date
  ), owned_workouts AS MATERIALIZED (
    SELECT w.user_id,w.id,f.local_date,f.classification_status,f.catalogue_category,f.answer,
      ((w.snapshot_id IS NOT NULL AND s.id IS NULL)
        OR (f.workout_log_id IS NOT NULL AND (
          f.snapshot_id IS DISTINCT FROM w.snapshot_id OR f.snapshot_date IS DISTINCT FROM s.date
          OR (f.stored_workout_type COLLATE "C") IS DISTINCT FROM (w.workout_type COLLATE "C")
          OR f.performed_at IS DISTINCT FROM w.performed_at
        ))) AS identity_bad,
      (f.workout_log_id IS NULL OR f.lifecycle_key IS DISTINCT FROM p_expected_lifecycle_key
        OR f.calendar_status IS DISTINCT FROM 'proven'
        OR f.zone_source IS DISTINCT FROM 'official_owner_zone_at_recording'
        OR f.zone_observed_at IS NULL OR f.local_date IS DISTINCT FROM s.date
        OR (f.time_zone COLLATE "C") IS DISTINCT FROM (p_time_zone COLLATE "C")) AS calendar_bad
    FROM public.workout_logs w
    LEFT JOIN private.workout_strength_facts f ON f.user_id=w.user_id AND f.workout_log_id=w.id
    LEFT JOIN public.daily_snapshots s ON s.user_id=w.user_id AND s.id=w.snapshot_id
    WHERE w.user_id=p_user_id
  ), proof AS (
    SELECT pg_catalog.bool_or(o.identity_bad) AS identity_bad,
      pg_catalog.bool_or(o.calendar_bad) AS calendar_bad,
      pg_catalog.bool_or(o.classification_status='unavailable'
        AND o.local_date BETWEEN p_week_start_date AND p_as_of_local_date) AS provenance_gap,
      pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'ownerKey',o.user_id,'workoutKey',o.id,
        'localDate',pg_catalog.to_char(o.local_date::timestamp,'YYYY-MM-DD'),'state','confirmed',
        'catalogueCategory',CASE WHEN o.classification_status='matched' THEN o.catalogue_category ELSE NULL END,
        'storedStrengthAnswer',CASE WHEN o.classification_status='unrecognized' AND o.answer IS NOT NULL
          THEN pg_catalog.jsonb_build_object('ownerKey',o.user_id,'workoutKey',o.id,'answer',o.answer)
          ELSE NULL END
      ) ORDER BY o.local_date,o.id) FILTER (
        WHERE o.local_date BETWEEN p_week_start_date AND p_as_of_local_date
          AND o.classification_status IN ('matched','unrecognized')
      ) AS workouts
    FROM owned_workouts o
  )
  SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM authenticated_scope)
      THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved','workouts',NULL)
    WHEN COALESCE(p.identity_bad,false)
      THEN pg_catalog.jsonb_build_object('status','unavailable','reason','identity_unproved','workouts',NULL)
    WHEN COALESCE(p.calendar_bad,false)
      THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved','workouts',NULL)
    WHEN COALESCE(p.provenance_gap,false)
      THEN pg_catalog.jsonb_build_object('status','unavailable','reason','provenance_gap','workouts',NULL)
    ELSE pg_catalog.jsonb_build_object('status','available','workouts',COALESCE(p.workouts,'[]'::jsonb))
  END INTO projection FROM proof p;
  RETURN projection;
END;
$project$;
REVOKE ALL ON FUNCTION public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)
  TO service_role;
DO $privileges$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
    WHERE p.oid='public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)'::regprocedure
      AND a.grantee NOT IN(p.proowner,'service_role'::regrole::oid)) THEN
    RAISE EXCEPTION 'workout_strength_week_projection_unexpected_privileges' USING ERRCODE='42501';
  END IF;
END $privileges$;
COMMENT ON FUNCTION public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date) IS
  'Backend-only snapshot of confirmed owned workouts with complete persisted calendar proof; no formula or caller activation.';

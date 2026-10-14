-- Dormant facts and read resolver. Capture/answer/reset writers are separate.
-- Unknown existing objects fail closed; existing APIs and grants are preserved.
DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('public.workout_logs') IS NULL
    OR pg_catalog.to_regclass('public.daily_snapshots') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_operations') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_facts_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF pg_catalog.to_regclass('private.workout_strength_facts') IS NOT NULL
    OR pg_catalog.to_regclass('public.daily_snapshots_user_id_id_key') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE (n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
        OR (n.nspname='public' AND p.proname='resolve_confirmed_workout_strength_capture')) THEN
    RAISE EXCEPTION 'workout_strength_facts_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE UNIQUE INDEX daily_snapshots_user_id_id_key ON public.daily_snapshots(user_id,id);

CREATE TABLE private.workout_strength_facts (
  user_id uuid NOT NULL,
  workout_log_id uuid NOT NULL,
  lifecycle_key uuid NOT NULL,
  snapshot_id uuid NOT NULL,
  stored_workout_type text COLLATE "C" NOT NULL,
  performed_at timestamptz NOT NULL,
  snapshot_date date NOT NULL,
  classification_status text COLLATE "C" NOT NULL,
  classification_reason text COLLATE "C",
  observation_key uuid,
  observed_at timestamptz,
  matcher_version text COLLATE "C",
  active_row_count bigint,
  match_method text COLLATE "C",
  catalogue_id uuid,
  catalogue_slug text COLLATE "C",
  catalogue_display_name text,
  catalogue_category text COLLATE "C",
  catalogue_updated_at timestamptz,
  calendar_status text COLLATE "C" NOT NULL,
  calendar_reason text COLLATE "C",
  local_date date,
  time_zone text,
  zone_source text COLLATE "C",
  zone_observed_at timestamptz,
  question_key uuid,
  answer text COLLATE "C",
  answer_operation_key text COLLATE "C",
  answer_accepted_at timestamptz,
  revision integer NOT NULL,
  PRIMARY KEY(user_id,workout_log_id),
  UNIQUE(user_id,lifecycle_key,workout_log_id),
  CONSTRAINT workout_strength_facts_life_fk FOREIGN KEY(user_id,lifecycle_key)
    REFERENCES private.workout_strength_lifecycles(user_id,lifecycle_key) ON DELETE CASCADE,
  CONSTRAINT workout_strength_facts_workout_fk FOREIGN KEY(user_id,workout_log_id)
    REFERENCES public.workout_logs(user_id,id) ON DELETE CASCADE,
  CONSTRAINT workout_strength_facts_snapshot_fk FOREIGN KEY(user_id,snapshot_id)
    REFERENCES public.daily_snapshots(user_id,id) ON DELETE CASCADE,
  -- Finite, representable values are required by the UTC-US6/civil-date wire.
  -- These checks do not look up a current zone or recreate historical evidence.
  CONSTRAINT workout_strength_facts_representation_check CHECK ((
    pg_catalog.btrim(stored_workout_type)<>''
    AND pg_catalog.isfinite(performed_at)
    AND pg_catalog.date_part('year',performed_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999
    AND snapshot_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    AND (observed_at IS NULL OR (pg_catalog.isfinite(observed_at)
      AND pg_catalog.date_part('year',observed_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999))
    AND (catalogue_updated_at IS NULL OR (pg_catalog.isfinite(catalogue_updated_at)
      AND pg_catalog.date_part('year',catalogue_updated_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999))
    AND (local_date IS NULL OR local_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-31')
    AND (zone_observed_at IS NULL OR (pg_catalog.isfinite(zone_observed_at)
      AND pg_catalog.date_part('year',zone_observed_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999))
    AND (answer_accepted_at IS NULL OR (pg_catalog.isfinite(answer_accepted_at)
      AND pg_catalog.date_part('year',answer_accepted_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999))
  ) IS TRUE),
  CONSTRAINT workout_strength_facts_classification_check CHECK ((
    (classification_status='matched' AND classification_reason IS NULL
      AND observation_key IS NOT NULL AND observed_at IS NOT NULL
      AND matcher_version='active_slug_then_unique_canonical_display_v1'
      AND active_row_count>=1 AND match_method IN ('active_slug','unique_active_display')
      AND catalogue_id IS NOT NULL AND catalogue_slug IS NOT NULL AND catalogue_slug<>'outro'
      AND catalogue_display_name IS NOT NULL
      AND catalogue_category IN ('musculacao','cardio','esporte','mobilidade')
      AND catalogue_updated_at IS NOT NULL
      AND question_key IS NULL AND answer IS NULL AND answer_operation_key IS NULL
      AND answer_accepted_at IS NULL AND revision=0)
    OR (classification_status='unrecognized'
      AND classification_reason IN ('no_active_match','ambiguous_active_name','generic_outro')
      AND observation_key IS NOT NULL AND observed_at IS NOT NULL
      AND matcher_version='active_slug_then_unique_canonical_display_v1' AND active_row_count>=0
      AND match_method IS NULL AND catalogue_id IS NULL AND catalogue_slug IS NULL
      AND catalogue_display_name IS NULL AND catalogue_category IS NULL AND catalogue_updated_at IS NULL
      AND question_key IS NOT NULL
      AND ((revision=0 AND answer IS NULL AND answer_operation_key IS NULL AND answer_accepted_at IS NULL)
        OR (revision=1 AND answer IN ('yes','no') AND answer_operation_key IS NOT NULL
          AND answer_operation_key<>'' AND answer_accepted_at IS NOT NULL)))
    OR (classification_status='unavailable'
      AND classification_reason IN ('catalogue_read_error','catalogue_invalid','catalogue_incomplete','legacy_provenance_gap')
      AND observation_key IS NULL AND observed_at IS NULL AND matcher_version IS NULL AND active_row_count IS NULL
      AND match_method IS NULL AND catalogue_id IS NULL AND catalogue_slug IS NULL
      AND catalogue_display_name IS NULL AND catalogue_category IS NULL AND catalogue_updated_at IS NULL
      AND question_key IS NULL AND answer IS NULL AND answer_operation_key IS NULL
      AND answer_accepted_at IS NULL AND revision=0)
  ) IS TRUE),
  CONSTRAINT workout_strength_facts_calendar_check CHECK ((
    (calendar_status='proven' AND calendar_reason IS NULL AND local_date IS NOT NULL
      AND local_date=snapshot_date AND time_zone IS NOT NULL AND time_zone<>''
      AND zone_source='official_owner_zone_at_recording' AND zone_observed_at IS NOT NULL)
    OR (calendar_status='unavailable'
      AND calendar_reason IN ('zone_unproved','calendar_conflict','legacy_calendar_gap')
      AND local_date IS NULL AND time_zone IS NULL AND zone_source IS NULL AND zone_observed_at IS NULL)
  ) IS TRUE)
);

CREATE UNIQUE INDEX workout_strength_facts_question_key
  ON private.workout_strength_facts(user_id,question_key) WHERE question_key IS NOT NULL;
-- The PK and lifecycle UNIQUE do not cover the snapshot child-FK lookup.
CREATE INDEX workout_strength_facts_snapshot_lookup ON private.workout_strength_facts(user_id,snapshot_id);
ALTER TABLE private.workout_strength_facts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.workout_strength_facts FROM PUBLIC,anon,authenticated,service_role;

-- One owned JOIN checks every copied anchor. No current catalogue/zone read.
-- Future insert code must use this guard in its own atomic transaction too.
CREATE FUNCTION private.workout_strength_fact_snapshot(
  p_user_id uuid,p_lifecycle_key uuid,p_workout_log_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $fact$
  SELECT pg_catalog.jsonb_build_object(
    'anchor',pg_catalog.jsonb_build_object(
      'ownerID',f.user_id::text,'workoutLogID',f.workout_log_id::text,'lifecycleKey',f.lifecycle_key::text,
      'snapshotID',f.snapshot_id::text,'storedWorkoutType',f.stored_workout_type,
      'performedAt',pg_catalog.to_char(f.performed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'snapshotDate',pg_catalog.to_char(f.snapshot_date::timestamp,'YYYY-MM-DD')),
    'classification',CASE f.classification_status
      WHEN 'matched' THEN pg_catalog.jsonb_build_object(
        'status','matched','observation',pg_catalog.jsonb_build_object(
          'observedAt',pg_catalog.to_char(f.observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'matcherVersion',f.matcher_version,'observationKey',f.observation_key::text),
        'method',f.match_method,'catalogue',pg_catalog.jsonb_build_object(
          'id',f.catalogue_id::text,'slug',f.catalogue_slug,'displayName',f.catalogue_display_name,
          'category',f.catalogue_category,'isActive',true,
          'updatedAtLiteral',pg_catalog.to_char(f.catalogue_updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))
      WHEN 'unrecognized' THEN pg_catalog.jsonb_build_object(
        'status','unrecognized','observation',pg_catalog.jsonb_build_object(
          'observedAt',pg_catalog.to_char(f.observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'matcherVersion',f.matcher_version,'observationKey',f.observation_key::text),
        'reason',f.classification_reason)
      ELSE pg_catalog.jsonb_build_object('status','unavailable','reason',f.classification_reason) END,
    'calendar',CASE f.calendar_status WHEN 'proven' THEN pg_catalog.jsonb_build_object(
      'status','proven','performedAt',pg_catalog.to_char(f.performed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'localDate',pg_catalog.to_char(f.local_date::timestamp,'YYYY-MM-DD'),'timeZone',f.time_zone,
      'zoneSource',f.zone_source,
      'zoneObservedAt',pg_catalog.to_char(f.zone_observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'snapshotID',f.snapshot_id::text,'snapshotDate',pg_catalog.to_char(f.snapshot_date::timestamp,'YYYY-MM-DD'))
      ELSE pg_catalog.jsonb_build_object('status','unavailable','reason',f.calendar_reason) END,
    'clarification',CASE WHEN f.classification_status<>'unrecognized'
      THEN pg_catalog.jsonb_build_object('status','not_applicable')
      WHEN f.revision=0 THEN pg_catalog.jsonb_build_object('status','unanswered','questionKey',f.question_key::text)
      ELSE pg_catalog.jsonb_build_object('status','answered','receipt',pg_catalog.jsonb_build_object(
        'ownerID',f.user_id::text,'workoutLogID',f.workout_log_id::text,'questionKey',f.question_key::text,
        'answer',f.answer,'operationKey',f.answer_operation_key,
        'acceptedAt',pg_catalog.to_char(f.answer_accepted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))) END,
    'revision',f.revision)
  FROM private.workout_strength_facts f
  JOIN public.workout_logs w ON w.user_id=f.user_id AND w.id=f.workout_log_id
  JOIN public.daily_snapshots s ON s.user_id=w.user_id AND s.id=w.snapshot_id
  WHERE f.user_id=p_user_id AND f.lifecycle_key=p_lifecycle_key AND f.workout_log_id=p_workout_log_id
    AND f.snapshot_id=w.snapshot_id AND f.snapshot_date=s.date
    AND f.stored_workout_type=(w.workout_type COLLATE "C") AND f.performed_at=w.performed_at;
$fact$;
REVOKE ALL ON FUNCTION private.workout_strength_fact_snapshot(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.resolve_confirmed_workout_strength_capture(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_operation_key text,p_original_operation_type text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $resolve$
DECLARE capture record;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_expected_lifecycle_key IS NULL
    OR p_operation_key IS NULL OR p_operation_key=''
    OR p_original_operation_type IS NULL OR pg_catalog.btrim(p_original_operation_type)='' THEN
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
  PERFORM 1 FROM private.workout_strength_lifecycles l
    WHERE l.user_id=p_user_id AND l.lifecycle_key=p_expected_lifecycle_key AND l.closed_at IS NULL;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle');
  END IF;

  -- Binding, live anchor and fact are read in one statement after the locks.
  SELECT o.operation_key,o.original_operation_type,o.original_workout_log_id,o.live_workout_log_id,
    o.resolution,o.capture_outcome,w.id AS owned_workout,s.id AS owned_snapshot,
    CASE WHEN o.capture_outcome='fact' THEN
      private.workout_strength_fact_snapshot(p_user_id,p_expected_lifecycle_key,o.live_workout_log_id)
      ELSE NULL END AS fact_wire
  INTO capture
  FROM private.workout_strength_operations o
  LEFT JOIN public.workout_logs w ON w.user_id=o.user_id AND w.id=o.live_workout_log_id
  LEFT JOIN public.daily_snapshots s ON s.user_id=w.user_id AND s.id=w.snapshot_id
  WHERE o.user_id=p_user_id AND o.lifecycle_key=p_expected_lifecycle_key AND o.operation_kind='capture'
    AND o.operation_key=(p_operation_key COLLATE "C")
    AND o.original_operation_type=(p_original_operation_type COLLATE "C");
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','operation_key_missing','confirmedWorkoutLogID',NULL);
  END IF;
  IF capture.live_workout_log_id IS NULL OR capture.owned_workout IS NULL OR capture.owned_snapshot IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_workout');
  END IF;
  IF capture.capture_outcome='legacy_provenance_gap' THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','legacy_provenance_gap',
      'confirmedWorkoutLogID',capture.live_workout_log_id::text);
  END IF;
  IF capture.fact_wire IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_workout');
  END IF;
  RETURN pg_catalog.jsonb_build_object('status','reuse_existing','binding',pg_catalog.jsonb_build_object(
    'ownerID',p_user_id::text,'lifecycleKey',p_expected_lifecycle_key::text,'operationKey',capture.operation_key,
    'originalOperationType',capture.original_operation_type,'workoutLogID',capture.live_workout_log_id::text,
    'resolution',capture.resolution),'fact',capture.fact_wire);
END;
$resolve$;
REVOKE ALL ON FUNCTION public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text) TO service_role;
COMMENT ON FUNCTION public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text) IS
  'Backend-only resolution of a stored capture binding against its owned original workout/snapshot; no capture or reclassification.';

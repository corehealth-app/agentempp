-- Dormant command journal. No capture, lifecycle opening, reset or caller.
-- Keep the first committed preparation and DB cutoff for the exact F1 tuple.
DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_commands_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF pg_catalog.to_regclass('private.workout_strength_commands') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='read_or_admit_workout_strength_command') THEN
    RAISE EXCEPTION 'workout_strength_commands_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE TABLE private.workout_strength_commands (
  user_id uuid NOT NULL,
  lifecycle_key uuid NOT NULL,
  operation_key text COLLATE "C" NOT NULL,
  original_operation_type text COLLATE "C" NOT NULL,
  legacy_arguments jsonb NOT NULL,
  admitted_at timestamptz NOT NULL,
  recent_cutoff timestamptz NOT NULL,
  PRIMARY KEY(user_id,lifecycle_key,operation_key,original_operation_type),
  CONSTRAINT workout_strength_commands_life_fk FOREIGN KEY(user_id,lifecycle_key)
    REFERENCES private.workout_strength_lifecycles(user_id,lifecycle_key) ON DELETE CASCADE,
  CONSTRAINT workout_strength_commands_shape_check CHECK ((
    operation_key<>'' AND pg_catalog.btrim(original_operation_type)<>''
    AND pg_catalog.jsonb_typeof(legacy_arguments)='object'
    AND pg_catalog.isfinite(admitted_at) AND pg_catalog.isfinite(recent_cutoff)
    AND pg_catalog.date_part('year',admitted_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999
    AND pg_catalog.date_part('year',recent_cutoff AT TIME ZONE 'UTC') BETWEEN 1 AND 9999
    AND recent_cutoff=admitted_at-interval '6 hours'
  ) IS TRUE)
);
ALTER TABLE private.workout_strength_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.workout_strength_commands FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_or_admit_workout_strength_command(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_operation_key text,
  p_original_operation_type text,p_legacy_arguments jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $admit$
DECLARE
  command private.workout_strength_commands%ROWTYPE;
  field text;
  number_value numeric;
  admitted_clock timestamptz;
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

  SELECT c.* INTO command FROM private.workout_strength_commands c
    WHERE c.user_id=p_user_id AND c.lifecycle_key=p_expected_lifecycle_key
      AND c.operation_key=(p_operation_key COLLATE "C")
      AND c.original_operation_type=(p_original_operation_type COLLATE "C");
  IF NOT FOUND THEN
    IF p_legacy_arguments IS NULL THEN RETURN NULL; END IF;

    -- Validate only a new candidate. A later candidate cannot invalidate or
    -- overwrite the committed winner. Preserve JSONB literals and all nulls.
    IF pg_catalog.jsonb_typeof(p_legacy_arguments)<>'object' THEN
      RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
    END IF;
    IF NOT (p_legacy_arguments ?& ARRAY['p_user_id','p_date','p_workout_type','p_duration_min',
      'p_estimated_kcal','p_intensity','p_notes','p_performed_at','p_provider_message_id',
      'p_calories_target','p_protein_target','p_replace_recent','p_replace_since'])
      OR p_legacy_arguments-ARRAY['p_user_id','p_date','p_workout_type','p_duration_min',
      'p_estimated_kcal','p_intensity','p_notes','p_performed_at','p_provider_message_id',
      'p_calories_target','p_protein_target','p_replace_recent','p_replace_since']<>'{}'::jsonb THEN
      RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['p_user_id','p_date','p_workout_type'] LOOP
      IF pg_catalog.jsonb_typeof(p_legacy_arguments->field)<>'string' THEN
        RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
      END IF;
    END LOOP;
    FOREACH field IN ARRAY ARRAY['p_intensity','p_notes','p_performed_at','p_provider_message_id','p_replace_since'] LOOP
      IF pg_catalog.jsonb_typeof(p_legacy_arguments->field) NOT IN ('string','null') THEN
        RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
      END IF;
    END LOOP;
    IF pg_catalog.jsonb_typeof(p_legacy_arguments->'p_duration_min')<>'number'
      OR pg_catalog.jsonb_typeof(p_legacy_arguments->'p_estimated_kcal')<>'number'
      OR pg_catalog.jsonb_typeof(p_legacy_arguments->'p_calories_target') NOT IN ('number','null')
      OR pg_catalog.jsonb_typeof(p_legacy_arguments->'p_protein_target') NOT IN ('number','null')
      OR pg_catalog.jsonb_typeof(p_legacy_arguments->'p_replace_recent') NOT IN ('boolean','null') THEN
      RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
    END IF;

    -- Cast validation is local to this block. Do not catch lock/insert/ACL
    -- failures as malformed input, or turn mandatory writes into unavailable.
    BEGIN
      IF (p_legacy_arguments->>'p_user_id')::uuid<>p_user_id
        OR ((p_legacy_arguments->>'p_workout_type') COLLATE "C")<>(p_original_operation_type COLLATE "C")
        OR pg_catalog.length(p_original_operation_type)>200 THEN
        RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
      END IF;
      PERFORM (p_legacy_arguments->>'p_date')::date;
      PERFORM (p_legacy_arguments->>'p_performed_at')::timestamptz;
      PERFORM (p_legacy_arguments->>'p_replace_since')::timestamptz;
      FOREACH field IN ARRAY ARRAY['p_duration_min','p_estimated_kcal','p_calories_target'] LOOP
        IF pg_catalog.jsonb_typeof(p_legacy_arguments->field)='number' THEN
          number_value:=(p_legacy_arguments->>field)::numeric;
          IF number_value<>pg_catalog.trunc(number_value) OR number_value NOT BETWEEN -2147483648 AND 2147483647 THEN
            RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
          END IF;
        END IF;
      END LOOP;
      IF (p_legacy_arguments->>'p_duration_min')::numeric NOT BETWEEN 1 AND 1440
        OR (p_legacy_arguments->>'p_estimated_kcal')::numeric NOT BETWEEN 0 AND 10000
        OR ((p_legacy_arguments->>'p_replace_recent')::boolean
          AND p_legacy_arguments->'p_replace_since'='null'::jsonb) THEN
        RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
      END IF;
    EXCEPTION WHEN data_exception THEN
      RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
    END;

    admitted_clock:=pg_catalog.clock_timestamp();
    INSERT INTO private.workout_strength_commands(user_id,lifecycle_key,operation_key,
      original_operation_type,legacy_arguments,admitted_at,recent_cutoff)
    VALUES(p_user_id,p_expected_lifecycle_key,p_operation_key,p_original_operation_type,
      p_legacy_arguments,admitted_clock,admitted_clock-interval '6 hours')
    ON CONFLICT(user_id,lifecycle_key,operation_key,original_operation_type) DO NOTHING;
    -- Fresh READ COMMITTED statement also resolves an external concurrent
    -- winner. The public path itself serializes on the common workout lock.
    SELECT c.* INTO STRICT command FROM private.workout_strength_commands c
      WHERE c.user_id=p_user_id AND c.lifecycle_key=p_expected_lifecycle_key
        AND c.operation_key=(p_operation_key COLLATE "C")
        AND c.original_operation_type=(p_original_operation_type COLLATE "C");
  END IF;
  RETURN pg_catalog.jsonb_build_object('ownerID',command.user_id::text,
    'lifecycleKey',command.lifecycle_key::text,'operationKey',command.operation_key,
    'originalOperationType',command.original_operation_type,'legacyArguments',command.legacy_arguments,
    'admittedAt',pg_catalog.to_char(command.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'recentCutoff',pg_catalog.to_char(command.recent_cutoff AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
END;
$admit$;
REVOKE ALL ON FUNCTION public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb) TO service_role;
COMMENT ON FUNCTION public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb) IS
  'Backend-only first committed workout preparation and stable DB cutoff; no capture or lifecycle opening.';

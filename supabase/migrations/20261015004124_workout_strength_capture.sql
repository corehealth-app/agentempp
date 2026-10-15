-- Dormant backend capture. The original 13-argument writer is unchanged.
-- Read frozen JSONB arguments in SQL; never round-trip numeric/nulls through JS.
DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.workout_types') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_commands') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_facts') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_operations') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR pg_catalog.to_regprocedure('private.workout_strength_fact_snapshot(uuid,uuid,uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.get_workout_strength_catalogue_context()') IS NULL
    OR pg_catalog.to_regprocedure('public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)') IS NULL
    OR pg_catalog.to_regprocedure('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_capture_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='register_workout_strength_atomic') THEN
    RAISE EXCEPTION 'workout_strength_capture_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE FUNCTION public.register_workout_strength_atomic(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_operation_key text,
  p_original_operation_type text,p_catalogue_observation jsonb,p_catalogue_decision jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $capture$
DECLARE
  invalid_authority CONSTANT jsonb :=
    '{"legacy_result":null,"strength":{"status":"forbidden","reason":"invalid_authority"}}'::jsonb;
  stale_workout CONSTANT jsonb :=
    '{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_workout"}}'::jsonb;
  command private.workout_strength_commands%ROWTYPE;
  operation private.workout_strength_operations%ROWTYPE;
  workout public.workout_logs%ROWTYPE;
  selected public.workout_types%ROWTYPE;
  args jsonb;
  legacy_result jsonb;
  strength jsonb;
  current_catalogue jsonb;
  row_wire jsonb;
  fact_wire jsonb;
  provider text;
  prepared_duration integer;
  provider_ids uuid[];
  workout_id uuid;
  previous_id uuid;
  row_id uuid;
  selected_id uuid;
  seen_slugs text[]:=ARRAY[]::text[];
  value_instant timestamptz;
  observation_key uuid;
  observed_at timestamptz;
  class_status text;
  class_reason text;
  match_method text;
  row_count bigint;
  resolution text;
  outcome text;
  owner_zone text;
  snapshot_date date;
  local_date date;
  calendar_status text;
  calendar_reason text;
  recorded_at timestamptz;
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
  -- Catalogue first, including replay. Never acquire SHARE after the advisory.
  LOCK TABLE public.workout_types IN SHARE MODE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  SELECT u.timezone INTO owner_zone FROM public.users u
    WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
  END IF;
  PERFORM 1 FROM private.workout_strength_lifecycles l
    WHERE l.user_id=p_user_id AND l.lifecycle_key=p_expected_lifecycle_key AND l.closed_at IS NULL;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('legacy_result',NULL,
      'strength',pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle'));
  END IF;

  -- Resolve an existing F1 before any new journal/envelope/catalogue decision.
  SELECT o.* INTO operation FROM private.workout_strength_operations o
    WHERE o.user_id=p_user_id AND o.lifecycle_key=p_expected_lifecycle_key AND o.operation_kind='capture'
      AND o.operation_key=(p_operation_key COLLATE "C")
      AND o.original_operation_type=(p_original_operation_type COLLATE "C");
  IF FOUND THEN
    strength:=public.resolve_confirmed_workout_strength_capture(
      p_user_id,p_expected_lifecycle_key,p_operation_key,p_original_operation_type);
    RETURN pg_catalog.jsonb_build_object('legacy_result',
      CASE WHEN strength->>'status' IN ('forbidden','conflict') THEN NULL ELSE operation.legacy_result END,
      'strength',strength);
  END IF;
  SELECT c.* INTO command FROM private.workout_strength_commands c
    WHERE c.user_id=p_user_id AND c.lifecycle_key=p_expected_lifecycle_key
      AND c.operation_key=(p_operation_key COLLATE "C")
      AND c.original_operation_type=(p_original_operation_type COLLATE "C");
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('legacy_result',NULL,'strength',
      pg_catalog.jsonb_build_object('status','unavailable','reason','operation_key_missing','confirmedWorkoutLogID',NULL));
  END IF;
  args:=command.legacy_arguments;
  -- Admission validated these values. Corrupt storage is an operational error,
  -- never permission to write another owner or to reinterpret the original type.
  IF (args->>'p_user_id')::uuid IS DISTINCT FROM p_user_id
    OR ((args->>'p_workout_type') COLLATE "C") IS DISTINCT FROM (p_original_operation_type COLLATE "C") THEN
    RAISE EXCEPTION 'invalid_workout_strength_stored_command' USING ERRCODE='22023';
  END IF;
  prepared_duration:=(args->>'p_duration_min')::numeric::integer;
  provider:=args->>'p_provider_message_id';

  -- Same legacy priority/raw predicates. Retain the chosen UUID, not a new
  -- oldest/newest policy. Empty provider skips early dedup, just as JS truthiness.
  IF provider IS NOT NULL AND provider<>'' THEN
    SELECT pg_catalog.array_agg(candidate.id) INTO provider_ids FROM (
      SELECT w.id FROM public.workout_logs w WHERE w.user_id=p_user_id
        AND (w.raw_provider_message_id COLLATE "C")=(provider COLLATE "C")
        AND (w.workout_type COLLATE "C")=(p_original_operation_type COLLATE "C") LIMIT 2
    ) candidate;
    IF pg_catalog.cardinality(provider_ids)>1 THEN
      RETURN pg_catalog.jsonb_build_object('legacy_result',NULL,'strength',
        pg_catalog.jsonb_build_object('status','unavailable','reason','identity_unproved','confirmedWorkoutLogID',NULL));
    ELSIF pg_catalog.cardinality(provider_ids)=1 THEN
      workout_id:=provider_ids[1];resolution:='provider_type_dedup';
    END IF;
  END IF;
  IF workout_id IS NULL THEN
    SELECT w.id INTO workout_id FROM public.workout_logs w WHERE w.user_id=p_user_id
      AND (w.workout_type COLLATE "C")=(p_original_operation_type COLLATE "C")
      AND w.duration_min=prepared_duration AND w.created_at>=command.recent_cutoff LIMIT 1;
    IF FOUND THEN resolution:='recent6h_dedup'; END IF;
  END IF;

  IF workout_id IS NULL THEN
    IF pg_catalog.jsonb_typeof(p_catalogue_decision) IS DISTINCT FROM 'object'
      OR pg_catalog.jsonb_typeof(p_catalogue_decision->'status') IS DISTINCT FROM 'string' THEN
      RETURN invalid_authority;
    END IF;
    IF p_catalogue_decision->'status'='"unavailable"'::jsonb THEN
      IF p_catalogue_observation IS NOT NULL
        OR NOT (p_catalogue_decision ?& ARRAY['status','reason'])
        OR p_catalogue_decision-ARRAY['status','reason']<>'{}'::jsonb
        OR (p_catalogue_decision->>'reason' COLLATE "C") NOT IN
          ('catalogue_read_error','catalogue_invalid','catalogue_incomplete')
        OR pg_catalog.jsonb_typeof(p_catalogue_decision->'reason') IS DISTINCT FROM 'string' THEN
        RETURN invalid_authority;
      END IF;
      class_status:='unavailable';class_reason:=p_catalogue_decision->>'reason';
    ELSE
      IF p_catalogue_decision->'status' NOT IN ('"matched"'::jsonb,'"unrecognized"'::jsonb)
        OR pg_catalog.jsonb_typeof(p_catalogue_observation) IS DISTINCT FROM 'object' THEN
        RETURN invalid_authority;
      END IF;
      IF NOT (p_catalogue_observation ?& ARRAY[
          'status','observationKey','observedAt','matcherVersion','complete','rowCount','activeRows'])
        OR p_catalogue_observation-ARRAY[
          'status','observationKey','observedAt','matcherVersion','complete','rowCount','activeRows']<>'{}'::jsonb
        OR p_catalogue_observation->'status' IS DISTINCT FROM '"available"'::jsonb
        OR p_catalogue_observation->'complete' IS DISTINCT FROM 'true'::jsonb
        OR p_catalogue_observation->'matcherVersion' IS DISTINCT FROM '"active_slug_then_unique_canonical_display_v1"'::jsonb
        OR pg_catalog.jsonb_typeof(p_catalogue_observation->'observationKey') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(p_catalogue_observation->'observedAt') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(p_catalogue_observation->'rowCount') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(p_catalogue_observation->'activeRows') IS DISTINCT FROM 'array' THEN
        RETURN invalid_authority;
      END IF;
      IF (p_catalogue_observation->>'observationKey') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR (p_catalogue_observation->>'observedAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$'
        OR (p_catalogue_observation->>'rowCount') !~ '^(0|[1-9][0-9]*)$' THEN
        RETURN invalid_authority;
      END IF;
      -- Only decoding untrusted catalogue literals is caught here. Do not put
      -- locks, the real writer, fact/binding inserts or transport in this block.
      BEGIN
        observation_key:=(p_catalogue_observation->>'observationKey')::uuid;
        observed_at:=(p_catalogue_observation->>'observedAt')::timestamptz;
        IF NOT pg_catalog.isfinite(observed_at)
          OR pg_catalog.to_char(observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
            <>p_catalogue_observation->>'observedAt'
          OR (p_catalogue_observation->>'rowCount')::numeric
            <>pg_catalog.jsonb_array_length(p_catalogue_observation->'activeRows') THEN
          RETURN invalid_authority;
        END IF;
        FOR row_wire IN SELECT value FROM pg_catalog.jsonb_array_elements(p_catalogue_observation->'activeRows') LOOP
          IF pg_catalog.jsonb_typeof(row_wire) IS DISTINCT FROM 'object' THEN RETURN invalid_authority; END IF;
          IF NOT (row_wire ?& ARRAY['id','slug','displayName','category','isActive','updatedAtLiteral'])
            OR row_wire-ARRAY['id','slug','displayName','category','isActive','updatedAtLiteral']<>'{}'::jsonb
            OR pg_catalog.jsonb_typeof(row_wire->'id') IS DISTINCT FROM 'string'
            OR pg_catalog.jsonb_typeof(row_wire->'slug') IS DISTINCT FROM 'string'
            OR pg_catalog.jsonb_typeof(row_wire->'displayName') IS DISTINCT FROM 'string'
            OR pg_catalog.jsonb_typeof(row_wire->'category') IS DISTINCT FROM 'string'
            OR pg_catalog.jsonb_typeof(row_wire->'updatedAtLiteral') IS DISTINCT FROM 'string'
            OR row_wire->'isActive' IS DISTINCT FROM 'true'::jsonb THEN RETURN invalid_authority; END IF;
          IF (row_wire->>'id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            OR (row_wire->>'updatedAtLiteral') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$'
            OR (row_wire->>'category' COLLATE "C") NOT IN ('musculacao','cardio','esporte','mobilidade')
            OR (row_wire->>'slug' COLLATE "C")=ANY(seen_slugs) THEN RETURN invalid_authority; END IF;
          row_id:=(row_wire->>'id')::uuid;
          value_instant:=(row_wire->>'updatedAtLiteral')::timestamptz;
          IF (previous_id IS NOT NULL AND row_id<=previous_id)
            OR NOT pg_catalog.isfinite(value_instant)
            OR pg_catalog.to_char(value_instant AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
              <>row_wire->>'updatedAtLiteral' THEN RETURN invalid_authority; END IF;
          previous_id:=row_id;seen_slugs:=pg_catalog.array_append(seen_slugs,row_wire->>'slug');
        END LOOP;
      EXCEPTION WHEN data_exception THEN
        RETURN invalid_authority;
      END;
      IF NOT (p_catalogue_decision ?& ARRAY['status','observationKey','matcherVersion','originalOperationType'])
        OR p_catalogue_decision->'observationKey' IS DISTINCT FROM p_catalogue_observation->'observationKey'
        OR p_catalogue_decision->'matcherVersion' IS DISTINCT FROM p_catalogue_observation->'matcherVersion'
        OR pg_catalog.jsonb_typeof(p_catalogue_decision->'originalOperationType') IS DISTINCT FROM 'string'
        OR (p_catalogue_decision->>'originalOperationType' COLLATE "C")<>(p_original_operation_type COLLATE "C") THEN
        RETURN invalid_authority;
      END IF;
      IF p_catalogue_decision->'status'='"matched"'::jsonb THEN
        IF NOT (p_catalogue_decision ?& ARRAY['method','selectedRowID'])
          OR p_catalogue_decision-ARRAY[
            'status','observationKey','matcherVersion','originalOperationType','method','selectedRowID']<>'{}'::jsonb
          OR pg_catalog.jsonb_typeof(p_catalogue_decision->'method') IS DISTINCT FROM 'string'
          OR (p_catalogue_decision->>'method' COLLATE "C") NOT IN ('active_slug','unique_active_display')
          OR pg_catalog.jsonb_typeof(p_catalogue_decision->'selectedRowID') IS DISTINCT FROM 'string' THEN
          RETURN invalid_authority;
        END IF;
        IF (p_catalogue_decision->>'selectedRowID') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
          RETURN invalid_authority;
        END IF;
        selected_id:=(p_catalogue_decision->>'selectedRowID')::uuid;
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(p_catalogue_observation->'activeRows') r
          WHERE r.value->>'id'=selected_id::text AND (r.value->>'slug' COLLATE "C")<>'outro') THEN
          RETURN invalid_authority;
        END IF;
        class_status:='matched';match_method:=p_catalogue_decision->>'method';
      ELSE
        IF NOT (p_catalogue_decision ? 'reason')
          OR p_catalogue_decision-ARRAY[
            'status','observationKey','matcherVersion','originalOperationType','reason']<>'{}'::jsonb
          OR pg_catalog.jsonb_typeof(p_catalogue_decision->'reason') IS DISTINCT FROM 'string'
          OR (p_catalogue_decision->>'reason' COLLATE "C") NOT IN
            ('no_active_match','ambiguous_active_name','generic_outro') THEN RETURN invalid_authority; END IF;
        class_status:='unrecognized';class_reason:=p_catalogue_decision->>'reason';
      END IF;
      -- Fresh statement after SHARE: count/order/all six row properties,
      -- including any competitor. New observation key/clock are not CAS values.
      current_catalogue:=public.get_workout_strength_catalogue_context();
      IF current_catalogue->'status' IS DISTINCT FROM '"available"'::jsonb
        OR (current_catalogue-ARRAY['observationKey','observedAt'])
          IS DISTINCT FROM (p_catalogue_observation-ARRAY['observationKey','observedAt']) THEN
        RETURN pg_catalog.jsonb_build_object('legacy_result',NULL,'strength',
          pg_catalog.jsonb_build_object('status','conflict','reason','source_observation_changed'));
      END IF;
      row_count:=(current_catalogue->>'rowCount')::bigint;
      IF class_status='matched' THEN
        SELECT t.* INTO STRICT selected FROM public.workout_types t WHERE t.id=selected_id AND t.is_active=true;
        -- This is a trusted TS decision + full-set CAS, not a SQL Unicode matcher.
      END IF;
    END IF;
    legacy_result:=public.register_workout_atomic(
      p_user_id:=(args->>'p_user_id')::uuid,p_date:=(args->>'p_date')::date,
      p_workout_type:=args->>'p_workout_type',p_duration_min:=prepared_duration,
      p_estimated_kcal:=(args->>'p_estimated_kcal')::numeric::integer,
      p_intensity:=args->>'p_intensity',p_notes:=args->>'p_notes',
      p_performed_at:=(args->>'p_performed_at')::timestamptz,
      p_provider_message_id:=provider,p_calories_target:=(args->>'p_calories_target')::numeric::integer,
      p_protein_target:=(args->>'p_protein_target')::numeric,
      p_replace_recent:=(args->>'p_replace_recent')::boolean,p_replace_since:=(args->>'p_replace_since')::timestamptz);
    IF legacy_result IS NULL
      OR pg_catalog.jsonb_typeof(legacy_result->'inserted') IS DISTINCT FROM 'boolean'
      OR pg_catalog.jsonb_typeof(legacy_result->'workout_log_id') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'workout_strength_registration_identity_unproved' USING ERRCODE='P0002';
    END IF;
    workout_id:=(legacy_result->>'workout_log_id')::uuid;
    resolution:=CASE WHEN legacy_result->'inserted'='true'::jsonb THEN 'sql_insert' ELSE 'sql_replay' END;
  END IF;

  -- The real row owns the anchor. X26's response snapshot may be another day.
  SELECT w.* INTO workout FROM public.workout_logs w WHERE w.user_id=p_user_id AND w.id=workout_id;
  IF FOUND THEN
    SELECT s.date INTO snapshot_date FROM public.daily_snapshots s WHERE s.user_id=p_user_id AND s.id=workout.snapshot_id;
  END IF;
  IF workout.id IS NULL OR snapshot_date IS NULL THEN
    IF legacy_result IS NULL THEN RETURN stale_workout; END IF;
    RAISE EXCEPTION 'workout_strength_registration_identity_unproved' USING ERRCODE='P0002';
  END IF;
  recorded_at:=pg_catalog.clock_timestamp();
  IF resolution='sql_insert' THEN
    calendar_status:='unavailable';calendar_reason:='zone_unproved';
    IF owner_zone IS NOT NULL AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=owner_zone) THEN
      local_date:=(workout.performed_at AT TIME ZONE owner_zone)::date;
      IF local_date=snapshot_date THEN calendar_status:='proven';calendar_reason:=NULL;
      ELSE calendar_reason:='calendar_conflict'; END IF;
    END IF;
    -- A mandatory constraint failure also rolls back the original writer and
    -- correction. Non-representable anchors do not become successful gaps.
    INSERT INTO private.workout_strength_facts(
      user_id,workout_log_id,lifecycle_key,snapshot_id,stored_workout_type,performed_at,snapshot_date,
      classification_status,classification_reason,observation_key,observed_at,matcher_version,active_row_count,
      match_method,catalogue_id,catalogue_slug,catalogue_display_name,catalogue_category,catalogue_updated_at,
      calendar_status,calendar_reason,local_date,time_zone,zone_source,zone_observed_at,
      question_key,answer,answer_operation_key,answer_accepted_at,revision)
    VALUES(p_user_id,workout_id,p_expected_lifecycle_key,workout.snapshot_id,workout.workout_type,workout.performed_at,snapshot_date,
      class_status,class_reason,observation_key,observed_at,
      CASE WHEN class_status<>'unavailable' THEN 'active_slug_then_unique_canonical_display_v1' ELSE NULL END,row_count,
      match_method,selected.id,selected.slug,selected.display_name,selected.category,selected.updated_at,
      calendar_status,calendar_reason,CASE WHEN calendar_status='proven' THEN local_date ELSE NULL END,
      CASE WHEN calendar_status='proven' THEN owner_zone ELSE NULL END,
      CASE WHEN calendar_status='proven' THEN 'official_owner_zone_at_recording' ELSE NULL END,
      CASE WHEN calendar_status='proven' THEN recorded_at ELSE NULL END,
      CASE WHEN class_status='unrecognized' THEN pg_catalog.gen_random_uuid() ELSE NULL END,NULL,NULL,NULL,0);
    fact_wire:=private.workout_strength_fact_snapshot(p_user_id,p_expected_lifecycle_key,workout_id);
    IF fact_wire IS NULL THEN
      RAISE EXCEPTION 'workout_strength_registration_identity_unproved' USING ERRCODE='P0002';
    END IF;
    outcome:='fact';
  ELSE
    fact_wire:=private.workout_strength_fact_snapshot(p_user_id,p_expected_lifecycle_key,workout_id);
    IF fact_wire IS NOT NULL THEN outcome:='fact';
    ELSIF EXISTS (SELECT 1 FROM private.workout_strength_facts f WHERE f.user_id=p_user_id AND f.workout_log_id=workout_id) THEN
      IF legacy_result IS NULL THEN RETURN stale_workout; END IF;
      RAISE EXCEPTION 'workout_strength_registration_identity_unproved' USING ERRCODE='P0002';
    ELSE outcome:='legacy_provenance_gap'; END IF;
  END IF;
  INSERT INTO private.workout_strength_operations(
    user_id,lifecycle_key,operation_kind,operation_key,original_operation_type,original_workout_log_id,
    live_workout_log_id,created_at,resolution,capture_outcome,legacy_result)
  VALUES(p_user_id,p_expected_lifecycle_key,'capture',p_operation_key,p_original_operation_type,workout_id,
    workout_id,recorded_at,resolution,outcome,legacy_result);
  strength:=public.resolve_confirmed_workout_strength_capture(
    p_user_id,p_expected_lifecycle_key,p_operation_key,p_original_operation_type);
  IF (outcome='fact' AND strength->>'status' IS DISTINCT FROM 'reuse_existing')
    OR (outcome='legacy_provenance_gap' AND strength IS DISTINCT FROM
      pg_catalog.jsonb_build_object('status','unavailable','reason','legacy_provenance_gap',
        'confirmedWorkoutLogID',workout_id::text)) THEN
    RAISE EXCEPTION 'workout_strength_registration_identity_unproved' USING ERRCODE='P0002';
  END IF;
  IF resolution='sql_insert' THEN strength:=strength||'{"status":"committed"}'::jsonb; END IF;
  RETURN pg_catalog.jsonb_build_object('legacy_result',legacy_result,'strength',strength);
END;
$capture$;
REVOKE ALL ON FUNCTION public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb) TO service_role;
COMMENT ON FUNCTION public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb) IS
  'Backend-only dormant atomic workout/fact/binding capture from an admitted SQL journal; original writer and callers unchanged.';

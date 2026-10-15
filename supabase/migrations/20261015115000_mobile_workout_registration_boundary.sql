-- UI workout revision boundary. Dormant until the real BFF/Swift CAS callers land.
-- No nutritional calculation changes. The legacy writer bodies below are preserved.
BEGIN;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('private.mobile_workout_proposal_admissions') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_commands') IS NULL
    OR pg_catalog.to_regclass('public.pending_registrations') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('register_workout_atomic','register_workout_strength_atomic',
        'admit_mobile_workout_proposal','materialize_mobile_workout_proposal')) <> 4
    OR (SELECT pg_catalog.md5(prosrc)='e982fbe59c4f569e58211e646c1eb8d8' AND proowner='postgres'::regrole
      FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)')) IS DISTINCT FROM true
    OR (SELECT pg_catalog.md5(prosrc)='3f67fcd2854a024357f289569ebb0f11' AND proowner='postgres'::regrole
      FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)')) IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('admit_mobile_workout_proposal','materialize_mobile_workout_proposal')
        AND (p.proowner<>'postgres'::regrole OR NOT p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'])) THEN
    RAISE EXCEPTION 'mobile_workout_registration_source_drift' USING ERRCODE='55000';
  END IF;
  IF pg_catalog.to_regclass('private.mobile_workout_registration_edit_receipts') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE NOT attisdropped AND
      ((attrelid='private.mobile_workout_proposal_admissions'::regclass AND attname IN ('content_revision','confirmed_lifecycle_key'))
        OR (attrelid='public.pending_registrations'::regclass AND attname='workout_ui_admission_id')))
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE (n.nspname='private' AND p.proname IN ('register_workout_atomic_core','register_workout_strength_core',
        'mobile_workout_registration_key_is_protected','mobile_workout_registration_pending_is_protected','guard_mobile_workout_registration'))
        OR (n.nspname='public' AND p.proname IN ('admit_mobile_workout_registration','materialize_mobile_workout_registration','get_mobile_workout_registration'))) THEN
    RAISE EXCEPTION 'mobile_workout_registration_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

-- Literal readonly guard is also used by isolated, rollback-only ACL regressions.
-- Only the existing explicit service table I/U grants may be removed; do not
-- silently repair PUBLIC, columns, inherited roles, SET-owner or superuser access.
DO $workout_acl_preflight$
DECLARE
  rel oid:='public.workout_logs'::regclass;
  service oid:='service_role'::regrole;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
      WHERE (r.rolsuper OR r.oid=(SELECT relowner FROM pg_catalog.pg_class WHERE oid=rel))
        AND pg_catalog.pg_has_role(service,r.oid,'MEMBER'))
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
      WHERE c.oid=rel AND a.privilege_type IN ('INSERT','UPDATE') AND a.grantee<>service
        AND (a.grantee=0 OR pg_catalog.pg_has_role(service,a.grantee,'MEMBER')))
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute c CROSS JOIN LATERAL pg_catalog.aclexplode(c.attacl) a
      WHERE c.attrelid=rel AND c.attnum>0 AND NOT c.attisdropped AND a.privilege_type IN ('INSERT','UPDATE')
        AND (a.grantee=0 OR a.grantee=service OR pg_catalog.pg_has_role(service,a.grantee,'MEMBER'))) THEN
    RAISE EXCEPTION 'C59S17B_UNEXPECTED_WORKOUT_WRITE_PRIVILEGE' USING ERRCODE='42501';
  END IF;
END $workout_acl_preflight$;

ALTER TABLE private.mobile_workout_proposal_admissions
  ADD COLUMN content_revision integer,
  ADD COLUMN confirmed_lifecycle_key uuid,
  ADD CONSTRAINT mobile_workout_proposal_admissions_revision_check
    CHECK (content_revision IS NULL OR content_revision>=0),
  ADD CONSTRAINT mobile_workout_proposal_admissions_lifecycle_check
    CHECK (content_revision IS NOT NULL OR confirmed_lifecycle_key IS NULL);

CREATE TABLE private.mobile_workout_registration_edit_receipts (
  user_id uuid NOT NULL,
  admission_id uuid NOT NULL,
  request_key text COLLATE "C" NOT NULL,
  input_hash text NOT NULL,
  expected_revision integer NOT NULL,
  result_revision integer NOT NULL,
  PRIMARY KEY(user_id,admission_id,request_key),
  CONSTRAINT mobile_workout_registration_edit_receipts_owner_fk FOREIGN KEY(user_id,admission_id)
    REFERENCES private.mobile_workout_proposal_admissions(user_id,admission_id) ON DELETE CASCADE,
  CONSTRAINT mobile_workout_registration_edit_receipts_shape_check CHECK ((
    (request_key COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$'
    AND (input_hash COLLATE "C") ~ '^[0-9a-f]{64}$'
    AND expected_revision>=0 AND result_revision::numeric=expected_revision::numeric+1
  ) IS TRUE)
);
ALTER TABLE private.mobile_workout_registration_edit_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_workout_registration_edit_receipts FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE public.pending_registrations
  ADD COLUMN workout_ui_admission_id uuid,
  ADD CONSTRAINT pending_registrations_workout_ui_owner_fk FOREIGN KEY(user_id,workout_ui_admission_id)
    REFERENCES private.mobile_workout_proposal_admissions(user_id,admission_id) ON DELETE NO ACTION;
CREATE INDEX pending_registrations_workout_ui_owner_idx
  ON public.pending_registrations(user_id,workout_ui_admission_id) WHERE workout_ui_admission_id IS NOT NULL;

CREATE FUNCTION private.mobile_workout_registration_key_is_protected(p_user_id uuid,p_request_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $protected_key$
  SELECT EXISTS (
    SELECT 1 FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.content_revision IS NOT NULL AND a.pending_id IS NOT NULL
      AND (a.request_key=(p_request_key COLLATE "C") OR EXISTS (
        SELECT 1 FROM private.mobile_workout_registration_edit_receipts e
        WHERE e.user_id=a.user_id AND e.admission_id=a.admission_id AND e.request_key=(p_request_key COLLATE "C")))
  )
$protected_key$;
REVOKE ALL ON FUNCTION private.mobile_workout_registration_key_is_protected(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- Minimal read capability for the INVOKER trigger, including a corrupt NULL marker.
-- Historical membership deliberately survives reset and deletion of the pending row.
CREATE FUNCTION private.mobile_workout_registration_pending_is_protected(p_user_id uuid,p_pending_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $protected_pending$
  SELECT EXISTS (SELECT 1 FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.pending_id=p_pending_id AND a.content_revision IS NOT NULL)
$protected_pending$;
REVOKE ALL ON FUNCTION private.mobile_workout_registration_pending_is_protected(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.mobile_workout_registration_pending_is_protected(uuid,uuid) TO service_role;

CREATE FUNCTION private.guard_mobile_workout_registration() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $pending_guard$
BEGIN
  -- This is an ACL seam, never a CAS proof. Only owned RPC bodies run as postgres;
  -- the future confirming RPC must establish owner/revision/F1 before any write.
  IF CURRENT_USER='postgres' THEN RETURN NEW; END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.workout_ui_admission_id IS NOT NULL
      OR private.mobile_workout_registration_pending_is_protected(NEW.user_id,NEW.id) THEN
      RAISE EXCEPTION 'mobile_workout_registration_requires_revision' USING ERRCODE='42501';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.workout_ui_admission_id IS DISTINCT FROM OLD.workout_ui_admission_id THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_revision' USING ERRCODE='42501';
  END IF;
  IF OLD.workout_ui_admission_id IS NOT NULL
    OR private.mobile_workout_registration_pending_is_protected(OLD.user_id,OLD.id)
    OR private.mobile_workout_registration_pending_is_protected(NEW.user_id,NEW.id) THEN
    IF OLD.status='pending' AND NEW.status IN ('cancelled','expired')
      AND NEW.resolved_at IS NOT NULL AND pg_catalog.isfinite(NEW.resolved_at)
      AND pg_catalog.to_jsonb(NEW)-ARRAY['status','resolved_at']=pg_catalog.to_jsonb(OLD)-ARRAY['status','resolved_at'] THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'mobile_workout_registration_requires_revision' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $pending_guard$;
REVOKE ALL ON FUNCTION private.guard_mobile_workout_registration() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pending_registrations_workout_ui_guard BEFORE INSERT OR UPDATE ON public.pending_registrations
  FOR EACH ROW EXECUTE FUNCTION private.guard_mobile_workout_registration();

CREATE FUNCTION private.register_workout_atomic_core(
  p_user_id uuid,
  p_date date,
  p_workout_type text,
  p_duration_min integer,
  p_estimated_kcal integer,
  p_intensity text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_performed_at timestamptz DEFAULT now(),
  p_provider_message_id text DEFAULT NULL,
  p_calories_target integer DEFAULT NULL,
  p_protein_target numeric DEFAULT NULL,
  p_replace_recent boolean DEFAULT false,
  p_replace_since timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $legacy13$
DECLARE
  v_snapshot_id uuid;
  v_workout_log_id uuid;
  v_inserted boolean := false;
  v_replaced_count integer := 0;
  v_affected_snapshot_ids uuid[] := ARRAY[]::uuid[];
  v_affected_snapshot_id uuid;
  v_result jsonb;
BEGIN
  IF p_user_id IS NULL OR p_date IS NULL
    OR NULLIF(btrim(p_workout_type), '') IS NULL
    OR length(p_workout_type) > 200
    OR p_duration_min IS NULL OR p_duration_min < 1 OR p_duration_min > 1440
    OR p_estimated_kcal IS NULL OR p_estimated_kcal < 0 OR p_estimated_kcal > 10000 THEN
    RAISE EXCEPTION 'invalid workout payload';
  END IF;
  IF p_replace_recent AND p_replace_since IS NULL THEN
    RAISE EXCEPTION 'replace requires a lower time boundary';
  END IF;

  -- Corrections may affect a previous local day, so all workout writes for a
  -- user share one short transaction lock instead of locking only one date.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':workouts', 0));

  INSERT INTO public.daily_snapshots (
    user_id,
    date,
    exercise_calories,
    training_done,
    calories_target,
    protein_target
  ) VALUES (
    p_user_id,
    p_date,
    0,
    false,
    p_calories_target,
    p_protein_target
  )
  ON CONFLICT (user_id, date) DO UPDATE SET
    calories_target = COALESCE(public.daily_snapshots.calories_target, EXCLUDED.calories_target),
    protein_target = COALESCE(public.daily_snapshots.protein_target, EXCLUDED.protein_target),
    updated_at = now()
  RETURNING id INTO v_snapshot_id;

  IF p_replace_recent THEN
    SELECT COALESCE(
      array_agg(DISTINCT snapshot_id) FILTER (WHERE snapshot_id IS NOT NULL),
      ARRAY[]::uuid[]
    )
    INTO v_affected_snapshot_ids
    FROM public.workout_logs
    WHERE user_id = p_user_id
      AND workout_type = p_workout_type
      AND created_at >= p_replace_since;

    DELETE FROM public.workout_logs
    WHERE user_id = p_user_id
      AND workout_type = p_workout_type
      AND created_at >= p_replace_since;
    GET DIAGNOSTICS v_replaced_count = ROW_COUNT;
  END IF;

  INSERT INTO public.workout_logs (
    user_id,
    snapshot_id,
    workout_type,
    duration_min,
    estimated_kcal,
    intensity,
    notes,
    performed_at,
    raw_provider_message_id
  ) VALUES (
    p_user_id,
    v_snapshot_id,
    btrim(p_workout_type),
    p_duration_min,
    p_estimated_kcal,
    p_intensity,
    p_notes,
    COALESCE(p_performed_at, now()),
    p_provider_message_id
  )
  ON CONFLICT (user_id, raw_provider_message_id, workout_type)
    WHERE raw_provider_message_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO v_workout_log_id;

  v_inserted := v_workout_log_id IS NOT NULL;
  IF NOT v_inserted AND p_provider_message_id IS NOT NULL THEN
    SELECT id
    INTO v_workout_log_id
    FROM public.workout_logs
    WHERE user_id = p_user_id
      AND raw_provider_message_id = p_provider_message_id
      AND workout_type = btrim(p_workout_type)
    LIMIT 1;
  END IF;

  SELECT ARRAY(
    SELECT DISTINCT affected.snapshot_id
    FROM unnest(v_affected_snapshot_ids || ARRAY[v_snapshot_id]) AS affected(snapshot_id)
    WHERE affected.snapshot_id IS NOT NULL
  ) INTO v_affected_snapshot_ids;

  FOREACH v_affected_snapshot_id IN ARRAY v_affected_snapshot_ids LOOP
    UPDATE public.daily_snapshots AS snapshot
    SET
      exercise_calories = (
        SELECT COALESCE(sum(workout.estimated_kcal), 0)::integer
        FROM public.workout_logs AS workout
        WHERE workout.snapshot_id = v_affected_snapshot_id
      ),
      training_done = EXISTS (
        SELECT 1
        FROM public.workout_logs AS workout
        WHERE workout.snapshot_id = v_affected_snapshot_id
      ),
      updated_at = now()
    WHERE snapshot.id = v_affected_snapshot_id;
  END LOOP;

  SELECT jsonb_build_object(
    'snapshot_id', snapshot.id,
    'workout_log_id', v_workout_log_id,
    'inserted', v_inserted,
    'replaced_count', v_replaced_count,
    'exercise_calories', snapshot.exercise_calories,
    'training_done', snapshot.training_done,
    'calories_target', snapshot.calories_target,
    'protein_target', snapshot.protein_target
  ) INTO v_result
  FROM public.daily_snapshots AS snapshot
  WHERE snapshot.id = v_snapshot_id;

  RETURN v_result;
END;
$legacy13$;
REVOKE ALL ON FUNCTION private.register_workout_atomic_core(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.register_workout_strength_core(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_operation_key text,
  p_original_operation_type text,p_catalogue_observation jsonb,p_catalogue_decision jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $legacy8$
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
    legacy_result:=private.register_workout_atomic_core(
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
$legacy8$;
REVOKE ALL ON FUNCTION private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.register_workout_atomic(
  p_user_id uuid,
  p_date date,
  p_workout_type text,
  p_duration_min integer,
  p_estimated_kcal integer,
  p_intensity text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_performed_at timestamptz DEFAULT now(),
  p_provider_message_id text DEFAULT NULL,
  p_calories_target integer DEFAULT NULL,
  p_protein_target numeric DEFAULT NULL,
  p_replace_recent boolean DEFAULT false,
  p_replace_since timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $writer_guard$
BEGIN
  PERFORM private.assert_trusted_backend();
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_read_committed' USING ERRCODE='22023';
  END IF;
  -- Separate statements are necessary: after an advisory wait READ COMMITTED
  -- must inspect the newly committed membership before even snapshot UPSERT.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  IF private.mobile_workout_registration_key_is_protected(p_user_id,p_provider_message_id) THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_revision' USING ERRCODE='42501';
  END IF;
  RETURN private.register_workout_atomic_core(p_user_id,p_date,p_workout_type,p_duration_min,p_estimated_kcal,
    p_intensity,p_notes,p_performed_at,p_provider_message_id,p_calories_target,p_protein_target,p_replace_recent,p_replace_since);
END $writer_guard$;
REVOKE INSERT,UPDATE ON TABLE public.workout_logs FROM service_role;

CREATE OR REPLACE FUNCTION public.register_workout_strength_atomic(
  p_user_id uuid,p_expected_lifecycle_key uuid,p_operation_key text,
  p_original_operation_type text,p_catalogue_observation jsonb,p_catalogue_decision jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $strength_guard$
DECLARE provider text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_expected_lifecycle_key IS NULL OR p_operation_key IS NULL OR p_operation_key=''
    OR p_original_operation_type IS NULL OR pg_catalog.btrim(p_original_operation_type)='' THEN
    RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;
  LOCK TABLE public.workout_types IN SHARE MODE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  SELECT c.legacy_arguments->>'p_provider_message_id' INTO provider FROM private.workout_strength_commands c
    WHERE c.user_id=p_user_id AND c.lifecycle_key=p_expected_lifecycle_key
      AND c.operation_key=(p_operation_key COLLATE "C") AND c.original_operation_type=(p_original_operation_type COLLATE "C");
  -- Guard before the core's existing F1 replay and early legacy provider dedup.
  IF private.mobile_workout_registration_key_is_protected(p_user_id,provider) THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_revision' USING ERRCODE='42501';
  END IF;
  RETURN private.register_workout_strength_core(p_user_id,p_expected_lifecycle_key,p_operation_key,
    p_original_operation_type,p_catalogue_observation,p_catalogue_decision);
END $strength_guard$;

-- Close the old S16 entrypoints; their OIDs/bodies stay intact for owner wrappers.
REVOKE EXECUTE ON FUNCTION public.admit_mobile_workout_proposal(uuid,text,jsonb) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamptz) FROM service_role;

CREATE FUNCTION public.admit_mobile_workout_registration(p_user_id uuid,p_request_key text,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $admit$
DECLARE result jsonb; revision integer;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_request_key IS NULL OR NOT ((p_request_key COLLATE "C") ~
    '^wui1:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  PERFORM private.mobile_workout_proposal_input_hash(p_input);
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  result:=public.admit_mobile_workout_proposal(p_user_id,p_request_key,p_input);
  IF result->>'status'='admitted' THEN
    UPDATE private.mobile_workout_proposal_admissions SET content_revision=0
      WHERE user_id=p_user_id AND admission_id=(result#>>'{admission,admissionID}')::uuid AND content_revision IS NULL
      RETURNING content_revision INTO STRICT revision;
  ELSIF result->>'status'='reused' THEN
    SELECT a.content_revision INTO revision FROM private.mobile_workout_proposal_admissions a
      WHERE a.user_id=p_user_id AND a.admission_id=(result#>>'{admission,admissionID}')::uuid;
    IF revision IS NULL THEN RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb; END IF;
  END IF;
  RETURN result;
END $admit$;
REVOKE ALL ON FUNCTION public.admit_mobile_workout_registration(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_mobile_workout_registration(uuid,text,jsonb) TO service_role;

CREATE FUNCTION public.materialize_mobile_workout_registration(
  p_user_id uuid,p_admission_id uuid,p_input jsonb,p_proposal jsonb,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $materialize$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.mobile_workout_proposal_admissions%ROWTYPE;
  pending public.pending_registrations%ROWTYPE;
  result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_admission_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  PERFORM private.mobile_workout_proposal_input_hash(p_input);
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_proposal_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_workout_proposal_patient_not_found' USING ERRCODE='P0002'; END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb; END IF;
  SELECT a.* INTO admission FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=p_admission_id FOR UPDATE;
  IF NOT FOUND OR admission.content_revision IS NULL THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  IF admission.epoch IS DISTINCT FROM authority.epoch THEN
    RETURN '{"status":"forbidden","reason":"stale_epoch"}'::jsonb;
  END IF;
  IF admission.pending_id IS NOT NULL THEN
    SELECT p.* INTO pending FROM public.pending_registrations p
      WHERE p.user_id=p_user_id AND p.id=admission.pending_id FOR SHARE;
    IF FOUND AND pending.workout_ui_admission_id IS DISTINCT FROM p_admission_id THEN
      RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
    END IF;
  END IF;
  result:=public.materialize_mobile_workout_proposal(p_user_id,p_admission_id,p_input,p_proposal,p_expires_at);
  IF result->>'status'='materialized' THEN
    UPDATE public.pending_registrations SET workout_ui_admission_id=p_admission_id
      WHERE user_id=p_user_id AND id=(result->>'pendingID')::uuid AND workout_ui_admission_id IS NULL
      RETURNING * INTO STRICT pending;
  END IF;
  RETURN result;
END $materialize$;
REVOKE ALL ON FUNCTION public.materialize_mobile_workout_registration(uuid,uuid,jsonb,jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.materialize_mobile_workout_registration(uuid,uuid,jsonb,jsonb,timestamptz) TO service_role;

CREATE FUNCTION public.get_mobile_workout_registration(p_user_id uuid,p_registration_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $projection$
DECLARE result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  -- Exactly one SELECT/snapshot obtains the payload and revision through every
  -- owned link. A revision never comes from a separate historical read.
  SELECT pg_catalog.jsonb_build_object('status','available','registration',pg_catalog.jsonb_build_object(
    'id',p.id,'status',p.status,'created_at',p.created_at,'expires_at',p.expires_at,'resolved_at',p.resolved_at,
    'proposal',p.proposal,'workout_protocol','ui-v1','content_revision',a.content_revision)) INTO result
  FROM public.users u
  JOIN private.workout_strength_authority_epochs e ON e.user_id=u.id
  JOIN private.mobile_workout_proposal_admissions a ON a.user_id=u.id AND a.epoch=e.epoch AND a.content_revision IS NOT NULL
  JOIN public.pending_registrations p ON p.user_id=u.id AND p.id=a.pending_id AND p.workout_ui_admission_id=a.admission_id
  WHERE u.id=p_user_id AND u.status='active' AND p.id=p_registration_id;
  RETURN COALESCE(result,'{"status":"forbidden","reason":"invalid_admission"}'::jsonb);
END $projection$;
REVOKE ALL ON FUNCTION public.get_mobile_workout_registration(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_workout_registration(uuid,uuid) TO service_role;

-- New object grants must match the narrow contract, including inherited access.
DO $privileges$
DECLARE service oid:='service_role'::regrole; postgres_owner oid:='postgres'::regrole;
BEGIN
  IF pg_catalog.has_table_privilege(service,'public.workout_logs','INSERT')
    OR pg_catalog.has_table_privilege(service,'public.workout_logs','UPDATE')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.workout_logs'::regclass AND a.attnum>0 AND NOT a.attisdropped
      AND (pg_catalog.has_column_privilege(service,a.attrelid,a.attnum,'INSERT') OR pg_catalog.has_column_privilege(service,a.attrelid,a.attnum,'UPDATE')))
    OR NOT pg_catalog.has_table_privilege(service,'public.workout_logs','SELECT')
    OR NOT pg_catalog.has_table_privilege(service,'public.workout_logs','DELETE')
    OR pg_catalog.has_function_privilege(service,'public.admit_mobile_workout_proposal(uuid,text,jsonb)','EXECUTE')
    OR pg_catalog.has_function_privilege(service,'public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'C59S17B_UNEXPECTED_WORKOUT_WRITE_PRIVILEGE' USING ERRCODE='42501';
  END IF;
  IF EXISTS (
    WITH objects AS (
      SELECT 'r'::pg_catalog."char" AS kind,c.oid,c.relowner AS owner_id,c.relacl AS acl,false AS backend_rpc
      FROM pg_catalog.pg_class c WHERE c.oid='private.mobile_workout_registration_edit_receipts'::regclass
      UNION ALL
      SELECT 'f'::pg_catalog."char",p.oid,p.proowner,p.proacl,
        (n.nspname='public' OR p.proname='mobile_workout_registration_pending_is_protected')
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE
        (n.nspname='private' AND p.proname IN ('register_workout_atomic_core','register_workout_strength_core',
          'mobile_workout_registration_key_is_protected','mobile_workout_registration_pending_is_protected','guard_mobile_workout_registration'))
        OR (n.nspname='public' AND p.proname IN ('admit_mobile_workout_registration','materialize_mobile_workout_registration','get_mobile_workout_registration'))
    ), actual AS (
      SELECT o.kind,o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(o.acl,pg_catalog.acldefault(o.kind,o.owner_id))) a
    ), expected AS (
      SELECT o.kind,o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL pg_catalog.aclexplode(pg_catalog.acldefault(o.kind,postgres_owner)) a
      WHERE a.grantee=postgres_owner
      UNION ALL SELECT o.kind,o.oid,postgres_owner,service,'EXECUTE'::text,false FROM objects o WHERE o.backend_rpc
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    ) SELECT 1 FROM objects WHERE owner_id<>postgres_owner UNION ALL SELECT 1 FROM differences
  ) THEN RAISE EXCEPTION 'C59S17B_UNEXPECTED_OBJECT_ACL' USING ERRCODE='42501'; END IF;
END $privileges$;
COMMIT;

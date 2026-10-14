-- Weekly strength target storage and private provenance primitives.
-- Dormant and additive: existing writers and reset paths are not connected here.
BEGIN;

CREATE TABLE private.strength_week_scopes (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  generation uuid NOT NULL DEFAULT pg_catalog.gen_random_uuid(),
  predecessor_generation uuid,
  open_operation_namespace text NOT NULL
    CHECK (open_operation_namespace COLLATE "C" ~ '^[a-z][a-z0-9_.:-]{0,63}$'),
  open_operation_key text NOT NULL
    CHECK (open_operation_key COLLATE "C" ~ '^[A-Za-z0-9._:-]{8,128}$'),
  opened_at timestamptz NOT NULL,
  closed_at timestamptz,
  PRIMARY KEY (user_id, generation),
  UNIQUE (user_id, open_operation_namespace, open_operation_key),
  FOREIGN KEY (user_id, predecessor_generation)
    REFERENCES private.strength_week_scopes(user_id, generation) ON DELETE NO ACTION,
  CHECK (predecessor_generation IS NULL OR predecessor_generation <> generation),
  CHECK (pg_catalog.isfinite(opened_at)
    AND pg_catalog.date_part('year', opened_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
  CHECK (closed_at IS NULL OR (pg_catalog.isfinite(closed_at) AND closed_at >= opened_at))
);
CREATE UNIQUE INDEX strength_week_scopes_one_current
  ON private.strength_week_scopes(user_id) WHERE closed_at IS NULL;

CREATE TABLE private.strength_week_source_versions (
  source_version_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  user_id uuid NOT NULL,
  generation uuid NOT NULL,
  source_kind text NOT NULL CHECK (source_kind IN ('accepted_plan', 'informed_frequency')),
  fact text NOT NULL CHECK (fact IN ('value', 'absent')),
  planned_days smallint,
  source_entity_id uuid,
  source_valid_until timestamptz,
  operation_namespace text NOT NULL
    CHECK (operation_namespace COLLATE "C" ~ '^[a-z][a-z0-9_.:-]{0,63}$'),
  operation_key text NOT NULL
    CHECK (operation_key COLLATE "C" ~ '^[A-Za-z0-9._:-]{8,128}$'),
  observed_at timestamptz NOT NULL,
  observed_timezone text NOT NULL CHECK (pg_catalog.length(observed_timezone) > 0),
  effective_week_start date NOT NULL,
  source_order bigint GENERATED ALWAYS AS IDENTITY (NO CYCLE),
  FOREIGN KEY (user_id, generation)
    REFERENCES private.strength_week_scopes(user_id, generation) ON DELETE CASCADE,
  UNIQUE (user_id, generation, source_version_id),
  UNIQUE (user_id, generation, source_kind, operation_namespace, operation_key),
  UNIQUE (source_order),
  CHECK (source_order > 0),
  CHECK (pg_catalog.isfinite(observed_at)
    AND pg_catalog.date_part('year', observed_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
  CHECK (pg_catalog.isfinite(effective_week_start)
    AND effective_week_start BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    AND pg_catalog.date_part('isodow', effective_week_start::timestamp) = 1),
  CHECK (source_valid_until IS NULL OR
    (pg_catalog.isfinite(source_valid_until)
      AND pg_catalog.date_part('year', source_valid_until AT TIME ZONE 'UTC') BETWEEN 1 AND 9999)),
  CHECK (
    (fact = 'absent' AND planned_days IS NULL AND source_entity_id IS NULL
      AND source_valid_until IS NULL)
    OR
    (fact = 'value' AND planned_days IS NOT NULL AND
      ((source_kind = 'accepted_plan' AND planned_days BETWEEN 1 AND 7
          AND source_entity_id IS NOT NULL)
       OR
       (source_kind = 'informed_frequency' AND planned_days BETWEEN 0 AND 7
          AND source_entity_id IS NULL AND source_valid_until IS NULL)))
  )
);
CREATE INDEX strength_week_source_versions_selection
  ON private.strength_week_source_versions
    (user_id, generation, source_kind, effective_week_start DESC, source_order DESC);

CREATE TABLE private.strength_week_targets (
  target_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  user_id uuid NOT NULL,
  generation uuid NOT NULL,
  week_start date NOT NULL,
  timezone_at_freeze text NOT NULL CHECK (pg_catalog.length(timezone_at_freeze) > 0),
  planned_days smallint,
  source text NOT NULL CHECK (source IN ('accepted_plan', 'informed_frequency', 'absent')),
  plan_source_version_id uuid,
  frequency_source_version_id uuid,
  frozen_at timestamptz NOT NULL,
  FOREIGN KEY (user_id, generation)
    REFERENCES private.strength_week_scopes(user_id, generation) ON DELETE CASCADE,
  FOREIGN KEY (user_id, generation, plan_source_version_id)
    REFERENCES private.strength_week_source_versions(user_id, generation, source_version_id)
    ON DELETE NO ACTION,
  FOREIGN KEY (user_id, generation, frequency_source_version_id)
    REFERENCES private.strength_week_source_versions(user_id, generation, source_version_id)
    ON DELETE NO ACTION,
  UNIQUE (user_id, generation, week_start),
  CHECK (pg_catalog.isfinite(week_start)
    AND week_start BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    AND pg_catalog.date_part('isodow', week_start::timestamp) = 1),
  CHECK (pg_catalog.isfinite(frozen_at)
    AND pg_catalog.date_part('year', frozen_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
  CHECK (
    (source = 'accepted_plan' AND planned_days IS NOT NULL AND planned_days BETWEEN 1 AND 7
      AND plan_source_version_id IS NOT NULL)
    OR
    (source = 'informed_frequency' AND planned_days IS NOT NULL AND planned_days BETWEEN 0 AND 7
      AND plan_source_version_id IS NOT NULL AND frequency_source_version_id IS NOT NULL)
    OR
    (source = 'absent' AND planned_days IS NULL
      AND plan_source_version_id IS NOT NULL AND frequency_source_version_id IS NOT NULL)
  )
);
ALTER TABLE private.strength_week_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.strength_week_source_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.strength_week_targets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.strength_week_scopes,
  private.strength_week_source_versions, private.strength_week_targets
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.strength_week_source_versions_source_order_seq
  FROM PUBLIC, anon, authenticated, service_role;

-- Value-only serde/shape helpers. None reads tables, clocks, auth or settings.
CREATE FUNCTION private.strength_week_json_keys(p_object jsonb, p_keys text[])
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
BEGIN
  IF pg_catalog.jsonb_typeof(p_object) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  RETURN p_object ?& p_keys AND (p_object - p_keys) = '{}'::jsonb;
END;
$fn$;

CREATE FUNCTION private.strength_week_freeze_shape(p_proof jsonb, p_proposal jsonb)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE k text; e jsonb; order_text text; uuid_text text; days numeric; source_text text;
BEGIN
  IF NOT private.strength_week_json_keys(p_proof, ARRAY['plan','frequency'])
    OR NOT private.strength_week_json_keys(p_proposal, ARRAY['source','planned_days','source_key'])
  THEN RETURN false; END IF;
  FOREACH k IN ARRAY ARRAY['plan','frequency'] LOOP
    e := p_proof -> k;
    IF pg_catalog.jsonb_typeof(e -> 'coverage') IS DISTINCT FROM 'string' THEN RETURN false; END IF;
    IF e ->> 'coverage' = 'unknown' THEN
      IF NOT private.strength_week_json_keys(e, ARRAY['coverage']) THEN RETURN false; END IF;
    ELSIF e ->> 'coverage' = 'covered' THEN
      IF NOT private.strength_week_json_keys(e, ARRAY['coverage','source_version_id','source_order'])
        OR pg_catalog.jsonb_typeof(e -> 'source_version_id') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(e -> 'source_order') IS DISTINCT FROM 'string'
      THEN RETURN false; END IF;
      uuid_text := e ->> 'source_version_id';
      order_text := e ->> 'source_order';
      IF uuid_text COLLATE "C" !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR order_text COLLATE "C" !~ '^[1-9][0-9]{0,18}$'
      THEN RETURN false; END IF;
      IF pg_catalog.length(order_text) = 19
        AND order_text COLLATE "C" > '9223372036854775807' COLLATE "C"
      THEN RETURN false; END IF;
    ELSE RETURN false;
    END IF;
  END LOOP;
  IF pg_catalog.jsonb_typeof(p_proposal -> 'source') IS DISTINCT FROM 'string' THEN RETURN false; END IF;
  source_text := p_proposal ->> 'source';
  IF source_text = 'absent' THEN
    RETURN p_proposal -> 'planned_days' = 'null'::jsonb
      AND p_proposal -> 'source_key' = 'null'::jsonb;
  END IF;
  IF source_text NOT IN ('accepted_plan','informed_frequency')
    OR pg_catalog.jsonb_typeof(p_proposal -> 'planned_days') IS DISTINCT FROM 'number'
    OR pg_catalog.jsonb_typeof(p_proposal -> 'source_key') IS DISTINCT FROM 'string'
  THEN RETURN false; END IF;
  uuid_text := p_proposal ->> 'source_key';
  IF uuid_text COLLATE "C" !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  THEN RETURN false; END IF;
  days := (p_proposal ->> 'planned_days')::numeric;
  RETURN days = pg_catalog.trunc(days) AND days BETWEEN
    CASE WHEN source_text = 'accepted_plan' THEN 1 ELSE 0 END AND 7;
END;
$fn$;

CREATE FUNCTION private.strength_week_source_wire(p_row private.strength_week_source_versions)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
SELECT pg_catalog.jsonb_build_object(
  'source_version_id',(p_row).source_version_id,'user_id',(p_row).user_id,'generation',(p_row).generation,
  'source_kind',(p_row).source_kind,'fact',(p_row).fact,'planned_days',(p_row).planned_days,
  'source_entity_id',(p_row).source_entity_id,
  'source_valid_until',CASE WHEN (p_row).source_valid_until IS NULL THEN NULL ELSE
    pg_catalog.to_char((p_row).source_valid_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
  'source_order',(p_row).source_order::text,
  'observed_at',pg_catalog.to_char((p_row).observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'observed_timezone',(p_row).observed_timezone,
  'effective_week_start',pg_catalog.to_char((p_row).effective_week_start::timestamp,'YYYY-MM-DD'))
$fn$;

CREATE FUNCTION private.strength_week_proof_wire(
  p_plan_id uuid, p_plan_order bigint, p_frequency_id uuid, p_frequency_order bigint)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
SELECT pg_catalog.jsonb_build_object(
  'plan',CASE WHEN p_plan_id IS NULL THEN pg_catalog.jsonb_build_object('coverage','unknown')
    ELSE pg_catalog.jsonb_build_object('coverage','covered','source_version_id',p_plan_id,'source_order',p_plan_order::text) END,
  'frequency',CASE WHEN p_frequency_id IS NULL THEN pg_catalog.jsonb_build_object('coverage','unknown')
    ELSE pg_catalog.jsonb_build_object('coverage','covered','source_version_id',p_frequency_id,'source_order',p_frequency_order::text) END)
$fn$;

CREATE FUNCTION private.strength_week_target_wire(
  p_target private.strength_week_targets,
  p_plan private.strength_week_source_versions,
  p_frequency private.strength_week_source_versions)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
BEGIN
  IF p_target.target_id IS NULL
    OR (p_target.plan_source_version_id IS NOT NULL AND
      (p_plan.source_version_id IS DISTINCT FROM p_target.plan_source_version_id
       OR p_plan.user_id IS DISTINCT FROM p_target.user_id
       OR p_plan.generation IS DISTINCT FROM p_target.generation
       OR p_plan.source_kind IS DISTINCT FROM 'accepted_plan'))
    OR (p_target.frequency_source_version_id IS NOT NULL AND
      (p_frequency.source_version_id IS DISTINCT FROM p_target.frequency_source_version_id
       OR p_frequency.user_id IS DISTINCT FROM p_target.user_id
       OR p_frequency.generation IS DISTINCT FROM p_target.generation
       OR p_frequency.source_kind IS DISTINCT FROM 'informed_frequency'))
  THEN RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE = 'XX001'; END IF;
  IF (p_target.source = 'accepted_plan' AND
      (p_plan.fact IS DISTINCT FROM 'value' OR p_plan.planned_days IS DISTINCT FROM p_target.planned_days))
    OR (p_target.source = 'informed_frequency' AND
      (p_plan.fact IS DISTINCT FROM 'absent' OR p_frequency.fact IS DISTINCT FROM 'value'
       OR p_frequency.planned_days IS DISTINCT FROM p_target.planned_days))
    OR (p_target.source = 'absent' AND
      (p_plan.fact IS DISTINCT FROM 'absent' OR p_frequency.fact IS DISTINCT FROM 'absent'))
  THEN RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE = 'XX001'; END IF;
  RETURN pg_catalog.jsonb_build_object(
    'target_id',p_target.target_id,'user_id',p_target.user_id,'generation',p_target.generation,
    'week_start',pg_catalog.to_char(p_target.week_start::timestamp,'YYYY-MM-DD'),
    'timezone_at_freeze',p_target.timezone_at_freeze,'planned_days',p_target.planned_days,
    'source',p_target.source,
    'source_key',CASE p_target.source WHEN 'accepted_plan' THEN p_plan.source_version_id
      WHEN 'informed_frequency' THEN p_frequency.source_version_id ELSE NULL END,
    'frozen_at',pg_catalog.to_char(p_target.frozen_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'source_proof',private.strength_week_proof_wire(
      p_plan.source_version_id,p_plan.source_order,p_frequency.source_version_id,p_frequency.source_order));
END;
$fn$;

-- Shared serialization point. No clock is evaluated before this owner lock.
CREATE FUNCTION private.strength_week_lock_owner(p_user_id uuid)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE zone text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_strength_week_requires_read_committed' USING ERRCODE = '22023';
  END IF;
  SELECT u.timezone INTO zone FROM public.users AS u
    WHERE u.id = p_user_id AND u.status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_strength_week_patient_not_found' USING ERRCODE = 'P0002';
  END IF;
  RETURN zone;
END;
$fn$;

-- The entire data photograph (including owner/scope/current clock/calendar,
-- winner and its referenced receipts, all-generation F1 guards and selections)
-- is ONE SQL statement. Serde helpers above perform no additional table reads.
CREATE FUNCTION private.strength_week_context_snapshot(p_user_id uuid, p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE owner_exists boolean; invalid_storage boolean; result jsonb;
BEGIN
  IF p_user_id IS NULL OR (p_observed_at IS NOT NULL AND
    (NOT pg_catalog.isfinite(p_observed_at)
      OR pg_catalog.date_part('year',p_observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999))
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE = '22023'; END IF;
  WITH observation AS MATERIALIZED (
    SELECT COALESCE(p_observed_at,pg_catalog.clock_timestamp()) AS at
  ), owned AS MATERIALIZED (
    SELECT u.id,u.timezone FROM public.users AS u
      WHERE u.id = p_user_id AND u.status = 'active'
  ), scope AS MATERIALIZED (
    SELECT s.* FROM private.strength_week_scopes AS s JOIN owned AS u ON u.id=s.user_id
      WHERE s.closed_at IS NULL
  ), calendar AS MATERIALIZED (
    SELECT o.at,u.id,u.timezone,
      EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=u.timezone) AS supported,
      CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=u.timezone)
        THEN pg_catalog.date_trunc('week',o.at AT TIME ZONE u.timezone)::date ELSE NULL END AS monday
    FROM observation AS o LEFT JOIN owned AS u ON true
  ), all_sources AS MATERIALIZED (
    SELECT v.* FROM private.strength_week_source_versions AS v
      JOIN scope AS s ON s.user_id=v.user_id AND s.generation=v.generation
  ), winner AS MATERIALIZED (
    SELECT t.* FROM private.strength_week_targets AS t JOIN scope AS s
      ON s.user_id=t.user_id AND s.generation=t.generation
      JOIN calendar AS c ON c.monday=t.week_start
  ), selected_plan AS MATERIALIZED (
    SELECT v.* FROM all_sources AS v,calendar AS c
      WHERE v.source_kind='accepted_plan' AND v.effective_week_start<=c.monday
      ORDER BY v.effective_week_start DESC,v.source_order DESC LIMIT 1
  ), selected_frequency AS MATERIALIZED (
    SELECT v.* FROM all_sources AS v,calendar AS c
      WHERE v.source_kind='informed_frequency' AND v.effective_week_start<=c.monday
      ORDER BY v.effective_week_start DESC,v.source_order DESC LIMIT 1
  )
  SELECT c.id IS NOT NULL,
    w.target_id IS NULL AND EXISTS (
      SELECT 1 FROM all_sources AS v JOIN scope AS ss ON true
      WHERE v.observed_at < ss.opened_at
        OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=v.observed_timezone)
    ),
    CASE
      WHEN s.generation IS NULL THEN pg_catalog.jsonb_build_object('status','unavailable','reason','missing_scope')
      WHEN NOT c.supported OR c.monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN w.target_id IS NOT NULL THEN pg_catalog.jsonb_build_object('status','ready','context',
        pg_catalog.jsonb_build_object('user_id',c.id,'generation',s.generation,'timezone',c.timezone,
          'week_start',pg_catalog.to_char(c.monday::timestamp,'YYYY-MM-DD'),
          'observed_at',pg_catalog.to_char(c.at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'kind','existing_target','target',private.strength_week_target_wire(w::private.strength_week_targets,
            wp::private.strength_week_source_versions,wf::private.strength_week_source_versions)))
      WHEN EXISTS(SELECT 1 FROM all_sources AS v
          WHERE v.source_kind='accepted_plan' AND v.observed_timezone<>c.timezone)
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN p.source_version_id IS NULL
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','history_incomplete')
      WHEN p.fact='value' AND p.source_valid_until IS NOT NULL
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN p.fact='absent' AND EXISTS(SELECT 1 FROM all_sources AS v
          WHERE v.source_kind='informed_frequency' AND v.observed_timezone<>c.timezone)
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN p.fact='absent' AND f.source_version_id IS NULL
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','history_incomplete')
      ELSE pg_catalog.jsonb_build_object('status','ready','context',
        pg_catalog.jsonb_build_object('user_id',c.id,'generation',s.generation,'timezone',c.timezone,
          'week_start',pg_catalog.to_char(c.monday::timestamp,'YYYY-MM-DD'),
          'observed_at',pg_catalog.to_char(c.at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'kind','source_facts',
          'plan',pg_catalog.jsonb_build_object('coverage','covered','receipt',private.strength_week_source_wire(p::private.strength_week_source_versions)),
          'frequency',CASE WHEN f.source_version_id IS NULL THEN pg_catalog.jsonb_build_object('coverage','unknown')
            ELSE pg_catalog.jsonb_build_object('coverage','covered','receipt',private.strength_week_source_wire(f::private.strength_week_source_versions)) END,
          'source_proof',private.strength_week_proof_wire(p.source_version_id,p.source_order,f.source_version_id,f.source_order)))
    END
  INTO owner_exists,invalid_storage,result
  FROM calendar AS c LEFT JOIN scope AS s ON true LEFT JOIN winner AS w ON true
    LEFT JOIN all_sources AS wp ON wp.source_version_id=w.plan_source_version_id
    LEFT JOIN all_sources AS wf ON wf.source_version_id=w.frequency_source_version_id
    LEFT JOIN selected_plan AS p ON true LEFT JOIN selected_frequency AS f ON true;
  IF NOT owner_exists THEN
    RAISE EXCEPTION 'mobile_strength_week_patient_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF invalid_storage THEN
    RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE = 'XX001';
  END IF;
  RETURN result;
END;
$fn$;

CREATE FUNCTION private.get_mobile_strength_week_context_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
BEGIN
  IF p_observed_at IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE = '22023';
  END IF;
  RETURN private.strength_week_context_snapshot(p_user_id,p_observed_at);
END;
$fn$;

CREATE FUNCTION public.get_mobile_strength_week_context(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $fn$
BEGIN
  PERFORM private.assert_trusted_backend();
  RETURN private.strength_week_context_snapshot(p_user_id,NULL);
END;
$fn$;

CREATE FUNCTION private.open_strength_week_scope(p_user_id uuid,p_operation_namespace text,p_operation_key text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE s private.strength_week_scopes; at timestamptz;
BEGIN
  IF p_operation_namespace IS NULL OR p_operation_key IS NULL
    OR p_operation_namespace COLLATE "C" !~ '^[a-z][a-z0-9_.:-]{0,63}$'
    OR p_operation_key COLLATE "C" !~ '^[A-Za-z0-9._:-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE = '22023'; END IF;
  PERFORM private.strength_week_lock_owner(p_user_id);
  SELECT v.* INTO s FROM private.strength_week_scopes AS v
    WHERE v.user_id=p_user_id AND v.open_operation_namespace=p_operation_namespace
      AND v.open_operation_key=p_operation_key FOR UPDATE;
  IF FOUND THEN
    IF s.predecessor_generation IS NOT NULL THEN
      RAISE EXCEPTION 'strength_week_operation_conflict' USING ERRCODE='40001';
    END IF;
    IF s.closed_at IS NOT NULL THEN
      RAISE EXCEPTION 'strength_week_scope_closed' USING ERRCODE='40001';
    END IF;
  ELSE
    PERFORM 1 FROM private.strength_week_scopes AS v WHERE v.user_id=p_user_id AND v.closed_at IS NULL FOR UPDATE;
    IF FOUND THEN RAISE EXCEPTION 'strength_week_scope_active' USING ERRCODE='40001'; END IF;
    at:=pg_catalog.clock_timestamp();
    INSERT INTO private.strength_week_scopes(user_id,open_operation_namespace,open_operation_key,opened_at)
      VALUES(p_user_id,p_operation_namespace,p_operation_key,at) RETURNING * INTO s;
  END IF;
  RETURN pg_catalog.jsonb_build_object('user_id',s.user_id,'generation',s.generation,
    'predecessor_generation',s.predecessor_generation,
    'opened_at',pg_catalog.to_char(s.opened_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'closed_at',NULL);
END;
$fn$;

CREATE FUNCTION private.roll_strength_week_scope(
  p_user_id uuid,p_expected_generation uuid,p_operation_namespace text,p_operation_key text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE s private.strength_week_scopes; current_scope private.strength_week_scopes; at timestamptz;
BEGIN
  IF p_expected_generation IS NULL OR p_operation_namespace IS NULL OR p_operation_key IS NULL
    OR p_operation_namespace COLLATE "C" !~ '^[a-z][a-z0-9_.:-]{0,63}$'
    OR p_operation_key COLLATE "C" !~ '^[A-Za-z0-9._:-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  PERFORM private.strength_week_lock_owner(p_user_id);
  -- Owned operation replay precedes the NEW transition current==expected guard.
  SELECT v.* INTO s FROM private.strength_week_scopes AS v
    WHERE v.user_id=p_user_id AND v.open_operation_namespace=p_operation_namespace
      AND v.open_operation_key=p_operation_key FOR UPDATE;
  IF FOUND THEN
    IF s.predecessor_generation IS DISTINCT FROM p_expected_generation THEN
      RAISE EXCEPTION 'strength_week_operation_conflict' USING ERRCODE='40001';
    END IF;
    IF s.closed_at IS NOT NULL THEN RAISE EXCEPTION 'strength_week_scope_closed' USING ERRCODE='40001'; END IF;
  ELSE
    SELECT v.* INTO current_scope FROM private.strength_week_scopes AS v
      WHERE v.user_id=p_user_id AND v.closed_at IS NULL FOR UPDATE;
    IF NOT FOUND OR current_scope.generation IS DISTINCT FROM p_expected_generation THEN
      RAISE EXCEPTION 'strength_week_generation_changed' USING ERRCODE='40001';
    END IF;
    at:=pg_catalog.clock_timestamp();
    UPDATE private.strength_week_scopes SET closed_at=at
      WHERE user_id=p_user_id AND generation=p_expected_generation AND closed_at IS NULL;
    INSERT INTO private.strength_week_scopes(user_id,predecessor_generation,
      open_operation_namespace,open_operation_key,opened_at)
      VALUES(p_user_id,p_expected_generation,p_operation_namespace,p_operation_key,at) RETURNING * INTO s;
  END IF;
  RETURN pg_catalog.jsonb_build_object('user_id',s.user_id,'generation',s.generation,
    'predecessor_generation',s.predecessor_generation,
    'opened_at',pg_catalog.to_char(s.opened_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'closed_at',NULL);
END;
$fn$;

CREATE FUNCTION private.capture_strength_week_source_at(
  p_user_id uuid,p_expected_generation uuid,p_source_kind text,p_fact text,p_planned_days smallint,
  p_source_entity_id uuid,p_source_valid_until timestamptz,p_operation_namespace text,p_operation_key text,
  p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE s private.strength_week_scopes; v private.strength_week_source_versions;
  zone text; local_monday date; matches_source boolean;
BEGIN
  IF p_expected_generation IS NULL OR p_source_kind IS NULL OR p_fact IS NULL
    OR p_source_kind NOT IN ('accepted_plan','informed_frequency') OR p_fact NOT IN ('value','absent')
    OR p_operation_namespace IS NULL OR p_operation_key IS NULL
    OR p_operation_namespace COLLATE "C" !~ '^[a-z][a-z0-9_.:-]{0,63}$'
    OR p_operation_key COLLATE "C" !~ '^[A-Za-z0-9._:-]{8,128}$'
    OR p_observed_at IS NULL OR NOT pg_catalog.isfinite(p_observed_at)
    OR pg_catalog.date_part('year',p_observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
    OR (p_source_valid_until IS NOT NULL AND
      (NOT pg_catalog.isfinite(p_source_valid_until)
       OR pg_catalog.date_part('year',p_source_valid_until AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999))
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  IF (p_fact='absent' AND (p_planned_days IS NOT NULL OR p_source_entity_id IS NOT NULL OR p_source_valid_until IS NOT NULL))
    OR (p_fact='value' AND (p_planned_days IS NULL
      OR (p_source_kind='accepted_plan' AND (p_planned_days NOT BETWEEN 1 AND 7 OR p_source_entity_id IS NULL))
      OR (p_source_kind='informed_frequency' AND
        (p_planned_days NOT BETWEEN 0 AND 7 OR p_source_entity_id IS NOT NULL OR p_source_valid_until IS NOT NULL))))
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  zone:=private.strength_week_lock_owner(p_user_id);
  SELECT a.* INTO s FROM private.strength_week_scopes AS a
    WHERE a.user_id=p_user_id AND a.closed_at IS NULL FOR UPDATE;
  IF NOT FOUND OR s.generation IS DISTINCT FROM p_expected_generation THEN
    RAISE EXCEPTION 'strength_week_generation_changed' USING ERRCODE='40001';
  END IF;
  SELECT a.* INTO v FROM private.strength_week_source_versions AS a
    WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.source_kind=p_source_kind
      AND a.operation_namespace=p_operation_namespace AND a.operation_key=p_operation_key;
  IF FOUND THEN
    IF v.fact IS DISTINCT FROM p_fact OR v.planned_days IS DISTINCT FROM p_planned_days
      OR v.source_entity_id IS DISTINCT FROM p_source_entity_id
      OR v.source_valid_until IS DISTINCT FROM p_source_valid_until
    THEN RAISE EXCEPTION 'strength_week_operation_conflict' USING ERRCODE='40001'; END IF;
    RETURN private.strength_week_source_wire(v);
  END IF;
  IF p_observed_at < s.opened_at OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=zone)
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  IF p_source_kind='accepted_plan' THEN
    IF p_fact='value' THEN
      SELECT EXISTS(SELECT 1 FROM public.training_plans AS p
        WHERE p.id=p_source_entity_id AND p.user_id=p_user_id AND p.active
          AND p.days_per_week=p_planned_days AND p.valid_until IS NOT DISTINCT FROM p_source_valid_until)
      INTO matches_source;
    ELSE
      SELECT NOT EXISTS(SELECT 1 FROM public.training_plans AS p
        WHERE p.user_id=p_user_id AND p.active) INTO matches_source;
    END IF;
  ELSE
    SELECT EXISTS(SELECT 1 FROM public.user_profiles AS p
      WHERE p.user_id=p_user_id AND p.training_frequency IS NOT DISTINCT FROM p_planned_days)
    INTO matches_source;
  END IF;
  IF NOT matches_source THEN
    RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023';
  END IF;
  local_monday:=pg_catalog.date_trunc('week',p_observed_at AT TIME ZONE zone)::date+7;
  IF local_monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
    RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023';
  END IF;
  INSERT INTO private.strength_week_source_versions(user_id,generation,source_kind,fact,planned_days,
    source_entity_id,source_valid_until,operation_namespace,operation_key,
    observed_at,observed_timezone,effective_week_start)
  VALUES(p_user_id,p_expected_generation,p_source_kind,p_fact,p_planned_days,
    p_source_entity_id,p_source_valid_until,p_operation_namespace,p_operation_key,
    p_observed_at,zone,local_monday) RETURNING * INTO v;
  RETURN private.strength_week_source_wire(v);
END;
$fn$;

CREATE FUNCTION private.capture_strength_week_source(
  p_user_id uuid,p_expected_generation uuid,p_source_kind text,p_fact text,p_planned_days smallint,
  p_source_entity_id uuid,p_source_valid_until timestamptz,p_operation_namespace text,p_operation_key text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE at timestamptz;
BEGIN
  PERFORM private.strength_week_lock_owner(p_user_id);
  PERFORM 1 FROM private.strength_week_scopes AS s
    WHERE s.user_id=p_user_id AND s.closed_at IS NULL FOR UPDATE;
  at:=pg_catalog.clock_timestamp();
  RETURN private.capture_strength_week_source_at(p_user_id,p_expected_generation,p_source_kind,p_fact,
    p_planned_days,p_source_entity_id,p_source_valid_until,p_operation_namespace,p_operation_key,at);
END;
$fn$;

CREATE FUNCTION private.freeze_mobile_strength_week_target_at(
  p_user_id uuid,p_expected_generation uuid,p_expected_timezone text,p_expected_week_start date,
  p_source_proof jsonb,p_proposal jsonb,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path = pg_catalog AS $fn$
DECLARE s private.strength_week_scopes; zone text; monday date; context_result jsonb; context jsonb;
  t private.strength_week_targets; p private.strength_week_source_versions;
  f private.strength_week_source_versions; new_id uuid; final_wire jsonb; proof jsonb;
  proposal jsonb; plan_ref uuid; frequency_ref uuid;
BEGIN
  IF p_expected_generation IS NULL OR p_expected_timezone IS NULL
    OR pg_catalog.length(pg_catalog.btrim(p_expected_timezone))=0
    OR p_expected_week_start IS NULL OR NOT pg_catalog.isfinite(p_expected_week_start)
    OR p_expected_week_start NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    OR pg_catalog.date_part('isodow',p_expected_week_start::timestamp)<>1
    OR p_observed_at IS NULL OR NOT pg_catalog.isfinite(p_observed_at)
    OR pg_catalog.date_part('year',p_observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
    OR NOT private.strength_week_freeze_shape(p_source_proof,p_proposal)
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  zone:=private.strength_week_lock_owner(p_user_id);
  SELECT a.* INTO s FROM private.strength_week_scopes AS a
    WHERE a.user_id=p_user_id AND a.closed_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    IF EXISTS(SELECT 1 FROM private.strength_week_scopes AS a
      WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.closed_at IS NOT NULL)
    THEN RETURN pg_catalog.jsonb_build_object('status','conflict','reason','generation_changed'); END IF;
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','missing_scope');
  END IF;
  IF s.generation<>p_expected_generation THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','generation_changed');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=zone) THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported');
  END IF;
  monday:=pg_catalog.date_trunc('week',p_observed_at AT TIME ZONE zone)::date;
  IF monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported');
  END IF;
  IF zone<>p_expected_timezone THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','timezone_changed');
  END IF;
  IF monday<>p_expected_week_start THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','week_changed');
  END IF;
  -- Existing durable fact wins before proof/proposal SEMANTICS or later sources.
  SELECT a.* INTO t FROM private.strength_week_targets AS a
    WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.week_start=monday;
  IF FOUND THEN
    SELECT a.* INTO p FROM private.strength_week_source_versions AS a
      WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.source_version_id=t.plan_source_version_id;
    SELECT a.* INTO f FROM private.strength_week_source_versions AS a
      WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.source_version_id=t.frequency_source_version_id;
    RETURN pg_catalog.jsonb_build_object('status','reused','target',private.strength_week_target_wire(t,p,f));
  END IF;
  context_result:=private.strength_week_context_snapshot(p_user_id,p_observed_at);
  IF context_result->>'status'='unavailable' THEN RETURN context_result; END IF;
  context:=context_result->'context';
  IF context->>'kind' IS DISTINCT FROM 'source_facts' THEN
    RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE='XX001';
  END IF;
  proof:=context->'source_proof';
  IF proof IS DISTINCT FROM p_source_proof THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','source_proof_changed');
  END IF;
  plan_ref:=(proof#>>'{plan,source_version_id}')::uuid;
  frequency_ref:=(proof#>>'{frequency,source_version_id}')::uuid;
  IF context#>>'{plan,receipt,fact}'='value' THEN
    proposal:=pg_catalog.jsonb_build_object('source','accepted_plan',
      'planned_days',context#>'{plan,receipt,planned_days}','source_key',plan_ref);
  ELSIF context#>>'{frequency,receipt,fact}'='value' THEN
    proposal:=pg_catalog.jsonb_build_object('source','informed_frequency',
      'planned_days',context#>'{frequency,receipt,planned_days}','source_key',frequency_ref);
  ELSE
    proposal:=pg_catalog.jsonb_build_object('source','absent','planned_days',NULL,'source_key',NULL);
  END IF;
  IF proposal IS DISTINCT FROM p_proposal THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','proposal_mismatch');
  END IF;
  INSERT INTO private.strength_week_targets(user_id,generation,week_start,timezone_at_freeze,
    planned_days,source,plan_source_version_id,frequency_source_version_id,frozen_at)
  VALUES(p_user_id,p_expected_generation,monday,zone,(proposal->>'planned_days')::smallint,
    proposal->>'source',plan_ref,frequency_ref,p_observed_at)
  ON CONFLICT (user_id,generation,week_start) DO NOTHING RETURNING target_id INTO new_id;
  -- Fresh READ COMMITTED statement: read the stored winner, never echo proposal.
  SELECT private.strength_week_target_wire(a,pv,fv) INTO final_wire
    FROM private.strength_week_targets AS a
    LEFT JOIN private.strength_week_source_versions AS pv
      ON pv.user_id=a.user_id AND pv.generation=a.generation AND pv.source_version_id=a.plan_source_version_id
    LEFT JOIN private.strength_week_source_versions AS fv
      ON fv.user_id=a.user_id AND fv.generation=a.generation AND fv.source_version_id=a.frequency_source_version_id
    WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.week_start=monday;
  IF final_wire IS NULL THEN
    RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE='XX001';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',CASE WHEN new_id IS NULL THEN 'reused' ELSE 'frozen' END,
    'target',final_wire);
END;
$fn$;

CREATE FUNCTION public.freeze_mobile_strength_week_target(
  p_user_id uuid,p_expected_generation uuid,p_expected_timezone text,p_expected_week_start date,
  p_source_proof jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $fn$
DECLARE at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_expected_generation IS NULL OR p_expected_timezone IS NULL
    OR pg_catalog.length(pg_catalog.btrim(p_expected_timezone))=0
    OR p_expected_week_start IS NULL OR NOT pg_catalog.isfinite(p_expected_week_start)
    OR p_expected_week_start NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    OR pg_catalog.date_part('isodow',p_expected_week_start::timestamp)<>1
    OR NOT private.strength_week_freeze_shape(p_source_proof,p_proposal)
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  -- C59A2_PRE_OWNER_LOCK_PUBLIC_FREEZE: future installed-private observation
  -- may be inserted HERE, before the first exclusive owner lock, never after.
  PERFORM private.strength_week_lock_owner(p_user_id);
  PERFORM 1 FROM private.strength_week_scopes AS s
    WHERE s.user_id=p_user_id AND s.closed_at IS NULL FOR UPDATE;
  at:=pg_catalog.clock_timestamp();
  RETURN private.freeze_mobile_strength_week_target_at(p_user_id,p_expected_generation,
    p_expected_timezone,p_expected_week_start,p_source_proof,p_proposal,at);
END;
$fn$;

-- Exact new-object ACL only; never schema-wide/default/old-object changes.
REVOKE ALL ON FUNCTION private.strength_week_json_keys(jsonb,text[]) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.strength_week_freeze_shape(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.strength_week_source_wire(private.strength_week_source_versions) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.strength_week_proof_wire(uuid,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.strength_week_target_wire(private.strength_week_targets,private.strength_week_source_versions,private.strength_week_source_versions) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.strength_week_lock_owner(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.strength_week_context_snapshot(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.get_mobile_strength_week_context_at(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.open_strength_week_scope(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.roll_strength_week_scope(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.capture_strength_week_source_at(uuid,uuid,text,text,smallint,uuid,timestamptz,text,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.capture_strength_week_source(uuid,uuid,text,text,smallint,uuid,timestamptz,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.freeze_mobile_strength_week_target_at(uuid,uuid,text,date,jsonb,jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_mobile_strength_week_context(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.freeze_mobile_strength_week_target(uuid,uuid,text,date,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_strength_week_context(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.freeze_mobile_strength_week_target(uuid,uuid,text,date,jsonb,jsonb) TO service_role;
COMMIT;

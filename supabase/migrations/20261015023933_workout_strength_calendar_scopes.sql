-- Dormant current-calendar observation only; no workout coverage or caller activation.
-- CREATE-only: neither a reserved relation nor any RPC overload may be overwritten.
DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('private.workout_strength_calendar_scopes') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='prepare_workout_strength_calendar_scope') THEN
    RAISE EXCEPTION 'workout_strength_calendar_scopes_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
  IF pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_calendar_scopes_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
END $preflight$;

CREATE TABLE private.workout_strength_calendar_scopes (
  user_id uuid NOT NULL,
  lifecycle_key uuid NOT NULL,
  scope_key uuid NOT NULL,
  time_zone text COLLATE "C" NOT NULL CHECK (time_zone<>''),
  week_start_date date NOT NULL CHECK (
    pg_catalog.isfinite(week_start_date)
    AND week_start_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    AND EXTRACT(ISODOW FROM week_start_date)=1
  ),
  as_of_local_date date NOT NULL CHECK (
    pg_catalog.isfinite(as_of_local_date)
    AND as_of_local_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    AND CASE WHEN pg_catalog.isfinite(week_start_date) AND pg_catalog.isfinite(as_of_local_date)
      AND week_start_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
      AND as_of_local_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
      THEN as_of_local_date-week_start_date BETWEEN 0 AND 6 ELSE false END
  ),
  created_at timestamptz NOT NULL CHECK (
    pg_catalog.isfinite(created_at)
    AND EXTRACT(YEAR FROM (created_at AT TIME ZONE 'UTC')) BETWEEN 1 AND 9999
  ),
  PRIMARY KEY(user_id,lifecycle_key,scope_key),
  UNIQUE(user_id,lifecycle_key,time_zone,week_start_date,as_of_local_date),
  FOREIGN KEY(user_id,lifecycle_key)
    REFERENCES private.workout_strength_lifecycles(user_id,lifecycle_key) ON DELETE CASCADE
);
ALTER TABLE private.workout_strength_calendar_scopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.workout_strength_calendar_scopes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.prepare_workout_strength_calendar_scope(
  p_user_id uuid,p_expected_lifecycle_key uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $prepare$
DECLARE
  official_zone text;
  observed_at timestamptz;
  local_clock timestamp;
  local_date date;
  monday date;
  calendar_scope private.workout_strength_calendar_scopes%ROWTYPE;
  result_status text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_expected_lifecycle_key IS NULL THEN
    RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  SELECT u.timezone INTO official_zone FROM public.users u
    WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
  END IF;
  PERFORM 1 FROM private.workout_strength_lifecycles l
    WHERE l.user_id=p_user_id AND l.lifecycle_key=p_expected_lifecycle_key AND l.closed_at IS NULL;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle');
  END IF;

  -- One post-lock clock and the locked account's literal current database zone.
  observed_at:=pg_catalog.clock_timestamp();
  IF official_zone IS NULL OR official_zone=''
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z
      WHERE (z.name COLLATE "C")=(official_zone COLLATE "C")) THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','zone_unproved');
  END IF;
  IF NOT pg_catalog.isfinite(observed_at)
    OR EXTRACT(YEAR FROM (observed_at AT TIME ZONE 'UTC')) NOT BETWEEN 1 AND 9999 THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved');
  END IF;
  local_clock:=observed_at AT TIME ZONE official_zone;
  IF NOT pg_catalog.isfinite(local_clock) OR EXTRACT(YEAR FROM local_clock) NOT BETWEEN 1 AND 9999 THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved');
  END IF;
  local_date:=local_clock::date;
  monday:=local_date-(EXTRACT(ISODOW FROM local_date)::integer-1);
  IF NOT pg_catalog.isfinite(local_date) OR NOT pg_catalog.isfinite(monday)
    OR local_date NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    OR monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved');
  END IF;

  SELECT s.* INTO calendar_scope FROM private.workout_strength_calendar_scopes s
    WHERE s.user_id=p_user_id AND s.lifecycle_key=p_expected_lifecycle_key
      AND s.time_zone=(official_zone COLLATE "C")
      AND s.week_start_date=monday AND s.as_of_local_date=local_date;
  IF FOUND THEN
    result_status:='reuse_existing';
  ELSE
    INSERT INTO private.workout_strength_calendar_scopes(
      user_id,lifecycle_key,scope_key,time_zone,week_start_date,as_of_local_date,created_at
    ) VALUES (
      p_user_id,p_expected_lifecycle_key,pg_catalog.gen_random_uuid(),official_zone,monday,local_date,observed_at
    ) RETURNING * INTO calendar_scope;
    result_status:='prepared';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',result_status,'scope',pg_catalog.jsonb_build_object(
    'ownerID',calendar_scope.user_id,'lifecycleKey',calendar_scope.lifecycle_key,'scopeKey',calendar_scope.scope_key,
    'timeZone',calendar_scope.time_zone,'weekStartDate',pg_catalog.to_char(calendar_scope.week_start_date,'YYYY-MM-DD'),
    'asOfLocalDate',pg_catalog.to_char(calendar_scope.as_of_local_date,'YYYY-MM-DD')
  ));
END;
$prepare$;
REVOKE ALL ON FUNCTION public.prepare_workout_strength_calendar_scope(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_workout_strength_calendar_scope(uuid,uuid) TO service_role;

-- Unknown default privileges must fail closed, never widen this new backend surface.
DO $privileges$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
    WHERE c.oid='private.workout_strength_calendar_scopes'::regclass AND a.grantee<>c.relowner)
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
      WHERE p.oid='public.prepare_workout_strength_calendar_scope(uuid,uuid)'::regprocedure
        AND a.grantee NOT IN(p.proowner,'service_role'::regrole::oid)) THEN
    RAISE EXCEPTION 'workout_strength_calendar_scopes_unexpected_privileges' USING ERRCODE='42501';
  END IF;
END $privileges$;
COMMENT ON FUNCTION public.prepare_workout_strength_calendar_scope(uuid,uuid) IS
  'Backend-only persisted current calendar observation for an existing owned open lifecycle; not historical workout coverage.';

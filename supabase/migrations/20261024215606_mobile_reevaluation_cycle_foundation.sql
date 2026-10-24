-- Dormant cycle authority. No routes, media, clinical answers, completion or jobs.
-- Existing signup/reset/weekly/WhatsApp writers are not replaced or called.
BEGIN;
SET LOCAL search_path = pg_catalog;
DO $preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL
    OR to_regclass('private.mobile_signup_strength_request_admissions') IS NULL
    OR to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR to_regclass('private.strength_week_source_versions') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
END $preflight$;

CREATE TABLE private.mobile_reevaluation_cycles (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  signup_generation uuid NOT NULL,
  signup_epoch uuid NOT NULL,
  cycle_id uuid NOT NULL DEFAULT gen_random_uuid(),
  revision bigint NOT NULL DEFAULT 1 CHECK(revision > 0),
  kind text NOT NULL CHECK(kind IN('REGULAR')),
  base_date date NOT NULL,
  due_date date NOT NULL,
  timezone_at_open text NOT NULL CHECK(length(timezone_at_open)>0),
  status text NOT NULL CHECK(status IN('open','collecting','review_ready','completed','invalidated')),
  opened_at timestamptz NOT NULL CHECK(isfinite(opened_at)),
  completed_at timestamptz,
  invalidated_at timestamptz,
  PRIMARY KEY(cycle_id),
  UNIQUE(user_id,signup_generation,cycle_id),
  FOREIGN KEY(user_id,signup_generation)
    REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) ON DELETE NO ACTION,
  CHECK(isfinite(base_date) AND base_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-17'
    AND due_date=base_date+14),
  CHECK((status='completed')=(completed_at IS NOT NULL)),
  CHECK(completed_at IS NULL OR (isfinite(completed_at) AND completed_at>=opened_at)),
  CHECK((status='invalidated')=(invalidated_at IS NOT NULL)),
  CHECK(invalidated_at IS NULL OR (isfinite(invalidated_at) AND invalidated_at>=opened_at))
);
CREATE UNIQUE INDEX mobile_reevaluation_one_open_owner ON private.mobile_reevaluation_cycles(user_id)
  WHERE status IN('open','collecting','review_ready');

CREATE TABLE private.mobile_reevaluation_start_keys (
  user_id uuid NOT NULL,
  idempotency_key uuid NOT NULL,
  signup_generation uuid NOT NULL,
  cycle_id uuid NOT NULL,
  created_at timestamptz NOT NULL CHECK(isfinite(created_at)),
  PRIMARY KEY(user_id,idempotency_key),
  FOREIGN KEY(user_id,signup_generation,cycle_id)
    REFERENCES private.mobile_reevaluation_cycles(user_id,signup_generation,cycle_id) ON DELETE CASCADE
);
ALTER TABLE private.mobile_reevaluation_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_reevaluation_start_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_reevaluation_cycles,private.mobile_reevaluation_start_keys
  FROM PUBLIC,anon,authenticated,service_role;

-- Match the first row lock used by strength_week_lock_owner. Do not request
-- workout/admission locks after it, or initialize any of their authority.
CREATE FUNCTION private.mobile_reevaluation_lock_owner(p_user_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_input' USING ERRCODE='22023';
  END IF;
  IF current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_reevaluation_patient_not_found' USING ERRCODE='P0002';
  END IF;
END $$;

CREATE FUNCTION private.mobile_reevaluation_cycle_wire(p_row private.mobile_reevaluation_cycles)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT jsonb_build_object('id',(p_row).cycle_id,'signup_generation',(p_row).signup_generation,
    'revision',(p_row).revision::text,'kind',(p_row).kind,'status',(p_row).status,
    'base_date',to_char((p_row).base_date::timestamp,'YYYY-MM-DD'),
    'due_date',to_char((p_row).due_date::timestamp,'YYYY-MM-DD'),
    'timezone_at_open',(p_row).timezone_at_open,
    'opened_at',to_char((p_row).opened_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

-- Explicit time is private/test-only. All public entrypoints pass NULL, after
-- acquiring the owner lock. Completion must later supply its own typed receipt;
-- neither a legacy reevaluations row nor a bare completed status is such proof.
CREATE FUNCTION private.mobile_reevaluation_context_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE
  observed_at timestamptz; profile public.user_profiles%ROWTYPE;
  receipt private.mobile_signup_strength_completion_receipts%ROWTYPE;
  source private.strength_week_source_versions%ROWTYPE;
  scope private.strength_week_scopes%ROWTYPE;
  admission private.mobile_signup_strength_request_admissions%ROWTYPE;
  current_epoch uuid; cycle private.mobile_reevaluation_cycles%ROWTYPE;
  zone text; base_day date; due_day date; reason text; cycle_wire jsonb := 'null';
BEGIN
  PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
  observed_at:=COALESCE(p_observed_at,clock_timestamp());
  IF NOT isfinite(observed_at) OR date_part('year',observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_input' USING ERRCODE='22023';
  END IF;
  SELECT p.* INTO profile FROM public.user_profiles p WHERE p.user_id=p_user_id;
  IF NOT FOUND OR profile.onboarding_completed IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('reason','onboarding_incomplete');
  END IF;
  IF profile.onboarding_completed_at IS NULL THEN
    RETURN jsonb_build_object('reason','anchor_unproven');
  END IF;
  SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
  SELECT r.* INTO receipt FROM private.mobile_signup_strength_completion_receipts r
    WHERE r.user_id=p_user_id AND r.epoch=current_epoch AND r.outcome='first_fresh'
      AND r.completed_at=profile.onboarding_completed_at;
  IF NOT FOUND THEN RETURN jsonb_build_object('reason','anchor_unproven'); END IF;
  SELECT a.* INTO admission FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=receipt.admission_id;
  SELECT s.* INTO scope FROM private.strength_week_scopes s
    WHERE s.user_id=p_user_id AND s.generation=receipt.generation;
  SELECT s.* INTO source FROM private.strength_week_source_versions s
    WHERE s.user_id=p_user_id AND s.generation=receipt.generation
      AND s.source_version_id=receipt.frequency_source_version_id;
  IF admission.admission_id IS NULL OR admission.epoch IS DISTINCT FROM receipt.epoch
    OR scope.generation IS NULL OR scope.predecessor_generation IS NOT NULL
    OR scope.open_operation_namespace IS DISTINCT FROM 'mobile_signup_completion_v1'
    OR scope.open_operation_key IS DISTINCT FROM receipt.admission_id::text
    OR source.source_version_id IS NULL OR source.source_kind IS DISTINCT FROM 'informed_frequency'
    OR source.fact IS DISTINCT FROM 'value' OR source.planned_days NOT BETWEEN 0 AND 7
    OR source.source_entity_id IS NOT NULL OR source.source_valid_until IS NOT NULL
    OR source.operation_namespace IS DISTINCT FROM 'mobile_signup_completion_v1'
    OR source.operation_key IS DISTINCT FROM receipt.admission_id::text
    OR NOT(admission.admitted_at<=receipt.completed_at AND receipt.completed_at<=scope.opened_at
      AND scope.opened_at<=source.observed_at AND source.observed_at<=receipt.recorded_at
      AND receipt.recorded_at<=observed_at)
    OR (receipt.completion_result->>'completed_at')::timestamptz IS DISTINCT FROM receipt.completed_at
    OR receipt.completion_result->>'user_id' IS DISTINCT FROM p_user_id::text
    OR receipt.completion_result->'onboarding_completed' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001';
  END IF;
  zone:=source.observed_timezone;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
    RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001';
  END IF;
  base_day:=(receipt.completed_at AT TIME ZONE zone)::date;
  IF base_day NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-17' THEN
    RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001';
  END IF;
  due_day:=base_day+14;
  IF EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles c WHERE c.user_id=p_user_id
    AND c.signup_generation=receipt.admission_id AND c.status='completed') THEN
    RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001';
  END IF;
  SELECT c.* INTO cycle FROM private.mobile_reevaluation_cycles c WHERE c.user_id=p_user_id
    AND c.signup_generation=receipt.admission_id AND c.status IN('open','collecting','review_ready');
  IF FOUND THEN
    IF cycle.signup_epoch IS DISTINCT FROM current_epoch OR cycle.base_date IS DISTINCT FROM base_day
      OR cycle.due_date IS DISTINCT FROM due_day OR cycle.timezone_at_open IS DISTINCT FROM zone
      OR cycle.opened_at>observed_at THEN
      RAISE EXCEPTION 'mobile_reevaluation_cycle_corrupt' USING ERRCODE='XX001';
    END IF;
    cycle_wire:=private.mobile_reevaluation_cycle_wire(cycle);
  END IF;
  reason:=CASE WHEN (observed_at AT TIME ZONE zone)::date<due_day THEN 'not_due' ELSE NULL END;
  RETURN jsonb_build_object('reason',reason,'signup_generation',receipt.admission_id,
    'signup_epoch',current_epoch,'observed_at',observed_at,
    'clock',jsonb_build_object('base_date',to_char(base_day::timestamp,'YYYY-MM-DD'),
      'due_date',to_char(due_day::timestamp,'YYYY-MM-DD'),'timezone',zone),'cycle',cycle_wire);
END $$;

CREATE FUNCTION private.mobile_reevaluation_state(p_context jsonb) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT jsonb_build_object('version',1,
    'availability',CASE WHEN p_context->>'reason' IS NULL THEN 'available' ELSE 'unavailable' END,
    'unavailable_reason',p_context->'reason',
    'clock',coalesce(p_context->'clock','null'::jsonb),'cycle',coalesce(p_context->'cycle','null'::jsonb))
$$;

CREATE FUNCTION private.mobile_reevaluation_clock_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT private.mobile_reevaluation_state(private.mobile_reevaluation_context_at(p_user_id,p_observed_at))
$$;

CREATE FUNCTION public.get_mobile_reevaluation_cycle(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  RETURN private.mobile_reevaluation_clock_at(p_user_id,NULL);
END $$;

CREATE FUNCTION private.start_mobile_reevaluation_cycle_at(
  p_user_id uuid,p_idempotency_key uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; previous private.mobile_reevaluation_start_keys%ROWTYPE;
  cycle private.mobile_reevaluation_cycles%ROWTYPE; observed_at timestamptz;
  generation_id uuid; epoch_id uuid;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_input' USING ERRCODE='22023';
  END IF;
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  generation_id:=(context->>'signup_generation')::uuid;
  epoch_id:=(context->>'signup_epoch')::uuid;
  SELECT k.* INTO previous FROM private.mobile_reevaluation_start_keys k
    WHERE k.user_id=p_user_id AND k.idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF previous.signup_generation IS DISTINCT FROM generation_id
      OR previous.cycle_id::text IS DISTINCT FROM context#>>'{cycle,id}' THEN
      RAISE EXCEPTION 'mobile_reevaluation_generation_changed' USING ERRCODE='40001';
    END IF;
    RETURN private.mobile_reevaluation_state(context);
  END IF;
  IF context->>'reason' IS NOT NULL THEN RETURN private.mobile_reevaluation_state(context); END IF;
  observed_at:=(context->>'observed_at')::timestamptz;
  IF context->'cycle'='null'::jsonb THEN
    -- A legitimate new signup cannot inherit a stale occurrence. Reset itself
    -- remains unchanged; no historical cycle or receipt is erased here.
    UPDATE private.mobile_reevaluation_cycles SET status='invalidated',
      revision=revision+1,invalidated_at=observed_at
      WHERE user_id=p_user_id AND signup_generation<>generation_id
        AND status IN('open','collecting','review_ready');
    INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,
      kind,base_date,due_date,timezone_at_open,status,opened_at)
      VALUES(p_user_id,generation_id,epoch_id,'REGULAR',(context#>>'{clock,base_date}')::date,
        (context#>>'{clock,due_date}')::date,context#>>'{clock,timezone}','open',observed_at)
      RETURNING * INTO cycle;
    context:=jsonb_set(context,'{cycle}',private.mobile_reevaluation_cycle_wire(cycle));
  END IF;
  INSERT INTO private.mobile_reevaluation_start_keys(user_id,idempotency_key,signup_generation,cycle_id,created_at)
    VALUES(p_user_id,p_idempotency_key,generation_id,(context#>>'{cycle,id}')::uuid,observed_at);
  RETURN private.mobile_reevaluation_state(context);
END $$;

-- The public writer never accepts a client clock. The same private core allows
-- deterministic local reset/concurrency qualification without clock overrides.
CREATE FUNCTION public.start_mobile_reevaluation_cycle(p_user_id uuid,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.start_mobile_reevaluation_cycle_at(p_user_id,p_idempotency_key,NULL::timestamptz)
$$;

REVOKE ALL ON FUNCTION private.mobile_reevaluation_lock_owner(uuid),
  private.mobile_reevaluation_cycle_wire(private.mobile_reevaluation_cycles),
  private.mobile_reevaluation_context_at(uuid,timestamptz),private.mobile_reevaluation_state(jsonb),
  private.mobile_reevaluation_clock_at(uuid,timestamptz),
  private.start_mobile_reevaluation_cycle_at(uuid,uuid,timestamptz),
  public.get_mobile_reevaluation_cycle(uuid),public.start_mobile_reevaluation_cycle(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_reevaluation_cycle(uuid),
  public.start_mobile_reevaluation_cycle(uuid,uuid) TO service_role;
COMMIT;

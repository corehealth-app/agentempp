-- Honest first legacy assessment: immediately due from its present admission,
-- never a fabricated earlier fortnight. No BFF/native activation or photo/FULL
-- completion bypass: those surfaces must be integrated before release.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_generation_sources') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_transition_requires_sources' USING ERRCODE='42501'; END IF;
END $preflight$;
ALTER TABLE private.mobile_reevaluation_cycles DROP CONSTRAINT mobile_reevaluation_cycles_kind_check;
ALTER TABLE private.mobile_reevaluation_cycles ADD CONSTRAINT mobile_reevaluation_cycles_kind_check
 CHECK(kind IN('REGULAR','EARLY_FULL','SAFETY','TRANSITION_FULL'));
DO $calendar_shape$
DECLARE ids oid[]; name text;
BEGIN
 SELECT array_agg(c.oid) INTO ids FROM pg_constraint c
  WHERE c.conrelid='private.mobile_reevaluation_cycles'::regclass AND c.contype='c'
   AND pg_get_constraintdef(c.oid) LIKE '%due_date%';
 IF cardinality(ids) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'unknown_mobile_reevaluation_calendar_check' USING ERRCODE='XX001'; END IF;
 SELECT conname INTO name FROM pg_constraint WHERE oid=ids[1];
 EXECUTE format('ALTER TABLE private.mobile_reevaluation_cycles DROP CONSTRAINT %I',name);
 EXECUTE format('ALTER TABLE private.mobile_reevaluation_cycles ADD CONSTRAINT %I CHECK(isfinite(base_date) AND base_date BETWEEN DATE ''0001-01-01'' AND DATE ''9999-12-17'' AND due_date=base_date+CASE WHEN kind=''TRANSITION_FULL'' THEN 0 ELSE 14 END)',name);
 SELECT array_agg(c.oid) INTO ids FROM pg_constraint c
  WHERE c.conrelid='private.mobile_clinical_start_requests'::regclass AND c.contype='c'
   AND pg_get_constraintdef(c.oid) LIKE '%requested_kind%' AND pg_get_constraintdef(c.oid) LIKE '%REGULAR%';
 IF cardinality(ids) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'unknown_mobile_clinical_start_kind_check' USING ERRCODE='XX001'; END IF;
 SELECT conname INTO name FROM pg_constraint WHERE oid=ids[1];
 EXECUTE format('ALTER TABLE private.mobile_clinical_start_requests DROP CONSTRAINT %I',name);
 EXECUTE format('ALTER TABLE private.mobile_clinical_start_requests ADD CONSTRAINT %I CHECK(requested_kind IN(''REGULAR'',''EARLY_FULL'',''TRANSITION_FULL''))',name);
END $calendar_shape$;
CREATE OR REPLACE FUNCTION private.mobile_clinical_calendar_base_at(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_signup_at timestamptz,p_signup_zone text,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE r private.mobile_clinical_full_receipts%ROWTYPE; c private.mobile_reevaluation_cycles%ROWTYPE;
 base_day date:=(p_signup_at AT TIME ZONE p_signup_zone)::date; zone text:=p_signup_zone;
 last_id uuid; last_at timestamptz:=p_signup_at; known_cycles integer:=0;
 initial private.mobile_clinical_legacy_admissions%ROWTYPE; legacy boolean;
BEGIN
 SELECT * INTO initial FROM private.mobile_clinical_legacy_admissions
  WHERE user_id=p_user_id AND generation=p_generation AND epoch=p_epoch;
 legacy:=FOUND;
 IF legacy AND (initial.admitted_at IS DISTINCT FROM p_signup_at
  OR initial.timezone_at_admission IS DISTINCT FROM p_signup_zone) THEN
  RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001'; END IF;
 FOR r IN SELECT x.* FROM private.mobile_clinical_full_receipts x
  WHERE x.user_id=p_user_id AND x.signup_generation=p_generation AND x.signup_epoch=p_epoch
   AND x.kind<>'ROUTINE_REVIEW' ORDER BY x.review_no LOOP
  IF (r.kind='TRANSITION_FULL' AND (NOT legacy OR known_cycles<>0 OR last_id IS NOT NULL))
   OR (legacy AND known_cycles=0 AND r.kind<>'TRANSITION_FULL') THEN
   RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001'; END IF;
  SELECT * INTO c FROM private.mobile_reevaluation_cycles WHERE user_id=p_user_id AND cycle_id=r.cycle_id;
  IF c.cycle_id IS NULL OR c.signup_generation<>p_generation OR c.signup_epoch<>p_epoch
   OR c.kind<>r.kind OR c.status<>'completed' OR c.completed_at<>r.completed_at
   OR c.revision<>r.final_cycle_revision OR c.base_date<>r.base_before
   OR c.due_date<>(r.base_before+(CASE WHEN r.kind='TRANSITION_FULL' THEN 0 ELSE 14 END))
   OR c.timezone_at_open<>zone OR r.previous_full_id IS DISTINCT FROM last_id OR r.base_before<>base_day
   OR r.completed_at<last_at OR r.completed_at>p_observed_at
   OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=r.timezone_at_completion)
   OR r.base_after IS DISTINCT FROM (r.completed_at AT TIME ZONE r.timezone_at_completion)::date
   OR (r.kind='REGULAR' AND r.base_after<base_day+14) THEN
   RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001';
  END IF;
  base_day:=r.base_after;zone:=r.timezone_at_completion;last_id:=r.review_id;last_at:=r.completed_at;
  known_cycles:=known_cycles+1;
 END LOOP;
 IF known_cycles<>(SELECT count(*) FROM private.mobile_reevaluation_cycles
  WHERE user_id=p_user_id AND signup_generation=p_generation AND status='completed')
  OR base_day NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-17' THEN
  RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001';
 END IF;
 RETURN jsonb_build_object('base_date',base_day,'timezone',zone,'last_full_id',last_id,
  'first_transition_pending',legacy AND last_id IS NULL);
END $$;

CREATE FUNCTION private.mobile_legacy_reevaluation_context_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE authority jsonb; calendar jsonb; cycle private.mobile_reevaluation_cycles%ROWTYPE;
 generation_id uuid; epoch_id uuid; base_day date; due_day date; zone text; first_transition boolean;
 observed timestamptz; reason text; cycle_wire jsonb:='null'::jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 observed:=coalesce(p_observed_at,clock_timestamp());
 authority:=private.read_mobile_clinical_legacy_generation_at(p_user_id,observed);
 IF authority IS NULL THEN RETURN jsonb_build_object('reason','anchor_unproven'); END IF;
 generation_id:=(authority->>'generation')::uuid;epoch_id:=(authority->>'epoch')::uuid;
 IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_generation_sources s WHERE s.user_id=p_user_id
  AND s.generation=generation_id AND s.epoch=epoch_id AND s.kind='legacy_transition') THEN
  RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001'; END IF;
 calendar:=private.mobile_clinical_calendar_base_at(p_user_id,generation_id,epoch_id,
  (authority->>'admitted_at')::timestamptz,authority->>'timezone_at_admission',observed);
 first_transition:=(calendar->>'first_transition_pending')::boolean;
 base_day:=(calendar->>'base_date')::date;zone:=calendar->>'timezone';
 due_day:=base_day+CASE WHEN first_transition THEN 0 ELSE 14 END;
 SELECT * INTO cycle FROM private.mobile_reevaluation_cycles c WHERE c.user_id=p_user_id
  AND c.signup_generation=generation_id AND c.status IN('open','collecting','review_ready');
 IF FOUND THEN
  IF cycle.signup_epoch IS DISTINCT FROM epoch_id OR cycle.base_date IS DISTINCT FROM base_day
   OR cycle.due_date IS DISTINCT FROM due_day OR cycle.timezone_at_open IS DISTINCT FROM zone
   OR cycle.opened_at>observed OR cycle.opened_at<(authority->>'admitted_at')::timestamptz
   OR (first_transition AND cycle.kind<>'TRANSITION_FULL')
   OR (NOT first_transition AND cycle.kind='TRANSITION_FULL') THEN
   RAISE EXCEPTION 'mobile_reevaluation_cycle_corrupt' USING ERRCODE='XX001'; END IF;
  cycle_wire:=private.mobile_reevaluation_cycle_wire(cycle);
 END IF;
 reason:=CASE WHEN first_transition OR cycle.kind='EARLY_FULL' THEN NULL
  WHEN (observed AT TIME ZONE zone)::date<due_day THEN 'not_due' ELSE NULL END;
 RETURN jsonb_build_object('reason',reason,'signup_generation',generation_id,'signup_epoch',epoch_id,
  'observed_at',observed,'authority',authority,'last_full_id',calendar->'last_full_id',
  'next_kind',CASE WHEN first_transition THEN 'TRANSITION_FULL' ELSE 'REGULAR' END,
  'clock',jsonb_build_object('base_date',base_day::text,'due_date',due_day::text,'timezone',zone),
  'cycle',cycle_wire);
END $$;

CREATE OR REPLACE FUNCTION private.mobile_reevaluation_context_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE
  observed_at timestamptz; profile public.user_profiles%ROWTYPE;
  receipt private.mobile_signup_strength_completion_receipts%ROWTYPE;
  source private.strength_week_source_versions%ROWTYPE;
  scope private.strength_week_scopes%ROWTYPE;
  admission private.mobile_signup_strength_request_admissions%ROWTYPE;
  current_epoch uuid; cycle private.mobile_reevaluation_cycles%ROWTYPE;
  zone text; base_day date; due_day date; reason text; cycle_wire jsonb := 'null'; calendar jsonb; legacy_authority jsonb;
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
  legacy_authority:=private.read_mobile_clinical_legacy_generation_at(p_user_id,observed_at);
  IF legacy_authority IS NOT NULL THEN
    IF EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r
      WHERE r.user_id=p_user_id AND r.epoch=(legacy_authority->>'epoch')::uuid AND r.outcome='first_fresh') THEN
      RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001'; END IF;
    RETURN private.mobile_legacy_reevaluation_context_at(p_user_id,observed_at);
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
  calendar:=private.mobile_clinical_calendar_base_at(p_user_id,receipt.admission_id,current_epoch,
    receipt.completed_at,zone,observed_at);
  base_day:=(calendar->>'base_date')::date;
  zone:=calendar->>'timezone';
  due_day:=base_day+14;
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
  reason:=CASE WHEN cycle.kind='EARLY_FULL' THEN NULL WHEN (observed_at AT TIME ZONE zone)::date<due_day THEN 'not_due' ELSE NULL END;
  RETURN jsonb_build_object('reason',reason,'signup_generation',receipt.admission_id,
    'signup_epoch',current_epoch,'observed_at',observed_at,'last_full_id',calendar->'last_full_id',
    'authority',jsonb_build_object('kind','signup_receipt','generation',receipt.admission_id,'epoch',current_epoch,
      'completed_at',to_char(receipt.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'timezone_at_signup',source.observed_timezone),
    'clock',jsonb_build_object('base_date',to_char(base_day::timestamp,'YYYY-MM-DD'),
      'due_date',to_char(due_day::timestamp,'YYYY-MM-DD'),'timezone',zone),'cycle',cycle_wire);
END $$;

CREATE OR REPLACE FUNCTION private.mobile_reevaluation_state(p_context jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,
  'availability',CASE WHEN p_context->>'reason' IS NULL THEN 'available' ELSE 'unavailable' END,
  'unavailable_reason',p_context->'reason','clock',coalesce(p_context->'clock','null'::jsonb),
  'cycle',coalesce(p_context->'cycle','null'::jsonb))
 ||CASE WHEN p_context->>'next_kind'='TRANSITION_FULL' THEN jsonb_build_object('transition',
   jsonb_build_object('kind','legacy_transition','generation',p_context->>'signup_generation',
    'epoch',p_context->>'signup_epoch','admitted_at',p_context#>>'{authority,admitted_at}')) ELSE '{}'::jsonb END
$$;

CREATE OR REPLACE FUNCTION private.start_mobile_reevaluation_cycle_at(
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
      VALUES(p_user_id,generation_id,epoch_id,
        CASE WHEN context->>'next_kind'='TRANSITION_FULL' THEN 'TRANSITION_FULL' ELSE 'REGULAR' END,
        (context#>>'{clock,base_date}')::date,
        (context#>>'{clock,due_date}')::date,context#>>'{clock,timezone}','open',observed_at)
      RETURNING * INTO cycle;
    context:=jsonb_set(context,'{cycle}',private.mobile_reevaluation_cycle_wire(cycle));
  END IF;
  INSERT INTO private.mobile_reevaluation_start_keys(user_id,idempotency_key,signup_generation,cycle_id,created_at)
    VALUES(p_user_id,p_idempotency_key,generation_id,(context#>>'{cycle,id}')::uuid,observed_at);
  RETURN private.mobile_reevaluation_state(context);
END $$;

CREATE OR REPLACE FUNCTION private.start_mobile_clinical_full_at(p_user_id uuid,p_operation_key uuid,p_kind text,p_reason text,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb;previous private.mobile_clinical_start_requests%ROWTYPE;
 cycle private.mobile_reevaluation_cycles%ROWTYPE;observed_at timestamptz;generation_id uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_operation_key IS NULL OR p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL')
  OR (p_kind IN('REGULAR','TRANSITION_FULL') AND p_reason IS NOT NULL)
  OR (p_kind='EARLY_FULL' AND (p_reason IS NULL OR p_reason NOT IN('gain_review_notice','not_well_with_plan'))) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_start' USING ERRCODE='22023';
 END IF;
 context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 generation_id:=(context->>'signup_generation')::uuid;
 IF p_kind='TRANSITION_FULL' AND context->>'next_kind' IS DISTINCT FROM 'TRANSITION_FULL' THEN
  RAISE EXCEPTION 'mobile_clinical_transition_not_available' USING ERRCODE='40001'; END IF;
 -- Kind is determined at conclusion. An abandoned early occurrence cannot
 -- bypass regular photos/window rules after a full fortnight has elapsed.
 IF context#>>'{cycle,kind}'='EARLY_FULL'
  AND ((context->>'observed_at')::timestamptz AT TIME ZONE (context#>>'{clock,timezone}'))::date>=(context#>>'{clock,due_date}')::date
  AND ((context->>'observed_at')::timestamptz AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date>=(context#>>'{clock,due_date}')::date THEN
  UPDATE private.mobile_reevaluation_cycles SET kind='REGULAR',revision=revision+1
   WHERE user_id=p_user_id AND cycle_id=(context#>>'{cycle,id}')::uuid AND kind='EARLY_FULL' AND status IN('open','collecting','review_ready');
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 END IF;
 SELECT * INTO previous FROM private.mobile_clinical_start_requests WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF previous.requested_kind<>p_kind OR previous.early_reason IS DISTINCT FROM p_reason
   OR previous.signup_generation IS DISTINCT FROM generation_id
   OR previous.cycle_id::text IS DISTINCT FROM context#>>'{cycle,id}' THEN
   RAISE EXCEPTION 'mobile_clinical_start_changed' USING ERRCODE='40001';
  END IF;
  RETURN private.mobile_reevaluation_state(context);
 END IF;
 IF generation_id IS NULL THEN RETURN private.mobile_reevaluation_state(context); END IF;
 IF p_kind='REGULAR' OR context->>'reason' IS NULL OR context#>>'{cycle,kind}'='REGULAR' THEN
  PERFORM private.start_mobile_reevaluation_cycle_at(p_user_id,p_operation_key,p_observed_at);
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 ELSE
  IF p_reason='gain_review_notice' AND NOT EXISTS(SELECT 1 FROM public.user_profiles
   WHERE user_id=p_user_id AND current_protocol='ganho_massa') THEN
   RAISE EXCEPTION 'invalid_mobile_clinical_early_reason' USING ERRCODE='22023';
  END IF;
  IF context->'cycle'='null'::jsonb THEN
   observed_at:=(context->>'observed_at')::timestamptz;
   UPDATE private.mobile_reevaluation_cycles SET status='invalidated',invalidated_at=observed_at,revision=revision+1
    WHERE user_id=p_user_id AND signup_generation<>generation_id AND status IN('open','collecting','review_ready');
   INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,kind,base_date,due_date,
    timezone_at_open,status,opened_at)
   VALUES(p_user_id,generation_id,(context->>'signup_epoch')::uuid,'EARLY_FULL',
    (context#>>'{clock,base_date}')::date,(context#>>'{clock,due_date}')::date,context#>>'{clock,timezone}','open',observed_at)
   RETURNING * INTO cycle;
   context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  END IF;
 END IF;
 IF context#>>'{cycle,id}' IS NULL THEN RETURN private.mobile_reevaluation_state(context); END IF;
 INSERT INTO private.mobile_clinical_start_requests VALUES(p_user_id,p_operation_key,p_kind,p_reason,
  generation_id,(context#>>'{cycle,id}')::uuid,(context->>'observed_at')::timestamptz);
 RETURN private.mobile_reevaluation_state(context);
END $$;
REVOKE ALL ON FUNCTION private.mobile_legacy_reevaluation_context_at(uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

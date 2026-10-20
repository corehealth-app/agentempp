-- Capture a real app plan confirmation in its proven signup generation.
-- No hook in the shared legacy plan saver; no new scope, workout or reminder.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_requires_postgres' USING ERRCODE='42501';
 END IF;
 IF to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL
  OR to_regclass('private.strength_week_source_versions') IS NULL
  OR to_regclass('private.strength_week_scopes') IS NULL
  OR to_regclass('private.workout_strength_authority_epochs') IS NULL
  OR to_regprocedure('private.capture_strength_week_source(uuid,uuid,text,text,smallint,uuid,timestamptz,text,text)') IS NULL
 THEN RAISE EXCEPTION 'strength_week_plan_confirmation_requires_substrate' USING ERRCODE='42P01'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='capture_mobile_plan_strength_week_source')
 THEN RAISE EXCEPTION 'strength_week_plan_confirmation_unknown_object' USING ERRCODE='42P07'; END IF;
END $preflight$;

CREATE FUNCTION private.capture_mobile_plan_strength_week_source(p_user_id uuid,p_draft_id uuid,p_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $capture$
DECLARE
 scope private.strength_week_scopes%ROWTYPE;
 signup private.mobile_signup_strength_completion_receipts%ROWTYPE;
 frequency private.strength_week_source_versions%ROWTYPE;
 draft public.plan_drafts%ROWTYPE;
 plan public.training_plans%ROWTYPE;
 current_epoch uuid;result jsonb;operation_key text;
 unavailable constant jsonb:='{"status":"unavailable","reason":"signup_generation_unproved"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_draft_id IS NULL OR p_plan_id IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_plan_confirmation' USING ERRCODE='22023';
 END IF;
 -- Reentrant under the confirmation's domain -> user -> draft locks. No late
 -- workouts advisory lock: that would invert the workout/reset lock order.
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'strength_week_plan_patient_not_found' USING ERRCODE='P0002';
 END IF;
 IF EXISTS(SELECT 1 FROM private.strength_week_source_versions v
  WHERE v.user_id=p_user_id AND v.operation_namespace='mobile_plan_confirmation_v1'
   AND v.operation_key LIKE p_draft_id::text||':v:%') THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_origin_conflict' USING ERRCODE='40001';
 END IF;
 SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e
  WHERE e.user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RETURN unavailable; END IF;
 SELECT s.* INTO scope FROM private.strength_week_scopes s
  WHERE s.user_id=p_user_id AND s.closed_at IS NULL FOR UPDATE;
 IF NOT FOUND OR scope.predecessor_generation IS NOT NULL
  OR scope.open_operation_namespace<>'mobile_signup_completion_v1' THEN RETURN unavailable; END IF;
 SELECT r.* INTO signup FROM private.mobile_signup_strength_completion_receipts r
  WHERE r.user_id=p_user_id AND r.generation=scope.generation AND r.outcome='first_fresh'
   AND r.epoch=current_epoch;
 IF NOT FOUND THEN RETURN unavailable; END IF;
 IF scope.open_operation_key IS DISTINCT FROM signup.admission_id::text
  OR (signup.completion_result->>'completed_at')::timestamptz IS DISTINCT FROM signup.completed_at THEN
  RAISE EXCEPTION 'strength_week_plan_signup_origin_invalid' USING ERRCODE='XX001';
 END IF;
 SELECT v.* INTO frequency FROM private.strength_week_source_versions v
  WHERE v.user_id=p_user_id AND v.generation=scope.generation
   AND v.source_version_id=signup.frequency_source_version_id;
 IF NOT FOUND OR frequency.source_kind<>'informed_frequency' OR frequency.fact<>'value'
  OR frequency.planned_days NOT BETWEEN 0 AND 7 OR frequency.source_entity_id IS NOT NULL
  OR frequency.source_valid_until IS NOT NULL OR frequency.operation_namespace<>'mobile_signup_completion_v1'
  OR frequency.operation_key IS DISTINCT FROM signup.admission_id::text
  OR scope.opened_at>frequency.observed_at OR frequency.observed_at>signup.recorded_at THEN
  RAISE EXCEPTION 'strength_week_plan_signup_origin_invalid' USING ERRCODE='XX001';
 END IF;
 -- Legacy confirmations without proven Y above keep their isolation contract.
 -- A new source uses the existing RC-only capture protocol, atomically.
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'mobile_strength_week_requires_read_committed' USING ERRCODE='22023';
 END IF;
 SELECT d.* INTO draft FROM public.plan_drafts d WHERE d.user_id=p_user_id AND d.id=p_draft_id;
 IF NOT FOUND OR draft.domain<>'training' OR draft.status<>'confirmed'
  OR draft.confirmed_plan_id IS DISTINCT FROM p_plan_id OR draft.resolved_at IS NULL
  OR draft.resolved_at<signup.recorded_at THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_origin_invalid' USING ERRCODE='XX001';
 END IF;
 SELECT p.* INTO plan FROM public.training_plans p WHERE p.user_id=p_user_id AND p.id=p_plan_id;
 IF NOT FOUND OR plan.active IS NOT TRUE OR plan.days_per_week NOT BETWEEN 1 AND 7
  OR plan.days_per_week IS DISTINCT FROM jsonb_array_length(draft.payload->'weekly_schedule')
  OR plan.weekly_schedule IS DISTINCT FROM draft.payload->'weekly_schedule'
  OR plan.source_request_key IS DISTINCT FROM 'plan-draft:'||draft.id::text
  OR plan.generated_at IS DISTINCT FROM draft.resolved_at
  OR plan.generated_by IS DISTINCT FROM
    (CASE draft.origin WHEN 'flow_generated' THEN 'flow_draft' ELSE 'patient_import' END
     ||CASE WHEN draft.payload_version>1 THEN '_edited' ELSE '' END) THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_origin_invalid' USING ERRCODE='XX001';
 END IF;
 operation_key:=draft.id::text||':v:'||draft.payload_version::text;
 result:=private.capture_strength_week_source(p_user_id,scope.generation,'accepted_plan','value',
  plan.days_per_week::smallint,plan.id,plan.valid_until,'mobile_plan_confirmation_v1',operation_key);
 RETURN jsonb_build_object('status','captured','source',result);
END $capture$;
REVOKE ALL ON FUNCTION private.capture_mobile_plan_strength_week_source(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

DO $hook$
DECLARE
 target constant regprocedure:='public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)'::regprocedure;
 original text;definition text;changed text;metadata jsonb;after_metadata jsonb;
 needle constant text:=$needle$  RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('already_confirmed', false);$needle$;
 addition constant text:=$addition$  IF v_draft.domain = 'training' THEN
    PERFORM private.capture_mobile_plan_strength_week_source(p_user_id, v_draft.id, v_plan_id);
  END IF;

$addition$;
BEGIN
 SELECT p.prosrc,pg_get_functiondef(p.oid),to_jsonb(p)-'prosrc' INTO STRICT original,definition,metadata
  FROM pg_proc p WHERE p.oid=target;
 IF pg_get_userbyid((metadata->>'proowner')::oid)<>'postgres'
  OR metadata->>'prosecdef'<>'true' OR metadata->>'provolatile'<>'v'
  OR metadata->'proconfig' IS DISTINCT FROM '["search_path=pg_catalog, public, private, pg_temp"]'::jsonb
  OR NOT has_function_privilege('service_role',target,'EXECUTE')
  OR has_function_privilege('anon',target,'EXECUTE') OR has_function_privilege('authenticated',target,'EXECUTE')
  OR encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex')<>
    'dffea7a75edfd43d5ea3e20ce20805744f23ddbb3775988ace3fe672fb185cab'
  OR (length(original)-length(replace(original,needle,'')))/length(needle)<>1
 THEN RAISE EXCEPTION 'strength_week_plan_confirmation_source_drift' USING ERRCODE='55000'; END IF;
 changed:=replace(original,needle,addition||needle);
 EXECUTE replace(definition,original,changed);
 SELECT to_jsonb(p)-'prosrc' INTO STRICT after_metadata FROM pg_proc p WHERE p.oid=target;
 IF after_metadata IS DISTINCT FROM metadata OR (SELECT prosrc FROM pg_proc WHERE oid=target) IS DISTINCT FROM changed
 THEN RAISE EXCEPTION 'strength_week_plan_confirmation_contract_changed' USING ERRCODE='55000'; END IF;
END $hook$;
COMMIT;

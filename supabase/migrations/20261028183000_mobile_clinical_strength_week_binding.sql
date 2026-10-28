-- Separate FULL/workout proof for the current clinical weekly reader.
-- Existing signup binding and the complete S12 history projector stay intact.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_strength_week_sources') IS NULL
  OR to_regclass('private.mobile_clinical_strength_week_bindings') IS NOT NULL THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_substrate' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='private' AND p.proname IN('mobile_clinical_strength_week_origin',
   'get_mobile_strength_week_lifecycle_binding_v2','bind_mobile_strength_week_lifecycle_v2',
   'get_mobile_strength_week_projection_v2_at','capture_mobile_plan_strength_week_source_v2'))
  OR (n.nspname='public' AND p.proname='get_mobile_strength_week_projection_v2')) THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_unknown_object' USING ERRCODE='42P07'; END IF;
END $preflight$;

CREATE TABLE private.mobile_clinical_strength_week_bindings(
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 week_generation uuid NOT NULL,
 clinical_generation uuid NOT NULL,
 epoch uuid NOT NULL,
 review_id uuid NOT NULL,
 frequency_source_version_id uuid NOT NULL,
 lifecycle_key uuid NOT NULL,
 workout_admission_id uuid NOT NULL,
 workout_content_revision integer NOT NULL CHECK(workout_content_revision>=0),
 bound_at timestamptz NOT NULL CHECK(isfinite(bound_at)),
 PRIMARY KEY(user_id,week_generation),
 FOREIGN KEY(user_id,week_generation) REFERENCES private.strength_week_scopes(user_id,generation) ON DELETE CASCADE,
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_strength_week_sources(user_id,review_id) ON DELETE CASCADE,
 FOREIGN KEY(user_id,week_generation,frequency_source_version_id)
  REFERENCES private.strength_week_source_versions(user_id,generation,source_version_id) ON DELETE CASCADE,
 FOREIGN KEY(user_id,lifecycle_key) REFERENCES private.workout_strength_lifecycles(user_id,lifecycle_key) ON DELETE CASCADE,
 FOREIGN KEY(user_id,workout_admission_id)
  REFERENCES private.mobile_workout_proposal_admissions(user_id,admission_id) ON DELETE NO ACTION
);
ALTER TABLE private.mobile_clinical_strength_week_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_clinical_strength_week_bindings FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_strength_week_binding_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_strength_week_bindings FOR EACH ROW
 EXECUTE FUNCTION private.guard_mobile_clinical_strength_week_source();

CREATE FUNCTION private.mobile_clinical_strength_week_origin(p_user_id uuid,p_generation uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $origin$
DECLARE
 scope private.strength_week_scopes%ROWTYPE;
 origin private.mobile_clinical_strength_week_sources%ROWTYPE;
 receipt private.mobile_clinical_full_receipts%ROWTYPE;
 source private.strength_week_source_versions%ROWTYPE;
 clinical private.mobile_clinical_generation_sources%ROWTYPE;
 current_epoch uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_generation IS NULL THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_week_origin_input' USING ERRCODE='22023'; END IF;
 SELECT * INTO scope FROM private.strength_week_scopes
  WHERE user_id=p_user_id AND generation=p_generation AND closed_at IS NULL;
 IF NOT FOUND OR scope.open_operation_namespace<>'mobile_clinical_full_frequency_v1'
  OR scope.predecessor_generation IS NOT NULL THEN
  RETURN '{"status":"unavailable","reason":"binding_unproved"}'::jsonb; END IF;
 SELECT * INTO origin FROM private.mobile_clinical_strength_week_sources o
  WHERE o.user_id=p_user_id AND o.week_generation=p_generation AND o.review_id::text=scope.open_operation_key;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_week_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT epoch INTO current_epoch FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id;
 IF current_epoch IS DISTINCT FROM origin.epoch THEN
  RETURN '{"status":"unavailable","reason":"binding_unproved"}'::jsonb; END IF;
 SELECT * INTO receipt FROM private.mobile_clinical_full_receipts
  WHERE user_id=p_user_id AND review_id=origin.review_id;
 SELECT * INTO clinical FROM private.mobile_clinical_generation_sources
  WHERE user_id=p_user_id AND generation=origin.clinical_generation;
 SELECT * INTO source FROM private.strength_week_source_versions
  WHERE user_id=p_user_id AND generation=p_generation AND source_version_id=origin.frequency_source_version_id;
 IF receipt.review_id IS NULL OR source.source_version_id IS NULL OR clinical.generation IS NULL
  OR receipt.kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL')
  OR receipt.signup_generation IS DISTINCT FROM origin.clinical_generation
  OR receipt.signup_epoch IS DISTINCT FROM origin.epoch OR clinical.epoch IS DISTINCT FROM origin.epoch
  OR clinical.kind NOT IN('signup_receipt','legacy_transition')
  OR source.source_kind<>'informed_frequency' OR source.fact<>'value'
  OR source.planned_days NOT BETWEEN 0 AND 7 OR source.source_entity_id IS NOT NULL OR source.source_valid_until IS NOT NULL
  OR source.operation_namespace<>'mobile_clinical_full_frequency_v1' OR source.operation_key<>origin.review_id::text
  OR source.observed_at IS DISTINCT FROM receipt.completed_at OR scope.opened_at IS DISTINCT FROM receipt.completed_at
  OR source.observed_timezone IS DISTINCT FROM receipt.timezone_at_completion
  OR (receipt.form#>>'{answers,strengthSessions}')::smallint IS DISTINCT FROM source.planned_days
  OR (receipt.proposal#>>'{profile,training_frequency}')::smallint IS DISTINCT FROM source.planned_days
  OR receipt.result->>'review_id' IS DISTINCT FROM receipt.review_id::text
  OR (receipt.result->>'completed_at')::timestamptz IS DISTINCT FROM receipt.completed_at
  OR origin.recorded_at<receipt.completed_at
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=source.observed_timezone)
  OR source.effective_week_start IS DISTINCT FROM
   date_trunc('week',receipt.completed_at AT TIME ZONE source.observed_timezone)::date+7 THEN
  RAISE EXCEPTION 'mobile_clinical_week_origin_invalid' USING ERRCODE='XX001'; END IF;
 RETURN jsonb_build_object('status','ready','origin',jsonb_build_object(
  'user_id',p_user_id,'generation',p_generation,'review_id',origin.review_id,
  'clinical_generation',origin.clinical_generation,'epoch',origin.epoch,
  'frequency_source_version_id',origin.frequency_source_version_id,
  'completed_at',receipt.completed_at,'recorded_at',origin.recorded_at));
END $origin$;
REVOKE ALL ON FUNCTION private.mobile_clinical_strength_week_origin(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.get_mobile_strength_week_lifecycle_binding_v2(
 p_user_id uuid,p_expected_generation uuid,p_expected_lifecycle_key uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $read$
DECLARE
 authority private.workout_strength_authority_epochs%ROWTYPE;
 life private.workout_strength_lifecycles%ROWTYPE;
 scope private.strength_week_scopes%ROWTYPE;
 binding private.mobile_clinical_strength_week_bindings%ROWTYPE;
 admission private.mobile_workout_proposal_admissions%ROWTYPE;
 operation private.workout_strength_operations%ROWTYPE;
 origin jsonb;legacy jsonb;op_count bigint;
 unavailable constant jsonb:='{"status":"unavailable","reason":"binding_unproved"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_expected_generation IS NULL OR p_expected_lifecycle_key IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_lifecycle_binding_input' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_requires_read_committed' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_patient_not_found' USING ERRCODE='P0002'; END IF;
 SELECT * INTO authority FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS DISTINCT FROM p_expected_lifecycle_key THEN RETURN unavailable; END IF;
 SELECT * INTO life FROM private.workout_strength_lifecycles
  WHERE user_id=p_user_id AND lifecycle_key=p_expected_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR life.closed_at IS NOT NULL THEN RETURN unavailable; END IF;
 SELECT * INTO scope FROM private.strength_week_scopes
  WHERE user_id=p_user_id AND generation=p_expected_generation FOR UPDATE;
 IF NOT FOUND OR scope.closed_at IS NOT NULL THEN RETURN unavailable; END IF;
 IF scope.open_operation_namespace<>'mobile_clinical_full_frequency_v1' THEN
  legacy:=public.get_mobile_strength_week_lifecycle_binding(p_user_id,p_expected_generation,p_expected_lifecycle_key);
  IF legacy->>'status'='ready' THEN
   RETURN jsonb_set(legacy,'{proof}',legacy->'proof'||'{"kind":"signup_receipt"}'::jsonb);
  END IF;
  RETURN legacy;
 END IF;
 SELECT * INTO binding FROM private.mobile_clinical_strength_week_bindings
  WHERE user_id=p_user_id AND week_generation=p_expected_generation FOR UPDATE;
 IF NOT FOUND THEN RETURN unavailable; END IF;
 origin:=private.mobile_clinical_strength_week_origin(p_user_id,p_expected_generation);
 IF origin->>'status' IS DISTINCT FROM 'ready' OR binding.epoch IS DISTINCT FROM authority.epoch
  OR binding.lifecycle_key IS DISTINCT FROM p_expected_lifecycle_key
  OR binding.review_id::text IS DISTINCT FROM origin#>>'{origin,review_id}'
  OR binding.clinical_generation::text IS DISTINCT FROM origin#>>'{origin,clinical_generation}'
  OR binding.frequency_source_version_id::text IS DISTINCT FROM origin#>>'{origin,frequency_source_version_id}'
  OR binding.bound_at<(origin#>>'{origin,recorded_at}')::timestamptz THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT * INTO admission FROM private.mobile_workout_proposal_admissions
  WHERE user_id=p_user_id AND admission_id=binding.workout_admission_id;
 IF NOT FOUND OR admission.epoch IS DISTINCT FROM binding.epoch
  OR admission.content_revision IS DISTINCT FROM binding.workout_content_revision
  OR admission.confirmed_lifecycle_key IS DISTINCT FROM binding.lifecycle_key THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT count(*) INTO op_count FROM private.workout_strength_operations o
  WHERE o.user_id=p_user_id AND o.lifecycle_key=binding.lifecycle_key AND o.operation_kind='capture'
  AND o.operation_key=('ui:'||admission.admission_id::text||':r:'||binding.workout_content_revision::text COLLATE "C");
 IF op_count<>1 THEN RAISE EXCEPTION 'mobile_clinical_week_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT * INTO STRICT operation FROM private.workout_strength_operations o
  WHERE o.user_id=p_user_id AND o.lifecycle_key=binding.lifecycle_key AND o.operation_kind='capture'
  AND o.operation_key=('ui:'||admission.admission_id::text||':r:'||binding.workout_content_revision::text COLLATE "C");
 IF operation.capture_outcome<>'fact' OR operation.created_at<life.opened_at
  OR operation.created_at<(origin#>>'{origin,recorded_at}')::timestamptz
  OR operation.created_at>binding.bound_at OR binding.bound_at<life.opened_at THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 -- Durability follows v1: no live pending/fact join after legitimate retention.
 RETURN jsonb_build_object('status','ready','proof',jsonb_build_object(
  'kind','clinical_full','ownerID',p_user_id,'generation',p_expected_generation,'epoch',binding.epoch,
  'lifecycleKey',binding.lifecycle_key,'clinicalGeneration',binding.clinical_generation,'reviewID',binding.review_id,
  'frequencySourceVersionID',binding.frequency_source_version_id,'workoutAdmissionID',binding.workout_admission_id,
  'workoutContentRevision',binding.workout_content_revision,
  'boundAt',to_char(binding.bound_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $read$;
REVOKE ALL ON FUNCTION private.get_mobile_strength_week_lifecycle_binding_v2(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.bind_mobile_strength_week_lifecycle_v2(p_user_id uuid,p_workout_admission_id uuid,p_lifecycle_key uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $bind$
DECLARE
 scope private.strength_week_scopes%ROWTYPE;
 authority private.workout_strength_authority_epochs%ROWTYPE;
 life private.workout_strength_lifecycles%ROWTYPE;
 admission private.mobile_workout_proposal_admissions%ROWTYPE;
 pending public.pending_registrations%ROWTYPE;
 operation private.workout_strength_operations%ROWTYPE;
 binding private.mobile_clinical_strength_week_bindings%ROWTYPE;
 origin jsonb;resolved jsonb;proof jsonb;original_key text;bound_clock timestamptz;
 unavailable constant jsonb:='{"status":"unavailable","reason":"binding_unproved"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_workout_admission_id IS NULL OR p_lifecycle_key IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_lifecycle_binding_input' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_requires_read_committed' USING ERRCODE='22023'; END IF;
 -- Same lock order as S17D and v1; reentrant when called by confirmation.
 LOCK TABLE public.workout_types IN SHARE MODE;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_patient_not_found' USING ERRCODE='P0002'; END IF;
 SELECT * INTO authority FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS DISTINCT FROM p_lifecycle_key THEN RETURN unavailable; END IF;
 SELECT * INTO life FROM private.workout_strength_lifecycles WHERE user_id=p_user_id AND lifecycle_key=p_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR life.closed_at IS NOT NULL THEN RETURN unavailable; END IF;
 SELECT * INTO scope FROM private.strength_week_scopes WHERE user_id=p_user_id AND closed_at IS NULL FOR UPDATE;
 IF NOT FOUND OR scope.open_operation_namespace<>'mobile_clinical_full_frequency_v1' THEN
  RETURN private.bind_mobile_strength_week_lifecycle(p_user_id,p_workout_admission_id,p_lifecycle_key); END IF;
 SELECT * INTO binding FROM private.mobile_clinical_strength_week_bindings
  WHERE user_id=p_user_id AND week_generation=scope.generation FOR UPDATE;
 IF FOUND THEN
  proof:=private.get_mobile_strength_week_lifecycle_binding_v2(p_user_id,scope.generation,p_lifecycle_key);
  IF proof->>'status' IS DISTINCT FROM 'ready' THEN
   RAISE EXCEPTION 'mobile_clinical_week_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
  RETURN jsonb_build_object('status','reused','proof',proof->'proof');
 END IF;
 origin:=private.mobile_clinical_strength_week_origin(p_user_id,scope.generation);
 IF origin->>'status' IS DISTINCT FROM 'ready' THEN RETURN unavailable; END IF;
 SELECT * INTO admission FROM private.mobile_workout_proposal_admissions
  WHERE user_id=p_user_id AND admission_id=p_workout_admission_id FOR UPDATE;
 IF NOT FOUND OR admission.epoch IS DISTINCT FROM authority.epoch OR admission.content_revision IS NULL
  OR admission.confirmed_lifecycle_key IS DISTINCT FROM p_lifecycle_key THEN RETURN unavailable; END IF;
 SELECT * INTO pending FROM public.pending_registrations
  WHERE user_id=p_user_id AND id=admission.pending_id FOR UPDATE;
 IF NOT FOUND OR pending.status<>'confirmed' OR pending.resolved_at IS NULL
  OR pending.workout_ui_admission_id IS DISTINCT FROM admission.admission_id THEN RETURN unavailable; END IF;
 original_key:='ui:'||admission.admission_id::text||':r:'||admission.content_revision::text;
 resolved:=public.resolve_confirmed_workout_strength_capture(p_user_id,p_lifecycle_key,original_key,pending.proposal->>'workoutType');
 IF resolved->>'status' IS DISTINCT FROM 'reuse_existing' THEN RETURN unavailable; END IF;
 SELECT * INTO operation FROM private.workout_strength_operations o
  WHERE o.user_id=p_user_id AND o.lifecycle_key=p_lifecycle_key AND o.operation_kind='capture'
   AND o.operation_key=(original_key COLLATE "C")
   AND o.original_operation_type=(pending.proposal->>'workoutType' COLLATE "C");
 IF NOT FOUND OR operation.capture_outcome<>'fact' OR operation.created_at<life.opened_at
  OR operation.created_at<(origin#>>'{origin,recorded_at}')::timestamptz
  OR pending.resolved_at<operation.created_at THEN RETURN unavailable; END IF;
 bound_clock:=clock_timestamp();
 IF NOT isfinite(bound_clock) OR bound_clock<pending.resolved_at OR bound_clock<life.opened_at THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_clock_invalid' USING ERRCODE='XX001'; END IF;
 -- A dedup keeps its original workout identity/date. This is a confirmation
 -- handshake, not evidence that another exercise was performed after FULL.
 INSERT INTO private.mobile_clinical_strength_week_bindings(user_id,week_generation,clinical_generation,epoch,
  review_id,frequency_source_version_id,lifecycle_key,workout_admission_id,workout_content_revision,bound_at)
 VALUES(p_user_id,scope.generation,(origin#>>'{origin,clinical_generation}')::uuid,authority.epoch,
  (origin#>>'{origin,review_id}')::uuid,(origin#>>'{origin,frequency_source_version_id}')::uuid,
  p_lifecycle_key,admission.admission_id,admission.content_revision,bound_clock);
 proof:=private.get_mobile_strength_week_lifecycle_binding_v2(p_user_id,scope.generation,p_lifecycle_key);
 IF proof->>'status' IS DISTINCT FROM 'ready' THEN
  RAISE EXCEPTION 'mobile_clinical_week_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 RETURN jsonb_build_object('status','bound','proof',proof->'proof');
END $bind$;
REVOKE ALL ON FUNCTION private.bind_mobile_strength_week_lifecycle_v2(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Clone only the binding reader call in the qualified atomic projector. This
-- preserves every calendar, target CAS, full-history S12 and rollback guard.
DO $projection$
DECLARE original text;definition text;changed text;
BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO STRICT original,definition FROM pg_proc
  WHERE oid='private.get_mobile_strength_week_projection_at(uuid,uuid,uuid,timestamptz)'::regprocedure;
 IF encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex')
  IS DISTINCT FROM '3a400344f91fd7288af654f52933b605dbb3bc178df81884c78ef59c0df70a14' THEN
  RAISE EXCEPTION 'mobile_clinical_week_projection_source_drift' USING ERRCODE='55000'; END IF;
 changed:=replace(original,'bound:=public.get_mobile_strength_week_lifecycle_binding(',
  'bound:=private.get_mobile_strength_week_lifecycle_binding_v2(');
 IF changed=original THEN RAISE EXCEPTION 'mobile_clinical_week_projection_binding_missing' USING ERRCODE='55000'; END IF;
 definition:=replace(definition,'FUNCTION private.get_mobile_strength_week_projection_at(',
  'FUNCTION private.get_mobile_strength_week_projection_v2_at(');
 EXECUTE replace(definition,original,changed);
END $projection$;
REVOKE ALL ON FUNCTION private.get_mobile_strength_week_projection_v2_at(uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.get_mobile_strength_week_projection_v2(p_user_id uuid,p_expected_generation uuid,p_target_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $public$
BEGIN
 RETURN private.get_mobile_strength_week_projection_v2_at(p_user_id,p_expected_generation,p_target_id,NULL::timestamptz);
END $public$;
REVOKE ALL ON FUNCTION public.get_mobile_strength_week_projection_v2(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_strength_week_projection_v2(uuid,uuid,uuid) TO service_role;

CREATE FUNCTION private.capture_mobile_plan_strength_week_source_v2(p_user_id uuid,p_draft_id uuid,p_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $plan$
DECLARE
 scope private.strength_week_scopes%ROWTYPE;draft public.plan_drafts%ROWTYPE;plan public.training_plans%ROWTYPE;
 origin jsonb;result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_draft_id IS NULL OR p_plan_id IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_plan_confirmation' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'strength_week_plan_patient_not_found' USING ERRCODE='P0002'; END IF;
 SELECT * INTO scope FROM private.strength_week_scopes WHERE user_id=p_user_id AND closed_at IS NULL FOR UPDATE;
 IF NOT FOUND OR scope.open_operation_namespace<>'mobile_clinical_full_frequency_v1' THEN
  RETURN private.capture_mobile_plan_strength_week_source(p_user_id,p_draft_id,p_plan_id); END IF;
 origin:=private.mobile_clinical_strength_week_origin(p_user_id,scope.generation);
 IF origin->>'status' IS DISTINCT FROM 'ready' THEN RETURN origin; END IF;
 IF EXISTS(SELECT 1 FROM private.strength_week_source_versions v WHERE v.user_id=p_user_id
  AND v.operation_namespace='mobile_plan_confirmation_v1' AND v.operation_key LIKE p_draft_id::text||':v:%') THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_origin_conflict' USING ERRCODE='40001'; END IF;
 SELECT * INTO draft FROM public.plan_drafts WHERE user_id=p_user_id AND id=p_draft_id;
 IF NOT FOUND OR draft.domain<>'training' OR draft.status<>'confirmed' OR draft.confirmed_plan_id IS DISTINCT FROM p_plan_id
  OR draft.resolved_at IS NULL OR draft.resolved_at<(origin#>>'{origin,recorded_at}')::timestamptz THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT * INTO plan FROM public.training_plans WHERE user_id=p_user_id AND id=p_plan_id;
 IF NOT FOUND OR plan.active IS NOT TRUE OR plan.days_per_week NOT BETWEEN 1 AND 7
  OR plan.days_per_week IS DISTINCT FROM jsonb_array_length(draft.payload->'weekly_schedule')
  OR plan.weekly_schedule IS DISTINCT FROM draft.payload->'weekly_schedule'
  OR plan.source_request_key IS DISTINCT FROM 'plan-draft:'||draft.id::text
  OR plan.generated_at IS DISTINCT FROM draft.resolved_at
  OR plan.generated_by IS DISTINCT FROM
   (CASE draft.origin WHEN 'flow_generated' THEN 'flow_draft' ELSE 'patient_import' END
    ||CASE WHEN draft.payload_version>1 THEN '_edited' ELSE '' END) THEN
  RAISE EXCEPTION 'strength_week_plan_confirmation_origin_invalid' USING ERRCODE='XX001'; END IF;
 result:=private.capture_strength_week_source(p_user_id,scope.generation,'accepted_plan','value',
  plan.days_per_week::smallint,plan.id,plan.valid_until,'mobile_plan_confirmation_v1',
  draft.id::text||':v:'||draft.payload_version::text);
 RETURN jsonb_build_object('status','captured','source',result);
END $plan$;
REVOKE ALL ON FUNCTION private.capture_mobile_plan_strength_week_source_v2(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $hooks$
DECLARE signature text;wanted text;needle text;replacement text;original text;definition text;metadata jsonb;after_metadata jsonb;changed text;
BEGIN
 FOR signature,wanted,needle,replacement IN SELECT * FROM (VALUES
 ('public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)',
  '8589c32a78101bcae3be7e884ac1967e8c916a3ba60b8fae73d41a2e72aa4295',
  'PERFORM private.bind_mobile_strength_week_lifecycle(','PERFORM private.bind_mobile_strength_week_lifecycle_v2('),
 ('public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)',
  '278f30ccc03a1248efb363ffd76968fd64411ec71d47ef8c41b80f6b69b06920',
  'PERFORM private.capture_mobile_plan_strength_week_source(','PERFORM private.capture_mobile_plan_strength_week_source_v2(')
 ) v(sig,hash,old_call,new_call) LOOP
  SELECT prosrc,pg_get_functiondef(oid),to_jsonb(p)-'prosrc' INTO STRICT original,definition,metadata
   FROM pg_proc p WHERE oid=to_regprocedure(signature);
  IF encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex') IS DISTINCT FROM wanted
   OR (length(original)-length(replace(original,needle,'')))/length(needle)<>1 THEN
   RAISE EXCEPTION 'mobile_clinical_week_hook_source_drift:%',signature USING ERRCODE='55000'; END IF;
  changed:=replace(original,needle,replacement);EXECUTE replace(definition,original,changed);
  SELECT to_jsonb(p)-'prosrc' INTO STRICT after_metadata FROM pg_proc p WHERE oid=to_regprocedure(signature);
  IF after_metadata IS DISTINCT FROM metadata OR (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure(signature)) IS DISTINCT FROM changed THEN
   RAISE EXCEPTION 'mobile_clinical_week_hook_metadata_changed:%',signature USING ERRCODE='55000'; END IF;
 END LOOP;
END $hooks$;
COMMIT;


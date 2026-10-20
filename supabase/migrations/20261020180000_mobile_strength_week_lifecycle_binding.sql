-- Bind only native confirmed workout provenance to its real signup generation.
-- No shared legacy core, nutrition formula, public confirmation result or caller changes.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $existing_confirmation$
BEGIN
 IF current_user<>'postgres' THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_requires_postgres_owner' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p
  WHERE p.oid=to_regprocedure('public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)')
   AND p.proowner='postgres'::regrole AND p.prosecdef AND p.provolatile='v'
   AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql')
   AND p.prorettype='jsonb'::regtype AND p.proconfig=ARRAY['search_path=pg_catalog']
   AND encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')=
    '3cdde8bf05e66acedbf4871314c715de600eca1d47794f448287660890a7d726') THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_confirmation_source_drift' USING ERRCODE='55000';
 END IF;
 IF EXISTS(
  WITH actual AS(
   SELECT a.grantor,a.grantee,a.privilege_type,a.is_grantable
   FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid='public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)'::regprocedure),
  expected AS(
   SELECT 'postgres'::regrole::oid AS grantor,'postgres'::regrole::oid AS grantee,
    'EXECUTE'::text AS privilege_type,false AS is_grantable
   UNION ALL SELECT 'postgres'::regrole::oid,'service_role'::regrole::oid,'EXECUTE',false),
  delta AS((SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
   UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)) SELECT 1 FROM delta)
  OR has_function_privilege('anon','public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)','EXECUTE')
  OR has_function_privilege('authenticated','public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)','EXECUTE') THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_confirmation_acl_drift' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='bind_mobile_strength_week_lifecycle') THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_unknown_object' USING ERRCODE='42P07';
 END IF;
END $existing_confirmation$;
-- New storage/reader candidate only. No writer hook or outer transaction.
SET LOCAL ROLE postgres;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
 IF current_user<>'postgres'
  OR to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL
  OR to_regclass('private.mobile_workout_proposal_admissions') IS NULL
  OR to_regclass('private.strength_week_scopes') IS NULL
  OR to_regclass('private.strength_week_source_versions') IS NULL
  OR to_regclass('private.workout_strength_lifecycles') IS NULL
  OR to_regclass('private.workout_strength_operations') IS NULL
  OR to_regprocedure('private.assert_trusted_backend()') IS NULL
 THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_requires_substrate' USING ERRCODE='42P01'; END IF;
 IF to_regclass('private.strength_week_lifecycle_bindings') IS NOT NULL
  OR to_regtype('private.strength_week_lifecycle_bindings') IS NOT NULL
  OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE (n.nspname='private' AND p.proname='preserve_strength_week_lifecycle_binding')
    OR (n.nspname='public' AND p.proname='get_mobile_strength_week_lifecycle_binding'))
 THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_unknown_object' USING ERRCODE='42P07'; END IF;
END $preflight$;

CREATE TABLE private.strength_week_lifecycle_bindings(
 user_id uuid NOT NULL,generation uuid NOT NULL,epoch uuid NOT NULL,lifecycle_key uuid NOT NULL,
 signup_admission_id uuid NOT NULL,frequency_source_version_id uuid NOT NULL,
 workout_admission_id uuid NOT NULL,workout_content_revision integer NOT NULL CHECK(workout_content_revision>=0),
 bound_at timestamptz NOT NULL CHECK(isfinite(bound_at) AND date_part('year',bound_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 PRIMARY KEY(user_id,generation),
 FOREIGN KEY(user_id,generation) REFERENCES private.strength_week_scopes(user_id,generation) ON DELETE CASCADE,
 FOREIGN KEY(user_id,lifecycle_key) REFERENCES private.workout_strength_lifecycles(user_id,lifecycle_key) ON DELETE CASCADE,
 FOREIGN KEY(user_id,signup_admission_id)
  REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) ON DELETE NO ACTION,
 FOREIGN KEY(user_id,generation,frequency_source_version_id)
  REFERENCES private.strength_week_source_versions(user_id,generation,source_version_id) ON DELETE NO ACTION,
 FOREIGN KEY(user_id,workout_admission_id)
  REFERENCES private.mobile_workout_proposal_admissions(user_id,admission_id) ON DELETE NO ACTION
);
ALTER TABLE private.strength_week_lifecycle_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.strength_week_lifecycle_bindings FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.preserve_strength_week_lifecycle_binding() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $immutable$
BEGIN
 IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_immutable' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END $immutable$;
CREATE TRIGGER preserve_strength_week_lifecycle_binding BEFORE UPDATE
 ON private.strength_week_lifecycle_bindings FOR EACH ROW
 EXECUTE FUNCTION private.preserve_strength_week_lifecycle_binding();
REVOKE ALL ON FUNCTION private.preserve_strength_week_lifecycle_binding() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.get_mobile_strength_week_lifecycle_binding(
 p_user_id uuid,p_expected_generation uuid,p_expected_lifecycle_key uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $read$
DECLARE
 authority private.workout_strength_authority_epochs%ROWTYPE;
 life private.workout_strength_lifecycles%ROWTYPE;
 scope private.strength_week_scopes%ROWTYPE;
 binding private.strength_week_lifecycle_bindings%ROWTYPE;
 signup private.mobile_signup_strength_completion_receipts%ROWTYPE;
 source private.strength_week_source_versions%ROWTYPE;
 admission private.mobile_workout_proposal_admissions%ROWTYPE;
 operation private.workout_strength_operations%ROWTYPE;
 op_count bigint;original_key text;
 unavailable constant jsonb:='{"status":"unavailable","reason":"binding_unproved"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_expected_generation IS NULL OR p_expected_lifecycle_key IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_lifecycle_binding_input' USING ERRCODE='22023';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_requires_read_committed' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_patient_not_found' USING ERRCODE='P0002';
 END IF;
 SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS DISTINCT FROM p_expected_lifecycle_key THEN RETURN unavailable; END IF;
 SELECT l.* INTO life FROM private.workout_strength_lifecycles l
  WHERE l.user_id=p_user_id AND l.lifecycle_key=p_expected_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR life.closed_at IS NOT NULL THEN RETURN unavailable; END IF;
 SELECT s.* INTO scope FROM private.strength_week_scopes s
  WHERE s.user_id=p_user_id AND s.generation=p_expected_generation FOR UPDATE;
 IF NOT FOUND OR scope.closed_at IS NOT NULL OR life.opened_at<scope.opened_at THEN RETURN unavailable; END IF;
 SELECT b.* INTO binding FROM private.strength_week_lifecycle_bindings b
  WHERE b.user_id=p_user_id AND b.generation=p_expected_generation FOR UPDATE;
 IF NOT FOUND THEN RETURN unavailable; END IF;
 IF binding.epoch IS DISTINCT FROM authority.epoch
  OR binding.lifecycle_key IS DISTINCT FROM p_expected_lifecycle_key THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
 END IF;

 -- From here, a CURRENT binding exists. Contradictory durable origins are corruption,
 -- not permission to adopt another source, rebind a life or repair history on read.
 SELECT r.* INTO signup FROM private.mobile_signup_strength_completion_receipts r
  WHERE r.user_id=p_user_id AND r.admission_id=binding.signup_admission_id;
 IF NOT FOUND OR signup.outcome<>'first_fresh' OR signup.epoch IS DISTINCT FROM binding.epoch
  OR signup.generation IS DISTINCT FROM binding.generation
  OR signup.frequency_source_version_id IS DISTINCT FROM binding.frequency_source_version_id
  OR scope.predecessor_generation IS NOT NULL
  OR scope.open_operation_namespace<>'mobile_signup_completion_v1'
  OR scope.open_operation_key<>signup.admission_id::text
 THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT v.* INTO source FROM private.strength_week_source_versions v
  WHERE v.user_id=p_user_id AND v.generation=binding.generation AND v.source_version_id=binding.frequency_source_version_id;
 IF NOT FOUND OR source.source_kind<>'informed_frequency' OR source.fact<>'value'
  OR source.planned_days NOT BETWEEN 0 AND 7 OR source.source_entity_id IS NOT NULL OR source.source_valid_until IS NOT NULL
  OR source.operation_namespace<>'mobile_signup_completion_v1' OR source.operation_key<>signup.admission_id::text
  OR scope.opened_at>source.observed_at OR source.observed_at>signup.recorded_at
  OR binding.bound_at<signup.recorded_at OR binding.bound_at<life.opened_at
 THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 SELECT a.* INTO admission FROM private.mobile_workout_proposal_admissions a
  WHERE a.user_id=p_user_id AND a.admission_id=binding.workout_admission_id;
 IF NOT FOUND OR admission.epoch IS DISTINCT FROM binding.epoch
  OR admission.content_revision IS DISTINCT FROM binding.workout_content_revision
  OR admission.confirmed_lifecycle_key IS DISTINCT FROM binding.lifecycle_key
 THEN RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001'; END IF;
 original_key:='ui:'||admission.admission_id::text||':r:'||binding.workout_content_revision::text;
 SELECT count(*) INTO op_count FROM private.workout_strength_operations o
  WHERE o.user_id=p_user_id AND o.lifecycle_key=binding.lifecycle_key AND o.operation_kind='capture'
   AND o.operation_key=(original_key COLLATE "C");
 IF op_count<>1 THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
 END IF;
 SELECT o.* INTO STRICT operation FROM private.workout_strength_operations o
  WHERE o.user_id=p_user_id AND o.lifecycle_key=binding.lifecycle_key AND o.operation_kind='capture'
   AND o.operation_key=(original_key COLLATE "C");
 IF operation.capture_outcome<>'fact' OR operation.created_at<life.opened_at OR operation.created_at>binding.bound_at THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
 END IF;
 -- Deliberately no live workout/fact or pending join: legitimate deletion/retention
 -- may remove those rows after the origin was confirmed without erasing this proof.
 RETURN jsonb_build_object('status','ready','proof',jsonb_build_object(
  'ownerID',binding.user_id::text,'generation',binding.generation::text,'epoch',binding.epoch::text,
  'lifecycleKey',binding.lifecycle_key::text,'signupAdmissionID',binding.signup_admission_id::text,
  'frequencySourceVersionID',binding.frequency_source_version_id::text,
  'workoutAdmissionID',binding.workout_admission_id::text,'workoutContentRevision',binding.workout_content_revision,
  'boundAt',to_char(binding.bound_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $read$;
REVOKE ALL ON FUNCTION public.get_mobile_strength_week_lifecycle_binding(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_strength_week_lifecycle_binding(uuid,uuid,uuid) TO service_role;

-- Owner-only producer. The native S17D confirmation calls this after admission
-- and pending are terminal, inside the same mutation subtransaction.
CREATE FUNCTION private.bind_mobile_strength_week_lifecycle(
 p_user_id uuid,p_workout_admission_id uuid,p_lifecycle_key uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $bind$
DECLARE
 authority private.workout_strength_authority_epochs%ROWTYPE;
 admission private.mobile_workout_proposal_admissions%ROWTYPE;
 pending public.pending_registrations%ROWTYPE;
 life private.workout_strength_lifecycles%ROWTYPE;
 scope private.strength_week_scopes%ROWTYPE;
 binding private.strength_week_lifecycle_bindings%ROWTYPE;
 signup private.mobile_signup_strength_completion_receipts%ROWTYPE;
 source private.strength_week_source_versions%ROWTYPE;
 operation private.workout_strength_operations%ROWTYPE;
 resolved jsonb;current_proof jsonb;original_key text;raw_type text;bound_clock timestamptz;
 unavailable constant jsonb:='{"status":"unavailable","reason":"binding_unproved"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_workout_admission_id IS NULL OR p_lifecycle_key IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_lifecycle_binding_input' USING ERRCODE='22023';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_requires_read_committed' USING ERRCODE='22023';
 END IF;
 -- These locks are reentrant under S17D. Keep its order for owner-only callers too.
 LOCK TABLE public.workout_types IN SHARE MODE;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_patient_not_found' USING ERRCODE='P0002';
 END IF;
 SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS DISTINCT FROM p_lifecycle_key THEN RETURN unavailable; END IF;
 SELECT a.* INTO admission FROM private.mobile_workout_proposal_admissions a
  WHERE a.user_id=p_user_id AND a.admission_id=p_workout_admission_id FOR UPDATE;
 IF NOT FOUND OR admission.epoch IS DISTINCT FROM authority.epoch
  OR admission.content_revision IS NULL OR admission.content_revision<0
  OR admission.confirmed_lifecycle_key IS DISTINCT FROM p_lifecycle_key THEN RETURN unavailable; END IF;
 SELECT p.* INTO pending FROM public.pending_registrations p
  WHERE p.user_id=p_user_id AND p.id=admission.pending_id FOR UPDATE;
 IF NOT FOUND OR pending.status<>'confirmed' OR pending.resolved_at IS NULL
  OR pending.workout_ui_admission_id IS DISTINCT FROM admission.admission_id THEN RETURN unavailable; END IF;
 SELECT l.* INTO life FROM private.workout_strength_lifecycles l
  WHERE l.user_id=p_user_id AND l.lifecycle_key=p_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR life.closed_at IS NOT NULL THEN RETURN unavailable; END IF;
 original_key:='ui:'||admission.admission_id::text||':r:'||admission.content_revision::text;
 raw_type:=pending.proposal->>'workoutType';
 resolved:=public.resolve_confirmed_workout_strength_capture(p_user_id,p_lifecycle_key,original_key,raw_type);
 IF resolved->>'status' IS DISTINCT FROM 'reuse_existing' THEN RETURN unavailable; END IF;
 SELECT o.* INTO operation FROM private.workout_strength_operations o
  WHERE o.user_id=p_user_id AND o.lifecycle_key=p_lifecycle_key AND o.operation_kind='capture'
   AND o.operation_key=(original_key COLLATE "C") AND o.original_operation_type=(raw_type COLLATE "C");
 IF NOT FOUND OR operation.capture_outcome<>'fact' THEN RETURN unavailable; END IF;
 SELECT s.* INTO scope FROM private.strength_week_scopes s
  WHERE s.user_id=p_user_id AND s.closed_at IS NULL FOR UPDATE;
 IF NOT FOUND OR life.opened_at<scope.opened_at THEN RETURN unavailable; END IF;

 -- Reuse the first origin, never the new admission or a fresh clock. The reader
 -- checks its durable capture even if the original live log was later deleted.
 SELECT b.* INTO binding FROM private.strength_week_lifecycle_bindings b
  WHERE b.user_id=p_user_id AND b.generation=scope.generation FOR UPDATE;
 IF FOUND THEN
  current_proof:=public.get_mobile_strength_week_lifecycle_binding(p_user_id,scope.generation,p_lifecycle_key);
  IF current_proof->>'status' IS DISTINCT FROM 'ready' THEN
   RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
  END IF;
  RETURN jsonb_build_object('status','reused','proof',current_proof->'proof');
 END IF;
 SELECT r.* INTO signup FROM private.mobile_signup_strength_completion_receipts r
  WHERE r.user_id=p_user_id AND r.epoch=authority.epoch AND r.outcome='first_fresh';
 IF NOT FOUND OR signup.generation IS DISTINCT FROM scope.generation
  OR scope.predecessor_generation IS NOT NULL
  OR scope.open_operation_namespace<>'mobile_signup_completion_v1'
  OR scope.open_operation_key<>signup.admission_id::text THEN RETURN unavailable; END IF;
 SELECT v.* INTO source FROM private.strength_week_source_versions v
  WHERE v.user_id=p_user_id AND v.generation=scope.generation AND v.source_version_id=signup.frequency_source_version_id;
 IF NOT FOUND OR source.source_kind<>'informed_frequency' OR source.fact<>'value'
  OR source.planned_days NOT BETWEEN 0 AND 7 OR source.source_entity_id IS NOT NULL OR source.source_valid_until IS NOT NULL
  OR source.operation_namespace<>'mobile_signup_completion_v1' OR source.operation_key<>signup.admission_id::text
  OR scope.opened_at>source.observed_at OR source.observed_at>signup.recorded_at THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
 END IF;
 -- Sample only after all waits and validations; transaction now() is too early.
 bound_clock:=clock_timestamp();
 IF NOT isfinite(bound_clock) OR date_part('year',bound_clock AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
  OR bound_clock<signup.recorded_at OR bound_clock<life.opened_at OR bound_clock<operation.created_at
  OR bound_clock<pending.resolved_at THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
 END IF;
 INSERT INTO private.strength_week_lifecycle_bindings(user_id,generation,epoch,lifecycle_key,
  signup_admission_id,frequency_source_version_id,workout_admission_id,workout_content_revision,bound_at)
 VALUES(p_user_id,scope.generation,authority.epoch,p_lifecycle_key,signup.admission_id,
  source.source_version_id,admission.admission_id,admission.content_revision,bound_clock);
 current_proof:=public.get_mobile_strength_week_lifecycle_binding(p_user_id,scope.generation,p_lifecycle_key);
 IF current_proof->>'status' IS DISTINCT FROM 'ready' THEN
  RAISE EXCEPTION 'strength_week_lifecycle_binding_origin_invalid' USING ERRCODE='XX001';
 END IF;
 RETURN jsonb_build_object('status','bound','proof',current_proof->'proof');
END $bind$;
REVOKE ALL ON FUNCTION private.bind_mobile_strength_week_lifecycle(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.confirm_mobile_workout_registration(
  p_user_id uuid,p_registration_id uuid,p_expected_revision integer,
  p_legacy_arguments jsonb,p_catalogue_observation jsonb,p_catalogue_decision jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $confirm$
DECLARE
  v_authority private.workout_strength_authority_epochs%ROWTYPE;
  v_admission private.mobile_workout_proposal_admissions%ROWTYPE;
  v_match private.mobile_workout_proposal_admissions%ROWTYPE;
  v_pending public.pending_registrations%ROWTYPE;
  v_lifecycle private.workout_strength_lifecycles%ROWTYPE;
  v_command private.workout_strength_commands%ROWTYPE;
  v_operation private.workout_strength_operations%ROWTYPE;
  v_admission_count integer:=0;
  v_lifecycle_key uuid;
  v_operation_key text;
  v_raw_type text;
  v_provider text;
  v_now timestamptz;
  v_source_instant timestamptz;
  v_performed_instant timestamptz;
  v_registration jsonb;
  v_arguments jsonb;
  v_capture jsonb;
  v_strength jsonb;
  v_resolved jsonb;
  v_gap jsonb;
  v_legacy_result jsonb;
  v_own_negative boolean:=false;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_registration_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0 THEN
    RAISE EXCEPTION 'invalid_mobile_workout_proposal_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'mobile_workout_registration_requires_read_committed' USING ERRCODE='22023';
  END IF;
  -- S8 takes this lock first, even on replay. Never invert its global order.
  LOCK TABLE public.workout_types IN SHARE MODE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile_workout_proposal_patient_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.* INTO v_authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
  FOR v_match IN SELECT a.* FROM private.mobile_workout_proposal_admissions a
    WHERE a.user_id=p_user_id AND a.pending_id=p_registration_id ORDER BY a.admission_id FOR UPDATE LOOP
    v_admission:=v_match;
    v_admission_count:=v_admission_count+1;
  END LOOP;
  IF v_admission_count<>1 OR v_admission.content_revision IS NULL OR v_authority.user_id IS NULL THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  IF v_admission.epoch IS DISTINCT FROM v_authority.epoch THEN
    RETURN '{"status":"forbidden","reason":"stale_epoch"}'::jsonb;
  END IF;
  -- Observe terminal updates or deletion committed during this row wait.
  SELECT p.* INTO v_pending FROM public.pending_registrations p
    WHERE p.user_id=p_user_id AND p.id=p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"pending_missing"}'::jsonb; END IF;
  IF v_pending.workout_ui_admission_id IS DISTINCT FROM v_admission.admission_id
    OR v_admission.pending_id IS DISTINCT FROM v_pending.id
    OR (v_admission.confirmed_lifecycle_key IS NOT NULL AND v_pending.status<>'confirmed') THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  v_provider:=v_pending.proposal->>'source_provider_message_id';
  IF (v_admission.content_revision=0 AND
      (v_provider COLLATE "C") IS DISTINCT FROM (v_admission.request_key COLLATE "C"))
    OR (v_admission.content_revision>0 AND NOT EXISTS (
      SELECT 1 FROM private.mobile_workout_registration_edit_receipts r
      WHERE r.user_id=p_user_id AND r.admission_id=v_admission.admission_id
        AND r.request_key=(v_provider COLLATE "C") AND r.result_revision=v_admission.content_revision)) THEN
    RETURN '{"status":"forbidden","reason":"invalid_admission"}'::jsonb;
  END IF;
  v_registration:=pg_catalog.jsonb_build_object('id',v_pending.id,'status',v_pending.status,
    'created_at',v_pending.created_at,'expires_at',v_pending.expires_at,'resolved_at',v_pending.resolved_at,
    'proposal',v_pending.proposal,'workout_protocol','ui-v1','content_revision',v_admission.content_revision);
  v_operation_key:='ui:'||v_admission.admission_id::text||':r:'||v_admission.content_revision::text;
  v_raw_type:=v_pending.proposal->>'workoutType';

  IF v_pending.status='confirmed' THEN
    IF v_admission.content_revision<>p_expected_revision THEN
      RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_conflict','registration',v_registration);
    END IF;
    v_lifecycle_key:=v_admission.confirmed_lifecycle_key;
    IF v_lifecycle_key IS NULL THEN RETURN '{"status":"forbidden","reason":"invalid_confirmation"}'::jsonb; END IF;
    SELECT l.* INTO v_lifecycle FROM private.workout_strength_lifecycles l
      WHERE l.user_id=p_user_id AND l.lifecycle_key=v_lifecycle_key FOR UPDATE;
    IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb; END IF;
    IF v_lifecycle.closed_at IS NOT NULL OR v_authority.current_lifecycle_key IS DISTINCT FROM v_lifecycle_key THEN
      RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb;
    END IF;
    -- A missing binding is never permission to re-enter a writer on replay.
    SELECT o.* INTO v_operation FROM private.workout_strength_operations o
      WHERE o.user_id=p_user_id AND o.lifecycle_key=v_lifecycle_key AND o.operation_kind='capture'
        AND o.operation_key=(v_operation_key COLLATE "C") AND o.original_operation_type=(v_raw_type COLLATE "C");
    IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"invalid_confirmation"}'::jsonb; END IF;
    v_resolved:=public.resolve_confirmed_workout_strength_capture(p_user_id,v_lifecycle_key,v_operation_key,v_raw_type);
    IF v_resolved->>'status'='forbidden' THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason',v_resolved->>'reason');
    END IF;
    v_gap:=pg_catalog.jsonb_build_object('status','unavailable','reason','legacy_provenance_gap',
      'confirmedWorkoutLogID',v_operation.live_workout_log_id::text);
    IF (v_operation.capture_outcome='fact' AND v_resolved->>'status' IS DISTINCT FROM 'reuse_existing')
      OR (v_operation.capture_outcome='legacy_provenance_gap' AND v_resolved IS DISTINCT FROM v_gap) THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','reused','registration',v_registration,'capture',
      pg_catalog.jsonb_build_object('legacy_result',v_operation.legacy_result,'strength',v_resolved));
  END IF;
  IF v_pending.status<>'pending' THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','not_pending','registration',v_registration);
  END IF;
  IF v_admission.content_revision<>p_expected_revision THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','revision_conflict','registration',v_registration);
  END IF;

  v_lifecycle_key:=v_authority.current_lifecycle_key;
  IF v_lifecycle_key IS NOT NULL THEN
    SELECT l.* INTO v_lifecycle FROM private.workout_strength_lifecycles l
      WHERE l.user_id=p_user_id AND l.lifecycle_key=v_lifecycle_key FOR UPDATE;
    IF NOT FOUND THEN RETURN '{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb; END IF;
    IF v_lifecycle.closed_at IS NOT NULL THEN RETURN '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb; END IF;
  ELSE
    PERFORM 1 FROM private.workout_strength_lifecycles l WHERE l.user_id=p_user_id AND l.closed_at IS NULL FOR UPDATE;
    IF FOUND THEN RETURN '{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb; END IF;
  END IF;
  -- TTL is a wall clock after all authority/lifecycle row waits, not transaction now().
  v_now:=pg_catalog.clock_timestamp();
  IF v_pending.expires_at<=v_now THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','expired','registration',v_registration);
  END IF;
  IF v_lifecycle_key IS NOT NULL THEN
    SELECT c.* INTO v_command FROM private.workout_strength_commands c
      WHERE c.user_id=p_user_id AND c.lifecycle_key=v_lifecycle_key
        AND c.operation_key=(v_operation_key COLLATE "C") AND c.original_operation_type=(v_raw_type COLLATE "C");
  END IF;
  IF v_command.user_id IS NULL AND p_legacy_arguments IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','preparation_required','registration',v_registration);
  END IF;

  -- Only this block may mutate. A legitimate negative from S8 must undo even
  -- the life and S7 preparation before its JSON result can leave the function.
  BEGIN
    IF v_lifecycle_key IS NULL THEN
      v_lifecycle_key:=pg_catalog.gen_random_uuid();
      INSERT INTO private.workout_strength_lifecycles(user_id,lifecycle_key,opened_at)
        VALUES(p_user_id,v_lifecycle_key,pg_catalog.clock_timestamp());
      UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=v_lifecycle_key
        WHERE user_id=p_user_id AND epoch=v_admission.epoch RETURNING * INTO STRICT v_authority;
    END IF;
    PERFORM public.read_or_admit_workout_strength_command(
      p_user_id,v_lifecycle_key,v_operation_key,v_raw_type,p_legacy_arguments);
    SELECT c.* INTO STRICT v_command FROM private.workout_strength_commands c
      WHERE c.user_id=p_user_id AND c.lifecycle_key=v_lifecycle_key
        AND c.operation_key=(v_operation_key COLLATE "C") AND c.original_operation_type=(v_raw_type COLLATE "C");
    v_arguments:=v_command.legacy_arguments;
    -- Cast only the chosen S7 value; do not reconstruct or normalize its JSONB.
    -- This narrow decoder never catches errors from S7, locks or the real writer.
    BEGIN
      v_source_instant:=(v_pending.proposal->>'source_timestamp')::timestamptz;
      v_performed_instant:=(v_arguments->>'p_performed_at')::timestamptz;
      IF (v_arguments->>'p_user_id')::uuid IS DISTINCT FROM p_user_id
        OR ((v_arguments->>'p_workout_type') COLLATE "C") IS DISTINCT FROM (v_raw_type COLLATE "C")
        OR (v_arguments->>'p_duration_min')::numeric IS DISTINCT FROM (v_pending.proposal->>'durationMin')::numeric
        OR v_arguments->'p_intensity' IS DISTINCT FROM v_pending.proposal->'intensity'
        OR ((v_arguments->>'p_provider_message_id') COLLATE "C") IS DISTINCT FROM (v_provider COLLATE "C")
        OR v_source_instant IS NULL OR NOT pg_catalog.isfinite(v_source_instant)
        OR v_performed_instant IS NULL OR NOT pg_catalog.isfinite(v_performed_instant)
        OR v_performed_instant IS DISTINCT FROM v_source_instant
        OR v_arguments->'p_replace_recent' IS DISTINCT FROM 'false'::jsonb
        OR v_arguments->'p_replace_since' IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'invalid_mobile_workout_registration_preparation' USING ERRCODE='22023';
      END IF;
    EXCEPTION WHEN data_exception THEN
      RAISE EXCEPTION 'invalid_mobile_workout_registration_preparation' USING ERRCODE='22023';
    END;
    -- kcal, targets, notes and date remain the first official preparation.
    -- The current producer recalculates them; preview equality is not required.
    v_capture:=private.register_workout_strength_core(
      p_user_id,v_lifecycle_key,v_operation_key,v_raw_type,p_catalogue_observation,p_catalogue_decision);
    IF pg_catalog.jsonb_typeof(v_capture) IS DISTINCT FROM 'object'
      OR NOT (v_capture ?& ARRAY['legacy_result','strength'])
      OR v_capture-ARRAY['legacy_result','strength']<>'{}'::jsonb
      OR pg_catalog.jsonb_typeof(v_capture->'strength') IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    v_strength:=v_capture->'strength';
    IF NOT (COALESCE(v_strength->>'status' IN ('committed','reuse_existing'),false)
      OR (v_strength->>'status'='unavailable' AND v_strength->>'reason'='legacy_provenance_gap')) THEN
      IF v_strength->>'status' IN ('forbidden','conflict','unavailable') THEN
        v_own_negative:=true;
        RAISE EXCEPTION 'mobile_workout_registration_capture_not_accepted' USING ERRCODE='P17D0';
      END IF;
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    SELECT o.* INTO v_operation FROM private.workout_strength_operations o
      WHERE o.user_id=p_user_id AND o.lifecycle_key=v_lifecycle_key AND o.operation_kind='capture'
        AND o.operation_key=(v_operation_key COLLATE "C") AND o.original_operation_type=(v_raw_type COLLATE "C");
    IF NOT FOUND THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    v_resolved:=public.resolve_confirmed_workout_strength_capture(p_user_id,v_lifecycle_key,v_operation_key,v_raw_type);
    v_legacy_result:=COALESCE(v_operation.legacy_result,'null'::jsonb);
    v_gap:=pg_catalog.jsonb_build_object('status','unavailable','reason','legacy_provenance_gap',
      'confirmedWorkoutLogID',v_operation.live_workout_log_id::text);
    IF (v_capture->'legacy_result')::text IS DISTINCT FROM v_legacy_result::text
      OR (v_operation.capture_outcome='fact' AND (
        NOT COALESCE(v_strength->>'status' IN ('committed','reuse_existing'),false)
        OR v_resolved->>'status' IS DISTINCT FROM 'reuse_existing'
        OR (v_strength||'{"status":"reuse_existing"}'::jsonb) IS DISTINCT FROM v_resolved))
      OR (v_operation.capture_outcome='legacy_provenance_gap' AND
        (v_strength IS DISTINCT FROM v_gap OR v_resolved IS DISTINCT FROM v_gap)) THEN
      RAISE EXCEPTION 'mobile_workout_registration_confirmation_unproved' USING ERRCODE='P0002';
    END IF;
    UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=v_lifecycle_key
      WHERE user_id=p_user_id AND admission_id=v_admission.admission_id AND content_revision=p_expected_revision
      RETURNING * INTO STRICT v_admission;
    UPDATE public.pending_registrations SET status='confirmed',resolved_at=pg_catalog.clock_timestamp()
      WHERE user_id=p_user_id AND id=p_registration_id AND status='pending' RETURNING * INTO STRICT v_pending;
    PERFORM private.bind_mobile_strength_week_lifecycle(
      p_user_id,v_admission.admission_id,v_lifecycle_key);
  EXCEPTION WHEN SQLSTATE 'P17D0' THEN
    -- A native P17D0 from a writer/trigger is not our control signal.
    IF NOT v_own_negative THEN RAISE; END IF;
  END;
  IF v_own_negative THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','capture_not_accepted',
      'registration',v_registration,'capture',v_capture);
  END IF;
  v_registration:=pg_catalog.jsonb_build_object('id',v_pending.id,'status',v_pending.status,
    'created_at',v_pending.created_at,'expires_at',v_pending.expires_at,'resolved_at',v_pending.resolved_at,
    'proposal',v_pending.proposal,'workout_protocol','ui-v1','content_revision',v_admission.content_revision);
  RETURN pg_catalog.jsonb_build_object('status','confirmed','registration',v_registration,'capture',v_capture);
END $confirm$;
REVOKE ALL ON FUNCTION public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb) TO service_role;

DO $privileges$
BEGIN
  IF EXISTS (
    WITH objects AS (
      SELECT p.oid,p.proowner AS owner_id,p.proacl AS acl FROM pg_catalog.pg_proc p
      WHERE p.oid='public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)'::regprocedure
    ), actual AS (
      SELECT o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(o.acl,pg_catalog.acldefault('f',o.owner_id))) a
    ), expected AS (
      SELECT o.oid,'postgres'::regrole::oid AS grantor,'postgres'::regrole::oid AS grantee,
        'EXECUTE'::text AS privilege_type,false AS is_grantable FROM objects o
      UNION ALL SELECT o.oid,'postgres'::regrole::oid,'service_role'::regrole::oid,'EXECUTE',false FROM objects o
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    ) SELECT 1 FROM objects WHERE owner_id<>'postgres'::regrole UNION ALL SELECT 1 FROM differences
  ) OR pg_catalog.has_function_privilege('anon','public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)','EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated','public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'mobile_workout_registration_unexpected_confirmation_acl' USING ERRCODE='42501';
  END IF;
END $privileges$;

COMMIT;

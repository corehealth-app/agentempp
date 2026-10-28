-- A confirmed FULL can attest a prospective frequency without becoming signup.
-- Current-week targets, old receipts and unknown workout history are untouched.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_generation_sources') IS NULL
  OR to_regclass('private.mobile_clinical_full_receipts') IS NULL
  OR to_regclass('private.strength_week_source_versions') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_requires_substrate' USING ERRCODE='55000';
 END IF;
 IF to_regclass('private.mobile_clinical_strength_week_sources') IS NOT NULL
  OR to_regprocedure('private.capture_mobile_clinical_strength_week_source(uuid,uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_unknown_existing_object' USING ERRCODE='42P07';
 END IF;
 IF (SELECT encode(extensions.digest(convert_to(prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc
  WHERE oid='private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)'::regprocedure)
  IS DISTINCT FROM 'ddb568c691e155b19ff632cadc58436ed1dbe848f7069949758962e55626ef9c' THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_writer_drift' USING ERRCODE='55000';
 END IF;
END $preflight$;

CREATE TABLE private.mobile_clinical_strength_week_sources(
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 clinical_generation uuid NOT NULL,
 epoch uuid NOT NULL,
 week_generation uuid NOT NULL,
 frequency_source_version_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(recorded_at)),
 PRIMARY KEY(user_id,review_id),
 UNIQUE(user_id,week_generation,frequency_source_version_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) ON DELETE CASCADE,
 FOREIGN KEY(user_id,clinical_generation) REFERENCES private.mobile_clinical_generation_sources(user_id,generation) ON DELETE CASCADE,
 FOREIGN KEY(user_id,week_generation,frequency_source_version_id)
  REFERENCES private.strength_week_source_versions(user_id,generation,source_version_id) ON DELETE CASCADE
);
ALTER TABLE private.mobile_clinical_strength_week_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_clinical_strength_week_sources FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.guard_mobile_clinical_strength_week_source() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $guard$
BEGIN
 -- Derived referential metadata follows an actual declared parent's lifetime.
 -- Never permit a direct DELETE while its owner/source still exists, including
 -- softdelete; only the parent's real FK cascade can enter this exception.
 IF TG_OP='DELETE' AND pg_trigger_depth()>1 AND current_user IN('postgres','service_role') AND (
  NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)
  OR NOT EXISTS(SELECT 1 FROM private.mobile_clinical_generation_sources
   WHERE user_id=OLD.user_id AND generation=OLD.clinical_generation)
  OR NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts
   WHERE user_id=OLD.user_id AND review_id=OLD.review_id)
  OR NOT EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=OLD.user_id
   AND generation=OLD.week_generation AND source_version_id=OLD.frequency_source_version_id)
 ) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'mobile_clinical_week_source_immutable' USING ERRCODE='55000';
END $guard$;
CREATE TRIGGER mobile_clinical_strength_week_source_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_strength_week_sources FOR EACH ROW
 EXECUTE FUNCTION private.guard_mobile_clinical_strength_week_source();
REVOKE ALL ON FUNCTION private.guard_mobile_clinical_strength_week_source() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.capture_mobile_clinical_strength_week_source(p_user_id uuid,p_review_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $capture$
DECLARE
 full_receipt private.mobile_clinical_full_receipts%ROWTYPE;
 clinical_source private.mobile_clinical_generation_sources%ROWTYPE;
 scope private.strength_week_scopes%ROWTYPE;
 prior_origin private.mobile_clinical_strength_week_sources%ROWTYPE;
 signup private.mobile_signup_strength_completion_receipts%ROWTYPE;
 current_epoch uuid;frequency smallint;captured jsonb;source_id uuid;
 unavailable constant jsonb:='{"status":"unavailable","reason":"clinical_frequency_unproved"}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_review_id IS NULL THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_week_source_input' USING ERRCODE='22023';
 END IF;
 -- FULL already owns the user fence. Never acquire a late workouts advisory lock.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_week_source_patient_not_found' USING ERRCODE='P0002'; END IF;
 SELECT * INTO full_receipt FROM private.mobile_clinical_full_receipts
  WHERE user_id=p_user_id AND review_id=p_review_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_week_source_receipt_missing' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior_origin FROM private.mobile_clinical_strength_week_sources
  WHERE user_id=p_user_id AND review_id=p_review_id;
 -- Only the writer calls this on first confirmation. An explicit internal replay
 -- is observational too: no open/capture or reset resurrection.
 IF FOUND THEN
  RETURN jsonb_build_object('status','reused','generation',prior_origin.week_generation,
   'frequency_source_version_id',prior_origin.frequency_source_version_id);
 END IF;
 IF full_receipt.kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL')
  OR full_receipt.form#>>'{answers,strengthSessions}' IS NULL THEN RETURN unavailable; END IF;
 IF jsonb_typeof(full_receipt.form#>'{answers,strengthSessions}')<>'number'
  OR (full_receipt.form#>>'{answers,strengthSessions}')::numeric NOT BETWEEN 0 AND 7
  OR trunc((full_receipt.form#>>'{answers,strengthSessions}')::numeric)
   IS DISTINCT FROM (full_receipt.form#>>'{answers,strengthSessions}')::numeric THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_frequency_invalid' USING ERRCODE='XX001';
 END IF;
 frequency:=(full_receipt.form#>>'{answers,strengthSessions}')::smallint;
 IF (full_receipt.proposal#>>'{profile,training_frequency}')::smallint IS DISTINCT FROM frequency
  OR NOT EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=p_user_id AND training_frequency=frequency) THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_frequency_not_applied' USING ERRCODE='XX001';
 END IF;
 SELECT * INTO clinical_source FROM private.mobile_clinical_generation_sources
  WHERE user_id=p_user_id AND generation=full_receipt.signup_generation;
 SELECT epoch INTO current_epoch FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF clinical_source.epoch IS DISTINCT FROM full_receipt.signup_epoch OR current_epoch IS DISTINCT FROM full_receipt.signup_epoch
  OR clinical_source.kind NOT IN('signup_receipt','legacy_transition') THEN RETURN unavailable; END IF;
 SELECT * INTO scope FROM private.strength_week_scopes WHERE user_id=p_user_id AND closed_at IS NULL FOR UPDATE;
 IF FOUND THEN
  IF scope.open_operation_namespace='mobile_signup_completion_v1' AND scope.predecessor_generation IS NULL THEN
   SELECT * INTO signup FROM private.mobile_signup_strength_completion_receipts
    WHERE user_id=p_user_id AND generation=scope.generation AND outcome='first_fresh'
     AND epoch=current_epoch AND admission_id::text=scope.open_operation_key;
   IF NOT FOUND THEN RETURN unavailable; END IF;
  ELSIF scope.open_operation_namespace='mobile_clinical_full_frequency_v1' AND scope.predecessor_generation IS NULL THEN
   IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_strength_week_sources o
    WHERE o.user_id=p_user_id AND o.week_generation=scope.generation AND o.epoch=current_epoch
     AND o.review_id::text=scope.open_operation_key) THEN RETURN unavailable; END IF;
  ELSE RETURN unavailable;
  END IF;
 ELSE
  -- The FULL owns this clock after the user fence. Sampling a second clock
  -- here could cross local Monday and postpone the source by an extra week.
  -- A new scope opens at this actual receipt, never at an invented signup.
  INSERT INTO private.strength_week_scopes(user_id,open_operation_namespace,open_operation_key,opened_at)
   VALUES(p_user_id,'mobile_clinical_full_frequency_v1',p_review_id::text,full_receipt.completed_at)
   RETURNING * INTO scope;
 END IF;
 captured:=private.capture_strength_week_source_at(p_user_id,scope.generation,'informed_frequency','value',
  frequency,NULL,NULL,'mobile_clinical_full_frequency_v1',p_review_id::text,full_receipt.completed_at);
 source_id:=(captured->>'source_version_id')::uuid;
 IF source_id IS NULL THEN RAISE EXCEPTION 'mobile_clinical_week_source_capture_invalid' USING ERRCODE='XX001'; END IF;
 -- Observation of absence has prospective coverage only. An active legacy plan
 -- is never relabelled as accepted; its draft needs a real confirmation instead.
 IF NOT EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=p_user_id AND active) THEN
  PERFORM private.capture_strength_week_source_at(p_user_id,scope.generation,'accepted_plan','absent',
   NULL,NULL,NULL,'mobile_clinical_full_plan_absence_v1',p_review_id::text,full_receipt.completed_at);
 END IF;
 INSERT INTO private.mobile_clinical_strength_week_sources(user_id,review_id,clinical_generation,epoch,
  week_generation,frequency_source_version_id)
 VALUES(p_user_id,p_review_id,full_receipt.signup_generation,full_receipt.signup_epoch,scope.generation,source_id);
 RETURN jsonb_build_object('status','captured','generation',scope.generation,'frequency_source_version_id',source_id);
END $capture$;
REVOKE ALL ON FUNCTION private.capture_mobile_clinical_strength_week_source(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $hook$
DECLARE
 target constant regprocedure:='private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)'::regprocedure;
 original text;definition text;metadata jsonb;after_metadata jsonb;changed text;
 needle constant text:=$needle$ PERFORM private.apply_mobile_clinical_preference(p_user_id,p_preview_id);$needle$;
 addition constant text:=$addition$ -- Only a frequency explicitly accepted and applied through the safe FULL branch
 -- attests a new weekly source. An opt-out, safety hold or unchanged fallback
 -- cannot turn a mutable profile into historical proof.
 IF preview.review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL')
  AND NOT unknown_guard AND NOT no_plan AND NOT loss_guard AND NOT effective_hold
  AND p_form#>>'{answers,strengthSessions}' IS NOT NULL
  AND (p_form#>>'{answers,strengthSessions}')::smallint IS NOT DISTINCT FROM new_frequency THEN
  PERFORM private.capture_mobile_clinical_strength_week_source(p_user_id,p_preview_id);
 END IF;
$addition$;
BEGIN
 SELECT prosrc,pg_get_functiondef(oid),to_jsonb(p)-'prosrc' INTO STRICT original,definition,metadata FROM pg_proc p WHERE oid=target;
 IF encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex')
  IS DISTINCT FROM 'ddb568c691e155b19ff632cadc58436ed1dbe848f7069949758962e55626ef9c'
  OR (length(original)-length(replace(original,needle,'')))/length(needle)<>1 THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_hook_drift' USING ERRCODE='55000'; END IF;
 changed:=replace(original,needle,addition||needle);EXECUTE replace(definition,original,changed);
 SELECT to_jsonb(p)-'prosrc' INTO STRICT after_metadata FROM pg_proc p WHERE oid=target;
 IF after_metadata IS DISTINCT FROM metadata OR (SELECT prosrc FROM pg_proc WHERE oid=target) IS DISTINCT FROM changed THEN
  RAISE EXCEPTION 'mobile_clinical_week_source_hook_contract_changed' USING ERRCODE='55000'; END IF;
END $hook$;
COMMIT;


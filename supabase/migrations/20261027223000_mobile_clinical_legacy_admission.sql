-- Present authority for an existing completed account without proven signup.
-- Dormant private foundation: no route, public grant, calendar/FULL or photo
-- activation. The complete transition chain must be integrated before release.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  OR to_regprocedure('private.mobile_reevaluation_lock_owner(uuid)') IS NULL
  OR to_regprocedure('private.mobile_reevaluation_context_at(uuid,timestamptz)') IS NULL
  OR to_regprocedure('private.mobile_clinical_evidence_immutable()') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_legacy_requires_existing_authority' USING ERRCODE='42501';
 END IF;
 IF to_regclass('private.mobile_clinical_legacy_admissions') IS NOT NULL THEN
  RAISE EXCEPTION 'mobile_clinical_legacy_unknown_existing_object' USING ERRCODE='42P07';
 END IF;
END $preflight$;

CREATE TABLE private.mobile_clinical_legacy_admissions(
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 generation uuid NOT NULL DEFAULT gen_random_uuid(),
 epoch uuid NOT NULL,
 admitted_at timestamptz NOT NULL CHECK(isfinite(admitted_at)),
 admitted_date date NOT NULL CHECK(isfinite(admitted_date)
  AND admitted_date BETWEEN DATE '0001-01-01' AND DATE '9999-12-17'),
 timezone_at_admission text NOT NULL CHECK(length(timezone_at_admission)>0),
 -- This is a reset/CAS marker observed now, not proof of the old signup date.
 profile_completed_marker timestamptz CHECK(isfinite(profile_completed_marker)),
 PRIMARY KEY(user_id,generation),UNIQUE(generation),UNIQUE(user_id,epoch),
 CHECK(profile_completed_marker<=admitted_at),
 CHECK(admitted_date=(admitted_at AT TIME ZONE timezone_at_admission)::date)
);
ALTER TABLE private.mobile_clinical_legacy_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_clinical_legacy_admissions FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_legacy_admission_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_legacy_admissions FOR EACH ROW
 EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.mobile_clinical_legacy_admission_wire(
 p_row private.mobile_clinical_legacy_admissions) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('kind','legacy_transition','user_id',(p_row).user_id,
  'generation',(p_row).generation,'epoch',(p_row).epoch,
  'admitted_at',to_char((p_row).admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'admitted_date',(p_row).admitted_date::text,'timezone_at_admission',(p_row).timezone_at_admission,
  'profile_completed_marker',to_char((p_row).profile_completed_marker AT TIME ZONE 'UTC',
   'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

-- Observation never initializes an epoch or an admission. An old generation
-- stops being authority after reset, epoch rotation or completion-marker drift.
CREATE FUNCTION private.read_mobile_clinical_legacy_generation_at(
 p_user_id uuid,p_observed_at timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE observed timestamptz; a private.mobile_clinical_legacy_admissions%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 observed:=coalesce(p_observed_at,clock_timestamp());
 IF p_user_id IS NULL OR NOT isfinite(observed)
  OR extract(year FROM observed AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_legacy_input' USING ERRCODE='22023';
 END IF;
 SELECT x.* INTO a FROM private.mobile_clinical_legacy_admissions x
  JOIN public.users u ON u.id=x.user_id AND u.status='active'
  JOIN public.user_profiles p ON p.user_id=x.user_id AND p.onboarding_completed IS TRUE
   AND p.onboarding_completed_at IS NOT DISTINCT FROM x.profile_completed_marker
  JOIN private.workout_strength_authority_epochs e ON e.user_id=x.user_id AND e.epoch=x.epoch
  WHERE x.user_id=p_user_id AND x.admitted_at<=observed AND e.changed_at<=observed;
 IF NOT FOUND THEN RETURN NULL; END IF;
 RETURN private.mobile_clinical_legacy_admission_wire(a);
END $$;

-- Explicit private boundary. Public callers will pass no clock when the full
-- integration is ready. This does not call onboarding completion, open a
-- strength scope, invent frequency, create a FULL or change any stored target.
CREATE FUNCTION private.admit_mobile_clinical_legacy_generation_at(
 p_user_id uuid,p_observed_at timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE p public.user_profiles%ROWTYPE;u public.users%ROWTYPE;
 e private.workout_strength_authority_epochs%ROWTYPE;
 a private.mobile_clinical_legacy_admissions%ROWTYPE;
 r private.mobile_signup_strength_completion_receipts%ROWTYPE;
 observed timestamptz; anchor jsonb; zone text; day date;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_legacy_input' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 BEGIN
  SELECT * INTO p FROM public.user_profiles WHERE user_id=p_user_id FOR UPDATE NOWAIT;
  IF NOT FOUND OR p.onboarding_completed IS DISTINCT FROM true THEN
   RETURN jsonb_build_object('version',1,'availability','unavailable','reason','onboarding_incomplete');
  END IF;
  SELECT * INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'mobile_clinical_legacy_busy' USING ERRCODE='55P03';
 END;
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user_id;
 observed:=coalesce(p_observed_at,clock_timestamp());zone:=u.timezone;
 IF NOT isfinite(observed) OR extract(year FROM observed AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
  OR (p.onboarding_completed_at IS NOT NULL AND NOT isfinite(p.onboarding_completed_at))
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_legacy_input' USING ERRCODE='22023';
 END IF;
 day:=(observed AT TIME ZONE zone)::date;
 IF day NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-17' THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_legacy_input' USING ERRCODE='22023'; END IF;
 IF p.onboarding_completed_at>observed OR e.changed_at>observed THEN
  RAISE EXCEPTION 'mobile_clinical_legacy_clock_reversed' USING ERRCODE='40001'; END IF;

 -- A genuine proof stays genuine; a corrupt current proof must not be rescued
 -- by calling it legacy. The existing validator retains all its original gates.
 SELECT * INTO r FROM private.mobile_signup_strength_completion_receipts
  WHERE user_id=p_user_id AND epoch=e.epoch AND outcome='first_fresh';
 IF FOUND THEN
  IF r.completed_at IS DISTINCT FROM p.onboarding_completed_at THEN
   RAISE EXCEPTION 'mobile_clinical_legacy_signup_corrupt' USING ERRCODE='XX001'; END IF;
  anchor:=private.mobile_reevaluation_context_at(p_user_id,observed);
  IF (anchor->>'signup_generation')::uuid IS DISTINCT FROM r.admission_id
   OR (anchor->>'signup_epoch')::uuid IS DISTINCT FROM e.epoch THEN
   RAISE EXCEPTION 'mobile_clinical_legacy_signup_corrupt' USING ERRCODE='XX001'; END IF;
  RETURN jsonb_build_object('version',1,'availability','signup_proven',
   'generation',r.admission_id,'epoch',e.epoch);
 END IF;
 IF e.user_id IS NULL THEN
  INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
   VALUES(p_user_id,gen_random_uuid(),observed) RETURNING * INTO e;
 END IF;
 SELECT * INTO a FROM private.mobile_clinical_legacy_admissions WHERE user_id=p_user_id AND epoch=e.epoch;
 IF FOUND THEN
  IF a.profile_completed_marker IS DISTINCT FROM p.onboarding_completed_at OR a.admitted_at>observed THEN
   RAISE EXCEPTION 'mobile_clinical_legacy_changed' USING ERRCODE='40001'; END IF;
 ELSE
  INSERT INTO private.mobile_clinical_legacy_admissions(user_id,epoch,admitted_at,admitted_date,
   timezone_at_admission,profile_completed_marker)
   VALUES(p_user_id,e.epoch,observed,day,zone,p.onboarding_completed_at) RETURNING * INTO a;
 END IF;
 RETURN jsonb_build_object('version',1,'availability','admitted',
  'authority',private.mobile_clinical_legacy_admission_wire(a));
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_legacy_admission_wire(private.mobile_clinical_legacy_admissions),
 private.read_mobile_clinical_legacy_generation_at(uuid,timestamptz),
 private.admit_mobile_clinical_legacy_generation_at(uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

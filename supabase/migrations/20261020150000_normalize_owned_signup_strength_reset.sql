-- Reset is shared with legacy callers. Normalize only the exact completion
-- attested by a first_fresh receipt from the new mobile signup writer.
-- Existing reset and photo-normalizer definitions remain unchanged.
BEGIN;
SET LOCAL search_path = pg_catalog;

DO $preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_signup_strength_reset_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL
    OR to_regclass('public.user_profiles') IS NULL THEN
    RAISE EXCEPTION 'mobile_signup_strength_reset_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='private' AND p.proname='normalize_mobile_signup_strength_receipted_reset')
    OR EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.user_profiles'::regclass
      AND t.tgname='normalize_mobile_signup_strength_receipted_reset') THEN
    RAISE EXCEPTION 'mobile_signup_strength_reset_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE FUNCTION private.normalize_mobile_signup_strength_receipted_reset()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $normalize$
BEGIN
  IF NEW.user_id IS NOT DISTINCT FROM OLD.user_id
    AND NEW.onboarding_completed_at IS NOT DISTINCT FROM OLD.onboarding_completed_at
    AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r
      WHERE r.user_id=OLD.user_id AND r.outcome='first_fresh'
        AND r.completed_at=OLD.onboarding_completed_at) THEN
    NEW.onboarding_completed_at := NULL;
  END IF;
  RETURN NEW;
END $normalize$;
REVOKE ALL ON FUNCTION private.normalize_mobile_signup_strength_receipted_reset()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER normalize_mobile_signup_strength_receipted_reset
  BEFORE UPDATE OF onboarding_completed ON public.user_profiles
  FOR EACH ROW WHEN (OLD.onboarding_completed IS TRUE AND NEW.onboarding_completed IS FALSE
    AND OLD.onboarding_completed_at IS NOT NULL)
  EXECUTE FUNCTION private.normalize_mobile_signup_strength_receipted_reset();

DO $acl$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_proc p,
    LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE p.oid='private.normalize_mobile_signup_strength_receipted_reset()'::regprocedure
      AND a.grantee<>p.proowner) THEN
    RAISE EXCEPTION 'mobile_signup_strength_reset_unexpected_inherited_grant' USING ERRCODE='42501';
  END IF;
END $acl$;
COMMIT;

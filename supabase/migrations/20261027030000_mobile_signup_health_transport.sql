-- One narrow backend transport; private legal/intent/health authority unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.admit_mobile_signup_health(uuid,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'signup_health_transport_requires_private_authority' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.admit_mobile_signup_health(p_user_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_signup_health_owner' USING ERRCODE='22023'; END IF;
 RETURN private.admit_mobile_signup_health(p_user_id,p_command);
END $$;
REVOKE ALL ON FUNCTION public.admit_mobile_signup_health(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_mobile_signup_health(uuid,jsonb) TO service_role;
COMMIT;

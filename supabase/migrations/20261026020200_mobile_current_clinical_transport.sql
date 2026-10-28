-- Additive backend transport. No clinical writer, app feature activation or clock input.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'mobile_current_clinical_transport_requires_capture' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.get_mobile_current_clinical_state(p_user_id uuid,p_mode text,p_body jsonb,p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_current_clinical_state_at(p_user_id,p_mode,p_body,p_expected,NULL);
END $$;
REVOKE ALL ON FUNCTION public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb) TO service_role;
COMMIT;

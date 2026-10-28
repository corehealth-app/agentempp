-- Explicit service-only admission port. No route/flag activation; profile,
-- onboarding acts, targets and the old completion marker remain unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.admit_mobile_clinical_legacy_generation_at(uuid,timestamptz)') IS NULL
  OR to_regclass('private.mobile_clinical_generation_sources') IS NULL THEN
  RAISE EXCEPTION 'legacy_admission_transport_requires_source' USING ERRCODE='42501';END IF;
 IF to_regprocedure('public.admit_mobile_clinical_legacy_generation(uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'legacy_admission_transport_unknown_existing_object' USING ERRCODE='42P07';END IF;
END $preflight$;
CREATE FUNCTION public.admit_mobile_clinical_legacy_generation(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE message text;detail text;hint text;
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.admit_mobile_clinical_legacy_generation_at(p_user_id,NULL);
EXCEPTION WHEN serialization_failure THEN
 -- Translate only this outer RPC under PostgREST's server-owned context.
 -- Nested/direct SQL retains the original serialization failure.
 IF current_setting('request.path',true)='/rpc/admit_mobile_clinical_legacy_generation'
  AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
  GET STACKED DIAGNOSTICS message=MESSAGE_TEXT,detail=PG_EXCEPTION_DETAIL,hint=PG_EXCEPTION_HINT;
  RAISE SQLSTATE 'PGRST' USING MESSAGE=jsonb_build_object('code','40001','message',message,
   'details',nullif(detail,''),'hint',nullif(hint,''))::text,DETAIL='{"status":409,"headers":{}}';
 END IF;
 RAISE;
END $$;
REVOKE ALL ON FUNCTION public.admit_mobile_clinical_legacy_generation(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_mobile_clinical_legacy_generation(uuid) TO service_role;
COMMIT;

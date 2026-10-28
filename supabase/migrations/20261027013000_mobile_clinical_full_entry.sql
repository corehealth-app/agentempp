-- Clock-free FULL entry; the existing authority owns kind/promotion/generation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.start_mobile_clinical_full_at(uuid,uuid,text,text,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'full_entry_requires_clinical_authority' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.start_mobile_clinical_full(p_user_id uuid,p_operation_key uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL
  OR (p_reason IS NOT NULL AND p_reason NOT IN('gain_review_notice','not_well_with_plan')) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_start' USING ERRCODE='22023'; END IF;
 RETURN private.start_mobile_clinical_full_at(p_user_id,p_operation_key,
  CASE WHEN p_reason IS NULL THEN 'REGULAR' ELSE 'EARLY_FULL' END,p_reason,NULL);
END $$;
REVOKE ALL ON FUNCTION public.start_mobile_clinical_full(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.start_mobile_clinical_full(uuid,uuid,text) TO service_role;
COMMIT;

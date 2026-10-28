-- Additive service-only transport. No app route, flag, cron or public clock.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)') IS NULL
  OR to_regprocedure('private.apply_mobile_clinical_daily_at(uuid,uuid,text,jsonb,timestamptz)') IS NULL
  OR to_regclass('private.mobile_clinical_daily_keys') IS NULL THEN
  RAISE EXCEPTION 'clinical_daily_transport_requires_authority' USING ERRCODE='42501';
 END IF;
END $$;
CREATE FUNCTION public.get_mobile_clinical_daily_receipt(p_user_id uuid,p_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE packet jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_daily_receipt_key' USING ERRCODE='22023'; END IF;
 SELECT jsonb_build_object('user_id',k.user_id,'operation_key',k.operation_key,'result',k.result)
  INTO packet FROM private.mobile_clinical_daily_keys k
  WHERE k.user_id=p_user_id AND k.operation_key=p_operation_key;
 RETURN packet;
END $$;
CREATE FUNCTION public.get_mobile_clinical_daily_context(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_daily_owner' USING ERRCODE='22023'; END IF;
 RETURN private.capture_mobile_clinical_context_at(p_user_id,'APPLICATION',NULL,NULL);
END $$;
CREATE FUNCTION public.apply_mobile_clinical_daily(p_user_id uuid,p_operation_key uuid,p_context_hash text,p_calculation jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_daily_owner' USING ERRCODE='22023'; END IF;
 -- Delegate directly: receipt replay must precede recapture in the authority.
 RETURN jsonb_build_object('user_id',p_user_id,'operation_key',p_operation_key,'result',
  private.apply_mobile_clinical_daily_at(p_user_id,p_operation_key,p_context_hash,p_calculation,NULL));
END $$;
REVOKE ALL ON FUNCTION public.get_mobile_clinical_daily_receipt(uuid,uuid),
 public.get_mobile_clinical_daily_context(uuid),public.apply_mobile_clinical_daily(uuid,uuid,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_daily_receipt(uuid,uuid),
 public.get_mobile_clinical_daily_context(uuid),public.apply_mobile_clinical_daily(uuid,uuid,text,jsonb) TO service_role;
COMMIT;

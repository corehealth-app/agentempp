-- Dormant backend-only FULL transport. No route, clock input or activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.prepare_mobile_clinical_preview_at(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,timestamptz)') IS NULL
  OR to_regprocedure('private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)') IS NULL
  OR to_regclass('private.mobile_clinical_full_receipts') IS NULL THEN
  RAISE EXCEPTION 'clinical_full_transport_requires_authority' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.get_mobile_clinical_full_context(p_user_id uuid,p_kind text,p_cycle_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','SAFETY','ROUTINE_REVIEW') THEN
  RAISE EXCEPTION 'invalid_clinical_full_scope' USING ERRCODE='22023'; END IF;
 RETURN private.capture_mobile_clinical_context_at(p_user_id,p_kind,p_cycle_id,NULL);
END $$;
CREATE FUNCTION public.prepare_mobile_clinical_full(p_user_id uuid,p_kind text,p_cycle_id uuid,
 p_operation_key uuid,p_context_hash text,p_form jsonb,p_intent jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_full_owner' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('user_id',p_user_id,'operation_key',p_operation_key,'preview',
  private.prepare_mobile_clinical_preview_at(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_form,p_intent,p_proposal,NULL));
END $$;
CREATE FUNCTION public.get_mobile_clinical_full_receipt(p_user_id uuid,p_preview_id uuid,p_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE receipt private.mobile_clinical_full_receipts%ROWTYPE;matched boolean:=false;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_preview_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_full_receipt_key' USING ERRCODE='22023'; END IF;
 SELECT r.* INTO receipt FROM private.mobile_clinical_confirmation_keys k
  JOIN private.mobile_clinical_full_receipts r ON r.user_id=k.user_id AND r.review_id=k.review_id
  WHERE k.user_id=p_user_id AND k.operation_key=p_operation_key;
 IF FOUND THEN
  IF receipt.preview_id<>p_preview_id THEN
   RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001'; END IF;
  matched:=true;
 ELSE
  SELECT r.* INTO receipt FROM private.mobile_clinical_full_receipts r
   WHERE r.user_id=p_user_id AND r.preview_id=p_preview_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
 END IF;
 -- Backend projection only, never an app DTO. If matched=false the service
 -- must delegate confirmation with the original package to bind the alias key
 -- before recapture; this read alone never reserves a key or applies effects.
 RETURN jsonb_build_object('user_id',receipt.user_id,'preview_id',receipt.preview_id,
  'operation_key',p_operation_key,'operation_matched',matched,'review_no',receipt.review_no::text,
  'form',receipt.form,'intent',receipt.intent,'proposal',receipt.proposal,'result',receipt.result);
END $$;
CREATE FUNCTION public.confirm_mobile_clinical_full(p_user_id uuid,p_preview_id uuid,p_operation_key uuid,
 p_form jsonb,p_intent jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_full_owner' USING ERRCODE='22023'; END IF;
 -- Replay and original-key conflicts are decided by the atomic authority
 -- before any current capture. Never pre-capture here.
 RETURN jsonb_build_object('user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,'result',
  private.confirm_mobile_clinical_preview_at(p_user_id,p_preview_id,p_operation_key,p_form,p_intent,p_proposal,NULL));
END $$;
REVOKE ALL ON FUNCTION public.get_mobile_clinical_full_context(uuid,text,uuid),
 public.prepare_mobile_clinical_full(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb),
 public.get_mobile_clinical_full_receipt(uuid,uuid,uuid),
 public.confirm_mobile_clinical_full(uuid,uuid,uuid,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_full_context(uuid,text,uuid),
 public.prepare_mobile_clinical_full(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb),
 public.get_mobile_clinical_full_receipt(uuid,uuid,uuid),
 public.confirm_mobile_clinical_full(uuid,uuid,uuid,jsonb,jsonb,jsonb) TO service_role;
COMMIT;

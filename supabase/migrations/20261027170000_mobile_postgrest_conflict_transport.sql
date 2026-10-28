-- PostgREST14 retries custom40001 forever. Preserve SQL semantics inside the
-- backend, but encode an outer HTTP conflict with the official PGRST transport.
-- No public RPC/signature/owner/ACL is added, renamed or removed.

DO $guard$
DECLARE expected jsonb; actual text;
BEGIN
  FOR expected IN SELECT value FROM jsonb_array_elements($pins$[{"signature":"public.accept_mobile_reevaluation_photo_consent(uuid,uuid,bigint,uuid,text,text,text,text,uuid)","body_md5":"a5b07fe6db1258432b2a57a7451ca386"},{"signature":"public.admit_mobile_signup_health(uuid,jsonb)","body_md5":"6305bda9ab8dc9ad58e54427fabfda27"},{"signature":"public.apply_mobile_clinical_daily(uuid,uuid,text,jsonb)","body_md5":"88a4bf8201d3ce9c57276db77abcd76a"},{"signature":"public.apply_mobile_clinical_day_close(uuid,uuid,date,date,text,text,jsonb)","body_md5":"00fd79ae6ce2f19c24b8caa4980fcbe1"},{"signature":"public.authorize_mobile_reevaluation_photo_provider(uuid,uuid,uuid,uuid)","body_md5":"3093a22b7902d9a1292cb855f7537847"},{"signature":"public.capture_mobile_clinical_day_close(uuid,date,date,text)","body_md5":"fbebdcb0d796b6076f9f79517c94416e"},{"signature":"public.claim_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid)","body_md5":"453ca20b7348fc593c4c2e050be73773"},{"signature":"public.commit_mobile_reevaluation_photo_disposition_page(uuid,uuid,bigint,bigint,uuid,uuid[])","body_md5":"61ec5b9ba82b3a8d390f411584092db6"},{"signature":"public.complete_mobile_reevaluation_photo_processing(uuid,uuid,uuid,uuid,jsonb)","body_md5":"4a64c38f10d3d6651ae0da3bdcb3dcb5"},{"signature":"public.complete_mobile_reevaluation_photo_upload(uuid,uuid,uuid,bigint,bigint,text,text)","body_md5":"38193dd557dfc8bd878505b306609207"},{"signature":"public.confirm_mobile_clinical_first_phase(uuid,uuid,uuid,jsonb,jsonb)","body_md5":"a968d93e62568f95a0c13bbf23e9bcc0"},{"signature":"public.confirm_mobile_clinical_full(uuid,uuid,uuid,jsonb,jsonb,jsonb)","body_md5":"3fb5491d376937af77a859dd1260bdbf"},{"signature":"public.confirm_mobile_clinical_full_command(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb)","body_md5":"1840206d7aec0e8ce634ad2d50f405cf"},{"signature":"public.create_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb,text,jsonb,jsonb,jsonb)","body_md5":"65999b620f5b21e6463669ea129d6099"},{"signature":"public.create_mobile_reevaluation_photo_asset(uuid,uuid,bigint,uuid,text,text,bigint,uuid)","body_md5":"a0d4b9f6a5d531080c219da2577ef728"},{"signature":"public.declare_mobile_health_risk(uuid,uuid,text[])","body_md5":"91c3be7f4cbd0ad59efdddd0ec0ef7dc"},{"signature":"public.discard_mobile_reevaluation_photos(uuid,uuid,uuid,bigint)","body_md5":"e1394fe9b43400bba299d56a27d60fef"},{"signature":"public.get_mobile_clinical_daily_context(uuid)","body_md5":"b14c33496d302f95d1a8557f80118e17"},{"signature":"public.get_mobile_clinical_first_phase_context(uuid)","body_md5":"58a1df6913e5c6c91b381e5b16bde000"},{"signature":"public.get_mobile_clinical_first_phase_receipt(uuid,uuid,uuid)","body_md5":"f9192b5149c33d497e4a295741cf13b8"},{"signature":"public.get_mobile_clinical_flow_period(uuid,text,date,date)","body_md5":"fca087270f543af830cd3f9af9cf0c3e"},{"signature":"public.get_mobile_clinical_full_command(uuid,uuid,uuid)","body_md5":"ad938bcf805741583b3c471831ee72f6"},{"signature":"public.get_mobile_clinical_full_command_receipt(uuid,uuid,uuid)","body_md5":"b436339753a3a7a777970e088cdacaaf"},{"signature":"public.get_mobile_clinical_full_context(uuid,text,uuid)","body_md5":"0b54700a2958e931a607b023d9cc32c7"},{"signature":"public.get_mobile_clinical_full_receipt(uuid,uuid,uuid)","body_md5":"545a21cd30144e8db63bb05295afbf8c"},{"signature":"public.get_mobile_current_clinical_state(uuid,text,jsonb,jsonb)","body_md5":"94567ec596aa234dc33f6042117b2ba4"},{"signature":"public.get_mobile_flow_plan_context(uuid)","body_md5":"542c03050ad44448275f5a6694e06ebc"},{"signature":"public.get_mobile_reevaluation_photo_asset(uuid,uuid,uuid)","body_md5":"2adc2700fa4e6d82c977ac70b783be6d"},{"signature":"public.get_mobile_reevaluation_photo_consent(uuid,uuid)","body_md5":"f36c99ca7d3b2e52249f2f2d9315f274"},{"signature":"public.get_mobile_reevaluation_photo_disposition_page(uuid,uuid,bigint,bigint,uuid)","body_md5":"6dca0ac5bb4447b326af148f8a26e4cc"},{"signature":"public.get_mobile_reevaluation_photo_snapshot(uuid,uuid)","body_md5":"4713ab5ec917df71add0b4f10e23ddd3"},{"signature":"public.get_mobile_reevaluation_photo_upload_completion(uuid,uuid,uuid)","body_md5":"4a042d69e31207ee8369841edbe8004b"},{"signature":"public.lookup_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb)","body_md5":"9f6d4685461b70bbd57285cbf2cf26b7"},{"signature":"public.prepare_mobile_clinical_first_phase(uuid,uuid,text,jsonb,jsonb)","body_md5":"03d9af991323f3448430cd5ca7be983b"},{"signature":"public.prepare_mobile_clinical_full(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb)","body_md5":"442be3b3cd4256abf0bc452dd41e80ca"},{"signature":"public.prepare_mobile_clinical_full_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb)","body_md5":"a7d01ddd5a3e0e64fbc6f610dfbff8f7"},{"signature":"public.prepare_mobile_clinical_full_presented_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,jsonb)","body_md5":"6db6d2a7d3f25adbfa307b7aed47d92f"},{"signature":"public.prepare_mobile_reevaluation_photo_disposition(uuid,uuid,uuid)","body_md5":"d2db68b05cb43870d2a1b4f58c088c43"},{"signature":"public.prepare_mobile_reevaluation_photo_upload(uuid,uuid,uuid,uuid)","body_md5":"bdfa7b95701ec212ba2c61daf3618adf"},{"signature":"public.record_weight_atomic(uuid,numeric,text,timestamp with time zone,text)","body_md5":"45b79f2476f4e54eb655e92f7c2e6f11"},{"signature":"public.register_mobile_reevaluation_photo_upload_ticket(uuid,uuid,uuid,uuid,timestamp with time zone)","body_md5":"7e62f325ba0ba68d28f2add7812b2ca0"},{"signature":"public.start_mobile_clinical_full(uuid,uuid,text)","body_md5":"e781ceebec005a374253cdec4ab0d4ef"},{"signature":"public.start_mobile_reevaluation_cycle(uuid,uuid)","body_md5":"22888b07fe953521a2b86a901abc0cad"}]$pins$::jsonb) LOOP
    SELECT md5(prosrc) INTO actual FROM pg_proc WHERE oid=to_regprocedure(expected->>'signature');
    IF actual IS DISTINCT FROM expected->>'body_md5' THEN
      RAISE EXCEPTION 'mobile_rpc_transport_source_changed' USING ERRCODE='55000';
    END IF;
  END LOOP;
END $guard$;

CREATE OR REPLACE FUNCTION public.accept_mobile_reevaluation_photo_consent(p_user_id uuid, p_cycle_id uuid, p_expected_revision bigint, p_document_id uuid, p_document_key text, p_version text, p_locale text, p_body_hash text, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.accept_mobile_reevaluation_photo_consent_at(p_user_id,p_cycle_id,p_expected_revision,
    p_document_id,p_document_key,p_version,p_locale,p_body_hash,p_idempotency_key,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/accept_mobile_reevaluation_photo_consent'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admit_mobile_signup_health(p_user_id uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_signup_health_owner' USING ERRCODE='22023'; END IF;
 RETURN private.admit_mobile_signup_health(p_user_id,p_command);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/admit_mobile_signup_health'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.apply_mobile_clinical_daily(p_user_id uuid, p_operation_key uuid, p_context_hash text, p_calculation jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_daily_owner' USING ERRCODE='22023'; END IF;
 -- Delegate directly: receipt replay must precede recapture in the authority.
 RETURN jsonb_build_object('user_id',p_user_id,'operation_key',p_operation_key,'result',
  private.apply_mobile_clinical_daily_at(p_user_id,p_operation_key,p_context_hash,p_calculation,NULL));
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/apply_mobile_clinical_daily'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.apply_mobile_clinical_day_close(p_user_id uuid, p_operation_key uuid, p_from date, p_close_date date, p_expected_timezone text, p_context_hash text, p_effect jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN PERFORM private.assert_trusted_backend();
 RETURN private.apply_mobile_clinical_day_close_at(p_user_id,p_operation_key,p_from,p_close_date,p_expected_timezone,p_context_hash,p_effect,NULL); END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/apply_mobile_clinical_day_close'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.authorize_mobile_reevaluation_photo_provider(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.authorize_mobile_reevaluation_photo_provider_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/authorize_mobile_reevaluation_photo_provider'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.capture_mobile_clinical_day_close(p_user_id uuid, p_from date, p_close_date date, p_expected_timezone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_clinical_day_close_at(p_user_id,p_from,p_close_date,p_expected_timezone,NULL); END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/capture_mobile_clinical_day_close'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_mobile_reevaluation_photo_processing(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.claim_mobile_reevaluation_photo_processing_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/claim_mobile_reevaluation_photo_processing'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.commit_mobile_reevaluation_photo_disposition_page(p_user_id uuid, p_disposition_id uuid, p_expected_sweep bigint, p_expected_capability_revision bigint, p_expected_after uuid, p_asset_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.commit_mobile_reevaluation_photo_disposition_page_at(p_user_id,p_disposition_id,p_expected_sweep,p_expected_capability_revision,p_expected_after,p_asset_ids,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/commit_mobile_reevaluation_photo_disposition_page'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_mobile_reevaluation_photo_processing(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid, p_request_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.complete_mobile_reevaluation_photo_processing_at(p_user_id,p_cycle_id,p_asset_id,p_request_id,p_result,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/complete_mobile_reevaluation_photo_processing'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_mobile_reevaluation_photo_upload(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid, p_expected_source_revision bigint, p_actual_size_bytes bigint, p_content_type text, p_etag text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.complete_mobile_reevaluation_photo_upload_at(p_user_id,p_cycle_id,p_asset_id,
    p_expected_source_revision,p_actual_size_bytes,p_content_type,p_etag,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/complete_mobile_reevaluation_photo_upload'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_mobile_clinical_first_phase(p_user_id uuid, p_preview_id uuid, p_operation_key uuid, p_selection jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN PERFORM private.assert_trusted_backend();RETURN private.confirm_mobile_clinical_first_phase_at(p_user_id,p_preview_id,p_operation_key,p_selection,p_proposal,NULL);END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/confirm_mobile_clinical_first_phase'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_mobile_clinical_full(p_user_id uuid, p_preview_id uuid, p_operation_key uuid, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_full_owner' USING ERRCODE='22023'; END IF;
 -- Replay and original-key conflicts are decided by the atomic authority
 -- before any current capture. Never pre-capture here.
 RETURN jsonb_build_object('user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,'result',
  private.confirm_mobile_clinical_preview_at(p_user_id,p_preview_id,p_operation_key,p_form,p_intent,p_proposal,NULL));
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/confirm_mobile_clinical_full'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_mobile_clinical_full_command(p_user_id uuid, p_preview_id uuid, p_operation_key uuid, p_command jsonb, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;packet jsonb;result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_preview_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_confirmation' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'clinical_full_command_not_found' USING ERRCODE='P0002'; END IF;
 SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 IF NOT FOUND OR c.command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,p_command,c.normalization_context)
  OR c.prepared_package IS DISTINCT FROM jsonb_build_object('form',p_form,'intent',p_intent,'proposal',p_proposal) THEN
  RAISE EXCEPTION 'clinical_full_command_conflict' USING ERRCODE='40001'; END IF;
 packet:=private.mobile_clinical_full_command_wire(p,c);
 -- The original atomic writer resolves original/alias receipt before capturing
 -- current facts. This wrapper adds command identity without changing that order.
 result:=private.confirm_mobile_clinical_preview_at(p_user_id,p_preview_id,p_operation_key,p_form,p_intent,p_proposal,NULL);
 RETURN jsonb_build_object('user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,'result',result);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/confirm_mobile_clinical_full_command'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_mobile_flow_plan_draft(p_user_id uuid, p_domain text, p_request_key text, p_source_message_id uuid, p_expected jsonb, p_status text, p_payload jsonb, p_uncertain_fields jsonb, p_origin_detail jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE actual jsonb;existing jsonb;result jsonb;draft public.plan_drafts%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 existing:=public.lookup_mobile_flow_plan_draft(p_user_id,p_domain,p_request_key,p_source_message_id,p_expected);
 IF existing IS NOT NULL THEN RETURN existing||jsonb_build_object('inserted',false);END IF;
 -- lookup holds the owner/profile/config/day/turn and advisory locks until
 -- this same transaction commits; no revalidation-to-INSERT race remains.
 actual:=p_expected;
 IF p_status IS NULL OR p_status NOT IN('needs_completion','ready_for_review')
  OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'invalid_mobile_flow_draft_payload' USING ERRCODE='22023';END IF;
 IF p_domain='nutrition' AND (jsonb_typeof(p_payload->'meta_kcal') IS DISTINCT FROM 'number'
  OR jsonb_typeof(p_payload->'meta_protein_g') IS DISTINCT FROM 'number'
  OR p_payload->'meta_kcal' IS DISTINCT FROM actual#>'{day,calories_target}'
  OR p_payload->'meta_protein_g' IS DISTINCT FROM actual#>'{day,protein_target}') THEN
  RAISE EXCEPTION 'mobile_flow_draft_targets_changed' USING ERRCODE='23514';END IF;
 result:=public.create_plan_draft_atomic(p_user_id,p_domain,'flow_generated',p_status,p_payload,NULL,
  p_uncertain_fields,'[]'::jsonb,NULL,p_source_message_id,p_origin_detail,p_request_key);
 IF result->'inserted' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'mobile_flow_draft_unproven_replay' USING ERRCODE='40001';END IF;
 SELECT * INTO STRICT draft FROM public.plan_drafts WHERE user_id=p_user_id AND id=(result->>'id')::uuid;
 INSERT INTO private.mobile_flow_plan_draft_origins(draft_id,user_id,request_key,source_message_id,binding)
 VALUES(draft.id,p_user_id,p_request_key,p_source_message_id,private.mobile_flow_plan_context_binding(actual));
 RETURN result||jsonb_build_object('payload',draft.payload);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/create_mobile_flow_plan_draft'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_mobile_reevaluation_photo_asset(p_user_id uuid, p_cycle_id uuid, p_expected_revision bigint, p_acceptance_id uuid, p_pose text, p_mime_type text, p_size_bytes bigint, p_request_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.create_mobile_reevaluation_photo_asset_at(p_user_id,p_cycle_id,p_expected_revision,
    p_acceptance_id,p_pose,p_mime_type,p_size_bytes,p_request_key,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/create_mobile_reevaluation_photo_asset'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.declare_mobile_health_risk(p_user_id uuid, p_operation_key uuid, p_items text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 RETURN private.declare_mobile_health_risk_at(p_user_id,p_operation_key,p_items,clock_timestamp());
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/declare_mobile_health_risk'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.discard_mobile_reevaluation_photos(p_user_id uuid, p_cycle_id uuid, p_acceptance_id uuid, p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;ctx jsonb;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 IF p_expected_revision IS NULL OR p_expected_revision<1 THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup' USING ERRCODE='22023'; END IF;
 SELECT x.* INTO h FROM private.mobile_reevaluation_photo_dispositions x WHERE x.user_id=p_user_id AND x.cycle_id=p_cycle_id AND x.acceptance_id=p_acceptance_id;
 IF FOUND THEN
  IF h.reason<>'discarded' OR h.request_revision<>p_expected_revision THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_changed' USING ERRCODE='40001'; END IF;
  RETURN private.mobile_reevaluation_photo_disposition_wire(h);
 END IF;
 ctx:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,NULL);
 IF ctx->>'cycle_revision' IS DISTINCT FROM p_expected_revision::text OR ctx#>>'{current_acceptance,acceptance_id}' IS DISTINCT FROM p_acceptance_id::text
  OR private.mobile_reevaluation_photo_consent_wire(ctx)->>'availability' IS DISTINCT FROM 'available' THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_changed' USING ERRCODE='40001'; END IF;
 RETURN private.seal_mobile_reevaluation_photo_disposition_at(p_user_id,p_cycle_id,p_acceptance_id,'discarded',NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/discard_mobile_reevaluation_photos'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_daily_context(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_daily_owner' USING ERRCODE='22023'; END IF;
 RETURN private.capture_mobile_clinical_context_at(p_user_id,'APPLICATION',NULL,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_daily_context'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_first_phase_context(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_clinical_first_phase_at(p_user_id,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_first_phase_context'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_first_phase_receipt(p_user_id uuid, p_preview_id uuid, p_operation_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE k private.mobile_clinical_first_phase_keys%ROWTYPE;r private.mobile_clinical_first_phase_confirmations%ROWTYPE;
 p private.mobile_clinical_first_phase_previews%ROWTYPE;matched boolean:=false;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_preview_id IS NULL OR p_operation_key IS NULL THEN RAISE EXCEPTION 'invalid_first_phase_receipt_lookup' USING ERRCODE='22023';END IF;
 SELECT * INTO k FROM private.mobile_clinical_first_phase_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF k.first_phase_id<>p_preview_id THEN RAISE EXCEPTION 'first_phase_key_conflict' USING ERRCODE='40001';END IF;
  matched:=true;
 END IF;
 SELECT * INTO r FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id AND first_phase_id=p_preview_id;
 IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO STRICT p FROM private.mobile_clinical_first_phase_previews WHERE user_id=p_user_id AND preview_id=p_preview_id;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,
  'operation_matched',matched,'prepared',private.mobile_clinical_first_phase_prepared(p),'result',r.result);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_first_phase_receipt'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_flow_period(p_user_id uuid, p_period text, p_expected_from date, p_expected_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.get_mobile_clinical_flow_period_at(p_user_id,p_period,p_expected_from,p_expected_to,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_flow_period'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_full_command(p_user_id uuid, p_preview_id uuid, p_prepare_operation_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR (p_preview_id IS NULL)=(p_prepare_operation_key IS NULL) THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_lookup' USING ERRCODE='22023'; END IF;
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id
  AND ((p_preview_id IS NOT NULL AND x.preview_id=p_preview_id)
    OR (p_prepare_operation_key IS NOT NULL AND x.operation_key=p_prepare_operation_key));
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'clinical_full_command_unavailable' USING ERRCODE='40001'; END IF;
 RETURN private.mobile_clinical_full_command_wire(p,c);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_full_command'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_full_command_receipt(p_user_id uuid, p_preview_id uuid, p_operation_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE receipt jsonb;p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 receipt:=public.get_mobile_clinical_full_receipt(p_user_id,p_preview_id,p_operation_key);
 IF receipt IS NULL THEN RETURN NULL; END IF;
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'clinical_full_command_unavailable' USING ERRCODE='40001'; END IF;
 IF c.prepared_package IS DISTINCT FROM jsonb_build_object('form',receipt->'form','intent',receipt->'intent','proposal',receipt->'proposal') THEN
  RAISE EXCEPTION 'clinical_full_command_corrupt' USING ERRCODE='XX001'; END IF;
 RETURN receipt||jsonb_build_object('prepared',private.mobile_clinical_full_command_wire(p,c));
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_full_command_receipt'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_full_context(p_user_id uuid, p_kind text, p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','SAFETY','ROUTINE_REVIEW') THEN
  RAISE EXCEPTION 'invalid_clinical_full_scope' USING ERRCODE='22023'; END IF;
 RETURN private.capture_mobile_clinical_context_at(p_user_id,p_kind,p_cycle_id,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_full_context'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_full_receipt(p_user_id uuid, p_preview_id uuid, p_operation_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
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
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_full_receipt'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_current_clinical_state(p_user_id uuid, p_mode text, p_body jsonb, p_expected jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_current_clinical_state_at(p_user_id,p_mode,p_body,p_expected,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_current_clinical_state'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_flow_plan_context(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_flow_plan_context_at(p_user_id,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_flow_plan_context'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_reevaluation_photo_asset(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE context jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_asset_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_photo_asset' USING ERRCODE='22023'; END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,NULL::timestamptz);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001';
  END IF;
  RETURN private.mobile_reevaluation_photo_asset_wire(context,p_asset_id);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_reevaluation_photo_asset'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_reevaluation_photo_consent(p_user_id uuid, p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.mobile_reevaluation_photo_consent_state_at(p_user_id,p_cycle_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_reevaluation_photo_consent'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_reevaluation_photo_disposition_page(p_user_id uuid, p_disposition_id uuid, p_expected_sweep bigint, p_expected_capability_revision bigint, p_expected_after uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE h private.mobile_reevaluation_photo_dispositions%ROWTYPE;items jsonb;last_id uuid;more boolean;
BEGIN
 h:=private.mobile_reevaluation_photo_disposition_page_header(p_user_id,p_disposition_id,p_expected_sweep,p_expected_capability_revision,p_expected_after);
 SELECT jsonb_agg(jsonb_build_object('asset_id',q.asset_id,'bucket_id',q.bucket_id,'object_path',q.object_path) ORDER BY q.asset_id),max(q.asset_id::text)::uuid INTO items,last_id
  FROM(SELECT a.* FROM private.mobile_reevaluation_photo_disposition_assets a WHERE a.disposition_id=p_disposition_id AND(p_expected_after IS NULL OR a.asset_id>p_expected_after) ORDER BY a.asset_id LIMIT 200) q;
 IF items IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_cleanup_page_missing' USING ERRCODE='40001'; END IF;
 SELECT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_disposition_assets WHERE disposition_id=p_disposition_id AND asset_id>last_id) INTO more;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'signup_generation',h.signup_generation,'cycle_id',h.cycle_id,'acceptance_id',h.acceptance_id,'disposition_id',p_disposition_id,
  'sweep_no',p_expected_sweep::text,'capability_revision',p_expected_capability_revision::text,'cursor',p_expected_after,'items',items,'has_more',more);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_reevaluation_photo_disposition_page'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_reevaluation_photo_snapshot(p_user_id uuid, p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.get_mobile_reevaluation_photo_snapshot_at(p_user_id,p_cycle_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_reevaluation_photo_snapshot'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_reevaluation_photo_upload_completion(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.get_mobile_reevaluation_photo_upload_completion_at(p_user_id,p_cycle_id,p_asset_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_reevaluation_photo_upload_completion'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.lookup_mobile_flow_plan_draft(p_user_id uuid, p_domain text, p_request_key text, p_source_message_id uuid, p_expected jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE actual jsonb;draft public.plan_drafts%ROWTYPE;origin private.mobile_flow_plan_draft_origins%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 -- Legacy writers acquire this advisory lock before their FK locks. Never
 -- wait for it while holding the new owner lock: refuse busy to avoid a cycle.
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':plan-drafts',0)) THEN
  RAISE EXCEPTION 'mobile_flow_draft_busy' USING ERRCODE='55P03';END IF;
 actual:=private.assert_mobile_flow_plan_context(p_user_id,p_domain,p_expected);
 PERFORM private.assert_mobile_flow_draft_turn(p_user_id,p_domain,p_request_key,p_source_message_id);
 SELECT * INTO draft FROM public.plan_drafts WHERE user_id=p_user_id AND request_key=p_request_key FOR SHARE NOWAIT;
 IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO origin FROM private.mobile_flow_plan_draft_origins WHERE user_id=p_user_id AND draft_id=draft.id;
 IF NOT FOUND OR draft.domain<>p_domain OR draft.origin<>'flow_generated'
  OR draft.source_message_id IS DISTINCT FROM p_source_message_id OR origin.source_message_id<>p_source_message_id
  OR origin.binding<>private.mobile_flow_plan_context_binding(actual) THEN
  RAISE EXCEPTION 'mobile_current_clinical_changed' USING ERRCODE='40001';END IF;
 -- Current edited payload/status, not a fabricated immutable creation ACK.
 RETURN private.plan_draft_dto(draft)||jsonb_build_object('payload',draft.payload);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/lookup_mobile_flow_plan_draft'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_clinical_first_phase(p_user_id uuid, p_operation_key uuid, p_context_hash text, p_selection jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN PERFORM private.assert_trusted_backend();RETURN private.prepare_mobile_clinical_first_phase_at(p_user_id,p_operation_key,p_context_hash,p_selection,p_proposal,NULL);END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_clinical_first_phase'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_clinical_full(p_user_id uuid, p_kind text, p_cycle_id uuid, p_operation_key uuid, p_context_hash text, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_clinical_full_owner' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('user_id',p_user_id,'operation_key',p_operation_key,'preview',
  private.prepare_mobile_clinical_preview_at(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_form,p_intent,p_proposal,NULL));
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_clinical_full'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_clinical_full_command(p_user_id uuid, p_kind text, p_cycle_id uuid, p_operation_key uuid, p_context_hash text, p_command jsonb, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
 profile public.user_profiles%ROWTYPE;wire jsonb;normalization jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL OR p_kind IS NULL
  OR p_kind NOT IN('REGULAR','EARLY_FULL','ROUTINE_REVIEW','SAFETY') THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_scope' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.operation_key=p_operation_key;
 IF FOUND THEN
  SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
  IF NOT FOUND OR p.review_kind IS DISTINCT FROM p_kind OR p.cycle_id IS DISTINCT FROM p_cycle_id
   OR c.command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,p_command,c.normalization_context) THEN
   RAISE EXCEPTION 'clinical_full_command_conflict' USING ERRCODE='40001'; END IF;
  -- Identity is the normalized client command, not a recalculated effect. Never
  -- extend expiry or consult a changed profile on this acknowledgement branch.
  RETURN private.mobile_clinical_full_command_wire(p,c);
 END IF;
 IF NOT private.mobile_clinical_full_command_valid(p_kind,p_command,p_form,p_intent,p_proposal) THEN
  RAISE EXCEPTION 'invalid_clinical_full_command' USING ERRCODE='22023'; END IF;
 wire:=private.prepare_mobile_clinical_preview_at(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_form,p_intent,p_proposal,NULL);
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=(wire->>'preview_id')::uuid;
 -- The delegated capture holds this profile and the full calculation context.
 -- Retain only the two original n21 normalization inputs, never a refused value.
 SELECT x.* INTO STRICT profile FROM public.user_profiles x WHERE x.user_id=p_user_id;
 IF NOT coalesce(private.mobile_clinical_preference_valid(p_form->'preference',profile.sex::text,profile.height_cm),false) THEN
  RAISE EXCEPTION 'invalid_clinical_full_normalized_preference' USING ERRCODE='22023'; END IF;
 normalization:=jsonb_build_object('sex',profile.sex,'heightCm',profile.height_cm);
 INSERT INTO private.mobile_clinical_full_commands(user_id,preview_id,command_version,command,prepared_package,normalization_context,command_hash)
 VALUES(p_user_id,p.preview_id,1,p_command,jsonb_build_object('form',p_form,'intent',p_intent,'proposal',p_proposal),normalization,
  private.mobile_clinical_full_command_hash(p,p_command,normalization)) RETURNING * INTO c;
 RETURN private.mobile_clinical_full_command_wire(p,c);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_clinical_full_command'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_clinical_full_presented_command(p_user_id uuid, p_kind text, p_cycle_id uuid, p_operation_key uuid, p_context_hash text, p_command jsonb, p_form jsonb, p_intent jsonb, p_proposal jsonb, p_presentation jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE existed boolean;wire jsonb;p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_full_presentation_scope' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 existed:=EXISTS(SELECT 1 FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.operation_key=p_operation_key);
 -- The old authority still validates the original normalized command before
 -- any current capture. Never add a guessed/backfilled policy to an old ACK.
 wire:=public.prepare_mobile_clinical_full_command(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_command,p_form,p_intent,p_proposal);
 IF existed THEN RETURN wire; END IF;
 IF NOT private.mobile_clinical_full_presentation_valid(p_presentation) THEN
  RAISE EXCEPTION 'invalid_clinical_full_presentation' USING ERRCODE='22023'; END IF;
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x
  WHERE x.user_id=p_user_id AND x.preview_id=(wire#>>'{preview,preview_id}')::uuid;
 SELECT x.* INTO STRICT c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
 INSERT INTO private.mobile_clinical_full_presentations(user_id,preview_id,presentation,binding_hash)
 VALUES(p_user_id,p.preview_id,p_presentation,private.mobile_clinical_full_presentation_hash(p,c,p_presentation));
 RETURN private.mobile_clinical_full_command_wire(p,c);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_clinical_full_presented_command'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_reevaluation_photo_disposition(p_user_id uuid, p_cycle_id uuid, p_acceptance_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.prepare_mobile_reevaluation_photo_disposition_at(p_user_id,p_cycle_id,p_acceptance_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_reevaluation_photo_disposition'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_reevaluation_photo_upload(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid, p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.prepare_mobile_reevaluation_photo_upload_at(p_user_id,p_cycle_id,p_asset_id,p_ticket_id,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_reevaluation_photo_upload'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_weight_atomic(p_user_id uuid, p_value numeric, p_unit text, p_measured_at timestamp with time zone, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.record_mobile_weight_at(p_user_id,p_value,p_unit,p_measured_at,p_idempotency_key,NULL));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/record_weight_atomic'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_mobile_reevaluation_photo_upload_ticket(p_user_id uuid, p_cycle_id uuid, p_asset_id uuid, p_ticket_id uuid, p_provider_expires_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.register_mobile_reevaluation_photo_upload_ticket_at(p_user_id,p_cycle_id,p_asset_id,p_ticket_id,p_provider_expires_at,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/register_mobile_reevaluation_photo_upload_ticket'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_mobile_clinical_full(p_user_id uuid, p_operation_key uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL
  OR (p_reason IS NOT NULL AND p_reason NOT IN('gain_review_notice','not_well_with_plan')) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_start' USING ERRCODE='22023'; END IF;
 RETURN private.start_mobile_clinical_full_at(p_user_id,p_operation_key,
  CASE WHEN p_reason IS NULL THEN 'REGULAR' ELSE 'EARLY_FULL' END,p_reason,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/start_mobile_clinical_full'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_mobile_reevaluation_cycle(p_user_id uuid, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
RETURN (SELECT private.start_mobile_reevaluation_cycle_at(p_user_id,p_idempotency_key,NULL::timestamptz));
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/start_mobile_reevaluation_cycle'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

NOTIFY pgrst,'reload schema';

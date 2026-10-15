-- Dormant Flow inbound foundation. No caller, flag or lifecycle activation.
BEGIN;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'flow_inbound_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('private.workout_strength_request_admissions') IS NULL
    OR pg_catalog.to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('public.messages') IS NULL
    OR pg_catalog.to_regclass('public.uniq_messages_provider_message_id_all') IS NULL
    OR pg_catalog.to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
    RAISE EXCEPTION 'flow_inbound_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid='private.workout_strength_request_admissions'::regclass
      AND attname IN ('flow_inbound_id','flow_inbound_refusal') AND NOT attisdropped)
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
      WHERE conrelid='private.workout_strength_request_admissions'::regclass
        AND conname='workout_strength_flow_inbound_receipt_check')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='access_workout_strength_flow_inbound') THEN
    RAISE EXCEPTION 'flow_inbound_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

ALTER TABLE private.workout_strength_request_admissions
  ADD COLUMN flow_inbound_id uuid,
  ADD COLUMN flow_inbound_refusal text COLLATE "C",
  ADD CONSTRAINT workout_strength_flow_inbound_receipt_check CHECK ((flow_inbound_refusal IS NULL OR flow_inbound_refusal='unproved_inbound') AND (flow_inbound_id IS NULL OR flow_inbound_refusal IS NULL));

CREATE FUNCTION public.access_workout_strength_flow_inbound(
  p_user_id uuid,p_admission_id uuid,p_text text,p_mode text,
  p_request_id text,p_started_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $access$
DECLARE
  authority private.workout_strength_authority_epochs%ROWTYPE;
  admission private.workout_strength_request_admissions%ROWTYPE;
  inbound public.messages%ROWTYPE;
  scoped_id text;
  started_iso text;
  result_status text;
  payload jsonb;
  violated_schema text;
  violated_table text;
  violated_constraint text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_admission_id IS NULL OR p_text IS NULL
    OR pg_catalog.char_length(p_text) NOT BETWEEN 1 AND 4000
    OR p_mode IS NULL OR (p_mode COLLATE "C") NOT IN ('probe','persist') THEN
    RAISE EXCEPTION 'invalid_flow_inbound_input' USING ERRCODE='22023';
  END IF;
  IF p_mode='probe' THEN
    IF p_request_id IS NOT NULL OR p_started_at IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_flow_inbound_input' USING ERRCODE='22023';
    END IF;
  ELSE
    IF p_request_id IS NULL
      OR NOT ((p_request_id COLLATE "C") ~ '^[A-Za-z0-9._:-]{8,128}$')
      OR p_started_at IS NULL OR NOT pg_catalog.isfinite(p_started_at)
      OR p_started_at < '0001-01-01T00:00:00Z'::timestamptz
      OR p_started_at >= '10000-01-01T00:00:00Z'::timestamptz
      OR p_started_at IS DISTINCT FROM pg_catalog.date_trunc('milliseconds',p_started_at) THEN
      RAISE EXCEPTION 'invalid_flow_inbound_input' USING ERRCODE='22023';
    END IF;
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'flow_inbound_requires_read_committed' USING ERRCODE='22023';
  END IF;

  -- Match reset and lock users before the IN trigger updates last_active_at.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  PERFORM u.id FROM public.users u
    WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'flow_inbound_patient_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e
    WHERE e.user_id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','invalid_admission');
  END IF;
  SELECT a.* INTO admission FROM private.workout_strength_request_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=p_admission_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','invalid_admission');
  END IF;
  IF admission.epoch IS DISTINCT FROM authority.epoch THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_epoch');
  END IF;
  IF (admission.request_hash COLLATE "C") IS DISTINCT FROM
    (pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_text,'UTF8')),'hex') COLLATE "C") THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','request_content_conflict');
  END IF;
  IF admission.flow_inbound_refusal IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','unproved_inbound');
  END IF;
  scoped_id:='mobile_flow/'||p_user_id::text||'/'||admission.request_key;

  IF admission.flow_inbound_id IS NOT NULL THEN
    IF admission.original_inbound_id IS NOT NULL
      AND admission.original_inbound_id IS DISTINCT FROM admission.flow_inbound_id THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','inbound_mismatch');
    END IF;
    SELECT m.* INTO inbound FROM public.messages m
      WHERE m.id=admission.flow_inbound_id AND m.user_id=p_user_id
        AND m.direction='in' AND m.role='user' AND m.content_type='text'
        AND (m.provider COLLATE "C")='mobile_flow'
        AND (m.provider_message_id COLLATE "C")=(scoped_id COLLATE "C")
        AND m.content IS NOT NULL
        AND (pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(m.content,'UTF8')),'hex') COLLATE "C")=
          (admission.request_hash COLLATE "C")
      FOR SHARE;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','inbound_mismatch');
    END IF;
    result_status:=CASE WHEN p_mode='probe' THEN 'bound' ELSE 'reused' END;
  ELSE
    -- A pre-protocol row or old lifecycle pair cannot supply this receipt.
    PERFORM m.id FROM public.messages m
      WHERE (m.provider COLLATE "C")='mobile_flow'
        AND (m.provider_message_id COLLATE "C")=(scoped_id COLLATE "C") FOR SHARE;
    IF FOUND OR admission.original_inbound_id IS NOT NULL THEN
      UPDATE private.workout_strength_request_admissions
        SET flow_inbound_refusal='unproved_inbound'
        WHERE user_id=p_user_id AND admission_id=p_admission_id
          AND flow_inbound_id IS NULL AND flow_inbound_refusal IS NULL;
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','unproved_inbound');
    END IF;
    IF p_mode='probe' THEN
      RETURN pg_catalog.jsonb_build_object('status','unbound');
    END IF;
    started_iso:=pg_catalog.to_char(p_started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    BEGIN
      INSERT INTO public.messages(user_id,direction,role,content_type,content,
        provider,provider_message_id,delivery_status,created_at,raw_payload)
      VALUES(p_user_id,'in','user','text',p_text,'mobile_flow',scoped_id,
        'processing',p_started_at,pg_catalog.jsonb_build_object(
          'request_id',p_request_id,'conversation_id','flow',
          'attempt_started_at',started_iso,'provider_started_at',NULL,
          'retry_started_at','[]'::jsonb)) RETURNING * INTO inbound;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS violated_schema=SCHEMA_NAME,
        violated_table=TABLE_NAME,violated_constraint=CONSTRAINT_NAME;
      IF violated_schema IS DISTINCT FROM 'public' OR violated_table IS DISTINCT FROM 'messages'
        OR violated_constraint NOT IN ('uniq_messages_provider_message_id_all','uniq_messages_inbound_provider_id') THEN
        RAISE;
      END IF;
      UPDATE private.workout_strength_request_admissions
        SET flow_inbound_refusal='unproved_inbound'
        WHERE user_id=p_user_id AND admission_id=p_admission_id
          AND flow_inbound_id IS NULL AND flow_inbound_refusal IS NULL;
      RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','unproved_inbound');
    END;
    UPDATE private.workout_strength_request_admissions
      SET flow_inbound_id=inbound.id
      WHERE user_id=p_user_id AND admission_id=p_admission_id
        AND flow_inbound_id IS NULL AND flow_inbound_refusal IS NULL
      RETURNING * INTO STRICT admission;
    result_status:='inserted';
  END IF;

  -- Keep only the operational fields consumed by the existing row mapper.
  SELECT COALESCE(pg_catalog.jsonb_object_agg(e.key,e.value),'{}'::jsonb)
    INTO payload FROM pg_catalog.jsonb_each(CASE
      WHEN pg_catalog.jsonb_typeof(inbound.raw_payload)='object' THEN inbound.raw_payload
      ELSE '{}'::jsonb END) e
    WHERE e.key=ANY(ARRAY['request_id','conversation_id','attempt_started_at',
      'provider_started_at','retry_started_at','last_retry_at']);
  RETURN pg_catalog.jsonb_build_object('status',result_status,'inbound',
    pg_catalog.jsonb_build_object('id',inbound.id::text,'direction','in',
      'content',inbound.content,'delivery_status',inbound.delivery_status,
      'raw_payload',payload,'created_at',pg_catalog.to_char(inbound.created_at AT TIME ZONE 'UTC',
        CASE WHEN inbound.created_at=pg_catalog.date_trunc('milliseconds',inbound.created_at)
          THEN 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"' ELSE 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"' END)));
END;
$access$;
REVOKE ALL ON FUNCTION public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamptz)
  TO service_role;

-- Reject unknown inherited grants instead of changing unrelated default ACLs.
DO $privileges$
BEGIN
  IF EXISTS (
    WITH objects AS (
      SELECT p.oid,p.proowner AS owner_id,p.proacl AS acl FROM pg_catalog.pg_proc p
      WHERE p.oid='public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamptz)'::regprocedure
    ), actual AS (
      SELECT o.oid,a.grantor,a.grantee,a.privilege_type,a.is_grantable
      FROM objects o CROSS JOIN LATERAL
        pg_catalog.aclexplode(COALESCE(o.acl,pg_catalog.acldefault('f',o.owner_id))) a
    ), expected AS (
      SELECT o.oid,'postgres'::regrole::oid AS grantor,'postgres'::regrole::oid AS grantee,
        'EXECUTE'::text AS privilege_type,false AS is_grantable FROM objects o
      UNION ALL SELECT o.oid,'postgres'::regrole::oid,'service_role'::regrole::oid,'EXECUTE',false
        FROM objects o
    ), differences AS (
      (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected)
      UNION ALL (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
    ) SELECT 1 FROM objects WHERE owner_id<>'postgres'::regrole
    UNION ALL SELECT 1 FROM differences
  ) OR pg_catalog.has_function_privilege('anon','public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated','public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'flow_inbound_unexpected_acl' USING ERRCODE='42501';
  END IF;
END $privileges$;

COMMIT;

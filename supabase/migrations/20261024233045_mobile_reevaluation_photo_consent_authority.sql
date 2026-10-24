-- No real consent text or retention policy is published by this migration.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
  IF current_user<>'postgres' THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regprocedure('private.mobile_reevaluation_context_at(uuid,timestamptz)') IS NULL
    OR to_regclass('public.legal_documents') IS NULL THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
END $preflight$;

CREATE TABLE private.mobile_reevaluation_photo_policies (
  document_id uuid PRIMARY KEY,
  document_key text NOT NULL CHECK(document_key='body_photo_reevaluation_consent'),
  version text NOT NULL,
  locale text NOT NULL,
  body_hash text NOT NULL,
  idle_timeout_seconds integer NOT NULL CHECK(idle_timeout_seconds>0),
  enabled boolean NOT NULL DEFAULT false,
  FOREIGN KEY(document_id,document_key,version,locale,body_hash)
    REFERENCES public.legal_documents(id,document_key,version,locale,body_hash) ON DELETE RESTRICT,
  UNIQUE(document_id,document_key,version,locale,body_hash,idle_timeout_seconds)
);

CREATE TABLE private.mobile_reevaluation_photo_consents (
  acceptance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  signup_generation uuid NOT NULL,
  cycle_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_key text NOT NULL,
  version text NOT NULL,
  locale text NOT NULL,
  body_hash text NOT NULL,
  idle_timeout_seconds integer NOT NULL CHECK(idle_timeout_seconds>0),
  accepted_at timestamptz NOT NULL CHECK(isfinite(accepted_at)),
  last_activity_at timestamptz NOT NULL CHECK(isfinite(last_activity_at) AND last_activity_at>=accepted_at),
  revoked_at timestamptz,
  revoked_reason text,
  FOREIGN KEY(user_id,signup_generation,cycle_id)
    REFERENCES private.mobile_reevaluation_cycles(user_id,signup_generation,cycle_id) ON DELETE CASCADE,
  FOREIGN KEY(document_id,document_key,version,locale,body_hash,idle_timeout_seconds)
    REFERENCES private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds)
    ON DELETE RESTRICT,
  UNIQUE(user_id,signup_generation,cycle_id,acceptance_id),
  CHECK((revoked_at IS NULL)=(revoked_reason IS NULL)),
  CHECK(revoked_at IS NULL OR (isfinite(revoked_at) AND revoked_at>=last_activity_at)),
  CHECK(revoked_reason IS NULL OR revoked_reason IN('expired','consent_changed','discarded','completed','generation_changed'))
);
CREATE UNIQUE INDEX mobile_reevaluation_photo_one_live_consent
  ON private.mobile_reevaluation_photo_consents(user_id,cycle_id) WHERE revoked_at IS NULL;

CREATE TABLE private.mobile_reevaluation_photo_consent_keys (
  user_id uuid NOT NULL,
  idempotency_key uuid NOT NULL,
  signup_generation uuid NOT NULL,
  cycle_id uuid NOT NULL,
  acceptance_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0),
  PRIMARY KEY(user_id,idempotency_key),
  FOREIGN KEY(user_id,signup_generation,cycle_id,acceptance_id)
    REFERENCES private.mobile_reevaluation_photo_consents(user_id,signup_generation,cycle_id,acceptance_id)
    ON DELETE CASCADE
);
ALTER TABLE private.mobile_reevaluation_photo_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_reevaluation_photo_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_reevaluation_photo_consent_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_reevaluation_photo_policies,
  private.mobile_reevaluation_photo_consents,private.mobile_reevaluation_photo_consent_keys
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_reevaluation_photo_policy_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF (to_jsonb(NEW)-'enabled') IS DISTINCT FROM (to_jsonb(OLD)-'enabled') THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_policy_immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER mobile_reevaluation_photo_policy_immutable BEFORE UPDATE
  ON private.mobile_reevaluation_photo_policies FOR EACH ROW
  EXECUTE FUNCTION private.mobile_reevaluation_photo_policy_immutable();

CREATE FUNCTION private.mobile_reevaluation_photo_consent_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF (to_jsonb(NEW)-ARRAY['last_activity_at','revoked_at','revoked_reason'])
      IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['last_activity_at','revoked_at','revoked_reason'])
    OR NEW.last_activity_at<OLD.last_activity_at
    OR (OLD.revoked_at IS NOT NULL AND NEW IS DISTINCT FROM OLD)
    OR (NEW.last_activity_at>OLD.last_activity_at
      AND NEW.last_activity_at>=OLD.last_activity_at+make_interval(secs=>OLD.idle_timeout_seconds)) THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER mobile_reevaluation_photo_consent_immutable BEFORE UPDATE
  ON private.mobile_reevaluation_photo_consents FOR EACH ROW
  EXECUTE FUNCTION private.mobile_reevaluation_photo_consent_immutable();

CREATE FUNCTION private.mobile_reevaluation_photo_consent_key_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_key_immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER mobile_reevaluation_photo_consent_key_immutable BEFORE UPDATE
  ON private.mobile_reevaluation_photo_consent_keys FOR EACH ROW
  EXECUTE FUNCTION private.mobile_reevaluation_photo_consent_key_immutable();

-- All paths lock the owner first. This serializes against signup/reset and
-- captures the authoritative clock AFTER waiting; no client clock is exposed.
CREATE FUNCTION private.mobile_reevaluation_photo_context(
  p_user_id uuid,p_cycle_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; observed_at timestamptz; doc public.legal_documents%ROWTYPE;
  policy private.mobile_reevaluation_photo_policies%ROWTYPE;
  consent private.mobile_reevaluation_photo_consents%ROWTYPE;
  current_locale text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_cycle_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_input' USING ERRCODE='22023';
  END IF;
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  IF context->>'reason' IS NOT NULL OR context#>>'{cycle,id}' IS DISTINCT FROM p_cycle_id::text THEN
    RAISE EXCEPTION 'mobile_reevaluation_cycle_changed' USING ERRCODE='40001';
  END IF;
  SELECT u.locale INTO current_locale FROM public.users u WHERE u.id=p_user_id;
  -- Prevent a concurrent publication from slipping between current-document
  -- selection and acceptance. Policy activation follows the same table order.
  LOCK TABLE public.legal_documents IN SHARE MODE;
  LOCK TABLE private.mobile_reevaluation_photo_policies IN SHARE MODE;
  -- Either table lock may have waited on publication/configuration. Capture
  -- time again under all locks, so newly effective text is never skipped.
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  observed_at:=(context->>'observed_at')::timestamptz;
  SELECT d.* INTO doc FROM public.legal_documents d
    WHERE d.document_key='body_photo_reevaluation_consent' AND d.locale=current_locale
      AND d.required_from<=observed_at
    ORDER BY d.required_from DESC,d.created_at DESC,d.id DESC LIMIT 1;
  IF FOUND THEN
    IF NOT isfinite(doc.required_from) THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_document_corrupt' USING ERRCODE='XX001';
    END IF;
    SELECT p.* INTO policy FROM private.mobile_reevaluation_photo_policies p
      WHERE p.document_id=doc.id AND p.enabled;
  END IF;
  SELECT a.* INTO consent FROM private.mobile_reevaluation_photo_consents a
    WHERE a.user_id=p_user_id AND a.signup_generation=(context->>'signup_generation')::uuid
      AND a.cycle_id=p_cycle_id AND a.revoked_at IS NULL;
  IF FOUND AND (consent.accepted_at>observed_at OR consent.last_activity_at>observed_at) THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_corrupt' USING ERRCODE='XX001';
  END IF;
  RETURN jsonb_build_object('cycle_revision',context#>>'{cycle,revision}',
    'signup_generation',context->'signup_generation','observed_at',context->'observed_at',
    'document',CASE WHEN policy.document_id IS NULL THEN 'null'::jsonb
      ELSE to_jsonb(doc)||jsonb_build_object('idle_timeout_seconds',policy.idle_timeout_seconds) END,
    'current_acceptance',CASE WHEN consent.acceptance_id IS NULL THEN 'null'::jsonb ELSE to_jsonb(consent) END);
END $$;

CREATE FUNCTION private.mobile_reevaluation_photo_consent_wire(p_context jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE doc jsonb:=p_context->'document'; consent jsonb:=p_context->'current_acceptance';
  reason text; doc_wire jsonb:='null'; acceptance_wire jsonb:='null'; expires_at timestamptz;
BEGIN
  IF doc='null'::jsonb THEN reason:='policy_unavailable';
  ELSE
    doc_wire:=jsonb_build_object('id',doc->'id','document_key',doc->'document_key',
      'version',doc->'version','locale',doc->'locale','body',doc->'body','body_hash',doc->'body_hash',
      'required_from',to_char((doc->>'required_from')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'idle_timeout_seconds',doc->'idle_timeout_seconds');
    IF consent='null'::jsonb THEN reason:='consent_required';
    ELSIF consent->>'document_id' IS DISTINCT FROM doc->>'id'
      OR consent->>'document_key' IS DISTINCT FROM doc->>'document_key'
      OR consent->>'version' IS DISTINCT FROM doc->>'version'
      OR consent->>'locale' IS DISTINCT FROM doc->>'locale'
      OR consent->>'body_hash' IS DISTINCT FROM doc->>'body_hash'
      OR consent->'idle_timeout_seconds' IS DISTINCT FROM doc->'idle_timeout_seconds' THEN
      reason:='consent_changed';
    ELSE
      expires_at:=(consent->>'last_activity_at')::timestamptz
        +make_interval(secs=>(consent->>'idle_timeout_seconds')::integer);
      IF expires_at<=(p_context->>'observed_at')::timestamptz THEN reason:='consent_expired';
      ELSE
        acceptance_wire:=jsonb_build_object('acceptance_id',consent->'acceptance_id',
          'document_id',consent->'document_id','document_key',consent->'document_key',
          'version',consent->'version','locale',consent->'locale','body_hash',consent->'body_hash',
          'accepted_at',to_char((consent->>'accepted_at')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'idle_expires_at',to_char(expires_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
      END IF;
    END IF;
  END IF;
  RETURN jsonb_build_object('version',1,'cycle_revision',p_context->'cycle_revision',
    'availability',CASE WHEN reason IS NULL THEN 'available' ELSE 'unavailable' END,
    'unavailable_reason',reason,'document',doc_wire,'acceptance',acceptance_wire);
END $$;

CREATE FUNCTION private.mobile_reevaluation_photo_consent_state_at(
  p_user_id uuid,p_cycle_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT private.mobile_reevaluation_photo_consent_wire(
    private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at))
$$;
CREATE FUNCTION public.get_mobile_reevaluation_photo_consent(p_user_id uuid,p_cycle_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.mobile_reevaluation_photo_consent_state_at(p_user_id,p_cycle_id,NULL::timestamptz)
$$;

CREATE FUNCTION private.accept_mobile_reevaluation_photo_consent_at(
  p_user_id uuid,p_cycle_id uuid,p_expected_revision bigint,p_document_id uuid,
  p_document_key text,p_version text,p_locale text,p_body_hash text,p_idempotency_key uuid,
  p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; wire jsonb; doc jsonb; active jsonb;
  previous private.mobile_reevaluation_photo_consent_keys%ROWTYPE;
  accepted private.mobile_reevaluation_photo_consents%ROWTYPE;
  observed_at timestamptz; generation_id uuid; reason text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_expected_revision IS NULL OR p_expected_revision<=0 OR p_document_id IS NULL
    OR p_document_key IS NULL OR p_document_key<>'body_photo_reevaluation_consent'
    OR p_version IS NULL OR p_version!~'^[A-Za-z0-9._-]{1,64}$'
    OR p_locale IS NULL OR p_locale NOT IN('pt-BR','en-US')
    OR p_body_hash IS NULL OR p_body_hash!~'^[0-9a-f]{64}$' OR p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_photo_consent' USING ERRCODE='22023';
  END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  wire:=private.mobile_reevaluation_photo_consent_wire(context);
  doc:=context->'document'; active:=context->'current_acceptance';
  observed_at:=(context->>'observed_at')::timestamptz;
  generation_id:=(context->>'signup_generation')::uuid;
  IF doc='null'::jsonb THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_policy_unavailable' USING ERRCODE='P0002';
  END IF;
  -- Current legal identity is checked BEFORE consulting idempotency keys.
  IF doc->>'id' IS DISTINCT FROM p_document_id::text
    OR doc->>'document_key' IS DISTINCT FROM p_document_key
    OR doc->>'version' IS DISTINCT FROM p_version OR doc->>'locale' IS DISTINCT FROM p_locale
    OR doc->>'body_hash' IS DISTINCT FROM p_body_hash THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001';
  END IF;
  SELECT k.* INTO previous FROM private.mobile_reevaluation_photo_consent_keys k
    WHERE k.user_id=p_user_id AND k.idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF previous.signup_generation IS DISTINCT FROM generation_id OR previous.cycle_id IS DISTINCT FROM p_cycle_id
      OR previous.expected_revision IS DISTINCT FROM p_expected_revision
      OR previous.acceptance_id::text IS DISTINCT FROM active->>'acceptance_id'
      OR wire->>'availability' IS DISTINCT FROM 'available' THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_consent_replay_changed' USING ERRCODE='40001';
    END IF;
    RETURN wire;
  END IF;
  IF context->>'cycle_revision' IS DISTINCT FROM p_expected_revision::text THEN
    RAISE EXCEPTION 'mobile_reevaluation_revision_changed' USING ERRCODE='40001';
  END IF;
  IF wire->>'availability'='available' THEN
    INSERT INTO private.mobile_reevaluation_photo_consent_keys(user_id,idempotency_key,
      signup_generation,cycle_id,acceptance_id,expected_revision)
      VALUES(p_user_id,p_idempotency_key,generation_id,p_cycle_id,
        (active->>'acceptance_id')::uuid,p_expected_revision);
    RETURN wire;
  END IF;
  reason:=CASE WHEN wire->>'unavailable_reason'='consent_expired' THEN 'expired' ELSE 'consent_changed' END;
  UPDATE private.mobile_reevaluation_photo_consents SET revoked_at=observed_at,revoked_reason=reason
    WHERE user_id=p_user_id AND cycle_id=p_cycle_id AND revoked_at IS NULL;
  INSERT INTO private.mobile_reevaluation_photo_consents(user_id,signup_generation,cycle_id,
    document_id,document_key,version,locale,body_hash,idle_timeout_seconds,accepted_at,last_activity_at)
    VALUES(p_user_id,generation_id,p_cycle_id,p_document_id,p_document_key,p_version,p_locale,
      p_body_hash,(doc->>'idle_timeout_seconds')::integer,observed_at,observed_at) RETURNING * INTO accepted;
  INSERT INTO private.mobile_reevaluation_photo_consent_keys(user_id,idempotency_key,
    signup_generation,cycle_id,acceptance_id,expected_revision)
    VALUES(p_user_id,p_idempotency_key,generation_id,p_cycle_id,accepted.acceptance_id,p_expected_revision);
  UPDATE private.mobile_reevaluation_cycles SET revision=revision+1,status='collecting'
    WHERE cycle_id=p_cycle_id AND user_id=p_user_id;
  context:=jsonb_set(context,'{current_acceptance}',to_jsonb(accepted));
  context:=jsonb_set(context,'{cycle_revision}',to_jsonb((p_expected_revision+1)::text));
  RETURN private.mobile_reevaluation_photo_consent_wire(context);
END $$;

CREATE FUNCTION public.accept_mobile_reevaluation_photo_consent(
  p_user_id uuid,p_cycle_id uuid,p_expected_revision bigint,p_document_id uuid,
  p_document_key text,p_version text,p_locale text,p_body_hash text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.accept_mobile_reevaluation_photo_consent_at(p_user_id,p_cycle_id,p_expected_revision,
    p_document_id,p_document_key,p_version,p_locale,p_body_hash,p_idempotency_key,NULL::timestamptz)
$$;

REVOKE ALL ON FUNCTION private.mobile_reevaluation_photo_policy_immutable(),
  private.mobile_reevaluation_photo_consent_immutable(),private.mobile_reevaluation_photo_consent_key_immutable(),
  private.mobile_reevaluation_photo_context(uuid,uuid,timestamptz),
  private.mobile_reevaluation_photo_consent_wire(jsonb),
  private.mobile_reevaluation_photo_consent_state_at(uuid,uuid,timestamptz),
  private.accept_mobile_reevaluation_photo_consent_at(uuid,uuid,bigint,uuid,text,text,text,text,uuid,timestamptz),
  public.get_mobile_reevaluation_photo_consent(uuid,uuid),
  public.accept_mobile_reevaluation_photo_consent(uuid,uuid,bigint,uuid,text,text,text,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_reevaluation_photo_consent(uuid,uuid),
  public.accept_mobile_reevaluation_photo_consent(uuid,uuid,bigint,uuid,text,text,text,text,uuid) TO service_role;
COMMIT;

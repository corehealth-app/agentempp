-- Positive completion intents. Dormant: no caller, switch, writer or ACL change
-- to the legacy signup/WhatsApp paths. Epoch is copied, never a foreign key to
-- the current epoch: reset must retain old identities while rotating authority.
BEGIN;
SET LOCAL search_path = pg_catalog;

DO $preflight$
BEGIN
  IF CURRENT_USER <> 'postgres' THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regclass('private.workout_strength_authority_epochs') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR to_regprocedure('public.observe_mobile_signup_strength_epoch(uuid)') IS NULL THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF to_regclass('private.mobile_signup_completion_intents') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('begin_mobile_signup_completion_intent',
        'resolve_mobile_signup_completion_intent','verify_mobile_signup_completion_intent')) THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE TABLE private.mobile_signup_completion_intents (
  user_id uuid NOT NULL REFERENCES private.workout_strength_authority_epochs(user_id) ON DELETE CASCADE,
  preparation_id uuid NOT NULL,
  intent_id uuid NOT NULL,
  request_key text COLLATE "C" NOT NULL,
  epoch uuid NOT NULL,
  issued_at timestamptz NOT NULL,
  PRIMARY KEY (user_id,preparation_id),
  UNIQUE (user_id,intent_id),
  UNIQUE (user_id,request_key),
  CHECK (((request_key COLLATE "C") ~ '^osc1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND pg_catalog.isfinite(issued_at)) IS TRUE)
);
ALTER TABLE private.mobile_signup_completion_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_signup_completion_intents FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.begin_mobile_signup_completion_intent(p_user_id uuid,p_preparation_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $begin$
DECLARE
  observation jsonb;
  current_epoch uuid;
  intent private.mobile_signup_completion_intents%ROWTYPE;
  outcome text := 'reused';
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_preparation_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_signup_completion_intent_input' USING ERRCODE='22023';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_requires_read_committed' USING ERRCODE='22023';
  END IF;
  -- Reuse the existing lock order and concrete authority initialization. These
  -- transaction locks stay held until this issuance is committed: workouts ->
  -- active users -> authority -> intent. No lifecycle/admission/hash is created.
  observation:=public.observe_mobile_signup_strength_epoch(p_user_id);
  current_epoch:=(observation#>>'{observation,epoch}')::uuid;
  SELECT i.* INTO intent FROM private.mobile_signup_completion_intents i
    WHERE i.user_id=p_user_id AND i.preparation_id=p_preparation_id FOR UPDATE;
  IF FOUND THEN
    IF intent.epoch IS DISTINCT FROM current_epoch THEN
      RETURN jsonb_build_object('status','forbidden','reason','stale_epoch');
    END IF;
  ELSE
    INSERT INTO private.mobile_signup_completion_intents
      (user_id,preparation_id,intent_id,request_key,epoch,issued_at)
      VALUES (p_user_id,p_preparation_id,gen_random_uuid(),'osc1:' || gen_random_uuid()::text,
        current_epoch,clock_timestamp()) RETURNING * INTO intent;
    outcome:='issued';
  END IF;
  RETURN jsonb_build_object('status',outcome,'intent',jsonb_build_object(
    'ownerID',intent.user_id::text,'preparationID',intent.preparation_id::text,
    'intentID',intent.intent_id::text,'requestKey',intent.request_key,'epoch',intent.epoch::text,
    'issuedAt',to_char(intent.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $begin$;
REVOKE ALL ON FUNCTION public.begin_mobile_signup_completion_intent(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_mobile_signup_completion_intent(uuid,uuid) TO service_role;

-- Read-only recovery of an uncertain begin. Absent never creates an observation
-- or authorizes the client to issue a new key. A stale Q is never reported absent.
CREATE FUNCTION public.resolve_mobile_signup_completion_intent(p_user_id uuid,p_preparation_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $resolve$
DECLARE intent private.mobile_signup_completion_intents%ROWTYPE; current_epoch uuid;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_preparation_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_signup_completion_intent_input' USING ERRCODE='22023';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_requires_read_committed' USING ERRCODE='22023';
  END IF;
  SELECT i.* INTO intent FROM private.mobile_signup_completion_intents i
    JOIN public.users u ON u.id=i.user_id AND u.status='active'
    WHERE i.user_id=p_user_id AND i.preparation_id=p_preparation_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','absent'); END IF;
  SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
  IF intent.epoch IS DISTINCT FROM current_epoch THEN
    RETURN jsonb_build_object('status','forbidden','reason','stale_epoch');
  END IF;
  RETURN jsonb_build_object('status','resolved','intent',jsonb_build_object(
    'ownerID',intent.user_id::text,'preparationID',intent.preparation_id::text,
    'intentID',intent.intent_id::text,'requestKey',intent.request_key,'epoch',intent.epoch::text,
    'issuedAt',to_char(intent.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $resolve$;
REVOKE ALL ON FUNCTION public.resolve_mobile_signup_completion_intent(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_mobile_signup_completion_intent(uuid,uuid) TO service_role;

-- Point-in-time only. The caller copies this original E0 before preparation;
-- existing admission and keyed writer revalidate E0 after each async boundary.
CREATE FUNCTION public.verify_mobile_signup_completion_intent(p_user_id uuid,p_intent_id uuid,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $verify$
DECLARE intent private.mobile_signup_completion_intents%ROWTYPE; current_epoch uuid;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_intent_id IS NULL OR p_request_key IS NULL
    OR NOT ((p_request_key COLLATE "C") ~ '^osc1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
    RAISE EXCEPTION 'invalid_mobile_signup_completion_intent_input' USING ERRCODE='22023';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_requires_read_committed' USING ERRCODE='22023';
  END IF;
  SELECT i.* INTO intent FROM private.mobile_signup_completion_intents i
    JOIN public.users u ON u.id=i.user_id AND u.status='active'
    WHERE i.user_id=p_user_id AND i.intent_id=p_intent_id AND i.request_key=(p_request_key COLLATE "C");
  IF NOT FOUND THEN RETURN jsonb_build_object('status','forbidden','reason','invalid_intent'); END IF;
  SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
  IF intent.epoch IS DISTINCT FROM current_epoch THEN
    RETURN jsonb_build_object('status','forbidden','reason','stale_epoch');
  END IF;
  RETURN jsonb_build_object('status','verified','intent',jsonb_build_object(
    'ownerID',intent.user_id::text,'preparationID',intent.preparation_id::text,
    'intentID',intent.intent_id::text,'requestKey',intent.request_key,'epoch',intent.epoch::text,
    'issuedAt',to_char(intent.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $verify$;
REVOKE ALL ON FUNCTION public.verify_mobile_signup_completion_intent(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.verify_mobile_signup_completion_intent(uuid,uuid,text) TO service_role;

DO $acl$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c,
    LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
    WHERE c.oid='private.mobile_signup_completion_intents'::regclass AND a.grantee<>c.relowner)
    OR EXISTS (SELECT 1 FROM pg_proc p,
      LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE p.oid IN ('public.begin_mobile_signup_completion_intent(uuid,uuid)'::regprocedure,
        'public.resolve_mobile_signup_completion_intent(uuid,uuid)'::regprocedure,
        'public.verify_mobile_signup_completion_intent(uuid,uuid,text)'::regprocedure)
        AND a.grantee NOT IN (p.proowner,'service_role'::regrole)) THEN
    RAISE EXCEPTION 'mobile_signup_completion_intent_unexpected_inherited_grant' USING ERRCODE='42501';
  END IF;
END $acl$;
COMMIT;

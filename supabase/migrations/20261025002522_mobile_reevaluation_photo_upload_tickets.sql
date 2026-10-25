-- Dormant signing authority. No URL/token is stored or issued by SQL.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501'; END IF;
  IF to_regclass('private.mobile_reevaluation_photo_assets') IS NULL THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_photo_origin' USING ERRCODE='42P01';
  END IF;
END $preflight$;

ALTER TABLE private.mobile_reevaluation_photo_assets ADD CONSTRAINT mobile_reevaluation_photo_ticket_scope
  UNIQUE(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id);
CREATE TABLE private.mobile_reevaluation_photo_upload_tickets (
  ticket_id uuid PRIMARY KEY,
  asset_id uuid NOT NULL,
  user_id uuid NOT NULL,
  signup_generation uuid NOT NULL,
  cycle_id uuid NOT NULL,
  consent_acceptance_id uuid NOT NULL,
  prepared_at timestamptz NOT NULL CHECK(isfinite(prepared_at)),
  provider_expires_at timestamptz,
  registered_at timestamptz,
  FOREIGN KEY(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id)
    REFERENCES private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id),
  CHECK((provider_expires_at IS NULL)=(registered_at IS NULL)),
  CHECK(provider_expires_at IS NULL OR (isfinite(provider_expires_at) AND provider_expires_at>prepared_at)),
  CHECK(registered_at IS NULL OR (isfinite(registered_at) AND registered_at>=prepared_at))
);
CREATE INDEX mobile_reevaluation_photo_tickets_asset
  ON private.mobile_reevaluation_photo_upload_tickets(asset_id,provider_expires_at);
ALTER TABLE private.mobile_reevaluation_photo_upload_tickets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_upload_tickets FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.preserve_mobile_reevaluation_photo_upload_ticket() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF to_jsonb(NEW)-ARRAY['provider_expires_at','registered_at']
      IS DISTINCT FROM to_jsonb(OLD)-ARRAY['provider_expires_at','registered_at']
    OR (OLD.provider_expires_at IS NOT NULL AND NEW IS DISTINCT FROM OLD) THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_upload_ticket_immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_photo_upload_ticket BEFORE UPDATE
  ON private.mobile_reevaluation_photo_upload_tickets FOR EACH ROW
  EXECUTE FUNCTION private.preserve_mobile_reevaluation_photo_upload_ticket();

CREATE FUNCTION private.mobile_reevaluation_photo_upload_ticket_wire(
  t private.mobile_reevaluation_photo_upload_tickets) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT jsonb_build_object('id',(t).ticket_id,'asset_id',(t).asset_id,'user_id',(t).user_id,
    'signup_generation',(t).signup_generation,'cycle_id',(t).cycle_id,
    'consent_acceptance_id',(t).consent_acceptance_id,
    'prepared_at',to_char((t).prepared_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'provider_expires_at',CASE WHEN (t).provider_expires_at IS NULL THEN NULL ELSE
      to_char((t).provider_expires_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
    'registered_at',CASE WHEN (t).registered_at IS NULL THEN NULL ELSE
      to_char((t).registered_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END)
$$;

CREATE FUNCTION private.prepare_mobile_reevaluation_photo_upload_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_ticket_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; asset_wire jsonb; ticket private.mobile_reevaluation_photo_upload_tickets%ROWTYPE;
  generation_id uuid; acceptance_id uuid; observed_at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_asset_id IS NULL OR p_ticket_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_upload_ticket' USING ERRCODE='22023';
  END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001';
  END IF;
  asset_wire:=private.mobile_reevaluation_photo_asset_wire(context,p_asset_id);
  IF asset_wire IS NULL THEN RAISE EXCEPTION 'mobile_reevaluation_photo_not_found' USING ERRCODE='P0002'; END IF;
  IF asset_wire#>>'{asset,status}' IS DISTINCT FROM 'pending_upload' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_upload_not_pending' USING ERRCODE='22023';
  END IF;
  generation_id:=(context->>'signup_generation')::uuid;
  acceptance_id:=(context#>>'{current_acceptance,acceptance_id}')::uuid;
  observed_at:=(context->>'observed_at')::timestamptz;
  SELECT t.* INTO ticket FROM private.mobile_reevaluation_photo_upload_tickets t WHERE t.ticket_id=p_ticket_id;
  IF FOUND THEN
    IF ROW(ticket.asset_id,ticket.user_id,ticket.signup_generation,ticket.cycle_id,ticket.consent_acceptance_id)
      IS DISTINCT FROM ROW(p_asset_id,p_user_id,generation_id,p_cycle_id,acceptance_id) THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_upload_ticket_changed' USING ERRCODE='40001';
    END IF;
  ELSE
    INSERT INTO private.mobile_reevaluation_photo_upload_tickets(ticket_id,asset_id,user_id,
      signup_generation,cycle_id,consent_acceptance_id,prepared_at)
      VALUES(p_ticket_id,p_asset_id,p_user_id,generation_id,p_cycle_id,acceptance_id,observed_at)
      RETURNING * INTO ticket;
  END IF;
  RETURN asset_wire||jsonb_build_object('ticket',private.mobile_reevaluation_photo_upload_ticket_wire(ticket));
END $$;

CREATE FUNCTION private.register_mobile_reevaluation_photo_upload_ticket_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_ticket_id uuid,
  p_provider_expires_at timestamptz,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE ticket private.mobile_reevaluation_photo_upload_tickets%ROWTYPE; observed_at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_cycle_id IS NULL OR p_asset_id IS NULL OR p_ticket_id IS NULL
    OR p_provider_expires_at IS NULL OR NOT isfinite(p_provider_expires_at) THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_upload_ticket' USING ERRCODE='22023';
  END IF;
  -- Bookkeeping of an already issued capability must survive soft-delete,
  -- reset, consent expiry and invalidation. This RPC grants no live access.
  PERFORM u.id FROM public.users u WHERE u.id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_upload_ticket_not_found' USING ERRCODE='P0002'; END IF;
  SELECT t.* INTO ticket FROM private.mobile_reevaluation_photo_upload_tickets t
    WHERE t.ticket_id=p_ticket_id AND t.user_id=p_user_id AND t.cycle_id=p_cycle_id AND t.asset_id=p_asset_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_reevaluation_upload_ticket_not_found' USING ERRCODE='P0002'; END IF;
  observed_at:=coalesce(p_observed_at,clock_timestamp());
  IF NOT isfinite(observed_at) OR observed_at<ticket.prepared_at OR p_provider_expires_at<=ticket.prepared_at THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_upload_ticket' USING ERRCODE='22023';
  END IF;
  IF ticket.provider_expires_at IS NOT NULL THEN
    IF ticket.provider_expires_at IS DISTINCT FROM p_provider_expires_at THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_upload_ticket_changed' USING ERRCODE='40001';
    END IF;
  ELSE
    UPDATE private.mobile_reevaluation_photo_upload_tickets SET provider_expires_at=p_provider_expires_at,
      registered_at=observed_at WHERE ticket_id=p_ticket_id RETURNING * INTO ticket;
  END IF;
  RETURN jsonb_build_object('version',1,'ticket',private.mobile_reevaluation_photo_upload_ticket_wire(ticket));
END $$;

CREATE FUNCTION public.prepare_mobile_reevaluation_photo_upload(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_ticket_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.prepare_mobile_reevaluation_photo_upload_at(p_user_id,p_cycle_id,p_asset_id,p_ticket_id,NULL::timestamptz)
$$;
CREATE FUNCTION public.register_mobile_reevaluation_photo_upload_ticket(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_ticket_id uuid,p_provider_expires_at timestamptz)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.register_mobile_reevaluation_photo_upload_ticket_at(p_user_id,p_cycle_id,p_asset_id,p_ticket_id,p_provider_expires_at,NULL::timestamptz)
$$;
REVOKE ALL ON FUNCTION private.preserve_mobile_reevaluation_photo_upload_ticket(),
  private.mobile_reevaluation_photo_upload_ticket_wire(private.mobile_reevaluation_photo_upload_tickets),
  private.prepare_mobile_reevaluation_photo_upload_at(uuid,uuid,uuid,uuid,timestamptz),
  private.register_mobile_reevaluation_photo_upload_ticket_at(uuid,uuid,uuid,uuid,timestamptz,timestamptz),
  public.prepare_mobile_reevaluation_photo_upload(uuid,uuid,uuid,uuid),
  public.register_mobile_reevaluation_photo_upload_ticket(uuid,uuid,uuid,uuid,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_mobile_reevaluation_photo_upload(uuid,uuid,uuid,uuid),
  public.register_mobile_reevaluation_photo_upload_ticket(uuid,uuid,uuid,uuid,timestamptz) TO service_role;
COMMIT;

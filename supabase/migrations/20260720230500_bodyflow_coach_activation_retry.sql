-- Preserve activation idempotency when a successful response is lost and the
-- master-admin action is retried.

CREATE OR REPLACE FUNCTION public.approve_and_activate_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_status text;
  v_validation jsonb;
  v_activation jsonb;
BEGIN
  IF p_pack_id IS NULL OR p_actor_id IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, actor_id, and time are required' USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;

  IF v_status = 'active' THEN
    RETURN public.activate_coach_content_pack(p_pack_id, p_actor_id, p_now);
  END IF;

  IF v_status NOT IN ('draft', 'scheduled') THEN
    RAISE EXCEPTION 'only a draft or scheduled pack can be activated' USING ERRCODE = '23514';
  END IF;

  v_validation := public.validate_coach_content_pack(p_pack_id);
  IF NOT (v_validation->>'valid')::boolean THEN
    RAISE EXCEPTION 'coach content pack must be complete before activation' USING ERRCODE = '23514';
  END IF;

  UPDATE public.coach_content_packs
  SET approved_by = p_actor_id,
      approved_at = COALESCE(approved_at, p_now),
      updated_at = p_now
  WHERE id = p_pack_id;

  v_activation := public.activate_coach_content_pack(p_pack_id, p_actor_id, p_now);

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.activate',
    'coach_content_pack',
    p_pack_id::text,
    jsonb_build_object('pack_id', p_pack_id, 'status', v_status),
    jsonb_build_object(
      'pack_id', p_pack_id,
      'status', 'active',
      'previous_pack_id', v_activation->'previous_pack_id',
      'entry_count', v_validation->'entry_count'
    ),
    p_now
  );

  RETURN v_activation;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_and_activate_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_and_activate_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;

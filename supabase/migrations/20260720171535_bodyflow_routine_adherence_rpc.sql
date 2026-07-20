CREATE OR REPLACE FUNCTION public.record_routine_adherence_atomic(
  p_user_id uuid,
  p_routine_item_id uuid,
  p_expected_item_type text,
  p_idempotency_key text,
  p_taken_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_existing record;
  v_item_type text;
  v_log_id uuid;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_routine_item_id IS NULL
    OR p_expected_item_type NOT IN ('supplement', 'medication')
    OR p_idempotency_key IS NULL
    OR p_taken_at IS NULL THEN
    RAISE EXCEPTION 'invalid routine adherence payload' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':routine:' || p_idempotency_key, 0)
  );

  SELECT *
  INTO v_existing
  FROM public.routine_adherence_logs
  WHERE user_id = p_user_id
    AND idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing.routine_item_id <> p_routine_item_id
      OR v_existing.item_type <> p_expected_item_type
      OR v_existing.status <> 'taken'
      OR v_existing.occurred_at <> p_taken_at THEN
      RAISE EXCEPTION 'routine adherence idempotency key conflict' USING ERRCODE = '23505';
    END IF;

    RETURN jsonb_build_object(
      'inserted', false,
      'adherence_log_id', v_existing.id
    );
  END IF;

  SELECT item_type
  INTO v_item_type
  FROM public.routine_items
  WHERE id = p_routine_item_id
    AND user_id = p_user_id
    AND item_type = p_expected_item_type
    AND active
  FOR KEY SHARE;

  IF v_item_type IS NULL THEN
    RAISE EXCEPTION 'routine item is inactive, missing, or has another type'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.routine_adherence_logs (
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    occurred_at
  ) VALUES (
    p_user_id,
    p_routine_item_id,
    v_item_type,
    'taken',
    p_idempotency_key,
    p_taken_at
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'inserted', true,
    'adherence_log_id', v_log_id
  );
END;
$$;

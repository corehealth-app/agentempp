CREATE OR REPLACE FUNCTION public.ensure_user_initialized(
  p_wpp text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wpp text := NULLIF(btrim(p_wpp), '');
  v_user_id uuid;
BEGIN
  IF v_wpp IS NULL THEN
    RAISE EXCEPTION 'wpp is required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_wpp || ':user-init', 0));

  SELECT id
  INTO v_user_id
  FROM public.users
  WHERE wpp = v_wpp;

  IF v_user_id IS NULL THEN
    INSERT INTO public.users (wpp, status)
    VALUES (v_wpp, 'active')
    ON CONFLICT (wpp) DO NOTHING
    RETURNING id INTO v_user_id;

    IF v_user_id IS NULL THEN
      SELECT id
      INTO v_user_id
      FROM public.users
      WHERE wpp = v_wpp;
    END IF;
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'failed to initialize user';
  END IF;

  INSERT INTO public.user_profiles (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_progress (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN v_user_id;
END;
$$;

ALTER TABLE public.mobile_devices
  DROP CONSTRAINT mobile_devices_installation_unique;

CREATE UNIQUE INDEX mobile_devices_active_installation_unique
  ON public.mobile_devices (installation_id)
  WHERE active;

CREATE OR REPLACE FUNCTION public.upsert_mobile_device(
  p_user_id uuid,
  p_installation_id text,
  p_apns_environment text,
  p_apns_token text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_device_id uuid;
  v_active_device record;
  v_installation_id text := NULLIF(btrim(p_installation_id), '');
  v_apns_token text := lower(p_apns_token);
  v_token_hash text;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR v_installation_id IS NULL
    OR p_apns_environment NOT IN ('sandbox', 'production')
    OR v_apns_token IS NULL
    OR v_apns_token !~ '^[0-9a-f]+$'
    OR char_length(v_apns_token) NOT BETWEEN 64 AND 512
    OR char_length(v_apns_token) % 2 <> 0 THEN
    RAISE EXCEPTION 'invalid mobile device payload' USING ERRCODE = '22023';
  END IF;

  v_token_hash := encode(extensions.digest(v_apns_token, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_token_hash || ':apns-token', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(v_installation_id || ':installation', 0));

  SELECT id, user_id, apns_token_hash
  INTO v_active_device
  FROM public.mobile_devices
  WHERE installation_id = v_installation_id
    AND active
  FOR UPDATE;

  IF FOUND
    AND v_active_device.user_id <> p_user_id
    AND v_active_device.apns_token_hash <> v_token_hash THEN
    RAISE EXCEPTION 'active installation belongs to another user' USING ERRCODE = '23505';
  END IF;

  UPDATE public.mobile_devices
  SET active = false,
      updated_at = clock_timestamp()
  WHERE apns_token_hash = v_token_hash
    AND active
    AND (v_active_device.id IS NULL OR id <> v_active_device.id);

  IF v_active_device.id IS NOT NULL AND v_active_device.user_id = p_user_id THEN
    UPDATE public.mobile_devices
    SET platform = 'ios',
        apns_environment = p_apns_environment,
        apns_token = v_apns_token,
        last_seen_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE id = v_active_device.id
    RETURNING id INTO v_device_id;

    RETURN v_device_id;
  END IF;

  IF v_active_device.id IS NOT NULL THEN
    UPDATE public.mobile_devices
    SET active = false,
        updated_at = clock_timestamp()
    WHERE id = v_active_device.id;
  END IF;

  INSERT INTO public.mobile_devices (
    user_id,
    installation_id,
    platform,
    apns_environment,
    apns_token,
    active,
    last_seen_at,
    updated_at
  ) VALUES (
    p_user_id,
    v_installation_id,
    'ios',
    p_apns_environment,
    v_apns_token,
    true,
    clock_timestamp(),
    clock_timestamp()
  )
  RETURNING id INTO v_device_id;

  RETURN v_device_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_mobile_device(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_mobile_device(uuid, text, text, text)
  TO service_role;

COMMENT ON FUNCTION public.upsert_mobile_device(uuid, text, text, text) IS
  'Registers an active iOS installation without rewriting ownership of historical delivery records.';

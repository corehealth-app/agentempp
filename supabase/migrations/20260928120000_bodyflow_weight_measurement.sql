-- M1 — weight recorded by the app in the existing official source.
--
-- `user_profiles.weight_kg` stays the single official weight (no second
-- ledger). This migration adds the instant of the measurement and one way to
-- apply a measurement in order, so the "last weight" does not depend on the
-- channel that wrote it.
--
-- Nothing here writes daily_snapshots, user_progress or the 7,700 block, and
-- no target formula changes. Existing rows are not backfilled: a weight
-- without an instant stays without one (its age cannot be proven).

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS weight_measured_at timestamptz;

COMMENT ON COLUMN public.user_profiles.weight_measured_at IS
  'Instant of the measurement stored in weight_kg. NULL = legacy value written before this column existed (age unknown).';

-- Legacy writers (WhatsApp profile tool, onboarding completion, conversation
-- reset) update weight_kg directly and know nothing about the instant. This
-- trigger keeps the pair consistent for them without any code change: a
-- weight written without an instant is dated at the write; a cleared weight
-- clears the instant. A writer that sets the instant itself is left alone.
CREATE OR REPLACE FUNCTION private.sync_weight_measured_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF NEW.weight_kg IS NULL THEN
    NEW.weight_measured_at := NULL;
  ELSIF TG_OP = 'INSERT' THEN
    IF NEW.weight_measured_at IS NULL THEN
      NEW.weight_measured_at := clock_timestamp();
    END IF;
  ELSIF NEW.weight_kg IS DISTINCT FROM OLD.weight_kg
    AND NEW.weight_measured_at IS NOT DISTINCT FROM OLD.weight_measured_at THEN
    -- Dated at the write, and never before the instant already stored (the
    -- app may have recorded one a few minutes ahead of this clock).
    NEW.weight_measured_at := GREATEST(
      clock_timestamp(),
      COALESCE(OLD.weight_measured_at + interval '1 microsecond', clock_timestamp())
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_profiles_sync_weight_measured_at ON public.user_profiles;
CREATE TRIGGER user_profiles_sync_weight_measured_at
  BEFORE INSERT OR UPDATE OF weight_kg, weight_measured_at
  ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION private.sync_weight_measured_at();

-- Known limits of the legacy writers, which this migration does not change:
-- they always count as the newest measurement (they carry no instant of
-- their own), and a legacy write of the SAME value does not renew the
-- instant, so a measurement taken between the two can still be applied.
--
-- The one ordered path. Caller holds the per-user lock.
--   no current instant (legacy)            -> applied
--   newer than the current instant         -> applied
--   same instant, same value               -> not applied (same_measurement)
--   same instant, different value          -> 23505 weight_measurement_conflict
--   older than the current instant         -> not applied (older_than_current)
CREATE OR REPLACE FUNCTION private.apply_weight_measurement(
  p_user_id uuid,
  p_weight_kg numeric,
  p_measured_at timestamptz,
  p_source text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_weight numeric(5, 2);
  v_current_weight numeric(5, 2);
  v_current_at timestamptz;
  v_found boolean;
BEGIN
  IF p_user_id IS NULL
    OR p_weight_kg IS NULL
    OR p_measured_at IS NULL
    OR p_source IS NULL
    OR p_source !~ '^[a-z][a-z0-9_]{1,39}$' THEN
    RAISE EXCEPTION 'invalid weight measurement' USING ERRCODE = '22023';
  END IF;

  v_weight := round(p_weight_kg, 2);
  IF v_weight < 30 OR v_weight > 300 THEN
    RAISE EXCEPTION 'weight out of range' USING ERRCODE = '22023';
  END IF;

  SELECT weight_kg, weight_measured_at, true
  INTO v_current_weight, v_current_at, v_found
  FROM public.user_profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_found IS NOT TRUE THEN
    INSERT INTO public.user_profiles (user_id, weight_kg, weight_measured_at)
    VALUES (p_user_id, v_weight, p_measured_at);
    RETURN jsonb_build_object(
      'applied', true, 'reason', 'applied',
      'weight_kg', v_weight, 'measured_at', p_measured_at
    );
  END IF;

  IF v_current_weight IS NOT NULL AND v_current_at IS NOT NULL THEN
    IF p_measured_at = v_current_at THEN
      IF v_weight = v_current_weight THEN
        RETURN jsonb_build_object(
          'applied', false, 'reason', 'same_measurement',
          'weight_kg', v_current_weight, 'measured_at', v_current_at
        );
      END IF;
      RAISE EXCEPTION 'weight_measurement_conflict' USING ERRCODE = '23505';
    END IF;
    IF p_measured_at < v_current_at THEN
      RETURN jsonb_build_object(
        'applied', false, 'reason', 'older_than_current',
        'weight_kg', v_current_weight, 'measured_at', v_current_at
      );
    END IF;
  END IF;

  UPDATE public.user_profiles
  SET weight_kg = v_weight,
      weight_measured_at = p_measured_at,
      updated_at = clock_timestamp()
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'applied', true, 'reason', 'applied',
    'weight_kg', v_weight, 'measured_at', p_measured_at
  );
END;
$$;

-- Mobile entry point. The unit is converted here, before rounding and
-- comparing, so a replay in pounds meets the stored kilograms.
CREATE OR REPLACE FUNCTION public.record_weight_atomic(
  p_user_id uuid,
  p_value numeric,
  p_unit text,
  p_measured_at timestamptz,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_active boolean;
  v_weight numeric;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT true INTO v_active
  FROM public.users
  WHERE id = p_user_id
    AND status = 'active';

  IF v_active IS NOT TRUE
    OR p_value IS NULL
    OR p_unit IS NULL
    OR p_unit NOT IN ('kg', 'lb')
    OR p_measured_at IS NULL
    OR p_idempotency_key IS NULL
    OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,128}$'
    OR p_measured_at > clock_timestamp() + interval '5 minutes'
    OR p_measured_at < clock_timestamp() - interval '7 days' THEN
    RAISE EXCEPTION 'invalid weight payload' USING ERRCODE = '22023';
  END IF;

  v_weight := CASE p_unit WHEN 'lb' THEN p_value * 0.45359237 ELSE p_value END;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':weight', 0));

  RETURN private.apply_weight_measurement(p_user_id, v_weight, p_measured_at, 'mobile');
END;
$$;

REVOKE ALL ON FUNCTION private.sync_weight_measured_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.apply_weight_measurement(uuid, numeric, timestamptz, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_weight_atomic(uuid, numeric, text, timestamptz, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_weight_atomic(uuid, numeric, text, timestamptz, text)
  TO service_role;

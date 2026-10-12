-- B4b: trusted signup origin. Historical/default false or NULL stays UNKNOWN.
-- No retag/backfill by kind/context and no new client column privileges.
BEGIN;

ALTER TABLE public.media_assets
  ADD COLUMN signup_origin boolean DEFAULT false;

ALTER TABLE public.media_assets
  ADD CONSTRAINT media_assets_signup_origin_shape CHECK (
    signup_origin IS NOT TRUE OR (
      kind = 'body_checkin_photo'
      AND context_text IS NOT NULL
      AND context_text IN ('Foto de frente.', 'Foto de lado.', 'Foto de costas.')
    )
  );

CREATE FUNCTION private.enforce_signup_body_photo_origin()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  IF NEW.signup_origin IS DISTINCT FROM OLD.signup_origin THEN
    RAISE EXCEPTION 'signup_body_photo_origin_immutable' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_signup_body_photo_origin
  BEFORE UPDATE ON public.media_assets
  FOR EACH ROW EXECUTE FUNCTION private.enforce_signup_body_photo_origin();

REVOKE ALL ON FUNCTION private.enforce_signup_body_photo_origin()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.enforce_signup_body_photo_origin() TO service_role;

COMMENT ON COLUMN public.media_assets.signup_origin IS
  'Private trusted INSERT marker: true proves signup origin. False/NULL is UNKNOWN; immutable.';

COMMIT;

-- Additive G-local negative proof and read-only technical signal, staging delivery only.
-- Existing checked/core/disposition functions and historical rows are untouched.
BEGIN;

CREATE TABLE private.signup_body_photo_zero_scopes (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  onboarding_completed_at timestamptz NOT NULL CHECK (isfinite(onboarding_completed_at)),
  version smallint NOT NULL DEFAULT 1 CHECK (version = 1),
  policy text NOT NULL DEFAULT 'signup_zero_scope_v1' CHECK (policy = 'signup_zero_scope_v1'),
  PRIMARY KEY (user_id, onboarding_completed_at)
);
ALTER TABLE private.signup_body_photo_zero_scopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.signup_body_photo_zero_scopes FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.preserve_signup_body_photo_zero_scope()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
    RAISE EXCEPTION 'signup_body_photo_zero_scope_immutable' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER preserve_signup_body_photo_zero_scope BEFORE UPDATE
  ON private.signup_body_photo_zero_scopes FOR EACH ROW
  EXECUTE FUNCTION private.preserve_signup_body_photo_zero_scope();
REVOKE ALL ON FUNCTION private.preserve_signup_body_photo_zero_scope()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.complete_mobile_onboarding_with_cleanup_scope(
  p_user_id uuid, p_submission jsonb, p_confirmation jsonb,
  p_expected_completed boolean, p_expected_completed_at timestamptz, p_expected_receipt_count bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  completed boolean; completed_at timestamptz; fresh_open boolean;
  no_unassigned_sources boolean; result jsonb; generation timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
  END IF;
  -- Same lock order as insertion and the unchanged checked wrapper.
  PERFORM pg_advisory_xact_lock(hashtextextended('mobile-onboarding:' || p_user_id::text, 0));
  SELECT p.onboarding_completed, p.onboarding_completed_at INTO completed, completed_at
    FROM public.users u JOIN public.user_profiles p ON p.user_id = u.id
    WHERE u.id = p_user_id AND u.status = 'active' FOR UPDATE OF u, p;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;
  fresh_open := completed IS FALSE AND completed_at IS NULL;
  no_unassigned_sources := false;
  IF fresh_open THEN
    -- Observe ALL marked unassigned sources, including legacy version NULL and every status.
    PERFORM m.id FROM public.media_assets m
      WHERE m.user_id = p_user_id AND m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE
        AND NOT EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a WHERE a.asset_id = m.id)
      ORDER BY m.id FOR UPDATE;
    SELECT NOT EXISTS (
      SELECT 1 FROM public.media_assets m
      WHERE m.user_id = p_user_id AND m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE
        AND NOT EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a WHERE a.asset_id = m.id)
    ) INTO no_unassigned_sources;
  END IF;
  result := public.complete_mobile_onboarding_with_body_photo_confirmation(
    p_user_id, p_submission, p_confirmation,
    p_expected_completed, p_expected_completed_at, p_expected_receipt_count
  );
  IF fresh_open AND no_unassigned_sources THEN
    IF jsonb_typeof(result) IS DISTINCT FROM 'object'
      OR result->>'user_id' IS DISTINCT FROM p_user_id::text
      OR result->>'onboarding_completed' IS DISTINCT FROM 'true'
      OR result->>'completed_at' IS NULL THEN
      RAISE EXCEPTION 'invalid_signup_body_photo_zero_scope' USING ERRCODE = '22023';
    END IF;
    generation := (result->>'completed_at')::timestamptz;
    IF NOT isfinite(generation) OR EXISTS (
      SELECT 1 FROM private.signup_body_photo_dispositions h
      WHERE h.user_id = p_user_id AND h.onboarding_completed_at = generation
    ) THEN
      RAISE EXCEPTION 'invalid_signup_body_photo_zero_scope' USING ERRCODE = '22023';
    END IF;
    -- Same transaction: a ledger failure rolls back the actual core/legal completion.
    INSERT INTO private.signup_body_photo_zero_scopes(user_id, onboarding_completed_at)
      VALUES (p_user_id, generation) ON CONFLICT (user_id, onboarding_completed_at) DO NOTHING;
  END IF;
  RETURN result;
END; $$;

CREATE FUNCTION public.get_mobile_signup_body_photo_cleanup_scope(p_user_id uuid, p_generation text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE generation timestamptz; result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_generation IS NULL OR length(p_generation) > 35
    OR p_generation !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,6})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$' THEN
    RAISE EXCEPTION 'invalid_body_photo_cleanup_generation' USING ERRCODE = '22023';
  END IF;
  BEGIN
    generation := p_generation::timestamptz;
  EXCEPTION WHEN SQLSTATE '22007' OR SQLSTATE '22008' OR SQLSTATE '22009' OR SQLSTATE '22P02' THEN
    RAISE EXCEPTION 'invalid_body_photo_cleanup_generation' USING ERRCODE = '22023';
  END;
  IF NOT isfinite(generation) THEN
    RAISE EXCEPTION 'invalid_body_photo_cleanup_generation' USING ERRCODE = '22023';
  END IF;
  -- One SELECT snapshot for account, positive manifest and immutable negative proof.
  SELECT jsonb_build_object('version', 1, 'user_id', u.id, 'generation', p_generation,
    'state', CASE
      WHEN h.user_id IS NOT NULL AND z.user_id IS NOT NULL THEN 'unknown'
      WHEN h.user_id IS NOT NULL AND h.version = 1 AND h.policy = 'delete_all_signup_v1'
        AND h.scope_sealed IS TRUE AND h.manifest_count > 0
        AND items.n = h.manifest_count AND items.valid IS TRUE THEN 'pending'
      WHEN h.user_id IS NULL AND z.version = 1 AND z.policy = 'signup_zero_scope_v1' THEN 'not_required'
      ELSE 'unknown' END)
    INTO result FROM public.users u
    LEFT JOIN private.signup_body_photo_dispositions h
      ON h.user_id = u.id AND h.onboarding_completed_at = generation
    LEFT JOIN private.signup_body_photo_zero_scopes z
      ON z.user_id = u.id AND z.onboarding_completed_at = generation
    CROSS JOIN LATERAL (
      SELECT count(*) AS n, bool_and(a.bucket_id = 'body-checkin-photos'
        AND a.context_text IN ('Foto de frente.', 'Foto de lado.', 'Foto de costas.')
        AND a.object_path ~ ('^' || p_user_id::text || '/' || a.asset_id::text || '[.][a-z0-9]+$')) AS valid
      FROM private.signup_body_photo_disposition_assets a
      WHERE a.user_id = u.id AND a.onboarding_completed_at = generation
    ) items
    WHERE u.id = p_user_id AND u.status = 'active';
  IF result IS NULL THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;
  RETURN result;
END; $$;

REVOKE ALL ON FUNCTION
  public.complete_mobile_onboarding_with_cleanup_scope(uuid,jsonb,jsonb,boolean,timestamptz,bigint),
  public.get_mobile_signup_body_photo_cleanup_scope(uuid,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.complete_mobile_onboarding_with_cleanup_scope(uuid,jsonb,jsonb,boolean,timestamptz,bigint),
  public.get_mobile_signup_body_photo_cleanup_scope(uuid,text) TO service_role;
COMMIT;

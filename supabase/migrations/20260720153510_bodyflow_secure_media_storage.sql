-- BodyFlow P0: private, app-first media catalog and Storage buckets.
-- Patient clients use the authenticated BFF for every upload/download capability.

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES
  (
    'meal-photos',
    'meal-photos',
    false,
    15728640,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
  ),
  (
    'body-checkin-photos',
    'body-checkin-photos',
    false,
    15728640,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
  ),
  (
    'gym-photos',
    'gym-photos',
    false,
    15728640,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
  ),
  (
    'audio-notes',
    'audio-notes',
    false,
    26214400,
    ARRAY[
      'audio/mpeg',
      'audio/mp4',
      'audio/x-m4a',
      'audio/aac',
      'audio/wav',
      'audio/x-wav',
      'audio/ogg'
    ]
  ),
  (
    'content-covers',
    'content-covers',
    false,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  )
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE TABLE public.media_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  kind text NOT NULL,
  bucket_id text NOT NULL REFERENCES storage.buckets(id),
  object_path text NOT NULL,
  mime_type text NOT NULL,
  declared_size_bytes bigint NOT NULL,
  actual_size_bytes bigint,
  etag text,
  status text NOT NULL DEFAULT 'pending_upload',
  failure_stage text,
  failure_code text,
  context_text text,
  processing_request_id text,
  processing_result jsonb,
  source_request_hash text NOT NULL,
  retention_until timestamptz,
  uploaded_at timestamptz,
  processed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_assets_object_unique UNIQUE (bucket_id, object_path),
  CONSTRAINT media_assets_request_unique UNIQUE (user_id, source_request_hash),
  CONSTRAINT media_assets_kind_check CHECK (
    kind IN (
      'meal_photo',
      'body_checkin_photo',
      'gym_photo',
      'audio_note',
      'content_cover'
    )
  ),
  CONSTRAINT media_assets_bucket_kind_check CHECK (
    (kind = 'meal_photo' AND bucket_id = 'meal-photos')
    OR (kind = 'body_checkin_photo' AND bucket_id = 'body-checkin-photos')
    OR (kind = 'gym_photo' AND bucket_id = 'gym-photos')
    OR (kind = 'audio_note' AND bucket_id = 'audio-notes')
    OR (kind = 'content_cover' AND bucket_id = 'content-covers')
  ),
  CONSTRAINT media_assets_mime_kind_check CHECK (
    (
      kind IN ('meal_photo', 'body_checkin_photo', 'gym_photo')
      AND mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif')
    )
    OR (
      kind = 'audio_note'
      AND mime_type IN (
        'audio/mpeg',
        'audio/mp4',
        'audio/x-m4a',
        'audio/aac',
        'audio/wav',
        'audio/x-wav',
        'audio/ogg'
      )
    )
    OR (
      kind = 'content_cover'
      AND mime_type IN ('image/jpeg', 'image/png', 'image/webp')
    )
  ),
  CONSTRAINT media_assets_size_check CHECK (
    declared_size_bytes > 0
    AND (
      (kind IN ('meal_photo', 'body_checkin_photo', 'gym_photo') AND declared_size_bytes <= 15728640)
      OR (kind = 'audio_note' AND declared_size_bytes <= 26214400)
      OR (kind = 'content_cover' AND declared_size_bytes <= 10485760)
    )
    AND (actual_size_bytes IS NULL OR actual_size_bytes = declared_size_bytes)
  ),
  CONSTRAINT media_assets_path_check CHECK (
    object_path ~ (
      '^'
      || user_id::text
      || '/'
      || id::text
      || '[.][a-z0-9]+$'
    )
  ),
  CONSTRAINT media_assets_status_check CHECK (
    status IN (
      'pending_upload',
      'uploaded',
      'processing',
      'processed',
      'failed',
      'deleted'
    )
  ),
  CONSTRAINT media_assets_failure_stage_check CHECK (
    failure_stage IS NULL OR failure_stage IN ('upload', 'processing')
  ),
  CONSTRAINT media_assets_failure_consistency_check CHECK (
    (status = 'failed' AND failure_stage IS NOT NULL AND failure_code IS NOT NULL)
    OR (status <> 'failed' AND failure_stage IS NULL AND failure_code IS NULL)
  ),
  CONSTRAINT media_assets_context_check CHECK (
    context_text IS NULL OR char_length(context_text) BETWEEN 1 AND 1000
  ),
  CONSTRAINT media_assets_hash_check CHECK (
    source_request_hash ~ '^[0-9a-f]{64}$'
    AND (
      processing_request_id IS NULL
      OR processing_request_id ~ '^[0-9a-f]{64}$'
    )
  ),
  CONSTRAINT media_assets_retention_check CHECK (
    kind = 'content_cover' OR retention_until IS NOT NULL
  ),
  CONSTRAINT media_assets_upload_consistency_check CHECK (
    status IN ('pending_upload', 'failed', 'deleted')
    OR (actual_size_bytes IS NOT NULL AND uploaded_at IS NOT NULL)
  ),
  CONSTRAINT media_assets_processed_consistency_check CHECK (
    status <> 'processed' OR processed_at IS NOT NULL
  ),
  CONSTRAINT media_assets_processing_request_check CHECK (
    status NOT IN ('processing', 'processed') OR processing_request_id IS NOT NULL
  ),
  CONSTRAINT media_assets_deleted_consistency_check CHECK (
    status <> 'deleted' OR deleted_at IS NOT NULL
  )
);

CREATE INDEX media_assets_user_created_idx
  ON public.media_assets (user_id, created_at DESC);
CREATE INDEX media_assets_processing_idx
  ON public.media_assets (status, updated_at)
  WHERE status IN ('uploaded', 'processing', 'failed');
CREATE INDEX media_assets_retention_idx
  ON public.media_assets (retention_until)
  WHERE retention_until IS NOT NULL AND deleted_at IS NULL;

CREATE OR REPLACE FUNCTION private.enforce_media_asset_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  IF NEW.status <> OLD.status AND NOT (
    (OLD.status = 'pending_upload' AND NEW.status IN ('uploaded', 'failed', 'deleted'))
    OR (OLD.status = 'uploaded' AND NEW.status IN ('processing', 'failed', 'deleted'))
    OR (OLD.status = 'processing' AND NEW.status IN ('processed', 'failed', 'deleted'))
    OR (
      OLD.status = 'failed'
      AND OLD.failure_stage = 'processing'
      AND NEW.status IN ('processing', 'deleted')
    )
    OR (OLD.status = 'processed' AND NEW.status = 'deleted')
  ) THEN
    RAISE EXCEPTION 'invalid media asset status transition: % -> %', OLD.status, NEW.status
      USING ERRCODE = '23514';
  END IF;

  IF NEW.status = 'processing' THEN
    NEW.failure_stage := NULL;
    NEW.failure_code := NULL;
  END IF;

  IF NEW.status = 'deleted' AND NEW.deleted_at IS NULL THEN
    NEW.deleted_at := clock_timestamp();
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_media_asset_transition
  BEFORE UPDATE ON public.media_assets
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_media_asset_transition();

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.media_assets FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id,
  user_id,
  kind,
  mime_type,
  declared_size_bytes,
  actual_size_bytes,
  status,
  failure_stage,
  failure_code,
  retention_until,
  uploaded_at,
  processed_at,
  deleted_at,
  created_at,
  updated_at
) ON TABLE public.media_assets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.media_assets TO service_role;

CREATE POLICY media_assets_patient_own_read
  ON public.media_assets
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.users domain_user
      WHERE domain_user.id = media_assets.user_id
        AND domain_user.auth_user_id = (SELECT auth.uid())
    )
  );

CREATE OR REPLACE FUNCTION public.claim_media_asset_processing(
  p_asset_id uuid,
  p_user_id uuid,
  p_request_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_asset public.media_assets%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_request_id !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid media processing request id' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_asset
  FROM public.media_assets
  WHERE id = p_asset_id
    AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND OR v_asset.status IN ('pending_upload', 'processed', 'deleted') THEN
    RETURN NULL;
  END IF;

  IF v_asset.status = 'processing'
    AND v_asset.processing_request_id IS DISTINCT FROM p_request_id THEN
    RETURN NULL;
  END IF;

  IF v_asset.status = 'failed'
    AND v_asset.failure_stage <> 'processing' THEN
    RETURN NULL;
  END IF;

  IF v_asset.status IN ('uploaded', 'failed') THEN
    UPDATE public.media_assets
    SET status = 'processing',
        processing_request_id = p_request_id,
        processing_result = NULL,
        processed_at = NULL
    WHERE id = v_asset.id
    RETURNING * INTO v_asset;
  END IF;

  RETURN jsonb_build_object(
    'id', v_asset.id,
    'user_id', v_asset.user_id,
    'kind', v_asset.kind,
    'bucket_id', v_asset.bucket_id,
    'object_path', v_asset.object_path,
    'mime_type', v_asset.mime_type,
    'context_text', v_asset.context_text,
    'status', v_asset.status,
    'processing_request_id', v_asset.processing_request_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_media_asset_processing(
  p_asset_id uuid,
  p_user_id uuid,
  p_request_id text,
  p_result jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.media_assets
  SET status = 'processed',
      processing_result = p_result,
      processed_at = clock_timestamp()
  WHERE id = p_asset_id
    AND user_id = p_user_id
    AND status = 'processing'
    AND processing_request_id = p_request_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_media_asset_processing(
  p_asset_id uuid,
  p_user_id uuid,
  p_request_id text,
  p_failure_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.media_assets
  SET status = 'failed',
      failure_stage = 'processing',
      failure_code = left(p_failure_code, 100)
  WHERE id = p_asset_id
    AND user_id = p_user_id
    AND status = 'processing'
    AND processing_request_id = p_request_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_media_asset_processing(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_media_asset_processing(uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fail_media_asset_processing(uuid, uuid, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_media_asset_processing(uuid, uuid, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_media_asset_processing(uuid, uuid, text, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_media_asset_processing(uuid, uuid, text, text)
  TO service_role;

REVOKE ALL ON FUNCTION private.enforce_media_asset_transition()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.enforce_media_asset_transition()
  TO service_role;

COMMENT ON TABLE public.media_assets IS
  'Canonical ownership, lifecycle and retention catalog for private BodyFlow app media.';
COMMENT ON COLUMN public.media_assets.context_text IS
  'Optional patient caption processed with the media as one context; never emitted in Inngest events.';
COMMENT ON COLUMN public.media_assets.source_request_hash IS
  'SHA-256 of the mobile idempotency key; raw request keys are not retained here.';
COMMENT ON COLUMN public.media_assets.processing_result IS
  'Private provider output for the owning patient workflow; never exposed through public Storage URLs.';

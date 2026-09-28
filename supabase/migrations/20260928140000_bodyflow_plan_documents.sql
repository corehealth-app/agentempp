-- M3 — plan documents: the photo or PDF of a plan the patient already has,
-- sent to become a draft (never a plan by itself; see plan_drafts).
--
-- A private bucket of its own, a media kind of its own, and no automatic
-- retention date: how long these documents are kept is a data-policy
-- decision that has not been taken, so nothing here deletes them on a timer.
-- The patient removes a document with the existing media deletion.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'plan-documents',
  'plan-documents',
  false,
  20971520,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

ALTER TABLE public.media_assets
  DROP CONSTRAINT media_assets_kind_check,
  DROP CONSTRAINT media_assets_bucket_kind_check,
  DROP CONSTRAINT media_assets_mime_kind_check,
  DROP CONSTRAINT media_assets_size_check,
  DROP CONSTRAINT media_assets_retention_check;

ALTER TABLE public.media_assets
  ADD CONSTRAINT media_assets_kind_check CHECK (
    kind IN (
      'meal_photo',
      'body_checkin_photo',
      'gym_photo',
      'audio_note',
      'content_cover',
      'plan_document'
    )
  ),
  ADD CONSTRAINT media_assets_bucket_kind_check CHECK (
    (kind = 'meal_photo' AND bucket_id = 'meal-photos')
    OR (kind = 'body_checkin_photo' AND bucket_id = 'body-checkin-photos')
    OR (kind = 'gym_photo' AND bucket_id = 'gym-photos')
    OR (kind = 'audio_note' AND bucket_id = 'audio-notes')
    OR (kind = 'content_cover' AND bucket_id = 'content-covers')
    OR (kind = 'plan_document' AND bucket_id = 'plan-documents')
  ),
  ADD CONSTRAINT media_assets_mime_kind_check CHECK (
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
    OR (
      kind = 'plan_document'
      AND mime_type IN (
        'application/pdf',
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/heif'
      )
    )
  ),
  ADD CONSTRAINT media_assets_size_check CHECK (
    declared_size_bytes > 0
    AND (
      (kind IN ('meal_photo', 'body_checkin_photo', 'gym_photo') AND declared_size_bytes <= 15728640)
      OR (kind = 'audio_note' AND declared_size_bytes <= 26214400)
      OR (kind = 'content_cover' AND declared_size_bytes <= 10485760)
      OR (kind = 'plan_document' AND declared_size_bytes <= 20971520)
    )
    AND (actual_size_bytes IS NULL OR actual_size_bytes = declared_size_bytes)
  ),
  ADD CONSTRAINT media_assets_retention_check CHECK (
    kind IN ('content_cover', 'plan_document') OR retention_until IS NOT NULL
  );

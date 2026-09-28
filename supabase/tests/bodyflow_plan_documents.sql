BEGIN;

INSERT INTO public.users (id, email, wpp, name, status)
VALUES ('00000000-0000-0000-0000-00000000d511', 'plan-doc@example.com', NULL, 'Plan Document Patient', 'active');

DO $test$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-00000000d511';
  v_bucket record;
  v_failed boolean;
  v_case record;
BEGIN
  SELECT * INTO v_bucket FROM storage.buckets WHERE id = 'plan-documents';
  IF NOT FOUND
    OR v_bucket.public
    OR v_bucket.file_size_limit <> 20971520
    OR NOT ('application/pdf' = ANY(v_bucket.allowed_mime_types))
    OR 'image/svg+xml' = ANY(v_bucket.allowed_mime_types)
    OR 'text/html' = ANY(v_bucket.allowed_mime_types) THEN
    RAISE EXCEPTION 'plan-documents bucket is wrong: %', v_bucket;
  END IF;

  -- No storage policy opens the bucket to clients.
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND (qual ILIKE '%plan-documents%' OR with_check ILIKE '%plan-documents%')
  ) THEN
    RAISE EXCEPTION 'a client storage policy reaches plan-documents';
  END IF;

  -- A PDF and a photo of a plan are accepted, without a retention date.
  INSERT INTO public.media_assets (
    id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
    status, source_request_hash, retention_until
  ) VALUES
    ('00000000-0000-0000-0000-00000000d521', v_user, 'plan_document', 'plan-documents',
     v_user::text || '/00000000-0000-0000-0000-00000000d521.pdf',
     'application/pdf', 20971520, 'pending_upload', repeat('1', 64), NULL),
    ('00000000-0000-0000-0000-00000000d522', v_user, 'plan_document', 'plan-documents',
     v_user::text || '/00000000-0000-0000-0000-00000000d522.jpg',
     'image/jpeg', 1024, 'pending_upload', repeat('2', 64), NULL);

  -- A plan document never carries a retention date: the retention job
  -- removes whatever is past its date.
  v_failed := false;
  BEGIN
    INSERT INTO public.media_assets (
      id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
      status, source_request_hash, retention_until
    ) VALUES (
      '00000000-0000-0000-0000-00000000d528', v_user, 'plan_document', 'plan-documents',
      v_user::text || '/00000000-0000-0000-0000-00000000d528.pdf',
      'application/pdf', 1024, 'pending_upload', repeat('8', 64), now() + interval '90 days'
    );
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'plan document accepted a retention date'; END IF;

  -- Everything else about a plan document is refused.
  FOR v_case IN
    SELECT * FROM (VALUES
      ('too large', 'plan_document', 'plan-documents', 'application/pdf', 20971521::bigint, 'pdf'),
      ('wrong bucket', 'plan_document', 'meal-photos', 'image/jpeg', 1024::bigint, 'jpg'),
      ('audio as document', 'plan_document', 'plan-documents', 'audio/mp4', 1024::bigint, 'm4a'),
      ('html as document', 'plan_document', 'plan-documents', 'text/html', 1024::bigint, 'html'),
      ('pdf as meal photo', 'meal_photo', 'meal-photos', 'application/pdf', 1024::bigint, 'pdf'),
      ('meal photo in the document bucket', 'meal_photo', 'plan-documents', 'image/jpeg', 1024::bigint, 'jpg')
    ) AS t(label, kind, bucket, mime, size, ext)
  LOOP
    v_failed := false;
    BEGIN
      INSERT INTO public.media_assets (
        id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
        status, source_request_hash, retention_until
      ) VALUES (
        '00000000-0000-0000-0000-00000000d529', v_user, v_case.kind, v_case.bucket,
        v_user::text || '/00000000-0000-0000-0000-00000000d529.' || v_case.ext,
        v_case.mime, v_case.size, 'pending_upload', repeat('9', 64),
        -- Each kind with the retention its own rule asks for, so the refusal
        -- comes from the rule under test.
        CASE WHEN v_case.kind = 'plan_document' THEN NULL ELSE now() + interval '30 days' END
      );
    EXCEPTION WHEN check_violation THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN
      RAISE EXCEPTION 'accepted: %', v_case.label;
    END IF;
  END LOOP;

  -- The existing kinds keep their rules: a meal photo still needs a
  -- retention date and still accepts what it accepted.
  v_failed := false;
  BEGIN
    INSERT INTO public.media_assets (
      id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
      status, source_request_hash, retention_until
    ) VALUES (
      '00000000-0000-0000-0000-00000000d523', v_user, 'meal_photo', 'meal-photos',
      v_user::text || '/00000000-0000-0000-0000-00000000d523.jpg',
      'image/jpeg', 1024, 'pending_upload', repeat('3', 64), NULL
    );
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'meal photo accepted without retention'; END IF;

  INSERT INTO public.media_assets (
    id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
    status, source_request_hash, retention_until
  ) VALUES
    ('00000000-0000-0000-0000-00000000d524', v_user, 'meal_photo', 'meal-photos',
     v_user::text || '/00000000-0000-0000-0000-00000000d524.jpg',
     'image/jpeg', 15728640, 'pending_upload', repeat('4', 64), now() + interval '30 days'),
    ('00000000-0000-0000-0000-00000000d525', v_user, 'audio_note', 'audio-notes',
     v_user::text || '/00000000-0000-0000-0000-00000000d525.m4a',
     'audio/mp4', 26214400, 'pending_upload', repeat('5', 64), now() + interval '30 days');
END;
$test$;

ROLLBACK;

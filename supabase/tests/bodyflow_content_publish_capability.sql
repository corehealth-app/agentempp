-- Locks 20260930120000_content_editor_publish_capability: the editorial owner
-- (content_editor with can_publish_content) writes, submits and publishes; an
-- independent nutrition_admin reviews; nobody else publishes. Synthetic
-- identities only; everything is rolled back.
BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_owner_id constant uuid := '00000000-0000-0000-0000-000000000991';
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000000992';
  v_reviewer_id constant uuid := '00000000-0000-0000-0000-000000000993';
  v_support_id constant uuid := '00000000-0000-0000-0000-000000000994';
  v_result jsonb;
  v_publication_id uuid;
  v_version_id uuid;
  v_updated_at timestamptz;
  v_body text := '## Publish capability' || E'\n\n' || repeat('word ', 205);
  v_draft jsonb;
BEGIN
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous
  ) VALUES
    (v_owner_id, 'authenticated', 'authenticated', 'cms-owner@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_editor_id, 'authenticated', 'authenticated', 'cms-plain-editor@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_reviewer_id, 'authenticated', 'authenticated', 'cms-reviewer@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_support_id, 'authenticated', 'authenticated', 'cms-support@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

  INSERT INTO public.admin_users (id, email, role, can_publish_content) VALUES
    (v_owner_id, 'cms-owner@example.com', 'content_editor', true),
    (v_editor_id, 'cms-plain-editor@example.com', 'content_editor', false),
    (v_reviewer_id, 'cms-reviewer@example.com', 'nutrition_admin', false),
    (v_support_id, 'cms-support@example.com', 'support', false);

  -- The capability belongs to content_editor only.
  BEGIN
    UPDATE public.admin_users SET can_publish_content = true WHERE id = v_reviewer_id;
    RAISE EXCEPTION 'a nutrition_admin was given the publish capability';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.admin_users SET role = 'nutrition_admin' WHERE id = v_owner_id;
    RAISE EXCEPTION 'an editor with the capability became a reviewer';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  v_draft := jsonb_build_object(
    'locale', 'pt-BR', 'category', 'nutrition',
    'title', 'Publish capability guide',
    'excerpt', 'A synthetic excerpt for the publish capability regression.',
    'bodyMarkdown', v_body, 'tags', '[]'::jsonb, 'featuredToday', false,
    'coverAssetId', NULL,
    'targeting', jsonb_build_object('protocols', '[]'::jsonb, 'plans', '[]'::jsonb, 'personalities', '[]'::jsonb)
  );

  -- 1. The owner creates and submits.
  v_result := public.create_content_publication(v_owner_id, 'synthetic-publish-capability');
  v_publication_id := (v_result->>'publication_id')::uuid;
  v_result := public.create_content_draft(v_owner_id, v_publication_id, 'pt-BR');
  v_version_id := (v_result->>'version_id')::uuid;
  v_updated_at := (v_result->>'updated_at')::timestamptz;
  v_result := public.save_content_draft(v_owner_id, v_version_id, v_updated_at, v_draft);
  v_updated_at := (v_result->>'updated_at')::timestamptz;
  PERFORM public.submit_content_version(v_owner_id, v_version_id, v_updated_at);

  -- 6. Publishing before review fails, even for the owner.
  BEGIN
    PERFORM public.publish_content_version(v_owner_id, v_version_id, NULL);
    RAISE EXCEPTION 'an in_review version was published';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 2. The owner cannot review.
  BEGIN
    PERFORM public.review_content_version(v_owner_id, v_version_id, 'approve', NULL);
    RAISE EXCEPTION 'the owner reviewed their own content';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- 3. The independent reviewer approves.
  PERFORM public.review_content_version(v_reviewer_id, v_version_id, 'approve', NULL);

  -- 4. The reviewer cannot publish; 7. nor a plain editor or a support admin.
  BEGIN
    PERFORM public.publish_content_version(v_reviewer_id, v_version_id, NULL);
    RAISE EXCEPTION 'the reviewer published';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.publish_content_version(v_editor_id, v_version_id, NULL);
    RAISE EXCEPTION 'an editor without the capability published';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.publish_content_version(v_support_id, v_version_id, NULL);
    RAISE EXCEPTION 'a support admin published';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- A direct write naming a publisher without the capability is refused by
  -- the trigger, not only by the RPC.
  BEGIN
    UPDATE public.content_versions
    SET published_by = v_editor_id, published_at = now(), publish_at = now()
    WHERE id = v_version_id;
    RAISE EXCEPTION 'a direct write published through an editor without the capability';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 5. The owner publishes after review; the audit names the owner.
  PERFORM public.publish_content_version(v_owner_id, v_version_id, NULL);
  IF NOT EXISTS (
    SELECT 1 FROM public.content_versions
    WHERE id = v_version_id AND authored_by = v_owner_id
      AND reviewed_by = v_reviewer_id AND published_by = v_owner_id
  ) OR NOT EXISTS (
    SELECT 1 FROM public.audit_log
    WHERE entity = 'content_version' AND entity_id = v_version_id::text
      AND actor_id = v_owner_id AND action = 'content.version.publish'
  ) THEN
    RAISE EXCEPTION 'owner publication was not recorded with the right actors';
  END IF;
END;
$test$;

RESET ROLE;

ROLLBACK;

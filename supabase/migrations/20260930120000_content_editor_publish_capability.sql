-- Content publication capability for a content_editor (staging-first).
--
-- The CMS keeps one role per admin: content_editor writes and submits,
-- nutrition_admin reviews (never the author: content_versions_review_pair_check),
-- master_admin publishes and archives. A programme where the same real person
-- is the editorial owner and the publisher (Performe AI evaluation: Dr. Roberto
-- Menescal writes and publishes, Eduardo reviews independently) could only be
-- represented by making that person master_admin, which also grants patient
-- support and operations powers. This migration adds the narrow capability
-- instead: a content_editor with can_publish_content may publish an APPROVED
-- version (review stays mandatory and independent). Archive stays master_admin.
--
-- Unchanged: authorship (authored_by must be content_editor), review
-- (reviewed_by must be nutrition_admin and differ from authored_by), audit log
-- actor ids, RPC grants (service_role only), admin_users RLS (no
-- authenticated writes). The flag can only be set by service_role / SQL.

ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS can_publish_content boolean NOT NULL DEFAULT false;

ALTER TABLE public.admin_users
  DROP CONSTRAINT IF EXISTS admin_users_publish_capability_role_check;
ALTER TABLE public.admin_users
  ADD CONSTRAINT admin_users_publish_capability_role_check
  CHECK (NOT can_publish_content OR role = 'content_editor');

CREATE OR REPLACE FUNCTION private.is_content_publisher(p_actor_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND (
        admin_user.role = 'master_admin'
        OR (admin_user.role = 'content_editor' AND admin_user.can_publish_content)
      )
  );
$$;

REVOKE ALL ON FUNCTION private.is_content_publisher(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.is_content_publisher(uuid) TO service_role;

CREATE OR REPLACE FUNCTION private.prepare_content_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_word_count integer;
  v_parent_counter integer;
  v_parent_archived_at timestamptz;
  v_snapshot_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'draft'
      OR NEW.submitted_at IS NOT NULL
      OR NEW.reviewed_by IS NOT NULL
      OR NEW.reviewed_at IS NOT NULL
      OR NEW.rejection_reason IS NOT NULL
      OR NEW.published_by IS NOT NULL
      OR NEW.published_at IS NOT NULL
      OR NEW.publish_at IS NOT NULL THEN
      RAISE EXCEPTION 'content versions must begin as clean drafts'
        USING ERRCODE = '23514';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.admin_users admin_user
      WHERE admin_user.id = NEW.authored_by
        AND admin_user.role = 'content_editor'
    ) THEN
      RAISE EXCEPTION 'content version author must be a content_editor'
        USING ERRCODE = '23514';
    END IF;

    SELECT publication.version_counter, publication.archived_at
    INTO v_parent_counter, v_parent_archived_at
    FROM public.content_publications publication
    WHERE publication.id = NEW.publication_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'content publication not found' USING ERRCODE = '23503';
    END IF;
    IF v_parent_archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'archived content publication cannot accept versions'
        USING ERRCODE = '23514';
    END IF;
    IF NEW.version <> v_parent_counter + 1 THEN
      RAISE EXCEPTION 'content version number must be the next publication revision'
        USING ERRCODE = '23514';
    END IF;

    UPDATE public.content_publications
    SET version_counter = NEW.version
    WHERE id = NEW.publication_id;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.publication_id IS DISTINCT FROM OLD.publication_id
      OR NEW.version IS DISTINCT FROM OLD.version
      OR NEW.locale IS DISTINCT FROM OLD.locale
      OR NEW.authored_by IS DISTINCT FROM OLD.authored_by
      OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'content version identity is immutable' USING ERRCODE = '23514';
    END IF;

    v_snapshot_changed := (
      NEW.category IS DISTINCT FROM OLD.category
      OR NEW.title IS DISTINCT FROM OLD.title
      OR NEW.excerpt IS DISTINCT FROM OLD.excerpt
      OR NEW.body_markdown IS DISTINCT FROM OLD.body_markdown
      OR NEW.body_hash IS DISTINCT FROM OLD.body_hash
      OR NEW.reading_time_minutes IS DISTINCT FROM OLD.reading_time_minutes
      OR NEW.tags IS DISTINCT FROM OLD.tags
      OR NEW.featured_today IS DISTINCT FROM OLD.featured_today
      OR NEW.cover_asset_id IS DISTINCT FROM OLD.cover_asset_id
    );

    IF OLD.state = 'draft' THEN
      IF NEW.state = 'draft' THEN
        NULL;
      ELSIF NEW.state = 'in_review' THEN
        IF v_snapshot_changed
          OR OLD.submitted_at IS NOT NULL
          OR NEW.submitted_at IS NULL
          OR NEW.reviewed_by IS NOT NULL
          OR NEW.reviewed_at IS NOT NULL
          OR NEW.rejection_reason IS NOT NULL
          OR NEW.published_by IS NOT NULL
          OR NEW.published_at IS NOT NULL
          OR NEW.publish_at IS NOT NULL
          OR NOT EXISTS (
            SELECT 1
            FROM public.admin_users admin_user
            WHERE admin_user.id = NEW.authored_by
              AND admin_user.role = 'content_editor'
          ) THEN
          RAISE EXCEPTION 'draft submission has invalid lifecycle metadata or actor role'
            USING ERRCODE = '23514';
        END IF;
      ELSE
        RAISE EXCEPTION 'invalid content version state transition: % -> %', OLD.state, NEW.state
          USING ERRCODE = '23514';
      END IF;
    ELSIF OLD.state = 'in_review' THEN
      IF v_snapshot_changed
        OR NEW.state NOT IN ('approved', 'rejected')
        OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
        OR NEW.reviewed_by IS NULL
        OR NEW.reviewed_at IS NULL
        OR NEW.reviewed_by = NEW.authored_by
        OR NEW.published_by IS NOT NULL
        OR NEW.published_at IS NOT NULL
        OR NEW.publish_at IS NOT NULL
        OR NOT EXISTS (
          SELECT 1
          FROM public.admin_users admin_user
          WHERE admin_user.id = NEW.reviewed_by
            AND admin_user.role = 'nutrition_admin'
        ) THEN
        RAISE EXCEPTION 'technical review has invalid lifecycle metadata or actor role'
          USING ERRCODE = '23514';
      END IF;
    ELSIF OLD.state = 'approved' THEN
      IF v_snapshot_changed
        OR NEW.state <> OLD.state
        OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
        OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
        OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
        OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
        OR OLD.published_by IS NOT NULL
        OR OLD.published_at IS NOT NULL
        OR OLD.publish_at IS NOT NULL
        OR NEW.published_by IS NULL
        OR NEW.published_at IS NULL
        OR NEW.publish_at IS NULL
        OR NOT (
          NEW.publish_at <= NEW.published_at
          OR NEW.publish_at >= NEW.published_at + interval '5 minutes'
        )
        OR NOT private.is_content_publisher(NEW.published_by) THEN
        RAISE EXCEPTION 'publication scheduling has invalid lifecycle metadata or actor role'
          USING ERRCODE = '23514';
      END IF;
    ELSE
      RAISE EXCEPTION 'rejected content versions are immutable' USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.body_markdown IS NULL THEN
    NEW.body_hash := NULL;
    NEW.reading_time_minutes := NULL;
  ELSE
    NEW.body_hash := encode(
      extensions.digest(convert_to(NEW.body_markdown, 'UTF8'), 'sha256'),
      'hex'
    );
    SELECT count(*)
    INTO v_word_count
    FROM regexp_matches(NEW.body_markdown, '[[:alnum:]]+', 'g');
    NEW.reading_time_minutes := greatest(1, ceil(v_word_count::numeric / 200)::integer);
  END IF;

  IF cardinality(NEW.tags) <> (
    SELECT count(DISTINCT tag)
    FROM unnest(NEW.tags) tag
  ) OR EXISTS (
    SELECT 1
    FROM unnest(NEW.tags) tag
    WHERE tag !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      OR char_length(tag) > 40
  ) THEN
    RAISE EXCEPTION 'content tags must be unique normalized slugs' USING ERRCODE = '23514';
  END IF;

  IF NEW.state <> 'draft' AND (
    NEW.category IS NULL
    OR NEW.title IS NULL
    OR NEW.excerpt IS NULL
    OR NEW.body_markdown IS NULL
    OR NEW.body_hash IS NULL
    OR NEW.reading_time_minutes IS NULL
    OR NEW.submitted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'submitted content versions require a complete snapshot'
      USING ERRCODE = '23514';
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_content_version(
  p_actor_id uuid,
  p_version_id uuid,
  p_publish_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_version public.content_versions%ROWTYPE;
  v_archived_at timestamptz;
  v_now timestamptz := clock_timestamp();
  v_effective_at timestamptz;
  v_effective_state text;
BEGIN
  IF p_actor_id IS NULL OR NOT private.is_content_publisher(p_actor_id) THEN
    RAISE EXCEPTION 'content publisher actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_version_id IS NULL THEN
    RAISE EXCEPTION 'content version is required' USING ERRCODE = '22023';
  END IF;

  IF p_publish_at IS NULL THEN
    v_effective_at := v_now;
    v_effective_state := 'published';
  ELSE
    IF p_publish_at < v_now + interval '5 minutes' THEN
      RAISE EXCEPTION 'scheduled publication must be at least five minutes in the future'
        USING ERRCODE = '22023';
    END IF;
    v_effective_at := p_publish_at;
    v_effective_state := 'scheduled';
  END IF;

  SELECT version.*
  INTO v_version
  FROM public.content_versions version
  WHERE version.id = p_version_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'content version not found' USING ERRCODE = '23503';
  END IF;
  SELECT publication.archived_at
  INTO v_archived_at
  FROM public.content_publications publication
  WHERE publication.id = v_version.publication_id
  FOR UPDATE;
  IF v_version.state <> 'approved' THEN
    RAISE EXCEPTION 'only approved content can be published' USING ERRCODE = '23514';
  END IF;
  IF v_version.publish_at IS NOT NULL THEN
    RAISE EXCEPTION 'content version is already published or scheduled'
      USING ERRCODE = '23514';
  END IF;
  IF v_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'archived content publication cannot be published'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.content_versions
  SET published_by = p_actor_id,
      published_at = v_now,
      publish_at = v_effective_at
  WHERE id = p_version_id
  RETURNING * INTO v_version;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    CASE WHEN v_effective_state = 'published'
      THEN 'content.version.publish'
      ELSE 'content.version.schedule'
    END,
    'content_version',
    p_version_id::text,
    jsonb_build_object(
      'publication_id', v_version.publication_id,
      'version_id', p_version_id,
      'version', v_version.version,
      'state', v_effective_state,
      'publish_at', v_effective_at,
      'body_hash', v_version.body_hash
    )
  );

  RETURN jsonb_build_object(
    'publication_id', v_version.publication_id,
    'version_id', p_version_id,
    'version', v_version.version,
    'state', v_version.state,
    'effective_state', v_effective_state,
    'publish_at', v_effective_at,
    'body_hash', v_version.body_hash,
    'updated_at', v_version.updated_at
  );
END;
$$;

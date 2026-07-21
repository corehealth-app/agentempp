-- BodyFlow educational content CMS persistence and editorial lifecycle.
-- The existing private content-covers bucket remains owned by Storage.
--
-- Trust boundary: these SECURITY INVOKER RPCs execute as service_role, which
-- also needs direct DML grants for backend repositories. PostgreSQL therefore
-- cannot make RPC use cryptographically exclusive. Every persisted row and
-- legal lifecycle transition is nevertheless validated by constraints and
-- triggers so direct service_role DML cannot create an invalid CMS state.

CREATE TABLE public.content_publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  version_counter integer NOT NULL DEFAULT 0,
  created_by uuid NOT NULL REFERENCES public.admin_users(id) ON DELETE RESTRICT,
  archived_by uuid REFERENCES public.admin_users(id) ON DELETE RESTRICT,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT content_publications_slug_check CHECK (
    slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
    AND char_length(slug) BETWEEN 3 AND 120
  ),
  CONSTRAINT content_publications_version_counter_check CHECK (version_counter >= 0),
  CONSTRAINT content_publications_archive_pair_check CHECK (
    (archived_by IS NULL) = (archived_at IS NULL)
  )
);

CREATE TABLE public.content_assets (
  id uuid PRIMARY KEY,
  bucket_id text NOT NULL DEFAULT 'content-covers',
  object_path text NOT NULL UNIQUE,
  mime_type text NOT NULL,
  declared_size_bytes bigint NOT NULL,
  actual_size_bytes bigint,
  etag text,
  status text NOT NULL DEFAULT 'pending_upload',
  created_by uuid NOT NULL REFERENCES public.admin_users(id) ON DELETE RESTRICT,
  uploaded_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT content_assets_bucket_check CHECK (bucket_id = 'content-covers'),
  CONSTRAINT content_assets_mime_type_check CHECK (
    mime_type IN ('image/jpeg', 'image/png', 'image/webp')
  ),
  CONSTRAINT content_assets_size_check CHECK (
    declared_size_bytes BETWEEN 1 AND 10485760
    AND (actual_size_bytes IS NULL OR actual_size_bytes = declared_size_bytes)
  ),
  CONSTRAINT content_assets_path_check CHECK (
    object_path = 'content/' || id::text || CASE mime_type
      WHEN 'image/jpeg' THEN '.jpg'
      WHEN 'image/png' THEN '.png'
      WHEN 'image/webp' THEN '.webp'
      ELSE ''
    END
  ),
  CONSTRAINT content_assets_status_check CHECK (
    status IN ('pending_upload', 'uploaded', 'deleted')
  ),
  CONSTRAINT content_assets_status_consistency_check CHECK (
    (
      status = 'pending_upload'
      AND actual_size_bytes IS NULL
      AND etag IS NULL
      AND uploaded_at IS NULL
      AND deleted_at IS NULL
    ) OR (
      status = 'uploaded'
      AND actual_size_bytes = declared_size_bytes
      AND char_length(btrim(etag)) BETWEEN 1 AND 512
      AND uploaded_at IS NOT NULL
      AND deleted_at IS NULL
    ) OR (
      status = 'deleted'
      AND deleted_at IS NOT NULL
      AND (
        (
          actual_size_bytes IS NULL
          AND etag IS NULL
          AND uploaded_at IS NULL
        ) OR (
          actual_size_bytes = declared_size_bytes
          AND char_length(btrim(etag)) BETWEEN 1 AND 512
          AND uploaded_at IS NOT NULL
        )
      )
    )
  )
);

CREATE INDEX content_assets_status_idx
  ON public.content_assets (status, updated_at DESC);

CREATE TABLE public.content_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid NOT NULL REFERENCES public.content_publications(id) ON DELETE RESTRICT,
  version integer NOT NULL,
  locale text NOT NULL,
  category text,
  title text,
  excerpt text,
  body_markdown text,
  body_hash text,
  reading_time_minutes integer,
  tags text[] NOT NULL DEFAULT '{}'::text[],
  featured_today boolean NOT NULL DEFAULT false,
  cover_asset_id uuid REFERENCES public.content_assets(id) ON DELETE RESTRICT,
  state text NOT NULL DEFAULT 'draft',
  authored_by uuid NOT NULL REFERENCES public.admin_users(id) ON DELETE RESTRICT,
  submitted_at timestamptz,
  reviewed_by uuid REFERENCES public.admin_users(id) ON DELETE RESTRICT,
  reviewed_at timestamptz,
  rejection_reason text,
  published_by uuid REFERENCES public.admin_users(id) ON DELETE RESTRICT,
  published_at timestamptz,
  publish_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT content_versions_publication_version_key UNIQUE (publication_id, version),
  CONSTRAINT content_versions_id_publication_key UNIQUE (id, publication_id),
  CONSTRAINT content_versions_version_check CHECK (version > 0),
  CONSTRAINT content_versions_locale_check CHECK (locale IN ('pt-BR', 'en-US')),
  CONSTRAINT content_versions_state_check CHECK (
    state IN ('draft', 'in_review', 'approved', 'rejected')
  ),
  CONSTRAINT content_versions_category_check CHECK (
    category IS NULL OR category IN (
      'weight_loss',
      'hypertrophy',
      'nutrition',
      'training',
      'neuroscience',
      'habit_formation',
      'cardiovascular_health',
      'hydration',
      'supplementation',
      'sleep',
      'using_bodyflow'
    )
  ),
  CONSTRAINT content_versions_title_check CHECK (
    title IS NULL OR char_length(title) BETWEEN 3 AND 120
  ),
  CONSTRAINT content_versions_excerpt_check CHECK (
    excerpt IS NULL OR char_length(excerpt) BETWEEN 20 AND 280
  ),
  CONSTRAINT content_versions_body_markdown_check CHECK (
    body_markdown IS NULL OR char_length(body_markdown) BETWEEN 100 AND 50000
  ),
  CONSTRAINT content_versions_body_hash_check CHECK (
    body_hash IS NULL OR body_hash ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT content_versions_reading_time_check CHECK (
    reading_time_minutes IS NULL OR reading_time_minutes BETWEEN 1 AND 500
  ),
  CONSTRAINT content_versions_tags_check CHECK (
    cardinality(tags) <= 20 AND array_position(tags, NULL) IS NULL
  ),
  CONSTRAINT content_versions_review_pair_check CHECK (
    (reviewed_by IS NULL) = (reviewed_at IS NULL)
    AND (reviewed_by IS NULL OR reviewed_by <> authored_by)
  ),
  CONSTRAINT content_versions_publish_pair_check CHECK (
    (published_by IS NULL) = (published_at IS NULL)
    AND (published_by IS NULL) = (publish_at IS NULL)
  ),
  CONSTRAINT content_versions_state_metadata_check CHECK (
    (
      state = 'draft'
      AND submitted_at IS NULL
      AND reviewed_by IS NULL
      AND reviewed_at IS NULL
      AND rejection_reason IS NULL
      AND published_by IS NULL
      AND published_at IS NULL
      AND publish_at IS NULL
    ) OR (
      state = 'in_review'
      AND submitted_at IS NOT NULL
      AND reviewed_by IS NULL
      AND reviewed_at IS NULL
      AND rejection_reason IS NULL
      AND published_by IS NULL
      AND published_at IS NULL
      AND publish_at IS NULL
    ) OR (
      state = 'approved'
      AND submitted_at IS NOT NULL
      AND reviewed_by IS NOT NULL
      AND reviewed_at IS NOT NULL
      AND rejection_reason IS NULL
    ) OR (
      state = 'rejected'
      AND submitted_at IS NOT NULL
      AND reviewed_by IS NOT NULL
      AND reviewed_at IS NOT NULL
      AND char_length(btrim(rejection_reason)) BETWEEN 10 AND 1000
      AND published_by IS NULL
      AND published_at IS NULL
      AND publish_at IS NULL
    )
  ),
  CONSTRAINT content_versions_lifecycle_chronology_check CHECK (
    (submitted_at IS NULL OR submitted_at >= created_at)
    AND (reviewed_at IS NULL OR reviewed_at >= submitted_at)
    AND (published_at IS NULL OR published_at >= reviewed_at)
  )
);

CREATE UNIQUE INDEX content_versions_one_draft_per_locale_idx
  ON public.content_versions (publication_id, locale)
  WHERE state = 'draft';

CREATE INDEX content_versions_visibility_idx
  ON public.content_versions (publication_id, locale, publish_at DESC, version DESC)
  WHERE state = 'approved' AND publish_at IS NOT NULL;

CREATE INDEX content_versions_review_queue_idx
  ON public.content_versions (state, submitted_at, id)
  WHERE state = 'in_review';

CREATE INDEX content_versions_cover_asset_idx
  ON public.content_versions (cover_asset_id)
  WHERE cover_asset_id IS NOT NULL;

CREATE TABLE public.content_version_target_protocols (
  content_version_id uuid NOT NULL REFERENCES public.content_versions(id) ON DELETE RESTRICT,
  protocol public.protocol_enum NOT NULL,
  PRIMARY KEY (content_version_id, protocol)
);

CREATE TABLE public.content_version_target_plans (
  content_version_id uuid NOT NULL REFERENCES public.content_versions(id) ON DELETE RESTRICT,
  plan public.plan_enum NOT NULL,
  PRIMARY KEY (content_version_id, plan)
);

CREATE TABLE public.content_version_target_personalities (
  content_version_id uuid NOT NULL REFERENCES public.content_versions(id) ON DELETE RESTRICT,
  personality_code text NOT NULL REFERENCES public.coach_personalities(code) ON DELETE RESTRICT,
  PRIMARY KEY (content_version_id, personality_code)
);

CREATE TABLE public.content_user_state (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  publication_id uuid NOT NULL REFERENCES public.content_publications(id) ON DELETE RESTRICT,
  first_opened_at timestamptz,
  last_opened_at timestamptz,
  last_opened_version_id uuid,
  completed_at timestamptz,
  completed_version_id uuid,
  saved_at timestamptz,
  last_origin text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, publication_id),
  CONSTRAINT content_user_state_last_opened_version_fkey
    FOREIGN KEY (last_opened_version_id, publication_id)
    REFERENCES public.content_versions(id, publication_id) ON DELETE RESTRICT,
  CONSTRAINT content_user_state_completed_version_fkey
    FOREIGN KEY (completed_version_id, publication_id)
    REFERENCES public.content_versions(id, publication_id) ON DELETE RESTRICT,
  CONSTRAINT content_user_state_origin_check CHECK (
    last_origin IS NULL OR last_origin IN ('today', 'library', 'push')
  ),
  CONSTRAINT content_user_state_opened_check CHECK (
    (first_opened_at IS NULL AND last_opened_at IS NULL AND last_opened_version_id IS NULL)
    OR (
      first_opened_at IS NOT NULL
      AND last_opened_at IS NOT NULL
      AND last_opened_version_id IS NOT NULL
      AND first_opened_at <= last_opened_at
    )
  ),
  CONSTRAINT content_user_state_completed_check CHECK (
    (completed_at IS NULL) = (completed_version_id IS NULL)
  )
);

CREATE INDEX content_user_state_saved_idx
  ON public.content_user_state (user_id, saved_at DESC, publication_id)
  WHERE saved_at IS NOT NULL;

CREATE TABLE public.content_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  publication_id uuid NOT NULL REFERENCES public.content_publications(id) ON DELETE RESTRICT,
  content_version_id uuid NOT NULL,
  event_type text NOT NULL,
  origin text NOT NULL,
  event_key_hash text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT content_events_version_fkey
    FOREIGN KEY (content_version_id, publication_id)
    REFERENCES public.content_versions(id, publication_id) ON DELETE RESTRICT,
  CONSTRAINT content_events_user_event_key_key UNIQUE (user_id, event_key_hash),
  CONSTRAINT content_events_type_check CHECK (
    event_type IN ('impression', 'opened', 'completed', 'saved', 'unsaved')
  ),
  CONSTRAINT content_events_origin_check CHECK (
    origin IN ('today', 'library', 'push')
  ),
  CONSTRAINT content_events_key_hash_check CHECK (
    event_key_hash ~ '^[0-9a-f]{64}$'
  )
);

CREATE INDEX content_events_publication_created_idx
  ON public.content_events (publication_id, created_at DESC, id);

CREATE INDEX content_events_user_created_idx
  ON public.content_events (user_id, created_at DESC, id);

CREATE OR REPLACE FUNCTION private.guard_content_publication_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.version_counter <> 0
      OR NEW.archived_by IS NOT NULL
      OR NEW.archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'content publications must begin active with a zero version counter'
        USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.admin_users admin_user
      WHERE admin_user.id = NEW.created_by
        AND admin_user.role = 'content_editor'
    ) THEN
      RAISE EXCEPTION 'content publication creator must be a content_editor'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'content publications cannot be deleted' USING ERRCODE = '23514';
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.slug IS DISTINCT FROM OLD.slug
    OR NEW.created_by IS DISTINCT FROM OLD.created_by
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'content publication identity is immutable' USING ERRCODE = '23514';
  END IF;

  IF NEW.version_counter IS DISTINCT FROM OLD.version_counter AND (
    NEW.version_counter <> OLD.version_counter + 1
    OR pg_trigger_depth() < 2
  ) THEN
    RAISE EXCEPTION 'content publication version counter advances only from a version insert'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.archived_at IS DISTINCT FROM OLD.archived_at
    OR NEW.archived_by IS DISTINCT FROM OLD.archived_by THEN
    IF OLD.archived_at IS NOT NULL
      OR NEW.archived_at IS NULL
      OR NEW.archived_by IS NULL
      OR NEW.version_counter IS DISTINCT FROM OLD.version_counter
      OR NOT EXISTS (
        SELECT 1
        FROM public.admin_users admin_user
        WHERE admin_user.id = NEW.archived_by
          AND admin_user.role = 'master_admin'
      ) THEN
      RAISE EXCEPTION 'content publication archive requires a master_admin and is irreversible'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER guard_content_publication_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.content_publications
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_publication_mutation();

CREATE OR REPLACE FUNCTION private.guard_content_asset_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_object_etag text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending_upload'
      OR NEW.actual_size_bytes IS NOT NULL
      OR NEW.etag IS NOT NULL
      OR NEW.uploaded_at IS NOT NULL
      OR NEW.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'content assets must begin pending upload without lifecycle metadata'
        USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.admin_users admin_user
      WHERE admin_user.id = NEW.created_by
        AND admin_user.role = 'content_editor'
    ) THEN
      RAISE EXCEPTION 'content asset creator must be a content_editor'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'content assets cannot be physically deleted' USING ERRCODE = '23514';
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.bucket_id IS DISTINCT FROM OLD.bucket_id
    OR NEW.object_path IS DISTINCT FROM OLD.object_path
    OR NEW.mime_type IS DISTINCT FROM OLD.mime_type
    OR NEW.declared_size_bytes IS DISTINCT FROM OLD.declared_size_bytes
    OR NEW.created_by IS DISTINCT FROM OLD.created_by
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'content asset identity and declaration are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF OLD.status = 'deleted' THEN
    RAISE EXCEPTION 'deleted content assets are immutable' USING ERRCODE = '23514';
  END IF;

  IF NEW.status = OLD.status THEN
    IF NEW.actual_size_bytes IS DISTINCT FROM OLD.actual_size_bytes
      OR NEW.etag IS DISTINCT FROM OLD.etag
      OR NEW.uploaded_at IS DISTINCT FROM OLD.uploaded_at
      OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
      RAISE EXCEPTION 'content asset lifecycle metadata is immutable without a state transition'
        USING ERRCODE = '23514';
    END IF;
  ELSIF OLD.status = 'pending_upload' AND NEW.status = 'uploaded' THEN
    SELECT object.metadata->>'eTag'
    INTO v_object_etag
    FROM storage.objects object
    WHERE object.bucket_id = OLD.bucket_id
      AND object.name = OLD.object_path
      AND object.metadata->>'mimetype' = OLD.mime_type
      AND CASE
        WHEN object.metadata->>'size' ~ '^[0-9]+$'
          THEN (object.metadata->>'size')::bigint
        ELSE NULL
      END = OLD.declared_size_bytes
      AND char_length(btrim(object.metadata->>'eTag')) BETWEEN 1 AND 512
    FOR SHARE;

    IF NOT FOUND
      OR NEW.actual_size_bytes <> OLD.declared_size_bytes
      OR btrim(NEW.etag) IS DISTINCT FROM btrim(v_object_etag)
      OR NEW.uploaded_at IS NULL
      OR NEW.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'content asset upload transition requires matching Storage metadata'
        USING ERRCODE = '23514';
    END IF;
    NEW.etag := btrim(v_object_etag);
  ELSIF OLD.status = 'pending_upload' AND NEW.status = 'deleted' THEN
    IF NEW.actual_size_bytes IS NOT NULL
      OR NEW.etag IS NOT NULL
      OR NEW.uploaded_at IS NOT NULL
      OR NEW.deleted_at IS NULL THEN
      RAISE EXCEPTION 'pending content asset deletion has invalid lifecycle metadata'
        USING ERRCODE = '23514';
    END IF;
  ELSIF OLD.status = 'uploaded' AND NEW.status = 'deleted' THEN
    IF NEW.actual_size_bytes IS DISTINCT FROM OLD.actual_size_bytes
      OR NEW.etag IS DISTINCT FROM OLD.etag
      OR NEW.uploaded_at IS DISTINCT FROM OLD.uploaded_at
      OR NEW.deleted_at IS NULL THEN
      RAISE EXCEPTION 'uploaded content asset deletion has invalid lifecycle metadata'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid content asset status transition: % -> %', OLD.status, NEW.status
      USING ERRCODE = '23514';
  END IF;

  IF NEW.status = 'deleted' AND EXISTS (
    SELECT 1
    FROM public.content_versions version
    WHERE version.cover_asset_id = OLD.id
  ) THEN
    RAISE EXCEPTION 'referenced content cover cannot be deleted'
      USING ERRCODE = '23514';
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER guard_content_asset_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.content_assets
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_asset_mutation();

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
        OR NOT EXISTS (
          SELECT 1
          FROM public.admin_users admin_user
          WHERE admin_user.id = NEW.published_by
            AND admin_user.role = 'master_admin'
        ) THEN
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

CREATE TRIGGER prepare_content_version_mutation
  BEFORE INSERT OR UPDATE ON public.content_versions
  FOR EACH ROW
  EXECUTE FUNCTION private.prepare_content_version_mutation();

CREATE OR REPLACE FUNCTION private.guard_content_version_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'content versions cannot be deleted' USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER guard_content_version_delete
  BEFORE DELETE ON public.content_versions
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_version_delete();

CREATE OR REPLACE FUNCTION private.validate_content_version_cover()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_asset_status text;
BEGIN
  IF NEW.cover_asset_id IS NOT NULL THEN
    SELECT asset.status
    INTO v_asset_status
    FROM public.content_assets asset
    WHERE asset.id = NEW.cover_asset_id
    FOR SHARE;

    IF NOT FOUND OR v_asset_status <> 'uploaded' THEN
      RAISE EXCEPTION 'content cover must be uploaded before attachment'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_content_version_cover
  BEFORE INSERT OR UPDATE OF cover_asset_id ON public.content_versions
  FOR EACH ROW
  EXECUTE FUNCTION private.validate_content_version_cover();

CREATE OR REPLACE FUNCTION private.guard_content_target_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_version_id uuid := CASE WHEN TG_OP = 'DELETE'
    THEN OLD.content_version_id
    ELSE NEW.content_version_id
  END;
  v_version_state text;
BEGIN
  IF TG_OP = 'UPDATE'
    AND NEW.content_version_id IS DISTINCT FROM OLD.content_version_id THEN
    RAISE EXCEPTION 'content targets cannot be reparented'
      USING ERRCODE = '23514';
  END IF;

  SELECT version.state
  INTO v_version_state
  FROM public.content_versions version
  WHERE version.id = v_version_id
  FOR UPDATE;

  IF NOT FOUND OR v_version_state <> 'draft' THEN
    RAISE EXCEPTION 'content targets are mutable only while their version is a draft'
      USING ERRCODE = '23514';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER guard_content_protocol_target_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.content_version_target_protocols
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_target_mutation();

CREATE TRIGGER guard_content_plan_target_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.content_version_target_plans
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_target_mutation();

CREATE TRIGGER guard_content_personality_target_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.content_version_target_personalities
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_target_mutation();

CREATE OR REPLACE FUNCTION private.validate_content_personality_target()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.coach_personalities personality
    WHERE personality.code = NEW.personality_code
      AND personality.selectable
  ) THEN
    RAISE EXCEPTION 'content personality target must be selectable'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_content_personality_target
  BEFORE INSERT OR UPDATE ON public.content_version_target_personalities
  FOR EACH ROW
  EXECUTE FUNCTION private.validate_content_personality_target();

CREATE OR REPLACE FUNCTION private.touch_content_user_state_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER touch_content_user_state_updated_at
  BEFORE UPDATE ON public.content_user_state
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_content_user_state_updated_at();

CREATE OR REPLACE FUNCTION private.guard_content_events_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'content events are append-only' USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER guard_content_events_immutable
  BEFORE UPDATE OR DELETE ON public.content_events
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_content_events_immutable();

CREATE OR REPLACE FUNCTION public.create_content_publication(
  p_actor_id uuid,
  p_slug text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_publication public.content_publications%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_slug IS NULL
    OR p_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
    OR char_length(p_slug) NOT BETWEEN 3 AND 120 THEN
    RAISE EXCEPTION 'invalid content publication slug' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.content_publications (slug, created_by)
  VALUES (p_slug, p_actor_id)
  RETURNING * INTO v_publication;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.publication.create',
    'content_publication',
    v_publication.id::text,
    jsonb_build_object('publication_id', v_publication.id)
  );

  RETURN jsonb_build_object(
    'publication_id', v_publication.id,
    'slug', v_publication.slug,
    'created_at', v_publication.created_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_content_draft(
  p_actor_id uuid,
  p_publication_id uuid,
  p_locale text,
  p_source_version_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_archived_at timestamptz;
  v_next_version integer;
  v_source public.content_versions%ROWTYPE;
  v_version public.content_versions%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_publication_id IS NULL OR p_locale NOT IN ('pt-BR', 'en-US') THEN
    RAISE EXCEPTION 'valid publication and locale are required' USING ERRCODE = '22023';
  END IF;

  SELECT publication.archived_at, publication.version_counter + 1
  INTO v_archived_at, v_next_version
  FROM public.content_publications publication
  WHERE publication.id = p_publication_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'content publication not found' USING ERRCODE = '23503';
  END IF;
  IF v_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'archived content publication cannot accept drafts'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.content_versions version
    WHERE version.publication_id = p_publication_id
      AND version.locale = p_locale
      AND version.state = 'draft'
  ) THEN
    RAISE EXCEPTION 'a draft already exists for this publication locale'
      USING ERRCODE = '23505';
  END IF;

  IF p_source_version_id IS NOT NULL THEN
    SELECT *
    INTO v_source
    FROM public.content_versions source
    WHERE source.id = p_source_version_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'source content version not found' USING ERRCODE = '23503';
    END IF;
    IF v_source.publication_id <> p_publication_id
      OR v_source.locale <> p_locale
      OR v_source.state NOT IN ('approved', 'rejected') THEN
      RAISE EXCEPTION 'source must be an immutable version of the same publication locale'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF p_source_version_id IS NULL THEN
    INSERT INTO public.content_versions (
      publication_id,
      version,
      locale,
      authored_by
    ) VALUES (
      p_publication_id,
      v_next_version,
      p_locale,
      p_actor_id
    )
    RETURNING * INTO v_version;
  ELSE
    INSERT INTO public.content_versions (
      publication_id,
      version,
      locale,
      category,
      title,
      excerpt,
      body_markdown,
      tags,
      featured_today,
      cover_asset_id,
      authored_by
    ) VALUES (
      p_publication_id,
      v_next_version,
      p_locale,
      v_source.category,
      v_source.title,
      v_source.excerpt,
      v_source.body_markdown,
      v_source.tags,
      v_source.featured_today,
      v_source.cover_asset_id,
      p_actor_id
    )
    RETURNING * INTO v_version;

    INSERT INTO public.content_version_target_protocols (content_version_id, protocol)
    SELECT v_version.id, target.protocol
    FROM public.content_version_target_protocols target
    WHERE target.content_version_id = p_source_version_id;

    INSERT INTO public.content_version_target_plans (content_version_id, plan)
    SELECT v_version.id, target.plan
    FROM public.content_version_target_plans target
    WHERE target.content_version_id = p_source_version_id;

    INSERT INTO public.content_version_target_personalities (
      content_version_id,
      personality_code
    )
    SELECT v_version.id, target.personality_code
    FROM public.content_version_target_personalities target
    WHERE target.content_version_id = p_source_version_id;
  END IF;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.version.create',
    'content_version',
    v_version.id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'publication_id', p_publication_id,
      'version_id', v_version.id,
      'source_version_id', p_source_version_id,
      'version', v_next_version,
      'state', 'draft',
      'body_hash', v_version.body_hash
    ))
  );

  RETURN jsonb_build_object(
    'publication_id', p_publication_id,
    'version_id', v_version.id,
    'version', v_next_version,
    'locale', p_locale,
    'state', 'draft',
    'updated_at', v_version.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.save_content_draft(
  p_actor_id uuid,
  p_version_id uuid,
  p_expected_updated_at timestamptz,
  p_draft jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_version public.content_versions%ROWTYPE;
  v_publication_archived_at timestamptz;
  v_category text;
  v_title text;
  v_excerpt text;
  v_body text;
  v_tags text[];
  v_featured_today boolean;
  v_cover_asset_id uuid;
  v_protocols public.protocol_enum[];
  v_plans public.plan_enum[];
  v_personalities text[];
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_version_id IS NULL OR p_expected_updated_at IS NULL THEN
    RAISE EXCEPTION 'version and expected timestamp are required' USING ERRCODE = '22023';
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
  INTO v_publication_archived_at
  FROM public.content_publications publication
  WHERE publication.id = v_version.publication_id
  FOR UPDATE;
  IF v_version.authored_by <> p_actor_id THEN
    RAISE EXCEPTION 'only the content author may save this draft' USING ERRCODE = '42501';
  END IF;
  IF v_version.state <> 'draft' THEN
    RAISE EXCEPTION 'only draft content can be saved' USING ERRCODE = '23514';
  END IF;
  IF v_publication_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'archived content publication cannot be edited' USING ERRCODE = '23514';
  END IF;
  IF v_version.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'content draft changed since it was loaded' USING ERRCODE = '40001';
  END IF;

  IF jsonb_typeof(p_draft) IS DISTINCT FROM 'object'
    OR NOT (p_draft ?& ARRAY[
      'locale',
      'category',
      'title',
      'excerpt',
      'bodyMarkdown',
      'tags',
      'featuredToday',
      'coverAssetId',
      'targeting'
    ])
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_draft) key
      WHERE key NOT IN (
        'locale',
        'category',
        'title',
        'excerpt',
        'bodyMarkdown',
        'tags',
        'featuredToday',
        'coverAssetId',
        'targeting'
      )
    ) THEN
    RAISE EXCEPTION 'content draft must use the exact supported shape'
      USING ERRCODE = '22023';
  END IF;

  IF jsonb_typeof(p_draft->'locale') <> 'string'
    OR p_draft->>'locale' <> v_version.locale
    OR jsonb_typeof(p_draft->'category') <> 'string'
    OR jsonb_typeof(p_draft->'title') <> 'string'
    OR jsonb_typeof(p_draft->'excerpt') <> 'string'
    OR jsonb_typeof(p_draft->'bodyMarkdown') <> 'string'
    OR jsonb_typeof(p_draft->'tags') <> 'array'
    OR jsonb_typeof(p_draft->'featuredToday') <> 'boolean'
    OR jsonb_typeof(p_draft->'targeting') <> 'object'
    OR (p_draft->'coverAssetId' <> 'null'::jsonb AND jsonb_typeof(p_draft->'coverAssetId') <> 'string') THEN
    RAISE EXCEPTION 'content draft field types or locale are invalid'
      USING ERRCODE = '22023';
  END IF;

  IF NOT ((p_draft->'targeting') ?& ARRAY['protocols', 'plans', 'personalities'])
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_draft->'targeting') key
      WHERE key NOT IN ('protocols', 'plans', 'personalities')
    )
    OR jsonb_typeof(p_draft#>'{targeting,protocols}') <> 'array'
    OR jsonb_typeof(p_draft#>'{targeting,plans}') <> 'array'
    OR jsonb_typeof(p_draft#>'{targeting,personalities}') <> 'array'
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_draft->'tags') value
      WHERE jsonb_typeof(value) <> 'string'
    )
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_draft#>'{targeting,protocols}') value
      WHERE jsonb_typeof(value) <> 'string'
    )
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_draft#>'{targeting,plans}') value
      WHERE jsonb_typeof(value) <> 'string'
    )
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_draft#>'{targeting,personalities}') value
      WHERE jsonb_typeof(value) <> 'string'
    ) THEN
    RAISE EXCEPTION 'content targets and tags must be string arrays'
      USING ERRCODE = '22023';
  END IF;

  v_category := p_draft->>'category';
  v_title := btrim(p_draft->>'title');
  v_excerpt := btrim(p_draft->>'excerpt');
  v_body := p_draft->>'bodyMarkdown';
  v_featured_today := (p_draft->>'featuredToday')::boolean;

  SELECT COALESCE(array_agg(value ORDER BY ordinal), '{}'::text[])
  INTO v_tags
  FROM jsonb_array_elements_text(p_draft->'tags') WITH ORDINALITY tags(value, ordinal);

  IF cardinality(v_tags) > 20
    OR cardinality(v_tags) <> (SELECT count(DISTINCT tag) FROM unnest(v_tags) tag)
    OR EXISTS (
      SELECT 1
      FROM unnest(v_tags) tag
      WHERE tag !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        OR char_length(tag) > 40
    ) THEN
    RAISE EXCEPTION 'content tags must be unique normalized slugs'
      USING ERRCODE = '22023';
  END IF;

  BEGIN
    SELECT COALESCE(array_agg(value::public.protocol_enum), '{}'::public.protocol_enum[])
    INTO v_protocols
    FROM jsonb_array_elements_text(p_draft#>'{targeting,protocols}') value;

    SELECT COALESCE(array_agg(value::public.plan_enum), '{}'::public.plan_enum[])
    INTO v_plans
    FROM jsonb_array_elements_text(p_draft#>'{targeting,plans}') value;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'invalid content protocol or plan target' USING ERRCODE = '22023';
  END;

  SELECT COALESCE(array_agg(value), '{}'::text[])
  INTO v_personalities
  FROM jsonb_array_elements_text(p_draft#>'{targeting,personalities}') value;

  IF cardinality(v_protocols) > 3
    OR cardinality(v_protocols) <> (SELECT count(DISTINCT target) FROM unnest(v_protocols) target)
    OR cardinality(v_plans) > 3
    OR cardinality(v_plans) <> (SELECT count(DISTINCT target) FROM unnest(v_plans) target)
    OR cardinality(v_personalities) > 3
    OR cardinality(v_personalities) <> (
      SELECT count(DISTINCT target) FROM unnest(v_personalities) target
    ) THEN
    RAISE EXCEPTION 'content targets must be unique and bounded' USING ERRCODE = '22023';
  END IF;

  IF p_draft->'coverAssetId' = 'null'::jsonb THEN
    v_cover_asset_id := NULL;
  ELSE
    BEGIN
      v_cover_asset_id := (p_draft->>'coverAssetId')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'cover asset id must be a UUID' USING ERRCODE = '22023';
    END;
  END IF;

  UPDATE public.content_versions
  SET category = v_category,
      title = v_title,
      excerpt = v_excerpt,
      body_markdown = v_body,
      tags = v_tags,
      featured_today = v_featured_today,
      cover_asset_id = v_cover_asset_id
  WHERE id = p_version_id
  RETURNING * INTO v_version;

  DELETE FROM public.content_version_target_protocols
  WHERE content_version_id = p_version_id;
  DELETE FROM public.content_version_target_plans
  WHERE content_version_id = p_version_id;
  DELETE FROM public.content_version_target_personalities
  WHERE content_version_id = p_version_id;

  INSERT INTO public.content_version_target_protocols (content_version_id, protocol)
  SELECT p_version_id, target FROM unnest(v_protocols) target;
  INSERT INTO public.content_version_target_plans (content_version_id, plan)
  SELECT p_version_id, target FROM unnest(v_plans) target;
  INSERT INTO public.content_version_target_personalities (
    content_version_id,
    personality_code
  )
  SELECT p_version_id, target FROM unnest(v_personalities) target;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.version.save',
    'content_version',
    p_version_id::text,
    jsonb_build_object(
      'publication_id', v_version.publication_id,
      'version_id', p_version_id,
      'version', v_version.version,
      'state', v_version.state,
      'body_hash', v_version.body_hash
    )
  );

  RETURN jsonb_build_object(
    'publication_id', v_version.publication_id,
    'version_id', p_version_id,
    'version', v_version.version,
    'state', v_version.state,
    'body_hash', v_version.body_hash,
    'reading_time_minutes', v_version.reading_time_minutes,
    'updated_at', v_version.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_content_version(
  p_actor_id uuid,
  p_version_id uuid,
  p_expected_updated_at timestamptz
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
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_version_id IS NULL OR p_expected_updated_at IS NULL THEN
    RAISE EXCEPTION 'version and expected timestamp are required' USING ERRCODE = '22023';
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
  IF v_version.authored_by <> p_actor_id THEN
    RAISE EXCEPTION 'only the content author may submit this version' USING ERRCODE = '42501';
  END IF;
  IF v_version.state <> 'draft' THEN
    RAISE EXCEPTION 'only draft content can be submitted' USING ERRCODE = '23514';
  END IF;
  IF v_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'archived content publication cannot be submitted'
      USING ERRCODE = '23514';
  END IF;
  IF v_version.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'content draft changed since it was loaded' USING ERRCODE = '40001';
  END IF;
  IF v_version.category IS NULL
    OR v_version.title IS NULL
    OR v_version.excerpt IS NULL
    OR v_version.body_markdown IS NULL
    OR v_version.body_hash IS NULL
    OR v_version.reading_time_minutes IS NULL THEN
    RAISE EXCEPTION 'content draft is incomplete' USING ERRCODE = '23514';
  END IF;
  IF v_version.cover_asset_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.content_assets asset
    WHERE asset.id = v_version.cover_asset_id
      AND asset.status = 'uploaded'
  ) THEN
    RAISE EXCEPTION 'content cover is not uploaded' USING ERRCODE = '23514';
  END IF;

  UPDATE public.content_versions
  SET state = 'in_review',
      submitted_at = v_now
  WHERE id = p_version_id
  RETURNING * INTO v_version;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.version.submit',
    'content_version',
    p_version_id::text,
    jsonb_build_object(
      'publication_id', v_version.publication_id,
      'version_id', p_version_id,
      'version', v_version.version,
      'state', 'in_review',
      'body_hash', v_version.body_hash
    )
  );

  RETURN jsonb_build_object(
    'publication_id', v_version.publication_id,
    'version_id', p_version_id,
    'version', v_version.version,
    'state', v_version.state,
    'body_hash', v_version.body_hash,
    'updated_at', v_version.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.review_content_version(
  p_actor_id uuid,
  p_version_id uuid,
  p_decision text,
  p_rejection_reason text DEFAULT NULL
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
  v_next_state text;
  v_reason text;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'nutrition_admin'
  ) THEN
    RAISE EXCEPTION 'nutrition_admin actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_version_id IS NULL OR p_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'valid version and review decision are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_decision = 'reject' THEN
    v_reason := btrim(p_rejection_reason);
    IF v_reason IS NULL OR char_length(v_reason) NOT BETWEEN 10 AND 1000 THEN
      RAISE EXCEPTION 'rejection reason must be between 10 and 1000 characters'
        USING ERRCODE = '22023';
    END IF;
    v_next_state := 'rejected';
  ELSE
    IF p_rejection_reason IS NOT NULL THEN
      RAISE EXCEPTION 'approval cannot include a rejection reason' USING ERRCODE = '22023';
    END IF;
    v_reason := NULL;
    v_next_state := 'approved';
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
  IF v_version.state <> 'in_review' THEN
    RAISE EXCEPTION 'only in-review content can be reviewed' USING ERRCODE = '23514';
  END IF;
  IF v_version.authored_by = p_actor_id THEN
    RAISE EXCEPTION 'content author cannot review their own version'
      USING ERRCODE = '23514';
  END IF;
  IF v_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'archived content publication cannot be reviewed'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.content_versions
  SET state = v_next_state,
      reviewed_by = p_actor_id,
      reviewed_at = v_now,
      rejection_reason = v_reason
  WHERE id = p_version_id
  RETURNING * INTO v_version;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.version.' || p_decision,
    'content_version',
    p_version_id::text,
    jsonb_build_object(
      'publication_id', v_version.publication_id,
      'version_id', p_version_id,
      'version', v_version.version,
      'state', v_next_state,
      'body_hash', v_version.body_hash
    )
  );

  RETURN jsonb_build_object(
    'publication_id', v_version.publication_id,
    'version_id', p_version_id,
    'version', v_version.version,
    'state', v_next_state,
    'body_hash', v_version.body_hash,
    'reviewed_at', v_now,
    'updated_at', v_version.updated_at
  );
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
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'master_admin'
  ) THEN
    RAISE EXCEPTION 'master_admin actor is required' USING ERRCODE = '42501';
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

CREATE OR REPLACE FUNCTION public.archive_content_publication(
  p_actor_id uuid,
  p_publication_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_publication public.content_publications%ROWTYPE;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'master_admin'
  ) THEN
    RAISE EXCEPTION 'master_admin actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_publication_id IS NULL THEN
    RAISE EXCEPTION 'content publication is required' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_publication
  FROM public.content_publications publication
  WHERE publication.id = p_publication_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'content publication not found' USING ERRCODE = '23503';
  END IF;

  IF v_publication.archived_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'outcome', 'already_archived',
      'publication_id', p_publication_id,
      'archived_at', v_publication.archived_at
    );
  END IF;

  UPDATE public.content_publications
  SET archived_by = p_actor_id,
      archived_at = v_now
  WHERE id = p_publication_id
  RETURNING * INTO v_publication;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.publication.archive',
    'content_publication',
    p_publication_id::text,
    jsonb_build_object(
      'publication_id', p_publication_id,
      'state', 'archived'
    )
  );

  RETURN jsonb_build_object(
    'outcome', 'archived',
    'publication_id', p_publication_id,
    'archived_at', v_publication.archived_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_content_asset(
  p_actor_id uuid,
  p_asset_id uuid,
  p_mime_type text,
  p_declared_size_bytes bigint,
  p_object_path text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_expected_path text;
  v_asset public.content_assets%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_asset_id IS NULL
    OR p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp')
    OR p_declared_size_bytes NOT BETWEEN 1 AND 10485760 THEN
    RAISE EXCEPTION 'valid content cover declaration is required' USING ERRCODE = '22023';
  END IF;

  v_expected_path := 'content/' || p_asset_id::text || CASE p_mime_type
    WHEN 'image/jpeg' THEN '.jpg'
    WHEN 'image/png' THEN '.png'
    WHEN 'image/webp' THEN '.webp'
  END;

  IF p_object_path IS DISTINCT FROM v_expected_path THEN
    RAISE EXCEPTION 'content cover path must be server-shaped' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.content_assets (
    id,
    object_path,
    mime_type,
    declared_size_bytes,
    created_by
  ) VALUES (
    p_asset_id,
    p_object_path,
    p_mime_type,
    p_declared_size_bytes,
    p_actor_id
  )
  RETURNING * INTO v_asset;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.asset.create',
    'content_asset',
    p_asset_id::text,
    jsonb_build_object('asset_id', p_asset_id, 'state', 'pending_upload')
  );

  RETURN jsonb_build_object(
    'asset_id', v_asset.id,
    'bucket_id', v_asset.bucket_id,
    'object_path', v_asset.object_path,
    'mime_type', v_asset.mime_type,
    'declared_size_bytes', v_asset.declared_size_bytes,
    'status', v_asset.status,
    'created_at', v_asset.created_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_content_asset(
  p_actor_id uuid,
  p_asset_id uuid,
  p_actual_size_bytes bigint,
  p_etag text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_asset public.content_assets%ROWTYPE;
  v_now timestamptz := clock_timestamp();
  v_object_etag text;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_asset_id IS NULL
    OR p_actual_size_bytes IS NULL
    OR p_etag IS NULL
    OR char_length(btrim(p_etag)) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'valid content cover completion is required' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_asset
  FROM public.content_assets asset
  WHERE asset.id = p_asset_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'content asset not found' USING ERRCODE = '23503';
  END IF;
  IF v_asset.created_by <> p_actor_id THEN
    RAISE EXCEPTION 'only the content asset creator may complete it'
      USING ERRCODE = '42501';
  END IF;
  IF v_asset.status <> 'pending_upload' THEN
    RAISE EXCEPTION 'only pending content assets can be completed'
      USING ERRCODE = '23514';
  END IF;
  IF p_actual_size_bytes <> v_asset.declared_size_bytes THEN
    RAISE EXCEPTION 'content cover size does not match its declaration'
      USING ERRCODE = '23514';
  END IF;

  SELECT object.metadata->>'eTag'
  INTO v_object_etag
    FROM storage.objects object
    WHERE object.bucket_id = v_asset.bucket_id
      AND object.name = v_asset.object_path
      AND object.metadata->>'mimetype' = v_asset.mime_type
      AND CASE
        WHEN object.metadata->>'size' ~ '^[0-9]+$'
          THEN (object.metadata->>'size')::bigint
        ELSE NULL
      END = p_actual_size_bytes
      AND char_length(btrim(object.metadata->>'eTag')) BETWEEN 1 AND 512
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'matching content cover object was not found in Storage'
      USING ERRCODE = '23514';
  END IF;
  IF btrim(p_etag) IS DISTINCT FROM btrim(v_object_etag) THEN
    RAISE EXCEPTION 'content cover ETag does not match Storage metadata'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.content_assets
  SET actual_size_bytes = p_actual_size_bytes,
      etag = btrim(v_object_etag),
      status = 'uploaded',
      uploaded_at = v_now
  WHERE id = p_asset_id
  RETURNING * INTO v_asset;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.asset.complete',
    'content_asset',
    p_asset_id::text,
    jsonb_build_object('asset_id', p_asset_id, 'state', 'uploaded')
  );

  RETURN jsonb_build_object(
    'asset_id', v_asset.id,
    'status', v_asset.status,
    'actual_size_bytes', v_asset.actual_size_bytes,
    'uploaded_at', v_asset.uploaded_at,
    'updated_at', v_asset.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_content_asset(
  p_actor_id uuid,
  p_asset_id uuid,
  p_expected_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_asset public.content_assets%ROWTYPE;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.admin_users admin_user
    WHERE admin_user.id = p_actor_id
      AND admin_user.role = 'content_editor'
  ) THEN
    RAISE EXCEPTION 'content_editor actor is required' USING ERRCODE = '42501';
  END IF;

  IF p_asset_id IS NULL
    OR p_expected_status IS NULL
    OR p_expected_status NOT IN ('pending_upload', 'uploaded', 'deleted') THEN
    RAISE EXCEPTION 'content asset and expected status are required' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_asset
  FROM public.content_assets asset
  WHERE asset.id = p_asset_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'content asset not found' USING ERRCODE = '23503';
  END IF;
  IF v_asset.created_by <> p_actor_id THEN
    RAISE EXCEPTION 'only the content asset creator may delete it'
      USING ERRCODE = '42501';
  END IF;
  IF v_asset.status = 'deleted' THEN
    RETURN jsonb_build_object(
      'asset_id', p_asset_id,
      'status', 'deleted',
      'deleted_at', v_asset.deleted_at
    );
  END IF;
  IF v_asset.status IS DISTINCT FROM p_expected_status THEN
    RAISE EXCEPTION 'content asset changed since it was loaded'
      USING ERRCODE = '40001';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.content_versions version
    WHERE version.cover_asset_id = p_asset_id
  ) THEN
    RAISE EXCEPTION 'referenced content cover cannot be deleted'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.content_assets
  SET status = 'deleted',
      deleted_at = v_now
  WHERE id = p_asset_id
  RETURNING * INTO v_asset;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after)
  VALUES (
    p_actor_id,
    'content.asset.delete',
    'content_asset',
    p_asset_id::text,
    jsonb_build_object('asset_id', p_asset_id, 'state', 'deleted')
  );

  RETURN jsonb_build_object(
    'asset_id', p_asset_id,
    'status', v_asset.status,
    'deleted_at', v_asset.deleted_at,
    'updated_at', v_asset.updated_at
  );
END;
$$;

ALTER TABLE public.content_publications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_version_target_protocols ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_version_target_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_version_target_personalities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.content_publications FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_assets FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_versions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_version_target_protocols FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_version_target_plans FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_version_target_personalities FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_user_state FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.content_events FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_publications TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_assets TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_versions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_version_target_protocols TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_version_target_plans TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_version_target_personalities TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_user_state TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.content_events TO service_role;

REVOKE ALL ON FUNCTION public.create_content_publication(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_content_draft(uuid, uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_content_draft(uuid, uuid, timestamptz, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_content_version(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.review_content_version(uuid, uuid, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.publish_content_version(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.archive_content_publication(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_content_asset(uuid, uuid, text, bigint, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_content_asset(uuid, uuid, bigint, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.delete_content_asset(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_content_publication(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_content_draft(uuid, uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_content_draft(uuid, uuid, timestamptz, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_content_version(uuid, uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.review_content_version(uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.publish_content_version(uuid, uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_content_publication(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_content_asset(uuid, uuid, text, bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_content_asset(uuid, uuid, bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_content_asset(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION private.guard_content_publication_mutation()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_content_asset_mutation()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.prepare_content_version_mutation()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_content_version_delete()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.validate_content_version_cover()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_content_target_mutation()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.validate_content_personality_target()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.touch_content_user_state_updated_at()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_content_events_immutable()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION private.guard_content_publication_mutation() TO service_role;
GRANT EXECUTE ON FUNCTION private.guard_content_asset_mutation() TO service_role;
GRANT EXECUTE ON FUNCTION private.prepare_content_version_mutation() TO service_role;
GRANT EXECUTE ON FUNCTION private.guard_content_version_delete() TO service_role;
GRANT EXECUTE ON FUNCTION private.validate_content_version_cover() TO service_role;
GRANT EXECUTE ON FUNCTION private.guard_content_target_mutation() TO service_role;
GRANT EXECUTE ON FUNCTION private.validate_content_personality_target() TO service_role;
GRANT EXECUTE ON FUNCTION private.touch_content_user_state_updated_at() TO service_role;
GRANT EXECUTE ON FUNCTION private.guard_content_events_immutable() TO service_role;

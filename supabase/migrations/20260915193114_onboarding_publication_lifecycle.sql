ALTER TABLE public.onboarding_legal_documents
  ALTER COLUMN publication_status SET DEFAULT 'inactive',
  ALTER COLUMN published_at DROP NOT NULL,
  ADD COLUMN archived_at timestamptz;

ALTER TABLE public.onboarding_legal_documents
  DROP CONSTRAINT onboarding_legal_documents_publication_check,
  ADD CONSTRAINT onboarding_legal_documents_publication_check CHECK (
    publication_status IN ('inactive', 'published', 'archived')
  ),
  ADD CONSTRAINT onboarding_legal_documents_lifecycle_timestamps_check CHECK (
    (publication_status = 'inactive' AND published_at IS NULL AND archived_at IS NULL)
    OR (publication_status = 'published' AND published_at IS NOT NULL AND archived_at IS NULL)
    OR (publication_status = 'archived' AND published_at IS NOT NULL AND archived_at IS NOT NULL)
  );

ALTER TABLE public.onboarding_legal_requirement_sets
  ALTER COLUMN publication_status SET DEFAULT 'inactive',
  ALTER COLUMN published_at DROP NOT NULL,
  ADD COLUMN archived_at timestamptz;

ALTER TABLE public.onboarding_legal_requirement_sets
  DROP CONSTRAINT onboarding_legal_requirement_sets_publication_check,
  ADD CONSTRAINT onboarding_legal_requirement_sets_publication_check CHECK (
    publication_status IN ('inactive', 'published', 'archived')
  ),
  ADD CONSTRAINT onboarding_legal_requirement_sets_lifecycle_timestamps_check CHECK (
    (publication_status = 'inactive' AND published_at IS NULL AND archived_at IS NULL)
    OR (publication_status = 'published' AND published_at IS NOT NULL AND archived_at IS NULL)
    OR (publication_status = 'archived' AND published_at IS NOT NULL AND archived_at IS NOT NULL)
  );

DROP TRIGGER onboarding_legal_documents_immutable
  ON public.onboarding_legal_documents;
DROP TRIGGER onboarding_legal_requirement_sets_immutable
  ON public.onboarding_legal_requirement_sets;

CREATE OR REPLACE FUNCTION private.guard_onboarding_legal_document_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Onboarding legal records are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.publication_status <> 'inactive'
      OR NEW.published_at IS NOT NULL
      OR NEW.archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'Onboarding legal documents must begin inactive'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.document_key IS DISTINCT FROM OLD.document_key
    OR NEW.version IS DISTINCT FROM OLD.version
    OR NEW.locale IS DISTINCT FROM OLD.locale
    OR NEW.body IS DISTINCT FROM OLD.body
    OR NEW.content_url IS DISTINCT FROM OLD.content_url
    OR NEW.content_hash IS DISTINCT FROM OLD.content_hash
    OR NEW.purpose IS DISTINCT FROM OLD.purpose
    OR NEW.action_type IS DISTINCT FROM OLD.action_type
    OR NEW.required IS DISTINCT FROM OLD.required
    OR NEW.effective_at IS DISTINCT FROM OLD.effective_at
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Onboarding legal document content and identity are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF current_setting('performe.onboarding_lifecycle_write', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'Onboarding legal document lifecycle requires a trusted function'
      USING ERRCODE = '42501';
  END IF;

  IF OLD.publication_status = 'inactive'
    AND NEW.publication_status = 'published'
    AND OLD.published_at IS NULL
    AND OLD.archived_at IS NULL
    AND NEW.published_at IS NOT NULL
    AND NEW.archived_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF OLD.publication_status = 'published'
    AND NEW.publication_status = 'archived'
    AND NEW.published_at IS NOT DISTINCT FROM OLD.published_at
    AND OLD.archived_at IS NULL
    AND NEW.archived_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Invalid onboarding legal document lifecycle transition: % -> %',
    OLD.publication_status, NEW.publication_status
    USING ERRCODE = '23514';
END;
$$;

CREATE OR REPLACE FUNCTION private.guard_onboarding_legal_requirement_set_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Onboarding legal records are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.publication_status <> 'inactive'
      OR NEW.published_at IS NOT NULL
      OR NEW.archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'Onboarding legal requirement sets must begin inactive'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.version IS DISTINCT FROM OLD.version
    OR NEW.locale IS DISTINCT FROM OLD.locale
    OR NEW.document_keys IS DISTINCT FROM OLD.document_keys
    OR NEW.effective_at IS DISTINCT FROM OLD.effective_at
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Onboarding legal requirement set identity and composition are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF current_setting('performe.onboarding_lifecycle_write', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'Onboarding legal requirement set lifecycle requires a trusted function'
      USING ERRCODE = '42501';
  END IF;

  IF OLD.publication_status = 'inactive'
    AND NEW.publication_status = 'published'
    AND OLD.published_at IS NULL
    AND OLD.archived_at IS NULL
    AND NEW.published_at IS NOT NULL
    AND NEW.archived_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF OLD.publication_status = 'published'
    AND NEW.publication_status = 'archived'
    AND NEW.published_at IS NOT DISTINCT FROM OLD.published_at
    AND OLD.archived_at IS NULL
    AND NEW.archived_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Invalid onboarding legal requirement set lifecycle transition: % -> %',
    OLD.publication_status, NEW.publication_status
    USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER onboarding_legal_documents_lifecycle_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.onboarding_legal_documents
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_onboarding_legal_document_lifecycle();

CREATE TRIGGER onboarding_legal_requirement_sets_lifecycle_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.onboarding_legal_requirement_sets
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_onboarding_legal_requirement_set_lifecycle();

REVOKE ALL ON FUNCTION private.guard_onboarding_legal_document_lifecycle()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_onboarding_legal_requirement_set_lifecycle()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.publish_onboarding_legal_document(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_document public.onboarding_legal_documents%ROWTYPE;
  v_now timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_document_id IS NULL THEN
    RAISE EXCEPTION 'onboarding_document_id_required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('onboarding-document:' || p_document_id::text, 0));

  SELECT document.*
  INTO v_document
  FROM public.onboarding_legal_documents document
  WHERE document.id = p_document_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_document_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_document.publication_status = 'published' THEN
    RETURN jsonb_build_object(
      'outcome', 'already_published',
      'document_id', v_document.id,
      'publication_status', v_document.publication_status,
      'published_at', v_document.published_at
    );
  END IF;
  IF v_document.publication_status <> 'inactive' THEN
    RAISE EXCEPTION 'archived_onboarding_document_cannot_be_published'
      USING ERRCODE = '23514';
  END IF;

  v_now := clock_timestamp();
  PERFORM set_config('performe.onboarding_lifecycle_write', 'on', true);

  UPDATE public.onboarding_legal_documents
  SET publication_status = 'published',
      published_at = v_now
  WHERE id = p_document_id
  RETURNING * INTO v_document;

  INSERT INTO public.audit_log (action, entity, entity_id, before, after, created_at)
  VALUES (
    'onboarding.legal_document.publish',
    'onboarding_legal_document',
    p_document_id::text,
    jsonb_build_object('publication_status', 'inactive'),
    jsonb_build_object(
      'publication_status', 'published',
      'document_key', v_document.document_key,
      'version', v_document.version,
      'locale', v_document.locale
    ),
    v_now
  );

  RETURN jsonb_build_object(
    'outcome', 'published',
    'document_id', v_document.id,
    'publication_status', v_document.publication_status,
    'published_at', v_document.published_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_onboarding_legal_document(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_document public.onboarding_legal_documents%ROWTYPE;
  v_now timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_document_id IS NULL THEN
    RAISE EXCEPTION 'onboarding_document_id_required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('onboarding-document:' || p_document_id::text, 0));

  SELECT document.*
  INTO v_document
  FROM public.onboarding_legal_documents document
  WHERE document.id = p_document_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_document_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_document.publication_status = 'archived' THEN
    RETURN jsonb_build_object(
      'outcome', 'already_archived',
      'document_id', v_document.id,
      'publication_status', v_document.publication_status,
      'published_at', v_document.published_at,
      'archived_at', v_document.archived_at
    );
  END IF;
  IF v_document.publication_status <> 'published' THEN
    RAISE EXCEPTION 'inactive_onboarding_document_cannot_be_archived'
      USING ERRCODE = '23514';
  END IF;

  v_now := clock_timestamp();
  IF EXISTS (
    SELECT 1
    FROM public.onboarding_legal_requirement_sets requirement_set
    WHERE requirement_set.locale = v_document.locale
      AND requirement_set.publication_status = 'published'
      AND requirement_set.effective_at <= v_now
      AND requirement_set.published_at <= v_now
      AND v_document.document_key = ANY(requirement_set.document_keys)
  ) THEN
    RAISE EXCEPTION 'published_onboarding_requirement_set_references_document'
      USING ERRCODE = '23514';
  END IF;

  PERFORM set_config('performe.onboarding_lifecycle_write', 'on', true);

  UPDATE public.onboarding_legal_documents
  SET publication_status = 'archived',
      archived_at = v_now
  WHERE id = p_document_id
  RETURNING * INTO v_document;

  INSERT INTO public.audit_log (action, entity, entity_id, before, after, created_at)
  VALUES (
    'onboarding.legal_document.archive',
    'onboarding_legal_document',
    p_document_id::text,
    jsonb_build_object('publication_status', 'published'),
    jsonb_build_object(
      'publication_status', 'archived',
      'document_key', v_document.document_key,
      'version', v_document.version,
      'locale', v_document.locale
    ),
    v_now
  );

  RETURN jsonb_build_object(
    'outcome', 'archived',
    'document_id', v_document.id,
    'publication_status', v_document.publication_status,
    'published_at', v_document.published_at,
    'archived_at', v_document.archived_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_onboarding_legal_requirement_set(p_requirement_set_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_requirement_set public.onboarding_legal_requirement_sets%ROWTYPE;
  v_now timestamptz;
  v_archived_ids uuid[];
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_requirement_set_id IS NULL THEN
    RAISE EXCEPTION 'onboarding_requirement_set_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT requirement_set.*
  INTO v_requirement_set
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.id = p_requirement_set_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_requirement_set_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('onboarding-requirement-set:' || v_requirement_set.locale, 0)
  );

  SELECT requirement_set.*
  INTO v_requirement_set
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.id = p_requirement_set_id
  FOR UPDATE;

  IF v_requirement_set.publication_status = 'published' THEN
    RETURN jsonb_build_object(
      'outcome', 'already_published',
      'requirement_set_id', v_requirement_set.id,
      'publication_status', v_requirement_set.publication_status,
      'published_at', v_requirement_set.published_at
    );
  END IF;
  IF v_requirement_set.publication_status <> 'inactive' THEN
    RAISE EXCEPTION 'archived_onboarding_requirement_set_cannot_be_published'
      USING ERRCODE = '23514';
  END IF;
  v_now := clock_timestamp();
  IF v_requirement_set.effective_at > v_now THEN
    RAISE EXCEPTION 'future_onboarding_requirement_set_cannot_be_published'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_requirement_set.document_keys) AS required_key(document_key)
    LEFT JOIN LATERAL (
      SELECT document.required
      FROM public.onboarding_legal_documents document
      WHERE document.locale = v_requirement_set.locale
        AND document.document_key = required_key.document_key
        AND document.publication_status = 'published'
        AND document.effective_at <= v_now
        AND document.published_at <= v_now
      ORDER BY document.effective_at DESC, document.published_at DESC, document.id DESC
      LIMIT 1
    ) current_document ON true
    WHERE current_document.required IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'onboarding_requirement_set_documents_unavailable'
      USING ERRCODE = '23514';
  END IF;

  SELECT array_agg(requirement_set.id ORDER BY requirement_set.effective_at, requirement_set.id)
  INTO v_archived_ids
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.locale = v_requirement_set.locale
    AND requirement_set.id <> v_requirement_set.id
    AND requirement_set.publication_status = 'published';

  PERFORM set_config('performe.onboarding_lifecycle_write', 'on', true);

  UPDATE public.onboarding_legal_requirement_sets
  SET publication_status = 'archived',
      archived_at = v_now
  WHERE locale = v_requirement_set.locale
    AND id <> v_requirement_set.id
    AND publication_status = 'published';

  UPDATE public.onboarding_legal_requirement_sets
  SET publication_status = 'published',
      published_at = v_now
  WHERE id = p_requirement_set_id
  RETURNING * INTO v_requirement_set;

  INSERT INTO public.audit_log (action, entity, entity_id, before, after, created_at)
  VALUES (
    'onboarding.legal_requirement_set.publish',
    'onboarding_legal_requirement_set',
    p_requirement_set_id::text,
    jsonb_build_object(
      'publication_status', 'inactive',
      'archived_requirement_set_ids', COALESCE(to_jsonb(v_archived_ids), '[]'::jsonb)
    ),
    jsonb_build_object(
      'publication_status', 'published',
      'version', v_requirement_set.version,
      'locale', v_requirement_set.locale,
      'document_keys', to_jsonb(v_requirement_set.document_keys)
    ),
    v_now
  );

  RETURN jsonb_build_object(
    'outcome', 'published',
    'requirement_set_id', v_requirement_set.id,
    'publication_status', v_requirement_set.publication_status,
    'published_at', v_requirement_set.published_at,
    'archived_requirement_set_ids', COALESCE(to_jsonb(v_archived_ids), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_onboarding_legal_requirement_set(p_requirement_set_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_requirement_set public.onboarding_legal_requirement_sets%ROWTYPE;
  v_now timestamptz;
  v_archived_ids uuid[];
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_requirement_set_id IS NULL THEN
    RAISE EXCEPTION 'onboarding_requirement_set_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT requirement_set.*
  INTO v_requirement_set
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.id = p_requirement_set_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_requirement_set_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('onboarding-requirement-set:' || v_requirement_set.locale, 0)
  );

  SELECT requirement_set.*
  INTO v_requirement_set
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.id = p_requirement_set_id
  FOR UPDATE;

  IF v_requirement_set.publication_status = 'archived' THEN
    RETURN jsonb_build_object(
      'outcome', 'already_archived',
      'requirement_set_id', v_requirement_set.id,
      'publication_status', v_requirement_set.publication_status,
      'published_at', v_requirement_set.published_at,
      'archived_at', v_requirement_set.archived_at
    );
  END IF;
  IF v_requirement_set.publication_status <> 'published' THEN
    RAISE EXCEPTION 'inactive_onboarding_requirement_set_cannot_be_archived'
      USING ERRCODE = '23514';
  END IF;

  v_now := clock_timestamp();
  SELECT array_agg(requirement_set.id ORDER BY requirement_set.effective_at, requirement_set.id)
  INTO v_archived_ids
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.locale = v_requirement_set.locale
    AND requirement_set.publication_status = 'published'
    AND requirement_set.effective_at <= v_requirement_set.effective_at;

  PERFORM set_config('performe.onboarding_lifecycle_write', 'on', true);

  UPDATE public.onboarding_legal_requirement_sets
  SET publication_status = 'archived',
      archived_at = v_now
  WHERE locale = v_requirement_set.locale
    AND publication_status = 'published'
    AND effective_at <= v_requirement_set.effective_at;

  SELECT requirement_set.*
  INTO v_requirement_set
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.id = p_requirement_set_id;

  INSERT INTO public.audit_log (action, entity, entity_id, before, after, created_at)
  VALUES (
    'onboarding.legal_requirement_set.archive',
    'onboarding_legal_requirement_set',
    p_requirement_set_id::text,
    jsonb_build_object(
      'publication_status', 'published',
      'archived_requirement_set_ids', COALESCE(to_jsonb(v_archived_ids), '[]'::jsonb)
    ),
    jsonb_build_object(
      'publication_status', 'archived',
      'version', v_requirement_set.version,
      'locale', v_requirement_set.locale
    ),
    v_now
  );

  RETURN jsonb_build_object(
    'outcome', 'archived',
    'requirement_set_id', v_requirement_set.id,
    'publication_status', v_requirement_set.publication_status,
    'published_at', v_requirement_set.published_at,
    'archived_at', v_requirement_set.archived_at,
    'archived_requirement_set_ids', COALESCE(to_jsonb(v_archived_ids), '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.publish_onboarding_legal_document(uuid) IS
  'Trusted-backend-only inactive-to-published transition for immutable onboarding legal documents.';
COMMENT ON FUNCTION public.archive_onboarding_legal_document(uuid) IS
  'Trusted-backend-only published-to-archived transition for onboarding legal documents not used by an eligible published requirement set.';
COMMENT ON FUNCTION public.publish_onboarding_legal_requirement_set(uuid) IS
  'Trusted-backend-only atomic publication and same-locale predecessor archival for onboarding requirement sets.';
COMMENT ON FUNCTION public.archive_onboarding_legal_requirement_set(uuid) IS
  'Trusted-backend-only archive that also prevents fallback to same-locale predecessor requirement sets.';

REVOKE ALL ON FUNCTION public.publish_onboarding_legal_document(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.archive_onboarding_legal_document(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.publish_onboarding_legal_requirement_set(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.archive_onboarding_legal_requirement_set(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.publish_onboarding_legal_document(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_onboarding_legal_document(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.publish_onboarding_legal_requirement_set(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_onboarding_legal_requirement_set(uuid)
  TO service_role;

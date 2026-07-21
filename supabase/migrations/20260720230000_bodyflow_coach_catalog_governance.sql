-- Atomic, service-only governance for BodyFlow coach content packs.
-- Copy is immutable: every edit creates a new version and moves only a draft
-- pack entry to that version.

CREATE OR REPLACE FUNCTION public.validate_coach_content_pack(
  p_pack_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pack_status text;
  v_entry_count integer;
  v_valid_entry_count integer;
BEGIN
  IF p_pack_id IS NULL THEN
    RAISE EXCEPTION 'pack_id is required' USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_pack_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (
      WHERE version.status IN ('draft', 'active')
        AND (
          (template.channel = 'in_app' AND version.title IS NULL AND version.subject IS NULL)
          OR (template.channel = 'push' AND version.title IS NOT NULL AND version.subject IS NULL)
          OR (template.channel = 'email' AND version.title IS NULL AND version.subject IS NOT NULL)
        )
    )
  INTO v_entry_count, v_valid_entry_count
  FROM public.coach_content_pack_entries entry
  JOIN public.coach_message_templates template ON template.id = entry.template_id
  JOIN public.coach_message_template_versions version
    ON version.id = entry.template_version_id
    AND version.template_id = entry.template_id
  WHERE entry.pack_id = p_pack_id;

  RETURN jsonb_build_object(
    'pack_id', p_pack_id,
    'status', v_pack_status,
    'entry_count', v_entry_count,
    'valid_entry_count', v_valid_entry_count,
    'expected_entry_count', 1080,
    'valid', v_entry_count = 1080 AND v_valid_entry_count = 1080
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.clone_active_coach_content_pack(
  p_slug text,
  p_label text,
  p_actor_id uuid,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_parent_pack_id uuid;
  v_pack_id uuid;
  v_entry_count integer;
BEGIN
  IF p_slug IS NULL OR p_label IS NULL OR p_actor_id IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'slug, label, actor_id, and time are required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('bodyflow-coach-pack-governance', 0));

  SELECT pack.id
  INTO v_parent_pack_id
  FROM public.coach_content_packs pack
  WHERE pack.status = 'active'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'an active coach content pack is required' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.coach_content_packs (
    slug,
    label,
    status,
    parent_pack_id,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    btrim(p_slug),
    btrim(p_label),
    'draft',
    v_parent_pack_id,
    p_actor_id,
    p_now,
    p_now
  )
  RETURNING id INTO v_pack_id;

  INSERT INTO public.coach_content_pack_entries (
    pack_id,
    template_id,
    template_version_id,
    created_at
  )
  SELECT
    v_pack_id,
    entry.template_id,
    entry.template_version_id,
    p_now
  FROM public.coach_content_pack_entries entry
  WHERE entry.pack_id = v_parent_pack_id;

  GET DIAGNOSTICS v_entry_count = ROW_COUNT;
  IF v_entry_count <> 1080 THEN
    RAISE EXCEPTION 'active coach content pack must contain exactly 1,080 entries'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.clone',
    'coach_content_pack',
    v_pack_id::text,
    jsonb_build_object(
      'pack_id', v_pack_id,
      'parent_pack_id', v_parent_pack_id,
      'status', 'draft',
      'entry_count', v_entry_count
    ),
    p_now
  );

  RETURN jsonb_build_object(
    'outcome', 'cloned',
    'pack_id', v_pack_id,
    'parent_pack_id', v_parent_pack_id,
    'entry_count', v_entry_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.revise_coach_draft_entries(
  p_pack_id uuid,
  p_revisions jsonb,
  p_actor_id uuid,
  p_provenance text,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, extensions, pg_temp
AS $$
DECLARE
  v_pack_status text;
  v_revision jsonb;
  v_template_id uuid;
  v_expected_version_id uuid;
  v_current_version_id uuid;
  v_current_title text;
  v_current_subject text;
  v_current_body text;
  v_channel text;
  v_title text;
  v_subject text;
  v_body text;
  v_next_version integer;
  v_new_version_id uuid;
  v_content_hash text;
  v_results jsonb := '[]'::jsonb;
  v_revision_count integer;
BEGIN
  IF p_pack_id IS NULL OR p_actor_id IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, actor_id, and time are required' USING ERRCODE = '22023';
  END IF;
  IF p_provenance NOT IN ('human', 'assisted_draft') THEN
    RAISE EXCEPTION 'draft provenance must be human or assisted_draft' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_revisions) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'revisions must be a JSON array' USING ERRCODE = '22023';
  END IF;

  v_revision_count := jsonb_array_length(p_revisions);
  IF v_revision_count < 1 OR v_revision_count > 9 THEN
    RAISE EXCEPTION 'between 1 and 9 revisions are required' USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_pack_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;
  IF v_pack_status <> 'draft' THEN
    RAISE EXCEPTION 'only a draft coach content pack can be revised' USING ERRCODE = '23514';
  END IF;

  FOR v_revision IN SELECT value FROM jsonb_array_elements(p_revisions)
  LOOP
    IF jsonb_typeof(v_revision) IS DISTINCT FROM 'object'
      OR NOT (
        v_revision ? 'template_id'
        AND v_revision ? 'expected_template_version_id'
        AND v_revision ? 'title'
        AND v_revision ? 'subject'
        AND v_revision ? 'body'
      )
      OR EXISTS (
        SELECT 1
        FROM jsonb_object_keys(v_revision) key
        WHERE key NOT IN (
          'template_id',
          'expected_template_version_id',
          'title',
          'subject',
          'body'
        )
      ) THEN
      RAISE EXCEPTION 'each revision must use the exact supported shape' USING ERRCODE = '22023';
    END IF;

    BEGIN
      v_template_id := (v_revision->>'template_id')::uuid;
      v_expected_version_id := (v_revision->>'expected_template_version_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'revision identifiers must be UUIDs' USING ERRCODE = '22023';
    END;

    v_title := v_revision->>'title';
    v_subject := v_revision->>'subject';
    v_body := v_revision->>'body';
    IF v_body IS NULL OR char_length(v_body) = 0 THEN
      RAISE EXCEPTION 'revision body is required' USING ERRCODE = '22023';
    END IF;

    SELECT
      entry.template_version_id,
      template.channel,
      current_version.title,
      current_version.subject,
      current_version.body
    INTO
      v_current_version_id,
      v_channel,
      v_current_title,
      v_current_subject,
      v_current_body
    FROM public.coach_content_pack_entries entry
    JOIN public.coach_message_templates template ON template.id = entry.template_id
    JOIN public.coach_message_template_versions current_version
      ON current_version.id = entry.template_version_id
    WHERE entry.pack_id = p_pack_id
      AND entry.template_id = v_template_id
    FOR UPDATE OF entry, template;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'revision template is not part of the draft pack' USING ERRCODE = '23503';
    END IF;
    IF v_current_version_id <> v_expected_version_id THEN
      RAISE EXCEPTION 'draft entry changed since it was loaded' USING ERRCODE = '40001';
    END IF;
    IF (v_channel = 'in_app' AND (v_title IS NOT NULL OR v_subject IS NOT NULL))
      OR (v_channel = 'push' AND (v_title IS NULL OR v_subject IS NOT NULL))
      OR (v_channel = 'email' AND (v_title IS NOT NULL OR v_subject IS NULL)) THEN
      RAISE EXCEPTION 'revision does not match its channel shape' USING ERRCODE = '23514';
    END IF;
    IF v_title IS NOT DISTINCT FROM v_current_title
      AND v_subject IS NOT DISTINCT FROM v_current_subject
      AND v_body IS NOT DISTINCT FROM v_current_body THEN
      RAISE EXCEPTION 'revision must change copy' USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(max(version.version), 0) + 1
    INTO v_next_version
    FROM public.coach_message_template_versions version
    WHERE version.template_id = v_template_id;

    v_content_hash := encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'title', v_title,
            'subject', v_subject,
            'body', v_body
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    INSERT INTO public.coach_message_template_versions (
      template_id,
      version,
      title,
      subject,
      body,
      status,
      provenance,
      authored_by,
      content_hash,
      created_at,
      updated_at
    ) VALUES (
      v_template_id,
      v_next_version,
      v_title,
      v_subject,
      v_body,
      'draft',
      p_provenance,
      p_actor_id,
      v_content_hash,
      p_now,
      p_now
    )
    RETURNING id INTO v_new_version_id;

    UPDATE public.coach_content_pack_entries
    SET template_version_id = v_new_version_id
    WHERE pack_id = p_pack_id
      AND template_id = v_template_id
      AND template_version_id = v_expected_version_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'draft entry changed during revision' USING ERRCODE = '40001';
    END IF;

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'template_id', v_template_id,
      'previous_template_version_id', v_expected_version_id,
      'template_version_id', v_new_version_id,
      'version', v_next_version
    ));
  END LOOP;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.revise',
    'coach_content_pack',
    p_pack_id::text,
    jsonb_build_object(
      'pack_id', p_pack_id,
      'provenance', p_provenance,
      'revision_count', v_revision_count
    ),
    p_now
  );

  RETURN jsonb_build_object(
    'outcome', 'revised',
    'pack_id', p_pack_id,
    'revision_count', v_revision_count,
    'revisions', v_results
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_effective_at timestamptz,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_status text;
  v_validation jsonb;
BEGIN
  IF p_pack_id IS NULL OR p_actor_id IS NULL OR p_effective_at IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, actor_id, effective_at, and time are required' USING ERRCODE = '22023';
  END IF;
  IF p_effective_at <= p_now THEN
    RAISE EXCEPTION 'scheduled activation must be in the future' USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'only a draft coach content pack can be scheduled' USING ERRCODE = '23514';
  END IF;

  v_validation := public.validate_coach_content_pack(p_pack_id);
  IF NOT (v_validation->>'valid')::boolean THEN
    RAISE EXCEPTION 'coach content pack must be complete before scheduling' USING ERRCODE = '23514';
  END IF;

  UPDATE public.coach_content_packs
  SET status = 'scheduled',
      effective_at = p_effective_at,
      approved_by = p_actor_id,
      approved_at = p_now,
      archived_at = NULL,
      updated_at = p_now
  WHERE id = p_pack_id;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.schedule',
    'coach_content_pack',
    p_pack_id::text,
    jsonb_build_object('pack_id', p_pack_id, 'status', v_status),
    jsonb_build_object(
      'pack_id', p_pack_id,
      'status', 'scheduled',
      'effective_at', p_effective_at,
      'entry_count', v_validation->'entry_count'
    ),
    p_now
  );

  RETURN jsonb_build_object(
    'outcome', 'scheduled',
    'pack_id', p_pack_id,
    'effective_at', p_effective_at,
    'entry_count', v_validation->'entry_count'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_and_activate_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_status text;
  v_validation jsonb;
  v_activation jsonb;
BEGIN
  IF p_pack_id IS NULL OR p_actor_id IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, actor_id, and time are required' USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;
  IF v_status NOT IN ('draft', 'scheduled') THEN
    RAISE EXCEPTION 'only a draft or scheduled pack can be activated' USING ERRCODE = '23514';
  END IF;

  v_validation := public.validate_coach_content_pack(p_pack_id);
  IF NOT (v_validation->>'valid')::boolean THEN
    RAISE EXCEPTION 'coach content pack must be complete before activation' USING ERRCODE = '23514';
  END IF;

  UPDATE public.coach_content_packs
  SET approved_by = p_actor_id,
      approved_at = COALESCE(approved_at, p_now),
      updated_at = p_now
  WHERE id = p_pack_id;

  v_activation := public.activate_coach_content_pack(p_pack_id, p_actor_id, p_now);

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.activate',
    'coach_content_pack',
    p_pack_id::text,
    jsonb_build_object('pack_id', p_pack_id, 'status', v_status),
    jsonb_build_object(
      'pack_id', p_pack_id,
      'status', 'active',
      'previous_pack_id', v_activation->'previous_pack_id',
      'entry_count', v_validation->'entry_count'
    ),
    p_now
  );

  RETURN v_activation;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_status text;
BEGIN
  IF p_pack_id IS NULL OR p_actor_id IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, actor_id, and time are required' USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;
  IF v_status NOT IN ('draft', 'scheduled') THEN
    RAISE EXCEPTION 'only a draft or scheduled pack can be archived' USING ERRCODE = '23514';
  END IF;

  PERFORM set_config('bodyflow.coach_pack_lifecycle_write', 'on', true);

  UPDATE public.coach_message_template_versions version
  SET status = 'archived',
      archived_at = p_now
  WHERE version.status = 'draft'
    AND EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries entry
      WHERE entry.pack_id = p_pack_id
        AND entry.template_version_id = version.id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries other_entry
      JOIN public.coach_content_packs other_pack ON other_pack.id = other_entry.pack_id
      WHERE other_entry.template_version_id = version.id
        AND other_entry.pack_id <> p_pack_id
        AND other_pack.status IN ('draft', 'scheduled', 'active')
    );

  UPDATE public.coach_content_packs
  SET status = 'archived',
      effective_at = NULL,
      archived_at = p_now,
      updated_at = p_now
  WHERE id = p_pack_id;

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.archive',
    'coach_content_pack',
    p_pack_id::text,
    jsonb_build_object('pack_id', p_pack_id, 'status', v_status),
    jsonb_build_object('pack_id', p_pack_id, 'status', 'archived'),
    p_now
  );

  RETURN jsonb_build_object(
    'outcome', 'archived',
    'pack_id', p_pack_id,
    'previous_status', v_status,
    'archived_at', p_now
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rollback_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_target_status text;
  v_active_pack_id uuid;
  v_active_parent_pack_id uuid;
  v_validation jsonb;
  v_activation jsonb;
BEGIN
  IF p_pack_id IS NULL OR p_actor_id IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, actor_id, and time are required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('bodyflow-coach-pack-activation', 0));

  SELECT pack.status
  INTO v_target_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;
  IF v_target_status <> 'archived' THEN
    RAISE EXCEPTION 'only an archived pack can be restored' USING ERRCODE = '23514';
  END IF;

  SELECT pack.id, pack.parent_pack_id
  INTO v_active_pack_id, v_active_parent_pack_id
  FROM public.coach_content_packs pack
  WHERE pack.status = 'active'
  FOR UPDATE;

  IF NOT FOUND OR v_active_parent_pack_id IS DISTINCT FROM p_pack_id THEN
    RAISE EXCEPTION 'only the immediate previous active pack can be restored'
      USING ERRCODE = '23514';
  END IF;

  PERFORM set_config('bodyflow.coach_pack_lifecycle_write', 'on', true);

  UPDATE public.coach_message_template_versions version
  SET status = 'draft',
      archived_at = NULL
  WHERE version.status = 'archived'
    AND EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries entry
      WHERE entry.pack_id = p_pack_id
        AND entry.template_version_id = version.id
    );

  UPDATE public.coach_content_packs
  SET status = 'scheduled',
      effective_at = p_now,
      archived_at = NULL,
      approved_by = p_actor_id,
      approved_at = p_now,
      updated_at = p_now
  WHERE id = p_pack_id;

  v_validation := public.validate_coach_content_pack(p_pack_id);
  IF NOT (v_validation->>'valid')::boolean THEN
    RAISE EXCEPTION 'previous coach content pack is no longer complete' USING ERRCODE = '23514';
  END IF;

  v_activation := public.activate_coach_content_pack(p_pack_id, p_actor_id, p_now);

  INSERT INTO public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  VALUES (
    p_actor_id,
    'coach_pack.rollback',
    'coach_content_pack',
    p_pack_id::text,
    jsonb_build_object(
      'pack_id', p_pack_id,
      'status', v_target_status,
      'replaced_pack_id', v_active_pack_id
    ),
    jsonb_build_object(
      'pack_id', p_pack_id,
      'status', 'active',
      'replaced_pack_id', v_active_pack_id,
      'entry_count', v_validation->'entry_count'
    ),
    p_now
  );

  RETURN jsonb_build_object(
    'outcome', 'rolled_back',
    'pack_id', p_pack_id,
    'replaced_pack_id', v_active_pack_id,
    'entry_count', v_validation->'entry_count',
    'activated_at', v_activation->'activated_at'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_coach_content_pack(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clone_active_coach_content_pack(text, text, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revise_coach_draft_entries(uuid, jsonb, uuid, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.schedule_coach_content_pack(uuid, uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_and_activate_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.archive_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rollback_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.validate_coach_content_pack(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.clone_active_coach_content_pack(text, text, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.revise_coach_draft_entries(uuid, jsonb, uuid, text, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.schedule_coach_content_pack(uuid, uuid, timestamptz, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_and_activate_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.rollback_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;

COMMENT ON FUNCTION public.validate_coach_content_pack(uuid) IS
  'Service-only structural validation for a complete immutable BodyFlow coach pack.';
COMMENT ON FUNCTION public.clone_active_coach_content_pack(text, text, uuid, timestamptz) IS
  'Service-only atomic clone of the active BodyFlow coach pack into a complete draft.';
COMMENT ON FUNCTION public.revise_coach_draft_entries(uuid, jsonb, uuid, text, timestamptz) IS
  'Service-only atomic immutable revision of one to nine entries in a draft coach pack.';
COMMENT ON FUNCTION public.schedule_coach_content_pack(uuid, uuid, timestamptz, timestamptz) IS
  'Service-only validation, human approval, and scheduling of a complete draft coach pack.';
COMMENT ON FUNCTION public.approve_and_activate_coach_content_pack(uuid, uuid, timestamptz) IS
  'Service-only validation, human approval, and immediate atomic coach pack activation.';
COMMENT ON FUNCTION public.archive_coach_content_pack(uuid, uuid, timestamptz) IS
  'Service-only archive operation for a draft or scheduled coach pack.';
COMMENT ON FUNCTION public.rollback_coach_content_pack(uuid, uuid, timestamptz) IS
  'Service-only one-step rollback to the immediate previous active coach pack.';

-- Allow an approved pack to atomically approve its immutable draft versions.
-- This preserves separation of duties: editors author drafts and the pack
-- approver promotes the exact reviewed snapshot.

CREATE OR REPLACE FUNCTION public.activate_coach_content_pack(
  p_pack_id uuid,
  p_activated_by uuid,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pack public.coach_content_packs%ROWTYPE;
  v_previous_pack_id uuid;
  v_entry_count integer;
BEGIN
  IF p_pack_id IS NULL OR p_activated_by IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'pack_id, activated_by, and activation time are required'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('bodyflow-coach-pack-activation', 0));

  SELECT *
  INTO v_pack
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;

  IF v_pack.status = 'active' THEN
    RETURN jsonb_build_object(
      'outcome', 'already_active',
      'pack_id', v_pack.id,
      'activated_at', v_pack.activated_at
    );
  END IF;

  IF v_pack.status NOT IN ('draft', 'scheduled') THEN
    RAISE EXCEPTION 'only a draft or scheduled pack can be activated'
      USING ERRCODE = '23514';
  END IF;

  IF v_pack.approved_by IS NULL OR v_pack.approved_at IS NULL THEN
    RAISE EXCEPTION 'content pack requires human approval before activation'
      USING ERRCODE = '23514';
  END IF;

  SELECT count(*)
  INTO v_entry_count
  FROM public.coach_content_pack_entries entry
  JOIN public.coach_message_templates template ON template.id = entry.template_id
  JOIN public.coach_message_template_versions version
    ON version.id = entry.template_version_id
    AND version.template_id = entry.template_id
  WHERE entry.pack_id = p_pack_id
    AND version.status IN ('draft', 'active')
    AND (
      (template.channel = 'in_app' AND version.title IS NULL AND version.subject IS NULL)
      OR (template.channel = 'push' AND version.title IS NOT NULL AND version.subject IS NULL)
      OR (template.channel = 'email' AND version.title IS NULL AND version.subject IS NOT NULL)
    );

  IF v_entry_count <> 1080
    OR (
      SELECT count(*)
      FROM public.coach_content_pack_entries entry
      WHERE entry.pack_id = p_pack_id
    ) <> 1080 THEN
    RAISE EXCEPTION 'approved content pack must contain exactly 1,080 valid renditions'
      USING ERRCODE = '23514';
  END IF;

  SELECT pack.id
  INTO v_previous_pack_id
  FROM public.coach_content_packs pack
  WHERE pack.status = 'active'
    AND pack.id <> p_pack_id
  FOR UPDATE;

  PERFORM set_config('bodyflow.coach_pack_lifecycle_write', 'on', true);

  IF v_previous_pack_id IS NOT NULL THEN
    UPDATE public.coach_content_packs
    SET status = 'archived',
        archived_at = p_now,
        updated_at = clock_timestamp()
    WHERE id = v_previous_pack_id;
  END IF;

  UPDATE public.coach_message_template_versions version
  SET status = 'archived',
      archived_at = p_now
  WHERE version.status = 'active'
    AND NOT EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries next_entry
      WHERE next_entry.pack_id = p_pack_id
        AND next_entry.template_version_id = version.id
    );

  UPDATE public.coach_message_template_versions version
  SET status = 'active',
      approved_by = COALESCE(version.approved_by, p_activated_by),
      approved_at = COALESCE(version.approved_at, p_now),
      archived_at = NULL
  WHERE EXISTS (
    SELECT 1
    FROM public.coach_content_pack_entries entry
    WHERE entry.pack_id = p_pack_id
      AND entry.template_version_id = version.id
  );

  UPDATE public.coach_content_packs
  SET status = 'active',
      effective_at = COALESCE(effective_at, p_now),
      activated_at = p_now,
      archived_at = NULL,
      activated_by = p_activated_by,
      updated_at = clock_timestamp()
  WHERE id = p_pack_id;

  RETURN jsonb_build_object(
    'outcome', 'activated',
    'pack_id', p_pack_id,
    'previous_pack_id', v_previous_pack_id,
    'entry_count', v_entry_count,
    'activated_at', p_now
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;

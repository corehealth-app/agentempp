-- Close validation/activation races for the BodyFlow coach catalog and keep
-- assisted revisions plus their copy-free telemetry in one transaction.

CREATE OR REPLACE FUNCTION public.validate_coach_content_pack(
  p_pack_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, extensions, pg_temp
AS $$
DECLARE
  v_pack_status text;
  v_entry_count integer;
  v_valid_entry_count integer;
  v_snapshot_hash text;
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
    ),
    encode(
      extensions.digest(
        convert_to(
          COALESCE(
            string_agg(
              entry.template_id::text || ':' || entry.template_version_id::text,
              ',' ORDER BY entry.template_id
            ),
            ''
          ),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  INTO v_entry_count, v_valid_entry_count, v_snapshot_hash
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
    'snapshot_hash', v_snapshot_hash,
    'valid', v_entry_count = 1080 AND v_valid_entry_count = 1080
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.revise_coach_assisted_draft_entries(
  p_pack_id uuid,
  p_revisions jsonb,
  p_actor_id uuid,
  p_model text,
  p_prompt_tokens integer,
  p_completion_tokens integer,
  p_cost_usd numeric,
  p_latency_ms integer,
  p_group_key text,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_pack_id IS NULL
    OR p_actor_id IS NULL
    OR p_now IS NULL
    OR p_model IS NULL
    OR p_group_key IS NULL
    OR char_length(btrim(p_model)) NOT BETWEEN 1 AND 120
    OR p_group_key !~ '^(focus|impulse|zen)\|(onboarding|meal_pending|registration_confirmed|error_corrected|hydration|supplement|medication|workout|progress|day_incomplete|reevaluation|reengagement|trial|paywall|return_after_abandonment)\|(pt-BR|en-US)$'
    OR p_prompt_tokens IS NULL
    OR p_prompt_tokens < 0
    OR p_completion_tokens IS NULL
    OR p_completion_tokens < 0
    OR p_latency_ms IS NULL
    OR p_latency_ms < 0
    OR (p_cost_usd IS NOT NULL AND p_cost_usd < 0) THEN
    RAISE EXCEPTION 'assisted revision telemetry is invalid' USING ERRCODE = '22023';
  END IF;

  v_result := public.revise_coach_draft_entries(
    p_pack_id,
    p_revisions,
    p_actor_id,
    'assisted_draft',
    p_now
  );

  INSERT INTO public.audit_log (
    actor_id,
    action,
    entity,
    entity_id,
    after,
    created_at
  ) VALUES (
    p_actor_id,
    'coach_assisted_rewrite.stored',
    'coach_message_group',
    p_pack_id::text || ':' || p_group_key,
    jsonb_build_object(
      'pack_id', p_pack_id,
      'group_key', p_group_key,
      'status', 'stored',
      'model', btrim(p_model),
      'prompt_tokens', p_prompt_tokens,
      'completion_tokens', p_completion_tokens,
      'cost_usd', p_cost_usd,
      'latency_ms', p_latency_ms
    ),
    p_now
  );

  RETURN v_result;
END;
$$;

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
  v_previous_parent_pack_id uuid;
  v_entry_count integer;
  v_is_rollback boolean;
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

  SELECT pack.id, pack.parent_pack_id
  INTO v_previous_pack_id, v_previous_parent_pack_id
  FROM public.coach_content_packs pack
  WHERE pack.status = 'active'
    AND pack.id <> p_pack_id
  FOR UPDATE;

  v_is_rollback := COALESCE(
    current_setting('bodyflow.coach_pack_rollback', true),
    'off'
  ) = 'on';

  IF v_previous_pack_id IS NOT NULL
    AND NOT (
      (NOT v_is_rollback AND v_pack.parent_pack_id = v_previous_pack_id)
      OR (v_is_rollback AND v_previous_parent_pack_id = p_pack_id)
    ) THEN
    RAISE EXCEPTION 'coach content pack is not based on the current active lineage'
      USING ERRCODE = '23514';
  END IF;

  IF v_previous_pack_id IS NULL AND v_pack.parent_pack_id IS NOT NULL THEN
    RAISE EXCEPTION 'coach content pack parent is not active'
      USING ERRCODE = '23514';
  END IF;

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

DROP FUNCTION IF EXISTS public.schedule_coach_content_pack(
  uuid,
  uuid,
  timestamptz,
  timestamptz
);

CREATE OR REPLACE FUNCTION public.schedule_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_effective_at timestamptz,
  p_expected_snapshot_hash text,
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
  IF p_pack_id IS NULL
    OR p_actor_id IS NULL
    OR p_effective_at IS NULL
    OR p_now IS NULL
    OR p_expected_snapshot_hash IS NULL
    OR p_expected_snapshot_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'pack_id, actor_id, effective_at, snapshot_hash, and time are required'
      USING ERRCODE = '22023';
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
  IF v_validation->>'snapshot_hash' <> p_expected_snapshot_hash THEN
    RAISE EXCEPTION 'coach content pack changed since validation' USING ERRCODE = '40001';
  END IF;
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
      'entry_count', v_validation->'entry_count',
      'snapshot_hash', p_expected_snapshot_hash
    ),
    p_now
  );

  RETURN jsonb_build_object(
    'outcome', 'scheduled',
    'pack_id', p_pack_id,
    'effective_at', p_effective_at,
    'entry_count', v_validation->'entry_count',
    'snapshot_hash', p_expected_snapshot_hash
  );
END;
$$;

DROP FUNCTION IF EXISTS public.approve_and_activate_coach_content_pack(
  uuid,
  uuid,
  timestamptz
);

CREATE OR REPLACE FUNCTION public.approve_and_activate_coach_content_pack(
  p_pack_id uuid,
  p_actor_id uuid,
  p_expected_snapshot_hash text,
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
  IF p_pack_id IS NULL
    OR p_actor_id IS NULL
    OR p_now IS NULL
    OR p_expected_snapshot_hash IS NULL
    OR p_expected_snapshot_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'pack_id, actor_id, snapshot_hash, and time are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT pack.status
  INTO v_status
  FROM public.coach_content_packs pack
  WHERE pack.id = p_pack_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coach content pack not found' USING ERRCODE = '23503';
  END IF;

  IF v_status = 'active' THEN
    RETURN jsonb_build_object(
      'outcome', 'already_active',
      'pack_id', p_pack_id,
      'entry_count', 1080,
      'activated_at', (
        SELECT pack.activated_at
        FROM public.coach_content_packs pack
        WHERE pack.id = p_pack_id
      )
    );
  END IF;

  IF v_status NOT IN ('draft', 'scheduled') THEN
    RAISE EXCEPTION 'only a draft or scheduled pack can be activated' USING ERRCODE = '23514';
  END IF;

  v_validation := public.validate_coach_content_pack(p_pack_id);
  IF v_validation->>'snapshot_hash' <> p_expected_snapshot_hash THEN
    RAISE EXCEPTION 'coach content pack changed since validation' USING ERRCODE = '40001';
  END IF;
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
      'entry_count', v_validation->'entry_count',
      'snapshot_hash', p_expected_snapshot_hash
    ),
    p_now
  );

  RETURN v_activation || jsonb_build_object('snapshot_hash', p_expected_snapshot_hash);
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

  PERFORM set_config('bodyflow.coach_pack_rollback', 'on', true);
  v_activation := public.activate_coach_content_pack(p_pack_id, p_actor_id, p_now);
  PERFORM set_config('bodyflow.coach_pack_rollback', 'off', true);

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
      'entry_count', v_validation->'entry_count',
      'snapshot_hash', v_validation->'snapshot_hash'
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
REVOKE ALL ON FUNCTION public.revise_coach_assisted_draft_entries(
  uuid, jsonb, uuid, text, integer, integer, numeric, integer, text, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.activate_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.schedule_coach_content_pack(
  uuid, uuid, timestamptz, text, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_and_activate_coach_content_pack(
  uuid, uuid, text, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rollback_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.validate_coach_content_pack(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.revise_coach_assisted_draft_entries(
  uuid, jsonb, uuid, text, integer, integer, numeric, integer, text, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.activate_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.schedule_coach_content_pack(
  uuid, uuid, timestamptz, text, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_and_activate_coach_content_pack(
  uuid, uuid, text, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.rollback_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;

COMMENT ON FUNCTION public.validate_coach_content_pack(uuid) IS
  'Validates catalog shape and returns a deterministic hash of the exact immutable version set.';
COMMENT ON FUNCTION public.revise_coach_assisted_draft_entries(
  uuid, jsonb, uuid, text, integer, integer, numeric, integer, text, timestamptz
) IS 'Atomically stores bounded assisted draft revisions and copy-free provider telemetry.';
COMMENT ON FUNCTION public.schedule_coach_content_pack(
  uuid, uuid, timestamptz, text, timestamptz
) IS 'Schedules only the exact fully validated draft snapshot.';
COMMENT ON FUNCTION public.approve_and_activate_coach_content_pack(
  uuid, uuid, text, timestamptz
) IS 'Approves and activates only the exact validated snapshot on the current active lineage.';

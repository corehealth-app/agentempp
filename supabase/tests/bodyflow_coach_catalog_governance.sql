BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_function text;
  v_actor_id uuid := '00000000-0000-0000-0000-000000000921';
  v_pack_one_id uuid;
  v_pack_two_id uuid;
  v_pack_sibling_id uuid;
  v_pack_three_id uuid;
  v_template_id uuid;
  v_source_version_id uuid;
  v_source_version integer;
  v_source_title text;
  v_source_subject text;
  v_source_body text;
  v_revision jsonb;
  v_result jsonb;
  v_new_version_id uuid;
  v_snapshot_hash text;
  v_pack_two_snapshot_hash text;
  v_sibling_snapshot_hash text;
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    'public.clone_active_coach_content_pack(text,text,uuid,timestamp with time zone)',
    'public.revise_coach_draft_entries(uuid,jsonb,uuid,text,timestamp with time zone)',
    'public.revise_coach_assisted_draft_entries(uuid,jsonb,uuid,text,integer,integer,numeric,integer,text,timestamp with time zone)',
    'public.validate_coach_content_pack(uuid)',
    'public.schedule_coach_content_pack(uuid,uuid,timestamp with time zone,text,timestamp with time zone)',
    'public.approve_and_activate_coach_content_pack(uuid,uuid,text,timestamp with time zone)',
    'public.archive_coach_content_pack(uuid,uuid,timestamp with time zone)',
    'public.rollback_coach_content_pack(uuid,uuid,timestamp with time zone)'
  ]
  LOOP
    IF to_regprocedure(v_function) IS NULL THEN
      RAISE EXCEPTION 'missing governance function %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      CROSS JOIN LATERAL aclexplode(
        COALESCE(
          function_definition.proacl,
          acldefault('f', function_definition.proowner)
        )
      ) privilege
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND privilege.grantee = 0
        AND privilege.privilege_type = 'EXECUTE'
    ) OR has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'governance function privileges are not service-only for %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND function_definition.prosecdef
    ) THEN
      RAISE EXCEPTION 'governance function must remain SECURITY INVOKER: %', v_function;
    END IF;
  END LOOP;

  IF to_regprocedure(
    'public.schedule_coach_content_pack(uuid,uuid,timestamp with time zone,timestamp with time zone)'
  ) IS NOT NULL
    OR to_regprocedure(
      'public.approve_and_activate_coach_content_pack(uuid,uuid,timestamp with time zone)'
    ) IS NOT NULL THEN
    RAISE EXCEPTION 'snapshot-less coach lifecycle functions are still available';
  END IF;

  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous
  ) VALUES (
    v_actor_id,
    'authenticated',
    'authenticated',
    'bodyflow-governance-test@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  );

  v_result := public.clone_active_coach_content_pack(
    'bodyflow-governance-test-one',
    'BodyFlow governance test one',
    v_actor_id,
    timestamptz '2026-08-01 12:00:00+00'
  );
  v_pack_one_id := (v_result->>'pack_id')::uuid;

  IF v_result->>'outcome' <> 'cloned'
    OR (v_result->>'entry_count')::integer <> 1080
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_content_packs pack
      JOIN public.coach_content_packs parent ON parent.id = pack.parent_pack_id
      WHERE pack.id = v_pack_one_id
        AND pack.status = 'draft'
        AND pack.created_by = v_actor_id
        AND parent.status = 'active'
    ) THEN
    RAISE EXCEPTION 'active pack clone was not created as a complete draft';
  END IF;

  SELECT
    entry.template_id,
    entry.template_version_id,
    version.version,
    version.title,
    version.subject,
    version.body
  INTO
    v_template_id,
    v_source_version_id,
    v_source_version,
    v_source_title,
    v_source_subject,
    v_source_body
  FROM public.coach_content_pack_entries entry
  JOIN public.coach_message_templates template ON template.id = entry.template_id
  JOIN public.coach_message_template_versions version
    ON version.id = entry.template_version_id
  WHERE entry.pack_id = v_pack_one_id
    AND template.channel = 'in_app'
  ORDER BY template.template_key
  LIMIT 1;

  v_revision := jsonb_build_array(jsonb_build_object(
    'template_id', v_template_id,
    'expected_template_version_id', v_source_version_id,
    'title', v_source_title,
    'subject', v_source_subject,
    'body', v_source_body || ' Revisão sintética segura.'
  ));

  v_result := public.revise_coach_draft_entries(
    v_pack_one_id,
    v_revision,
    v_actor_id,
    'human',
    timestamptz '2026-08-01 12:05:00+00'
  );
  v_new_version_id := (v_result->'revisions'->0->>'template_version_id')::uuid;

  IF v_result->>'outcome' <> 'revised'
    OR (v_result->>'revision_count')::integer <> 1
    OR v_new_version_id = v_source_version_id
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_message_template_versions version
      WHERE version.id = v_new_version_id
        AND version.template_id = v_template_id
        AND version.version = v_source_version + 1
        AND version.status = 'draft'
        AND version.provenance = 'human'
        AND version.authored_by = v_actor_id
    )
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries entry
      WHERE entry.pack_id = v_pack_one_id
        AND entry.template_id = v_template_id
        AND entry.template_version_id = v_new_version_id
    ) THEN
    RAISE EXCEPTION 'draft revision was not inserted immutably';
  END IF;

  BEGIN
    PERFORM public.revise_coach_draft_entries(
      v_pack_one_id,
      v_revision,
      v_actor_id,
      'human',
      timestamptz '2026-08-01 12:06:00+00'
    );
    RAISE EXCEPTION 'stale draft revision was accepted';
  EXCEPTION
    WHEN serialization_failure THEN NULL;
  END;

  v_result := public.validate_coach_content_pack(v_pack_one_id);
  IF NOT (v_result->>'valid')::boolean
    OR (v_result->>'entry_count')::integer <> 1080
    OR (v_result->>'valid_entry_count')::integer <> 1080
    OR v_result->>'snapshot_hash' !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'complete draft pack did not validate';
  END IF;
  v_snapshot_hash := v_result->>'snapshot_hash';

  v_revision := jsonb_build_array(jsonb_build_object(
    'template_id', v_template_id,
    'expected_template_version_id', v_new_version_id,
    'title', v_source_title,
    'subject', v_source_subject,
    'body', v_source_body || ' Segunda revisão sintética segura.'
  ));
  v_result := public.revise_coach_assisted_draft_entries(
    v_pack_one_id,
    v_revision,
    v_actor_id,
    'anthropic/claude-haiku-4.5',
    700,
    800,
    0.002,
    450,
    'focus|progress|pt-BR',
    timestamptz '2026-08-01 12:07:00+00'
  );
  v_new_version_id := (v_result->'revisions'->0->>'template_version_id')::uuid;

  IF NOT EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id = v_actor_id
      AND audit.action = 'coach_assisted_rewrite.stored'
      AND audit.entity = 'coach_message_group'
      AND audit.after = jsonb_build_object(
        'pack_id', v_pack_one_id,
        'group_key', 'focus|progress|pt-BR',
        'status', 'stored',
        'model', 'anthropic/claude-haiku-4.5',
        'prompt_tokens', 700,
        'completion_tokens', 800,
        'cost_usd', 0.002,
        'latency_ms', 450
      )
  ) THEN
    RAISE EXCEPTION 'assisted revision telemetry was not stored atomically';
  END IF;

  BEGIN
    PERFORM public.schedule_coach_content_pack(
      v_pack_one_id,
      v_actor_id,
      timestamptz '2026-09-01 12:00:00+00',
      v_snapshot_hash,
      timestamptz '2026-08-01 12:09:00+00'
    );
    RAISE EXCEPTION 'stale validated snapshot was scheduled';
  EXCEPTION
    WHEN serialization_failure THEN NULL;
  END;

  v_result := public.validate_coach_content_pack(v_pack_one_id);
  v_snapshot_hash := v_result->>'snapshot_hash';

  v_result := public.schedule_coach_content_pack(
    v_pack_one_id,
    v_actor_id,
    timestamptz '2026-09-01 12:00:00+00',
    v_snapshot_hash,
    timestamptz '2026-08-01 12:10:00+00'
  );
  IF v_result->>'outcome' <> 'scheduled'
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_content_packs pack
      WHERE pack.id = v_pack_one_id
        AND pack.status = 'scheduled'
        AND pack.approved_by = v_actor_id
        AND pack.approved_at = timestamptz '2026-08-01 12:10:00+00'
        AND pack.effective_at = timestamptz '2026-09-01 12:00:00+00'
    ) THEN
    RAISE EXCEPTION 'complete draft pack was not scheduled';
  END IF;

  v_result := public.approve_and_activate_coach_content_pack(
    v_pack_one_id,
    v_actor_id,
    v_snapshot_hash,
    timestamptz '2026-09-01 12:00:00+00'
  );
  IF v_result->>'outcome' <> 'activated'
    OR (SELECT status FROM public.coach_content_packs WHERE id = v_pack_one_id) <> 'active' THEN
    RAISE EXCEPTION 'scheduled pack was not activated atomically';
  END IF;

  v_result := public.clone_active_coach_content_pack(
    'bodyflow-governance-test-two',
    'BodyFlow governance test two',
    v_actor_id,
    timestamptz '2026-09-01 12:05:00+00'
  );
  v_pack_two_id := (v_result->>'pack_id')::uuid;
  v_pack_two_snapshot_hash := public.validate_coach_content_pack(v_pack_two_id)->>'snapshot_hash';

  v_result := public.clone_active_coach_content_pack(
    'bodyflow-governance-test-sibling',
    'BodyFlow governance test sibling',
    v_actor_id,
    timestamptz '2026-09-01 12:06:00+00'
  );
  v_pack_sibling_id := (v_result->>'pack_id')::uuid;
  v_sibling_snapshot_hash := public.validate_coach_content_pack(v_pack_sibling_id)->>'snapshot_hash';

  v_result := public.approve_and_activate_coach_content_pack(
    v_pack_two_id,
    v_actor_id,
    v_pack_two_snapshot_hash,
    timestamptz '2026-09-01 12:10:00+00'
  );
  IF v_result->>'outcome' <> 'activated'
    OR (SELECT status FROM public.coach_content_packs WHERE id = v_pack_two_id) <> 'active'
    OR (SELECT status FROM public.coach_content_packs WHERE id = v_pack_one_id) <> 'archived' THEN
    RAISE EXCEPTION 'approved draft was not activated atomically';
  END IF;

  BEGIN
    PERFORM public.approve_and_activate_coach_content_pack(
      v_pack_sibling_id,
      v_actor_id,
      v_sibling_snapshot_hash,
      timestamptz '2026-09-01 12:11:00+00'
    );
    RAISE EXCEPTION 'stale sibling pack replaced a newer active pack';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  PERFORM public.archive_coach_content_pack(
    v_pack_sibling_id,
    v_actor_id,
    timestamptz '2026-09-01 12:12:00+00'
  );

  v_result := public.approve_and_activate_coach_content_pack(
    v_pack_two_id,
    v_actor_id,
    v_pack_two_snapshot_hash,
    timestamptz '2026-09-01 12:10:00+00'
  );
  IF v_result->>'outcome' <> 'already_active'
    OR (
      SELECT count(*)
      FROM public.audit_log audit
      WHERE audit.actor_id = v_actor_id
        AND audit.action = 'coach_pack.activate'
        AND audit.entity_id = v_pack_two_id::text
    ) <> 1 THEN
    RAISE EXCEPTION 'activation retry was not idempotent';
  END IF;

  PERFORM public.rollback_coach_content_pack(
    v_pack_one_id,
    v_actor_id,
    timestamptz '2026-09-01 12:15:00+00'
  );
  IF (SELECT status FROM public.coach_content_packs WHERE id = v_pack_one_id) <> 'active'
    OR (SELECT status FROM public.coach_content_packs WHERE id = v_pack_two_id) <> 'archived' THEN
    RAISE EXCEPTION 'one-step rollback did not archive the replaced pack';
  END IF;

  v_result := public.clone_active_coach_content_pack(
    'bodyflow-governance-test-three',
    'BodyFlow governance test three',
    v_actor_id,
    timestamptz '2026-09-01 12:20:00+00'
  );
  v_pack_three_id := (v_result->>'pack_id')::uuid;

  DELETE FROM public.coach_content_pack_entries
  WHERE pack_id = v_pack_three_id
    AND template_id = (
      SELECT entry.template_id
      FROM public.coach_content_pack_entries entry
      WHERE entry.pack_id = v_pack_three_id
      ORDER BY entry.template_id
      LIMIT 1
    );

  v_result := public.validate_coach_content_pack(v_pack_three_id);
  IF (v_result->>'valid')::boolean
    OR (v_result->>'entry_count')::integer <> 1079 THEN
    RAISE EXCEPTION 'incomplete draft pack was accepted by validation';
  END IF;
  v_snapshot_hash := v_result->>'snapshot_hash';

  BEGIN
    PERFORM public.schedule_coach_content_pack(
      v_pack_three_id,
      v_actor_id,
      timestamptz '2026-10-01 12:00:00+00',
      v_snapshot_hash,
      timestamptz '2026-09-01 12:25:00+00'
    );
    RAISE EXCEPTION 'incomplete draft pack was scheduled';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  PERFORM public.archive_coach_content_pack(
    v_pack_three_id,
    v_actor_id,
    timestamptz '2026-09-01 12:30:00+00'
  );

  IF EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id = v_actor_id
      AND (
        COALESCE(audit.before, '{}'::jsonb) ?| ARRAY['body', 'title', 'subject', 'prompt']
        OR COALESCE(audit.after, '{}'::jsonb) ?| ARRAY['body', 'title', 'subject', 'prompt']
      )
  ) THEN
    RAISE EXCEPTION 'coach governance audit telemetry contains message copy';
  END IF;

  IF (
    SELECT count(DISTINCT audit.action)
    FROM public.audit_log audit
    WHERE audit.actor_id = v_actor_id
      AND audit.entity = 'coach_content_pack'
      AND audit.action IN (
        'coach_pack.clone',
        'coach_pack.revise',
        'coach_pack.schedule',
        'coach_pack.activate',
        'coach_pack.archive',
        'coach_pack.rollback'
      )
  ) <> 6 THEN
    RAISE EXCEPTION 'coach governance audit trail is incomplete';
  END IF;
END;
$test$;

ROLLBACK;

BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Fail first and clearly when Task 2 has not been implemented yet.
DO $test$
DECLARE
  v_relation text;
BEGIN
  FOREACH v_relation IN ARRAY ARRAY[
    'content_publications',
    'content_assets',
    'content_versions',
    'content_version_target_protocols',
    'content_version_target_plans',
    'content_version_target_personalities',
    'content_user_state',
    'content_events'
  ]
  LOOP
    IF to_regclass('public.' || v_relation) IS NULL THEN
      RAISE EXCEPTION 'missing relation public.%', v_relation;
    END IF;
  END LOOP;
END;
$test$;

DO $test$
DECLARE
  v_relation text;
  v_function text;
  v_index text;
  v_trigger text;
  v_constraint text;
BEGIN
  FOREACH v_relation IN ARRAY ARRAY[
    'content_publications',
    'content_assets',
    'content_versions',
    'content_version_target_protocols',
    'content_version_target_plans',
    'content_version_target_personalities',
    'content_user_state',
    'content_events'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND relation.relname = v_relation
        AND relation.relkind = 'r'
        AND relation.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'RLS is not enabled on public.%', v_relation;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
      CROSS JOIN LATERAL aclexplode(
        COALESCE(relation.relacl, acldefault('r', relation.relowner))
      ) privilege
      WHERE namespace.nspname = 'public'
        AND relation.relname = v_relation
        AND (
          privilege.grantee = 0
          OR privilege.grantee IN (
            (SELECT oid FROM pg_roles WHERE rolname = 'anon'),
            (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
          )
        )
    ) THEN
      RAISE EXCEPTION 'client or PUBLIC table privilege remains on public.%', v_relation;
    END IF;

    IF NOT has_table_privilege('service_role', 'public.' || v_relation, 'SELECT')
      OR NOT has_table_privilege('service_role', 'public.' || v_relation, 'INSERT')
      OR NOT has_table_privilege('service_role', 'public.' || v_relation, 'UPDATE')
      OR NOT has_table_privilege('service_role', 'public.' || v_relation, 'DELETE') THEN
      RAISE EXCEPTION 'service_role lacks explicit CRUD privileges on public.%', v_relation;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_class relation
      CROSS JOIN LATERAL aclexplode(relation.relacl) privilege
      WHERE relation.oid = ('public.' || v_relation)::regclass
        AND privilege.grantee <> relation.relowner
        AND privilege.grantee <> (SELECT oid FROM pg_roles WHERE rolname = 'service_role')
    ) OR (
      SELECT count(*)
      FROM pg_class relation
      CROSS JOIN LATERAL aclexplode(relation.relacl) privilege
      WHERE relation.oid = ('public.' || v_relation)::regclass
        AND privilege.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'service_role')
        AND privilege.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
    ) <> 4 THEN
      RAISE EXCEPTION 'CMS table grantees are not exactly owner plus service_role CRUD for public.%',
        v_relation;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_policy policy
      WHERE policy.polrelid = ('public.' || v_relation)::regclass
    ) THEN
      RAISE EXCEPTION 'service-only relation public.% unexpectedly has an RLS policy', v_relation;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = 'public'
      AND relation.relkind IN ('r', 'p')
      AND relation.relname LIKE 'content\_%' ESCAPE '\'
  ) <> 8 THEN
    RAISE EXCEPTION 'public CMS relation namespace must contain exactly eight tables';
  END IF;

  FOREACH v_function IN ARRAY ARRAY[
    'public.create_content_publication(uuid,text)',
    'public.create_content_draft(uuid,uuid,text,uuid)',
    'public.save_content_draft(uuid,uuid,timestamp with time zone,jsonb)',
    'public.submit_content_version(uuid,uuid,timestamp with time zone)',
    'public.review_content_version(uuid,uuid,text,text)',
    'public.publish_content_version(uuid,uuid,timestamp with time zone)',
    'public.archive_content_publication(uuid,uuid)',
    'public.create_content_asset(uuid,uuid,text,bigint,text)',
    'public.complete_content_asset(uuid,uuid,bigint,text)',
    'public.delete_content_asset(uuid,uuid)'
  ]
  LOOP
    IF to_regprocedure(v_function) IS NULL THEN
      RAISE EXCEPTION 'missing CMS function %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      CROSS JOIN LATERAL aclexplode(
        COALESCE(function_definition.proacl, acldefault('f', function_definition.proowner))
      ) privilege
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND (
          privilege.grantee = 0
          OR privilege.grantee IN (
            (SELECT oid FROM pg_roles WHERE rolname = 'anon'),
            (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
          )
        )
        AND privilege.privilege_type = 'EXECUTE'
    ) OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'CMS function privileges are not service-only for %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      CROSS JOIN LATERAL aclexplode(function_definition.proacl) privilege
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND privilege.grantee <> function_definition.proowner
        AND privilege.grantee <> (SELECT oid FROM pg_roles WHERE rolname = 'service_role')
    ) OR (
      SELECT count(*)
      FROM pg_proc function_definition
      CROSS JOIN LATERAL aclexplode(function_definition.proacl) privilege
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND privilege.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'service_role')
        AND privilege.privilege_type = 'EXECUTE'
    ) <> 1 THEN
      RAISE EXCEPTION 'CMS function grantees are not exactly owner plus service_role for %',
        v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND function_definition.prosecdef
    ) THEN
      RAISE EXCEPTION 'CMS function must remain SECURITY INVOKER: %', v_function;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND function_definition.proconfig @> ARRAY['search_path=public, pg_temp']
    ) THEN
      RAISE EXCEPTION 'CMS function lacks fixed public, pg_temp search_path: %', v_function;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM pg_proc function_definition
    JOIN pg_namespace namespace ON namespace.oid = function_definition.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_definition.proname IN (
        'create_content_publication',
        'create_content_draft',
        'save_content_draft',
        'submit_content_version',
        'review_content_version',
        'publish_content_version',
        'archive_content_publication',
        'create_content_asset',
        'complete_content_asset',
        'delete_content_asset'
      )
  ) <> 10 THEN
    RAISE EXCEPTION 'public CMS RPC namespace must contain exactly ten signatures';
  END IF;

  IF (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure('public.create_content_draft(uuid,uuid,text,uuid)')
  ) <> 1 OR (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure('public.review_content_version(uuid,uuid,text,text)')
  ) <> 1 OR (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure('public.publish_content_version(uuid,uuid,timestamp with time zone)')
  ) <> 1 THEN
    RAISE EXCEPTION 'CMS RPC defaults do not match the published contract';
  END IF;

  FOREACH v_index IN ARRAY ARRAY[
    'content_publications_slug_key',
    'content_versions_publication_version_key',
    'content_versions_one_draft_per_locale_idx',
    'content_versions_visibility_idx',
    'content_versions_cover_asset_idx',
    'content_assets_object_path_key',
    'content_version_target_protocols_pkey',
    'content_version_target_plans_pkey',
    'content_version_target_personalities_pkey',
    'content_user_state_pkey',
    'content_events_user_event_key_key',
    'content_events_publication_created_idx'
  ]
  LOOP
    IF to_regclass('public.' || v_index) IS NULL THEN
      RAISE EXCEPTION 'missing CMS index public.%', v_index;
    END IF;
  END LOOP;

  FOREACH v_constraint IN ARRAY ARRAY[
    'content_publications_slug_check',
    'content_publications_version_counter_check',
    'content_publications_archive_pair_check',
    'content_assets_mime_type_check',
    'content_assets_size_check',
    'content_assets_path_check',
    'content_assets_status_check',
    'content_assets_status_consistency_check',
    'content_versions_locale_check',
    'content_versions_state_check',
    'content_versions_category_check',
    'content_versions_title_check',
    'content_versions_excerpt_check',
    'content_versions_body_markdown_check',
    'content_versions_body_hash_check',
    'content_versions_reading_time_check',
    'content_versions_tags_check',
    'content_versions_review_pair_check',
    'content_versions_publish_pair_check',
    'content_versions_state_metadata_check',
    'content_versions_lifecycle_chronology_check',
    'content_user_state_origin_check',
    'content_events_type_check',
    'content_events_origin_check',
    'content_events_key_hash_check'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint constraint_definition
      WHERE constraint_definition.conname = v_constraint
        AND constraint_definition.connamespace = 'public'::regnamespace
    ) THEN
      RAISE EXCEPTION 'missing CMS constraint %', v_constraint;
    END IF;
  END LOOP;

  FOREACH v_trigger IN ARRAY ARRAY[
    'guard_content_publication_mutation',
    'guard_content_asset_mutation',
    'prepare_content_version_mutation',
    'guard_content_version_delete',
    'validate_content_version_cover',
    'guard_content_protocol_target_mutation',
    'guard_content_plan_target_mutation',
    'guard_content_personality_target_mutation',
    'validate_content_personality_target',
    'touch_content_user_state_updated_at',
    'guard_content_events_immutable'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_trigger trigger_definition
      JOIN pg_class relation ON relation.oid = trigger_definition.tgrelid
      JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND trigger_definition.tgname = v_trigger
        AND NOT trigger_definition.tgisinternal
    ) THEN
      RAISE EXCEPTION 'missing CMS trigger %', v_trigger;
    END IF;
  END LOOP;

  IF (
    SELECT attribute.atttypid
    FROM pg_attribute attribute
    WHERE attribute.attrelid = 'public.content_version_target_protocols'::regclass
      AND attribute.attname = 'protocol'
      AND NOT attribute.attisdropped
  ) <> 'public.protocol_enum'::regtype THEN
    RAISE EXCEPTION 'protocol targets do not use public.protocol_enum';
  END IF;

  IF (
    SELECT attribute.atttypid
    FROM pg_attribute attribute
    WHERE attribute.attrelid = 'public.content_version_target_plans'::regclass
      AND attribute.attname = 'plan'
      AND NOT attribute.attisdropped
  ) <> 'public.plan_enum'::regtype THEN
    RAISE EXCEPTION 'plan targets do not use public.plan_enum';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint constraint_definition
    WHERE constraint_definition.conrelid = 'public.content_version_target_personalities'::regclass
      AND constraint_definition.confrelid = 'public.coach_personalities'::regclass
      AND constraint_definition.contype = 'f'
  ) THEN
    RAISE EXCEPTION 'personality targets do not reference coach_personalities(code)';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint constraint_definition
    WHERE constraint_definition.conrelid = 'public.content_assets'::regclass
      AND constraint_definition.confrelid = 'public.media_assets'::regclass
  ) THEN
    RAISE EXCEPTION 'content_assets improperly reuses media_assets';
  END IF;

  IF (
    SELECT count(*)
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN (
        'content_publications',
        'content_assets',
        'content_versions',
        'content_version_target_protocols',
        'content_version_target_plans',
        'content_version_target_personalities',
        'content_user_state',
        'content_events'
      )
      AND column_name ILIKE '%body%'
  ) <> 2 OR NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'content_versions'
      AND column_name IN ('body_markdown', 'body_hash')
  ) THEN
    RAISE EXCEPTION 'article body data is not confined to content_versions';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM storage.buckets bucket
    WHERE bucket.id = 'content-covers'
      AND NOT bucket.public
      AND bucket.file_size_limit = 10485760
      AND bucket.allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
  ) THEN
    RAISE EXCEPTION 'existing content-covers bucket contract changed or is missing';
  END IF;


  IF position(
    'FOR SHARE' IN upper(pg_get_functiondef('private.validate_content_version_cover()'::regprocedure))
  ) = 0 THEN
    RAISE EXCEPTION 'cover attachment guard does not take a delete-conflicting row lock';
  END IF;

  IF position(
    'FOR UPDATE' IN upper(pg_get_functiondef('private.guard_content_target_mutation()'::regprocedure))
  ) = 0 THEN
    RAISE EXCEPTION 'target mutation guard does not serialize on the parent version row';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc function_definition
    JOIN pg_namespace namespace ON namespace.oid = function_definition.pronamespace
    WHERE namespace.nspname IN ('public', 'private')
      AND function_definition.prokind = 'f'
      AND pg_get_functiondef(function_definition.oid) ~ 'bodyflow\\.content_(publication|version|asset)_write'
  ) THEN
    RAISE EXCEPTION 'CMS lifecycle functions retain transaction-local bypass GUCs';
  END IF;
END;
$test$;

SET LOCAL ROLE anon;
DO $test$
DECLARE
  v_table_denied boolean := false;
  v_rpc_denied boolean := false;
BEGIN
  IF current_user <> 'anon' THEN
    RAISE EXCEPTION 'anon denial probe is not executing as anon';
  END IF;
  BEGIN
    PERFORM count(*) FROM public.content_publications;
  EXCEPTION WHEN insufficient_privilege THEN
    v_table_denied := true;
  END;
  BEGIN
    PERFORM public.create_content_publication(NULL, 'anon-runtime-denial');
  EXCEPTION WHEN insufficient_privilege THEN
    v_rpc_denied := true;
  END;
  IF NOT v_table_denied OR NOT v_rpc_denied THEN
    RAISE EXCEPTION 'PUBLIC/anon runtime access to CMS table or RPC was not denied';
  END IF;
END;
$test$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_table_denied boolean := false;
  v_rpc_denied boolean := false;
BEGIN
  IF current_user <> 'authenticated' THEN
    RAISE EXCEPTION 'authenticated denial probe is not executing as authenticated';
  END IF;
  BEGIN
    PERFORM count(*) FROM public.content_publications;
  EXCEPTION WHEN insufficient_privilege THEN
    v_table_denied := true;
  END;
  BEGIN
    PERFORM public.create_content_publication(NULL, 'authenticated-runtime-denial');
  EXCEPTION WHEN insufficient_privilege THEN
    v_rpc_denied := true;
  END;
  IF NOT v_table_denied OR NOT v_rpc_denied THEN
    RAISE EXCEPTION 'authenticated runtime access to CMS table or RPC was not denied';
  END IF;
END;
$test$;
RESET ROLE;

DO $test$
DECLARE
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000000981';
  v_reviewer_id constant uuid := '00000000-0000-0000-0000-000000000982';
  v_master_id constant uuid := '00000000-0000-0000-0000-000000000983';
  v_patient_auth_id constant uuid := '00000000-0000-0000-0000-000000000984';
  v_patient_id constant uuid := '00000000-0000-0000-0000-000000000985';
  v_editor_two_id constant uuid := '00000000-0000-0000-0000-000000000986';
BEGIN
  INSERT INTO auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous
  ) VALUES
    (v_editor_id, 'authenticated', 'authenticated', 'content-cms-editor@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_reviewer_id, 'authenticated', 'authenticated', 'content-cms-reviewer@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_master_id, 'authenticated', 'authenticated', 'content-cms-master@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_patient_auth_id, 'authenticated', 'authenticated', 'content-cms-patient@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_editor_two_id, 'authenticated', 'authenticated', 'content-cms-editor-two@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

  INSERT INTO public.admin_users (id, email, role)
  VALUES
    (v_editor_id, 'content-cms-editor@example.com', 'content_editor'),
    (v_reviewer_id, 'content-cms-reviewer@example.com', 'nutrition_admin'),
    (v_master_id, 'content-cms-master@example.com', 'master_admin'),
    (v_editor_two_id, 'content-cms-editor-two@example.com', 'content_editor');

  INSERT INTO public.users (id, auth_user_id, email, wpp, name)
  VALUES (v_patient_id, v_patient_auth_id, 'content-cms-patient@example.com', NULL, 'Synthetic CMS Patient');
END;
$test$;

SET LOCAL ROLE service_role;

DO $test$
DECLARE
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000000981';
  v_reviewer_id constant uuid := '00000000-0000-0000-0000-000000000982';
  v_master_id constant uuid := '00000000-0000-0000-0000-000000000983';
  v_patient_auth_id constant uuid := '00000000-0000-0000-0000-000000000984';
  v_patient_id constant uuid := '00000000-0000-0000-0000-000000000985';
  v_editor_two_id constant uuid := '00000000-0000-0000-0000-000000000986';
  v_asset_id constant uuid := '00000000-0000-0000-0000-000000000991';
  v_deleted_asset_id constant uuid := '00000000-0000-0000-0000-000000000992';
  v_publication_id uuid;
  v_second_publication_id uuid;
  v_version_pt_id uuid;
  v_version_en_id uuid;
  v_version_en_replacement_id uuid;
  v_result jsonb;
  v_draft jsonb;
  v_en_draft jsonb;
  v_body text := '## Synthetic guidance' || E'\n\n' || repeat('word ', 205);
  v_initial_updated_at timestamptz;
  v_expected_updated_at timestamptz;
  v_hash text;
  v_role_denied_editor_review boolean := false;
  v_role_denied_editor_publish boolean := false;
  v_role_denied_nutrition_author boolean := false;
  v_role_denied_nutrition_publish boolean := false;
  v_role_denied_master_author boolean := false;
  v_role_denied_master_review boolean := false;
BEGIN
  IF current_user <> 'service_role' THEN
    RAISE EXCEPTION 'CMS success workflow is not executing as service_role';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.users domain_user
    WHERE domain_user.id IN (v_editor_id, v_reviewer_id, v_master_id)
  ) THEN
    RAISE EXCEPTION 'synthetic CMS admins overlap patient identities';
  END IF;

  BEGIN
    INSERT INTO public.content_publications (slug, version_counter, created_by)
    VALUES ('direct-malformed-publication', 1, v_editor_id);
    RAISE EXCEPTION 'direct publication insert accepted a nonzero version counter';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_publications (
      slug,
      created_by,
      archived_by,
      archived_at
    ) VALUES (
      'direct-lifecycle-publication',
      v_editor_id,
      v_master_id,
      clock_timestamp()
    );
    RAISE EXCEPTION 'direct publication insert accepted archive lifecycle metadata';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_publications (slug, created_by)
    VALUES ('direct-wrong-role-publication', v_reviewer_id);
    RAISE EXCEPTION 'direct publication insert accepted a non-editor creator';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_assets (
      id,
      object_path,
      mime_type,
      declared_size_bytes,
      actual_size_bytes,
      etag,
      status,
      created_by,
      uploaded_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000997',
      'content/00000000-0000-0000-0000-000000000997.jpg',
      'image/jpeg',
      100,
      100,
      'forged-etag',
      'uploaded',
      v_editor_id,
      clock_timestamp()
    );
    RAISE EXCEPTION 'direct asset insert accepted an uploaded lifecycle state';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_assets (
      id,
      object_path,
      mime_type,
      declared_size_bytes,
      created_by
    ) VALUES (
      '00000000-0000-0000-0000-000000000998',
      'content/00000000-0000-0000-0000-000000000998.png',
      'image/png',
      100,
      v_reviewer_id
    );
    RAISE EXCEPTION 'direct asset insert accepted a non-editor creator';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_publication(v_editor_id, 'Bad Slug');
    RAISE EXCEPTION 'invalid publication slug was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_publication(v_reviewer_id, 'reviewer-created-publication');
    RAISE EXCEPTION 'nutrition_admin created a content publication';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_publication(v_master_id, 'master-created-publication');
    RAISE EXCEPTION 'master_admin created a content publication';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  v_result := public.create_content_publication(v_editor_id, 'synthetic-health-guide');
  v_publication_id := (v_result->>'publication_id')::uuid;

  IF v_result->>'slug' <> 'synthetic-health-guide' OR NOT EXISTS (
    SELECT 1
    FROM public.content_publications publication
    WHERE publication.id = v_publication_id
      AND publication.slug = 'synthetic-health-guide'
      AND publication.created_by = v_editor_id
      AND publication.version_counter = 0
      AND publication.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'content publication was not created correctly';
  END IF;

  v_result := public.create_content_publication(v_editor_id, 'synthetic-archive-guard');
  v_second_publication_id := (v_result->>'publication_id')::uuid;

  BEGIN
    UPDATE public.content_publications
    SET slug = 'changed-synthetic-health-guide'
    WHERE id = v_publication_id;
    RAISE EXCEPTION 'publication slug was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_draft(v_editor_id, v_publication_id, 'es-ES');
    RAISE EXCEPTION 'unsupported locale draft was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_draft(v_reviewer_id, v_publication_id, 'pt-BR');
    RAISE EXCEPTION 'nutrition_admin created a content draft';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_draft(v_master_id, v_publication_id, 'pt-BR');
    RAISE EXCEPTION 'master_admin created a content draft';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_versions (
      id,
      publication_id,
      version,
      locale,
      category,
      title,
      excerpt,
      body_markdown,
      state,
      authored_by,
      submitted_at,
      reviewed_by,
      reviewed_at,
      published_by,
      published_at,
      publish_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000971',
      v_publication_id,
      1,
      'pt-BR',
      'nutrition',
      'Direct approved insertion',
      'A direct lifecycle insertion that must never be accepted by persistence.',
      v_body,
      'approved',
      v_editor_id,
      clock_timestamp(),
      v_reviewer_id,
      clock_timestamp(),
      v_master_id,
      clock_timestamp(),
      clock_timestamp()
    );
    RAISE EXCEPTION 'direct version insert accepted an approved and published lifecycle state';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_versions (
      id,
      publication_id,
      version,
      locale,
      state,
      authored_by,
      submitted_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000972',
      v_publication_id,
      1,
      'pt-BR',
      'draft',
      v_editor_id,
      clock_timestamp()
    );
    RAISE EXCEPTION 'direct version insert accepted lifecycle metadata on a draft';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.content_versions (
      id,
      publication_id,
      version,
      locale,
      authored_by
    ) VALUES (
      '00000000-0000-0000-0000-000000000973',
      v_publication_id,
      1,
      'pt-BR',
      v_reviewer_id
    );
    RAISE EXCEPTION 'direct version insert accepted a non-editor author';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_result := public.create_content_draft(v_editor_id, v_publication_id, 'pt-BR');
  v_version_pt_id := (v_result->>'version_id')::uuid;
  IF (v_result->>'version')::integer <> 1 THEN
    RAISE EXCEPTION 'first publication version was not version 1';
  END IF;

  BEGIN
    UPDATE public.content_publications
    SET version_counter = version_counter + 5
    WHERE id = v_publication_id;
    RAISE EXCEPTION 'create_content_draft leaked its allocation guard';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  SELECT updated_at
  INTO v_initial_updated_at
  FROM public.content_versions
  WHERE id = v_version_pt_id;

  BEGIN
    PERFORM public.create_content_draft(v_editor_id, v_publication_id, 'pt-BR');
    RAISE EXCEPTION 'second draft for the same publication locale was accepted';
  EXCEPTION
    WHEN unique_violation OR check_violation THEN NULL;
  END;

  v_result := public.create_content_draft(v_editor_id, v_publication_id, 'en-US');
  v_version_en_id := (v_result->>'version_id')::uuid;
  IF (v_result->>'version')::integer <> 2 OR (
    SELECT version_counter
    FROM public.content_publications
    WHERE id = v_publication_id
  ) <> 2 THEN
    RAISE EXCEPTION 'publication versions are not allocated monotonically';
  END IF;

  BEGIN
    UPDATE public.content_publications
    SET version_counter = 1
    WHERE id = v_publication_id;
    RAISE EXCEPTION 'publication version counter moved backwards';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_draft := jsonb_build_object(
    'locale', 'pt-BR',
    'category', 'nutrition',
    'title', 'Synthetic nutrition guidance',
    'excerpt', 'A synthetic excerpt long enough for strict persistence validation.',
    'bodyMarkdown', v_body,
    'tags', jsonb_build_array('health-basics', 'daily-habits'),
    'featuredToday', true,
    'coverAssetId', NULL,
    'targeting', jsonb_build_object(
      'protocols', jsonb_build_array('recomposicao'),
      'plans', jsonb_build_array('mensal'),
      'personalities', jsonb_build_array('balanced')
    )
  );

  BEGIN
    PERFORM public.save_content_draft(
      v_reviewer_id,
      v_version_pt_id,
      v_initial_updated_at,
      v_draft
    );
    RAISE EXCEPTION 'nutrition_admin saved a content draft';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.save_content_draft(
      v_master_id,
      v_version_pt_id,
      v_initial_updated_at,
      v_draft
    );
    RAISE EXCEPTION 'master_admin saved a content draft';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.save_content_draft(v_editor_id, v_version_pt_id, v_initial_updated_at, v_draft);
    RAISE EXCEPTION 'non-selectable balanced personality target was accepted';
  EXCEPTION
    WHEN check_violation OR foreign_key_violation THEN NULL;
  END;

  v_draft := jsonb_set(v_draft, '{targeting,personalities}', '["focus"]'::jsonb);
  v_result := public.save_content_draft(v_editor_id, v_version_pt_id, v_initial_updated_at, v_draft);
  v_expected_updated_at := (v_result->>'updated_at')::timestamptz;

  BEGIN
    PERFORM public.save_content_draft(v_editor_id, v_version_pt_id, v_initial_updated_at, v_draft);
    RAISE EXCEPTION 'stale content draft write was accepted';
  EXCEPTION
    WHEN serialization_failure THEN NULL;
  END;

  SELECT version.body_hash
  INTO v_hash
  FROM public.content_versions version
  WHERE version.id = v_version_pt_id;

  IF v_hash <> encode(extensions.digest(convert_to(v_body, 'UTF8'), 'sha256'), 'hex')
    OR (SELECT reading_time_minutes FROM public.content_versions WHERE id = v_version_pt_id) <> 2 THEN
    RAISE EXCEPTION 'database did not recompute body hash and reading time';
  END IF;

  IF (
    SELECT count(*)
    FROM public.content_version_target_protocols target
    WHERE target.content_version_id = v_version_pt_id
      AND target.protocol = 'recomposicao'::public.protocol_enum
  ) <> 1 OR (
    SELECT count(*)
    FROM public.content_version_target_plans target
    WHERE target.content_version_id = v_version_pt_id
      AND target.plan = 'mensal'::public.plan_enum
  ) <> 1 OR (
    SELECT count(*)
    FROM public.content_version_target_personalities target
    WHERE target.content_version_id = v_version_pt_id
      AND target.personality_code = 'focus'
  ) <> 1 THEN
    RAISE EXCEPTION 'initial content targets were not persisted';
  END IF;

  v_draft := jsonb_set(v_draft, '{targeting}', jsonb_build_object(
    'protocols', jsonb_build_array('ganho_massa'),
    'plans', '[]'::jsonb,
    'personalities', jsonb_build_array('zen')
  ));
  v_result := public.save_content_draft(v_editor_id, v_version_pt_id, v_expected_updated_at, v_draft);
  v_expected_updated_at := (v_result->>'updated_at')::timestamptz;

  IF EXISTS (
    SELECT 1
    FROM public.content_version_target_protocols target
    WHERE target.content_version_id = v_version_pt_id
      AND target.protocol = 'recomposicao'::public.protocol_enum
  ) OR EXISTS (
    SELECT 1
    FROM public.content_version_target_plans target
    WHERE target.content_version_id = v_version_pt_id
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.content_version_target_protocols target
    WHERE target.content_version_id = v_version_pt_id
      AND target.protocol = 'ganho_massa'::public.protocol_enum
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.content_version_target_personalities target
    WHERE target.content_version_id = v_version_pt_id
      AND target.personality_code = 'zen'
  ) THEN
    RAISE EXCEPTION 'save_content_draft did not replace targets atomically';
  END IF;

  BEGIN
    PERFORM public.create_content_asset(
      v_editor_id,
      '00000000-0000-0000-0000-000000000993',
      'image/svg+xml',
      100,
      'content/00000000-0000-0000-0000-000000000993.svg'
    );
    RAISE EXCEPTION 'SVG content cover was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_asset(
      v_editor_id,
      '00000000-0000-0000-0000-000000000994',
      'image/jpeg',
      10485761,
      'content/00000000-0000-0000-0000-000000000994.jpg'
    );
    RAISE EXCEPTION 'oversized content cover was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_asset(
      v_editor_id,
      '00000000-0000-0000-0000-000000000995',
      'image/png',
      100,
      'content/wrong-name.png'
    );
    RAISE EXCEPTION 'non-server-shaped content cover path was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_asset(
      v_reviewer_id,
      '00000000-0000-0000-0000-000000000974',
      'image/jpeg',
      100,
      'content/00000000-0000-0000-0000-000000000974.jpg'
    );
    RAISE EXCEPTION 'nutrition_admin created a content asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_asset(
      v_master_id,
      '00000000-0000-0000-0000-000000000975',
      'image/jpeg',
      100,
      'content/00000000-0000-0000-0000-000000000975.jpg'
    );
    RAISE EXCEPTION 'master_admin created a content asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM public.create_content_asset(
    v_editor_id,
    v_asset_id,
    'image/jpeg',
    4096,
    'content/' || v_asset_id::text || '.jpg'
  );

  v_draft := jsonb_set(v_draft, '{coverAssetId}', to_jsonb(v_asset_id::text));
  BEGIN
    PERFORM public.save_content_draft(v_editor_id, v_version_pt_id, v_expected_updated_at, v_draft);
    RAISE EXCEPTION 'pending content cover was attached to a draft';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.complete_content_asset(v_reviewer_id, v_asset_id, 4096, 'synthetic-etag');
    RAISE EXCEPTION 'nutrition_admin completed a content asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.complete_content_asset(v_master_id, v_asset_id, 4096, 'synthetic-etag');
    RAISE EXCEPTION 'master_admin completed a content asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.complete_content_asset(v_editor_two_id, v_asset_id, 4096, 'synthetic-etag');
    RAISE EXCEPTION 'non-owner content editor completed another editor asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    UPDATE public.content_assets
    SET actual_size_bytes = 4096,
        etag = 'direct-forged-etag',
        status = 'uploaded',
        uploaded_at = clock_timestamp()
    WHERE id = v_asset_id;
    RAISE EXCEPTION 'direct asset upload transition accepted a missing Storage object';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.complete_content_asset(v_editor_id, v_asset_id, 4096, 'synthetic-etag');
    RAISE EXCEPTION 'content cover completion accepted a missing Storage object';
  EXCEPTION
    WHEN foreign_key_violation OR check_violation THEN NULL;
  END;

  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES (
    'content-covers',
    'content/' || v_asset_id::text || '.jpg',
    jsonb_build_object('mimetype', 'image/jpeg', 'size', 4095, 'eTag', 'synthetic-etag')
  );

  BEGIN
    PERFORM public.complete_content_asset(v_editor_id, v_asset_id, 4096, 'synthetic-etag');
    RAISE EXCEPTION 'content cover completion accepted mismatched Storage metadata';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  UPDATE storage.objects
  SET metadata = jsonb_build_object(
    'mimetype', 'image/jpeg',
    'size', 4096
  )
  WHERE bucket_id = 'content-covers'
    AND name = 'content/' || v_asset_id::text || '.jpg';

  BEGIN
    PERFORM public.complete_content_asset(v_editor_id, v_asset_id, 4096, 'synthetic-etag');
    RAISE EXCEPTION 'content cover completion accepted missing Storage ETag metadata';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  UPDATE storage.objects
  SET metadata = metadata || jsonb_build_object('eTag', 'storage-etag')
  WHERE bucket_id = 'content-covers'
    AND name = 'content/' || v_asset_id::text || '.jpg';

  BEGIN
    PERFORM public.complete_content_asset(v_editor_id, v_asset_id, 4096, 'caller-etag');
    RAISE EXCEPTION 'content cover completion accepted a caller ETag mismatch';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_result := public.complete_content_asset(v_editor_id, v_asset_id, 4096, 'storage-etag');
  IF v_result->>'status' <> 'uploaded' OR NOT EXISTS (
    SELECT 1
    FROM public.content_assets asset
    WHERE asset.id = v_asset_id
      AND asset.bucket_id = 'content-covers'
      AND asset.object_path = 'content/' || v_asset_id::text || '.jpg'
      AND asset.status = 'uploaded'
      AND asset.actual_size_bytes = 4096
      AND asset.etag = 'storage-etag'
  ) THEN
    RAISE EXCEPTION 'matching content cover was not completed';
  END IF;

  BEGIN
    UPDATE public.content_assets
    SET etag = 'same-transaction-forged-etag'
    WHERE id = v_asset_id;
    RAISE EXCEPTION 'complete_content_asset leaked its lifecycle guard';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.content_assets
    SET status = 'pending_upload'
    WHERE id = v_asset_id;
    RAISE EXCEPTION 'uploaded content cover returned to pending state';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_result := public.save_content_draft(v_editor_id, v_version_pt_id, v_expected_updated_at, v_draft);
  v_expected_updated_at := (v_result->>'updated_at')::timestamptz;

  BEGIN
    PERFORM public.delete_content_asset(v_editor_id, v_asset_id);
    RAISE EXCEPTION 'referenced content cover was deleted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  PERFORM public.create_content_asset(
    v_editor_id,
    v_deleted_asset_id,
    'image/webp',
    1024,
    'content/' || v_deleted_asset_id::text || '.webp'
  );

  BEGIN
    PERFORM public.delete_content_asset(v_reviewer_id, v_deleted_asset_id);
    RAISE EXCEPTION 'nutrition_admin deleted a content asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.delete_content_asset(v_master_id, v_deleted_asset_id);
    RAISE EXCEPTION 'master_admin deleted a content asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.delete_content_asset(v_editor_two_id, v_deleted_asset_id);
    RAISE EXCEPTION 'non-owner content editor deleted another editor asset';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  v_result := public.delete_content_asset(v_editor_id, v_deleted_asset_id);
  IF v_result->>'status' <> 'deleted' OR (
    SELECT status
    FROM public.content_assets
    WHERE id = v_deleted_asset_id
  ) <> 'deleted' THEN
    RAISE EXCEPTION 'unreferenced pending content cover was not deleted';
  END IF;

  v_draft := jsonb_set(v_draft, '{coverAssetId}', to_jsonb(v_deleted_asset_id::text));
  BEGIN
    PERFORM public.save_content_draft(v_editor_id, v_version_pt_id, v_expected_updated_at, v_draft);
    RAISE EXCEPTION 'sequential attachment accepted a deleted content cover';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  v_draft := jsonb_set(v_draft, '{coverAssetId}', to_jsonb(v_asset_id::text));

  BEGIN
    PERFORM public.submit_content_version(v_reviewer_id, v_version_pt_id, v_expected_updated_at);
    RAISE EXCEPTION 'nutrition_admin performed content_editor submission';
  EXCEPTION
    WHEN insufficient_privilege THEN v_role_denied_nutrition_author := true;
  END;

  BEGIN
    PERFORM public.submit_content_version(v_master_id, v_version_pt_id, v_expected_updated_at);
    RAISE EXCEPTION 'master_admin performed content_editor submission';
  EXCEPTION
    WHEN insufficient_privilege THEN v_role_denied_master_author := true;
  END;

  BEGIN
    PERFORM public.submit_content_version(v_editor_id, v_version_pt_id, v_initial_updated_at);
    RAISE EXCEPTION 'stale content submission was accepted';
  EXCEPTION
    WHEN serialization_failure THEN NULL;
  END;

  INSERT INTO public.content_version_target_plans (content_version_id, plan)
  VALUES (v_version_pt_id, 'mensal');

  PERFORM public.submit_content_version(v_editor_id, v_version_pt_id, v_expected_updated_at);

  IF (
    SELECT state
    FROM public.content_versions
    WHERE id = v_version_pt_id
  ) <> 'in_review' THEN
    RAISE EXCEPTION 'content draft did not enter review';
  END IF;

  BEGIN
    UPDATE public.content_versions
    SET state = 'approved',
        reviewed_by = v_editor_id,
        reviewed_at = clock_timestamp()
    WHERE id = v_version_pt_id;
    RAISE EXCEPTION 'submit_content_version leaked its lifecycle guard';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.content_versions
    SET title = 'Forbidden submitted edit'
    WHERE id = v_version_pt_id;
    RAISE EXCEPTION 'submitted content snapshot was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.content_version_target_protocols
    WHERE content_version_id = v_version_pt_id;
    RAISE EXCEPTION 'submitted content targets were mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.content_version_target_protocols
    SET content_version_id = v_version_en_id
    WHERE content_version_id = v_version_pt_id
      AND protocol = 'ganho_massa'::public.protocol_enum;
    RAISE EXCEPTION 'submitted protocol target was reparented into a draft';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_version_target_protocols target
    WHERE target.content_version_id = v_version_pt_id
      AND target.protocol = 'ganho_massa'::public.protocol_enum
  ) OR EXISTS (
    SELECT 1
    FROM public.content_version_target_protocols target
    WHERE target.content_version_id = v_version_en_id
      AND target.protocol = 'ganho_massa'::public.protocol_enum
  ) THEN
    RAISE EXCEPTION 'submitted protocol target changed after failed reparenting';
  END IF;

  BEGIN
    UPDATE public.content_version_target_plans
    SET content_version_id = v_version_en_id
    WHERE content_version_id = v_version_pt_id
      AND plan = 'mensal'::public.plan_enum;
    RAISE EXCEPTION 'submitted plan target was reparented into a draft';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_version_target_plans target
    WHERE target.content_version_id = v_version_pt_id
      AND target.plan = 'mensal'::public.plan_enum
  ) OR EXISTS (
    SELECT 1
    FROM public.content_version_target_plans target
    WHERE target.content_version_id = v_version_en_id
      AND target.plan = 'mensal'::public.plan_enum
  ) THEN
    RAISE EXCEPTION 'submitted plan target changed after failed reparenting';
  END IF;

  BEGIN
    UPDATE public.content_version_target_personalities
    SET content_version_id = v_version_en_id
    WHERE content_version_id = v_version_pt_id
      AND personality_code = 'zen';
    RAISE EXCEPTION 'submitted personality target was reparented into a draft';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_version_target_personalities target
    WHERE target.content_version_id = v_version_pt_id
      AND target.personality_code = 'zen'
  ) OR EXISTS (
    SELECT 1
    FROM public.content_version_target_personalities target
    WHERE target.content_version_id = v_version_en_id
      AND target.personality_code = 'zen'
  ) THEN
    RAISE EXCEPTION 'submitted personality target changed after failed reparenting';
  END IF;

  BEGIN
    PERFORM public.review_content_version(v_editor_id, v_version_pt_id, 'approve', NULL);
    RAISE EXCEPTION 'content_editor performed nutrition review';
  EXCEPTION
    WHEN insufficient_privilege THEN v_role_denied_editor_review := true;
  END;

  BEGIN
    PERFORM public.publish_content_version(v_editor_id, v_version_pt_id, NULL);
    RAISE EXCEPTION 'content_editor performed master publication';
  EXCEPTION
    WHEN insufficient_privilege THEN v_role_denied_editor_publish := true;
  END;

  BEGIN
    PERFORM public.publish_content_version(v_reviewer_id, v_version_pt_id, NULL);
    RAISE EXCEPTION 'nutrition_admin performed master publication';
  EXCEPTION
    WHEN insufficient_privilege THEN v_role_denied_nutrition_publish := true;
  END;

  BEGIN
    PERFORM public.review_content_version(v_master_id, v_version_pt_id, 'approve', NULL);
    RAISE EXCEPTION 'master_admin performed nutrition review';
  EXCEPTION
    WHEN insufficient_privilege THEN v_role_denied_master_review := true;
  END;

  BEGIN
    PERFORM public.publish_content_version(v_master_id, v_version_pt_id, NULL);
    RAISE EXCEPTION 'content version was published before technical review';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  UPDATE public.admin_users
  SET role = 'nutrition_admin'
  WHERE id = v_editor_id;
  BEGIN
    PERFORM public.review_content_version(v_editor_id, v_version_pt_id, 'approve', NULL);
    RAISE EXCEPTION 'content author reviewed their own version';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  UPDATE public.admin_users
  SET role = 'content_editor'
  WHERE id = v_editor_id;

  PERFORM public.review_content_version(v_reviewer_id, v_version_pt_id, 'approve', NULL);

  BEGIN
    UPDATE public.content_versions
    SET published_by = v_master_id,
        published_at = clock_timestamp(),
        publish_at = clock_timestamp() + interval '4 minutes'
    WHERE id = v_version_pt_id;
    RAISE EXCEPTION 'direct publication transition accepted a sub-five-minute schedule';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.content_versions
    SET published_by = v_editor_id,
        published_at = clock_timestamp(),
        publish_at = clock_timestamp()
    WHERE id = v_version_pt_id;
    RAISE EXCEPTION 'review_content_version leaked its lifecycle guard';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.publish_content_version(
      v_master_id,
      v_version_pt_id,
      clock_timestamp() + interval '4 minutes'
    );
    RAISE EXCEPTION 'content schedule under five minutes was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  v_result := public.publish_content_version(v_master_id, v_version_pt_id, NULL);
  IF v_result->>'effective_state' <> 'published' OR NOT EXISTS (
    SELECT 1
    FROM public.content_versions version
    WHERE version.id = v_version_pt_id
      AND version.state = 'approved'
      AND version.publish_at <= clock_timestamp()
      AND version.published_by = v_master_id
  ) THEN
    RAISE EXCEPTION 'approved content version was not immediately published';
  END IF;

  BEGIN
    UPDATE public.content_versions
    SET publish_at = publish_at + interval '1 hour'
    WHERE id = v_version_pt_id;
    RAISE EXCEPTION 'publish_content_version leaked its lifecycle guard';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  SELECT updated_at
  INTO v_expected_updated_at
  FROM public.content_versions
  WHERE id = v_version_en_id;

  v_en_draft := jsonb_build_object(
    'locale', 'en-US',
    'category', 'habit_formation',
    'title', 'Synthetic habit guidance',
    'excerpt', 'A synthetic English excerpt long enough for strict persistence.',
    'bodyMarkdown', v_body,
    'tags', jsonb_build_array('daily-habits'),
    'featuredToday', false,
    'coverAssetId', NULL,
    'targeting', jsonb_build_object(
      'protocols', '[]'::jsonb,
      'plans', '[]'::jsonb,
      'personalities', '[]'::jsonb
    )
  );
  v_result := public.save_content_draft(v_editor_id, v_version_en_id, v_expected_updated_at, v_en_draft);
  v_expected_updated_at := (v_result->>'updated_at')::timestamptz;
  PERFORM public.submit_content_version(v_editor_id, v_version_en_id, v_expected_updated_at);

  BEGIN
    PERFORM public.review_content_version(v_reviewer_id, v_version_en_id, 'reject', NULL);
    RAISE EXCEPTION 'content rejection without a reason was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.review_content_version(v_reviewer_id, v_version_en_id, 'reject', 'too short');
    RAISE EXCEPTION 'content rejection with a short reason was accepted';
  EXCEPTION
    WHEN invalid_parameter_value OR check_violation THEN NULL;
  END;

  PERFORM public.review_content_version(
    v_reviewer_id,
    v_version_en_id,
    'reject',
    'Synthetic rejection reason with sufficient detail.'
  );

  BEGIN
    UPDATE public.content_versions
    SET excerpt = 'Rejected content must remain immutable after technical review.'
    WHERE id = v_version_en_id;
    RAISE EXCEPTION 'rejected content snapshot was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_result := public.create_content_draft(
    v_editor_id,
    v_publication_id,
    'en-US',
    v_version_en_id
  );
  v_version_en_replacement_id := (v_result->>'version_id')::uuid;
  IF (v_result->>'version')::integer <> 3 OR NOT EXISTS (
    SELECT 1
    FROM public.content_versions version
    WHERE version.id = v_version_en_replacement_id
      AND version.version = 3
      AND version.state = 'draft'
      AND version.body_hash = (
        SELECT source.body_hash
        FROM public.content_versions source
        WHERE source.id = v_version_en_id
      )
  ) THEN
    RAISE EXCEPTION 'rejected version did not produce a monotonic replacement draft';
  END IF;

  SELECT updated_at
  INTO v_expected_updated_at
  FROM public.content_versions
  WHERE id = v_version_en_replacement_id;
  v_en_draft := jsonb_set(v_en_draft, '{title}', to_jsonb('Revised synthetic habit guidance'::text));
  v_result := public.save_content_draft(
    v_editor_id,
    v_version_en_replacement_id,
    v_expected_updated_at,
    v_en_draft
  );
  v_expected_updated_at := (v_result->>'updated_at')::timestamptz;
  PERFORM public.submit_content_version(
    v_editor_id,
    v_version_en_replacement_id,
    v_expected_updated_at
  );
  PERFORM public.review_content_version(
    v_reviewer_id,
    v_version_en_replacement_id,
    'approve',
    NULL
  );
  v_result := public.publish_content_version(
    v_master_id,
    v_version_en_replacement_id,
    clock_timestamp() + interval '10 minutes'
  );

  IF v_result->>'effective_state' <> 'scheduled' OR NOT EXISTS (
    SELECT 1
    FROM public.content_versions version
    WHERE version.id = v_version_en_replacement_id
      AND version.publish_at > clock_timestamp() + interval '5 minutes'
      AND version.published_by = v_master_id
  ) THEN
    RAISE EXCEPTION 'approved content version was not scheduled safely';
  END IF;

  INSERT INTO public.content_user_state (
    user_id,
    publication_id,
    first_opened_at,
    last_opened_at,
    last_opened_version_id,
    last_origin
  ) VALUES (
    v_patient_id,
    v_publication_id,
    clock_timestamp(),
    clock_timestamp(),
    v_version_pt_id,
    'library'
  );

  BEGIN
    INSERT INTO public.content_events (
      user_id,
      publication_id,
      content_version_id,
      event_type,
      origin,
      event_key_hash
    ) VALUES (
      v_patient_id,
      v_publication_id,
      v_version_pt_id,
      'published',
      'library',
      repeat('b', 64)
    );
    RAISE EXCEPTION 'direct malformed content event insert was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.content_events (
    user_id,
    publication_id,
    content_version_id,
    event_type,
    origin,
    event_key_hash
  ) VALUES (
    v_patient_id,
    v_publication_id,
    v_version_pt_id,
    'opened',
    'library',
    repeat('a', 64)
  );

  BEGIN
    INSERT INTO public.content_events (
      user_id,
      publication_id,
      content_version_id,
      event_type,
      origin,
      event_key_hash
    ) VALUES (
      v_patient_id,
      v_publication_id,
      v_version_pt_id,
      'opened',
      'library',
      repeat('a', 64)
    );
    RAISE EXCEPTION 'duplicate patient event key was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.content_events
    SET origin = 'today'
    WHERE user_id = v_patient_id
      AND event_key_hash = repeat('a', 64);
    RAISE EXCEPTION 'content event was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.content_events
    WHERE user_id = v_patient_id
      AND event_key_hash = repeat('a', 64);
    RAISE EXCEPTION 'content event was deletable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.archive_content_publication(v_editor_id, v_publication_id);
    RAISE EXCEPTION 'content_editor archived a content publication';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.archive_content_publication(v_reviewer_id, v_publication_id);
    RAISE EXCEPTION 'nutrition_admin archived a content publication';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  v_result := public.archive_content_publication(v_master_id, v_publication_id);
  IF v_result->>'outcome' <> 'archived' OR NOT EXISTS (
    SELECT 1
    FROM public.content_publications publication
    WHERE publication.id = v_publication_id
      AND publication.archived_at IS NOT NULL
      AND publication.archived_by = v_master_id
  ) THEN
    RAISE EXCEPTION 'master_admin did not globally archive the publication';
  END IF;

  BEGIN
    UPDATE public.content_publications
    SET archived_by = v_editor_id,
        archived_at = clock_timestamp()
    WHERE id = v_second_publication_id;
    RAISE EXCEPTION 'archive_content_publication leaked its lifecycle guard';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.content_publications
    SET archived_at = NULL,
        archived_by = NULL
    WHERE id = v_publication_id;
    RAISE EXCEPTION 'global publication archive was reversible by direct write';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.create_content_draft(v_editor_id, v_publication_id, 'pt-BR', v_version_pt_id);
    RAISE EXCEPTION 'archived publication accepted a new draft';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  IF NOT v_role_denied_editor_review
    OR NOT v_role_denied_editor_publish
    OR NOT v_role_denied_nutrition_author
    OR NOT v_role_denied_nutrition_publish
    OR NOT v_role_denied_master_author
    OR NOT v_role_denied_master_review THEN
    RAISE EXCEPTION 'editorial role separation matrix was incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id = v_editor_id
      AND audit.action = 'content.version.submit'
      AND audit.entity_id = v_version_pt_id::text
      AND audit.after->>'state' = 'in_review'
      AND audit.after->>'body_hash' = v_hash
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id = v_reviewer_id
      AND audit.action = 'content.version.approve'
      AND audit.entity_id = v_version_pt_id::text
      AND audit.after->>'state' = 'approved'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id = v_master_id
      AND audit.action = 'content.version.publish'
      AND audit.entity_id = v_version_pt_id::text
      AND audit.after ? 'publish_at'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id = v_master_id
      AND audit.action = 'content.publication.archive'
      AND audit.entity_id = v_publication_id::text
      AND audit.after->>'state' = 'archived'
  ) THEN
    RAISE EXCEPTION 'required safe CMS lifecycle audit rows are missing';
  END IF;

  IF EXISTS (
    WITH expected(action, required_after, allowed_after) AS (
      VALUES
        ('content.publication.create', ARRAY['publication_id']::text[], ARRAY['publication_id']::text[]),
        ('content.publication.archive', ARRAY['publication_id', 'state']::text[], ARRAY['publication_id', 'state']::text[]),
        ('content.version.create', ARRAY['publication_id', 'version_id', 'version', 'state']::text[], ARRAY['publication_id', 'version_id', 'source_version_id', 'version', 'state', 'body_hash']::text[]),
        ('content.version.save', ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[], ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[]),
        ('content.version.submit', ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[], ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[]),
        ('content.version.approve', ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[], ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[]),
        ('content.version.reject', ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[], ARRAY['publication_id', 'version_id', 'version', 'state', 'body_hash']::text[]),
        ('content.version.publish', ARRAY['publication_id', 'version_id', 'version', 'state', 'publish_at', 'body_hash']::text[], ARRAY['publication_id', 'version_id', 'version', 'state', 'publish_at', 'body_hash']::text[]),
        ('content.version.schedule', ARRAY['publication_id', 'version_id', 'version', 'state', 'publish_at', 'body_hash']::text[], ARRAY['publication_id', 'version_id', 'version', 'state', 'publish_at', 'body_hash']::text[]),
        ('content.asset.create', ARRAY['asset_id', 'state']::text[], ARRAY['asset_id', 'state']::text[]),
        ('content.asset.complete', ARRAY['asset_id', 'state']::text[], ARRAY['asset_id', 'state']::text[]),
        ('content.asset.delete', ARRAY['asset_id', 'state']::text[], ARRAY['asset_id', 'state']::text[])
    )
    SELECT 1
    FROM public.audit_log audit
    LEFT JOIN expected ON expected.action = audit.action
    WHERE audit.actor_id IN (v_editor_id, v_reviewer_id, v_master_id)
      AND audit.action LIKE 'content.%'
      AND (
        expected.action IS NULL
        OR COALESCE(audit.before, '{}'::jsonb) <> '{}'::jsonb
        OR EXISTS (
          SELECT 1
          FROM jsonb_object_keys(COALESCE(audit.after, '{}'::jsonb)) actual_key
          WHERE NOT actual_key = ANY(expected.allowed_after)
        )
        OR EXISTS (
          SELECT 1
          FROM unnest(expected.required_after) required_key
          WHERE NOT COALESCE(audit.after, '{}'::jsonb) ? required_key
        )
      )
  ) OR EXISTS (
    WITH expected(action) AS (
      VALUES
        ('content.publication.create'),
        ('content.publication.archive'),
        ('content.version.create'),
        ('content.version.save'),
        ('content.version.submit'),
        ('content.version.approve'),
        ('content.version.reject'),
        ('content.version.publish'),
        ('content.version.schedule'),
        ('content.asset.create'),
        ('content.asset.complete'),
        ('content.asset.delete')
    )
    SELECT 1
    FROM expected
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.audit_log audit
      WHERE audit.actor_id IN (v_editor_id, v_reviewer_id, v_master_id)
        AND audit.action = expected.action
    )
  ) THEN
    RAISE EXCEPTION 'CMS audit rows do not match the exact action-specific key allowlists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id IN (v_editor_id, v_reviewer_id, v_master_id)
      AND audit.action LIKE 'content.%'
      AND (
        audit.actor_email IS NOT NULL
        OR COALESCE(audit.before, '{}'::jsonb)::text
          ~* '"(body_markdown|body|signed_url|email|pii|token|credential|secret|object_path)"[[:space:]]*:'
        OR COALESCE(audit.after, '{}'::jsonb)::text
          ~* '"(body_markdown|body|signed_url|email|pii|token|credential|secret|object_path)"[[:space:]]*:'
        OR COALESCE(audit.before, '{}'::jsonb)::text LIKE '%' || v_body || '%'
        OR COALESCE(audit.after, '{}'::jsonb)::text LIKE '%' || v_body || '%'
      )
  ) THEN
    RAISE EXCEPTION 'CMS audit rows contain content copy or sensitive payloads';
  END IF;
END;
$test$;

RESET ROLE;

ROLLBACK;

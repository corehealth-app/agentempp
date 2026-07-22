BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Fail first and clearly when Task 3 has not been implemented yet.
DO $test$
DECLARE
  v_function text;
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    'public.list_mobile_content(uuid,text,text,integer,timestamp with time zone,uuid,timestamp with time zone)',
    'public.get_mobile_content(uuid,uuid,timestamp with time zone)',
    'public.record_mobile_content_event(uuid,uuid,integer,text,text,text,timestamp with time zone)',
    'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
  ]
  LOOP
    IF to_regprocedure(v_function) IS NULL THEN
      RAISE EXCEPTION 'missing content delivery function %', v_function;
    END IF;
  END LOOP;
END;
$test$;

DO $test$
DECLARE
  v_function text;
  v_definition text;
  v_failures text[] := '{}'::text[];
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    'public.list_mobile_content(uuid,text,text,integer,timestamp with time zone,uuid,timestamp with time zone)',
    'public.get_mobile_content(uuid,uuid,timestamp with time zone)',
    'public.record_mobile_content_event(uuid,uuid,integer,text,text,text,timestamp with time zone)',
    'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
  ]
  LOOP
    IF (
      SELECT function_definition.prorettype
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
    ) <> 'jsonb'::regtype THEN
      RAISE EXCEPTION 'content delivery function must return jsonb: %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND function_definition.prosecdef
    ) THEN
      RAISE EXCEPTION 'content delivery function must remain SECURITY INVOKER: %', v_function;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND function_definition.proconfig @> ARRAY['search_path=public, pg_temp']
    ) THEN
      RAISE EXCEPTION 'content delivery function lacks fixed public, pg_temp search_path: %',
        v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      CROSS JOIN LATERAL aclexplode(
        COALESCE(function_definition.proacl, acldefault('f', function_definition.proowner))
      ) privilege
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND privilege.privilege_type = 'EXECUTE'
        AND (
          privilege.grantee = 0
          OR privilege.grantee IN (
            (SELECT oid FROM pg_roles WHERE rolname = 'anon'),
            (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
          )
        )
    ) OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'content delivery function privileges are not service-only: %', v_function;
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
      RAISE EXCEPTION 'content delivery grantees are not exactly owner plus service_role: %',
        v_function;
    END IF;

    v_definition := pg_get_functiondef(to_regprocedure(v_function));
    IF v_definition ~* 'SECURITY[[:space:]]+DEFINER'
      OR v_definition ~* 'EXECUTE[[:space:]]+format'
      OR v_definition ~* 'body_markdown[^;]*content_events'
      OR v_definition ~* 'body_markdown[^;]*audit_log' THEN
      RAISE EXCEPTION 'unsafe content delivery function definition: %', v_function;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM pg_proc function_definition
    JOIN pg_namespace namespace ON namespace.oid = function_definition.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_definition.proname IN (
        'list_mobile_content',
        'get_mobile_content',
        'record_mobile_content_event',
        'set_mobile_content_saved'
      )
  ) <> 4 THEN
    RAISE EXCEPTION 'public content delivery namespace must contain exactly four signatures';
  END IF;

  IF to_regprocedure('private.enforce_content_user_state_monotonic()') IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM pg_trigger trigger_definition
      WHERE trigger_definition.tgrelid = 'public.content_user_state'::regclass
        AND trigger_definition.tgname = 'content_user_state_monotonic_guard'
        AND NOT trigger_definition.tgisinternal
        AND trigger_definition.tgfoid =
          'private.enforce_content_user_state_monotonic()'::regprocedure
    )
    OR has_function_privilege(
      'anon',
      'private.enforce_content_user_state_monotonic()',
      'EXECUTE'
    )
    OR has_function_privilege(
      'authenticated',
      'private.enforce_content_user_state_monotonic()',
      'EXECUTE'
    ) THEN
    RAISE EXCEPTION 'content user-state monotonic trigger is missing or client-executable';
  END IF;

  IF (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.list_mobile_content(uuid,text,text,integer,timestamp with time zone,uuid,timestamp with time zone)'
    )
  ) <> 6 OR (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.get_mobile_content(uuid,uuid,timestamp with time zone)'
    )
  ) <> 1 OR (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.record_mobile_content_event(uuid,uuid,integer,text,text,text,timestamp with time zone)'
    )
  ) <> 1 OR (
    SELECT pronargdefaults
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
    )
  ) <> 1 THEN
    RAISE EXCEPTION 'content delivery defaults do not match the approved signatures';
  END IF;

  IF (
    SELECT proargnames
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.list_mobile_content(uuid,text,text,integer,timestamp with time zone,uuid,timestamp with time zone)'
    )
  ) <> ARRAY[
    'p_user_id', 'p_surface', 'p_category', 'p_limit',
    'p_cursor_publish_at', 'p_cursor_publication_id', 'p_now'
  ] OR (
    SELECT proargnames
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.get_mobile_content(uuid,uuid,timestamp with time zone)'
    )
  ) <> ARRAY['p_user_id', 'p_publication_id', 'p_now']
  OR (
    SELECT proargnames
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.record_mobile_content_event(uuid,uuid,integer,text,text,text,timestamp with time zone)'
    )
  ) <> ARRAY[
    'p_user_id', 'p_publication_id', 'p_version', 'p_event_type',
    'p_origin', 'p_event_key', 'p_now'
  ] OR (
    SELECT proargnames
    FROM pg_proc
    WHERE oid = to_regprocedure(
      'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
    )
  ) <> ARRAY[
    'p_user_id', 'p_publication_id', 'p_version', 'p_saved',
    'p_origin', 'p_event_key', 'p_now'
  ] THEN
    RAISE EXCEPTION 'content RPCs accepted client targeting input or changed p_now placement';
  END IF;

  IF to_regclass('public.subscriptions_content_delivery_idx') IS NULL THEN
    RAISE EXCEPTION 'missing deterministic subscription lookup index';
  END IF;

  FOREACH v_function IN ARRAY ARRAY[
    'public.record_mobile_content_event(uuid,uuid,integer,text,text,text,timestamp with time zone)',
    'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
  ]
  LOOP
    v_definition := upper(pg_get_functiondef(to_regprocedure(v_function)));
    IF position('PG_ADVISORY_XACT_LOCK' IN v_definition) = 0 THEN
      RAISE EXCEPTION 'content mutation lacks a per-user/publication advisory lock: %', v_function;
    END IF;
    IF position('EXTENSIONS.DIGEST' IN v_definition) = 0 THEN
      RAISE EXCEPTION 'content mutation does not hash trimmed event keys with extensions.digest: %',
        v_function;
    END IF;

    IF position('PG_ADVISORY_XACT_LOCK' IN v_definition) = 0
      OR position('FROM PUBLIC.CONTENT_VERSIONS CONTENT_VERSION' IN v_definition) = 0
      OR position('FOR KEY SHARE OF CONTENT_VERSION' IN v_definition) = 0
      OR position('FROM PUBLIC.CONTENT_PUBLICATIONS PUBLICATION' IN v_definition) = 0
      OR position('FOR UPDATE' IN v_definition) = 0
      OR position('WITH PATIENT AS' IN v_definition) = 0
      OR position('PG_ADVISORY_XACT_LOCK' IN v_definition)
        >= position('FROM PUBLIC.CONTENT_VERSIONS CONTENT_VERSION' IN v_definition)
      OR position('FROM PUBLIC.CONTENT_VERSIONS CONTENT_VERSION' IN v_definition)
        >= position('FOR KEY SHARE OF CONTENT_VERSION' IN v_definition)
      OR position('FOR KEY SHARE OF CONTENT_VERSION' IN v_definition)
        >= position('FROM PUBLIC.CONTENT_PUBLICATIONS PUBLICATION' IN v_definition)
      OR position('FROM PUBLIC.CONTENT_PUBLICATIONS PUBLICATION' IN v_definition)
        >= position('FOR UPDATE' IN v_definition)
      OR position('FOR UPDATE' IN v_definition) >= position('WITH PATIENT AS' IN v_definition) THEN
      v_failures := array_append(
        v_failures,
        'missing advisory/version-key-share/publication-update/eligibility lock order: ' || v_function
      );
    END IF;

    IF v_definition ~ 'CONTENT_VERSIONS[^;]+FOR UPDATE' THEN
      v_failures := array_append(v_failures, 'Task 3 must not row-lock versions: ' || v_function);
    END IF;
  END LOOP;

  IF to_regclass('private.content_mutation_receipts') IS NULL THEN
    v_failures := array_append(v_failures, 'missing private.content_mutation_receipts');
  ELSE
    IF (
      SELECT array_agg(attribute.attname ORDER BY attribute.attnum)
      FROM pg_attribute attribute
      WHERE attribute.attrelid = 'private.content_mutation_receipts'::regclass
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) <> ARRAY[
      'user_id',
      'event_key_hash',
      'operation',
      'publication_id',
      'content_version',
      'event_type',
      'desired_saved',
      'origin',
      'response',
      'created_at'
    ]::name[] THEN
      RAISE EXCEPTION 'private receipt columns exceed the approved technical data model';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint constraint_definition
      WHERE constraint_definition.conrelid = 'private.content_mutation_receipts'::regclass
        AND constraint_definition.contype = 'p'
        AND pg_get_constraintdef(constraint_definition.oid)
          = 'PRIMARY KEY (user_id, event_key_hash)'
    ) OR NOT EXISTS (
      SELECT 1
      FROM pg_constraint constraint_definition
      WHERE constraint_definition.conrelid = 'private.content_mutation_receipts'::regclass
        AND constraint_definition.contype = 'c'
        AND pg_get_constraintdef(constraint_definition.oid) LIKE '%octet_length((response)::text) <= 2048%'
    ) THEN
      RAISE EXCEPTION 'private receipt key or bounded-response constraint is missing';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class relation
      WHERE relation.oid = 'private.content_mutation_receipts'::regclass
        AND relation.relrowsecurity
        AND relation.relforcerowsecurity
    ) OR EXISTS (
      SELECT 1
      FROM pg_policies policy
      WHERE policy.schemaname = 'private'
        AND policy.tablename = 'content_mutation_receipts'
    ) THEN
      RAISE EXCEPTION 'private receipt RLS must be enabled and forced without client policies';
    END IF;

    IF has_table_privilege('anon', 'private.content_mutation_receipts', 'SELECT,INSERT,UPDATE,DELETE')
      OR has_table_privilege('authenticated', 'private.content_mutation_receipts', 'SELECT,INSERT,UPDATE,DELETE')
      OR NOT has_table_privilege('service_role', 'private.content_mutation_receipts', 'SELECT,INSERT,UPDATE')
      OR has_table_privilege('service_role', 'private.content_mutation_receipts', 'DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
      RAISE EXCEPTION 'private receipt table privileges are not least-privilege service-only';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_class relation
      CROSS JOIN LATERAL aclexplode(relation.relacl) privilege
      WHERE relation.oid = 'private.content_mutation_receipts'::regclass
        AND privilege.grantee <> relation.relowner
        AND (
          privilege.grantee <> (SELECT oid FROM pg_roles WHERE rolname = 'service_role')
          OR privilege.privilege_type NOT IN ('SELECT', 'INSERT', 'UPDATE')
        )
    ) OR (
      SELECT count(*)
      FROM pg_class relation
      CROSS JOIN LATERAL aclexplode(relation.relacl) privilege
      WHERE relation.oid = 'private.content_mutation_receipts'::regclass
        AND privilege.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'service_role')
        AND privilege.privilege_type IN ('SELECT', 'INSERT', 'UPDATE')
    ) <> 3 THEN
      RAISE EXCEPTION 'private receipt ACL has unexpected grantees or privileges';
    END IF;
  END IF;

  IF (
    SELECT count(*)
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = 'public'
      AND relation.relkind = 'r'
      AND relation.relname IN (
        'content_publications',
        'content_assets',
        'content_versions',
        'content_version_target_protocols',
        'content_version_target_plans',
        'content_version_target_personalities',
        'content_user_state',
        'content_events'
      )
  ) <> 8 OR to_regclass('public.content_mutation_receipts') IS NOT NULL THEN
    RAISE EXCEPTION 'CMS must retain exactly eight public tables and no public receipt table';
  END IF;

  IF cardinality(v_failures) > 0 THEN
    RAISE EXCEPTION 'Task 3 review RED: %', array_to_string(v_failures, '; ');
  END IF;
END;
$test$;

SET LOCAL ROLE anon;
DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  IF current_user <> 'anon' THEN
    RAISE EXCEPTION 'anon denial probe is not executing as anon';
  END IF;
  BEGIN
    PERFORM public.list_mobile_content(NULL);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon executed a content delivery RPC';
  END IF;
END;
$test$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  IF current_user <> 'authenticated' THEN
    RAISE EXCEPTION 'authenticated denial probe is not executing as authenticated';
  END IF;
  BEGIN
    PERFORM public.get_mobile_content(NULL, NULL);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'authenticated executed a content delivery RPC';
  END IF;
END;
$test$;
RESET ROLE;

DO $test$
DECLARE
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000002001';
  v_reviewer_id constant uuid := '00000000-0000-0000-0000-000000002002';
  v_master_id constant uuid := '00000000-0000-0000-0000-000000002003';
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
    (v_editor_id, 'authenticated', 'authenticated', 'task3-editor@example.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_reviewer_id, 'authenticated', 'authenticated', 'task3-reviewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_master_id, 'authenticated', 'authenticated', 'task3-master@example.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

  INSERT INTO public.admin_users (id, email, role)
  VALUES
    (v_editor_id, 'task3-editor@example.invalid', 'content_editor'),
    (v_reviewer_id, 'task3-reviewer@example.invalid', 'nutrition_admin'),
    (v_master_id, 'task3-master@example.invalid', 'master_admin');

  INSERT INTO public.users (id, wpp, email, name, locale, metadata)
  VALUES
    ('00000000-0000-0000-0000-000000002101', NULL, 'eligible-task3@example.invalid', 'Task 3 Eligible PII Marker', 'pt-BR', '{"token":"task3-secret-marker"}'::jsonb),
    ('00000000-0000-0000-0000-000000002102', NULL, 'english-task3@example.invalid', 'Task 3 English', 'en-US', '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002103', NULL, 'missing-task3@example.invalid', 'Task 3 Missing Attributes', 'pt-BR', '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002104', NULL, 'expired-task3@example.invalid', 'Task 3 Expired', 'pt-BR', '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002105', NULL, 'null-locale-task3@example.invalid', 'Task 3 Null Locale', NULL, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002106', NULL, 'unsupported-task3@example.invalid', 'Task 3 Unsupported Locale', 'es-ES', '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002107', NULL, 'duplicate-sub-task3@example.invalid', 'Task 3 Duplicate Subscription', 'pt-BR', '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002108', NULL, 'elapsed-trial-task3@example.invalid', 'Task 3 Elapsed Trial', 'pt-BR', '{}'::jsonb),
    ('00000000-0000-0000-0000-000000002109', NULL, 'null-start-task3@example.invalid', 'Task 3 Null Period Start', 'pt-BR', '{}'::jsonb);

  INSERT INTO public.user_profiles (user_id, current_protocol)
  VALUES
    ('00000000-0000-0000-0000-000000002101', 'recomposicao'),
    ('00000000-0000-0000-0000-000000002102', 'manutencao'),
    ('00000000-0000-0000-0000-000000002104', 'recomposicao'),
    ('00000000-0000-0000-0000-000000002107', 'recomposicao'),
    ('00000000-0000-0000-0000-000000002108', 'recomposicao');

  INSERT INTO public.user_coach_preferences (user_id, personality_code)
  VALUES
    ('00000000-0000-0000-0000-000000002101', 'focus'),
    ('00000000-0000-0000-0000-000000002102', 'zen'),
    ('00000000-0000-0000-0000-000000002104', 'focus'),
    ('00000000-0000-0000-0000-000000002107', 'focus'),
    ('00000000-0000-0000-0000-000000002108', 'focus');

  INSERT INTO public.subscriptions (
    id,
    user_id,
    plan,
    status,
    current_period_start,
    current_period_end,
    trial_ends_at,
    created_at,
    updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000002201', '00000000-0000-0000-0000-000000002101', 'mensal', 'active', clock_timestamp() - interval '1 day', clock_timestamp() + interval '30 days', NULL, clock_timestamp() - interval '1 day', clock_timestamp()),
    ('00000000-0000-0000-0000-000000002202', '00000000-0000-0000-0000-000000002104', 'mensal', 'active', clock_timestamp() - interval '30 days', clock_timestamp() - interval '1 second', NULL, clock_timestamp() - interval '30 days', clock_timestamp()),
    ('00000000-0000-0000-0000-000000002203', '00000000-0000-0000-0000-000000002107', 'mensal', 'active', '2026-07-15 00:00:00+00', '2026-08-15 00:00:00+00', NULL, '2026-07-15 00:00:00+00', '2026-07-20 00:00:00+00'),
    ('00000000-0000-0000-0000-000000002204', '00000000-0000-0000-0000-000000002107', 'anual', 'active', '2025-08-01 00:00:00+00', '2026-10-01 00:00:00+00', NULL, '2025-08-01 00:00:00+00', '2026-07-01 00:00:00+00'),
    ('00000000-0000-0000-0000-000000002205', '00000000-0000-0000-0000-000000002108', 'trial', 'trial', clock_timestamp() - interval '7 days', clock_timestamp() + interval '7 days', clock_timestamp() - interval '1 second', clock_timestamp() - interval '7 days', clock_timestamp()),
    ('00000000-0000-0000-0000-000000002206', '00000000-0000-0000-0000-000000002109', 'mensal', 'active', '2026-07-15 00:00:00+00', '2026-08-15 00:00:00+00', NULL, '2026-07-15 00:00:00+00', '2026-07-20 00:00:00+00'),
    ('00000000-0000-0000-0000-000000002207', '00000000-0000-0000-0000-000000002109', 'anual', 'active', NULL, '2026-10-01 00:00:00+00', NULL, '2025-08-01 00:00:00+00', '2026-07-21 00:00:00+00');
END;
$test$;

CREATE FUNCTION pg_temp.task3_publish_version(
  p_publication_id uuid,
  p_locale text,
  p_category text,
  p_featured_today boolean,
  p_protocols text[] DEFAULT '{}'::text[],
  p_plans text[] DEFAULT '{}'::text[],
  p_personalities text[] DEFAULT '{}'::text[],
  p_cover_asset_id uuid DEFAULT NULL,
  p_publish_at timestamptz DEFAULT NULL,
  p_source_version_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fixture$
DECLARE
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000002001';
  v_reviewer_id constant uuid := '00000000-0000-0000-0000-000000002002';
  v_master_id constant uuid := '00000000-0000-0000-0000-000000002003';
  v_result jsonb;
  v_version_id uuid;
  v_updated_at timestamptz;
  v_version integer;
  v_draft jsonb;
BEGIN
  v_result := public.create_content_draft(
    v_editor_id,
    p_publication_id,
    p_locale,
    p_source_version_id
  );
  v_version_id := (v_result->>'version_id')::uuid;
  v_version := (v_result->>'version')::integer;

  SELECT version.updated_at
  INTO v_updated_at
  FROM public.content_versions version
  WHERE version.id = v_version_id;

  v_draft := jsonb_build_object(
    'locale', p_locale,
    'category', p_category,
    'title', 'Fixture ' || replace(p_publication_id::text, '-', ' '),
    'excerpt', 'Synthetic educational content used only by the rollback-safe Task 3 SQL suite.',
    'bodyMarkdown', '## Synthetic guidance' || E'\n\n' || repeat('word ', 40),
    'tags', jsonb_build_array('fixture'),
    'featuredToday', p_featured_today,
    'coverAssetId', CASE
      WHEN p_cover_asset_id IS NULL THEN 'null'::jsonb
      ELSE to_jsonb(p_cover_asset_id::text)
    END,
    'targeting', jsonb_build_object(
      'protocols', to_jsonb(p_protocols),
      'plans', to_jsonb(p_plans),
      'personalities', to_jsonb(p_personalities)
    )
  );

  v_result := public.save_content_draft(v_editor_id, v_version_id, v_updated_at, v_draft);
  v_updated_at := (v_result->>'updated_at')::timestamptz;
  PERFORM public.submit_content_version(v_editor_id, v_version_id, v_updated_at);
  PERFORM public.review_content_version(v_reviewer_id, v_version_id, 'approve', NULL);
  v_result := public.publish_content_version(v_master_id, v_version_id, p_publish_at);

  RETURN jsonb_build_object(
    'publicationId', p_publication_id,
    'versionId', v_version_id,
    'version', v_version,
    'publishAt', v_result->>'publish_at'
  );
END;
$fixture$;

CREATE FUNCTION pg_temp.task3_publish_publication(
  p_slug text,
  p_locale text,
  p_category text,
  p_featured_today boolean,
  p_protocols text[] DEFAULT '{}'::text[],
  p_plans text[] DEFAULT '{}'::text[],
  p_personalities text[] DEFAULT '{}'::text[],
  p_cover_asset_id uuid DEFAULT NULL,
  p_publish_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fixture$
DECLARE
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000002001';
  v_result jsonb;
  v_publication_id uuid;
BEGIN
  v_result := public.create_content_publication(v_editor_id, p_slug);
  v_publication_id := (v_result->>'publication_id')::uuid;
  RETURN pg_temp.task3_publish_version(
    v_publication_id,
    p_locale,
    p_category,
    p_featured_today,
    p_protocols,
    p_plans,
    p_personalities,
    p_cover_asset_id,
    p_publish_at,
    NULL
  );
END;
$fixture$;

GRANT EXECUTE ON FUNCTION pg_temp.task3_publish_version(
  uuid, text, text, boolean, text[], text[], text[], uuid, timestamptz, uuid
) TO service_role;
GRANT EXECUTE ON FUNCTION pg_temp.task3_publish_publication(
  text, text, text, boolean, text[], text[], text[], uuid, timestamptz
) TO service_role;

SET LOCAL ROLE service_role;

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-0000-0000-000000002101';
  v_en_user_id constant uuid := '00000000-0000-0000-0000-000000002102';
  v_missing_user_id constant uuid := '00000000-0000-0000-0000-000000002103';
  v_expired_user_id constant uuid := '00000000-0000-0000-0000-000000002104';
  v_null_locale_user_id constant uuid := '00000000-0000-0000-0000-000000002105';
  v_unsupported_locale_user_id constant uuid := '00000000-0000-0000-0000-000000002106';
  v_duplicate_sub_user_id constant uuid := '00000000-0000-0000-0000-000000002107';
  v_elapsed_trial_user_id constant uuid := '00000000-0000-0000-0000-000000002108';
  v_null_start_user_id constant uuid := '00000000-0000-0000-0000-000000002109';
  v_editor_id constant uuid := '00000000-0000-0000-0000-000000002001';
  v_master_id constant uuid := '00000000-0000-0000-0000-000000002003';
  v_asset_id constant uuid := '00000000-0000-0000-0000-000000002301';
  v_result jsonb;
  v_list jsonb;
  v_detail jsonb;
  v_replay jsonb;
  v_first_response jsonb;
  v_noop_response jsonb;
  v_publication_id uuid;
  v_version_id uuid;
  v_version integer;
  v_universal_publication_id uuid;
  v_en_publication_id uuid;
  v_protocol_publication_id uuid;
  v_plan_publication_id uuid;
  v_personality_publication_id uuid;
  v_all_publication_id uuid;
  v_protocol_mismatch_id uuid;
  v_plan_mismatch_id uuid;
  v_personality_mismatch_id uuid;
  v_featured_publication_id uuid;
  v_regular_publication_id uuid;
  v_training_publication_id uuid;
  v_future_publication_id uuid;
  v_archived_publication_id uuid;
  v_replacement_publication_id uuid;
  v_replacement_live_version_id uuid;
  v_replacement_live_version integer;
  v_replacement_future_version_id uuid;
  v_replacement_future_version integer;
  v_superseded_schedule_publication_id uuid;
  v_superseded_schedule_latest_version integer;
  v_due_publication_id uuid;
  v_due_version integer;
  v_target_guard_publication_id uuid;
  v_target_guard_version_id uuid;
  v_target_guard_old_version integer;
  v_target_guard_new_version integer;
  v_cover_publication_id uuid;
  v_duplicate_annual_id uuid;
  v_duplicate_monthly_id uuid;
  v_duplicate_monthly_version integer;
  v_trial_target_id uuid;
  v_state_publication_id uuid;
  v_state_version_id uuid;
  v_state_version integer;
  v_state_replacement_version integer;
  v_cursor_publication_ids uuid[] := '{}'::uuid[];
  v_cursor_at timestamptz := clock_timestamp() + interval '1 day';
  v_future_at timestamptz := clock_timestamp() + interval '2 days';
  v_effective_now timestamptz;
  v_cursor_now timestamptz;
  v_page_one jsonb;
  v_page_two jsonb;
  v_expected_cursor_ids uuid[];
  v_event_count integer;
  v_saved_event_count integer;
  v_receipt_count integer;
  v_hash text;
  v_legacy_hash text;
  v_collision_rejected boolean := false;
  v_target_event_rejected boolean := false;
  v_target_save_rejected boolean := false;
  v_stale_rejected boolean := false;
  v_non_visible_rejected boolean := false;
  v_malformed_cursor_rejected boolean := false;
BEGIN
  IF current_user <> 'service_role' THEN
    RAISE EXCEPTION 'content delivery success workflow is not executing as service_role';
  END IF;

  v_result := public.list_mobile_content(
    '00000000-0000-0000-0000-000000002199',
    'library',
    NULL,
    20,
    NULL,
    NULL,
    clock_timestamp()
  );
  IF v_result <> jsonb_build_object('items', '[]'::jsonb, 'nextCursor', NULL) THEN
    RAISE EXCEPTION 'service_role empty content list response is not deterministic: %', v_result;
  END IF;

  BEGIN
    PERFORM public.list_mobile_content(v_user_id, 'library', NULL, 20, clock_timestamp(), NULL);
  EXCEPTION WHEN invalid_parameter_value THEN
    v_malformed_cursor_rejected := true;
  END;
  IF NOT v_malformed_cursor_rejected THEN
    RAISE EXCEPTION 'malformed cursor pair was accepted';
  END IF;

  BEGIN
    PERFORM public.list_mobile_content(v_user_id, 'feed');
    RAISE EXCEPTION 'invalid content surface was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.list_mobile_content(v_user_id, NULL);
    RAISE EXCEPTION 'null content surface was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.list_mobile_content(v_user_id, 'library', NULL, 51);
    RAISE EXCEPTION 'content list limit above 50 was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  PERFORM public.create_content_asset(
    v_editor_id,
    v_asset_id,
    'image/jpeg',
    4096,
    'content/' || v_asset_id::text || '.jpg'
  );
  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES (
    'content-covers',
    'content/' || v_asset_id::text || '.jpg',
    jsonb_build_object('mimetype', 'image/jpeg', 'size', 4096, 'eTag', 'task3-cover-etag')
  );
  PERFORM public.complete_content_asset(
    v_editor_id,
    v_asset_id,
    4096,
    'task3-cover-etag'
  );

  v_result := pg_temp.task3_publish_publication(
    'task3-universal', 'pt-BR', 'nutrition', false
  );
  v_universal_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-english-only', 'en-US', 'nutrition', false
  );
  v_en_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-protocol', 'pt-BR', 'nutrition', false, ARRAY['recomposicao']
  );
  v_protocol_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-plan', 'pt-BR', 'nutrition', false, '{}'::text[], ARRAY['mensal']
  );
  v_plan_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-personality', 'pt-BR', 'nutrition', false, '{}'::text[], '{}'::text[], ARRAY['focus']
  );
  v_personality_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-all-targets',
    'pt-BR',
    'nutrition',
    false,
    ARRAY['recomposicao'],
    ARRAY['mensal'],
    ARRAY['focus']
  );
  v_all_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-protocol-mismatch', 'pt-BR', 'nutrition', false, ARRAY['ganho_massa']
  );
  v_protocol_mismatch_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-plan-mismatch', 'pt-BR', 'nutrition', false, '{}'::text[], ARRAY['anual']
  );
  v_plan_mismatch_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-personality-mismatch', 'pt-BR', 'nutrition', false, '{}'::text[], '{}'::text[], ARRAY['zen']
  );
  v_personality_mismatch_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-featured', 'pt-BR', 'habit_formation', true
  );
  v_featured_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-regular', 'pt-BR', 'habit_formation', false
  );
  v_regular_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-training', 'pt-BR', 'training', false
  );
  v_training_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-future', 'pt-BR', 'nutrition', false, '{}'::text[], '{}'::text[], '{}'::text[], NULL, v_future_at
  );
  v_future_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-archive', 'pt-BR', 'nutrition', false
  );
  v_archived_publication_id := (v_result->>'publicationId')::uuid;
  PERFORM public.archive_content_publication(v_master_id, v_archived_publication_id);

  v_result := public.create_content_publication(v_editor_id, 'task3-replacement-waiting');
  v_replacement_publication_id := (v_result->>'publication_id')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_replacement_publication_id, 'pt-BR', 'cardiovascular_health', false
  );
  v_replacement_live_version := (v_result->>'version')::integer;
  v_replacement_live_version_id := (v_result->>'versionId')::uuid;
  v_version_id := v_replacement_live_version_id;
  v_result := pg_temp.task3_publish_version(
    v_replacement_publication_id,
    'pt-BR',
    'cardiovascular_health',
    true,
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    NULL,
    v_future_at,
    v_version_id
  );
  v_replacement_future_version_id := (v_result->>'versionId')::uuid;
  v_replacement_future_version := (v_result->>'version')::integer;
  PERFORM public.create_content_draft(
    v_editor_id,
    v_replacement_publication_id,
    'pt-BR',
    (v_result->>'versionId')::uuid
  );

  v_result := public.create_content_publication(v_editor_id, 'task3-superseded-schedule');
  v_superseded_schedule_publication_id := (v_result->>'publication_id')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_superseded_schedule_publication_id,
    'pt-BR',
    'nutrition',
    false
  );
  v_version_id := (v_result->>'versionId')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_superseded_schedule_publication_id,
    'pt-BR',
    'nutrition',
    false,
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    NULL,
    v_future_at,
    v_version_id
  );
  v_version_id := (v_result->>'versionId')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_superseded_schedule_publication_id,
    'pt-BR',
    'nutrition',
    true,
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    NULL,
    NULL,
    v_version_id
  );
  v_superseded_schedule_latest_version := (v_result->>'version')::integer;

  v_result := public.create_content_publication(v_editor_id, 'task3-newest-due');
  v_due_publication_id := (v_result->>'publication_id')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_due_publication_id, 'pt-BR', 'supplementation', false
  );
  v_version_id := (v_result->>'versionId')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_due_publication_id,
    'pt-BR',
    'supplementation',
    true,
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    NULL,
    NULL,
    v_version_id
  );
  v_due_version := (v_result->>'version')::integer;

  v_result := public.create_content_publication(v_editor_id, 'task3-newest-targeting-guard');
  v_target_guard_publication_id := (v_result->>'publication_id')::uuid;
  v_result := pg_temp.task3_publish_version(
    v_target_guard_publication_id,
    'pt-BR',
    'neuroscience',
    false
  );
  v_target_guard_version_id := (v_result->>'versionId')::uuid;
  v_target_guard_old_version := (v_result->>'version')::integer;
  v_result := pg_temp.task3_publish_version(
    v_target_guard_publication_id,
    'pt-BR',
    'neuroscience',
    false,
    ARRAY['ganho_massa'],
    '{}'::text[],
    '{}'::text[],
    NULL,
    NULL,
    v_target_guard_version_id
  );
  v_target_guard_new_version := (v_result->>'version')::integer;

  v_result := pg_temp.task3_publish_publication(
    'task3-cover',
    'pt-BR',
    'hydration',
    false,
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    v_asset_id
  );
  v_cover_publication_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-duplicate-annual', 'pt-BR', 'weight_loss', false, '{}'::text[], ARRAY['anual']
  );
  v_duplicate_annual_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-duplicate-monthly', 'pt-BR', 'weight_loss', false, '{}'::text[], ARRAY['mensal']
  );
  v_duplicate_monthly_id := (v_result->>'publicationId')::uuid;
  v_duplicate_monthly_version := (v_result->>'version')::integer;

  v_result := pg_temp.task3_publish_publication(
    'task3-trial-target', 'pt-BR', 'weight_loss', false, '{}'::text[], ARRAY['trial']
  );
  v_trial_target_id := (v_result->>'publicationId')::uuid;

  v_result := pg_temp.task3_publish_publication(
    'task3-state', 'pt-BR', 'using_bodyflow', false
  );
  v_state_publication_id := (v_result->>'publicationId')::uuid;
  v_state_version_id := (v_result->>'versionId')::uuid;
  v_state_version := (v_result->>'version')::integer;

  FOR v_event_count IN 1..3 LOOP
    v_result := pg_temp.task3_publish_publication(
      'task3-cursor-' || v_event_count::text,
      'pt-BR',
      'sleep',
      false,
      '{}'::text[],
      '{}'::text[],
      '{}'::text[],
      NULL,
      v_cursor_at
    );
    v_cursor_publication_ids := array_append(
      v_cursor_publication_ids,
      (v_result->>'publicationId')::uuid
    );
  END LOOP;

  v_effective_now := clock_timestamp() + interval '1 minute';
  v_cursor_now := greatest(v_cursor_at, v_future_at) + interval '1 minute';

  v_list := public.list_mobile_content(v_user_id, 'library', NULL, 50, NULL, NULL, v_effective_now);
  IF NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_universal_publication_id)))
    OR NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_protocol_publication_id)))
    OR NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_plan_publication_id)))
    OR NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_personality_publication_id)))
    OR NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_all_publication_id)))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_en_publication_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_protocol_mismatch_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_plan_mismatch_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_personality_mismatch_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_future_publication_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_archived_publication_id)) THEN
    RAISE EXCEPTION 'locale, schedule, archive, wildcard, or AND targeting eligibility failed';
  END IF;

  v_detail := public.get_mobile_content(v_en_user_id, v_en_publication_id, v_effective_now);
  IF v_detail->>'locale' <> 'en-US'
    OR (v_detail->>'publicationId')::uuid <> v_en_publication_id
    OR public.get_mobile_content(v_user_id, v_en_publication_id, v_effective_now) IS NOT NULL THEN
    RAISE EXCEPTION 'exact locale delivery or no-fallback behavior failed';
  END IF;

  IF jsonb_array_length(
    public.list_mobile_content(v_null_locale_user_id, 'library', NULL, 50, NULL, NULL, v_effective_now)->'items'
  ) <> 0 OR jsonb_array_length(
    public.list_mobile_content(v_unsupported_locale_user_id, 'library', NULL, 50, NULL, NULL, v_effective_now)->'items'
  ) <> 0 THEN
    RAISE EXCEPTION 'null or unsupported patient locale did not fail closed';
  END IF;

  v_list := public.list_mobile_content(
    v_missing_user_id, 'library', 'nutrition', 50, NULL, NULL, v_effective_now
  );
  IF NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_universal_publication_id)))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_protocol_publication_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_plan_publication_id))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_personality_publication_id)) THEN
    RAISE EXCEPTION 'missing patient attributes did not match only wildcard dimensions';
  END IF;

  v_list := public.list_mobile_content(
    v_expired_user_id, 'library', 'nutrition', 50, NULL, NULL, v_effective_now
  );
  IF v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_plan_publication_id)) THEN
    RAISE EXCEPTION 'expired active subscription qualified for plan targeting';
  END IF;

  v_list := public.list_mobile_content(
    v_duplicate_sub_user_id, 'library', 'weight_loss', 50, NULL, NULL, '2026-08-01 00:00:00+00'
  );
  IF v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_duplicate_annual_id))
    OR NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_duplicate_monthly_id))) THEN
    RAISE EXCEPTION 'list did not resolve the most recent eligible subscription period';
  END IF;

  v_detail := public.get_mobile_content(
    v_duplicate_sub_user_id, v_duplicate_monthly_id, '2026-08-01 00:00:00+00'
  );
  IF v_detail IS NULL
    OR (v_detail->>'publicationId')::uuid <> v_duplicate_monthly_id
    OR public.get_mobile_content(
      v_duplicate_sub_user_id, v_duplicate_annual_id, '2026-08-01 00:00:00+00'
    ) IS NOT NULL THEN
    RAISE EXCEPTION 'detail did not resolve the most recent eligible subscription period';
  END IF;

  v_result := public.record_mobile_content_event(
    v_duplicate_sub_user_id,
    v_duplicate_monthly_id,
    v_duplicate_monthly_version,
    'opened',
    'library',
    'task3-recency-event-key',
    '2026-08-01 00:00:00+00'
  );
  IF (v_result->>'publicationId')::uuid <> v_duplicate_monthly_id THEN
    RAISE EXCEPTION 'event did not resolve the most recent eligible subscription period';
  END IF;

  v_result := public.set_mobile_content_saved(
    v_duplicate_sub_user_id,
    v_duplicate_monthly_id,
    v_duplicate_monthly_version,
    true,
    'library',
    'task3-recency-save-key',
    '2026-08-01 00:00:00+00'
  );
  IF (v_result->>'publicationId')::uuid <> v_duplicate_monthly_id
    OR NOT (v_result->>'saved')::boolean THEN
    RAISE EXCEPTION 'save did not resolve the most recent eligible subscription period';
  END IF;

  v_list := public.list_mobile_content(
    v_null_start_user_id, 'library', 'weight_loss', 50, NULL, NULL, '2026-08-01 00:00:00+00'
  );
  IF v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_duplicate_annual_id))
    OR NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_duplicate_monthly_id))) THEN
    RAISE EXCEPTION 'list selected an eligible subscription with a null period start';
  END IF;

  v_detail := public.get_mobile_content(
    v_null_start_user_id, v_duplicate_monthly_id, '2026-08-01 00:00:00+00'
  );
  IF v_detail IS NULL
    OR (v_detail->>'publicationId')::uuid <> v_duplicate_monthly_id
    OR public.get_mobile_content(
      v_null_start_user_id, v_duplicate_annual_id, '2026-08-01 00:00:00+00'
    ) IS NOT NULL THEN
    RAISE EXCEPTION 'detail selected an eligible subscription with a null period start';
  END IF;

  v_result := public.record_mobile_content_event(
    v_null_start_user_id,
    v_duplicate_monthly_id,
    v_duplicate_monthly_version,
    'opened',
    'library',
    'task3-null-start-event-key',
    '2026-08-01 00:00:00+00'
  );
  IF (v_result->>'publicationId')::uuid <> v_duplicate_monthly_id THEN
    RAISE EXCEPTION 'event selected an eligible subscription with a null period start';
  END IF;

  v_result := public.set_mobile_content_saved(
    v_null_start_user_id,
    v_duplicate_monthly_id,
    v_duplicate_monthly_version,
    true,
    'library',
    'task3-null-start-save-key',
    '2026-08-01 00:00:00+00'
  );
  IF (v_result->>'publicationId')::uuid <> v_duplicate_monthly_id
    OR NOT (v_result->>'saved')::boolean THEN
    RAISE EXCEPTION 'save selected an eligible subscription with a null period start';
  END IF;

  v_list := public.list_mobile_content(
    v_elapsed_trial_user_id, 'library', 'weight_loss', 50, NULL, NULL, v_effective_now
  );
  IF v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_trial_target_id)) THEN
    RAISE EXCEPTION 'elapsed trial_ends_at qualified despite a future current_period_end';
  END IF;

  v_list := public.list_mobile_content(
    v_user_id, 'today', NULL, 50, NULL, NULL, v_effective_now
  );
  IF NOT (v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_featured_publication_id)))
    OR v_list->'items' @> jsonb_build_array(jsonb_build_object('publicationId', v_regular_publication_id)) THEN
    RAISE EXCEPTION 'today surface did not enforce featured_today';
  END IF;

  v_list := public.list_mobile_content(
    v_user_id, 'library', 'training', 50, NULL, NULL, v_effective_now
  );
  IF jsonb_array_length(v_list->'items') <> 1
    OR (v_list#>>'{items,0,publicationId}')::uuid <> v_training_publication_id THEN
    RAISE EXCEPTION 'exact category filtering failed';
  END IF;

  v_detail := public.get_mobile_content(
    v_user_id, v_replacement_publication_id, v_effective_now
  );
  IF (v_detail->>'version')::integer <> v_replacement_live_version
    OR (v_detail->>'featuredToday')::boolean THEN
    RAISE EXCEPTION 'live version was displaced by a draft or future replacement';
  END IF;

  v_detail := public.get_mobile_content(
    v_user_id, v_replacement_publication_id, v_future_at + interval '1 minute'
  );
  IF (v_detail->>'version')::integer <> v_replacement_future_version
    OR NOT (v_detail->>'featuredToday')::boolean THEN
    RAISE EXCEPTION 'newest due approved replacement was not selected';
  END IF;

  v_detail := public.get_mobile_content(
    v_user_id,
    v_superseded_schedule_publication_id,
    v_future_at + interval '1 minute'
  );
  IF (v_detail->>'version')::integer <> v_superseded_schedule_latest_version
    OR NOT (v_detail->>'featuredToday')::boolean THEN
    RAISE EXCEPTION 'an older scheduled version displaced a newer immediate publication';
  END IF;

  v_detail := public.get_mobile_content(v_user_id, v_due_publication_id, v_effective_now);
  IF (v_detail->>'version')::integer <> v_due_version
    OR NOT (v_detail->>'featuredToday')::boolean THEN
    RAISE EXCEPTION 'newest currently due approved version was not selected';
  END IF;

  v_list := public.list_mobile_content(
    v_user_id, 'library', 'neuroscience', 10, NULL, NULL, v_effective_now
  );
  IF v_target_guard_new_version <= v_target_guard_old_version
    OR v_list->'items' @> jsonb_build_array(
      jsonb_build_object('publicationId', v_target_guard_publication_id)
    )
    OR public.get_mobile_content(
      v_user_id, v_target_guard_publication_id, v_effective_now
    ) IS NOT NULL THEN
    RAISE EXCEPTION 'newest due ineligible version fell back to an older universal version';
  END IF;

  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_target_guard_publication_id,
      v_target_guard_old_version,
      'opened',
      'library',
      'task3-target-guard-event-key',
      v_effective_now
    );
  EXCEPTION
    WHEN no_data_found THEN
      IF SQLERRM = 'content_not_visible' THEN
        v_target_event_rejected := true;
      END IF;
  END;
  BEGIN
    PERFORM public.set_mobile_content_saved(
      v_user_id,
      v_target_guard_publication_id,
      v_target_guard_old_version,
      true,
      'library',
      'task3-target-guard-save-key',
      v_effective_now
    );
  EXCEPTION
    WHEN no_data_found THEN
      IF SQLERRM = 'content_not_visible' THEN
        v_target_save_rejected := true;
      END IF;
  END;
  IF NOT v_target_event_rejected OR NOT v_target_save_rejected THEN
    RAISE EXCEPTION 'mutation eligibility fell back to an older universal version';
  END IF;

  v_list := public.list_mobile_content(
    v_user_id, 'library', 'hydration', 10, NULL, NULL, v_effective_now
  );
  v_detail := v_list#>'{items,0}';
  IF (v_detail->>'publicationId')::uuid <> v_cover_publication_id
    OR v_detail->'cover' <> jsonb_build_object(
      'bucketId', 'content-covers',
      'objectPath', 'content/' || v_asset_id::text || '.jpg'
    )
    OR v_detail ?| ARRAY[
      'userId', 'email', 'name', 'wpp', 'token', 'accessToken', 'signedUrl',
      'eventKey', 'eventKeyHash', 'coverAssetId', 'bucketId', 'objectPath'
    ]
    OR v_list::text LIKE '%Task 3 Eligible PII Marker%'
    OR v_list::text LIKE '%eligible-task3@example.invalid%'
    OR v_list::text LIKE '%task3-secret-marker%' THEN
    RAISE EXCEPTION 'trusted cover DTO or PII/path leakage contract failed: %', v_detail;
  END IF;

  v_detail := public.get_mobile_content(v_user_id, v_cover_publication_id, v_effective_now);
  IF (v_detail->>'publicationId')::uuid <> v_cover_publication_id
    OR jsonb_typeof(v_detail->'cover') <> 'object'
    OR v_detail->'cover' <> jsonb_build_object(
      'bucketId', 'content-covers',
      'objectPath', 'content/' || v_asset_id::text || '.jpg'
    )
    OR (SELECT count(*) FROM jsonb_object_keys(v_detail->'cover')) <> 2
    OR v_detail ?| ARRAY[
      'userId', 'email', 'name', 'wpp', 'token', 'accessToken', 'signedUrl',
      'eventKey', 'eventKeyHash', 'coverAssetId', 'bucketId', 'objectPath', 'bodyHash'
    ]
    OR v_detail::text LIKE '%Task 3 Eligible PII Marker%'
    OR v_detail::text LIKE '%eligible-task3@example.invalid%'
    OR v_detail::text LIKE '%task3-secret-marker%'
    OR v_detail::text LIKE '%signedUrl%'
    OR v_detail::text LIKE '%eventKey%'
    OR v_detail::text LIKE '%eventKeyHash%'
    OR v_detail::text ~ '[0-9a-f]{64}' THEN
    RAISE EXCEPTION 'detail DTO leaked forbidden data or malformed its cover: %', v_detail;
  END IF;

  SELECT array_agg(publication_id ORDER BY publication_id DESC)
  INTO v_expected_cursor_ids
  FROM unnest(v_cursor_publication_ids) publication_id;

  v_page_one := public.list_mobile_content(
    v_user_id, 'library', 'sleep', 2, NULL, NULL, v_cursor_now
  );
  IF jsonb_array_length(v_page_one->'items') <> 2
    OR (v_page_one#>>'{items,0,publicationId}')::uuid <> v_expected_cursor_ids[1]
    OR (v_page_one#>>'{items,1,publicationId}')::uuid <> v_expected_cursor_ids[2]
    OR (v_page_one#>>'{nextCursor,publicationId}')::uuid <> v_expected_cursor_ids[2]
    OR (v_page_one#>>'{nextCursor,publishAt}')::timestamptz <> v_cursor_at THEN
    RAISE EXCEPTION 'first deterministic cursor page is incorrect: %', v_page_one;
  END IF;

  v_page_two := public.list_mobile_content(
    v_user_id,
    'library',
    'sleep',
    2,
    (v_page_one#>>'{nextCursor,publishAt}')::timestamptz,
    (v_page_one#>>'{nextCursor,publicationId}')::uuid,
    v_cursor_now
  );
  IF jsonb_array_length(v_page_two->'items') <> 1
    OR (v_page_two#>>'{items,0,publicationId}')::uuid <> v_expected_cursor_ids[3]
    OR v_page_two->'nextCursor' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'second deterministic cursor page is incorrect: %', v_page_two;
  END IF;

  BEGIN
    INSERT INTO public.content_version_target_personalities (
      content_version_id,
      personality_code
    ) VALUES (
      (
        SELECT version.id
        FROM public.content_versions version
        WHERE version.publication_id = v_replacement_publication_id
          AND version.state = 'draft'
      ),
      'balanced'
    );
    RAISE EXCEPTION 'non-selectable balanced personality was targetable';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  v_result := public.record_mobile_content_event(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    'impression',
    'library',
    '  task3-impression-key  ',
    v_effective_now
  );
  IF (v_result->>'publicationId')::uuid <> v_state_publication_id
    OR (v_result->>'version')::integer <> v_state_version
    OR (v_result->>'saved')::boolean
    OR (v_result->>'completed')::boolean
    OR (v_result->>'replayed')::boolean
    OR v_result ?| ARRAY['userId', 'eventKey', 'eventKeyHash', 'rawKey', 'hash'] THEN
    RAISE EXCEPTION 'impression response/state contract failed: %', v_result;
  END IF;

  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      NULL,
      'library',
      'task3-null-event-key',
      v_effective_now
    );
    RAISE EXCEPTION 'null content event type was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  v_hash := encode(
    extensions.digest(convert_to('task3-impression-key', 'UTF8'), 'sha256'),
    'hex'
  );
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_events event
    WHERE event.user_id = v_user_id
      AND event.publication_id = v_state_publication_id
      AND event.content_version_id = v_state_version_id
      AND event.event_type = 'impression'
      AND event.origin = 'library'
      AND event.event_key_hash = v_hash
  ) OR EXISTS (
    SELECT 1
    FROM public.content_user_state state
    WHERE state.user_id = v_user_id
      AND state.publication_id = v_state_publication_id
  ) THEN
    RAISE EXCEPTION 'trimmed SHA-256 event hash or impression-only state behavior failed';
  END IF;
  v_first_response := v_result;

  v_replay := public.record_mobile_content_event(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    'impression',
    'library',
    'task3-impression-key',
    v_effective_now
  );
  SELECT count(*)
  INTO v_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.event_key_hash = v_hash;
  IF v_replay <> v_first_response
    OR v_event_count <> 1
    OR v_replay::text LIKE '%' || v_hash || '%'
    OR v_replay::text LIKE '%task3-impression-key%'
    OR NOT EXISTS (
      SELECT 1
      FROM private.content_mutation_receipts receipt
      WHERE receipt.user_id = v_user_id
        AND receipt.event_key_hash = v_hash
        AND receipt.operation = 'record_event'
        AND receipt.publication_id = v_state_publication_id
        AND receipt.content_version = v_state_version
        AND receipt.event_type = 'impression'
        AND receipt.desired_saved IS NULL
        AND receipt.origin = 'library'
        AND receipt.response = v_first_response
    ) THEN
    RAISE EXCEPTION 'same-semantic event retry did not return the exact prior response';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      'impression',
      'today',
      'task3-impression-key',
      v_effective_now
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'event key origin collision was not rejected stably';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_universal_publication_id,
      1,
      'impression',
      'library',
      'task3-impression-key',
      v_effective_now
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'event key publication collision was not rejected stably';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_state_publication_id,
      v_state_version + 1,
      'impression',
      'library',
      'task3-impression-key',
      v_effective_now
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'event key visible-version collision was not rejected stably';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      'opened',
      'library',
      'task3-impression-key',
      v_effective_now
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'event key event-type collision was not rejected stably';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.set_mobile_content_saved(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      false,
      'library',
      'task3-impression-key',
      v_effective_now
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'event key cross-RPC collision was not rejected stably';
  END IF;

  SELECT count(*)
  INTO v_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.event_key_hash = v_hash;
  IF v_event_count <> 1 THEN
    RAISE EXCEPTION 'event collision matrix changed the exact metric count';
  END IF;

  v_legacy_hash := encode(
    extensions.digest(convert_to('task3-legacy-event-key', 'UTF8'), 'sha256'),
    'hex'
  );
  INSERT INTO public.content_events (
    user_id,
    publication_id,
    content_version_id,
    event_type,
    origin,
    event_key_hash,
    occurred_at
  ) VALUES (
    v_user_id,
    v_state_publication_id,
    v_state_version_id,
    'impression',
    'push',
    v_legacy_hash,
    v_effective_now
  );
  v_first_response := public.record_mobile_content_event(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    'impression',
    'push',
    'task3-legacy-event-key',
    v_effective_now
  );
  v_replay := public.record_mobile_content_event(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    'impression',
    'push',
    'task3-legacy-event-key',
    v_effective_now + interval '1 second'
  );
  SELECT count(*)
  INTO v_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.event_key_hash = v_legacy_hash;
  IF v_event_count <> 1
    OR NOT (v_first_response->>'replayed')::boolean
    OR v_replay <> v_first_response
    OR NOT EXISTS (
      SELECT 1
      FROM private.content_mutation_receipts receipt
      WHERE receipt.user_id = v_user_id
        AND receipt.event_key_hash = v_legacy_hash
        AND receipt.response = v_first_response
    ) THEN
    RAISE EXCEPTION 'existing metric event hash was not defensively adopted into receipts';
  END IF;

  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    'opened',
    'library',
    'task3-opened-key',
    v_effective_now
  );
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_user_state state
    WHERE state.user_id = v_user_id
      AND state.publication_id = v_state_publication_id
      AND state.first_opened_at = v_effective_now
      AND state.last_opened_at = v_effective_now
      AND state.last_opened_version_id = v_state_version_id
      AND state.last_origin = 'library'
  ) THEN
    RAISE EXCEPTION 'opened/click event did not update consolidated state';
  END IF;

  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    'completed',
    'library',
    'task3-completed-key',
    v_effective_now + interval '1 second'
  );
  v_detail := public.get_mobile_content(
    v_user_id,
    v_state_publication_id,
    v_effective_now + interval '2 seconds'
  );
  IF NOT (v_detail->>'completed')::boolean THEN
    RAISE EXCEPTION 'completed state is not current for its visible version';
  END IF;

  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_future_version,
    'opened',
    'push',
    'task3-newer-opened-key',
    v_future_at + interval '2 minutes'
  );
  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_live_version,
    'opened',
    'library',
    'task3-delayed-opened-key',
    v_effective_now
  );
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_user_state state
    WHERE state.user_id = v_user_id
      AND state.publication_id = v_replacement_publication_id
      AND state.first_opened_at = v_effective_now
      AND state.last_opened_at = v_future_at + interval '2 minutes'
      AND state.last_opened_version_id = v_replacement_future_version_id
      AND state.last_origin = 'push'
  ) THEN
    RAISE EXCEPTION 'a delayed opened event regressed consolidated content state';
  END IF;

  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_future_version,
    'completed',
    'push',
    'task3-newer-completed-key',
    v_future_at + interval '3 minutes'
  );
  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_live_version,
    'completed',
    'library',
    'task3-delayed-completed-key',
    v_effective_now + interval '1 second'
  );
  IF NOT EXISTS (
    SELECT 1
    FROM public.content_user_state state
    WHERE state.user_id = v_user_id
      AND state.publication_id = v_replacement_publication_id
      AND state.completed_at = v_future_at + interval '3 minutes'
      AND state.completed_version_id = v_replacement_future_version_id
      AND state.last_origin = 'push'
  ) THEN
    RAISE EXCEPTION 'a delayed completed event regressed consolidated content state';
  END IF;

  PERFORM public.record_mobile_content_event(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_future_version,
    'impression',
    'today',
    'task3-newer-impression-key',
    v_future_at + interval '5 minutes'
  );
  PERFORM public.set_mobile_content_saved(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_future_version,
    true,
    'library',
    'task3-newer-saved-key',
    v_future_at + interval '2 minutes 30 seconds'
  );
  v_result := public.set_mobile_content_saved(
    v_user_id,
    v_replacement_publication_id,
    v_replacement_live_version,
    false,
    'library',
    'task3-delayed-unsaved-key',
    v_effective_now + interval '2 seconds'
  );
  IF NOT (v_result->>'saved')::boolean
    OR (v_result->>'changed')::boolean
    OR NOT EXISTS (
      SELECT 1
      FROM public.content_user_state state
      WHERE state.user_id = v_user_id
        AND state.publication_id = v_replacement_publication_id
        AND state.saved_at = v_future_at + interval '2 minutes 30 seconds'
        AND state.last_origin = 'push'
    ) THEN
    RAISE EXCEPTION 'a delayed save mutation regressed consolidated content state';
  END IF;

  v_result := public.set_mobile_content_saved(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    true,
    'library',
    'task3-saved-key',
    v_effective_now + interval '3 seconds'
  );
  IF NOT (v_result->>'saved')::boolean
    OR NOT (v_result->>'changed')::boolean
    OR (v_result->>'replayed')::boolean
    OR v_result ?| ARRAY['eventKey', 'eventKeyHash', 'rawKey', 'hash'] THEN
    RAISE EXCEPTION 'save state transition response failed: %', v_result;
  END IF;
  v_first_response := v_result;
  v_hash := encode(
    extensions.digest(convert_to('task3-saved-key', 'UTF8'), 'sha256'),
    'hex'
  );

  v_replay := public.set_mobile_content_saved(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    true,
    'library',
    'task3-saved-key',
    v_effective_now + interval '30 seconds'
  );
  IF v_replay <> v_first_response
    OR v_replay::text LIKE '%' || v_hash || '%'
    OR v_replay::text LIKE '%task3-saved-key%'
    OR NOT EXISTS (
      SELECT 1
      FROM private.content_mutation_receipts receipt
      WHERE receipt.user_id = v_user_id
        AND receipt.event_key_hash = v_hash
        AND receipt.operation = 'set_saved'
        AND receipt.publication_id = v_state_publication_id
        AND receipt.content_version = v_state_version
        AND receipt.event_type IS NULL
        AND receipt.desired_saved
        AND receipt.origin = 'library'
        AND receipt.response = v_first_response
    ) THEN
    RAISE EXCEPTION 'save event retry did not return the exact prior response';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.set_mobile_content_saved(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      false,
      'library',
      'task3-saved-key',
      v_effective_now + interval '31 seconds'
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'save key desired-state collision was not rejected stably';
  END IF;
  SELECT count(*)
  INTO v_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.event_key_hash = v_hash;
  IF v_event_count <> 1 THEN
    RAISE EXCEPTION 'save collision matrix changed the exact metric count';
  END IF;

  v_result := public.set_mobile_content_saved(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    true,
    'today',
    'task3-save-noop-key',
    v_effective_now + interval '4 seconds'
  );
  SELECT count(*)
  INTO v_saved_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.publication_id = v_state_publication_id
    AND event.event_type IN ('saved', 'unsaved');
  IF (v_result->>'changed')::boolean
    OR NOT (v_result->>'saved')::boolean
    OR v_saved_event_count <> 1 THEN
    RAISE EXCEPTION 'same saved final state was not a no-op';
  END IF;
  v_noop_response := v_result;
  v_hash := encode(
    extensions.digest(convert_to('task3-save-noop-key', 'UTF8'), 'sha256'),
    'hex'
  );
  v_replay := public.set_mobile_content_saved(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    true,
    'today',
    'task3-save-noop-key',
    v_effective_now + interval '40 seconds'
  );
  SELECT count(*)
  INTO v_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.event_key_hash = v_hash;
  SELECT count(*)
  INTO v_receipt_count
  FROM private.content_mutation_receipts receipt
  WHERE receipt.user_id = v_user_id
    AND receipt.event_key_hash = v_hash
    AND receipt.operation = 'set_saved'
    AND receipt.publication_id = v_state_publication_id
    AND receipt.content_version = v_state_version
    AND receipt.event_type IS NULL
    AND receipt.desired_saved
    AND receipt.origin = 'today'
    AND receipt.response = v_noop_response;
  IF v_replay <> v_noop_response
    OR v_event_count <> 0
    OR v_receipt_count <> 1
    OR v_replay::text LIKE '%' || v_hash || '%'
    OR v_replay::text LIKE '%task3-save-noop-key%' THEN
    RAISE EXCEPTION 'no-op save key was not reserved and replayed exactly';
  END IF;

  v_collision_rejected := false;
  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      'impression',
      'today',
      'task3-save-noop-key',
      v_effective_now + interval '41 seconds'
    );
  EXCEPTION
    WHEN SQLSTATE 'P4090' THEN
      IF SQLERRM = 'content_event_key_conflict' THEN
        v_collision_rejected := true;
      END IF;
  END;
  IF NOT v_collision_rejected THEN
    RAISE EXCEPTION 'prior no-op key was reusable with cross-RPC semantics';
  END IF;

  v_result := public.set_mobile_content_saved(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    false,
    'library',
    'task3-unsaved-key',
    v_effective_now + interval '5 seconds'
  );
  IF (v_result->>'saved')::boolean OR NOT (v_result->>'changed')::boolean THEN
    RAISE EXCEPTION 'unsaved state transition failed: %', v_result;
  END IF;

  PERFORM public.set_mobile_content_saved(
    v_user_id,
    v_state_publication_id,
    v_state_version,
    true,
    'library',
    'task3-resaved-key',
    v_effective_now + interval '6 seconds'
  );
  SELECT count(*)
  INTO v_saved_event_count
  FROM public.content_events event
  WHERE event.user_id = v_user_id
    AND event.publication_id = v_state_publication_id
    AND event.event_type IN ('saved', 'unsaved');
  IF v_saved_event_count <> 3 OR NOT EXISTS (
    SELECT 1
    FROM public.content_events event
    WHERE event.user_id = v_user_id
      AND event.publication_id = v_state_publication_id
      AND event.event_type = 'unsaved'
  ) THEN
    RAISE EXCEPTION 'saved/unsaved metrics were not recorded exactly once per state change';
  END IF;

  v_list := public.list_mobile_content(
    v_user_id,
    'saved',
    'using_bodyflow',
    10,
    NULL,
    NULL,
    v_effective_now + interval '7 seconds'
  );
  IF jsonb_array_length(v_list->'items') <> 1
    OR (v_list#>>'{items,0,publicationId}')::uuid <> v_state_publication_id THEN
    RAISE EXCEPTION 'saved surface did not return currently eligible saved content';
  END IF;

  v_result := pg_temp.task3_publish_version(
    v_state_publication_id,
    'pt-BR',
    'using_bodyflow',
    true,
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    NULL,
    NULL,
    v_state_version_id
  );
  v_state_replacement_version := (v_result->>'version')::integer;
  v_effective_now := clock_timestamp() + interval '1 minute';

  v_detail := public.get_mobile_content(v_user_id, v_state_publication_id, v_effective_now);
  IF (v_detail->>'version')::integer <> v_state_replacement_version
    OR NOT (v_detail->>'saved')::boolean
    OR (v_detail->>'completed')::boolean THEN
    RAISE EXCEPTION 'saved persistence or version-scoped completion reset failed';
  END IF;

  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_state_publication_id,
      v_state_version,
      'opened',
      'library',
      'task3-stale-key',
      v_effective_now
    );
  EXCEPTION
    WHEN serialization_failure THEN
      IF SQLERRM = 'content_version_changed' THEN
        v_stale_rejected := true;
      END IF;
  END;
  IF NOT v_stale_rejected THEN
    RAISE EXCEPTION 'stale visible version did not produce the stable conflict error';
  END IF;

  BEGIN
    PERFORM public.record_mobile_content_event(
      v_user_id,
      v_plan_mismatch_id,
      1,
      'opened',
      'library',
      'task3-ineligible-key',
      v_effective_now
    );
  EXCEPTION
    WHEN no_data_found THEN
      IF SQLERRM = 'content_not_visible' THEN
        v_non_visible_rejected := true;
      END IF;
  END;
  IF NOT v_non_visible_rejected THEN
    RAISE EXCEPTION 'non-visible content did not produce the stable opaque not-found error';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.content_events event
    WHERE event.user_id = v_user_id
      AND event.event_key_hash IN (
        encode(extensions.digest(convert_to('task3-stale-key', 'UTF8'), 'sha256'), 'hex'),
        encode(extensions.digest(convert_to('task3-ineligible-key', 'UTF8'), 'sha256'), 'hex'),
        encode(extensions.digest(convert_to('task3-save-noop-key', 'UTF8'), 'sha256'), 'hex')
      )
  ) THEN
    RAISE EXCEPTION 'rejected or no-op mutation persisted an event';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.content_events event
    JOIN public.content_versions content_version
      ON content_version.id = event.content_version_id
    WHERE event.user_id = v_user_id
      AND NOT EXISTS (
        SELECT 1
        FROM private.content_mutation_receipts receipt
        WHERE receipt.user_id = event.user_id
          AND receipt.event_key_hash = event.event_key_hash
          AND receipt.publication_id = event.publication_id
          AND receipt.content_version = content_version.version
          AND receipt.origin = event.origin
          AND (
            (
              receipt.operation = 'record_event'
              AND receipt.event_type = event.event_type
              AND receipt.desired_saved IS NULL
            ) OR (
              receipt.operation = 'set_saved'
              AND receipt.event_type IS NULL
              AND receipt.desired_saved = (event.event_type = 'saved')
            )
          )
      )
  ) THEN
    RAISE EXCEPTION 'an actual metric event lacks its exact technical receipt';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.content_mutation_receipts receipt
    WHERE receipt.user_id = v_user_id
      AND (
        receipt.response ?| ARRAY[
          'userId', 'eventKey', 'eventKeyHash', 'rawKey', 'hash', 'bodyMarkdown',
          'signedUrl', 'email', 'name', 'wpp', 'token', 'accessToken'
        ]
        OR receipt.response::text ~ '[0-9a-f]{64}'
        OR receipt.response::text LIKE '%task3-%-key%'
        OR receipt.response::text LIKE '%Task 3 Eligible PII Marker%'
        OR receipt.response::text LIKE '%eligible-task3@example.invalid%'
        OR receipt.response::text LIKE '%task3-secret-marker%'
      )
  ) THEN
    RAISE EXCEPTION 'receipt response retained a raw key/hash, body, signed URL, or PII marker';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.audit_log audit
    WHERE audit.actor_id IN (v_user_id)
      AND (
        audit.before::text LIKE '%word word word%'
        OR audit.after::text LIKE '%word word word%'
        OR audit.before::text LIKE '%task3-%-key%'
        OR audit.after::text LIKE '%task3-%-key%'
      )
  ) THEN
    RAISE EXCEPTION 'mobile content body or event key was copied into audit';
  END IF;
END;
$test$;

RESET ROLE;

ROLLBACK;

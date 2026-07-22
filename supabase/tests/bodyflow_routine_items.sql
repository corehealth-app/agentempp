BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_column text;
  v_relation text;
  v_function regprocedure;
  v_function_signature text;
  v_privilege text;
  v_constraint_definition text;
  v_index_definition text;
  v_required_columns constant text[] := ARRAY[
    'routine_items.dose_text',
    'routine_items.origin',
    'routine_items.reminders_enabled',
    'routine_items.archived_at',
    'routine_items.version',
    'reminder_rules.deactivated_at',
    'routine_adherence_logs.reminder_rule_id',
    'routine_adherence_logs.occurrence_key',
    'routine_adherence_logs.source',
    'routine_adherence_logs.supersedes_log_id',
    'reminder_events.routine_occurrence_key',
    'reminder_events.routine_action_log_id',
    'notification_deliveries.routine_preview_mode',
    'notification_preferences.routine_preview_mode'
  ];
  v_routine_relations constant text[] := ARRAY[
    'public.notification_preferences',
    'public.reminder_rules',
    'public.routine_items',
    'public.routine_adherence_logs',
    'public.reminder_events',
    'public.notification_deliveries',
    'public.legal_documents',
    'public.user_legal_acceptances'
  ];
  v_patient_read_relations constant text[] := ARRAY[
    'public.notification_preferences',
    'public.reminder_rules',
    'public.routine_items',
    'public.routine_adherence_logs',
    'public.user_legal_acceptances'
  ];
  v_service_mutable_relations constant text[] := ARRAY[
    'public.notification_preferences',
    'public.reminder_rules',
    'public.routine_items',
    'public.reminder_events',
    'public.notification_deliveries'
  ];
  v_service_immutable_relations constant text[] := ARRAY[
    'public.routine_adherence_logs',
    'public.legal_documents',
    'public.user_legal_acceptances'
  ];
  v_client_forbidden_privileges constant text[] := ARRAY[
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'REFERENCES',
    'TRIGGER'
  ];
  v_service_forbidden_privileges constant text[] := ARRAY[
    'DELETE',
    'TRUNCATE',
    'REFERENCES',
    'TRIGGER'
  ];
  v_trigger_functions constant text[] := ARRAY[
    'private.reject_bodyflow_routine_immutable_mutation()',
    'private.enforce_routine_mutation_receipt_result_keys()',
    'private.enforce_notification_delivery_routine_preview()'
  ];
BEGIN
  FOREACH v_column IN ARRAY v_required_columns
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = split_part(v_column, '.', 1)
        AND column_name = split_part(v_column, '.', 2)
    ) THEN
      RAISE EXCEPTION 'missing required routine column public.%', v_column;
    END IF;
  END LOOP;

  IF to_regclass('public.legal_documents') IS NULL
    OR to_regclass('public.user_legal_acceptances') IS NULL
    OR to_regclass('private.routine_mutation_receipts') IS NULL THEN
    RAISE EXCEPTION 'missing routine legal or receipt relation';
  END IF;

  IF to_regclass('public.routine_mutation_receipts') IS NOT NULL THEN
    RAISE EXCEPTION 'private receipt relation is exposed in public';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'routine_adherence_logs'
      AND column_name = 'occurrence_key'
      AND is_nullable = 'YES'
      AND column_default IS NULL
      AND is_generated = 'NEVER'
  ) THEN
    RAISE EXCEPTION 'occurrence identity is not nullable and database-assigned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    CROSS JOIN LATERAL unnest(COALESCE(procedure.proargnames, ARRAY[]::text[])) argument_name
    WHERE namespace.nspname = 'public'
      AND argument_name IN ('occurrence_key', 'p_occurrence_key')
  ) THEN
    RAISE EXCEPTION 'public function accepts a caller-provided occurrence key';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notification_preferences'
      AND column_name = 'routine_preview_mode'
      AND is_nullable = 'NO'
      AND column_default = '''private''::text'
  ) OR NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'routine_items'
      AND column_name = 'reminders_enabled'
      AND is_nullable = 'NO'
      AND column_default = 'true'
  ) OR NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'routine_items'
      AND column_name = 'version'
      AND is_nullable = 'NO'
      AND column_default = '1'
  ) THEN
    RAISE EXCEPTION 'routine persistence defaults are incorrect';
  END IF;

  FOREACH v_relation IN ARRAY ARRAY[
    'public.notification_preferences',
    'public.reminder_rules',
    'public.routine_items',
    'public.routine_adherence_logs',
    'public.reminder_events',
    'public.notification_deliveries',
    'public.legal_documents',
    'public.user_legal_acceptances',
    'private.routine_mutation_receipts'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class relation
      WHERE relation.oid = v_relation::regclass
        AND relation.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'RLS is not enabled on %', v_relation;
    END IF;
  END LOOP;

  SELECT pg_get_constraintdef(constraint_definition.oid)
  INTO v_constraint_definition
  FROM pg_constraint constraint_definition
  WHERE constraint_definition.conname = 'routine_adherence_logs_rule_owner_type_fkey'
    AND constraint_definition.conrelid = 'public.routine_adherence_logs'::regclass;

  IF v_constraint_definition IS NULL
    OR v_constraint_definition NOT LIKE '%FOREIGN KEY (reminder_rule_id, user_id, routine_item_id, item_type)%'
    OR v_constraint_definition NOT LIKE '%REFERENCES reminder_rules(id, user_id, routine_item_id, category)%'
    OR v_constraint_definition NOT LIKE '%ON DELETE RESTRICT%' THEN
    RAISE EXCEPTION 'occurrence rule ownership foreign key is incomplete';
  END IF;

  SELECT pg_get_constraintdef(constraint_definition.oid)
  INTO v_constraint_definition
  FROM pg_constraint constraint_definition
  WHERE constraint_definition.conname = 'routine_adherence_logs_supersedes_owner_fkey'
    AND constraint_definition.conrelid = 'public.routine_adherence_logs'::regclass;

  IF v_constraint_definition IS NULL
    OR v_constraint_definition NOT LIKE '%FOREIGN KEY (supersedes_log_id, user_id, routine_item_id, item_type, occurrence_key)%'
    OR v_constraint_definition NOT LIKE '%REFERENCES routine_adherence_logs(id, user_id, routine_item_id, item_type, occurrence_key)%'
    OR v_constraint_definition NOT LIKE '%ON DELETE RESTRICT%' THEN
    RAISE EXCEPTION 'superseding action ownership foreign key is incomplete';
  END IF;

  SELECT pg_get_constraintdef(constraint_definition.oid)
  INTO v_constraint_definition
  FROM pg_constraint constraint_definition
  WHERE constraint_definition.conname = 'reminder_events_routine_action_owner_fkey'
    AND constraint_definition.conrelid = 'public.reminder_events'::regclass;

  IF v_constraint_definition IS NULL
    OR v_constraint_definition NOT LIKE '%FOREIGN KEY (routine_action_log_id, user_id, reminder_rule_id, routine_occurrence_key)%'
    OR v_constraint_definition NOT LIKE '%REFERENCES routine_adherence_logs(id, user_id, reminder_rule_id, occurrence_key)%'
    OR v_constraint_definition NOT LIKE '%ON DELETE RESTRICT%' THEN
    RAISE EXCEPTION 'reminder action ownership foreign key is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint constraint_definition
    WHERE constraint_definition.conrelid = 'public.routine_adherence_logs'::regclass
      AND constraint_definition.conname = 'routine_adherence_logs_missed_source_new_rows_check'
      AND NOT constraint_definition.convalidated
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint constraint_definition
    WHERE constraint_definition.conrelid = 'public.routine_adherence_logs'::regclass
      AND constraint_definition.conname = 'routine_adherence_logs_skipped_source_new_rows_check'
      AND NOT constraint_definition.convalidated
  ) THEN
    RAISE EXCEPTION 'new-row adherence source constraints are missing or validated';
  END IF;

  SELECT indexdef
  INTO v_index_definition
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname = 'routine_adherence_logs_occurrence_state_idx';

  IF v_index_definition IS NULL
    OR v_index_definition NOT LIKE '%(user_id, occurrence_key, occurred_at DESC, created_at DESC, id DESC)%'
    OR v_index_definition NOT LIKE '%WHERE (occurrence_key IS NOT NULL)%' THEN
    RAISE EXCEPTION 'occurrence state index is missing or incorrectly ordered';
  END IF;

  SELECT indexdef
  INTO v_index_definition
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname = 'routine_adherence_logs_system_missed_occurrence_unique';

  IF v_index_definition IS NULL
    OR v_index_definition NOT LIKE 'CREATE UNIQUE INDEX%'
    OR v_index_definition NOT LIKE '%(user_id, occurrence_key)%'
    OR v_index_definition NOT LIKE '%status = ''missed''%'
    OR v_index_definition NOT LIKE '%source = ''system''%' THEN
    RAISE EXCEPTION 'system missed occurrence uniqueness index is incomplete';
  END IF;

  SELECT indexdef
  INTO v_index_definition
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname = 'reminder_events_routine_action_log_unique';

  IF v_index_definition IS NULL
    OR v_index_definition NOT LIKE 'CREATE UNIQUE INDEX%'
    OR v_index_definition NOT LIKE '%(routine_action_log_id)%'
    OR v_index_definition NOT LIKE '%routine_action_log_id IS NOT NULL%' THEN
    RAISE EXCEPTION 'reminder action uniqueness index is incomplete';
  END IF;

  IF to_regclass('public.legal_documents_current_idx') IS NULL THEN
    RAISE EXCEPTION 'legal current-version index is missing';
  END IF;

  FOREACH v_relation IN ARRAY v_routine_relations
  LOOP
    IF has_table_privilege('anon', v_relation, 'SELECT') THEN
      RAISE EXCEPTION 'anon can read routine or legal relation %', v_relation;
    END IF;

    FOREACH v_privilege IN ARRAY v_client_forbidden_privileges
    LOOP
      IF has_table_privilege('anon', v_relation, v_privilege) THEN
        RAISE EXCEPTION 'anon has forbidden % on %', v_privilege, v_relation;
      END IF;

      IF has_table_privilege('authenticated', v_relation, v_privilege) THEN
        RAISE EXCEPTION 'authenticated has forbidden % on %', v_privilege, v_relation;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_relation IN ARRAY v_patient_read_relations
  LOOP
    IF NOT has_table_privilege('authenticated', v_relation, 'SELECT') THEN
      RAISE EXCEPTION 'authenticated is missing owned read access on %', v_relation;
    END IF;
  END LOOP;

  IF has_table_privilege('authenticated', 'public.legal_documents', 'SELECT')
    OR has_table_privilege('authenticated', 'public.reminder_events', 'SELECT')
    OR has_table_privilege('authenticated', 'public.notification_deliveries', 'SELECT') THEN
    RAISE EXCEPTION 'BFF-only routine data is client-accessible';
  END IF;

  FOREACH v_privilege IN ARRAY ARRAY[
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'REFERENCES',
    'TRIGGER'
  ]
  LOOP
    IF has_table_privilege('anon', 'private.routine_mutation_receipts', v_privilege)
      OR has_table_privilege('authenticated', 'private.routine_mutation_receipts', v_privilege) THEN
      RAISE EXCEPTION 'client role has forbidden % on private receipts', v_privilege;
    END IF;
  END LOOP;

  FOREACH v_relation IN ARRAY v_service_mutable_relations
  LOOP
    IF NOT has_table_privilege('service_role', v_relation, 'SELECT')
      OR NOT has_table_privilege('service_role', v_relation, 'INSERT')
      OR NOT has_table_privilege('service_role', v_relation, 'UPDATE') THEN
      RAISE EXCEPTION 'service role is missing mutable-table operations on %', v_relation;
    END IF;

    FOREACH v_privilege IN ARRAY v_service_forbidden_privileges
    LOOP
      IF has_table_privilege('service_role', v_relation, v_privilege) THEN
        RAISE EXCEPTION 'service role has forbidden % on %', v_privilege, v_relation;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_relation IN ARRAY v_service_immutable_relations
  LOOP
    IF NOT has_table_privilege('service_role', v_relation, 'SELECT')
      OR NOT has_table_privilege('service_role', v_relation, 'INSERT')
      OR has_table_privilege('service_role', v_relation, 'UPDATE') THEN
      RAISE EXCEPTION 'service role immutable-table operations are incorrect on %', v_relation;
    END IF;

    FOREACH v_privilege IN ARRAY v_service_forbidden_privileges
    LOOP
      IF has_table_privilege('service_role', v_relation, v_privilege) THEN
        RAISE EXCEPTION 'service role has forbidden % on %', v_privilege, v_relation;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT has_table_privilege('service_role', 'private.routine_mutation_receipts', 'SELECT')
    OR NOT has_table_privilege('service_role', 'private.routine_mutation_receipts', 'INSERT')
    OR NOT has_table_privilege('service_role', 'private.routine_mutation_receipts', 'UPDATE') THEN
    RAISE EXCEPTION 'service role is missing private receipt operations';
  END IF;

  FOREACH v_privilege IN ARRAY v_service_forbidden_privileges
  LOOP
    IF has_table_privilege('service_role', 'private.routine_mutation_receipts', v_privilege) THEN
      RAISE EXCEPTION 'service role has forbidden % on private receipts', v_privilege;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_legal_acceptances'
      AND cmd = 'SELECT'
      AND roles @> ARRAY['authenticated']::name[]
      AND qual LIKE '%auth.uid()%'
  ) OR EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('legal_documents', 'user_legal_acceptances')
      AND cmd <> 'SELECT'
  ) THEN
    RAISE EXCEPTION 'legal RLS policies do not preserve BFF writes and owned reads';
  END IF;

  FOREACH v_function_signature IN ARRAY v_trigger_functions
  LOOP
    v_function := to_regprocedure(v_function_signature);

    IF v_function IS NULL THEN
      RAISE EXCEPTION 'trusted trigger function is missing';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc procedure
      WHERE procedure.oid = v_function
        AND (
          procedure.prosecdef
          OR NOT COALESCE(procedure.proconfig, ARRAY[]::text[])
            @> ARRAY['search_path=pg_catalog, pg_temp']
        )
    ) OR has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'trusted trigger function security is incorrect';
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.legal_documents'::regclass
      AND tgname = 'legal_documents_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.user_legal_acceptances'::regclass
      AND tgname = 'user_legal_acceptances_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.routine_adherence_logs'::regclass
      AND tgname = 'routine_adherence_logs_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'private.routine_mutation_receipts'::regclass
      AND tgname = 'routine_mutation_receipts_result_keys'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.notification_deliveries'::regclass
      AND tgname = 'notification_deliveries_routine_preview'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'immutable or receipt allowlist trigger is missing';
  END IF;
END;
$test$;

SET LOCAL ROLE anon;

DO $test$
BEGIN
  BEGIN
    PERFORM 1 FROM public.routine_items LIMIT 1;
    RAISE EXCEPTION 'anon read a routine relation';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM 1 FROM public.legal_documents LIMIT 1;
    RAISE EXCEPTION 'anon read a legal relation';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM 1 FROM private.routine_mutation_receipts LIMIT 1;
    RAISE EXCEPTION 'anon read a private receipt relation';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE authenticated;

DO $test$
BEGIN
  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name)
    VALUES ('00000000-0000-0000-0000-000000000801', 'medication', 'Synthetic item');
    RAISE EXCEPTION 'authenticated wrote a routine relation';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.user_legal_acceptances (
      user_id,
      legal_document_id,
      document_key,
      version,
      locale,
      body_hash
    ) VALUES (
      '00000000-0000-0000-0000-000000000801',
      '00000000-0000-0000-0000-000000000899',
      'synthetic_document',
      '1.0',
      'en-US',
      repeat('a', 64)
    );
    RAISE EXCEPTION 'authenticated wrote a legal relation';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

RESET ROLE;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-0000-0000-000000000801';
  v_other_user_id constant uuid := '00000000-0000-0000-0000-000000000802';
  v_auth_user_id constant uuid := '00000000-0000-0000-0000-000000000811';
  v_other_auth_user_id constant uuid := '00000000-0000-0000-0000-000000000812';
  v_item_id constant uuid := '00000000-0000-0000-0000-000000000821';
  v_other_item_id constant uuid := '00000000-0000-0000-0000-000000000822';
  v_supplement_item_id constant uuid := '00000000-0000-0000-0000-000000000823';
  v_same_owner_item_id constant uuid := '00000000-0000-0000-0000-000000000824';
  v_rule_id constant uuid := '00000000-0000-0000-0000-000000000831';
  v_other_rule_id constant uuid := '00000000-0000-0000-0000-000000000832';
  v_supplement_rule_id constant uuid := '00000000-0000-0000-0000-000000000833';
  v_same_owner_rule_id constant uuid := '00000000-0000-0000-0000-000000000834';
  v_hydration_rule_id constant uuid := '00000000-0000-0000-0000-000000000835';
  v_log_id constant uuid := '00000000-0000-0000-0000-000000000841';
  v_other_log_id constant uuid := '00000000-0000-0000-0000-000000000842';
  v_snooze_log_id constant uuid := '00000000-0000-0000-0000-000000000843';
  v_hydration_event_id constant uuid := '00000000-0000-0000-0000-000000000872';
  v_device_id constant uuid := '00000000-0000-0000-0000-000000000881';
  v_old_document_id constant uuid := '00000000-0000-0000-0000-000000000851';
  v_current_document_id constant uuid := '00000000-0000-0000-0000-000000000852';
  v_future_document_id constant uuid := '00000000-0000-0000-0000-000000000853';
  v_old_acceptance_id constant uuid := '00000000-0000-0000-0000-000000000861';
  v_current_acceptance_id constant uuid := '00000000-0000-0000-0000-000000000862';
  v_occurrence_key constant text := repeat('a', 64);
  v_other_occurrence_key constant text := repeat('b', 64);
  v_snooze_occurrence_key constant text := repeat('c', 64);
  v_old_hash text;
  v_current_hash text;
  v_selected_version text;
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
    (
      v_auth_user_id,
      'authenticated',
      'authenticated',
      'bodyflow-routine-test-a@example.invalid',
      '',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    ),
    (
      v_other_auth_user_id,
      'authenticated',
      'authenticated',
      'bodyflow-routine-test-b@example.invalid',
      '',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    );

  INSERT INTO public.users (id, auth_user_id, email, timezone)
  VALUES
    (v_user_id, v_auth_user_id, 'bodyflow-routine-domain-a@example.invalid', 'America/Sao_Paulo'),
    (v_other_user_id, v_other_auth_user_id, 'bodyflow-routine-domain-b@example.invalid', 'America/Sao_Paulo');

  INSERT INTO public.mobile_devices (
    id,
    user_id,
    installation_id,
    apns_environment,
    apns_token
  ) VALUES (
    v_device_id,
    v_user_id,
    'routine-test-installation',
    'sandbox',
    repeat('a', 64)
  );

  INSERT INTO public.routine_items (
    id,
    user_id,
    item_type,
    name,
    dose_text,
    origin,
    reminders_enabled,
    active
  ) VALUES
    (v_item_id, v_user_id, 'medication', 'Synthetic item A', 'Synthetic dose A', 'user', true, true),
    (v_other_item_id, v_other_user_id, 'medication', 'Synthetic item B', 'Synthetic dose B', 'professional', true, true),
    (v_supplement_item_id, v_user_id, 'supplement', 'Synthetic item C', 'Synthetic dose C', 'protocol', true, true),
    (v_same_owner_item_id, v_user_id, 'medication', 'Synthetic item D', 'Synthetic dose D', 'other', true, true);

  INSERT INTO public.reminder_rules (
    id,
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays
  ) VALUES
    (v_rule_id, v_user_id, v_item_id, 'medication', time '08:00', ARRAY[1, 2, 3]),
    (v_other_rule_id, v_other_user_id, v_other_item_id, 'medication', time '09:00', ARRAY[1, 2, 3]),
    (v_supplement_rule_id, v_user_id, v_supplement_item_id, 'supplement', time '10:00', ARRAY[1, 2, 3]),
    (v_same_owner_rule_id, v_user_id, v_same_owner_item_id, 'medication', time '11:00', ARRAY[1, 2, 3]),
    (v_hydration_rule_id, v_user_id, NULL, 'hydration', time '12:00', ARRAY[1, 2, 3]);

  INSERT INTO public.routine_adherence_logs (
    id,
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    reminder_rule_id,
    occurrence_key,
    source,
    scheduled_for,
    occurred_at
  ) VALUES
    (
      v_log_id,
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-test-log-a',
      v_rule_id,
      v_occurrence_key,
      'patient',
      timestamptz '2026-07-22 11:00:00+00',
      timestamptz '2026-07-22 11:01:00+00'
    ),
    (
      v_other_log_id,
      v_other_user_id,
      v_other_item_id,
      'medication',
      'taken',
      'routine-test-log-b',
      v_other_rule_id,
      v_other_occurrence_key,
      'offline_sync',
      timestamptz '2026-07-22 12:00:00+00',
      timestamptz '2026-07-22 12:01:00+00'
    );

  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name, dose_text, origin)
    VALUES (v_user_id, 'medication', 'Synthetic item', 'Synthetic dose', 'invalid');
    RAISE EXCEPTION 'invalid routine origin was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name, dose_text)
    VALUES (v_user_id, 'medication', '   ', 'Synthetic dose');
    RAISE EXCEPTION 'blank routine name was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name, dose_text)
    VALUES (v_user_id, 'medication', repeat('n', 201), 'Synthetic dose');
    RAISE EXCEPTION 'oversized routine name was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name, dose_text)
    VALUES (v_user_id, 'medication', 'Synthetic item', '   ');
    RAISE EXCEPTION 'blank routine dose was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name, dose_text)
    VALUES (v_user_id, 'medication', 'Synthetic item', repeat('d', 121));
    RAISE EXCEPTION 'oversized routine dose was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (user_id, item_type, name, version)
    VALUES (v_user_id, 'medication', 'Synthetic item', 0);
    RAISE EXCEPTION 'nonpositive routine version was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (
      user_id,
      item_type,
      name,
      active,
      reminders_enabled,
      archived_at
    ) VALUES (
      v_user_id,
      'medication',
      'Synthetic item',
      true,
      false,
      clock_timestamp()
    );
    RAISE EXCEPTION 'active archived routine item was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_items (
      user_id,
      item_type,
      name,
      active,
      reminders_enabled,
      archived_at
    ) VALUES (
      v_user_id,
      'medication',
      'Synthetic item',
      false,
      true,
      clock_timestamp()
    );
    RAISE EXCEPTION 'archived routine item with reminders was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.routine_items (
    user_id,
    item_type,
    name,
    active,
    reminders_enabled,
    archived_at
  ) VALUES (
    v_user_id,
    'medication',
    'Synthetic archived item',
    false,
    false,
    clock_timestamp()
  );

  BEGIN
    INSERT INTO public.reminder_rules (
      user_id,
      routine_item_id,
      category,
      local_time,
      weekdays,
      active,
      deactivated_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      time '11:00',
      ARRAY[4],
      true,
      clock_timestamp()
    );
    RAISE EXCEPTION 'active deactivated reminder rule was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays,
    active,
    deactivated_at
  ) VALUES (
    v_user_id,
    v_item_id,
    'medication',
    time '12:00',
    ARRAY[4],
    false,
    clock_timestamp()
  );

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays,
    active
  ) VALUES (
    v_user_id,
    v_item_id,
    'medication',
    time '13:00',
    ARRAY[4],
    false
  );

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'invalid',
      'routine-invalid-status',
      clock_timestamp()
    );
    RAISE EXCEPTION 'invalid routine status was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'missed',
      'routine-null-source-missed',
      clock_timestamp()
    );
    RAISE EXCEPTION 'null-source missed action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      source,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'skipped',
      'routine-system-source-skipped',
      'system',
      clock_timestamp()
    );
    RAISE EXCEPTION 'system-source skipped action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.routine_adherence_logs (
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    occurred_at
  ) VALUES (
    v_user_id,
    v_item_id,
    'medication',
    'taken',
    'routine-legacy-null-source-taken',
    clock_timestamp()
  );

  INSERT INTO public.routine_adherence_logs (
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    occurred_at,
    snoozed_until
  ) VALUES (
    v_user_id,
    v_item_id,
    'medication',
    'snoozed',
    'routine-legacy-null-source-snoozed',
    clock_timestamp(),
    clock_timestamp()
  );

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      source,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-invalid-source',
      'invalid',
      clock_timestamp()
    );
    RAISE EXCEPTION 'invalid routine source was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-invalid-key',
      v_rule_id,
      'not-a-hash',
      'patient',
      timestamptz '2026-07-22 13:00:00+00',
      timestamptz '2026-07-22 13:01:00+00'
    );
    RAISE EXCEPTION 'malformed occurrence key was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      occurrence_key,
      source,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-incomplete-key',
      repeat('d', 64),
      'patient',
      clock_timestamp()
    );
    RAISE EXCEPTION 'occurrence key without rule and schedule was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-cross-user-rule',
      v_other_rule_id,
      repeat('e', 64),
      'patient',
      timestamptz '2026-07-22 14:00:00+00',
      timestamptz '2026-07-22 14:01:00+00'
    );
    RAISE EXCEPTION 'cross-user occurrence rule was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-cross-item-rule',
      v_same_owner_rule_id,
      repeat('6', 64),
      'patient',
      timestamptz '2026-07-22 14:30:00+00',
      timestamptz '2026-07-22 14:31:00+00'
    );
    RAISE EXCEPTION 'same-owner same-type cross-item rule was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-cross-type-rule',
      v_supplement_rule_id,
      repeat('f', 64),
      'patient',
      timestamptz '2026-07-22 15:00:00+00',
      timestamptz '2026-07-22 15:01:00+00'
    );
    RAISE EXCEPTION 'cross-type occurrence rule was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at,
      supersedes_log_id
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-cross-occurrence-supersede',
      v_rule_id,
      repeat('7', 64),
      'patient',
      timestamptz '2026-07-22 19:15:00+00',
      timestamptz '2026-07-22 19:16:00+00',
      v_log_id
    );
    RAISE EXCEPTION 'cross-occurrence superseding action was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'missed',
      'routine-patient-missed',
      v_rule_id,
      repeat('1', 64),
      'patient',
      timestamptz '2026-07-22 16:00:00+00',
      timestamptz '2026-07-22 16:01:00+00'
    );
    RAISE EXCEPTION 'patient-authored missed action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.routine_adherence_logs (
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    reminder_rule_id,
    occurrence_key,
    source,
    scheduled_for,
    occurred_at
  ) VALUES (
    v_user_id,
    v_item_id,
    'medication',
    'missed',
    'routine-system-missed-a',
    v_rule_id,
    repeat('2', 64),
    'system',
    timestamptz '2026-07-22 17:00:00+00',
    timestamptz '2026-07-23 03:00:00+00'
  );

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'missed',
      'routine-system-missed-b',
      v_rule_id,
      repeat('2', 64),
      'system',
      timestamptz '2026-07-22 17:00:00+00',
      timestamptz '2026-07-23 03:01:00+00'
    );
    RAISE EXCEPTION 'duplicate system missed action was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  INSERT INTO public.routine_adherence_logs (
    id,
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    reminder_rule_id,
    occurrence_key,
    source,
    scheduled_for,
    occurred_at,
    snoozed_until
  ) VALUES (
    v_snooze_log_id,
    v_user_id,
    v_item_id,
    'medication',
    'snoozed',
    'routine-snooze-timing',
    v_rule_id,
    v_snooze_occurrence_key,
    'patient',
    timestamptz '2026-07-22 18:00:00+00',
    timestamptz '2026-07-22 18:01:00+00',
    timestamptz '2026-07-22 18:01:00+00'
  );

  INSERT INTO public.routine_adherence_logs (
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    reminder_rule_id,
    occurrence_key,
    source,
    scheduled_for,
    occurred_at,
    snoozed_until
  ) VALUES (
    v_user_id,
    v_item_id,
    'medication',
    'snoozed',
    'routine-snooze-cross-day',
    v_rule_id,
    repeat('0', 64),
    'patient',
    timestamptz '2026-07-22 18:15:00+00',
    timestamptz '2026-07-22 18:16:00+00',
    timestamptz '2026-07-23 18:16:00+00'
  );

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at,
      supersedes_log_id
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-cross-user-supersede',
      v_rule_id,
      repeat('3', 64),
      'patient',
      timestamptz '2026-07-22 19:00:00+00',
      timestamptz '2026-07-22 19:01:00+00',
      v_other_log_id
    );
    RAISE EXCEPTION 'cross-user superseding action was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.routine_adherence_logs (
      user_id,
      routine_item_id,
      item_type,
      status,
      idempotency_key,
      reminder_rule_id,
      occurrence_key,
      source,
      scheduled_for,
      occurred_at,
      supersedes_log_id
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'skipped',
      'routine-invalid-supersede',
      v_rule_id,
      repeat('4', 64),
      'patient',
      timestamptz '2026-07-22 20:00:00+00',
      timestamptz '2026-07-22 20:01:00+00',
      v_log_id
    );
    RAISE EXCEPTION 'non-corrective superseding action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.routine_adherence_logs
    SET occurred_at = occurred_at + interval '1 second'
    WHERE id = v_log_id;
    RAISE EXCEPTION 'previous routine action was edited';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.routine_adherence_logs WHERE id = v_log_id;
    RAISE EXCEPTION 'previous routine action was deleted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.reminder_events (
    id,
    user_id,
    reminder_rule_id,
    scheduled_for,
    status,
    routine_occurrence_key,
    routine_action_log_id
  ) VALUES (
    '00000000-0000-0000-0000-000000000871',
    v_user_id,
    v_rule_id,
    timestamptz '2026-07-22 18:30:00+00',
    'queued',
    v_snooze_occurrence_key,
    v_snooze_log_id
  );

  BEGIN
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      routine_occurrence_key,
      routine_action_log_id
    ) VALUES (
      v_user_id,
      v_rule_id,
      timestamptz '2026-07-22 18:31:00+00',
      'queued',
      v_snooze_occurrence_key,
      v_snooze_log_id
    );
    RAISE EXCEPTION 'duplicate snooze follow-up event was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      routine_occurrence_key,
      routine_action_log_id
    ) VALUES (
      v_user_id,
      v_rule_id,
      timestamptz '2026-07-22 18:32:00+00',
      'queued',
      repeat('5', 64),
      v_other_log_id
    );
    RAISE EXCEPTION 'cross-user reminder action reference was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      routine_occurrence_key,
      routine_action_log_id
    ) VALUES (
      v_user_id,
      v_supplement_rule_id,
      timestamptz '2026-07-22 18:34:00+00',
      'queued',
      v_snooze_occurrence_key,
      v_snooze_log_id
    );
    RAISE EXCEPTION 'event action with a mismatched reminder rule was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      routine_occurrence_key,
      routine_action_log_id
    ) VALUES (
      v_user_id,
      v_rule_id,
      timestamptz '2026-07-22 18:35:00+00',
      'queued',
      repeat('8', 64),
      v_snooze_log_id
    );
    RAISE EXCEPTION 'event action with a mismatched occurrence key was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      routine_occurrence_key
    ) VALUES (
      v_user_id,
      v_rule_id,
      timestamptz '2026-07-22 18:33:00+00',
      'queued',
      'not-a-hash'
    );
    RAISE EXCEPTION 'malformed event occurrence key was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.reminder_events (
    id,
    user_id,
    reminder_rule_id,
    scheduled_for,
    status
  ) VALUES (
    v_hydration_event_id,
    v_user_id,
    v_hydration_rule_id,
    timestamptz '2026-07-22 19:00:00+00',
    'queued'
  );

  INSERT INTO public.notification_preferences (user_id)
  VALUES (v_user_id);

  IF NOT EXISTS (
    SELECT 1
    FROM public.notification_preferences
    WHERE user_id = v_user_id
      AND routine_preview_mode = 'private'
  ) THEN
    RAISE EXCEPTION 'routine preview default is not private';
  END IF;

  BEGIN
    UPDATE public.notification_preferences
    SET routine_preview_mode = 'invalid'
    WHERE user_id = v_user_id;
    RAISE EXCEPTION 'invalid preference preview mode was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.notification_deliveries (
      user_id,
      reminder_event_id,
      mobile_device_id,
      channel,
      provider,
      template_key,
      personality,
      scheduled_for,
      routine_preview_mode
    ) VALUES (
      v_user_id,
      '00000000-0000-0000-0000-000000000871',
      v_device_id,
      'push',
      'apns',
      'synthetic.template',
      'synthetic',
      timestamptz '2026-07-22 18:30:00+00',
      'invalid'
    );
    RAISE EXCEPTION 'invalid delivery preview mode was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.notification_deliveries (
      user_id,
      reminder_event_id,
      mobile_device_id,
      channel,
      provider,
      template_key,
      personality,
      scheduled_for,
      routine_preview_mode
    ) VALUES (
      v_user_id,
      '00000000-0000-0000-0000-000000000871',
      v_device_id,
      'push',
      'apns',
      'synthetic.template',
      'synthetic',
      timestamptz '2026-07-22 18:30:00+00',
      NULL
    );
    RAISE EXCEPTION 'routine delivery without a preview mode was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.notification_deliveries (
      user_id,
      reminder_event_id,
      mobile_device_id,
      channel,
      provider,
      template_key,
      personality,
      scheduled_for,
      routine_preview_mode
    ) VALUES (
      v_user_id,
      v_hydration_event_id,
      v_device_id,
      'push',
      'apns',
      'synthetic.template',
      'synthetic',
      timestamptz '2026-07-22 19:00:00+00',
      'private'
    );
    RAISE EXCEPTION 'non-routine delivery with a preview mode was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  IF (
    SELECT count(*)
    FROM public.legal_documents
    WHERE document_key = 'medication_reminder_disclaimer'
      AND version = '2026-07-22.1'
      AND (
        (locale = 'pt-BR'
          AND body = 'O BodyFlow apenas organiza lembretes e registros. Ele não prescreve, recomenda nem altera medicamentos ou doses. Siga a orientação do profissional de saúde responsável.')
        OR (locale = 'en-US'
          AND body = 'BodyFlow only organizes reminders and records. It does not prescribe, recommend or change medications or doses. Follow the guidance of the responsible healthcare professional.')
      )
      AND body_hash = encode(extensions.digest(body, 'sha256'), 'hex')
      AND body_hash ~ '^[0-9a-f]{64}$'
  ) <> 2 THEN
    RAISE EXCEPTION 'versioned medication disclaimer seed is incomplete';
  END IF;

  BEGIN
    INSERT INTO public.legal_documents (
      document_key,
      version,
      locale,
      body,
      required_from
    ) VALUES ('Invalid-Key', '1.0', 'en-US', 'Synthetic legal copy', now());
    RAISE EXCEPTION 'invalid legal document key was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.legal_documents (
      document_key,
      version,
      locale,
      body,
      required_from
    ) VALUES ('synthetic_document', 'invalid version', 'en-US', 'Synthetic legal copy', now());
    RAISE EXCEPTION 'invalid legal document version was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.legal_documents (
      document_key,
      version,
      locale,
      body,
      required_from
    ) VALUES ('synthetic_document', '1.0', 'es-CO', 'Synthetic legal copy', now());
    RAISE EXCEPTION 'invalid legal locale was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.legal_documents (
      document_key,
      version,
      locale,
      body,
      required_from
    ) VALUES ('synthetic_document', '1.0', 'en-US', '   ', now());
    RAISE EXCEPTION 'blank legal body was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.legal_documents (
      document_key,
      version,
      locale,
      body,
      required_from
    ) VALUES ('synthetic_document', '1.0', 'en-US', repeat('x', 4001), now());
    RAISE EXCEPTION 'oversized legal body was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.legal_documents (
    id,
    document_key,
    version,
    locale,
    body,
    required_from
  ) VALUES
    (
      v_old_document_id,
      'synthetic_disclaimer',
      '1.0',
      'en-US',
      'Synthetic legal copy version one.',
      clock_timestamp() - interval '2 days'
    ),
    (
      v_current_document_id,
      'synthetic_disclaimer',
      '2.0',
      'en-US',
      'Synthetic legal copy version two.',
      clock_timestamp() - interval '1 day'
    ),
    (
      v_future_document_id,
      'synthetic_disclaimer',
      '3.0',
      'en-US',
      'Synthetic legal copy version three.',
      clock_timestamp() + interval '1 day'
    );

  SELECT version
  INTO v_selected_version
  FROM public.legal_documents
  WHERE document_key = 'synthetic_disclaimer'
    AND locale = 'en-US'
    AND required_from <= clock_timestamp()
  ORDER BY required_from DESC
  LIMIT 1;

  IF v_selected_version <> '2.0' THEN
    RAISE EXCEPTION 'current legal version selection is not greatest due version';
  END IF;

  SELECT body_hash INTO v_old_hash
  FROM public.legal_documents
  WHERE id = v_old_document_id;

  SELECT body_hash INTO v_current_hash
  FROM public.legal_documents
  WHERE id = v_current_document_id;

  INSERT INTO public.user_legal_acceptances (
    id,
    user_id,
    legal_document_id,
    document_key,
    version,
    locale,
    body_hash
  ) VALUES
    (
      v_old_acceptance_id,
      v_user_id,
      v_old_document_id,
      'synthetic_disclaimer',
      '1.0',
      'en-US',
      v_old_hash
    ),
    (
      v_current_acceptance_id,
      v_user_id,
      v_current_document_id,
      'synthetic_disclaimer',
      '2.0',
      'en-US',
      v_current_hash
    );

  IF NOT EXISTS (
    SELECT 1
    FROM public.legal_documents
    WHERE id = v_old_document_id
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.user_legal_acceptances
    WHERE id = v_old_acceptance_id
      AND body_hash = v_old_hash
  ) THEN
    RAISE EXCEPTION 'new legal requirement replaced prior audit history';
  END IF;

  BEGIN
    INSERT INTO public.user_legal_acceptances (
      user_id,
      legal_document_id,
      document_key,
      version,
      locale,
      body_hash
    ) VALUES (
      v_user_id,
      v_old_document_id,
      'synthetic_disclaimer',
      '1.0',
      'en-US',
      v_old_hash
    );
    RAISE EXCEPTION 'duplicate patient document acceptance was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.user_legal_acceptances (
      user_id,
      legal_document_id,
      document_key,
      version,
      locale,
      body_hash
    ) VALUES (
      v_other_user_id,
      v_current_document_id,
      'synthetic_disclaimer',
      '2.0',
      'en-US',
      repeat('0', 64)
    );
    RAISE EXCEPTION 'acceptance with an unshown document hash was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.legal_documents
    SET document_key = 'synthetic_disclaimer_changed'
    WHERE id = v_old_document_id;
    RAISE EXCEPTION 'legal document key was edited';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.legal_documents
    SET version = '1.1'
    WHERE id = v_old_document_id;
    RAISE EXCEPTION 'legal document version was edited';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.legal_documents
    SET locale = 'pt-BR'
    WHERE id = v_old_document_id;
    RAISE EXCEPTION 'legal document locale was edited';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.legal_documents
    SET body = 'Synthetic changed legal copy.'
    WHERE id = v_old_document_id;
    RAISE EXCEPTION 'legal document body or hash was edited';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.legal_documents WHERE id = v_old_document_id;
    RAISE EXCEPTION 'legal document was deleted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.user_legal_acceptances
    SET accepted_at = accepted_at + interval '1 second'
    WHERE id = v_old_acceptance_id;
    RAISE EXCEPTION 'legal acceptance was edited';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.user_legal_acceptances WHERE id = v_old_acceptance_id;
    RAISE EXCEPTION 'legal acceptance was deleted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO private.routine_mutation_receipts (
    user_id,
    idempotency_key,
    operation,
    request_hash,
    result_payload
  ) VALUES (
    v_user_id,
    'receipt-valid-001',
    'routine_item_create',
    repeat('6', 64),
    jsonb_build_object(
      'routine_item_id', v_item_id,
      'version', 1,
      'archived_at', NULL,
      'document_key', 'synthetic_disclaimer',
      'accepted_version', '2.0',
      'accepted_at', timestamptz '2026-07-22 20:00:00+00'
    )
  );

  BEGIN
    INSERT INTO private.routine_mutation_receipts (
      user_id,
      idempotency_key,
      operation,
      request_hash,
      result_payload
    ) VALUES (
      v_user_id,
      'short',
      'routine_item_create',
      repeat('7', 64),
      '{}'::jsonb
    );
    RAISE EXCEPTION 'invalid receipt idempotency key was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO private.routine_mutation_receipts (
      user_id,
      idempotency_key,
      operation,
      request_hash,
      result_payload
    ) VALUES (
      v_user_id,
      'receipt-invalid-operation',
      'invalid',
      repeat('7', 64),
      '{}'::jsonb
    );
    RAISE EXCEPTION 'invalid receipt operation was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO private.routine_mutation_receipts (
      user_id,
      idempotency_key,
      operation,
      request_hash,
      result_payload
    ) VALUES (
      v_user_id,
      'receipt-invalid-hash',
      'routine_item_update',
      repeat('A', 64),
      '{}'::jsonb
    );
    RAISE EXCEPTION 'invalid receipt request hash was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO private.routine_mutation_receipts (
      user_id,
      idempotency_key,
      operation,
      request_hash,
      result_payload
    ) VALUES (
      v_user_id,
      'receipt-invalid-shape',
      'routine_item_archive',
      repeat('8', 64),
      '[]'::jsonb
    );
    RAISE EXCEPTION 'non-object receipt result was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO private.routine_mutation_receipts (
      user_id,
      idempotency_key,
      operation,
      request_hash,
      result_payload
    ) VALUES (
      v_user_id,
      'receipt-forbidden-key',
      'legal_acceptance',
      repeat('9', 64),
      jsonb_build_object('forbidden', 'synthetic')
    );
    RAISE EXCEPTION 'receipt result key outside allowlist was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END;
$test$;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000811","role":"authenticated"}',
  true
);

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-0000-0000-000000000801';
  v_other_user_id constant uuid := '00000000-0000-0000-0000-000000000802';
BEGIN
  IF (SELECT count(*) FROM public.routine_items WHERE user_id = v_user_id) < 1
    OR EXISTS (SELECT 1 FROM public.routine_items WHERE user_id = v_other_user_id)
    OR (SELECT count(*) FROM public.reminder_rules WHERE user_id = v_user_id) < 1
    OR EXISTS (SELECT 1 FROM public.reminder_rules WHERE user_id = v_other_user_id)
    OR (SELECT count(*) FROM public.routine_adherence_logs WHERE user_id = v_user_id) < 1
    OR EXISTS (SELECT 1 FROM public.routine_adherence_logs WHERE user_id = v_other_user_id)
    OR (SELECT count(*) FROM public.user_legal_acceptances WHERE user_id = v_user_id) <> 2
    OR EXISTS (SELECT 1 FROM public.user_legal_acceptances WHERE user_id = v_other_user_id) THEN
    RAISE EXCEPTION 'patient ownership reads leaked or hid routine data';
  END IF;

  BEGIN
    PERFORM 1 FROM public.legal_documents LIMIT 1;
    RAISE EXCEPTION 'patient read BFF-only legal document text';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    UPDATE public.routine_items
    SET active = false
    WHERE user_id = v_user_id;
    RAISE EXCEPTION 'patient directly changed routine persistence';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

RESET ROLE;
ROLLBACK;

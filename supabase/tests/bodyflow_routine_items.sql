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
    'private.enforce_notification_delivery_routine_preview()',
    'private.enforce_routine_adherence_correction()',
    'private.enforce_reminder_event_routine_action()'
  ];
  v_public_api_functions constant text[] := ARRAY[
    'public.create_mobile_routine_item(uuid,text,jsonb,text,text)',
    'public.update_mobile_routine_item(uuid,uuid,integer,jsonb,text,text)',
    'public.archive_mobile_routine_item(uuid,uuid,text,text)',
    'public.list_mobile_routine_items(uuid,text,boolean,timestamp with time zone)',
    'public.list_mobile_routine_history(uuid,uuid,text,integer,timestamp with time zone,uuid)',
    'public.record_routine_occurrence_action_atomic(uuid,uuid,text,uuid,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text)',
    'public.get_mobile_legal_document(uuid,text)',
    'public.accept_mobile_legal_document(uuid,text,text,text,text)'
  ];
  v_private_api_functions constant text[] := ARRAY[
    'private.routine_user_timezone(uuid)',
    'private.canonicalize_routine_schedules(jsonb)',
    'private.routine_same_local_date(uuid,timestamp with time zone,timestamp with time zone)',
    'private.derive_routine_occurrence_key(uuid,timestamp with time zone)',
    'private.lock_routine_occurrence(uuid,text)',
    'private.lock_routine_item(uuid,uuid,text,boolean)',
    'private.read_routine_mutation_receipt(uuid,text,text,text)',
    'private.write_routine_mutation_receipt(uuid,text,text,text,jsonb)',
    'private.assert_current_medication_legal_acceptance(uuid)'
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
  WHERE constraint_definition.conname = 'routine_adherence_logs_supersedes_distinct_check'
    AND constraint_definition.conrelid = 'public.routine_adherence_logs'::regclass;

  IF v_constraint_definition IS NULL
    OR v_constraint_definition NOT LIKE '%supersedes_log_id <> id%' THEN
    RAISE EXCEPTION 'superseding action self-reference check is incomplete';
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

  FOREACH v_function_signature IN ARRAY v_public_api_functions
  LOOP
    v_function := to_regprocedure(v_function_signature);

    IF v_function IS NULL THEN
      RAISE EXCEPTION 'routine public API function is missing: %', v_function_signature;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc procedure
      WHERE procedure.oid = v_function
        AND procedure.prosecdef
        AND COALESCE(procedure.proconfig, ARRAY[]::text[])
          @> ARRAY['search_path=pg_catalog, public, private, pg_temp']
        AND pg_get_functiondef(procedure.oid)
          LIKE '%PERFORM private.assert_trusted_backend();%'
    ) OR has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'routine public API function security is incorrect: %', v_function_signature;
    END IF;
  END LOOP;

  FOREACH v_function_signature IN ARRAY v_private_api_functions
  LOOP
    v_function := to_regprocedure(v_function_signature);

    IF v_function IS NULL THEN
      RAISE EXCEPTION 'routine private API helper is missing: %', v_function_signature;
    END IF;

    IF has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'routine private API helper security is incorrect: %', v_function_signature;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    CROSS JOIN LATERAL unnest(COALESCE(procedure.proargnames, ARRAY[]::text[])) argument_name
    WHERE namespace.nspname = 'public'
      AND procedure.proname IN ('list_mobile_routine_items', 'list_mobile_routine_history')
      AND argument_name IN (
        'timezone', 'p_timezone', 'local_date', 'p_local_date',
        'occurrence_key', 'p_occurrence_key'
      )
  ) THEN
    RAISE EXCEPTION 'routine read API accepts caller-derived time or occurrence identity';
  END IF;

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
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.routine_adherence_logs'::regclass
      AND tgname = 'routine_adherence_logs_correction'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.reminder_events'::regclass
      AND tgname = 'reminder_events_routine_action'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'routine integrity trigger is missing';
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
  v_self_reference_log_id constant uuid := '00000000-0000-0000-0000-000000000844';
  v_non_system_missed_log_id constant uuid := '00000000-0000-0000-0000-000000000845';
  v_not_prior_missed_log_id constant uuid := '00000000-0000-0000-0000-000000000846';
  v_correctable_missed_log_id constant uuid := '00000000-0000-0000-0000-000000000847';
  v_corrected_log_id constant uuid := '00000000-0000-0000-0000-000000000848';
  v_same_statement_missed_log_id constant uuid := '00000000-0000-0000-0000-000000000849';
  v_same_statement_correction_log_id constant uuid := '00000000-0000-0000-0000-000000000850';
  v_same_statement_snooze_log_id constant uuid := '00000000-0000-0000-0000-000000000891';
  v_hydration_event_id constant uuid := '00000000-0000-0000-0000-000000000872';
  v_alternate_routine_event_id constant uuid := '00000000-0000-0000-0000-000000000873';
  v_device_id constant uuid := '00000000-0000-0000-0000-000000000881';
  v_legacy_delivery_id constant uuid := '00000000-0000-0000-0000-000000000882';
  v_old_document_id constant uuid := '00000000-0000-0000-0000-000000000851';
  v_current_document_id constant uuid := '00000000-0000-0000-0000-000000000852';
  v_future_document_id constant uuid := '00000000-0000-0000-0000-000000000853';
  v_old_acceptance_id constant uuid := '00000000-0000-0000-0000-000000000861';
  v_current_acceptance_id constant uuid := '00000000-0000-0000-0000-000000000862';
  v_occurrence_key constant text := repeat('a', 64);
  v_other_occurrence_key constant text := repeat('b', 64);
  v_snooze_occurrence_key constant text := repeat('c', 64);
  v_non_system_occurrence_key constant text := repeat('9', 64);
  v_not_prior_occurrence_key constant text := repeat('d', 64);
  v_correction_occurrence_key constant text := repeat('e', 64);
  v_old_hash text;
  v_current_hash text;
  v_selected_version text;
BEGIN
  IF private.derive_routine_occurrence_key(
    '00000000-0000-0000-0000-000000000001',
    timestamptz '1970-01-01 00:00:00+00'
  ) <> 'b5e2f590802383c15604fb003b96237aa47b5cb979264fbadedc36d499006701' THEN
    RAISE EXCEPTION 'routine occurrence key is not canonical UUID plus UTC epoch microseconds';
  END IF;

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

  BEGIN
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
      created_at,
      supersedes_log_id
    ) VALUES (
      v_self_reference_log_id,
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-self-reference-correction',
      v_rule_id,
      repeat('4', 64),
      'patient',
      timestamptz '2026-07-22 17:10:00+00',
      timestamptz '2026-07-22 17:11:00+00',
      timestamptz '2026-07-22 17:12:00+00',
      v_self_reference_log_id
    );
    RAISE EXCEPTION 'self-referencing correction was accepted';
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
      occurred_at,
      created_at,
      supersedes_log_id
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-non-missed-correction',
      v_rule_id,
      v_occurrence_key,
      'patient',
      timestamptz '2026-07-22 11:00:00+00',
      timestamptz '2026-07-22 11:02:00+00',
      timestamptz '2026-07-22 17:13:00+00',
      v_log_id
    );
    RAISE EXCEPTION 'correction of a non-missed action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  ALTER TABLE public.routine_adherence_logs
    DROP CONSTRAINT routine_adherence_logs_missed_source_check,
    DROP CONSTRAINT routine_adherence_logs_missed_source_new_rows_check;

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
    created_at
  ) VALUES (
    v_non_system_missed_log_id,
    v_user_id,
    v_item_id,
    'medication',
    'missed',
    'routine-legacy-non-system-missed',
    v_rule_id,
    v_non_system_occurrence_key,
    'patient',
    timestamptz '2026-07-22 17:20:00+00',
    timestamptz '2026-07-22 17:21:00+00',
    timestamptz '2026-07-22 17:22:00+00'
  );

  ALTER TABLE public.routine_adherence_logs
    ADD CONSTRAINT routine_adherence_logs_missed_source_check
      CHECK (source IS NULL OR status <> 'missed' OR source = 'system') NOT VALID,
    ADD CONSTRAINT routine_adherence_logs_missed_source_new_rows_check
      CHECK (
        status <> 'missed'
        OR source IS NOT DISTINCT FROM 'system'
      ) NOT VALID;

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
      created_at,
      supersedes_log_id
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-non-system-correction',
      v_rule_id,
      v_non_system_occurrence_key,
      'patient',
      timestamptz '2026-07-22 17:20:00+00',
      timestamptz '2026-07-22 17:23:00+00',
      timestamptz '2026-07-22 17:24:00+00',
      v_non_system_missed_log_id
    );
    RAISE EXCEPTION 'correction of a non-system missed action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  ALTER TABLE public.routine_adherence_logs
    DISABLE TRIGGER routine_adherence_logs_immutable;

  DELETE FROM public.routine_adherence_logs
  WHERE id = v_non_system_missed_log_id;

  ALTER TABLE public.routine_adherence_logs
    ENABLE TRIGGER routine_adherence_logs_immutable;

  ALTER TABLE public.routine_adherence_logs
    DROP CONSTRAINT routine_adherence_logs_missed_source_check,
    DROP CONSTRAINT routine_adherence_logs_missed_source_new_rows_check,
    ADD CONSTRAINT routine_adherence_logs_missed_source_check
      CHECK (source IS NULL OR status <> 'missed' OR source = 'system'),
    ADD CONSTRAINT routine_adherence_logs_missed_source_new_rows_check
      CHECK (
        status <> 'missed'
        OR source IS NOT DISTINCT FROM 'system'
      ) NOT VALID;

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
    created_at
  ) VALUES (
    v_not_prior_missed_log_id,
    v_user_id,
    v_item_id,
    'medication',
    'missed',
    'routine-not-prior-missed',
    v_rule_id,
    v_not_prior_occurrence_key,
    'system',
    timestamptz '2026-07-22 17:30:00+00',
    timestamptz '2026-07-22 17:31:00+00',
    timestamptz '2026-07-22 17:35:00+00'
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
      created_at,
      supersedes_log_id
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      'taken',
      'routine-not-prior-correction',
      v_rule_id,
      v_not_prior_occurrence_key,
      'offline_sync',
      timestamptz '2026-07-22 17:30:00+00',
      timestamptz '2026-07-22 17:33:00+00',
      timestamptz '2026-07-22 17:34:00+00',
      v_not_prior_missed_log_id
    );
    RAISE EXCEPTION 'correction older than its missed action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
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
      created_at,
      supersedes_log_id
    ) VALUES
      (
        v_same_statement_correction_log_id,
        v_user_id,
        v_item_id,
        'medication',
        'taken',
        'routine-same-statement-correction',
        v_rule_id,
        repeat('6', 64),
        'patient',
        timestamptz '2026-07-22 17:36:00+00',
        timestamptz '2026-07-22 17:39:00+00',
        timestamptz '2026-07-22 17:39:00+00',
        v_same_statement_missed_log_id
      ),
      (
        v_same_statement_missed_log_id,
        v_user_id,
        v_item_id,
        'medication',
        'missed',
        'routine-same-statement-missed',
        v_rule_id,
        repeat('6', 64),
        'system',
        timestamptz '2026-07-22 17:36:00+00',
        timestamptz '2026-07-22 17:37:00+00',
        timestamptz '2026-07-22 17:38:00+00',
        NULL
      );
    RAISE EXCEPTION 'same-statement correction target was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
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
    created_at
  ) VALUES (
    v_correctable_missed_log_id,
    v_user_id,
    v_item_id,
    'medication',
    'missed',
    'routine-correctable-missed',
    v_rule_id,
    v_correction_occurrence_key,
    'system',
    timestamptz '2026-07-22 17:40:00+00',
    timestamptz '2026-07-22 17:41:00+00',
    timestamptz '2026-07-22 17:42:00+00'
  );

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
    created_at,
    supersedes_log_id
  ) VALUES (
    v_corrected_log_id,
    v_user_id,
    v_item_id,
    'medication',
    'taken',
    'routine-valid-correction',
    v_rule_id,
    v_correction_occurrence_key,
    'patient',
    timestamptz '2026-07-22 17:40:00+00',
    timestamptz '2026-07-22 17:43:00+00',
    timestamptz '2026-07-22 17:44:00+00',
    v_correctable_missed_log_id
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.routine_adherence_logs correction
    JOIN public.routine_adherence_logs missed
      ON missed.id = correction.supersedes_log_id
    WHERE correction.id = v_corrected_log_id
      AND missed.id = v_correctable_missed_log_id
      AND missed.status = 'missed'
      AND missed.source = 'system'
      AND missed.created_at < correction.created_at
  ) THEN
    RAISE EXCEPTION 'valid two-row correction was not persisted';
  END IF;

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

  BEGIN
    WITH same_statement_action AS (
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
        snoozed_until,
        created_at
      ) VALUES (
        v_same_statement_snooze_log_id,
        v_user_id,
        v_item_id,
        'medication',
        'snoozed',
        'routine-same-statement-snooze',
        v_rule_id,
        repeat('7', 64),
        'patient',
        timestamptz '2026-07-22 18:25:00+00',
        timestamptz '2026-07-22 18:26:00+00',
        timestamptz '2026-07-22 18:27:00+00',
        timestamptz '2026-07-22 18:26:30+00'
      )
      RETURNING id
    )
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      routine_occurrence_key,
      routine_action_log_id
    )
    SELECT
      v_user_id,
      v_rule_id,
      timestamptz '2026-07-22 18:28:00+00',
      'queued',
      repeat('7', 64),
      same_statement_action.id
    FROM same_statement_action;
    RAISE EXCEPTION 'same-statement follow-up action was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
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
      timestamptz '2026-07-22 18:29:00+00',
      'queued',
      v_occurrence_key,
      v_log_id
    );
    RAISE EXCEPTION 'follow-up event for a non-snoozed action was accepted';
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
    v_alternate_routine_event_id,
    v_user_id,
    v_supplement_rule_id,
    timestamptz '2026-07-22 19:15:00+00',
    'queued'
  );

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

  IF NOT EXISTS (
    SELECT 1
    FROM public.reminder_events event
    JOIN public.routine_adherence_logs action
      ON action.id = event.routine_action_log_id
    WHERE event.id = '00000000-0000-0000-0000-000000000871'
      AND action.id = v_snooze_log_id
      AND action.status = 'snoozed'
  ) THEN
    RAISE EXCEPTION 'valid snoozed follow-up event was not persisted';
  END IF;

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

  ALTER TABLE public.notification_deliveries
    DISABLE TRIGGER notification_deliveries_routine_preview;

  INSERT INTO public.notification_deliveries (
    id,
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
    v_legacy_delivery_id,
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

  ALTER TABLE public.notification_deliveries
    ENABLE TRIGGER notification_deliveries_routine_preview;

  UPDATE public.notification_deliveries
  SET status = 'sent',
      provider_message_id = 'synthetic-provider-id',
      updated_at = timestamptz '2026-07-22 18:31:00+00'
  WHERE id = v_legacy_delivery_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.notification_deliveries
    WHERE id = v_legacy_delivery_id
      AND status = 'sent'
      AND provider_message_id = 'synthetic-provider-id'
      AND routine_preview_mode IS NULL
  ) THEN
    RAISE EXCEPTION 'legacy routine delivery metadata update failed';
  END IF;

  BEGIN
    UPDATE public.notification_deliveries
    SET reminder_event_id = v_alternate_routine_event_id,
        updated_at = timestamptz '2026-07-22 18:32:00+00'
    WHERE id = v_legacy_delivery_id;
    RAISE EXCEPTION 'legacy null-preview association change was accepted';
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

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-0000-0000-000000000901';
  v_other_user_id constant uuid := '00000000-0000-0000-0000-000000000902';
  v_auth_user_id constant uuid := '00000000-0000-0000-0000-000000000911';
  v_other_auth_user_id constant uuid := '00000000-0000-0000-0000-000000000912';
  v_missing_item_id constant uuid := '00000000-0000-0000-0000-000000000999';
  v_result jsonb;
  v_replay jsonb;
  v_list jsonb;
  v_history jsonb;
  v_next_history jsonb;
  v_legal jsonb;
  v_receipt_result jsonb;
  v_crud_item_id uuid;
  v_medication_item_id uuid;
  v_occurrence_item_id uuid;
  v_other_item_id uuid;
  v_rule_0800 uuid;
  v_rule_2000 uuid;
  v_rule_0130 uuid;
  v_rule_0230 uuid;
  v_original_rule_ids uuid[];
  v_retained_rule_id uuid;
  v_replaced_rule_id uuid;
  v_occurrence_key text;
  v_snooze_occurrence_key text;
  v_missed_occurrence_key text;
  v_old_missed_occurrence_key text;
  v_missed_scheduled_for timestamptz;
  v_old_missed_scheduled_for timestamptz;
  v_missed_log_id uuid := '00000000-0000-0000-0000-000000000941';
  v_old_missed_log_id uuid := '00000000-0000-0000-0000-000000000942';
  v_cursor_occurred_at timestamptz;
  v_cursor_log_id uuid;
  v_expected_ids jsonb;
  v_returned_ids jsonb;
  v_count_before bigint;
  v_count_after bigint;
  v_error_other text;
  v_error_missing text;
  v_error_wrong_type text;
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
      'bodyflow-routine-api-a@example.invalid',
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
      'bodyflow-routine-api-b@example.invalid',
      '',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    );

  INSERT INTO public.users (
    id,
    auth_user_id,
    email,
    locale,
    timezone,
    status
  ) VALUES
    (
      v_user_id,
      v_auth_user_id,
      'bodyflow-routine-api-domain-a@example.invalid',
      'en-US',
      'America/New_York',
      'active'
    ),
    (
      v_other_user_id,
      v_other_auth_user_id,
      'bodyflow-routine-api-domain-b@example.invalid',
      'pt-BR',
      'America/Sao_Paulo',
      'active'
    );

  v_legal := public.get_mobile_legal_document(
    v_user_id,
    'medication_reminder_disclaimer'
  );

  IF v_legal ->> 'locale' <> 'en-US'
    OR v_legal ->> 'document_key' <> 'medication_reminder_disclaimer'
    OR v_legal ->> 'version' <> '2026-07-22.1'
    OR v_legal ->> 'body_hash' IS NULL
    OR v_legal ? 'legal_document_id'
    OR v_legal ? 'user_id'
    OR v_legal ? 'email' THEN
    RAISE EXCEPTION 'mobile legal document did not select the stored patient locale or leaked audit fields';
  END IF;

  SELECT count(*)
  INTO v_count_before
  FROM public.routine_items
  WHERE user_id = v_user_id;

  BEGIN
    PERFORM public.create_mobile_routine_item(
      v_user_id,
      'medication',
      jsonb_build_object(
        'name', 'Synthetic medication before acceptance',
        'dose_text', 'Synthetic dose',
        'origin', 'professional',
        'reminders_enabled', true,
        'schedules', jsonb_build_array(
          jsonb_build_object('local_time', '09:00', 'weekdays', jsonb_build_array(1, 2, 3))
        )
      ),
      'medication-before-acceptance',
      repeat('1', 64)
    );
    RAISE EXCEPTION 'medication was created before current localized legal acceptance';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  SELECT count(*)
  INTO v_count_after
  FROM public.routine_items
  WHERE user_id = v_user_id;

  IF v_count_after <> v_count_before
    OR EXISTS (
      SELECT 1
      FROM private.routine_mutation_receipts
      WHERE user_id = v_user_id
        AND idempotency_key = 'medication-before-acceptance'
    ) THEN
    RAISE EXCEPTION 'failed medication create left partial item or receipt state';
  END IF;

  BEGIN
    PERFORM public.accept_mobile_legal_document(
      v_user_id,
      'medication_reminder_disclaimer',
      v_legal ->> 'version',
      repeat('0', 64),
      'legal-acceptance-wrong-hash'
    );
    RAISE EXCEPTION 'legal acceptance accepted a body hash that was not shown';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  v_result := public.accept_mobile_legal_document(
    v_user_id,
    'medication_reminder_disclaimer',
    v_legal ->> 'version',
    v_legal ->> 'body_hash',
    'legal-acceptance-current'
  );
  v_replay := public.accept_mobile_legal_document(
    v_user_id,
    'medication_reminder_disclaimer',
    v_legal ->> 'version',
    v_legal ->> 'body_hash',
    'legal-acceptance-current'
  );

  IF v_replay IS DISTINCT FROM v_result
    OR v_result ->> 'document_key' <> 'medication_reminder_disclaimer'
    OR v_result ->> 'accepted_version' <> v_legal ->> 'version'
    OR v_result ? 'body'
    OR v_result ? 'body_hash'
    OR v_result ? 'locale' THEN
    RAISE EXCEPTION 'legal acceptance replay or technical result shape is incorrect';
  END IF;

  BEGIN
    PERFORM public.accept_mobile_legal_document(
      v_user_id,
      'medication_reminder_disclaimer',
      v_legal ->> 'version',
      repeat('f', 64),
      'legal-acceptance-current'
    );
    RAISE EXCEPTION 'legal idempotency key was reused for a different request';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  v_result := public.create_mobile_routine_item(
    v_user_id,
    'medication',
    jsonb_build_object(
      'name', 'Synthetic accepted medication',
      'dose_text', 'Synthetic dose',
      'origin', 'professional',
      'reminders_enabled', true,
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '09:00', 'weekdays', jsonb_build_array(1, 2, 3))
      )
    ),
    'medication-after-acceptance',
    repeat('2', 64)
  );
  v_medication_item_id := (v_result ->> 'routine_item_id')::uuid;

  IF NOT EXISTS (
    SELECT 1
    FROM public.routine_items item
    WHERE item.id = v_medication_item_id
      AND item.user_id = v_user_id
      AND item.item_type = 'medication'
  ) THEN
    RAISE EXCEPTION 'medication was not created after exact current acceptance';
  END IF;

  v_result := public.create_mobile_routine_item(
    v_user_id,
    'supplement',
    jsonb_build_object(
      'name', 'Synthetic CRUD item',
      'dose_text', 'Synthetic CRUD dose',
      'origin', 'user',
      'reminders_enabled', true,
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '20:00', 'weekdays', jsonb_build_array(5, 3, 1)),
        jsonb_build_object('local_time', '08:00', 'weekdays', jsonb_build_array(3, 1, 5))
      )
    ),
    'routine-create-crud-001',
    repeat('3', 64)
  );
  v_crud_item_id := (v_result ->> 'routine_item_id')::uuid;

  SELECT array_agg(rule.id ORDER BY rule.local_time, rule.id)
  INTO v_original_rule_ids
  FROM public.reminder_rules rule
  WHERE rule.user_id = v_user_id
    AND rule.routine_item_id = v_crud_item_id
    AND rule.active;

  SELECT count(*)
  INTO v_count_before
  FROM public.product_events event
  WHERE event.user_id = v_user_id
    AND event.event = 'routine.item.created'
    AND event.properties ->> 'routine_item_id' = v_crud_item_id::text;

  IF v_result <> jsonb_build_object('routine_item_id', v_crud_item_id, 'version', 1)
    OR cardinality(v_original_rule_ids) <> 2
    OR v_count_before <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM private.routine_mutation_receipts receipt
      WHERE receipt.user_id = v_user_id
        AND receipt.idempotency_key = 'routine-create-crud-001'
        AND receipt.operation = 'routine_item_create'
        AND receipt.request_hash = repeat('3', 64)
        AND receipt.result_payload = v_result
    ) THEN
    RAISE EXCEPTION 'routine create did not atomically persist item, schedules, event and receipt';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_events event
    CROSS JOIN LATERAL jsonb_object_keys(event.properties) property_key(key)
    WHERE event.user_id = v_user_id
      AND event.event LIKE 'routine.item.%'
      AND property_key.key NOT IN ('routine_item_id', 'item_type', 'version', 'status')
  ) OR EXISTS (
    SELECT 1
    FROM private.routine_mutation_receipts receipt
    WHERE receipt.user_id = v_user_id
      AND (
        receipt.result_payload ?| ARRAY['name', 'dose', 'dose_text', 'body', 'email', 'timezone']
        OR receipt.result_payload::text LIKE '%Synthetic%'
      )
  ) THEN
    RAISE EXCEPTION 'routine technical events or receipts retained identifying content';
  END IF;

  v_replay := public.create_mobile_routine_item(
    v_user_id,
    'supplement',
    jsonb_build_object(
      'name', 'Synthetic CRUD item',
      'dose_text', 'Synthetic CRUD dose',
      'origin', 'user',
      'reminders_enabled', true,
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '20:00', 'weekdays', jsonb_build_array(5, 3, 1)),
        jsonb_build_object('local_time', '08:00', 'weekdays', jsonb_build_array(3, 1, 5))
      )
    ),
    'routine-create-crud-001',
    repeat('3', 64)
  );

  IF v_replay IS DISTINCT FROM v_result
    OR (
      SELECT count(*)
      FROM public.reminder_rules
      WHERE routine_item_id = v_crud_item_id
    ) <> 2
    OR (
      SELECT count(*)
      FROM public.product_events
      WHERE user_id = v_user_id
        AND event = 'routine.item.created'
        AND properties ->> 'routine_item_id' = v_crud_item_id::text
    ) <> 1 THEN
    RAISE EXCEPTION 'routine create replay duplicated state or changed its result';
  END IF;

  BEGIN
    PERFORM public.create_mobile_routine_item(
      v_user_id,
      'supplement',
      jsonb_build_object(
        'name', 'Different request',
        'dose_text', 'Different request dose',
        'origin', 'other',
        'reminders_enabled', true,
        'schedules', jsonb_build_array(
          jsonb_build_object('local_time', '12:00', 'weekdays', jsonb_build_array(1))
        )
      ),
      'routine-create-crud-001',
      repeat('4', 64)
    );
    RAISE EXCEPTION 'create idempotency key accepted a different request hash';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  v_result := public.update_mobile_routine_item(
    v_user_id,
    v_crud_item_id,
    1,
    jsonb_build_object(
      'name', 'Synthetic CRUD item updated',
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '08:00', 'weekdays', jsonb_build_array(5, 1, 3)),
        jsonb_build_object('local_time', '20:00', 'weekdays', jsonb_build_array(1, 3, 5))
      )
    ),
    'routine-update-crud-001',
    repeat('5', 64)
  );

  IF v_result <> jsonb_build_object('routine_item_id', v_crud_item_id, 'version', 2)
    OR (
      SELECT array_agg(rule.id ORDER BY rule.local_time, rule.id)
      FROM public.reminder_rules rule
      WHERE rule.user_id = v_user_id
        AND rule.routine_item_id = v_crud_item_id
        AND rule.active
    ) IS DISTINCT FROM v_original_rule_ids THEN
    RAISE EXCEPTION 'unchanged canonical schedules did not retain their reminder rule IDs';
  END IF;

  v_replay := public.update_mobile_routine_item(
    v_user_id,
    v_crud_item_id,
    1,
    jsonb_build_object(
      'name', 'Synthetic CRUD item updated',
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '08:00', 'weekdays', jsonb_build_array(5, 1, 3)),
        jsonb_build_object('local_time', '20:00', 'weekdays', jsonb_build_array(1, 3, 5))
      )
    ),
    'routine-update-crud-001',
    repeat('5', 64)
  );

  IF v_replay IS DISTINCT FROM v_result THEN
    RAISE EXCEPTION 'routine update did not replay its technical result';
  END IF;

  BEGIN
    PERFORM public.update_mobile_routine_item(
      v_user_id,
      v_crud_item_id,
      1,
      jsonb_build_object('name', 'Different update request'),
      'routine-update-crud-001',
      repeat('a', 64)
    );
    RAISE EXCEPTION 'update idempotency key accepted a different request hash';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  SELECT rule.id
  INTO v_retained_rule_id
  FROM public.reminder_rules rule
  WHERE rule.routine_item_id = v_crud_item_id
    AND rule.active
    AND rule.local_time = time '08:00';

  SELECT rule.id
  INTO v_replaced_rule_id
  FROM public.reminder_rules rule
  WHERE rule.routine_item_id = v_crud_item_id
    AND rule.active
    AND rule.local_time = time '20:00';

  v_result := public.update_mobile_routine_item(
    v_user_id,
    v_crud_item_id,
    2,
    jsonb_build_object(
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '08:00', 'weekdays', jsonb_build_array(1, 3, 5)),
        jsonb_build_object('local_time', '21:00', 'weekdays', jsonb_build_array(1, 3, 5))
      )
    ),
    'routine-update-crud-002',
    repeat('6', 64)
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.reminder_rules
    WHERE id = v_retained_rule_id
      AND active
      AND deactivated_at IS NULL
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.reminder_rules
    WHERE id = v_replaced_rule_id
      AND NOT active
      AND deactivated_at IS NOT NULL
      AND local_time = time '20:00'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.reminder_rules
    WHERE routine_item_id = v_crud_item_id
      AND active
      AND local_time = time '21:00'
  ) THEN
    RAISE EXCEPTION 'changed schedules were not deactivated and replaced while retaining matches';
  END IF;

  BEGIN
    PERFORM public.update_mobile_routine_item(
      v_user_id,
      v_crud_item_id,
      2,
      jsonb_build_object(
        'name', 'Stale update must not persist',
        'schedules', jsonb_build_array(
          jsonb_build_object('local_time', '22:00', 'weekdays', jsonb_build_array(1, 3, 5))
        )
      ),
      'routine-update-crud-stale',
      repeat('7', 64)
    );
    RAISE EXCEPTION 'stale expected version changed a routine item';
  EXCEPTION
    WHEN serialization_failure THEN NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.routine_items
    WHERE id = v_crud_item_id
      AND (version <> 3 OR name = 'Stale update must not persist')
  ) OR EXISTS (
    SELECT 1
    FROM public.reminder_rules
    WHERE routine_item_id = v_crud_item_id
      AND active
      AND local_time = time '22:00'
  ) OR EXISTS (
    SELECT 1
    FROM private.routine_mutation_receipts
    WHERE user_id = v_user_id
      AND idempotency_key = 'routine-update-crud-stale'
  ) THEN
    RAISE EXCEPTION 'stale update left partial item or receipt state';
  END IF;

  v_result := public.archive_mobile_routine_item(
    v_user_id,
    v_crud_item_id,
    'routine-archive-crud-001',
    repeat('b', 64)
  );
  v_replay := public.archive_mobile_routine_item(
    v_user_id,
    v_crud_item_id,
    'routine-archive-crud-001',
    repeat('b', 64)
  );

  IF v_replay IS DISTINCT FROM v_result
    OR (v_result ->> 'version')::integer <> 4
    OR v_result ->> 'archived_at' IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.reminder_rules
      WHERE routine_item_id = v_crud_item_id
        AND active
    )
    OR NOT EXISTS (
      SELECT 1
      FROM public.routine_items
      WHERE id = v_crud_item_id
        AND NOT active
        AND NOT reminders_enabled
        AND archived_at IS NOT NULL
        AND version = 4
    ) THEN
    RAISE EXCEPTION 'archive did not deactivate the item and every active rule or replay exactly';
  END IF;

  BEGIN
    PERFORM public.archive_mobile_routine_item(
      v_user_id,
      v_medication_item_id,
      'routine-archive-crud-001',
      repeat('c', 64)
    );
    RAISE EXCEPTION 'archive idempotency key was reused for a different item';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  v_list := public.list_mobile_routine_items(
    v_user_id,
    'supplement',
    false,
    timestamptz '2026-07-22 17:00:00+00'
  );
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_list -> 'items') item
    WHERE item ->> 'id' = v_crud_item_id::text
  ) THEN
    RAISE EXCEPTION 'routine list included archived items by default';
  END IF;

  v_list := public.list_mobile_routine_items(
    v_user_id,
    'supplement',
    true,
    timestamptz '2026-07-22 17:00:00+00'
  );
  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_list -> 'items') item
    WHERE item ->> 'id' = v_crud_item_id::text
      AND item ->> 'archived_at' IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'routine list omitted archived items when requested';
  END IF;

  v_result := public.create_mobile_routine_item(
    v_user_id,
    'supplement',
    jsonb_build_object(
      'name', 'Synthetic occurrence item',
      'dose_text', 'Synthetic occurrence dose',
      'origin', 'protocol',
      'reminders_enabled', true,
      'schedules', jsonb_build_array(
        jsonb_build_object(
          'local_time', '20:00',
          'weekdays', jsonb_build_array(0, 1, 2, 3, 4, 5, 6)
        ),
        jsonb_build_object(
          'local_time', '08:00',
          'weekdays', jsonb_build_array(0, 1, 2, 3, 4, 5, 6)
        )
      )
    ),
    'routine-create-occurrence',
    repeat('8', 64)
  );
  v_occurrence_item_id := (v_result ->> 'routine_item_id')::uuid;

  SELECT rule.id
  INTO v_rule_0800
  FROM public.reminder_rules rule
  WHERE rule.routine_item_id = v_occurrence_item_id
    AND rule.local_time = time '08:00'
    AND rule.active;

  SELECT rule.id
  INTO v_rule_2000
  FROM public.reminder_rules rule
  WHERE rule.routine_item_id = v_occurrence_item_id
    AND rule.local_time = time '20:00'
    AND rule.active;

  v_result := public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    v_rule_0800,
    timestamptz '2026-07-22 12:00:00+00',
    'taken',
    timestamptz '2026-07-22 12:01:00+00',
    NULL,
    'routine-occurrence-0800-taken'
  );
  v_occurrence_key := v_result ->> 'occurrence_key';
  v_replay := public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    v_rule_0800,
    timestamptz '2026-07-22 12:00:00+00',
    'taken',
    timestamptz '2026-07-22 12:01:00+00',
    NULL,
    'routine-occurrence-0800-taken'
  );

  IF v_replay IS DISTINCT FROM v_result
    OR v_occurrence_key <> private.derive_routine_occurrence_key(
      v_rule_0800,
      timestamptz '2026-07-22 12:00:00+00'
    )
    OR char_length(v_occurrence_key) <> 64 THEN
    RAISE EXCEPTION 'exact occurrence action did not derive or replay its database identity';
  END IF;

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0800,
      timestamptz '2026-07-22 12:00:00+00',
      'skipped',
      timestamptz '2026-07-22 12:02:00+00',
      NULL,
      'routine-occurrence-0800-taken'
    );
    RAISE EXCEPTION 'adherence idempotency key accepted a different action';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  v_list := public.list_mobile_routine_items(
    v_user_id,
    'supplement',
    false,
    timestamptz '2026-07-22 17:00:00+00'
  );

  IF v_list ->> 'local_date' <> '2026-07-22'
    OR (
      SELECT schedule #>> '{occurrence,status}'
      FROM jsonb_array_elements(v_list -> 'items') item
      CROSS JOIN LATERAL jsonb_array_elements(item -> 'schedules') schedule
      WHERE item ->> 'id' = v_occurrence_item_id::text
        AND schedule ->> 'local_time' = '08:00'
    ) <> 'taken'
    OR (
      SELECT schedule #>> '{occurrence,status}'
      FROM jsonb_array_elements(v_list -> 'items') item
      CROSS JOIN LATERAL jsonb_array_elements(item -> 'schedules') schedule
      WHERE item ->> 'id' = v_occurrence_item_id::text
        AND schedule ->> 'local_time' = '20:00'
    ) <> 'pending'
    OR (
      SELECT jsonb_agg(schedule ->> 'local_time' ORDER BY schedule_ordinality)
      FROM jsonb_array_elements(v_list -> 'items') item
      CROSS JOIN LATERAL jsonb_array_elements(item -> 'schedules')
        WITH ORDINALITY AS schedules(schedule, schedule_ordinality)
      WHERE item ->> 'id' = v_occurrence_item_id::text
    ) <> '["08:00", "20:00"]'::jsonb THEN
    RAISE EXCEPTION 'routine list did not derive local date, exact statuses, or stable schedule order';
  END IF;

  v_result := public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    v_rule_2000,
    timestamptz '2026-07-23 00:00:00+00',
    'snoozed',
    timestamptz '2026-07-23 00:01:00+00',
    timestamptz '2026-07-23 00:30:00+00',
    'routine-occurrence-2000-snooze'
  );
  v_snooze_occurrence_key := v_result ->> 'occurrence_key';

  IF v_snooze_occurrence_key <> private.derive_routine_occurrence_key(
    v_rule_2000,
    timestamptz '2026-07-23 00:00:00+00'
  ) THEN
    RAISE EXCEPTION 'snooze changed the original occurrence identity';
  END IF;

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_2000,
      timestamptz '2026-07-23 00:00:00+00',
      'snoozed',
      timestamptz '2026-07-23 00:02:00+00',
      timestamptz '2026-07-23 04:00:00+00',
      'routine-occurrence-cross-day-snooze'
    );
    RAISE EXCEPTION 'snooze crossed the stored-timezone local day';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0800,
      timestamptz '2026-07-23 12:00:00+00',
      'missed',
      timestamptz '2026-07-23 12:01:00+00',
      NULL,
      'routine-occurrence-client-missed'
    );
    RAISE EXCEPTION 'client-authored missed action was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0800,
      timestamptz '2026-07-22 12:00:00+00',
      'skipped',
      timestamptz '2026-07-22 12:02:00+00',
      NULL,
      'routine-occurrence-terminal-rewrite'
    );
    RAISE EXCEPTION 'terminal exact occurrence accepted an ordinary rewrite';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_missed_scheduled_for := (
    (
      (timezone('America/New_York', clock_timestamp())::date - 6)
      + time '08:00'
    ) AT TIME ZONE 'America/New_York'
  );
  v_missed_occurrence_key := private.derive_routine_occurrence_key(
    v_rule_0800,
    v_missed_scheduled_for
  );

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
    created_at
  ) VALUES (
    v_missed_log_id,
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    'missed',
    'routine-system-missed-correctable',
    v_rule_0800,
    v_missed_occurrence_key,
    'system',
    v_missed_scheduled_for,
    clock_timestamp() - interval '6 days',
    clock_timestamp() - interval '6 days'
  );

  PERFORM public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    v_rule_0800,
    v_missed_scheduled_for,
    'taken',
    clock_timestamp(),
    NULL,
    'routine-missed-correction-once'
  );

  IF (
    SELECT count(*)
    FROM public.routine_adherence_logs
    WHERE user_id = v_user_id
      AND occurrence_key = v_missed_occurrence_key
  ) <> 2 OR NOT EXISTS (
    SELECT 1
    FROM public.routine_adherence_logs correction
    WHERE correction.user_id = v_user_id
      AND correction.occurrence_key = v_missed_occurrence_key
      AND correction.status = 'taken'
      AND correction.source = 'patient'
      AND correction.supersedes_log_id = v_missed_log_id
  ) THEN
    RAISE EXCEPTION 'seven-day missed correction did not preserve the two-row audit history';
  END IF;

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0800,
      v_missed_scheduled_for,
      'taken',
      clock_timestamp(),
      NULL,
      'routine-missed-correction-twice'
    );
    RAISE EXCEPTION 'missed occurrence was corrected more than once';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_old_missed_scheduled_for := (
    (
      (timezone('America/New_York', clock_timestamp())::date - 8)
      + time '08:00'
    ) AT TIME ZONE 'America/New_York'
  );
  v_old_missed_occurrence_key := private.derive_routine_occurrence_key(
    v_rule_0800,
    v_old_missed_scheduled_for
  );

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
    created_at
  ) VALUES (
    v_old_missed_log_id,
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    'missed',
    'routine-system-missed-expired',
    v_rule_0800,
    v_old_missed_occurrence_key,
    'system',
    v_old_missed_scheduled_for,
    clock_timestamp() - interval '8 days',
    clock_timestamp() - interval '8 days'
  );

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0800,
      v_old_missed_scheduled_for,
      'taken',
      clock_timestamp(),
      NULL,
      'routine-missed-correction-expired'
    );
    RAISE EXCEPTION 'expired missed occurrence correction was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays
  ) VALUES
    (
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      time '01:30',
      ARRAY[0, 1, 2, 3, 4, 5, 6]::smallint[]
    ),
    (
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      time '02:30',
      ARRAY[0, 1, 2, 3, 4, 5, 6]::smallint[]
    );

  SELECT id
  INTO v_rule_0130
  FROM public.reminder_rules
  WHERE routine_item_id = v_occurrence_item_id
    AND local_time = time '01:30'
  ORDER BY created_at DESC, id DESC
  LIMIT 1;

  SELECT id
  INTO v_rule_0230
  FROM public.reminder_rules
  WHERE routine_item_id = v_occurrence_item_id
    AND local_time = time '02:30'
  ORDER BY created_at DESC, id DESC
  LIMIT 1;

  PERFORM public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    v_rule_0130,
    timestamptz '2026-11-01 06:30:00+00',
    'taken',
    timestamptz '2026-11-01 06:31:00+00',
    NULL,
    'routine-dst-fall-canonical'
  );

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0130,
      timestamptz '2026-11-01 05:30:00+00',
      'taken',
      timestamptz '2026-11-01 05:31:00+00',
      NULL,
      'routine-dst-fall-noncanonical'
    );
    RAISE EXCEPTION 'noncanonical ambiguous DST instant was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.record_routine_occurrence_action_atomic(
      v_user_id,
      v_occurrence_item_id,
      'supplement',
      v_rule_0230,
      timestamptz '2026-03-08 07:30:00+00',
      'taken',
      timestamptz '2026-03-08 07:31:00+00',
      NULL,
      'routine-dst-spring-nonexistent'
    );
    RAISE EXCEPTION 'nonexistent DST local schedule instant was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  v_result := public.create_mobile_routine_item(
    v_other_user_id,
    'supplement',
    jsonb_build_object(
      'name', 'Synthetic other-owner item',
      'dose_text', 'Synthetic other-owner dose',
      'origin', 'other',
      'reminders_enabled', true,
      'schedules', jsonb_build_array(
        jsonb_build_object('local_time', '10:00', 'weekdays', jsonb_build_array(1, 2, 3))
      )
    ),
    'routine-create-other-owner',
    repeat('9', 64)
  );
  v_other_item_id := (v_result ->> 'routine_item_id')::uuid;

  BEGIN
    PERFORM public.list_mobile_routine_history(
      v_user_id,
      v_other_item_id,
      'supplement',
      20,
      NULL,
      NULL
    );
    RAISE EXCEPTION 'cross-user history disclosed item existence';
  EXCEPTION
    WHEN no_data_found THEN
      GET STACKED DIAGNOSTICS v_error_other = MESSAGE_TEXT;
  END;

  BEGIN
    PERFORM public.list_mobile_routine_history(
      v_user_id,
      v_missing_item_id,
      'supplement',
      20,
      NULL,
      NULL
    );
    RAISE EXCEPTION 'missing history item did not use the non-disclosing error';
  EXCEPTION
    WHEN no_data_found THEN
      GET STACKED DIAGNOSTICS v_error_missing = MESSAGE_TEXT;
  END;

  BEGIN
    PERFORM public.list_mobile_routine_history(
      v_user_id,
      v_occurrence_item_id,
      'medication',
      20,
      NULL,
      NULL
    );
    RAISE EXCEPTION 'wrong-type history item did not use the non-disclosing error';
  EXCEPTION
    WHEN no_data_found THEN
      GET STACKED DIAGNOSTICS v_error_wrong_type = MESSAGE_TEXT;
  END;

  IF v_error_other IS DISTINCT FROM v_error_missing
    OR v_error_other IS DISTINCT FROM v_error_wrong_type THEN
    RAISE EXCEPTION 'history errors disclosed ownership, type, or existence';
  END IF;

  v_history := public.list_mobile_routine_history(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    50,
    NULL,
    NULL
  );

  SELECT jsonb_agg(ordered.id ORDER BY ordered.occurred_at DESC, ordered.id DESC)
  INTO v_expected_ids
  FROM (
    SELECT log.id, log.occurred_at
    FROM public.routine_adherence_logs log
    WHERE log.user_id = v_user_id
      AND log.routine_item_id = v_occurrence_item_id
      AND log.item_type = 'supplement'
    ORDER BY log.occurred_at DESC, log.id DESC
    LIMIT 50
  ) ordered;

  SELECT jsonb_agg((entry ->> 'id')::uuid ORDER BY entry_ordinality)
  INTO v_returned_ids
  FROM jsonb_array_elements(v_history -> 'items')
    WITH ORDINALITY AS entries(entry, entry_ordinality);

  IF v_returned_ids IS DISTINCT FROM v_expected_ids THEN
    RAISE EXCEPTION 'routine history is not ordered by the stable occurred-at/id tuple';
  END IF;

  v_history := public.list_mobile_routine_history(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    2,
    NULL,
    NULL
  );
  v_cursor_occurred_at := (v_history #>> '{next_cursor,occurred_at}')::timestamptz;
  v_cursor_log_id := (v_history #>> '{next_cursor,log_id}')::uuid;
  v_next_history := public.list_mobile_routine_history(
    v_user_id,
    v_occurrence_item_id,
    'supplement',
    2,
    v_cursor_occurred_at,
    v_cursor_log_id
  );

  IF v_cursor_occurred_at IS NULL OR v_cursor_log_id IS NULL
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_next_history -> 'items') entry
      JOIN public.routine_adherence_logs log
        ON log.id = (entry ->> 'id')::uuid
      WHERE (log.occurred_at, log.id) >= (v_cursor_occurred_at, v_cursor_log_id)
    ) THEN
    RAISE EXCEPTION 'routine history cursor did not apply the stable tuple boundary';
  END IF;

  SELECT result_payload
  INTO v_receipt_result
  FROM private.routine_mutation_receipts
  WHERE user_id = v_user_id
    AND idempotency_key = 'legal-acceptance-current';

  IF v_receipt_result ?| ARRAY['body', 'body_hash', 'locale', 'user_id', 'email']
    OR EXISTS (
      SELECT 1
      FROM public.product_events event
      WHERE event.user_id = v_user_id
        AND event.event LIKE 'routine.item.%'
        AND event.properties::text LIKE '%Synthetic%'
    ) THEN
    RAISE EXCEPTION 'technical legal or routine records retained identifying content';
  END IF;
END;
$test$;

ROLLBACK;

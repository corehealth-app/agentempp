BEGIN;

DO $test$
DECLARE
  v_role_constraint text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'auth_user_id'
      AND is_nullable = 'YES'
      AND data_type = 'uuid'
  ) THEN
    RAISE EXCEPTION 'users.auth_user_id nullable uuid is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'wpp'
      AND is_nullable = 'NO'
  ) THEN
    RAISE EXCEPTION 'users.wpp must be nullable for app-first accounts';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint constraint_row
    JOIN pg_class source_table ON source_table.oid = constraint_row.conrelid
    JOIN pg_namespace source_schema ON source_schema.oid = source_table.relnamespace
    JOIN pg_class target_table ON target_table.oid = constraint_row.confrelid
    JOIN pg_namespace target_schema ON target_schema.oid = target_table.relnamespace
    WHERE constraint_row.contype = 'f'
      AND source_schema.nspname = 'public'
      AND source_table.relname = 'users'
      AND target_schema.nspname = 'auth'
      AND target_table.relname = 'users'
      AND pg_get_constraintdef(constraint_row.oid) LIKE '%(auth_user_id)%REFERENCES auth.users(id)%'
  ) THEN
    RAISE EXCEPTION 'users.auth_user_id FK to auth.users(id) is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_index index_row
    JOIN pg_class table_row ON table_row.oid = index_row.indrelid
    JOIN pg_namespace schema_row ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname = 'public'
      AND table_row.relname = 'users'
      AND index_row.indisunique
      AND pg_get_indexdef(index_row.indexrelid) LIKE '%(auth_user_id)%'
  ) THEN
    RAISE EXCEPTION 'users.auth_user_id unique index is missing';
  END IF;

  SELECT pg_get_constraintdef(constraint_row.oid)
  INTO v_role_constraint
  FROM pg_constraint constraint_row
  WHERE constraint_row.conrelid = 'public.admin_users'::regclass
    AND constraint_row.contype = 'c'
    AND pg_get_constraintdef(constraint_row.oid) LIKE '%role%';

  IF v_role_constraint IS NULL
    OR v_role_constraint NOT LIKE '%support%'
    OR v_role_constraint NOT LIKE '%content_editor%'
    OR v_role_constraint NOT LIKE '%nutrition_admin%'
    OR v_role_constraint NOT LIKE '%operations_admin%'
    OR v_role_constraint NOT LIKE '%master_admin%' THEN
    RAISE EXCEPTION 'admin_users role constraint does not contain the approved RBAC roles';
  END IF;

  IF to_regprocedure('public.bootstrap_patient_profile()') IS NULL THEN
    RAISE EXCEPTION 'email-first patient bootstrap function is missing';
  END IF;

  IF has_function_privilege('anon', 'public.bootstrap_patient_profile()', 'EXECUTE')
    OR NOT has_function_privilege('authenticated', 'public.bootstrap_patient_profile()', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.bootstrap_patient_profile()', 'EXECUTE') THEN
    RAISE EXCEPTION 'patient bootstrap grants are incorrect';
  END IF;
END;
$test$;

ROLLBACK;

ALTER TABLE public.routine_items
  ADD COLUMN dose_text text,
  ADD COLUMN origin text,
  ADD COLUMN reminders_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN archived_at timestamptz,
  ADD COLUMN version integer NOT NULL DEFAULT 1,
  ADD CONSTRAINT routine_items_origin_check
    CHECK (origin IS NULL OR origin IN ('user', 'professional', 'protocol', 'other')),
  ADD CONSTRAINT routine_items_dose_text_check
    CHECK (dose_text IS NULL OR char_length(btrim(dose_text)) BETWEEN 1 AND 120),
  ADD CONSTRAINT routine_items_version_check
    CHECK (version > 0),
  ADD CONSTRAINT routine_items_archive_state_check
    CHECK (archived_at IS NULL OR (NOT active AND NOT reminders_enabled));

ALTER TABLE public.reminder_rules
  ADD COLUMN deactivated_at timestamptz,
  ADD CONSTRAINT reminder_rules_deactivated_state_check
    CHECK (deactivated_at IS NULL OR NOT active),
  ADD CONSTRAINT reminder_rules_occurrence_identity_unique
    UNIQUE (id, user_id, routine_item_id, category);

ALTER TABLE public.routine_adherence_logs
  ADD COLUMN reminder_rule_id uuid,
  ADD COLUMN occurrence_key text,
  ADD COLUMN source text,
  ADD COLUMN supersedes_log_id uuid;

ALTER TABLE public.routine_adherence_logs
  DROP CONSTRAINT routine_adherence_logs_snooze_check,
  ADD CONSTRAINT routine_adherence_logs_snooze_check CHECK (
    (status = 'snoozed' AND snoozed_until IS NOT NULL)
    OR (status <> 'snoozed' AND snoozed_until IS NULL)
  ),
  ADD CONSTRAINT routine_adherence_logs_supersedes_identity_unique
    UNIQUE (id, user_id, routine_item_id, item_type, occurrence_key),
  ADD CONSTRAINT routine_adherence_logs_event_identity_unique
    UNIQUE (id, user_id, reminder_rule_id, occurrence_key),
  ADD CONSTRAINT routine_adherence_logs_source_check
    CHECK (source IS NULL OR source IN ('patient', 'system', 'offline_sync')),
  ADD CONSTRAINT routine_adherence_logs_occurrence_key_check
    CHECK (occurrence_key IS NULL OR occurrence_key ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT routine_adherence_logs_occurrence_shape_check
    CHECK (
      occurrence_key IS NULL
      OR (
        reminder_rule_id IS NOT NULL
        AND scheduled_for IS NOT NULL
        AND source IS NOT NULL
      )
    ),
  ADD CONSTRAINT routine_adherence_logs_supersedes_shape_check
    CHECK (
      supersedes_log_id IS NULL
      OR (
        occurrence_key IS NOT NULL
        AND status = 'taken'
        AND source IN ('patient', 'offline_sync')
      )
    ),
  ADD CONSTRAINT routine_adherence_logs_missed_source_check
    CHECK (source IS NULL OR status <> 'missed' OR source = 'system'),
  ADD CONSTRAINT routine_adherence_logs_missed_source_new_rows_check
    CHECK (
      status <> 'missed'
      OR source IS NOT DISTINCT FROM 'system'
    ) NOT VALID,
  ADD CONSTRAINT routine_adherence_logs_skipped_source_new_rows_check
    CHECK (
      status <> 'skipped'
      OR (
        source IS NOT NULL
        AND source IN ('patient', 'offline_sync')
      )
    ) NOT VALID,
  ADD CONSTRAINT routine_adherence_logs_rule_owner_type_fkey
    FOREIGN KEY (reminder_rule_id, user_id, routine_item_id, item_type)
    REFERENCES public.reminder_rules(id, user_id, routine_item_id, category)
    ON DELETE RESTRICT,
  ADD CONSTRAINT routine_adherence_logs_supersedes_owner_fkey
    FOREIGN KEY (
      supersedes_log_id,
      user_id,
      routine_item_id,
      item_type,
      occurrence_key
    ) REFERENCES public.routine_adherence_logs(
      id,
      user_id,
      routine_item_id,
      item_type,
      occurrence_key
    )
    ON DELETE RESTRICT;

CREATE INDEX routine_adherence_logs_occurrence_state_idx
  ON public.routine_adherence_logs (
    user_id,
    occurrence_key,
    occurred_at DESC,
    created_at DESC,
    id DESC
  )
  WHERE occurrence_key IS NOT NULL;

CREATE UNIQUE INDEX routine_adherence_logs_system_missed_occurrence_unique
  ON public.routine_adherence_logs (user_id, occurrence_key)
  WHERE occurrence_key IS NOT NULL
    AND status = 'missed'
    AND source = 'system';

ALTER TABLE public.reminder_events
  ADD COLUMN routine_occurrence_key text,
  ADD COLUMN routine_action_log_id uuid,
  ADD CONSTRAINT reminder_events_routine_occurrence_key_check
    CHECK (
      routine_occurrence_key IS NULL
      OR routine_occurrence_key ~ '^[0-9a-f]{64}$'
    ),
  ADD CONSTRAINT reminder_events_routine_action_shape_check
    CHECK (
      routine_action_log_id IS NULL
      OR routine_occurrence_key IS NOT NULL
    ),
  ADD CONSTRAINT reminder_events_routine_action_owner_fkey
    FOREIGN KEY (
      routine_action_log_id,
      user_id,
      reminder_rule_id,
      routine_occurrence_key
    ) REFERENCES public.routine_adherence_logs(
      id,
      user_id,
      reminder_rule_id,
      occurrence_key
    )
    ON DELETE RESTRICT;

CREATE UNIQUE INDEX reminder_events_routine_action_log_unique
  ON public.reminder_events (routine_action_log_id)
  WHERE routine_action_log_id IS NOT NULL;

ALTER TABLE public.notification_deliveries
  ADD COLUMN routine_preview_mode text,
  ADD CONSTRAINT notification_deliveries_routine_preview_mode_check
    CHECK (
      routine_preview_mode IS NULL
      OR routine_preview_mode IN ('private', 'name', 'name_and_dose')
    );

ALTER TABLE public.notification_preferences
  ADD COLUMN routine_preview_mode text NOT NULL DEFAULT 'private',
  ADD CONSTRAINT notification_preferences_routine_preview_mode_check
    CHECK (routine_preview_mode IN ('private', 'name', 'name_and_dose'));

CREATE TABLE public.legal_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_key text NOT NULL,
  version text NOT NULL,
  locale text NOT NULL,
  body text NOT NULL,
  body_hash text GENERATED ALWAYS AS (
    encode(extensions.digest(body, 'sha256'), 'hex')
  ) STORED,
  required_from timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT legal_documents_key_locale_version_unique
    UNIQUE (document_key, locale, version),
  CONSTRAINT legal_documents_key_locale_required_unique
    UNIQUE (document_key, locale, required_from),
  CONSTRAINT legal_documents_exact_identity_unique
    UNIQUE (id, document_key, version, locale, body_hash),
  CONSTRAINT legal_documents_key_check
    CHECK (document_key ~ '^[a-z][a-z0-9_]{0,99}$'),
  CONSTRAINT legal_documents_version_check
    CHECK (version ~ '^[A-Za-z0-9._-]{1,64}$'),
  CONSTRAINT legal_documents_locale_check
    CHECK (locale IN ('pt-BR', 'en-US')),
  CONSTRAINT legal_documents_body_check
    CHECK (char_length(btrim(body)) BETWEEN 1 AND 4000),
  CONSTRAINT legal_documents_body_hash_check
    CHECK (body_hash ~ '^[0-9a-f]{64}$')
);

CREATE INDEX legal_documents_current_idx
  ON public.legal_documents (document_key, locale, required_from DESC);

CREATE TABLE public.user_legal_acceptances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  legal_document_id uuid NOT NULL,
  document_key text NOT NULL,
  version text NOT NULL,
  locale text NOT NULL,
  body_hash text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT user_legal_acceptances_user_key_version_unique
    UNIQUE (user_id, document_key, version),
  CONSTRAINT user_legal_acceptances_document_fkey
    FOREIGN KEY (legal_document_id, document_key, version, locale, body_hash)
    REFERENCES public.legal_documents(id, document_key, version, locale, body_hash)
    ON DELETE RESTRICT,
  CONSTRAINT user_legal_acceptances_key_check
    CHECK (document_key ~ '^[a-z][a-z0-9_]{0,99}$'),
  CONSTRAINT user_legal_acceptances_version_check
    CHECK (version ~ '^[A-Za-z0-9._-]{1,64}$'),
  CONSTRAINT user_legal_acceptances_locale_check
    CHECK (locale IN ('pt-BR', 'en-US')),
  CONSTRAINT user_legal_acceptances_body_hash_check
    CHECK (body_hash ~ '^[0-9a-f]{64}$')
);

CREATE TABLE private.routine_mutation_receipts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  idempotency_key text NOT NULL,
  operation text NOT NULL,
  request_hash text NOT NULL,
  result_payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT routine_mutation_receipts_pkey
    PRIMARY KEY (user_id, idempotency_key),
  CONSTRAINT routine_mutation_receipts_idempotency_key_check CHECK (
    char_length(idempotency_key) BETWEEN 8 AND 128
    AND idempotency_key ~ '^[A-Za-z0-9._:-]+$'
  ),
  CONSTRAINT routine_mutation_receipts_operation_check CHECK (
    operation IN (
      'routine_item_create',
      'routine_item_update',
      'routine_item_archive',
      'legal_acceptance'
    )
  ),
  CONSTRAINT routine_mutation_receipts_request_hash_check
    CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT routine_mutation_receipts_result_payload_check
    CHECK (jsonb_typeof(result_payload) = 'object')
);

CREATE OR REPLACE FUNCTION private.reject_bodyflow_routine_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'BodyFlow routine audit records are immutable'
    USING ERRCODE = '23514';
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_routine_mutation_receipt_result_keys()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF jsonb_typeof(NEW.result_payload) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'routine receipt result must be an object'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_object_keys(NEW.result_payload) AS result_key(key)
    WHERE result_key.key <> ALL (ARRAY[
      'routine_item_id',
      'version',
      'archived_at',
      'document_key',
      'accepted_version',
      'accepted_at'
    ]::text[])
  ) THEN
    RAISE EXCEPTION 'routine receipt result contains an unsupported key'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_notification_delivery_routine_preview()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_category text;
BEGIN
  SELECT rule.category
  INTO v_category
  FROM public.reminder_events event
  JOIN public.reminder_rules rule
    ON rule.id = event.reminder_rule_id
    AND rule.user_id = event.user_id
  WHERE event.id = NEW.reminder_event_id
    AND event.user_id = NEW.user_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_category IN ('supplement', 'medication') THEN
    IF NEW.routine_preview_mode IS NULL
      OR NEW.routine_preview_mode NOT IN ('private', 'name', 'name_and_dose') THEN
      RAISE EXCEPTION 'routine delivery requires a controlled preview mode'
        USING ERRCODE = '23514';
    END IF;
  ELSIF NEW.routine_preview_mode IS NOT NULL THEN
    RAISE EXCEPTION 'non-routine delivery cannot store a routine preview mode'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER legal_documents_immutable
  BEFORE UPDATE OR DELETE ON public.legal_documents
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_bodyflow_routine_immutable_mutation();

CREATE TRIGGER user_legal_acceptances_immutable
  BEFORE UPDATE OR DELETE ON public.user_legal_acceptances
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_bodyflow_routine_immutable_mutation();

CREATE TRIGGER routine_adherence_logs_immutable
  BEFORE UPDATE OR DELETE ON public.routine_adherence_logs
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_bodyflow_routine_immutable_mutation();

CREATE TRIGGER routine_mutation_receipts_result_keys
  BEFORE INSERT OR UPDATE OF result_payload
  ON private.routine_mutation_receipts
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_routine_mutation_receipt_result_keys();

CREATE TRIGGER notification_deliveries_routine_preview
  BEFORE INSERT OR UPDATE ON public.notification_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_notification_delivery_routine_preview();

ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.routine_mutation_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_legal_acceptances_patient_own_read
  ON public.user_legal_acceptances
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.users domain_user
      WHERE domain_user.id = user_legal_acceptances.user_id
        AND domain_user.auth_user_id = (SELECT auth.uid())
    )
  );

INSERT INTO public.legal_documents (
  document_key,
  version,
  locale,
  body,
  required_from
) VALUES
  (
    'medication_reminder_disclaimer',
    '2026-07-22.1',
    'pt-BR',
    'O BodyFlow apenas organiza lembretes e registros. Ele não prescreve, recomenda nem altera medicamentos ou doses. Siga a orientação do profissional de saúde responsável.',
    timestamptz '2026-07-22 00:00:00+00'
  ),
  (
    'medication_reminder_disclaimer',
    '2026-07-22.1',
    'en-US',
    'BodyFlow only organizes reminders and records. It does not prescribe, recommend or change medications or doses. Follow the guidance of the responsible healthcare professional.',
    timestamptz '2026-07-22 00:00:00+00'
  );

COMMENT ON TABLE public.legal_documents IS
  'Immutable versioned legal copy served through the trusted BodyFlow BFF.';
COMMENT ON TABLE public.user_legal_acceptances IS
  'Immutable patient acceptance of the exact version and hash that was shown.';
COMMENT ON TABLE private.routine_mutation_receipts IS
  'Private technical replay receipts with allowlisted result keys and no raw request payload.';

-- BodyFlow Prompt 07: deterministic coach copy, editorial packs, patient tone
-- preference, selection telemetry and the non-visual mascot state machine.

CREATE TABLE public.coach_personalities (
  code text PRIMARY KEY,
  name_pt_br text NOT NULL,
  description_pt_br text NOT NULL,
  name_en_us text NOT NULL,
  description_en_us text NOT NULL,
  selectable boolean NOT NULL DEFAULT true,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT coach_personalities_code_check CHECK (
    code IN ('balanced', 'focus', 'impulse', 'zen')
  ),
  CONSTRAINT coach_personalities_name_check CHECK (
    char_length(btrim(name_pt_br)) BETWEEN 1 AND 80
    AND char_length(btrim(name_en_us)) BETWEEN 1 AND 80
  ),
  CONSTRAINT coach_personalities_description_check CHECK (
    char_length(btrim(description_pt_br)) BETWEEN 1 AND 240
    AND char_length(btrim(description_en_us)) BETWEEN 1 AND 240
  ),
  CONSTRAINT coach_personalities_balanced_internal_check CHECK (
    code <> 'balanced' OR NOT selectable
  )
);

CREATE TABLE public.user_coach_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  personality_code text NOT NULL REFERENCES public.coach_personalities(code),
  selected_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT user_coach_preferences_public_choice_check CHECK (
    personality_code IN ('focus', 'impulse', 'zen')
  )
);

CREATE TABLE public.coach_message_context_policies (
  context text NOT NULL,
  channel text NOT NULL,
  cooldown_seconds integer NOT NULL DEFAULT 0,
  max_per_local_day smallint,
  delivery_enabled boolean NOT NULL DEFAULT true,
  refresh_cadence text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (context, channel),
  CONSTRAINT coach_context_policies_context_check CHECK (
    context IN (
      'onboarding',
      'meal_pending',
      'registration_confirmed',
      'error_corrected',
      'hydration',
      'supplement',
      'medication',
      'workout',
      'progress',
      'day_incomplete',
      'reevaluation',
      'reengagement',
      'trial',
      'paywall',
      'return_after_abandonment'
    )
  ),
  CONSTRAINT coach_context_policies_channel_check CHECK (
    channel IN ('in_app', 'push', 'email')
  ),
  CONSTRAINT coach_context_policies_cooldown_check CHECK (
    cooldown_seconds BETWEEN 0 AND 2592000
  ),
  CONSTRAINT coach_context_policies_daily_limit_check CHECK (
    max_per_local_day IS NULL OR max_per_local_day BETWEEN 1 AND 20
  ),
  CONSTRAINT coach_context_policies_refresh_check CHECK (
    refresh_cadence IN ('monthly', 'quarterly')
  ),
  CONSTRAINT coach_context_policies_email_disabled_check CHECK (
    channel <> 'email' OR NOT delivery_enabled
  )
);

CREATE TABLE public.coach_content_packs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  label text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  parent_pack_id uuid REFERENCES public.coach_content_packs(id) ON DELETE RESTRICT,
  effective_at timestamptz,
  activated_at timestamptz,
  archived_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at timestamptz,
  activated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT coach_content_packs_slug_check CHECK (
    slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
    AND char_length(slug) BETWEEN 3 AND 120
  ),
  CONSTRAINT coach_content_packs_label_check CHECK (
    char_length(btrim(label)) BETWEEN 1 AND 160
  ),
  CONSTRAINT coach_content_packs_status_check CHECK (
    status IN ('draft', 'scheduled', 'active', 'archived')
  ),
  CONSTRAINT coach_content_packs_parent_check CHECK (parent_pack_id IS DISTINCT FROM id),
  CONSTRAINT coach_content_packs_approval_pair_check CHECK (
    (approved_by IS NULL) = (approved_at IS NULL)
  )
);

CREATE UNIQUE INDEX coach_content_packs_one_active_idx
  ON public.coach_content_packs ((true))
  WHERE status = 'active';
CREATE INDEX coach_content_packs_due_idx
  ON public.coach_content_packs (effective_at, id)
  WHERE status = 'scheduled';

CREATE TABLE public.coach_message_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key text NOT NULL UNIQUE,
  personality_code text NOT NULL REFERENCES public.coach_personalities(code),
  context text NOT NULL,
  channel text NOT NULL,
  locale text NOT NULL,
  variant smallint NOT NULL,
  allowed_variables text[] NOT NULL DEFAULT ARRAY[]::text[],
  required_variables text[] NOT NULL DEFAULT ARRAY[]::text[],
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT coach_message_templates_key_check CHECK (
    template_key ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    AND char_length(template_key) BETWEEN 3 AND 240
  ),
  CONSTRAINT coach_message_templates_context_check CHECK (
    context IN (
      'onboarding',
      'meal_pending',
      'registration_confirmed',
      'error_corrected',
      'hydration',
      'supplement',
      'medication',
      'workout',
      'progress',
      'day_incomplete',
      'reevaluation',
      'reengagement',
      'trial',
      'paywall',
      'return_after_abandonment'
    )
  ),
  CONSTRAINT coach_message_templates_channel_check CHECK (
    channel IN ('in_app', 'push', 'email')
  ),
  CONSTRAINT coach_message_templates_locale_check CHECK (
    locale IN ('pt-BR', 'en-US')
  ),
  CONSTRAINT coach_message_templates_variant_check CHECK (variant BETWEEN 1 AND 3),
  CONSTRAINT coach_message_templates_required_subset_check CHECK (
    required_variables <@ allowed_variables
  ),
  CONSTRAINT coach_message_templates_variable_names_check CHECK (
    array_to_string(allowed_variables, ',') !~ '[^a-z0-9_,]'
    AND array_to_string(required_variables, ',') !~ '[^a-z0-9_,]'
  ),
  CONSTRAINT coach_message_templates_tuple_unique UNIQUE (
    personality_code,
    context,
    channel,
    locale,
    variant
  )
);

CREATE INDEX coach_message_templates_selection_idx
  ON public.coach_message_templates (context, channel, locale, personality_code, variant);

CREATE TABLE public.coach_message_template_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES public.coach_message_templates(id) ON DELETE RESTRICT,
  version integer NOT NULL,
  title text,
  subject text,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  provenance text NOT NULL,
  authored_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at timestamptz,
  archived_at timestamptz,
  content_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT coach_message_template_versions_version_check CHECK (version > 0),
  CONSTRAINT coach_message_template_versions_title_check CHECK (
    title IS NULL OR char_length(title) BETWEEN 1 AND 60
  ),
  CONSTRAINT coach_message_template_versions_subject_check CHECK (
    subject IS NULL OR char_length(subject) BETWEEN 1 AND 120
  ),
  CONSTRAINT coach_message_template_versions_body_check CHECK (
    char_length(body) BETWEEN 1 AND 4000
    AND body !~ E'[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]'
  ),
  CONSTRAINT coach_message_template_versions_status_check CHECK (
    status IN ('draft', 'active', 'archived')
  ),
  CONSTRAINT coach_message_template_versions_provenance_check CHECK (
    provenance IN ('seed', 'human', 'assisted_draft')
  ),
  CONSTRAINT coach_message_template_versions_approval_pair_check CHECK (
    (approved_by IS NULL) = (approved_at IS NULL)
  ),
  CONSTRAINT coach_message_template_versions_hash_check CHECK (
    content_hash ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT coach_message_template_versions_number_unique UNIQUE (template_id, version),
  CONSTRAINT coach_message_template_versions_id_template_unique UNIQUE (id, template_id)
);

CREATE INDEX coach_message_template_versions_status_idx
  ON public.coach_message_template_versions (template_id, status, version DESC);

CREATE TABLE public.coach_content_pack_entries (
  pack_id uuid NOT NULL REFERENCES public.coach_content_packs(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.coach_message_templates(id) ON DELETE RESTRICT,
  template_version_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (pack_id, template_id),
  CONSTRAINT coach_content_pack_entries_version_unique UNIQUE (pack_id, template_version_id),
  CONSTRAINT coach_content_pack_entries_version_template_fkey
    FOREIGN KEY (template_version_id, template_id)
    REFERENCES public.coach_message_template_versions(id, template_id)
    ON DELETE RESTRICT
);

CREATE INDEX coach_content_pack_entries_version_idx
  ON public.coach_content_pack_entries (template_version_id, pack_id);

CREATE TABLE public.coach_message_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  pack_id uuid REFERENCES public.coach_content_packs(id) ON DELETE RESTRICT,
  template_id uuid REFERENCES public.coach_message_templates(id) ON DELETE RESTRICT,
  template_version_id uuid REFERENCES public.coach_message_template_versions(id) ON DELETE RESTRICT,
  context text NOT NULL,
  channel text NOT NULL,
  locale text NOT NULL,
  requested_personality text NOT NULL,
  effective_personality text NOT NULL,
  outcome text NOT NULL,
  reason text NOT NULL,
  event_key_hash text,
  local_date date NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT coach_message_usage_context_check CHECK (
    context IN (
      'onboarding',
      'meal_pending',
      'registration_confirmed',
      'error_corrected',
      'hydration',
      'supplement',
      'medication',
      'workout',
      'progress',
      'day_incomplete',
      'reevaluation',
      'reengagement',
      'trial',
      'paywall',
      'return_after_abandonment'
    )
  ),
  CONSTRAINT coach_message_usage_channel_check CHECK (channel IN ('in_app', 'push', 'email')),
  CONSTRAINT coach_message_usage_locale_check CHECK (locale IN ('pt-BR', 'en-US')),
  CONSTRAINT coach_message_usage_requested_personality_check CHECK (
    requested_personality IN ('balanced', 'focus', 'impulse', 'zen')
  ),
  CONSTRAINT coach_message_usage_effective_personality_check CHECK (
    effective_personality IN ('balanced', 'focus', 'impulse', 'zen')
  ),
  CONSTRAINT coach_message_usage_outcome_check CHECK (
    outcome IN ('selected', 'suppressed', 'failed')
  ),
  CONSTRAINT coach_message_usage_reason_check CHECK (
    reason IN (
      'exact',
      'balanced_fallback',
      'delivery_disabled',
      'user_push_disabled',
      'cooldown',
      'daily_limit',
      'global_push_limit',
      'missing_variables',
      'catalog_incomplete'
    )
  ),
  CONSTRAINT coach_message_usage_event_hash_check CHECK (
    event_key_hash IS NULL OR event_key_hash ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT coach_message_usage_selection_shape_check CHECK (
    (
      outcome = 'selected'
      AND pack_id IS NOT NULL
      AND template_id IS NOT NULL
      AND template_version_id IS NOT NULL
      AND reason IN ('exact', 'balanced_fallback')
    ) OR (
      outcome <> 'selected'
      AND template_id IS NULL
      AND template_version_id IS NULL
    )
  )
);

CREATE UNIQUE INDEX coach_message_usage_event_idempotency_idx
  ON public.coach_message_usage (user_id, context, channel, event_key_hash)
  WHERE event_key_hash IS NOT NULL;
CREATE INDEX coach_message_usage_lru_idx
  ON public.coach_message_usage (user_id, template_id, occurred_at DESC)
  WHERE outcome = 'selected';
CREATE INDEX coach_message_usage_limits_idx
  ON public.coach_message_usage (user_id, context, channel, local_date, occurred_at DESC)
  WHERE outcome = 'selected';

CREATE TABLE public.user_mascot_state (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'inactive',
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT user_mascot_state_value_check CHECK (
    state IN ('inactive', 'reactivating', 'active', 'evolving', 'neglected')
  )
);

CREATE TABLE public.user_mascot_state_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  from_state text,
  to_state text NOT NULL,
  reason text NOT NULL,
  event_key_hash text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT user_mascot_state_events_from_check CHECK (
    from_state IS NULL OR from_state IN ('inactive', 'reactivating', 'active', 'evolving', 'neglected')
  ),
  CONSTRAINT user_mascot_state_events_to_check CHECK (
    to_state IN ('inactive', 'reactivating', 'active', 'evolving', 'neglected')
  ),
  CONSTRAINT user_mascot_state_events_reason_check CHECK (
    reason ~ '^[a-z0-9_.:-]+$'
    AND char_length(reason) BETWEEN 1 AND 80
  ),
  CONSTRAINT user_mascot_state_events_hash_check CHECK (
    event_key_hash ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT user_mascot_state_events_idempotency_unique UNIQUE (user_id, event_key_hash)
);

CREATE INDEX user_mascot_state_events_history_idx
  ON public.user_mascot_state_events (user_id, occurred_at DESC, id DESC);

INSERT INTO public.coach_personalities (
  code,
  name_pt_br,
  description_pt_br,
  name_en_us,
  description_en_us,
  selectable
) VALUES
  ('balanced', 'Equilibrado', 'Tom interno neutro usado quando nenhuma personalidade foi escolhida.', 'Balanced', 'Internal neutral tone used before a personality is selected.', false),
  ('focus', 'Focus', 'Comunicação objetiva, direta e orientada à próxima ação.', 'Focus', 'Direct, objective communication oriented to the next action.', true),
  ('impulse', 'Impulse', 'Comunicação energética e positiva, sem exageros ou pressão.', 'Impulse', 'Energetic and positive communication without hype or pressure.', true),
  ('zen', 'Zen', 'Comunicação calma, acolhedora e clara, sem perder precisão.', 'Zen', 'Calm, supportive and clear communication without losing precision.', true);

WITH context_policy(context, cooldown_seconds, max_per_local_day, refresh_cadence) AS (
  VALUES
    ('onboarding', 0, NULL::smallint, 'quarterly'),
    ('meal_pending', 14400, 2::smallint, 'monthly'),
    ('registration_confirmed', 0, NULL::smallint, 'monthly'),
    ('error_corrected', 0, NULL::smallint, 'monthly'),
    ('hydration', 7200, 3::smallint, 'monthly'),
    ('supplement', 0, NULL::smallint, 'monthly'),
    ('medication', 0, NULL::smallint, 'monthly'),
    ('workout', 0, 1::smallint, 'monthly'),
    ('progress', 0, 1::smallint, 'monthly'),
    ('day_incomplete', 0, 1::smallint, 'monthly'),
    ('reevaluation', 0, 1::smallint, 'quarterly'),
    ('reengagement', 259200, NULL::smallint, 'monthly'),
    ('trial', 0, 1::smallint, 'quarterly'),
    ('paywall', 0, 1::smallint, 'quarterly'),
    ('return_after_abandonment', 604800, NULL::smallint, 'quarterly')
), channel_policy(channel, delivery_enabled) AS (
  VALUES
    ('in_app', true),
    ('push', true),
    ('email', false)
)
INSERT INTO public.coach_message_context_policies (
  context,
  channel,
  cooldown_seconds,
  max_per_local_day,
  delivery_enabled,
  refresh_cadence
)
SELECT
  context_policy.context,
  channel_policy.channel,
  CASE
    WHEN channel_policy.channel = 'in_app'
      AND context_policy.context NOT IN (
        'progress',
        'day_incomplete',
        'reevaluation',
        'reengagement',
        'trial',
        'paywall',
        'return_after_abandonment'
      )
      THEN 0
    ELSE context_policy.cooldown_seconds
  END,
  CASE
    WHEN channel_policy.channel = 'in_app'
      AND context_policy.context NOT IN (
        'progress',
        'day_incomplete',
        'reevaluation',
        'trial',
        'paywall'
      )
      THEN NULL
    ELSE context_policy.max_per_local_day
  END,
  channel_policy.delivery_enabled,
  context_policy.refresh_cadence
FROM context_policy
CROSS JOIN channel_policy;

CREATE OR REPLACE FUNCTION private.enforce_coach_template_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'coach template identities are immutable; create a version instead'
    USING ERRCODE = '23514';
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_coach_version_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'coach message versions are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.template_id IS DISTINCT FROM OLD.template_id
    OR NEW.version IS DISTINCT FROM OLD.version
    OR NEW.title IS DISTINCT FROM OLD.title
    OR NEW.subject IS DISTINCT FROM OLD.subject
    OR NEW.body IS DISTINCT FROM OLD.body
    OR NEW.provenance IS DISTINCT FROM OLD.provenance
    OR NEW.authored_by IS DISTINCT FROM OLD.authored_by
    OR NEW.content_hash IS DISTINCT FROM OLD.content_hash
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'coach message copy is immutable; create a new version'
      USING ERRCODE = '23514';
  END IF;

  IF current_setting('bodyflow.coach_pack_lifecycle_write', true) IS DISTINCT FROM 'on'
    AND (
      NEW.status IS DISTINCT FROM OLD.status
      OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
      OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
      OR NEW.archived_at IS DISTINCT FROM OLD.archived_at
    ) THEN
    RAISE EXCEPTION 'coach version lifecycle changes require a pack RPC'
      USING ERRCODE = '23514';
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_coach_pack_entry_mutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pack_id uuid := COALESCE(NEW.pack_id, OLD.pack_id);
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.coach_content_packs pack
    WHERE pack.id = v_pack_id
      AND pack.status IN ('scheduled', 'active', 'archived')
  ) THEN
    RAISE EXCEPTION 'only draft content pack entries may change'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.reject_coach_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'BodyFlow coach audit records are append-only'
    USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER coach_message_templates_immutable
  BEFORE UPDATE OR DELETE ON public.coach_message_templates
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_coach_template_immutable();

CREATE TRIGGER coach_message_template_versions_immutable
  BEFORE UPDATE OR DELETE ON public.coach_message_template_versions
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_coach_version_immutable();

CREATE TRIGGER coach_content_pack_entries_mutable_drafts_only
  BEFORE INSERT OR UPDATE OR DELETE ON public.coach_content_pack_entries
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_coach_pack_entry_mutable();

CREATE TRIGGER coach_message_usage_append_only
  BEFORE UPDATE OR DELETE ON public.coach_message_usage
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_coach_audit_mutation();

CREATE TRIGGER user_mascot_state_events_append_only
  BEFORE UPDATE OR DELETE ON public.user_mascot_state_events
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_coach_audit_mutation();

CREATE OR REPLACE FUNCTION public.set_user_coach_personality(
  p_user_id uuid,
  p_personality text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_preference public.user_coach_preferences%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id is required' USING ERRCODE = '22023';
  END IF;

  IF p_personality NOT IN ('focus', 'impulse', 'zen')
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_personalities personality
      WHERE personality.code = p_personality
        AND personality.selectable
        AND personality.active
    ) THEN
    RAISE EXCEPTION 'personality must be focus, impulse, or zen'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users domain_user WHERE domain_user.id = p_user_id) THEN
    RAISE EXCEPTION 'domain user not found' USING ERRCODE = '23503';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('coach-preference:' || p_user_id::text, 0));

  INSERT INTO public.user_coach_preferences (
    user_id,
    personality_code,
    selected_at,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_personality,
    clock_timestamp(),
    clock_timestamp(),
    clock_timestamp()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET personality_code = EXCLUDED.personality_code,
      selected_at = CASE
        WHEN public.user_coach_preferences.personality_code = EXCLUDED.personality_code
          THEN public.user_coach_preferences.selected_at
        ELSE EXCLUDED.selected_at
      END,
      updated_at = clock_timestamp()
  RETURNING * INTO v_preference;

  RETURN jsonb_build_object(
    'user_id', v_preference.user_id,
    'selected_personality', v_preference.personality_code,
    'effective_personality', v_preference.personality_code,
    'selected_at', v_preference.selected_at
  );
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

CREATE OR REPLACE FUNCTION public.activate_due_coach_content_pack(
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pack_id uuid;
  v_approved_by uuid;
BEGIN
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'activation time is required' USING ERRCODE = '22023';
  END IF;

  SELECT pack.id, pack.approved_by
  INTO v_pack_id, v_approved_by
  FROM public.coach_content_packs pack
  WHERE pack.status = 'scheduled'
    AND pack.effective_at IS NOT NULL
    AND pack.effective_at <= p_now
    AND pack.approved_by IS NOT NULL
    AND pack.approved_at IS NOT NULL
  ORDER BY pack.effective_at, pack.id
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_pack_id IS NULL THEN
    RETURN jsonb_build_object('outcome', 'no_due_pack');
  END IF;

  RETURN public.activate_coach_content_pack(v_pack_id, v_approved_by, p_now);
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_user_mascot_state(
  p_user_id uuid,
  p_next_state text,
  p_reason text,
  p_event_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, extensions, pg_temp
AS $$
DECLARE
  v_current_state text;
  v_event_key_hash text;
  v_existing public.user_mascot_state_events%ROWTYPE;
  v_event public.user_mascot_state_events%ROWTYPE;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF p_user_id IS NULL
    OR p_next_state IS NULL
    OR p_reason IS NULL
    OR p_event_key IS NULL
    OR char_length(btrim(p_event_key)) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'valid user, state, reason, and event key are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_next_state NOT IN ('inactive', 'reactivating', 'active', 'evolving', 'neglected') THEN
    RAISE EXCEPTION 'invalid mascot state' USING ERRCODE = '23514';
  END IF;

  IF p_reason !~ '^[a-z0-9_.:-]+$' OR char_length(p_reason) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'mascot reason must be a bounded operational code'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users domain_user WHERE domain_user.id = p_user_id) THEN
    RAISE EXCEPTION 'domain user not found' USING ERRCODE = '23503';
  END IF;

  v_event_key_hash := encode(extensions.digest(btrim(p_event_key), 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('mascot-state:' || p_user_id::text, 0));

  SELECT *
  INTO v_existing
  FROM public.user_mascot_state_events event
  WHERE event.user_id = p_user_id
    AND event.event_key_hash = v_event_key_hash;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'event_id', v_existing.id,
      'user_id', v_existing.user_id,
      'from_state', v_existing.from_state,
      'state', v_existing.to_state,
      'reason', v_existing.reason,
      'changed_at', v_existing.occurred_at,
      'idempotent_replay', true
    );
  END IF;

  SELECT mascot.state
  INTO v_current_state
  FROM public.user_mascot_state mascot
  WHERE mascot.user_id = p_user_id
  FOR UPDATE;

  v_current_state := COALESCE(v_current_state, 'inactive');

  IF p_next_state = v_current_state
    OR NOT (
      (v_current_state = 'inactive' AND p_next_state IN ('reactivating', 'active'))
      OR (v_current_state = 'reactivating' AND p_next_state IN ('inactive', 'active'))
      OR (v_current_state = 'active' AND p_next_state IN ('inactive', 'evolving', 'neglected'))
      OR (v_current_state = 'evolving' AND p_next_state IN ('active', 'neglected'))
      OR (v_current_state = 'neglected' AND p_next_state IN ('inactive', 'reactivating', 'active'))
    ) THEN
    RAISE EXCEPTION 'invalid mascot transition from % to %', v_current_state, p_next_state
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.user_mascot_state (
    user_id,
    state,
    changed_at,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_next_state,
    v_now,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE
  SET state = EXCLUDED.state,
      changed_at = EXCLUDED.changed_at,
      updated_at = EXCLUDED.updated_at;

  INSERT INTO public.user_mascot_state_events (
    user_id,
    from_state,
    to_state,
    reason,
    event_key_hash,
    occurred_at
  ) VALUES (
    p_user_id,
    v_current_state,
    p_next_state,
    p_reason,
    v_event_key_hash,
    v_now
  )
  RETURNING * INTO v_event;

  RETURN jsonb_build_object(
    'event_id', v_event.id,
    'user_id', v_event.user_id,
    'from_state', v_event.from_state,
    'state', v_event.to_state,
    'reason', v_event.reason,
    'changed_at', v_event.occurred_at,
    'idempotent_replay', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_coach_message(
  p_user_id uuid,
  p_context text,
  p_channel text,
  p_locale text,
  p_event_key text,
  p_available_variables text[],
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, extensions, pg_temp
AS $$
DECLARE
  v_event_key_hash text;
  v_timezone text;
  v_local_date date;
  v_requested_personality text;
  v_effective_personality text;
  v_reason text;
  v_pack_id uuid;
  v_policy public.coach_message_context_policies%ROWTYPE;
  v_candidate record;
  v_usage_id uuid;
  v_result jsonb;
  v_latest_at timestamptz;
  v_selected_today integer;
  v_global_push_limit integer := 8;
  v_push_enabled boolean := true;
  v_global_push_count integer := 0;
  v_available_variables text[] := ARRAY[]::text[];
BEGIN
  IF p_user_id IS NULL
    OR p_context IS NULL
    OR p_channel IS NULL
    OR p_locale IS NULL
    OR p_event_key IS NULL
    OR p_now IS NULL
    OR char_length(btrim(p_event_key)) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'valid user, context, channel, locale, event key, and time are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_locale NOT IN ('pt-BR', 'en-US') THEN
    RAISE EXCEPTION 'unsupported coach locale' USING ERRCODE = '22023';
  END IF;

  IF p_available_variables IS NOT NULL AND EXISTS (
    SELECT 1
    FROM unnest(p_available_variables) variable(name)
    WHERE variable.name !~ '^[a-z][a-z0-9_]*$'
  ) THEN
    RAISE EXCEPTION 'available variable names are invalid' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT variable.name ORDER BY variable.name), ARRAY[]::text[])
  INTO v_available_variables
  FROM unnest(COALESCE(p_available_variables, ARRAY[]::text[])) variable(name);

  SELECT domain_user.timezone
  INTO v_timezone
  FROM public.users domain_user
  WHERE domain_user.id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'domain user not found' USING ERRCODE = '23503';
  END IF;

  v_timezone := COALESCE(NULLIF(v_timezone, ''), 'UTC');
  v_local_date := timezone(v_timezone, p_now)::date;
  v_event_key_hash := encode(extensions.digest(btrim(p_event_key), 'sha256'), 'hex');

  SELECT *
  INTO v_policy
  FROM public.coach_message_context_policies policy
  WHERE policy.context = p_context
    AND policy.channel = p_channel;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unsupported coach context or channel' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(preference.personality_code, 'balanced')
  INTO v_requested_personality
  FROM (SELECT 1) singleton
  LEFT JOIN public.user_coach_preferences preference
    ON preference.user_id = p_user_id;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      concat_ws(':', 'coach-claim', p_user_id::text, p_context, p_channel),
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.event_key_hash = v_event_key_hash
      AND usage.locale <> p_locale
  ) THEN
    RAISE EXCEPTION 'event key was already claimed with another locale'
      USING ERRCODE = '23514';
  END IF;

  SELECT jsonb_build_object(
    'usage_id', usage.id,
    'outcome', usage.outcome,
    'reason', usage.reason,
    'pack_id', usage.pack_id,
    'template_id', usage.template_id,
    'template_version_id', usage.template_version_id,
    'requested_personality', usage.requested_personality,
    'effective_personality', usage.effective_personality,
    'context', usage.context,
    'channel', usage.channel,
    'locale', usage.locale,
    'title', version.title,
    'subject', version.subject,
    'body', version.body,
    'allowed_variables', COALESCE(to_jsonb(template.allowed_variables), '[]'::jsonb),
    'required_variables', COALESCE(to_jsonb(template.required_variables), '[]'::jsonb),
    'occurred_at', usage.occurred_at,
    'idempotent_replay', true
  )
  INTO v_result
  FROM public.coach_message_usage usage
  LEFT JOIN public.coach_message_template_versions version
    ON version.id = usage.template_version_id
  LEFT JOIN public.coach_message_templates template
    ON template.id = usage.template_id
  WHERE usage.user_id = p_user_id
    AND usage.context = p_context
    AND usage.channel = p_channel
    AND usage.event_key_hash = v_event_key_hash;

  IF v_result IS NOT NULL THEN
    RETURN v_result;
  END IF;

  SELECT pack.id
  INTO v_pack_id
  FROM public.coach_content_packs pack
  WHERE pack.status = 'active';

  IF NOT v_policy.delivery_enabled THEN
    INSERT INTO public.coach_message_usage (
      user_id, pack_id, context, channel, locale,
      requested_personality, effective_personality, outcome, reason,
      event_key_hash, local_date, occurred_at
    ) VALUES (
      p_user_id, v_pack_id, p_context, p_channel, p_locale,
      v_requested_personality, v_requested_personality, 'suppressed', 'delivery_disabled',
      v_event_key_hash, v_local_date, p_now
    ) RETURNING id INTO v_usage_id;

    RETURN jsonb_build_object(
      'usage_id', v_usage_id,
      'outcome', 'suppressed',
      'reason', 'delivery_disabled',
      'pack_id', v_pack_id,
      'requested_personality', v_requested_personality,
      'effective_personality', v_requested_personality,
      'context', p_context,
      'channel', p_channel,
      'locale', p_locale,
      'idempotent_replay', false
    );
  END IF;

  IF v_pack_id IS NULL THEN
    INSERT INTO public.coach_message_usage (
      user_id, context, channel, locale,
      requested_personality, effective_personality, outcome, reason,
      event_key_hash, local_date, occurred_at
    ) VALUES (
      p_user_id, p_context, p_channel, p_locale,
      v_requested_personality, v_requested_personality, 'failed', 'catalog_incomplete',
      v_event_key_hash, v_local_date, p_now
    ) RETURNING id INTO v_usage_id;

    RETURN jsonb_build_object(
      'usage_id', v_usage_id,
      'outcome', 'failed',
      'reason', 'catalog_incomplete',
      'requested_personality', v_requested_personality,
      'effective_personality', v_requested_personality,
      'context', p_context,
      'channel', p_channel,
      'locale', p_locale,
      'idempotent_replay', false
    );
  END IF;

  SELECT
    template.id AS template_id,
    version.id AS template_version_id,
    template.personality_code,
    template.allowed_variables,
    template.required_variables,
    version.title,
    version.subject,
    version.body
  INTO v_candidate
  FROM public.coach_content_pack_entries entry
  JOIN public.coach_message_templates template ON template.id = entry.template_id
  JOIN public.coach_message_template_versions version
    ON version.id = entry.template_version_id
    AND version.template_id = template.id
  WHERE entry.pack_id = v_pack_id
    AND version.status = 'active'
    AND template.context = p_context
    AND template.channel = p_channel
    AND template.locale = p_locale
    AND template.personality_code IN (v_requested_personality, 'balanced')
    AND template.required_variables <@ v_available_variables
  ORDER BY
    CASE WHEN template.personality_code = v_requested_personality THEN 0 ELSE 1 END,
    CASE WHEN template.id = (
      SELECT previous_usage.template_id
      FROM public.coach_message_usage previous_usage
      JOIN public.coach_message_templates previous_template
        ON previous_template.id = previous_usage.template_id
      WHERE previous_usage.user_id = p_user_id
        AND previous_usage.outcome = 'selected'
        AND previous_usage.context = p_context
        AND previous_usage.channel = p_channel
        AND previous_usage.locale = p_locale
        AND previous_template.personality_code = template.personality_code
      ORDER BY previous_usage.occurred_at DESC, previous_usage.id DESC
      LIMIT 1
    ) THEN 1 ELSE 0 END,
    (
      SELECT max(previous_usage.occurred_at)
      FROM public.coach_message_usage previous_usage
      WHERE previous_usage.user_id = p_user_id
        AND previous_usage.outcome = 'selected'
        AND previous_usage.template_id = template.id
    ) ASC NULLS FIRST,
    template.variant,
    template.template_key
  LIMIT 1;

  IF v_candidate.template_id IS NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries entry
      JOIN public.coach_message_templates template ON template.id = entry.template_id
      JOIN public.coach_message_template_versions version
        ON version.id = entry.template_version_id
      WHERE entry.pack_id = v_pack_id
        AND version.status = 'active'
        AND template.context = p_context
        AND template.channel = p_channel
        AND template.locale = p_locale
        AND template.personality_code IN (v_requested_personality, 'balanced')
    ) THEN
      v_reason := 'missing_variables';
    ELSE
      v_reason := 'catalog_incomplete';
    END IF;

    INSERT INTO public.coach_message_usage (
      user_id, pack_id, context, channel, locale,
      requested_personality, effective_personality, outcome, reason,
      event_key_hash, local_date, occurred_at
    ) VALUES (
      p_user_id, v_pack_id, p_context, p_channel, p_locale,
      v_requested_personality, v_requested_personality, 'failed', v_reason,
      v_event_key_hash, v_local_date, p_now
    ) RETURNING id INTO v_usage_id;

    RETURN jsonb_build_object(
      'usage_id', v_usage_id,
      'outcome', 'failed',
      'reason', v_reason,
      'pack_id', v_pack_id,
      'requested_personality', v_requested_personality,
      'effective_personality', v_requested_personality,
      'context', p_context,
      'channel', p_channel,
      'locale', p_locale,
      'idempotent_replay', false
    );
  END IF;

  v_effective_personality := v_candidate.personality_code;
  v_reason := CASE
    WHEN v_effective_personality = v_requested_personality THEN 'exact'
    ELSE 'balanced_fallback'
  END;

  IF p_channel = 'push' THEN
    SELECT preference.push_enabled, preference.daily_push_limit
    INTO v_push_enabled, v_global_push_limit
    FROM public.notification_preferences preference
    WHERE preference.user_id = p_user_id;

    v_push_enabled := COALESCE(v_push_enabled, true);
    v_global_push_limit := COALESCE(v_global_push_limit, 8);

    IF NOT v_push_enabled THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'user_push_disabled',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'user_push_disabled',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  IF v_policy.cooldown_seconds > 0 THEN
    SELECT max(usage.occurred_at)
    INTO v_latest_at
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.outcome = 'selected';

    IF v_latest_at IS NOT NULL
      AND v_latest_at + make_interval(secs => v_policy.cooldown_seconds) > p_now THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'cooldown',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'cooldown',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  IF v_policy.max_per_local_day IS NOT NULL THEN
    SELECT count(*)
    INTO v_selected_today
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.local_date = v_local_date
      AND usage.outcome = 'selected';

    IF v_selected_today >= v_policy.max_per_local_day THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'daily_limit',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'daily_limit',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  IF p_channel = 'push' THEN
    SELECT
      (
        SELECT count(*)
        FROM public.coach_message_usage usage
        WHERE usage.user_id = p_user_id
          AND usage.channel = 'push'
          AND usage.local_date = v_local_date
          AND usage.outcome = 'selected'
      ) + (
        SELECT count(*)
        FROM public.reminder_events event
        WHERE event.user_id = p_user_id
          AND event.status = 'queued'
          AND timezone(v_timezone, event.scheduled_for)::date = v_local_date
      )
    INTO v_global_push_count;

    IF v_global_push_count >= v_global_push_limit THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'global_push_limit',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'global_push_limit',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  INSERT INTO public.coach_message_usage (
    user_id,
    pack_id,
    template_id,
    template_version_id,
    context,
    channel,
    locale,
    requested_personality,
    effective_personality,
    outcome,
    reason,
    event_key_hash,
    local_date,
    occurred_at
  ) VALUES (
    p_user_id,
    v_pack_id,
    v_candidate.template_id,
    v_candidate.template_version_id,
    p_context,
    p_channel,
    p_locale,
    v_requested_personality,
    v_effective_personality,
    'selected',
    v_reason,
    v_event_key_hash,
    v_local_date,
    p_now
  ) RETURNING id INTO v_usage_id;

  RETURN jsonb_build_object(
    'usage_id', v_usage_id,
    'outcome', 'selected',
    'reason', v_reason,
    'pack_id', v_pack_id,
    'template_id', v_candidate.template_id,
    'template_version_id', v_candidate.template_version_id,
    'requested_personality', v_requested_personality,
    'effective_personality', v_effective_personality,
    'context', p_context,
    'channel', p_channel,
    'locale', p_locale,
    'title', v_candidate.title,
    'subject', v_candidate.subject,
    'body', v_candidate.body,
    'allowed_variables', to_jsonb(v_candidate.allowed_variables),
    'required_variables', to_jsonb(v_candidate.required_variables),
    'occurred_at', p_now,
    'idempotent_replay', false
  );
END;
$$;

ALTER TABLE public.coach_personalities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_coach_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_message_context_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_content_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_message_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_message_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_content_pack_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_message_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_mascot_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_mascot_state_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.coach_personalities,
  public.user_coach_preferences,
  public.coach_message_context_policies,
  public.coach_content_packs,
  public.coach_message_templates,
  public.coach_message_template_versions,
  public.coach_content_pack_entries,
  public.coach_message_usage,
  public.user_mascot_state,
  public.user_mascot_state_events
FROM PUBLIC, anon, authenticated;

GRANT ALL PRIVILEGES ON TABLE
  public.coach_personalities,
  public.user_coach_preferences,
  public.coach_message_context_policies,
  public.coach_content_packs,
  public.coach_message_templates,
  public.coach_message_template_versions,
  public.coach_content_pack_entries,
  public.coach_message_usage,
  public.user_mascot_state,
  public.user_mascot_state_events
TO service_role;

REVOKE ALL ON FUNCTION
  private.enforce_coach_template_immutable(),
  private.enforce_coach_version_immutable(),
  private.enforce_coach_pack_entry_mutable(),
  private.reject_coach_audit_mutation()
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.set_user_coach_personality(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_coach_message(uuid, text, text, text, text, text[], timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.activate_coach_content_pack(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.activate_due_coach_content_pack(timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.transition_user_mascot_state(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.set_user_coach_personality(uuid, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_coach_message(uuid, text, text, text, text, text[], timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.activate_coach_content_pack(uuid, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.activate_due_coach_content_pack(timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.transition_user_mascot_state(uuid, text, text, text)
  TO service_role;

COMMENT ON TABLE public.coach_message_usage IS
  'Append-only selection telemetry. Stores no rendered body, raw event key, contact data, or patient message.';
COMMENT ON TABLE public.user_mascot_state IS
  'Current non-visual BodyFlow mascot state. Transitions are explicit and never inferred from elapsed time.';
COMMENT ON FUNCTION public.claim_coach_message(uuid, text, text, text, text, text[], timestamptz) IS
  'Service-only deterministic catalog claim with idempotency, local limits, locale isolation, and LRU variants.';

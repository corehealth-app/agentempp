-- App-only onboarding refinement: habitual water no longer blocks signup.
-- No row backfill, column/enum removal, grants, formulas, or legacy writer edits.
-- Existing completion/intents/receipts remain unchanged.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $preflight$
BEGIN
  IF current_user <> 'postgres' OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.oid = to_regprocedure('public.complete_mobile_onboarding_atomic(uuid,jsonb)')
      AND n.nspname = 'public' AND p.prosecdef
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND md5(p.prosrc) = '56865793e8a7ecd61e8aa65942ff41ca'
  ) THEN
    RAISE EXCEPTION 'onboarding_water_optional_unknown_source' USING ERRCODE = '55000';
  END IF;
END $preflight$;

CREATE OR REPLACE FUNCTION public.complete_mobile_onboarding_atomic(
  p_user_id uuid,
  p_submission jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_required_keys constant text[] := ARRAY[
    'name',
    'locale',
    'country',
    'timezone',
    'sex',
    'birth_date',
    'height_cm',
    'weight_kg',
    'objective',
    'activity_level',
    'training_frequency',
    'hunger_level',
    'wake_time',
    'bedtime',
    'food_organization',
    'persona',
    'document_actions'
  ];
  v_allowed_keys constant text[] := v_required_keys || ARRAY['body_fat_percent', 'water_intake'];
  v_action_count integer;
  v_current_count integer;
  v_required_count integer;
  v_matched_required_count integer;
  v_existing_completion timestamptz;
  v_existing_completed boolean;
  v_completed_at timestamptz;
  v_objective text;
  v_persona text;
  v_locale text;
  v_hunger text;
  v_body_fat numeric;
  v_requirement_keys text[];
  v_current_documents public.onboarding_legal_documents[];
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_submission IS NULL
    OR jsonb_typeof(p_submission) <> 'object'
    OR NOT (p_submission ?& v_required_keys)
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_submission) supplied_key
      WHERE supplied_key <> ALL(v_allowed_keys)
    ) THEN
    RAISE EXCEPTION 'invalid_onboarding_submission' USING ERRCODE = '22023';
  END IF;

  IF jsonb_typeof(p_submission -> 'name') <> 'string'
    OR char_length(btrim(p_submission ->> 'name')) NOT BETWEEN 1 AND 100
    OR p_submission ->> 'locale' NOT IN ('pt-BR', 'en-US')
    OR p_submission ->> 'country' !~ '^[A-Z]{2}$'
    OR NOT EXISTS (
      SELECT 1 FROM pg_timezone_names zone WHERE zone.name = p_submission ->> 'timezone'
    )
    OR p_submission ->> 'sex' NOT IN ('masculino', 'feminino')
    OR p_submission ->> 'birth_date' !~ '^\d{4}-\d{2}-\d{2}$'
    OR (p_submission ->> 'birth_date')::date > v_now::date
    OR jsonb_typeof(p_submission -> 'height_cm') <> 'number'
    OR (p_submission ->> 'height_cm')::numeric NOT BETWEEN 100 AND 250
    OR jsonb_typeof(p_submission -> 'weight_kg') <> 'number'
    OR (p_submission ->> 'weight_kg')::numeric NOT BETWEEN 30 AND 300
    OR (
      p_submission ? 'body_fat_percent'
      AND (
        jsonb_typeof(p_submission -> 'body_fat_percent') <> 'number'
        OR (p_submission ->> 'body_fat_percent')::numeric NOT BETWEEN 3 AND 60
      )
    )
    OR p_submission ->> 'objective' NOT IN ('recomposicao', 'ganho_massa', 'manutencao')
    OR p_submission ->> 'activity_level' NOT IN (
      'sedentario', 'leve', 'moderado', 'alto', 'atleta'
    )
    OR jsonb_typeof(p_submission -> 'training_frequency') <> 'number'
    OR (p_submission ->> 'training_frequency')::integer NOT BETWEEN 0 AND 7
    OR (
      p_submission ? 'water_intake'
      AND p_submission -> 'water_intake' <> 'null'::jsonb
      AND (jsonb_typeof(p_submission -> 'water_intake') IS DISTINCT FROM 'string'
        OR p_submission ->> 'water_intake' NOT IN ('pouco', 'moderado', 'bastante'))
    )
    OR p_submission ->> 'hunger_level' NOT IN ('pouca', 'moderada', 'muita')
    OR p_submission ->> 'wake_time' !~ '^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$'
    OR p_submission ->> 'bedtime' !~ '^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$'
    OR p_submission ->> 'food_organization' NOT IN ('sim', 'nao')
    OR jsonb_typeof(p_submission -> 'document_actions') <> 'array' THEN
    RAISE EXCEPTION 'invalid_onboarding_submission' USING ERRCODE = '22023';
  END IF;

  v_objective := p_submission ->> 'objective';
  v_persona := p_submission ->> 'persona';
  v_locale := p_submission ->> 'locale';
  v_hunger := p_submission ->> 'hunger_level';
  v_body_fat := CASE
    WHEN p_submission ? 'body_fat_percent'
      THEN (p_submission ->> 'body_fat_percent')::numeric
    ELSE NULL
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.coach_personalities personality
    WHERE personality.code = v_persona
      AND personality.selectable
      AND personality.active
  ) THEN
    RAISE EXCEPTION 'invalid_onboarding_persona' USING ERRCODE = '23514';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('mobile-onboarding:' || p_user_id::text, 0));

  SELECT profile.onboarding_completed, profile.onboarding_completed_at
  INTO v_existing_completed, v_existing_completion
  FROM public.users domain_user
  JOIN public.user_profiles profile ON profile.user_id = domain_user.id
  WHERE domain_user.id = p_user_id
    AND domain_user.status = 'active'
  FOR UPDATE OF domain_user, profile;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT requirement_set.document_keys
  INTO v_requirement_keys
  FROM public.onboarding_legal_requirement_sets requirement_set
  WHERE requirement_set.locale = v_locale
    AND requirement_set.publication_status = 'published'
    AND requirement_set.effective_at <= v_now
    AND requirement_set.published_at <= v_now
  ORDER BY
    requirement_set.effective_at DESC,
    requirement_set.published_at DESC,
    requirement_set.id DESC
  LIMIT 1;

  IF v_requirement_keys IS NULL THEN
    RAISE EXCEPTION 'onboarding_documents_unavailable' USING ERRCODE = '23514';
  END IF;

  SELECT array_agg(
    current_document::public.onboarding_legal_documents
    ORDER BY current_document.document_key
  )
  INTO v_current_documents
  FROM (
    SELECT DISTINCT ON (document.document_key)
      document.*
    FROM public.onboarding_legal_documents document
    WHERE document.locale = v_locale
      AND document.document_key = ANY(v_requirement_keys)
      AND document.publication_status = 'published'
      AND document.effective_at <= v_now
      AND document.published_at <= v_now
    ORDER BY
      document.document_key,
      document.effective_at DESC,
      document.published_at DESC,
      document.id DESC
  ) current_document;

  SELECT count(*), count(*) FILTER (WHERE required)
  INTO v_current_count, v_required_count
  FROM unnest(v_current_documents) document;

  IF v_current_count <> cardinality(v_requirement_keys)
    OR v_required_count <> v_current_count
    OR v_current_count > 16 THEN
    RAISE EXCEPTION 'onboarding_documents_unavailable' USING ERRCODE = '23514';
  END IF;

  SELECT jsonb_array_length(p_submission -> 'document_actions')
  INTO v_action_count;
  IF v_action_count < 1 OR v_action_count > 16
    OR v_action_count <> (
      SELECT count(DISTINCT action ->> 'document_key')
      FROM jsonb_array_elements(p_submission -> 'document_actions') action
    ) THEN
    RAISE EXCEPTION 'invalid_onboarding_document_actions' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_submission -> 'document_actions') action
    WHERE jsonb_typeof(action) <> 'object'
      OR NOT (action ?& ARRAY['document_key', 'version', 'locale', 'content_hash', 'action'])
      OR EXISTS (
        SELECT 1
        FROM jsonb_object_keys(action) action_key
        WHERE action_key <> ALL(ARRAY[
          'document_key', 'version', 'locale', 'content_hash', 'action'
        ])
      )
      OR action ->> 'document_key' !~ '^[a-z][a-z0-9_]{0,99}$'
      OR action ->> 'document_key' ~ '^dev_'
      OR action ->> 'version' !~ '^[A-Za-z0-9._-]{1,64}$'
      OR action ->> 'locale' <> v_locale
      OR action ->> 'content_hash' !~ '^[0-9a-f]{64}$'
      OR action ->> 'action' NOT IN ('acceptance', 'acknowledgement', 'consent')
  ) THEN
    RAISE EXCEPTION 'invalid_onboarding_document_actions' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_submission -> 'document_actions') action
    LEFT JOIN unnest(v_current_documents) document
      ON document.document_key = action ->> 'document_key'
      AND document.version = action ->> 'version'
      AND document.locale = action ->> 'locale'
      AND document.content_hash = action ->> 'content_hash'
      AND document.action_type = action ->> 'action'
    WHERE document.id IS NULL
  ) THEN
    RAISE EXCEPTION 'onboarding_document_version_mismatch' USING ERRCODE = '23514';
  END IF;

  SELECT count(*)
  INTO v_matched_required_count
  FROM unnest(v_current_documents) document
  JOIN jsonb_array_elements(p_submission -> 'document_actions') action
    ON document.document_key = action ->> 'document_key'
    AND document.version = action ->> 'version'
    AND document.locale = action ->> 'locale'
    AND document.content_hash = action ->> 'content_hash'
    AND document.action_type = action ->> 'action'
  WHERE document.required;

  IF v_matched_required_count <> v_required_count THEN
    RAISE EXCEPTION 'onboarding_required_action_missing' USING ERRCODE = '23514';
  END IF;

  IF v_existing_completion IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.users domain_user
      JOIN public.user_profiles profile ON profile.user_id = domain_user.id
      JOIN public.user_coach_preferences preference ON preference.user_id = domain_user.id
      WHERE domain_user.id = p_user_id
        AND domain_user.name = btrim(p_submission ->> 'name')
        AND domain_user.locale = v_locale
        AND domain_user.timezone = p_submission ->> 'timezone'
        AND domain_user.country = p_submission ->> 'country'
        AND domain_user.country_confirmed
        AND profile.sex = (p_submission ->> 'sex')::public.sex_enum
        AND profile.birth_date = (p_submission ->> 'birth_date')::date
        AND profile.height_cm = (p_submission ->> 'height_cm')::numeric
        AND profile.weight_kg = (p_submission ->> 'weight_kg')::numeric
        AND profile.body_fat_percent IS NOT DISTINCT FROM v_body_fat
        AND profile.activity_level = (p_submission ->> 'activity_level')::public.activity_enum
        AND profile.training_frequency = (p_submission ->> 'training_frequency')::smallint
        -- Missing/unknown is not a request to erase a historical answer.
        AND (p_submission ->> 'water_intake' IS NULL
          OR profile.water_intake IS NOT DISTINCT FROM
            (p_submission ->> 'water_intake')::public.water_enum)
        AND profile.hunger_level = (p_submission ->> 'hunger_level')::public.hunger_enum
        AND profile.wake_time = (p_submission ->> 'wake_time')::time
        AND profile.bedtime = (p_submission ->> 'bedtime')::time
        AND profile.food_organization = p_submission ->> 'food_organization'
        AND profile.current_protocol = v_objective::public.protocol_enum
        AND profile.onboarding_step = 6
        AND profile.onboarding_completed
        AND profile.onboarding_completed_at = v_existing_completion
        AND preference.personality_code = v_persona
    ) THEN
      RAISE EXCEPTION 'onboarding_already_completed' USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.user_onboarding_legal_actions (
      user_id,
      legal_document_id,
      document_key,
      version,
      locale,
      content_hash,
      purpose,
      action_type,
      acted_at,
      created_at
    )
    SELECT
      p_user_id,
      document.id,
      document.document_key,
      document.version,
      document.locale,
      document.content_hash,
      document.purpose,
      document.action_type,
      v_now,
      v_now
    FROM unnest(v_current_documents) document
    JOIN jsonb_array_elements(p_submission -> 'document_actions') action
      ON document.document_key = action ->> 'document_key'
      AND document.version = action ->> 'version'
      AND document.locale = action ->> 'locale'
      AND document.content_hash = action ->> 'content_hash'
      AND document.action_type = action ->> 'action'
    ON CONFLICT (user_id, legal_document_id) DO NOTHING;

    SELECT jsonb_build_object(
      'user_id', p_user_id,
      'onboarding_completed', true,
      'completed_at', v_existing_completion,
      'objective', v_objective,
      'persona', v_persona,
      'document_actions', COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'document_key', action.document_key,
              'version', action.version,
              'locale', action.locale,
              'content_hash', action.content_hash,
              'purpose', action.purpose,
              'action', action.action_type,
              'acted_at', action.acted_at
            ) ORDER BY action.document_key
          )
          FROM public.user_onboarding_legal_actions action
          JOIN unnest(v_current_documents) document
            ON document.id = action.legal_document_id
          WHERE action.user_id = p_user_id
        ),
        '[]'::jsonb
      )
    ) INTO v_result;

    RETURN v_result;
  END IF;

  UPDATE public.users domain_user
  SET name = btrim(p_submission ->> 'name'),
      locale = v_locale,
      timezone = p_submission ->> 'timezone',
      country = p_submission ->> 'country',
      country_confirmed = true,
      updated_at = CASE
        WHEN domain_user.name IS DISTINCT FROM btrim(p_submission ->> 'name')
          OR domain_user.locale IS DISTINCT FROM v_locale
          OR domain_user.timezone IS DISTINCT FROM p_submission ->> 'timezone'
          OR domain_user.country IS DISTINCT FROM p_submission ->> 'country'
          OR NOT domain_user.country_confirmed
          THEN v_now
        ELSE domain_user.updated_at
      END
  WHERE domain_user.id = p_user_id;

  UPDATE public.user_profiles profile
  SET sex = (p_submission ->> 'sex')::public.sex_enum,
      birth_date = (p_submission ->> 'birth_date')::date,
      height_cm = (p_submission ->> 'height_cm')::numeric,
      weight_kg = (p_submission ->> 'weight_kg')::numeric,
      body_fat_measured_at = CASE
        WHEN profile.body_fat_percent IS DISTINCT FROM v_body_fat THEN v_now
        ELSE profile.body_fat_measured_at
      END,
      body_fat_percent = v_body_fat,
      activity_level = (p_submission ->> 'activity_level')::public.activity_enum,
      training_frequency = (p_submission ->> 'training_frequency')::smallint,
      water_intake = COALESCE((p_submission ->> 'water_intake')::public.water_enum,
        profile.water_intake),
      hunger_level = (p_submission ->> 'hunger_level')::public.hunger_enum,
      wake_time = (p_submission ->> 'wake_time')::time,
      bedtime = (p_submission ->> 'bedtime')::time,
      food_organization = p_submission ->> 'food_organization',
      cycle_start_weight_kg = CASE
        WHEN v_objective IN ('ganho_massa', 'manutencao')
          AND profile.current_protocol IS DISTINCT FROM v_objective::public.protocol_enum
          THEN (p_submission ->> 'weight_kg')::numeric
        ELSE profile.cycle_start_weight_kg
      END,
      cycle_start_bf_percent = CASE
        WHEN v_objective IN ('ganho_massa', 'manutencao')
          AND profile.current_protocol IS DISTINCT FROM v_objective::public.protocol_enum
          THEN v_body_fat
        ELSE profile.cycle_start_bf_percent
      END,
      cycle_start_training_freq = CASE
        WHEN v_objective IN ('ganho_massa', 'manutencao')
          AND profile.current_protocol IS DISTINCT FROM v_objective::public.protocol_enum
          THEN (p_submission ->> 'training_frequency')::smallint
        ELSE profile.cycle_start_training_freq
      END,
      cycle_start_at = CASE
        WHEN v_objective IN ('ganho_massa', 'manutencao')
          AND profile.current_protocol IS DISTINCT FROM v_objective::public.protocol_enum
          THEN v_now
        ELSE profile.cycle_start_at
      END,
      current_protocol = v_objective::public.protocol_enum,
      deficit_level = CASE
        WHEN v_objective = 'recomposicao' THEN CASE v_hunger
          WHEN 'muita' THEN 400
          WHEN 'moderada' THEN 500
          WHEN 'pouca' THEN 600
        END
        ELSE NULL
      END,
      onboarding_step = 6,
      onboarding_completed = true,
      onboarding_completed_at = COALESCE(profile.onboarding_completed_at, v_now),
      updated_at = CASE
        WHEN profile.onboarding_completed_at IS NULL THEN v_now
        ELSE profile.updated_at
      END
  WHERE profile.user_id = p_user_id
  RETURNING profile.onboarding_completed_at INTO v_completed_at;

  INSERT INTO public.user_coach_preferences (
    user_id,
    personality_code,
    selected_at,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    v_persona,
    v_now,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE
  SET personality_code = EXCLUDED.personality_code,
      selected_at = CASE
        WHEN public.user_coach_preferences.personality_code = EXCLUDED.personality_code
          THEN public.user_coach_preferences.selected_at
        ELSE EXCLUDED.selected_at
      END,
      updated_at = CASE
        WHEN public.user_coach_preferences.personality_code = EXCLUDED.personality_code
          THEN public.user_coach_preferences.updated_at
        ELSE EXCLUDED.updated_at
      END;

  INSERT INTO public.user_onboarding_legal_actions (
    user_id,
    legal_document_id,
    document_key,
    version,
    locale,
    content_hash,
    purpose,
    action_type,
    acted_at,
    created_at
  )
  SELECT
    p_user_id,
    document.id,
    document.document_key,
    document.version,
    document.locale,
    document.content_hash,
    document.purpose,
    document.action_type,
    v_now,
    v_now
  FROM unnest(v_current_documents) document
  JOIN jsonb_array_elements(p_submission -> 'document_actions') action
    ON document.document_key = action ->> 'document_key'
    AND document.version = action ->> 'version'
    AND document.locale = action ->> 'locale'
    AND document.content_hash = action ->> 'content_hash'
    AND document.action_type = action ->> 'action'
  ON CONFLICT (user_id, legal_document_id) DO NOTHING;

  SELECT jsonb_build_object(
    'user_id', p_user_id,
    'onboarding_completed', true,
    'completed_at', v_completed_at,
    'objective', v_objective,
    'persona', v_persona,
    'document_actions', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'document_key', action.document_key,
            'version', action.version,
            'locale', action.locale,
            'content_hash', action.content_hash,
            'purpose', action.purpose,
            'action', action.action_type,
            'acted_at', action.acted_at
          ) ORDER BY action.document_key
        )
        FROM public.user_onboarding_legal_actions action
        JOIN unnest(v_current_documents) document
          ON document.id = action.legal_document_id
        WHERE action.user_id = p_user_id
      ),
      '[]'::jsonb
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMIT;

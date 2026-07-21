-- Deterministic, service-only mobile content delivery.

CREATE INDEX subscriptions_content_delivery_idx
  ON public.subscriptions (
    user_id,
    current_period_end DESC,
    updated_at DESC,
    created_at DESC,
    id DESC
  )
  INCLUDE (plan, status, trial_ends_at)
  WHERE status IN ('active', 'trial');

CREATE TABLE private.content_mutation_receipts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  event_key_hash text NOT NULL,
  operation text NOT NULL,
  publication_id uuid NOT NULL REFERENCES public.content_publications(id) ON DELETE RESTRICT,
  content_version integer NOT NULL,
  event_type text,
  desired_saved boolean,
  origin text NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, event_key_hash),
  CONSTRAINT content_mutation_receipts_key_hash_check CHECK (
    event_key_hash ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT content_mutation_receipts_operation_check CHECK (
    operation IN ('record_event', 'set_saved')
  ),
  CONSTRAINT content_mutation_receipts_version_check CHECK (content_version > 0),
  CONSTRAINT content_mutation_receipts_event_type_check CHECK (
    event_type IS NULL OR event_type IN ('impression', 'opened', 'completed')
  ),
  CONSTRAINT content_mutation_receipts_origin_check CHECK (
    origin IN ('today', 'library', 'push')
  ),
  CONSTRAINT content_mutation_receipts_semantics_check CHECK (
    (
      operation = 'record_event'
      AND event_type IS NOT NULL
      AND desired_saved IS NULL
    ) OR (
      operation = 'set_saved'
      AND event_type IS NULL
      AND desired_saved IS NOT NULL
    )
  ),
  CONSTRAINT content_mutation_receipts_response_check CHECK (
    jsonb_typeof(response) = 'object'
    AND octet_length(response::text) <= 2048
  )
);

ALTER TABLE private.content_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.content_mutation_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.content_mutation_receipts
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE private.content_mutation_receipts
  TO service_role;

CREATE OR REPLACE FUNCTION public.list_mobile_content(
  p_user_id uuid,
  p_surface text DEFAULT 'library',
  p_category text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_cursor_publish_at timestamptz DEFAULT NULL,
  p_cursor_publication_id uuid DEFAULT NULL,
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_surface IS NULL OR p_surface NOT IN ('today', 'library', 'saved') THEN
    RAISE EXCEPTION 'invalid_content_surface' USING ERRCODE = '22023';
  END IF;
  IF p_category IS NOT NULL AND p_category NOT IN (
    'weight_loss',
    'hypertrophy',
    'nutrition',
    'training',
    'neuroscience',
    'habit_formation',
    'cardiovascular_health',
    'hydration',
    'supplementation',
    'sleep',
    'using_bodyflow'
  ) THEN
    RAISE EXCEPTION 'invalid_content_category' USING ERRCODE = '22023';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'invalid_content_limit' USING ERRCODE = '22023';
  END IF;
  IF (p_cursor_publish_at IS NULL) <> (p_cursor_publication_id IS NULL) THEN
    RAISE EXCEPTION 'invalid_content_cursor' USING ERRCODE = '22023';
  END IF;
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_content_time' USING ERRCODE = '22023';
  END IF;

  WITH patient AS (
    SELECT
      domain_user.locale,
      profile.current_protocol,
      preference.personality_code,
      (
        SELECT subscription.plan
        FROM public.subscriptions subscription
        WHERE subscription.user_id = domain_user.id
          AND subscription.status IN ('active', 'trial')
          AND subscription.current_period_end IS NOT NULL
          AND subscription.current_period_end > p_now
          AND (
            subscription.status <> 'trial'
            OR (
              subscription.trial_ends_at IS NOT NULL
              AND subscription.trial_ends_at > p_now
            )
          )
        ORDER BY
          CASE
            WHEN subscription.status = 'trial' THEN least(
              subscription.current_period_end,
              subscription.trial_ends_at
            )
            ELSE subscription.current_period_end
          END DESC,
          subscription.updated_at DESC,
          subscription.created_at DESC,
          subscription.id DESC
        LIMIT 1
      ) AS plan
    FROM public.users domain_user
    LEFT JOIN public.user_profiles profile
      ON profile.user_id = domain_user.id
    LEFT JOIN public.user_coach_preferences preference
      ON preference.user_id = domain_user.id
      AND preference.personality_code <> 'balanced'
    WHERE domain_user.id = p_user_id
      AND domain_user.locale IN ('pt-BR', 'en-US')
  ),
  ranked_visible AS (
    SELECT
      publication.id AS publication_id,
      publication.slug,
      content_version.id AS version_id,
      content_version.version,
      content_version.locale,
      content_version.category,
      content_version.title,
      content_version.excerpt,
      content_version.tags,
      content_version.reading_time_minutes,
      content_version.featured_today,
      content_version.publish_at,
      content_version.cover_asset_id,
      patient.current_protocol,
      patient.plan,
      patient.personality_code,
      row_number() OVER (
        PARTITION BY publication.id
        ORDER BY content_version.publish_at DESC, content_version.version DESC
      ) AS visibility_rank
    FROM patient
    JOIN public.content_versions content_version
      ON content_version.locale = patient.locale
      AND content_version.state = 'approved'
      AND content_version.publish_at IS NOT NULL
      AND content_version.publish_at <= p_now
    JOIN public.content_publications publication
      ON publication.id = content_version.publication_id
      AND publication.archived_at IS NULL
  ),
  eligible AS (
    SELECT ranked_visible.*
    FROM ranked_visible
    WHERE ranked_visible.visibility_rank = 1
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.protocol = ranked_visible.current_protocol
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.plan = ranked_visible.plan
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.personality_code = ranked_visible.personality_code
            AND target.personality_code <> 'balanced'
        )
      )
  ),
  filtered AS (
    SELECT
      eligible.*,
      state.saved_at IS NOT NULL AS saved,
      state.completed_at IS NOT NULL
        AND state.completed_version_id = eligible.version_id AS completed,
      asset.bucket_id AS cover_bucket_id,
      asset.object_path AS cover_object_path
    FROM eligible
    LEFT JOIN public.content_user_state state
      ON state.user_id = p_user_id
      AND state.publication_id = eligible.publication_id
    LEFT JOIN public.content_assets asset
      ON asset.id = eligible.cover_asset_id
      AND asset.status = 'uploaded'
    WHERE (p_surface <> 'today' OR eligible.featured_today)
      AND (p_surface <> 'saved' OR state.saved_at IS NOT NULL)
      AND (p_category IS NULL OR eligible.category = p_category)
      AND (
        p_cursor_publish_at IS NULL
        OR eligible.publish_at < p_cursor_publish_at
        OR (
          eligible.publish_at = p_cursor_publish_at
          AND eligible.publication_id < p_cursor_publication_id
        )
      )
  ),
  page_with_sentinel AS (
    SELECT filtered.*
    FROM filtered
    ORDER BY filtered.publish_at DESC, filtered.publication_id DESC
    LIMIT p_limit + 1
  ),
  returned_page AS (
    SELECT page_with_sentinel.*
    FROM page_with_sentinel
    ORDER BY page_with_sentinel.publish_at DESC, page_with_sentinel.publication_id DESC
    LIMIT p_limit
  )
  SELECT jsonb_build_object(
    'items', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'publicationId', item.publication_id,
            'slug', item.slug,
            'locale', item.locale,
            'title', item.title,
            'excerpt', item.excerpt,
            'category', item.category,
            'tags', to_jsonb(item.tags),
            'readingTimeMinutes', item.reading_time_minutes,
            'publishAt', item.publish_at,
            'featuredToday', item.featured_today,
            'version', item.version,
            'saved', item.saved,
            'completed', item.completed,
            'cover', CASE
              WHEN item.cover_bucket_id IS NULL THEN NULL
              ELSE jsonb_build_object(
                'bucketId', item.cover_bucket_id,
                'objectPath', item.cover_object_path
              )
            END
          )
          ORDER BY item.publish_at DESC, item.publication_id DESC
        )
        FROM returned_page item
      ),
      '[]'::jsonb
    ),
    'nextCursor', CASE
      WHEN (SELECT count(*) FROM page_with_sentinel) > p_limit THEN (
        SELECT jsonb_build_object(
          'publishAt', cursor_item.publish_at,
          'publicationId', cursor_item.publication_id
        )
        FROM returned_page cursor_item
        ORDER BY cursor_item.publish_at DESC, cursor_item.publication_id DESC
        OFFSET p_limit - 1
        LIMIT 1
      )
      ELSE NULL
    END
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_mobile_content(
  p_user_id uuid,
  p_publication_id uuid,
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_content_time' USING ERRCODE = '22023';
  END IF;

  WITH patient AS (
    SELECT
      domain_user.locale,
      profile.current_protocol,
      preference.personality_code,
      (
        SELECT subscription.plan
        FROM public.subscriptions subscription
        WHERE subscription.user_id = domain_user.id
          AND subscription.status IN ('active', 'trial')
          AND subscription.current_period_end IS NOT NULL
          AND subscription.current_period_end > p_now
          AND (
            subscription.status <> 'trial'
            OR (
              subscription.trial_ends_at IS NOT NULL
              AND subscription.trial_ends_at > p_now
            )
          )
        ORDER BY
          CASE
            WHEN subscription.status = 'trial' THEN least(
              subscription.current_period_end,
              subscription.trial_ends_at
            )
            ELSE subscription.current_period_end
          END DESC,
          subscription.updated_at DESC,
          subscription.created_at DESC,
          subscription.id DESC
        LIMIT 1
      ) AS plan
    FROM public.users domain_user
    LEFT JOIN public.user_profiles profile
      ON profile.user_id = domain_user.id
    LEFT JOIN public.user_coach_preferences preference
      ON preference.user_id = domain_user.id
      AND preference.personality_code <> 'balanced'
    WHERE domain_user.id = p_user_id
      AND domain_user.locale IN ('pt-BR', 'en-US')
  ),
  ranked_visible AS (
    SELECT
      publication.id AS publication_id,
      publication.slug,
      content_version.id AS version_id,
      content_version.version,
      content_version.locale,
      content_version.category,
      content_version.title,
      content_version.excerpt,
      content_version.body_markdown,
      content_version.tags,
      content_version.reading_time_minutes,
      content_version.featured_today,
      content_version.publish_at,
      content_version.cover_asset_id,
      patient.current_protocol,
      patient.plan,
      patient.personality_code,
      row_number() OVER (
        PARTITION BY publication.id
        ORDER BY content_version.publish_at DESC, content_version.version DESC
      ) AS visibility_rank
    FROM patient
    JOIN public.content_versions content_version
      ON content_version.locale = patient.locale
      AND content_version.state = 'approved'
      AND content_version.publish_at IS NOT NULL
      AND content_version.publish_at <= p_now
      AND content_version.publication_id = p_publication_id
    JOIN public.content_publications publication
      ON publication.id = content_version.publication_id
      AND publication.archived_at IS NULL
  ),
  eligible AS (
    SELECT ranked_visible.*
    FROM ranked_visible
    WHERE ranked_visible.visibility_rank = 1
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.protocol = ranked_visible.current_protocol
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.plan = ranked_visible.plan
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.personality_code = ranked_visible.personality_code
            AND target.personality_code <> 'balanced'
        )
      )
  )
  SELECT jsonb_build_object(
    'publicationId', eligible.publication_id,
    'slug', eligible.slug,
    'locale', eligible.locale,
    'title', eligible.title,
    'excerpt', eligible.excerpt,
    'bodyMarkdown', eligible.body_markdown,
    'category', eligible.category,
    'tags', to_jsonb(eligible.tags),
    'readingTimeMinutes', eligible.reading_time_minutes,
    'publishAt', eligible.publish_at,
    'featuredToday', eligible.featured_today,
    'version', eligible.version,
    'saved', state.saved_at IS NOT NULL,
    'completed', state.completed_at IS NOT NULL
      AND state.completed_version_id = eligible.version_id,
    'cover', CASE
      WHEN asset.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'bucketId', asset.bucket_id,
        'objectPath', asset.object_path
      )
    END
  )
  INTO v_result
  FROM eligible
  LEFT JOIN public.content_user_state state
    ON state.user_id = p_user_id
    AND state.publication_id = eligible.publication_id
  LEFT JOIN public.content_assets asset
    ON asset.id = eligible.cover_asset_id
    AND asset.status = 'uploaded';

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_mobile_content_event(
  p_user_id uuid,
  p_publication_id uuid,
  p_version integer,
  p_event_type text,
  p_origin text,
  p_event_key text,
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_version_id uuid;
  v_visible_version integer;
  v_key text;
  v_key_hash text;
  v_existing_operation text;
  v_existing_publication_id uuid;
  v_existing_version integer;
  v_existing_event_type text;
  v_existing_desired_saved boolean;
  v_existing_origin text;
  v_existing_response jsonb;
  v_receipt_inserted boolean := false;
  v_event_inserted boolean := false;
  v_saved boolean;
  v_completed boolean;
  v_response jsonb;
BEGIN
  IF p_user_id IS NULL OR p_publication_id IS NULL THEN
    RAISE EXCEPTION 'invalid_content_identity' USING ERRCODE = '22023';
  END IF;
  IF p_version IS NULL OR p_version <= 0 THEN
    RAISE EXCEPTION 'invalid_content_version' USING ERRCODE = '22023';
  END IF;
  IF p_event_type IS NULL OR p_event_type NOT IN ('impression', 'opened', 'completed') THEN
    RAISE EXCEPTION 'invalid_content_event' USING ERRCODE = '22023';
  END IF;
  IF p_origin IS NULL OR p_origin NOT IN ('today', 'library', 'push') THEN
    RAISE EXCEPTION 'invalid_content_origin' USING ERRCODE = '22023';
  END IF;
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_content_time' USING ERRCODE = '22023';
  END IF;

  v_key := btrim(p_event_key);
  IF v_key IS NULL OR char_length(v_key) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'invalid_content_event_key' USING ERRCODE = '22023';
  END IF;
  v_key_hash := encode(
    extensions.digest(convert_to(v_key, 'UTF8'), 'sha256'),
    'hex'
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_publication_id::text, 0)
  );

  PERFORM content_version.id
  FROM public.content_versions content_version
  WHERE content_version.publication_id = p_publication_id
    AND content_version.locale = (
      SELECT domain_user.locale
      FROM public.users domain_user
      WHERE domain_user.id = p_user_id
        AND domain_user.locale IN ('pt-BR', 'en-US')
    )
    AND content_version.state = 'approved'
    AND content_version.publish_at IS NOT NULL
    AND content_version.publish_at <= p_now
  ORDER BY content_version.publish_at DESC, content_version.version DESC
  LIMIT 1
  FOR KEY SHARE OF content_version;

  PERFORM 1
  FROM public.content_publications publication
  WHERE publication.id = p_publication_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'content_not_visible' USING ERRCODE = 'P0002';
  END IF;

  SELECT
    receipt.operation,
    receipt.publication_id,
    receipt.content_version,
    receipt.event_type,
    receipt.desired_saved,
    receipt.origin,
    receipt.response
  INTO
    v_existing_operation,
    v_existing_publication_id,
    v_existing_version,
    v_existing_event_type,
    v_existing_desired_saved,
    v_existing_origin,
    v_existing_response
  FROM private.content_mutation_receipts receipt
  WHERE receipt.user_id = p_user_id
    AND receipt.event_key_hash = v_key_hash;

  IF FOUND THEN
    IF v_existing_operation IS DISTINCT FROM 'record_event'
      OR v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS DISTINCT FROM p_event_type
      OR v_existing_desired_saved IS NOT NULL
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;
    RETURN v_existing_response;
  END IF;

  WITH patient AS (
    SELECT
      domain_user.locale,
      profile.current_protocol,
      preference.personality_code,
      (
        SELECT subscription.plan
        FROM public.subscriptions subscription
        WHERE subscription.user_id = domain_user.id
          AND subscription.status IN ('active', 'trial')
          AND subscription.current_period_end IS NOT NULL
          AND subscription.current_period_end > p_now
          AND (
            subscription.status <> 'trial'
            OR (
              subscription.trial_ends_at IS NOT NULL
              AND subscription.trial_ends_at > p_now
            )
          )
        ORDER BY
          CASE
            WHEN subscription.status = 'trial' THEN least(
              subscription.current_period_end,
              subscription.trial_ends_at
            )
            ELSE subscription.current_period_end
          END DESC,
          subscription.updated_at DESC,
          subscription.created_at DESC,
          subscription.id DESC
        LIMIT 1
      ) AS plan
    FROM public.users domain_user
    LEFT JOIN public.user_profiles profile
      ON profile.user_id = domain_user.id
    LEFT JOIN public.user_coach_preferences preference
      ON preference.user_id = domain_user.id
      AND preference.personality_code <> 'balanced'
    WHERE domain_user.id = p_user_id
      AND domain_user.locale IN ('pt-BR', 'en-US')
  ),
  ranked_visible AS (
    SELECT
      content_version.id AS version_id,
      content_version.version,
      patient.current_protocol,
      patient.plan,
      patient.personality_code,
      row_number() OVER (
        PARTITION BY content_version.publication_id
        ORDER BY content_version.publish_at DESC, content_version.version DESC
      ) AS visibility_rank
    FROM patient
    JOIN public.content_versions content_version
      ON content_version.locale = patient.locale
      AND content_version.state = 'approved'
      AND content_version.publish_at IS NOT NULL
      AND content_version.publish_at <= p_now
      AND content_version.publication_id = p_publication_id
    JOIN public.content_publications publication
      ON publication.id = content_version.publication_id
      AND publication.archived_at IS NULL
  ),
  eligible AS (
    SELECT ranked_visible.version_id, ranked_visible.version
    FROM ranked_visible
    WHERE ranked_visible.visibility_rank = 1
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.protocol = ranked_visible.current_protocol
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.plan = ranked_visible.plan
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.personality_code = ranked_visible.personality_code
            AND target.personality_code <> 'balanced'
        )
      )
  )
  SELECT eligible.version_id, eligible.version
  INTO v_version_id, v_visible_version
  FROM eligible;

  IF v_version_id IS NULL THEN
    RAISE EXCEPTION 'content_not_visible' USING ERRCODE = 'P0002';
  END IF;
  IF p_version <> v_visible_version THEN
    RAISE EXCEPTION 'content_version_changed' USING ERRCODE = '40001';
  END IF;

  INSERT INTO private.content_mutation_receipts (
    user_id,
    event_key_hash,
    operation,
    publication_id,
    content_version,
    event_type,
    desired_saved,
    origin,
    response
  ) VALUES (
    p_user_id,
    v_key_hash,
    'record_event',
    p_publication_id,
    p_version,
    p_event_type,
    NULL,
    p_origin,
    '{}'::jsonb
  )
  ON CONFLICT (user_id, event_key_hash) DO NOTHING
  RETURNING true INTO v_receipt_inserted;

  IF NOT COALESCE(v_receipt_inserted, false) THEN
    SELECT
      receipt.operation,
      receipt.publication_id,
      receipt.content_version,
      receipt.event_type,
      receipt.desired_saved,
      receipt.origin,
      receipt.response
    INTO
      v_existing_operation,
      v_existing_publication_id,
      v_existing_version,
      v_existing_event_type,
      v_existing_desired_saved,
      v_existing_origin,
      v_existing_response
    FROM private.content_mutation_receipts receipt
    WHERE receipt.user_id = p_user_id
      AND receipt.event_key_hash = v_key_hash;

    IF NOT FOUND
      OR v_existing_operation IS DISTINCT FROM 'record_event'
      OR v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS DISTINCT FROM p_event_type
      OR v_existing_desired_saved IS NOT NULL
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;
    RETURN v_existing_response;
  END IF;

  SELECT
    event.publication_id,
    content_version.version,
    event.event_type,
    event.origin
  INTO
    v_existing_publication_id,
    v_existing_version,
    v_existing_event_type,
    v_existing_origin
  FROM public.content_events event
  JOIN public.content_versions content_version
    ON content_version.id = event.content_version_id
  WHERE event.user_id = p_user_id
    AND event.event_key_hash = v_key_hash;

  IF FOUND THEN
    IF v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS DISTINCT FROM p_event_type
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;

    SELECT
      COALESCE(state.saved_at IS NOT NULL, false),
      COALESCE(
        state.completed_at IS NOT NULL
          AND state.completed_version_id = v_version_id,
        false
      )
    INTO v_saved, v_completed
    FROM (SELECT 1) singleton
    LEFT JOIN public.content_user_state state
      ON state.user_id = p_user_id
      AND state.publication_id = p_publication_id;

    v_response := jsonb_build_object(
      'publicationId', p_publication_id,
      'version', p_version,
      'saved', v_saved,
      'completed', v_completed,
      'changed', false,
      'replayed', true
    );
    UPDATE private.content_mutation_receipts
    SET response = v_response
    WHERE user_id = p_user_id
      AND event_key_hash = v_key_hash;
    RETURN v_response;
  END IF;

  INSERT INTO public.content_events (
    user_id,
    publication_id,
    content_version_id,
    event_type,
    origin,
    event_key_hash,
    occurred_at
  ) VALUES (
    p_user_id,
    p_publication_id,
    v_version_id,
    p_event_type,
    p_origin,
    v_key_hash,
    p_now
  )
  ON CONFLICT (user_id, event_key_hash) DO NOTHING
  RETURNING true INTO v_event_inserted;

  IF NOT COALESCE(v_event_inserted, false) THEN
    SELECT
      event.publication_id,
      content_version.version,
      event.event_type,
      event.origin
    INTO
      v_existing_publication_id,
      v_existing_version,
      v_existing_event_type,
      v_existing_origin
    FROM public.content_events event
    JOIN public.content_versions content_version
      ON content_version.id = event.content_version_id
    WHERE event.user_id = p_user_id
      AND event.event_key_hash = v_key_hash;

    IF NOT FOUND
      OR v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS DISTINCT FROM p_event_type
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;

    SELECT
      COALESCE(state.saved_at IS NOT NULL, false),
      COALESCE(
        state.completed_at IS NOT NULL
          AND state.completed_version_id = v_version_id,
        false
      )
    INTO v_saved, v_completed
    FROM (SELECT 1) singleton
    LEFT JOIN public.content_user_state state
      ON state.user_id = p_user_id
      AND state.publication_id = p_publication_id;

    v_response := jsonb_build_object(
      'publicationId', p_publication_id,
      'version', p_version,
      'saved', v_saved,
      'completed', v_completed,
      'changed', false,
      'replayed', true
    );
    UPDATE private.content_mutation_receipts
    SET response = v_response
    WHERE user_id = p_user_id
      AND event_key_hash = v_key_hash;
    RETURN v_response;
  END IF;

  IF p_event_type = 'opened' THEN
    INSERT INTO public.content_user_state (
      user_id,
      publication_id,
      first_opened_at,
      last_opened_at,
      last_opened_version_id,
      last_origin
    ) VALUES (
      p_user_id,
      p_publication_id,
      p_now,
      p_now,
      v_version_id,
      p_origin
    )
    ON CONFLICT (user_id, publication_id) DO UPDATE
    SET first_opened_at = COALESCE(
          least(public.content_user_state.first_opened_at, EXCLUDED.first_opened_at),
          EXCLUDED.first_opened_at
        ),
        last_opened_at = greatest(
          public.content_user_state.last_opened_at,
          EXCLUDED.last_opened_at
        ),
        last_opened_version_id = EXCLUDED.last_opened_version_id,
        last_origin = EXCLUDED.last_origin;
  ELSIF p_event_type = 'completed' THEN
    INSERT INTO public.content_user_state (
      user_id,
      publication_id,
      completed_at,
      completed_version_id,
      last_origin
    ) VALUES (
      p_user_id,
      p_publication_id,
      p_now,
      v_version_id,
      p_origin
    )
    ON CONFLICT (user_id, publication_id) DO UPDATE
    SET completed_at = EXCLUDED.completed_at,
        completed_version_id = EXCLUDED.completed_version_id,
        last_origin = EXCLUDED.last_origin;
  END IF;

  SELECT
    COALESCE(state.saved_at IS NOT NULL, false),
    COALESCE(
      state.completed_at IS NOT NULL
        AND state.completed_version_id = v_version_id,
      false
    )
  INTO v_saved, v_completed
  FROM (SELECT 1) singleton
  LEFT JOIN public.content_user_state state
    ON state.user_id = p_user_id
    AND state.publication_id = p_publication_id;

  v_response := jsonb_build_object(
    'publicationId', p_publication_id,
    'version', p_version,
    'saved', v_saved,
    'completed', v_completed,
    'changed', true,
    'replayed', false
  );
  UPDATE private.content_mutation_receipts
  SET response = v_response
  WHERE user_id = p_user_id
    AND event_key_hash = v_key_hash;
  RETURN v_response;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_mobile_content_saved(
  p_user_id uuid,
  p_publication_id uuid,
  p_version integer,
  p_saved boolean,
  p_origin text,
  p_event_key text,
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_version_id uuid;
  v_visible_version integer;
  v_key text;
  v_key_hash text;
  v_event_type text;
  v_existing_operation text;
  v_existing_publication_id uuid;
  v_existing_version integer;
  v_existing_event_type text;
  v_existing_desired_saved boolean;
  v_existing_origin text;
  v_existing_response jsonb;
  v_receipt_inserted boolean := false;
  v_event_inserted boolean := false;
  v_current_saved boolean := false;
  v_completed boolean := false;
  v_response jsonb;
BEGIN
  IF p_user_id IS NULL OR p_publication_id IS NULL THEN
    RAISE EXCEPTION 'invalid_content_identity' USING ERRCODE = '22023';
  END IF;
  IF p_version IS NULL OR p_version <= 0 OR p_saved IS NULL THEN
    RAISE EXCEPTION 'invalid_content_save' USING ERRCODE = '22023';
  END IF;
  IF p_origin IS NULL OR p_origin NOT IN ('today', 'library', 'push') THEN
    RAISE EXCEPTION 'invalid_content_origin' USING ERRCODE = '22023';
  END IF;
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_content_time' USING ERRCODE = '22023';
  END IF;

  v_key := btrim(p_event_key);
  IF v_key IS NULL OR char_length(v_key) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'invalid_content_event_key' USING ERRCODE = '22023';
  END IF;
  v_key_hash := encode(
    extensions.digest(convert_to(v_key, 'UTF8'), 'sha256'),
    'hex'
  );
  v_event_type := CASE WHEN p_saved THEN 'saved' ELSE 'unsaved' END;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_publication_id::text, 0)
  );

  PERFORM content_version.id
  FROM public.content_versions content_version
  WHERE content_version.publication_id = p_publication_id
    AND content_version.locale = (
      SELECT domain_user.locale
      FROM public.users domain_user
      WHERE domain_user.id = p_user_id
        AND domain_user.locale IN ('pt-BR', 'en-US')
    )
    AND content_version.state = 'approved'
    AND content_version.publish_at IS NOT NULL
    AND content_version.publish_at <= p_now
  ORDER BY content_version.publish_at DESC, content_version.version DESC
  LIMIT 1
  FOR KEY SHARE OF content_version;

  PERFORM 1
  FROM public.content_publications publication
  WHERE publication.id = p_publication_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'content_not_visible' USING ERRCODE = 'P0002';
  END IF;

  SELECT
    receipt.operation,
    receipt.publication_id,
    receipt.content_version,
    receipt.event_type,
    receipt.desired_saved,
    receipt.origin,
    receipt.response
  INTO
    v_existing_operation,
    v_existing_publication_id,
    v_existing_version,
    v_existing_event_type,
    v_existing_desired_saved,
    v_existing_origin,
    v_existing_response
  FROM private.content_mutation_receipts receipt
  WHERE receipt.user_id = p_user_id
    AND receipt.event_key_hash = v_key_hash;

  IF FOUND THEN
    IF v_existing_operation IS DISTINCT FROM 'set_saved'
      OR v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS NOT NULL
      OR v_existing_desired_saved IS DISTINCT FROM p_saved
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;
    RETURN v_existing_response;
  END IF;

  WITH patient AS (
    SELECT
      domain_user.locale,
      profile.current_protocol,
      preference.personality_code,
      (
        SELECT subscription.plan
        FROM public.subscriptions subscription
        WHERE subscription.user_id = domain_user.id
          AND subscription.status IN ('active', 'trial')
          AND subscription.current_period_end IS NOT NULL
          AND subscription.current_period_end > p_now
          AND (
            subscription.status <> 'trial'
            OR (
              subscription.trial_ends_at IS NOT NULL
              AND subscription.trial_ends_at > p_now
            )
          )
        ORDER BY
          CASE
            WHEN subscription.status = 'trial' THEN least(
              subscription.current_period_end,
              subscription.trial_ends_at
            )
            ELSE subscription.current_period_end
          END DESC,
          subscription.updated_at DESC,
          subscription.created_at DESC,
          subscription.id DESC
        LIMIT 1
      ) AS plan
    FROM public.users domain_user
    LEFT JOIN public.user_profiles profile
      ON profile.user_id = domain_user.id
    LEFT JOIN public.user_coach_preferences preference
      ON preference.user_id = domain_user.id
      AND preference.personality_code <> 'balanced'
    WHERE domain_user.id = p_user_id
      AND domain_user.locale IN ('pt-BR', 'en-US')
  ),
  ranked_visible AS (
    SELECT
      content_version.id AS version_id,
      content_version.version,
      patient.current_protocol,
      patient.plan,
      patient.personality_code,
      row_number() OVER (
        PARTITION BY content_version.publication_id
        ORDER BY content_version.publish_at DESC, content_version.version DESC
      ) AS visibility_rank
    FROM patient
    JOIN public.content_versions content_version
      ON content_version.locale = patient.locale
      AND content_version.state = 'approved'
      AND content_version.publish_at IS NOT NULL
      AND content_version.publish_at <= p_now
      AND content_version.publication_id = p_publication_id
    JOIN public.content_publications publication
      ON publication.id = content_version.publication_id
      AND publication.archived_at IS NULL
  ),
  eligible AS (
    SELECT ranked_visible.version_id, ranked_visible.version
    FROM ranked_visible
    WHERE ranked_visible.visibility_rank = 1
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_protocols target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.protocol = ranked_visible.current_protocol
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_plans target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.plan = ranked_visible.plan
        )
      )
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
        )
        OR EXISTS (
          SELECT 1
          FROM public.content_version_target_personalities target
          WHERE target.content_version_id = ranked_visible.version_id
            AND target.personality_code = ranked_visible.personality_code
            AND target.personality_code <> 'balanced'
        )
      )
  )
  SELECT eligible.version_id, eligible.version
  INTO v_version_id, v_visible_version
  FROM eligible;

  IF v_version_id IS NULL THEN
    RAISE EXCEPTION 'content_not_visible' USING ERRCODE = 'P0002';
  END IF;
  IF p_version <> v_visible_version THEN
    RAISE EXCEPTION 'content_version_changed' USING ERRCODE = '40001';
  END IF;

  INSERT INTO private.content_mutation_receipts (
    user_id,
    event_key_hash,
    operation,
    publication_id,
    content_version,
    event_type,
    desired_saved,
    origin,
    response
  ) VALUES (
    p_user_id,
    v_key_hash,
    'set_saved',
    p_publication_id,
    p_version,
    NULL,
    p_saved,
    p_origin,
    '{}'::jsonb
  )
  ON CONFLICT (user_id, event_key_hash) DO NOTHING
  RETURNING true INTO v_receipt_inserted;

  IF NOT COALESCE(v_receipt_inserted, false) THEN
    SELECT
      receipt.operation,
      receipt.publication_id,
      receipt.content_version,
      receipt.event_type,
      receipt.desired_saved,
      receipt.origin,
      receipt.response
    INTO
      v_existing_operation,
      v_existing_publication_id,
      v_existing_version,
      v_existing_event_type,
      v_existing_desired_saved,
      v_existing_origin,
      v_existing_response
    FROM private.content_mutation_receipts receipt
    WHERE receipt.user_id = p_user_id
      AND receipt.event_key_hash = v_key_hash;

    IF NOT FOUND
      OR v_existing_operation IS DISTINCT FROM 'set_saved'
      OR v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS NOT NULL
      OR v_existing_desired_saved IS DISTINCT FROM p_saved
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;
    RETURN v_existing_response;
  END IF;

  SELECT
    event.publication_id,
    content_version.version,
    event.event_type,
    event.origin
  INTO
    v_existing_publication_id,
    v_existing_version,
    v_existing_event_type,
    v_existing_origin
  FROM public.content_events event
  JOIN public.content_versions content_version
    ON content_version.id = event.content_version_id
  WHERE event.user_id = p_user_id
    AND event.event_key_hash = v_key_hash;

  IF FOUND THEN
    IF v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS DISTINCT FROM v_event_type
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;

    SELECT
      COALESCE(state.saved_at IS NOT NULL, false),
      COALESCE(
        state.completed_at IS NOT NULL
          AND state.completed_version_id = v_version_id,
        false
      )
    INTO v_current_saved, v_completed
    FROM (SELECT 1) singleton
    LEFT JOIN public.content_user_state state
      ON state.user_id = p_user_id
      AND state.publication_id = p_publication_id;

    v_response := jsonb_build_object(
      'publicationId', p_publication_id,
      'version', p_version,
      'saved', v_current_saved,
      'completed', v_completed,
      'changed', false,
      'replayed', true
    );
    UPDATE private.content_mutation_receipts
    SET response = v_response
    WHERE user_id = p_user_id
      AND event_key_hash = v_key_hash;
    RETURN v_response;
  END IF;

  SELECT COALESCE(state.saved_at IS NOT NULL, false)
  INTO v_current_saved
  FROM (SELECT 1) singleton
  LEFT JOIN public.content_user_state state
    ON state.user_id = p_user_id
    AND state.publication_id = p_publication_id;

  IF v_current_saved = p_saved THEN
    SELECT COALESCE(
      state.completed_at IS NOT NULL
        AND state.completed_version_id = v_version_id,
      false
    )
    INTO v_completed
    FROM (SELECT 1) singleton
    LEFT JOIN public.content_user_state state
      ON state.user_id = p_user_id
      AND state.publication_id = p_publication_id;

    v_response := jsonb_build_object(
      'publicationId', p_publication_id,
      'version', p_version,
      'saved', p_saved,
      'completed', v_completed,
      'changed', false,
      'replayed', false
    );
    UPDATE private.content_mutation_receipts
    SET response = v_response
    WHERE user_id = p_user_id
      AND event_key_hash = v_key_hash;
    RETURN v_response;
  END IF;

  INSERT INTO public.content_events (
    user_id,
    publication_id,
    content_version_id,
    event_type,
    origin,
    event_key_hash,
    occurred_at
  ) VALUES (
    p_user_id,
    p_publication_id,
    v_version_id,
    v_event_type,
    p_origin,
    v_key_hash,
    p_now
  )
  ON CONFLICT (user_id, event_key_hash) DO NOTHING
  RETURNING true INTO v_event_inserted;

  IF NOT COALESCE(v_event_inserted, false) THEN
    SELECT
      event.publication_id,
      content_version.version,
      event.event_type,
      event.origin
    INTO
      v_existing_publication_id,
      v_existing_version,
      v_existing_event_type,
      v_existing_origin
    FROM public.content_events event
    JOIN public.content_versions content_version
      ON content_version.id = event.content_version_id
    WHERE event.user_id = p_user_id
      AND event.event_key_hash = v_key_hash;

    IF NOT FOUND
      OR v_existing_publication_id IS DISTINCT FROM p_publication_id
      OR v_existing_version IS DISTINCT FROM p_version
      OR v_existing_event_type IS DISTINCT FROM v_event_type
      OR v_existing_origin IS DISTINCT FROM p_origin THEN
      RAISE EXCEPTION 'content_event_key_conflict' USING ERRCODE = '22023';
    END IF;

    SELECT
      COALESCE(state.saved_at IS NOT NULL, false),
      COALESCE(
        state.completed_at IS NOT NULL
          AND state.completed_version_id = v_version_id,
        false
      )
    INTO v_current_saved, v_completed
    FROM (SELECT 1) singleton
    LEFT JOIN public.content_user_state state
      ON state.user_id = p_user_id
      AND state.publication_id = p_publication_id;

    v_response := jsonb_build_object(
      'publicationId', p_publication_id,
      'version', p_version,
      'saved', v_current_saved,
      'completed', v_completed,
      'changed', false,
      'replayed', true
    );
    UPDATE private.content_mutation_receipts
    SET response = v_response
    WHERE user_id = p_user_id
      AND event_key_hash = v_key_hash;
    RETURN v_response;
  END IF;

  IF p_saved THEN
    INSERT INTO public.content_user_state (
      user_id,
      publication_id,
      saved_at,
      last_origin
    ) VALUES (
      p_user_id,
      p_publication_id,
      p_now,
      p_origin
    )
    ON CONFLICT (user_id, publication_id) DO UPDATE
    SET saved_at = EXCLUDED.saved_at,
        last_origin = EXCLUDED.last_origin;
  ELSE
    UPDATE public.content_user_state
    SET saved_at = NULL,
        last_origin = p_origin
    WHERE user_id = p_user_id
      AND publication_id = p_publication_id;
  END IF;

  SELECT COALESCE(
    state.completed_at IS NOT NULL
      AND state.completed_version_id = v_version_id,
    false
  )
  INTO v_completed
  FROM (SELECT 1) singleton
  LEFT JOIN public.content_user_state state
    ON state.user_id = p_user_id
    AND state.publication_id = p_publication_id;

  v_response := jsonb_build_object(
    'publicationId', p_publication_id,
    'version', p_version,
    'saved', p_saved,
    'completed', v_completed,
    'changed', true,
    'replayed', false
  );
  UPDATE private.content_mutation_receipts
  SET response = v_response
  WHERE user_id = p_user_id
    AND event_key_hash = v_key_hash;
  RETURN v_response;
END;
$$;

REVOKE ALL ON FUNCTION public.list_mobile_content(
  uuid, text, text, integer, timestamptz, uuid, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_mobile_content(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_mobile_content_event(
  uuid, uuid, integer, text, text, text, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_mobile_content_saved(
  uuid, uuid, integer, boolean, text, text, timestamptz
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.list_mobile_content(
  uuid, text, text, integer, timestamptz, uuid, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_content(uuid, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.record_mobile_content_event(
  uuid, uuid, integer, text, text, text, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_mobile_content_saved(
  uuid, uuid, integer, boolean, text, text, timestamptz
) TO service_role;

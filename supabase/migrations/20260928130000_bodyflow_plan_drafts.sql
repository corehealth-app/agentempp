-- M2 — plan drafts: a training or nutrition plan proposed by Flow or imported
-- from a document only becomes the patient's plan after the patient reviews
-- and confirms it in the app.
--
-- Nothing here confirms by itself: the only path from a draft to a plan is
-- public.confirm_plan_draft_atomic, executable by the trusted backend alone,
-- bound to p_user_id, to the reviewed payload_version and to the plan the
-- draft was written against. No target formula changes and no existing plan
-- or prescription is rewritten or deleted.

-- ---------------------------------------------------------------------------
-- 1. Ownership anchors and idempotency for prescriptions
-- ---------------------------------------------------------------------------

-- Composite targets so a draft can only point at media and messages of its
-- own patient (the foreign keys below carry user_id).
--
-- Both are plain unique indexes created only when missing, so on a database
-- with many rows they can be built beforehand, one statement at a time and
-- outside a transaction, with CREATE UNIQUE INDEX CONCURRENTLY under the
-- same names; this file then finds them in place and takes no long lock.
CREATE UNIQUE INDEX IF NOT EXISTS media_assets_id_user_unique
  ON public.media_assets (id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS messages_id_user_unique
  ON public.messages (id, user_id);

ALTER TABLE public.prescriptions
  ADD COLUMN IF NOT EXISTS source_request_key text;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_prescriptions_request
  ON public.prescriptions (user_id, source_request_key)
  WHERE source_request_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. plan_drafts
-- ---------------------------------------------------------------------------

CREATE TABLE public.plan_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  domain text NOT NULL,
  origin text NOT NULL,
  status text NOT NULL,
  source_media_asset_id uuid,
  source_message_id uuid,
  -- What the patient reviews and, once complete, confirms.
  payload jsonb,
  payload_version integer NOT NULL DEFAULT 1,
  -- What the extraction read, kept as it came (nullable fields, unknown
  -- parts preserved). Never confirmed directly.
  extraction_payload jsonb,
  uncertain_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  unrecognized_segments jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- The plan in force when the draft was written; a different one at
  -- confirmation means the patient reviewed against something else.
  base_active_plan_id uuid,
  base_latest_prescription_id uuid,
  -- Method, model and prompt version. Never the document's text.
  origin_detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  failure_code text,
  request_key text NOT NULL,
  confirmation_key text,
  confirmed_plan_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 days'),
  resolved_at timestamptz,
  CONSTRAINT plan_drafts_request_unique UNIQUE (user_id, request_key),
  CONSTRAINT plan_drafts_domain_check CHECK (domain IN ('training', 'nutrition')),
  CONSTRAINT plan_drafts_origin_check CHECK (
    origin IN ('flow_generated', 'imported_photo', 'imported_pdf')
  ),
  CONSTRAINT plan_drafts_status_check CHECK (
    status IN (
      'extracting', 'generating', 'needs_completion', 'ready_for_review',
      'confirmed', 'discarded', 'expired', 'failed'
    )
  ),
  CONSTRAINT plan_drafts_source_check CHECK (
    (origin = 'flow_generated' AND source_media_asset_id IS NULL)
    OR (
      origin IN ('imported_photo', 'imported_pdf')
      AND source_media_asset_id IS NOT NULL
      AND source_message_id IS NULL
    )
  ),
  CONSTRAINT plan_drafts_payload_check CHECK (
    (payload IS NULL OR jsonb_typeof(payload) = 'object')
    AND (extraction_payload IS NULL OR jsonb_typeof(extraction_payload) = 'object')
    AND jsonb_typeof(uncertain_fields) = 'array'
    AND jsonb_typeof(unrecognized_segments) = 'array'
    AND jsonb_typeof(origin_detail) = 'object'
    AND payload_version >= 1
    AND pg_column_size(payload) <= 262144
    AND pg_column_size(extraction_payload) <= 262144
    AND pg_column_size(uncertain_fields) <= 65536
    AND pg_column_size(unrecognized_segments) <= 65536
    AND pg_column_size(origin_detail) <= 4096
  ),
  CONSTRAINT plan_drafts_reviewable_payload_check CHECK (
    status NOT IN ('needs_completion', 'ready_for_review', 'confirmed')
    OR payload IS NOT NULL
  ),
  CONSTRAINT plan_drafts_failure_check CHECK (
    (status = 'failed' AND failure_code IS NOT NULL AND failure_code ~ '^[a-z][a-z0-9_]{1,63}$')
    OR (status <> 'failed' AND failure_code IS NULL)
  ),
  CONSTRAINT plan_drafts_confirmed_check CHECK (
    (status = 'confirmed' AND confirmed_plan_id IS NOT NULL AND confirmation_key IS NOT NULL)
    OR (status <> 'confirmed' AND confirmed_plan_id IS NULL)
  ),
  CONSTRAINT plan_drafts_resolved_check CHECK (
    (status IN ('confirmed', 'discarded', 'expired', 'failed')) = (resolved_at IS NOT NULL)
  ),
  CONSTRAINT plan_drafts_key_check CHECK (
    request_key ~ '^[A-Za-z0-9._:/-]{8,200}$'
    AND (confirmation_key IS NULL OR confirmation_key ~ '^[A-Za-z0-9._:-]{8,128}$')
  ),
  CONSTRAINT plan_drafts_media_owner_fk
    FOREIGN KEY (source_media_asset_id, user_id)
    REFERENCES public.media_assets (id, user_id) ON DELETE RESTRICT,
  -- A deleted message (conversation reset) only takes the anchor away: the
  -- draft, and the record of what was confirmed, stay.
  CONSTRAINT plan_drafts_message_owner_fk
    FOREIGN KEY (source_message_id, user_id)
    REFERENCES public.messages (id, user_id) ON DELETE SET NULL (source_message_id)
);

COMMENT ON TABLE public.plan_drafts IS
  'Training/nutrition plans awaiting the patient''s review. A draft becomes a plan only through confirm_plan_draft_atomic.';

CREATE INDEX plan_drafts_user_open_idx
  ON public.plan_drafts (user_id, created_at DESC)
  WHERE status IN ('extracting', 'generating', 'needs_completion', 'ready_for_review');
-- A document is imported once: one draft per document, unless the earlier
-- one failed, expired or was discarded.
CREATE UNIQUE INDEX plan_drafts_one_per_document
  ON public.plan_drafts (source_media_asset_id)
  WHERE source_media_asset_id IS NOT NULL
    AND status IN ('extracting', 'needs_completion', 'ready_for_review', 'confirmed');
CREATE INDEX plan_drafts_media_idx
  ON public.plan_drafts (source_media_asset_id)
  WHERE source_media_asset_id IS NOT NULL;
CREATE INDEX plan_drafts_message_idx
  ON public.plan_drafts (source_message_id)
  WHERE source_message_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.enforce_plan_draft_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  -- The only change a deleted message causes: its anchor is cleared, in any
  -- state of the draft, and nothing else moves.
  IF OLD.source_message_id IS NOT NULL
    AND NEW.source_message_id IS NULL
    AND (to_jsonb(NEW) - 'source_message_id') = (to_jsonb(OLD) - 'source_message_id') THEN
    RETURN NEW;
  END IF;

  IF NEW.id <> OLD.id
    OR NEW.user_id <> OLD.user_id
    OR NEW.domain <> OLD.domain
    OR NEW.origin <> OLD.origin
    OR NEW.request_key <> OLD.request_key
    OR NEW.source_media_asset_id IS DISTINCT FROM OLD.source_media_asset_id
    OR NEW.source_message_id IS DISTINCT FROM OLD.source_message_id
    OR NEW.base_active_plan_id IS DISTINCT FROM OLD.base_active_plan_id
    OR NEW.base_latest_prescription_id IS DISTINCT FROM OLD.base_latest_prescription_id
    OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'plan draft identity is immutable' USING ERRCODE = '23514';
  END IF;

  -- A resolved draft is a record: nothing in it changes again.
  IF OLD.status IN ('confirmed', 'discarded', 'expired', 'failed') THEN
    RAISE EXCEPTION 'plan draft is resolved' USING ERRCODE = '23514';
  END IF;

  IF NEW.status <> OLD.status AND NOT (
    (
      OLD.status IN ('extracting', 'generating')
      AND NEW.status IN ('needs_completion', 'ready_for_review', 'failed', 'discarded', 'expired')
    )
    OR (
      OLD.status IN ('needs_completion', 'ready_for_review')
      AND NEW.status IN ('needs_completion', 'ready_for_review', 'discarded', 'expired')
    )
    OR (OLD.status = 'ready_for_review' AND NEW.status = 'confirmed')
  ) THEN
    RAISE EXCEPTION 'invalid plan draft status transition: % -> %', OLD.status, NEW.status
      USING ERRCODE = '23514';
  END IF;

  IF NEW.payload_version < OLD.payload_version THEN
    RAISE EXCEPTION 'plan draft version cannot go back' USING ERRCODE = '23514';
  END IF;

  IF NEW.payload IS DISTINCT FROM OLD.payload
    AND OLD.payload IS NOT NULL
    AND NEW.payload_version <= OLD.payload_version THEN
    RAISE EXCEPTION 'plan draft payload changed without a new version' USING ERRCODE = '23514';
  END IF;

  -- A draft is marked confirmed only by the confirmation itself, which
  -- announces the draft it is confirming for the length of its transaction.
  IF NEW.status = 'confirmed'
    AND OLD.status <> 'confirmed'
    AND current_setting('bodyflow.confirming_plan_draft', true) IS DISTINCT FROM NEW.id::text THEN
    RAISE EXCEPTION 'plan draft can only be confirmed by its confirmation'
      USING ERRCODE = '23514';
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_plan_draft_transition
  BEFORE UPDATE ON public.plan_drafts
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_plan_draft_transition();

ALTER TABLE public.plan_drafts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.plan_drafts FROM PUBLIC, anon, authenticated;
-- The patient may see that a draft exists and where it stands. Its content
-- is served by the backend, which is the only writer.
GRANT SELECT (
  id, user_id, domain, origin, status, payload_version,
  created_at, updated_at, expires_at, resolved_at
) ON TABLE public.plan_drafts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.plan_drafts TO service_role;

CREATE POLICY plan_drafts_patient_own_read
  ON public.plan_drafts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.users domain_user
      WHERE domain_user.id = plan_drafts.user_id
        AND domain_user.auth_user_id = (SELECT auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- 3. One way to replace the active training plan
-- ---------------------------------------------------------------------------

-- Caller holds the '<user>:training-plan' lock. Used by the WhatsApp save
-- (which turns the daily reminders on) and by the app confirmation (which
-- does not: a plan confirmed in the app never starts a WhatsApp delivery).
CREATE OR REPLACE FUNCTION private.replace_active_training_plan(
  p_user_id uuid,
  p_plan_type text,
  p_days_per_week integer,
  p_equipment_summary text,
  p_weekly_schedule jsonb,
  p_generated_by text,
  p_generated_at timestamptz,
  p_valid_until timestamptz,
  p_version integer,
  p_notes text,
  p_request_key text,
  p_enable_reminders boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_plan_id uuid;
  v_request_key text := NULLIF(btrim(p_request_key), '');
BEGIN
  IF p_user_id IS NULL
    OR p_plan_type IS NULL
    OR p_plan_type NOT IN ('split', 'full_body', 'custom')
    OR p_days_per_week IS NULL OR p_days_per_week < 1 OR p_days_per_week > 7
    OR jsonb_typeof(p_weekly_schedule) <> 'array'
    OR jsonb_array_length(p_weekly_schedule) < 1
    OR jsonb_array_length(p_weekly_schedule) > 7
    OR p_version IS NULL OR p_version < 1
    OR p_enable_reminders IS NULL THEN
    RAISE EXCEPTION 'invalid training plan payload';
  END IF;

  IF v_request_key IS NOT NULL THEN
    SELECT id
    INTO v_plan_id
    FROM public.training_plans
    WHERE user_id = p_user_id AND source_request_key = v_request_key
    LIMIT 1;

    IF v_plan_id IS NOT NULL THEN
      RETURN jsonb_build_object('plan_id', v_plan_id, 'inserted', false);
    END IF;
  END IF;

  UPDATE public.training_plans
  SET active = false
  WHERE user_id = p_user_id AND active = true;

  INSERT INTO public.training_plans (
    user_id, plan_type, days_per_week, equipment_summary, weekly_schedule,
    generated_by, generated_at, valid_until, active, version, notes,
    source_request_key
  ) VALUES (
    p_user_id,
    p_plan_type,
    p_days_per_week,
    p_equipment_summary,
    p_weekly_schedule,
    COALESCE(NULLIF(btrim(p_generated_by), ''), 'agent'),
    COALESCE(p_generated_at, now()),
    p_valid_until,
    true,
    p_version,
    p_notes,
    v_request_key
  )
  RETURNING id INTO v_plan_id;

  IF p_enable_reminders THEN
    UPDATE public.users
    SET
      metadata = COALESCE(metadata, '{}'::jsonb) || '{"training_reminders": true}'::jsonb,
      updated_at = now()
    WHERE id = p_user_id;
  ELSE
    PERFORM 1 FROM public.users WHERE id = p_user_id;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'training plan user not found';
  END IF;

  RETURN jsonb_build_object('plan_id', v_plan_id, 'inserted', true);
END;
$$;

-- Same signature, same result and same effects as before; the body now goes
-- through the shared function.
CREATE OR REPLACE FUNCTION public.save_training_plan_atomic(
  p_user_id uuid,
  p_plan_type text,
  p_days_per_week integer,
  p_equipment_summary text,
  p_weekly_schedule jsonb,
  p_generated_by text,
  p_generated_at timestamptz,
  p_valid_until timestamptz,
  p_version integer,
  p_notes text,
  p_request_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, private, pg_temp
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid training plan payload';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':training-plan', 0));

  RETURN private.replace_active_training_plan(
    p_user_id, p_plan_type, p_days_per_week, p_equipment_summary,
    p_weekly_schedule, p_generated_by, p_generated_at, p_valid_until,
    p_version, p_notes, p_request_key, true
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Draft RPCs (trusted backend only, always bound to p_user_id)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.plan_draft_dto(p_draft public.plan_drafts)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'id', p_draft.id,
    'domain', p_draft.domain,
    'origin', p_draft.origin,
    'status', CASE
      WHEN p_draft.status IN ('extracting', 'generating', 'needs_completion', 'ready_for_review')
        AND p_draft.expires_at <= clock_timestamp() THEN 'expired'
      ELSE p_draft.status
    END,
    'payload_version', p_draft.payload_version,
    'confirmed_plan_id', p_draft.confirmed_plan_id
  );
$$;

CREATE OR REPLACE FUNCTION public.create_plan_draft_atomic(
  p_user_id uuid,
  p_domain text,
  p_origin text,
  p_status text,
  p_payload jsonb,
  p_extraction_payload jsonb,
  p_uncertain_fields jsonb,
  p_unrecognized_segments jsonb,
  p_source_media_asset_id uuid,
  p_source_message_id uuid,
  p_origin_detail jsonb,
  p_request_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_draft public.plan_drafts;
  v_active boolean;
  v_open integer;
  v_base_plan uuid;
  v_base_prescription uuid;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_domain IS NULL OR p_domain NOT IN ('training', 'nutrition')
    OR p_origin IS NULL
    OR p_origin NOT IN ('flow_generated', 'imported_photo', 'imported_pdf')
    OR p_status IS NULL
    OR p_status NOT IN ('extracting', 'generating', 'needs_completion', 'ready_for_review')
    OR p_request_key IS NULL
    OR p_request_key !~ '^[A-Za-z0-9._:/-]{8,200}$'
    -- Content arrives with the outcome of the work, not before it.
    OR (p_status IN ('extracting', 'generating') AND p_payload IS NOT NULL)
    OR (p_status IN ('needs_completion', 'ready_for_review')
        AND (p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object')) THEN
    RAISE EXCEPTION 'invalid plan draft' USING ERRCODE = '22023';
  END IF;

  SELECT true INTO v_active
  FROM public.users
  WHERE id = p_user_id AND status = 'active';
  IF v_active IS NOT TRUE THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':plan-drafts', 0));

  SELECT * INTO v_draft
  FROM public.plan_drafts
  WHERE user_id = p_user_id AND request_key = p_request_key;
  IF FOUND THEN
    IF v_draft.domain <> p_domain OR v_draft.origin <> p_origin THEN
      RAISE EXCEPTION 'plan_draft_request_conflict' USING ERRCODE = '23505';
    END IF;
    RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('inserted', false);
  END IF;

  -- The sources must belong to the same patient (the foreign keys say so
  -- again); another patient's media or message is simply not found.
  IF p_source_media_asset_id IS NOT NULL THEN
    PERFORM 1
    FROM public.media_assets
    WHERE id = p_source_media_asset_id
      AND user_id = p_user_id
      AND status <> 'deleted';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'plan_draft_source_not_found' USING ERRCODE = 'PD404';
    END IF;
  END IF;
  IF p_source_message_id IS NOT NULL THEN
    PERFORM 1
    FROM public.messages
    WHERE id = p_source_message_id AND user_id = p_user_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'plan_draft_source_not_found' USING ERRCODE = 'PD404';
    END IF;
  END IF;

  SELECT count(*) INTO v_open
  FROM public.plan_drafts
  WHERE user_id = p_user_id
    AND status IN ('extracting', 'generating', 'needs_completion', 'ready_for_review')
    AND expires_at > clock_timestamp();
  IF v_open >= 20 THEN
    RAISE EXCEPTION 'plan_draft_limit_reached' USING ERRCODE = 'PD429';
  END IF;

  IF p_domain = 'training' THEN
    SELECT id INTO v_base_plan
    FROM public.training_plans
    WHERE user_id = p_user_id AND active = true;
  ELSE
    -- The latest prescription, valid or not: one that merely expires during
    -- the review is not a change of plan.
    SELECT id INTO v_base_prescription
    FROM public.prescriptions
    WHERE user_id = p_user_id
    ORDER BY generated_at DESC, id DESC
    LIMIT 1;
  END IF;

  INSERT INTO public.plan_drafts (
    user_id, domain, origin, status, source_media_asset_id, source_message_id,
    payload, extraction_payload, uncertain_fields, unrecognized_segments,
    base_active_plan_id, base_latest_prescription_id, origin_detail, request_key
  ) VALUES (
    p_user_id, p_domain, p_origin, p_status, p_source_media_asset_id,
    p_source_message_id, p_payload, p_extraction_payload,
    COALESCE(p_uncertain_fields, '[]'::jsonb),
    COALESCE(p_unrecognized_segments, '[]'::jsonb),
    v_base_plan, v_base_prescription,
    COALESCE(p_origin_detail, '{}'::jsonb), p_request_key
  )
  RETURNING * INTO v_draft;

  RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('inserted', true);
END;
$$;

-- Outcome of an extraction or generation that was started earlier: the
-- content to review, or the failure. Only a draft still in progress moves.
CREATE OR REPLACE FUNCTION public.resolve_plan_draft_work_atomic(
  p_user_id uuid,
  p_draft_id uuid,
  p_status text,
  p_payload jsonb,
  p_extraction_payload jsonb,
  p_uncertain_fields jsonb,
  p_unrecognized_segments jsonb,
  p_origin_detail jsonb,
  p_failure_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_draft public.plan_drafts;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR p_draft_id IS NULL
    OR p_status IS NULL
    OR p_status NOT IN ('needs_completion', 'ready_for_review', 'failed')
    OR (p_status = 'failed') <> (p_failure_code IS NOT NULL)
    OR (p_status <> 'failed' AND p_payload IS NULL) THEN
    RAISE EXCEPTION 'invalid plan draft outcome' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_draft
  FROM public.plan_drafts
  WHERE id = p_draft_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;

  -- Already resolved (a repeated delivery of the same work): no effect.
  IF v_draft.status NOT IN ('extracting', 'generating') THEN
    RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('applied', false);
  END IF;

  UPDATE public.plan_drafts
  SET status = p_status,
      payload = CASE WHEN p_status = 'failed' THEN NULL ELSE p_payload END,
      extraction_payload = CASE WHEN p_status = 'failed' THEN NULL ELSE p_extraction_payload END,
      uncertain_fields = COALESCE(p_uncertain_fields, '[]'::jsonb),
      unrecognized_segments = COALESCE(p_unrecognized_segments, '[]'::jsonb),
      origin_detail = COALESCE(p_origin_detail, origin_detail),
      failure_code = CASE WHEN p_status = 'failed' THEN p_failure_code END,
      resolved_at = CASE WHEN p_status = 'failed' THEN clock_timestamp() END
  WHERE id = p_draft_id
  RETURNING * INTO v_draft;

  RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('applied', true);
END;
$$;

-- The patient's edit. p_complete says whether the edited content passed the
-- strict validation of its domain (done by the backend before this call).
CREATE OR REPLACE FUNCTION public.update_plan_draft_atomic(
  p_user_id uuid,
  p_draft_id uuid,
  p_expected_version integer,
  p_payload jsonb,
  p_uncertain_fields jsonb,
  p_complete boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_draft public.plan_drafts;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR p_draft_id IS NULL
    OR p_expected_version IS NULL OR p_expected_version < 1
    OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR p_complete IS NULL THEN
    RAISE EXCEPTION 'invalid plan draft edit' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_draft
  FROM public.plan_drafts
  WHERE id = p_draft_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;
  IF v_draft.status NOT IN ('needs_completion', 'ready_for_review') THEN
    RAISE EXCEPTION 'plan_draft_not_reviewable' USING ERRCODE = 'PD422';
  END IF;
  IF v_draft.expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'plan_draft_expired' USING ERRCODE = 'PD410';
  END IF;
  IF v_draft.payload_version <> p_expected_version THEN
    RAISE EXCEPTION 'plan_draft_changed' USING ERRCODE = 'PD409';
  END IF;

  UPDATE public.plan_drafts
  SET payload = p_payload,
      payload_version = payload_version + 1,
      uncertain_fields = COALESCE(p_uncertain_fields, '[]'::jsonb),
      status = CASE WHEN p_complete THEN 'ready_for_review' ELSE 'needs_completion' END
  WHERE id = p_draft_id
  RETURNING * INTO v_draft;

  RETURN private.plan_draft_dto(v_draft);
END;
$$;

CREATE OR REPLACE FUNCTION public.discard_plan_draft_atomic(
  p_user_id uuid,
  p_draft_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_draft public.plan_drafts;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR p_draft_id IS NULL THEN
    RAISE EXCEPTION 'invalid plan draft' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_draft
  FROM public.plan_drafts
  WHERE id = p_draft_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;
  IF v_draft.status = 'discarded' THEN
    RETURN private.plan_draft_dto(v_draft);
  END IF;
  IF v_draft.status IN ('confirmed', 'expired', 'failed') THEN
    RAISE EXCEPTION 'plan_draft_not_reviewable' USING ERRCODE = 'PD422';
  END IF;

  UPDATE public.plan_drafts
  SET status = 'discarded', resolved_at = clock_timestamp()
  WHERE id = p_draft_id
  RETURNING * INTO v_draft;

  RETURN private.plan_draft_dto(v_draft);
END;
$$;

-- The only path from a draft to a plan.
CREATE OR REPLACE FUNCTION public.confirm_plan_draft_atomic(
  p_user_id uuid,
  p_draft_id uuid,
  p_payload_version integer,
  p_valid_until timestamptz,
  p_idempotency_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_draft public.plan_drafts;
  v_domain text;
  v_current_plan uuid;
  v_current_generated_by text;
  v_current_prescription uuid;
  v_active boolean;
  v_plan_id uuid;
  v_generated_by text;
  v_schedule jsonb;
  v_plan_type text;
  v_days integer;
  v_now timestamptz := clock_timestamp();
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR p_draft_id IS NULL
    OR p_payload_version IS NULL OR p_payload_version < 1
    OR p_idempotency_key IS NULL
    OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,128}$'
    OR (p_valid_until IS NOT NULL AND p_valid_until <= v_now) THEN
    RAISE EXCEPTION 'invalid plan draft confirmation' USING ERRCODE = '22023';
  END IF;

  SELECT domain INTO v_domain
  FROM public.plan_drafts
  WHERE id = p_draft_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;

  -- Same lock as every other change of the patient's plan in this domain, so
  -- two confirmations (or a confirmation and a WhatsApp save) run in turn.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_user_id::text || CASE v_domain
      WHEN 'training' THEN ':training-plan' ELSE ':nutrition-plan' END,
    0
  ));

  -- The patient's row comes before the draft's: the same order the
  -- conversation reset uses, and it makes every writer of this patient's
  -- plans that does not take the advisory lock (a direct insert of a
  -- prescription holds a key-share lock on this row) wait for its turn.
  SELECT status = 'active' INTO v_active
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;
  IF v_active IS NOT TRUE THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;

  SELECT * INTO v_draft
  FROM public.plan_drafts
  WHERE id = p_draft_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_draft_not_found' USING ERRCODE = 'PD404';
  END IF;

  IF v_draft.status = 'confirmed' THEN
    -- The same confirmation again returns the same plan; nothing is written.
    RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('already_confirmed', true);
  END IF;
  IF v_draft.status <> 'ready_for_review' THEN
    RAISE EXCEPTION 'plan_draft_not_reviewable' USING ERRCODE = 'PD422';
  END IF;
  IF v_draft.expires_at <= v_now THEN
    RAISE EXCEPTION 'plan_draft_expired' USING ERRCODE = 'PD410';
  END IF;
  IF v_draft.payload_version <> p_payload_version THEN
    RAISE EXCEPTION 'plan_draft_changed' USING ERRCODE = 'PD409';
  END IF;

  -- The origin, and whether the patient changed the content before
  -- confirming it.
  v_generated_by := CASE v_draft.origin
    WHEN 'flow_generated' THEN 'flow_draft' ELSE 'patient_import' END
    || CASE WHEN v_draft.payload_version > 1 THEN '_edited' ELSE '' END;

  IF v_draft.domain = 'training' THEN
    SELECT id, generated_by INTO v_current_plan, v_current_generated_by
    FROM public.training_plans
    WHERE user_id = p_user_id AND active = true;

    IF v_current_generated_by = 'professional' THEN
      RAISE EXCEPTION 'prescribed_plan_protected' USING ERRCODE = 'PD423';
    END IF;
    IF v_current_plan IS DISTINCT FROM v_draft.base_active_plan_id THEN
      RAISE EXCEPTION 'plan_changed_during_review' USING ERRCODE = 'PD412';
    END IF;

    v_schedule := v_draft.payload -> 'weekly_schedule';
    v_plan_type := COALESCE(v_draft.payload ->> 'plan_type', 'custom');
    IF jsonb_typeof(v_schedule) IS DISTINCT FROM 'array'
      OR jsonb_array_length(v_schedule) < 1
      OR jsonb_array_length(v_schedule) > 7
      OR v_plan_type NOT IN ('split', 'full_body', 'custom') THEN
      RAISE EXCEPTION 'plan_draft_not_reviewable' USING ERRCODE = 'PD422';
    END IF;
    v_days := jsonb_array_length(v_schedule);

    v_plan_id := (private.replace_active_training_plan(
      p_user_id,
      v_plan_type,
      v_days,
      NULLIF(left(v_draft.payload ->> 'equipment_summary', 500), ''),
      v_schedule,
      v_generated_by,
      v_now,
      p_valid_until,
      1,
      NULLIF(left(v_draft.payload ->> 'notes', 500), ''),
      'plan-draft:' || v_draft.id::text,
      false
    ) ->> 'plan_id')::uuid;
  ELSE
    SELECT id, generated_by INTO v_current_prescription, v_current_generated_by
    FROM public.prescriptions
    WHERE user_id = p_user_id
    ORDER BY generated_at DESC, id DESC
    LIMIT 1;

    IF v_current_generated_by = 'professional'
      AND EXISTS (
        SELECT 1 FROM public.prescriptions
        WHERE id = v_current_prescription
          AND (valid_until IS NULL OR valid_until >= v_now)
      ) THEN
      RAISE EXCEPTION 'prescribed_plan_protected' USING ERRCODE = 'PD423';
    END IF;
    IF v_current_prescription IS DISTINCT FROM v_draft.base_latest_prescription_id THEN
      RAISE EXCEPTION 'plan_changed_during_review' USING ERRCODE = 'PD412';
    END IF;
    IF jsonb_typeof(v_draft.payload -> 'daily_meals') IS DISTINCT FROM 'array'
      OR jsonb_array_length(v_draft.payload -> 'daily_meals') < 1 THEN
      RAISE EXCEPTION 'plan_draft_not_reviewable' USING ERRCODE = 'PD422';
    END IF;

    -- Insert only: earlier prescriptions are never changed or removed.
    INSERT INTO public.prescriptions (
      user_id, type, payload, generated_by, generated_at, valid_until,
      version, notes, source_request_key
    ) VALUES (
      p_user_id,
      CASE
        WHEN jsonb_typeof(v_draft.payload -> 'shopping_list') = 'array'
          AND jsonb_array_length(v_draft.payload -> 'shopping_list') > 0
        THEN 'combined' ELSE 'diet'
      END,
      v_draft.payload,
      v_generated_by,
      v_now,
      p_valid_until,
      1,
      NULLIF(left(v_draft.payload ->> 'notes', 500), ''),
      'plan-draft:' || v_draft.id::text
    )
    RETURNING id INTO v_plan_id;
  END IF;

  PERFORM set_config('bodyflow.confirming_plan_draft', p_draft_id::text, true);
  UPDATE public.plan_drafts
  SET status = 'confirmed',
      confirmed_plan_id = v_plan_id,
      confirmation_key = p_idempotency_key,
      resolved_at = v_now
  WHERE id = p_draft_id
  RETURNING * INTO v_draft;
  PERFORM set_config('bodyflow.confirming_plan_draft', '', true);

  RETURN private.plan_draft_dto(v_draft) || jsonb_build_object('already_confirmed', false);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Privileges
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION private.enforce_plan_draft_transition() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.plan_draft_dto(public.plan_drafts) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.replace_active_training_plan(
  uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.replace_active_training_plan(
  uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text, boolean
) TO service_role;

REVOKE ALL ON FUNCTION public.save_training_plan_atomic(
  uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_training_plan_atomic(
  uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text
) TO service_role;

REVOKE ALL ON FUNCTION public.create_plan_draft_atomic(
  uuid, text, text, text, jsonb, jsonb, jsonb, jsonb, uuid, uuid, jsonb, text
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_plan_draft_work_atomic(
  uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, jsonb, text
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_plan_draft_atomic(
  uuid, uuid, integer, jsonb, jsonb, boolean
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.discard_plan_draft_atomic(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.confirm_plan_draft_atomic(
  uuid, uuid, integer, timestamptz, text
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_plan_draft_atomic(
  uuid, text, text, text, jsonb, jsonb, jsonb, jsonb, uuid, uuid, jsonb, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.resolve_plan_draft_work_atomic(
  uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, jsonb, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_plan_draft_atomic(
  uuid, uuid, integer, jsonb, jsonb, boolean
) TO service_role;
GRANT EXECUTE ON FUNCTION public.discard_plan_draft_atomic(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.confirm_plan_draft_atomic(
  uuid, uuid, integer, timestamptz, text
) TO service_role;

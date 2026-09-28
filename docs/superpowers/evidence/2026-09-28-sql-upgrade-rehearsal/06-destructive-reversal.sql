-- DESTRUCTIVE REVERSAL OF M4, M3, M2, M1 (in that order). NEVER AUTOMATIC.
--
-- This is NOT a rollback without data loss. Running it deletes, with no way
-- back except a restore from backup:
--   * every plan draft (public.plan_drafts), including drafts under review;
--   * every imported plan document row (media_assets kind plan_document) —
--     the storage objects in bucket plan-documents must be handled first;
--   * prescriptions.source_request_key (idempotency of confirmed plans);
--   * user_profiles.weight_measured_at and weight_instant_source (the
--     instant of every weight measured through the app).
-- Plans already confirmed stay in prescriptions/training_plans, but lose
-- their link to the draft that produced them.
--
-- Old function bodies and constraints below were extracted from a restore of
-- the pre-M1 baseline (pg_get_functiondef / pg_get_constraintdef).
-- It refuses to run while any plan_document storage object exists.
-- Run only with explicit written authorization naming this file and hash.
\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'plan-documents') THEN
    RAISE EXCEPTION 'REVERSAL REFUSED: plan-documents bucket still holds objects; export or delete them explicitly first';
  END IF;
END;
$guard$;

-- M4 ---------------------------------------------------------------------
DROP FUNCTION public.reset_user_conversation_atomic(uuid, boolean);
CREATE OR REPLACE FUNCTION public.reset_user_conversation_atomic(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_deleted integer;
  v_deleted_total integer := 0;
BEGIN
  PERFORM 1
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user % not found', p_user_id;
  END IF;

  DELETE FROM public.pending_registrations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_dispatch_outbox WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_buffer WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.tools_audit WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.llm_evaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_gap_reminder_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.engagement_delivery_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.attention_dismissals WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_phrase_cooldown WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_food_corrections WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.prescriptions WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.training_plans WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.reevaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.meal_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.workout_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_snapshots WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.messages WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.product_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  INSERT INTO public.user_profiles (
    user_id,
    onboarding_completed,
    onboarding_step
  ) VALUES (
    p_user_id,
    false,
    0
  )
  ON CONFLICT (user_id) DO UPDATE
  SET sex = null,
      birth_date = null,
      height_cm = null,
      weight_kg = null,
      body_fat_percent = null,
      body_fat_measured_at = null,
      activity_level = null,
      training_frequency = null,
      water_intake = null,
      hunger_level = null,
      wake_time = null,
      bedtime = null,
      current_protocol = null,
      goal_type = null,
      goal_value = null,
      deficit_level = null,
      food_organization = null,
      bf_percent_estimated = null,
      bf_source = null,
      bf_estimated_at = null,
      cycle_start_weight_kg = null,
      cycle_start_bf_percent = null,
      cycle_start_training_freq = null,
      cycle_start_at = null,
      onboarding_completed = false,
      onboarding_step = 0,
      updated_at = now();

  INSERT INTO public.user_progress (
    user_id,
    xp_total,
    level,
    current_streak,
    longest_streak,
    blocks_completed,
    deficit_block,
    badges_earned
  ) VALUES (
    p_user_id,
    0,
    1,
    0,
    0,
    0,
    0,
    '{}'::text[]
  )
  ON CONFLICT (user_id) DO UPDATE
  SET xp_total = 0,
      level = 1,
      current_streak = 0,
      longest_streak = 0,
      blocks_completed = 0,
      deficit_block = 0,
      current_weight = null,
      current_bf_percent = null,
      badges_earned = '{}'::text[],
      last_active_date = null,
      next_reevaluation = null,
      updated_at = now();

  UPDATE public.users
  SET name = null,
      summary = null,
      summary_updated_at = null,
      tags = '{}'::text[],
      admin_notes = null,
      country_confirmed = false,
      last_active_at = null,
      metadata = '{}'::jsonb,
      updated_at = now()
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'reset', true,
    'user_id', p_user_id,
    'deleted_rows', v_deleted_total
  );
END;
$function$

;

-- M3 ---------------------------------------------------------------------
DELETE FROM public.media_assets WHERE kind = 'plan_document';
ALTER TABLE public.media_assets
  DROP CONSTRAINT media_assets_kind_check,
  DROP CONSTRAINT media_assets_bucket_kind_check,
  DROP CONSTRAINT media_assets_mime_kind_check,
  DROP CONSTRAINT media_assets_size_check,
  DROP CONSTRAINT media_assets_retention_check;
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_bucket_kind_check CHECK ((((kind = 'meal_photo'::text) AND (bucket_id = 'meal-photos'::text)) OR ((kind = 'body_checkin_photo'::text) AND (bucket_id = 'body-checkin-photos'::text)) OR ((kind = 'gym_photo'::text) AND (bucket_id = 'gym-photos'::text)) OR ((kind = 'audio_note'::text) AND (bucket_id = 'audio-notes'::text)) OR ((kind = 'content_cover'::text) AND (bucket_id = 'content-covers'::text))));
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_kind_check CHECK ((kind = ANY (ARRAY['meal_photo'::text, 'body_checkin_photo'::text, 'gym_photo'::text, 'audio_note'::text, 'content_cover'::text])));
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_mime_kind_check CHECK ((((kind = ANY (ARRAY['meal_photo'::text, 'body_checkin_photo'::text, 'gym_photo'::text])) AND (mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'image/heic'::text, 'image/heif'::text]))) OR ((kind = 'audio_note'::text) AND (mime_type = ANY (ARRAY['audio/mpeg'::text, 'audio/mp4'::text, 'audio/x-m4a'::text, 'audio/aac'::text, 'audio/wav'::text, 'audio/x-wav'::text, 'audio/ogg'::text]))) OR ((kind = 'content_cover'::text) AND (mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text])))));
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_retention_check CHECK (((kind = 'content_cover'::text) OR (retention_until IS NOT NULL)));
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_size_check CHECK (((declared_size_bytes > 0) AND (((kind = ANY (ARRAY['meal_photo'::text, 'body_checkin_photo'::text, 'gym_photo'::text])) AND (declared_size_bytes <= 15728640)) OR ((kind = 'audio_note'::text) AND (declared_size_bytes <= 26214400)) OR ((kind = 'content_cover'::text) AND (declared_size_bytes <= 10485760))) AND ((actual_size_bytes IS NULL) OR (actual_size_bytes = declared_size_bytes))));
-- The empty plan-documents bucket is removed through the Storage API, not
-- SQL: storage.protect_delete blocks a direct DELETE on storage.buckets
-- (verified in the local rehearsal, 2026-09-28).

-- M2 ---------------------------------------------------------------------
DROP FUNCTION private.plan_draft_dto(public.plan_drafts);
DROP TABLE public.plan_drafts;
DROP FUNCTION private.enforce_plan_draft_transition();
DROP FUNCTION public.create_plan_draft_atomic;
DROP FUNCTION public.resolve_plan_draft_work_atomic;
DROP FUNCTION public.update_plan_draft_atomic;
DROP FUNCTION public.discard_plan_draft_atomic;
DROP FUNCTION public.confirm_plan_draft_atomic;
CREATE OR REPLACE FUNCTION public.save_training_plan_atomic(p_user_id uuid, p_plan_type text, p_days_per_week integer, p_equipment_summary text, p_weekly_schedule jsonb, p_generated_by text, p_generated_at timestamp with time zone, p_valid_until timestamp with time zone, p_version integer, p_notes text, p_request_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    OR p_version IS NULL OR p_version < 1 THEN
    RAISE EXCEPTION 'invalid training plan payload';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':training-plan', 0));

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
    user_id,
    plan_type,
    days_per_week,
    equipment_summary,
    weekly_schedule,
    generated_by,
    generated_at,
    valid_until,
    active,
    version,
    notes,
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

  UPDATE public.users
  SET
    metadata = COALESCE(metadata, '{}'::jsonb) || '{"training_reminders": true}'::jsonb,
    updated_at = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'training plan user not found';
  END IF;

  RETURN jsonb_build_object('plan_id', v_plan_id, 'inserted', true);
END;
$function$

;
DROP FUNCTION private.replace_active_training_plan;
DROP INDEX public.uniq_prescriptions_request;
ALTER TABLE public.prescriptions DROP COLUMN source_request_key;
DROP INDEX public.messages_id_user_unique;
DROP INDEX public.media_assets_id_user_unique;

-- M1 ---------------------------------------------------------------------
DROP TRIGGER user_profiles_sync_weight_measured_at ON public.user_profiles;
DROP FUNCTION public.record_weight_atomic;
DROP FUNCTION private.apply_weight_measurement;
DROP FUNCTION private.sync_weight_measured_at();
ALTER TABLE public.user_profiles DROP CONSTRAINT user_profiles_weight_instant_source_check;
ALTER TABLE public.user_profiles DROP COLUMN weight_instant_source, DROP COLUMN weight_measured_at;

-- Mobile-only confirmed-record mutation and receipt in one transaction.
-- Existing legacy registration/finalization remain unchanged.
-- p_expected_state and p_calculated_items are authenticated server values, never client fields.
CREATE OR REPLACE FUNCTION public.mutate_mobile_confirmed_meal(
  p_user_id uuid,
  p_idempotency_key text,
  p_request_method text,
  p_request_route text,
  p_request_hash text,
  p_record_id uuid,
  p_expected_version text,
  p_item_ids uuid[],
  p_expected_state jsonb,
  p_calculated_items jsonb,
  p_nutrition_mode text,
  p_quantity_change jsonb,
  p_request_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
SET lock_timeout = '2000ms'
AS $$
DECLARE
  v_now timestamptz;
  v_request public.mobile_api_idempotency%ROWTYPE;
  v_inserted_claim uuid;
  v_user public.users%ROWTYPE;
  v_snapshot public.daily_snapshots%ROWTYPE;
  v_anchor public.meal_logs%ROWTYPE;
  v_context jsonb;
  v_actual_state jsonb;
  v_typed_expected_state jsonb;
  v_expected_user public.users%ROWTYPE;
  v_expected_snapshot public.daily_snapshots%ROWTYPE;
  v_expected_items jsonb;
  v_quantity_item public.meal_logs%ROWTYPE;
  v_quantity_ratio double precision;
  v_quantity_rounded double precision[];
  v_before_snapshot jsonb;
  v_before_retained jsonb;
  v_after_retained jsonb;
  v_date date;
  v_snapshot_id uuid;
  v_timezone text;
  v_group_ids uuid[];
  v_before_ids uuid[];
  v_new_ids uuid[] := ARRAY[]::uuid[];
  v_remaining_group_ids uuid[];
  v_selected_count integer;
  v_changed_count integer;
  v_expected_inserted integer;
  v_registered jsonb;
  v_body jsonb;
  v_completed boolean;
BEGIN
  PERFORM private.assert_trusted_backend();

  -- Protocol identity precedes replay; no business/context/target/calculation guards here.
  IF p_user_id IS NULL OR p_record_id IS NULL
    OR p_request_method IS NULL OR p_request_method NOT IN ('PATCH', 'DELETE')
    OR p_request_route IS DISTINCT FROM '/api/mobile/v1/meal-records/' || p_record_id::text
    OR p_request_hash IS NULL OR p_request_hash !~ '^[0-9a-f]{64}$'
    OR p_idempotency_key IS NULL OR char_length(p_idempotency_key) NOT BETWEEN 8 AND 128
    OR p_idempotency_key !~ '^[A-Za-z0-9._:-]+$'
    OR p_request_id IS NULL OR char_length(p_request_id) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'mobile meal request identity is invalid' USING ERRCODE = '22023';
  END IF;

  IF NOT pg_try_advisory_xact_lock(hashtextextended(
    'mobile-confirmed-meal:' || p_user_id::text || ':' || p_idempotency_key, 0
  )) THEN
    RETURN jsonb_build_object('action', 'in_progress');
  END IF;

  SELECT * INTO v_request FROM public.mobile_api_idempotency
  WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key FOR UPDATE NOWAIT;
  IF NOT FOUND THEN
    v_now := clock_timestamp();
    INSERT INTO public.mobile_api_idempotency (
      user_id, idempotency_key, request_method, request_route, request_hash,
      created_at, updated_at, expires_at
    ) VALUES (
      p_user_id, p_idempotency_key, p_request_method, p_request_route, p_request_hash,
      v_now, v_now, v_now + interval '24 hours'
    ) ON CONFLICT (user_id, idempotency_key) DO NOTHING RETURNING id INTO v_inserted_claim;
    SELECT * INTO v_request FROM public.mobile_api_idempotency
    WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key FOR UPDATE NOWAIT;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'mobile meal request disappeared' USING ERRCODE = '40001';
    END IF;
  END IF;

  IF v_request.request_method IS DISTINCT FROM p_request_method
    OR v_request.request_route IS DISTINCT FROM p_request_route
    OR v_request.request_hash IS DISTINCT FROM p_request_hash THEN
    RETURN jsonb_build_object('action', 'conflict');
  END IF;
  -- Completed identity wins over expiry, absent targets, closed day, or changed country.
  IF v_request.state = 'completed' THEN
    RETURN jsonb_build_object('action', 'replay',
      'response_status', v_request.response_status, 'response_body', v_request.response_body);
  END IF;
  v_now := clock_timestamp();
  IF v_inserted_claim IS NULL AND v_request.state = 'processing'
    AND v_request.updated_at > v_now - interval '10 minutes' THEN
    RETURN jsonb_build_object('action', 'in_progress');
  END IF;
  IF v_inserted_claim IS NULL THEN
    UPDATE public.mobile_api_idempotency SET state = 'processing', response_status = NULL,
      response_body = NULL, attempt_count = attempt_count + 1,
      updated_at = v_now, expires_at = v_now + interval '24 hours'
    WHERE id = v_request.id;
  END IF;

  -- These are operation guards only for a fresh, not-yet-completed mutation.
  IF p_expected_version IS NULL OR p_expected_version !~ '^v1:[0-9a-f]{64}$'
    OR p_expected_state IS NULL OR jsonb_typeof(p_expected_state) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_expected_state->'context') IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_expected_state->'snapshot') IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_expected_state->'items') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'mobile meal expected state is invalid' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(cardinality(p_item_ids), 0) NOT BETWEEN 1 AND 30
    OR array_ndims(p_item_ids) IS DISTINCT FROM 1
    OR array_position(p_item_ids, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'mobile meal selection is invalid' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT id)::integer INTO v_selected_count FROM unnest(p_item_ids) AS selected(id);
  IF v_selected_count <> cardinality(p_item_ids) THEN
    RAISE EXCEPTION 'mobile meal ids must be unique' USING ERRCODE = '22023';
  END IF;
  IF p_request_method = 'PATCH' AND (
    v_selected_count <> 1 OR p_item_ids[1] IS DISTINCT FROM p_record_id
  ) THEN
    RAISE EXCEPTION 'mobile meal PATCH edits one anchored food item' USING ERRCODE = '22023';
  END IF;
  IF p_request_method = 'DELETE' AND (p_calculated_items IS NOT NULL
    OR p_nutrition_mode IS NOT NULL OR p_quantity_change IS NOT NULL) THEN
    RAISE EXCEPTION 'mobile meal DELETE cannot contain replacement calculation' USING ERRCODE = '22023';
  END IF;
  IF p_request_method = 'PATCH' AND (p_nutrition_mode IS NULL
    OR p_nutrition_mode NOT IN ('quantity_only', 'recalculated')
    OR (p_nutrition_mode = 'recalculated' AND p_quantity_change IS NOT NULL)) THEN
    RAISE EXCEPTION 'mobile meal backend nutrition mode is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR SHARE NOWAIT;
  IF NOT FOUND OR v_user.status::text IS DISTINCT FROM 'active'
    OR v_user.auth_user_id IS NULL
    OR v_user.auth_user_id::text IS DISTINCT FROM p_expected_state->'context'->>'auth_user_id' THEN
    RAISE EXCEPTION 'mobile meal authenticated context changed' USING ERRCODE = '40001';
  END IF;
  v_context := jsonb_build_object('id', v_user.id, 'auth_user_id', v_user.auth_user_id,
    'country', v_user.country, 'country_confirmed', v_user.country_confirmed,
    'timezone', v_user.timezone, 'status', v_user.status, 'wpp', v_user.wpp,
    'updated_at', v_user.updated_at);
  -- Reject unknown/missing keys before typed conversion. No timestamp precision is discarded.
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_expected_state) AS keys(key))
      IS DISTINCT FROM ARRAY['context', 'items', 'snapshot']::text[]
    OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_expected_state->'context') AS keys(key))
      IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_context) AS keys(key)) THEN
    RAISE EXCEPTION 'mobile meal expected context keys differ' USING ERRCODE = '22023';
  END IF;
  v_expected_user := jsonb_populate_record(NULL::public.users, p_expected_state->'context');
  IF v_context IS DISTINCT FROM jsonb_build_object('id', v_expected_user.id,
    'auth_user_id', v_expected_user.auth_user_id, 'country', v_expected_user.country,
    'country_confirmed', v_expected_user.country_confirmed, 'timezone', v_expected_user.timezone,
    'status', v_expected_user.status, 'wpp', v_expected_user.wpp, 'updated_at', v_expected_user.updated_at) THEN
    RAISE EXCEPTION 'mobile meal official context changed' USING ERRCODE = '40001';
  END IF;
  IF p_request_method = 'PATCH' AND p_nutrition_mode = 'recalculated' AND (
    NOT v_user.country_confirmed OR NULLIF(btrim(v_user.country), '') IS NULL
  ) THEN
    RAISE EXCEPTION 'mobile meal confirmed country required' USING ERRCODE = '22023';
  END IF;
  v_timezone := v_user.timezone;
  IF v_timezone IS NULL OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_timezone) THEN
    RAISE EXCEPTION 'mobile meal official timezone required' USING ERRCODE = '22023';
  END IF;
  -- wpp never blocks this authenticated API. Country is required only for fresh catalog calculation.
  v_date := (p_expected_state->'snapshot'->>'date')::date;
  v_snapshot_id := (p_expected_state->'snapshot'->>'id')::uuid;
  IF v_date IS NULL OR v_snapshot_id IS NULL THEN
    RAISE EXCEPTION 'mobile meal snapshot identity is invalid' USING ERRCODE = '22023';
  END IF;
  -- Same owner:date lock as existing base/scoped registration, before snapshot locks.
  IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || v_date::text, 0)) THEN
    RAISE EXCEPTION 'mobile meal date is busy' USING ERRCODE = '55P03';
  END IF;
  SELECT * INTO v_snapshot FROM public.daily_snapshots
  WHERE id = v_snapshot_id AND user_id = p_user_id AND date = v_date FOR UPDATE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile meal snapshot changed' USING ERRCODE = '40001';
  END IF;
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_expected_state->'snapshot') AS keys(key))
    IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(to_jsonb(v_snapshot)) AS keys(key)) THEN
    RAISE EXCEPTION 'mobile meal expected snapshot keys differ' USING ERRCODE = '22023';
  END IF;
  v_expected_snapshot := jsonb_populate_record(NULL::public.daily_snapshots, p_expected_state->'snapshot');
  -- UUID order, including remaining rows used by the existing sum(snapshot_id) formula.
  PERFORM 1 FROM public.meal_logs WHERE snapshot_id = v_snapshot_id ORDER BY id FOR UPDATE NOWAIT;
  IF EXISTS (SELECT 1 FROM public.meal_logs WHERE snapshot_id = v_snapshot_id AND user_id <> p_user_id) THEN
    RAISE EXCEPTION 'mobile meal snapshot contains foreign-owner rows' USING ERRCODE = '40001';
  END IF;
  SELECT * INTO v_anchor FROM public.meal_logs
  WHERE id = p_record_id AND user_id = p_user_id AND snapshot_id = v_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mobile meal anchor changed' USING ERRCODE = '40001';
  END IF;
  IF jsonb_array_length(p_expected_state->'items') NOT BETWEEN 1 AND 30 OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_expected_state->'items') AS expected(item)
    WHERE jsonb_typeof(item) IS DISTINCT FROM 'object'
  ) THEN
    RAISE EXCEPTION 'mobile meal expected full rows are invalid' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_expected_state->'items') AS expected(item)
    WHERE (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(item) AS keys(key))
      IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(to_jsonb(v_anchor)) AS keys(key))
  ) THEN
    RAISE EXCEPTION 'mobile meal expected full row keys differ' USING ERRCODE = '22023';
  END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(jsonb_populate_record(NULL::public.meal_logs, item))
    ORDER BY (item->>'id')::uuid), '[]'::jsonb) INTO v_expected_items
  FROM jsonb_array_elements(p_expected_state->'items') AS expected(item);
  SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::uuid[]) INTO v_group_ids
  FROM public.meal_logs WHERE user_id = p_user_id AND snapshot_id = v_snapshot_id
    AND ((v_anchor.raw_provider_message_id IS NULL AND id = p_record_id)
      OR (v_anchor.raw_provider_message_id IS NOT NULL
        AND raw_provider_message_id = v_anchor.raw_provider_message_id));
  IF cardinality(v_group_ids) NOT BETWEEN 1 AND 30 OR NOT (p_item_ids <@ v_group_ids) THEN
    RAISE EXCEPTION 'mobile meal official group selection changed' USING ERRCODE = '40001';
  END IF;
  SELECT jsonb_build_object('context', v_context, 'snapshot', to_jsonb(v_snapshot),
    'items', COALESCE(jsonb_agg(to_jsonb(meal) ORDER BY meal.id), '[]'::jsonb))
  INTO v_actual_state FROM public.meal_logs AS meal WHERE meal.id = ANY(v_group_ids);
  v_typed_expected_state := jsonb_build_object('context', v_context,
    'snapshot', to_jsonb(v_expected_snapshot), 'items', v_expected_items);
  IF v_actual_state IS DISTINCT FROM v_typed_expected_state THEN
    RAISE EXCEPTION 'mobile meal version state changed' USING ERRCODE = '40001';
  END IF;
  -- Authoritative clock after locks. Snapshot date AND every group timestamp must match.
  v_now := clock_timestamp();
  IF v_snapshot.day_closed OR v_date IS DISTINCT FROM (v_now AT TIME ZONE v_timezone)::date
    OR EXISTS (SELECT 1 FROM public.meal_logs WHERE id = ANY(v_group_ids)
      AND (consumed_at AT TIME ZONE v_timezone)::date IS DISTINCT FROM v_date) THEN
    RAISE EXCEPTION 'mobile meal current open local day required' USING ERRCODE = '40001';
  END IF;
  v_before_snapshot := to_jsonb(v_snapshot);
  SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::uuid[]),
    COALESCE(jsonb_agg(to_jsonb(meal) ORDER BY id) FILTER (WHERE NOT (id = ANY(p_item_ids))), '[]'::jsonb)
  INTO v_before_ids, v_before_retained FROM public.meal_logs AS meal WHERE snapshot_id = v_snapshot_id;

  IF p_request_method = 'PATCH' THEN
    IF p_calculated_items IS NULL OR jsonb_typeof(p_calculated_items) IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'mobile meal backend calculated items required' USING ERRCODE = '22023';
    END IF;
    v_expected_inserted := jsonb_array_length(p_calculated_items);
    IF cardinality(v_group_ids) - v_selected_count + v_expected_inserted > 30 THEN
      RAISE EXCEPTION 'mobile meal resulting group exceeds30items' USING ERRCODE = '22023';
    END IF;
    IF v_expected_inserted NOT BETWEEN 1 AND 30 OR EXISTS (
      SELECT 1 FROM jsonb_to_recordset(p_calculated_items) AS item(source text)
      WHERE (p_nutrition_mode = 'recalculated' AND item.source IS NULL)
        OR item.source IN ('no_match', 'composite_rejected', 'category_mismatch', 'protein_mismatch')
    ) THEN
      RAISE EXCEPTION 'mobile meal nutrition unresolved' USING ERRCODE = '22023';
    END IF;
    IF p_nutrition_mode = 'quantity_only' THEN
      -- The mode/proof are authenticated backend values, never client request fields.
      -- Compare to the official anchor AFTER whole-state/version/context locks.
      IF v_expected_inserted <> 1 OR p_quantity_change IS NULL
        OR jsonb_typeof(p_quantity_change) IS DISTINCT FROM 'object'
        OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_quantity_change) AS keys(key))
          IS DISTINCT FROM ARRAY['quantity_g']::text[]
        OR jsonb_typeof(p_quantity_change->'quantity_g') IS DISTINCT FROM 'number'
        OR jsonb_typeof(p_calculated_items->0) IS DISTINCT FROM 'object'
        OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_calculated_items->0) AS keys(key))
          IS DISTINCT FROM ARRAY['carbs_g', 'confidence', 'fat_g', 'food_db_id', 'food_name',
            'kcal', 'protein_g', 'quantity_g', 'source']::text[] THEN
        RAISE EXCEPTION 'mobile meal quantity proof is invalid' USING ERRCODE = '22023';
      END IF;
      IF EXISTS (SELECT 1 FROM unnest(ARRAY['quantity_g', 'kcal', 'protein_g', 'carbs_g', 'fat_g']) AS fields(field)
        WHERE jsonb_typeof((p_calculated_items->0)->field) IS DISTINCT FROM 'number') THEN
        RAISE EXCEPTION 'mobile meal quantity nutrients must be numeric' USING ERRCODE = '22023';
      END IF;
      v_quantity_item := jsonb_populate_record(NULL::public.meal_logs, p_calculated_items->0);
      IF v_anchor.quantity_g IS NULL OR v_anchor.quantity_g <= 0 OR v_anchor.quantity_g > 9999
        OR v_anchor.kcal IS NULL OR v_anchor.kcal < 0 OR v_anchor.kcal > 99999
        OR v_anchor.protein_g IS NULL OR v_anchor.protein_g < 0 OR v_anchor.protein_g > 9999
        OR v_anchor.carbs_g IS NULL OR v_anchor.carbs_g < 0 OR v_anchor.carbs_g > 9999
        OR v_anchor.fat_g IS NULL OR v_anchor.fat_g < 0 OR v_anchor.fat_g > 9999
        OR v_anchor.kcal > v_anchor.quantity_g * 9.5 + 5
        OR v_anchor.protein_g + v_anchor.carbs_g + v_anchor.fat_g > v_anchor.quantity_g * 1.1 + 5
        OR (v_anchor.source IN ('canonical_exact', 'canonical_fuzzy') AND v_anchor.food_db_id IS NULL)
        OR v_anchor.source IN ('no_match', 'composite_rejected', 'category_mismatch', 'protein_mismatch')
        OR v_quantity_item.food_name IS DISTINCT FROM v_anchor.food_name
        OR v_quantity_item.source IS DISTINCT FROM v_anchor.source
        OR v_quantity_item.food_db_id IS DISTINCT FROM v_anchor.food_db_id
        OR v_quantity_item.confidence IS DISTINCT FROM v_anchor.confidence
        OR v_quantity_item.quantity_g IS NULL OR v_quantity_item.quantity_g <= 0 OR v_quantity_item.quantity_g > 9999
        OR v_quantity_item.quantity_g IS DISTINCT FROM (p_quantity_change->>'quantity_g')::numeric
        OR v_quantity_item.quantity_g IS DISTINCT FROM ((p_calculated_items->0)->>'quantity_g')::numeric THEN
        RAISE EXCEPTION 'mobile meal quantity provenance changed' USING ERRCODE = '22023';
      END IF;
      -- Existing JS helper: ratio binary64, round((value+EPSILON)*10^d)/10^d.
      -- For nonnegative x, use floor(x)+(fraction>=0.5), not floor(x+0.5) with its extra rounding.
      -- Exact JS/PG goldens remain a REQUIRED runtime gate; no equivalence is claimed here.
      v_quantity_ratio := v_quantity_item.quantity_g::double precision / v_anchor.quantity_g::double precision;
      SELECT array_agg((floor(value) + CASE WHEN value - floor(value) >= 0.5 THEN 1 ELSE 0 END)
        / CASE WHEN ordinal = 1 THEN 10 ELSE 100 END ORDER BY ordinal)
      INTO v_quantity_rounded
      FROM unnest(ARRAY[
        (v_anchor.kcal::double precision * v_quantity_ratio + 2.220446049250313e-16::double precision) * 10,
        (v_anchor.protein_g::double precision * v_quantity_ratio + 2.220446049250313e-16::double precision) * 100,
        (v_anchor.carbs_g::double precision * v_quantity_ratio + 2.220446049250313e-16::double precision) * 100,
        (v_anchor.fat_g::double precision * v_quantity_ratio + 2.220446049250313e-16::double precision) * 100
      ]) WITH ORDINALITY AS scaled(value, ordinal);
      IF v_quantity_item.kcal::double precision IS DISTINCT FROM
          v_quantity_rounded[1]
        OR v_quantity_item.protein_g::double precision IS DISTINCT FROM
          v_quantity_rounded[2]
        OR v_quantity_item.carbs_g::double precision IS DISTINCT FROM
          v_quantity_rounded[3]
        OR v_quantity_item.fat_g::double precision IS DISTINCT FROM
          v_quantity_rounded[4] THEN
        RAISE EXCEPTION 'mobile meal quantity proportional values differ' USING ERRCODE = '22023';
      END IF;
    END IF;
    v_registered := public.register_meal_atomic_scoped(
      p_user_id => p_user_id, p_date => v_date, p_meal_type => v_anchor.meal_type,
      p_items => p_calculated_items, p_replace => true, p_replace_meal_types => NULL,
      p_consumed_at => v_anchor.consumed_at, p_provider_message_id => v_anchor.raw_provider_message_id,
      p_calories_target => v_snapshot.calories_target, p_protein_target => v_snapshot.protein_target,
      p_replace_log_ids => p_item_ids
    );
    IF (v_registered->>'replaced_count')::integer IS DISTINCT FROM 1
      OR (v_registered->>'inserted_count')::integer IS DISTINCT FROM v_expected_inserted
      OR (v_registered->>'snapshot_id')::uuid IS DISTINCT FROM v_snapshot_id THEN
      RAISE EXCEPTION 'mobile meal scoped replacement incomplete' USING ERRCODE = '40001';
    END IF;
    SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::uuid[]) INTO v_new_ids
    FROM public.meal_logs WHERE snapshot_id = v_snapshot_id AND NOT (id = ANY(v_before_ids));
    IF cardinality(v_new_ids) IS DISTINCT FROM v_expected_inserted THEN
      RAISE EXCEPTION 'mobile meal official replacement ids incomplete' USING ERRCODE = '40001';
    END IF;
    IF EXISTS (SELECT 1 FROM public.meal_logs WHERE id = ANY(v_new_ids) AND (
      user_id IS DISTINCT FROM p_user_id OR snapshot_id IS DISTINCT FROM v_snapshot_id
      OR meal_type IS DISTINCT FROM v_anchor.meal_type OR consumed_at IS DISTINCT FROM v_anchor.consumed_at
      OR raw_provider_message_id IS DISTINCT FROM v_anchor.raw_provider_message_id
    )) THEN
      RAISE EXCEPTION 'mobile meal replacement headers changed' USING ERRCODE = '40001';
    END IF;
    UPDATE public.meal_logs SET image_url = v_anchor.image_url, raw_message_id = v_anchor.raw_message_id
    WHERE id = ANY(v_new_ids) AND user_id = p_user_id AND snapshot_id = v_snapshot_id;
    GET DIAGNOSTICS v_changed_count = ROW_COUNT;
    IF v_changed_count IS DISTINCT FROM v_expected_inserted THEN
      RAISE EXCEPTION 'mobile meal replacement origin incomplete' USING ERRCODE = '40001';
    END IF;
    IF p_nutrition_mode = 'quantity_only' AND EXISTS (
      SELECT 1 FROM public.meal_logs WHERE id = ANY(v_new_ids) AND (
        food_name IS DISTINCT FROM v_anchor.food_name OR source IS DISTINCT FROM v_anchor.source
        OR food_db_id IS DISTINCT FROM v_anchor.food_db_id OR confidence IS DISTINCT FROM v_anchor.confidence
        OR image_url IS DISTINCT FROM v_anchor.image_url OR raw_message_id IS DISTINCT FROM v_anchor.raw_message_id
        OR quantity_g IS DISTINCT FROM v_quantity_item.quantity_g OR kcal IS DISTINCT FROM v_quantity_item.kcal
        OR protein_g IS DISTINCT FROM v_quantity_item.protein_g OR carbs_g IS DISTINCT FROM v_quantity_item.carbs_g
        OR fat_g IS DISTINCT FROM v_quantity_item.fat_g
      )
    ) THEN
      RAISE EXCEPTION 'mobile meal quantity publication changed' USING ERRCODE = '40001';
    END IF;
  ELSE
    DELETE FROM public.meal_logs WHERE id = ANY(p_item_ids) AND user_id = p_user_id AND snapshot_id = v_snapshot_id;
    GET DIAGNOSTICS v_changed_count = ROW_COUNT;
    IF v_changed_count IS DISTINCT FROM v_selected_count THEN
      RAISE EXCEPTION 'mobile meal finite delete incomplete' USING ERRCODE = '40001';
    END IF;
  END IF;

  -- The existing official rounding/formulas; all other snapshot columns remain untouched.
  UPDATE public.daily_snapshots AS snapshot SET calories_consumed = totals.calories_consumed,
    protein_g = totals.protein_g, carbs_g = totals.carbs_g, fat_g = totals.fat_g,
    updated_at = clock_timestamp()
  FROM (SELECT round(COALESCE(sum(kcal), 0))::integer AS calories_consumed,
    round(COALESCE(sum(protein_g), 0), 2) AS protein_g,
    round(COALESCE(sum(carbs_g), 0), 2) AS carbs_g,
    round(COALESCE(sum(fat_g), 0), 2) AS fat_g
    FROM public.meal_logs WHERE snapshot_id = v_snapshot_id) AS totals
  WHERE snapshot.id = v_snapshot_id AND snapshot.user_id = p_user_id;
  GET DIAGNOSTICS v_changed_count = ROW_COUNT;
  IF v_changed_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'mobile meal snapshot publication incomplete' USING ERRCODE = '40001';
  END IF;
  SELECT * INTO v_snapshot FROM public.daily_snapshots WHERE id = v_snapshot_id;
  IF (to_jsonb(v_snapshot) - ARRAY['calories_consumed', 'protein_g', 'carbs_g', 'fat_g', 'daily_balance', 'updated_at'])
    IS DISTINCT FROM (v_before_snapshot - ARRAY['calories_consumed', 'protein_g', 'carbs_g', 'fat_g', 'daily_balance', 'updated_at']) THEN
    RAISE EXCEPTION 'mobile meal unrelated snapshot columns changed' USING ERRCODE = '40001';
  END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(meal) ORDER BY id), '[]'::jsonb) INTO v_after_retained
  FROM public.meal_logs AS meal WHERE snapshot_id = v_snapshot_id
    AND id = ANY(v_before_ids) AND NOT (id = ANY(p_item_ids));
  IF v_after_retained IS DISTINCT FROM v_before_retained THEN
    RAISE EXCEPTION 'mobile meal untouched rows changed' USING ERRCODE = '40001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.meal_logs WHERE id = ANY(p_item_ids)) THEN
    RAISE EXCEPTION 'mobile meal selected ids still present' USING ERRCODE = '40001';
  END IF;
  v_now := clock_timestamp();
  IF (v_now AT TIME ZONE v_timezone)::date IS DISTINCT FROM v_date THEN
    RAISE EXCEPTION 'mobile meal local date changed before completion' USING ERRCODE = '40001';
  END IF;
  SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::uuid[]) INTO v_remaining_group_ids
  FROM public.meal_logs WHERE user_id = p_user_id AND snapshot_id = v_snapshot_id
    AND ((v_anchor.raw_provider_message_id IS NULL AND id = ANY(v_new_ids))
      OR (v_anchor.raw_provider_message_id IS NOT NULL
        AND raw_provider_message_id = v_anchor.raw_provider_message_id));
  -- Public receipt allowlist accepted by root; method/status/owner stay in HTTP/ledger/auth.
  v_body := jsonb_build_object('data', jsonb_build_object(
    'record_id', p_record_id, 'operation', CASE WHEN p_request_method = 'PATCH' THEN 'updated' ELSE 'deleted' END,
    'removed_item_ids', to_jsonb(p_item_ids), 'new_item_ids', to_jsonb(v_new_ids),
    'next_record_id', CASE WHEN p_request_method = 'PATCH' THEN v_new_ids[1]
      ELSE v_remaining_group_ids[1] END,
    'snapshot', jsonb_build_object('id', v_snapshot.id, 'date', v_snapshot.date,
      'calories_consumed', v_snapshot.calories_consumed,
      'protein_g', v_snapshot.protein_g, 'carbs_g', v_snapshot.carbs_g, 'fat_g', v_snapshot.fat_g,
      'daily_balance', v_snapshot.daily_balance)),
    'meta', jsonb_build_object('api_version', 'v1', 'request_id', p_request_id));
  v_completed := public.complete_mobile_api_request(v_request.id, p_user_id, 200, v_body);
  IF v_completed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'mobile meal receipt completion failed' USING ERRCODE = '40001';
  END IF;
  RETURN jsonb_build_object('action', 'completed', 'response_status', 200, 'response_body', v_body);
END;
$$;

REVOKE ALL ON FUNCTION public.mutate_mobile_confirmed_meal(uuid, text, text, text, text,
  uuid, text, uuid[], jsonb, jsonb, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mutate_mobile_confirmed_meal(uuid, text, text, text, text,
  uuid, text, uuid[], jsonb, jsonb, text, jsonb, text) TO service_role;

-- Preserve completed C11 identity before generic expiry; all other routes retain their existing expiry behavior.
CREATE OR REPLACE FUNCTION public.claim_mobile_api_request(
  p_user_id uuid,
  p_idempotency_key text,
  p_request_method text,
  p_request_route text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_inserted_id uuid;
  v_request public.mobile_api_idempotency%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user id is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.mobile_api_idempotency (
    user_id,
    idempotency_key,
    request_method,
    request_route,
    request_hash,
    created_at,
    updated_at,
    expires_at
  ) VALUES (
    p_user_id,
    p_idempotency_key,
    upper(p_request_method),
    p_request_route,
    lower(p_request_hash),
    v_now,
    v_now,
    v_now + interval '24 hours'
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'action', 'claimed',
      'claim_id', v_inserted_id
    );
  END IF;

  SELECT *
  INTO v_request
  FROM public.mobile_api_idempotency
  WHERE user_id = p_user_id
    AND idempotency_key = p_idempotency_key
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'idempotency claim disappeared' USING ERRCODE = '40001';
  END IF;


IF v_request.state = 'completed'
  AND v_request.request_method IN ('PATCH', 'DELETE')
  AND v_request.request_route ~ '^/api/mobile/v1/meal-records/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
THEN
  IF v_request.request_method <> upper(p_request_method)
    OR v_request.request_route <> p_request_route
    OR v_request.request_hash <> lower(p_request_hash) THEN
    RETURN jsonb_build_object('action', 'conflict');
  END IF;
  RETURN jsonb_build_object('action', 'replay',
    'response_status', v_request.response_status, 'response_body', v_request.response_body);
END IF;

  IF v_request.expires_at <= v_now THEN
    UPDATE public.mobile_api_idempotency
    SET request_method = upper(p_request_method),
        request_route = p_request_route,
        request_hash = lower(p_request_hash),
        state = 'processing',
        response_status = NULL,
        response_body = NULL,
        attempt_count = 1,
        created_at = v_now,
        updated_at = v_now,
        expires_at = v_now + interval '24 hours'
    WHERE id = v_request.id;

    RETURN jsonb_build_object(
      'action', 'claimed',
      'claim_id', v_request.id
    );
  END IF;

  IF v_request.request_method <> upper(p_request_method)
    OR v_request.request_route <> p_request_route
    OR v_request.request_hash <> lower(p_request_hash) THEN
    RETURN jsonb_build_object('action', 'conflict');
  END IF;

  IF v_request.state = 'completed' THEN
    RETURN jsonb_build_object(
      'action', 'replay',
      'response_status', v_request.response_status,
      'response_body', v_request.response_body
    );
  END IF;

  IF v_request.state = 'processing'
    AND v_request.updated_at > v_now - interval '10 minutes' THEN
    RETURN jsonb_build_object('action', 'in_progress');
  END IF;

  UPDATE public.mobile_api_idempotency
  SET state = 'processing',
      response_status = NULL,
      response_body = NULL,
      attempt_count = attempt_count + 1,
      updated_at = v_now,
      expires_at = v_now + interval '24 hours'
  WHERE id = v_request.id;

  RETURN jsonb_build_object(
    'action', 'claimed',
    'claim_id', v_request.id
  );
END;
$$;

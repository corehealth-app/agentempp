BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
) VALUES
  ('00000000-0000-0000-0000-00000000b501', 'authenticated', 'authenticated', 'draft-a@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-00000000b502', 'authenticated', 'authenticated', 'draft-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

INSERT INTO public.users (id, auth_user_id, email, wpp, name, status, metadata)
VALUES
  ('00000000-0000-0000-0000-00000000b511', '00000000-0000-0000-0000-00000000b501', 'draft-a@example.com', NULL, 'Draft Patient A', 'active', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000b512', '00000000-0000-0000-0000-00000000b502', 'draft-b@example.com', NULL, 'Draft Patient B', 'active', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000b513', NULL, 'draft-c@example.com', NULL, 'Draft Patient Blocked', 'blocked', '{}'::jsonb);

INSERT INTO public.media_assets (
  id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
  status, source_request_hash, retention_until
) VALUES
  ('00000000-0000-0000-0000-00000000b521', '00000000-0000-0000-0000-00000000b511',
   'meal_photo', 'meal-photos',
   '00000000-0000-0000-0000-00000000b511/00000000-0000-0000-0000-00000000b521.jpg',
   'image/jpeg', 1024, 'pending_upload', repeat('d', 64), now() + interval '30 days');

INSERT INTO public.messages (id, user_id, direction, role, content_type, content, provider)
VALUES
  ('00000000-0000-0000-0000-00000000b531', '00000000-0000-0000-0000-00000000b511',
   'in', 'user', 'text', 'synthetic', 'mobile_flow');

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_a uuid := '00000000-0000-0000-0000-00000000b511';
  v_b uuid := '00000000-0000-0000-0000-00000000b512';
  v_blocked uuid := '00000000-0000-0000-0000-00000000b513';
  v_media uuid := '00000000-0000-0000-0000-00000000b521';
  v_message uuid := '00000000-0000-0000-0000-00000000b531';
  v_training jsonb := '{"plan_type":"split","equipment_summary":"halteres","notes":"nota","weekly_schedule":[{"day":"seg","focus":"inferiores","duration_min":60,"exercises":[{"name":"agachamento","muscle_group":"pernas","sets":3,"reps_range":"8-12","rest_seconds":90}]},{"day":"qua","focus":"superiores","duration_min":50,"exercises":[{"name":"supino","muscle_group":"peito","sets":3,"reps_range":"8-12","rest_seconds":90}]}]}'::jsonb;
  v_nutrition jsonb := '{"mode":"referencia","horizon":"daily","daily_meals":[{"meal_type":"almoco","items":[{"food_name":"arroz","quantity_g":120}]}],"shopping_list":[]}'::jsonb;
  v_result jsonb;
  v_draft uuid;
  v_second uuid;
  v_third uuid;
  v_nutrition_draft uuid;
  v_old_plan uuid;
  v_plan uuid;
  v_count integer;
  v_failed boolean;
  v_row record;
  v_fn text;
BEGIN
  -- 1. Privileges: clients execute nothing and write nothing.
  FOREACH v_fn IN ARRAY ARRAY[
    'public.create_plan_draft_atomic(uuid,text,text,text,jsonb,jsonb,jsonb,jsonb,uuid,uuid,jsonb,text)',
    'public.resolve_plan_draft_work_atomic(uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,jsonb,text)',
    'public.update_plan_draft_atomic(uuid,uuid,integer,jsonb,jsonb,boolean)',
    'public.discard_plan_draft_atomic(uuid,uuid)',
    'public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)',
    'public.save_training_plan_atomic(uuid,text,integer,text,jsonb,text,timestamptz,timestamptz,integer,text,text)',
    'private.replace_active_training_plan(uuid,text,integer,text,jsonb,text,timestamptz,timestamptz,integer,text,text,boolean)'
  ] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE')
      OR has_function_privilege('anon', v_fn, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'privileges are wrong for %', v_fn;
    END IF;
  END LOOP;

  IF has_table_privilege('anon', 'public.plan_drafts', 'SELECT')
    OR has_table_privilege('authenticated', 'public.plan_drafts', 'INSERT')
    OR has_table_privilege('authenticated', 'public.plan_drafts', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.plan_drafts', 'DELETE')
    OR has_column_privilege('authenticated', 'public.plan_drafts', 'payload', 'SELECT')
    OR has_column_privilege('authenticated', 'public.plan_drafts', 'extraction_payload', 'SELECT')
    OR has_column_privilege('authenticated', 'public.plan_drafts', 'request_key', 'SELECT')
    OR NOT has_column_privilege('authenticated', 'public.plan_drafts', 'status', 'SELECT')
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.plan_drafts'::regclass) THEN
    RAISE EXCEPTION 'plan_drafts exposure is wrong';
  END IF;

  -- A plan already in force, written before the draft.
  INSERT INTO public.training_plans (
    user_id, plan_type, days_per_week, weekly_schedule, generated_at, active
  ) VALUES (
    v_a, 'full_body', 1,
    '[{"day":"seg","focus":"full body","duration_min":30,"exercises":[]}]'::jsonb,
    now() - interval '10 days', true
  ) RETURNING id INTO v_old_plan;

  -- 2. A Flow proposal is a draft; the same request never creates another.
  v_result := public.create_plan_draft_atomic(
    v_a, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
    NULL, NULL, NULL, v_message, '{"method":"generator"}'::jsonb,
    'mobile_flow/a/key-0001:propoe_plano_treino');
  v_draft := (v_result->>'id')::uuid;
  IF NOT (v_result->>'inserted')::boolean
    OR v_result->>'status' <> 'ready_for_review'
    OR (v_result->>'payload_version')::int <> 1 THEN
    RAISE EXCEPTION 'draft not created: %', v_result;
  END IF;

  v_result := public.create_plan_draft_atomic(
    v_a, 'training', 'flow_generated', 'ready_for_review',
    '{"weekly_schedule":[]}'::jsonb, NULL, NULL, NULL, NULL, v_message, NULL,
    'mobile_flow/a/key-0001:propoe_plano_treino');
  IF (v_result->>'inserted')::boolean OR (v_result->>'id')::uuid <> v_draft THEN
    RAISE EXCEPTION 'replay created another draft: %', v_result;
  END IF;
  IF (SELECT payload FROM public.plan_drafts WHERE id = v_draft) <> v_training THEN
    RAISE EXCEPTION 'replay changed the draft';
  END IF;

  SELECT count(*) INTO v_count FROM public.training_plans WHERE user_id = v_a;
  IF v_count <> 1
    OR (SELECT base_active_plan_id FROM public.plan_drafts WHERE id = v_draft) <> v_old_plan THEN
    RAISE EXCEPTION 'creating a draft touched the plans or lost its base';
  END IF;

  -- 3. Isolation: B reaches nothing of A.
  FOR v_row IN SELECT unnest(ARRAY['update', 'confirm', 'discard', 'resolve']) AS op LOOP
    v_failed := false;
    BEGIN
      IF v_row.op = 'update' THEN
        PERFORM public.update_plan_draft_atomic(v_b, v_draft, 1, v_training, NULL, true);
      ELSIF v_row.op = 'confirm' THEN
        PERFORM public.confirm_plan_draft_atomic(v_b, v_draft, 1, NULL, 'confirm-key-b-0001');
      ELSIF v_row.op = 'discard' THEN
        PERFORM public.discard_plan_draft_atomic(v_b, v_draft);
      ELSE
        PERFORM public.resolve_plan_draft_work_atomic(
          v_b, v_draft, 'ready_for_review', v_training, NULL, NULL, NULL, NULL, NULL);
      END IF;
    EXCEPTION WHEN SQLSTATE 'PD404' THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN
      RAISE EXCEPTION 'patient B reached the draft of A through %', v_row.op;
    END IF;
  END LOOP;
  IF (SELECT status FROM public.plan_drafts WHERE id = v_draft) <> 'ready_for_review'
    OR (SELECT count(*) FROM public.training_plans WHERE user_id = v_b) <> 0 THEN
    RAISE EXCEPTION 'a refused operation changed something';
  END IF;

  -- B cannot anchor a draft on the media or the message of A.
  v_failed := false;
  BEGIN
    PERFORM public.create_plan_draft_atomic(
      v_b, 'training', 'imported_photo', 'extracting', NULL, NULL, NULL, NULL,
      v_media, NULL, NULL, 'plan-import:b-0001');
  EXCEPTION WHEN SQLSTATE 'PD404' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'B imported with the media of A'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.create_plan_draft_atomic(
      v_b, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
      NULL, NULL, NULL, v_message, NULL, 'mobile_flow/b/key-0001:propoe_plano_treino');
  EXCEPTION WHEN SQLSTATE 'PD404' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'B anchored a draft on the message of A'; END IF;

  -- The foreign keys say the same even to a direct write.
  v_failed := false;
  BEGIN
    INSERT INTO public.plan_drafts (
      user_id, domain, origin, status, source_media_asset_id, request_key
    ) VALUES (v_b, 'training', 'imported_photo', 'extracting', v_media, 'plan-import:b-0002');
  EXCEPTION WHEN foreign_key_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'foreign key accepted the media of A for B'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.create_plan_draft_atomic(
      v_blocked, 'training', 'flow_generated', 'ready_for_review', v_training,
      NULL, NULL, NULL, NULL, NULL, NULL, 'mobile_flow/c/key-0001:propoe_plano_treino');
  EXCEPTION WHEN SQLSTATE 'PD404' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'inactive patient got a draft'; END IF;

  -- 4. Edits: the reviewed version is the one that counts.
  v_failed := false;
  BEGIN
    PERFORM public.update_plan_draft_atomic(v_a, v_draft, 2, v_training, NULL, true);
  EXCEPTION WHEN SQLSTATE 'PD409' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'edit over another version accepted'; END IF;

  v_result := public.update_plan_draft_atomic(
    v_a, v_draft, 1, v_training || '{"notes":"editado"}'::jsonb,
    '[{"pointer":"/weekly_schedule/0/exercises/0/sets","reason":"missing"}]'::jsonb, false);
  IF (v_result->>'payload_version')::int <> 2 OR v_result->>'status' <> 'needs_completion' THEN
    RAISE EXCEPTION 'incomplete edit not recorded: %', v_result;
  END IF;

  -- An incomplete draft is never confirmed.
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_draft, 2, NULL, 'confirm-key-a-0001');
  EXCEPTION WHEN SQLSTATE 'PD422' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'incomplete draft confirmed'; END IF;

  v_result := public.update_plan_draft_atomic(
    v_a, v_draft, 2, v_training || '{"notes":"editado"}'::jsonb, NULL, true);
  IF (v_result->>'payload_version')::int <> 3 OR v_result->>'status' <> 'ready_for_review' THEN
    RAISE EXCEPTION 'complete edit not recorded: %', v_result;
  END IF;

  -- A version the patient did not review is refused.
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_draft, 2, NULL, 'confirm-key-a-0002');
  EXCEPTION WHEN SQLSTATE 'PD409' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'older version confirmed'; END IF;
  IF (SELECT count(*) FROM public.training_plans WHERE user_id = v_a) <> 1 THEN
    RAISE EXCEPTION 'a refused confirmation wrote a plan';
  END IF;

  -- Two more drafts written against the same plan.
  v_second := (public.create_plan_draft_atomic(
    v_a, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
    NULL, NULL, NULL, NULL, NULL, 'mobile_flow/a/key-0002:propoe_plano_treino')->>'id')::uuid;
  v_third := (public.create_plan_draft_atomic(
    v_a, 'training', 'imported_photo', 'extracting', NULL, NULL,
    NULL, NULL, v_media, NULL, NULL, 'plan-import:a-0001')->>'id')::uuid;

  -- 5. Confirmation: the draft becomes the active plan, with its origin.
  v_result := public.confirm_plan_draft_atomic(
    v_a, v_draft, 3, now() + interval '42 days', 'confirm-key-a-0003');
  v_plan := (v_result->>'confirmed_plan_id')::uuid;
  SELECT * INTO v_row FROM public.training_plans WHERE id = v_plan;
  IF v_result->>'status' <> 'confirmed'
    OR (v_result->>'already_confirmed')::boolean
    OR NOT v_row.active
    OR v_row.user_id <> v_a
    OR v_row.generated_by <> 'flow_draft'
    OR v_row.source_request_key <> 'plan-draft:' || v_draft::text
    OR v_row.plan_type <> 'split'
    OR v_row.days_per_week <> 2
    OR v_row.notes <> 'editado'
    OR v_row.weekly_schedule <> v_training -> 'weekly_schedule'
    OR (SELECT active FROM public.training_plans WHERE id = v_old_plan)
    OR (SELECT count(*) FROM public.training_plans WHERE user_id = v_a AND active) <> 1 THEN
    RAISE EXCEPTION 'confirmation did not produce the plan: % / %', v_result, v_row;
  END IF;

  -- A plan confirmed in the app never turns the WhatsApp delivery on.
  IF (SELECT metadata ? 'training_reminders' FROM public.users WHERE id = v_a) THEN
    RAISE EXCEPTION 'confirmation enabled training reminders';
  END IF;

  -- The same confirmation again: same plan, nothing written.
  v_result := public.confirm_plan_draft_atomic(
    v_a, v_draft, 3, now() + interval '42 days', 'confirm-key-a-0003');
  IF NOT (v_result->>'already_confirmed')::boolean
    OR (v_result->>'confirmed_plan_id')::uuid <> v_plan
    OR (SELECT count(*) FROM public.training_plans WHERE user_id = v_a) <> 2 THEN
    RAISE EXCEPTION 'repeated confirmation is not idempotent: %', v_result;
  END IF;

  -- 6. The other draft was reviewed against a plan that is no longer current.
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_second, 1, NULL, 'confirm-key-a-0004');
  EXCEPTION WHEN SQLSTATE 'PD412' THEN
    v_failed := true;
  END;
  IF NOT v_failed
    OR (SELECT count(*) FROM public.training_plans WHERE user_id = v_a) <> 2
    OR (SELECT status FROM public.plan_drafts WHERE id = v_second) <> 'ready_for_review' THEN
    RAISE EXCEPTION 'draft over a replaced plan was confirmed';
  END IF;

  -- A resolved draft is a record.
  v_failed := false;
  BEGIN
    UPDATE public.plan_drafts SET payload = '{}'::jsonb, payload_version = 9 WHERE id = v_draft;
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'confirmed draft was changed'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.discard_plan_draft_atomic(v_a, v_draft);
  EXCEPTION WHEN SQLSTATE 'PD422' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'confirmed draft was discarded'; END IF;

  -- 7. Discarding is final and repeatable.
  v_result := public.discard_plan_draft_atomic(v_a, v_second);
  v_result := public.discard_plan_draft_atomic(v_a, v_second);
  IF v_result->>'status' <> 'discarded' THEN
    RAISE EXCEPTION 'discard failed: %', v_result;
  END IF;
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_second, 1, NULL, 'confirm-key-a-0005');
  EXCEPTION WHEN SQLSTATE 'PD422' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'discarded draft confirmed'; END IF;

  -- 8. Extraction outcome: once, and only while in progress.
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_third, 1, NULL, 'confirm-key-a-0006');
  EXCEPTION WHEN SQLSTATE 'PD422' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'draft still extracting was confirmed'; END IF;

  v_result := public.resolve_plan_draft_work_atomic(
    v_a, v_third, 'needs_completion',
    '{"weekly_schedule":[{"day":"seg","focus":null,"exercises":[]}]}'::jsonb,
    '{"weekly_schedule":[{"day":"seg"}]}'::jsonb,
    '[{"pointer":"/weekly_schedule/0/focus","reason":"missing"}]'::jsonb,
    '["Tomar 1 comprimido de X"]'::jsonb,
    '{"method":"vision"}'::jsonb, NULL);
  IF NOT (v_result->>'applied')::boolean OR v_result->>'status' <> 'needs_completion' THEN
    RAISE EXCEPTION 'extraction outcome not applied: %', v_result;
  END IF;
  v_result := public.resolve_plan_draft_work_atomic(
    v_a, v_third, 'failed', NULL, NULL, NULL, NULL, NULL, 'extraction_failed');
  IF (v_result->>'applied')::boolean OR v_result->>'status' <> 'needs_completion' THEN
    RAISE EXCEPTION 'a second outcome replaced the first: %', v_result;
  END IF;
  IF (SELECT unrecognized_segments FROM public.plan_drafts WHERE id = v_third)
    <> '["Tomar 1 comprimido de X"]'::jsonb THEN
    RAISE EXCEPTION 'unrecognized text was not kept as it came';
  END IF;

  -- 9. An expired draft is not confirmed and reads as expired.
  UPDATE public.plan_drafts SET expires_at = now() - interval '1 minute' WHERE id = v_third;
  UPDATE public.plan_drafts SET status = 'ready_for_review' WHERE id = v_third;
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_third, 1, NULL, 'confirm-key-a-0007');
  EXCEPTION WHEN SQLSTATE 'PD410' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'expired draft confirmed'; END IF;
  v_failed := false;
  BEGIN
    PERFORM public.update_plan_draft_atomic(v_a, v_third, 1, v_training, NULL, true);
  EXCEPTION WHEN SQLSTATE 'PD410' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'expired draft edited'; END IF;

  -- 10. The WhatsApp save keeps its behaviour and takes part in the conflict.
  v_second := (public.create_plan_draft_atomic(
    v_a, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
    NULL, NULL, NULL, NULL, NULL, 'mobile_flow/a/key-0003:propoe_plano_treino')->>'id')::uuid;
  v_result := public.save_training_plan_atomic(
    v_a, 'full_body', 3, 'peso corporal',
    '[{"day":"seg","focus":"full body","duration_min":30,"exercises":[]}]'::jsonb,
    'agent', now(), now() + interval '42 days', 1, NULL, 'provider-training-draft-test');
  IF NOT (v_result->>'inserted')::boolean
    OR NOT (SELECT (metadata->>'training_reminders')::boolean FROM public.users WHERE id = v_a)
    OR (SELECT count(*) FROM public.training_plans WHERE user_id = v_a AND active) <> 1 THEN
    RAISE EXCEPTION 'WhatsApp save changed behaviour: %', v_result;
  END IF;
  v_result := public.save_training_plan_atomic(
    v_a, 'full_body', 3, 'peso corporal',
    '[{"day":"seg","focus":"full body","duration_min":30,"exercises":[]}]'::jsonb,
    'agent', now(), now() + interval '42 days', 1, NULL, 'provider-training-draft-test');
  IF (v_result->>'inserted')::boolean THEN
    RAISE EXCEPTION 'WhatsApp save is no longer idempotent';
  END IF;
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_second, 1, NULL, 'confirm-key-a-0008');
  EXCEPTION WHEN SQLSTATE 'PD412' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'draft confirmed over a plan saved meanwhile'; END IF;

  -- 11. A plan prescribed by a professional is never replaced by a draft.
  UPDATE public.training_plans SET generated_by = 'professional'
  WHERE user_id = v_a AND active;
  v_second := (public.create_plan_draft_atomic(
    v_a, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
    NULL, NULL, NULL, NULL, NULL, 'mobile_flow/a/key-0004:propoe_plano_treino')->>'id')::uuid;
  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_second, 1, NULL, 'confirm-key-a-0009');
  EXCEPTION WHEN SQLSTATE 'PD423' THEN
    v_failed := true;
  END;
  IF NOT v_failed
    OR (SELECT generated_by FROM public.training_plans WHERE user_id = v_a AND active)
      <> 'professional' THEN
    RAISE EXCEPTION 'prescribed plan was replaced';
  END IF;

  -- 12. Nutrition: insert only, with the same conflict rule.
  INSERT INTO public.prescriptions (user_id, type, payload, generated_at, valid_until)
  VALUES (v_a, 'combined', '{"daily_meals":[]}'::jsonb, now() - interval '1 hour', now() + interval '1 day');
  v_nutrition_draft := (public.create_plan_draft_atomic(
    v_a, 'nutrition', 'imported_pdf', 'ready_for_review', v_nutrition, NULL,
    NULL, '["Medicamento X 10 mg"]'::jsonb, v_media, NULL, NULL, 'plan-import:a-0002')->>'id')::uuid;
  v_second := (public.create_plan_draft_atomic(
    v_a, 'nutrition', 'flow_generated', 'ready_for_review', v_nutrition, NULL,
    NULL, NULL, NULL, NULL, NULL, 'mobile_flow/a/key-0005:propoe_plano_dieta')->>'id')::uuid;

  v_result := public.confirm_plan_draft_atomic(
    v_a, v_nutrition_draft, 1, now() + interval '30 days', 'confirm-key-a-0010');
  SELECT * INTO v_row FROM public.prescriptions
  WHERE id = (v_result->>'confirmed_plan_id')::uuid;
  IF v_row.user_id <> v_a
    OR v_row.generated_by <> 'patient_import'
    OR v_row.type <> 'diet'
    OR v_row.payload <> v_nutrition
    OR v_row.source_request_key <> 'plan-draft:' || v_nutrition_draft::text
    OR (SELECT count(*) FROM public.prescriptions WHERE user_id = v_a) <> 2
    OR (SELECT count(*) FROM public.prescriptions
        WHERE user_id = v_a AND payload = '{"daily_meals":[]}'::jsonb) <> 1 THEN
    RAISE EXCEPTION 'nutrition confirmation is wrong: % / %', v_result, v_row;
  END IF;

  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_second, 1, NULL, 'confirm-key-a-0011');
  EXCEPTION WHEN SQLSTATE 'PD412' THEN
    v_failed := true;
  END;
  IF NOT v_failed OR (SELECT count(*) FROM public.prescriptions WHERE user_id = v_a) <> 2 THEN
    RAISE EXCEPTION 'second nutrition draft confirmed over a newer prescription';
  END IF;

  -- No draft writes a routine item, a supplement or a medication.
  IF to_regclass('public.routine_items') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM public.routine_items WHERE user_id = $1' INTO v_count USING v_a;
    IF v_count <> 0 THEN RAISE EXCEPTION 'a draft wrote a routine item'; END IF;
  END IF;

  -- 13. Invalid requests are refused.
  FOR v_row IN
    SELECT * FROM (VALUES
      ('sleep', 'flow_generated', 'ready_for_review', 'valid-key-0001'),
      ('training', 'whatsapp', 'ready_for_review', 'valid-key-0002'),
      ('training', 'flow_generated', 'confirmed', 'valid-key-0003'),
      ('training', 'flow_generated', 'ready_for_review', 'short'),
      ('training', 'flow_generated', 'ready_for_review', 'has space in it')
    ) AS t(domain, origin, status, request_key)
  LOOP
    v_failed := false;
    BEGIN
      PERFORM public.create_plan_draft_atomic(
        v_b, v_row.domain, v_row.origin, v_row.status, v_training, NULL,
        NULL, NULL, NULL, NULL, NULL, v_row.request_key);
    EXCEPTION WHEN invalid_parameter_value THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'invalid draft accepted: %', v_row; END IF;
  END LOOP;

  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(v_a, v_second, 1, now() - interval '1 day', 'confirm-key-a-0012');
  EXCEPTION WHEN invalid_parameter_value THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'validity in the past accepted'; END IF;

  -- 14. Open drafts are bounded per patient.
  FOR v_count IN 1..20 LOOP
    PERFORM public.create_plan_draft_atomic(
      v_b, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
      NULL, NULL, NULL, NULL, NULL, 'mobile_flow/b/limit-' || lpad(v_count::text, 4, '0'));
  END LOOP;
  v_failed := false;
  BEGIN
    PERFORM public.create_plan_draft_atomic(
      v_b, 'training', 'flow_generated', 'ready_for_review', v_training, NULL,
      NULL, NULL, NULL, NULL, NULL, 'mobile_flow/b/limit-0021');
  EXCEPTION WHEN SQLSTATE 'PD429' THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'open draft limit not enforced'; END IF;
END;
$test$;

-- 15. The patient sees that own drafts exist, never their content, and
--     never another patient's; and executes none of the RPCs.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000b501","role":"authenticated"}',
  true
);

DO $test$
DECLARE
  v_own integer;
  v_cross integer;
  v_failed boolean := false;
BEGIN
  SELECT count(*) INTO v_own FROM public.plan_drafts
  WHERE user_id = '00000000-0000-0000-0000-00000000b511';
  SELECT count(*) INTO v_cross FROM public.plan_drafts
  WHERE user_id = '00000000-0000-0000-0000-00000000b512';
  IF v_own < 1 OR v_cross <> 0 THEN
    RAISE EXCEPTION 'draft ownership failed: own %, cross %', v_own, v_cross;
  END IF;

  BEGIN
    PERFORM payload FROM public.plan_drafts LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'client read the draft content'; END IF;

  v_failed := false;
  BEGIN
    UPDATE public.plan_drafts SET status = 'confirmed';
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'client updated a draft'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.confirm_plan_draft_atomic(
      '00000000-0000-0000-0000-00000000b511',
      (SELECT id FROM public.plan_drafts LIMIT 1), 1, NULL, 'confirm-key-client-1');
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'client executed the confirmation'; END IF;
END;
$test$;

ROLLBACK;

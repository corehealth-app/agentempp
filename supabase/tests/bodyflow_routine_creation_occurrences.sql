-- Physical 2026-10-01: item created 17:13:42Z, rules at 15:00/15:05Z,
-- list/UI advertised Pending/Tomado, writer returned routine_occurrence_not_found.
-- Disposable synthetic fixture, rolled back; no clock or write guard override.
BEGIN;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
DO $test$
DECLARE
  v_auth uuid := gen_random_uuid();
  v_user uuid := gen_random_uuid();
  v_other_auth uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_item uuid := gen_random_uuid();
  v_rule_a uuid := gen_random_uuid();
  v_rule_b uuid := gen_random_uuid();
  v_created timestamptz := '2026-10-01T17:13:42.060899Z';
  v_now timestamptz := '2026-10-01T17:54:18.238487Z';
  v_page jsonb;
  v_schedule jsonb;
  v_next jsonb;
  v_rule uuid;
  v_scheduled timestamptz;
BEGIN
  INSERT INTO auth.users(id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, 'authenticated', 'authenticated', v_auth::text||'@example.invalid',
    '', v_created, '{"provider":"email","providers":["email"]}', '{}', v_created, v_created, false, false),
    (v_other_auth, 'authenticated', 'authenticated', v_other_auth::text||'@example.invalid',
    '', v_created, '{"provider":"email","providers":["email"]}', '{}', v_created, v_created, false, false);
  INSERT INTO public.users(id, auth_user_id, email, timezone)
  VALUES (v_user, v_auth, v_auth::text||'@example.invalid', 'America/Sao_Paulo'),
    (v_other, v_other_auth, v_other_auth::text||'@example.invalid', 'America/Sao_Paulo');
  INSERT INTO public.routine_items(id,user_id,item_type,name,dose_text,origin,
    reminders_enabled,active,created_at,updated_at)
  VALUES(v_item,v_user,'supplement','QA smoke — não ingerir',
    'Somente teste de interface','other',false,true,v_created,v_created);
  INSERT INTO public.reminder_rules(id,user_id,routine_item_id,category,
    local_time,weekdays,active,created_at)
  VALUES(v_rule_a,v_user,v_item,'supplement','12:00',ARRAY[0,1,2,3,4,5,6],true,v_created),
    (v_rule_b,v_user,v_item,'supplement','12:05',ARRAY[0,1,2,3,4,5,6],true,v_created);
  v_page := public.list_mobile_routine_items(v_user,'supplement',false,v_now);
  IF jsonb_array_length(v_page->'items') <> 1
    OR jsonb_array_length(v_page->'items'->0->'schedules') <> 2
    OR v_page->'items'->0->>'reminders_enabled' <> 'false' THEN
    RAISE EXCEPTION 'exact creation fixture lost configured schedules/item';
  END IF;
  FOR v_schedule IN SELECT value FROM jsonb_array_elements(v_page->'items'->0->'schedules') LOOP
    IF v_schedule->'occurrence' IS DISTINCT FROM 'null'::jsonb THEN
      RAISE EXCEPTION 'pre-creation schedule advertised an actionable occurrence: %',v_schedule->>'local_time';
    END IF;
  END LOOP;
  -- The writer remains strict: never invent backdated snapshots to fix the UI.
  FOR v_rule,v_scheduled IN SELECT v_rule_a,timestamptz '2026-10-01T15:00Z'
    UNION ALL SELECT v_rule_b,timestamptz '2026-10-01T15:05Z' LOOP
    BEGIN
      PERFORM public.record_routine_occurrence_action_atomic(v_user,v_item,'supplement',
        v_rule,v_scheduled,'taken',v_now,NULL,'creation-regression-'||v_rule::text);
      RAISE EXCEPTION 'pre-creation occurrence unexpectedly accepted';
    EXCEPTION WHEN no_data_found THEN
      IF SQLERRM <> 'routine_occurrence_not_found' THEN RAISE; END IF;
    END;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.routine_adherence_logs WHERE routine_item_id=v_item) THEN
    RAISE EXCEPTION 'pre-creation fixture wrote adherence logs';
  END IF;
  v_next := public.list_mobile_routine_items(v_user,'supplement',false,'2026-10-02T17:54:18Z');
  FOR v_schedule IN SELECT value FROM jsonb_array_elements(v_next->'items'->0->'schedules') LOOP
    IF v_schedule->'occurrence'->>'status' IS DISTINCT FROM 'pending'
      OR (v_schedule->'occurrence'->>'scheduled_for')::timestamptz NOT IN
        (timestamptz '2026-10-02T15:00Z',timestamptz '2026-10-02T15:05Z') THEN
      RAISE EXCEPTION 'valid next-day occurrence was hidden or changed';
    END IF;
  END LOOP;
  -- A non-scheduled weekday must stay visible and null without calling the
  -- resolver with a null timestamp/key (SQL AND order is not guaranteed).
  UPDATE public.reminder_rules SET weekdays=ARRAY[1] WHERE id=v_rule_a;
  v_page := public.list_mobile_routine_items(v_user,'supplement',false,v_now);
  SELECT value INTO v_schedule FROM jsonb_array_elements(v_page->'items'->0->'schedules')
    WHERE value->>'id'=v_rule_a::text;
  IF v_schedule IS NULL OR v_schedule->'occurrence' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'non-scheduled weekday was hidden or not null';
  END IF;
  IF jsonb_array_length(public.list_mobile_routine_items(v_other,'supplement',false,v_now)->'items') <> 0 THEN
    RAISE EXCEPTION 'routine creation fixture leaked to other owner';
  END IF;
END;
$test$;
ROLLBACK;

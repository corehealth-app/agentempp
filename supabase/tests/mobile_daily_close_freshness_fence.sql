-- Standalone/local only. Fixtures roll back; never run against patient data.
BEGIN;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';

CREATE FUNCTION pg_temp.mobile_close(
  owner_id uuid, snapshot_id uuid, local_date date, zone text,
  expected_snapshot jsonb, expected_profile jsonb, expected_progress jsonb
) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.finalize_mobile_daily_close_atomic(
    owner_id, snapshot_id, 'complete', 15, 1, 1, 1, 0, 576, ARRAY[]::text[],
    local_date, clock_timestamp(), zone, expected_snapshot, expected_profile, expected_progress)
$$;

DO $test$
DECLARE
  v_user uuid := '0b9f6f0e-0000-4000-8000-00000000c126';
  v_other uuid := '0b9f6f0e-0000-4000-8000-00000000c127';
  v_new uuid := '0b9f6f0e-0000-4000-8000-00000000c129';
  v_date date := (clock_timestamp() AT TIME ZONE 'Pacific/Honolulu')::date - 2;
  v_snapshot jsonb;
  v_profile jsonb;
  v_progress jsonb;
  v_other_before jsonb;
  v_id uuid;
  v_result jsonb;
  v_live jsonb;
  v_signature text := 'public.finalize_mobile_daily_close_atomic(uuid,uuid,text,integer,integer,integer,integer,integer,integer,text[],date,timestamptz,text,jsonb,jsonb,jsonb)';
BEGIN
  INSERT INTO public.users(id, wpp, timezone, name)
    VALUES(v_user, NULL, 'Pacific/Honolulu', 'synthetic-c11-m5'),
          (v_other, NULL, 'Pacific/Honolulu', 'synthetic-c11-other');
  INSERT INTO public.user_profiles(user_id, current_protocol, deficit_level)
    VALUES(v_user, 'recomposicao', 500);
  INSERT INTO public.user_progress(user_id) VALUES(v_user), (v_other);
  INSERT INTO public.daily_snapshots(user_id, date, calories_consumed, calories_target)
    VALUES(v_user, v_date, 1000, 1576) RETURNING id INTO v_id;
  SELECT to_jsonb(s) INTO v_snapshot FROM public.daily_snapshots s WHERE id = v_id;
  SELECT to_jsonb(p) INTO v_profile FROM public.user_profiles p WHERE user_id = v_user;
  SELECT jsonb_build_object('xp_total',xp_total,'level',level,'current_streak',current_streak,
    'longest_streak',longest_streak,'blocks_completed',blocks_completed,'deficit_block',deficit_block,
    'badges_earned',badges_earned,'last_active_date',last_active_date,'updated_at',updated_at)
    INTO v_progress FROM public.user_progress WHERE user_id = v_user;
  SELECT to_jsonb(p) INTO v_other_before FROM public.user_progress p WHERE user_id = v_other;

  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Asia/Tokyo',v_snapshot,v_profile,v_progress);
  IF v_result->>'reason' IS DISTINCT FROM 'context_changed' THEN
    RAISE EXCEPTION 'stale timezone was not refused: %',v_result;
  END IF;
  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',
    jsonb_set(v_snapshot,'{calories_consumed}','500'),v_profile,v_progress);
  IF v_result->>'reason' IS DISTINCT FROM 'snapshot_changed' THEN
    RAISE EXCEPTION 'stale snapshot was not refused: %',v_result;
  END IF;
  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',v_snapshot,
    jsonb_set(v_profile,'{deficit_level}','400'),v_progress);
  IF v_result->>'reason' IS DISTINCT FROM 'profile_changed' THEN
    RAISE EXCEPTION 'stale profile was not refused: %',v_result;
  END IF;
  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',v_snapshot,v_profile,
    jsonb_set(v_progress,'{xp_total}','1'));
  IF v_result->>'reason' IS DISTINCT FROM 'progress_changed' THEN
    RAISE EXCEPTION 'stale progress was not refused: %',v_result;
  END IF;
  SELECT to_jsonb(s) INTO v_live FROM public.daily_snapshots s WHERE id = v_id;
  IF v_live IS DISTINCT FROM v_snapshot THEN RAISE EXCEPTION 'refusal changed snapshot'; END IF;

  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',
    v_snapshot - 'updated_at',v_profile,v_progress);
  IF v_result->>'reason' IS DISTINCT FROM 'snapshot_changed' THEN
    RAISE EXCEPTION 'missing snapshot key accepted';
  END IF;
  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',v_snapshot,
    v_profile || '{"invented":true}',v_progress);
  IF v_result->>'reason' IS DISTINCT FROM 'profile_changed' THEN
    RAISE EXCEPTION 'extra profile key accepted';
  END IF;

  IF has_function_privilege('anon',v_signature,'EXECUTE') OR
    has_function_privilege('authenticated',v_signature,'EXECUTE') OR
    NOT has_function_privilege('service_role',v_signature,'EXECUTE') THEN
    RAISE EXCEPTION 'mobile finalizer ACL failed';
  END IF;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',v_snapshot,v_profile,v_progress);
    RAISE EXCEPTION 'untrusted JWT role accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);

  -- Equivalent, precision-preserving ISO offsets emitted by SDK/transport
  -- must compare as the same typed timestamps, without dropping any field.
  SELECT jsonb_set(v_snapshot,'{updated_at}',to_jsonb(
    to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z'))
    INTO v_snapshot FROM public.daily_snapshots WHERE id = v_id;
  SELECT jsonb_set(v_profile,'{updated_at}',to_jsonb(
    to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z'))
    INTO v_profile FROM public.user_profiles WHERE user_id = v_user;
  SELECT jsonb_set(v_progress,'{updated_at}',to_jsonb(
    to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z'))
    INTO v_progress FROM public.user_progress WHERE user_id = v_user;
  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',v_snapshot,v_profile,v_progress);
  IF v_result->'applied' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'equivalent timestamp context falsely refused: %',v_result;
  END IF;
  SELECT to_jsonb(p) INTO v_live FROM public.user_progress p WHERE user_id = v_other;
  IF v_live IS DISTINCT FROM v_other_before THEN RAISE EXCEPTION 'other account changed'; END IF;
  v_result := pg_temp.mobile_close(v_user,v_id,v_date,'Pacific/Honolulu',v_snapshot,v_profile,v_progress);
  IF v_result->>'reason' IS DISTINCT FROM 'already_closed' THEN
    RAISE EXCEPTION 'closed replay did not preserve prior result: %',v_result;
  END IF;

  -- No progress row exists. A refused current day cannot initialize it;
  -- a delegated error must roll our own insertion back; a valid close may
  -- initialize the standard row exactly once in the same transaction.
  INSERT INTO public.users(id,wpp,timezone,name)
    VALUES(v_new,NULL,'Pacific/Honolulu','synthetic-c11-null-progress');
  INSERT INTO public.user_profiles(user_id,current_protocol,deficit_level)
    VALUES(v_new,'recomposicao',500);
  INSERT INTO public.daily_snapshots(user_id,date,calories_consumed,calories_target)
    VALUES(v_new,(clock_timestamp() AT TIME ZONE 'Pacific/Honolulu')::date,1000,1576)
    RETURNING id INTO v_id;
  SELECT to_jsonb(s) INTO v_snapshot FROM public.daily_snapshots s WHERE id=v_id;
  SELECT to_jsonb(p) INTO v_profile FROM public.user_profiles p WHERE user_id=v_new;
  v_result := pg_temp.mobile_close(v_new,v_id,(v_snapshot->>'date')::date,
    'Pacific/Honolulu',v_snapshot,v_profile,NULL);
  IF v_result->>'reason' IS DISTINCT FROM 'not_closable' OR
    EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=v_new) THEN
    RAISE EXCEPTION 'current day closed or refused request initialized progress';
  END IF;
  UPDATE public.daily_snapshots SET date=v_date WHERE id=v_id;
  SELECT to_jsonb(s) INTO v_snapshot FROM public.daily_snapshots s WHERE id=v_id;
  BEGIN
    PERFORM public.finalize_mobile_daily_close_atomic(
      v_new,v_id,'complete',-1,1,1,1,0,576,ARRAY[]::text[],v_date,clock_timestamp(),
      'Pacific/Honolulu',v_snapshot,v_profile,NULL);
    RAISE EXCEPTION 'invalid delegation payload accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'invalid daily close payload' THEN RAISE; END IF;
  END;
  SELECT to_jsonb(s) INTO v_live FROM public.daily_snapshots s WHERE id=v_id;
  IF v_live IS DISTINCT FROM v_snapshot OR
    EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=v_new) THEN
    RAISE EXCEPTION 'delegation error left a partial snapshot/progress row';
  END IF;
  v_result := pg_temp.mobile_close(v_new,v_id,v_date,'Pacific/Honolulu',v_snapshot,v_profile,NULL);
  IF v_result->'applied' IS DISTINCT FROM 'true'::jsonb OR
    (SELECT xp_total FROM public.user_progress WHERE user_id=v_new) IS DISTINCT FROM 15 THEN
    RAISE EXCEPTION 'own progress initialization failed';
  END IF;
END;
$test$;

DO $reset$
DECLARE
  u uuid := '0b9f6f0e-0000-4000-8000-00000000c133';
  today date := (clock_timestamp() AT TIME ZONE 'Pacific/Honolulu')::date;
  latest date;
  expected jsonb;
  before_row jsonb;
  actual jsonb;
  result jsonb;
  signature text := 'public.reset_mobile_inactive_streak_atomic(uuid,text,jsonb,date)';
BEGIN
  latest := today-CASE WHEN clock_timestamp()-(today::timestamp AT TIME ZONE 'Pacific/Honolulu')
    >= interval '30 minutes' THEN 1 ELSE 2 END;
  INSERT INTO users(id,wpp,timezone,name) VALUES(u,NULL,'Pacific/Honolulu','synthetic-c11-reset');
  INSERT INTO user_progress(user_id,xp_total,current_streak,longest_streak,last_active_date)
    VALUES(u,40,3,3,latest-1);
  SELECT to_jsonb(p),jsonb_build_object('current_streak',current_streak,
    'last_active_date',last_active_date,'updated_at',updated_at)
    INTO before_row,expected FROM user_progress p WHERE user_id=u;
  result := public.reset_mobile_inactive_streak_atomic(u,'Asia/Tokyo',expected,latest+1);
  IF result->>'reason' IS DISTINCT FROM 'context_changed' THEN
    RAISE EXCEPTION 'reset accepted stale official timezone';
  END IF;
  result := public.reset_mobile_inactive_streak_atomic(u,'Pacific/Honolulu',expected,latest+1);
  IF result->>'reason' IS DISTINCT FROM 'context_changed' THEN
    RAISE EXCEPTION 'reset accepted old calendar';
  END IF;
  result := public.reset_mobile_inactive_streak_atomic(u,'Pacific/Honolulu',expected,latest);
  IF result->>'reason' IS DISTINCT FROM 'not_inactive' THEN
    RAISE EXCEPTION 'reset ignored the tolerated empty day';
  END IF;
  result := public.reset_mobile_inactive_streak_atomic(u,'Pacific/Honolulu',
    expected || '{"invented":true}',latest);
  IF result->>'reason' IS DISTINCT FROM 'progress_changed' THEN
    RAISE EXCEPTION 'reset accepted extra progress key';
  END IF;
  result := public.reset_mobile_inactive_streak_atomic(u,'Pacific/Honolulu',
    jsonb_set(expected,'{current_streak}','4'),latest);
  IF result->>'reason' IS DISTINCT FROM 'progress_changed' THEN
    RAISE EXCEPTION 'reset accepted changed progress';
  END IF;
  SELECT to_jsonb(p) INTO actual FROM user_progress p WHERE user_id=u;
  IF actual IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'refused reset changed whole progress'; END IF;
  IF has_function_privilege('anon',signature,'EXECUTE') OR
    has_function_privilege('authenticated',signature,'EXECUTE') OR
    NOT has_function_privilege('service_role',signature,'EXECUTE') THEN
    RAISE EXCEPTION 'reset ACL failed';
  END IF;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.reset_mobile_inactive_streak_atomic(u,'Pacific/Honolulu',expected,latest);
    RAISE EXCEPTION 'reset accepted untrusted JWT role';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE user_progress SET last_active_date=latest-2 WHERE user_id=u;
  SELECT to_jsonb(p),jsonb_build_object('current_streak',current_streak,
    'last_active_date',last_active_date,'updated_at',
      to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z')
    INTO before_row,expected FROM user_progress p WHERE user_id=u;
  result := public.reset_mobile_inactive_streak_atomic(u,'Pacific/Honolulu',expected,latest);
  IF result IS DISTINCT FROM jsonb_build_object('applied',true,'user_id',u,
    'previous_streak',3,'last_active_date',latest-2,'gap_days',2,'latest_closable_date',latest) THEN
    RAISE EXCEPTION 'valid inactivity reset failed: %',result;
  END IF;
  SELECT to_jsonb(p) INTO actual FROM user_progress p WHERE user_id=u;
  IF (actual - ARRAY['current_streak','updated_at']) IS DISTINCT FROM
    (before_row - ARRAY['current_streak','updated_at']) OR actual->>'current_streak' <> '0' THEN
    RAISE EXCEPTION 'reset changed unrelated progress fields';
  END IF;
END;
$reset$;
ROLLBACK;

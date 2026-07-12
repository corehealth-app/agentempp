BEGIN;

DO $test$
DECLARE
  v_wpp text := '15550000444';
  v_user_id uuid;
  v_retry_user_id uuid;
  v_profile_count integer;
  v_progress_count integer;
BEGIN
  INSERT INTO public.users (wpp, status)
  VALUES (v_wpp, 'active')
  RETURNING id INTO v_user_id;

  -- Existing partially initialized users are repaired in the same transaction.
  v_retry_user_id := public.ensure_user_initialized(v_wpp);

  SELECT count(*) INTO v_profile_count
  FROM public.user_profiles
  WHERE user_id = v_user_id;

  SELECT count(*) INTO v_progress_count
  FROM public.user_progress
  WHERE user_id = v_user_id;

  IF v_retry_user_id <> v_user_id
    OR v_profile_count <> 1
    OR v_progress_count <> 1 THEN
    RAISE EXCEPTION 'partial user was not repaired: user %, retry %, profile %, progress %',
      v_user_id, v_retry_user_id, v_profile_count, v_progress_count;
  END IF;

  -- Repeated delivery is idempotent and cannot create duplicate children.
  IF public.ensure_user_initialized(v_wpp) <> v_user_id THEN
    RAISE EXCEPTION 'retry returned a different user';
  END IF;

  SELECT count(*) INTO v_profile_count
  FROM public.user_profiles
  WHERE user_id = v_user_id;

  SELECT count(*) INTO v_progress_count
  FROM public.user_progress
  WHERE user_id = v_user_id;

  IF v_profile_count <> 1 OR v_progress_count <> 1 THEN
    RAISE EXCEPTION 'retry duplicated children: profile %, progress %',
      v_profile_count, v_progress_count;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.ensure_user_initialized(text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute ensure_user_initialized';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.ensure_user_initialized(text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute ensure_user_initialized';
  END IF;
END;
$test$;

ROLLBACK;

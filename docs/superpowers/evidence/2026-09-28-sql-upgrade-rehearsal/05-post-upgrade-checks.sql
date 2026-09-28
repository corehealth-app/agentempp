-- Post-upgrade checks after M1-M4. Runs inside BEGIN/ROLLBACK: it writes
-- only to prove the writers and leaves nothing behind. LOCAL REHEARSAL ONLY.
\set ON_ERROR_STOP on
BEGIN;
DO $checks$
DECLARE
  A constant uuid := '00000000-0000-0000-0000-00000000ea01';
  B constant uuid := '00000000-0000-0000-0000-00000000eb01';
  r record;
  v jsonb;
  v_bad text;
BEGIN
  -- 1. Legacy rows are not backfilled: a weight written before M1 keeps no instant.
  SELECT weight_kg, weight_measured_at, weight_instant_source INTO r FROM public.user_profiles WHERE user_id = A;
  IF r.weight_kg <> 82.4 OR r.weight_measured_at IS NOT NULL OR r.weight_instant_source IS NOT NULL THEN
    RAISE EXCEPTION 'CHECK 1: legacy weight row changed by the upgrade: %', row_to_json(r);
  END IF;

  -- 2. Legacy writer (direct weight_kg update) keeps working and is dated as
  --    the write instant, labelled "recorded", never "measured".
  UPDATE public.user_profiles SET weight_kg = 81.9 WHERE user_id = A;
  SELECT weight_kg, weight_measured_at, weight_instant_source INTO r FROM public.user_profiles WHERE user_id = A;
  IF r.weight_instant_source IS DISTINCT FROM 'recorded' OR r.weight_measured_at IS NULL THEN
    RAISE EXCEPTION 'CHECK 2: legacy weight writer not labelled recorded: %', row_to_json(r);
  END IF;

  -- 3. Legacy media writer: every pre-M3 kind can still be inserted.
  INSERT INTO public.media_assets (id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
    status, source_request_hash, retention_until)
  VALUES ('00000000-0000-0000-0000-00000000aa11', A, 'meal_photo', 'meal-photos',
    '00000000-0000-0000-0000-00000000ea01/00000000-0000-0000-0000-00000000aa11.jpg', 'image/jpeg', 1000,
    'pending_upload', repeat('6', 64), now() + interval '30 days');

  -- 4. Legacy plan writers keep working; the new column stays NULL for them.
  INSERT INTO public.prescriptions (user_id, type, payload) VALUES (B, 'diet', '{"meals":[]}');
  IF EXISTS (SELECT 1 FROM public.prescriptions WHERE user_id = B AND source_request_key IS NOT NULL) THEN
    RAISE EXCEPTION 'CHECK 4: legacy prescription got a request key';
  END IF;

  -- 5. New objects are reachable only by the trusted backend.
  SELECT string_agg(sig, ', ') INTO v_bad FROM (
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('record_weight_atomic', 'create_plan_draft_atomic', 'update_plan_draft_atomic',
                        'resolve_plan_draft_work_atomic', 'confirm_plan_draft_atomic', 'discard_plan_draft_atomic',
                        'reset_user_conversation_atomic', 'save_training_plan_atomic')
      AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
           OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE'))
  ) s;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CHECK 5: wrong EXECUTE grants on %', v_bad; END IF;

  SELECT string_agg(sig, ', ') INTO v_bad FROM (
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private'
      AND p.proname IN ('apply_weight_measurement', 'sync_weight_measured_at', 'plan_draft_dto',
                        'enforce_plan_draft_transition', 'replace_active_training_plan')
      AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  ) s;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CHECK 5b: private helper executable by a client role: %', v_bad; END IF;

  -- 6. plan_drafts: RLS on, no client table privilege.
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.plan_drafts'::regclass) THEN
    RAISE EXCEPTION 'CHECK 6: RLS disabled on plan_drafts';
  END IF;
  IF has_table_privilege('anon', 'public.plan_drafts', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.plan_drafts', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'CHECK 6: client role has a table privilege on plan_drafts';
  END IF;
  IF has_column_privilege('anon', 'public.user_profiles', 'weight_instant_source', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.user_profiles', 'weight_instant_source', 'UPDATE') THEN
    RAISE EXCEPTION 'CHECK 6b: client role can write the weight instant source';
  END IF;

  -- 7. plan-documents bucket is private and bounded.
  SELECT public, file_size_limit, allowed_mime_types INTO r FROM storage.buckets WHERE id = 'plan-documents';
  IF r.public OR r.file_size_limit IS NULL THEN
    RAISE EXCEPTION 'CHECK 7: plan-documents bucket not private/bounded: %', row_to_json(r);
  END IF;

  -- 8. Every index is valid and ready.
  SELECT string_agg(indexrelid::regclass::text, ', ') INTO v_bad
  FROM pg_index WHERE NOT (indisvalid AND indisready);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CHECK 8: invalid indexes: %', v_bad; END IF;

  -- 9. The legacy one-argument reset (still called by any old backend) keeps plans.
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v := public.reset_user_conversation_atomic(A);
  IF NOT EXISTS (SELECT 1 FROM public.prescriptions WHERE user_id = A)
     OR NOT EXISTS (SELECT 1 FROM public.training_plans WHERE user_id = A) THEN
    RAISE EXCEPTION 'CHECK 9: legacy reset removed plans: %', v;
  END IF;

  RAISE NOTICE 'POST-UPGRADE CHECKS OK (1-9)';
END;
$checks$;
ROLLBACK;

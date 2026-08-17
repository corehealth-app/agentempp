BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000449';
  v_claim jsonb;
  v_same_claim jsonb;
  v_busy jsonb;
  v_final jsonb;
  v_retry_final jsonb;
  v_attempt_id uuid;
  v_message_count integer;
  v_event_count integer;
  v_snapshot_status text;
  v_snapshot_sent_at timestamptz;
  v_failed_claim jsonb;
  v_reclaim jsonb;
BEGIN
  INSERT INTO public.users (id, wpp, status)
  VALUES (v_user_id, '15550000449', 'active')
  ON CONFLICT (id) DO NOTHING;

  v_claim := public.claim_daily_gap_reminder(
    v_user_id,
    date '2026-07-12',
    'inngest-run-1',
    '["jantar"]'::jsonb,
    timestamptz '2026-07-12 23:00:00+00'
  );
  v_attempt_id := (v_claim->>'attempt_id')::uuid;

  v_same_claim := public.claim_daily_gap_reminder(
    v_user_id,
    date '2026-07-12',
    'inngest-run-1',
    '["jantar"]'::jsonb,
    timestamptz '2026-07-12 23:01:00+00'
  );
  v_busy := public.claim_daily_gap_reminder(
    v_user_id,
    date '2026-07-12',
    'inngest-run-2',
    '["jantar"]'::jsonb,
    timestamptz '2026-07-12 23:01:00+00'
  );

  IF v_claim->>'status' <> 'claimed'
    OR (v_same_claim->>'attempt_id')::uuid <> v_attempt_id
    OR v_busy->>'status' <> 'busy' THEN
    RAISE EXCEPTION 'daily gap claim is not idempotent: claim %, same %, busy %',
      v_claim, v_same_claim, v_busy;
  END IF;

  v_final := public.finalize_daily_gap_reminder(
    v_attempt_id,
    'inngest-run-1',
    'whatsapp_cloud',
    'wamid-gap-delivery-1',
    'Lembrete de jantar',
    timestamptz '2026-07-12 23:02:00+00',
    10,
    22
  );

  v_retry_final := public.finalize_daily_gap_reminder(
    v_attempt_id,
    'inngest-run-1',
    'whatsapp_cloud',
    'wamid-gap-delivery-1',
    'Lembrete de jantar',
    timestamptz '2026-07-12 23:02:00+00',
    10,
    22
  );

  SELECT count(*) INTO v_message_count
  FROM public.messages
  WHERE provider = 'whatsapp_cloud'
    AND provider_message_id = 'wamid-gap-delivery-1';
  SELECT count(*) INTO v_event_count
  FROM public.product_events
  WHERE user_id = v_user_id
    AND event = 'daily.gap_reminder_sent';
  SELECT day_status, gap_reminder_sent_at
  INTO v_snapshot_status, v_snapshot_sent_at
  FROM public.daily_snapshots
  WHERE user_id = v_user_id AND date = date '2026-07-12';

  IF NOT (v_final->>'applied')::boolean
    OR (v_retry_final->>'applied')::boolean
    OR v_message_count <> 1
    OR v_event_count <> 1
    OR v_snapshot_status <> 'pending_close'
    OR v_snapshot_sent_at <> timestamptz '2026-07-12 23:02:00+00' THEN
    RAISE EXCEPTION 'daily gap finalization failed: first %, retry %, messages %, events %, status %, sent %',
      v_final, v_retry_final, v_message_count, v_event_count,
      v_snapshot_status, v_snapshot_sent_at;
  END IF;

  v_busy := public.claim_daily_gap_reminder(
    v_user_id,
    date '2026-07-12',
    'inngest-run-2',
    '["jantar"]'::jsonb,
    timestamptz '2026-07-12 23:03:00+00'
  );
  IF v_busy->>'status' <> 'already_sent' THEN
    RAISE EXCEPTION 'sent reminder was claimed again: %', v_busy;
  END IF;

  v_failed_claim := public.claim_daily_gap_reminder(
    v_user_id,
    date '2026-07-13',
    'inngest-run-3',
    '["almoco"]'::jsonb,
    timestamptz '2026-07-13 23:00:00+00'
  );
  IF NOT public.fail_daily_gap_reminder(
    (v_failed_claim->>'attempt_id')::uuid,
    'inngest-run-3',
    'provider failed',
    timestamptz '2026-07-13 23:01:00+00'
  ) THEN
    RAISE EXCEPTION 'failed delivery was not marked failed';
  END IF;

  v_reclaim := public.claim_daily_gap_reminder(
    v_user_id,
    date '2026-07-13',
    'inngest-run-4',
    '["almoco"]'::jsonb,
    timestamptz '2026-07-13 23:02:00+00'
  );

  IF v_reclaim->>'status' <> 'claimed'
    OR (v_reclaim->>'attempt_id')::uuid = (v_failed_claim->>'attempt_id')::uuid
    OR EXISTS (
      SELECT 1
      FROM public.daily_snapshots
      WHERE user_id = v_user_id
        AND date = date '2026-07-13'
        AND gap_reminder_sent_at IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'failed delivery changed snapshot or could not be retried: failed %, retry %',
      v_failed_claim, v_reclaim;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.claim_daily_gap_reminder(uuid,date,text,jsonb,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.finalize_daily_gap_reminder(uuid,text,text,text,text,timestamptz,integer,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute daily gap delivery functions';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.claim_daily_gap_reminder(uuid,date,text,jsonb,timestamptz)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.finalize_daily_gap_reminder(uuid,text,text,text,text,timestamptz,integer,integer)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.fail_daily_gap_reminder(uuid,text,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute daily gap delivery functions';
  END IF;
END;
$test$;

ROLLBACK;

BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000551';
  v_phrase_id uuid := '00000000-0000-0000-0000-000000000552';
  v_claim jsonb;
  v_same_claim jsonb;
  v_busy jsonb;
  v_final jsonb;
  v_retry_final jsonb;
  v_failed_claim jsonb;
  v_reclaim jsonb;
  v_attempt_id uuid;
  v_message_count integer;
  v_sent_count integer;
  v_prompt_count integer;
  v_phrase record;
BEGIN
  INSERT INTO public.users (id, wpp, status)
  VALUES (v_user_id, '15550000551', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.engagement_phrases (
    id, phrase, slot, language, active, picked_count, used_count
  ) VALUES (
    v_phrase_id, 'Frase de teste', 'morning', 'pt-BR', true, 0, 0
  ) ON CONFLICT (id) DO UPDATE SET picked_count = 0, used_count = 0;

  v_claim := public.claim_engagement_delivery(
    v_user_id,
    DATE '2026-07-12',
    'cafe_da_manha',
    'engagement-run-1',
    timestamptz '2026-07-12 12:00:00+00'
  );
  v_attempt_id := (v_claim->>'attempt_id')::uuid;

  v_same_claim := public.claim_engagement_delivery(
    v_user_id,
    DATE '2026-07-12',
    'cafe_da_manha',
    'engagement-run-1',
    timestamptz '2026-07-12 12:01:00+00'
  );
  v_busy := public.claim_engagement_delivery(
    v_user_id,
    DATE '2026-07-12',
    'almoco',
    'engagement-run-2',
    timestamptz '2026-07-12 12:01:00+00'
  );

  IF v_claim->>'status' <> 'claimed'
    OR (v_same_claim->>'attempt_id')::uuid <> v_attempt_id
    OR v_busy->>'status' <> 'busy' THEN
    RAISE EXCEPTION 'engagement claim is not idempotent: claim %, same %, busy %',
      v_claim, v_same_claim, v_busy;
  END IF;

  v_final := public.finalize_engagement_delivery(
    p_attempt_id => v_attempt_id,
    p_claim_key => 'engagement-run-1',
    p_provider => 'whatsapp_cloud',
    p_deliveries => '[
      {"provider_message_id":"wamid-eng-1","content":"Bom dia","content_type":"text","media_url":null},
      {"provider_message_id":"wamid-eng-2","content":"Vamos nessa","content_type":"text","media_url":null}
    ]'::jsonb,
    p_sent_at => timestamptz '2026-07-12 12:02:00+00',
    p_model => 'test-model',
    p_prompt_tokens => 10,
    p_completion_tokens => 20,
    p_cost_usd => 0.01,
    p_latency_ms => 100,
    p_reevaluation_due => true,
    p_reevaluation_context => '{"due_date":"2026-07-12"}'::jsonb,
    p_phrase_id => v_phrase_id,
    p_phrase_used => true
  );

  v_retry_final := public.finalize_engagement_delivery(
    p_attempt_id => v_attempt_id,
    p_claim_key => 'engagement-run-1',
    p_provider => 'whatsapp_cloud',
    p_deliveries => '[
      {"provider_message_id":"wamid-eng-1","content":"Bom dia","content_type":"text","media_url":null},
      {"provider_message_id":"wamid-eng-2","content":"Vamos nessa","content_type":"text","media_url":null}
    ]'::jsonb,
    p_sent_at => timestamptz '2026-07-12 12:02:00+00'
  );

  SELECT count(*) INTO v_message_count
  FROM public.messages
  WHERE provider = 'whatsapp_cloud'
    AND provider_message_id IN ('wamid-eng-1', 'wamid-eng-2');
  SELECT count(*) INTO v_sent_count
  FROM public.product_events
  WHERE user_id = v_user_id AND event = 'engagement.sent';
  SELECT count(*) INTO v_prompt_count
  FROM public.product_events
  WHERE user_id = v_user_id AND event = 'reevaluation.prompt_sent';
  SELECT picked_count, used_count INTO v_phrase
  FROM public.engagement_phrases WHERE id = v_phrase_id;

  IF NOT (v_final->>'applied')::boolean
    OR (v_retry_final->>'applied')::boolean
    OR v_message_count <> 2
    OR v_sent_count <> 1
    OR v_prompt_count <> 1
    OR v_phrase.picked_count <> 1
    OR v_phrase.used_count <> 1
    OR NOT EXISTS (
      SELECT 1 FROM public.user_phrase_cooldown
      WHERE user_id = v_user_id
        AND phrase_table = 'engagement'
        AND phrase_id = v_phrase_id
        AND last_seen_at = timestamptz '2026-07-12 12:02:00+00'
    ) THEN
    RAISE EXCEPTION 'engagement finalization failed: final %, retry %, messages %, sent %, prompt %, phrase %',
      v_final, v_retry_final, v_message_count, v_sent_count, v_prompt_count, v_phrase;
  END IF;

  v_busy := public.claim_engagement_delivery(
    v_user_id,
    DATE '2026-07-12',
    'almoco',
    'engagement-run-2',
    timestamptz '2026-07-12 13:00:00+00'
  );
  IF v_busy->>'status' <> 'already_sent' THEN
    RAISE EXCEPTION 'sent engagement was claimed again: %', v_busy;
  END IF;

  v_failed_claim := public.claim_engagement_delivery(
    v_user_id,
    DATE '2026-07-13',
    'cafe_da_manha',
    'engagement-run-3',
    timestamptz '2026-07-13 12:00:00+00'
  );
  IF NOT public.fail_engagement_delivery(
    (v_failed_claim->>'attempt_id')::uuid,
    'engagement-run-3',
    'provider failed',
    timestamptz '2026-07-13 12:01:00+00'
  ) THEN
    RAISE EXCEPTION 'failed engagement was not marked failed';
  END IF;

  v_reclaim := public.claim_engagement_delivery(
    v_user_id,
    DATE '2026-07-13',
    'almoco',
    'engagement-run-4',
    timestamptz '2026-07-13 13:00:00+00'
  );
  IF v_reclaim->>'status' <> 'claimed'
    OR (v_reclaim->>'attempt_id')::uuid = (v_failed_claim->>'attempt_id')::uuid THEN
    RAISE EXCEPTION 'failed engagement could not be reclaimed: failed %, retry %',
      v_failed_claim, v_reclaim;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.claim_engagement_delivery(uuid,date,text,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.finalize_engagement_delivery(uuid,text,text,jsonb,timestamptz,text,integer,integer,numeric,integer,boolean,jsonb,uuid,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute engagement delivery functions';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.claim_engagement_delivery(uuid,date,text,text,timestamptz)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.finalize_engagement_delivery(uuid,text,text,jsonb,timestamptz,text,integer,integer,numeric,integer,boolean,jsonb,uuid,boolean)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.fail_engagement_delivery(uuid,text,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute engagement delivery functions';
  END IF;
END;
$test$;

ROLLBACK;

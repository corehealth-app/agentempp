-- C5a full-schema integration regression.
-- Run only against an authorized disposable local Supabase migration chain.
-- Existing schemas/roles/extensions/functions are required; no bootstrap or stand-ins.
-- Claims below are a synthetic guard fixture, NOT a GoTrue/JWT/session proof.
-- All fixture writes are rolled back. Existing fixture IDs cause an explicit abort.
BEGIN;
DO $test$
DECLARE
  v_a constant uuid := '00000000-0000-0000-0000-00000000c5a1';
  v_b constant uuid := '00000000-0000-0000-0000-00000000c5a2';
  v_in constant uuid := '00000000-0000-0000-0000-00000000c5a3';
  v_event text := 'mobile_flow/' || v_a::text || '/c5a-integration-0001';
  v_catalog constant text := 'flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb';
  v_phrase constant text := 'Consistência vale mais do que perfeição.';
  v_cursor jsonb;
  v_receipt jsonb;
  v_read jsonb;
  v_result jsonb;
  v_original jsonb;
  v_reset jsonb;
  v_commit_sig constant text := 'public.commit_flow_phrase_reply(uuid,text,uuid,text,text,text,text,text,uuid,text,jsonb,jsonb,jsonb,text,timestamptz,jsonb)';
BEGIN
  -- Causal RED before migration: fails explicitly before any fixture data.
  IF to_regprocedure('public.read_flow_phrase_cursor(uuid)') IS NULL
    OR to_regprocedure(v_commit_sig) IS NULL THEN
    RAISE EXCEPTION 'C5a assertion: required phrase RPCs are absent';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='users'
      AND column_name='flow_phrase_cursor_revision' AND data_type='bigint'
      AND is_nullable='NO') THEN
    RAISE EXCEPTION 'C5a assertion: required bigint witness is absent';
  END IF;
  IF has_function_privilege('anon','public.read_flow_phrase_cursor(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','public.read_flow_phrase_cursor(uuid)','EXECUTE')
    OR has_function_privilege('anon',v_commit_sig,'EXECUTE')
    OR has_function_privilege('authenticated',v_commit_sig,'EXECUTE')
    OR NOT has_function_privilege('service_role','public.read_flow_phrase_cursor(uuid)','EXECUTE')
    OR NOT has_function_privilege('service_role',v_commit_sig,'EXECUTE')
    OR has_column_privilege('anon','public.users','flow_phrase_cursor_revision','SELECT')
    OR has_column_privilege('authenticated','public.users','flow_phrase_cursor_revision','SELECT')
    OR has_column_privilege('authenticated','public.users','flow_phrase_cursor_revision','UPDATE') THEN
    RAISE EXCEPTION 'C5a assertion: effective RPC/column ACL is wrong';
  END IF;
  IF EXISTS (SELECT 1 FROM public.users WHERE id IN (v_a,v_b))
    OR EXISTS (SELECT 1 FROM public.messages WHERE id=v_in) THEN
    RAISE EXCEPTION 'C5a fixture IDs already exist; preserve and abort';
  END IF;
  INSERT INTO public.users(id,email,locale,status)
    VALUES (v_a,'c5a-a@example.invalid','pt-BR','active'),
           (v_b,'c5a-b@example.invalid','en-US','active');
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_read := public.read_flow_phrase_cursor(v_a);
  IF v_read IS DISTINCT FROM jsonb_build_object(
    'anchor_assistant_id',NULL,'cursor_revision','0','cursor',NULL) THEN
    RAISE EXCEPTION 'C5a assertion: empty cursor is not official zero';
  END IF;
  v_original := jsonb_build_object('request_id','c5a-request-original',
    'conversation_id','flow','attempt_started_at','2026-10-13T00:00:00.000Z',
    'fixture_sentinel',jsonb_build_object('preserve',true));
  INSERT INTO public.messages(id,user_id,direction,role,content_type,content,
    provider,provider_message_id,raw_payload,delivery_status,created_at)
  VALUES(v_in,v_a,'in','user','text','Status do dia','mobile_flow',v_event,
    v_original,'processing','2026-10-13T00:00:00Z');
  v_cursor := jsonb_build_object('schema','flow.phrase-state.v1','userId',v_a::text,
    'catalogVersion',v_catalog,'ordinal',1,
    'lastTextKey',encode(extensions.digest(convert_to(v_phrase,'UTF8'),'sha256'),'hex'),
    'usedTextKeys',jsonb_build_array(encode(extensions.digest(convert_to(v_phrase,'UTF8'),'sha256'),'hex')));
  v_receipt := jsonb_build_object('eventKey',v_event,
    'requestFingerprint','ad21dd91df986aaf7ffbce6760ecfcfc0df4bb223481946e208b4d17e292e580',
    'selection',jsonb_build_object('phrase',v_phrase,'phraseId','engagement:002',
      'sourceText',v_phrase,'foodCanonicalName',NULL,'reason','selected_incentive'));
  v_result := public.commit_flow_phrase_reply(
    p_user_id=>v_a,p_event_key=>v_event,p_expected_inbound_id=>v_in,
    p_inbound_provider_message_id=>v_event,p_assistant_provider_message_id=>v_event||'/assistant',
    p_expected_inbound_content=>'Status do dia',p_expected_request_id=>'c5a-request-original',
    p_expected_attempt_started_at=>'2026-10-13T00:00:00.000Z',
    p_expected_anchor_assistant_id=>NULL,p_expected_cursor_revision=>'0',p_expected_cursor=>NULL,
    p_next_cursor=>v_cursor,p_receipt=>v_receipt,
    p_content=>'Status sintético de teste.'||E'\n\n'||v_phrase,
    p_created_at=>'2026-10-13T00:00:01Z',
    p_metadata=>jsonb_build_object('stage','recomposicao','modelUsed','none',
      'promptTokens',0,'completionTokens',0,'costUsd',0,'latencyMs',1));
  IF v_result->>'action' IS DISTINCT FROM 'committed'
    OR (SELECT raw_payload FROM public.messages WHERE id=v_in) IS DISTINCT FROM v_original
    OR (SELECT delivery_status FROM public.messages WHERE id=v_in) IS DISTINCT FROM 'completed'
    OR (SELECT count(*) FROM public.messages WHERE user_id=v_a AND direction='out')<>1 THEN
    RAISE EXCEPTION 'C5a assertion: committed OUT/IN preservation mismatch';
  END IF;
  v_read := public.read_flow_phrase_cursor(v_a);
  IF v_read->>'cursor_revision' IS DISTINCT FROM '1'
    OR v_read->'cursor' IS DISTINCT FROM v_cursor
    OR v_read->>'anchor_assistant_id' IS DISTINCT FROM v_result#>>'{message,id}' THEN
    RAISE EXCEPTION 'C5a assertion: official cursor does not match committed OUT';
  END IF;
  -- Historical replay precedes new-publication/CAS parameter validation.
  v_result := public.commit_flow_phrase_reply(v_a,v_event,v_in,v_event,v_event||'/assistant',
    'Status do dia',NULL,NULL,NULL,'0',NULL,NULL,NULL,NULL,NULL,NULL);
  IF v_result->>'action' IS DISTINCT FROM 'replay'
    OR public.read_flow_phrase_cursor(v_a) IS DISTINCT FROM v_read
    OR (SELECT count(*) FROM public.messages WHERE user_id=v_a AND direction='out')<>1 THEN
    RAISE EXCEPTION 'C5a assertion: replay advanced or duplicated the official cursor';
  END IF;
  v_result := public.commit_flow_phrase_reply(v_b,v_event,v_in,v_event,v_event||'/assistant',
    'Status do dia',NULL,NULL,NULL,'0',NULL,NULL,NULL,NULL,NULL,NULL);
  IF v_result->>'action' IS DISTINCT FROM 'event_conflict'
    OR public.read_flow_phrase_cursor(v_b) IS DISTINCT FROM jsonb_build_object(
      'anchor_assistant_id',NULL,'cursor_revision','0','cursor',NULL) THEN
    RAISE EXCEPTION 'C5a assertion: other owner accepted the event or gained state';
  END IF;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.read_flow_phrase_cursor(v_a);
    RAISE EXCEPTION 'C5a assertion: forged end-user claim passed backend guard';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_reset := public.reset_user_conversation_atomic(v_a);
  IF v_reset->>'reset' IS DISTINCT FROM 'true'
    OR v_reset->>'kept_plans' IS DISTINCT FROM 'true'
    OR public.read_flow_phrase_cursor(v_a) IS DISTINCT FROM jsonb_build_object(
      'anchor_assistant_id',NULL,'cursor_revision','0','cursor',NULL)
    OR public.read_flow_phrase_cursor(v_b) IS DISTINCT FROM jsonb_build_object(
      'anchor_assistant_id',NULL,'cursor_revision','0','cursor',NULL) THEN
    RAISE EXCEPTION 'C5a assertion: default reset did not zero only its official lane';
  END IF;
END;
$test$;
ROLLBACK;

-- C5c/C13: app-only shared phrase rotation and immutable registration feedback.
-- Additive RPCs. C5a namespaces, message witness and legacy RPC bodies stay intact.
-- Rollout: qualify common-aware BFF with C13 off BEFORE allowing registration
-- feedback. Old BFF is not a compatible rollback after shared-state adoption.
-- Shared conversation reset clears the new technical state through its existing
-- legacy-witness reset; existing pending deletion cascades private receipts.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE public.users
 ADD COLUMN flow_shared_phrase_revision bigint NOT NULL DEFAULT 0,
 ADD COLUMN flow_shared_phrase_legacy_revision bigint NOT NULL DEFAULT 0,
 ADD COLUMN flow_shared_phrase_cursor jsonb,
 ADD CONSTRAINT users_flow_shared_phrase_coherent CHECK (
  (flow_shared_phrase_revision=0 AND flow_shared_phrase_legacy_revision=0 AND flow_shared_phrase_cursor IS NULL)
  OR (flow_shared_phrase_revision>0 AND flow_shared_phrase_revision>=flow_phrase_cursor_revision
    AND flow_shared_phrase_legacy_revision=flow_phrase_cursor_revision AND flow_shared_phrase_cursor IS NOT NULL));
REVOKE SELECT(flow_shared_phrase_revision,flow_shared_phrase_legacy_revision,flow_shared_phrase_cursor),
 INSERT(flow_shared_phrase_revision,flow_shared_phrase_legacy_revision,flow_shared_phrase_cursor),
 UPDATE(flow_shared_phrase_revision,flow_shared_phrase_legacy_revision,flow_shared_phrase_cursor)
 ON public.users FROM PUBLIC,anon,authenticated;

CREATE TABLE private.mobile_registration_feedback (
 registration_id uuid PRIMARY KEY REFERENCES public.pending_registrations(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 proposal_hash text NOT NULL CHECK(proposal_hash ~ '^[a-f0-9]{64}$'),
 cursor_revision bigint NOT NULL CHECK(cursor_revision>0),
 feedback jsonb NOT NULL CHECK(jsonb_typeof(feedback)='object'),
 steps jsonb NOT NULL CHECK(jsonb_typeof(steps)='array'),
 created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE INDEX mobile_registration_feedback_user ON private.mobile_registration_feedback(user_id);
ALTER TABLE private.mobile_registration_feedback ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_registration_feedback FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.assert_flow_shared_cursor(p_cursor jsonb,p_user_id uuid) RETURNS void
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_ord numeric;v_used text[]:=ARRAY[]::text[];v_key jsonb;
BEGIN
 IF p_user_id IS NULL OR jsonb_typeof(p_cursor) IS DISTINCT FROM 'object'
 OR NOT(p_cursor ?& ARRAY['schema','userId','catalogVersion','ordinal','lastTextKey','usedTextKeys'])
 OR p_cursor-ARRAY['schema','userId','catalogVersion','ordinal','lastTextKey','usedTextKeys']<>'{}'::jsonb
 OR p_cursor->>'schema' IS DISTINCT FROM 'flow.phrase-state.v1'
 OR p_cursor->>'userId' IS DISTINCT FROM p_user_id::text
 OR p_cursor->>'catalogVersion' IS DISTINCT FROM 'flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb'
 OR jsonb_typeof(p_cursor->'ordinal') IS DISTINCT FROM 'number'
 OR jsonb_typeof(p_cursor->'usedTextKeys') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'shared phrase cursor corrupt' USING ERRCODE='22023';END IF;
 v_ord:=(p_cursor->>'ordinal')::numeric;
 IF v_ord<0 OR v_ord>9007199254740991 OR v_ord<>trunc(v_ord)
 THEN RAISE EXCEPTION 'shared phrase ordinal corrupt' USING ERRCODE='22023';END IF;
 FOR v_key IN SELECT value FROM jsonb_array_elements(p_cursor->'usedTextKeys') LOOP
  IF jsonb_typeof(v_key) IS DISTINCT FROM 'string' OR (v_key#>>'{}') !~ '^[a-f0-9]{64}$' OR (v_key#>>'{}')=ANY(v_used)
  THEN RAISE EXCEPTION 'shared phrase keys corrupt' USING ERRCODE='22023';END IF;
  v_used:=array_append(v_used,v_key#>>'{}');
 END LOOP;
 IF cardinality(v_used)::numeric>v_ord OR
 (v_ord=0 AND (p_cursor->'lastTextKey' IS DISTINCT FROM 'null'::jsonb OR cardinality(v_used)<>0)) OR
 (v_ord>0 AND (jsonb_typeof(p_cursor->'lastTextKey') IS DISTINCT FROM 'string'
  OR (p_cursor->>'lastTextKey') !~ '^[a-f0-9]{64}$' OR cardinality(v_used)=0
  OR v_used[cardinality(v_used)] IS DISTINCT FROM p_cursor->>'lastTextKey'))
 THEN RAISE EXCEPTION 'shared phrase cursor incoherent' USING ERRCODE='22023';END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.assert_flow_shared_cursor(jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.guard_flow_shared_phrase_reset() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW.flow_phrase_cursor_revision=0 THEN
  IF EXISTS(SELECT 1 FROM public.messages m WHERE m.user_id=NEW.id AND m.raw_payload ? 'flow_phrase_v1')
   OR EXISTS(SELECT 1 FROM private.mobile_registration_feedback r WHERE r.user_id=NEW.id)
  THEN RAISE EXCEPTION 'shared phrase reset requires source removal' USING ERRCODE='22023';END IF;
  NEW.flow_shared_phrase_revision:=0;NEW.flow_shared_phrase_legacy_revision:=0;NEW.flow_shared_phrase_cursor:=NULL;
 ELSIF OLD.flow_shared_phrase_revision>0 AND (
  NEW.flow_phrase_cursor_revision<>OLD.flow_phrase_cursor_revision+1
  OR NEW.flow_shared_phrase_revision<>OLD.flow_shared_phrase_revision+1
  OR NEW.flow_shared_phrase_legacy_revision<>NEW.flow_phrase_cursor_revision)
 THEN RAISE EXCEPTION 'common-aware phrase writer required after adoption' USING ERRCODE='40001';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.guard_flow_shared_phrase_reset() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_flow_shared_phrase_reset BEFORE UPDATE OF flow_phrase_cursor_revision ON public.users
 FOR EACH ROW EXECUTE FUNCTION private.guard_flow_shared_phrase_reset();

CREATE FUNCTION public.read_flow_shared_phrase_cursor(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_user public.users%ROWTYPE;v_legacy jsonb;v_cursor jsonb;v_revision bigint;v_mode text;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO v_user FROM public.users WHERE id=p_user_id FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'shared phrase account absent' USING ERRCODE='P0002';END IF;
 v_legacy:=public.read_flow_phrase_cursor(p_user_id);
 IF v_legacy->>'cursor_revision' IS DISTINCT FROM v_user.flow_phrase_cursor_revision::text
 THEN RAISE EXCEPTION 'legacy phrase witness inconsistent' USING ERRCODE='22023';END IF;
 IF v_user.flow_shared_phrase_revision=0 THEN
  IF v_user.flow_shared_phrase_legacy_revision<>0 OR v_user.flow_shared_phrase_cursor IS NOT NULL
  THEN RAISE EXCEPTION 'shared phrase initial state corrupt' USING ERRCODE='22023';END IF;
  v_mode:='legacy';v_cursor:=v_legacy->'cursor';v_revision:=v_user.flow_phrase_cursor_revision;
 ELSE
  IF v_user.flow_shared_phrase_revision<0 OR v_user.flow_shared_phrase_revision<v_user.flow_phrase_cursor_revision
   OR v_user.flow_shared_phrase_legacy_revision<>v_user.flow_phrase_cursor_revision
  THEN RAISE EXCEPTION 'shared phrase witness inconsistent' USING ERRCODE='22023';END IF;
  v_mode:='shared';v_cursor:=v_user.flow_shared_phrase_cursor;v_revision:=v_user.flow_shared_phrase_revision;
  PERFORM private.assert_flow_shared_cursor(v_cursor,p_user_id);
 END IF;
 RETURN jsonb_build_object('schema','flow.shared-phrase-snapshot.v1','mode',v_mode,
  'anchor_assistant_id',v_legacy->'anchor_assistant_id','legacy_cursor_revision',v_legacy->>'cursor_revision',
  'cursor_revision',v_revision::text,'cursor',v_cursor);
END;$fn$;
REVOKE ALL ON FUNCTION public.read_flow_shared_phrase_cursor(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_flow_shared_phrase_cursor(uuid) TO service_role;

-- Same real C5a event/attempt/OUT/IN fences; common CAS, separate chat witness.
CREATE FUNCTION public.commit_flow_shared_phrase_reply(
  p_user_id uuid,
  p_event_key text,
  p_expected_inbound_id uuid,
  p_inbound_provider_message_id text,
  p_assistant_provider_message_id text,
  p_expected_inbound_content text,
  p_expected_request_id text,
  p_expected_attempt_started_at text,
  p_expected_anchor_assistant_id uuid,
  p_expected_cursor_revision text,
  p_expected_cursor jsonb,
  p_next_cursor jsonb,
  p_receipt jsonb,
  p_content text,
  p_created_at timestamptz,
  p_metadata jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $fn$
DECLARE
  v_user_revision bigint;
  v_in public.messages%ROWTYPE;
  v_out public.messages%ROWTYPE;
  v_prefix text;
  v_bare_key text;
  v_current jsonb;
  v_old_cursor jsonb;
  v_namespace jsonb;
  v_old_revision bigint;
  v_next_revision bigint;
  v_old_ordinal numeric;
  v_new_ordinal numeric;
  v_selection jsonb;
  v_selected_key text;
  v_affected integer;
  v_catalog constant text :=
    'flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb';
BEGIN
  PERFORM private.assert_trusted_backend();
  -- Identity/body inputs only. New-publication input validation is AFTER replay.
  IF p_user_id IS NULL OR p_event_key IS NULL
    OR p_expected_inbound_id IS NULL
    OR p_inbound_provider_message_id IS NULL
    OR p_assistant_provider_message_id IS NULL
    OR p_expected_inbound_content IS NULL
  THEN
    RAISE EXCEPTION 'invalid flow phrase event' USING ERRCODE = '22023';
  END IF;
  v_prefix := 'mobile_flow/' || p_user_id::text || '/';
  v_bare_key := substring(p_event_key FROM char_length(v_prefix) + 1);
  IF left(p_event_key, char_length(v_prefix)) <> v_prefix
    OR char_length(v_bare_key) NOT BETWEEN 8 AND 128
    OR v_bare_key !~ '^[A-Za-z0-9._:-]+$'
    OR p_inbound_provider_message_id NOT IN (p_event_key, v_bare_key)
    -- New C5 replies always use the scoped output, including a legacy IN.
    OR p_assistant_provider_message_id <> p_event_key || '/assistant'
  THEN
    RETURN jsonb_build_object('action', 'event_conflict');
  END IF;

  -- One account lane, same first lock as reset. No messages lock before this.
  SELECT u.flow_phrase_cursor_revision INTO v_user_revision
  FROM public.users u WHERE u.id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'flow phrase account absent' USING ERRCODE = 'P0002';
  END IF;
  IF v_user_revision IS NULL OR v_user_revision < 0 THEN
    RAISE EXCEPTION 'flow phrase witness corrupt' USING ERRCODE = 'P0001';
  END IF;
  SELECT m.* INTO v_in FROM public.messages m
  WHERE m.user_id = p_user_id AND m.provider = 'mobile_flow'
    AND m.direction = 'in'
    AND m.provider_message_id = p_inbound_provider_message_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('action', 'event_conflict');
  END IF;
  IF v_in.id IS DISTINCT FROM p_expected_inbound_id
    OR v_in.role <> 'user' OR v_in.content_type <> 'text'
    OR v_in.content IS DISTINCT FROM p_expected_inbound_content
  THEN
    RETURN jsonb_build_object('action', 'event_conflict');
  END IF;

  -- Event lookup independent of CURRENT cursor/CAS/attempt/catalog parameters.
  SELECT m.* INTO v_out FROM public.messages m
  WHERE m.user_id = p_user_id AND m.provider = 'mobile_flow'
    AND m.direction = 'out'
    AND m.provider_message_id = p_assistant_provider_message_id;
  IF FOUND THEN
    IF v_out.role <> 'assistant' OR v_out.content_type <> 'text'
      OR v_out.delivery_status IS DISTINCT FROM 'completed'
      OR v_out.content IS NULL OR btrim(v_out.content) = ''
      OR jsonb_typeof(v_out.raw_payload) IS DISTINCT FROM 'object'
      OR jsonb_typeof(v_out.raw_payload -> 'request_id') IS DISTINCT FROM 'string'
      OR v_out.raw_payload ->> 'conversation_id' IS DISTINCT FROM 'flow'
    THEN
      RAISE EXCEPTION 'flow phrase replay corrupt' USING ERRCODE = 'P0001';
    END IF;
    v_namespace := v_out.raw_payload -> 'flow_phrase_v1';
    PERFORM private.assert_flow_phrase_namespace(v_namespace, p_user_id);
    IF v_namespace #> '{receipt,selection,phrase}' <> 'null'::jsonb
      AND right(v_out.content,
        char_length(v_namespace #>> '{receipt,selection,phrase}'))
        IS DISTINCT FROM v_namespace #>> '{receipt,selection,phrase}'
    THEN
      RAISE EXCEPTION 'flow phrase replay text corrupt' USING ERRCODE = 'P0001';
    END IF;
    IF v_namespace #>> '{receipt,eventKey}' IS DISTINCT FROM p_event_key THEN
      RAISE EXCEPTION 'flow phrase replay identity corrupt' USING ERRCODE = 'P0001';
    END IF;
    RETURN jsonb_build_object('action', 'replay', 'message', jsonb_build_object(
      'id', v_out.id, 'direction', v_out.direction, 'content', v_out.content,
      'delivery_status', v_out.delivery_status, 'raw_payload', v_out.raw_payload,
      'created_at', v_out.created_at));
  END IF;

  -- Only a still-owned real attempt may publish. Compare raw strings literally.
  IF p_expected_request_id IS NULL OR p_expected_attempt_started_at IS NULL
    OR v_in.delivery_status IS DISTINCT FROM 'processing'
    OR jsonb_typeof(v_in.raw_payload) IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_in.raw_payload -> 'request_id') IS DISTINCT FROM 'string'
    OR jsonb_typeof(v_in.raw_payload -> 'attempt_started_at') IS DISTINCT FROM 'string'
    OR v_in.raw_payload ->> 'request_id' IS DISTINCT FROM p_expected_request_id
    OR v_in.raw_payload ->> 'attempt_started_at'
      IS DISTINCT FROM p_expected_attempt_started_at
  THEN
    RETURN jsonb_build_object('action', 'attempt_conflict');
  END IF;
  IF p_expected_request_id !~ '^[A-Za-z0-9._:-]{8,128}$'
    OR p_expected_attempt_started_at = ''
    OR v_in.raw_payload ->> 'conversation_id' IS DISTINCT FROM 'flow'
    OR p_expected_cursor_revision IS NULL
    OR p_expected_cursor_revision !~ '^(0|[1-9][0-9]*)$'
    OR char_length(p_expected_cursor_revision) > 19
  THEN
    RAISE EXCEPTION 'invalid flow phrase publication' USING ERRCODE = '22023';
  END IF;
  IF p_expected_cursor_revision::numeric > 9223372036854775807 THEN
    RAISE EXCEPTION 'invalid flow phrase revision' USING ERRCODE = '22023';
  END IF;
  -- VOLATILE read sees the newly committed cursor after acquiring users lock.
  v_current := public.read_flow_shared_phrase_cursor(p_user_id);
  IF (v_current ->> 'legacy_cursor_revision')::bigint <> v_user_revision THEN
    RAISE EXCEPTION 'flow phrase witness read inconsistent' USING ERRCODE = 'P0001';
  END IF;
  IF v_current ->> 'anchor_assistant_id'
      IS DISTINCT FROM p_expected_anchor_assistant_id::text
    OR v_current ->> 'cursor_revision' IS DISTINCT FROM p_expected_cursor_revision
    OR v_current -> 'cursor'
      IS DISTINCT FROM COALESCE(p_expected_cursor, 'null'::jsonb)
  THEN
    RETURN jsonb_build_object('action', 'cursor_conflict');
  END IF;
  v_old_revision := v_user_revision;
  v_old_cursor := v_current -> 'cursor';
  IF v_old_cursor = 'null'::jsonb THEN
    -- The common read proved no prior cursor; C13-first can have chat witness zero with a non-null cursor.
    v_old_cursor := jsonb_build_object(
      'schema','flow.phrase-state.v1','userId',p_user_id::text,
      'catalogVersion',v_catalog,'ordinal',0,
      'lastTextKey',NULL,'usedTextKeys',jsonb_build_array());
  END IF;
  IF v_old_revision = 9223372036854775807 THEN
    RAISE EXCEPTION 'flow phrase revision exhausted' USING ERRCODE = '22003';
  END IF;
  v_next_revision := v_old_revision + 1;
  v_namespace := jsonb_build_object(
    'schema','flow.phrase-store.v1',
    'cursor_revision',v_next_revision::text,
    'previous_anchor_assistant_id',p_expected_anchor_assistant_id,
    'cursor',p_next_cursor,'receipt',p_receipt);
  PERFORM private.assert_flow_phrase_namespace(v_namespace, p_user_id);
  IF p_receipt ->> 'eventKey' IS DISTINCT FROM p_event_key
    OR p_next_cursor ->> 'catalogVersion' IS DISTINCT FROM v_old_cursor ->> 'catalogVersion'
  THEN
    RAISE EXCEPTION 'invalid flow phrase transition' USING ERRCODE = '22023';
  END IF;
  v_selection := p_receipt -> 'selection';
  v_old_ordinal := (v_old_cursor ->> 'ordinal')::numeric;
  v_new_ordinal := (p_next_cursor ->> 'ordinal')::numeric;
  IF v_selection -> 'phrase' = 'null'::jsonb THEN
    IF p_next_cursor IS DISTINCT FROM v_old_cursor THEN
      RAISE EXCEPTION 'invalid flow phrase empty transition' USING ERRCODE = '22023';
    END IF;
  ELSE
    v_selected_key := p_next_cursor ->> 'lastTextKey';
    IF v_old_ordinal = 9007199254740991
      OR v_new_ordinal <> v_old_ordinal + 1
      OR v_selected_key IS NOT DISTINCT FROM v_old_cursor ->> 'lastTextKey'
      OR NOT (
        (NOT ((v_old_cursor -> 'usedTextKeys') ? v_selected_key)
          AND p_next_cursor -> 'usedTextKeys' =
            (v_old_cursor -> 'usedTextKeys') || jsonb_build_array(v_selected_key))
        OR p_next_cursor -> 'usedTextKeys' = jsonb_build_array(v_selected_key)
      )
    THEN
      RAISE EXCEPTION 'invalid flow phrase selected transition' USING ERRCODE = '22023';
    END IF;
  END IF;

  -- Preserve the existing metadata columns; only deterministic status is eligible.
  IF p_content IS NULL OR btrim(p_content) = ''
    OR p_created_at IS NULL OR NOT isfinite(p_created_at)
    OR jsonb_typeof(p_metadata) IS DISTINCT FROM 'object'
    OR NOT (p_metadata ?& ARRAY[
      'stage','modelUsed','promptTokens','completionTokens','costUsd','latencyMs'])
    OR (p_metadata - ARRAY[
      'stage','modelUsed','promptTokens','completionTokens','costUsd','latencyMs'])
      <> '{}'::jsonb
    OR jsonb_typeof(p_metadata -> 'stage') IS DISTINCT FROM 'string'
    OR btrim(p_metadata ->> 'stage') = ''
    OR p_metadata ->> 'modelUsed' IS DISTINCT FROM 'none'
    OR jsonb_typeof(p_metadata -> 'promptTokens') IS DISTINCT FROM 'number'
    OR jsonb_typeof(p_metadata -> 'completionTokens') IS DISTINCT FROM 'number'
    OR jsonb_typeof(p_metadata -> 'costUsd') IS DISTINCT FROM 'number'
    OR jsonb_typeof(p_metadata -> 'latencyMs') IS DISTINCT FROM 'number'
  THEN
    RAISE EXCEPTION 'invalid flow phrase message' USING ERRCODE = '22023';
  END IF;
  IF (p_metadata ->> 'promptTokens')::numeric <> 0
    OR (p_metadata ->> 'completionTokens')::numeric <> 0
    OR (p_metadata ->> 'costUsd')::numeric <> 0
    OR (p_metadata ->> 'latencyMs')::numeric < 0
    OR (p_metadata ->> 'latencyMs')::numeric > 2147483647
    OR (p_metadata ->> 'latencyMs')::numeric
      <> trunc((p_metadata ->> 'latencyMs')::numeric)
  THEN
    RAISE EXCEPTION 'invalid flow phrase metrics' USING ERRCODE = '22023';
  END IF;
  IF v_selection -> 'phrase' <> 'null'::jsonb
    AND right(p_content, char_length(v_selection ->> 'phrase'))
      IS DISTINCT FROM v_selection ->> 'phrase'
  THEN
    RAISE EXCEPTION 'invalid flow phrase final text' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.messages (
    user_id, direction, role, content_type, content,
    provider, provider_message_id, raw_payload, delivery_status,
    agent_stage, model_used, prompt_tokens, completion_tokens,
    cost_usd, latency_ms, created_at
  ) VALUES (
    p_user_id, 'out', 'assistant', 'text', p_content,
    'mobile_flow', p_assistant_provider_message_id,
    jsonb_build_object('request_id',p_expected_request_id,'conversation_id','flow',
      'flow_phrase_v1',v_namespace),
    'completed', p_metadata ->> 'stage', p_metadata ->> 'modelUsed',
    0, 0, 0, (p_metadata ->> 'latencyMs')::integer, p_created_at
  ) RETURNING * INTO v_out;

  IF (v_current->>'cursor_revision')::bigint = 9223372036854775807 THEN
    RAISE EXCEPTION 'shared phrase revision exhausted' USING ERRCODE='22003';
  END IF;
  UPDATE public.users u
  SET flow_phrase_cursor_revision = v_next_revision,
      flow_shared_phrase_legacy_revision = v_next_revision,
      flow_shared_phrase_revision = (v_current->>'cursor_revision')::bigint + 1,
      flow_shared_phrase_cursor = p_next_cursor
  WHERE u.id = p_user_id AND u.flow_phrase_cursor_revision = v_old_revision;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'flow phrase witness fence lost' USING ERRCODE = '40001';
  END IF;

  UPDATE public.messages m
  SET delivery_status = 'completed', delivery_error = NULL
  WHERE m.id = v_in.id AND m.id = p_expected_inbound_id AND m.user_id = p_user_id
    AND m.provider = 'mobile_flow' AND m.direction = 'in'
    AND m.provider_message_id = p_inbound_provider_message_id
    AND m.delivery_status = 'processing'
    AND m.content IS NOT DISTINCT FROM p_expected_inbound_content
    AND m.raw_payload ->> 'request_id' = p_expected_request_id
    AND m.raw_payload ->> 'attempt_started_at' = p_expected_attempt_started_at;
  -- No raw_payload assignment: IN namespace/attempt/retry fields remain literal.
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION 'flow phrase completion fence lost' USING ERRCODE = '40001';
  END IF;
  -- No EXCEPTION handler: failures roll back OUT + users witness + IN completion.
  RETURN jsonb_build_object('action', 'committed', 'message', jsonb_build_object(
    'id', v_out.id, 'direction', v_out.direction, 'content', v_out.content,
    'delivery_status', v_out.delivery_status, 'raw_payload', v_out.raw_payload,
    'created_at', v_out.created_at));
END;
$fn$;

REVOKE ALL ON FUNCTION public.commit_flow_shared_phrase_reply(
  uuid,text,uuid,text,text,text,text,text,uuid,text,jsonb,jsonb,jsonb,text,timestamptz,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_flow_shared_phrase_reply(
  uuid,text,uuid,text,text,text,text,text,uuid,text,jsonb,jsonb,jsonb,text,timestamptz,jsonb)
  TO service_role;

CREATE FUNCTION private.assert_registration_phrase_step(p_user_id uuid,p_old jsonb,p_step jsonb,p_event text,p_kind text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_next jsonb;v_receipt jsonb;v_selection jsonb;v_key text;v_old_ord numeric;v_next_ord numeric;
BEGIN
 PERFORM private.assert_flow_shared_cursor(p_old,p_user_id);
 IF jsonb_typeof(p_step) IS DISTINCT FROM 'object' OR NOT(p_step ?& ARRAY['receipt','nextCursor'])
 OR p_step-ARRAY['receipt','nextCursor']<>'{}'::jsonb
 THEN RAISE EXCEPTION 'registration phrase step invalid' USING ERRCODE='22023';END IF;
 v_next:=p_step->'nextCursor';v_receipt:=p_step->'receipt';
 PERFORM private.assert_flow_shared_cursor(v_next,p_user_id);
 IF jsonb_typeof(v_receipt) IS DISTINCT FROM 'object' OR NOT(v_receipt ?& ARRAY['eventKey','requestFingerprint','selection'])
 OR v_receipt-ARRAY['eventKey','requestFingerprint','selection']<>'{}'::jsonb
 OR v_receipt->>'eventKey' IS DISTINCT FROM p_event
 OR jsonb_typeof(v_receipt->'requestFingerprint') IS DISTINCT FROM 'string' OR (v_receipt->>'requestFingerprint') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'registration phrase receipt invalid' USING ERRCODE='22023';END IF;
 v_selection:=v_receipt->'selection';
 IF jsonb_typeof(v_selection) IS DISTINCT FROM 'object' OR NOT(v_selection ?& ARRAY['phrase','phraseId','sourceText','foodCanonicalName','reason'])
 OR v_selection-ARRAY['phrase','phraseId','sourceText','foodCanonicalName','reason']<>'{}'::jsonb
 OR jsonb_typeof(v_selection->'reason') IS DISTINCT FROM 'string'
 OR (v_selection->'foodCanonicalName'<>'null'::jsonb AND (jsonb_typeof(v_selection->'foodCanonicalName') IS DISTINCT FROM 'string' OR btrim(v_selection->>'foodCanonicalName')=''))
 OR (p_kind<>'food' AND v_selection->'foodCanonicalName' IS DISTINCT FROM 'null'::jsonb)
 THEN RAISE EXCEPTION 'registration phrase selection invalid' USING ERRCODE='22023';END IF;
 v_old_ord:=(p_old->>'ordinal')::numeric;v_next_ord:=(v_next->>'ordinal')::numeric;
 IF v_selection->'phrase'='null'::jsonb THEN
  IF v_selection->'phraseId' IS DISTINCT FROM 'null'::jsonb OR v_selection->'sourceText' IS DISTINCT FROM 'null'::jsonb
   OR v_selection->>'reason' NOT IN ('unsupported_language','no_anchor','no_food_match','no_eligible_phrase','only_previous_phrase','rotation_exhausted')
   OR (p_kind<>'food' AND v_selection->>'reason' IN ('no_anchor','no_food_match'))
   OR ((v_selection->>'reason'='rotation_exhausted') IS DISTINCT FROM (v_old_ord=9007199254740991))
   OR v_next IS DISTINCT FROM p_old
  THEN RAISE EXCEPTION 'registration empty phrase transition invalid' USING ERRCODE='22023';END IF;
 ELSE
  IF jsonb_typeof(v_selection->'phrase') IS DISTINCT FROM 'string' OR btrim(v_selection->>'phrase')=''
   OR jsonb_typeof(v_selection->'sourceText') IS DISTINCT FROM 'string' OR btrim(v_selection->>'sourceText')=''
   OR jsonb_typeof(v_selection->'phraseId') IS DISTINCT FROM 'string'
   OR (p_kind='food' AND ((v_selection->>'phraseId') !~ '^food:[a-z0-9_:]+$' OR v_selection->>'reason'<>'selected_food' OR v_selection->'foodCanonicalName'='null'::jsonb))
   OR (p_kind='incentive' AND ((v_selection->>'phraseId') !~ '^engagement:[0-9]{3}$' OR v_selection->>'reason'<>'selected_incentive'))
   OR (p_kind='workout' AND ((v_selection->>'phraseId') !~ '^engagement:[0-9]{3}$' OR v_selection->>'reason'<>'workout_incentive_fallback'))
  THEN RAISE EXCEPTION 'registration selected phrase invalid' USING ERRCODE='22023';END IF;
  v_key:=encode(extensions.digest(convert_to(v_selection->>'phrase','UTF8'),'sha256'),'hex');
  IF v_old_ord=9007199254740991 OR v_next_ord<>v_old_ord+1
   OR v_key IS DISTINCT FROM v_next->>'lastTextKey' OR v_key IS NOT DISTINCT FROM p_old->>'lastTextKey'
   OR NOT((NOT((p_old->'usedTextKeys') ? v_key) AND v_next->'usedTextKeys'=(p_old->'usedTextKeys')||jsonb_build_array(v_key))
     OR v_next->'usedTextKeys'=jsonb_build_array(v_key))
  THEN RAISE EXCEPTION 'registration selected transition invalid' USING ERRCODE='22023';END IF;
 END IF;
 RETURN v_next;
END;$fn$;
REVOKE ALL ON FUNCTION private.assert_registration_phrase_step(uuid,jsonb,jsonb,text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_mobile_registration_feedback(p_user_id uuid,p_registration_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_pending public.pending_registrations%ROWTYPE;v_receipt private.mobile_registration_feedback%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM 1 FROM public.users WHERE id=p_user_id FOR SHARE;
 IF NOT FOUND THEN RETURN jsonb_build_object('action','absent');END IF;
 SELECT * INTO v_pending FROM public.pending_registrations WHERE id=p_registration_id AND user_id=p_user_id FOR SHARE;
 IF NOT FOUND OR v_pending.status<>'confirmed' THEN RETURN jsonb_build_object('action','absent');END IF;
 SELECT * INTO v_receipt FROM private.mobile_registration_feedback WHERE registration_id=p_registration_id AND user_id=p_user_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('action','absent');END IF;
 IF v_receipt.proposal_hash IS DISTINCT FROM encode(extensions.digest(convert_to(v_pending.proposal::text,'UTF8'),'sha256'),'hex')
 THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 RETURN jsonb_build_object('action','available','feedback',v_receipt.feedback);
END;$fn$;
REVOKE ALL ON FUNCTION public.read_mobile_registration_feedback(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_mobile_registration_feedback(uuid,uuid) TO service_role;

CREATE FUNCTION private.assert_feedback_numeric_fields(p_object jsonb,p_keys text[],p_nullable text[],p_positive text[]) RETURNS void
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE k text;v numeric;
BEGIN
 IF jsonb_typeof(p_object) IS DISTINCT FROM 'object' OR NOT(p_object ?& p_keys) OR p_object-p_keys<>'{}'::jsonb
 THEN RAISE EXCEPTION 'feedback numeric object invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY p_keys LOOP
  IF p_object->k='null'::jsonb AND k=ANY(p_nullable) THEN CONTINUE;END IF;
  IF jsonb_typeof(p_object->k) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'feedback numeric type invalid' USING ERRCODE='22023';END IF;
  v:=(p_object->>k)::numeric;
  IF v<0 OR v>9007199254740991 OR (k=ANY(p_positive) AND v<=0)
  THEN RAISE EXCEPTION 'feedback numeric value invalid' USING ERRCODE='22023';END IF;
 END LOOP;
END;$fn$;
REVOKE ALL ON FUNCTION private.assert_feedback_numeric_fields(jsonb,text[],text[],text[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.assert_registration_feedback_shape(p_feedback jsonb,p_id uuid,p_kind text) RETURNS void
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE d jsonb;l jsonb;keys text[]:=ARRAY[]::text[];t text;k text;dt date;
BEGIN
 IF jsonb_typeof(p_feedback) IS DISTINCT FROM 'object'
 OR NOT(p_feedback ?& ARRAY['schema','registration_id','kind','locale','meal_totals','day','lines','food_comment','incentive'])
 OR p_feedback-ARRAY['schema','registration_id','kind','locale','meal_totals','day','lines','food_comment','incentive']<>'{}'::jsonb
 OR p_feedback->>'schema' IS DISTINCT FROM 'registration.feedback.v1' OR p_feedback->>'registration_id' IS DISTINCT FROM p_id::text
 OR p_feedback->>'kind' IS DISTINCT FROM p_kind OR jsonb_typeof(p_feedback->'locale') IS DISTINCT FROM 'string'
 OR p_feedback->>'locale' NOT IN ('pt-BR','en') OR pg_column_size(p_feedback)>131072
 THEN RAISE EXCEPTION 'feedback public shape invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY ARRAY['food_comment','incentive'] LOOP
  IF p_feedback->k='null'::jsonb THEN CONTINUE;END IF;
  IF jsonb_typeof(p_feedback->k) IS DISTINCT FROM 'string' OR btrim(p_feedback->>k)='' OR length(p_feedback->>k)>4000 OR p_feedback->>'locale'='en'
  THEN RAISE EXCEPTION 'feedback phrase invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 IF p_kind='meal' THEN
  PERFORM private.assert_feedback_numeric_fields(p_feedback->'meal_totals',ARRAY['kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY[]::text[]);
 ELSIF p_feedback->'meal_totals' IS DISTINCT FROM 'null'::jsonb OR p_feedback->'food_comment' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'workout feedback carries meal fields' USING ERRCODE='22023';END IF;
 d:=p_feedback->'day';
 IF d<>'null'::jsonb THEN
  IF jsonb_typeof(d) IS DISTINCT FROM 'object' OR NOT(d ?& ARRAY['local_date','current_protocol','remaining_food_kcal','food_excess_kcal','exercise_kcal','consumed','targets','calorie_percentage','protein_percentage'])
   OR d-ARRAY['local_date','current_protocol','remaining_food_kcal','food_excess_kcal','exercise_kcal','consumed','targets','calorie_percentage','protein_percentage']<>'{}'::jsonb
   OR jsonb_typeof(d->'local_date') IS DISTINCT FROM 'string' OR (d->>'local_date') !~ '^\d{4}-\d{2}-\d{2}$'
   OR (d->'current_protocol'<>'null'::jsonb AND (jsonb_typeof(d->'current_protocol') IS DISTINCT FROM 'string' OR d->>'current_protocol' NOT IN ('recomposicao','ganho_massa','manutencao')))
  THEN RAISE EXCEPTION 'feedback day shape invalid' USING ERRCODE='22023';END IF;
  dt:=(d->>'local_date')::date;
  PERFORM private.assert_feedback_numeric_fields(d-ARRAY['local_date','current_protocol','consumed','targets'],
   ARRAY['remaining_food_kcal','food_excess_kcal','exercise_kcal','calorie_percentage','protein_percentage'],
   ARRAY['remaining_food_kcal','food_excess_kcal','calorie_percentage','protein_percentage'],ARRAY[]::text[]);
  PERFORM private.assert_feedback_numeric_fields(d->'consumed',ARRAY['calories_kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY[]::text[]);
  PERFORM private.assert_feedback_numeric_fields(d->'targets',ARRAY['calories_kcal','protein_g'],ARRAY['calories_kcal','protein_g'],ARRAY['calories_kcal','protein_g']);
  IF ((d#>'{targets,calories_kcal}'='null'::jsonb) IS DISTINCT FROM (d->'calorie_percentage'='null'::jsonb))
   OR ((d#>'{targets,protein_g}'='null'::jsonb) IS DISTINCT FROM (d->'protein_percentage'='null'::jsonb))
  THEN RAISE EXCEPTION 'feedback target availability inconsistent' USING ERRCODE='22023';END IF;
 END IF;
 IF jsonb_typeof(p_feedback->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p_feedback->'lines')<1 OR jsonb_array_length(p_feedback->'lines')>5
 THEN RAISE EXCEPTION 'feedback lines invalid' USING ERRCODE='22023';END IF;
 FOR l IN SELECT value FROM jsonb_array_elements(p_feedback->'lines') LOOP
  IF jsonb_typeof(l) IS DISTINCT FROM 'object' OR NOT(l ?& ARRAY['key','text']) OR l-ARRAY['key','text']<>'{}'::jsonb
   OR jsonb_typeof(l->'key') IS DISTINCT FROM 'string' OR l->>'key' NOT IN ('meal_totals','day_calories','day_protein','food_budget','day_unavailable')
   OR (l->>'key')=ANY(keys) OR jsonb_typeof(l->'text') IS DISTINCT FROM 'string' OR btrim(l->>'text')='' OR length(l->>'text')>4000
  THEN RAISE EXCEPTION 'feedback line invalid' USING ERRCODE='22023';END IF;
  keys:=array_append(keys,l->>'key');
 END LOOP;
 IF (p_kind='meal') IS DISTINCT FROM ('meal_totals'=ANY(keys))
 OR (d='null'::jsonb AND (NOT('day_unavailable'=ANY(keys)) OR keys && ARRAY['day_calories','day_protein','food_budget']))
 OR (d<>'null'::jsonb AND ('day_unavailable'=ANY(keys) OR NOT(keys @> ARRAY['day_calories','day_protein'])))
 THEN RAISE EXCEPTION 'feedback lines do not describe available facts' USING ERRCODE='22023';END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.assert_registration_feedback_shape(jsonb,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.commit_mobile_registration_feedback(
 p_user_id uuid,p_registration_id uuid,p_expected_proposal jsonb,p_expected_revision text,
 p_expected_cursor jsonb,p_steps jsonb,p_feedback jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_user public.users%ROWTYPE;v_pending public.pending_registrations%ROWTYPE;v_existing jsonb;
 v_current jsonb;v_cursor jsonb;v_revision bigint;v_kind text;v_prefix text;v_step jsonb;v_index integer:=0;
 v_food jsonb:='null'::jsonb;v_incentive jsonb:='null'::jsonb;v_total jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO v_user FROM public.users WHERE id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 SELECT * INTO v_pending FROM public.pending_registrations WHERE id=p_registration_id AND user_id=p_user_id FOR SHARE;
 IF NOT FOUND OR v_pending.status<>'confirmed' THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 -- Replay after identity/ownership, before CURRENT cursor, proposal parameters or day.
 v_existing:=public.read_mobile_registration_feedback(p_user_id,p_registration_id);
 IF v_existing->>'action'='available' THEN RETURN jsonb_build_object('action','replay','feedback',v_existing->'feedback');END IF;
 IF v_existing->>'action'='event_conflict' THEN RETURN v_existing;END IF;
 IF v_pending.proposal IS DISTINCT FROM p_expected_proposal THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 v_kind:=v_pending.proposal->>'kind';
 IF v_kind IS NULL OR v_kind NOT IN ('meal','workout') THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 IF p_expected_revision IS NULL OR p_expected_revision !~ '^(0|[1-9][0-9]*)$' OR length(p_expected_revision)>19
 THEN RAISE EXCEPTION 'shared revision invalid' USING ERRCODE='22023';END IF;
 IF p_expected_revision::numeric>9223372036854775807 THEN RAISE EXCEPTION 'shared revision invalid' USING ERRCODE='22023';END IF;
 v_current:=public.read_flow_shared_phrase_cursor(p_user_id);
 IF v_current->>'cursor_revision' IS DISTINCT FROM p_expected_revision
 OR v_current->'cursor' IS DISTINCT FROM coalesce(p_expected_cursor,'null'::jsonb)
 THEN RETURN jsonb_build_object('action','cursor_conflict');END IF;
 v_revision:=(v_current->>'cursor_revision')::bigint;
 IF v_revision=9223372036854775807 THEN RAISE EXCEPTION 'shared revision exhausted' USING ERRCODE='22003';END IF;
 v_cursor:=v_current->'cursor';
 IF v_cursor='null'::jsonb THEN v_cursor:=jsonb_build_object('schema','flow.phrase-state.v1','userId',p_user_id::text,
  'catalogVersion','flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb','ordinal',0,'lastTextKey',NULL,'usedTextKeys',jsonb_build_array());END IF;
 IF jsonb_typeof(p_steps) IS DISTINCT FROM 'array' OR jsonb_array_length(p_steps)<>(CASE WHEN v_kind='meal' THEN 2 ELSE 1 END)
 OR pg_column_size(p_steps)>1048576 THEN RAISE EXCEPTION 'registration phrase steps invalid' USING ERRCODE='22023';END IF;
 v_prefix:='mobile_registration/'||p_user_id::text||'/'||p_registration_id::text;
 FOR v_step IN SELECT value FROM jsonb_array_elements(p_steps) LOOP
  IF v_kind='meal' AND v_index=0 THEN
   v_cursor:=private.assert_registration_phrase_step(p_user_id,v_cursor,v_step,v_prefix||'/food','food');
   v_food:=v_step#>'{receipt,selection,phrase}';
  ELSE
   v_cursor:=private.assert_registration_phrase_step(p_user_id,v_cursor,v_step,v_prefix||'/incentive',CASE WHEN v_kind='meal' THEN 'incentive' ELSE 'workout' END);
   v_incentive:=v_step#>'{receipt,selection,phrase}';
  END IF;
  v_index:=v_index+1;
 END LOOP;
 IF jsonb_typeof(p_feedback) IS DISTINCT FROM 'object'
 OR NOT(p_feedback ?& ARRAY['schema','registration_id','kind','locale','meal_totals','day','lines','food_comment','incentive'])
 OR p_feedback-ARRAY['schema','registration_id','kind','locale','meal_totals','day','lines','food_comment','incentive']<>'{}'::jsonb
 OR p_feedback->>'schema' IS DISTINCT FROM 'registration.feedback.v1'
 OR p_feedback->>'registration_id' IS DISTINCT FROM p_registration_id::text
 OR p_feedback->>'kind' IS DISTINCT FROM v_kind OR p_feedback->>'locale' NOT IN ('pt-BR','en')
 OR jsonb_typeof(p_feedback->'locale') IS DISTINCT FROM 'string'
 OR jsonb_typeof(p_feedback->'lines') IS DISTINCT FROM 'array'
 OR p_feedback->'food_comment' IS DISTINCT FROM v_food OR p_feedback->'incentive' IS DISTINCT FROM v_incentive
 OR pg_column_size(p_feedback)>131072
 THEN RAISE EXCEPTION 'registration feedback invalid' USING ERRCODE='22023';END IF;
 PERFORM private.assert_registration_feedback_shape(p_feedback,p_registration_id,v_kind);
 IF v_kind='meal' THEN
  v_total:=jsonb_build_object('kcal',v_pending.proposal#>'{totals,kcal}',
   'protein_g',v_pending.proposal#>'{totals,protein_g}','carbs_g',v_pending.proposal#>'{totals,carbs_g}',
   'fat_g',v_pending.proposal#>'{totals,fat_g}');
  IF p_feedback->'meal_totals' IS DISTINCT FROM v_total THEN RAISE EXCEPTION 'feedback meal totals differ from confirmed facts' USING ERRCODE='22023';END IF;
 ELSE
  IF p_feedback->'meal_totals' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'workout cannot carry meal totals' USING ERRCODE='22023';END IF;
 END IF;
 IF p_feedback->'day'<>'null'::jsonb AND v_pending.proposal ? 'source_local_date'
 AND p_feedback#>>'{day,local_date}' IS DISTINCT FROM v_pending.proposal->>'source_local_date'
 THEN RAISE EXCEPTION 'feedback day differs from confirmed facts' USING ERRCODE='22023';END IF;
 INSERT INTO private.mobile_registration_feedback(registration_id,user_id,proposal_hash,cursor_revision,feedback,steps)
 VALUES(p_registration_id,p_user_id,encode(extensions.digest(convert_to(v_pending.proposal::text,'UTF8'),'sha256'),'hex'),v_revision+1,p_feedback,p_steps);
 UPDATE public.users SET flow_shared_phrase_revision=v_revision+1,
  flow_shared_phrase_legacy_revision=flow_phrase_cursor_revision,flow_shared_phrase_cursor=v_cursor WHERE id=p_user_id;
 -- No exception handler: receipt and both selections/cursor commit or roll back together.
 RETURN jsonb_build_object('action','committed','feedback',p_feedback);
END;$fn$;
REVOKE ALL ON FUNCTION public.commit_mobile_registration_feedback(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_mobile_registration_feedback(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb) TO service_role;
COMMIT;

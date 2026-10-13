-- C5a: atomic Flow phrase cursor and reply, first adoption only.
-- Deploy this migration before enabling the Flow route's phrase reply store.
-- Environment application requires explicit approval; never target old production.
-- Existing two-connection, replay and reset proofs are preserved separately.
-- Dependencies are the REAL existing users/messages schema, index, auth.jwt(),
-- private.assert_trusted_backend(), extensions.digest(), roles and reset tables.
-- Do not install extensions, create roles/tables, use a fake digest or bootstrap
-- dependencies here. No clinical backfill, country/meta writer or new calculator.
-- SHARED RESET IS INCLUDED BELOW: notify WhatsApp impact before implementation.
-- Inert consumer adoption only. If prior namespaces/unknown source exist, abort.

BEGIN;

-- This future DDL bundle needs a measured, brief adoption window. Users first;
-- then block messages DML so the inert-namespace precondition stays true.
-- These locks can briefly block legacy writes; conflicts abort without waiting.
LOCK TABLE public.users IN ACCESS EXCLUSIVE MODE NOWAIT;
LOCK TABLE public.messages IN SHARE ROW EXCLUSIVE MODE NOWAIT;

DO $proposal$
BEGIN
  PERFORM private.assert_trusted_backend();
  IF EXISTS (
    SELECT 1 FROM public.messages WHERE raw_payload ? 'flow_phrase_v1'
  ) THEN
    RAISE EXCEPTION 'flow phrase witness adoption requires explicit policy'
      USING ERRCODE = '22023';
  END IF;
  -- First adoption only. Do not leave an unknown/obsolete overload callable.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE (n.nspname = 'public' AND p.proname IN (
      'read_flow_phrase_cursor','commit_flow_phrase_reply'))
      OR (n.nspname = 'private' AND p.proname = 'assert_flow_phrase_namespace')
  ) THEN
    RAISE EXCEPTION 'flow phrase function adoption requires explicit policy'
      USING ERRCODE = '22023';
  END IF;
END;
$proposal$;

-- No IF NOT EXISTS: incompatible/unknown schema is not silently adopted.
-- Default zero initializes the technical witness; no data-derived UPDATE/backfill.
ALTER TABLE public.users
  ADD COLUMN flow_phrase_cursor_revision bigint NOT NULL DEFAULT 0,
  ADD CONSTRAINT users_flow_phrase_cursor_revision_nonnegative
    CHECK (flow_phrase_cursor_revision >= 0);

-- Existing authenticated users grants are named safe columns, not table SELECT.
-- Column revokes do NOT override an inherited/future table grant: test effective ACL.
REVOKE SELECT (flow_phrase_cursor_revision),
  INSERT (flow_phrase_cursor_revision), UPDATE (flow_phrase_cursor_revision)
  ON public.users FROM PUBLIC, anon, authenticated;

-- Private structural validator: recognized status incentive/any only.
-- Full eligibility/fingerprint/seed/reset proof is still the trusted pure adapter.
CREATE OR REPLACE FUNCTION private.assert_flow_phrase_namespace(
  p_namespace jsonb,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  v_cursor jsonb;
  v_receipt jsonb;
  v_selection jsonb;
  v_revision numeric;
  v_ordinal numeric;
  v_key jsonb;
  v_used text[] := ARRAY[]::text[];
  v_expected_prefix text;
  v_event_key text;
  v_bare_key text;
  v_phrase text;
  v_catalog constant text :=
    'flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb';
BEGIN
  IF p_user_id IS NULL
    OR jsonb_typeof(p_namespace) IS DISTINCT FROM 'object'
    OR NOT (p_namespace ?& ARRAY[
      'schema','cursor_revision','previous_anchor_assistant_id','cursor','receipt'])
    OR (p_namespace - ARRAY[
      'schema','cursor_revision','previous_anchor_assistant_id','cursor','receipt'])
      <> '{}'::jsonb
    OR p_namespace ->> 'schema' IS DISTINCT FROM 'flow.phrase-store.v1'
    OR jsonb_typeof(p_namespace -> 'cursor_revision') IS DISTINCT FROM 'string'
    OR (p_namespace ->> 'cursor_revision') !~ '^[1-9][0-9]*$'
    OR char_length(p_namespace ->> 'cursor_revision') > 19
  THEN
    RAISE EXCEPTION 'flow phrase namespace corrupt' USING ERRCODE = 'P0001';
  END IF;
  v_revision := (p_namespace ->> 'cursor_revision')::numeric;
  IF v_revision > 9223372036854775807 THEN
    RAISE EXCEPTION 'flow phrase revision corrupt' USING ERRCODE = 'P0001';
  END IF;
  IF p_namespace -> 'previous_anchor_assistant_id' <> 'null'::jsonb THEN
    IF jsonb_typeof(p_namespace -> 'previous_anchor_assistant_id')
        IS DISTINCT FROM 'string'
      OR (p_namespace ->> 'previous_anchor_assistant_id')
        !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    THEN
      RAISE EXCEPTION 'flow phrase predecessor corrupt' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  IF (v_revision = 1)
    IS DISTINCT FROM (p_namespace -> 'previous_anchor_assistant_id' = 'null'::jsonb)
  THEN
    RAISE EXCEPTION 'flow phrase predecessor corrupt' USING ERRCODE = 'P0001';
  END IF;

  v_cursor := p_namespace -> 'cursor';
  IF jsonb_typeof(v_cursor) IS DISTINCT FROM 'object'
    OR NOT (v_cursor ?& ARRAY[
      'schema','userId','catalogVersion','ordinal','lastTextKey','usedTextKeys'])
    OR (v_cursor - ARRAY[
      'schema','userId','catalogVersion','ordinal','lastTextKey','usedTextKeys'])
      <> '{}'::jsonb
    OR v_cursor ->> 'schema' IS DISTINCT FROM 'flow.phrase-state.v1'
    OR jsonb_typeof(v_cursor -> 'userId') IS DISTINCT FROM 'string'
    OR v_cursor ->> 'userId' IS DISTINCT FROM p_user_id::text
    OR jsonb_typeof(v_cursor -> 'catalogVersion') IS DISTINCT FROM 'string'
    -- Future approved versions require explicit historical recognition here.
    OR v_cursor ->> 'catalogVersion' IS DISTINCT FROM v_catalog
    OR jsonb_typeof(v_cursor -> 'ordinal') IS DISTINCT FROM 'number'
    OR jsonb_typeof(v_cursor -> 'usedTextKeys') IS DISTINCT FROM 'array'
  THEN
    RAISE EXCEPTION 'flow phrase cursor corrupt' USING ERRCODE = 'P0001';
  END IF;
  v_ordinal := (v_cursor ->> 'ordinal')::numeric;
  IF v_ordinal < 0 OR v_ordinal > 9007199254740991
    OR v_ordinal <> trunc(v_ordinal)
  THEN
    RAISE EXCEPTION 'flow phrase ordinal corrupt' USING ERRCODE = 'P0001';
  END IF;
  IF v_cursor -> 'lastTextKey' <> 'null'::jsonb THEN
    IF jsonb_typeof(v_cursor -> 'lastTextKey') IS DISTINCT FROM 'string'
      OR (v_cursor ->> 'lastTextKey') !~ '^[a-f0-9]{64}$'
    THEN
      RAISE EXCEPTION 'flow phrase text key corrupt' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  FOR v_key IN SELECT value FROM jsonb_array_elements(v_cursor -> 'usedTextKeys')
  LOOP
    IF jsonb_typeof(v_key) IS DISTINCT FROM 'string'
      OR (v_key #>> '{}') !~ '^[a-f0-9]{64}$'
      OR (v_key #>> '{}') = ANY(v_used)
    THEN
      RAISE EXCEPTION 'flow phrase used keys corrupt' USING ERRCODE = 'P0001';
    END IF;
    v_used := array_append(v_used, v_key #>> '{}');
  END LOOP;
  IF cardinality(v_used)::numeric > v_ordinal
    OR (v_ordinal = 0 AND (
      v_cursor -> 'lastTextKey' <> 'null'::jsonb OR cardinality(v_used) <> 0))
    OR (v_ordinal > 0 AND (
      v_cursor -> 'lastTextKey' = 'null'::jsonb
      OR cardinality(v_used) = 0
      OR v_used[cardinality(v_used)] IS DISTINCT FROM v_cursor ->> 'lastTextKey'))
  THEN
    RAISE EXCEPTION 'flow phrase cursor coherence corrupt' USING ERRCODE = 'P0001';
  END IF;

  v_receipt := p_namespace -> 'receipt';
  IF jsonb_typeof(v_receipt) IS DISTINCT FROM 'object'
    OR NOT (v_receipt ?& ARRAY['eventKey','requestFingerprint','selection'])
    OR (v_receipt - ARRAY['eventKey','requestFingerprint','selection']) <> '{}'::jsonb
    OR jsonb_typeof(v_receipt -> 'eventKey') IS DISTINCT FROM 'string'
    OR jsonb_typeof(v_receipt -> 'requestFingerprint') IS DISTINCT FROM 'string'
    OR (v_receipt ->> 'requestFingerprint') !~ '^[a-f0-9]{64}$'
  THEN
    RAISE EXCEPTION 'flow phrase receipt corrupt' USING ERRCODE = 'P0001';
  END IF;
  v_expected_prefix := 'mobile_flow/' || p_user_id::text || '/';
  v_event_key := v_receipt ->> 'eventKey';
  v_bare_key := substring(v_event_key FROM char_length(v_expected_prefix) + 1);
  IF left(v_event_key, char_length(v_expected_prefix)) <> v_expected_prefix
    OR char_length(v_bare_key) NOT BETWEEN 8 AND 128
    OR v_bare_key !~ '^[A-Za-z0-9._:-]+$'
  THEN
    RAISE EXCEPTION 'flow phrase event corrupt' USING ERRCODE = 'P0001';
  END IF;
  v_selection := v_receipt -> 'selection';
  IF jsonb_typeof(v_selection) IS DISTINCT FROM 'object'
    OR NOT (v_selection ?& ARRAY[
      'phrase','phraseId','sourceText','foodCanonicalName','reason'])
    OR (v_selection - ARRAY[
      'phrase','phraseId','sourceText','foodCanonicalName','reason']) <> '{}'::jsonb
    OR jsonb_typeof(v_selection -> 'reason') IS DISTINCT FROM 'string'
    -- Group B is incentive/any for recognized status only.
    OR v_selection -> 'foodCanonicalName' IS DISTINCT FROM 'null'::jsonb
  THEN
    RAISE EXCEPTION 'flow phrase selection corrupt' USING ERRCODE = 'P0001';
  END IF;
  IF v_selection -> 'phrase' = 'null'::jsonb THEN
    IF v_selection -> 'phraseId' IS DISTINCT FROM 'null'::jsonb
      OR v_selection -> 'sourceText' IS DISTINCT FROM 'null'::jsonb
      OR v_selection ->> 'reason' NOT IN (
        'unsupported_language','no_eligible_phrase','only_previous_phrase','rotation_exhausted')
      OR (v_selection ->> 'reason' = 'rotation_exhausted')
        IS DISTINCT FROM (v_ordinal = 9007199254740991)
    THEN
      RAISE EXCEPTION 'flow phrase empty selection corrupt' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    IF jsonb_typeof(v_selection -> 'phrase') IS DISTINCT FROM 'string'
      OR btrim(v_selection ->> 'phrase') = ''
      OR jsonb_typeof(v_selection -> 'phraseId') IS DISTINCT FROM 'string'
      OR (v_selection ->> 'phraseId') !~ '^engagement:[0-9]{3}$'
      OR jsonb_typeof(v_selection -> 'sourceText') IS DISTINCT FROM 'string'
      OR btrim(v_selection ->> 'sourceText') = ''
      OR v_selection ->> 'reason' IS DISTINCT FROM 'selected_incentive'
      OR v_ordinal = 0
    THEN
      RAISE EXCEPTION 'flow phrase selected receipt corrupt' USING ERRCODE = 'P0001';
    END IF;
    v_phrase := v_selection ->> 'phrase';
    IF encode(extensions.digest(convert_to(v_phrase, 'UTF8'), 'sha256'), 'hex')
      IS DISTINCT FROM v_cursor ->> 'lastTextKey'
    THEN
      RAISE EXCEPTION 'flow phrase selected hash corrupt' USING ERRCODE = 'P0001';
    END IF;
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION private.assert_flow_phrase_namespace(jsonb, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Read uses users FOR SHARE; no writes or cursor repair.
CREATE OR REPLACE FUNCTION public.read_flow_phrase_cursor(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $fn$
DECLARE
  v_water bigint;
  v_row public.messages%ROWTYPE;
  v_namespace jsonb;
  v_revision bigint;
  v_anchor uuid;
  v_cursor jsonb := 'null'::jsonb;
  v_seen jsonb := '{}'::jsonb;
  v_exact integer := 0;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid flow phrase read' USING ERRCODE = '22023';
  END IF;
  SELECT u.flow_phrase_cursor_revision INTO v_water
  FROM public.users u WHERE u.id = p_user_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'flow phrase account absent' USING ERRCODE = 'P0002';
  END IF;
  IF v_water IS NULL OR v_water < 0 THEN
    RAISE EXCEPTION 'flow phrase witness corrupt' USING ERRCODE = 'P0001';
  END IF;
  FOR v_row IN
    SELECT m.* FROM public.messages m
    WHERE m.user_id = p_user_id AND m.raw_payload ? 'flow_phrase_v1'
  LOOP
    IF v_row.provider IS DISTINCT FROM 'mobile_flow'
      OR v_row.direction <> 'out' OR v_row.role <> 'assistant'
      OR v_row.content_type <> 'text'
      OR v_row.delivery_status IS DISTINCT FROM 'completed'
      OR v_row.content IS NULL OR btrim(v_row.content) = ''
      OR jsonb_typeof(v_row.raw_payload) IS DISTINCT FROM 'object'
      OR jsonb_typeof(v_row.raw_payload -> 'request_id') IS DISTINCT FROM 'string'
      OR v_row.raw_payload ->> 'conversation_id' IS DISTINCT FROM 'flow'
    THEN
      RAISE EXCEPTION 'flow phrase message corrupt' USING ERRCODE = 'P0001';
    END IF;
    v_namespace := v_row.raw_payload -> 'flow_phrase_v1';
    PERFORM private.assert_flow_phrase_namespace(v_namespace, p_user_id);
    IF v_row.provider_message_id IS DISTINCT FROM
      (v_namespace #>> '{receipt,eventKey}') || '/assistant'
    THEN
      RAISE EXCEPTION 'flow phrase message identity corrupt' USING ERRCODE = 'P0001';
    END IF;
    v_revision := (v_namespace ->> 'cursor_revision')::bigint;
    IF v_revision > v_water THEN
      RAISE EXCEPTION 'flow phrase witness behind publication' USING ERRCODE = 'P0001';
    END IF;
    IF v_namespace #> '{receipt,selection,phrase}' <> 'null'::jsonb
      AND right(v_row.content,
        char_length(v_namespace #>> '{receipt,selection,phrase}'))
        IS DISTINCT FROM v_namespace #>> '{receipt,selection,phrase}'
    THEN
      RAISE EXCEPTION 'flow phrase message text corrupt' USING ERRCODE = 'P0001';
    END IF;
    IF v_seen ? v_revision::text THEN
      RAISE EXCEPTION 'flow phrase duplicate revision' USING ERRCODE = 'P0001';
    END IF;
    v_seen := v_seen || jsonb_build_object(v_revision::text, true);
    IF v_revision = v_water THEN
      v_exact := v_exact + 1;
      v_anchor := v_row.id;
      v_cursor := v_namespace -> 'cursor';
    END IF;
  END LOOP;
  IF (v_water = 0 AND v_seen <> '{}'::jsonb)
    OR (v_water > 0 AND v_exact <> 1)
  THEN
    RAISE EXCEPTION 'flow phrase witness anchor absent' USING ERRCODE = 'P0001';
  END IF;
  RETURN jsonb_build_object(
    'anchor_assistant_id',v_anchor,'cursor_revision',v_water::text,'cursor',v_cursor);
END;
$fn$;

REVOKE ALL ON FUNCTION public.read_flow_phrase_cursor(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_flow_phrase_cursor(uuid) TO service_role;

-- Commit uses users FOR UPDATE, replay before current cursor/CAS.
CREATE OR REPLACE FUNCTION public.commit_flow_phrase_reply(
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
  v_current := public.read_flow_phrase_cursor(p_user_id);
  IF (v_current ->> 'cursor_revision')::bigint <> v_user_revision THEN
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
  IF v_old_revision = 0 THEN
    -- read proved witness zero AND no C5 namespace; reset is the deliberate zero.
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

  UPDATE public.users u
  SET flow_phrase_cursor_revision = v_next_revision
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

REVOKE ALL ON FUNCTION public.commit_flow_phrase_reply(
  uuid,text,uuid,text,text,text,text,text,uuid,text,jsonb,jsonb,jsonb,text,timestamptz,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_flow_phrase_reply(
  uuid,text,uuid,text,text,text,text,text,uuid,text,jsonb,jsonb,jsonb,text,timestamptz,jsonb)
  TO service_role;

-- FULL REAL RESET SOURCE COPIED BELOW.
-- Only added: flow_phrase_cursor_revision = 0 in its final users UPDATE.
-- Keep every delete, onboarding/progress reset, keep_plans behavior, wrapper,
-- response, ACL and search_path exactly as the current source. No new timestamp
-- or metadata behavior; existing metadata/updated_at statements are preserved.
-- M4 — resetting a conversation keeps the patient's plans by default.
--
-- `reset_user_conversation_atomic` is the admin panel's "Resetar conversa":
-- it wipes the conversation, the logs and the onboarding so the flow can be
-- tested again. Until now it also deleted the confirmed training plan and
-- the prescriptions. From this migration on:
--
--   reset_user_conversation_atomic(user)          keeps plans and drafts
--   reset_user_conversation_atomic(user, true)    keeps plans and drafts
--   reset_user_conversation_atomic(user, false)   deletes them too
--
-- Nothing else the reset does changes. It never touches the account itself,
-- subscriptions, the audit log or media (documents stay until the patient
-- deletes them). Deleting an account is a different operation.

CREATE OR REPLACE FUNCTION public.reset_user_conversation_atomic(
  p_user_id uuid,
  p_keep_plans boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_deleted integer;
  v_deleted_total integer := 0;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR p_keep_plans IS NULL THEN
    RAISE EXCEPTION 'invalid reset request' USING ERRCODE = '22023';
  END IF;

  PERFORM 1
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user % not found', p_user_id;
  END IF;

  DELETE FROM public.pending_registrations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_dispatch_outbox WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_buffer WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.tools_audit WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.llm_evaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_gap_reminder_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.engagement_delivery_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.attention_dismissals WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_phrase_cooldown WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_food_corrections WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  IF NOT p_keep_plans THEN
    -- Everything of the plans goes, drafts included (their documents stay:
    -- the patient removes them).
    DELETE FROM public.plan_drafts WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_deleted_total := v_deleted_total + v_deleted;

    DELETE FROM public.prescriptions WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_deleted_total := v_deleted_total + v_deleted;

    DELETE FROM public.training_plans WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_deleted_total := v_deleted_total + v_deleted;
  END IF;

  DELETE FROM public.reevaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.meal_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.workout_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_snapshots WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.messages WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.product_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  INSERT INTO public.user_profiles (
    user_id,
    onboarding_completed,
    onboarding_step
  ) VALUES (
    p_user_id,
    false,
    0
  )
  ON CONFLICT (user_id) DO UPDATE
  SET sex = null,
      birth_date = null,
      height_cm = null,
      weight_kg = null,
      body_fat_percent = null,
      body_fat_measured_at = null,
      activity_level = null,
      training_frequency = null,
      water_intake = null,
      hunger_level = null,
      wake_time = null,
      bedtime = null,
      current_protocol = null,
      goal_type = null,
      goal_value = null,
      deficit_level = null,
      food_organization = null,
      bf_percent_estimated = null,
      bf_source = null,
      bf_estimated_at = null,
      cycle_start_weight_kg = null,
      cycle_start_bf_percent = null,
      cycle_start_training_freq = null,
      cycle_start_at = null,
      onboarding_completed = false,
      onboarding_step = 0,
      updated_at = now();

  INSERT INTO public.user_progress (
    user_id,
    xp_total,
    level,
    current_streak,
    longest_streak,
    blocks_completed,
    deficit_block,
    badges_earned
  ) VALUES (
    p_user_id,
    0,
    1,
    0,
    0,
    0,
    0,
    '{}'::text[]
  )
  ON CONFLICT (user_id) DO UPDATE
  SET xp_total = 0,
      level = 1,
      current_streak = 0,
      longest_streak = 0,
      blocks_completed = 0,
      deficit_block = 0,
      current_weight = null,
      current_bf_percent = null,
      badges_earned = '{}'::text[],
      last_active_date = null,
      next_reevaluation = null,
      updated_at = now();

  UPDATE public.users
  SET name = null,
      flow_phrase_cursor_revision = 0,
      summary = null,
      summary_updated_at = null,
      tags = '{}'::text[],
      admin_notes = null,
      country_confirmed = false,
      last_active_at = null,
      -- The daily delivery of a kept training plan keeps its settings.
      metadata = CASE
        WHEN p_keep_plans THEN jsonb_strip_nulls(jsonb_build_object(
          'training_reminders', metadata -> 'training_reminders',
          'training_delivery_hour', metadata -> 'training_delivery_hour'
        ))
        ELSE '{}'::jsonb
      END,
      updated_at = now()
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'reset', true,
    'user_id', p_user_id,
    'deleted_rows', v_deleted_total,
    'kept_plans', p_keep_plans
  );
END;
$$;

-- The one-argument form keeps its signature and now keeps the plans.
CREATE OR REPLACE FUNCTION public.reset_user_conversation_atomic(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RETURN public.reset_user_conversation_atomic(p_user_id, true);
END;
$$;

REVOKE ALL ON FUNCTION public.reset_user_conversation_atomic(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reset_user_conversation_atomic(uuid, boolean)
  TO service_role;
REVOKE ALL ON FUNCTION public.reset_user_conversation_atomic(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reset_user_conversation_atomic(uuid)
  TO service_role;

COMMIT;

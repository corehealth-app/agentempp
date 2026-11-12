-- Journal3 follows a genuine canonical3 winner without weakening old readers.
-- Registration, feedback, rewards and the v1/v2 history paths stay unchanged.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'journal_feedback_v3_requires_postgres' USING ERRCODE='42501';END IF;
 IF to_regprocedure('public.read_mobile_registration_feedback_v3(uuid,uuid,text)') IS NULL
  OR to_regclass('private.mobile_registration_feedback_claims') IS NULL
  OR to_regclass('private.mobile_registration_feedback_v3') IS NULL THEN
  RAISE EXCEPTION 'journal_feedback_v3_missing_substrate';END IF;
 IF to_regprocedure('private.conversation_journal_feedback_ref_v3(private.conversation_meal_effects)') IS NOT NULL
  OR to_regprocedure('private.conversation_journal_child_v3(uuid,uuid,jsonb)') IS NOT NULL
  OR to_regprocedure('private.conversation_journal_entry_v3(uuid,jsonb,jsonb,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'journal_feedback_v3_unknown_existing_helper';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc
   WHERE oid='public.read_mobile_registration_feedback_v3(uuid,uuid,text)'::regprocedure)
   IS DISTINCT FROM '381dbb9fb7464bf3cc1e5ebc63ee16d1c68cdf9ec7f1b2aba693151829e517c5' THEN
  RAISE EXCEPTION 'journal_feedback_v3_unknown_canonical_reader';END IF;
END $preflight$;

CREATE FUNCTION private.conversation_journal_feedback_ref_v3(e private.conversation_meal_effects) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE registration uuid;result jsonb;feedback jsonb;
BEGIN
 registration:=(e.receipt->>'registration_id')::uuid;
 -- Legacy winners retain the exact old helper and its absence/refusal behavior.
 -- A canonical3 row without its reciprocal claim must also refuse, never fall
 -- through to an apparent missing old receipt.
 IF NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_claims c
    WHERE c.user_id=e.user_id AND c.origin='pending_registration' AND c.registration_id=registration AND c.version=3)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v3 f
    WHERE f.user_id=e.user_id AND f.origin='pending_registration' AND f.registration_id=registration) THEN
  RETURN private.conversation_thread_feedback_ref_v2(e);
 END IF;
 result:=public.read_mobile_registration_feedback_v3(e.user_id,registration,'pending_registration');
 feedback:=result->'feedback';
 IF result->>'action' IS DISTINCT FROM 'available'
  OR feedback->>'schema' IS DISTINCT FROM 'registration.feedback.v3'
  OR feedback->'registration_id' IS DISTINCT FROM e.receipt->'registration_id'
  OR feedback#>>'{registration,kind}' IS DISTINCT FROM 'meal'
  OR NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v3 f
    WHERE f.user_id=e.user_id AND f.origin='pending_registration' AND f.registration_id=registration
     AND f.meal_command_id=e.command_id) THEN
  RETURN '{"action":"event_conflict"}'::jsonb;
 END IF;
 RETURN jsonb_build_object('schema','registration.feedback.v3','registration_id',registration);
EXCEPTION WHEN data_exception THEN RETURN '{"action":"event_conflict"}'::jsonb;
END $$;

-- Reuse the qualified factual/lineage validators verbatim under journal-only
-- identities. Replace only their feedback-reference port, then only journal3's
-- two call sites. No global old helper, writer or old journal is widened.
DO $journal_only$
DECLARE sig text;expected text;new_name text;body text;definition text;needle text;replacement text;
BEGIN
 FOR sig,expected,new_name IN SELECT * FROM (VALUES
  ('private.conversation_thread_child_v2(uuid,uuid,jsonb)',
   '9933d32584de6752a17d698b15e9fef1589577a9f09677bbb1910566bccc5e4b','conversation_journal_child_v3'),
  ('private.conversation_thread_entry_v2(uuid,jsonb,jsonb,jsonb)',
   'a9af0f241cd397130db8234beb8926f070407be19014698d93cc8e6104810459','conversation_journal_entry_v3')
 ) AS qualified(signature,source_hash,helper_name) LOOP
  SELECT prosrc,pg_get_functiondef(oid) INTO body,definition FROM pg_proc WHERE oid=to_regprocedure(sig);
  IF encode(sha256(convert_to(body,'UTF8')),'hex') IS DISTINCT FROM expected THEN
   RAISE EXCEPTION 'journal_feedback_v3_unqualified_helper:%',sig;END IF;
  needle:='private.conversation_thread_feedback_ref_v2(';
  IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN
   RAISE EXCEPTION 'journal_feedback_v3_reference_hook:%',sig;END IF;
  definition:=replace(definition,split_part(sig,'(',1)||'(','private.'||new_name||'(');
  EXECUTE replace(definition,needle,'private.conversation_journal_feedback_ref_v3(');
 END LOOP;
 sig:='public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)';
 SELECT prosrc,pg_get_functiondef(oid) INTO body,definition FROM pg_proc WHERE oid=to_regprocedure(sig);
 IF encode(sha256(convert_to(body,'UTF8')),'hex') IS DISTINCT FROM
  'd64c2ba448a29687d319f3712b9d6f5607579e513f0773dec66ebb020305f91d' THEN
  RAISE EXCEPTION 'journal_feedback_v3_unqualified_page_reader';END IF;
 FOR needle,replacement IN SELECT * FROM (VALUES
  ('private.conversation_thread_child_v2(','private.conversation_journal_child_v3('),
  ('private.conversation_thread_entry_v2(','private.conversation_journal_entry_v3(')
 ) AS hooks(old_call,new_call) LOOP
  IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN
   RAISE EXCEPTION 'journal_feedback_v3_page_hook:%',needle;END IF;
  definition:=replace(definition,needle,replacement);
 END LOOP;
 EXECUTE definition;
END $journal_only$;
REVOKE ALL ON FUNCTION private.conversation_journal_feedback_ref_v3(private.conversation_meal_effects),
 private.conversation_journal_child_v3(uuid,uuid,jsonb),private.conversation_journal_entry_v3(uuid,jsonb,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

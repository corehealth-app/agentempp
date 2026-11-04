-- Durable terminal non-registration and a private, read-only journal projection.
-- Neither a read nor an unfinished model attempt can create a terminal decision.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_meal_semantic_results') IS NULL
  OR to_regclass('private.conversation_meal_edit_operations') IS NULL
  OR to_regprocedure('private.lock_conversation_meal(uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'meal_decisions_require_current_journal' USING ERRCODE='55000';END IF;
END $$;

CREATE TABLE private.conversation_meal_decisions(
 user_id uuid NOT NULL,command_id uuid NOT NULL,epoch uuid NOT NULL,
 input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),source_hash text NOT NULL CHECK(source_hash ~ '^[0-9a-f]{64}$'),
 attempt_id uuid NOT NULL,semantic_result_hash text NOT NULL CHECK(semantic_result_hash ~ '^[0-9a-f]{64}$'),
 decision_hash text NOT NULL CHECK(decision_hash ~ '^[0-9a-f]{64}$'),
 decision jsonb NOT NULL CHECK(jsonb_typeof(decision)='object'),sealed_at timestamptz NOT NULL CHECK(isfinite(sealed_at)),
 PRIMARY KEY(user_id,command_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE,
 FOREIGN KEY(user_id,command_id,attempt_id) REFERENCES private.conversation_meal_semantic_results ON DELETE CASCADE
);
ALTER TABLE private.conversation_meal_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_decisions FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.guard_conversation_meal_decision() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id) OR
  NOT EXISTS(SELECT 1 FROM private.conversation_meal_source_captures WHERE user_id=OLD.user_id AND command_id=OLD.command_id)) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'conversation_meal_decision_immutable' USING ERRCODE='22023';
END $$;
CREATE TRIGGER immutable_conversation_meal_decision BEFORE UPDATE OR DELETE ON private.conversation_meal_decisions
 FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_meal_decision();

CREATE FUNCTION private.assert_conversation_meal_decision(v jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE item jsonb;n numeric;seen integer[]:='{}';
BEGIN
 PERFORM private.conversation_meal_keys(v,ARRAY['schema','status','reason','food_indexes']);
 IF v->>'schema' IS DISTINCT FROM 'conversation.meal-decision.v1' OR v->>'status' IS DISTINCT FROM 'not_recorded'
  OR jsonb_typeof(v->'reason') IS DISTINCT FROM 'string' OR coalesce(NOT((v->>'reason' COLLATE "C") ~ '^[a-z_]{1,80}$'),true)
  OR jsonb_typeof(v->'food_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'food_indexes')>30 THEN
  RAISE EXCEPTION 'invalid_conversation_meal_decision' USING ERRCODE='22023';END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(v->'food_indexes') LOOP
  IF jsonb_typeof(item)<>'number' THEN RAISE EXCEPTION 'invalid_conversation_meal_decision' USING ERRCODE='22023';END IF;
  n:=(item#>>'{}')::numeric;
  IF n<0 OR n>29 OR n<>trunc(n) OR n::integer=ANY(seen) THEN RAISE EXCEPTION 'invalid_conversation_meal_decision' USING ERRCODE='22023';END IF;
  seen:=array_append(seen,n::integer);
 END LOOP;
END $$;
CREATE FUNCTION private.conversation_meal_decision_receipt(d private.conversation_meal_decisions) RETURNS jsonb
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT (d).decision||jsonb_build_object('owner_id',(d).user_id,'command_id',(d).command_id,'epoch',(d).epoch,
  'input_hash',(d).input_hash,'source_hash',(d).source_hash,'attempt_id',(d).attempt_id,'semantic_result_hash',(d).semantic_result_hash,
  'decision_hash',(d).decision_hash,'sealed_at',to_char((d).sealed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
$$;
CREATE FUNCTION private.conversation_meal_decision_valid(d private.conversation_meal_decisions,c private.conversation_meal_command_ids,
 s private.conversation_meal_source_captures,a private.conversation_meal_semantic_attempts,r private.conversation_meal_semantic_results) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT coalesce((d).command_id IS NOT NULL AND (d).user_id=(c).user_id AND (d).command_id=(c).command_id
  AND (d).epoch=(c).epoch AND (d).input_hash=(c).input_hash AND (d).source_hash=(s).source_hash
  AND (a).attempt_id=(d).attempt_id AND (a).epoch=(c).epoch AND (a).input_hash=(c).input_hash AND (a).source_hash=(s).source_hash
  AND (a).interpreter_version='conversation.meal-interpreter.v1' AND (r).attempt_id=(a).attempt_id AND (r).status='completed'
  AND (r).result_hash=(d).semantic_result_hash
  AND (r).result_hash=encode(sha256(convert_to(private.conversation_command_canonical((r).result),'UTF8')),'hex')
  AND (d).decision_hash=encode(sha256(convert_to(private.conversation_command_canonical((d).decision),'UTF8')),'hex'),false);
$$;

-- Both qualified writers already hold the same owner/epoch/command lane before
-- insertion. This additive fence leaves their proven bodies unchanged.
CREATE FUNCTION private.fence_conversation_meal_decision() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM private.conversation_meal_decisions WHERE user_id=NEW.user_id AND command_id=NEW.command_id) THEN
  RAISE EXCEPTION 'conversation_meal_terminal_decision' USING ERRCODE='40001';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_decision_before_resolved BEFORE INSERT ON private.conversation_meal_resolved
 FOR EACH ROW EXECUTE FUNCTION private.fence_conversation_meal_decision();
CREATE TRIGGER conversation_decision_before_effect BEFORE INSERT ON private.conversation_meal_effects
 FOR EACH ROW EXECUTE FUNCTION private.fence_conversation_meal_decision();

CREATE FUNCTION public.seal_conversation_meal_decision(p_user_id uuid,p_command_id uuid,p_expected_epoch uuid,p_expected_input_hash text,
 p_expected_source_hash text,p_attempt_id uuid,p_expected_result_hash text,p_decision jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;
 a private.conversation_meal_semantic_attempts%ROWTYPE;r private.conversation_meal_semantic_results%ROWTYPE;d private.conversation_meal_decisions%ROWTYPE;raw jsonb;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_command_id);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=p_command_id;
 IF p_expected_epoch IS DISTINCT FROM c.epoch THEN RETURN '{"action":"stale_epoch"}'::jsonb;END IF;
 IF p_expected_input_hash IS DISTINCT FROM c.input_hash THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"source_required"}'::jsonb;END IF;
 IF p_expected_source_hash IS DISTINCT FROM s.source_hash THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT private.conversation_meal_stored_source_valid(c,raw,s) THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 SELECT * INTO a FROM private.conversation_meal_semantic_attempts WHERE user_id=p_user_id AND command_id=p_command_id AND interpreter_version='conversation.meal-interpreter.v1';
 SELECT * INTO r FROM private.conversation_meal_semantic_results WHERE user_id=p_user_id AND command_id=p_command_id AND attempt_id=a.attempt_id;
 IF r.status IS DISTINCT FROM 'completed' THEN RETURN '{"action":"semantic_required"}'::jsonb;END IF;
 IF p_attempt_id IS DISTINCT FROM a.attempt_id OR p_expected_result_hash IS DISTINCT FROM r.result_hash
  OR a.epoch IS DISTINCT FROM c.epoch OR a.input_hash IS DISTINCT FROM c.input_hash OR a.source_hash IS DISTINCT FROM s.source_hash THEN
  RETURN '{"action":"semantic_conflict"}'::jsonb;END IF;
 SELECT * INTO d FROM private.conversation_meal_decisions WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN
  IF NOT private.conversation_meal_decision_valid(d,c,s,a,r) THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  IF p_decision IS DISTINCT FROM d.decision THEN RETURN '{"action":"decision_conflict"}'::jsonb;END IF;
  RETURN jsonb_build_object('action','replay','command',private.conversation_meal_command_binding(c),'decision',private.conversation_meal_decision_receipt(d));
 END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=p_user_id AND command_id=p_command_id)
  OR EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=p_user_id AND command_id=p_command_id) THEN RETURN '{"action":"resolved_conflict"}'::jsonb;END IF;
 PERFORM private.assert_conversation_meal_decision(p_decision);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_decision->'food_indexes') x WHERE NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(r.result->'foods') f WHERE (f->>'index')::numeric=(x#>>'{}')::numeric)) THEN RETURN '{"action":"semantic_conflict"}'::jsonb;END IF;
 INSERT INTO private.conversation_meal_decisions VALUES(p_user_id,p_command_id,c.epoch,c.input_hash,s.source_hash,a.attempt_id,r.result_hash,
  encode(sha256(convert_to(private.conversation_command_canonical(p_decision),'UTF8')),'hex'),p_decision,clock_timestamp()) RETURNING * INTO d;
 IF NOT private.conversation_meal_decision_valid(d,c,s,a,r) THEN RAISE EXCEPTION 'conversation_meal_decision_binding_conflict' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('action','sealed','command',private.conversation_meal_command_binding(c),'decision',private.conversation_meal_decision_receipt(d));
END $$;

CREATE FUNCTION public.read_conversation_meal_decision(p_user_id uuid,p_command_id uuid,p_expected_epoch uuid,p_expected_input_hash text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'invalid_conversation_decision_read' USING ERRCODE='22023';END IF;
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e.epoch OR c.epoch IS DISTINCT FROM p_expected_epoch OR raw.command_id IS NULL THEN '{"action":"stale_epoch"}'::jsonb
  WHEN c.input_hash IS DISTINCT FROM p_expected_input_hash THEN '{"action":"input_conflict"}'::jsonb
  WHEN NOT private.conversation_meal_stored_source_valid(c,raw.source_input,s) THEN '{"action":"event_conflict"}'::jsonb
  WHEN d.command_id IS NULL THEN '{"action":"absent"}'::jsonb
  WHEN NOT private.conversation_meal_decision_valid(d,c,s,a,r) THEN '{"action":"event_conflict"}'::jsonb
  ELSE jsonb_build_object('action','available','command',private.conversation_meal_command_binding(c),'decision',private.conversation_meal_decision_receipt(d)) END INTO result
 FROM private.conversation_meal_command_ids c JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs e ON e.user_id=c.user_id
 LEFT JOIN private.conversation_meal_command_sources raw ON raw.user_id=c.user_id AND raw.command_id=c.command_id
 LEFT JOIN private.conversation_meal_source_captures s ON s.user_id=c.user_id AND s.command_id=c.command_id
 LEFT JOIN private.conversation_meal_decisions d ON d.user_id=c.user_id AND d.command_id=c.command_id
 LEFT JOIN private.conversation_meal_semantic_attempts a ON a.user_id=d.user_id AND a.command_id=d.command_id AND a.attempt_id=d.attempt_id
 LEFT JOIN private.conversation_meal_semantic_results r ON r.user_id=a.user_id AND r.command_id=a.command_id AND r.attempt_id=a.attempt_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;

CREATE INDEX conversation_command_journal_page ON private.conversation_meal_command_ids(user_id,epoch,admitted_at DESC,command_id DESC);
CREATE INDEX conversation_edit_journal_page ON private.conversation_meal_edit_operations(user_id,applied_at DESC,command_id DESC,operation_id DESC);
CREATE FUNCTION private.conversation_meal_journal_events(p_user uuid,p_epoch uuid)
RETURNS TABLE(at timestamptz,event_id text,command_id uuid,operation_id uuid)
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT c.admitted_at,'command/'||c.command_id::text,c.command_id,NULL::uuid
 FROM private.conversation_meal_command_ids c WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL
 UNION ALL
 SELECT op.applied_at,'edit/'||c.command_id::text||'/'||op.operation_id::text,c.command_id,op.operation_id
 FROM private.conversation_meal_edit_operations op JOIN private.conversation_meal_command_ids c ON c.user_id=op.user_id AND c.command_id=op.command_id
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL;
$$;
-- Closed receipt projection deliberately excludes any future private fields.
CREATE FUNCTION private.conversation_meal_journal_receipt(v jsonb,is_edit boolean) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN v IS NULL THEN NULL ELSE coalesce(jsonb_object_agg(key,value),'{}'::jsonb) END
 FROM jsonb_each(v) WHERE key=ANY(CASE WHEN is_edit THEN
  ARRAY['schema','owner_id','command_id','operation_id','input_hash','kind','revision','applied_at','undo_expires_at','target_operation_id','removed_item_ids','new_item_ids','next_record_id','snapshot']
 ELSE ARRAY['schema','owner_id','command_id','input_hash','registration_id','provider_key','meal_type','local_date','timezone','consumed_at','log_ids','effect_version'] END);
$$;
CREATE FUNCTION private.conversation_meal_journal_entry(p_user uuid,p_command uuid,p_operation uuid,p_at timestamptz,p_event_id text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;
 a private.conversation_meal_semantic_attempts%ROWTYPE;r private.conversation_meal_semantic_results%ROWTYPE;d private.conversation_meal_decisions%ROWTYPE;
 fx private.conversation_meal_effects%ROWTYPE;op private.conversation_meal_edit_operations%ROWTYPE;raw jsonb;receipt jsonb;
BEGIN
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_command;
 SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_command;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_command;
 IF NOT private.conversation_meal_stored_source_valid(c,raw,s) THEN RETURN NULL;END IF;
 SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_command;
 IF fx.command_id IS NOT NULL AND (s.command_id IS NULL OR fx.receipt->>'owner_id' IS DISTINCT FROM c.user_id::text
  OR fx.receipt->>'command_id' IS DISTINCT FROM c.command_id::text OR fx.receipt->>'input_hash' IS DISTINCT FROM c.input_hash
  OR NOT EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=p_user AND command_id=p_command)) THEN RETURN NULL;END IF;
 IF p_operation IS NOT NULL THEN
  SELECT * INTO op FROM private.conversation_meal_edit_operations WHERE user_id=p_user AND command_id=p_command AND operation_id=p_operation;
  IF op.operation_id IS NULL OR fx.command_id IS NULL OR op.applied_at IS DISTINCT FROM p_at OR op.receipt->>'owner_id' IS DISTINCT FROM c.user_id::text
   OR op.receipt->>'command_id' IS DISTINCT FROM c.command_id::text OR op.receipt->>'operation_id' IS DISTINCT FROM p_operation::text THEN RETURN NULL;END IF;
  receipt:=private.conversation_meal_journal_receipt(op.receipt,true);
  -- The nested snapshot also has an explicit factual whitelist.
  receipt:=jsonb_set(receipt,'{snapshot}',(SELECT jsonb_object_agg(key,value) FROM jsonb_each(receipt->'snapshot')
   WHERE key=ANY(ARRAY['id','date','calories_consumed','protein_g','carbs_g','fat_g','daily_balance'])));
  RETURN jsonb_build_object('event_id',p_event_id,'at',to_char(p_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'kind','edit','command',private.conversation_meal_command_binding(c),'receipt',receipt);
 END IF;
 SELECT * INTO d FROM private.conversation_meal_decisions WHERE user_id=p_user AND command_id=p_command;
 IF d.command_id IS NOT NULL THEN
  SELECT * INTO a FROM private.conversation_meal_semantic_attempts WHERE user_id=p_user AND command_id=p_command AND attempt_id=d.attempt_id;
  SELECT * INTO r FROM private.conversation_meal_semantic_results WHERE user_id=p_user AND command_id=p_command AND attempt_id=d.attempt_id;
  IF fx.command_id IS NOT NULL OR NOT private.conversation_meal_decision_valid(d,c,s,a,r) THEN RETURN NULL;END IF;
 END IF;
 RETURN jsonb_build_object('event_id',p_event_id,'at',to_char(p_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'kind','command','command',private.conversation_meal_command_binding(c),'source_input',raw,
  'status',CASE WHEN fx.command_id IS NOT NULL THEN 'registered' WHEN d.command_id IS NOT NULL THEN 'not_recorded' ELSE 'pending' END,
  'receipt',private.conversation_meal_journal_receipt(fx.receipt,false),
  'decision',CASE WHEN d.command_id IS NULL THEN NULL ELSE private.conversation_meal_decision_receipt(d) END);
END $$;

CREATE FUNCTION public.read_conversation_meal_journal_page(p_user_id uuid,p_expected_epoch uuid,p_limit integer DEFAULT 10,p_cursor jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE epoch uuid;cursor_at timestamptz;cursor_id text;row record;items jsonb:='[]';entry jsonb;next_cursor jsonb;more boolean:=false;n integer:=0;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'invalid_conversation_journal_page' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"absent"}'::jsonb;END IF;
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE user_id=p_user_id;
 IF epoch IS NULL OR p_expected_epoch IS DISTINCT FROM epoch THEN RETURN '{"action":"stale_epoch"}'::jsonb;END IF;
 IF p_cursor IS NOT NULL THEN
  BEGIN
   PERFORM private.conversation_meal_keys(p_cursor,ARRAY['at','id']);
   IF jsonb_typeof(p_cursor->'at') IS DISTINCT FROM 'string' OR jsonb_typeof(p_cursor->'id') IS DISTINCT FROM 'string'
    OR NOT(p_cursor->>'at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$')
    OR NOT(p_cursor->>'id' ~ '^(command/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|edit/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$') THEN
    RAISE EXCEPTION 'invalid_cursor';END IF;
   cursor_at:=(p_cursor->>'at')::timestamptz;cursor_id:=p_cursor->>'id';
   IF NOT isfinite(cursor_at) OR NOT EXISTS(SELECT 1 FROM private.conversation_meal_journal_events(p_user_id,epoch) e WHERE e.at=cursor_at AND e.event_id=cursor_id) THEN RAISE EXCEPTION 'invalid_cursor';END IF;
  EXCEPTION WHEN data_exception OR raise_exception THEN RETURN '{"action":"cursor_conflict"}'::jsonb;END;
 END IF;
 FOR row IN SELECT e.* FROM private.conversation_meal_journal_events(p_user_id,epoch) e
  WHERE cursor_at IS NULL OR e.at<cursor_at OR (e.at=cursor_at AND (e.event_id COLLATE "C")<(cursor_id COLLATE "C"))
  ORDER BY e.at DESC,e.event_id COLLATE "C" DESC LIMIT p_limit+1 LOOP
  n:=n+1;IF n>p_limit THEN more:=true;EXIT;END IF;
  entry:=private.conversation_meal_journal_entry(p_user_id,row.command_id,row.operation_id,row.at,row.event_id);
  IF entry IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  items:=items||jsonb_build_array(entry);next_cursor:=jsonb_build_object('at',entry->'at','id',entry->'event_id');
 END LOOP;
 RETURN jsonb_build_object('action','available','owner_id',p_user_id,'epoch',epoch,'items',items,'has_more',more,
  'next_cursor',CASE WHEN more THEN next_cursor ELSE NULL END);
END $$;

REVOKE ALL ON FUNCTION private.guard_conversation_meal_decision(),private.assert_conversation_meal_decision(jsonb),
 private.conversation_meal_decision_receipt(private.conversation_meal_decisions),
 private.conversation_meal_decision_valid(private.conversation_meal_decisions,private.conversation_meal_command_ids,private.conversation_meal_source_captures,private.conversation_meal_semantic_attempts,private.conversation_meal_semantic_results),
 private.fence_conversation_meal_decision(),private.conversation_meal_journal_events(uuid,uuid),private.conversation_meal_journal_receipt(jsonb,boolean),
 private.conversation_meal_journal_entry(uuid,uuid,uuid,timestamptz,text),
 public.seal_conversation_meal_decision(uuid,uuid,uuid,text,text,uuid,text,jsonb),public.read_conversation_meal_decision(uuid,uuid,uuid,text),
 public.read_conversation_meal_journal_page(uuid,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.seal_conversation_meal_decision(uuid,uuid,uuid,text,text,uuid,text,jsonb),
 public.read_conversation_meal_decision(uuid,uuid,uuid,text),public.read_conversation_meal_journal_page(uuid,uuid,integer,jsonb) TO service_role;
COMMIT;

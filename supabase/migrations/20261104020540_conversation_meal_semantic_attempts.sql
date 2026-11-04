-- Dormant one-attempt interpreter journal and read-only writer recovery.
-- A committed fresh `claimed` response alone authorizes one physical request.
-- Reads/replays/unknown never authorize another request; no lease or expiry.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_meal_source_captures') IS NULL
  OR to_regclass('private.conversation_meal_resolved') IS NULL OR to_regclass('private.conversation_meal_effects') IS NULL
  OR to_regprocedure('private.lock_conversation_meal(uuid,uuid)') IS NULL
  OR to_regclass('private.conversation_meal_semantic_attempts') IS NOT NULL THEN
  RAISE EXCEPTION 'semantic_attempts_require_current_substrate' USING ERRCODE='42501'; END IF;
END $preflight$;

CREATE TABLE private.conversation_meal_semantic_attempts (
 user_id uuid NOT NULL,command_id uuid NOT NULL,interpreter_version text COLLATE "C" NOT NULL CHECK(interpreter_version='conversation.meal-interpreter.v1'),
 epoch uuid NOT NULL,input_hash text NOT NULL CHECK(input_hash ~ '^[a-f0-9]{64}$'),source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 attempt_id uuid NOT NULL UNIQUE,started_at timestamptz NOT NULL CHECK(isfinite(started_at)),
 PRIMARY KEY(user_id,command_id,interpreter_version),UNIQUE(user_id,command_id,attempt_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE
);
-- Epoch/source_hash are functionally fixed by this immutable parent command.
CREATE TABLE private.conversation_meal_semantic_results (
 user_id uuid NOT NULL,command_id uuid NOT NULL,attempt_id uuid NOT NULL,status text NOT NULL CHECK(status IN('completed','unknown','error')),
 result jsonb,result_hash text,error_code text,finished_at timestamptz NOT NULL CHECK(isfinite(finished_at)),
 PRIMARY KEY(user_id,command_id,attempt_id),FOREIGN KEY(user_id,command_id,attempt_id)
 REFERENCES private.conversation_meal_semantic_attempts(user_id,command_id,attempt_id) ON DELETE CASCADE,
 CHECK((status='completed' AND result IS NOT NULL AND jsonb_typeof(result)='object' AND result_hash IS NOT NULL AND result_hash ~ '^[a-f0-9]{64}$' AND error_code IS NULL)
  OR (status='unknown' AND result IS NULL AND result_hash IS NULL AND error_code IS NOT NULL AND error_code='provider_outcome_unknown')
  OR (status='error' AND result IS NULL AND result_hash IS NULL AND error_code IS NOT NULL AND error_code='provider_terminal_error'))
);
ALTER TABLE private.conversation_meal_semantic_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_semantic_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_semantic_attempts,private.conversation_meal_semantic_results FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_conversation_semantic_attempt BEFORE UPDATE ON private.conversation_meal_semantic_attempts FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER immutable_conversation_semantic_result BEFORE UPDATE ON private.conversation_meal_semantic_results FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();

CREATE FUNCTION private.conversation_meal_stored_source_valid(c private.conversation_meal_command_ids,raw jsonb,s private.conversation_meal_source_captures) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT coalesce(raw IS NOT NULL AND raw->>'command_id'=(c).command_id::text
  AND encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex')=(c).input_hash
  AND ((s).command_id IS NULL OR ((s).user_id=(c).user_id AND (s).command_id=(c).command_id
   AND (s).context->>'owner_id'=(c).user_id::text AND (s).context->>'command_id'=(c).command_id::text
   AND (s).context->>'epoch'=(c).epoch::text AND (s).context->>'input_hash'=(c).input_hash
   AND (s).context->'source_input'=raw AND (s).source_hash=encode(sha256(convert_to(private.conversation_command_canonical((s).context),'UTF8')),'hex'))),false);
$$;
CREATE FUNCTION private.conversation_semantic_state(a private.conversation_meal_semantic_attempts,r private.conversation_meal_semantic_results,action text) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT jsonb_build_object('action',action,'owner_id',(a).user_id,'command_id',(a).command_id,'attempt_id',(a).attempt_id,
  'interpreter_version',(a).interpreter_version,'input_hash',(a).input_hash,'source_hash',(a).source_hash,'epoch',(a).epoch,
  'status',coalesce((r).status,'started'),'result',(r).result,'result_hash',(r).result_hash,'error_code',(r).error_code,
  'started_at',to_char((a).started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'finished_at',CASE WHEN (r).finished_at IS NULL THEN NULL ELSE to_char((r).finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END);
$$;
CREATE FUNCTION private.conversation_utf16_length(value text) RETURNS integer
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT coalesce(sum(CASE WHEN ascii(ch)>65535 THEN 2 ELSE 1 END),0)::integer FROM regexp_split_to_table(value,'') ch;
$$;
CREATE FUNCTION private.conversation_utf16_boundary(value text,p_position integer) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE ch text;n integer:=0;
BEGIN
 IF p_position=0 THEN RETURN true; END IF;
 FOR ch IN SELECT regexp_split_to_table(value,'') LOOP n:=n+CASE WHEN ascii(ch)>65535 THEN 2 ELSE 1 END;
  IF n=p_position THEN RETURN true; END IF;IF n>p_position THEN RETURN false; END IF;END LOOP;
 RETURN false;
END $$;
CREATE FUNCTION private.conversation_semantic_uint(value jsonb,maximum numeric) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE n numeric;
BEGIN
 IF jsonb_typeof(value) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
 n:=(value#>>'{}')::numeric;
 IF n<0 OR n>maximum OR n<>trunc(n) THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
 RETURN n;
END $$;
CREATE FUNCTION private.conversation_semantic_text(c jsonb,source_unit text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE source_unit WHEN 'command_text' THEN c#>>'{source_input,source,text}' WHEN 'media_caption' THEN c#>>'{source_evidence,caption}' WHEN 'media_transcript' THEN c#>>'{source_evidence,transcript}' ELSE NULL END;
$$;
CREATE FUNCTION private.assert_conversation_semantic_result(v jsonb,a private.conversation_meal_semantic_attempts,c jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE src jsonb;span jsonb;food jsonb;ref jsonb;metadata jsonb;source_unit text;span_kind text;text_value text;text_length integer;span_cursor integer;
 start_at integer;end_at integer;n integer;food_index_var integer;food_count integer;visual_count integer:=0;seen text[]:='{}';seen_indexes integer[];k text;
BEGIN
 PERFORM private.conversation_meal_keys(v,ARRAY['schema','interpreter_version','owner_id','command_id','attempt_id','input_hash','source_hash','source_units','decision','reason','sources','foods','provider_metadata']);
 IF v->>'schema' IS DISTINCT FROM 'conversation.meal-interpretation.v1' OR v->>'interpreter_version' IS DISTINCT FROM (a).interpreter_version
  OR v->>'owner_id' IS DISTINCT FROM (a).user_id::text OR v->>'command_id' IS DISTINCT FROM (a).command_id::text OR v->>'attempt_id' IS DISTINCT FROM (a).attempt_id::text
  OR jsonb_typeof(v->'input_hash') IS DISTINCT FROM 'string' OR v->>'input_hash' IS DISTINCT FROM (a).input_hash
  OR jsonb_typeof(v->'source_hash') IS DISTINCT FROM 'string' OR v->>'source_hash' IS DISTINCT FROM (a).source_hash
  OR v->'source_units' IS DISTINCT FROM c->'source_units' OR v->>'decision' IS NULL OR v->>'decision' NOT IN('reported_meal','not_reported','clarification_required')
  OR v->>'reason' IS NULL OR v->>'reason' NOT IN('explicit_report','nominal_food_list','explicit_media_action','dream','future','habit','negated','third_party','question','mixed','ambiguous')
  OR jsonb_typeof(v->'sources') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'sources') NOT BETWEEN 1 AND 4
  OR jsonb_typeof(v->'foods') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'foods')>30
  OR octet_length(private.conversation_command_canonical(v))>131072 THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
 food_count:=jsonb_array_length(v->'foods');
 IF c->'source_units' @> '["vision_items"]'::jsonb THEN visual_count:=jsonb_array_length(c#>'{media,processing_result,items}'); END IF;
 FOR src IN SELECT value FROM jsonb_array_elements(v->'sources') LOOP
  PERFORM private.conversation_meal_keys(src,ARRAY['unit','classification','spans','visual_indexes']);source_unit:=src->>'unit';
  IF source_unit IS NULL OR NOT(c->'source_units' ? source_unit) OR source_unit=ANY(seen) OR src->>'classification' IS NULL
   OR src->>'classification' NOT IN('reported','nominal_list','media_pointer','visual','dream','future','habit','negated','third_party','question','mixed','ambiguous')
   OR jsonb_typeof(src->'spans') IS DISTINCT FROM 'array' OR jsonb_array_length(src->'spans')>4096
   OR jsonb_typeof(src->'visual_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(src->'visual_indexes')>30 THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
  seen:=array_append(seen,source_unit);
  IF source_unit='vision_items' THEN
   IF src->'spans'<>'[]'::jsonb OR src->>'classification' IS DISTINCT FROM 'visual' OR visual_count NOT BETWEEN 1 AND 30
    OR src->'visual_indexes' IS DISTINCT FROM (SELECT jsonb_agg(seq.item) FROM generate_series(0,visual_count-1) AS seq(item)) THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
   seen_indexes:='{}';FOR ref IN SELECT value FROM jsonb_array_elements(src->'visual_indexes') LOOP
    food_index_var:=private.conversation_semantic_uint(ref,visual_count-1)::integer;
    IF food_index_var=ANY(seen_indexes) THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;seen_indexes:=array_append(seen_indexes,food_index_var);END LOOP;
  ELSE
   text_value:=private.conversation_semantic_text(c,source_unit);text_length:=private.conversation_utf16_length(text_value);span_cursor:=0;
   IF text_value IS NULL OR text_length NOT BETWEEN 1 AND (CASE WHEN source_unit='media_caption' THEN 1000 ELSE 2000 END)
    OR src->'visual_indexes'<>'[]'::jsonb OR jsonb_array_length(src->'spans') NOT BETWEEN 1 AND least(text_length,4096) THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
   FOR span IN SELECT value FROM jsonb_array_elements(src->'spans') LOOP
    PERFORM private.conversation_meal_keys(span,ARRAY['start','end','kind','food_index']);start_at:=private.conversation_semantic_uint(span->'start',text_length)::integer;end_at:=private.conversation_semantic_uint(span->'end',text_length)::integer;
    IF start_at<>span_cursor OR end_at<=start_at OR NOT private.conversation_utf16_boundary(text_value,start_at) OR NOT private.conversation_utf16_boundary(text_value,end_at)
     OR span->>'kind' IS NULL OR span->>'kind' NOT IN('food','quantity','unit','report','separator','other') THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
    IF span->'food_index'<>'null'::jsonb THEN PERFORM private.conversation_semantic_uint(span->'food_index',food_count-1); END IF;span_cursor:=end_at;
   END LOOP;
   IF span_cursor<>text_length THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
  END IF;
 END LOOP;
 IF to_jsonb(seen) IS DISTINCT FROM v->'source_units' THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
 n:=0;FOR food IN SELECT value FROM jsonb_array_elements(v->'foods') LOOP
  PERFORM private.conversation_meal_keys(food,ARRAY['index','name','quantity','unit','visual_index']);food_index_var:=private.conversation_semantic_uint(food->'index',29)::integer;
  IF food_index_var<>n THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;n:=n+1;
  IF food->'visual_index'<>'null'::jsonb THEN PERFORM private.conversation_semantic_uint(food->'visual_index',visual_count-1); END IF;
  FOREACH k IN ARRAY ARRAY['name','quantity','unit'] LOOP
   ref:=food->k;IF ref='null'::jsonb THEN CONTINUE; END IF;
   PERFORM private.conversation_meal_keys(ref,ARRAY['unit','start','end']);source_unit:=ref->>'unit';text_value:=private.conversation_semantic_text(c,source_unit);text_length:=private.conversation_utf16_length(text_value);
   IF source_unit IS NULL OR source_unit NOT IN('command_text','media_caption','media_transcript') OR NOT(c->'source_units' ? source_unit) OR text_value IS NULL THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
   start_at:=private.conversation_semantic_uint(ref->'start',text_length)::integer;end_at:=private.conversation_semantic_uint(ref->'end',text_length)::integer;span_kind:=CASE WHEN k='name' THEN 'food' ELSE k END;
   IF end_at<=start_at OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'sources') s CROSS JOIN LATERAL jsonb_array_elements(s->'spans') p
    WHERE s->>'unit'=source_unit AND p->'start'=ref->'start' AND p->'end'=ref->'end' AND p->>'kind'=span_kind AND p->'food_index'=to_jsonb(food_index_var)) THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
  END LOOP;
 END LOOP;
 metadata:=v->'provider_metadata';PERFORM private.conversation_meal_keys(metadata,ARRAY['model','prompt_tokens','completion_tokens','cost_usd','latency_ms']);
 IF jsonb_typeof(metadata->'model') IS DISTINCT FROM 'string' OR private.conversation_utf16_length(metadata->>'model') NOT BETWEEN 1 AND 128 THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
 FOREACH k IN ARRAY ARRAY['prompt_tokens','completion_tokens','latency_ms'] LOOP PERFORM private.conversation_semantic_uint(metadata->k,9007199254740991);END LOOP;
 IF metadata->'cost_usd'<>'null'::jsonb THEN
  IF jsonb_typeof(metadata->'cost_usd') IS DISTINCT FROM 'number' OR (metadata->>'cost_usd')::numeric<0 OR (metadata->>'cost_usd')::numeric>1.7976931348623157e308 THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END IF;
 END IF;
 -- This validates a receipt shape/source binding, never a consumption proof.
END $$;

CREATE FUNCTION public.start_conversation_meal_semantic_attempt(p_user_id uuid,p_command_id uuid,p_interpreter_version text,p_expected_source_hash text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;a private.conversation_meal_semantic_attempts%ROWTYPE;r private.conversation_meal_semantic_results%ROWTYPE;raw jsonb;fresh jsonb;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_command_id);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 IF p_interpreter_version IS DISTINCT FROM 'conversation.meal-interpreter.v1' THEN RAISE EXCEPTION 'invalid_conversation_semantic_version' USING ERRCODE='22023'; END IF;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=p_command_id;
 SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_command_id;
 IF s.command_id IS NULL THEN RETURN '{"action":"source_required"}'::jsonb; END IF;
 IF NOT private.conversation_meal_stored_source_valid(c,raw,s) THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 SELECT * INTO a FROM private.conversation_meal_semantic_attempts WHERE user_id=p_user_id AND command_id=p_command_id AND interpreter_version=p_interpreter_version;
 IF FOUND THEN
  IF a.epoch IS DISTINCT FROM c.epoch OR a.input_hash IS DISTINCT FROM c.input_hash OR a.source_hash IS DISTINCT FROM s.source_hash THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
  SELECT * INTO r FROM private.conversation_meal_semantic_results WHERE user_id=p_user_id AND command_id=p_command_id AND attempt_id=a.attempt_id;
  RETURN private.conversation_semantic_state(a,r,CASE WHEN r.status='completed' THEN 'replay' ELSE 'reconciliation_required' END);
 END IF;
 IF p_expected_source_hash IS DISTINCT FROM s.source_hash THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 fresh:=private.conversation_meal_source_at(p_user_id,p_command_id,NULL);
 IF (fresh#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb; END IF;
 IF fresh IS DISTINCT FROM s.context THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 INSERT INTO private.conversation_meal_semantic_attempts VALUES(p_user_id,p_command_id,p_interpreter_version,c.epoch,c.input_hash,s.source_hash,gen_random_uuid(),clock_timestamp()) RETURNING * INTO a;
 RETURN private.conversation_semantic_state(a,r,'claimed');
END $$;
CREATE FUNCTION public.read_conversation_meal_semantic_attempt(p_user_id uuid,p_command_id uuid,p_interpreter_version text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR p_interpreter_version IS DISTINCT FROM 'conversation.meal-interpreter.v1' OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_semantic_read' USING ERRCODE='22023'; END IF;
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e.epoch OR raw.command_id IS NULL THEN '{"action":"stale_epoch"}'::jsonb
  WHEN NOT private.conversation_meal_stored_source_valid(c,raw.source_input,s) THEN '{"action":"event_conflict"}'::jsonb
  WHEN a.attempt_id IS NULL THEN '{"action":"absent"}'::jsonb
  WHEN a.epoch IS DISTINCT FROM c.epoch OR a.input_hash IS DISTINCT FROM c.input_hash OR a.source_hash IS DISTINCT FROM s.source_hash THEN '{"action":"event_conflict"}'::jsonb
  ELSE private.conversation_semantic_state(a,r,CASE WHEN r.status='completed' THEN 'available' ELSE 'reconciliation_required' END) END INTO result
 FROM private.conversation_meal_command_ids c JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs e ON e.user_id=c.user_id
 LEFT JOIN private.conversation_meal_command_sources raw ON raw.user_id=c.user_id AND raw.command_id=c.command_id
 LEFT JOIN private.conversation_meal_source_captures s ON s.user_id=c.user_id AND s.command_id=c.command_id
 LEFT JOIN private.conversation_meal_semantic_attempts a ON a.user_id=c.user_id AND a.command_id=c.command_id AND a.interpreter_version=p_interpreter_version
 LEFT JOIN private.conversation_meal_semantic_results r ON r.user_id=a.user_id AND r.command_id=a.command_id AND r.attempt_id=a.attempt_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;
CREATE FUNCTION private.finish_conversation_meal_semantic(p_user uuid,p_command uuid,p_version text,p_attempt uuid,p_result jsonb,p_error text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;a private.conversation_meal_semantic_attempts%ROWTYPE;r private.conversation_meal_semantic_results%ROWTYPE;raw jsonb;hash text;
BEGIN
 gate:=private.lock_conversation_meal(p_user,p_command);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 IF p_version IS DISTINCT FROM 'conversation.meal-interpreter.v1' THEN RAISE EXCEPTION 'invalid_conversation_semantic_version' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM private.conversation_meal_semantic_attempts WHERE user_id=p_user AND command_id=p_command AND interpreter_version=p_version;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'::jsonb; END IF;
 IF p_attempt IS DISTINCT FROM a.attempt_id THEN RETURN '{"action":"attempt_conflict"}'::jsonb; END IF;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_command;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_command;
 SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_command;
 IF NOT private.conversation_meal_stored_source_valid(c,raw,s) OR a.epoch IS DISTINCT FROM c.epoch OR a.input_hash IS DISTINCT FROM c.input_hash OR a.source_hash IS DISTINCT FROM s.source_hash THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 SELECT * INTO r FROM private.conversation_meal_semantic_results WHERE user_id=p_user AND command_id=p_command AND attempt_id=p_attempt;
 IF FOUND THEN RETURN private.conversation_semantic_state(a,r,'replay'); END IF;
 IF p_error IS NULL THEN
  BEGIN PERFORM private.assert_conversation_semantic_result(p_result,a,s.context);
  EXCEPTION WHEN data_exception THEN RAISE EXCEPTION 'invalid_conversation_semantic_result' USING ERRCODE='22023'; END;
  hash:=encode(sha256(convert_to(private.conversation_command_canonical(p_result),'UTF8')),'hex');
  INSERT INTO private.conversation_meal_semantic_results VALUES(p_user,p_command,p_attempt,'completed',p_result,hash,NULL,clock_timestamp()) RETURNING * INTO r;
 ELSE
  IF p_error NOT IN('provider_outcome_unknown','provider_terminal_error') OR p_result IS NOT NULL THEN RAISE EXCEPTION 'invalid_conversation_semantic_error' USING ERRCODE='22023'; END IF;
  INSERT INTO private.conversation_meal_semantic_results VALUES(p_user,p_command,p_attempt,CASE WHEN p_error='provider_outcome_unknown' THEN 'unknown' ELSE 'error' END,NULL,NULL,p_error,clock_timestamp()) RETURNING * INTO r;
 END IF;
 RETURN private.conversation_semantic_state(a,r,'committed');
END $$;
CREATE FUNCTION public.commit_conversation_meal_semantic_result(p_user_id uuid,p_command_id uuid,p_interpreter_version text,p_attempt_id uuid,p_result jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN RETURN private.finish_conversation_meal_semantic(p_user_id,p_command_id,p_interpreter_version,p_attempt_id,p_result,NULL);END $$;
CREATE FUNCTION public.mark_conversation_meal_semantic_unknown(p_user_id uuid,p_command_id uuid,p_interpreter_version text,p_attempt_id uuid,p_error_code text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN
 RETURN private.finish_conversation_meal_semantic(p_user_id,p_command_id,p_interpreter_version,p_attempt_id,NULL,coalesce(p_error_code,''));
END $$;

CREATE FUNCTION public.read_conversation_meal_prepared(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_meal_prepared_read' USING ERRCODE='22023'; END IF;
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM a.epoch OR raw.command_id IS NULL THEN '{"action":"stale_epoch"}'::jsonb
  WHEN NOT private.conversation_meal_stored_source_valid(c,raw.source_input,s) THEN '{"action":"event_conflict"}'::jsonb
  WHEN r.command_id IS NOT NULL AND (s.command_id IS NULL OR r.resolved->>'input_hash' IS DISTINCT FROM c.input_hash OR r.resolved->>'source_hash' IS DISTINCT FROM s.source_hash OR r.resolved_hash IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(r.resolved),'UTF8')),'hex')) THEN '{"action":"event_conflict"}'::jsonb
  WHEN e.command_id IS NOT NULL AND (r.command_id IS NULL OR s.command_id IS NULL OR e.receipt->>'owner_id' IS DISTINCT FROM c.user_id::text OR e.receipt->>'command_id' IS DISTINCT FROM c.command_id::text OR e.receipt->>'input_hash' IS DISTINCT FROM c.input_hash OR e.receipt->>'effect_version' IS DISTINCT FROM 'cmeal1:'||encode(sha256(convert_to(private.conversation_command_canonical(e.original_facts),'UTF8')),'hex')) THEN '{"action":"event_conflict"}'::jsonb
  ELSE jsonb_build_object('action','available','command',private.conversation_meal_command_binding(c),
   'source',CASE WHEN s.command_id IS NULL THEN NULL ELSE jsonb_build_object('source_hash',s.source_hash,'captured_at',s.captured_at,'context',s.context) END,
   'resolved',CASE WHEN r.command_id IS NULL THEN NULL ELSE jsonb_build_object('resolved_hash',r.resolved_hash,'prepared_at',r.prepared_at,'resolved',r.resolved) END,
   'receipt',e.receipt) END INTO result
 FROM private.conversation_meal_command_ids c JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs a ON a.user_id=c.user_id
 LEFT JOIN private.conversation_meal_command_sources raw ON raw.user_id=c.user_id AND raw.command_id=c.command_id
 LEFT JOIN private.conversation_meal_source_captures s ON s.user_id=c.user_id AND s.command_id=c.command_id
 LEFT JOIN private.conversation_meal_resolved r ON r.user_id=c.user_id AND r.command_id=c.command_id
 LEFT JOIN private.conversation_meal_effects e ON e.user_id=c.user_id AND e.command_id=c.command_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;

REVOKE ALL ON FUNCTION private.conversation_meal_stored_source_valid(private.conversation_meal_command_ids,jsonb,private.conversation_meal_source_captures),private.conversation_semantic_state(private.conversation_meal_semantic_attempts,private.conversation_meal_semantic_results,text),
 private.conversation_utf16_length(text),private.conversation_utf16_boundary(text,integer),private.conversation_semantic_uint(jsonb,numeric),private.conversation_semantic_text(jsonb,text),private.assert_conversation_semantic_result(jsonb,private.conversation_meal_semantic_attempts,jsonb),private.finish_conversation_meal_semantic(uuid,uuid,text,uuid,jsonb,text),
 public.start_conversation_meal_semantic_attempt(uuid,uuid,text,text),public.read_conversation_meal_semantic_attempt(uuid,uuid,text),public.commit_conversation_meal_semantic_result(uuid,uuid,text,uuid,jsonb),public.mark_conversation_meal_semantic_unknown(uuid,uuid,text,uuid,text),public.read_conversation_meal_prepared(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.start_conversation_meal_semantic_attempt(uuid,uuid,text,text),public.read_conversation_meal_semantic_attempt(uuid,uuid,text),public.commit_conversation_meal_semantic_result(uuid,uuid,text,uuid,jsonb),public.mark_conversation_meal_semantic_unknown(uuid,uuid,text,uuid,text),public.read_conversation_meal_prepared(uuid,uuid) TO service_role;
COMMIT;

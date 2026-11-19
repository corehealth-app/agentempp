-- Item-bound food-name clarification. Preserve the current function bodies,
-- including workout identity/rate guards. Only exact reviewed source hashes apply.
BEGIN;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('public.admit_conversation_meal_reply(uuid,uuid,uuid,text,text,uuid,jsonb)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('12c9d37e79f8c122abf0ec45c719b6b9d0a7c339d58ec60977b6a3d696429734','1d6fd7d7d9dac8fdf3e8fc2e3f410b84297b9b9a19d4c1cd85feb583aad3b5cb') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: public.admit_conversation_meal_reply(uuid,uuid,uuid,text,text,uuid,jsonb)';END IF;
 IF cardinality(string_to_array(body,$before$OR (question->>'kind'='quantity' AND$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$OR (question->>'kind'='quantity' AND$before$,$after$OR (question->>'kind'='food_name' AND p_input#>'{answer,food_index}' IS DISTINCT FROM question->'food_index')
  OR (question->>'kind'='quantity' AND$after$);
 EXECUTE body;
END $patch$;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('private.conversation_continuation_food_name(jsonb,jsonb)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('7687081d8e6a152c5239f6876e3cb5f68a3ff42a8ee5dad738866da99ad031a4','7687081d8e6a152c5239f6876e3cb5f68a3ff42a8ee5dad738866da99ad031a4') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: private.conversation_continuation_food_name(jsonb,jsonb)';END IF;
 IF cardinality(string_to_array(body,$before$SELECT private.conversation_continuation_slice($before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$SELECT private.conversation_continuation_slice($before$,$after$SELECT CASE WHEN food->'visual_index' IS NOT NULL AND food->'visual_index'<>'null'::jsonb AND source#>>'{media,kind}' IN('meal_photo','conversation_photo') THEN coalesce(source#>>ARRAY['media','processing_result','analysis','items',food->>'visual_index','name'],source#>>ARRAY['media','processing_result','items',food->>'visual_index','name']) ELSE private.conversation_continuation_slice($after$);
 IF cardinality(string_to_array(body,$before$(food#>>'{name,end}')::numeric::integer);$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$(food#>>'{name,end}')::numeric::integer);$before$,$after$(food#>>'{name,end}')::numeric::integer) END;$after$);
 EXECUTE body;
END $patch$;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('private.assert_conversation_meal_reply(jsonb)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('21c32b69b03e358028c9f11d5f6a3c587c4a3f00791e6136803412919b9e34f8','21c32b69b03e358028c9f11d5f6a3c587c4a3f00791e6136803412919b9e34f8') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: private.assert_conversation_meal_reply(jsonb)';END IF;
 IF cardinality(string_to_array(body,$before$ELSIF a->>'kind'='meal_type' THEN$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$ELSIF a->>'kind'='meal_type' THEN$before$,$after$ELSIF a->>'kind'='food_name' THEN
  PERFORM private.conversation_meal_keys(a,ARRAY['kind','food_index','name']);
  PERFORM private.conversation_semantic_uint(a->'food_index',29);
  IF NOT private.conversation_command_text_valid(a->'name',160) THEN RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
 ELSIF a->>'kind'='meal_type' THEN$after$);
 EXECUTE body;
END $patch$;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('private.conversation_continuation_question(jsonb,integer,jsonb,text,integer)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('86d245fe3f295576e1d2fdad7bcba927a31e5a34eee510e02646f0ed4b9a536a','86d245fe3f295576e1d2fdad7bcba927a31e5a34eee510e02646f0ed4b9a536a') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: private.conversation_continuation_question(jsonb,integer,jsonb,text,integer)';END IF;
 IF cardinality(string_to_array(body,$before$kind NOT IN('quantity','meal_type')$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$kind NOT IN('quantity','meal_type')$before$,$after$kind NOT IN('quantity','meal_type','food_name')$after$);
 IF cardinality(string_to_array(body,$before$IF kind='quantity' THEN$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$IF kind='quantity' THEN$before$,$after$IF kind='food_name' THEN
  SELECT x INTO food FROM jsonb_array_elements(parent#>'{semantic,result,foods}') x WHERE (x->>'index')::numeric=food_index;
  IF food IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements(answers) x
    WHERE x#>>'{answer,kind}'='quantity' AND (x#>>'{answer,food_index}')::numeric=food_index) THEN RETURN NULL;END IF;
  SELECT x#>>'{answer,name}' INTO name FROM jsonb_array_elements(answers) WITH ORDINALITY AS a(x,n)
   WHERE x#>>'{answer,kind}'='food_name' AND (x#>>'{answer,food_index}')::numeric=food_index ORDER BY n DESC LIMIT 1;
  name:=coalesce(name,private.conversation_continuation_food_name(parent#>'{source,context}',food));
  IF NOT private.conversation_command_text_valid(to_jsonb(name),160) THEN RETURN NULL;END IF;
 ELSIF kind='quantity' THEN$after$);
 IF cardinality(string_to_array(body,$before$name:=private.conversation_continuation_food_name(parent#>'{source,context}',food);$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$name:=private.conversation_continuation_food_name(parent#>'{source,context}',food);$before$,$after$SELECT x#>>'{answer,name}' INTO name FROM jsonb_array_elements(answers) WITH ORDINALITY AS a(x,n)
   WHERE x#>>'{answer,kind}'='food_name' AND (x#>>'{answer,food_index}')::numeric=food_index ORDER BY n DESC LIMIT 1;
  name:=coalesce(name,private.conversation_continuation_food_name(parent#>'{source,context}',food));$after$);
 EXECUTE body;
END $patch$;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('private.conversation_continuation_parent(uuid,uuid)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('d68c4327d64f93aceb7589fe0c01c150864208d3482639f2fe2fcafb1e5974fa','d68c4327d64f93aceb7589fe0c01c150864208d3482639f2fe2fcafb1e5974fa') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: private.conversation_continuation_parent(uuid,uuid)';END IF;
 IF cardinality(string_to_array(body,$before$NOT IN('missing_quantity','meal_type_required')$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$NOT IN('missing_quantity','meal_type_required')$before$,$after$NOT IN('missing_quantity','meal_type_required','unqualified_whole_name')$after$);
 EXECUTE body;
END $patch$;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('private.conversation_continuation_head(uuid,uuid,jsonb)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('6e2addc3f1f3f06e5fbc30ef9513c3166488319ef81e02282dfb7ea87af45fd3','6e2addc3f1f3f06e5fbc30ef9513c3166488319ef81e02282dfb7ea87af45fd3') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: private.conversation_continuation_head(uuid,uuid,jsonb)';END IF;
 IF cardinality(string_to_array(body,$before$ELSIF parent#>>'{decision,reason}'='meal_type_required' THEN$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$ELSIF parent#>>'{decision,reason}'='meal_type_required' THEN$before$,$after$ELSIF parent#>>'{decision,reason}'='unqualified_whole_name' AND jsonb_array_length(parent#>'{decision,food_indexes}')=1 THEN
  kind:='food_name';index:=(parent#>>'{decision,food_indexes,0}')::numeric::integer;
 ELSIF parent#>>'{decision,reason}'='meal_type_required' THEN$after$);
 EXECUTE body;
END $patch$;

DO $patch$
DECLARE body text;old_hash text;
BEGIN
 body:=pg_get_functiondef('private.assert_conversation_continuation_preparation(jsonb,jsonb,jsonb)'::regprocedure);
 old_hash:=encode(sha256(convert_to(body,'UTF8')),'hex');
 IF old_hash NOT IN('dde88d0df6e37d7e7703e24654f421f426e47c0ee8c6271595faa5a10ae8e898','dde88d0df6e37d7e7703e24654f421f426e47c0ee8c6271595faa5a10ae8e898') THEN RAISE EXCEPTION 'food_name_clarification_source_changed: private.assert_conversation_continuation_preparation(jsonb,jsonb,jsonb)';END IF;
 IF cardinality(string_to_array(body,$before$v#>>'{materialization,reason}' IS DISTINCT FROM 'missing_quantity'$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$v#>>'{materialization,reason}' IS DISTINCT FROM 'missing_quantity'$before$,$after$v#>>'{materialization,reason}' NOT IN('missing_quantity','unqualified_whole_name')$after$);
 IF cardinality(string_to_array(body,$before$v#>>'{next_need,kind}' IS DISTINCT FROM 'quantity'$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_patch_count';END IF;
 body:=replace(body,$before$v#>>'{next_need,kind}' IS DISTINCT FROM 'quantity'$before$,$after$v#>>'{next_need,kind}' IS DISTINCT FROM (CASE v#>>'{materialization,reason}' WHEN 'missing_quantity' THEN 'quantity' ELSE 'food_name' END)$after$);
 EXECUTE body;
END $patch$;

-- Version the closed reader; preserve legacy pagination before projecting.
DO $compat$ DECLARE body text; BEGIN
 IF to_regprocedure('private.conversation_thread_parent_v3(uuid,uuid,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'food_name_clarification_new_reader_exists';END IF;
 body:=pg_get_functiondef('private.conversation_thread_parent_v2(uuid,uuid,uuid)'::regprocedure);
 IF encode(sha256(convert_to(body,'UTF8')),'hex')<>'ecb2bc8705ec5d4e740bf45af2f503b203365e551fa79461e381708e136e399e' THEN RAISE EXCEPTION 'food_name_clarification_reader_changed';END IF;
 EXECUTE $clone$CREATE OR REPLACE FUNCTION private.conversation_thread_parent_v3(p_user uuid, p_parent uuid, p_epoch uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO,YMD'
AS $function$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;raw jsonb;
 d private.conversation_meal_decisions%ROWTYPE;a private.conversation_meal_semantic_attempts%ROWTYPE;r private.conversation_meal_semantic_results%ROWTYPE;
 fx private.conversation_meal_effects%ROWTYPE;decision jsonb;parent jsonb;head jsonb;continuation jsonb;fulfilled uuid;v jsonb;
 linked private.conversation_meal_command_ids%ROWTYPE;last_reply jsonb;accepted uuid;
BEGIN
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_parent;
 SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_parent;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_parent;
 IF c.command_id IS NULL OR c.command_protocol IS DISTINCT FROM 'conversation.command.v1' OR c.kind IS DISTINCT FROM 'meal.report'
  OR c.epoch IS DISTINCT FROM p_epoch OR c.invalidated_at IS NOT NULL OR NOT isfinite(c.admitted_at)
  OR NOT private.conversation_meal_stored_source_valid(c,raw,s) THEN RETURN NULL;END IF;
 PERFORM private.assert_conversation_meal_input(raw);
 SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_parent;
 IF fx.command_id IS NOT NULL AND private.conversation_thread_effect_v2(fx,c,NULL) IS NULL THEN RETURN NULL;END IF;
 SELECT * INTO d FROM private.conversation_meal_decisions WHERE user_id=p_user AND command_id=p_parent;
 IF d.command_id IS NOT NULL THEN
  SELECT * INTO a FROM private.conversation_meal_semantic_attempts WHERE user_id=p_user AND command_id=p_parent AND attempt_id=d.attempt_id;
  SELECT * INTO r FROM private.conversation_meal_semantic_results WHERE user_id=p_user AND command_id=p_parent AND attempt_id=d.attempt_id;
  IF fx.command_id IS NOT NULL OR NOT private.conversation_meal_decision_valid(d,c,s,a,r) OR d.sealed_at<c.admitted_at THEN RETURN NULL;END IF;
  PERFORM private.assert_conversation_meal_decision(d.decision);
  decision:=jsonb_build_object('schema','conversation.meal-decision-public.v1','status','not_recorded','owner_id',p_user,'command_id',p_parent,
   'input_hash',c.input_hash,'epoch',c.epoch,'reason',d.decision->'reason','food_indexes',d.decision->'food_indexes',
   'decision_hash',d.decision_hash,'sealed_at',private.conversation_thread_clock_v2(d.sealed_at));
  -- Full immutable evidence is verified internally once per distinct parent;
  -- none of it is returned in the compact page or repeated for child events.
  parent:=private.conversation_continuation_parent(p_user,p_parent);
  IF parent IS NOT NULL THEN
   head:=private.conversation_continuation_head(p_user,p_parent,parent);
   IF head IS NOT NULL THEN
    IF jsonb_array_length(head->'answers')<>(head->>'revision')::integer OR (head->>'revision')::integer NOT BETWEEN 0 AND 31 THEN RETURN NULL;END IF;
    IF head->'question'<>'null'::jsonb AND head->'question' IS DISTINCT FROM private.conversation_continuation_question(parent,(head->>'revision')::integer,
     head->'answers',head#>>'{question,kind}',(head#>>'{question,food_index}')::numeric::integer) THEN RETURN NULL;END IF;
    SELECT f.reply_id INTO fulfilled FROM private.conversation_meal_fulfillments f WHERE f.user_id=p_user AND f.parent_command_id=p_parent;
    IF head->>'fulfilled_by' IS DISTINCT FROM fulfilled::text OR (fulfilled IS NOT NULL AND head->'question'<>'null'::jsonb)
     OR (fulfilled IS NULL AND head->'question'='null'::jsonb) THEN RETURN NULL;END IF;
    IF (head->>'revision')::integer>0 THEN
     accepted:=(head#>>ARRAY['answers',((head->>'revision')::integer-1)::text,'reply_id'])::uuid;
     SELECT * INTO linked FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=accepted;
     IF linked.epoch IS DISTINCT FROM p_epoch OR linked.invalidated_at IS NOT NULL THEN RETURN NULL;END IF;
     last_reply:=private.conversation_continuation_reply(p_user,p_parent,accepted,linked.input_hash,head);
     IF last_reply IS NULL OR last_reply#>'{source,context,answer_chain}' IS DISTINCT FROM head->'answers'
      OR (fulfilled IS NULL AND (last_reply#>>'{preparation,preparation,status}' IS DISTINCT FROM 'needs_reply'
       OR last_reply#>'{preparation,next_question}' IS DISTINCT FROM head->'question'))
      OR (fulfilled IS NOT NULL AND (accepted IS DISTINCT FROM fulfilled OR last_reply#>>'{preparation,preparation,status}' IS DISTINCT FROM 'ready'
       OR last_reply->'receipt'='null'::jsonb)) THEN RETURN NULL;END IF;
    END IF;
    continuation:=jsonb_build_object('revision',head->'revision','question',head->'question','fulfilled_by',head->'fulfilled_by');
   END IF;
  END IF;
 END IF;
 IF continuation IS NULL AND (EXISTS(SELECT 1 FROM private.conversation_meal_continuation_heads WHERE user_id=p_user AND parent_command_id=p_parent)
  OR EXISTS(SELECT 1 FROM private.conversation_meal_reply_ids l JOIN private.conversation_meal_command_ids child ON child.user_id=l.user_id AND child.command_id=l.reply_id
   WHERE l.user_id=p_user AND l.parent_command_id=p_parent AND child.invalidated_at IS NULL AND child.epoch=p_epoch)) THEN RETURN NULL;END IF;
 v:=jsonb_build_object('schema','conversation.meal-thread.v1','thread_id',p_parent,'parent_binding',private.conversation_meal_command_binding(c),
  'original_command',raw,'terminal_receipt',decision,'continuation',continuation);
 IF fulfilled IS NOT NULL THEN
  SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=fulfilled;
  IF private.conversation_thread_effect_v2(fx,linked,v) IS NULL THEN RETURN NULL;END IF;
 END IF;
 -- This capsule is private and cached once per selected parent. Only its
 -- descriptor field is ever added to the public-facing threads array.
 RETURN jsonb_build_object('descriptor',v,'parent_proof',parent);
EXCEPTION WHEN data_exception THEN RETURN NULL;
END $function$
$clone$;
 IF cardinality(string_to_array(body,$before$IF head IS NOT NULL THEN$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_reader_patch_count';END IF;
 EXECUTE replace(body,$before$IF head IS NOT NULL THEN$before$,$after$IF head IS NOT NULL AND head#>>'{question,kind}' IS DISTINCT FROM 'food_name' THEN$after$);
END $compat$;
REVOKE ALL ON FUNCTION private.conversation_thread_parent_v3(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $compat$ DECLARE body text; BEGIN
 IF to_regprocedure('public.read_conversation_meal_journal_page_v3(uuid,uuid,integer,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'food_name_clarification_new_reader_exists';END IF;
 body:=pg_get_functiondef('public.read_conversation_meal_journal_page_v2(uuid,uuid,integer,jsonb)'::regprocedure);
 IF encode(sha256(convert_to(body,'UTF8')),'hex')<>'5e3a8edb2f01c81dfc1579d761e8c60eaccb174916536bbb6f08c3239ca0d200' THEN RAISE EXCEPTION 'food_name_clarification_reader_changed';END IF;
 EXECUTE $clone$CREATE OR REPLACE FUNCTION public.read_conversation_meal_journal_page_v3(p_user_id uuid, p_expected_epoch uuid, p_limit integer DEFAULT 10, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO,YMD'
AS $function$
DECLARE epoch uuid;cursor_at timestamptz;cursor_id text;keys jsonb;row jsonb;entry jsonb;parent jsonb;child jsonb;
 parents jsonb:='{}';children jsonb:='{}';threads jsonb:='[]';items jsonb:='[]';more boolean;last_cursor jsonb;observed timestamptz;
 parent_id uuid;parent_key text;reply_key text;id_pattern text:='[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'invalid_conversation_thread_page' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"absent"}'::jsonb;END IF;
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE user_id=p_user_id;
 IF epoch IS NULL OR p_expected_epoch IS DISTINCT FROM epoch THEN RETURN '{"action":"stale_epoch"}'::jsonb;END IF;
 IF p_cursor IS NOT NULL THEN
  BEGIN
   PERFORM private.conversation_meal_keys(p_cursor,ARRAY['at','id']);
   IF jsonb_typeof(p_cursor->'at') IS DISTINCT FROM 'string' OR jsonb_typeof(p_cursor->'id') IS DISTINCT FROM 'string'
    OR NOT(p_cursor->>'at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$')
    OR NOT(p_cursor->>'id' ~ ('^(command/'||id_pattern||'|(?:reply|reply-result|fulfillment|edit)/'||id_pattern||'/'||id_pattern||')$')) THEN RAISE EXCEPTION 'invalid_cursor';END IF;
   cursor_at:=(p_cursor->>'at')::timestamptz;cursor_id:=p_cursor->>'id';
   IF NOT isfinite(cursor_at) OR NOT EXISTS(SELECT 1 FROM private.conversation_thread_events_v2(p_user_id,epoch) e WHERE e.at=cursor_at AND e.event_id=cursor_id) THEN RAISE EXCEPTION 'invalid_cursor';END IF;
  EXCEPTION WHEN data_exception OR raise_exception THEN RETURN '{"action":"cursor_conflict"}'::jsonb;END;
 END IF;
 -- Select limit+1 keys as one bounded relation. Only the returned prefix is
 -- projected; no whole source/model is emitted per entry or fetched via RPCs.
 SELECT coalesce(jsonb_agg(jsonb_build_object('at',private.conversation_thread_clock_v2(e.at),'event_id',e.event_id,'thread_id',e.thread_id,
  'effect_id',e.effect_id,'reply_id',e.reply_id,'operation_id',e.operation_id,'kind',e.kind) ORDER BY e.at DESC,e.event_id COLLATE "C" DESC),'[]'::jsonb)
 INTO keys FROM (SELECT x.* FROM private.conversation_thread_events_v2(p_user_id,epoch) x
  WHERE cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C"))
  ORDER BY x.at DESC,x.event_id COLLATE "C" DESC LIMIT p_limit+1) e;
 more:=jsonb_array_length(keys)>p_limit;
 SELECT coalesce(jsonb_agg(x ORDER BY ord),'[]'::jsonb) INTO keys FROM jsonb_array_elements(keys) WITH ORDINALITY a(x,ord) WHERE ord<=p_limit;
 FOR parent_key IN SELECT DISTINCT (x->>'thread_id') COLLATE "C" FROM jsonb_array_elements(keys) x ORDER BY 1 LOOP
  parent_id:=parent_key::uuid;
  IF parent_id IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  parent:=private.conversation_thread_parent_v3(p_user_id,parent_id,epoch);IF parent IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  parents:=parents||jsonb_build_object(parent_id::text,parent);threads:=threads||jsonb_build_array(parent->'descriptor');
 END LOOP;
 -- Distinct child verification is cached as a small DTO, not the full capsule.
 FOR reply_key,parent_key IN SELECT DISTINCT x->>'reply_id',x->>'thread_id' FROM jsonb_array_elements(keys) x WHERE x->'reply_id'<>'null'::jsonb LOOP
  IF children ? reply_key THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  child:=private.conversation_thread_child_v2(p_user_id,reply_key::uuid,parents->parent_key);
  IF child IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;children:=children||jsonb_build_object(reply_key,child);
 END LOOP;
 FOR row IN SELECT value FROM jsonb_array_elements(keys) LOOP
  IF row->'event_id'='null'::jsonb OR row->'at'='null'::jsonb THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  entry:=private.conversation_thread_entry_v2(p_user_id,row,parents#>ARRAY[row->>'thread_id','descriptor'],children->(row->>'reply_id'));
  IF entry IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  items:=items||jsonb_build_array(entry);last_cursor:=jsonb_build_object('at',entry->'at','id',entry->'event_id');
 END LOOP;
 observed:=clock_timestamp();
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(threads) x WHERE (x#>>'{parent_binding,admitted_at}')::timestamptz>observed
  OR (x#>>'{terminal_receipt,sealed_at}')::timestamptz>observed)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(items) x WHERE (x->>'at')::timestamptz>observed OR (x#>>'{receipt,consumed_at}')::timestamptz>observed) THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 RETURN jsonb_build_object('action','available','schema','conversation.journal-page-private.v2','owner_id',p_user_id,'epoch',epoch,
  'observed_at',private.conversation_thread_clock_v2(observed),'threads',threads,'items',items,'has_more',more,'next_cursor',CASE WHEN more THEN last_cursor ELSE NULL END);
END $function$
$clone$;
 IF cardinality(string_to_array(body,$before$WHERE cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C"))$before$))<>2 THEN RAISE EXCEPTION 'food_name_clarification_reader_patch_count';END IF;
 EXECUTE replace(body,$before$WHERE cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C"))$before$,$after$WHERE NOT EXISTS(SELECT 1 FROM private.conversation_meal_continuation_heads h
   WHERE h.user_id=p_user_id AND h.parent_command_id=x.thread_id
    AND (h.question->>'kind'='food_name' OR EXISTS(SELECT 1 FROM jsonb_array_elements(h.answers) l WHERE l#>>'{answer,kind}'='food_name')))
   AND (cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C")))$after$);
END $compat$;
REVOKE ALL ON FUNCTION public.read_conversation_meal_journal_page_v3(uuid,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_journal_page_v3(uuid,uuid,integer,jsonb) TO service_role;
COMMIT;

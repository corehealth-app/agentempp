-- Compact, private, read-only v2 thread page. The v1 reader is untouched.
-- Source-only until real-PG RED/fresh migration/roles/snapshot qualification.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('public.read_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text)') IS NULL
  OR to_regprocedure('private.conversation_meal_feedback_receipt(private.conversation_meal_effects)') IS NULL THEN
  RAISE EXCEPTION 'thread_page_v2_requires_current_substrate' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p WHERE p.oid=to_regprocedure('private.conversation_continuation_parent(uuid,uuid)')) IS DISTINCT FROM 'cc6c0bfaa3ee580854a375c966cbde679b69f569bd27142c5eb05b0923dbc6a0' THEN
  RAISE EXCEPTION 'thread_page_v2_requires_qualified_helpers' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p WHERE p.oid=to_regprocedure('private.conversation_continuation_head(uuid,uuid,jsonb)')) IS DISTINCT FROM 'eead50b6590386be57638aaeca5c3b75584e3520ebf48eab72f3f13a73a0b425' THEN
  RAISE EXCEPTION 'thread_page_v2_requires_qualified_helpers' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p WHERE p.oid=to_regprocedure('private.conversation_continuation_reply(uuid,uuid,uuid,text,jsonb)')) IS DISTINCT FROM 'fb1389a754c7cfd738e4198afbb056b24ecce49e30f00b0161de419f507fb230' THEN
  RAISE EXCEPTION 'thread_page_v2_requires_qualified_helpers' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p WHERE p.oid=to_regprocedure('private.conversation_meal_feedback_receipt(private.conversation_meal_effects)')) IS DISTINCT FROM '01d1eef2a3faaf334310782162a88f34f98f6c93752283fae505e5de9eca37c0' THEN
  RAISE EXCEPTION 'thread_page_v2_requires_qualified_helpers' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p WHERE p.oid=to_regprocedure('private.conversation_continuation_question(jsonb,integer,jsonb,text,integer)')) IS DISTINCT FROM '78f06a84286ca39f3955a5c78b594083ba526b741ab322f6bcf59c3de4b6a90b' THEN
  RAISE EXCEPTION 'thread_page_v2_requires_qualified_helpers' USING ERRCODE='55000';END IF;
END $$;
CREATE INDEX conversation_thread_preparation_page_v2 ON private.conversation_meal_resolved(user_id,prepared_at DESC,command_id DESC);
CREATE INDEX conversation_thread_effect_page_v2 ON private.conversation_meal_effects(user_id,committed_at DESC,command_id DESC);

CREATE FUNCTION private.conversation_thread_clock_v2(value timestamptz) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT to_char(value AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
$$;

-- Only immutable event identities/clocks participate in keyset ordering.
-- Dependency integrity is checked by the selected-row projections, never by
-- silently dropping an event whose source/preparation cannot be decoded.
CREATE FUNCTION private.conversation_thread_events_v2(p_user uuid,p_epoch uuid)
RETURNS TABLE(at timestamptz,event_id text,thread_id uuid,effect_id uuid,reply_id uuid,operation_id uuid,kind text)
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT c.admitted_at,'command/'||c.command_id::text,c.command_id,c.command_id,NULL::uuid,NULL::uuid,'report'::text
 FROM private.conversation_meal_command_ids c
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL AND c.command_protocol='conversation.command.v1' AND c.kind='meal.report'
 UNION ALL
 SELECT c.admitted_at,'reply/'||l.parent_command_id::text||'/'||c.command_id::text,l.parent_command_id,c.command_id,c.command_id,NULL::uuid,'reply'
 FROM private.conversation_meal_command_ids c LEFT JOIN private.conversation_meal_reply_ids l ON l.user_id=c.user_id AND l.reply_id=c.command_id
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL AND c.command_protocol='conversation.clarification.v1' AND c.kind='meal.clarify'
 UNION ALL
 SELECT r.prepared_at,'reply-result/'||l.parent_command_id::text||'/'||c.command_id::text,l.parent_command_id,c.command_id,c.command_id,NULL::uuid,'reply_result'
 FROM private.conversation_meal_resolved r JOIN private.conversation_meal_command_ids c ON c.user_id=r.user_id AND c.command_id=r.command_id
 LEFT JOIN private.conversation_meal_reply_ids l ON l.user_id=c.user_id AND l.reply_id=c.command_id
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL AND c.command_protocol='conversation.clarification.v1' AND c.kind='meal.clarify'
 UNION ALL
 SELECT fx.committed_at,'fulfillment/'||l.parent_command_id::text||'/'||c.command_id::text,l.parent_command_id,c.command_id,c.command_id,NULL::uuid,'fulfillment'
 FROM private.conversation_meal_effects fx JOIN private.conversation_meal_command_ids c ON c.user_id=fx.user_id AND c.command_id=fx.command_id
 LEFT JOIN private.conversation_meal_reply_ids l ON l.user_id=c.user_id AND l.reply_id=c.command_id
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL AND c.command_protocol='conversation.clarification.v1' AND c.kind='meal.clarify'
 UNION ALL
 SELECT op.applied_at,'edit/'||c.command_id::text||'/'||op.operation_id::text,
 CASE WHEN c.command_protocol='conversation.command.v1' THEN c.command_id ELSE l.parent_command_id END,c.command_id,
 CASE WHEN c.command_protocol='conversation.clarification.v1' THEN c.command_id ELSE NULL::uuid END,op.operation_id,'edit'
 FROM private.conversation_meal_edit_operations op JOIN private.conversation_meal_command_ids c ON c.user_id=op.user_id AND c.command_id=op.command_id
 LEFT JOIN private.conversation_meal_reply_ids l ON l.user_id=c.user_id AND l.reply_id=c.command_id
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL
 AND ((c.command_protocol='conversation.command.v1' AND c.kind='meal.report') OR (c.command_protocol='conversation.clarification.v1' AND c.kind='meal.clarify'));
$$;

-- Mandatory factual receipt only. Historical logs come from the frozen FX,
-- never current rows that a C11 correction may have replaced or removed.
CREATE FUNCTION private.conversation_thread_effect_v2(e private.conversation_meal_effects,c private.conversation_meal_command_ids,parent jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE v jsonb:=e.receipt;keys text[];ids jsonb;item jsonb;stamp timestamptz;registration uuid;seen text[]:='{}';
BEGIN
 IF e.command_id IS NULL OR e.user_id IS DISTINCT FROM c.user_id OR e.command_id IS DISTINCT FROM c.command_id THEN RETURN NULL;END IF;
 keys:=ARRAY['schema','owner_id','command_id','input_hash','registration_id','provider_key','meal_type','local_date','timezone','consumed_at','log_ids','effect_version'];
 IF c.command_protocol='conversation.command.v1' AND c.kind='meal.report' THEN
  IF v->>'schema' IS DISTINCT FROM 'conversation.meal-effect.v1' OR v->>'provider_key' IS DISTINCT FROM 'conversation.meal/'||c.user_id::text||'/'||c.command_id::text THEN RETURN NULL;END IF;
 ELSIF c.command_protocol='conversation.clarification.v1' AND c.kind='meal.clarify' THEN
  keys:=keys||ARRAY['parent_command_id','parent_input_hash','parent_decision_hash','epoch'];
  IF parent IS NULL OR v->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-effect.v1'
   OR v->'parent_command_id' IS DISTINCT FROM parent#>'{parent_binding,command_id}' OR v->'parent_input_hash' IS DISTINCT FROM parent#>'{parent_binding,input_hash}'
   OR v->'parent_decision_hash' IS DISTINCT FROM parent#>'{terminal_receipt,decision_hash}' OR v->>'epoch' IS DISTINCT FROM c.epoch::text
   OR v->>'provider_key' IS DISTINCT FROM 'conversation.clarification/'||c.user_id::text||'/'||(parent->>'thread_id') THEN RETURN NULL;END IF;
 ELSE RETURN NULL;END IF;
 PERFORM private.conversation_meal_keys(v,keys);
 IF v->>'owner_id' IS DISTINCT FROM c.user_id::text OR v->>'command_id' IS DISTINCT FROM c.command_id::text OR v->>'input_hash' IS DISTINCT FROM c.input_hash
  OR v->>'effect_version' IS DISTINCT FROM 'cmeal1:'||encode(sha256(convert_to(private.conversation_command_canonical(e.original_facts),'UTF8')),'hex') OR v->>'meal_type' IS NULL OR v->>'meal_type' NOT IN('cafe','almoco','lanche','jantar','ceia','outro')
  OR jsonb_typeof(v->'timezone') IS DISTINCT FROM 'string' OR length(v->>'timezone')=0 OR jsonb_typeof(v->'local_date') IS DISTINCT FROM 'string'
  OR jsonb_typeof(v->'log_ids') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'log_ids') NOT BETWEEN 1 AND 30
  OR NOT EXISTS(SELECT 1 FROM private.conversation_meal_resolved r WHERE r.user_id=c.user_id AND r.command_id=c.command_id) THEN RETURN NULL;END IF;
 registration:=(v->>'registration_id')::uuid;stamp:=(v->>'consumed_at')::timestamptz;
 IF registration IS NULL OR NOT isfinite(stamp) OR NOT isfinite(e.committed_at) OR stamp IS DISTINCT FROM e.committed_at OR stamp<c.admitted_at
  OR (stamp AT TIME ZONE (v->>'timezone'))::date IS DISTINCT FROM (v->>'local_date')::date
  OR e.original_facts#>>'{confirmed,id}' IS DISTINCT FROM registration::text OR e.original_facts#>>'{confirmed,user_id}' IS DISTINCT FROM c.user_id::text
  OR e.original_facts#>>'{confirmed,status}' IS DISTINCT FROM 'confirmed' OR jsonb_typeof(e.original_facts->'logs') IS DISTINCT FROM 'array' THEN RETURN NULL;END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(v->'log_ids') LOOP
  IF jsonb_typeof(item)<>'string' OR NOT(item#>>'{}' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
   OR item#>>'{}'=ANY(seen) THEN RETURN NULL;END IF;seen:=array_append(seen,item#>>'{}');
 END LOOP;
 SELECT jsonb_agg(x->'id' ORDER BY x->>'id') INTO ids FROM jsonb_array_elements(e.original_facts->'logs') x;
 IF ids IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY x) FROM unnest(seen) x)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(e.original_facts->'logs') x WHERE x->>'user_id' IS DISTINCT FROM c.user_id::text
   OR x->>'raw_provider_message_id' IS DISTINCT FROM v->>'provider_key' OR x->>'meal_type' IS DISTINCT FROM v->>'meal_type'
   OR (x->>'consumed_at')::timestamptz IS DISTINCT FROM stamp) THEN RETURN NULL;END IF;
 RETURN v;
EXCEPTION WHEN data_exception THEN RETURN NULL;
END $$;

-- A safe reference to an already sealed first winner, never its health body.
-- The existing helper checks the original proposal/source binding and v1/v2
-- reciprocal winner. It performs no capture, enrichment or receipt insertion.
CREATE FUNCTION private.conversation_thread_feedback_ref_v2(e private.conversation_meal_effects) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE r jsonb;v jsonb;
BEGIN
 r:=private.conversation_meal_feedback_receipt(e);
 IF r->>'action'='absent' THEN RETURN NULL;END IF;
 IF r->>'action' NOT IN('available','legacy') OR r->>'action' IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 v:=r->'feedback';
 IF v->>'schema' NOT IN('registration.feedback.v1','registration.feedback.v2') OR v->>'schema' IS NULL
  OR v->'registration_id' IS DISTINCT FROM e.receipt->'registration_id'
  OR (v->>'schema'='registration.feedback.v1' AND v->>'kind' IS DISTINCT FROM 'meal')
  OR (v->>'schema'='registration.feedback.v2' AND v#>>'{registration,kind}' IS DISTINCT FROM 'meal') THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 RETURN jsonb_build_object('schema',v->'schema','registration_id',v->'registration_id');
END $$;

CREATE FUNCTION private.conversation_thread_parent_v2(p_user uuid,p_parent uuid,p_epoch uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
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
END $$;

-- Cache only a compact selected-child projection, once per distinct child.
-- The qualified old read helper may inspect its immutable capsule internally;
-- no full source, model or preparation is serialized into a page result.
CREATE FUNCTION private.conversation_thread_child_v2(p_user uuid,p_reply uuid,capsule jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;l private.conversation_meal_reply_ids%ROWTYPE;
 fx private.conversation_meal_effects%ROWTYPE;v jsonb;receipt jsonb;ref jsonb;prep jsonb;status text;parent_id uuid;fulfilled uuid;body jsonb;question jsonb;
 parent jsonb:=capsule->'descriptor';proof jsonb:=nullif(capsule->'parent_proof','null'::jsonb);chain jsonb;prefix jsonb;link jsonb;expected_question jsonb;revision integer;
 previous_id uuid;previous_hash text;previous jsonb;
BEGIN
 IF proof IS NULL THEN RETURN NULL;END IF;
 parent_id:=(parent->>'thread_id')::uuid;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_reply;
 SELECT * INTO l FROM private.conversation_meal_reply_ids WHERE user_id=p_user AND reply_id=p_reply;
 IF parent#>'{continuation}'='null'::jsonb OR c.command_id IS NULL OR c.epoch::text IS DISTINCT FROM parent#>>'{parent_binding,epoch}'
  OR c.invalidated_at IS NOT NULL OR c.admitted_at<(parent#>>'{parent_binding,admitted_at}')::timestamptz
  OR l.parent_command_id IS DISTINCT FROM parent_id OR l.parent_input_hash IS DISTINCT FROM parent#>>'{parent_binding,input_hash}'
  OR l.parent_decision_hash IS DISTINCT FROM parent#>>'{terminal_receipt,decision_hash}' THEN RETURN NULL;END IF;
 v:=private.conversation_continuation_reply(p_user,parent_id,p_reply,c.input_hash,parent->'continuation');
 IF v IS NULL THEN RETURN NULL;END IF;
 body:=v->'body';SELECT q.question INTO question FROM private.conversation_meal_replies q WHERE q.user_id=p_user AND q.reply_id=p_reply;
 PERFORM private.assert_conversation_meal_reply(body);
 PERFORM private.conversation_meal_keys(question,ARRAY['schema','question_key','revision','kind','food_index','food_name','allowed_units','quantity_reference']);
 revision:=(body->>'expected_revision')::numeric::integer;chain:=v#>'{source,context,answer_chain}';
 IF jsonb_typeof(chain) IS DISTINCT FROM 'array' OR jsonb_array_length(chain)<>revision+1 THEN RETURN NULL;END IF;
 link:=chain->revision;
 IF link->>'reply_id' IS DISTINCT FROM p_reply::text OR link->>'reply_input_hash' IS DISTINCT FROM c.input_hash
  OR link->'question_key' IS DISTINCT FROM body->'question_key' OR link->'answer' IS DISTINCT FROM body->'answer' THEN RETURN NULL;END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY ord),'[]'::jsonb) INTO prefix FROM jsonb_array_elements(chain) WITH ORDINALITY a(x,ord) WHERE ord<=revision;
 expected_question:=private.conversation_continuation_question(proof,revision,prefix,question->>'kind',(question->>'food_index')::numeric::integer);
 IF expected_question IS NULL OR question IS DISTINCT FROM expected_question THEN RETURN NULL;END IF;
 IF revision>0 THEN
  previous_id:=(prefix#>>ARRAY[(revision-1)::text,'reply_id'])::uuid;
  SELECT old.input_hash INTO previous_hash FROM private.conversation_meal_command_ids old WHERE old.user_id=p_user AND old.command_id=previous_id;
  previous:=private.conversation_continuation_reply(p_user,parent_id,previous_id,previous_hash,parent->'continuation');
  IF previous IS NULL OR previous#>'{source,context,answer_chain}' IS DISTINCT FROM prefix
   OR previous#>>'{preparation,preparation,status}' IS DISTINCT FROM 'needs_reply'
   OR previous#>'{preparation,next_question}' IS DISTINCT FROM question THEN RETURN NULL;END IF;
 END IF;
 prep:=nullif(v->'preparation','null'::jsonb);
 IF prep IS NOT NULL THEN
  status:=prep#>>'{preparation,status}';
  IF prep#>>'{preparation,schema}' IS DISTINCT FROM 'conversation.meal-continuation-preparation.v1' OR status IS NULL OR status NOT IN('ready','needs_reply')
   OR prep#>'{preparation,input_hash}' IS DISTINCT FROM v#>'{binding,input_hash}'
   OR prep#>'{preparation,source_hash}' IS DISTINCT FROM v#>'{source,source_hash}'
   OR prep#>'{preparation,parent_ref}' IS DISTINCT FROM v#>'{source,context,parent}'
   OR prep#>'{preparation,answer_chain_hash}' IS DISTINCT FROM v#>'{source,context,answer_chain_hash}'
   OR (prep->>'prepared_at')::timestamptz<c.admitted_at THEN RETURN NULL;END IF;
  IF status='needs_reply' THEN
   PERFORM private.conversation_meal_keys(prep->'next_question',ARRAY['schema','question_key','revision','kind','food_index','food_name','allowed_units','quantity_reference']);
   expected_question:=private.conversation_continuation_question(proof,revision+1,chain,prep#>>'{preparation,next_need,kind}',
    (prep#>>'{preparation,next_need,food_index}')::numeric::integer);
   IF expected_question IS NULL OR prep->'next_question' IS DISTINCT FROM expected_question THEN RETURN NULL;END IF;
  ELSIF prep->'next_question'<>'null'::jsonb THEN RETURN NULL;END IF;
 END IF;
 SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_reply;
 IF fx.command_id IS NOT NULL THEN
  SELECT f.reply_id INTO fulfilled FROM private.conversation_meal_fulfillments f WHERE f.user_id=p_user AND f.parent_command_id=parent_id;
  IF fulfilled IS DISTINCT FROM p_reply OR parent#>>'{continuation,fulfilled_by}' IS DISTINCT FROM p_reply::text OR status IS DISTINCT FROM 'ready'
   OR fx.committed_at<(prep->>'prepared_at')::timestamptz THEN RETURN NULL;END IF;
  receipt:=private.conversation_thread_effect_v2(fx,c,parent);IF receipt IS NULL THEN RETURN NULL;END IF;
  ref:=private.conversation_thread_feedback_ref_v2(fx);IF ref ? 'action' THEN RETURN NULL;END IF;
 END IF;
 RETURN jsonb_build_object('child_binding',v->'binding','body',body,'question',question,
  'prepared_hash',CASE WHEN prep IS NULL THEN NULL ELSE prep->'prepared_hash' END,
  'prepared_at',CASE WHEN prep IS NULL THEN NULL ELSE private.conversation_thread_clock_v2((prep->>'prepared_at')::timestamptz) END,
  'status',CASE status WHEN 'ready' THEN 'prepared' ELSE status END,'next_question',CASE WHEN prep IS NULL THEN NULL ELSE prep->'next_question' END,
  'receipt',receipt,'committed_at',private.conversation_thread_clock_v2(fx.committed_at),'feedback_ref',ref);
EXCEPTION WHEN data_exception THEN RETURN NULL;
END $$;

CREATE FUNCTION private.conversation_thread_entry_v2(p_user uuid,key jsonb,parent jsonb,child jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;fx private.conversation_meal_effects%ROWTYPE;
 op private.conversation_meal_edit_operations%ROWTYPE;ident private.conversation_meal_edit_ids%ROWTYPE;receipt jsonb;ref jsonb;base jsonb;effect_id uuid;
 id jsonb;field text;removed text[];added text[];n numeric;
BEGIN
 effect_id:=(key->>'effect_id')::uuid;
 base:=jsonb_build_object('event_id',key->'event_id','at',key->'at','kind',key->'kind','thread_id',key->'thread_id');
 IF key->>'kind'='report' THEN
  SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=effect_id;
  SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=effect_id;
  IF fx.command_id IS NOT NULL THEN
   receipt:=private.conversation_thread_effect_v2(fx,c,parent);IF receipt IS NULL THEN RETURN NULL;END IF;
   ref:=private.conversation_thread_feedback_ref_v2(fx);IF ref ? 'action' THEN RETURN NULL;END IF;
  END IF;
  IF key->>'event_id' IS DISTINCT FROM 'command/'||c.command_id::text OR key->>'at' IS DISTINCT FROM private.conversation_thread_clock_v2(c.admitted_at) THEN RETURN NULL;END IF;
  RETURN base||jsonb_build_object('status',CASE WHEN receipt IS NOT NULL THEN 'registered' WHEN parent->'terminal_receipt'<>'null'::jsonb THEN 'not_recorded' ELSE 'pending' END,
   'receipt',receipt,'feedback_ref',ref);
 ELSIF key->>'kind'='reply' THEN
  IF child IS NULL OR key->>'at' IS DISTINCT FROM child#>>'{child_binding,admitted_at}' THEN RETURN NULL;END IF;
  RETURN base||jsonb_build_object('child_binding',child->'child_binding','body',child->'body','question',child->'question');
 ELSIF key->>'kind'='reply_result' THEN
  IF child IS NULL OR child->'prepared_hash'='null'::jsonb OR key->>'at' IS DISTINCT FROM child->>'prepared_at' THEN RETURN NULL;END IF;
  RETURN base||jsonb_build_object('child_binding',child->'child_binding','prepared_hash',child->'prepared_hash','status',child->'status','next_question',child->'next_question');
 ELSIF key->>'kind'='fulfillment' THEN
  IF child IS NULL OR child->'receipt'='null'::jsonb OR key->>'at' IS DISTINCT FROM child->>'committed_at' THEN RETURN NULL;END IF;
  RETURN base||jsonb_build_object('child_binding',child->'child_binding','receipt',child->'receipt','feedback_ref',child->'feedback_ref');
 ELSIF key->>'kind'='edit' THEN
  SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=effect_id;
  SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=effect_id;
  IF c.epoch::text IS DISTINCT FROM parent#>>'{parent_binding,epoch}' OR private.conversation_thread_effect_v2(fx,c,parent) IS NULL
   OR (c.command_protocol='conversation.clarification.v1' AND (child IS NULL OR child->'receipt'='null'::jsonb)) THEN RETURN NULL;END IF;
  SELECT * INTO op FROM private.conversation_meal_edit_operations WHERE user_id=p_user AND command_id=effect_id AND operation_id=(key->>'operation_id')::uuid;
  SELECT * INTO ident FROM private.conversation_meal_edit_ids WHERE user_id=p_user AND command_id=effect_id AND operation_id=op.operation_id;
  receipt:=op.receipt;
  PERFORM private.conversation_meal_keys(receipt,ARRAY['schema','owner_id','command_id','operation_id','input_hash','kind','revision','applied_at','undo_expires_at','target_operation_id','removed_item_ids','new_item_ids','next_record_id','snapshot']);
  IF ident.operation_id IS NULL OR ident.epoch IS DISTINCT FROM c.epoch OR ident.input_hash IS DISTINCT FROM receipt->>'input_hash'
   OR receipt->>'schema' IS DISTINCT FROM 'conversation.meal-edit-effect.v1' OR receipt->>'owner_id' IS DISTINCT FROM p_user::text
   OR receipt->>'command_id' IS DISTINCT FROM c.command_id::text OR receipt->>'operation_id' IS DISTINCT FROM op.operation_id::text
   OR op.applied_at<c.admitted_at OR (receipt->>'applied_at')::timestamptz IS DISTINCT FROM op.applied_at
   OR key->>'at' IS DISTINCT FROM private.conversation_thread_clock_v2(op.applied_at)
   OR receipt->>'kind' IS DISTINCT FROM (CASE ident.kind WHEN 'save' THEN 'saved' WHEN 'undo_save' THEN 'save_undone' WHEN 'undo_registration' THEN 'registration_undone' END)
   OR jsonb_typeof(receipt->'revision') IS DISTINCT FROM 'number' OR jsonb_typeof(receipt->'applied_at') IS DISTINCT FROM 'string'
   OR (receipt->'undo_expires_at'<>'null'::jsonb AND jsonb_typeof(receipt->'undo_expires_at') IS DISTINCT FROM 'string')
   OR (receipt->'target_operation_id'<>'null'::jsonb AND (jsonb_typeof(receipt->'target_operation_id') IS DISTINCT FROM 'string'
    OR NOT(receipt->>'target_operation_id' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'))) THEN RETURN NULL;END IF;
  n:=(receipt->>'revision')::numeric;IF n NOT BETWEEN 1 AND 2147483647 OR n<>trunc(n) THEN RETURN NULL;END IF;
  FOREACH field IN ARRAY ARRAY['removed_item_ids','new_item_ids'] LOOP
   IF jsonb_typeof(receipt->field) IS DISTINCT FROM 'array' OR jsonb_array_length(receipt->field)>30
    OR (field='removed_item_ids' AND jsonb_array_length(receipt->field)<1) THEN RETURN NULL;END IF;
   IF field='removed_item_ids' THEN removed:='{}';ELSE added:='{}';END IF;
   FOR id IN SELECT value FROM jsonb_array_elements(receipt->field) LOOP
    IF jsonb_typeof(id)<>'string' OR NOT(id#>>'{}' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') THEN RETURN NULL;END IF;
    IF field='removed_item_ids' THEN IF id#>>'{}'=ANY(removed) THEN RETURN NULL;END IF;removed:=array_append(removed,id#>>'{}');
    ELSE IF id#>>'{}'=ANY(added) THEN RETURN NULL;END IF;added:=array_append(added,id#>>'{}');END IF;
   END LOOP;
  END LOOP;
  IF removed && added THEN RETURN NULL;END IF;
  IF ident.kind='save' THEN
   IF cardinality(removed)<>1 OR cardinality(added)<1 OR receipt->>'next_record_id' IS DISTINCT FROM added[1]
    OR receipt->'target_operation_id'<>'null'::jsonb OR receipt->'undo_expires_at'='null'::jsonb
    OR (receipt->>'undo_expires_at')::timestamptz IS DISTINCT FROM op.applied_at+interval '5 minutes' THEN RETURN NULL;END IF;
  ELSIF ident.kind='undo_save' THEN
   IF n<2 OR cardinality(added)<>1 OR receipt->>'next_record_id' IS DISTINCT FROM added[1] OR receipt->'undo_expires_at'<>'null'::jsonb
    OR receipt->>'target_operation_id' IS NULL OR (receipt->>'target_operation_id')::uuid=op.operation_id THEN RETURN NULL;END IF;
  ELSIF ident.kind='undo_registration' THEN
   IF n<>1 OR cardinality(added)<>0 OR receipt->'next_record_id'<>'null'::jsonb OR receipt->'target_operation_id'<>'null'::jsonb OR receipt->'undo_expires_at'<>'null'::jsonb THEN RETURN NULL;END IF;
  END IF;
  SELECT jsonb_object_agg(k,v) INTO receipt FROM jsonb_each(receipt) x(k,v)
   WHERE k=ANY(ARRAY['owner_id','command_id','operation_id','input_hash','kind','revision','applied_at','undo_expires_at','target_operation_id','removed_item_ids','new_item_ids','next_record_id']);
  receipt:=receipt||jsonb_build_object('schema','conversation.meal-edit-effect-public.v1');
  RETURN base||jsonb_build_object('effect_binding',private.conversation_meal_command_binding(c),'receipt',receipt);
 END IF;
 RETURN NULL;
EXCEPTION WHEN data_exception THEN RETURN NULL;
END $$;

CREATE FUNCTION public.read_conversation_meal_journal_page_v2(p_user_id uuid,p_expected_epoch uuid,p_limit integer DEFAULT 10,p_cursor jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
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
  parent:=private.conversation_thread_parent_v2(p_user_id,parent_id,epoch);IF parent IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
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
END $$;

REVOKE ALL ON FUNCTION private.conversation_thread_clock_v2(timestamptz),private.conversation_thread_events_v2(uuid,uuid),
 private.conversation_thread_effect_v2(private.conversation_meal_effects,private.conversation_meal_command_ids,jsonb),
 private.conversation_thread_feedback_ref_v2(private.conversation_meal_effects),private.conversation_thread_parent_v2(uuid,uuid,uuid),
 private.conversation_thread_child_v2(uuid,uuid,jsonb),private.conversation_thread_entry_v2(uuid,jsonb,jsonb,jsonb),
 public.read_conversation_meal_journal_page_v2(uuid,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_journal_page_v2(uuid,uuid,integer,jsonb) TO service_role;
COMMIT;

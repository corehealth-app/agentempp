-- Observational conversation timeline. Explicit reset is the epoch cutoff;
-- profile changes/reevaluation never create or rotate authority here.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('public.read_conversation_intake(uuid,uuid,text,uuid)') IS NULL
 OR to_regprocedure('private.conversation_thread_parent_v2(uuid,uuid,uuid)') IS NULL
 OR to_regprocedure('private.conversation_thread_child_v2(uuid,uuid,jsonb)') IS NULL
 OR to_regprocedure('private.conversation_thread_entry_v2(uuid,jsonb,jsonb,jsonb)') IS NULL
 OR to_regclass('private.conversation_workout_inputs') IS NULL THEN
  RAISE EXCEPTION 'journal_v3_requires_current_substrate' USING ERRCODE='55000';END IF;
END $preflight$;
-- Historical validation reads only immutable originals. It deliberately never
-- calls the live media projection helper, whose locks/day checks authorize POST.
CREATE FUNCTION private.conversation_journal_media_input_v3(u uuid,input jsonb) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;s private.conversation_intake_sources%ROWTYPE;r private.conversation_intake_routing_results%ROWTYPE;
 raw jsonb;selected jsonb;media jsonb;origin jsonb;expected jsonb;projection jsonb;claim uuid;h text;
BEGIN
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=(input#>>'{intake_origin,intake_id}')::uuid;
 IF c.intake_id IS NULL OR c.invalidated_at IS NOT NULL OR c.reserved_child_id::text IS DISTINCT FROM input->>'command_id'
 OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e WHERE e.user_id=u AND e.epoch=c.epoch) THEN RETURN false;END IF;
 SELECT source_input INTO raw FROM private.conversation_intake_inputs WHERE user_id=u AND intake_id=c.intake_id;
 SELECT * INTO s FROM private.conversation_intake_sources WHERE user_id=u AND intake_id=c.intake_id;
 SELECT * INTO r FROM private.conversation_intake_routing_results WHERE user_id=u AND intake_id=c.intake_id;
 SELECT claim_id INTO claim FROM private.conversation_intake_claims WHERE user_id=u AND intake_id=c.intake_id;
 SELECT selection INTO selected FROM private.conversation_intake_selections WHERE user_id=u AND intake_id=c.intake_id;
 IF raw IS NULL OR s.intake_id IS NULL OR r.intake_id IS NULL OR claim IS NULL OR selected IS NULL THEN RETURN false;END IF;
 PERFORM private.assert_conversation_intake_input(raw);PERFORM private.assert_conversation_intake_decision(r.decision);
 IF c.input_hash IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex')
 OR s.source_hash IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(s.context),'UTF8')),'hex')
 OR s.context->'source_input' IS DISTINCT FROM raw OR s.context->>'owner_id' IS DISTINCT FROM u::text OR s.context->>'intake_id' IS DISTINCT FROM c.intake_id::text
 OR s.context->>'epoch' IS DISTINCT FROM c.epoch::text OR s.context->>'input_hash' IS DISTINCT FROM c.input_hash
 OR r.decision_hash IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(r.decision),'UTF8')),'hex') THEN RETURN false;END IF;
 media:=s.context->'media';
 IF raw#>>'{source,channel}' IS DISTINCT FROM 'media' OR raw#>>'{source,user_action}' IS DISTINCT FROM 'report_actual_record'
 OR media->>'owner_id' IS DISTINCT FROM u::text OR media->>'asset_id' IS DISTINCT FROM raw#>>'{source,media_asset_id}' OR media->>'status' IS DISTINCT FROM 'processed'
 OR NOT isfinite((media->>'processed_at')::timestamptz) OR NOT isfinite((media->>'updated_at')::timestamptz)
 OR (r.decision->>'kind'='meal.report' AND media->>'kind' NOT IN('meal_photo','audio_note'))
 OR (r.decision->>'kind'='workout.report' AND media->>'kind' NOT IN('gym_photo','audio_note')) OR r.decision->>'kind' NOT IN('meal.report','workout.report') THEN RETURN false;END IF;
 origin:=jsonb_build_object('schema','conversation.intake-media-origin.v1','intake_id',c.intake_id,'input_hash',c.input_hash,'source_hash',s.source_hash,'epoch',c.epoch,'claim_id',claim,'decision_hash',r.decision_hash);
 expected:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',c.reserved_child_id,'kind',r.decision->>'kind','source',raw->'source','intake_origin',origin);
 IF r.decision->>'kind'='meal.report' AND raw ? 'meal_type_hint' THEN expected:=expected||jsonb_build_object('meal_type',raw->'meal_type_hint');END IF;
 IF input IS DISTINCT FROM expected THEN RETURN false;END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex');
 projection:=jsonb_build_object('schema','conversation.intake-media-projection.v1','origin',origin,'child_input_hash',h,'media',jsonb_build_object('asset_id',media->'asset_id','owner_id',media->'owner_id','kind',media->'kind','processed_at',media->'processed_at','updated_at',media->'updated_at','processing_hash',encode(sha256(convert_to(private.conversation_command_canonical(jsonb_build_object('context_text',media->'context_text','processing_result',media->'processing_result')),'UTF8')),'hex')));
 PERFORM private.conversation_meal_keys(selected,ARRAY['schema','intake','source_hash','decision_hash','decision','selected_at','command','media_projection']);
 RETURN coalesce(selected->>'schema'='conversation.intake-selection.v2' AND selected->'intake'=private.conversation_intake_binding(c) AND selected->>'source_hash'=s.source_hash
 AND selected->'decision'=r.decision AND selected->>'decision_hash'=r.decision_hash AND selected->'media_projection'=projection AND selected#>'{command,input}'=input AND selected#>>'{command,input_hash}'=h,false);
EXCEPTION WHEN data_exception THEN RETURN false;
END $$;
-- Clone the exact qualified v2 projection under a new private identity. Only
-- its input validator changes for genuine internal neutral media. Old readers,
-- their guards and source bodies remain byte-identical.
DO $historical_parent$
DECLARE body text;needle text:=' PERFORM private.assert_conversation_meal_input(raw);';
BEGIN
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='private.conversation_thread_parent_v2(uuid,uuid,uuid)'::regprocedure) IS DISTINCT FROM 'ba20465e5a4ea2cc62963f165b49e032cbdd197db06fe176f635ef3e4cc64825' THEN RAISE EXCEPTION 'journal_v3_unknown_parent_substrate';END IF;
 body:=pg_get_functiondef('private.conversation_thread_parent_v2(uuid,uuid,uuid)'::regprocedure);
 IF (length(body)-length(replace(body,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'journal_v3_parent_validation_hook';END IF;
 body:=replace(body,'private.conversation_thread_parent_v2(', 'private.conversation_journal_parent_v3(');
 EXECUTE replace(body,needle,' IF raw ? ''intake_origin'' THEN IF NOT private.conversation_journal_media_input_v3(p_user,raw) THEN RETURN NULL;END IF;ELSE'||needle||'END IF;');
END $historical_parent$;
CREATE INDEX conversation_intake_journal_page_v3 ON private.conversation_intake_ids(user_id,epoch,admitted_at DESC,intake_id DESC) WHERE invalidated_at IS NULL;
CREATE INDEX conversation_workout_journal_page_v3 ON private.conversation_workout_command_ids(user_id,epoch,admitted_at DESC,command_id DESC) WHERE invalidated_at IS NULL;
CREATE FUNCTION private.conversation_journal_events_v3(p_user uuid,p_epoch uuid)
RETURNS TABLE(at timestamptz,event_id text,origin text,intake_id uuid,command_id uuid,thread_id uuid,effect_id uuid,reply_id uuid,operation_id uuid,kind text)
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT c.admitted_at,'intake/'||c.intake_id::text,'intake'::text,c.intake_id,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text
 FROM private.conversation_intake_ids c WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL
 UNION ALL
 SELECT c.admitted_at,'workout/'||c.command_id::text,'workout',NULL::uuid,c.command_id,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text
 FROM private.conversation_workout_command_ids c WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_ids i WHERE i.user_id=c.user_id AND i.reserved_child_id=c.command_id)
 UNION ALL
 SELECT e.at,e.event_id,'meal',i.intake_id,NULL::uuid,e.thread_id,e.effect_id,e.reply_id,e.operation_id,e.kind
 FROM private.conversation_thread_events_v2(p_user,p_epoch) e
 LEFT JOIN private.conversation_intake_ids i ON i.user_id=p_user AND i.reserved_child_id=e.thread_id
 WHERE NOT(e.kind='report' AND i.intake_id IS NOT NULL);
$$;
CREATE FUNCTION public.read_conversation_journal_page_v3(p_user_id uuid,p_expected_epoch uuid,p_limit integer DEFAULT 10,p_cursor jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE v_epoch uuid;cursor_at timestamptz;cursor_id text;keys jsonb;row jsonb;entry jsonb;parent jsonb;child jsonb;capsule jsonb;selection jsonb;typed jsonb;raw jsonb;
 c private.conversation_intake_ids%ROWTYPE;w private.conversation_workout_command_ids%ROWTYPE;m private.conversation_meal_command_ids%ROWTYPE;
 intakes jsonb:='[]';workouts jsonb:='[]';parents jsonb:='{}';children jsonb:='{}';threads jsonb:='[]';items jsonb:='[]';meal_keys jsonb:='[]';meal_items jsonb:='[]';
 more boolean;last_cursor jsonb;observed timestamptz;parent_id uuid;v_intake_id uuid;parent_key text;reply_key text;
 id_pattern text:='[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_expected_epoch IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'invalid_conversation_journal_v3' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"absent"}';END IF;
 SELECT e.epoch INTO v_epoch FROM private.workout_strength_authority_epochs e WHERE user_id=p_user_id;
 IF v_epoch IS NULL OR p_expected_epoch IS DISTINCT FROM v_epoch THEN RETURN '{"action":"stale_epoch"}';END IF;
 BEGIN -- Corrupt historical projections refuse without swallowing SQL argument errors.
 IF p_cursor IS NOT NULL THEN
  BEGIN
   PERFORM private.conversation_meal_keys(p_cursor,ARRAY['at','id']);
   IF jsonb_typeof(p_cursor->'at') IS DISTINCT FROM 'string' OR jsonb_typeof(p_cursor->'id') IS DISTINCT FROM 'string'
    OR NOT(p_cursor->>'at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$')
    OR NOT(p_cursor->>'id' ~ ('^(?:(?:intake|workout|command)/'||id_pattern||'|(?:reply|reply-result|fulfillment|edit)/'||id_pattern||'/'||id_pattern||')$')) THEN RAISE EXCEPTION 'invalid_cursor';END IF;
   cursor_at:=(p_cursor->>'at')::timestamptz;cursor_id:=p_cursor->>'id';
   IF NOT isfinite(cursor_at) OR NOT EXISTS(SELECT 1 FROM private.conversation_journal_events_v3(p_user_id,v_epoch) e WHERE e.at=cursor_at AND e.event_id=cursor_id) THEN RAISE EXCEPTION 'invalid_cursor';END IF;
  EXCEPTION WHEN data_exception OR raise_exception THEN RETURN '{"action":"cursor_conflict"}';END;
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(e)-'at'||jsonb_build_object('at',private.conversation_thread_clock_v2(e.at)) ORDER BY e.at DESC,e.event_id COLLATE "C" DESC),'[]') INTO keys
 FROM (SELECT x.* FROM private.conversation_journal_events_v3(p_user_id,v_epoch) x WHERE cursor_at IS NULL OR x.at<cursor_at OR (x.at=cursor_at AND (x.event_id COLLATE "C")<(cursor_id COLLATE "C"))
 ORDER BY x.at DESC,x.event_id COLLATE "C" DESC LIMIT p_limit+1) e;
 more:=jsonb_array_length(keys)>p_limit;
 SELECT coalesce(jsonb_agg(x ORDER BY ord),'[]') INTO keys FROM jsonb_array_elements(keys) WITH ORDINALITY a(x,ord) WHERE ord<=p_limit;
 -- Only original intakes actually referenced by the selected prefix are read.
 FOR v_intake_id IN SELECT DISTINCT (x->>'intake_id')::uuid FROM jsonb_array_elements(keys) x WHERE x->>'intake_id' IS NOT NULL LOOP
  SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=v_intake_id AND conversation_intake_ids.epoch=v_epoch AND invalidated_at IS NULL;
  IF NOT FOUND THEN RETURN '{"action":"event_conflict"}';END IF;
  capsule:=public.read_conversation_intake(p_user_id,v_intake_id,c.input_hash,v_epoch);
  IF capsule->>'action' IS DISTINCT FROM 'available' THEN RETURN '{"action":"event_conflict"}';END IF;
  PERFORM private.assert_conversation_intake_input(capsule->'source_input');
  IF encode(sha256(convert_to(private.conversation_command_canonical(capsule->'source_input'),'UTF8')),'hex') IS DISTINCT FROM c.input_hash THEN RETURN '{"action":"event_conflict"}';END IF;
  selection:=capsule->'selection';
  IF selection<>'null'::jsonb THEN
   IF selection->>'schema' IS DISTINCT FROM 'conversation.intake-selection.v1' AND selection->>'schema' IS DISTINCT FROM 'conversation.intake-selection.v2' THEN RETURN '{"action":"event_conflict"}';END IF;
   PERFORM private.conversation_meal_keys(selection,ARRAY['schema','intake','source_hash','decision_hash','decision','selected_at','command']||CASE WHEN selection->>'schema'='conversation.intake-selection.v2' THEN ARRAY['media_projection'] ELSE ARRAY[]::text[] END);
   PERFORM private.assert_conversation_intake_decision(selection->'decision');
   IF selection->'intake' IS DISTINCT FROM capsule->'intake' OR selection->'source_hash' IS DISTINCT FROM capsule->'source_hash'
    OR selection->>'decision_hash' IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(selection->'decision'),'UTF8')),'hex')
    OR NOT isfinite((selection->>'selected_at')::timestamptz) OR (selection->>'selected_at')::timestamptz<c.admitted_at THEN RETURN '{"action":"event_conflict"}';END IF;
   typed:=selection->'command';
   IF selection->>'schema'='conversation.intake-selection.v2' AND NOT private.conversation_journal_media_input_v3(p_user_id,typed->'input') THEN RETURN '{"action":"event_conflict"}';END IF;
   IF typed<>'null'::jsonb THEN
    IF typed->>'command_id' IS DISTINCT FROM c.reserved_child_id::text OR typed->>'owner_id' IS DISTINCT FROM p_user_id::text OR typed->>'epoch' IS DISTINCT FROM v_epoch::text
     OR typed->>'kind' IS DISTINCT FROM selection#>>'{decision,kind}' OR NOT isfinite((typed->>'admitted_at')::timestamptz)
     OR (typed->>'admitted_at')::timestamptz<c.admitted_at OR (typed->>'admitted_at')::timestamptz>(selection->>'selected_at')::timestamptz THEN RETURN '{"action":"event_conflict"}';END IF;
    IF typed->>'kind'='workout.report' THEN
     SELECT * INTO w FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=c.reserved_child_id;
     SELECT source_input INTO raw FROM private.conversation_workout_inputs WHERE user_id=p_user_id AND command_id=c.reserved_child_id;
     IF w.command_id IS NULL OR w.invalidated_at IS NOT NULL OR w.epoch IS DISTINCT FROM v_epoch OR w.input_hash IS DISTINCT FROM typed->>'input_hash' OR w.admitted_at IS DISTINCT FROM (typed->>'admitted_at')::timestamptz OR raw IS DISTINCT FROM typed->'input' THEN RETURN '{"action":"event_conflict"}';END IF;
    ELSIF typed->>'kind'='meal.report' THEN
     SELECT * INTO m FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=c.reserved_child_id;
     SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user_id AND command_id=c.reserved_child_id;
     IF m.command_id IS NULL OR m.invalidated_at IS NOT NULL OR m.epoch IS DISTINCT FROM v_epoch OR m.input_hash IS DISTINCT FROM typed->>'input_hash' OR m.admitted_at IS DISTINCT FROM (typed->>'admitted_at')::timestamptz OR raw IS DISTINCT FROM typed->'input' THEN RETURN '{"action":"event_conflict"}';END IF;
    ELSE RETURN '{"action":"event_conflict"}';END IF;
   ELSIF selection#>>'{decision,kind}' IN('meal.report','workout.report') THEN RETURN '{"action":"event_conflict"}';END IF;
  ELSIF EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=c.reserved_child_id)
   OR EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=c.reserved_child_id) THEN RETURN '{"action":"event_conflict"}';END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(keys) x WHERE x->>'origin'='meal' AND x->>'intake_id'=v_intake_id::text)
   AND (selection#>>'{command,kind}' IS DISTINCT FROM 'meal.report') THEN RETURN '{"action":"event_conflict"}';END IF;
  intakes:=intakes||jsonb_build_array(capsule);
 END LOOP;
 FOR row IN SELECT value FROM jsonb_array_elements(keys) LOOP
  IF row->>'origin'='intake' THEN
   items:=items||jsonb_build_array(jsonb_build_object('kind','intake','event_id',row->'event_id','at',row->'at','intake_id',row->'intake_id'));
   SELECT value#>'{selection,command}' INTO typed FROM jsonb_array_elements(intakes) WHERE value#>>'{intake,intake_id}'=row->>'intake_id';
   IF typed->>'kind'='meal.report' THEN
    SELECT to_jsonb(e)-'at'||jsonb_build_object('at',private.conversation_thread_clock_v2(e.at)) INTO entry FROM private.conversation_thread_events_v2(p_user_id,v_epoch) e WHERE e.event_id='command/'||(typed->>'command_id');
    IF entry IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;meal_keys:=meal_keys||jsonb_build_array(entry);
   ELSIF typed->>'kind'='workout.report' THEN
    SELECT * INTO w FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=(typed->>'command_id')::uuid;
    SELECT source_input INTO raw FROM private.conversation_workout_inputs WHERE user_id=p_user_id AND command_id=w.command_id;
    workouts:=workouts||jsonb_build_array(jsonb_build_object('binding',jsonb_build_object('owner_id',w.user_id,'command_id',w.command_id,'input_hash',w.input_hash,'epoch',w.epoch,'admitted_at',private.conversation_thread_clock_v2(w.admitted_at)),'source_input',raw));
   END IF;
  ELSIF row->>'origin'='workout' THEN
   SELECT * INTO w FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=(row->>'command_id')::uuid;
   SELECT source_input INTO raw FROM private.conversation_workout_inputs WHERE user_id=p_user_id AND command_id=w.command_id;
   PERFORM private.assert_conversation_workout_input(raw);
   IF raw IS NULL OR encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex') IS DISTINCT FROM w.input_hash THEN RETURN '{"action":"event_conflict"}';END IF;
   workouts:=workouts||jsonb_build_array(jsonb_build_object('binding',jsonb_build_object('owner_id',w.user_id,'command_id',w.command_id,'input_hash',w.input_hash,'epoch',w.epoch,'admitted_at',private.conversation_thread_clock_v2(w.admitted_at)),'source_input',raw));
   items:=items||jsonb_build_array(jsonb_build_object('kind','workout','event_id',row->'event_id','at',row->'at','command_id',row->'command_id'));
  ELSE
   meal_keys:=meal_keys||jsonb_build_array(row-'origin'-'intake_id'-'command_id');
   items:=items||jsonb_build_array(jsonb_build_object('kind','meal','event_id',row->'event_id','at',row->'at','intake_id',row->'intake_id'));
  END IF;
  last_cursor:=jsonb_build_object('at',row->'at','id',row->'event_id');
 END LOOP;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'at')::timestamptz DESC,(x->>'event_id') COLLATE "C" DESC),'[]') INTO meal_keys FROM (SELECT DISTINCT x FROM jsonb_array_elements(meal_keys) x) d;
 FOR parent_key IN SELECT DISTINCT (x->>'thread_id') COLLATE "C" FROM jsonb_array_elements(meal_keys) x ORDER BY 1 LOOP
  parent_id:=parent_key::uuid;IF parent_id IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;
  parent:=private.conversation_journal_parent_v3(p_user_id,parent_id,v_epoch);IF parent IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;
  parents:=parents||jsonb_build_object(parent_key,parent);threads:=threads||jsonb_build_array(parent->'descriptor');
 END LOOP;
 FOR reply_key,parent_key IN SELECT DISTINCT x->>'reply_id',x->>'thread_id' FROM jsonb_array_elements(meal_keys) x WHERE x->>'reply_id' IS NOT NULL LOOP
  IF children ? reply_key THEN RETURN '{"action":"event_conflict"}';END IF;
  child:=private.conversation_thread_child_v2(p_user_id,reply_key::uuid,parents->parent_key);IF child IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;children:=children||jsonb_build_object(reply_key,child);
 END LOOP;
 FOR row IN SELECT value FROM jsonb_array_elements(meal_keys) LOOP
  entry:=private.conversation_thread_entry_v2(p_user_id,row,parents#>ARRAY[row->>'thread_id','descriptor'],children->(row->>'reply_id'));
  IF entry IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;meal_items:=meal_items||jsonb_build_array(entry);
 END LOOP;
 observed:=clock_timestamp();
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(items) x WHERE NOT isfinite((x->>'at')::timestamptz) OR (x->>'at')::timestamptz>observed)
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(intakes) x WHERE (x#>>'{selection,selected_at}')::timestamptz>observed)
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(meal_items) x WHERE (x->>'at')::timestamptz>observed OR (x#>>'{receipt,consumed_at}')::timestamptz>observed) THEN RETURN '{"action":"event_conflict"}';END IF;
 RETURN jsonb_build_object('action','available','schema','conversation.journal-page-private.v3','owner_id',p_user_id,'epoch',v_epoch,'observed_at',private.conversation_thread_clock_v2(observed),
  'intakes',intakes,'workouts',workouts,'meal_page',jsonb_build_object('action','available','schema','conversation.journal-page-private.v2','owner_id',p_user_id,'epoch',v_epoch,'observed_at',private.conversation_thread_clock_v2(observed),'threads',threads,'items',meal_items,'has_more',false,'next_cursor',NULL),
  'items',items,'has_more',more,'next_cursor',CASE WHEN more THEN last_cursor ELSE NULL END);
 EXCEPTION WHEN data_exception THEN RETURN '{"action":"event_conflict"}';
 END;
END $$;
REVOKE ALL ON FUNCTION private.conversation_journal_media_input_v3(uuid,jsonb),private.conversation_journal_parent_v3(uuid,uuid,uuid),private.conversation_journal_events_v3(uuid,uuid),public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb) TO service_role;
COMMIT;

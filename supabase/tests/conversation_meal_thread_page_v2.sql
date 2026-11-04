-- Actual RED before installation: this must fail with THREAD_PAGE_V2_RED.
-- No PG execution until explicit runtime/registry ownership handover.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN IF to_regprocedure('public.read_conversation_meal_journal_page_v2(uuid,uuid,integer,jsonb)') IS NULL THEN
 RAISE EXCEPTION 'THREAD_PAGE_V2_RED:missing_compact_reader';END IF;END $$;
\ir fixtures/conversation_meal_thread_page_v2_fixture.sql
DO $test$
DECLARE u uuid:='c3d20000-0000-4000-8000-000000000001';a uuid:='c3d20000-0000-4000-8000-000000000002';
 p uuid:='c3d20000-0000-4000-8000-000000000003';r1 uuid:='c3d20000-0000-4000-8000-000000000004';r2 uuid:='c3d20000-0000-4000-8000-000000000005';
 c1 uuid:='c3d20000-0000-4000-8000-000000000101';c2 uuid:='c3d20000-0000-4000-8000-000000000102';pending uuid:='c3d20000-0000-4000-8000-000000000103';
 foreign_u uuid:='c3d20000-0000-4000-8000-000000000201';foreign_a uuid:='c3d20000-0000-4000-8000-000000000202';foreign_p uuid:='c3d20000-0000-4000-8000-000000000203';
 op uuid:='c3d20000-0000-4000-8000-000000000301';bad_op uuid:='c3d20000-0000-4000-8000-000000000302';bad_clock timestamptz;bad_receipt jsonb;seed jsonb;other_seed jsonb;epoch uuid;state jsonb;body jsonb;ad1 jsonb;ad2 jsonb;partial jsonb;ready jsonb;fx jsonb;
 page jsonb;whole jsonb;before_state jsonb;original jsonb;first_cursor jsonb;cursor jsonb;entry jsonb;descriptor jsonb;ids text[]:='{}';expected text[];calls integer:=0;row jsonb;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,p);epoch:=(seed#>>'{terminal,epoch}')::uuid;
 other_seed:=pg_temp.continuation_seed(foreign_u,foreign_a,foreign_p);
 original:=pg_temp.continuation_read(u,p,seed)->'parent';
 state:=pg_temp.continuation_read(u,p,seed);body:=pg_temp.continuation_body(state,'{"kind":"quantity","food_index":0,"amount":100,"unit":"g"}');
 ad1:=pg_temp.continuation_admit(u,p,seed,r1,body);state:=pg_temp.continuation_read(u,p,seed,r1,ad1#>>'{child_binding,input_hash}');
 partial:=pg_temp.continuation_prepare(u,p,seed,r1,ad1#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(state,false));
 page:=public.read_conversation_meal_journal_page_v2(u,epoch,1);first_cursor:=page->'next_cursor';
 PERFORM pg_temp.writer_ok(page#>>'{items,0,kind}'='reply_result' AND page#>>'{items,0,status}'='needs_reply'
  AND page#>>'{items,0,next_question,kind}'='meal_type','partial preparation has its own durable event after admission');
 state:=pg_temp.continuation_read(u,p,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 ad2:=pg_temp.continuation_admit(u,p,seed,r2,body);state:=pg_temp.continuation_read(u,p,seed,r2,ad2#>>'{child_binding,input_hash}');
 ready:=pg_temp.continuation_prepare(u,p,seed,r2,ad2#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(state));
 fx:=pg_temp.continuation_commit(u,p,seed,r2,ad2#>>'{child_binding,input_hash}',ready#>>'{stored,prepared_hash}');
 PERFORM pg_temp.thread_v2_register(u,c1);PERFORM pg_temp.thread_v2_register(u,c2);PERFORM public.admit_conversation_meal_command(u,pg_temp.writer_input(pending));
 PERFORM pg_temp.thread_v2_save(u,c1,op);PERFORM pg_temp.thread_v2_save(u,c2,op);PERFORM pg_temp.thread_v2_legacy_feedback(u,c1);
 before_state:=pg_temp.semantic_owner_state(u);whole:=public.read_conversation_meal_journal_page_v2(u,epoch,25);
 PERFORM pg_temp.writer_ok(whole->>'action'='available' AND whole->>'schema'='conversation.journal-page-private.v2'
  AND whole->>'owner_id'=u::text AND whole->>'epoch'=epoch::text AND jsonb_array_length(whole->'items')=11
  AND jsonb_array_length(whole->'threads')=4 AND whole->'has_more'='false'::jsonb AND whole->'next_cursor'='null'::jsonb,'one setwise page contains all five variants with parents deduplicated');
 SELECT value INTO descriptor FROM jsonb_array_elements(whole->'threads') WHERE value->>'thread_id'=p::text;
 PERFORM pg_temp.writer_ok(descriptor#>'{original_command}'=original#>'{source,context,source_input}'
  AND descriptor#>>'{terminal_receipt,status}'='not_recorded' AND descriptor#>>'{terminal_receipt,decision_hash}'=seed#>>'{decision,decision_hash}'
  AND descriptor#>>'{continuation,revision}'='2' AND descriptor#>>'{continuation,fulfilled_by}'=r2::text
  AND descriptor#>'{continuation,question}'='null'::jsonb,'parent negative remains original while current head is fulfilled');
 SELECT value INTO entry FROM jsonb_array_elements(whole->'items') WHERE value->>'event_id'='fulfillment/'||p::text||'/'||r2::text;
 PERFORM pg_temp.writer_ok(entry->'receipt'=fx#>'{fulfillment,receipt}' AND entry#>>'{child_binding,command_protocol}'='conversation.clarification.v1'
  AND entry#>>'{receipt,schema}'='conversation.meal-continuation-effect.v1' AND entry->'feedback_ref'='null'::jsonb,'actual child effect never becomes a fake v1 report or recaptured feedback');
 SELECT value INTO entry FROM jsonb_array_elements(whole->'items') WHERE value->>'event_id'='reply-result/'||p::text||'/'||r1::text;
 PERFORM pg_temp.writer_ok(entry#>>'{status}'='needs_reply' AND entry#>>'{next_question,question_key}'=partial#>>'{stored,next_question,question_key}'
  AND entry->>'at'=to_char((partial#>>'{stored,prepared_at}')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'historical next question and immutable preparation clock survive supersession');
 page:=public.read_conversation_meal_journal_page_v2(u,epoch,25,first_cursor);
 PERFORM pg_temp.writer_ok(page->>'action'='available' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(page->'items') x WHERE x->>'event_id'='fulfillment/'||p::text||'/'||r2::text),'later fulfillment does not move or invalidate an old event cursor');
 SELECT value INTO entry FROM jsonb_array_elements(whole->'items') WHERE value->>'event_id'='command/'||c1::text;
 PERFORM pg_temp.writer_ok(entry#>>'{feedback_ref,schema}'='registration.feedback.v1' AND (SELECT count(*)=2 FROM jsonb_object_keys(entry->'feedback_ref'))
  AND NOT(entry ? 'feedback') AND NOT(entry ? 'context'),'already sealed original feedback is only a bounded reference');
 PERFORM pg_temp.writer_ok((SELECT count(*)=2 FROM jsonb_array_elements(whole->'items') x WHERE x->>'kind'='edit')
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(whole->'items') x WHERE x->>'kind'='edit' AND (x->'receipt' ? 'snapshot')),'same operation UUID across commands stays unique and edits expose no snapshot');
 LOOP
  page:=public.read_conversation_meal_journal_page_v2(u,epoch,1,cursor);calls:=calls+1;IF calls>12 THEN RAISE EXCEPTION 'thread_v2_paging_loop';END IF;
  PERFORM pg_temp.writer_ok(jsonb_array_length(page->'items')=1 AND jsonb_array_length(page->'threads')=1,'each single-event page includes exactly its own descriptor '||calls::text);
  ids:=array_append(ids,page#>>'{items,0,event_id}');EXIT WHEN page->'has_more'='false'::jsonb;cursor:=page->'next_cursor';
 END LOOP;
 SELECT array_agg(x->>'event_id' ORDER BY ord) INTO expected FROM jsonb_array_elements(whole->'items') WITH ORDINALITY x(x,ord);
 PERFORM pg_temp.writer_ok(ids=expected AND cardinality(ids)=11 AND (SELECT count(DISTINCT id)=11 FROM unnest(ids) id),'tuple pagination returns exactly the full ordered event stream without duplicates or gaps');
 FOR entry IN SELECT value FROM jsonb_array_elements(whole->'items') LOOP
  IF entry->>'kind'='report' THEN PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','thread_id','status','receipt','feedback_ref']);
  ELSIF entry->>'kind'='reply' THEN PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','thread_id','child_binding','body','question']);
  ELSIF entry->>'kind'='reply_result' THEN PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','thread_id','child_binding','prepared_hash','status','next_question']);
  ELSIF entry->>'kind'='fulfillment' THEN PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','thread_id','child_binding','receipt','feedback_ref']);
  ELSIF entry->>'kind'='edit' THEN PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','thread_id','effect_binding','receipt']);
  ELSE RAISE EXCEPTION 'unknown_thread_event';END IF;
  PERFORM pg_temp.writer_ok(entry->>'at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$','canonical event microseconds '||(entry->>'event_id'));
 END LOOP;
 PERFORM pg_temp.writer_ok(NOT(whole::text ~ '"(clinical|context|original_facts|feedback_context|before_items|after_items|before_group|after_group|current_state|processing_result|signed_url|semantic|provider_metadata|source_hash|source_receipts)"[[:space:]]*:'),'compact page contains no private context/model/nutrition/audit bodies');
 PERFORM pg_temp.writer_ok(pg_temp.semantic_owner_state(u)=before_state,'all page reads including feedback refs have zero data/progress/source/cursor effects');
 PERFORM pg_temp.writer_ok((SELECT jsonb_array_length(public.read_conversation_meal_journal_page(u,epoch,25)->'items')=6)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.read_conversation_meal_journal_page(u,epoch,25)->'items') x WHERE x#>>'{command,command_protocol}'<>'conversation.command.v1'),'old v1 stream and strict decoder protocol remain unchanged');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,(other_seed#>>'{terminal,epoch}')::uuid)='{"action":"stale_epoch"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(whole->'threads') x WHERE x#>>'{parent_binding,owner_id}'<>u::text),'foreign owner epoch and descriptors never leak');
 -- Structurally allowed but malformed synthetic audit receipt; no immutable
 -- row is updated. The reader must refuse it rather than publish 12/13 keys.
 bad_clock:=clock_timestamp();
 SELECT jsonb_set(jsonb_set(jsonb_set(o.receipt-'revision','{operation_id}',to_jsonb(bad_op)),'{input_hash}',to_jsonb(repeat('d',64))),'{applied_at}',to_jsonb(bad_clock))
 INTO bad_receipt FROM private.conversation_meal_edit_operations o WHERE user_id=u AND command_id=c1 AND operation_id=op;
 INSERT INTO private.conversation_meal_edit_ids VALUES(u,c1,bad_op,epoch,repeat('d',64),'save',bad_clock);
 INSERT INTO private.conversation_meal_edit_operations VALUES(u,c1,bad_op,bad_receipt,'[]','[]','[]','[]',bad_clock);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,epoch)='{"action":"event_conflict"}'::jsonb,'malformed selected audit cannot become a falsely qualified public receipt');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,epoch,25,cursor)='{"action":"stale_epoch"}'::jsonb
  AND (SELECT count(*)=6 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_meal_command_ids WHERE user_id=u),'reset wins over historical cursor, preserving all UUID tombstones');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS thread_page_v2_assertions FROM meal_writer_assertions;
ROLLBACK;

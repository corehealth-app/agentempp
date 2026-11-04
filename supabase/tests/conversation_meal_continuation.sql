-- RED must be executed on the exact owned PG before installing the migration.
-- This file is source-only until the parent explicitly hands over that runtime.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN IF to_regprocedure('public.read_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text)') IS NULL THEN
 RAISE EXCEPTION 'CONTINUATION_RED:missing_linked_continuation';END IF;END $$;
\ir fixtures/conversation_meal_continuation_fixture.sql
DO $test$
DECLARE u uuid:='c3c10000-0000-4000-8000-000000000001';a uuid:='c3c10000-0000-4000-8000-000000000002';
 c uuid:='c3c10000-0000-4000-8000-000000000003';r uuid:='c3c10000-0000-4000-8000-000000000004';
 other_r uuid:='c3c10000-0000-4000-8000-000000000005';seed jsonb;state jsonb;body jsonb;v jsonb;again jsonb;before_state jsonb;parent_before jsonb;rejected boolean;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,c);before_state:=pg_temp.semantic_owner_state(u);
 state:=pg_temp.continuation_read(u,c,seed);
 PERFORM pg_temp.writer_ok(state->>'action'='available' AND state#>>'{head,question,kind}'='quantity'
  AND state#>>'{head,question,food_index}'='0' AND state#>>'{head,question,food_name}'='arroz'
  AND state#>'{head,question,allowed_units}'='["g","kg"]'::jsonb AND state#>'{head,answers}'='[]'::jsonb
  AND state->'fulfillment'='null'::jsonb AND state->'reply'='null'::jsonb,'actual original missing occurrence produces one source-bound question');
 PERFORM pg_temp.writer_ok(pg_temp.semantic_owner_state(u)=before_state,'question read has zero effects including no head initialization');
 parent_before:=state->'parent';body:=pg_temp.continuation_body(state,'{"kind":"quantity","food_index":0,"amount":100,"unit":"g"}');
 v:=pg_temp.continuation_admit(u,c,seed,r,body);
 PERFORM pg_temp.writer_ok(v->>'action'='admitted' AND v#>>'{child_binding,command_id}'=r::text
  AND v#>>'{child_binding,command_protocol}'='conversation.clarification.v1' AND v#>>'{child_binding,kind}'='meal.clarify'
  AND v#>'{source,context,source_input}'=body AND v#>>'{source,context,parent,decision_hash}'=seed#>>'{decision,decision_hash}'
  AND v#>>'{source,context,authority,context,command_id}'=c::text,'reply has its own permanent identity and a distinct bound authority source');
 PERFORM pg_temp.writer_ok(v#>>'{child_binding,input_hash}'=encode(sha256(convert_to('{"answer":{"amount":100,"food_index":0,"kind":"quantity","unit":"g"},"expected_revision":0,"question_key":'||to_jsonb(state#>>'{head,question,question_key}')::text||',"schema":"conversation.meal-clarification.v1"}','UTF8')),'hex'),'reply body hash uses SQL canonical decimal JSON');
 before_state:=pg_temp.semantic_owner_state(u);again:=pg_temp.continuation_admit(u,c,seed,r,body);
 PERFORM pg_temp.writer_ok(again=jsonb_set(v,'{action}','"replay"') AND pg_temp.semantic_owner_state(u)=before_state,'lost admission response recovers one exact child source without another identity');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_read(u,c,seed,r,v#>>'{child_binding,input_hash}')#>'{parent}'=parent_before,'reply never mutates parent model source or terminal decision');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,c,seed,r,jsonb_set(body,'{answer,amount}','101'))='{"action":"input_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'same reply UUID changed body cannot replace original');
 rejected:=false;BEGIN PERFORM pg_temp.continuation_admit(u,c,seed,other_r,body||'{"unexpected":true}');EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
 PERFORM pg_temp.writer_ok(rejected AND pg_temp.semantic_owner_state(u)=before_state,'closed reply rejects unknown keys without an identity');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,c,seed,other_r,jsonb_set(body,'{question_key}',to_jsonb(repeat('0',64))))='{"action":"question_conflict"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=other_r),'foreign question is not an unbound new-meal bypass');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_semantic_attempts WHERE user_id=u AND command_id=r)
  AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE user_id=u),'reply admission never creates a fake provider attempt or food effect');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(u,(seed#>>'{terminal,epoch}')::uuid)->'items' @> jsonb_build_array(jsonb_build_object('event_id','command/'||c::text))
  AND jsonb_array_length(public.read_conversation_meal_journal_page(u,(seed#>>'{terminal,epoch}')::uuid)->'items')=1,'v1 journal filters linked children instead of breaking closed v1 decoding');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_read(u,c,seed)='{"action":"stale_epoch"}'::jsonb
  AND pg_temp.continuation_admit(u,c,seed,r,body)='{"action":"stale_epoch"}'::jsonb,'reset precedes all old parent and child replay');
 PERFORM pg_temp.writer_ok((SELECT count(*)=2 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_meal_command_ids WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_sources WHERE user_id=u),'reset erases bodies and sources but preserves both permanent UUID tombstones');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS continuation_assertions FROM meal_writer_assertions;
ROLLBACK;

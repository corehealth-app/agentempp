BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN IF to_regprocedure('public.commit_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text,text)') IS NULL THEN
 RAISE EXCEPTION 'CONTINUATION_WRITER_RED:missing_linked_writer';END IF;END $$;
\ir fixtures/conversation_meal_continuation_fixture.sql
DO $test$
DECLARE u uuid:='c3c20000-0000-4000-8000-000000000001';a uuid:='c3c20000-0000-4000-8000-000000000002';
 c uuid:='c3c20000-0000-4000-8000-000000000003';r1 uuid:='c3c20000-0000-4000-8000-000000000004';r2 uuid:='c3c20000-0000-4000-8000-000000000005';
 losing uuid:='c3c20000-0000-4000-8000-000000000006';seed jsonb;state jsonb;body jsonb;admit1 jsonb;admit2 jsonb;loser jsonb;prep1 jsonb;prep2 jsonb;ready jsonb;fx jsonb;
 before_state jsonb;parent_before jsonb;rejected boolean;sid uuid;legacy_pending uuid:=gen_random_uuid();old_count bigint;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,c);state:=pg_temp.continuation_read(u,c,seed);parent_before:=state->'parent';
 body:=pg_temp.continuation_body(state,'{"kind":"quantity","food_index":0,"amount":100,"unit":"g"}');
 admit1:=pg_temp.continuation_admit(u,c,seed,r1,body);
 state:=pg_temp.continuation_read(u,c,seed,r1,admit1#>>'{child_binding,input_hash}');
 prep1:=pg_temp.continuation_preparation(state,false);
 ready:=pg_temp.continuation_prepare(u,c,seed,r1,admit1#>>'{child_binding,input_hash}',prep1);
 PERFORM pg_temp.writer_ok(ready->>'action'='prepared' AND ready#>>'{head,revision}'='1' AND ready#>>'{head,question,kind}'='meal_type'
  AND ready#>'{head,answers,0,answer}'=body->'answer' AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'quantity reply preserves its fact and advances one linked question without any meal effect');
 before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_prepare(u,c,seed,r1,admit1#>>'{child_binding,input_hash}',prep1)=jsonb_set(ready,'{action}','"replay"')
  AND pg_temp.semantic_owner_state(u)=before_state,'lost partial preparation response replays immutable next question with no second advancement');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r1,admit1#>>'{child_binding,input_hash}',ready#>>'{stored,prepared_hash}')='{"action":"question_conflict"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE user_id=u),'partial accepted reply is never an implicit food registration');
 state:=pg_temp.continuation_read(u,c,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 admit2:=pg_temp.continuation_admit(u,c,seed,r2,body);loser:=pg_temp.continuation_admit(u,c,seed,losing,body);
 state:=pg_temp.continuation_read(u,c,seed,r2,admit2#>>'{child_binding,input_hash}');prep2:=pg_temp.continuation_preparation(state);
 ready:=pg_temp.continuation_prepare(u,c,seed,r2,admit2#>>'{child_binding,input_hash}',prep2);
 PERFORM pg_temp.writer_ok(ready->>'action'='prepared' AND ready#>'{stored,next_question}'='null'::jsonb AND ready#>>'{head,revision}'='1','final preparation seals nutrition but does not fulfill the parent early');
 -- A legacy caller must not turn the linked preparation into an old v1 event.
 before_state:=pg_temp.semantic_owner_state(u);rejected:=false;
 BEGIN PERFORM public.commit_conversation_meal(u,r2,ready#>>'{stored,prepared_hash}');EXCEPTION WHEN OTHERS THEN rejected:=true;END;
 PERFORM pg_temp.writer_ok(rejected AND pg_temp.semantic_owner_state(u)=before_state,'old writer refuses a linked child atomically');
 fx:=pg_temp.continuation_commit(u,c,seed,r2,admit2#>>'{child_binding,input_hash}',ready#>>'{stored,prepared_hash}');
 PERFORM pg_temp.writer_ok(fx->>'action'='committed' AND fx#>>'{fulfillment,receipt,schema}'='conversation.meal-continuation-effect.v1'
  AND fx#>>'{fulfillment,receipt,command_id}'=r2::text AND fx#>>'{fulfillment,receipt,parent_command_id}'=c::text
  AND fx#>>'{fulfillment,receipt,parent_decision_hash}'=seed#>>'{decision,decision_hash}'
  AND fx#>>'{fulfillment,receipt,provider_key}'='conversation.clarification/'||u::text||'/'||c::text,'actual writer publishes a child effect and unique parent fulfillment together');
 SELECT snapshot_id INTO sid FROM public.meal_logs WHERE user_id=u;
 PERFORM pg_temp.writer_ok((SELECT count(*)=1 FROM public.meal_logs WHERE user_id=u) AND (SELECT count(*)=1 FROM public.pending_registrations WHERE user_id=u AND status='confirmed')
  AND (SELECT calories_target IS NULL AND protein_target IS NULL AND calories_consumed=130 FROM public.daily_snapshots WHERE id=sid)
  AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u),'real first-day write preserves NULL targets and has no XP/block/progress side effect');
 state:=pg_temp.continuation_read(u,c,seed,r2,admit2#>>'{child_binding,input_hash}');
 PERFORM pg_temp.writer_ok(state->'parent'=parent_before AND state#>>'{reply,state}'='saved' AND state#>'{reply,receipt}'=fx#>'{fulfillment,receipt}'
  AND state->'fulfillment'=fx->'fulfillment' AND state#>>'{head,revision}'='2','parent proof remains original and read recovers actual immutable child outcome');
 before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r2,admit2#>>'{child_binding,input_hash}','obsolete')=jsonb_set(fx,'{action}','"replay"')
  AND pg_temp.semantic_owner_state(u)=before_state,'lost commit response replays first winner before obsolete prepared hash with no domain repeat');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,losing,loser#>>'{child_binding,input_hash}',ready#>>'{stored,prepared_hash}')='{"action":"question_conflict"}'::jsonb
  AND pg_temp.continuation_read(u,c,seed,losing,loser#>>'{child_binding,input_hash}')#>>'{reply,state}'='superseded','a second bound reply cannot fulfill the same parent twice or inherit another UUID ACK');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=u AND command_id=c)
  AND (SELECT count(*)=1 FROM private.conversation_meal_semantic_attempts WHERE user_id=u),'no fake parent effect or extra physical semantic invocation');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(legacy_pending,u,'pending','{"kind":"meal","legacy":true}',clock_timestamp()+interval '1 hour');
 PERFORM pg_temp.writer_ok(EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=legacy_pending AND status='pending'),'unrelated legacy pending admission remains unchanged');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r2,admit2#>>'{child_binding,input_hash}',ready#>>'{stored,prepared_hash}')='{"action":"stale_epoch"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_fulfillments WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_continuation_heads WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_replies WHERE user_id=u),'reset scrubs health lineage and blocks old completed-child replay');
 PERFORM pg_temp.writer_ok((SELECT count(*)=4 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_meal_command_ids WHERE user_id=u)
  AND (SELECT count(*)=3 FROM private.conversation_meal_reply_ids WHERE user_id=u),'permanent child identity/link prevents UUID reacquisition after reset');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS continuation_writer_assertions FROM meal_writer_assertions;
ROLLBACK;

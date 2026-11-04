BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN IF to_regprocedure('public.seal_conversation_meal_decision(uuid,uuid,uuid,text,text,uuid,text,jsonb)') IS NULL THEN
 RAISE EXCEPTION 'DECISION_RED:missing_durable_decision';END IF;END $$;
\ir fixtures/conversation_meal_decision_fixture.sql
DO $decision$
DECLARE u uuid:='c3de0000-0000-4000-8000-000000000001';a uuid:='c3de0000-0000-4000-8000-000000000002';c uuid:='c3de0000-0000-4000-8000-000000000003';
 second_c uuid:='c3de0000-0000-4000-8000-000000000004';third_c uuid:='c3de0000-0000-4000-8000-000000000005';seed jsonb;other_seed jsonb;third_seed jsonb;v jsonb;before_state jsonb;after_state jsonb;refused boolean;payload jsonb;
BEGIN
 seed:=pg_temp.decision_seed(u,a,c);before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_decision(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}')='{"action":"absent"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'decision read absent has no effect');
 v:=pg_temp.decision_seal(u,c,seed);
 PERFORM pg_temp.writer_ok(v->>'action'='sealed' AND v#>>'{decision,status}'='not_recorded' AND v#>>'{decision,reason}'='meal_type_required'
  AND v#>>'{command,epoch}'=seed#>>'{terminal,epoch}' AND v#>>'{command,input_hash}'=seed#>>'{terminal,input_hash}'
  AND v#>>'{decision,attempt_id}'=seed#>>'{terminal,attempt_id}' AND v#>>'{decision,semantic_result_hash}'=seed#>>'{terminal,result_hash}','seal binds actual completed semantic source and original command');
 PERFORM pg_temp.writer_ok(v#>>'{decision,decision_hash}'=encode(sha256(convert_to('{"food_indexes":[],"reason":"meal_type_required","schema":"conversation.meal-decision.v1","status":"not_recorded"}','UTF8')),'hex'),'decision hash matches independent literal canonical JSON');
 after_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.decision_seal(u,c,seed)=jsonb_set(v,'{action}','"replay"') AND pg_temp.semantic_owner_state(u)=after_state,'first decision exact replay immutable');
 PERFORM pg_temp.writer_ok(pg_temp.decision_seal(u,c,seed,pg_temp.decision_payload('nutrition_unresolved'))='{"action":"decision_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=after_state,'changed decision never replaces winner');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_decision(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}')=jsonb_set(v,'{action}','"available"')
  AND pg_temp.semantic_owner_state(u)=after_state,'read recovers exact sealed decision without reinterpretation');
 refused:=false;BEGIN UPDATE private.conversation_meal_decisions SET decision=pg_temp.decision_payload('changed') WHERE user_id=u AND command_id=c;
 EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_meal_decision_immutable';END;
 PERFORM pg_temp.writer_ok(refused,'winner payload cannot be updated even by table owner');
 refused:=false;BEGIN DELETE FROM private.conversation_meal_decisions WHERE user_id=u AND command_id=c;
 EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_meal_decision_immutable';END;
 PERFORM pg_temp.writer_ok(refused,'winner cannot be deleted outside source or account cascade');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_decision(u,c,gen_random_uuid(),seed#>>'{terminal,input_hash}')='{"action":"stale_epoch"}'::jsonb
  AND public.read_conversation_meal_decision(u,c,(seed#>>'{terminal,epoch}')::uuid,repeat('f',64))='{"action":"input_conflict"}'::jsonb,'read expected original epoch and hash fenced');
 refused:=false;BEGIN PERFORM public.prepare_conversation_meal(u,c,pg_temp.writer_resolved(seed->'source'));
 EXCEPTION WHEN serialization_failure THEN refused:=SQLERRM='conversation_meal_terminal_decision';END;
 PERFORM pg_temp.writer_ok(refused AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=u AND command_id=c)
  AND pg_temp.semantic_owner_state(u)=after_state,'sealed decision prevents preparation before any domain effect');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(u,c,repeat('a',64))='{"action":"resolved_required"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=after_state,'sealed decision cannot reach a domain writer');
 other_seed:=pg_temp.decision_seed(u,a,second_c,false);
 FOREACH payload IN ARRAY ARRAY[
  pg_temp.decision_payload()||'{"unexpected":true}',pg_temp.decision_payload('UPPER'),pg_temp.decision_payload(repeat('a',81)),
  pg_temp.decision_payload('valid','[0,0]'),pg_temp.decision_payload('valid','[30]'),pg_temp.decision_payload('valid','[-1]'),
  pg_temp.decision_payload('valid','[0.5]'),pg_temp.decision_payload('valid','null'),pg_temp.decision_payload('valid','{}')
 ] LOOP
  before_state:=pg_temp.semantic_owner_state(u);refused:=false;
  BEGIN PERFORM pg_temp.decision_seal(u,second_c,other_seed,payload);EXCEPTION WHEN invalid_parameter_value THEN refused:=true;END;
  PERFORM pg_temp.writer_ok(refused AND pg_temp.semantic_owner_state(u)=before_state,'reject closed malformed decision '||payload::text);
 END LOOP;
 before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.seal_conversation_meal_decision(u,second_c,(other_seed#>>'{terminal,epoch}')::uuid,other_seed#>>'{terminal,input_hash}',repeat('f',64),
  (other_seed#>>'{terminal,attempt_id}')::uuid,other_seed#>>'{terminal,result_hash}',pg_temp.decision_payload())='{"action":"source_conflict"}'::jsonb,'caller source hash cannot override actual capture');
 PERFORM pg_temp.writer_ok(public.seal_conversation_meal_decision(u,second_c,(other_seed#>>'{terminal,epoch}')::uuid,other_seed#>>'{terminal,input_hash}',other_seed#>>'{terminal,source_hash}',
  (seed#>>'{terminal,attempt_id}')::uuid,other_seed#>>'{terminal,result_hash}',pg_temp.decision_payload())='{"action":"semantic_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'attempt identity cannot be borrowed from another command');
 PERFORM public.prepare_conversation_meal(u,second_c,pg_temp.writer_resolved(other_seed->'source'));
 before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.decision_seal(u,second_c,other_seed)='{"action":"resolved_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'prepared nutrition authority wins over a later decision');
 third_seed:=pg_temp.decision_seed(u,a,third_c,false);
 UPDATE public.users SET timezone='Pacific/Kiritimati' WHERE id=u;
 v:=pg_temp.decision_seal(u,third_c,third_seed);
 PERFORM pg_temp.writer_ok(v->>'action'='sealed' AND pg_temp.decision_seal(u,third_c,third_seed)=jsonb_set(v,'{action}','"replay"')
  AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),'completed original attempt seals and replays without live timezone or day recapture');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_decision(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}')='{"action":"stale_epoch"}'::jsonb
  AND pg_temp.decision_seal(u,c,seed)='{"action":"stale_epoch"}'::jsonb,'reset before every old decision replay');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_decisions WHERE user_id=u)
  AND (SELECT count(*)=3 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_meal_command_ids WHERE user_id=u),'reset scrubs decision and retains permanent UUID tombstones');
END $decision$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS durable_decision_assertions FROM meal_writer_assertions;
ROLLBACK;

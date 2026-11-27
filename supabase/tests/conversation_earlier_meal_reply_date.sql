BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_continuation_fixture.sql

DO $test$
DECLARE
  u uuid:=gen_random_uuid();
  e uuid:=gen_random_uuid();
  intake uuid:=gen_random_uuid();
  reply_id uuid:=gen_random_uuid();
  today date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
  source_input jsonb;
  admission jsonb;
  capture jsonb;
  claim jsonb;
  selection jsonb;
  parent_id uuid;
  model jsonb;
  terminal jsonb;
  decision jsonb;
  seed jsonb;
  pending jsonb;
  body jsonb;
  answer jsonb;
BEGIN
  INSERT INTO public.users(id,email,status,timezone,country,country_confirmed)
    VALUES(u,'earlier-reply@example.invalid','active','America/Sao_Paulo','BR',true);
  INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
    VALUES(u,e,clock_timestamp());
  INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target)
    VALUES(u,today-1,1700,110);
  source_input:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',intake,
    'meal_type_hint','almoco','source',jsonb_build_object('channel','text','text','Ontem comi arroz'));
  admission:=public.admit_conversation_intake(u,e,source_input);
  capture:=public.capture_conversation_intake_source(u,intake,admission#>>'{intake,input_hash}',e);
  claim:=public.claim_conversation_intake_routing(u,intake,admission#>>'{intake,input_hash}',e,capture->>'source_hash');
  selection:=public.seal_conversation_intake_routing(u,intake,admission#>>'{intake,input_hash}',e,
    capture->>'source_hash',(claim->>'claim_id')::uuid,
    '{"schema":"conversation.intake-routing.v1","kind":"meal.report","reason":"verified_meal_yesterday"}');
  parent_id:=(selection#>>'{selection,command,command_id}')::uuid;
  capture:=public.capture_conversation_meal_source(u,parent_id);
  claim:=public.start_conversation_meal_semantic_attempt(u,parent_id,'conversation.meal-interpreter.v1',
    capture->>'source_hash');
  model:=pg_temp.semantic_result(claim);
  model:=jsonb_set(model,'{foods}',
    '[{"index":0,"name":{"unit":"command_text","start":11,"end":16},"quantity":null,"unit":null,"visual_index":null}]');
  model:=jsonb_set(model,'{sources,0,spans}',
    '[{"start":0,"end":10,"kind":"report","food_index":null},{"start":10,"end":11,"kind":"separator","food_index":null},{"start":11,"end":16,"kind":"food","food_index":0}]');
  terminal:=public.commit_conversation_meal_semantic_result(u,parent_id,'conversation.meal-interpreter.v1',
    (claim->>'attempt_id')::uuid,model);
  decision:=public.seal_conversation_meal_decision(u,parent_id,e,terminal->>'input_hash',capture->>'source_hash',
    (terminal->>'attempt_id')::uuid,terminal->>'result_hash',pg_temp.decision_payload('missing_quantity','[0]'));
  seed:=jsonb_build_object('terminal',terminal,'decision',decision->'decision');
  pending:=pg_temp.continuation_read(u,parent_id,seed);
  PERFORM pg_temp.writer_ok(pending->>'action'='available'
    AND pending#>>'{head,question,kind}'='quantity','the historical report keeps its concrete quantity question');
  body:=pg_temp.continuation_body(pending,'{"kind":"quantity","food_index":0,"amount":100,"unit":"g"}');
  answer:=pg_temp.continuation_admit(u,parent_id,seed,reply_id,body);
  PERFORM pg_temp.writer_ok(answer->>'action'='admitted'
    AND answer#>>'{source,context,authority,context,day,date}'=(today-1)::text
    AND answer#>>'{source,context,authority,context,day,calories_target}'='1700',
    'an answer inherits the original day and its targets, even though it is written today');
  PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,parent_id,seed,reply_id,body)
    =jsonb_set(answer,'{action}','"replay"')
    AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u),
    'replaying an answer keeps one linked preparation and creates no confirmed meal yet');
END $test$;

SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS earlier_meal_reply_date_assertions FROM meal_writer_assertions;
ROLLBACK;

-- Requires the complete unified-journal substrate, including neutral intake tables.
-- Transaction-owned synthetic photo. No image/provider/user account is reused.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
CREATE TEMP TABLE r204_name_read_samples(name text,payload jsonb);
\ir fixtures/conversation_meal_continuation_fixture.sql
-- Reuse the existing complete media fixture, changing only the test food and
-- the real sealed refusal that this regression must make recoverable.
DO $fixture$
DECLARE original text;changed text;
BEGIN
 original:=pg_get_functiondef('pg_temp.continuation_media_seed(uuid,uuid,uuid,uuid,text)'::regprocedure);
 changed:=replace(original,'continuation_media_seed','continuation_name_media_seed');
 changed:=replace(changed,'"name":"arroz"','"name":"alimento do buffet"');
 changed:=replace(changed,'pg_temp.decision_payload(CASE kind WHEN ''audio_note'' THEN ''missing_quantity'' ELSE ''meal_type_required'' END,CASE kind WHEN ''audio_note'' THEN ''[0]''::jsonb ELSE ''[]''::jsonb END)',
  'pg_temp.decision_payload(''unqualified_whole_name'',''[0]''::jsonb)');
 IF changed=original OR position('pg_temp.decision_payload(''unqualified_whole_name''' IN changed)=0 THEN RAISE EXCEPTION 'name_fixture_source_changed';END IF;
 EXECUTE changed;
END $fixture$;
DO $test$
DECLARE u uuid:='c2040000-0000-4000-8000-000000000001';a uuid:='c2040000-0000-4000-8000-000000000002';
 c uuid:='c2040000-0000-4000-8000-000000000003';r uuid:='c2040000-0000-4000-8000-000000000004';
 asset uuid:='c2040000-0000-4000-8000-000000000005';wrong uuid:='c2040000-0000-4000-8000-000000000006';
 legacy uuid:='c2040000-0000-4000-8000-000000000007';old_page jsonb;new_page jsonb;
 seed jsonb;state jsonb;body jsonb;admitted jsonb;after_read jsonb;original_parent jsonb;
BEGIN
 seed:=pg_temp.continuation_name_media_seed(u,a,c,asset,'meal_photo');
 state:=pg_temp.continuation_read(u,c,seed);original_parent:=state->'parent';
 PERFORM pg_temp.continuation_seed(u,a,legacy,true,false);
 old_page:=public.read_conversation_meal_journal_page_v2(u,(seed#>>'{terminal,epoch}')::uuid,25,NULL);
 new_page:=public.read_conversation_meal_journal_page_v3(u,(seed#>>'{terminal,epoch}')::uuid,25,NULL);
 PERFORM pg_temp.writer_ok(old_page->>'action'='available' AND new_page->>'action'='available'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(old_page->'threads') t WHERE t->>'thread_id'=c::text AND t->'continuation'='null'::jsonb)
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(new_page->'threads') t WHERE t->>'thread_id'=c::text AND t#>>'{continuation,question,kind}'='food_name'),
  'legacy reader retains the original refusal without an unknown kind; versioned reader exposes the actionable name question');
 INSERT INTO r204_name_read_samples VALUES('legacy_before',old_page),('current_before',new_page);

 PERFORM pg_temp.writer_ok(state->>'action'='available' AND state#>>'{head,question,kind}'='food_name'
  AND state#>>'{head,question,food_name}'='alimento do buffet','photo refusal offers its own original item-name question');
 body:=pg_temp.continuation_body(state,'{"kind":"food_name","food_index":0,"name":"pão francês"}');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,c,seed,wrong,jsonb_set(body,'{answer,food_index}','1'))='{"action":"question_conflict"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=wrong),'name answer cannot substitute another item');
 admitted:=pg_temp.continuation_admit(u,c,seed,r,body);
 PERFORM pg_temp.writer_ok(admitted->>'action'='admitted','explicit corrected name enters the existing bound answer chain');
 old_page:=public.read_conversation_meal_journal_page_v2(u,(seed#>>'{terminal,epoch}')::uuid,25,NULL);
 new_page:=public.read_conversation_meal_journal_page_v3(u,(seed#>>'{terminal,epoch}')::uuid,25,NULL);
 PERFORM pg_temp.writer_ok(old_page->>'action'='available' AND jsonb_array_length(old_page->'threads')=1
  AND old_page#>>'{threads,0,thread_id}'=legacy::text AND old_page#>>'{threads,0,continuation,question,kind}'='quantity'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(old_page->'items') e WHERE e->>'thread_id'=c::text)
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(new_page->'items') e WHERE e->>'thread_id'=c::text AND e#>>'{body,answer,kind}'='food_name'),
  'legacy pagination preserves its supported conversation; new name-answer events are read only through the versioned reader');
 INSERT INTO r204_name_read_samples VALUES('legacy_after',old_page),('current_after',new_page);

 old_page:=public.read_conversation_journal_page_v3(u,(seed#>>'{terminal,epoch}')::uuid,25,NULL);
 PERFORM pg_temp.writer_ok(old_page->>'action'='available'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(old_page#>'{meal_page,threads}') t WHERE t->>'thread_id'=c::text),
  'legacy unified reader filters unsupported name threads before pagination');
 new_page:=public.read_conversation_journal_page_v4(u,(seed#>>'{terminal,epoch}')::uuid,25,NULL);
 PERFORM pg_temp.writer_ok(new_page->>'action'='available'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(new_page#>'{meal_page,items}') t WHERE t#>>'{body,answer,kind}'='food_name'),
  'versioned unified reader preserves the complete name-answer history');

 after_read:=pg_temp.continuation_read(u,c,seed,r,admitted#>>'{child_binding,input_hash}');
 PERFORM pg_temp.writer_ok(after_read->'parent'=original_parent,'original image observation, quantity, semantics and refusal remain immutable');
 PERFORM pg_temp.writer_ok(after_read#>>'{reply,source,context,answer_chain,0,answer,name}'='pão francês'
  AND EXISTS(SELECT 1 FROM private.conversation_meal_replies
   WHERE user_id=u AND reply_id=r AND question=state#>'{head,question}')
  AND after_read#>>'{reply,body,question_key}'=state#>>'{head,question,question_key}',
  'correction is auditable and bound to the precise original question');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,c,seed,r,body)->>'action'='replay','technical retry reuses the same original answer');
 PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,c,seed,r,jsonb_set(body,'{answer,name}','"feijão"'))->>'action'='input_conflict','same answer identity cannot silently change food');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=u),'asking and accepting a name alone never fabricates consumption or XP');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_semantic_attempts WHERE user_id=u AND command_id=r),'corrected name does not rerun image interpretation');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT jsonb_build_object('assertions',(SELECT count(*) FROM meal_writer_assertions),'samples',(SELECT jsonb_object_agg(name,payload) FROM r204_name_read_samples)) AS name_clarification_evidence;
ROLLBACK;

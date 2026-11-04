BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN IF to_regprocedure('public.read_conversation_meal_journal_page(uuid,uuid,integer,jsonb)') IS NULL THEN
 RAISE EXCEPTION 'JOURNAL_PAGE_RED:missing_page';END IF;END $$;
\ir fixtures/conversation_meal_decision_fixture.sql
CREATE FUNCTION pg_temp.page_admit(u uuid,c uuid,at_clock timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE raw jsonb:=pg_temp.writer_input(c);epoch uuid;
BEGIN
 SELECT a.epoch INTO epoch FROM private.workout_strength_authority_epochs a WHERE user_id=u;
 -- Fixed synthetic server event ties; never UPDATE an immutable identity.
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
 VALUES(u,c,encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex'),'conversation.command.v1','meal.report',epoch,at_clock);
 INSERT INTO private.conversation_meal_command_sources VALUES(u,c,raw);
END $$;
CREATE FUNCTION pg_temp.page_register(u uuid,c uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb;r jsonb;
BEGIN s:=public.capture_conversation_meal_source(u,c);r:=public.prepare_conversation_meal(u,c,pg_temp.writer_resolved(s));
 RETURN public.commit_conversation_meal(u,c,r->>'resolved_hash')->'receipt';END $$;
CREATE FUNCTION pg_temp.page_save(u uuid,c uuid,op uuid,anchor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE state jsonb:=public.read_conversation_meal_edit_state(u,c);input jsonb;
BEGIN
 input:=jsonb_build_object('schema','conversation.meal-edit.v1','kind','save','expected_revision',0,'expected_version','v1:'||repeat('a',64),
  'record_id',anchor,'items',jsonb_build_array(jsonb_build_object('food_name','arroz sintetico','quantity_g',200)));
 RETURN public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',
  '[{"food_name":"arroz sintetico","quantity_g":200,"kcal":260.1,"protein_g":4.62,"carbs_g":56.42,"fat_g":0.42,"source":"user_kcal","food_db_id":null,"confidence":null}]',
  'quantity_only','{"quantity_g":200}','synthetic-page-edit')->'receipt';
END $$;
DO $page$
DECLARE u uuid:='c3dc0000-0000-4000-8000-000000000001';a uuid:='c3dc0000-0000-4000-8000-000000000002';
 foreign_u uuid:='c3dc0000-0000-4000-8000-000000000003';foreign_a uuid:='c3dc0000-0000-4000-8000-000000000004';
 c1 uuid:='c3dc0000-0000-4000-8000-000000000101';c2 uuid:='c3dc0000-0000-4000-8000-000000000102';c3 uuid:='c3dc0000-0000-4000-8000-000000000103';c4 uuid:='c3dc0000-0000-4000-8000-000000000104';
 foreign_c uuid:='c3dc0000-0000-4000-8000-000000000201';op uuid:='c3dc0000-0000-4000-8000-000000000301';epoch uuid:=gen_random_uuid();foreign_epoch uuid:=gen_random_uuid();tie timestamptz:=clock_timestamp()-interval '1 hour';
 source jsonb;fx1 jsonb;fx2 jsonb;ed1 jsonb;ed2 jsonb;decision jsonb;page jsonb;whole jsonb;cursor jsonb;entry jsonb;before_state jsonb;after_state jsonb;ids text[]:='{}';expected text[];refused boolean;at_before text;count_pages integer:=0;
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id IN(u,foreign_u)) OR EXISTS(SELECT 1 FROM auth.users WHERE id IN(a,foreign_a)) THEN RAISE EXCEPTION 'page_fixture_collision';END IF;
 INSERT INTO auth.users(id) VALUES(a),(foreign_a);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed) VALUES
  (u,a,'page-a@example.invalid','active','UTC','BR',true),(foreign_u,foreign_a,'page-b@example.invalid','active','UTC','BR',true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(u,epoch)='{"action":"stale_epoch"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u),'page never initializes an absent epoch');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,epoch,clock_timestamp()),(foreign_u,foreign_epoch,clock_timestamp());
 PERFORM pg_temp.page_admit(u,c1,tie);PERFORM pg_temp.page_admit(u,c2,tie);PERFORM pg_temp.page_admit(u,c3,tie);PERFORM pg_temp.page_admit(foreign_u,foreign_c,tie);
 fx1:=pg_temp.page_register(u,c1);fx2:=pg_temp.page_register(u,c2);source:=pg_temp.decision_seed(u,a,c4,false);decision:=pg_temp.decision_seal(u,c4,source)->'decision';
 ed1:=pg_temp.page_save(u,c1,op,(fx1#>>'{log_ids,0}')::uuid);ed2:=pg_temp.page_save(u,c2,op,(fx2#>>'{log_ids,0}')::uuid);
 expected:=ARRAY['edit/'||c2::text||'/'||op::text,'edit/'||c1::text||'/'||op::text,'command/'||c4::text,'command/'||c3::text,'command/'||c2::text,'command/'||c1::text];
 before_state:=pg_temp.semantic_owner_state(u);
 LOOP
  page:=public.read_conversation_meal_journal_page(u,epoch,1,cursor);count_pages:=count_pages+1;
  IF count_pages>8 THEN RAISE EXCEPTION 'page_did_not_terminate';END IF;
  PERFORM pg_temp.writer_ok(page->>'action'='available' AND page->>'owner_id'=u::text AND page->>'epoch'=epoch::text,'page actual owner epoch '||count_pages::text);
  PERFORM pg_temp.writer_ok(jsonb_array_length(page->'items')=1,'page exact limit '||count_pages::text);
  entry:=page#>'{items,0}';ids:=array_append(ids,entry->>'event_id');
  PERFORM pg_temp.writer_ok(entry#>>'{command,owner_id}'=u::text AND entry#>>'{command,epoch}'=epoch::text,'entry actual current owned binding '||count_pages::text);
  IF (page->>'has_more')::boolean THEN
   PERFORM pg_temp.writer_ok(page->'next_cursor'=jsonb_build_object('at',entry->'at','id',entry->'event_id'),'cursor uses last returned event '||count_pages::text);
   cursor:=page->'next_cursor';
  ELSE PERFORM pg_temp.writer_ok(page->'next_cursor'='null'::jsonb,'last page has no cursor');EXIT;END IF;
 END LOOP;
 PERFORM pg_temp.writer_ok(ids=expected AND cardinality(ids)=6 AND (SELECT count(DISTINCT x)=6 FROM unnest(ids) x),'keyset ties no skip duplicate and operation IDs scoped by command');
 whole:=public.read_conversation_meal_journal_page(u,epoch);
 PERFORM pg_temp.writer_ok(jsonb_array_length(whole->'items')=6 AND NOT(whole->>'has_more')::boolean AND pg_temp.semantic_owner_state(u)=before_state,'default page ten and every read have zero effects');
 FOR entry IN SELECT value FROM jsonb_array_elements(whole->'items') LOOP
  IF entry->>'kind'='command' THEN
   PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','command','source_input','status','receipt','decision']);
   PERFORM pg_temp.writer_ok(entry->'source_input'=(SELECT source_input FROM private.conversation_meal_command_sources WHERE user_id=u AND command_id=(entry#>>'{command,command_id}')::uuid),'page original source only '||(entry->>'event_id'));
   IF entry#>>'{command,command_id}'=c1::text THEN PERFORM pg_temp.writer_ok(entry->'receipt'=fx1 AND entry->>'status'='registered','page keeps immutable original FX after item edit');END IF;
   IF entry#>>'{command,command_id}'=c4::text THEN PERFORM pg_temp.writer_ok(entry->'decision'=decision AND entry->>'status'='not_recorded','page carries sealed decision');END IF;
   IF entry#>>'{command,command_id}'=c3::text THEN at_before:=entry->>'at';PERFORM pg_temp.writer_ok(entry->>'status'='pending' AND entry->'receipt'='null'::jsonb,'page pending is not a receipt');END IF;
  ELSE PERFORM private.conversation_meal_keys(entry,ARRAY['event_id','at','kind','command','receipt']);END IF;
 END LOOP;
 PERFORM pg_temp.writer_ok(NOT(whole::text ~ '"(clinical|original_facts|feedback_context|before_items|after_items|before_group|after_group|current_state|processing_result|signed_url)"'),'page private whitelist excludes clinical media and audit bodies');
 page:=public.read_conversation_meal_journal_page(foreign_u,foreign_epoch);
 PERFORM pg_temp.writer_ok(jsonb_array_length(page->'items')=1 AND page#>>'{items,0,command,command_id}'=foreign_c::text,'owner B sees only its actual original command');
 PERFORM pg_temp.page_register(u,c3);page:=public.read_conversation_meal_journal_page(u,epoch,25,NULL);
 PERFORM pg_temp.writer_ok((SELECT array_agg(x->>'event_id' ORDER BY n) FROM jsonb_array_elements(page->'items') WITH ORDINALITY e(x,n))=expected
  AND (SELECT x->>'at'=at_before AND x->>'status'='registered' FROM jsonb_array_elements(page->'items') x WHERE x->>'event_id'='command/'||c3::text),'terminal status update never moves admission event or changes pagination identity');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(u,foreign_epoch)='{"action":"stale_epoch"}'::jsonb,'foreign epoch refuses before data');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(u,epoch,10,jsonb_build_object('at',to_char(tie AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'id','command/'||foreign_c::text))='{"action":"cursor_conflict"}'::jsonb,'foreign cursor anchor cannot enter owned history');
 FOR cursor IN SELECT value FROM jsonb_array_elements('[{},null,{"at":"bad","id":"command/x"},{"at":"2026-01-01T00:00:00.000000Z","id":"command/00000000-0000-0000-0000-000000000000","extra":true}]') LOOP
  PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(u,epoch,10,cursor)='{"action":"cursor_conflict"}'::jsonb,'closed malformed cursor refuses '||cursor::text);
 END LOOP;
 FOREACH count_pages IN ARRAY ARRAY[0,26] LOOP refused:=false;BEGIN PERFORM public.read_conversation_meal_journal_page(u,epoch,count_pages);EXCEPTION WHEN invalid_parameter_value THEN refused:=true;END;PERFORM pg_temp.writer_ok(refused,'page bounded limit '||count_pages::text);END LOOP;
 UPDATE public.users SET status='blocked' WHERE id=foreign_u;
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(foreign_u,foreign_epoch)='{"action":"absent"}'::jsonb,'inactive patient history fails closed');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page(u,epoch)='{"action":"stale_epoch"}'::jsonb,'reset invalidates old cursor and original expected epoch');
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u;
 page:=public.read_conversation_meal_journal_page(u,epoch);
 PERFORM pg_temp.writer_ok(page->'items'='[]'::jsonb AND NOT(page->>'has_more')::boolean AND page->'next_cursor'='null'::jsonb,'reset scrubs history content without reacquiring old UUIDs');
END $page$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS journal_page_assertions FROM meal_writer_assertions;
ROLLBACK;

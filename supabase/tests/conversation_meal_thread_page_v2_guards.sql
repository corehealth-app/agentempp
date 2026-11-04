-- No PG execution until the exact runtime/registry handover.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_thread_page_v2_fixture.sql
DO $test$
DECLARE u uuid:='c3d30000-0000-4000-8000-000000000001';a uuid:='c3d30000-0000-4000-8000-000000000002';parent_id uuid:='c3d30000-0000-4000-8000-000000000003';
 foreign_u uuid:='c3d30000-0000-4000-8000-000000000201';foreign_a uuid:='c3d30000-0000-4000-8000-000000000202';foreign_p uuid:='c3d30000-0000-4000-8000-000000000203';
 c1 uuid:='c3d30000-0000-4000-8000-000000000101';c2 uuid:='c3d30000-0000-4000-8000-000000000102';c3 uuid:='c3d30000-0000-4000-8000-000000000103';bad uuid:='c3d30000-0000-4000-8000-000000000401';
 seed jsonb;foreign_seed jsonb;epoch uuid;new_epoch uuid;page jsonb;baseline jsonb;state jsonb;cursor jsonb;stamp timestamptz:=clock_timestamp()-interval '1 hour';clock_text text;raw jsonb;v jsonb;rejected boolean;bound integer;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,parent_id);epoch:=(seed#>>'{terminal,epoch}')::uuid;
 IF EXISTS(SELECT 1 FROM public.users WHERE id=foreign_u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=foreign_a) THEN RAISE EXCEPTION 'thread_empty_fixture_collision';END IF;
 INSERT INTO auth.users(id) VALUES(foreign_a);INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed)
  VALUES(foreign_u,foreign_a,'thread-empty@example.invalid','active','UTC','BR',true);
 state:=pg_temp.semantic_owner_state(foreign_u);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(foreign_u,gen_random_uuid())='{"action":"stale_epoch"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=foreign_u) AND pg_temp.semantic_owner_state(foreign_u)=state,'read refuses missing epoch without initializing lifecycle or identity');
 foreign_seed:=pg_temp.continuation_seed(foreign_u,foreign_a,foreign_p,true,false);
 PERFORM pg_temp.thread_v2_pending_at(u,c1,stamp);PERFORM pg_temp.thread_v2_pending_at(u,c2,stamp);PERFORM pg_temp.thread_v2_pending_at(u,c3,stamp);
 clock_text:=to_char(stamp AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 page:=public.read_conversation_meal_journal_page_v2(u,epoch,1);cursor:=page->'next_cursor';page:=public.read_conversation_meal_journal_page_v2(u,epoch,3,cursor);
 PERFORM pg_temp.writer_ok(page#>>'{items,0,event_id}'='command/'||c3::text AND page#>>'{items,1,event_id}'='command/'||c2::text
  AND page#>>'{items,2,event_id}'='command/'||c1::text,'server timestamp ties use exact descending C event ID order');
 PERFORM pg_temp.writer_ok(page#>>'{threads,0,thread_id}'=c1::text AND page#>>'{threads,1,thread_id}'=c2::text
  AND page#>>'{threads,2,thread_id}'=c3::text,'descriptors are unique and sorted independently of event order');
 FOREACH bound IN ARRAY ARRAY[0,26] LOOP
  rejected:=false;BEGIN PERFORM public.read_conversation_meal_journal_page_v2(u,epoch,bound);EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
  PERFORM pg_temp.writer_ok(rejected,'invalid page limit refused '||bound::text);
 END LOOP;
 FOREACH v IN ARRAY ARRAY['{}'::jsonb,'[]','{"at":1,"id":2}',jsonb_build_object('at',clock_text,'id','command/'||c1::text,'v',2),
  jsonb_build_object('at',clock_text,'id','reply/'||parent_id::text||'/'||c1::text),jsonb_build_object('at',clock_text||'0','id','command/'||c1::text),
  jsonb_build_object('at',foreign_seed#>>'{command,admitted_at}','id','command/'||foreign_p::text)] LOOP
  PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,epoch,10,v)='{"action":"cursor_conflict"}'::jsonb,'closed actual owned cursor refuses '||md5(v::text));
 END LOOP;
 baseline:=pg_temp.thread_v2_without_clock(public.read_conversation_meal_journal_page_v2(u,epoch));
 SET LOCAL timezone='Pacific/Auckland';SET LOCAL datestyle='SQL,DMY';
 PERFORM pg_temp.writer_ok(pg_temp.thread_v2_without_clock(public.read_conversation_meal_journal_page_v2(u,epoch))=baseline,'page clocks/JSON are independent of caller timezone and DateStyle');
 SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
 UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=u;state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.thread_v2_without_clock(public.read_conversation_meal_journal_page_v2(u,epoch))=baseline
  AND pg_temp.semantic_owner_state(u)=state,'historical head remains read-only after current source drift and is not a new write grant');
 UPDATE public.users SET status='blocked' WHERE id=u;
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,epoch)='{"action":"absent"}'::jsonb,'inactive patient has no page');
 UPDATE public.users SET status='active' WHERE id=u;
 PERFORM public.reset_user_conversation_atomic(u,true);
 SELECT e.epoch INTO new_epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u;
 page:=public.read_conversation_meal_journal_page_v2(u,new_epoch);
 PERFORM pg_temp.writer_ok(page->'items'='[]'::jsonb AND page->'threads'='[]'::jsonb AND page->'has_more'='false'::jsonb
  AND page->'next_cursor'='null'::jsonb,'new epoch returns an empty page without resurrecting erased content');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,new_epoch,10,cursor)='{"action":"cursor_conflict"}'::jsonb
  AND public.read_conversation_meal_journal_page_v2(u,epoch,10,cursor)='{"action":"stale_epoch"}'::jsonb,'old anchor and expected epoch cannot cross reset');
 -- Explicit synthetic corrupted source: no immutable row is updated.
 raw:=pg_temp.writer_input(bad);
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
 VALUES(u,bad,repeat('0',64),'conversation.command.v1','meal.report',new_epoch,clock_timestamp());
 INSERT INTO private.conversation_meal_command_sources VALUES(u,bad,raw);state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,new_epoch)='{"action":"event_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=state,'corrupt selected original binding fails closed rather than omitting the event');
 DELETE FROM public.users WHERE id=u;
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_journal_page_v2(u,new_epoch)='{"action":"absent"}'::jsonb,'account deletion removes page authority');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS thread_page_v2_guard_assertions FROM meal_writer_assertions;
ROLLBACK;

-- Actual privilege boundary, not a service claim on a postgres session only.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_thread_page_v2_fixture.sql
CREATE TEMP TABLE thread_role_fixture(u uuid,epoch uuid,baseline jsonb) ON COMMIT DROP;
DO $$ DECLARE s jsonb;u uuid:='c3d40000-0000-4000-8000-000000000001';a uuid:='c3d40000-0000-4000-8000-000000000002';c uuid:='c3d40000-0000-4000-8000-000000000003';BEGIN
 s:=pg_temp.continuation_seed(u,a,c);INSERT INTO thread_role_fixture VALUES(u,(s#>>'{terminal,epoch}')::uuid,pg_temp.semantic_owner_state(u));END $$;
GRANT SELECT ON thread_role_fixture TO service_role,anon,authenticated;
SET LOCAL ROLE service_role;
DO $$ DECLARE t record;p jsonb;rejected boolean;BEGIN
 IF current_user<>'service_role' THEN RAISE EXCEPTION 'actual_role_required';END IF;SELECT * INTO STRICT t FROM pg_temp.thread_role_fixture;
 p:=public.read_conversation_meal_journal_page_v2(t.u,t.epoch);
 IF p->>'action'<>'available' OR jsonb_array_length(p->'items')<>1 THEN RAISE EXCEPTION 'actual_service_read_failed';END IF;
 rejected:=false;BEGIN PERFORM 1 FROM private.conversation_meal_command_ids;EXCEPTION WHEN insufficient_privilege THEN rejected:=true;END;
 IF NOT rejected THEN RAISE EXCEPTION 'new_reader_must_not_grant_private_table_access';END IF;
 rejected:=false;BEGIN PERFORM private.conversation_thread_events_v2(t.u,t.epoch);EXCEPTION WHEN insufficient_privilege THEN rejected:=true;END;
 IF NOT rejected THEN RAISE EXCEPTION 'new_private_helpers_are_not_executable_capabilities';END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ DECLARE t record;rejected boolean;BEGIN SELECT * INTO STRICT t FROM pg_temp.thread_role_fixture;rejected:=false;
 BEGIN PERFORM public.read_conversation_meal_journal_page_v2(t.u,t.epoch);EXCEPTION WHEN insufficient_privilege THEN rejected:=true;END;
 IF NOT rejected THEN RAISE EXCEPTION 'anon_must_not_execute_even_with_claimed_service_jwt';END IF;END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ DECLARE t record;rejected boolean;BEGIN SELECT * INTO STRICT t FROM pg_temp.thread_role_fixture;rejected:=false;
 BEGIN PERFORM public.read_conversation_meal_journal_page_v2(t.u,t.epoch);EXCEPTION WHEN insufficient_privilege THEN rejected:=true;END;
 IF NOT rejected THEN RAISE EXCEPTION 'authenticated_must_not_execute_even_with_claimed_service_jwt';END IF;END $$;
RESET ROLE;
DO $$ DECLARE t record;BEGIN SELECT * INTO STRICT t FROM thread_role_fixture;
 PERFORM pg_temp.writer_ok(pg_temp.semantic_owner_state(t.u)=t.baseline,'actual-role read and ACL denials leave all owner state unchanged');
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname LIKE 'conversation_thread_%_v2'
  AND (p.provolatile NOT IN('s','i') OR p.prosecdef OR has_function_privilege('service_role',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE'))) THEN RAISE EXCEPTION 'new_helper_acl_or_volatility_conflict';END IF;
END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE rejected boolean:=false;BEGIN
 BEGIN PERFORM public.read_conversation_meal_journal_page_v2(gen_random_uuid(),gen_random_uuid());EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
 IF NOT rejected THEN RAISE EXCEPTION 'repeatable_read_must_be_refused';END IF;END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE rejected boolean:=false;BEGIN
 BEGIN PERFORM public.read_conversation_meal_journal_page_v2(gen_random_uuid(),gen_random_uuid());EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
 IF NOT rejected THEN RAISE EXCEPTION 'serializable_must_be_refused';END IF;END $$;
ROLLBACK;

-- INSERT-only corruption seams. No immutable row is updated. Every attack is
-- scoped to this explicit synthetic owner and rolled back independently.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_thread_page_v2_fixture.sql
CREATE FUNCTION pg_temp.thread_v2_attack_question(q jsonb,attack text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 CASE attack
 WHEN 'extra_snapshot' THEN RETURN q||'{"snapshot":{"private_health":"synthetic"}}'::jsonb;
 WHEN 'extra_source' THEN RETURN q||'{"source_context":{"clinical":"synthetic"}}'::jsonb;
 WHEN 'changed_name' THEN RETURN jsonb_set(q,'{food_name}','"leite"');
 WHEN 'changed_units' THEN RETURN jsonb_set(q,'{allowed_units}','["g","kg","mL"]');
 WHEN 'changed_reference' THEN RETURN jsonb_set(q,'{quantity_reference}','{"unit":"mL","grams_per_unit":1.03,"reference_id":"fao-infoods-v2-whole-milk-tb","estimated":true}');
 ELSE RAISE EXCEPTION 'unknown_synthetic_question_attack';END CASE;
END $$;
CREATE FUNCTION pg_temp.thread_v2_attack_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE attack text:=current_setting('performe.thread_v2_attack',true);
BEGIN
 IF NEW.user_id<>'c3d50000-0000-4000-8000-000000000001'::uuid OR coalesce(attack,'')='' THEN RETURN NEW;END IF;
 IF TG_TABLE_NAME='conversation_meal_replies' THEN
  IF current_setting('performe.thread_v2_target',true)='question' THEN
   NEW.question:=pg_temp.thread_v2_attack_question(NEW.question,attack);
  END IF;
 ELSIF TG_TABLE_NAME='conversation_meal_continuation_preparations' THEN
  IF current_setting('performe.thread_v2_target',true)='next_question' THEN
   IF NEW.next_question IS NOT NULL THEN
    NEW.next_question:=pg_temp.thread_v2_attack_question(NEW.next_question,attack);
   END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER thread_v2_test_question_insert BEFORE INSERT ON private.conversation_meal_replies FOR EACH ROW EXECUTE FUNCTION pg_temp.thread_v2_attack_insert();
CREATE TRIGGER thread_v2_test_next_insert BEFORE INSERT ON private.conversation_meal_continuation_preparations FOR EACH ROW EXECUTE FUNCTION pg_temp.thread_v2_attack_insert();
DO $attacks$
DECLARE u uuid:='c3d50000-0000-4000-8000-000000000001';a uuid:='c3d50000-0000-4000-8000-000000000002';p uuid:='c3d50000-0000-4000-8000-000000000003';
 r1 uuid:='c3d50000-0000-4000-8000-000000000004';r2 uuid:='c3d50000-0000-4000-8000-000000000005';seed jsonb;epoch uuid;attack text;target text;state jsonb;body jsonb;ad1 jsonb;ad2 jsonb;prep jsonb;fx jsonb;page jsonb;before_state jsonb;safe boolean;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,p);epoch:=(seed#>>'{terminal,epoch}')::uuid;
 FOREACH target IN ARRAY ARRAY['question','next_question'] LOOP
  FOREACH attack IN ARRAY ARRAY['extra_snapshot','extra_source','changed_name','changed_units','changed_reference'] LOOP
   safe:=false;
   BEGIN
    PERFORM set_config('performe.thread_v2_target',target,true);PERFORM set_config('performe.thread_v2_attack',attack,true);
    state:=pg_temp.continuation_read(u,p,seed);body:=pg_temp.continuation_body(state,'{"kind":"quantity","food_index":0,"amount":100,"unit":"g"}');
    ad1:=pg_temp.continuation_admit(u,p,seed,r1,body);
    IF target='next_question' THEN
     state:=pg_temp.continuation_read(u,p,seed,r1,ad1#>>'{child_binding,input_hash}');
     prep:=pg_temp.continuation_prepare(u,p,seed,r1,ad1#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(state,false));
     -- Advance and fulfill with a different child: the tampered question is
     -- now historical, so checking ONLY the current head cannot catch it.
     PERFORM set_config('performe.thread_v2_attack','',true);
     state:=pg_temp.continuation_read(u,p,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
     ad2:=pg_temp.continuation_admit(u,p,seed,r2,body);state:=pg_temp.continuation_read(u,p,seed,r2,ad2#>>'{child_binding,input_hash}');
     prep:=pg_temp.continuation_prepare(u,p,seed,r2,ad2#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(state));
     fx:=pg_temp.continuation_commit(u,p,seed,r2,ad2#>>'{child_binding,input_hash}',prep#>>'{stored,prepared_hash}');
     IF fx->>'action'<>'committed' THEN RAISE EXCEPTION 'attack_fixture_fulfillment_failed';END IF;
    END IF;
    before_state:=pg_temp.semantic_owner_state(u);page:=public.read_conversation_meal_journal_page_v2(u,epoch,25);
    safe:=page='{"action":"event_conflict"}'::jsonb AND pg_temp.semantic_owner_state(u)=before_state;
    RAISE EXCEPTION 'rollback_owned_attack_case' USING ERRCODE='P5851';
   EXCEPTION WHEN SQLSTATE 'P5851' THEN NULL;END;
   PERFORM pg_temp.writer_ok(safe,'full historical question provenance rejects INSERT '||target||' '||attack||' with zero read effects');
  END LOOP;
 END LOOP;
END $attacks$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS thread_page_v2_question_attack_assertions FROM meal_writer_assertions;
ROLLBACK;

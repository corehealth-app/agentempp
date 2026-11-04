BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_decision_fixture.sql
DO $prerequisite$
DECLARE u uuid:='c3db0000-0000-4000-8000-000000000001';a uuid:='c3db0000-0000-4000-8000-000000000002';c uuid:='c3db0000-0000-4000-8000-000000000003';c2 uuid:='c3db0000-0000-4000-8000-000000000004';
 admission jsonb;source jsonb;claim jsonb;seed jsonb;before_state jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=a) THEN RAISE EXCEPTION 'decision_prerequisite_collision';END IF;
 INSERT INTO auth.users(id) VALUES(a);INSERT INTO public.users(id,auth_user_id,status,timezone,country,country_confirmed) VALUES(u,a,'active','UTC','BR',true);
 admission:=public.admit_conversation_meal_command(u,pg_temp.writer_input(c)-'meal_type');before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.seal_conversation_meal_decision(u,c,(admission#>>'{command,epoch}')::uuid,admission#>>'{command,input_hash}',repeat('f',64),gen_random_uuid(),repeat('f',64),pg_temp.decision_payload())='{"action":"source_required"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'decision cannot fabricate captured source');
 source:=public.capture_conversation_meal_source(u,c);claim:=public.start_conversation_meal_semantic_attempt(u,c,'conversation.meal-interpreter.v1',source->>'source_hash');before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.seal_conversation_meal_decision(u,c,(claim->>'epoch')::uuid,claim->>'input_hash',claim->>'source_hash',(claim->>'attempt_id')::uuid,repeat('f',64),pg_temp.decision_payload())='{"action":"semantic_required"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'started provider attempt is not a terminal semantic decision');
 PERFORM public.mark_conversation_meal_semantic_unknown(u,c,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,'provider_outcome_unknown');before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.seal_conversation_meal_decision(u,c,(claim->>'epoch')::uuid,claim->>'input_hash',claim->>'source_hash',(claim->>'attempt_id')::uuid,repeat('f',64),pg_temp.decision_payload())='{"action":"semantic_required"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'unknown provider outcome never becomes invented not-recorded');
 seed:=pg_temp.decision_seed(u,a,c2,false);before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.seal_conversation_meal_decision(u,c2,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',seed#>>'{terminal,source_hash}',(seed#>>'{terminal,attempt_id}')::uuid,repeat('f',64),pg_temp.decision_payload())='{"action":"semantic_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'caller cannot replace actual semantic result hash');
 PERFORM pg_temp.writer_ok(pg_temp.decision_seal(u,c2,seed,pg_temp.decision_payload('nutrition_unresolved','[29]'))='{"action":"semantic_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'decision food indexes reference actual completed interpretation foods');
 PERFORM pg_temp.writer_ok(pg_temp.decision_seal(u,c2,seed,pg_temp.decision_payload('nutrition_unresolved','[0]'))->>'action'='sealed','actual source food index may be sealed');
 DELETE FROM public.users WHERE id=u;DELETE FROM auth.users WHERE id=a;
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_decisions WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'account cascade removes live decision and command identities');
END $prerequisite$;
DO $acl$
DECLARE signature text;refused boolean:=false;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'public.seal_conversation_meal_decision(uuid,uuid,uuid,text,text,uuid,text,jsonb)',
  'public.read_conversation_meal_decision(uuid,uuid,uuid,text)',
  'public.read_conversation_meal_journal_page(uuid,uuid,integer,jsonb)'] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE') OR has_function_privilege('authenticated',signature,'EXECUTE') OR NOT has_function_privilege('service_role',signature,'EXECUTE') THEN RAISE EXCEPTION 'decision_page_acl_failed:%',signature;END IF;
 END LOOP;
 IF NOT(SELECT relrowsecurity FROM pg_class WHERE oid='private.conversation_meal_decisions'::regclass) OR
  has_table_privilege('service_role','private.conversation_meal_decisions','SELECT,INSERT,UPDATE,DELETE') OR
  has_table_privilege('authenticated','private.conversation_meal_decisions','SELECT,INSERT,UPDATE,DELETE') OR
  has_table_privilege('anon','private.conversation_meal_decisions','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'decision_rls_failed';END IF;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN PERFORM public.read_conversation_meal_journal_page(NULL,NULL);EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
 IF NOT refused THEN RAISE EXCEPTION 'decision_page_untrusted_jwt_accepted';END IF;
 RAISE NOTICE 'DECISION_SECURITY_PASS:ACL_RLS_untrusted_JWT';
END $acl$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS decision_prerequisite_assertions FROM meal_writer_assertions;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.seal_conversation_meal_decision('c3db0000-0000-4000-8000-000000000001','c3db0000-0000-4000-8000-000000000003','c3db0000-0000-4000-8000-000000000099',repeat('a',64),repeat('b',64),'c3db0000-0000-4000-8000-000000000003',repeat('c',64),'{}'::jsonb);EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'decision_isolation_failed:seal_conversation_meal_decision';END IF;RAISE NOTICE 'DECISION_SECURITY_PASS:REPEATABLE READ:seal_conversation_meal_decision';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_decision('c3db0000-0000-4000-8000-000000000001','c3db0000-0000-4000-8000-000000000003','c3db0000-0000-4000-8000-000000000099',repeat('a',64));EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_decision_read';END;IF NOT refused THEN RAISE EXCEPTION 'decision_isolation_failed:read_conversation_meal_decision';END IF;RAISE NOTICE 'DECISION_SECURITY_PASS:REPEATABLE READ:read_conversation_meal_decision';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_journal_page('c3db0000-0000-4000-8000-000000000001','c3db0000-0000-4000-8000-000000000099',10,NULL);EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_journal_page';END;IF NOT refused THEN RAISE EXCEPTION 'decision_isolation_failed:read_conversation_meal_journal_page';END IF;RAISE NOTICE 'DECISION_SECURITY_PASS:REPEATABLE READ:read_conversation_meal_journal_page';END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.seal_conversation_meal_decision('c3db0000-0000-4000-8000-000000000001','c3db0000-0000-4000-8000-000000000003','c3db0000-0000-4000-8000-000000000099',repeat('a',64),repeat('b',64),'c3db0000-0000-4000-8000-000000000003',repeat('c',64),'{}'::jsonb);EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'decision_isolation_failed:seal_conversation_meal_decision';END IF;RAISE NOTICE 'DECISION_SECURITY_PASS:SERIALIZABLE:seal_conversation_meal_decision';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_decision('c3db0000-0000-4000-8000-000000000001','c3db0000-0000-4000-8000-000000000003','c3db0000-0000-4000-8000-000000000099',repeat('a',64));EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_decision_read';END;IF NOT refused THEN RAISE EXCEPTION 'decision_isolation_failed:read_conversation_meal_decision';END IF;RAISE NOTICE 'DECISION_SECURITY_PASS:SERIALIZABLE:read_conversation_meal_decision';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_journal_page('c3db0000-0000-4000-8000-000000000001','c3db0000-0000-4000-8000-000000000099',10,NULL);EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_journal_page';END;IF NOT refused THEN RAISE EXCEPTION 'decision_isolation_failed:read_conversation_meal_journal_page';END IF;RAISE NOTICE 'DECISION_SECURITY_PASS:SERIALIZABLE:read_conversation_meal_journal_page';END $$;
ROLLBACK;

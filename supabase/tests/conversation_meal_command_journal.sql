-- Synthetic, transaction-scoped contract. Never call against a cloud database.
BEGIN;
CREATE TEMP TABLE journal_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.journal_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'JOURNAL_ASSERT: %',label; END IF;
INSERT INTO journal_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.journal_input(c uuid,t text DEFAULT 'Comi 100g de arroz') RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('command_protocol','conversation.command.v1','command_id',c::text,'kind','meal.report','meal_type','almoco','source',jsonb_build_object('channel','text','text',t)); $$;
DO $test$
DECLARE a uuid:='c3a00000-0000-4000-8000-000000000001';b uuid:='c3a00000-0000-4000-8000-000000000002';c uuid:='c3a00000-0000-4000-8000-000000000003';d uuid:='c3a00000-0000-4000-8000-000000000004';
 input jsonb:=pg_temp.journal_input(c);x jsonb;y jsonb;before_clock timestamptz:=clock_timestamp();
BEGIN
 PERFORM pg_temp.journal_ok(to_regprocedure('public.admit_conversation_meal_command(uuid,jsonb)') IS NOT NULL,'journal admission exists');
 INSERT INTO public.users(id,email,status,timezone) VALUES(a,'journal-a@example.invalid','active','UTC'),(b,'journal-b@example.invalid','active','UTC');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 x:=public.admit_conversation_meal_command(a,input);
 PERFORM pg_temp.journal_ok(x->>'action'='admitted','new command admitted');
 PERFORM pg_temp.journal_ok((SELECT admitted_at>=before_clock AND admitted_at<=clock_timestamp() FROM private.conversation_meal_command_ids WHERE user_id=a AND command_id=c),'server admission clock');
 y:=public.admit_conversation_meal_command(a,input);
 PERFORM pg_temp.journal_ok(y->>'action'='replay' AND x->'command'=y->'command','same immutable admission replay');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(a,pg_temp.journal_input(c,'Comi 200g de arroz'))='{"action":"input_conflict"}'::jsonb,'same ID changed source conflicts');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(a,pg_temp.journal_input(d))->>'action'='admitted','two IDs same food distinct admissions');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(b,input)->>'action'='admitted','owners isolated');
END $test$;
CREATE FUNCTION pg_temp.journal_bad_input(u uuid,v jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE code text; BEGIN
 BEGIN PERFORM public.admit_conversation_meal_command(u,v); EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 PERFORM pg_temp.journal_ok(code='22023',label);
END $$;
DO $test$
DECLARE a uuid:='c3a00000-0000-4000-8000-000000000001';b uuid:='c3a00000-0000-4000-8000-000000000002';c uuid:='c3a00000-0000-4000-8000-000000000003';old_id uuid:='c3a00000-0000-4000-8000-000000000005';
 input jsonb:=pg_temp.journal_input(c);x jsonb;y jsonb;h text;candidate jsonb;code text;k text;epoch uuid;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH k IN ARRAY ARRAY['command_protocol','kind','command_id','source','meal_type'] LOOP
  PERFORM pg_temp.journal_bad_input(a,jsonb_set(input,ARRAY[k],'null'::jsonb),'reject null command field '||k);
 END LOOP;
 PERFORM pg_temp.journal_bad_input(a,input||'{"epoch":"forged"}'::jsonb,'reject forged authority');
 PERFORM pg_temp.journal_bad_input(a,jsonb_set(input,'{source}','{"channel":"text","text":"ok","transcript":"forged"}'),'reject forged source property');
 PERFORM pg_temp.journal_bad_input(a,jsonb_set(input,'{source}','{"channel":"media","media_asset_id":"c3a00000-0000-4000-8000-000000000008","user_action":null}'),'reject null media gesture');
 PERFORM pg_temp.journal_bad_input(a,jsonb_set(input,'{source}',jsonb_build_object('channel','text','text',repeat('😀',1001))),'same UTF16 limit as DTO');
 PERFORM pg_temp.journal_bad_input(a,jsonb_set(input,'{source}',jsonb_build_object('channel','text','text',chr(127))),'reject source DEL');
 PERFORM pg_temp.journal_bad_input(a,jsonb_set(input,'{source}',jsonb_build_object('channel','text','text',E'\t\n')),'reject whitespace source');
 h:=public.admit_conversation_meal_command(a,input)#>>'{command,input_hash}';
 PERFORM pg_temp.journal_ok(h='15356c1f9607410ffd95a822c5dfeedcb0cf42f1f2c042bf8621a1e38e600368','same hash as strict DTO canonical JSON');
 candidate:=jsonb_build_object('schema','conversation.meal-candidate.v1','input_hash',h,'status','prepared','candidate',jsonb_build_object('draft','synthetic candidate only','source_evidence',jsonb_build_object('text','untrusted derived candidate')));
 x:=public.attach_conversation_meal_candidate(a,c,h,candidate);
 PERFORM pg_temp.journal_ok(x->>'action'='attached','attach candidate once');
 PERFORM pg_temp.journal_ok(public.attach_conversation_meal_candidate(a,c,h,candidate)=x||'{"action":"replay"}'::jsonb,'candidate attachment replay exact hash');
 PERFORM pg_temp.journal_ok(public.attach_conversation_meal_candidate(a,c,h,jsonb_set(candidate,'{candidate,draft}','"override"'))='{"action":"candidate_conflict"}'::jsonb,'candidate cannot be overridden');
 PERFORM pg_temp.journal_ok(public.attach_conversation_meal_candidate(a,c,repeat('0',64),jsonb_set(candidate,'{input_hash}',to_jsonb(repeat('0',64))))='{"action":"input_conflict"}'::jsonb,'attach binds original input hash');
 PERFORM pg_temp.journal_ok(public.attach_conversation_meal_candidate(b,old_id,h,candidate)='{"action":"absent"}'::jsonb,'foreign attach absent');
 y:=public.read_conversation_meal_command(a,c);
 PERFORM pg_temp.journal_ok(y->>'state'='candidate_attached' AND y->'source_input'=input AND y->'candidate'=candidate,'read returns frozen original plus candidate separately');
 PERFORM pg_temp.journal_ok(public.read_conversation_meal_command(b,old_id)='{"action":"absent"}'::jsonb,'foreign status reveals nothing');
 BEGIN UPDATE private.conversation_meal_command_sources SET source_input='{}' WHERE user_id=a AND command_id=c;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 PERFORM pg_temp.journal_ok(code='22023' AND public.read_conversation_meal_command(a,c)=y,'original source immutable');code:=NULL;
 BEGIN UPDATE private.conversation_meal_command_candidates SET candidate='{}' WHERE user_id=a AND command_id=c;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 PERFORM pg_temp.journal_ok(code='22023','candidate immutable');code:=NULL;
 BEGIN PERFORM public.attach_conversation_meal_candidate(a,c,h,jsonb_set(candidate,'{status}','null'));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 PERFORM pg_temp.journal_ok(code='22023','reject null candidate status');
 -- A fixture admitted 25 hours ago proves no HTTP TTL or request-clock expiry.
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE user_id=a;
 input:=pg_temp.journal_input(old_id);h:=encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_command_ids VALUES(a,old_id,h,'conversation.command.v1','meal.report',epoch,clock_timestamp()-interval '25 hours',NULL);
 INSERT INTO private.conversation_meal_command_sources VALUES(a,old_id,input);
 x:=public.admit_conversation_meal_command(a,input);
 PERFORM pg_temp.journal_ok(x->>'action'='replay' AND (x#>>'{command,admitted_at}')::timestamptz<clock_timestamp()-interval '24 hours','durable replay beyond 24 hours');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(b,pg_temp.journal_input('00000000-0000-0000-0000-000000000000'))->>'action'='admitted','DTO parity accepts nil command UUID');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(b,jsonb_build_object('command_protocol','conversation.command.v1','command_id','c3a00000-0000-0000-0000-000000000007','kind','meal.report','source',jsonb_build_object('channel','media','media_asset_id','c3a00000-0000-0000-0000-000000000008','user_action','register_consumed_meal')))->>'action'='admitted','DTO parity accepts non RFC variant media UUID');
 -- Reset initializes no workout lifecycle, but admission initialized its epoch.
 PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=a),'journal never initializes workout lifecycle');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM pg_temp.journal_ok((SELECT count(*)=3 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_meal_command_ids WHERE user_id=a),'reset retains all dedup tombstones');
 PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_sources WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_candidates WHERE user_id=a),'reset scrubs source and candidate content');
 PERFORM pg_temp.journal_ok(public.read_conversation_meal_command(a,c)='{"action":"stale_epoch"}'::jsonb,'reset status hides scrubbed source');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(a,pg_temp.journal_input(c))='{"action":"stale_epoch"}'::jsonb AND public.admit_conversation_meal_command(a,pg_temp.journal_input(c,'changed'))='{"action":"stale_epoch"}'::jsonb,'old UUID never reacquires epoch even changed source');
 PERFORM pg_temp.journal_ok(public.attach_conversation_meal_candidate(a,c,candidate->>'input_hash',candidate)='{"action":"stale_epoch"}'::jsonb,'reset fences prepared candidate');
 PERFORM pg_temp.journal_ok(public.admit_conversation_meal_command(a,pg_temp.journal_input('c3a00000-0000-4000-8000-000000000006'))->>'action'='admitted','new UUID after reset allowed');
 PERFORM pg_temp.journal_ok(public.read_conversation_meal_command(b,c)->>'action'='available','reset isolates other owner');
 DELETE FROM public.users WHERE id=a;
 PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=a),'account deletion cascades tombstones');
END $test$;
-- Hash vectors generated by the actual frozen TypeScript bindConversationCommand.
SELECT pg_temp.journal_ok(encode(sha256(convert_to(private.conversation_command_canonical($vector${"command_protocol":"conversation.command.v1","command_id":"c3a00000-0000-4000-8000-000000000030","kind":"meal.report","source":{"channel":"text","text":"  Comi café 😀\nporção é \"arroz\" \\ teste\t  "}}$vector$::jsonb),'UTF8')),'hex')='ac7af29a6de646650f170c4df2f477ea66111d5c8037c599681240f1b37e220f','actual TypeScript canonical parity vector 1');
SELECT pg_temp.journal_ok(encode(sha256(convert_to(private.conversation_command_canonical($vector${"command_protocol":"conversation.command.v1","command_id":"c3a00000-0000-4000-8000-000000000030","kind":"meal.report","meal_type":"ceia","source":{"channel":"media","media_asset_id":"00000000-0000-0000-0000-000000000000","user_action":"register_consumed_meal","caption":"Meu café 😀"}}$vector$::jsonb),'UTF8')),'hex')='da324404e86d71f9812e7cd4536d92f83e1fbb6e5e39df5e3bbc04395865c510','actual TypeScript canonical parity vector 2');
CREATE FUNCTION pg_temp.journal_forced_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic journal rollback' USING ERRCODE='P5503'; END $$;
DO $journal_rollback$
DECLARE a uuid:='c3a00000-0000-4000-8000-000000000031';b uuid:='c3a00000-0000-4000-8000-000000000002';c uuid:='c3a00000-0000-4000-8000-000000000003';code text;h text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(a,'journal-rollback@example.invalid','active','UTC');
 CREATE TRIGGER qa_journal_failure AFTER INSERT ON private.conversation_meal_command_sources FOR EACH ROW EXECUTE FUNCTION pg_temp.journal_forced_failure();
 BEGIN PERFORM public.admit_conversation_meal_command(a,pg_temp.journal_input(c));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 DROP TRIGGER qa_journal_failure ON private.conversation_meal_command_sources;
 PERFORM pg_temp.journal_ok(code='P5503' AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=a),'post-source failure rolls back ID source and new epoch');
 h:=public.read_conversation_meal_command(b,c)#>>'{command,input_hash}';code:=NULL;
 CREATE TRIGGER qa_journal_failure AFTER INSERT ON private.conversation_meal_command_candidates FOR EACH ROW EXECUTE FUNCTION pg_temp.journal_forced_failure();
 BEGIN PERFORM public.attach_conversation_meal_candidate(b,c,h,jsonb_build_object('schema','conversation.meal-candidate.v1','input_hash',h,'status','prepared','candidate','{}'::jsonb));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 DROP TRIGGER qa_journal_failure ON private.conversation_meal_command_candidates;
 PERFORM pg_temp.journal_ok(code='P5503' AND public.read_conversation_meal_command(b,c)->>'state'='admitted','post-candidate failure rolls back attachment preserves source');
END $journal_rollback$;
DO $roles_and_preservation$
DECLARE a uuid:='c3a00000-0000-4000-8000-000000000020';c uuid:='c3a00000-0000-4000-8000-000000000021';pending uuid:='c3a00000-0000-4000-8000-000000000022';x jsonb;h text;code text;r text;cursor_before jsonb;input jsonb:=pg_temp.journal_input(c);
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(a,'journal-service@example.invalid','active','UTC');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=a),'reset before any authority remains valid');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(pending,a,'pending','{"kind":"workout","synthetic":"preserve"}',clock_timestamp()+interval '1 hour');
 cursor_before:=public.read_flow_shared_phrase_cursor(a);
 SET LOCAL ROLE service_role;
 x:=public.admit_conversation_meal_command(a,input);
 h:=x#>>'{command,input_hash}';
 x:=public.attach_conversation_meal_candidate(a,c,h,jsonb_build_object('schema','conversation.meal-candidate.v1','input_hash',h,'status','conversational','candidate','{}'::jsonb));
 x:=public.read_conversation_meal_command(a,c);
 SET LOCAL ROLE NONE;
 PERFORM pg_temp.journal_ok(x->>'state'='candidate_attached','actual service role executes complete foundation');
 PERFORM pg_temp.journal_ok((SELECT status='pending' AND proposal='{"kind":"workout","synthetic":"preserve"}'::jsonb FROM public.pending_registrations WHERE id=pending),'unrelated pending is preserved');
 PERFORM pg_temp.journal_ok(cursor_before=public.read_flow_shared_phrase_cursor(a),'journal never advances v1 phrase cursor');
 PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=a) AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),'candidate foundation writes no domain or reward snapshot');
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  code:=NULL;
  BEGIN
   EXECUTE format('SET LOCAL ROLE %I',r);
   PERFORM public.read_conversation_meal_command(a,c);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  SET LOCAL ROLE NONE;
  PERFORM pg_temp.journal_ok(code='42501','actual public role denied '||r);
 END LOOP;
 code:=NULL;
 BEGIN
  SET LOCAL ROLE service_role;
  PERFORM 1 FROM private.conversation_meal_command_sources;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 SET LOCAL ROLE NONE;
 PERFORM pg_temp.journal_ok(code='42501','actual service direct-table read denied');
END $roles_and_preservation$;
DO $acl$
DECLARE f text;t text;r text;
BEGIN
 FOREACH f IN ARRAY ARRAY['public.admit_conversation_meal_command(uuid,jsonb)','public.attach_conversation_meal_candidate(uuid,uuid,text,jsonb)','public.read_conversation_meal_command(uuid,uuid)'] LOOP
  PERFORM pg_temp.journal_ok(NOT has_function_privilege('anon',f,'EXECUTE') AND NOT has_function_privilege('authenticated',f,'EXECUTE') AND has_function_privilege('service_role',f,'EXECUTE'),'trusted-only RPC '||f);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['private.conversation_meal_command_ids','private.conversation_meal_command_sources','private.conversation_meal_command_candidates'] LOOP
  PERFORM pg_temp.journal_ok((SELECT relrowsecurity FROM pg_class WHERE oid=t::regclass),'RLS enabled '||t);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.journal_ok(NOT has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE'),'no direct table privilege '||r||' '||t);
  END LOOP;
 END LOOP;
END $acl$;
SELECT count(*) AS journal_assertions FROM journal_assertions;
ROLLBACK;

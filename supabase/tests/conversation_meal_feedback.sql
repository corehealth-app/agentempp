-- Real owned local PostgreSQL only. A fresh test session rolls every fixture back.
BEGIN;
\ir fixtures/conversation_meal_feedback_fixture.sql
DO $exists$
BEGIN PERFORM pg_temp.writer_ok(to_regprocedure('public.commit_conversation_meal_feedback_v2(uuid,uuid,text,jsonb)') IS NOT NULL,'command feedback sealer exists');END $exists$;
DO $frozen$
DECLARE a uuid:='c3f00000-0000-4000-8000-000000000001';auth_id uuid:='c3f00000-0000-4000-8000-000000000002';cmd uuid:='c3f00000-0000-4000-8000-000000000003';foreign_owner uuid:='c3f00000-0000-4000-8000-000000000004';
 committed jsonb;source jsonb;f jsonb;x jsonb;before_all jsonb;frozen jsonb;mid uuid;sid uuid;rid uuid;state jsonb;code text;message text;cursor_before jsonb;
BEGIN
 INSERT INTO auth.users(id) VALUES(auth_id);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed) VALUES(a,auth_id,'command-feedback@example.invalid','active','UTC','BR',true);
 INSERT INTO public.users(id,email,status,timezone) VALUES(foreign_owner,'command-feedback-other@example.invalid','active','UTC');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 committed:=pg_temp.feedback_seed(a,cmd);rid:=(committed#>>'{receipt,registration_id}')::uuid;
 source:=public.read_conversation_meal_feedback_source(a,cmd);f:=pg_temp.command_feedback(source->'context');
 PERFORM pg_temp.writer_ok(source->>'action'='available' AND source->'receipt'=committed->'receipt','read returns exact frozen source and mandatory receipt');
 PERFORM pg_temp.writer_ok(source#>>'{context,logs,0,kcal}'='130.04','original saved two-decimal facts are frozen');
 before_all:=pg_temp.feedback_owner_state(a);cursor_before:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_v2(a,cmd)='{"action":"absent"}'::jsonb,'no implicit feedback on source/status read');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_source(a,cmd)=source AND pg_temp.feedback_owner_state(a)=before_all,'repeated source read has no initialization or effects');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_source(foreign_owner,cmd)='{"action":"absent"}'::jsonb AND public.read_conversation_meal_feedback_v2(foreign_owner,cmd)='{"action":"absent"}'::jsonb,'foreign reads reveal no original context');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_feedback_v2(a,cmd,'cmeal1:'||repeat('a',64),f)='{"action":"source_conflict"}'::jsonb,'new seal requires actual immutable effect version');
 BEGIN PERFORM public.commit_conversation_meal_feedback_v2(a,cmd,committed#>>'{receipt,effect_version}',jsonb_set(f,'{registration,items,0,kcal}','999'));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;END;
 PERFORM pg_temp.writer_ok(code='22023' AND message='invalid_conversation_meal_feedback' AND pg_temp.feedback_owner_state(a)=before_all,'invalid DTO redacted with no effects');
 -- Actual C11 edit after domain commit, before receipt sealing.
 mid:=(committed#>>'{receipt,log_ids,0}')::uuid;SELECT snapshot_id INTO sid FROM public.meal_logs WHERE id=mid;
 SELECT to_jsonb(e) INTO frozen FROM private.conversation_meal_effects e WHERE user_id=a AND command_id=cmd;
 state:=pg_temp.feedback_c11_state(a,sid,mid);
 x:=public.mutate_mobile_confirmed_meal(a,'synthetic-feedback-c11','PATCH','/api/mobile/v1/meal-records/'||mid::text,repeat('f',64),mid,'v1:'||repeat('a',64),ARRAY[mid],state,
 '[{"food_name":"arroz sintetico","food_db_id":null,"source":"user_kcal","quantity_g":100,"kcal":140,"protein_g":2.31,"carbs_g":28.21,"fat_g":0.21,"confidence":null}]','recalculated',NULL,'synthetic-feedback-c11');
 PERFORM pg_temp.writer_ok(x->>'action'='completed' AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE id=mid),'actual C11 replaces old live log');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_source(a,cmd)=source AND (SELECT to_jsonb(e)=frozen FROM private.conversation_meal_effects e WHERE user_id=a AND command_id=cmd),'C11 cannot recapture or rewrite original source');
 UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=a;
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_source(a,cmd)=source,'later current owner context does not rewrite historical source');
 PERFORM pg_temp.writer_ok(public.commit_mobile_registration_feedback_v2(a,rid,source->'context',f)='{"action":"event_conflict"}'::jsonb,'generic live-CAS sealer cannot capture command events');
 before_all:=pg_temp.feedback_owner_state(a);
 CREATE TRIGGER qa_command_feedback_fail AFTER INSERT ON private.mobile_registration_feedback_v2 FOR EACH ROW EXECUTE FUNCTION pg_temp.feedback_fail_insert();
 code:=NULL;BEGIN PERFORM public.commit_conversation_meal_feedback_v2(a,cmd,committed#>>'{receipt,effect_version}',f);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 DROP TRIGGER qa_command_feedback_fail ON private.mobile_registration_feedback_v2;
 PERFORM pg_temp.writer_ok(code='P5510' AND pg_temp.feedback_owner_state(a)=before_all,'failed seal rolls back without affecting original domain');
 x:=pg_temp.feedback_service_commit(a,cmd,committed#>>'{receipt,effect_version}',f);
 PERFORM pg_temp.writer_ok(x=jsonb_build_object('action','committed','feedback',f),'frozen original seals after live C11 replacement');
 PERFORM pg_temp.writer_ok((pg_temp.feedback_owner_state(a)-'private.mobile_registration_feedback_v2')=(before_all-'private.mobile_registration_feedback_v2'),'sealing changes only receipt table');
 PERFORM pg_temp.writer_ok((SELECT command_id=cmd AND proposal_hash=encode(extensions.digest(convert_to((source#>'{context,confirmed,proposal}')::text,'UTF8'),'sha256'),'hex') FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'v2 receipt linked to owned command and original proposal hash');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_v2(a,cmd)=jsonb_build_object('action','available','feedback',f),'command read returns original v2 receipt');
 PERFORM set_config('TimeZone','Pacific/Honolulu',true);PERFORM set_config('DateStyle','SQL,DMY',true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_source(a,cmd)=source AND public.read_conversation_meal_feedback_v2(a,cmd)=jsonb_build_object('action','available','feedback',f),'caller TimeZone and DateStyle cannot alter original read');
 PERFORM set_config('TimeZone','UTC',true);PERFORM set_config('DateStyle','ISO,YMD',true);
 UPDATE public.daily_snapshots SET calories_consumed=999,day_closed=true WHERE id=sid;
 UPDATE public.pending_registrations SET proposal=proposal||'{"synthetic_later_revision":true}' WHERE id=rid;
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_v2(a,cmd)=jsonb_build_object('action','available','feedback',f) AND public.read_mobile_registration_feedback_v2(a,rid)='{"action":"event_conflict"}'::jsonb,'command frozen read preserves old T2C live proposal CAS');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_feedback_v2(a,cmd,NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'retry replays before payload/currentday/live proposal checks');
 PERFORM pg_temp.writer_ok(public.commit_mobile_registration_feedback(a,rid,NULL,NULL,NULL,NULL,NULL)='{"action":"event_conflict"}'::jsonb AND public.read_flow_shared_phrase_cursor(a)=cursor_before,'v2 winner fences v1 before phrase draw');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,cmd,NULL)=jsonb_set(committed,'{action}','"replay"'),'feedback never repeats command domain');
 -- Epoch transition alone must scrub linked health receipt even while pending survives.
 UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid() WHERE user_id=a;
 PERFORM pg_temp.writer_ok(EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=rid) AND NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'epoch source cascade scrubs linked receipt without pending deletion');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_v2(a,cmd)='{"action":"stale_epoch"}'::jsonb AND public.read_conversation_meal_feedback_source(a,cmd)='{"action":"stale_epoch"}'::jsonb AND public.commit_conversation_meal_feedback_v2(a,cmd,NULL,NULL)='{"action":"stale_epoch"}'::jsonb,'all feedback paths fence old UUID before replay');
END $frozen$;
DO $unavailable$
DECLARE a uuid:='c3f00000-0000-4000-8000-000000000010';cmd uuid:='c3f00000-0000-4000-8000-000000000011';committed jsonb;source jsonb;before_all jsonb;definition text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'command-feedback-null@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 -- Force only optional capture to fail; restore before any read or seal.
 SELECT pg_get_functiondef('private.capture_mobile_registration_feedback_v2(uuid,uuid)'::regprocedure) INTO definition;
 EXECUTE $replace$CREATE OR REPLACE FUNCTION private.capture_mobile_registration_feedback_v2(p_owner uuid,p_registration uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $body$BEGIN RAISE EXCEPTION 'synthetic optional enrichment failure' USING ERRCODE='P5509'; END $body$$replace$;
 committed:=pg_temp.feedback_seed(a,cmd);
 EXECUTE definition;
 before_all:=pg_temp.feedback_owner_state(a);source:=public.read_conversation_meal_feedback_source(a,cmd);
 PERFORM pg_temp.writer_ok(source=jsonb_build_object('action','unavailable','reason','original_context_unavailable','receipt',committed->'receipt'),'missing optional context explicitly unavailable with factual receipt');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_feedback_v2(a,cmd,committed#>>'{receipt,effect_version}','{}')=source,'NULL frozen context never recaptured during seal');
 PERFORM pg_temp.writer_ok(pg_temp.feedback_owner_state(a)=before_all AND public.commit_conversation_meal(a,cmd,NULL)=jsonb_set(committed,'{action}','"replay"'),'missing enrichment has no domain retry or state changes');
END $unavailable$;
DO $legacy$
DECLARE a uuid:='c3f00000-0000-4000-8000-000000000020';cmd uuid;committed jsonb;source jsonb;p jsonb;x jsonb;f jsonb;rid uuid;changed boolean;cursor_before jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'command-feedback-v1@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH changed IN ARRAY ARRAY[false,true] LOOP
  cmd:=CASE WHEN changed THEN 'c3f00000-0000-4000-8000-000000000022'::uuid ELSE 'c3f00000-0000-4000-8000-000000000021'::uuid END;
  committed:=pg_temp.feedback_seed(a,cmd);rid:=(committed#>>'{receipt,registration_id}')::uuid;source:=public.read_conversation_meal_feedback_source(a,cmd);
  p:=source#>'{context,confirmed,proposal}';
  IF changed THEN p:=p||'{"synthetic_c11_revision":true}'::jsonb;UPDATE public.pending_registrations SET proposal=p WHERE id=rid;END IF;
  x:=pg_temp.command_seal_legacy(a,rid,p);f:=pg_temp.command_legacy_feedback(rid);
  PERFORM pg_temp.writer_ok(x=jsonb_build_object('action','committed','feedback',f),'actual legacy writer still works changed='||changed);
  cursor_before:=public.read_flow_shared_phrase_cursor(a);
  IF changed THEN
   PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_v2(a,cmd)='{"action":"event_conflict"}'::jsonb AND public.commit_conversation_meal_feedback_v2(a,cmd,NULL,NULL)='{"action":"event_conflict"}'::jsonb,'changed-hash v1 winner cannot be relabelled as original');
  ELSE
   PERFORM pg_temp.writer_ok(public.read_conversation_meal_feedback_v2(a,cmd)=jsonb_build_object('action','legacy','feedback',f) AND public.commit_conversation_meal_feedback_v2(a,cmd,NULL,NULL)=jsonb_build_object('action','legacy','feedback',f),'original v1 winner stays unchanged before any v2 validation');
  END IF;
  PERFORM pg_temp.writer_ok(public.read_flow_shared_phrase_cursor(a)=cursor_before AND NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'v1 winner prevents new receipt or phrase draw changed='||changed);
 END LOOP;
END $legacy$;
DO $acl$
DECLARE sig text;role_name text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['public.read_conversation_meal_feedback_source(uuid,uuid)','public.read_conversation_meal_feedback_v2(uuid,uuid)','public.commit_conversation_meal_feedback_v2(uuid,uuid,text,jsonb)'] LOOP
 PERFORM pg_temp.writer_ok(has_function_privilege('service_role',sig,'EXECUTE') AND NOT has_function_privilege('anon',sig,'EXECUTE') AND NOT has_function_privilege('authenticated',sig,'EXECUTE'),'service-only command feedback '||sig);END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
 PERFORM pg_temp.writer_ok(NOT has_table_privilege(role_name,'private.mobile_registration_feedback_v2','SELECT,INSERT,UPDATE,DELETE'),'no direct receipt access '||role_name);END LOOP;
END $acl$;
SELECT count(*) AS conversation_feedback_assertions FROM meal_writer_assertions;
ROLLBACK;

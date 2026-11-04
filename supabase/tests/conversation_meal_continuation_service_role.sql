BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_continuation_fixture.sql
CREATE TEMP TABLE continuation_role_fixture(u uuid,c uuid,r uuid,parent_seed jsonb,admission jsonb,preparation jsonb,old_c uuid,old_prepared jsonb) ON COMMIT DROP;
DO $seed$
DECLARE u uuid:='c3c60000-0000-4000-8000-000000000001';a uuid:='c3c60000-0000-4000-8000-000000000002';c uuid:='c3c60000-0000-4000-8000-000000000003';r uuid:='c3c60000-0000-4000-8000-000000000004';old_c uuid:='c3c60000-0000-4000-8000-000000000005';
 seed jsonb;state jsonb;body jsonb;admission jsonb;source jsonb;old_prepared jsonb;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,c,false);state:=pg_temp.continuation_read(u,c,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 admission:=pg_temp.continuation_admit(u,c,seed,r,body);state:=pg_temp.continuation_read(u,c,seed,r,admission#>>'{child_binding,input_hash}');
 source:=pg_temp.writer_seed(u,old_c);old_prepared:=public.prepare_conversation_meal(u,old_c,pg_temp.writer_resolved(source));
 INSERT INTO continuation_role_fixture VALUES(u,c,r,seed,admission,pg_temp.continuation_preparation(state),old_c,old_prepared);
END $seed$;
GRANT SELECT ON continuation_role_fixture TO service_role;
SET LOCAL ROLE service_role;
DO $actual_service$
DECLARE t record;v jsonb;prepared jsonb;fx jsonb;old_fx jsonb;rejected boolean;protocol text;f text;
BEGIN
 IF current_user<>'service_role' THEN RAISE EXCEPTION 'actual role required, JWT claims alone are insufficient';END IF;
 SELECT * INTO STRICT t FROM pg_temp.continuation_role_fixture;
 -- Unknown registry UUID with recognized protocol must reach the protected
 -- lookup seam under actual service privileges and remain a legacy no-op.
 FOREACH protocol IN ARRAY ARRAY['conversation.command.v1','conversation.clarification.v1'] LOOP
  INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending',jsonb_build_object('kind','meal','command_protocol',protocol,'command_id',gen_random_uuid()),clock_timestamp()+interval '1 hour');
 END LOOP;
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending','{"kind":"meal"}',clock_timestamp()+interval '1 hour');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending',jsonb_build_object('kind','meal','command_id',t.r),clock_timestamp()+interval '1 hour');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending','{"kind":"meal","command_protocol":"conversation.command.v1"}',clock_timestamp()+interval '1 hour');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending',jsonb_build_object('kind','meal','command_id',t.c,'command_protocol','conversation.command.v1'),clock_timestamp()+interval '1 hour');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending',jsonb_build_object('kind','meal','command_id',t.r,'command_protocol','conversation.clarification.v1'),clock_timestamp()+interval '1 hour');
 rejected:=false;BEGIN
  INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending',jsonb_build_object('kind','meal','command_id',t.r,'command_protocol','conversation.command.v1'),clock_timestamp()+interval '1 hour');
 EXCEPTION WHEN serialization_failure THEN rejected:=SQLERRM='conversation_pending_protocol_conflict';END;
 IF NOT rejected THEN RAISE EXCEPTION 'actual service linked child mismatch must refuse';END IF;
 rejected:=false;BEGIN
  INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),t.u,'pending',jsonb_build_object('kind','meal','command_id',t.c,'command_protocol','conversation.clarification.v1'),clock_timestamp()+interval '1 hour');
 EXCEPTION WHEN serialization_failure THEN rejected:=SQLERRM='conversation_pending_protocol_conflict';END;
 IF NOT rejected THEN RAISE EXCEPTION 'actual service linked parent mismatch must refuse';END IF;
 rejected:=false;BEGIN PERFORM 1 FROM private.conversation_meal_command_ids WHERE user_id=t.u;EXCEPTION WHEN insufficient_privilege THEN rejected:=true;END;
 IF NOT rejected OR has_table_privilege(current_user,'private.conversation_meal_command_ids','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'protected seam must not grant private-table access';END IF;
 FOREACH f IN ARRAY ARRAY['public.read_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text)',
  'public.admit_conversation_meal_reply(uuid,uuid,uuid,text,text,uuid,jsonb)','public.read_conversation_meal_continuation_nutrition_source(uuid,uuid,text,text)',
  'public.prepare_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text,jsonb)','public.commit_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text,text)'] LOOP
  IF NOT has_function_privilege(current_user,f,'EXECUTE') OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE') THEN RAISE EXCEPTION 'actual five wrapper ACL regression';END IF;
 END LOOP;
 v:=public.read_conversation_meal_continuation(t.u,t.c,(t.parent_seed#>>'{terminal,epoch}')::uuid,t.parent_seed#>>'{terminal,input_hash}',t.r,t.admission#>>'{child_binding,input_hash}');
 IF v->>'action'<>'available' OR v#>>'{reply,binding,command_id}'<>t.r::text THEN RAISE EXCEPTION 'actual service read not source-bound';END IF;
 prepared:=public.prepare_conversation_meal_continuation(t.u,t.c,(t.parent_seed#>>'{terminal,epoch}')::uuid,t.parent_seed#>>'{terminal,input_hash}',t.r,t.admission#>>'{child_binding,input_hash}',t.preparation);
 fx:=public.commit_conversation_meal_continuation(t.u,t.c,(t.parent_seed#>>'{terminal,epoch}')::uuid,t.parent_seed#>>'{terminal,input_hash}',t.r,t.admission#>>'{child_binding,input_hash}',prepared#>>'{stored,prepared_hash}');
 IF prepared->>'action'<>'prepared' OR fx->>'action'<>'committed' THEN RAISE EXCEPTION 'actual service linked writer must commit';END IF;
 IF public.commit_conversation_meal_continuation(t.u,t.c,(t.parent_seed#>>'{terminal,epoch}')::uuid,t.parent_seed#>>'{terminal,input_hash}',t.r,t.admission#>>'{child_binding,input_hash}','obsolete')<>jsonb_set(fx,'{action}','"replay"') THEN RAISE EXCEPTION 'actual service first-winner replay changed';END IF;
 old_fx:=public.commit_conversation_meal(t.u,t.old_c,t.old_prepared->>'resolved_hash');
 IF old_fx->>'action'<>'committed' OR old_fx#>>'{receipt,schema}'<>'conversation.meal-effect.v1' THEN RAISE EXCEPTION 'actual service old writer compatibility';END IF;
END $actual_service$;
SET LOCAL ROLE NONE;
DO $$ DECLARE u uuid:='c3c60000-0000-4000-8000-000000000001';BEGIN
 PERFORM pg_temp.writer_ok((SELECT count(*)=2 FROM public.meal_logs WHERE user_id=u) AND (SELECT count(*)=7 FROM public.pending_registrations WHERE user_id=u AND status='pending')
  AND (SELECT count(*)=1 FROM private.conversation_meal_fulfillments WHERE user_id=u),'actual service legacy pending and both writers preserve exact row counts');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS continuation_actual_role_assertions FROM meal_writer_assertions;
ROLLBACK;

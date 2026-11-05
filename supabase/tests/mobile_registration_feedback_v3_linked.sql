-- Actual existing linked writer, then new canonical metadata only. Roll back all.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_continuation_fixture.sql
CREATE TEMP TABLE linked_v3_assertions(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.linked_v3_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'LINKED_V3_ASSERT:%',label;END IF;INSERT INTO linked_v3_assertions VALUES(label);END $$;
CREATE FUNCTION pg_temp.linked_v3_register(u uuid,a uuid,parent_id uuid,child_id uuid,new_owner boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE seed jsonb;s jsonb;body jsonb;admitted jsonb;prepared jsonb;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,parent_id,false,new_owner);s:=pg_temp.continuation_read(u,parent_id,seed);
 body:=pg_temp.continuation_body(s,'{"kind":"meal_type","meal_type":"almoco"}');admitted:=pg_temp.continuation_admit(u,parent_id,seed,child_id,body);
 s:=pg_temp.continuation_read(u,parent_id,seed,child_id,admitted#>>'{child_binding,input_hash}');
 prepared:=pg_temp.continuation_prepare(u,parent_id,seed,child_id,admitted#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(s));
 RETURN pg_temp.continuation_commit(u,parent_id,seed,child_id,admitted#>>'{child_binding,input_hash}',prepared#>>'{stored,prepared_hash}');END $$;
CREATE TEMP TABLE linked_v3_actual_golden(context jsonb,feedback jsonb);
DO $linked$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000100';a uuid:='139f0000-0000-4000-8000-000000000101';parent_id uuid:='139f0000-0000-4000-8000-000000000102';child_id uuid:='139f0000-0000-4000-8000-000000000103';
 parent2 uuid:='139f0000-0000-4000-8000-000000000104';child2 uuid:='139f0000-0000-4000-8000-000000000105';x jsonb;c jsonb;f jsonb;r uuid;before_state jsonb;
BEGIN
 x:=pg_temp.linked_v3_register(u,a,parent_id,child_id,true);r:=(x#>>'{fulfillment,receipt,registration_id}')::uuid;
 PERFORM pg_temp.linked_v3_ok(x->>'action'='committed','actual linked domain writer commits');
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';
 PERFORM pg_temp.linked_v3_ok(c#>>'{source,command,receipt,schema}'='conversation.meal-continuation-effect.v1' AND c#>>'{source,command,continuation,parentBinding,command_id}'=parent_id::text AND c#>>'{source,command,command_id}'=child_id::text,'capture retains actual linked parent/child bindings');
 PERFORM pg_temp.linked_v3_ok(c#>>'{source,capture,confirmed,proposal,command_protocol}'='conversation.clarification.v1' AND c#>>'{source,command,receipt,provider_key}'='conversation.clarification/'||u||'/'||parent_id,'linked original is never relabelled direct command/provider');
 f:=jsonb_build_object('schema','registration.feedback.v3','registration_id',r,'local_date',c->'local_date','locale','pt-BR','assistant','Flow AI','registration',c->'record','day',NULL,'block',jsonb_build_object('status','protected'),'guidance','unavailable','education',jsonb_build_object('status','unavailable'));
 PERFORM private.assert_registration_feedback_v3_sources(f,c);
 before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.linked_v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',jsonb_set(c,'{source,command,continuation,parentBinding,command_id}',to_jsonb(child_id)),f)='{"action":"source_conflict"}'::jsonb AND pg_temp.semantic_owner_state(u)=before_state,'changed parent source refuses fresh seal with no effects');
 PERFORM pg_temp.linked_v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f)=jsonb_build_object('action','committed','feedback',f),'linked original seals canonical v3');
 INSERT INTO linked_v3_actual_golden VALUES(c,f);
 PERFORM pg_temp.linked_v3_ok(public.commit_conversation_meal_feedback_v2(u,child_id,NULL,NULL)='{"action":"event_conflict"}'::jsonb,'late linked v2 sealer observes v3 fence');
 -- A second legitimate meal of the same kind retains its own effect identity.
 x:=pg_temp.linked_v3_register(u,a,parent2,child2,false);r:=(x#>>'{fulfillment,receipt,registration_id}')::uuid;
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';
 f:=jsonb_build_object('schema','registration.feedback.v2','registration_id',r,'local_date',c->'local_date','locale','pt-BR','assistant','Flow AI','registration',c->'record','day',NULL,'block',jsonb_build_object('status','unavailable'),'guidance','unavailable','education',jsonb_build_object('status','unavailable'));
 PERFORM pg_temp.linked_v3_ok(public.commit_conversation_meal_feedback_v2(u,child2,x#>>'{fulfillment,receipt,effect_version}',f)->>'action'='committed','actual old linked frozen v2 remains compatible');
 PERFORM pg_temp.linked_v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'canonical old linked v2 returned byte-exact');
 PERFORM pg_temp.linked_v3_ok((SELECT count(*)=2 FROM public.meal_logs WHERE user_id=u) AND (SELECT count(*)=2 FROM private.mobile_registration_feedback_claims WHERE user_id=u),'two legitimate equal linked meals remain two events');
END $linked$;
SELECT jsonb_build_object('linked_v3_actual_golden',jsonb_agg(to_jsonb(g))) FROM linked_v3_actual_golden g;
SELECT count(*) FROM linked_v3_assertions;
ROLLBACK;

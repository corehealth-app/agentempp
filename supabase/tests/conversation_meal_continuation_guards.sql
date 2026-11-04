BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_continuation_fixture.sql
\ir fixtures/conversation_meal_continuation_quantity_golden.sql
DO $guards$
DECLARE u uuid:='c3c30000-0000-4000-8000-000000000001';a uuid:='c3c30000-0000-4000-8000-000000000002';
 c uuid:='c3c30000-0000-4000-8000-000000000003';r uuid:='c3c30000-0000-4000-8000-000000000004';
 seed jsonb;state jsonb;body jsonb;admit jsonb;prep jsonb;v jsonb;before_state jsonb;bad jsonb;rejected boolean;row record;t text;isolation text;
BEGIN
 FOR row IN SELECT * FROM continuation_quantity_golden LOOP
  PERFORM pg_temp.writer_ok(private.conversation_continuation_quantity_reference(row.name) IS NOT DISTINCT FROM nullif(row.reference,'null'::jsonb),
   'actual TypeScript reference parity '||row.name);
 END LOOP;
 FOR row IN SELECT * FROM continuation_conversion_golden LOOP
  v:=jsonb_build_object('food_index',0,'allowed_units',jsonb_build_array(row.unit),'quantity_reference',private.conversation_continuation_quantity_reference(row.name));
  PERFORM pg_temp.writer_ok(private.conversation_continuation_grams(jsonb_build_object('kind','quantity','food_index',0,'amount',row.amount,'unit',row.unit),v) IS NOT DISTINCT FROM row.quantity_g,
   'JS mass/reference conversion parity '||row.name||' '||row.unit||' '||row.amount::text);
 END LOOP;
 seed:=pg_temp.continuation_seed(u,a,c,false);state:=pg_temp.continuation_read(u,c,seed);
 PERFORM pg_temp.writer_ok(state#>>'{head,question,kind}'='meal_type' AND state#>'{head,question,food_name}'='null'::jsonb
  AND state#>'{head,question,food_index}'='null'::jsonb AND state#>'{head,question,allowed_units}'='[]'::jsonb,'meal-type question never invents a meal window or occurrence');
 body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 FOREACH bad IN ARRAY ARRAY[body||'{"extra":true}',jsonb_set(body,'{expected_revision}','-1'),jsonb_set(body,'{expected_revision}','0.5'),
  jsonb_set(body,'{answer}','{"kind":"meal_type","meal_type":"breakfast"}'),jsonb_set(body,'{answer}','{"kind":"quantity","food_index":0,"amount":0,"unit":"g"}'),
  jsonb_set(body,'{answer}','{"kind":"quantity","food_index":30,"amount":100,"unit":"g"}'),jsonb_set(body,'{answer}','{"kind":"quantity","food_index":0,"amount":100,"unit":"cup"}'),
  jsonb_set(body,'{question_key}','null'),jsonb_set(body,'{answer}','null')]
 LOOP
  before_state:=pg_temp.semantic_owner_state(u);rejected:=false;
  BEGIN PERFORM pg_temp.continuation_admit(u,c,seed,r,bad);EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
  PERFORM pg_temp.writer_ok(rejected AND pg_temp.semantic_owner_state(u)=before_state,'malformed closed reply no writes '||bad::text);
 END LOOP;
 before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(public.admit_conversation_meal_reply(u,c,gen_random_uuid(),seed#>>'{terminal,input_hash}',seed#>>'{decision,decision_hash}',r,body)='{"action":"stale_epoch"}'::jsonb
  AND public.admit_conversation_meal_reply(u,c,(seed#>>'{terminal,epoch}')::uuid,repeat('0',64),seed#>>'{decision,decision_hash}',r,body)='{"action":"input_conflict"}'::jsonb
  AND public.admit_conversation_meal_reply(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',repeat('0',64),r,body)='{"action":"decision_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'actual original epoch input and decision cannot be replaced');
 -- Numeric-scale inputs follow the actual RPC, not merely a validator.
 body:=jsonb_set(body,'{expected_revision}','0.0');admit:=pg_temp.continuation_admit(u,c,seed,r,body);
 state:=pg_temp.continuation_read(u,c,seed,r,admit#>>'{child_binding,input_hash}');prep:=pg_temp.continuation_preparation(state);
 PERFORM pg_temp.writer_ok(admit->>'action'='admitted','numeric scale revision0.0 accepted by real admission');
 FOREACH bad IN ARRAY ARRAY[prep||'{"extra":true}',jsonb_set(prep,'{parent_ref,source_hash}',to_jsonb(repeat('0',64))),
  jsonb_set(prep,'{materialization,source_groups,0,source_positions,0,name,start}','0'),jsonb_set(prep,'{materialization,source_groups}','[]'),
  jsonb_set(prep,'{meal,items,0,input_indexes}','[]'),jsonb_set(prep,'{materialization,nutrition_label}','{}'),
  jsonb_set(prep,'{materialization,input_hash}',to_jsonb(repeat('0',64))),jsonb_set(prep,'{meal,meal_type}','"jantar"')]
 LOOP
  before_state:=pg_temp.semantic_owner_state(u);rejected:=false;
  BEGIN PERFORM pg_temp.continuation_prepare(u,c,seed,r,admit#>>'{child_binding,input_hash}',bad);EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;END;
  PERFORM pg_temp.writer_ok(rejected AND pg_temp.semantic_owner_state(u)=before_state,'malformed linked preparation no writes '||md5(bad::text));
 END LOOP;
 -- Catalog/config/correction binding is captured BEFORE any calculation and
 -- includes miss lookups. A changed catalog must refuse even identical macros.
 before_state:=pg_temp.semantic_owner_state(u);
 UPDATE private.conversation_food_catalog_revision SET revision=revision+1,epoch=gen_random_uuid() WHERE singleton;
 PERFORM pg_temp.writer_ok(pg_temp.continuation_prepare(u,c,seed,r,admit#>>'{child_binding,input_hash}',prep)='{"action":"source_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'authority drift does not reinterpret or prepare original evidence');
 -- Pending rows outside a proven conversation identity remain untouched.
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),u,'pending','{"kind":"meal"}',clock_timestamp()+interval '1 hour');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),u,'pending',jsonb_build_object('kind','meal','command_id',gen_random_uuid()),clock_timestamp()+interval '1 hour');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),u,'pending',jsonb_build_object('kind','meal','command_id',r),clock_timestamp()+interval '1 hour');
 rejected:=false;BEGIN
  INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(gen_random_uuid(),u,'confirmed',
   jsonb_build_object('kind','meal','command_id',r,'command_protocol','conversation.command.v1'),clock_timestamp());
 EXCEPTION WHEN serialization_failure THEN rejected:=SQLERRM='conversation_pending_protocol_conflict';END;
 PERFORM pg_temp.writer_ok(rejected AND (SELECT count(*)=3 FROM public.pending_registrations WHERE user_id=u),'exact proven command protocol guard preserves unrelated legacy forms including unlinked metadata');
END $guards$;
-- ACL includes every new private function/table; no direct grants to service.
DO $acl$
DECLARE f record;t record;role text;
BEGIN
 FOR t IN SELECT c.oid,n.nspname,c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='private' AND c.relname IN('conversation_meal_reply_ids','conversation_meal_continuation_heads','conversation_meal_replies','conversation_meal_continuation_preparations','conversation_meal_fulfillments') LOOP
  PERFORM pg_temp.writer_ok(t.relrowsecurity,'RLS private '||t.relname);
  FOREACH role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.writer_ok(NOT has_table_privilege(role,t.oid,'SELECT,INSERT,UPDATE,DELETE'),'no direct table access '||role||' '||t.relname);
  END LOOP;
 END LOOP;
 FOR f IN SELECT p.oid,n.nspname,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='private' AND (p.proname LIKE 'conversation_continuation_%' OR p.proname IN('lock_conversation_continuation','assert_conversation_meal_reply','assert_conversation_continuation_materialization','assert_conversation_continuation_preparation','fence_conversation_pending_protocol','guard_conversation_continuation_delete','conversation_pending_protocol_conflicts')))
  OR (n.nspname='public' AND p.proname IN('read_conversation_meal_continuation','admit_conversation_meal_reply','read_conversation_meal_continuation_nutrition_source','prepare_conversation_meal_continuation','commit_conversation_meal_continuation')) LOOP
  FOREACH role IN ARRAY ARRAY['anon','authenticated'] LOOP PERFORM pg_temp.writer_ok(NOT has_function_privilege(role,f.oid,'EXECUTE'),'RPC denied '||role||' '||f.proname);END LOOP;
  PERFORM pg_temp.writer_ok(has_function_privilege('service_role',f.oid,'EXECUTE')=(f.nspname='public' OR f.proname='conversation_pending_protocol_conflicts'),'only five trusted public wrappers plus protected boolean pending seam '||f.proname);
 END LOOP;
END $acl$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS continuation_guard_assertions FROM meal_writer_assertions;
ROLLBACK;

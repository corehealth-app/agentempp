BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}'; SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_edit_fixture.sql
DO $many$
DECLARE u uuid:='c3ec0000-0000-4000-8000-000000000001';a uuid:='c3ec0000-0000-4000-8000-000000000002';c uuid:='c3ec0000-0000-4000-8000-000000000003';
 op uuid:='c3ec0000-0000-4000-8000-000000000004';undo_id uuid:='c3ec0000-0000-4000-8000-000000000005';
 effect jsonb;state jsonb;old_state jsonb;input jsonb;undo_input jsonb;v jsonb;undone jsonb;before_save jsonb;before_failure jsonb;anchor uuid;refused boolean;
BEGIN
 effect:=pg_temp.edit_seed(u,a,c);anchor:=(effect#>>'{log_ids,0}')::uuid;
 INSERT INTO public.food_db(id,name_pt,source,is_verified,source_ref,kcal_per_100g,protein_g,carbs_g,fat_g)
 VALUES(2140000090,'synthetic edit reference','synthetic',true,'synthetic:meal-edit',130.04,2.31,28.21,0.21);
 UPDATE public.meal_logs SET source='canonical_exact',food_db_id=2140000090,confidence=0.93,image_url='synthetic-private-image',raw_message_id=a WHERE id=anchor;
 PERFORM public.register_meal_atomic(u,(effect->>'local_date')::date,'almoco','[{"food_name":"retained sibling","quantity_g":50,"kcal":50,"protein_g":2,"carbs_g":5,"fat_g":1,"source":"product_label","food_db_id":null,"confidence":0.91}]',false,NULL,(effect->>'consumed_at')::timestamptz,effect->>'provider_key',NULL,NULL);
 UPDATE public.daily_snapshots SET calories_target=NULL,protein_target=NULL,xp_earned=40,deficit_accumulated=321,water_consumed_ml=1100 WHERE user_id=u;
 state:=public.read_conversation_meal_edit_state(u,c);
 PERFORM pg_temp.writer_ok(NOT(state->>'lineage_compatible')::boolean
  AND public.undo_conversation_meal_registration(u,c,gen_random_uuid(),pg_temp.edit_input('undo_registration',0),state->'current_state','changed-original')->>'action'='version_conflict','original undo rejects any full original group drift');
 before_save:=pg_temp.edit_fingerprint(u);
 input:=pg_temp.edit_input('save',0,anchor)||'{"items":[{"food_name":"arroz split","quantity_g":60},{"food_name":"feijao split","quantity_g":50}]}';
 v:=public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',
 '[{"food_name":"arroz split","quantity_g":60,"kcal":80,"protein_g":1,"carbs_g":16,"fat_g":0.2,"source":"user_kcal","food_db_id":null,"confidence":null},{"food_name":"feijao split","quantity_g":50,"kcal":50,"protein_g":3,"carbs_g":8,"fat_g":0.1,"source":"user_kcal","food_db_id":null,"confidence":null}]','recalculated',NULL,'save-one-to-many');
 PERFORM pg_temp.writer_ok(v->>'action'='committed' AND jsonb_array_length(v#>'{receipt,new_item_ids}')=2 AND (SELECT count(*)=3 FROM public.meal_logs WHERE user_id=u),'actual C11 one to many retains sibling');
 state:=public.read_conversation_meal_edit_state(u,c);old_state:=state;
 undo_input:=pg_temp.edit_input('undo_save',1,NULL,op);
 before_failure:=pg_temp.edit_fingerprint(u);refused:=false;
 BEGIN
  DELETE FROM public.food_db WHERE id=2140000090;
  PERFORM public.undo_conversation_meal_item_edit(u,c,undo_id,undo_input,state->'current_state','missing-reference');
 EXCEPTION WHEN raise_exception THEN refused:=SQLERRM='invalid meal item provenance: unknown food_db_id';END;
 PERFORM pg_temp.writer_ok(refused AND pg_temp.edit_fingerprint(u)=before_failure,'missing original reference rolls back finite removal and has no fallback');
 PERFORM public.register_meal_atomic(u,(effect->>'local_date')::date,'lanche','[{"food_name":"independent append","quantity_g":20,"kcal":20,"protein_g":1,"carbs_g":2,"fat_g":0.3,"source":"product_label","food_db_id":null,"confidence":null}]',false,NULL,clock_timestamp(),'synthetic-independent-edit-append',NULL,NULL);
 before_failure:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_item_edit(u,c,undo_id,undo_input,old_state->'current_state','stale-before-append')->>'action'='version_conflict'
  AND pg_temp.edit_fingerprint(u)=before_failure,'stale whole snapshot CAS refuses without mutation');
 state:=public.read_conversation_meal_edit_state(u,c);
 undone:=public.undo_conversation_meal_item_edit(u,c,undo_id,undo_input,state->'current_state','fresh-after-append');
 PERFORM pg_temp.writer_ok(undone->>'action'='committed' AND jsonb_array_length(undone#>'{receipt,removed_item_ids}')=2
  AND jsonb_array_length(undone#>'{receipt,new_item_ids}')=1,'undo replaces all output IDs with server held single beforeimage');
 PERFORM pg_temp.writer_ok((SELECT jsonb_agg(to_jsonb(m)-ARRAY['id','created_at'] ORDER BY food_name) FROM public.meal_logs m WHERE user_id=u AND raw_provider_message_id=effect->>'provider_key')
  =(SELECT jsonb_agg(x-ARRAY['id','created_at'] ORDER BY x->>'food_name') FROM jsonb_array_elements(before_save->'logs') x),'restores exact reference confidence origin and untouched sibling');
 PERFORM pg_temp.writer_ok((SELECT count(*)=3 FROM public.meal_logs WHERE user_id=u)
  AND (SELECT calories_consumed=200 AND calories_target IS NULL AND protein_target IS NULL AND exercise_calories=300 AND xp_earned=40 AND deficit_accumulated=321 AND water_consumed_ml=1100 FROM public.daily_snapshots WHERE user_id=u),'current totals retain independent append and all nullable target protected fields');
 state:=public.read_conversation_meal_edit_state(u,c);anchor:=(undone#>>'{receipt,new_item_ids,0}')::uuid;
 -- Legacy C11 then replaces the same facts with a new physical UUID.
 v:=public.mutate_mobile_confirmed_meal(u,'synthetic-external-c11','PATCH','/api/mobile/v1/meal-records/'||anchor,repeat('b',64),anchor,'v1:'||repeat('a',64),ARRAY[anchor],state->'current_state',
 '[{"food_name":"arroz sintetico","quantity_g":100,"kcal":130.04,"protein_g":2.31,"carbs_g":28.21,"fat_g":0.21,"source":"canonical_exact","food_db_id":2140000090,"confidence":0.93}]','recalculated',NULL,'external-edit-back');
 state:=public.read_conversation_meal_edit_state(u,c);
 PERFORM pg_temp.writer_ok(v->>'action'='completed' AND NOT(state->>'lineage_compatible')::boolean
  AND public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',2,NULL,op),state->'current_state','obsolete-external')->>'action'='version_conflict','external C11 equal facts with new IDs cannot revive old undo');
END $many$;

DO $expired$
DECLARE u uuid:='c3ec0000-0000-4000-8000-000000000011';a uuid:='c3ec0000-0000-4000-8000-000000000012';c uuid:='c3ec0000-0000-4000-8000-000000000013';
 op uuid:='c3ec0000-0000-4000-8000-000000000014';state jsonb;before_state jsonb;zone text;
BEGIN
 zone:=CASE WHEN extract(hour FROM clock_timestamp() AT TIME ZONE 'UTC') BETWEEN 1 AND 22 THEN 'UTC' ELSE 'Etc/GMT+12' END;
 PERFORM pg_temp.edit_seed(u,a,c,clock_timestamp()-interval '6 minutes',zone);
 state:=public.read_conversation_meal_edit_state(u,c);before_state:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_registration(u,c,op,pg_temp.edit_input('undo_registration',0),state->'current_state','initial-expired')->>'action'='undo_expired'
  AND pg_temp.edit_fingerprint(u)=before_state,'initial deadline uses actual FX committed clock not admission or log creation');
 PERFORM pg_temp.edit_deadline_fixture(u,c,op,clock_timestamp());
 state:=public.read_conversation_meal_edit_state(u,c);before_state:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',1,NULL,op),state->'current_state','save-expired')->>'action'='undo_expired'
  AND pg_temp.edit_fingerprint(u)=before_state,'save deadline inclusive at or after expiry');
 UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=u;
 state:=public.read_conversation_meal_edit_state(u,c);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',1,NULL,op),state->'current_state','closed-day')->>'action'='day_closed','closed day refuses even with full fresh CAS');
END $expired$;

CREATE FUNCTION pg_temp.reject_edit_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF current_setting('performe.qa_reject_edit_audit',true)='on' THEN RAISE EXCEPTION 'synthetic_mandatory_edit_audit_failure';END IF;RETURN NEW;END $$;
CREATE TRIGGER synthetic_reject_edit_audit BEFORE INSERT ON private.conversation_meal_edit_operations FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_edit_audit();
DO $rollback$
DECLARE u uuid:='c3ec0000-0000-4000-8000-000000000021';a uuid:='c3ec0000-0000-4000-8000-000000000022';c uuid:='c3ec0000-0000-4000-8000-000000000023';
 effect jsonb;state jsonb;before_state jsonb;input jsonb;refused boolean;anchor uuid;
BEGIN
 effect:=pg_temp.edit_seed(u,a,c);anchor:=(effect#>>'{log_ids,0}')::uuid;state:=public.read_conversation_meal_edit_state(u,c);before_state:=pg_temp.edit_fingerprint(u);
 input:=pg_temp.edit_input('save',0,anchor);PERFORM set_config('performe.qa_reject_edit_audit','on',true);refused:=false;
 BEGIN PERFORM public.commit_conversation_meal_item_edit(u,c,gen_random_uuid(),input,state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','fail-after-domain');
 EXCEPTION WHEN raise_exception THEN refused:=SQLERRM='synthetic_mandatory_edit_audit_failure';END;
 PERFORM pg_temp.writer_ok(refused AND pg_temp.edit_fingerprint(u)=before_state,'mandatory audit failure rolls back domain C11 ledger head identity and receipt');
 refused:=false;BEGIN PERFORM public.undo_conversation_meal_registration(u,c,gen_random_uuid(),pg_temp.edit_input('undo_registration',0),state->'current_state','fail-after-delete');
 EXCEPTION WHEN raise_exception THEN refused:=SQLERRM='synthetic_mandatory_edit_audit_failure';END;
 PERFORM pg_temp.writer_ok(refused AND pg_temp.edit_fingerprint(u)=before_state,'mandatory compensation receipt failure rolls back initial finite delete');
 PERFORM set_config('performe.qa_reject_edit_audit','off',true);
END $rollback$;
DO $external$
DECLARE u uuid:='c3ec0000-0000-4000-8000-000000000031';a uuid:='c3ec0000-0000-4000-8000-000000000032';c uuid:='c3ec0000-0000-4000-8000-000000000033';
 op uuid:='c3ec0000-0000-4000-8000-000000000034';other_command uuid:='c3ec0000-0000-4000-8000-000000000039';
 effect jsonb;state jsonb;input jsonb;v jsonb;source jsonb;prepared jsonb;anchor uuid;before_state jsonb;refused boolean;
BEGIN
 effect:=pg_temp.edit_seed(u,a,c);anchor:=(effect#>>'{log_ids,0}')::uuid;state:=public.read_conversation_meal_edit_state(u,c);input:=pg_temp.edit_input('save',0,anchor);
 UPDATE public.users SET auth_user_id=NULL WHERE id=u;before_state:=pg_temp.edit_fingerprint(u);refused:=false;
 BEGIN PERFORM public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','missing-auth-link');EXCEPTION WHEN serialization_failure THEN refused:=true;END;
 PERFORM pg_temp.writer_ok(refused AND pg_temp.edit_fingerprint(u)=before_state,'actual auth link required without domain effects');
 UPDATE public.users SET auth_user_id=a WHERE id=u;state:=public.read_conversation_meal_edit_state(u,c);before_state:=pg_temp.edit_fingerprint(u);refused:=false;
 BEGIN PERFORM public.commit_conversation_meal_item_edit(u,c,op,input||'{"unexpected":true}',state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','invalid-shape');EXCEPTION WHEN invalid_parameter_value THEN refused:=true;END;
 PERFORM pg_temp.writer_ok(refused AND pg_temp.edit_fingerprint(u)=before_state,'closed original intent unknown keys rejected');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_item_edit(u,c,op,input||jsonb_build_object('record_id','c3ec0000-0000-4000-8000-000000000001'),state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','foreign-anchor')->>'action'='version_conflict'
  AND pg_temp.edit_fingerprint(u)=before_state,'foreign or missing anchor cannot mutate command group');
 PERFORM public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','save-before-external');
 state:=public.read_conversation_meal_edit_state(u,c);anchor:=(state#>>'{current_state,items,0,id}')::uuid;
 v:=public.mutate_mobile_confirmed_meal(u,'synthetic-active-external','PATCH','/api/mobile/v1/meal-records/'||anchor,repeat('b',64),anchor,'v1:'||repeat('a',64),ARRAY[anchor],state->'current_state',pg_temp.edit_quantity(),'recalculated',NULL,'same-facts-new-ID');
 state:=public.read_conversation_meal_edit_state(u,c);before_state:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(v->>'action'='completed' AND NOT(state->>'lineage_compatible')::boolean
  AND public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',1,NULL,op),state->'current_state','external-obsolete')->>'action'='version_conflict'
  AND pg_temp.edit_fingerprint(u)=before_state,'active Save undo rejects external C11 edit back to equal facts');
 anchor:=(state#>>'{current_state,items,0,id}')::uuid;
 PERFORM public.mutate_mobile_confirmed_meal(u,'synthetic-active-external-delete','DELETE','/api/mobile/v1/meal-records/'||anchor,repeat('b',64),anchor,'v1:'||repeat('a',64),ARRAY[anchor],state->'current_state',NULL,NULL,NULL,'external-delete');
 before_state:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',1,NULL,op),state->'current_state','deleted-group')->>'action'='version_conflict'
  AND pg_temp.edit_fingerprint(u)=before_state,'external group deletion never recreates guessed original facts');
 source:=pg_temp.writer_seed(u,other_command);prepared:=public.prepare_conversation_meal(u,other_command,pg_temp.writer_resolved(source));
 v:=public.commit_conversation_meal(u,other_command,prepared->>'resolved_hash');
 state:=public.read_conversation_meal_edit_state(u,other_command);anchor:=(v#>>'{receipt,log_ids,0}')::uuid;
 v:=public.commit_conversation_meal_item_edit(u,other_command,op,pg_temp.edit_input('save',0,anchor),state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','same-op-different-command');
 PERFORM pg_temp.writer_ok(v->>'action'='committed' AND (SELECT count(*)=2 FROM private.conversation_meal_edit_ids WHERE user_id=u AND operation_id=op)
  AND (SELECT count(*)=2 FROM public.mobile_api_idempotency WHERE user_id=u AND idempotency_key LIKE 'cmeal-edit1:%:'||op::text||':save'),'internal C11 identity includes command and operation');
END $external$;
CREATE FUNCTION pg_temp.delay_edit_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF current_setting('performe.qa_delay_edit_audit',true)='on' THEN PERFORM pg_sleep(0.3);END IF;RETURN NEW;END $$;
CREATE TRIGGER synthetic_delay_edit_audit BEFORE INSERT ON private.conversation_meal_edit_operations FOR EACH ROW EXECUTE FUNCTION pg_temp.delay_edit_audit();
DO $terminal_clock$
DECLARE u uuid:='c3ec0000-0000-4000-8000-000000000041';a uuid:='c3ec0000-0000-4000-8000-000000000042';c uuid:='c3ec0000-0000-4000-8000-000000000043';
 op uuid:='c3ec0000-0000-4000-8000-000000000044';state jsonb;before_state jsonb;refused boolean:=false;
BEGIN
 PERFORM pg_temp.edit_seed(u,a,c);PERFORM pg_temp.edit_deadline_fixture(u,c,op,clock_timestamp()+interval '200 milliseconds');
 state:=public.read_conversation_meal_edit_state(u,c);before_state:=pg_temp.edit_fingerprint(u);PERFORM set_config('performe.qa_delay_edit_audit','on',true);
 BEGIN PERFORM public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',1,NULL,op),state->'current_state','deadline-crosses-audit');
 EXCEPTION WHEN serialization_failure THEN refused:=SQLERRM='conversation_meal_edit_deadline_passed';END;
 PERFORM pg_temp.writer_ok(refused AND pg_temp.edit_fingerprint(u)=before_state,'deadline crossed during mandatory audit publication rolls back whole compensation');
 PERFORM set_config('performe.qa_delay_edit_audit','off',true);
END $terminal_clock$;
DO $original_group$
DECLARE u uuid:='c3ec0000-0000-4000-8000-000000000051';a uuid:='c3ec0000-0000-4000-8000-000000000052';c uuid:='c3ec0000-0000-4000-8000-000000000053';
 source jsonb;resolved jsonb;prepared jsonb;effect jsonb;state jsonb;original jsonb;v jsonb;
BEGIN
 INSERT INTO auth.users(id) VALUES(a);INSERT INTO public.users(id,auth_user_id,status,timezone,country,country_confirmed) VALUES(u,a,'active','UTC','BR',true);
 PERFORM public.admit_conversation_meal_command(u,pg_temp.writer_input(c)||jsonb_build_object('source',jsonb_build_object('channel','text','text','Comi 100g de arroz e 50g de feijao sinteticos')));
 source:=public.capture_conversation_meal_source(u,c);resolved:=pg_temp.writer_resolved(source);
 resolved:=jsonb_set(resolved,'{items}',(resolved->'items')||jsonb_build_array((resolved#>'{items,0}')||'{"name":"feijao sintetico","quantity_g":50,"kcal":50,"protein_g":3,"carbs_g":8,"fat_g":0.1,"input_indexes":[1]}'));
 resolved:=jsonb_set(resolved,'{semantic_proof,input_count}','2');resolved:=jsonb_set(resolved,'{totals}','{"kcal":180,"protein_g":5.3,"carbs_g":36.2,"fat_g":0.3}');
 prepared:=public.prepare_conversation_meal(u,c,resolved);effect:=public.commit_conversation_meal(u,c,prepared->>'resolved_hash');original:=pg_temp.edit_fingerprint(u)->'effects';
 PERFORM public.register_meal_atomic(u,(effect#>>'{receipt,local_date}')::date,'lanche','[{"food_name":"other registration","quantity_g":50,"kcal":50,"protein_g":1,"carbs_g":8,"fat_g":0.2,"source":"product_label","food_db_id":null,"confidence":null}]',false,NULL,clock_timestamp(),'synthetic-other-original-undo',NULL,NULL);
 state:=public.read_conversation_meal_edit_state(u,c);v:=public.undo_conversation_meal_registration(u,c,gen_random_uuid(),pg_temp.edit_input('undo_registration',0),state->'current_state','full-original-group-undo');
 PERFORM pg_temp.writer_ok(effect->>'action'='committed' AND jsonb_array_length(effect#>'{receipt,log_ids}')=2
  AND v->>'action'='committed' AND jsonb_array_length(v#>'{receipt,removed_item_ids}')=2
  AND (SELECT count(*)=1 AND min(food_name)='other registration' FROM public.meal_logs WHERE user_id=u),'initial undo removes exact whole original group and retains independent registration');
 PERFORM pg_temp.writer_ok((SELECT calories_consumed=50 AND protein_g=1 AND carbs_g=8 AND fat_g=0.2 AND calories_target IS NULL AND protein_target IS NULL FROM public.daily_snapshots WHERE user_id=u)
  AND pg_temp.edit_fingerprint(u)->'effects'=original,'initial undo recomputes current sums and preserves NULL targets and original FX');
END $original_group$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS edit_guard_assertions FROM meal_writer_assertions;
ROLLBACK;

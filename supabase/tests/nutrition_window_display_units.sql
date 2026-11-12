-- Synthetic rollback qualification of the actual readonly RPC and existing writers.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_edit_fixture.sql
ALTER FUNCTION pg_temp.writer_input(uuid,text) RENAME TO nutrition_base_input;
ALTER FUNCTION pg_temp.writer_resolved(jsonb) RENAME TO nutrition_base_resolved;
CREATE FUNCTION pg_temp.writer_input(c uuid,channel text DEFAULT 'text') RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_set(pg_temp.nutrition_base_input(c,channel),'{source,text}',to_jsonb(CASE WHEN current_setting('nutrition.fixture.food',true) LIKE 'milk%' THEN 'Bebi 200mL de leite'
  WHEN current_setting('nutrition.fixture.food',true)='whey' THEN 'Tomei 1 medida de whey' ELSE 'Comi 100g de arroz sintetico' END));
$$;
CREATE FUNCTION pg_temp.writer_resolved(source jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb:=pg_temp.nutrition_base_resolved(source);kind text:=current_setting('nutrition.fixture.food',true);grams numeric;name text;unit text;amount numeric;
BEGIN
 IF kind NOT LIKE 'milk%' AND kind<>'whey' THEN RETURN v;END IF;
 grams:=CASE WHEN kind LIKE 'milk%' THEN 206 ELSE 30 END;name:=CASE WHEN kind LIKE 'milk%' THEN 'leite' ELSE 'whey' END;
 unit:=CASE WHEN kind LIKE 'milk%' THEN 'mL' ELSE 'scoop' END;amount:=CASE WHEN kind LIKE 'milk%' THEN 200 ELSE 1 END;
 v:=jsonb_set(v,'{items,0}',jsonb_build_object('name',name,'food_db_id',NULL,'nutrition_source','user_kcal','quantity_g',grams,
  'kcal',120,'protein_g',10,'carbs_g',10,'fat_g',2,'confidence',NULL,'input_indexes','[0]'::jsonb,
  'quantity_basis','portion_reference','display_qty',amount,'display_unit',unit));
 v:=jsonb_set(v,'{totals}','{"kcal":120,"protein_g":10,"carbs_g":10,"fat_g":2}');
 IF kind LIKE 'milk_%' THEN
  v:=jsonb_set(v,'{items,0}',v#>'{items,0}'||'{"kcal":125.7,"protein_g":6.49,"carbs_g":9.89,"fat_g":6.7}');
  v:=jsonb_set(v,'{totals}','{"kcal":125.7,"protein_g":6.5,"carbs_g":9.9,"fat_g":6.7}');
 END IF;
 RETURN v;
END $$;
CREATE TEMP TABLE nutrition_units_golden(stage text,food text,observation jsonb) ON COMMIT DROP;
DO $units$
DECLARE kind text;u uuid;a uuid;c uuid;op uuid;undo_op uuid;original jsonb;state jsonb;body jsonb;calc jsonb;v jsonb;undone jsonb;
 anchor public.meal_logs%ROWTYPE;old_id uuid;new_id uuid;before_read jsonb;after_read jsonb;grams numeric;ratio numeric;units jsonb;refused boolean;
BEGIN
 PERFORM pg_temp.writer_ok(NOT has_function_privilege('anon','public.read_nutrition_window_units(uuid,uuid[])','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.read_nutrition_window_units(uuid,uuid[])','EXECUTE')
  AND has_function_privilege('service_role','public.read_nutrition_window_units(uuid,uuid[])','EXECUTE'),'nutrition units service-only grants');
 FOREACH kind IN ARRAY ARRAY['milk','milk_fractional','milk_binary70','milk_binary110','whey','legacy'] LOOP
  u:=gen_random_uuid();a:=gen_random_uuid();c:=gen_random_uuid();op:=gen_random_uuid();undo_op:=gen_random_uuid();
  PERFORM set_config('nutrition.fixture.food',kind,true);original:=pg_temp.edit_seed(u,a,c);old_id:=(original#>>'{log_ids,0}')::uuid;
  before_read:=pg_temp.edit_fingerprint(u);units:=public.read_nutrition_window_units(u,ARRAY[old_id]);
  PERFORM pg_temp.writer_ok(jsonb_array_length(units->'items')=1 AND units#>>'{items,0,meal,id}'=old_id::text,'nutrition units exact owned current id '||kind);
  IF kind='legacy' THEN
   PERFORM pg_temp.writer_ok(units#>'{items,0,display_quantity}'='null'::jsonb,'legacy has honest grams without a display reference');
  ELSE
   PERFORM pg_temp.writer_ok(units#>>'{items,0,display_quantity,provenance}'='sealed_original'
    AND units#>>'{items,0,display_quantity,unit}'=CASE WHEN kind LIKE 'milk%' THEN 'mL' ELSE 'scoop' END
    AND (units#>>'{items,0,display_quantity,value}')::numeric=CASE WHEN kind LIKE 'milk%' THEN 200 ELSE 1 END
    AND units#>'{items,0,display_quantity,estimated}'='false'::jsonb,'sealed original literal unit '||kind);
  END IF;
  INSERT INTO nutrition_units_golden VALUES('original',kind,units);
  PERFORM pg_temp.writer_ok(public.read_nutrition_window_units(u,ARRAY[old_id])=units AND pg_temp.edit_fingerprint(u)=before_read,'readonly reopen has no domain effect '||kind);
  IF kind<>'legacy' THEN
   SELECT * INTO STRICT anchor FROM public.meal_logs WHERE id=old_id;
   grams:=CASE kind WHEN 'milk' THEN 412 WHEN 'milk_fractional' THEN 185.4 WHEN 'milk_binary70' THEN 72.1 WHEN 'milk_binary110' THEN 113.3 ELSE 40 END;ratio:=grams/anchor.quantity_g;
   state:=public.read_conversation_meal_edit_state(u,c);
   body:=jsonb_build_object('schema','conversation.meal-edit.v1','kind','save','expected_revision',0,'expected_version','v1:'||repeat('a',64),
    'record_id',old_id,'items',jsonb_build_array(jsonb_build_object('food_name',anchor.food_name,'quantity_g',grams)));
   -- The actual quantity-only JS writer rounds kcal to one decimal and macros
   -- to two. Keep the old two-decimal fixture too, to protect legacy proofs.
   calc:=jsonb_build_array(jsonb_build_object('food_name',anchor.food_name,'quantity_g',grams,'kcal',round(anchor.kcal*ratio,CASE WHEN kind LIKE 'milk_%' THEN 1 ELSE 2 END),
    'protein_g',round(anchor.protein_g*ratio,2),'carbs_g',round(anchor.carbs_g*ratio,2),'fat_g',round(anchor.fat_g*ratio,2),
    'source',anchor.source,'food_db_id',anchor.food_db_id,'confidence',anchor.confidence));
   -- Literal outputs of actual reconcilePendingMealEdit, also asserted in TS.
   -- A decimal-only fixture misses these binary64 half-way boundaries.
   IF kind='milk_binary70' THEN
    calc:=jsonb_set(calc,'{0}',calc->0||'{"kcal":44,"protein_g":2.27,"carbs_g":3.46,"fat_g":2.34}');
   ELSIF kind='milk_binary110' THEN
    calc:=jsonb_set(calc,'{0}',calc->0||'{"kcal":69.1,"protein_g":3.57,"carbs_g":5.44,"fat_g":3.68}');
   END IF;
   v:=public.commit_conversation_meal_item_edit(u,c,op,body,state->'current_state',calc,'quantity_only',jsonb_build_object('quantity_g',grams),'nutrition-units-save');
   PERFORM pg_temp.writer_ok(v->>'action'='committed','actual unit quantity edit committed '||kind);
   new_id:=(v#>>'{receipt,new_item_ids,0}')::uuid;units:=public.read_nutrition_window_units(u,ARRAY[new_id]);
   PERFORM pg_temp.writer_ok(new_id<>old_id AND units#>>'{items,0,meal,id}'=new_id::text
    AND units#>>'{items,0,display_quantity,provenance}'='audited_same_food_scale'
    AND units#>'{items,0,display_quantity,estimated}'='true'::jsonb
    AND (units#>>'{items,0,display_quantity,value}')::numeric=CASE kind WHEN 'milk' THEN 400 WHEN 'milk_fractional' THEN 180 WHEN 'milk_binary70' THEN 70 WHEN 'milk_binary110' THEN 110 ELSE 1.333333 END
    AND (units#>>'{items,0,display_quantity,reference,quantity_g}')::numeric=anchor.quantity_g,'current identity gets only approximate sealed ratio '||kind);
   INSERT INTO nutrition_units_golden VALUES('saved',kind,units);
   before_read:=pg_temp.edit_fingerprint(u);
   PERFORM pg_temp.writer_ok(public.read_nutrition_window_units(u,ARRAY[new_id])=units AND pg_temp.edit_fingerprint(u)=before_read,'corrected cold reopen preserves exact metadata without writes '||kind);
   state:=public.read_conversation_meal_edit_state(u,c);
   body:=pg_temp.edit_input('undo_save',1,NULL,op);
   undone:=public.undo_conversation_meal_item_edit(u,c,undo_op,body,state->'current_state','nutrition-units-undo');
   PERFORM pg_temp.writer_ok(undone->>'action'='committed','actual unit Undo committed '||kind);
   new_id:=(undone#>>'{receipt,new_item_ids,0}')::uuid;units:=public.read_nutrition_window_units(u,ARRAY[new_id]);
   PERFORM pg_temp.writer_ok(new_id<>old_id AND units#>>'{items,0,display_quantity,provenance}'='audited_restore'
    AND units#>'{items,0,display_quantity,estimated}'='false'::jsonb
    AND (units#>>'{items,0,display_quantity,value}')::numeric=CASE WHEN kind LIKE 'milk%' THEN 200 ELSE 1 END,'Undo proves literal original unit under new id '||kind);
   INSERT INTO nutrition_units_golden VALUES('undone',kind,units);
   UPDATE public.meal_logs SET food_name=food_name||' preparo diferente' WHERE id=new_id;
   PERFORM pg_temp.writer_ok(public.read_nutrition_window_units(u,ARRAY[new_id])#>'{items,0,display_quantity}'='null'::jsonb,'changed preparation invalidates metadata '||kind);
  END IF;
  refused:=false;BEGIN PERFORM public.read_nutrition_window_units(gen_random_uuid(),ARRAY[old_id]);EXCEPTION WHEN SQLSTATE '22023' THEN refused:=true;END;
  PERFORM pg_temp.writer_ok(refused,'foreign or stale ids refused '||kind);
 END LOOP;
END $units$;
DO $precision_boundaries$
DECLARE a jsonb;b jsonb;field text;
BEGIN
 a:='{"user_id":"synthetic-owner","snapshot_id":"synthetic-day","food_name":"leite","food_db_id":null,"source":"user_kcal","meal_type":"cafe","consumed_at":"2026-11-12T00:00:00Z","raw_provider_message_id":"synthetic-registration","quantity_g":206,"kcal":125.7,"protein_g":6.49,"carbs_g":9.89,"fat_g":6.7}';
 b:=a||'{"quantity_g":185.4,"kcal":113.1,"protein_g":5.84,"carbs_g":8.9,"fat_g":6.03}';
 PERFORM pg_temp.writer_ok(private.nutrition_window_same_scaled_food(a,b),'official kcal1/macros2 projection qualifies');
 PERFORM pg_temp.writer_ok(private.nutrition_window_same_scaled_food(a,b||'{"kcal":113.13}'),'previous exact kcal2 projection remains qualified');
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"kcal":113.11}'),'no arbitrary calorie tolerance');
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"protein_g":5.8}'),'one-decimal macro does not qualify');
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"protein_g":5.85}'),'changed two-decimal macro does not qualify');
 b:=a||'{"quantity_g":113.3,"kcal":69.1,"protein_g":3.57,"carbs_g":5.44,"fat_g":3.68}';
 PERFORM pg_temp.writer_ok(private.nutrition_window_same_scaled_food(a,b),'whole official binary64 vector qualifies');
 PERFORM pg_temp.writer_ok(private.nutrition_window_same_scaled_food(a,b||'{"kcal":69.14,"fat_g":3.69}'),'whole legacy numeric2 vector qualifies');
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"kcal":69.14}'),'mixed legacy kcal and binary64 fat refused');
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"fat_g":3.69}'),'mixed binary64 kcal and legacy fat refused');
 b:=a||'{"quantity_g":185.4,"kcal":113.1,"protein_g":5.84,"carbs_g":8.9,"fat_g":6.03}';
 FOREACH field IN ARRAY ARRAY['user_id','snapshot_id','food_name','food_db_id','source','meal_type','consumed_at','raw_provider_message_id'] LOOP
  PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,jsonb_set(b,ARRAY[field],'"different"')),
   'known rounding never weakens identity '||field);
 END LOOP;
 FOREACH field IN ARRAY ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g'] LOOP
  PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,jsonb_set(b,ARRAY[field],'"113.1"')),
   'string numeric value remains refused '||field);
 END LOOP;
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"quantity_g":0}'),'zero quantity remains refused');
 PERFORM pg_temp.writer_ok(NOT private.nutrition_window_same_scaled_food(a,b||'{"quantity_g":-1}'),'negative quantity remains refused');
 PERFORM pg_temp.writer_ok(NOT has_function_privilege('anon','private.nutrition_window_same_scaled_food(jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('authenticated','private.nutrition_window_same_scaled_food(jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('service_role','private.nutrition_window_same_scaled_food(jsonb,jsonb)','EXECUTE'),'private proof ACL unchanged');
END $precision_boundaries$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS nutrition_units_assertions FROM meal_writer_assertions;
-- Actual owned SQL pieces only; not a full HTTP/native window fixture.
SELECT jsonb_build_object('provenance','Actual readonly RPC pieces under controlled rollback-only SQL fixture; not HTTP/provider',
 'pieces',jsonb_agg(jsonb_build_object('stage',stage,'food',food,'observation',observation) ORDER BY food,stage)) AS nutrition_units_golden FROM nutrition_units_golden;
ROLLBACK;

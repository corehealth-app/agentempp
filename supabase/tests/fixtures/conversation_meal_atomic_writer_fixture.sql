-- Transaction-owned helpers only. Caller begins and rolls back.
CREATE TEMP TABLE meal_writer_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.writer_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'MEAL_WRITER_ASSERT: %',label; END IF; INSERT INTO meal_writer_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.writer_input(c uuid,channel text DEFAULT 'text') RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('command_protocol','conversation.command.v1','command_id',c,'kind','meal.report','meal_type','almoco','source',jsonb_build_object('channel','text','text','Comi 100g de arroz sintetico')); $$;
CREATE FUNCTION pg_temp.writer_resolved(c jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','conversation.meal-resolved.v1','input_hash',c#>'{context,input_hash}','source_hash',c->'source_hash','meal_type','almoco',
 'semantic_proof',jsonb_build_object('schema','conversation.meal-semantic.v1','decision','consumed_meal','input_hash',c#>'{context,input_hash}','source_hash',c->'source_hash','complete_source',true,'source_units',c#>'{context,source_units}','input_count',1),
 'items',jsonb_build_array(jsonb_build_object('name','arroz sintetico','food_db_id',NULL,'nutrition_source','user_kcal','quantity_g',100,'kcal',130.04,'protein_g',2.31,'carbs_g',28.21,'fat_g',0.21,'confidence',NULL,'input_indexes',jsonb_build_array(0),'quantity_basis','stated','display_qty',NULL,'display_unit',NULL)),
 'totals',jsonb_build_object('kcal',130,'protein_g',2.3,'carbs_g',28.2,'fat_g',0.2),'preparation_annotations','[]'::jsonb,'source_receipts','[]'::jsonb); $$;
CREATE FUNCTION pg_temp.writer_seed(u uuid,c uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN PERFORM public.admit_conversation_meal_command(u,pg_temp.writer_input(c));RETURN public.capture_conversation_meal_source(u,c); END $$;

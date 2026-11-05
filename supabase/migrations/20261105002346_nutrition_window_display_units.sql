-- Read-only owned display quantities from sealed facts and immutable edit lineage.
-- No name/reference catalog lookup, clinical admission, Auth bootstrap or writer.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_meal_effects') IS NULL
  OR to_regclass('private.conversation_meal_edit_heads') IS NULL
  OR to_regclass('private.conversation_meal_edit_operations') IS NULL
  OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
  RAISE EXCEPTION 'nutrition_units_requires_meal_substrate' USING ERRCODE='42501';END IF;
END $preflight$;

CREATE INDEX nutrition_window_effect_provider ON private.conversation_meal_effects(user_id,((receipt->>'provider_key')));
CREATE INDEX nutrition_window_edit_revision ON private.conversation_meal_edit_operations(user_id,command_id,(((receipt->>'revision')::integer)));

CREATE FUNCTION private.nutrition_window_same_scaled_food(a jsonb,b jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE k text;q numeric;
BEGIN
 IF jsonb_typeof(a->'quantity_g') IS DISTINCT FROM 'number' OR jsonb_typeof(b->'quantity_g') IS DISTINCT FROM 'number'
  OR (a->>'quantity_g')::numeric<=0 OR (b->>'quantity_g')::numeric<=0 THEN RETURN false;END IF;
 FOREACH k IN ARRAY ARRAY['user_id','snapshot_id','food_name','food_db_id','source','meal_type','consumed_at','raw_provider_message_id'] LOOP
  IF a->k IS DISTINCT FROM b->k THEN RETURN false;END IF;
 END LOOP;
 q:=(b->>'quantity_g')::numeric/(a->>'quantity_g')::numeric;
 FOREACH k IN ARRAY ARRAY['kcal','protein_g','carbs_g','fat_g'] LOOP
  IF jsonb_typeof(a->k) IS DISTINCT FROM 'number' OR jsonb_typeof(b->k) IS DISTINCT FROM 'number'
   OR round((a->>k)::numeric*q,2) IS DISTINCT FROM (b->>k)::numeric THEN RETURN false;END IF;
 END LOOP;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION private.nutrition_window_same_scaled_food(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_nutrition_window_units(p_user_id uuid,p_meal_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE m public.meal_logs%ROWTYPE;fx private.conversation_meal_effects%ROWTYPE;head private.conversation_meal_edit_heads%ROWTYPE;
 op private.conversation_meal_edit_operations%ROWTYPE;target private.conversation_meal_edit_operations%ROWTYPE;
 result jsonb:='[]';current_group jsonb;cursor_row jsonb;origin jsonb;item jsonb;candidate jsonb;display jsonb;proof jsonb;
 revision integer;matches integer;step integer;k text;scaled boolean;restored boolean;valid boolean;value numeric;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_meal_ids IS NULL OR cardinality(p_meal_ids)>1000 OR array_position(p_meal_ids,NULL) IS NOT NULL
  OR cardinality(p_meal_ids)<>(SELECT count(DISTINCT id) FROM unnest(p_meal_ids) id)
  OR EXISTS(SELECT 1 FROM unnest(p_meal_ids) id WHERE NOT EXISTS(SELECT 1 FROM public.meal_logs x WHERE x.id=id AND x.user_id=p_user_id)) THEN
  RAISE EXCEPTION 'nutrition_units_invalid_owned_set' USING ERRCODE='22023';END IF;
 FOR m IN SELECT * FROM public.meal_logs WHERE user_id=p_user_id AND id=ANY(p_meal_ids) ORDER BY id LOOP
  display:=NULL;proof:=NULL;fx:=NULL;head:=NULL;revision:=NULL;current_group:=NULL;
  SELECT count(*) INTO matches FROM(SELECT 1 FROM private.conversation_meal_effects e
   WHERE e.user_id=p_user_id AND e.receipt->>'provider_key'=m.raw_provider_message_id LIMIT 2) x;
  IF matches=1 THEN
   SELECT * INTO fx FROM private.conversation_meal_effects e WHERE e.user_id=p_user_id AND e.receipt->>'provider_key'=m.raw_provider_message_id;
   SELECT * INTO head FROM private.conversation_meal_edit_heads h WHERE h.user_id=p_user_id AND h.command_id=fx.command_id;
   revision:=coalesce(head.revision,0);
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') INTO current_group FROM public.meal_logs x
    WHERE x.user_id=p_user_id AND x.raw_provider_message_id=m.raw_provider_message_id;
   IF jsonb_array_length(current_group) BETWEEN 1 AND 30
    AND current_group=coalesce(head.after_group,fx.original_facts->'logs')
    AND m.snapshot_id::text=fx.original_facts#>>'{snapshot,id}' THEN
    cursor_row:=to_jsonb(m);scaled:=false;restored:=false;
    FOR step IN 0..64 LOOP
     SELECT x INTO origin FROM jsonb_array_elements(fx.original_facts->'logs') x WHERE x->'id'=cursor_row->'id';
     IF origin IS NOT NULL THEN
      IF origin IS DISTINCT FROM cursor_row THEN EXIT;END IF;
      candidate:=NULL;matches:=0;
      FOR item IN SELECT x FROM jsonb_array_elements(fx.original_facts#>'{confirmed,proposal,items}') x LOOP
       valid:=item->>'name'=origin->>'food_name' AND item->'food_db_id'=origin->'food_db_id'
        AND item->>'nutrition_source'=origin->>'source';
       FOREACH k IN ARRAY ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g'] LOOP
        valid:=valid AND jsonb_typeof(item->k)='number' AND jsonb_typeof(origin->k)='number'
         AND round((item->>k)::numeric,2)=(origin->>k)::numeric;
       END LOOP;
       IF valid THEN candidate:=item;matches:=matches+1;END IF;
      END LOOP;
      IF matches<>1 OR jsonb_typeof(candidate->'display_qty') IS DISTINCT FROM 'number'
       OR NOT((candidate->>'display_qty')::numeric>0 AND (candidate->>'display_qty')::numeric<=999999)
       OR jsonb_typeof(candidate->'display_unit') IS DISTINCT FROM 'string' OR length(candidate->>'display_unit') NOT BETWEEN 1 AND 40
       OR candidate->>'display_unit'<>btrim(candidate->>'display_unit') OR candidate->>'display_unit' ~ '[[:cntrl:]]'
       OR candidate->>'quantity_basis' NOT IN('stated','portion_reference','visual_estimate')
       OR (origin->>'quantity_g')::numeric<=0 THEN EXIT;END IF;
      value:=CASE WHEN scaled THEN round((candidate->>'display_qty')::numeric*m.quantity_g/(origin->>'quantity_g')::numeric,6)
       ELSE (candidate->>'display_qty')::numeric END;
      IF value<=0 OR value>999999 OR (NOT scaled AND m.quantity_g IS DISTINCT FROM (origin->>'quantity_g')::numeric) THEN EXIT;END IF;
      display:=jsonb_build_object('value',value,'unit',candidate->>'display_unit',
       'estimated',scaled OR candidate->>'quantity_basis'='visual_estimate',
       'provenance',CASE WHEN scaled THEN 'audited_same_food_scale' WHEN restored THEN 'audited_restore' ELSE 'sealed_original' END,
       'reference',jsonb_build_object('original_log_id',origin->'id','value',candidate->'display_qty','unit',candidate->>'display_unit',
        'quantity_g',origin->'quantity_g','quantity_basis',candidate->>'quantity_basis'));
      EXIT;
     END IF;
     -- At most the latest 65 immutable edits are searched. An older/unproved
     -- chain has no display-unit permission and retains its actual stored grams.
     SELECT count(*) INTO matches FROM(SELECT 1 FROM private.conversation_meal_edit_operations o
      WHERE o.user_id=p_user_id AND o.command_id=fx.command_id
       AND (o.receipt->>'revision')::integer BETWEEN greatest(1,revision-64) AND revision
       AND o.after_items @> jsonb_build_array(jsonb_build_object('id',cursor_row->'id')) LIMIT 2) x;
     IF matches<>1 THEN EXIT;END IF;
     SELECT * INTO op FROM private.conversation_meal_edit_operations o WHERE o.user_id=p_user_id AND o.command_id=fx.command_id
      AND (o.receipt->>'revision')::integer BETWEEN greatest(1,revision-64) AND revision
      AND o.after_items @> jsonb_build_array(jsonb_build_object('id',cursor_row->'id'));
     IF jsonb_array_length(op.after_items)<>1 OR op.after_items->0 IS DISTINCT FROM cursor_row THEN EXIT;END IF;
     IF op.receipt->>'kind'='saved' THEN
      IF jsonb_array_length(op.before_items)<>1 OR NOT private.nutrition_window_same_scaled_food(op.before_items->0,cursor_row) THEN EXIT;END IF;
      scaled:=scaled OR op.before_items#>'{0,quantity_g}' IS DISTINCT FROM cursor_row->'quantity_g';
      restored:=true;cursor_row:=op.before_items->0;
     ELSIF op.receipt->>'kind'='save_undone' THEN
      SELECT * INTO target FROM private.conversation_meal_edit_operations o WHERE o.user_id=p_user_id AND o.command_id=fx.command_id
       AND o.operation_id=(op.receipt->>'target_operation_id')::uuid;
      IF target.receipt->>'kind' IS DISTINCT FROM 'saved' OR jsonb_array_length(target.before_items)<>1
       OR cursor_row-ARRAY['id','created_at'] IS DISTINCT FROM (target.before_items->0)-ARRAY['id','created_at'] THEN EXIT;END IF;
      restored:=true;cursor_row:=target.before_items->0;
     ELSE EXIT;END IF;
    END LOOP;
    proof:=jsonb_build_object('command_id',fx.command_id,'revision',revision,
     'group_version',encode(sha256(convert_to(private.conversation_command_canonical(current_group),'UTF8')),'hex'));
   END IF;
  END IF;
  result:=result||jsonb_build_array(jsonb_build_object('meal',jsonb_build_object('id',m.id,'user_id',m.user_id,'snapshot_id',m.snapshot_id,
   'meal_type',m.meal_type,'food_name',m.food_name,'quantity_g',m.quantity_g,'kcal',m.kcal,'protein_g',m.protein_g,'carbs_g',m.carbs_g,'fat_g',m.fat_g,
   'consumed_at',m.consumed_at,'raw_provider_message_id',m.raw_provider_message_id,'source',m.source),
   'binding',proof,'display_quantity',display));
 END LOOP;
 RETURN jsonb_build_object('schema','nutrition.window-units.v1','owner_id',p_user_id,'items',result);
END $$;
REVOKE ALL ON FUNCTION public.read_nutrition_window_units(uuid,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_nutrition_window_units(uuid,uuid[]) TO service_role;
COMMIT;

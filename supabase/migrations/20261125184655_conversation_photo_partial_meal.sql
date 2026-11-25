-- Keep the original meal and continuation validators. The sole extra shape
-- is an ordered list of excluded observations on a trusted photo-only root.
DO $migration$
DECLARE
 definition text := pg_get_functiondef('private.assert_conversation_resolved_meal(jsonb,jsonb,text)'::regprocedure);
 old_keys constant text := 'PERFORM private.conversation_meal_keys(v,ARRAY[''schema'',''input_hash'',''source_hash'',''meal_type'',''semantic_proof'',''items'',''totals'',''preparation_annotations'',''source_receipts'']);';
 new_keys constant text := replace(old_keys, '(v,ARRAY', '(v - ''photo_review'',ARRAY');
 old_count constant text := 'input_count:=(proof->>''input_count'')::integer;';
 new_count constant text := $body$input_count:=(proof->>'input_count')::integer;
 IF v ? 'photo_review' THEN
  IF source->>'schema' IS DISTINCT FROM 'conversation.meal-source.v2'
   OR jsonb_typeof(source#>'{source_input,intake_origin}') IS DISTINCT FROM 'object'
   OR source#>>'{source_input,source,channel}' IS DISTINCT FROM 'media'
   OR source#>>'{source_input,source,user_action}' IS DISTINCT FROM 'report_actual_record'
   OR (source#>'{source_input,source}') ? 'caption'
   OR source->'source_units' IS DISTINCT FROM '["vision_items"]'::jsonb
   OR source#>>'{media,kind}' IS DISTINCT FROM 'conversation_photo'
   OR source#>'{media,catalog_version}' IS DISTINCT FROM '2'::jsonb
   OR source#>>'{media,status}' IS DISTINCT FROM 'processed'
   OR source#>>'{media,processing_result,status}' IS DISTINCT FROM 'ready'
   OR source#>>'{media,processing_result,classification}' IS DISTINCT FROM 'meal'
   OR jsonb_typeof(source#>'{media,processing_result,analysis,items}') IS DISTINCT FROM 'array'
   OR jsonb_typeof(v->'photo_review') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid_conversation_photo_review' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(v->'photo_review') NOT BETWEEN 1 AND 29
   OR input_count + jsonb_array_length(v->'photo_review') <> jsonb_array_length(source#>'{media,processing_result,analysis,items}')
   OR input_count + jsonb_array_length(v->'photo_review') > 30
   OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(v->'photo_review') WITH ORDINALITY AS review(idx, pos)
    WHERE CASE WHEN jsonb_typeof(idx) = 'number' THEN
     idx::numeric <> trunc(idx::numeric)
     OR idx::numeric NOT BETWEEN 0 AND input_count + jsonb_array_length(v->'photo_review') - 1
     OR (pos > 1 AND idx <= (v->'photo_review')->(pos::integer - 2))
    ELSE true END
   ) THEN
    RAISE EXCEPTION 'invalid_conversation_photo_review' USING ERRCODE='22023';
  END IF;
 END IF;$body$;
BEGIN
 IF (length(definition) - length(replace(definition, old_keys, ''))) <> length(old_keys)
  OR (length(definition) - length(replace(definition, old_count, ''))) <> length(old_count)
  OR position('photo_review' IN definition) > 0 THEN
  RAISE EXCEPTION 'unexpected_conversation_resolved_meal_definition';
 END IF;
 EXECUTE replace(replace(definition, old_keys, new_keys), old_count, new_count);
END $migration$;

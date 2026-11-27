-- Reuse a captured portion only for the omitted item of the same meal.
BEGIN;

ALTER TABLE private.conversation_meal_photo_answers
  ADD COLUMN estimated_quantity_g numeric CHECK (estimated_quantity_g > 0 AND estimated_quantity_g <= 9999);

CREATE FUNCTION private.conversation_photo_review_grams(
  p_user uuid, p_command uuid, p_photo_index integer
) RETURNS numeric LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT CASE WHEN observed.grams BETWEEN 0.05 AND 9999 THEN round(observed.grams,1) END
  FROM private.conversation_meal_source_captures source
  CROSS JOIN LATERAL (
    SELECT (source.context#>'{media,processing_result,analysis,items}')
      ->p_photo_index->'quantity_g_estimate' AS quantity
  ) raw
  CROSS JOIN LATERAL (
    SELECT CASE WHEN jsonb_typeof(raw.quantity) = 'number'
      THEN (raw.quantity #>> '{}')::numeric END AS grams
  ) observed
  WHERE source.user_id = p_user AND source.command_id = p_command
    AND p_photo_index BETWEEN 0 AND 29
$$;

CREATE FUNCTION public.read_conversation_meal_photo_review_v2(
  p_user_id uuid, p_command_id uuid, p_input_hash text, p_expected_epoch uuid, p_revision integer
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT coalesce(jsonb_agg(
    item || jsonb_strip_nulls(jsonb_build_object('estimated_quantity_g',
      private.conversation_photo_review_grams(p_user_id,p_command_id,(item->>'index')::integer)))
      ORDER BY (item->>'index')::integer), '[]'::jsonb)
  FROM jsonb_array_elements(public.read_conversation_meal_photo_review(
    p_user_id,p_command_id,p_input_hash,p_expected_epoch,p_revision)) AS review(item)
$$;

REVOKE ALL ON FUNCTION private.conversation_photo_review_grams(uuid,uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.read_conversation_meal_photo_review_v2(uuid,uuid,text,uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_photo_review_v2(uuid,uuid,text,uuid,integer)
  TO service_role;

DO $migration$
DECLARE
  validator text := pg_get_functiondef('private.assert_conversation_meal_edit_input(jsonb,text)'::regprocedure);
  writer text := pg_get_functiondef('private.apply_conversation_meal_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text,text)'::regprocedure);
  old_basis constant text := 'v#>>''{items,0,quantity_basis}'' IS DISTINCT FROM ''stated''';
  photo_facts constant text := 'IF p_mode IS DISTINCT FROM ''recalculated''';
  answer_insert constant text := 'INSERT INTO private.conversation_meal_photo_answers(user_id,command_id,operation_id,photo_index)
      VALUES (p_user,p_command,p_operation,(p_input->>''photo_review_index'')::integer);';
BEGIN
  IF length(validator) - length(replace(validator,old_basis,'')) <> length(old_basis)
     OR length(writer) - length(replace(writer,photo_facts,'')) <> length(photo_facts)
     OR length(writer) - length(replace(writer,answer_insert,'')) <> length(answer_insert) THEN
    RAISE EXCEPTION 'unexpected_conversation_photo_answer_definition';
  END IF;
  EXECUTE replace(validator,old_basis,
    'coalesce(v#>>''{items,0,quantity_basis}'','''') NOT IN (''stated'',''visual_estimate'')');
  writer := replace(writer,photo_facts,$guard$
    IF p_input#>>'{items,0,quantity_basis}' = 'visual_estimate'
       AND (p_input#>>'{items,0,quantity_g}')::numeric IS DISTINCT FROM
         private.conversation_photo_review_grams(p_user,p_command,(p_input->>'photo_review_index')::integer)
    THEN
      RAISE EXCEPTION 'conversation_photo_estimate_changed' USING ERRCODE='40001';
    END IF;
    IF p_mode IS DISTINCT FROM 'recalculated'
  $guard$);
  EXECUTE replace(writer,answer_insert,$answer$
    INSERT INTO private.conversation_meal_photo_answers(user_id,command_id,operation_id,photo_index,estimated_quantity_g)
    VALUES (p_user,p_command,p_operation,(p_input->>'photo_review_index')::integer,
      CASE WHEN p_input#>>'{items,0,quantity_basis}' = 'visual_estimate'
        THEN (p_input#>>'{items,0,quantity_g}')::numeric END);
  $answer$);
END;
$migration$;

COMMIT;

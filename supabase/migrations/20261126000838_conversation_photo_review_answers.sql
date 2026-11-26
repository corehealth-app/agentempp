-- A photo review answer is bound to the original excluded observation and
-- committed with the existing meal edit and its finite undo.
BEGIN;

CREATE TABLE private.conversation_meal_photo_answers (
  user_id uuid NOT NULL,
  command_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  photo_index integer NOT NULL CHECK (photo_index BETWEEN 0 AND 29),
  PRIMARY KEY (user_id, command_id, operation_id),
  FOREIGN KEY (user_id, command_id, operation_id)
    REFERENCES private.conversation_meal_edit_operations ON DELETE CASCADE
);

ALTER TABLE private.conversation_meal_photo_answers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_photo_answers FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.conversation_answered_photo_indexes(p_user uuid, p_command uuid)
RETURNS integer[] LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT coalesce(array_agg(DISTINCT a.photo_index ORDER BY a.photo_index), '{}'::integer[])
  FROM private.conversation_meal_photo_answers a
  WHERE a.user_id = p_user AND a.command_id = p_command
    AND NOT EXISTS (
      SELECT 1 FROM private.conversation_meal_edit_operations undo
      WHERE undo.user_id = a.user_id AND undo.command_id = a.command_id
        AND undo.receipt->>'kind' = 'save_undone'
        AND undo.receipt->>'target_operation_id' = a.operation_id::text
    )
$$;

CREATE FUNCTION public.read_conversation_meal_photo_review(
  p_user_id uuid, p_command_id uuid, p_input_hash text, p_expected_epoch uuid, p_revision integer
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE pending jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF NOT EXISTS (
    SELECT 1 FROM private.conversation_meal_command_ids c
    JOIN private.workout_strength_authority_epochs a ON a.user_id = c.user_id
    JOIN public.users u ON u.id = c.user_id
    WHERE c.user_id = p_user_id AND c.command_id = p_command_id
      AND c.epoch = p_expected_epoch AND a.epoch = p_expected_epoch
      AND c.input_hash = p_input_hash
      AND c.invalidated_at IS NULL AND u.status = 'active'
  ) THEN
    RAISE EXCEPTION 'conversation_photo_answer_scope_changed' USING ERRCODE='40001';
  END IF;
  SELECT jsonb_agg(jsonb_build_object('index', review_item.index, 'name',
     (source.context#>'{media,processing_result,analysis,items}')->review_item.index->>'name')
     ORDER BY review_item.index) INTO pending
  FROM private.conversation_meal_resolved resolved
  JOIN private.conversation_meal_source_captures source USING (user_id, command_id)
  LEFT JOIN private.conversation_meal_edit_heads head USING (user_id, command_id)
  CROSS JOIN LATERAL (
    SELECT value::integer AS index
    FROM jsonb_array_elements_text(resolved.resolved->'photo_review')
  ) review_item
  WHERE resolved.user_id = p_user_id AND resolved.command_id = p_command_id
    AND coalesce(head.revision, 0) = p_revision
    AND NOT (review_item.index = ANY(private.conversation_answered_photo_indexes(p_user_id, p_command_id)));
  RETURN coalesce(pending, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION private.conversation_answered_photo_indexes(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.read_conversation_meal_photo_review(uuid,uuid,text,uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_photo_review(uuid,uuid,text,uuid,integer)
  TO service_role;

DO $migration$
DECLARE
  validator text := pg_get_functiondef('private.assert_conversation_meal_edit_input(jsonb,text)'::regprocedure);
  writer text := pg_get_functiondef('private.apply_conversation_meal_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text,text)'::regprocedure);
  keys constant text := 'PERFORM private.conversation_meal_keys(v,ARRAY[''schema'',''kind'',''expected_revision'',''expected_version'',''record_id'',''items'']);';
  before_save constant text := 'removed:=ARRAY[anchor.id];before_items:=jsonb_build_array(to_jsonb(anchor));';
  after_save constant text := 'SELECT coalesce(array_agg(x::uuid ORDER BY x::uuid),''{}'') INTO new_ids FROM jsonb_array_elements_text(result#>''{response_body,data,new_item_ids}'') x;';
  write_receipt constant text := 'INSERT INTO private.conversation_meal_edit_operations VALUES(p_user,p_command,p_operation,receipt,before_items,after_items,g,after_group,clock);';
BEGIN
  IF length(validator) - length(replace(validator, keys, '')) <> length(keys)
     OR length(writer) - length(replace(writer, before_save, '')) <> length(before_save)
     OR length(writer) - length(replace(writer, after_save, '')) <> length(after_save)
     OR length(writer) - length(replace(writer, write_receipt, '')) <> length(write_receipt) THEN
    RAISE EXCEPTION 'unexpected_conversation_meal_edit_definition';
  END IF;

  EXECUTE replace(validator, keys, $validator$
    PERFORM private.conversation_meal_keys(
      v - 'photo_review_index', ARRAY['schema','kind','expected_revision','expected_version','record_id','items']);
    IF v ? 'photo_review_index' THEN
      PERFORM private.conversation_semantic_uint(v->'photo_review_index', 29);
      IF jsonb_typeof(v->'items') IS DISTINCT FROM 'array'
         OR jsonb_array_length(v->'items') <> 1
         OR (v->'items'->0) ? 'user_kcal'
         OR v#>>'{items,0,quantity_basis}' IS DISTINCT FROM 'stated'
         OR (v->'items'->0) ? 'candidate_id' THEN
        RAISE EXCEPTION 'invalid_conversation_photo_answer' USING ERRCODE='22023';
      END IF;
    END IF;
  $validator$);

  writer := replace(writer, before_save, $before$
    IF p_input ? 'photo_review_index' THEN
      IF NOT EXISTS (
        SELECT 1 FROM private.conversation_meal_resolved r
        WHERE r.user_id = p_user AND r.command_id = p_command
          AND r.resolved->'photo_review' @> jsonb_build_array(p_input->'photo_review_index')
      ) OR (p_input->>'photo_review_index')::integer =
           ANY(private.conversation_answered_photo_indexes(p_user,p_command)) THEN
        RETURN '{"action":"version_conflict"}';
      END IF;
      -- Keep the C11 replacement and its compatible receipt. The first
      -- calculated row is a byte-for-byte copy of the selected anchor's facts.
      IF p_mode IS DISTINCT FROM 'recalculated'
         OR jsonb_typeof(p_calculated) IS DISTINCT FROM 'array'
         OR jsonb_array_length(p_calculated) <> 2
         OR p_calculated->0 IS DISTINCT FROM jsonb_build_object(
           'food_name', anchor.food_name, 'quantity_g', anchor.quantity_g, 'kcal', anchor.kcal,
           'protein_g', anchor.protein_g, 'carbs_g', anchor.carbs_g, 'fat_g', anchor.fat_g,
           'food_db_id', anchor.food_db_id, 'source', anchor.source, 'confidence', anchor.confidence)
         OR p_calculated#>'{1,quantity_g}' IS DISTINCT FROM p_input#>'{items,0,quantity_g}' THEN
        RAISE EXCEPTION 'conversation_photo_answer_facts_changed' USING ERRCODE='40001';
      END IF;
    END IF;
    removed:=ARRAY[anchor.id];before_items:=jsonb_build_array(to_jsonb(anchor));
  $before$);
  writer := replace(writer, after_save, after_save || $after$
    IF p_input ? 'photo_review_index' AND NOT EXISTS (
      SELECT 1 FROM public.meal_logs m WHERE m.id = ANY(new_ids)
        AND (to_jsonb(m)-ARRAY['id','created_at']) =
            (to_jsonb(anchor)-ARRAY['id','created_at'])
    ) THEN
      RAISE EXCEPTION 'conversation_photo_answer_anchor_changed' USING ERRCODE='40001';
    END IF;
  $after$);
  writer := replace(writer, write_receipt, write_receipt || $receipt$
    IF p_kind = 'save' AND p_input ? 'photo_review_index' THEN
      INSERT INTO private.conversation_meal_photo_answers(user_id,command_id,operation_id,photo_index)
      VALUES (p_user,p_command,p_operation,(p_input->>'photo_review_index')::integer);
    END IF;
  $receipt$);
  EXECUTE writer;
END;
$migration$;

COMMIT;

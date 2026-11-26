-- Owned synthetic database only. The photo detector/resolver is upstream of
-- this test. Here we seed its two persisted observations and exercise the
-- actual C11 writer, public review read, replay, and compensation.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
\ir fixtures/conversation_meal_edit_fixture.sql

DO $test$
DECLARE
  u uuid := 'c3ed0000-0000-4000-8000-000000000071';
  a uuid := 'c3ed0000-0000-4000-8000-000000000072';
  c uuid := 'c3ed0000-0000-4000-8000-000000000073';
  op uuid := gen_random_uuid();
  original jsonb; before_edit jsonb; state jsonb; input jsonb; answer jsonb; result jsonb;
  anchor uuid; epoch uuid; input_hash text;
BEGIN
  original := pg_temp.edit_seed(u,a,c);
  anchor := (original#>>'{log_ids,0}')::uuid;
  before_edit := pg_temp.edit_fingerprint(u);
  state := public.read_conversation_meal_edit_state(u,c);
  epoch := (state#>>'{command,epoch}')::uuid;
  input_hash := state#>>'{command,input_hash}';
  input := pg_temp.edit_input('save',0,anchor) ||
    '{"photo_review_index":1,"items":[{"food_name":"feijao sintetico","quantity_g":50,"quantity_basis":"stated"}]}';
  answer := (SELECT jsonb_agg(jsonb_build_object(
    'food_name',m.food_name,'quantity_g',m.quantity_g,'kcal',m.kcal,'protein_g',m.protein_g,
    'carbs_g',m.carbs_g,'fat_g',m.fat_g,'food_db_id',m.food_db_id,'source',m.source,'confidence',m.confidence))
    FROM public.meal_logs m WHERE m.id=anchor) ||
    '[{"food_name":"feijao sintetico","quantity_g":50,"kcal":40,"protein_g":3,"carbs_g":7,"fat_g":0.3,"source":"user_kcal","food_db_id":null,"confidence":null}]';
  PERFORM pg_temp.writer_ok(
    public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',answer,'recalculated',NULL,'not-a-photo')->>'action'='version_conflict',
    'a normal meal cannot claim an omitted photo item');

  -- Seed the qualified output of the upstream photo fixture on this one
  -- disposable command. Restore both immutable guards before any API call.
  ALTER TABLE private.conversation_meal_resolved DISABLE TRIGGER immutable_conversation_meal_resolved;
  UPDATE private.conversation_meal_resolved SET resolved=resolved || '{"photo_review":[1]}'::jsonb
    WHERE user_id=u AND command_id=c;
  ALTER TABLE private.conversation_meal_resolved ENABLE TRIGGER immutable_conversation_meal_resolved;
  ALTER TABLE private.conversation_meal_source_captures DISABLE TRIGGER immutable_conversation_meal_source;
  UPDATE private.conversation_meal_source_captures
    SET context=context || '{"media":{"processing_result":{"analysis":{"items":[{"name":"arroz sintetico"},{"name":"feijao sintetico"}]}}}}'::jsonb
    WHERE user_id=u AND command_id=c;
  ALTER TABLE private.conversation_meal_source_captures ENABLE TRIGGER immutable_conversation_meal_source;

  PERFORM pg_temp.writer_ok(public.read_conversation_meal_photo_review(u,c,input_hash,epoch,0)=
    '[{"index":1,"name":"feijao sintetico"}]'::jsonb,'only the excluded photo item is offered');
  result := public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',answer,'recalculated',NULL,'photo-answer');
  PERFORM pg_temp.writer_ok(result->>'action'='committed' AND (SELECT count(*) FROM public.meal_logs WHERE user_id=u)=2,
    'one omitted food joins the original meal');
  PERFORM pg_temp.writer_ok(EXISTS(
    SELECT 1 FROM public.meal_logs m WHERE m.user_id=u
      AND to_jsonb(m)-ARRAY['id','created_at']=(before_edit->'logs'->0)-ARRAY['id','created_at']),
    'existing food facts and metadata are exact');
  PERFORM pg_temp.writer_ok(public.read_conversation_meal_photo_review(u,c,input_hash,epoch,1)='[]',
    'the answered question disappears at the new revision');
  PERFORM pg_temp.writer_ok(
    public.commit_conversation_meal_item_edit(u,c,op,input,NULL,NULL,NULL,NULL,'replay')=jsonb_set(result,'{action}','"replay"'),
    'response loss recovers the original fact without another write');
  state := public.read_conversation_meal_edit_state(u,c);
  input := jsonb_set(jsonb_set(input,'{expected_revision}','1'),'{record_id}',state#>'{current_state,items,0,id}');
  PERFORM pg_temp.writer_ok(
    public.commit_conversation_meal_item_edit(u,c,gen_random_uuid(),input,state->'current_state',answer,'recalculated',NULL,'repeated-answer')->>'action'='version_conflict',
    'a different operation cannot answer the same excluded item twice');
  result := public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),
    pg_temp.edit_input('undo_save',1,NULL,op),state->'current_state','undo-photo-answer');
  PERFORM pg_temp.writer_ok(result#>>'{receipt,kind}'='save_undone'
    AND (SELECT count(*) FROM public.meal_logs WHERE user_id=u)=1,
    'undo removes only the added food and restores the original facts');
  PERFORM pg_temp.writer_ok(public.read_conversation_meal_photo_review(u,c,input_hash,epoch,2)=
    '[{"index":1,"name":"feijao sintetico"}]'::jsonb,'undo reopens the exact unanswered question');
  PERFORM pg_temp.writer_ok((pg_temp.edit_fingerprint(u)->'progress')=(before_edit->'progress'),
    'answer and undo leave rewards unchanged');
  DELETE FROM public.users WHERE id=u;
  DELETE FROM auth.users WHERE id=a;
  PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_photo_answers WHERE user_id=u),
    'account deletion cascades answer lineage');
END;
$test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS photo_review_answer_assertions FROM meal_writer_assertions;
ROLLBACK;

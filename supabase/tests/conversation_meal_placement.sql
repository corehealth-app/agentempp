-- Real owned local PG only. All synthetic rows roll back.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_edit_fixture.sql
ALTER FUNCTION pg_temp.writer_resolved(jsonb) RENAME TO placement_base_resolved;
CREATE FUNCTION pg_temp.writer_resolved(source jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_set(v,'{items,0}',v#>'{items,0}'
    ||'{"quantity_basis":"portion_reference","display_qty":1,"display_unit":"porção"}'::jsonb)
  FROM (SELECT pg_temp.placement_base_resolved(source) AS v) base;
$$;

DO $test$
DECLARE
  u uuid:='c3ed0000-0000-4000-8000-000000000051';
  a uuid:='c3ed0000-0000-4000-8000-000000000052';
  c uuid:='c3ed0000-0000-4000-8000-000000000053';
  op uuid:='c3ed0000-0000-4000-8000-000000000054';
  undo_id uuid:='c3ed0000-0000-4000-8000-000000000055';
  fx jsonb;
  original jsonb;
  current jsonb;
  input jsonb;
  undone jsonb;
  moved jsonb;
  original_day date;
  prior_day date;
  original_id uuid;
  unrelated_id uuid;
  prior_group jsonb;
  before_move jsonb;
  after_move jsonb;
  scaled_id uuid;
BEGIN
  fx:=pg_temp.edit_seed(u,a,c);
  original_day:=(fx->>'local_date')::date;
  prior_day:=original_day-1;
  original_id:=(fx#>>'{log_ids,0}')::uuid;
  INSERT INTO public.daily_snapshots(user_id,date,calories_target,exercise_calories,calories_consumed)
    VALUES(u,prior_day,1700,90,75) RETURNING id INTO unrelated_id;
  INSERT INTO public.meal_logs(user_id,snapshot_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,consumed_at)
    VALUES(u,unrelated_id,'cafe','Unrelated QA',40,75,2,12,2,'user_kcal',prior_day+time '08:00');

  original:=public.read_conversation_meal_edit_state(u,c);
  input:=pg_temp.edit_input('placement',0)||jsonb_build_object('local_date',prior_day,'meal_type','jantar');
  before_move:=pg_temp.edit_fingerprint(u);
  PERFORM pg_temp.writer_ok(public.apply_conversation_meal_placement(u,c,gen_random_uuid(),
    input||jsonb_build_object('local_date',original_day+1),original->'current_state')->>'action'='invalid_date',
    'future date is refused');
  PERFORM pg_temp.writer_ok(public.apply_conversation_meal_placement(u,c,gen_random_uuid(),
    input||'{"expected_revision":51}',original->'current_state')->>'action'='version_conflict',
    'optimistic revision mismatch preserves diary');
  PERFORM pg_temp.writer_ok(pg_temp.edit_fingerprint(u)=before_move,'refusals have no effect');

  moved:=public.apply_conversation_meal_placement(u,c,op,input,original->'current_state');
  PERFORM pg_temp.writer_ok(moved->>'action'='committed' AND moved#>>'{receipt,kind}'='placement_saved'
    AND moved#>>'{receipt,snapshot,date}'=prior_day::text,'move returns a durable placement receipt');
  after_move:=pg_temp.edit_fingerprint(u);
  current:=public.read_conversation_meal_edit_state(u,c);
  PERFORM pg_temp.writer_ok(current->'original_receipt'=fx AND current->>'revision'='1'
    AND current#>>'{current_state,snapshot,date}'=prior_day::text
    AND current#>>'{current_state,items,0,meal_type}'='jantar'
    AND current#>>'{current_state,items,0,id}'=original_id::text,
    'reopen shows the corrected meal with the same identity and original receipt');
  PERFORM pg_temp.writer_ok(
    (SELECT calories_consumed=0 AND protein_g=0 AND calories_target=1900 AND exercise_calories=300
      FROM public.daily_snapshots WHERE user_id=u AND date=original_day)
    AND
    (SELECT calories_consumed=round(75+(original#>>'{current_state,items,0,kcal}')::numeric)
      AND calories_target=1700 AND exercise_calories=90 FROM public.daily_snapshots
      WHERE user_id=u AND date=prior_day),
    'only nutrition totals move between snapshots');
  PERFORM pg_temp.writer_ok(after_move->'effects'=before_move->'effects'
    AND after_move->'progress'=before_move->'progress','clinical progress and original effects stay unchanged');
  PERFORM pg_temp.writer_ok(public.read_nutrition_window_units(u,ARRAY[original_id])
    #>'{items,0,display_quantity}' @> '{"provenance":"sealed_original","value":1,"unit":"porção"}',
    'cross-day move preserves the original portion reference on the nutrition panel');
  PERFORM pg_temp.writer_ok(public.apply_conversation_meal_placement(u,c,op,input,NULL)
    =jsonb_set(moved,'{action}','"replay"'),'lost response replays without a second move');
  PERFORM pg_temp.writer_ok(public.read_conversation_meal_edit_operation(u,c,op,input)->'receipt'=moved->'receipt',
    'operation reconciliation uses immutable receipt');
  PERFORM pg_temp.writer_ok(public.apply_conversation_meal_placement(u,c,op,input||'{"meal_type":"cafe"}',NULL)
    ->>'action'='input_conflict','same operation cannot replace its original input');
  PERFORM pg_temp.writer_ok(NOT EXISTS (SELECT 1 FROM private.conversation_thread_events_v2(
    u,(current#>>'{command,epoch}')::uuid) e WHERE e.operation_id=op),
    'older journal versions remain readable');

  undone:=public.apply_conversation_meal_placement(u,c,undo_id,
    pg_temp.edit_input('undo_placement',1)||jsonb_build_object('target_operation_id',op),current->'current_state');
  PERFORM pg_temp.writer_ok(undone#>>'{receipt,kind}'='placement_undone','latest move can be undone');
  current:=public.read_conversation_meal_edit_state(u,c);
  prior_group:=original#>'{current_state,items}';
  PERFORM pg_temp.writer_ok(current#>'{current_state,items}'=prior_group
    AND (SELECT calories_consumed=75 FROM public.daily_snapshots WHERE user_id=u AND date=prior_day),
    'undo restores exact original items and independent destination nutrition');
  UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=u AND date=prior_day;
  current:=public.read_conversation_meal_edit_state(u,c);
  PERFORM pg_temp.writer_ok(public.apply_conversation_meal_placement(u,c,gen_random_uuid(),
    input||'{"expected_revision":2}',current->'current_state')->>'action'='day_closed',
    'a closed destination cannot be reopened by changing the date');

  moved:=public.apply_conversation_meal_placement(u,c,gen_random_uuid(),
    input||jsonb_build_object('expected_revision',2,'local_date',original_day),current->'current_state');
  PERFORM pg_temp.writer_ok(moved->>'action'='committed','meal type can change without a date change');
  current:=public.read_conversation_meal_edit_state(u,c);
  moved:=public.commit_conversation_meal_item_edit(u,c,gen_random_uuid(),
    pg_temp.edit_input('save',3,original_id),current->'current_state',pg_temp.edit_quantity(),
    'quantity_only','{"quantity_g":200}','placement-units-save');
  PERFORM pg_temp.writer_ok(moved->>'action'='committed','quantity remains editable after correcting the meal type');
  scaled_id:=(moved#>>'{receipt,new_item_ids,0}')::uuid;
  PERFORM pg_temp.writer_ok(public.read_nutrition_window_units(u,ARRAY[scaled_id])
    #>'{items,0,display_quantity}' @> '{"provenance":"audited_same_food_scale","value":2,"unit":"porção"}',
    'quantity edit still links to the original portion across an audited type change');
  PERFORM pg_temp.writer_ok(NOT has_function_privilege('authenticated',
    'public.apply_conversation_meal_placement(uuid,uuid,uuid,jsonb,jsonb)','EXECUTE'),
    'client cannot call placement writer directly');
END $test$;

SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS meal_placement_assertions FROM meal_writer_assertions;
ROLLBACK;

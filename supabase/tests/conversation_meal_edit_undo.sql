-- Real owned local PG only; all synthetic auth/public rows roll back.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN
 IF to_regprocedure('public.undo_conversation_meal_registration(uuid,uuid,uuid,jsonb,jsonb,text)') IS NULL THEN
  RAISE EXCEPTION 'MEAL_EDIT_RED:missing_direct_edit_undo'; END IF;
END $$;
\ir fixtures/conversation_meal_edit_fixture.sql

DO $initial$
DECLARE u uuid:='c3ed0000-0000-4000-8000-000000000001';a uuid:='c3ed0000-0000-4000-8000-000000000002';
 c uuid:='c3ed0000-0000-4000-8000-000000000003';op uuid:='c3ed0000-0000-4000-8000-000000000004';
 original jsonb;state jsonb;input jsonb;v jsonb;before_read jsonb;after_undo jsonb;refused boolean;
BEGIN
 original:=pg_temp.edit_seed(u,a,c);
 before_read:=pg_temp.edit_fingerprint(u);
 state:=public.read_conversation_meal_edit_state(u,c);
 PERFORM pg_temp.writer_ok(state->>'action'='available' AND state->>'revision'='0' AND (state->>'lineage_compatible')::boolean
  AND state->'original_receipt'=original AND state->'last_operation'='null'::jsonb,'initial read has original current generation');
 PERFORM pg_temp.writer_ok(pg_temp.edit_fingerprint(u)=before_read AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_heads WHERE user_id=u),'read creates no head/domain effect');
 input:=pg_temp.edit_input('undo_registration',0)||'{"expected_revision":0.0}';
 v:=public.undo_conversation_meal_registration(u,c,op,input,state->'current_state','synthetic-initial-undo');
 PERFORM pg_temp.writer_ok(v->'command'=state->'command','initial undo success carries actual original command binding');
 PERFORM pg_temp.writer_ok(v->>'action'='committed' AND v#>>'{receipt,kind}'='registration_undone'
  AND v#>>'{receipt,revision}'='1' AND v#>'{receipt,new_item_ids}'='[]'::jsonb,'initial registration undo has durable compensation');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u)
  AND (SELECT calories_consumed=0 AND protein_g=0 AND carbs_g=0 AND fat_g=0 AND calories_target=1900 AND protein_target=120 AND exercise_calories=300 FROM public.daily_snapshots WHERE user_id=u),'initial undo finite deletion preserves targets exercise');
 after_undo:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_registration(u,c,op,input,NULL,'different-retry-id')=jsonb_set(v,'{action}','"replay"')
  AND pg_temp.edit_fingerprint(u)=after_undo,'initial undo unknown response replays without current group');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_edit_operation(u,c,op,input)=jsonb_build_object('action','available','command',state->'command','receipt',v->'receipt'),'explicit operation read recovers original receipt and command binding');
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_registration(u,c,gen_random_uuid(),input,NULL,'second-initial-undo')->>'action'='version_conflict','different undo identity never removes twice');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_effect(u,c)->'receipt'=original
  AND (pg_temp.edit_fingerprint(u)->'effects')=(before_read->'effects')
  AND (pg_temp.edit_fingerprint(u)->'pending')=(before_read->'pending'),'original registration receipt facts and confirmed pending immutable');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_edit_operation(u,c,op,input)='{"action":"stale_epoch"}'::jsonb
  AND public.undo_conversation_meal_registration(u,c,op,input,NULL,'after-reset')='{"action":"stale_epoch"}'::jsonb,'reset wins over completed undo replay');
 PERFORM pg_temp.writer_ok(EXISTS(SELECT 1 FROM private.conversation_meal_edit_ids WHERE user_id=u AND command_id=c AND operation_id=op)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_operations WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_heads WHERE user_id=u),'reset keeps op identity and scrubs audit head receipt');
 DELETE FROM public.users WHERE id=u; DELETE FROM auth.users WHERE id=a;
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_ids WHERE user_id=u),'owner delete cascades edit tombstones');
END $initial$;

DO $save$
DECLARE u uuid:='c3ed0000-0000-4000-8000-000000000011';a uuid:='c3ed0000-0000-4000-8000-000000000012';
 c uuid:='c3ed0000-0000-4000-8000-000000000013';op uuid:='c3ed0000-0000-4000-8000-000000000014';undo_id uuid:='c3ed0000-0000-4000-8000-000000000015';
 original jsonb;state jsonb;input jsonb;undo_input jsonb;v jsonb;undone jsonb;before_save jsonb;after_save jsonb;after_undo jsonb;anchor uuid;
BEGIN
 original:=pg_temp.edit_seed(u,a,c);anchor:=(original#>>'{log_ids,0}')::uuid;
 before_save:=pg_temp.edit_fingerprint(u);state:=public.read_conversation_meal_edit_state(u,c);input:=pg_temp.edit_input('save',0,anchor);
 v:=public.commit_conversation_meal_item_edit(u,c,op,input,state->'current_state',pg_temp.edit_quantity(),'quantity_only','{"quantity_g":200}','synthetic-save');
 PERFORM pg_temp.writer_ok(v->'command'=state->'command','Save success carries actual original command binding');
 PERFORM pg_temp.writer_ok(v->>'action'='committed' AND v#>>'{receipt,kind}'='saved' AND v#>>'{receipt,revision}'='1'
  AND (v#>>'{receipt,undo_expires_at}')::timestamptz=(v#>>'{receipt,applied_at}')::timestamptz+interval '5 minutes','direct save creates own five minute window');
 PERFORM pg_temp.writer_ok((SELECT count(*)=1 AND min(quantity_g)=200 AND min(kcal)=260.1 FROM public.meal_logs WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE id=anchor),'quantity save actual C11 new physical ID');
 after_save:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_item_edit(u,c,op,input,NULL,NULL,NULL,NULL,'lost-save-response')=jsonb_set(v,'{action}','"replay"')
  AND pg_temp.edit_fingerprint(u)=after_save,'save first winner before fresh context calculation');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_edit_operation(u,c,op,input||'{"expected_revision":1}')='{"action":"input_conflict"}'::jsonb,'same operation changed intent conflicts');
 state:=public.read_conversation_meal_edit_state(u,c);
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_registration(u,c,gen_random_uuid(),pg_temp.edit_input('undo_registration',1),state->'current_state','obsolete-initial')->>'action'='version_conflict','any save makes initial undo obsolete');
 undo_input:=pg_temp.edit_input('undo_save',1,NULL,op)||'{"expected_revision":1.0}';
 undone:=public.undo_conversation_meal_item_edit(u,c,undo_id,undo_input,state->'current_state','synthetic-save-undo');
 PERFORM pg_temp.writer_ok(undone->'command'=state->'command','Save undo success carries actual original command binding');
 PERFORM pg_temp.writer_ok(undone->>'action'='committed' AND undone#>>'{receipt,kind}'='save_undone' AND undone#>>'{receipt,revision}'='2','last Save undo creates next durable generation');
 after_undo:=pg_temp.edit_fingerprint(u);
 PERFORM pg_temp.writer_ok((SELECT jsonb_agg(to_jsonb(m)-ARRAY['id','created_at'] ORDER BY food_name) FROM public.meal_logs m WHERE user_id=u)
  =(SELECT jsonb_agg(x-ARRAY['id','created_at'] ORDER BY x->>'food_name') FROM jsonb_array_elements(before_save->'logs') x),'undo restores exact prior facts with new physical identity');
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_item_edit(u,c,undo_id,undo_input,NULL,'lost-undo-response')=jsonb_set(undone,'{action}','"replay"')
  AND pg_temp.edit_fingerprint(u)=after_undo,'undo first winner replays without repeating compensation');
 PERFORM pg_temp.writer_ok(public.undo_conversation_meal_item_edit(u,c,gen_random_uuid(),pg_temp.edit_input('undo_save',2,NULL,op),NULL,'no-redo')->>'action'='version_conflict','no second undo or implicit redo');
 PERFORM pg_temp.writer_ok(after_undo->'effects'=before_save->'effects' AND after_undo->'pending'=before_save->'pending'
  AND after_undo->'progress'=before_save->'progress' AND after_undo->'workouts'=before_save->'workouts','save undo leaves original and protected neighbors byte exact');
 DELETE FROM public.users WHERE id=u;DELETE FROM auth.users WHERE id=a;
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_ids WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_operations WHERE user_id=u)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_heads WHERE user_id=u),'active generation owner delete cascades without constraint bypass');
END $save$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS direct_edit_undo_assertions FROM meal_writer_assertions;
ROLLBACK;

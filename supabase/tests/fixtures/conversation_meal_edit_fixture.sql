\ir conversation_meal_atomic_writer_fixture.sql
-- Explicit synthetic auth.users links exercise C11; these are not GoTrue sessions.
CREATE FUNCTION pg_temp.edit_seed(u uuid,a uuid,c uuid,observed timestamptz DEFAULT NULL,zone text DEFAULT 'UTC') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE source jsonb;prepared jsonb;effect jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=a) THEN
  RAISE EXCEPTION 'edit_fixture_collision'; END IF;
 INSERT INTO auth.users(id) VALUES(a);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed)
 VALUES(u,a,'meal-edit-'||u::text||'@example.invalid','active',zone,'BR',true);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,exercise_calories)
 VALUES(u,(clock_timestamp() AT TIME ZONE zone)::date,1900,120,300);
 source:=pg_temp.writer_seed(u,c);
 prepared:=public.prepare_conversation_meal(u,c,pg_temp.writer_resolved(source));
 IF observed IS NULL THEN effect:=public.commit_conversation_meal(u,c,prepared->>'resolved_hash');
 ELSE effect:=private.commit_conversation_meal_at(u,c,prepared->>'resolved_hash',observed);END IF;
 IF effect->>'action'<>'committed' THEN RAISE EXCEPTION 'edit_fixture_domain_not_committed';END IF;
 RETURN effect->'receipt';
END $$;
CREATE FUNCTION pg_temp.edit_input(kind text,revision integer,anchor uuid DEFAULT NULL,target uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','conversation.meal-edit.v1','kind',kind,'expected_revision',revision,'expected_version','v1:'||repeat('a',64))
 ||CASE kind WHEN 'save' THEN jsonb_build_object('record_id',anchor,'items',jsonb_build_array(jsonb_build_object('food_name','arroz sintetico','quantity_g',200)))
 WHEN 'undo_save' THEN jsonb_build_object('target_operation_id',target) ELSE '{}'::jsonb END;
$$;
CREATE FUNCTION pg_temp.edit_quantity() RETURNS jsonb LANGUAGE sql AS $$
 SELECT '[{"food_name":"arroz sintetico","quantity_g":200,"kcal":260.1,"protein_g":4.62,"carbs_g":56.42,"fat_g":0.42,"source":"user_kcal","food_db_id":null,"confidence":null}]'::jsonb;
$$;
CREATE FUNCTION pg_temp.edit_fingerprint(u uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('logs',(SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY id),'[]') FROM public.meal_logs m WHERE user_id=u),
 'snapshots',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM public.daily_snapshots s WHERE user_id=u),
 'effects',(SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY command_id),'[]') FROM private.conversation_meal_effects e WHERE user_id=u),
 'pending',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]') FROM public.pending_registrations p WHERE user_id=u),
 'progress',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY user_id),'[]') FROM public.user_progress p WHERE user_id=u),
 'workouts',(SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY id),'[]') FROM public.workout_logs w WHERE user_id=u),
 'ledger',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY id),'[]') FROM public.mobile_api_idempotency l WHERE user_id=u),
 'edit_ids',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY operation_id),'[]') FROM private.conversation_meal_edit_ids i WHERE user_id=u),
 'edit_ops',(SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY operation_id),'[]') FROM private.conversation_meal_edit_operations o WHERE user_id=u),
 'edit_head',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY command_id),'[]') FROM private.conversation_meal_edit_heads h WHERE user_id=u));
$$;
-- A private synthetic audit at a selected server-relative deadline exercises
-- wait/expiry without a five-minute sleep. Actual Save's exact TTL is tested separately.
CREATE FUNCTION pg_temp.edit_deadline_fixture(u uuid,c uuid,op uuid,deadline timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE state jsonb;g jsonb;receipt jsonb;input jsonb;h text;epoch uuid;
BEGIN
 state:=public.read_conversation_meal_edit_state(u,c);g:=state#>'{current_state,items}';
 input:=pg_temp.edit_input('save',0,(g->0->>'id')::uuid);h:=encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex');
 SELECT a.epoch INTO epoch FROM private.workout_strength_authority_epochs a WHERE user_id=u;
 receipt:=jsonb_build_object('schema','conversation.meal-edit-effect.v1','owner_id',u,'command_id',c,'operation_id',op,'input_hash',h,'kind','saved','revision',1,
  'applied_at',deadline-interval '5 minutes','undo_expires_at',deadline,'target_operation_id',NULL,
  'removed_item_ids',jsonb_build_array(gen_random_uuid()),'new_item_ids',(SELECT jsonb_agg(x->'id') FROM jsonb_array_elements(g) x),
  'next_record_id',g->0->'id','snapshot',state#>'{current_state,snapshot}');
 INSERT INTO private.conversation_meal_edit_ids VALUES(u,c,op,epoch,h,'save',deadline-interval '5 minutes');
 INSERT INTO private.conversation_meal_edit_operations VALUES(u,c,op,receipt,g,g,g,g,deadline-interval '5 minutes');
 INSERT INTO private.conversation_meal_edit_heads VALUES(u,c,1,op,g);
END $$;

-- Real SQL dependency receipts. All synthetic business data rolls back.
BEGIN;
\ir fixtures/conversation_meal_atomic_writer_fixture.sql
DO $nutrition$
DECLARE a uuid:='c3e00000-0000-4000-8000-000000000001';c uuid:='c3e00000-0000-4000-8000-000000000002';other uuid:='c3e00000-0000-4000-8000-000000000003';
 log_id uuid:='c3e00000-0000-4000-8000-000000000004';sid uuid:='c3e00000-0000-4000-8000-000000000005';src jsonb;v jsonb;r1 jsonb;r2 jsonb;r3 jsonb;prep jsonb;append_src jsonb;append_prep jsonb;x jsonb;code text;
BEGIN
 PERFORM pg_temp.writer_ok(to_regprocedure('public.read_conversation_meal_nutrition_source(uuid,uuid,text,text)') IS NOT NULL,'real bound history source RPC exists');
 INSERT INTO public.food_db(id,name_pt,source,is_verified,source_ref,kcal_per_100g,protein_g,carbs_g,fat_g) VALUES(2140000002,'synthetic history food','synthetic',true,'synthetic:conversation-history',130.04,2.31,28.21,0.21);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-history@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date) VALUES(sid,a,(clock_timestamp() AT TIME ZONE 'UTC')::date-1);
 INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,food_db_id,source,quantity_g,kcal,protein_g,carbs_g,fat_g,meal_type,created_at,consumed_at,raw_provider_message_id)
 VALUES(log_id,a,sid,'synthetic history food',2140000002,'canonical_exact',100,130.04,2.31,28.21,0.21,'almoco',clock_timestamp()-interval '1 day',clock_timestamp()-interval '1 day','synthetic-history-original');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM public.admit_conversation_meal_command(a,jsonb_set(pg_temp.writer_input(c),'{source,text}','"Comi 100g de synthetic history food"'));
 src:=public.capture_conversation_meal_source(a,c);
 r1:=public.read_conversation_meal_nutrition_source(a,c,'trusted_recent',NULL);
 r2:=public.read_conversation_meal_nutrition_source(a,c,'exact_median','synthetic history food');
 r3:=public.read_conversation_meal_nutrition_source(a,c,'exact_median','missing food');
 PERFORM pg_temp.writer_ok(r1->>'action'='captured' AND r1#>>'{rows,0,id}'=log_id::text AND r1#>'{rows,0,food_db,is_verified}'='true'::jsonb,'actual trusted history row and verified projection captured');
 PERFORM pg_temp.writer_ok(jsonb_array_length(r2->'rows')=1 AND r3->'rows'='[]'::jsonb,'actual median hit and miss both captured');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_nutrition_source(a,c,'trusted_recent',NULL)=jsonb_set(r1,'{action}','"replay"'),'history lookup lost response replays exact stored rows and hash');
 v:=pg_temp.writer_resolved(src);v:=jsonb_set(jsonb_set(jsonb_set(v,'{items,0,name}','"synthetic history food"'),'{items,0,food_db_id}','2140000002'),'{items,0,nutrition_source}','"history"');
 code:=NULL;BEGIN PERFORM public.prepare_conversation_meal(a,c,v);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 PERFORM pg_temp.writer_ok(code='22023','omitted lookup receipts cannot authorize resolved meal');
 v:=jsonb_set(v,'{source_receipts}',jsonb_build_array(jsonb_build_object('id',r1->'source_receipt_id','hash',r1->'source_receipt_hash'),jsonb_build_object('id',r2->'source_receipt_id','hash',r2->'source_receipt_hash'),jsonb_build_object('id',r3->'source_receipt_id','hash',r3->'source_receipt_hash')));
 SET LOCAL timezone='America/Los_Angeles';prep:=public.prepare_conversation_meal(a,c,v);SET LOCAL timezone='UTC';
 PERFORM pg_temp.writer_ok(prep->>'action'='prepared' AND public.read_conversation_meal_nutrition_source(a,c,'exact_median','another')='{"action":"sealed"}'::jsonb,'preparation seals exact complete lookup set');
 -- A legitimate independent append is later than this command's capture.
 append_src:=pg_temp.writer_seed(a,other);append_prep:=public.prepare_conversation_meal(a,other,pg_temp.writer_resolved(append_src));
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal(a,other,append_prep->>'resolved_hash')->>'action'='committed','independent factual append commits while first history preparation waits');
 x:=public.commit_conversation_meal(a,c,prep->>'resolved_hash');
 PERFORM pg_temp.writer_ok(x->>'action'='committed','later append excluded from earlier bound historical window');
 PERFORM pg_temp.writer_ok((SELECT count(*)=3 FROM public.meal_logs WHERE user_id=a),'history consumption adds one new group without rewriting original');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_nutrition_sources WHERE user_id=a) AND public.read_conversation_meal_nutrition_source(a,c,'trusted_recent',NULL)='{"action":"stale_epoch"}'::jsonb,'reset scrubs query rows and fences historical lookup UUID');
END $nutrition$;
DO $dependency_drift$
DECLARE a uuid:='c3e00000-0000-4000-8000-000000000010';c uuid;log_id uuid:='c3e00000-0000-4000-8000-000000000011';sid uuid:='c3e00000-0000-4000-8000-000000000012';src jsonb;receipt jsonb;v jsonb;prep jsonb;x jsonb;mode text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'atomic-history-drift@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date) VALUES(sid,a,(clock_timestamp() AT TIME ZONE 'UTC')::date-1);
 INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,food_db_id,source,quantity_g,kcal,protein_g,carbs_g,fat_g,created_at,consumed_at) VALUES(log_id,a,sid,'synthetic history food',2140000002,'canonical_exact',100,130.04,2.31,28.21,0.21,clock_timestamp()-interval '1 day',clock_timestamp()-interval '1 day');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH mode IN ARRAY ARRAY['edited','deleted','miss_became_hit'] LOOP
  c:=gen_random_uuid();src:=pg_temp.writer_seed(a,c);receipt:=public.read_conversation_meal_nutrition_source(a,c,'exact_median',CASE WHEN mode='miss_became_hit' THEN 'unseen history name' ELSE 'synthetic history food' END);
  v:=jsonb_set(pg_temp.writer_resolved(src),'{source_receipts}',jsonb_build_array(jsonb_build_object('id',receipt->'source_receipt_id','hash',receipt->'source_receipt_hash')));prep:=public.prepare_conversation_meal(a,c,v);
  BEGIN
   IF mode='edited' THEN UPDATE public.meal_logs SET kcal=140 WHERE id=log_id;
   ELSIF mode='deleted' THEN DELETE FROM public.meal_logs WHERE id=log_id;
   ELSE UPDATE public.meal_logs SET food_name='unseen history name' WHERE id=log_id; END IF;
   x:=public.commit_conversation_meal(a,c,prep->>'resolved_hash');
   IF x<>'{"action":"source_conflict"}'::jsonb THEN RAISE EXCEPTION 'history drift not fenced: % %',mode,x; END IF;
   RAISE EXCEPTION 'rollback history mutation' USING ERRCODE='P5510';
  EXCEPTION WHEN SQLSTATE 'P5510' THEN NULL; END;
  PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=a AND command_id=c),'history rowset drift fenced '||mode);
 END LOOP;
 INSERT INTO public.user_food_corrections(user_id,said_name,corrected_to,custom_kcal_per_100g,status,confirmed_count) VALUES(a,'synthetic correction','synthetic remap',100,'active',3);
 c:=gen_random_uuid();src:=pg_temp.writer_seed(a,c);
 UPDATE public.user_food_corrections SET custom_kcal_per_100g=200 WHERE user_id=a;
 UPDATE public.user_food_corrections SET custom_kcal_per_100g=100 WHERE user_id=a;
 PERFORM pg_temp.writer_ok(public.prepare_conversation_meal(a,c,pg_temp.writer_resolved(src))='{"action":"source_conflict"}'::jsonb,'correction/remap ABA fenced even if final row restored');
END $dependency_drift$;
SELECT count(*) FROM meal_writer_assertions;
ROLLBACK;

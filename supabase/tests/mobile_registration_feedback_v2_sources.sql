BEGIN;
CREATE TEMP TABLE source_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.source_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'V2_SOURCE_ASSERT: %',label; END IF; INSERT INTO source_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.source_refuse(f jsonb,c jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE code text;
BEGIN
 BEGIN PERFORM private.assert_registration_feedback_v2_sources(f,c);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 PERFORM pg_temp.source_ok(code='22023',label||' ['||coalesce(code,'accepted')||']');
END $$;
DO $test$
DECLARE a uuid:='c2b00000-0000-4000-8000-000000000001';rid uuid:='c2b00000-0000-4000-8000-000000000003';sid uuid:='c2b00000-0000-4000-8000-000000000004';mid uuid:='c2b00000-0000-4000-8000-000000000005';
 ts timestamptz:=date_trunc('second',clock_timestamp());p jsonb;c jsonb;f jsonb;x jsonb;k text;mut jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'v2-contract@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date,calories_target,protein_target,calories_consumed,protein_g,carbs_g,fat_g,exercise_calories) VALUES(sid,a,(ts AT TIME ZONE 'UTC')::date,1900,120,126,6.3,9.5,6.5,504);
 INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,consumed_at,meal_type,raw_provider_message_id) VALUES(mid,a,sid,'leite integral',206,126.12,6.3,9.5,6.5,'product_label',ts,'cafe','v2-contract-meal');
 p:=jsonb_build_object('kind','meal','mealType','cafe','registration_origin','mobile_app','source_provider_message_id','v2-contract-meal','source_timestamp',to_char(ts AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'source_timezone','UTC','source_local_date',(ts AT TIME ZONE 'UTC')::date::text,'items',jsonb_build_array(jsonb_build_object('name','leite integral','quantity_g',206,'kcal',126.12,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5,'nutrition_source','product_label')),'totals',jsonb_build_object('kcal',126.1,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5));
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(rid,a,'confirmed',p,ts+interval '1 day');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 c:=public.capture_mobile_registration_feedback_v2(a,rid)->'context';
 f:=jsonb_build_object('schema','registration.feedback.v2','registration_id',rid,'local_date',p->'source_local_date','locale','pt-BR','assistant','Flow AI',
  'registration',jsonb_build_object('kind','meal','meal_kind','cafe','totals',p->'totals','items',jsonb_build_array(jsonb_build_object('log_id',mid,'food_name','leite integral','quantity_g',206,'quantity',jsonb_build_object('value',200,'unit','mL','estimated',true,'reference_id','fao-infoods-v2-whole-milk-tb'),'nutrition_source','product_label','kcal',126.12,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5))),
  'day',NULL,'block',jsonb_build_object('status','unavailable'),'guidance','unavailable','education',jsonb_build_object('status','unavailable'));
 PERFORM private.assert_registration_feedback_v2_sources(f,c);
 PERFORM pg_temp.source_ok(true,'actual captured incomplete owner accepts item-only feedback');
 FOR k IN SELECT unnest(ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g']) LOOP
  PERFORM pg_temp.source_refuse(jsonb_set(f,ARRAY['registration','items','0',k],'999'::jsonb),c,'changed stored item '||k);
 END LOOP;
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,totals,kcal}','126.12'::jsonb),c,'summary remains canonical one-decimal total');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,items,0,food_name}','"leite com whey"'::jsonb),c,'saved food name cannot change');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,items,0,log_id}',to_jsonb(a)),c,'foreign or missing log ID');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,items,0,nutrition_source}','"llm_estimate"'::jsonb),c,'saved source cannot change');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,items,0,quantity,value}','206'::jsonb),c,'milk density not treated as one-to-one');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,items,0,quantity,reference_id}','"invented-density"'::jsonb),c,'invented display provenance rejected');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{guidance}','"available"'::jsonb),c,'incomplete state does not become available');
 x:=jsonb_set(f,'{education}',private.registration_feedback_v2_expected_education(f,true));
 PERFORM pg_temp.source_refuse(x,c,'generated summary cannot prove preferences');
 x:=jsonb_set(f,'{education}',private.registration_feedback_v2_expected_education(f,false));
 PERFORM private.assert_registration_feedback_v2_sources(x,c);PERFORM pg_temp.source_ok(true,'exact reviewed education accepted');
 PERFORM pg_temp.source_refuse(jsonb_set(x,'{education,text}','"Sou nutricionista e garanto a perda de peso"'::jsonb),c,'arbitrary educational prose rejected');
 PERFORM pg_temp.source_refuse(f||'{"private_context":{"health":"secret"}}'::jsonb,c,'private root field rejected');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{registration,items,0}',(f#>'{registration,items,0}')||'{"diagnosis":"x"}'::jsonb),c,'private nested field rejected');

 INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at,birth_date,height_cm,weight_kg,body_fat_percent,current_protocol)
 VALUES(a,true,ts-interval '1 day','1990-01-01',180,80,24,'recomposicao');
 INSERT INTO public.user_progress(user_id,deficit_block,blocks_completed) VALUES(a,500,2);
 c:=public.capture_mobile_registration_feedback_v2(a,rid)->'context';
 f:=jsonb_set(f,'{guidance}','"available"'::jsonb);
 f:=jsonb_set(f,'{day}',jsonb_build_object('local_date',p->'source_local_date','current_protocol','recomposicao',
  'consumed',jsonb_build_object('calories_kcal',126,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5),'targets',jsonb_build_object('calories_kcal',1900,'protein_g',120),
  'calorie_percentage',6.6,'protein_percentage',5.3,'remaining_food_kcal',1774,'food_excess_kcal',0,'exercise_kcal',504));
 f:=jsonb_set(f,'{block}',jsonb_build_object('status','available','target_kcal',7700,'current_kcal',500,'percentage',6,'completed_blocks',2,'total_credited_kcal',15900));
 PERFORM private.assert_registration_feedback_v2_sources(f,c);PERFORM pg_temp.source_ok(true,'actual complete clinical source accepts independent day and block');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{day,remaining_food_kcal}','2278'::jsonb),c,'exercise never increases food budget');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{day,consumed,calories_kcal}','126.12'::jsonb),c,'day is integer snapshot not fresh item sum');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{day,exercise_kcal}','0'::jsonb),c,'exercise uses official snapshot');
 PERFORM pg_temp.source_refuse(jsonb_set(jsonb_set(f,'{day,targets,calories_kcal}','2000'::jsonb),'{day,calorie_percentage}','6.3'::jsonb),c,'fabricated calorie target rejected');
 PERFORM pg_temp.source_refuse(jsonb_set(jsonb_set(f,'{day,targets,protein_g}','150'::jsonb),'{day,protein_percentage}','4.2'::jsonb),c,'fabricated protein target rejected');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{block,current_kcal}','700'::jsonb),c,'block cannot credit this event');
 PERFORM pg_temp.source_refuse(jsonb_set(f,'{block,completed_blocks}','3'::jsonb),c,'block count cannot be increased');
 x:=jsonb_set(jsonb_set(f,'{block}','{"status":"not_applicable"}'::jsonb),'{day,current_protocol}','"ganho_massa"'::jsonb);
 PERFORM pg_temp.source_refuse(x,c,'objective comes from current profile not guessed day');
 x:=jsonb_set(jsonb_set(f,'{day,targets,calories_kcal}','null'::jsonb),'{day,calorie_percentage}','null'::jsonb);
 x:=jsonb_set(jsonb_set(x,'{day,remaining_food_kcal}','null'::jsonb),'{day,food_excess_kcal}','null'::jsonb);
 PERFORM private.assert_registration_feedback_v2_sources(x,c);PERFORM pg_temp.source_ok(true,'independent missing calorie target retains protein target');
 x:=jsonb_set(jsonb_set(f,'{day,targets,protein_g}','null'::jsonb),'{day,protein_percentage}','null'::jsonb);
 PERFORM private.assert_registration_feedback_v2_sources(x,c);PERFORM pg_temp.source_ok(true,'independent missing protein target retains calorie target');

 UPDATE public.user_profiles SET body_fat_percent=10 WHERE user_id=a;
 c:=public.capture_mobile_registration_feedback_v2(a,rid)->'context';
 PERFORM pg_temp.source_refuse(f,c,'unchanged stored targets cannot escape current clinical pause');
 f:=jsonb_set(jsonb_set(f,'{guidance}','"paused"'::jsonb),'{block}','{"status":"protected"}'::jsonb);
 f:=jsonb_set(jsonb_set(jsonb_set(f,'{day,current_protocol}','null'::jsonb),'{day,targets}', '{"calories_kcal":null,"protein_g":null}'::jsonb),'{day,calorie_percentage}','null'::jsonb);
 f:=jsonb_set(jsonb_set(jsonb_set(f,'{day,protein_percentage}','null'::jsonb),'{day,remaining_food_kcal}','null'::jsonb),'{day,food_excess_kcal}','null'::jsonb);
 PERFORM private.assert_registration_feedback_v2_sources(f,c);PERFORM pg_temp.source_ok(true,'clinical pause preserves consumption while masking targets and block');
 UPDATE public.user_profiles SET weight_kg=NULL WHERE user_id=a;
 c:=public.capture_mobile_registration_feedback_v2(a,rid)->'context';
 f:=jsonb_set(jsonb_set(f,'{day}','null'::jsonb),'{block}','{"status":"unavailable"}'::jsonb);
 PERFORM private.assert_registration_feedback_v2_sources(f,c);PERFORM pg_temp.source_ok(true,'partial known BF guard still pauses with no weight');
 PERFORM pg_temp.source_ok(NOT has_function_privilege('service_role','private.assert_registration_feedback_v2_sources(jsonb,jsonb)','EXECUTE'),'source validator has no direct service grant');
END $test$;
SELECT count(*) AS source_assertions FROM source_assertions;
ROLLBACK;

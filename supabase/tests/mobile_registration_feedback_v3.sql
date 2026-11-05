-- Actual retained owned PostgreSQL only. Concrete core + v3 migration must be
-- installed inside this same rollback wrapper, never persisted or bootstrapped.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
CREATE TEMP TABLE feedback_v3_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE TEMP TABLE feedback_v3_actual_golden(kind text,context jsonb,feedback jsonb);
CREATE TEMP TABLE feedback_v3_reconcile_golden(kind text,bound_command jsonb,epoch uuid,response jsonb);
CREATE FUNCTION pg_temp.v3_ok(value boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'V3_ASSERT:%',label;END IF;
 INSERT INTO feedback_v3_assertions VALUES(label);
END $$;
DO $$BEGIN
 PERFORM pg_temp.v3_ok(to_regprocedure('public.read_mobile_registration_feedback_v3(uuid,uuid,text)') IS NOT NULL
  AND to_regprocedure('public.capture_mobile_registration_feedback_v3(uuid,uuid,text)') IS NOT NULL
  AND to_regprocedure('public.commit_mobile_registration_feedback_v3(uuid,uuid,text,jsonb,jsonb)') IS NOT NULL,
  'canonical v3 receipt entrypoints exist');
END $$;
-- Helpers and historical fixture are loaded by the precoverage prelude.
CREATE FUNCTION pg_temp.v3_seed(u uuid,r uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE ts timestamptz:=date_trunc('second',clock_timestamp());s uuid:=gen_random_uuid();m uuid:=gen_random_uuid();p jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,u::text||'@feedback-v3.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date,calories_target,protein_target,calories_consumed,protein_g,carbs_g,fat_g) VALUES(s,u,(ts AT TIME ZONE 'UTC')::date,1900,120,126,6.3,9.5,6.5);
 INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,consumed_at,meal_type,raw_provider_message_id) VALUES(m,u,s,'leite integral',206,126.12,6.3,9.5,6.5,'product_label',ts,'cafe','v3/'||r);
 p:=jsonb_build_object('kind','meal','mealType','cafe','registration_origin','mobile_app','source_provider_message_id','v3/'||r,'source_timestamp',to_char(ts AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'source_timezone','UTC','source_local_date',(ts AT TIME ZONE 'UTC')::date::text,'items',jsonb_build_array(jsonb_build_object('name','leite integral','quantity_g',206,'kcal',126.12,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5,'nutrition_source','product_label')),'totals',jsonb_build_object('kcal',126.1,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5));
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(r,u,'confirmed',p,ts+interval '1 day');
 INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at,birth_date,height_cm,weight_kg,body_fat_percent,current_protocol) VALUES(u,true,ts-interval '1 day','1990-01-01',180,80,24,'recomposicao');
 INSERT INTO public.user_progress(user_id,deficit_block,blocks_completed) VALUES(u,500,2);
END $$;
CREATE FUNCTION pg_temp.v3_feedback(c jsonb,include_day boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb;s jsonb:=c->'snapshot';p jsonb:=private.mobile_registration_feedback_v2_policy(c->'clinical');d jsonb;available boolean:=s->'exercise_energy_complete'='true' AND s->'exercise_calories'<>'null';
 reason text:=CASE WHEN s ? 'exercise_energy_complete' THEN 'unknown_workout_energy' ELSE 'source_unavailable' END;
BEGIN
 IF include_day THEN
 d:=jsonb_build_object('local_date',c->'local_date','current_protocol',CASE WHEN c#>>'{clinical,assessment}'='complete' AND p->>'guidance'='available' THEN c#>'{clinical,phase_origin,phase}' ELSE 'null'::jsonb END,
 'consumed',jsonb_build_object('calories_kcal',s->'calories_consumed','protein_g',s->'protein_g','carbs_g',s->'carbs_g','fat_g',s->'fat_g'),
 'targets',CASE WHEN c#>>'{clinical,assessment}'='complete' AND p->>'guidance'='available' THEN jsonb_build_object('calories_kcal',s->'calories_target','protein_g',s->'protein_target') ELSE '{"calories_kcal":null,"protein_g":null}' END,
 'exercise_kcal',CASE WHEN available THEN s->'exercise_calories' ELSE 'null'::jsonb END,
 'exercise_energy',CASE WHEN available THEN '{"status":"available"}' ELSE jsonb_build_object('status','unavailable','reason',reason) END);
 d:=d||jsonb_build_object('calorie_percentage',private.mobile_feedback_v2_percentage((s->>'calories_consumed')::numeric,(d#>>'{targets,calories_kcal}')::numeric,1000,10),'protein_percentage',private.mobile_feedback_v2_percentage((s->>'protein_g')::numeric,(d#>>'{targets,protein_g}')::numeric,1000,10),
 'remaining_food_kcal',CASE WHEN d#>'{targets,calories_kcal}'='null' THEN NULL ELSE greatest(0,(s->>'calories_target')::numeric-(s->>'calories_consumed')::numeric) END,'food_excess_kcal',CASE WHEN d#>'{targets,calories_kcal}'='null' THEN NULL ELSE greatest(0,(s->>'calories_consumed')::numeric-(s->>'calories_target')::numeric) END);
 END IF;
 f:=jsonb_build_object('schema','registration.feedback.v3','registration_id',c->'registration_id','local_date',c->'local_date','locale','pt-BR','assistant','Flow AI','registration',c->'record','day',d,'block',jsonb_build_object('status',CASE WHEN p->>'guidance'='paused' OR (p#>>'{hide,block}')::boolean THEN 'protected' ELSE 'unavailable' END),'guidance',p->'guidance','education',jsonb_build_object('status','unavailable'));
 RETURN f;
END $$;
CREATE FUNCTION pg_temp.v3_refuse(f jsonb,c jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE code text;BEGIN
 BEGIN PERFORM private.assert_registration_feedback_v3_sources(f,c);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 PERFORM pg_temp.v3_ok(code='22023',label||' ['||coalesce(code,'accepted')||']');END $$;
DO $behavior$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000001';r uuid:='139f0000-0000-4000-8000-000000000002';c jsonb;f jsonb;x jsonb;before_state jsonb;w uuid;
BEGIN
 PERFORM pg_temp.v3_seed(u,r);
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';
 f:=pg_temp.v3_feedback(c);PERFORM private.assert_registration_feedback_v3_sources(f,c);
 INSERT INTO feedback_v3_actual_golden VALUES('known_meal',c,f);
 PERFORM pg_temp.v3_ok(f#>>'{day,exercise_kcal}'='0' AND f#>>'{day,exercise_energy,status}'='available','known zero remains a proven number');
 before_state:=pg_temp.feedback_owner_state(u);
 PERFORM pg_temp.v3_ok(public.read_mobile_registration_feedback_v3(u,r,'pending_registration')='{"action":"absent"}'::jsonb,'read absent before seal');
 PERFORM pg_temp.v3_ok(pg_temp.feedback_owner_state(u)=before_state,'read does not change any owner row');
 INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) VALUES(u,(c#>>'{snapshot,id}')::uuid,'caminhada',30,NULL,clock_timestamp()) RETURNING id INTO w;
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f)='{"action":"source_conflict"}'::jsonb,'late unknown workout rejects stale complete capture');
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';f:=pg_temp.v3_feedback(c);
 PERFORM pg_temp.v3_ok(f#>'{day,exercise_kcal}'='null' AND f#>>'{day,exercise_energy,reason}'='unknown_workout_energy' AND f#>>'{day,remaining_food_kcal}'='1774','unknown exercise keeps food and independent budget');
 PERFORM pg_temp.v3_refuse(jsonb_set(f,'{day,exercise_kcal}','0'),c,'NULL is never zero');
 PERFORM pg_temp.v3_refuse(jsonb_set(f,'{day,exercise_energy}','{"status":"available"}'),c,'partial private sum cannot prove energy');
 PERFORM pg_temp.v3_refuse(jsonb_set(f,'{day,remaining_food_kcal}','2278'),c,'exercise does not increase food budget');
 PERFORM pg_temp.v3_refuse(jsonb_set(f,'{registration,items,0,kcal}','999'),c,'sealed facts match original source');
 x:=public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f);
 PERFORM pg_temp.v3_ok(x=jsonb_build_object('action','committed','feedback',f),'one actual v3 commit');
 UPDATE public.workout_logs SET estimated_kcal=0 WHERE id=w;
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'replay wins before fresh source or invalid payload');
 PERFORM pg_temp.v3_ok(public.read_mobile_registration_feedback_v3(u,r,'pending_registration')=jsonb_build_object('action','available','feedback',f),'repair zero cannot rewrite original availability');
 PERFORM pg_temp.v3_ok(public.read_mobile_registration_feedback(u,r)->>'action'='event_conflict' AND public.read_mobile_registration_feedback_v2(u,r)->>'action'='event_conflict','old readers cannot start another version');
 PERFORM pg_temp.v3_ok((SELECT count(*)=1 FROM private.mobile_registration_feedback_claims WHERE user_id=u AND registration_id=r),'one canonical claim');
 PERFORM pg_temp.v3_ok((SELECT deficit_block=500 AND blocks_completed=2 FROM public.user_progress WHERE user_id=u),'feedback grants no block credit');
END $behavior$;

CREATE FUNCTION pg_temp.v3_legacy(u uuid,r uuid,p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE rd jsonb;c jsonb;steps jsonb;f jsonb;
BEGIN rd:=public.read_flow_shared_phrase_cursor(u);c:=coalesce(nullif(rd->'cursor','null'),pg_temp.feedback_empty_cursor(u));
 steps:=jsonb_build_array(pg_temp.feedback_empty_step(u,r,'incentive',c));
 f:=jsonb_build_object('schema','registration.feedback.v1','registration_id',r,'kind','workout','locale','en','meal_totals',NULL,'day',NULL,
 'lines',jsonb_build_array(jsonb_build_object('key','day_unavailable','text','Synthetic day unavailable.')),'food_comment',NULL,'incentive',NULL);
 RETURN public.commit_mobile_registration_feedback(u,r,p,rd->>'cursor_revision',rd->'cursor',steps,f);END $$;
DO $canonical_old$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000010';r uuid:='139f0000-0000-4000-8000-000000000011';r1 uuid:='139f0000-0000-4000-8000-000000000012';c jsonb;f jsonb;x jsonb;cursor_before jsonb;
BEGIN
 PERFORM pg_temp.v3_seed(u,r);c:=public.capture_mobile_registration_feedback_v2(u,r)->'context';
 f:=jsonb_set(pg_temp.v3_feedback(public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context',false),'{schema}','"registration.feedback.v2"');
 x:=public.commit_mobile_registration_feedback_v2(u,r,c,f);
 PERFORM pg_temp.v3_ok(x=jsonb_build_object('action','committed','feedback',f),'known actual v2 writer remains supported');
 cursor_before:=public.read_flow_shared_phrase_cursor(u);
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'canonical v2 is returned exact before invalid new context');
 PERFORM pg_temp.v3_ok(public.read_mobile_registration_feedback_v3(u,r,'pending_registration')=jsonb_build_object('action','available','feedback',f),'canonical v2 read exact');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(r1,u,'confirmed','{"kind":"workout"}',clock_timestamp()+interval '1 day');
 x:=pg_temp.v3_legacy(u,r1,'{"kind":"workout"}');f:=x->'feedback';
 PERFORM pg_temp.v3_ok(x->>'action'='committed','actual fresh v1 writer remains supported');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r1,'pending_registration',NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'canonical v1 returned exact without v3 capture');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback(u,r1,NULL,NULL,NULL,NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'old v1 lost-response replay remains exact');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v2(u,r1,NULL,NULL)=jsonb_build_object('action','legacy','feedback',f),'old v2 retains legacy action and literal v1 payload');
 PERFORM pg_temp.v3_ok((SELECT count(*)=2 AND count(DISTINCT version)=2 FROM private.mobile_registration_feedback_claims WHERE user_id=u),'one metadata claim per old event without coercion');
END $canonical_old$;
DO $frozen_meal$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000020';cmd uuid:='139f0000-0000-4000-8000-000000000021';oldcmd uuid:='139f0000-0000-4000-8000-000000000022';x jsonb;c jsonb;f jsonb;r uuid;before_state jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'v3-frozen-meal@example.invalid','active','UTC','BR',true);
 x:=pg_temp.feedback_seed(u,cmd);r:=(x#>>'{receipt,registration_id}')::uuid;
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';
 PERFORM pg_temp.v3_ok(c#>>'{source,command,command_id}'=cmd::text AND c->'day_workouts'='null','conversational meal uses frozen context with explicit metadata');
 f:=pg_temp.v3_feedback(c);before_state:=pg_temp.feedback_owner_state(u);
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f)->>'action'='committed','frozen meal seals v3 from original source');
 PERFORM pg_temp.v3_ok(public.commit_conversation_meal_feedback_v2(u,cmd,NULL,NULL)='{"action":"event_conflict"}'::jsonb,'frozen v2 writer cannot reseal canonical v3');
 PERFORM pg_temp.v3_ok(public.read_conversation_meal_feedback_v2(u,cmd)='{"action":"event_conflict"}'::jsonb,'command old reader observes canonical fence');
 x:=pg_temp.feedback_seed(u,oldcmd);r:=(x#>>'{receipt,registration_id}')::uuid;
 c:=public.read_conversation_meal_feedback_source(u,oldcmd)->'context';f:=pg_temp.command_feedback(c);
 PERFORM pg_temp.v3_ok(public.commit_conversation_meal_feedback_v2(u,oldcmd,x#>>'{receipt,effect_version}',f)->>'action'='committed','old command-only frozen v2 still seals known source');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'canonical frozen old v2 exact; never reinterpreted as live pending');
END $frozen_meal$;
CREATE TEMP TABLE workout_assertions(label text);
CREATE FUNCTION pg_temp.workout_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'V3_WORKOUT_SETUP:%',label;END IF;END $$;
CREATE FUNCTION pg_temp.v3_workout(u uuid,c uuid,t text DEFAULT 'Fiz 30 minutos de caminhada.') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE source jsonb;p jsonb;e uuid;input jsonb;
BEGIN
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 IF NOT FOUND THEN e:=gen_random_uuid();INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());END IF;
 input:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',c,'kind','workout.report','source',jsonb_build_object('channel','text','text',t));
 PERFORM public.admit_conversation_workout_command(u,e,input);
 source:=public.capture_conversation_workout_source(u,c,encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex'),e);
 p:=public.prepare_conversation_workout(u,c,source#>>'{context,input_hash}',source->>'source_hash',e,private.conversation_workout_report(source->'context',source->>'source_hash'));
 RETURN public.commit_conversation_workout(u,c,source#>>'{context,input_hash}',source->>'source_hash',e,p->>'prepared_hash',p->'prepared');END $$;
DO $own_workout$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000030';cmd uuid:='139f0000-0000-4000-8000-000000000031';x jsonb;c jsonb;f jsonb;before_state jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'v3-own-workout@example.invalid','active','UTC','BR',true);
 x:=pg_temp.v3_workout(u,cmd);PERFORM pg_temp.v3_ok(x->>'action'='committed','actual own workout registration executes');
 c:=public.capture_mobile_registration_feedback_v3(u,cmd,'conversation_workout')->'context';f:=pg_temp.v3_feedback(c);
 PERFORM pg_temp.v3_ok(c#>>'{record,kind}'='workout' AND c#>>'{source,effect,receipt,provenance}'='conversation.workout.v1' AND c#>'{record,estimated_kcal}'='null','own provenance retained without ui-v1/pending fabrication');
 INSERT INTO feedback_v3_actual_golden VALUES('unknown_workout',c,f);
 INSERT INTO feedback_v3_reconcile_golden SELECT 'unknown_workout',jsonb_build_object('ownerId',u,'commandId',cmd,'inputHash',c#>'{source,effect,receipt,input_hash}','command',c#>'{source,input}'),(c#>>'{source,effect,receipt,epoch}')::uuid,public.reconcile_conversation_workout(u,cmd,c#>>'{source,effect,receipt,input_hash}',(c#>>'{source,effect,receipt,epoch}')::uuid);
 before_state:=pg_temp.feedback_owner_state(u);
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,cmd,'conversation_workout',c,f)=jsonb_build_object('action','committed','feedback',f),'actual nullable workout receipt seals with factual day');
 UPDATE public.workout_logs SET estimated_kcal=0 WHERE user_id=u;
 PERFORM pg_temp.v3_ok(public.capture_mobile_registration_feedback_v3(u,cmd,'conversation_workout')->'context'=c,'later known-zero repair cannot rewrite original workout capture');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,cmd,'conversation_workout',NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'own workout replay exact after repair0');
 DELETE FROM public.workout_logs WHERE user_id=u;
 PERFORM pg_temp.v3_ok(public.capture_mobile_registration_feedback_v3(u,cmd,'conversation_workout')->'context'=c AND public.read_mobile_registration_feedback_v3(u,cmd,'conversation_workout')=jsonb_build_object('action','available','feedback',f),'physical live removal preserves immutable original source and receipt');
 -- An actual pending UUID is a distinct origin; identical UUIDs never alias.
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(cmd,u,'confirmed','{"kind":"workout"}',clock_timestamp()+interval '1 day');
 x:=pg_temp.v3_legacy(u,cmd,'{"kind":"workout"}');
 PERFORM pg_temp.v3_ok(x->>'action'='committed' AND x->'feedback'<>f,'same UUID in different real origins stays two events');
 PERFORM pg_temp.v3_ok((SELECT count(*)=2 AND count(DISTINCT origin)=2 FROM private.mobile_registration_feedback_claims WHERE user_id=u AND registration_id=cmd),'origin race key separates pending and workout identities');
 UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid() WHERE user_id=u;
 PERFORM pg_temp.v3_ok(NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v3 WHERE user_id=u) AND EXISTS(SELECT 1 FROM private.mobile_registration_feedback_claims WHERE user_id=u AND origin='conversation_workout'),'reset scrubs receipt payload while permanent claim prevents reseal');
 PERFORM pg_temp.v3_ok(public.read_mobile_registration_feedback_v3(u,cmd,'conversation_workout')='{"action":"event_conflict"}','reset/tombstone cannot resurrect payload');
END $own_workout$;


DO $known_workout$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000033';cmd uuid:='139f0000-0000-4000-8000-000000000034';c jsonb;f jsonb;x jsonb;k integer;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'v3-known-workout@example.invalid','active','UTC','BR',true);
 INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(u,80);
 x:=pg_temp.v3_workout(u,cmd,'Fiz 30 minutos de caminhada moderada.');k:=public.calc_workout_kcal('caminhada',30,'moderada',80);
 c:=public.capture_mobile_registration_feedback_v3(u,cmd,'conversation_workout')->'context';f:=pg_temp.v3_feedback(c);
 PERFORM pg_temp.v3_ok((c#>>'{record,estimated_kcal}')::numeric=k AND f#>>'{day,exercise_energy,status}'='available' AND (f#>>'{day,exercise_kcal}')::numeric=k,'actual known workout retains existing formula and available energy');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,cmd,'conversation_workout',c,f)=jsonb_build_object('action','committed','feedback',f),'actual known workout v3 seal');
 INSERT INTO feedback_v3_actual_golden VALUES('known_workout',c,f);
 INSERT INTO feedback_v3_reconcile_golden SELECT 'known_workout',jsonb_build_object('ownerId',u,'commandId',cmd,'inputHash',c#>'{source,effect,receipt,input_hash}','command',c#>'{source,input}'),(c#>>'{source,effect,receipt,epoch}')::uuid,public.reconcile_conversation_workout(u,cmd,c#>>'{source,effect,receipt,input_hash}',(c#>>'{source,effect,receipt,epoch}')::uuid);
END $known_workout$;
DO $historical_coverage$
DECLARE u uuid;cmd uuid;oldcmd uuid;old_feedback jsonb;oldrow jsonb;r uuid;c jsonb;f jsonb;
BEGIN
 SELECT owner_id,unsealed_command,old_command,old_receipt,old_row INTO STRICT u,cmd,oldcmd,old_feedback,oldrow FROM feedback_v3_precoverage;
 PERFORM pg_temp.v3_ok((SELECT to_jsonb(row)=oldrow FROM private.mobile_registration_feedback_v2 row WHERE row.user_id=u),'backfill never rewrites old receipt/sourcehash/created_at');
 r:=(SELECT (receipt->>'registration_id')::uuid FROM private.conversation_meal_effects WHERE user_id=u AND command_id=cmd);
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';
 PERFORM pg_temp.v3_ok(NOT(c->'snapshot' ? 'exercise_energy_complete') AND (SELECT NOT exercise_energy_complete FROM public.daily_snapshots WHERE user_id=u),'actual pre-DDL frozen snapshot has no marker while current snapshot proves false');
 UPDATE public.workout_logs SET estimated_kcal=0 WHERE user_id=u;
 PERFORM pg_temp.v3_ok((SELECT exercise_energy_complete FROM public.daily_snapshots WHERE user_id=u) AND public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context'=c,'repair0 cannot certify missing original coverage');
 f:=pg_temp.v3_feedback(c);
 PERFORM pg_temp.v3_ok(f#>'{day,exercise_kcal}'='null' AND f#>>'{day,exercise_energy,reason}'='source_unavailable' AND f#>'{day,consumed}'<>'null','pre-DDL source keeps food with unavailable exercise');
 PERFORM pg_temp.v3_refuse(jsonb_set(jsonb_set(f,'{day,exercise_energy}','{"status":"available"}'),'{day,exercise_kcal}','0'),c,'pre-DDL missing marker cannot inherit current default true');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f)->>'action'='committed','pre-DDL original facts seal without coverage fabrication');
 INSERT INTO feedback_v3_actual_golden VALUES('precoverage_meal',c,f);
 r:=(SELECT (receipt->>'registration_id')::uuid FROM private.conversation_meal_effects WHERE user_id=u AND command_id=oldcmd);
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',NULL,NULL)=jsonb_build_object('action','replay','feedback',old_feedback),'actual pre-DDL v2 wins exact after backfill and repair0');
 PERFORM pg_temp.v3_ok((SELECT to_jsonb(legacy_row)=l.stored_row AND public.read_mobile_registration_feedback_v3(l.owner_id,l.registration_id,'pending_registration')=jsonb_build_object('action','available','feedback',l.feedback) FROM feedback_v3_precoverage_legacy l JOIN private.mobile_registration_feedback legacy_row ON legacy_row.registration_id=l.registration_id),'actual pre-DDL v1 row/steps/cursor receipt preserved exact by backfill');
END $historical_coverage$;

CREATE FUNCTION pg_temp.v3_fail_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic post insert failure' USING ERRCODE='P5511';END $$;
DO $neighbors$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000070';r uuid:='139f0000-0000-4000-8000-000000000071';c jsonb;f jsonb;x jsonb;before_state jsonb;code text;k text;
BEGIN
 PERFORM pg_temp.v3_seed(u,r);
 INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) SELECT u,id,'caminhada',30,NULL,clock_timestamp() FROM public.daily_snapshots WHERE user_id=u;
 FOREACH k IN ARRAY ARRAY['ganho_massa','manutencao'] LOOP
  UPDATE public.user_profiles SET current_protocol=k::public.protocol_enum WHERE user_id=u;
  c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';f:=jsonb_set(pg_temp.v3_feedback(c),'{block}','{"status":"not_applicable"}');
  PERFORM private.assert_registration_feedback_v3_sources(f,c);
  PERFORM pg_temp.v3_ok(f#>>'{day,current_protocol}'=k AND f#>'{day,exercise_kcal}'='null' AND f#>>'{day,remaining_food_kcal}'='1774','independent food targets with unknown exercise in '||k);
 END LOOP;
 UPDATE public.user_profiles SET current_protocol='recomposicao',body_fat_percent=10 WHERE user_id=u;
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';f:=pg_temp.v3_feedback(c);PERFORM private.assert_registration_feedback_v3_sources(f,c);
 PERFORM pg_temp.v3_ok(f->>'guidance'='paused' AND f#>>'{block,status}'='protected' AND f#>'{day,targets,calories_kcal}'='null' AND f#>>'{day,consumed,calories_kcal}'='126','known BF guard retains food and unavailable exercise with goals protected');
 UPDATE public.user_profiles SET body_fat_percent=24,weight_kg=NULL WHERE user_id=u;
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';f:=pg_temp.v3_feedback(c);PERFORM private.assert_registration_feedback_v3_sources(f,c);
 PERFORM pg_temp.v3_ok(f->>'guidance'='unavailable' AND (f#>>'{day,consumed,protein_g}')::numeric=6.3 AND f#>'{day,targets,protein_g}'='null','incomplete assessment retains factual protein without an invented target');
 before_state:=pg_temp.feedback_owner_state(u);
 CREATE TRIGGER qa_v3_fail AFTER INSERT ON private.mobile_registration_feedback_v3 FOR EACH ROW EXECUTE FUNCTION pg_temp.v3_fail_insert();
 BEGIN PERFORM public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 DROP TRIGGER qa_v3_fail ON private.mobile_registration_feedback_v3;
 PERFORM pg_temp.v3_ok(code='P5511' AND pg_temp.feedback_owner_state(u)=before_state,'late insert failure rolls claim and receipt back atomically');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f)->>'action'='committed','valid retry after rolled back claim');
 DELETE FROM public.pending_registrations WHERE id=r AND user_id=u;
 PERFORM pg_temp.v3_ok(NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v3 WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_claims WHERE user_id=u),'pending parent deletion cascades receipt and claim');
 PERFORM pg_temp.v3_ok(public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f)='{"action":"event_conflict"}'::jsonb,'deleted source cannot be resealed');
END $neighbors$;
DO $acl$
DECLARE sig text;code text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['public.read_mobile_registration_feedback_v3(uuid,uuid,text)','public.capture_mobile_registration_feedback_v3(uuid,uuid,text)','public.commit_mobile_registration_feedback_v3(uuid,uuid,text,jsonb,jsonb)'] LOOP
  PERFORM pg_temp.v3_ok(NOT has_function_privilege('anon',sig,'EXECUTE') AND NOT has_function_privilege('authenticated',sig,'EXECUTE') AND has_function_privilege('service_role',sig,'EXECUTE'),'service-only '||sig);
 END LOOP;
 PERFORM pg_temp.v3_ok(NOT has_table_privilege('service_role','private.mobile_registration_feedback_v3','SELECT') AND NOT has_table_privilege('service_role','private.mobile_registration_feedback_claims','INSERT'),'metadata tables remain private');
END $acl$;
SELECT jsonb_build_object('feedback_v3_actual_golden',jsonb_agg(to_jsonb(g) ORDER BY kind)) FROM feedback_v3_actual_golden g;
SELECT jsonb_build_object('workout_reconcile_actual_golden',jsonb_agg(to_jsonb(g) ORDER BY kind),'reconcile_prosrc_sha256',(SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.reconcile_conversation_workout(uuid,uuid,text,uuid)'::regprocedure)) FROM feedback_v3_reconcile_golden g;
SELECT count(*) FROM feedback_v3_assertions;
ROLLBACK;

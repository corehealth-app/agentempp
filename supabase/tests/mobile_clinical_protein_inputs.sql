-- Actual private FULL writer; ordinary answers and approved effects differ.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

CREATE FUNCTION m3b_cycle_test.protein_seed(n integer) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;
BEGIN
 a:=m3b_cycle_test.seed(n,clock_timestamp()-interval '6 days');
 UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,
  weight_kg=80,body_fat_percent=NULL,activity_level='moderado',training_frequency=4,
  hunger_level='moderada',current_protocol='manutencao',deficit_level=NULL WHERE user_id=a;
 -- Protein-branch cases assume an actual preexisting 2400/144 target.
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,2400,144,'manutencao');
 RETURN a;
END $$;
CREATE FUNCTION m3b_cycle_test.protein_request(a uuid,answer_hunger text,answer_sessions integer,
 save_hunger text DEFAULT 'moderada',save_sessions integer DEFAULT 4,
 principal text DEFAULT 'keep',confirmed boolean DEFAULT false,after_protein numeric DEFAULT 144) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE start jsonb;cycle uuid;context jsonb;form jsonb;intent jsonb;proposal jsonb;preview jsonb;
BEGIN
 start:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);
 cycle:=(start#>>'{cycle,id}')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,NULL);
 form:=jsonb_build_object('version',1,'phase','manutencao','kind','EARLY_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',answer_sessions,'hunger',answer_hunger,
   'energy',NULL,'adherence',NULL,'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
   'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 intent:=jsonb_build_object('principalConfirmed',confirmed);
 proposal:=jsonb_build_object('version',1,'principal',principal,'clearHold',false,'profile',jsonb_build_object(
  'current_protocol','manutencao','deficit_level',NULL,'activity_level','moderado','training_frequency',save_sessions,'hunger_level',save_hunger),
  'targets',jsonb_build_object('beforeKcal',2400,'beforeProtein',144,'afterKcal',2400,'afterProtein',after_protein,'formulaAfterKcal',2400),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',form,intent,proposal,NULL);
 RETURN jsonb_build_object('preview',preview,'form',form,'intent',intent,'proposal',proposal);
END $$;
CREATE FUNCTION m3b_cycle_test.protein_reprepare(a uuid,r jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;preview jsonb;cycle uuid:=(r#>>'{context,cycle_id}')::uuid;
BEGIN
 SELECT p.cycle_id INTO STRICT cycle FROM private.mobile_clinical_previews p
  WHERE p.user_id=a AND p.preview_id=(r#>>'{preview,preview_id}')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,NULL);
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',
  r->'form',r->'intent',r->'proposal',NULL);
 RETURN r||jsonb_build_object('preview',preview);
END $$;
CREATE FUNCTION m3b_cycle_test.protein_confirm(a uuid,r jsonb,k uuid DEFAULT gen_random_uuid()) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT private.confirm_mobile_clinical_preview_at(a,(r#>>'{preview,preview_id}')::uuid,k,r->'form',r->'intent',r->'proposal',NULL)
$$;
CREATE FUNCTION m3b_cycle_test.protein_refused(a uuid,r jsonb,state text,message text,label text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE before_rows jsonb:=m3b_cycle_test.original_state(a);actual_state text;actual_message text;
BEGIN
 BEGIN PERFORM m3b_cycle_test.protein_confirm(a,r);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
 END;
 PERFORM m3b_cycle_test.ok(actual_state=state AND actual_message=message
  AND before_rows=m3b_cycle_test.original_state(a),label||' ['||coalesce(actual_message,'NO_ERROR')||']');
END $$;

INSERT INTO public.global_config(key,value) VALUES('calc.protein_factors',
 '{"muita":1.6,"moderada":1.8,"pouca":1.8,"training_low":1.7,"optimal_mid_training":1.9,"optimal_high_training":2}')
 ON CONFLICT(key) DO UPDATE SET value=excluded.value;

DO $$
DECLARE a uuid;r jsonb;result jsonb;
BEGIN
 a:=m3b_cycle_test.protein_seed(2300);
 r:=m3b_cycle_test.protein_request(a,'muita',5);
 result:=m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT hunger_level='moderada' AND training_frequency=4 FROM public.user_profiles WHERE user_id=a),
  'keep/declined protein package preserves old hunger and frequency');
 PERFORM m3b_cycle_test.ok((SELECT form#>>'{answers,hunger}'='muita'
  AND form#>>'{answers,strengthSessions}'='5' FROM private.mobile_clinical_full_receipts WHERE user_id=a),
  'ordinary answers remain in the confirmed receipt without silently becoming applied inputs');
END $$;
DO $$
DECLARE a uuid;r jsonb;result jsonb;k uuid:=gen_random_uuid();before_rows jsonb;replay jsonb;
BEGIN
 a:=m3b_cycle_test.protein_seed(2301);
 r:=m3b_cycle_test.protein_request(a,'muita',5,'muita',5);
 PERFORM m3b_cycle_test.protein_refused(a,r,'40001','mobile_clinical_protein_confirmation_required',
  'changing hunger branch under keep is refused before any effect');

 a:=m3b_cycle_test.protein_seed(2302);
 r:=m3b_cycle_test.protein_request(a,'muita',5,'muita',5,'activity',true,128);
 result:=m3b_cycle_test.protein_confirm(a,r,k);
 PERFORM m3b_cycle_test.ok((SELECT hunger_level='muita' AND training_frequency=5 FROM public.user_profiles WHERE user_id=a)
  AND result#>>'{targets,afterProtein}'='128',
  'accepted protein package applies declared inputs without inventing a new activity level');
 PERFORM m3b_cycle_test.throws(format('UPDATE public.user_profiles SET hunger_level=''moderada'' WHERE user_id=%L',a),
  '40001','unconfirmed old/chat profile writer cannot move a protected protein branch');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 replay:=m3b_cycle_test.protein_confirm(a,r,k);
 PERFORM m3b_cycle_test.ok(replay=result AND before_rows=m3b_cycle_test.original_state(a),
  'original accepted protein package replays after reset without restoring profile inputs');

 a:=m3b_cycle_test.protein_seed(2303);
 r:=m3b_cycle_test.protein_request(a,'pouca',3,'pouca',3);
 PERFORM m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT hunger_level='pouca' AND training_frequency=3 FROM public.user_profiles WHERE user_id=a),
  'same branch hunger/frequency answers save on FULL without extra principal confirmation');

 a:=m3b_cycle_test.protein_seed(2304);
 r:=m3b_cycle_test.protein_request(a,NULL,2,'moderada',4);
 PERFORM m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT training_frequency=4 FROM public.user_profiles WHERE user_id=a),
  'declined low-training branch does not silently change tomorrow protein');
 a:=m3b_cycle_test.protein_seed(2305);
 r:=m3b_cycle_test.protein_request(a,NULL,2,'moderada',2);
 PERFORM m3b_cycle_test.protein_refused(a,r,'40001','mobile_clinical_protein_confirmation_required',
  'new frequency branch cannot be smuggled through keep');
 a:=m3b_cycle_test.protein_seed(2306);
 r:=m3b_cycle_test.protein_request(a,NULL,2,'moderada',2,'activity',true,136);
 result:=m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT training_frequency=2 FROM public.user_profiles WHERE user_id=a)
  AND result#>>'{targets,afterProtein}'='136','accepted low-training package persists exactly its shown input and target');

 a:=m3b_cycle_test.protein_seed(2307);
 r:=m3b_cycle_test.protein_request(a,NULL,NULL,NULL,4);
 PERFORM m3b_cycle_test.protein_refused(a,r,'22023','invalid_mobile_clinical_effects',
  'blank hunger cannot erase an existing answer');
 a:=m3b_cycle_test.protein_seed(2308);
 UPDATE public.user_profiles SET hunger_level=NULL WHERE user_id=a;
 r:=m3b_cycle_test.protein_request(a,NULL,NULL,NULL,4);
 PERFORM m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT hunger_level IS NULL FROM public.user_profiles WHERE user_id=a),
  'calculation fallback Moderada is never persisted as an invented answer');

 a:=m3b_cycle_test.protein_seed(2309);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 r:=m3b_cycle_test.protein_request(a,'pouca',3,'pouca',3);
 PERFORM m3b_cycle_test.protein_refused(a,r,'40001','mobile_clinical_safety_block',
  'HOLD preserves even a same-branch hunger/frequency change');
 a:=m3b_cycle_test.protein_seed(2310);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 r:=m3b_cycle_test.protein_request(a,'muita',5);
 PERFORM m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT hunger_level='moderada' AND training_frequency=4 FROM public.user_profiles WHERE user_id=a),
  'guarded FULL still records ordinary answers while preserving original clinical inputs');

 a:=m3b_cycle_test.protein_seed(2311);
 UPDATE public.global_config SET value='{"muita":1.5,"moderada":1.5,"pouca":1.5}' WHERE key='calc.protein_factors';
 r:=m3b_cycle_test.protein_request(a,'muita',5,'muita',5,'activity',true,128);
 PERFORM m3b_cycle_test.protein_refused(a,r,'40001','mobile_clinical_protein_table_unverified',
  'a legacy/default protein row cannot authorize a different branch');
 UPDATE public.global_config SET value='{"muita":1.6,"moderada":1.8,"pouca":1.8,"training_low":1.7,"optimal_mid_training":1.9,"optimal_high_training":2}'
  WHERE key='calc.protein_factors';

 a:=m3b_cycle_test.protein_seed(2312);
 r:=m3b_cycle_test.protein_request(a,NULL,4);
 r:=jsonb_set(r,'{form,answers,activity}',
  '{"otherExerciseType":null,"otherExerciseDays":null,"sessionMinutes":null,"sessionIntensity":null,"mostlySitting":null,"activityLevel":"alto","activityLevelConfirmed":true}');
 r:=jsonb_set(r,'{proposal,profile,activity_level}','"alto"');r:=m3b_cycle_test.protein_reprepare(a,r);
 PERFORM m3b_cycle_test.protein_refused(a,r,'40001','mobile_clinical_activity_confirmation_required',
  'choosing an activity level in a draft is not acceptance of its effects under keep');

 a:=m3b_cycle_test.protein_seed(2313);
 r:=m3b_cycle_test.protein_request(a,NULL,4);
 r:=jsonb_set(r,'{form,answers,weightKg}','81');r:=jsonb_set(r,'{proposal,targets,afterProtein}','145.8');
 r:=m3b_cycle_test.protein_reprepare(a,r);result:=m3b_cycle_test.protein_confirm(a,r);
 PERFORM m3b_cycle_test.ok((SELECT weight_kg=81 AND hunger_level='moderada' AND training_frequency=4 FROM public.user_profiles WHERE user_id=a)
  AND result#>>'{targets,afterProtein}'='145.8','ordinary weight can change protein grams without pretending to change the input branch');

 a:=m3b_cycle_test.protein_seed(2314);
 r:=m3b_cycle_test.protein_request(a,'muita',5,'muita',5,'activity',true,128);
 CREATE FUNCTION m3b_cycle_test.fail_protein_effect() RETURNS trigger LANGUAGE plpgsql AS $f$
  BEGIN RAISE EXCEPTION 'synthetic_protein_rollback'; END $f$;
 CREATE TRIGGER synthetic_protein_rollback BEFORE INSERT ON private.mobile_clinical_episode_events
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_protein_effect();
 PERFORM m3b_cycle_test.protein_refused(a,r,'P0001','synthetic_protein_rollback',
  'late failure rolls back approved hunger/frequency and every FULL effect');
 DROP TRIGGER synthetic_protein_rollback ON private.mobile_clinical_episode_events;

 a:=m3b_cycle_test.protein_seed(2315);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 UPDATE public.global_config SET value='{"muita":1.5,"moderada":1.5,"pouca":1.5}' WHERE key='calc.protein_factors';
 r:=m3b_cycle_test.protein_request(a,'muita',5,'muita',5,'activity',true,128);
 PERFORM m3b_cycle_test.protein_refused(a,r,'40001','mobile_clinical_safety_block',
  'n10 safety wins before any unverified table or protein package decision');
END $$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,
 'private.mobile_clinical_protein_branch(text,text,smallint,jsonb)','EXECUTE'),role||' no direct clinical branch entry')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;

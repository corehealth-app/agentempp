-- True future signup origins only; never reconstruct baselines from a profile.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
SELECT m3b_cycle_test.ok(to_regclass('private.mobile_clinical_signup_origins') IS NOT NULL,
 'immutable initial clinical origin authority exists');
DO $$
DECLARE a uuid; old_user uuid; body text:='SYNTHETIC LOCAL CLINICAL ORIGIN'; digest text;
 observation jsonb; admission jsonb; result jsonb; replay jsonb; submission jsonb; origin jsonb;
 first_generation uuid; phase text; key text; i integer:=1300; before_profile jsonb;
BEGIN
 old_user:=m3b_cycle_test.seed(1299,'2026-10-01T23:00:00Z');
 UPDATE public.user_profiles SET weight_kg=80,body_fat_percent=24,height_cm=180,
  current_protocol='ganho_massa',cycle_start_weight_kg=74,cycle_start_at='2026-10-01' WHERE user_id=old_user;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=old_user),
  'legacy/current profile and mutable cycle columns do not manufacture initial evidence');
 digest:=encode(extensions.digest(body,'sha256'),'hex');
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,
  purpose,action_type,required,effective_at)
 VALUES(m3b_cycle_test.uid(201),'m3b_local_test','m3b-local-1','pt-BR',body,digest,
  'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(201));
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES(m3b_cycle_test.uid(202),'m3b-local-1','pt-BR',ARRAY['m3b_local_test'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(202));
 FOREACH phase IN ARRAY ARRAY['recomposicao','manutencao','ganho_massa'] LOOP
  a:=m3b_cycle_test.seed(i,NULL); key:='clinical-origin-'||i::text; i:=i+1;
  submission:=jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR',
   'timezone','America/Sao_Paulo','sex','masculino','birth_date','1990-01-01','height_cm',180,
   'weight_kg',80,'body_fat_percent',CASE WHEN phase='ganho_massa' THEN 15 ELSE 24 END,
   'objective',phase,'activity_level','moderado','training_frequency',4,'hunger_level','moderada',
   'wake_time','07:00','bedtime','23:00','food_organization','sim','persona','focus',
   'document_actions',jsonb_build_array(jsonb_build_object('document_key','m3b_local_test',
    'version','m3b-local-1','locale','pt-BR','content_hash',digest,'action','acceptance')));
  observation:=public.observe_mobile_signup_strength_epoch(a);
  admission:=public.admit_mobile_signup_strength_request(a,key,repeat('d',64),
   (observation#>>'{observation,epoch}')::uuid)->'admission';
  result:=public.complete_mobile_onboarding_keyed(a,submission,'atomic',key,repeat('d',64),
   (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
  SELECT to_jsonb(o) INTO origin FROM private.mobile_clinical_signup_origins o WHERE user_id=a;
  PERFORM m3b_cycle_test.ok(private.capture_mobile_clinical_context_at(a,'ROUTINE_REVIEW',NULL,NULL)
   #>>'{facts,protocol_authority,signup_origin,episode_id}'=origin->>'episode_id',
   phase||' exact origin is bound by clinical context');
  PERFORM m3b_cycle_test.ok(origin->>'phase'=phase AND (origin->>'start_weight_kg')::numeric=80
   AND (origin->>'start_height_cm')::numeric=180 AND (origin->>'start_training_frequency')::integer=4
   AND origin->>'signup_generation'=admission->>'admissionID'
   AND origin->>'signup_epoch'=admission->>'epoch'
   AND (origin->>'started_at')::timestamptz=(result->>'completed_at')::timestamptz,
   phase||' baseline captured inside actual signup completion');
  PERFORM m3b_cycle_test.ok((phase='manutencao')=(origin->>'maintenance_since' IS NOT NULL)
   AND (phase<>'recomposicao' OR (origin->>'deficit_level')::integer=500),
   phase||' R and initial deficit have actual entry provenance');
  replay:=public.complete_mobile_onboarding_keyed(a,submission,'atomic',key,repeat('d',64),
   (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
  PERFORM m3b_cycle_test.ok(replay=result AND (SELECT count(*)=1 FROM private.mobile_clinical_signup_origins WHERE user_id=a),
   phase||' completion replay has one origin');
  UPDATE public.user_profiles SET weight_kg=82,body_fat_percent=26 WHERE user_id=a;
  IF to_regprocedure('private.mobile_clinical_profile_write_fence()') IS NOT NULL THEN
   PERFORM m3b_cycle_test.throws(format('UPDATE public.user_profiles SET training_frequency=2 WHERE user_id=%L',a),
    '40001',phase||' completed activity change requires the new review route');
  END IF;
  PERFORM m3b_cycle_test.ok(origin=(SELECT to_jsonb(o) FROM private.mobile_clinical_signup_origins o WHERE user_id=a),
   phase||' later profile reports cannot rewrite entry baseline');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_signup_origins SET start_weight_kg=85 WHERE user_id=%L',a),
   '55000',phase||' initial origin immutable');
  first_generation:=(origin->>'signup_generation')::uuid;
  PERFORM public.reset_user_conversation_atomic(a,true);
  PERFORM m3b_cycle_test.ok(origin=(SELECT to_jsonb(o) FROM private.mobile_clinical_signup_origins o WHERE user_id=a),
   phase||' reset preserves origin without relabeling it');
  PERFORM m3b_cycle_test.complete_again(a,key||'-after-reset');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=2 FROM private.mobile_clinical_signup_origins WHERE user_id=a)
   AND EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a AND signup_generation=first_generation),
   phase||' new signup has distinct episode and retains old immutable origin');
  PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id=a),
   phase||' real signup produced the legal action under test');
  PERFORM m3b_cycle_test.throws(format('UPDATE public.user_onboarding_legal_actions SET action_type=action_type WHERE user_id=%L',a),
   '23514',phase||' legal actions remain immutable while owner is active');
  UPDATE public.users SET status='deleted',updated_at=clock_timestamp()-interval '2 hours' WHERE id=a;
  PERFORM m3b_cycle_test.throws(format('DELETE FROM public.user_onboarding_legal_actions WHERE user_id=%L',a),
   '23514',phase||' softdelete alone never authorizes direct legal ledger deletion');
  DELETE FROM public.users WHERE id=a;
  PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id=a),
   phase||' actual final owner deletion cascades clinical and legal evidence');
 END LOOP;
 -- Constraint-only synthetic origin for the new table's cascade path. This
 -- direct test INSERT is not a signup baseline capture or a historical import.
 INSERT INTO private.mobile_clinical_signup_origins(user_id,signup_generation,signup_epoch,
  phase,started_at,start_date,timezone_at_entry,start_weight_kg,start_height_cm,
  deficit_level,captured_at,rule_version)
 SELECT old_user,r.admission_id,r.epoch,'recomposicao',r.completed_at,'2026-10-01',
  'America/Sao_Paulo',80,180,500,r.recorded_at,'clinical-v1'
 FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=old_user;
 -- Existing source/receipt FK requires receipt-first removal. New evidence
 -- remains immutable until users actually disappears later in this transaction.
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=old_user;
 DELETE FROM public.users WHERE id=old_user;
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=old_user),
  'new origin FK cascades on actual owner deletion without bypassing evidence immutability');
END $$;
SELECT m3b_cycle_test.ok(NOT has_table_privilege(role,'private.mobile_clinical_signup_origins','SELECT,INSERT,UPDATE,DELETE'),
 role||' no direct initial clinical origin access') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;

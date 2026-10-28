-- Actual service-only transport, synthetic proposal only, one rollback fixture.
-- This does not prove the full BFF evaluator or any remote activation.
BEGIN;
DO $$ BEGIN
 IF to_regprocedure('public.get_mobile_clinical_full_context(uuid,text,uuid)') IS NULL
  OR to_regprocedure('public.prepare_mobile_clinical_full(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb)') IS NULL
  OR to_regprocedure('public.get_mobile_clinical_full_receipt(uuid,uuid,uuid)') IS NULL
  OR to_regprocedure('public.confirm_mobile_clinical_full(uuid,uuid,uuid,jsonb,jsonb,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'clinical_full_backend_transport_missing';END IF;
END $$;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_full_fixture.sql
DO $$
DECLARE c jsonb;a uuid;cycle uuid;context jsonb;candidate jsonb;form jsonb;intent jsonb;proposal jsonb;
 packet jsonb;preview uuid;key uuid:=gen_random_uuid();alias_key uuid:=gen_random_uuid();prepare_key uuid:=gen_random_uuid();
 original jsonb;before_rows jsonb;caller text;statement text;refused boolean;
BEGIN
 c:=m3b_cycle_test.clinical_photos(4150);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');
 EXECUTE 'SET LOCAL ROLE service_role';
 context:=public.get_mobile_clinical_full_context(a,'REGULAR',cycle);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(context->>'user_id'=a::text AND context->>'review_kind'='REGULAR','real backend role captures exact FULL scope');
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 form:=jsonb_build_object('version',1,'phase','recomposicao','kind','REGULAR','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',84,'strengthSessions',4,'hunger','moderada','energy','boa',
  'adherence','bem_consistente','strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
  'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',false,
  'profile',jsonb_build_object('current_protocol','recomposicao','deficit_level',500,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',1700,'beforeProtein',120,'afterKcal',1599,'afterProtein',126,'formulaAfterKcal',1599),
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.prepare_mobile_clinical_full(a,'REGULAR',cycle,prepare_key,context->>'context_hash',form,intent,proposal);
 EXECUTE 'RESET ROLE';
 preview:=(packet#>>'{preview,preview_id}')::uuid;
 PERFORM m3b_cycle_test.ok(packet->>'user_id'=a::text AND packet->>'operation_key'=prepare_key::text AND preview IS NOT NULL,'public prepare binds original owner and operation');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_receipt(a,preview,key) IS NULL,'absence of original ACK remains SQL NULL');
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.confirm_mobile_clinical_full(a,preview,key,form,intent,proposal);
 EXECUTE 'RESET ROLE';
 original:=public.get_mobile_clinical_full_receipt(a,preview,key);
 PERFORM m3b_cycle_test.ok(packet->'result'=original->'result' AND original->'operation_matched'='true'::jsonb,'confirmation returns exact durable original result');
 PERFORM m3b_cycle_test.ok(original->'form'=form AND original->'intent'=intent AND original->'proposal'=proposal,'only backend lookup carries original package for replay without recalculation');
 PERFORM m3b_cycle_test.ok(jsonb_typeof(original->'review_no')='string','review counter remains exact text');
 packet:=public.get_mobile_clinical_full_receipt(a,preview,alias_key);
 PERFORM m3b_cycle_test.ok(packet->'operation_matched'='false'::jsonb AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_confirmation_keys WHERE user_id=a AND operation_key=alias_key),'preview lookup is read-only and does not reserve alias key');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_full_receipt(%L,%L,%L)',a,gen_random_uuid(),key),'40001','operation cannot identify a different preview');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_receipt(gen_random_uuid(),preview,key) IS NULL,'receipt cannot cross owner');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.confirm_mobile_clinical_full(a,preview,key,form,intent,proposal);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(packet->'result'=original->'result' AND before_rows=m3b_cycle_test.original_state(a),'same confirmation after actual reset does not recapture or resurrect effects');
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.confirm_mobile_clinical_full(a,preview,alias_key,form,intent,proposal);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(packet->'result'=original->'result' AND (SELECT count(*)=1 FROM private.mobile_clinical_full_receipts WHERE user_id=a),'alias replay registers only the key before any current context');
 PERFORM m3b_cycle_test.throws(format('SELECT public.confirm_mobile_clinical_full(%L,%L,%L,%L,%L,%L)',a,preview,key,jsonb_set(form,'{answers,weightKg}','83'),intent,proposal),'40001','same key changed input still conflicts');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_full_context(%L,%L,NULL)',a,'APPLICATION'),'22023','FULL capture cannot select APPLICATION');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_full_receipt(NULL,%L,%L)',preview,key),'22023','null owner is invalid rather than absent');
 FOREACH statement IN ARRAY ARRAY[
  format('SELECT public.get_mobile_clinical_full_context(%L,%L,%L)',a,'REGULAR',cycle),
  format('SELECT public.prepare_mobile_clinical_full(%L,%L,%L,%L,%L,%L,%L,%L)',a,'REGULAR',cycle,prepare_key,context->>'context_hash',form,intent,proposal),
  format('SELECT public.get_mobile_clinical_full_receipt(%L,%L,%L)',a,preview,key),
  format('SELECT public.confirm_mobile_clinical_full(%L,%L,%L,%L,%L,%L)',a,preview,key,form,intent,proposal)
 ] LOOP
  FOREACH caller IN ARRAY ARRAY['anon','authenticated'] LOOP
   refused:=false;EXECUTE format('SET LOCAL ROLE %I',caller);
   BEGIN EXECUTE statement;EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
   EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(refused,'actual client role denied FULL backend wrapper');
  END LOOP;
  PERFORM set_config('request.jwt.claim','{"role":"authenticated"}',true);
  PERFORM m3b_cycle_test.throws(statement,'42501','every definer validates trusted backend JWT');
  PERFORM set_config('request.jwt.claim','{"role":"service_role"}',true);
 END LOOP;
END $$;
SELECT m3b_cycle_test.ok((SELECT count(*)=4 AND bool_and(prosecdef AND 'search_path=pg_catalog'=ANY(proconfig) AND 'lock_timeout=2s'=ANY(proconfig)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('get_mobile_clinical_full_context','prepare_mobile_clinical_full','get_mobile_clinical_full_receipt','confirm_mobile_clinical_full')),'four backend wrappers only, bounded owner wait and no clock overload');
SELECT m3b_cycle_test.ok(NOT has_function_privilege('service_role','private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)','EXECUTE') AND NOT has_function_privilege('service_role','private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)','EXECUTE'),'private clinical clock authority stays revoked');
SELECT m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_clinical_full_receipts','SELECT'),'backend cannot bypass narrow receipt projection');
ROLLBACK;

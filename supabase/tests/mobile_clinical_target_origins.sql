-- New applied source only; no historical provenance inferred. Synthetic owners; every effect rolls back.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL request.jwt.claim='{"role":"service_role"}';
\ir fixtures/mobile_clinical_full_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.mobile_clinical_target_origin(uuid,uuid,uuid,date,timestamptz)') IS NOT NULL,
 'target-origin authority exists');
CREATE FUNCTION m3b_cycle_test.target_request(c jsonb,formula integer DEFAULT 1599)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;candidate jsonb;form jsonb;intent jsonb;proposal jsonb;preview jsonb;
BEGIN
 context:=private.capture_mobile_clinical_context_at((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid,NULL);
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 form:=jsonb_build_object('version',1,'phase','recomposicao','kind','REGULAR','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',84,'strengthSessions',4,'hunger','moderada','energy','boa',
   'adherence','bem_consistente','strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
   'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',false,
  'profile',jsonb_build_object('current_protocol','recomposicao','deficit_level',500,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',context#>'{facts,day,calories_target}','beforeProtein',context#>'{facts,day,protein_target}',
   'afterKcal',coalesce(formula,(context#>>'{facts,day,calories_target}')::integer),
   'afterProtein',CASE WHEN formula IS NULL THEN (context#>>'{facts,day,protein_target}')::numeric ELSE 126 END,'formulaAfterKcal',formula),
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid,
  gen_random_uuid(),context->>'context_hash',form,intent,proposal,NULL);
 RETURN jsonb_build_object('preview',preview,'form',form,'intent',intent,'proposal',proposal,'context',context);
END $$;
DO $$
DECLARE c jsonb;a uuid;request jsonb;ack jsonb;source jsonb;again jsonb;generation uuid;epoch uuid;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;operation uuid:=gen_random_uuid();
 origin uuid;n integer;mode text;sid uuid;
BEGIN
 FOR n IN 4700..4705 LOOP
  mode:=(ARRAY['applied','absent','null_target','closed','preserved','equal'])[n-4699];
  c:=m3b_cycle_test.clinical_photos(n);a:=(c->>'user')::uuid;
  IF mode<>'absent' THEN
   INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at,
    calories_consumed,exercise_calories,xp_earned)
   VALUES(a,day,CASE WHEN mode='null_target' THEN NULL WHEN mode='equal' THEN 1599 ELSE 1700 END,
    CASE WHEN mode='equal' THEN 126 ELSE 120 END,'recomposicao',mode='closed',CASE WHEN mode='closed' THEN clock_timestamp() END,
    200,50,15);
  END IF;
  request:=m3b_cycle_test.target_request(c,CASE WHEN mode='preserved' THEN NULL ELSE 1599 END);
  generation:=(request#>>'{context,facts,anchor,signup_generation}')::uuid;
  epoch:=(request#>>'{context,facts,anchor,signup_epoch}')::uuid;
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp()) IS NULL,
   mode||': existing numeric target is not historical source proof');
  ack:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
   request->'form',request->'intent',request->'proposal',NULL);
  source:=private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp());
  IF mode NOT IN('applied','equal','absent','null_target') THEN
   PERFORM m3b_cycle_test.ok(source IS NULL AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
    mode||': receipt or day-event without a calculated open-row write does not establish source');
   CONTINUE;
  END IF;
  origin:=(source->>'origin_id')::uuid;sid:=(source->>'snapshot_id')::uuid;
  PERFORM m3b_cycle_test.ok((SELECT calories_target=1599 AND protein_target=126 AND NOT day_closed
   FROM public.daily_snapshots WHERE id=sid),mode||': accepted target is present in the actual open snapshot');
  PERFORM m3b_cycle_test.ok((SELECT calories_consumed=CASE WHEN mode='absent' THEN 0 ELSE 200 END
   AND exercise_calories=CASE WHEN mode='absent' THEN 0 ELSE 50 END
   AND xp_earned=CASE WHEN mode='absent' THEN 0 ELSE 15 END FROM public.daily_snapshots WHERE id=sid),
   mode||': materialization preserves existing intake exercise and XP, using defaults only for a new row');
  PERFORM m3b_cycle_test.ok(source->>'source'='clinical_full_v1' AND source->>'review_id'=ack->>'review_id'
   AND source->>'snapshot_id'=(SELECT id::text FROM public.daily_snapshots WHERE user_id=a AND date=day)
   AND source->>'context_hash'=request#>>'{context,context_hash}'
   AND (source->>'calories_target')::integer=1599 AND (source->>'protein_target')::numeric=126,
   mode||': actual confirmed write binds source owner/admission/epoch/snapshot/value/receipt/hash');
  PERFORM m3b_cycle_test.ok(private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,NULL)
   #>'{facts,protocol_authority,target_origin}'=source,'captured and hashed authority contains applied source');
  UPDATE public.daily_snapshots SET calories_consumed=200,exercise_calories=50,xp_earned=15 WHERE id=sid;
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp())=source,
   'unrelated meal workout XP aggregates preserve target origin');
  UPDATE public.daily_snapshots SET protein_target=127 WHERE id=sid;
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp())=source
   AND source->>'target_component'='calories',
   'protein-only correction preserves calorie origin without claiming the protein was recalculated by that source');
  UPDATE public.daily_snapshots SET protein_target=126 WHERE id=sid;
  again:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
   request->'form',request->'intent',request->'proposal',NULL);
  PERFORM m3b_cycle_test.ok(again=ack AND (SELECT count(*)=1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
   'same original receipt replay never appends target origin');
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_target_origin(a,gen_random_uuid(),epoch,day,clock_timestamp()) IS NULL
   AND private.mobile_clinical_target_origin(a,generation,gen_random_uuid(),day,clock_timestamp()) IS NULL
   AND private.mobile_clinical_target_origin(gen_random_uuid(),generation,epoch,day,clock_timestamp()) IS NULL
   AND private.mobile_clinical_target_origin(a,generation,epoch,day-1,clock_timestamp()) IS NULL,
   'cross owner generation epoch date cannot borrow source');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_target_origins SET calories_target=1800 WHERE origin_id=%L',origin),
   '55000','immutable target evidence cannot be rewritten');
  PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_target_origins WHERE origin_id=%L',origin),
   '55000','immutable evidence cannot be removed while owner exists');
  UPDATE public.daily_snapshots SET calories_target=1600 WHERE id=sid;
  UPDATE public.daily_snapshots SET calories_target=1599 WHERE id=sid;
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp()) IS NULL
   AND (SELECT count(*)=1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
   'external target edit and numerical restoration invalidate pointer without erasing history');
  again:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
   request->'form',request->'intent',request->'proposal',NULL);
  PERFORM m3b_cycle_test.ok(again=ack AND private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp()) IS NULL,
   'alias replay cannot revive invalidated provenance');
 END LOOP;
END $$;
SELECT m3b_cycle_test.ok((SELECT count(*)=4 FROM private.mobile_clinical_target_origins),
 'only the four actual calculated open-row writes created evidence');
DO $$
DECLARE c jsonb;a uuid;request jsonb;proposal jsonb;preview jsonb;
BEGIN
 c:=m3b_cycle_test.clinical_photos(4707);a:=(c->>'user')::uuid;
 request:=m3b_cycle_test.target_request(c);
 proposal:=jsonb_set(request->'proposal','{targets,beforeKcal}','1700');
 preview:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',(c->>'cycle')::uuid,gen_random_uuid(),
  request#>>'{context,context_hash}',request->'form',request->'intent',proposal,NULL);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  preview->>'preview_id',gen_random_uuid(),request->'form',request->'intent',proposal),
  '40001','a missing snapshot never proves a supplied before-target or schedule starting baseline');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a),
  'fabricated before-target fails before clinical effects and target materialization');
END $$;
CREATE FUNCTION m3b_cycle_test.fail_after_target_source() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=NEW.user_id AND review_id=NEW.review_id)
 THEN RAISE EXCEPTION 'synthetic failure after source'; END IF;
 RETURN NEW;
END $$;
DO $$
DECLARE c jsonb;a uuid;request jsonb;form jsonb;proposal jsonb;preview jsonb;result jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;generation uuid;epoch uuid;
BEGIN
 c:=m3b_cycle_test.clinical_photos(4709);a:=(c->>'user')::uuid;
 UPDATE public.user_profiles SET current_protocol='manutencao',deficit_level=NULL WHERE user_id=a;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,2400,120,'manutencao');
 request:=m3b_cycle_test.target_request(c);form:=jsonb_set(request->'form','{phase}','"manutencao"');
 proposal:=request->'proposal'||jsonb_build_object('profile',jsonb_build_object('current_protocol','manutencao',
  'deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',2400,'beforeProtein',120,'afterKcal',2400,'afterProtein',144,'formulaAfterKcal',2609));
 preview:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',(c->>'cycle')::uuid,gen_random_uuid(),
  request#>>'{context,context_hash}',form,request->'intent',proposal,NULL);
 result:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,request->'intent',proposal,NULL);
 generation:=(request#>>'{context,facts,anchor,signup_generation}')::uuid;epoch:=(request#>>'{context,facts,anchor,signup_epoch}')::uuid;
 PERFORM m3b_cycle_test.ok(result#>>'{targets,formulaAfterKcal}'='2609'
  AND (SELECT calories_target=2400 AND protein_target=144 FROM public.daily_snapshots WHERE user_id=a),
  'a fresh formula and protein calculation can coexist with calories preserved by an unknown ledger');
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_target_origin(a,generation,epoch,day,clock_timestamp()) IS NULL
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
  'preserved calories are not relabeled as newly calculated because protein or formula changed');
END $$;
DO $$
DECLARE c jsonb;a uuid;request jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.clinical_photos(4708);a:=(c->>'user')::uuid;
 UPDATE public.user_profiles SET deficit_level=NULL WHERE user_id=a;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,1700,120,'recomposicao');
 request:=m3b_cycle_test.target_request(c);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal'),
  '40001','SQL refuses a backend default500 substituted for an unknown actual deficit under HOLD');
 PERFORM m3b_cycle_test.ok((SELECT deficit_level IS NULL FROM public.user_profiles WHERE user_id=a)
  AND (SELECT calories_target=1700 FROM public.daily_snapshots WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a),
  'refused unknown-deficit replacement preserves the profile actual target and receipts');
END $$;
DO $$
DECLARE c jsonb;a uuid;request jsonb;before_rows jsonb;result jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.clinical_photos(4706);a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,1700,120,'recomposicao');
 request:=m3b_cycle_test.target_request(c);before_rows:=m3b_cycle_test.original_state(a);
 CREATE TRIGGER synthetic_target_origin_rollback AFTER INSERT ON private.mobile_clinical_full_receipts
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_after_target_source();
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal'),
  'P0001','a downstream failure after source insertion is surfaced');
 DROP TRIGGER synthetic_target_origin_rollback ON private.mobile_clinical_full_receipts;
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origin_heads WHERE user_id=a),
  'source and pointer roll back with the entire FULL, including target and photos');
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'status'='confirmed'
  AND (SELECT count(*)=1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
  'known rolled-back attempt leaves unchanged preview usable once');
 DELETE FROM public.daily_snapshots WHERE user_id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origin_heads WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
  'snapshot removal retires only the pointer and preserves immutable numerical history');
 PERFORM m3b_cycle_test.remove_photos(ARRAY[a]);
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a),
  'owner purge cascades target evidence through the existing immutable purge exception');
END $$;
SELECT m3b_cycle_test.ok((SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN(
 'private.mobile_clinical_target_origins'::regclass,'private.mobile_clinical_target_origin_heads'::regclass))
 AND NOT has_table_privilege('service_role','private.mobile_clinical_target_origins','SELECT')
 AND NOT has_table_privilege('authenticated','private.mobile_clinical_target_origin_heads','SELECT')
 AND NOT has_function_privilege('service_role','private.mobile_clinical_target_origin(uuid,uuid,uuid,date,timestamptz)','EXECUTE'),
 'RLS and ACL keep evidence and origin helper private');
ROLLBACK;

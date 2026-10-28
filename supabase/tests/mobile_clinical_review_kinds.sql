-- Explicit private clocks below qualify civil boundaries locally only.
-- Targets are synthetic server effects, not proof of a BFF clinical calculator.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_full_fixture.sql

CREATE FUNCTION m3b_cycle_test.clinical_seed(n integer,phase text,completed timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;
BEGIN
 a:=m3b_cycle_test.seed(n,coalesce(completed,clock_timestamp()-interval '6 days'));
 UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,weight_kg=80,
  body_fat_percent=CASE WHEN phase='ganho_massa' THEN 15 ELSE 24 END,activity_level='moderado',
  training_frequency=4,hunger_level='moderada',current_protocol=phase::public.protocol_enum,
  deficit_level=CASE WHEN phase='recomposicao' THEN 500 END WHERE user_id=a;
 RETURN a;
END $$;
CREATE FUNCTION m3b_cycle_test.refuse_clinical(a uuid,request jsonb,expected_message text,label text,
 at_time timestamptz DEFAULT NULL,expected_state text DEFAULT '40001')
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE code text;message text;before_rows jsonb;
BEGIN
 before_rows:=m3b_cycle_test.original_state(a);
 BEGIN
  PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
   request->'form',request->'intent',request->'proposal',at_time);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
 END;
 PERFORM m3b_cycle_test.ok(code=expected_state AND message=expected_message
  AND before_rows=m3b_cycle_test.original_state(a),label||' [code='||coalesce(code,'NONE')||', message='||coalesce(message,'NONE')||']');
END $$;
CREATE FUNCTION m3b_cycle_test.kind_form(phase text,kind text,sessions integer DEFAULT NULL,level text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'phase',phase,'kind',kind,'activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',sessions,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
   'healthCheck',CASE WHEN kind IN('REGULAR','EARLY_FULL') THEN jsonb_build_object('kind','none') ELSE NULL END,
   'professionalConversationConfirmed',NULL,'activity',CASE WHEN level IS NULL THEN NULL ELSE jsonb_build_object(
    'otherExerciseType',NULL,'otherExerciseDays',NULL,'sessionMinutes',NULL,'sessionIntensity',NULL,'mostlySitting',NULL,
    'activityLevel',level,'activityLevelConfirmed',true) END))
$$;
CREATE FUNCTION m3b_cycle_test.kind_effect(phase text,level text,frequency integer,before_kcal integer,after_kcal integer,
 principal text DEFAULT 'keep') RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'principal',principal,'clearHold',false,'profile',jsonb_build_object(
  'current_protocol',phase,'deficit_level',CASE WHEN phase='recomposicao' THEN 500 END,'activity_level',level,'training_frequency',frequency,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',before_kcal,'beforeProtein',144,'afterKcal',after_kcal,'afterProtein',144,'formulaAfterKcal',after_kcal),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL))
$$;
CREATE FUNCTION m3b_cycle_test.kind_prepare(a uuid,kind text,cycle uuid,form jsonb,intent jsonb,proposal jsonb,at_time timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;preview jsonb;
BEGIN
 -- Explicit synthetic baseline for these review-kind cases. A number in a
 -- proposal never stands in for a missing stored target in the real writer.
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 SELECT a,(coalesce(at_time,clock_timestamp()) AT TIME ZONE u.timezone)::date,
  (proposal#>>'{targets,beforeKcal}')::integer,(proposal#>>'{targets,beforeProtein}')::numeric,p.current_protocol
 FROM public.users u JOIN public.user_profiles p ON p.user_id=u.id
 WHERE u.id=a AND proposal#>>'{targets,beforeKcal}' IS NOT NULL
 ON CONFLICT(user_id,date) DO NOTHING;
 context:=private.capture_mobile_clinical_context_at(a,kind,cycle,at_time);
 preview:=private.prepare_mobile_clinical_preview_at(a,kind,cycle,gen_random_uuid(),context->>'context_hash',form,intent,proposal,at_time);
 RETURN jsonb_build_object('context',context,'preview',preview,'form',form,'intent',intent,'proposal',proposal);
END $$;

DO $early$
DECLARE a uuid;start_key uuid:=gen_random_uuid();s jsonb;repeated jsonb;cycle uuid;request jsonb;result jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.clinical_seed(1600,'ganho_massa');
 s:=private.start_mobile_clinical_full_at(a,start_key,'EARLY_FULL','gain_review_notice',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 repeated:=private.start_mobile_clinical_full_at(a,start_key,'EARLY_FULL','gain_review_notice',NULL);
 PERFORM m3b_cycle_test.ok(s=repeated AND s#>>'{cycle,kind}'='EARLY_FULL'
  AND (SELECT count(*)=1 FROM private.mobile_reevaluation_cycles WHERE user_id=a),'early start replay opens exactly one early occurrence');
 PERFORM m3b_cycle_test.throws(format('SELECT private.start_mobile_clinical_full_at(%L,%L,''EARLY_FULL'',''not_well_with_plan'',NULL)',a,start_key),
  '40001','same start key cannot change early reason');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_consent(%L,%L)',a,cycle),
  '40001','early occurrence cannot allocate regular body photo authority');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,m3b_cycle_test.kind_form('ganho_massa','EARLY_FULL'),
  '{"principalConfirmed":false}',m3b_cycle_test.kind_effect('ganho_massa','moderado',4,2993,2993));
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'kind'='EARLY_FULL' AND (SELECT difficulty_count IS NULL FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND (SELECT count(*)=0 FROM private.mobile_weight_measurements WHERE user_id=a),'early FULL preserves unknown counter and creates no blank weight measurement');
 PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)#>>'{clock,base_date}'=day::text
  AND public.get_mobile_reevaluation_cycle(a)#>>'{clock,due_date}'=(day+14)::text,
  'actual early FULL moves base once without counting a regular fortnight');
END $early$;

DO $late_early$
DECLARE a uuid;k uuid:=gen_random_uuid();s jsonb;cycle uuid;later timestamptz:=clock_timestamp()+interval '9 days';
 c jsonb;request jsonb;before_rows jsonb;
BEGIN
 a:=m3b_cycle_test.clinical_seed(1601,'ganho_massa');
 s:=private.start_mobile_clinical_full_at(a,k,'EARLY_FULL','gain_review_notice',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''EARLY_FULL'',%L,%L)',a,cycle,later),
  '40001','abandoned early cannot conclude as early after a complete fortnight');
 s:=private.start_mobile_clinical_full_at(a,k,'EARLY_FULL','gain_review_notice',later);
 PERFORM m3b_cycle_test.ok(s#>>'{cycle,id}'=cycle::text AND s#>>'{cycle,kind}'='REGULAR'
  AND (s#>>'{cycle,revision}')::bigint=2,'due early promotes same occurrence to regular with new revision');
 request:=m3b_cycle_test.kind_prepare(a,'REGULAR',cycle,m3b_cycle_test.kind_form('ganho_massa','REGULAR'),
  '{"principalConfirmed":false}',m3b_cycle_test.kind_effect('ganho_massa','moderado',4,2993,2993),later);
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,%L)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal',later),
  '40001','promoted regular requires three new processed photos and explicit mean acceptance');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
  AND (SELECT status='open' FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),
  'missing regular photos cannot write answers profile or move base');
END $late_early$;

DO $routine$
DECLARE a uuid;s jsonb;cycle uuid;request jsonb;result jsonb;clock_before jsonb;clock_after jsonb;context jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.clinical_seed(1610,'manutencao');clock_before:=public.get_mobile_reevaluation_cycle(a)->'clock';
 INSERT INTO public.user_progress(user_id) VALUES(a);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,2609,144,'manutencao');
 request:=m3b_cycle_test.kind_prepare(a,'ROUTINE_REVIEW',NULL,m3b_cycle_test.kind_form('manutencao','ROUTINE_REVIEW',5,'alto'),
  '{"principalConfirmed":true}',m3b_cycle_test.kind_effect('manutencao','alto',5,2609,2904,'activity'));
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 clock_after:=public.get_mobile_reevaluation_cycle(a)->'clock';
 PERFORM m3b_cycle_test.ok(result->>'kind'='ROUTINE_REVIEW' AND result->'cycle_id'='null'::jsonb AND clock_after=clock_before
  AND (SELECT count(*)=0 FROM private.mobile_reevaluation_cycles WHERE user_id=a),
  'routine confirmation never opens FULL occurrence or advances base');
 PERFORM m3b_cycle_test.ok((SELECT activity_level='alto' AND training_frequency=5 AND current_protocol='manutencao'
  FROM public.user_profiles WHERE user_id=a) AND (SELECT calories_target=2904 AND protein_target=144
  FROM public.daily_snapshots WHERE user_id=a AND date=day),'routine profile and open day targets change together on confirmation');
 PERFORM public.advance_reevaluation_schedule(a,day+20);
 PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->'clock'=clock_before,
  'actual legacy schedule writer cannot change typed clinical base');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,m3b_cycle_test.kind_form('manutencao','EARLY_FULL'),
  '{"principalConfirmed":false}',m3b_cycle_test.kind_effect('manutencao','alto',5,2904,2904));
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 context:=private.capture_mobile_clinical_context_at(a,'ROUTINE_REVIEW',NULL,NULL);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(context#>'{facts,protocol_authority,routine_reviews_since_regular}')=1
  AND context#>>'{facts,protocol_authority,routine_reviews_since_regular,0,activity_level_changed}'='true',
  'early FULL does not erase actual routine level change since previous REGULAR');
END $routine$;

DO $safety$
DECLARE c jsonb;a uuid;old_cycle uuid;request jsonb;result jsonb;proposal jsonb;before_rows jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.clinical_photos(1620);a:=(c->>'user')::uuid;old_cycle:=(c->>'cycle')::uuid;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,1700,120,'recomposicao');
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,1700,2609,'neutral_exit');
 proposal:=jsonb_set(jsonb_set(jsonb_set(proposal,'{targets,beforeProtein}','120'),'{episode,ledgerSteps}','[]'),
  '{episode,maintenanceSince}',to_jsonb(day::text));
 request:=m3b_cycle_test.kind_prepare(a,'SAFETY',NULL,m3b_cycle_test.kind_form('recomposicao','SAFETY',4,'moderado'),
  '{"principalConfirmed":true}',proposal);
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'kind'='SAFETY' AND result->>'cycle_id'<>old_cycle::text
  AND (SELECT status='invalidated' FROM private.mobile_reevaluation_cycles WHERE cycle_id=old_cycle)
  AND (SELECT count(*)=1 FROM private.mobile_reevaluation_cycles WHERE user_id=a AND status='completed'),
  'confirmed safety exit invalidates open regular and records exactly one completed safety occurrence');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=3 AND bool_and(invalidated_reason='cycle_changed')
  FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
  AND (SELECT manifest_count=3 FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=a),
  'safety displacement seals old regular photo scope without claiming Storage removal');
 PERFORM m3b_cycle_test.ok(public.get_mobile_health_hold_state(a)->>'hold_active'='true'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_health_clear_receipts WHERE user_id=a)
  AND public.get_mobile_reevaluation_cycle(a)#>>'{clock,base_date}'=day::text,
  'safety confirmation moves base but cannot clear HOLD');
 a:=m3b_cycle_test.clinical_seed(1621,'recomposicao');
 UPDATE public.user_profiles SET weight_kg=50 WHERE user_id=a;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,1700,2609,'neutral_exit');
 proposal:=jsonb_set(proposal,'{episode,ledgerSteps}','[]');
 request:=m3b_cycle_test.kind_prepare(a,'SAFETY',NULL,m3b_cycle_test.kind_form('recomposicao','SAFETY',4,'moderado'),
  '{"principalConfirmed":true}',proposal);before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal'),
  '40001','approved A1 protection refuses neutral exit and any automatic substitute target');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles WHERE user_id=a),
  'refused safety change writes no occurrence and preserves profile HOLD and targets');
END $safety$;
DO $activity_priority$
DECLARE a uuid;c jsonb;s jsonb;cycle uuid;request jsonb;form jsonb;intent jsonb;proposal jsonb;candidate jsonb;
 phase text;doc public.legal_documents%ROWTYPE;consent jsonb;code text;message text;at_time timestamptz;
 before_rows jsonb;n integer:=1640;
BEGIN
 FOREACH phase IN ARRAY ARRAY['manutencao','ganho_massa'] LOOP
  -- Private clocks make an actual routine -> EARLY -> REGULAR sequence in the
  -- disposable local fixture. This never backdates provider or customer data.
  a:=m3b_cycle_test.clinical_seed(n,phase,clock_timestamp()-interval '25 days');n:=n+1;
  at_time:=clock_timestamp()-interval '20 days';
  request:=m3b_cycle_test.kind_prepare(a,'ROUTINE_REVIEW',NULL,m3b_cycle_test.kind_form(phase,'ROUTINE_REVIEW',5,'alto'),
   '{"principalConfirmed":true}',m3b_cycle_test.kind_effect(phase,'alto',5,2609,2904,'activity'),at_time);
  PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
   request->'form',request->'intent',request->'proposal',at_time);
  at_time:=clock_timestamp()-interval '15 days';
  s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',at_time);
  request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',(s#>>'{cycle,id}')::uuid,m3b_cycle_test.kind_form(phase,'EARLY_FULL'),
   '{"principalConfirmed":false}',m3b_cycle_test.kind_effect(phase,'alto',5,2904,2904),at_time);
  PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
   request->'form',request->'intent',request->'proposal',at_time);
  s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'REGULAR',NULL,NULL);cycle:=(s#>>'{cycle,id}')::uuid;
  SELECT * INTO STRICT doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
  consent:=public.accept_mobile_reevaluation_photo_consent(a,cycle,(s#>>'{cycle,revision}')::bigint,doc.id,doc.document_key,
   doc.version,doc.locale,doc.body_hash,gen_random_uuid());
  c:=m3b_cycle_test.process_clinical_photos(jsonb_build_object('user',a,'cycle',cycle,
   'revision',consent->'cycle_revision','acceptance',consent#>'{acceptance,acceptance_id}'));
  candidate:=private.mobile_clinical_body_fat_candidate_at(a,cycle,NULL);
  form:=m3b_cycle_test.kind_form(phase,'REGULAR');
  intent:=jsonb_build_object('principalConfirmed',true,'bodyFat',jsonb_build_object('confirmed',true,
   'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
  proposal:=m3b_cycle_test.kind_effect(phase,'alto',5,2904,3004,
   CASE phase WHEN 'manutencao' THEN 'maintenance_step' ELSE 'gain_step' END);
  proposal:=jsonb_set(proposal,'{episode,ledgerSteps}','[100]');
  request:=m3b_cycle_test.kind_prepare(a,'REGULAR',cycle,form,intent,proposal);
  before_rows:=m3b_cycle_test.original_state(a);
  code:=NULL;message:=NULL;
  BEGIN
   PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),form,intent,proposal,NULL);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
  END;
  PERFORM m3b_cycle_test.ok(code='40001' AND message='mobile_clinical_activity_priority'
   AND before_rows=m3b_cycle_test.original_state(a),
   phase||': regular calorie step is refused specifically by actual prior routine level change even after EARLY');
 END LOOP;
END $activity_priority$;
DO $actual_r$
DECLARE a uuid;s jsonb;cycle uuid;request jsonb;form jsonb;proposal jsonb;before_rows jsonb;
 code text;message text;day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.clinical_seed(1650,'recomposicao');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 form:=m3b_cycle_test.kind_form('recomposicao','EARLY_FULL',4,'moderado');
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,2109,2609,'phase_maintenance');
 proposal:=jsonb_set(jsonb_set(proposal,'{episode,ledgerSteps}','[]'),'{episode,maintenanceSince}',to_jsonb((day-1)::text));
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 before_rows:=m3b_cycle_test.original_state(a);
 BEGIN
  PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
   form,request->'intent',proposal,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
 END;
 PERFORM m3b_cycle_test.ok(code='40001' AND message='mobile_clinical_R_unproven'
  AND before_rows=m3b_cycle_test.original_state(a),'new maintenance episode cannot backdate R to yesterday');
 proposal:=jsonb_set(proposal,'{episode,maintenanceSince}',to_jsonb(day::text));
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  form,request->'intent',proposal,NULL);
 PERFORM m3b_cycle_test.ok((SELECT maintenance_since=day AND entry_date=day
  FROM private.mobile_clinical_episode_events WHERE user_id=a),'confirmed direct maintenance starts R on actual application date');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(calories_target=2609 AND formula_target=2609)
  FROM private.mobile_clinical_day_events WHERE user_id=a AND date=day)
  AND EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a AND date=day
   AND calories_target=2609 AND current_protocol='manutencao' AND NOT day_closed),
  'a confirmed direct maintenance event corresponds to an actual open snapshot target');
END $actual_r$;
DO $closed_r$
DECLARE a uuid;s jsonb;cycle uuid;request jsonb;form jsonb;proposal jsonb;before_day jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.clinical_seed(1651,'recomposicao');
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at,
  calories_consumed,exercise_calories) VALUES(a,day,2109,144,'recomposicao',true,clock_timestamp(),2000,100);
 SELECT to_jsonb(ds) INTO before_day FROM public.daily_snapshots ds WHERE user_id=a AND date=day;
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 form:=m3b_cycle_test.kind_form('recomposicao','EARLY_FULL',4,'moderado');
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,2109,2609,'phase_maintenance');
 proposal:=jsonb_set(proposal,'{episode,ledgerSteps}','[]');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(before_day=(SELECT to_jsonb(ds) FROM public.daily_snapshots ds WHERE user_id=a AND date=day)
  AND (SELECT maintenance_since IS NULL AND phase='manutencao' FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a),
  'a closed day is preserved and cannot establish R for an unapplied new target');
END $closed_r$;
DO $frozen_schedule$
DECLARE a uuid;s jsonb;cycle uuid;request jsonb;form jsonb;proposal jsonb;plan jsonb;bad jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;later timestamptz:=clock_timestamp()+interval '7 days';
BEGIN
 a:=m3b_cycle_test.clinical_seed(1660,'recomposicao');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 form:=m3b_cycle_test.kind_form('recomposicao','EARLY_FULL');
 plan:=jsonb_build_object('version',1,'kind','recomp_to_maintenance','state','running','startDate',day,
  'startTargetKcal',2109,'maintenanceTargetKcal',2609,'plannedEndDate',day+28);
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,2109,2209,'recomposition_transition');
 proposal:=jsonb_set(jsonb_set(jsonb_set(proposal,'{episode,ledgerSteps}','[]'),'{episode,schedule}',plan),
  '{targets,formulaAfterKcal}','2609');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
  'schedule start requires explicit activity confirmation even when level is unchanged');
 form:=m3b_cycle_test.kind_form('recomposicao','EARLY_FULL',4,'moderado');
 bad:=jsonb_set(jsonb_set(proposal,'{episode,schedule,startDate}',to_jsonb((day-1)::text)),
  '{episode,schedule,plannedEndDate}',to_jsonb((day+27)::text));
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',bad);
 PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
  'a new schedule cannot backdate C');
 bad:=jsonb_set(jsonb_set(proposal,'{episode,schedule,kind}','"gain_exit"'),
  '{episode,schedule,plannedEndDate}',to_jsonb(day::text));
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',bad);
 PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
  'n5 principal cannot install an n18 schedule');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok((SELECT schedule=plan AND phase='manutencao' AND maintenance_since IS NULL
  FROM private.mobile_clinical_episode_events WHERE user_id=a),'confirmed n5 stores frozen plan without inventing R');
 form:=m3b_cycle_test.kind_form('manutencao','ROUTINE_REVIEW');
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,2209,2209);
 proposal:=jsonb_set(jsonb_set(jsonb_set(proposal,'{episode,ledgerSteps}','[]'),'{episode,schedule}',plan),
  '{targets,formulaAfterKcal}','2609');
 bad:=jsonb_set(jsonb_set(proposal,'{episode,schedule,maintenanceTargetKcal}','2709'),
  '{episode,schedule,plannedEndDate}',to_jsonb((day+35)::text));
 request:=m3b_cycle_test.kind_prepare(a,'ROUTINE_REVIEW',NULL,form,'{"principalConfirmed":false}',bad);
 PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
  'keep cannot silently replace frozen values even with a canonical schedule');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 form:=m3b_cycle_test.kind_form('manutencao','EARLY_FULL');
 proposal:=jsonb_set(jsonb_set(proposal,'{principal}','"schedule_pause"'),'{episode,schedule,state}','"suspended"');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok((SELECT schedule=jsonb_set(plan,'{state}','"suspended"') AND maintenance_since IS NULL
  FROM private.mobile_clinical_episode_events WHERE user_id=a ORDER BY event_no DESC LIMIT 1),
  'pause preserves frozen values and keeps R unknown');
 form:=m3b_cycle_test.kind_form('manutencao','ROUTINE_REVIEW');
 proposal:=jsonb_set(jsonb_set(proposal,'{principal}','"keep"'),'{episode,schedule}',plan);
 request:=m3b_cycle_test.kind_prepare(a,'ROUTINE_REVIEW',NULL,form,'{"principalConfirmed":false}',proposal);
 PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
  'keep cannot automatically resume a suspended schedule');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 form:=m3b_cycle_test.kind_form('manutencao','EARLY_FULL',4,'moderado');
 plan:=jsonb_build_object('version',1,'kind','recomp_to_maintenance','state','running','startDate',day,
  'startTargetKcal',2209,'maintenanceTargetKcal',2509,'plannedEndDate',day+14);
 proposal:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(proposal,'{principal}','"schedule_reconfirm"'),'{episode,schedule}',plan),
  '{targets,afterKcal}','2309'),'{targets,formulaAfterKcal}','2509');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok((SELECT schedule=plan AND maintenance_since IS NULL
  FROM private.mobile_clinical_episode_events WHERE user_id=a ORDER BY event_no DESC LIMIT 1),
  'only a separately confirmed fresh plan resumes a paused n5 schedule');
 form:=m3b_cycle_test.kind_form('manutencao','ROUTINE_REVIEW');
 proposal:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(proposal,'{principal}','"keep"'),'{targets,beforeKcal}','2309'),
  '{targets,afterKcal}','2350'),'{targets,formulaAfterKcal}','2350');
 proposal:=jsonb_set(proposal,'{episode,maintenanceSince}',to_jsonb((day+7)::text));
 request:=m3b_cycle_test.kind_prepare(a,'ROUTINE_REVIEW',NULL,form,'{"principalConfirmed":false}',proposal,later);
 bad:=jsonb_set(proposal,'{episode,maintenanceSince}',to_jsonb((day+14)::text));
 s:=m3b_cycle_test.kind_prepare(a,'ROUTINE_REVIEW',NULL,form,'{"principalConfirmed":false}',bad,later);
 PERFORM m3b_cycle_test.refuse_clinical(a,s,'mobile_clinical_R_unproven',
  'planned end is not proof of R at an earlier actual application',later);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',later);
 PERFORM m3b_cycle_test.ok((SELECT schedule=plan AND maintenance_since=day+7
  FROM private.mobile_clinical_episode_events WHERE user_id=a ORDER BY event_no DESC LIMIT 1),
  'n5 reaches lower M today before its frozen end and establishes R only on application');
END $frozen_schedule$;
DO $gain_schedule$
DECLARE a uuid;s jsonb;cycle uuid;request jsonb;form jsonb;proposal jsonb;plan jsonb;immediate boolean;
 n integer:=1670;day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 FOREACH immediate IN ARRAY ARRAY[false,true] LOOP
  a:=m3b_cycle_test.clinical_seed(n,'ganho_massa');n:=n+1;
  s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','gain_review_notice',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
  form:=m3b_cycle_test.kind_form('ganho_massa','EARLY_FULL',4,'moderado');
  plan:=jsonb_build_object('version',1,'kind','gain_exit','state','running','startDate',day,
   'startTargetKcal',CASE WHEN immediate THEN 2500 ELSE 2993 END,'maintenanceTargetKcal',2609,
   'plannedEndDate',CASE WHEN immediate THEN day ELSE day+21 END);
  proposal:=m3b_cycle_test.kind_effect(CASE WHEN immediate THEN 'manutencao' ELSE 'ganho_massa' END,'moderado',4,
   CASE WHEN immediate THEN 2500 ELSE 2993 END,CASE WHEN immediate THEN 2609 ELSE 2893 END,'gain_exit');
  proposal:=jsonb_set(proposal,'{episode,schedule}',plan);
  IF immediate THEN
   proposal:=jsonb_set(jsonb_set(proposal,'{episode,ledgerSteps}','[]'),'{episode,maintenanceSince}',to_jsonb(day::text));
  ELSE
   request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
   PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
    'n18 budget formula must stay at confirmed frozen M during the gain ramp');
  END IF;
  proposal:=jsonb_set(proposal,'{targets,formulaAfterKcal}','2609');
  request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
  PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
   request->'form',request->'intent',request->'proposal',NULL);
  PERFORM m3b_cycle_test.ok((SELECT schedule=plan AND phase=CASE WHEN immediate THEN 'manutencao' ELSE 'ganho_massa' END
   AND maintenance_since IS NOT DISTINCT FROM CASE WHEN immediate THEN day END
   FROM private.mobile_clinical_episode_events WHERE user_id=a),
   CASE WHEN immediate THEN 'G below M enters maintenance with actual R on E'
    ELSE 'n18 first step applies on E while phase remains gain and R stays unknown' END);
  PERFORM m3b_cycle_test.ok((SELECT formula_target=2609 AND effective_adjustment=calories_target-2609
   FROM private.mobile_clinical_day_events WHERE user_id=a),
   'n18 confirmed day authority records frozen M and its effective adjustment');
  IF NOT immediate THEN
   s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','gain_review_notice',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
   proposal:=jsonb_set(jsonb_set(jsonb_set(proposal,'{principal}','"schedule_pause"'),'{episode,schedule,state}','"suspended"'),
    '{targets,beforeKcal}','2893');
   request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
   PERFORM m3b_cycle_test.refuse_clinical(a,request,'mobile_clinical_schedule_effect_mismatch',
    'n18 has no ordinary in-app cancellation');
  END IF;
 END LOOP;
END $gain_schedule$;
DO $transition_safety$
DECLARE a uuid;s jsonb;cycle uuid;request jsonb;form jsonb;proposal jsonb;plan jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.clinical_seed(1680,'recomposicao');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 plan:=jsonb_build_object('version',1,'kind','recomp_to_maintenance','state','running','startDate',day,
  'startTargetKcal',2109,'maintenanceTargetKcal',2609,'plannedEndDate',day+28);
 form:=m3b_cycle_test.kind_form('recomposicao','EARLY_FULL',4,'moderado');
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,2109,2209,'recomposition_transition');
 proposal:=jsonb_set(jsonb_set(jsonb_set(proposal,'{episode,ledgerSteps}','[]'),'{episode,schedule}',plan),'{targets,formulaAfterKcal}','2609');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 form:=m3b_cycle_test.kind_form('manutencao','EARLY_FULL');
 proposal:=m3b_cycle_test.kind_effect('ganho_massa','moderado',4,2209,2700);
 proposal:=jsonb_set(proposal,'{episode,ledgerSteps}','[]');
 request:=m3b_cycle_test.kind_prepare(a,'EARLY_FULL',cycle,form,'{"principalConfirmed":false}',proposal);
 PERFORM m3b_cycle_test.refuse_clinical(a,request,'invalid_mobile_clinical_effects',
  'keep cannot use a prior schedule as permission for a different phase',NULL,'22023');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 form:=m3b_cycle_test.kind_form('manutencao','SAFETY',4,'moderado');
 proposal:=m3b_cycle_test.kind_effect('manutencao','moderado',4,2209,2609,'neutral_exit');
 proposal:=jsonb_set(jsonb_set(proposal,'{episode,ledgerSteps}','[]'),'{episode,maintenanceSince}',to_jsonb(day::text));
 request:=m3b_cycle_test.kind_prepare(a,'SAFETY',NULL,form,'{"principalConfirmed":true}',proposal);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok((SELECT schedule IS NULL AND maintenance_since=day AND phase='manutencao'
  FROM private.mobile_clinical_episode_events WHERE user_id=a ORDER BY event_no DESC LIMIT 1)
  AND public.get_mobile_health_hold_state(a)->>'hold_active'='true',
  'eligible n10 direct exit ends an n5 transition already in maintenance without clearing HOLD');
END $transition_safety$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT m3b_cycle_test.ok(true,'all kind transactions satisfy actual deferred foreign keys');
ROLLBACK;

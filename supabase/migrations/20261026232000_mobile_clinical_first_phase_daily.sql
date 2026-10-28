-- Genuine first-phase source for prospective daily applications. Dormant.
-- No reconstruction of an initial choice as a FULL or a signup event.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_first_phase_confirmations') IS NULL THEN
  RAISE EXCEPTION 'clinical_daily_requires_first_phase_authority' USING ERRCODE='42501';END IF;
END $$;
ALTER TABLE private.mobile_clinical_daily_applications
 ALTER COLUMN source_review_id DROP NOT NULL,
 ADD COLUMN source_first_phase_id uuid,
 ADD FOREIGN KEY(user_id,source_first_phase_id) REFERENCES private.mobile_clinical_first_phase_confirmations(user_id,first_phase_id)
  DEFERRABLE INITIALLY DEFERRED,
 ADD CONSTRAINT mobile_clinical_daily_one_source CHECK(num_nonnulls(source_review_id,source_first_phase_id)=1);
-- A daily application remains the unique source of an applied target. This
-- additional pointer records its genuine confirmed decision, not a second source.
ALTER TABLE private.mobile_clinical_target_origins
 ADD COLUMN decision_first_phase_id uuid,
 ADD FOREIGN KEY(user_id,decision_first_phase_id) REFERENCES private.mobile_clinical_first_phase_confirmations(user_id,first_phase_id)
  DEFERRABLE INITIALLY DEFERRED,
 ADD CHECK(num_nonnulls(decision_review_id,decision_first_phase_id)<=1);

CREATE OR REPLACE FUNCTION private.mobile_clinical_calorie_basis(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_kind text,p_reference uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE o private.mobile_clinical_target_origins%ROWTYPE;d private.mobile_clinical_calorie_decisions%ROWTYPE;
 initial private.mobile_clinical_first_phase_confirmations%ROWTYPE;
BEGIN
 IF p_kind='application' THEN
  SELECT * INTO o FROM private.mobile_clinical_target_origins WHERE user_id=p_user_id AND application_id=p_reference
   AND signup_generation=p_generation AND signup_epoch=p_epoch;
 ELSIF p_kind='first_after' THEN
  SELECT * INTO initial FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id
   AND first_phase_id=p_reference AND signup_generation=p_generation AND signup_epoch=p_epoch;
  IF NOT FOUND THEN RETURN NULL;END IF;
  RETURN jsonb_build_object('basis_type','first_phase_decision','first_phase_id',initial.first_phase_id,
   'phase',initial.phase,'calories_target',(initial.proposal#>>'{targets,afterKcal}')::integer,
   'formula_target',(initial.proposal#>>'{targets,formulaAfterKcal}')::integer);
 ELSIF p_kind IN('full_after','full_before') THEN
  SELECT * INTO d FROM private.mobile_clinical_calorie_decisions WHERE user_id=p_user_id AND review_id=p_reference
   AND signup_generation=p_generation AND signup_epoch=p_epoch;
  IF p_kind='full_before' THEN
   SELECT * INTO o FROM private.mobile_clinical_target_origins WHERE user_id=p_user_id AND origin_id=d.parent_origin_id
    AND signup_generation=p_generation AND signup_epoch=p_epoch;
  ELSIF d.review_id IS NOT NULL THEN
   RETURN jsonb_build_object('basis_type','decision','review_id',d.review_id,'phase',d.phase,
    'calories_target',d.calories_target,'formula_target',d.formula_target);
  ELSE
   SELECT * INTO o FROM private.mobile_clinical_target_origins WHERE user_id=p_user_id AND review_id=p_reference
    AND signup_generation=p_generation AND signup_epoch=p_epoch;
  END IF;
 ELSE RAISE EXCEPTION 'invalid_clinical_calorie_basis' USING ERRCODE='22023'; END IF;
 IF o.origin_id IS NULL THEN RETURN NULL; END IF;
 -- This is an immutable past input, NOT a claim about its old snapshot's
 -- current values. The daily branch explicitly selects which input it uses.
 RETURN to_jsonb(o)||jsonb_build_object('basis_type','origin');
END $$;

CREATE OR REPLACE FUNCTION private.record_mobile_clinical_daily_target_origin(p_user_id uuid,p_application uuid,
 p_snapshot uuid,p_basis jsonb) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE a private.mobile_clinical_daily_applications%ROWTYPE;s public.daily_snapshots%ROWTYPE;
 d private.mobile_clinical_calorie_decisions%ROWTYPE;initial private.mobile_clinical_first_phase_confirmations%ROWTYPE;
 kind text;formula integer;parent uuid;decision uuid;first_decision uuid;origin uuid;
BEGIN
 SELECT * INTO STRICT a FROM private.mobile_clinical_daily_applications WHERE user_id=p_user_id AND application_id=p_application;
 SELECT * INTO STRICT s FROM public.daily_snapshots WHERE user_id=p_user_id AND id=p_snapshot;
 IF s.date<>a.date OR s.day_closed OR s.updated_at<>a.applied_at OR s.current_protocol::text<>a.phase
  OR s.calories_target IS DISTINCT FROM a.calories_target OR s.protein_target IS DISTINCT FROM a.protein_target THEN
  RAISE EXCEPTION 'clinical_daily_target_origin_write_changed' USING ERRCODE='XX001'; END IF;
 IF a.result->>'reason'='episode_formula' THEN
  kind:='calculated';formula:=a.formula_target;
 ELSIF a.result->>'reason'='confirmed_target' AND a.source_first_phase_id IS NOT NULL THEN
  SELECT * INTO STRICT initial FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id
   AND first_phase_id=a.source_first_phase_id AND event_id=a.source_episode_event_id
   AND signup_generation=a.signup_generation AND signup_epoch=a.signup_epoch;
  IF initial.effective_date>a.date OR initial.confirmed_at>a.applied_at OR initial.phase<>a.phase
   OR (initial.proposal#>>'{targets,afterKcal}')::integer<>a.calories_target
   OR (initial.proposal#>>'{targets,formulaAfterKcal}')::integer<>a.formula_target THEN
   RAISE EXCEPTION 'clinical_daily_first_decision_changed' USING ERRCODE='XX001';END IF;
  kind:='confirmed';formula:=a.formula_target;first_decision:=initial.first_phase_id;
 ELSIF a.result->>'reason' IN('confirmed_schedule','confirmed_target') THEN
  SELECT * INTO d FROM private.mobile_clinical_calorie_decisions WHERE user_id=p_user_id
   AND review_id=coalesce(a.schedule_review_id,a.source_review_id)
   AND signup_generation=a.signup_generation AND signup_epoch=a.signup_epoch;
  IF NOT FOUND THEN RETURN; END IF;
  kind:='confirmed';formula:=a.formula_target;decision:=d.review_id;
 ELSIF p_basis IS NOT NULL AND (p_basis->>'calories_target')::integer=a.calories_target
  AND p_basis->>'phase'=a.phase THEN
  kind:='carried';formula:=(p_basis->>'formula_target')::integer;
  IF p_basis->>'basis_type'='origin' THEN
   parent:=(p_basis->>'origin_id')::uuid;
   IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins o WHERE o.user_id=p_user_id
    AND o.origin_id=parent AND o.signup_generation=a.signup_generation AND o.signup_epoch=a.signup_epoch
    AND o.phase=a.phase AND o.calories_target=a.calories_target AND o.formula_target=formula
    AND o.recorded_at<=a.applied_at) THEN
    RAISE EXCEPTION 'clinical_daily_calorie_parent_changed' USING ERRCODE='XX001'; END IF;
  ELSIF p_basis->>'basis_type'='decision' THEN
   decision:=(p_basis->>'review_id')::uuid;
   IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions x WHERE x.user_id=p_user_id
    AND x.review_id=decision AND x.signup_generation=a.signup_generation AND x.signup_epoch=a.signup_epoch
    AND x.phase=a.phase AND x.calories_target=a.calories_target AND x.formula_target=formula
    AND x.decided_at<=a.applied_at) THEN
    RAISE EXCEPTION 'clinical_daily_calorie_decision_changed' USING ERRCODE='XX001'; END IF;
  ELSIF p_basis->>'basis_type'='first_phase_decision' THEN
   first_decision:=(p_basis->>'first_phase_id')::uuid;
   IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_first_phase_confirmations x WHERE x.user_id=p_user_id
    AND x.first_phase_id=first_decision AND x.signup_generation=a.signup_generation AND x.signup_epoch=a.signup_epoch
    AND x.phase=a.phase AND (x.proposal#>>'{targets,afterKcal}')::integer=a.calories_target
    AND (x.proposal#>>'{targets,formulaAfterKcal}')::integer=formula
    AND x.confirmed_at<=a.applied_at AND x.effective_date<=a.date) THEN
    RAISE EXCEPTION 'clinical_daily_first_basis_changed' USING ERRCODE='XX001';END IF;
  ELSE RETURN; END IF;
 ELSE RETURN; END IF;
 IF a.calories_target IS NULL OR formula IS NULL THEN RETURN; END IF;
 INSERT INTO private.mobile_clinical_target_origins(user_id,signup_generation,signup_epoch,snapshot_id,date,phase,
  calories_target,protein_target,formula_target,application_id,origin_kind,deficit_level,parent_origin_id,decision_review_id,decision_first_phase_id,context_hash,recorded_at)
 VALUES(p_user_id,a.signup_generation,a.signup_epoch,s.id,s.date,a.phase,a.calories_target,a.protein_target,formula,
  a.application_id,kind,a.deficit_level,parent,decision,first_decision,a.context_hash,a.applied_at) RETURNING origin_id INTO origin;
 INSERT INTO private.mobile_clinical_target_origin_heads VALUES(s.id,p_user_id,origin)
  ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,origin_id=excluded.origin_id;
END $$;

CREATE OR REPLACE FUNCTION private.apply_mobile_clinical_daily_at(p_user_id uuid,p_operation_key uuid,p_context_hash text,
 p_calculation jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO, YMD' AS $$
DECLARE key_row private.mobile_clinical_daily_keys%ROWTYPE;head private.mobile_clinical_daily_applications%ROWTYPE;
 source private.mobile_clinical_episode_events%ROWTYPE;episode private.mobile_clinical_episode_events%ROWTYPE;
 review private.mobile_clinical_full_receipts%ROWTYPE;initial private.mobile_clinical_first_phase_confirmations%ROWTYPE;
 source_proposal jsonb;profile public.user_profiles%ROWTYPE;
 snapshot public.daily_snapshots%ROWTYPE;
 context jsonb;safety jsonb;result jsonb;frozen jsonb;plan jsonb;calculation_key text;
 observed timestamptz;today date;zone text;generation uuid;epoch uuid;request_hash text;fingerprint text;
 application_id uuid:=gen_random_uuid();application_no bigint;previous_id uuid;plan_review uuid;
 current_kcal integer;current_protein numeric;after_kcal integer;after_protein numeric;formula integer;
 calculated integer;maintenance integer;sedentary integer;protein numeric;maintenance_protein numeric;
 age_years integer;bmi numeric;blocked boolean;loss_guard boolean;no_plan boolean;unknown_guard boolean;
 state text:='none';reason text;step integer;net integer;reached boolean:=false;pending_confirmed_target boolean:=false;
 calorie_basis jsonb;written_snapshot uuid;signup_key record;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_operation_key IS NULL OR p_context_hash IS NULL OR p_context_hash !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(p_calculation) IS DISTINCT FROM 'object' OR octet_length(p_calculation::text)>8192
  OR p_calculation->'version' IS DISTINCT FROM '1'::jsonb
  OR NOT(p_calculation ?& ARRAY['version','formulaKcal','maintenanceKcal','sedentaryKcal','proteinTarget','maintenanceProteinTarget'])
  OR p_calculation-ARRAY['version','formulaKcal','maintenanceKcal','sedentaryKcal','proteinTarget','maintenanceProteinTarget']<>'{}'::jsonb THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_daily_calculation' USING ERRCODE='22023';
 END IF;
 FOREACH calculation_key IN ARRAY ARRAY['formulaKcal','maintenanceKcal','sedentaryKcal','proteinTarget','maintenanceProteinTarget'] LOOP
  IF p_calculation->calculation_key<>'null'::jsonb AND (
   jsonb_typeof(p_calculation->calculation_key)<>'number'
   OR (p_calculation->>calculation_key)::numeric NOT BETWEEN
    (CASE WHEN calculation_key IN('proteinTarget','maintenanceProteinTarget') THEN 0 ELSE 1 END)
    AND (CASE WHEN calculation_key IN('proteinTarget','maintenanceProteinTarget') THEN 9999.99 ELSE 2147483647 END)
   OR (calculation_key NOT IN('proteinTarget','maintenanceProteinTarget')
    AND trunc((p_calculation->>calculation_key)::numeric)<>(p_calculation->>calculation_key)::numeric)) THEN
   RAISE EXCEPTION 'invalid_mobile_clinical_daily_calculation' USING ERRCODE='22023';
  END IF;
 END LOOP;
 request_hash:=encode(extensions.digest(jsonb_build_object('context_hash',p_context_hash,'calculation',p_calculation)::text,'sha256'),'hex');
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO key_row FROM private.mobile_clinical_daily_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF key_row.request_hash<>request_hash THEN RAISE EXCEPTION 'mobile_clinical_daily_conflict' USING ERRCODE='40001'; END IF;
  RETURN key_row.result;
 END IF;
 SELECT k.request_hash,k.result INTO signup_key FROM private.mobile_clinical_signup_application_keys k
  WHERE k.user_id=p_user_id AND k.operation_key=p_operation_key;
 IF FOUND THEN
  IF signup_key.request_hash<>request_hash THEN RAISE EXCEPTION 'mobile_clinical_daily_conflict' USING ERRCODE='40001';END IF;
  RETURN signup_key.result;
 END IF;
 context:=private.capture_mobile_clinical_context_at(p_user_id,'APPLICATION',NULL,p_observed_at);
 observed:=(context->>'observed_at')::timestamptz;today:=(context#>>'{facts,calculation_date}')::date;
 zone:=context#>>'{facts,owner,timezone}';generation:=(context#>>'{facts,anchor,signup_generation}')::uuid;
 epoch:=(context#>>'{facts,anchor,signup_epoch}')::uuid;safety:=context#>'{facts,safety}';
 IF context->>'context_hash'<>p_context_hash OR observed>=(context->>'valid_until')::timestamptz THEN
  RAISE EXCEPTION 'mobile_clinical_daily_stale' USING ERRCODE='40001';
 END IF;
 SELECT * INTO source FROM private.mobile_clinical_episode_events WHERE user_id=p_user_id
  AND signup_generation=generation AND signup_epoch=epoch ORDER BY event_no DESC LIMIT 1;
 SELECT * INTO snapshot FROM public.daily_snapshots WHERE user_id=p_user_id AND date=today;
 IF source.event_id IS NULL AND NOT coalesce(snapshot.day_closed,false)
  AND EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=p_user_id
   AND signup_generation=generation AND signup_epoch=epoch) THEN
  RETURN private.apply_mobile_clinical_signup_targets(p_user_id,p_operation_key,context,p_calculation);
 END IF;
 IF source.event_id IS NULL OR coalesce(snapshot.day_closed,false) THEN
  result:=jsonb_build_object('version',1,'availability','unavailable','reason',
   CASE WHEN source.event_id IS NULL THEN 'clinical_episode_unavailable' ELSE 'day_closed' END,'date',today);
  INSERT INTO private.mobile_clinical_daily_keys VALUES(p_user_id,p_operation_key,request_hash,NULL,result,observed);
  RETURN result;
 END IF;
 IF source.first_phase_id IS NOT NULL THEN
  SELECT * INTO STRICT initial FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id
   AND first_phase_id=source.first_phase_id AND signup_generation=generation AND signup_epoch=epoch AND event_id=source.event_id;
  IF today<initial.effective_date THEN
   result:=jsonb_build_object('version',1,'availability','unavailable','reason','phase_not_started','date',today);
   INSERT INTO private.mobile_clinical_daily_keys VALUES(p_user_id,p_operation_key,request_hash,NULL,result,observed);
   RETURN result;
  END IF;
  IF initial.confirmed_at>observed THEN RAISE EXCEPTION 'mobile_clinical_daily_clock_reversed' USING ERRCODE='40001';END IF;
  source_proposal:=initial.proposal;
 ELSE
  SELECT * INTO STRICT review FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND review_id=source.review_id;
  source_proposal:=review.proposal;
 END IF;
 SELECT * INTO episode FROM private.mobile_clinical_effective_episode(p_user_id,generation,epoch);
 SELECT * INTO STRICT profile FROM public.user_profiles WHERE user_id=p_user_id;
 IF episode.phase IS DISTINCT FROM profile.current_protocol::text THEN
  RAISE EXCEPTION 'mobile_clinical_episode_drift' USING ERRCODE='40001';
 END IF;
 SELECT x.* INTO head FROM private.mobile_clinical_daily_heads h JOIN private.mobile_clinical_daily_applications x
  ON x.user_id=h.user_id AND x.application_id=h.application_id WHERE h.user_id=p_user_id;
 IF head.signup_generation=generation AND head.signup_epoch=epoch AND head.applied_at>observed THEN
  RAISE EXCEPTION 'mobile_clinical_daily_clock_reversed' USING ERRCODE='40001';
 END IF;
 fingerprint:=private.mobile_clinical_daily_fingerprint(p_user_id,source.event_id,generation,epoch,today,
  context#>'{facts,calculation_config}',safety);
 IF head.source_episode_event_id=source.event_id AND head.signup_generation=generation AND head.signup_epoch=epoch
  AND head.date=today AND head.post_fingerprint=fingerprint THEN
  INSERT INTO private.mobile_clinical_daily_keys VALUES(p_user_id,p_operation_key,request_hash,head.application_id,head.result,observed);
  RETURN head.result;
 END IF;
 IF snapshot.calories_target IS NOT NULL THEN
  current_kcal:=snapshot.calories_target;current_protein:=snapshot.protein_target;
  calorie_basis:=nullif(context#>'{facts,protocol_authority,target_origin}','null'::jsonb);
  IF calorie_basis IS NOT NULL THEN calorie_basis:=calorie_basis||jsonb_build_object('basis_type','origin'); END IF;
 ELSIF head.source_episode_event_id=source.event_id AND head.signup_generation=generation AND head.signup_epoch=epoch THEN
  current_kcal:=head.calories_target;current_protein:=head.protein_target;
  calorie_basis:=private.mobile_clinical_calorie_basis(p_user_id,generation,epoch,'application',head.application_id);
 ELSIF source.first_phase_id IS NOT NULL THEN
  IF initial.applied_snapshot_id IS NULL THEN
   -- The initial choice on a closed day did not apply its proposed target.
   current_kcal:=(initial.proposal#>>'{targets,beforeKcal}')::integer;
   current_protein:=(initial.proposal#>>'{targets,beforeProtein}')::numeric;
   calorie_basis:=NULL;
  ELSE
   current_kcal:=(initial.proposal#>>'{targets,afterKcal}')::integer;
   current_protein:=(initial.proposal#>>'{targets,afterProtein}')::numeric;
   calorie_basis:=private.mobile_clinical_calorie_basis(p_user_id,generation,epoch,'first_after',initial.first_phase_id);
  END IF;
 ELSIF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=p_user_id AND review_id=source.review_id) THEN
  -- The FULL was confirmed on a closed day (or had no calculated target).
  -- Its proposed after-target is not an already-applied current target.
  current_kcal:=(review.proposal#>>'{targets,beforeKcal}')::integer;current_protein:=(review.proposal#>>'{targets,beforeProtein}')::numeric;
  calorie_basis:=private.mobile_clinical_calorie_basis(p_user_id,generation,epoch,'full_before',review.review_id);
 ELSE
  current_kcal:=(review.proposal#>>'{targets,afterKcal}')::integer;current_protein:=(review.proposal#>>'{targets,afterProtein}')::numeric;
  calorie_basis:=private.mobile_clinical_calorie_basis(p_user_id,generation,epoch,'full_after',review.review_id);
 END IF;
 calculated:=(p_calculation->>'formulaKcal')::integer;maintenance:=(p_calculation->>'maintenanceKcal')::integer;
 sedentary:=(p_calculation->>'sedentaryKcal')::integer;protein:=(p_calculation->>'proteinTarget')::numeric;
 maintenance_protein:=(p_calculation->>'maintenanceProteinTarget')::numeric;
 formula:=coalesce(CASE WHEN head.source_episode_event_id=source.event_id THEN head.formula_target END,
  (source_proposal#>>'{targets,formulaAfterKcal}')::integer,calculated);
 age_years:=CASE WHEN profile.birth_date IS NOT NULL AND profile.birth_date<=today
  THEN extract(year FROM age(today,profile.birth_date))::integer END;
 bmi:=CASE WHEN profile.height_cm>0 AND profile.weight_kg IS NOT NULL THEN profile.weight_kg/power(profile.height_cm/100,2) END;
 unknown_guard:=age_years IS NULL OR bmi IS NULL;
 no_plan:=coalesce(age_years<18,false) OR coalesce((safety->>'declared_no_plan')::boolean,false);
 loss_guard:=coalesce(age_years>=18 AND bmi<18.5,false) OR coalesce(profile.body_fat_percent<=10,false);
 blocked:=unknown_guard OR no_plan OR loss_guard OR coalesce((safety->>'hold_active')::boolean,false);
 after_kcal:=current_kcal;after_protein:=current_protein;plan:=episode.schedule;
 IF plan IS NOT NULL THEN
  SELECT r.review_id,r.proposal#>'{episode,schedule}' INTO plan_review,frozen
   FROM private.mobile_clinical_full_receipts r WHERE r.user_id=p_user_id
    AND r.signup_generation=generation AND r.signup_epoch=epoch
    AND r.principal IN('recomposition_transition','gain_exit','schedule_reconfirm')
    AND (r.proposal#>'{episode,schedule}')-'state'=plan-'state'
   ORDER BY r.review_no DESC LIMIT 1;
  IF plan_review IS NULL THEN RAISE EXCEPTION 'mobile_clinical_schedule_unproven' USING ERRCODE='XX001'; END IF;
  IF today<(plan->>'startDate')::date THEN
   result:=jsonb_build_object('version',1,'availability','unavailable','reason','schedule_not_started','date',today);
   INSERT INTO private.mobile_clinical_daily_keys VALUES(p_user_id,p_operation_key,request_hash,NULL,result,observed);
   RETURN result;
  END IF;
  IF blocked OR plan->>'state'='suspended' THEN
   plan:=jsonb_set(plan,'{state}','"suspended"');state:='suspended';reason:=CASE WHEN blocked THEN 'safety' ELSE 'confirmation_required' END;
  ELSE
   IF maintenance IS NULL OR protein IS NULL OR maintenance_protein IS NULL THEN
    RAISE EXCEPTION 'mobile_clinical_calculation_unavailable' USING ERRCODE='40001';
   END IF;
   step:=((today-(plan->>'startDate')::date)/7)+1;
   IF plan->>'kind'='gain_exit' THEN
    after_kcal:=greatest((plan->>'maintenanceTargetKcal')::integer,
     (plan->>'startTargetKcal')::numeric-step::numeric*100);
    formula:=(plan->>'maintenanceTargetKcal')::integer;
    reached:=after_kcal=formula;
   ELSE
    after_kcal:=least((plan->>'maintenanceTargetKcal')::integer,
     (plan->>'startTargetKcal')::numeric+step::numeric*100,maintenance);
    formula:=maintenance;reached:=after_kcal=maintenance;
   END IF;
   state:=CASE WHEN reached THEN 'completed' ELSE 'running' END;reason:='confirmed_schedule';
   after_protein:=CASE WHEN reached OR plan->>'kind'='recomp_to_maintenance' THEN maintenance_protein ELSE protein END;
   IF reached THEN
    IF episode.phase<>'manutencao' THEN
     episode.episode_id:=gen_random_uuid();episode.phase:='manutencao';episode.entry_origin:='confirmed_phase_change';
     episode.entry_date:=today;episode.start_weight_kg:=profile.weight_kg;episode.start_height_cm:=profile.height_cm;
     episode.start_body_fat_percent:=profile.body_fat_percent;episode.start_training_frequency:=profile.training_frequency;
     episode.deficit_level:=NULL;episode.difficulty_count:=NULL;episode.ledger_steps:='{}';
    END IF;
    episode.maintenance_since:=coalesce(episode.maintenance_since,today);plan:=NULL;
   END IF;
  END IF;
 ELSE
  -- A direct phase change confirmed on a closed day has not established R.
  -- Only its original approved target (not a new target under HOLD) may do so.
  pending_confirmed_target:=episode.phase='manutencao' AND episode.maintenance_since IS NULL AND (
   (source.first_phase_id IS NOT NULL AND initial.phase='manutencao' AND NOT blocked)
   OR (source.review_id IS NOT NULL AND review.principal IN('phase_maintenance','neutral_exit','gain_exit')
    AND (NOT blocked OR (review.principal='neutral_exit' AND NOT unknown_guard AND NOT no_plan AND NOT loss_guard
     AND review.result->>'safety_revision'=safety->>'safety_revision'))));
  IF pending_confirmed_target THEN
   after_kcal:=(source_proposal#>>'{targets,afterKcal}')::integer;after_protein:=(source_proposal#>>'{targets,afterProtein}')::numeric;
   formula:=(source_proposal#>>'{targets,formulaAfterKcal}')::integer;episode.maintenance_since:=today;reason:='confirmed_target';
  ELSIF blocked THEN reason:='safety';
  ELSIF snapshot.calories_target IS NOT NULL THEN reason:='stored_target';
  ELSIF calculated IS NULL OR protein IS NULL THEN
   RAISE EXCEPTION 'mobile_clinical_calculation_unavailable' USING ERRCODE='40001';
  ELSIF episode.phase<>'recomposicao' AND episode.ledger_steps IS NULL THEN reason:='unknown_ledger_preserved';
  ELSE
   SELECT coalesce(sum(x),0) INTO net FROM unnest(episode.ledger_steps) x;
   IF episode.phase='recomposicao' THEN after_kcal:=calculated;
   ELSIF episode.phase='manutencao' THEN
    IF sedentary IS NULL THEN RAISE EXCEPTION 'mobile_clinical_calculation_unavailable' USING ERRCODE='40001'; END IF;
    after_kcal:=greatest(sedentary,calculated+net);
   ELSE
    IF maintenance IS NULL THEN RAISE EXCEPTION 'mobile_clinical_calculation_unavailable' USING ERRCODE='40001'; END IF;
    after_kcal:=greatest(maintenance,calculated+net);
   END IF;
   after_protein:=protein;formula:=calculated;reason:='episode_formula';
  END IF;
 END IF;
 episode.schedule:=plan;episode.applied_at:=observed;
 SELECT coalesce(max(a.application_no),0)+1 INTO application_no FROM private.mobile_clinical_daily_applications a
  WHERE a.user_id=p_user_id AND a.signup_generation=generation;
 previous_id:=CASE WHEN head.signup_generation=generation AND head.signup_epoch=epoch THEN head.application_id END;
 IF episode.phase<>profile.current_protocol::text THEN
  INSERT INTO private.mobile_clinical_write_permits VALUES(p_user_id,pg_current_xact_id(),application_id);
  UPDATE public.user_profiles SET current_protocol=episode.phase::public.protocol_enum,deficit_level=episode.deficit_level,
   updated_at=observed WHERE user_id=p_user_id;
  DELETE FROM private.mobile_clinical_write_permits WHERE user_id=p_user_id AND transaction_id=pg_current_xact_id();
 END IF;
 IF after_kcal IS NOT NULL THEN
  INSERT INTO public.daily_snapshots AS actual(user_id,date,calories_target,protein_target,current_protocol,updated_at)
  VALUES(p_user_id,today,after_kcal,after_protein,episode.phase::public.protocol_enum,observed)
  ON CONFLICT(user_id,date) DO UPDATE SET calories_target=excluded.calories_target,protein_target=excluded.protein_target,
   current_protocol=excluded.current_protocol,updated_at=excluded.updated_at
   WHERE NOT actual.day_closed AND (ROW(actual.calories_target,actual.protein_target,actual.current_protocol)
    IS DISTINCT FROM ROW(excluded.calories_target,excluded.protein_target,excluded.current_protocol)
    OR reason IN('episode_formula','confirmed_schedule','confirmed_target'))
  RETURNING id INTO written_snapshot;
  IF NOT EXISTS(SELECT 1 FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=today
   AND NOT d.day_closed AND d.calories_target=after_kcal AND d.protein_target IS NOT DISTINCT FROM after_protein
   AND d.current_protocol::text=episode.phase) THEN
   RAISE EXCEPTION 'mobile_clinical_day_target_changed' USING ERRCODE='40001';
  END IF;
 END IF;
 fingerprint:=private.mobile_clinical_daily_fingerprint(p_user_id,source.event_id,generation,epoch,today,
  context#>'{facts,calculation_config}',safety);
 result:=jsonb_build_object('version',1,'availability','applied','application_id',application_id,
  'application_no',application_no::text,'date',today,'state',state,'reason',reason,
  'needs_new_confirmation',state='suspended' OR (state='running' AND today>=(frozen->>'plannedEndDate')::date),
  'applied_at',to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'source_kind',CASE WHEN source.first_phase_id IS NULL THEN 'full' ELSE 'first_phase' END,
  'source_first_phase_id',source.first_phase_id,'source_review_id',source.review_id,'schedule_review_id',plan_review,
  'targets',jsonb_build_object('calories_target',after_kcal,'protein_target',after_protein,'formula_target',formula,
   'effective_adjustment',after_kcal-formula),
  'episode',private.mobile_clinical_canonical_row(to_jsonb(episode),ARRAY['applied_at'],ARRAY['event_no','difficulty_count']));
 INSERT INTO private.mobile_clinical_daily_applications(user_id,application_id,signup_generation,signup_epoch,application_no,
  previous_application_id,source_episode_event_id,source_review_id,source_first_phase_id,schedule_review_id,context_hash,post_fingerprint,
  date,timezone_at_application,state,frozen_schedule,episode_id,phase,entry_origin,entry_date,
  start_weight_kg,start_height_cm,start_body_fat_percent,start_training_frequency,maintenance_since,deficit_level,
  difficulty_count,ledger_steps,schedule,calories_target,protein_target,formula_target,effective_adjustment,safety_revision,
  calculation,applied_at,result,rule_version)
 VALUES(p_user_id,application_id,generation,epoch,application_no,previous_id,source.event_id,source.review_id,source.first_phase_id,plan_review,
  p_context_hash,fingerprint,today,zone,state,frozen,episode.episode_id,episode.phase,episode.entry_origin,episode.entry_date,
  episode.start_weight_kg,episode.start_height_cm,episode.start_body_fat_percent,episode.start_training_frequency,
  episode.maintenance_since,episode.deficit_level,episode.difficulty_count,episode.ledger_steps,plan,
  after_kcal,after_protein,formula,after_kcal-formula,(safety->>'safety_revision')::bigint,p_calculation,observed,result,'clinical-v1');
 IF written_snapshot IS NOT NULL THEN
  PERFORM private.record_mobile_clinical_daily_target_origin(p_user_id,application_id,written_snapshot,calorie_basis);
 END IF;
 INSERT INTO private.mobile_clinical_daily_heads VALUES(p_user_id,application_id)
  ON CONFLICT(user_id) DO UPDATE SET application_id=excluded.application_id;
 INSERT INTO private.mobile_clinical_daily_keys VALUES(p_user_id,p_operation_key,request_hash,application_id,result,observed);
 RETURN result;
END $$;

REVOKE ALL ON FUNCTION private.mobile_clinical_calorie_basis(uuid,uuid,uuid,text,uuid),
 private.record_mobile_clinical_daily_target_origin(uuid,uuid,uuid,jsonb),
 private.apply_mobile_clinical_daily_at(uuid,uuid,text,jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

-- Dormant daily clinical authority. No public RPC, cron, route or feature flag.
-- Calculation inputs are private server outputs bound to the full fresh
-- context. A strict BFF calculator is still required before any activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.mobile_clinical_effective_episode(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_daily_requires_full_authority' USING ERRCODE='42501';
 END IF;
END $$;

CREATE TABLE private.mobile_clinical_daily_applications (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 application_id uuid NOT NULL DEFAULT gen_random_uuid(),
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 application_no bigint NOT NULL CHECK(application_no>0),
 previous_application_id uuid,
 source_episode_event_id uuid NOT NULL,
 source_review_id uuid NOT NULL,
 schedule_review_id uuid,
 context_hash text NOT NULL CHECK(context_hash ~ '^[0-9a-f]{64}$'),
 post_fingerprint text NOT NULL CHECK(post_fingerprint ~ '^[0-9a-f]{64}$'),
 date date NOT NULL CHECK(isfinite(date)),
 timezone_at_application text NOT NULL,
 state text NOT NULL CHECK(state IN('none','running','suspended','completed')),
 frozen_schedule jsonb CHECK(frozen_schedule IS NULL OR private.mobile_clinical_schedule_valid(frozen_schedule)),
 episode_id uuid NOT NULL,
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 entry_origin text NOT NULL CHECK(entry_origin IN('signup','confirmed_phase_change','legacy_unknown')),
 entry_date date CHECK(isfinite(entry_date)),
 start_weight_kg numeric(5,2) CHECK(start_weight_kg BETWEEN 30 AND 300),
 start_height_cm numeric CHECK(start_height_cm>0),
 start_body_fat_percent numeric CHECK(start_body_fat_percent BETWEEN 3 AND 60),
 start_training_frequency smallint CHECK(start_training_frequency BETWEEN 0 AND 7),
 maintenance_since date CHECK(isfinite(maintenance_since)),
 deficit_level integer CHECK(deficit_level IN(400,500,600)),
 difficulty_count bigint CHECK(difficulty_count BETWEEN 0 AND 9007199254740991),
 ledger_steps integer[] CHECK(private.mobile_clinical_ledger_valid(ledger_steps)),
 schedule jsonb CHECK(schedule IS NULL OR private.mobile_clinical_schedule_valid(schedule)),
 calories_target integer CHECK(calories_target>0),
 protein_target numeric(6,2) CHECK(protein_target BETWEEN 0 AND 9999.99),
 formula_target integer CHECK(formula_target>0),
 effective_adjustment integer,
 safety_revision bigint NOT NULL CHECK(safety_revision>=0),
 calculation jsonb NOT NULL CHECK(jsonb_typeof(calculation)='object'),
 applied_at timestamptz NOT NULL CHECK(isfinite(applied_at)),
 result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
 rule_version text NOT NULL CHECK(rule_version='clinical-v1'),
 PRIMARY KEY(user_id,application_id),UNIQUE(application_id),UNIQUE(user_id,signup_generation,application_no),
 FOREIGN KEY(user_id,signup_generation) REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,source_episode_event_id) REFERENCES private.mobile_clinical_episode_events(user_id,event_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,source_review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,schedule_review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,previous_application_id) REFERENCES private.mobile_clinical_daily_applications(user_id,application_id) DEFERRABLE INITIALLY DEFERRED,
 CONSTRAINT mobile_clinical_daily_deficit_authority CHECK(
  CASE WHEN phase='recomposicao' THEN deficit_level IS NOT NULL OR entry_origin='legacy_unknown'
   ELSE deficit_level IS NULL END),
 CHECK((frozen_schedule IS NULL)=(schedule_review_id IS NULL)),
 CHECK((state IN('running','suspended'))=(schedule IS NOT NULL)),
 CHECK(state<>'completed' OR (phase='manutencao' AND maintenance_since IS NOT NULL AND frozen_schedule IS NOT NULL)),
 CHECK(effective_adjustment IS NOT DISTINCT FROM calories_target-formula_target),
 CHECK(entry_origin<>'legacy_unknown' OR (entry_date IS NULL AND start_weight_kg IS NULL
  AND start_height_cm IS NULL AND start_body_fat_percent IS NULL AND start_training_frequency IS NULL))
);
CREATE TABLE private.mobile_clinical_daily_heads (
 user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 application_id uuid NOT NULL,
 FOREIGN KEY(user_id,application_id) REFERENCES private.mobile_clinical_daily_applications(user_id,application_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE private.mobile_clinical_daily_keys (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 request_hash text NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 application_id uuid,
 result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
 acknowledged_at timestamptz NOT NULL CHECK(isfinite(acknowledged_at)),
 PRIMARY KEY(user_id,operation_key),
 FOREIGN KEY(user_id,application_id) REFERENCES private.mobile_clinical_daily_applications(user_id,application_id) DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE private.mobile_clinical_daily_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_daily_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_daily_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_daily_applications,private.mobile_clinical_daily_heads,private.mobile_clinical_daily_keys
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_daily_application_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_daily_applications
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();
CREATE TRIGGER mobile_clinical_daily_key_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_daily_keys
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE OR REPLACE FUNCTION private.mobile_clinical_effective_episode(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS private.mobile_clinical_episode_events LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE e private.mobile_clinical_episode_events%ROWTYPE;a private.mobile_clinical_daily_applications%ROWTYPE;
BEGIN
 SELECT * INTO e FROM private.mobile_clinical_episode_events x WHERE x.user_id=p_user_id
  AND x.signup_generation=p_generation AND x.signup_epoch=p_epoch ORDER BY x.event_no DESC LIMIT 1;
 IF e.event_id IS NULL THEN RETURN e; END IF;
 SELECT x.* INTO a FROM private.mobile_clinical_daily_heads h JOIN private.mobile_clinical_daily_applications x
  ON x.user_id=h.user_id AND x.application_id=h.application_id
  WHERE h.user_id=p_user_id AND x.signup_generation=p_generation AND x.signup_epoch=p_epoch
   AND x.source_episode_event_id=e.event_id;
 IF a.application_id IS NULL THEN RETURN e; END IF;
 e.episode_id:=a.episode_id;e.phase:=a.phase;e.entry_origin:=a.entry_origin;e.entry_date:=a.entry_date;
 e.start_weight_kg:=a.start_weight_kg;e.start_height_cm:=a.start_height_cm;
 e.start_body_fat_percent:=a.start_body_fat_percent;e.start_training_frequency:=a.start_training_frequency;
 e.maintenance_since:=a.maintenance_since;e.deficit_level:=a.deficit_level;e.difficulty_count:=a.difficulty_count;
 e.ledger_steps:=a.ledger_steps;e.schedule:=a.schedule;e.applied_at:=a.applied_at;
 RETURN e;
END $$;
CREATE OR REPLACE FUNCTION private.mobile_clinical_daily_authority(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE a private.mobile_clinical_daily_applications%ROWTYPE;source_id uuid;
BEGIN
 SELECT event_id INTO source_id FROM private.mobile_clinical_episode_events WHERE user_id=p_user_id
  AND signup_generation=p_generation AND signup_epoch=p_epoch ORDER BY event_no DESC LIMIT 1;
 SELECT x.* INTO a FROM private.mobile_clinical_daily_heads h JOIN private.mobile_clinical_daily_applications x
  ON x.user_id=h.user_id AND x.application_id=h.application_id WHERE h.user_id=p_user_id
   AND x.signup_generation=p_generation AND x.signup_epoch=p_epoch;
 IF a.application_id IS NULL THEN RETURN 'null'::jsonb; END IF;
 RETURN jsonb_build_object('applicable',a.source_episode_event_id=source_id,
  'application',private.mobile_clinical_canonical_row(to_jsonb(a),ARRAY['applied_at'],ARRAY['application_no','difficulty_count','safety_revision']));
END $$;

-- Only target inputs enter the repeat fingerprint. Consumption/XP/photo
-- activity are still protected by the fresh context hash but do not create
-- another target application merely because the user logged a meal.
CREATE FUNCTION private.mobile_clinical_daily_fingerprint(p_user_id uuid,p_source_event uuid,p_generation uuid,
 p_epoch uuid,p_date date,p_config jsonb,p_safety jsonb) RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' AS $$
DECLARE profile jsonb;owner jsonb;day jsonb;
BEGIN
 SELECT to_jsonb(p)-'updated_at' INTO profile FROM public.user_profiles p WHERE user_id=p_user_id;
 SELECT jsonb_build_object('id',u.id,'status',u.status,'timezone',u.timezone,'locale',u.locale) INTO owner FROM public.users u WHERE id=p_user_id;
 SELECT jsonb_build_object('date',d.date,'day_closed',d.day_closed,'closed_at',d.closed_at,
  'calories_target',d.calories_target,'protein_target',d.protein_target,'current_protocol',d.current_protocol)
  INTO day FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=p_date;
 RETURN encode(extensions.digest(jsonb_build_object('version',1,'user',owner,'source_event',p_source_event,
  'signup_generation',p_generation,'signup_epoch',p_epoch,'date',p_date,'profile',profile,'day',day,
  'calculation_config',p_config,'safety',p_safety)::text,'sha256'),'hex');
END $$;

CREATE FUNCTION private.apply_mobile_clinical_daily_at(p_user_id uuid,p_operation_key uuid,p_context_hash text,
 p_calculation jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO, YMD' AS $$
DECLARE key_row private.mobile_clinical_daily_keys%ROWTYPE;head private.mobile_clinical_daily_applications%ROWTYPE;
 source private.mobile_clinical_episode_events%ROWTYPE;episode private.mobile_clinical_episode_events%ROWTYPE;
 review private.mobile_clinical_full_receipts%ROWTYPE;profile public.user_profiles%ROWTYPE;
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
 SELECT * INTO STRICT review FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND review_id=source.review_id;
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
  (review.proposal#>>'{targets,formulaAfterKcal}')::integer,calculated);
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
  pending_confirmed_target:=episode.phase='manutencao' AND episode.maintenance_since IS NULL
   AND review.principal IN('phase_maintenance','neutral_exit','gain_exit')
   AND (NOT blocked OR (review.principal='neutral_exit' AND NOT unknown_guard AND NOT no_plan AND NOT loss_guard
    AND review.result->>'safety_revision'=safety->>'safety_revision'));
  IF pending_confirmed_target THEN
   after_kcal:=(review.proposal#>>'{targets,afterKcal}')::integer;after_protein:=(review.proposal#>>'{targets,afterProtein}')::numeric;
   formula:=(review.proposal#>>'{targets,formulaAfterKcal}')::integer;episode.maintenance_since:=today;reason:='confirmed_target';
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
  'source_review_id',source.review_id,'schedule_review_id',plan_review,
  'targets',jsonb_build_object('calories_target',after_kcal,'protein_target',after_protein,'formula_target',formula,
   'effective_adjustment',after_kcal-formula),
  'episode',private.mobile_clinical_canonical_row(to_jsonb(episode),ARRAY['applied_at'],ARRAY['event_no','difficulty_count']));
 INSERT INTO private.mobile_clinical_daily_applications(user_id,application_id,signup_generation,signup_epoch,application_no,
  previous_application_id,source_episode_event_id,source_review_id,schedule_review_id,context_hash,post_fingerprint,
  date,timezone_at_application,state,frozen_schedule,episode_id,phase,entry_origin,entry_date,
  start_weight_kg,start_height_cm,start_body_fat_percent,start_training_frequency,maintenance_since,deficit_level,
  difficulty_count,ledger_steps,schedule,calories_target,protein_target,formula_target,effective_adjustment,safety_revision,
  calculation,applied_at,result,rule_version)
 VALUES(p_user_id,application_id,generation,epoch,application_no,previous_id,source.event_id,source.review_id,plan_review,
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
REVOKE ALL ON FUNCTION private.mobile_clinical_effective_episode(uuid,uuid,uuid),
 private.mobile_clinical_daily_authority(uuid,uuid,uuid),
 private.mobile_clinical_daily_fingerprint(uuid,uuid,uuid,uuid,date,jsonb,jsonb),
 private.apply_mobile_clinical_daily_at(uuid,uuid,text,jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

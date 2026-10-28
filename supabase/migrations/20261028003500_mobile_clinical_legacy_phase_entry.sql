-- Explicit first phase in a proven legacy FULL. Genuine FIRST_PHASE receipt
-- authority and its signup-only foreign keys remain unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_generation_sources') IS NULL THEN
  RAISE EXCEPTION 'legacy_phase_entry_requires_generation_sources' USING ERRCODE='42501'; END IF;
END $preflight$;

CREATE FUNCTION private.assert_mobile_clinical_legacy_phase_entry(c jsonb,f jsonb,i jsonb,p jsonb,bf numeric)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE profile jsonb:=c#>'{facts,profile}';answers jsonb:=f->'answers';after_profile jsonb:=p->'profile';
 phase text:=p#>>'{profile,current_protocol}';principal text:=p->>'principal';
 height numeric;weight numeric;years integer;bmi numeric;frequency numeric;hunger text;level text;
 cut numeric:=25;training_min numeric:=3;bf_cut numeric;gain_cut numeric;limits jsonb;cfg jsonb;
 table_value jsonb;deficit integer;above boolean;cleared boolean;factor numeric;key text;n numeric;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF c->>'review_kind' NOT IN('REGULAR','TRANSITION_FULL')
  OR c#>>'{facts,anchor,authority,kind}' IS DISTINCT FROM 'legacy_transition'
  OR profile->'current_protocol' IS DISTINCT FROM 'null'::jsonb
  OR f->'phase' IS DISTINCT FROM 'null'::jsonb
  OR f->'legacyOrigin' IS DISTINCT FROM c#>'{facts,protocol_authority,phase_origin}'
  OR f#>>'{legacyOrigin,kind}' IS DISTINCT FROM 'legacy_transition_unassigned'
  OR f#>>'{legacyOrigin,generation}' IS DISTINCT FROM c#>>'{facts,anchor,signup_generation}'
  OR f#>>'{legacyOrigin,epoch}' IS DISTINCT FROM c#>>'{facts,anchor,signup_epoch}'
  OR f#>>'{legacyOrigin,admittedAt}' IS DISTINCT FROM c#>>'{facts,anchor,authority,admitted_at}'
  OR i->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb
  OR answers->'healthCheck' IS DISTINCT FROM '{"kind":"none"}'::jsonb
  OR phase IS NULL OR phase NOT IN('recomposicao','ganho_massa','manutencao')
  OR principal IS DISTINCT FROM (CASE phase WHEN 'recomposicao' THEN 'phase_recomposition'
    WHEN 'ganho_massa' THEN 'phase_gain' ELSE 'phase_maintenance' END)
  OR bf IS NULL OR bf IS DISTINCT FROM (c#>>'{facts,protocol_authority,body_fat_candidate,mean_percent}')::numeric THEN
  RAISE EXCEPTION 'legacy_phase_entry_authority_changed' USING ERRCODE='40001'; END IF;
 height:=(profile->>'height_cm')::numeric;
 weight:=coalesce((answers->>'weightKg')::numeric,(profile->>'weight_kg')::numeric);
 hunger:=coalesce(answers->>'hunger',profile->>'hunger_level');
 frequency:=coalesce((answers->>'strengthSessions')::numeric,(profile->>'training_frequency')::numeric);
 level:=CASE WHEN answers#>'{activity,activityLevelConfirmed}'='true'::jsonb
  THEN answers#>>'{activity,activityLevel}' ELSE profile->>'activity_level' END;
 cleared:=coalesce((c#>>'{facts,safety,hold_active}')::boolean,false)
  AND answers#>'{professionalConversationConfirmed}'='true'::jsonb;
 cleared:=coalesce(cleared,false);
 years:=CASE WHEN profile->>'birth_date' IS NOT NULL AND
   (profile->>'birth_date')::date<=(c#>>'{facts,calculation_date}')::date
  THEN extract(year FROM age((c#>>'{facts,calculation_date}')::date,(profile->>'birth_date')::date))::integer END;
 bmi:=CASE WHEN height>0 THEN weight/power(height/100,2) END;
 IF years IS NULL OR years<18 OR bmi IS NULL OR bmi<18.5 OR bf<=10 OR bf>60
  OR (coalesce((c#>>'{facts,safety,hold_active}')::boolean,true) AND NOT cleared)
  OR p->'clearHold' IS DISTINCT FROM to_jsonb(cleared)
  OR profile->>'sex' IS NULL OR profile->>'sex' NOT IN('masculino','feminino')
  OR height IS NULL OR height<=0 OR weight IS NULL OR weight NOT BETWEEN 30 AND 300
  OR frequency IS NULL OR frequency NOT BETWEEN 0 AND 7 OR trunc(frequency)<>frequency
  OR hunger IS NULL OR hunger NOT IN('pouca','moderada','muita')
  OR level IS NULL OR level NOT IN('sedentario','leve','moderado','alto','atleta') THEN
  RAISE EXCEPTION 'legacy_phase_entry_safety_or_inputs_changed' USING ERRCODE='40001'; END IF;
 SELECT x->'value' INTO cfg FROM jsonb_array_elements(c#>'{facts,calculation_config}') x
  WHERE x->>'key'='calc.imc_limit_recomp';
 IF jsonb_typeof(cfg)='number' THEN cut:=(cfg#>>'{}')::numeric; END IF;
 SELECT x->'value' INTO cfg FROM jsonb_array_elements(c#>'{facts,calculation_config}') x
  WHERE x->>'key'='calc.training_min';
 IF jsonb_typeof(cfg)='number' THEN training_min:=(cfg#>>'{}')::numeric; END IF;
 SELECT x->'value'->(profile->>'sex') INTO limits FROM jsonb_array_elements(c#>'{facts,calculation_config}') x
  WHERE x->>'key'='calc.bf_limits';
 bf_cut:=CASE WHEN profile->>'sex'='masculino' THEN 20 ELSE 28 END;
 gain_cut:=CASE WHEN profile->>'sex'='masculino' THEN 19 ELSE 27 END;
 IF jsonb_typeof(limits->'recomp')='number' THEN bf_cut:=(limits->>'recomp')::numeric; END IF;
 IF jsonb_typeof(limits->'gain')='number' THEN gain_cut:=(limits->>'gain')::numeric; END IF;
 above:=bf>=bf_cut;
 IF (above AND phase<>'recomposicao') OR (phase='ganho_massa' AND
   (cut<=0 OR bmi>=cut OR bf>gain_cut OR frequency<training_min)) THEN
  RAISE EXCEPTION 'legacy_phase_entry_choice_changed' USING ERRCODE='40001'; END IF;
 SELECT x->'value' INTO table_value FROM jsonb_array_elements(c#>'{facts,calculation_config}') x
  WHERE x->>'key'='calc.deficit_by_hunger';
 IF table_value IS NOT NULL AND table_value<>'null'::jsonb AND
  table_value IS DISTINCT FROM '{"muita":400,"moderada":500,"pouca":600}'::jsonb THEN
  RAISE EXCEPTION 'legacy_phase_entry_deficit_table_unverified' USING ERRCODE='40001'; END IF;
 deficit:=CASE WHEN phase='recomposicao' THEN CASE hunger WHEN 'muita' THEN 400 WHEN 'moderada' THEN 500 ELSE 600 END END;
 IF after_profile IS DISTINCT FROM jsonb_build_object('current_protocol',phase,'deficit_level',deficit,
   'activity_level',level,'training_frequency',frequency,'hunger_level',hunger)
  OR p#>'{targets,beforeKcal}' IS DISTINCT FROM coalesce(c#>'{facts,day,calories_target}','null'::jsonb)
  OR p#>'{targets,beforeProtein}' IS DISTINCT FROM coalesce(c#>'{facts,day,protein_target}','null'::jsonb)
  OR p#>'{targets,afterKcal}' IS DISTINCT FROM p#>'{targets,formulaAfterKcal}' THEN
  RAISE EXCEPTION 'invalid_legacy_phase_entry_effects' USING ERRCODE='22023'; END IF;
 FOREACH key IN ARRAY ARRAY['afterKcal','afterProtein','formulaAfterKcal'] LOOP
  IF jsonb_typeof(p#>ARRAY['targets',key]) IS DISTINCT FROM 'number' THEN
   RAISE EXCEPTION 'invalid_legacy_phase_entry_number' USING ERRCODE='22023'; END IF;
  n:=(p#>>ARRAY['targets',key])::numeric;
  IF (key='afterProtein' AND (n NOT BETWEEN 0 AND 9999.99 OR round(n,2)<>n))
   OR (key<>'afterProtein' AND (n NOT BETWEEN 1 AND 2147483647 OR trunc(n)<>n)) THEN
   RAISE EXCEPTION 'invalid_legacy_phase_entry_number' USING ERRCODE='22023'; END IF;
 END LOOP;
 SELECT x->'value' INTO cfg FROM jsonb_array_elements(c#>'{facts,calculation_config}') x
  WHERE x->>'key'='calc.recomp_protein_g_per_kg';
 factor:=CASE WHEN cfg IN('null'::jsonb,'0'::jsonb) THEN NULL
  WHEN jsonb_typeof(cfg)='number' THEN CASE WHEN (cfg#>>'{}')::numeric>0 AND (cfg#>>'{}')::numeric<=3
   THEN (cfg#>>'{}')::numeric ELSE 1.5 END ELSE 1.5 END;
 IF phase<>'recomposicao' OR factor IS NULL THEN
  SELECT x->'value' INTO cfg FROM jsonb_array_elements(c#>'{facts,calculation_config}') x
   WHERE x->>'key'='calc.protein_factors';
  IF cfg IS DISTINCT FROM '{"muita":1.6,"moderada":1.8,"pouca":1.8,"training_low":1.7,"optimal_mid_training":1.9,"optimal_high_training":2}'::jsonb THEN
   RAISE EXCEPTION 'legacy_phase_entry_protein_table_unverified' USING ERRCODE='40001'; END IF;
 END IF;
 IF p->'episode' IS DISTINCT FROM jsonb_build_object('difficultyCount',CASE WHEN phase='recomposicao' THEN 0 END,
   'ledgerSteps',CASE WHEN phase='recomposicao' THEN 'null'::jsonb ELSE '[]'::jsonb END,'schedule',NULL,
   'maintenanceSince',CASE WHEN phase='manutencao' AND NOT coalesce((c#>>'{facts,day,day_closed}')::boolean,false)
    THEN c#>>'{facts,calculation_date}' END) THEN
  RAISE EXCEPTION 'invalid_legacy_phase_entry_episode' USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION private.assert_mobile_clinical_legacy_phase_entry(jsonb,jsonb,jsonb,jsonb,numeric)
 FROM PUBLIC,anon,authenticated,service_role;

-- BEGIN GENERATED EXISTING WRITERS
CREATE OR REPLACE FUNCTION private.confirm_mobile_clinical_preview_at(p_user_id uuid, p_preview_id uuid, p_operation_key uuid, p_form jsonb, p_intent jsonb, p_proposal jsonb, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET "TimeZone" TO 'UTC'
AS $function$
DECLARE preview private.mobile_clinical_previews%ROWTYPE; receipt private.mobile_clinical_full_receipts%ROWTYPE;
 key_row private.mobile_clinical_confirmation_keys%ROWTYPE; previous private.mobile_clinical_episode_events%ROWTYPE;
 origin private.mobile_clinical_signup_origins%ROWTYPE; profile_row public.user_profiles%ROWTYPE;
 cycle_row private.mobile_reevaluation_cycles%ROWTYPE; consent_row record;
 context jsonb; safety jsonb; candidate jsonb; profile_after jsonb; targets jsonb; episode jsonb; result jsonb; preference_result jsonb;
 input_hash text; principal text; phase text; before_phase text; zone text; day date; observed_at timestamptz;
 after_kcal integer; after_protein numeric; formula_kcal integer; before_kcal integer; before_protein numeric;
 new_weight numeric; new_frequency smallint; new_level text; deficit integer; body_fat numeric;
 new_hunger text; protein_branch_before text; protein_branch_after text;
 protein_branch_changed boolean:=false; protein_factors_row jsonb; recomp_factor_row jsonb;
 health_only boolean;legacy_health boolean;prospective_initial boolean;origin_key text;health_answer jsonb;health_items text[];
 clear_hold boolean; effective_hold boolean; no_plan boolean; loss_guard boolean; unknown_guard boolean;
 age_years integer; bmi numeric; safety_revision bigint; before_revision bigint; review_number bigint;
 current_cycle uuid; episode_id uuid; entry_origin text; entry_date date; r_date date;
 start_weight numeric; start_height numeric; start_bf numeric; start_frequency smallint;
 previous_steps integer[]; steps integer[]; count_after bigint; old_weight_marker text;
 schedule jsonb;previous_schedule jsonb;previous_r date;expected_r date;expected_kcal numeric;
 schedule_reached boolean;step_count integer;
 previous_full uuid; base_day date; cycle_revision bigint; applied_day public.daily_snapshots%ROWTYPE;
 written_day_id uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_preview_id IS NULL OR p_operation_key IS NULL OR jsonb_typeof(p_form) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object' OR jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
  OR octet_length(p_form::text)>65536 OR octet_length(p_intent::text)>8192 OR octet_length(p_proposal::text)>65536 THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_confirmation' USING ERRCODE='22023';
 END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 input_hash:=encode(extensions.digest(jsonb_build_object('preview_id',p_preview_id,
  'form',p_form,'intent',p_intent,'proposal',p_proposal)::text,'sha256'),'hex');
 SELECT * INTO key_row FROM private.mobile_clinical_confirmation_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF key_row.input_hash<>input_hash THEN RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001'; END IF;
  SELECT * INTO STRICT receipt FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND review_id=key_row.review_id;
  RETURN receipt.result;
 END IF;
 SELECT * INTO receipt FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND preview_id=p_preview_id;
 IF FOUND THEN
  IF receipt.input_hash<>input_hash THEN RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001'; END IF;
  INSERT INTO private.mobile_clinical_confirmation_keys(user_id,operation_key,review_id,input_hash,confirmed_at)
   VALUES(p_user_id,p_operation_key,receipt.review_id,input_hash,coalesce(p_observed_at,clock_timestamp()));
  RETURN receipt.result;
 END IF;
 SELECT * INTO preview FROM private.mobile_clinical_previews WHERE user_id=p_user_id AND preview_id=p_preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_preview_not_found' USING ERRCODE='P0002'; END IF;
 IF preview.form_hash<>encode(extensions.digest(p_form::text,'sha256'),'hex')
  OR preview.intent_hash<>encode(extensions.digest(p_intent::text,'sha256'),'hex')
  OR preview.proposal_hash<>encode(extensions.digest(p_proposal::text,'sha256'),'hex') THEN
  RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001';
 END IF;
 context:=private.capture_mobile_clinical_context_at(p_user_id,preview.review_kind,preview.cycle_id,p_observed_at);
 observed_at:=(context->>'observed_at')::timestamptz;day:=(context#>>'{facts,calculation_date}')::date;
 IF context->>'context_hash'<>preview.context_hash OR observed_at>=preview.valid_until
  OR preview.signup_generation::text IS DISTINCT FROM context#>>'{facts,anchor,signup_generation}'
  OR preview.signup_epoch::text IS DISTINCT FROM context#>>'{facts,anchor,signup_epoch}' THEN
  RAISE EXCEPTION 'mobile_clinical_preview_stale' USING ERRCODE='40001';
 END IF;
 SELECT * INTO STRICT profile_row FROM public.user_profiles WHERE user_id=p_user_id;
 SELECT * INTO applied_day FROM public.daily_snapshots WHERE user_id=p_user_id AND date=day;
 before_phase:=profile_row.current_protocol::text;zone:=context#>>'{facts,owner,timezone}';
 base_day:=(context#>>'{facts,anchor,clock,base_date}')::date;
 previous_full:=(context#>>'{facts,anchor,last_full_id}')::uuid;
 principal:=p_proposal->>'principal';profile_after:=p_proposal->'profile';targets:=p_proposal->'targets';episode:=p_proposal->'episode';
 IF p_form->'version' IS DISTINCT FROM '1'::jsonb OR p_form->>'kind' IS DISTINCT FROM preview.review_kind
  OR p_form->>'phase' IS DISTINCT FROM before_phase OR p_proposal->'version' IS DISTINCT FROM '1'::jsonb
  OR p_proposal-ARRAY['version','principal','profile','targets','episode','clearHold']<>'{}'::jsonb
  OR principal IS NULL OR principal NOT IN('keep','deficit_step','activity','phase_maintenance','phase_gain',
   'phase_recomposition','recomposition_transition','gain_exit','neutral_exit','maintenance_step','gain_step','schedule_reconfirm','schedule_pause')
  OR jsonb_typeof(profile_after) IS DISTINCT FROM 'object' OR jsonb_typeof(targets) IS DISTINCT FROM 'object'
  OR jsonb_typeof(episode) IS DISTINCT FROM 'object' OR jsonb_typeof(p_proposal->'clearHold') IS DISTINCT FROM 'boolean'
  OR NOT(profile_after ?& ARRAY['current_protocol','deficit_level','activity_level','training_frequency','hunger_level'])
  OR profile_after-ARRAY['current_protocol','deficit_level','activity_level','training_frequency','hunger_level']<>'{}'::jsonb
  OR NOT(targets ?& ARRAY['beforeKcal','beforeProtein','afterKcal','afterProtein','formulaAfterKcal'])
  OR targets-ARRAY['beforeKcal','beforeProtein','afterKcal','afterProtein','formulaAfterKcal']<>'{}'::jsonb
  OR NOT(episode ?& ARRAY['difficultyCount','ledgerSteps','schedule','maintenanceSince'])
  OR episode-ARRAY['difficultyCount','ledgerSteps','schedule','maintenanceSince']<>'{}'::jsonb
  OR (principal<>'keep' AND p_intent->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_proposal' USING ERRCODE='22023';
 END IF;
 phase:=profile_after->>'current_protocol';deficit:=(profile_after->>'deficit_level')::integer;
 new_frequency:=(profile_after->>'training_frequency')::smallint;new_level:=profile_after->>'activity_level';
 new_hunger:=profile_after->>'hunger_level';
 before_kcal:=(targets->>'beforeKcal')::integer;before_protein:=(targets->>'beforeProtein')::numeric;
 after_kcal:=(targets->>'afterKcal')::integer;after_protein:=(targets->>'afterProtein')::numeric;
 formula_kcal:=(targets->>'formulaAfterKcal')::integer;count_after:=(episode->>'difficultyCount')::bigint;
 r_date:=(episode->>'maintenanceSince')::date;new_weight:=(p_form#>>'{answers,weightKg}')::numeric;
 health_only:=before_phase IS NULL;
 legacy_health:=health_only AND context#>>'{facts,anchor,authority,kind}'='legacy_transition';
 origin_key:=CASE WHEN legacy_health THEN 'legacyOrigin' ELSE 'noPlanOrigin' END;
 prospective_initial:=coalesce(legacy_health AND preview.review_kind IN('REGULAR','TRANSITION_FULL')
  AND phase IS NOT NULL AND principal IN('phase_recomposition','phase_gain','phase_maintenance')
  AND p_intent->'principalConfirmed'='true'::jsonb,false);
 IF health_only THEN
  IF context#>>'{facts,protocol_authority,phase_origin,kind}' IS DISTINCT FROM
    (CASE WHEN legacy_health THEN 'legacy_transition_unassigned' ELSE 'confirmed_no_plan' END)
   OR p_form->origin_key IS DISTINCT FROM context#>'{facts,protocol_authority,phase_origin}' THEN
   RAISE EXCEPTION 'mobile_clinical_no_plan_origin_unproven' USING ERRCODE='40001';
  END IF;
  IF preview.review_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL') OR (principal<>'keep' AND NOT prospective_initial)
   OR NOT(p_form ?& ARRAY['version','phase','kind','activityPurpose','answers','preference',origin_key])
   OR p_form-ARRAY['version','phase','kind','activityPurpose','answers','preference',origin_key]<>'{}'::jsonb
   OR p_form->'phase' IS DISTINCT FROM 'null'::jsonb OR p_form->>'activityPurpose' IS DISTINCT FROM 'normal'
   OR p_form->'preference' IS DISTINCT FROM 'null'::jsonb
   OR jsonb_typeof(p_form->'answers') IS DISTINCT FROM 'object'
   OR NOT(p_form->'answers' ?& ARRAY['weightKg','strengthSessions','adherence','hunger','energy',
    'strengthProgression','fatPerception','difficultToMaintain','activity','healthCheck','professionalConversationConfirmed'])
   OR (p_form->'answers')-ARRAY['weightKg','strengthSessions','adherence','hunger','energy',
    'strengthProgression','fatPerception','difficultToMaintain','activity','healthCheck','professionalConversationConfirmed']<>'{}'::jsonb
   OR EXISTS(SELECT 1 FROM jsonb_each((p_form->'answers')-(CASE WHEN legacy_health THEN ARRAY['weightKg','strengthSessions','hunger','activity','healthCheck','professionalConversationConfirmed'] ELSE ARRAY['weightKg','healthCheck','professionalConversationConfirmed'] END)) x
    WHERE x.value<>'null'::jsonb)
   OR jsonb_typeof(p_form#>'{answers,weightKg}') NOT IN('number','null')
   OR jsonb_typeof(p_form#>'{answers,professionalConversationConfirmed}') NOT IN('boolean','null')
   OR (NOT prospective_initial AND profile_after IS DISTINCT FROM jsonb_build_object('current_protocol',NULL,'deficit_level',NULL,
    'activity_level',profile_row.activity_level,'training_frequency',profile_row.training_frequency,'hunger_level',profile_row.hunger_level))
   OR (NOT prospective_initial AND (CASE WHEN legacy_health THEN
    targets IS DISTINCT FROM jsonb_build_object('beforeKcal',applied_day.calories_target,
     'beforeProtein',applied_day.protein_target,'afterKcal',applied_day.calories_target,
     'afterProtein',applied_day.protein_target,'formulaAfterKcal',NULL)
    ELSE EXISTS(SELECT 1 FROM jsonb_each(targets) x WHERE x.value<>'null'::jsonb) END))
   OR (NOT prospective_initial AND EXISTS(SELECT 1 FROM jsonb_each(episode) x WHERE x.value<>'null'::jsonb))
   OR jsonb_typeof(p_intent->'principalConfirmed') IS DISTINCT FROM 'boolean'
   OR p_intent-ARRAY['principalConfirmed','bodyFat']<>'{}'::jsonb THEN
   RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
  END IF;
  health_answer:=p_form#>'{answers,healthCheck}';
  IF health_answer<>'null'::jsonb THEN
   IF jsonb_typeof(health_answer) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
   END IF;
   IF health_answer->>'kind'='none' THEN
    IF health_answer<>'{"kind":"none"}'::jsonb THEN
     RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
    END IF;
   ELSIF health_answer->>'kind'='risks' AND jsonb_typeof(health_answer->'items')='array'
    AND health_answer-ARRAY['kind','items']='{}'::jsonb THEN
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(health_answer->'items') x WHERE jsonb_typeof(x)<>'string') THEN
     RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
    END IF;
    SELECT array_agg(x) INTO health_items FROM jsonb_array_elements_text(health_answer->'items') x;
    IF to_jsonb(private.mobile_health_risk_set(health_items)) IS DISTINCT FROM health_answer->'items' THEN
     RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
    END IF;
   ELSE RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023'; END IF;
  END IF;
  IF context#>'{facts,protocol_authority,signup_origin}' IS DISTINCT FROM 'null'::jsonb
   OR context#>'{facts,protocol_authority,episode}' IS DISTINCT FROM 'null'::jsonb
   OR context#>'{facts,protocol_authority,daily_application}' IS DISTINCT FROM 'null'::jsonb
   OR context#>'{facts,protocol_authority,day_events}' IS DISTINCT FROM '[]'::jsonb THEN
   RAISE EXCEPTION 'mobile_clinical_no_plan_authority_inconsistent' USING ERRCODE='40001';
  END IF;
 ELSE
 IF phase IS NULL OR phase NOT IN('recomposicao','manutencao','ganho_massa')
  OR (phase<>'recomposicao' AND deficit IS NOT NULL) OR (deficit IS NOT NULL AND deficit NOT IN(400,500,600))
  OR (phase='recomposicao' AND deficit IS NULL AND NOT(
   before_phase='recomposicao' AND profile_row.deficit_level IS NULL AND principal='keep'
   AND formula_kcal IS NULL AND after_kcal IS NOT DISTINCT FROM before_kcal
   AND after_protein IS NOT DISTINCT FROM before_protein))
  OR (new_level IS NOT NULL AND new_level NOT IN('sedentario','leve','moderado','alto','atleta'))
  OR (new_hunger IS NOT NULL AND (jsonb_typeof(profile_after->'hunger_level')<>'string' OR new_hunger NOT IN('pouca','moderada','muita')))
  OR new_frequency NOT BETWEEN 0 AND 7 OR new_weight NOT BETWEEN 30 AND 300
  OR after_kcal<=0 OR before_kcal<=0 OR formula_kcal<=0 OR after_protein NOT BETWEEN 0 AND 9999.99
  OR before_protein NOT BETWEEN 0 AND 9999.99 OR count_after NOT BETWEEN 0 AND 9007199254740991
  OR (phase<>before_phase AND (principal NOT IN('phase_maintenance','phase_gain','phase_recomposition','recomposition_transition','gain_exit','neutral_exit')))
  OR (before_phase='recomposicao' AND phase='ganho_massa') OR (before_phase='ganho_massa' AND phase='recomposicao')
  OR (new_level IS DISTINCT FROM profile_row.activity_level::text AND
   (p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb
    OR p_form#>>'{answers,activity,activityLevel}' IS DISTINCT FROM new_level))
  OR (new_frequency IS DISTINCT FROM profile_row.training_frequency AND
   (p_form#>>'{answers,strengthSessions}' IS NULL OR
    (p_form#>>'{answers,strengthSessions}')::smallint IS DISTINCT FROM new_frequency))
  OR (new_hunger IS DISTINCT FROM profile_row.hunger_level::text AND
   (p_form#>>'{answers,hunger}' IS NULL OR p_form#>>'{answers,hunger}' IS DISTINCT FROM new_hunger)) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_effects' USING ERRCODE='22023';
 END IF;
 -- Compare input branches in the resulting phase. A separately confirmed
 -- phase already owns its shown protein projection; weight changes alone
 -- never turn an ordinary answer into acceptance of a different branch.
 SELECT c->'value' INTO protein_factors_row FROM jsonb_array_elements(context#>'{facts,calculation_config}') c
  WHERE c->>'key'='calc.protein_factors';
 SELECT c->'value' INTO recomp_factor_row FROM jsonb_array_elements(context#>'{facts,calculation_config}') c
  WHERE c->>'key'='calc.recomp_protein_g_per_kg';
 protein_branch_before:=private.mobile_clinical_protein_branch(phase,profile_row.hunger_level::text,profile_row.training_frequency,recomp_factor_row);
 protein_branch_after:=private.mobile_clinical_protein_branch(phase,new_hunger,new_frequency,recomp_factor_row);
 protein_branch_changed:=protein_branch_before IS DISTINCT FROM protein_branch_after;
 IF (principal IN('deficit_step','maintenance_step','gain_step')
   AND new_level IS DISTINCT FROM profile_row.activity_level::text)
  OR (principal IN('maintenance_step','gain_step') AND EXISTS(
   SELECT 1 FROM jsonb_array_elements(context#>'{facts,protocol_authority,routine_reviews_since_regular}') r
    WHERE r->'activity_level_changed'='true'::jsonb)) THEN
  RAISE EXCEPTION 'mobile_clinical_activity_priority' USING ERRCODE='40001';
 END IF;
 IF (phase=before_phase AND principal<>'deficit_step' AND deficit IS DISTINCT FROM profile_row.deficit_level)
  OR (principal='deficit_step' AND (preview.review_kind<>'REGULAR' OR before_phase<>'recomposicao' OR phase<>before_phase
   OR profile_row.deficit_level IS NULL
   OR NOT((profile_row.deficit_level=600 AND deficit=500) OR (profile_row.deficit_level=500 AND deficit=400))))
  OR (principal='activity' AND (phase<>before_phase OR (NOT protein_branch_changed
   AND p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb)))
  OR (principal='maintenance_step' AND (before_phase<>'manutencao' OR phase<>before_phase))
  OR (principal='gain_step' AND (before_phase<>'ganho_massa' OR phase<>before_phase))
  OR (principal='phase_gain' AND phase<>'ganho_massa')
  OR (principal='phase_recomposition' AND phase<>'recomposicao')
  OR (principal IN('phase_maintenance','recomposition_transition','neutral_exit') AND phase<>'manutencao')
  OR (principal='recomposition_transition' AND before_phase<>'recomposicao')
  OR (principal='gain_exit' AND (before_phase<>'ganho_massa' OR phase NOT IN('ganho_massa','manutencao')))
  OR (principal='neutral_exit' AND preview.review_kind<>'SAFETY')
  OR (principal='schedule_pause' AND (phase<>before_phase OR after_kcal IS DISTINCT FROM before_kcal)) THEN
  RAISE EXCEPTION 'mobile_clinical_principal_effect_mismatch' USING ERRCODE='40001';
 END IF;
 END IF;
 IF new_weight IS NOT NULL AND (new_weight NOT BETWEEN 30 AND 300 OR round(new_weight,2)<>new_weight) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_weight_precision' USING ERRCODE='22023';
 END IF;
 safety:=context#>'{facts,safety}';before_revision:=(safety->>'safety_revision')::bigint;
 clear_hold:=coalesce((safety->>'hold_active')::boolean,false) AND preview.review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL')
  AND p_form#>>'{answers,healthCheck,kind}'='none' AND p_form#>'{answers,professionalConversationConfirmed}'='true'::jsonb;
 clear_hold:=coalesce(clear_hold,false);
 IF (p_proposal->>'clearHold')::boolean<>clear_hold THEN
  RAISE EXCEPTION 'mobile_clinical_clear_intent_changed' USING ERRCODE='40001';
 END IF;
 IF p_form#>>'{answers,healthCheck,kind}'='risks' AND EXISTS(
  SELECT 1 FROM jsonb_array_elements_text(p_form#>'{answers,healthCheck,items}')x
  WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(safety->'items')s WHERE s->>'code'=x)) THEN
  RAISE EXCEPTION 'mobile_clinical_risk_not_declared' USING ERRCODE='40001';
 END IF;
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';body_fat:=profile_row.body_fat_percent;
 IF preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN
  IF candidate->>'availability' IS DISTINCT FROM 'available'
   OR p_intent#>'{bodyFat,confirmed}' IS DISTINCT FROM 'true'::jsonb
   OR p_intent#>>'{bodyFat,sourceHash}' IS DISTINCT FROM candidate->>'source_hash'
   OR (p_intent#>>'{bodyFat,meanHundredths}')::integer IS DISTINCT FROM (candidate->>'mean_hundredths')::integer THEN
   RAISE EXCEPTION 'mobile_clinical_three_photo_confirmation_required' USING ERRCODE='40001';
  END IF;
  body_fat:=(candidate->>'mean_percent')::numeric;
 ELSIF p_intent ? 'bodyFat' AND p_intent->'bodyFat'<>'null'::jsonb THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_photo_intent' USING ERRCODE='22023';
 END IF;
 effective_hold:=(safety->>'hold_active')::boolean AND NOT clear_hold;
 unknown_guard:=profile_row.birth_date IS NULL OR profile_row.height_cm IS NULL OR coalesce(new_weight,profile_row.weight_kg) IS NULL;
 IF profile_row.birth_date IS NOT NULL THEN
  age_years:=extract(year FROM day)::integer-extract(year FROM profile_row.birth_date)::integer
   -CASE WHEN to_char(day,'MMDD')<to_char(profile_row.birth_date,'MMDD') THEN 1 ELSE 0 END;
 END IF;
 bmi:=coalesce(new_weight,profile_row.weight_kg)/nullif(power(profile_row.height_cm/100,2),0);
 no_plan:=coalesce(age_years<18,false) OR (effective_hold AND (safety->>'declared_no_plan')::boolean);
 loss_guard:=coalesce(age_years>=18 AND bmi<18.5,false) OR coalesce(body_fat<=10,false);
 IF (unknown_guard OR no_plan OR loss_guard OR effective_hold) THEN
  IF new_hunger IS DISTINCT FROM profile_row.hunger_level::text
   OR new_frequency IS DISTINCT FROM profile_row.training_frequency THEN
   RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
  END IF;
  IF principal NOT IN('keep','schedule_pause') AND NOT(principal='neutral_exit' AND effective_hold AND NOT unknown_guard AND NOT no_plan AND NOT loss_guard) THEN
   RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
  END IF;
  IF principal<>'neutral_exit' AND (phase IS DISTINCT FROM before_phase OR deficit IS DISTINCT FROM profile_row.deficit_level
   OR new_level IS DISTINCT FROM profile_row.activity_level::text OR new_frequency IS DISTINCT FROM profile_row.training_frequency
   OR (after_kcal IS NOT NULL AND after_kcal IS DISTINCT FROM before_kcal)
   OR (after_protein IS NOT NULL AND after_protein IS DISTINCT FROM before_protein)) THEN
   RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
  END IF;
  IF episode#>>'{schedule,state}'='running' THEN RAISE EXCEPTION 'mobile_clinical_schedule_suspended' USING ERRCODE='40001'; END IF;
 END IF;
 IF prospective_initial THEN
  PERFORM private.assert_mobile_clinical_legacy_phase_entry(context,p_form,p_intent,p_proposal,body_fat);
  episode_id:=gen_random_uuid();entry_origin:='confirmed_phase_change';entry_date:=day;
  start_weight:=coalesce(new_weight,profile_row.weight_kg);start_height:=profile_row.height_cm;
  start_bf:=body_fat;start_frequency:=new_frequency;schedule:=NULL;
  steps:=CASE WHEN phase='recomposicao' THEN NULL ELSE ARRAY[]::integer[] END;
 END IF;
 IF NOT health_only THEN
 IF protein_branch_changed THEN
  IF protein_factors_row IS DISTINCT FROM '{"muita":1.6,"moderada":1.8,"pouca":1.8,"training_low":1.7,"optimal_mid_training":1.9,"optimal_high_training":2}'::jsonb THEN
   RAISE EXCEPTION 'mobile_clinical_protein_table_unverified' USING ERRCODE='40001';
  END IF;
  IF p_intent->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb OR principal NOT IN(
   'activity','phase_maintenance','phase_gain','phase_recomposition','recomposition_transition','gain_exit','schedule_reconfirm') THEN
   RAISE EXCEPTION 'mobile_clinical_protein_confirmation_required' USING ERRCODE='40001';
  END IF;
 END IF;
 IF new_level IS DISTINCT FROM profile_row.activity_level::text AND
  (p_intent->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb OR principal NOT IN(
   'activity','phase_maintenance','phase_gain','phase_recomposition','recomposition_transition','gain_exit','neutral_exit','schedule_reconfirm')) THEN
  RAISE EXCEPTION 'mobile_clinical_activity_confirmation_required' USING ERRCODE='40001';
 END IF;
 IF preview.review_kind='SAFETY' AND principal<>'neutral_exit' THEN
  RAISE EXCEPTION 'mobile_clinical_safety_change_required' USING ERRCODE='22023';
 END IF;
 IF principal='neutral_exit' AND (phase<>'manutencao' OR NOT effective_hold OR no_plan OR loss_guard OR unknown_guard
  OR p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb) THEN
  RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
 END IF;
 IF preview.review_kind='ROUTINE_REVIEW' AND (principal NOT IN('keep','activity') OR phase<>before_phase
  OR deficit IS DISTINCT FROM profile_row.deficit_level OR clear_hold OR new_weight IS NOT NULL) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_routine_effects' USING ERRCODE='22023';
 END IF;
 SELECT * INTO previous FROM private.mobile_clinical_effective_episode(p_user_id,preview.signup_generation,preview.signup_epoch);
 SELECT * INTO origin FROM private.mobile_clinical_signup_origins WHERE user_id=p_user_id
  AND signup_generation=preview.signup_generation AND signup_epoch=preview.signup_epoch;
 schedule:=nullif(episode->'schedule','null'::jsonb);previous_schedule:=previous.schedule;
 previous_r:=CASE WHEN previous.event_id IS NOT NULL THEN previous.maintenance_since
  WHEN origin.phase=before_phase THEN origin.maintenance_since END;
 expected_r:=CASE WHEN phase<>before_phase THEN CASE WHEN phase='manutencao' THEN day END ELSE previous_r END;
 IF schedule IS NOT NULL AND NOT private.mobile_clinical_schedule_valid(schedule) THEN
  RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
 END IF;
 IF schedule IS NOT NULL AND schedule->>'kind'='gain_exit'
  AND formula_kcal IS DISTINCT FROM (schedule->>'maintenanceTargetKcal')::integer THEN
  RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
 END IF;
 IF principal IN('recomposition_transition','gain_exit','schedule_reconfirm') THEN
  IF schedule IS NULL OR schedule->>'state'<>'running' OR (schedule->>'startDate')::date<>day
   OR before_kcal IS NULL OR (schedule->>'startTargetKcal')::integer IS DISTINCT FROM before_kcal
   OR p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb
   OR (principal='recomposition_transition' AND schedule->>'kind'<>'recomp_to_maintenance')
   OR (principal='gain_exit' AND schedule->>'kind'<>'gain_exit')
   OR (principal='schedule_reconfirm' AND (previous_schedule IS NULL OR schedule->>'kind'<>previous_schedule->>'kind'))
   OR (schedule->>'kind'='recomp_to_maintenance' AND phase<>'manutencao')
   OR (schedule->>'kind'='gain_exit' AND before_phase<>'ganho_massa') THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_kcal:=CASE schedule->>'kind' WHEN 'gain_exit' THEN greatest(
   (schedule->>'maintenanceTargetKcal')::numeric,(schedule->>'startTargetKcal')::numeric-100)
   ELSE least((schedule->>'maintenanceTargetKcal')::numeric,(schedule->>'startTargetKcal')::numeric+100,formula_kcal) END;
  schedule_reached:=expected_kcal=CASE schedule->>'kind' WHEN 'gain_exit'
   THEN (schedule->>'maintenanceTargetKcal')::numeric ELSE formula_kcal END;
  IF after_kcal IS DISTINCT FROM expected_kcal OR (schedule->>'kind'='gain_exit'
   AND phase IS DISTINCT FROM (CASE WHEN schedule_reached THEN 'manutencao' ELSE 'ganho_massa' END)) THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_r:=CASE WHEN schedule_reached THEN day END;
 ELSIF principal='schedule_pause' THEN
  IF previous_schedule IS NULL OR schedule IS DISTINCT FROM jsonb_set(previous_schedule,'{state}','"suspended"')
   OR (schedule->>'kind'='gain_exit' AND NOT(unknown_guard OR no_plan OR loss_guard OR effective_hold)) THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_r:=previous_r;
 ELSE
  IF (phase=before_phase AND schedule IS DISTINCT FROM previous_schedule
    AND NOT(principal='neutral_exit' AND schedule IS NULL))
   OR (phase<>before_phase AND schedule IS NOT NULL AND schedule IS DISTINCT FROM previous_schedule)
   OR (principal IN('maintenance_step','gain_step','deficit_step') AND previous_schedule IS NOT NULL AND previous_r IS NULL) THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  -- A previously approved running plan can reach maintenance in this atomic
  -- application. Its frozen dates never establish R before that application.
  IF schedule IS NOT NULL AND schedule->>'state'='running' AND previous_r IS NULL
   AND NOT(unknown_guard OR no_plan OR loss_guard OR effective_hold) THEN
   step_count:=((day-(schedule->>'startDate')::date)/7)+1;
   IF day<(schedule->>'startDate')::date THEN
    RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
   END IF;
   expected_kcal:=CASE schedule->>'kind' WHEN 'gain_exit' THEN greatest(
    (schedule->>'maintenanceTargetKcal')::numeric,(schedule->>'startTargetKcal')::numeric-step_count::numeric*100)
    ELSE least((schedule->>'maintenanceTargetKcal')::numeric,
     (schedule->>'startTargetKcal')::numeric+step_count::numeric*100,formula_kcal) END;
   schedule_reached:=expected_kcal=CASE schedule->>'kind' WHEN 'gain_exit'
    THEN (schedule->>'maintenanceTargetKcal')::numeric ELSE formula_kcal END;
   IF after_kcal IS DISTINCT FROM expected_kcal OR phase IS DISTINCT FROM
    (CASE WHEN schedule->>'kind'='recomp_to_maintenance' OR schedule_reached THEN 'manutencao' ELSE 'ganho_massa' END) THEN
    RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
   END IF;
   expected_r:=CASE WHEN schedule_reached THEN day END;
  END IF;
 END IF;
 IF principal='neutral_exit' THEN
  IF after_kcal IS DISTINCT FROM formula_kcal THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_r:=day;
 END IF;
 IF coalesce(applied_day.day_closed,false) AND (phase<>before_phase OR previous_r IS NULL) THEN
  expected_r:=NULL;
 END IF;
 IF r_date IS DISTINCT FROM expected_r THEN
  RAISE EXCEPTION 'mobile_clinical_R_unproven' USING ERRCODE='40001';
 END IF;
 IF previous.event_id IS NOT NULL AND previous.phase<>before_phase THEN
  RAISE EXCEPTION 'mobile_clinical_episode_drift' USING ERRCODE='40001';
 END IF;
 IF phase<>before_phase THEN
  episode_id:=gen_random_uuid();entry_origin:='confirmed_phase_change';entry_date:=day;
  start_weight:=coalesce(new_weight,profile_row.weight_kg);start_height:=profile_row.height_cm;start_bf:=body_fat;start_frequency:=new_frequency;
  previous_steps:='{}';
 ELSIF previous.event_id IS NOT NULL THEN
  episode_id:=previous.episode_id;entry_origin:=previous.entry_origin;entry_date:=previous.entry_date;
  start_weight:=previous.start_weight_kg;start_height:=previous.start_height_cm;start_bf:=previous.start_body_fat_percent;
  start_frequency:=previous.start_training_frequency;previous_steps:=previous.ledger_steps;
 ELSIF origin.episode_id IS NOT NULL AND origin.phase=before_phase THEN
  episode_id:=origin.episode_id;entry_origin:='signup';entry_date:=origin.start_date;
  start_weight:=origin.start_weight_kg;start_height:=origin.start_height_cm;start_bf:=origin.start_body_fat_percent;
  start_frequency:=origin.start_training_frequency;previous_steps:='{}';
 ELSE
  episode_id:=gen_random_uuid();entry_origin:='legacy_unknown';previous_steps:=NULL;
 END IF;
 IF jsonb_typeof(episode->'ledgerSteps')='array' THEN
  SELECT coalesce(array_agg(value::integer),'{}') INTO steps FROM jsonb_array_elements_text(episode->'ledgerSteps');
 ELSIF episode->'ledgerSteps'='null'::jsonb THEN steps:=NULL;
 ELSE RAISE EXCEPTION 'invalid_mobile_clinical_ledger' USING ERRCODE='22023'; END IF;
 IF NOT private.mobile_clinical_ledger_valid(steps) THEN RAISE EXCEPTION 'invalid_mobile_clinical_ledger' USING ERRCODE='22023'; END IF;
 IF principal IN('maintenance_step','gain_step') THEN
  IF preview.review_kind<>'REGULAR' OR phase<>before_phase OR previous_steps IS NULL
   OR cardinality(steps) IS DISTINCT FROM cardinality(previous_steps)+1
   OR steps[1:cardinality(previous_steps)] IS DISTINCT FROM previous_steps THEN
   RAISE EXCEPTION 'mobile_clinical_episode_ledger_changed' USING ERRCODE='40001';
  END IF;
 ELSIF steps IS DISTINCT FROM previous_steps THEN RAISE EXCEPTION 'mobile_clinical_episode_ledger_changed' USING ERRCODE='40001'; END IF;
 IF phase=before_phase AND preview.review_kind<>'REGULAR' AND count_after IS DISTINCT FROM
  (CASE WHEN previous.event_id IS NOT NULL THEN previous.difficulty_count WHEN origin.phase=before_phase THEN 0 END) THEN
  RAISE EXCEPTION 'mobile_clinical_early_counter_changed' USING ERRCODE='40001';
 END IF;
 END IF;
 IF (NOT health_only OR legacy_health) AND (before_kcal IS DISTINCT FROM applied_day.calories_target
  OR before_protein IS DISTINCT FROM applied_day.protein_target) THEN
  RAISE EXCEPTION 'mobile_clinical_day_target_changed' USING ERRCODE='40001';
 END IF;
 SELECT coalesce(max(review_no),0)+1 INTO review_number FROM private.mobile_clinical_full_receipts
  WHERE user_id=p_user_id AND signup_generation=preview.signup_generation;
 IF preview.review_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL') AND coalesce(p_form->'preference','null'::jsonb)<>'null'::jsonb THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_preference' USING ERRCODE='22023';
 END IF;
 preference_result:=private.mobile_clinical_preference_decision(p_user_id,preview.signup_generation,preview.signup_epoch,p_form->'preference');
 INSERT INTO private.mobile_clinical_write_permits VALUES(p_user_id,pg_current_xact_id(),p_preview_id);
 old_weight_marker:=current_setting('bodyflow.weight_write',true);
 PERFORM set_config('bodyflow.weight_write','recorded',true);
 UPDATE public.user_profiles SET weight_kg=coalesce(new_weight,weight_kg),
  weight_measured_at=CASE WHEN new_weight IS NOT NULL THEN greatest(observed_at,coalesce(weight_measured_at+interval '1 microsecond',observed_at)) ELSE weight_measured_at END,
  weight_instant_source=CASE WHEN new_weight IS NOT NULL THEN 'recorded' ELSE weight_instant_source END,
  current_protocol=phase::public.protocol_enum,deficit_level=deficit,activity_level=new_level::public.activity_enum,
  training_frequency=new_frequency,hunger_level=new_hunger::public.hunger_enum,
  updated_at=observed_at WHERE user_id=p_user_id;
 PERFORM set_config('bodyflow.weight_write',coalesce(old_weight_marker,''),true);
 IF new_weight IS NOT NULL THEN
  INSERT INTO private.mobile_weight_measurements(user_id,weight_kg,measured_at,instant_source,received_at,observed_timezone,authority_epoch)
   VALUES(p_user_id,new_weight,observed_at,'recorded',observed_at,zone,preview.signup_epoch);
 END IF;
 IF preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN
  UPDATE public.user_profiles SET body_fat_percent=body_fat,body_fat_measured_at=observed_at,updated_at=observed_at WHERE user_id=p_user_id;
 END IF;
 current_cycle:=preview.cycle_id;
 IF preview.review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL','SAFETY') THEN
  IF preview.review_kind='SAFETY' THEN
   current_cycle:=(context#>>'{facts,cycle,cycle_id}')::uuid;
  END IF;
  IF current_cycle IS NOT NULL THEN
   FOR consent_row IN SELECT acceptance_id FROM private.mobile_reevaluation_photo_consents
    WHERE user_id=p_user_id AND cycle_id=current_cycle ORDER BY acceptance_id LOOP
    PERFORM private.seal_mobile_reevaluation_photo_disposition_at(p_user_id,current_cycle,consent_row.acceptance_id,
     CASE WHEN preview.review_kind='SAFETY' THEN 'cycle_changed' ELSE 'completed' END,observed_at);
   END LOOP;
  END IF;
  IF preview.review_kind='SAFETY' THEN
   UPDATE private.mobile_reevaluation_cycles SET status='invalidated',invalidated_at=observed_at,revision=revision+1
    WHERE user_id=p_user_id AND status IN('open','collecting','review_ready');
   INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,kind,base_date,due_date,
    timezone_at_open,status,opened_at,completed_at)
    VALUES(p_user_id,preview.signup_generation,preview.signup_epoch,'SAFETY',base_day,base_day+14,
     context#>>'{facts,anchor,clock,timezone}','completed',observed_at,observed_at) RETURNING cycle_id INTO current_cycle;
  ELSE
   UPDATE private.mobile_reevaluation_cycles SET status='completed',completed_at=observed_at,revision=revision+1
    WHERE user_id=p_user_id AND cycle_id=current_cycle AND status IN('open','collecting','review_ready');
   IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_cycle_changed' USING ERRCODE='40001'; END IF;
  END IF;
  SELECT revision INTO STRICT cycle_revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=current_cycle;
 END IF;
 safety_revision:=before_revision+CASE WHEN clear_hold THEN 1 ELSE 0 END;
 IF clear_hold THEN
  INSERT INTO private.mobile_clinical_health_clear_receipts VALUES(p_user_id,p_preview_id,before_revision,safety_revision,true,observed_at);
  UPDATE private.mobile_health_hold_states s SET safety_revision=s.safety_revision+1,hold_active=false,
   items='{}',last_declared_at=observed_at WHERE s.user_id=p_user_id AND s.safety_revision=before_revision;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_safety_revision_changed' USING ERRCODE='40001'; END IF;
 END IF;
 IF (NOT health_only OR prospective_initial) AND after_kcal IS NOT NULL AND NOT coalesce(applied_day.day_closed,false) THEN
  INSERT INTO public.daily_snapshots AS actual(user_id,date,calories_target,protein_target,current_protocol,updated_at)
  VALUES(p_user_id,day,after_kcal,after_protein,phase::public.protocol_enum,observed_at)
  ON CONFLICT(user_id,date) DO UPDATE SET calories_target=excluded.calories_target,protein_target=excluded.protein_target,
   current_protocol=excluded.current_protocol,updated_at=excluded.updated_at WHERE NOT actual.day_closed
  RETURNING id INTO written_day_id;
  IF written_day_id IS NULL THEN
   RAISE EXCEPTION 'mobile_clinical_day_target_changed' USING ERRCODE='40001';
  END IF;
 END IF;
 IF written_day_id IS NOT NULL THEN
  INSERT INTO private.mobile_clinical_day_events(user_id,date,review_id,phase,deficit_level,calories_target,protein_target,
   formula_target,effective_adjustment,schedule,applied_at,rule_version)
  VALUES(p_user_id,day,p_preview_id,phase,deficit,after_kcal,after_protein,formula_kcal,
   after_kcal-formula_kcal,schedule,observed_at,'clinical-v1');
 END IF;
 UPDATE public.user_progress SET current_weight=coalesce(new_weight,current_weight),
  current_bf_percent=CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN body_fat ELSE current_bf_percent END,
  next_reevaluation=CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN (day+14)::timestamp AT TIME ZONE zone ELSE next_reevaluation END,
  updated_at=observed_at WHERE user_id=p_user_id;
 IF NOT health_only OR prospective_initial THEN
 INSERT INTO private.mobile_clinical_episode_events(user_id,signup_generation,signup_epoch,review_id,event_no,previous_event_id,
  episode_id,phase,entry_origin,entry_date,start_weight_kg,start_height_cm,start_body_fat_percent,start_training_frequency,
  maintenance_since,deficit_level,difficulty_count,ledger_steps,schedule,applied_at,rule_version)
 VALUES(p_user_id,preview.signup_generation,preview.signup_epoch,p_preview_id,coalesce(previous.event_no,0)+1,previous.event_id,
  episode_id,phase,entry_origin,entry_date,start_weight,start_height,start_bf,start_frequency,r_date,deficit,count_after,steps,
  nullif(episode->'schedule','null'::jsonb),observed_at,'clinical-v1');
 END IF;
 result:=jsonb_build_object('version',1,'user_id',p_user_id,'review_id',p_preview_id,'kind',preview.review_kind,
  'status','confirmed','principal',principal,'completed_at',to_char(observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'cycle_id',current_cycle,'cycle_revision',cycle_revision::text,'safety_revision',safety_revision::text,
  'next_due_date',CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN day+14 ELSE base_day+14 END,
  'targets',targets,'body_fat_percent',CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN body_fat ELSE NULL END,
  'preference',preference_result);
 INSERT INTO private.mobile_clinical_full_receipts(user_id,review_id,preview_id,signup_generation,signup_epoch,review_no,
  kind,cycle_id,previous_full_id,base_before,base_after,timezone_at_completion,calculation_date,completed_at,final_cycle_revision,
  principal,activity_level_changed,context_hash,input_hash,form,intent,proposal,result,body_fat_mean,body_fat_source_hash,rule_version)
 VALUES(p_user_id,p_preview_id,p_preview_id,preview.signup_generation,preview.signup_epoch,review_number,preview.review_kind,
  current_cycle,previous_full,base_day,CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN day END,zone,day,observed_at,cycle_revision,
  principal,new_level IS DISTINCT FROM profile_row.activity_level::text,preview.context_hash,input_hash,p_form,p_intent,p_proposal,result,
  CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN body_fat END,CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN candidate->>'source_hash' END,'clinical-v1');
 IF preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN
  INSERT INTO private.mobile_clinical_body_fat_receipts VALUES(p_user_id,p_preview_id,preview.signup_generation,preview.signup_epoch,
   current_cycle,(candidate->>'acceptance_id')::uuid,body_fat,candidate->>'source_hash',candidate->'sources',observed_at);
  INSERT INTO private.mobile_clinical_body_fat_heads VALUES(p_user_id,p_preview_id)
   ON CONFLICT(user_id) DO UPDATE SET review_id=excluded.review_id;
 END IF;
 PERFORM private.apply_mobile_clinical_preference(p_user_id,p_preview_id);
 INSERT INTO private.mobile_clinical_confirmation_keys VALUES(p_user_id,p_operation_key,p_preview_id,input_hash,observed_at);
 DELETE FROM private.mobile_clinical_write_permits WHERE user_id=p_user_id AND transaction_id=pg_current_xact_id();
 PERFORM private.mobile_health_state_wire(p_user_id);
 PERFORM private.mobile_reevaluation_context_at(p_user_id,observed_at);
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION private.mobile_clinical_full_command_valid(p_kind text, p_command jsonb, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE choice jsonb;kind text;principal text;
BEGIN
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object'
  OR NOT(p_command ?& ARRAY['form','choice','measureConfirmed','bodyFat'])
  OR p_command-ARRAY['form','choice','measureConfirmed','bodyFat']<>'{}'::jsonb
  OR octet_length(p_command::text)>81920
  OR jsonb_typeof(p_form) IS DISTINCT FROM 'object'
  OR p_command->'form' IS DISTINCT FROM p_form
  OR p_form->'version' IS DISTINCT FROM '1'::jsonb
  OR p_form->>'kind' IS DISTINCT FROM p_kind
  OR NOT(p_form ?& ARRAY['version','phase','kind','activityPurpose','answers','preference'])
  OR p_form-ARRAY['version','phase','kind','activityPurpose','answers','preference','noPlanOrigin','legacyOrigin']<>'{}'::jsonb
  OR jsonb_typeof(p_form->'answers') IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_command->'measureConfirmed') IS DISTINCT FROM 'boolean'
  OR p_command->'bodyFat' IS DISTINCT FROM coalesce(p_intent->'bodyFat','null'::jsonb)
  OR jsonb_typeof(p_command->'bodyFat') NOT IN('object','null') THEN RETURN false; END IF;
 choice:=p_command->'choice';kind:=choice->>'kind';principal:=p_proposal->>'principal';
 IF jsonb_typeof(choice) IS DISTINCT FROM 'object' OR jsonb_typeof(choice->'kind') IS DISTINCT FROM 'string'
  OR principal IS NULL THEN RETURN false; END IF;
 IF kind='phase' THEN
  RETURN coalesce(choice-ARRAY['kind','phase']='{}'::jsonb AND jsonb_typeof(choice->'phase')='string'
   AND CASE choice->>'phase'
    WHEN 'manutencao' THEN principal IN('recomposition_transition','gain_exit') OR
     (principal='phase_maintenance' AND p_kind IN('REGULAR','TRANSITION_FULL') AND p_form->'phase'='null'::jsonb
      AND p_form#>>'{legacyOrigin,kind}'='legacy_transition_unassigned')
    WHEN 'ganho_massa' THEN principal='phase_gain'
    WHEN 'recomposicao' THEN principal='phase_recomposition' ELSE false END,false);
 ELSIF kind='schedule' THEN
  RETURN coalesce(choice-ARRAY['kind','action']='{}'::jsonb AND jsonb_typeof(choice->'action')='string'
   AND CASE choice->>'action' WHEN 'pause' THEN principal='schedule_pause'
    WHEN 'reconfirm' THEN principal='schedule_reconfirm' ELSE false END,false);
 END IF;
 IF choice-ARRAY['kind']<>'{}'::jsonb THEN RETURN false; END IF;
 RETURN CASE kind WHEN 'keep' THEN principal IN('keep','schedule_pause')
  WHEN 'activity' THEN principal='activity'
  WHEN 'phase_calorie_step' THEN principal IN('deficit_step','maintenance_step','gain_step')
  WHEN 'neutral_exit' THEN principal='neutral_exit' ELSE false END;
END $function$;
COMMIT;

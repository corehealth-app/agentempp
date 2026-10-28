\ir mobile_clinical_no_plan_fixture.sql
CREATE FUNCTION m3b_cycle_test.first_phase_request(n integer,phase text DEFAULT 'recomposicao',closed boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE signup jsonb:=m3b_cycle_test.no_plan_signup(n);a uuid:=(signup->>'user')::uuid;cycle uuid;q jsonb;c jsonb;p jsonb;prepared jsonb;
BEGIN
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);PERFORM m3b_cycle_test.no_plan_confirm(a,q);
 IF closed THEN INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,water_consumed_ml,day_closed,closed_at)
  VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1900,120,333,true,clock_timestamp());END IF;
 c:=public.get_mobile_clinical_first_phase_context(a);
 p:=jsonb_build_object('version',1,'phase',phase,'deficitLevel',CASE WHEN phase='recomposicao' THEN 500 END,
  'effectiveDate',c#>'{facts,first_phase,effective_date}',
  'targets',jsonb_build_object('beforeKcal',CASE WHEN closed THEN 1900 END,'beforeProtein',CASE WHEN closed THEN 120 END,
   'afterKcal',CASE WHEN phase='recomposicao' THEN 1413 ELSE 2471 END,
   'afterProtein',CASE WHEN phase='recomposicao' THEN 121.5 ELSE 145.8 END,
   'formulaAfterKcal',CASE WHEN phase='recomposicao' THEN 1413 ELSE 2471 END),
  'formulaBodyFat',jsonb_build_object('origin','report','percent',NULL),
  'episode',jsonb_build_object('difficultyCount',CASE WHEN phase='recomposicao' THEN 0 END,
   'ledgerSteps',CASE WHEN phase='recomposicao' THEN 'null'::jsonb ELSE '[]'::jsonb END,'schedule',NULL,
   'maintenanceSince',CASE WHEN phase='manutencao' AND NOT closed THEN c#>>'{facts,calculation_date}' END));
 prepared:=public.prepare_mobile_clinical_first_phase(a,gen_random_uuid(),c->>'context_hash',jsonb_build_object('phase',phase),p);
 RETURN jsonb_build_object('user',a,'context',c,'selection',jsonb_build_object('phase',phase),'proposal',p,'prepared',prepared);
END $$;
CREATE FUNCTION m3b_cycle_test.first_phase_confirm(q jsonb,k uuid DEFAULT gen_random_uuid()) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT public.confirm_mobile_clinical_first_phase((q->>'user')::uuid,(q#>>'{prepared,preview_id}')::uuid,k,q->'selection',q->'proposal')
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;

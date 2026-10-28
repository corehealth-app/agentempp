-- Exact historical close evidence. No route/default activation or inferred backfill.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.apply_mobile_clinical_day_close_at(uuid,uuid,date,date,text,text,jsonb,timestamptz)') IS NULL
  OR to_regclass('private.mobile_flow_plan_day_revisions') IS NULL THEN
  RAISE EXCEPTION 'clinical_period_requires_whole_close_authority' USING ERRCODE='42501';END IF;
END $$;
CREATE TABLE private.mobile_clinical_closed_day_evidence(
 snapshot_id uuid PRIMARY KEY REFERENCES public.daily_snapshots(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 signup_epoch uuid,
 signup_generation uuid,
 context_hash text NOT NULL CHECK(context_hash ~ '^[a-f0-9]{64}$'),
 request_hash text NOT NULL CHECK(request_hash ~ '^[a-f0-9]{64}$'),
 effect_hash text NOT NULL CHECK(effect_hash ~ '^[a-f0-9]{64}$'),
 snapshot_binding jsonb NOT NULL CHECK(jsonb_typeof(snapshot_binding)='object'),
 recorded_at timestamptz NOT NULL,
 UNIQUE(user_id,operation_key)
);
ALTER TABLE private.mobile_clinical_closed_day_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_closed_day_evidence FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.mobile_clinical_closed_day_evidence_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE id=OLD.snapshot_id)
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'mobile_clinical_closed_day_evidence_immutable' USING ERRCODE='55000';
END $$;
CREATE TRIGGER mobile_clinical_closed_day_evidence_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_closed_day_evidence FOR EACH ROW
 EXECUTE FUNCTION private.mobile_clinical_closed_day_evidence_immutable();

CREATE FUNCTION private.mobile_clinical_closed_day_binding(d public.daily_snapshots) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT jsonb_build_object('id',d.id,'user_id',d.user_id,'date',d.date,
  'calories_consumed',d.calories_consumed,'calories_target',d.calories_target,
  'protein_g',d.protein_g,'protein_target',d.protein_target,'carbs_g',d.carbs_g,'fat_g',d.fat_g,
  'exercise_calories',d.exercise_calories,'training_done',d.training_done,'xp_earned',d.xp_earned,
  'current_protocol',d.current_protocol,'day_closed',d.day_closed,'day_status',d.day_status,
  'closed_at',d.closed_at,'target_revision',coalesce((SELECT revision::text
   FROM private.mobile_flow_plan_day_revisions WHERE snapshot_id=d.id AND user_id=d.user_id),'0'))
$$;

CREATE OR REPLACE FUNCTION private.apply_mobile_clinical_day_close_at(p_user_id uuid,p_operation_key uuid,p_from date,p_close_date date,
 p_expected_timezone text,p_context_hash text,p_effect jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE key_row private.mobile_clinical_day_close_keys%ROWTYPE;c jsonb;facts jsonb;request jsonb;rh text;eh text;
 result jsonb;envelope jsonb;f jsonb;g jsonb;before_progress jsonb;profile jsonb;written public.daily_snapshots%ROWTYPE;
 expected_progress jsonb;delegate jsonb;observed timestamptz;dstatus text;new_badges jsonb;block_enabled boolean;
 calories integer;target integer;protein numeric;protein_goal numeric;carbs numeric;fat numeric;exercise integer;xp integer;
 xp_total integer;lvl integer;streak integer;longest integer;blocks integer;deficit integer;credit numeric;balance integer;
 badges text[];snapshot_id uuid;k text;item jsonb;gap jsonb;events jsonb;event jsonb;props jsonb;allowed text[];
 old_xp integer;old_blocks integer;old_deficit integer;old_streak integer;last_active date;gap_days integer;
 historical_phase text;historical_deficit integer;credit_status text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_operation_key IS NULL OR p_from IS NULL OR p_expected_timezone IS NULL OR p_context_hash IS NULL
  OR p_context_hash!~'^[0-9a-f]{64}$' OR jsonb_typeof(p_effect) IS DISTINCT FROM 'object'
  OR p_effect->'version' IS DISTINCT FROM '1'::jsonb OR octet_length(p_effect::text)>65536
  OR p_effect->>'kind' IS DISTINCT FROM (CASE WHEN p_close_date IS NULL THEN 'reset' ELSE 'close' END) THEN
  RAISE EXCEPTION 'invalid_clinical_day_close_effect' USING ERRCODE='22023'; END IF;
 request:=jsonb_build_object('kind',CASE WHEN p_close_date IS NULL THEN 'reset' ELSE 'close' END,'from',p_from,'date',p_close_date,'timezone',p_expected_timezone);
 rh:=encode(extensions.digest(request::text,'sha256'),'hex');
 eh:=encode(extensions.digest(jsonb_build_object('context_hash',p_context_hash,'effect',p_effect)::text,'sha256'),'hex');
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO key_row FROM private.mobile_clinical_day_close_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF key_row.request_hash<>rh OR key_row.effect_hash<>eh THEN RAISE EXCEPTION 'clinical_day_close_key_conflict' USING ERRCODE='40001'; END IF;
  RETURN key_row.result;
 END IF;
 c:=private.capture_mobile_clinical_day_close_at(p_user_id,p_from,p_close_date,p_expected_timezone,p_observed_at);
 facts:=c->'facts';observed:=(c->>'observed_at')::timestamptz;
 IF c->>'context_hash'<>p_context_hash OR facts->>'disposition'<>'ready' THEN
  RAISE EXCEPTION 'clinical_day_close_context_changed' USING ERRCODE='40001'; END IF;
 before_progress:=facts->'progress';profile:=facts->'profile';
 historical_phase:=facts#>>'{snapshot,current_protocol}';
 historical_deficit:=(facts#>>'{target_authority,applied_target,deficit_level}')::integer;
 old_xp:=coalesce((before_progress->>'xp_total')::integer,0);old_blocks:=coalesce((before_progress->>'blocks_completed')::integer,0);
 old_deficit:=coalesce((before_progress->>'deficit_block')::integer,0);
 IF p_close_date IS NULL THEN
  IF p_effect-ARRAY['version','kind']<>'{}'::jsonb THEN RAISE EXCEPTION 'invalid_clinical_reset_effect' USING ERRCODE='22023'; END IF;
  old_streak:=(before_progress->>'current_streak')::integer;last_active:=(before_progress->>'last_active_date')::date;
  gap_days:=(facts#>>'{calendar,latest_closable_date}')::date-last_active;
  IF old_streak IS NULL OR old_streak<=0 OR gap_days<2 OR jsonb_array_length(facts->'earlier_activity')<>0 THEN
   RAISE EXCEPTION 'clinical_reset_changed' USING ERRCODE='40001'; END IF;
  UPDATE public.user_progress SET current_streak=0,updated_at=observed WHERE user_id=p_user_id;
  INSERT INTO public.product_events(user_id,event,properties) VALUES(p_user_id,'streak.reset_inactive',
   jsonb_build_object('previous_streak',old_streak,'last_active_date',last_active,'gap_days',gap_days,
    'yesterday',facts#>'{calendar,latest_closable_date}'));
  result:=jsonb_build_object('kind','applied','reset',jsonb_build_object('applied',true,'previousStreak',old_streak,
   'lastActiveDate',last_active,'gapDays',gap_days));
 ELSE
  IF NOT(p_effect ?& ARRAY['fields','progress','dayStatus','blockCredit','dailyBalance','gap','telemetry'])
   OR p_effect-ARRAY['version','kind','fields','progress','dayStatus','blockCredit','dailyBalance','gap','telemetry']<>'{}'::jsonb THEN
   RAISE EXCEPTION 'invalid_clinical_close_effect' USING ERRCODE='22023'; END IF;
  f:=p_effect->'fields';g:=p_effect->'progress';gap:=p_effect->'gap';events:=p_effect->'telemetry';
  IF jsonb_typeof(f) IS DISTINCT FROM 'object' OR NOT(f ?& ARRAY['calories_consumed','calories_target','protein_g','protein_target',
    'carbs_g','fat_g','exercise_calories','training_done','xp_earned','current_protocol'])
   OR f-ARRAY['calories_consumed','calories_target','protein_g','protein_target','carbs_g','fat_g','exercise_calories','training_done','xp_earned','current_protocol']<>'{}'::jsonb
   OR jsonb_typeof(g) IS DISTINCT FROM 'object' OR NOT(g ?& ARRAY['xpTotal','level','currentStreak','longestStreak','blocksCompleted','deficitBlock','badgesEarned','lastActiveDate'])
   OR g-ARRAY['xpTotal','level','currentStreak','longestStreak','blocksCompleted','deficitBlock','badgesEarned','lastActiveDate']<>'{}'::jsonb
   OR jsonb_typeof(f->'training_done') IS DISTINCT FROM 'boolean' OR g->>'lastActiveDate' IS DISTINCT FROM p_close_date::text
   OR f->>'current_protocol' IS DISTINCT FROM historical_phase
   OR jsonb_typeof(g->'badgesEarned') IS DISTINCT FROM 'array' OR jsonb_array_length(g->'badgesEarned')>2048
   OR jsonb_typeof(gap) IS DISTINCT FROM 'array' OR jsonb_array_length(gap)>5
   OR jsonb_typeof(events) IS DISTINCT FROM 'array' OR jsonb_array_length(events) NOT BETWEEN 1 AND 6 THEN
   RAISE EXCEPTION 'invalid_clinical_close_fields' USING ERRCODE='22023'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(g->'badgesEarned') LOOP
   IF jsonb_typeof(item)<>'string' OR length(item#>>'{}') NOT BETWEEN 1 AND 256 THEN
    RAISE EXCEPTION 'invalid_clinical_close_badge' USING ERRCODE='22023'; END IF;
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(gap) LOOP
   IF jsonb_typeof(item)<>'string' OR item#>>'{}' NOT IN('cafe','almoco','lanche','jantar','ceia') THEN
    RAISE EXCEPTION 'invalid_clinical_close_gap' USING ERRCODE='22023'; END IF;
  END LOOP;
  calories:=private.mobile_clinical_close_number(f->'calories_consumed',false,0,2147483647,true);
  target:=private.mobile_clinical_close_number(f->'calories_target',true,1,2147483647,true);
  protein:=private.mobile_clinical_close_number(f->'protein_g',false,0,9999.99,false);
  protein_goal:=private.mobile_clinical_close_number(f->'protein_target',true,0,9999.99,false);
  carbs:=private.mobile_clinical_close_number(f->'carbs_g',false,0,9999.99,false);
  fat:=private.mobile_clinical_close_number(f->'fat_g',false,0,9999.99,false);
  exercise:=private.mobile_clinical_close_number(f->'exercise_calories',false,0,2147483647,true);
  xp:=private.mobile_clinical_close_number(f->'xp_earned',false,0,2147483647,true);
  xp_total:=private.mobile_clinical_close_number(g->'xpTotal',false,0,2147483647,true);
  lvl:=private.mobile_clinical_close_number(g->'level',false,1,2147483647,true);
  streak:=private.mobile_clinical_close_number(g->'currentStreak',false,0,2147483647,true);
  longest:=private.mobile_clinical_close_number(g->'longestStreak',false,0,2147483647,true);
  blocks:=private.mobile_clinical_close_number(g->'blocksCompleted',false,0,2147483647,true);
  deficit:=private.mobile_clinical_close_number(g->'deficitBlock',false,0,2147483647,true);
  credit:=private.mobile_clinical_close_number(p_effect->'blockCredit',false,-2147483648,2147483647,false);
  balance:=private.mobile_clinical_close_number(p_effect->'dailyBalance',false,-2147483648,2147483647,true);
  dstatus:=p_effect->>'dayStatus';
  IF dstatus NOT IN('complete','user_skipped','incomplete_no_response') OR xp_total::numeric<>old_xp::numeric+xp
   OR balance::numeric<>calories::numeric-coalesce(target,0)-exercise OR longest<streak
   OR longest<coalesce((before_progress->>'longest_streak')::integer,0) THEN
   RAISE EXCEPTION 'invalid_clinical_close_derived_fields' USING ERRCODE='22023'; END IF;
  -- Closing a past date is never a target recalculation, even before dawn.
  -- Preserve each historical field independently, including NULL.
  IF target IS DISTINCT FROM (facts#>>'{snapshot,calories_target}')::integer
   OR protein_goal IS DISTINCT FROM (facts#>>'{snapshot,protein_target}')::numeric THEN
   RAISE EXCEPTION 'clinical_close_stored_target_changed' USING ERRCODE='40001'; END IF;
  block_enabled:=coalesce(historical_phase='recomposicao' AND historical_deficit IN(400,500,600)
   AND facts#>>'{current,phase_origin,kind}'='assigned'
   AND NOT coalesce((facts#>>'{current,safety,no_plan}')::boolean,true),false);
  credit_status:=CASE WHEN historical_phase IS NULL OR (historical_phase='recomposicao' AND historical_deficit IS NULL)
   THEN 'preserved_unknown' WHEN block_enabled THEN 'calculated' ELSE 'not_applicable' END;
  IF NOT block_enabled AND (credit<>0 OR blocks<>old_blocks OR deficit<>old_deficit) THEN
   RAISE EXCEPTION 'clinical_close_block_protected' USING ERRCODE='40001'; END IF;
  SELECT coalesce(array_agg(value#>>'{}'),'{}'::text[]) INTO badges FROM jsonb_array_elements(g->'badgesEarned');
  SELECT coalesce(jsonb_agg(value),'[]'::jsonb) INTO new_badges FROM jsonb_array_elements(g->'badgesEarned')
   WHERE NOT coalesce(before_progress->'badges_earned','[]'::jsonb) @> jsonb_build_array(value);
  IF (SELECT count(*) FROM jsonb_array_elements(events) e WHERE e->>'event'='daily_closer.completed')<>1
   OR (SELECT count(*) FROM jsonb_array_elements(events))<>(SELECT count(DISTINCT e->>'event') FROM jsonb_array_elements(events) e) THEN
   RAISE EXCEPTION 'invalid_clinical_close_telemetry' USING ERRCODE='22023'; END IF;
  FOR event IN SELECT value FROM jsonb_array_elements(events) LOOP
   IF jsonb_typeof(event)<>'object' OR NOT(event ?& ARRAY['event','properties']) OR event-ARRAY['event','properties']<>'{}'::jsonb
    OR jsonb_typeof(event->'properties')<>'object' THEN RAISE EXCEPTION 'invalid_clinical_close_event' USING ERRCODE='22023'; END IF;
   props:=event->'properties';
   CASE event->>'event'
    WHEN 'daily_closer.completed' THEN
     IF props<>jsonb_build_object('snapshot_date',p_close_date,'calories_consumed',calories,'calories_target',target,
      'exercise_calories',exercise,'training_done',f->'training_done','day_status',dstatus,'xp_earned',xp,
      'blocks_completed',blocks,'blocks_completed_delta',blocks-old_blocks) THEN
      RAISE EXCEPTION 'invalid_clinical_close_completed_event' USING ERRCODE='22023'; END IF;
    WHEN 'badge.earned' THEN
     IF jsonb_array_length(new_badges)=0 OR props<>jsonb_build_object('badges',new_badges,'snapshot_date',p_close_date) THEN
      RAISE EXCEPTION 'invalid_clinical_close_badge_event' USING ERRCODE='22023'; END IF;
    WHEN 'bloco7700.block_completed' THEN
     IF NOT block_enabled OR blocks<=old_blocks OR props<>jsonb_build_object('snapshot_date',p_close_date,
      'previous_count',old_blocks,'new_count',blocks,'kg_estimate',blocks) THEN
      RAISE EXCEPTION 'invalid_clinical_close_block_event' USING ERRCODE='22023'; END IF;
    WHEN 'bloco7700.skipped_incomplete_day' THEN
     IF NOT block_enabled OR dstatus<>'incomplete_no_response' OR props<>jsonb_build_object('date',p_close_date,
      'gap',gap,'reason','lembrete enviado, paciente não respondeu') THEN
      RAISE EXCEPTION 'invalid_clinical_close_incomplete_event' USING ERRCODE='22023'; END IF;
    WHEN 'bloco7700.skipped_inactive_day' THEN
     IF NOT block_enabled OR jsonb_array_length(facts->'day_meals')+jsonb_array_length(facts->'day_workouts')<>0
      OR props<>jsonb_build_object('date',p_close_date,'calories_target',target) THEN
      RAISE EXCEPTION 'invalid_clinical_close_inactive_event' USING ERRCODE='22023'; END IF;
    WHEN 'bloco7700.skipped_subregistro' THEN
     IF NOT block_enabled OR NOT(props ?& ARRAY['date','day_status','calories_consumed','calories_target','pct'])
      OR props-ARRAY['date','day_status','calories_consumed','calories_target','pct']<>'{}'::jsonb
      OR props->>'date'<>p_close_date::text OR props->>'day_status'<>dstatus
      OR props->'calories_consumed'<>to_jsonb(calories) OR props->'calories_target' IS DISTINCT FROM to_jsonb(target)
      OR private.mobile_clinical_close_number(props->'pct',false,0,50,true) IS NULL THEN
      RAISE EXCEPTION 'invalid_clinical_close_subregistro_event' USING ERRCODE='22023'; END IF;
    ELSE RAISE EXCEPTION 'invalid_clinical_close_event_name' USING ERRCODE='22023';
   END CASE;
  END LOOP;
  -- FIRST business effect. Every source above is still locked, and a delegate
  -- refusal below raises so no preliminary aggregate can survive.
  snapshot_id:=(facts#>>'{snapshot,id}')::uuid;
  IF snapshot_id IS NULL THEN
   INSERT INTO public.daily_snapshots(user_id,date) VALUES(p_user_id,p_close_date)
    ON CONFLICT(user_id,date) DO NOTHING RETURNING id INTO snapshot_id;
   IF snapshot_id IS NULL THEN RAISE EXCEPTION 'clinical_close_snapshot_appeared' USING ERRCODE='40001'; END IF;
  END IF;
  UPDATE public.daily_snapshots SET calories_consumed=calories,calories_target=target,protein_g=protein,
   protein_target=protein_goal,carbs_g=carbs,fat_g=fat,exercise_calories=exercise,training_done=(f->>'training_done')::boolean,
   xp_earned=xp,current_protocol=historical_phase::public.protocol_enum,updated_at=observed
   WHERE id=snapshot_id AND user_id=p_user_id AND NOT day_closed RETURNING * INTO written;
  IF NOT FOUND OR written.daily_balance<>balance THEN RAISE EXCEPTION 'clinical_close_write_changed' USING ERRCODE='40001'; END IF;
  expected_progress:=CASE WHEN before_progress='null'::jsonb THEN NULL ELSE jsonb_build_object(
   'xp_total',before_progress->'xp_total','level',before_progress->'level','current_streak',before_progress->'current_streak',
   'longest_streak',before_progress->'longest_streak','blocks_completed',before_progress->'blocks_completed',
   'deficit_block',before_progress->'deficit_block','badges_earned',before_progress->'badges_earned',
   'last_active_date',before_progress->'last_active_date','updated_at',before_progress->'updated_at') END;
  delegate:=public.finalize_mobile_daily_close_atomic(p_user_id,snapshot_id,dstatus,xp_total,lvl,streak,longest,
   blocks,deficit,badges,p_close_date,observed,p_expected_timezone,to_jsonb(written),profile,expected_progress);
  IF delegate->'applied' IS DISTINCT FROM 'true'::jsonb OR delegate->'already_closed' IS DISTINCT FROM 'false'::jsonb
   OR delegate->>'snapshot_id' IS DISTINCT FROM snapshot_id::text OR delegate->>'day_status' IS DISTINCT FROM dstatus THEN
   RAISE EXCEPTION 'clinical_close_delegate_refused' USING ERRCODE='40001'; END IF;
  -- Re-read AFTER the delegate: `written` above was the preliminary aggregate.
  SELECT * INTO written FROM public.daily_snapshots WHERE id=snapshot_id AND user_id=p_user_id;
  IF NOT FOUND OR NOT written.day_closed OR written.closed_at IS NULL OR written.day_status::text<>dstatus
   OR written.daily_balance<>balance THEN
   RAISE EXCEPTION 'clinical_close_final_snapshot_changed' USING ERRCODE='40001';END IF;
  INSERT INTO private.mobile_clinical_closed_day_evidence(snapshot_id,user_id,operation_key,
   signup_epoch,signup_generation,context_hash,request_hash,effect_hash,snapshot_binding,recorded_at)
  VALUES(snapshot_id,p_user_id,p_operation_key,(facts#>>'{current,epoch}')::uuid,
   (facts#>>'{current,signup_generation}')::uuid,p_context_hash,rh,eh,
   private.mobile_clinical_closed_day_binding(written),observed);
  INSERT INTO public.product_events(user_id,event,properties)
   SELECT p_user_id,e->>'event',e->'properties' FROM jsonb_array_elements(events) e;
  result:=jsonb_build_object('date',p_close_date,'closed',true,'dryRun',false,'late',facts#>'{calendar,late}',
   'detail',jsonb_build_object('caloriesConsumed',calories,'exerciseCalories',exercise,
    'storedCaloriesTarget',facts#>'{snapshot,calories_target}','caloriesTarget',target,
    'storedProteinTarget',facts#>'{snapshot,protein_target}','proteinTarget',protein_goal,'dayStatus',dstatus,
    'xpEarned',xp,'blockCredit',credit,'blockCreditStatus',credit_status,'newBadges',new_badges,'progress',g));
 END IF;
 envelope:=jsonb_build_object('user_id',p_user_id,'operation_key',p_operation_key,'request',request,'result',result);
 INSERT INTO private.mobile_clinical_day_close_keys VALUES(p_user_id,p_operation_key,rh,eh,envelope,observed);
 RETURN envelope;
END $$;

CREATE FUNCTION private.get_mobile_clinical_flow_period_at(p_user_id uuid,p_period text,
 p_expected_from date,p_expected_to date,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE current_state jsonb;first_day date;last_day date;n integer;rows jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_period IS NULL OR p_period NOT IN('semana','mes') OR p_expected_from IS NULL OR p_expected_to IS NULL THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_period' USING ERRCODE='22023';END IF;
 current_state:=private.capture_mobile_current_clinical_state_at(p_user_id,'profile',NULL,NULL,p_observed_at);
 last_day:=(current_state->>'date')::date;n:=CASE p_period WHEN 'semana' THEN 7 ELSE 30 END;
 first_day:=last_day-(n-1);
 IF p_expected_from<>first_day OR p_expected_to<>last_day THEN
  RAISE EXCEPTION 'mobile_clinical_period_changed' USING ERRCODE='40001';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('date',d.date,'calories_consumed',d.calories_consumed,
  'protein_g',d.protein_g,'day_status',d.day_status,'balance_proven',proof.proven,
  'daily_balance',CASE WHEN proof.proven THEN d.daily_balance ELSE NULL END) ORDER BY d.date),'[]'::jsonb)
 INTO rows FROM public.daily_snapshots d
 LEFT JOIN private.mobile_clinical_closed_day_evidence e ON e.snapshot_id=d.id AND e.user_id=p_user_id
 LEFT JOIN private.mobile_clinical_day_close_keys k ON k.user_id=p_user_id AND k.operation_key=e.operation_key
 CROSS JOIN LATERAL(SELECT coalesce(e.snapshot_binding=private.mobile_clinical_closed_day_binding(d)
  AND e.signup_epoch IS NOT DISTINCT FROM (current_state->>'epoch')::uuid
  AND e.signup_generation IS NOT DISTINCT FROM (current_state->>'signup_generation')::uuid
  AND k.request_hash=e.request_hash AND k.effect_hash=e.effect_hash
  AND k.result->>'user_id'=p_user_id::text AND k.result->>'operation_key'=e.operation_key::text
  AND k.result#>>'{result,closed}'='true' AND k.result#>>'{result,date}'=d.date::text
  AND d.closed_at IS NOT NULL AND d.calories_target>0
  AND d.daily_balance=d.calories_consumed-d.calories_target-d.exercise_calories,false) AS proven) proof
 WHERE d.user_id=p_user_id AND d.date BETWEEN first_day AND last_day AND d.day_closed;
 RETURN jsonb_build_object('version',1,'period',p_period,'from',first_day,'to',last_day,
  'observed_at',current_state->'observed_at','rows',rows);
END $$;
CREATE FUNCTION public.get_mobile_clinical_flow_period(p_user_id uuid,p_period text,
 p_expected_from date,p_expected_to date) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.get_mobile_clinical_flow_period_at(p_user_id,p_period,p_expected_from,p_expected_to,NULL);
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_closed_day_evidence_immutable(),
 private.mobile_clinical_closed_day_binding(public.daily_snapshots),
 private.get_mobile_clinical_flow_period_at(uuid,text,date,date,timestamptz),
 public.get_mobile_clinical_flow_period(uuid,text,date,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_flow_period(uuid,text,date,date) TO service_role;
COMMIT;

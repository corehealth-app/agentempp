-- Dormant whole-day authority. No existing writer, route, flag or cron replaced.
-- All business rows, telemetry and acknowledgement commit/roll back together.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)') IS NULL
  OR to_regprocedure('public.finalize_mobile_daily_close_atomic(uuid,uuid,text,integer,integer,integer,integer,integer,integer,text[],date,timestamptz,text,jsonb,jsonb,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'whole_clinical_close_requires_current_authority' USING ERRCODE='42501'; END IF;
END $$;
CREATE TABLE private.mobile_clinical_day_close_keys (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 request_hash text NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 effect_hash text NOT NULL CHECK(effect_hash ~ '^[0-9a-f]{64}$'),
 result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
 acknowledged_at timestamptz NOT NULL CHECK(isfinite(acknowledged_at)),
 PRIMARY KEY(user_id,operation_key)
);
ALTER TABLE private.mobile_clinical_day_close_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_day_close_keys FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_day_close_key_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_day_close_keys FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.capture_mobile_clinical_day_close_at(p_user_id uuid,p_from date,p_close_date date,
 p_expected_timezone text,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE u public.users%ROWTYPE;p jsonb;pr jsonb;s jsonb;c jsonb;stable jsonb;pa jsonb;facts jsonb;request jsonb;
 observed timestamptz;today date;latest date;frontier date;first_open date;start_at timestamptz;end_at timestamptz;
 before_end timestamptz;pattern_snaps jsonb;pattern_meals jsonb;meals jsonb;workouts jsonb;messages jsonb;historical_target jsonb;
 registered jsonb;skips jsonb;earlier jsonb;later jsonb;disposition text;late boolean;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_from IS NULL OR NOT isfinite(p_from) OR extract(year FROM p_from) NOT BETWEEN 1 AND 9999
  OR (p_close_date IS NOT NULL AND (NOT isfinite(p_close_date) OR extract(year FROM p_close_date) NOT BETWEEN 1 AND 9999
    OR p_close_date<p_from)) OR p_expected_timezone IS NULL OR p_expected_timezone='' THEN
  RAISE EXCEPTION 'invalid_clinical_day_close_scope' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user_id;
 IF u.wpp IS NOT NULL OR u.timezone IS DISTINCT FROM p_expected_timezone
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=u.timezone) THEN
  RAISE EXCEPTION 'clinical_day_close_context_changed' USING ERRCODE='40001'; END IF;
 IF (p_close_date IS NOT NULL AND NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':'||p_close_date::text,0)))
  OR NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':daily-close',0)) THEN
  RAISE EXCEPTION 'clinical_day_close_busy' USING ERRCODE='55P03'; END IF;
 -- Existing rows outside the read window may be moved INTO it. Protect all of
 -- this owner's rows, not just their current membership. Parent FK locks fence
 -- inserts; NOWAIT avoids deadlocks with the unchanged legacy writers.
 BEGIN
  PERFORM x.user_id FROM public.user_profiles x WHERE x.user_id=p_user_id FOR SHARE NOWAIT;
  IF NOT FOUND THEN RAISE EXCEPTION 'clinical_day_close_profile_unavailable' USING ERRCODE='55000'; END IF;
  PERFORM x.user_id FROM public.user_progress x WHERE x.user_id=p_user_id FOR UPDATE NOWAIT;
  PERFORM x.id FROM public.daily_snapshots x WHERE x.user_id=p_user_id ORDER BY x.id FOR UPDATE NOWAIT;
  PERFORM x.id FROM public.meal_logs x WHERE x.user_id=p_user_id OR x.snapshot_id IN
   (SELECT d.id FROM public.daily_snapshots d WHERE d.user_id=p_user_id) ORDER BY x.id FOR SHARE NOWAIT;
  PERFORM x.id FROM public.workout_logs x WHERE x.user_id=p_user_id OR x.snapshot_id IN
   (SELECT d.id FROM public.daily_snapshots d WHERE d.user_id=p_user_id) ORDER BY x.id FOR SHARE NOWAIT;
  PERFORM x.id FROM public.messages x WHERE x.user_id=p_user_id ORDER BY x.id FOR SHARE NOWAIT;
  PERFORM x.id FROM public.product_events x WHERE x.user_id=p_user_id ORDER BY x.id FOR SHARE NOWAIT;
  LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'clinical_day_close_busy' USING ERRCODE='55P03';
 END;
 -- The historical gap helper joins through snapshot_id. Inconsistent owner
 -- associations are refused, never read into another patient's context.
 IF EXISTS(SELECT 1 FROM public.meal_logs x JOIN public.daily_snapshots d ON d.id=x.snapshot_id
   WHERE (x.user_id=p_user_id OR d.user_id=p_user_id) AND x.user_id<>d.user_id)
  OR EXISTS(SELECT 1 FROM public.workout_logs x JOIN public.daily_snapshots d ON d.id=x.snapshot_id
   WHERE (x.user_id=p_user_id OR d.user_id=p_user_id) AND x.user_id<>d.user_id) THEN
  RAISE EXCEPTION 'clinical_day_close_association_changed' USING ERRCODE='40001'; END IF;
 observed:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(observed) OR extract(year FROM observed AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
  RAISE EXCEPTION 'invalid_clinical_day_close_clock' USING ERRCODE='22023'; END IF;
 c:=private.capture_mobile_current_clinical_state_at(p_user_id,'profile',NULL,NULL,observed);
 today:=(c->>'date')::date;
 latest:=today-CASE WHEN observed-(today::timestamp AT TIME ZONE u.timezone)>=interval '30 minutes' THEN 1 ELSE 2 END;
 late:=CASE WHEN p_close_date IS NOT NULL THEN p_close_date<today-1
  OR (p_close_date=today-1 AND extract(hour FROM observed AT TIME ZONE u.timezone)>4) END;
 SELECT private.mobile_clinical_canonical_row(to_jsonb(x),
  ARRAY['created_at','updated_at','bf_estimated_at','cycle_start_at','body_fat_measured_at','onboarding_completed_at','weight_measured_at'],
  ARRAY[]::text[]) INTO p FROM public.user_profiles x WHERE x.user_id=p_user_id;
 SELECT to_jsonb(x) INTO pr FROM public.user_progress x WHERE x.user_id=p_user_id;
 SELECT to_jsonb(x) INTO s FROM public.daily_snapshots x WHERE x.user_id=p_user_id AND x.date=p_close_date;
 SELECT greatest((pr->>'last_active_date')::date,max(x.date)) INTO frontier
  FROM public.daily_snapshots x WHERE x.user_id=p_user_id AND x.day_closed;
 first_open:=greatest(p_from,frontier+1);
 start_at:=p_close_date::timestamp AT TIME ZONE u.timezone;
 end_at:=(p_close_date+1)::timestamp AT TIME ZONE u.timezone;
 before_end:=coalesce(p_close_date,latest+1)::timestamp AT TIME ZONE u.timezone;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'user_id',x.user_id,'snapshot_id',x.snapshot_id,
  'meal_type',x.meal_type,'kcal',x.kcal,'protein_g',x.protein_g,'carbs_g',x.carbs_g,'fat_g',x.fat_g,
  'consumed_at',x.consumed_at) ORDER BY x.id),'[]'::jsonb) INTO meals FROM public.meal_logs x
  WHERE x.user_id=p_user_id AND x.consumed_at>=start_at AND x.consumed_at<end_at;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'user_id',x.user_id,'estimated_kcal',x.estimated_kcal,
  'performed_at',x.performed_at) ORDER BY x.id),'[]'::jsonb) INTO workouts FROM public.workout_logs x
  WHERE x.user_id=p_user_id AND x.performed_at>=start_at AND x.performed_at<end_at;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'created_at',x.created_at) ORDER BY x.id),'[]'::jsonb)
  INTO messages FROM public.messages x WHERE x.user_id=p_user_id AND x.direction='in' AND x.created_at>=start_at AND x.created_at<end_at;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'date',x.date) ORDER BY x.id),'[]'::jsonb) INTO pattern_snaps
  FROM public.daily_snapshots x WHERE x.user_id=p_user_id AND x.date BETWEEN today-14 AND today-1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'snapshot_id',x.snapshot_id,'meal_type',x.meal_type) ORDER BY x.id),'[]'::jsonb)
  INTO pattern_meals FROM public.meal_logs x WHERE x.snapshot_id IN
   (SELECT d.id FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date BETWEEN today-14 AND today-1)
   AND x.meal_type IS NOT NULL;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'meal_type',x.meal_type) ORDER BY x.id),'[]'::jsonb) INTO registered
  FROM public.meal_logs x WHERE x.snapshot_id=(s->>'id')::uuid AND x.meal_type IS NOT NULL;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'occurred_at',x.occurred_at,
  'properties',jsonb_build_object('local_date',x.properties->'local_date','meal_type',x.properties->'meal_type')) ORDER BY x.id),'[]'::jsonb)
  INTO skips FROM public.product_events x WHERE x.user_id=p_user_id AND x.event='meal.user_skipped' AND
   (x.properties->>'local_date'=p_close_date::text OR (x.occurred_at>=start_at AND x.occurred_at<end_at
    AND (jsonb_typeof(x.properties->'local_date') IS DISTINCT FROM 'string' OR x.properties->>'local_date'=p_close_date::text)));
 SELECT coalesce(jsonb_agg(z ORDER BY z->>'kind',z->>'id'),'[]'::jsonb) INTO earlier FROM (
  SELECT jsonb_build_object('kind','meal','id',x.id::text,'at',x.consumed_at) z FROM public.meal_logs x
   WHERE x.user_id=p_user_id AND x.consumed_at>=(first_open::timestamp AT TIME ZONE u.timezone) AND x.consumed_at<before_end
  UNION ALL SELECT jsonb_build_object('kind','workout','id',x.id::text,'at',x.performed_at) FROM public.workout_logs x
   WHERE x.user_id=p_user_id AND x.performed_at>=(first_open::timestamp AT TIME ZONE u.timezone) AND x.performed_at<before_end
  UNION ALL SELECT jsonb_build_object('kind','message','id',x.id::text,'at',x.created_at) FROM public.messages x
   WHERE x.user_id=p_user_id AND x.direction='in' AND x.created_at>=(first_open::timestamp AT TIME ZONE u.timezone) AND x.created_at<before_end
 ) activity;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'date',x.date) ORDER BY x.id),'[]'::jsonb) INTO later
  FROM public.daily_snapshots x WHERE x.user_id=p_user_id AND x.day_closed AND x.date>p_close_date;
 IF p_close_date IS NULL THEN
  disposition:=CASE WHEN jsonb_array_length(earlier)>0 THEN 'pending_activity'
   WHEN latest<p_from OR pr IS NULL OR coalesce((pr->>'current_streak')::integer,0)<=0
    OR pr->>'last_active_date' IS NULL OR latest-(pr->>'last_active_date')::date<2 THEN 'unchanged' ELSE 'ready' END;
 ELSE
  disposition:=CASE WHEN p_close_date>latest THEN 'not_closable_yet' WHEN coalesce((s->>'day_closed')::boolean,false) THEN 'already_closed'
   WHEN p_close_date<=frontier OR jsonb_array_length(later)>0 THEN 'behind_frontier'
   WHEN jsonb_array_length(earlier)>0 THEN 'earlier_date_changed'
   WHEN jsonb_array_length(meals)+jsonb_array_length(workouts)+jsonb_array_length(messages)=0 THEN 'inactive' ELSE 'ready' END;
 END IF;
 pa:=CASE WHEN c->>'signup_generation' IS NOT NULL AND c->>'epoch' IS NOT NULL THEN
  private.mobile_clinical_protocol_authority(p_user_id,(c->>'signup_generation')::uuid,(c->>'epoch')::uuid,NULL,observed) ELSE '{}'::jsonb END;
 historical_target:=CASE WHEN p_close_date IS NOT NULL AND c->>'signup_generation' IS NOT NULL AND c->>'epoch' IS NOT NULL THEN
  private.mobile_clinical_target_origin(p_user_id,(c->>'signup_generation')::uuid,(c->>'epoch')::uuid,p_close_date,
   least(observed,end_at-interval '1 microsecond')) END;
 request:=jsonb_build_object('kind',CASE WHEN p_close_date IS NULL THEN 'reset' ELSE 'close' END,
  'from',p_from,'date',p_close_date,'timezone',u.timezone);
 facts:=jsonb_build_object('owner',jsonb_build_object('id',u.id,'status',u.status,'wpp',u.wpp,'timezone',u.timezone,'locale',u.locale),
  'current',c,'profile',p,'progress',pr,'snapshot',s,'frontier',frontier,'later_closed',later,
  'calendar',jsonb_build_object('today',today,'latest_closable_date',latest,'date',p_close_date,'late',late,
    'day_start',start_at,'day_end',end_at,'pattern_from',today-14,'pattern_to',today-1,
    'current_day_end',to_char(((today+1)::timestamp AT TIME ZONE u.timezone) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
  'day_meals',meals,'day_workouts',workouts,'inbound_messages',messages,'pattern_snapshots',pattern_snaps,
  'pattern_meals',pattern_meals,'registered_meals',registered,'skip_events',skips,'earlier_activity',earlier,
  'target_authority',jsonb_build_object('phase_origin',c->'phase_origin','body_fat_origin',pa->'body_fat_origin',
   'signup_body_fat_origin',pa->'signup_body_fat_origin','body_fat_candidate',NULL,'applied_target',historical_target),'disposition',disposition);
 IF octet_length(facts::text)>2097152 THEN RAISE EXCEPTION 'clinical_day_close_context_too_large' USING ERRCODE='54000'; END IF;
 stable:=facts #- '{current,observed_at}' #- '{current,context_hash}' #- '{current,safety,observed_at}';
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'request',request,'facts',facts,
  'observed_at',to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'context_hash',encode(extensions.digest(jsonb_build_object('version',1,'request',request,'facts',stable)::text,'sha256'),'hex'));
END $$;

CREATE FUNCTION private.mobile_clinical_close_number(v jsonb,allow_null boolean,lo numeric,hi numeric,whole boolean)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE n numeric;
BEGIN
 IF allow_null AND v='null'::jsonb THEN RETURN NULL; END IF;
 IF jsonb_typeof(v) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_clinical_day_close_number' USING ERRCODE='22023'; END IF;
 n:=v::text::numeric;
 IF n<lo OR n>hi OR (whole AND trunc(n)<>n) THEN RAISE EXCEPTION 'invalid_clinical_day_close_number' USING ERRCODE='22023'; END IF;
 RETURN n;
END $$;
CREATE FUNCTION private.get_mobile_clinical_day_close_receipt(p_user_id uuid,p_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE r jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL THEN RAISE EXCEPTION 'invalid_clinical_day_close_key' USING ERRCODE='22023'; END IF;
 SELECT x.result INTO r FROM private.mobile_clinical_day_close_keys x WHERE x.user_id=p_user_id AND x.operation_key=p_operation_key;
 RETURN r;
END $$;
CREATE FUNCTION private.apply_mobile_clinical_day_close_at(p_user_id uuid,p_operation_key uuid,p_from date,p_close_date date,
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

CREATE FUNCTION public.capture_mobile_clinical_day_close(p_user_id uuid,p_from date,p_close_date date,p_expected_timezone text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_clinical_day_close_at(p_user_id,p_from,p_close_date,p_expected_timezone,NULL); END $$;
CREATE FUNCTION public.apply_mobile_clinical_day_close(p_user_id uuid,p_operation_key uuid,p_from date,p_close_date date,
 p_expected_timezone text,p_context_hash text,p_effect jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN PERFORM private.assert_trusted_backend();
 RETURN private.apply_mobile_clinical_day_close_at(p_user_id,p_operation_key,p_from,p_close_date,p_expected_timezone,p_context_hash,p_effect,NULL); END $$;
CREATE FUNCTION public.get_mobile_clinical_day_close_receipt(p_user_id uuid,p_operation_key uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM private.assert_trusted_backend();RETURN private.get_mobile_clinical_day_close_receipt(p_user_id,p_operation_key); END $$;
REVOKE ALL ON FUNCTION private.capture_mobile_clinical_day_close_at(uuid,date,date,text,timestamptz),
 private.mobile_clinical_close_number(jsonb,boolean,numeric,numeric,boolean),
 private.get_mobile_clinical_day_close_receipt(uuid,uuid),
 private.apply_mobile_clinical_day_close_at(uuid,uuid,date,date,text,text,jsonb,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.capture_mobile_clinical_day_close(uuid,date,date,text),
 public.apply_mobile_clinical_day_close(uuid,uuid,date,date,text,text,jsonb),public.get_mobile_clinical_day_close_receipt(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.capture_mobile_clinical_day_close(uuid,date,date,text),
 public.apply_mobile_clinical_day_close(uuid,uuid,date,date,text,text,jsonb),public.get_mobile_clinical_day_close_receipt(uuid,uuid) TO service_role;
COMMIT;

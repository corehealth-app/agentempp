-- Current real whole-close writer and immutable receipt, synthetic rollback only.
BEGIN;
\ir fixtures/mobile_clinical_day_close_fixture.sql
CREATE TEMP TABLE workout_close_golden(kind text,envelope jsonb) ON COMMIT DROP;
CREATE TEMP TABLE workout_period_golden(kind text,packet jsonb) ON COMMIT DROP;
DO $unknown$
DECLARE q jsonb:=m3b_cycle_test.close_seed(1391);u uuid:=(q->>'user')::uuid;s uuid:=(q->>'snapshot')::uuid;
 c jsonb;e jsonb;r jsonb;again jsonb;key uuid:=gen_random_uuid();before_state jsonb;message text;packet jsonb;period text;last_day date;
BEGIN
 INSERT INTO public.user_progress(user_id,xp_total,blocks_completed,deficit_block) VALUES(u,40,1,321);
 INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at)
 VALUES(u,s,'caminhada',30,NULL,((q->>'date')::date+time '12:00') AT TIME ZONE (q->>'zone'));
 c:=m3b_cycle_test.close_capture(q);e:=m3b_cycle_test.close_effect(q);
 e:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(e,'{fields,training_done}','true'),'{fields,xp_earned}','20'),'{blockCredit}','0'),'{progress,deficitBlock}','321');
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{progress,xpTotal}','60'),'{progress,blocksCompleted}','1'),'{telemetry,0,properties,training_done}','true');
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{telemetry,0,properties,xp_earned}','20'),'{telemetry,0,properties,blocks_completed}','1'),'{telemetry,0,properties,exercise_calories}','null');
 e:=jsonb_set(e,'{telemetry,0,properties,exercise_energy_complete}','false');
 before_state:=m3b_cycle_test.original_state(u);
 BEGIN PERFORM m3b_cycle_test.close_apply(q,c,gen_random_uuid(),jsonb_set(e,'{telemetry,0,properties,exercise_calories}','0'));EXCEPTION WHEN SQLSTATE '22023' THEN GET STACKED DIAGNOSTICS message=MESSAGE_TEXT;END;
 PERFORM m3b_cycle_test.ok(message='invalid_clinical_close_completed_event' AND before_state=m3b_cycle_test.original_state(u),'unknown partial numeric telemetry refused before any close effects');
 r:=m3b_cycle_test.close_apply(q,c,key,e);
 PERFORM m3b_cycle_test.ok(r#>>'{result,calculation_version}'='bodyflow.day-close.v2'
  AND r#>'{result,detail,exerciseCalories}'='null'::jsonb
  AND r#>>'{result,detail,exerciseEnergy,reason}'='unknown_workout_energy'
  AND r#>>'{result,detail,blockCreditStatus}'='preserved_unknown','new unknown result uses explicit closed v2 null energy');
 PERFORM m3b_cycle_test.ok((SELECT day_closed AND NOT exercise_energy_complete AND xp_earned=20 FROM public.daily_snapshots WHERE id=s)
  AND (SELECT xp_total=60 AND blocks_completed=1 AND deficit_block=321 FROM public.user_progress WHERE user_id=u),'unknown close keeps performed XP and prior official block');
 PERFORM m3b_cycle_test.ok((SELECT properties->'exercise_calories'='null'::jsonb AND properties->'exercise_energy_complete'='false'::jsonb FROM public.product_events WHERE user_id=u AND event='daily_closer.completed'),'unknown completed event never publishes partial zero');
 INSERT INTO workout_close_golden VALUES('unknown',r);
 last_day:=(clock_timestamp() AT TIME ZONE (q->>'zone'))::date;
 FOREACH period IN ARRAY ARRAY['semana','mes'] LOOP
  before_state:=m3b_cycle_test.original_state(u);
  packet:=private.get_mobile_clinical_flow_period_at(u,period,last_day-CASE WHEN period='semana' THEN 6 ELSE 29 END,last_day,NULL);
  PERFORM m3b_cycle_test.ok(packet#>'{rows,0,balance_proven}'='false'::jsonb AND packet#>'{rows,0,daily_balance}'='null'::jsonb
   AND packet#>'{rows,0,calories_consumed}'='1600'::jsonb AND packet#>'{rows,0,protein_g}'='100'::jsonb,'unknown close keeps food/protein but cannot certify Flow '||period||' balance');
  PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(u),'unknown period remains read only '||period);
  INSERT INTO workout_period_golden VALUES('unknown_'||period,packet);
 END LOOP;
 UPDATE public.workout_logs SET estimated_kcal=0 WHERE user_id=u;
 packet:=private.get_mobile_clinical_flow_period_at(u,'semana',last_day-6,last_day,NULL);
 PERFORM m3b_cycle_test.ok(packet#>'{rows,0,balance_proven}'='false'::jsonb AND packet#>'{rows,0,daily_balance}'='null'::jsonb,'NULL to known zero cannot retroactively certify an originally unavailable close');

 UPDATE public.workout_logs SET estimated_kcal=90 WHERE user_id=u;
 again:=m3b_cycle_test.close_apply(q,c,key,e);
 PERFORM m3b_cycle_test.ok(again=r AND (SELECT exercise_energy_complete FROM public.daily_snapshots WHERE id=s)
  AND (SELECT xp_total=60 AND deficit_block=321 FROM public.user_progress WHERE user_id=u),'coverage repair does not rewrite historical acknowledgement or duplicate XP/credit');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_day_close_receipt(u,key)=r,'read-only cold receipt preserves nullable original');
END $unknown$;
DO $known$
DECLARE q jsonb:=m3b_cycle_test.close_seed(1392);c jsonb;e jsonb;r jsonb;k uuid:=gen_random_uuid();packet jsonb;last_day date;
BEGIN
 c:=m3b_cycle_test.close_capture(q);e:=m3b_cycle_test.close_effect(q);r:=m3b_cycle_test.close_apply(q,c,k,e);
 PERFORM m3b_cycle_test.ok(NOT(r->'result'?'calculation_version') AND NOT(r#>'{result,detail}'?'exerciseEnergy')
  AND r#>'{result,detail,exerciseCalories}'='0'::jsonb,'known result remains exact legacy numeric shape');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_day_close_receipt((q->>'user')::uuid,k)=r,'known legacy result replays unchanged');
 INSERT INTO workout_close_golden VALUES('known',r);
 last_day:=(clock_timestamp() AT TIME ZONE (q->>'zone'))::date;
 packet:=private.get_mobile_clinical_flow_period_at((q->>'user')::uuid,'semana',last_day-6,last_day,NULL);
 PERFORM m3b_cycle_test.ok(packet#>'{rows,0,balance_proven}'='true'::jsonb AND packet#>'{rows,0,daily_balance}'='-400'::jsonb,'known legacy period balance proof remains available');
 INSERT INTO workout_period_golden VALUES('known_semana',packet);

END $known$;
DO $timezone_coverage$
DECLARE u uuid:='139c0000-0000-4000-8000-000000000494';d date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-1;s uuid;start_at timestamptz;end_at timestamptz;code text;version timestamptz;written integer;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'workout-zone-coverage@example.invalid','active','UTC');
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,calories_consumed) VALUES(u,d,1900,1500) RETURNING id INTO s;
 INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at)
 VALUES(u,s,'caminhada',30,NULL,(d+time '01:00') AT TIME ZONE 'UTC');
 UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=u;
 start_at:=d::timestamp AT TIME ZONE 'America/Sao_Paulo';end_at:=(d+1)::timestamp AT TIME ZONE 'America/Sao_Paulo';
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u AND performed_at>=start_at AND performed_at<end_at)
  AND (SELECT count(*)=1 AND bool_and(estimated_kcal IS NULL) FROM public.workout_logs WHERE user_id=u AND snapshot_id=s)
  AND (SELECT NOT exercise_energy_complete FROM public.daily_snapshots WHERE id=s),'new-zone subset is empty while the owned snapshot still proves NULL coverage');
 -- The SDK sends the observed numeric aggregate but only for the exact
 -- version read, with the physical marker omitted. The NULL day is unchanged.
 SELECT updated_at INTO version FROM public.daily_snapshots WHERE id=s;
 UPDATE public.daily_snapshots SET calories_consumed=1500,exercise_calories=0
 WHERE id=s AND NOT day_closed AND updated_at=version;
 GET DIAGNOSTICS written=ROW_COUNT;
 PERFORM m3b_cycle_test.ok(written=1,'unchanged SDK version can write its observed aggregate');
 BEGIN PERFORM public.finalize_daily_close_atomic(u,s,'complete',15,1,1,1,0,500,ARRAY[]::text[],d);EXCEPTION WHEN SQLSTATE '40001' THEN code:=SQLSTATE;END;
 PERFORM m3b_cycle_test.ok(code='40001' AND (SELECT NOT exercise_energy_complete AND NOT day_closed FROM public.daily_snapshots WHERE id=s)
  AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u),'failed later finalizer cannot leave falsely complete coverage or credit');
 SELECT updated_at INTO version FROM public.daily_snapshots WHERE id=s;
 UPDATE public.workout_logs SET estimated_kcal=100 WHERE user_id=u;
 -- Exact stale exercise0 payload is present, unlike the earlier incomplete
 -- proof. The CAS must update zero rows after the real physical repair.
 UPDATE public.daily_snapshots SET calories_consumed=1500,exercise_calories=0,training_done=true,xp_earned=20
 WHERE id=s AND NOT day_closed AND updated_at=version;
 GET DIAGNOSTICS written=ROW_COUNT;
 PERFORM m3b_cycle_test.ok(written=0 AND (SELECT estimated_kcal=100 FROM public.workout_logs WHERE user_id=u AND snapshot_id=s)
  AND (SELECT exercise_energy_complete AND exercise_calories=100 AND NOT day_closed AND xp_earned=0 FROM public.daily_snapshots WHERE id=s)
  AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u),'stale SDK exercise0 cannot overwrite physical repair100 or grant XP/credit');
 SELECT updated_at INTO version FROM public.daily_snapshots WHERE id=s;
 UPDATE public.daily_snapshots SET updated_at=clock_timestamp() WHERE id=s;
 UPDATE public.daily_snapshots SET exercise_calories=0,xp_earned=20 WHERE id=s AND NOT day_closed AND updated_at=version;
 GET DIAGNOSTICS written=ROW_COUNT;
 PERFORM m3b_cycle_test.ok(written=0 AND (SELECT exercise_energy_complete AND exercise_calories=100 AND xp_earned=0 FROM public.daily_snapshots WHERE id=s),'version-only change refuses stale SDK aggregates');
 SELECT updated_at INTO version FROM public.daily_snapshots WHERE id=s;
 UPDATE public.daily_snapshots SET day_closed=true WHERE id=s;
 UPDATE public.daily_snapshots SET exercise_calories=0,xp_earned=20 WHERE id=s AND NOT day_closed AND updated_at=version;
 GET DIAGNOSTICS written=ROW_COUNT;
 PERFORM m3b_cycle_test.ok(written=0 AND (SELECT exercise_energy_complete AND exercise_calories=100 AND xp_earned=0 FROM public.daily_snapshots WHERE id=s),'concurrently closed day refuses stale SDK aggregates');
 INSERT INTO public.daily_snapshots(user_id,date,exercise_calories,training_done,xp_earned) VALUES(u,d,0,false,20)
 ON CONFLICT(user_id,date) DO NOTHING;
 GET DIAGNOSTICS written=ROW_COUNT;
 PERFORM m3b_cycle_test.ok(written=0 AND (SELECT exercise_energy_complete AND exercise_calories=100 AND training_done AND xp_earned=0 FROM public.daily_snapshots WHERE id=s),'SDK ignoreDuplicates leaves a newly appeared physical row intact');
END $timezone_coverage$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT jsonb_build_object('provenance','Actual local owned whole-close PostgreSQL writer under rollback only',
 'workout_close_golden',jsonb_agg(jsonb_build_object('kind',kind,'envelope',envelope) ORDER BY kind)) FROM workout_close_golden;
SELECT jsonb_build_object('workout_period_golden',jsonb_agg(jsonb_build_object('kind',kind,'packet',packet) ORDER BY kind)) FROM workout_period_golden;
ROLLBACK;

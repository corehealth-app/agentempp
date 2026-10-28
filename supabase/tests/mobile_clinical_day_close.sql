-- Real owned PostgreSQL, synthetic calculations only; not a core/BFF proof.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
DO $$ BEGIN
 IF to_regprocedure('private.capture_mobile_clinical_day_close_at(uuid,date,date,text,timestamptz)') IS NULL
  OR to_regprocedure('private.apply_mobile_clinical_day_close_at(uuid,uuid,date,date,text,text,jsonb,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'M3B_ASSERT:whole_close_and_reset_authority_missing'; END IF;
END $$;
\ir fixtures/mobile_clinical_day_close_fixture.sql
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3100);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;k uuid:=gen_random_uuid();before_state jsonb;
BEGIN
 before_state:=m3b_cycle_test.original_state(a);c:=m3b_cycle_test.close_capture(q);
 PERFORM m3b_cycle_test.ok(c#>>'{facts,disposition}'='ready' AND before_state=m3b_cycle_test.original_state(a),
  'close capture reads exact historical facts without business writes');
 PERFORM m3b_cycle_test.ok(c#>>'{facts,current,date}'=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date::text
  AND c#>>'{facts,calendar,date}'=q->>'date','current clinical date stays distinct from historical closing date');
 PERFORM m3b_cycle_test.ok(c#>>'{facts,profile,onboarding_completed_at}' ~ '^.{19}\.[0-9]{6}Z$'
  AND c#>>'{facts,calendar,current_day_end}'=to_char((((c#>>'{facts,current,date}')::date+1)::timestamp
   AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'formula context receives canonical profile micros and the actual next civil boundary');
 r:=m3b_cycle_test.close_apply(q,c,k);
 PERFORM m3b_cycle_test.ok(r#>>'{result,closed}'='true' AND r#>>'{result,date}'=q->>'date','one authority closes the selected date');
 PERFORM m3b_cycle_test.ok((SELECT day_closed AND calories_consumed=1600 AND daily_balance=-400
  AND water_consumed_ml=777 AND calories_target=2000 FROM public.daily_snapshots WHERE user_id=a),
  'dayFields and finalization apply together while hydration survives');
 PERFORM m3b_cycle_test.ok((SELECT xp_total=15 AND deficit_block=400 AND last_active_date=(q->>'date')::date
  FROM public.user_progress WHERE user_id=a),'same transaction applies supplied trusted derived progress');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM public.product_events WHERE user_id=a AND event='daily_closer.completed'),
  'completed telemetry is committed once');
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.close_apply(q,c,k)=r AND before_state=m3b_cycle_test.original_state(a),
  'same request returns original without duplicate writes or telemetry');
 PERFORM public.reset_user_conversation_atomic(a,true);
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.close_apply(q,c,k)=r AND before_state=m3b_cycle_test.original_state(a),
  'original close acknowledgement survives actual signup reset without effects');
 PERFORM m3b_cycle_test.throws(format('SELECT private.apply_mobile_clinical_day_close_at(%L,%L,%L,%L,%L,%L,%L,NULL)',a,k,
  q->>'from',q->>'date',q->>'zone',c->>'context_hash',jsonb_set(m3b_cycle_test.close_effect(q),'{fields,xp_earned}','99')),
  '40001','same operation cannot accept a different effect');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3101);a uuid:=(q->>'user')::uuid;c jsonb;before_state jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001',
  'new health revision refuses before all day/progress effects');
 PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a),'health refusal leaves no preliminary dayFields');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3102);a uuid:=(q->>'user')::uuid;c jsonb;before_state jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);
 UPDATE public.meal_logs SET kcal=1700 WHERE user_id=a;
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001',
  'changed meal facts invalidate the old whole-close calculation');
 PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a),'source refusal preserves every original row');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3103);a uuid:=(q->>'user')::uuid;c jsonb;before_state jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);
 INSERT INTO public.meal_logs(user_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at)
 VALUES(a,'almoco','synthetic earlier',100,50,0,0,0,((q->>'date')::date-1+time '12:00') AT TIME ZONE 'America/Sao_Paulo');
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001',
  'new earlier activity cannot be skipped by advancing the frontier');
 PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a),'earlier activity refusal writes nothing');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3104);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;k uuid:=gen_random_uuid();before_state jsonb;
BEGIN
 DELETE FROM public.meal_logs WHERE user_id=a;DELETE FROM public.daily_snapshots WHERE user_id=a;
 INSERT INTO public.user_progress(user_id,current_streak,longest_streak,last_active_date,xp_total)
 VALUES(a,4,9,(q->>'date')::date-3,90) ON CONFLICT(user_id) DO UPDATE
 SET current_streak=4,longest_streak=9,last_active_date=excluded.last_active_date,xp_total=90;
 c:=private.capture_mobile_clinical_day_close_at(a,(q->>'from')::date,NULL,q->>'zone',NULL);
 PERFORM m3b_cycle_test.ok(c#>>'{facts,disposition}'='ready','empty discovery still captures clinical inactivity authority');
 r:=private.apply_mobile_clinical_day_close_at(a,k,(q->>'from')::date,NULL,q->>'zone',c->>'context_hash','{"version":1,"kind":"reset"}',NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{result,kind}'='applied' AND (SELECT current_streak=0 AND longest_streak=9 AND xp_total=90
  FROM public.user_progress WHERE user_id=a),'guarded inactivity resets only the streak');
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(private.apply_mobile_clinical_day_close_at(a,k,(q->>'from')::date,NULL,q->>'zone',c->>'context_hash',
  '{"version":1,"kind":"reset"}',NULL)=r AND before_state=m3b_cycle_test.original_state(a),'reset replay adds no event or mutation');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3105);a uuid:=(q->>'user')::uuid;c jsonb;before_state jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);
 UPDATE public.user_profiles SET weight_kg=81 WHERE user_id=a;
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001','profile changes refuse whole close');
 PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a),'profile refusal leaves all rows intact');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
-- Validate the completed fixtures, then restore the writer's normal deferred
-- receipt/event FK ordering before creating the next historical FULL.
SET CONSTRAINTS ALL DEFERRED;
-- A signed fractional credit is a valid output of the existing pure core.
-- This is a transport shape test; the actual formula remains a BFF/core gate.
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3106);a uuid:=(q->>'user')::uuid;c jsonb;e jsonb;r jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);
 e:=jsonb_set(jsonb_set(m3b_cycle_test.close_effect(q),'{blockCredit}','-100.25'),'{progress,deficitBlock}','0');
 r:=private.apply_mobile_clinical_day_close_at(a,gen_random_uuid(),(q->>'from')::date,(q->>'date')::date,
  q->>'zone',c->>'context_hash',e,NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{result,detail,blockCredit}'='-100.25','signed fractional core credit survives transport without truncation');
END $$;

-- Force the real delegate to fail after the preliminary dayFields UPDATE.
-- Both test triggers are transaction-local and never installed by a migration.
CREATE FUNCTION m3b_cycle_test.fail_progress_close() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.user_id=m3b_cycle_test.uid(3107) AND NEW.xp_total=15 THEN
  PERFORM m3b_cycle_test.ok((SELECT calories_consumed=1600 AND NOT day_closed FROM public.daily_snapshots
   WHERE user_id=NEW.user_id),'failure injection observes the preliminary write before finalization');
  RAISE EXCEPTION 'synthetic delegate failure' USING ERRCODE='40001';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER m3b_close_progress_fault BEFORE INSERT OR UPDATE ON public.user_progress
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_progress_close();
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3107);a uuid:=(q->>'user')::uuid;c jsonb;b jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001','delegate failure propagates');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'delegate failure rolls back dayFields, progress, events and acknowledgement');
END $$;
CREATE FUNCTION m3b_cycle_test.fail_close_telemetry() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.user_id=m3b_cycle_test.uid(3108) AND NEW.event='daily_closer.completed' THEN
  PERFORM m3b_cycle_test.ok((SELECT day_closed FROM public.daily_snapshots WHERE user_id=NEW.user_id)
   AND (SELECT xp_total=15 FROM public.user_progress WHERE user_id=NEW.user_id),'telemetry failure occurs after actual finalization');
  RAISE EXCEPTION 'synthetic telemetry failure' USING ERRCODE='40001';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER m3b_close_telemetry_fault BEFORE INSERT ON public.product_events
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_close_telemetry();
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3108);a uuid:=(q->>'user')::uuid;c jsonb;b jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001','telemetry failure propagates');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'failure after finalization rolls back the whole close');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3109);a uuid:=(q->>'user')::uuid;c jsonb;b jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);
 INSERT INTO public.global_config(key,value) VALUES('calc.close_fixture',jsonb_build_object('value',1));
 b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001','fresh calc configuration invalidates the old close');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'configuration refusal has no effects');
 DELETE FROM public.global_config WHERE key='calc.close_fixture';
 c:=m3b_cycle_test.close_capture(q);
 PERFORM public.reset_user_conversation_atomic(a,true);b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'40001','signup epoch reset invalidates unapplied close');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'epoch refusal preserves reset state');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3110);a uuid:=(q->>'user')::uuid;c jsonb;b jsonb;e jsonb;
BEGIN
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 c:=m3b_cycle_test.close_capture(q);b:=m3b_cycle_test.original_state(a);
 e:=jsonb_set(m3b_cycle_test.close_effect(q),'{fields,calories_target}','2100');
 e:=jsonb_set(e,'{dailyBalance}','-500');
 e:=jsonb_set(e,'{telemetry,0,properties,calories_target}','2100');
 PERFORM m3b_cycle_test.throws(format('SELECT private.apply_mobile_clinical_day_close_at(%L,%L,%L,%L,%L,%L,%L,NULL)',
  a,gen_random_uuid(),q->>'from',q->>'date',q->>'zone',c->>'context_hash',e),'40001','risk cannot authorize a new calorie target');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'protected target refusal precedes every effect');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3111);a uuid:=(q->>'user')::uuid;c jsonb;b jsonb;
BEGIN
 DELETE FROM public.meal_logs WHERE user_id=a;DELETE FROM public.daily_snapshots WHERE user_id=a;
 INSERT INTO public.user_progress(user_id,current_streak,longest_streak,last_active_date,xp_total)
 VALUES(a,4,9,(q->>'date')::date-3,90);
 c:=private.capture_mobile_clinical_day_close_at(a,(q->>'from')::date,NULL,q->>'zone',NULL);
 INSERT INTO public.meal_logs(user_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at)
 VALUES(a,'almoco','new pending activity',100,50,0,0,0,((q->>'date')::date+time '12:00') AT TIME ZONE 'America/Sao_Paulo');
 b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.apply_mobile_clinical_day_close_at(%L,%L,%L,NULL,%L,%L,%L,NULL)',
  a,gen_random_uuid(),q->>'from',q->>'zone',c->>'context_hash','{"version":1,"kind":"reset"}'),'40001','new pending activity vetoes inactivity reset');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'reset refusal preserves streak and telemetry');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3112);a uuid:=(q->>'user')::uuid;other uuid:=m3b_cycle_test.seed(3113,NULL);b jsonb;
BEGIN
 UPDATE public.meal_logs SET user_id=other WHERE snapshot_id=(q->>'snapshot')::uuid;
 b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_capture(%L)',q),'40001','cross-owner snapshot membership cannot enter clinical context');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'foreign association refusal changes no rows');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3114);a uuid:=(q->>'user')::uuid;c jsonb;d date;seconds numeric;
BEGIN
 d:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
 c:=private.capture_mobile_clinical_day_close_at(a,(q->>'from')::date,(q->>'date')::date,q->>'zone',
  d::timestamp AT TIME ZONE 'America/Sao_Paulo');
 PERFORM m3b_cycle_test.ok((c#>>'{facts,calendar,latest_closable_date}')::date=d-2 AND
  c#>>'{facts,disposition}'='not_closable_yet','midnight does not prematurely close yesterday');
 c:=private.capture_mobile_clinical_day_close_at(a,(q->>'from')::date,(q->>'date')::date,q->>'zone',
  (d+time '00:30') AT TIME ZONE 'America/Sao_Paulo');
 PERFORM m3b_cycle_test.ok((c#>>'{facts,calendar,latest_closable_date}')::date=d-1 AND
  c#>>'{facts,calendar,late}'='false','00:30 admits yesterday without late classification');
 c:=private.capture_mobile_clinical_day_close_at(a,(q->>'from')::date,(q->>'date')::date,q->>'zone',
  (d+time '05:00') AT TIME ZONE 'America/Sao_Paulo');
 PERFORM m3b_cycle_test.ok(c#>>'{facts,calendar,late}'='true','05:00 moves yesterday into late target preservation');
 UPDATE public.users SET timezone='America/New_York' WHERE id=a;
 c:=private.capture_mobile_clinical_day_close_at(a,'2026-10-20','2026-11-01','America/New_York','2026-11-02T12:00Z');
 seconds:=extract(epoch FROM (c#>>'{facts,calendar,day_end}')::timestamptz-(c#>>'{facts,calendar,day_start}')::timestamptz);
 PERFORM m3b_cycle_test.ok(seconds=90000,'historical civil day uses the actual 25-hour DST interval');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3115);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;k uuid:=gen_random_uuid();
BEGIN
 c:=m3b_cycle_test.close_capture(q);r:=m3b_cycle_test.close_apply(q,c,k);
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_day_close_keys SET result=%L WHERE user_id=%L',r,a),'55000','original acknowledgement cannot be updated');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_day_close_keys WHERE user_id=%L',a),'55000','original acknowledgement cannot be directly deleted');
 -- Existing signup source FK requires the established ordered local purge.
 -- The new journal itself is removed only by the final parent cascade.
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_close_keys WHERE user_id=a),'established ordered user purge cascades the new acknowledgement');
END $$;
DO $$
DECLARE role_name text;fn text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH fn IN ARRAY ARRAY['public.capture_mobile_clinical_day_close(uuid,date,date,text)',
   'public.apply_mobile_clinical_day_close(uuid,uuid,date,date,text,text,jsonb)',
   'public.get_mobile_clinical_day_close_receipt(uuid,uuid)'] LOOP
   PERFORM m3b_cycle_test.ok(NOT has_function_privilege(role_name,fn,'EXECUTE'),'client role cannot call '||fn);
  END LOOP;
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.mobile_clinical_day_close_keys'::regclass)
  AND NOT has_table_privilege('service_role','private.mobile_clinical_day_close_keys','SELECT'),
  'journal is RLS-protected and private even from direct service-role reads');
 PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role',
  'private.apply_mobile_clinical_day_close_at(uuid,uuid,date,date,text,text,jsonb,timestamptz)','EXECUTE'),
  'backend cannot bypass public wrapper to provide a private clock');
END $$;
DO $$
DECLARE denied boolean;r jsonb;role_name text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  denied:=false;EXECUTE format('SET LOCAL ROLE %I',role_name);
  BEGIN PERFORM public.get_mobile_clinical_day_close_receipt('b3b01000-0000-4000-8000-000000003110',gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(denied,'actual client role cannot execute the receipt RPC');
 END LOOP;
 EXECUTE 'SET LOCAL ROLE service_role';
 r:=public.get_mobile_clinical_day_close_receipt('b3b01000-0000-4000-8000-000000003110',gen_random_uuid());
 denied:=false;
 BEGIN PERFORM private.capture_mobile_clinical_day_close_at('b3b01000-0000-4000-8000-000000003110',
  current_date-10,current_date-1,'America/Sao_Paulo',NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(r IS NULL AND denied,'actual backend reaches wrapper but cannot invoke private clock helper');
 PERFORM set_config('request.jwt.claim','{"role":"authenticated"}',true);denied:=false;
 BEGIN PERFORM public.get_mobile_clinical_day_close_receipt('b3b01000-0000-4000-8000-000000003110',gen_random_uuid());
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claim','{"role":"service_role"}',true);
 PERFORM m3b_cycle_test.ok(denied,'definer refuses an untrusted JWT claim independently of SQL caller');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3116);a uuid:=(q->>'user')::uuid;c jsonb;e jsonb;r jsonb;
BEGIN
 UPDATE public.daily_snapshots SET calories_target=NULL,protein_target=NULL WHERE user_id=a;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 c:=m3b_cycle_test.close_capture(q);e:=m3b_cycle_test.close_effect(q);
 e:=jsonb_set(jsonb_set(e,'{fields,calories_target}','null'),'{fields,protein_target}','null');
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{dailyBalance}','1600'),'{blockCredit}','0'),'{progress,deficitBlock}','0');
 e:=jsonb_set(e,'{telemetry,0,properties,calories_target}','null');
 r:=private.apply_mobile_clinical_day_close_at(a,gen_random_uuid(),(q->>'from')::date,(q->>'date')::date,
  q->>'zone',c->>'context_hash',e,NULL);
 PERFORM m3b_cycle_test.ok((SELECT day_closed AND calories_target IS NULL AND protein_target IS NULL AND xp_earned=15
  FROM public.daily_snapshots WHERE user_id=a),'clinical hold preserves absent targets and the existing supplied XP bonus');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3117);a uuid:=(q->>'user')::uuid;c jsonb;e jsonb;b jsonb;r jsonb;
BEGIN
 UPDATE public.daily_snapshots SET calories_target=2001 WHERE user_id=a;
 UPDATE public.daily_snapshots SET calories_target=2000 WHERE user_id=a;
 INSERT INTO public.user_progress(user_id,xp_total,blocks_completed,deficit_block) VALUES(a,90,1,400);
 c:=m3b_cycle_test.close_capture(q);b:=m3b_cycle_test.original_state(a);e:=m3b_cycle_test.close_effect(q);
 PERFORM m3b_cycle_test.ok(c#>'{facts,target_authority,applied_target}'='null'::jsonb,
  'editing and restoring calories does not recreate historical deficit proof');
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{progress,xpTotal}','105'),'{progress,blocksCompleted}','1'),
  '{telemetry,0,properties,blocks_completed}','1');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L,%L,%L)',q,c,gen_random_uuid(),e),
  '40001','unknown historical deficit cannot accept a supplied credit');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'unknown-deficit credit refusal leaves the whole state intact');
 e:=jsonb_set(e,'{blockCredit}','0');r:=m3b_cycle_test.close_apply(q,c,gen_random_uuid(),e);
 PERFORM m3b_cycle_test.ok(r#>>'{result,detail,blockCreditStatus}'='preserved_unknown'
  AND (SELECT xp_total=105 AND blocks_completed=1 AND deficit_block=400 FROM public.user_progress WHERE user_id=a)
  AND (SELECT day_closed FROM public.daily_snapshots WHERE user_id=a),
  'unknown deficit closes records and XP while preserving the previous block');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(3118);a uuid:=(q->>'user')::uuid;c jsonb;e jsonb;b jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);b:=m3b_cycle_test.original_state(a);e:=m3b_cycle_test.close_effect(q);
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{fields,calories_target}','2001'),'{dailyBalance}','-401'),
  '{telemetry,0,properties,calories_target}','2001');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L,%L,%L)',q,c,gen_random_uuid(),e),
  '40001','ordinary close cannot replace a historical target even without a clinical hold');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'historical target refusal precedes every write');
END $$;
SELECT m3b_cycle_test.ok((SELECT bool_and(proconfig @> ARRAY['lock_timeout=2s']) FROM pg_proc
 WHERE oid IN('public.capture_mobile_clinical_day_close(uuid,date,date,text)'::regprocedure,
 'public.apply_mobile_clinical_day_close(uuid,uuid,date,date,text,text,jsonb)'::regprocedure)),
 'public owner waits have the existing two-second mobile timeout');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

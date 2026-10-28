-- Actual owned PostgreSQL only. Synthetic trusted close effects; no provider.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
DO $$ BEGIN
 IF to_regclass('private.mobile_clinical_closed_day_evidence') IS NULL
  OR to_regprocedure('public.get_mobile_clinical_flow_period(uuid,text,date,date)') IS NULL THEN
  RAISE EXCEPTION 'M3B_ASSERT:exact_closed_day_evidence_and_period_missing';END IF;
END $$;
\ir fixtures/mobile_clinical_day_close_fixture.sql
CREATE FUNCTION m3b_cycle_test.period(q jsonb) RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT public.get_mobile_clinical_flow_period((q->>'user')::uuid,'semana',
  (clock_timestamp() AT TIME ZONE (q->>'zone'))::date-6,
  (clock_timestamp() AT TIME ZONE (q->>'zone'))::date)
$$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(6400);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;k uuid:=gen_random_uuid();
 packet jsonb;b jsonb;proof jsonb;s uuid:=(q->>'snapshot')::uuid;
BEGIN
 c:=m3b_cycle_test.close_capture(q);r:=m3b_cycle_test.close_apply(q,c,k);
 SELECT to_jsonb(e) INTO proof FROM private.mobile_clinical_closed_day_evidence e WHERE snapshot_id=s;
 PERFORM m3b_cycle_test.ok(proof->>'user_id'=a::text AND proof->>'operation_key'=k::text
  AND proof->>'context_hash'=c->>'context_hash' AND proof#>>'{snapshot_binding,day_closed}'='true',
  'close writes exact final snapshot proof in the original transaction');
 PERFORM m3b_cycle_test.ok(proof#>>'{snapshot_binding,closed_at}' IS NOT NULL
  AND proof->>'signup_epoch'=c#>>'{facts,current,epoch}'
  AND proof->>'signup_generation'=c#>>'{facts,current,signup_generation}',
  'proof records final close timestamp and original identity generation');
 b:=m3b_cycle_test.original_state(a);packet:=m3b_cycle_test.period(q);
 PERFORM m3b_cycle_test.ok(packet#>'{rows,0}'=jsonb_build_object('date',q->'date',
  'calories_consumed',1600,'protein_g',100,'day_status','complete','daily_balance',-400,'balance_proven',true),
  'certified historical net arithmetic comes from the exact closed snapshot');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a)
  AND (SELECT count(*)=1 FROM private.mobile_clinical_closed_day_evidence WHERE user_id=a),
  'period is read only and never closes or backfills a day');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.close_apply(q,c,k)=r
  AND (SELECT count(*)=1 FROM private.mobile_clinical_closed_day_evidence WHERE user_id=a),
  'original close replay creates no second proof');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_closed_day_evidence WHERE snapshot_id=%L',s),
  '55000','cannot erase proof for a surviving snapshot');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_closed_day_evidence SET context_hash=%L WHERE snapshot_id=%L',repeat('f',64),s),
  '55000','cannot relabel original closing evidence');
 UPDATE public.daily_snapshots SET calories_consumed=1601 WHERE id=s;
 packet:=m3b_cycle_test.period(q);
 PERFORM m3b_cycle_test.ok(packet#>>'{rows,0,balance_proven}'='false' AND packet#>'{rows,0,daily_balance}'='null',
  'a changed aggregate preserves consumption but revokes historical balance proof');
 UPDATE public.daily_snapshots SET calories_consumed=1600,calories_target=2001 WHERE id=s;
 UPDATE public.daily_snapshots SET calories_target=2000 WHERE id=s;
 packet:=m3b_cycle_test.period(q);
 PERFORM m3b_cycle_test.ok(packet#>>'{rows,0,balance_proven}'='false',
  'changed-and-restored target revision cannot revive close proof');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_closed_day_evidence WHERE user_id=a)
  AND m3b_cycle_test.close_apply(q,c,k)=r
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_closed_day_evidence WHERE user_id=a),
  'reset cascades snapshot proof while original acknowledgement replays without backfill');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(6401);a uuid:=(q->>'user')::uuid;packet jsonb;
 other jsonb:=m3b_cycle_test.close_seed(6402);
BEGIN
 UPDATE public.daily_snapshots SET calories_consumed=1600,protein_g=100,day_closed=true,
  closed_at=clock_timestamp(),day_status='complete' WHERE user_id=a;
 PERFORM m3b_cycle_test.close_apply(other,m3b_cycle_test.close_capture(other));
 packet:=m3b_cycle_test.period(q);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(packet->'rows')=1 AND packet#>>'{rows,0,calories_consumed}'='1600'
  AND packet#>>'{rows,0,day_status}'='complete' AND packet#>>'{rows,0,balance_proven}'='false'
  AND packet#>'{rows,0,daily_balance}'='null',
  'legacy closed days keep intake and completeness without invented proof or foreign rows');
 UPDATE public.users SET timezone='America/New_York' WHERE id=a;
 packet:=private.get_mobile_clinical_flow_period_at(a,'semana','2026-10-26','2026-11-01','2026-11-02T04:30:00Z');
 PERFORM m3b_cycle_test.ok(packet->>'from'='2026-10-26' AND packet->>'to'='2026-11-01',
  'SQL civil window follows the actual DST timezone and server observation');
 PERFORM m3b_cycle_test.throws(format('SELECT private.get_mobile_clinical_flow_period_at(%L,%L,%L,%L,%L)',
  a,'semana','2026-10-26','2026-11-01','2026-11-02T05:00:00Z'),'40001',
  'crossing the civil boundary refuses stale expected window');
 packet:=private.get_mobile_clinical_flow_period_at(a,'mes','2028-02-01','2028-03-01','2028-03-01T18:00:00Z');
 PERFORM m3b_cycle_test.ok(packet->>'from'='2028-02-01' AND packet->>'to'='2028-03-01',
  'month is the approved thirty-day window including a leap day');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_flow_period(%L,%L,%L,%L)',
  a,'year','2026-01-01','2026-12-31'),'22023','unbounded history is refused');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(6403);a uuid:=(q->>'user')::uuid;c jsonb;e jsonb;r jsonb;packet jsonb;
BEGIN
 INSERT INTO public.user_progress(user_id,xp_total,blocks_completed,deficit_block) VALUES(a,0,0,1234);
 UPDATE public.daily_snapshots SET calories_target=2001 WHERE user_id=a;
 UPDATE public.daily_snapshots SET calories_target=2000 WHERE user_id=a;
 c:=m3b_cycle_test.close_capture(q);
 e:=jsonb_set(jsonb_set(m3b_cycle_test.close_effect(q),'{blockCredit}','0'),'{progress,deficitBlock}','1234');
 r:=m3b_cycle_test.close_apply(q,c,gen_random_uuid(),e);packet:=m3b_cycle_test.period(q);
 PERFORM m3b_cycle_test.ok(r#>>'{result,detail,blockCreditStatus}'='preserved_unknown'
  AND r#>>'{result,detail,blockCredit}'='0'
  AND (SELECT deficit_block=1234 AND xp_total=15 FROM public.user_progress WHERE user_id=a),
  'unknown historical DD closes records and XP with zero credit or debit to the block');
 PERFORM m3b_cycle_test.ok(packet#>>'{rows,0,balance_proven}'='true' AND packet#>>'{rows,0,daily_balance}'='-400',
  'proven stored-target arithmetic does not require or invent a physiological DD');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(6404);a uuid:=(q->>'user')::uuid;c jsonb;e jsonb;packet jsonb;
BEGIN
 UPDATE public.daily_snapshots SET calories_target=NULL WHERE user_id=a;
 c:=m3b_cycle_test.close_capture(q);e:=m3b_cycle_test.close_effect(q);
 e:=jsonb_set(jsonb_set(e,'{fields,calories_target}','null'),'{telemetry,0,properties,calories_target}','null');
 e:=jsonb_set(jsonb_set(jsonb_set(e,'{dailyBalance}','1600'),'{blockCredit}','0'),'{progress,deficitBlock}','0');
 PERFORM m3b_cycle_test.close_apply(q,c,gen_random_uuid(),e);packet:=m3b_cycle_test.period(q);
 PERFORM m3b_cycle_test.ok(packet#>>'{rows,0,balance_proven}'='false'
  AND packet#>'{rows,0,daily_balance}'='null' AND packet#>>'{rows,0,calories_consumed}'='1600',
  'NULL target never becomes a proven zero-calorie target through the generated balance');
END $$;
CREATE FUNCTION m3b_cycle_test.refuse_period_key() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN IF NEW.user_id='b3b01000-0000-4000-8000-000000006405' THEN
  RAISE EXCEPTION 'synthetic final receipt refusal';END IF;RETURN NEW;END $$;
CREATE TRIGGER qa_period_refuse_key BEFORE INSERT ON private.mobile_clinical_day_close_keys
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.refuse_period_key();
DO $$
DECLARE q jsonb:=m3b_cycle_test.close_seed(6405);a uuid:=(q->>'user')::uuid;c jsonb;b jsonb;
BEGIN
 c:=m3b_cycle_test.close_capture(q);b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.close_apply(%L,%L)',q,c),'P0001',
  'failure of final receipt rolls back day, progress, telemetry and close proof together');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_closed_day_evidence WHERE user_id=a),
  'no partial proof survives transaction refusal');
END $$;
DO $$
DECLARE role_name text;denied boolean;packet jsonb;a uuid:='b3b01000-0000-4000-8000-000000006403';
 today date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 PERFORM m3b_cycle_test.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.mobile_clinical_closed_day_evidence'::regclass),
  'close evidence has private RLS defense in depth');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(role_name,'private.mobile_clinical_closed_day_evidence','SELECT')
   AND NOT has_function_privilege(role_name,'private.get_mobile_clinical_flow_period_at(uuid,text,date,date,timestamptz)','EXECUTE'),
   'no role has direct private proof or caller-clock access');
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  EXECUTE format('SET LOCAL ROLE %I',role_name);denied:=false;
  BEGIN PERFORM public.get_mobile_clinical_flow_period(a,'semana',today-6,today);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(denied,'actual client role is denied historical backend RPC');
 END LOOP;
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.get_mobile_clinical_flow_period(a,'semana',today-6,today);
 EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(jsonb_array_length(packet->'rows')=1,
  'actual backend role reads only the bounded public projection');
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_closed_day_evidence WHERE user_id=a),
  'established ordered account purge cascades close proof');
END $$;
ROLLBACK;

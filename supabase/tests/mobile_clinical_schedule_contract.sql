-- SQL journal accepts exactly the canonical frozen schedule from core.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.mobile_clinical_schedule_valid(jsonb)') IS NOT NULL,
 'canonical schedule journal validator exists');
DO $$
DECLARE n5 jsonb:='{"version":1,"kind":"recomp_to_maintenance","state":"running","startDate":"2026-10-25","startTargetKcal":2000,"maintenanceTargetKcal":2350,"plannedEndDate":"2026-11-15"}';
 n18 jsonb:='{"version":1,"kind":"gain_exit","state":"running","startDate":"2026-10-25","startTargetKcal":2650,"maintenanceTargetKcal":2350,"plannedEndDate":"2026-11-08"}';
 item record;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  (n5,true,'n5 freezes C plus 21 days for a 350 kcal gap'),
  (n18,true,'n18 freezes E plus 14 days for a 300 kcal gap'),
  (jsonb_set(n5,'{state}','"suspended"'),true,'suspended preserves the frozen schedule'),
  (jsonb_set(n18,'{state}','"completed"'),false,'terminal application state is not a replacement frozen schedule'),
  (n5||'{"unapproved":true}',false,'extra fields are not clinical authority'),
  (n5-'maintenanceTargetKcal',false,'missing frozen target is refused'),
  (jsonb_set(n5,'{version}','2'),false,'unknown formula version is refused'),
  (jsonb_set(n5,'{kind}','"arbitrary"'),false,'unknown schedule kind is refused'),
  (jsonb_set(n5,'{state}','"paused"'),false,'unknown activation state is refused'),
  (jsonb_set(n5,'{startTargetKcal}','"2000"'),false,'string kcal is refused'),
  (jsonb_set(n5,'{startTargetKcal}','2000.5'),false,'fractional kcal is refused'),
  (jsonb_set(n5,'{startTargetKcal}','0'),false,'zero kcal is refused'),
  (jsonb_set(n5,'{maintenanceTargetKcal}','-1'),false,'negative maintenance kcal is refused'),
  (jsonb_set(n5,'{maintenanceTargetKcal}','9007199254740992'),false,'unsafe integer kcal is refused'),
  (jsonb_set(n5,'{startDate}','"2026-02-30"'),false,'invalid civil date is refused'),
  (jsonb_set(n5,'{startDate}','"2026-1-1"'),false,'noncanonical date is refused'),
  (jsonb_set(n5,'{plannedEndDate}','"2026-11-16"'),false,'a supplied later R date cannot change the frozen end'),
  (jsonb_set(n18,'{plannedEndDate}','"2026-11-01"'),false,'an early frozen end is refused'),
  (jsonb_set(jsonb_set(n5,'{maintenanceTargetKcal}','2050'),'{plannedEndDate}','"2026-10-25"'),true,'first n5 step may finish on C'),
  (jsonb_set(jsonb_set(n18,'{startTargetKcal}','2300'),'{plannedEndDate}','"2026-10-25"'),true,'G below M finishes on E'),
  ('[]'::jsonb,false,'array is not a schedule'),
  ('true'::jsonb,false,'boolean is not a schedule')
 ) AS checks(schedule,expected,label) LOOP
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_schedule_valid(item.schedule) IS NOT DISTINCT FROM item.expected,item.label);
 END LOOP;
END $$;
ROLLBACK;

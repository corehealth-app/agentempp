\set ON_ERROR_STOP on
-- Local rollback-only guard test. The reviewed wrapper installs only the two
-- literal projection functions. These sentinel UUIDs do not assert real Y/L.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL search_path=pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL check_function_bodies=on;
-- P5_RR_ASSERTIONS_BEGIN
SET LOCAL ROLE service_role;
DO $rr$
BEGIN
 IF current_setting('transaction_isolation')<>'repeatable read'
  OR current_setting('check_function_bodies')<>'on'
 THEN RAISE EXCEPTION 'P5_RR_SETUP_ISOLATION_OR_VALIDATOR';END IF;
 BEGIN
  PERFORM public.get_mobile_strength_week_projection(
   'c59d3800-0000-4000-8000-000000000001'::uuid,
   'c59d3800-0000-4000-8000-000000000002'::uuid,
   'c59d3800-0000-4000-8000-000000000003'::uuid);
  RAISE EXCEPTION 'P5_RR_GUARD_NOT_RAISED';
 EXCEPTION WHEN SQLSTATE '22023' THEN
  IF SQLERRM<>'strength_week_projection_requires_read_committed' THEN RAISE;END IF;
 END;
 RAISE NOTICE 'P5_RR_PUBLIC_LITERAL_GUARD_22023_EXACT';
END $rr$;
RESET ROLE;
-- P5_RR_ASSERTIONS_END
ROLLBACK;

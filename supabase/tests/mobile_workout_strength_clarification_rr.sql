-- Real REPEATABLE READ transaction, no producer. Caller installs candidate/support
-- in that transaction and owns ROLLBACK. No simulated GUC isolation or guard change.
\set ON_ERROR_STOP on
SET LOCAL ROLE postgres;
DO $rr$
DECLARE r jsonb;u uuid:=c59s17d_fixture.uid(3101);sql text;prefix text;BEGIN
 IF current_setting('transaction_isolation')<>'repeatable read'
  OR to_regprocedure('public.get_mobile_workout_strength_clarification(uuid,uuid)') IS NULL
  OR to_regprocedure('public.answer_mobile_workout_strength_clarification(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL
 THEN RAISE EXCEPTION 'P10B_SETUP_CANDIDATE_OR_RR_REQUIRED';END IF;
 FOR prefix,sql IN SELECT * FROM (VALUES
  ('reader',c59p10b_fixture.get_sql(u,c59s17d_fixture.uid(3199))),
  ('answer',c59p10b_fixture.answer_sql(u,c59s17d_fixture.uid(3198),c59s17d_fixture.uid(3199),0,c59s17d_fixture.uid(3197),'yes','p10b-rr'))
 ) AS commands(prefix,sql) LOOP
  r:=c59s17d_fixture.attempt(sql);
  SET LOCAL ROLE postgres;
  PERFORM c59p10b_fixture.ok(r->'ok'='false'::jsonb AND r->>'sqlstate'='22023'
   AND r->>'message'='workout_strength_requires_read_committed',prefix||'_real_rr_rejected');
 END LOOP;
 r:=c59s17d_fixture.attempt('SELECT public.get_mobile_workout_strength_clarification(NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='22023' AND r->>'message'='invalid_workout_strength_input','reader_args_before_rr');
 r:=c59s17d_fixture.attempt('SELECT public.answer_mobile_workout_strength_clarification(NULL,NULL,NULL,NULL,NULL,NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='22023' AND r->>'message'='invalid_workout_strength_input','answer_args_before_rr');
END $rr$;
SAVEPOINT untrusted_claims;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
DO $guard_priority$
DECLARE r jsonb;BEGIN
 r:=c59s17d_fixture.attempt('SELECT public.get_mobile_workout_strength_clarification(NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='42501' AND r->>'message'='trusted backend role required','reader_guard_before_args_rr');
 r:=c59s17d_fixture.attempt('SELECT public.answer_mobile_workout_strength_clarification(NULL,NULL,NULL,NULL,NULL,NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='42501' AND r->>'message'='trusted backend role required','answer_guard_before_args_rr');
END $guard_priority$;
ROLLBACK TO untrusted_claims;
RELEASE untrusted_claims;

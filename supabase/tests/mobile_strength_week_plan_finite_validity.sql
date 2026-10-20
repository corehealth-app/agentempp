\set ON_ERROR_STOP on
-- Real signup and confirmed Flow plan, then an official future-week QA observation.
-- This tests private deterministic observation, not the public wall clock or HTTP.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=pg_catalog;SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='3s';
DO $target$ BEGIN
 IF session_user<>'c5_local_admin' OR current_user<>'c5_local_admin'
  OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
  OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
  OR current_setting('listen_addresses')<>'' OR inet_server_addr() IS NOT NULL
  OR to_regprocedure('private.capture_mobile_plan_strength_week_source(uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'C59P2_SETUP_WRONG_TARGET_OR_MISSING_P1'; END IF;
END $target$;
\ir fixtures/mobile_strength_week_plan_confirmation_fixture.sql
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE FUNCTION c59_plan_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
REVOKE ALL ON FUNCTION c59_plan_fixture.state(uuid) FROM PUBLIC,anon,authenticated,service_role;
DO $real_plan$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000901';
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"seg","focus":"full body","exercises":[]},{"day":"qua","focus":"full body","exercises":[]},{"day":"sex","focus":"full body","exercises":[]}]}';
 d jsonb;answer jsonb;valid timestamptz;plan public.training_plans%ROWTYPE;
 src private.strength_week_source_versions%ROWTYPE;freq private.strength_week_source_versions%ROWTYPE;
 receipt private.mobile_signup_strength_completion_receipts%ROWTYPE;g uuid;monday_at timestamptz;at timestamptz;
BEGIN
 SELECT * INTO STRICT receipt FROM private.mobile_signup_strength_completion_receipts WHERE user_id=u;
 g:=receipt.generation;
 SELECT * INTO STRICT freq FROM private.strength_week_source_versions WHERE user_id=u
  AND source_version_id=receipt.frequency_source_version_id AND generation=g;
 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'P2-real-finite-flow-create-20261020');
 at:=clock_timestamp();valid:=at+interval '42 days';
 answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,valid,'P2-real-finite-flow-confirm');
 SET LOCAL ROLE postgres;
 SELECT * INTO STRICT plan FROM public.training_plans WHERE id=(answer->>'confirmed_plan_id')::uuid AND user_id=u;
 SELECT * INTO STRICT src FROM private.strength_week_source_versions WHERE user_id=u
  AND generation=g AND source_kind='accepted_plan';
 monday_at:=src.effective_week_start::timestamp AT TIME ZONE src.observed_timezone;
 IF receipt.outcome IS DISTINCT FROM 'first_fresh' OR freq.fact IS DISTINCT FROM 'value'
  OR freq.source_kind IS DISTINCT FROM 'informed_frequency' OR freq.planned_days IS DISTINCT FROM 4::smallint
  OR freq.source_valid_until IS NOT NULL
  OR answer->>'status' IS DISTINCT FROM 'confirmed' OR (answer->>'already_confirmed')::boolean IS NOT FALSE
  OR plan.active IS NOT TRUE OR plan.days_per_week IS DISTINCT FROM 3 OR plan.generated_by IS DISTINCT FROM 'flow_draft'
  OR plan.valid_until IS DISTINCT FROM valid OR valid-at IS DISTINCT FROM interval '42 days'
  OR src.source_entity_id IS DISTINCT FROM plan.id OR src.planned_days IS DISTINCT FROM 3::smallint
  OR src.fact IS DISTINCT FROM 'value' OR src.source_valid_until IS DISTINCT FROM valid
  OR src.operation_namespace IS DISTINCT FROM 'mobile_plan_confirmation_v1'
  OR src.operation_key IS DISTINCT FROM (d->>'id')||':v:1'
  OR src.observed_at<receipt.recorded_at OR src.observed_at>clock_timestamp()
  OR src.observed_timezone IS DISTINCT FROM 'UTC' OR freq.observed_timezone IS DISTINCT FROM 'UTC'
  OR src.effective_week_start IS DISTINCT FROM (date_trunc('week',src.observed_at AT TIME ZONE 'UTC')::date+7)
  OR src.effective_week_start IS DISTINCT FROM freq.effective_week_start
  OR NOT isfinite(valid) OR valid<monday_at OR NOT isfinite(monday_at)
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=src.observed_timezone)
  OR EXISTS(SELECT 1 FROM private.strength_week_targets WHERE user_id=u)
  OR (SELECT count(*) FROM private.strength_week_source_versions WHERE user_id=u)<>2
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e
   WHERE e.user_id=u AND e.epoch=receipt.epoch AND e.current_lifecycle_key IS NULL)
  OR NOT EXISTS(SELECT 1 FROM private.strength_week_scopes x WHERE x.user_id=u AND x.generation=g
   AND x.closed_at IS NULL AND x.open_operation_namespace='mobile_signup_completion_v1'
   AND x.open_operation_key=receipt.admission_id::text)
  OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u)
  OR EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u)
 THEN RAISE EXCEPTION 'C59P2_SETUP_REAL_42_DAY_SOURCE_UNPROVED'; END IF;
 INSERT INTO c59_plan_fixture.context(key,value) VALUES
  ('p2_plan_source',to_jsonb(src)),('p2_frequency_source',to_jsonb(freq)),
  ('p2_monday_at',to_jsonb(monday_at)),('p2_observed_at',to_jsonb(monday_at+interval '12 hours')),
  ('p2_state_before_read',c59_plan_fixture.state(u));
 RAISE NOTICE 'C59P2_SETUP_REAL_CONFIRMED_42_DAY_SOURCE';
END $real_plan$;

CREATE FUNCTION c59_plan_fixture.assert_real_finite_plan() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $finite$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000901';
 src private.strength_week_source_versions%ROWTYPE;freq private.strength_week_source_versions%ROWTYPE;
 baseline jsonb;r jsonb;freeze_result jsonb;read_after jsonb;before_winner_read jsonb;proposal jsonb;at timestamptz;monday_at timestamptz;
BEGIN
 SELECT (jsonb_populate_record(NULL::private.strength_week_source_versions,value)).* INTO STRICT src
  FROM c59_plan_fixture.context WHERE key='p2_plan_source';
 SELECT (jsonb_populate_record(NULL::private.strength_week_source_versions,value)).* INTO STRICT freq
  FROM c59_plan_fixture.context WHERE key='p2_frequency_source';
 SELECT value INTO STRICT baseline FROM c59_plan_fixture.context WHERE key='p2_state_before_read';
 SELECT (value#>>'{}')::timestamptz INTO STRICT at FROM c59_plan_fixture.context WHERE key='p2_observed_at';
 SELECT (value#>>'{}')::timestamptz INTO STRICT monday_at FROM c59_plan_fixture.context WHERE key='p2_monday_at';
 r:=private.get_mobile_strength_week_context_at(u,at);
 IF r->>'status' IS DISTINCT FROM 'ready' OR r#>>'{context,kind}' IS DISTINCT FROM 'source_facts' THEN
  RAISE EXCEPTION 'C59P2_REQUIRED_REAL_42_DAY_CONTEXT_READY' USING ERRCODE='P2R01',DETAIL=r::text;
 END IF;
 IF r#>>'{context,user_id}' IS DISTINCT FROM u::text OR r#>>'{context,generation}' IS DISTINCT FROM src.generation::text
  OR r#>>'{context,timezone}' IS DISTINCT FROM 'UTC'
  OR r#>>'{context,week_start}' IS DISTINCT FROM to_char(src.effective_week_start::timestamp,'YYYY-MM-DD')
  OR r#>>'{context,week_start_at}' IS DISTINCT FROM to_char(monday_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  OR r#>'{context,plan,receipt}' IS DISTINCT FROM private.strength_week_source_wire(src)
  OR r#>'{context,frequency,receipt}' IS DISTINCT FROM private.strength_week_source_wire(freq)
  OR r#>'{context,source_proof}' IS DISTINCT FROM private.strength_week_proof_wire(
   src.source_version_id,src.source_order,freq.source_version_id,freq.source_order)
  OR c59_plan_fixture.state(u) IS DISTINCT FROM baseline
 THEN RAISE EXCEPTION 'C59P2_FINITE_CONTEXT_PROOF_OR_READ_STATE_INVALID' USING ERRCODE='P2R02'; END IF;
 proposal:=jsonb_build_object('source','accepted_plan','planned_days',3,'source_key',src.source_version_id);
 freeze_result:=private.freeze_mobile_strength_week_target_at(u,src.generation,'UTC',src.effective_week_start,
  r#>'{context,source_proof}',proposal,at);
 IF freeze_result->>'status' IS DISTINCT FROM 'frozen' OR freeze_result#>>'{target,source}' IS DISTINCT FROM 'accepted_plan'
  OR freeze_result#>>'{target,planned_days}' IS DISTINCT FROM '3'
  OR freeze_result#>>'{target,source_key}' IS DISTINCT FROM src.source_version_id::text
  OR freeze_result#>'{target,source_proof}' IS DISTINCT FROM r#>'{context,source_proof}'
  OR (SELECT count(*) FROM private.strength_week_targets WHERE user_id=u)<>1
  OR c59_plan_fixture.state(u)-'private.strength_week_targets' IS DISTINCT FROM baseline-'private.strength_week_targets'
 THEN RAISE EXCEPTION 'C59P2_FINITE_REAL_FREEZE_INVALID' USING ERRCODE='P2R03'; END IF;
 before_winner_read:=c59_plan_fixture.state(u);
 read_after:=private.get_mobile_strength_week_context_at(u,at);
 IF read_after->>'status' IS DISTINCT FROM 'ready'
  OR read_after#>>'{context,kind}' IS DISTINCT FROM 'existing_target'
  OR read_after#>'{context,target}' IS DISTINCT FROM freeze_result->'target'
  OR c59_plan_fixture.state(u) IS DISTINCT FROM before_winner_read
 THEN RAISE EXCEPTION 'C59P2_FINITE_WINNER_NOT_PRESERVED' USING ERRCODE='P2R04'; END IF;
 RAISE NOTICE 'C59P2_REAL_FINITE_42_DAYS_READ_AND_FREEZE';
END $finite$;
REVOKE ALL ON FUNCTION c59_plan_fixture.assert_real_finite_plan() FROM PUBLIC,anon,authenticated,service_role;
SELECT c59_plan_fixture.assert_real_finite_plan();
ROLLBACK;

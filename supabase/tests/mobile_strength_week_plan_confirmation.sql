\set ON_ERROR_STOP on
-- Native local regression: real signup, real plan confirmations, rollback only.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='3s';
SET LOCAL search_path=pg_catalog;SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $target$ BEGIN
 IF session_user<>'c5_local_admin' OR current_user<>'c5_local_admin'
  OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
  OR inet_server_addr() IS NOT NULL OR current_setting('listen_addresses')<>''
  OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
  OR to_regprocedure('private.capture_mobile_plan_strength_week_source(uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_WRONG_TARGET_OR_UNAPPLIED_MIGRATION'; END IF;
END $target$;
\ir fixtures/mobile_strength_week_plan_confirmation_fixture.sql
SET LOCAL ROLE postgres;
SET LOCAL search_path=pg_catalog,public,private,pg_temp;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE FUNCTION c59_plan_fixture.assert_accepted_source(
 u uuid,d uuid,plan uuid,g uuid,valid timestamptz
) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $oracle$
DECLARE s private.strength_week_source_versions%ROWTYPE;draft public.plan_drafts%ROWTYPE;n integer;
BEGIN
 SELECT count(*) INTO n FROM private.strength_week_source_versions
  WHERE user_id=u AND generation=g AND source_kind='accepted_plan';
 IF n=0 THEN RAISE EXCEPTION 'C59PLAN_REQUIRED_ACCEPTED_SOURCE_MISSING'; END IF;
 IF n<>1 THEN RAISE EXCEPTION 'C59PLAN_REQUIRED_ACCEPTED_SOURCE_WRONG_COUNT'; END IF;
 SELECT * INTO STRICT s FROM private.strength_week_source_versions
  WHERE user_id=u AND generation=g AND source_kind='accepted_plan';
 SELECT * INTO STRICT draft FROM public.plan_drafts WHERE id=d AND user_id=u;
 IF s.fact IS DISTINCT FROM 'value' OR s.planned_days IS DISTINCT FROM 3::smallint
  OR s.source_entity_id IS DISTINCT FROM plan OR s.source_valid_until IS DISTINCT FROM valid
  OR s.operation_namespace IS DISTINCT FROM 'mobile_plan_confirmation_v1'
  OR s.operation_key IS DISTINCT FROM (d::text||':v:'||draft.payload_version::text)
  OR s.observed_at<draft.resolved_at OR s.observed_at>clock_timestamp()
  OR s.observed_timezone IS DISTINCT FROM 'UTC'
  OR s.effective_week_start IS DISTINCT FROM (date_trunc('week',s.observed_at AT TIME ZONE 'UTC')::date+7)
 THEN RAISE EXCEPTION 'C59PLAN_REQUIRED_ACCEPTED_SOURCE_WRONG_PROOF'; END IF;
END $oracle$;
REVOKE ALL ON FUNCTION c59_plan_fixture.assert_accepted_source(uuid,uuid,uuid,uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;

DO $controls$
DECLARE
 a constant uuid:='c59d2c00-0000-4000-8000-000000000901';
 b constant uuid:='c59d2c00-0000-4000-8000-000000000902';
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"seg","focus":"full body","exercises":[]},{"day":"qua","focus":"full body","exercises":[]},{"day":"sex","focus":"full body","exercises":[]}]}';
 da jsonb;db jsonb;answer_a jsonb;answer_b jsonb;valid timestamptz;g uuid;frequency jsonb;receipt jsonb;
 pa public.training_plans%ROWTYPE;draft public.plan_drafts%ROWTYPE;binding_before regclass;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_plan_fixture.context WHERE key='generation';
 SELECT value INTO STRICT frequency FROM c59_plan_fixture.context WHERE key='source';
 SELECT value INTO STRICT receipt FROM c59_plan_fixture.context WHERE key='signup_receipt';
 binding_before:=to_regclass('private.strength_week_lifecycle_bindings');
 IF EXISTS(SELECT 1 FROM public.users WHERE id=b) THEN RAISE EXCEPTION 'C59PLAN_SETUP_NO_Y_OWNER_COLLISION'; END IF;
 INSERT INTO public.users(id,email,wpp,name,status,timezone,metadata)
  VALUES(b,NULL,NULL,'C59 plan without Y','active','UTC','{"qa_owner":"accepted-plan-no-y"}');
 SET LOCAL ROLE service_role;
 da:=public.create_plan_draft_atomic(a,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'plan-real-confirm-A-20261020');
 db:=public.create_plan_draft_atomic(b,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'plan-real-confirm-B-20261020');
 valid:=clock_timestamp()+interval '42 days';
 answer_a:=public.confirm_plan_draft_atomic(a,(da->>'id')::uuid,1,valid,'plan-real-confirm-key-A');
 answer_b:=public.confirm_plan_draft_atomic(b,(db->>'id')::uuid,1,NULL,'plan-real-confirm-key-B');
 RESET ROLE;
 IF answer_a->>'status' IS DISTINCT FROM 'confirmed' OR answer_b->>'status' IS DISTINCT FROM 'confirmed'
  OR (answer_a->>'already_confirmed')::boolean IS NOT FALSE
  OR (answer_b->>'already_confirmed')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_REAL_CONFIRMATION_FAILED'; END IF;
 SELECT * INTO STRICT pa FROM public.training_plans WHERE id=(answer_a->>'confirmed_plan_id')::uuid AND user_id=a;
 SELECT * INTO STRICT draft FROM public.plan_drafts WHERE id=(da->>'id')::uuid AND user_id=a;
 IF pa.active IS NOT TRUE OR pa.days_per_week IS DISTINCT FROM 3 OR pa.generated_by IS DISTINCT FROM 'flow_draft'
  OR pa.valid_until IS DISTINCT FROM valid OR draft.status IS DISTINCT FROM 'confirmed'
  OR draft.confirmed_plan_id IS DISTINCT FROM pa.id OR draft.resolved_at IS NULL
  OR draft.resolved_at IS DISTINCT FROM pa.generated_at
  OR (SELECT to_jsonb(v) FROM private.strength_week_source_versions v WHERE source_version_id=(frequency->>'source_version_id')::uuid)
    IS DISTINCT FROM frequency
  OR (SELECT to_jsonb(v) FROM private.mobile_signup_strength_completion_receipts v WHERE user_id=a)
    IS DISTINCT FROM receipt
  OR (SELECT generation FROM private.strength_week_scopes WHERE user_id=a AND closed_at IS NULL) IS DISTINCT FROM g
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e
    WHERE e.user_id=a AND e.epoch=(receipt->>'epoch')::uuid AND e.current_lifecycle_key IS NULL)
  OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id IN(a,b))
  OR EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id IN(a,b))
  OR EXISTS(SELECT 1 FROM public.messages WHERE user_id IN(a,b))
  OR EXISTS(SELECT 1 FROM public.users WHERE id IN(a,b) AND metadata ? 'training_reminders')
  OR to_regclass('private.strength_week_lifecycle_bindings') IS DISTINCT FROM binding_before
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_CONFIRMED_PLAN_OR_ORIGIN_PROOF_INVALID'; END IF;
 RAISE NOTICE 'C59PLAN_CONTROL_REAL_CONFIRMATION_Y_BEFORE_FIRST_WORKOUT';
 IF EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=b)
  OR EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=b)
  OR EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=b)
  OR NOT EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=b AND id=(answer_b->>'confirmed_plan_id')::uuid
    AND active AND valid_until IS NULL)
  OR NOT EXISTS(SELECT 1 FROM public.plan_drafts d WHERE d.id=(db->>'id')::uuid AND d.user_id=b
    AND d.status='confirmed' AND d.confirmed_plan_id=(answer_b->>'confirmed_plan_id')::uuid
    AND d.resolved_at IS NOT NULL)
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_CONFIRMATION_WITHOUT_Y_CHANGED_AUTHORITY'; END IF;
 RAISE NOTICE 'C59PLAN_CONTROL_WITHOUT_Y_CONFIRMS_WITHOUT_INVENTED_SOURCE';
 INSERT INTO c59_plan_fixture.context(key,value) VALUES
  ('draft_a',da),('answer_a',answer_a),('original_valid_until',to_jsonb(valid));
END $controls$;

DO $required$
DECLARE a constant uuid:='c59d2c00-0000-4000-8000-000000000901';g uuid;d uuid;p uuid;v timestamptz;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_plan_fixture.context WHERE key='generation';
 SELECT (value->>'id')::uuid INTO STRICT d FROM c59_plan_fixture.context WHERE key='draft_a';
 SELECT (value->>'confirmed_plan_id')::uuid INTO STRICT p FROM c59_plan_fixture.context WHERE key='answer_a';
 SELECT (value#>>'{}')::timestamptz INTO STRICT v FROM c59_plan_fixture.context WHERE key='original_valid_until';
 PERFORM c59_plan_fixture.assert_accepted_source(a,d,p,g,v);
 RAISE NOTICE 'C59PLAN_GREEN_REAL_ACCEPTED_PLAN_SOURCE';
END $required$;
\ir fixtures/mobile_strength_week_plan_confirmation_neighbors.sql
\ir fixtures/mobile_strength_week_plan_confirmation_lifecycle.sql
ROLLBACK;

\set ON_ERROR_STOP on
-- QA only. The reviewed rollback wrapper installs the real signup/plan42day
-- fixture, its private future-week freeze, the literal bridge and S17D helpers.
-- It executes SETUP before installing P5, then ASSERTIONS. No public clock override.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=pg_catalog;SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
-- P5_SETUP_BEGIN
\ir fixtures/mobile_strength_week_projection_fixture.sql
SET LOCAL ROLE postgres;
DO $calendar_baseline$
DECLARE u constant uuid:='c59d2c00-0000-4000-8000-000000000902';ui jsonb;obs jsonb;r jsonb;l uuid;c jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN RAISE EXCEPTION 'P5_SETUP_CONTROL_COLLISION';END IF;
 INSERT INTO public.users(id,name,timezone,status,metadata)
 VALUES(u,'P5 calendar compatibility synthetic','UTC','active','{"qa_owner":"P5"}');
 ui:=c59s17d_fixture.member(u,c59s17d_fixture.key(7992),c59s17d_fixture.input(42,'p5-calendar-control'));
 obs:=public.get_workout_strength_catalogue_context();
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,ui->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,ui#>>'{proposal,workoutType}')));
 SET LOCAL ROLE postgres;
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR r#>>'{result,capture,strength,status}' IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'P5_SETUP_CONTROL_NOT_REAL_CONFIRMED:%',r;END IF;
 SELECT current_lifecycle_key INTO STRICT l FROM private.workout_strength_authority_epochs WHERE user_id=u;
 c:=public.prepare_workout_strength_calendar_scope(u,l);
 IF c->>'status' IS DISTINCT FROM 'prepared' OR l IS NULL
  OR EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=u)
 THEN RAISE EXCEPTION 'P5_SETUP_OLD_PUBLIC_CALENDAR_NOT_PROVED';END IF;
 INSERT INTO c59_plan_fixture.context VALUES('p5_old_calendar',c),('p5_control_lifecycle',to_jsonb(l)),
  ('p5_control_state',c59s17d_fixture.state(u));
 RAISE NOTICE 'P5_OLD_PUBLIC_CALENDAR_REAL_L_BASELINE';
END $calendar_baseline$;
-- P5_SETUP_END

-- P5_ASSERTIONS_BEGIN
SET LOCAL ROLE postgres;
DO $no_lifecycle$
DECLARE u constant uuid:='c59d2c00-0000-4000-8000-000000000901';t private.strength_week_targets%ROWTYPE;
 at timestamptz;s jsonb;r jsonb;
BEGIN
 SELECT * INTO STRICT t FROM private.strength_week_targets WHERE user_id=u;
 SELECT (value#>>'{}')::timestamptz INTO STRICT at FROM c59_plan_fixture.context WHERE key='p2_observed_at';
 IF EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u)
  OR EXISTS(SELECT 1 FROM private.strength_week_lifecycle_bindings WHERE user_id=u)
 THEN RAISE EXCEPTION 'P5_SETUP_NO_L_ALREADY_BOUND';END IF;
 s:=c59s17d_fixture.state(u);
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at);
 IF r IS DISTINCT FROM '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_NO_L_INVENTED_AUTHORITY_OR_STATE';END IF;
 RAISE NOTICE 'P5_REAL_Y_WITHOUT_L_UNAVAILABLE_NO_SIDE_EFFECT';
END $no_lifecycle$;

DO $real_projection$
DECLARE u constant uuid:='c59d2c00-0000-4000-8000-000000000901';control constant uuid:='c59d2c00-0000-4000-8000-000000000902';
 t private.strength_week_targets%ROWTYPE;ui jsonb;obs jsonb;r jsonb;again jsonb;binding jsonb;old_calendar jsonb;
 target_wire jsonb;s jsonb;before_projection jsonb;at timestamptz;l uuid;control_l uuid;
 performed text;k text;v jsonb;v_proposal jsonb;v_admission jsonb;expires timestamptz;
BEGIN
 SELECT * INTO STRICT t FROM private.strength_week_targets WHERE user_id=u;
 SELECT (value#>>'{}')::timestamptz INTO STRICT at FROM c59_plan_fixture.context WHERE key='p2_observed_at';
 -- Use a real current event through admission/materialization/confirmation.
 -- The literal older fixture helpers retain their fixed historical defaults.
 performed:=to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
 k:=c59s17d_fixture.key(7991);v:=c59s17d_fixture.input(43,'p5-real-current-workout',performed);
 v_proposal:=c59s17d_fixture.proposal(k,v,400,performed);expires:=clock_timestamp()+interval '6 hours';
 r:=c59s17d_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'admitted'
 THEN RAISE EXCEPTION 'P5_SETUP_REAL_CURRENT_ADMIT:%',r;END IF;
 v_admission:=r#>'{result,admission}';
 r:=c59s17d_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',
  u,v_admission->>'admissionID',v,v_proposal,expires));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'materialized'
 THEN RAISE EXCEPTION 'P5_SETUP_REAL_CURRENT_MATERIALIZE:%',r;END IF;
 ui:=jsonb_build_object('registrationID',r#>'{result,pendingID}','proposal',v_proposal);
 SET LOCAL ROLE postgres;
 obs:=public.get_workout_strength_catalogue_context();
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,ui->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,ui#>>'{proposal,workoutType}')));
 SET LOCAL ROLE postgres;
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR r#>>'{result,capture,strength,status}' IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'P5_SETUP_Y_L_NOT_REAL_CONFIRMED:%',r;END IF;
 SELECT current_lifecycle_key INTO STRICT l FROM private.workout_strength_authority_epochs WHERE user_id=u;
 IF (SELECT count(*) FROM private.workout_strength_facts f JOIN public.workout_logs w
    ON w.user_id=f.user_id AND w.id=f.workout_log_id WHERE f.user_id=u
     AND f.lifecycle_key=l AND f.performed_at=performed::timestamptz AND w.performed_at=f.performed_at)<>1
 THEN RAISE EXCEPTION 'P5_SETUP_CURRENT_EVENT_FACT_NOT_PROVED';END IF;
 RAISE NOTICE 'P5_REAL_CURRENT_WORKOUT_CONFIRMED_WITH_ORIGINAL_TIMESTAMP';
 binding:=public.get_mobile_strength_week_lifecycle_binding(u,t.generation,l);
 IF binding->>'status' IS DISTINCT FROM 'ready' THEN RAISE EXCEPTION 'P5_SETUP_REAL_BINDING_ABSENT';END IF;
 SELECT private.strength_week_target_wire(a,p,f) INTO STRICT target_wire FROM private.strength_week_targets a
 LEFT JOIN private.strength_week_source_versions p ON p.user_id=a.user_id AND p.source_version_id=a.plan_source_version_id
 LEFT JOIN private.strength_week_source_versions f ON f.user_id=a.user_id AND f.source_version_id=a.frequency_source_version_id
 WHERE a.target_id=t.target_id;
 before_projection:=c59s17d_fixture.state(u);
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at);
 IF r->>'status' IS DISTINCT FROM 'available' OR r->'target' IS DISTINCT FROM target_wire
  OR r->'binding' IS DISTINCT FROM binding->'proof'
  OR r#>>'{calendar,ownerID}' IS DISTINCT FROM u::text
  OR r#>>'{calendar,lifecycleKey}' IS DISTINCT FROM l::text
  OR r#>>'{calendar,timeZone}' IS DISTINCT FROM t.timezone_at_freeze
  OR r#>>'{calendar,weekStartDate}' IS DISTINCT FROM to_char(t.week_start::timestamp,'YYYY-MM-DD')
  OR r#>>'{calendar,asOfLocalDate}' IS DISTINCT FROM to_char(at AT TIME ZONE t.timezone_at_freeze,'YYYY-MM-DD')
  OR r->>'observed_at' IS DISTINCT FROM to_char(at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  OR r->'projection' IS DISTINCT FROM '{"status":"available","workouts":[]}'::jsonb
  OR c59s17d_fixture.state(u)-'private.workout_strength_calendar_scopes'
    IS DISTINCT FROM before_projection-'private.workout_strength_calendar_scopes'
 THEN RAISE EXCEPTION 'P5_REAL_FUTURE_QA_PROJECTION_INVALID:%',r;END IF;
 s:=c59s17d_fixture.state(u);
 again:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at);
 IF again IS DISTINCT FROM r OR c59s17d_fixture.state(u) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_REPLAY_CHANGED_PROJECTION_OR_RECEIPT';END IF;
 INSERT INTO c59_plan_fixture.context VALUES('p5_available',r),('p5_lifecycle',to_jsonb(l)),('p5_state',s);
 RAISE NOTICE 'P5_REAL_Y_L_BINDING_FUTURE_QA_AVAILABLE_EMPTY_WEEK_REPLAY';

 -- Real-clock public API cannot publish the target acquired for next Monday.
 SET LOCAL ROLE service_role;
 again:=public.get_mobile_strength_week_projection(u,t.generation,t.target_id);
 SET LOCAL ROLE postgres;
 IF again IS DISTINCT FROM '{"status":"conflict","reason":"week_changed"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_PUBLIC_REAL_CLOCK_MIXED_FUTURE_TARGET';END IF;
 RAISE NOTICE 'P5_PUBLIC_REAL_CLOCK_REJECTS_FUTURE_TARGET_NO_SIDE_EFFECT';

 SELECT value INTO STRICT old_calendar FROM c59_plan_fixture.context WHERE key='p5_old_calendar';
 SELECT (value#>>'{}')::uuid INTO STRICT control_l FROM c59_plan_fixture.context WHERE key='p5_control_lifecycle';
 SELECT value INTO STRICT s FROM c59_plan_fixture.context WHERE key='p5_control_state';
 SET LOCAL ROLE service_role;
 again:=public.prepare_workout_strength_calendar_scope(control,control_l);
 SET LOCAL ROLE postgres;
 IF again IS DISTINCT FROM (old_calendar||'{"status":"reuse_existing"}'::jsonb)
  OR c59s17d_fixture.state(control) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_PUBLIC_CALENDAR_COMPATIBILITY_CHANGED';END IF;
 RAISE NOTICE 'P5_PUBLIC_CALENDAR_OLD_RECEIPT_REUSED_EXACT';
END $real_projection$;

DO $conflicts_and_acl$
DECLARE u constant uuid:='c59d2c00-0000-4000-8000-000000000901';t private.strength_week_targets%ROWTYPE;
 at timestamptz;s jsonb;r jsonb;role_name text;signature text;
BEGIN
 SELECT * INTO STRICT t FROM private.strength_week_targets WHERE user_id=u;
 SELECT (value#>>'{}')::timestamptz INTO STRICT at FROM c59_plan_fixture.context WHERE key='p2_observed_at';
 s:=c59s17d_fixture.state(u);
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,'c59d2c00-0000-4000-8000-000000000999',at);
 IF r IS DISTINCT FROM '{"status":"conflict","reason":"target_changed"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s THEN RAISE EXCEPTION 'P5_MISSING_TARGET_OR_SIDE_EFFECT';END IF;
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at+interval '7 days');
 IF r IS DISTINCT FROM '{"status":"conflict","reason":"week_changed"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s THEN RAISE EXCEPTION 'P5_CHANGED_WEEK_OR_SIDE_EFFECT';END IF;
 UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=u;
 s:=c59s17d_fixture.state(u);
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at);
 IF r IS DISTINCT FROM '{"status":"unavailable","reason":"timezone_incompatible"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s THEN RAISE EXCEPTION 'P5_CHANGED_ZONE_OR_SIDE_EFFECT';END IF;
 UPDATE public.users SET timezone='UTC' WHERE id=u;
 FOREACH signature IN ARRAY ARRAY[
  'private.prepare_workout_strength_calendar_scope_at(uuid,uuid,timestamptz)',
  'private.get_mobile_strength_week_projection_at(uuid,uuid,uuid,timestamptz)'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(role_name,signature,'EXECUTE') THEN RAISE EXCEPTION 'P5_PRIVATE_EXPOSED:%:%',role_name,signature;END IF;
  END LOOP;
 END LOOP;
 IF NOT has_function_privilege('service_role','public.get_mobile_strength_week_projection(uuid,uuid,uuid)','EXECUTE')
  OR has_function_privilege('anon','public.get_mobile_strength_week_projection(uuid,uuid,uuid)','EXECUTE')
  OR has_function_privilege('authenticated','public.get_mobile_strength_week_projection(uuid,uuid,uuid)','EXECUTE')
  OR to_regprocedure('public.get_mobile_strength_week_projection(uuid,uuid,uuid,timestamptz)') IS NOT NULL
 THEN RAISE EXCEPTION 'P5_PUBLIC_CLOCK_OR_ACL_EXPOSED';END IF;
 r:=c59s17d_fixture.attempt(format('SELECT private.get_mobile_strength_week_projection_at(%L,%L,%L,%L)',u,t.generation,t.target_id,at));
 SET LOCAL ROLE postgres;
 IF r->'ok' IS DISTINCT FROM 'false'::jsonb OR r->>'sqlstate' IS DISTINCT FROM '42501'
 THEN RAISE EXCEPTION 'P5_ACTUAL_PRIVATE_EXECUTE_NOT_DENIED:%',r;END IF;
 RAISE NOTICE 'P5_TARGET_WEEK_ZONE_CONFLICTS_AND_PRIVATE_ACL';
END $conflicts_and_acl$;

CREATE FUNCTION c59s17d_fixture.p5_observe_calendar_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fault$
DECLARE at timestamptz;
BEGIN
 SELECT (value#>>'{}')::timestamptz INTO STRICT at FROM c59_plan_fixture.context WHERE key='p2_observed_at';
 IF NEW.user_id='c59d2c00-0000-4000-8000-000000000901'::uuid THEN
  IF NEW.created_at=at+interval '1 day' THEN
   IF NOT EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes c WHERE c.user_id=NEW.user_id AND c.scope_key=NEW.scope_key)
   THEN RAISE EXCEPTION 'P5_SETUP_AFTER_INSERT_ROW_ABSENT';END IF;
   RAISE NOTICE 'P5_CALENDAR_INSERT_OBSERVED_BEFORE_NEGATIVE';
  ELSIF NEW.created_at=at+interval '2 days' THEN
   RAISE EXCEPTION 'P5_SYNTHETIC_AFTER_INSERT_FAILURE' USING ERRCODE='XX000';
  END IF;
 END IF;
 RETURN NEW;
END $fault$;
REVOKE ALL ON FUNCTION c59s17d_fixture.p5_observe_calendar_insert() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER p5_observe_calendar_insert AFTER INSERT ON private.workout_strength_calendar_scopes
FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.p5_observe_calendar_insert();

DO $negative_atomicity$
DECLARE u constant uuid:='c59d2c00-0000-4000-8000-000000000901';t private.strength_week_targets%ROWTYPE;
 at timestamptz;now_at timestamptz;s jsonb;r jsonb;old_count bigint;fact_count bigint;
BEGIN
 SELECT * INTO STRICT t FROM private.strength_week_targets WHERE user_id=u;
 SELECT (value#>>'{}')::timestamptz INTO STRICT at FROM c59_plan_fixture.context WHERE key='p2_observed_at';
 SELECT count(*) INTO old_count FROM public.workout_logs WHERE user_id=u;
 SELECT count(*) INTO fact_count FROM private.workout_strength_facts WHERE user_id=u;
 now_at:=clock_timestamp();
 SET LOCAL ROLE service_role;
 PERFORM public.register_workout_atomic(u,(now_at AT TIME ZONE 'UTC')::date,
  'P5 legacy calendar gap',10,100,'moderada','P5 synthetic only',now_at,'p5-native-legacy-gap',2200,150.125,false,NULL);
 SET LOCAL ROLE postgres;
 IF (SELECT count(*) FROM public.workout_logs WHERE user_id=u)<>old_count+1
  OR (SELECT count(*) FROM private.workout_strength_facts WHERE user_id=u)<>fact_count
 THEN RAISE EXCEPTION 'P5_SETUP_REAL_LEGACY_GAP_NOT_PROVED';END IF;
 s:=c59s17d_fixture.state(u);
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at+interval '1 day');
 IF r IS DISTINCT FROM '{"status":"unavailable","reason":"calendar_unproved"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_NEGATIVE_RETAINED_NEW_CALENDAR_OR_LOST_OLD_RECEIPT:%',r;END IF;
 RAISE NOTICE 'P5_NEGATIVE_AFTER_INSERT_ROLLS_BACK_ONLY_NEW_RECEIPT';
 r:=c59s17d_fixture.attempt(format('SELECT private.get_mobile_strength_week_projection_at(%L,%L,%L,%L)',
  u,t.generation,t.target_id,at+interval '2 days'),'postgres');
 SET LOCAL ROLE postgres;
 IF r->'ok' IS DISTINCT FROM 'false'::jsonb OR r->>'sqlstate' IS DISTINCT FROM 'XX000'
  OR r->>'message' IS DISTINCT FROM 'P5_SYNTHETIC_AFTER_INSERT_FAILURE'
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_UNEXPECTED_ERROR_SWALLOWED_OR_STATE_CHANGED:%',r;END IF;
 RAISE NOTICE 'P5_UNEXPECTED_AFTER_INSERT_ERROR_PROPAGATES_ATOMICALLY';
 SET LOCAL ROLE service_role;
 r:=public.reset_user_conversation_atomic(u,true);
 SET LOCAL ROLE postgres;
 IF r->'reset' IS DISTINCT FROM 'true'::jsonb
  OR EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=u AND closed_at IS NULL)
 THEN RAISE EXCEPTION 'P5_SETUP_REAL_RESET_NOT_CLOSED';END IF;
 s:=c59s17d_fixture.state(u);
 r:=private.get_mobile_strength_week_projection_at(u,t.generation,t.target_id,at);
 IF r IS DISTINCT FROM '{"status":"conflict","reason":"generation_changed"}'::jsonb
  OR c59s17d_fixture.state(u) IS DISTINCT FROM s
 THEN RAISE EXCEPTION 'P5_RESET_OLD_Y_RETURNED_MIXED_PROJECTION';END IF;
 RAISE NOTICE 'P5_REAL_RESET_REJECTS_OLD_Y_WITHOUT_STATE_CHANGE';
END $negative_atomicity$;
-- P5_ASSERTIONS_END
ROLLBACK;

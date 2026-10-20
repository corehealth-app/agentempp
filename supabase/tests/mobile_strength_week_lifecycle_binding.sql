\set ON_ERROR_STOP on
-- Native C5 regression: only synthetic owners and one outer rollback.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL search_path=pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO,YMD';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $target$
BEGIN
 IF session_user<>'c5_local_admin' OR current_user<>'c5_local_admin'
  OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
  OR current_setting('listen_addresses')<>'' OR inet_server_addr() IS NOT NULL
  OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
  OR to_regclass('private.strength_week_lifecycle_bindings') IS NULL
  OR to_regprocedure('private.bind_mobile_strength_week_lifecycle(uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_WRONG_TARGET_OR_UNAPPLIED_MIGRATION'; END IF;
END $target$;
\ir fixtures/mobile_strength_week_lifecycle_binding_fixture.sql
-- Same behavioral requirement for old S17D RED and hooked S17D GREEN.
-- Real RPC/DDL absence and failed confirmation are SETUP, never product RED.
RESET ROLE;
SET LOCAL search_path=pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $confirmation_control$
DECLARE
 u uuid;g uuid;l uuid;x jsonb;args jsonb;obs jsonb;res jsonb;resolved jsonb;
 a record;op record;lo timestamptz;hi timestamptz;v_operation_key text;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 x:=c59s17d_fixture.member(u,c59s17d_fixture.key(7701),
  c59s17d_fixture.input(40,'c59bridge-noncatalogue-20261020'));
 args:=c59s17d_fixture.legacy_arguments(u,x->'proposal');
 obs:=public.get_workout_strength_catalogue_context();
 IF obs->>'status' IS DISTINCT FROM 'available'
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_REAL_CATALOGUE'; END IF;
 lo:=clock_timestamp();
 res:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(x->>'registrationID')::uuid,0,args,obs,
  c59s17d_fixture.catalogue_decision(obs,x#>>'{proposal,workoutType}')));
 hi:=clock_timestamp();
 IF res->'ok' IS DISTINCT FROM 'true'::jsonb OR res#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR res#>>'{result,capture,strength,status}' IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_REAL_CONFIRMATION:%',res; END IF;
 SELECT * INTO STRICT a FROM private.mobile_workout_proposal_admissions
  WHERE user_id=u AND admission_id=(x#>>'{admission,admissionID}')::uuid;
 l:=a.confirmed_lifecycle_key;
 v_operation_key:='ui:'||a.admission_id::text||':r:0';
 SELECT o.* INTO STRICT op FROM private.workout_strength_operations o
  WHERE o.user_id=u AND o.lifecycle_key=l AND o.operation_kind='capture' AND o.operation_key=v_operation_key
   AND o.original_operation_type='c59bridge-noncatalogue-20261020';
 resolved:=public.resolve_confirmed_workout_strength_capture(u,l,v_operation_key,'c59bridge-noncatalogue-20261020');
 IF l IS NULL OR a.content_revision<>0 OR op.capture_outcome<>'fact'
  OR resolved->>'status' IS DISTINCT FROM 'reuse_existing'
  OR ((res#>'{result,capture,strength}')||'{"status":"reuse_existing"}'::jsonb) IS DISTINCT FROM resolved
  OR NOT EXISTS(SELECT 1 FROM public.pending_registrations p WHERE p.user_id=u AND p.id=a.pending_id
    AND p.status='confirmed' AND p.resolved_at BETWEEN lo AND hi AND p.workout_ui_admission_id=a.admission_id)
  OR NOT EXISTS(SELECT 1 FROM ONLY public.workout_logs w WHERE w.user_id=u AND w.id=op.original_workout_log_id)
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_facts f WHERE f.user_id=u AND f.lifecycle_key=l
    AND f.workout_log_id=op.original_workout_log_id AND f.classification_status='unrecognized')
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e WHERE e.user_id=u
    AND e.epoch=a.epoch AND e.current_lifecycle_key=l)
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles life
    JOIN private.strength_week_scopes s ON s.user_id=life.user_id
    WHERE life.user_id=u AND life.lifecycle_key=l AND life.closed_at IS NULL AND s.generation=g
      AND s.closed_at IS NULL AND life.opened_at>=s.opened_at)
  OR EXISTS(SELECT 1 FROM public.messages WHERE user_id=u)
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_CONFIRMATION_ORIGIN'; END IF;
 INSERT INTO c59_bridge_fixture.context VALUES
  ('workout_ui',x),('lifecycle',to_jsonb(l)),('workout_result',res->'result'),
  ('confirm_lower',to_jsonb(lo)),('confirm_upper',to_jsonb(hi)),
  ('binding_before_control',(SELECT coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb)
    FROM private.strength_week_lifecycle_bindings b WHERE b.user_id=u));
 RAISE NOTICE 'C59BRIDGE_CONTROL_REAL_UI_CONFIRMED_FACT_NO_FLOW';
END $confirmation_control$;

SET LOCAL ROLE postgres;
SAVEPOINT reader_positive_control;
DO $reader_positive_control$
DECLARE u uuid;g uuid;l uuid;signup jsonb;ui jsonb;probe jsonb;proof jsonb;b record;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT value INTO STRICT signup FROM c59_bridge_fixture.context WHERE key='signup_receipt';
 SELECT value INTO STRICT ui FROM c59_bridge_fixture.context WHERE key='workout_ui';
 -- Explicit QA reader control, not a claim of product-owned binding creation.
 IF NOT EXISTS(SELECT 1 FROM private.strength_week_lifecycle_bindings WHERE user_id=u AND generation=g) THEN
  INSERT INTO private.strength_week_lifecycle_bindings(user_id,generation,epoch,lifecycle_key,
   signup_admission_id,frequency_source_version_id,workout_admission_id,workout_content_revision,bound_at)
  VALUES(u,g,(signup->>'epoch')::uuid,l,(signup->>'admission_id')::uuid,
   (signup->>'frequency_source_version_id')::uuid,(ui#>>'{admission,admissionID}')::uuid,0,clock_timestamp());
 END IF;
 SELECT * INTO STRICT b FROM private.strength_week_lifecycle_bindings WHERE user_id=u AND generation=g;
 probe:=c59s17d_fixture.attempt(format('SELECT public.get_mobile_strength_week_lifecycle_binding(%L::uuid,%L::uuid,%L::uuid)',u,g,l));
 proof:=jsonb_build_object('ownerID',u::text,'generation',g::text,'epoch',signup->>'epoch',
  'lifecycleKey',l::text,'signupAdmissionID',signup->>'admission_id',
  'frequencySourceVersionID',signup->>'frequency_source_version_id',
  'workoutAdmissionID',ui#>>'{admission,admissionID}','workoutContentRevision',0,
  'boundAt',to_char(b.bound_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
 IF probe IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','ready','proof',proof))
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_READER_POSITIVE_CONTROL:%',probe; END IF;
 RAISE NOTICE 'C59BRIDGE_CONTROL_READER_READY_WITH_REAL_ORIGIN_QA_ROW';
END $reader_positive_control$;
ROLLBACK TO SAVEPOINT reader_positive_control;
RELEASE SAVEPOINT reader_positive_control;
RESET ROLE;

DO $behavioral_requirement$
DECLARE u uuid;g uuid;l uuid;before_rows jsonb;actual_rows jsonb;probe jsonb;proof jsonb;lo timestamptz;hi timestamptz;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT value INTO STRICT before_rows FROM c59_bridge_fixture.context WHERE key='binding_before_control';
 SELECT coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb) INTO actual_rows
  FROM private.strength_week_lifecycle_bindings b WHERE b.user_id=u;
 IF actual_rows IS DISTINCT FROM before_rows
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_READER_CONTROL_NOT_ROLLED_BACK'; END IF;
 probe:=c59s17d_fixture.attempt(format('SELECT public.get_mobile_strength_week_lifecycle_binding(%L::uuid,%L::uuid,%L::uuid)',u,g,l));
 IF probe=jsonb_build_object('ok',true,'result','{"status":"unavailable","reason":"binding_unproved"}'::jsonb)
  AND actual_rows='[]'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_EXPECTED_OWNED_PROOF'; END IF;
 IF probe->'ok' IS DISTINCT FROM 'true'::jsonb OR probe#>>'{result,status}' IS DISTINCT FROM 'ready'
  OR jsonb_array_length(actual_rows)<>1
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_NONCAUSAL_OR_INVALID_PROOF:%',probe; END IF;
 proof:=probe#>'{result,proof}';
 SELECT (value#>>'{}')::timestamptz INTO STRICT lo FROM c59_bridge_fixture.context WHERE key='confirm_lower';
 SELECT (value#>>'{}')::timestamptz INTO STRICT hi FROM c59_bridge_fixture.context WHERE key='confirm_upper';
 IF proof->>'ownerID'<>u::text OR proof->>'generation'<>g::text OR proof->>'lifecycleKey'<>l::text
  OR (proof->>'boundAt')::timestamptz NOT BETWEEN lo AND hi
 THEN RAISE EXCEPTION 'C59BRIDGE_WRONG_ORIGIN_OR_BOUND_CLOCK'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_REAL_CONFIRMATION_AUTOMATIC_JOINT_PROOF';
END $behavioral_requirement$;

DO $second_and_replay$
DECLARE u uuid;g uuid;l uuid;b jsonb;proof jsonb;x jsonb;first_ui jsonb;obs jsonb;r jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT value INTO STRICT first_ui FROM c59_bridge_fixture.context WHERE key='workout_ui';
 SELECT to_jsonb(v) INTO STRICT b FROM private.strength_week_lifecycle_bindings v WHERE user_id=u AND generation=g;
 proof:=public.get_mobile_strength_week_lifecycle_binding(u,g,l);
 x:=c59_bridge_fixture.confirm(u,7702);
 IF b IS DISTINCT FROM(SELECT to_jsonb(v) FROM private.strength_week_lifecycle_bindings v WHERE user_id=u AND generation=g)
  OR proof IS DISTINCT FROM public.get_mobile_strength_week_lifecycle_binding(u,g,l)
  OR (SELECT count(*) FROM private.strength_week_source_versions WHERE user_id=u)<>1
  OR b->>'workout_admission_id'=x#>>'{admission,admissionID}'
 THEN RAISE EXCEPTION 'C59BRIDGE_SECOND_CONFIRMATION_REPLACED_ORIGIN'; END IF;
 obs:=public.get_workout_strength_catalogue_context();
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(first_ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,first_ui->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,first_ui#>>'{proposal,workoutType}')));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'reused'
  OR proof IS DISTINCT FROM public.get_mobile_strength_week_lifecycle_binding(u,g,l)
  OR b IS DISTINCT FROM(SELECT to_jsonb(v) FROM private.strength_week_lifecycle_bindings v WHERE user_id=u AND generation=g)
 THEN RAISE EXCEPTION 'C59BRIDGE_REPLAY_CHANGED_ORIGIN'; END IF;
 INSERT INTO c59_bridge_fixture.context VALUES('original_binding',b),('original_proof',proof);
 RAISE NOTICE 'C59BRIDGE_PASS_SECOND_CONFIRM_AND_REPLAY_PRESERVE_EXACT_ORIGIN_CLOCK';
END $second_and_replay$;

SET LOCAL ROLE postgres;
SAVEPOINT missing_binding_replay;
DELETE FROM private.strength_week_lifecycle_bindings
 WHERE user_id=(SELECT (value#>>'{}')::uuid FROM c59_bridge_fixture.context WHERE key='owner');
DO $no_repair$
DECLARE u uuid;g uuid;l uuid;x jsonb;obs jsonb;r jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT value INTO STRICT x FROM c59_bridge_fixture.context WHERE key='workout_ui';
 obs:=public.get_workout_strength_catalogue_context();
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(x->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,x->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,x#>>'{proposal,workoutType}')));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'reused'
  OR EXISTS(SELECT 1 FROM private.strength_week_lifecycle_bindings WHERE user_id=u)
  OR public.get_mobile_strength_week_lifecycle_binding(u,g,l) IS DISTINCT FROM
   '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_REPLAY_REPAIRED_MISSING_PROOF'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_REPLAY_NEVER_CREATES_MISSING_BINDING';
END $no_repair$;
ROLLBACK TO SAVEPOINT missing_binding_replay;
RELEASE SAVEPOINT missing_binding_replay;
RESET ROLE;

DO $deleted_origin$
DECLARE u uuid;g uuid;l uuid;proof jsonb;origin uuid;x jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT value INTO STRICT proof FROM c59_bridge_fixture.context WHERE key='original_proof';
 SELECT o.original_workout_log_id INTO STRICT origin FROM private.workout_strength_operations o
  JOIN private.strength_week_lifecycle_bindings b ON b.user_id=o.user_id AND b.lifecycle_key=o.lifecycle_key
  WHERE b.user_id=u AND o.operation_kind='capture'
   AND o.operation_key='ui:'||b.workout_admission_id::text||':r:'||b.workout_content_revision::text;
 DELETE FROM ONLY public.workout_logs WHERE user_id=u AND id=origin;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u AND workout_log_id=origin)
  OR public.get_mobile_strength_week_lifecycle_binding(u,g,l) IS DISTINCT FROM proof
 THEN RAISE EXCEPTION 'C59BRIDGE_DELETED_ORIGIN_ERASED_DURABLE_PROOF'; END IF;
 x:=c59_bridge_fixture.confirm(u,7703);
 IF public.get_mobile_strength_week_lifecycle_binding(u,g,l) IS DISTINCT FROM proof THEN
  RAISE EXCEPTION 'C59BRIDGE_NEW_CONFIRM_AFTER_DELETE_REPLACED_ORIGIN'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_DELETED_ORIGINAL_LOG_AND_NEW_CONFIRM_PRESERVE_PROOF';
END $deleted_origin$;

DO $missing_y_and_older_life$
DECLARE no_y constant uuid:='c59b2600-0000-4000-8000-000000000903';
 older constant uuid:='c59b2600-0000-4000-8000-000000000902';
 x jsonb;signup jsonb;l uuid;g uuid;first_l uuid;
BEGIN
 PERFORM c59_bridge_fixture.new_owner(no_y);
 x:=c59_bridge_fixture.confirm(no_y,7704);
 IF EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=no_y)
  OR EXISTS(SELECT 1 FROM private.strength_week_lifecycle_bindings WHERE user_id=no_y)
  OR EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=no_y)
 THEN RAISE EXCEPTION 'C59BRIDGE_NO_Y_WAS_FABRICATED'; END IF;
 PERFORM c59_bridge_fixture.new_owner(older);
 x:=c59_bridge_fixture.confirm(older,7705);
 SELECT current_lifecycle_key INTO STRICT first_l FROM private.workout_strength_authority_epochs WHERE user_id=older;
 signup:=c59_bridge_fixture.finish_signup(older);
 g:=(signup#>>'{receipt,generation}')::uuid;
 x:=c59_bridge_fixture.confirm(older,7706);
 SELECT current_lifecycle_key INTO STRICT l FROM private.workout_strength_authority_epochs WHERE user_id=older;
 IF l IS DISTINCT FROM first_l
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles life
   JOIN private.strength_week_scopes s ON s.user_id=life.user_id WHERE life.user_id=older
    AND life.lifecycle_key=l AND s.generation=g AND life.opened_at<s.opened_at)
  OR EXISTS(SELECT 1 FROM private.strength_week_lifecycle_bindings WHERE user_id=older)
  OR public.get_mobile_strength_week_lifecycle_binding(older,g,l) IS DISTINCT FROM
   '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_ADOPTED_PREVIOUS_LIFECYCLE'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_NO_Y_AND_LIFECYCLE_BEFORE_Y_KEEP_CONFIRMATION_UNBOUND';
END $missing_y_and_older_life$;

DO $immutability_and_input_acl$
DECLARE u uuid;g uuid;l uuid;before_row jsonb;r jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT to_jsonb(b) INTO STRICT before_row FROM private.strength_week_lifecycle_bindings b WHERE user_id=u AND generation=g;
 BEGIN
  UPDATE private.strength_week_lifecycle_bindings SET bound_at=bound_at+interval '1 microsecond' WHERE user_id=u AND generation=g;
  RAISE EXCEPTION 'C59BRIDGE_IMMUTABILITY_NOT_ENFORCED';
 EXCEPTION WHEN SQLSTATE '22023' THEN
  IF SQLERRM<>'strength_week_lifecycle_binding_immutable' THEN RAISE; END IF;
 END;
 IF before_row IS DISTINCT FROM(SELECT to_jsonb(b) FROM private.strength_week_lifecycle_bindings b WHERE user_id=u AND generation=g)
 THEN RAISE EXCEPTION 'C59BRIDGE_IMMUTABILITY_CHANGED_ROW'; END IF;
 r:=c59s17d_fixture.attempt(format('SELECT private.bind_mobile_strength_week_lifecycle(%L::uuid,%L::uuid,%L::uuid)',u,before_row->>'workout_admission_id',l));
 IF r->'ok' IS DISTINCT FROM 'false'::jsonb OR r->>'sqlstate'<>'42501' THEN RAISE EXCEPTION 'C59BRIDGE_PRIVATE_HELPER_EXPOSED'; END IF;
 r:=c59s17d_fixture.attempt(format('SELECT public.get_mobile_strength_week_lifecycle_binding(%L::uuid,%L::uuid,%L::uuid)',u,g,l),'anon');
 IF r->'ok' IS DISTINCT FROM 'false'::jsonb OR r->>'sqlstate'<>'42501' THEN RAISE EXCEPTION 'C59BRIDGE_READER_EXPOSED_TO_ANON'; END IF;
 r:=c59s17d_fixture.attempt(format('SELECT public.get_mobile_strength_week_lifecycle_binding(NULL,%L::uuid,%L::uuid)',g,l));
 IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"22023","message":"invalid_strength_week_lifecycle_binding_input"}'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_NULL_GUARD'; END IF;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 r:=c59s17d_fixture.attempt(format('SELECT public.get_mobile_strength_week_lifecycle_binding(%L::uuid,%L::uuid,%L::uuid)',u,g,l));
 IF r->'ok' IS DISTINCT FROM 'false'::jsonb OR r->>'sqlstate'<>'42501' THEN RAISE EXCEPTION 'C59BRIDGE_TRUSTED_GUARD'; END IF;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 IF public.get_mobile_strength_week_lifecycle_binding(u,gen_random_uuid(),l) IS DISTINCT FROM '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
  OR public.get_mobile_strength_week_lifecycle_binding(u,g,gen_random_uuid()) IS DISTINCT FROM '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
  OR public.get_mobile_strength_week_lifecycle_binding('c59b2600-0000-4000-8000-000000000902',g,l) IS DISTINCT FROM '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_CROSS_IDENTITY_PROOF'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_IMMUTABILITY_INPUT_TRUST_ACL_AND_EXPECTED_IDENTITIES';
END $immutability_and_input_acl$;

SET LOCAL ROLE postgres;
SAVEPOINT contradictory_binding;
DELETE FROM private.strength_week_lifecycle_bindings
 WHERE user_id=(SELECT (value#>>'{}')::uuid FROM c59_bridge_fixture.context WHERE key='owner');
INSERT INTO private.strength_week_lifecycle_bindings
 SELECT (jsonb_populate_record(NULL::private.strength_week_lifecycle_bindings,
  value||jsonb_build_object('epoch',gen_random_uuid()))).* FROM c59_bridge_fixture.context WHERE key='original_binding';
DO $contradiction$
DECLARE u uuid;g uuid;l uuid;r jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 r:=c59s17d_fixture.attempt(format('SELECT public.get_mobile_strength_week_lifecycle_binding(%L::uuid,%L::uuid,%L::uuid)',u,g,l));
 IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"XX001","message":"strength_week_lifecycle_binding_origin_invalid"}'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_CURRENT_CORRUPTION_HIDDEN:%',r; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_CURRENT_BINDING_CONTRADICTION_PROPAGATES_XX001';
END $contradiction$;
ROLLBACK TO SAVEPOINT contradictory_binding;
RELEASE SAVEPOINT contradictory_binding;
RESET ROLE;

SET LOCAL ROLE postgres;
CREATE FUNCTION c59_bridge_fixture.fail_after_binding() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $qa$
BEGIN
 IF NEW.user_id='c59b2600-0000-4000-8000-000000000904' THEN
  IF NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a
    JOIN public.pending_registrations p ON p.user_id=a.user_id AND p.id=a.pending_id
    JOIN private.workout_strength_operations o ON o.user_id=a.user_id AND o.lifecycle_key=a.confirmed_lifecycle_key
     AND o.operation_kind='capture' AND o.operation_key='ui:'||a.admission_id::text||':r:'||a.content_revision::text
    WHERE a.user_id=NEW.user_id AND a.admission_id=NEW.workout_admission_id
     AND a.confirmed_lifecycle_key=NEW.lifecycle_key AND p.status='confirmed' AND p.resolved_at IS NOT NULL
     AND o.capture_outcome='fact') THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_INJECTION_NOT_AFTER_TERMINAL_CAPTURE'; END IF;
  RAISE EXCEPTION 'C59BRIDGE_INJECTED_AFTER_BINDING' USING ERRCODE='PB001';
 END IF;
 RETURN NEW;
END $qa$;
REVOKE ALL ON FUNCTION c59_bridge_fixture.fail_after_binding() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER c59_bridge_fail_after_binding AFTER INSERT ON private.strength_week_lifecycle_bindings
 FOR EACH ROW EXECUTE FUNCTION c59_bridge_fixture.fail_after_binding();
RESET ROLE;
DO $rollback_everything$
DECLARE u constant uuid:='c59b2600-0000-4000-8000-000000000904';x jsonb;s jsonb;obs jsonb;r jsonb;before_state jsonb;
BEGIN
 PERFORM c59_bridge_fixture.new_owner(u);
 s:=c59_bridge_fixture.finish_signup(u);
 x:=c59s17d_fixture.member(u,c59s17d_fixture.key(7707),c59s17d_fixture.input(40,'c59bridge-noncatalogue-20261020'));
 obs:=public.get_workout_strength_catalogue_context();
 before_state:=c59s17d_fixture.state(u);
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(x->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,x->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,x#>>'{proposal,workoutType}')));
 IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"PB001","message":"C59BRIDGE_INJECTED_AFTER_BINDING"}'::jsonb
  OR before_state IS DISTINCT FROM c59s17d_fixture.state(u)
 THEN RAISE EXCEPTION 'C59BRIDGE_POST_BINDING_FAILURE_NOT_ATOMIC:%',r; END IF;
 INSERT INTO c59_bridge_fixture.context VALUES('atomic_retry_ui',x),('atomic_retry_signup',s);
 RAISE NOTICE 'C59BRIDGE_PASS_POST_BINDING_FAILURE_ROLLS_BACK_ALL_OWNER_ROWS';
END $rollback_everything$;
SET LOCAL ROLE postgres;
DROP TRIGGER c59_bridge_fail_after_binding ON private.strength_week_lifecycle_bindings;
RESET ROLE;
DO $retry_after_rollback$
DECLARE u constant uuid:='c59b2600-0000-4000-8000-000000000904';x jsonb;s jsonb;obs jsonb;r jsonb;l uuid;
BEGIN
 SELECT value INTO STRICT x FROM c59_bridge_fixture.context WHERE key='atomic_retry_ui';
 SELECT value INTO STRICT s FROM c59_bridge_fixture.context WHERE key='atomic_retry_signup';
 obs:=public.get_workout_strength_catalogue_context();
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(x->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,x->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,x#>>'{proposal,workoutType}')));
 SELECT current_lifecycle_key INTO STRICT l FROM private.workout_strength_authority_epochs WHERE user_id=u;
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR (SELECT count(*) FROM private.strength_week_lifecycle_bindings WHERE user_id=u)<>1
  OR (SELECT count(*) FROM private.workout_strength_operations WHERE user_id=u AND operation_kind='capture')<>1
  OR public.get_mobile_strength_week_lifecycle_binding(u,(s#>>'{receipt,generation}')::uuid,l)->>'status' IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'C59BRIDGE_RETRY_AFTER_ATOMIC_ROLLBACK'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_RETRY_AFTER_ROLLBACK_ONE_CAPTURE_ONE_BINDING';
END $retry_after_rollback$;

DO $reset_history$
DECLARE u uuid;g uuid;l uuid;before_row jsonb;r jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT u FROM c59_bridge_fixture.context WHERE key='owner';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_bridge_fixture.context WHERE key='generation';
 SELECT (value#>>'{}')::uuid INTO STRICT l FROM c59_bridge_fixture.context WHERE key='lifecycle';
 SELECT value INTO STRICT before_row FROM c59_bridge_fixture.context WHERE key='original_binding';
 r:=public.reset_user_conversation_atomic(u,false);
 IF before_row IS DISTINCT FROM(SELECT to_jsonb(b) FROM private.strength_week_lifecycle_bindings b WHERE user_id=u AND generation=g)
  OR NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=u AND generation=g AND closed_at IS NOT NULL)
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u AND lifecycle_key=l AND closed_at IS NOT NULL)
  OR public.get_mobile_strength_week_lifecycle_binding(u,g,l) IS DISTINCT FROM '{"status":"unavailable","reason":"binding_unproved"}'::jsonb
 THEN RAISE EXCEPTION 'C59BRIDGE_RESET_ERASED_HISTORY_OR_LEFT_ACTIVE_PROOF'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_REAL_RESET_RETAINS_HISTORY_AND_DENIES_CURRENT_PROOF';
END $reset_history$;

DO $no_extra_sources$
BEGIN
 IF (SELECT count(*) FROM private.strength_week_source_versions
   WHERE user_id IN('c59b2600-0000-4000-8000-000000000901','c59b2600-0000-4000-8000-000000000902','c59b2600-0000-4000-8000-000000000904'))<>3
  OR EXISTS(SELECT 1 FROM private.strength_week_source_versions
   WHERE user_id::text LIKE 'c59b2600-%' AND source_kind<>'informed_frequency')
  OR EXISTS(SELECT 1 FROM public.messages WHERE user_id::text LIKE 'c59b2600-%')
 THEN RAISE EXCEPTION 'C59BRIDGE_EXTRA_PLAN_ABSENCE_OR_FLOW_FABRICATED'; END IF;
 RAISE NOTICE 'C59BRIDGE_PASS_THREE_REAL_SIGNUP_SOURCES_NO_PLAN_ABSENCE_OR_FLOW';
END $no_extra_sources$;
RESET ROLE;
ROLLBACK;
\echo C59BRIDGE_GREEN_ROLLBACK

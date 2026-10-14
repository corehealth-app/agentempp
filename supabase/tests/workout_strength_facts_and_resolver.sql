-- S5 executable test-first. Root pins the six inputs and local synthetic target.
-- Missing includes/API/DDL are SETUP, never product causal RED. No fake RPC.
\set ON_ERROR_STOP on
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S5_SETUP_MIGRATION_PATH';END$$;
\endif
\if :{?bindings_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S5_SETUP_BINDINGS_PATH';END$$;
\endif
\if :{?legacy_api_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S5_SETUP_LEGACY_API_PATH';END$$;
\endif
\if :{?legacy_permissions_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S5_SETUP_LEGACY_PERMISSIONS_PATH';END$$;
\endif
-- RR must be selected BEFORE queries; SET isolation late would be25001/setup.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $setup$
BEGIN
  IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  THEN RAISE EXCEPTION 'C59S5_SETUP_PLATFORM_MISSING';END IF;
  IF to_regclass('public.daily_snapshots') IS NOT NULL OR to_regclass('public.workout_logs') IS NOT NULL
    OR to_regclass('public.workout_types') IS NOT NULL
    OR to_regclass('private.workout_strength_lifecycles') IS NOT NULL
    OR to_regclass('private.workout_strength_operations') IS NOT NULL
    OR to_regclass('private.workout_strength_facts') IS NOT NULL
    OR to_regnamespace('c59s5_fixture') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
      (n.nspname='public' AND p.proname IN('register_workout_atomic','resolve_confirmed_workout_strength_capture'))
      OR(n.nspname='private' AND p.proname='workout_strength_fact_snapshot'))
  THEN RAISE EXCEPTION 'C59S5_SETUP_UNKNOWN_EXISTING_OBJECT';END IF;
END $setup$;
\ir fixtures/workout_strength_facts_and_resolver_fixture.sql
\i :legacy_api_path
\i :legacy_permissions_path
\i :bindings_path
SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,
  'owner',p.proowner::text,'config',p.proconfig,'comment',obj_description(p.oid,'pg_proc'),
  'trusted_guard',(SELECT jsonb_build_object('definition',pg_get_functiondef(g.oid),'acl',g.proacl::text,
    'owner',g.proowner::text,'config',g.proconfig,'comment',obj_description(g.oid,'pg_proc'))
    FROM pg_proc g WHERE g.oid='private.assert_trusted_backend()'::regprocedure))::text) AS legacy_fingerprint
FROM pg_proc p WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure
\gset s5_
\i :migration_path
DO $installed$
BEGIN
  IF to_regclass('private.workout_strength_facts') IS NULL
    OR to_regprocedure('private.workout_strength_fact_snapshot(uuid,uuid,uuid)') IS NULL
    OR to_regprocedure('public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)') IS NULL
  THEN RAISE EXCEPTION 'C59S5_SETUP_UNIMPLEMENTED';END IF;
END $installed$;

SELECT c59s5_fixture.throws(
  'SELECT public.resolve_confirmed_workout_strength_capture(''c59a6000-0000-0000-0000-000000000001'',''c59a6000-0000-0000-0000-000000000002'',''valid-key'',''musculacao'')',
  '22023','workout_strength_requires_read_committed','guard_real_repeatable_read_rejected_before_owner_lookup');
ROLLBACK;

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $setup$
BEGIN
  IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL
    OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  THEN RAISE EXCEPTION 'C59S5_SETUP_PLATFORM_MISSING';END IF;
  IF to_regclass('public.daily_snapshots') IS NOT NULL OR to_regclass('public.workout_logs') IS NOT NULL
    OR to_regclass('public.workout_types') IS NOT NULL
    OR to_regclass('private.workout_strength_lifecycles') IS NOT NULL
    OR to_regclass('private.workout_strength_operations') IS NOT NULL
    OR to_regclass('private.workout_strength_facts') IS NOT NULL
    OR to_regnamespace('c59s5_fixture') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
      (n.nspname='public' AND p.proname IN('register_workout_atomic','resolve_confirmed_workout_strength_capture'))
      OR(n.nspname='private' AND p.proname='workout_strength_fact_snapshot'))
  THEN RAISE EXCEPTION 'C59S5_SETUP_UNKNOWN_EXISTING_OBJECT';END IF;
END $setup$;
\ir fixtures/workout_strength_facts_and_resolver_fixture.sql
\i :legacy_api_path
\i :legacy_permissions_path
\i :bindings_path
SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,
  'owner',p.proowner::text,'config',p.proconfig,'comment',obj_description(p.oid,'pg_proc'),
  'trusted_guard',(SELECT jsonb_build_object('definition',pg_get_functiondef(g.oid),'acl',g.proacl::text,
    'owner',g.proowner::text,'config',g.proconfig,'comment',obj_description(g.oid,'pg_proc'))
    FROM pg_proc g WHERE g.oid='private.assert_trusted_backend()'::regprocedure))::text) AS legacy_fingerprint
FROM pg_proc p WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure
\gset s5_
\i :migration_path
DO $installed$
BEGIN
  IF to_regclass('private.workout_strength_facts') IS NULL
    OR to_regprocedure('private.workout_strength_fact_snapshot(uuid,uuid,uuid)') IS NULL
    OR to_regprocedure('public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)') IS NULL
  THEN RAISE EXCEPTION 'C59S5_SETUP_UNIMPLEMENTED';END IF;
END $installed$;

SET LOCAL TimeZone='Pacific/Auckland';
SET LOCAL DateStyle='SQL, DMY';
SELECT count(*) AS baseline_users FROM public.users
\gset s5_

-- Actual old writer establishes anchor. Its D13 replay response is deliberately
-- NOT the row/snapshot anchor of UUIDW. Owner DML below only seeds stored facts.
DO $actual_anchor$
DECLARE a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();la uuid:=gen_random_uuid();lb uuid:=gen_random_uuid();
  ra jsonb;rb jsonb;replay jsonb;wa jsonb;f jsonb;fb jsonb;op jsonb;ef jsonb;binding jsonb;s jsonb;q uuid:=gen_random_uuid();
BEGIN
  INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES
    (a,'c59s5-a-'||a,'C59S5 synthetic A','America/Sao_Paulo','{"c59a2_synthetic":true}'),
    (b,'c59s5-b-'||b,'C59S5 synthetic B','America/Sao_Paulo','{"c59a2_synthetic":true}');
  ra:=public.register_workout_atomic(a,DATE'2026-10-12','  musculacao  ',60,300,'moderada','S5 A',
    '2026-10-12T15:00:00.123456Z','c59s5-provider-a',2000,150,false,NULL);
  rb:=public.register_workout_atomic(b,DATE'2026-10-12','natacao',20,200,'moderada','S5 B',
    '2026-10-12T15:00:00.123456Z','c59s5-provider-b',1800,100,false,NULL);
  replay:=public.register_workout_atomic(a,DATE'2026-10-13','  musculacao  ',60,300,'moderada','S5 A',
    '2026-10-13T15:00:00.123456Z','c59s5-provider-a',2000,150,false,NULL);
  SELECT to_jsonb(w) INTO wa FROM public.workout_logs w WHERE id=(ra->>'workout_log_id')::uuid;
  PERFORM c59s5_fixture.ok(ra->'inserted'='true'::jsonb AND rb->'inserted'='true'::jsonb
    AND replay->'inserted'='false'::jsonb AND replay->>'workout_log_id'=ra->>'workout_log_id'
    AND replay->>'snapshot_id'<>ra->>'snapshot_id' AND wa->>'snapshot_id'=ra->>'snapshot_id'
    AND (SELECT date=DATE'2026-10-12' FROM public.daily_snapshots WHERE id=(wa->>'snapshot_id')::uuid)
    AND (SELECT date=DATE'2026-10-13' AND exercise_calories=0 FROM public.daily_snapshots WHERE id=(replay->>'snapshot_id')::uuid)
    AND (SELECT count(*)=1 FROM public.workout_logs WHERE user_id=a),
    'real_X26_UUID_row_D12_distinct_from_attempt_response_D13');
  INSERT INTO private.workout_strength_lifecycles VALUES
    (a,la,'2026-10-01T00:00:00Z',NULL,NULL),(b,lb,'2026-10-01T00:00:00Z',NULL,NULL);
  f:=jsonb_build_object('user_id',a,'workout_log_id',ra->'workout_log_id','lifecycle_key',la,
    'snapshot_id',ra->'snapshot_id','stored_workout_type','musculacao','performed_at','2026-10-12T15:00:00.123456Z',
    'snapshot_date','2026-10-12','classification_status','matched','classification_reason',NULL,
    'observation_key','c59a6000-0000-0000-0000-000000000010','observed_at','2026-10-12T14:59:59.000001Z',
    'matcher_version','active_slug_then_unique_canonical_display_v1','active_row_count',5,'match_method','active_slug',
    'catalogue_id','c59a6000-0000-0000-0000-000000000011','catalogue_slug','peito_triceps',
    'catalogue_display_name','Peito e tríceps','catalogue_category','musculacao','catalogue_updated_at','2026-10-10T01:02:03.000002Z',
    'calendar_status','proven','calendar_reason',NULL,'local_date','2026-10-12','time_zone','America/Sao_Paulo',
    'zone_source','official_owner_zone_at_recording','zone_observed_at','2026-10-12T14:59:58.000003Z',
    'question_key',NULL,'answer',NULL,'answer_operation_key',NULL,'answer_accepted_at',NULL,'revision',0);
  EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',f);
  fb:=f||jsonb_build_object('user_id',b,'workout_log_id',rb->'workout_log_id','lifecycle_key',lb,'snapshot_id',rb->'snapshot_id',
    'stored_workout_type','natacao','catalogue_slug','natacao','catalogue_display_name','Natação','catalogue_category','cardio');
  EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',fb);
  op:=jsonb_build_object('user_id',a,'lifecycle_key',la,'operation_kind','capture','operation_key','capture-real',
    'original_operation_type','  musculacao  ','original_workout_log_id',ra->'workout_log_id','live_workout_log_id',ra->'workout_log_id',
    'created_at','2026-10-12T15:01:00Z','resolution','sql_replay','capture_outcome','fact','legacy_result',replay);
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',op);
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    op||jsonb_build_object('user_id',b,'lifecycle_key',lb,'operation_key','capture-b','original_operation_type','natacao',
      'original_workout_log_id',rb->'workout_log_id','live_workout_log_id',rb->'workout_log_id','legacy_result',rb));
  binding:=jsonb_build_object('ownerID',a,'lifecycleKey',la,'operationKey','capture-real',
    'originalOperationType','  musculacao  ','workoutLogID',ra->'workout_log_id','resolution','sql_replay');
  ef:=jsonb_build_object('anchor',jsonb_build_object('ownerID',a,'workoutLogID',ra->'workout_log_id','lifecycleKey',la,
    'snapshotID',ra->'snapshot_id','storedWorkoutType','musculacao','performedAt','2026-10-12T15:00:00.123456Z','snapshotDate','2026-10-12'),
    'classification',jsonb_build_object('status','matched','observation',jsonb_build_object(
      'observedAt','2026-10-12T14:59:59.000001Z','matcherVersion','active_slug_then_unique_canonical_display_v1',
      'observationKey','c59a6000-0000-0000-0000-000000000010'),'method','active_slug',
      'catalogue',jsonb_build_object('id','c59a6000-0000-0000-0000-000000000011','slug','peito_triceps','displayName','Peito e tríceps',
        'category','musculacao','isActive',true,'updatedAtLiteral','2026-10-10T01:02:03.000002Z')),
    'calendar',jsonb_build_object('status','proven','performedAt','2026-10-12T15:00:00.123456Z','localDate','2026-10-12',
      'timeZone','America/Sao_Paulo','zoneSource','official_owner_zone_at_recording','zoneObservedAt','2026-10-12T14:59:58.000003Z',
      'snapshotID',ra->'snapshot_id','snapshotDate','2026-10-12'),
    'clarification',jsonb_build_object('status','not_applicable'),'revision',0);
  s:=jsonb_build_object('a',a,'b',b,'la',la,'lb',lb,'wa',ra->'workout_log_id','wb',rb->'workout_log_id',
    'ra',ra,'rb',rb,'replay',replay,'f',f,'fb',fb,'op',op,'expected_fact',ef,'expected_binding',binding,'question',q,
    'row_b',(SELECT to_jsonb(w) FROM public.workout_logs w WHERE id=(rb->>'workout_log_id')::uuid),
    'snapshot_b',(SELECT to_jsonb(d) FROM public.daily_snapshots d WHERE id=(rb->>'snapshot_id')::uuid));
  PERFORM set_config('c59s5_test.state',s::text,true);
END $actual_anchor$;

DO $strict_wire$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;r jsonb;
BEGIN
  r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
  PERFORM c59s5_fixture.ok(r=jsonb_build_object('status','reuse_existing','binding',s->'expected_binding','fact',s->'expected_fact'),
    'exact_R2_matched_proven_wire_US6_no_active_count_under_nonUTC_DateStyle');
  PERFORM c59s5_fixture.ok(private.workout_strength_fact_snapshot((s->>'a')::uuid,(s->>'la')::uuid,(s->>'wa')::uuid)=s->'expected_fact'
    AND private.workout_strength_fact_snapshot((s->>'b')::uuid,(s->>'la')::uuid,(s->>'wa')::uuid) IS NULL,
    'private_shared_guard_owned_join_and_foreign_SQLNULL');
  PERFORM c59s5_fixture.ok(to_regclass('public.workout_types') IS NULL
    AND r#>>'{fact,anchor,snapshotDate}'='2026-10-12'
    AND r#>>'{fact,anchor,snapshotID}'=s#>>'{ra,snapshot_id}'
    AND r#>>'{fact,anchor,snapshotID}'<>s#>>'{replay,snapshot_id}',
    'historical_catalogue_absent_and_actual_anchor12_not_response13');
END $strict_wire$;

-- Exact new shape and indexes, not a rerun of X4 storage regression.
DO $metadata$
DECLARE cols text[];types text[];
BEGIN
  SELECT array_agg(attname::text ORDER BY attnum),array_agg(format_type(atttypid,atttypmod) ORDER BY attnum)
    INTO cols,types FROM pg_attribute WHERE attrelid='private.workout_strength_facts'::regclass AND attnum>0 AND NOT attisdropped;
  PERFORM c59s5_fixture.ok(cols=ARRAY['user_id','workout_log_id','lifecycle_key','snapshot_id','stored_workout_type','performed_at','snapshot_date',
    'classification_status','classification_reason','observation_key','observed_at','matcher_version','active_row_count','match_method',
    'catalogue_id','catalogue_slug','catalogue_display_name','catalogue_category','catalogue_updated_at','calendar_status','calendar_reason',
    'local_date','time_zone','zone_source','zone_observed_at','question_key','answer','answer_operation_key','answer_accepted_at','revision']
    AND types=ARRAY['uuid','uuid','uuid','uuid','text','timestamp with time zone','date','text','text','uuid','timestamp with time zone',
      'text','bigint','text','uuid','text','text','text','timestamp with time zone','text','text','date','text','text','timestamp with time zone',
      'uuid','text','text','timestamp with time zone','integer'], 'facts_exact_thirty_columns_types');
  PERFORM c59s5_fixture.ok((SELECT bool_and(attnotnull=(attname IN('user_id','workout_log_id','lifecycle_key','snapshot_id',
      'stored_workout_type','performed_at','snapshot_date','classification_status','calendar_status','revision')))
    FROM pg_attribute WHERE attrelid='private.workout_strength_facts'::regclass AND attnum>0 AND NOT attisdropped)
    AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_facts'::regclass AND contype='p' AND conkey=ARRAY[1,2]::smallint[])
    AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_facts'::regclass AND contype='u' AND conkey=ARRAY[1,3,2]::smallint[])
    AND EXISTS(SELECT 1 FROM pg_index WHERE indrelid='private.workout_strength_facts'::regclass AND indisunique AND indpred IS NOT NULL
      AND pg_get_indexdef(indexrelid,1,true)='user_id' AND pg_get_indexdef(indexrelid,2,true)='question_key'),
    'facts_nullability_owned_PK_UNIQUE_question_partial');
  PERFORM c59s5_fixture.ok((SELECT indisunique AND indisvalid AND indnatts=2 AND indpred IS NULL
      AND pg_get_indexdef(indexrelid,1,true)='user_id' AND pg_get_indexdef(indexrelid,2,true)='id'
    FROM pg_index WHERE indexrelid='public.daily_snapshots_user_id_id_key'::regclass)
    AND (SELECT NOT indisunique AND indisvalid AND indnatts=2 AND indpred IS NULL
      AND pg_get_indexdef(indexrelid,1,true)='user_id' AND pg_get_indexdef(indexrelid,2,true)='snapshot_id'
    FROM pg_index WHERE indexrelid='private.workout_strength_facts_snapshot_lookup'::regclass),
    'facts_only_required_snapshot_owned_index_and_child_lookup');
END $metadata$;

-- Coherent owner-DML fixture states, not a public answer/edit/backfill API.
SAVEPOINT s5_branches;
DO $branches$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;f jsonb:=s->'f';u jsonb;v jsonb;r jsonb;reason text;answer_value text;receipt jsonb;
BEGIN
  u:=f||jsonb_build_object('classification_status','unrecognized','classification_reason','no_active_match','active_row_count',0,
    'match_method',NULL,'catalogue_id',NULL,'catalogue_slug',NULL,'catalogue_display_name',NULL,'catalogue_category',NULL,'catalogue_updated_at',NULL,
    'question_key',s->'question');
  v:=u||jsonb_build_object('classification_status','unavailable','classification_reason','catalogue_invalid','observation_key',NULL,
    'observed_at',NULL,'matcher_version',NULL,'active_row_count',NULL,'question_key',NULL);
  PERFORM set_config('c59s5_test.unknown',u::text,true);PERFORM set_config('c59s5_test.unavailable',v::text,true);
  FOREACH reason IN ARRAY ARRAY['no_active_match','ambiguous_active_name','generic_outro'] LOOP
    DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
    EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',u||jsonb_build_object('classification_reason',reason));
    r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
    PERFORM c59s5_fixture.ok(r->>'status'='reuse_existing' AND r#>'{fact,classification}'=jsonb_build_object('status','unrecognized',
      'observation',s#>'{expected_fact,classification,observation}','reason',reason)
      AND r#>'{fact,clarification}'=jsonb_build_object('status','unanswered','questionKey',s->'question')
      AND r#>'{fact,revision}'='0'::jsonb,'unrecognized_unanswered:'||reason);
  END LOOP;
  FOREACH answer_value IN ARRAY ARRAY['yes','no'] LOOP
    DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
    EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',
      u||jsonb_build_object('answer',answer_value,'answer_operation_key','stored-answer-'||answer_value,'answer_accepted_at','2026-10-12T15:02:03.654321Z','revision',1));
    r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
    receipt:=jsonb_build_object('ownerID',s->'a','workoutLogID',s->'wa','questionKey',s->'question','answer',answer_value,
      'operationKey','stored-answer-'||answer_value,'acceptedAt','2026-10-12T15:02:03.654321Z');
    PERFORM c59s5_fixture.ok(r#>'{fact,clarification}'=jsonb_build_object('status','answered','receipt',receipt)
      AND r#>'{fact,revision}'='1'::jsonb,'unrecognized_answered_exact_receipt:'||answer_value);
  END LOOP;
  FOREACH reason IN ARRAY ARRAY['catalogue_read_error','catalogue_invalid','catalogue_incomplete','legacy_provenance_gap'] LOOP
    DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
    EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',v||jsonb_build_object('classification_reason',reason));
    r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
    PERFORM c59s5_fixture.ok(r#>'{fact,classification}'=jsonb_build_object('status','unavailable','reason',reason)
      AND r#>'{fact,clarification}'='{"status":"not_applicable"}'::jsonb,'classification_unavailable_exact:'||reason);
  END LOOP;
  FOREACH reason IN ARRAY ARRAY['zone_unproved','calendar_conflict','legacy_calendar_gap'] LOOP
    DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
    EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',
      f||jsonb_build_object('calendar_status','unavailable','calendar_reason',reason,'local_date',NULL,'time_zone',NULL,'zone_source',NULL,'zone_observed_at',NULL));
    r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
    PERFORM c59s5_fixture.ok(r#>'{fact,calendar}'=jsonb_build_object('status','unavailable','reason',reason),
      'calendar_unavailable_exact:'||reason);
  END LOOP;
END $branches$;
-- Preserve only JSON fixture templates across this savepoint, not product rows.
SELECT current_setting('c59s5_test.unknown') AS unknown_template,current_setting('c59s5_test.unavailable') AS unavailable_template
\gset s5_
ROLLBACK TO SAVEPOINT s5_branches;
RELEASE SAVEPOINT s5_branches;
SELECT set_config('c59s5_test.unknown',:'s5_unknown_template',true),set_config('c59s5_test.unavailable',:'s5_unavailable_template',true);

SAVEPOINT s5_constraints;
DO $constraints$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;f jsonb:=s->'f';u jsonb:=current_setting('c59s5_test.unknown')::jsonb;
  v jsonb:=current_setting('c59s5_test.unavailable')::jsonb;x record;patch jsonb;
BEGIN
  PERFORM c59s5_fixture.throws(format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',f),
    '23505',NULL,'facts_duplicate_owned_UUID');
  DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
  FOR x IN SELECT * FROM (VALUES
    ('null_status','{"classification_status":null}'::jsonb,'23502'),
    ('null_revision','{"revision":null}'::jsonb,'23502'),
    ('null_count','{"active_row_count":null}'::jsonb,'23514'),
    ('zero_matched_count','{"active_row_count":0}'::jsonb,'23514'),
    ('null_method','{"match_method":null}'::jsonb,'23514'),
    ('null_catalogue','{"catalogue_id":null}'::jsonb,'23514'),
    ('other_category','{"catalogue_category":"strength"}'::jsonb,'23514'),
    ('generic_matched','{"catalogue_slug":"outro"}'::jsonb,'23514'),
    ('null_matcher','{"matcher_version":null}'::jsonb,'23514'),
    ('matched_question',jsonb_build_object('question_key',s->'question'),'23514'),
    ('matched_revision','{"revision":1}'::jsonb,'23514'),
    ('null_zone_source','{"zone_source":null}'::jsonb,'23514'),
    ('empty_proven_zone','{"time_zone":""}'::jsonb,'23514'),
    ('calendar_date_conflict','{"local_date":"2026-10-13"}'::jsonb,'23514'),
    ('performed_infinity','{"performed_at":"infinity"}'::jsonb,'23514'),
    ('observed_infinity','{"observed_at":"infinity"}'::jsonb,'23514'),
    ('catalogue_year10000','{"catalogue_updated_at":"10000-01-01T00:00:00Z"}'::jsonb,'23514'),
    ('zone_infinity','{"zone_observed_at":"infinity"}'::jsonb,'23514'),
    ('date_infinity','{"snapshot_date":"infinity","local_date":"infinity"}'::jsonb,'23514'),
    ('raw_blank','{"stored_workout_type":"   "}'::jsonb,'23514')
  )t(label,change,state) LOOP
    PERFORM c59s5_fixture.throws(format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',f||x.change),
      x.state,NULL,'facts_matched_invalid:'||x.label);
  END LOOP;
  FOR x IN SELECT * FROM (VALUES
    ('null_question','{"question_key":null}'::jsonb),
    ('null_reason','{"classification_reason":null}'::jsonb),
    ('negative_count','{"active_row_count":-1}'::jsonb),
    ('mixed_catalogue','{"catalogue_slug":"outro"}'::jsonb),
    ('revision_without_answer','{"revision":1}'::jsonb),
    ('answer_null',jsonb_build_object('revision',1,'answer',NULL,'answer_operation_key','stored','answer_accepted_at','2026-10-12T15:02:03Z')),
    ('answer_infinity','{"revision":1,"answer":"yes","answer_operation_key":"stored","answer_accepted_at":"infinity"}'::jsonb)
  )t(label,change) LOOP
    PERFORM c59s5_fixture.throws(format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',u||x.change),
      '23514',NULL,'facts_unrecognized_invalid:'||x.label);
  END LOOP;
  FOR x IN SELECT * FROM (VALUES
    ('null_reason','{"classification_reason":null}'::jsonb),
    ('observation_leak',jsonb_build_object('observation_key','c59a6000-0000-0000-0000-000000000010')),
    ('revision_one','{"revision":1}'::jsonb)
  )t(label,change) LOOP
    PERFORM c59s5_fixture.throws(format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',v||x.change),
      '23514',NULL,'facts_unavailable_invalid:'||x.label);
  END LOOP;
  PERFORM c59s5_fixture.throws(format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',
    f||'{"calendar_status":"unavailable","calendar_reason":null,"local_date":null,"time_zone":null,"zone_source":null,"zone_observed_at":null}'::jsonb),
    '23514',NULL,'facts_calendar_unavailable_NULL_reason');
  FOR x IN SELECT * FROM (VALUES
    ('lifecycle',jsonb_build_object('lifecycle_key',s->'lb')),
    ('workout',jsonb_build_object('workout_log_id',s->'wb')),
    ('snapshot',jsonb_build_object('snapshot_id',s#>'{rb,snapshot_id}'))
  )t(label,change) LOOP
    PERFORM c59s5_fixture.throws(format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',f||x.change),
      '23503',NULL,'facts_owned_FK:'||x.label);
  END LOOP;
END $constraints$;
ROLLBACK TO SAVEPOINT s5_constraints;
RELEASE SAVEPOINT s5_constraints;

SAVEPOINT s5_F1;
DO $f1$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;r jsonb;op jsonb;
BEGIN
  op:=s->'op'||jsonb_build_object('original_operation_type','musculacao','resolution','provider_type_dedup','legacy_result',NULL);
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',op);
  r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','musculacao');
  PERFORM c59s5_fixture.ok(r->>'status'='reuse_existing' AND r#>>'{binding,originalOperationType}'='musculacao'
    AND r#>>'{binding,resolution}'='provider_type_dedup' AND r->'fact'=s->'expected_fact','F1_space_variant_exact_binding_preserved');
  r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','MUSCULACAO');
  PERFORM c59s5_fixture.ok(r='{"status":"unavailable","reason":"operation_key_missing","confirmedWorkoutLogID":null}'::jsonb,
    'F1_case_does_not_canonicalize_or_select_other_raw_type');
  op:=s->'op'||jsonb_build_object('operation_kind','answer','operation_key','answer-only','original_operation_type',NULL,
    'resolution',NULL,'capture_outcome',NULL,'legacy_result',NULL,'answer_expected_revision',0,'answer_question_key',s->'question',
    'answer_value','yes','answer_receipt',jsonb_build_object('ownerID',s->'a','workoutLogID',s->'wa','questionKey',s->'question',
      'answer','yes','operationKey','answer-only','acceptedAt','2026-10-12T15:02:03Z'));
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',op);
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'answer-only','musculacao')=
    '{"status":"unavailable","reason":"operation_key_missing","confirmedWorkoutLogID":null}'::jsonb,'capture_resolver_ignores_answer_binding');
END $f1$;
ROLLBACK TO SAVEPOINT s5_F1;
RELEASE SAVEPOINT s5_F1;

SAVEPOINT s5_history;
UPDATE public.users SET timezone='S5_current_zone_not_in_catalogue' WHERE id=(current_setting('c59s5_test.state')::jsonb->>'a')::uuid;
DO $historical$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;
BEGIN
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ')=
    jsonb_build_object('status','reuse_existing','binding',s->'expected_binding','fact',s->'expected_fact'),
    'current_unknown_zone_and_absent_catalogue_do_not_reclassify_history');
END $historical$;
ROLLBACK TO SAVEPOINT s5_history;
RELEASE SAVEPOINT s5_history;

SAVEPOINT s5_bad_anchor;
DO $bad_anchor$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;x record;f jsonb:=s->'f';r jsonb;old_life uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.workout_strength_lifecycles VALUES
    ((s->>'a')::uuid,old_life,'2026-09-01T00:00:00Z','2026-09-30T00:00:00Z','S5-historical-close');
  FOR x IN SELECT * FROM (VALUES
    ('lifecycle',jsonb_build_object('lifecycle_key',old_life)),
    ('snapshot_response13',jsonb_build_object('snapshot_id',s#>'{replay,snapshot_id}','snapshot_date','2026-10-13','local_date','2026-10-13')),
    ('stored_type','{"stored_workout_type":"other-original"}'::jsonb),
    ('performed_at','{"performed_at":"2026-10-12T15:00:01.123456Z"}'::jsonb),
    ('snapshot_date','{"snapshot_date":"2026-10-13","local_date":"2026-10-13"}'::jsonb)
  )t(label,change) LOOP
    DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
    EXECUTE format('INSERT INTO private.workout_strength_facts SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_facts,%L::jsonb)',f||x.change);
    r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
    PERFORM c59s5_fixture.ok(private.workout_strength_fact_snapshot((s->>'a')::uuid,(s->>'la')::uuid,(s->>'wa')::uuid) IS NULL
      AND r='{"status":"forbidden","reason":"stale_workout"}'::jsonb,'shared_anchor_guard_rejects:'||x.label);
  END LOOP;
  DELETE FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid AND workout_log_id=(s->>'wa')::uuid;
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ')=
    '{"status":"forbidden","reason":"stale_workout"}'::jsonb,'fact_binding_missing_fact_never_fabricates');
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    s->'op'||jsonb_build_object('operation_key','legacy-gap','resolution','provider_type_dedup','capture_outcome','legacy_provenance_gap','legacy_result',NULL));
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'legacy-gap','  musculacao  ')=
    jsonb_build_object('status','unavailable','reason','legacy_provenance_gap','confirmedWorkoutLogID',s->'wa')
    AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid),
    'gap_binding_keeps_actual_UUID_without_fact_backfill');
END $bad_anchor$;
ROLLBACK TO SAVEPOINT s5_bad_anchor;
RELEASE SAVEPOINT s5_bad_anchor;

SAVEPOINT s5_closed;
UPDATE private.workout_strength_lifecycles SET closed_at='2026-10-14T15:00:00Z',close_operation_key='S5-close'
WHERE user_id=(current_setting('c59s5_test.state')::jsonb->>'a')::uuid;
DO $closed$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;
BEGIN
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'missing-key','musculacao')=
    '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'closed_lifecycle_precedes_binding_lookup');
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ')=
    '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'closed_lifecycle_denies_existing_replay');
END $closed$;
ROLLBACK TO SAVEPOINT s5_closed;
RELEASE SAVEPOINT s5_closed;

DO $guards$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;x record;
BEGIN
  FOR x IN SELECT * FROM (VALUES
    ('owner',NULL::text,s->>'la','key','musculacao'),
    ('life',s->>'a',NULL::text,'key','musculacao'),
    ('key_null',s->>'a',s->>'la',NULL::text,'musculacao'),
    ('key_empty',s->>'a',s->>'la','','musculacao'),
    ('type_null',s->>'a',s->>'la','key',NULL::text),
    ('type_blank',s->>'a',s->>'la','key','   ')
  )t(label,owner_id,life,key,raw_type) LOOP
    PERFORM c59s5_fixture.throws(format('SELECT public.resolve_confirmed_workout_strength_capture(%L::uuid,%L::uuid,%L,%L)',x.owner_id,x.life,x.key,x.raw_type),
      '22023','invalid_workout_strength_input','syntax_invalid:'||x.label);
  END LOOP;
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,' ','musculacao')=
    '{"status":"unavailable","reason":"operation_key_missing","confirmedWorkoutLogID":null}'::jsonb,'nonempty_key_not_trimmed_or_new_regex');
  PERFORM c59s5_fixture.throws(format('SELECT public.resolve_confirmed_workout_strength_capture(%L,%L,%L,%L)',gen_random_uuid(),s->>'la','key','musculacao'),
    'P0002','workout_strength_patient_not_found','missing_owner_P0002');
  PERFORM c59s5_fixture.ok(public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'lb')::uuid,'capture-b','natacao')=
    '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'foreign_lifecycle_never_reads_other_owner_binding');
END $guards$;
SAVEPOINT s5_inactive;
UPDATE public.users SET status='deleted' WHERE id=(current_setting('c59s5_test.state')::jsonb->>'a')::uuid;
SELECT c59s5_fixture.throws(format('SELECT public.resolve_confirmed_workout_strength_capture(%L,%L,%L,%L)',
  current_setting('c59s5_test.state')::jsonb->>'a',current_setting('c59s5_test.state')::jsonb->>'lb','missing-key','musculacao'),
  'P0002','workout_strength_patient_not_found','inactive_owner_before_lifecycle_lookup');
ROLLBACK TO SAVEPOINT s5_inactive;
RELEASE SAVEPOINT s5_inactive;

SAVEPOINT s5_snapshot_delete;
DELETE FROM public.daily_snapshots WHERE id=(current_setting('c59s5_test.state')::jsonb#>>'{ra,snapshot_id}')::uuid;
DO $snapshot_delete$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;
BEGIN
  PERFORM c59s5_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid)
    AND public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ')=
      '{"status":"forbidden","reason":"stale_workout"}'::jsonb,'actual_snapshot_delete_cascades_fact_and_refuses_stale_UUID');
END $snapshot_delete$;
ROLLBACK TO SAVEPOINT s5_snapshot_delete;
RELEASE SAVEPOINT s5_snapshot_delete;

-- Permission checks before correction while valid owned data still exists.
DO $permissions$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;p record;h record;role_name text;code text;r jsonb;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid='public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure;
  SELECT * INTO h FROM pg_proc WHERE oid='private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure;
  PERFORM c59s5_fixture.ok(p.prosecdef AND p.provolatile='v' AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND NOT h.prosecdef AND h.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND NOT has_function_privilege('service_role',h.oid,'EXECUTE')
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(h.proacl,acldefault('f',h.proowner))) a WHERE a.grantee<>h.proowner),
    'resolver_definer_and_private_invoker_guard_owner_only');
  PERFORM c59s5_fixture.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.workout_strength_facts'::regclass)
    AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.workout_strength_facts'::regclass)
    AND NOT EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE c.oid='private.workout_strength_facts'::regclass AND a.grantee<>c.relowner),
    'facts_RLS_no_policies_owner_only_ACL');
  EXECUTE 'SET LOCAL ROLE service_role';
  r:=public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
  EXECUTE 'RESET ROLE';
  PERFORM c59s5_fixture.ok(r->>'status'='reuse_existing','service_role_real_resolver_without_direct_fact_permission');
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    PERFORM c59s5_fixture.ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'resolver_EXECUTE_denied:'||role_name);
    EXECUTE format('SET LOCAL ROLE %I',role_name);code:=NULL;
    BEGIN PERFORM public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ');
    EXCEPTION WHEN OTHERS THEN code:=SQLSTATE;END;
    EXECUTE 'RESET ROLE';
    PERFORM c59s5_fixture.ok(code='42501','resolver_real_ACL_denial:'||role_name);
  END LOOP;
  PERFORM c59s5_fixture.ok(NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE a.grantee NOT IN(p.proowner,(SELECT oid FROM pg_roles WHERE rolname='service_role')) OR a.privilege_type<>'EXECUTE'
      OR (a.grantee=(SELECT oid FROM pg_roles WHERE rolname='service_role') AND a.is_grantable)),
    'resolver_public_ACL_no_PUBLIC_or_extra_grant');
END $permissions$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59s5_fixture.throws('SELECT public.resolve_confirmed_workout_strength_capture(NULL,NULL,NULL,NULL)',
  '42501','trusted backend role required','trusted_guard_before_invalid_syntax');
SET LOCAL request.jwt.claims='{"role":"service_role"}';

DO $correction$
DECLARE s jsonb:=current_setting('c59s5_test.state')::jsonb;r jsonb;
BEGIN
  r:=public.register_workout_atomic((s->>'a')::uuid,DATE'2026-10-12','musculacao',80,400,'moderada','S5 real correction',
    '2026-10-12T16:00:00.123456Z','c59s5-provider-correct',2000,150,true,'2000-01-01T00:00:00Z');
  PERFORM c59s5_fixture.ok(r->'inserted'='true'::jsonb AND r->>'replaced_count'='1' AND r->>'workout_log_id'<>s->>'wa'
    AND r->>'exercise_calories'='400' AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=(s->>'a')::uuid),
    'real_legacy_correction_new_UUID_400_fact_cascade');
  PERFORM c59s5_fixture.ok((SELECT live_workout_log_id IS NULL AND original_workout_log_id=(s->>'wa')::uuid
      FROM private.workout_strength_operations WHERE user_id=(s->>'a')::uuid AND operation_key='capture-real')
    AND public.resolve_confirmed_workout_strength_capture((s->>'a')::uuid,(s->>'la')::uuid,'capture-real','  musculacao  ')=
      '{"status":"forbidden","reason":"stale_workout"}'::jsonb,'correction_tombstone_no_rebind_to_replacement');
  PERFORM c59s5_fixture.ok((SELECT to_jsonb(w)=s->'row_b' FROM public.workout_logs w WHERE id=(s->>'wb')::uuid)
    AND (SELECT to_jsonb(d)=s->'snapshot_b' AND exercise_calories=200 FROM public.daily_snapshots d WHERE id=(s#>>'{rb,snapshot_id}')::uuid)
    AND public.resolve_confirmed_workout_strength_capture((s->>'b')::uuid,(s->>'lb')::uuid,'capture-b','natacao')->>'status'='reuse_existing',
    'other_owner_real_row_snapshot_200_and_fact_unchanged');
END $correction$;
SELECT c59s5_fixture.ok((SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,
  'owner',p.proowner::text,'config',p.proconfig,'comment',obj_description(p.oid,'pg_proc'),
  'trusted_guard',(SELECT jsonb_build_object('definition',pg_get_functiondef(g.oid),'acl',g.proacl::text,
    'owner',g.proowner::text,'config',g.proconfig,'comment',obj_description(g.oid,'pg_proc'))
    FROM pg_proc g WHERE g.oid='private.assert_trusted_backend()'::regprocedure))::text)
  FROM pg_proc p WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure)=:'s5_legacy_fingerprint',
  'legacy_API_and_trusted_guard_definition_ACL_preserved');
ROLLBACK;
SELECT (to_regclass('public.daily_snapshots') IS NULL AND to_regclass('public.workout_logs') IS NULL
  AND to_regclass('private.workout_strength_facts') IS NULL AND to_regclass('private.workout_strength_operations') IS NULL
  AND to_regclass('private.workout_strength_lifecycles') IS NULL AND to_regnamespace('c59s5_fixture') IS NULL
  AND to_regprocedure('private.workout_strength_fact_snapshot(uuid,uuid,uuid)') IS NULL
  AND to_regprocedure('public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)') IS NULL
  AND NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='register_workout_atomic')
  AND(SELECT count(*) FROM public.users)=:'s5_baseline_users'::bigint) AS rollback_ok
\gset s5_
\if :s5_rollback_ok
\echo C59S5_ROLLBACK_CONFIRMED
\else
DO $$BEGIN RAISE EXCEPTION 'C59S5_ROLLBACK_MISMATCH';END$$;
\endif
-- Root independently verifies fresh full baseline equality and owned stop.

-- X4 relational-storage test first; no future capture/answer RPC is simulated.
-- Root binds ALL three exact local files and the exclusive synthetic target.
\set ON_ERROR_STOP on
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59X4_SETUP_MIGRATION_PATH_REQUIRED';END$$;
\endif
\if :{?legacy_api_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59X4_SETUP_LEGACY_API_PATH_REQUIRED';END$$;
\endif
\if :{?legacy_permissions_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59X4_SETUP_LEGACY_PERMISSIONS_PATH_REQUIRED';END$$;
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $setup$
BEGIN
  IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL
  THEN RAISE EXCEPTION 'C59X4_SETUP_PLATFORM_SUBSTRATE_MISSING';END IF;
  IF to_regclass('public.daily_snapshots') IS NOT NULL OR to_regclass('public.workout_logs') IS NOT NULL
    OR to_regclass('private.workout_strength_lifecycles') IS NOT NULL
    OR to_regclass('private.workout_strength_operations') IS NOT NULL
    OR to_regnamespace('c59x4_fixture') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='register_workout_atomic')
  THEN RAISE EXCEPTION 'C59X4_SETUP_UNKNOWN_EXISTING_OBJECT';END IF;
END $setup$;
SELECT count(*) AS baseline_users FROM public.users
\gset x4_
\ir fixtures/workout_strength_bindings_fixture.sql
\i :legacy_api_path
\i :legacy_permissions_path
SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,
  'owner',p.proowner::text,'config',p.proconfig,'security_definer',p.prosecdef,
  'comment',obj_description(p.oid,'pg_proc'))::text) AS legacy_fingerprint
FROM pg_proc p WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure
\gset x4_

-- Real pre-existing data: owner local invokes the unchanged INVOKER API; no
-- extra grants to bypass original RLS and no manufactured workout UUIDs.
DO $legacy_before$
DECLARE a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();ra jsonb;rb jsonb;s jsonb;
BEGIN
  INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES
    (a,'c59x4-a-'||a,'C59X4 synthetic A','America/Sao_Paulo','{"c59a2_synthetic":true}'),
    (b,'c59x4-b-'||b,'C59X4 synthetic B','America/Sao_Paulo','{"c59a2_synthetic":true}');
  ra:=public.register_workout_atomic(a,'2026-10-12','musculacao',60,300,'moderada','X4 A',
    '2026-10-12T15:00:00Z','c59x4-provider-a',2000,150,false,NULL);
  rb:=public.register_workout_atomic(b,'2026-10-12','musculacao',40,200,'moderada','X4 B',
    '2026-10-12T15:00:00Z','c59x4-provider-b',1800,100,false,NULL);
  PERFORM c59x4_fixture.ok(ra->'inserted'='true'::jsonb AND rb->'inserted'='true'::jsonb
    AND ra->>'exercise_calories'='300' AND rb->>'exercise_calories'='200'
    AND (SELECT count(*)=2 FROM public.workout_logs WHERE user_id IN(a,b))
    AND (SELECT count(*)=2 FROM public.daily_snapshots WHERE user_id IN(a,b))
    AND (SELECT estimated_kcal=300 AND user_id=a AND snapshot_id=(ra->>'snapshot_id')::uuid
      FROM public.workout_logs WHERE id=(ra->>'workout_log_id')::uuid),
    'legacy_two_real_rows_before_migration');
  s:=jsonb_build_object('a',a,'b',b,'wa',ra->'workout_log_id','wb',rb->'workout_log_id',
    'legacy_a',ra,'legacy_b',rb,'life_a',gen_random_uuid(),'life_b',gen_random_uuid(),
    'row_a',(SELECT to_jsonb(w) FROM public.workout_logs w WHERE id=(ra->>'workout_log_id')::uuid),
    'row_b',(SELECT to_jsonb(w) FROM public.workout_logs w WHERE id=(rb->>'workout_log_id')::uuid),
    'snapshot_b',(SELECT to_jsonb(d) FROM public.daily_snapshots d WHERE id=(rb->>'snapshot_id')::uuid));
  PERFORM set_config('c59x4_test.state',s::text,true);
END $legacy_before$;

-- The future product migration is Root-bound; absence/compile errors are SETUP.
\i :migration_path
DO $installed$
BEGIN
  IF to_regclass('private.workout_strength_lifecycles') IS NULL
    OR to_regclass('private.workout_strength_operations') IS NULL
  THEN RAISE EXCEPTION 'C59X4_SETUP_STORAGE_UNIMPLEMENTED';END IF;
END $installed$;
SELECT c59x4_fixture.ok((SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),
  'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,'security_definer',p.prosecdef,
  'comment',obj_description(p.oid,'pg_proc'))::text) FROM pg_proc p
  WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure)=:'x4_legacy_fingerprint',
  'legacy_api_definition_ACL_unchanged_after_migration');

DO $shape_replay$
DECLARE s jsonb:=current_setting('c59x4_test.state')::jsonb;r jsonb;
BEGIN
  PERFORM c59x4_fixture.ok((SELECT array_agg(attname::text ORDER BY attnum)=
    ARRAY['user_id','lifecycle_key','opened_at','closed_at','close_operation_key']
    FROM pg_attribute WHERE attrelid='private.workout_strength_lifecycles'::regclass
      AND attnum>0 AND NOT attisdropped)
    AND (SELECT array_agg(format_type(atttypid,atttypmod) ORDER BY attnum)=
      ARRAY['uuid','uuid','timestamp with time zone','timestamp with time zone','text']
      AND bool_and(attnotnull=(attname IN('user_id','lifecycle_key','opened_at')))
      FROM pg_attribute WHERE attrelid='private.workout_strength_lifecycles'::regclass
        AND attnum>0 AND NOT attisdropped)
    AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_lifecycles'::regclass
      AND contype='p' AND conkey=ARRAY[1,2]::smallint[]),'lifecycle_exact_five_columns');
  PERFORM c59x4_fixture.ok((SELECT array_agg(attname::text ORDER BY attnum)=
    ARRAY['user_id','lifecycle_key','operation_kind','operation_key','original_operation_type',
      'original_workout_log_id','live_workout_log_id','created_at','resolution','capture_outcome',
      'legacy_result','answer_expected_revision','answer_question_key','answer_value','answer_receipt']
    FROM pg_attribute WHERE attrelid='private.workout_strength_operations'::regclass
      AND attnum>0 AND NOT attisdropped)
    AND (SELECT bool_and(attcollation='pg_catalog."C"'::regcollation) FROM pg_attribute
      WHERE attrelid='private.workout_strength_operations'::regclass
        AND attname IN('operation_key','original_operation_type'))
    AND (SELECT array_agg(format_type(atttypid,atttypmod) ORDER BY attnum)=
      ARRAY['uuid','uuid','text','text','text','uuid','uuid','timestamp with time zone',
        'text','text','jsonb','integer','uuid','text','jsonb']
      AND bool_and(attnotnull=(attname IN('user_id','lifecycle_key','operation_kind','operation_key',
        'original_workout_log_id','created_at')))
      FROM pg_attribute WHERE attrelid='private.workout_strength_operations'::regclass
        AND attnum>0 AND NOT attisdropped),
    'operations_exact_fifteen_columns_and_C_literals');
  PERFORM c59x4_fixture.ok((SELECT i.indisunique AND i.indisvalid AND i.indnatts=2
      AND i.indpred IS NULL AND pg_get_indexdef(i.indexrelid,1,true)='user_id'
      AND pg_get_indexdef(i.indexrelid,2,true)='id'
    FROM pg_index i WHERE i.indexrelid='public.workout_logs_user_id_id_key'::regclass)
    AND to_regclass('public.daily_snapshots_user_id_id_key') IS NULL,
    'only_required_workout_composite_index');
  PERFORM c59x4_fixture.ok((SELECT to_jsonb(w)=s->'row_a' FROM public.workout_logs w WHERE id=(s->>'wa')::uuid)
    AND (SELECT to_jsonb(w)=s->'row_b' FROM public.workout_logs w WHERE id=(s->>'wb')::uuid),
    'new_index_preserves_both_existing_workouts');
  r:=public.register_workout_atomic((s->>'a')::uuid,'2026-10-12','musculacao',60,300,'moderada','X4 A',
    '2026-10-12T15:00:00Z','c59x4-provider-a',2000,150,false,NULL);
  PERFORM c59x4_fixture.ok(r->'inserted'='false'::jsonb AND r->>'workout_log_id'=s->>'wa'
    AND r->>'snapshot_id'=s#>>'{legacy_a,snapshot_id}' AND r->>'exercise_calories'='300'
    AND r->>'replaced_count'='0' AND (SELECT count(*)=1 FROM public.workout_logs WHERE user_id=(s->>'a')::uuid),
    'legacy_replay_after_index_same_UUID_official_300');
  PERFORM set_config('c59x4_test.state',(s||jsonb_build_object('legacy_replay',r))::text,true);
END $shape_replay$;

DO $lifecycles$
DECLARE s jsonb:=current_setting('c59x4_test.state')::jsonb;a uuid:=(s->>'a')::uuid;b uuid:=(s->>'b')::uuid;
  la uuid:=(s->>'life_a')::uuid;lb uuid:=(s->>'life_b')::uuid;next_la uuid:=gen_random_uuid();x record;
BEGIN
  INSERT INTO private.workout_strength_lifecycles VALUES(a,la,'2026-10-01T00:00:00Z',NULL,NULL);
  PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_lifecycles VALUES(%L,%L,%L,NULL,NULL)',
    a,gen_random_uuid(),'2026-10-02T00:00:00Z'),'23505','life_one_open_owner');
  FOR x IN SELECT * FROM (VALUES
    ('closed_without_key','2026-10-02T00:00:00Z'::text,NULL::text),
    ('key_without_closed',NULL::text,'close-key'),
    ('closed_before_open','2026-09-30T00:00:00Z','close-key'),
    ('empty_close_key','2026-10-02T00:00:00Z','')
  ) t(label,closed_at,close_key) LOOP
    PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_lifecycles VALUES(%L,%L,%L,%L,%L)',
      b,gen_random_uuid(),'2026-10-01T00:00:00Z',x.closed_at,x.close_key),'23514','life_'||x.label);
  END LOOP;
  PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_lifecycles VALUES(%L,%L,%L,NULL,NULL)',
    gen_random_uuid(),gen_random_uuid(),'2026-10-01T00:00:00Z'),'23503','life_owned_user_FK');
  UPDATE private.workout_strength_lifecycles SET closed_at='2026-10-03T00:00:00Z',close_operation_key='close-original'
    WHERE user_id=a AND lifecycle_key=la;
  INSERT INTO private.workout_strength_lifecycles VALUES
    (a,next_la,'2026-10-04T00:00:00Z',NULL,NULL),(b,lb,'2026-10-01T00:00:00Z',NULL,NULL);
  PERFORM c59x4_fixture.ok((SELECT count(*)=2 FROM private.workout_strength_lifecycles WHERE user_id=a)
    AND (SELECT count(*)=1 FROM private.workout_strength_lifecycles WHERE user_id=a AND closed_at IS NULL),
    'life_closed_history_and_new_identity_storage');
  PERFORM set_config('c59x4_test.state',(s||jsonb_build_object('life_a',next_la,'history_life_a',la))::text,true);
END $lifecycles$;

-- Owner DML below tests storage constraints only; no provenance/admission API.
DO $operations$
DECLARE s jsonb:=current_setting('c59x4_test.state')::jsonb;cap jsonb;ans jsonb;receipt jsonb;patch jsonb;
  q uuid:=gen_random_uuid();x record;raw text;result jsonb;
BEGIN
  cap:=jsonb_build_object('user_id',s->'a','lifecycle_key',s->'life_a','operation_kind','capture',
    'operation_key','capture-original','original_operation_type','musculacao',
    'original_workout_log_id',s->'wa','live_workout_log_id',s->'wa','created_at','2026-10-12T15:00:00Z',
    'resolution','sql_insert','capture_outcome','fact','legacy_result',s->'legacy_a') ||
    '{"answer_expected_revision":null,"answer_question_key":null,"answer_value":null,"answer_receipt":null}'::jsonb;
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',cap);
  FOREACH raw IN ARRAY ARRAY['musculacao','MUSCULACAO','  musculacao  '] LOOP
    EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
      cap||jsonb_build_object('operation_key','raw-key / ç','original_operation_type',raw));
  END LOOP;
  PERFORM c59x4_fixture.ok((SELECT array_agg(original_operation_type ORDER BY original_operation_type COLLATE "C")=
      ARRAY['  musculacao  ','MUSCULACAO','musculacao'] FROM private.workout_strength_operations
      WHERE user_id=(s->>'a')::uuid AND operation_key='raw-key / ç'),
    'capture_exact_raw_case_space_variants_no_new_key_regex');
  PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',cap),
    '23505','capture_exact_tuple_duplicate_denied');
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    cap||jsonb_build_object('user_id',s->'b','lifecycle_key',s->'life_b','original_workout_log_id',s->'wb','live_workout_log_id',s->'wb','legacy_result',s->'legacy_b'));
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    cap||jsonb_build_object('lifecycle_key',s->'history_life_a'));
  PERFORM c59x4_fixture.ok((SELECT count(*)=3 FROM private.workout_strength_operations WHERE operation_key='capture-original'),
    'capture_owner_and_lifecycle_addresses_distinct_storage_only');
  FOR x IN SELECT * FROM (VALUES
    ('wrong_lifecycle',jsonb_build_object('lifecycle_key',s->'life_b')),
    ('wrong_live_owner',jsonb_build_object('original_workout_log_id',s->'wb','live_workout_log_id',s->'wb'))
  )t(label,change) LOOP
    PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
      cap||x.change||jsonb_build_object('operation_key','bad-'||x.label)),'23503','capture_'||x.label);
  END LOOP;
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    cap||jsonb_build_object('operation_key','original-without-live','original_workout_log_id',gen_random_uuid(),
      'live_workout_log_id',NULL,'resolution','provider_type_dedup','capture_outcome','legacy_provenance_gap','legacy_result',NULL));
  PERFORM c59x4_fixture.ok((SELECT live_workout_log_id IS NULL FROM private.workout_strength_operations
    WHERE operation_key='original-without-live'),'original_UUID_nonFK_tombstone_storage');
  FOR x IN SELECT * FROM (VALUES
    ('sql_replay',s->'legacy_replay'),('provider_type_dedup',NULL::jsonb),('recent6h_dedup',NULL::jsonb)
  )t(resolution,legacy) LOOP
    EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
      cap||jsonb_build_object('operation_key','resolution-'||x.resolution,'resolution',x.resolution,
        'capture_outcome','legacy_provenance_gap','legacy_result',x.legacy));
  END LOOP;
  PERFORM c59x4_fixture.ok((SELECT count(*)=3 FROM private.workout_strength_operations WHERE operation_key LIKE 'resolution-%'),
    'capture_four_resolution_shapes_with_real_legacy_JSON');
  FOR x IN SELECT * FROM (VALUES
    ('null_type','{"original_operation_type":null}'::jsonb,'23514'),
    ('space_type','{"original_operation_type":"   "}'::jsonb,'23514'),
    ('null_resolution','{"resolution":null}'::jsonb,'23514'),
    ('null_outcome','{"capture_outcome":null}'::jsonb,'23514'),
    ('unknown_outcome','{"capture_outcome":"other"}'::jsonb,'23514'),
    ('unknown_resolution','{"resolution":"other"}'::jsonb,'23514'),
    ('insert_gap','{"capture_outcome":"legacy_provenance_gap"}'::jsonb,'23514'),
    ('missing_legacy','{"legacy_result":null}'::jsonb,'23514'),
    ('early_with_legacy','{"resolution":"recent6h_dedup"}'::jsonb,'23514'),
    ('capture_answer_mixed','{"answer_expected_revision":0}'::jsonb,'23514'),
    ('empty_key','{"operation_key":""}'::jsonb,'23514'),
    ('null_kind','{"operation_kind":null}'::jsonb,'23502'),
    ('null_key','{"operation_key":null}'::jsonb,'23502'),
    ('unknown_kind','{"operation_kind":"other"}'::jsonb,'23514'),
    ('live_original_diff',jsonb_build_object('live_workout_log_id',s->'wb'),'23514')
  )t(label,change,state) LOOP
    patch:=cap||jsonb_build_object('operation_key','bad-'||x.label)||x.change;
    PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',patch),
      x.state,'capture_invalid_'||x.label);
  END LOOP;
  receipt:=jsonb_build_object('ownerID',s->'a','workoutLogID',s->'wa','questionKey',q,'answer','yes',
    'operationKey','answer-A','acceptedAt','2026-10-12T15:00:00.123456Z');
  ans:=cap||jsonb_build_object('operation_kind','answer','operation_key','answer-A','original_operation_type',NULL,
    'resolution',NULL,'capture_outcome',NULL,'legacy_result',NULL,'answer_expected_revision',0,
    'answer_question_key',q,'answer_value','yes','answer_receipt',receipt);
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',ans);
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    ans||'{"operation_key":"answer-B","answer_expected_revision":1}'::jsonb);
  PERFORM c59x4_fixture.ok((SELECT answer_expected_revision=1 AND answer_receipt=receipt
      AND answer_receipt->>'operationKey'='answer-A' FROM private.workout_strength_operations
      WHERE user_id=(s->>'a')::uuid AND operation_kind='answer' AND operation_key='answer-B'),
    'answer_A0_B1_retains_B_content_and_A_winning_receipt');
  PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',ans),
    '23505','answer_own_key_unique');
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
    cap||'{"operation_key":"answer-A"}'::jsonb);
  PERFORM c59x4_fixture.ok((SELECT count(*)=2 FROM private.workout_strength_operations
    WHERE user_id=(s->>'a')::uuid AND lifecycle_key=(s->>'life_a')::uuid AND operation_key='answer-A'),
    'capture_and_answer_partial_keys_separate');
  FOR x IN SELECT * FROM (VALUES
    ('null_revision','{"answer_expected_revision":null}'::jsonb),
    ('negative_revision','{"answer_expected_revision":-1}'::jsonb),
    ('null_question','{"answer_question_key":null}'::jsonb),
    ('null_answer','{"answer_value":null}'::jsonb),
    ('unknown_answer','{"answer_value":"maybe"}'::jsonb),
    ('sql_null_receipt','{"answer_receipt":null}'::jsonb),
    ('mixed_capture_fields','{"original_operation_type":"musculacao"}'::jsonb)
  )t(label,change) LOOP
    PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
      ans||jsonb_build_object('operation_key','bad-answer-'||x.label)||x.change),'23514','answer_invalid_'||x.label);
  END LOOP;
  FOR x IN SELECT * FROM (VALUES
    ('json_null','null'::jsonb),
    ('missing_and_extra_key',(receipt-'acceptedAt')||'{"extra":"not-a-receipt-key"}'::jsonb),
    ('null_accepted_at',receipt||'{"acceptedAt":null}'::jsonb),
    ('numeric_operation_key',receipt||'{"operationKey":7}'::jsonb),
    ('empty_operation_key',receipt||'{"operationKey":""}'::jsonb),
    ('numeric_accepted_at',receipt||'{"acceptedAt":7}'::jsonb),
    ('empty_accepted_at',receipt||'{"acceptedAt":""}'::jsonb),
    ('wrong_owner',receipt||jsonb_build_object('ownerID',s->'b')),
    ('wrong_workout',receipt||jsonb_build_object('workoutLogID',s->'wb')),
    ('wrong_question',receipt||jsonb_build_object('questionKey',gen_random_uuid())),
    ('wrong_answer',receipt||'{"answer":"no"}'::jsonb)
  )t(label,bad_receipt) LOOP
    -- Select the bad receipt as a SQL jsonb expression: jsonb_populate_record
    -- would otherwise convert JSON null to SQL NULL and lose that distinct case.
    PERFORM c59x4_fixture.throws(format('INSERT INTO private.workout_strength_operations SELECT user_id,lifecycle_key,operation_kind,operation_key,original_operation_type,original_workout_log_id,live_workout_log_id,created_at,resolution,capture_outcome,legacy_result,answer_expected_revision,answer_question_key,answer_value,%L::jsonb FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',
      x.bad_receipt,ans||jsonb_build_object('operation_key','bad-receipt-'||x.label)),
      '23514','answer_receipt_'||x.label);
  END LOOP;
  PERFORM set_config('c59x4_test.state',(s||jsonb_build_object('capture_template',cap,'question',q))::text,true);
END $operations$;

DO $real_correction$
DECLARE s jsonb:=current_setting('c59x4_test.state')::jsonb;before_ops jsonb;after_ops jsonb;before_b jsonb;r jsonb;cap jsonb;
BEGIN
  SELECT jsonb_agg(to_jsonb(o)-'live_workout_log_id' ORDER BY lifecycle_key,operation_kind,operation_key,original_operation_type)
    INTO before_ops FROM private.workout_strength_operations o WHERE user_id=(s->>'a')::uuid;
  SELECT to_jsonb(o) INTO before_b FROM private.workout_strength_operations o WHERE user_id=(s->>'b')::uuid;
  PERFORM c59x4_fixture.ok((SELECT created_at>='2000-01-01T00:00:00Z'::timestamptz AND workout_type='musculacao'
    FROM public.workout_logs WHERE id=(s->>'wa')::uuid),'correction_real_created_at_boundary_premise');
  r:=public.register_workout_atomic((s->>'a')::uuid,'2026-10-12','musculacao',80,400,'moderada','X4 correction',
    '2026-10-12T16:00:00Z','c59x4-provider-a-correction',2000,150,true,'2000-01-01T00:00:00Z');
  PERFORM c59x4_fixture.ok(r->'inserted'='true'::jsonb AND r->>'replaced_count'='1'
    AND r->>'workout_log_id'<>s->>'wa'
    AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE id=(s->>'wa')::uuid)
    AND (SELECT count(*)=1 FROM public.workout_logs WHERE user_id=(s->>'a')::uuid),
    'correction_REAL_delete_old_insert_new_UUID');
  SELECT jsonb_agg(to_jsonb(o)-'live_workout_log_id' ORDER BY lifecycle_key,operation_kind,operation_key,original_operation_type)
    INTO after_ops FROM private.workout_strength_operations o WHERE user_id=(s->>'a')::uuid;
  PERFORM c59x4_fixture.ok(before_ops=after_ops
    AND NOT EXISTS(SELECT 1 FROM private.workout_strength_operations WHERE user_id=(s->>'a')::uuid AND live_workout_log_id IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM private.workout_strength_operations WHERE live_workout_log_id=(r->>'workout_log_id')::uuid),
    'correction_only_live_FK_NULL_owner_original_content_receipts_preserved_no_rebind');
  PERFORM c59x4_fixture.ok(r->>'exercise_calories'='400' AND r->'training_done'='true'::jsonb
    AND r->>'calories_target'='2000' AND (r->>'protein_target')::numeric=150
    AND (SELECT exercise_calories=400 AND training_done FROM public.daily_snapshots WHERE id=(r->>'snapshot_id')::uuid),
    'correction_official_snapshot_total_400');
  PERFORM c59x4_fixture.ok((SELECT to_jsonb(w)=s->'row_b' FROM public.workout_logs w WHERE id=(s->>'wb')::uuid)
    AND (SELECT to_jsonb(d)=s->'snapshot_b' AND exercise_calories=200 FROM public.daily_snapshots d WHERE id=(s#>>'{legacy_b,snapshot_id}')::uuid)
    AND (SELECT to_jsonb(o)=before_b FROM private.workout_strength_operations o WHERE user_id=(s->>'b')::uuid),
    'correction_other_owner_workout_snapshot_200_binding_unchanged');
  -- Explicit owner DELETE is a separate FK-only case, not a calorie writer.
  cap:=s->'capture_template'||jsonb_build_object('operation_key','new-own-delete','original_workout_log_id',r->'workout_log_id',
    'live_workout_log_id',r->'workout_log_id','legacy_result',r);
  EXECUTE format('INSERT INTO private.workout_strength_operations SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_operations,%L::jsonb)',cap);
  DELETE FROM public.workout_logs WHERE id=(r->>'workout_log_id')::uuid AND user_id=(s->>'a')::uuid;
  PERFORM c59x4_fixture.ok((SELECT live_workout_log_id IS NULL AND original_workout_log_id=(r->>'workout_log_id')::uuid
    AND user_id=(s->>'a')::uuid FROM private.workout_strength_operations WHERE operation_key='new-own-delete'),
    'direct_workout_delete_retains_owned_tombstone');
  DELETE FROM public.users WHERE id=(s->>'a')::uuid;
  PERFORM c59x4_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=(s->>'a')::uuid)
    AND NOT EXISTS(SELECT 1 FROM private.workout_strength_operations WHERE user_id=(s->>'a')::uuid)
    AND EXISTS(SELECT 1 FROM public.workout_logs WHERE id=(s->>'wb')::uuid AND estimated_kcal=200)
    AND (SELECT live_workout_log_id=(s->>'wb')::uuid FROM private.workout_strength_operations WHERE user_id=(s->>'b')::uuid),
    'account_owner_cascade_only_owned_lifecycles_operations');
END $real_correction$;

DO $permissions$
DECLARE role_name text;sqlstate_seen text;rel text;s jsonb:=current_setting('c59x4_test.state')::jsonb;
BEGIN
  PERFORM c59x4_fixture.ok((SELECT bool_and(c.relrowsecurity) AND count(*)=2 FROM pg_class c
    WHERE c.oid IN('private.workout_strength_lifecycles'::regclass,'private.workout_strength_operations'::regclass))
    AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid IN('private.workout_strength_lifecycles'::regclass,'private.workout_strength_operations'::regclass)),
    'private_storage_RLS_enabled_no_policies');
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    PERFORM c59x4_fixture.ok(NOT has_table_privilege(role_name,'private.workout_strength_lifecycles','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      AND NOT has_table_privilege(role_name,'private.workout_strength_operations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
      'private_storage_ALL_revoked:'||role_name);
    EXECUTE format('SET LOCAL ROLE %I',role_name);
    sqlstate_seen:=NULL;
    BEGIN PERFORM 1 FROM private.workout_strength_operations;
    EXCEPTION WHEN OTHERS THEN sqlstate_seen:=SQLSTATE;END;
    EXECUTE 'RESET ROLE';
    PERFORM c59x4_fixture.ok(sqlstate_seen='42501','private_operations_SELECT_denied:'||role_name);
    EXECUTE format('SET LOCAL ROLE %I',role_name);
    sqlstate_seen:=NULL;
    BEGIN
      INSERT INTO private.workout_strength_lifecycles VALUES((s->>'b')::uuid,gen_random_uuid(),now(),NULL,NULL);
    EXCEPTION WHEN OTHERS THEN sqlstate_seen:=SQLSTATE;END;
    EXECUTE 'RESET ROLE';
    PERFORM c59x4_fixture.ok(sqlstate_seen='42501','private_lifecycle_INSERT_denied:'||role_name);
  END LOOP;
  PERFORM c59x4_fixture.ok(NOT EXISTS(SELECT 1 FROM pg_class c,
    LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
    WHERE c.oid IN('private.workout_strength_lifecycles'::regclass,'private.workout_strength_operations'::regclass)
      AND a.grantee<>c.relowner),'private_table_ACL_owner_only_no_PUBLIC');
END $permissions$;
SELECT c59x4_fixture.ok((SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),
  'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,'security_definer',p.prosecdef,
  'comment',obj_description(p.oid,'pg_proc'))::text) FROM pg_proc p
  WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure)=:'x4_legacy_fingerprint',
  'legacy_api_definition_ACL_unchanged_after_real_correction');
ROLLBACK;
SELECT (to_regclass('public.daily_snapshots') IS NULL AND to_regclass('public.workout_logs') IS NULL
  AND to_regclass('private.workout_strength_lifecycles') IS NULL
  AND to_regclass('private.workout_strength_operations') IS NULL AND to_regnamespace('c59x4_fixture') IS NULL
  AND NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='register_workout_atomic')
  AND (SELECT count(*) FROM public.users)=:'x4_baseline_users'::bigint) AS rollback_ok
\gset x4_
\if :x4_rollback_ok
\echo C59X4_ROLLBACK_CONFIRMED
\else
DO $$BEGIN RAISE EXCEPTION 'C59X4_ROLLBACK_MISMATCH';END$$;
\endif
-- Fresh full schema/functions/ACL/rows/sequences equality and stop are Root gates.

-- TEST ONLY. No product DDL, source restore, ACL changes or migration execution.
-- postddl_expected_four_json is a public pinned projection of REAL run-r2 metadata16.
-- psql quotes it as a SQL literal OUTSIDE dollarquoted PL/pgSQL bodies.
\if :prepare_postddl
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
SET LOCAL ROLE postgres;
\endif
CREATE TEMP TABLE c59s17b_expected_four(value jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO c59s17b_expected_four VALUES(:'postddl_expected_four_json'::jsonb);
DO $postddl_reference$DECLARE e jsonb:=(SELECT value FROM pg_temp.c59s17b_expected_four);BEGIN
 IF e->>'format' IS DISTINCT FROM 'S17B_EXPECTED_FOUR_PREDDL_R1' OR e->>'version' IS DISTINCT FROM '1'
 OR e#>>'{origin,phase}' IS DISTINCT FROM 'real_preDDL_metadata16'
 OR e#>>'{origin,sha256}' IS DISTINCT FROM '9b669705ef0ff66ce1ef06af6adfb39cc965cf89b4c50a3b3f8b10e927ea6e9c'
 OR e#>>'{origin,database}' IS DISTINCT FROM current_database() OR e#>>'{origin,database_oid}' IS DISTINCT FROM (SELECT oid::text FROM pg_database WHERE datname=current_database())
 OR e#>>'{metadata_source,sha256}' IS DISTINCT FROM '1468296cc81689bb4ceea04210f52dc52faa238d41f054eb02e122a2536247dd'
 OR e#>>'{permitted_new_sources_origin,migration_sha256}' IS DISTINCT FROM '49b1f73ee6493bd627f7eb027b95632385190df4d33df512e99e4d8f2da0d00c'
 OR jsonb_typeof(e->'functions') IS DISTINCT FROM 'array' OR jsonb_array_length(e->'functions')<>4
 OR (SELECT array_agg(x->>'oid' ORDER BY (x->>'oid')::oid)FROM jsonb_array_elements(e->'functions')x)IS DISTINCT FROM ARRAY['21704','21796','22427','22428']
 OR e->>'defaults_precision' IS DISTINCT FROM 'SQL_RENDERING_ONLY_NOT_PG_NODE_TREE'
 THEN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_REFERENCE_PROVENANCE';END IF;
END $postddl_reference$;
\if :prepare_postddl
DO $postddl_pre$BEGIN
 IF to_regnamespace('c59s17b_fixture') IS NOT NULL THEN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_FIXTURE_COLLISION';END IF;
 IF to_regprocedure('public.admit_mobile_workout_registration(uuid,text,jsonb)') IS NULL
 OR to_regprocedure('public.materialize_mobile_workout_registration(uuid,uuid,jsonb,jsonb,timestamp with time zone)') IS NULL
 OR to_regprocedure('public.get_mobile_workout_registration(uuid,uuid)') IS NULL
 OR to_regprocedure('private.register_workout_atomic_core(uuid,date,text,integer,integer,text,text,timestamp with time zone,text,integer,numeric,boolean,timestamp with time zone)') IS NULL
 OR to_regprocedure('private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb)') IS NULL
 OR to_regclass('private.mobile_workout_registration_edit_receipts') IS NULL
 OR (SELECT count(*)FROM pg_attribute WHERE NOT attisdropped AND((attrelid='private.mobile_workout_proposal_admissions'::regclass AND attname IN('content_revision','confirmed_lifecycle_key'))OR(attrelid='public.pending_registrations'::regclass AND attname='workout_ui_admission_id')))<>3
 THEN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_PRODUCT_ABSENT' USING ERRCODE='42883';END IF;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN(SELECT('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(501,504)i UNION ALL SELECT('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(701,740)i UNION ALL SELECT('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM unnest(ARRAY[901,902,903,999])i)
 OR email IN(SELECT 'c59s17b-'||i||'@example.invalid' FROM generate_series(501,504)i UNION ALL SELECT 'c59s17b-'||i||'@example.invalid' FROM generate_series(701,740)i UNION ALL SELECT 'c59s17b-'||i||'@example.invalid' FROM unnest(ARRAY[901,902,903,999])i)
 OR wpp IN(SELECT '155517'||lpad(i::text,7,'0') FROM generate_series(501,504)i UNION ALL SELECT '155517'||lpad(i::text,7,'0') FROM generate_series(701,740)i UNION ALL SELECT '155517'||lpad(i::text,7,'0') FROM unnest(ARRAY[901,902,903,999])i))
 THEN RAISE EXCEPTION 'C59S17B_SETUP_OWNER_COLLISION';END IF;
END $postddl_pre$;
\ir mobile_workout_registration_boundary_fixture.sql
SET LOCAL ROLE postgres;
-- Extra QA origin, never a product table. old_functions below is EMPTY on purpose.
CREATE TABLE c59s17b_fixture.postddl_origin(tag text PRIMARY KEY,expected_four jsonb NOT NULL,legacy_samples jsonb NOT NULL);
REVOKE ALL ON c59s17b_fixture.postddl_origin FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s17b_fixture.assert_postddl_origin(expected jsonb) RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $postddl_owned$
DECLARE o record;r record;h record;n integer;sample jsonb;BEGIN
 SELECT * INTO STRICT o FROM c59s17b_fixture.ownership WHERE tag='c59s17b_ui_boundary_v1';
 SELECT * INTO STRICT r FROM c59s17b_fixture.postddl_origin WHERE tag='c59s17b_postddl_runtime_v1';
 IF (SELECT count(*)FROM c59s17b_fixture.ownership)<>1 OR (SELECT count(*)FROM c59s17b_fixture.postddl_origin)<>1
 OR o.owner_name IS DISTINCT FROM session_user OR o.old_functions IS DISTINCT FROM '{}'::jsonb
 OR o.fixture_fingerprint IS DISTINCT FROM c59s17b_fixture.fingerprint() OR r.expected_four IS DISTINCT FROM expected
 OR (SELECT array_agg(case_id ORDER BY case_id)FROM c59s17b_fixture.historical)IS DISTINCT FROM ARRAY['bound-null','collision-null','unbound-null']
 OR (SELECT array_agg(k ORDER BY k)FROM jsonb_object_keys(r.legacy_samples)k)IS DISTINCT FROM ARRAY['bound-null','collision-null','unbound-null']
 THEN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_ORIGIN_DRIFT';END IF;
 FOR h IN SELECT * FROM c59s17b_fixture.historical ORDER BY case_id LOOP
 n:=CASE h.case_id WHEN 'bound-null' THEN 901 WHEN 'collision-null' THEN 902 ELSE 903 END;
 sample:=jsonb_build_object('owner_id',h.owner_id,'payload',h.payload,'legacy_shape',h.old_state,'raw_state',c59s17b_fixture.state(h.owner_id));
 IF h.owner_id IS DISTINCT FROM c59s17b_fixture.uid(n) OR sample IS DISTINCT FROM r.legacy_samples->h.case_id
 OR h.old_state IS DISTINCT FROM c59s17b_fixture.old_shape(c59s17b_fixture.state(h.owner_id))
 OR h.payload->>'ownerID' IS DISTINCT FROM h.owner_id::text OR h.payload->>'requestKey' IS DISTINCT FROM c59s17b_fixture.key(n)
 OR h.payload->'input' IS DISTINCT FROM c59s17b_fixture.input()
 OR NOT EXISTS(SELECT 1 FROM ONLY public.users WHERE id=h.owner_id AND email='c59s17b-'||n||'@example.invalid'AND wpp='155517'||lpad(n::text,7,'0')AND name='C59S17B synthetic'AND country='US'AND timezone='UTC'AND country_confirmed AND flow_phrase_cursor_revision=17 AND metadata='{"c59s17b_fixture":"c59s17b_ui_boundary_v1"}'::jsonb)
 THEN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_LEGACY_SAMPLE_DRIFT';END IF;
 END LOOP;
END $postddl_owned$;
REVOKE ALL ON FUNCTION c59s17b_fixture.assert_postddl_origin(jsonb) FROM PUBLIC,anon,authenticated,service_role;
-- Same real S16 owner RPCs as original prepare, now AFTER DDL; no historical upgrade claim.
DO $history$ DECLARE i integer;u uuid;k text;v jsonb:=c59s17b_fixture.input();a jsonb;r jsonb;pid uuid;payload jsonb; BEGIN
 FOR i IN 901..903 LOOP
 u:=c59s17b_fixture.owner(i);k:=c59s17b_fixture.key(i);
 IF i=902 THEN r:=public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',clock_timestamp()+interval '1 hour',k);pid:=(r->>'pending_id')::uuid;END IF;
 a:=public.admit_mobile_workout_proposal(u,k,v);
 IF a->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17B_SETUP_OLD_REAL_ADMIT';END IF;
 payload:=jsonb_build_object('ownerID',u,'requestKey',k,'input',v,'admission',a->'admission');
 IF i IN(901,902)THEN
 r:=public.materialize_mobile_workout_proposal(u,(a#>>'{admission,admissionID}')::uuid,v,c59s17b_fixture.proposal(k,v),clock_timestamp()+interval '1 hour');
 IF(i=901 AND r->>'status' IS DISTINCT FROM 'materialized')OR(i=902 AND r IS DISTINCT FROM '{"status":"conflict","reason":"unproved_pending"}'::jsonb)THEN RAISE EXCEPTION 'C59S17B_SETUP_OLD_REAL_MATERIALIZE';END IF;
 payload:=payload||jsonb_build_object('materialized',r);END IF;
 INSERT INTO c59s17b_fixture.historical VALUES(CASE i WHEN 901 THEN 'bound-null' WHEN 902 THEN 'collision-null' ELSE 'unbound-null' END,u,payload,c59s17b_fixture.old_shape(c59s17b_fixture.state(u)));
 END LOOP;
END $history$;
INSERT INTO c59s17b_fixture.postddl_origin
 SELECT 'c59s17b_postddl_runtime_v1',(SELECT value FROM pg_temp.c59s17b_expected_four),jsonb_object_agg(h.case_id,jsonb_build_object('owner_id',h.owner_id,'payload',h.payload,'legacy_shape',h.old_state,'raw_state',c59s17b_fixture.state(h.owner_id)))FROM c59s17b_fixture.historical h;
INSERT INTO c59s17b_fixture.ownership VALUES('c59s17b_ui_boundary_v1',session_user,c59s17b_fixture.fingerprint(),'{}'::jsonb);
DO $postddl_check$BEGIN PERFORM c59s17b_fixture.assert_postddl_origin((SELECT value FROM pg_temp.c59s17b_expected_four));END $postddl_check$;
COMMIT;
\echo C59S17B_POSTDDL_FIXTURE_PREPARED
\else
DO $postddl_check$BEGIN PERFORM c59s17b_fixture.assert_postddl_origin((SELECT value FROM pg_temp.c59s17b_expected_four));END $postddl_check$;
\endif

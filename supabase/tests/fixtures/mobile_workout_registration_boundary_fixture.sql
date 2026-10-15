-- TEST ONLY. Existing C5 substrate; no shadow writer, product DDL or bootstrap.
CREATE SCHEMA c59s17b_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s17b_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s17b_fixture.ownership(tag text PRIMARY KEY, owner_name text NOT NULL, fixture_fingerprint jsonb NOT NULL, old_functions jsonb NOT NULL);
CREATE TABLE c59s17b_fixture.historical(case_id text PRIMARY KEY, owner_id uuid UNIQUE NOT NULL, payload jsonb NOT NULL, old_state jsonb NOT NULL);
CREATE TABLE c59s17b_fixture.cases(case_id text PRIMARY KEY, owner_id uuid UNIQUE NOT NULL, payload jsonb NOT NULL);
CREATE FUNCTION c59s17b_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $uid$
 SELECT ('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $uid$;
CREATE FUNCTION c59s17b_fixture.key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $key$
 SELECT 'wui1:'||c59s17b_fixture.uid(i)::text $key$;
CREATE FUNCTION c59s17b_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $ok$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S17B_ASSERT:%',label; END IF; RAISE NOTICE 'C59S17B_PASS:%',label; END $ok$;
CREATE FUNCTION c59s17b_fixture.owner(i integer) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $owner$
DECLARE u uuid:=c59s17b_fixture.uid(i); BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
 VALUES(u,'155517'||lpad(i::text,7,'0'),'c59s17b-'||i||'@example.invalid','C59S17B synthetic','UTC','US',true,'{"c59s17b_fixture":"c59s17b_ui_boundary_v1"}',17);
 RETURN u; END $owner$;
CREATE FUNCTION c59s17b_fixture.input(raw text DEFAULT 'musculacao') RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $input$
 SELECT jsonb_build_object('kind','workout','workout_type',raw,'duration_min',60,'intensity','moderada') $input$;
CREATE FUNCTION c59s17b_fixture.proposal(k text,v jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $proposal$
 SELECT jsonb_build_object('kind','workout','workoutType',v->>'workout_type','durationMin',v->'duration_min','kcalEst',300,'intensity',v->>'intensity',
 'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp','2026-10-15T12:00:00.123Z','source_timezone','UTC','source_local_date','2026-10-15',
 'raw_args',jsonb_build_object('workout_type',v->>'workout_type','duration_min',v->'duration_min','intensity',v->>'intensity'),'express_eligible',false) $proposal$;
-- Invoke the real statement under the requested effective role. No simulated RPC result.
CREATE FUNCTION c59s17b_fixture.attempt(sql text,role_name text DEFAULT 'service_role') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $attempt$
DECLARE r jsonb;s text;m text; BEGIN
 EXECUTE format('SET LOCAL ROLE %I',role_name);
 BEGIN EXECUTE sql INTO r; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT; END;
 SET LOCAL ROLE NONE;
 IF s IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m); END IF;
 RETURN jsonb_build_object('ok',true,'result',r);
END $attempt$;
CREATE FUNCTION c59s17b_fixture.ui(i integer,bind boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $ui$
DECLARE u uuid:=c59s17b_fixture.owner(i);v jsonb:=c59s17b_fixture.input();k text:=c59s17b_fixture.key(i);r jsonb;a jsonb;e timestamptz:=clock_timestamp()+interval '1 hour'; BEGIN
 r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17B_SETUP_REAL_ADMIT:%',r; END IF;
 a:=r#>'{result,admission}';r:=jsonb_build_object('ownerID',u,'input',v,'proposal',c59s17b_fixture.proposal(k,v),'requestKey',k,'expiresAt',e,'admission',a);
 IF bind THEN a:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a->>'admissionID',v,r->'proposal',e));
 IF a->'ok' IS DISTINCT FROM 'true'::jsonb OR a#>>'{result,status}' IS DISTINCT FROM 'materialized' THEN RAISE EXCEPTION 'C59S17B_SETUP_REAL_MATERIALIZE:%',a; END IF;
 r:=r||jsonb_build_object('materialized',a->'result'); END IF; RETURN r;
END $ui$;
CREATE FUNCTION c59s17b_fixture.arguments(u uuid,raw text,provider text) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $args$
 SELECT jsonb_build_object('p_user_id',u,'p_date','2026-10-15','p_workout_type',raw,'p_duration_min',60,'p_estimated_kcal',300,
 'p_intensity','moderada','p_notes','S17B preserved café 🏋️','p_performed_at','2026-10-15T12:00:00.123456Z','p_provider_message_id',provider,
 'p_calories_target',2000,'p_protein_target',150.25,'p_replace_recent',false,'p_replace_since',NULL) $args$;
CREATE FUNCTION c59s17b_fixture.legacy_sql(a jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $legacy$
 SELECT format('SELECT public.register_workout_atomic(%L::uuid,%L::date,%L,%L::integer,%L::integer,%L,%L,%L::timestamptz,%L,%L::integer,%L::numeric,%L::boolean,%L::timestamptz)',
 a->>'p_user_id',a->>'p_date',a->>'p_workout_type',a->>'p_duration_min',a->>'p_estimated_kcal',a->>'p_intensity',a->>'p_notes',a->>'p_performed_at',a->>'p_provider_message_id',a->>'p_calories_target',a->>'p_protein_target',a->>'p_replace_recent',a->>'p_replace_since') $legacy$;
CREATE FUNCTION c59s17b_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $state$
DECLARE t text;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x) FROM ONLY public.users x WHERE id=u)); BEGIN
 FOREACH t IN ARRAY ARRAY['public.messages','public.user_profiles','public.user_progress','public.workout_logs','public.daily_snapshots','public.pending_registrations','private.workout_strength_lifecycles','private.workout_strength_operations','private.workout_strength_facts','private.workout_strength_commands','private.workout_strength_calendar_scopes','private.workout_strength_authority_epochs','private.workout_strength_request_admissions','private.mobile_workout_proposal_admissions','private.mobile_workout_registration_edit_receipts'] LOOP
 IF to_regclass(t) IS NOT NULL THEN EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM ONLY %s x WHERE user_id=$1',t) INTO a USING u; r:=r||jsonb_build_object(t,a); END IF; END LOOP; RETURN r;
END $state$;
-- Only the three explicitly additive NULL fields are removable for upgrade comparison.
CREATE FUNCTION c59s17b_fixture.old_shape(s jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $old$
DECLARE j jsonb;p jsonb;r jsonb:=s;new_columns integer; BEGIN
 SELECT count(*)INTO new_columns FROM pg_attribute WHERE NOT attisdropped AND((attrelid='private.mobile_workout_proposal_admissions'::regclass AND attname IN('content_revision','confirmed_lifecycle_key'))OR(attrelid='public.pending_registrations'::regclass AND attname='workout_ui_admission_id'));
 IF new_columns=0 AND to_regclass('private.mobile_workout_registration_edit_receipts')IS NULL THEN RETURN s;END IF;
 IF new_columns<>3 OR to_regclass('private.mobile_workout_registration_edit_receipts')IS NULL THEN RAISE EXCEPTION 'C59S17B_HISTORICAL_PARTIAL_SCHEMA';END IF;
 IF s?'private.mobile_workout_registration_edit_receipts' AND s->'private.mobile_workout_registration_edit_receipts'<>'[]'::jsonb THEN RAISE EXCEPTION 'C59S17B_HISTORICAL_UNEXPECTED_EDIT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(s->'private.mobile_workout_proposal_admissions')x WHERE x->'content_revision' IS DISTINCT FROM 'null'::jsonb OR x->'confirmed_lifecycle_key' IS DISTINCT FROM 'null'::jsonb)
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->'workout_ui_admission_id' IS DISTINCT FROM 'null'::jsonb) THEN RAISE EXCEPTION 'C59S17B_HISTORICAL_PROMOTED'; END IF;
 SELECT coalesce(jsonb_agg(x-ARRAY['content_revision','confirmed_lifecycle_key'] ORDER BY (x-ARRAY['content_revision','confirmed_lifecycle_key'])::text),'[]'::jsonb) INTO j FROM jsonb_array_elements(s->'private.mobile_workout_proposal_admissions')x;
 SELECT coalesce(jsonb_agg(x-'workout_ui_admission_id' ORDER BY (x-'workout_ui_admission_id')::text),'[]'::jsonb) INTO p FROM jsonb_array_elements(s->'public.pending_registrations')x;
 RETURN(r-'private.mobile_workout_registration_edit_receipts')||jsonb_build_object('private.mobile_workout_proposal_admissions',j,'public.pending_registrations',p);
END $old$;
CREATE FUNCTION c59s17b_fixture.functions() RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $functions$
 SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'prosrc',p.prosrc,'acl',p.proacl::text,'owner',p.proowner::text,'defaults',p.proargdefaults::text,'names',p.proargnames,'args',p.proargtypes::text,'rettype',p.prorettype::text)) FROM pg_proc p WHERE p.oid IN(
 'public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure,
 'public.admit_mobile_workout_proposal(uuid,text,jsonb)'::regprocedure,
 'public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamp with time zone)'::regprocedure) $functions$;
CREATE FUNCTION c59s17b_fixture.fingerprint() RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $fingerprint$
 SELECT jsonb_build_object('schema',(SELECT jsonb_build_array(oid::text,nspowner::text,nspacl::text) FROM pg_namespace WHERE nspname='c59s17b_fixture'),
 'functions',(SELECT jsonb_object_agg(p.oid::text,md5(pg_get_functiondef(p.oid)||coalesce(p.proacl::text,'')||p.proowner::text)) FROM pg_proc p WHERE p.pronamespace='c59s17b_fixture'::regnamespace),
 'relations',(SELECT jsonb_object_agg(c.oid::text,jsonb_build_object('name',c.relname,'owner',c.relowner::text,'acl',c.relacl::text,'kind',c.relkind,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attcollation::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_array(k.oid::text,md5(pg_get_constraintdef(k.oid,true))) ORDER BY k.oid) FROM pg_constraint k WHERE k.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid))) ORDER BY i.indexrelid) FROM pg_index i WHERE i.indrelid=c.oid))) FROM pg_class c WHERE c.relnamespace='c59s17b_fixture'::regnamespace)) $fingerprint$;
CREATE FUNCTION c59s17b_fixture.fail_after_bind() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fault$
BEGIN IF NEW.user_id=c59s17b_fixture.uid(725) AND OLD.pending_id IS NULL AND NEW.pending_id IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations p WHERE p.id=NEW.pending_id AND p.user_id=NEW.user_id AND p.workout_ui_admission_id IS NULL)
 OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a WHERE a.user_id=NEW.user_id AND a.admission_id=NEW.admission_id AND a.pending_id=NEW.pending_id)
 THEN RAISE EXCEPTION 'C59S17B_FAULT_BIND_ORDER_UNPROVED' USING ERRCODE='P0002'; END IF;
 RAISE EXCEPTION 'C59S17B_INJECTED_AFTER_REAL_BIND' USING ERRCODE='P0001'; END IF; RETURN NEW;
END $fault$;
CREATE FUNCTION c59s17b_fixture.fail_after_marker() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fault$
BEGIN IF NEW.user_id=c59s17b_fixture.uid(725) AND OLD.workout_ui_admission_id IS NULL AND NEW.workout_ui_admission_id IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a WHERE a.user_id=NEW.user_id AND a.admission_id=NEW.workout_ui_admission_id AND a.pending_id=NEW.id AND a.content_revision=0)
 OR NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations p WHERE p.id=NEW.id AND p.workout_ui_admission_id=NEW.workout_ui_admission_id)
 THEN RAISE EXCEPTION 'C59S17B_FAULT_MARKER_ORDER_UNPROVED' USING ERRCODE='P0002'; END IF;
 RAISE EXCEPTION 'C59S17B_INJECTED_AFTER_REAL_MARKER' USING ERRCODE='P0001'; END IF; RETURN NEW;
END $fault$;
DO $acl$ DECLARE f record; BEGIN
 FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17b_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.oid::regprocedure); END LOOP;
END $acl$;
REVOKE ALL ON ALL TABLES IN SCHEMA c59s17b_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE NONE;

-- PRIVATE TEST-FIRST SOURCE ONLY. Root must adopt/review before any execution.
-- No product DDL, shadow mutator, public test switch, schema grant or body replacement.
CREATE SCHEMA c59s17c_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s17c_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s17c_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,fixture_fingerprint jsonb NOT NULL);
CREATE TABLE c59s17c_fixture.cases(case_id text PRIMARY KEY,owner_id uuid UNIQUE NOT NULL,payload jsonb NOT NULL);
CREATE FUNCTION c59s17c_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT ('c59c7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $f$;
CREATE FUNCTION c59s17c_fixture.key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wui1:'||c59s17c_fixture.uid(i)::text $f$;
CREATE FUNCTION c59s17c_fixture.edit_key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wue1:'||c59s17c_fixture.uid(i)::text $f$;
CREATE FUNCTION c59s17c_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S17C_ASSERT:%',label;END IF;RAISE NOTICE 'C59S17C_PASS:%',label;END $f$;
CREATE FUNCTION c59s17c_fixture.owner(i integer) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE u uuid:=c59s17c_fixture.uid(i);BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
 VALUES(u,'155518'||lpad(i::text,7,'0'),'c59s17c-'||i||'@example.invalid','C59S17C synthetic','UTC','US',true,'{"c59s17c_fixture":"c59s17c_edit_cancel_v1"}',17);
 INSERT INTO public.user_profiles(user_id,weight_kg)VALUES(u,70);RETURN u;END $f$;
CREATE FUNCTION c59s17c_fixture.input(duration integer DEFAULT 40,raw text DEFAULT 'Natação',performed text DEFAULT NULL) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workout_type',raw,'duration_min',duration,'intensity','moderada')||CASE WHEN performed IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('performed_at',performed)END $f$;
-- kcal/time are explicit synthetic official-candidate literals, not a new calorie formula.
CREATE FUNCTION c59s17c_fixture.proposal(k text,v jsonb,kcal integer DEFAULT 400,ts text DEFAULT '2026-10-15T12:00:00.123Z') RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workoutType',v->>'workout_type','durationMin',v->'duration_min','kcalEst',kcal,'intensity',v->>'intensity',
 'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp',ts,'source_timezone','UTC','source_local_date',left(ts,10),
 'raw_args',jsonb_build_object('workout_type',v->>'workout_type','duration_min',v->'duration_min','intensity',v->>'intensity'),'express_eligible',false) $f$;
-- Literal closed-S17B pattern: execute actual SQL as effective role; retain native diagnostics.
CREATE FUNCTION c59s17c_fixture.attempt(sql text,role_name text DEFAULT 'service_role') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $f$
DECLARE r jsonb;s text;m text;BEGIN EXECUTE format('SET LOCAL ROLE %I',role_name);
 BEGIN EXECUTE sql INTO r;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;END;
 SET LOCAL ROLE NONE;IF s IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m);END IF;
 RETURN jsonb_build_object('ok',true,'result',r);END $f$;
CREATE FUNCTION c59s17c_fixture.member(u uuid,k text,v jsonb,kcal integer DEFAULT 400) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE r jsonb;a jsonb;p jsonb:=c59s17c_fixture.proposal(k,v,kcal);e timestamptz:=clock_timestamp()+interval '6 hours';BEGIN
 r:=c59s17c_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_ADMIT:%',r;END IF;a:=r#>'{result,admission}';
 r:=c59s17c_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a->>'admissionID',v,p,e));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'materialized' THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_MATERIALIZE:%',r;END IF;
 RETURN jsonb_build_object('ownerID',u,'requestKey',k,'input',v,'proposal',p,'expiresAt',e,'admission',a,'materialized',r->'result','registrationID',r#>'{result,pendingID}');END $f$;
CREATE FUNCTION c59s17c_fixture.ui(i integer) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
BEGIN RETURN c59s17c_fixture.member(c59s17c_fixture.owner(i),c59s17c_fixture.key(i),c59s17c_fixture.input());END $f$;
CREATE FUNCTION c59s17c_fixture.edit_sql(u uuid,pid uuid,expected integer,k text,v jsonb,p jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.edit_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer,%L,%L::jsonb,%L::jsonb)',u,pid,expected,k,v,p) $f$;
CREATE FUNCTION c59s17c_fixture.cancel_sql(u uuid,pid uuid,expected integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.cancel_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer)',u,pid,expected) $f$;
-- Read raw official rows independently of either new mutator; exactly the closed eight fields.
CREATE FUNCTION c59s17c_fixture.registration(u uuid,pid uuid) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('id',p.id,'status',p.status,'created_at',p.created_at,'expires_at',p.expires_at,'resolved_at',p.resolved_at,'proposal',p.proposal,'workout_protocol','ui-v1','content_revision',a.content_revision)
 FROM ONLY public.pending_registrations p JOIN private.mobile_workout_proposal_admissions a ON a.user_id=p.user_id AND a.pending_id=p.id AND a.admission_id=p.workout_ui_admission_id
 WHERE p.user_id=u AND p.id=pid $f$;
-- Superset of the closed fifteen groups: EVERY public/private base table with user_id.
CREATE FUNCTION c59s17c_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
-- Global rows outside selected synthetic owner: no hidden cross-owner/product-table effects.
CREATE FUNCTION c59s17c_fixture.outside(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:='{}';has_user boolean;pred text;BEGIN
 FOR t IN SELECT n.nspname,c.relname,c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')ORDER BY n.nspname,c.relname LOOP
 SELECT EXISTS(SELECT 1 FROM pg_attribute x WHERE x.attrelid=t.oid AND x.attname='user_id'AND x.atttypid='uuid'::regtype AND x.attnum>0 AND NOT x.attisdropped)INTO has_user;
 pred:=CASE WHEN t.nspname='public'AND t.relname='users'THEN ' WHERE id IS DISTINCT FROM $1'WHEN has_user THEN ' WHERE user_id IS DISTINCT FROM $1'ELSE ''END;
 EXECUTE format('SELECT jsonb_build_object(''count'',count(*),''rows_md5'',md5(coalesce(string_agg(to_jsonb(x)::text,E''\n''ORDER BY to_jsonb(x)::text),'''')))FROM ONLY %I.%I x%s',t.nspname,t.relname,pred)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
CREATE FUNCTION c59s17c_fixture.assert_unchanged_except(s jsonb,t jsonb,allowed text[],label text)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF s-allowed IS DISTINCT FROM t-allowed THEN RAISE EXCEPTION 'C59S17C_UNEXPECTED_EFFECT:%',label;END IF;END $f$;
CREATE FUNCTION c59s17c_fixture.assert_edited(r jsonb,s jsonb,u uuid,pid uuid,k text,v jsonb,p jsonb,expected integer,lo timestamptz,hi timestamptz)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE t jsonb:=c59s17c_fixture.state(u);j jsonb;oldj jsonb;pending jsonb;oldp jsonb;e timestamptz;expected_receipt jsonb;BEGIN
 SELECT x INTO STRICT j FROM jsonb_array_elements(t->'private.mobile_workout_proposal_admissions')x WHERE x->>'pending_id'=pid::text;
 SELECT x INTO STRICT oldj FROM jsonb_array_elements(s->'private.mobile_workout_proposal_admissions')x WHERE x->>'pending_id'=pid::text;
 SELECT x INTO STRICT pending FROM jsonb_array_elements(t->'public.pending_registrations')x WHERE x->>'id'=pid::text;
 SELECT x INTO STRICT oldp FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->>'id'=pid::text;e:=(pending->>'expires_at')::timestamptz;
 expected_receipt:=jsonb_build_object('user_id',u,'admission_id',j->'admission_id','request_key',k,'input_hash',private.mobile_workout_proposal_input_hash(v),'expected_revision',expected,'result_revision',expected+1);
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','edited','registration',c59s17c_fixture.registration(u,pid),'receipt',jsonb_build_object('requestKey',k,'expectedRevision',expected,'resultRevision',expected+1)))
 OR j IS DISTINCT FROM oldj||jsonb_build_object('content_revision',expected+1)
 OR pending IS DISTINCT FROM oldp||jsonb_build_object('proposal',p,'expires_at',e)
 OR e IS NULL OR NOT isfinite(e)OR e<lo+interval '24 hours'OR e>hi+interval '24 hours'
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(t->'private.mobile_workout_registration_edit_receipts')x WHERE x=expected_receipt)
 OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.mobile_workout_registration_edit_receipts')x WHERE x<>expected_receipt)IS DISTINCT FROM s->'private.mobile_workout_registration_edit_receipts'
 THEN RAISE EXCEPTION 'C59S17C_EDIT_DELTA_OR_WIRE:%',r;END IF;
 PERFORM c59s17c_fixture.assert_unchanged_except(s,t,ARRAY['private.mobile_workout_proposal_admissions','public.pending_registrations','private.mobile_workout_registration_edit_receipts'],'edited');
 -- Admissions/pending other than the edited original must also remain byte exact.
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.mobile_workout_proposal_admissions')x WHERE (x->>'pending_id') IS DISTINCT FROM pid::text)IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'private.mobile_workout_proposal_admissions')x WHERE (x->>'pending_id') IS DISTINCT FROM pid::text)
 OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'public.pending_registrations')x WHERE x->>'id'<>pid::text)IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->>'id'<>pid::text)THEN RAISE EXCEPTION 'C59S17C_EDIT_OTHER_REGISTRATION_MUTATED';END IF;
END $f$;
CREATE FUNCTION c59s17c_fixture.assert_cancelled(r jsonb,s jsonb,u uuid,pid uuid,lo timestamptz,hi timestamptz)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE t jsonb:=c59s17c_fixture.state(u);oldp jsonb;p jsonb;resolved timestamptz;BEGIN
 SELECT x INTO STRICT oldp FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->>'id'=pid::text;
 SELECT x INTO STRICT p FROM jsonb_array_elements(t->'public.pending_registrations')x WHERE x->>'id'=pid::text;resolved:=(p->>'resolved_at')::timestamptz;
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','cancelled','registration',c59s17c_fixture.registration(u,pid)))
 OR p IS DISTINCT FROM oldp||jsonb_build_object('status','cancelled','resolved_at',resolved)
 OR resolved IS NULL OR NOT isfinite(resolved)OR resolved<lo OR resolved>hi THEN RAISE EXCEPTION 'C59S17C_CANCEL_DELTA_OR_WIRE:%',r;END IF;
 PERFORM c59s17c_fixture.assert_unchanged_except(s,t,ARRAY['public.pending_registrations'],'cancelled');
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'public.pending_registrations')x WHERE x->>'id'<>pid::text)IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->>'id'<>pid::text)THEN RAISE EXCEPTION 'C59S17C_CANCEL_OTHER_REGISTRATION_MUTATED';END IF;END $f$;
CREATE FUNCTION c59s17c_fixture.expect_conflict(sql text,u uuid,pid uuid,reason text)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17c_fixture.state(u);o jsonb:=c59s17c_fixture.outside(u);r jsonb;BEGIN r:=c59s17c_fixture.attempt(sql);
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','conflict','reason',reason,'registration',c59s17c_fixture.registration(u,pid)))OR c59s17c_fixture.state(u)IS DISTINCT FROM s OR c59s17c_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17C_CONFLICT:%:%',reason,r;END IF;END $f$;
CREATE FUNCTION c59s17c_fixture.expect_forbidden(sql text,u uuid,reason text)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17c_fixture.state(u);o jsonb:=c59s17c_fixture.outside(u);r jsonb;BEGIN r:=c59s17c_fixture.attempt(sql);
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','forbidden','reason',reason))OR c59s17c_fixture.state(u)IS DISTINCT FROM s OR c59s17c_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17C_FORBIDDEN:%:%',reason,r;END IF;END $f$;
CREATE FUNCTION c59s17c_fixture.expect_sqlstate(sql text,u uuid,code text,role_name text DEFAULT 'service_role',expected_message text DEFAULT NULL)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17c_fixture.state(u);o jsonb:=c59s17c_fixture.outside(u);r jsonb;BEGIN r:=c59s17c_fixture.attempt(sql,role_name);
 IF r->>'sqlstate'IS DISTINCT FROM code OR r->'ok'IS DISTINCT FROM 'false'::jsonb OR(expected_message IS NOT NULL AND r->>'message'IS DISTINCT FROM expected_message)OR c59s17c_fixture.state(u)IS DISTINCT FROM s OR c59s17c_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17C_NATIVE_NEGATIVE:%:%',code,r;END IF;END $f$;
CREATE FUNCTION c59s17c_fixture.fingerprint()RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('schema',(SELECT jsonb_build_array(oid::text,nspowner::text,nspacl::text)FROM pg_namespace WHERE nspname='c59s17c_fixture'),
 'functions',(SELECT jsonb_object_agg(p.oid::text,md5(pg_get_functiondef(p.oid)||coalesce(p.proacl::text,'')||p.proowner::text))FROM pg_proc p WHERE p.pronamespace='c59s17c_fixture'::regnamespace),
 'relations',(SELECT jsonb_object_agg(c.oid::text,jsonb_build_object('name',c.relname,'owner',c.relowner::text,'acl',c.relacl::text,'kind',c.relkind,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attcollation::text)ORDER BY a.attnum)FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_array(k.oid::text,md5(pg_get_constraintdef(k.oid,true)))ORDER BY k.oid)FROM pg_constraint k WHERE k.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid)))ORDER BY i.indexrelid)FROM pg_index i WHERE i.indrelid=c.oid)))FROM pg_class c WHERE c.relnamespace='c59s17c_fixture'::regnamespace)) $f$;
-- Only negative fault cases 1771/1772 install these as AFTER ROW triggers.
CREATE FUNCTION c59s17c_fixture.fail_after_pending_update()RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF NEW.user_id=c59s17c_fixture.uid(1771)AND NEW.proposal IS DISTINCT FROM OLD.proposal THEN
 IF NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations p WHERE p.user_id=NEW.user_id AND p.id=NEW.id AND p.proposal=NEW.proposal)THEN RAISE EXCEPTION 'C59S17C_FAULT_UPDATE_NOT_VISIBLE';END IF;
 RAISE EXCEPTION 'C59S17C_INJECTED_AFTER_PENDING_UPDATE' USING ERRCODE='P0001';END IF;RETURN NEW;END $f$;
CREATE FUNCTION c59s17c_fixture.fail_after_receipt_insert()RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF NEW.user_id=c59s17c_fixture.uid(1772)THEN
 IF NOT EXISTS(SELECT 1 FROM private.mobile_workout_registration_edit_receipts e WHERE e.user_id=NEW.user_id AND e.admission_id=NEW.admission_id AND e.request_key=NEW.request_key)THEN RAISE EXCEPTION 'C59S17C_FAULT_RECEIPT_NOT_VISIBLE' USING ERRCODE='P0002';END IF;
 RAISE EXCEPTION 'C59S17C_INJECTED_AFTER_RECEIPT_INSERT' USING ERRCODE='P0001';END IF;RETURN NEW;END $f$;
-- Two strictly scoped owner-only clock fixtures. A may rearm the same case under its rowlock.
CREATE FUNCTION c59s17c_fixture.arm_expiry_case(cid text)RETURNS timestamptz LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $f$
DECLARE u uuid;pid uuid;e timestamptz;c record;BEGIN
 IF current_user<>session_user OR session_user<>'c5_local_admin'OR cid NOT IN('expiry-edit-after-rowlock','expiry-cancel-after-rowlock')THEN RAISE EXCEPTION 'C59S17C_EXPIRY_SCOPE';END IF;
 SELECT * INTO STRICT c FROM c59s17c_fixture.ownership WHERE tag='c59s17c_edit_cancel_v1';IF c.owner_name<>session_user OR c.fixture_fingerprint IS DISTINCT FROM c59s17c_fixture.fingerprint()THEN RAISE EXCEPTION 'C59S17C_EXPIRY_OWNERSHIP';END IF;
 u:=c59s17c_fixture.uid(CASE cid WHEN 'expiry-edit-after-rowlock'THEN 1811 ELSE 1812 END);
 SELECT(payload->>'registrationID')::uuid INTO STRICT pid FROM c59s17c_fixture.cases WHERE case_id=cid AND owner_id=u AND payload->>'ownerID'=u::text;
 SET LOCAL ROLE postgres;
 UPDATE ONLY public.pending_registrations p SET expires_at=clock_timestamp()+interval '5 seconds'
 WHERE p.user_id=u AND p.id=pid AND p.status='pending'AND EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a WHERE a.user_id=u AND a.pending_id=pid AND a.admission_id=p.workout_ui_admission_id AND a.content_revision=0)
 RETURNING expires_at INTO STRICT e;
 UPDATE c59s17c_fixture.cases SET payload=payload||jsonb_build_object('armedExpiry',e)WHERE case_id=cid AND owner_id=u;
 SET LOCAL ROLE NONE;RETURN e;END $f$;
CREATE FUNCTION c59s17c_fixture.arguments(u uuid,raw text,provider text) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $args$
 SELECT jsonb_build_object('p_user_id',u,'p_date','2026-10-15','p_workout_type',raw,'p_duration_min',60,'p_estimated_kcal',300,
 'p_intensity','moderada','p_notes','S17C preserved café 🏋️','p_performed_at','2026-10-15T12:00:00.123456Z','p_provider_message_id',provider,
 'p_calories_target',2000,'p_protein_target',150.25,'p_replace_recent',false,'p_replace_since',NULL) $args$;
CREATE FUNCTION c59s17c_fixture.legacy_sql(a jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $legacy$
 SELECT format('SELECT public.register_workout_atomic(%L::uuid,%L::date,%L,%L::integer,%L::integer,%L,%L,%L::timestamptz,%L,%L::integer,%L::numeric,%L::boolean,%L::timestamptz)',
 a->>'p_user_id',a->>'p_date',a->>'p_workout_type',a->>'p_duration_min',a->>'p_estimated_kcal',a->>'p_intensity',a->>'p_notes',a->>'p_performed_at',a->>'p_provider_message_id',a->>'p_calories_target',a->>'p_protein_target',a->>'p_replace_recent',a->>'p_replace_since') $legacy$;
DO $acl$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17c_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.oid::regprocedure);END LOOP;END $acl$;
REVOKE ALL ON ALL TABLES IN SCHEMA c59s17c_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE NONE;

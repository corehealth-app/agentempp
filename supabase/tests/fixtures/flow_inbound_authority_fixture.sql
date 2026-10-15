-- PRIVATE TEST SOURCE. No replacement product body; only real RPC calls.
CREATE SCHEMA c59s17i_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s17i_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s17i_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,fixture_fingerprint jsonb NOT NULL);
CREATE TABLE c59s17i_fixture.cases(case_id text PRIMARY KEY,owner_id uuid UNIQUE NOT NULL,payload jsonb NOT NULL);
CREATE FUNCTION c59s17i_fixture.uid(i integer)RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT ('c59f1700-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $f$;
CREATE FUNCTION c59s17i_fixture.ok(v boolean,label text)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S17I_ASSERT:%',label;END IF;RAISE NOTICE 'C59S17I_PASS:%',label;END $f$;
CREATE FUNCTION c59s17i_fixture.hash(t text)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT encode(sha256(convert_to(t,'UTF8')),'hex') $f$;
CREATE FUNCTION c59s17i_fixture.owner(i integer)RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE u uuid:=c59s17i_fixture.uid(i);BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision,last_active_at)
 VALUES(u,'155527'||lpad(i::text,7,'0'),'c59s17i-'||i||'@example.invalid','C59S17I synthetic','UTC','US',true,'{"c59s17i_fixture":"c59s17i_atomic_in_v1"}',17,'2026-01-01T00:00:00.000Z');
 INSERT INTO public.user_profiles(user_id,weight_kg)VALUES(u,70);
 INSERT INTO public.user_progress(user_id)VALUES(u);RETURN u;END $f$;
CREATE FUNCTION c59s17i_fixture.attempt(sql text,role_name text DEFAULT 'service_role')RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $f$
DECLARE r jsonb;s text;m text;BEGIN EXECUTE format('SET LOCAL ROLE %I',role_name);
 BEGIN EXECUTE sql INTO r;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;END;
 SET LOCAL ROLE NONE;IF s IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m);END IF;
 RETURN jsonb_build_object('ok',true,'result',r);END $f$;
CREATE FUNCTION c59s17i_fixture.seed(i integer,t text DEFAULT E'S17I café 🏋️\nUnicode é')RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE u uuid:=c59s17i_fixture.owner(i);k text:='s17i-request-'||i;r jsonb;BEGIN
 r:=c59s17i_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,k,c59s17i_fixture.hash(t)));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'admitted'THEN RAISE EXCEPTION 'C59S17I_SETUP_REAL_ADMIT:%',r;END IF;
 RETURN jsonb_build_object('ownerID',u,'requestKey',k,'text',t,'requestHash',c59s17i_fixture.hash(t),'admission',r#>'{result,admission}','requestID','s17i-original-request','startedAt','2026-10-15T12:00:00.123Z');END $f$;
CREATE FUNCTION c59s17i_fixture.access_sql(p jsonb,mode text DEFAULT 'persist',requestid text DEFAULT 's17i-original-request',started text DEFAULT '2026-10-15T12:00:00.123Z')RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.access_workout_strength_flow_inbound(%L::uuid,%L::uuid,%L,%L,%L,%L::timestamptz)',p->>'ownerID',p#>>'{admission,admissionID}',p->>'text',mode,CASE WHEN mode='probe'THEN NULL ELSE requestid END,CASE WHEN mode='probe'THEN NULL ELSE started END) $f$;
CREATE FUNCTION c59s17i_fixture.reset_sql(p jsonb,keep boolean DEFAULT true)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.reset_user_conversation_atomic(%L::uuid,%L::boolean)',p->>'ownerID',keep) $f$;
CREATE FUNCTION c59s17i_fixture.payload(cid text)RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT payload FROM c59s17i_fixture.cases WHERE case_id=cid $f$;
CREATE FUNCTION c59s17i_fixture.state(u uuid)RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
CREATE FUNCTION c59s17i_fixture.outside(u uuid)RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:='{}';has_user boolean;pred text;BEGIN
 FOR t IN SELECT n.nspname,c.relname,c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')ORDER BY n.nspname,c.relname LOOP
 SELECT EXISTS(SELECT 1 FROM pg_attribute x WHERE x.attrelid=t.oid AND x.attname='user_id'AND x.atttypid='uuid'::regtype AND x.attnum>0 AND NOT x.attisdropped)INTO has_user;
 pred:=CASE WHEN t.nspname='public'AND t.relname='users'THEN ' WHERE id IS DISTINCT FROM $1'WHEN has_user THEN ' WHERE user_id IS DISTINCT FROM $1'ELSE ''END;
 EXECUTE format('SELECT jsonb_build_object(''count'',count(*),''rows_md5'',md5(coalesce(string_agg(to_jsonb(x)::text,E''\n''ORDER BY to_jsonb(x)::text),'''')))FROM ONLY %I.%I x%s',t.nspname,t.relname,pred)INTO a USING u;r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
CREATE FUNCTION c59s17i_fixture.fingerprint()RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('schema',(SELECT jsonb_build_array(oid::text,nspowner::text,nspacl::text)FROM pg_namespace WHERE nspname='c59s17i_fixture'),
 'functions',(SELECT jsonb_object_agg(p.oid::text,md5(pg_get_functiondef(p.oid)||coalesce(p.proacl::text,'')||p.proowner::text))FROM pg_proc p WHERE p.pronamespace='c59s17i_fixture'::regnamespace),
 'relations',(SELECT jsonb_object_agg(c.oid::text,jsonb_build_object('name',c.relname,'owner',c.relowner::text,'acl',c.relacl::text,'kind',c.relkind,'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attcollation::text)ORDER BY a.attnum)FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'constraints',(SELECT jsonb_agg(jsonb_build_array(k.oid::text,md5(pg_get_constraintdef(k.oid,true)))ORDER BY k.oid)FROM pg_constraint k WHERE k.conrelid=c.oid),'indexes',(SELECT jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid)))ORDER BY i.indexrelid)FROM pg_index i WHERE i.indrelid=c.oid)))FROM pg_class c WHERE c.relnamespace='c59s17i_fixture'::regnamespace)) $f$;
CREATE FUNCTION c59s17i_fixture.expect_result(sql text,u uuid,expected jsonb)RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17i_fixture.state(u);o jsonb:=c59s17i_fixture.outside(u);r jsonb;BEGIN r:=c59s17i_fixture.attempt(sql);
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',expected)OR c59s17i_fixture.state(u)IS DISTINCT FROM s OR c59s17i_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17I_EXPECT_RESULT:%',r;END IF;END $f$;
CREATE FUNCTION c59s17i_fixture.expect_error(sql text,u uuid,code text,role_name text DEFAULT 'service_role',message text DEFAULT NULL)RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17i_fixture.state(u);o jsonb:=c59s17i_fixture.outside(u);r jsonb;BEGIN r:=c59s17i_fixture.attempt(sql,role_name);
 IF r->'ok'IS DISTINCT FROM 'false'::jsonb OR r->>'sqlstate'IS DISTINCT FROM code OR(message IS NOT NULL AND r->>'message'IS DISTINCT FROM message)OR c59s17i_fixture.state(u)IS DISTINCT FROM s OR c59s17i_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17I_EXPECT_ERROR:%',r;END IF;END $f$;
CREATE FUNCTION c59s17i_fixture.inserted(p jsonb)RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE r jsonb;BEGIN r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p));IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'inserted'THEN RAISE EXCEPTION 'C59S17I_SETUP_REAL_INSERT:%',r;END IF;RETURN r->'result';END $f$;
CREATE FUNCTION c59s17i_fixture.assert_reset(s jsonb,t jsonb)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE e jsonb:=t#>'{private.workout_strength_authority_epochs,0}';p jsonb:=t#>'{public.user_profiles,0}';g jsonb:=t#>'{public.user_progress,0}';BEGIN
 IF t->'public.messages'IS DISTINCT FROM '[]'::jsonb OR t->'private.workout_strength_request_admissions'IS DISTINCT FROM s->'private.workout_strength_request_admissions'
 OR e->>'epoch'IS NOT DISTINCT FROM s#>>'{private.workout_strength_authority_epochs,0,epoch}'OR e IS DISTINCT FROM(s#>'{private.workout_strength_authority_epochs,0}')||jsonb_build_object('epoch',e->'epoch','changed_at',e->'changed_at','current_lifecycle_key',NULL)
 OR t->'user'IS DISTINCT FROM(s->'user')||jsonb_build_object('name',NULL,'flow_phrase_cursor_revision',0,'summary',NULL,'summary_updated_at',NULL,'tags','[]'::jsonb,'admin_notes',NULL,'country_confirmed',false,'last_active_at',NULL,'metadata','{}'::jsonb,'updated_at',t#>'{user,updated_at}')
 OR p IS DISTINCT FROM(s#>'{public.user_profiles,0}')||jsonb_build_object('weight_kg',NULL,'weight_measured_at',NULL,'weight_instant_source',NULL,'onboarding_completed',false,'onboarding_step',0,'updated_at',p->'updated_at')
 OR g IS DISTINCT FROM(s#>'{public.user_progress,0}')||jsonb_build_object('updated_at',g->'updated_at')
 OR t-ARRAY['user','public.messages','public.user_profiles','public.user_progress','private.workout_strength_authority_epochs']IS DISTINCT FROM s-ARRAY['user','public.messages','public.user_profiles','public.user_progress','private.workout_strength_authority_epochs']THEN RAISE EXCEPTION 'C59S17I_RESET_DELTA';END IF;
 IF e->>'epoch'IS NULL OR NOT isfinite((e->>'changed_at')::timestamptz)THEN RAISE EXCEPTION 'C59S17I_RESET_EPOCH_CLOCK';END IF;END $f$;
CREATE FUNCTION c59s17i_fixture.fault_before_binding()RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF NEW.user_id=c59s17i_fixture.uid(4170)AND OLD.flow_inbound_id IS NULL AND NEW.flow_inbound_id IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM ONLY public.messages m WHERE m.id=NEW.flow_inbound_id AND m.user_id=NEW.user_id AND m.direction='in'AND m.provider='mobile_flow')OR(SELECT last_active_at FROM ONLY public.users WHERE id=NEW.user_id)IS DISTINCT FROM '2026-10-15T12:00:00.123Z'::timestamptz THEN RAISE EXCEPTION 'C59S17I_FAULT_ORDER_NOT_PROVED' USING ERRCODE='P0002';END IF;
 RAISE EXCEPTION 'C59S17I_AFTER_INSERT_BEFORE_BINDING' USING ERRCODE='P0001';END IF;RETURN NEW;END $f$;
CREATE FUNCTION c59s17i_fixture.unrelated_unique()RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF NEW.user_id=c59s17i_fixture.uid(4171)THEN RAISE EXCEPTION 'C59S17I_UNRELATED_UNIQUE' USING ERRCODE='23505',CONSTRAINT='c59s17i_unrelated_unique';END IF;RETURN NEW;END $f$;
DO $acl$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17i_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.oid::regprocedure);END LOOP;END $acl$;
REVOKE ALL ON ALL TABLES IN SCHEMA c59s17i_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE NONE;

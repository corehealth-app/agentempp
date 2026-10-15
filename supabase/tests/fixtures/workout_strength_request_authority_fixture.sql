-- TEST ONLY. Uses retained C5 real schema and the Root-installed S15 migration.
CREATE SCHEMA c59s15_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s15_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s15_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,object_oids jsonb NOT NULL,object_fingerprint jsonb NOT NULL,sentinel jsonb NOT NULL);
CREATE TABLE c59s15_fixture.cases(case_id text PRIMARY KEY,owner_id uuid UNIQUE NOT NULL,payload jsonb NOT NULL);
REVOKE ALL ON TABLE c59s15_fixture.ownership,c59s15_fixture.cases FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s15_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $ok$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S15_ASSERT:%',label;END IF;RAISE NOTICE 'C59S15_PASS:%',label;END $ok$;
CREATE FUNCTION c59s15_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $uid$
 SELECT ('c59b5000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $uid$;
CREATE FUNCTION c59s15_fixture.owner(i integer) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $owner$
DECLARE u uuid:=c59s15_fixture.uid(i);BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
 VALUES(u,'155515'||lpad(i::text,7,'0'),'c59s15-'||i||'@example.invalid','C59S15 synthetic','UTC','US',true,'{"c59s15_fixture":"c59s15_authority_v1"}',17);
 RETURN u;END $owner$;
CREATE FUNCTION c59s15_fixture.hash(t text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $hash$
 SELECT encode(sha256(convert_to(t,'UTF8')),'hex') $hash$;
CREATE FUNCTION c59s15_fixture.attempt(sql text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $attempt$
DECLARE v jsonb;s text;BEGIN BEGIN EXECUTE sql INTO v;RETURN jsonb_build_object('ok',true,'result',v);
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;RETURN jsonb_build_object('ok',false,'sqlstate',s);END;END $attempt$;
CREATE FUNCTION c59s15_fixture.inbound(u uuid,k text,t text) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $inbound$
DECLARE m uuid;BEGIN
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id,raw_payload)
 VALUES(u,'in','user','text',t,'mobile_flow','mobile_flow/'||u::text||'/'||k,'{"request_id":"c59s15-synthetic","conversation_id":"flow"}') RETURNING id INTO m;
 RETURN m;END $inbound$;
CREATE FUNCTION c59s15_fixture.seed(i integer,with_admission boolean DEFAULT true,with_init boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $seed$
DECLARE u uuid:=c59s15_fixture.owner(i);k text:='s15-request-'||i;t text:='C59S15 café 🏋️';r jsonb;p jsonb;m uuid;v jsonb;BEGIN
 p:=jsonb_build_object('ownerID',u::text,'requestKey',k,'content',t,'requestHash',c59s15_fixture.hash(t));
 IF with_admission THEN
  r:=public.admit_workout_strength_request(u,k,p->>'requestHash');
  IF r->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S15_SETUP_REAL_ADMISSION';END IF;
  m:=c59s15_fixture.inbound(u,k,t);p:=p||jsonb_build_object('admission',r->'admission','inboundID',m::text);
  IF with_init THEN
   v:=public.initialize_workout_strength_lifecycle(u,(r#>>'{admission,admissionID}')::uuid,m);
   IF v->>'status' IS DISTINCT FROM 'initialized' THEN RAISE EXCEPTION 'C59S15_SETUP_REAL_INIT';END IF;
   p:=p||jsonb_build_object('lifecycle',v->'lifecycle');
  END IF;
 END IF;RETURN p;END $seed$;
CREATE FUNCTION c59s15_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $state$
DECLARE t text;rows jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x) FROM ONLY public.users x WHERE id=u));BEGIN
 FOREACH t IN ARRAY ARRAY['public.messages','public.user_profiles','public.user_progress','public.workout_logs','public.daily_snapshots','public.pending_registrations','private.workout_strength_lifecycles','private.workout_strength_operations','private.workout_strength_facts','private.workout_strength_commands','private.workout_strength_calendar_scopes','private.workout_strength_authority_epochs','private.workout_strength_request_admissions'] LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM ONLY %s x WHERE user_id=$1',t) INTO rows USING u;
 r:=r||jsonb_build_object(t,rows);END LOOP;RETURN r;END $state$;
CREATE FUNCTION c59s15_fixture.admission_wire(r jsonb,u uuid,k text,h text,s text) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $wire$
 SELECT r->>'status'=s AND (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(r)key)=ARRAY['admission','status']
 AND (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(r->'admission')key)=ARRAY['admissionID','admittedAt','epoch','ownerID','requestHash','requestKey','requestNamespace']
 AND r#>>'{admission,ownerID}'=u::text AND r#>>'{admission,requestNamespace}'='mobile_flow_turn'
 AND r#>>'{admission,requestKey}'=k AND r#>>'{admission,requestHash}'=h
 AND EXISTS(SELECT 1 FROM private.workout_strength_request_admissions a WHERE a.user_id=u AND a.admission_id=(r#>>'{admission,admissionID}')::uuid
 AND a.epoch=(r#>>'{admission,epoch}')::uuid AND a.request_key=k AND a.request_hash=h
 AND to_char(a.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')=r#>>'{admission,admittedAt}') $wire$;
CREATE FUNCTION c59s15_fixture.lifecycle_wire(r jsonb,u uuid,s text) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $wire$
 SELECT r->>'status'=s AND (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(r)key)=ARRAY['lifecycle','status']
 AND (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(r->'lifecycle')key)=ARRAY['lifecycleKey','openedAt','ownerID']
 AND r#>>'{lifecycle,ownerID}'=u::text AND EXISTS(SELECT 1 FROM private.workout_strength_lifecycles l
 WHERE l.user_id=u AND l.lifecycle_key=(r#>>'{lifecycle,lifecycleKey}')::uuid AND l.closed_at IS NULL
 AND to_char(l.opened_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')=r#>>'{lifecycle,openedAt}') $wire$;
CREATE FUNCTION c59s15_fixture.fail_after_close() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fault$
BEGIN IF OLD.user_id=c59s15_fixture.uid(718) THEN
 IF NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=OLD.user_id AND closed_at IS NOT NULL)
 OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e JOIN private.workout_strength_request_admissions a USING(user_id)
 WHERE e.user_id=OLD.user_id AND e.current_lifecycle_key IS NULL AND e.epoch<>a.epoch)
 OR EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE user_id=OLD.user_id)
 THEN RAISE EXCEPTION 'C59S15_FAULT_ORDER_NOT_PROVED' USING ERRCODE='P0002';END IF;
 RAISE EXCEPTION 'C59S15_INJECTED_AFTER_EPOCH_AND_CLOSE' USING ERRCODE='P0001';END IF;RETURN OLD;END $fault$;
CREATE FUNCTION c59s15_fixture.object_oids() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $oids$
 SELECT jsonb_build_object('schema','c59s15_fixture'::regnamespace::oid::text,
 'relations',(SELECT jsonb_object_agg(n.nspname||'.'||c.relname,c.oid::text) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s15_fixture') AND c.relkind IN('r','p','v','m','S','i','I')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,p.oid::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s15_fixture') AND p.prokind IN('f','p')))
$oids$;
CREATE FUNCTION c59s15_fixture.object_fingerprint() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $fingerprint$
 WITH rels AS (SELECT c.* FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s15_fixture') AND c.relkind IN('r','p','v','m','S')),
 funcs AS (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s15_fixture') AND p.prokind IN('f','p'))
 SELECT jsonb_build_object('schemas',(SELECT jsonb_object_agg(nspname,jsonb_build_object('oid',oid::text,'owner',nspowner::text,'acl',nspacl::text)) FROM pg_namespace WHERE nspname IN('public','private','c59s15_fixture')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'definition_md5',md5(pg_get_functiondef(p.oid)),'comment_md5',md5(obj_description(p.oid,'pg_proc')))) FROM funcs p),
 'relations',(SELECT jsonb_object_agg(r.oid::regclass::text,jsonb_build_object('oid',r.oid::text,'owner',r.relowner::text,'acl',r.relacl::text,'kind',r.relkind,'rls',r.relrowsecurity,'forceRls',r.relforcerowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attcollation::text,md5(pg_get_expr(d.adbin,d.adrelid))) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.oid::text,c.conname,md5(pg_get_constraintdef(c.oid,true))) ORDER BY c.conname),'[]') FROM pg_constraint c WHERE c.conrelid=r.oid),
 'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid))) ORDER BY i.indexrelid),'[]') FROM pg_index i WHERE i.indrelid=r.oid),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_array(t.oid::text,t.tgname,t.tgenabled,t.tgisinternal,md5(pg_get_triggerdef(t.oid,true))) ORDER BY t.tgname),'[]') FROM pg_trigger t WHERE t.tgrelid=r.oid),
 'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('oid',p.oid::text,'name',p.polname,'relation',p.polrelid::text,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using_md5',md5(pg_get_expr(p.polqual,p.polrelid)),'check_md5',md5(pg_get_expr(p.polwithcheck,p.polrelid))) ORDER BY p.polname),'[]') FROM pg_policy p WHERE p.polrelid=r.oid))) FROM rels r),
 'sequences',(SELECT coalesce(jsonb_object_agg(c.oid::regclass::text,jsonb_build_object('oid',c.oid::text,'owner',c.relowner::text,'acl',c.relacl::text,'parameters',to_jsonb(s),'lastValue',v.last_value)),'{}') FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_sequences v ON v.schemaname=n.nspname AND v.sequencename=c.relname WHERE n.nspname IN('public','private','c59s15_fixture')))
$fingerprint$;
DO $revoke$DECLARE p record;BEGIN FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='c59s15_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.oid::regprocedure);END LOOP;END $revoke$;
SET LOCAL ROLE NONE;

-- TEST ONLY. Real retained C5 substrate and Root-installed S16; no product shadow or bootstrap.
CREATE SCHEMA c59s16_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s16_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s16_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,object_oids jsonb NOT NULL,object_fingerprint jsonb NOT NULL,sentinel jsonb NOT NULL);
CREATE TABLE c59s16_fixture.cases(case_id text PRIMARY KEY,owner_id uuid UNIQUE NOT NULL,payload jsonb NOT NULL);
REVOKE ALL ON TABLE c59s16_fixture.ownership,c59s16_fixture.cases FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s16_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $ok$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S16_ASSERT:%',label;END IF;RAISE NOTICE 'C59S16_PASS:%',label;END $ok$;
CREATE FUNCTION c59s16_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $uid$
 SELECT ('c59b6000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $uid$;
CREATE FUNCTION c59s16_fixture.owner(i integer) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $owner$
DECLARE u uuid:=c59s16_fixture.uid(i);BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
 VALUES(u,'155516'||lpad(i::text,7,'0'),'c59s16-'||i||'@example.invalid','C59S16 synthetic','UTC','US',true,'{"c59s16_fixture":"c59s16_ui_proposal_v1"}',17);
 RETURN u;END $owner$;
CREATE FUNCTION c59s16_fixture.input() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $input$
 SELECT '{"kind":"workout","workout_type":"C59S16 café 🏋️","duration_min":10,"intensity":"moderada"}'::jsonb $input$;
CREATE FUNCTION c59s16_fixture.proposal(k text,v jsonb,kcal integer DEFAULT 123) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $proposal$
 SELECT jsonb_build_object('kind','workout','workoutType',v->>'workout_type','durationMin',(v->>'duration_min')::integer,'kcalEst',kcal,'intensity',v->>'intensity',
 'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp',CASE WHEN v?'performed_at' THEN to_char((v->>'performed_at')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') ELSE '2026-10-15T12:00:00.000Z' END,
 'source_timezone','UTC','source_local_date',CASE WHEN v?'performed_at' THEN ((v->>'performed_at')::timestamptz AT TIME ZONE 'UTC')::date::text ELSE '2026-10-15' END,
 'raw_args',jsonb_build_object('workout_type',v->>'workout_type','duration_min',(v->>'duration_min')::integer,'intensity',v->>'intensity'),'express_eligible',false) $proposal$;
CREATE FUNCTION c59s16_fixture.attempt(sql text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $attempt$
DECLARE v jsonb;s text;BEGIN BEGIN EXECUTE sql INTO v;RETURN jsonb_build_object('ok',true,'result',v);
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;RETURN jsonb_build_object('ok',false,'sqlstate',s);END;END $attempt$;
CREATE FUNCTION c59s16_fixture.seed(i integer,bind boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $seed$
DECLARE u uuid:=c59s16_fixture.owner(i);k text:='s16-request-'||i;v jsonb:=c59s16_fixture.input();a jsonb;p jsonb;r jsonb;e timestamptz:=clock_timestamp()+interval '1 hour';BEGIN
 a:=public.admit_mobile_workout_proposal(u,k,v);
 IF a->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S16_SETUP_REAL_ADMISSION';END IF;
 p:=c59s16_fixture.proposal(k,v);r:=jsonb_build_object('ownerID',u::text,'requestKey',k,'input',v,'proposal',p,'expiresAt',e,'admission',a->'admission');
 IF bind THEN a:=public.materialize_mobile_workout_proposal(u,(r#>>'{admission,admissionID}')::uuid,v,p,e);
 IF a->>'status' IS DISTINCT FROM 'materialized' THEN RAISE EXCEPTION 'C59S16_SETUP_REAL_MATERIALIZE';END IF;r:=r||jsonb_build_object('materialized',a);END IF;RETURN r;END $seed$;
CREATE FUNCTION c59s16_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $state$
DECLARE t text;rows jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOREACH t IN ARRAY ARRAY['public.messages','public.user_profiles','public.user_progress','public.workout_logs','public.daily_snapshots','public.pending_registrations','private.workout_strength_lifecycles','private.workout_strength_operations','private.workout_strength_facts','private.workout_strength_commands','private.workout_strength_calendar_scopes','private.workout_strength_authority_epochs','private.workout_strength_request_admissions','private.mobile_workout_proposal_admissions'] LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM ONLY %s x WHERE user_id=$1',t) INTO rows USING u;r:=r||jsonb_build_object(t,rows);END LOOP;RETURN r;END $state$;
CREATE FUNCTION c59s16_fixture.admission_wire(r jsonb,u uuid,k text,h text,s text) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $wire$
 SELECT r->>'status'=s AND(SELECT array_agg(key ORDER BY key)FROM jsonb_object_keys(r)key)=ARRAY['admission','status']
 AND(SELECT array_agg(key ORDER BY key)FROM jsonb_object_keys(r->'admission')key)=ARRAY['admissionID','admittedAt','epoch','ownerID','requestHash','requestKey','requestNamespace']
 AND r#>>'{admission,ownerID}'=u::text AND r#>>'{admission,requestNamespace}'='mobile_workout_proposal_v1'
 AND r#>>'{admission,requestKey}'=k AND r#>>'{admission,requestHash}'=h
 AND EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a WHERE a.user_id=u AND a.admission_id=(r#>>'{admission,admissionID}')::uuid
 AND a.epoch=(r#>>'{admission,epoch}')::uuid AND a.request_key=k AND a.request_hash=h AND to_char(a.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')=r#>>'{admission,admittedAt}') $wire$;
CREATE FUNCTION c59s16_fixture.fail_after_cancel() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fault$
BEGIN IF NEW.user_id=c59s16_fixture.uid(718)AND NEW.proposal->>'source_provider_message_id'='s16-request-718' THEN
 IF NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE user_id=NEW.user_id AND status='cancelled')
 OR EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE user_id=NEW.user_id AND status='pending')
 OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=NEW.user_id AND pending_id IS NULL AND rejection_reason IS NULL)
 THEN RAISE EXCEPTION 'C59S16_FAULT_ORDER_NOT_PROVED' USING ERRCODE='P0002';END IF;
 RAISE EXCEPTION 'C59S16_INJECTED_AFTER_REAL_CANCEL' USING ERRCODE='P0001';END IF;RETURN NEW;END $fault$;
CREATE FUNCTION c59s16_fixture.fail_after_bind() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $bind_fault$
BEGIN IF NEW.user_id=c59s16_fixture.uid(718)AND OLD.pending_id IS NULL AND NEW.pending_id IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations p WHERE p.id=NEW.pending_id AND p.user_id=NEW.user_id AND p.status='pending'AND p.proposal->>'source_provider_message_id'=NEW.request_key)
 OR NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE user_id=NEW.user_id AND status='cancelled')
 OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a WHERE a.user_id=NEW.user_id AND a.admission_id=NEW.admission_id AND a.pending_id=NEW.pending_id AND a.first_proposal_hash=NEW.first_proposal_hash AND a.bound_at=NEW.bound_at)
 THEN RAISE EXCEPTION 'C59S16_BIND_FAULT_ORDER_NOT_PROVED' USING ERRCODE='P0002';END IF;
 RAISE EXCEPTION 'C59S16_INJECTED_AFTER_INSERT_AND_BIND' USING ERRCODE='P0001';END IF;RETURN NEW;END $bind_fault$;
CREATE FUNCTION c59s16_fixture.object_oids() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $oids$
 SELECT jsonb_build_object('schema','c59s16_fixture'::regnamespace::oid::text,
 'relations',(SELECT jsonb_object_agg(n.nspname||'.'||c.relname,c.oid::text) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s16_fixture') AND c.relkind IN('r','p','v','m','S','i','I')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,p.oid::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s16_fixture') AND p.prokind IN('f','p')))
$oids$;
CREATE FUNCTION c59s16_fixture.object_fingerprint() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $fingerprint$
 WITH rels AS (SELECT c.* FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s16_fixture') AND c.relkind IN('r','p','v','m','S')),
 funcs AS (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s16_fixture') AND p.prokind IN('f','p'))
 SELECT jsonb_build_object('schemas',(SELECT jsonb_object_agg(nspname,jsonb_build_object('oid',oid::text,'owner',nspowner::text,'acl',nspacl::text)) FROM pg_namespace WHERE nspname IN('public','private','c59s16_fixture')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'definition_md5',md5(pg_get_functiondef(p.oid)),'comment_md5',md5(obj_description(p.oid,'pg_proc')))) FROM funcs p),
 'relations',(SELECT jsonb_object_agg(r.oid::regclass::text,jsonb_build_object('oid',r.oid::text,'owner',r.relowner::text,'acl',r.relacl::text,'kind',r.relkind,'rls',r.relrowsecurity,'forceRls',r.relforcerowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attcollation::text,md5(pg_get_expr(d.adbin,d.adrelid))) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.oid::text,c.conname,md5(pg_get_constraintdef(c.oid,true))) ORDER BY c.conname),'[]') FROM pg_constraint c WHERE c.conrelid=r.oid),
 'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid))) ORDER BY i.indexrelid),'[]') FROM pg_index i WHERE i.indrelid=r.oid),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_array(t.oid::text,t.tgname,t.tgenabled,t.tgisinternal,md5(pg_get_triggerdef(t.oid,true))) ORDER BY t.tgname),'[]') FROM pg_trigger t WHERE t.tgrelid=r.oid),
 'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('oid',p.oid::text,'name',p.polname,'relation',p.polrelid::text,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using_md5',md5(pg_get_expr(p.polqual,p.polrelid)),'check_md5',md5(pg_get_expr(p.polwithcheck,p.polrelid))) ORDER BY p.polname),'[]') FROM pg_policy p WHERE p.polrelid=r.oid))) FROM rels r),
 'sequences',(SELECT coalesce(jsonb_object_agg(c.oid::regclass::text,jsonb_build_object('oid',c.oid::text,'owner',c.relowner::text,'acl',c.relacl::text,'parameters',to_jsonb(s),'lastValue',v.last_value)),'{}') FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_sequences v ON v.schemaname=n.nspname AND v.sequencename=c.relname WHERE n.nspname IN('public','private','c59s16_fixture')))
$fingerprint$;
DO $revoke$DECLARE p record;BEGIN FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='c59s16_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.oid::regprocedure);END LOOP;END $revoke$;
SET LOCAL ROLE NONE;

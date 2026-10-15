-- PRIVATE S17D TEST-FIRST SOURCE ONLY. No product body/caller/DDL replacement.
CREATE SCHEMA c59s17d_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s17d_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,fixture_fingerprint jsonb NOT NULL);
CREATE TABLE c59s17d_fixture.cases(case_id text PRIMARY KEY,owner_id uuid UNIQUE NOT NULL,payload jsonb NOT NULL);
CREATE TABLE c59s17d_fixture.catalogue_origin(row_data jsonb NOT NULL);
CREATE TABLE c59s17d_fixture.faults(owner_id uuid PRIMARY KEY,event text NOT NULL,sqlstate text NOT NULL);
CREATE FUNCTION c59s17d_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT ('c59d7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $f$;
CREATE FUNCTION c59s17d_fixture.key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wui1:'||c59s17d_fixture.uid(i)::text $f$;
CREATE FUNCTION c59s17d_fixture.edit_key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wue1:'||c59s17d_fixture.uid(i)::text $f$;
CREATE FUNCTION c59s17d_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S17D_ASSERT:%',label;END IF;RAISE NOTICE 'C59S17D_PASS:%',label;END $f$;
CREATE FUNCTION c59s17d_fixture.owner(i integer) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE u uuid:=c59s17d_fixture.uid(i);BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
 VALUES(u,'155519'||lpad(i::text,7,'0'),'c59s17d-'||i||'@example.invalid','C59S17D synthetic','UTC','US',true,'{"c59s17d_fixture":"c59s17d_confirm_v1"}',17);
 INSERT INTO public.user_profiles(user_id,weight_kg)VALUES(u,70);RETURN u;END $f$;
CREATE FUNCTION c59s17d_fixture.input(duration integer DEFAULT 40,raw text DEFAULT 'c59s17d-treino',performed text DEFAULT NULL) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workout_type',raw,'duration_min',duration,'intensity','moderada')||CASE WHEN performed IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('performed_at',performed)END $f$;
CREATE FUNCTION c59s17d_fixture.proposal(k text,v jsonb,kcal integer DEFAULT 400,ts text DEFAULT '2026-10-15T12:00:00.123Z') RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workoutType',v->>'workout_type','durationMin',v->'duration_min','kcalEst',kcal,'intensity',v->>'intensity',
 'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp',ts,'source_timezone','UTC','source_local_date',left(ts,10),
 'raw_args',jsonb_build_object('workout_type',v->>'workout_type','duration_min',v->'duration_min','intensity',v->>'intensity'),'express_eligible',false) $f$;
CREATE FUNCTION c59s17d_fixture.attempt(sql text,role_name text DEFAULT 'service_role') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $f$
DECLARE r jsonb;s text;m text;BEGIN EXECUTE format('SET LOCAL ROLE %I',role_name);
 BEGIN EXECUTE sql INTO r;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;END;
 SET LOCAL ROLE NONE;IF s IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m);END IF;
 RETURN jsonb_build_object('ok',true,'result',r);END $f$;
CREATE FUNCTION c59s17d_fixture.member(u uuid,k text,v jsonb,kcal integer DEFAULT 400) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE r jsonb;a jsonb;p jsonb:=c59s17d_fixture.proposal(k,v,kcal);e timestamptz:=clock_timestamp()+interval '6 hours';BEGIN
 r:=c59s17d_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_ADMIT:%',r;END IF;a:=r#>'{result,admission}';
 r:=c59s17d_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a->>'admissionID',v,p,e));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'materialized' THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_MATERIALIZE:%',r;END IF;
 RETURN jsonb_build_object('ownerID',u,'requestKey',k,'input',v,'proposal',p,'expiresAt',e,'admission',a,'materialized',r->'result','registrationID',r#>'{result,pendingID}');END $f$;
CREATE FUNCTION c59s17d_fixture.ui(i integer) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
BEGIN RETURN c59s17d_fixture.member(c59s17d_fixture.owner(i),c59s17d_fixture.key(i),c59s17d_fixture.input());END $f$;
CREATE FUNCTION c59s17d_fixture.edit_sql(u uuid,pid uuid,expected integer,k text,v jsonb,p jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.edit_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer,%L,%L::jsonb,%L::jsonb)',u,pid,expected,k,v,p) $f$;
CREATE FUNCTION c59s17d_fixture.cancel_sql(u uuid,pid uuid,expected integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.cancel_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer)',u,pid,expected) $f$;
CREATE FUNCTION c59s17d_fixture.registration(u uuid,pid uuid) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('id',p.id,'status',p.status,'created_at',p.created_at,'expires_at',p.expires_at,'resolved_at',p.resolved_at,'proposal',p.proposal,'workout_protocol','ui-v1','content_revision',a.content_revision)
 FROM ONLY public.pending_registrations p JOIN private.mobile_workout_proposal_admissions a ON a.user_id=p.user_id AND a.pending_id=p.id AND a.admission_id=p.workout_ui_admission_id
 WHERE p.user_id=u AND p.id=pid $f$;
CREATE FUNCTION c59s17d_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
CREATE FUNCTION c59s17d_fixture.outside(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:='{}';has_user boolean;pred text;BEGIN
 FOR t IN SELECT n.nspname,c.relname,c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')ORDER BY n.nspname,c.relname LOOP
 SELECT EXISTS(SELECT 1 FROM pg_attribute x WHERE x.attrelid=t.oid AND x.attname='user_id'AND x.atttypid='uuid'::regtype AND x.attnum>0 AND NOT x.attisdropped)INTO has_user;
 pred:=CASE WHEN t.nspname='public'AND t.relname='users'THEN ' WHERE id IS DISTINCT FROM $1'WHEN has_user THEN ' WHERE user_id IS DISTINCT FROM $1'ELSE ''END;
 EXECUTE format('SELECT jsonb_build_object(''count'',count(*),''rows_md5'',md5(coalesce(string_agg(to_jsonb(x)::text,E''\n''ORDER BY to_jsonb(x)::text),'''')))FROM ONLY %I.%I x%s',t.nspname,t.relname,pred)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
CREATE FUNCTION c59s17d_fixture.assert_unchanged_except(s jsonb,t jsonb,allowed text[],label text)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF s-allowed IS DISTINCT FROM t-allowed THEN RAISE EXCEPTION 'C59S17D_UNEXPECTED_EFFECT:%',label;END IF;END $f$;
CREATE FUNCTION c59s17d_fixture.expect_sqlstate(sql text,u uuid,code text,role_name text DEFAULT 'service_role',expected_message text DEFAULT NULL)RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17d_fixture.state(u);o jsonb:=c59s17d_fixture.outside(u);r jsonb;BEGIN r:=c59s17d_fixture.attempt(sql,role_name);
 IF r->>'sqlstate'IS DISTINCT FROM code OR r->'ok'IS DISTINCT FROM 'false'::jsonb OR(expected_message IS NOT NULL AND r->>'message'IS DISTINCT FROM expected_message)OR c59s17d_fixture.state(u)IS DISTINCT FROM s OR c59s17d_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17D_NATIVE_NEGATIVE:%:%',code,r;END IF;END $f$;
CREATE FUNCTION c59s17d_fixture.fingerprint()RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('schema',(SELECT jsonb_build_array(oid::text,nspowner::text,nspacl::text)FROM pg_namespace WHERE nspname='c59s17d_fixture'),
 'functions',(SELECT jsonb_object_agg(p.oid::text,md5(pg_get_functiondef(p.oid)||coalesce(p.proacl::text,'')||p.proowner::text))FROM pg_proc p WHERE p.pronamespace='c59s17d_fixture'::regnamespace),
 'relations',(SELECT jsonb_object_agg(c.oid::text,jsonb_build_object('name',c.relname,'owner',c.relowner::text,'acl',c.relacl::text,'kind',c.relkind,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attcollation::text)ORDER BY a.attnum)FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_array(k.oid::text,md5(pg_get_constraintdef(k.oid,true)))ORDER BY k.oid)FROM pg_constraint k WHERE k.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid)))ORDER BY i.indexrelid)FROM pg_index i WHERE i.indrelid=c.oid)))FROM pg_class c WHERE c.relnamespace='c59s17d_fixture'::regnamespace)) $f$;
CREATE FUNCTION c59s17d_fixture.legacy_sql(a jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $legacy$
 SELECT format('SELECT public.register_workout_atomic(%L::uuid,%L::date,%L,%L::integer,%L::integer,%L,%L,%L::timestamptz,%L,%L::integer,%L::numeric,%L::boolean,%L::timestamptz)',
 a->>'p_user_id',a->>'p_date',a->>'p_workout_type',a->>'p_duration_min',a->>'p_estimated_kcal',a->>'p_intensity',a->>'p_notes',a->>'p_performed_at',a->>'p_provider_message_id',a->>'p_calories_target',a->>'p_protein_target',a->>'p_replace_recent',a->>'p_replace_since') $legacy$;
CREATE FUNCTION c59s17d_fixture.confirm_sql(u uuid,pid uuid,expected integer,a jsonb,o jsonb,d jsonb)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.confirm_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer,%L::jsonb,%L::jsonb,%L::jsonb)',u,pid,expected,a,o,d) $f$;
CREATE FUNCTION c59s17d_fixture.operation_key(a uuid,r integer)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'ui:'||a::text||':r:'||r::text $f$;
-- Explicit official preparation literals, not a new calorie formula or an HTTP payload.
CREATE FUNCTION c59s17d_fixture.legacy_arguments(u uuid,p jsonb,day text DEFAULT NULL,kcal integer DEFAULT 525)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('p_user_id',u,'p_date',coalesce(day,p->>'source_local_date'),'p_workout_type',p->'workoutType','p_duration_min',p->'durationMin','p_estimated_kcal',kcal,'p_intensity',p->'intensity','p_notes','S17D café 🏋️','p_performed_at',p->'source_timestamp','p_provider_message_id',p->'source_provider_message_id','p_calories_target',2200,'p_protein_target',150.125,'p_replace_recent',false,'p_replace_since',NULL) $f$;
CREATE FUNCTION c59s17d_fixture.catalogue_decision(o jsonb,raw text)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT CASE WHEN raw='c59s17d-treino'THEN jsonb_build_object('status','matched','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'method','active_slug','selectedRowID',c59s17d_fixture.uid(9901))
 ELSE jsonb_build_object('status','unrecognized','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'reason','no_active_match')END $f$;
CREATE FUNCTION c59s17d_fixture.catalogue_state()RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY id),'[]'::jsonb)FROM ONLY public.workout_types x $f$;
CREATE FUNCTION c59s17d_fixture.payload_refresh_catalogue(cid text)RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE c record;o jsonb;p jsonb;BEGIN
 IF current_user<>session_user OR session_user<>'c5_local_admin'THEN RAISE EXCEPTION 'C59S17D_QA_OWNER_REQUIRED';END IF;
 SELECT * INTO STRICT c FROM c59s17d_fixture.ownership WHERE tag='c59s17d_confirm_v1';IF c.owner_name<>session_user OR c.fixture_fingerprint IS DISTINCT FROM c59s17d_fixture.fingerprint()THEN RAISE EXCEPTION 'C59S17D_QA_OWNERSHIP';END IF;
 SELECT payload INTO STRICT p FROM c59s17d_fixture.cases WHERE case_id=cid AND owner_id=(payload->>'ownerID')::uuid;
 o:=public.get_workout_strength_catalogue_context();IF o->>'status'IS DISTINCT FROM 'available'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_CATALOGUE';END IF;
 p:=p||jsonb_build_object('catalogueObservation',o,'catalogueDecision',c59s17d_fixture.catalogue_decision(o,p#>>'{proposal,workoutType}'));
 UPDATE c59s17d_fixture.cases SET payload=p WHERE case_id=cid;RETURN p;END $f$;
CREATE FUNCTION c59s17d_fixture.mutate_catalogue(cid text)RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE baseline jsonb;r jsonb;BEGIN
 IF current_user<>session_user OR session_user<>'c5_local_admin'OR cid NOT IN('catalogue-mutation-confirm-commit','catalogue-mutation-confirm-rollback')OR NOT EXISTS(SELECT 1 FROM c59s17d_fixture.cases WHERE case_id=cid AND owner_id=c59s17d_fixture.uid(CASE cid WHEN 'catalogue-mutation-confirm-commit'THEN 2818 ELSE 2819 END))THEN RAISE EXCEPTION 'C59S17D_CATALOGUE_SCOPE';END IF;
 SELECT row_data INTO STRICT baseline FROM c59s17d_fixture.catalogue_origin;
 IF NOT EXISTS(SELECT 1 FROM ONLY public.workout_types t WHERE id=c59s17d_fixture.uid(9901)AND to_jsonb(t)-ARRAY['display_name','updated_at']=baseline-ARRAY['display_name','updated_at'])THEN RAISE EXCEPTION 'C59S17D_CATALOGUE_ORIGIN_DRIFT';END IF;
 UPDATE ONLY public.workout_types t SET display_name='S17D changed '||cid WHERE id=c59s17d_fixture.uid(9901)RETURNING to_jsonb(t)INTO STRICT r;RETURN r;END $f$;
CREATE FUNCTION c59s17d_fixture.catalogue_mutation_sql(cid text)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT c59s17d_fixture.mutate_catalogue(%L)',cid) $f$;
-- Only this explicit fixture producer writes a REAL Flow IN. UI helpers never call it implicitly.
CREATE FUNCTION c59s17d_fixture.flow(u uuid,k text DEFAULT NULL)RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE key text:=coalesce(k,'s17d-flow-'||gen_random_uuid()::text);text_in text:='S17D synthetic Flow lifecycle';a jsonb;r jsonb;mid uuid;BEGIN
 r:=c59s17d_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L,%L,%L)',u,key,encode(sha256(convert_to(text_in,'UTF8')),'hex')));
 IF r#>>'{result,status}'IS DISTINCT FROM 'admitted'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_FLOW_ADMIT:%',r;END IF;a:=r#>'{result,admission}';
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id,raw_payload)VALUES(u,'in','user','text',text_in,'mobile_flow','mobile_flow/'||u::text||'/'||key,'{"request_id":"c59s17d-flow-synthetic","conversation_id":"flow"}')RETURNING id INTO mid;
 r:=c59s17d_fixture.attempt(format('SELECT public.initialize_workout_strength_lifecycle(%L,%L,%L)',u,a->>'admissionID',mid));
 IF r#>>'{result,status}'IS DISTINCT FROM 'initialized'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_FLOW_INIT:%',r;END IF;
 RETURN jsonb_build_object('admission',a,'inboundID',mid,'lifecycle',r#>'{result,lifecycle}');END $f$;
CREATE FUNCTION c59s17d_fixture.seed_capture(u uuid,l uuid,a jsonb)RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE k text:='s17d-seed-'||gen_random_uuid()::text;r jsonb;command jsonb;BEGIN
 command:=public.read_or_admit_workout_strength_command(u,l,k,a->>'p_workout_type',a);
 IF command IS NULL OR command->'legacyArguments'IS DISTINCT FROM a THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_S7';END IF;
 r:=c59s17d_fixture.attempt(format('SELECT public.register_workout_strength_atomic(%L,%L,%L,%L,NULL,''{"status":"unavailable","reason":"catalogue_read_error"}''::jsonb)',u,l,k,a->>'p_workout_type'));
 IF r#>>'{result,strength,status}'IS DISTINCT FROM 'committed'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_S8:%',r;END IF;RETURN jsonb_build_object('operationKey',k,'capture',r->'result');END $f$;
CREATE FUNCTION c59s17d_fixture.capture_evidence(u uuid,pid uuid)RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE a record;o record;key text;raw text;resolved jsonb;BEGIN
 SELECT * INTO STRICT a FROM private.mobile_workout_proposal_admissions WHERE user_id=u AND pending_id=pid;
 SELECT proposal->>'workoutType'INTO STRICT raw FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;key:=c59s17d_fixture.operation_key(a.admission_id,a.content_revision);
 SELECT * INTO o FROM private.workout_strength_operations WHERE user_id=u AND lifecycle_key=a.confirmed_lifecycle_key AND operation_kind='capture'AND operation_key=(key COLLATE "C")AND original_operation_type=(raw COLLATE "C");
 IF NOT FOUND THEN RETURN jsonb_build_object('operation',NULL,'resolved',NULL);END IF;
 resolved:=public.resolve_confirmed_workout_strength_capture(u,a.confirmed_lifecycle_key,key,raw);
 RETURN jsonb_build_object('operation',to_jsonb(o),'command',(SELECT to_jsonb(c)FROM private.workout_strength_commands c WHERE c.user_id=u AND c.lifecycle_key=a.confirmed_lifecycle_key AND c.operation_key=(key COLLATE "C")AND c.original_operation_type=(raw COLLATE "C")),
 'workout',(SELECT to_jsonb(w)FROM ONLY public.workout_logs w WHERE w.user_id=u AND w.id=o.live_workout_log_id),'snapshot',(SELECT to_jsonb(s)FROM ONLY public.daily_snapshots s JOIN ONLY public.workout_logs w ON w.user_id=s.user_id AND w.snapshot_id=s.id WHERE w.user_id=u AND w.id=o.live_workout_log_id),
 'fact',(SELECT to_jsonb(f)FROM private.workout_strength_facts f WHERE f.user_id=u AND f.lifecycle_key=a.confirmed_lifecycle_key AND f.workout_log_id=o.live_workout_log_id),'resolved',resolved);END $f$;
CREATE FUNCTION c59s17d_fixture.expect_result(sql text,u uuid,expected jsonb)RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=c59s17d_fixture.state(u);o jsonb:=c59s17d_fixture.outside(u);r jsonb;BEGIN r:=c59s17d_fixture.attempt(sql);
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',expected)OR c59s17d_fixture.state(u)IS DISTINCT FROM s OR c59s17d_fixture.outside(u)IS DISTINCT FROM o THEN RAISE EXCEPTION 'C59S17D_NEGATIVE_OR_REPLAY:%',r;END IF;END $f$;
CREATE FUNCTION c59s17d_fixture.arm_expiry_case(cid text)RETURNS timestamptz LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE u uuid:=c59s17d_fixture.uid(2813);pid uuid;e timestamptz;c record;BEGIN
 IF current_user<>session_user OR session_user<>'c5_local_admin'OR cid<>'expiry-confirm-after-rowlock'THEN RAISE EXCEPTION 'C59S17D_EXPIRY_SCOPE';END IF;
 SELECT * INTO STRICT c FROM c59s17d_fixture.ownership WHERE tag='c59s17d_confirm_v1';IF c.owner_name<>session_user OR c.fixture_fingerprint IS DISTINCT FROM c59s17d_fixture.fingerprint()THEN RAISE EXCEPTION 'C59S17D_EXPIRY_OWNERSHIP';END IF;
 SELECT(payload->>'registrationID')::uuid INTO STRICT pid FROM c59s17d_fixture.cases WHERE case_id=cid AND owner_id=u;
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations p SET expires_at=clock_timestamp()+interval '5 seconds'WHERE p.user_id=u AND p.id=pid AND p.status='pending'AND EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions a WHERE a.user_id=u AND a.pending_id=pid AND a.admission_id=p.workout_ui_admission_id AND a.content_revision=0)RETURNING expires_at INTO STRICT e;
 UPDATE c59s17d_fixture.cases SET payload=payload||jsonb_build_object('armedExpiry',e)WHERE case_id=cid;SET LOCAL ROLE NONE;RETURN e;END $f$;
CREATE FUNCTION c59s17d_fixture.fail_checkpoint()RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
DECLARE setting record;BEGIN
 SELECT * INTO setting FROM c59s17d_fixture.faults WHERE owner_id=NEW.user_id AND event=TG_ARGV[0];
 IF FOUND THEN RAISE EXCEPTION USING ERRCODE=setting.sqlstate,MESSAGE='C59S17D_INJECTED_AFTER_'||setting.event;END IF;RETURN NEW;END $f$;
CREATE FUNCTION c59s17d_fixture.assert_confirmed(r jsonb,s jsonb,global_before jsonb,u uuid,pid uuid,args jsonb,lo timestamptz,hi timestamptz,resolution text,outcome text,anchor uuid DEFAULT NULL)RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE t jsonb:=c59s17d_fixture.state(u);ev jsonb:=c59s17d_fixture.capture_evidence(u,pid);op jsonb;cmd jsonb;w jsonb;snap jsonb;j jsonb;oldj jsonb;p jsonb;oldp jsonb;epoch jsonb;old_epoch jsonb;life jsonb;key text;life_id text;wid text;expected_capture jsonb;normalized_strength jsonb;row_item jsonb;oldrow jsonb;target jsonb;oldtarget jsonb;created_life boolean;BEGIN
 op:=ev->'operation';cmd:=ev->'command';w:=ev->'workout';snap:=ev->'snapshot';
 SELECT x INTO STRICT j FROM jsonb_array_elements(t->'private.mobile_workout_proposal_admissions')x WHERE x->>'pending_id'=pid::text;
 SELECT x INTO STRICT oldj FROM jsonb_array_elements(s->'private.mobile_workout_proposal_admissions')x WHERE x->>'pending_id'=pid::text;
 SELECT x INTO STRICT p FROM jsonb_array_elements(t->'public.pending_registrations')x WHERE x->>'id'=pid::text;
 SELECT x INTO STRICT oldp FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->>'id'=pid::text;
 life_id:=j->>'confirmed_lifecycle_key';key:=c59s17d_fixture.operation_key((j->>'admission_id')::uuid,(j->>'content_revision')::integer);wid:=op->>'original_workout_log_id';
 IF life_id IS NULL OR op->>'resolution'IS DISTINCT FROM resolution OR op->>'capture_outcome'IS DISTINCT FROM outcome OR op->>'user_id'IS DISTINCT FROM u::text OR op->>'lifecycle_key'IS DISTINCT FROM life_id OR op->>'operation_kind'IS DISTINCT FROM 'capture'OR op->>'operation_key'IS DISTINCT FROM key OR op->>'original_operation_type'IS DISTINCT FROM p#>>'{proposal,workoutType}'OR op->>'live_workout_log_id'IS DISTINCT FROM wid OR(anchor IS NOT NULL AND wid IS DISTINCT FROM anchor::text)THEN RAISE EXCEPTION 'C59S17D_CAPTURE_IDENTITY_OR_OUTCOME';END IF;
 expected_capture:=jsonb_build_object('legacy_result',op->'legacy_result','strength',ev->'resolved');
 IF outcome='fact'AND resolution='sql_insert'THEN expected_capture:=jsonb_set(expected_capture,'{strength,status}','"committed"');END IF;
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','confirmed','registration',c59s17d_fixture.registration(u,pid),'capture',expected_capture))THEN RAISE EXCEPTION 'C59S17D_CONFIRM_EXACT_WIRE:%',r;END IF;
 IF outcome='fact'THEN
 IF ev#>>'{resolved,status}'IS DISTINCT FROM 'reuse_existing'OR ev#>>'{resolved,binding,ownerID}'IS DISTINCT FROM u::text OR ev#>>'{resolved,binding,lifecycleKey}'IS DISTINCT FROM life_id OR ev#>>'{resolved,binding,operationKey}'IS DISTINCT FROM key OR ev#>>'{resolved,binding,workoutLogID}'IS DISTINCT FROM wid OR ev#>>'{resolved,fact,anchor,snapshotID}'IS DISTINCT FROM w->>'snapshot_id'OR ev#>>'{fact,snapshot_id}'IS DISTINCT FROM w->>'snapshot_id'THEN RAISE EXCEPTION 'C59S17D_FACT_PROOF_REAL_RESOLVER';END IF;
 ELSE IF ev->'resolved'IS DISTINCT FROM jsonb_build_object('status','unavailable','reason','legacy_provenance_gap','confirmedWorkoutLogID',wid)OR EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u AND workout_log_id=wid::uuid)THEN RAISE EXCEPTION 'C59S17D_GAP_UNPROVED_OR_BACKFILLED';END IF;END IF;
 IF j IS DISTINCT FROM oldj||jsonb_build_object('confirmed_lifecycle_key',life_id)OR p IS DISTINCT FROM oldp||jsonb_build_object('status','confirmed','resolved_at',p->'resolved_at')OR p->>'resolved_at'IS NULL OR NOT isfinite((p->>'resolved_at')::timestamptz)OR(p->>'resolved_at')::timestamptz<lo OR(p->>'resolved_at')::timestamptz>hi OR(p->>'resolved_at')::timestamptz<(op->>'created_at')::timestamptz THEN RAISE EXCEPTION 'C59S17D_CONFIRM_ONLY_LINK_STATUS_RESOLVED_AFTER_CAPTURE';END IF;
 epoch:=t#>'{private.workout_strength_authority_epochs,0}';old_epoch:=s#>'{private.workout_strength_authority_epochs,0}';created_life:=old_epoch->'current_lifecycle_key'='null'::jsonb;
 IF epoch IS DISTINCT FROM old_epoch||jsonb_build_object('current_lifecycle_key',life_id)THEN RAISE EXCEPTION 'C59S17D_EPOCH_ONLY_CURRENT_POINTER';END IF;
 IF created_life THEN
 IF jsonb_array_length(t->'private.workout_strength_lifecycles')<>jsonb_array_length(s->'private.workout_strength_lifecycles')+1 THEN RAISE EXCEPTION 'C59S17D_ONE_NEW_LIFE';END IF;
 SELECT x INTO STRICT life FROM jsonb_array_elements(t->'private.workout_strength_lifecycles')x WHERE x->>'lifecycle_key'=life_id;
 IF life IS DISTINCT FROM jsonb_build_object('user_id',u,'lifecycle_key',life_id,'opened_at',life->'opened_at','closed_at',NULL,'close_operation_key',NULL)OR(life->>'opened_at')::timestamptz<lo OR(life->>'opened_at')::timestamptz>hi THEN RAISE EXCEPTION 'C59S17D_NEW_LIFE_OWNED_DB_CLOCK';END IF;
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.workout_strength_lifecycles')x WHERE x<>life)IS DISTINCT FROM s->'private.workout_strength_lifecycles'THEN RAISE EXCEPTION 'C59S17D_OLD_LIVES_CHANGED';END IF;
 ELSE IF t->'private.workout_strength_lifecycles'IS DISTINCT FROM s->'private.workout_strength_lifecycles'THEN RAISE EXCEPTION 'C59S17D_REUSED_LIFE_CHANGED';END IF;END IF;
 IF cmd->'legacy_arguments'IS DISTINCT FROM args OR(cmd->'legacy_arguments')::text IS DISTINCT FROM args::text OR cmd->>'user_id'IS DISTINCT FROM u::text OR cmd->>'lifecycle_key'IS DISTINCT FROM life_id OR cmd->>'operation_key'IS DISTINCT FROM key OR cmd->>'original_operation_type'IS DISTINCT FROM p#>>'{proposal,workoutType}'OR(cmd->>'recent_cutoff')::timestamptz IS DISTINCT FROM(cmd->>'admitted_at')::timestamptz-interval '6 hours'THEN RAISE EXCEPTION 'C59S17D_S7_EXACT_THIRTEEN_LITERAL_CUTOFF';END IF;
 SELECT x INTO oldrow FROM jsonb_array_elements(s->'private.workout_strength_commands')x WHERE x->>'lifecycle_key'=life_id AND x->>'operation_key'=key AND x->>'original_operation_type'=p#>>'{proposal,workoutType}';
 IF oldrow IS NOT NULL THEN IF cmd IS DISTINCT FROM oldrow THEN RAISE EXCEPTION 'C59S17D_STORED_COMMAND_OVERWRITTEN';END IF;
 ELSE IF(cmd->>'admitted_at')::timestamptz<lo OR(cmd->>'admitted_at')::timestamptz>hi THEN RAISE EXCEPTION 'C59S17D_COMMAND_CLOCK';END IF;END IF;
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.workout_strength_commands')x WHERE x->>'lifecycle_key'IS DISTINCT FROM life_id OR x->>'operation_key'IS DISTINCT FROM key OR x->>'original_operation_type'IS DISTINCT FROM p#>>'{proposal,workoutType}')IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'private.workout_strength_commands')x WHERE x->>'lifecycle_key'IS DISTINCT FROM life_id OR x->>'operation_key'IS DISTINCT FROM key OR x->>'original_operation_type'IS DISTINCT FROM p#>>'{proposal,workoutType}')THEN RAISE EXCEPTION 'C59S17D_OTHER_COMMAND_CHANGED';END IF;
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.workout_strength_operations')x WHERE x<>op)IS DISTINCT FROM s->'private.workout_strength_operations'THEN RAISE EXCEPTION 'C59S17D_ONLY_ONE_CAPTURE_BINDING';END IF;
 IF resolution='sql_insert'THEN
 IF w->>'id'IS DISTINCT FROM wid OR w->>'user_id'IS DISTINCT FROM u::text OR w->>'workout_type'IS DISTINCT FROM btrim(args->>'p_workout_type')OR w->'duration_min'IS DISTINCT FROM args->'p_duration_min'OR w->'estimated_kcal'IS DISTINCT FROM args->'p_estimated_kcal'OR w->'intensity'IS DISTINCT FROM args->'p_intensity'OR w->'notes'IS DISTINCT FROM args->'p_notes'OR w->'raw_provider_message_id'IS DISTINCT FROM args->'p_provider_message_id'OR(w->>'performed_at')::timestamptz IS DISTINCT FROM(args->>'p_performed_at')::timestamptz THEN RAISE EXCEPTION 'C59S17D_REAL13_WORKOUT_LITERAL';END IF;
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'public.workout_logs')x WHERE x->>'id'<>wid)IS DISTINCT FROM s->'public.workout_logs'OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.workout_strength_facts')x WHERE x->>'workout_log_id'<>wid)IS DISTINCT FROM s->'private.workout_strength_facts'THEN RAISE EXCEPTION 'C59S17D_NEW_WORKOUT_FACT_OLD_ROWS_PRESERVED';END IF;
 ELSE IF t->'public.workout_logs'IS DISTINCT FROM s->'public.workout_logs'OR t->'private.workout_strength_facts'IS DISTINCT FROM s->'private.workout_strength_facts'THEN RAISE EXCEPTION 'C59S17D_DEDUP_NO_NEW_WORKOUT_OR_FACT';END IF;END IF;
 IF resolution IN('provider_type_dedup','recent6h_dedup')THEN IF t->'public.daily_snapshots'IS DISTINCT FROM s->'public.daily_snapshots'OR op->'legacy_result'IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'C59S17D_EARLY_DEDUP_NO_SNAPSHOT_OR_LEGACY';END IF;
 ELSE
 SELECT x INTO STRICT target FROM jsonb_array_elements(t->'public.daily_snapshots')x WHERE (x->>'date')::date=(args->>'p_date')::date;
 SELECT x INTO oldtarget FROM jsonb_array_elements(s->'public.daily_snapshots')x WHERE (x->>'date')::date=(args->>'p_date')::date;
 IF target->'exercise_calories'IS DISTINCT FROM to_jsonb((SELECT coalesce(sum(estimated_kcal),0)::integer FROM ONLY public.workout_logs WHERE user_id=u AND snapshot_id=(target->>'id')::uuid))OR target->'training_done'IS DISTINCT FROM to_jsonb(EXISTS(SELECT 1 FROM ONLY public.workout_logs WHERE user_id=u AND snapshot_id=(target->>'id')::uuid))THEN RAISE EXCEPTION 'C59S17D_OFFICIAL_SNAPSHOT_COUNTERS';END IF;
 IF oldtarget IS NOT NULL AND target-ARRAY['calories_target','protein_target','exercise_calories','training_done','updated_at','daily_balance']IS DISTINCT FROM oldtarget-ARRAY['calories_target','protein_target','exercise_calories','training_done','updated_at','daily_balance']THEN RAISE EXCEPTION 'C59S17D_EXISTING_SNAPSHOT_OTHER_FIELDS_CHANGED';END IF;
 IF target->'calories_target'IS DISTINCT FROM coalesce(nullif(oldtarget->'calories_target','null'::jsonb),args->'p_calories_target')OR target->'protein_target'IS DISTINCT FROM coalesce(nullif(oldtarget->'protein_target','null'::jsonb),coalesce(to_jsonb((args->>'p_protein_target')::numeric(6,2)),'null'::jsonb))THEN RAISE EXCEPTION 'C59S17D_OFFICIAL_TARGETS_FIRST_PREPARATION';END IF;
 IF op->'legacy_result'IS DISTINCT FROM jsonb_build_object('snapshot_id',target->'id','workout_log_id',wid,'inserted',resolution='sql_insert','replaced_count',0,'exercise_calories',target->'exercise_calories','training_done',target->'training_done','calories_target',target->'calories_target','protein_target',target->'protein_target')THEN RAISE EXCEPTION 'C59S17D_X26_EXACT_ATTEMPT_LEGACY_RESULT';END IF;
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'public.daily_snapshots')x WHERE (x->>'date')::date<>(args->>'p_date')::date)IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'public.daily_snapshots')x WHERE (x->>'date')::date<>(args->>'p_date')::date)THEN RAISE EXCEPTION 'C59S17D_OTHER_SNAPSHOTS_CHANGED';END IF;
 END IF;
 PERFORM c59s17d_fixture.assert_unchanged_except(s,t,ARRAY['public.pending_registrations','private.mobile_workout_proposal_admissions','private.workout_strength_authority_epochs','private.workout_strength_lifecycles','private.workout_strength_commands','private.workout_strength_operations','public.workout_logs','public.daily_snapshots','private.workout_strength_facts'],'confirmation');
 IF(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.mobile_workout_proposal_admissions')x WHERE(x->>'pending_id')IS DISTINCT FROM pid::text)IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'private.mobile_workout_proposal_admissions')x WHERE(x->>'pending_id')IS DISTINCT FROM pid::text)
 OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'public.pending_registrations')x WHERE x->>'id'<>pid::text)IS DISTINCT FROM(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(s->'public.pending_registrations')x WHERE x->>'id'<>pid::text)OR c59s17d_fixture.outside(u)IS DISTINCT FROM global_before THEN RAISE EXCEPTION 'C59S17D_NEIGHBOR_OR_GLOBAL_OUTSIDE_CHANGED';END IF;
END $f$;
CREATE FUNCTION c59s17d_fixture.assert_cleanup_case(cid text,u uuid,payload jsonb)RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE s jsonb:=payload->'initialState';t jsonb:=c59s17d_fixture.state(u);j jsonb;oldj jsonb;p jsonb;oldp jsonb;e jsonb;revision integer;expected_proposal jsonb;args jsonb;ev jsonb;link text;BEGIN
 IF s IS NULL OR payload->>'ownerID'IS DISTINCT FROM u::text OR s#>>'{user,name}'IS DISTINCT FROM 'C59S17D synthetic'OR s#>'{user,metadata}'IS DISTINCT FROM '{"c59s17d_fixture":"c59s17d_confirm_v1"}'::jsonb THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_OWNERSHIP_PAYLOAD';END IF;
 IF cid='sentinel'THEN IF t IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_SENTINEL_CHANGED';END IF;RETURN;END IF;
 IF jsonb_array_length(t->'private.mobile_workout_proposal_admissions')<>1 OR jsonb_array_length(t->'public.pending_registrations')>1 OR jsonb_array_length(t->'private.mobile_workout_registration_edit_receipts')>1 THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_MEMBERSHIP_COUNTS';END IF;
 j:=t#>'{private.mobile_workout_proposal_admissions,0}';oldj:=s#>'{private.mobile_workout_proposal_admissions,0}';revision:=(j->>'content_revision')::integer;link:=j->>'confirmed_lifecycle_key';
 IF revision NOT IN(0,1)OR j IS DISTINCT FROM oldj||jsonb_build_object('content_revision',revision,'confirmed_lifecycle_key',j->'confirmed_lifecycle_key')THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_JOURNAL_CHANGED';END IF;
 e:=t#>'{private.mobile_workout_registration_edit_receipts,0}';
 IF revision=0 THEN IF e IS NOT NULL THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_EXTRA_RECEIPT';END IF;expected_proposal:=payload->'proposal';args:=payload->'legacyArguments';
 ELSE IF e IS DISTINCT FROM jsonb_build_object('user_id',u,'admission_id',j->'admission_id','request_key',payload->'editKeyA','input_hash',payload->'inputHashA','expected_revision',0,'result_revision',1)THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_EDIT_RECEIPT';END IF;expected_proposal:=payload->'editProposalA';args:=payload->'legacyArgumentsEditedA';END IF;
 p:=t#>'{public.pending_registrations,0}';oldp:=s#>'{public.pending_registrations,0}';
 IF p IS NULL THEN
 IF cid NOT IN('reset-confirm-commit','delete-pending-confirm-commit')OR revision<>0 OR link IS NOT NULL THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_PENDING_MISSING';END IF;
 ELSE IF p-ARRAY['status','resolved_at','proposal','expires_at']IS DISTINCT FROM oldp-ARRAY['status','resolved_at','proposal','expires_at']OR p->'proposal'IS DISTINCT FROM expected_proposal OR p->>'status'NOT IN('pending','cancelled','expired','confirmed')OR NOT isfinite((p->>'expires_at')::timestamptz)THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_PENDING_SHAPE';END IF;
 IF p->>'status'='pending'AND p->'resolved_at'IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_PENDING_RESOLVED';END IF;
 IF p->>'status'<>'pending'AND(p->>'resolved_at'IS NULL OR NOT isfinite((p->>'resolved_at')::timestamptz))THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_TERMINAL_CLOCK';END IF;END IF;
 IF p->>'status'='confirmed'THEN
 -- These A/B positives were prepared fresh: no seed capture/dedup. Exactly one official capture is reachable.
 IF link IS NULL OR t#>>'{private.workout_strength_authority_epochs,0,current_lifecycle_key}'IS DISTINCT FROM link OR t#>'{private.workout_strength_authority_epochs,0}'IS DISTINCT FROM(s#>'{private.workout_strength_authority_epochs,0}')||jsonb_build_object('current_lifecycle_key',link)
 OR jsonb_array_length(t->'private.workout_strength_lifecycles')<>1 OR jsonb_array_length(t->'private.workout_strength_commands')<>1 OR jsonb_array_length(t->'private.workout_strength_operations')<>1 OR jsonb_array_length(t->'public.workout_logs')<>1 OR jsonb_array_length(t->'public.daily_snapshots')<>1 OR jsonb_array_length(t->'private.workout_strength_facts')<>1 THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_FRESH_CAPTURE_COUNTS';END IF;
 ev:=c59s17d_fixture.capture_evidence(u,(payload->>'registrationID')::uuid);
 IF ev#>>'{resolved,status}'IS DISTINCT FROM 'reuse_existing'OR ev#>'{command,legacy_arguments}'IS DISTINCT FROM args OR ev#>>'{operation,resolution}'IS DISTINCT FROM 'sql_insert'OR ev#>>'{operation,capture_outcome}'IS DISTINCT FROM 'fact'OR ev#>>'{operation,original_workout_log_id}'IS DISTINCT FROM ev#>>'{workout,id}'OR ev#>>'{fact,snapshot_id}'IS DISTINCT FROM ev#>>'{snapshot,id}'OR ev#>>'{workout,snapshot_id}'IS DISTINCT FROM ev#>>'{snapshot,id}'OR ev#>'{workout,estimated_kcal}'IS DISTINCT FROM args->'p_estimated_kcal'OR ev#>'{snapshot,exercise_calories}'IS DISTINCT FROM args->'p_estimated_kcal'OR ev#>'{snapshot,training_done}'IS DISTINCT FROM 'true'::jsonb OR ev#>>'{lifecycle,closed_at}'IS NOT NULL THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_CAPTURE_ANCHORS';END IF;
 PERFORM c59s17d_fixture.assert_unchanged_except(s,t,ARRAY['public.pending_registrations','private.mobile_workout_proposal_admissions','private.mobile_workout_registration_edit_receipts','private.workout_strength_authority_epochs','private.workout_strength_lifecycles','private.workout_strength_commands','private.workout_strength_operations','public.workout_logs','public.daily_snapshots','private.workout_strength_facts'],'teardown_confirmed');
 ELSIF cid='reset-confirm-commit'AND p IS NULL THEN
 IF t->'user'IS DISTINCT FROM(s->'user')||jsonb_build_object('name',NULL,'flow_phrase_cursor_revision',0,'summary',NULL,'summary_updated_at',NULL,'tags','[]'::jsonb,'admin_notes',NULL,'country_confirmed',false,'last_active_at',NULL,'metadata','{}'::jsonb,'updated_at',t#>'{user,updated_at}')
 OR t#>'{public.user_profiles,0}'IS DISTINCT FROM(s#>'{public.user_profiles,0}')||jsonb_build_object('weight_kg',NULL,'weight_measured_at',NULL,'weight_instant_source',NULL,'onboarding_completed',false,'onboarding_step',0,'updated_at',t#>'{public.user_profiles,0,updated_at}')
 OR t#>'{public.user_progress,0}'IS DISTINCT FROM jsonb_build_object('user_id',u,'xp_total',0,'level',1,'current_streak',0,'longest_streak',0,'blocks_completed',0,'deficit_block',0,'current_weight',NULL,'current_bf_percent',NULL,'badges_earned','[]'::jsonb,'last_active_date',NULL,'next_reevaluation',NULL,'updated_at',t#>'{public.user_progress,0,updated_at}')
 OR t#>>'{private.workout_strength_authority_epochs,0,epoch}'IS NOT DISTINCT FROM s#>>'{private.workout_strength_authority_epochs,0,epoch}'OR t#>'{private.workout_strength_authority_epochs,0}'IS DISTINCT FROM(s#>'{private.workout_strength_authority_epochs,0}')||jsonb_build_object('epoch',t#>'{private.workout_strength_authority_epochs,0,epoch}','changed_at',t#>'{private.workout_strength_authority_epochs,0,changed_at}','current_lifecycle_key',NULL)THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_RESET_DELTA';END IF;
 PERFORM c59s17d_fixture.assert_unchanged_except(s,t,ARRAY['user','public.user_profiles','public.user_progress','private.workout_strength_authority_epochs','public.pending_registrations'],'teardown_reset');
 ELSE
 IF link IS NOT NULL THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_UNCONFIRMED_LINK';END IF;
 PERFORM c59s17d_fixture.assert_unchanged_except(s,t,ARRAY['public.pending_registrations','private.mobile_workout_proposal_admissions','private.mobile_workout_registration_edit_receipts'],'teardown_unconfirmed');
 END IF;
END $f$;
CREATE FUNCTION c59s17d_fixture.corrupt_binding_after_insert()RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF NEW.user_id=c59s17d_fixture.uid(2910)AND NEW.operation_kind='capture'THEN
 UPDATE private.workout_strength_operations SET legacy_result=legacy_result||'{"replaced_count":99}'::jsonb WHERE user_id=NEW.user_id AND lifecycle_key=NEW.lifecycle_key AND operation_kind=NEW.operation_kind AND operation_key=NEW.operation_key;
 END IF;RETURN NEW;END $f$;
DO $acl$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17d_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.oid::regprocedure);END LOOP;END $acl$;
REVOKE ALL ON ALL TABLES IN SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE NONE;

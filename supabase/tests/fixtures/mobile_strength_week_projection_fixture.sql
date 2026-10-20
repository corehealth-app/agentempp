-- Local QA only. S17D helpers below are copied literally from the reviewed
-- lifecycle fixture; no synthetic catalogue match or producer proof is seeded.
RESET ROLE;

SET LOCAL search_path=pg_catalog;
CREATE SCHEMA c59s17d_fixture AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
CREATE FUNCTION c59s17d_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT ('c59d7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $f$;

CREATE FUNCTION c59s17d_fixture.key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wui1:'||c59s17d_fixture.uid(i)::text $f$;

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

CREATE FUNCTION c59s17d_fixture.confirm_sql(u uuid,pid uuid,expected integer,a jsonb,o jsonb,d jsonb)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.confirm_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer,%L::jsonb,%L::jsonb,%L::jsonb)',u,pid,expected,a,o,d) $f$;

CREATE FUNCTION c59s17d_fixture.legacy_arguments(u uuid,p jsonb,day text DEFAULT NULL,kcal integer DEFAULT 525)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('p_user_id',u,'p_date',coalesce(day,p->>'source_local_date'),'p_workout_type',p->'workoutType','p_duration_min',p->'durationMin','p_estimated_kcal',kcal,'p_intensity',p->'intensity','p_notes','S17D café 🏋️','p_performed_at',p->'source_timestamp','p_provider_message_id',p->'source_provider_message_id','p_calories_target',2200,'p_protein_target',150.125,'p_replace_recent',false,'p_replace_since',NULL) $f$;

CREATE FUNCTION c59s17d_fixture.catalogue_decision(o jsonb,raw text)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT CASE WHEN raw='c59s17d-treino'THEN jsonb_build_object('status','matched','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'method','active_slug','selectedRowID',c59s17d_fixture.uid(9901))
 ELSE jsonb_build_object('status','unrecognized','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'reason','no_active_match')END $f$;

CREATE FUNCTION c59s17d_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;

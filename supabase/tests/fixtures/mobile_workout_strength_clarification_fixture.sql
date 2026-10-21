-- Local, rollback-only QA support. Reuses ten literal, real S17D producer helpers.
-- The controller must prove both fixture schemas/UUIDs absent before executing.
\ir mobile_strength_week_projection_fixture.sql
RESET ROLE;
CREATE SCHEMA c59p10b_fixture AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA c59p10b_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
CREATE TABLE c59p10b_fixture.context(label text PRIMARY KEY, value jsonb NOT NULL);
CREATE FUNCTION c59p10b_fixture.catalogue() RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM ONLY public.workout_types t
$f$;

CREATE FUNCTION c59p10b_fixture.ok(v boolean, label text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN
 IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'P10B_ASSERT:%',label;END IF;
 RAISE NOTICE 'P10B_PASS:%',label;
END $f$;

CREATE FUNCTION c59p10b_fixture.produce(u uuid, key_id integer, raw text, invalid_catalogue boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE p jsonb; o jsonb; d jsonb; r jsonb;
BEGIN
 p:=c59s17d_fixture.member(u,c59s17d_fixture.key(key_id),c59s17d_fixture.input(40,raw));
 SET LOCAL ROLE postgres;
 SET LOCAL ROLE service_role;
 o:=public.get_workout_strength_catalogue_context();
 SET LOCAL ROLE postgres;
 IF invalid_catalogue THEN
  IF o IS DISTINCT FROM '{"status":"unavailable","reason":"catalogue_invalid"}'::jsonb
   THEN RAISE EXCEPTION 'P10B_SETUP_REAL_UNAVAILABLE_CATALOGUE:%',o;END IF;
  d:=o; o:=NULL;
 ELSE
  IF o->>'status' IS DISTINCT FROM 'available' THEN RAISE EXCEPTION 'P10B_SETUP_REAL_CATALOGUE:%',o;END IF;
  d:=c59s17d_fixture.catalogue_decision(o,raw);
 END IF;
 r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(p->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,p->'proposal'),o,d));
 SET LOCAL ROLE postgres;
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR r#>>'{result,capture,strength,status}' IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'P10B_SETUP_REAL_CONFIRM:%',r;END IF;
 RETURN p||jsonb_build_object('confirmation',r->'result');
END $f$;

CREATE FUNCTION c59p10b_fixture.get_sql(u uuid,w uuid) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.get_mobile_workout_strength_clarification(%L::uuid,%L::uuid)',u,w)
$f$;
CREATE FUNCTION c59p10b_fixture.answer_sql(u uuid,l uuid,w uuid,r integer,q uuid,a text,k text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.answer_mobile_workout_strength_clarification(%L::uuid,%L::uuid,%L::uuid,%L::integer,%L::uuid,%L,%L)',u,l,w,r,q,a,k)
$f$;
CREATE FUNCTION c59p10b_fixture.expect(sql text,u uuid,control uuid,expected jsonb,label text) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE before_owner jsonb;before_control jsonb;before_catalogue jsonb;r jsonb;
BEGIN
 before_owner:=c59s17d_fixture.state(u);before_control:=c59s17d_fixture.state(control);
 before_catalogue:=c59p10b_fixture.catalogue();
 r:=c59s17d_fixture.attempt(sql);
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r=jsonb_build_object('ok',true,'result',expected)
  AND c59s17d_fixture.state(u)=before_owner AND c59s17d_fixture.state(control)=before_control
  AND c59p10b_fixture.catalogue()=before_catalogue,label);
END $f$;
CREATE FUNCTION c59p10b_fixture.expect_error(sql text,u uuid,control uuid,code text,message text,label text) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE before_owner jsonb;before_control jsonb;r jsonb;
BEGIN
 before_owner:=c59s17d_fixture.state(u);before_control:=c59s17d_fixture.state(control);
 r:=c59s17d_fixture.attempt(sql);
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r=jsonb_build_object('ok',false,'sqlstate',code,'message',message)
  AND c59s17d_fixture.state(u)=before_owner AND c59s17d_fixture.state(control)=before_control,label);
END $f$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59p10b_fixture FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;

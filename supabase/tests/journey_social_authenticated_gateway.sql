BEGIN;
DO $$ BEGIN
 ASSERT to_regprocedure('public.journey_social_patient_authenticated(uuid,uuid,uuid,text,jsonb)') IS NOT NULL,
 'Authenticated social gateway is not implemented';
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('19400000-0000-4000-8000-000000000001','social-auth-a@example.invalid',clock_timestamp()),
 ('19400000-0000-4000-8000-000000000002','social-auth-b@example.invalid',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES
 ('19400000-0000-4000-9000-000000000001','19400000-0000-4000-8000-000000000001','Synthetic social Auth A'),
 ('19400000-0000-4000-9000-000000000002','19400000-0000-4000-8000-000000000002','Synthetic social Auth B');
INSERT INTO auth.sessions(id,user_id,created_at,not_after) VALUES
 ('19400000-0000-4000-a000-000000000001','19400000-0000-4000-8000-000000000001',clock_timestamp(),NULL),
 ('19400000-0000-4000-a000-000000000002','19400000-0000-4000-8000-000000000002',clock_timestamp(),NULL),
 ('19400000-0000-4000-a000-000000000003','19400000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp()-interval '1 minute');
DO $test$
DECLARE a uuid='19400000-0000-4000-9000-000000000001';u uuid='19400000-0000-4000-8000-000000000001';s uuid='19400000-0000-4000-a000-000000000001';bad uuid;r jsonb;before_sessions jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_sessions FROM auth.sessions x WHERE user_id IN(u,'19400000-0000-4000-8000-000000000002');
 r:=public.journey_social_patient_authenticated(a,u,s,'profile.read','{}');
 ASSERT r->>'revision'='0' AND r->>'opted_in'='false';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_profiles WHERE user_id=a),'read cannot initialize participation';
 FOREACH bad IN ARRAY ARRAY['19400000-0000-4000-a000-000000000002'::uuid,'19400000-0000-4000-a000-000000000003'::uuid,'19400000-0000-4000-a000-000000000099'::uuid] LOOP
  BEGIN
   PERFORM public.journey_social_patient_authenticated(a,u,bad,'profile.read','{}');
   RAISE EXCEPTION 'foreign, expired or missing login accepted';
  EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,'19400000-0000-4000-8000-000000000002',s,'profile.read','{}');
  RAISE EXCEPTION 'foreign Auth mapping accepted';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'moderate.profile','{}');
  RAISE EXCEPTION 'patient gateway reached moderation';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'profile.read','{"owner_id":"unexpected"}');
  RAISE EXCEPTION 'client authority override accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 ASSERT (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM auth.sessions x WHERE user_id IN(u,'19400000-0000-4000-8000-000000000002'))=before_sessions,'reads cannot renew or modify Auth sessions';
 r:=public.journey_social_patient_authenticated(a,u,s,'profile.update','{"operation_id":"19400000-0000-4000-b000-000000000001","expected_revision":0,"opted_in":true,"nickname":"Pessoa A","consent_version":"journey-social.v1"}');
 ASSERT r->>'status'='applied' AND r#>>'{profile,revision}'='1';
 r:=public.journey_social_patient_authenticated(a,u,s,'profile.update','{"operation_id":"19400000-0000-4000-b000-000000000001","expected_revision":0,"opted_in":true,"nickname":"Pessoa A","consent_version":"journey-social.v1"}');
 ASSERT r->>'status'='replayed';
 r:=public.journey_social_patient_authenticated(a,u,s,'ranking.read','{"limit":20,"cursor":null}');
 ASSERT jsonb_array_length(r->'entries')=1 AND r#>>'{entries,0,is_you}'='true';
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'profile.update','{"operation_id":"19400000-0000-4000-b000-000000000002","expected_revision":1,"opted_in":true,"nickname":23,"consent_version":"journey-social.v1"}');
  RAISE EXCEPTION 'number coerced into nickname';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'ranking.read','{"limit":"20","cursor":null}');
  RAISE EXCEPTION 'string coerced into page size';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 RAISE NOTICE 'PASS original live session, no session renewal/bootstrap, closed operations, strict types and replay';
END $test$;
-- A temporary nontransactional witness proves the writer was reached before
-- natural session expiry; only domain changes must roll back. No product hook.
CREATE TEMP SEQUENCE gateway_writer_reached;
CREATE FUNCTION pg_temp.delay_social_writer() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 PERFORM nextval('pg_temp.gateway_writer_reached');PERFORM pg_sleep(.35);RETURN NEW;END$$;
CREATE TRIGGER gateway_test_delay BEFORE UPDATE ON private.journey_social_profiles FOR EACH ROW EXECUTE FUNCTION pg_temp.delay_social_writer();
DO $test$
DECLARE a uuid='19400000-0000-4000-9000-000000000001';u uuid='19400000-0000-4000-8000-000000000001';s uuid='19400000-0000-4000-a000-000000000001';
BEGIN
 UPDATE auth.sessions SET not_after=clock_timestamp()+interval '.25 seconds' WHERE id=s;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'profile.update','{"operation_id":"19400000-0000-4000-b000-000000000002","expected_revision":1,"opted_in":false,"nickname":null,"consent_version":null}');
  RAISE EXCEPTION 'session expired inside writer but command committed';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 ASSERT (SELECT is_called FROM pg_temp.gateway_writer_reached),'test must reach actual writer, not fail before it';
 ASSERT (SELECT revision FROM private.journey_social_profiles WHERE user_id=a)=1;
 ASSERT (SELECT opted_in FROM private.journey_social_profiles WHERE user_id=a);
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_operations WHERE user_id=a AND operation_id='19400000-0000-4000-b000-000000000002');
 DELETE FROM auth.sessions WHERE id=s;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'profile.update','{"operation_id":"19400000-0000-4000-b000-000000000001","expected_revision":0,"opted_in":true,"nickname":"Pessoa A","consent_version":"journey-social.v1"}');
  RAISE EXCEPTION 'logout allowed old operation replay';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 ASSERT NOT has_function_privilege('anon','public.journey_social_patient_authenticated(uuid,uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.journey_social_patient_authenticated(uuid,uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.journey_social_patient_authenticated(uuid,uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('service_role','private.lock_journey_social_patient_session(uuid,uuid,uuid)','EXECUTE');
 RAISE NOTICE 'PASS expiry after actual writer rolls back profile/receipt; logout denies replay; least privilege';
END $test$;
ROLLBACK;

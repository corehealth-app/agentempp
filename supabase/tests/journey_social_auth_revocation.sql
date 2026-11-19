-- Current Auth state must remain authoritative even for an unexpired login.
-- Transactional synthetic fixtures only; no persisted user or reward writes.
BEGIN;
CREATE TEMP TABLE auth_revocation_failures(message text);
CREATE FUNCTION pg_temp.expect_social_denial(command text) RETURNS void
LANGUAGE plpgsql AS $$BEGIN
 BEGIN
  EXECUTE command;
  INSERT INTO auth_revocation_failures VALUES('revoked identity was accepted');
 EXCEPTION WHEN SQLSTATE 'PT401' OR insufficient_privilege THEN NULL;
 END;
END$$;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('20100000-0000-4000-8000-000000000001','revocation-a@example.invalid',clock_timestamp()),
 ('20100000-0000-4000-8000-000000000002','revocation-b@example.invalid',clock_timestamp()),
 ('20100000-0000-4000-8000-000000000003','revocation-operator@example.invalid',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES
 ('20100000-0000-4000-9000-000000000001','20100000-0000-4000-8000-000000000001','Synthetic revocation A'),
 ('20100000-0000-4000-9000-000000000002','20100000-0000-4000-8000-000000000002','Synthetic revocation B');
INSERT INTO public.admin_users(id,email,role) VALUES
 ('20100000-0000-4000-8000-000000000003','revocation-operator@example.invalid','operations_admin');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES
 ('20100000-0000-4000-a000-000000000001','20100000-0000-4000-8000-000000000001',clock_timestamp()),
 ('20100000-0000-4000-a000-000000000003','20100000-0000-4000-8000-000000000003',clock_timestamp());
SELECT public.mutate_journey_social_profile('20100000-0000-4000-9000-000000000001','20100000-0000-4000-8000-000000000001','20100000-0000-4000-b000-000000000001',0,true,'Pessoa A','journey-social.v1') IS NOT NULL;
SELECT public.mutate_journey_social_profile('20100000-0000-4000-9000-000000000002','20100000-0000-4000-8000-000000000002','20100000-0000-4000-b000-000000000002',0,true,'Pessoa B','journey-social.v1') IS NOT NULL;
DO $$DECLARE
 a uuid='20100000-0000-4000-9000-000000000001';
 u uuid='20100000-0000-4000-8000-000000000001';
 s uuid='20100000-0000-4000-a000-000000000001';
 operator_id uuid='20100000-0000-4000-8000-000000000003';
 r jsonb; failures text;
BEGIN
 UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 hour' WHERE id=u;
 PERFORM pg_temp.expect_social_denial(format('SELECT public.journey_social_patient_authenticated(%L,%L,%L,%L,%L)',a,u,s,'profile.read','{}'));
 PERFORM pg_temp.expect_social_denial(format('SELECT public.journey_social_patient_authenticated(%L,%L,%L,%L,%L)',a,u,s,'profile.update','{"operation_id":"20100000-0000-4000-b000-000000000003","expected_revision":1,"opted_in":false,"nickname":null,"consent_version":null}'));
 PERFORM pg_temp.expect_social_denial(format('SELECT public.resolve_journey_social_operation_authenticated(%L,%L,%L,%L,%L)',a,u,s,'profile','{"operation_id":"20100000-0000-4000-b000-000000000004","expected_revision":1,"opted_in":false,"nickname":null,"consent_version":null}'));
 IF EXISTS(SELECT 1 FROM private.journey_social_operations WHERE user_id=a AND operation_id='20100000-0000-4000-b000-000000000003') THEN INSERT INTO auth_revocation_failures VALUES('banned writer persisted an operation');END IF;
 IF EXISTS(SELECT 1 FROM private.journey_social_operation_fences WHERE user_id=a AND operation_id='20100000-0000-4000-b000-000000000004') THEN INSERT INTO auth_revocation_failures VALUES('banned recovery persisted a fence');END IF;
 -- Restore only this synthetic state so later cases remain independent.
 UPDATE private.journey_social_profiles SET opted_in=true,nickname='Pessoa A',consent_version='journey-social.v1',consented_at=clock_timestamp() WHERE user_id=a;
 UPDATE auth.users SET banned_until=clock_timestamp()-interval '1 second' WHERE id=u;
 r:=public.journey_social_patient_authenticated(a,u,s,'profile.read','{}');
 ASSERT r->>'opted_in'='true','an expired ban must not permanently disable a valid account';
 UPDATE auth.users SET deleted_at=clock_timestamp() WHERE id=u;
 PERFORM pg_temp.expect_social_denial(format('SELECT public.journey_social_patient_authenticated(%L,%L,%L,%L,%L)',a,u,s,'profile.read','{}'));
 UPDATE auth.users SET deleted_at=NULL WHERE id=u;
 UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 hour' WHERE id='20100000-0000-4000-8000-000000000002';
 r:=public.journey_social_patient_authenticated(a,u,s,'ranking.read','{"limit":20,"cursor":null}');
 IF jsonb_array_length(r->'entries')<>1 THEN INSERT INTO auth_revocation_failures VALUES('banned peer remains in ranking');END IF;
 UPDATE auth.users SET banned_until=NULL,deleted_at=clock_timestamp() WHERE id='20100000-0000-4000-8000-000000000002';
 r:=public.journey_social_patient_authenticated(a,u,s,'ranking.read','{"limit":20,"cursor":null}');
 IF jsonb_array_length(r->'entries')<>1 THEN INSERT INTO auth_revocation_failures VALUES('deleted Auth peer remains in ranking');END IF;
 UPDATE auth.users SET deleted_at=NULL,email_confirmed_at=NULL WHERE id='20100000-0000-4000-8000-000000000002';
 r:=public.journey_social_patient_authenticated(a,u,s,'ranking.read','{"limit":20,"cursor":null}');
 IF jsonb_array_length(r->'entries')<>1 THEN INSERT INTO auth_revocation_failures VALUES('unconfirmed peer remains in ranking');END IF;
 UPDATE auth.users SET deleted_at=clock_timestamp() WHERE id=operator_id;
 PERFORM pg_temp.expect_social_denial(format('SELECT public.journey_social_operator_authenticated(%L,%L,%L,%L)',operator_id,'20100000-0000-4000-a000-000000000003','queue.read','{"limit":20,"cursor":null}'));
 ASSERT NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id IN(a,'20100000-0000-4000-9000-000000000002'));
 SELECT string_agg(message,'; ') INTO failures FROM auth_revocation_failures;
 ASSERT failures IS NULL,failures;
 RAISE NOTICE 'PASS current ban/deletion/confirmation exclusions, original session guards, no revoked effects or rewards';
END$$;
ROLLBACK;

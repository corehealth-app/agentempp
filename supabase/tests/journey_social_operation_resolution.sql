-- Rollback-only fixtures. Run in a verified owned local copy, never hosted QA.
BEGIN;
DO $$ BEGIN
 ASSERT to_regprocedure('public.resolve_journey_social_operation_authenticated(uuid,uuid,uuid,text,jsonb)') IS NOT NULL,
 'Authenticated receipt-or-fence resolution is not implemented';
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('19600000-0000-4000-8000-000000000001','resolution-a@example.invalid',clock_timestamp()),
 ('19600000-0000-4000-8000-000000000002','resolution-b@example.invalid',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES
 ('19600000-0000-4000-9000-000000000001','19600000-0000-4000-8000-000000000001','Synthetic resolution A'),
 ('19600000-0000-4000-9000-000000000002','19600000-0000-4000-8000-000000000002','Synthetic resolution B');
INSERT INTO auth.sessions(id,user_id,created_at,not_after) VALUES
 ('19600000-0000-4000-a000-000000000001','19600000-0000-4000-8000-000000000001',clock_timestamp(),NULL),
 ('19600000-0000-4000-a000-000000000002','19600000-0000-4000-8000-000000000002',clock_timestamp(),NULL),
 ('19600000-0000-4000-a000-000000000003','19600000-0000-4000-8000-000000000001',clock_timestamp(),NULL);
DO $test$
DECLARE a uuid='19600000-0000-4000-9000-000000000001';u uuid='19600000-0000-4000-8000-000000000001';
 s uuid='19600000-0000-4000-a000-000000000001';s2 uuid='19600000-0000-4000-a000-000000000003';
 c jsonb='{"operation_id":"19600000-0000-4000-c000-000000000001","expected_revision":0,"opted_in":true,"nickname":"Pessoa A","consent_version":"journey-social.v1"}';
 r jsonb; saved jsonb; before_profile jsonb; peer uuid; peer_command jsonb; q jsonb; action text;op uuid;before_sessions jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_sessions FROM auth.sessions x WHERE user_id IN(u,'19600000-0000-4000-8000-000000000002');
 -- No original send: resolve produces a durable no-effect fence, no profile.
 r:=public.resolve_journey_social_operation_authenticated(a,u,s,'profile',c);
 ASSERT r->>'status'='fenced' AND r->'receipt'='null' AND r#>>'{profile,revision}'='0';
 ASSERT r->>'operation_id'=c->>'operation_id' AND r->>'kind'='profile' AND r->>'expected_revision'='0';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_profiles WHERE user_id=a);
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_operations WHERE user_id=a);
 ASSERT (SELECT count(*) FROM private.journey_social_operation_fences WHERE user_id=a)=1;
 ASSERT public.resolve_journey_social_operation_authenticated(a,u,s2,'profile',c)=r;
 BEGIN
  PERFORM public.journey_social_patient_authenticated(a,u,s,'profile.update',c);
  RAISE EXCEPTION 'late original consent crossed a durable fence';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL;END;
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_profiles WHERE user_id=a),'failed late transaction must roll back profile';
 BEGIN
  PERFORM public.resolve_journey_social_operation_authenticated(a,u,s2,'profile',c||'{"nickname":"Changed"}');
  RAISE EXCEPTION 'same operation content changed';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL;END;
 -- A genuine new command succeeds and can be observed from a new login.
 c:=c||'{"operation_id":"19600000-0000-4000-c000-000000000002"}';
 saved:=public.journey_social_patient_authenticated(a,u,s,'profile.update',c);
 PERFORM public.journey_social_patient_authenticated(a,u,s,'profile.update','{"operation_id":"19600000-0000-4000-c000-000000000003","expected_revision":1,"opted_in":false,"nickname":null,"consent_version":null}');
 before_profile:=public.read_journey_social_profile(a,u);
 DELETE FROM auth.sessions WHERE id=s;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO before_sessions FROM auth.sessions x WHERE user_id IN(u,'19600000-0000-4000-8000-000000000002');
 r:=public.resolve_journey_social_operation_authenticated(a,u,s2,'profile',c);
 ASSERT r->>'status'='applied' AND r->'receipt'=saved->'receipt' AND r->'profile'=before_profile;
 ASSERT r#>>'{profile,opted_in}'='false' AND r#>>'{profile,revision}'='2','historical consent cannot be restored';
 BEGIN
  PERFORM public.resolve_journey_social_operation_authenticated(a,u,s,'profile',c);
  RAISE EXCEPTION 'dead login could resolve';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
 BEGIN
  PERFORM public.resolve_journey_social_operation_authenticated(a,'19600000-0000-4000-8000-000000000002',s2,'profile',c);
  RAISE EXCEPTION 'foreign mapping could resolve';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
 ASSERT public.read_journey_social_profile(a,u)=before_profile;
 r:=public.resolve_journey_social_operation_authenticated('19600000-0000-4000-9000-000000000002','19600000-0000-4000-8000-000000000002','19600000-0000-4000-a000-000000000002','profile',c);
 ASSERT r->>'status'='fenced' AND r->'receipt'='null' AND r#>>'{profile,revision}'='0','another account cannot read the original receipt';
 PERFORM public.journey_social_patient_authenticated(a,u,s2,'profile.update','{"operation_id":"19600000-0000-4000-c000-000000000020","expected_revision":2,"opted_in":true,"nickname":"Pessoa A","consent_version":"journey-social.v1"}');
 before_profile:=public.read_journey_social_profile(a,u);
 -- Peer actions are fenced atomically, including their profile revision.
 q:=public.journey_social_patient_authenticated('19600000-0000-4000-9000-000000000002','19600000-0000-4000-8000-000000000002','19600000-0000-4000-a000-000000000002','profile.update',c||'{"operation_id":"19600000-0000-4000-c000-000000000010","nickname":"Pessoa B"}');
 peer:=(q#>>'{profile,member_id}')::uuid;
 FOREACH action IN ARRAY ARRAY['block','report'] LOOP
  op:=CASE WHEN action='block' THEN '19600000-0000-4000-c000-000000000004'::uuid ELSE '19600000-0000-4000-c000-000000000005'::uuid END;
  peer_command:=jsonb_build_object('operation_id',op,'expected_revision',3,'member_id',peer)||
    CASE WHEN action='block' THEN '{"blocked":true}'::jsonb ELSE '{"reason":"spam"}'::jsonb END;
  r:=public.resolve_journey_social_operation_authenticated(a,u,s2,action,peer_command);
  ASSERT r->>'status'='fenced' AND r->'profile'=before_profile;
  BEGIN
   IF action='block' THEN PERFORM public.mutate_journey_social_block(a,u,op,3,peer,true);
   ELSE PERFORM public.submit_journey_social_report(a,u,op,3,peer,'spam');END IF;
   RAISE EXCEPTION 'late peer operation crossed fence';
  EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL;END;
 END LOOP;
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_blocks WHERE blocker_id=a);
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_reports WHERE reporter_id=a);
 ASSERT public.read_journey_social_profile(a,u)=before_profile;
 -- Exact hashes also recover completed peer commands without repeating them.
 FOREACH action IN ARRAY ARRAY['block','report'] LOOP
  before_profile:=public.read_journey_social_profile(a,u);
  op:=CASE WHEN action='block' THEN '19600000-0000-4000-c000-000000000006'::uuid ELSE '19600000-0000-4000-c000-000000000007'::uuid END;
  peer_command:=jsonb_build_object('operation_id',op,'expected_revision',(before_profile->>'revision')::bigint,'member_id',peer)||
    CASE WHEN action='block' THEN '{"blocked":true}'::jsonb ELSE '{"reason":"spam"}'::jsonb END;
  saved:=public.journey_social_patient_authenticated(a,u,s2,CASE WHEN action='block' THEN 'block.update' ELSE 'report.create' END,peer_command);
  r:=public.resolve_journey_social_operation_authenticated(a,u,s2,action,peer_command);
  ASSERT r->>'status'='applied' AND r->'receipt'=saved->'receipt' AND r->'profile'=saved->'profile';
  ASSERT public.resolve_journey_social_operation_authenticated(a,u,s2,action,peer_command)=r;
 END LOOP;
 ASSERT (SELECT count(*) FROM private.journey_social_reports WHERE reporter_id=a)=1;
 ASSERT (SELECT count(*) FROM private.journey_social_blocks WHERE blocker_id=a)=1;
 ASSERT (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM auth.sessions x WHERE user_id IN(u,'19600000-0000-4000-8000-000000000002'))=before_sessions,'recovery cannot renew or mutate current sessions';
 -- Invalid payload cannot allocate another fence or write consent.
 FOREACH q IN ARRAY ARRAY[c||'{"owner_id":"override"}',c||'{"expected_revision":1.5}',c||'{"opted_in":"true"}',c||'{"nickname":null}',c||'{"consent_version":null}'] LOOP
  BEGIN
   PERFORM public.resolve_journey_social_operation_authenticated(a,u,s2,'profile',q);
   RAISE EXCEPTION 'invalid resolution accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 END LOOP;
 BEGIN
  PERFORM public.resolve_journey_social_operation_authenticated(a,u,s2,'moderate',c);
  RAISE EXCEPTION 'patient resolution reached moderation';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 ASSERT NOT has_function_privilege('anon','public.resolve_journey_social_operation_authenticated(uuid,uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.resolve_journey_social_operation_authenticated(uuid,uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.resolve_journey_social_operation_authenticated(uuid,uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT NOT has_table_privilege('service_role','private.journey_social_operation_fences','SELECT,INSERT,UPDATE,DELETE');
 RAISE NOTICE 'PASS absent send fenced, late profile/block/report rolled back, exact3kind receipts, new-login withdrawal, mapping/input/privileges';
END $test$;
CREATE FUNCTION pg_temp.expire_resolution_login() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id='19600000-0000-4000-a000-000000000003';RETURN NEW;END $$;
CREATE TRIGGER resolution_expiry_test AFTER INSERT ON private.journey_social_operation_fences FOR EACH ROW EXECUTE FUNCTION pg_temp.expire_resolution_login();
DO $$BEGIN
 BEGIN
  PERFORM public.resolve_journey_social_operation_authenticated('19600000-0000-4000-9000-000000000001','19600000-0000-4000-8000-000000000001','19600000-0000-4000-a000-000000000003','profile','{"operation_id":"19600000-0000-4000-c000-000000000030","expected_revision":3,"opted_in":false,"nickname":null,"consent_version":null}');
  RAISE EXCEPTION 'expiry during recovery returned a fence';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_operation_fences WHERE operation_id='19600000-0000-4000-c000-000000000030');
 ASSERT (SELECT not_after FROM auth.sessions WHERE id='19600000-0000-4000-a000-000000000003') IS NULL;
 RAISE NOTICE 'PASS login expiry during recovery rolls back its fence';
END $$;
DROP TRIGGER resolution_expiry_test ON private.journey_social_operation_fences;
DELETE FROM public.users WHERE id='19600000-0000-4000-9000-000000000001';
DO $$BEGIN ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_operation_fences WHERE user_id='19600000-0000-4000-9000-000000000001');RAISE NOTICE 'PASS private fences follow account cascade';END $$;
ROLLBACK;

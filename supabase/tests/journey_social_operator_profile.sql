BEGIN;
DO $$ BEGIN
 ASSERT to_regprocedure('public.journey_social_operator_profile_authenticated(uuid,uuid,uuid)') IS NOT NULL,
 'Operators need a live-session public profile lookup after resolving a report';
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('20000000-0000-4000-8000-000000000001','moderation-target@example.invalid',clock_timestamp()),
 ('20000000-0000-4000-8000-000000000002','moderation-operator@example.invalid',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES('20000000-0000-4000-9000-000000000001','20000000-0000-4000-8000-000000000001','Synthetic lookup');
INSERT INTO public.admin_users(id,email,role) VALUES('20000000-0000-4000-8000-000000000002','moderation-operator@example.invalid','operations_admin');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('20000000-0000-4000-a000-000000000002','20000000-0000-4000-8000-000000000002',clock_timestamp());
SELECT public.mutate_journey_social_profile('20000000-0000-4000-9000-000000000001','20000000-0000-4000-8000-000000000001','20000000-0000-4000-b000-000000000001',0,true,'Pessoa consulta','journey-social.v1') IS NOT NULL;
DO $$ DECLARE a uuid='20000000-0000-4000-8000-000000000002';s uuid='20000000-0000-4000-a000-000000000002';member uuid;r jsonb;BEGIN
 SELECT member_id INTO member FROM private.journey_social_profiles WHERE user_id='20000000-0000-4000-9000-000000000001';
 r:=public.journey_social_operator_profile_authenticated(a,s,member);
 ASSERT r->>'member_id'=member::text AND r->>'nickname'='Pessoa consulta';
 ASSERT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k)=ARRAY['member_id','moderation','nickname','opted_in','revision'];
 PERFORM public.mutate_journey_social_profile('20000000-0000-4000-9000-000000000001','20000000-0000-4000-8000-000000000001','20000000-0000-4000-b000-000000000002',1,false,NULL,NULL);
 r:=public.journey_social_operator_profile_authenticated(a,s,member);
 ASSERT r->>'opted_in'='false' AND r->'nickname'='null'::jsonb AND r->>'revision'='2';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_moderation_operations WHERE actor_id=a),'lookup cannot moderate';
 UPDATE public.admin_users SET role='support' WHERE id=a;
 BEGIN PERFORM public.journey_social_operator_profile_authenticated(a,s,member);RAISE EXCEPTION 'support profile lookup accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE public.admin_users SET role='operations_admin' WHERE id=a;
 DELETE FROM auth.sessions WHERE id=s;
 BEGIN PERFORM public.journey_social_operator_profile_authenticated(a,s,member);RAISE EXCEPTION 'logout profile lookup accepted';EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
 ASSERT NOT has_function_privilege('anon','public.journey_social_operator_profile_authenticated(uuid,uuid,uuid)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.journey_social_operator_profile_authenticated(uuid,uuid,uuid)','EXECUTE');
 RAISE NOTICE 'PASS operational profile lookup is current, privacy-limited, read-only and original-session-bound';
END $$;
ROLLBACK;

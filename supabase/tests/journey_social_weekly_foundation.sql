-- Real PostgreSQL assertions. All identities and snapshots below are synthetic.
BEGIN;
DO $$ BEGIN
 ASSERT to_regprocedure('public.read_journey_social_profile(uuid,uuid)') IS NOT NULL,
  'Journey participation reader is not implemented';
END $$;
-- Eligible ranking fixtures are confirmed accounts, as required by mobile Auth.
INSERT INTO auth.users(id,email,email_confirmed_at)
 SELECT ('19000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'journey-r190-'||i||'@example.invalid',clock_timestamp() FROM generate_series(1,7) i;
INSERT INTO public.users(id,auth_user_id,name,timezone)
 SELECT ('19000000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,
 ('19000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'Synthetic Journey '||i,'America/Sao_Paulo' FROM generate_series(1,7) i;
DO $test$
DECLARE p jsonb; n bigint;
BEGIN
 SELECT count(*) INTO n FROM private.journey_social_profiles;
 p:=public.read_journey_social_profile('19000000-0000-4000-9000-000000000001','19000000-0000-4000-8000-000000000001');
 ASSERT p=jsonb_build_object('revision',0,'opted_in',false,'nickname',NULL,'member_id',NULL,'moderation','active');
 ASSERT (SELECT count(*) FROM private.journey_social_profiles)=n,'reading must not create participation';
 BEGIN
  PERFORM public.read_journey_social_profile('19000000-0000-4000-9000-000000000001','19000000-0000-4000-8000-000000000002');
  RAISE EXCEPTION 'wrong Auth accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.read_journey_weekly_ranking('19000000-0000-4000-9000-000000000001','19000000-0000-4000-8000-000000000001',50);
  RAISE EXCEPTION 'unconsented viewer read peers';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN
  PERFORM public.read_journey_social_profile('19000000-0000-4000-9000-000000000001','19000000-0000-4000-8000-000000000001');
  RAISE EXCEPTION 'authenticated claim accepted by backend-only RPC';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','',true);
 RAISE NOTICE 'PASS absent read is side-effect free; original Auth and consent required';
END $test$;
DO $test$
DECLARE a uuid='19000000-0000-4000-9000-000000000001'; u uuid='19000000-0000-4000-8000-000000000001'; r jsonb; replay jsonb;
BEGIN
 r:=public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000001',0,true,'Caminhante','journey-social.v1');
 ASSERT r->>'status'='applied' AND r#>>'{profile,revision}'='1';
 ASSERT r#>>'{profile,opted_in}'='true' AND r#>>'{profile,nickname}'='Caminhante';
 ASSERT (r#>>'{profile,member_id}')::uuid NOT IN (a,u),'peer identity must differ from Auth/domain';
 replay:=public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000001',0,true,'Caminhante','journey-social.v1');
 ASSERT replay->>'status'='replayed' AND replay->'receipt'=r->'receipt';
 BEGIN
  PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000001',0,true,'Outro apelido','journey-social.v1');
  RAISE EXCEPTION 'same operation accepted different content';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 BEGIN
  PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000002',0,false,NULL,NULL);
  RAISE EXCEPTION 'stale revision accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 BEGIN
  PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000002',1,true,'test@example.invalid','journey-social.v1');
  RAISE EXCEPTION 'email accepted as nickname';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000002',1,true,'Caminhante','other-consent');
  RAISE EXCEPTION 'unrecognized consent accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000002',1,false,NULL,NULL);
 replay:=public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000001',0,true,'Caminhante','journey-social.v1');
 ASSERT replay->'receipt'=r->'receipt' AND replay#>>'{profile,revision}'='2' AND replay#>>'{profile,opted_in}'='false','old receipt may not re-enroll';
 ASSERT replay#>'{profile,nickname}'='null'::jsonb,'withdrawal clears visible nickname';
 PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000003',2,true,'Caminhante','journey-social.v1');
 RAISE NOTICE 'PASS explicit consent, CAS, immutable replay, nickname validation and withdrawal';
END $test$;
SELECT public.mutate_journey_social_profile(
 ('19000000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,
 ('19000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 ('19000000-0000-4000-b000-'||lpad(i::text,12,'0'))::uuid,
 0,true,'Pessoa '||i,'journey-social.v1') IS NOT NULL FROM generate_series(2,7) i WHERE i<>4;
UPDATE public.users SET status='blocked' WHERE id='19000000-0000-4000-9000-000000000005';
UPDATE private.journey_social_profiles SET moderation='suspended' WHERE user_id='19000000-0000-4000-9000-000000000006';
INSERT INTO public.daily_snapshots(user_id,date,xp_earned,day_closed) VALUES
 ('19000000-0000-4000-9000-000000000001','2026-11-02',20,true),
 ('19000000-0000-4000-9000-000000000001','2026-11-03',10,true),
 ('19000000-0000-4000-9000-000000000001','2026-11-04',999,false),
 ('19000000-0000-4000-9000-000000000001','2026-11-01',999,true),
 ('19000000-0000-4000-9000-000000000001','2026-11-09',999,true),
 ('19000000-0000-4000-9000-000000000002','2026-11-02',30,true),
 ('19000000-0000-4000-9000-000000000003','2026-11-02',10,true),
 ('19000000-0000-4000-9000-000000000004','2026-11-02',300,true),
 ('19000000-0000-4000-9000-000000000005','2026-11-02',500,true),
 ('19000000-0000-4000-9000-000000000006','2026-11-02',200,true),
 ('19000000-0000-4000-9000-000000000007','2026-11-01',400,true);
DO $test$
DECLARE a uuid='19000000-0000-4000-9000-000000000001'; u uuid='19000000-0000-4000-8000-000000000001'; p jsonb; item jsonb; before_xp jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(s) ORDER BY user_id,date) INTO before_xp FROM public.daily_snapshots s WHERE user_id::text LIKE '19000000%';
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-04T16:00:00Z',50);
 ASSERT p->>'week_start'='2026-11-02' AND p->>'week_end'='2026-11-08';
 ASSERT p->>'through_date'='2026-11-04' AND p->>'basis'='closed_daily_xp';
 ASSERT jsonb_array_length(p->'entries')=4,'exclude unconsented, blocked and suspended profiles';
 ASSERT p#>>'{entries,0,weekly_xp}'='30' AND p#>>'{entries,1,weekly_xp}'='30','only closed XP in this week';
 ASSERT p#>>'{entries,0,rank}'='1' AND p#>>'{entries,1,rank}'='1' AND p#>>'{entries,2,rank}'='3' AND p#>>'{entries,3,rank}'='4','ties share rank';
 ASSERT p#>>'{entries,2,weekly_xp}'='10' AND p#>>'{entries,3,weekly_xp}'='0';
 ASSERT p->>'has_more'='false';
 ASSERT (SELECT count(*) FROM jsonb_array_elements(p->'entries') x WHERE x->>'is_you'='true')=1;
 FOR item IN SELECT value FROM jsonb_array_elements(p->'entries') LOOP
  ASSERT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(item) k)=ARRAY['is_you','member_id','nickname','rank','weekly_xp'];
  ASSERT item->>'member_id' NOT LIKE '19000000%','do not leak internal identity';
 END LOOP;
 ASSERT (SELECT jsonb_agg(to_jsonb(s) ORDER BY user_id,date) FROM public.daily_snapshots s WHERE user_id::text LIKE '19000000%')=before_xp,'ranking cannot mutate XP or daily facts';
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-04T16:00:00Z',1);
 ASSERT jsonb_array_length(p->'entries')=1 AND p->>'has_more'='true','bound response without claiming full coverage';
 BEGIN
  PERFORM public.read_journey_weekly_ranking(a,u,101);
  RAISE EXCEPTION 'unbounded leaderboard accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-02T02:59:59Z',50);
 ASSERT p->>'week_start'='2026-10-26' AND p->>'week_end'='2026-11-01','Sunday in official timezone';
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-02T03:00:00Z',50);
 ASSERT p->>'week_start'='2026-11-02','Monday boundary in official timezone';
 UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=a;
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-01T15:00:00Z',50);
 ASSERT p->>'week_start'='2026-11-02','server session timezone cannot replace user civil date';
 UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=a;
 UPDATE public.users SET timezone='Invalid/Timezone' WHERE id=a;
 BEGIN
  PERFORM private.project_journey_weekly_ranking(a,u,'2026-11-04T16:00:00Z',50);
  RAISE EXCEPTION 'invalid official timezone accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=a;
 RAISE NOTICE 'PASS official closed weekly XP, shared ranks, privacy whitelist, bounds and civil week';
END $test$;
DO $test$
DECLARE a uuid='19000000-0000-4000-9000-000000000001'; u uuid='19000000-0000-4000-8000-000000000001'; p jsonb;
BEGIN
 INSERT INTO private.journey_social_blocks(blocker_id,target_id) VALUES (a,'19000000-0000-4000-9000-000000000002');
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-04T16:00:00Z',50);
 ASSERT jsonb_array_length(p->'entries')=3;
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'entries') x WHERE x->>'nickname'='Pessoa 2');
 DELETE FROM private.journey_social_blocks WHERE blocker_id=a;
 INSERT INTO private.journey_social_blocks(blocker_id,target_id) VALUES ('19000000-0000-4000-9000-000000000002',a);
 p:=private.project_journey_weekly_ranking(a,u,'2026-11-04T16:00:00Z',50);
 ASSERT jsonb_array_length(p->'entries')=3,'reverse blocks must also hide peers';
 PERFORM public.mutate_journey_social_profile(a,u,'19000000-0000-4000-a000-000000000004',3,false,NULL,NULL);
 BEGIN
  PERFORM private.project_journey_weekly_ranking(a,u,'2026-11-04T16:00:00Z',50);
  RAISE EXCEPTION 'withdrawn profile still reads peers';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 p:=private.project_journey_weekly_ranking('19000000-0000-4000-9000-000000000003','19000000-0000-4000-8000-000000000003','2026-11-04T16:00:00Z',50);
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'entries') x WHERE x->>'nickname'='Caminhante'),'withdrawal invisible to next peer read';
 RAISE NOTICE 'PASS bidirectional block filtering and immediate withdrawal';
END $test$;
DO $test$
DECLARE fn text; t text;
BEGIN
 FOREACH fn IN ARRAY ARRAY['read_journey_social_profile(uuid,uuid)','mutate_journey_social_profile(uuid,uuid,uuid,bigint,boolean,text,text)','read_journey_weekly_ranking(uuid,uuid,integer)'] LOOP
  ASSERT NOT has_function_privilege('anon','public.'||fn,'EXECUTE');
  ASSERT NOT has_function_privilege('authenticated','public.'||fn,'EXECUTE');
  ASSERT has_function_privilege('service_role','public.'||fn,'EXECUTE');
 END LOOP;
 ASSERT NOT has_function_privilege('service_role','private.project_journey_weekly_ranking(uuid,uuid,timestamp with time zone,integer)','EXECUTE'),'no caller-selected clock via API';
 FOREACH t IN ARRAY ARRAY['journey_social_profiles','journey_social_operations','journey_social_blocks'] LOOP
  ASSERT NOT has_table_privilege('service_role','private.'||t,'SELECT');
  ASSERT NOT has_table_privilege('authenticated','private.'||t,'SELECT');
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid=('private.'||t)::regclass),'RLS defense in depth';
 END LOOP;
 -- Account deletion compatibility is proved by real FK cascade, not a name check.
 DELETE FROM public.users WHERE id='19000000-0000-4000-9000-000000000001';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_profiles WHERE user_id='19000000-0000-4000-9000-000000000001');
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_operations WHERE user_id='19000000-0000-4000-9000-000000000001');
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_blocks WHERE target_id='19000000-0000-4000-9000-000000000001');
 BEGIN
  INSERT INTO private.journey_social_profiles(user_id,auth_user_id,revision,opted_in,nickname,consent_version,consented_at)
  VALUES('19000000-0000-4000-9000-000000000004','19000000-0000-4000-8000-000000000004',1,true,'Sem consentimento',NULL,clock_timestamp());
  RAISE EXCEPTION 'missing consent passed the storage constraint';
 EXCEPTION WHEN check_violation THEN NULL; END;
 RAISE NOTICE 'PASS least privilege, private clock, RLS and account deletion cascades';
END $test$;
ROLLBACK;

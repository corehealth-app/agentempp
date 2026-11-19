-- Real private-store tests: synthetic accounts only, rollback every fixture.
BEGIN;
DO $$ BEGIN
 ASSERT to_regprocedure('public.mutate_journey_social_block(uuid,uuid,uuid,bigint,uuid,boolean)') IS NOT NULL,
 'Social blocking command is not implemented';
END $$;
-- Positive ranking fixtures represent the existing confirmed-account policy.
INSERT INTO auth.users(id,email,email_confirmed_at) SELECT ('19200000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'social-r191-'||i||'@example.invalid',clock_timestamp() FROM generate_series(1,7) i;
INSERT INTO public.users(id,auth_user_id,name,timezone) SELECT ('19200000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,
 ('19200000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Synthetic social '||i,'America/Sao_Paulo' FROM generate_series(1,4) i;
INSERT INTO public.admin_users(id,email,role) VALUES
 ('19200000-0000-4000-8000-000000000005','social-r191-5@example.invalid','support'),
 ('19200000-0000-4000-8000-000000000006','social-r191-6@example.invalid','operations_admin'),
 ('19200000-0000-4000-8000-000000000007','social-r191-7@example.invalid','master_admin');
SELECT public.mutate_journey_social_profile(
 ('19200000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,
 ('19200000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 ('19200000-0000-4000-a000-'||lpad(i::text,12,'0'))::uuid,0,true,'Pessoa '||i,'journey-social.v1') IS NOT NULL FROM generate_series(1,4) i;
INSERT INTO public.daily_snapshots(user_id,date,xp_earned,day_closed) SELECT
 ('19200000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,'2026-11-02',
 CASE i WHEN 1 THEN 30 WHEN 2 THEN 30 WHEN 3 THEN 10 ELSE 0 END,true FROM generate_series(1,4) i;
DO $test$
DECLARE a uuid='19200000-0000-4000-9000-000000000001'; u uuid='19200000-0000-4000-8000-000000000001'; p jsonb; q jsonb; c jsonb; first_ids uuid[];
BEGIN
 p:=private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',2,NULL); c:=p->'next_cursor';
 ASSERT jsonb_array_length(p->'entries')=2 AND c<>'null'::jsonb;
 ASSERT p#>>'{entries,0,rank}'='1' AND p#>>'{entries,1,rank}'='1';
 SELECT array_agg((x->>'member_id')::uuid) INTO first_ids FROM jsonb_array_elements(p->'entries') x;
 ASSERT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(c) k)=ARRAY['context_hash','offset','through_date','viewer_member_id','week_start'];
 q:=private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:01:00Z',2,c);
 ASSERT jsonb_array_length(q->'entries')=2 AND q->'next_cursor'='null'::jsonb;
 ASSERT q#>>'{entries,0,rank}'='3' AND q#>>'{entries,1,rank}'='4';
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(q->'entries') x WHERE (x->>'member_id')::uuid=ANY(first_ids));
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page('19200000-0000-4000-9000-000000000002','19200000-0000-4000-8000-000000000002','2026-11-04T16:00:00Z',2,c);
  RAISE EXCEPTION 'cross-viewer cursor accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page(a,u,'2026-11-05T16:00:00Z',2,c);
  RAISE EXCEPTION 'cursor crossed official civil day';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 UPDATE public.daily_snapshots SET xp_earned=31 WHERE user_id=a;
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',2,c);
  RAISE EXCEPTION 'changed ranking accepted old cursor';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 UPDATE public.daily_snapshots SET xp_earned=30 WHERE user_id=a;
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',2,c||'{"owner_id":"unexpected"}'::jsonb);
  RAISE EXCEPTION 'extra cursor authority field accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 RAISE NOTICE 'PASS privacy-bound pagination, shared ranks, day/context changes and cursor shape';
END $test$;
DO $test$
DECLARE a uuid='19200000-0000-4000-9000-000000000001'; u uuid='19200000-0000-4000-8000-000000000001'; b uuid; c uuid; r jsonb; q jsonb; page jsonb; cur jsonb;
BEGIN
 SELECT member_id INTO b FROM private.journey_social_profiles WHERE user_id='19200000-0000-4000-9000-000000000002';
 SELECT member_id INTO c FROM private.journey_social_profiles WHERE user_id='19200000-0000-4000-9000-000000000003';
 page:=private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',1,NULL);cur:=page->'next_cursor';
 r:=public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000001',1,b,true);
 ASSERT r->>'status'='applied' AND r#>>'{profile,revision}'='2';
 q:=public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000001',1,b,true);
 ASSERT q->>'status'='replayed' AND q->'receipt'=r->'receipt';
 ASSERT (SELECT count(*) FROM private.journey_social_blocks WHERE blocker_id=a)=1;
 BEGIN
  PERFORM public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000001',1,b,false);
  RAISE EXCEPTION 'changed block replay accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',1,cur);
  RAISE EXCEPTION 'page after a block disclosed old audience';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 page:=private.project_journey_weekly_ranking_page('19200000-0000-4000-9000-000000000002','19200000-0000-4000-8000-000000000002','2026-11-04T16:00:00Z',50,NULL);
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(page->'entries') x WHERE x->>'is_you'='false' AND x->>'nickname'='Pessoa 1');
 PERFORM public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000002',2,c,true);
 page:=public.read_journey_social_blocks(a,u,1,NULL,NULL);cur:=page->'next_cursor';
 ASSERT jsonb_array_length(page->'entries')=1 AND cur<>'null'::jsonb;
 q:=public.read_journey_social_blocks(a,u,1,(cur->>'after_member_id')::uuid,(cur->>'revision')::bigint);
 ASSERT jsonb_array_length(q->'entries')=1 AND q->'next_cursor'='null'::jsonb;
 PERFORM public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000003',3,b,false);
 BEGIN
  PERFORM public.read_journey_social_blocks(a,u,1,(cur->>'after_member_id')::uuid,(cur->>'revision')::bigint);
  RAISE EXCEPTION 'stale block list cursor accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 q:=public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000001',1,b,true);
 ASSERT q->'receipt'=r->'receipt' AND q#>>'{profile,revision}'='4';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_blocks WHERE blocker_id=a AND target_id='19200000-0000-4000-9000-000000000002'),'replay must not block again';
 BEGIN
  PERFORM public.mutate_journey_social_block(a,u,'19200000-0000-4000-b000-000000000004',4,(SELECT member_id FROM private.journey_social_profiles WHERE user_id=a),true);
  RAISE EXCEPTION 'self block accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 RAISE NOTICE 'PASS actual block/unblock, immutable replay, reverse privacy and list pagination';
END $test$;
DO $test$
DECLARE a uuid='19200000-0000-4000-9000-000000000001'; u uuid='19200000-0000-4000-8000-000000000001'; b uuid; r jsonb; q jsonb;
BEGIN
 SELECT member_id INTO b FROM private.journey_social_profiles WHERE user_id='19200000-0000-4000-9000-000000000002';
 r:=public.submit_journey_social_report(a,u,'19200000-0000-4000-c000-000000000001',4,b,'nickname');
 ASSERT r->>'status'='applied' AND r#>>'{profile,revision}'='5' AND r#>>'{receipt,report_status}'='pending';
 q:=public.submit_journey_social_report(a,u,'19200000-0000-4000-c000-000000000001',4,b,'nickname');
 ASSERT q->>'status'='replayed' AND q->'receipt'=r->'receipt';
 q:=public.submit_journey_social_report(a,u,'19200000-0000-4000-c000-000000000002',5,b,'nickname');
 ASSERT q#>>'{receipt,report_id}'=r#>>'{receipt,report_id}' AND q#>>'{profile,revision}'='6','deduplicate the same pending reason';
 ASSERT (SELECT count(*) FROM private.journey_social_reports WHERE reporter_id=a)=1;
 ASSERT (SELECT moderation FROM private.journey_social_profiles WHERE member_id=b)='active','a report must not automatically suspend anyone';
 BEGIN
  PERFORM public.submit_journey_social_report(a,u,'19200000-0000-4000-c000-000000000003',6,b,'clinical_override');
  RAISE EXCEPTION 'unrecognized free-form reason accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.read_journey_social_reports('19200000-0000-4000-8000-000000000005',50,NULL,NULL);
  RAISE EXCEPTION 'support role read moderation queue';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 q:=public.read_journey_social_reports('19200000-0000-4000-8000-000000000006',50,NULL,NULL);
 ASSERT jsonb_array_length(q->'entries')=1;
 ASSERT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(q#>'{entries,0}') k)=ARRAY['created_at','member_id','moderation','nickname','profile_revision','reason','report_id','revision','status'];
 q:=public.read_journey_social_reports('19200000-0000-4000-8000-000000000007',50,NULL,NULL);
 ASSERT jsonb_array_length(q->'entries')=1,'master administrator retains operational moderation';
 RAISE NOTICE 'PASS idempotent report, pending deduplication, no automatic punishment and staff whitelist';
END $test$;
DO $test$
DECLARE actor uuid='19200000-0000-4000-8000-000000000006'; a uuid='19200000-0000-4000-9000-000000000002'; u uuid='19200000-0000-4000-8000-000000000002'; b uuid; r jsonb; q jsonb; rid uuid;
BEGIN
 SELECT member_id INTO b FROM private.journey_social_profiles WHERE user_id=a;
 BEGIN
  PERFORM public.moderate_journey_social_profile('19200000-0000-4000-8000-000000000005','19200000-0000-4000-d000-000000000001',b,1,'suspend');
  RAISE EXCEPTION 'support suspended a participant';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 r:=public.moderate_journey_social_profile(actor,'19200000-0000-4000-d000-000000000001',b,1,'suspend');
 ASSERT r#>>'{profile,moderation}'='suspended' AND r#>>'{profile,revision}'='2';
 q:=public.moderate_journey_social_profile(actor,'19200000-0000-4000-d000-000000000001',b,1,'suspend');
 ASSERT q->>'status'='replayed' AND q->'receipt'=r->'receipt';
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',50,NULL);
  RAISE EXCEPTION 'suspended viewer read peers';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.mutate_journey_social_profile(a,u,'19200000-0000-4000-e000-000000000001',2,false,NULL,NULL);
 q:=public.moderate_journey_social_profile(actor,'19200000-0000-4000-d000-000000000002',b,3,'restore');
 ASSERT q#>>'{profile,moderation}'='active' AND q#>>'{profile,opted_in}'='false','moderator restore cannot restore consent';
 SELECT id INTO rid FROM private.journey_social_reports WHERE target_id=a;
 r:=public.resolve_journey_social_report(actor,'19200000-0000-4000-d000-000000000003',rid,1,'dismissed');
 ASSERT r#>>'{receipt,revision}'='2' AND r#>>'{receipt,report_status}'='dismissed';
 q:=public.resolve_journey_social_report(actor,'19200000-0000-4000-d000-000000000003',rid,1,'dismissed');
 ASSERT q->>'status'='replayed' AND q->'receipt'=r->'receipt';
 BEGIN
  PERFORM public.resolve_journey_social_report(actor,'19200000-0000-4000-d000-000000000004',rid,1,'resolved');
  RAISE EXCEPTION 'stale report resolution accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 UPDATE public.admin_users SET role='support' WHERE id=actor;
 BEGIN
  PERFORM public.moderate_journey_social_profile(actor,'19200000-0000-4000-d000-000000000001',b,1,'suspend');
  RAISE EXCEPTION 'replay survived operator role revocation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 ASSERT (SELECT sum(xp_earned) FROM public.daily_snapshots WHERE user_id::text LIKE '19200000%')=70;
 ASSERT NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id::text LIKE '19200000%');
 RAISE NOTICE 'PASS operational moderation CAS/audit, role revocation and no consent or XP restoration';
END $test$;
DO $test$
DECLARE a uuid='19200000-0000-4000-9000-000000000001'; u uuid='19200000-0000-4000-8000-000000000001'; p jsonb; c jsonb;
BEGIN
 p:=private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',1,NULL);c:=p->'next_cursor';
 ASSERT c<>'null'::jsonb,'fixture must still have another visible participant';
 PERFORM public.mutate_journey_social_profile('19200000-0000-4000-9000-000000000004','19200000-0000-4000-8000-000000000004','19200000-0000-4000-f000-000000000001',1,false,NULL,NULL);
 BEGIN
  PERFORM private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',1,c);
  RAISE EXCEPTION 'pagination retained withdrawn peer';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 p:=private.project_journey_weekly_ranking_page(a,u,'2026-11-04T16:00:00Z',50,NULL);
 ASSERT jsonb_array_length(p->'entries')=1 AND p#>>'{entries,0,is_you}'='true';
 RAISE NOTICE 'PASS withdrawal during pagination discards prior audience';
END $test$;
DO $test$
DECLARE fn text;
BEGIN
 FOREACH fn IN ARRAY ARRAY[
 'mutate_journey_social_block(uuid,uuid,uuid,bigint,uuid,boolean)',
 'submit_journey_social_report(uuid,uuid,uuid,bigint,uuid,text)',
 'read_journey_social_blocks(uuid,uuid,integer,uuid,bigint)',
 'read_journey_weekly_ranking_page(uuid,uuid,integer,jsonb)',
 'moderate_journey_social_profile(uuid,uuid,uuid,bigint,text)',
 'read_journey_social_reports(uuid,integer,timestamp with time zone,uuid)',
 'resolve_journey_social_report(uuid,uuid,uuid,bigint,text)'] LOOP
  ASSERT NOT has_function_privilege('anon','public.'||fn,'EXECUTE');
  ASSERT NOT has_function_privilege('authenticated','public.'||fn,'EXECUTE');
  ASSERT has_function_privilege('service_role','public.'||fn,'EXECUTE');
 END LOOP;
 ASSERT NOT has_table_privilege('service_role','private.journey_social_reports','SELECT');
 ASSERT NOT has_table_privilege('service_role','private.journey_social_moderation_operations','SELECT');
 DELETE FROM public.users WHERE id='19200000-0000-4000-9000-000000000002';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_reports WHERE target_id='19200000-0000-4000-9000-000000000002');
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_moderation_operations WHERE target_id='19200000-0000-4000-9000-000000000002');
 ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid='private.journey_social_reports'::regclass);
 ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid='private.journey_social_moderation_operations'::regclass);
 ASSERT NOT has_function_privilege('service_role','private.commit_journey_social_peer_command(uuid,uuid,uuid,bigint,uuid,text,text,boolean)','EXECUTE');
 ASSERT NOT has_function_privilege('service_role','private.project_journey_weekly_ranking_page(uuid,uuid,timestamp with time zone,integer,jsonb)','EXECUTE');
 DELETE FROM public.users WHERE id='19200000-0000-4000-9000-000000000001';
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_reports WHERE reporter_id='19200000-0000-4000-9000-000000000001');
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_blocks WHERE blocker_id='19200000-0000-4000-9000-000000000001');
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_operations WHERE user_id='19200000-0000-4000-9000-000000000001');
 RAISE NOTICE 'PASS backend-only privileges, no raw table access and target/reporter account cascades';
END $test$;
ROLLBACK;

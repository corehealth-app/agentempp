-- Synthetic accounts only. Every fixture, trigger and receipt rolls back.
BEGIN;
DO $$ BEGIN
 ASSERT to_regprocedure('public.journey_social_operator_authenticated(uuid,uuid,text,jsonb)') IS NOT NULL,
 'Operational moderation must require an original live operator session';
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at)
 SELECT ('19900000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'moderation-r199-'||i||'@example.invalid',clock_timestamp() FROM generate_series(1,7) i;
INSERT INTO auth.sessions(id,user_id,created_at)
 SELECT ('19900000-0000-4000-a000-'||lpad(i::text,12,'0'))::uuid,
 ('19900000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,clock_timestamp() FROM generate_series(1,7) i;
INSERT INTO public.admin_users(id,email,role) SELECT
 ('19900000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'moderation-r199-'||i||'@example.invalid',
 (ARRAY['support','content_editor','nutrition_admin','operations_admin','master_admin'])[i] FROM generate_series(1,5) i;
INSERT INTO public.users(id,auth_user_id,name) SELECT
 ('19900000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,
 ('19900000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Synthetic participant '||i FROM generate_series(6,7) i;
SELECT public.mutate_journey_social_profile(
 ('19900000-0000-4000-9000-'||lpad(i::text,12,'0'))::uuid,
 ('19900000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 ('19900000-0000-4000-b000-'||lpad(i::text,12,'0'))::uuid,0,true,'Pessoa '||i,'journey-social.v1') IS NOT NULL FROM generate_series(6,7) i;
DO $test$
DECLARE a uuid='19900000-0000-4000-8000-000000000004';s uuid='19900000-0000-4000-a000-000000000004';
 member uuid; report uuid; r jsonb; command jsonb; bad uuid; i integer;
BEGIN
 FOR i IN 1..3 LOOP
  BEGIN
   PERFORM public.journey_social_operator_authenticated(
    ('19900000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
    ('19900000-0000-4000-a000-'||lpad(i::text,12,'0'))::uuid,'queue.read','{"limit":20,"cursor":null}');
   RAISE EXCEPTION 'non-operational admin accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.journey_social_operator_authenticated('19900000-0000-4000-8000-000000000006','19900000-0000-4000-a000-000000000006','queue.read','{"limit":20,"cursor":null}');
  RAISE EXCEPTION 'participant reached operational gateway';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY['19900000-0000-4000-a000-000000000005'::uuid,'19900000-0000-4000-a000-000000000099'::uuid] LOOP
  BEGIN
   PERFORM public.journey_social_operator_authenticated(a,bad,'queue.read','{"limit":20,"cursor":null}');
   RAISE EXCEPTION 'foreign or missing session accepted';
  EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 END LOOP;
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 minute' WHERE id=s;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'queue.read','{"limit":20,"cursor":null}');
  RAISE EXCEPTION 'expired session accepted';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 UPDATE auth.sessions SET not_after=NULL WHERE id=s;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'queue.read','{"limit":20,"cursor":null,"actor_id":"forged"}');
  RAISE EXCEPTION 'client authority override accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'queue.read','{"limit":"20","cursor":null}');
  RAISE EXCEPTION 'coerced page size accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 SELECT member_id INTO member FROM private.journey_social_profiles WHERE user_id='19900000-0000-4000-9000-000000000007';
 r:=public.submit_journey_social_report('19900000-0000-4000-9000-000000000006','19900000-0000-4000-8000-000000000006',
  '19900000-0000-4000-b000-000000000010',1,member,'nickname');
 report:=(r#>>'{receipt,report_id}')::uuid;
 r:=public.journey_social_operator_authenticated(a,s,'queue.read','{"limit":20,"cursor":null}');
 ASSERT jsonb_array_length(r->'entries')=1 AND r#>>'{entries,0,report_id}'=report::text;
 ASSERT NOT (r#>'{entries,0}') ?| ARRAY['reporter_id','target_id','auth_user_id','email','weight','calories','xp'];
 command:=jsonb_build_object('operation_id','19900000-0000-4000-b000-000000000011','member_id',member,'expected_revision',1,'action','suspend');
 r:=public.journey_social_operator_authenticated(a,s,'profile.moderate',command);
 ASSERT r->>'status'='applied' AND r#>>'{profile,moderation}'='suspended' AND r#>>'{receipt,revision}'='2';
 r:=public.journey_social_operator_authenticated(a,s,'profile.moderate',command);
 ASSERT r->>'status'='replayed' AND r#>>'{profile,revision}'='2';
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'profile.moderate',command||'{"action":"restore"}');
  RAISE EXCEPTION 'changed replay accepted';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 r:=public.journey_social_operator_authenticated(a,s,'operation.resolve',jsonb_build_object('kind','profile','command',command));
 ASSERT r->>'status'='applied' AND r#>>'{receipt,moderation}'='suspended';
 -- Resolution of a missing response never executes suspension/restore.
 command:=command||'{"operation_id":"19900000-0000-4000-b000-000000000012","expected_revision":2,"action":"restore"}';
 r:=public.journey_social_operator_authenticated(a,s,'operation.resolve',jsonb_build_object('kind','profile','command',command));
 ASSERT r->>'status'='fenced' AND r->'receipt'='null'::jsonb;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'profile.moderate',command);
  RAISE EXCEPTION 'delayed fenced moderation applied';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 ASSERT (SELECT moderation='suspended' AND revision=2 FROM private.journey_social_profiles WHERE member_id=member);
 -- Even the lower-level backend writer cannot bypass the durable fence.
 BEGIN
  PERFORM public.moderate_journey_social_profile(a,(command->>'operation_id')::uuid,member,2,'restore');
  RAISE EXCEPTION 'lower-level delayed writer bypassed fence';
 EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
 command:=jsonb_build_object('operation_id','19900000-0000-4000-b000-000000000013','report_id',report,'expected_revision',1,'status','resolved');
 r:=public.journey_social_operator_authenticated(a,s,'report.resolve',command);
 ASSERT r->>'status'='applied' AND r#>>'{receipt,report_status}'='resolved';
 ASSERT (SELECT moderation='suspended' AND revision=2 FROM private.journey_social_profiles WHERE member_id=member),'resolving report cannot restore profile';
 r:=public.journey_social_operator_authenticated(a,s,'operation.resolve',jsonb_build_object('kind','report','command',command));
 ASSERT r->>'status'='applied' AND r#>>'{receipt,report_id}'=report::text;
 UPDATE public.admin_users SET role='support' WHERE id=a;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'report.resolve',command);
  RAISE EXCEPTION 'revoked role replay accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE public.admin_users SET role='operations_admin' WHERE id=a;
 DELETE FROM auth.sessions WHERE id=s;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'operation.resolve',jsonb_build_object('kind','report','command',command));
  RAISE EXCEPTION 'logout accepted receipt recovery';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 r:=public.journey_social_operator_authenticated('19900000-0000-4000-8000-000000000005','19900000-0000-4000-a000-000000000005','queue.read','{"limit":20,"cursor":null}');
 ASSERT r->'entries'='[]'::jsonb;
 RAISE NOTICE 'PASS closed operational access, fresh roles/sessions, separate moderation/resolution, replay and durable no-write recovery';
END $test$;
CREATE TEMP SEQUENCE operator_writer_reached;
CREATE FUNCTION pg_temp.expire_operator_writer() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 PERFORM nextval('pg_temp.operator_writer_reached');PERFORM pg_sleep(.35);RETURN NEW;END$$;
CREATE TRIGGER operator_delay BEFORE UPDATE ON private.journey_social_profiles FOR EACH ROW EXECUTE FUNCTION pg_temp.expire_operator_writer();
DO $test$
DECLARE a uuid='19900000-0000-4000-8000-000000000005';s uuid='19900000-0000-4000-a000-000000000005';member uuid;
BEGIN
 SELECT member_id INTO member FROM private.journey_social_profiles WHERE user_id='19900000-0000-4000-9000-000000000007';
 UPDATE auth.sessions SET not_after=clock_timestamp()+interval '.25 seconds' WHERE id=s;
 BEGIN
  PERFORM public.journey_social_operator_authenticated(a,s,'profile.moderate',jsonb_build_object('operation_id','19900000-0000-4000-b000-000000000014','member_id',member,'expected_revision',2,'action','restore'));
  RAISE EXCEPTION 'session expiry during writer committed';
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 ASSERT (SELECT is_called FROM pg_temp.operator_writer_reached),'must reach actual profile writer';
 ASSERT (SELECT moderation='suspended' AND revision=2 FROM private.journey_social_profiles WHERE member_id=member);
 ASSERT NOT EXISTS(SELECT 1 FROM private.journey_social_moderation_operations WHERE operation_id='19900000-0000-4000-b000-000000000014');
 ASSERT NOT has_function_privilege('anon','public.journey_social_operator_authenticated(uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('authenticated','public.journey_social_operator_authenticated(uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT has_function_privilege('service_role','public.journey_social_operator_authenticated(uuid,uuid,text,jsonb)','EXECUTE');
 ASSERT NOT has_table_privilege('service_role','private.journey_social_moderation_fences','SELECT');
 RAISE NOTICE 'PASS expiry after actual writer rolls back effect and receipt; gateway-only grants';
END $test$;
ROLLBACK;

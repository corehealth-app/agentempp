-- Shared regression body: real legacy confirmations without a proven signup Y.
-- Run once in READ COMMITTED and once in actual REPEATABLE READ, rollback only.
SET LOCAL search_path=pg_catalog;
DO $target$ BEGIN
 IF session_user<>'c5_local_admin' OR current_user<>'c5_local_admin'
  OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
  OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
  OR current_setting('listen_addresses')<>'' OR inet_server_addr() IS NOT NULL
  OR current_setting('transaction_isolation') NOT IN('read committed','repeatable read')
  OR current_setting('transaction_read_only')<>'off'
  OR to_regnamespace('c59_plan_compat') IS NOT NULL
  OR to_regprocedure('private.capture_mobile_plan_strength_week_source(uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_WRONG_LOCAL_TARGET'; END IF;
END $target$;
CREATE SCHEMA c59_plan_compat AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
CREATE FUNCTION c59_plan_compat.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
REVOKE ALL ON FUNCTION c59_plan_compat.state(uuid) FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $compat$
DECLARE
 u constant uuid:='c59d2d00-0000-4000-8000-000000000901';
 media_photo constant uuid:='c59d2d00-0000-4000-8000-000000000911';
 media_pdf constant uuid:='c59d2d00-0000-4000-8000-000000000912';
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"seg","focus":"full body","exercises":[]},{"day":"qui","focus":"full body","exercises":[]}]}';
 initial jsonb;after_flow jsonb;before_replay jsonb;d jsonb;answer jsonb;replayed jsonb;
 flow_draft uuid;flow_plan uuid;flow_answer jsonb;flow_row jsonb;v_valid timestamptz;
 v_origin text;role_name text;helper regprocedure;fn record;plan public.training_plans%ROWTYPE;
 excluded constant text[]:=ARRAY['public.plan_drafts','public.training_plans'];
 iso constant text:=current_setting('transaction_isolation');
BEGIN
 helper:='private.capture_mobile_plan_strength_week_source(uuid,uuid,uuid)'::regprocedure;
 SELECT p.*,pg_get_userbyid(p.proowner) AS owner INTO STRICT fn FROM pg_proc p WHERE oid=helper;
 IF fn.owner<>'postgres' OR fn.prosecdef OR fn.provolatile<>'v'
  OR fn.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR EXISTS(SELECT 1 FROM aclexplode(coalesce(fn.proacl,acldefault('f',fn.proowner))) a
    WHERE a.grantee<>fn.proowner AND a.privilege_type='EXECUTE')
  OR NOT has_function_privilege('postgres',helper,'EXECUTE')
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_HELPER_NOT_OWNER_ONLY'; END IF;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF has_function_privilege(role_name,helper,'EXECUTE') THEN
   RAISE EXCEPTION 'C59PLAN_COMPAT_HELPER_EXPOSED:%',role_name;
  END IF;
 END LOOP;
 IF NOT has_function_privilege('service_role','public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)','EXECUTE')
  OR has_function_privilege('anon','public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)','EXECUTE')
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_CONFIRMATION_ACL_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN RAISE EXCEPTION 'C59PLAN_COMPAT_OWNER_COLLISION'; END IF;
 INSERT INTO public.users(id,email,wpp,name,status,timezone,metadata)
  VALUES(u,NULL,NULL,'C59 compatibility synthetic','active','UTC','{"qa_owner":"P1-compatibility"}');
 initial:=c59_plan_compat.state(u);
 IF EXISTS(SELECT 1 FROM jsonb_each(initial) x WHERE x.key<>'user' AND x.value<>'[]'::jsonb)
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_OWNER_NOT_EMPTY'; END IF;
 -- Local database rows only: no object upload, network request or extraction.
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,
  status,source_request_hash,retention_until) VALUES
  (media_photo,u,'meal_photo','meal-photos',u::text||'/'||media_photo::text||'.jpg','image/jpeg',1024,
   'pending_upload',repeat('a',64),clock_timestamp()+interval '30 days'),
  (media_pdf,u,'meal_photo','meal-photos',u::text||'/'||media_pdf::text||'.jpg','image/jpeg',1024,
   'pending_upload',repeat('b',64),clock_timestamp()+interval '30 days');
 initial:=c59_plan_compat.state(u);
 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'P1-compat-flow-create-20261020');
 v_valid:=clock_timestamp()+interval '42 days';
 answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,v_valid,'P1-compat-flow-confirm');
 SET LOCAL ROLE postgres;
 flow_draft:=(d->>'id')::uuid;flow_plan:=(answer->>'confirmed_plan_id')::uuid;flow_answer:=answer;
 SELECT * INTO STRICT plan FROM public.training_plans WHERE id=flow_plan AND user_id=u;
 IF answer->>'status' IS DISTINCT FROM 'confirmed' OR (answer->>'already_confirmed')::boolean IS NOT FALSE
  OR plan.active IS NOT TRUE OR plan.days_per_week IS DISTINCT FROM 2
  OR plan.generated_by IS DISTINCT FROM 'flow_draft' OR plan.valid_until IS DISTINCT FROM v_valid
  OR plan.source_request_key IS DISTINCT FROM 'plan-draft:'||flow_draft::text
  OR NOT EXISTS(SELECT 1 FROM public.plan_drafts x WHERE x.id=flow_draft AND x.user_id=u
   AND x.status='confirmed' AND x.confirmed_plan_id=flow_plan AND x.resolved_at=plan.generated_at)
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_FLOW_CONFIRMATION_WRONG'; END IF;
 after_flow:=c59_plan_compat.state(u);flow_row:=to_jsonb(plan);
 IF after_flow-excluded IS DISTINCT FROM initial-excluded
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_FLOW_INVENTED_AUTHORITY_OR_SIDE_EFFECT'; END IF;
 SET LOCAL ROLE service_role;
 replayed:=public.confirm_plan_draft_atomic(u,flow_draft,1,clock_timestamp()+interval '60 days','P1-compat-flow-confirm');
 SET LOCAL ROLE postgres;
 IF (replayed->>'already_confirmed')::boolean IS NOT TRUE
  OR replayed-'already_confirmed' IS DISTINCT FROM flow_answer-'already_confirmed'
  OR c59_plan_compat.state(u) IS DISTINCT FROM after_flow
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_FLOW_REPLAY_CHANGED_STATE'; END IF;
 FOREACH v_origin IN ARRAY ARRAY['imported_photo','imported_pdf'] LOOP
  SET LOCAL ROLE service_role;
  d:=public.create_plan_draft_atomic(u,'training',v_origin,'ready_for_review',payload,
   NULL,NULL,NULL,CASE v_origin WHEN 'imported_photo' THEN media_photo ELSE media_pdf END,NULL,NULL,'P1-compat-'||v_origin||'-create-20261020');
  answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,NULL,'P1-compat-'||v_origin||'-confirm');
  SET LOCAL ROLE postgres;
  SELECT * INTO STRICT plan FROM public.training_plans WHERE id=(answer->>'confirmed_plan_id')::uuid AND user_id=u;
  IF answer->>'status' IS DISTINCT FROM 'confirmed' OR (answer->>'already_confirmed')::boolean IS NOT FALSE
   OR plan.active IS NOT TRUE OR plan.days_per_week IS DISTINCT FROM 2 OR plan.valid_until IS NOT NULL
   OR plan.generated_by IS DISTINCT FROM 'patient_import'
   OR plan.source_request_key IS DISTINCT FROM 'plan-draft:'||(d->>'id')
   OR (SELECT count(*) FROM public.training_plans WHERE user_id=u AND active)<>1
   OR NOT EXISTS(SELECT 1 FROM public.plan_drafts x WHERE x.id=(d->>'id')::uuid AND x.user_id=u
    AND x.origin=v_origin AND x.status='confirmed' AND x.confirmed_plan_id=plan.id AND x.resolved_at=plan.generated_at)
  THEN RAISE EXCEPTION 'C59PLAN_COMPAT_IMPORT_CONFIRMATION_WRONG:%',v_origin; END IF;
  before_replay:=c59_plan_compat.state(u);
  IF before_replay-excluded IS DISTINCT FROM initial-excluded
  THEN RAISE EXCEPTION 'C59PLAN_COMPAT_IMPORT_INVENTED_AUTHORITY_OR_SIDE_EFFECT'; END IF;
  SET LOCAL ROLE service_role;
  replayed:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,clock_timestamp()+interval '42 days','P1-compat-'||v_origin||'-confirm');
  SET LOCAL ROLE postgres;
  IF (replayed->>'already_confirmed')::boolean IS NOT TRUE
   OR replayed-'already_confirmed' IS DISTINCT FROM answer-'already_confirmed'
   OR c59_plan_compat.state(u) IS DISTINCT FROM before_replay
  THEN RAISE EXCEPTION 'C59PLAN_COMPAT_IMPORT_REPLAY_CHANGED_STATE:%',v_origin; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.training_plans WHERE user_id=u)<>3
  OR (SELECT count(*) FROM public.plan_drafts WHERE user_id=u)<>3
  OR (SELECT to_jsonb(x)-'active' FROM public.training_plans x WHERE id=flow_plan) IS DISTINCT FROM flow_row-'active'
  OR (SELECT active FROM public.training_plans WHERE id=flow_plan) IS NOT FALSE
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_REPLACEMENT_DAMAGED_ORIGINAL_PLAN'; END IF;
 before_replay:=c59_plan_compat.state(u);
 SET LOCAL ROLE service_role;
 replayed:=public.confirm_plan_draft_atomic(u,flow_draft,1,clock_timestamp()+interval '42 days','P1-compat-flow-confirm');
 SET LOCAL ROLE postgres;
 IF (replayed->>'already_confirmed')::boolean IS NOT TRUE
  OR replayed-'already_confirmed' IS DISTINCT FROM flow_answer-'already_confirmed'
  OR c59_plan_compat.state(u) IS DISTINCT FROM before_replay
  OR current_setting('transaction_isolation') IS DISTINCT FROM iso
 THEN RAISE EXCEPTION 'C59PLAN_COMPAT_OLD_REPLAY_CHANGED_STATE_OR_ISOLATION'; END IF;
 RAISE NOTICE 'C59PLAN_COMPAT_NO_Y_FLOW_BOTH_IMPORTS_REPLAY_ACL:%',iso;
END $compat$;
RESET ROLE;
SET LOCAL search_path=pg_catalog;

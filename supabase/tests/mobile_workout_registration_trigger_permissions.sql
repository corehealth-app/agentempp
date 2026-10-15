\set ON_ERROR_STOP on
-- POSITIVE REGRESSION: same source before and after fix; success is always required.
-- Root runs this file twice, each in a NEW direct-local psql process/backend: warm_case=false / true.
\if :{?warm_case}
\else
\set warm_case false
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $target$BEGIN
 IF session_user<>'c5_local_admin' OR current_user<>'c5_local_admin' OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
 OR current_setting('listen_addresses')<>'' OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
 THEN RAISE EXCEPTION 'C59S17B_LEGACY_EDIT_R2_WRONG_LOCAL_TARGET';END IF;
 IF to_regnamespace('c59s17b_fixture')IS NOT NULL THEN RAISE EXCEPTION 'C59S17B_LEGACY_EDIT_R2_SCHEMA_COLLISION';END IF;
 IF to_regprocedure('private.guard_mobile_workout_registration()')IS NULL OR to_regclass('private.mobile_workout_registration_edit_receipts')IS NULL
 THEN RAISE EXCEPTION 'C59S17B_LEGACY_EDIT_R2_PRODUCT_ABSENT';END IF;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN('c59b7000-0000-0000-0000-000000000715','c59b7000-0000-0000-0000-000000000716')OR email IN('c59s17b-715@example.invalid','c59s17b-716@example.invalid')OR wpp IN('1555170000715','1555170000716'))
 THEN RAISE EXCEPTION 'C59S17B_LEGACY_EDIT_R2_OWNER_COLLISION';END IF;
END $target$;
\ir fixtures/mobile_workout_registration_boundary_fixture.sql
CREATE TEMP TABLE c59s17b_legacy_edit_context(case_id text NOT NULL,warm_packet jsonb,packet jsonb)ON COMMIT DROP;
INSERT INTO pg_temp.c59s17b_legacy_edit_context(case_id)VALUES(CASE WHEN (:'warm_case')::boolean THEN 'warm_c5_owned_insert_then_service'ELSE 'cold_service_first'END);
\if :warm_case
-- Exact preceding legacy INSERT shape from original715; replace_pending is SECURITY INVOKER.
-- First UPDATE touches zero715 rows, so it does NOT prime a row-level UPDATE trigger branch.
DO $warm$DECLARE u uuid:=c59s17b_fixture.owner(715);r jsonb;s text;m text;role_before text:=current_user;BEGIN
 BEGIN
 r:=public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',clock_timestamp()+interval '1 hour',c59s17b_fixture.key(715));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;END;
 UPDATE pg_temp.c59s17b_legacy_edit_context SET warm_packet=jsonb_build_object('caller_role',role_before,'ok',s IS NULL,'result',r,'sqlstate',s,'message',m,
 'replace_security_definer',(SELECT prosecdef FROM pg_proc WHERE oid='public.replace_pending_registration_atomic(uuid,jsonb,timestamp with time zone,text)'::regprocedure),
 'actual_pending',(SELECT coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb)FROM ONLY public.pending_registrations p WHERE user_id=u));
END $warm$;
\endif
DO $exact_case$DECLARE u uuid:=c59s17b_fixture.owner(716);v jsonb:='{"kind":"workout","durationMin":20}';e timestamptz:=clock_timestamp()+interval '1 hour';pid uuid;r jsonb;s jsonb;old_row jsonb;after_state jsonb;original_assert boolean;insert_packet jsonb;insert_assert boolean;update_attempted boolean:=false;BEGIN
 s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('INSERT INTO public.pending_registrations(user_id,proposal,expires_at)VALUES(%L,%L::jsonb,%L::timestamptz)RETURNING to_jsonb(pending_registrations)',u,v,e));pid:=(r#>>'{result,id}')::uuid;insert_packet:=r;
 insert_assert:=r->'ok'='true'::jsonb AND r#>>'{result,user_id}'=u::text AND r#>>'{result,status}'='pending'AND r#>'{result,proposal}'=v AND(r#>>'{result,expires_at}')::timestamptz=e AND r#>'{result,workout_ui_admission_id}'='null'::jsonb AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result'));
 IF r->'ok'='true'::jsonb AND pid IS NOT NULL THEN
 s:=c59s17b_fixture.state(u);old_row:=s->'public.pending_registrations'->0;v:=v||'{"durationMin":25}';e:=e+interval '1 hour';
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET proposal=%L::jsonb,expires_at=%L::timestamptz WHERE id=%L RETURNING to_jsonb(pending_registrations)',v,e,pid));update_attempted:=true;
 original_assert:=r->'ok'='true'::jsonb AND (r->'result')-ARRAY['proposal','expires_at']=old_row-ARRAY['proposal','expires_at']AND r#>'{result,proposal}'=v AND(r#>>'{result,expires_at}')::timestamptz=e AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result'));
 ELSE
 -- No invented UUID/second UPDATE on a missing row. Preserve INSERT's real failure packet separately.
 r:=NULL;
 END IF;
 after_state:=c59s17b_fixture.state(u);
 UPDATE pg_temp.c59s17b_legacy_edit_context SET packet=jsonb_build_object(
 'kind','C59S17B_TRIGGER_PERMISSION_POSITIVE_REGRESSION_R1','case_id',case_id,'backend_pid',pg_backend_pid(),'session_user',session_user,'current_user',current_user,
 'owner',u,'pending_id',pid,'warm_packet',warm_packet,'insert_packet',insert_packet,'insert_original_assert',insert_assert,'update_attempted',update_attempted,'update_packet',r,
 'components',jsonb_build_object('attempt_ok',r->'ok'='true'::jsonb,
 'unchanged_fields',(r->'result')-ARRAY['proposal','expires_at']=old_row-ARRAY['proposal','expires_at'],
 'proposal_exact',r#>'{result,proposal}'=v,'expiry_exact',(r#>>'{result,expires_at}')::timestamptz=e,
 'full_state_exact',CASE WHEN update_attempted THEN after_state=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result'))ELSE NULL END,'original_assert',original_assert),
 'expected_proposal',v,'expected_expiry',e,'old_pending',old_row,'before_state',s,'after_state',after_state,
 'old_without_mutated_fields',old_row-ARRAY['proposal','expires_at'],'returned_without_mutated_fields',(r->'result')-ARRAY['proposal','expires_at'],
 'expected_after_state',CASE WHEN update_attempted THEN jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result'))ELSE NULL END,
 'effective_service_private_usage',has_schema_privilege('service_role','private','USAGE'),
 'effective_service_pending_update',has_table_privilege('service_role','public.pending_registrations','UPDATE'),
 'pending_noninternal_triggers',(SELECT jsonb_agg(jsonb_build_object('name',t.tgname,'definition',pg_get_triggerdef(t.oid),'function_md5',md5(p.prosrc))ORDER BY t.oid)FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE t.tgrelid='public.pending_registrations'::regclass AND NOT t.tgisinternal));
END $exact_case$;
-- Native errors remain in the exception packet. No expected-error or skip parameter exists.
DO $positive_oracles$DECLARE p jsonb:=(SELECT packet FROM pg_temp.c59s17b_legacy_edit_context);BEGIN
 IF p IS NULL THEN RAISE EXCEPTION 'C59S17B_TRIGGER_PERMISSION_DIAGNOSTIC_MISSING';END IF;
 IF p->'insert_original_assert'IS DISTINCT FROM 'true'::jsonb THEN
 RAISE EXCEPTION 'C59S17B_TRIGGER_PERMISSION_INSERT:%',p;
 END IF;
 IF p->'update_attempted'IS DISTINCT FROM 'true'::jsonb OR p#>'{components,original_assert}'IS DISTINCT FROM 'true'::jsonb THEN
 RAISE EXCEPTION 'C59S17B_TRIGGER_PERMISSION_EDIT:%',p;
 END IF;
 IF p->'effective_service_private_usage'IS DISTINCT FROM 'false'::jsonb THEN
 RAISE EXCEPTION 'C59S17B_TRIGGER_PERMISSION_PRIVATE_USAGE_WIDENED:%',p;
 END IF;
 IF p->>'case_id'='warm_c5_owned_insert_then_service'AND(p#>'{warm_packet,ok}'IS DISTINCT FROM 'true'::jsonb
 OR p#>>'{warm_packet,caller_role}'IS DISTINCT FROM 'c5_local_admin'OR p#>'{warm_packet,replace_security_definer}'IS DISTINCT FROM 'false'::jsonb
 OR jsonb_array_length(p#>'{warm_packet,actual_pending}')IS DISTINCT FROM 1)THEN
 RAISE EXCEPTION 'C59S17B_TRIGGER_PERMISSION_WARM_SETUP:%',p;
 END IF;
 RAISE NOTICE 'C59S17B_TRIGGER_PERMISSION_PASS:%:INSERT_EDIT_FULLSTATE_NO_PRIVATE_USAGE',p->>'case_id';
END $positive_oracles$;
SELECT packet FROM pg_temp.c59s17b_legacy_edit_context;
ROLLBACK;
DO $rolled_back$BEGIN
 IF to_regnamespace('c59s17b_fixture')IS NOT NULL OR to_regclass('pg_temp.c59s17b_legacy_edit_context')IS NOT NULL
 OR EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN('c59b7000-0000-0000-0000-000000000715','c59b7000-0000-0000-0000-000000000716')OR email IN('c59s17b-715@example.invalid','c59s17b-716@example.invalid')OR wpp IN('1555170000715','1555170000716'))
 THEN RAISE EXCEPTION 'C59S17B_LEGACY_EDIT_R2_ROLLBACK_FAILED';END IF;
END $rolled_back$;
\echo C59S17B_TRIGGER_PERMISSIONS_ROLLBACK_CONFIRMED

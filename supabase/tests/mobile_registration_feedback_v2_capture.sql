-- Synthetic local SQL qualification only; fixture effects always roll back.
BEGIN;
CREATE TEMP TABLE v2_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.v2ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'V2_ASSERT: %',label; END IF; INSERT INTO v2_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.v2_service_capture(p_owner uuid,p_registration uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result jsonb;
BEGIN
 SET LOCAL ROLE service_role;
 result:=public.capture_mobile_registration_feedback_v2(p_owner,p_registration);
 SET LOCAL ROLE NONE;
 RETURN result;
END $$;
CREATE FUNCTION pg_temp.v2_owner_state(p_owner uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t record;part jsonb;result jsonb;
BEGIN
 SELECT to_jsonb(u) INTO result FROM public.users u WHERE id=p_owner;result:=jsonb_build_object('users',result);
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN('public','private') AND c.relkind IN('r','p') AND EXISTS(SELECT 1 FROM pg_attribute a
   WHERE a.attrelid=c.oid AND a.attname='user_id' AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)
  ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM %I.%I x WHERE user_id=$1',t.nspname,t.relname) INTO part USING p_owner;
  result:=result||jsonb_build_object(t.nspname||'.'||t.relname,part);
 END LOOP;RETURN result;
END $$;
DO $test$
DECLARE a uuid:='b2b00000-0000-4000-8000-000000000001';b uuid:='b2b00000-0000-4000-8000-000000000002';
 rid uuid:='b2b00000-0000-4000-8000-000000000003';sid uuid:='b2b00000-0000-4000-8000-000000000004';mid uuid:='b2b00000-0000-4000-8000-000000000005';
 ts timestamptz:=date_trunc('second',clock_timestamp());p jsonb;c jsonb;x jsonb;before_cursor jsonb;actual text;before_all jsonb;binding jsonb;changed jsonb;
BEGIN
 PERFORM pg_temp.v2ok(to_regprocedure('public.capture_mobile_registration_feedback_v2(uuid,uuid)') IS NOT NULL,'v2 capture RPC exists');
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'v2-a@example.invalid','active','UTC','BR',true),(b,'v2-b@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date,calories_target,protein_target,calories_consumed,protein_g,carbs_g,fat_g) VALUES(sid,a,(ts AT TIME ZONE 'UTC')::date,1900,120,126,6.3,9.5,6.5);
 INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,consumed_at,meal_type,raw_provider_message_id) VALUES(mid,a,sid,'leite integral',206,126.12,6.3,9.5,6.5,'product_label',ts,'cafe','v2-owned-meal');
 p:=jsonb_build_object('kind','meal','mealType','cafe','registration_origin','mobile_app','source_provider_message_id','v2-owned-meal','source_timestamp',to_char(ts AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'source_timezone','UTC','source_local_date',(ts AT TIME ZONE 'UTC')::date::text,'items',jsonb_build_array(jsonb_build_object('name','leite integral','quantity_g',206,'kcal',126.12,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5,'nutrition_source','product_label')),'totals',jsonb_build_object('kcal',126.1,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5));
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(rid,a,'confirmed',p,ts+interval '1 day');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 SELECT jsonb_build_object('revision',flow_shared_phrase_revision,'cursor',flow_shared_phrase_cursor) INTO before_cursor FROM public.users WHERE id=a;
 before_all:=pg_temp.v2_owner_state(a);
 c:=pg_temp.v2_service_capture(a,rid);
 PERFORM pg_temp.v2ok(before_all=pg_temp.v2_owner_state(a),'capture changes no owned persisted table');
 PERFORM pg_temp.v2ok(c->>'action'='available','owned confirmed capture available');
 PERFORM pg_temp.v2ok(c#>>'{context,confirmed,user_id}'=a::text AND c#>>'{context,confirmed,id}'=rid::text,'private owner and event are bound');
 PERFORM pg_temp.v2ok(c#>>'{context,logs,0,id}'=mid::text AND c#>'{context,logs,0,kcal}'='126.12'::jsonb,'actual stored item facts');
 PERFORM pg_temp.v2ok(c#>'{context,confirmed,proposal,totals,kcal}'='126.1'::jsonb,'canonical total kept separately');
 PERFORM pg_temp.v2ok(c#>>'{context,snapshot,id}'=sid::text AND c#>>'{context,clinical,user_id}'=a::text,'day and clinical ownership');
 binding:=private.mobile_registration_feedback_v2_source_binding(c->'context');
 changed:=jsonb_set(c->'context','{clinical}',(c#>'{context,clinical}')||jsonb_build_object('observed_at','2026-11-03T01:00:00Z','context_hash','different-clock','safety',jsonb_build_object('observed_at','2026-11-03T01:00:00Z')));
 PERFORM pg_temp.v2ok(private.mobile_registration_feedback_v2_source_binding(changed)=binding,'CAS ignores dynamic clinical clocks only');
 changed:=jsonb_set(c->'context','{clinical,epoch}',to_jsonb(b::text));
 PERFORM pg_temp.v2ok(private.mobile_registration_feedback_v2_source_binding(changed)<>binding,'CAS binds changed authority epoch');
 changed:=jsonb_set(c->'context','{snapshot,calories_consumed}','999'::jsonb);
 PERFORM pg_temp.v2ok(private.mobile_registration_feedback_v2_source_binding(changed)<>binding,'CAS binds official snapshot change');
 changed:=jsonb_set(c->'context','{logs,0,kcal}','999'::jsonb);
 PERFORM pg_temp.v2ok(private.mobile_registration_feedback_v2_source_binding(changed)<>binding,'CAS binds saved item change');

 x:=pg_temp.v2_service_capture(b,rid);PERFORM pg_temp.v2ok(x='{"action":"event_conflict"}'::jsonb,'foreign owner rejected without context');
 UPDATE public.pending_registrations SET status='pending' WHERE id=rid;
 PERFORM pg_temp.v2ok(pg_temp.v2_service_capture(a,rid)='{"action":"event_conflict"}'::jsonb,'pending not a saved event');
 UPDATE public.pending_registrations SET status='confirmed',proposal=p-'registration_origin' WHERE id=rid;
 PERFORM pg_temp.v2ok(pg_temp.v2_service_capture(a,rid)='{"action":"event_conflict"}'::jsonb,'nonmobile proposal rejected');
 UPDATE public.pending_registrations SET proposal=p WHERE id=rid;
 UPDATE public.meal_logs SET kcal=190 WHERE id=mid;
 PERFORM pg_temp.v2ok(pg_temp.v2_service_capture(a,rid)='{"action":"event_conflict"}'::jsonb,'edited saved facts do not regenerate original receipt');
 PERFORM pg_temp.v2ok(before_cursor=(SELECT jsonb_build_object('revision',flow_shared_phrase_revision,'cursor',flow_shared_phrase_cursor) FROM public.users WHERE id=a),'capture never advances v1 phrases');
 PERFORM pg_temp.v2ok(NOT has_function_privilege('anon','public.capture_mobile_registration_feedback_v2(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.capture_mobile_registration_feedback_v2(uuid,uuid)','EXECUTE') AND has_function_privilege('service_role','public.capture_mobile_registration_feedback_v2(uuid,uuid)','EXECUTE'),'service-only public capture ACL');
 PERFORM pg_temp.v2ok(NOT has_table_privilege('service_role','private.mobile_registration_feedback_v2','INSERT') AND NOT has_table_privilege('authenticated','private.mobile_registration_feedback_v2','SELECT'),'private receipt ACL');
 INSERT INTO private.mobile_registration_feedback_v2(registration_id,user_id,proposal_hash,source_hash,feedback)
 VALUES(rid,a,repeat('a',64),repeat('b',64),jsonb_build_object('schema','registration.feedback.v2'));
 BEGIN UPDATE private.mobile_registration_feedback_v2 SET source_hash=repeat('c',64) WHERE registration_id=rid;
  RAISE EXCEPTION 'immutable update accepted';EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 PERFORM pg_temp.v2ok((SELECT source_hash=repeat('b',64) FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'receipt cannot be updated');
 BEGIN DELETE FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid;
  RAISE EXCEPTION 'direct receipt deletion accepted';EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 PERFORM pg_temp.v2ok(EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'receipt cannot be deleted independently');
 DELETE FROM public.pending_registrations WHERE id=rid;
 PERFORM pg_temp.v2ok(NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'owned pending cascade is allowed');

END $test$;
SELECT count(*) AS assertions FROM v2_assertions;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $isolation$
DECLARE actual text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 BEGIN PERFORM public.capture_mobile_registration_feedback_v2('b2b00000-0000-4000-8000-000000000001','b2b00000-0000-4000-8000-000000000003');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
 ASSERT actual='22023','feedback capture must require READ COMMITTED';
END $isolation$;
ROLLBACK;

BEGIN;
CREATE TEMP TABLE store_context(c jsonb,f jsonb) ON COMMIT DROP;
CREATE TEMP TABLE store_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.store_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'V2_STORE_ASSERT: %',label; END IF; INSERT INTO store_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.service_commit(a uuid,r uuid,c jsonb,f jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x jsonb;
BEGIN SET LOCAL ROLE service_role;x:=public.commit_mobile_registration_feedback_v2(a,r,c,f);SET LOCAL ROLE NONE;RETURN x;END $$;
CREATE FUNCTION pg_temp.fail_v2_insert() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'forced receipt rollback' USING ERRCODE='P5502';END $$;
CREATE FUNCTION pg_temp.empty_cursor(u uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','flow.phrase-state.v1','userId',u::text,'catalogVersion','flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb','ordinal',0,'lastTextKey',NULL,'usedTextKeys',jsonb_build_array());$$;
CREATE FUNCTION pg_temp.step(u uuid,r uuid,stage text,old jsonb,phrase text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c jsonb:=old; k text; s jsonb;
BEGIN
 IF phrase IS NOT NULL THEN k:=encode(extensions.digest(convert_to(phrase,'UTF8'),'sha256'),'hex');
 c:=jsonb_set(jsonb_set(jsonb_set(c,'{ordinal}',to_jsonb((c->>'ordinal')::int+1)),'{lastTextKey}',to_jsonb(k)),'{usedTextKeys}',(c->'usedTextKeys')||jsonb_build_array(k));END IF;
 s:=jsonb_build_object('phrase',phrase,'phraseId',CASE WHEN phrase IS NULL THEN NULL WHEN stage='food' THEN 'food:b:bom_iogurtes_proteicos:005' ELSE 'engagement:002' END,
 'sourceText',phrase,'foodCanonicalName',CASE WHEN stage='food' AND phrase IS NOT NULL THEN 'iogurte natural' ELSE NULL END,
 'reason',CASE WHEN phrase IS NULL THEN 'unsupported_language' WHEN stage='food' THEN 'selected_food' WHEN stage='workout' THEN 'workout_incentive_fallback' ELSE 'selected_incentive' END);
 RETURN jsonb_build_object('receipt',jsonb_build_object('eventKey','mobile_registration/'||u::text||'/'||r::text||'/'||CASE WHEN stage='food' THEN 'food' ELSE 'incentive' END,'requestFingerprint',repeat('a',64),'selection',s),'nextCursor',c);
END;$$;
CREATE FUNCTION pg_temp.feedback(r uuid,kind text,steps jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','registration.feedback.v1','registration_id',r::text,'kind',kind,
 'locale',CASE WHEN steps#>'{0,receipt,selection,phrase}'='null'::jsonb THEN 'en' ELSE 'pt-BR' END,
 'meal_totals',CASE WHEN kind='meal' THEN jsonb_build_object('kcal',435,'protein_g',42,'carbs_g',49,'fat_g',5) ELSE NULL END,
 'day',NULL,'lines',(CASE WHEN kind='meal' THEN jsonb_build_array(jsonb_build_object('key','meal_totals','text','435 kcal | synthetic meal totals')) ELSE '[]'::jsonb END)||jsonb_build_array(jsonb_build_object('key','day_unavailable','text','Synthetic numbers unavailable.')),
 'food_comment',CASE WHEN kind='meal' THEN steps#>'{0,receipt,selection,phrase}' ELSE 'null'::jsonb END,
 'incentive',steps#>ARRAY[(jsonb_array_length(steps)-1)::text,'receipt','selection','phrase']);$$;
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
DECLARE a uuid:='c2b00000-0000-4000-8000-000000000001';rid uuid:='c2b00000-0000-4000-8000-000000000003';sid uuid:='c2b00000-0000-4000-8000-000000000004';mid uuid:='c2b00000-0000-4000-8000-000000000005';
 ts timestamptz:=date_trunc('second',clock_timestamp());p jsonb;c jsonb;f jsonb;x jsonb;k text;mut jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'v2-contract@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date,calories_target,protein_target,calories_consumed,protein_g,carbs_g,fat_g,exercise_calories) VALUES(sid,a,(ts AT TIME ZONE 'UTC')::date,1900,120,126,6.3,9.5,6.5,504);
 INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,consumed_at,meal_type,raw_provider_message_id) VALUES(mid,a,sid,'leite integral',206,126.12,6.3,9.5,6.5,'product_label',ts,'cafe','v2-contract-meal');
 p:=jsonb_build_object('kind','meal','mealType','cafe','registration_origin','mobile_app','source_provider_message_id','v2-contract-meal','source_timestamp',to_char(ts AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'source_timezone','UTC','source_local_date',(ts AT TIME ZONE 'UTC')::date::text,'items',jsonb_build_array(jsonb_build_object('name','leite integral','quantity_g',206,'kcal',126.12,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5,'nutrition_source','product_label')),'totals',jsonb_build_object('kcal',126.1,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5));
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(rid,a,'confirmed',p,ts+interval '1 day');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 c:=public.capture_mobile_registration_feedback_v2(a,rid)->'context';
 f:=jsonb_build_object('schema','registration.feedback.v2','registration_id',rid,'local_date',p->'source_local_date','locale','pt-BR','assistant','Flow AI',
  'registration',jsonb_build_object('kind','meal','meal_kind','cafe','totals',p->'totals','items',jsonb_build_array(jsonb_build_object('log_id',mid,'food_name','leite integral','quantity_g',206,'quantity',jsonb_build_object('value',200,'unit','mL','estimated',true,'reference_id','fao-infoods-v2-whole-milk-tb'),'nutrition_source','product_label','kcal',126.12,'protein_g',6.3,'carbs_g',9.5,'fat_g',6.5))),
  'day',NULL,'block',jsonb_build_object('status','unavailable'),'guidance','unavailable','education',jsonb_build_object('status','unavailable'));
 INSERT INTO store_context VALUES(c,f);
END $test$;

DO $test$
DECLARE a uuid:='c2b00000-0000-4000-8000-000000000001';b uuid:='c2b00000-0000-4000-8000-000000000009';rid uuid:='c2b00000-0000-4000-8000-000000000003';rid2 uuid:='c2b00000-0000-4000-8000-000000000007';sid uuid:='c2b00000-0000-4000-8000-000000000004';mid uuid:='c2b00000-0000-4000-8000-000000000005';
 c jsonb;f jsonb;x jsonb;before_all jsonb;old_cursor jsonb;legacy jsonb;steps jsonb;code text;source jsonb;k text;
BEGIN
 SELECT store_context.c,store_context.f INTO c,f FROM store_context;
 INSERT INTO public.users(id,email,status,timezone) VALUES(b,'v2-store-b@example.invalid','active','UTC');
 PERFORM pg_temp.store_ok(public.read_mobile_registration_feedback_v2(a,rid)='{"action":"absent"}'::jsonb,'no receipt before commit');
 x:=pg_temp.service_commit(b,rid,c,f);PERFORM pg_temp.store_ok(x='{"action":"event_conflict"}'::jsonb,'foreign commit denied');
 PERFORM pg_temp.store_ok(public.read_mobile_registration_feedback_v2(b,rid)='{"action":"absent"}'::jsonb,'foreign read reveals no payload');
 FOR k IN SELECT unnest(ARRAY['snapshot','clinical','progress','logs']) LOOP
  source:=CASE WHEN k='snapshot' THEN jsonb_set(c,'{snapshot,calories_consumed}','999'::jsonb)
   WHEN k='clinical' THEN jsonb_set(c,'{clinical,epoch}',to_jsonb(b))
   WHEN k='progress' THEN jsonb_set(c,'{progress}','{"deficit_block":999}'::jsonb)
   ELSE jsonb_set(c,'{logs,0,kcal}','999'::jsonb) END;
  PERFORM pg_temp.store_ok(pg_temp.service_commit(a,rid,source,f)='{"action":"source_conflict"}'::jsonb,'stale private source rejected: '||k);
 END LOOP;
 old_cursor:=public.read_flow_shared_phrase_cursor(a);
 before_all:=pg_temp.v2_owner_state(a);
 BEGIN PERFORM pg_temp.service_commit(a,rid,c,jsonb_set(f,'{registration,items,0,kcal}','999'::jsonb));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 PERFORM pg_temp.store_ok(code='22023' AND before_all=pg_temp.v2_owner_state(a),'malformed prepared facts roll back with no effects');
 CREATE TRIGGER qa_fail_v2_receipt AFTER INSERT ON private.mobile_registration_feedback_v2 FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_v2_insert();
 code:=NULL;
 BEGIN PERFORM pg_temp.service_commit(a,rid,c,f);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 DROP TRIGGER qa_fail_v2_receipt ON private.mobile_registration_feedback_v2;
 PERFORM pg_temp.store_ok(code='P5502' AND before_all=pg_temp.v2_owner_state(a),'post-insert failure rolls back entire receipt');
 source:=public.capture_mobile_registration_feedback_v2(a,rid)->'context';
 PERFORM pg_temp.store_ok(c#>'{clinical,observed_at}'<>source#>'{clinical,observed_at}' AND private.mobile_registration_feedback_v2_source_binding(c)=private.mobile_registration_feedback_v2_source_binding(source),'real second clock capture preserves stable source');
 x:=pg_temp.service_commit(a,rid,c,f);
 PERFORM pg_temp.store_ok(x=jsonb_build_object('action','committed','feedback',f),'service-role first commit returns exact closed receipt');
 PERFORM pg_temp.store_ok((pg_temp.v2_owner_state(a)-'private.mobile_registration_feedback_v2')=(before_all-'private.mobile_registration_feedback_v2'),'first commit changes no domain table or reward');
 PERFORM pg_temp.store_ok((SELECT count(*)=1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'one durable receipt');
 PERFORM pg_temp.store_ok(public.read_flow_shared_phrase_cursor(a)=old_cursor,'v2 never advances shared or legacy phrase state');
 PERFORM pg_temp.store_ok(public.read_mobile_registration_feedback_v2(a,rid)=jsonb_build_object('action','available','feedback',f),'read returns exact receipt');
 PERFORM pg_temp.store_ok(pg_temp.service_commit(a,rid,NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'lost-response retry replays before invalid preparation');
 UPDATE public.daily_snapshots SET calories_consumed=999 WHERE id=sid;
 PERFORM pg_temp.store_ok(pg_temp.service_commit(a,rid,NULL,NULL)=jsonb_build_object('action','replay','feedback',f),'new day facts do not regenerate original receipt');
 PERFORM pg_temp.store_ok((SELECT feedback=f AND source_hash=encode(extensions.digest(convert_to(private.mobile_registration_feedback_v2_source_binding(c)::text,'UTF8'),'sha256'),'hex') FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid),'only source hash and public facts stored');
 UPDATE public.pending_registrations SET proposal=proposal||'{"changed":true}'::jsonb WHERE id=rid;
 PERFORM pg_temp.store_ok(public.read_mobile_registration_feedback_v2(a,rid)='{"action":"event_conflict"}'::jsonb AND pg_temp.service_commit(a,rid,NULL,NULL)='{"action":"event_conflict"}'::jsonb,'changed canonical proposal invalidates read and replay');
 UPDATE public.pending_registrations SET proposal=proposal-'changed' WHERE id=rid;
 x:=public.commit_mobile_registration_feedback(a,rid,NULL,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.store_ok(x='{"action":"event_conflict"}'::jsonb AND public.read_flow_shared_phrase_cursor(a)=old_cursor AND NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback WHERE registration_id=rid),'v2 winner prevents later v1 receipt and phrase draw');

 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(rid2,a,'confirmed','{"kind":"workout"}',now()+interval '1 day');
 steps:=jsonb_build_array(pg_temp.step(a,rid2,'workout',pg_temp.empty_cursor(a),NULL));legacy:=pg_temp.feedback(rid2,'workout',steps);
 x:=public.commit_mobile_registration_feedback(a,rid2,'{"kind":"workout"}','0',NULL,steps,legacy);
 PERFORM pg_temp.store_ok(x=jsonb_build_object('action','committed','feedback',legacy),'actual v1 writer remains functional for a new legacy event');
 old_cursor:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.store_ok(public.read_mobile_registration_feedback_v2(a,rid2)=jsonb_build_object('action','legacy','feedback',legacy),'v1 receipt is returned unchanged as legacy');
 PERFORM pg_temp.store_ok(pg_temp.service_commit(a,rid2,NULL,NULL)=jsonb_build_object('action','legacy','feedback',legacy) AND public.read_flow_shared_phrase_cursor(a)=old_cursor AND NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid2),'v1 winner never upgraded or redrawn by v2');
 DELETE FROM public.pending_registrations WHERE id=rid;
 PERFORM pg_temp.store_ok(NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=rid) AND pg_temp.service_commit(a,rid,c,f)='{"action":"event_conflict"}'::jsonb,'parent deletion cannot resurrect historical receipt');
 FOREACH k IN ARRAY ARRAY['public.read_mobile_registration_feedback_v2(uuid,uuid)','public.commit_mobile_registration_feedback_v2(uuid,uuid,jsonb,jsonb)'] LOOP
  PERFORM pg_temp.store_ok(NOT has_function_privilege('anon',k,'EXECUTE') AND NOT has_function_privilege('authenticated',k,'EXECUTE') AND has_function_privilege('service_role',k,'EXECUTE'),'trusted-only RPC '||k);
 END LOOP;
END $test$;
SELECT count(*) AS store_assertions FROM store_assertions;
ROLLBACK;

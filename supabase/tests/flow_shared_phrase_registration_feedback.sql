-- C5c/C13 on the real local Supabase schema; all fixture writes roll back.
-- Claims/content below test structural SQL fences, not GoTrue sessions or clinical eligibility.
BEGIN;
CREATE TEMP TABLE c5c_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_ok boolean,p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'C5c assertion: %',p_label;END IF;INSERT INTO c5c_assertions VALUES(p_label);END;$$;
DO $$BEGIN
 IF to_regprocedure('public.read_flow_shared_phrase_cursor(uuid)') IS NULL
 OR to_regprocedure('public.commit_mobile_registration_feedback(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'C5c required shared cursor and registration receipt RPCs absent';END IF;
END;$$;
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
CREATE FUNCTION pg_temp.fail_cursor_update() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'forced after receipt' USING ERRCODE='P5501';END;$$;
DO $test$
DECLARE
 a constant uuid:='00000000-0000-0000-0000-00000000c5c1';b constant uuid:='00000000-0000-0000-0000-00000000c5c2';
 meal constant uuid:='00000000-0000-0000-0000-00000000c5c3';workout constant uuid:='00000000-0000-0000-0000-00000000c5c4';
 incoming constant uuid:='00000000-0000-0000-0000-00000000c5c5';pending_id constant uuid:='00000000-0000-0000-0000-00000000c5c6';
 proposal jsonb:=jsonb_build_object('kind','meal','source_local_date','2026-10-24','totals',jsonb_build_object('kcal',435,'protein_g',42,'carbs_g',49,'fat_g',5),'items',jsonb_build_array(jsonb_build_object('name','iogurte natural','kcal',435,'protein_g',42,'carbs_g',49,'fat_g',5)));
 wp jsonb:=jsonb_build_object('kind','workout'); rd jsonb; result jsonb;oldrd jsonb; c jsonb;steps jsonb;fb jsonb;originalfb jsonb;flowstep jsonb;ev text;role_name text;rpc text;bad jsonb;n integer:=0;
 sig constant text:='public.commit_flow_shared_phrase_reply(uuid,text,uuid,text,text,text,text,text,uuid,text,jsonb,jsonb,jsonb,text,timestamptz,jsonb)';
BEGIN
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM public.users WHERE id IN(a,b)),'fixture IDs unused');
 FOREACH rpc IN ARRAY ARRAY['public.read_flow_shared_phrase_cursor(uuid)',sig,'public.read_mobile_registration_feedback(uuid,uuid)','public.commit_mobile_registration_feedback(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb)'] LOOP
  PERFORM pg_temp.ok(NOT has_function_privilege('anon',rpc,'EXECUTE') AND NOT has_function_privilege('authenticated',rpc,'EXECUTE') AND has_function_privilege('service_role',rpc,'EXECUTE'),'RPC ACL '||rpc);
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM pg_temp.ok(NOT has_column_privilege(role_name,'public.users','flow_shared_phrase_cursor','SELECT') AND NOT has_column_privilege(role_name,'public.users','flow_shared_phrase_revision','UPDATE') AND NOT has_table_privilege(role_name,'private.mobile_registration_feedback','SELECT'),'effective private ACL '||role_name);
 END LOOP;
 PERFORM pg_temp.ok(NOT has_table_privilege('service_role','private.mobile_registration_feedback','INSERT'),'service has no direct receipt writer');
 INSERT INTO public.users(id,email,status) VALUES(a,'c5c-a@example.invalid','active'),(b,'c5c-b@example.invalid','active');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 rd:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.ok(rd->>'mode'='legacy' AND rd->>'cursor_revision'='0' AND rd->>'legacy_cursor_revision'='0' AND rd->'cursor'='null'::jsonb,'empty shared read has validated legacy zero');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(meal,a,'confirmed',proposal,now()+interval '1 day'),(workout,a,'confirmed',wp,now()+interval '1 day'),(pending_id,a,'pending',wp,now()+interval '1 day');
 result:=public.commit_mobile_registration_feedback(b,meal,NULL,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.ok(result->>'action'='event_conflict','foreign owner rejected');
 result:=public.commit_mobile_registration_feedback(a,pending_id,NULL,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.ok(result->>'action'='event_conflict','pending is not confirmed feedback');
 result:=public.commit_mobile_registration_feedback(a,meal,wp,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.ok(result->>'action'='event_conflict','proposal mismatch rejected');
 c:=pg_temp.empty_cursor(a);steps:=jsonb_build_array(pg_temp.step(a,meal,'food',c,'Synthetic food education.'));
 c:=steps#>'{0,nextCursor}';steps:=steps||jsonb_build_array(pg_temp.step(a,meal,'incentive',c,'Consistência vale mais do que perfeição.'));fb:=pg_temp.feedback(meal,'meal',steps);
 -- A malformed public DTO cannot seal a durable receipt or consume a draw.
 FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  jsonb_set(fb,'{lines}','[{"key":"day_unavailable","text":"bad","extra":"private"}]'::jsonb),
  jsonb_set(fb,'{day}','{"private_pending":"sentinel"}'::jsonb),
  jsonb_set(fb,'{meal_totals,kcal}','436'::jsonb),
  jsonb_set(fb,'{lines}','[]'::jsonb),
  jsonb_set(fb,'{meal_totals}',(fb->'meal_totals')||'{"extra":1}'::jsonb),
  fb||'{"extra":"not public"}'::jsonb)) LOOP
  n:=n+1;
  BEGIN PERFORM public.commit_mobile_registration_feedback(a,meal,proposal,'0',NULL,steps,bad);RAISE EXCEPTION 'malformed DTO accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  PERFORM pg_temp.ok(public.read_flow_shared_phrase_cursor(a)=rd AND public.read_mobile_registration_feedback(a,meal)->>'action'='absent','malformed DTO is atomic '||n);
 END LOOP;
 result:=public.commit_mobile_registration_feedback(a,meal,proposal,'0',NULL,steps,fb);
 PERFORM pg_temp.ok(result->>'action'='committed' AND result->'feedback'=fb,'C13 first event commits both selections');originalfb:=fb;
 rd:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.ok(rd->>'mode'='shared' AND rd->>'cursor_revision'='1' AND rd->>'legacy_cursor_revision'='0' AND rd->'anchor_assistant_id'='null'::jsonb AND rd#>>'{cursor,ordinal}'='2','C13 first has common positive without fake Flow anchor');
 PERFORM pg_temp.ok((SELECT count(*) FROM public.messages WHERE user_id=a)=0,'registration feedback creates no chat turn');
 result:=public.commit_mobile_registration_feedback(a,meal,NULL,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.ok(result->>'action'='replay' AND result->'feedback'=fb AND public.read_flow_shared_phrase_cursor(a)=rd,'replay before current publication inputs');
 PERFORM pg_temp.ok(public.read_mobile_registration_feedback(a,meal)->'feedback'=fb AND public.read_mobile_registration_feedback(b,meal)->>'action'='absent','read projection owner isolated');
 UPDATE public.pending_registrations p SET proposal=p.proposal||'{"source_sentinel":true}'::jsonb WHERE id=meal;
 PERFORM pg_temp.ok(public.read_mobile_registration_feedback(a,meal)->>'action'='event_conflict','stored receipt refuses changed confirmed proposal');
 UPDATE public.pending_registrations p SET proposal=p.proposal-'source_sentinel' WHERE id=meal;

 c:=rd->'cursor';steps:=jsonb_build_array(pg_temp.step(a,workout,'workout',c,'Next distinct synthetic incentive.'));fb:=pg_temp.feedback(workout,'workout',steps);
 result:=public.commit_mobile_registration_feedback(a,workout,wp,'0',NULL,steps,fb);
 PERFORM pg_temp.ok(result->>'action'='cursor_conflict' AND public.read_flow_shared_phrase_cursor(a)=rd,'stale CAS has no side effects');
 BEGIN
  result:=public.commit_mobile_registration_feedback(a,workout,wp,'1',c,jsonb_set(steps,'{0,nextCursor,ordinal}','4'::jsonb),fb);
  RAISE EXCEPTION 'ordinal skip accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM pg_temp.ok(public.read_flow_shared_phrase_cursor(a)=rd AND public.read_mobile_registration_feedback(a,workout)->>'action'='absent','step ordinal cannot skip');
 BEGIN
  steps:=jsonb_build_array(pg_temp.step(a,workout,'workout',c,c->>'lastTextKey'));
  steps:=jsonb_build_array(pg_temp.step(a,workout,'workout',c,'Consistência vale mais do que perfeição.'));fb:=pg_temp.feedback(workout,'workout',steps);
  PERFORM public.commit_mobile_registration_feedback(a,workout,wp,'1',c,steps,fb);RAISE EXCEPTION 'repeat accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM pg_temp.ok(public.read_flow_shared_phrase_cursor(a)=rd,'immediate previous text rejected');
 steps:=jsonb_build_array(pg_temp.step(a,workout,'workout',c,'Next distinct synthetic incentive.'));fb:=pg_temp.feedback(workout,'workout',steps);
 CREATE TRIGGER qa_c5c_forced_failure AFTER UPDATE OF flow_shared_phrase_revision ON public.users FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_cursor_update();
 BEGIN
  PERFORM public.commit_mobile_registration_feedback(a,workout,wp,'1',c,steps,fb);RAISE EXCEPTION 'forced failure absent';
 EXCEPTION WHEN SQLSTATE 'P5501' THEN NULL;END;
 DROP TRIGGER qa_c5c_forced_failure ON public.users;
 PERFORM pg_temp.ok(public.read_mobile_registration_feedback(a,workout)->>'action'='absent' AND public.read_flow_shared_phrase_cursor(a)=rd,'failure after receipt rolls back receipt and cursor');
 -- Deep day fields must remain the declared public projection.
 bad:=jsonb_set(fb,'{day}','{"local_date":"2026-10-24","current_protocol":"recomposicao","consumed":{"calories_kcal":1785,"protein_g":126,"carbs_g":200,"fat_g":50},"targets":{"calories_kcal":2400,"protein_g":150},"remaining_food_kcal":615,"food_excess_kcal":0,"exercise_kcal":504,"calorie_percentage":74.4,"protein_percentage":84}'::jsonb);
 bad:=jsonb_set(bad,'{lines}','[{"key":"day_calories","text":"74.4%"},{"key":"day_protein","text":"84.0%"}]'::jsonb);
 PERFORM private.assert_registration_feedback_shape(bad,workout,'workout');
 PERFORM pg_temp.ok(true,'well-shaped day accepted by public DTO boundary');
 BEGIN PERFORM public.commit_mobile_registration_feedback(a,workout,wp,'1',c,steps,jsonb_set(bad,'{day,consumed}',(bad#>'{day,consumed}')||'{"source":"private-sentinel"}'::jsonb));RAISE EXCEPTION 'nested day accepted extras';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM pg_temp.ok(public.read_flow_shared_phrase_cursor(a)=rd,'nested day extras do not seal a receipt');
 -- An old caller cannot silently fork the shared cursor. OUT rolls back too.
 ev:='mobile_flow/'||a::text||'/c5c-status-0001';
 INSERT INTO public.messages(id,user_id,direction,role,content_type,content,provider,provider_message_id,raw_payload,delivery_status)
 VALUES(incoming,a,'in','user','text','Status do dia','mobile_flow',ev,jsonb_build_object('request_id','c5c-request-0001','conversation_id','flow','attempt_started_at','2026-10-24T00:00:00.000Z'),'processing');
 flowstep:=pg_temp.step(a,workout,'incentive',c,'A new synthetic Flow incentive.');
 flowstep:=jsonb_set(flowstep,'{receipt,eventKey}',to_jsonb(ev));
 BEGIN
  PERFORM public.commit_flow_phrase_reply(a,ev,incoming,ev,ev||'/assistant','Status do dia','c5c-request-0001','2026-10-24T00:00:00.000Z',NULL,'0',NULL,
   pg_temp.step(a,workout,'incentive',pg_temp.empty_cursor(a),'A new synthetic Flow incentive.')->'nextCursor',flowstep->'receipt','Status'||E'\n\nA new synthetic Flow incentive.',now(),jsonb_build_object('stage','recomposicao','modelUsed','none','promptTokens',0,'completionTokens',0,'costUsd',0,'latencyMs',1));
  RAISE EXCEPTION 'old writer accepted';
 EXCEPTION WHEN serialization_failure OR check_violation THEN NULL;END;
 PERFORM pg_temp.ok((SELECT count(*) FROM public.messages WHERE user_id=a AND direction='out')=0 AND (SELECT delivery_status FROM public.messages WHERE id=incoming)='processing','old writer rolls back OUT and IN');
 result:=public.commit_flow_shared_phrase_reply(a,ev,incoming,ev,ev||'/assistant','Status do dia','c5c-request-0001','2026-10-24T00:00:00.000Z',NULL,'1',c,
  flowstep->'nextCursor',flowstep->'receipt','Status'||E'\n\nA new synthetic Flow incentive.',now(),jsonb_build_object('stage','recomposicao','modelUsed','none','promptTokens',0,'completionTokens',0,'costUsd',0,'latencyMs',1));
 PERFORM pg_temp.ok(result->>'action'='committed','new Flow writer accepts C13 first state');
 rd:=public.read_flow_shared_phrase_cursor(a);oldrd:=rd;
 PERFORM pg_temp.ok(rd->>'cursor_revision'='2' AND rd->>'legacy_cursor_revision'='1' AND rd#>>'{cursor,ordinal}'='3' AND rd->>'anchor_assistant_id'=result#>>'{message,id}','common and chat witnesses independent');
 result:=public.commit_flow_shared_phrase_reply(a,ev,incoming,ev,ev||'/assistant','Status do dia',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.ok(result->>'action'='replay' AND public.read_flow_shared_phrase_cursor(a)=rd,'Flow replay does not advance common cursor');
 c:=rd->'cursor';steps:=jsonb_build_array(pg_temp.step(a,workout,'workout',c,'Next distinct synthetic incentive.'));fb:=pg_temp.feedback(workout,'workout',steps);
 result:=public.commit_mobile_registration_feedback(a,workout,wp,'2',c,steps,fb);
 PERFORM pg_temp.ok(result->>'action'='committed' AND public.read_flow_shared_phrase_cursor(a)->>'cursor_revision'='3' AND public.read_flow_shared_phrase_cursor(a)->>'legacy_cursor_revision'='1','workout feedback continues Flow cursor');
 rd:=public.read_flow_shared_phrase_cursor(a);
 result:=public.commit_mobile_registration_feedback(a,meal,NULL,NULL,NULL,NULL,NULL);
 PERFORM pg_temp.ok(result->'feedback'=originalfb AND public.read_flow_shared_phrase_cursor(a)=rd,'old meal replay after other events stays immutable');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN PERFORM public.read_flow_shared_phrase_cursor(a);RAISE EXCEPTION 'end user reached backend RPC';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 result:=public.reset_user_conversation_atomic(a);
 rd:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.ok(result->>'kept_plans'='true' AND rd->>'mode'='legacy' AND rd->>'cursor_revision'='0' AND (SELECT count(*) FROM private.mobile_registration_feedback WHERE user_id=a)=0,'existing default reset clears receipts and common state');
 -- Empty selections are an event receipt, not two phantom phrase draws.
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(meal,b,'confirmed',proposal,now()+interval '1 day');
 c:=pg_temp.empty_cursor(b);steps:=jsonb_build_array(pg_temp.step(b,meal,'food',c,NULL),pg_temp.step(b,meal,'incentive',c,NULL));fb:=pg_temp.feedback(meal,'meal',steps);
 result:=public.commit_mobile_registration_feedback(b,meal,proposal,'0',NULL,steps,fb);
 PERFORM pg_temp.ok(result->>'action'='committed' AND public.read_flow_shared_phrase_cursor(b)#>>'{cursor,ordinal}'='0','two empty selections do not draw phrases');
 result:=public.reset_user_conversation_atomic(b,false);rd:=public.read_flow_shared_phrase_cursor(b);
 PERFORM pg_temp.ok(result->>'kept_plans'='false' AND rd->>'cursor_revision'='0' AND rd->'cursor'='null'::jsonb,'reset also clears C13-only lane with chat witness zero');
END;$test$;
DO $legacy$
DECLARE
 a constant uuid:='00000000-0000-0000-0000-00000000c5c1';r constant uuid:='00000000-0000-0000-0000-00000000c5c3';
 inside constant uuid:='00000000-0000-0000-0000-00000000c5c5';ev text;step jsonb;rd jsonb;result jsonb;c jsonb;steps jsonb;proposal jsonb;fb jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 ev:='mobile_flow/'||a::text||'/c5c-adoption-0001';
 INSERT INTO public.messages(id,user_id,direction,role,content_type,content,provider,provider_message_id,raw_payload,delivery_status)
 VALUES(inside,a,'in','user','text','Status do dia','mobile_flow',ev,jsonb_build_object('request_id','adoption-request-0001','conversation_id','flow','attempt_started_at','2026-10-24T01:00:00.000Z'),'processing');
 step:=pg_temp.step(a,r,'incentive',pg_temp.empty_cursor(a),'Existing legacy incentive.');step:=jsonb_set(step,'{receipt,eventKey}',to_jsonb(ev));
 result:=public.commit_flow_phrase_reply(a,ev,inside,ev,ev||'/assistant','Status do dia','adoption-request-0001','2026-10-24T01:00:00.000Z',NULL,'0',NULL,
 step->'nextCursor',step->'receipt','Status'||E'\n\nExisting legacy incentive.',now(),jsonb_build_object('stage','recomposicao','modelUsed','none','promptTokens',0,'completionTokens',0,'costUsd',0,'latencyMs',1));
 rd:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.ok(result->>'action'='committed' AND rd->>'mode'='legacy' AND rd->>'cursor_revision'='1' AND rd->'cursor'=step->'nextCursor','validated legacy cursor is imported without reset');
 proposal:=jsonb_build_object('kind','meal','totals',jsonb_build_object('kcal',435,'protein_g',42,'carbs_g',49,'fat_g',5),'items',jsonb_build_array(jsonb_build_object('kcal',435,'protein_g',42,'carbs_g',49,'fat_g',5)));
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(r,a,'confirmed',proposal,now()+interval '1 day');
 steps:=jsonb_build_array(pg_temp.step(a,r,'food',rd->'cursor','Imported cursor food sentence.'));steps:=steps||jsonb_build_array(pg_temp.step(a,r,'incentive',steps#>'{0,nextCursor}','Imported cursor incentive.'));fb:=pg_temp.feedback(r,'meal',steps);
 result:=public.commit_mobile_registration_feedback(a,r,proposal,'1',rd->'cursor',steps,fb);rd:=public.read_flow_shared_phrase_cursor(a);
 PERFORM pg_temp.ok(result->>'action'='committed' AND rd->>'mode'='shared' AND rd->>'cursor_revision'='2' AND rd->>'legacy_cursor_revision'='1' AND rd#>>'{cursor,ordinal}'='3','adoption preserves prior draw plus two food draws');
 PERFORM public.reset_user_conversation_atomic(a);
END;$legacy$;
SELECT 'PASS C5c assertions: '||count(*) FROM c5c_assertions;
ROLLBACK;

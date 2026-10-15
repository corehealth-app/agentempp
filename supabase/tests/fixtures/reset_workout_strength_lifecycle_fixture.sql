-- TEST ONLY. C5 real substrate +13 approved product assets MUST already exist.
-- No product table, fake auth, shadow RPC, migration include, bootstrap or restore.
CREATE SCHEMA c59s14_fixture AUTHORIZATION postgres;
SET LOCAL ROLE postgres;
REVOKE ALL ON SCHEMA c59s14_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE c59s14_fixture.ownership(tag text PRIMARY KEY,owner_name text NOT NULL,object_oids jsonb NOT NULL,object_fingerprint jsonb NOT NULL,sentinel jsonb NOT NULL);
CREATE TABLE c59s14_fixture.cases(case_id text PRIMARY KEY,owner_id uuid UNIQUE NOT NULL,life uuid NOT NULL,payload jsonb NOT NULL);
REVOKE ALL ON TABLE c59s14_fixture.ownership,c59s14_fixture.cases FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s14_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $ok$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S14_ASSERT:%',label;END IF;RAISE NOTICE 'C59S14_PASS:%',label;END $ok$;
CREATE FUNCTION c59s14_fixture.attempt(sql text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $attempt$
DECLARE v jsonb;state text;BEGIN BEGIN EXECUTE sql INTO v;RETURN jsonb_build_object('ok',true,'result',v);
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS state=RETURNED_SQLSTATE;RETURN jsonb_build_object('ok',false,'sqlstate',state);END;END $attempt$;
CREATE FUNCTION c59s14_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $uid$
 SELECT ('c59ae000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $uid$;
CREATE FUNCTION c59s14_fixture.owner(i integer,with_life boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $owner$
DECLARE u uuid:=c59s14_fixture.uid(i);BEGIN
 INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
 VALUES(u,'155514'||lpad(i::text,7,'0'),'c59s14-'||i||'@example.invalid','C59S14 synthetic','UTC','US',true,
 '{"c59s14_fixture":"c59s14_reset_v1","training_reminders":true,"training_delivery_hour":7,"buttons_enabled":true}',19);
 IF with_life THEN INSERT INTO private.workout_strength_lifecycles VALUES(u,c59s14_fixture.uid(i+1000),TIMESTAMPTZ '2026-10-01T00:00:00Z',NULL,NULL);END IF;RETURN u;
END $owner$;
CREATE FUNCTION c59s14_fixture.arguments(u uuid,raw text,key text) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $args$
 SELECT jsonb_build_object('p_user_id',u::text,'p_date','2026-10-12','p_workout_type',raw,'p_duration_min',60,'p_estimated_kcal',300,
 'p_intensity','moderada','p_notes','C59S14 original','p_performed_at','2026-10-12T12:00:00.123456Z','p_provider_message_id',key,
 'p_calories_target',2000,'p_protein_target',150,'p_replace_recent',false,'p_replace_since',NULL) $args$;
CREATE FUNCTION c59s14_fixture.capture(u uuid,l uuid,key text,raw text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $capture$
DECLARE obs jsonb;d jsonb;BEGIN
 obs:=public.get_workout_strength_catalogue_context();
 IF EXISTS(SELECT 1 FROM public.workout_types WHERE is_active AND (slug=raw OR display_name=raw)) THEN RAISE EXCEPTION 'C59S14_SETUP_RAW_MUST_BE_UNRECOGNIZED';END IF;
 d:=jsonb_build_object('status','unrecognized','observationKey',obs->'observationKey','matcherVersion',obs->'matcherVersion','originalOperationType',raw,'reason','no_active_match');
 RETURN public.register_workout_strength_atomic(u,l,key,raw,obs,d);
END $capture$;
CREATE FUNCTION c59s14_fixture.answer(p jsonb,key text DEFAULT NULL) RETURNS jsonb LANGUAGE sql VOLATILE SET search_path=pg_catalog AS $answer$
 SELECT public.answer_confirmed_workout_strength((p->>'ownerID')::uuid,(p->>'lifecycleKey')::uuid,(p->>'workoutLogID')::uuid,
 0,(p->>'questionKey')::uuid,'yes',coalesce(key,p->>'answerKey')) $answer$;
CREATE FUNCTION c59s14_fixture.seed(i integer,answered boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $seed$
DECLARE u uuid:=c59s14_fixture.owner(i);l uuid:=c59s14_fixture.uid(i+1000);key text:='s14-original-'||i;raw text:='C59S14 original '||u;r jsonb;p jsonb;a jsonb;s jsonb;BEGIN
 PERFORM public.read_or_admit_workout_strength_command(u,l,key,raw,c59s14_fixture.arguments(u,raw,key));
 r:=c59s14_fixture.capture(u,l,key,raw);
 IF r#>>'{strength,status}' IS DISTINCT FROM 'committed' OR r#>>'{strength,fact,classification,status}' IS DISTINCT FROM 'unrecognized'
 OR r#>>'{strength,fact,calendar,status}' IS DISTINCT FROM 'proven' OR r#>>'{strength,fact,revision}' IS DISTINCT FROM '0' THEN RAISE EXCEPTION 'C59S14_SETUP_REAL_CAPTURE';END IF;
 p:=jsonb_build_object('ownerID',u::text,'lifecycleKey',l::text,'captureKey',key,'originalType',raw,
 'workoutLogID',r#>'{strength,binding,workoutLogID}','questionKey',r#>'{strength,fact,clarification,questionKey}',
 'answerKey','s14-answer-'||i,'pendingKey','s14-pending-'||i,'pendingRaw','C59S14 pending '||u);
 IF answered THEN a:=c59s14_fixture.answer(p);IF a->>'status' IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION 'C59S14_SETUP_REAL_ANSWER';END IF;p:=p||jsonb_build_object('receipt',a->'receipt');END IF;
 PERFORM public.read_or_admit_workout_strength_command(u,l,p->>'pendingKey',p->>'pendingRaw',c59s14_fixture.arguments(u,p->>'pendingRaw',p->>'pendingKey'));
 s:=public.prepare_workout_strength_calendar_scope(u,l);IF s->>'status' IS DISTINCT FROM 'prepared' THEN RAISE EXCEPTION 'C59S14_SETUP_REAL_SCOPE';END IF;
 RETURN p||jsonb_build_object('scope',s->'scope');
END $seed$;
CREATE FUNCTION c59s14_fixture.enrich(u uuid) RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $enrich$
DECLARE msg uuid;draft uuid;sub uuid;BEGIN
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider) VALUES(u,'in','user','text','C59S14 synthetic','mobile_flow') RETURNING id INTO msg;
 INSERT INTO public.pending_registrations(user_id,proposal,proposal_msg_id,expires_at) VALUES(u,'{"kind":"meal","mealType":"jantar"}',msg,clock_timestamp()+interval '1 hour');
 INSERT INTO public.meal_logs(user_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,meal_type) VALUES(u,'arroz',100,128,2.5,28,0.2,'almoco');
 INSERT INTO public.training_plans(user_id,plan_type,days_per_week,weekly_schedule,generated_by) VALUES(u,'split',2,'[{"day":"seg"}]','flow_draft');
 INSERT INTO public.prescriptions(user_id,type,payload,generated_by) VALUES(u,'diet','{"daily_meals":[]}','patient_import');
 draft:=(public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review','{"weekly_schedule":[{"day":"seg","focus":"a","duration_min":30,"exercises":[]}]}',NULL,NULL,NULL,NULL,msg,NULL,'s14-draft-'||u)->>'id')::uuid;
 INSERT INTO public.user_profiles(user_id,weight_kg,body_fat_percent,onboarding_completed,onboarding_step) VALUES(u,90,20,true,9)
 ON CONFLICT(user_id) DO UPDATE SET weight_kg=90,body_fat_percent=20,onboarding_completed=true,onboarding_step=9;
 INSERT INTO public.user_progress(user_id,xp_total,level,current_streak,deficit_block,current_weight,badges_earned) VALUES(u,500,4,7,3100,89,ARRAY['s14-old'])
 ON CONFLICT(user_id) DO UPDATE SET xp_total=500,level=4,current_streak=7,deficit_block=3100,current_weight=89,badges_earned=ARRAY['s14-old'];
 INSERT INTO public.subscriptions(user_id,provider,provider_subscription_id,plan,status) VALUES(u,'stripe','s14-sub-'||u,'mensal','active') RETURNING id INTO sub;
 INSERT INTO public.subscription_events(subscription_id,user_id,event_type,provider_event_id) VALUES(sub,u,'invoice.payment_succeeded','s14-event-'||u);
 RETURN draft;
END $enrich$;
CREATE FUNCTION c59s14_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $state$
DECLARE t text;rows jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x) FROM ONLY public.users x WHERE id=u));BEGIN
 FOREACH t IN ARRAY ARRAY['pending_registrations','message_dispatch_outbox','message_buffer','tools_audit','llm_evaluations','daily_gap_reminder_attempts','engagement_delivery_attempts','attention_dismissals','user_phrase_cooldown','user_food_corrections','plan_drafts','prescriptions','training_plans','reevaluations','meal_logs','workout_logs','daily_snapshots','messages','product_events','user_profiles','user_progress','subscriptions','subscription_events','private.workout_strength_lifecycles','private.workout_strength_operations','private.workout_strength_facts','private.workout_strength_commands','private.workout_strength_calendar_scopes'] LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM ONLY %s x WHERE user_id=$1',CASE WHEN position('.' in t)>0 THEN t ELSE 'public.'||t END) INTO rows USING u;
 r:=r||jsonb_build_object(t,rows);END LOOP;RETURN r;END $state$;
CREATE FUNCTION c59s14_fixture.deleted_count(s jsonb,keep boolean) RETURNS integer LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $count$
DECLARE t text;n integer:=0;BEGIN FOREACH t IN ARRAY ARRAY['pending_registrations','message_dispatch_outbox','message_buffer','tools_audit','llm_evaluations','daily_gap_reminder_attempts','engagement_delivery_attempts','attention_dismissals','user_phrase_cooldown','user_food_corrections','plan_drafts','prescriptions','training_plans','reevaluations','meal_logs','workout_logs','daily_snapshots','messages','product_events'] LOOP
 IF NOT keep OR t NOT IN('plan_drafts','prescriptions','training_plans') THEN n:=n+jsonb_array_length(s->t);END IF;END LOOP;RETURN n;END $count$;
CREATE FUNCTION c59s14_fixture.delete_owner(u uuid) RETURNS jsonb LANGUAGE sql VOLATILE SET search_path=pg_catalog AS $delete$
 WITH gone AS(DELETE FROM public.users WHERE id=u RETURNING id) SELECT jsonb_build_object('deleted',count(*)=1) FROM gone $delete$;
CREATE FUNCTION c59s14_fixture.fail_after_close() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fault$
BEGIN IF OLD.user_id=c59s14_fixture.uid(107) THEN
 IF NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=OLD.user_id AND closed_at IS NOT NULL)
 OR EXISTS(SELECT 1 FROM public.pending_registrations WHERE user_id=OLD.user_id) THEN RAISE EXCEPTION 'C59S14_FAULT_ORDER_NOT_PROVED' USING ERRCODE='P0002';END IF;
 RAISE EXCEPTION 'C59S14_INJECTED_AFTER_CLOSE_AND_EARLY_DELETE' USING ERRCODE='P0001';END IF;RETURN OLD;END $fault$;
CREATE FUNCTION c59s14_fixture.object_oids() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $oids$
 SELECT jsonb_build_object('schema','c59s14_fixture'::regnamespace::oid::text,
 'relations',(SELECT jsonb_object_agg(n.nspname||'.'||c.relname,c.oid::text) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s14_fixture') AND c.relkind IN('r','p','v','m','S','i','I')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,p.oid::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s14_fixture') AND p.prokind IN('f','p')))
$oids$;
CREATE FUNCTION c59s14_fixture.object_fingerprint() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path=pg_catalog SET DateStyle='ISO, YMD' SET TimeZone='UTC' AS $fingerprint$
 WITH rels AS (SELECT c.* FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','c59s14_fixture') AND c.relkind IN('r','p','v','m','S')),
 funcs AS (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','c59s14_fixture') AND p.prokind IN('f','p'))
 SELECT jsonb_build_object('schemas',(SELECT jsonb_object_agg(nspname,jsonb_build_object('oid',oid::text,'owner',nspowner::text,'acl',nspacl::text)) FROM pg_namespace WHERE nspname IN('public','private','c59s14_fixture')),
 'functions',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'definition_md5',md5(pg_get_functiondef(p.oid)),'comment_md5',md5(obj_description(p.oid,'pg_proc')))) FROM funcs p),
 'relations',(SELECT jsonb_object_agg(r.oid::regclass::text,jsonb_build_object('oid',r.oid::text,'owner',r.relowner::text,'acl',r.relacl::text,'kind',r.relkind,'rls',r.relrowsecurity,'forceRls',r.relforcerowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attcollation::text,md5(pg_get_expr(d.adbin,d.adrelid))) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.oid::text,c.conname,md5(pg_get_constraintdef(c.oid,true))) ORDER BY c.conname),'[]') FROM pg_constraint c WHERE c.conrelid=r.oid),
 'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,md5(pg_get_indexdef(i.indexrelid))) ORDER BY i.indexrelid),'[]') FROM pg_index i WHERE i.indrelid=r.oid),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_array(t.oid::text,t.tgname,t.tgenabled,t.tgisinternal,md5(pg_get_triggerdef(t.oid,true))) ORDER BY t.tgname),'[]') FROM pg_trigger t WHERE t.tgrelid=r.oid),
 'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('oid',p.oid::text,'name',p.polname,'relation',p.polrelid::text,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using_md5',md5(pg_get_expr(p.polqual,p.polrelid)),'check_md5',md5(pg_get_expr(p.polwithcheck,p.polrelid))) ORDER BY p.polname),'[]') FROM pg_policy p WHERE p.polrelid=r.oid))) FROM rels r),
 'sequences',(SELECT coalesce(jsonb_object_agg(c.oid::regclass::text,jsonb_build_object('oid',c.oid::text,'owner',c.relowner::text,'acl',c.relacl::text,'parameters',to_jsonb(s),'lastValue',v.last_value)),'{}') FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_sequences v ON v.schemaname=n.nspname AND v.sequencename=c.relname WHERE n.nspname IN('public','private','c59s14_fixture')))
$fingerprint$;
DO $revoke$DECLARE p record;BEGIN FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='c59s14_fixture'::regnamespace LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',p.oid::regprocedure);END LOOP;END $revoke$;
SET LOCAL ROLE NONE;

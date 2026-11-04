-- Synthetic transaction-owned helpers; caller must roll back every row.
\ir conversation_meal_atomic_writer_fixture.sql
CREATE FUNCTION pg_temp.command_feedback(c jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','registration.feedback.v2','registration_id',c->'registration_id','local_date',c#>'{confirmed,proposal,source_local_date}',
 'locale','pt-BR','assistant','Flow AI','registration',jsonb_build_object('kind','meal','meal_kind','almoco',
 'totals',jsonb_build_object('kcal',130,'protein_g',2.3,'carbs_g',28.2,'fat_g',0.2),
 'items',jsonb_build_array(jsonb_build_object('log_id',c#>'{logs,0,id}','food_name','arroz sintetico','quantity_g',100,
 'quantity',jsonb_build_object('value',100,'unit','g','estimated',false,'reference_id',NULL),
 'nutrition_source','user_kcal','kcal',130.04,'protein_g',2.31,'carbs_g',28.21,'fat_g',0.21))),
 'day',NULL,'block',jsonb_build_object('status','unavailable'),'guidance','unavailable','education',jsonb_build_object('status','unavailable')); $$;
CREATE FUNCTION pg_temp.feedback_seed(u uuid,c uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE source jsonb;prepared jsonb;
BEGIN source:=pg_temp.writer_seed(u,c);prepared:=public.prepare_conversation_meal(u,c,pg_temp.writer_resolved(source));
 RETURN public.commit_conversation_meal(u,c,prepared->>'resolved_hash');END $$;
CREATE FUNCTION pg_temp.feedback_owner_state(owner_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t record;part jsonb;result jsonb;
BEGIN
 SELECT to_jsonb(u) INTO result FROM public.users u WHERE id=owner_id;result:=jsonb_build_object('users',result);
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private') AND c.relkind IN('r','p') AND EXISTS(SELECT 1 FROM pg_attribute a
 WHERE a.attrelid=c.oid AND a.attname='user_id' AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)
 ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM %I.%I x WHERE user_id=$1',t.nspname,t.relname) INTO part USING owner_id;
 result:=result||jsonb_build_object(t.nspname||'.'||t.relname,part);END LOOP;RETURN result;
END $$;
CREATE FUNCTION pg_temp.feedback_fail_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'synthetic feedback rollback' USING ERRCODE='P5510';END $$;
CREATE FUNCTION pg_temp.feedback_service_commit(u uuid,c uuid,v text,f jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x jsonb;BEGIN SET LOCAL ROLE service_role;x:=public.commit_conversation_meal_feedback_v2(u,c,v,f);SET LOCAL ROLE NONE;RETURN x;END $$;
CREATE FUNCTION pg_temp.feedback_empty_cursor(u uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','flow.phrase-state.v1','userId',u::text,'catalogVersion','flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb','ordinal',0,'lastTextKey',NULL,'usedTextKeys',jsonb_build_array());$$;
CREATE FUNCTION pg_temp.feedback_empty_step(u uuid,r uuid,stage text,c jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('receipt',jsonb_build_object('eventKey','mobile_registration/'||u::text||'/'||r::text||'/'||stage,
 'requestFingerprint',repeat('a',64),'selection',jsonb_build_object('phrase',NULL,'phraseId',NULL,'sourceText',NULL,'foodCanonicalName',NULL,'reason','unsupported_language')),'nextCursor',c);$$;
CREATE FUNCTION pg_temp.command_legacy_feedback(r uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','registration.feedback.v1','registration_id',r::text,'kind','meal','locale','en',
 'meal_totals',jsonb_build_object('kcal',130,'protein_g',2.3,'carbs_g',28.2,'fat_g',0.2),'day',NULL,
 'lines',jsonb_build_array(jsonb_build_object('key','meal_totals','text','130 kcal | synthetic original totals'),jsonb_build_object('key','day_unavailable','text','Synthetic day unavailable.')),
 'food_comment',NULL,'incentive',NULL);$$;
CREATE FUNCTION pg_temp.command_seal_legacy(u uuid,r uuid,p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE rd jsonb;c jsonb;steps jsonb;
BEGIN rd:=public.read_flow_shared_phrase_cursor(u);c:=coalesce(nullif(rd->'cursor','null'),pg_temp.feedback_empty_cursor(u));
 steps:=jsonb_build_array(pg_temp.feedback_empty_step(u,r,'food',c),pg_temp.feedback_empty_step(u,r,'incentive',c));
 RETURN public.commit_mobile_registration_feedback(u,r,p,rd->>'cursor_revision',rd->'cursor',steps,pg_temp.command_legacy_feedback(r));END $$;
CREATE FUNCTION pg_temp.feedback_c11_state(owner_id uuid,snapshot_id uuid,anchor_id uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('context',jsonb_build_object('id',u.id,'auth_user_id',u.auth_user_id,'country',u.country,'country_confirmed',u.country_confirmed,'timezone',u.timezone,'status',u.status,'wpp',u.wpp,'updated_at',u.updated_at),'snapshot',to_jsonb(s),
 'items',(SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.meal_logs m WHERE m.user_id=u.id AND m.snapshot_id=s.id AND m.raw_provider_message_id=a.raw_provider_message_id))
 FROM public.users u JOIN public.daily_snapshots s ON s.user_id=u.id JOIN public.meal_logs a ON a.user_id=u.id AND a.snapshot_id=s.id WHERE u.id=$1 AND s.id=$2 AND a.id=$3 $$;

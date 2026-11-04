-- Synthetic helpers only; caller begins/rolls back, no provider is contacted.
\ir conversation_meal_atomic_writer_fixture.sql
CREATE FUNCTION pg_temp.semantic_result(a jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','conversation.meal-interpretation.v1','interpreter_version','conversation.meal-interpreter.v1',
 'owner_id',a->'owner_id','command_id',a->'command_id','attempt_id',a->'attempt_id','input_hash',a->'input_hash','source_hash',a->'source_hash',
 'source_units',jsonb_build_array('command_text'),'decision','reported_meal','reason','explicit_report',
 'sources',jsonb_build_array(jsonb_build_object('unit','command_text','classification','reported','visual_indexes','[]'::jsonb,
 'spans',jsonb_build_array(
 jsonb_build_object('start',0,'end',4,'kind','report','food_index',NULL),jsonb_build_object('start',4,'end',5,'kind','separator','food_index',NULL),
 jsonb_build_object('start',5,'end',8,'kind','quantity','food_index',0),jsonb_build_object('start',8,'end',9,'kind','unit','food_index',0),
 jsonb_build_object('start',9,'end',13,'kind','other','food_index',NULL),jsonb_build_object('start',13,'end',28,'kind','food','food_index',0)))),
 'foods',jsonb_build_array(jsonb_build_object('index',0,'name',jsonb_build_object('unit','command_text','start',13,'end',28),
 'quantity',jsonb_build_object('unit','command_text','start',5,'end',8),'unit',jsonb_build_object('unit','command_text','start',8,'end',9),'visual_index',NULL)),
 'provider_metadata',jsonb_build_object('model','synthetic/no-provider','prompt_tokens',0,'completion_tokens',0,'cost_usd',0.001,'latency_ms',0));$$;
CREATE FUNCTION pg_temp.semantic_owner_state(owner_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t record;part jsonb;result jsonb;
BEGIN
 SELECT to_jsonb(u) INTO result FROM public.users u WHERE id=owner_id;result:=jsonb_build_object('users',result);
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('r','p')
 AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id' AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped) ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]''::jsonb) FROM %I.%I x WHERE user_id=$1',t.nspname,t.relname) INTO part USING owner_id;
 result:=result||jsonb_build_object(t.nspname||'.'||t.relname,part);END LOOP;RETURN result;
END $$;
CREATE FUNCTION pg_temp.semantic_media_seed(u uuid,c uuid,asset uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE input jsonb;
BEGIN
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,context_text,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,processing_result)
 VALUES(asset,u,'meal_photo','meal-photos',u::text||'/'||asset::text||'.jpg','image/jpeg',1200,1200,'processed',NULL,repeat('f',64),repeat('e',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),'{"items":[{"name":"arroz"}]}');
 input:=jsonb_set(pg_temp.writer_input(c),'{source}',jsonb_build_object('channel','media','media_asset_id',asset,'user_action','register_consumed_meal'));
 PERFORM public.admit_conversation_meal_command(u,input);RETURN public.capture_conversation_meal_source(u,c);
END $$;
CREATE FUNCTION pg_temp.semantic_c11_state(owner_id uuid,snapshot_id uuid,anchor_id uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('context',jsonb_build_object('id',u.id,'auth_user_id',u.auth_user_id,'country',u.country,'country_confirmed',u.country_confirmed,'timezone',u.timezone,'status',u.status,'wpp',u.wpp,'updated_at',u.updated_at),'snapshot',to_jsonb(s),
 'items',(SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.meal_logs m WHERE m.user_id=u.id AND m.snapshot_id=s.id AND m.raw_provider_message_id=a.raw_provider_message_id))
 FROM public.users u JOIN public.daily_snapshots s ON s.user_id=u.id JOIN public.meal_logs a ON a.user_id=u.id AND a.snapshot_id=s.id WHERE u.id=$1 AND s.id=$2 AND a.id=$3 $$;
CREATE FUNCTION pg_temp.semantic_reject(u uuid,c uuid,a jsonb,v jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE before_all jsonb;code text;message text;
BEGIN
 before_all:=pg_temp.semantic_owner_state(u);
 BEGIN PERFORM public.commit_conversation_meal_semantic_result(u,c,'conversation.meal-interpreter.v1',(a->>'attempt_id')::uuid,v);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;END;
 IF code IS DISTINCT FROM '22023' OR message IS DISTINCT FROM 'invalid_conversation_semantic_result' OR pg_temp.semantic_owner_state(u) IS DISTINCT FROM before_all THEN
  RAISE NOTICE 'semantic rejected-case % code=% message=% state_equal=%',label,code,message,pg_temp.semantic_owner_state(u)=before_all;
 END IF;
 PERFORM pg_temp.writer_ok(code='22023' AND message='invalid_conversation_semantic_result' AND pg_temp.semantic_owner_state(u)=before_all,label);
END $$;

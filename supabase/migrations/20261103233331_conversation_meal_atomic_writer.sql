-- Dormant trusted-backend resolved meal authority. No routes/callers activated.
BEGIN;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_meal_command_ids') IS NULL
  OR to_regprocedure('private.capture_mobile_registration_feedback_v2(uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'conversation_meal_writer_requires_current_substrate' USING ERRCODE='42501'; END IF;
END $$;

-- A pre-calculation catalog fence covers composite/history lookups too. Epoch
-- changes on actual row-mutating statements and TRUNCATE, including ABA writes.
CREATE TABLE private.conversation_food_catalog_revision (
 singleton boolean PRIMARY KEY CHECK(singleton),revision bigint NOT NULL CHECK(revision>=0),epoch uuid NOT NULL
);
INSERT INTO private.conversation_food_catalog_revision VALUES(true,0,gen_random_uuid());
ALTER TABLE private.conversation_food_catalog_revision ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_food_catalog_revision FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.advance_conversation_food_catalog() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN
 IF TG_OP<>'TRUNCATE' THEN IF NOT EXISTS(SELECT 1 FROM changed_rows) THEN RETURN NULL; END IF; END IF;
 UPDATE private.conversation_food_catalog_revision SET revision=revision+1,epoch=gen_random_uuid() WHERE singleton;
 RETURN NULL;
END $$;
CREATE TRIGGER conversation_food_insert AFTER INSERT ON public.food_db REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_food_update AFTER UPDATE ON public.food_db REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_food_delete AFTER DELETE ON public.food_db REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_food_truncate AFTER TRUNCATE ON public.food_db FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();

CREATE TRIGGER conversation_correction_insert AFTER INSERT ON public.user_food_corrections REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_correction_update AFTER UPDATE ON public.user_food_corrections REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_correction_delete AFTER DELETE ON public.user_food_corrections REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_correction_truncate AFTER TRUNCATE ON public.user_food_corrections FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();

CREATE TRIGGER conversation_config_insert AFTER INSERT ON public.global_config REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_config_update AFTER UPDATE ON public.global_config REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_config_delete AFTER DELETE ON public.global_config REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();
CREATE TRIGGER conversation_config_truncate AFTER TRUNCATE ON public.global_config FOR EACH STATEMENT EXECUTE FUNCTION private.advance_conversation_food_catalog();

CREATE TABLE private.conversation_meal_source_captures (
 user_id uuid NOT NULL,command_id uuid NOT NULL,source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 context jsonb NOT NULL CHECK(jsonb_typeof(context)='object'),captured_at timestamptz NOT NULL CHECK(isfinite(captured_at)),
 PRIMARY KEY(user_id,command_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_command_sources ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_nutrition_sources (
 user_id uuid NOT NULL,command_id uuid NOT NULL,lookup_key text NOT NULL,source_receipt_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN('trusted_recent','exact_median')),
 food_name text,result_hash text NOT NULL CHECK(result_hash ~ '^[a-f0-9]{64}$'),rows jsonb NOT NULL CHECK(jsonb_typeof(rows)='array'),
 PRIMARY KEY(user_id,command_id,lookup_key),UNIQUE(user_id,command_id,source_receipt_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE
);
ALTER TABLE private.conversation_meal_nutrition_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_nutrition_sources FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_conversation_meal_nutrition BEFORE UPDATE ON private.conversation_meal_nutrition_sources FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TABLE private.conversation_meal_resolved (
 user_id uuid NOT NULL,command_id uuid NOT NULL,resolved_hash text NOT NULL CHECK(resolved_hash ~ '^[a-f0-9]{64}$'),
 resolved jsonb NOT NULL CHECK(jsonb_typeof(resolved)='object'),prepared_at timestamptz NOT NULL CHECK(isfinite(prepared_at)),
 PRIMARY KEY(user_id,command_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_effects (
 user_id uuid NOT NULL,command_id uuid NOT NULL,receipt jsonb NOT NULL CHECK(jsonb_typeof(receipt)='object'),
 original_facts jsonb NOT NULL CHECK(jsonb_typeof(original_facts)='object'),feedback_context jsonb,
 committed_at timestamptz NOT NULL CHECK(isfinite(committed_at)),
 PRIMARY KEY(user_id,command_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_resolved ON DELETE CASCADE
);
ALTER TABLE private.conversation_meal_source_captures ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_resolved ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_effects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_source_captures,private.conversation_meal_resolved,private.conversation_meal_effects FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_conversation_meal_source BEFORE UPDATE ON private.conversation_meal_source_captures FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER immutable_conversation_meal_resolved BEFORE UPDATE ON private.conversation_meal_resolved FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER immutable_conversation_meal_effect BEFORE UPDATE ON private.conversation_meal_effects FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();

CREATE FUNCTION private.lock_conversation_meal(p_user uuid,p_command uuid) RETURNS text
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;e uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_command IS NULL THEN RAISE EXCEPTION 'invalid_conversation_meal' USING ERRCODE='22023'; END IF;
 PERFORM private.lock_conversation_command_owner(p_user);
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user FOR UPDATE;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_command FOR UPDATE;
 IF NOT FOUND THEN RETURN 'absent'; END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e THEN RETURN 'stale_epoch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_command) THEN RETURN 'stale_epoch'; END IF;
 RETURN 'current';
END $$;

CREATE FUNCTION private.conversation_meal_source_at(p_user uuid,p_command uuid,p_observed timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;u public.users%ROWTYPE;s public.daily_snapshots%ROWTYPE;
 m public.media_assets%ROWTYPE;input jsonb;clinical jsonb;media jsonb;units jsonb:='[]';evidence jsonb:='{}';
 catalog jsonb;revision bigint;day date;observed timestamptz;caption text;transcript text;
BEGIN
 -- Caller holds the owner/epoch/command lane. Upgrade the user through the
 -- existing clinical authority BEFORE acquiring the date lane: legacy inserts
 -- may hold FK key-share locks while using that unchanged date lane.
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 LOCK TABLE public.food_db IN SHARE MODE NOWAIT;
 LOCK TABLE public.user_food_corrections IN SHARE MODE NOWAIT;
 clinical:=private.capture_mobile_current_clinical_state_at(p_user,'profile',NULL,NULL,p_observed);
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user;
 SELECT * INTO STRICT c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_command;
 SELECT source_input INTO STRICT input FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_command;
 IF NOT u.country_confirmed OR u.country IS NULL THEN RAISE EXCEPTION 'conversation_meal_country_required' USING ERRCODE='55000'; END IF;
 day:=(clinical->>'date')::date;
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user::text||':'||day::text,0)) THEN RAISE EXCEPTION 'conversation_meal_day_busy' USING ERRCODE='55P03'; END IF;
 SELECT * INTO s FROM public.daily_snapshots WHERE user_id=p_user AND date=day FOR UPDATE NOWAIT;
 IF FOUND THEN SELECT r.revision INTO revision FROM private.mobile_flow_plan_day_revisions r WHERE r.snapshot_id=s.id AND r.user_id=p_user; END IF;
 SELECT jsonb_build_object('epoch',r.epoch,'revision',r.revision::text) INTO STRICT catalog FROM private.conversation_food_catalog_revision r WHERE singleton FOR SHARE;
 IF input#>>'{source,channel}'='text' THEN units:=jsonb_build_array('command_text');
 ELSE
  SELECT * INTO m FROM public.media_assets WHERE id=(input#>>'{source,media_asset_id}')::uuid AND user_id=p_user FOR SHARE NOWAIT;
  IF NOT FOUND OR m.status<>'processed' OR m.kind NOT IN('meal_photo','audio_note') OR m.processed_at IS NULL OR m.deleted_at IS NOT NULL THEN
   RAISE EXCEPTION 'conversation_meal_media_changed' USING ERRCODE='40001'; END IF;
  IF octet_length(coalesce(m.processing_result,'null')::text)>1048576 THEN RAISE EXCEPTION 'conversation_meal_media_too_large' USING ERRCODE='54000'; END IF;
  caption:=coalesce(input#>>'{source,caption}',m.context_text);
  IF caption IS NOT NULL AND btrim(caption)<>'' THEN units:=units||jsonb_build_array('media_caption'); END IF;
  IF m.kind='audio_note' THEN
   transcript:=m.processing_result->>'text';
   IF transcript IS NULL OR btrim(transcript)='' THEN RAISE EXCEPTION 'conversation_meal_transcript_missing' USING ERRCODE='55000'; END IF;
   units:=units||jsonb_build_array('media_transcript');
  ELSE
   IF jsonb_typeof(m.processing_result->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(m.processing_result->'items') NOT BETWEEN 1 AND 30 THEN
    RAISE EXCEPTION 'conversation_meal_vision_missing' USING ERRCODE='55000'; END IF;
   units:=units||jsonb_build_array('vision_items');
  END IF;
  media:=jsonb_build_object('asset_id',m.id,'kind',m.kind,'status',m.status,'processed_at',m.processed_at,'updated_at',m.updated_at,
   'processing_result',m.processing_result,'context_text',m.context_text);
  evidence:=jsonb_build_object('caption',caption,'transcript',transcript);
 END IF;
 observed:=coalesce(p_observed,clock_timestamp());
 IF (observed AT TIME ZONE u.timezone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'conversation_meal_clock_changed' USING ERRCODE='40001'; END IF;
 clinical:=private.capture_mobile_current_clinical_state_at(p_user,'profile',NULL,NULL,observed);
 RETURN jsonb_build_object('schema','conversation.meal-source.v1','owner_id',p_user,'command_id',p_command,'input_hash',c.input_hash,
  'epoch',c.epoch,'source_input',input,'source_units',units,'source_evidence',evidence,'media',media,'catalog',catalog,
  'owner',jsonb_build_object('timezone',u.timezone,'locale',u.locale,'country',u.country,'country_confirmed',u.country_confirmed),
  'clinical',clinical-'observed_at'-'context_hash' #- '{safety,observed_at}',
  'day',jsonb_build_object('date',day,'day_closed',coalesce(s.day_closed,false),'calories_target',s.calories_target,'protein_target',s.protein_target,
   'current_protocol',s.current_protocol,'target_revision',coalesce(revision,0)::text,
   'calorie_origin',private.mobile_clinical_target_origin(p_user,(clinical->>'signup_generation')::uuid,c.epoch,day,observed)));
END $$;

CREATE FUNCTION public.capture_conversation_meal_source(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;old private.conversation_meal_source_captures%ROWTYPE;context jsonb;h text;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_command_id);
 IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 SELECT * INTO old FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN RETURN jsonb_build_object('action','replay','source_hash',old.source_hash,'captured_at',old.captured_at,'context',old.context); END IF;
 context:=private.conversation_meal_source_at(p_user_id,p_command_id,NULL);
 IF (context#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb; END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_source_captures VALUES(p_user_id,p_command_id,h,context,clock_timestamp());
 RETURN jsonb_build_object('action','captured','source_hash',h,'captured_at',(SELECT captured_at FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_command_id),'context',context);
END $$;

CREATE FUNCTION private.conversation_meal_keys(v jsonb,keys text[]) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN
 IF v IS NULL OR jsonb_typeof(v) IS DISTINCT FROM 'object' OR NOT(v ?& keys) OR v-keys<>'{}'::jsonb THEN
  RAISE EXCEPTION 'invalid_conversation_resolved_meal' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION private.assert_conversation_resolved_meal(v jsonb,source jsonb,h text) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE item jsonb;proof jsonb:=v->'semantic_proof';annotation jsonb;field text;n numeric;input_count integer;covered integer[];indexes integer[];
BEGIN
 PERFORM private.conversation_meal_keys(v,ARRAY['schema','input_hash','source_hash','meal_type','semantic_proof','items','totals','preparation_annotations','source_receipts']);
 PERFORM private.conversation_meal_keys(proof,ARRAY['schema','decision','input_hash','source_hash','complete_source','source_units','input_count']);
 IF v->>'schema' IS DISTINCT FROM 'conversation.meal-resolved.v1' OR v->>'input_hash' IS DISTINCT FROM source->>'input_hash' OR v->>'source_hash' IS DISTINCT FROM h
  OR v->>'meal_type' IS NULL OR v->>'meal_type' NOT IN('cafe','almoco','lanche','jantar','ceia','outro')
  OR (source#>>'{source_input,meal_type}' IS NOT NULL AND v->>'meal_type' IS DISTINCT FROM source#>>'{source_input,meal_type}')
  OR proof->>'schema' IS DISTINCT FROM 'conversation.meal-semantic.v1' OR proof->>'decision' IS DISTINCT FROM 'consumed_meal'
  OR proof->>'input_hash' IS DISTINCT FROM source->>'input_hash' OR proof->>'source_hash' IS DISTINCT FROM h
  OR proof->'complete_source' IS DISTINCT FROM 'true'::jsonb OR jsonb_typeof(proof->'source_units') IS DISTINCT FROM 'array'
  OR (SELECT jsonb_agg(x ORDER BY x) FROM jsonb_array_elements(proof->'source_units') x) IS DISTINCT FROM (SELECT jsonb_agg(x ORDER BY x) FROM jsonb_array_elements(source->'source_units') x)
  OR jsonb_typeof(proof->'input_count') IS DISTINCT FROM 'number' OR (proof->>'input_count')::numeric NOT BETWEEN 1 AND 30
  OR (proof->>'input_count')::numeric<>trunc((proof->>'input_count')::numeric)
  OR jsonb_typeof(v->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'items') NOT BETWEEN 1 AND 30
  OR jsonb_typeof(v->'preparation_annotations') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'preparation_annotations')>30
  OR octet_length(v::text)>262144 THEN RAISE EXCEPTION 'invalid_conversation_resolved_meal' USING ERRCODE='22023'; END IF;
 input_count:=(proof->>'input_count')::integer;
 FOR item IN SELECT value FROM jsonb_array_elements(v->'items') LOOP
  PERFORM private.conversation_meal_keys(item,ARRAY['name','food_db_id','nutrition_source','quantity_g','kcal','protein_g','carbs_g','fat_g','confidence','input_indexes','quantity_basis','display_qty','display_unit']);
  IF NOT private.conversation_command_text_valid(item->'name',250) OR btrim(item->>'name') IS DISTINCT FROM item->>'name'
   OR item->>'nutrition_source' IS NULL OR item->>'nutrition_source' NOT IN('taco','canonical_exact','canonical_fuzzy','canonical_composite','canonical_composite_partial','rule_based','user_correction','history','user_kcal','product_label','llm_estimate')
   OR item->>'quantity_basis' IS NULL OR item->>'quantity_basis' NOT IN('stated','portion_reference','visual_estimate')
   OR jsonb_typeof(item->'food_db_id') NOT IN('number','null') OR (item->>'food_db_id')::numeric NOT BETWEEN 1 AND 2147483647
   OR (item->>'food_db_id')::numeric<>trunc((item->>'food_db_id')::numeric)
   OR (item->>'nutrition_source' IN('canonical_exact','canonical_fuzzy') AND item->'food_db_id'='null'::jsonb)
   OR (item->'food_db_id'<>'null'::jsonb AND NOT EXISTS(SELECT 1 FROM public.food_db WHERE id=(item->>'food_db_id')::integer))
   OR jsonb_typeof(item->'confidence') NOT IN('number','null') OR (item->>'confidence')::numeric NOT BETWEEN 0 AND 1
   OR jsonb_typeof(item->'display_qty') NOT IN('number','null') OR (item->>'display_qty')::numeric<=0
   OR (item->'display_unit'<>'null'::jsonb AND NOT private.conversation_command_text_valid(item->'display_unit',40))
   OR jsonb_typeof(item->'input_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(item->'input_indexes') NOT BETWEEN 1 AND 30 THEN
   RAISE EXCEPTION 'invalid_conversation_resolved_item' USING ERRCODE='22023'; END IF;
  IF item->>'nutrition_source'='history' AND (item->'food_db_id'='null'::jsonb OR NOT EXISTS(SELECT 1 FROM private.conversation_meal_nutrition_sources n CROSS JOIN LATERAL jsonb_array_elements(n.rows) x WHERE n.user_id=(source->>'owner_id')::uuid AND n.command_id=(source->>'command_id')::uuid AND (x->>'food_db_id')::integer=(item->>'food_db_id')::integer)) THEN RAISE EXCEPTION 'conversation_history_source_required' USING ERRCODE='22023'; END IF;
  FOR field IN SELECT unnest(ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g']) LOOP
   IF jsonb_typeof(item->field) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_conversation_resolved_item' USING ERRCODE='22023'; END IF;
   n:=(item->>field)::numeric;
   IF n<0 OR (field='quantity_g' AND n<=0) OR n>(CASE WHEN field='kcal' THEN 99999 ELSE 9999 END) THEN RAISE EXCEPTION 'invalid_conversation_resolved_item' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF (item->>'kcal')::numeric>(item->>'quantity_g')::numeric*9.5+5 OR (item->>'protein_g')::numeric+(item->>'carbs_g')::numeric+(item->>'fat_g')::numeric>(item->>'quantity_g')::numeric*1.1+5 THEN RAISE EXCEPTION 'invalid_conversation_resolved_item' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(item->'input_indexes') x WHERE jsonb_typeof(x) IS DISTINCT FROM 'number' OR x::text::numeric<>trunc(x::text::numeric) OR x::text::numeric NOT BETWEEN 0 AND input_count-1) THEN RAISE EXCEPTION 'invalid_conversation_input_coverage' USING ERRCODE='22023'; END IF;
  SELECT array_agg(DISTINCT x::text::integer ORDER BY x::text::integer) INTO indexes FROM jsonb_array_elements(item->'input_indexes') x;
  IF cardinality(indexes)<>jsonb_array_length(item->'input_indexes') THEN RAISE EXCEPTION 'invalid_conversation_input_coverage' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') x GROUP BY x->>'name' HAVING count(*)>1) THEN RAISE EXCEPTION 'conversation_duplicate_canonical_names' USING ERRCODE='22023'; END IF;
 SELECT array_agg(DISTINCT x::text::integer ORDER BY x::text::integer) INTO covered FROM jsonb_array_elements(v->'items') i CROSS JOIN LATERAL jsonb_array_elements(i->'input_indexes') x;
 IF covered IS DISTINCT FROM ARRAY(SELECT generate_series(0,input_count-1)) THEN RAISE EXCEPTION 'invalid_conversation_input_coverage' USING ERRCODE='22023'; END IF;
 PERFORM private.conversation_meal_keys(v->'totals',ARRAY['kcal','protein_g','carbs_g','fat_g']);
 FOR field IN SELECT unnest(ARRAY['kcal','protein_g','carbs_g','fat_g']) LOOP
  IF jsonb_typeof(v->'totals'->field) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_conversation_totals' USING ERRCODE='22023'; END IF;
  n:=(v->'totals'->>field)::numeric;
  IF n<0 OR n<>round(n,1) OR abs(n-(SELECT sum((x->>field)::numeric) FROM jsonb_array_elements(v->'items') x))>0.050000001 THEN RAISE EXCEPTION 'invalid_conversation_totals' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOR annotation IN SELECT value FROM jsonb_array_elements(v->'preparation_annotations') LOOP
  PERFORM private.conversation_meal_keys(annotation,ARRAY['schema','kind','input_indexes','food_name','policy','reference_id']);
  IF annotation->>'schema' IS DISTINCT FROM 'consumed.preparation.v1' OR annotation->>'kind' IS DISTINCT FROM 'default_cooked'
   OR NOT private.conversation_command_text_valid(annotation->'food_name',250) OR NOT private.conversation_command_text_valid(annotation->'policy',128) OR NOT private.conversation_command_text_valid(annotation->'reference_id',200)
   OR jsonb_typeof(annotation->'input_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(annotation->'input_indexes') NOT BETWEEN 1 AND 30
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') x WHERE x->>'name'=annotation->>'food_name' AND (x->'input_indexes') @> (annotation->'input_indexes')) THEN RAISE EXCEPTION 'invalid_conversation_preparation_annotation' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(annotation->'input_indexes') x WHERE jsonb_typeof(x) IS DISTINCT FROM 'number' OR x::text::numeric<>trunc(x::text::numeric) OR x::text::numeric NOT BETWEEN 0 AND input_count-1) THEN RAISE EXCEPTION 'invalid_conversation_preparation_annotation' USING ERRCODE='22023'; END IF;
  SELECT array_agg(DISTINCT x::text::integer ORDER BY x::text::integer) INTO indexes FROM jsonb_array_elements(annotation->'input_indexes') x;
  IF cardinality(indexes)<>jsonb_array_length(annotation->'input_indexes') THEN RAISE EXCEPTION 'invalid_conversation_preparation_annotation' USING ERRCODE='22023'; END IF;
 END LOOP;
END $$;

CREATE FUNCTION private.conversation_meal_nutrition_rows(p_user uuid,p_kind text,p_food_name text,p_as_of timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user_id',r.user_id,'created_at',r.created_at,'food_name',r.food_name,'food_db_id',r.food_db_id,
  'quantity_g',r.quantity_g,'kcal',r.kcal,'protein_g',r.protein_g,'carbs_g',r.carbs_g,'fat_g',r.fat_g,'source',r.source,
  'food_db',CASE WHEN r.food_db_id IS NULL THEN 'null'::jsonb ELSE jsonb_build_object('is_verified',r.is_verified) END)
  ORDER BY r.created_at DESC,r.id DESC),'[]'::jsonb) INTO result FROM (
  SELECT m.*,f.is_verified FROM public.meal_logs m LEFT JOIN public.food_db f ON f.id=m.food_db_id
  WHERE m.user_id=p_user AND m.source IN('canonical_exact','canonical_fuzzy','user_kcal')
   AND (p_kind<>'trusted_recent' OR m.kcal>0) AND (p_kind<>'exact_median' OR m.food_name ILIKE p_food_name)
   AND m.created_at>=p_as_of-interval '30 days' AND m.created_at<=p_as_of
  ORDER BY m.created_at DESC,m.id DESC LIMIT CASE WHEN p_kind='trusted_recent' THEN 50 ELSE 20 END FOR SHARE OF m NOWAIT
 ) r;
 RETURN result;
END $$;
CREATE FUNCTION public.read_conversation_meal_nutrition_source(p_user_id uuid,p_command_id uuid,p_kind text,p_food_name text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_meal_source_captures%ROWTYPE;n private.conversation_meal_nutrition_sources%ROWTYPE;lookup text;source jsonb;rows jsonb;h text;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_command_id);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 IF p_kind IS NULL OR p_kind NOT IN('trusted_recent','exact_median') OR (p_kind='trusted_recent' AND p_food_name IS NOT NULL)
  OR (p_kind='exact_median' AND NOT private.conversation_command_text_valid(to_jsonb(p_food_name),250)) THEN RAISE EXCEPTION 'invalid_conversation_nutrition_lookup' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=p_user_id AND command_id=p_command_id) THEN RETURN '{"action":"sealed"}'::jsonb; END IF;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"source_required"}'::jsonb; END IF;
 source:=private.conversation_meal_source_at(p_user_id,p_command_id,NULL);
 IF source IS DISTINCT FROM s.context THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 lookup:=encode(sha256(convert_to(jsonb_build_object('kind',p_kind,'food_name',p_food_name)::text,'UTF8')),'hex');
 SELECT * INTO n FROM private.conversation_meal_nutrition_sources WHERE user_id=p_user_id AND command_id=p_command_id AND lookup_key=lookup;
 IF FOUND THEN RETURN jsonb_build_object('action','replay','owner_id',p_user_id,'command_id',p_command_id,'source_receipt_id',n.source_receipt_id,'source_receipt_hash',n.result_hash,'as_of',s.captured_at,'rows',n.rows); END IF;
 IF (SELECT count(*) FROM private.conversation_meal_nutrition_sources WHERE user_id=p_user_id AND command_id=p_command_id)>=64 THEN RAISE EXCEPTION 'conversation_nutrition_lookup_limit' USING ERRCODE='54000'; END IF;
 rows:=private.conversation_meal_nutrition_rows(p_user_id,p_kind,p_food_name,s.captured_at);
 IF octet_length(rows::text)+(SELECT coalesce(sum(octet_length(x.rows::text)),0) FROM private.conversation_meal_nutrition_sources x WHERE user_id=p_user_id AND command_id=p_command_id)>2097152 THEN RAISE EXCEPTION 'conversation_nutrition_source_too_large' USING ERRCODE='54000'; END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(jsonb_build_object('kind',p_kind,'food_name',p_food_name,'as_of',s.captured_at,'rows',rows)),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_nutrition_sources VALUES(p_user_id,p_command_id,lookup,gen_random_uuid(),p_kind,p_food_name,h,rows) RETURNING * INTO n;
 RETURN jsonb_build_object('action','captured','owner_id',p_user_id,'command_id',p_command_id,'source_receipt_id',n.source_receipt_id,'source_receipt_hash',n.result_hash,'as_of',s.captured_at,'rows',n.rows);
END $$;
CREATE FUNCTION private.conversation_meal_nutrition_current(p_user uuid,p_command uuid,p_receipts jsonb) RETURNS boolean
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE n private.conversation_meal_nutrition_sources%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;receipt jsonb;actual jsonb;expected jsonb;
BEGIN
 IF jsonb_typeof(p_receipts) IS DISTINCT FROM 'array' OR jsonb_array_length(p_receipts)>64 THEN RAISE EXCEPTION 'invalid_conversation_source_receipts' USING ERRCODE='22023'; END IF;
 FOR receipt IN SELECT value FROM jsonb_array_elements(p_receipts) LOOP
  PERFORM private.conversation_meal_keys(receipt,ARRAY['id','hash']);
  IF jsonb_typeof(receipt->'id') IS DISTINCT FROM 'string' OR receipt->>'id' !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
   OR jsonb_typeof(receipt->'hash') IS DISTINCT FROM 'string' OR receipt->>'hash' !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'invalid_conversation_source_receipts' USING ERRCODE='22023'; END IF;
 END LOOP;
 SELECT coalesce(jsonb_agg(x ORDER BY x->>'id'),'[]'::jsonb) INTO expected FROM jsonb_array_elements(p_receipts) x;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',source_receipt_id,'hash',result_hash) ORDER BY source_receipt_id),'[]'::jsonb) INTO actual FROM private.conversation_meal_nutrition_sources WHERE user_id=p_user AND command_id=p_command;
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'conversation_source_receipts_incomplete' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_command;
 FOR n IN SELECT * FROM private.conversation_meal_nutrition_sources WHERE user_id=p_user AND command_id=p_command ORDER BY lookup_key LOOP
  IF private.conversation_meal_nutrition_rows(p_user,n.kind,n.food_name,s.captured_at) IS DISTINCT FROM n.rows THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $$;

CREATE FUNCTION public.prepare_conversation_meal(p_user_id uuid,p_command_id uuid,p_resolved jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_meal_source_captures%ROWTYPE;r private.conversation_meal_resolved%ROWTYPE;fresh jsonb;h text;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_command_id);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 SELECT * INTO r FROM private.conversation_meal_resolved WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN
  IF p_resolved IS DISTINCT FROM r.resolved THEN RETURN '{"action":"resolved_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('action','replay','resolved_hash',r.resolved_hash);
 END IF;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"source_required"}'::jsonb; END IF;
 fresh:=private.conversation_meal_source_at(p_user_id,p_command_id,NULL);
 IF fresh IS DISTINCT FROM s.context THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 IF (fresh#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb; END IF;
 PERFORM private.assert_conversation_resolved_meal(p_resolved,s.context,s.source_hash);
 IF NOT private.conversation_meal_nutrition_current(p_user_id,p_command_id,p_resolved->'source_receipts') THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_resolved),'UTF8')),'hex');
 INSERT INTO private.conversation_meal_resolved VALUES(p_user_id,p_command_id,h,p_resolved,clock_timestamp());
 RETURN jsonb_build_object('action','prepared','resolved_hash',h);
END $$;

CREATE FUNCTION private.commit_conversation_meal_at(p_user uuid,p_command uuid,p_hash text,p_observed timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_meal_source_captures%ROWTYPE;r private.conversation_meal_resolved%ROWTYPE;e private.conversation_meal_effects%ROWTYPE;
 fresh jsonb;clock timestamptz;day date;zone text;registration uuid:=gen_random_uuid();provider text;
 proposal jsonb;atomic_items jsonb;registered jsonb;logs jsonb;log_ids jsonb;snapshot jsonb;original jsonb;feedback jsonb;receipt jsonb;effect_hash text;item jsonb;matched jsonb;used text[]:='{}';
BEGIN
 gate:=private.lock_conversation_meal(p_user,p_command);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
 SELECT * INTO e FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_command;
 IF FOUND THEN RETURN jsonb_build_object('action','replay','receipt',e.receipt); END IF;
 IF p_hash IS NULL OR NOT(p_hash COLLATE "C" ~ '^[a-f0-9]{64}$') THEN RAISE EXCEPTION 'invalid_conversation_resolved_hash' USING ERRCODE='22023'; END IF;
 SELECT * INTO r FROM private.conversation_meal_resolved WHERE user_id=p_user AND command_id=p_command;
 IF NOT FOUND THEN RETURN '{"action":"resolved_required"}'::jsonb; END IF;
 IF r.resolved_hash IS DISTINCT FROM p_hash THEN RETURN '{"action":"resolved_conflict"}'::jsonb; END IF;
 SELECT * INTO STRICT s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_command;
 fresh:=private.conversation_meal_source_at(p_user,p_command,p_observed);
 IF fresh IS DISTINCT FROM s.context THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 IF (fresh#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb; END IF;
 IF NOT private.conversation_meal_nutrition_current(p_user,p_command,r.resolved->'source_receipts') THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 clock:=coalesce(p_observed,clock_timestamp());zone:=fresh#>>'{owner,timezone}';day:=(fresh#>>'{day,date}')::date;
 IF (clock AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 -- Unique provider group makes identical meals with different UUIDs additive.
 provider:='conversation.meal/'||p_user::text||'/'||p_command::text;
 IF EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=p_user AND raw_provider_message_id=provider) THEN RAISE EXCEPTION 'conversation_unjournaled_domain_effect' USING ERRCODE='40001'; END IF;
 SELECT jsonb_agg(jsonb_build_object('name',x->'name','food_db_id',x->'food_db_id','nutrition_source',x->'nutrition_source','quantity_g',x->'quantity_g',
  'kcal',x->'kcal','protein_g',x->'protein_g','carbs_g',x->'carbs_g','fat_g',x->'fat_g','display_qty',x->'display_qty','display_unit',x->'display_unit','quantity_basis',x->'quantity_basis') ORDER BY n),
  jsonb_agg(jsonb_build_object('food_name',x->'name','food_db_id',x->'food_db_id','source',x->'nutrition_source','quantity_g',x->'quantity_g',
  'kcal',x->'kcal','protein_g',x->'protein_g','carbs_g',x->'carbs_g','fat_g',x->'fat_g','confidence',x->'confidence') ORDER BY n)
 INTO proposal,atomic_items FROM jsonb_array_elements(r.resolved->'items') WITH ORDINALITY a(x,n);
 proposal:=jsonb_build_object('kind','meal','mealType',r.resolved->'meal_type','registration_origin','mobile_app','items',proposal,'totals',r.resolved->'totals',
  'source_provider_message_id',provider,'source_timestamp',to_char(clock AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'source_timezone',zone,'source_local_date',day,
  'replace',false,'express_eligible',false,'command_protocol','conversation.command.v1','command_id',p_command,
  'preparation_annotations',r.resolved->'preparation_annotations');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,created_at,expires_at,resolved_at) VALUES(registration,p_user,'confirmed',proposal,clock,clock,clock);
 registered:=public.register_meal_atomic(p_user,day,(r.resolved->>'meal_type')::public.meal_type_enum,atomic_items,false,NULL,clock,provider,
  (fresh#>>'{day,calories_target}')::integer,(fresh#>>'{day,protein_target}')::numeric);
 IF (registered->>'inserted_count')::integer IS DISTINCT FROM jsonb_array_length(atomic_items) OR (registered->>'replaced_count')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'conversation_meal_partial_domain_effect' USING ERRCODE='40001'; END IF;
 -- Pin the new command group's creation clock too; transaction-start now()
 -- must not let a later append enter an earlier frozen history window.
 UPDATE public.meal_logs SET created_at=clock WHERE user_id=p_user AND raw_provider_message_id=provider;
 SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id),jsonb_agg(to_jsonb(m.id) ORDER BY m.id) INTO logs,log_ids FROM public.meal_logs m WHERE user_id=p_user AND raw_provider_message_id=provider;
 IF jsonb_array_length(logs) IS DISTINCT FROM jsonb_array_length(atomic_items) THEN RAISE EXCEPTION 'conversation_meal_group_changed' USING ERRCODE='40001'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(atomic_items) LOOP
  SELECT x INTO matched FROM jsonb_array_elements(logs) x WHERE NOT(x->>'id'=ANY(used)) AND x->>'food_name'=item->>'food_name'
   AND x->'food_db_id'=item->'food_db_id' AND x->>'source'=item->>'source' AND x->'quantity_g'=to_jsonb(round((item->>'quantity_g')::numeric,2))
   AND x->'kcal'=to_jsonb(round((item->>'kcal')::numeric,2)) AND x->'protein_g'=to_jsonb(round((item->>'protein_g')::numeric,2))
   AND x->'carbs_g'=to_jsonb(round((item->>'carbs_g')::numeric,2)) AND x->'fat_g'=to_jsonb(round((item->>'fat_g')::numeric,2))
   AND x->'confidence'=coalesce(to_jsonb(round((item->>'confidence')::numeric,2)),'null')
   AND (x->>'consumed_at')::timestamptz=clock AND x->>'meal_type'=r.resolved->>'meal_type'
   AND (x->>'snapshot_id')::uuid=(registered->>'snapshot_id')::uuid;
  IF matched IS NULL THEN RAISE EXCEPTION 'conversation_meal_saved_facts_changed' USING ERRCODE='40001'; END IF;
  used:=array_append(used,matched->>'id');
 END LOOP;
 SELECT to_jsonb(d) INTO STRICT snapshot FROM public.daily_snapshots d WHERE id=(registered->>'snapshot_id')::uuid AND user_id=p_user AND date=day;
 IF snapshot->'calories_target' IS DISTINCT FROM fresh#>'{day,calories_target}' OR snapshot->'protein_target' IS DISTINCT FROM fresh#>'{day,protein_target}' THEN RAISE EXCEPTION 'conversation_meal_official_targets_changed' USING ERRCODE='40001'; END IF;
 original:=jsonb_build_object('confirmed',jsonb_build_object('id',registration,'user_id',p_user,'status','confirmed','proposal',proposal),'logs',logs,'snapshot',snapshot);
 effect_hash:=encode(sha256(convert_to(private.conversation_command_canonical(original),'UTF8')),'hex');
 receipt:=jsonb_build_object('schema','conversation.meal-effect.v1','owner_id',p_user,'command_id',p_command,'input_hash',fresh->'input_hash',
  'registration_id',registration,'provider_key',provider,'meal_type',r.resolved->'meal_type','local_date',day,'timezone',zone,
  'consumed_at',proposal->'source_timestamp','log_ids',log_ids,'effect_version','cmeal1:'||effect_hash);
 -- Optional enrichment cannot turn an already valid factual write into a
 -- retryable domain error. Never recapture this original source on later retry.
 BEGIN feedback:=private.capture_mobile_registration_feedback_v2(p_user,registration);
  IF feedback IS NOT NULL AND (feedback->'confirmed' IS DISTINCT FROM original->'confirmed' OR feedback->'logs' IS DISTINCT FROM logs OR feedback->'snapshot' IS DISTINCT FROM snapshot) THEN feedback:=NULL; END IF;
 EXCEPTION WHEN OTHERS THEN feedback:=NULL; END;
 IF (coalesce(p_observed,clock_timestamp()) AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'conversation_meal_clock_changed_before_completion' USING ERRCODE='40001'; END IF;
 INSERT INTO private.conversation_meal_effects VALUES(p_user,p_command,receipt,original,feedback,clock);
 RETURN jsonb_build_object('action','committed','receipt',receipt);
END $$;
CREATE FUNCTION public.commit_conversation_meal(p_user_id uuid,p_command_id uuid,p_resolved_hash text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN RETURN private.commit_conversation_meal_at(p_user_id,p_command_id,p_resolved_hash,NULL); END $$;
CREATE FUNCTION public.read_conversation_meal_effect(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_meal_read' USING ERRCODE='22023'; END IF;
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM a.epoch THEN '{"action":"stale_epoch"}'::jsonb
  WHEN e.command_id IS NULL THEN '{"action":"absent"}'::jsonb ELSE jsonb_build_object('action','available','receipt',e.receipt) END INTO result
 FROM private.conversation_meal_command_ids c JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs a ON a.user_id=c.user_id LEFT JOIN private.conversation_meal_effects e ON e.user_id=c.user_id AND e.command_id=c.command_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION private.conversation_meal_nutrition_rows(uuid,text,text,timestamptz),private.conversation_meal_nutrition_current(uuid,uuid,jsonb),public.read_conversation_meal_nutrition_source(uuid,uuid,text,text),private.advance_conversation_food_catalog(),private.lock_conversation_meal(uuid,uuid),private.conversation_meal_source_at(uuid,uuid,timestamptz),
 private.conversation_meal_keys(jsonb,text[]),private.assert_conversation_resolved_meal(jsonb,jsonb,text),private.commit_conversation_meal_at(uuid,uuid,text,timestamptz),
 public.capture_conversation_meal_source(uuid,uuid),public.prepare_conversation_meal(uuid,uuid,jsonb),public.commit_conversation_meal(uuid,uuid,text),public.read_conversation_meal_effect(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_nutrition_source(uuid,uuid,text,text),public.capture_conversation_meal_source(uuid,uuid),public.prepare_conversation_meal(uuid,uuid,jsonb),public.commit_conversation_meal(uuid,uuid,text),public.read_conversation_meal_effect(uuid,uuid) TO service_role;
COMMIT;

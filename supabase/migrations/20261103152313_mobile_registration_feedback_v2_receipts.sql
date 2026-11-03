-- Immutable v2 receipts, source CAS and closed cross-language validation.
-- Dormant service-only API; no business writer, default route or native activation.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_registration_feedback_v2') IS NULL
  OR to_regprocedure('private.capture_mobile_registration_feedback_v2(uuid,uuid)') IS NULL
  OR (SELECT encode(extensions.digest(convert_to(prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc WHERE oid='public.commit_mobile_registration_feedback(uuid,uuid,jsonb,text,jsonb,jsonb,jsonb)'::regprocedure) IS DISTINCT FROM '0dfadd8c62313e3fcc0ec91173680fb289a5ef4b01bd9043c88c59567f538cb3' THEN
  RAISE EXCEPTION 'feedback_v2_receipts_requires_pinned_substrate' USING ERRCODE='42501';
 END IF;
END $preflight$;
CREATE FUNCTION private.mobile_feedback_v2_keys(p jsonb,k text[]) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR NOT(p ?& k) OR p-k<>'{}'::jsonb THEN
  RAISE EXCEPTION 'feedback_v2_object_invalid' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION private.mobile_feedback_v2_text(p jsonb,nullable boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF nullable AND p='null'::jsonb THEN RETURN; END IF;
 IF jsonb_typeof(p) IS DISTINCT FROM 'string' OR btrim(p#>>'{}')='' OR length(p#>>'{}')>240
  OR (p#>>'{}')<>btrim(p#>>'{}') THEN RAISE EXCEPTION 'feedback_v2_text_invalid' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION private.mobile_feedback_v2_normalize(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT lower(btrim(regexp_replace(normalize(p,NFD),U&'[\0300-\036f]','','g')))
$$;
CREATE FUNCTION private.mobile_registration_feedback_v2_policy(c jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE birth date;day date;age integer;height numeric;weight numeric;fat numeric;no_plan boolean;paused boolean;absent boolean;protein boolean;
BEGIN
 -- Input is private captured source, not a client policy. Partial known guards
 -- remain active even if another body field is missing; no rounded BMI cutoff.
 day:=(c->>'date')::date;birth:=(c#>>'{body,birth_date}')::date;
 IF birth IS NOT NULL THEN age:=extract(year FROM day)::integer-extract(year FROM birth)::integer
   -CASE WHEN to_char(day,'MM-DD')<to_char(birth,'MM-DD') THEN 1 ELSE 0 END; END IF;
 height:=(c#>>'{body,height_cm}')::numeric;weight:=(c#>>'{body,weight_kg}')::numeric;fat:=(c#>>'{body,body_fat_percent}')::numeric;
 no_plan:=coalesce(age<18,false) OR EXISTS(SELECT 1 FROM jsonb_array_elements(c#>'{health_state,items}') x WHERE x->>'code'='pregnant_or_breastfeeding');
 paused:=no_plan OR coalesce((c#>>'{health_state,hold_active}')::boolean,false) OR coalesce(fat<=10,false)
  OR coalesce(age>=18 AND weight*10000<18.5*height*height,false);
 absent:=c#>>'{phase_origin,kind}' IN('confirmed_no_plan','not_completed');
 protein:=no_plan OR EXISTS(SELECT 1 FROM jsonb_array_elements(c#>'{health_state,items}') x WHERE x->>'code'='professional_diet');
 RETURN jsonb_build_object('guidance',CASE WHEN paused THEN 'paused' WHEN c->>'assessment'='complete' THEN 'available' ELSE 'unavailable' END,
  'hide',jsonb_build_object('objective',absent OR no_plan,'calories',absent OR no_plan,'protein',absent OR protein,
   'balance',absent OR no_plan,'block',absent OR no_plan,'budget',absent OR no_plan));
END $$;
CREATE FUNCTION private.registration_feedback_v2_expected_education(f jsonb,p_preferences boolean) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE en boolean:=f->>'locale'='en';r jsonb:=f->'registration';id text;body text;t text;energy text;protein text;objective text:=f#>>'{day,current_protocol}';
BEGIN
 IF f->>'guidance'='paused' THEN
  id:='clinical_pause';body:=CASE WHEN en THEN 'Your record remains available. Weight-loss guidance is paused; seek a professional assessment before changing your targets.' ELSE 'Seu registro continua disponível. As orientações de perda de peso estão pausadas; procure avaliação profissional antes de alterar suas metas.' END;
 ELSIF r->>'kind'='workout' THEN
  t:=private.mobile_feedback_v2_normalize(r->>'workout_type');
  IF t IN('caminhada','walking','walk') THEN
   id:='activity_walking';body:=CASE WHEN en THEN 'Walking contributes to an active routine. Its value goes beyond estimated calories; it is a different stimulus from muscle-strengthening exercise.' ELSE 'A caminhada contribui para uma rotina ativa. Seu valor vai além das calorias estimadas; é um estímulo diferente dos exercícios de fortalecimento muscular.' END;
  ELSIF t IN('musculacao','treino de forca','strength training','resistance training') THEN
   id:='activity_strength';body:=CASE WHEN en THEN 'This strength session records a muscle-strengthening stimulus. Energy expenditure alone does not describe the session; sets, repetitions and load help track its execution.' ELSE 'Este treino de força registra um estímulo de fortalecimento muscular. O gasto energético sozinho não descreve a sessão; séries, repetições e carga ajudam a acompanhar sua execução.' END;
  ELSE
   id:='activity_general';body:=CASE WHEN en THEN 'This activity contributes to your movement routine. Estimated expenditure varies with duration and intensity and is not a measurement of muscle gain.' ELSE 'Esta atividade contribui para sua rotina de movimento. O gasto estimado varia com duração e intensidade e não mede ganho de massa muscular.' END;
  END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE private.mobile_feedback_v2_normalize(x->>'food_name') IN('leite','leite integral'))
   AND EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE private.mobile_feedback_v2_normalize(x->>'food_name') IN('whey','whey protein','whey protein em po')) THEN
   id:='milk_whey';body:=CASE WHEN en THEN 'Milk and whey both contribute to the protein shown for this drink. The scoop is an editable reference; checking the label helps account for differences between products.' ELSE 'Leite e whey contribuem juntos para a proteína mostrada nesta bebida. A medida é uma referência editável; conferir o rótulo ajuda a considerar diferenças entre produtos.' END;
  ELSIF (r#>>'{totals,protein_g}')::numeric>0 THEN
   id:='meal_protein';
   SELECT x->>'food_name' INTO energy FROM jsonb_array_elements(r->'items') WITH ORDINALITY AS a(x,n) ORDER BY (x->>'kcal')::numeric DESC,n LIMIT 1;
   SELECT x->>'food_name' INTO protein FROM jsonb_array_elements(r->'items') WITH ORDINALITY AS a(x,n) ORDER BY (x->>'protein_g')::numeric DESC,n LIMIT 1;
   body:=CASE WHEN en THEN 'Among the recorded items, '||energy||' has the largest energy contribution and '||protein||' the largest protein contribution. Changing a portion affects both energy and nutrients; compare the items before deciding what to adjust.' ELSE 'Entre os itens registrados, '||energy||' tem a maior contribuição de energia e '||protein||' a maior contribuição de proteína. Mudar uma porção afeta a energia e os nutrientes; compare os itens antes de decidir o que ajustar.' END;
  ELSIF (r#>>'{totals,kcal}')::numeric>0 THEN
   id:='meal_energy';body:=CASE WHEN en THEN 'The portions determine the energy shown for this meal. Check the individual items to see which contributes most; one record alone does not define the quality of your whole day.' ELSE 'As porções determinam a energia mostrada nesta refeição. Confira os itens para ver qual contribui mais; um registro isolado não define a qualidade de todo o seu dia.' END;
  ELSE
   id:='meal_general';body:=CASE WHEN en THEN 'This record preserves the amounts you provided. If the food or preparation changes, editing the item updates its calculation without recording the meal again.' ELSE 'Este registro preserva as quantidades informadas. Se o alimento ou preparo mudar, editar o item atualiza seu cálculo sem registrar a refeição outra vez.' END;
  END IF;
 END IF;
 IF f->>'guidance'='available' AND objective='ganho_massa' THEN
  body:=body||CASE WHEN en THEN ' For your current goal, follow the whole routine rather than interpreting this event as muscle gain.' ELSE ' No seu objetivo atual, acompanhe o conjunto da rotina sem interpretar este evento como ganho de massa.' END;
 ELSIF f->>'guidance'='available' AND objective='recomposicao' AND f#>>'{block,status}'='available' THEN
  body:=body||CASE WHEN en THEN ' Your long-term block uses consolidated days, not an immediate credit for this record.' ELSE ' Seu bloco de longo prazo usa dias consolidados, sem crédito imediato por este registro.' END;
 END IF;
 IF f->>'guidance'<>'paused' THEN
  body:=body||CASE WHEN p_preferences THEN CASE WHEN en THEN ' Would you like to explore an adjustment that respects the preferences you already shared?' ELSE ' Quer pensar em um ajuste que respeite as preferências que você já informou?' END
  ELSE CASE WHEN en THEN ' Would you like to tell me what you prefer so we can discuss a suitable adjustment?' ELSE ' Quer me contar o que você prefere para conversarmos sobre um ajuste adequado?' END END;
 END IF;
 RETURN jsonb_build_object('status','available','text',body,'provenance',jsonb_build_object('source','reviewed_template',
  'catalog_version','registration.education.v1','template_id',id,'preferences_known',p_preferences));
END $$;
-- Match the existing positive IEEE754 presentation rule exactly. PostgreSQL
-- round(float8) uses ties-to-even; exact numeric rounding can disagree with JS
-- at valid half-step ratios. Do not use floor(x+0.5), which can round the sum.
CREATE FUNCTION private.mobile_feedback_v2_percentage(v numeric,t numeric,scale double precision,divisor double precision) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE x double precision;n double precision;
BEGIN
 IF t IS NULL THEN RETURN 'null'::jsonb; END IF;
 x:=(v::double precision/t::double precision)*scale;n:=floor(x);
 IF x-n>=0.5 THEN n:=n+1; END IF;
 RETURN to_jsonb(n/divisor);
END $$;
CREATE FUNCTION private.assert_registration_feedback_v2_shape(f jsonb,p_id uuid,p_kind text) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE r jsonb;d jsonb;b jsonb;e jsonb;i jsonb;q jsonb;id uuid;day date;seen uuid[]:='{}';k text;percent numeric;
BEGIN
 PERFORM private.mobile_feedback_v2_keys(f,ARRAY['schema','registration_id','local_date','locale','assistant','registration','day','block','guidance','education']);
 IF f->>'schema' IS DISTINCT FROM 'registration.feedback.v2' OR f->>'registration_id' IS DISTINCT FROM p_id::text
  OR f->>'assistant' IS DISTINCT FROM 'Flow AI' OR f->>'locale' IS NULL OR f->>'locale' NOT IN('pt-BR','en')
  OR f->>'guidance' IS NULL OR f->>'guidance' NOT IN('available','paused','unavailable') OR pg_column_size(f)>131072
  OR f->>'local_date' IS NULL OR f->>'local_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'feedback_v2_root_invalid' USING ERRCODE='22023'; END IF;
 day:=(f->>'local_date')::date;IF NOT isfinite(day) OR extract(year FROM day) NOT BETWEEN 1 AND 9999 THEN RAISE EXCEPTION 'feedback_v2_date_invalid' USING ERRCODE='22023'; END IF;
 r:=f->'registration';
 IF r->>'kind' IS DISTINCT FROM p_kind OR p_kind IS NULL OR p_kind NOT IN('meal','workout') THEN RAISE EXCEPTION 'feedback_v2_kind_invalid' USING ERRCODE='22023'; END IF;
 IF p_kind='meal' THEN
  PERFORM private.mobile_feedback_v2_keys(r,ARRAY['kind','meal_kind','items','totals']);
  IF r->>'meal_kind' IS NULL OR r->>'meal_kind' NOT IN('cafe','almoco','lanche','jantar','ceia','outro')
   OR jsonb_typeof(r->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(r->'items') NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'feedback_v2_meal_invalid' USING ERRCODE='22023'; END IF;
  PERFORM private.assert_feedback_numeric_fields(r->'totals',ARRAY['kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY[]::text[]);
  FOR i IN SELECT value FROM jsonb_array_elements(r->'items') LOOP
   PERFORM private.mobile_feedback_v2_keys(i,ARRAY['log_id','food_name','quantity_g','quantity','nutrition_source','kcal','protein_g','carbs_g','fat_g']);
   id:=(i->>'log_id')::uuid;
   IF id IS NULL OR id=ANY(seen) OR i->>'nutrition_source' IS NULL OR i->>'nutrition_source' NOT IN('taco','canonical_exact','canonical_fuzzy','canonical_composite','canonical_composite_partial','rule_based','user_correction','history','user_kcal','product_label','pending_approved','llm_estimate') THEN RAISE EXCEPTION 'feedback_v2_item_invalid' USING ERRCODE='22023'; END IF;
   seen:=array_append(seen,id);PERFORM private.mobile_feedback_v2_text(i->'food_name');
   PERFORM private.assert_feedback_numeric_fields(i-ARRAY['log_id','food_name','quantity','nutrition_source'],ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY['quantity_g']);
   IF (i->>'quantity_g')::numeric>9999 THEN RAISE EXCEPTION 'feedback_v2_item_mass_invalid' USING ERRCODE='22023'; END IF;
   q:=i->'quantity';PERFORM private.mobile_feedback_v2_keys(q,ARRAY['value','unit','estimated','reference_id']);
   PERFORM private.assert_feedback_numeric_fields(q-ARRAY['unit','estimated','reference_id'],ARRAY['value'],ARRAY[]::text[],ARRAY['value']);
   PERFORM private.mobile_feedback_v2_text(q->'reference_id',true);
   IF (q->>'value')::numeric>999999 OR q->>'unit' IS NULL OR q->>'unit' NOT IN('g','mL','unit','scoop') OR jsonb_typeof(q->'estimated') IS DISTINCT FROM 'boolean'
    OR (q->>'unit'='g' AND abs((q->>'value')::numeric-(i->>'quantity_g')::numeric)>=0.000001)
    OR (q->'estimated'='true'::jsonb AND q->>'unit'<>'g' AND q->'reference_id'='null'::jsonb) THEN RAISE EXCEPTION 'feedback_v2_quantity_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
 ELSE
  PERFORM private.mobile_feedback_v2_keys(r,ARRAY['kind','log_id','workout_type','duration_min','intensity','estimated_kcal']);
  id:=(r->>'log_id')::uuid;IF id IS NULL THEN RAISE EXCEPTION 'feedback_v2_workout_id_invalid' USING ERRCODE='22023'; END IF;
  PERFORM private.mobile_feedback_v2_text(r->'workout_type');PERFORM private.mobile_feedback_v2_text(r->'intensity',true);
  PERFORM private.assert_feedback_numeric_fields(r-ARRAY['kind','log_id','workout_type','intensity'],ARRAY['duration_min','estimated_kcal'],ARRAY['duration_min','estimated_kcal'],ARRAY['duration_min']);
  IF (r->>'duration_min')::numeric>1440 THEN RAISE EXCEPTION 'feedback_v2_workout_duration_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 d:=f->'day';
 IF d<>'null'::jsonb THEN
  -- Reuse the existing pure closed day shape; never its receipt/cursor writer.
  PERFORM private.assert_registration_feedback_shape(jsonb_build_object('schema','registration.feedback.v1','registration_id',p_id,'kind','workout','locale',f->'locale','meal_totals',NULL,'day',d,'lines',jsonb_build_array(jsonb_build_object('key','day_calories','text','day'),jsonb_build_object('key','day_protein','text','protein')),'food_comment',NULL,'incentive',NULL),p_id,'workout');
  IF d->>'local_date' IS DISTINCT FROM f->>'local_date' THEN RAISE EXCEPTION 'feedback_v2_day_date_invalid' USING ERRCODE='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['calories_kcal','protein_g'] LOOP
   percent:=(private.mobile_feedback_v2_percentage((d#>>ARRAY['consumed',k])::numeric,(d#>>ARRAY['targets',k])::numeric,1000,10)#>>'{}')::numeric;
   IF (d->>(CASE WHEN k='calories_kcal' THEN 'calorie_percentage' ELSE 'protein_percentage' END))::numeric IS DISTINCT FROM percent THEN RAISE EXCEPTION 'feedback_v2_percentage_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF (d#>'{targets,calories_kcal}'='null'::jsonb AND (d->'remaining_food_kcal'<>'null'::jsonb OR d->'food_excess_kcal'<>'null'::jsonb))
   OR ((d->>'remaining_food_kcal')::numeric>0 AND (d->>'food_excess_kcal')::numeric>0)
   OR f->>'guidance'='unavailable' OR (f->>'guidance'='paused' AND (d->'current_protocol'<>'null'::jsonb OR d#>'{targets,calories_kcal}'<>'null'::jsonb OR d#>'{targets,protein_g}'<>'null'::jsonb)) THEN RAISE EXCEPTION 'feedback_v2_day_visibility_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 b:=f->'block';
 IF b->>'status'='available' THEN
  PERFORM private.mobile_feedback_v2_keys(b,ARRAY['status','target_kcal','current_kcal','percentage','completed_blocks','total_credited_kcal']);
  PERFORM private.assert_feedback_numeric_fields(b-'status',ARRAY['target_kcal','current_kcal','percentage','completed_blocks','total_credited_kcal'],ARRAY[]::text[],ARRAY[]::text[]);
  IF d='null'::jsonb OR d->>'current_protocol' IS DISTINCT FROM 'recomposicao' OR f->>'guidance'<>'available'
   OR b->'target_kcal'<>'7700'::jsonb OR (b->>'completed_blocks')::numeric<>trunc((b->>'completed_blocks')::numeric)
   OR b->'percentage' IS DISTINCT FROM private.mobile_feedback_v2_percentage((b->>'current_kcal')::numeric,7700,100,1)
   OR abs((b->>'total_credited_kcal')::numeric-((b->>'completed_blocks')::numeric*7700+(b->>'current_kcal')::numeric))>=0.000001 THEN RAISE EXCEPTION 'feedback_v2_block_invalid' USING ERRCODE='22023'; END IF;
 ELSE
  PERFORM private.mobile_feedback_v2_keys(b,ARRAY['status']);
  IF b->>'status' IS NULL OR b->>'status' NOT IN('unavailable','not_applicable','protected') OR (b->>'status'='not_applicable' AND (d='null'::jsonb OR d->>'current_protocol' IS NULL OR d->>'current_protocol'='recomposicao')) THEN RAISE EXCEPTION 'feedback_v2_block_status_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 e:=f->'education';
 IF e='{"status":"unavailable"}'::jsonb THEN RETURN; END IF;
 IF jsonb_typeof(e#>'{provenance,preferences_known}') IS DISTINCT FROM 'boolean' OR length(e->>'text')>1600
  OR e IS DISTINCT FROM private.registration_feedback_v2_expected_education(f,(e#>>'{provenance,preferences_known}')::boolean) THEN RAISE EXCEPTION 'feedback_v2_education_invalid' USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION private.mobile_feedback_v2_percentage(numeric,numeric,double precision,double precision),private.mobile_feedback_v2_keys(jsonb,text[]),private.mobile_feedback_v2_text(jsonb,boolean),private.mobile_feedback_v2_normalize(text),private.mobile_registration_feedback_v2_policy(jsonb),private.registration_feedback_v2_expected_education(jsonb,boolean),private.assert_registration_feedback_v2_shape(jsonb,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_feedback_v2_quantity(p_name text,p_mass numeric,p_basis text) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE name text:=regexp_replace(private.mobile_feedback_v2_normalize(p_name),'\s+',' ','g');ratio numeric;ref text;unit text;
BEGIN
 CASE
 WHEN name IN('leite','leite integral') THEN ratio:=1.03;ref:='fao-infoods-v2-whole-milk-tb';unit:='mL';
 WHEN name IN('cafe coado','cafe preparado','cafe expresso','cafe espresso') THEN ratio:=1;ref:='fao-infoods-v2-coffee-fndds4-1';unit:='mL';
 WHEN name IN('cha preparado','cha liquido') THEN ratio:=1;ref:='fao-infoods-v2-tea-fndds4-1';unit:='mL';
 WHEN name='agua' THEN ratio:=1;ref:='fao-infoods-v2-water-cg';unit:='mL';
 WHEN name='suco de laranja' THEN ratio:=1.038;ref:='fao-infoods-v2-orange-juice-sw';unit:='mL';
 WHEN name IN('whey','whey protein','whey protein em po') THEN ratio:=30;ref:='app-household-whey-scoop-v1';unit:='scoop';
 WHEN name IN('pao de queijo','paes de queijo','pao de queijo com requeijao') THEN ratio:=30;ref:='app-household-cheese-bread-unit-v1';unit:='unit';
 WHEN name IN('ovo','ovos','ovo de galinha','ovos de galinha') THEN ratio:=50;ref:='app-household-egg-unit-v1';unit:='unit';
 WHEN name IN('pao frances','paes franceses','paozinho') THEN ratio:=50;ref:='app-household-french-bread-unit-v1';unit:='unit';
 WHEN name IN('banana','bananas') THEN ratio:=100;ref:='app-household-banana-unit-v1';unit:='unit';
 WHEN name IN('maca','macas') THEN ratio:=150;ref:='app-household-apple-unit-v1';unit:='unit';
 ELSE RETURN jsonb_build_object('value',p_mass,'unit','g','estimated',coalesce(p_basis IN('portion_reference','visual_estimate'),false),'reference_id',NULL);
 END CASE;
 RETURN jsonb_build_object('value',round(p_mass/ratio,6),'unit',unit,'estimated',true,'reference_id',ref);
END $$;
CREATE FUNCTION private.assert_registration_feedback_v2_sources(f jsonb,c jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE r jsonb:=f->'registration';p jsonb:=c#>'{confirmed,proposal}';i jsonb;original jsonb;saved jsonb;d jsonb:=f->'day';s jsonb:=c->'snapshot';
 b jsonb:=f->'block';progress jsonb:=c->'progress';policy jsonb:=private.mobile_registration_feedback_v2_policy(c->'clinical');n integer:=0;k text;target numeric;hide boolean;objective text;
BEGIN
 PERFORM private.assert_registration_feedback_v2_shape(f,(c->>'registration_id')::uuid,p->>'kind');
 IF c->'version' IS DISTINCT FROM '1'::jsonb OR f->>'local_date' IS DISTINCT FROM p->>'source_local_date'
  OR f->>'guidance' IS DISTINCT FROM policy->>'guidance' THEN RAISE EXCEPTION 'feedback_v2_source_identity_invalid' USING ERRCODE='22023'; END IF;
 IF r->>'kind'='meal' THEN
  IF r->'totals' IS DISTINCT FROM p->'totals' OR r->>'meal_kind' IS DISTINCT FROM p->>'mealType'
   OR jsonb_array_length(r->'items')<>jsonb_array_length(c->'logs') OR jsonb_array_length(r->'items')<>jsonb_array_length(p->'items') THEN RAISE EXCEPTION 'feedback_v2_meal_source_invalid' USING ERRCODE='22023'; END IF;
  FOR i IN SELECT value FROM jsonb_array_elements(r->'items') LOOP
   original:=p->'items'->n;n:=n+1;
   SELECT value INTO saved FROM jsonb_array_elements(c->'logs') WHERE value->>'id'=i->>'log_id';
   IF saved IS NULL OR i->'food_name' IS DISTINCT FROM saved->'food_name' OR i->'food_name' IS DISTINCT FROM original->'name'
    OR i->'nutrition_source' IS DISTINCT FROM saved->'source' OR i->'quantity' IS DISTINCT FROM private.mobile_feedback_v2_quantity(saved->>'food_name',(saved->>'quantity_g')::numeric,original->>'quantity_basis') THEN RAISE EXCEPTION 'feedback_v2_item_source_invalid' USING ERRCODE='22023'; END IF;
   FOREACH k IN ARRAY ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g'] LOOP
    IF i->k IS DISTINCT FROM saved->k THEN RAISE EXCEPTION 'feedback_v2_item_number_invalid' USING ERRCODE='22023'; END IF;
   END LOOP;
  END LOOP;
 ELSE
  IF jsonb_array_length(c->'logs')<>1 THEN RAISE EXCEPTION 'feedback_v2_workout_source_invalid' USING ERRCODE='22023'; END IF;
  saved:=c->'logs'->0;
  IF r->'log_id' IS DISTINCT FROM saved->'id' THEN RAISE EXCEPTION 'feedback_v2_workout_source_invalid' USING ERRCODE='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['workout_type','duration_min','intensity','estimated_kcal'] LOOP
   IF r->k IS DISTINCT FROM saved->k THEN RAISE EXCEPTION 'feedback_v2_workout_number_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
 END IF;
 IF d<>'null'::jsonb THEN
  IF c#>>'{clinical,assessment}' IS DISTINCT FROM 'complete' OR s->>'date' IS DISTINCT FROM f->>'local_date'
   OR c#>>'{clinical,date}' IS DISTINCT FROM f->>'local_date' THEN RAISE EXCEPTION 'feedback_v2_day_source_invalid' USING ERRCODE='22023'; END IF;
  IF d->'consumed' IS DISTINCT FROM jsonb_build_object('calories_kcal',s->'calories_consumed','protein_g',s->'protein_g','carbs_g',s->'carbs_g','fat_g',s->'fat_g')
   OR d->'exercise_kcal' IS DISTINCT FROM s->'exercise_calories' THEN RAISE EXCEPTION 'feedback_v2_day_consumed_invalid' USING ERRCODE='22023'; END IF;
  objective:=CASE WHEN c#>>'{clinical,phase_origin,kind}'='assigned' THEN c#>>'{clinical,phase_origin,phase}' ELSE NULL END;
  IF d->'current_protocol'<>'null'::jsonb AND (policy->>'guidance'='paused' OR (policy#>>'{hide,objective}')::boolean OR d->>'current_protocol' IS DISTINCT FROM objective) THEN RAISE EXCEPTION 'feedback_v2_objective_source_invalid' USING ERRCODE='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['calories_kcal','protein_g'] LOOP
   target:=(d#>>ARRAY['targets',k])::numeric;
   hide:=coalesce((policy#>>ARRAY['hide',CASE WHEN k='calories_kcal' THEN 'calories' ELSE 'protein' END])::boolean,true);
   IF target IS NOT NULL AND (hide OR policy->>'guidance'='paused' OR target IS DISTINCT FROM (s->>(CASE WHEN k='calories_kcal' THEN 'calories_target' ELSE 'protein_target' END))::numeric) THEN RAISE EXCEPTION 'feedback_v2_target_source_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  target:=(d#>>'{targets,calories_kcal}')::numeric;
  IF (d->'remaining_food_kcal'<>'null'::jsonb AND ((policy#>>'{hide,balance}')::boolean OR (d->>'remaining_food_kcal')::numeric IS DISTINCT FROM greatest(0,target-(s->>'calories_consumed')::numeric)))
   OR (d->'food_excess_kcal'<>'null'::jsonb AND ((policy#>>'{hide,balance}')::boolean OR (d->>'food_excess_kcal')::numeric IS DISTINCT FROM greatest(0,(s->>'calories_consumed')::numeric-target))) THEN RAISE EXCEPTION 'feedback_v2_budget_source_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 hide:=c#>>'{clinical,assessment}'='complete' AND (policy->>'guidance'='paused' OR (policy#>>'{hide,block}')::boolean OR (policy#>>'{hide,objective}')::boolean);
 IF (hide AND b->>'status'<>'protected') OR (NOT hide AND b->>'status'='protected') THEN RAISE EXCEPTION 'feedback_v2_block_visibility_invalid' USING ERRCODE='22023'; END IF;
 IF b->>'status'='available' AND (progress='null'::jsonb OR b->'current_kcal' IS DISTINCT FROM progress->'deficit_block'
  OR b->'completed_blocks' IS DISTINCT FROM progress->'blocks_completed') THEN RAISE EXCEPTION 'feedback_v2_block_source_invalid' USING ERRCODE='22023'; END IF;
 -- No stable preference witness is captured yet. Nonempty generated summaries
 -- are not proof that this patient supplied or confirmed a preference.
 IF f#>>'{education,provenance,preferences_known}'='true' THEN RAISE EXCEPTION 'feedback_v2_preferences_unproved' USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION private.mobile_feedback_v2_quantity(text,numeric,text),private.assert_registration_feedback_v2_sources(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_mobile_registration_feedback_v2(p_user_id uuid,p_registration_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p public.pending_registrations%ROWTYPE;r private.mobile_registration_feedback_v2%ROWTYPE;old private.mobile_registration_feedback%ROWTYPE;h text;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'::jsonb; END IF;
 SELECT * INTO p FROM public.pending_registrations WHERE id=p_registration_id AND user_id=p_user_id FOR SHARE NOWAIT;
 IF NOT FOUND OR p.status<>'confirmed' THEN RETURN '{"action":"absent"}'::jsonb; END IF;
 h:=encode(extensions.digest(convert_to(p.proposal::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO r FROM private.mobile_registration_feedback_v2 WHERE registration_id=p_registration_id AND user_id=p_user_id;
 SELECT * INTO old FROM private.mobile_registration_feedback WHERE registration_id=p_registration_id AND user_id=p_user_id;
 IF r.registration_id IS NOT NULL AND old.registration_id IS NOT NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 IF r.registration_id IS NOT NULL THEN
  IF r.proposal_hash IS DISTINCT FROM h THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('action','available','feedback',r.feedback);
 END IF;
 IF old.registration_id IS NOT NULL THEN
  IF old.proposal_hash IS DISTINCT FROM h THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('action','legacy','feedback',old.feedback);
 END IF;
 RETURN '{"action":"absent"}'::jsonb;
END $$;
REVOKE ALL ON FUNCTION public.read_mobile_registration_feedback_v2(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_mobile_registration_feedback_v2(uuid,uuid) TO service_role;
CREATE FUNCTION public.commit_mobile_registration_feedback_v2(p_user_id uuid,p_registration_id uuid,p_expected_context jsonb,p_feedback jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;existing jsonb;binding jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'feedback_v2_requires_read_committed' USING ERRCODE='22023'; END IF;
 IF p_user_id IS NULL OR p_registration_id IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 -- Same order as capture and protected workout writers. Never hold an owner
 -- SHARE lock from a receipt read before waiting for the workouts lane.
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM 1 FROM public.users WHERE id=p_user_id AND status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 existing:=public.read_mobile_registration_feedback_v2(p_user_id,p_registration_id);
 IF existing->>'action'='available' THEN RETURN jsonb_build_object('action','replay','feedback',existing->'feedback'); END IF;
 IF existing->>'action' IN('legacy','event_conflict') THEN RETURN existing; END IF;
 -- Replays above need no current observation, prepared payload or source read.
 c:=private.capture_mobile_registration_feedback_v2(p_user_id,p_registration_id);
 IF c IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 binding:=private.mobile_registration_feedback_v2_source_binding(c);
 IF binding IS DISTINCT FROM private.mobile_registration_feedback_v2_source_binding(p_expected_context) THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 PERFORM private.assert_registration_feedback_v2_sources(p_feedback,c);
 INSERT INTO private.mobile_registration_feedback_v2(registration_id,user_id,proposal_hash,source_hash,feedback)
 VALUES(p_registration_id,p_user_id,encode(extensions.digest(convert_to((c#>'{confirmed,proposal}')::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(binding::text,'UTF8'),'sha256'),'hex'),p_feedback);
 RETURN jsonb_build_object('action','committed','feedback',p_feedback);
END $$;
REVOKE ALL ON FUNCTION public.commit_mobile_registration_feedback_v2(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_mobile_registration_feedback_v2(uuid,uuid,jsonb,jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.commit_mobile_registration_feedback(
 p_user_id uuid,p_registration_id uuid,p_expected_proposal jsonb,p_expected_revision text,
 p_expected_cursor jsonb,p_steps jsonb,p_feedback jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_user public.users%ROWTYPE;v_pending public.pending_registrations%ROWTYPE;v_existing jsonb;
 v_current jsonb;v_cursor jsonb;v_revision bigint;v_kind text;v_prefix text;v_step jsonb;v_index integer:=0;
 v_food jsonb:='null'::jsonb;v_incentive jsonb:='null'::jsonb;v_total jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO v_user FROM public.users WHERE id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 SELECT * INTO v_pending FROM public.pending_registrations WHERE id=p_registration_id AND user_id=p_user_id FOR SHARE;
 IF NOT FOUND OR v_pending.status<>'confirmed' THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 -- First stored version owns this event; an old client cannot advance phrases
 -- after a v2 winner. Registration success itself remains independent.
 IF EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 WHERE registration_id=p_registration_id AND user_id=p_user_id)
 THEN RETURN jsonb_build_object('action','event_conflict'); END IF;
 -- Replay after identity/ownership, before CURRENT cursor, proposal parameters or day.
 v_existing:=public.read_mobile_registration_feedback(p_user_id,p_registration_id);
 IF v_existing->>'action'='available' THEN RETURN jsonb_build_object('action','replay','feedback',v_existing->'feedback');END IF;
 IF v_existing->>'action'='event_conflict' THEN RETURN v_existing;END IF;
 IF v_pending.proposal IS DISTINCT FROM p_expected_proposal THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 v_kind:=v_pending.proposal->>'kind';
 IF v_kind IS NULL OR v_kind NOT IN ('meal','workout') THEN RETURN jsonb_build_object('action','event_conflict');END IF;
 IF p_expected_revision IS NULL OR p_expected_revision !~ '^(0|[1-9][0-9]*)$' OR length(p_expected_revision)>19
 THEN RAISE EXCEPTION 'shared revision invalid' USING ERRCODE='22023';END IF;
 IF p_expected_revision::numeric>9223372036854775807 THEN RAISE EXCEPTION 'shared revision invalid' USING ERRCODE='22023';END IF;
 v_current:=public.read_flow_shared_phrase_cursor(p_user_id);
 IF v_current->>'cursor_revision' IS DISTINCT FROM p_expected_revision
 OR v_current->'cursor' IS DISTINCT FROM coalesce(p_expected_cursor,'null'::jsonb)
 THEN RETURN jsonb_build_object('action','cursor_conflict');END IF;
 v_revision:=(v_current->>'cursor_revision')::bigint;
 IF v_revision=9223372036854775807 THEN RAISE EXCEPTION 'shared revision exhausted' USING ERRCODE='22003';END IF;
 v_cursor:=v_current->'cursor';
 IF v_cursor='null'::jsonb THEN v_cursor:=jsonb_build_object('schema','flow.phrase-state.v1','userId',p_user_id::text,
  'catalogVersion','flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb','ordinal',0,'lastTextKey',NULL,'usedTextKeys',jsonb_build_array());END IF;
 IF jsonb_typeof(p_steps) IS DISTINCT FROM 'array' OR jsonb_array_length(p_steps)<>(CASE WHEN v_kind='meal' THEN 2 ELSE 1 END)
 OR pg_column_size(p_steps)>1048576 THEN RAISE EXCEPTION 'registration phrase steps invalid' USING ERRCODE='22023';END IF;
 v_prefix:='mobile_registration/'||p_user_id::text||'/'||p_registration_id::text;
 FOR v_step IN SELECT value FROM jsonb_array_elements(p_steps) LOOP
  IF v_kind='meal' AND v_index=0 THEN
   v_cursor:=private.assert_registration_phrase_step(p_user_id,v_cursor,v_step,v_prefix||'/food','food');
   v_food:=v_step#>'{receipt,selection,phrase}';
  ELSE
   v_cursor:=private.assert_registration_phrase_step(p_user_id,v_cursor,v_step,v_prefix||'/incentive',CASE WHEN v_kind='meal' THEN 'incentive' ELSE 'workout' END);
   v_incentive:=v_step#>'{receipt,selection,phrase}';
  END IF;
  v_index:=v_index+1;
 END LOOP;
 IF jsonb_typeof(p_feedback) IS DISTINCT FROM 'object'
 OR NOT(p_feedback ?& ARRAY['schema','registration_id','kind','locale','meal_totals','day','lines','food_comment','incentive'])
 OR p_feedback-ARRAY['schema','registration_id','kind','locale','meal_totals','day','lines','food_comment','incentive']<>'{}'::jsonb
 OR p_feedback->>'schema' IS DISTINCT FROM 'registration.feedback.v1'
 OR p_feedback->>'registration_id' IS DISTINCT FROM p_registration_id::text
 OR p_feedback->>'kind' IS DISTINCT FROM v_kind OR p_feedback->>'locale' NOT IN ('pt-BR','en')
 OR jsonb_typeof(p_feedback->'locale') IS DISTINCT FROM 'string'
 OR jsonb_typeof(p_feedback->'lines') IS DISTINCT FROM 'array'
 OR p_feedback->'food_comment' IS DISTINCT FROM v_food OR p_feedback->'incentive' IS DISTINCT FROM v_incentive
 OR pg_column_size(p_feedback)>131072
 THEN RAISE EXCEPTION 'registration feedback invalid' USING ERRCODE='22023';END IF;
 PERFORM private.assert_registration_feedback_shape(p_feedback,p_registration_id,v_kind);
 IF v_kind='meal' THEN
  v_total:=jsonb_build_object('kcal',v_pending.proposal#>'{totals,kcal}',
   'protein_g',v_pending.proposal#>'{totals,protein_g}','carbs_g',v_pending.proposal#>'{totals,carbs_g}',
   'fat_g',v_pending.proposal#>'{totals,fat_g}');
  IF p_feedback->'meal_totals' IS DISTINCT FROM v_total THEN RAISE EXCEPTION 'feedback meal totals differ from confirmed facts' USING ERRCODE='22023';END IF;
 ELSE
  IF p_feedback->'meal_totals' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'workout cannot carry meal totals' USING ERRCODE='22023';END IF;
 END IF;
 IF p_feedback->'day'<>'null'::jsonb AND v_pending.proposal ? 'source_local_date'
 AND p_feedback#>>'{day,local_date}' IS DISTINCT FROM v_pending.proposal->>'source_local_date'
 THEN RAISE EXCEPTION 'feedback day differs from confirmed facts' USING ERRCODE='22023';END IF;
 INSERT INTO private.mobile_registration_feedback(registration_id,user_id,proposal_hash,cursor_revision,feedback,steps)
 VALUES(p_registration_id,p_user_id,encode(extensions.digest(convert_to(v_pending.proposal::text,'UTF8'),'sha256'),'hex'),v_revision+1,p_feedback,p_steps);
 UPDATE public.users SET flow_shared_phrase_revision=v_revision+1,
  flow_shared_phrase_legacy_revision=flow_phrase_cursor_revision,flow_shared_phrase_cursor=v_cursor WHERE id=p_user_id;
 -- No exception handler: receipt and both selections/cursor commit or roll back together.
 RETURN jsonb_build_object('action','committed','feedback',p_feedback);
END;$fn$;

COMMIT;

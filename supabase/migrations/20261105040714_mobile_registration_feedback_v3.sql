-- Additive dormant canonical feedback. No route/capability/native activation.
-- Old receipt JSON/steps/cursors are never rewritten. No clinical/reward writer.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_workout_effects') IS NULL
  OR to_regprocedure('private.assert_registration_feedback_v2_sources(jsonb,jsonb)') IS NULL
  OR to_regclass('private.mobile_registration_feedback_claims') IS NOT NULL
  OR to_regclass('private.mobile_registration_feedback_v3') IS NOT NULL THEN
  RAISE EXCEPTION 'feedback_v3_requires_pinned_substrate' USING ERRCODE='42501';END IF;
END $preflight$;
-- Parent tables first, then old receipt tables, all NOWAIT. Active writers cause
-- a safe migration abort. Backfill inserts NO FKs until after metadata-only
-- copying: it never waits for a user row held by a writer waiting on this DDL.
LOCK TABLE public.users,public.pending_registrations,private.conversation_workout_command_ids IN SHARE ROW EXCLUSIVE MODE NOWAIT;
LOCK TABLE private.mobile_registration_feedback,private.mobile_registration_feedback_v2 IN SHARE ROW EXCLUSIVE MODE NOWAIT;
DO $existing$
BEGIN
 IF EXISTS(SELECT 1 FROM private.mobile_registration_feedback a JOIN private.mobile_registration_feedback_v2 b USING(registration_id))
  OR EXISTS(SELECT 1 FROM private.mobile_registration_feedback r LEFT JOIN public.pending_registrations p ON p.id=r.registration_id WHERE p.id IS NULL OR p.user_id<>r.user_id)
  OR EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 r LEFT JOIN public.pending_registrations p ON p.id=r.registration_id WHERE p.id IS NULL OR p.user_id<>r.user_id)
  OR EXISTS(SELECT 1 FROM private.mobile_registration_feedback_v2 r LEFT JOIN private.conversation_meal_effects e ON e.user_id=r.user_id AND e.command_id=r.command_id
    WHERE r.command_id IS NOT NULL AND (e.command_id IS NULL OR e.receipt->>'registration_id' IS DISTINCT FROM r.registration_id::text))
  OR EXISTS(SELECT 1 FROM private.conversation_meal_effects GROUP BY user_id,receipt->>'registration_id' HAVING count(*)>1) THEN
  RAISE EXCEPTION 'feedback_v3_ambiguous_or_orphan_existing_receipt' USING ERRCODE='23514';END IF;
END $existing$;
CREATE TABLE private.mobile_registration_feedback_claims (
 user_id uuid NOT NULL,origin text NOT NULL CHECK(origin IN('pending_registration','conversation_workout')),
 registration_id uuid NOT NULL,version smallint NOT NULL CHECK(version IN(1,2,3)),
 pending_id uuid,workout_command_id uuid,
 PRIMARY KEY(user_id,origin,registration_id),
 CHECK((origin='pending_registration' AND pending_id IS NOT NULL AND pending_id=registration_id AND workout_command_id IS NULL)
  OR (origin='conversation_workout' AND workout_command_id IS NOT NULL AND workout_command_id=registration_id AND pending_id IS NULL AND version=3))
);
INSERT INTO private.mobile_registration_feedback_claims(user_id,origin,registration_id,version,pending_id)
 SELECT user_id,'pending_registration',registration_id,1,registration_id FROM private.mobile_registration_feedback
 UNION ALL SELECT user_id,'pending_registration',registration_id,2,registration_id FROM private.mobile_registration_feedback_v2;
ALTER TABLE private.mobile_registration_feedback_claims
 ADD FOREIGN KEY(user_id) REFERENCES public.users ON DELETE CASCADE,
 ADD FOREIGN KEY(pending_id) REFERENCES public.pending_registrations ON DELETE CASCADE,
 ADD FOREIGN KEY(user_id,workout_command_id) REFERENCES private.conversation_workout_command_ids ON DELETE CASCADE;
CREATE TABLE private.mobile_registration_feedback_v3 (
 user_id uuid NOT NULL REFERENCES public.users ON DELETE CASCADE,
 origin text NOT NULL CHECK(origin IN('pending_registration','conversation_workout')),
 registration_id uuid NOT NULL,pending_id uuid REFERENCES public.pending_registrations ON DELETE CASCADE,
 workout_command_id uuid,meal_command_id uuid,
 event_hash text COLLATE "C" NOT NULL CHECK(event_hash ~ '^[a-f0-9]{64}$'),
 source_hash text COLLATE "C" NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 feedback jsonb NOT NULL CHECK(jsonb_typeof(feedback)='object' AND feedback->>'schema'='registration.feedback.v3'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(user_id,origin,registration_id),
 FOREIGN KEY(user_id,workout_command_id) REFERENCES private.conversation_workout_effects ON DELETE CASCADE,
 FOREIGN KEY(user_id,meal_command_id) REFERENCES private.conversation_meal_effects ON DELETE CASCADE,
 CHECK((origin='pending_registration' AND pending_id IS NOT NULL AND pending_id=registration_id AND workout_command_id IS NULL)
  OR (origin='conversation_workout' AND workout_command_id IS NOT NULL AND workout_command_id=registration_id AND pending_id IS NULL AND meal_command_id IS NULL))
);
ALTER TABLE private.mobile_registration_feedback_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_registration_feedback_v3 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_registration_feedback_claims,private.mobile_registration_feedback_v3 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.claim_mobile_registration_feedback() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE origin text:='pending_registration';v smallint;claimed uuid;
BEGIN
 -- Existing v1 accepts RR/serializable. The unique index arbitrates even when
 -- that snapshot cannot see a concurrent winner; never rely on SELECT alone.
 IF TG_TABLE_NAME='mobile_registration_feedback' THEN v:=1;
 ELSIF TG_TABLE_NAME='mobile_registration_feedback_v2' THEN v:=2;
 ELSE v:=3;origin:=NEW.origin;END IF;
 PERFORM 1 FROM public.users WHERE id=NEW.user_id FOR NO KEY UPDATE;
 INSERT INTO private.mobile_registration_feedback_claims(user_id,origin,registration_id,version,pending_id,workout_command_id)
 VALUES(NEW.user_id,origin,NEW.registration_id,v,CASE WHEN origin='pending_registration' THEN NEW.registration_id END,CASE WHEN origin='conversation_workout' THEN NEW.registration_id END)
 ON CONFLICT DO NOTHING RETURNING registration_id INTO claimed;
 IF claimed IS NULL THEN RAISE EXCEPTION 'registration_feedback_canonical_conflict' USING ERRCODE='23505';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER canonical_mobile_registration_feedback BEFORE INSERT ON private.mobile_registration_feedback FOR EACH ROW EXECUTE FUNCTION private.claim_mobile_registration_feedback();
CREATE TRIGGER canonical_mobile_registration_feedback_v2 BEFORE INSERT ON private.mobile_registration_feedback_v2 FOR EACH ROW EXECUTE FUNCTION private.claim_mobile_registration_feedback();
CREATE TRIGGER canonical_mobile_registration_feedback_v3 BEFORE INSERT ON private.mobile_registration_feedback_v3 FOR EACH ROW EXECUTE FUNCTION private.claim_mobile_registration_feedback();
CREATE FUNCTION private.guard_mobile_registration_feedback_v3() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)
  OR (OLD.pending_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=OLD.pending_id))
  OR (OLD.workout_command_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_effects WHERE user_id=OLD.user_id AND command_id=OLD.workout_command_id))
  OR (OLD.meal_command_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=OLD.user_id AND command_id=OLD.meal_command_id))) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'immutable_registration_feedback_v3' USING ERRCODE='22023';
END $$;
CREATE TRIGGER immutable_mobile_registration_feedback_v3 BEFORE UPDATE OR DELETE ON private.mobile_registration_feedback_v3 FOR EACH ROW EXECUTE FUNCTION private.guard_mobile_registration_feedback_v3();
CREATE FUNCTION private.guard_mobile_registration_feedback_claim() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)
  OR (OLD.pending_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=OLD.pending_id))
  OR (OLD.workout_command_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=OLD.user_id AND command_id=OLD.workout_command_id))) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'immutable_registration_feedback_claim' USING ERRCODE='22023';
END $$;
CREATE TRIGGER immutable_mobile_registration_feedback_claim BEFORE UPDATE OR DELETE ON private.mobile_registration_feedback_claims FOR EACH ROW EXECUTE FUNCTION private.guard_mobile_registration_feedback_claim();

CREATE FUNCTION private.assert_registration_feedback_v3_shape(f jsonb,p_id uuid,p_kind text) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE r jsonb;d jsonb;b jsonb;e jsonb;i jsonb;q jsonb;id uuid;day date;seen uuid[]:='{}';k text;percent numeric;
BEGIN
 PERFORM private.mobile_feedback_v2_keys(f,ARRAY['schema','registration_id','local_date','locale','assistant','registration','day','block','guidance','education']);
 IF f->>'schema' IS DISTINCT FROM 'registration.feedback.v3' OR f->>'registration_id' IS DISTINCT FROM p_id::text
  OR f->>'assistant' IS DISTINCT FROM 'Flow AI' OR f->>'locale' IS NULL OR f->>'locale' NOT IN('pt-BR','en')
  OR f->>'guidance' IS NULL OR f->>'guidance' NOT IN('available','paused','unavailable') OR pg_column_size(f)>131072
  OR f->>'local_date' IS NULL OR f->>'local_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'feedback_v3_root_invalid' USING ERRCODE='22023'; END IF;
 day:=(f->>'local_date')::date;IF NOT isfinite(day) OR extract(year FROM day) NOT BETWEEN 1 AND 9999 THEN RAISE EXCEPTION 'feedback_v3_date_invalid' USING ERRCODE='22023'; END IF;
 r:=f->'registration';
 IF r->>'kind' IS DISTINCT FROM p_kind OR p_kind IS NULL OR p_kind NOT IN('meal','workout') THEN RAISE EXCEPTION 'feedback_v3_kind_invalid' USING ERRCODE='22023'; END IF;
 IF p_kind='meal' THEN
  PERFORM private.mobile_feedback_v2_keys(r,ARRAY['kind','meal_kind','items','totals']);
  IF r->>'meal_kind' IS NULL OR r->>'meal_kind' NOT IN('cafe','almoco','lanche','jantar','ceia','outro')
   OR jsonb_typeof(r->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(r->'items') NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'feedback_v3_meal_invalid' USING ERRCODE='22023'; END IF;
  PERFORM private.assert_feedback_numeric_fields(r->'totals',ARRAY['kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY[]::text[]);
  FOR i IN SELECT value FROM jsonb_array_elements(r->'items') LOOP
   PERFORM private.mobile_feedback_v2_keys(i,ARRAY['log_id','food_name','quantity_g','quantity','nutrition_source','kcal','protein_g','carbs_g','fat_g']);
   id:=(i->>'log_id')::uuid;
   IF id IS NULL OR id=ANY(seen) OR i->>'nutrition_source' IS NULL OR i->>'nutrition_source' NOT IN('taco','canonical_exact','canonical_fuzzy','canonical_composite','canonical_composite_partial','rule_based','user_correction','history','user_kcal','product_label','pending_approved','llm_estimate') THEN RAISE EXCEPTION 'feedback_v3_item_invalid' USING ERRCODE='22023'; END IF;
   seen:=array_append(seen,id);PERFORM private.mobile_feedback_v2_text(i->'food_name');
   PERFORM private.assert_feedback_numeric_fields(i-ARRAY['log_id','food_name','quantity','nutrition_source'],ARRAY['quantity_g','kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY['quantity_g']);
   IF (i->>'quantity_g')::numeric>9999 THEN RAISE EXCEPTION 'feedback_v3_item_mass_invalid' USING ERRCODE='22023'; END IF;
   q:=i->'quantity';PERFORM private.mobile_feedback_v2_keys(q,ARRAY['value','unit','estimated','reference_id']);
   PERFORM private.assert_feedback_numeric_fields(q-ARRAY['unit','estimated','reference_id'],ARRAY['value'],ARRAY[]::text[],ARRAY['value']);
   PERFORM private.mobile_feedback_v2_text(q->'reference_id',true);
   IF (q->>'value')::numeric>999999 OR q->>'unit' IS NULL OR q->>'unit' NOT IN('g','mL','unit','scoop') OR jsonb_typeof(q->'estimated') IS DISTINCT FROM 'boolean'
    OR (q->>'unit'='g' AND abs((q->>'value')::numeric-(i->>'quantity_g')::numeric)>=0.000001)
    OR (q->'estimated'='true'::jsonb AND q->>'unit'<>'g' AND q->'reference_id'='null'::jsonb) THEN RAISE EXCEPTION 'feedback_v3_quantity_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
 ELSE
  PERFORM private.mobile_feedback_v2_keys(r,ARRAY['kind','log_id','workout_type','duration_min','intensity','estimated_kcal']);
  id:=(r->>'log_id')::uuid;IF id IS NULL THEN RAISE EXCEPTION 'feedback_v3_workout_id_invalid' USING ERRCODE='22023'; END IF;
  PERFORM private.mobile_feedback_v2_text(r->'workout_type');PERFORM private.mobile_feedback_v2_text(r->'intensity',true);
  PERFORM private.assert_feedback_numeric_fields(r-ARRAY['kind','log_id','workout_type','intensity'],ARRAY['duration_min','estimated_kcal'],ARRAY['duration_min','estimated_kcal'],ARRAY['duration_min']);
  IF (r->>'duration_min')::numeric>1440 THEN RAISE EXCEPTION 'feedback_v3_workout_duration_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 d:=f->'day';
 IF d<>'null'::jsonb THEN
  PERFORM private.mobile_feedback_v2_keys(d,ARRAY['local_date','current_protocol','consumed','targets','calorie_percentage','protein_percentage','remaining_food_kcal','food_excess_kcal','exercise_kcal','exercise_energy']);
  IF d->'current_protocol'<>'null' AND (d->>'current_protocol' IS NULL OR d->>'current_protocol' NOT IN('recomposicao','ganho_massa','manutencao')) THEN RAISE EXCEPTION 'feedback_v3_protocol_invalid' USING ERRCODE='22023';END IF;
  PERFORM private.assert_feedback_numeric_fields(d->'consumed',ARRAY['calories_kcal','protein_g','carbs_g','fat_g'],ARRAY[]::text[],ARRAY[]::text[]);
  PERFORM private.assert_feedback_numeric_fields(d->'targets',ARRAY['calories_kcal','protein_g'],ARRAY['calories_kcal','protein_g'],ARRAY['calories_kcal','protein_g']);
  PERFORM private.assert_feedback_numeric_fields(d-ARRAY['local_date','current_protocol','consumed','targets','exercise_energy'],ARRAY['calorie_percentage','protein_percentage','remaining_food_kcal','food_excess_kcal','exercise_kcal'],ARRAY['calorie_percentage','protein_percentage','remaining_food_kcal','food_excess_kcal','exercise_kcal'],ARRAY[]::text[]);
  IF d->'exercise_energy'='{"status":"available"}' THEN
   IF d->'exercise_kcal'='null' THEN RAISE EXCEPTION 'feedback_v3_energy_invalid' USING ERRCODE='22023';END IF;
  ELSE
   PERFORM private.mobile_feedback_v2_keys(d->'exercise_energy',ARRAY['status','reason']);
   IF d#>>'{exercise_energy,status}' IS DISTINCT FROM 'unavailable' OR d#>>'{exercise_energy,reason}' IS NULL OR d#>>'{exercise_energy,reason}' NOT IN('unknown_workout_energy','source_unavailable') OR d->'exercise_kcal'<>'null' THEN RAISE EXCEPTION 'feedback_v3_energy_invalid' USING ERRCODE='22023';END IF;
  END IF;
  IF p_kind='workout' AND r->'estimated_kcal'='null' AND d->'exercise_kcal'<>'null' THEN RAISE EXCEPTION 'feedback_v3_unknown_registration_energy' USING ERRCODE='22023';END IF;
  IF d->>'local_date' IS DISTINCT FROM f->>'local_date' THEN RAISE EXCEPTION 'feedback_v3_day_date_invalid' USING ERRCODE='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['calories_kcal','protein_g'] LOOP
   percent:=(private.mobile_feedback_v2_percentage((d#>>ARRAY['consumed',k])::numeric,(d#>>ARRAY['targets',k])::numeric,1000,10)#>>'{}')::numeric;
   IF (d->>(CASE WHEN k='calories_kcal' THEN 'calorie_percentage' ELSE 'protein_percentage' END))::numeric IS DISTINCT FROM percent THEN RAISE EXCEPTION 'feedback_v3_percentage_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF (d->'remaining_food_kcal'<>'null' AND (d->>'remaining_food_kcal')::numeric IS DISTINCT FROM greatest(0,(d#>>'{targets,calories_kcal}')::numeric-(d#>>'{consumed,calories_kcal}')::numeric))
   OR (d->'food_excess_kcal'<>'null' AND (d->>'food_excess_kcal')::numeric IS DISTINCT FROM greatest(0,(d#>>'{consumed,calories_kcal}')::numeric-(d#>>'{targets,calories_kcal}')::numeric)) THEN RAISE EXCEPTION 'feedback_v3_budget_invalid' USING ERRCODE='22023';END IF;
  IF (d#>'{targets,calories_kcal}'='null'::jsonb AND (d->'remaining_food_kcal'<>'null'::jsonb OR d->'food_excess_kcal'<>'null'::jsonb))
   OR ((d->>'remaining_food_kcal')::numeric>0 AND (d->>'food_excess_kcal')::numeric>0)
   OR (f->>'guidance'<>'available' AND (d->'current_protocol'<>'null'::jsonb OR d#>'{targets,calories_kcal}'<>'null'::jsonb OR d#>'{targets,protein_g}'<>'null'::jsonb)) THEN RAISE EXCEPTION 'feedback_v3_day_visibility_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 b:=f->'block';
 IF b->>'status'='available' THEN
  PERFORM private.mobile_feedback_v2_keys(b,ARRAY['status','target_kcal','current_kcal','percentage','completed_blocks','total_credited_kcal']);
  PERFORM private.assert_feedback_numeric_fields(b-'status',ARRAY['target_kcal','current_kcal','percentage','completed_blocks','total_credited_kcal'],ARRAY[]::text[],ARRAY[]::text[]);
  IF d='null'::jsonb OR d->>'current_protocol' IS DISTINCT FROM 'recomposicao' OR f->>'guidance'<>'available'
   OR b->'target_kcal'<>'7700'::jsonb OR (b->>'completed_blocks')::numeric<>trunc((b->>'completed_blocks')::numeric)
   OR b->'percentage' IS DISTINCT FROM private.mobile_feedback_v2_percentage((b->>'current_kcal')::numeric,7700,100,1)
   OR abs((b->>'total_credited_kcal')::numeric-((b->>'completed_blocks')::numeric*7700+(b->>'current_kcal')::numeric))>=0.000001 THEN RAISE EXCEPTION 'feedback_v3_block_invalid' USING ERRCODE='22023'; END IF;
 ELSE
  PERFORM private.mobile_feedback_v2_keys(b,ARRAY['status']);
  IF b->>'status' IS NULL OR b->>'status' NOT IN('unavailable','not_applicable','protected') OR (b->>'status'='not_applicable' AND (d='null'::jsonb OR d->>'current_protocol' IS NULL OR d->>'current_protocol'='recomposicao')) THEN RAISE EXCEPTION 'feedback_v3_block_status_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 e:=f->'education';
 IF e='{"status":"unavailable"}'::jsonb THEN RETURN; END IF;
 IF jsonb_typeof(e#>'{provenance,preferences_known}') IS DISTINCT FROM 'boolean' OR length(e->>'text')>1600
  OR e IS DISTINCT FROM private.registration_feedback_v2_expected_education(f,(e#>>'{provenance,preferences_known}')::boolean) THEN RAISE EXCEPTION 'feedback_v3_education_invalid' USING ERRCODE='22023'; END IF;
END $$;

CREATE FUNCTION private.registration_feedback_v3_record(c jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE p jsonb:=c#>'{confirmed,proposal}';item jsonb;saved jsonb;items jsonb:='[]';used text[]:='{}';
BEGIN
 IF p->>'kind'='workout' THEN
  saved:=c->'logs'->0;
  RETURN jsonb_build_object('kind','workout','log_id',saved->'id','workout_type',saved->'workout_type','duration_min',saved->'duration_min','intensity',saved->'intensity','estimated_kcal',saved->'estimated_kcal');
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p->'items') LOOP
  SELECT value INTO saved FROM jsonb_array_elements(c->'logs') WHERE NOT(value->>'id'=ANY(used)) AND value->>'food_name'=item->>'name' AND value->>'source'=item->>'nutrition_source'
   AND value->'quantity_g'=to_jsonb(round((item->>'quantity_g')::numeric,2)) AND value->'kcal'=to_jsonb(round((item->>'kcal')::numeric,2))
   AND value->'protein_g'=to_jsonb(round((item->>'protein_g')::numeric,2)) AND value->'carbs_g'=to_jsonb(round((item->>'carbs_g')::numeric,2)) AND value->'fat_g'=to_jsonb(round((item->>'fat_g')::numeric,2)) ORDER BY value->>'id' LIMIT 1;
  IF saved IS NULL THEN RAISE EXCEPTION 'feedback_v3_item_source_invalid' USING ERRCODE='22023';END IF;used:=array_append(used,saved->>'id');
  items:=items||jsonb_build_array(jsonb_build_object('log_id',saved->'id','food_name',saved->'food_name','quantity_g',saved->'quantity_g',
   'quantity',private.mobile_feedback_v2_quantity(saved->>'food_name',(saved->>'quantity_g')::numeric,item->>'quantity_basis'),'nutrition_source',saved->'source',
   'kcal',saved->'kcal','protein_g',saved->'protein_g','carbs_g',saved->'carbs_g','fat_g',saved->'fat_g'));
 END LOOP;
 IF cardinality(used)<>jsonb_array_length(c->'logs') THEN RAISE EXCEPTION 'feedback_v3_item_source_invalid' USING ERRCODE='22023';END IF;
 RETURN jsonb_build_object('kind','meal','meal_kind',p->'mealType','totals',p->'totals','items',items);
END $$;
CREATE FUNCTION private.registration_feedback_v3_source_binding(c jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT (c-ARRAY['clinical','source'])||jsonb_build_object('clinical',private.mobile_registration_feedback_v2_context_binding(c->'clinical'),
 'source',CASE WHEN c#>>'{source,kind}'='pending_registration' THEN (c->'source')||jsonb_build_object('capture',private.mobile_registration_feedback_v2_source_binding(c#>'{source,capture}')) ELSE c->'source' END);
$$;
-- Both real meal paths share pending identity but retain their own protocol,
-- receipt schema/provider and original parent linkage. Never fake a direct meal.
CREATE FUNCTION private.registration_feedback_v3_meal_command(e private.conversation_meal_effects) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;linked jsonb;continuation jsonb:=NULL;
BEGIN
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=e.user_id AND command_id=e.command_id;
 IF NOT FOUND OR c.invalidated_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=e.user_id AND epoch=c.epoch)
  OR e.receipt->>'command_id' IS DISTINCT FROM c.command_id::text OR e.receipt->>'input_hash' IS DISTINCT FROM c.input_hash
  OR e.feedback_context#>>'{clinical,epoch}' IS DISTINCT FROM c.epoch::text THEN RETURN NULL;END IF;
 IF e.receipt->>'schema'='conversation.meal-effect.v1' THEN
  IF c.command_protocol<>'conversation.command.v1' OR c.kind<>'meal.report' THEN RETURN NULL;END IF;
 ELSIF e.receipt->>'schema'='conversation.meal-continuation-effect.v1' THEN
  IF c.command_protocol<>'conversation.clarification.v1' OR c.kind<>'meal.clarify' OR e.receipt->>'epoch' IS DISTINCT FROM c.epoch::text THEN RETURN NULL;END IF;
  linked:=private.conversation_continuation_fulfillment(e.user_id,(e.receipt->>'parent_command_id')::uuid);
  IF linked IS NULL OR linked->'receipt' IS DISTINCT FROM e.receipt OR linked#>>'{child_binding,command_id}' IS DISTINCT FROM c.command_id::text
   OR NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids p WHERE p.user_id=e.user_id AND p.command_id=(e.receipt->>'parent_command_id')::uuid
    AND p.invalidated_at IS NULL AND p.epoch=c.epoch AND p.command_protocol='conversation.command.v1' AND p.kind='meal.report') THEN RETURN NULL;END IF;
  continuation:=jsonb_build_object('parentBinding',linked->'parent_binding','childBinding',linked->'child_binding','parentDecisionHash',e.receipt->'parent_decision_hash','receipt',e.receipt);
 ELSE RETURN NULL;END IF;
 RETURN jsonb_build_object('command_id',c.command_id,'epoch',c.epoch,'input_hash',c.input_hash,'receipt',e.receipt,'continuation',continuation);
END $$;
CREATE FUNCTION private.capture_mobile_registration_feedback_v3(u uuid,r uuid,o text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE p public.pending_registrations%ROWTYPE;e private.conversation_meal_effects%ROWTYPE;wc private.conversation_workout_command_ids%ROWTYPE;
 we private.conversation_workout_effects%ROWTYPE;ws private.conversation_workout_sources%ROWTYPE;wp private.conversation_workout_preparations%ROWTYPE;
 c jsonb;source jsonb;record jsonb;event text;workouts jsonb;row public.workout_logs%ROWTYPE;command jsonb:=NULL;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'feedback_v3_requires_read_committed' USING ERRCODE='22023';END IF;
 IF u IS NULL OR r IS NULL OR o IS NULL OR o NOT IN('pending_registration','conversation_workout') THEN RETURN NULL;END IF;
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 PERFORM private.lock_conversation_command_owner(u);
 IF o='pending_registration' THEN
  SELECT * INTO p FROM public.pending_registrations WHERE id=r AND user_id=u AND status='confirmed' FOR SHARE NOWAIT;
  IF NOT FOUND THEN RETURN NULL;END IF;
  IF (SELECT count(*) FROM private.conversation_meal_effects WHERE user_id=u AND receipt->>'registration_id'=r::text)>1 THEN RETURN NULL;END IF;
  SELECT * INTO e FROM private.conversation_meal_effects WHERE user_id=u AND receipt->>'registration_id'=r::text FOR SHARE NOWAIT;
  IF FOUND THEN
   IF NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids cmd JOIN private.workout_strength_authority_epochs a ON a.user_id=cmd.user_id AND a.epoch=cmd.epoch
    WHERE cmd.user_id=u AND cmd.command_id=e.command_id AND cmd.invalidated_at IS NULL) OR private.conversation_meal_frozen_feedback_source(e)->>'action'<>'available' THEN RETURN NULL;END IF;
   c:=e.feedback_context;
   command:=private.registration_feedback_v3_meal_command(e);IF command IS NULL THEN RETURN NULL;END IF;
   workouts:=NULL;
  ELSE
   IF p.proposal ? 'command_protocol' OR p.proposal ? 'command_id' THEN RETURN NULL;END IF;
   c:=private.capture_mobile_registration_feedback_v2(u,r);IF c IS NULL THEN RETURN NULL;END IF;
   workouts:='[]';
   FOR row IN SELECT * FROM public.workout_logs WHERE user_id=u AND snapshot_id=(c#>>'{snapshot,id}')::uuid ORDER BY id FOR SHARE NOWAIT LOOP
    workouts:=workouts||jsonb_build_array(to_jsonb(row));IF jsonb_array_length(workouts)>10000 THEN RETURN NULL;END IF;
   END LOOP;
  END IF;
  record:=private.registration_feedback_v3_record(c);
  event:=encode(extensions.digest(convert_to((c#>'{confirmed,proposal}')::text,'UTF8'),'sha256'),'hex');
  source:=jsonb_build_object('kind','pending_registration','capture',c,'command',command);
 ELSE
  SELECT * INTO wc FROM private.conversation_workout_command_ids WHERE user_id=u AND command_id=r FOR SHARE NOWAIT;
  IF NOT FOUND OR wc.invalidated_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u AND epoch=wc.epoch) THEN RETURN NULL;END IF;
  SELECT * INTO we FROM private.conversation_workout_effects WHERE user_id=u AND command_id=r FOR SHARE NOWAIT;
  IF NOT FOUND OR we.feedback_context IS NULL OR we.feedback_context->'logs' IS DISTINCT FROM jsonb_build_array(we.original_facts->'workout')
   OR jsonb_typeof(we.feedback_context#>'{snapshot,exercise_energy_complete}') IS DISTINCT FROM 'boolean'
   OR jsonb_typeof(we.feedback_context#>'{snapshot,exercise_calories}') IS DISTINCT FROM 'number' THEN RETURN NULL;END IF;
  SELECT * INTO STRICT ws FROM private.conversation_workout_sources WHERE user_id=u AND command_id=r FOR SHARE NOWAIT;
  SELECT * INTO STRICT wp FROM private.conversation_workout_preparations WHERE user_id=u AND command_id=r FOR SHARE NOWAIT;
  c:=we.feedback_context;record:=jsonb_build_object('kind','workout','log_id',we.receipt->'workout_id')||(we.receipt->'activity');
  event:=encode(extensions.digest(convert_to(jsonb_build_object('receipt',we.receipt,'original_facts',we.original_facts)::text,'UTF8'),'sha256'),'hex');
  source:=jsonb_build_object('kind','conversation_workout','input',ws.context->'source_input','captured',jsonb_build_object('source_hash',ws.source_hash,'context',ws.context),
    'prepared',wp.prepared,'effect',jsonb_build_object('action','available','receipt',we.receipt,'original_facts',we.original_facts),'feedback_context',c);
  workouts:=NULL;
 END IF;
 RETURN jsonb_build_object('version',3,'origin',o,'user_id',u,'registration_id',r,'event_hash',event,'local_date',c#>'{snapshot,date}','record',record,'source',source,
  'logs',c->'logs','snapshot',c->'snapshot','day_workouts',workouts,'progress',c->'progress','clinical',c->'clinical');
END $$;
CREATE FUNCTION private.assert_registration_feedback_v3_sources(f jsonb,c jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE r jsonb:=f->'registration';d jsonb:=f->'day';s jsonb:=c->'snapshot';b jsonb:=f->'block';progress jsonb:=c->'progress';
 policy jsonb:=private.mobile_registration_feedback_v2_policy(c->'clinical');k text;target numeric;hide boolean;objective text;complete boolean;reason text;frozen boolean;
BEGIN
 PERFORM private.assert_registration_feedback_v3_shape(f,(c->>'registration_id')::uuid,c#>>'{record,kind}');
 IF c->'version' IS DISTINCT FROM '3' OR f->>'local_date' IS DISTINCT FROM c->>'local_date' OR r IS DISTINCT FROM c->'record' OR f->>'guidance' IS DISTINCT FROM policy->>'guidance' THEN RAISE EXCEPTION 'feedback_v3_source_identity_invalid' USING ERRCODE='22023';END IF;
 frozen:=c->>'origin'='conversation_workout' OR c#>'{source,command}'<>'null';
 complete:=s->'exercise_energy_complete'='true' AND s->'exercise_calories'<>'null';
 IF NOT frozen THEN complete:=complete AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'day_workouts') w WHERE w->'estimated_kcal'='null');END IF;
 reason:=CASE WHEN s ? 'exercise_energy_complete' AND s->'exercise_calories'<>'null' THEN 'unknown_workout_energy' ELSE 'source_unavailable' END;
 IF d<>'null' THEN
  IF s->>'date' IS DISTINCT FROM f->>'local_date' OR c#>>'{clinical,date}' IS DISTINCT FROM f->>'local_date' THEN RAISE EXCEPTION 'feedback_v3_day_source_invalid' USING ERRCODE='22023';END IF;
  IF d->'consumed' IS DISTINCT FROM jsonb_build_object('calories_kcal',s->'calories_consumed','protein_g',s->'protein_g','carbs_g',s->'carbs_g','fat_g',s->'fat_g') THEN RAISE EXCEPTION 'feedback_v3_day_consumed_invalid' USING ERRCODE='22023';END IF;
  IF d#>>'{exercise_energy,status}'='available' THEN
   IF complete IS DISTINCT FROM true OR d->'exercise_kcal' IS DISTINCT FROM s->'exercise_calories' THEN RAISE EXCEPTION 'feedback_v3_day_energy_unproved' USING ERRCODE='22023';END IF;
  ELSIF d#>>'{exercise_energy,reason}' IS DISTINCT FROM (CASE WHEN complete THEN 'source_unavailable' ELSE reason END) THEN RAISE EXCEPTION 'feedback_v3_day_energy_unproved' USING ERRCODE='22023';END IF;
  objective:=CASE WHEN c#>>'{clinical,phase_origin,kind}'='assigned' THEN c#>>'{clinical,phase_origin,phase}' ELSE NULL END;
  IF d->'current_protocol'<>'null' AND (policy->>'guidance'<>'available' OR (policy#>>'{hide,objective}')::boolean OR d->>'current_protocol' IS DISTINCT FROM objective) THEN RAISE EXCEPTION 'feedback_v3_objective_source_invalid' USING ERRCODE='22023';END IF;
  FOREACH k IN ARRAY ARRAY['calories_kcal','protein_g'] LOOP
   target:=(d#>>ARRAY['targets',k])::numeric;hide:=coalesce((policy#>>ARRAY['hide',CASE WHEN k='calories_kcal' THEN 'calories' ELSE 'protein' END])::boolean,true);
   IF target IS NOT NULL AND (hide OR policy->>'guidance'<>'available' OR target IS DISTINCT FROM (s->>(CASE WHEN k='calories_kcal' THEN 'calories_target' ELSE 'protein_target' END))::numeric) THEN RAISE EXCEPTION 'feedback_v3_target_source_invalid' USING ERRCODE='22023';END IF;
  END LOOP;
 END IF;
 hide:=policy->>'guidance'='paused' OR (policy#>>'{hide,block}')::boolean OR (policy#>>'{hide,objective}')::boolean;
 IF (hide AND b->>'status'<>'protected') OR (NOT hide AND b->>'status'='protected') THEN RAISE EXCEPTION 'feedback_v3_block_visibility_invalid' USING ERRCODE='22023';END IF;
 IF b->>'status'='available' AND (progress='null' OR b->'current_kcal' IS DISTINCT FROM progress->'deficit_block' OR b->'completed_blocks' IS DISTINCT FROM progress->'blocks_completed') THEN RAISE EXCEPTION 'feedback_v3_block_source_invalid' USING ERRCODE='22023';END IF;
 IF f#>>'{education,provenance,preferences_known}'='true' THEN RAISE EXCEPTION 'feedback_v3_preferences_unproved' USING ERRCODE='22023';END IF;
END $$;

-- Read is receipt-only. No current day recapture, cursor, rewards or registration.
CREATE FUNCTION public.read_mobile_registration_feedback_v3(p_user_id uuid,p_registration_id uuid,p_origin text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p public.pending_registrations%ROWTYPE;e private.conversation_meal_effects%ROWTYPE;we private.conversation_workout_effects%ROWTYPE;
 stored_receipt private.mobile_registration_feedback_v3%ROWTYPE;claim private.mobile_registration_feedback_claims%ROWTYPE;h text;old jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_registration_id IS NULL OR p_origin IS NULL OR p_origin NOT IN('pending_registration','conversation_workout') THEN RETURN '{"action":"event_conflict"}';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"event_conflict"}';END IF;
 IF p_origin='pending_registration' THEN
  SELECT * INTO p FROM public.pending_registrations WHERE id=p_registration_id AND user_id=p_user_id AND status='confirmed';
  IF NOT FOUND THEN RETURN '{"action":"event_conflict"}';END IF;
  IF (SELECT count(*) FROM private.conversation_meal_effects WHERE user_id=p_user_id AND receipt->>'registration_id'=p_registration_id::text)>1 THEN RETURN '{"action":"event_conflict"}';END IF;
  SELECT * INTO e FROM private.conversation_meal_effects WHERE user_id=p_user_id AND receipt->>'registration_id'=p_registration_id::text;
  IF FOUND THEN
   IF NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids cmd JOIN private.workout_strength_authority_epochs a ON a.user_id=cmd.user_id AND a.epoch=cmd.epoch
     WHERE cmd.user_id=p_user_id AND cmd.command_id=e.command_id AND cmd.invalidated_at IS NULL) THEN RETURN '{"action":"event_conflict"}';END IF;
   h:=encode(extensions.digest(convert_to((e.original_facts#>'{confirmed,proposal}')::text,'UTF8'),'sha256'),'hex');
  ELSE h:=encode(extensions.digest(convert_to(p.proposal::text,'UTF8'),'sha256'),'hex');END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids cmd JOIN private.workout_strength_authority_epochs a ON a.user_id=cmd.user_id AND a.epoch=cmd.epoch
    WHERE cmd.user_id=p_user_id AND cmd.command_id=p_registration_id AND cmd.invalidated_at IS NULL) THEN RETURN '{"action":"event_conflict"}';END IF;
  SELECT * INTO we FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_registration_id;
  IF NOT FOUND THEN RETURN '{"action":"event_conflict"}';END IF;
  h:=encode(extensions.digest(convert_to(jsonb_build_object('receipt',we.receipt,'original_facts',we.original_facts)::text,'UTF8'),'sha256'),'hex');
 END IF;
 SELECT * INTO claim FROM private.mobile_registration_feedback_claims WHERE user_id=p_user_id AND origin=p_origin AND registration_id=p_registration_id;
 SELECT * INTO stored_receipt FROM private.mobile_registration_feedback_v3 WHERE user_id=p_user_id AND origin=p_origin AND registration_id=p_registration_id;
 IF stored_receipt.registration_id IS NOT NULL THEN
  IF claim.version IS DISTINCT FROM 3 OR stored_receipt.event_hash IS DISTINCT FROM h THEN RETURN '{"action":"event_conflict"}';END IF;
  RETURN jsonb_build_object('action','available','feedback',stored_receipt.feedback);
 END IF;
 IF claim.version=3 THEN RETURN '{"action":"event_conflict"}';END IF;
 IF p_origin='pending_registration' THEN
  IF e.command_id IS NOT NULL THEN old:=private.conversation_meal_feedback_receipt(e);
  ELSE old:=public.read_mobile_registration_feedback_v2(p_user_id,p_registration_id);END IF;
  IF old->>'action' IN('available','legacy') THEN
   IF claim.version IS DISTINCT FROM (CASE old#>>'{feedback,schema}' WHEN 'registration.feedback.v1' THEN 1 WHEN 'registration.feedback.v2' THEN 2 END) THEN RETURN '{"action":"event_conflict"}';END IF;
   RETURN jsonb_build_object('action','available','feedback',old->'feedback');END IF;
  IF old->>'action'='event_conflict' THEN RETURN old;END IF;
 END IF;
 IF claim.registration_id IS NOT NULL THEN RETURN '{"action":"event_conflict"}';END IF;
 RETURN '{"action":"absent"}';
END $$;
CREATE FUNCTION public.capture_mobile_registration_feedback_v3(p_user_id uuid,p_registration_id uuid,p_origin text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();c:=private.capture_mobile_registration_feedback_v3(p_user_id,p_registration_id,p_origin);
 IF c IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;
 RETURN jsonb_build_object('action','available','context',c);
END $$;
CREATE FUNCTION public.commit_mobile_registration_feedback_v3(p_user_id uuid,p_registration_id uuid,p_origin text,p_expected_context jsonb,p_feedback jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;existing jsonb;binding jsonb;meal uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'feedback_v3_requires_read_committed' USING ERRCODE='22023';END IF;
 IF p_user_id IS NULL OR p_registration_id IS NULL OR p_origin IS NULL OR p_origin NOT IN('pending_registration','conversation_workout') THEN RETURN '{"action":"event_conflict"}';END IF;
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 PERFORM private.lock_conversation_command_owner(p_user_id);
 existing:=public.read_mobile_registration_feedback_v3(p_user_id,p_registration_id,p_origin);
 IF existing->>'action'='available' THEN RETURN jsonb_build_object('action','replay','feedback',existing->'feedback');END IF;
 IF existing->>'action'='event_conflict' THEN RETURN existing;END IF;
 c:=private.capture_mobile_registration_feedback_v3(p_user_id,p_registration_id,p_origin);
 IF c IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;
 binding:=private.registration_feedback_v3_source_binding(c);
 IF binding IS DISTINCT FROM private.registration_feedback_v3_source_binding(p_expected_context) THEN RETURN '{"action":"source_conflict"}';END IF;
 PERFORM private.assert_registration_feedback_v3_sources(p_feedback,c);
 meal:=(c#>>'{source,command,command_id}')::uuid;
 INSERT INTO private.mobile_registration_feedback_v3(user_id,origin,registration_id,pending_id,workout_command_id,meal_command_id,event_hash,source_hash,feedback)
 VALUES(p_user_id,p_origin,p_registration_id,CASE WHEN p_origin='pending_registration' THEN p_registration_id END,CASE WHEN p_origin='conversation_workout' THEN p_registration_id END,meal,c->>'event_hash',
  encode(extensions.digest(convert_to(binding::text,'UTF8'),'sha256'),'hex'),p_feedback);
 RETURN jsonb_build_object('action','committed','feedback',p_feedback);
END $$;

-- Pin and splice only the old read boundary. Old writes/isolations/phrase
-- progression and their exact early replay behavior otherwise remain intact.
DO $old_read_guards$
DECLARE sig text;expected text;needle text;replacement text;definition text;body text;
BEGIN
 FOR sig,expected,needle,replacement IN SELECT * FROM (VALUES
 ('public.read_mobile_registration_feedback(uuid,uuid)','aee289a84f82addf99d56e2f7c9bdd16195855bb6be690e8fc031e69b2734b80',
 ' SELECT * INTO v_receipt FROM private.mobile_registration_feedback WHERE registration_id=p_registration_id AND user_id=p_user_id;',
 E' IF EXISTS(SELECT 1 FROM private.mobile_registration_feedback_claims WHERE user_id=p_user_id AND origin=\'pending_registration\' AND registration_id=p_registration_id AND version=3) THEN RETURN \'{"action":"event_conflict"}\'::jsonb;END IF;\n SELECT * INTO v_receipt FROM private.mobile_registration_feedback WHERE registration_id=p_registration_id AND user_id=p_user_id;'),
 ('public.read_mobile_registration_feedback_v2(uuid,uuid)','709360f590b58e8d4cba3eb2ef219ddba2c772b817a0624350fc9c2960e3e58f',
 ' h:=encode(extensions.digest(convert_to(p.proposal::text,''UTF8''),''sha256''),''hex'');',
 E' IF EXISTS(SELECT 1 FROM private.mobile_registration_feedback_claims WHERE user_id=p_user_id AND origin=\'pending_registration\' AND registration_id=p_registration_id AND version=3) THEN RETURN \'{"action":"event_conflict"}\'::jsonb;END IF;\n h:=encode(extensions.digest(convert_to(p.proposal::text,\'UTF8\'),\'sha256\'),\'hex\');'),
 ('private.conversation_meal_feedback_receipt(private.conversation_meal_effects)','01d1eef2a3faaf334310782162a88f34f98f6c93752283fae505e5de9eca37c0',
 ' registration:=(e.receipt->>''registration_id'')::uuid;',
 E' registration:=(e.receipt->>\'registration_id\')::uuid;\n IF EXISTS(SELECT 1 FROM private.mobile_registration_feedback_claims WHERE user_id=e.user_id AND origin=\'pending_registration\' AND registration_id=registration AND version=3) THEN RETURN \'{"action":"event_conflict"}\'::jsonb;END IF;')
 ) AS guards(sig,expected,needle,replacement) LOOP
  SELECT prosrc,pg_get_functiondef(oid) INTO body,definition FROM pg_proc WHERE oid=to_regprocedure(sig);
  IF encode(sha256(convert_to(body,'UTF8')),'hex') IS DISTINCT FROM expected OR (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'feedback_v3_unpinned_old_reader:%',sig USING ERRCODE='42501';END IF;
  EXECUTE replace(definition,needle,replacement);
 END LOOP;
END $old_read_guards$;
REVOKE ALL ON FUNCTION private.claim_mobile_registration_feedback(),private.guard_mobile_registration_feedback_v3(),private.guard_mobile_registration_feedback_claim(),
 private.assert_registration_feedback_v3_shape(jsonb,uuid,text),private.assert_registration_feedback_v3_sources(jsonb,jsonb),private.registration_feedback_v3_record(jsonb),private.registration_feedback_v3_source_binding(jsonb),private.registration_feedback_v3_meal_command(private.conversation_meal_effects),private.capture_mobile_registration_feedback_v3(uuid,uuid,text),
 public.read_mobile_registration_feedback_v3(uuid,uuid,text),public.capture_mobile_registration_feedback_v3(uuid,uuid,text),public.commit_mobile_registration_feedback_v3(uuid,uuid,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_mobile_registration_feedback_v3(uuid,uuid,text),public.capture_mobile_registration_feedback_v3(uuid,uuid,text),public.commit_mobile_registration_feedback_v3(uuid,uuid,text,jsonb,jsonb) TO service_role;
COMMIT;

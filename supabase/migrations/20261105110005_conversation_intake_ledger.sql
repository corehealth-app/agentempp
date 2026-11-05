-- Neutral routing is not performed authority. Only the genuine fenced typed
-- admission can create a child, and selection + child commit in one transaction.
-- No routes, capabilities, provider calls, effects, receipts or reward changes.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'intake_requires_postgres' USING ERRCODE='42501';END IF;
 IF to_regclass('private.conversation_intake_ids') IS NOT NULL THEN RAISE EXCEPTION 'intake_unknown_existing_object' USING ERRCODE='42P07';END IF;
 IF to_regprocedure('public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)') IS NULL
 OR to_regprocedure('public.admit_conversation_workout_command(uuid,uuid,jsonb)') IS NULL
 OR to_regprocedure('private.lock_conversation_command_owner(uuid)') IS NULL
 OR to_regprocedure('private.conversation_command_canonical(jsonb)') IS NULL THEN RAISE EXCEPTION 'intake_missing_substrate' USING ERRCODE='42P01';END IF;
END $preflight$;
CREATE TABLE private.conversation_intake_ids(
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,intake_id uuid NOT NULL,
 input_hash text COLLATE "C" NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),epoch uuid NOT NULL,
 admitted_at timestamptz NOT NULL CHECK(isfinite(admitted_at)),reserved_child_id uuid NOT NULL CHECK(reserved_child_id<>intake_id),
 invalidated_at timestamptz CHECK(isfinite(invalidated_at)),PRIMARY KEY(user_id,intake_id),UNIQUE(user_id,reserved_child_id)
);
CREATE INDEX conversation_intake_admission_window ON private.conversation_intake_ids(user_id,epoch,admitted_at);
CREATE TABLE private.conversation_intake_inputs(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,source_input jsonb NOT NULL CHECK(jsonb_typeof(source_input)='object'),
 admitted_time_zone text,admitted_local_date date,
 PRIMARY KEY(user_id,intake_id),FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_ids ON DELETE CASCADE
);
CREATE TABLE private.conversation_intake_sources(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,source_hash text COLLATE "C" NOT NULL CHECK(source_hash ~ '^[0-9a-f]{64}$'),
 context jsonb NOT NULL CHECK(jsonb_typeof(context)='object'),
 PRIMARY KEY(user_id,intake_id),FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_inputs ON DELETE CASCADE
);
CREATE TABLE private.conversation_intake_claims(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,claim_id uuid NOT NULL,
 PRIMARY KEY(user_id,intake_id),UNIQUE(claim_id),FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_sources ON DELETE CASCADE
);
CREATE TABLE private.conversation_intake_selections(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,decision_hash text COLLATE "C" NOT NULL CHECK(decision_hash ~ '^[0-9a-f]{64}$'),
 selection jsonb NOT NULL CHECK(jsonb_typeof(selection)='object'),
 PRIMARY KEY(user_id,intake_id),FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_claims ON DELETE CASCADE
);
ALTER TABLE private.conversation_intake_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_intake_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_intake_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_intake_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_intake_selections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_intake_ids,private.conversation_intake_inputs,private.conversation_intake_sources,private.conversation_intake_claims,private.conversation_intake_selections FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.conversation_intake_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_TABLE_NAME='conversation_intake_ids' THEN
  IF OLD.invalidated_at IS NULL AND NEW.invalidated_at IS NOT NULL AND to_jsonb(OLD)-'invalidated_at'=to_jsonb(NEW)-'invalidated_at' THEN RETURN NEW;END IF;
 END IF;
 RAISE EXCEPTION 'conversation_intake_immutable' USING ERRCODE='22023';
END $$;
CREATE TRIGGER conversation_intake_ids_immutable BEFORE UPDATE ON private.conversation_intake_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE TRIGGER conversation_intake_input_immutable BEFORE UPDATE ON private.conversation_intake_inputs FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE TRIGGER conversation_intake_source_immutable BEFORE UPDATE ON private.conversation_intake_sources FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE TRIGGER conversation_intake_claim_immutable BEFORE UPDATE ON private.conversation_intake_claims FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE TRIGGER conversation_intake_selection_immutable BEFORE UPDATE ON private.conversation_intake_selections FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE FUNCTION private.scrub_conversation_intake_on_epoch() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN
 UPDATE private.conversation_intake_ids SET invalidated_at=clock_timestamp() WHERE user_id=NEW.user_id AND invalidated_at IS NULL;
 DELETE FROM private.conversation_intake_inputs WHERE user_id=NEW.user_id;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_intake_epoch_scrub AFTER UPDATE OF epoch ON private.workout_strength_authority_epochs FOR EACH ROW WHEN(OLD.epoch IS DISTINCT FROM NEW.epoch) EXECUTE FUNCTION private.scrub_conversation_intake_on_epoch();
-- Bidirectional namespace fence. A later typed writer cannot adopt a neutral
-- intake UUID. Reserved children are separately checked before real admission.
CREATE FUNCTION private.conversation_intake_namespace_fence() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id::text||':workouts',0));
 IF TG_TABLE_NAME='conversation_intake_ids' THEN
  IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=NEW.user_id AND command_id IN(NEW.intake_id,NEW.reserved_child_id))
  OR EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=NEW.user_id AND command_id IN(NEW.intake_id,NEW.reserved_child_id))
  OR EXISTS(SELECT 1 FROM private.conversation_intake_ids WHERE user_id=NEW.user_id AND (intake_id=NEW.reserved_child_id OR reserved_child_id=NEW.intake_id)) THEN RAISE EXCEPTION 'conversation_intake_namespace_conflict' USING ERRCODE='23505';END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM private.conversation_intake_ids WHERE user_id=NEW.user_id AND intake_id=NEW.command_id) THEN RAISE EXCEPTION 'conversation_intake_namespace_conflict' USING ERRCODE='23505';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER conversation_intake_namespace BEFORE INSERT ON private.conversation_intake_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_namespace_fence();
CREATE TRIGGER conversation_meal_intake_namespace BEFORE INSERT ON private.conversation_meal_command_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_namespace_fence();
CREATE TRIGGER conversation_workout_intake_namespace BEFORE INSERT ON private.conversation_workout_command_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_namespace_fence();
CREATE FUNCTION private.assert_conversation_intake_input(v jsonb) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE s jsonb:=v->'source';
BEGIN
 IF jsonb_typeof(v) IS DISTINCT FROM 'object' OR NOT(v ?& ARRAY['intake_protocol','intake_id','source'])
 OR v-ARRAY['intake_protocol','intake_id','source','meal_type_hint']<>'{}'::jsonb
 OR v->>'intake_protocol' IS DISTINCT FROM 'conversation.intake.v1'
 OR jsonb_typeof(v->'intake_id') IS DISTINCT FROM 'string' OR NOT coalesce(v->>'intake_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false)
 OR (v ? 'meal_type_hint' AND (jsonb_typeof(v->'meal_type_hint') IS DISTINCT FROM 'string' OR v->>'meal_type_hint' NOT IN('cafe','almoco','lanche','jantar','ceia','outro')))
 OR jsonb_typeof(s) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid_conversation_intake' USING ERRCODE='22023';END IF;
 IF s->>'channel'='text' THEN
  IF s-ARRAY['channel','text']<>'{}'::jsonb OR NOT private.conversation_command_text_valid(s->'text',2000) THEN RAISE EXCEPTION 'invalid_conversation_intake' USING ERRCODE='22023';END IF;
 ELSIF s->>'channel'='media' THEN
  IF NOT(s ?& ARRAY['channel','media_asset_id','user_action']) OR s-ARRAY['channel','media_asset_id','user_action','caption']<>'{}'::jsonb
  OR s->>'user_action' IS DISTINCT FROM 'report_actual_record' OR jsonb_typeof(s->'media_asset_id') IS DISTINCT FROM 'string'
  OR NOT coalesce(s->>'media_asset_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false)
  OR (s ? 'caption' AND NOT private.conversation_command_text_valid(s->'caption',1000)) THEN RAISE EXCEPTION 'invalid_conversation_intake' USING ERRCODE='22023';END IF;
 ELSE RAISE EXCEPTION 'invalid_conversation_intake' USING ERRCODE='22023';END IF;
END $$;
CREATE FUNCTION private.assert_conversation_intake_decision(v jsonb) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE q jsonb:=v->'question';
BEGIN
 IF jsonb_typeof(v) IS DISTINCT FROM 'object' OR NOT(v ?& ARRAY['schema','kind','reason']) OR v-ARRAY['schema','kind','reason','question']<>'{}'::jsonb
 OR v->>'schema' IS DISTINCT FROM 'conversation.intake-routing.v1' OR v->>'kind' NOT IN('meal.report','workout.report','not_reported','clarification_required')
 OR jsonb_typeof(v->'kind') IS DISTINCT FROM 'string' OR jsonb_typeof(v->'reason') IS DISTINCT FROM 'string'
 OR NOT coalesce(v->>'reason' ~ '^[a-z_]{1,80}$',false) THEN RAISE EXCEPTION 'invalid_conversation_intake_decision' USING ERRCODE='22023';END IF;
 IF v->>'kind'='clarification_required' THEN
  IF jsonb_typeof(q) IS DISTINCT FROM 'object' OR NOT(q ?& ARRAY['field','text']) OR q-ARRAY['field','text']<>'{}'::jsonb
  OR jsonb_typeof(q->'field') IS DISTINCT FROM 'string' OR q->>'field' NOT IN('record_kind','description') OR NOT private.conversation_command_text_valid(q->'text',300) THEN RAISE EXCEPTION 'invalid_conversation_intake_decision' USING ERRCODE='22023';END IF;
 ELSIF v ? 'question' THEN RAISE EXCEPTION 'invalid_conversation_intake_decision' USING ERRCODE='22023';END IF;
END $$;
CREATE FUNCTION private.conversation_intake_clock(t timestamptz) RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$ SELECT to_char(t AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') $$;
CREATE FUNCTION private.conversation_intake_binding(c private.conversation_intake_ids) RETURNS jsonb LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('owner_id',c.user_id,'intake_id',c.intake_id,'input_hash',c.input_hash,'epoch',c.epoch,'admitted_at',private.conversation_intake_clock(c.admitted_at));
$$;
CREATE FUNCTION private.lock_conversation_intake(u uuid,i uuid,h text,e uuid) RETURNS text LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;actual uuid;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.lock_conversation_command_owner(u);
 SELECT epoch INTO actual FROM private.workout_strength_authority_epochs WHERE user_id=u FOR UPDATE;
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=i FOR UPDATE;
 IF NOT FOUND THEN RETURN 'absent';END IF;
 IF actual IS DISTINCT FROM e OR c.epoch IS DISTINCT FROM actual OR c.invalidated_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM private.conversation_intake_inputs WHERE user_id=u AND intake_id=i) THEN RETURN 'stale_epoch';END IF;
 IF c.input_hash IS DISTINCT FROM h THEN RETURN 'input_conflict';END IF;RETURN 'current';
END $$;
CREATE FUNCTION public.admit_conversation_intake(p_user_id uuid,p_expected_epoch uuid,p_input jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;actual uuid;i uuid;child uuid;h text;tz text;day date;at timestamptz;attempt integer;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_intake_input(p_input);PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO actual FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF actual IS NULL OR actual IS DISTINCT FROM p_expected_epoch THEN RETURN '{"action":"stale_epoch"}';END IF;
 i:=(p_input->>'intake_id')::uuid;h:=encode(sha256(convert_to(private.conversation_command_canonical(p_input),'UTF8')),'hex');
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=i FOR UPDATE;
 IF FOUND THEN
  IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM actual THEN RETURN '{"action":"stale_epoch"}';END IF;
  IF c.input_hash IS DISTINCT FROM h THEN RETURN '{"action":"input_conflict"}';END IF;
  RETURN jsonb_build_object('action','replay','intake',private.conversation_intake_binding(c));
 END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=i)
 OR EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=i)
 OR EXISTS(SELECT 1 FROM private.conversation_intake_ids WHERE user_id=p_user_id AND reserved_child_id=i) THEN RETURN '{"action":"input_conflict"}';END IF;
 at:=clock_timestamp();
 IF (SELECT count(*) FROM private.conversation_intake_ids WHERE user_id=p_user_id AND epoch=actual AND admitted_at>=at-interval '60 seconds')>=10 THEN RETURN '{"action":"rate_limited"}';END IF;
 FOR attempt IN 1..8 LOOP
  child:=gen_random_uuid();EXIT WHEN child<>i AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=child)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=child)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_ids WHERE user_id=p_user_id AND (intake_id=child OR reserved_child_id=child));
  child:=NULL;
 END LOOP;
 IF child IS NULL THEN RAISE EXCEPTION 'intake_child_identity_unavailable' USING ERRCODE='40001';END IF;
 SELECT timezone INTO tz FROM public.users WHERE id=p_user_id;
 IF EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=tz) THEN day:=(at AT TIME ZONE tz)::date;END IF;
 INSERT INTO private.conversation_intake_ids VALUES(p_user_id,i,h,actual,at,child,NULL) RETURNING * INTO c;
 INSERT INTO private.conversation_intake_inputs VALUES(p_user_id,i,p_input,tz,day);
 RETURN jsonb_build_object('action','admitted','intake',private.conversation_intake_binding(c));
END $$;
-- Rebuild only the neutral source from its actual owned rows. No clinical or
-- performed-source is synthesized here. A fresh check never mutates the capture.
CREATE FUNCTION private.conversation_intake_context(u uuid,i uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;r private.conversation_intake_inputs%ROWTYPE;m public.media_assets%ROWTYPE;
 tz text;at timestamptz:=clock_timestamp();media jsonb:=NULL;context jsonb;
BEGIN
 SELECT * INTO STRICT c FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=i;
 SELECT * INTO STRICT r FROM private.conversation_intake_inputs WHERE user_id=u AND intake_id=i;
 SELECT timezone INTO tz FROM public.users WHERE id=u AND status='active';
 IF tz IS DISTINCT FROM r.admitted_time_zone OR r.admitted_local_date IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=tz) THEN RETURN '{"action":"day_changed"}';END IF;
 IF (at AT TIME ZONE tz)::date IS DISTINCT FROM r.admitted_local_date OR c.admitted_at>at THEN RETURN '{"action":"day_changed"}';END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended(u::text||':'||r.admitted_local_date::text,0)) THEN RAISE EXCEPTION 'intake_day_busy' USING ERRCODE='55P03';END IF;
 PERFORM 1 FROM public.daily_snapshots WHERE user_id=u AND date=r.admitted_local_date AND day_closed FOR SHARE NOWAIT;
 IF FOUND THEN RETURN '{"action":"day_closed"}';END IF;
 IF r.source_input#>>'{source,channel}'='media' THEN
  SELECT * INTO m FROM public.media_assets WHERE user_id=u AND id=(r.source_input#>>'{source,media_asset_id}')::uuid FOR SHARE NOWAIT;
  IF NOT FOUND OR m.status<>'processed' OR m.kind NOT IN('meal_photo','audio_note','gym_photo') OR m.deleted_at IS NOT NULL
  OR m.processed_at IS NULL OR NOT isfinite(m.processed_at) OR m.updated_at IS NULL OR NOT isfinite(m.updated_at)
  OR m.processed_at>at OR m.updated_at>at OR jsonb_typeof(m.processing_result) IS DISTINCT FROM 'object' OR octet_length(m.processing_result::text)>1048576 THEN RETURN '{"action":"media_unavailable"}';END IF;
  media:=jsonb_build_object('asset_id',m.id,'owner_id',m.user_id,'kind',m.kind,'status',m.status,'processed_at',private.conversation_intake_clock(m.processed_at),'updated_at',private.conversation_intake_clock(m.updated_at),'context_text',m.context_text,'processing_result',m.processing_result);
 END IF;
 context:=jsonb_build_object('schema','conversation.intake-source.v1','owner_id',u,'intake_id',i,'input_hash',c.input_hash,'epoch',c.epoch,
 'source_input',r.source_input,'admitted_at',private.conversation_intake_clock(c.admitted_at),'captured_at',private.conversation_intake_clock(at),
 'time_zone',tz,'local_date',r.admitted_local_date::text,'media',media);
 IF octet_length(context::text)>2097152 THEN RETURN '{"action":"media_unavailable"}';END IF;
 RETURN context;
END $$;
CREATE FUNCTION public.capture_conversation_intake_source(p_user_id uuid,p_intake_id uuid,p_input_hash text,p_expected_epoch uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;context jsonb;old private.conversation_intake_sources%ROWTYPE;h text;
BEGIN
 gate:=private.lock_conversation_intake(p_user_id,p_intake_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 context:=private.conversation_intake_context(p_user_id,p_intake_id);IF context ? 'action' THEN RETURN context;END IF;
 SELECT * INTO old FROM private.conversation_intake_sources WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF FOUND THEN
  IF old.context-'captured_at' IS DISTINCT FROM context-'captured_at' THEN RETURN '{"action":"media_unavailable"}';END IF;
  RETURN jsonb_build_object('action','replay','source_hash',old.source_hash,'context',old.context);
 END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex');
 INSERT INTO private.conversation_intake_sources VALUES(p_user_id,p_intake_id,h,context);
 RETURN jsonb_build_object('action','captured','source_hash',h,'context',context);
END $$;
CREATE FUNCTION public.claim_conversation_intake_routing(p_user_id uuid,p_intake_id uuid,p_input_hash text,p_expected_epoch uuid,p_source_hash text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_intake_sources%ROWTYPE;fresh jsonb;claim uuid;
BEGIN
 gate:=private.lock_conversation_intake(p_user_id,p_intake_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO s FROM private.conversation_intake_sources WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF s.source_hash IS DISTINCT FROM p_source_hash THEN RETURN '{"action":"source_conflict"}';END IF;
 fresh:=private.conversation_intake_context(p_user_id,p_intake_id);IF fresh ? 'action' THEN RETURN fresh;END IF;
 IF s.context-'captured_at' IS DISTINCT FROM fresh-'captured_at' THEN RETURN '{"action":"source_conflict"}';END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_intake_claims WHERE user_id=p_user_id AND intake_id=p_intake_id) THEN RETURN '{"action":"already_claimed"}';END IF;
 claim:=gen_random_uuid();INSERT INTO private.conversation_intake_claims VALUES(p_user_id,p_intake_id,claim);
 RETURN jsonb_build_object('action','claimed','claim_id',claim);
END $$;
CREATE FUNCTION public.seal_conversation_intake_routing(p_user_id uuid,p_intake_id uuid,p_input_hash text,p_expected_epoch uuid,p_source_hash text,p_claim_id uuid,p_decision jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;c private.conversation_intake_ids%ROWTYPE;s private.conversation_intake_sources%ROWTYPE;old private.conversation_intake_selections%ROWTYPE;
 actual_claim uuid;fresh jsonb;h text;raw jsonb;typed jsonb;child jsonb:=NULL;selection jsonb;selected_at timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_intake_decision(p_decision);
 gate:=private.lock_conversation_intake(p_user_id,p_intake_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=p_intake_id;
 SELECT * INTO s FROM private.conversation_intake_sources WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF s.source_hash IS DISTINCT FROM p_source_hash THEN RETURN '{"action":"source_conflict"}';END IF;
 SELECT claim_id INTO actual_claim FROM private.conversation_intake_claims WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF actual_claim IS NULL OR actual_claim IS DISTINCT FROM p_claim_id THEN RETURN '{"action":"claim_conflict"}';END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_decision),'UTF8')),'hex');
 SELECT * INTO old FROM private.conversation_intake_selections WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF FOUND THEN
  IF old.decision_hash IS DISTINCT FROM h OR old.selection->'decision' IS DISTINCT FROM p_decision THEN RETURN '{"action":"decision_conflict"}';END IF;
  RETURN jsonb_build_object('action','replay','selection',old.selection);
 END IF;
 fresh:=private.conversation_intake_context(p_user_id,p_intake_id);IF fresh ? 'action' THEN RETURN fresh;END IF;
 IF s.context-'captured_at' IS DISTINCT FROM fresh-'captured_at' THEN RETURN '{"action":"source_conflict"}';END IF;
 IF p_decision->>'kind' IN('meal.report','workout.report') AND s.context#>>'{source_input,source,channel}'='media' THEN RETURN '{"action":"media_projection_required"}';END IF;
 -- Internal exception rolls back the REAL typed admission if any later fence
 -- fails. Never return a refusal out of this block after creating a child.
 BEGIN
  IF p_decision->>'kind' IN('meal.report','workout.report') THEN
   IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=c.reserved_child_id)
   OR EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=c.reserved_child_id) THEN RETURN '{"action":"input_conflict"}';END IF;
   raw:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',c.reserved_child_id,'kind',p_decision->>'kind','source',s.context#>'{source_input,source}');
   IF p_decision->>'kind'='meal.report' AND s.context#>'{source_input,meal_type_hint}' IS NOT NULL THEN raw:=raw||jsonb_build_object('meal_type',s.context#>'{source_input,meal_type_hint}');END IF;
   IF p_decision->>'kind'='meal.report' THEN typed:=public.admit_conversation_meal_command_fenced(p_user_id,raw,p_expected_epoch);
   ELSE typed:=public.admit_conversation_workout_command(p_user_id,p_expected_epoch,raw);END IF;
   IF typed->>'action' IS DISTINCT FROM 'admitted' THEN
    gate:=CASE WHEN typed->>'action' IN('rate_limited','stale_epoch','input_conflict') THEN typed->>'action' ELSE 'input_conflict' END;
    RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE=gate;
   END IF;
   child:=jsonb_build_object('kind',p_decision->>'kind','owner_id',p_user_id,'command_id',c.reserved_child_id,'input_hash',typed#>>'{command,input_hash}','epoch',p_expected_epoch,'admitted_at',typed#>>'{command,admitted_at}','input',raw);
   IF (child->>'admitted_at')::timestamptz<c.admitted_at OR child->>'input_hash' IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex') THEN RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE='input_conflict';END IF;
  END IF;
  gate:=private.lock_conversation_intake(p_user_id,p_intake_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE=gate;END IF;
  fresh:=private.conversation_intake_context(p_user_id,p_intake_id);
  IF fresh ? 'action' THEN RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE=fresh->>'action';END IF;
  IF s.context-'captured_at' IS DISTINCT FROM fresh-'captured_at' THEN RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE='source_conflict';END IF;
  selected_at:=clock_timestamp();
  IF (selected_at AT TIME ZONE (s.context->>'time_zone'))::date IS DISTINCT FROM (s.context->>'local_date')::date THEN RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE='day_changed';END IF;
  IF child IS NOT NULL AND selected_at<(child->>'admitted_at')::timestamptz THEN RAISE EXCEPTION USING ERRCODE='PI001',MESSAGE='day_changed';END IF;
  selection:=jsonb_build_object('schema','conversation.intake-selection.v1','intake',private.conversation_intake_binding(c),'source_hash',s.source_hash,'decision_hash',h,'decision',p_decision,'selected_at',private.conversation_intake_clock(selected_at),'command',child);
  INSERT INTO private.conversation_intake_selections VALUES(p_user_id,p_intake_id,h,selection);
 EXCEPTION WHEN SQLSTATE 'PI001' THEN GET STACKED DIAGNOSTICS gate=MESSAGE_TEXT;RETURN jsonb_build_object('action',gate);
 END;
 RETURN jsonb_build_object('action','sealed','selection',selection);
END $$;
CREATE FUNCTION public.read_conversation_intake(p_user_id uuid,p_intake_id uuid,p_input_hash text,p_expected_epoch uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;raw jsonb;s private.conversation_intake_sources%ROWTYPE;selection jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM p_expected_epoch
 OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id AND epoch=c.epoch)
 OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}';END IF;
 SELECT source_input INTO raw FROM private.conversation_intake_inputs WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"stale_epoch"}';END IF;
 SELECT * INTO s FROM private.conversation_intake_sources WHERE user_id=p_user_id AND intake_id=p_intake_id;
 SELECT x.selection INTO selection FROM private.conversation_intake_selections x WHERE user_id=p_user_id AND intake_id=p_intake_id;
 RETURN jsonb_build_object('action','available','intake',private.conversation_intake_binding(c),'source_input',raw,'source_hash',s.source_hash,'claimed',EXISTS(SELECT 1 FROM private.conversation_intake_claims WHERE user_id=p_user_id AND intake_id=p_intake_id),'selection',selection);
END $$;
REVOKE ALL ON FUNCTION private.conversation_intake_immutable(),private.scrub_conversation_intake_on_epoch(),private.conversation_intake_namespace_fence(),private.assert_conversation_intake_input(jsonb),private.assert_conversation_intake_decision(jsonb),private.conversation_intake_clock(timestamptz),private.conversation_intake_binding(private.conversation_intake_ids),private.lock_conversation_intake(uuid,uuid,text,uuid),private.conversation_intake_context(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.admit_conversation_intake(uuid,uuid,jsonb),public.capture_conversation_intake_source(uuid,uuid,text,uuid),public.claim_conversation_intake_routing(uuid,uuid,text,uuid,text),public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb),public.read_conversation_intake(uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_conversation_intake(uuid,uuid,jsonb),public.capture_conversation_intake_source(uuid,uuid,text,uuid),public.claim_conversation_intake_routing(uuid,uuid,text,uuid,text),public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb),public.read_conversation_intake(uuid,uuid,text,uuid) TO service_role;
COMMIT;

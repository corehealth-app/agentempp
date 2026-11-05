-- INERT DESIGN PROTOTYPE, NOT A MIGRATION, NOT EXECUTED OR RUNTIME-QUALIFIED.
-- First foundation only: permanent identity, sealed source and effect storage.
-- There is intentionally no commit_conversation_workout implementation here.
-- A new atomic core must first qualify NULL-energy coverage, strength anchors,
-- existing ledger/rollups and independent semantic validation (see companion doc).
-- No application/default route imports or applies this file.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'workout_conversation_requires_postgres' USING ERRCODE='42501'; END IF;
 IF to_regclass('private.conversation_workout_command_ids') IS NOT NULL
  OR to_regclass('private.conversation_workout_sources') IS NOT NULL
  OR to_regclass('private.conversation_workout_preparations') IS NOT NULL
  OR to_regclass('private.conversation_workout_effects') IS NOT NULL THEN
  RAISE EXCEPTION 'workout_conversation_unknown_existing_object' USING ERRCODE='42P07'; END IF;
 IF to_regclass('private.conversation_meal_command_ids') IS NULL
  OR to_regclass('private.workout_strength_authority_epochs') IS NULL
  OR to_regclass('public.media_assets') IS NULL
  OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  OR to_regprocedure('private.lock_conversation_command_owner(uuid)') IS NULL
  OR to_regprocedure('private.conversation_command_canonical(jsonb)') IS NULL
  OR to_regprocedure('private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'workout_conversation_missing_substrate' USING ERRCODE='42P01'; END IF;
END $preflight$;

CREATE TABLE private.conversation_workout_command_ids (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 command_id uuid NOT NULL,input_hash text COLLATE "C" NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 command_protocol text NOT NULL CHECK(command_protocol='conversation.command.v1'),
 kind text NOT NULL CHECK(kind='workout.report'),epoch uuid NOT NULL,
 admitted_at timestamptz NOT NULL CHECK(isfinite(admitted_at)),
 invalidated_at timestamptz CHECK(isfinite(invalidated_at)),PRIMARY KEY(user_id,command_id)
);
CREATE TABLE private.conversation_workout_inputs (
 user_id uuid NOT NULL,command_id uuid NOT NULL,source_input jsonb NOT NULL CHECK(jsonb_typeof(source_input)='object'),
 PRIMARY KEY(user_id,command_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_workout_command_ids ON DELETE CASCADE
);
CREATE TABLE private.conversation_workout_sources (
 user_id uuid NOT NULL,command_id uuid NOT NULL,source_hash text COLLATE "C" NOT NULL CHECK(source_hash ~ '^[0-9a-f]{64}$'),
 context jsonb NOT NULL CHECK(jsonb_typeof(context)='object'),captured_at timestamptz NOT NULL CHECK(isfinite(captured_at)),
 PRIMARY KEY(user_id,command_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_workout_inputs ON DELETE CASCADE
);
CREATE TABLE private.conversation_workout_preparations (
 user_id uuid NOT NULL,command_id uuid NOT NULL,prepared_hash text COLLATE "C" NOT NULL CHECK(prepared_hash ~ '^[0-9a-f]{64}$'),
 prepared jsonb NOT NULL CHECK(jsonb_typeof(prepared)='object'),prepared_at timestamptz NOT NULL CHECK(isfinite(prepared_at)),
 PRIMARY KEY(user_id,command_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_workout_sources ON DELETE CASCADE
);
-- A receipt is historical. Undo may null the live link; it must not erase the
-- original identity/facts. Only the future qualified atomic core inserts here.
CREATE TABLE private.conversation_workout_effects (
 user_id uuid NOT NULL,command_id uuid NOT NULL,original_workout_id uuid NOT NULL,live_workout_id uuid,
 receipt jsonb NOT NULL CHECK(jsonb_typeof(receipt)='object'
  AND receipt->>'schema'='conversation.workout-effect.v1'
  AND receipt->>'provenance'='conversation.workout.v1'
  AND receipt->>'owner_id'=user_id::text AND receipt->>'command_id'=command_id::text),
 original_facts jsonb NOT NULL CHECK(jsonb_typeof(original_facts)='object'),recorded_at timestamptz NOT NULL CHECK(isfinite(recorded_at)),
 PRIMARY KEY(user_id,command_id),UNIQUE(user_id,original_workout_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_workout_preparations ON DELETE CASCADE,
 FOREIGN KEY(user_id,live_workout_id) REFERENCES public.workout_logs(user_id,id) ON DELETE SET NULL(live_workout_id)
);
ALTER TABLE private.conversation_workout_command_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_workout_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_workout_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_workout_preparations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_workout_effects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.conversation_workout_command_ids,private.conversation_workout_inputs,
 private.conversation_workout_sources,private.conversation_workout_preparations,private.conversation_workout_effects
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.conversation_workout_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_TABLE_NAME='conversation_workout_command_ids' THEN
  IF OLD.invalidated_at IS NULL AND NEW.invalidated_at IS NOT NULL AND to_jsonb(OLD)-'invalidated_at'=to_jsonb(NEW)-'invalidated_at' THEN RETURN NEW; END IF;
 ELSIF TG_TABLE_NAME='conversation_workout_effects' THEN
  IF OLD.live_workout_id IS NOT NULL AND NEW.live_workout_id IS NULL AND to_jsonb(OLD)-'live_workout_id'=to_jsonb(NEW)-'live_workout_id' THEN RETURN NEW; END IF;
 END IF;
 RAISE EXCEPTION 'conversation_workout_immutable' USING ERRCODE='22023';
END $$;
CREATE TRIGGER conversation_workout_ids_immutable BEFORE UPDATE ON private.conversation_workout_command_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_immutable();
CREATE TRIGGER conversation_workout_inputs_immutable BEFORE UPDATE ON private.conversation_workout_inputs FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_immutable();
CREATE TRIGGER conversation_workout_source_immutable BEFORE UPDATE ON private.conversation_workout_sources FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_immutable();
CREATE TRIGGER conversation_workout_prepared_immutable BEFORE UPDATE ON private.conversation_workout_preparations FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_immutable();
CREATE TRIGGER conversation_workout_effect_immutable BEFORE UPDATE ON private.conversation_workout_effects FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_immutable();

-- Same generic cmsg1 UUID cannot be retyped into a meal or workout. Both
-- admissions already share the :workouts owner lane; this also fences direct
-- privileged inserts and the reverse (workout -> meal) collision.
CREATE FUNCTION private.conversation_workout_kind_fence() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id::text||':workouts',0));
 IF TG_TABLE_NAME='conversation_workout_command_ids' THEN
  IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=NEW.user_id AND command_id=NEW.command_id) THEN RAISE EXCEPTION 'conversation_command_kind_conflict' USING ERRCODE='23505'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=NEW.user_id AND command_id=NEW.command_id) THEN RAISE EXCEPTION 'conversation_command_kind_conflict' USING ERRCODE='23505'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_workout_kind_fence BEFORE INSERT ON private.conversation_workout_command_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_kind_fence();
CREATE TRIGGER conversation_meal_workout_kind_fence BEFORE INSERT ON private.conversation_meal_command_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_kind_fence();

CREATE FUNCTION private.assert_conversation_workout_input(v jsonb) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE s jsonb:=v->'source';
BEGIN
 IF v IS NULL OR jsonb_typeof(v)<>'object' OR NOT(v ?& ARRAY['command_protocol','command_id','kind','source'])
  OR v-ARRAY['command_protocol','command_id','kind','source']<>'{}'::jsonb
  OR v->>'command_protocol' IS DISTINCT FROM 'conversation.command.v1' OR v->>'kind' IS DISTINCT FROM 'workout.report'
  OR jsonb_typeof(v->'command_id') IS DISTINCT FROM 'string'
  OR NOT coalesce((v->>'command_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false)
  OR jsonb_typeof(s) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid_conversation_workout' USING ERRCODE='22023'; END IF;
 IF s->>'channel'='text' THEN
  IF s-ARRAY['channel','text']<>'{}'::jsonb OR NOT private.conversation_command_text_valid(s->'text',2000) THEN RAISE EXCEPTION 'invalid_conversation_workout' USING ERRCODE='22023'; END IF;
 ELSIF s->>'channel'='media' THEN
  IF NOT(s ?& ARRAY['channel','media_asset_id','user_action']) OR s-ARRAY['channel','media_asset_id','user_action','caption']<>'{}'::jsonb
   OR s->>'user_action' IS DISTINCT FROM 'register_performed_workout'
   OR jsonb_typeof(s->'media_asset_id') IS DISTINCT FROM 'string'
   OR NOT coalesce((s->>'media_asset_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false)
   OR (s ? 'caption' AND NOT private.conversation_command_text_valid(s->'caption',1000)) THEN RAISE EXCEPTION 'invalid_conversation_workout' USING ERRCODE='22023'; END IF;
 ELSE RAISE EXCEPTION 'invalid_conversation_workout' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION public.admit_conversation_workout_command(p_user_id uuid,p_expected_epoch uuid,p_input jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;e uuid;h text;id uuid;action text:='replay';
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_workout_input(p_input);PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF e IS NULL OR e IS DISTINCT FROM p_expected_epoch THEN RETURN '{"action":"stale_epoch"}'; END IF;
 id:=(p_input->>'command_id')::uuid;h:=encode(sha256(convert_to(private.conversation_command_canonical(p_input),'UTF8')),'hex');
 SELECT * INTO c FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=id FOR UPDATE;
 IF FOUND THEN
  IF c.epoch IS DISTINCT FROM e OR c.invalidated_at IS NOT NULL THEN RETURN '{"action":"stale_epoch"}'; END IF;
  IF c.input_hash IS DISTINCT FROM h THEN RETURN '{"action":"input_conflict"}'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=id) THEN RETURN '{"action":"input_conflict"}'; END IF;
  INSERT INTO private.conversation_workout_command_ids VALUES(p_user_id,id,h,'conversation.command.v1','workout.report',e,clock_timestamp(),NULL) RETURNING * INTO c;
  INSERT INTO private.conversation_workout_inputs VALUES(p_user_id,id,p_input);action:='admitted';
 END IF;
 RETURN jsonb_build_object('action',action,'command',jsonb_build_object('owner_id',c.user_id,'command_id',c.command_id,'input_hash',c.input_hash,'epoch',c.epoch,'admitted_at',to_char(c.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $$;

CREATE FUNCTION public.capture_conversation_workout_source(p_user_id uuid,p_command_id uuid,p_input_hash text,p_expected_epoch uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;old private.conversation_workout_sources%ROWTYPE;e uuid;u public.users%ROWTYPE;
 input jsonb;clinical jsonb;context jsonb;catalogue jsonb;media jsonb:=NULL;m public.media_assets%ROWTYPE;observed timestamptz;day date;h text;
BEGIN
 PERFORM private.assert_trusted_backend();
 -- Match protected workout lock order; never obtain catalogue after owner lane.
 LOCK TABLE public.workout_types IN SHARE MODE NOWAIT;
 PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 SELECT * INTO c FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=p_command_id FOR UPDATE;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'; END IF;
 IF c.invalidated_at IS NOT NULL OR e IS DISTINCT FROM c.epoch OR e IS DISTINCT FROM p_expected_epoch THEN RETURN '{"action":"stale_epoch"}'; END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}'; END IF;
 SELECT * INTO old FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN RETURN jsonb_build_object('source_hash',old.source_hash,'context',old.context); END IF;
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user_id;SELECT source_input INTO STRICT input FROM private.conversation_workout_inputs WHERE user_id=p_user_id AND command_id=p_command_id;
 IF input#>>'{source,channel}'='media' THEN
  SELECT * INTO m FROM public.media_assets WHERE user_id=p_user_id AND id=(input#>>'{source,media_asset_id}')::uuid FOR SHARE NOWAIT;
  IF NOT FOUND OR m.status<>'processed' OR m.kind NOT IN('gym_photo','audio_note') OR m.processed_at IS NULL OR m.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'workout_media_unavailable' USING ERRCODE='40001'; END IF;
  IF jsonb_typeof(m.processing_result) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'workout_media_unavailable' USING ERRCODE='55000'; END IF;
  IF octet_length(m.processing_result::text)>1048576 THEN RAISE EXCEPTION 'workout_media_too_large' USING ERRCODE='54000'; END IF;
  IF m.kind='audio_note' AND NOT private.conversation_command_text_valid(m.processing_result->'text',2000) THEN RAISE EXCEPTION 'workout_transcript_unavailable' USING ERRCODE='55000'; END IF;
  media:=jsonb_build_object('asset_id',m.id,'owner_id',m.user_id,'kind',m.kind,'status',m.status,'processed_at',m.processed_at,'updated_at',m.updated_at,'context_text',m.context_text,'processing_result',m.processing_result);
 END IF;
 observed:=clock_timestamp();clinical:=private.capture_mobile_current_clinical_state_at(p_user_id,'profile',NULL,NULL,observed);
 day:=(c.admitted_at AT TIME ZONE u.timezone)::date;
 IF (clinical->>'epoch')::uuid IS DISTINCT FROM c.epoch OR (clinical->>'date')::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'workout_source_clock_or_epoch_changed' USING ERRCODE='40001'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':'||day::text,0)) THEN RAISE EXCEPTION 'workout_day_busy' USING ERRCODE='55P03'; END IF;
 PERFORM 1 FROM public.daily_snapshots WHERE user_id=p_user_id AND date=day AND day_closed FOR SHARE NOWAIT;
 IF FOUND THEN RETURN '{"action":"day_closed"}'; END IF;
 IF EXISTS(SELECT 1 FROM public.workout_types WHERE is_active AND (updated_at IS NULL OR NOT isfinite(updated_at))) THEN RAISE EXCEPTION 'workout_catalogue_incomplete' USING ERRCODE='55000'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'slug',w.slug,'display_name',w.display_name,'is_active',true,'updated_at',w.updated_at) ORDER BY w.id),'[]') INTO catalogue FROM public.workout_types w WHERE w.is_active;
 IF jsonb_array_length(catalogue)>2048 THEN RAISE EXCEPTION 'workout_catalogue_too_large' USING ERRCODE='54000'; END IF;
 context:=jsonb_build_object('schema','conversation.workout-source.v1','owner_id',p_user_id,'command_id',p_command_id,'input_hash',c.input_hash,'epoch',c.epoch,'source_input',input,'admitted_at',c.admitted_at,'captured_at',observed,'clinical',clinical,'day_closed',false,'media',media,'catalogue',catalogue);
 h:=encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex');
 INSERT INTO private.conversation_workout_sources VALUES(p_user_id,p_command_id,h,context,observed);
 RETURN jsonb_build_object('source_hash',h,'context',context);
END $$;

-- Read contract consumed by the dormant one-write/one-read adapter. No source
-- recapture, epoch initialization, registration, reward, seal or repair on GET.
CREATE FUNCTION public.read_conversation_workout_effect(p_user_id uuid,p_command_id uuid,p_input_hash text,p_source_hash text,p_expected_epoch uuid,p_prepared_hash text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;effect private.conversation_workout_effects%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"stale_epoch"}'; END IF;
 SELECT * INTO c FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'; END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM p_expected_epoch OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id AND epoch=c.epoch) THEN RETURN '{"action":"stale_epoch"}'; END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id AND source_hash=p_source_hash) THEN RETURN '{"action":"source_conflict"}'; END IF;
 SELECT * INTO effect FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'; END IF;
 IF effect.receipt->>'prepared_hash' IS DISTINCT FROM p_prepared_hash THEN RETURN '{"action":"prepared_conflict"}'; END IF;
 RETURN jsonb_build_object('action','available','receipt',effect.receipt,'original_facts',effect.original_facts);
END $$;
REVOKE ALL ON FUNCTION private.conversation_workout_immutable(),private.conversation_workout_kind_fence(),private.assert_conversation_workout_input(jsonb),
 public.admit_conversation_workout_command(uuid,uuid,jsonb),public.capture_conversation_workout_source(uuid,uuid,text,uuid),public.read_conversation_workout_effect(uuid,uuid,text,text,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
-- No EXECUTE grant or capability switch in this prototype.
COMMIT;

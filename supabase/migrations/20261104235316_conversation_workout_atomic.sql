-- Concrete backend workout commands with independent performed authority.
-- No capability/HTTP/native cutover; legacy workout/UI writers remain unchanged.
-- Nullable log energy is preserved; snapshot sum is marked incomplete explicitly.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'workout_conversation_requires_postgres' USING ERRCODE='42501'; END IF;
 IF to_regclass('private.conversation_workout_command_ids') IS NOT NULL
  OR to_regclass('private.conversation_workout_sources') IS NOT NULL
  OR to_regclass('private.conversation_workout_preparations') IS NOT NULL
  OR to_regclass('private.conversation_workout_effects') IS NOT NULL
  OR to_regclass('private.mobile_clinical_unknown_exercise_evidence') IS NOT NULL THEN
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
-- original identity/facts. Only the owned atomic core inserts here.
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
CREATE FUNCTION private.conversation_workout_admission_count(p_user uuid,p_epoch uuid,p_at timestamptz) RETURNS bigint LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT (SELECT count(*) FROM private.conversation_meal_command_ids WHERE user_id=p_user AND epoch=p_epoch AND admitted_at>=p_at-interval '60 seconds')+
 (SELECT count(*) FROM private.conversation_workout_command_ids WHERE user_id=p_user AND epoch=p_epoch AND admitted_at>=p_at-interval '60 seconds');
$$;
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
  IF private.conversation_workout_admission_count(p_user_id,e,clock_timestamp())>=10 THEN RETURN '{"action":"rate_limited"}'; END IF;
  INSERT INTO private.conversation_workout_command_ids VALUES(p_user_id,id,h,'conversation.command.v1','workout.report',e,clock_timestamp(),NULL) RETURNING * INTO c;
  INSERT INTO private.conversation_workout_inputs VALUES(p_user_id,id,p_input);action:='admitted';
 END IF;
 RETURN jsonb_build_object('action',action,'command',jsonb_build_object('owner_id',c.user_id,'command_id',c.command_id,'input_hash',c.input_hash,'epoch',c.epoch,'admitted_at',to_char(c.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
END $$;

-- Coverage is metadata, never a new numeric formula or a ledger rewrite.
ALTER TABLE public.daily_snapshots ADD COLUMN exercise_energy_complete boolean NOT NULL DEFAULT true;
UPDATE public.daily_snapshots s SET exercise_energy_complete=false WHERE EXISTS(
 SELECT 1 FROM public.workout_logs w WHERE w.user_id=s.user_id AND w.snapshot_id=s.id AND w.estimated_kcal IS NULL);
COMMENT ON COLUMN public.daily_snapshots.exercise_energy_complete IS 'False means exercise_calories is only a known partial sum; do not publish derived energy or grant energy credit.';
-- Existing immutable close bindings predate coverage. Retain an additive,
-- immutable witness only where an actual owned NULL row proves unavailable
-- energy at migration. A later NULL -> known zero must not revive that old
-- arithmetic merely by restoring its numeric binding. No old evidence,
-- receipt, progress or closed ledger is rewritten.
CREATE TABLE private.mobile_clinical_unknown_exercise_evidence (
 snapshot_id uuid PRIMARY KEY REFERENCES private.mobile_clinical_closed_day_evidence(snapshot_id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 snapshot_binding_sha256 text NOT NULL CHECK(snapshot_binding_sha256 ~ '^[0-9a-f]{64}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.mobile_clinical_unknown_exercise_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_unknown_exercise_evidence FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.mobile_clinical_unknown_exercise_evidence(snapshot_id,user_id,snapshot_binding_sha256)
 SELECT d.id,d.user_id,encode(sha256(convert_to(e.snapshot_binding::text,'UTF8')),'hex')
 FROM public.daily_snapshots d JOIN private.mobile_clinical_closed_day_evidence e ON e.snapshot_id=d.id AND e.user_id=d.user_id
 WHERE d.day_closed AND NOT d.exercise_energy_complete AND EXISTS(
  SELECT 1 FROM public.workout_logs w WHERE w.user_id=d.user_id AND w.snapshot_id=d.id AND w.estimated_kcal IS NULL);
CREATE TRIGGER mobile_clinical_unknown_exercise_evidence_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_unknown_exercise_evidence FOR EACH ROW
 EXECUTE FUNCTION private.mobile_clinical_closed_day_evidence_immutable();
COMMENT ON TABLE private.mobile_clinical_unknown_exercise_evidence IS 'Immutable unavailable-at-migration witness for exact existing closed evidence with owned NULL workout energy; receipt and ledger unchanged.';
CREATE FUNCTION private.refresh_conversation_workout_energy() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE ids uuid[];snapshot uuid;known integer;complete boolean;owner uuid;
BEGIN
 IF TG_OP='INSERT' THEN ids:=ARRAY[NEW.snapshot_id];owner:=NEW.user_id;
 ELSIF TG_OP='DELETE' THEN ids:=ARRAY[OLD.snapshot_id];owner:=OLD.user_id;
 ELSE ids:=ARRAY[OLD.snapshot_id,NEW.snapshot_id];owner:=NEW.user_id;
  IF OLD.user_id IS DISTINCT FROM NEW.user_id THEN RAISE EXCEPTION 'workout_owner_immutable' USING ERRCODE='22023';END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(owner::text||':workouts',0));
 FOR snapshot IN SELECT DISTINCT x FROM unnest(ids) x WHERE x IS NOT NULL ORDER BY x LOOP
  SELECT coalesce(sum(estimated_kcal),0)::integer,coalesce(bool_and(estimated_kcal IS NOT NULL),true) INTO known,complete FROM public.workout_logs WHERE user_id=owner AND snapshot_id=snapshot;
  UPDATE public.daily_snapshots SET exercise_calories=known,exercise_energy_complete=complete,
   training_done=EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=owner AND snapshot_id=snapshot),updated_at=clock_timestamp()
   -- Membership and duration/type edits also invalidate the reader latch when
   -- both workouts have NULL/zero energy and these scalar aggregates are equal.
   WHERE user_id=owner AND id=snapshot;
 END LOOP;
 RETURN coalesce(NEW,OLD);
END $$;
CREATE TRIGGER conversation_workout_energy_refresh AFTER INSERT OR UPDATE OR DELETE ON public.workout_logs FOR EACH ROW EXECUTE FUNCTION private.refresh_conversation_workout_energy();

CREATE FUNCTION private.conversation_workout_clock(t timestamptz) RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT to_char(t AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
$$;
CREATE FUNCTION private.lock_conversation_workout(p_user uuid,p_command uuid,p_hash text,p_epoch uuid) RETURNS text LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;e uuid;
BEGIN
 PERFORM private.assert_trusted_backend();LOCK TABLE public.workout_types IN SHARE MODE NOWAIT;
 PERFORM private.lock_conversation_command_owner(p_user);
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user FOR UPDATE;
 SELECT * INTO c FROM private.conversation_workout_command_ids WHERE user_id=p_user AND command_id=p_command FOR UPDATE;
 IF NOT FOUND THEN RETURN 'absent';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e OR e IS DISTINCT FROM p_epoch THEN RETURN 'stale_epoch';END IF;
 IF c.input_hash IS DISTINCT FROM p_hash THEN RETURN 'input_conflict';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.conversation_workout_inputs WHERE user_id=p_user AND command_id=p_command) THEN RETURN 'stale_epoch';END IF;
 RETURN 'current';
END $$;
CREATE FUNCTION private.conversation_workout_source_at(p_user uuid,p_command uuid,p_observed timestamptz DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;u public.users%ROWTYPE;m public.media_assets%ROWTYPE;
 input jsonb;clinical jsonb;catalogue jsonb;media jsonb:=NULL;observed timestamptz;day date;
BEGIN
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 SELECT * INTO STRICT c FROM private.conversation_workout_command_ids WHERE user_id=p_user AND command_id=p_command;
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user;
 SELECT source_input INTO STRICT input FROM private.conversation_workout_inputs WHERE user_id=p_user AND command_id=p_command;
 observed:=coalesce(p_observed,clock_timestamp());clinical:=private.capture_mobile_current_clinical_state_at(p_user,'profile',NULL,NULL,observed);
 day:=(c.admitted_at AT TIME ZONE u.timezone)::date;
 IF (clinical->>'epoch')::uuid IS DISTINCT FROM c.epoch OR (clinical->>'date')::date IS DISTINCT FROM day OR (clock_timestamp() AT TIME ZONE u.timezone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'workout_source_clock_or_epoch_changed' USING ERRCODE='40001';END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user::text||':'||day::text,0)) THEN RAISE EXCEPTION 'workout_day_busy' USING ERRCODE='55P03';END IF;
 PERFORM 1 FROM public.daily_snapshots WHERE user_id=p_user AND date=day AND day_closed FOR SHARE NOWAIT;
 IF FOUND THEN RETURN jsonb_build_object('day_closed',true);END IF;
 IF input#>>'{source,channel}'='media' THEN
  SELECT * INTO m FROM public.media_assets WHERE user_id=p_user AND id=(input#>>'{source,media_asset_id}')::uuid FOR SHARE NOWAIT;
  IF NOT FOUND OR m.status<>'processed' OR m.kind NOT IN('gym_photo','audio_note') OR m.processed_at IS NULL OR m.deleted_at IS NOT NULL OR jsonb_typeof(m.processing_result) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'workout_media_unavailable' USING ERRCODE='40001';END IF;
  IF m.processed_at>observed OR m.updated_at>observed THEN RAISE EXCEPTION 'workout_media_future_observation' USING ERRCODE='40001';END IF;
  IF octet_length(m.processing_result::text)>1048576 THEN RAISE EXCEPTION 'workout_media_too_large' USING ERRCODE='54000';END IF;
  IF m.kind='audio_note' AND NOT private.conversation_command_text_valid(m.processing_result->'text',2000) THEN RAISE EXCEPTION 'workout_transcript_unavailable' USING ERRCODE='55000';END IF;
  IF input#>>'{source,caption}' IS NOT NULL AND nullif(btrim(m.context_text),'') IS NOT NULL AND input#>>'{source,caption}' IS DISTINCT FROM m.context_text THEN RAISE EXCEPTION 'workout_media_caption_conflict' USING ERRCODE='40001';END IF;
  media:=jsonb_build_object('asset_id',m.id,'owner_id',m.user_id,'kind',m.kind,'status',m.status,'processed_at',private.conversation_workout_clock(m.processed_at),'updated_at',private.conversation_workout_clock(m.updated_at),'context_text',m.context_text,'processing_result',m.processing_result);
 END IF;
 IF EXISTS(SELECT 1 FROM public.workout_types WHERE is_active AND (updated_at IS NULL OR NOT isfinite(updated_at) OR updated_at>observed)) THEN RAISE EXCEPTION 'workout_catalogue_incomplete' USING ERRCODE='55000';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'slug',w.slug,'display_name',w.display_name,'is_active',true,'updated_at',private.conversation_workout_clock(w.updated_at),'category',w.category,'kcal_per_min',w.kcal_per_min) ORDER BY w.id),'[]') INTO catalogue FROM public.workout_types w WHERE w.is_active;
 IF jsonb_array_length(catalogue)>2048 THEN RAISE EXCEPTION 'workout_catalogue_too_large' USING ERRCODE='54000';END IF;
 RETURN jsonb_build_object('schema','conversation.workout-source.v1','owner_id',p_user,'command_id',p_command,'input_hash',c.input_hash,'epoch',c.epoch,'source_input',input,'admitted_at',private.conversation_workout_clock(c.admitted_at),'captured_at',private.conversation_workout_clock(observed),'clinical',clinical,'day_closed',false,'media',media,'catalogue',catalogue);
END $$;
CREATE FUNCTION private.conversation_workout_source_binding(c jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT (c-'captured_at'-'clinical')||jsonb_build_object('clinical',(c->'clinical')-'observed_at'-'context_hash' #- '{safety,observed_at}');
$$;
CREATE FUNCTION public.capture_conversation_workout_source(p_user_id uuid,p_command_id uuid,p_input_hash text,p_expected_epoch uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;old private.conversation_workout_sources%ROWTYPE;context jsonb;h text;
BEGIN
 gate:=private.lock_conversation_workout(p_user_id,p_command_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO old FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN RETURN jsonb_build_object('source_hash',old.source_hash,'context',old.context);END IF;
 context:=private.conversation_workout_source_at(p_user_id,p_command_id);
 IF context->'day_closed'='true'::jsonb THEN RETURN '{"action":"day_closed"}';END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(context),'UTF8')),'hex');
 INSERT INTO private.conversation_workout_sources VALUES(p_user_id,p_command_id,h,context,(context->>'captured_at')::timestamptz);
 RETURN jsonb_build_object('source_hash',h,'context',context);
END $$;

-- Executable complete-clause guard, independently reconstructed from stored
-- source by SQL. Caller-supplied performed flags, spans or kcal are not proof.
CREATE FUNCTION private.conversation_workout_report(c jsonb,h text) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE src jsonb:=c->'source_input';units jsonb:='[]';unit jsonb;evidence jsonb:='[]';base jsonb;v text;n text;parts text[];rows jsonb;selected jsonb;activity jsonb:=NULL;next jsonb;minutes integer;missing boolean:=false;field text;answer jsonb;
BEGIN
 base:=jsonb_build_object('owner_id',c->'owner_id','command_id',c->'command_id','input_hash',c->'input_hash','source_hash',h,'epoch',c->'epoch');
 IF src#>>'{source,channel}'='text' THEN units:=jsonb_build_array(jsonb_build_object('unit','command_text','text',src#>>'{source,text}'));
 ELSE
  v:=coalesce(src#>>'{source,caption}',c#>>'{media,context_text}');IF nullif(btrim(v),'') IS NOT NULL THEN units:=units||jsonb_build_array(jsonb_build_object('unit','media_caption','text',v));END IF;
  IF c#>>'{media,kind}'='audio_note' THEN units:=units||jsonb_build_array(jsonb_build_object('unit','media_transcript','text',c#>>'{media,processing_result,text}'));END IF;
 END IF;
 field:='activity';
 IF jsonb_array_length(units)>0 THEN
  FOR unit IN SELECT value FROM jsonb_array_elements(units) LOOP
   v:=lower(public.f_unaccent(regexp_replace(btrim(unit->>'text'),'\s+',' ','g')));
   IF v ~ '\?' OR v ~ '\m(nao|nunca|amanha|ontem|sempre|costumo|faco|fazia|farei|faria|vou|iria|se|sonh[a-z]*|pai|mae|ele|ela|voce|voces|todos|toda|todo|semanalmente|diariamente)\M' THEN RETURN base||jsonb_build_object('status','not_reported','reason','non_performed_or_conflicting_source');END IF;
   parts:=regexp_match(v,'^(?:eu )?(?:fiz|realizei) (?:(\d{1,4}) (?:min|minuto|minutos) de )?([[:alpha:] _-]+?)(?: (leve|moderada|alta))?[.!]?$');
   IF parts IS NULL THEN EXIT;END IF;
   n:=parts[2];
   SELECT coalesce(jsonb_agg(x),'[]') INTO rows FROM jsonb_array_elements(c->'catalogue') x WHERE lower(public.f_unaccent(replace(x->>'slug','_',' ')))=n OR lower(public.f_unaccent(x->>'display_name'))=n;
   IF jsonb_array_length(rows)<>1 THEN EXIT;END IF;selected:=rows->0;
   IF selected->>'slug'='outro' THEN EXIT;END IF;
   IF parts[3] IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(c->'catalogue') x WHERE lower(public.f_unaccent(replace(x->>'slug','_',' ')))=n||' '||parts[3] OR lower(public.f_unaccent(x->>'display_name'))=n||' '||parts[3]) THEN EXIT;END IF;
   IF parts[1] IS NULL THEN missing:=true;field:='duration_min';CONTINUE;END IF;
   minutes:=parts[1]::integer;IF minutes<1 OR minutes>1440 THEN field:='duration_min';EXIT;END IF;
   next:=jsonb_build_object('workout_type',selected->'slug','duration_min',minutes,'intensity',parts[3]);
   IF activity IS NOT NULL AND activity IS DISTINCT FROM next THEN activity:=NULL;EXIT;END IF;
   activity:=next;evidence:=evidence||jsonb_build_array(unit);
  END LOOP;
  IF NOT missing AND activity IS NOT NULL AND jsonb_array_length(evidence)=jsonb_array_length(units) THEN RETURN base||jsonb_build_object('status','ready','activity',activity,'evidence',evidence);END IF;
 END IF;
 answer:=jsonb_build_object('source_hash',h,'field',field);
 RETURN base||jsonb_build_object('status','needs_reply','question',jsonb_build_object('key',encode(sha256(convert_to(private.conversation_command_canonical(answer),'UTF8')),'hex'),'field',field,'text',CASE WHEN field='duration_min' THEN 'Quantos minutos durou essa atividade?' ELSE 'Qual atividade você realizou e por quantos minutos?' END));
END $$;
CREATE FUNCTION public.prepare_conversation_workout(p_user_id uuid,p_command_id uuid,p_input_hash text,p_source_hash text,p_expected_epoch uuid,p_report jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_workout_sources%ROWTYPE;p private.conversation_workout_preparations%ROWTYPE;fresh jsonb;report jsonb;prepared jsonb;energy jsonb;weight numeric;kcal integer:=NULL;selected public.workout_types%ROWTYPE;h text;
BEGIN
 gate:=private.lock_conversation_workout(p_user_id,p_command_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO s FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"source_required"}';END IF;
 IF s.source_hash IS DISTINCT FROM p_source_hash THEN RETURN '{"action":"source_conflict"}';END IF;
 report:=private.conversation_workout_report(s.context,s.source_hash);
 IF p_report IS DISTINCT FROM report THEN RETURN '{"action":"semantic_conflict"}';END IF;
 SELECT * INTO p FROM private.conversation_workout_preparations WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN RETURN jsonb_build_object('action','replay','prepared_hash',p.prepared_hash,'prepared',p.prepared);END IF;
 fresh:=private.conversation_workout_source_at(p_user_id,p_command_id);
 IF fresh->'day_closed'='true'::jsonb THEN RETURN '{"action":"day_closed"}';END IF;
 IF private.conversation_workout_source_binding(fresh) IS DISTINCT FROM private.conversation_workout_source_binding(s.context) THEN RETURN '{"action":"source_conflict"}';END IF;
 prepared:=report;
 IF report->>'status'='ready' THEN
  weight:=(s.context#>>'{clinical,body,weight_kg}')::numeric;
  SELECT * INTO STRICT selected FROM public.workout_types WHERE is_active AND slug=report#>>'{activity,workout_type}';
  IF weight IS NOT NULL AND report#>>'{activity,intensity}' IS NOT NULL AND selected.kcal_per_min IS NOT NULL THEN
   kcal:=public.calc_workout_kcal(selected.slug,(report#>>'{activity,duration_min}')::integer,report#>>'{activity,intensity}',weight);
   IF kcal IS NOT NULL AND (kcal<0 OR kcal>10000) THEN RAISE EXCEPTION 'workout_estimate_out_of_range' USING ERRCODE='22023';END IF;
  END IF;
  energy:=CASE WHEN kcal IS NULL THEN '{"status":"unavailable"}'::jsonb ELSE jsonb_build_object('status','available','source','calc_workout_kcal','weight_kg',trim_scale(weight)) END;
  prepared:=report||jsonb_build_object('activity',report->'activity'||jsonb_build_object('estimated_kcal',kcal),'performed_at',s.context->'admitted_at','local_date',s.context#>'{clinical,date}','time_zone',s.context#>'{clinical,timezone}','energy',energy);
 END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(prepared),'UTF8')),'hex');
 INSERT INTO private.conversation_workout_preparations VALUES(p_user_id,p_command_id,h,prepared,clock_timestamp());
 RETURN jsonb_build_object('action','prepared','prepared_hash',h,'prepared',prepared);
END $$;

CREATE TABLE private.conversation_workout_events(
 user_id uuid NOT NULL,command_id uuid NOT NULL,event_id uuid NOT NULL DEFAULT gen_random_uuid(),
 kind text NOT NULL CHECK(kind IN('prepared','registered','edit','undo_edit','undo_registration')),
 at timestamptz NOT NULL CHECK(isfinite(at)),body jsonb NOT NULL CHECK(jsonb_typeof(body)='object'),
 PRIMARY KEY(user_id,event_id),FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_workout_inputs ON DELETE CASCADE
);
CREATE INDEX conversation_workout_event_page ON private.conversation_workout_events(user_id,at DESC,event_id DESC);
ALTER TABLE private.conversation_workout_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_workout_events FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE private.conversation_workout_effects ADD COLUMN feedback_context jsonb;
CREATE FUNCTION public.commit_conversation_workout(p_user_id uuid,p_command_id uuid,p_input_hash text,p_source_hash text,p_expected_epoch uuid,p_prepared_hash text,p_prepared jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_workout_sources%ROWTYPE;p private.conversation_workout_preparations%ROWTYPE;e private.conversation_workout_effects%ROWTYPE;
 a private.workout_strength_authority_epochs%ROWTYPE;selected public.workout_types%ROWTYPE;w public.workout_logs%ROWTYPE;snap public.daily_snapshots%ROWTYPE;
 fresh jsonb;clock timestamptz;performed timestamptz;day date;zone text;life uuid;operation text;legacy jsonb;strength jsonb;receipt jsonb;facts jsonb;feedback jsonb;clinical jsonb;proposal jsonb;
BEGIN
 gate:=private.lock_conversation_workout(p_user_id,p_command_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO e FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN
  IF e.receipt->>'prepared_hash' IS DISTINCT FROM p_prepared_hash THEN RETURN '{"action":"prepared_conflict"}';END IF;
  RETURN jsonb_build_object('action','replay','receipt',e.receipt);
 END IF;
 SELECT * INTO p FROM private.conversation_workout_preparations WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"prepared_required"}';END IF;
 IF p.prepared_hash IS DISTINCT FROM p_prepared_hash OR p.prepared IS DISTINCT FROM p_prepared THEN RETURN '{"action":"prepared_conflict"}';END IF;
 IF p.prepared->>'status'<>'ready' THEN RETURN jsonb_build_object('action','not_ready','prepared',p.prepared);END IF;
 SELECT * INTO STRICT s FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 IF s.source_hash IS DISTINCT FROM p_source_hash THEN RETURN '{"action":"source_conflict"}';END IF;
 fresh:=private.conversation_workout_source_at(p_user_id,p_command_id);
 IF fresh->'day_closed'='true'::jsonb THEN RETURN '{"action":"day_closed"}';END IF;
 IF private.conversation_workout_source_binding(fresh) IS DISTINCT FROM private.conversation_workout_source_binding(s.context) THEN RETURN '{"action":"source_conflict"}';END IF;
 IF private.conversation_workout_report(s.context,s.source_hash) IS DISTINCT FROM (p.prepared-ARRAY['performed_at','local_date','time_zone','energy'] || jsonb_build_object('activity',(p.prepared->'activity')-'estimated_kcal')) THEN
  RAISE EXCEPTION 'workout_semantic_preparation_unproved' USING ERRCODE='22023';END IF;
 clock:=clock_timestamp();performed:=(p.prepared->>'performed_at')::timestamptz;zone:=p.prepared->>'time_zone';day:=(p.prepared->>'local_date')::date;
 IF performed IS DISTINCT FROM (s.context->>'admitted_at')::timestamptz OR (clock AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RETURN '{"action":"source_conflict"}';END IF;
 operation:='cwork1:'||p_command_id::text;
 IF EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=p_user_id AND raw_provider_message_id=operation) THEN RAISE EXCEPTION 'unjournaled_conversation_workout_effect' USING ERRCODE='40001';END IF;
 SELECT * INTO STRICT selected FROM public.workout_types WHERE slug=p.prepared#>>'{activity,workout_type}' AND is_active AND slug<>'outro';
 SELECT * INTO STRICT a FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 life:=a.current_lifecycle_key;
 IF life IS NULL THEN
  IF EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=p_user_id AND closed_at IS NULL) THEN RAISE EXCEPTION 'workout_lifecycle_unproved' USING ERRCODE='40001';END IF;
  life:=gen_random_uuid();INSERT INTO private.workout_strength_lifecycles(user_id,lifecycle_key,opened_at) VALUES(p_user_id,life,clock);
  UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=life WHERE user_id=p_user_id AND epoch=p_expected_epoch;
 ELSIF NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=p_user_id AND lifecycle_key=life AND closed_at IS NULL) THEN RETURN '{"action":"stale_lifecycle"}';END IF;
 -- Snapshot defaults/targets remain the existing authority. Do not mint a
 -- calorie target or use exercise to increase the food budget.
 INSERT INTO public.daily_snapshots(user_id,date) VALUES(p_user_id,day) ON CONFLICT(user_id,date) DO NOTHING;
 SELECT * INTO STRICT snap FROM public.daily_snapshots WHERE user_id=p_user_id AND date=day FOR UPDATE NOWAIT;
 IF snap.day_closed THEN RAISE EXCEPTION 'workout_day_closed_after_wait' USING ERRCODE='40001';END IF;
 INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,intensity,notes,performed_at,raw_provider_message_id)
 VALUES(p_user_id,snap.id,p.prepared#>>'{activity,workout_type}',(p.prepared#>>'{activity,duration_min}')::integer,(p.prepared#>>'{activity,estimated_kcal}')::integer,p.prepared#>>'{activity,intensity}','conversation.workout.v1',performed,operation) RETURNING * INTO w;
 SELECT * INTO STRICT snap FROM public.daily_snapshots WHERE user_id=p_user_id AND id=snap.id;
 INSERT INTO private.workout_strength_facts(user_id,workout_log_id,lifecycle_key,snapshot_id,stored_workout_type,performed_at,snapshot_date,
 classification_status,classification_reason,observation_key,observed_at,matcher_version,active_row_count,match_method,catalogue_id,catalogue_slug,catalogue_display_name,catalogue_category,catalogue_updated_at,
 calendar_status,calendar_reason,local_date,time_zone,zone_source,zone_observed_at,question_key,answer,answer_operation_key,answer_accepted_at,revision)
 VALUES(p_user_id,w.id,life,snap.id,w.workout_type,w.performed_at,day,'matched',NULL,gen_random_uuid(),clock,'active_slug_then_unique_canonical_display_v1',jsonb_array_length(s.context->'catalogue'),'active_slug',selected.id,selected.slug,selected.display_name,selected.category,selected.updated_at,
 'proven',NULL,day,zone,'official_owner_zone_at_recording',clock,NULL,NULL,NULL,NULL,0);
 legacy:=jsonb_build_object('provenance','conversation.workout.v1','snapshot_id',snap.id,'workout_log_id',w.id,'inserted',true,'deduped',false);
 INSERT INTO private.workout_strength_operations(user_id,lifecycle_key,operation_kind,operation_key,original_operation_type,original_workout_log_id,live_workout_log_id,created_at,resolution,capture_outcome,legacy_result)
 VALUES(p_user_id,life,'capture',operation,w.workout_type,w.id,w.id,clock,'sql_insert','fact',legacy);
 strength:=public.resolve_confirmed_workout_strength_capture(p_user_id,life,operation,w.workout_type);
 IF strength->>'status' IS DISTINCT FROM 'reuse_existing' OR strength#>>'{fact,anchor,workoutLogID}' IS DISTINCT FROM w.id::text THEN RAISE EXCEPTION 'workout_strength_receipt_unproved' USING ERRCODE='40001';END IF;
 strength:=strength||'{"status":"committed"}'::jsonb;
 receipt:=jsonb_build_object('schema','conversation.workout-effect.v1','provenance','conversation.workout.v1','owner_id',p_user_id,'command_id',p_command_id,'input_hash',p_input_hash,'source_hash',s.source_hash,'epoch',p_expected_epoch,'registration_id',p_command_id,'workout_id',w.id,'snapshot_id',snap.id,'lifecycle_key',life,'operation_key',operation,'prepared_hash',p.prepared_hash,'performed_at',private.conversation_workout_clock(performed),'local_date',day,'time_zone',zone,'committed_at',private.conversation_workout_clock(clock),'effect_version',1,'activity',p.prepared->'activity');
 facts:=jsonb_build_object('workout',jsonb_build_object('id',w.id,'user_id',p_user_id,'snapshot_id',snap.id,'raw_provider_message_id',operation,'workout_type',w.workout_type,'duration_min',w.duration_min,'intensity',w.intensity,'estimated_kcal',w.estimated_kcal,'performed_at',private.conversation_workout_clock(w.performed_at)),
 'snapshot',jsonb_build_object('id',snap.id,'user_id',p_user_id,'date',day),'strength_capture',strength);
 proposal:=jsonb_build_object('kind','workout','workoutType',w.workout_type,'source_provider_message_id',operation,'source_timestamp',private.conversation_workout_clock(performed),'source_timezone',zone,'source_local_date',day,'command_protocol','conversation.command.v1','command_id',p_command_id,'workout_protocol','conversation.workout.v1');
 -- Frozen context is owned original evidence, never a fabricated pending/UI
 -- review. Current policy and numerical coverage are rechecked at presentation.
 clinical:=private.capture_mobile_current_clinical_state_at(p_user_id,'profile',NULL,NULL,clock);
 feedback:=jsonb_build_object('version',1,'user_id',p_user_id,'registration_id',p_command_id,'confirmed',jsonb_build_object('id',p_command_id,'user_id',p_user_id,'status','confirmed','proposal',proposal),
 'logs',jsonb_build_array(facts->'workout'),'workout_proof',jsonb_build_object('kind','conversation.workout.v1','receipt',receipt,'strength_capture',strength),'snapshot',to_jsonb(snap),'progress',(SELECT to_jsonb(pr) FROM public.user_progress pr WHERE pr.user_id=p_user_id),'clinical',clinical);
 INSERT INTO private.conversation_workout_effects(user_id,command_id,original_workout_id,live_workout_id,receipt,original_facts,recorded_at,feedback_context) VALUES(p_user_id,p_command_id,w.id,w.id,receipt,facts,clock,feedback);
 INSERT INTO private.conversation_workout_events(user_id,command_id,kind,at,body) VALUES(p_user_id,p_command_id,'registered',clock,jsonb_build_object('receipt',receipt));
 RETURN jsonb_build_object('action','committed','receipt',receipt);
END $$;

CREATE FUNCTION public.read_conversation_workout_effect(p_user_id uuid,p_command_id uuid,p_input_hash text,p_source_hash text,p_expected_epoch uuid,p_prepared_hash text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;effect private.conversation_workout_effects%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'conversation_workout_requires_read_committed' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"stale_epoch"}';END IF;
 SELECT * INTO c FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM p_expected_epoch OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id AND epoch=c.epoch) THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id AND source_hash=p_source_hash) THEN RETURN '{"action":"source_conflict"}';END IF;
 SELECT * INTO effect FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF effect.receipt->>'prepared_hash' IS DISTINCT FROM p_prepared_hash THEN RETURN '{"action":"prepared_conflict"}';END IF;
 RETURN jsonb_build_object('action','available','receipt',effect.receipt,'original_facts',effect.original_facts);
END $$;
CREATE FUNCTION public.read_conversation_workout_preparation(p_user_id uuid,p_command_id uuid,p_input_hash text,p_expected_epoch uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.conversation_workout_command_ids%ROWTYPE;s private.conversation_workout_sources%ROWTYPE;p private.conversation_workout_preparations%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'conversation_workout_requires_read_committed' USING ERRCODE='22023';END IF;
 SELECT * INTO c FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM p_expected_epoch OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id AND epoch=c.epoch) OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}';END IF;
 SELECT * INTO s FROM private.conversation_workout_sources WHERE user_id=p_user_id AND command_id=p_command_id;
 SELECT * INTO p FROM private.conversation_workout_preparations WHERE user_id=p_user_id AND command_id=p_command_id;
 RETURN jsonb_build_object('action','available','source',CASE WHEN s.command_id IS NULL THEN NULL ELSE jsonb_build_object('source_hash',s.source_hash,'context',s.context) END,
 'preparation',CASE WHEN p.command_id IS NULL THEN NULL ELSE jsonb_build_object('prepared_hash',p.prepared_hash,'prepared',p.prepared) END);
END $$;

-- Reset invalidates permanent identity and scrubs all personal payloads by the
-- same epoch boundary as meal commands. Reset never admits an old UUID again.
CREATE FUNCTION private.scrub_conversation_workout_on_epoch() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 UPDATE private.conversation_workout_command_ids SET invalidated_at=clock_timestamp() WHERE user_id=NEW.user_id AND invalidated_at IS NULL;
 DELETE FROM private.conversation_workout_inputs WHERE user_id=NEW.user_id;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_workout_epoch_scrub AFTER UPDATE OF epoch ON private.workout_strength_authority_epochs FOR EACH ROW WHEN(OLD.epoch IS DISTINCT FROM NEW.epoch) EXECUTE FUNCTION private.scrub_conversation_workout_on_epoch();
CREATE FUNCTION private.journal_conversation_workout_preparation() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 INSERT INTO private.conversation_workout_events(user_id,command_id,kind,at,body) VALUES(NEW.user_id,NEW.command_id,'prepared',NEW.prepared_at,jsonb_build_object('prepared_hash',NEW.prepared_hash,'prepared',NEW.prepared));RETURN NEW;
END $$;
CREATE TRIGGER conversation_workout_prepared_event AFTER INSERT ON private.conversation_workout_preparations FOR EACH ROW EXECUTE FUNCTION private.journal_conversation_workout_preparation();
CREATE TRIGGER conversation_workout_events_immutable BEFORE UPDATE ON private.conversation_workout_events FOR EACH ROW EXECUTE FUNCTION private.conversation_workout_immutable();

-- Only these exact reviewed legacy bodies are extended. Preserve all former
-- admission/replay rules and the threshold; meal/reply/workout share one cap.
DO $shared_budget$
DECLARE fn_id regprocedure;body text;needle text;replacement text;
BEGIN
 fn_id:='public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)'::regprocedure;
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'6127d6a338cf961d5c50cb3ddfd001265f56413996dbe19df67cbeac9300e2b6' THEN RAISE EXCEPTION 'unknown_meal_admission_body';END IF;
 body:=pg_get_functiondef(fn_id);needle:=$n$(SELECT count(*) FROM private.conversation_meal_command_ids ids
  WHERE ids.user_id=p_user_id AND ids.epoch=e.epoch
   AND ids.admitted_at>=admission_clock-interval '60 seconds')$n$;
 replacement:='private.conversation_workout_admission_count(p_user_id,e.epoch,admission_clock)';
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'meal_quota_guard_missing';END IF;
 body:=replace(body,needle,replacement);
 body:=replace(body,'admission_clock:=clock_timestamp();',$n$IF EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=(p_input->>'command_id')::uuid) THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
 admission_clock:=clock_timestamp();$n$);EXECUTE body;
 fn_id:='public.admit_conversation_meal_reply(uuid,uuid,uuid,text,text,uuid,jsonb)'::regprocedure;
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'6488ca99d987fdc666ae81cc6ab43ba9c5d60a803fa8458545605484fc5ad070' THEN RAISE EXCEPTION 'unknown_reply_admission_body';END IF;
 body:=pg_get_functiondef(fn_id);needle:=$n$(SELECT count(*) FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND epoch=p_expected_epoch AND admitted_at>=clock-interval '60 seconds')$n$;
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'reply_quota_guard_missing';END IF;
 body:=replace(body,needle,'private.conversation_workout_admission_count(p_user_id,p_expected_epoch,clock)');
 body:=replace(body,'PERFORM private.assert_conversation_meal_reply(p_input);',$n$IF EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=p_user_id AND command_id=p_reply_id) THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
 PERFORM private.assert_conversation_meal_reply(p_input);$n$);EXECUTE body;
END $shared_budget$;

-- No new reward policy: when energy coverage is unknown an open day may still
-- receive existing XP/status treatment, but cannot change energy block ledger.
-- Already closed days retain their exact old replay and consolidated progress.
DO $coverage_finalizer$
DECLARE fn_id regprocedure:='public.finalize_daily_close_atomic(uuid,uuid,text,integer,integer,integer,integer,integer,integer,text[],date,timestamp with time zone)'::regprocedure;body text;needle text;
BEGIN
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'793c7e6b4eeb4f0445a2717eff32bad458261f79fc4f7742c51160dbaac70482' THEN RAISE EXCEPTION 'unknown_daily_close_body';END IF;
 body:=pg_get_functiondef(fn_id);
 body:=replace(body,$n$  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':daily-close', 0));$n$,$n$  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':workouts', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':daily-close', 0));$n$);
 needle:='  INSERT INTO public.user_progress (';
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'daily_close_guard_missing';END IF;
 body:=replace(body,needle,$n$  IF (EXISTS(SELECT 1 FROM public.daily_snapshots WHERE id=p_snapshot_id AND user_id=p_user_id AND NOT exercise_energy_complete)
    OR EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=p_user_id AND snapshot_id=p_snapshot_id AND estimated_kcal IS NULL))
    AND (p_blocks_completed IS DISTINCT FROM coalesce((SELECT blocks_completed FROM public.user_progress WHERE user_id=p_user_id),0)
      OR p_deficit_block IS DISTINCT FROM coalesce((SELECT deficit_block FROM public.user_progress WHERE user_id=p_user_id),0)) THEN
    RAISE EXCEPTION 'incomplete_workout_energy' USING ERRCODE='40001';
  END IF;
  INSERT INTO public.user_progress ($n$);EXECUTE body;
END $coverage_finalizer$;

-- Read-only reconciliation preserves original identity after edit/Undo. It
-- never re-runs extraction, estimation or registration to repair a lost reply.
CREATE FUNCTION public.reconcile_conversation_workout(p_user_id uuid,p_command_id uuid,p_input_hash text,p_expected_epoch uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE prepared jsonb;e private.conversation_workout_effects%ROWTYPE;w public.workout_logs%ROWTYPE;s public.daily_snapshots%ROWTYPE;
BEGIN
 prepared:=public.read_conversation_workout_preparation(p_user_id,p_command_id,p_input_hash,p_expected_epoch);
 IF prepared->>'action'<>'available' THEN RETURN prepared;END IF;
 SELECT * INTO e FROM private.conversation_workout_effects WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN prepared||jsonb_build_object('effect',NULL);END IF;
 IF e.live_workout_id IS NOT NULL THEN
  SELECT * INTO w FROM public.workout_logs WHERE user_id=p_user_id AND id=e.live_workout_id;
  IF NOT FOUND THEN RETURN '{"action":"effect_conflict"}';END IF;
  SELECT * INTO s FROM public.daily_snapshots WHERE user_id=p_user_id AND id=w.snapshot_id;
  IF NOT FOUND THEN RETURN '{"action":"effect_conflict"}';END IF;
 END IF;
 RETURN prepared||jsonb_build_object('effect',jsonb_build_object('receipt',e.receipt,'original_facts',e.original_facts),
  'current',CASE WHEN e.live_workout_id IS NULL THEN jsonb_build_object('status','removed') ELSE jsonb_build_object('status','present','workout',to_jsonb(w),'snapshot',to_jsonb(s)) END);
END $$;

-- V2 cannot encode null exercise. Reject only NEW numeric day seals with an
-- explicit incomplete source marker; existing immutable receipts/replay remain
-- exact. Additive per-field feedbackv3 is required before activity activation.
-- NEW unknown-energy close acknowledgements use an explicit closed v2 shape;
-- old known results and already sealed legacy receipt replay stay byte-identical.
DO $close_result_availability$
DECLARE fn_id regprocedure:='private.apply_mobile_clinical_day_close_at(uuid,uuid,date,date,text,text,jsonb,timestamp with time zone)'::regprocedure;body text;needle text;
BEGIN
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'5fb9d24c60084dd00c4d483a5045ff3564e2d684635c84e52e342ef67b2cd14d' THEN RAISE EXCEPTION 'unknown_clinical_close_result_body';END IF;
 body:=pg_get_functiondef(fn_id);
 needle:='historical_phase text;historical_deficit integer;credit_status text;';
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'clinical_close_result_declaration_missing';END IF;
 body:=replace(body,needle,needle||'energy_complete boolean;');
 body:=replace(body,'PERFORM private.mobile_reevaluation_lock_owner(p_user_id);','PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||'':workouts'',0)); PERFORM private.mobile_reevaluation_lock_owner(p_user_id);');
 needle:=$n$facts:=c->'facts';observed:=(c->>'observed_at')::timestamptz;$n$;
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'clinical_close_result_capture_missing';END IF;
 body:=replace(body,needle,needle||$n$
 energy_complete:=CASE WHEN p_close_date IS NULL THEN true ELSE coalesce((facts#>>'{snapshot,exercise_energy_complete}')::boolean,true)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'day_workouts') w WHERE w->'estimated_kcal' IS NULL OR w->'estimated_kcal'='null'::jsonb) END;$n$);
 body:=replace(body,'credit_status:=CASE WHEN historical_phase IS NULL','credit_status:=CASE WHEN NOT energy_complete OR historical_phase IS NULL');
 body:=replace(body,'IF NOT block_enabled AND (credit<>0','IF (NOT block_enabled OR NOT energy_complete) AND (credit<>0');
 body:=replace(body,'fat_g=fat,exercise_calories=exercise,training_done=','fat_g=fat,exercise_calories=exercise,exercise_energy_complete=energy_complete,training_done=');
 needle:=$n$IF props<>jsonb_build_object('snapshot_date',p_close_date,'calories_consumed',calories,'calories_target',target,
      'exercise_calories',exercise,'training_done',f->'training_done','day_status',dstatus,'xp_earned',xp,
      'blocks_completed',blocks,'blocks_completed_delta',blocks-old_blocks) THEN$n$;
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'clinical_close_completed_projection_missing';END IF;
 body:=replace(body,needle,$n$IF props<>(jsonb_build_object('snapshot_date',p_close_date,'calories_consumed',calories,'calories_target',target,
      'exercise_calories',CASE WHEN energy_complete THEN exercise ELSE NULL END,'training_done',f->'training_done','day_status',dstatus,'xp_earned',xp,
      'blocks_completed',blocks,'blocks_completed_delta',blocks-old_blocks) || CASE WHEN energy_complete THEN '{}'::jsonb ELSE '{"exercise_energy_complete":false}'::jsonb END) THEN$n$);
 needle:=$n$'xpEarned',xp,'blockCredit',credit,'blockCreditStatus',credit_status,'newBadges',new_badges,'progress',g));$n$;
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'clinical_close_result_projection_missing';END IF;
 body:=replace(body,needle,needle||$n$
  IF NOT energy_complete THEN result:=result||jsonb_build_object('calculation_version','bodyflow.day-close.v2',
   'detail',(result->'detail')||jsonb_build_object('exerciseCalories',NULL,'exerciseEnergy',jsonb_build_object('status','unavailable','reason','unknown_workout_energy')));END IF;$n$);
 EXECUTE body;
END $close_result_availability$;

DO $feedback_guard$
DECLARE fn_id regprocedure:='private.assert_registration_feedback_v2_sources(jsonb,jsonb)'::regprocedure;body text;needle text;
BEGIN
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'fd782fea7b0430e3da892b1590651cafd2ae0e53a8226e6dd994f7cecacd3668' THEN RAISE EXCEPTION 'unknown_feedback_v2_sources_body';END IF;
 body:=pg_get_functiondef(fn_id);needle:=' PERFORM private.assert_registration_feedback_v2_shape(f,(c->>''registration_id'')::uuid,p->>''kind'');';
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'feedback_v2_sources_guard_missing';END IF;
 body:=replace(body,needle,$n$ IF f->'day' IS DISTINCT FROM 'null'::jsonb AND s->'exercise_energy_complete'='false'::jsonb THEN RAISE EXCEPTION 'feedback_v2_day_energy_unavailable' USING ERRCODE='22023';END IF;
$n$||needle);EXECUTE body;
END $feedback_guard$;

-- R2-F1: retain legacy known bindings byte-for-byte; an unavailable close
-- records its false witness and cannot regain proof after NULL -> known zero.
DO $period_coverage$
DECLARE fn_id regprocedure;body text;needle text;
BEGIN
 fn_id:='private.mobile_clinical_closed_day_binding(public.daily_snapshots)'::regprocedure;
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'a25dabcefd070fc2f2b5e992062ef38276b66343972ad483c8f510f609c09246' THEN RAISE EXCEPTION 'unknown_closed_day_binding_body';END IF;
 body:=pg_get_functiondef(fn_id);needle:=$n$FROM private.mobile_flow_plan_day_revisions WHERE snapshot_id=d.id AND user_id=d.user_id),'0'))$n$;
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'closed_day_binding_projection_missing';END IF;
 body:=replace(body,needle,needle||$n$ || CASE WHEN d.exercise_energy_complete THEN '{}'::jsonb ELSE '{"exercise_energy_complete":false}'::jsonb END$n$);EXECUTE body;
 fn_id:='private.get_mobile_clinical_flow_period_at(uuid,text,date,date,timestamp with time zone)'::regprocedure;
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'6536951e9983f58f6fc13e7290d9cd130c255fb3890498fa09774402bb54467d' THEN RAISE EXCEPTION 'unknown_clinical_flow_period_body';END IF;
 body:=pg_get_functiondef(fn_id);needle:='AND d.closed_at IS NOT NULL AND d.calories_target>0';
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'closed_day_period_proof_missing';END IF;
 -- This historical v1 series always uses generated consumed-target-exercise,
 -- including gain/maintenance. Do not silently replace its formula. Todayv4's
 -- independent gain/maintenance balance remains available in its own reader.
 body:=replace(body,needle,'AND d.exercise_energy_complete AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_unknown_exercise_evidence unavailable WHERE unavailable.snapshot_id=d.id AND unavailable.user_id=d.user_id) '||needle);EXECUTE body;
END $period_coverage$;

-- R2-F3: every mobile legacy finalization takes the existing owner lane before
-- user/profile, day/daily-close and snapshot rows, matching both registrars.
DO $mobile_finalizer_lock_order$
DECLARE fn_id regprocedure:='public.finalize_mobile_daily_close_atomic(uuid,uuid,text,integer,integer,integer,integer,integer,integer,text[],date,timestamp with time zone,text,jsonb,jsonb,jsonb)'::regprocedure;body text;needle text;
BEGIN
 IF encode(sha256(convert_to((SELECT prosrc FROM pg_proc WHERE pg_proc.oid=fn_id),'UTF8')),'hex')<>'9cb24cb0d11ee51083810db266d53bd64cd9ad19ae0985f13c4c7f8ba033732c' THEN RAISE EXCEPTION 'unknown_mobile_finalizer_body';END IF;
 body:=pg_get_functiondef(fn_id);needle:='  SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR SHARE NOWAIT;';
 IF strpos(body,needle)=0 THEN RAISE EXCEPTION 'mobile_finalizer_owner_lock_missing';END IF;
 body:=replace(body,needle,$n$  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
$n$||needle);EXECUTE body;
END $mobile_finalizer_lock_order$;

DO $acl$
DECLARE fn regprocedure;
BEGIN
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE
  (n.nspname='private' AND (p.proname LIKE '%conversation_workout%' OR p.proname='assert_conversation_workout_input')) OR
  (n.nspname='public' AND p.proname IN('admit_conversation_workout_command','capture_conversation_workout_source','prepare_conversation_workout','commit_conversation_workout','read_conversation_workout_effect','read_conversation_workout_preparation','reconcile_conversation_workout')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',fn);
  IF (SELECT n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid=fn)='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',fn);END IF;
 END LOOP;
END $acl$;
COMMIT;

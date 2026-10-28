-- Dormant explicit later first-phase authority. No FULL/signup/calendar fiction.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.capture_mobile_clinical_first_phase_at(uuid,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'first_phase_confirmation_requires_context' USING ERRCODE='42501';END IF;
END $$;
CREATE TABLE private.mobile_clinical_first_phase_previews (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 preview_id uuid NOT NULL DEFAULT gen_random_uuid(),prepare_operation_key uuid NOT NULL,
 signup_generation uuid NOT NULL,signup_epoch uuid NOT NULL,
 context_hash text NOT NULL CHECK(context_hash ~ '^[a-f0-9]{64}$'),
 selection jsonb NOT NULL,selection_hash text NOT NULL CHECK(selection_hash ~ '^[a-f0-9]{64}$'),
 proposal jsonb NOT NULL,proposal_hash text NOT NULL CHECK(proposal_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL CHECK(isfinite(created_at)),valid_until timestamptz NOT NULL CHECK(valid_until>created_at),
 PRIMARY KEY(user_id,preview_id),UNIQUE(user_id,prepare_operation_key),
 FOREIGN KEY(user_id,signup_generation) REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE private.mobile_clinical_first_phase_confirmations (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,first_phase_id uuid NOT NULL,
 signup_generation uuid NOT NULL,signup_epoch uuid NOT NULL,event_id uuid NOT NULL,episode_id uuid NOT NULL,
 phase text NOT NULL CHECK(phase IN('recomposicao','ganho_massa','manutencao')),
 deficit_level integer CHECK(deficit_level IN(400,500,600)),decision_date date NOT NULL CHECK(isfinite(decision_date)),
 effective_date date NOT NULL CHECK(isfinite(effective_date)),confirmed_at timestamptz NOT NULL CHECK(isfinite(confirmed_at)),
 context_hash text NOT NULL CHECK(context_hash ~ '^[a-f0-9]{64}$'),command_hash text NOT NULL CHECK(command_hash ~ '^[a-f0-9]{64}$'),
 -- Historical witness, as in target_origins: reset may delete the live day
 -- while the original immutable acknowledgement must remain replayable.
 proposal jsonb NOT NULL,applied_snapshot_id uuid,result jsonb NOT NULL,
 PRIMARY KEY(user_id,first_phase_id),UNIQUE(user_id,signup_generation),UNIQUE(user_id,event_id),
 FOREIGN KEY(user_id,first_phase_id) REFERENCES private.mobile_clinical_first_phase_previews(user_id,preview_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,signup_generation) REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((phase='recomposicao')=(deficit_level IS NOT NULL)),CHECK(effective_date IN(decision_date,decision_date+1))
);
CREATE TABLE private.mobile_clinical_first_phase_keys (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,operation_key uuid NOT NULL,first_phase_id uuid NOT NULL,
 input_hash text NOT NULL CHECK(input_hash ~ '^[a-f0-9]{64}$'),acknowledged_at timestamptz NOT NULL CHECK(isfinite(acknowledged_at)),
 PRIMARY KEY(user_id,operation_key),
 FOREIGN KEY(user_id,first_phase_id) REFERENCES private.mobile_clinical_first_phase_confirmations(user_id,first_phase_id) DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE private.mobile_clinical_first_phase_previews ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_first_phase_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_first_phase_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_first_phase_previews,private.mobile_clinical_first_phase_confirmations,
 private.mobile_clinical_first_phase_keys FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_first_phase_preview_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_first_phase_previews
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();
CREATE TRIGGER mobile_first_phase_confirmation_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_first_phase_confirmations
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();
CREATE TRIGGER mobile_first_phase_key_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_first_phase_keys
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

-- Explicit source union. Existing FULL events keep their real review and the
-- first event references a genuine confirmation, never an invented review.
ALTER TABLE private.mobile_clinical_episode_events ADD COLUMN first_phase_id uuid,
 ALTER COLUMN review_id DROP NOT NULL,
 ADD UNIQUE(user_id,first_phase_id),
 ADD FOREIGN KEY(user_id,first_phase_id) REFERENCES private.mobile_clinical_first_phase_confirmations(user_id,first_phase_id) DEFERRABLE INITIALLY DEFERRED,
 ADD CONSTRAINT mobile_clinical_episode_one_source CHECK(num_nonnulls(review_id,first_phase_id)=1);
ALTER TABLE private.mobile_clinical_first_phase_confirmations ADD FOREIGN KEY(user_id,event_id)
 REFERENCES private.mobile_clinical_episode_events(user_id,event_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE private.mobile_clinical_target_origins ADD COLUMN first_phase_id uuid,
 ADD UNIQUE(user_id,first_phase_id),
 ADD FOREIGN KEY(user_id,first_phase_id) REFERENCES private.mobile_clinical_first_phase_confirmations(user_id,first_phase_id) DEFERRABLE INITIALLY DEFERRED,
 DROP CONSTRAINT mobile_clinical_target_origin_one_source,
 ADD CONSTRAINT mobile_clinical_target_origin_one_source CHECK(num_nonnulls(review_id,application_id,signup_application_id,first_phase_id)=1);

CREATE FUNCTION private.mobile_clinical_first_phase_prepared(p private.mobile_clinical_first_phase_previews)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'user_id',(p).user_id,'preview_id',(p).preview_id,
  'prepare_operation_key',(p).prepare_operation_key,'signup_generation',(p).signup_generation,'signup_epoch',(p).signup_epoch,
  'context_hash',(p).context_hash,'selection',(p).selection,'package',(p).proposal,
  'created_at',to_char((p).created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'valid_until',to_char((p).valid_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;
CREATE FUNCTION private.assert_mobile_clinical_first_phase_package(c jsonb,s jsonb,p jsonb) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE f jsonb:=c->'facts';profile jsonb:=c#>'{facts,profile}';phase text;deficit integer;years integer;
 bmi numeric;bf numeric;height numeric;weight numeric;cut numeric:=25;bf_cut numeric;gain_cut numeric;training_min numeric:=3;
 limits jsonb;row_value jsonb;above boolean;expected_origin text;expected_bf numeric;key text;n numeric;
BEGIN
 IF jsonb_typeof(s) IS DISTINCT FROM 'object' OR NOT(s ? 'phase') OR s-ARRAY['phase']<>'{}'::jsonb
  OR jsonb_typeof(s->'phase') IS DISTINCT FROM 'string'
  OR s->>'phase' NOT IN('recomposicao','ganho_massa','manutencao') OR jsonb_typeof(p) IS DISTINCT FROM 'object'
  OR NOT(p ?& ARRAY['version','phase','deficitLevel','effectiveDate','targets','formulaBodyFat','episode'])
  OR p-ARRAY['version','phase','deficitLevel','effectiveDate','targets','formulaBodyFat','episode']<>'{}'::jsonb
  OR p->'version' IS DISTINCT FROM '1'::jsonb OR p->>'phase' IS DISTINCT FROM s->>'phase'
  OR p->'effectiveDate' IS DISTINCT FROM f#>'{first_phase,effective_date}' THEN
  RAISE EXCEPTION 'invalid_first_phase_package' USING ERRCODE='22023';END IF;
 phase:=s->>'phase';height:=(profile->>'height_cm')::numeric;weight:=(profile->>'weight_kg')::numeric;bf:=(profile->>'body_fat_percent')::numeric;
 years:=CASE WHEN profile->>'birth_date' IS NOT NULL AND (profile->>'birth_date')::date<=(f->>'calculation_date')::date
  THEN extract(year FROM age((f->>'calculation_date')::date,(profile->>'birth_date')::date))::integer END;
 bmi:=CASE WHEN height>0 THEN weight/power(height/100,2) END;
 IF years IS NULL OR years<18 OR bmi IS NULL OR bmi<18.5 OR coalesce(bf<=10,false)
  OR coalesce((f#>>'{safety,hold_active}')::boolean,true) OR profile->>'sex' IS NULL OR profile->>'sex' NOT IN('masculino','feminino')
  OR profile->>'activity_level' IS NULL OR profile->>'training_frequency' IS NULL OR profile->>'hunger_level' IS NULL
  OR profile->>'hunger_level' NOT IN('pouca','moderada','muita') THEN
  RAISE EXCEPTION 'first_phase_safety_or_inputs_changed' USING ERRCODE='40001';END IF;
 SELECT cfg.value INTO row_value FROM public.global_config cfg WHERE cfg.key='calc.imc_limit_recomp';
 IF jsonb_typeof(row_value)='number' THEN cut:=(row_value#>>'{}')::numeric;END IF;
 SELECT cfg.value INTO row_value FROM public.global_config cfg WHERE cfg.key='calc.training_min';
 IF jsonb_typeof(row_value)='number' THEN training_min:=(row_value#>>'{}')::numeric;END IF;
 SELECT cfg.value->(profile->>'sex') INTO limits FROM public.global_config cfg WHERE cfg.key='calc.bf_limits';
 bf_cut:=CASE WHEN profile->>'sex'='masculino' THEN 20 ELSE 28 END;
 gain_cut:=CASE WHEN profile->>'sex'='masculino' THEN 19 ELSE 27 END;
 IF jsonb_typeof(limits->'recomp')='number' THEN bf_cut:=(limits->>'recomp')::numeric;END IF;
 IF jsonb_typeof(limits->'gain')='number' THEN gain_cut:=(limits->>'gain')::numeric;END IF;
 above:=CASE WHEN bf IS NOT NULL THEN bf>=bf_cut ELSE bmi>=cut END;
 IF (above AND phase<>'recomposicao') OR (phase='ganho_massa' AND
  (cut<=0 OR bmi>=cut OR coalesce(bf>gain_cut,false) OR (profile->>'training_frequency')::numeric<training_min)) THEN
  RAISE EXCEPTION 'first_phase_choice_changed' USING ERRCODE='40001';END IF;
 deficit:=CASE WHEN phase='recomposicao' THEN CASE profile->>'hunger_level' WHEN 'muita' THEN 400 WHEN 'moderada' THEN 500 ELSE 600 END END;
 IF p->'deficitLevel' IS DISTINCT FROM coalesce(to_jsonb(deficit),'null'::jsonb)
  OR jsonb_typeof(p->'targets') IS DISTINCT FROM 'object'
  OR NOT(p->'targets' ?& ARRAY['beforeKcal','beforeProtein','afterKcal','afterProtein','formulaAfterKcal'])
  OR (p->'targets')-ARRAY['beforeKcal','beforeProtein','afterKcal','afterProtein','formulaAfterKcal']<>'{}'::jsonb
  OR p#>'{targets,beforeKcal}' IS DISTINCT FROM coalesce(f#>'{day,calories_target}','null'::jsonb)
  OR p#>'{targets,beforeProtein}' IS DISTINCT FROM coalesce(f#>'{day,protein_target}','null'::jsonb)
  OR p#>'{targets,afterKcal}' IS DISTINCT FROM p#>'{targets,formulaAfterKcal}' THEN
  RAISE EXCEPTION 'invalid_first_phase_targets' USING ERRCODE='22023';END IF;
 FOREACH key IN ARRAY ARRAY['afterKcal','afterProtein','formulaAfterKcal'] LOOP
  IF jsonb_typeof(p#>ARRAY['targets',key]) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_first_phase_number' USING ERRCODE='22023';END IF;
  n:=(p#>>ARRAY['targets',key])::numeric;
  IF (key='afterProtein' AND n NOT BETWEEN 0 AND 9999.99)
   OR (key<>'afterProtein' AND (n NOT BETWEEN 1 AND 2147483647 OR trunc(n)<>n)) THEN
   RAISE EXCEPTION 'invalid_first_phase_number' USING ERRCODE='22023';END IF;
 END LOOP;
 expected_origin:=CASE WHEN bf IS NULL THEN 'none' ELSE 'report' END;
 IF f#>'{protocol_authority,signup_body_fat_origin}'<>'null'::jsonb THEN
  expected_origin:='signup';expected_bf:=(f#>>'{protocol_authority,signup_body_fat_origin,confirmed_body_fat_percent}')::numeric;
 END IF;
 IF f#>'{protocol_authority,body_fat_origin}'<>'null'::jsonb THEN
  expected_origin:='recurring';expected_bf:=(f#>>'{protocol_authority,body_fat_origin,mean_percent}')::numeric;
 END IF;
 IF p->'formulaBodyFat' IS DISTINCT FROM jsonb_build_object('origin',expected_origin,'percent',expected_bf)
  OR p->'episode' IS DISTINCT FROM jsonb_build_object('difficultyCount',CASE WHEN phase='recomposicao' THEN 0 END,
   'ledgerSteps',CASE WHEN phase='recomposicao' THEN 'null'::jsonb ELSE '[]'::jsonb END,'schedule',NULL,
   'maintenanceSince',CASE WHEN phase='manutencao' AND NOT coalesce((f#>>'{day,day_closed}')::boolean,false) THEN f->>'calculation_date' END) THEN
  RAISE EXCEPTION 'invalid_first_phase_provenance_or_episode' USING ERRCODE='22023';END IF;
END $$;

CREATE FUNCTION public.get_mobile_clinical_first_phase_prepared(p_user_id uuid,p_preview_id uuid,p_prepare_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p private.mobile_clinical_first_phase_previews%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR num_nonnulls(p_preview_id,p_prepare_operation_key)<>1 THEN RAISE EXCEPTION 'invalid_first_phase_lookup' USING ERRCODE='22023';END IF;
 SELECT * INTO p FROM private.mobile_clinical_first_phase_previews WHERE user_id=p_user_id
  AND (preview_id=p_preview_id OR prepare_operation_key=p_prepare_operation_key);
 RETURN CASE WHEN p.preview_id IS NOT NULL THEN private.mobile_clinical_first_phase_prepared(p) END;
END $$;
CREATE FUNCTION private.prepare_mobile_clinical_first_phase_at(p_user_id uuid,p_operation_key uuid,p_context_hash text,
 p_selection jsonb,p_proposal jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE p private.mobile_clinical_first_phase_previews%ROWTYPE;c jsonb;sh text;ph text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_operation_key IS NULL OR p_context_hash IS NULL OR p_context_hash!~'^[a-f0-9]{64}$'
  OR p_selection IS NULL OR p_proposal IS NULL OR octet_length(p_selection::text)>1024 OR octet_length(p_proposal::text)>8192 THEN
  RAISE EXCEPTION 'invalid_first_phase_prepare' USING ERRCODE='22023';END IF;
 sh:=encode(extensions.digest(p_selection::text,'sha256'),'hex');ph:=encode(extensions.digest(p_proposal::text,'sha256'),'hex');
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO p FROM private.mobile_clinical_first_phase_previews WHERE user_id=p_user_id AND prepare_operation_key=p_operation_key;
 IF FOUND THEN
  IF ROW(p.context_hash,p.selection_hash,p.proposal_hash) IS DISTINCT FROM ROW(p_context_hash,sh,ph) THEN
   RAISE EXCEPTION 'first_phase_prepare_conflict' USING ERRCODE='40001';END IF;
  RETURN private.mobile_clinical_first_phase_prepared(p);
 END IF;
 c:=private.capture_mobile_clinical_first_phase_at(p_user_id,p_observed_at);
 IF c->>'context_hash'<>p_context_hash THEN RAISE EXCEPTION 'first_phase_context_changed' USING ERRCODE='40001';END IF;
 PERFORM private.assert_mobile_clinical_first_phase_package(c,p_selection,p_proposal);
 INSERT INTO private.mobile_clinical_first_phase_previews(user_id,prepare_operation_key,signup_generation,signup_epoch,context_hash,
  selection,selection_hash,proposal,proposal_hash,created_at,valid_until)
 VALUES(p_user_id,p_operation_key,(c#>>'{facts,anchor,signup_generation}')::uuid,(c#>>'{facts,anchor,signup_epoch}')::uuid,p_context_hash,
  p_selection,sh,p_proposal,ph,(c->>'observed_at')::timestamptz,(c->>'valid_until')::timestamptz) RETURNING * INTO p;
 RETURN private.mobile_clinical_first_phase_prepared(p);
END $$;
CREATE FUNCTION public.prepare_mobile_clinical_first_phase(p_user_id uuid,p_operation_key uuid,p_context_hash text,p_selection jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN PERFORM private.assert_trusted_backend();RETURN private.prepare_mobile_clinical_first_phase_at(p_user_id,p_operation_key,p_context_hash,p_selection,p_proposal,NULL);END $$;

CREATE FUNCTION public.get_mobile_clinical_first_phase_receipt(p_user_id uuid,p_preview_id uuid,p_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE k private.mobile_clinical_first_phase_keys%ROWTYPE;r private.mobile_clinical_first_phase_confirmations%ROWTYPE;
 p private.mobile_clinical_first_phase_previews%ROWTYPE;matched boolean:=false;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_preview_id IS NULL OR p_operation_key IS NULL THEN RAISE EXCEPTION 'invalid_first_phase_receipt_lookup' USING ERRCODE='22023';END IF;
 SELECT * INTO k FROM private.mobile_clinical_first_phase_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF k.first_phase_id<>p_preview_id THEN RAISE EXCEPTION 'first_phase_key_conflict' USING ERRCODE='40001';END IF;
  matched:=true;
 END IF;
 SELECT * INTO r FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id AND first_phase_id=p_preview_id;
 IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO STRICT p FROM private.mobile_clinical_first_phase_previews WHERE user_id=p_user_id AND preview_id=p_preview_id;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,
  'operation_matched',matched,'prepared',private.mobile_clinical_first_phase_prepared(p),'result',r.result);
END $$;
CREATE FUNCTION private.confirm_mobile_clinical_first_phase_at(p_user_id uuid,p_preview_id uuid,p_operation_key uuid,
 p_selection jsonb,p_proposal jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE p private.mobile_clinical_first_phase_previews%ROWTYPE;r private.mobile_clinical_first_phase_confirmations%ROWTYPE;
 k private.mobile_clinical_first_phase_keys%ROWTYPE;c jsonb;f jsonb;profile jsonb;observed timestamptz;day date;
 phase text;deficit integer;sh text;ph text;ih text;event uuid:=gen_random_uuid();episode uuid:=gen_random_uuid();written uuid;
 result jsonb;gen uuid;epoch uuid;next_no bigint;origin uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_preview_id IS NULL OR p_operation_key IS NULL OR p_selection IS NULL OR p_proposal IS NULL
  OR octet_length(p_selection::text)>1024 OR octet_length(p_proposal::text)>8192 THEN
  RAISE EXCEPTION 'invalid_first_phase_confirm' USING ERRCODE='22023';END IF;
 sh:=encode(extensions.digest(p_selection::text,'sha256'),'hex');ph:=encode(extensions.digest(p_proposal::text,'sha256'),'hex');
 ih:=encode(extensions.digest(jsonb_build_object('preview',p_preview_id,'selection_hash',sh,'proposal_hash',ph)::text,'sha256'),'hex');
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO p FROM private.mobile_clinical_first_phase_previews WHERE user_id=p_user_id AND preview_id=p_preview_id;
 IF NOT FOUND OR p.selection_hash<>sh OR p.proposal_hash<>ph THEN RAISE EXCEPTION 'first_phase_original_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO k FROM private.mobile_clinical_first_phase_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND AND (k.first_phase_id<>p_preview_id OR k.input_hash<>ih) THEN RAISE EXCEPTION 'first_phase_key_conflict' USING ERRCODE='40001';END IF;
 SELECT * INTO r FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id AND first_phase_id=p_preview_id;
 IF FOUND THEN
  IF k.operation_key IS NULL THEN INSERT INTO private.mobile_clinical_first_phase_keys VALUES(p_user_id,p_operation_key,p_preview_id,ih,coalesce(p_observed_at,clock_timestamp()));END IF;
  RETURN jsonb_build_object('user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,'result',r.result);
 END IF;
 c:=private.capture_mobile_clinical_first_phase_at(p_user_id,p_observed_at);observed:=(c->>'observed_at')::timestamptz;
 IF c->>'context_hash'<>p.context_hash OR observed<p.created_at OR observed>=p.valid_until THEN
  RAISE EXCEPTION 'first_phase_context_changed' USING ERRCODE='40001';END IF;
 PERFORM private.assert_mobile_clinical_first_phase_package(c,p_selection,p_proposal);
 f:=c->'facts';profile:=f->'profile';gen:=(f#>>'{anchor,signup_generation}')::uuid;epoch:=(f#>>'{anchor,signup_epoch}')::uuid;
 phase:=p.selection->>'phase';deficit:=(p.proposal->>'deficitLevel')::integer;day:=(f->>'calculation_date')::date;
 INSERT INTO private.mobile_clinical_write_permits VALUES(p_user_id,pg_current_xact_id(),p_preview_id);
 UPDATE public.user_profiles SET current_protocol=phase::public.protocol_enum,deficit_level=deficit,updated_at=observed
  WHERE user_id=p_user_id AND current_protocol IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'first_phase_profile_changed' USING ERRCODE='40001';END IF;
 DELETE FROM private.mobile_clinical_write_permits WHERE user_id=p_user_id AND transaction_id=pg_current_xact_id();
 IF NOT coalesce((f#>>'{day,day_closed}')::boolean,false) THEN
  INSERT INTO public.daily_snapshots AS d(user_id,date,current_protocol,calories_target,protein_target,updated_at)
  VALUES(p_user_id,day,phase::public.protocol_enum,(p.proposal#>>'{targets,afterKcal}')::integer,(p.proposal#>>'{targets,afterProtein}')::numeric,observed)
  ON CONFLICT(user_id,date) DO UPDATE SET current_protocol=excluded.current_protocol,calories_target=excluded.calories_target,
   protein_target=excluded.protein_target,updated_at=excluded.updated_at WHERE NOT d.day_closed RETURNING id INTO written;
  IF written IS NULL THEN RAISE EXCEPTION 'first_phase_day_changed' USING ERRCODE='40001';END IF;
 END IF;
 result:=jsonb_build_object('version',1,'source','confirmed_first_phase_v1','first_phase_id',p_preview_id,'event_id',event,'episode_id',episode,
  'signup_generation',gen,'signup_epoch',epoch,'phase',phase,'deficit_level',deficit,'decision_date',day,
  'effective_date',p.proposal->'effectiveDate','confirmed_at',to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'applied_snapshot_id',written,'targets',jsonb_build_object('calories_target',p.proposal#>'{targets,afterKcal}',
   'protein_target',p.proposal#>'{targets,afterProtein}','formula_target',p.proposal#>'{targets,formulaAfterKcal}'),
  'maintenance_since',p.proposal#>'{episode,maintenanceSince}');
 INSERT INTO private.mobile_clinical_first_phase_confirmations(user_id,first_phase_id,signup_generation,signup_epoch,event_id,episode_id,
  phase,deficit_level,decision_date,effective_date,confirmed_at,context_hash,command_hash,proposal,applied_snapshot_id,result)
 VALUES(p_user_id,p_preview_id,gen,epoch,event,episode,phase,deficit,day,(p.proposal->>'effectiveDate')::date,observed,p.context_hash,sh,p.proposal,written,result);
 SELECT coalesce(max(event_no),0)+1 INTO next_no FROM private.mobile_clinical_episode_events WHERE user_id=p_user_id AND signup_generation=gen;
 INSERT INTO private.mobile_clinical_episode_events(user_id,signup_generation,signup_epoch,review_id,first_phase_id,event_id,event_no,
  previous_event_id,episode_id,phase,entry_origin,entry_date,start_weight_kg,start_height_cm,start_body_fat_percent,
  start_training_frequency,maintenance_since,deficit_level,difficulty_count,ledger_steps,schedule,applied_at,rule_version)
 VALUES(p_user_id,gen,epoch,NULL,p_preview_id,event,next_no,NULL,episode,phase,'confirmed_phase_change',day,
  (profile->>'weight_kg')::numeric,(profile->>'height_cm')::numeric,(profile->>'body_fat_percent')::numeric,
  (profile->>'training_frequency')::smallint,(p.proposal#>>'{episode,maintenanceSince}')::date,deficit,
  CASE WHEN phase='recomposicao' THEN 0 END,CASE WHEN phase<>'recomposicao' THEN '{}'::integer[] END,NULL,observed,'clinical-v1');
 IF written IS NOT NULL THEN
  INSERT INTO private.mobile_clinical_target_origins(user_id,signup_generation,signup_epoch,snapshot_id,date,phase,calories_target,
   protein_target,formula_target,context_hash,recorded_at,origin_kind,deficit_level,first_phase_id)
  VALUES(p_user_id,gen,epoch,written,day,phase,(p.proposal#>>'{targets,afterKcal}')::integer,
   (p.proposal#>>'{targets,afterProtein}')::numeric,(p.proposal#>>'{targets,formulaAfterKcal}')::integer,p.context_hash,observed,'calculated',deficit,p_preview_id)
  RETURNING origin_id INTO origin;
  INSERT INTO private.mobile_clinical_target_origin_heads VALUES(written,p_user_id,origin)
   ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,origin_id=excluded.origin_id;
 END IF;
 INSERT INTO private.mobile_clinical_first_phase_keys VALUES(p_user_id,p_operation_key,p_preview_id,ih,observed);
 RETURN jsonb_build_object('user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,'result',result);
END $$;
CREATE FUNCTION public.confirm_mobile_clinical_first_phase(p_user_id uuid,p_preview_id uuid,p_operation_key uuid,p_selection jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN PERFORM private.assert_trusted_backend();RETURN private.confirm_mobile_clinical_first_phase_at(p_user_id,p_preview_id,p_operation_key,p_selection,p_proposal,NULL);END $$;

REVOKE ALL ON FUNCTION private.mobile_clinical_first_phase_prepared(private.mobile_clinical_first_phase_previews),
 private.assert_mobile_clinical_first_phase_package(jsonb,jsonb,jsonb),
 private.prepare_mobile_clinical_first_phase_at(uuid,uuid,text,jsonb,jsonb,timestamptz),
 private.confirm_mobile_clinical_first_phase_at(uuid,uuid,uuid,jsonb,jsonb,timestamptz),
 public.get_mobile_clinical_first_phase_prepared(uuid,uuid,uuid),public.get_mobile_clinical_first_phase_receipt(uuid,uuid,uuid),
 public.prepare_mobile_clinical_first_phase(uuid,uuid,text,jsonb,jsonb),public.confirm_mobile_clinical_first_phase(uuid,uuid,uuid,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_first_phase_prepared(uuid,uuid,uuid),
 public.get_mobile_clinical_first_phase_receipt(uuid,uuid,uuid),public.prepare_mobile_clinical_first_phase(uuid,uuid,text,jsonb,jsonb),
 public.confirm_mobile_clinical_first_phase(uuid,uuid,uuid,jsonb,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION private.mobile_clinical_target_origin(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_date date,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE evidence private.mobile_clinical_target_origins%ROWTYPE;day public.daily_snapshots%ROWTYPE;
BEGIN
 SELECT * INTO day FROM public.daily_snapshots WHERE user_id=p_user_id AND date=p_date;
 SELECT e.* INTO evidence FROM private.mobile_clinical_target_origin_heads h
  JOIN private.mobile_clinical_target_origins e ON e.user_id=h.user_id AND e.origin_id=h.origin_id
  WHERE h.snapshot_id=day.id AND h.user_id=p_user_id;
 IF NOT FOUND OR evidence.signup_generation IS DISTINCT FROM p_generation
  OR evidence.signup_epoch IS DISTINCT FROM p_epoch OR evidence.recorded_at>p_observed_at THEN RETURN NULL;END IF;
 IF ROW(evidence.snapshot_id,evidence.user_id,evidence.date,evidence.phase,evidence.calories_target)
  IS DISTINCT FROM ROW(day.id,day.user_id,day.date,day.current_protocol::text,day.calories_target) THEN
  RAISE EXCEPTION 'mobile_clinical_target_origin_inconsistent' USING ERRCODE='XX001';END IF;
 RETURN private.mobile_clinical_canonical_row(to_jsonb(evidence),ARRAY['recorded_at'],ARRAY[]::text[])
  ||jsonb_build_object('version',1,'source',CASE WHEN evidence.first_phase_id IS NOT NULL THEN 'clinical_first_phase_v1'
   WHEN evidence.signup_application_id IS NOT NULL THEN 'clinical_signup_v1'
   WHEN evidence.application_id IS NOT NULL THEN 'clinical_daily_v1' ELSE 'clinical_full_v1' END,'target_component','calories');
END $$;
CREATE OR REPLACE FUNCTION private.mobile_clinical_confirmed_calorie_decision(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_date date,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE d private.mobile_clinical_calorie_decisions%ROWTYPE;e private.mobile_clinical_episode_events%ROWTYPE;
 c private.mobile_clinical_full_commands%ROWTYPE;p private.mobile_clinical_previews%ROWTYPE;
 initial private.mobile_clinical_first_phase_confirmations%ROWTYPE;preview private.mobile_clinical_first_phase_previews%ROWTYPE;
BEGIN
 e:=private.mobile_clinical_effective_episode(p_user_id,p_generation,p_epoch);
 IF e.event_id IS NULL THEN RETURN NULL;END IF;
 IF e.first_phase_id IS NOT NULL THEN
  SELECT * INTO STRICT initial FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=p_user_id
   AND first_phase_id=e.first_phase_id AND event_id=e.event_id AND signup_generation=p_generation AND signup_epoch=p_epoch;
  IF initial.confirmed_at>p_observed_at OR initial.effective_date>p_date THEN RETURN NULL;END IF;
  SELECT * INTO STRICT preview FROM private.mobile_clinical_first_phase_previews WHERE user_id=p_user_id AND preview_id=initial.first_phase_id;
  IF preview.context_hash<>initial.context_hash OR preview.selection_hash<>initial.command_hash
   OR preview.proposal<>initial.proposal OR initial.phase<>e.phase THEN
   RAISE EXCEPTION 'clinical_first_phase_decision_inconsistent' USING ERRCODE='XX001';END IF;
  RETURN jsonb_build_object('version',1,'source','confirmed_first_phase_calculation_v1','user_id',p_user_id,
   'signup_generation',p_generation,'signup_epoch',p_epoch,'review_id',NULL,'first_phase_id',initial.first_phase_id,
   'source_episode_event_id',e.event_id,'phase',e.phase,'decision_kind','calculated',
   'calories_target',initial.proposal#>'{targets,afterKcal}','formula_target',initial.proposal#>'{targets,formulaAfterKcal}',
   'decision_date',initial.decision_date,'valid_from_date',initial.effective_date,
   'decided_at',to_char(initial.confirmed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'command_hash',initial.command_hash,'context_hash',initial.context_hash);
 END IF;
 SELECT * INTO d FROM private.mobile_clinical_calorie_decisions WHERE user_id=p_user_id AND review_id=e.review_id
  AND source_episode_event_id=e.event_id AND signup_generation=p_generation AND signup_epoch=p_epoch;
 IF NOT FOUND OR d.decided_at>p_observed_at
  OR (d.decided_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date>p_date THEN RETURN NULL;END IF;
 SELECT * INTO STRICT c FROM private.mobile_clinical_full_commands WHERE user_id=p_user_id AND preview_id=d.review_id;
 SELECT * INTO STRICT p FROM private.mobile_clinical_previews WHERE user_id=p_user_id AND preview_id=d.review_id;
 PERFORM private.mobile_clinical_full_command_wire(p,c);
 IF c.command_hash<>d.command_hash OR p.context_hash<>d.context_hash THEN
  RAISE EXCEPTION 'clinical_calorie_decision_inconsistent' USING ERRCODE='XX001';END IF;
 RETURN jsonb_build_object('version',1,'source','confirmed_full_calculation_v1','user_id',p_user_id,
  'signup_generation',p_generation,'signup_epoch',p_epoch,'review_id',d.review_id,'source_episode_event_id',e.event_id,
  'phase',e.phase,'decision_kind',d.decision_kind,'calories_target',d.calories_target,'formula_target',d.formula_target,
  'decision_date',d.decision_date,'valid_from_date',(d.decided_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date,
  'decided_at',to_char(d.decided_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'command_hash',d.command_hash,'context_hash',d.context_hash);
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_target_origin(uuid,uuid,uuid,date,timestamptz),
 private.mobile_clinical_confirmed_calorie_decision(uuid,uuid,uuid,date,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

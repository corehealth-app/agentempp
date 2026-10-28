-- Dormant assigned-signup applications before any FULL. Real signup source,
-- never a fabricated review/event or a backfill of historical formula input.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_calorie_decisions') IS NULL THEN
  RAISE EXCEPTION 'signup_targets_require_clinical_authority' USING ERRCODE='42501'; END IF;
END $$;
CREATE TABLE private.mobile_clinical_signup_applications (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 application_id uuid NOT NULL DEFAULT gen_random_uuid(),
 signup_generation uuid NOT NULL,signup_epoch uuid NOT NULL,signup_episode_id uuid NOT NULL,
 application_no bigint NOT NULL CHECK(application_no>0),
 date date NOT NULL CHECK(isfinite(date)),timezone_at_application text NOT NULL,
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 deficit_level integer CHECK(deficit_level IN(400,500,600)),
 context_hash text NOT NULL CHECK(context_hash ~ '^[a-f0-9]{64}$'),
 post_fingerprint text NOT NULL CHECK(post_fingerprint ~ '^[a-f0-9]{64}$'),
 reason text NOT NULL CHECK(reason IN('signup_formula','signup_stored_target','signup_preserved_unknown','safety')),
 snapshot_id uuid,previous_snapshot_id uuid,parent_origin_id uuid,
 calories_target integer CHECK(calories_target>0),protein_target numeric(6,2) CHECK(protein_target BETWEEN 0 AND 9999.99),
 formula_target integer CHECK(formula_target>0),calculation jsonb NOT NULL CHECK(jsonb_typeof(calculation)='object'),
 applied_at timestamptz NOT NULL CHECK(isfinite(applied_at)),result jsonb NOT NULL,
 PRIMARY KEY(user_id,application_id),UNIQUE(user_id,signup_generation,application_no),
 FOREIGN KEY(user_id,signup_generation) REFERENCES private.mobile_clinical_signup_origins(user_id,signup_generation) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,signup_episode_id) REFERENCES private.mobile_clinical_signup_origins(user_id,episode_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,parent_origin_id) REFERENCES private.mobile_clinical_target_origins(user_id,origin_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((phase='recomposicao')=(deficit_level IS NOT NULL)),
 CHECK(reason<>'signup_formula' OR (calories_target IS NOT NULL AND calories_target=formula_target AND snapshot_id IS NOT NULL))
);
CREATE TABLE private.mobile_clinical_signup_application_keys (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,operation_key uuid NOT NULL,
 request_hash text NOT NULL CHECK(request_hash ~ '^[a-f0-9]{64}$'),application_id uuid NOT NULL,
 result jsonb NOT NULL,acknowledged_at timestamptz NOT NULL CHECK(isfinite(acknowledged_at)),
 PRIMARY KEY(user_id,operation_key),
 FOREIGN KEY(user_id,application_id) REFERENCES private.mobile_clinical_signup_applications(user_id,application_id) DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE private.mobile_clinical_signup_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_signup_application_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_signup_applications,private.mobile_clinical_signup_application_keys FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_signup_application_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_signup_applications
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();
CREATE TRIGGER mobile_clinical_signup_application_key_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_signup_application_keys
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();
ALTER TABLE private.mobile_clinical_target_origins ADD COLUMN signup_application_id uuid,
 ADD UNIQUE(user_id,signup_application_id),
 ADD FOREIGN KEY(user_id,signup_application_id) REFERENCES private.mobile_clinical_signup_applications(user_id,application_id) DEFERRABLE INITIALLY DEFERRED;
DO $$ DECLARE c record;n integer:=0;BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='private.mobile_clinical_target_origins'::regclass
  AND contype='c' AND pg_get_expr(conbin,conrelid) LIKE '%num_nonnulls(review_id, application_id)%' LOOP
  n:=n+1;EXECUTE format('ALTER TABLE private.mobile_clinical_target_origins DROP CONSTRAINT %I',c.conname);
 END LOOP;
 IF n<>1 THEN RAISE EXCEPTION 'unknown_calorie_origin_source_constraint'; END IF;
END $$;
ALTER TABLE private.mobile_clinical_target_origins ADD CONSTRAINT mobile_clinical_target_origin_one_source
 CHECK(num_nonnulls(review_id,application_id,signup_application_id)=1);

CREATE FUNCTION private.mobile_clinical_signup_fingerprint(p_user_id uuid,p_generation uuid,p_epoch uuid,p_episode uuid,
 p_date date,p_config jsonb,p_safety jsonb) RETURNS text
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT encode(extensions.digest(jsonb_build_object('source','signup','signup_episode',p_episode,
  'inputs',private.mobile_clinical_daily_fingerprint(p_user_id,NULL,p_generation,p_epoch,p_date,p_config,p_safety))::text,'sha256'),'hex')
$$;
CREATE FUNCTION private.apply_mobile_clinical_signup_targets(p_user_id uuid,p_key uuid,p_context jsonb,p_calculation jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' AS $$
DECLARE o private.mobile_clinical_signup_origins%ROWTYPE;receipt private.mobile_signup_strength_completion_receipts%ROWTYPE;
 profile public.user_profiles%ROWTYPE;s public.daily_snapshots%ROWTYPE;prior public.daily_snapshots%ROWTYPE;
 head private.mobile_clinical_signup_applications%ROWTYPE;v_generation uuid;epoch uuid;today date;observed timestamptz;
 safety jsonb;basis jsonb;fingerprint text;request_hash text;app uuid:=gen_random_uuid();seq bigint;result jsonb;
 calories integer;protein numeric;formula integer;reason text;blocked boolean;years integer;origin uuid;written uuid;source_kind text;
BEGIN
 PERFORM private.assert_trusted_backend();
 v_generation:=(p_context#>>'{facts,anchor,signup_generation}')::uuid;epoch:=(p_context#>>'{facts,anchor,signup_epoch}')::uuid;
 today:=(p_context#>>'{facts,calculation_date}')::date;observed:=(p_context->>'observed_at')::timestamptz;
 safety:=p_context#>'{facts,safety}';
 SELECT * INTO STRICT o FROM private.mobile_clinical_signup_origins WHERE user_id=p_user_id AND signup_generation=v_generation AND signup_epoch=epoch;
 SELECT * INTO STRICT receipt FROM private.mobile_signup_strength_completion_receipts WHERE user_id=p_user_id AND admission_id=v_generation;
 SELECT * INTO STRICT profile FROM public.user_profiles WHERE user_id=p_user_id;
 IF p_context->>'user_id'<>p_user_id::text OR p_context->>'review_kind'<>'APPLICATION'
  OR receipt.outcome IS DISTINCT FROM 'first_fresh' OR receipt.epoch IS DISTINCT FROM epoch OR receipt.completed_at IS DISTINCT FROM o.started_at
  OR profile.onboarding_completed_at IS DISTINCT FROM o.started_at OR profile.onboarding_completed IS DISTINCT FROM true
  OR receipt.completion_result->>'objective' IS DISTINCT FROM o.phase OR profile.current_protocol::text IS DISTINCT FROM o.phase
  OR profile.deficit_level IS DISTINCT FROM o.deficit_level OR o.captured_at>observed
  OR EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=p_user_id AND signup_generation=v_generation AND signup_epoch=epoch) THEN
  RAISE EXCEPTION 'mobile_clinical_signup_source_changed' USING ERRCODE='40001'; END IF;
 request_hash:=encode(extensions.digest(jsonb_build_object('context_hash',p_context->>'context_hash','calculation',p_calculation)::text,'sha256'),'hex');
 fingerprint:=private.mobile_clinical_signup_fingerprint(p_user_id,v_generation,epoch,o.episode_id,today,p_context#>'{facts,calculation_config}',safety);
 SELECT * INTO head FROM private.mobile_clinical_signup_applications WHERE user_id=p_user_id AND signup_generation=v_generation
  AND signup_epoch=epoch ORDER BY application_no DESC LIMIT 1;
 IF head.date=today AND head.post_fingerprint=fingerprint THEN
  INSERT INTO private.mobile_clinical_signup_application_keys VALUES(p_user_id,p_key,request_hash,head.application_id,head.result,observed);
  RETURN head.result;
 END IF;
 SELECT * INTO s FROM public.daily_snapshots WHERE user_id=p_user_id AND date=today;
 IF coalesce(s.day_closed,false) THEN RAISE EXCEPTION 'mobile_clinical_signup_day_closed' USING ERRCODE='40001';END IF;
 years:=CASE WHEN profile.birth_date IS NOT NULL AND profile.birth_date<=today THEN extract(year FROM age(today,profile.birth_date))::integer END;
 blocked:=years IS NULL OR years<18 OR profile.height_cm IS NULL OR profile.weight_kg IS NULL
  OR profile.weight_kg/power(profile.height_cm/100,2)<18.5 OR coalesce(profile.body_fat_percent<=10,false)
  OR coalesce((safety->>'hold_active')::boolean,false) OR coalesce((safety->>'declared_no_plan')::boolean,false);
 IF s.calories_target IS NOT NULL THEN
  calories:=s.calories_target;protein:=s.protein_target;reason:=CASE WHEN blocked THEN 'safety' ELSE 'signup_stored_target' END;
 ELSE
  -- The previous target is inspected under a nonblocking lock. Timestamps
  -- do not prove signup membership (defaults may use transaction start).
  -- An unknown old formula is never relabelled as a new calculation.
  BEGIN
   SELECT * INTO prior FROM public.daily_snapshots WHERE user_id=p_user_id AND date<today
    AND calories_target IS NOT NULL ORDER BY date DESC LIMIT 1 FOR UPDATE NOWAIT;
  EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'mobile_clinical_busy' USING ERRCODE='55P03';END;
  IF prior.id IS NOT NULL THEN
   IF prior.current_protocol::text IS DISTINCT FROM o.phase THEN RAISE EXCEPTION 'mobile_clinical_signup_prior_phase_changed' USING ERRCODE='40001';END IF;
   basis:=private.mobile_clinical_target_origin(p_user_id,v_generation,epoch,prior.date,observed);
  END IF;
  IF blocked OR (prior.id IS NOT NULL AND basis IS NULL) THEN
   calories:=prior.calories_target;protein:=prior.protein_target;formula:=(basis->>'formula_target')::integer;
   reason:=CASE WHEN blocked THEN 'safety' ELSE 'signup_preserved_unknown' END;source_kind:='carried';
  ELSE
   calories:=(p_calculation->>'formulaKcal')::integer;protein:=(p_calculation->>'proteinTarget')::numeric;formula:=calories;
   IF calories IS NULL OR protein IS NULL THEN RAISE EXCEPTION 'mobile_clinical_calculation_unavailable' USING ERRCODE='40001';END IF;
   reason:='signup_formula';source_kind:='calculated';
  END IF;
  IF calories IS NOT NULL THEN
   INSERT INTO public.daily_snapshots AS actual(user_id,date,calories_target,protein_target,current_protocol,updated_at)
   VALUES(p_user_id,today,calories,protein,o.phase::public.protocol_enum,observed)
   ON CONFLICT(user_id,date) DO UPDATE SET calories_target=excluded.calories_target,protein_target=excluded.protein_target,
    current_protocol=excluded.current_protocol,updated_at=excluded.updated_at WHERE NOT actual.day_closed
   RETURNING id INTO written;
   IF written IS NULL THEN RAISE EXCEPTION 'mobile_clinical_signup_target_changed' USING ERRCODE='40001';END IF;
  END IF;
 END IF;
 SELECT coalesce(max(application_no),0)+1 INTO seq FROM private.mobile_clinical_signup_applications WHERE user_id=p_user_id AND signup_generation=v_generation;
 fingerprint:=private.mobile_clinical_signup_fingerprint(p_user_id,v_generation,epoch,o.episode_id,today,p_context#>'{facts,calculation_config}',safety);
 result:=jsonb_build_object('version',1,'availability','applied','source_kind','signup','application_id',app,'application_no',seq::text,
  'date',today,'state','none','reason',reason,'needs_new_confirmation',false,
  'applied_at',to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'source_review_id',NULL,
  'source_signup_id',v_generation,'schedule_review_id',NULL,
  'targets',jsonb_build_object('calories_target',calories,'protein_target',protein,'formula_target',formula,'effective_adjustment',calories-formula),
  'episode',jsonb_build_object('user_id',p_user_id,'signup_generation',v_generation,'signup_epoch',epoch));
 INSERT INTO private.mobile_clinical_signup_applications(user_id,application_id,signup_generation,signup_epoch,signup_episode_id,
  application_no,date,timezone_at_application,phase,deficit_level,context_hash,post_fingerprint,reason,snapshot_id,previous_snapshot_id,parent_origin_id,
  calories_target,protein_target,formula_target,calculation,applied_at,result)
 VALUES(p_user_id,app,v_generation,epoch,o.episode_id,seq,today,p_context#>>'{facts,owner,timezone}',o.phase,o.deficit_level,
  p_context->>'context_hash',fingerprint,reason,written,prior.id,(basis->>'origin_id')::uuid,calories,protein,formula,p_calculation,observed,result);
 IF written IS NOT NULL AND formula IS NOT NULL THEN
  INSERT INTO private.mobile_clinical_target_origins(user_id,signup_generation,signup_epoch,snapshot_id,date,phase,calories_target,
   protein_target,formula_target,context_hash,recorded_at,origin_kind,deficit_level,parent_origin_id,signup_application_id)
  VALUES(p_user_id,v_generation,epoch,written,today,o.phase,calories,protein,formula,p_context->>'context_hash',observed,source_kind,
   o.deficit_level,(basis->>'origin_id')::uuid,app) RETURNING origin_id INTO origin;
  INSERT INTO private.mobile_clinical_target_origin_heads VALUES(written,p_user_id,origin)
   ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,origin_id=excluded.origin_id;
 END IF;
 INSERT INTO private.mobile_clinical_signup_application_keys VALUES(p_user_id,p_key,request_hash,app,result,observed);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_signup_fingerprint(uuid,uuid,uuid,uuid,date,jsonb,jsonb),
 private.apply_mobile_clinical_signup_targets(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
-- The existing service-only transport stays the one entry. Its getter is
-- extended after its authority dispatch gains signup receipt-first handling.
CREATE OR REPLACE FUNCTION private.mobile_clinical_target_origin(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_date date,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE evidence private.mobile_clinical_target_origins%ROWTYPE;day public.daily_snapshots%ROWTYPE;
BEGIN
 SELECT d.* INTO day FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=p_date;
 SELECT e.* INTO evidence FROM private.mobile_clinical_target_origin_heads h
  JOIN private.mobile_clinical_target_origins e ON e.user_id=h.user_id AND e.origin_id=h.origin_id
  WHERE h.snapshot_id=day.id AND h.user_id=p_user_id;
 IF NOT FOUND OR evidence.signup_generation IS DISTINCT FROM p_generation
  OR evidence.signup_epoch IS DISTINCT FROM p_epoch OR evidence.recorded_at>p_observed_at THEN RETURN NULL; END IF;
 IF ROW(evidence.snapshot_id,evidence.user_id,evidence.date,evidence.phase,evidence.calories_target)
  IS DISTINCT FROM ROW(day.id,day.user_id,day.date,day.current_protocol::text,day.calories_target) THEN
  RAISE EXCEPTION 'mobile_clinical_target_origin_inconsistent' USING ERRCODE='XX001';
 END IF;
 RETURN private.mobile_clinical_canonical_row(to_jsonb(evidence),ARRAY['recorded_at'],ARRAY[]::text[])
  ||jsonb_build_object('version',1,'source',CASE WHEN evidence.signup_application_id IS NOT NULL THEN 'clinical_signup_v1' WHEN evidence.application_id IS NULL THEN 'clinical_full_v1' ELSE 'clinical_daily_v1' END,'target_component','calories');
END $$;
CREATE OR REPLACE FUNCTION public.get_mobile_clinical_daily_receipt(p_user_id uuid,p_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE packet jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_daily_receipt_key' USING ERRCODE='22023'; END IF;
 SELECT jsonb_build_object('user_id',k.user_id,'operation_key',k.operation_key,'result',k.result)
  INTO packet FROM private.mobile_clinical_daily_keys k WHERE k.user_id=p_user_id AND k.operation_key=p_operation_key;
 IF FOUND THEN RETURN packet;END IF;
 SELECT jsonb_build_object('user_id',k.user_id,'operation_key',k.operation_key,'result',k.result)
  INTO packet FROM private.mobile_clinical_signup_application_keys k WHERE k.user_id=p_user_id AND k.operation_key=p_operation_key;
 RETURN packet;
END $$;
REVOKE ALL ON FUNCTION public.get_mobile_clinical_daily_receipt(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_daily_receipt(uuid,uuid) TO service_role;
COMMIT;

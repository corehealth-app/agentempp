-- Capture future genuine signup entry baselines in the existing transaction.
-- No historical backfill or writer replacement; unknown legacy stays unknown.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.mobile_clinical_protocol_authority(uuid,uuid,uuid,uuid,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_requires_snapshot_authority' USING ERRCODE='42501';
 END IF;
END $$;

CREATE TABLE private.mobile_clinical_signup_origins (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 episode_id uuid NOT NULL DEFAULT gen_random_uuid(),
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 started_at timestamptz NOT NULL CHECK(isfinite(started_at)),
 start_date date NOT NULL CHECK(isfinite(start_date)),
 timezone_at_entry text NOT NULL,
 start_weight_kg numeric(5,2) NOT NULL CHECK(start_weight_kg BETWEEN 30 AND 300),
 start_height_cm numeric NOT NULL CHECK(start_height_cm>0),
 start_body_fat_percent numeric CHECK(start_body_fat_percent BETWEEN 3 AND 60),
 start_training_frequency smallint CHECK(start_training_frequency BETWEEN 0 AND 7),
 start_activity_level text CHECK(start_activity_level IN('sedentario','leve','moderado','alto','atleta')),
 deficit_level integer CHECK(deficit_level IN(400,500,600)),
 maintenance_since date,
 captured_at timestamptz NOT NULL CHECK(isfinite(captured_at) AND captured_at>=started_at),
 rule_version text NOT NULL CHECK(rule_version='clinical-v1'),
 PRIMARY KEY(user_id,signup_generation), UNIQUE(user_id,episode_id),
 FOREIGN KEY(user_id,signup_generation)
  REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((phase='recomposicao')=(deficit_level IS NOT NULL)),
 CHECK((phase='manutencao')=(maintenance_since IS NOT NULL)),
 CHECK(maintenance_since IS NULL OR maintenance_since=start_date)
);
ALTER TABLE private.mobile_clinical_signup_origins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_signup_origins FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_signup_origin_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_signup_origins FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.capture_mobile_clinical_signup_origin() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; profile_row public.user_profiles%ROWTYPE; phase text; zone text; local_day date;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF NEW.outcome<>'first_fresh' THEN RETURN NULL; END IF;
 phase:=NEW.completion_result->>'objective';
 -- Older receipt formats omit objective. Do not manufacture initial clinical
 -- facts by reading a mutable profile at a later observation.
 IF phase IS NULL OR phase NOT IN('recomposicao','manutencao','ganho_massa') THEN RETURN NULL; END IF;
 context:=private.mobile_reevaluation_context_at(NEW.user_id,NULL);
 IF context->>'signup_generation' IS DISTINCT FROM NEW.admission_id::text
  OR context->>'signup_epoch' IS DISTINCT FROM NEW.epoch::text THEN
  RAISE EXCEPTION 'mobile_clinical_signup_origin_inconsistent' USING ERRCODE='XX001';
 END IF;
 SELECT * INTO STRICT profile_row FROM public.user_profiles WHERE user_id=NEW.user_id;
 IF profile_row.current_protocol::text IS DISTINCT FROM phase
  OR profile_row.onboarding_completed IS DISTINCT FROM true
  OR profile_row.onboarding_completed_at IS DISTINCT FROM NEW.completed_at THEN
  RAISE EXCEPTION 'mobile_clinical_signup_origin_inconsistent' USING ERRCODE='XX001';
 END IF;
 zone:=context#>>'{clock,timezone}';
 local_day:=(NEW.completed_at AT TIME ZONE zone)::date;
 INSERT INTO private.mobile_clinical_signup_origins(user_id,signup_generation,signup_epoch,
  phase,started_at,start_date,timezone_at_entry,start_weight_kg,start_height_cm,start_body_fat_percent,
  start_training_frequency,start_activity_level,deficit_level,maintenance_since,captured_at,rule_version)
 VALUES(NEW.user_id,NEW.admission_id,NEW.epoch,phase,NEW.completed_at,local_day,zone,
  profile_row.weight_kg,profile_row.height_cm,profile_row.body_fat_percent,
  profile_row.training_frequency,profile_row.activity_level::text,
  CASE WHEN phase='recomposicao' THEN coalesce(profile_row.deficit_level,500) END,
  CASE WHEN phase='manutencao' THEN local_day END,NEW.recorded_at,'clinical-v1');
 RETURN NULL;
END $$;
CREATE TRIGGER capture_mobile_clinical_signup_origin AFTER INSERT
 ON private.mobile_signup_strength_completion_receipts FOR EACH ROW
 EXECUTE FUNCTION private.capture_mobile_clinical_signup_origin();

CREATE OR REPLACE FUNCTION private.mobile_clinical_protocol_authority(p_user_id uuid,p_generation uuid,p_epoch uuid,p_cycle_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('signup_origin',coalesce((
  SELECT private.mobile_clinical_canonical_row(to_jsonb(o),ARRAY['started_at','captured_at'],ARRAY[]::text[])
  FROM private.mobile_clinical_signup_origins o
  WHERE o.user_id=p_user_id AND o.signup_generation=p_generation AND o.signup_epoch=p_epoch),'null'::jsonb))
$$;
REVOKE ALL ON FUNCTION private.capture_mobile_clinical_signup_origin(),
 private.mobile_clinical_protocol_authority(uuid,uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

-- Structural source registry for clinical generations. This is not a signup,
-- a FULL receipt, a calendar anchor or proof of present eligibility. All those
-- checks remain in their authorities. No public route/grant/flag is enabled.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_legacy_admissions') IS NULL
  OR to_regclass('private.mobile_signup_strength_completion_receipts') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_generation_requires_sources' USING ERRCODE='42501';
 END IF;
 IF to_regclass('private.mobile_clinical_generation_sources') IS NOT NULL THEN
  RAISE EXCEPTION 'mobile_clinical_generation_unknown_existing_registry' USING ERRCODE='42P07';
 END IF;
END $preflight$;

CREATE TABLE private.mobile_clinical_generation_sources(
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 generation uuid NOT NULL,
 epoch uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('signup_receipt','legacy_transition')),
 signup_admission_id uuid,
 legacy_generation uuid,
 registered_at timestamptz NOT NULL DEFAULT clock_timestamp() CHECK(isfinite(registered_at)),
 PRIMARY KEY(user_id,generation),
 FOREIGN KEY(user_id,signup_admission_id)
  REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) ON DELETE CASCADE,
 FOREIGN KEY(user_id,legacy_generation)
  REFERENCES private.mobile_clinical_legacy_admissions(user_id,generation) ON DELETE CASCADE,
 CHECK(((kind='signup_receipt' AND signup_admission_id=generation AND legacy_generation IS NULL)
  OR (kind='legacy_transition' AND legacy_generation=generation AND signup_admission_id IS NULL)) IS TRUE)
);
ALTER TABLE private.mobile_clinical_generation_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_clinical_generation_sources FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.guard_mobile_clinical_generation_source() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE source_epoch uuid;
BEGIN
 IF TG_OP='DELETE' THEN
  -- Derived referential metadata follows its actual source's lifetime. An
  -- existing source cannot lose its registry; final account/source cascades
  -- retain their existing purge order and all dependent clinical FKs.
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)
   OR (OLD.kind='signup_receipt' AND NOT EXISTS(SELECT 1
    FROM private.mobile_signup_strength_completion_receipts WHERE user_id=OLD.user_id AND admission_id=OLD.generation))
   OR (OLD.kind='legacy_transition' AND NOT EXISTS(SELECT 1
    FROM private.mobile_clinical_legacy_admissions WHERE user_id=OLD.user_id AND generation=OLD.generation)) THEN
   RETURN OLD;
  END IF;
  RAISE EXCEPTION 'mobile_clinical_generation_source_immutable' USING ERRCODE='55000';
 ELSIF TG_OP='UPDATE' THEN
  RAISE EXCEPTION 'mobile_clinical_generation_source_immutable' USING ERRCODE='55000';
 END IF;
 IF NEW.kind='signup_receipt' AND NEW.signup_admission_id=NEW.generation AND NEW.legacy_generation IS NULL THEN
  SELECT epoch INTO source_epoch FROM private.mobile_signup_strength_completion_receipts
   WHERE user_id=NEW.user_id AND admission_id=NEW.generation;
 ELSIF NEW.kind='legacy_transition' AND NEW.legacy_generation=NEW.generation AND NEW.signup_admission_id IS NULL THEN
  SELECT epoch INTO source_epoch FROM private.mobile_clinical_legacy_admissions
   WHERE user_id=NEW.user_id AND generation=NEW.generation;
 ELSE
  RAISE EXCEPTION 'mobile_clinical_generation_source_shape' USING ERRCODE='23514';
 END IF;
 IF source_epoch IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_generation_source_missing' USING ERRCODE='23503';
 END IF;
 IF source_epoch IS DISTINCT FROM NEW.epoch THEN
  RAISE EXCEPTION 'mobile_clinical_generation_source_epoch' USING ERRCODE='23514';
 END IF;
 NEW.registered_at:=clock_timestamp();
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_generation_source_guard BEFORE INSERT OR UPDATE OR DELETE
 ON private.mobile_clinical_generation_sources FOR EACH ROW
 EXECUTE FUNCTION private.guard_mobile_clinical_generation_source();

CREATE FUNCTION private.register_mobile_clinical_generation_source() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE value jsonb:=to_jsonb(NEW); source_kind text;source_generation uuid;
 owner_id uuid:=(value->>'user_id')::uuid;source_epoch uuid:=(value->>'epoch')::uuid;
 current_source private.mobile_clinical_generation_sources%ROWTYPE;
BEGIN
 IF TG_TABLE_SCHEMA<>'private' THEN
  RAISE EXCEPTION 'mobile_clinical_generation_source_trigger' USING ERRCODE='XX001';
 ELSIF TG_TABLE_NAME='mobile_signup_strength_completion_receipts' THEN
  source_kind:='signup_receipt';source_generation:=(value->>'admission_id')::uuid;
 ELSIF TG_TABLE_NAME='mobile_clinical_legacy_admissions' THEN
  source_kind:='legacy_transition';source_generation:=(value->>'generation')::uuid;
 ELSE
  RAISE EXCEPTION 'mobile_clinical_generation_source_trigger' USING ERRCODE='XX001';
 END IF;
 INSERT INTO private.mobile_clinical_generation_sources(user_id,generation,epoch,kind,
  signup_admission_id,legacy_generation)
 VALUES(owner_id,source_generation,source_epoch,source_kind,
  CASE WHEN source_kind='signup_receipt' THEN source_generation END,
  CASE WHEN source_kind='legacy_transition' THEN source_generation END)
 ON CONFLICT(user_id,generation) DO NOTHING;
 SELECT * INTO STRICT current_source FROM private.mobile_clinical_generation_sources
  WHERE user_id=owner_id AND generation=source_generation;
 IF current_source.kind IS DISTINCT FROM source_kind OR current_source.epoch IS DISTINCT FROM source_epoch THEN
  RAISE EXCEPTION 'mobile_clinical_generation_source_collision' USING ERRCODE='XX001'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_register_signup_source AFTER INSERT
 ON private.mobile_signup_strength_completion_receipts FOR EACH ROW
 EXECUTE FUNCTION private.register_mobile_clinical_generation_source();
CREATE TRIGGER mobile_clinical_register_legacy_source AFTER INSERT
 ON private.mobile_clinical_legacy_admissions FOR EACH ROW
 EXECUTE FUNCTION private.register_mobile_clinical_generation_source();
REVOKE ALL ON FUNCTION private.guard_mobile_clinical_generation_source(),
 private.register_mobile_clinical_generation_source() FROM PUBLIC,anon,authenticated,service_role;

-- Bind existing immutable sources without altering any source/profile/target.
-- The registry records the source type, not first_fresh eligibility. A signup
-- still has to pass the complete original validator before serving as anchor.
INSERT INTO private.mobile_clinical_generation_sources(user_id,generation,epoch,kind,signup_admission_id)
 SELECT user_id,admission_id,epoch,'signup_receipt',admission_id
 FROM private.mobile_signup_strength_completion_receipts;
INSERT INTO private.mobile_clinical_generation_sources(user_id,generation,epoch,kind,legacy_generation)
 SELECT user_id,generation,epoch,'legacy_transition',generation FROM private.mobile_clinical_legacy_admissions;

DO $generic_fks$
DECLARE relation_name text; relation_oid regclass; keys smallint[]; target_keys smallint[];
 candidates oid[]; existing pg_constraint%ROWTYPE; definition text; replacement text;
BEGIN
 target_keys:=ARRAY[
  (SELECT attnum FROM pg_attribute WHERE attrelid='private.mobile_signup_strength_completion_receipts'::regclass AND attname='user_id'),
  (SELECT attnum FROM pg_attribute WHERE attrelid='private.mobile_signup_strength_completion_receipts'::regclass AND attname='admission_id')];
 FOREACH relation_name IN ARRAY ARRAY['mobile_reevaluation_cycles','mobile_clinical_previews',
  'mobile_clinical_full_receipts','mobile_clinical_episode_events','mobile_clinical_daily_applications'] LOOP
  relation_oid:=to_regclass('private.'||relation_name);
  keys:=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=relation_oid AND attname='user_id'),
   (SELECT attnum FROM pg_attribute WHERE attrelid=relation_oid AND attname='signup_generation')];
  SELECT array_agg(c.oid) INTO candidates FROM pg_constraint c WHERE c.conrelid=relation_oid
   AND c.contype='f' AND c.confrelid='private.mobile_signup_strength_completion_receipts'::regclass
   AND c.conkey=keys AND c.confkey=target_keys;
  IF cardinality(candidates) IS DISTINCT FROM 1 THEN
   RAISE EXCEPTION 'mobile_clinical_generation_unknown_fk:%',relation_name USING ERRCODE='XX001'; END IF;
  SELECT * INTO STRICT existing FROM pg_constraint WHERE oid=candidates[1];
  IF existing.confupdtype<>'a' OR existing.confdeltype<>'a' OR NOT existing.convalidated
   OR existing.condeferrable IS DISTINCT FROM (relation_name<>'mobile_reevaluation_cycles')
   OR existing.condeferred IS DISTINCT FROM (relation_name<>'mobile_reevaluation_cycles') THEN
   RAISE EXCEPTION 'mobile_clinical_generation_fk_properties:%',relation_name USING ERRCODE='XX001'; END IF;
  definition:=pg_get_constraintdef(existing.oid);
  replacement:=replace(definition,
   'REFERENCES private.mobile_signup_strength_completion_receipts(user_id, admission_id)',
   'REFERENCES private.mobile_clinical_generation_sources(user_id, generation)');
  IF replacement=definition THEN
   RAISE EXCEPTION 'mobile_clinical_generation_fk_definition:%',relation_name USING ERRCODE='XX001'; END IF;
  EXECUTE format('ALTER TABLE private.%I DROP CONSTRAINT %I',relation_name,existing.conname);
  EXECUTE format('ALTER TABLE private.%I ADD CONSTRAINT %I %s',relation_name,existing.conname,replacement);
 END LOOP;
END $generic_fks$;
COMMIT;

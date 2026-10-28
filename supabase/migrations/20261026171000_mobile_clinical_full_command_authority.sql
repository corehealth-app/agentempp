-- Additive, dormant, backend-only FULL command identity. No route, activation,
-- public clock, clinical calculation or replacement of the original writer.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
  OR to_regclass('private.mobile_clinical_previews') IS NULL
  OR to_regprocedure('private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)') IS NULL
  OR to_regprocedure('public.get_mobile_clinical_full_receipt(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'clinical_full_commands_require_authority' USING ERRCODE='42501'; END IF;
END $$;

CREATE TABLE private.mobile_clinical_full_commands (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 preview_id uuid NOT NULL,
 command_version integer NOT NULL CHECK(command_version=1),
 command jsonb NOT NULL CHECK(jsonb_typeof(command)='object' AND octet_length(command::text)<=81920),
 prepared_package jsonb NOT NULL CHECK(jsonb_typeof(prepared_package)='object' AND octet_length(prepared_package::text)<=147456),
 normalization_context jsonb NOT NULL CHECK(jsonb_typeof(normalization_context)='object'
  AND normalization_context ?& ARRAY['sex','heightCm']
  AND normalization_context-ARRAY['sex','heightCm']='{}'::jsonb
  AND jsonb_typeof(normalization_context->'sex') IN('string','null')
  AND (normalization_context->'sex'='null'::jsonb OR normalization_context->>'sex' IN('masculino','feminino'))
  AND jsonb_typeof(normalization_context->'heightCm') IN('number','null')
  AND (normalization_context->'heightCm'='null'::jsonb OR (normalization_context->>'heightCm')::numeric>0)),
 command_hash text NOT NULL CHECK(command_hash ~ '^[0-9a-f]{64}$'),
 PRIMARY KEY(user_id,preview_id),
 FOREIGN KEY(user_id,preview_id) REFERENCES private.mobile_clinical_previews(user_id,preview_id) ON DELETE CASCADE
);
ALTER TABLE private.mobile_clinical_full_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_full_commands FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_full_command_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_full_commands FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.mobile_clinical_full_command_valid(p_kind text,p_command jsonb,p_form jsonb,p_intent jsonb,p_proposal jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE choice jsonb;kind text;principal text;
BEGIN
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object'
  OR NOT(p_command ?& ARRAY['form','choice','measureConfirmed','bodyFat'])
  OR p_command-ARRAY['form','choice','measureConfirmed','bodyFat']<>'{}'::jsonb
  OR octet_length(p_command::text)>81920
  OR jsonb_typeof(p_form) IS DISTINCT FROM 'object'
  OR p_command->'form' IS DISTINCT FROM p_form
  OR p_form->'version' IS DISTINCT FROM '1'::jsonb
  OR p_form->>'kind' IS DISTINCT FROM p_kind
  OR NOT(p_form ?& ARRAY['version','phase','kind','activityPurpose','answers','preference'])
  OR p_form-ARRAY['version','phase','kind','activityPurpose','answers','preference','noPlanOrigin']<>'{}'::jsonb
  OR jsonb_typeof(p_form->'answers') IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_command->'measureConfirmed') IS DISTINCT FROM 'boolean'
  OR p_command->'bodyFat' IS DISTINCT FROM coalesce(p_intent->'bodyFat','null'::jsonb)
  OR jsonb_typeof(p_command->'bodyFat') NOT IN('object','null') THEN RETURN false; END IF;
 choice:=p_command->'choice';kind:=choice->>'kind';principal:=p_proposal->>'principal';
 IF jsonb_typeof(choice) IS DISTINCT FROM 'object' OR jsonb_typeof(choice->'kind') IS DISTINCT FROM 'string'
  OR principal IS NULL THEN RETURN false; END IF;
 IF kind='phase' THEN
  RETURN coalesce(choice-ARRAY['kind','phase']='{}'::jsonb AND jsonb_typeof(choice->'phase')='string'
   AND CASE choice->>'phase'
    WHEN 'manutencao' THEN principal IN('recomposition_transition','gain_exit')
    WHEN 'ganho_massa' THEN principal='phase_gain'
    WHEN 'recomposicao' THEN principal='phase_recomposition' ELSE false END,false);
 ELSIF kind='schedule' THEN
  RETURN coalesce(choice-ARRAY['kind','action']='{}'::jsonb AND jsonb_typeof(choice->'action')='string'
   AND CASE choice->>'action' WHEN 'pause' THEN principal='schedule_pause'
    WHEN 'reconfirm' THEN principal='schedule_reconfirm' ELSE false END,false);
 END IF;
 IF choice-ARRAY['kind']<>'{}'::jsonb THEN RETURN false; END IF;
 RETURN CASE kind WHEN 'keep' THEN principal IN('keep','schedule_pause')
  WHEN 'activity' THEN principal='activity'
  WHEN 'phase_calorie_step' THEN principal IN('deficit_step','maintenance_step','gain_step')
  WHEN 'neutral_exit' THEN principal='neutral_exit' ELSE false END;
END $$;

CREATE FUNCTION private.mobile_clinical_full_command_hash(p private.mobile_clinical_previews,p_command jsonb,p_normalization jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT encode(extensions.digest(jsonb_build_object('version',1,'user_id',(p).user_id,
  'preview_id',(p).preview_id,'kind',(p).review_kind,'cycle_id',(p).cycle_id,
  'signup_generation',(p).signup_generation,'signup_epoch',(p).signup_epoch,
  'context_hash',(p).context_hash,'form_hash',(p).form_hash,'intent_hash',(p).intent_hash,'proposal_hash',(p).proposal_hash,
  'command',p_command,'normalization_context',p_normalization)::text,'sha256'),'hex')
$$;
CREATE FUNCTION private.mobile_clinical_full_command_wire(p private.mobile_clinical_previews,c private.mobile_clinical_full_commands)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF (p).user_id IS DISTINCT FROM (c).user_id OR (p).preview_id IS DISTINCT FROM (c).preview_id
  OR (c).command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,(c).command,(c).normalization_context)
  OR NOT private.mobile_clinical_full_command_valid((p).review_kind,(c).command,
    (c).prepared_package->'form',(c).prepared_package->'intent',(c).prepared_package->'proposal')
  OR (p).form_hash IS DISTINCT FROM encode(extensions.digest(((c).prepared_package->'form')::text,'sha256'),'hex')
  OR (p).intent_hash IS DISTINCT FROM encode(extensions.digest(((c).prepared_package->'intent')::text,'sha256'),'hex')
  OR (p).proposal_hash IS DISTINCT FROM encode(extensions.digest(((c).prepared_package->'proposal')::text,'sha256'),'hex') THEN
  RAISE EXCEPTION 'clinical_full_command_corrupt' USING ERRCODE='XX001'; END IF;
 RETURN jsonb_build_object('user_id',(p).user_id,'operation_key',(p).operation_key,
  'preview',private.mobile_clinical_preview_wire(p),'command_version',(c).command_version,
  'command',(c).command,'command_hash',(c).command_hash,'normalization_context',(c).normalization_context,
  'package',(c).prepared_package);
END $$;

CREATE FUNCTION public.get_mobile_clinical_full_command(p_user_id uuid,p_preview_id uuid,p_prepare_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR (p_preview_id IS NULL)=(p_prepare_operation_key IS NULL) THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_lookup' USING ERRCODE='22023'; END IF;
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id
  AND ((p_preview_id IS NOT NULL AND x.preview_id=p_preview_id)
    OR (p_prepare_operation_key IS NOT NULL AND x.operation_key=p_prepare_operation_key));
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'clinical_full_command_unavailable' USING ERRCODE='40001'; END IF;
 RETURN private.mobile_clinical_full_command_wire(p,c);
END $$;

CREATE FUNCTION public.prepare_mobile_clinical_full_command(p_user_id uuid,p_kind text,p_cycle_id uuid,
 p_operation_key uuid,p_context_hash text,p_command jsonb,p_form jsonb,p_intent jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
 profile public.user_profiles%ROWTYPE;wire jsonb;normalization jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL OR p_kind IS NULL
  OR p_kind NOT IN('REGULAR','EARLY_FULL','ROUTINE_REVIEW','SAFETY') THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_scope' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.operation_key=p_operation_key;
 IF FOUND THEN
  SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
  IF NOT FOUND OR p.review_kind IS DISTINCT FROM p_kind OR p.cycle_id IS DISTINCT FROM p_cycle_id
   OR c.command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,p_command,c.normalization_context) THEN
   RAISE EXCEPTION 'clinical_full_command_conflict' USING ERRCODE='40001'; END IF;
  -- Identity is the normalized client command, not a recalculated effect. Never
  -- extend expiry or consult a changed profile on this acknowledgement branch.
  RETURN private.mobile_clinical_full_command_wire(p,c);
 END IF;
 IF NOT private.mobile_clinical_full_command_valid(p_kind,p_command,p_form,p_intent,p_proposal) THEN
  RAISE EXCEPTION 'invalid_clinical_full_command' USING ERRCODE='22023'; END IF;
 wire:=private.prepare_mobile_clinical_preview_at(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_form,p_intent,p_proposal,NULL);
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=(wire->>'preview_id')::uuid;
 -- The delegated capture holds this profile and the full calculation context.
 -- Retain only the two original n21 normalization inputs, never a refused value.
 SELECT x.* INTO STRICT profile FROM public.user_profiles x WHERE x.user_id=p_user_id;
 IF NOT coalesce(private.mobile_clinical_preference_valid(p_form->'preference',profile.sex::text,profile.height_cm),false) THEN
  RAISE EXCEPTION 'invalid_clinical_full_normalized_preference' USING ERRCODE='22023'; END IF;
 normalization:=jsonb_build_object('sex',profile.sex,'heightCm',profile.height_cm);
 INSERT INTO private.mobile_clinical_full_commands(user_id,preview_id,command_version,command,prepared_package,normalization_context,command_hash)
 VALUES(p_user_id,p.preview_id,1,p_command,jsonb_build_object('form',p_form,'intent',p_intent,'proposal',p_proposal),normalization,
  private.mobile_clinical_full_command_hash(p,p_command,normalization)) RETURNING * INTO c;
 RETURN private.mobile_clinical_full_command_wire(p,c);
END $$;

CREATE FUNCTION public.get_mobile_clinical_full_command_receipt(p_user_id uuid,p_preview_id uuid,p_operation_key uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE receipt jsonb;p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 receipt:=public.get_mobile_clinical_full_receipt(p_user_id,p_preview_id,p_operation_key);
 IF receipt IS NULL THEN RETURN NULL; END IF;
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'clinical_full_command_unavailable' USING ERRCODE='40001'; END IF;
 IF c.prepared_package IS DISTINCT FROM jsonb_build_object('form',receipt->'form','intent',receipt->'intent','proposal',receipt->'proposal') THEN
  RAISE EXCEPTION 'clinical_full_command_corrupt' USING ERRCODE='XX001'; END IF;
 RETURN receipt||jsonb_build_object('prepared',private.mobile_clinical_full_command_wire(p,c));
END $$;

CREATE FUNCTION public.confirm_mobile_clinical_full_command(p_user_id uuid,p_preview_id uuid,p_operation_key uuid,
 p_command jsonb,p_form jsonb,p_intent jsonb,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;packet jsonb;result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_preview_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_confirmation' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'clinical_full_command_not_found' USING ERRCODE='P0002'; END IF;
 SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p_preview_id;
 IF NOT FOUND OR c.command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,p_command,c.normalization_context)
  OR c.prepared_package IS DISTINCT FROM jsonb_build_object('form',p_form,'intent',p_intent,'proposal',p_proposal) THEN
  RAISE EXCEPTION 'clinical_full_command_conflict' USING ERRCODE='40001'; END IF;
 packet:=private.mobile_clinical_full_command_wire(p,c);
 -- The original atomic writer resolves original/alias receipt before capturing
 -- current facts. This wrapper adds command identity without changing that order.
 result:=private.confirm_mobile_clinical_preview_at(p_user_id,p_preview_id,p_operation_key,p_form,p_intent,p_proposal,NULL);
 RETURN jsonb_build_object('user_id',p_user_id,'preview_id',p_preview_id,'operation_key',p_operation_key,'result',result);
END $$;

REVOKE ALL ON FUNCTION private.mobile_clinical_full_command_valid(text,jsonb,jsonb,jsonb,jsonb),
 private.mobile_clinical_full_command_hash(private.mobile_clinical_previews,jsonb,jsonb),
 private.mobile_clinical_full_command_wire(private.mobile_clinical_previews,private.mobile_clinical_full_commands),
 public.get_mobile_clinical_full_command(uuid,uuid,uuid),
 public.prepare_mobile_clinical_full_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb),
 public.get_mobile_clinical_full_command_receipt(uuid,uuid,uuid),
 public.confirm_mobile_clinical_full_command(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_full_command(uuid,uuid,uuid),
 public.prepare_mobile_clinical_full_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb),
 public.get_mobile_clinical_full_command_receipt(uuid,uuid,uuid),
 public.confirm_mobile_clinical_full_command(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) TO service_role;
COMMIT;

-- Additive original after-target display evidence. No client route or activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_full_commands') IS NULL THEN
  RAISE EXCEPTION 'clinical_full_presentation_requires_commands' USING ERRCODE='42501'; END IF;
END $$;

CREATE FUNCTION private.mobile_clinical_full_presentation_valid(v jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT coalesce(jsonb_typeof(v)='object' AND v ?& ARRAY['version','hide','professionalAssessmentRecommended','pauseWeightLossGuidance']
  AND v-ARRAY['version','hide','professionalAssessmentRecommended','pauseWeightLossGuidance']='{}'::jsonb
  AND v->'version'='1'::jsonb AND jsonb_typeof(v->'hide')='object'
  AND (v->'hide') ?& ARRAY['objective','calories','protein']
  AND (v->'hide')-ARRAY['objective','calories','protein']='{}'::jsonb
  AND jsonb_typeof(v#>'{hide,objective}')='boolean' AND jsonb_typeof(v#>'{hide,calories}')='boolean'
  AND jsonb_typeof(v#>'{hide,protein}')='boolean'
  AND jsonb_typeof(v->'professionalAssessmentRecommended')='boolean'
  AND jsonb_typeof(v->'pauseWeightLossGuidance')='boolean',false)
$$;
CREATE TABLE private.mobile_clinical_full_presentations (
 user_id uuid NOT NULL,
 preview_id uuid NOT NULL,
 presentation jsonb NOT NULL CHECK(private.mobile_clinical_full_presentation_valid(presentation)),
 binding_hash text NOT NULL CHECK(binding_hash ~ '^[0-9a-f]{64}$'),
 PRIMARY KEY(user_id,preview_id),
 FOREIGN KEY(user_id,preview_id) REFERENCES private.mobile_clinical_full_commands(user_id,preview_id) ON DELETE CASCADE
);
ALTER TABLE private.mobile_clinical_full_presentations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_full_presentations FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_full_presentation_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_full_presentations FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.mobile_clinical_full_presentation_hash(p private.mobile_clinical_previews,c private.mobile_clinical_full_commands,v jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT encode(extensions.digest(jsonb_build_object('version',1,'user_id',(p).user_id,'preview_id',(p).preview_id,
  'context_hash',(p).context_hash,'proposal_hash',(p).proposal_hash,'command_hash',(c).command_hash,'presentation',v)::text,'sha256'),'hex')
$$;

CREATE OR REPLACE FUNCTION private.mobile_clinical_full_command_wire(p private.mobile_clinical_previews,c private.mobile_clinical_full_commands)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE display private.mobile_clinical_full_presentations%ROWTYPE;wire jsonb;
BEGIN
 IF (p).user_id IS DISTINCT FROM (c).user_id OR (p).preview_id IS DISTINCT FROM (c).preview_id
  OR (c).command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,(c).command,(c).normalization_context)
  OR NOT private.mobile_clinical_full_command_valid((p).review_kind,(c).command,
    (c).prepared_package->'form',(c).prepared_package->'intent',(c).prepared_package->'proposal')
  OR (p).form_hash IS DISTINCT FROM encode(extensions.digest(((c).prepared_package->'form')::text,'sha256'),'hex')
  OR (p).intent_hash IS DISTINCT FROM encode(extensions.digest(((c).prepared_package->'intent')::text,'sha256'),'hex')
  OR (p).proposal_hash IS DISTINCT FROM encode(extensions.digest(((c).prepared_package->'proposal')::text,'sha256'),'hex') THEN
  RAISE EXCEPTION 'clinical_full_command_corrupt' USING ERRCODE='XX001'; END IF;
 wire:=jsonb_build_object('user_id',(p).user_id,'operation_key',(p).operation_key,
  'preview',private.mobile_clinical_preview_wire(p),'command_version',(c).command_version,
  'command',(c).command,'command_hash',(c).command_hash,'normalization_context',(c).normalization_context,
  'package',(c).prepared_package);
 SELECT x.* INTO display FROM private.mobile_clinical_full_presentations x
  WHERE x.user_id=(p).user_id AND x.preview_id=(p).preview_id;
 IF FOUND THEN
  IF NOT private.mobile_clinical_full_presentation_valid(display.presentation)
   OR display.binding_hash IS DISTINCT FROM private.mobile_clinical_full_presentation_hash(p,c,display.presentation) THEN
   RAISE EXCEPTION 'clinical_full_presentation_corrupt' USING ERRCODE='XX001'; END IF;
  wire:=wire||jsonb_build_object('presentation',display.presentation);
 END IF;
 RETURN wire;
END $$;

CREATE FUNCTION public.prepare_mobile_clinical_full_presented_command(p_user_id uuid,p_kind text,p_cycle_id uuid,
 p_operation_key uuid,p_context_hash text,p_command jsonb,p_form jsonb,p_intent jsonb,p_proposal jsonb,p_presentation jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE existed boolean;wire jsonb;p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL THEN
  RAISE EXCEPTION 'invalid_clinical_full_presentation_scope' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 existed:=EXISTS(SELECT 1 FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.operation_key=p_operation_key);
 -- The old authority still validates the original normalized command before
 -- any current capture. Never add a guessed/backfilled policy to an old ACK.
 wire:=public.prepare_mobile_clinical_full_command(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_command,p_form,p_intent,p_proposal);
 IF existed THEN RETURN wire; END IF;
 IF NOT private.mobile_clinical_full_presentation_valid(p_presentation) THEN
  RAISE EXCEPTION 'invalid_clinical_full_presentation' USING ERRCODE='22023'; END IF;
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x
  WHERE x.user_id=p_user_id AND x.preview_id=(wire#>>'{preview,preview_id}')::uuid;
 SELECT x.* INTO STRICT c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
 INSERT INTO private.mobile_clinical_full_presentations(user_id,preview_id,presentation,binding_hash)
 VALUES(p_user_id,p.preview_id,p_presentation,private.mobile_clinical_full_presentation_hash(p,c,p_presentation));
 RETURN private.mobile_clinical_full_command_wire(p,c);
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_full_presentation_valid(jsonb),
 private.mobile_clinical_full_presentation_hash(private.mobile_clinical_previews,private.mobile_clinical_full_commands,jsonb),
 public.prepare_mobile_clinical_full_presented_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_mobile_clinical_full_presented_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,jsonb) TO service_role;
COMMIT;

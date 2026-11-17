-- Refuse a new private source on immutable old admission callers. Preserve the
-- complete original legacy implementation and historical intake provenance.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
DO $guard$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_media_identity_v2') IS NULL
  OR to_regprocedure('public.admit_conversation_versioned_media_intake_v2(uuid,uuid,jsonb)') IS NULL
  OR to_regprocedure('private.admit_conversation_intake_legacy_v2(uuid,uuid,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'private_admission_guard_substrate_required' USING ERRCODE='42501';END IF;
 IF(SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.admit_conversation_intake(uuid,uuid,jsonb)'::regprocedure)
  IS DISTINCT FROM '1317813e9f7f7fa86b272820cb5c0bd4fdd889543018dfefb9bdada7df30af34'
  OR(SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb)'::regprocedure)
  IS DISTINCT FROM '769eefe408e46d78296c49eb88ba756eb00803c50afec6173b5de56826fb0459' THEN
  RAISE EXCEPTION 'private_admission_guard_source_changed' USING ERRCODE='40001';END IF;
END $guard$;
-- Copy the exact original body into a closed internal implementation. Keep
-- the original public function OID, signature and grants for old prepared RPCs.
-- No row, receipt, constraint or domain writer is rewritten.
DO $copy$
DECLARE body text;old text:='FUNCTION public.admit_conversation_intake(';new text:='FUNCTION private.admit_conversation_intake_legacy_v2(';
BEGIN
 body:=pg_get_functiondef('public.admit_conversation_intake(uuid,uuid,jsonb)'::regprocedure);
 IF(length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'private_admission_copy_changed';END IF;
 EXECUTE replace(body,old,new);
END $copy$;
REVOKE ALL ON FUNCTION private.admit_conversation_intake_legacy_v2(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_conversation_intake(p_user_id uuid,p_expected_epoch uuid,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE actual uuid;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_intake_input(p_input);
 PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO actual FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF actual IS NULL OR actual IS DISTINCT FROM p_expected_epoch THEN
  RETURN private.admit_conversation_intake_legacy_v2(p_user_id,p_expected_epoch,p_input);END IF;
 -- Existing admissions remain replayable with their frozen version, including
 -- genuine later asset-ID reuse. Only a NEW intake referencing v2 is refused.
 IF p_input#>>'{source,channel}'='media'
  AND EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=(p_input#>>'{source,media_asset_id}')::uuid AND catalog_version=2)
  AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=(p_input->>'intake_id')::uuid) THEN
  RETURN '{"action":"input_conflict"}';END IF;
 RETURN private.admit_conversation_intake_legacy_v2(p_user_id,p_expected_epoch,p_input);
END $$;
REVOKE ALL ON FUNCTION public.admit_conversation_intake(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_conversation_intake(uuid,uuid,jsonb) TO service_role;

DO $patch$
DECLARE body text;old text:='public.admit_conversation_intake(p_user_id,p_expected_epoch,p_input)';new text:='private.admit_conversation_intake_legacy_v2(p_user_id,p_expected_epoch,p_input)';
BEGIN
 body:=pg_get_functiondef('public.admit_conversation_private_media_intake_v2(uuid,uuid,jsonb)'::regprocedure);
 IF(length(body)-length(replace(body,old,'')))/length(old)<>2 THEN
  RAISE EXCEPTION 'private_admission_guard_hook_changed' USING ERRCODE='40001';END IF;
 -- This existing wrapper already validates private ownership/lifetime and
 -- installs the immutable binding in the same owner-lane transaction.
 EXECUTE replace(body,old,new);
 IF(SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='private.admit_conversation_intake_legacy_v2(uuid,uuid,jsonb)'::regprocedure)
  IS DISTINCT FROM '1317813e9f7f7fa86b272820cb5c0bd4fdd889543018dfefb9bdada7df30af34' THEN
  RAISE EXCEPTION 'private_admission_guard_legacy_changed' USING ERRCODE='40001';END IF;
END $patch$;
COMMIT;

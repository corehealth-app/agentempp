-- Authenticated recovery never executes the original intent. A durable fence
-- prevents a delayed original writer, including its profile/peer side effects.
BEGIN;
CREATE TABLE private.journey_social_operation_fences (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_id uuid NOT NULL,
 auth_user_id uuid NOT NULL,
 input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(user_id,operation_id)
);
ALTER TABLE private.journey_social_operation_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.journey_social_operation_fences FROM PUBLIC,anon,authenticated,service_role;

-- The existing writers hold this same account row through receipt insertion.
-- Raising here rolls back the entire original transaction, not just its receipt.
CREATE FUNCTION private.reject_fenced_journey_social_operation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM 1 FROM public.users WHERE id=NEW.user_id FOR NO KEY UPDATE;
 IF EXISTS(SELECT 1 FROM private.journey_social_operation_fences WHERE user_id=NEW.user_id AND operation_id=NEW.operation_id) THEN
  RAISE EXCEPTION 'Journey operation was cancelled before application' USING ERRCODE='PT409';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.reject_fenced_journey_social_operation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER journey_social_operation_fence BEFORE INSERT ON private.journey_social_operations
 FOR EACH ROW EXECUTE FUNCTION private.reject_fenced_journey_social_operation();

-- Reconstruct the existing writer's exact typed hash; never call that writer.
CREATE FUNCTION private.journey_social_resolution_hash(p_kind text,p_command jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE keys text[]; rev bigint; member uuid; payload jsonb; enabled boolean;nick text;consent text;
BEGIN
 IF p_kind IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' OR octet_length(p_command::text)>8192 THEN
  RAISE EXCEPTION 'Closed resolution command required' USING ERRCODE='22023';END IF;
 keys:=CASE p_kind
  WHEN 'profile' THEN ARRAY['operation_id','expected_revision','opted_in','nickname','consent_version']
  WHEN 'block' THEN ARRAY['operation_id','expected_revision','member_id','blocked']
  WHEN 'report' THEN ARRAY['operation_id','expected_revision','member_id','reason'] ELSE NULL END;
 IF keys IS NULL OR NOT(p_command?&keys) OR p_command-keys<>'{}'::jsonb
  OR jsonb_typeof(p_command->'operation_id') IS DISTINCT FROM 'string' THEN
  RAISE EXCEPTION 'Closed resolution command required' USING ERRCODE='22023';END IF;
 PERFORM (p_command->>'operation_id')::uuid;
 rev:=private.journey_social_input_integer(p_command,'expected_revision',CASE WHEN p_kind='profile' THEN 0 ELSE 1 END,9007199254740990);
 IF p_kind='profile' THEN
  IF jsonb_typeof(p_command->'opted_in') IS DISTINCT FROM 'boolean'
   OR jsonb_typeof(p_command->'nickname') NOT IN('string','null') OR jsonb_typeof(p_command->'consent_version') NOT IN('string','null') THEN
   RAISE EXCEPTION 'Typed resolution consent required' USING ERRCODE='22023';END IF;
  enabled:=(p_command->>'opted_in')::boolean;nick:=p_command->>'nickname';consent:=p_command->>'consent_version';
  IF (enabled AND (nick IS NULL OR nick<>btrim(nick) OR char_length(nick) NOT BETWEEN 2 AND 32 OR nick ~ '[[:cntrl:]@]' OR consent IS DISTINCT FROM 'journey-social.v1'))
   OR (NOT enabled AND (nick IS NOT NULL OR consent IS NOT NULL)) THEN
   RAISE EXCEPTION 'Valid resolution consent required' USING ERRCODE='22023';END IF;
  payload:=jsonb_build_object('kind','profile','expected_revision',rev,'opted_in',enabled,'nickname',nick,'consent_version',consent);
 ELSE
  IF jsonb_typeof(p_command->'member_id') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Typed resolution peer required' USING ERRCODE='22023';END IF;
  member:=(p_command->>'member_id')::uuid;
  IF p_kind='block' THEN
   IF jsonb_typeof(p_command->'blocked') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Typed resolution block required' USING ERRCODE='22023';END IF;
   payload:=jsonb_build_object('kind','block','expected_revision',rev,'member_id',member,'reason',NULL,'blocked',(p_command->>'blocked')::boolean);
  ELSE
   IF jsonb_typeof(p_command->'reason') IS DISTINCT FROM 'string' OR p_command->>'reason' NOT IN('nickname','harassment','spam','other') THEN
    RAISE EXCEPTION 'Closed resolution reason required' USING ERRCODE='22023';END IF;
   payload:=jsonb_build_object('kind','report','expected_revision',rev,'member_id',member,'reason',p_command->>'reason','blocked',NULL);
  END IF;
 END IF;
 RETURN encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RAISE EXCEPTION 'Invalid typed resolution input' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION private.journey_social_resolution_hash(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.resolve_journey_social_operation_authenticated(
 p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_kind text,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE hash text;op uuid;prior private.journey_social_operations%ROWTYPE;
 fence private.journey_social_operation_fences%ROWTYPE;result jsonb;state text;receipt jsonb;
BEGIN
 -- Current authenticated login may differ from the lost original login, but
 -- domain/Auth ownership and current login liveness are always revalidated.
 PERFORM private.lock_journey_social_patient_session(p_user_id,p_auth_user_id,p_auth_session_id);
 hash:=private.journey_social_resolution_hash(p_kind,p_command);
 op:=(p_command->>'operation_id')::uuid;
 SELECT * INTO prior FROM private.journey_social_operations WHERE user_id=p_user_id AND operation_id=op;
 IF FOUND THEN
  IF prior.auth_user_id<>p_auth_user_id OR prior.input_hash<>hash THEN RAISE EXCEPTION 'Journey resolution content changed' USING ERRCODE='PT409';END IF;
  state:='applied';receipt:=prior.receipt;
 ELSE
  SELECT * INTO fence FROM private.journey_social_operation_fences WHERE user_id=p_user_id AND operation_id=op;
  IF FOUND THEN
   IF fence.auth_user_id<>p_auth_user_id OR fence.input_hash<>hash THEN RAISE EXCEPTION 'Journey resolution content changed' USING ERRCODE='PT409';END IF;
  ELSE
   INSERT INTO private.journey_social_operation_fences(user_id,operation_id,auth_user_id,input_hash) VALUES(p_user_id,op,p_auth_user_id,hash);
  END IF;
  state:='fenced';receipt:=NULL;
 END IF;
 result:=jsonb_build_object('status',state,'operation_id',op,'kind',p_kind,'expected_revision',(p_command->>'expected_revision')::bigint,
  'receipt',receipt,'profile',public.read_journey_social_profile(p_user_id,p_auth_user_id));
 PERFORM private.lock_journey_social_patient_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.resolve_journey_social_operation_authenticated(uuid,uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_journey_social_operation_authenticated(uuid,uuid,uuid,text,jsonb) TO service_role;
COMMIT;

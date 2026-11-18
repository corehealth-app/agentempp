-- Backend-only operational moderation. No patient route or social activation.
BEGIN;
CREATE TABLE private.journey_social_moderation_fences (
 actor_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(actor_id,operation_id)
);
ALTER TABLE private.journey_social_moderation_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.journey_social_moderation_fences FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.lock_journey_social_operator_session(p_actor uuid,p_login uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_actor IS NULL OR p_login IS NULL THEN RAISE EXCEPTION 'Original operator login required' USING ERRCODE='PT401';END IF;
 -- Same row/order as the existing writers. Do not upgrade shared role locks.
 BEGIN
  PERFORM 1 FROM public.admin_users a JOIN auth.users u ON u.id=a.id
   WHERE a.id=p_actor AND a.role IN('operations_admin','master_admin')
   AND u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
   FOR NO KEY UPDATE OF a NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Operator authorization is changing' USING ERRCODE='PT409';END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Operational moderation unavailable' USING ERRCODE='42501';END IF;
 BEGIN
  PERFORM 1 FROM auth.sessions WHERE id=p_login AND user_id=p_actor
   AND (not_after IS NULL OR not_after>clock_timestamp()) FOR SHARE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Operator session is changing' USING ERRCODE='PT409';END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original operator login unavailable' USING ERRCODE='PT401';END IF;
END $$;
REVOKE ALL ON FUNCTION private.lock_journey_social_operator_session(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.journey_social_moderation_hash(p_kind text,p_command jsonb)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE keys text[];rev bigint;target uuid;payload jsonb;
BEGIN
 IF p_kind IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' OR octet_length(p_command::text)>8192 THEN
  RAISE EXCEPTION 'Closed moderation command required' USING ERRCODE='22023';END IF;
 keys:=CASE p_kind WHEN 'profile' THEN ARRAY['operation_id','expected_revision','member_id','action']
  WHEN 'report' THEN ARRAY['operation_id','expected_revision','report_id','status'] ELSE NULL END;
 IF keys IS NULL OR NOT(p_command?&keys) OR p_command-keys<>'{}'::jsonb
  OR jsonb_typeof(p_command->'operation_id') IS DISTINCT FROM 'string' THEN
  RAISE EXCEPTION 'Closed moderation command required' USING ERRCODE='22023';END IF;
 PERFORM (p_command->>'operation_id')::uuid;
 rev:=private.journey_social_input_integer(p_command,'expected_revision',1,9007199254740990);
 IF p_kind='profile' THEN
  IF jsonb_typeof(p_command->'member_id') IS DISTINCT FROM 'string' OR jsonb_typeof(p_command->'action') IS DISTINCT FROM 'string'
   OR p_command->>'action' NOT IN('suspend','restore') THEN RAISE EXCEPTION 'Typed moderation required' USING ERRCODE='22023';END IF;
  target:=(p_command->>'member_id')::uuid;
  payload:=jsonb_build_object('kind','moderation','member_id',target,'expected_revision',rev,'action',p_command->>'action');
 ELSE
  IF jsonb_typeof(p_command->'report_id') IS DISTINCT FROM 'string' OR jsonb_typeof(p_command->'status') IS DISTINCT FROM 'string'
   OR p_command->>'status' NOT IN('dismissed','resolved') THEN RAISE EXCEPTION 'Typed report resolution required' USING ERRCODE='22023';END IF;
  target:=(p_command->>'report_id')::uuid;
  payload:=jsonb_build_object('kind','report_resolution','report_id',target,'expected_revision',rev,'status',p_command->>'status');
 END IF;
 RETURN encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RAISE EXCEPTION 'Invalid typed moderation input' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION private.journey_social_moderation_hash(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Also protect a delayed lower-level backend call: raising here rolls back its
-- profile/report effect as well as receipt insertion. No existing body changes.
CREATE FUNCTION private.reject_fenced_journey_social_moderation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM 1 FROM public.admin_users WHERE id=NEW.actor_id FOR NO KEY UPDATE;
 IF EXISTS(SELECT 1 FROM private.journey_social_moderation_fences WHERE actor_id=NEW.actor_id AND operation_id=NEW.operation_id) THEN
  RAISE EXCEPTION 'Moderation cancelled before application' USING ERRCODE='PT409';END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.reject_fenced_journey_social_moderation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER journey_social_moderation_fence BEFORE INSERT ON private.journey_social_moderation_operations
 FOR EACH ROW EXECUTE FUNCTION private.reject_fenced_journey_social_moderation();

CREATE FUNCTION public.journey_social_operator_authenticated(p_actor_id uuid,p_auth_session_id uuid,p_action text,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE keys text[];kind text;command jsonb;hash text;prior_hash text;receipt jsonb;op uuid;rev bigint;result jsonb;cursor_value jsonb;
BEGIN
 PERFORM private.lock_journey_social_operator_session(p_actor_id,p_auth_session_id);
 IF p_action IS NULL OR p_input IS NULL OR jsonb_typeof(p_input)<>'object' OR octet_length(p_input::text)>8192 THEN
  RAISE EXCEPTION 'Closed operator input required' USING ERRCODE='22023';END IF;
 keys:=CASE p_action WHEN 'queue.read' THEN ARRAY['limit','cursor']
  WHEN 'operation.resolve' THEN ARRAY['kind','command']
  WHEN 'profile.moderate' THEN ARRAY['operation_id','expected_revision','member_id','action']
  WHEN 'report.resolve' THEN ARRAY['operation_id','expected_revision','report_id','status'] ELSE NULL END;
 IF keys IS NULL OR NOT(p_input?&keys) OR p_input-keys<>'{}'::jsonb THEN RAISE EXCEPTION 'Closed operator operation required' USING ERRCODE='22023';END IF;
 IF p_action='queue.read' THEN
  rev:=private.journey_social_input_integer(p_input,'limit',1,100);
  cursor_value:=p_input->'cursor';
  IF cursor_value='null'::jsonb THEN
   result:=public.read_journey_social_reports(p_actor_id,rev::integer,NULL,NULL);
  ELSE
   IF jsonb_typeof(cursor_value) IS DISTINCT FROM 'object' OR NOT(cursor_value?&ARRAY['created_at','report_id'])
    OR cursor_value-ARRAY['created_at','report_id']<>'{}'::jsonb
    OR jsonb_typeof(cursor_value->'created_at') IS DISTINCT FROM 'string' OR jsonb_typeof(cursor_value->'report_id') IS DISTINCT FROM 'string'
    OR (cursor_value->>'created_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' THEN
    RAISE EXCEPTION 'Typed queue cursor required' USING ERRCODE='22023';END IF;
   result:=public.read_journey_social_reports(p_actor_id,rev::integer,(cursor_value->>'created_at')::timestamptz,(cursor_value->>'report_id')::uuid);
  END IF;
 ELSE
  kind:=CASE p_action WHEN 'profile.moderate' THEN 'profile' WHEN 'report.resolve' THEN 'report' ELSE p_input->>'kind' END;
  command:=CASE WHEN p_action='operation.resolve' THEN p_input->'command' ELSE p_input END;
  hash:=private.journey_social_moderation_hash(kind,command);
  op:=(command->>'operation_id')::uuid;rev:=(command->>'expected_revision')::bigint;
  IF p_action='operation.resolve' THEN
   SELECT o.input_hash,o.receipt INTO prior_hash,receipt FROM private.journey_social_moderation_operations o WHERE o.actor_id=p_actor_id AND o.operation_id=op;
   IF FOUND THEN
    IF prior_hash<>hash THEN RAISE EXCEPTION 'Moderation operation changed' USING ERRCODE='PT409';END IF;
    result:=jsonb_build_object('status','applied','kind',kind,'operation_id',op,'expected_revision',rev,'receipt',receipt);
   ELSE
    SELECT f.input_hash INTO prior_hash FROM private.journey_social_moderation_fences f WHERE f.actor_id=p_actor_id AND f.operation_id=op;
    IF FOUND AND prior_hash<>hash THEN RAISE EXCEPTION 'Moderation fence changed' USING ERRCODE='PT409';END IF;
    INSERT INTO private.journey_social_moderation_fences(actor_id,operation_id,input_hash) VALUES(p_actor_id,op,hash) ON CONFLICT DO NOTHING;
    result:=jsonb_build_object('status','fenced','kind',kind,'operation_id',op,'expected_revision',rev,'receipt',NULL);
   END IF;
  ELSE
   IF EXISTS(SELECT 1 FROM private.journey_social_moderation_fences WHERE actor_id=p_actor_id AND operation_id=op) THEN
    RAISE EXCEPTION 'Moderation operation was cancelled' USING ERRCODE='PT409';END IF;
   IF kind='profile' THEN result:=public.moderate_journey_social_profile(p_actor_id,op,(command->>'member_id')::uuid,rev,command->>'action');
   ELSE result:=public.resolve_journey_social_report(p_actor_id,op,(command->>'report_id')::uuid,rev,command->>'status');END IF;
  END IF;
 END IF;
 -- Natural expiry after an actual write aborts effects and the immutable receipt.
 PERFORM private.lock_journey_social_operator_session(p_actor_id,p_auth_session_id);
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_datetime_format OR datetime_field_overflow THEN
 RAISE EXCEPTION 'Invalid typed operator input' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION public.journey_social_operator_authenticated(uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.journey_social_operator_authenticated(uuid,uuid,text,jsonb) TO service_role;
COMMIT;

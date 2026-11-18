-- Patient-only transport. Does not expose operational moderation commands.
BEGIN;
CREATE FUNCTION private.lock_journey_social_patient_session(p_user uuid,p_auth uuid,p_login uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user IS NULL OR p_auth IS NULL OR p_login IS NULL THEN RAISE EXCEPTION 'Original social login required' USING ERRCODE='PT401'; END IF;
 -- Compatible with reciprocal block FKs. Session deletion cannot pass while
 -- a command is in progress; no lease, token refresh, epoch or profile write.
 PERFORM 1 FROM public.users u JOIN auth.users a ON a.id=u.auth_user_id
 WHERE u.id=p_user AND u.auth_user_id=p_auth AND u.status='active' AND a.email_confirmed_at IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM public.admin_users WHERE id=p_auth) FOR NO KEY UPDATE OF u;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original social identity unavailable' USING ERRCODE='PT401'; END IF;
 BEGIN
  PERFORM 1 FROM auth.sessions WHERE id=p_login AND user_id=p_auth AND (not_after IS NULL OR not_after>clock_timestamp()) FOR SHARE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Original social login changed' USING ERRCODE='PT409'; END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original social login unavailable' USING ERRCODE='PT401'; END IF;
END $$;
REVOKE ALL ON FUNCTION private.lock_journey_social_patient_session(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.journey_social_input_integer(p_input jsonb,p_key text,p_min bigint,p_max bigint)
RETURNS bigint LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE n numeric;
BEGIN
 IF jsonb_typeof(p_input->p_key) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Social integer required' USING ERRCODE='22023'; END IF;
 n:=(p_input->>p_key)::numeric;
 IF n<>trunc(n) OR n<p_min OR n>p_max THEN RAISE EXCEPTION 'Social integer out of bounds' USING ERRCODE='22023'; END IF;
 RETURN n::bigint;
END $$;
REVOKE ALL ON FUNCTION private.journey_social_input_integer(jsonb,text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.journey_social_patient_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_action text,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE keys text[];result jsonb;op uuid;rev bigint;member uuid;lim integer;cursor_value jsonb;
BEGIN
 PERFORM private.lock_journey_social_patient_session(p_user_id,p_auth_user_id,p_auth_session_id);
 IF p_action IS NULL OR p_input IS NULL OR jsonb_typeof(p_input)<>'object' OR octet_length(p_input::text)>8192 THEN
  RAISE EXCEPTION 'Closed social input required' USING ERRCODE='22023';
 END IF;
 keys:=CASE p_action
  WHEN 'profile.read' THEN ARRAY[]::text[]
  WHEN 'profile.update' THEN ARRAY['operation_id','expected_revision','opted_in','nickname','consent_version']
  WHEN 'block.update' THEN ARRAY['operation_id','expected_revision','member_id','blocked']
  WHEN 'report.create' THEN ARRAY['operation_id','expected_revision','member_id','reason']
  WHEN 'ranking.read' THEN ARRAY['limit','cursor']
  WHEN 'blocks.read' THEN ARRAY['limit','after_member_id','expected_revision'] ELSE NULL END;
 IF keys IS NULL OR NOT(p_input?&keys) OR p_input-keys<>'{}'::jsonb THEN
  RAISE EXCEPTION 'Closed social operation required' USING ERRCODE='22023';
 END IF;
 IF p_action IN('profile.update','block.update','report.create') THEN
  IF jsonb_typeof(p_input->'operation_id') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Social operation UUID required' USING ERRCODE='22023'; END IF;
  op:=(p_input->>'operation_id')::uuid;
  rev:=private.journey_social_input_integer(p_input,'expected_revision',0,9007199254740990);
 END IF;
 IF p_action IN('block.update','report.create') THEN
  IF jsonb_typeof(p_input->'member_id') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Public social member UUID required' USING ERRCODE='22023'; END IF;
  member:=(p_input->>'member_id')::uuid;
 END IF;
 IF p_action IN('ranking.read','blocks.read') THEN lim:=private.journey_social_input_integer(p_input,'limit',1,100)::integer; END IF;
 CASE p_action
 WHEN 'profile.read' THEN result:=public.read_journey_social_profile(p_user_id,p_auth_user_id);
 WHEN 'profile.update' THEN
  IF jsonb_typeof(p_input->'opted_in') IS DISTINCT FROM 'boolean'
   OR jsonb_typeof(p_input->'nickname') NOT IN('string','null') OR jsonb_typeof(p_input->'consent_version') NOT IN('string','null') THEN
   RAISE EXCEPTION 'Typed social consent required' USING ERRCODE='22023';
  END IF;
  result:=public.mutate_journey_social_profile(p_user_id,p_auth_user_id,op,rev,(p_input->>'opted_in')::boolean,p_input->>'nickname',p_input->>'consent_version');
 WHEN 'block.update' THEN
  IF jsonb_typeof(p_input->'blocked') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Social block boolean required' USING ERRCODE='22023'; END IF;
  result:=public.mutate_journey_social_block(p_user_id,p_auth_user_id,op,rev,member,(p_input->>'blocked')::boolean);
 WHEN 'report.create' THEN
  IF jsonb_typeof(p_input->'reason') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Social report reason required' USING ERRCODE='22023'; END IF;
  result:=public.submit_journey_social_report(p_user_id,p_auth_user_id,op,rev,member,p_input->>'reason');
 WHEN 'ranking.read' THEN
  IF jsonb_typeof(p_input->'cursor') NOT IN('object','null') THEN RAISE EXCEPTION 'Social ranking cursor required' USING ERRCODE='22023'; END IF;
  cursor_value:=CASE WHEN p_input->'cursor'='null'::jsonb THEN NULL ELSE p_input->'cursor' END;
  result:=public.read_journey_weekly_ranking_page(p_user_id,p_auth_user_id,lim,cursor_value);
 WHEN 'blocks.read' THEN
  IF jsonb_typeof(p_input->'after_member_id') NOT IN('string','null') OR jsonb_typeof(p_input->'expected_revision') NOT IN('number','null') THEN
   RAISE EXCEPTION 'Typed social blocks cursor required' USING ERRCODE='22023';
  END IF;
  result:=public.read_journey_social_blocks(p_user_id,p_auth_user_id,lim,(p_input->>'after_member_id')::uuid,
   CASE WHEN p_input->'expected_revision'='null'::jsonb THEN NULL ELSE private.journey_social_input_integer(p_input,'expected_revision',0,9007199254740990) END);
 END CASE;
 -- Natural expiry during a writer aborts the profile, peer effect and receipt.
 PERFORM private.lock_journey_social_patient_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RAISE EXCEPTION 'Invalid typed social input' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION public.journey_social_patient_authenticated(uuid,uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.journey_social_patient_authenticated(uuid,uuid,uuid,text,jsonb) TO service_role;
COMMIT;

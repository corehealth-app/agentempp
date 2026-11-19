-- A resolved report leaves the pending queue. Operators still need a current
-- public profile to restore moderation, without searching patient health data.
BEGIN;
CREATE FUNCTION public.journey_social_operator_profile_authenticated(p_actor_id uuid,p_auth_session_id uuid,p_member_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE owner_id uuid;auth_id uuid;result jsonb;
BEGIN
 PERFORM private.lock_journey_social_operator_session(p_actor_id,p_auth_session_id);
 IF p_member_id IS NULL THEN RAISE EXCEPTION 'Public member required' USING ERRCODE='22023';END IF;
 SELECT p.user_id,p.auth_user_id INTO owner_id,auth_id FROM private.journey_social_profiles p
  JOIN public.users u ON u.id=p.user_id AND u.auth_user_id=p.auth_user_id AND u.status='active'
  WHERE p.member_id=p_member_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey member unavailable' USING ERRCODE='PT404';END IF;
 result:=public.read_journey_social_profile(owner_id,auth_id);
 PERFORM private.lock_journey_social_operator_session(p_actor_id,p_auth_session_id);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.journey_social_operator_profile_authenticated(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.journey_social_operator_profile_authenticated(uuid,uuid,uuid) TO service_role;
COMMIT;

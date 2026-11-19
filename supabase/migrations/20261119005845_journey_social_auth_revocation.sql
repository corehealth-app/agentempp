-- Preserve current Auth revocation at the SQL boundary, including during a
-- live original session. Only additive social functions are replaced; no
-- clinical, registration, XP, Auth writer or legacy reader is altered.
BEGIN;
CREATE OR REPLACE FUNCTION private.journey_social_timezone(p_user_id uuid,p_auth_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_timezone text;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT coalesce(nullif(u.timezone,''),'America/Sao_Paulo') INTO v_timezone
 FROM public.users u JOIN auth.users a ON a.id=u.auth_user_id
 WHERE u.id=p_user_id AND u.auth_user_id=p_auth_user_id AND u.status='active'
 AND a.deleted_at IS NULL AND (a.banned_until IS NULL OR a.banned_until<=statement_timestamp());
 IF NOT FOUND OR p_user_id IS NULL OR p_auth_user_id IS NULL THEN
  RAISE EXCEPTION 'Journey original identity unavailable' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM private.journey_social_profiles p WHERE p.user_id=p_user_id AND p.auth_user_id<>p_auth_user_id) THEN
  RAISE EXCEPTION 'Journey original identity changed' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN
  RAISE EXCEPTION 'Official timezone unavailable' USING ERRCODE='22023';
 END IF;
 RETURN v_timezone;
END $$;
CREATE OR REPLACE FUNCTION private.lock_journey_social_patient_session(p_user uuid,p_auth uuid,p_login uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user IS NULL OR p_auth IS NULL OR p_login IS NULL THEN RAISE EXCEPTION 'Original social login required' USING ERRCODE='PT401'; END IF;
 -- Compatible with reciprocal block FKs. Session deletion cannot pass while
 -- a command is in progress; no lease, token refresh, epoch or profile write.
 BEGIN
  PERFORM 1 FROM public.users u JOIN auth.users a ON a.id=u.auth_user_id
 WHERE u.id=p_user AND u.auth_user_id=p_auth AND u.status='active' AND a.email_confirmed_at IS NOT NULL
 AND a.deleted_at IS NULL AND (a.banned_until IS NULL OR a.banned_until<=clock_timestamp())
 AND NOT EXISTS(SELECT 1 FROM public.admin_users WHERE id=p_auth) FOR NO KEY UPDATE OF u FOR SHARE OF a NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Original social identity is changing' USING ERRCODE='PT409';END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original social identity unavailable' USING ERRCODE='PT401'; END IF;
 BEGIN
  PERFORM 1 FROM auth.sessions WHERE id=p_login AND user_id=p_auth AND (not_after IS NULL OR not_after>clock_timestamp()) FOR SHARE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Original social login changed' USING ERRCODE='PT409'; END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original social login unavailable' USING ERRCODE='PT401'; END IF;
END $$;
CREATE OR REPLACE FUNCTION private.lock_journey_social_operator_session(p_actor uuid,p_login uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_actor IS NULL OR p_login IS NULL THEN RAISE EXCEPTION 'Original operator login required' USING ERRCODE='PT401';END IF;
 -- Same row/order as the existing writers. Do not upgrade shared role locks.
 BEGIN
  PERFORM 1 FROM public.admin_users a JOIN auth.users u ON u.id=a.id
   WHERE a.id=p_actor AND a.role IN('operations_admin','master_admin')
   AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
   FOR NO KEY UPDATE OF a NOWAIT FOR SHARE OF u NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Operator authorization is changing' USING ERRCODE='PT409';END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Operational moderation unavailable' USING ERRCODE='42501';END IF;
 BEGIN
  PERFORM 1 FROM auth.sessions WHERE id=p_login AND user_id=p_actor
   AND (not_after IS NULL OR not_after>clock_timestamp()) FOR SHARE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'Operator session is changing' USING ERRCODE='PT409';END;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original operator login unavailable' USING ERRCODE='PT401';END IF;
END $$;
CREATE OR REPLACE FUNCTION private.journey_weekly_ranking_rows(p_user_id uuid,p_auth_user_id uuid,p_at timestamptz)
RETURNS TABLE(member_id uuid,nickname text,weekly_xp bigint,rank_position bigint,is_you boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_timezone text; v_date date; v_start date;
BEGIN
 v_timezone:=private.journey_social_timezone(p_user_id,p_auth_user_id);
 IF p_at IS NULL OR NOT isfinite(p_at) THEN RAISE EXCEPTION 'Invalid ranking clock' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.journey_social_profiles p WHERE p.user_id=p_user_id AND p.auth_user_id=p_auth_user_id AND p.opted_in AND p.moderation='active') THEN
  RAISE EXCEPTION 'Journey participation required' USING ERRCODE='42501';
 END IF;
 v_date:=(p_at AT TIME ZONE v_timezone)::date;v_start:=date_trunc('week',v_date::timestamp)::date;
 RETURN QUERY WITH eligible AS (
  SELECT p.user_id,p.member_id,p.nickname FROM private.journey_social_profiles p
  JOIN public.users u ON u.id=p.user_id AND u.auth_user_id=p.auth_user_id AND u.status='active'
  JOIN auth.users a ON a.id=p.auth_user_id AND a.email_confirmed_at IS NOT NULL
   AND a.deleted_at IS NULL AND (a.banned_until IS NULL OR a.banned_until<=p_at)
  WHERE p.opted_in AND p.moderation='active' AND NOT EXISTS(SELECT 1 FROM private.journey_social_blocks b WHERE
   (b.blocker_id=p_user_id AND b.target_id=p.user_id) OR (b.target_id=p_user_id AND b.blocker_id=p.user_id))
 ), totals AS (
  SELECT e.user_id,e.member_id,e.nickname,coalesce(sum(s.xp_earned),0)::bigint AS weekly_xp FROM eligible e
  LEFT JOIN public.daily_snapshots s ON s.user_id=e.user_id AND s.day_closed AND s.date>=v_start AND s.date<=least(v_start+6,v_date)
  GROUP BY e.user_id,e.member_id,e.nickname
 ) SELECT t.member_id,t.nickname,t.weekly_xp,rank() OVER(ORDER BY t.weekly_xp DESC),t.user_id=p_user_id FROM totals t;
END $$;
COMMIT;

-- Additive backend-only foundation. No existing XP writer or legacy reader changes.
-- Native/API exposure waits for block/report/moderation and connected qualification.
BEGIN;
CREATE TABLE private.journey_social_profiles (
 user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 auth_user_id uuid NOT NULL,
 member_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 revision bigint NOT NULL CHECK (revision>0),
 opted_in boolean NOT NULL,
 nickname text,
 consent_version text,
 consented_at timestamptz,
 moderation text NOT NULL DEFAULT 'active' CHECK (moderation IN ('active','suspended')),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK (member_id<>user_id AND member_id<>auth_user_id),
 CHECK ((opted_in AND consent_version IS NOT NULL AND consent_version='journey-social.v1' AND consented_at IS NOT NULL
   AND nickname IS NOT NULL AND nickname=btrim(nickname) AND char_length(nickname) BETWEEN 2 AND 32
   AND nickname !~ '[[:cntrl:]@]')
  OR (NOT opted_in AND nickname IS NULL AND consent_version IS NULL AND consented_at IS NULL))
);
CREATE TABLE private.journey_social_operations (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_id uuid NOT NULL,
 auth_user_id uuid NOT NULL,
 input_hash text NOT NULL CHECK (input_hash ~ '^[0-9a-f]{64}$'),
 receipt jsonb NOT NULL CHECK (jsonb_typeof(receipt)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(user_id,operation_id)
);
CREATE TABLE private.journey_social_blocks (
 blocker_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 target_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(blocker_id,target_id),
 CHECK (blocker_id<>target_id)
);
CREATE INDEX journey_social_blocks_target_idx ON private.journey_social_blocks(target_id,blocker_id);
ALTER TABLE private.journey_social_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.journey_social_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.journey_social_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.journey_social_profiles,private.journey_social_operations,private.journey_social_blocks
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.journey_social_timezone(p_user_id uuid,p_auth_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_timezone text;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT coalesce(nullif(u.timezone,''),'America/Sao_Paulo') INTO v_timezone
 FROM public.users u JOIN auth.users a ON a.id=u.auth_user_id
 WHERE u.id=p_user_id AND u.auth_user_id=p_auth_user_id AND u.status='active';
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
REVOKE ALL ON FUNCTION private.journey_social_timezone(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_journey_social_profile(p_user_id uuid,p_auth_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_result jsonb;
BEGIN
 PERFORM private.journey_social_timezone(p_user_id,p_auth_user_id);
 SELECT jsonb_build_object('revision',p.revision,'opted_in',p.opted_in,'nickname',p.nickname,
  'member_id',p.member_id,'moderation',p.moderation) INTO v_result
 FROM private.journey_social_profiles p WHERE p.user_id=p_user_id;
 RETURN coalesce(v_result,jsonb_build_object('revision',0,'opted_in',false,'nickname',NULL,'member_id',NULL,'moderation','active'));
END $$;
REVOKE ALL ON FUNCTION public.read_journey_social_profile(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_journey_social_profile(uuid,uuid) TO service_role;

CREATE FUNCTION public.mutate_journey_social_profile(
 p_user_id uuid,p_auth_user_id uuid,p_operation_id uuid,p_expected_revision bigint,
 p_opted_in boolean,p_nickname text,p_consent_version text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_hash text; v_prior private.journey_social_operations%ROWTYPE;
 v_revision bigint; v_receipt jsonb;
BEGIN
 PERFORM private.journey_social_timezone(p_user_id,p_auth_user_id);
 IF p_operation_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0 OR p_opted_in IS NULL
  OR (p_opted_in AND (p_nickname IS NULL OR p_nickname<>btrim(p_nickname)
    OR char_length(p_nickname) NOT BETWEEN 2 AND 32 OR p_nickname ~ '[[:cntrl:]@]'
    OR p_consent_version IS DISTINCT FROM 'journey-social.v1'))
  OR (NOT p_opted_in AND (p_nickname IS NOT NULL OR p_consent_version IS NOT NULL)) THEN
  RAISE EXCEPTION 'Invalid Journey participation command' USING ERRCODE='22023';
 END IF;
 -- Same owner row serializes concurrent operations without locking other people.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND auth_user_id=p_auth_user_id AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey identity changed' USING ERRCODE='42501'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
  'kind','profile','expected_revision',p_expected_revision,'opted_in',p_opted_in,
  'nickname',p_nickname,'consent_version',p_consent_version)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_prior FROM private.journey_social_operations
 WHERE user_id=p_user_id AND operation_id=p_operation_id;
 IF FOUND THEN
  IF v_prior.auth_user_id<>p_auth_user_id OR v_prior.input_hash<>v_hash THEN
   RAISE EXCEPTION 'Journey operation content changed' USING ERRCODE='PT409';
  END IF;
  RETURN jsonb_build_object('status','replayed','receipt',v_prior.receipt,
   'profile',public.read_journey_social_profile(p_user_id,p_auth_user_id));
 END IF;
 SELECT revision INTO v_revision FROM private.journey_social_profiles WHERE user_id=p_user_id;
 v_revision:=coalesce(v_revision,0);
 IF v_revision<>p_expected_revision THEN
  RAISE EXCEPTION 'Journey participation revision changed' USING ERRCODE='PT409';
 END IF;
 v_revision:=v_revision+1;
 INSERT INTO private.journey_social_profiles(user_id,auth_user_id,revision,opted_in,nickname,consent_version,consented_at)
 VALUES(p_user_id,p_auth_user_id,v_revision,p_opted_in,p_nickname,p_consent_version,
  CASE WHEN p_opted_in THEN clock_timestamp() ELSE NULL END)
 ON CONFLICT(user_id) DO UPDATE SET revision=excluded.revision,opted_in=excluded.opted_in,
  nickname=excluded.nickname,consent_version=excluded.consent_version,consented_at=excluded.consented_at,
  updated_at=clock_timestamp();
 v_receipt:=jsonb_build_object('operation_id',p_operation_id,'revision',v_revision,'opted_in',p_opted_in);
 INSERT INTO private.journey_social_operations(user_id,operation_id,auth_user_id,input_hash,receipt)
 VALUES(p_user_id,p_operation_id,p_auth_user_id,v_hash,v_receipt);
 RETURN jsonb_build_object('status','applied','receipt',v_receipt,
  'profile',public.read_journey_social_profile(p_user_id,p_auth_user_id));
END $$;
REVOKE ALL ON FUNCTION public.mutate_journey_social_profile(uuid,uuid,uuid,bigint,boolean,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mutate_journey_social_profile(uuid,uuid,uuid,bigint,boolean,text,text) TO service_role;

-- Private clock parameter permits deterministic civil-week tests, not client-selected time.
CREATE FUNCTION private.project_journey_weekly_ranking(
 p_user_id uuid,p_auth_user_id uuid,p_at timestamptz,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_timezone text; v_date date; v_start date; v_result jsonb;
BEGIN
 v_timezone:=private.journey_social_timezone(p_user_id,p_auth_user_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_at IS NULL OR NOT isfinite(p_at) THEN
  RAISE EXCEPTION 'Invalid Journey ranking bounds' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.journey_social_profiles WHERE user_id=p_user_id
   AND auth_user_id=p_auth_user_id AND opted_in AND moderation='active') THEN
  RAISE EXCEPTION 'Journey participation required' USING ERRCODE='42501';
 END IF;
 v_date:=(p_at AT TIME ZONE v_timezone)::date;
 v_start:=date_trunc('week',v_date::timestamp)::date;
 WITH eligible AS (
  SELECT p.user_id,p.member_id,p.nickname
  FROM private.journey_social_profiles p
  JOIN public.users u ON u.id=p.user_id AND u.auth_user_id=p.auth_user_id AND u.status='active'
  JOIN auth.users a ON a.id=p.auth_user_id
  WHERE p.opted_in AND p.moderation='active'
   AND NOT EXISTS(SELECT 1 FROM private.journey_social_blocks b WHERE
    (b.blocker_id=p_user_id AND b.target_id=p.user_id) OR (b.target_id=p_user_id AND b.blocker_id=p.user_id))
 ), totals AS (
  SELECT e.user_id,e.member_id,e.nickname,coalesce(sum(s.xp_earned),0)::bigint AS weekly_xp
  FROM eligible e LEFT JOIN public.daily_snapshots s ON s.user_id=e.user_id
   AND s.day_closed AND s.date>=v_start AND s.date<=least(v_start+6,v_date)
  GROUP BY e.user_id,e.member_id,e.nickname
 ), ranked AS (
  SELECT *,rank() OVER(ORDER BY weekly_xp DESC) AS position FROM totals
 ), bounded AS (
  SELECT * FROM ranked ORDER BY weekly_xp DESC,member_id LIMIT p_limit+1
 ), page AS (
  SELECT * FROM bounded ORDER BY weekly_xp DESC,member_id LIMIT p_limit
 )
 SELECT jsonb_build_object('week_start',v_start,'week_end',v_start+6,'through_date',v_date,
  'basis','closed_daily_xp','has_more',(SELECT count(*)>p_limit FROM bounded),
  'entries',coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',member_id,'nickname',nickname,
   'rank',position,'weekly_xp',weekly_xp,'is_you',user_id=p_user_id)
   ORDER BY weekly_xp DESC,member_id) FROM page),'[]'::jsonb)) INTO v_result;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION private.project_journey_weekly_ranking(uuid,uuid,timestamptz,integer)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.read_journey_weekly_ranking(p_user_id uuid,p_auth_user_id uuid,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
 SELECT private.project_journey_weekly_ranking(p_user_id,p_auth_user_id,statement_timestamp(),p_limit);
$$;
REVOKE ALL ON FUNCTION public.read_journey_weekly_ranking(uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_journey_weekly_ranking(uuid,uuid,integer) TO service_role;
COMMIT;

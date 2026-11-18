-- Backend-only T6 controls. No HTTP/native activation or change to reward writers.
BEGIN;
CREATE TABLE private.journey_social_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 reporter_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 target_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 reason text NOT NULL CHECK(reason IN('nickname','harassment','spam','other')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','dismissed','resolved')),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(reporter_id<>target_id)
);
CREATE UNIQUE INDEX journey_social_reports_pending_unique ON private.journey_social_reports(reporter_id,target_id,reason) WHERE status='pending';
CREATE INDEX journey_social_reports_queue_idx ON private.journey_social_reports(created_at,id) WHERE status='pending';
CREATE TABLE private.journey_social_moderation_operations (
 actor_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 target_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 receipt jsonb NOT NULL CHECK(jsonb_typeof(receipt)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(actor_id,operation_id)
);
ALTER TABLE private.journey_social_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.journey_social_moderation_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.journey_social_reports,private.journey_social_moderation_operations FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.commit_journey_social_peer_command(
 p_user_id uuid,p_auth_user_id uuid,p_operation_id uuid,p_expected_revision bigint,
 p_member_id uuid,p_kind text,p_reason text,p_blocked boolean)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_hash text; v_prior private.journey_social_operations%ROWTYPE;
 v_profile private.journey_social_profiles%ROWTYPE; v_target uuid; v_report uuid; v_receipt jsonb;
BEGIN
 PERFORM private.journey_social_timezone(p_user_id,p_auth_user_id);
 IF p_operation_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_member_id IS NULL
  OR p_kind IS NULL OR p_kind NOT IN('block','report')
  OR (p_kind='block' AND (p_blocked IS NULL OR p_reason IS NOT NULL))
  OR (p_kind='report' AND (p_blocked IS NOT NULL OR p_reason IS NULL OR p_reason NOT IN('nickname','harassment','spam','other'))) THEN
  RAISE EXCEPTION 'Invalid Journey peer command' USING ERRCODE='22023';
 END IF;
 -- NO KEY UPDATE remains compatible with target FK KEY SHARE when A/B block each other.
 PERFORM 1 FROM public.users WHERE id=p_user_id AND auth_user_id=p_auth_user_id AND status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey original identity changed' USING ERRCODE='42501'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('kind',p_kind,'expected_revision',p_expected_revision,
  'member_id',p_member_id,'reason',p_reason,'blocked',p_blocked)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_prior FROM private.journey_social_operations WHERE user_id=p_user_id AND operation_id=p_operation_id;
 IF FOUND THEN
  IF v_prior.auth_user_id<>p_auth_user_id OR v_prior.input_hash<>v_hash THEN
   RAISE EXCEPTION 'Journey operation content changed' USING ERRCODE='PT409';
  END IF;
  RETURN jsonb_build_object('status','replayed','receipt',v_prior.receipt,'profile',public.read_journey_social_profile(p_user_id,p_auth_user_id));
 END IF;
 SELECT * INTO v_profile FROM private.journey_social_profiles WHERE user_id=p_user_id AND auth_user_id=p_auth_user_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey profile unavailable' USING ERRCODE='42501'; END IF;
 IF v_profile.revision<>p_expected_revision THEN RAISE EXCEPTION 'Journey social revision changed' USING ERRCODE='PT409'; END IF;
 IF p_kind='report' AND (NOT v_profile.opted_in OR v_profile.moderation<>'active') THEN
  RAISE EXCEPTION 'Journey participation required' USING ERRCODE='42501';
 END IF;
 SELECT p.user_id INTO v_target FROM private.journey_social_profiles p JOIN public.users u
  ON u.id=p.user_id AND u.auth_user_id=p.auth_user_id WHERE p.member_id=p_member_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey member unavailable' USING ERRCODE='PT404'; END IF;
 IF v_target=p_user_id THEN RAISE EXCEPTION 'Cannot target own Journey profile' USING ERRCODE='22023'; END IF;
 IF p_kind='block' THEN
  IF p_blocked THEN
   INSERT INTO private.journey_social_blocks(blocker_id,target_id) VALUES(p_user_id,v_target) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM private.journey_social_blocks WHERE blocker_id=p_user_id AND target_id=v_target;
  END IF;
  v_receipt:=jsonb_build_object('operation_id',p_operation_id,'revision',v_profile.revision+1,'member_id',p_member_id,'blocked',p_blocked);
 ELSE
  INSERT INTO private.journey_social_reports(reporter_id,target_id,reason) VALUES(p_user_id,v_target,p_reason)
   ON CONFLICT(reporter_id,target_id,reason) WHERE status='pending' DO NOTHING RETURNING id INTO v_report;
  IF v_report IS NULL THEN
   SELECT id INTO STRICT v_report FROM private.journey_social_reports WHERE reporter_id=p_user_id AND target_id=v_target AND reason=p_reason AND status='pending';
  END IF;
  v_receipt:=jsonb_build_object('operation_id',p_operation_id,'revision',v_profile.revision+1,'report_id',v_report,'report_status','pending');
 END IF;
 UPDATE private.journey_social_profiles SET revision=revision+1,updated_at=clock_timestamp() WHERE user_id=p_user_id;
 INSERT INTO private.journey_social_operations(user_id,operation_id,auth_user_id,input_hash,receipt)
  VALUES(p_user_id,p_operation_id,p_auth_user_id,v_hash,v_receipt);
 RETURN jsonb_build_object('status','applied','receipt',v_receipt,'profile',public.read_journey_social_profile(p_user_id,p_auth_user_id));
END $$;
REVOKE ALL ON FUNCTION private.commit_journey_social_peer_command(uuid,uuid,uuid,bigint,uuid,text,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.mutate_journey_social_block(p_user_id uuid,p_auth_user_id uuid,p_operation_id uuid,p_expected_revision bigint,p_member_id uuid,p_blocked boolean)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
 SELECT private.commit_journey_social_peer_command(p_user_id,p_auth_user_id,p_operation_id,p_expected_revision,p_member_id,'block',NULL,p_blocked);
$$;
REVOKE ALL ON FUNCTION public.mutate_journey_social_block(uuid,uuid,uuid,bigint,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mutate_journey_social_block(uuid,uuid,uuid,bigint,uuid,boolean) TO service_role;
CREATE FUNCTION public.submit_journey_social_report(p_user_id uuid,p_auth_user_id uuid,p_operation_id uuid,p_expected_revision bigint,p_member_id uuid,p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
 SELECT private.commit_journey_social_peer_command(p_user_id,p_auth_user_id,p_operation_id,p_expected_revision,p_member_id,'report',p_reason,NULL);
$$;
REVOKE ALL ON FUNCTION public.submit_journey_social_report(uuid,uuid,uuid,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_journey_social_report(uuid,uuid,uuid,bigint,uuid,text) TO service_role;

CREATE FUNCTION public.read_journey_social_blocks(p_user_id uuid,p_auth_user_id uuid,p_limit integer DEFAULT 50,p_after_member_id uuid DEFAULT NULL,p_expected_revision bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_revision bigint; v_entries jsonb; v_more boolean;
BEGIN
 PERFORM private.journey_social_timezone(p_user_id,p_auth_user_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR ((p_after_member_id IS NULL)<>(p_expected_revision IS NULL)) THEN
  RAISE EXCEPTION 'Invalid Journey block page' USING ERRCODE='22023';
 END IF;
 SELECT coalesce((SELECT revision FROM private.journey_social_profiles WHERE user_id=p_user_id),0) INTO v_revision;
 IF p_expected_revision IS NOT NULL AND p_expected_revision<>v_revision THEN
  RAISE EXCEPTION 'Journey block list changed' USING ERRCODE='PT409';
 END IF;
 WITH visible AS (
  SELECT p.member_id,CASE WHEN p.opted_in AND p.moderation='active' AND u.status='active' AND u.auth_user_id=p.auth_user_id THEN p.nickname ELSE NULL END AS nickname
  FROM private.journey_social_blocks b JOIN private.journey_social_profiles p ON p.user_id=b.target_id JOIN public.users u ON u.id=p.user_id
  WHERE b.blocker_id=p_user_id AND (p_after_member_id IS NULL OR p.member_id>p_after_member_id)
  ORDER BY p.member_id LIMIT p_limit+1
 ), page AS (SELECT * FROM visible ORDER BY member_id LIMIT p_limit)
 SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',member_id,'nickname',nickname) ORDER BY member_id) FROM page),'[]'::jsonb),
  (SELECT count(*)>p_limit FROM visible) INTO v_entries,v_more;
 RETURN jsonb_build_object('revision',v_revision,'entries',v_entries,'next_cursor',CASE WHEN v_more THEN
  jsonb_build_object('revision',v_revision,'after_member_id',v_entries#>>ARRAY[(jsonb_array_length(v_entries)-1)::text,'member_id']) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.read_journey_social_blocks(uuid,uuid,integer,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_journey_social_blocks(uuid,uuid,integer,uuid,bigint) TO service_role;

-- Shared row projection keeps the old first-page reader and the new pager equivalent.
CREATE FUNCTION private.journey_weekly_ranking_rows(p_user_id uuid,p_auth_user_id uuid,p_at timestamptz)
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
  JOIN auth.users a ON a.id=p.auth_user_id
  WHERE p.opted_in AND p.moderation='active' AND NOT EXISTS(SELECT 1 FROM private.journey_social_blocks b WHERE
   (b.blocker_id=p_user_id AND b.target_id=p.user_id) OR (b.target_id=p_user_id AND b.blocker_id=p.user_id))
 ), totals AS (
  SELECT e.user_id,e.member_id,e.nickname,coalesce(sum(s.xp_earned),0)::bigint AS weekly_xp FROM eligible e
  LEFT JOIN public.daily_snapshots s ON s.user_id=e.user_id AND s.day_closed AND s.date>=v_start AND s.date<=least(v_start+6,v_date)
  GROUP BY e.user_id,e.member_id,e.nickname
 ) SELECT t.member_id,t.nickname,t.weekly_xp,rank() OVER(ORDER BY t.weekly_xp DESC),t.user_id=p_user_id FROM totals t;
END $$;
REVOKE ALL ON FUNCTION private.journey_weekly_ranking_rows(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.project_journey_weekly_ranking_page(p_user_id uuid,p_auth_user_id uuid,p_at timestamptz,p_limit integer,p_cursor jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_timezone text; v_date date; v_start date; v_viewer uuid; v_revision bigint; v_offset integer:=0;
 v_hash text; v_entries jsonb; v_total bigint; v_next jsonb; v_numeric numeric;
BEGIN
 v_timezone:=private.journey_social_timezone(p_user_id,p_auth_user_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_at IS NULL OR NOT isfinite(p_at) THEN
  RAISE EXCEPTION 'Invalid ranking page bounds' USING ERRCODE='22023';
 END IF;
 v_date:=(p_at AT TIME ZONE v_timezone)::date;v_start:=date_trunc('week',v_date::timestamp)::date;
 SELECT member_id,revision INTO v_viewer,v_revision FROM private.journey_social_profiles WHERE user_id=p_user_id;
 IF p_cursor IS NOT NULL THEN
  IF jsonb_typeof(p_cursor)<>'object' OR octet_length(p_cursor::text)>2048 THEN RAISE EXCEPTION 'Invalid ranking cursor' USING ERRCODE='22023'; END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_cursor) k) IS DISTINCT FROM ARRAY['context_hash','offset','through_date','viewer_member_id','week_start']
   OR jsonb_typeof(p_cursor->'offset') IS DISTINCT FROM 'number'
   OR jsonb_typeof(p_cursor->'context_hash') IS DISTINCT FROM 'string'
   OR jsonb_typeof(p_cursor->'viewer_member_id') IS DISTINCT FROM 'string'
   OR jsonb_typeof(p_cursor->'week_start') IS DISTINCT FROM 'string'
   OR jsonb_typeof(p_cursor->'through_date') IS DISTINCT FROM 'string'
   OR (p_cursor->>'context_hash') !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION 'Invalid ranking cursor fields' USING ERRCODE='22023';
  END IF;
  v_numeric:=(p_cursor->>'offset')::numeric;
  IF v_numeric<1 OR v_numeric>2147483647 OR v_numeric<>trunc(v_numeric) THEN RAISE EXCEPTION 'Invalid ranking offset' USING ERRCODE='22023'; END IF;
  v_offset:=v_numeric::integer;
 END IF;
 WITH ranked AS MATERIALIZED (SELECT * FROM private.journey_weekly_ranking_rows(p_user_id,p_auth_user_id,p_at)),
 page AS (SELECT * FROM ranked ORDER BY weekly_xp DESC,member_id LIMIT p_limit OFFSET v_offset)
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('viewer',v_viewer,'revision',v_revision,'timezone',v_timezone,'week_start',v_start,'through_date',v_date)::text||
  coalesce((SELECT string_agg(jsonb_build_object('member_id',member_id,'nickname',nickname,'rank',rank_position,'weekly_xp',weekly_xp,'is_you',is_you)::text,E'\n' ORDER BY weekly_xp DESC,member_id) FROM ranked),''),'UTF8'),'sha256'),'hex'),
  coalesce((SELECT jsonb_agg(jsonb_build_object('member_id',member_id,'nickname',nickname,'rank',rank_position,'weekly_xp',weekly_xp,'is_you',is_you) ORDER BY weekly_xp DESC,member_id) FROM page),'[]'::jsonb),
  (SELECT count(*) FROM ranked) INTO v_hash,v_entries,v_total;
 IF p_cursor IS NOT NULL AND ((p_cursor->>'context_hash') IS DISTINCT FROM v_hash
  OR (p_cursor->>'viewer_member_id') IS DISTINCT FROM v_viewer::text OR (p_cursor->>'week_start') IS DISTINCT FROM v_start::text
  OR (p_cursor->>'through_date') IS DISTINCT FROM v_date::text OR v_offset>=v_total) THEN
  RAISE EXCEPTION 'Journey ranking changed; refresh' USING ERRCODE='PT409';
 END IF;
 IF v_offset::bigint+p_limit<v_total THEN v_next:=jsonb_build_object('context_hash',v_hash,'offset',v_offset::bigint+p_limit,
  'viewer_member_id',v_viewer,'week_start',v_start,'through_date',v_date); END IF;
 RETURN jsonb_build_object('week_start',v_start,'week_end',v_start+6,'through_date',v_date,'basis','closed_daily_xp','entries',v_entries,'next_cursor',v_next);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RAISE EXCEPTION 'Invalid ranking cursor value' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION private.project_journey_weekly_ranking_page(uuid,uuid,timestamptz,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.read_journey_weekly_ranking_page(p_user_id uuid,p_auth_user_id uuid,p_limit integer DEFAULT 50,p_cursor jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
 SELECT private.project_journey_weekly_ranking_page(p_user_id,p_auth_user_id,statement_timestamp(),p_limit,p_cursor);
$$;
REVOKE ALL ON FUNCTION public.read_journey_weekly_ranking_page(uuid,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_journey_weekly_ranking_page(uuid,uuid,integer,jsonb) TO service_role;
CREATE OR REPLACE FUNCTION private.project_journey_weekly_ranking(p_user_id uuid,p_auth_user_id uuid,p_at timestamptz,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_page jsonb;
BEGIN
 v_page:=private.project_journey_weekly_ranking_page(p_user_id,p_auth_user_id,p_at,p_limit,NULL);
 RETURN (v_page-'next_cursor')||jsonb_build_object('has_more',v_page->'next_cursor'<>'null'::jsonb);
END $$;
REVOKE ALL ON FUNCTION private.project_journey_weekly_ranking(uuid,uuid,timestamptz,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.assert_journey_social_operator(p_actor_id uuid)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 IF NOT EXISTS(SELECT 1 FROM public.admin_users a JOIN auth.users u ON u.id=a.id WHERE a.id=p_actor_id AND a.role IN('operations_admin','master_admin')) THEN
  RAISE EXCEPTION 'Journey operational moderation unavailable' USING ERRCODE='42501';
 END IF;
END $$;
REVOKE ALL ON FUNCTION private.assert_journey_social_operator(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.moderate_journey_social_profile(p_actor_id uuid,p_operation_id uuid,p_member_id uuid,p_expected_revision bigint,p_action text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_profile private.journey_social_profiles%ROWTYPE;v_prior private.journey_social_moderation_operations%ROWTYPE;
 v_hash text;v_receipt jsonb;v_state text;
BEGIN
 PERFORM private.assert_journey_social_operator(p_actor_id);
 IF p_operation_id IS NULL OR p_member_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_action IS NULL OR p_action NOT IN('suspend','restore') THEN
  RAISE EXCEPTION 'Invalid Journey moderation command' USING ERRCODE='22023';
 END IF;
 PERFORM 1 FROM public.admin_users WHERE id=p_actor_id AND role IN('operations_admin','master_admin') FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey operator changed' USING ERRCODE='42501'; END IF;
 SELECT p.* INTO v_profile FROM private.journey_social_profiles p JOIN public.users u ON u.id=p.user_id AND u.auth_user_id=p.auth_user_id AND u.status='active'
  WHERE p.member_id=p_member_id FOR NO KEY UPDATE OF u;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey member unavailable' USING ERRCODE='PT404'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('kind','moderation','member_id',p_member_id,'expected_revision',p_expected_revision,'action',p_action)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_prior FROM private.journey_social_moderation_operations WHERE actor_id=p_actor_id AND operation_id=p_operation_id;
 IF FOUND THEN
  IF v_prior.input_hash<>v_hash THEN RAISE EXCEPTION 'Journey moderation operation changed' USING ERRCODE='PT409'; END IF;
  RETURN jsonb_build_object('status','replayed','receipt',v_prior.receipt,'profile',public.read_journey_social_profile(v_profile.user_id,v_profile.auth_user_id));
 END IF;
 -- Re-read after the owner lock: a concurrent participant may have withdrawn.
 SELECT * INTO STRICT v_profile FROM private.journey_social_profiles WHERE user_id=v_profile.user_id;
 IF v_profile.revision<>p_expected_revision THEN RAISE EXCEPTION 'Journey profile revision changed' USING ERRCODE='PT409'; END IF;
 v_state:=CASE WHEN p_action='suspend' THEN 'suspended' ELSE 'active' END;
 UPDATE private.journey_social_profiles SET moderation=v_state,revision=revision+1,updated_at=clock_timestamp() WHERE user_id=v_profile.user_id;
 v_receipt:=jsonb_build_object('operation_id',p_operation_id,'member_id',p_member_id,'revision',v_profile.revision+1,
  'previous_moderation',v_profile.moderation,'moderation',v_state);
 INSERT INTO private.journey_social_moderation_operations(actor_id,operation_id,target_id,input_hash,receipt)
  VALUES(p_actor_id,p_operation_id,v_profile.user_id,v_hash,v_receipt);
 RETURN jsonb_build_object('status','applied','receipt',v_receipt,'profile',public.read_journey_social_profile(v_profile.user_id,v_profile.auth_user_id));
END $$;
REVOKE ALL ON FUNCTION public.moderate_journey_social_profile(uuid,uuid,uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.moderate_journey_social_profile(uuid,uuid,uuid,bigint,text) TO service_role;

CREATE FUNCTION public.read_journey_social_reports(p_actor_id uuid,p_limit integer DEFAULT 50,p_after_at timestamptz DEFAULT NULL,p_after_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_entries jsonb;v_more boolean;
BEGIN
 PERFORM private.assert_journey_social_operator(p_actor_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR ((p_after_at IS NULL)<>(p_after_id IS NULL)) OR (p_after_at IS NOT NULL AND NOT isfinite(p_after_at)) THEN
  RAISE EXCEPTION 'Invalid moderation queue page' USING ERRCODE='22023';
 END IF;
 WITH visible AS (
  SELECT r.id,r.reason,r.status,r.revision,r.created_at,p.member_id,p.nickname,p.moderation,p.revision AS profile_revision
  FROM private.journey_social_reports r JOIN private.journey_social_profiles p ON p.user_id=r.target_id
  WHERE r.status='pending' AND (p_after_at IS NULL OR (r.created_at,r.id)>(p_after_at,p_after_id)) ORDER BY r.created_at,r.id LIMIT p_limit+1
 ), page AS(SELECT * FROM visible ORDER BY created_at,id LIMIT p_limit)
 SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('report_id',id,'reason',reason,'status',status,'revision',revision,'created_at',created_at,
  'member_id',member_id,'nickname',nickname,'moderation',moderation,'profile_revision',profile_revision) ORDER BY created_at,id) FROM page),'[]'::jsonb),
  (SELECT count(*)>p_limit FROM visible) INTO v_entries,v_more;
 RETURN jsonb_build_object('entries',v_entries,'next_cursor',CASE WHEN v_more THEN jsonb_build_object(
  'created_at',v_entries#>>ARRAY[(jsonb_array_length(v_entries)-1)::text,'created_at'],'report_id',v_entries#>>ARRAY[(jsonb_array_length(v_entries)-1)::text,'report_id']) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.read_journey_social_reports(uuid,integer,timestamptz,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_journey_social_reports(uuid,integer,timestamptz,uuid) TO service_role;
CREATE FUNCTION public.resolve_journey_social_report(p_actor_id uuid,p_operation_id uuid,p_report_id uuid,p_expected_revision bigint,p_status text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_report private.journey_social_reports%ROWTYPE;v_prior private.journey_social_moderation_operations%ROWTYPE;v_hash text;v_receipt jsonb;
BEGIN
 PERFORM private.assert_journey_social_operator(p_actor_id);
 IF p_operation_id IS NULL OR p_report_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_status IS NULL OR p_status NOT IN('dismissed','resolved') THEN
  RAISE EXCEPTION 'Invalid report resolution' USING ERRCODE='22023';
 END IF;
 PERFORM 1 FROM public.admin_users WHERE id=p_actor_id AND role IN('operations_admin','master_admin') FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey operator changed' USING ERRCODE='42501'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('kind','report_resolution','report_id',p_report_id,'expected_revision',p_expected_revision,'status',p_status)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_prior FROM private.journey_social_moderation_operations WHERE actor_id=p_actor_id AND operation_id=p_operation_id;
 IF FOUND THEN
  IF v_prior.input_hash<>v_hash THEN RAISE EXCEPTION 'Journey resolution operation changed' USING ERRCODE='PT409'; END IF;
  RETURN jsonb_build_object('status','replayed','receipt',v_prior.receipt);
 END IF;
 SELECT * INTO v_report FROM private.journey_social_reports WHERE id=p_report_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Journey report unavailable' USING ERRCODE='PT404'; END IF;
 IF v_report.revision<>p_expected_revision OR v_report.status<>'pending' THEN RAISE EXCEPTION 'Journey report changed' USING ERRCODE='PT409'; END IF;
 UPDATE private.journey_social_reports SET status=p_status,revision=revision+1,updated_at=clock_timestamp() WHERE id=p_report_id;
 v_receipt:=jsonb_build_object('operation_id',p_operation_id,'report_id',p_report_id,'revision',v_report.revision+1,'report_status',p_status);
 INSERT INTO private.journey_social_moderation_operations(actor_id,operation_id,target_id,input_hash,receipt)
  VALUES(p_actor_id,p_operation_id,v_report.target_id,v_hash,v_receipt);
 RETURN jsonb_build_object('status','applied','receipt',v_receipt);
END $$;
REVOKE ALL ON FUNCTION public.resolve_journey_social_report(uuid,uuid,uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_journey_social_report(uuid,uuid,uuid,bigint,text) TO service_role;
COMMIT;

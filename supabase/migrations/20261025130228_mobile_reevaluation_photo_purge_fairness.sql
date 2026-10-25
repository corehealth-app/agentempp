-- Durable technical fairness; does not change eligibility, retention or capabilities.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.mobile_reevaluation_photo_disposition_purge_ready(private.mobile_reevaluation_photo_dispositions,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'mobile_reevaluation_purge_fairness_precondition' USING ERRCODE='42501';
 END IF;
END $preflight$;
CREATE TABLE private.mobile_reevaluation_photo_purge_owner_visits(
 user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 visited_at timestamptz NOT NULL CHECK(isfinite(visited_at))
);
CREATE TABLE private.mobile_reevaluation_photo_purge_scope_visits(
 acceptance_id uuid PRIMARY KEY REFERENCES private.mobile_reevaluation_photo_consents(acceptance_id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 visited_at timestamptz NOT NULL CHECK(isfinite(visited_at))
);
CREATE INDEX mobile_reevaluation_photo_purge_scope_visits_owner ON private.mobile_reevaluation_photo_purge_scope_visits(user_id);
ALTER TABLE private.mobile_reevaluation_photo_purge_owner_visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_reevaluation_photo_purge_scope_visits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_purge_owner_visits,private.mobile_reevaluation_photo_purge_scope_visits FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.list_mobile_deleted_users_for_photo_purge(p_cutoff timestamptz,p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE ids uuid[];at_time timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 at_time:=clock_timestamp();
 IF current_setting('transaction_isolation')<>'read committed' OR p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_purge_claim' USING ERRCODE='22023';
 END IF;
 ids:=ARRAY(SELECT u.id FROM public.users u LEFT JOIN private.mobile_reevaluation_photo_purge_owner_visits v ON v.user_id=u.id
  WHERE u.status='deleted' AND u.updated_at<=p_cutoff
  ORDER BY v.visited_at ASC NULLS FIRST,u.updated_at,u.id LIMIT p_limit FOR UPDATE OF u SKIP LOCKED);
 at_time:=clock_timestamp();
 RETURN jsonb_build_object('version',1,'users',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id) ORDER BY ord) FROM unnest(ids) WITH ORDINALITY x(id,ord)),'[]'::jsonb));
END $$;

CREATE FUNCTION public.begin_mobile_deleted_user_photo_purge(p_user_id uuid,p_cutoff timestamptz)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE eligible boolean;at_time timestamptz;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);at_time:=clock_timestamp();
 IF p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_purge_claim' USING ERRCODE='22023';END IF;
 SELECT u.status='deleted' AND u.updated_at<=p_cutoff INTO eligible FROM public.users u WHERE u.id=p_user_id;
 IF eligible THEN
  INSERT INTO private.mobile_reevaluation_photo_purge_owner_visits(user_id,visited_at) VALUES(p_user_id,at_time)
   ON CONFLICT(user_id) DO UPDATE SET visited_at=EXCLUDED.visited_at;
 END IF;
 RETURN eligible;
END $$;

CREATE FUNCTION public.claim_mobile_reevaluation_photo_purge_scopes(p_user_id uuid,p_cutoff timestamptz,p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz;eligible boolean;ids uuid[];more boolean;items jsonb;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);at_time:=clock_timestamp();
 IF p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_purge_claim' USING ERRCODE='22023';
 END IF;
 SELECT u.status='deleted' AND u.updated_at<=p_cutoff INTO eligible FROM public.users u WHERE u.id=p_user_id;
 IF NOT eligible THEN RETURN jsonb_build_object('version',1,'user_id',p_user_id,'eligible',false,'items','[]'::jsonb,'has_more',false);END IF;
 ids:=ARRAY(SELECT a.acceptance_id FROM private.mobile_reevaluation_photo_consents a
  LEFT JOIN private.mobile_reevaluation_photo_dispositions h ON h.acceptance_id=a.acceptance_id
  LEFT JOIN private.mobile_reevaluation_photo_purge_scope_visits v ON v.acceptance_id=a.acceptance_id
  WHERE a.user_id=p_user_id AND(h.disposition_id IS NULL OR h.sweep_state IN('idle','pending')
   OR(h.sweep_state='waiting' AND h.next_sweep_at<=at_time)
   OR(h.sweep_state='settled' AND NOT private.mobile_reevaluation_photo_disposition_purge_ready(h,at_time)))
  ORDER BY v.visited_at ASC NULLS FIRST,a.acceptance_id LIMIT p_limit+1);
 more:=cardinality(ids)>p_limit;ids:=ids[1:p_limit];
 SELECT coalesce(jsonb_agg(jsonb_build_object('cycle_id',a.cycle_id,'acceptance_id',a.acceptance_id) ORDER BY x.ord),'[]'::jsonb)
  INTO items FROM unnest(ids) WITH ORDINALITY x(id,ord) JOIN private.mobile_reevaluation_photo_consents a ON a.acceptance_id=x.id AND a.user_id=p_user_id;
 -- Reserve the visit before external work, including failed/timed-out removals.
 INSERT INTO private.mobile_reevaluation_photo_purge_scope_visits(acceptance_id,user_id,visited_at)
  SELECT unnest(ids),p_user_id,clock_timestamp() ON CONFLICT(acceptance_id) DO UPDATE SET visited_at=EXCLUDED.visited_at;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'eligible',true,'items',items,'has_more',more);
END $$;
REVOKE ALL ON FUNCTION public.list_mobile_deleted_users_for_photo_purge(timestamptz,integer),
 public.begin_mobile_deleted_user_photo_purge(uuid,timestamptz),
 public.claim_mobile_reevaluation_photo_purge_scopes(uuid,timestamptz,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.list_mobile_deleted_users_for_photo_purge(timestamptz,integer),
 public.begin_mobile_deleted_user_photo_purge(uuid,timestamptz),
 public.claim_mobile_reevaluation_photo_purge_scopes(uuid,timestamptz,integer) TO service_role;
COMMIT;

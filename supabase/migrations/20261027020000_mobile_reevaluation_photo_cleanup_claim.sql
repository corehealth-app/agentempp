-- Dormant normal cleanup discovery. No policy/text, cron or Storage activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('public.prepare_mobile_reevaluation_photo_disposition(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'mobile_reevaluation_cleanup_claim_precondition' USING ERRCODE='42501';
 END IF;
END $preflight$;

-- No user FK: discovery locks an acceptance, not its owner. A second FK lock
-- on users here would invert the owner -> acceptance order of clinical writes.
CREATE TABLE private.mobile_reevaluation_photo_cleanup_visits(
 acceptance_id uuid PRIMARY KEY REFERENCES private.mobile_reevaluation_photo_consents(acceptance_id) ON DELETE CASCADE,
 visited_at timestamptz NOT NULL CHECK(isfinite(visited_at))
);
ALTER TABLE private.mobile_reevaluation_photo_cleanup_visits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_cleanup_visits FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX mobile_reevaluation_photo_cleanup_activity ON private.mobile_reevaluation_photo_consents(last_activity_at,acceptance_id);
CREATE INDEX mobile_reevaluation_photo_cleanup_waiting ON private.mobile_reevaluation_photo_dispositions(next_sweep_at,acceptance_id) WHERE sweep_state='waiting';

CREATE FUNCTION public.claim_mobile_reevaluation_photo_cleanup_scopes(p_limit integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
DECLARE at_time timestamptz;ids uuid[];more boolean;items jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup_claim' USING ERRCODE='22023';
 END IF;
 at_time:=clock_timestamp();
 ids:=ARRAY(
  SELECT a.acceptance_id FROM private.mobile_reevaluation_photo_consents a
   JOIN public.users u ON u.id=a.user_id
   JOIN private.mobile_reevaluation_cycles c ON c.cycle_id=a.cycle_id AND c.user_id=a.user_id
   LEFT JOIN public.user_profiles p ON p.user_id=a.user_id
   LEFT JOIN private.workout_strength_authority_epochs e ON e.user_id=a.user_id
   LEFT JOIN private.mobile_signup_strength_completion_receipts r ON r.user_id=a.user_id AND r.admission_id=a.signup_generation
   LEFT JOIN private.mobile_reevaluation_photo_dispositions h ON h.acceptance_id=a.acceptance_id
   LEFT JOIN private.mobile_reevaluation_photo_cleanup_visits v ON v.acceptance_id=a.acceptance_id
   LEFT JOIN LATERAL(
    SELECT d.id FROM public.legal_documents d WHERE d.document_key='body_photo_reevaluation_consent'
     AND d.locale=u.locale AND d.required_from<=at_time ORDER BY d.required_from DESC,d.created_at DESC,d.id DESC LIMIT 1
   ) doc ON true
   LEFT JOIN private.mobile_reevaluation_photo_policies policy ON policy.document_id=doc.id
  WHERE u.status<>'deleted' AND (
   (h.disposition_id IS NULL AND (
    a.revoked_at IS NOT NULL OR a.last_activity_at+make_interval(secs=>a.idle_timeout_seconds)<=at_time
    OR c.status NOT IN('open','collecting','review_ready')
    OR p.onboarding_completed IS DISTINCT FROM true OR c.signup_epoch IS DISTINCT FROM e.epoch
    OR r.completed_at IS DISTINCT FROM p.onboarding_completed_at OR r.outcome IS DISTINCT FROM 'first_fresh'
    OR a.document_id IS DISTINCT FROM doc.id OR a.locale IS DISTINCT FROM u.locale OR policy.enabled IS DISTINCT FROM true
   )) OR (h.disposition_id IS NOT NULL AND (h.sweep_state IN('idle','pending')
    OR(h.sweep_state='waiting' AND h.next_sweep_at<=at_time)))
  )
  ORDER BY coalesce(v.visited_at,a.accepted_at),a.acceptance_id LIMIT p_limit+1 FOR UPDATE OF a SKIP LOCKED
 );
 more:=cardinality(ids)>p_limit;ids:=ids[1:p_limit];
 -- Commit this technical visit before any external removal, including failures.
 -- The original prepare RPC still makes the final decision: a candidate which
 -- was renewed or otherwise remains valid will return live and is not removed.
 INSERT INTO private.mobile_reevaluation_photo_cleanup_visits(acceptance_id,visited_at)
  SELECT unnest(ids),clock_timestamp() ON CONFLICT(acceptance_id) DO UPDATE SET visited_at=EXCLUDED.visited_at;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'cycle_id',a.cycle_id,'acceptance_id',a.acceptance_id) ORDER BY x.ord),'[]'::jsonb)
  INTO items FROM unnest(ids) WITH ORDINALITY x(id,ord) JOIN private.mobile_reevaluation_photo_consents a ON a.acceptance_id=x.id;
 RETURN jsonb_build_object('version',1,'items',items,'has_more',more);
END $$;
REVOKE ALL ON FUNCTION public.claim_mobile_reevaluation_photo_cleanup_scopes(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_mobile_reevaluation_photo_cleanup_scopes(integer) TO service_role;
COMMIT;

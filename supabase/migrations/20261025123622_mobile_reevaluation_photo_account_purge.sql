-- Backend-only account cleanup. No cron, policy publication or external removal.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_reevaluation_photo_dispositions') IS NULL THEN
  RAISE EXCEPTION 'mobile_reevaluation_purge_precondition' USING ERRCODE='42501';
 END IF;
END $preflight$;

CREATE FUNCTION private.mobile_reevaluation_photo_disposition_purge_ready(
 h private.mobile_reevaluation_photo_dispositions,p_observed_at timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT coalesce(
  (h).sweep_state='settled' AND (h).sweep_no>0
  AND (h).sweep_capability_revision=(h).capability_revision
  AND (h).sealed_at<=(h).sweep_started_at
  AND (h).sweep_started_at<=(h).last_ack_at AND (h).last_ack_at<=p_observed_at
  AND (h).manifest_count=(SELECT count(*) FROM private.mobile_reevaluation_photo_disposition_assets d WHERE d.disposition_id=(h).disposition_id)
  AND (h).manifest_count=(SELECT count(*) FROM private.mobile_reevaluation_photo_assets l
    WHERE l.user_id=(h).user_id AND l.signup_generation=(h).signup_generation
      AND l.cycle_id=(h).cycle_id AND l.consent_acceptance_id=(h).acceptance_id)
  AND (h).cursor IS NOT DISTINCT FROM (SELECT max(d.asset_id::text)::uuid
    FROM private.mobile_reevaluation_photo_disposition_assets d WHERE d.disposition_id=(h).disposition_id)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_upload_tickets t
    WHERE t.user_id=(h).user_id AND t.consent_acceptance_id=(h).acceptance_id
      AND (t.provider_expires_at IS NULL OR t.provider_expires_at>=(h).sweep_started_at))
  AND NOT EXISTS(
    SELECT 1 FROM private.mobile_reevaluation_photo_disposition_assets d
    JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=d.asset_id
    LEFT JOIN public.media_assets m ON m.id=d.asset_id
    WHERE d.disposition_id=(h).disposition_id AND (
      d.last_sweep_no<>(h).sweep_no OR d.last_ack_at IS NULL
      OR d.last_ack_at<(h).sweep_started_at OR d.last_ack_at>(h).last_ack_at
      OR l.invalidated_at IS NULL OR l.invalidated_at>p_observed_at
      OR m.id IS NULL OR m.user_id<>d.user_id OR m.reevaluation_origin_version IS DISTINCT FROM 1
      OR m.bucket_id<>d.bucket_id OR m.object_path<>d.object_path OR m.mime_type<>d.mime_type
      OR m.processing_result IS NOT NULL
      OR NOT(m.status='deleted' OR(m.status='failed' AND m.failure_stage='upload'))
    )),false)
$$;

CREATE FUNCTION private.purge_mobile_reevaluation_photo_catalog_at(
 p_user_id uuid,p_cutoff timestamptz,p_observed_at timestamptz)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE owner_row public.users%ROWTYPE;at_time timestamptz;constraint_row record;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_cutoff IS NULL OR NOT isfinite(p_cutoff)
  OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_purge' USING ERRCODE='22023';
 END IF;
 SELECT u.* INTO owner_row FROM public.users u WHERE u.id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 -- Same owner serialization as allocation, ticket registration, processing and ACK.
 PERFORM m.id FROM public.media_assets m WHERE m.user_id=p_user_id
  AND m.reevaluation_origin_version=1 ORDER BY m.id FOR UPDATE;
 at_time:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(at_time) OR p_cutoff>at_time THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_purge_clock' USING ERRCODE='22023';
 END IF;
 IF owner_row.status<>'deleted' OR owner_row.updated_at>p_cutoff THEN RETURN false;END IF;
 IF EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_dispositions h
   WHERE h.user_id=p_user_id AND NOT private.mobile_reevaluation_photo_disposition_purge_ready(h,at_time))
  OR EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_assets l
   LEFT JOIN private.mobile_reevaluation_photo_disposition_assets d ON d.asset_id=l.asset_id
   WHERE l.user_id=p_user_id AND d.asset_id IS NULL)
  OR EXISTS(SELECT 1 FROM public.media_assets m
   LEFT JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=m.id
   WHERE m.user_id=p_user_id AND m.reevaluation_origin_version=1 AND l.asset_id IS NULL)
 THEN RETURN false;END IF;
 -- Defer only the existing ledger->media FK, retaining the immediate reverse FK.
 -- This also works when a caller previously selected SET CONSTRAINTS ALL IMMEDIATE.
 FOR constraint_row IN SELECT conname FROM pg_constraint
  WHERE conrelid='private.mobile_reevaluation_photo_assets'::regclass
   AND confrelid='public.media_assets'::regclass AND contype='f' AND condeferrable
 LOOP EXECUTE format('SET CONSTRAINTS private.%I DEFERRED',constraint_row.conname);END LOOP;
 DELETE FROM private.mobile_reevaluation_photo_disposition_assets WHERE user_id=p_user_id;
 DELETE FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=p_user_id;
 DELETE FROM private.mobile_reevaluation_photo_processing_attempts WHERE user_id=p_user_id;
 DELETE FROM private.mobile_reevaluation_photo_sources WHERE user_id=p_user_id;
 DELETE FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id=p_user_id;
 DELETE FROM public.media_assets WHERE user_id=p_user_id AND reevaluation_origin_version=1;
 DELETE FROM private.mobile_reevaluation_photo_assets WHERE user_id=p_user_id;
 RETURN true;
END $$;

CREATE FUNCTION public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(p_user_id uuid,p_cutoff timestamptz)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.purge_mobile_reevaluation_photo_catalog_at(p_user_id,p_cutoff,NULL)
$$;

CREATE FUNCTION public.list_mobile_reevaluation_photo_purge_scopes(
 p_user_id uuid,p_cutoff timestamptz,p_after_acceptance uuid DEFAULT NULL,p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz;eligible boolean;items jsonb;more boolean;last_id uuid;
BEGIN
 PERFORM private.mobile_reevaluation_photo_cleanup_owner(p_user_id);
 at_time:=clock_timestamp();
 IF p_cutoff IS NULL OR NOT isfinite(p_cutoff) OR p_cutoff>at_time OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_purge' USING ERRCODE='22023';
 END IF;
 SELECT u.status='deleted' AND u.updated_at<=p_cutoff INTO eligible FROM public.users u WHERE u.id=p_user_id;
 IF NOT eligible THEN RETURN jsonb_build_object('version',1,'user_id',p_user_id,'eligible',false,'items','[]'::jsonb,'has_more',false,'cursor',NULL);END IF;
 WITH due AS (
  SELECT a.cycle_id,a.acceptance_id FROM private.mobile_reevaluation_photo_consents a
  LEFT JOIN private.mobile_reevaluation_photo_dispositions h ON h.acceptance_id=a.acceptance_id
  WHERE a.user_id=p_user_id AND(p_after_acceptance IS NULL OR a.acceptance_id>p_after_acceptance)
   AND(h.disposition_id IS NULL OR h.sweep_state IN('idle','pending')
    OR(h.sweep_state='waiting' AND h.next_sweep_at<=at_time)
    OR(h.sweep_state='settled' AND NOT private.mobile_reevaluation_photo_disposition_purge_ready(h,at_time)))
  ORDER BY a.acceptance_id LIMIT p_limit+1
 ), page AS (SELECT * FROM due ORDER BY acceptance_id LIMIT p_limit)
 SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('cycle_id',cycle_id,'acceptance_id',acceptance_id) ORDER BY acceptance_id) FROM page),'[]'::jsonb),
  (SELECT count(*)>p_limit FROM due),(SELECT max(acceptance_id::text)::uuid FROM page)
 INTO items,more,last_id;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'eligible',true,'items',items,'has_more',more,'cursor',last_id);
END $$;

REVOKE ALL ON FUNCTION private.mobile_reevaluation_photo_disposition_purge_ready(private.mobile_reevaluation_photo_dispositions,timestamptz),
 private.purge_mobile_reevaluation_photo_catalog_at(uuid,timestamptz,timestamptz),
 public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(uuid,timestamptz),
 public.list_mobile_reevaluation_photo_purge_scopes(uuid,timestamptz,uuid,integer)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(uuid,timestamptz),
 public.list_mobile_reevaluation_photo_purge_scopes(uuid,timestamptz,uuid,integer) TO service_role;
COMMIT;

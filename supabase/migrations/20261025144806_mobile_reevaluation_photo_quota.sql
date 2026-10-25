-- Per-person recurring-photo allocation quota. Replays return before INSERT;
-- existing historical rows remain intact and also count until 24h have elapsed.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN
  RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501';
 END IF;
 IF to_regprocedure('private.mobile_reevaluation_lock_owner(uuid)') IS NULL
  OR to_regclass('private.mobile_reevaluation_photo_assets') IS NULL THEN
  RAISE EXCEPTION 'mobile_reevaluation_requires_photo_authority' USING ERRCODE='42P01';
 END IF;
END $preflight$;

CREATE INDEX mobile_reevaluation_photo_assets_quota
 ON private.mobile_reevaluation_photo_assets(user_id,created_at DESC);

CREATE FUNCTION private.enforce_mobile_reevaluation_photo_quota() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 -- Reentrant for the allocator, which has already captured its context clock
 -- after this owner lock. Direct ledger inserts must serialize as well.
 PERFORM private.mobile_reevaluation_lock_owner(NEW.user_id);
 IF (SELECT count(*) FROM (
   SELECT 1 FROM private.mobile_reevaluation_photo_assets l
    WHERE l.user_id=NEW.user_id AND l.created_at>NEW.created_at-interval '24 hours'
    LIMIT 6
  ) recent)>=6 THEN
  RAISE EXCEPTION 'mobile_reevaluation_photo_limit_reached' USING ERRCODE='P0001';
 END IF;
 -- No filter on cycle, consent, status or invalidation. Discard, reset and
 -- substitution do not restore capacity; a transaction rollback does.
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.enforce_mobile_reevaluation_photo_quota()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER enforce_mobile_reevaluation_photo_quota BEFORE INSERT
 ON private.mobile_reevaluation_photo_assets FOR EACH ROW
 EXECUTE FUNCTION private.enforce_mobile_reevaluation_photo_quota();
COMMIT;

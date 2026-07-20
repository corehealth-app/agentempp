-- Failed uploads must remain deletable by the patient API and retention worker.
-- Only processing failures may be retried as processing work.
CREATE OR REPLACE FUNCTION private.enforce_media_asset_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  IF NEW.status <> OLD.status AND NOT (
    (OLD.status = 'pending_upload' AND NEW.status IN ('uploaded', 'failed', 'deleted'))
    OR (OLD.status = 'uploaded' AND NEW.status IN ('processing', 'failed', 'deleted'))
    OR (OLD.status = 'processing' AND NEW.status IN ('processed', 'failed', 'deleted'))
    OR (
      OLD.status = 'failed'
      AND (
        NEW.status = 'deleted'
        OR (OLD.failure_stage = 'processing' AND NEW.status = 'processing')
      )
    )
    OR (OLD.status = 'processed' AND NEW.status = 'deleted')
  ) THEN
    RAISE EXCEPTION 'invalid media asset status transition: % -> %', OLD.status, NEW.status
      USING ERRCODE = '23514';
  END IF;

  IF NEW.status = 'processing' THEN
    NEW.failure_stage := NULL;
    NEW.failure_code := NULL;
  END IF;

  IF NEW.status = 'deleted' AND NEW.deleted_at IS NULL THEN
    NEW.deleted_at := clock_timestamp();
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

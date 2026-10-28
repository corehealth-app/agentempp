-- Genuine measurements and durable request acknowledgements. No backfill,
-- profile trigger, clinical consumer, target change or new calendar authority.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  OR to_regprocedure('private.apply_weight_measurement(uuid,numeric,timestamptz,text)') IS NULL THEN
  RAISE EXCEPTION 'mobile_weight_requires_existing_owner_authority' USING ERRCODE='42501';
 END IF;
END $$;

CREATE TABLE private.mobile_weight_measurements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 weight_kg numeric(5,2) NOT NULL CHECK(weight_kg BETWEEN 30 AND 300),
 measured_at timestamptz NOT NULL CHECK(isfinite(measured_at)
   AND extract(year FROM measured_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 instant_source text NOT NULL CHECK(instant_source IN('measured','recorded')),
 received_at timestamptz NOT NULL CHECK(isfinite(received_at)
   AND extract(year FROM received_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 observed_timezone text NOT NULL CHECK(length(observed_timezone) BETWEEN 1 AND 64),
 -- Observed reset epoch, not a signup completion/generation proof. Unknown stays NULL.
 authority_epoch uuid,
 UNIQUE(user_id,measured_at), UNIQUE(user_id,id)
);
CREATE TABLE private.mobile_weight_request_receipts (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9._:-]{8,128}$'),
 request_value numeric NOT NULL CHECK(request_value>0 AND request_value<=700),
 request_unit text NOT NULL CHECK(request_unit IN('kg','lb')),
 request_measured_at timestamptz NOT NULL CHECK(isfinite(request_measured_at)),
 measurement_id uuid NOT NULL,
 result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'
   AND jsonb_typeof(result->'applied')='boolean'
   AND result->>'reason' IN('applied','same_measurement','older_than_current')
   AND (result->>'weight_kg')::numeric BETWEEN 30 AND 300
   AND isfinite((result->>'measured_at')::timestamptz)
   AND result ?& ARRAY['applied','reason','weight_kg','measured_at']),
 received_at timestamptz NOT NULL CHECK(isfinite(received_at)),
 PRIMARY KEY(user_id,request_key),
 FOREIGN KEY(user_id,measurement_id) REFERENCES private.mobile_weight_measurements(user_id,id) ON DELETE CASCADE
);
ALTER TABLE private.mobile_weight_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_weight_request_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_weight_measurements,private.mobile_weight_request_receipts
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_weight_evidence_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'mobile_weight_evidence_immutable' USING ERRCODE='55000';
END $$;
CREATE TRIGGER mobile_weight_measurement_immutable BEFORE UPDATE OR DELETE ON private.mobile_weight_measurements
 FOR EACH ROW EXECUTE FUNCTION private.mobile_weight_evidence_immutable();
CREATE TRIGGER mobile_weight_request_immutable BEFORE UPDATE OR DELETE ON private.mobile_weight_request_receipts
 FOR EACH ROW EXECUTE FUNCTION private.mobile_weight_evidence_immutable();

-- Explicit time is private/test-only. The public caller passes NULL: the clock
-- is sampled after owner/profile locks, not before a potentially long wait.
CREATE FUNCTION private.record_mobile_weight_at(p_user_id uuid,p_value numeric,p_unit text,
 p_measured_at timestamptz,p_idempotency_key text,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE zone text; observed_at timestamptz; weight numeric; epoch_id uuid;
 receipt private.mobile_weight_request_receipts%ROWTYPE;
 measurement private.mobile_weight_measurements%ROWTYPE; result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' OR p_user_id IS NULL
   OR p_value IS NULL OR p_value::text IN('NaN','Infinity','-Infinity') OR p_value<=0 OR p_value>700
   OR p_unit IS NULL OR p_unit NOT IN('kg','lb') OR p_measured_at IS NULL OR NOT isfinite(p_measured_at)
   OR extract(year FROM p_measured_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
   OR p_idempotency_key IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,128}$' THEN
  RAISE EXCEPTION 'invalid weight payload' USING ERRCODE='22023';
 END IF;
 -- Same first lock as reset/cycle/photo/HOLD. Do not acquire workouts after it.
 SELECT u.timezone INTO zone FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'invalid weight payload' USING ERRCODE='22023'; END IF;
 SELECT * INTO receipt FROM private.mobile_weight_request_receipts
   WHERE user_id=p_user_id AND request_key=p_idempotency_key;
 IF FOUND THEN
  IF receipt.request_value<>p_value OR receipt.request_unit<>p_unit OR receipt.request_measured_at<>p_measured_at THEN
   RAISE EXCEPTION 'mobile_weight_request_conflict' USING ERRCODE='40001';
  END IF;
  -- No writes and no window revalidation: replay never reapplies to a reset/newer profile.
  RETURN receipt.result;
 END IF;
 IF zone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
  RAISE EXCEPTION 'invalid weight timezone' USING ERRCODE='22023';
 END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':weight',0)) THEN
  RAISE EXCEPTION 'mobile_weight_busy' USING ERRCODE='55P03';
 END IF;
 BEGIN
  PERFORM p.user_id FROM public.user_profiles p WHERE p.user_id=p_user_id FOR UPDATE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'mobile_weight_busy' USING ERRCODE='55P03';
 END;
 observed_at:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(observed_at) OR extract(year FROM observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
  RAISE EXCEPTION 'invalid weight clock' USING ERRCODE='22023';
 END IF;
 IF p_measured_at>observed_at+interval '5 minutes' OR p_measured_at<observed_at-interval '7 days' THEN
  RAISE EXCEPTION 'mobile_weight_measured_at_out_of_range' USING ERRCODE='22023';
 END IF;
 weight:=round(CASE p_unit WHEN 'lb' THEN p_value*0.45359237 ELSE p_value END,2);
 IF weight NOT BETWEEN 30 AND 300 THEN RAISE EXCEPTION 'weight out of range' USING ERRCODE='22023'; END IF;
 SELECT * INTO measurement FROM private.mobile_weight_measurements WHERE user_id=p_user_id AND measured_at=p_measured_at;
 IF FOUND AND measurement.weight_kg<>weight THEN
  RAISE EXCEPTION 'weight_measurement_conflict' USING ERRCODE='23505';
 END IF;
 result:=private.apply_weight_measurement(p_user_id,weight,p_measured_at,'mobile');
 IF measurement.id IS NULL THEN
  SELECT e.epoch INTO epoch_id FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
  INSERT INTO private.mobile_weight_measurements(user_id,weight_kg,measured_at,instant_source,received_at,observed_timezone,authority_epoch)
   VALUES(p_user_id,weight,p_measured_at,'measured',observed_at,zone,epoch_id) RETURNING * INTO measurement;
 END IF;
 INSERT INTO private.mobile_weight_request_receipts(user_id,request_key,request_value,request_unit,
   request_measured_at,measurement_id,result,received_at)
  VALUES(p_user_id,p_idempotency_key,p_value,p_unit,p_measured_at,measurement.id,result,observed_at);
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.record_weight_atomic(p_user_id uuid,p_value numeric,p_unit text,
 p_measured_at timestamptz,p_idempotency_key text) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.record_mobile_weight_at(p_user_id,p_value,p_unit,p_measured_at,p_idempotency_key,NULL)
$$;
REVOKE ALL ON FUNCTION private.mobile_weight_evidence_immutable(),
 private.record_mobile_weight_at(uuid,numeric,text,timestamptz,text,timestamptz),
 public.record_weight_atomic(uuid,numeric,text,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_weight_atomic(uuid,numeric,text,timestamptz,text) TO service_role;
COMMIT;

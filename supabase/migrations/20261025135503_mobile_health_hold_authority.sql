-- Dormant n10 authority, per person and independent of signup/cycle/photo authority.
-- Does not activate a consumer, clear a HOLD, or write clinical answers/targets.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
  IF current_user<>'postgres' THEN
    RAISE EXCEPTION 'mobile_health_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regprocedure('private.assert_trusted_backend()') IS NULL
    OR to_regprocedure('private.mobile_reevaluation_lock_owner(uuid)') IS NULL THEN
    RAISE EXCEPTION 'mobile_health_requires_owner_authority' USING ERRCODE='42P01';
  END IF;
END $$;

-- Technical codes of the single core n10 v1 catalog, in exactly the same order.
CREATE TYPE private.mobile_health_risk_code_v1 AS ENUM (
 'unintended_weight_loss','reduced_intake','persistent_fatigue_weakness_dizziness',
 'menstrual_change','loss_of_control_eating','appetite_weight_treatment',
 'professional_diet','pregnant_or_breastfeeding');
REVOKE ALL ON TYPE private.mobile_health_risk_code_v1 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_health_risks_canonical(p_items private.mobile_health_risk_code_v1[])
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT coalesce(p_items=ARRAY(SELECT DISTINCT x FROM unnest(p_items) x ORDER BY x)
   AND array_position(p_items,NULL) IS NULL,false)
$$;

CREATE TABLE private.mobile_health_hold_states (
 user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 safety_revision bigint NOT NULL CHECK(safety_revision>0),
 hold_active boolean NOT NULL,
 items private.mobile_health_risk_code_v1[] NOT NULL,
 last_declared_at timestamptz NOT NULL CHECK(isfinite(last_declared_at)
   AND extract(year FROM last_declared_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 CHECK(private.mobile_health_risks_canonical(items)),
 CHECK(hold_active=(cardinality(items)>0))
);
CREATE TABLE private.mobile_health_risk_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 safety_revision bigint NOT NULL CHECK(safety_revision>0),
 items private.mobile_health_risk_code_v1[] NOT NULL CHECK(cardinality(items)>0),
 declared_at timestamptz NOT NULL CHECK(isfinite(declared_at)
   AND extract(year FROM declared_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 UNIQUE(user_id,operation_key), UNIQUE(user_id,safety_revision),
 CHECK(private.mobile_health_risks_canonical(items))
);
ALTER TABLE private.mobile_health_hold_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_health_risk_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_health_hold_states,private.mobile_health_risk_receipts
 FROM PUBLIC,anon,authenticated,service_role;

-- Durable operation receipts cannot expire like the HTTP idempotency cache.
-- Deletion is allowed only as part of the person's actual hard deletion.
CREATE FUNCTION private.mobile_health_receipt_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'mobile_health_receipt_immutable' USING ERRCODE='55000';
END $$;
CREATE TRIGGER mobile_health_receipt_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_health_risk_receipts FOR EACH ROW EXECUTE FUNCTION private.mobile_health_receipt_immutable();

CREATE FUNCTION private.mobile_health_risk_set(p_items text[])
RETURNS private.mobile_health_risk_code_v1[] LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER
SET search_path=pg_catalog AS $$
DECLARE result private.mobile_health_risk_code_v1[];
BEGIN
 IF p_items IS NULL OR coalesce(array_ndims(p_items),0)<>1 OR array_lower(p_items,1)<>1
   OR cardinality(p_items) NOT BETWEEN 1 AND 8 OR array_position(p_items,NULL) IS NOT NULL
   OR (SELECT count(DISTINCT x) FROM unnest(p_items) x)<>cardinality(p_items) THEN
   RAISE EXCEPTION 'invalid_mobile_health_items' USING ERRCODE='22023';
 END IF;
 SELECT array_agg(x ORDER BY x) INTO result
   FROM unnest(enum_range(NULL::private.mobile_health_risk_code_v1)) x WHERE x::text=ANY(p_items);
 IF cardinality(result) IS DISTINCT FROM cardinality(p_items) THEN
   RAISE EXCEPTION 'invalid_mobile_health_items' USING ERRCODE='22023';
 END IF;
 RETURN result;
END $$;

CREATE FUNCTION private.mobile_health_state_wire(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE state private.mobile_health_hold_states%ROWTYPE; item_dates jsonb;
BEGIN
 SELECT * INTO state FROM private.mobile_health_hold_states WHERE user_id=p_user_id;
 IF NOT FOUND THEN
   IF EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts WHERE user_id=p_user_id) THEN
     RAISE EXCEPTION 'mobile_health_authority_inconsistent' USING ERRCODE='XX001';
   END IF;
   RETURN jsonb_build_object('version',1,'user_id',p_user_id,'safety_revision','0','hold_active',false,
     'declared_no_plan',false,'hide_protein',false,'last_declared_at',NULL,'items','[]'::jsonb);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts WHERE user_id=p_user_id)
   OR (state.hold_active AND NOT EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts r
     WHERE r.user_id=p_user_id AND r.safety_revision=state.safety_revision))
   OR EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts r WHERE r.user_id=p_user_id
     AND r.safety_revision=state.safety_revision AND (NOT state.hold_active
       OR r.declared_at<>state.last_declared_at OR NOT r.items<@state.items))
   OR EXISTS(SELECT 1 FROM unnest(state.items) x WHERE NOT EXISTS(
   SELECT 1 FROM private.mobile_health_risk_receipts r WHERE r.user_id=p_user_id AND x=ANY(r.items)
     AND r.safety_revision<=state.safety_revision AND r.declared_at<=state.last_declared_at))
   OR EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts r WHERE r.user_id=p_user_id
     AND (r.safety_revision>state.safety_revision OR r.declared_at>state.last_declared_at)) THEN
   RAISE EXCEPTION 'mobile_health_authority_inconsistent' USING ERRCODE='XX001';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('code',x,'declared_at',
   to_char((SELECT max(r.declared_at) FROM private.mobile_health_risk_receipts r
     WHERE r.user_id=p_user_id AND x=ANY(r.items)) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')) ORDER BY x),'[]')
 INTO item_dates FROM unnest(state.items) x;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'safety_revision',state.safety_revision::text,
   'hold_active',state.hold_active,'declared_no_plan','pregnant_or_breastfeeding'=ANY(state.items),
   'hide_protein','professional_diet'=ANY(state.items),
   'last_declared_at',to_char(state.last_declared_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'items',item_dates);
END $$;

CREATE FUNCTION private.mobile_health_receipt_wire(p_row private.mobile_health_risk_receipts)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',(p_row).id,'operation_key',(p_row).operation_key,
   'safety_revision',(p_row).safety_revision::text,'items',(p_row).items,
   'declared_at',to_char((p_row).declared_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

-- Explicit clock is private/test-only. Public declaration supplies the real clock AFTER its lock.
CREATE FUNCTION private.declare_mobile_health_risk_at(p_user_id uuid,p_operation_key uuid,
 p_items text[],p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE receipt private.mobile_health_risk_receipts%ROWTYPE; state private.mobile_health_hold_states%ROWTYPE;
 canonical private.mobile_health_risk_code_v1[]; combined private.mobile_health_risk_code_v1[]; next_revision bigint;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 IF p_operation_key IS NULL OR p_observed_at IS NULL OR NOT isfinite(p_observed_at)
   OR extract(year FROM p_observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
   RAISE EXCEPTION 'invalid_mobile_health_input' USING ERRCODE='22023';
 END IF;
 canonical:=private.mobile_health_risk_set(p_items);
 SELECT * INTO receipt FROM private.mobile_health_risk_receipts
   WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
   IF receipt.items<>canonical THEN
     RAISE EXCEPTION 'mobile_health_operation_conflict' USING ERRCODE='40001';
   END IF;
   RETURN jsonb_build_object('version',1,'user_id',p_user_id,'receipt',private.mobile_health_receipt_wire(receipt),
     'state',private.mobile_health_state_wire(p_user_id));
 END IF;
 -- Verify existing authority before extending it; never overwrite an unavailable/corrupt state.
 PERFORM private.mobile_health_state_wire(p_user_id);
 SELECT * INTO state FROM private.mobile_health_hold_states WHERE user_id=p_user_id;
 IF FOUND AND p_observed_at<state.last_declared_at THEN
   RAISE EXCEPTION 'mobile_health_clock_regressed' USING ERRCODE='40001';
 END IF;
 next_revision:=coalesce(state.safety_revision,0)+1;
 SELECT ARRAY(SELECT DISTINCT x FROM unnest(coalesce(state.items,'{}')||canonical) x ORDER BY x) INTO combined;
 INSERT INTO private.mobile_health_risk_receipts(user_id,operation_key,safety_revision,items,declared_at)
   VALUES(p_user_id,p_operation_key,next_revision,canonical,p_observed_at) RETURNING * INTO receipt;
 INSERT INTO private.mobile_health_hold_states(user_id,safety_revision,hold_active,items,last_declared_at)
   VALUES(p_user_id,next_revision,true,combined,p_observed_at)
   ON CONFLICT(user_id) DO UPDATE SET safety_revision=excluded.safety_revision,hold_active=true,
     items=excluded.items,last_declared_at=excluded.last_declared_at;
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'receipt',private.mobile_health_receipt_wire(receipt),
   'state',private.mobile_health_state_wire(p_user_id));
END $$;

CREATE FUNCTION public.get_mobile_health_hold_state(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 RETURN private.mobile_health_state_wire(p_user_id);
END $$;
CREATE FUNCTION public.declare_mobile_health_risk(p_user_id uuid,p_operation_key uuid,p_items text[])
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 RETURN private.declare_mobile_health_risk_at(p_user_id,p_operation_key,p_items,clock_timestamp());
END $$;

REVOKE ALL ON FUNCTION private.mobile_health_risks_canonical(private.mobile_health_risk_code_v1[]),
 private.mobile_health_receipt_immutable(),private.mobile_health_risk_set(text[]),
 private.mobile_health_state_wire(uuid),private.mobile_health_receipt_wire(private.mobile_health_risk_receipts),
 private.declare_mobile_health_risk_at(uuid,uuid,text[],timestamptz),
 public.get_mobile_health_hold_state(uuid),public.declare_mobile_health_risk(uuid,uuid,text[])
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_health_hold_state(uuid),public.declare_mobile_health_risk(uuid,uuid,text[])
 TO service_role;
COMMENT ON TABLE private.mobile_health_hold_states IS
 'Private n10 person HOLD. Reset/cancel/none/opt-out do not clear it. No clinical FULL clear entrypoint yet.';
COMMENT ON TABLE private.mobile_health_risk_receipts IS
 'Durable private operation receipts; no HTTP TTL. Old replay returns original receipt plus current state.';
COMMIT;

-- Durable routing is neither a performed fact nor an effect receipt. Preserve
-- the five v1 RPC DTOs; no route/capability/provider/native activation here.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'intake_routing_requires_postgres' USING ERRCODE='42501';END IF;
 IF to_regclass('private.conversation_intake_routing_leases') IS NOT NULL OR to_regclass('private.conversation_intake_routing_results') IS NOT NULL THEN RAISE EXCEPTION 'intake_routing_unknown_existing_object' USING ERRCODE='42P07';END IF;
 IF to_regprocedure('public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)') IS NULL
 OR to_regprocedure('private.lock_conversation_intake(uuid,uuid,text,uuid)') IS NULL THEN RAISE EXCEPTION 'intake_routing_missing_substrate' USING ERRCODE='42P01';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)'::regprocedure)<>'0a612a59006fb8af88abee14387972fa13fd4dba300a6e5d4a38a552fab821b8' THEN RAISE EXCEPTION 'intake_routing_unknown_seal_body';END IF;
END $preflight$;
CREATE TABLE private.conversation_intake_routing_leases(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,source_hash text COLLATE "C" NOT NULL CHECK(source_hash ~ '^[0-9a-f]{64}$'),claim_id uuid NOT NULL,
 lease_anchor_at timestamptz NOT NULL CHECK(isfinite(lease_anchor_at)),lease_clock_origin text NOT NULL CHECK(lease_clock_origin IN('claim','migration_backfill')),
 PRIMARY KEY(user_id,intake_id),FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_claims ON DELETE CASCADE
);
CREATE TABLE private.conversation_intake_routing_results(
 user_id uuid NOT NULL,intake_id uuid NOT NULL,decision_hash text COLLATE "C" NOT NULL CHECK(decision_hash ~ '^[0-9a-f]{64}$'),decision jsonb NOT NULL CHECK(jsonb_typeof(decision)='object'),
 recorded_at timestamptz NOT NULL CHECK(isfinite(recorded_at)),origin text NOT NULL CHECK(origin IN('router','interrupted','sealed_selection_backfill')),
 PRIMARY KEY(user_id,intake_id),FOREIGN KEY(user_id,intake_id) REFERENCES private.conversation_intake_routing_leases ON DELETE CASCADE
);
ALTER TABLE private.conversation_intake_routing_leases ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_intake_routing_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_intake_routing_leases,private.conversation_intake_routing_results FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER conversation_intake_routing_lease_immutable BEFORE UPDATE ON private.conversation_intake_routing_leases FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE TRIGGER conversation_intake_routing_result_immutable BEFORE UPDATE ON private.conversation_intake_routing_results FOR EACH ROW EXECUTE FUNCTION private.conversation_intake_immutable();
CREATE FUNCTION private.conversation_intake_interrupted_decision() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT '{"schema":"conversation.intake-routing.v1","kind":"clarification_required","reason":"routing_interrupted","question":{"field":"description","text":"Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?"}}'::jsonb;
$$;
CREATE FUNCTION private.assert_conversation_intake_routing_lease() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;s private.conversation_intake_sources%ROWTYPE;claim uuid;captured timestamptz;
BEGIN
 SELECT * INTO STRICT c FROM private.conversation_intake_ids WHERE user_id=NEW.user_id AND intake_id=NEW.intake_id;
 SELECT * INTO STRICT s FROM private.conversation_intake_sources WHERE user_id=NEW.user_id AND intake_id=NEW.intake_id;
 SELECT claim_id INTO STRICT claim FROM private.conversation_intake_claims WHERE user_id=NEW.user_id AND intake_id=NEW.intake_id;
 captured:=(s.context->>'captured_at')::timestamptz;
 IF NEW.claim_id IS DISTINCT FROM claim OR NEW.source_hash IS DISTINCT FROM s.source_hash
 OR s.source_hash IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(s.context),'UTF8')),'hex')
 OR s.context->>'owner_id' IS DISTINCT FROM c.user_id::text OR s.context->>'intake_id' IS DISTINCT FROM c.intake_id::text
 OR s.context->>'input_hash' IS DISTINCT FROM c.input_hash OR s.context->>'epoch' IS DISTINCT FROM c.epoch::text
 OR (s.context->>'admitted_at')::timestamptz IS DISTINCT FROM c.admitted_at
 OR captured IS NULL OR NOT isfinite(captured) OR captured<c.admitted_at
 OR NEW.lease_anchor_at IS NULL OR NOT isfinite(NEW.lease_anchor_at) OR NEW.lease_anchor_at<captured OR NEW.lease_anchor_at>clock_timestamp() THEN
  RAISE EXCEPTION 'invalid_intake_routing_lease' USING ERRCODE='22023';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_intake_routing_lease_binding BEFORE INSERT ON private.conversation_intake_routing_leases FOR EACH ROW EXECUTE FUNCTION private.assert_conversation_intake_routing_lease();
CREATE FUNCTION private.capture_conversation_intake_routing_lease() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 INSERT INTO private.conversation_intake_routing_leases(user_id,intake_id,source_hash,claim_id,lease_anchor_at,lease_clock_origin)
 SELECT NEW.user_id,NEW.intake_id,s.source_hash,NEW.claim_id,clock_timestamp(),'claim' FROM private.conversation_intake_sources s WHERE s.user_id=NEW.user_id AND s.intake_id=NEW.intake_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'intake_routing_source_absent' USING ERRCODE='22023';END IF;RETURN NEW;
END $$;
CREATE TRIGGER conversation_intake_routing_lease_after_claim AFTER INSERT ON private.conversation_intake_claims FOR EACH ROW EXECUTE FUNCTION private.capture_conversation_intake_routing_lease();
CREATE FUNCTION private.assert_conversation_intake_routing_result() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE l private.conversation_intake_routing_leases%ROWTYPE;c private.conversation_intake_ids%ROWTYPE;selected jsonb;
BEGIN
 PERFORM private.assert_conversation_intake_decision(NEW.decision);
 IF NEW.decision_hash IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(NEW.decision),'UTF8')),'hex') OR NEW.recorded_at IS NULL OR NOT isfinite(NEW.recorded_at) OR NEW.recorded_at>clock_timestamp() THEN RAISE EXCEPTION 'invalid_intake_routing_result' USING ERRCODE='22023';END IF;
 SELECT * INTO STRICT l FROM private.conversation_intake_routing_leases WHERE user_id=NEW.user_id AND intake_id=NEW.intake_id;
 SELECT * INTO STRICT c FROM private.conversation_intake_ids WHERE user_id=NEW.user_id AND intake_id=NEW.intake_id;
 IF NEW.origin='sealed_selection_backfill' THEN
  SELECT selection INTO STRICT selected FROM private.conversation_intake_selections WHERE user_id=NEW.user_id AND intake_id=NEW.intake_id;
  IF selected->'intake' IS DISTINCT FROM private.conversation_intake_binding(c) OR selected->>'source_hash' IS DISTINCT FROM l.source_hash
  OR selected->>'decision_hash' IS DISTINCT FROM NEW.decision_hash OR selected->'decision' IS DISTINCT FROM NEW.decision
  OR (selected->>'selected_at')::timestamptz IS DISTINCT FROM NEW.recorded_at OR NEW.recorded_at<c.admitted_at THEN RAISE EXCEPTION 'invalid_intake_routing_backfill' USING ERRCODE='22023';END IF;
 ELSE
  IF NEW.recorded_at<l.lease_anchor_at OR NEW.recorded_at<c.admitted_at THEN RAISE EXCEPTION 'invalid_intake_routing_clock' USING ERRCODE='22023';END IF;
  IF NEW.origin='interrupted' AND (NEW.decision IS DISTINCT FROM private.conversation_intake_interrupted_decision() OR NEW.recorded_at<l.lease_anchor_at+interval '60 seconds') THEN RAISE EXCEPTION 'invalid_intake_routing_interruption' USING ERRCODE='22023';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER conversation_intake_routing_result_binding BEFORE INSERT ON private.conversation_intake_routing_results FOR EACH ROW EXECUTE FUNCTION private.assert_conversation_intake_routing_result();
-- Only metadata is added. The old immutable claim and selection rows, their
-- hashes and clocks stay literal. Unknown old completion times are NOT guessed.
DO $backfill$
DECLARE anchor timestamptz:=clock_timestamp();
BEGIN
 INSERT INTO private.conversation_intake_routing_leases(user_id,intake_id,source_hash,claim_id,lease_anchor_at,lease_clock_origin)
 SELECT c.user_id,c.intake_id,s.source_hash,c.claim_id,anchor,'migration_backfill' FROM private.conversation_intake_claims c JOIN private.conversation_intake_sources s USING(user_id,intake_id);
 INSERT INTO private.conversation_intake_routing_results(user_id,intake_id,decision_hash,decision,recorded_at,origin)
 SELECT s.user_id,s.intake_id,s.decision_hash,s.selection->'decision',(s.selection->>'selected_at')::timestamptz,'sealed_selection_backfill' FROM private.conversation_intake_selections s;
END $backfill$;
CREATE FUNCTION private.conversation_intake_routing_proof(u uuid,i uuid) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('intake',private.conversation_intake_binding(c),'source_hash',l.source_hash,'claim_id',l.claim_id,'lease_anchor_at',private.conversation_intake_clock(l.lease_anchor_at),'lease_clock_origin',l.lease_clock_origin,
 'result',CASE WHEN r.user_id IS NULL THEN NULL ELSE jsonb_build_object('schema','conversation.intake-routing-result.v1','decision_hash',r.decision_hash,'decision',r.decision,'recorded_at',private.conversation_intake_clock(r.recorded_at),'origin',r.origin) END)
 FROM private.conversation_intake_ids c JOIN private.conversation_intake_routing_leases l USING(user_id,intake_id) LEFT JOIN private.conversation_intake_routing_results r USING(user_id,intake_id)
 WHERE c.user_id=u AND c.intake_id=i;
$$;
CREATE FUNCTION private.record_conversation_intake_routing_result(u uuid,i uuid,d jsonb,h text) RETURNS text LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE r private.conversation_intake_routing_results%ROWTYPE;
BEGIN
 PERFORM private.assert_conversation_intake_decision(d);
 IF h IS DISTINCT FROM encode(sha256(convert_to(private.conversation_command_canonical(d),'UTF8')),'hex') THEN RAISE EXCEPTION 'invalid_intake_routing_result_hash' USING ERRCODE='22023';END IF;
 SELECT * INTO r FROM private.conversation_intake_routing_results WHERE user_id=u AND intake_id=i;
 IF FOUND THEN
  IF r.decision_hash IS DISTINCT FROM h OR r.decision IS DISTINCT FROM d THEN RETURN 'decision_conflict';END IF;RETURN 'current';
 END IF;
 INSERT INTO private.conversation_intake_routing_results VALUES(u,i,h,d,clock_timestamp(),'router');RETURN 'current';
END $$;
-- This insertion precedes BOTH fresh-day checks and the inner actual typed
-- admission savepoint. A returned quota/day refusal therefore retains routing.
-- The original identity/source/claim/selection checks remain before this hook.
DO $seal$
DECLARE fn regprocedure:='public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)'::regprocedure;body text;needle text;
BEGIN
 body:=pg_get_functiondef(fn);needle:=$n$ fresh:=private.conversation_intake_context(p_user_id,p_intake_id);IF fresh ? 'action' THEN RETURN fresh;END IF;$n$;
 IF (length(body)-length(replace(body,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'intake_routing_seal_hook_missing';END IF;
 body:=replace(body,needle,$n$ gate:=private.record_conversation_intake_routing_result(p_user_id,p_intake_id,p_decision,h);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
$n$||needle);EXECUTE body;
END $seal$;
CREATE FUNCTION public.read_conversation_intake_routing_result(p_user_id uuid,p_intake_id uuid,p_input_hash text,p_expected_epoch uuid,p_source_hash text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;l private.conversation_intake_routing_leases%ROWTYPE;s private.conversation_intake_sources%ROWTYPE;claim uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM p_expected_epoch
 OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id AND epoch=c.epoch)
 OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active') THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}';END IF;
 SELECT * INTO s FROM private.conversation_intake_sources WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF s.source_hash IS DISTINCT FROM p_source_hash THEN RETURN '{"action":"source_conflict"}';END IF;
 SELECT claim_id INTO claim FROM private.conversation_intake_claims WHERE user_id=p_user_id AND intake_id=p_intake_id;
 SELECT * INTO l FROM private.conversation_intake_routing_leases WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF l.source_hash IS DISTINCT FROM s.source_hash OR l.claim_id IS DISTINCT FROM claim THEN RETURN '{"action":"source_conflict"}';END IF;
 RETURN jsonb_build_object('action','available')||private.conversation_intake_routing_proof(p_user_id,p_intake_id);
END $$;
CREATE FUNCTION public.reconcile_conversation_intake_routing(p_user_id uuid,p_intake_id uuid,p_input_hash text,p_expected_epoch uuid,p_source_hash text,p_claim_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;c private.conversation_intake_ids%ROWTYPE;l private.conversation_intake_routing_leases%ROWTYPE;s private.conversation_intake_sources%ROWTYPE;claim uuid;d jsonb;h text;at timestamptz;selection jsonb;
BEGIN
 gate:=private.lock_conversation_intake(p_user_id,p_intake_id,p_input_hash,p_expected_epoch);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO s FROM private.conversation_intake_sources WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF s.source_hash IS DISTINCT FROM p_source_hash THEN RETURN '{"action":"source_conflict"}';END IF;
 SELECT claim_id INTO claim FROM private.conversation_intake_claims WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF claim IS NULL OR claim IS DISTINCT FROM p_claim_id THEN RETURN '{"action":"claim_conflict"}';END IF;
 SELECT * INTO l FROM private.conversation_intake_routing_leases WHERE user_id=p_user_id AND intake_id=p_intake_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 IF l.source_hash IS DISTINCT FROM s.source_hash OR l.claim_id IS DISTINCT FROM claim THEN RETURN '{"action":"source_conflict"}';END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_intake_routing_results WHERE user_id=p_user_id AND intake_id=p_intake_id) THEN
  RETURN jsonb_build_object('action','replay','result',jsonb_build_object('action','available')||private.conversation_intake_routing_proof(p_user_id,p_intake_id));END IF;
 -- Do not invent a missing result from current typed identities or selections.
 IF EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=p_user_id AND intake_id=p_intake_id) THEN RAISE EXCEPTION 'intake_routing_result_missing' USING ERRCODE='40001';END IF;
 at:=clock_timestamp();IF at<l.lease_anchor_at+interval '60 seconds' THEN RETURN '{"action":"in_flight"}';END IF;
 SELECT * INTO STRICT c FROM private.conversation_intake_ids WHERE user_id=p_user_id AND intake_id=p_intake_id;
 d:=private.conversation_intake_interrupted_decision();h:=encode(sha256(convert_to(private.conversation_command_canonical(d),'UTF8')),'hex');
 INSERT INTO private.conversation_intake_routing_results VALUES(p_user_id,p_intake_id,h,d,at,'interrupted');
 -- Pure terminal interruption has no child/effect and may close an old local
 -- day. It never relaxes seal's day/media/typed quota/current-source guards.
 selection:=jsonb_build_object('schema','conversation.intake-selection.v1','intake',private.conversation_intake_binding(c),'source_hash',s.source_hash,'decision_hash',h,'decision',d,'selected_at',private.conversation_intake_clock(at),'command',NULL);
 INSERT INTO private.conversation_intake_selections VALUES(p_user_id,p_intake_id,h,selection);
 RETURN jsonb_build_object('action','reconciled','result',jsonb_build_object('action','available')||private.conversation_intake_routing_proof(p_user_id,p_intake_id));
END $$;
REVOKE ALL ON FUNCTION private.conversation_intake_interrupted_decision(),private.assert_conversation_intake_routing_lease(),private.capture_conversation_intake_routing_lease(),private.assert_conversation_intake_routing_result(),private.conversation_intake_routing_proof(uuid,uuid),private.record_conversation_intake_routing_result(uuid,uuid,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_conversation_intake_routing_result(uuid,uuid,text,uuid,text),public.reconcile_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_conversation_intake_routing_result(uuid,uuid,text,uuid,text),public.reconcile_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid) TO service_role;
COMMIT;

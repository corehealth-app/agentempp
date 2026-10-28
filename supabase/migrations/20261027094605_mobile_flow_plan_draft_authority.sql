-- Mobile-only draft authority. No route, flag, agent or app activation.
-- Legacy RPCs and mutable patient edits remain unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)') IS NULL
  OR to_regprocedure('public.create_plan_draft_atomic(uuid,text,text,text,jsonb,jsonb,jsonb,jsonb,uuid,uuid,jsonb,text)') IS NULL THEN
  RAISE EXCEPTION 'mobile_flow_draft_requires_clinical_authority' USING ERRCODE='42501';END IF;
END $$;

-- Only changes to targets/identity increment this latch. Intake/workout/XP
-- aggregation must not invalidate a generation. No inferred historical backfill.
CREATE TABLE private.mobile_flow_plan_day_revisions(
 snapshot_id uuid PRIMARY KEY REFERENCES public.daily_snapshots(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 revision bigint NOT NULL CHECK(revision>0)
);
ALTER TABLE private.mobile_flow_plan_day_revisions ENABLE ROW LEVEL SECURITY;
CREATE INDEX mobile_flow_plan_day_revision_owner ON private.mobile_flow_plan_day_revisions(user_id);
REVOKE ALL ON private.mobile_flow_plan_day_revisions FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.advance_mobile_flow_plan_day_revision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF ROW(OLD.id,OLD.user_id,OLD.date,OLD.calories_target,OLD.protein_target,OLD.current_protocol)
  IS DISTINCT FROM ROW(NEW.id,NEW.user_id,NEW.date,NEW.calories_target,NEW.protein_target,NEW.current_protocol) THEN
  INSERT INTO private.mobile_flow_plan_day_revisions(snapshot_id,user_id,revision) VALUES(NEW.id,NEW.user_id,1)
  ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,
   revision=private.mobile_flow_plan_day_revisions.revision+1;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_flow_plan_day_revision AFTER UPDATE ON public.daily_snapshots
 FOR EACH ROW EXECUTE FUNCTION private.advance_mobile_flow_plan_day_revision();

CREATE TABLE private.mobile_flow_plan_draft_origins(
 draft_id uuid PRIMARY KEY REFERENCES public.plan_drafts(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 request_key text NOT NULL,
 source_message_id uuid NOT NULL,
 binding jsonb NOT NULL CHECK(jsonb_typeof(binding)='object'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(user_id,request_key)
);
ALTER TABLE private.mobile_flow_plan_draft_origins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_flow_plan_draft_origins FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.mobile_flow_plan_draft_origin_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 -- Preserve normal draft/reset/account cascade deletion; never erase the
 -- origin of a surviving draft in order to relabel it with a new context.
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.plan_drafts WHERE id=OLD.draft_id)
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'mobile_flow_draft_origin_immutable' USING ERRCODE='55000';
END $$;
CREATE TRIGGER mobile_flow_plan_draft_origin_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_flow_plan_draft_origins FOR EACH ROW EXECUTE FUNCTION private.mobile_flow_plan_draft_origin_immutable();

CREATE FUNCTION private.capture_mobile_flow_plan_context_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE state jsonb;day public.daily_snapshots%ROWTYPE;day_wire jsonb;revision bigint;
 age integer;height numeric;weight numeric;fat numeric;no_plan boolean;loss_guard boolean;training boolean;nutrition boolean;
BEGIN
 PERFORM private.assert_trusted_backend();
 state:=private.capture_mobile_current_clinical_state_at(p_user_id,'profile',NULL,NULL,p_observed_at);
 BEGIN
  SELECT * INTO day FROM public.daily_snapshots WHERE user_id=p_user_id AND date=(state->>'date')::date FOR SHARE NOWAIT;
  IF FOUND THEN
   SELECT r.revision INTO revision FROM private.mobile_flow_plan_day_revisions r WHERE r.snapshot_id=day.id AND r.user_id=p_user_id;
   day_wire:=jsonb_build_object('snapshot_id',day.id,'date',day.date,'calories_target',day.calories_target,
    'protein_target',day.protein_target,'current_protocol',day.current_protocol,'target_revision',coalesce(revision,0)::text,
    'calorie_origin',private.mobile_clinical_target_origin(p_user_id,(state->>'signup_generation')::uuid,
     (state->>'epoch')::uuid,day.date,(state->>'observed_at')::timestamptz));
  END IF;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'mobile_flow_draft_busy' USING ERRCODE='55P03';END;
 -- Same approved display/guidance rules as evaluateReevaluationSafety,
 -- including known guards when some unrelated assessment field is missing.
 IF state#>>'{body,birth_date}' IS NOT NULL THEN
  age:=extract(year FROM (state->>'date')::date)::integer-extract(year FROM (state#>>'{body,birth_date}')::date)::integer
   -CASE WHEN to_char((state->>'date')::date,'MM-DD')<to_char((state#>>'{body,birth_date}')::date,'MM-DD') THEN 1 ELSE 0 END;
 END IF;
 height:=(state#>>'{body,height_cm}')::numeric;weight:=(state#>>'{body,weight_kg}')::numeric;fat:=(state#>>'{body,body_fat_percent}')::numeric;
 no_plan:=coalesce(age<18,false) OR (state#>>'{health_state,declared_no_plan}')::boolean;
 loss_guard:=coalesce(age>=18 AND weight*10000<18.5*height*height,false) OR coalesce(fat<=10,false);
 training:=state#>>'{phase_origin,kind}' NOT IN('confirmed_no_plan','not_completed') AND NOT no_plan;
 nutrition:=training AND NOT loss_guard AND NOT (state#>>'{health_state,hold_active}')::boolean
  AND NOT (state#>>'{health_state,hide_protein}')::boolean
  AND coalesce(day.calories_target>0 AND day.protein_target>0,false);
 RETURN jsonb_build_object('version',1,'state',state,'day',day_wire,
  'allowed',jsonb_build_object('training',training,'nutrition',nutrition));
END $$;

CREATE FUNCTION private.mobile_flow_plan_context_binding(p_context jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',p_context->'version','state',
  ((p_context->'state')-ARRAY['observed_at','context_hash'])#-'{safety,observed_at}',
  'day',p_context->'day','allowed',p_context->'allowed')
$$;
CREATE FUNCTION private.assert_mobile_flow_plan_context(p_user_id uuid,p_domain text,p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE actual jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_domain IS NULL OR p_domain NOT IN('training','nutrition')
  OR jsonb_typeof(p_expected) IS DISTINCT FROM 'object' OR p_expected->'version' IS DISTINCT FROM '1'::jsonb
  OR NOT(p_expected ?& ARRAY['version','state','day','allowed'])
  OR p_expected-ARRAY['version','state','day','allowed']<>'{}'::jsonb
  OR jsonb_typeof(p_expected->'state') IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_expected#>'{state,observed_at}') IS DISTINCT FROM 'string' THEN
  RAISE EXCEPTION 'invalid_mobile_flow_draft_context' USING ERRCODE='22023';END IF;
 actual:=private.capture_mobile_flow_plan_context_at(p_user_id,NULL);
 IF private.mobile_flow_plan_context_binding(actual) IS DISTINCT FROM private.mobile_flow_plan_context_binding(p_expected)
  OR (p_expected#>>'{state,observed_at}')::timestamptz>(actual#>>'{state,observed_at}')::timestamptz THEN
  RAISE EXCEPTION 'mobile_current_clinical_changed' USING ERRCODE='40001';END IF;
 IF actual#>ARRAY['allowed',p_domain] IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'mobile_flow_draft_guidance_unavailable' USING ERRCODE='23514';END IF;
 RETURN actual;
END $$;

CREATE FUNCTION private.assert_mobile_flow_draft_turn(p_user_id uuid,p_domain text,p_request_key text,p_source_message_id uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM 1 FROM public.messages WHERE id=p_source_message_id AND user_id=p_user_id
  AND direction='in' AND role='user' AND provider='mobile_flow'
  AND provider_message_id||CASE WHEN p_domain='training' THEN ':propoe_plano_treino' ELSE ':propoe_plano_dieta' END=p_request_key
  FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_flow_draft_turn_not_found' USING ERRCODE='P0002';END IF;
END $$;
CREATE FUNCTION public.get_mobile_flow_plan_context(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_flow_plan_context_at(p_user_id,NULL);
END $$;
CREATE FUNCTION public.lookup_mobile_flow_plan_draft(p_user_id uuid,p_domain text,p_request_key text,
 p_source_message_id uuid,p_expected jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actual jsonb;draft public.plan_drafts%ROWTYPE;origin private.mobile_flow_plan_draft_origins%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 -- Legacy writers acquire this advisory lock before their FK locks. Never
 -- wait for it while holding the new owner lock: refuse busy to avoid a cycle.
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':plan-drafts',0)) THEN
  RAISE EXCEPTION 'mobile_flow_draft_busy' USING ERRCODE='55P03';END IF;
 actual:=private.assert_mobile_flow_plan_context(p_user_id,p_domain,p_expected);
 PERFORM private.assert_mobile_flow_draft_turn(p_user_id,p_domain,p_request_key,p_source_message_id);
 SELECT * INTO draft FROM public.plan_drafts WHERE user_id=p_user_id AND request_key=p_request_key FOR SHARE NOWAIT;
 IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT * INTO origin FROM private.mobile_flow_plan_draft_origins WHERE user_id=p_user_id AND draft_id=draft.id;
 IF NOT FOUND OR draft.domain<>p_domain OR draft.origin<>'flow_generated'
  OR draft.source_message_id IS DISTINCT FROM p_source_message_id OR origin.source_message_id<>p_source_message_id
  OR origin.binding<>private.mobile_flow_plan_context_binding(actual) THEN
  RAISE EXCEPTION 'mobile_current_clinical_changed' USING ERRCODE='40001';END IF;
 -- Current edited payload/status, not a fabricated immutable creation ACK.
 RETURN private.plan_draft_dto(draft)||jsonb_build_object('payload',draft.payload);
END $$;
CREATE FUNCTION public.create_mobile_flow_plan_draft(p_user_id uuid,p_domain text,p_request_key text,
 p_source_message_id uuid,p_expected jsonb,p_status text,p_payload jsonb,p_uncertain_fields jsonb,p_origin_detail jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actual jsonb;existing jsonb;result jsonb;draft public.plan_drafts%ROWTYPE;
BEGIN
 PERFORM private.assert_trusted_backend();
 existing:=public.lookup_mobile_flow_plan_draft(p_user_id,p_domain,p_request_key,p_source_message_id,p_expected);
 IF existing IS NOT NULL THEN RETURN existing||jsonb_build_object('inserted',false);END IF;
 -- lookup holds the owner/profile/config/day/turn and advisory locks until
 -- this same transaction commits; no revalidation-to-INSERT race remains.
 actual:=p_expected;
 IF p_status IS NULL OR p_status NOT IN('needs_completion','ready_for_review')
  OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'invalid_mobile_flow_draft_payload' USING ERRCODE='22023';END IF;
 IF p_domain='nutrition' AND (jsonb_typeof(p_payload->'meta_kcal') IS DISTINCT FROM 'number'
  OR jsonb_typeof(p_payload->'meta_protein_g') IS DISTINCT FROM 'number'
  OR p_payload->'meta_kcal' IS DISTINCT FROM actual#>'{day,calories_target}'
  OR p_payload->'meta_protein_g' IS DISTINCT FROM actual#>'{day,protein_target}') THEN
  RAISE EXCEPTION 'mobile_flow_draft_targets_changed' USING ERRCODE='23514';END IF;
 result:=public.create_plan_draft_atomic(p_user_id,p_domain,'flow_generated',p_status,p_payload,NULL,
  p_uncertain_fields,'[]'::jsonb,NULL,p_source_message_id,p_origin_detail,p_request_key);
 IF result->'inserted' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'mobile_flow_draft_unproven_replay' USING ERRCODE='40001';END IF;
 SELECT * INTO STRICT draft FROM public.plan_drafts WHERE user_id=p_user_id AND id=(result->>'id')::uuid;
 INSERT INTO private.mobile_flow_plan_draft_origins(draft_id,user_id,request_key,source_message_id,binding)
 VALUES(draft.id,p_user_id,p_request_key,p_source_message_id,private.mobile_flow_plan_context_binding(actual));
 RETURN result||jsonb_build_object('payload',draft.payload);
END $$;

REVOKE ALL ON FUNCTION private.advance_mobile_flow_plan_day_revision(),private.mobile_flow_plan_draft_origin_immutable(),
 private.capture_mobile_flow_plan_context_at(uuid,timestamptz),private.mobile_flow_plan_context_binding(jsonb),
 private.assert_mobile_flow_plan_context(uuid,text,jsonb),private.assert_mobile_flow_draft_turn(uuid,text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_mobile_flow_plan_context(uuid),public.lookup_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb),
 public.create_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb,text,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_mobile_flow_plan_context(uuid),public.lookup_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb),
 public.create_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb,text,jsonb,jsonb,jsonb) TO service_role;
COMMIT;

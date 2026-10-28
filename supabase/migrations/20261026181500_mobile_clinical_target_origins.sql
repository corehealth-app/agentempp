-- Dormant n41 evidence for NEW, actually applied clinical FULL targets.
-- No backfill or claim about historical typed-BF use. Unknown stays unknown.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_full_commands') IS NULL THEN
  RAISE EXCEPTION 'mobile_target_origin_requires_clinical_authority' USING ERRCODE='42501';
 END IF;
END $$;
CREATE TABLE private.mobile_clinical_target_origins (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 origin_id uuid NOT NULL DEFAULT gen_random_uuid(),
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 snapshot_id uuid NOT NULL,
 date date NOT NULL CHECK(isfinite(date)),
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 calories_target integer NOT NULL CHECK(calories_target>0),
 protein_target numeric(6,2) CHECK(protein_target>=0),
 formula_target integer NOT NULL CHECK(formula_target>0),
 review_id uuid NOT NULL,
 context_hash text NOT NULL CHECK(context_hash ~ '^[0-9a-f]{64}$'),
 recorded_at timestamptz NOT NULL CHECK(isfinite(recorded_at)),
 PRIMARY KEY(user_id,origin_id),
 UNIQUE(user_id,review_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id)
  DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE private.mobile_clinical_target_origin_heads (
 snapshot_id uuid PRIMARY KEY REFERENCES public.daily_snapshots(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 origin_id uuid NOT NULL,
 FOREIGN KEY(user_id,origin_id) REFERENCES private.mobile_clinical_target_origins(user_id,origin_id)
);
ALTER TABLE private.mobile_clinical_target_origins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_target_origin_heads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_target_origins,private.mobile_clinical_target_origin_heads
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_target_origin_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_target_origins FOR EACH ROW
 EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

-- Calorie provenance is independent of the observed protein value. A change
-- to actual calories/phase invalidates the pointer; n11 protein-only changes
-- do not create or erase the calorie origin.
-- Restoring equal old numbers later must not revive old provenance. Meal,
-- workout, XP, closure and other aggregate-only writes preserve the pointer.
CREATE FUNCTION private.invalidate_mobile_clinical_target_origin() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF ROW(OLD.id,OLD.user_id,OLD.date,OLD.calories_target,OLD.current_protocol)
  IS DISTINCT FROM ROW(NEW.id,NEW.user_id,NEW.date,NEW.calories_target,NEW.current_protocol) THEN
  DELETE FROM private.mobile_clinical_target_origin_heads WHERE snapshot_id=OLD.id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_target_origin_invalidate AFTER UPDATE
 ON public.daily_snapshots FOR EACH ROW EXECUTE FUNCTION private.invalidate_mobile_clinical_target_origin();

-- Runs only on an INSERT of immutable FULL evidence, after the actual UPDATE.
-- Neither a preview, a numerical candidate nor a replay can call this path.
-- A day_event alone is insufficient. Require the exact open row and the
-- actual target write's server timestamp, including a newly materialized day.
CREATE FUNCTION private.record_mobile_clinical_full_target_origin() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE applied public.daily_snapshots%ROWTYPE;origin uuid;
BEGIN
 IF NEW.rule_version<>'clinical-v1' OR NEW.proposal#>>'{targets,formulaAfterKcal}' IS NULL
  OR NEW.proposal#>>'{targets,afterKcal}' IS NULL OR NEW.principal='schedule_pause'
  OR coalesce(NEW.proposal#>>'{episode,schedule,state}'='suspended',false) THEN RETURN NEW; END IF;
 -- Formula availability is not proof that it determined the calorie target.
 -- Maintenance/gain with an unknown ledger may keep old calories while
 -- recalculating protein. Never relabel that fallback as a new calorie origin.
 IF NEW.proposal#>>'{profile,current_protocol}' IN('manutencao','ganho_massa')
  AND NEW.proposal#>'{episode,ledgerSteps}'='null'::jsonb
  AND NEW.proposal#>'{episode,schedule}'='null'::jsonb
  AND NOT(NEW.principal='neutral_exit'
   AND NEW.proposal#>'{targets,afterKcal}'=NEW.proposal#>'{targets,formulaAfterKcal}') THEN RETURN NEW; END IF;
 SELECT d.* INTO applied FROM public.daily_snapshots d
  JOIN private.mobile_clinical_day_events e ON e.user_id=d.user_id AND e.date=d.date
  WHERE e.user_id=NEW.user_id AND e.review_id=NEW.review_id AND e.date=NEW.calculation_date
   AND e.applied_at=NEW.completed_at AND d.updated_at=NEW.completed_at AND NOT d.day_closed
   AND e.calories_target=(NEW.proposal#>>'{targets,afterKcal}')::integer
   AND e.protein_target IS NOT DISTINCT FROM (NEW.proposal#>>'{targets,afterProtein}')::numeric
   AND e.formula_target=(NEW.proposal#>>'{targets,formulaAfterKcal}')::integer
   AND e.phase=NEW.proposal#>>'{profile,current_protocol}'
   AND d.current_protocol::text=e.phase AND d.calories_target=e.calories_target
   AND d.protein_target IS NOT DISTINCT FROM e.protein_target;
 IF NOT FOUND THEN RETURN NEW; END IF;
 INSERT INTO private.mobile_clinical_target_origins(user_id,signup_generation,signup_epoch,snapshot_id,date,
  phase,calories_target,protein_target,formula_target,review_id,context_hash,recorded_at)
 VALUES(NEW.user_id,NEW.signup_generation,NEW.signup_epoch,applied.id,applied.date,
  applied.current_protocol::text,applied.calories_target,applied.protein_target,
  (NEW.proposal#>>'{targets,formulaAfterKcal}')::integer,NEW.review_id,NEW.context_hash,NEW.completed_at)
 RETURNING origin_id INTO origin;
 INSERT INTO private.mobile_clinical_target_origin_heads VALUES(applied.id,NEW.user_id,origin)
  ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,origin_id=excluded.origin_id;
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_full_target_origin AFTER INSERT
 ON private.mobile_clinical_full_receipts FOR EACH ROW
 EXECUTE FUNCTION private.record_mobile_clinical_full_target_origin();

CREATE FUNCTION private.mobile_clinical_target_origin(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_date date,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE evidence private.mobile_clinical_target_origins%ROWTYPE;day public.daily_snapshots%ROWTYPE;
BEGIN
 SELECT d.* INTO day FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=p_date;
 SELECT e.* INTO evidence FROM private.mobile_clinical_target_origin_heads h
  JOIN private.mobile_clinical_target_origins e ON e.user_id=h.user_id AND e.origin_id=h.origin_id
  WHERE h.snapshot_id=day.id AND h.user_id=p_user_id;
 IF NOT FOUND OR evidence.signup_generation IS DISTINCT FROM p_generation
  OR evidence.signup_epoch IS DISTINCT FROM p_epoch OR evidence.recorded_at>p_observed_at THEN RETURN NULL; END IF;
 IF ROW(evidence.snapshot_id,evidence.user_id,evidence.date,evidence.phase,evidence.calories_target)
  IS DISTINCT FROM ROW(day.id,day.user_id,day.date,day.current_protocol::text,day.calories_target) THEN
  RAISE EXCEPTION 'mobile_clinical_target_origin_inconsistent' USING ERRCODE='XX001';
 END IF;
 RETURN private.mobile_clinical_canonical_row(to_jsonb(evidence),ARRAY['recorded_at'],ARRAY[]::text[])
  ||jsonb_build_object('version',1,'source','clinical_full_v1','target_component','calories');
END $$;
REVOKE ALL ON FUNCTION private.invalidate_mobile_clinical_target_origin(),
 private.record_mobile_clinical_full_target_origin(),private.mobile_clinical_target_origin(uuid,uuid,uuid,date,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
-- protocol_authority is extended below. This source is never a public DTO.
CREATE OR REPLACE FUNCTION private.mobile_clinical_protocol_authority(p_user_id uuid,p_generation uuid,p_epoch uuid,p_cycle_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE origin jsonb; candidate jsonb; episode jsonb; prior_regular jsonb; body_origin jsonb;
 day_events jsonb; routine_events jsonb;
BEGIN
 SELECT private.mobile_clinical_canonical_row(to_jsonb(o),ARRAY['started_at','captured_at'],ARRAY[]::text[])
  INTO origin FROM private.mobile_clinical_signup_origins o
  WHERE o.user_id=p_user_id AND o.signup_generation=p_generation AND o.signup_epoch=p_epoch;
 IF p_cycle_id IS NOT NULL AND EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles
  WHERE user_id=p_user_id AND cycle_id=p_cycle_id AND kind='REGULAR' AND status IN('open','collecting','review_ready')) THEN
  candidate:=private.mobile_clinical_body_fat_candidate_at(p_user_id,p_cycle_id,p_observed_at);
 END IF;
 SELECT private.mobile_clinical_canonical_row(to_jsonb(e),ARRAY['applied_at'],ARRAY['event_no','difficulty_count'])
  INTO episode FROM private.mobile_clinical_effective_episode(p_user_id,p_generation,p_epoch) e WHERE e.event_id IS NOT NULL;
 SELECT coalesce(jsonb_agg(jsonb_build_object('review_id',q.review_id,'kind',q.kind,'date',q.calculation_date,
  'review_no',q.review_no::text,'form',q.form,'principal',q.principal,
  'activity_level_changed',q.activity_level_changed) ORDER BY q.review_no),'[]') INTO prior_regular
  FROM(SELECT * FROM private.mobile_clinical_full_receipts r WHERE r.user_id=p_user_id
   AND r.signup_generation=p_generation AND r.signup_epoch=p_epoch AND r.kind='REGULAR' ORDER BY r.review_no DESC LIMIT 2)q;
 SELECT private.mobile_clinical_canonical_row(to_jsonb(b),ARRAY['confirmed_at'],ARRAY[]::text[]) INTO body_origin
  FROM private.mobile_clinical_body_fat_heads h JOIN private.mobile_clinical_body_fat_receipts b
   ON b.user_id=h.user_id AND b.review_id=h.review_id JOIN public.user_profiles p ON p.user_id=b.user_id
  WHERE b.user_id=p_user_id AND b.signup_generation=p_generation AND b.signup_epoch=p_epoch
   AND p.body_fat_percent=b.mean_percent AND p.body_fat_measured_at=b.confirmed_at;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(e),ARRAY['applied_at'],ARRAY[]::text[]) ORDER BY r.review_no),'[]')
  INTO day_events FROM private.mobile_clinical_day_events e JOIN private.mobile_clinical_full_receipts r
   ON r.user_id=e.user_id AND r.review_id=e.review_id JOIN public.users u ON u.id=e.user_id
  WHERE e.user_id=p_user_id AND e.date=(p_observed_at AT TIME ZONE u.timezone)::date
   AND r.signup_generation=p_generation AND r.signup_epoch=p_epoch;
 SELECT coalesce(jsonb_agg(jsonb_build_object('review_id',r.review_id,'principal',r.principal,
  'base_before',r.base_before,'date',r.calculation_date,'review_no',r.review_no::text,
  'activity_level_changed',r.activity_level_changed) ORDER BY r.review_no),'[]') INTO routine_events
  FROM private.mobile_clinical_full_receipts r WHERE r.user_id=p_user_id AND r.signup_generation=p_generation
   AND r.signup_epoch=p_epoch AND r.kind='ROUTINE_REVIEW' AND r.review_no>coalesce((
    SELECT max(f.review_no) FROM private.mobile_clinical_full_receipts f WHERE f.user_id=p_user_id
     AND f.signup_generation=p_generation AND f.signup_epoch=p_epoch AND f.kind='REGULAR'),0);
 RETURN jsonb_build_object('signup_origin',coalesce(origin,'null'::jsonb),
  'phase_origin',CASE WHEN (SELECT current_protocol IS NOT NULL FROM public.user_profiles WHERE user_id=p_user_id)
   THEN jsonb_build_object('kind','assigned') ELSE coalesce(
    private.mobile_clinical_signup_no_plan_origin(p_user_id,p_generation,p_epoch),jsonb_build_object('kind','legacy_unassigned')) END,
  'body_fat_candidate',coalesce(candidate,'null'::jsonb),
  'episode',coalesce(episode,'null'::jsonb),'prior_regular_reviews',prior_regular,
  'body_fat_origin',coalesce(body_origin,'null'::jsonb),
  'signup_body_fat_origin',private.mobile_clinical_signup_photo_origin(p_user_id,p_generation,p_epoch),
  'day_events',day_events,'routine_reviews_since_regular',routine_events,
  'preference',private.mobile_clinical_preference_current(p_user_id,p_generation,p_epoch),
  'daily_application',private.mobile_clinical_daily_authority(p_user_id,p_generation,p_epoch),
  'target_origin',private.mobile_clinical_target_origin(p_user_id,p_generation,p_epoch,
   (p_observed_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date,p_observed_at));
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_protocol_authority(uuid,uuid,uuid,uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

-- Dormant prospective calculation authority. Confirmed decision != applied
-- target. No backfill, public grant, model/client calculation or activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_target_origins') IS NULL THEN
  RAISE EXCEPTION 'calorie_decisions_require_applied_origin' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION private.mobile_clinical_has_calorie_calculation(p jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT coalesce(p#>>'{targets,formulaAfterKcal}' IS NOT NULL AND p#>>'{targets,afterKcal}' IS NOT NULL
  AND p->>'principal'<>'schedule_pause' AND coalesce(p#>>'{episode,schedule,state}','')<>'suspended'
  AND NOT(p#>>'{profile,current_protocol}' IN('manutencao','ganho_massa')
   AND p#>'{episode,ledgerSteps}'='null'::jsonb AND p#>'{episode,schedule}'='null'::jsonb
   AND NOT(p->>'principal'='neutral_exit' AND p#>'{targets,afterKcal}'=p#>'{targets,formulaAfterKcal}')),false)
$$;
CREATE TABLE private.mobile_clinical_calorie_decisions (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 source_episode_event_id uuid NOT NULL,
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 decision_kind text NOT NULL CHECK(decision_kind IN('calculated','preserved_known')),
 parent_origin_id uuid,
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 calories_target integer NOT NULL CHECK(calories_target>0),
 formula_target integer NOT NULL CHECK(formula_target>0),
 decision_date date NOT NULL CHECK(isfinite(decision_date)),
 decided_at timestamptz NOT NULL CHECK(isfinite(decided_at)),
 command_hash text NOT NULL CHECK(command_hash ~ '^[a-f0-9]{64}$'),
 context_hash text NOT NULL CHECK(context_hash ~ '^[a-f0-9]{64}$'),
 PRIMARY KEY(user_id,review_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,source_episode_event_id) REFERENCES private.mobile_clinical_episode_events(user_id,event_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,parent_origin_id) REFERENCES private.mobile_clinical_target_origins(user_id,origin_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK(decision_kind<>'preserved_known' OR parent_origin_id IS NOT NULL)
);
ALTER TABLE private.mobile_clinical_calorie_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_calorie_decisions FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_calorie_decision_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_calorie_decisions FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

ALTER TABLE private.mobile_clinical_target_origins
 ALTER COLUMN review_id DROP NOT NULL,
 ADD COLUMN application_id uuid,
 ADD COLUMN origin_kind text NOT NULL DEFAULT 'calculated' CHECK(origin_kind IN('calculated','confirmed','carried')),
 ADD COLUMN deficit_level integer CHECK(deficit_level IN(400,500,600)),
 ADD COLUMN parent_origin_id uuid,
 ADD COLUMN decision_review_id uuid,
 ADD UNIQUE(user_id,application_id),
 ADD FOREIGN KEY(user_id,application_id) REFERENCES private.mobile_clinical_daily_applications(user_id,application_id) DEFERRABLE INITIALLY DEFERRED,
 ADD FOREIGN KEY(user_id,parent_origin_id) REFERENCES private.mobile_clinical_target_origins(user_id,origin_id) DEFERRABLE INITIALLY DEFERRED,
 ADD FOREIGN KEY(user_id,decision_review_id) REFERENCES private.mobile_clinical_calorie_decisions(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 ADD CHECK(num_nonnulls(review_id,application_id)=1);

CREATE FUNCTION private.record_mobile_clinical_calorie_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE c private.mobile_clinical_full_commands%ROWTYPE;p private.mobile_clinical_previews%ROWTYPE;
 origin jsonb;event uuid;kind text;formula integer;
BEGIN
 IF NEW.proposal#>>'{targets,afterKcal}' IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO c FROM private.mobile_clinical_full_commands WHERE user_id=NEW.user_id AND preview_id=NEW.preview_id;
 IF NOT FOUND THEN RETURN NEW; END IF; -- old/private receipts are not reconstructed as commands
 SELECT * INTO STRICT p FROM private.mobile_clinical_previews WHERE user_id=NEW.user_id AND preview_id=NEW.preview_id;
 PERFORM private.mobile_clinical_full_command_wire(p,c);
 IF c.prepared_package IS DISTINCT FROM jsonb_build_object('form',NEW.form,'intent',NEW.intent,'proposal',NEW.proposal)
  OR p.context_hash<>NEW.context_hash OR p.signup_generation<>NEW.signup_generation OR p.signup_epoch<>NEW.signup_epoch THEN
  RAISE EXCEPTION 'clinical_calorie_decision_command_changed' USING ERRCODE='XX001'; END IF;
 SELECT event_id INTO event FROM private.mobile_clinical_episode_events WHERE user_id=NEW.user_id AND review_id=NEW.review_id;
 IF event IS NULL THEN RETURN NEW; END IF;
 -- Runs alphabetically BEFORE the new FULL origin trigger. Calorie/phase
 -- changes already invalidate an old head; unchanged known calories keep it.
 origin:=private.mobile_clinical_target_origin(NEW.user_id,NEW.signup_generation,NEW.signup_epoch,NEW.calculation_date,NEW.completed_at);
 IF private.mobile_clinical_has_calorie_calculation(NEW.proposal) THEN
  kind:='calculated';formula:=(NEW.proposal#>>'{targets,formulaAfterKcal}')::integer;
 ELSIF origin IS NOT NULL
  AND NEW.proposal#>'{targets,afterKcal}'=NEW.proposal#>'{targets,beforeKcal}'
  AND NEW.proposal#>>'{profile,current_protocol}'=NEW.form->>'phase'
  AND (origin->>'calories_target')::integer=(NEW.proposal#>>'{targets,beforeKcal}')::integer
  AND origin->>'phase'=NEW.proposal#>>'{profile,current_protocol}' THEN
  kind:='preserved_known';formula:=(origin->>'formula_target')::integer;
 ELSE RETURN NEW; END IF;
 INSERT INTO private.mobile_clinical_calorie_decisions(user_id,review_id,source_episode_event_id,signup_generation,signup_epoch,
  decision_kind,parent_origin_id,phase,calories_target,formula_target,decision_date,decided_at,command_hash,context_hash)
 VALUES(NEW.user_id,NEW.review_id,event,NEW.signup_generation,NEW.signup_epoch,kind,(origin->>'origin_id')::uuid,
  NEW.proposal#>>'{profile,current_protocol}',(NEW.proposal#>>'{targets,afterKcal}')::integer,formula,
  NEW.calculation_date,NEW.completed_at,c.command_hash,NEW.context_hash);
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_calorie_decision AFTER INSERT ON private.mobile_clinical_full_receipts
 FOR EACH ROW EXECUTE FUNCTION private.record_mobile_clinical_calorie_decision();

CREATE FUNCTION private.mobile_clinical_confirmed_calorie_decision(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_date date,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE d private.mobile_clinical_calorie_decisions%ROWTYPE;e private.mobile_clinical_episode_events%ROWTYPE;
 c private.mobile_clinical_full_commands%ROWTYPE;p private.mobile_clinical_previews%ROWTYPE;
BEGIN
 e:=private.mobile_clinical_effective_episode(p_user_id,p_generation,p_epoch);
 IF e.event_id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO d FROM private.mobile_clinical_calorie_decisions WHERE user_id=p_user_id AND review_id=e.review_id
  AND source_episode_event_id=e.event_id AND signup_generation=p_generation AND signup_epoch=p_epoch;
 IF NOT FOUND OR d.decided_at>p_observed_at
  OR (d.decided_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date>p_date THEN RETURN NULL; END IF;
 SELECT * INTO STRICT c FROM private.mobile_clinical_full_commands WHERE user_id=p_user_id AND preview_id=d.review_id;
 SELECT * INTO STRICT p FROM private.mobile_clinical_previews WHERE user_id=p_user_id AND preview_id=d.review_id;
 PERFORM private.mobile_clinical_full_command_wire(p,c);
 IF c.command_hash<>d.command_hash OR p.context_hash<>d.context_hash THEN
  RAISE EXCEPTION 'clinical_calorie_decision_inconsistent' USING ERRCODE='XX001'; END IF;
 RETURN jsonb_build_object('version',1,'source','confirmed_full_calculation_v1','user_id',p_user_id,
  'signup_generation',p_generation,'signup_epoch',p_epoch,'review_id',d.review_id,'source_episode_event_id',e.event_id,
  'phase',e.phase,'decision_kind',d.decision_kind,'calories_target',d.calories_target,'formula_target',d.formula_target,
  'decision_date',d.decision_date,
  'valid_from_date',(d.decided_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date,
  'decided_at',to_char(d.decided_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'command_hash',d.command_hash,'context_hash',d.context_hash);
END $$;

REVOKE ALL ON FUNCTION private.mobile_clinical_has_calorie_calculation(jsonb),private.record_mobile_clinical_calorie_decision(),
 private.mobile_clinical_confirmed_calorie_decision(uuid,uuid,uuid,date,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
-- Applied origin/decision captures and daily writer extensions follow below.
CREATE FUNCTION private.mobile_clinical_calorie_basis(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_kind text,p_reference uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE o private.mobile_clinical_target_origins%ROWTYPE;d private.mobile_clinical_calorie_decisions%ROWTYPE;
BEGIN
 IF p_kind='application' THEN
  SELECT * INTO o FROM private.mobile_clinical_target_origins WHERE user_id=p_user_id AND application_id=p_reference
   AND signup_generation=p_generation AND signup_epoch=p_epoch;
 ELSIF p_kind IN('full_after','full_before') THEN
  SELECT * INTO d FROM private.mobile_clinical_calorie_decisions WHERE user_id=p_user_id AND review_id=p_reference
   AND signup_generation=p_generation AND signup_epoch=p_epoch;
  IF p_kind='full_before' THEN
   SELECT * INTO o FROM private.mobile_clinical_target_origins WHERE user_id=p_user_id AND origin_id=d.parent_origin_id
    AND signup_generation=p_generation AND signup_epoch=p_epoch;
  ELSIF d.review_id IS NOT NULL THEN
   RETURN jsonb_build_object('basis_type','decision','review_id',d.review_id,'phase',d.phase,
    'calories_target',d.calories_target,'formula_target',d.formula_target);
  ELSE
   SELECT * INTO o FROM private.mobile_clinical_target_origins WHERE user_id=p_user_id AND review_id=p_reference
    AND signup_generation=p_generation AND signup_epoch=p_epoch;
  END IF;
 ELSE RAISE EXCEPTION 'invalid_clinical_calorie_basis' USING ERRCODE='22023'; END IF;
 IF o.origin_id IS NULL THEN RETURN NULL; END IF;
 -- This is an immutable past input, NOT a claim about its old snapshot's
 -- current values. The daily branch explicitly selects which input it uses.
 RETURN to_jsonb(o)||jsonb_build_object('basis_type','origin');
END $$;

CREATE FUNCTION private.record_mobile_clinical_daily_target_origin(p_user_id uuid,p_application uuid,
 p_snapshot uuid,p_basis jsonb) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE a private.mobile_clinical_daily_applications%ROWTYPE;s public.daily_snapshots%ROWTYPE;
 d private.mobile_clinical_calorie_decisions%ROWTYPE;kind text;formula integer;parent uuid;decision uuid;origin uuid;
BEGIN
 SELECT * INTO STRICT a FROM private.mobile_clinical_daily_applications WHERE user_id=p_user_id AND application_id=p_application;
 SELECT * INTO STRICT s FROM public.daily_snapshots WHERE user_id=p_user_id AND id=p_snapshot;
 IF s.date<>a.date OR s.day_closed OR s.updated_at<>a.applied_at OR s.current_protocol::text<>a.phase
  OR s.calories_target IS DISTINCT FROM a.calories_target OR s.protein_target IS DISTINCT FROM a.protein_target THEN
  RAISE EXCEPTION 'clinical_daily_target_origin_write_changed' USING ERRCODE='XX001'; END IF;
 IF a.result->>'reason'='episode_formula' THEN
  kind:='calculated';formula:=a.formula_target;
 ELSIF a.result->>'reason' IN('confirmed_schedule','confirmed_target') THEN
  SELECT * INTO d FROM private.mobile_clinical_calorie_decisions WHERE user_id=p_user_id
   AND review_id=coalesce(a.schedule_review_id,a.source_review_id)
   AND signup_generation=a.signup_generation AND signup_epoch=a.signup_epoch;
  IF NOT FOUND THEN RETURN; END IF;
  kind:='confirmed';formula:=a.formula_target;decision:=d.review_id;
 ELSIF p_basis IS NOT NULL AND (p_basis->>'calories_target')::integer=a.calories_target
  AND p_basis->>'phase'=a.phase THEN
  kind:='carried';formula:=(p_basis->>'formula_target')::integer;
  IF p_basis->>'basis_type'='origin' THEN
   parent:=(p_basis->>'origin_id')::uuid;
   IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins o WHERE o.user_id=p_user_id
    AND o.origin_id=parent AND o.signup_generation=a.signup_generation AND o.signup_epoch=a.signup_epoch
    AND o.phase=a.phase AND o.calories_target=a.calories_target AND o.formula_target=formula
    AND o.recorded_at<=a.applied_at) THEN
    RAISE EXCEPTION 'clinical_daily_calorie_parent_changed' USING ERRCODE='XX001'; END IF;
  ELSIF p_basis->>'basis_type'='decision' THEN
   decision:=(p_basis->>'review_id')::uuid;
   IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions x WHERE x.user_id=p_user_id
    AND x.review_id=decision AND x.signup_generation=a.signup_generation AND x.signup_epoch=a.signup_epoch
    AND x.phase=a.phase AND x.calories_target=a.calories_target AND x.formula_target=formula
    AND x.decided_at<=a.applied_at) THEN
    RAISE EXCEPTION 'clinical_daily_calorie_decision_changed' USING ERRCODE='XX001'; END IF;
  ELSE RETURN; END IF;
 ELSE RETURN; END IF;
 IF a.calories_target IS NULL OR formula IS NULL THEN RETURN; END IF;
 INSERT INTO private.mobile_clinical_target_origins(user_id,signup_generation,signup_epoch,snapshot_id,date,phase,
  calories_target,protein_target,formula_target,application_id,origin_kind,deficit_level,parent_origin_id,decision_review_id,context_hash,recorded_at)
 VALUES(p_user_id,a.signup_generation,a.signup_epoch,s.id,s.date,a.phase,a.calories_target,a.protein_target,formula,
  a.application_id,kind,a.deficit_level,parent,decision,a.context_hash,a.applied_at) RETURNING origin_id INTO origin;
 INSERT INTO private.mobile_clinical_target_origin_heads VALUES(s.id,p_user_id,origin)
  ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,origin_id=excluded.origin_id;
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_calorie_basis(uuid,uuid,uuid,text,uuid),
 private.record_mobile_clinical_daily_target_origin(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.record_mobile_clinical_full_target_origin() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE applied public.daily_snapshots%ROWTYPE;origin uuid;
BEGIN
 IF NEW.rule_version<>'clinical-v1' OR NOT private.mobile_clinical_has_calorie_calculation(NEW.proposal) THEN RETURN NEW; END IF;
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
  phase,calories_target,protein_target,formula_target,review_id,context_hash,recorded_at,deficit_level,decision_review_id)
 VALUES(NEW.user_id,NEW.signup_generation,NEW.signup_epoch,applied.id,applied.date,
  applied.current_protocol::text,applied.calories_target,applied.protein_target,
  (NEW.proposal#>>'{targets,formulaAfterKcal}')::integer,NEW.review_id,NEW.context_hash,NEW.completed_at,(NEW.proposal#>>'{profile,deficit_level}')::integer,
  CASE WHEN EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions x WHERE x.user_id=NEW.user_id AND x.review_id=NEW.review_id) THEN NEW.review_id END)
 RETURNING origin_id INTO origin;
 INSERT INTO private.mobile_clinical_target_origin_heads VALUES(applied.id,NEW.user_id,origin)
  ON CONFLICT(snapshot_id) DO UPDATE SET user_id=excluded.user_id,origin_id=excluded.origin_id;
 RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private.mobile_clinical_target_origin(p_user_id uuid,p_generation uuid,p_epoch uuid,
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
  ||jsonb_build_object('version',1,'source',CASE WHEN evidence.application_id IS NULL THEN 'clinical_full_v1' ELSE 'clinical_daily_v1' END,'target_component','calories');
END $$;

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
   (p_observed_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date,p_observed_at),
  'confirmed_calorie_decision',private.mobile_clinical_confirmed_calorie_decision(p_user_id,p_generation,p_epoch,
   (p_observed_at AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date,p_observed_at));
END $$;
REVOKE ALL ON FUNCTION private.record_mobile_clinical_full_target_origin(),private.mobile_clinical_target_origin(uuid,uuid,uuid,date,timestamptz),private.mobile_clinical_protocol_authority(uuid,uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

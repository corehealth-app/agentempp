-- Dormant typed clinical conclusion substrate. Public consumers remain absent.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_signup_origins') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_requires_initial_origin' USING ERRCODE='42501';
 END IF;
END $$;

CREATE FUNCTION private.mobile_clinical_body_fat_candidate_at(p_user_id uuid,p_cycle_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; wire jsonb; snapshot jsonb; slot jsonb; photo jsonb; sources jsonb; source jsonb;
 anchor jsonb; mean_value numeric; total numeric:=0; cycle_revision text;
 unavailable jsonb:=jsonb_build_object('version',1,'availability','unavailable',
  'mean_percent',NULL,'mean_hundredths',NULL,'source_hash',NULL,'sources','[]'::jsonb);
BEGIN
 PERFORM private.assert_trusted_backend();
 context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
 BEGIN
  PERFORM m.id FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets a
   ON m.id=a.asset_id AND m.user_id=a.user_id WHERE a.user_id=p_user_id AND a.cycle_id=p_cycle_id
   ORDER BY m.id FOR SHARE OF m NOWAIT;
 EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'mobile_clinical_busy' USING ERRCODE='55P03';
 END;
 context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
 wire:=private.mobile_reevaluation_photo_consent_wire(context);
 IF wire->>'availability' IS DISTINCT FROM 'available' THEN
  RETURN unavailable||jsonb_build_object('unavailable_reason',wire->>'unavailable_reason');
 END IF;
 snapshot:=private.get_mobile_reevaluation_photo_snapshot_at(p_user_id,p_cycle_id,p_observed_at);
 anchor:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 sources:='[]'::jsonb;
 IF jsonb_array_length(snapshot->'photos')<>3 THEN
  RAISE EXCEPTION 'mobile_clinical_photo_snapshot_corrupt' USING ERRCODE='XX001';
 END IF;
 FOR slot IN SELECT value FROM jsonb_array_elements(snapshot->'photos') LOOP
  photo:=slot->'photo';
  IF photo IS NULL OR photo='null'::jsonb OR photo->>'status' IS DISTINCT FROM 'processed'
   OR photo#>>'{analysis,type}' IS DISTINCT FROM 'body' OR photo#>>'{analysis,view}' IS DISTINCT FROM slot->>'pose'
   OR jsonb_typeof(photo#>'{analysis,bf_percent_estimate}') IS DISTINCT FROM 'number'
   OR (photo#>>'{analysis,bf_percent_estimate}')::numeric NOT BETWEEN 3 AND 60
   OR (photo->>'created_at')::timestamptz<(snapshot->>'opened_at')::timestamptz THEN
   RETURN unavailable||jsonb_build_object('unavailable_reason','three_processed_photos_required');
  END IF;
  SELECT jsonb_build_object('pose',s.pose,'asset_id',s.selected_asset_id,'source_revision',s.source_revision::text,
   'processing_request_id',t.processing_request_id,'attempt_id',t.request_id,
   'processed_at',to_char(t.finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'bf_percent',(t.result->>'bf_percent_estimate')::numeric)
  INTO source FROM private.mobile_reevaluation_photo_sources s
   JOIN public.media_assets m ON m.id=s.selected_asset_id AND m.user_id=s.user_id
   JOIN private.mobile_reevaluation_photo_processing_attempts t ON t.asset_id=m.id AND t.user_id=m.user_id
    AND t.signup_generation=s.signup_generation AND t.cycle_id=s.cycle_id
    AND t.consent_acceptance_id=s.consent_acceptance_id AND t.pose=s.pose
    AND t.source_revision=s.source_revision AND t.processing_request_id=m.processing_request_id AND t.status='succeeded'
  WHERE s.user_id=p_user_id AND s.signup_generation=(anchor->>'signup_generation')::uuid
   AND s.cycle_id=p_cycle_id AND s.consent_acceptance_id=(context#>>'{current_acceptance,acceptance_id}')::uuid
   AND s.pose=slot->>'pose' AND s.requested_asset_id=s.selected_asset_id
   AND s.selected_asset_id=(photo->>'asset_id')::uuid;
  IF source IS NULL THEN RAISE EXCEPTION 'mobile_clinical_photo_source_changed' USING ERRCODE='40001'; END IF;
  sources:=sources||jsonb_build_array(source);
  total:=total+(photo#>>'{analysis,bf_percent_estimate}')::numeric;
 END LOOP;
 IF (SELECT count(DISTINCT x->>'asset_id') FROM jsonb_array_elements(sources)x)<>3 THEN
  RAISE EXCEPTION 'mobile_clinical_photo_snapshot_corrupt' USING ERRCODE='XX001';
 END IF;
 mean_value:=round(total/3,2);
 RETURN jsonb_build_object('version',1,'availability','available','unavailable_reason',NULL,
  'user_id',p_user_id,'signup_generation',anchor->'signup_generation','signup_epoch',anchor->'signup_epoch',
  'cycle_id',p_cycle_id,'cycle_revision',context->'cycle_revision',
  'acceptance_id',context#>'{current_acceptance,acceptance_id}',
  'mean_percent',mean_value,'mean_hundredths',(mean_value*100)::integer,'sources',sources,
  'source_hash',encode(extensions.digest(jsonb_build_object('version',1,'user_id',p_user_id,
   'signup_generation',anchor->'signup_generation','signup_epoch',anchor->'signup_epoch','cycle_id',p_cycle_id,
   'cycle_revision',context->'cycle_revision','acceptance_id',context#>'{current_acceptance,acceptance_id}',
   'mean_hundredths',(mean_value*100)::integer,'sources',sources)::text,'sha256'),'hex'));
END $$;

-- A signup baseline is not photo provenance. Read only the surviving numeric
-- receipt, bound to the SAME proven completion generation and epoch. No media
-- identifiers, paths, signed URLs or deleted processing results are projected.
CREATE FUNCTION private.mobile_clinical_signup_photo_origin(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT private.mobile_clinical_canonical_row(jsonb_build_object(
  'user_id',r.user_id,'signup_generation',c.admission_id,'signup_epoch',c.epoch,
  'onboarding_completed_at',r.onboarding_completed_at,'receipt_version',r.receipt_version,
  'method',r.method,'confirmed_body_fat_percent',r.confirmed_body_fat_percent,
  'fingerprint',r.fingerprint,'decided_at',r.decided_at),
  ARRAY['onboarding_completed_at','decided_at'],ARRAY[]::text[])
 FROM private.mobile_signup_strength_completion_receipts c
 JOIN public.user_profiles p ON p.user_id=c.user_id AND p.onboarding_completed
  AND p.onboarding_completed_at=c.completed_at
 JOIN private.signup_body_photo_receipts r ON r.user_id=c.user_id AND r.onboarding_completed_at=c.completed_at
 WHERE c.user_id=p_user_id AND c.admission_id=p_generation AND c.epoch=p_epoch AND c.outcome='first_fresh'
  AND r.receipt_version=1 AND r.decision='accepted' AND r.method='arithmetic_mean_v1'
  AND r.invalidated_at IS NULL AND r.confirmed_body_fat_percent=p.body_fat_percent
$$;
REVOKE ALL ON FUNCTION private.mobile_clinical_signup_photo_origin(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- A NULL profile alone is not no-plan authority. Keep the original keyed
-- first_fresh acknowledgement, generation, epoch and completion bound together.
-- This historical proof never asserts that an age/health guard is still active.
CREATE FUNCTION private.mobile_clinical_signup_no_plan_origin(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('kind','confirmed_no_plan','signupGeneration',r.admission_id,
  'signupEpoch',r.epoch,'completedAt',to_char(r.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
 FROM private.mobile_signup_strength_completion_receipts r
 JOIN public.user_profiles p ON p.user_id=r.user_id AND p.onboarding_completed
  AND p.onboarding_completed_at=r.completed_at AND p.current_protocol IS NULL AND p.deficit_level IS NULL
 JOIN private.workout_strength_authority_epochs e ON e.user_id=r.user_id AND e.epoch=r.epoch
 WHERE r.user_id=p_user_id AND r.admission_id=p_generation AND r.epoch=p_epoch AND r.outcome='first_fresh'
  AND r.completion_result ? 'objective' AND r.completion_result->'objective'='null'::jsonb
  AND r.completion_result#>'{clinical_safety,version}'='1'::jsonb
  AND r.completion_result#>'{clinical_safety,no_plan}'='true'::jsonb
  AND r.completion_result->>'user_id'=r.user_id::text
  AND r.completion_result->'onboarding_completed'='true'::jsonb
  AND (r.completion_result->>'completed_at')::timestamptz=r.completed_at
$$;
REVOKE ALL ON FUNCTION private.mobile_clinical_signup_no_plan_origin(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

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
  'daily_application',private.mobile_clinical_daily_authority(p_user_id,p_generation,p_epoch));
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_body_fat_candidate_at(uuid,uuid,timestamptz),
 private.mobile_clinical_protocol_authority(uuid,uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- Typed confirmation authority. No caller can insert a completed clinical
-- occurrence through an active public endpoint in this migration.
ALTER TABLE private.mobile_reevaluation_cycles DROP CONSTRAINT mobile_reevaluation_cycles_kind_check;
ALTER TABLE private.mobile_reevaluation_cycles ADD CONSTRAINT mobile_reevaluation_cycles_kind_check
 CHECK(kind IN('REGULAR','EARLY_FULL','SAFETY'));
ALTER TABLE private.mobile_reevaluation_cycles ADD CONSTRAINT mobile_reevaluation_safety_is_concluded
 CHECK(kind<>'SAFETY' OR status='completed');

CREATE TABLE private.mobile_clinical_full_receipts (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 preview_id uuid NOT NULL,
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 review_no bigint NOT NULL CHECK(review_no>0),
 kind text NOT NULL CHECK(kind IN('REGULAR','EARLY_FULL','SAFETY','ROUTINE_REVIEW')),
 cycle_id uuid,
 previous_full_id uuid,
 base_before date NOT NULL CHECK(isfinite(base_before)),
 base_after date,
 timezone_at_completion text NOT NULL,
 calculation_date date NOT NULL CHECK(isfinite(calculation_date)),
 completed_at timestamptz NOT NULL CHECK(isfinite(completed_at)),
 final_cycle_revision bigint,
 principal text NOT NULL CHECK(principal IN('keep','deficit_step','activity','phase_maintenance',
  'phase_gain','phase_recomposition','recomposition_transition','gain_exit','neutral_exit',
  'maintenance_step','gain_step','schedule_reconfirm','schedule_pause')),
 activity_level_changed boolean NOT NULL,
 context_hash text NOT NULL CHECK(context_hash ~ '^[0-9a-f]{64}$'),
 input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 form jsonb NOT NULL CHECK(jsonb_typeof(form)='object'),
 intent jsonb NOT NULL CHECK(jsonb_typeof(intent)='object'),
 proposal jsonb NOT NULL CHECK(jsonb_typeof(proposal)='object'),
 result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
 body_fat_mean numeric(4,2) CHECK(body_fat_mean BETWEEN 3 AND 60),
 body_fat_source_hash text CHECK(body_fat_source_hash ~ '^[0-9a-f]{64}$'),
 rule_version text NOT NULL CHECK(rule_version='clinical-v1'),
 PRIMARY KEY(user_id,review_id), UNIQUE(review_id), UNIQUE(user_id,preview_id),
 UNIQUE(user_id,signup_generation,review_no), UNIQUE(user_id,cycle_id),
 FOREIGN KEY(user_id,preview_id) REFERENCES private.mobile_clinical_previews(user_id,preview_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,signup_generation) REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,signup_generation,cycle_id) REFERENCES private.mobile_reevaluation_cycles(user_id,signup_generation,cycle_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,previous_full_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((kind='ROUTINE_REVIEW')=(cycle_id IS NULL)),
 CHECK((kind='ROUTINE_REVIEW')=(base_after IS NULL)),
 CHECK((kind='ROUTINE_REVIEW')=(final_cycle_revision IS NULL)),
 CHECK(final_cycle_revision IS NULL OR final_cycle_revision>0),
 CHECK(base_after IS NULL OR (isfinite(base_after) AND base_after=calculation_date)),
 CHECK(kind<>'REGULAR' OR (base_after>=base_before+14 AND body_fat_mean IS NOT NULL AND body_fat_source_hash IS NOT NULL)),
 CHECK(kind<>'SAFETY' OR principal='neutral_exit'),
 CHECK((body_fat_mean IS NULL)=(body_fat_source_hash IS NULL))
);
CREATE TABLE private.mobile_clinical_confirmation_keys (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 review_id uuid NOT NULL,
 input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 confirmed_at timestamptz NOT NULL CHECK(isfinite(confirmed_at)),
 PRIMARY KEY(user_id,operation_key),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) ON DELETE CASCADE
);
-- N21 separate preference authority. Neither this record nor its head is a
-- goal_type/goal_value or a calculation input. Values rejected by the clinical
-- floor must be normalized OUT of the form before prepare, never audited as
-- an accepted FULL answer. Direct private calls are checked again below.
CREATE TABLE private.mobile_clinical_preference_receipts (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 action text NOT NULL CHECK(action IN('keep','skip','change','remove')),
 outcome text NOT NULL CHECK(outcome IN('unchanged','saved','removed')),
 value jsonb CHECK(value IS NULL OR jsonb_typeof(value)='object'),
 result jsonb NOT NULL CHECK(jsonb_typeof(result)='object'),
 recorded_at timestamptz NOT NULL CHECK(isfinite(recorded_at)),
 PRIMARY KEY(user_id,review_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((action='change')=(outcome='saved')),
 CHECK((action='remove')=(outcome='removed')),
 CHECK(action<>'remove' OR value IS NULL)
);
CREATE TABLE private.mobile_clinical_preference_heads (
 user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_preference_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE private.mobile_clinical_preference_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.mobile_clinical_preference_heads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_preference_receipts,private.mobile_clinical_preference_heads FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_preference_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_preference_receipts
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.mobile_clinical_preference_valid(p_preference jsonb,p_sex text,p_height numeric)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE action text;kind text;value jsonb;number numeric;
BEGIN
 IF p_preference IS NULL OR p_preference='null'::jsonb THEN RETURN true; END IF;
 IF jsonb_typeof(p_preference)<>'object' THEN RETURN false; END IF;
 action:=p_preference->>'action';
 IF action IN('keep','skip','remove') THEN RETURN p_preference-ARRAY['action']='{}'::jsonb; END IF;
 IF action IS DISTINCT FROM 'change' OR NOT(p_preference ? 'value')
  OR p_preference-ARRAY['action','value']<>'{}'::jsonb THEN RETURN false; END IF;
 value:=p_preference->'value';
 IF jsonb_typeof(value)<>'object' THEN RETURN false; END IF;
 kind:=value->>'kind';
 IF kind IN('follow_app','professional') THEN RETURN value-ARRAY['kind']='{}'::jsonb; END IF;
 IF kind='routine' THEN RETURN coalesce(value-ARRAY['kind','value']='{}'::jsonb
  AND value->>'value' IN('regular_training','more_energy','organized_food','maintain_weight'),false); END IF;
 IF kind='weight' THEN
  IF value-ARRAY['kind','kg']<>'{}'::jsonb OR jsonb_typeof(value->'kg') IS DISTINCT FROM 'number'
   OR p_height IS NULL OR p_height<=0 OR p_height::text IN('NaN','Infinity','-Infinity') THEN RETURN false; END IF;
  number:=(value->>'kg')::numeric;
  RETURN number BETWEEN 30 AND 300 AND number/power(p_height/100,2)>=18.5;
 ELSIF kind='body_fat' THEN
  IF value-ARRAY['kind','percent']<>'{}'::jsonb OR jsonb_typeof(value->'percent') IS DISTINCT FROM 'number' THEN RETURN false; END IF;
  number:=(value->>'percent')::numeric;
  RETURN coalesce(number BETWEEN 10 AND 60 AND (number>=12 OR p_sex='masculino'),false);
 END IF;
 RETURN false;
EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation OR division_by_zero THEN RETURN false;
END $$;
CREATE FUNCTION private.mobile_clinical_preference_current(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('user_id',r.user_id,'signup_generation',r.signup_generation,'signup_epoch',r.signup_epoch,
  'review_id',r.review_id,'status',r.outcome,'value',r.value,
  'recorded_at',to_char(r.recorded_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
 FROM private.mobile_clinical_preference_heads h JOIN private.mobile_clinical_preference_receipts r
  ON r.user_id=h.user_id AND r.review_id=h.review_id
 JOIN private.mobile_signup_strength_completion_receipts c ON c.user_id=r.user_id AND c.admission_id=r.signup_generation
  AND c.epoch=r.signup_epoch AND c.outcome='first_fresh'
 JOIN private.workout_strength_authority_epochs e ON e.user_id=c.user_id AND e.epoch=c.epoch
 JOIN public.user_profiles p ON p.user_id=c.user_id AND p.onboarding_completed AND p.onboarding_completed_at=c.completed_at
 WHERE r.user_id=p_user_id AND r.signup_generation=p_generation AND r.signup_epoch=p_epoch
$$;
CREATE FUNCTION private.mobile_clinical_preference_decision(p_user_id uuid,p_generation uuid,p_epoch uuid,p_preference jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE current_preference jsonb;profile public.user_profiles%ROWTYPE;action text;
BEGIN
 SELECT * INTO STRICT profile FROM public.user_profiles WHERE user_id=p_user_id;
 IF NOT coalesce(private.mobile_clinical_preference_valid(p_preference,profile.sex::text,profile.height_cm),false) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_preference' USING ERRCODE='22023';
 END IF;
 current_preference:=private.mobile_clinical_preference_current(p_user_id,p_generation,p_epoch);
 action:=p_preference->>'action';
 RETURN jsonb_build_object('status',CASE action WHEN 'change' THEN 'saved' WHEN 'remove' THEN 'removed' ELSE 'unchanged' END,
  'value',CASE action WHEN 'change' THEN p_preference->'value' WHEN 'remove' THEN 'null'::jsonb ELSE current_preference->'value' END);
END $$;
CREATE FUNCTION private.apply_mobile_clinical_preference(p_user_id uuid,p_review_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE r private.mobile_clinical_full_receipts%ROWTYPE;preference jsonb;action text;result jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_write_permits WHERE user_id=p_user_id
  AND transaction_id=pg_current_xact_id() AND review_id=p_review_id) THEN
  RAISE EXCEPTION 'mobile_clinical_preference_conclusion_required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO STRICT r FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND review_id=p_review_id;
 preference:=r.form->'preference';action:=preference->>'action';
 IF action IS NULL THEN RETURN; END IF;
 IF r.kind NOT IN('REGULAR','EARLY_FULL') OR action NOT IN('keep','skip','change','remove') THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_preference' USING ERRCODE='22023';
 END IF;
 IF EXISTS(SELECT 1 FROM private.mobile_clinical_preference_receipts WHERE user_id=p_user_id AND review_id=p_review_id) THEN RETURN; END IF;
 result:=r.result->'preference';
 INSERT INTO private.mobile_clinical_preference_receipts(user_id,review_id,signup_generation,signup_epoch,action,outcome,value,result,recorded_at)
  VALUES(p_user_id,p_review_id,r.signup_generation,r.signup_epoch,action,result->>'status',
   nullif(result->'value','null'::jsonb),result,r.completed_at);
 IF action IN('change','remove') THEN
  INSERT INTO private.mobile_clinical_preference_heads VALUES(p_user_id,p_review_id)
   ON CONFLICT(user_id) DO UPDATE SET review_id=excluded.review_id;
 END IF;
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_preference_valid(jsonb,text,numeric),
 private.mobile_clinical_preference_current(uuid,uuid,uuid),private.mobile_clinical_preference_decision(uuid,uuid,uuid,jsonb),
 private.apply_mobile_clinical_preference(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_clinical_ledger_valid(p_steps integer[]) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE step integer; total integer:=0;
BEGIN
 IF p_steps IS NULL THEN RETURN true; END IF;
 IF cardinality(p_steps)>200 OR (cardinality(p_steps)>0 AND (array_ndims(p_steps)<>1 OR array_lower(p_steps,1)<>1)) THEN RETURN false; END IF;
 FOREACH step IN ARRAY p_steps LOOP
  IF step IS NULL OR step=0 OR step NOT BETWEEN -200 AND 200 THEN RETURN false; END IF;
  total:=total+abs(step);
 END LOOP;
 RETURN total<=200;
END $$;
-- The immutable plan has seven canonical fields. Reaching maintenance is a
-- separate application fact; a caller cannot replace this with a guessed R.
CREATE FUNCTION private.mobile_clinical_schedule_valid(p_schedule jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE start_day date;end_day date;initial numeric;maintenance numeric;gap numeric;weeks numeric;
BEGIN
 IF jsonb_typeof(p_schedule) IS DISTINCT FROM 'object'
  OR NOT(p_schedule ?& ARRAY['version','kind','state','startDate','startTargetKcal','maintenanceTargetKcal','plannedEndDate'])
  OR p_schedule-ARRAY['version','kind','state','startDate','startTargetKcal','maintenanceTargetKcal','plannedEndDate']<>'{}'::jsonb
  OR p_schedule->'version' IS DISTINCT FROM '1'::jsonb
  OR p_schedule->>'kind' NOT IN('recomp_to_maintenance','gain_exit')
  OR p_schedule->>'state' NOT IN('running','suspended')
  OR jsonb_typeof(p_schedule->'kind') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_schedule->'state') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_schedule->'startDate') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_schedule->'plannedEndDate') IS DISTINCT FROM 'string'
  OR (p_schedule->>'startDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  OR (p_schedule->>'plannedEndDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  OR jsonb_typeof(p_schedule->'startTargetKcal') IS DISTINCT FROM 'number'
  OR jsonb_typeof(p_schedule->'maintenanceTargetKcal') IS DISTINCT FROM 'number' THEN RETURN false; END IF;
 initial:=(p_schedule->>'startTargetKcal')::numeric;maintenance:=(p_schedule->>'maintenanceTargetKcal')::numeric;
 IF initial NOT BETWEEN 1 AND 9007199254740991 OR maintenance NOT BETWEEN 1 AND 9007199254740991
  OR trunc(initial)<>initial OR trunc(maintenance)<>maintenance THEN RETURN false; END IF;
 start_day:=(p_schedule->>'startDate')::date;end_day:=(p_schedule->>'plannedEndDate')::date;
 gap:=CASE p_schedule->>'kind' WHEN 'gain_exit' THEN initial-maintenance ELSE maintenance-initial END;
 weeks:=greatest(0,ceil(gap/100)-1);
 RETURN isfinite(start_day) AND isfinite(end_day) AND extract(year FROM start_day) BETWEEN 1 AND 9999
  AND extract(year FROM end_day) BETWEEN 1 AND 9999 AND end_day=start_day+(weeks*7)::integer;
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow OR numeric_value_out_of_range THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_schedule_valid(jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE private.mobile_clinical_episode_events (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 review_id uuid NOT NULL,
 event_id uuid NOT NULL DEFAULT gen_random_uuid(),
 event_no bigint NOT NULL CHECK(event_no>0),
 previous_event_id uuid,
 episode_id uuid NOT NULL,
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 entry_origin text NOT NULL CHECK(entry_origin IN('signup','confirmed_phase_change','legacy_unknown')),
 entry_date date CHECK(isfinite(entry_date)),
 start_weight_kg numeric(5,2) CHECK(start_weight_kg BETWEEN 30 AND 300),
 start_height_cm numeric CHECK(start_height_cm>0),
 start_body_fat_percent numeric CHECK(start_body_fat_percent BETWEEN 3 AND 60),
 start_training_frequency smallint CHECK(start_training_frequency BETWEEN 0 AND 7),
 maintenance_since date CHECK(isfinite(maintenance_since)),
 deficit_level integer CHECK(deficit_level IN(400,500,600)),
 difficulty_count bigint CHECK(difficulty_count BETWEEN 0 AND 9007199254740991),
 ledger_steps integer[] CHECK(private.mobile_clinical_ledger_valid(ledger_steps)),
 schedule jsonb CHECK(schedule IS NULL OR private.mobile_clinical_schedule_valid(schedule)),
 applied_at timestamptz NOT NULL CHECK(isfinite(applied_at)),
 rule_version text NOT NULL CHECK(rule_version='clinical-v1'),
 PRIMARY KEY(user_id,event_id), UNIQUE(user_id,signup_generation,event_no), UNIQUE(user_id,review_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,previous_event_id) REFERENCES private.mobile_clinical_episode_events(user_id,event_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,signup_generation) REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED,
 CONSTRAINT mobile_clinical_episode_deficit_authority CHECK(
  CASE WHEN phase='recomposicao' THEN deficit_level IS NOT NULL OR entry_origin='legacy_unknown'
   ELSE deficit_level IS NULL END),
 CHECK(entry_origin<>'legacy_unknown' OR (entry_date IS NULL AND start_weight_kg IS NULL
  AND start_height_cm IS NULL AND start_body_fat_percent IS NULL AND start_training_frequency IS NULL))
);
CREATE TABLE private.mobile_clinical_health_clear_receipts (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 previous_safety_revision bigint NOT NULL CHECK(previous_safety_revision>0),
 safety_revision bigint NOT NULL CHECK(safety_revision=previous_safety_revision+1),
 professional_conversation_confirmed boolean NOT NULL CHECK(professional_conversation_confirmed),
 cleared_at timestamptz NOT NULL CHECK(isfinite(cleared_at)),
 PRIMARY KEY(user_id,review_id), UNIQUE(user_id,safety_revision),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE private.mobile_clinical_body_fat_receipts (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid NOT NULL,
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 cycle_id uuid NOT NULL,
 acceptance_id uuid NOT NULL,
 mean_percent numeric(4,2) NOT NULL CHECK(mean_percent BETWEEN 3 AND 60),
 source_hash text NOT NULL CHECK(source_hash ~ '^[0-9a-f]{64}$'),
 sources jsonb NOT NULL CHECK(jsonb_typeof(sources)='array' AND jsonb_array_length(sources)=3),
 confirmed_at timestamptz NOT NULL CHECK(isfinite(confirmed_at)),
 PRIMARY KEY(user_id,review_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED
);
-- This pointer is invalidated by manual writes; the numeric receipt is immutable.
CREATE TABLE private.mobile_clinical_body_fat_heads (
 user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 review_id uuid,
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_body_fat_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE private.mobile_clinical_day_events (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 date date NOT NULL CHECK(isfinite(date)),
 review_id uuid NOT NULL,
 phase text NOT NULL CHECK(phase IN('recomposicao','manutencao','ganho_massa')),
 deficit_level integer CHECK(deficit_level IN(400,500,600)),
 calories_target integer CHECK(calories_target>0),
 protein_target numeric(6,2) CHECK(protein_target>=0),
 formula_target integer CHECK(formula_target>0),
 effective_adjustment integer,
 schedule jsonb CHECK(schedule IS NULL OR private.mobile_clinical_schedule_valid(schedule)),
 applied_at timestamptz NOT NULL CHECK(isfinite(applied_at)),
 rule_version text NOT NULL CHECK(rule_version='clinical-v1'),
 PRIMARY KEY(user_id,date,review_id),
 FOREIGN KEY(user_id,review_id) REFERENCES private.mobile_clinical_full_receipts(user_id,review_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((effective_adjustment IS NULL)=(calories_target IS NULL OR formula_target IS NULL)),
 CHECK(effective_adjustment IS NULL OR effective_adjustment=calories_target-formula_target)
);
-- Ephemeral transaction-scoped capability, accessible only to the private
-- confirmation implementation. No setting supplied by a caller grants it.
CREATE TABLE private.mobile_clinical_write_permits (
 user_id uuid NOT NULL,
 transaction_id xid8 NOT NULL,
 review_id uuid NOT NULL,
 PRIMARY KEY(user_id,transaction_id)
);
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['mobile_clinical_full_receipts','mobile_clinical_confirmation_keys',
  'mobile_clinical_episode_events','mobile_clinical_health_clear_receipts','mobile_clinical_body_fat_receipts',
  'mobile_clinical_day_events','mobile_clinical_body_fat_heads','mobile_clinical_write_permits'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role',name);
  IF name NOT IN('mobile_clinical_body_fat_heads','mobile_clinical_write_permits') THEN
   EXECUTE format('CREATE TRIGGER mobile_clinical_evidence_immutable BEFORE UPDATE OR DELETE ON private.%I '
    ||'FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable()',name);
  END IF;
 END LOOP;
END $$;

-- Dormant extension points: a later private application journal can project
-- effective episode state without fabricating another FULL review/event.
CREATE FUNCTION private.mobile_clinical_effective_episode(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS private.mobile_clinical_episode_events LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE e private.mobile_clinical_episode_events%ROWTYPE;
BEGIN
 SELECT * INTO e FROM private.mobile_clinical_episode_events x WHERE x.user_id=p_user_id
  AND x.signup_generation=p_generation AND x.signup_epoch=p_epoch ORDER BY x.event_no DESC LIMIT 1;
 RETURN e;
END $$;
CREATE FUNCTION private.mobile_clinical_daily_authority(p_user_id uuid,p_generation uuid,p_epoch uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT 'null'::jsonb
$$;
REVOKE ALL ON FUNCTION private.mobile_clinical_effective_episode(uuid,uuid,uuid),
 private.mobile_clinical_daily_authority(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_clinical_calendar_base_at(p_user_id uuid,p_generation uuid,p_epoch uuid,
 p_signup_at timestamptz,p_signup_zone text,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE r private.mobile_clinical_full_receipts%ROWTYPE; c private.mobile_reevaluation_cycles%ROWTYPE;
 base_day date:=(p_signup_at AT TIME ZONE p_signup_zone)::date; zone text:=p_signup_zone;
 last_id uuid; last_at timestamptz:=p_signup_at; known_cycles integer:=0;
BEGIN
 FOR r IN SELECT x.* FROM private.mobile_clinical_full_receipts x
  WHERE x.user_id=p_user_id AND x.signup_generation=p_generation AND x.signup_epoch=p_epoch
   AND x.kind<>'ROUTINE_REVIEW' ORDER BY x.review_no LOOP
  SELECT * INTO c FROM private.mobile_reevaluation_cycles WHERE user_id=p_user_id AND cycle_id=r.cycle_id;
  IF c.cycle_id IS NULL OR c.signup_generation<>p_generation OR c.signup_epoch<>p_epoch
   OR c.kind<>r.kind OR c.status<>'completed' OR c.completed_at<>r.completed_at
   OR c.revision<>r.final_cycle_revision OR c.base_date<>r.base_before OR c.due_date<>r.base_before+14
   OR c.timezone_at_open<>zone OR r.previous_full_id IS DISTINCT FROM last_id OR r.base_before<>base_day
   OR r.completed_at<last_at OR r.completed_at>p_observed_at
   OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=r.timezone_at_completion)
   OR r.base_after IS DISTINCT FROM (r.completed_at AT TIME ZONE r.timezone_at_completion)::date
   OR (r.kind='REGULAR' AND r.base_after<base_day+14) THEN
   RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001';
  END IF;
  base_day:=r.base_after;zone:=r.timezone_at_completion;last_id:=r.review_id;last_at:=r.completed_at;
  known_cycles:=known_cycles+1;
 END LOOP;
 IF known_cycles<>(SELECT count(*) FROM private.mobile_reevaluation_cycles
  WHERE user_id=p_user_id AND signup_generation=p_generation AND status='completed')
  OR base_day NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-17' THEN
  RAISE EXCEPTION 'mobile_reevaluation_completion_unproven' USING ERRCODE='XX001';
 END IF;
 RETURN jsonb_build_object('base_date',base_day,'timezone',zone,'last_full_id',last_id);
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_calendar_base_at(uuid,uuid,uuid,timestamptz,text,timestamptz),
 private.mobile_clinical_ledger_valid(integer[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.mobile_reevaluation_context_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE
  observed_at timestamptz; profile public.user_profiles%ROWTYPE;
  receipt private.mobile_signup_strength_completion_receipts%ROWTYPE;
  source private.strength_week_source_versions%ROWTYPE;
  scope private.strength_week_scopes%ROWTYPE;
  admission private.mobile_signup_strength_request_admissions%ROWTYPE;
  current_epoch uuid; cycle private.mobile_reevaluation_cycles%ROWTYPE;
  zone text; base_day date; due_day date; reason text; cycle_wire jsonb := 'null'; calendar jsonb;
BEGIN
  PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
  observed_at:=COALESCE(p_observed_at,clock_timestamp());
  IF NOT isfinite(observed_at) OR date_part('year',observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_input' USING ERRCODE='22023';
  END IF;
  SELECT p.* INTO profile FROM public.user_profiles p WHERE p.user_id=p_user_id;
  IF NOT FOUND OR profile.onboarding_completed IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('reason','onboarding_incomplete');
  END IF;
  IF profile.onboarding_completed_at IS NULL THEN
    RETURN jsonb_build_object('reason','anchor_unproven');
  END IF;
  SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
  SELECT r.* INTO receipt FROM private.mobile_signup_strength_completion_receipts r
    WHERE r.user_id=p_user_id AND r.epoch=current_epoch AND r.outcome='first_fresh'
      AND r.completed_at=profile.onboarding_completed_at;
  IF NOT FOUND THEN RETURN jsonb_build_object('reason','anchor_unproven'); END IF;
  SELECT a.* INTO admission FROM private.mobile_signup_strength_request_admissions a
    WHERE a.user_id=p_user_id AND a.admission_id=receipt.admission_id;
  SELECT s.* INTO scope FROM private.strength_week_scopes s
    WHERE s.user_id=p_user_id AND s.generation=receipt.generation;
  SELECT s.* INTO source FROM private.strength_week_source_versions s
    WHERE s.user_id=p_user_id AND s.generation=receipt.generation
      AND s.source_version_id=receipt.frequency_source_version_id;
  IF admission.admission_id IS NULL OR admission.epoch IS DISTINCT FROM receipt.epoch
    OR scope.generation IS NULL OR scope.predecessor_generation IS NOT NULL
    OR scope.open_operation_namespace IS DISTINCT FROM 'mobile_signup_completion_v1'
    OR scope.open_operation_key IS DISTINCT FROM receipt.admission_id::text
    OR source.source_version_id IS NULL OR source.source_kind IS DISTINCT FROM 'informed_frequency'
    OR source.fact IS DISTINCT FROM 'value' OR source.planned_days NOT BETWEEN 0 AND 7
    OR source.source_entity_id IS NOT NULL OR source.source_valid_until IS NOT NULL
    OR source.operation_namespace IS DISTINCT FROM 'mobile_signup_completion_v1'
    OR source.operation_key IS DISTINCT FROM receipt.admission_id::text
    OR NOT(admission.admitted_at<=receipt.completed_at AND receipt.completed_at<=scope.opened_at
      AND scope.opened_at<=source.observed_at AND source.observed_at<=receipt.recorded_at
      AND receipt.recorded_at<=observed_at)
    OR (receipt.completion_result->>'completed_at')::timestamptz IS DISTINCT FROM receipt.completed_at
    OR receipt.completion_result->>'user_id' IS DISTINCT FROM p_user_id::text
    OR receipt.completion_result->'onboarding_completed' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001';
  END IF;
  zone:=source.observed_timezone;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
    RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001';
  END IF;
  base_day:=(receipt.completed_at AT TIME ZONE zone)::date;
  IF base_day NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-17' THEN
    RAISE EXCEPTION 'mobile_reevaluation_origin_corrupt' USING ERRCODE='XX001';
  END IF;
  due_day:=base_day+14;
  calendar:=private.mobile_clinical_calendar_base_at(p_user_id,receipt.admission_id,current_epoch,
    receipt.completed_at,zone,observed_at);
  base_day:=(calendar->>'base_date')::date;
  zone:=calendar->>'timezone';
  due_day:=base_day+14;
  SELECT c.* INTO cycle FROM private.mobile_reevaluation_cycles c WHERE c.user_id=p_user_id
    AND c.signup_generation=receipt.admission_id AND c.status IN('open','collecting','review_ready');
  IF FOUND THEN
    IF cycle.signup_epoch IS DISTINCT FROM current_epoch OR cycle.base_date IS DISTINCT FROM base_day
      OR cycle.due_date IS DISTINCT FROM due_day OR cycle.timezone_at_open IS DISTINCT FROM zone
      OR cycle.opened_at>observed_at THEN
      RAISE EXCEPTION 'mobile_reevaluation_cycle_corrupt' USING ERRCODE='XX001';
    END IF;
    cycle_wire:=private.mobile_reevaluation_cycle_wire(cycle);
  END IF;
  reason:=CASE WHEN cycle.kind='EARLY_FULL' THEN NULL WHEN (observed_at AT TIME ZONE zone)::date<due_day THEN 'not_due' ELSE NULL END;
  RETURN jsonb_build_object('reason',reason,'signup_generation',receipt.admission_id,
    'signup_epoch',current_epoch,'observed_at',observed_at,'last_full_id',calendar->'last_full_id',
    'clock',jsonb_build_object('base_date',to_char(base_day::timestamp,'YYYY-MM-DD'),
      'due_date',to_char(due_day::timestamp,'YYYY-MM-DD'),'timezone',zone),'cycle',cycle_wire);
END $$;
-- Named branch of the existing n11 cascade, not a new protein formula.
CREATE FUNCTION private.mobile_clinical_protein_branch(p_phase text,p_hunger text,
 p_frequency smallint,p_recomp_factor jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF p_phase='recomposicao' AND NOT(coalesce(jsonb_typeof(p_recomp_factor)='null',false)
  OR coalesce(p_recomp_factor='0'::jsonb,false)) THEN RETURN 'fixed_recomposition'; END IF;
 IF p_hunger='muita' THEN RETURN 'muita'; END IF;
 IF p_frequency<3 THEN RETURN 'training_low'; END IF;
 IF p_hunger='pouca' AND p_frequency>=5 THEN RETURN 'optimal_high_training'; END IF;
 IF p_hunger='pouca' AND p_frequency>=4 THEN RETURN 'optimal_mid_training'; END IF;
 RETURN 'moderada';
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_protein_branch(text,text,smallint,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_clinical_profile_write_fence() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF OLD.onboarding_completed IS TRUE AND NEW.onboarding_completed IS TRUE
  AND ROW(NEW.current_protocol,NEW.deficit_level,NEW.activity_level,NEW.training_frequency,NEW.hunger_level,
   NEW.cycle_start_weight_kg,NEW.cycle_start_bf_percent,NEW.cycle_start_training_freq,NEW.cycle_start_at)
   IS DISTINCT FROM ROW(OLD.current_protocol,OLD.deficit_level,OLD.activity_level,OLD.training_frequency,OLD.hunger_level,
   OLD.cycle_start_weight_kg,OLD.cycle_start_bf_percent,OLD.cycle_start_training_freq,OLD.cycle_start_at)
  AND (EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=OLD.user_id)
   OR EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=OLD.user_id)
   OR EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=OLD.user_id
    AND r.outcome='first_fresh' AND r.completion_result ? 'objective'
    AND r.completion_result->'objective'='null'::jsonb
    AND r.completion_result#>'{clinical_safety,version}'='1'::jsonb
    AND r.completion_result#>'{clinical_safety,no_plan}'='true'::jsonb))
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_write_permits
   WHERE user_id=OLD.user_id AND transaction_id=pg_current_xact_id()) THEN
  RAISE EXCEPTION 'mobile_clinical_review_required' USING ERRCODE='40001';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_profile_write_fence BEFORE UPDATE OF current_protocol,deficit_level,
 activity_level,training_frequency,hunger_level,cycle_start_weight_kg,cycle_start_bf_percent,cycle_start_training_freq,cycle_start_at
 ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_profile_write_fence();
CREATE FUNCTION private.mobile_clinical_invalidate_body_fat() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 -- UPDATE only: never insert a users-FK row from a legacy profile-first path.
 UPDATE private.mobile_clinical_body_fat_heads SET review_id=NULL WHERE user_id=OLD.user_id AND review_id IS NOT NULL;
 RETURN NEW;
END $$;
CREATE TRIGGER mobile_clinical_bf_manual_write AFTER UPDATE OF body_fat_percent ON public.user_profiles
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_invalidate_body_fat();
CREATE TRIGGER mobile_clinical_bf_profile_state AFTER UPDATE OF body_fat_measured_at,onboarding_completed,onboarding_completed_at
 ON public.user_profiles FOR EACH ROW WHEN(OLD.body_fat_measured_at IS DISTINCT FROM NEW.body_fat_measured_at
  OR OLD.onboarding_completed IS DISTINCT FROM NEW.onboarding_completed
  OR OLD.onboarding_completed_at IS DISTINCT FROM NEW.onboarding_completed_at)
 EXECUTE FUNCTION private.mobile_clinical_invalidate_body_fat();

-- All inputs here are server evaluated and private. A client/model never gets
-- to submit this proposal directly; T4 must provide the strict BFF adapter.
CREATE FUNCTION private.confirm_mobile_clinical_preview_at(p_user_id uuid,p_preview_id uuid,p_operation_key uuid,
 p_form jsonb,p_intent jsonb,p_proposal jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' AS $$
DECLARE preview private.mobile_clinical_previews%ROWTYPE; receipt private.mobile_clinical_full_receipts%ROWTYPE;
 key_row private.mobile_clinical_confirmation_keys%ROWTYPE; previous private.mobile_clinical_episode_events%ROWTYPE;
 origin private.mobile_clinical_signup_origins%ROWTYPE; profile_row public.user_profiles%ROWTYPE;
 cycle_row private.mobile_reevaluation_cycles%ROWTYPE; consent_row record;
 context jsonb; safety jsonb; candidate jsonb; profile_after jsonb; targets jsonb; episode jsonb; result jsonb; preference_result jsonb;
 input_hash text; principal text; phase text; before_phase text; zone text; day date; observed_at timestamptz;
 after_kcal integer; after_protein numeric; formula_kcal integer; before_kcal integer; before_protein numeric;
 new_weight numeric; new_frequency smallint; new_level text; deficit integer; body_fat numeric;
 new_hunger text; protein_branch_before text; protein_branch_after text;
 protein_branch_changed boolean:=false; protein_factors_row jsonb; recomp_factor_row jsonb;
 health_only boolean;health_answer jsonb;health_items text[];
 clear_hold boolean; effective_hold boolean; no_plan boolean; loss_guard boolean; unknown_guard boolean;
 age_years integer; bmi numeric; safety_revision bigint; before_revision bigint; review_number bigint;
 current_cycle uuid; episode_id uuid; entry_origin text; entry_date date; r_date date;
 start_weight numeric; start_height numeric; start_bf numeric; start_frequency smallint;
 previous_steps integer[]; steps integer[]; count_after bigint; old_weight_marker text;
 schedule jsonb;previous_schedule jsonb;previous_r date;expected_r date;expected_kcal numeric;
 schedule_reached boolean;step_count integer;
 previous_full uuid; base_day date; cycle_revision bigint; applied_day public.daily_snapshots%ROWTYPE;
 written_day_id uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_preview_id IS NULL OR p_operation_key IS NULL OR jsonb_typeof(p_form) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object' OR jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
  OR octet_length(p_form::text)>65536 OR octet_length(p_intent::text)>8192 OR octet_length(p_proposal::text)>65536 THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_confirmation' USING ERRCODE='22023';
 END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 input_hash:=encode(extensions.digest(jsonb_build_object('preview_id',p_preview_id,
  'form',p_form,'intent',p_intent,'proposal',p_proposal)::text,'sha256'),'hex');
 SELECT * INTO key_row FROM private.mobile_clinical_confirmation_keys WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF key_row.input_hash<>input_hash THEN RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001'; END IF;
  SELECT * INTO STRICT receipt FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND review_id=key_row.review_id;
  RETURN receipt.result;
 END IF;
 SELECT * INTO receipt FROM private.mobile_clinical_full_receipts WHERE user_id=p_user_id AND preview_id=p_preview_id;
 IF FOUND THEN
  IF receipt.input_hash<>input_hash THEN RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001'; END IF;
  INSERT INTO private.mobile_clinical_confirmation_keys(user_id,operation_key,review_id,input_hash,confirmed_at)
   VALUES(p_user_id,p_operation_key,receipt.review_id,input_hash,coalesce(p_observed_at,clock_timestamp()));
  RETURN receipt.result;
 END IF;
 SELECT * INTO preview FROM private.mobile_clinical_previews WHERE user_id=p_user_id AND preview_id=p_preview_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_preview_not_found' USING ERRCODE='P0002'; END IF;
 IF preview.form_hash<>encode(extensions.digest(p_form::text,'sha256'),'hex')
  OR preview.intent_hash<>encode(extensions.digest(p_intent::text,'sha256'),'hex')
  OR preview.proposal_hash<>encode(extensions.digest(p_proposal::text,'sha256'),'hex') THEN
  RAISE EXCEPTION 'mobile_clinical_confirmation_conflict' USING ERRCODE='40001';
 END IF;
 context:=private.capture_mobile_clinical_context_at(p_user_id,preview.review_kind,preview.cycle_id,p_observed_at);
 observed_at:=(context->>'observed_at')::timestamptz;day:=(context#>>'{facts,calculation_date}')::date;
 IF context->>'context_hash'<>preview.context_hash OR observed_at>=preview.valid_until
  OR preview.signup_generation::text IS DISTINCT FROM context#>>'{facts,anchor,signup_generation}'
  OR preview.signup_epoch::text IS DISTINCT FROM context#>>'{facts,anchor,signup_epoch}' THEN
  RAISE EXCEPTION 'mobile_clinical_preview_stale' USING ERRCODE='40001';
 END IF;
 SELECT * INTO STRICT profile_row FROM public.user_profiles WHERE user_id=p_user_id;
 SELECT * INTO applied_day FROM public.daily_snapshots WHERE user_id=p_user_id AND date=day;
 before_phase:=profile_row.current_protocol::text;zone:=context#>>'{facts,owner,timezone}';
 base_day:=(context#>>'{facts,anchor,clock,base_date}')::date;
 previous_full:=(context#>>'{facts,anchor,last_full_id}')::uuid;
 principal:=p_proposal->>'principal';profile_after:=p_proposal->'profile';targets:=p_proposal->'targets';episode:=p_proposal->'episode';
 IF p_form->'version' IS DISTINCT FROM '1'::jsonb OR p_form->>'kind' IS DISTINCT FROM preview.review_kind
  OR p_form->>'phase' IS DISTINCT FROM before_phase OR p_proposal->'version' IS DISTINCT FROM '1'::jsonb
  OR p_proposal-ARRAY['version','principal','profile','targets','episode','clearHold']<>'{}'::jsonb
  OR principal IS NULL OR principal NOT IN('keep','deficit_step','activity','phase_maintenance','phase_gain',
   'phase_recomposition','recomposition_transition','gain_exit','neutral_exit','maintenance_step','gain_step','schedule_reconfirm','schedule_pause')
  OR jsonb_typeof(profile_after) IS DISTINCT FROM 'object' OR jsonb_typeof(targets) IS DISTINCT FROM 'object'
  OR jsonb_typeof(episode) IS DISTINCT FROM 'object' OR jsonb_typeof(p_proposal->'clearHold') IS DISTINCT FROM 'boolean'
  OR NOT(profile_after ?& ARRAY['current_protocol','deficit_level','activity_level','training_frequency','hunger_level'])
  OR profile_after-ARRAY['current_protocol','deficit_level','activity_level','training_frequency','hunger_level']<>'{}'::jsonb
  OR NOT(targets ?& ARRAY['beforeKcal','beforeProtein','afterKcal','afterProtein','formulaAfterKcal'])
  OR targets-ARRAY['beforeKcal','beforeProtein','afterKcal','afterProtein','formulaAfterKcal']<>'{}'::jsonb
  OR NOT(episode ?& ARRAY['difficultyCount','ledgerSteps','schedule','maintenanceSince'])
  OR episode-ARRAY['difficultyCount','ledgerSteps','schedule','maintenanceSince']<>'{}'::jsonb
  OR (principal<>'keep' AND p_intent->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_proposal' USING ERRCODE='22023';
 END IF;
 phase:=profile_after->>'current_protocol';deficit:=(profile_after->>'deficit_level')::integer;
 new_frequency:=(profile_after->>'training_frequency')::smallint;new_level:=profile_after->>'activity_level';
 new_hunger:=profile_after->>'hunger_level';
 before_kcal:=(targets->>'beforeKcal')::integer;before_protein:=(targets->>'beforeProtein')::numeric;
 after_kcal:=(targets->>'afterKcal')::integer;after_protein:=(targets->>'afterProtein')::numeric;
 formula_kcal:=(targets->>'formulaAfterKcal')::integer;count_after:=(episode->>'difficultyCount')::bigint;
 r_date:=(episode->>'maintenanceSince')::date;new_weight:=(p_form#>>'{answers,weightKg}')::numeric;
 health_only:=before_phase IS NULL;
 IF health_only THEN
  IF context#>>'{facts,protocol_authority,phase_origin,kind}' IS DISTINCT FROM 'confirmed_no_plan'
   OR p_form->'noPlanOrigin' IS DISTINCT FROM context#>'{facts,protocol_authority,phase_origin}' THEN
   RAISE EXCEPTION 'mobile_clinical_no_plan_origin_unproven' USING ERRCODE='40001';
  END IF;
  IF preview.review_kind NOT IN('REGULAR','EARLY_FULL') OR principal<>'keep'
   OR NOT(p_form ?& ARRAY['version','phase','kind','activityPurpose','answers','preference','noPlanOrigin'])
   OR p_form-ARRAY['version','phase','kind','activityPurpose','answers','preference','noPlanOrigin']<>'{}'::jsonb
   OR p_form->'phase' IS DISTINCT FROM 'null'::jsonb OR p_form->>'activityPurpose' IS DISTINCT FROM 'normal'
   OR p_form->'preference' IS DISTINCT FROM 'null'::jsonb
   OR jsonb_typeof(p_form->'answers') IS DISTINCT FROM 'object'
   OR NOT(p_form->'answers' ?& ARRAY['weightKg','strengthSessions','adherence','hunger','energy',
    'strengthProgression','fatPerception','difficultToMaintain','activity','healthCheck','professionalConversationConfirmed'])
   OR (p_form->'answers')-ARRAY['weightKg','strengthSessions','adherence','hunger','energy',
    'strengthProgression','fatPerception','difficultToMaintain','activity','healthCheck','professionalConversationConfirmed']<>'{}'::jsonb
   OR EXISTS(SELECT 1 FROM jsonb_each((p_form->'answers')-ARRAY['weightKg','healthCheck','professionalConversationConfirmed']) x
    WHERE x.value<>'null'::jsonb)
   OR jsonb_typeof(p_form#>'{answers,weightKg}') NOT IN('number','null')
   OR jsonb_typeof(p_form#>'{answers,professionalConversationConfirmed}') NOT IN('boolean','null')
   OR profile_after IS DISTINCT FROM jsonb_build_object('current_protocol',NULL,'deficit_level',NULL,
    'activity_level',profile_row.activity_level,'training_frequency',profile_row.training_frequency,'hunger_level',profile_row.hunger_level)
   OR EXISTS(SELECT 1 FROM jsonb_each(targets) x WHERE x.value<>'null'::jsonb)
   OR EXISTS(SELECT 1 FROM jsonb_each(episode) x WHERE x.value<>'null'::jsonb)
   OR jsonb_typeof(p_intent->'principalConfirmed') IS DISTINCT FROM 'boolean'
   OR p_intent-ARRAY['principalConfirmed','bodyFat']<>'{}'::jsonb THEN
   RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
  END IF;
  health_answer:=p_form#>'{answers,healthCheck}';
  IF health_answer<>'null'::jsonb THEN
   IF jsonb_typeof(health_answer) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
   END IF;
   IF health_answer->>'kind'='none' THEN
    IF health_answer<>'{"kind":"none"}'::jsonb THEN
     RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
    END IF;
   ELSIF health_answer->>'kind'='risks' AND jsonb_typeof(health_answer->'items')='array'
    AND health_answer-ARRAY['kind','items']='{}'::jsonb THEN
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(health_answer->'items') x WHERE jsonb_typeof(x)<>'string') THEN
     RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
    END IF;
    SELECT array_agg(x) INTO health_items FROM jsonb_array_elements_text(health_answer->'items') x;
    IF to_jsonb(private.mobile_health_risk_set(health_items)) IS DISTINCT FROM health_answer->'items' THEN
     RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023';
    END IF;
   ELSE RAISE EXCEPTION 'invalid_mobile_clinical_health_only_effects' USING ERRCODE='22023'; END IF;
  END IF;
  IF context#>'{facts,protocol_authority,signup_origin}' IS DISTINCT FROM 'null'::jsonb
   OR context#>'{facts,protocol_authority,episode}' IS DISTINCT FROM 'null'::jsonb
   OR context#>'{facts,protocol_authority,daily_application}' IS DISTINCT FROM 'null'::jsonb
   OR context#>'{facts,protocol_authority,day_events}' IS DISTINCT FROM '[]'::jsonb THEN
   RAISE EXCEPTION 'mobile_clinical_no_plan_authority_inconsistent' USING ERRCODE='40001';
  END IF;
 ELSE
 IF phase IS NULL OR phase NOT IN('recomposicao','manutencao','ganho_massa')
  OR (phase<>'recomposicao' AND deficit IS NOT NULL) OR (deficit IS NOT NULL AND deficit NOT IN(400,500,600))
  OR (phase='recomposicao' AND deficit IS NULL AND NOT(
   before_phase='recomposicao' AND profile_row.deficit_level IS NULL AND principal='keep'
   AND formula_kcal IS NULL AND after_kcal IS NOT DISTINCT FROM before_kcal
   AND after_protein IS NOT DISTINCT FROM before_protein))
  OR (new_level IS NOT NULL AND new_level NOT IN('sedentario','leve','moderado','alto','atleta'))
  OR (new_hunger IS NOT NULL AND (jsonb_typeof(profile_after->'hunger_level')<>'string' OR new_hunger NOT IN('pouca','moderada','muita')))
  OR new_frequency NOT BETWEEN 0 AND 7 OR new_weight NOT BETWEEN 30 AND 300
  OR after_kcal<=0 OR before_kcal<=0 OR formula_kcal<=0 OR after_protein NOT BETWEEN 0 AND 9999.99
  OR before_protein NOT BETWEEN 0 AND 9999.99 OR count_after NOT BETWEEN 0 AND 9007199254740991
  OR (phase<>before_phase AND (principal NOT IN('phase_maintenance','phase_gain','phase_recomposition','recomposition_transition','gain_exit','neutral_exit')))
  OR (before_phase='recomposicao' AND phase='ganho_massa') OR (before_phase='ganho_massa' AND phase='recomposicao')
  OR (new_level IS DISTINCT FROM profile_row.activity_level::text AND
   (p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb
    OR p_form#>>'{answers,activity,activityLevel}' IS DISTINCT FROM new_level))
  OR (new_frequency IS DISTINCT FROM profile_row.training_frequency AND
   (p_form#>>'{answers,strengthSessions}' IS NULL OR
    (p_form#>>'{answers,strengthSessions}')::smallint IS DISTINCT FROM new_frequency))
  OR (new_hunger IS DISTINCT FROM profile_row.hunger_level::text AND
   (p_form#>>'{answers,hunger}' IS NULL OR p_form#>>'{answers,hunger}' IS DISTINCT FROM new_hunger)) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_effects' USING ERRCODE='22023';
 END IF;
 -- Compare input branches in the resulting phase. A separately confirmed
 -- phase already owns its shown protein projection; weight changes alone
 -- never turn an ordinary answer into acceptance of a different branch.
 SELECT c->'value' INTO protein_factors_row FROM jsonb_array_elements(context#>'{facts,calculation_config}') c
  WHERE c->>'key'='calc.protein_factors';
 SELECT c->'value' INTO recomp_factor_row FROM jsonb_array_elements(context#>'{facts,calculation_config}') c
  WHERE c->>'key'='calc.recomp_protein_g_per_kg';
 protein_branch_before:=private.mobile_clinical_protein_branch(phase,profile_row.hunger_level::text,profile_row.training_frequency,recomp_factor_row);
 protein_branch_after:=private.mobile_clinical_protein_branch(phase,new_hunger,new_frequency,recomp_factor_row);
 protein_branch_changed:=protein_branch_before IS DISTINCT FROM protein_branch_after;
 IF (principal IN('deficit_step','maintenance_step','gain_step')
   AND new_level IS DISTINCT FROM profile_row.activity_level::text)
  OR (principal IN('maintenance_step','gain_step') AND EXISTS(
   SELECT 1 FROM jsonb_array_elements(context#>'{facts,protocol_authority,routine_reviews_since_regular}') r
    WHERE r->'activity_level_changed'='true'::jsonb)) THEN
  RAISE EXCEPTION 'mobile_clinical_activity_priority' USING ERRCODE='40001';
 END IF;
 IF (phase=before_phase AND principal<>'deficit_step' AND deficit IS DISTINCT FROM profile_row.deficit_level)
  OR (principal='deficit_step' AND (preview.review_kind<>'REGULAR' OR before_phase<>'recomposicao' OR phase<>before_phase
   OR profile_row.deficit_level IS NULL
   OR NOT((profile_row.deficit_level=600 AND deficit=500) OR (profile_row.deficit_level=500 AND deficit=400))))
  OR (principal='activity' AND (phase<>before_phase OR (NOT protein_branch_changed
   AND p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb)))
  OR (principal='maintenance_step' AND (before_phase<>'manutencao' OR phase<>before_phase))
  OR (principal='gain_step' AND (before_phase<>'ganho_massa' OR phase<>before_phase))
  OR (principal='phase_gain' AND phase<>'ganho_massa')
  OR (principal='phase_recomposition' AND phase<>'recomposicao')
  OR (principal IN('phase_maintenance','recomposition_transition','neutral_exit') AND phase<>'manutencao')
  OR (principal='recomposition_transition' AND before_phase<>'recomposicao')
  OR (principal='gain_exit' AND (before_phase<>'ganho_massa' OR phase NOT IN('ganho_massa','manutencao')))
  OR (principal='neutral_exit' AND preview.review_kind<>'SAFETY')
  OR (principal='schedule_pause' AND (phase<>before_phase OR after_kcal IS DISTINCT FROM before_kcal)) THEN
  RAISE EXCEPTION 'mobile_clinical_principal_effect_mismatch' USING ERRCODE='40001';
 END IF;
 END IF;
 IF new_weight IS NOT NULL AND (new_weight NOT BETWEEN 30 AND 300 OR round(new_weight,2)<>new_weight) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_weight_precision' USING ERRCODE='22023';
 END IF;
 safety:=context#>'{facts,safety}';before_revision:=(safety->>'safety_revision')::bigint;
 clear_hold:=coalesce((safety->>'hold_active')::boolean,false) AND preview.review_kind IN('REGULAR','EARLY_FULL')
  AND p_form#>>'{answers,healthCheck,kind}'='none' AND p_form#>'{answers,professionalConversationConfirmed}'='true'::jsonb;
 clear_hold:=coalesce(clear_hold,false);
 IF (p_proposal->>'clearHold')::boolean<>clear_hold THEN
  RAISE EXCEPTION 'mobile_clinical_clear_intent_changed' USING ERRCODE='40001';
 END IF;
 IF p_form#>>'{answers,healthCheck,kind}'='risks' AND EXISTS(
  SELECT 1 FROM jsonb_array_elements_text(p_form#>'{answers,healthCheck,items}')x
  WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(safety->'items')s WHERE s->>'code'=x)) THEN
  RAISE EXCEPTION 'mobile_clinical_risk_not_declared' USING ERRCODE='40001';
 END IF;
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';body_fat:=profile_row.body_fat_percent;
 IF preview.review_kind='REGULAR' THEN
  IF candidate->>'availability' IS DISTINCT FROM 'available'
   OR p_intent#>'{bodyFat,confirmed}' IS DISTINCT FROM 'true'::jsonb
   OR p_intent#>>'{bodyFat,sourceHash}' IS DISTINCT FROM candidate->>'source_hash'
   OR (p_intent#>>'{bodyFat,meanHundredths}')::integer IS DISTINCT FROM (candidate->>'mean_hundredths')::integer THEN
   RAISE EXCEPTION 'mobile_clinical_three_photo_confirmation_required' USING ERRCODE='40001';
  END IF;
  body_fat:=(candidate->>'mean_percent')::numeric;
 ELSIF p_intent ? 'bodyFat' AND p_intent->'bodyFat'<>'null'::jsonb THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_photo_intent' USING ERRCODE='22023';
 END IF;
 effective_hold:=(safety->>'hold_active')::boolean AND NOT clear_hold;
 unknown_guard:=profile_row.birth_date IS NULL OR profile_row.height_cm IS NULL OR coalesce(new_weight,profile_row.weight_kg) IS NULL;
 IF profile_row.birth_date IS NOT NULL THEN
  age_years:=extract(year FROM day)::integer-extract(year FROM profile_row.birth_date)::integer
   -CASE WHEN to_char(day,'MMDD')<to_char(profile_row.birth_date,'MMDD') THEN 1 ELSE 0 END;
 END IF;
 bmi:=coalesce(new_weight,profile_row.weight_kg)/nullif(power(profile_row.height_cm/100,2),0);
 no_plan:=coalesce(age_years<18,false) OR (effective_hold AND (safety->>'declared_no_plan')::boolean);
 loss_guard:=coalesce(age_years>=18 AND bmi<18.5,false) OR coalesce(body_fat<=10,false);
 IF (unknown_guard OR no_plan OR loss_guard OR effective_hold) THEN
  IF new_hunger IS DISTINCT FROM profile_row.hunger_level::text
   OR new_frequency IS DISTINCT FROM profile_row.training_frequency THEN
   RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
  END IF;
  IF principal NOT IN('keep','schedule_pause') AND NOT(principal='neutral_exit' AND effective_hold AND NOT unknown_guard AND NOT no_plan AND NOT loss_guard) THEN
   RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
  END IF;
  IF principal<>'neutral_exit' AND (phase IS DISTINCT FROM before_phase OR deficit IS DISTINCT FROM profile_row.deficit_level
   OR new_level IS DISTINCT FROM profile_row.activity_level::text OR new_frequency IS DISTINCT FROM profile_row.training_frequency
   OR (after_kcal IS NOT NULL AND after_kcal IS DISTINCT FROM before_kcal)
   OR (after_protein IS NOT NULL AND after_protein IS DISTINCT FROM before_protein)) THEN
   RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
  END IF;
  IF episode#>>'{schedule,state}'='running' THEN RAISE EXCEPTION 'mobile_clinical_schedule_suspended' USING ERRCODE='40001'; END IF;
 END IF;
 IF NOT health_only THEN
 IF protein_branch_changed THEN
  IF protein_factors_row IS DISTINCT FROM '{"muita":1.6,"moderada":1.8,"pouca":1.8,"training_low":1.7,"optimal_mid_training":1.9,"optimal_high_training":2}'::jsonb THEN
   RAISE EXCEPTION 'mobile_clinical_protein_table_unverified' USING ERRCODE='40001';
  END IF;
  IF p_intent->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb OR principal NOT IN(
   'activity','phase_maintenance','phase_gain','phase_recomposition','recomposition_transition','gain_exit','schedule_reconfirm') THEN
   RAISE EXCEPTION 'mobile_clinical_protein_confirmation_required' USING ERRCODE='40001';
  END IF;
 END IF;
 IF new_level IS DISTINCT FROM profile_row.activity_level::text AND
  (p_intent->'principalConfirmed' IS DISTINCT FROM 'true'::jsonb OR principal NOT IN(
   'activity','phase_maintenance','phase_gain','phase_recomposition','recomposition_transition','gain_exit','neutral_exit','schedule_reconfirm')) THEN
  RAISE EXCEPTION 'mobile_clinical_activity_confirmation_required' USING ERRCODE='40001';
 END IF;
 IF preview.review_kind='SAFETY' AND principal<>'neutral_exit' THEN
  RAISE EXCEPTION 'mobile_clinical_safety_change_required' USING ERRCODE='22023';
 END IF;
 IF principal='neutral_exit' AND (phase<>'manutencao' OR NOT effective_hold OR no_plan OR loss_guard OR unknown_guard
  OR p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb) THEN
  RAISE EXCEPTION 'mobile_clinical_safety_block' USING ERRCODE='40001';
 END IF;
 IF preview.review_kind='ROUTINE_REVIEW' AND (principal NOT IN('keep','activity') OR phase<>before_phase
  OR deficit IS DISTINCT FROM profile_row.deficit_level OR clear_hold OR new_weight IS NOT NULL) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_routine_effects' USING ERRCODE='22023';
 END IF;
 SELECT * INTO previous FROM private.mobile_clinical_effective_episode(p_user_id,preview.signup_generation,preview.signup_epoch);
 SELECT * INTO origin FROM private.mobile_clinical_signup_origins WHERE user_id=p_user_id
  AND signup_generation=preview.signup_generation AND signup_epoch=preview.signup_epoch;
 schedule:=nullif(episode->'schedule','null'::jsonb);previous_schedule:=previous.schedule;
 previous_r:=CASE WHEN previous.event_id IS NOT NULL THEN previous.maintenance_since
  WHEN origin.phase=before_phase THEN origin.maintenance_since END;
 expected_r:=CASE WHEN phase<>before_phase THEN CASE WHEN phase='manutencao' THEN day END ELSE previous_r END;
 IF schedule IS NOT NULL AND NOT private.mobile_clinical_schedule_valid(schedule) THEN
  RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
 END IF;
 IF schedule IS NOT NULL AND schedule->>'kind'='gain_exit'
  AND formula_kcal IS DISTINCT FROM (schedule->>'maintenanceTargetKcal')::integer THEN
  RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
 END IF;
 IF principal IN('recomposition_transition','gain_exit','schedule_reconfirm') THEN
  IF schedule IS NULL OR schedule->>'state'<>'running' OR (schedule->>'startDate')::date<>day
   OR before_kcal IS NULL OR (schedule->>'startTargetKcal')::integer IS DISTINCT FROM before_kcal
   OR p_form#>'{answers,activity,activityLevelConfirmed}' IS DISTINCT FROM 'true'::jsonb
   OR (principal='recomposition_transition' AND schedule->>'kind'<>'recomp_to_maintenance')
   OR (principal='gain_exit' AND schedule->>'kind'<>'gain_exit')
   OR (principal='schedule_reconfirm' AND (previous_schedule IS NULL OR schedule->>'kind'<>previous_schedule->>'kind'))
   OR (schedule->>'kind'='recomp_to_maintenance' AND phase<>'manutencao')
   OR (schedule->>'kind'='gain_exit' AND before_phase<>'ganho_massa') THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_kcal:=CASE schedule->>'kind' WHEN 'gain_exit' THEN greatest(
   (schedule->>'maintenanceTargetKcal')::numeric,(schedule->>'startTargetKcal')::numeric-100)
   ELSE least((schedule->>'maintenanceTargetKcal')::numeric,(schedule->>'startTargetKcal')::numeric+100,formula_kcal) END;
  schedule_reached:=expected_kcal=CASE schedule->>'kind' WHEN 'gain_exit'
   THEN (schedule->>'maintenanceTargetKcal')::numeric ELSE formula_kcal END;
  IF after_kcal IS DISTINCT FROM expected_kcal OR (schedule->>'kind'='gain_exit'
   AND phase IS DISTINCT FROM (CASE WHEN schedule_reached THEN 'manutencao' ELSE 'ganho_massa' END)) THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_r:=CASE WHEN schedule_reached THEN day END;
 ELSIF principal='schedule_pause' THEN
  IF previous_schedule IS NULL OR schedule IS DISTINCT FROM jsonb_set(previous_schedule,'{state}','"suspended"')
   OR (schedule->>'kind'='gain_exit' AND NOT(unknown_guard OR no_plan OR loss_guard OR effective_hold)) THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_r:=previous_r;
 ELSE
  IF (phase=before_phase AND schedule IS DISTINCT FROM previous_schedule
    AND NOT(principal='neutral_exit' AND schedule IS NULL))
   OR (phase<>before_phase AND schedule IS NOT NULL AND schedule IS DISTINCT FROM previous_schedule)
   OR (principal IN('maintenance_step','gain_step','deficit_step') AND previous_schedule IS NOT NULL AND previous_r IS NULL) THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  -- A previously approved running plan can reach maintenance in this atomic
  -- application. Its frozen dates never establish R before that application.
  IF schedule IS NOT NULL AND schedule->>'state'='running' AND previous_r IS NULL
   AND NOT(unknown_guard OR no_plan OR loss_guard OR effective_hold) THEN
   step_count:=((day-(schedule->>'startDate')::date)/7)+1;
   IF day<(schedule->>'startDate')::date THEN
    RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
   END IF;
   expected_kcal:=CASE schedule->>'kind' WHEN 'gain_exit' THEN greatest(
    (schedule->>'maintenanceTargetKcal')::numeric,(schedule->>'startTargetKcal')::numeric-step_count::numeric*100)
    ELSE least((schedule->>'maintenanceTargetKcal')::numeric,
     (schedule->>'startTargetKcal')::numeric+step_count::numeric*100,formula_kcal) END;
   schedule_reached:=expected_kcal=CASE schedule->>'kind' WHEN 'gain_exit'
    THEN (schedule->>'maintenanceTargetKcal')::numeric ELSE formula_kcal END;
   IF after_kcal IS DISTINCT FROM expected_kcal OR phase IS DISTINCT FROM
    (CASE WHEN schedule->>'kind'='recomp_to_maintenance' OR schedule_reached THEN 'manutencao' ELSE 'ganho_massa' END) THEN
    RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
   END IF;
   expected_r:=CASE WHEN schedule_reached THEN day END;
  END IF;
 END IF;
 IF principal='neutral_exit' THEN
  IF after_kcal IS DISTINCT FROM formula_kcal THEN
   RAISE EXCEPTION 'mobile_clinical_schedule_effect_mismatch' USING ERRCODE='40001';
  END IF;
  expected_r:=day;
 END IF;
 IF coalesce(applied_day.day_closed,false) AND (phase<>before_phase OR previous_r IS NULL) THEN
  expected_r:=NULL;
 END IF;
 IF r_date IS DISTINCT FROM expected_r THEN
  RAISE EXCEPTION 'mobile_clinical_R_unproven' USING ERRCODE='40001';
 END IF;
 IF previous.event_id IS NOT NULL AND previous.phase<>before_phase THEN
  RAISE EXCEPTION 'mobile_clinical_episode_drift' USING ERRCODE='40001';
 END IF;
 IF phase<>before_phase THEN
  episode_id:=gen_random_uuid();entry_origin:='confirmed_phase_change';entry_date:=day;
  start_weight:=coalesce(new_weight,profile_row.weight_kg);start_height:=profile_row.height_cm;start_bf:=body_fat;start_frequency:=new_frequency;
  previous_steps:='{}';
 ELSIF previous.event_id IS NOT NULL THEN
  episode_id:=previous.episode_id;entry_origin:=previous.entry_origin;entry_date:=previous.entry_date;
  start_weight:=previous.start_weight_kg;start_height:=previous.start_height_cm;start_bf:=previous.start_body_fat_percent;
  start_frequency:=previous.start_training_frequency;previous_steps:=previous.ledger_steps;
 ELSIF origin.episode_id IS NOT NULL AND origin.phase=before_phase THEN
  episode_id:=origin.episode_id;entry_origin:='signup';entry_date:=origin.start_date;
  start_weight:=origin.start_weight_kg;start_height:=origin.start_height_cm;start_bf:=origin.start_body_fat_percent;
  start_frequency:=origin.start_training_frequency;previous_steps:='{}';
 ELSE
  episode_id:=gen_random_uuid();entry_origin:='legacy_unknown';previous_steps:=NULL;
 END IF;
 IF jsonb_typeof(episode->'ledgerSteps')='array' THEN
  SELECT coalesce(array_agg(value::integer),'{}') INTO steps FROM jsonb_array_elements_text(episode->'ledgerSteps');
 ELSIF episode->'ledgerSteps'='null'::jsonb THEN steps:=NULL;
 ELSE RAISE EXCEPTION 'invalid_mobile_clinical_ledger' USING ERRCODE='22023'; END IF;
 IF NOT private.mobile_clinical_ledger_valid(steps) THEN RAISE EXCEPTION 'invalid_mobile_clinical_ledger' USING ERRCODE='22023'; END IF;
 IF principal IN('maintenance_step','gain_step') THEN
  IF preview.review_kind<>'REGULAR' OR phase<>before_phase OR previous_steps IS NULL
   OR cardinality(steps) IS DISTINCT FROM cardinality(previous_steps)+1
   OR steps[1:cardinality(previous_steps)] IS DISTINCT FROM previous_steps THEN
   RAISE EXCEPTION 'mobile_clinical_episode_ledger_changed' USING ERRCODE='40001';
  END IF;
 ELSIF steps IS DISTINCT FROM previous_steps THEN RAISE EXCEPTION 'mobile_clinical_episode_ledger_changed' USING ERRCODE='40001'; END IF;
 IF phase=before_phase AND preview.review_kind<>'REGULAR' AND count_after IS DISTINCT FROM
  (CASE WHEN previous.event_id IS NOT NULL THEN previous.difficulty_count WHEN origin.phase=before_phase THEN 0 END) THEN
  RAISE EXCEPTION 'mobile_clinical_early_counter_changed' USING ERRCODE='40001';
 END IF;
 IF before_kcal IS DISTINCT FROM applied_day.calories_target
  OR before_protein IS DISTINCT FROM applied_day.protein_target THEN
  RAISE EXCEPTION 'mobile_clinical_day_target_changed' USING ERRCODE='40001';
 END IF;
 END IF;
 SELECT coalesce(max(review_no),0)+1 INTO review_number FROM private.mobile_clinical_full_receipts
  WHERE user_id=p_user_id AND signup_generation=preview.signup_generation;
 IF preview.review_kind NOT IN('REGULAR','EARLY_FULL') AND coalesce(p_form->'preference','null'::jsonb)<>'null'::jsonb THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_preference' USING ERRCODE='22023';
 END IF;
 preference_result:=private.mobile_clinical_preference_decision(p_user_id,preview.signup_generation,preview.signup_epoch,p_form->'preference');
 INSERT INTO private.mobile_clinical_write_permits VALUES(p_user_id,pg_current_xact_id(),p_preview_id);
 old_weight_marker:=current_setting('bodyflow.weight_write',true);
 PERFORM set_config('bodyflow.weight_write','recorded',true);
 UPDATE public.user_profiles SET weight_kg=coalesce(new_weight,weight_kg),
  weight_measured_at=CASE WHEN new_weight IS NOT NULL THEN greatest(observed_at,coalesce(weight_measured_at+interval '1 microsecond',observed_at)) ELSE weight_measured_at END,
  weight_instant_source=CASE WHEN new_weight IS NOT NULL THEN 'recorded' ELSE weight_instant_source END,
  current_protocol=phase::public.protocol_enum,deficit_level=deficit,activity_level=new_level::public.activity_enum,
  training_frequency=new_frequency,hunger_level=new_hunger::public.hunger_enum,
  updated_at=observed_at WHERE user_id=p_user_id;
 PERFORM set_config('bodyflow.weight_write',coalesce(old_weight_marker,''),true);
 IF new_weight IS NOT NULL THEN
  INSERT INTO private.mobile_weight_measurements(user_id,weight_kg,measured_at,instant_source,received_at,observed_timezone,authority_epoch)
   VALUES(p_user_id,new_weight,observed_at,'recorded',observed_at,zone,preview.signup_epoch);
 END IF;
 IF preview.review_kind='REGULAR' THEN
  UPDATE public.user_profiles SET body_fat_percent=body_fat,body_fat_measured_at=observed_at,updated_at=observed_at WHERE user_id=p_user_id;
 END IF;
 current_cycle:=preview.cycle_id;
 IF preview.review_kind IN('REGULAR','EARLY_FULL','SAFETY') THEN
  IF preview.review_kind='SAFETY' THEN
   current_cycle:=(context#>>'{facts,cycle,cycle_id}')::uuid;
  END IF;
  IF current_cycle IS NOT NULL THEN
   FOR consent_row IN SELECT acceptance_id FROM private.mobile_reevaluation_photo_consents
    WHERE user_id=p_user_id AND cycle_id=current_cycle ORDER BY acceptance_id LOOP
    PERFORM private.seal_mobile_reevaluation_photo_disposition_at(p_user_id,current_cycle,consent_row.acceptance_id,
     CASE WHEN preview.review_kind='SAFETY' THEN 'cycle_changed' ELSE 'completed' END,observed_at);
   END LOOP;
  END IF;
  IF preview.review_kind='SAFETY' THEN
   UPDATE private.mobile_reevaluation_cycles SET status='invalidated',invalidated_at=observed_at,revision=revision+1
    WHERE user_id=p_user_id AND status IN('open','collecting','review_ready');
   INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,kind,base_date,due_date,
    timezone_at_open,status,opened_at,completed_at)
    VALUES(p_user_id,preview.signup_generation,preview.signup_epoch,'SAFETY',base_day,base_day+14,
     context#>>'{facts,anchor,clock,timezone}','completed',observed_at,observed_at) RETURNING cycle_id INTO current_cycle;
  ELSE
   UPDATE private.mobile_reevaluation_cycles SET status='completed',completed_at=observed_at,revision=revision+1
    WHERE user_id=p_user_id AND cycle_id=current_cycle AND status IN('open','collecting','review_ready');
   IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_cycle_changed' USING ERRCODE='40001'; END IF;
  END IF;
  SELECT revision INTO STRICT cycle_revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=current_cycle;
 END IF;
 safety_revision:=before_revision+CASE WHEN clear_hold THEN 1 ELSE 0 END;
 IF clear_hold THEN
  INSERT INTO private.mobile_clinical_health_clear_receipts VALUES(p_user_id,p_preview_id,before_revision,safety_revision,true,observed_at);
  UPDATE private.mobile_health_hold_states s SET safety_revision=s.safety_revision+1,hold_active=false,
   items='{}',last_declared_at=observed_at WHERE s.user_id=p_user_id AND s.safety_revision=before_revision;
  IF NOT FOUND THEN RAISE EXCEPTION 'mobile_clinical_safety_revision_changed' USING ERRCODE='40001'; END IF;
 END IF;
 IF after_kcal IS NOT NULL AND NOT coalesce(applied_day.day_closed,false) THEN
  INSERT INTO public.daily_snapshots AS actual(user_id,date,calories_target,protein_target,current_protocol,updated_at)
  VALUES(p_user_id,day,after_kcal,after_protein,phase::public.protocol_enum,observed_at)
  ON CONFLICT(user_id,date) DO UPDATE SET calories_target=excluded.calories_target,protein_target=excluded.protein_target,
   current_protocol=excluded.current_protocol,updated_at=excluded.updated_at WHERE NOT actual.day_closed
  RETURNING id INTO written_day_id;
  IF written_day_id IS NULL THEN
   RAISE EXCEPTION 'mobile_clinical_day_target_changed' USING ERRCODE='40001';
  END IF;
 END IF;
 IF written_day_id IS NOT NULL THEN
  INSERT INTO private.mobile_clinical_day_events(user_id,date,review_id,phase,deficit_level,calories_target,protein_target,
   formula_target,effective_adjustment,schedule,applied_at,rule_version)
  VALUES(p_user_id,day,p_preview_id,phase,deficit,after_kcal,after_protein,formula_kcal,
   after_kcal-formula_kcal,schedule,observed_at,'clinical-v1');
 END IF;
 UPDATE public.user_progress SET current_weight=coalesce(new_weight,current_weight),
  current_bf_percent=CASE WHEN preview.review_kind='REGULAR' THEN body_fat ELSE current_bf_percent END,
  next_reevaluation=CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN (day+14)::timestamp AT TIME ZONE zone ELSE next_reevaluation END,
  updated_at=observed_at WHERE user_id=p_user_id;
 IF NOT health_only THEN
 INSERT INTO private.mobile_clinical_episode_events(user_id,signup_generation,signup_epoch,review_id,event_no,previous_event_id,
  episode_id,phase,entry_origin,entry_date,start_weight_kg,start_height_cm,start_body_fat_percent,start_training_frequency,
  maintenance_since,deficit_level,difficulty_count,ledger_steps,schedule,applied_at,rule_version)
 VALUES(p_user_id,preview.signup_generation,preview.signup_epoch,p_preview_id,coalesce(previous.event_no,0)+1,previous.event_id,
  episode_id,phase,entry_origin,entry_date,start_weight,start_height,start_bf,start_frequency,r_date,deficit,count_after,steps,
  nullif(episode->'schedule','null'::jsonb),observed_at,'clinical-v1');
 END IF;
 result:=jsonb_build_object('version',1,'user_id',p_user_id,'review_id',p_preview_id,'kind',preview.review_kind,
  'status','confirmed','principal',principal,'completed_at',to_char(observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'cycle_id',current_cycle,'cycle_revision',cycle_revision::text,'safety_revision',safety_revision::text,
  'next_due_date',CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN day+14 ELSE base_day+14 END,
  'targets',targets,'body_fat_percent',CASE WHEN preview.review_kind='REGULAR' THEN body_fat ELSE NULL END,
  'preference',preference_result);
 INSERT INTO private.mobile_clinical_full_receipts(user_id,review_id,preview_id,signup_generation,signup_epoch,review_no,
  kind,cycle_id,previous_full_id,base_before,base_after,timezone_at_completion,calculation_date,completed_at,final_cycle_revision,
  principal,activity_level_changed,context_hash,input_hash,form,intent,proposal,result,body_fat_mean,body_fat_source_hash,rule_version)
 VALUES(p_user_id,p_preview_id,p_preview_id,preview.signup_generation,preview.signup_epoch,review_number,preview.review_kind,
  current_cycle,previous_full,base_day,CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN day END,zone,day,observed_at,cycle_revision,
  principal,new_level IS DISTINCT FROM profile_row.activity_level::text,preview.context_hash,input_hash,p_form,p_intent,p_proposal,result,
  CASE WHEN preview.review_kind='REGULAR' THEN body_fat END,CASE WHEN preview.review_kind='REGULAR' THEN candidate->>'source_hash' END,'clinical-v1');
 IF preview.review_kind='REGULAR' THEN
  INSERT INTO private.mobile_clinical_body_fat_receipts VALUES(p_user_id,p_preview_id,preview.signup_generation,preview.signup_epoch,
   current_cycle,(candidate->>'acceptance_id')::uuid,body_fat,candidate->>'source_hash',candidate->'sources',observed_at);
  INSERT INTO private.mobile_clinical_body_fat_heads VALUES(p_user_id,p_preview_id)
   ON CONFLICT(user_id) DO UPDATE SET review_id=excluded.review_id;
 END IF;
 PERFORM private.apply_mobile_clinical_preference(p_user_id,p_preview_id);
 INSERT INTO private.mobile_clinical_confirmation_keys VALUES(p_user_id,p_operation_key,p_preview_id,input_hash,observed_at);
 DELETE FROM private.mobile_clinical_write_permits WHERE user_id=p_user_id AND transaction_id=pg_current_xact_id();
 PERFORM private.mobile_health_state_wire(p_user_id);
 PERFORM private.mobile_reevaluation_context_at(p_user_id,observed_at);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_profile_write_fence(),private.mobile_clinical_invalidate_body_fat(),
 private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.mobile_health_state_wire(p_user_id uuid) RETURNS jsonb
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
     AND (r.safety_revision>state.safety_revision OR r.declared_at>state.last_declared_at))
   OR (NOT state.hold_active AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_health_clear_receipts c
     JOIN private.mobile_clinical_full_receipts f ON f.user_id=c.user_id AND f.review_id=c.review_id
     WHERE c.user_id=p_user_id AND c.safety_revision=state.safety_revision AND c.cleared_at=state.last_declared_at
       AND f.kind IN('REGULAR','EARLY_FULL') AND f.completed_at=c.cleared_at
       AND f.form#>>'{answers,healthCheck,kind}'='none'
       AND f.form#>'{answers,professionalConversationConfirmed}'='true'::jsonb
       AND f.result->>'safety_revision'=c.safety_revision::text))
   OR EXISTS(SELECT 1 FROM private.mobile_clinical_health_clear_receipts c WHERE c.user_id=p_user_id
     AND (c.safety_revision>state.safety_revision OR c.cleared_at>state.last_declared_at
       OR (c.safety_revision=state.safety_revision AND state.hold_active))) THEN
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
CREATE TABLE private.mobile_clinical_start_requests (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 requested_kind text NOT NULL CHECK(requested_kind IN('REGULAR','EARLY_FULL')),
 early_reason text,
 signup_generation uuid NOT NULL,
 cycle_id uuid NOT NULL,
 opened_at timestamptz NOT NULL CHECK(isfinite(opened_at)),
 PRIMARY KEY(user_id,operation_key),
 FOREIGN KEY(user_id,signup_generation,cycle_id) REFERENCES private.mobile_reevaluation_cycles(user_id,signup_generation,cycle_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((requested_kind='EARLY_FULL')=(early_reason IS NOT NULL)),
 CHECK(early_reason IS NULL OR early_reason IN('gain_review_notice','not_well_with_plan'))
);
ALTER TABLE private.mobile_clinical_start_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_start_requests FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_start_request_immutable BEFORE UPDATE OR DELETE ON private.mobile_clinical_start_requests
 FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();
CREATE FUNCTION private.start_mobile_clinical_full_at(p_user_id uuid,p_operation_key uuid,p_kind text,p_reason text,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb;previous private.mobile_clinical_start_requests%ROWTYPE;
 cycle private.mobile_reevaluation_cycles%ROWTYPE;observed_at timestamptz;generation_id uuid;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_operation_key IS NULL OR p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL')
  OR (p_kind='REGULAR' AND p_reason IS NOT NULL)
  OR (p_kind='EARLY_FULL' AND (p_reason IS NULL OR p_reason NOT IN('gain_review_notice','not_well_with_plan'))) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_start' USING ERRCODE='22023';
 END IF;
 context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 generation_id:=(context->>'signup_generation')::uuid;
 -- Kind is determined at conclusion. An abandoned early occurrence cannot
 -- bypass regular photos/window rules after a full fortnight has elapsed.
 IF context#>>'{cycle,kind}'='EARLY_FULL'
  AND ((context->>'observed_at')::timestamptz AT TIME ZONE (context#>>'{clock,timezone}'))::date>=(context#>>'{clock,due_date}')::date
  AND ((context->>'observed_at')::timestamptz AT TIME ZONE (SELECT timezone FROM public.users WHERE id=p_user_id))::date>=(context#>>'{clock,due_date}')::date THEN
  UPDATE private.mobile_reevaluation_cycles SET kind='REGULAR',revision=revision+1
   WHERE user_id=p_user_id AND cycle_id=(context#>>'{cycle,id}')::uuid AND kind='EARLY_FULL' AND status IN('open','collecting','review_ready');
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 END IF;
 SELECT * INTO previous FROM private.mobile_clinical_start_requests WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF previous.requested_kind<>p_kind OR previous.early_reason IS DISTINCT FROM p_reason
   OR previous.signup_generation IS DISTINCT FROM generation_id
   OR previous.cycle_id::text IS DISTINCT FROM context#>>'{cycle,id}' THEN
   RAISE EXCEPTION 'mobile_clinical_start_changed' USING ERRCODE='40001';
  END IF;
  RETURN private.mobile_reevaluation_state(context);
 END IF;
 IF generation_id IS NULL THEN RETURN private.mobile_reevaluation_state(context); END IF;
 IF p_kind='REGULAR' OR context->>'reason' IS NULL OR context#>>'{cycle,kind}'='REGULAR' THEN
  PERFORM private.start_mobile_reevaluation_cycle_at(p_user_id,p_operation_key,p_observed_at);
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 ELSE
  IF p_reason='gain_review_notice' AND NOT EXISTS(SELECT 1 FROM public.user_profiles
   WHERE user_id=p_user_id AND current_protocol='ganho_massa') THEN
   RAISE EXCEPTION 'invalid_mobile_clinical_early_reason' USING ERRCODE='22023';
  END IF;
  IF context->'cycle'='null'::jsonb THEN
   observed_at:=(context->>'observed_at')::timestamptz;
   UPDATE private.mobile_reevaluation_cycles SET status='invalidated',invalidated_at=observed_at,revision=revision+1
    WHERE user_id=p_user_id AND signup_generation<>generation_id AND status IN('open','collecting','review_ready');
   INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,kind,base_date,due_date,
    timezone_at_open,status,opened_at)
   VALUES(p_user_id,generation_id,(context->>'signup_epoch')::uuid,'EARLY_FULL',
    (context#>>'{clock,base_date}')::date,(context#>>'{clock,due_date}')::date,context#>>'{clock,timezone}','open',observed_at)
   RETURNING * INTO cycle;
   context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  END IF;
 END IF;
 IF context#>>'{cycle,id}' IS NULL THEN RETURN private.mobile_reevaluation_state(context); END IF;
 INSERT INTO private.mobile_clinical_start_requests VALUES(p_user_id,p_operation_key,p_kind,p_reason,
  generation_id,(context#>>'{cycle,id}')::uuid,(context->>'observed_at')::timestamptz);
 RETURN private.mobile_reevaluation_state(context);
END $$;
REVOKE ALL ON FUNCTION private.start_mobile_clinical_full_at(uuid,uuid,text,text,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.mobile_reevaluation_photo_context(
  p_user_id uuid,p_cycle_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; observed_at timestamptz; doc public.legal_documents%ROWTYPE;
  policy private.mobile_reevaluation_photo_policies%ROWTYPE;
  consent private.mobile_reevaluation_photo_consents%ROWTYPE;
  current_locale text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_cycle_id IS NULL THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_input' USING ERRCODE='22023';
  END IF;
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  IF context->>'reason' IS NOT NULL OR context#>>'{cycle,id}' IS DISTINCT FROM p_cycle_id::text
    OR context#>>'{cycle,kind}' IS DISTINCT FROM 'REGULAR' THEN
    RAISE EXCEPTION 'mobile_reevaluation_cycle_changed' USING ERRCODE='40001';
  END IF;
  SELECT u.locale INTO current_locale FROM public.users u WHERE u.id=p_user_id;
  -- Prevent a concurrent publication from slipping between current-document
  -- selection and acceptance. Policy activation follows the same table order.
  LOCK TABLE public.legal_documents IN SHARE MODE;
  LOCK TABLE private.mobile_reevaluation_photo_policies IN SHARE MODE;
  -- Either table lock may have waited on publication/configuration. Capture
  -- time again under all locks, so newly effective text is never skipped.
  context:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
  observed_at:=(context->>'observed_at')::timestamptz;
  SELECT d.* INTO doc FROM public.legal_documents d
    WHERE d.document_key='body_photo_reevaluation_consent' AND d.locale=current_locale
      AND d.required_from<=observed_at
    ORDER BY d.required_from DESC,d.created_at DESC,d.id DESC LIMIT 1;
  IF FOUND THEN
    IF NOT isfinite(doc.required_from) THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_document_corrupt' USING ERRCODE='XX001';
    END IF;
    SELECT p.* INTO policy FROM private.mobile_reevaluation_photo_policies p
      WHERE p.document_id=doc.id AND p.enabled;
  END IF;
  SELECT a.* INTO consent FROM private.mobile_reevaluation_photo_consents a
    WHERE a.user_id=p_user_id AND a.signup_generation=(context->>'signup_generation')::uuid
      AND a.cycle_id=p_cycle_id AND a.revoked_at IS NULL;
  IF FOUND AND (consent.accepted_at>observed_at OR consent.last_activity_at>observed_at) THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_corrupt' USING ERRCODE='XX001';
  END IF;
  RETURN jsonb_build_object('cycle_revision',context#>>'{cycle,revision}',
    'signup_generation',context->'signup_generation','observed_at',context->'observed_at',
    'document',CASE WHEN policy.document_id IS NULL THEN 'null'::jsonb
      ELSE to_jsonb(doc)||jsonb_build_object('idle_timeout_seconds',policy.idle_timeout_seconds) END,
    'current_acceptance',CASE WHEN consent.acceptance_id IS NULL THEN 'null'::jsonb ELSE to_jsonb(consent) END);
END $$;
COMMIT;

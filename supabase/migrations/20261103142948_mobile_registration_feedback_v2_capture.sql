-- Dormant service-only feedback v2 substrate. No registration, reward or daily writer.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_registration_feedback') IS NULL
  OR to_regprocedure('private.assert_trusted_backend()') IS NULL
  OR to_regprocedure('private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)') IS NULL
  OR to_regprocedure('public.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NULL
  OR to_regprocedure('public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)') IS NULL THEN
  RAISE EXCEPTION 'feedback_v2_capture_requires_current_substrate' USING ERRCODE='42501';
 END IF;
END $preflight$;

-- Private stable observation projection only. It does not establish ownership,
-- clinical eligibility or registration authority; trusted capture/commit does.
CREATE FUNCTION private.mobile_registration_feedback_v2_context_binding(p_context jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $binding$
 SELECT jsonb_object_agg(k,coalesce(p_context->k,'null'::jsonb))
 FROM unnest(ARRAY['user_id','mode','profile_present','profile_hash','epoch','signup_generation','generation_authority','generation_token','first_completion','date','timezone','body','assessment','missing','health_state','phase_origin','calculation_config']::text[]) AS keys(k)
$binding$;
REVOKE ALL ON FUNCTION private.mobile_registration_feedback_v2_context_binding(jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_registration_feedback_v2_source_binding(p_context jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT (p_context-'clinical')||jsonb_build_object('clinical',private.mobile_registration_feedback_v2_context_binding(p_context->'clinical'))
$$;
REVOKE ALL ON FUNCTION private.mobile_registration_feedback_v2_source_binding(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE private.mobile_registration_feedback_v2 (
 registration_id uuid PRIMARY KEY REFERENCES public.pending_registrations(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 proposal_hash text NOT NULL CHECK(proposal_hash ~ '^[a-f0-9]{64}$'),
 source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 feedback jsonb NOT NULL CHECK(jsonb_typeof(feedback)='object' AND feedback->>'schema'='registration.feedback.v2'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX mobile_registration_feedback_v2_owner ON private.mobile_registration_feedback_v2(user_id);
ALTER TABLE private.mobile_registration_feedback_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_registration_feedback_v2 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.guard_mobile_registration_feedback_v2() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.pending_registrations WHERE id=OLD.registration_id)
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'immutable_registration_feedback_v2' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION private.guard_mobile_registration_feedback_v2() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_mobile_registration_feedback_v2 BEFORE UPDATE OR DELETE ON private.mobile_registration_feedback_v2
 FOR EACH ROW EXECUTE FUNCTION private.guard_mobile_registration_feedback_v2();

CREATE FUNCTION private.capture_mobile_registration_feedback_v2(p_owner uuid,p_registration uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE p public.pending_registrations%ROWTYPE;m public.meal_logs%ROWTYPE;w public.workout_logs%ROWTYPE;s public.daily_snapshots%ROWTYPE;
 a private.mobile_workout_proposal_admissions%ROWTYPE;candidate private.mobile_workout_proposal_admissions%ROWTYPE;
 authority private.workout_strength_authority_epochs%ROWTYPE;l private.workout_strength_lifecycles%ROWTYPE;o private.workout_strength_operations%ROWTYPE;
 clinical jsonb;logs jsonb:='[]';progress jsonb;proof jsonb;item jsonb;matched jsonb;used text[]:='{}';
 source_time timestamptz;source_day date;zone text;provider text;v_operation_key text;resolved jsonb;gap jsonb;
 log_snapshot uuid;admissions integer:=0;kind text;protected boolean;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'feedback_v2_requires_read_committed' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR p_registration IS NULL THEN RETURN NULL; END IF;
 -- The current clinical reader takes the owner lane then this config lock.
 -- Pre-acquire it fail-fast, so it cannot wait on a config writer behind us.
 LOCK TABLE public.global_config IN SHARE MODE NOWAIT;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_owner::text||':workouts',0));
 PERFORM 1 FROM public.users WHERE id=p_owner AND status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO p FROM public.pending_registrations WHERE id=p_registration AND user_id=p_owner FOR SHARE NOWAIT;
 IF NOT FOUND OR p.status<>'confirmed' THEN RETURN NULL; END IF;
 kind:=p.proposal->>'kind';provider:=p.proposal->>'source_provider_message_id';zone:=p.proposal->>'source_timezone';
 IF kind IS NULL OR kind NOT IN('meal','workout') OR provider IS NULL OR btrim(provider)='' OR length(provider)>512
  OR zone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN RETURN NULL; END IF;
 BEGIN
  source_time:=(p.proposal->>'source_timestamp')::timestamptz;source_day:=(p.proposal->>'source_local_date')::date;
  IF source_time IS NULL OR NOT isfinite(source_time) OR source_day IS NULL OR NOT isfinite(source_day)
   OR (source_time AT TIME ZONE zone)::date<>source_day THEN RETURN NULL; END IF;
 EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN NULL; END;
 IF kind='meal' THEN
  IF p.proposal->>'registration_origin' IS DISTINCT FROM 'mobile_app' OR jsonb_typeof(p.proposal->'items') IS DISTINCT FROM 'array'
   OR jsonb_array_length(p.proposal->'items') NOT BETWEEN 1 AND 30 THEN RETURN NULL; END IF;
  FOR m IN SELECT * FROM public.meal_logs WHERE user_id=p_owner AND raw_provider_message_id=provider ORDER BY id FOR SHARE NOWAIT LOOP
   IF m.consumed_at IS DISTINCT FROM source_time OR m.meal_type::text IS DISTINCT FROM p.proposal->>'mealType'
    OR (log_snapshot IS NOT NULL AND m.snapshot_id IS DISTINCT FROM log_snapshot) THEN RETURN NULL; END IF;
   log_snapshot:=m.snapshot_id;logs:=logs||jsonb_build_array(to_jsonb(m));
   IF jsonb_array_length(logs)>30 THEN RETURN NULL; END IF;
  END LOOP;
  IF jsonb_array_length(logs)<>jsonb_array_length(p.proposal->'items') OR log_snapshot IS NULL THEN RETURN NULL; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p.proposal->'items') LOOP
   IF item->>'nutrition_source' IS NULL OR item->>'nutrition_source' NOT IN('taco','canonical_exact','canonical_fuzzy','canonical_composite','canonical_composite_partial','rule_based','user_correction','history','user_kcal','product_label','pending_approved','llm_estimate') THEN RETURN NULL; END IF;
   SELECT value INTO matched FROM jsonb_array_elements(logs) WHERE NOT(value->>'id'=ANY(used))
    AND value->>'food_name'=item->>'name' AND value->>'source'=item->>'nutrition_source'
    AND value->'quantity_g'=to_jsonb(round((item->>'quantity_g')::numeric,2))
    AND value->'kcal'=to_jsonb(round((item->>'kcal')::numeric,2))
    AND value->'protein_g'=to_jsonb(round((item->>'protein_g')::numeric,2))
    AND value->'carbs_g'=to_jsonb(round((item->>'carbs_g')::numeric,2))
    AND value->'fat_g'=to_jsonb(round((item->>'fat_g')::numeric,2)) ORDER BY value->>'id' LIMIT 1;
   IF matched IS NULL THEN RETURN NULL; END IF;used:=array_append(used,matched->>'id');
  END LOOP;
 ELSE
  protected:=p.workout_ui_admission_id IS NOT NULL OR public.mobile_workout_registration_pending_is_protected(p_owner,p_registration);
  IF protected THEN
   SELECT * INTO authority FROM private.workout_strength_authority_epochs WHERE user_id=p_owner FOR SHARE NOWAIT;
   FOR candidate IN SELECT * FROM private.mobile_workout_proposal_admissions WHERE user_id=p_owner AND pending_id=p_registration ORDER BY admission_id FOR SHARE NOWAIT LOOP
    a:=candidate;admissions:=admissions+1;
   END LOOP;
   IF admissions<>1 OR a.content_revision IS NULL OR authority.user_id IS NULL OR a.epoch IS DISTINCT FROM authority.epoch
    OR p.workout_ui_admission_id IS DISTINCT FROM a.admission_id OR a.confirmed_lifecycle_key IS NULL THEN RETURN NULL; END IF;
   IF (a.content_revision=0 AND (provider COLLATE "C") IS DISTINCT FROM (a.request_key COLLATE "C"))
    OR (a.content_revision>0 AND NOT EXISTS(SELECT 1 FROM private.mobile_workout_registration_edit_receipts WHERE user_id=p_owner
     AND admission_id=a.admission_id AND request_key=(provider COLLATE "C") AND result_revision=a.content_revision)) THEN RETURN NULL; END IF;
   SELECT * INTO l FROM private.workout_strength_lifecycles WHERE user_id=p_owner AND lifecycle_key=a.confirmed_lifecycle_key FOR SHARE NOWAIT;
   IF NOT FOUND OR l.closed_at IS NOT NULL OR authority.current_lifecycle_key IS DISTINCT FROM l.lifecycle_key THEN RETURN NULL; END IF;
   v_operation_key:='ui:'||a.admission_id::text||':r:'||a.content_revision::text;
   SELECT op.* INTO o FROM private.workout_strength_operations op WHERE op.user_id=p_owner AND op.lifecycle_key=l.lifecycle_key
    AND op.operation_kind='capture' AND op.operation_key=(v_operation_key COLLATE "C")
    AND op.original_operation_type=(p.proposal->>'workoutType' COLLATE "C") FOR SHARE NOWAIT;
   IF NOT FOUND OR o.live_workout_log_id IS NULL THEN RETURN NULL; END IF;
   resolved:=public.resolve_confirmed_workout_strength_capture(p_owner,l.lifecycle_key,v_operation_key,p.proposal->>'workoutType');
   gap:=jsonb_build_object('status','unavailable','reason','legacy_provenance_gap','confirmedWorkoutLogID',o.live_workout_log_id::text);
   IF (o.capture_outcome='fact' AND resolved->>'status' IS DISTINCT FROM 'reuse_existing')
    OR (o.capture_outcome='legacy_provenance_gap' AND resolved IS DISTINCT FROM gap)
    OR o.capture_outcome NOT IN('fact','legacy_provenance_gap') THEN RETURN NULL; END IF;
   SELECT * INTO w FROM public.workout_logs WHERE id=o.live_workout_log_id AND user_id=p_owner FOR SHARE NOWAIT;
   IF NOT FOUND THEN RETURN NULL; END IF;
   proof:=jsonb_build_object('kind','ui-v1','epoch',authority.epoch,'admission_id',a.admission_id,'content_revision',a.content_revision,
    'lifecycle_key',l.lifecycle_key,'operation_key',v_operation_key,'workout_id',w.id,'resolver',resolved);
  ELSE
   -- Direct-key legacy capture is admitted only when it is uniquely proven.
   SELECT count(*) INTO admissions FROM public.workout_logs WHERE user_id=p_owner AND raw_provider_message_id=provider;
   IF admissions<>1 THEN RETURN NULL; END IF;
   SELECT * INTO w FROM public.workout_logs WHERE user_id=p_owner AND raw_provider_message_id=provider FOR SHARE NOWAIT;
   proof:=jsonb_build_object('kind','direct-key','operation_key',provider,'workout_id',w.id);
  END IF;
  IF w.workout_type IS DISTINCT FROM p.proposal->>'workoutType' OR w.performed_at IS DISTINCT FROM source_time OR w.snapshot_id IS NULL THEN RETURN NULL; END IF;
  log_snapshot:=w.snapshot_id;logs:=jsonb_build_array(to_jsonb(w));
 END IF;
 SELECT * INTO s FROM public.daily_snapshots WHERE id=log_snapshot AND user_id=p_owner FOR SHARE NOWAIT;
 IF NOT FOUND OR s.date IS DISTINCT FROM source_day THEN RETURN NULL; END IF;
 SELECT to_jsonb(x) INTO progress FROM public.user_progress x WHERE user_id=p_owner FOR SHARE NOWAIT;
 clinical:=private.capture_mobile_current_clinical_state_at(p_owner,'profile',NULL,NULL,NULL);
 RETURN jsonb_build_object('version',1,'user_id',p_owner,'registration_id',p_registration,
  'confirmed',jsonb_build_object('id',p.id,'user_id',p.user_id,'status',p.status,'proposal',p.proposal)||CASE WHEN kind='workout' AND protected THEN jsonb_build_object('workout_protocol','ui-v1','confirmedWorkoutId',w.id) ELSE '{}'::jsonb END,
  'logs',logs,'workout_proof',proof,'snapshot',to_jsonb(s),'progress',progress,'clinical',clinical);
END $$;
REVOKE ALL ON FUNCTION private.capture_mobile_registration_feedback_v2(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.capture_mobile_registration_feedback_v2(p_user_id uuid,p_registration_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE context jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 context:=private.capture_mobile_registration_feedback_v2(p_user_id,p_registration_id);
 IF context IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb; END IF;
 RETURN jsonb_build_object('action','available','context',context);
END $$;
REVOKE ALL ON FUNCTION public.capture_mobile_registration_feedback_v2(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.capture_mobile_registration_feedback_v2(uuid,uuid) TO service_role;
COMMIT;

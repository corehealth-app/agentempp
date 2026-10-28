-- Dormant clinical snapshot and hash-only preview journal. No public RPC,
-- clinical conclusion, policy activation or target write is introduced here.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres'
   OR to_regclass('private.mobile_weight_measurements') IS NULL
   OR to_regprocedure('private.mobile_health_state_wire(uuid)') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_requires_existing_authority' USING ERRCODE='42501';
 END IF;
END $$;

CREATE TABLE private.mobile_clinical_previews (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 preview_id uuid NOT NULL DEFAULT gen_random_uuid(),
 review_kind text NOT NULL CHECK(review_kind IN('REGULAR','EARLY_FULL','ROUTINE_REVIEW','SAFETY')),
 signup_generation uuid NOT NULL,
 signup_epoch uuid NOT NULL,
 cycle_id uuid,
 context_hash text NOT NULL CHECK(context_hash ~ '^[0-9a-f]{64}$'),
 form_hash text NOT NULL CHECK(form_hash ~ '^[0-9a-f]{64}$'),
 intent_hash text NOT NULL CHECK(intent_hash ~ '^[0-9a-f]{64}$'),
 proposal_hash text NOT NULL CHECK(proposal_hash ~ '^[0-9a-f]{64}$'),
 rule_version text NOT NULL CHECK(rule_version='clinical-v1'),
 created_at timestamptz NOT NULL CHECK(isfinite(created_at)),
 valid_until timestamptz NOT NULL CHECK(isfinite(valid_until) AND valid_until>created_at),
 PRIMARY KEY(user_id,operation_key), UNIQUE(user_id,preview_id), UNIQUE(preview_id),
 FOREIGN KEY(user_id,signup_generation)
  REFERENCES private.mobile_signup_strength_completion_receipts(user_id,admission_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,signup_generation,cycle_id)
  REFERENCES private.mobile_reevaluation_cycles(user_id,signup_generation,cycle_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((review_kind IN('REGULAR','EARLY_FULL'))=(cycle_id IS NOT NULL))
);
ALTER TABLE private.mobile_clinical_previews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_clinical_previews FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.mobile_clinical_evidence_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'mobile_clinical_evidence_immutable' USING ERRCODE='55000';
END $$;
CREATE TRIGGER mobile_clinical_preview_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_previews FOR EACH ROW EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

-- All timestamps and bigint revisions have one deterministic wire format.
-- Callers supply fixed, reviewed column lists; no SQL identifiers are executed.
CREATE FUNCTION private.mobile_clinical_canonical_row(p_row jsonb,p_timestamps text[],p_bigints text[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE k text; result jsonb:=p_row;
BEGIN
 IF p_row IS NULL OR p_row='null'::jsonb THEN RETURN 'null'::jsonb; END IF;
 FOREACH k IN ARRAY p_timestamps LOOP
  IF p_row->>k IS NOT NULL THEN
   result:=jsonb_set(result,ARRAY[k],to_jsonb(to_char((p_row->>k)::timestamptz
    AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
  END IF;
 END LOOP;
 FOREACH k IN ARRAY p_bigints LOOP
  IF p_row->>k IS NOT NULL THEN result:=jsonb_set(result,ARRAY[k],to_jsonb(p_row->>k)); END IF;
 END LOOP;
 RETURN result;
END $$;

-- Extended by subsequent typed clinical authorities. The empty object makes
-- absence explicit; no profile-derived episode/R/ledger is inferred here.
CREATE FUNCTION private.mobile_clinical_protocol_authority(p_user_id uuid,p_generation uuid,p_epoch uuid,p_cycle_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT '{}'::jsonb
$$;

CREATE FUNCTION private.capture_mobile_clinical_context_at(
 p_user_id uuid,p_kind text,p_cycle_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO, YMD' AS $$
DECLARE owner_row public.users%ROWTYPE; profile_row public.user_profiles%ROWTYPE;
 observed_at timestamptz; first_day date; today date; deadline timestamptz; next_boundary timestamptz;
 anchor jsonb; cycle_row private.mobile_reevaluation_cycles%ROWTYPE; generation_id uuid;
 scope_cycle_id uuid; photo_context jsonb; photo_availability jsonb; facts jsonb;
 profile_json jsonb; progress_json jsonb; day_json jsonb; history_json jsonb; calc_json jsonb;
 documents_json jsonb; policies_json jsonb; consents_json jsonb; sources_json jsonb;
 allocations_json jsonb; media_json jsonb; tickets_json jsonb; attempts_json jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','ROUTINE_REVIEW','SAFETY','APPLICATION')
  OR ((p_kind IN('REGULAR','EARLY_FULL'))<>(p_cycle_id IS NOT NULL)) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_context' USING ERRCODE='22023';
 END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO STRICT owner_row FROM public.users WHERE id=p_user_id;
 IF owner_row.timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=owner_row.timezone) THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_timezone' USING ERRCODE='22023';
 END IF;
 observed_at:=coalesce(p_observed_at,clock_timestamp());
 IF NOT isfinite(observed_at) OR extract(year FROM observed_at) NOT BETWEEN 1 AND 9998 THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_clock' USING ERRCODE='22023';
 END IF;
 first_day:=(observed_at AT TIME ZONE owner_row.timezone)::date;
 -- Never wait for a legacy advisory/profile lock after holding users. Reset
 -- may own :workouts before users; that lock must not be acquired here.
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':weight',0))
  OR NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':'||first_day::text,0))
  OR NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':daily-close',0)) THEN
  RAISE EXCEPTION 'mobile_clinical_busy' USING ERRCODE='55P03';
 END IF;
 BEGIN
  PERFORM p.user_id FROM public.user_profiles p WHERE p.user_id=p_user_id FOR UPDATE NOWAIT;
  PERFORM d.id FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=first_day
   ORDER BY d.id FOR UPDATE NOWAIT;
  PERFORM p.user_id FROM public.user_progress p WHERE p.user_id=p_user_id FOR UPDATE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'mobile_clinical_busy' USING ERRCODE='55P03';
 END;
 -- Protect publication, policy and the complete calc.* set, including inserts.
 LOCK TABLE public.legal_documents IN SHARE MODE;
 LOCK TABLE private.mobile_reevaluation_photo_policies IN SHARE MODE;
 LOCK TABLE public.global_config IN SHARE MODE;
 anchor:=private.mobile_reevaluation_context_at(p_user_id,p_observed_at);
 IF anchor->>'signup_generation' IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_anchor_unavailable' USING ERRCODE='40001';
 END IF;
 generation_id:=(anchor->>'signup_generation')::uuid;
 scope_cycle_id:=(anchor#>>'{cycle,id}')::uuid;
 IF p_kind IN('REGULAR','EARLY_FULL') THEN
  IF scope_cycle_id IS DISTINCT FROM p_cycle_id THEN
   RAISE EXCEPTION 'mobile_clinical_cycle_changed' USING ERRCODE='40001';
  END IF;
  SELECT * INTO STRICT cycle_row FROM private.mobile_reevaluation_cycles WHERE cycle_id=scope_cycle_id;
  IF cycle_row.kind<>p_kind OR (p_kind='REGULAR' AND anchor->>'reason' IS NOT NULL) THEN
   RAISE EXCEPTION 'mobile_clinical_review_not_available' USING ERRCODE='40001';
  END IF;
 ELSIF p_kind='ROUTINE_REVIEW' AND (scope_cycle_id IS NOT NULL OR anchor->>'reason' IS DISTINCT FROM 'not_due') THEN
  RAISE EXCEPTION 'mobile_clinical_regular_required' USING ERRCODE='40001';
 END IF;
 BEGIN
  PERFORM c.cycle_id FROM private.mobile_reevaluation_cycles c WHERE c.user_id=p_user_id
   AND c.signup_generation=generation_id ORDER BY c.cycle_id FOR UPDATE NOWAIT;
  PERFORM c.acceptance_id FROM private.mobile_reevaluation_photo_consents c WHERE c.user_id=p_user_id
   AND c.cycle_id=scope_cycle_id ORDER BY c.acceptance_id FOR UPDATE NOWAIT;
  PERFORM s.pose FROM private.mobile_reevaluation_photo_sources s WHERE s.user_id=p_user_id
   AND s.cycle_id=scope_cycle_id ORDER BY s.consent_acceptance_id,s.pose FOR UPDATE NOWAIT;
  PERFORM l.asset_id FROM private.mobile_reevaluation_photo_assets l WHERE l.user_id=p_user_id
   AND l.cycle_id=scope_cycle_id ORDER BY l.asset_id FOR UPDATE NOWAIT;
  PERFORM m.id FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets l
   ON l.asset_id=m.id AND l.user_id=m.user_id WHERE l.user_id=p_user_id AND l.cycle_id=scope_cycle_id
   ORDER BY m.id FOR UPDATE OF m NOWAIT;
  PERFORM t.ticket_id FROM private.mobile_reevaluation_photo_upload_tickets t WHERE t.user_id=p_user_id
   AND t.cycle_id=scope_cycle_id ORDER BY t.asset_id,t.ticket_id FOR UPDATE NOWAIT;
  PERFORM t.request_id FROM private.mobile_reevaluation_photo_processing_attempts t WHERE t.user_id=p_user_id
   AND t.cycle_id=scope_cycle_id ORDER BY t.asset_id,t.request_id FOR UPDATE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'mobile_clinical_busy' USING ERRCODE='55P03';
 END;
 -- All authority locks are held. Time is sampled again after every possible
 -- blocking wait; crossing the day whose advisory was locked rejects the read.
 observed_at:=coalesce(p_observed_at,clock_timestamp());
 today:=(observed_at AT TIME ZONE owner_row.timezone)::date;
 IF today<>first_day THEN RAISE EXCEPTION 'mobile_clinical_day_changed' USING ERRCODE='40001'; END IF;
 anchor:=private.mobile_reevaluation_context_at(p_user_id,observed_at);
 IF anchor->>'signup_generation' IS DISTINCT FROM generation_id::text
  OR (anchor#>>'{cycle,id}')::uuid IS DISTINCT FROM scope_cycle_id
  OR (p_kind='REGULAR' AND anchor->>'reason' IS NOT NULL)
  OR (p_kind='ROUTINE_REVIEW' AND anchor->>'reason' IS DISTINCT FROM 'not_due') THEN
  RAISE EXCEPTION 'mobile_clinical_context_changed' USING ERRCODE='40001';
 END IF;
 -- The original calendar retains its source timezone. Clinical 14-day rules
 -- also use the owner's present civil date, which may still be the prior day
 -- after a westward timezone change. Never treat that as a full fortnight.
 IF p_kind='REGULAR' AND today<(anchor#>>'{clock,due_date}')::date THEN
  RAISE EXCEPTION 'mobile_clinical_review_not_available' USING ERRCODE='40001';
 END IF;
 IF p_kind='EARLY_FULL' AND today>=(anchor#>>'{clock,due_date}')::date
  AND (observed_at AT TIME ZONE (anchor#>>'{clock,timezone}'))::date>=(anchor#>>'{clock,due_date}')::date THEN
  RAISE EXCEPTION 'mobile_clinical_regular_required' USING ERRCODE='40001';
 END IF;
 SELECT * INTO STRICT profile_row FROM public.user_profiles WHERE user_id=p_user_id;
 profile_json:=private.mobile_clinical_canonical_row(to_jsonb(profile_row),
  ARRAY['created_at','updated_at','bf_estimated_at','cycle_start_at','body_fat_measured_at','onboarding_completed_at','weight_measured_at'],ARRAY[]::text[]);
 SELECT private.mobile_clinical_canonical_row(to_jsonb(p),ARRAY['updated_at'],ARRAY[]::text[])
  INTO progress_json FROM public.user_progress p WHERE p.user_id=p_user_id;
 SELECT private.mobile_clinical_canonical_row(to_jsonb(d),ARRAY['closed_at','created_at','updated_at'],ARRAY[]::text[])
  INTO day_json FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=today;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(w),ARRAY['measured_at','received_at'],ARRAY[]::text[])
   ||jsonb_build_object('local_date',(w.measured_at AT TIME ZONE owner_row.timezone)::date)
   ORDER BY w.measured_at,w.id),'[]') INTO history_json
  FROM private.mobile_weight_measurements w WHERE w.user_id=p_user_id
   AND w.authority_epoch=(anchor->>'signup_epoch')::uuid
   AND (w.measured_at AT TIME ZONE owner_row.timezone)::date BETWEEN today-27 AND today;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(
   jsonb_build_object('key',c.key,'value',c.value,'updated_at',c.updated_at),ARRAY['updated_at'],ARRAY[]::text[])
   ORDER BY c.key),'[]') INTO calc_json FROM public.global_config c WHERE c.key LIKE 'calc.%';
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(d)-'body',ARRAY['required_from','created_at'],ARRAY[]::text[])
   ORDER BY d.required_from,d.created_at,d.id),'[]') INTO documents_json FROM public.legal_documents d
  WHERE d.document_key='body_photo_reevaluation_consent' AND d.locale=owner_row.locale;
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.document_id),'[]') INTO policies_json
  FROM private.mobile_reevaluation_photo_policies p WHERE p.document_id IN(
   SELECT d.id FROM public.legal_documents d WHERE d.document_key='body_photo_reevaluation_consent' AND d.locale=owner_row.locale);
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(c),
   ARRAY['accepted_at','last_activity_at','revoked_at'],ARRAY[]::text[]) ORDER BY c.acceptance_id),'[]') INTO consents_json
  FROM private.mobile_reevaluation_photo_consents c WHERE c.user_id=p_user_id AND c.cycle_id=scope_cycle_id;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(s),ARRAY['selected_at'],ARRAY['source_revision'])
   ORDER BY s.consent_acceptance_id,CASE s.pose WHEN 'front' THEN 1 WHEN 'side' THEN 2 ELSE 3 END),'[]') INTO sources_json
  FROM private.mobile_reevaluation_photo_sources s WHERE s.user_id=p_user_id AND s.cycle_id=scope_cycle_id;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(l),ARRAY['created_at','invalidated_at'],ARRAY['request_revision'])
   ORDER BY l.asset_id),'[]') INTO allocations_json FROM private.mobile_reevaluation_photo_assets l
  WHERE l.user_id=p_user_id AND l.cycle_id=scope_cycle_id;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(
   jsonb_build_object('id',m.id,'user_id',m.user_id,'reevaluation_origin_version',m.reevaluation_origin_version,
    'kind',m.kind,'mime_type',m.mime_type,'declared_size_bytes',m.declared_size_bytes,'actual_size_bytes',m.actual_size_bytes,
    'etag',m.etag,'status',m.status,'failure_stage',m.failure_stage,'failure_code',m.failure_code,
    'processing_request_id',m.processing_request_id,'retention_until',m.retention_until,
    'created_at',m.created_at,'uploaded_at',m.uploaded_at,'processed_at',m.processed_at,'deleted_at',m.deleted_at),
   ARRAY['retention_until','created_at','uploaded_at','processed_at','deleted_at'],ARRAY['declared_size_bytes','actual_size_bytes'])
   ORDER BY m.id),'[]') INTO media_json FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets l
  ON l.asset_id=m.id AND l.user_id=m.user_id WHERE l.user_id=p_user_id AND l.cycle_id=scope_cycle_id;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(t),
   ARRAY['prepared_at','provider_expires_at','registered_at'],ARRAY[]::text[]) ORDER BY t.asset_id,t.ticket_id),'[]') INTO tickets_json
  FROM private.mobile_reevaluation_photo_upload_tickets t WHERE t.user_id=p_user_id AND t.cycle_id=scope_cycle_id;
 SELECT coalesce(jsonb_agg(private.mobile_clinical_canonical_row(to_jsonb(t),
   ARRAY['claimed_at','lease_until','provider_started_at','provider_authorized_until','finished_at'],ARRAY['source_revision'])
   ORDER BY t.asset_id,t.request_id),'[]') INTO attempts_json FROM private.mobile_reevaluation_photo_processing_attempts t
  WHERE t.user_id=p_user_id AND t.cycle_id=scope_cycle_id;
 deadline:=((today+1)::timestamp AT TIME ZONE owner_row.timezone);
 SELECT min(d.required_from) INTO next_boundary FROM public.legal_documents d
  WHERE d.document_key='body_photo_reevaluation_consent' AND d.locale=owner_row.locale AND d.required_from>observed_at;
 deadline:=least(deadline,next_boundary);
 IF scope_cycle_id IS NOT NULL AND p_kind='REGULAR' THEN
  photo_context:=private.mobile_reevaluation_photo_context(p_user_id,scope_cycle_id,observed_at);
  photo_availability:=private.mobile_reevaluation_photo_consent_wire(photo_context)-'document';
  IF photo_context#>>'{current_acceptance,revoked_at}' IS NULL THEN
   next_boundary:=(photo_context#>>'{current_acceptance,last_activity_at}')::timestamptz
    +make_interval(secs=>(photo_context#>>'{current_acceptance,idle_timeout_seconds}')::integer);
   deadline:=least(deadline,next_boundary);
  END IF;
 ELSIF p_kind IN('ROUTINE_REVIEW','EARLY_FULL') THEN
  next_boundary:=(anchor#>>'{clock,due_date}')::date::timestamp AT TIME ZONE (anchor#>>'{clock,timezone}');
  IF next_boundary>observed_at THEN deadline:=least(deadline,next_boundary); END IF;
 END IF;
 SELECT * INTO cycle_row FROM private.mobile_reevaluation_cycles WHERE cycle_id=scope_cycle_id;
 facts:=jsonb_build_object('owner',jsonb_build_object('id',owner_row.id,'status',owner_row.status,
   'locale',owner_row.locale,'timezone',owner_row.timezone,'updated_at',to_char(owner_row.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
  'anchor',anchor-ARRAY['observed_at','cycle'],'calculation_date',today,
  'cycle',CASE WHEN cycle_row.cycle_id IS NULL THEN 'null'::jsonb ELSE
   private.mobile_clinical_canonical_row(to_jsonb(cycle_row),
    ARRAY['opened_at','completed_at','invalidated_at'],ARRAY['revision']) END,
  'profile',profile_json,'progress',coalesce(progress_json,'null'::jsonb),'day',coalesce(day_json,'null'::jsonb),
  'weight_history',history_json,'safety',private.mobile_health_state_wire(p_user_id),'calculation_config',calc_json,
  'protocol_authority',private.mobile_clinical_protocol_authority(p_user_id,generation_id,(anchor->>'signup_epoch')::uuid,scope_cycle_id,observed_at),
  'photo_authority',jsonb_build_object('documents',documents_json,'policies',policies_json,'consents',consents_json,
   'sources',sources_json,'allocations',allocations_json,'media',media_json,'tickets',tickets_json,'attempts',attempts_json,
   'consent_state',coalesce(photo_availability,'null'::jsonb)));
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'review_kind',p_kind,'cycle_id',p_cycle_id,
  'observed_at',to_char(observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'valid_until',to_char(deadline AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'facts',facts,'context_hash',encode(extensions.digest(
   jsonb_build_object('version',1,'rule_version','clinical-v1','review_kind',p_kind,'cycle_id',p_cycle_id,'facts',facts)::text,'sha256'),'hex'));
END $$;

CREATE FUNCTION private.mobile_clinical_preview_wire(p private.mobile_clinical_previews)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'user_id',(p).user_id,'preview_id',(p).preview_id,
  'review_kind',(p).review_kind,'cycle_id',(p).cycle_id,'context_hash',(p).context_hash,
  'rule_version',(p).rule_version,
  'created_at',to_char((p).created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'valid_until',to_char((p).valid_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

CREATE FUNCTION private.prepare_mobile_clinical_preview_at(p_user_id uuid,p_kind text,p_cycle_id uuid,
 p_operation_key uuid,p_context_hash text,p_form jsonb,p_intent jsonb,p_proposal jsonb,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; previous private.mobile_clinical_previews%ROWTYPE;
 form_hash text; intent_hash text; proposal_hash text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','ROUTINE_REVIEW','SAFETY')
  OR p_operation_key IS NULL OR p_context_hash IS NULL OR p_context_hash !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(p_form) IS DISTINCT FROM 'object' OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
  OR octet_length(p_form::text)>65536 OR octet_length(p_intent::text)>8192 OR octet_length(p_proposal::text)>65536 THEN
  RAISE EXCEPTION 'invalid_mobile_clinical_preview' USING ERRCODE='22023';
 END IF;
 form_hash:=encode(extensions.digest(p_form::text,'sha256'),'hex');
 intent_hash:=encode(extensions.digest(p_intent::text,'sha256'),'hex');
 proposal_hash:=encode(extensions.digest(p_proposal::text,'sha256'),'hex');
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO previous FROM private.mobile_clinical_previews WHERE user_id=p_user_id AND operation_key=p_operation_key;
 IF FOUND THEN
  IF ROW(previous.review_kind,previous.cycle_id,previous.context_hash,previous.form_hash,previous.intent_hash,previous.proposal_hash)
   IS DISTINCT FROM ROW(p_kind,p_cycle_id,p_context_hash,form_hash,intent_hash,proposal_hash) THEN
   RAISE EXCEPTION 'mobile_clinical_preview_conflict' USING ERRCODE='40001';
  END IF;
  -- Returns only the original acknowledgement, never a permission to conclude.
  -- Confirmation must capture and compare current authority again.
  RETURN private.mobile_clinical_preview_wire(previous);
 END IF;
 context:=private.capture_mobile_clinical_context_at(p_user_id,p_kind,p_cycle_id,p_observed_at);
 IF context->>'context_hash'<>p_context_hash
  OR (context->>'valid_until')::timestamptz<=(context->>'observed_at')::timestamptz THEN
  RAISE EXCEPTION 'mobile_clinical_preview_stale' USING ERRCODE='40001';
 END IF;
 INSERT INTO private.mobile_clinical_previews(user_id,operation_key,review_kind,signup_generation,signup_epoch,
  cycle_id,context_hash,form_hash,intent_hash,proposal_hash,rule_version,created_at,valid_until)
 VALUES(p_user_id,p_operation_key,p_kind,(context#>>'{facts,anchor,signup_generation}')::uuid,
  (context#>>'{facts,anchor,signup_epoch}')::uuid,p_cycle_id,p_context_hash,form_hash,intent_hash,proposal_hash,
  'clinical-v1',(context->>'observed_at')::timestamptz,(context->>'valid_until')::timestamptz) RETURNING * INTO previous;
 RETURN private.mobile_clinical_preview_wire(previous);
END $$;

REVOKE ALL ON FUNCTION private.mobile_clinical_evidence_immutable(),
 private.mobile_clinical_canonical_row(jsonb,text[],text[]),
 private.mobile_clinical_protocol_authority(uuid,uuid,uuid,uuid,timestamptz),
 private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz),
 private.mobile_clinical_preview_wire(private.mobile_clinical_previews),
 private.prepare_mobile_clinical_preview_at(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

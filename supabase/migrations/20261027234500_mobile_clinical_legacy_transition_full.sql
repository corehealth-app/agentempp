-- Honest legacy TRANSITION_FULL: same three NEW photo authority and atomic
-- conclusion, with no fabricated signup or elapsed fortnight. Local draft until
-- the complete BFF/native integration and whole-plan gates are satisfied.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_generation_sources') IS NULL THEN
  RAISE EXCEPTION 'mobile_clinical_transition_requires_generation_sources' USING ERRCODE='42501'; END IF;
END $preflight$;
ALTER TABLE private.mobile_clinical_previews DROP CONSTRAINT mobile_clinical_previews_review_kind_check;
ALTER TABLE private.mobile_clinical_previews ADD CONSTRAINT mobile_clinical_previews_review_kind_check
 CHECK(review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL','ROUTINE_REVIEW','SAFETY'));
ALTER TABLE private.mobile_clinical_previews DROP CONSTRAINT mobile_clinical_previews_check1;
ALTER TABLE private.mobile_clinical_previews ADD CONSTRAINT mobile_clinical_previews_check1
 CHECK((review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL'))=(cycle_id IS NOT NULL));
ALTER TABLE private.mobile_clinical_full_receipts DROP CONSTRAINT mobile_clinical_full_receipts_kind_check;
ALTER TABLE private.mobile_clinical_full_receipts ADD CONSTRAINT mobile_clinical_full_receipts_kind_check
 CHECK(kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL','SAFETY','ROUTINE_REVIEW'));
-- The pre-existing REGULAR 14-day check is retained byte-for-byte.
ALTER TABLE private.mobile_clinical_full_receipts ADD CONSTRAINT mobile_clinical_transition_photos_required
 CHECK(kind<>'TRANSITION_FULL' OR (body_fat_mean IS NOT NULL AND body_fat_source_hash IS NOT NULL));
CREATE OR REPLACE FUNCTION private.mobile_reevaluation_photo_context(p_user_id uuid, p_cycle_id uuid, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
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
    OR coalesce(context#>>'{cycle,kind}' IN('REGULAR','TRANSITION_FULL'),false) IS NOT TRUE THEN
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
END $function$;

CREATE OR REPLACE FUNCTION private.capture_mobile_clinical_context_at(p_user_id uuid, p_kind text, p_cycle_id uuid, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO, YMD'
AS $function$
DECLARE owner_row public.users%ROWTYPE; profile_row public.user_profiles%ROWTYPE;
 observed_at timestamptz; first_day date; today date; deadline timestamptz; next_boundary timestamptz;
 anchor jsonb; cycle_row private.mobile_reevaluation_cycles%ROWTYPE; generation_id uuid;
 scope_cycle_id uuid; photo_context jsonb; photo_availability jsonb; facts jsonb;
 profile_json jsonb; progress_json jsonb; day_json jsonb; history_json jsonb; calc_json jsonb;
 documents_json jsonb; policies_json jsonb; consents_json jsonb; sources_json jsonb;
 allocations_json jsonb; media_json jsonb; tickets_json jsonb; attempts_json jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL','ROUTINE_REVIEW','SAFETY','APPLICATION')
  OR ((p_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL'))<>(p_cycle_id IS NOT NULL)) THEN
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
 IF p_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL') THEN
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
 IF scope_cycle_id IS NOT NULL AND p_kind IN('REGULAR','TRANSITION_FULL') THEN
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
END $function$;

CREATE OR REPLACE FUNCTION private.prepare_mobile_clinical_preview_at(p_user_id uuid, p_kind text, p_cycle_id uuid, p_operation_key uuid, p_context_hash text, p_form jsonb, p_intent jsonb, p_proposal jsonb, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE context jsonb; previous private.mobile_clinical_previews%ROWTYPE;
 form_hash text; intent_hash text; proposal_hash text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL','ROUTINE_REVIEW','SAFETY')
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
END $function$;

CREATE OR REPLACE FUNCTION private.mobile_clinical_protocol_authority(p_user_id uuid, p_generation uuid, p_epoch uuid, p_cycle_id uuid, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE origin jsonb; candidate jsonb; episode jsonb; prior_regular jsonb; body_origin jsonb;
 day_events jsonb; routine_events jsonb;
BEGIN
 SELECT private.mobile_clinical_canonical_row(to_jsonb(o),ARRAY['started_at','captured_at'],ARRAY[]::text[])
  INTO origin FROM private.mobile_clinical_signup_origins o
  WHERE o.user_id=p_user_id AND o.signup_generation=p_generation AND o.signup_epoch=p_epoch;
 IF p_cycle_id IS NOT NULL AND EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles
  WHERE user_id=p_user_id AND cycle_id=p_cycle_id AND kind IN('REGULAR','TRANSITION_FULL') AND status IN('open','collecting','review_ready')) THEN
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
    private.mobile_clinical_signup_no_plan_origin(p_user_id,p_generation,p_epoch),
    (SELECT jsonb_build_object('kind','legacy_transition_unassigned','generation',l->'generation',
      'epoch',l->'epoch','admittedAt',l->'admitted_at')
     FROM (SELECT private.read_mobile_clinical_legacy_generation_at(p_user_id,p_observed_at) l) proof
     WHERE l->>'generation'=p_generation::text AND l->>'epoch'=p_epoch::text),
    jsonb_build_object('kind','legacy_unassigned')) END,
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
END $function$;

CREATE OR REPLACE FUNCTION private.confirm_mobile_clinical_preview_at(p_user_id uuid, p_preview_id uuid, p_operation_key uuid, p_form jsonb, p_intent jsonb, p_proposal jsonb, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET "TimeZone" TO 'UTC'
AS $function$
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
 health_only boolean;legacy_health boolean;origin_key text;health_answer jsonb;health_items text[];
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
 legacy_health:=health_only AND context#>>'{facts,anchor,authority,kind}'='legacy_transition';
 origin_key:=CASE WHEN legacy_health THEN 'legacyOrigin' ELSE 'noPlanOrigin' END;
 IF health_only THEN
  IF context#>>'{facts,protocol_authority,phase_origin,kind}' IS DISTINCT FROM
    (CASE WHEN legacy_health THEN 'legacy_transition_unassigned' ELSE 'confirmed_no_plan' END)
   OR p_form->origin_key IS DISTINCT FROM context#>'{facts,protocol_authority,phase_origin}' THEN
   RAISE EXCEPTION 'mobile_clinical_no_plan_origin_unproven' USING ERRCODE='40001';
  END IF;
  IF preview.review_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL') OR principal<>'keep'
   OR NOT(p_form ?& ARRAY['version','phase','kind','activityPurpose','answers','preference',origin_key])
   OR p_form-ARRAY['version','phase','kind','activityPurpose','answers','preference',origin_key]<>'{}'::jsonb
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
   OR (CASE WHEN legacy_health THEN
    targets IS DISTINCT FROM jsonb_build_object('beforeKcal',applied_day.calories_target,
     'beforeProtein',applied_day.protein_target,'afterKcal',applied_day.calories_target,
     'afterProtein',applied_day.protein_target,'formulaAfterKcal',NULL)
    ELSE EXISTS(SELECT 1 FROM jsonb_each(targets) x WHERE x.value<>'null'::jsonb) END)
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
 clear_hold:=coalesce((safety->>'hold_active')::boolean,false) AND preview.review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL')
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
 IF preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN
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
 IF preview.review_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL') AND coalesce(p_form->'preference','null'::jsonb)<>'null'::jsonb THEN
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
 IF preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN
  UPDATE public.user_profiles SET body_fat_percent=body_fat,body_fat_measured_at=observed_at,updated_at=observed_at WHERE user_id=p_user_id;
 END IF;
 current_cycle:=preview.cycle_id;
 IF preview.review_kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL','SAFETY') THEN
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
  current_bf_percent=CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN body_fat ELSE current_bf_percent END,
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
  'targets',targets,'body_fat_percent',CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN body_fat ELSE NULL END,
  'preference',preference_result);
 INSERT INTO private.mobile_clinical_full_receipts(user_id,review_id,preview_id,signup_generation,signup_epoch,review_no,
  kind,cycle_id,previous_full_id,base_before,base_after,timezone_at_completion,calculation_date,completed_at,final_cycle_revision,
  principal,activity_level_changed,context_hash,input_hash,form,intent,proposal,result,body_fat_mean,body_fat_source_hash,rule_version)
 VALUES(p_user_id,p_preview_id,p_preview_id,preview.signup_generation,preview.signup_epoch,review_number,preview.review_kind,
  current_cycle,previous_full,base_day,CASE WHEN preview.review_kind<>'ROUTINE_REVIEW' THEN day END,zone,day,observed_at,cycle_revision,
  principal,new_level IS DISTINCT FROM profile_row.activity_level::text,preview.context_hash,input_hash,p_form,p_intent,p_proposal,result,
  CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN body_fat END,CASE WHEN preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN candidate->>'source_hash' END,'clinical-v1');
 IF preview.review_kind IN('REGULAR','TRANSITION_FULL') THEN
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
END $function$;

CREATE OR REPLACE FUNCTION public.get_mobile_clinical_full_context(p_user_id uuid, p_kind text, p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_kind IS NULL OR p_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL','SAFETY','ROUTINE_REVIEW') THEN
  RAISE EXCEPTION 'invalid_clinical_full_scope' USING ERRCODE='22023'; END IF;
 RETURN private.capture_mobile_clinical_context_at(p_user_id,p_kind,p_cycle_id,NULL);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/get_mobile_clinical_full_context'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_mobile_clinical_full_command(p_user_id uuid, p_kind text, p_cycle_id uuid, p_operation_key uuid, p_context_hash text, p_command jsonb, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE _m3b_transport_message text; _m3b_transport_detail text; _m3b_transport_hint text;
BEGIN
DECLARE p private.mobile_clinical_previews%ROWTYPE;c private.mobile_clinical_full_commands%ROWTYPE;
 profile public.user_profiles%ROWTYPE;wire jsonb;normalization jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_operation_key IS NULL OR p_kind IS NULL
  OR p_kind NOT IN('REGULAR','EARLY_FULL','TRANSITION_FULL','ROUTINE_REVIEW','SAFETY') THEN
  RAISE EXCEPTION 'invalid_clinical_full_command_scope' USING ERRCODE='22023'; END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT x.* INTO p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.operation_key=p_operation_key;
 IF FOUND THEN
  SELECT x.* INTO c FROM private.mobile_clinical_full_commands x WHERE x.user_id=p_user_id AND x.preview_id=p.preview_id;
  IF NOT FOUND OR p.review_kind IS DISTINCT FROM p_kind OR p.cycle_id IS DISTINCT FROM p_cycle_id
   OR c.command_hash IS DISTINCT FROM private.mobile_clinical_full_command_hash(p,p_command,c.normalization_context) THEN
   RAISE EXCEPTION 'clinical_full_command_conflict' USING ERRCODE='40001'; END IF;
  -- Identity is the normalized client command, not a recalculated effect. Never
  -- extend expiry or consult a changed profile on this acknowledgement branch.
  RETURN private.mobile_clinical_full_command_wire(p,c);
 END IF;
 IF NOT private.mobile_clinical_full_command_valid(p_kind,p_command,p_form,p_intent,p_proposal) THEN
  RAISE EXCEPTION 'invalid_clinical_full_command' USING ERRCODE='22023'; END IF;
 wire:=private.prepare_mobile_clinical_preview_at(p_user_id,p_kind,p_cycle_id,p_operation_key,p_context_hash,p_form,p_intent,p_proposal,NULL);
 SELECT x.* INTO STRICT p FROM private.mobile_clinical_previews x WHERE x.user_id=p_user_id AND x.preview_id=(wire->>'preview_id')::uuid;
 -- The delegated capture holds this profile and the full calculation context.
 -- Retain only the two original n21 normalization inputs, never a refused value.
 SELECT x.* INTO STRICT profile FROM public.user_profiles x WHERE x.user_id=p_user_id;
 IF NOT coalesce(private.mobile_clinical_preference_valid(p_form->'preference',profile.sex::text,profile.height_cm),false) THEN
  RAISE EXCEPTION 'invalid_clinical_full_normalized_preference' USING ERRCODE='22023'; END IF;
 normalization:=jsonb_build_object('sex',profile.sex,'heightCm',profile.height_cm);
 INSERT INTO private.mobile_clinical_full_commands(user_id,preview_id,command_version,command,prepared_package,normalization_context,command_hash)
 VALUES(p_user_id,p.preview_id,1,p_command,jsonb_build_object('form',p_form,'intent',p_intent,'proposal',p_proposal),normalization,
  private.mobile_clinical_full_command_hash(p,p_command,normalization)) RETURNING * INTO c;
 RETURN private.mobile_clinical_full_command_wire(p,c);
END;
EXCEPTION WHEN serialization_failure THEN
  -- Only the RPC named by PostgREST's server-owned request context translates.
  -- Nested public/private SQL calls and direct SQL keep their original 40001.
  IF current_setting('request.path',true)='/rpc/prepare_mobile_clinical_full_command'
      AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
    GET STACKED DIAGNOSTICS _m3b_transport_message=MESSAGE_TEXT,
      _m3b_transport_detail=PG_EXCEPTION_DETAIL,_m3b_transport_hint=PG_EXCEPTION_HINT;
    RAISE SQLSTATE 'PGRST' USING
      MESSAGE=jsonb_build_object('code','40001','message',_m3b_transport_message,
        'details',nullif(_m3b_transport_detail,''),'hint',nullif(_m3b_transport_hint,''))::text,
      DETAIL='{"status":409,"headers":{}}';
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_mobile_reevaluation_photo_cleanup_scopes(p_limit integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '2s'
AS $function$
DECLARE at_time timestamptz;ids uuid[];more boolean;items jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF current_setting('transaction_isolation')<>'read committed' OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'invalid_mobile_reevaluation_cleanup_claim' USING ERRCODE='22023';
 END IF;
 at_time:=clock_timestamp();
 ids:=ARRAY(
  SELECT a.acceptance_id FROM private.mobile_reevaluation_photo_consents a
   JOIN public.users u ON u.id=a.user_id
   JOIN private.mobile_reevaluation_cycles c ON c.cycle_id=a.cycle_id AND c.user_id=a.user_id
   LEFT JOIN public.user_profiles p ON p.user_id=a.user_id
   LEFT JOIN private.workout_strength_authority_epochs e ON e.user_id=a.user_id
   LEFT JOIN private.mobile_clinical_generation_sources source ON source.user_id=a.user_id AND source.generation=a.signup_generation
   LEFT JOIN private.mobile_signup_strength_completion_receipts r ON r.user_id=a.user_id AND r.admission_id=a.signup_generation
   LEFT JOIN private.mobile_clinical_legacy_admissions legacy ON legacy.user_id=a.user_id AND legacy.generation=a.signup_generation
   LEFT JOIN private.mobile_reevaluation_photo_dispositions h ON h.acceptance_id=a.acceptance_id
   LEFT JOIN private.mobile_reevaluation_photo_cleanup_visits v ON v.acceptance_id=a.acceptance_id
   LEFT JOIN LATERAL(
    SELECT d.id FROM public.legal_documents d WHERE d.document_key='body_photo_reevaluation_consent'
     AND d.locale=u.locale AND d.required_from<=at_time ORDER BY d.required_from DESC,d.created_at DESC,d.id DESC LIMIT 1
   ) doc ON true
   LEFT JOIN private.mobile_reevaluation_photo_policies policy ON policy.document_id=doc.id
  WHERE u.status<>'deleted' AND (
   (h.disposition_id IS NULL AND (
    a.revoked_at IS NOT NULL OR a.last_activity_at+make_interval(secs=>a.idle_timeout_seconds)<=at_time
    OR c.status NOT IN('open','collecting','review_ready')
    OR p.onboarding_completed IS DISTINCT FROM true OR c.signup_epoch IS DISTINCT FROM e.epoch
    OR (source.epoch=c.signup_epoch AND (
     (source.kind='signup_receipt' AND r.epoch=c.signup_epoch AND r.outcome='first_fresh'
      AND r.completed_at IS NOT DISTINCT FROM p.onboarding_completed_at AND r.completed_at<=at_time)
     OR (source.kind='legacy_transition' AND legacy.epoch=c.signup_epoch
      AND legacy.profile_completed_marker IS NOT DISTINCT FROM p.onboarding_completed_at AND legacy.admitted_at<=at_time)
    )) IS DISTINCT FROM true
    OR a.document_id IS DISTINCT FROM doc.id OR a.locale IS DISTINCT FROM u.locale OR policy.enabled IS DISTINCT FROM true
   )) OR (h.disposition_id IS NOT NULL AND (h.sweep_state IN('idle','pending')
    OR(h.sweep_state='waiting' AND h.next_sweep_at<=at_time)))
  )
  ORDER BY coalesce(v.visited_at,a.accepted_at),a.acceptance_id LIMIT p_limit+1 FOR UPDATE OF a SKIP LOCKED
 );
 more:=cardinality(ids)>p_limit;ids:=ids[1:p_limit];
 -- Commit this technical visit before any external removal, including failures.
 -- The original prepare RPC still makes the final decision: a candidate which
 -- was renewed or otherwise remains valid will return live and is not removed.
 INSERT INTO private.mobile_reevaluation_photo_cleanup_visits(acceptance_id,visited_at)
  SELECT unnest(ids),clock_timestamp() ON CONFLICT(acceptance_id) DO UPDATE SET visited_at=EXCLUDED.visited_at;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'cycle_id',a.cycle_id,'acceptance_id',a.acceptance_id) ORDER BY x.ord),'[]'::jsonb)
  INTO items FROM unnest(ids) WITH ORDINALITY x(id,ord) JOIN private.mobile_reevaluation_photo_consents a ON a.acceptance_id=x.id;
 RETURN jsonb_build_object('version',1,'items',items,'has_more',more);
END $function$;

CREATE OR REPLACE FUNCTION private.mobile_clinical_full_command_valid(p_kind text, p_command jsonb, p_form jsonb, p_intent jsonb, p_proposal jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE choice jsonb;kind text;principal text;
BEGIN
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object'
  OR NOT(p_command ?& ARRAY['form','choice','measureConfirmed','bodyFat'])
  OR p_command-ARRAY['form','choice','measureConfirmed','bodyFat']<>'{}'::jsonb
  OR octet_length(p_command::text)>81920
  OR jsonb_typeof(p_form) IS DISTINCT FROM 'object'
  OR p_command->'form' IS DISTINCT FROM p_form
  OR p_form->'version' IS DISTINCT FROM '1'::jsonb
  OR p_form->>'kind' IS DISTINCT FROM p_kind
  OR NOT(p_form ?& ARRAY['version','phase','kind','activityPurpose','answers','preference'])
  OR p_form-ARRAY['version','phase','kind','activityPurpose','answers','preference','noPlanOrigin','legacyOrigin']<>'{}'::jsonb
  OR jsonb_typeof(p_form->'answers') IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_proposal) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_command->'measureConfirmed') IS DISTINCT FROM 'boolean'
  OR p_command->'bodyFat' IS DISTINCT FROM coalesce(p_intent->'bodyFat','null'::jsonb)
  OR jsonb_typeof(p_command->'bodyFat') NOT IN('object','null') THEN RETURN false; END IF;
 choice:=p_command->'choice';kind:=choice->>'kind';principal:=p_proposal->>'principal';
 IF jsonb_typeof(choice) IS DISTINCT FROM 'object' OR jsonb_typeof(choice->'kind') IS DISTINCT FROM 'string'
  OR principal IS NULL THEN RETURN false; END IF;
 IF kind='phase' THEN
  RETURN coalesce(choice-ARRAY['kind','phase']='{}'::jsonb AND jsonb_typeof(choice->'phase')='string'
   AND CASE choice->>'phase'
    WHEN 'manutencao' THEN principal IN('recomposition_transition','gain_exit')
    WHEN 'ganho_massa' THEN principal='phase_gain'
    WHEN 'recomposicao' THEN principal='phase_recomposition' ELSE false END,false);
 ELSIF kind='schedule' THEN
  RETURN coalesce(choice-ARRAY['kind','action']='{}'::jsonb AND jsonb_typeof(choice->'action')='string'
   AND CASE choice->>'action' WHEN 'pause' THEN principal='schedule_pause'
    WHEN 'reconfirm' THEN principal='schedule_reconfirm' ELSE false END,false);
 END IF;
 IF choice-ARRAY['kind']<>'{}'::jsonb THEN RETURN false; END IF;
 RETURN CASE kind WHEN 'keep' THEN principal IN('keep','schedule_pause')
  WHEN 'activity' THEN principal='activity'
  WHEN 'phase_calorie_step' THEN principal IN('deficit_step','maintenance_step','gain_step')
  WHEN 'neutral_exit' THEN principal='neutral_exit' ELSE false END;
END $function$;

CREATE OR REPLACE FUNCTION private.mobile_health_state_wire(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
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
       AND f.kind IN('REGULAR','EARLY_FULL','TRANSITION_FULL') AND f.completed_at=c.cleared_at
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
END $function$;
COMMIT;

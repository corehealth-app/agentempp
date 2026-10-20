-- Atomic dormant projection for a target already acquired through the weekly CAS.
-- Private clocks are owner-only QA seams; public functions never accept a clock.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
DECLARE sig text;wanted text;f record;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'strength_week_projection_requires_postgres' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='private' AND p.proname IN('prepare_workout_strength_calendar_scope_at','get_mobile_strength_week_projection_at'))
   OR (n.nspname='public' AND p.proname='get_mobile_strength_week_projection'))
 THEN RAISE EXCEPTION 'strength_week_projection_unknown_object' USING ERRCODE='42P07';END IF;
 FOR sig,wanted IN SELECT * FROM (VALUES ('public.prepare_workout_strength_calendar_scope(uuid,uuid)','0e89ab7ecc960ad45e2875a9bcb87fcd86daba482203288f157f535ddbc96dfd'),('public.get_mobile_strength_week_lifecycle_binding(uuid,uuid,uuid)','3c2f9fc427261c4a6f4626644348e7088ae6a3fafba98beb9166bff979da50c1'),('public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)','a432794f7dd33e2babcf3fa320ba3120b305d3826590f92ad59aadc1ec3daefa'),('private.strength_week_target_wire(private.strength_week_targets,private.strength_week_source_versions,private.strength_week_source_versions)','5367ecbd3a925964b6c60b4ea54fe061341600af7a746120ffd730c900283f0a')) v(signature,sha) LOOP
  SELECT p.*,l.lanname INTO f FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure(sig);
  IF NOT FOUND OR pg_get_userbyid(f.proowner)<>'postgres' OR f.provolatile<>'v' OR f.lanname<>'plpgsql'
   OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR f.prosecdef IS DISTINCT FROM (sig LIKE 'public.%')
   OR encode(extensions.digest(convert_to(f.prosrc,'UTF8'),'sha256'),'hex') IS DISTINCT FROM wanted
   OR has_function_privilege('anon',to_regprocedure(sig),'EXECUTE')
   OR has_function_privilege('authenticated',to_regprocedure(sig),'EXECUTE')
   OR has_function_privilege('service_role',to_regprocedure(sig),'EXECUTE') IS DISTINCT FROM (sig LIKE 'public.%')
  THEN RAISE EXCEPTION 'strength_week_projection_substrate_drift:%',sig USING ERRCODE='55000';END IF;
 END LOOP;
END $preflight$;
CREATE FUNCTION private.prepare_workout_strength_calendar_scope_at(
 p_user_id uuid,p_expected_lifecycle_key uuid,p_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $calendar_at$
DECLARE
  official_zone text;
  observed_at timestamptz;
  local_clock timestamp;
  local_date date;
  monday date;
  calendar_scope private.workout_strength_calendar_scopes%ROWTYPE;
  result_status text;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_expected_lifecycle_key IS NULL THEN
    RAISE EXCEPTION 'invalid_workout_strength_input' USING ERRCODE='22023';
  END IF;
  IF pg_catalog.current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'workout_strength_requires_read_committed' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text||':workouts',0));
  SELECT u.timezone INTO official_zone FROM public.users u
    WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_strength_patient_not_found' USING ERRCODE='P0002';
  END IF;
  PERFORM 1 FROM private.workout_strength_lifecycles l
    WHERE l.user_id=p_user_id AND l.lifecycle_key=p_expected_lifecycle_key AND l.closed_at IS NULL;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('status','forbidden','reason','stale_lifecycle');
  END IF;

  -- One post-lock clock and the locked account's literal current database zone.
  observed_at:=COALESCE(p_at,pg_catalog.clock_timestamp());
  IF official_zone IS NULL OR official_zone=''
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z
      WHERE (z.name COLLATE "C")=(official_zone COLLATE "C")) THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','zone_unproved');
  END IF;
  IF NOT pg_catalog.isfinite(observed_at)
    OR EXTRACT(YEAR FROM (observed_at AT TIME ZONE 'UTC')) NOT BETWEEN 1 AND 9999 THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved');
  END IF;
  local_clock:=observed_at AT TIME ZONE official_zone;
  IF NOT pg_catalog.isfinite(local_clock) OR EXTRACT(YEAR FROM local_clock) NOT BETWEEN 1 AND 9999 THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved');
  END IF;
  local_date:=local_clock::date;
  monday:=local_date-(EXTRACT(ISODOW FROM local_date)::integer-1);
  IF NOT pg_catalog.isfinite(local_date) OR NOT pg_catalog.isfinite(monday)
    OR local_date NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    OR monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unproved');
  END IF;

  SELECT s.* INTO calendar_scope FROM private.workout_strength_calendar_scopes s
    WHERE s.user_id=p_user_id AND s.lifecycle_key=p_expected_lifecycle_key
      AND s.time_zone=(official_zone COLLATE "C")
      AND s.week_start_date=monday AND s.as_of_local_date=local_date;
  IF FOUND THEN
    result_status:='reuse_existing';
  ELSE
    INSERT INTO private.workout_strength_calendar_scopes(
      user_id,lifecycle_key,scope_key,time_zone,week_start_date,as_of_local_date,created_at
    ) VALUES (
      p_user_id,p_expected_lifecycle_key,pg_catalog.gen_random_uuid(),official_zone,monday,local_date,observed_at
    ) RETURNING * INTO calendar_scope;
    result_status:='prepared';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',result_status,'scope',pg_catalog.jsonb_build_object(
    'ownerID',calendar_scope.user_id,'lifecycleKey',calendar_scope.lifecycle_key,'scopeKey',calendar_scope.scope_key,
    'timeZone',calendar_scope.time_zone,'weekStartDate',pg_catalog.to_char(calendar_scope.week_start_date,'YYYY-MM-DD'),
    'asOfLocalDate',pg_catalog.to_char(calendar_scope.as_of_local_date,'YYYY-MM-DD')
  ));
END;
$calendar_at$;
REVOKE ALL ON FUNCTION private.prepare_workout_strength_calendar_scope_at(uuid,uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
DO $replace_calendar$
DECLARE original text;definition text;metadata jsonb;after_metadata jsonb;
 next_body constant text:=$public_calendar$
BEGIN
 RETURN private.prepare_workout_strength_calendar_scope_at(p_user_id,p_expected_lifecycle_key,NULL::timestamptz);
END;
$public_calendar$;
BEGIN
 SELECT prosrc,pg_get_functiondef(oid),to_jsonb(p)-'prosrc' INTO STRICT original,definition,metadata
  FROM pg_proc p WHERE p.oid='public.prepare_workout_strength_calendar_scope(uuid,uuid)'::regprocedure;
 IF encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex')<>'0e89ab7ecc960ad45e2875a9bcb87fcd86daba482203288f157f535ddbc96dfd'
 THEN RAISE EXCEPTION 'strength_week_projection_calendar_source_drift' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,original,next_body);
 SELECT to_jsonb(p)-'prosrc' INTO STRICT after_metadata FROM pg_proc p
  WHERE p.oid='public.prepare_workout_strength_calendar_scope(uuid,uuid)'::regprocedure;
 IF after_metadata IS DISTINCT FROM metadata OR (SELECT prosrc FROM pg_proc
   WHERE oid='public.prepare_workout_strength_calendar_scope(uuid,uuid)'::regprocedure) IS DISTINCT FROM next_body
 THEN RAISE EXCEPTION 'strength_week_projection_calendar_contract_changed' USING ERRCODE='55000';END IF;
END $replace_calendar$;
CREATE FUNCTION private.get_mobile_strength_week_projection_at(
 p_user_id uuid,p_expected_generation uuid,p_target_id uuid,p_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $projection_at$
DECLARE
 authority private.workout_strength_authority_epochs%ROWTYPE;
 life private.workout_strength_lifecycles%ROWTYPE;
 week_scope private.strength_week_scopes%ROWTYPE;
 stored private.strength_week_targets%ROWTYPE;
 owner_zone text;at timestamptz;local_clock timestamp;local_date date;monday date;
 bound jsonb;target_wire jsonb;calendar_reply jsonb;calendar jsonb;projected jsonb;
 negative jsonb;negative_rollback boolean:=false;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_expected_generation IS NULL OR p_target_id IS NULL THEN
  RAISE EXCEPTION 'invalid_strength_week_projection_input' USING ERRCODE='22023';END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'strength_week_projection_requires_read_committed' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 SELECT u.timezone INTO owner_zone FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'strength_week_projection_patient_not_found' USING ERRCODE='P0002';END IF;
 -- Non-locking probes under the exclusive owner fence preserve generation
 -- precedence after reset, without taking a Y row lock before authority/L.
 IF NOT EXISTS(SELECT 1 FROM private.strength_week_scopes s WHERE s.user_id=p_user_id
  AND s.generation=p_expected_generation AND s.closed_at IS NULL) THEN
  RETURN jsonb_build_object('status','conflict','reason','generation_changed');END IF;
 IF NOT EXISTS(SELECT 1 FROM private.strength_week_targets t WHERE t.user_id=p_user_id
  AND t.generation=p_expected_generation AND t.target_id=p_target_id) THEN
  RETURN jsonb_build_object('status','conflict','reason','target_changed');END IF;
 SELECT e.* INTO authority FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id FOR UPDATE;
 IF NOT FOUND OR authority.current_lifecycle_key IS NULL THEN
  RETURN jsonb_build_object('status','unavailable','reason','binding_unproved');END IF;
 SELECT l.* INTO life FROM private.workout_strength_lifecycles l
  WHERE l.user_id=p_user_id AND l.lifecycle_key=authority.current_lifecycle_key FOR UPDATE;
 IF NOT FOUND OR life.closed_at IS NOT NULL THEN
  RETURN jsonb_build_object('status','unavailable','reason','binding_unproved');END IF;
 SELECT s.* INTO week_scope FROM private.strength_week_scopes s
  WHERE s.user_id=p_user_id AND s.generation=p_expected_generation FOR UPDATE;
 IF NOT FOUND OR week_scope.closed_at IS NOT NULL THEN
  RETURN jsonb_build_object('status','conflict','reason','generation_changed');END IF;
 bound:=public.get_mobile_strength_week_lifecycle_binding(p_user_id,p_expected_generation,life.lifecycle_key);
 IF bound='{"status":"unavailable","reason":"binding_unproved"}'::jsonb THEN RETURN bound;END IF;
 IF bound->>'status' IS DISTINCT FROM 'ready' OR bound#>>'{proof,ownerID}' IS DISTINCT FROM p_user_id::text
  OR bound#>>'{proof,generation}' IS DISTINCT FROM p_expected_generation::text
  OR bound#>>'{proof,lifecycleKey}' IS DISTINCT FROM life.lifecycle_key::text
  OR bound#>>'{proof,epoch}' IS DISTINCT FROM authority.epoch::text THEN
  RAISE EXCEPTION 'strength_week_projection_storage_invalid' USING ERRCODE='XX001';END IF;
 SELECT t.* INTO stored FROM private.strength_week_targets t WHERE t.user_id=p_user_id
  AND t.generation=p_expected_generation AND t.target_id=p_target_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','conflict','reason','target_changed');END IF;
 SELECT private.strength_week_target_wire(stored,pv,fv) INTO STRICT target_wire
  FROM (SELECT 1) anchor
  LEFT JOIN private.strength_week_source_versions pv ON pv.user_id=stored.user_id
   AND pv.generation=stored.generation AND pv.source_version_id=stored.plan_source_version_id
  LEFT JOIN private.strength_week_source_versions fv ON fv.user_id=stored.user_id
   AND fv.generation=stored.generation AND fv.source_version_id=stored.frequency_source_version_id;
 -- This is the only observation clock for the composed operation. All fences
 -- and binding/target validation above have completed before it is sampled.
 at:=COALESCE(p_at,clock_timestamp());
 IF NOT isfinite(at) OR date_part('year',at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999 THEN
  RETURN jsonb_build_object('status','unavailable','reason','calendar_unproved');END IF;
 IF owner_zone IS NULL OR owner_zone='' OR NOT EXISTS(SELECT 1 FROM pg_timezone_names z
  WHERE (z.name COLLATE "C")=(owner_zone COLLATE "C")) THEN
  RETURN jsonb_build_object('status','unavailable','reason','zone_unproved');END IF;
 local_clock:=at AT TIME ZONE owner_zone;
 IF NOT isfinite(local_clock) OR date_part('year',local_clock) NOT BETWEEN 1 AND 9999 THEN
  RETURN jsonb_build_object('status','unavailable','reason','calendar_unproved');END IF;
 local_date:=local_clock::date;monday:=local_date-(extract(isodow FROM local_date)::integer-1);
 IF monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
  RETURN jsonb_build_object('status','unavailable','reason','calendar_unproved');END IF;
 IF (owner_zone COLLATE "C") IS DISTINCT FROM (stored.timezone_at_freeze COLLATE "C") THEN
  RETURN jsonb_build_object('status','unavailable','reason','timezone_incompatible');END IF;
 IF monday IS DISTINCT FROM stored.week_start THEN
  RETURN jsonb_build_object('status','conflict','reason','week_changed');END IF;
 IF at<stored.frozen_at OR at<life.opened_at OR at<week_scope.opened_at
  OR at<(bound#>>'{proof,boundAt}')::timestamptz THEN
  RETURN jsonb_build_object('status','unavailable','reason','calendar_unproved');END IF;
 BEGIN
  calendar_reply:=private.prepare_workout_strength_calendar_scope_at(p_user_id,life.lifecycle_key,at);
  calendar:=calendar_reply->'scope';
  IF COALESCE(calendar_reply->>'status' IN('prepared','reuse_existing'),false) IS NOT TRUE OR calendar IS NULL
   OR calendar->>'ownerID' IS DISTINCT FROM p_user_id::text
   OR calendar->>'lifecycleKey' IS DISTINCT FROM life.lifecycle_key::text
   OR calendar->>'timeZone' IS DISTINCT FROM owner_zone
   OR calendar->>'weekStartDate' IS DISTINCT FROM to_char(monday::timestamp,'YYYY-MM-DD')
   OR calendar->>'asOfLocalDate' IS DISTINCT FROM to_char(local_date::timestamp,'YYYY-MM-DD') THEN
   RAISE EXCEPTION 'strength_week_projection_storage_invalid' USING ERRCODE='XX001';END IF;
  projected:=public.get_confirmed_workouts_for_strength_week(p_user_id,life.lifecycle_key,
   (calendar->>'scopeKey')::uuid,owner_zone,monday,local_date);
  IF projected->>'status'='unavailable' AND projected->>'reason' IN('provenance_gap','calendar_unproved','identity_unproved')
   AND projected->'workouts'='null'::jsonb THEN
   negative:=jsonb_build_object('status','unavailable','reason',projected->>'reason');
   negative_rollback:=true;
   RAISE EXCEPTION 'strength_week_projection_rollback_calendar_negative' USING ERRCODE='P5N01';
  END IF;
  IF projected->>'status' IS DISTINCT FROM 'available' OR jsonb_typeof(projected->'workouts') IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'strength_week_projection_storage_invalid' USING ERRCODE='XX001';END IF;
  RETURN jsonb_build_object('status','available','target',target_wire,'binding',bound->'proof',
   'calendar',calendar,'projection',projected,'observed_at',to_char(at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
 EXCEPTION WHEN SQLSTATE 'P5N01' THEN
  IF negative_rollback IS NOT TRUE OR SQLERRM<>'strength_week_projection_rollback_calendar_negative' OR negative IS NULL THEN RAISE;END IF;
  RETURN negative;
 END;
END;
$projection_at$;
REVOKE ALL ON FUNCTION private.get_mobile_strength_week_projection_at(uuid,uuid,uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.get_mobile_strength_week_projection(p_user_id uuid,p_expected_generation uuid,p_target_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $public_projection$
BEGIN
 RETURN private.get_mobile_strength_week_projection_at(p_user_id,p_expected_generation,p_target_id,NULL::timestamptz);
END;
$public_projection$;
REVOKE ALL ON FUNCTION public.get_mobile_strength_week_projection(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_strength_week_projection(uuid,uuid,uuid) TO service_role;
DO $privileges$
DECLARE sig text;f record;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
  'private.prepare_workout_strength_calendar_scope_at(uuid,uuid,timestamptz)',
  'private.get_mobile_strength_week_projection_at(uuid,uuid,uuid,timestamptz)',
  'public.get_mobile_strength_week_projection(uuid,uuid,uuid)'] LOOP
  SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.oid=to_regprocedure(sig);
  IF pg_get_userbyid(f.proowner)<>'postgres' OR f.provolatile<>'v'
   OR f.prosecdef IS DISTINCT FROM (sig LIKE 'public.%')
   OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
    WHERE a.grantee<>f.proowner AND (sig NOT LIKE 'public.%' OR a.grantee<>'service_role'::regrole::oid))
   OR has_function_privilege('anon',to_regprocedure(sig),'EXECUTE')
   OR has_function_privilege('authenticated',to_regprocedure(sig),'EXECUTE')
   OR has_function_privilege('service_role',to_regprocedure(sig),'EXECUTE') IS DISTINCT FROM (sig LIKE 'public.%')
  THEN RAISE EXCEPTION 'strength_week_projection_unexpected_privileges:%',sig USING ERRCODE='42501';END IF;
 END LOOP;
END $privileges$;
COMMIT;

-- Finite accepted plans apply inclusively at Monday00 in the official week timezone.
-- Preserve the last source, its original validity and proof; never revive an older plan.
-- Existing frozen targets retain their original week/timezone and remain authoritative.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $migration$
DECLARE sig text;before_sha text;after_sha text;next_body text;
  original text;definition text;metadata jsonb;actual jsonb;target regprocedure;digest text;
BEGIN
 IF current_user<>'postgres' THEN
  RAISE EXCEPTION 'strength_week_finite_validity_requires_postgres' USING ERRCODE='42501';
 END IF;
 FOR sig,before_sha,after_sha,next_body IN SELECT * FROM (VALUES
    ('private.strength_week_target_wire(private.strength_week_targets,private.strength_week_source_versions,private.strength_week_source_versions)','b938a4d2c24c9a2b14744a768a8c2dbb974659fc1ab3662c035e2299dfad9ad8','5367ecbd3a925964b6c60b4ea54fe061341600af7a746120ffd730c900283f0a',$p2_body$
DECLARE week_start_at timestamptz;plan_applicable boolean:=false;fallback_proven boolean:=false;
BEGIN
  IF p_target.target_id IS NULL
    OR (p_target.plan_source_version_id IS NOT NULL AND
      (p_plan.source_version_id IS DISTINCT FROM p_target.plan_source_version_id
       OR p_plan.user_id IS DISTINCT FROM p_target.user_id
       OR p_plan.generation IS DISTINCT FROM p_target.generation
       OR p_plan.source_kind IS DISTINCT FROM 'accepted_plan'))
    OR (p_target.frequency_source_version_id IS NOT NULL AND
      (p_frequency.source_version_id IS DISTINCT FROM p_target.frequency_source_version_id
       OR p_frequency.user_id IS DISTINCT FROM p_target.user_id
       OR p_frequency.generation IS DISTINCT FROM p_target.generation
       OR p_frequency.source_kind IS DISTINCT FROM 'informed_frequency'))
  THEN RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE = 'XX001'; END IF;
  -- Revalidate finite plan applicability against the frozen week's civil
  -- Monday and its original timezone, never the current owner timezone/clock.
  IF p_target.plan_source_version_id IS NOT NULL AND p_plan.fact='value' THEN
    IF p_plan.source_valid_until IS NULL THEN
      plan_applicable:=true;
    ELSE
      IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=p_target.timezone_at_freeze) THEN
        RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE='XX001';
      END IF;
      week_start_at:=p_target.week_start::timestamp AT TIME ZONE p_target.timezone_at_freeze;
      plan_applicable:=p_plan.source_valid_until>=week_start_at;
    END IF;
  END IF;
  fallback_proven:=p_target.plan_source_version_id IS NOT NULL AND
    (p_plan.fact='absent' OR (p_plan.fact='value' AND p_plan.source_valid_until IS NOT NULL
      AND plan_applicable IS FALSE));
  IF (p_target.source = 'accepted_plan' AND
      (plan_applicable IS NOT TRUE OR p_plan.planned_days IS DISTINCT FROM p_target.planned_days))
    OR (p_target.source = 'informed_frequency' AND
      (fallback_proven IS NOT TRUE OR p_frequency.fact IS DISTINCT FROM 'value'
       OR p_frequency.planned_days IS DISTINCT FROM p_target.planned_days))
    OR (p_target.source = 'absent' AND
      (fallback_proven IS NOT TRUE OR p_frequency.fact IS DISTINCT FROM 'absent'))
  THEN RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE = 'XX001'; END IF;
  RETURN pg_catalog.jsonb_build_object(
    'target_id',p_target.target_id,'user_id',p_target.user_id,'generation',p_target.generation,
    'week_start',pg_catalog.to_char(p_target.week_start::timestamp,'YYYY-MM-DD'),
    'timezone_at_freeze',p_target.timezone_at_freeze,'planned_days',p_target.planned_days,
    'source',p_target.source,
    'source_key',CASE p_target.source WHEN 'accepted_plan' THEN p_plan.source_version_id
      WHEN 'informed_frequency' THEN p_frequency.source_version_id ELSE NULL END,
    'frozen_at',pg_catalog.to_char(p_target.frozen_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'source_proof',private.strength_week_proof_wire(
      p_plan.source_version_id,p_plan.source_order,p_frequency.source_version_id,p_frequency.source_order));
END;
$p2_body$),
    ('private.strength_week_context_snapshot(uuid,timestamptz)','1c0b0efea5a0a09f7b3d9d81cd0bf3690156fc8eaf09f5500d7304d39208fa96','04a45fab917de6988f8d5077f745e71a84f85834191fc0bc7b985571a6ddc526',$p2_body$
DECLARE owner_exists boolean; invalid_storage boolean; result jsonb;
BEGIN
  IF p_user_id IS NULL OR (p_observed_at IS NOT NULL AND
    (NOT pg_catalog.isfinite(p_observed_at)
      OR pg_catalog.date_part('year',p_observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999))
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE = '22023'; END IF;
  WITH observation AS MATERIALIZED (
    SELECT COALESCE(p_observed_at,pg_catalog.clock_timestamp()) AS at
  ), owned AS MATERIALIZED (
    SELECT u.id,u.timezone FROM public.users AS u
      WHERE u.id = p_user_id AND u.status = 'active'
  ), scope AS MATERIALIZED (
    SELECT s.* FROM private.strength_week_scopes AS s JOIN owned AS u ON u.id=s.user_id
      WHERE s.closed_at IS NULL
  ), calendar AS MATERIALIZED (
    SELECT local_calendar.*,CASE WHEN local_calendar.supported THEN
      local_calendar.monday::timestamp AT TIME ZONE local_calendar.timezone ELSE NULL END AS week_start_at
    FROM (
    SELECT o.at,u.id,u.timezone,
      EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=u.timezone) AS supported,
      CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=u.timezone)
        THEN pg_catalog.date_trunc('week',o.at AT TIME ZONE u.timezone)::date ELSE NULL END AS monday
    FROM observation AS o LEFT JOIN owned AS u ON true
    ) AS local_calendar
  ), all_sources AS MATERIALIZED (
    SELECT v.* FROM private.strength_week_source_versions AS v
      JOIN scope AS s ON s.user_id=v.user_id AND s.generation=v.generation
  ), winner AS MATERIALIZED (
    SELECT t.* FROM private.strength_week_targets AS t JOIN scope AS s
      ON s.user_id=t.user_id AND s.generation=t.generation
      JOIN calendar AS c ON c.monday=t.week_start
  ), selected_plan AS MATERIALIZED (
    SELECT v.* FROM all_sources AS v,calendar AS c
      WHERE v.source_kind='accepted_plan' AND v.effective_week_start<=c.monday
      ORDER BY v.effective_week_start DESC,v.source_order DESC LIMIT 1
  ), selected_frequency AS MATERIALIZED (
    SELECT v.* FROM all_sources AS v,calendar AS c
      WHERE v.source_kind='informed_frequency' AND v.effective_week_start<=c.monday
      ORDER BY v.effective_week_start DESC,v.source_order DESC LIMIT 1
  )
  SELECT c.id IS NOT NULL,
    w.target_id IS NULL AND EXISTS (
      SELECT 1 FROM all_sources AS v JOIN scope AS ss ON true
      WHERE v.observed_at < ss.opened_at
        OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=v.observed_timezone)
    ),
    CASE
      WHEN s.generation IS NULL THEN pg_catalog.jsonb_build_object('status','unavailable','reason','missing_scope')
      WHEN NOT c.supported OR c.monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN w.target_id IS NOT NULL THEN pg_catalog.jsonb_build_object('status','ready','context',
        pg_catalog.jsonb_build_object('user_id',c.id,'generation',s.generation,'timezone',c.timezone,
          'week_start',pg_catalog.to_char(c.monday::timestamp,'YYYY-MM-DD'),
          'observed_at',pg_catalog.to_char(c.at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'kind','existing_target','target',private.strength_week_target_wire(w::private.strength_week_targets,
            wp::private.strength_week_source_versions,wf::private.strength_week_source_versions)))
      WHEN pg_catalog.date_part('year',c.week_start_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN EXISTS(SELECT 1 FROM all_sources AS v
          WHERE v.source_kind='accepted_plan' AND v.observed_timezone<>c.timezone)
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN p.source_version_id IS NULL
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','history_incomplete')
      WHEN (p.fact='absent' OR (p.fact='value' AND p.source_valid_until IS NOT NULL
          AND p.source_valid_until<c.week_start_at)) AND EXISTS(SELECT 1 FROM all_sources AS v
          WHERE v.source_kind='informed_frequency' AND v.observed_timezone<>c.timezone)
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported')
      WHEN (p.fact='absent' OR (p.fact='value' AND p.source_valid_until IS NOT NULL
          AND p.source_valid_until<c.week_start_at)) AND f.source_version_id IS NULL
        THEN pg_catalog.jsonb_build_object('status','unavailable','reason','history_incomplete')
      ELSE pg_catalog.jsonb_build_object('status','ready','context',
        pg_catalog.jsonb_build_object('user_id',c.id,'generation',s.generation,'timezone',c.timezone,
          'week_start',pg_catalog.to_char(c.monday::timestamp,'YYYY-MM-DD'),
          'observed_at',pg_catalog.to_char(c.at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'kind','source_facts',
          'week_start_at',pg_catalog.to_char(c.week_start_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'plan',pg_catalog.jsonb_build_object('coverage','covered','receipt',private.strength_week_source_wire(p::private.strength_week_source_versions)),
          'frequency',CASE WHEN f.source_version_id IS NULL THEN pg_catalog.jsonb_build_object('coverage','unknown')
            ELSE pg_catalog.jsonb_build_object('coverage','covered','receipt',private.strength_week_source_wire(f::private.strength_week_source_versions)) END,
          'source_proof',private.strength_week_proof_wire(p.source_version_id,p.source_order,f.source_version_id,f.source_order)))
    END
  INTO owner_exists,invalid_storage,result
  FROM calendar AS c LEFT JOIN scope AS s ON true LEFT JOIN winner AS w ON true
    LEFT JOIN all_sources AS wp ON wp.source_version_id=w.plan_source_version_id
    LEFT JOIN all_sources AS wf ON wf.source_version_id=w.frequency_source_version_id
    LEFT JOIN selected_plan AS p ON true LEFT JOIN selected_frequency AS f ON true;
  IF NOT owner_exists THEN
    RAISE EXCEPTION 'mobile_strength_week_patient_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF invalid_storage THEN
    RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE = 'XX001';
  END IF;
  RETURN result;
END;
$p2_body$),
    ('private.freeze_mobile_strength_week_target_at(uuid,uuid,text,date,jsonb,jsonb,timestamptz)','4b3259bb66b89033ef508c6f4c40b02d15acdc682a6afe8e8953e86793328122','758456a27a724177afabdfb372e6d4b6ec45fafe8ff976ed71d593080c0fd62d',$p2_body$
DECLARE s private.strength_week_scopes; zone text; monday date; context_result jsonb; context jsonb;
  t private.strength_week_targets; p private.strength_week_source_versions;
  f private.strength_week_source_versions; new_id uuid; final_wire jsonb; proof jsonb;
  proposal jsonb; plan_ref uuid; frequency_ref uuid;
BEGIN
  IF p_expected_generation IS NULL OR p_expected_timezone IS NULL
    OR pg_catalog.length(pg_catalog.btrim(p_expected_timezone))=0
    OR p_expected_week_start IS NULL OR NOT pg_catalog.isfinite(p_expected_week_start)
    OR p_expected_week_start NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
    OR pg_catalog.date_part('isodow',p_expected_week_start::timestamp)<>1
    OR p_observed_at IS NULL OR NOT pg_catalog.isfinite(p_observed_at)
    OR pg_catalog.date_part('year',p_observed_at AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
    OR NOT private.strength_week_freeze_shape(p_source_proof,p_proposal)
  THEN RAISE EXCEPTION 'invalid_mobile_strength_week_input' USING ERRCODE='22023'; END IF;
  zone:=private.strength_week_lock_owner(p_user_id);
  SELECT a.* INTO s FROM private.strength_week_scopes AS a
    WHERE a.user_id=p_user_id AND a.closed_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    IF EXISTS(SELECT 1 FROM private.strength_week_scopes AS a
      WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.closed_at IS NOT NULL)
    THEN RETURN pg_catalog.jsonb_build_object('status','conflict','reason','generation_changed'); END IF;
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','missing_scope');
  END IF;
  IF s.generation<>p_expected_generation THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','generation_changed');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name=zone) THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported');
  END IF;
  monday:=pg_catalog.date_trunc('week',p_observed_at AT TIME ZONE zone)::date;
  IF monday NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
    RETURN pg_catalog.jsonb_build_object('status','unavailable','reason','calendar_unsupported');
  END IF;
  IF zone<>p_expected_timezone THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','timezone_changed');
  END IF;
  IF monday<>p_expected_week_start THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','week_changed');
  END IF;
  -- Existing durable fact wins before proof/proposal SEMANTICS or later sources.
  SELECT a.* INTO t FROM private.strength_week_targets AS a
    WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.week_start=monday;
  IF FOUND THEN
    SELECT a.* INTO p FROM private.strength_week_source_versions AS a
      WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.source_version_id=t.plan_source_version_id;
    SELECT a.* INTO f FROM private.strength_week_source_versions AS a
      WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.source_version_id=t.frequency_source_version_id;
    RETURN pg_catalog.jsonb_build_object('status','reused','target',private.strength_week_target_wire(t,p,f));
  END IF;
  context_result:=private.strength_week_context_snapshot(p_user_id,p_observed_at);
  IF context_result->>'status'='unavailable' THEN RETURN context_result; END IF;
  context:=context_result->'context';
  IF context->>'kind' IS DISTINCT FROM 'source_facts' THEN
    RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE='XX001';
  END IF;
  proof:=context->'source_proof';
  IF proof IS DISTINCT FROM p_source_proof THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','source_proof_changed');
  END IF;
  plan_ref:=(proof#>>'{plan,source_version_id}')::uuid;
  frequency_ref:=(proof#>>'{frequency,source_version_id}')::uuid;
  IF context#>>'{plan,receipt,fact}'='value' AND
    (context#>>'{plan,receipt,source_valid_until}' IS NULL OR
     (context#>>'{plan,receipt,source_valid_until}')::timestamptz>=(context->>'week_start_at')::timestamptz) THEN
    proposal:=pg_catalog.jsonb_build_object('source','accepted_plan',
      'planned_days',context#>'{plan,receipt,planned_days}','source_key',plan_ref);
  ELSIF context#>>'{frequency,receipt,fact}'='value' THEN
    proposal:=pg_catalog.jsonb_build_object('source','informed_frequency',
      'planned_days',context#>'{frequency,receipt,planned_days}','source_key',frequency_ref);
  ELSE
    proposal:=pg_catalog.jsonb_build_object('source','absent','planned_days',NULL,'source_key',NULL);
  END IF;
  IF proposal IS DISTINCT FROM p_proposal THEN
    RETURN pg_catalog.jsonb_build_object('status','conflict','reason','proposal_mismatch');
  END IF;
  INSERT INTO private.strength_week_targets(user_id,generation,week_start,timezone_at_freeze,
    planned_days,source,plan_source_version_id,frequency_source_version_id,frozen_at)
  VALUES(p_user_id,p_expected_generation,monday,zone,(proposal->>'planned_days')::smallint,
    proposal->>'source',plan_ref,frequency_ref,p_observed_at)
  ON CONFLICT (user_id,generation,week_start) DO NOTHING RETURNING target_id INTO new_id;
  -- Fresh READ COMMITTED statement: read the stored winner, never echo proposal.
  SELECT private.strength_week_target_wire(a,pv,fv) INTO final_wire
    FROM private.strength_week_targets AS a
    LEFT JOIN private.strength_week_source_versions AS pv
      ON pv.user_id=a.user_id AND pv.generation=a.generation AND pv.source_version_id=a.plan_source_version_id
    LEFT JOIN private.strength_week_source_versions AS fv
      ON fv.user_id=a.user_id AND fv.generation=a.generation AND fv.source_version_id=a.frequency_source_version_id
    WHERE a.user_id=p_user_id AND a.generation=p_expected_generation AND a.week_start=monday;
  IF final_wire IS NULL THEN
    RAISE EXCEPTION 'mobile_strength_week_storage_invalid' USING ERRCODE='XX001';
  END IF;
  RETURN pg_catalog.jsonb_build_object('status',CASE WHEN new_id IS NULL THEN 'reused' ELSE 'frozen' END,
    'target',final_wire);
END;
$p2_body$)
 ) v(signature,original_sha256,next_sha256,next_body) LOOP
  target:=to_regprocedure(sig);
  IF target IS NULL THEN RAISE EXCEPTION 'strength_week_finite_validity_requires_substrate:%',sig USING ERRCODE='42P01';END IF;
  SELECT p.prosrc,pg_get_functiondef(p.oid),to_jsonb(p)-'prosrc' INTO STRICT original,definition,metadata
   FROM pg_proc p WHERE p.oid=target;
  IF pg_get_userbyid((metadata->>'proowner')::oid)<>'postgres'
   OR metadata->>'prosecdef'<>'false' OR metadata->>'provolatile'<>'v'
   OR (SELECT lanname FROM pg_language WHERE oid=(metadata->>'prolang')::oid)<>'plpgsql'
   OR metadata->'proconfig' IS DISTINCT FROM '["search_path=pg_catalog"]'::jsonb
   OR has_function_privilege('anon',target,'EXECUTE')
   OR has_function_privilege('authenticated',target,'EXECUTE')
   OR has_function_privilege('service_role',target,'EXECUTE')
  THEN RAISE EXCEPTION 'strength_week_finite_validity_contract_drift:%',sig USING ERRCODE='55000';END IF;
  digest:=encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex');
  IF digest=after_sha THEN CONTINUE;END IF;
  IF digest<>before_sha OR encode(extensions.digest(convert_to(next_body,'UTF8'),'sha256'),'hex')<>after_sha THEN
   RAISE EXCEPTION 'strength_week_finite_validity_source_drift:%',sig USING ERRCODE='55000';
  END IF;
  EXECUTE replace(definition,original,next_body);
  SELECT to_jsonb(p)-'prosrc' INTO STRICT actual FROM pg_proc p WHERE p.oid=target;
  IF actual IS DISTINCT FROM metadata OR (SELECT prosrc FROM pg_proc WHERE oid=target) IS DISTINCT FROM next_body THEN
   RAISE EXCEPTION 'strength_week_finite_validity_changed_contract:%',sig USING ERRCODE='55000';
  END IF;
 END LOOP;
END $migration$;
COMMIT;

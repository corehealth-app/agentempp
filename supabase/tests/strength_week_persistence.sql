-- Sequential weekly-strength persistence regression; run only in an exclusive
-- synthetic local database after the migration and fixture below are installed.
-- Fixture: fixtures/strength_week_fixture_support.sql. Sequence gaps are retained.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';

DO $preflight$
DECLARE signature text;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'public.get_mobile_strength_week_context(uuid)',
    'public.freeze_mobile_strength_week_target(uuid,uuid,text,date,jsonb,jsonb)',
    'private.open_strength_week_scope(uuid,text,text)',
    'private.roll_strength_week_scope(uuid,uuid,text,text)',
    'private.capture_strength_week_source(uuid,uuid,text,text,smallint,uuid,timestamp with time zone,text,text)',
    'private.get_mobile_strength_week_context_at(uuid,timestamp with time zone)',
    'private.freeze_mobile_strength_week_target_at(uuid,uuid,text,date,jsonb,jsonb,timestamp with time zone)',
    'private.capture_strength_week_source_at(uuid,uuid,text,text,smallint,uuid,timestamp with time zone,text,text,timestamp with time zone)'
  ] LOOP
    IF to_regprocedure(signature) IS NULL THEN
      RAISE EXCEPTION 'C59A2_SETUP_UNIMPLEMENTED:%',signature;
    END IF;
  END LOOP;
END $preflight$;

-- W1: every row has its own owner/scope; no cross-case replacement/reset.
DO $w1$
DECLARE x record;o jsonb;p jsonb;f jsonb;r jsonb;fr jsonb;again jsonb;proposal jsonb;
  expected_proof jsonb;before_sources bigint;
BEGIN
  FOR x IN SELECT * FROM (VALUES
    ('plan-wins',true,3,true,4,'accepted_plan',3,true),
    ('fallback-four',true,NULL,true,4,'informed_frequency',4,true),
    ('fallback-zero',true,NULL,true,0,'informed_frequency',0,true),
    ('both-absent',true,NULL,true,NULL,'absent',NULL,true),
    ('plan-lower-unknown',true,3,false,NULL,'accepted_plan',3,true),
    ('higher-unknown',false,NULL,true,4,NULL,NULL,false),
    ('lower-unknown',true,NULL,false,NULL,NULL,NULL,false),
    ('entire-history-unknown',false,NULL,false,NULL,NULL,NULL,false)
  ) AS t(label,plan_known,pdays,freq_known,fdays,source,expected_days,ready) LOOP
    o:=c59a2_fixture.new_owner('W1-'||x.label);p:=NULL;f:=NULL;
    IF x.plan_known THEN p:=c59a2_fixture.plan(o,x.pdays::smallint,x.label||'-plan');END IF;
    IF x.freq_known THEN f:=c59a2_fixture.frequency(o,x.fdays::smallint,x.label||'-freq');END IF;
    SELECT count(*) INTO before_sources FROM private.strength_week_source_versions
      WHERE user_id=(o->>'user_id')::uuid;
    r:=c59a2_fixture.read_at(o);
    PERFORM c59a2_fixture.ok((SELECT count(*)=before_sources FROM private.strength_week_source_versions
      WHERE user_id=(o->>'user_id')::uuid) AND
      (SELECT count(*)=0 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
      'W1-'||x.label||':read_no_writes');
    IF NOT x.ready THEN
      PERFORM c59a2_fixture.ok(r='{"status":"unavailable","reason":"history_incomplete"}',
        'W1-'||x.label||':unknown_not_absent');
      CONTINUE;
    END IF;
    expected_proof:=jsonb_build_object(
      'plan',CASE WHEN p IS NULL THEN '{"coverage":"unknown"}'::jsonb ELSE
        jsonb_build_object('coverage','covered','source_version_id',p->'source_version_id','source_order',p->'source_order') END,
      'frequency',CASE WHEN f IS NULL THEN '{"coverage":"unknown"}'::jsonb ELSE
        jsonb_build_object('coverage','covered','source_version_id',f->'source_version_id','source_order',f->'source_order') END);
    PERFORM c59a2_fixture.ok(r->>'status'='ready' AND r#>>'{context,kind}'='source_facts'
      AND r#>'{context,source_proof}'=expected_proof,'W1-'||x.label||':exact_coverage_proof');
    proposal:=c59a2_fixture.proposal(x.source,x.expected_days::smallint,
      CASE x.source WHEN 'accepted_plan' THEN p->>'source_version_id'
        WHEN 'informed_frequency' THEN f->>'source_version_id' ELSE NULL END);
    fr:=c59a2_fixture.freeze_at(o,r,proposal);
    PERFORM c59a2_fixture.ok(fr->>'status'='frozen' AND
      fr#>'{target,planned_days}'=proposal->'planned_days' AND
      fr#>'{target,source}'=proposal->'source' AND fr#>'{target,source_key}'=proposal->'source_key' AND
      fr#>'{target,source_proof}'=expected_proof AND fr#>>'{target,user_id}'=o->>'user_id' AND
      fr#>>'{target,generation}'=o->>'generation' AND fr#>>'{target,week_start}'='2026-10-12',
      'W1-'||x.label||':frozen_exact_owned_proposal');
    again:=c59a2_fixture.freeze_at(o,r,proposal);
    PERFORM c59a2_fixture.ok(again->>'status'='reused' AND again->'target'=fr->'target'
      AND (SELECT count(*)=1 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
      'W1-'||x.label||':replay_identical_target');
    r:=c59a2_fixture.read_at(o);
    PERFORM c59a2_fixture.ok(r#>>'{context,kind}'='existing_target' AND r#>'{context,target}'=fr->'target',
      'W1-'||x.label||':read_stored_target');
  END LOOP;
END $w1$;

DO $bounds$
DECLARE o jsonb;p jsonb;r jsonb;days smallint;bad jsonb;
BEGIN
  o:=c59a2_fixture.ready_case('W1-bounds');p:=o->'plan';r:=o->'read';
  FOREACH days IN ARRAY ARRAY[0,8]::smallint[] LOOP
    PERFORM c59a2_fixture.throws(format(
      'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,%s::smallint,%L::uuid,NULL,%L,%L,%L::timestamptz)',
      o->>'user_id',o->>'generation','accepted_plan','value',days,p->>'source_entity_id',
      'c59a2.fixture','bad-plan-'||days,'2026-10-08T12:00:00Z'),
      '22023','invalid_mobile_strength_week_input','W1:invalid_plan_producer_'||days);
  END LOOP;
  FOREACH days IN ARRAY ARRAY[-1,8]::smallint[] LOOP
    PERFORM c59a2_fixture.throws(format(
      'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,%s::smallint,NULL,NULL,%L,%L,%L::timestamptz)',
      o->>'user_id',o->>'generation','informed_frequency','value',days,
      'c59a2.fixture','bad-freq-'||days,'2026-10-08T12:00:00Z'),
      '22023','invalid_mobile_strength_week_input','W1:invalid_frequency_producer_'||days);
  END LOOP;
  PERFORM c59a2_fixture.throws(format(
    'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,NULL,NULL,NULL,%L,%L,%L::timestamptz)',
    o->>'user_id',o->>'generation','informed_frequency','value','c59a2.fixture','bad-null-value','2026-10-08T00:00:00.000000Z'),
    '22023','invalid_mobile_strength_week_input','W1:null_is_not_value');
  FOR bad IN SELECT v FROM (VALUES
    ('{"source":"accepted_plan","planned_days":3.5,"source_key":"00000000-0000-0000-0000-000000000001"}'::jsonb),
    ('{"source":"accepted_plan","planned_days":"3","source_key":"00000000-0000-0000-0000-000000000001"}'::jsonb),
    ('{"source":"absent","planned_days":null,"source_key":null,"extra":true}'::jsonb),
    ('{"source":"unknown","planned_days":3,"source_key":null}'::jsonb)
  ) z(v) LOOP
    PERFORM c59a2_fixture.throws(format('SELECT c59a2_fixture.freeze_at(%L::jsonb,%L::jsonb,%L::jsonb)',o,r,bad),
      '22023','invalid_mobile_strength_week_input','W1:strict_JSON_not_smallint_coercion');
  END LOOP;
  PERFORM c59a2_fixture.ok((SELECT count(*)=0 FROM private.strength_week_targets
    WHERE user_id=(o->>'user_id')::uuid),'W1:invalid_inputs_zero_targets');
END $bounds$;

-- W3: causal changed facts are established before the conflict oracle.
DO $w3$
DECLARE o jsonb;foreign_o jsonb;r jsonb;p jsonb;q jsonb;result jsonb;fresh jsonb;new_scope jsonb;
BEGIN
  o:=c59a2_fixture.ready_case('W3-proof');r:=o->'read';p:=o->'proposal';
  foreign_o:=c59a2_fixture.ready_case('W3-foreign');
  q:=jsonb_set(r,'{context,source_proof,plan,source_version_id}',foreign_o#>'{plan,source_version_id}');
  result:=c59a2_fixture.freeze_at(o,q,p);
  PERFORM c59a2_fixture.ok(result='{"status":"conflict","reason":"source_proof_changed"}','W3:foreign_receipt');
  q:=jsonb_set(r,'{context,source_proof,plan,source_order}','"9223372036854775807"');
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,q,p)='{"status":"conflict","reason":"source_proof_changed"}',
    'W3:changed_opaque_order');
  q:=jsonb_set(r,'{context,source_proof,frequency}','{"coverage":"unknown"}');
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,q,p)='{"status":"conflict","reason":"source_proof_changed"}',
    'W3:changed_coverage');
  q:=jsonb_set(r,'{context,source_proof,plan}',r#>'{context,source_proof,frequency}');
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,q,p)='{"status":"conflict","reason":"source_proof_changed"}',
    'W3:wrong_kind_receipt');
  FOR q IN SELECT v FROM (VALUES
    (c59a2_fixture.proposal('accepted_plan',2::smallint,o#>>'{plan,source_version_id}')),
    (c59a2_fixture.proposal('accepted_plan',3::smallint,o#>>'{frequency,source_version_id}')),
    (c59a2_fixture.proposal('informed_frequency',4::smallint,o#>>'{frequency,source_version_id}'))
  ) z(v) LOOP
    PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,r,q)='{"status":"conflict","reason":"proposal_mismatch"}',
      'W3:proposal_value_key_priority');
  END LOOP;
  PERFORM c59a2_fixture.ok((SELECT count(*)=0 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
    'W3:forged_zero_targets');
  PERFORM c59a2_fixture.frequency(o,5::smallint,'W3-new-eligible','2026-10-09T00:00:00.000000Z');
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,r,p)='{"status":"conflict","reason":"source_proof_changed"}',
    'W3:changed_unnecessary_kind_still_full_proof_CAS');
  fresh:=c59a2_fixture.read_at(o);result:=c59a2_fixture.freeze_at(o,fresh,p);
  PERFORM c59a2_fixture.ok(result->>'status'='frozen','W3:current_snapshot_can_freeze');
  PERFORM c59a2_fixture.ok((c59a2_fixture.freeze_at(o,r,
    c59a2_fixture.proposal('informed_frequency',4::smallint,o#>>'{frequency,source_version_id}')))->'target'=result->'target',
    'W3:existing_winner_precedes_wellformed_stale_proof_and_lower_proposal');
  PERFORM c59a2_fixture.throws(format(
    'SELECT private.freeze_mobile_strength_week_target_at(%L::uuid,NULL,%L,%L::date,%L::jsonb,%L::jsonb,%L::timestamptz)',
    o->>'user_id','America/Sao_Paulo','2026-10-12',fresh#>'{context,source_proof}',p,'2026-10-12T12:00Z'),
    '22023','invalid_mobile_strength_week_input','W3:null_generation_not_current');
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,fresh,p,'2026-10-19T12:00Z')=
    '{"status":"conflict","reason":"week_changed"}','W3:week_before_winner');
  UPDATE public.users SET timezone='America/New_York' WHERE id=(o->>'user_id')::uuid;
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,fresh,p)=
    '{"status":"conflict","reason":"timezone_changed"}','W3:timezone_before_winner');
  UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=(o->>'user_id')::uuid;
  new_scope:=private.roll_strength_week_scope((o->>'user_id')::uuid,(o->>'generation')::uuid,'c59a2.fixture','W3-roll-scope');
  PERFORM c59a2_fixture.ok(new_scope->>'generation'<>o->>'generation','W3:actual_new_generation_setup');
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,fresh,p)=
    '{"status":"conflict","reason":"generation_changed"}','W3:generation_before_old_winner');
END $w3$;

DO $w4$
DECLARE k text;o jsonb;r jsonb;old jsonb;next_r jsonb;n jsonb;old_p jsonb;new_p jsonb;
BEGIN
  FOREACH k IN ARRAY ARRAY['frequency','plan','tombstone'] LOOP
    o:=c59a2_fixture.new_owner('W4-'||k);
    IF k='frequency' THEN
      PERFORM c59a2_fixture.plan(o,NULL,'W4-'||k||'-absent');
      n:=c59a2_fixture.frequency(o,4::smallint,'W4-'||k||'-old');
      old_p:=c59a2_fixture.proposal('informed_frequency',4::smallint,n->>'source_version_id');
    ELSE
      n:=c59a2_fixture.plan(o,4::smallint,'W4-'||k||'-old');
      PERFORM c59a2_fixture.frequency(o,2::smallint,'W4-'||k||'-freq');
      old_p:=c59a2_fixture.proposal('accepted_plan',4::smallint,n->>'source_version_id');
    END IF;
    r:=c59a2_fixture.read_at(o);old:=c59a2_fixture.freeze_at(o,r,old_p);
    PERFORM c59a2_fixture.ok(old->>'status'='frozen','W4-'||k||':initial_freeze');
    IF k='frequency' THEN
      n:=c59a2_fixture.frequency(o,3::smallint,'W4-'||k||'-new','2026-10-15T12:00:00.654321Z');
      new_p:=c59a2_fixture.proposal('informed_frequency',3::smallint,n->>'source_version_id');
    ELSIF k='plan' THEN
      n:=c59a2_fixture.plan(o,3::smallint,'W4-'||k||'-new','2026-10-15T12:00:00.654321Z');
      new_p:=c59a2_fixture.proposal('accepted_plan',3::smallint,n->>'source_version_id');
    ELSE
      n:=c59a2_fixture.plan(o,NULL,'W4-'||k||'-new','2026-10-15T12:00:00.654321Z');
      next_r:=c59a2_fixture.read_at(o,'2026-10-19T12:00Z');
      new_p:=c59a2_fixture.proposal('informed_frequency',2::smallint,next_r#>>'{context,frequency,receipt,source_version_id}');
    END IF;
    PERFORM c59a2_fixture.ok(n->>'effective_week_start'='2026-10-19'
      AND n->>'observed_at'='2026-10-15T12:00:00.654321Z'
      AND n->>'observed_timezone'='America/Sao_Paulo','W4-'||k||':next_local_Monday_exact_micros');
    PERFORM c59a2_fixture.ok((c59a2_fixture.read_at(o)#>'{context,target}')=old->'target'
      AND (c59a2_fixture.freeze_at(o,r,old_p)->'target')=old->'target','W4-'||k||':week12_immutable');
    next_r:=c59a2_fixture.read_at(o,'2026-10-19T12:00Z');
    r:=c59a2_fixture.freeze_at(o,next_r,new_p,'2026-10-19T12:00Z');
    PERFORM c59a2_fixture.ok(r->>'status'='frozen' AND r#>>'{target,week_start}'='2026-10-19'
      AND r#>'{target,planned_days}'=new_p->'planned_days' AND r#>'{target,source}'=new_p->'source',
      'W4-'||k||':new_week_new_source');
    PERFORM c59a2_fixture.ok((SELECT count(*)=2 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
      'W4-'||k||':history_retained');
  END LOOP;
END $w4$;

DO $w5$
DECLARE o jsonb;p jsonb;r jsonb;before_monday jsonb;after_monday jsonb;old jsonb;n jsonb;
BEGIN
  o:=c59a2_fixture.new_owner('W5-boundary');p:=c59a2_fixture.plan(o,3::smallint,'W5-plan-source');
  before_monday:=c59a2_fixture.read_at(o,'2026-10-19T02:59:59.999999Z');
  after_monday:=c59a2_fixture.read_at(o,'2026-10-19T03:00:00.000000Z');
  PERFORM c59a2_fixture.ok(before_monday#>>'{context,week_start}'='2026-10-12'
    AND after_monday#>>'{context,week_start}'='2026-10-19'
    AND before_monday#>>'{context,observed_at}'='2026-10-19T02:59:59.999999Z','W5:local_boundary_and_micros');
  old:=c59a2_fixture.freeze_at(o,after_monday,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'),
    '2026-10-19T03:00:00.000000Z');
  n:=c59a2_fixture.plan(o,5::smallint,'W5-on-Monday','2026-10-19T03:00:00.000001Z');
  PERFORM c59a2_fixture.ok(n->>'effective_week_start'='2026-10-26' AND
    (c59a2_fixture.read_at(o,'2026-10-19T03:00:00.000002Z')#>'{context,target}')=old->'target',
    'W5:Monday_capture_applies_following_Monday');
  o:=c59a2_fixture.new_owner('W5-DST','America/New_York');
  PERFORM c59a2_fixture.plan(o,3::smallint,'W5-DST-plan','2026-10-22T16:00Z');
  before_monday:=c59a2_fixture.read_at(o,'2026-11-02T04:59:59.999999Z');
  after_monday:=c59a2_fixture.read_at(o,'2026-11-02T05:00:00.000000Z');
  PERFORM c59a2_fixture.ok(before_monday#>>'{context,week_start}'='2026-10-26'
    AND after_monday#>>'{context,week_start}'='2026-11-02'
    AND timestamptz '2026-11-02 00:00 America/New_York'-timestamptz '2026-10-26 00:00 America/New_York'=interval '169 hours',
    'W5:DST_civil_not_168_hours');
END $w5$;

DO $w6$
DECLARE o jsonb;r jsonb;p jsonb;old jsonb;fresh jsonb;
BEGIN
  o:=c59a2_fixture.new_owner('W6-travel','Asia/Tokyo');
  p:=c59a2_fixture.plan(o,3::smallint,'W6-plan-source','2026-10-08T12:00Z');
  r:=c59a2_fixture.read_at(o,'2026-10-18T23:30Z');
  PERFORM c59a2_fixture.ok(r#>>'{context,week_start}'='2026-10-19','W6:Tokyo_real_context_setup');
  UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=(o->>'user_id')::uuid;
  PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,r,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'),
    '2026-10-18T23:30Z')='{"status":"conflict","reason":"timezone_changed"}',
    'W6:official_timezone_guard_before_week');
  PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o,'2026-10-18T23:30Z')=
    '{"status":"unavailable","reason":"calendar_unsupported"}','W6:fresh_lookup_not_cached_zone');
  o:=c59a2_fixture.ready_case('W6-same-week');r:=o->'read';
  old:=c59a2_fixture.freeze_at(o,r,o->'proposal');
  UPDATE public.users SET timezone='America/New_York' WHERE id=(o->>'user_id')::uuid;
  fresh:=c59a2_fixture.read_at(o);
  PERFORM c59a2_fixture.ok(fresh#>>'{context,timezone}'='America/New_York'
    AND fresh#>>'{context,week_start}'='2026-10-12' AND fresh#>'{context,target}'=old->'target'
    AND fresh#>>'{context,target,timezone_at_freeze}'='America/Sao_Paulo',
    'W6:same_named_week_preserves_old_target_and_zone');
  r:=jsonb_set(r,'{context,timezone}','"America/New_York"');
  PERFORM c59a2_fixture.ok((c59a2_fixture.freeze_at(o,r,o->'proposal')->'target')=old->'target'
    AND (SELECT count(*)=1 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
    'W6:timezone_not_part_of_target_key');
END $w6$;

DO $w7$
DECLARE completed boolean;o jsonb;s1 jsonb;s2 jsonb;s3 jsonb;r jsonb;p jsonb;old jsonb;n bigint;
  captured_after_open timestamptz;effective_week_at timestamptz;
BEGIN
  FOREACH completed IN ARRAY ARRAY[true,false] LOOP
    o:=c59a2_fixture.new_owner('W7-'||completed,'America/Sao_Paulo',false,completed);
    PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o)='{"status":"unavailable","reason":"missing_scope"}' AND
      (SELECT count(*)=0 FROM private.strength_week_scopes WHERE user_id=(o->>'user_id')::uuid),
      'W7:read_no_open_true_null_or_incomplete');
    s1:=private.open_strength_week_scope((o->>'user_id')::uuid,'c59a2.fixture','W7-open-scope');
    PERFORM c59a2_fixture.ok(s1=private.open_strength_week_scope((o->>'user_id')::uuid,'c59a2.fixture','W7-open-scope'),
      'W7:open_exact_active_replay');
    o:=o||jsonb_build_object('generation',s1->'generation');
    PERFORM c59a2_fixture.throws(format('SELECT private.open_strength_week_scope(%L::uuid,%L,%L)',
      o->>'user_id','c59a2.fixture','W7-other-open'),'40001','strength_week_scope_active','W7:different_open_conflicts');
    captured_after_open:=(s1->>'opened_at')::timestamptz+interval '1 microsecond';
    p:=c59a2_fixture.plan(o,3::smallint,'W7-source',captured_after_open);
    effective_week_at:=((p->>'effective_week_start')::date+time '12:00') AT TIME ZONE 'America/Sao_Paulo';
    r:=c59a2_fixture.read_at(o,effective_week_at);
    PERFORM c59a2_fixture.ok((p->>'observed_at')::timestamptz>(s1->>'opened_at')::timestamptz
      AND r#>>'{context,week_start}'=p->>'effective_week_start','W7:captured_after_open_eligible_week_setup');
    -- Scope/open/roll are real primitives; this future-Monday clock is explicitly
    -- synthetic. It does not claim a wall-clock real-writer/reset chronology.
    old:=c59a2_fixture.freeze_at(o,r,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'),effective_week_at);
    s2:=private.roll_strength_week_scope((o->>'user_id')::uuid,(o->>'generation')::uuid,'c59a2.fixture','W7-roll-one');
    PERFORM c59a2_fixture.ok(s2->>'generation'<>o->>'generation'
      AND s2->>'predecessor_generation'=o->>'generation'
      AND (SELECT count(*)=1 FROM private.strength_week_scopes WHERE user_id=(o->>'user_id')::uuid AND closed_at IS NULL)
      AND (SELECT count(*)=2 FROM private.strength_week_scopes WHERE user_id=(o->>'user_id')::uuid),
      'W7:roll_closes_and_appends_owned_generation');
    PERFORM c59a2_fixture.ok(s2=private.roll_strength_week_scope((o->>'user_id')::uuid,(o->>'generation')::uuid,
      'c59a2.fixture','W7-roll-one'),'W7:roll_replay_precedes_new_transition_guard');
    PERFORM c59a2_fixture.throws(format('SELECT private.roll_strength_week_scope(%L::uuid,%L::uuid,%L,%L)',
      o->>'user_id',s2->>'generation','c59a2.fixture','W7-roll-one'),
      '40001','strength_week_operation_conflict','W7:changed_replay_predecessor');
    PERFORM c59a2_fixture.ok(c59a2_fixture.freeze_at(o,r,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'),effective_week_at)=
      '{"status":"conflict","reason":"generation_changed"}' AND
      (SELECT count(*)=1 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid)
      AND (SELECT target_id::text=old#>>'{target,target_id}' FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
      'W7:late_generation_one_cannot_touch_two_history_retained');
    PERFORM c59a2_fixture.throws(format('SELECT private.open_strength_week_scope(%L::uuid,%L,%L)',
      o->>'user_id','c59a2.fixture','W7-open-scope'),'40001','strength_week_scope_closed','W7:closed_open_not_reopened');
    s3:=private.roll_strength_week_scope((o->>'user_id')::uuid,(s2->>'generation')::uuid,'c59a2.fixture','W7-roll-two');
    PERFORM c59a2_fixture.throws(format('SELECT private.roll_strength_week_scope(%L::uuid,%L::uuid,%L,%L)',
      o->>'user_id',o->>'generation','c59a2.fixture','W7-roll-one'),
      '40001','strength_week_scope_closed','W7:closed_roll_result_not_revived');
    n:=(SELECT count(*) FROM private.strength_week_scopes WHERE user_id=(o->>'user_id')::uuid);
    UPDATE public.users SET timezone='America/New_York' WHERE id=(o->>'user_id')::uuid;
    PERFORM c59a2_fixture.read_at(o,effective_week_at+interval '14 days');
    PERFORM c59a2_fixture.ok((SELECT count(*)=n FROM private.strength_week_scopes WHERE user_id=(o->>'user_id')::uuid)
      AND (SELECT onboarding_completed_at IS NULL AND onboarding_completed=completed
        FROM public.user_profiles WHERE user_id=(o->>'user_id')::uuid),
      'W7:no_photo_epoch_or_calendar_auto_roll');
  END LOOP;
END $w7$;

DO $w8$
DECLARE o jsonb;u uuid;before_rows jsonb;after_rows jsonb;
BEGIN
  o:=c59a2_fixture.new_owner('W8-unknown');u:=(o->>'user_id')::uuid;
  UPDATE public.user_profiles SET training_frequency=3 WHERE user_id=u;
  INSERT INTO public.training_plans(user_id,days_per_week,weekly_schedule)VALUES(u,3,'[]');
  before_rows:=jsonb_build_array((SELECT count(*) FROM private.strength_week_scopes),
    (SELECT count(*) FROM private.strength_week_source_versions),(SELECT count(*) FROM private.strength_week_targets));
  PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o)='{"status":"unavailable","reason":"history_incomplete"}',
    'W8:mutable_profile_plan_are_not_historical_receipts');
  after_rows:=jsonb_build_array((SELECT count(*) FROM private.strength_week_scopes),
    (SELECT count(*) FROM private.strength_week_source_versions),(SELECT count(*) FROM private.strength_week_targets));
  PERFORM c59a2_fixture.ok(before_rows=after_rows,'W8:read_exact_zero_writes');
  PERFORM c59a2_fixture.throws(format('SELECT public.get_mobile_strength_week_context(%L::uuid)',gen_random_uuid()),
    'P0002','mobile_strength_week_patient_not_found','W8:missing_owner_error_not_unavailable');
  UPDATE public.users SET status='blocked' WHERE id=u;
  PERFORM c59a2_fixture.throws(format('SELECT public.get_mobile_strength_week_context(%L::uuid)',u),
    'P0002','mobile_strength_week_patient_not_found','W8:inactive_owner_error_not_unavailable');
END $w8$;

DO $w9$
DECLARE o jsonb;a jsonb;b jsonb;c jsonb;r jsonb;u uuid;g uuid;
BEGIN
  o:=c59a2_fixture.new_owner('W9-replay');u:=(o->>'user_id')::uuid;g:=(o->>'generation')::uuid;
  PERFORM c59a2_fixture.plan(o,NULL,'W9-plan-absent');
  a:=c59a2_fixture.frequency(o,4::smallint,'W9-freq-replay','2026-10-08T12:00:00.123456Z');
  UPDATE public.user_profiles SET training_frequency=3 WHERE user_id=u;
  b:=private.capture_strength_week_source_at(u,g,'informed_frequency','value',4::smallint,NULL,NULL,
    'c59a2.fixture','W9-freq-replay','2026-10-15T12:00:00.654321Z');
  PERFORM c59a2_fixture.ok(a=b AND (SELECT count(*)=1 FROM private.strength_week_source_versions
    WHERE user_id=u AND source_kind='informed_frequency'),'W9:replay_immutable_original_despite_current_profile');
  PERFORM c59a2_fixture.throws(format(
    'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,3::smallint,NULL,NULL,%L,%L,%L::timestamptz)',
    u,g,'informed_frequency','value','c59a2.fixture','W9-freq-replay','2026-10-15T00:00:00.000000Z'),
    '40001','strength_week_operation_conflict','W9:changed_canonical_content');
  b:=c59a2_fixture.frequency(o,3::smallint,'W9-equal-time-one','2026-10-09T12:00:00.123456Z');
  c:=c59a2_fixture.frequency(o,5::smallint,'W9-equal-time-two','2026-10-09T12:00:00.123456Z');
  r:=c59a2_fixture.read_at(o);
  PERFORM c59a2_fixture.ok(b->'observed_at'=c->'observed_at'
    AND c->>'observed_at'='2026-10-09T12:00:00.123456Z'
    AND (c->>'source_order')::bigint>(b->>'source_order')::bigint
    AND r#>'{context,frequency,receipt}'=c,'W9:equal_timestamp_real_identity_order');
  -- Owner fixture only: exercise >2^53 wire/order with actual stored receipts.
  -- OVERRIDING does not claim these are naturally assigned adjacent identities.
  INSERT INTO private.strength_week_source_versions(source_version_id,user_id,generation,source_kind,
    fact,planned_days,source_entity_id,source_valid_until,operation_namespace,operation_key,
    observed_at,observed_timezone,effective_week_start,source_order) OVERRIDING SYSTEM VALUE
  VALUES(gen_random_uuid(),u,g,'informed_frequency','value',6,NULL,NULL,'c59a2.fixture','W9-big-first',
    '2026-10-09T12:00:00.123457Z','America/Sao_Paulo','2026-10-12',9007199254740993),
    (gen_random_uuid(),u,g,'informed_frequency','value',7,NULL,NULL,'c59a2.fixture','W9-big-second',
    '2026-10-09T12:00:00.123457Z','America/Sao_Paulo','2026-10-12',9007199254740994);
  r:=c59a2_fixture.read_at(o);
  PERFORM c59a2_fixture.ok(r#>>'{context,frequency,receipt,source_order}'='9007199254740994'
    AND jsonb_typeof(r#>'{context,frequency,receipt,source_order}')='string'
    AND r#>>'{context,frequency,receipt,planned_days}'='7'
    AND r#>>'{context,frequency,receipt,observed_at}'='2026-10-09T12:00:00.123457Z',
    'W9:bigint_and_microseconds_lossless');
  BEGIN
    PERFORM c59a2_fixture.frequency(o,2::smallint,'W9-rolled-back','2026-10-10T00:00:00.000000Z');
    RAISE EXCEPTION 'C59A2_FIXTURE_ROLLBACK' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;END;
  b:=c59a2_fixture.frequency(o,2::smallint,'W9-after-gap','2026-10-10T00:00:00.000000Z');
  PERFORM c59a2_fixture.ok((SELECT count(*)=0 FROM private.strength_week_source_versions
    WHERE user_id=u AND operation_key='W9-rolled-back') AND b->>'source_version_id' IS NOT NULL,
    'W9:rollback_gap_not_identity_collision');
END $w9$;

-- F1-A..H, including pending foreign-zone rows hidden by eligibility selection.
DO $f1$
DECLARE o jsonb;r jsonb;p jsonb;f jsonb;old jsonb;q jsonb;until_at timestamptz;variant text;
BEGIN
  o:=c59a2_fixture.ready_case('F1-A');r:=o->'read';old:=c59a2_fixture.freeze_at(o,r,o->'proposal');
  UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=(o->>'user_id')::uuid;
  PERFORM c59a2_fixture.plan(o,5::smallint,'F1-A-pending','2026-10-15T00:00:00.000000Z','2026-12-01T00:00:00.000000Z');
  UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=(o->>'user_id')::uuid;
  PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o)#>'{context,target}'=old->'target'
    AND (c59a2_fixture.freeze_at(o,r,o->'proposal')->'target')=old->'target','F1-A:winner_before_all_source_guards');
  o:=c59a2_fixture.new_owner('F1-B','Asia/Tokyo');
  p:=c59a2_fixture.plan(o,3::smallint,'F1-B-Tokyo-pending','2026-10-15T00:00:00.000000Z');
  PERFORM c59a2_fixture.ok(p->>'effective_week_start'='2026-10-19','F1-B:future_receipt_setup');
  UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=(o->>'user_id')::uuid;
  f:=c59a2_fixture.frequency(o,4::smallint,'F1-B-local-frequency','2026-10-08T00:00:00.000000Z');
  PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o,'2026-10-18T23:30Z')=
    '{"status":"unavailable","reason":"calendar_unsupported"}','F1-B:foreign_pending_plan_no_fallback');
  q:=jsonb_build_object('plan',jsonb_build_object('coverage','unknown'),'frequency',
    jsonb_build_object('coverage','covered','source_version_id',f->'source_version_id','source_order',f->'source_order'));
  PERFORM c59a2_fixture.ok(private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
    'Pacific/Honolulu','2026-10-12',q,c59a2_fixture.proposal('informed_frequency',4::smallint,f->>'source_version_id'),
    '2026-10-18T23:30Z')='{"status":"unavailable","reason":"calendar_unsupported"}' AND
    (SELECT count(*)=0 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
    'F1-B:freeze_pending_guard_and_zero_targets');
  FOREACH until_at IN ARRAY ARRAY[timestamptz '2026-10-09T00:00:00.000000Z',timestamptz '2099-12-31T00:00:00.000000Z'] LOOP
    o:=c59a2_fixture.new_owner('F1-C-'||extract(year FROM until_at));
    p:=c59a2_fixture.plan(o,3::smallint,'F1-C-finite','2026-10-08T00:00:00.000000Z',until_at);
    f:=c59a2_fixture.frequency(o,4::smallint,'F1-C-fallback');
    r:=c59a2_fixture.read_at(o);
    PERFORM c59a2_fixture.ok(r->>'status'='ready' AND r#>>'{context,kind}'='source_facts'
      AND r#>'{context,plan,receipt}'=p AND r#>'{context,frequency,receipt}'=f
      AND r#>>'{context,week_start_at}'='2026-10-12T03:00:00.000000Z',
      'F1-C:finite_selected_proof_preserved');
    q:=jsonb_build_object('plan',jsonb_build_object('coverage','covered','source_version_id',p->'source_version_id','source_order',p->'source_order'),
      'frequency',jsonb_build_object('coverage','covered','source_version_id',f->'source_version_id','source_order',f->'source_order'));
    IF until_at<timestamptz '2026-10-12T03:00:00.000000Z' THEN
      PERFORM c59a2_fixture.ok(private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
        'America/Sao_Paulo','2026-10-12',q,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'),
        '2026-10-12T12:00Z')='{"status":"conflict","reason":"proposal_mismatch"}',
        'F1-C:expired_plan_proposal_rejected');
      old:=private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
        'America/Sao_Paulo','2026-10-12',q,c59a2_fixture.proposal('informed_frequency',4::smallint,f->>'source_version_id'),'2026-10-12T12:00Z');
      PERFORM c59a2_fixture.ok(old->>'status'='frozen' AND old#>>'{target,source}'='informed_frequency'
        AND old#>>'{target,planned_days}'='4' AND old#>'{target,source_proof}'=q,
        'F1-C:expired_plan_falls_back_with_original_proof');
    ELSE
      old:=private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
        'America/Sao_Paulo','2026-10-12',q,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'),'2026-10-12T12:00Z');
      PERFORM c59a2_fixture.ok(old->>'status'='frozen' AND old#>>'{target,source}'='accepted_plan'
        AND old#>>'{target,planned_days}'='3' AND old#>'{target,source_proof}'=q,
        'F1-C:valid_finite_plan_freezes_with_original_proof');
    END IF;
  END LOOP;
  FOREACH variant IN ARRAY ARRAY['unknown','foreign-pending'] LOOP
    o:=c59a2_fixture.new_owner('F1-D-'||variant);
    p:=c59a2_fixture.plan(o,3::smallint,'F1-D-plan');
    IF variant='foreign-pending' THEN
      UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=(o->>'user_id')::uuid;
      PERFORM c59a2_fixture.frequency(o,4::smallint,'F1-D-foreign','2026-10-15T00:00:00.000000Z');
      UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=(o->>'user_id')::uuid;
    END IF;
    r:=c59a2_fixture.read_at(o);old:=c59a2_fixture.freeze_at(o,r,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'));
    PERFORM c59a2_fixture.ok(r->>'status'='ready' AND old->>'status'='frozen'
      AND old#>>'{target,planned_days}'='3','F1-D:unnecessary_frequency_does_not_block');
  END LOOP;
  FOREACH variant IN ARRAY ARRAY['unknown','older-local'] LOOP
    o:=c59a2_fixture.new_owner('F1-E-'||variant);p:=c59a2_fixture.plan(o,NULL,'F1-E-plan-absent');f:=NULL;
    IF variant='older-local' THEN f:=c59a2_fixture.frequency(o,4::smallint,'F1-E-local');END IF;
    UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=(o->>'user_id')::uuid;
    PERFORM c59a2_fixture.frequency(o,5::smallint,'F1-E-future','2026-10-15T00:00:00.000000Z');
    UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=(o->>'user_id')::uuid;
    PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o)='{"status":"unavailable","reason":"calendar_unsupported"}',
      'F1-E:necessary_foreign_pending_frequency_no_old_fallback');
    q:=jsonb_build_object('plan',jsonb_build_object('coverage','covered','source_version_id',p->'source_version_id','source_order',p->'source_order'),
      'frequency',CASE WHEN f IS NULL THEN jsonb_build_object('coverage','unknown') ELSE
      jsonb_build_object('coverage','covered','source_version_id',f->'source_version_id','source_order',f->'source_order') END);
    PERFORM c59a2_fixture.ok(private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
      'America/Sao_Paulo','2026-10-12',q,CASE WHEN f IS NULL THEN c59a2_fixture.proposal('absent',NULL,NULL)
        ELSE c59a2_fixture.proposal('informed_frequency',4::smallint,f->>'source_version_id') END,
      '2026-10-12T12:00Z')='{"status":"unavailable","reason":"calendar_unsupported"}' AND
      (SELECT count(*)=0 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
      'F1-E:freeze_same_pending_guard_zero_targets');
  END LOOP;
  FOREACH variant IN ARRAY ARRAY['local','foreign'] LOOP
    o:=c59a2_fixture.new_owner('F1-F-'||variant);
    IF variant='foreign' THEN UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=(o->>'user_id')::uuid;END IF;
    f:=c59a2_fixture.frequency(o,4::smallint,'F1-F-frequency');
    UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=(o->>'user_id')::uuid;
    PERFORM c59a2_fixture.ok(c59a2_fixture.read_at(o)='{"status":"unavailable","reason":"history_incomplete"}',
      'F1-F:unknown_plan_before_unnecessary_frequency_guard');
    q:=jsonb_build_object('plan',jsonb_build_object('coverage','unknown'),'frequency',
      jsonb_build_object('coverage','covered','source_version_id',f->'source_version_id','source_order',f->'source_order'));
    PERFORM c59a2_fixture.ok(private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
      'America/Sao_Paulo','2026-10-12',q,c59a2_fixture.proposal('informed_frequency',4::smallint,f->>'source_version_id'),
      '2026-10-12T12:00Z')='{"status":"unavailable","reason":"history_incomplete"}' AND
      (SELECT count(*)=0 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid),
      'F1-F:freeze_same_unknown_plan_guard_zero_targets');
  END LOOP;
  o:=c59a2_fixture.new_owner('F1-G');p:=c59a2_fixture.plan(o,3::smallint,'F1-G-current');
  f:=c59a2_fixture.plan(o,5::smallint,'F1-G-future','2026-10-15T00:00:00.000000Z','2099-12-31T00:00:00.000000Z');
  r:=c59a2_fixture.read_at(o);old:=c59a2_fixture.freeze_at(o,r,c59a2_fixture.proposal('accepted_plan',3::smallint,p->>'source_version_id'));
  r:=c59a2_fixture.read_at(o,'2026-10-19T12:00Z');
  PERFORM c59a2_fixture.ok(old->>'status'='frozen' AND old#>>'{target,planned_days}'='3'
    AND r->>'status'='ready' AND r#>'{context,plan,receipt}'=f
    AND r#>>'{context,frequency,coverage}'='unknown'
    AND c59a2_fixture.read_at(o)#>'{context,target}'=old->'target',
    'F1-G:future_finite_plan_selected_prior_target_retained');
  q:=jsonb_build_object('plan',jsonb_build_object('coverage','covered','source_version_id',f->'source_version_id','source_order',f->'source_order'),
    'frequency',jsonb_build_object('coverage','unknown'));
  r:=private.freeze_mobile_strength_week_target_at((o->>'user_id')::uuid,(o->>'generation')::uuid,
    'America/Sao_Paulo','2026-10-19',q,c59a2_fixture.proposal('accepted_plan',5::smallint,f->>'source_version_id'),'2026-10-19T12:00Z');
  PERFORM c59a2_fixture.ok(r->>'status'='frozen' AND r#>>'{target,source}'='accepted_plan'
    AND r#>>'{target,planned_days}'='5' AND r#>'{target,source_proof}'=q
    AND (SELECT count(*)=2 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid)
    AND c59a2_fixture.read_at(o)#>'{context,target}'=old->'target',
    'F1-G:future_finite_plan_freezes_prior_target_unchanged');
  -- F1-H is exactly W1 fallback-zero/both-absent, not another copied algorithm.
  PERFORM c59a2_fixture.ok((SELECT count(*)=2 FROM private.strength_week_targets t JOIN public.users u ON u.id=t.user_id
    WHERE u.name IN ('W1-fallback-zero','W1-both-absent') AND
      ((t.source='informed_frequency' AND t.planned_days=0) OR (t.source='absent' AND t.planned_days IS NULL))),
    'F1-H:same_zone_zero_and_explicit_absence_preserved');
END $f1$;

DO $w10$
DECLARE o jsonb;other_o jsonb;r jsonb;t jsonb;decoy jsonb;role_name text;table_name text;signature text;
  identity_sequence text;
BEGIN
  o:=c59a2_fixture.ready_case('W10-owner');other_o:=c59a2_fixture.ready_case('W10-decoy');
  r:=o->'read';t:=c59a2_fixture.freeze_at(o,r,o->'proposal');
  SELECT to_jsonb(u) INTO decoy FROM public.users u WHERE id=(other_o->>'user_id')::uuid;
  PERFORM c59a2_fixture.throws(format(
    'INSERT INTO private.strength_week_targets(target_id,user_id,generation,week_start,timezone_at_freeze,planned_days,source,plan_source_version_id,frequency_source_version_id,frozen_at) VALUES(gen_random_uuid(),%L::uuid,%L::uuid,%L::date,%L,3,%L,%L::uuid,NULL,clock_timestamp())',
    o->>'user_id',o->>'generation','2026-10-19','America/Sao_Paulo','accepted_plan',other_o#>>'{plan,source_version_id}'),
    '23503',NULL,'W10:foreign_composite_receipt_rejected');
  identity_sequence:=pg_get_serial_sequence('private.strength_week_source_versions','source_order');
  PERFORM c59a2_fixture.ok(identity_sequence IS NOT NULL,'W10:real_identity_sequence_setup');
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    PERFORM c59a2_fixture.ok(NOT has_sequence_privilege(role_name,identity_sequence,'USAGE,SELECT,UPDATE'),
      'W10:'||role_name||':no_direct_identity_sequence_privilege');
    FOREACH table_name IN ARRAY ARRAY['strength_week_scopes','strength_week_source_versions','strength_week_targets'] LOOP
      PERFORM c59a2_fixture.ok(NOT has_table_privilege(role_name,'private.'||table_name,'SELECT,INSERT,UPDATE,DELETE'),
        'W10:'||role_name||':no_direct_'||table_name);
      PERFORM c59a2_fixture.throws(format('SET LOCAL ROLE %I;SELECT * FROM private.%I LIMIT 1',role_name,table_name),
        '42501',NULL,'W10:'||role_name||':actual_direct_denial');
      PERFORM c59a2_fixture.ok((SELECT relrowsecurity FROM pg_class WHERE oid=('private.'||table_name)::regclass),
        'W10:RLS_enabled_'||table_name);
    END LOOP;
    FOR signature IN SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='private' AND p.proname IN('open_strength_week_scope','roll_strength_week_scope',
      'capture_strength_week_source','get_mobile_strength_week_context_at','freeze_mobile_strength_week_target_at',
      'capture_strength_week_source_at') LOOP
      PERFORM c59a2_fixture.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),
        'W10:'||role_name||':no_helper_EXECUTE');
      PERFORM c59a2_fixture.throws(format('SET LOCAL ROLE %I;SELECT private.get_mobile_strength_week_context_at(%L::uuid,%L::timestamptz)',
        role_name,o->>'user_id','2026-10-12T12:00Z'),'42501',NULL,'W10:'||role_name||':actual_time_seam_denial');
    END LOOP;
  END LOOP;
  FOR signature IN SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN('get_mobile_strength_week_context','freeze_mobile_strength_week_target') LOOP
    PERFORM c59a2_fixture.ok(has_function_privilege('service_role',signature,'EXECUTE')
      AND NOT has_function_privilege('anon',signature,'EXECUTE') AND NOT has_function_privilege('authenticated',signature,'EXECUTE')
      AND (SELECT prosecdef AND provolatile='v' AND proconfig=ARRAY['search_path=pg_catalog'] FROM pg_proc WHERE oid=signature::regprocedure),
      'W10:trusted_public_entry_metadata');
  END LOOP;
  PERFORM c59a2_fixture.ok((SELECT count(*)=2 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN('get_mobile_strength_week_context','freeze_mobile_strength_week_target')
      AND NOT ('timestamp with time zone'::regtype::oid=ANY(p.proargtypes::oid[]))),
    'W10:exactly_two_public_no_clock_overrides');
  DELETE FROM public.users WHERE id=(o->>'user_id')::uuid;
  PERFORM c59a2_fixture.ok((SELECT count(*)=0 FROM private.strength_week_scopes WHERE user_id=(o->>'user_id')::uuid)
    AND (SELECT count(*)=0 FROM private.strength_week_source_versions WHERE user_id=(o->>'user_id')::uuid)
    AND (SELECT count(*)=0 FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid)
    AND (SELECT to_jsonb(u)=decoy FROM public.users u WHERE id=(other_o->>'user_id')::uuid),
    'W10:real_account_delete_cascades_without_foreign_mutation');
END $w10$;

-- SQL isolation contract is a separate transaction because SET TRANSACTION must
-- precede queries. This suite's synthetic rows above are intentionally rolled back.
ROLLBACK;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59a2_fixture.throws(
  $q$SELECT public.freeze_mobile_strength_week_target('00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002','America/Sao_Paulo','2026-10-12',
  '{"plan":{"coverage":"unknown"},"frequency":{"coverage":"unknown"}}',
  '{"source":"absent","planned_days":null,"source_key":null}')$q$,
  '22023','mobile_strength_week_requires_read_committed','W10:wrong_isolation_exact_error');
ROLLBACK;
\echo C59A2_SEQUENTIAL_FINISHED_NOT_CONCURRENCY_PROOF

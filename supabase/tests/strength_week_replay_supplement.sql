-- Original-source replay regression after replacing the current training plan.
-- Requires fixtures/strength_week_fixture_support.sql in an exclusive local test DB.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $w9_plan_replay$
DECLARE o jsonb;first_receipt jsonb;replacement jsonb;replay jsonb;u uuid;g uuid;
BEGIN
  o:=c59a2_fixture.new_owner('W9-plan-replay-contract');
  u:=(o->>'user_id')::uuid;g:=(o->>'generation')::uuid;
  first_receipt:=c59a2_fixture.plan(o,3::smallint,'W9-plan-stable-key','2026-10-08T12:00:00.123456Z');
  replacement:=c59a2_fixture.plan(o,3::smallint,'W9-plan-replacement','2026-10-15T12:00:00.654321Z','2099-12-31T00:00:00.000000Z');
  PERFORM c59a2_fixture.ok((SELECT NOT active FROM public.training_plans
      WHERE id=(first_receipt->>'source_entity_id')::uuid)
    AND replacement->>'source_entity_id'<>first_receipt->>'source_entity_id',
    'W9:original_plan_replaced_setup');
  replay:=private.capture_strength_week_source_at(u,g,'accepted_plan','value',3::smallint,
    (first_receipt->>'source_entity_id')::uuid,NULL,'c59a2.fixture','W9-plan-stable-key','2026-10-22T12:00Z');
  PERFORM c59a2_fixture.ok(replay=first_receipt AND
    (SELECT count(*)=2 FROM private.strength_week_source_versions WHERE user_id=u),
    'W9:canonical_replay_precedes_current_plan_lookup_preserves_original');
  PERFORM c59a2_fixture.throws(format(
    'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,3::smallint,%L::uuid,NULL,%L,%L,%L::timestamptz)',
    u,g,'accepted_plan','value',replacement->>'source_entity_id','c59a2.fixture','W9-plan-stable-key','2026-10-22T12:00Z'),
    '40001','strength_week_operation_conflict','W9:replay_changed_plan_reference');
  PERFORM c59a2_fixture.throws(format(
    'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,3::smallint,%L::uuid,%L::timestamptz,%L,%L,%L::timestamptz)',
    u,g,'accepted_plan','value',first_receipt->>'source_entity_id','2099-12-31T00:00:00.000000Z',
    'c59a2.fixture','W9-plan-stable-key','2026-10-22T12:00Z'),
    '40001','strength_week_operation_conflict','W9:replay_changed_original_validity');
  PERFORM c59a2_fixture.throws(format(
    'SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,%L,%L,NULL,NULL,NULL,%L,%L,%L::timestamptz)',
    u,g,'accepted_plan','absent','c59a2.fixture','W9-plan-stable-key','2026-10-22T12:00Z'),
    '40001','strength_week_operation_conflict','W9:replay_changed_fact');
  PERFORM c59a2_fixture.ok((SELECT count(*)=2 FROM private.strength_week_source_versions WHERE user_id=u),
    'W9:changed_content_adds_zero_receipts');
END $w9_plan_replay$;
ROLLBACK;
